--[[--
Doom for AppDock: runs doomgeneric (see doom/doomgeneric_vnc.c) as a background
process that publishes its picture through a loopback-only VNC server, and shows
that picture inside KOReader so KOReader handles e-ink refresh, colour and touch.

Files expected on the device (installed by doom-kobo.zip):
  /mnt/onboard/.adds/doom/bin/doomgeneric-960   (and -640 for narrow screens)
  /mnt/onboard/.adds/doom/freedoom1.wad         (or your own doom.wad / doom1.wad / doom2.wad)

Usage from another AppDock file:
  local Doom = require("appdock_doom")
  Doom.open()
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local ffi = require("ffi")
local logger = require("logger")
local _ = require("gettext")

local Screen = Device.screen

-- ---------------------------------------------------------------- config ----
local DOOM_DIR = os.getenv("DOOM_DIR") or "/mnt/onboard/.adds/doom"
local DOOM_LOG = DOOM_DIR .. "/doom.log"
local DOOM_HOME = DOOM_DIR .. "/home"      -- working dir: default.cfg and savegames
local VNC_HOST, VNC_PORT = "127.0.0.1", 5962 -- must match scripts/03-doom.sh
local POLL_INTERVAL = 0.08
local CONNECT_TIMEOUT = 20
-- KOReader refresh mode for game frames: "ui" (default), "partial", "fast" (A2, ghosty,
-- bad colours on Kaleido screens but the quickest).
local REFRESH_MODE = os.getenv("DOOM_REFRESH") or "ui"
local WAD_CANDIDATES = {
    "doom2.wad", "doom.wad", "doom1.wad", "freedoom2.wad", "freedoom1.wad",
    "DOOM2.WAD", "DOOM.WAD", "DOOM1.WAD",
}

local function shq(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function fileExists(path)
    local f = io.open(path, "rb")
    if f then f:close(); return true end
    return false
end

-- ------------------------------------------------------------ RFB client ----
local function be16(s, i) local a, b = s:byte(i, i + 1); return a * 256 + b end
local function be32(s, i)
    local a, b, c, d = s:byte(i, i + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
end
local function s32(s, i)
    local v = be32(s, i)
    if v >= 2147483648 then v = v - 4294967296 end
    return v
end
local function p16(v) v = math.floor(v); return string.char(math.floor(v / 256) % 256, v % 256) end
local function p32(v)
    v = math.floor(v)
    return string.char(math.floor(v / 16777216) % 256, math.floor(v / 65536) % 256,
        math.floor(v / 256) % 256, v % 256)
end

local function bbStride(bb)
    local ok, v = pcall(function() return bb.stride end)
    if ok and v then return tonumber(v) end
    ok, v = pcall(function() return bb.pitch end)
    if ok and v then return tonumber(v) end
    return bb:getWidth() * 4
end

local RFB = {}
RFB.__index = RFB

function RFB:send(data)
    local i = 1
    while i <= #data do
        local sent, err, last = self.sock:send(data, i)
        if sent then
            i = sent + 1
        elseif last and last >= i then
            i = last + 1
        else
            error("rfb send: " .. tostring(err))
        end
    end
end

function RFB:read(n)
    if n == 0 then return "" end
    local parts, got = {}, 0
    while got < n do
        local data, err, partial = self.sock:receive(n - got)
        data = data or partial
        if data and #data > 0 then
            parts[#parts + 1] = data
            got = got + #data
        else
            error("rfb read: " .. tostring(err))
        end
    end
    return table.concat(parts)
end

function RFB:handshake()
    local ver = self:read(12)
    if not ver:match("^RFB 003%.%d%d%d\n$") then error("not an RFB server") end
    self:send("RFB 003.008\n")
    local n = self:read(1):byte()
    if n == 0 then error("rfb: server refused connection") end
    local types = self:read(n)
    local has_none = false
    for i = 1, n do if types:byte(i) == 1 then has_none = true end end
    if not has_none then error("rfb: server wants authentication") end
    self:send("\1")
    if be32(self:read(4), 1) ~= 0 then error("rfb: security handshake failed") end
    self:send("\1") -- shared session
    local init = self:read(24)
    self.w, self.h = be16(init, 1), be16(init, 3)
    self:read(be32(init, 21)) -- desktop name
    -- 32 bpp, depth 24, little endian, true colour, R in the lowest byte so the
    -- memory layout is R,G,B,pad like a KOReader RGB32 blitbuffer.
    self:send("\0\0\0\0" .. string.char(32, 24, 0, 1)
        .. p16(255) .. p16(255) .. p16(255) .. string.char(0, 8, 16) .. "\0\0\0")
    self:send("\2\0" .. p16(1) .. p32(0)) -- encodings: Raw only
    self.bb = Blitbuffer.new(self.w, self.h, Blitbuffer.TYPE_BBRGB32)
    self.bb:fill(Blitbuffer.COLOR_BLACK)
end

function RFB.connect(host, port)
    local socket = require("socket")
    local sock = socket.tcp()
    sock:settimeout(3)
    local ok, err = sock:connect(host, port)
    if not ok then
        sock:close()
        return nil, err
    end
    local self = setmetatable({ sock = sock }, RFB)
    local hs_ok, hs_err = pcall(self.handshake, self)
    if not hs_ok then
        sock:close()
        return nil, hs_err
    end
    return self
end

function RFB:close()
    if self.sock then pcall(self.sock.close, self.sock); self.sock = nil end
end

function RFB:requestUpdate(incremental)
    self:send("\3" .. string.char(incremental and 1 or 0)
        .. p16(0) .. p16(0) .. p16(self.w) .. p16(self.h))
end

function RFB:blit(x, y, w, h, data)
    local bb = self.bb
    local stride = bbStride(bb)
    local src = ffi.cast("const uint8_t*", data)
    for row = 0, h - 1 do
        if y + row >= self.h then break end
        local dst = bb.data + (y + row) * stride + x * 4
        ffi.copy(dst, src + row * w * 4, w * 4)
        for i = 0, w - 1 do dst[i * 4 + 3] = 255 end -- opaque alpha
    end
end

-- Returns nil (nothing pending), false (message handled, no pixels), or the
-- union rectangle {x0,y0,x1,y1} of changed pixels.
function RFB:poll()
    local socket = require("socket")
    local ready = socket.select({ self.sock }, nil, 0)
    if not ready or not ready[1] then return nil end
    local t = self:read(1):byte()
    if t == 0 then
        local n = be16(self:read(3), 2)
        local x0, y0, x1, y1
        for _ = 1, n do
            local rh = self:read(12)
            local x, y, w, h = be16(rh, 1), be16(rh, 3), be16(rh, 5), be16(rh, 7)
            if s32(rh, 9) ~= 0 then error("rfb: unsupported encoding") end
            self:blit(x, y, w, h, self:read(w * h * 4))
            x0 = x0 and math.min(x0, x) or x
            y0 = y0 and math.min(y0, y) or y
            x1 = x1 and math.max(x1, x + w) or (x + w)
            y1 = y1 and math.max(y1, y + h) or (y + h)
        end
        if x0 then return { x0, y0, x1, y1 } end
        return false
    elseif t == 2 then -- bell
        return false
    elseif t == 3 then -- server cut text
        self:read(be32(self:read(7), 4))
        return false
    end
    error("rfb: unexpected server message " .. tostring(t))
end

function RFB:key(keysym, down)
    self:send("\4" .. string.char(down and 1 or 0) .. "\0\0" .. p32(keysym))
end

-- ---------------------------------------------------------- process mgmt ----
local Proc = { pid = nil, exe = nil }

local function pickBinary()
    local width = Screen:getWidth()
    local order = width >= 960 and { "doomgeneric-960", "doomgeneric-640" }
        or { "doomgeneric-640", "doomgeneric-960" }
    for _, name in ipairs(order) do
        if fileExists(DOOM_DIR .. "/bin/" .. name) then return name end
    end
end

local function pickWad()
    for _, name in ipairs(WAD_CANDIDATES) do
        local p = DOOM_DIR .. "/" .. name
        if fileExists(p) then return p end
    end
end

function Proc.available()
    if not pickBinary() then
        return false, _("Doom is not installed. Unzip doom-kobo.zip into the Kobo root (see README).")
    end
    if not pickWad() then
        return false, _("No WAD found. Put doom.wad (or freedoom1.wad) into .adds/doom/.")
    end
    return true
end

function Proc.stop()
    if Proc.exe then os.execute("pkill -x " .. Proc.exe .. " >/dev/null 2>&1") end
    os.execute("pkill -x doomgeneric-960 >/dev/null 2>&1; pkill -x doomgeneric-640 >/dev/null 2>&1")
    if Proc.pid then
        os.execute("kill -9 " .. tostring(Proc.pid) .. " >/dev/null 2>&1")
        Proc.pid = nil
    end
end

function Proc.start()
    Proc.stop()
    local exe, wad = pickBinary(), pickWad()
    if not exe or not wad then return false end
    Proc.exe = exe
    -- The VNC server binds to 127.0.0.1; some e-readers leave "lo" down
    -- ("Cannot assign requested address"), so bring it up (needs root, harmless otherwise).
    os.execute("ifconfig lo 127.0.0.1 netmask 255.0.0.0 up >/dev/null 2>&1 || ip link set lo up >/dev/null 2>&1")
    os.execute("mkdir -p " .. shq(DOOM_HOME))
    local cmd = string.format(
        "(cd %s && LD_LIBRARY_PATH=%s${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH} exec %s -iwad %s) >%s 2>&1 & echo $!",
        shq(DOOM_HOME), shq(DOOM_DIR .. "/lib"), shq(DOOM_DIR .. "/bin/" .. exe), shq(wad), shq(DOOM_LOG))
    local p = io.popen(cmd)
    if not p then return false end
    local pid = p:read("*l")
    p:close()
    Proc.pid = tonumber(pid)
    return Proc.pid ~= nil
end

local function logTail()
    local f = io.open(DOOM_LOG, "rb")
    if not f then return "" end
    local size = f:seek("end")
    f:seek("set", math.max(0, size - 400))
    local data = f:read("*a") or ""
    f:close()
    return data
end

-- -------------------------------------------------------------- controls ----
-- X11 keysyms understood by doom/doomgeneric_vnc.c
local K = {
    Left = 0xFF51, Up = 0xFF52, Right = 0xFF53, Down = 0xFF54,
    Enter = 0xFF0D, Esc = 0xFF1B, Tab = 0xFF09,
    Ctrl = 0xFFE3, Shift = 0xFFE1, Space = 0x20,
    StrafeL = 0x2C, StrafeR = 0x2E, -- , and .
    F6 = 0xFFC3, F9 = 0xFFC6,
}
local function ch(c) return c:byte() end

-- Rows of buttons; every row is split evenly.  kind: nil = hold while touched,
-- "latch" = toggles, "close" = leaves the game.
local LAYOUT = {
    { { "Menu", K.Esc }, { "Enter", K.Enter }, { "Map", K.Tab }, { "Quit", nil, "close" } },
    { { "Strafe ←", K.StrafeL }, { "↑", K.Up }, { "Strafe →", K.StrafeR }, { "Fire", K.Ctrl } },
    { { "←", K.Left }, { "↓", K.Down }, { "→", K.Right }, { "Use", K.Space } },
    { { "1", ch("1") }, { "2", ch("2") }, { "3", ch("3") }, { "4", ch("4") },
      { "5", ch("5") }, { "6", ch("6") }, { "7", ch("7") } },
    { { "Run", K.Shift, "latch" }, { "Y", ch("y") }, { "N", ch("n") },
      { "Quicksave", K.F6 }, { "Quickload", K.F9 } },
}

-- -------------------------------------------------------------- the view ----
local DoomView = InputContainer:extend{
    name = "DoomView",
    covers_fullscreen = false,
}

function DoomView:init()
    local sw = self.width or Screen:getWidth()
    local sh = self.height or Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self.held = {}        -- button -> true while its key is down
    self.by_slot = {}     -- touch slot -> button
    self.last_touch = {}  -- button -> os.clock() of last "touch"
    self.status_widget = TextWidget:new{
        text = _("Starting Doom…"),
        face = Font:getFace("cfont", 22),
        max_width = sw - 40,
    }
    self.label_face = Font:getFace("cfont", 22)
    self.ges_events = {
        TouchPanel = { GestureRange:new{ ges = "touch", range = self.dimen } },
        ReleasePanel = { GestureRange:new{ ges = "release", range = self.dimen } },
        TapPanel = { GestureRange:new{ ges = "tap", range = self.dimen } },
    }
    if Device:hasKeys() then
        -- page-turn buttons: right = fire, left = use
        self.key_events = {
            PageFire = { { "RPgFwd" }, { "LPgFwd" }, event = "PageFire" },
            PageUse = { { "RPgBack" }, { "LPgBack" }, event = "PageUse" },
        }
    end
    self:layoutPanel()
    self:launch()
end

-- Computes the rectangle of every button below the game picture.
function DoomView:layoutPanel(game_h)
    local sw, sh = self.dimen.w, self.dimen.h
    self.game_h = game_h or 0
    self.buttons = {}
    local top = self.game_h
    local margin = Screen:scaleBySize(6)
    local avail = sh - top - margin
    if avail < 100 then return end
    local rows = #LAYOUT
    local row_h = math.min(math.floor(avail / rows), Screen:scaleBySize(120))
    local y = top + margin
    for _, row in ipairs(LAYOUT) do
        local cell_w = math.floor((sw - margin * (#row + 1)) / #row)
        for i, def in ipairs(row) do
            local label = def[1]
            self.buttons[#self.buttons + 1] = {
                label = label, key = def[2], kind = def[3],
                rect = Geom:new{ x = margin + (i - 1) * (cell_w + margin), y = y, w = cell_w, h = row_h - margin },
                text = TextWidget:new{ text = label, face = self.label_face, max_width = cell_w - 8 },
            }
        end
        y = y + row_h
    end
end

function DoomView:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_WHITE)
    if self.rfb then
        bb:blitFrom(self.rfb.bb, x + self.game_x, y, 0, 0,
            math.min(self.dimen.w, self.rfb.w), self.rfb.h)
        for _, b in ipairs(self.buttons) do
            local r = b.rect
            local active = self.held[b]
            bb:paintRect(x + r.x, y + r.y, r.w, r.h, Blitbuffer.COLOR_BLACK)
            bb:paintRect(x + r.x + 2, y + r.y + 2, r.w - 4, r.h - 4,
                active and Blitbuffer.COLOR_GRAY_4 or Blitbuffer.COLOR_WHITE)
            local ts = b.text:getSize()
            b.text:paintTo(bb, x + r.x + math.floor((r.w - ts.w) / 2), y + r.y + math.floor((r.h - ts.h) / 2))
        end
    else
        self.status_widget:paintTo(bb, x + 20, y + 20)
    end
end

function DoomView:launch()
    if self.rfb then self.rfb:close(); self.rfb = nil end
    if not Proc.start() then
        self:fail(_("Could not start Doom."))
        return
    end
    self.connect_deadline = os.time() + CONNECT_TIMEOUT
    self.connect_cb = function() self:tryConnect() end
    UIManager:scheduleIn(0.5, self.connect_cb)
    UIManager:setDirty(self, "ui")
end

function DoomView:tryConnect()
    if self.closed then return end
    local rfb = RFB.connect(VNC_HOST, VNC_PORT)
    if rfb then
        self.rfb = rfb
        self.game_x = math.max(0, math.floor((self.dimen.w - rfb.w) / 2))
        self:layoutPanel(rfb.h)
        pcall(rfb.requestUpdate, rfb, false)
        self.poll_cb = function() self:pollRfb() end
        UIManager:scheduleIn(POLL_INTERVAL, self.poll_cb)
        UIManager:setDirty(self, "full")
        return
    end
    if os.time() > self.connect_deadline then
        self:fail(_("Doom did not start.") .. "\n" .. logTail())
        return
    end
    UIManager:scheduleIn(0.4, self.connect_cb)
end

function DoomView:pollRfb()
    if self.closed or not self.rfb then return end
    local ok, res = pcall(self.rfb.poll, self.rfb)
    if not ok then
        -- Doom quit (menu "Quit game") or crashed.
        logger.warn("Doom: " .. tostring(res))
        self:fail(_("Doom exited.") .. "\n" .. logTail())
        return
    end
    if res then
        pcall(self.rfb.requestUpdate, self.rfb, true)
        local w, h = res[3] - res[1], res[4] - res[2]
        if w > 0 and h > 0 then
            UIManager:setDirty(self, REFRESH_MODE, Geom:new{ x = self.game_x + res[1], y = res[2], w = w, h = h })
        end
    end
    UIManager:scheduleIn(POLL_INTERVAL, self.poll_cb)
end

function DoomView:fail(message)
    if self.closed then return end
    UIManager:close(self, "full")
    UIManager:show(InfoMessage:new{ text = tostring(message), timeout = 6 })
end

function DoomView:sendKey(key, down)
    if not self.rfb then return end
    local ok, err = pcall(self.rfb.key, self.rfb, key, down)
    if not ok then self:fail(tostring(err)) end
end

-- ---------------------------------------------------------------- touch ----
function DoomView:buttonAt(pos)
    if not self.rfb then return nil end
    for _, b in ipairs(self.buttons) do
        if b.rect:contains(pos) then return b end
    end
end

function DoomView:press(b)
    if b.kind == "close" then
        UIManager:close(self, "full")
        return
    end
    if b.kind == "latch" then
        self.held[b] = not self.held[b] or nil
        self:sendKey(b.key, self.held[b] and true or false)
        UIManager:setDirty(self, "ui", Geom:new{ x = b.rect.x, y = b.rect.y, w = b.rect.w, h = b.rect.h })
        return
    end
    if self.held[b] then return end
    self.held[b] = true
    self:sendKey(b.key, true)
    -- safety net in case the "release" event never arrives
    b.timeout_cb = function() self:release(b) end
    UIManager:scheduleIn(2.5, b.timeout_cb)
end

function DoomView:release(b)
    if b.kind == "latch" or b.kind == "close" or not self.held[b] then return end
    self.held[b] = nil
    if b.timeout_cb then UIManager:unschedule(b.timeout_cb); b.timeout_cb = nil end
    self:sendKey(b.key, false)
end

function DoomView:pulse(b, seconds)
    self:press(b)
    UIManager:scheduleIn(seconds or 0.15, function() self:release(b) end)
end

function DoomView:onTouchPanel(_arg, ges)
    local b = self:buttonAt(ges.pos)
    if not b then return true end
    self.last_touch[b] = os.clock()
    self.by_slot[ges.slot or 0] = b
    self:press(b)
    return true
end

function DoomView:onReleasePanel(_arg, ges)
    local b = self.by_slot[ges.slot or 0]
    self.by_slot[ges.slot or 0] = nil
    if not b or not self.held[b] then b = ges.pos and self:buttonAt(ges.pos) end
    if b then self:release(b) end
    return true
end

-- Fallback for devices/KOReader versions that do not deliver touch/release:
-- a plain tap becomes a short key press.
function DoomView:onTapPanel(_arg, ges)
    local b = self:buttonAt(ges.pos)
    if not b or b.kind == "latch" or b.kind == "close" then return true end
    if os.clock() - (self.last_touch[b] or -10) > 1.0 then self:pulse(b, 0.2) end
    return true
end

function DoomView:pulseKey(key, seconds)
    self:sendKey(key, true)
    UIManager:scheduleIn(seconds or 0.15, function() self:sendKey(key, false) end)
end

function DoomView:onPageFire() self:pulseKey(K.Ctrl); return true end
function DoomView:onPageUse() self:pulseKey(K.Space); return true end

function DoomView:onCloseWidget()
    self.closed = true
    if self.connect_cb then UIManager:unschedule(self.connect_cb) end
    if self.poll_cb then UIManager:unschedule(self.poll_cb) end
    if self.rfb then self.rfb:close(); self.rfb = nil end
    Proc.stop()
    UIManager:setDirty(nil, "full")
end

-- ------------------------------------------------------------ public API ----
local M = {}

function M.available()
    return Proc.available()
end

function M.open()
    local ok, err = Proc.available()
    if not ok then
        UIManager:show(InfoMessage:new{ text = err })
        return false
    end
    UIManager:show(DoomView:new{})
    return true
end

-- AppDock's built-in DApp host supplies the assigned pane dimensions instead
-- of opening a top-level KOReader dialog.
function M.buildPane(_, context)
    local width = context and context.dimen and context.dimen.w or Screen:getWidth()
    local height = context and context.dimen and context.dimen.h or Screen:getHeight()
    return DoomView:new{ width = width, height = height }
end

function M.close()
    Proc.stop()
end

M._test = { RFB = RFB, shq = shq, LAYOUT = LAYOUT, DoomView = DoomView }

return M
