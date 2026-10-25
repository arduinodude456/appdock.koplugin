--[[--
Full browser for AppDock: runs NetSurf (JavaScript, real CSS layout) as a
background process that renders into a loopback-only VNC framebuffer, and shows
that framebuffer inside KOReader so KOReader handles e-ink refresh, colour and
touch.

Files expected on the device (installed by the release zip):
  /mnt/onboard/.adds/netsurf/bin/netsurf-fb
  /mnt/onboard/.adds/netsurf/cacert.pem, fonts/, share/netsurf/
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local Widget = require("ui/widget/widget")
local AppDockDialogs = require("appdock_dialogs")
local AppDockKeyboard = require("appdock_keyboard")
local InputDialog = AppDockDialogs.InputDialog
local ffi = require("ffi")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")

local Screen = Device.screen

-- ---------------------------------------------------------------- config ----
local NS_DIR = os.getenv("NETSURF_DIR") or "/mnt/onboard/.adds/netsurf"
local NS_BIN = NS_DIR .. "/bin/netsurf-fb"
local NS_LOG = NS_DIR .. "/netsurf.log"
local NS_HOME = NS_DIR .. "/home"
local VNC_HOST, VNC_PORT = "127.0.0.1", 5961 -- must match scripts/03-netsurf.sh
local TOOLBAR_PX = 48        -- NetSurf's own toolbar height (fb_toolbar_size)
local DEFAULT_ZOOM = 200     -- percent; 7" @ 300 ppi needs ~2x
-- JavaScript (Duktape). Modern sites can be slow with it, and while NetSurf runs a
-- script it does not serve the VNC connection (taps/keys get delayed or lost).
-- Set to false if pages freeze.
local ENABLE_JS = false
-- Every tap is sent as a double click (needed to focus text fields here). Side effect:
-- checkboxes toggle twice. Set to false for single clicks.
local DOUBLE_CLICK = true
local POLL_INTERVAL = 0.12
local CONNECT_TIMEOUT = 25

local function shq(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
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
    -- Encodings: Raw + RichCursor pseudo-encoding (-239). Without the latter,
    -- libvncserver paints its own default mouse cursor into the framebuffer and
    -- leaves it at the top-left corner (libnsfb never updates its position).
    -- With it the cursor is sent separately and we simply ignore it.
    self:send("\2\0" .. p16(2) .. p32(0) .. p32(-239))
    self.bb = Blitbuffer.new(self.w, self.h, Blitbuffer.TYPE_BBRGB32)
    self.bb:fill(Blitbuffer.COLOR_WHITE)
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
    -- bb.data is typed (ColorRGB32*) on RGB32 buffers; address it as raw bytes.
    local base = ffi.cast("uint8_t*", bb.data)
    for row = 0, h - 1 do
        if y + row >= self.h then break end
        local dst = base + (y + row) * stride + x * 4
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
            local enc = s32(rh, 9)
            if enc == 0 then
                self:blit(x, y, w, h, self:read(w * h * 4))
                x0 = x0 and math.min(x0, x) or x
                y0 = y0 and math.min(y0, y) or y
                x1 = x1 and math.max(x1, x + w) or (x + w)
                y1 = y1 and math.max(y1, y + h) or (y + h)
            elseif enc == -239 then -- RichCursor: pixels + 1-bit mask; x,y = hotspot. Ignored.
                self:read(w * h * 4 + math.floor((w + 7) / 8) * h)
            elseif enc == -240 then -- XCursor: 2 colours + bitmap + mask. Ignored.
                if w * h > 0 then self:read(6 + 2 * math.floor((w + 7) / 8) * h) end
            else
                error("rfb: unsupported encoding " .. tostring(enc))
            end
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

function RFB:pointer(mask, x, y)
    x = math.max(0, math.min(self.w - 1, math.floor(x)))
    y = math.max(0, math.min(self.h - 1, math.floor(y)))
    self:send("\5" .. string.char(mask) .. p16(x) .. p16(y))
end

function RFB:key(keysym, down)
    self:send("\4" .. string.char(down and 1 or 0) .. "\0\0" .. p32(keysym))
end

function RFB:tapKey(keysym)
    self:key(keysym, true)
    self:key(keysym, false)
end

local function codepoints(s)
    local out, i, n = {}, 1, #s
    local function cont(k) return (s:byte(k) or 0x80) - 0x80 end
    while i <= n do
        local c = s:byte(i)
        local cp, len
        if c < 0x80 then cp, len = c, 1
        elseif c < 0xE0 then cp, len = (c - 0xC0) * 64 + cont(i + 1), 2
        elseif c < 0xF0 then cp, len = ((c - 0xE0) * 64 + cont(i + 1)) * 64 + cont(i + 2), 3
        else cp, len = (((c - 0xF0) * 64 + cont(i + 1)) * 64 + cont(i + 2)) * 64 + cont(i + 3), 4 end
        out[#out + 1] = cp
        i = i + len
    end
    return out
end

function RFB:typeText(text)
    for _, cp in ipairs(codepoints(text)) do
        local sym
        if cp == 10 then sym = 0xFF0D
        elseif cp == 8 then sym = 0xFF08
        elseif cp < 0x100 then sym = cp
        else sym = 0x01000000 + cp end
        self:tapKey(sym)
    end
end

-- ---------------------------------------------------------- process mgmt ----
local Proc = { pid = nil }

function Proc.available()
    local f = io.open(NS_BIN, "rb")
    if not f then
        return false, _("NetSurf is not installed. Unzip netsurf-kobo.zip into the Kobo root (see README).")
    end
    f:close()
    return true
end

local function writeChoices(zoom)
    local dir = NS_HOME .. "/.netsurf"
    os.execute("mkdir -p " .. shq(dir))
    local f = io.open(dir .. "/Choices", "w")
    if not f then return end
    f:write(table.concat({
        "ca_bundle:" .. NS_DIR .. "/cacert.pem",
        "enable_javascript:" .. (ENABLE_JS and "1" or "0"),
        "scale:" .. tostring(zoom),
        "fb_toolbar_size:" .. TOOLBAR_PX,
        "fb_toolbar_layout:bfsrut",
        "cookie_file:" .. dir .. "/Cookies",
        "memory_cache_size:" .. (6 * 1024 * 1024),
    }, "\n") .. "\n")
    f:close()
end

function Proc.stop()
    os.execute("pkill -x netsurf-fb >/dev/null 2>&1")
    if Proc.pid then
        os.execute("kill -9 " .. tostring(Proc.pid) .. " >/dev/null 2>&1")
        Proc.pid = nil
    end
end

function Proc.start(width, height, url, zoom)
    Proc.stop()
    -- NetSurf's VNC server binds to 127.0.0.1; some e-readers leave "lo" down
    -- ("Cannot assign requested address"), so bring it up (needs root, harmless otherwise).
    os.execute("ifconfig lo 127.0.0.1 netmask 255.0.0.0 up >/dev/null 2>&1 || ip link set lo up >/dev/null 2>&1")
    writeChoices(zoom)
    local cmd = string.format(
        "(cd %s && HOME=%s NETSURFRES=%s LD_LIBRARY_PATH=%s${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH} exec ./bin/netsurf-fb -f vnc -b 32 -w %d -h %d %s) >%s 2>&1 & echo $!",
        shq(NS_DIR), shq(NS_HOME), shq(NS_DIR .. "/share/netsurf"), shq(NS_DIR .. "/lib"),
        width, height, shq(url), shq(NS_LOG))
    local p = io.popen(cmd)
    if not p then return false end
    local pid = p:read("*l")
    p:close()
    Proc.pid = tonumber(pid)
    return Proc.pid ~= nil
end

local function logTail()
    local f = io.open(NS_LOG, "rb")
    if not f then return "" end
    local size = f:seek("end")
    f:seek("set", math.max(0, size - 400))
    local data = f:read("*a") or ""
    f:close()
    return data
end

-- ------------------------------------------------------------------ URLs ----
local function toUrl(input)
    input = tostring(input or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if input == "" then return nil end
    if input:match("^https?://") then return input end
    if input:match("^[%a][%w+.-]*:") and not input:match("^[%w.-]+:%d+") then
        return nil, _("Only HTTP and HTTPS addresses are supported.")
    end
    if input:find("%s") or not input:find("%.") then
        return "https://duckduckgo.com/?q=" .. util.urlEncode(input)
    end
    return "https://" .. input
end

-- -------------------------------------------------------------- the view ----
local FBWidget = Widget:extend{ width = 0, height = 0, view = nil }

function FBWidget:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
end

function FBWidget:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    self.view:paintFramebuffer(bb, x, y)
end

local NetSurfView = InputContainer:extend{
    name = "NetSurfView",
    covers_fullscreen = true,
    url = "about:blank",
    zoom = DEFAULT_ZOOM,
}

function NetSurfView:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self.status_widget = TextWidget:new{
        text = _("Starting NetSurf…"),
        face = Font:getFace("cfont", 22),
        max_width = sw - 40,
    }
    self.toolbar = ButtonTable:new{
        width = sw,
        show_parent = self,
        buttons = {
            {
                { text = _("Back"), callback = function() self:navButton(0) end },
                { text = _("Forward"), callback = function() self:navButton(1) end },
                { text = _("Reload"), callback = function() self:navButton(3) end },
                { text = _("Address"), callback = function() self:showAddressDialog() end },
                { text = _("Type"), callback = function() self:showTypeDialog() end },
            },
            {
                { text = _("Zoom −"), callback = function() self:zoomStep("-") end },
                { text = _("Zoom +"), callback = function() self:zoomStep("+") end },
                { text = _("Up"), callback = function() self:scrollPage(-1) end },
                { text = _("Down"), callback = function() self:scrollPage(1) end },
                { text = _("Close"), callback = function() UIManager:close(self, "full") end },
            },
        },
    }
    self.toolbar_h = self.toolbar:getSize().h
    self.view_w, self.view_h = sw, sh - self.toolbar_h
    self.fbw = FBWidget:new{ width = self.view_w, height = self.view_h, view = self }
    self[1] = VerticalGroup:new{ align = "left", self.fbw, self.toolbar }
    self.ges_events = {
        TapView = { GestureRange:new{ ges = "tap", range = Geom:new{ x = 0, y = 0, w = self.view_w, h = self.view_h } } },
        SwipeView = { GestureRange:new{ ges = "swipe", range = Geom:new{ x = 0, y = 0, w = self.view_w, h = self.view_h } } },
        -- On e-ink a slightly longer touch becomes "hold", a quick second touch a
        -- "double_tap". Neither reached NetSurf before, which felt like lost taps.
        HoldReleaseView = { GestureRange:new{ ges = "hold_release", range = Geom:new{ x = 0, y = 0, w = self.view_w, h = self.view_h } } },
        DoubleTapView = { GestureRange:new{ ges = "double_tap", range = Geom:new{ x = 0, y = 0, w = self.view_w, h = self.view_h } } },
    }
    self:launch(self.url)
end

function NetSurfView:paintFramebuffer(bb, x, y)
    bb:paintRect(x, y, self.view_w, self.view_h, Blitbuffer.COLOR_WHITE)
    if self.rfb then
        bb:blitFrom(self.rfb.bb, x, y, 0, 0,
            math.min(self.view_w, self.rfb.w), math.min(self.view_h, self.rfb.h))
    else
        self.status_widget:paintTo(bb, x + 20, y + 20)
    end
end

function NetSurfView:launch(url)
    self.url = url
    if self.rfb then self.rfb:close(); self.rfb = nil end
    if not Proc.start(self.view_w, self.view_h, url, self.zoom) then
        self:fail(_("Could not start NetSurf."))
        return
    end
    self.connect_deadline = os.time() + CONNECT_TIMEOUT
    self.connect_cb = function() self:tryConnect() end
    UIManager:scheduleIn(0.6, self.connect_cb)
    UIManager:setDirty(self, "ui")
end

function NetSurfView:tryConnect()
    if self.closed then return end
    local rfb = RFB.connect(VNC_HOST, VNC_PORT)
    if rfb then
        self.rfb = rfb
        pcall(rfb.requestUpdate, rfb, false)
        self.poll_cb = function() self:pollRfb() end
        UIManager:scheduleIn(POLL_INTERVAL, self.poll_cb)
        return
    end
    if os.time() > self.connect_deadline then
        self:fail(_("NetSurf did not start.") .. "\n" .. logTail())
        return
    end
    UIManager:scheduleIn(0.5, self.connect_cb)
end

function NetSurfView:pollRfb()
    if self.closed or not self.rfb then return end
    -- Drain everything the server has queued (up to 8 messages per tick).
    local union, got = nil, false
    for _ = 1, 8 do
        local ok, res = pcall(self.rfb.poll, self.rfb)
        if not ok then
            self:fail(tostring(res))
            return
        end
        if res == nil then break end
        got = true
        if res then
            if union then
                union = { math.min(union[1], res[1]), math.min(union[2], res[2]),
                          math.max(union[3], res[3]), math.max(union[4], res[4]) }
            else
                union = res
            end
        end
    end
    -- Ask for the next update after ANY server message (also cursor-only ones),
    -- otherwise the server never sends anything again and the screen freezes.
    if got then pcall(self.rfb.requestUpdate, self.rfb, true) end
    if union then
        self.frame_count = (self.frame_count or 0) + 1
        local res = union
        if self.tap_wait and os.time() - self.tap_wait <= 3 then
            self.tap_wait = nil
            self:debugNote(string.format("Bild reagiert: %d,%d bis %d,%d", res[1], res[2], res[3], res[4]))
        end
        local w, h = res[3] - res[1], math.min(res[4], self.view_h) - res[2]
        if w > 0 and h > 0 then
            local big = (w * h) > (self.view_w * self.view_h * 0.5)
            UIManager:setDirty(self, big and "partial" or "ui", Geom:new{ x = res[1], y = res[2], w = w, h = h })
        end
    end
    UIManager:scheduleIn(POLL_INTERVAL, self.poll_cb)
end

function NetSurfView:fail(message)
    if self.closed then return end
    logger.warn("NetSurf: " .. tostring(message))
    UIManager:close(self, "full")
    UIManager:show(InfoMessage:new{ text = tostring(message), timeout = 8 })
end

function NetSurfView:rfbDo(fn)
    if not self.rfb then return end
    local ok, err = pcall(fn, self.rfb)
    if not ok then self:fail(tostring(err)) end
end

-- NetSurf's VNC surface only learns the pointer position from pure "move" events
-- (button presses carry no coordinates for it), and it handles roughly one input
-- event per main-loop pass. So a click is sent as: move, then press, then release,
-- spaced apart. A press that arrives together with the move leaves the cursor at
-- its old position (top left) and the click lands there.
local STEP = 0.15

-- All pointer events go through ONE queue. Before, every tap started its own timers,
-- so two taps (or a tap and a swipe) within ~1 s interleaved their move/press/release
-- events and NetSurf saw garbage. Now they are strictly sent one after another.
function NetSurfView:pointerSequence(seq)
    self.pq = self.pq or {}
    if #self.pq > 24 then return end -- user is hammering the screen: drop, don't pile up
    for _, e in ipairs(seq) do self.pq[#self.pq + 1] = e end
    if not self.pq_running then
        self.pq_running = true
        UIManager:scheduleIn(0, function() self:pumpPointer() end)
    end
end

function NetSurfView:pumpPointer()
    if self.closed then return end
    if self.keying then -- keyboard typing has priority, don't mix event streams
        UIManager:scheduleIn(0.1, function() self:pumpPointer() end)
        return
    end
    local e = table.remove(self.pq, 1)
    if not e then
        self.pq_running = false
        return
    end
    self:rfbDo(function(r) r:pointer(e[1], e[2], e[3]) end)
    UIManager:scheduleIn(e[4] or STEP, function() self:pumpPointer() end)
end

-- Every event is sent twice: NetSurf's VNC surface is known to drop input events
-- (every other one, see NetSurf bug #2242), so one of each pair gets through.
-- Pointer events are state based (button mask + position), so duplicates are harmless.
function NetSurfView:click(x, y, force)
    -- A click is still being sent (e.g. the extra tap/double_tap gesture of a user who
    -- tapped twice): ignore it, otherwise NetSurf sees 4 clicks and toggles things twice.
    if not force and self.pq_running and #(self.pq or {}) > 0 then return end
    local H, C = STEP, 0.1 -- H: after hover moves, C: between click events
    if DOUBLE_CLICK then
        -- One single tap of the user is sent as a complete double click, every event
        -- doubled (NetSurf drops about every other one) and fast enough to stay inside
        -- NetSurf's double-click time. A plain click only counts as hover for text fields.
        self:pointerSequence({
            { 0, x, y, H }, { 0, x, y, H },
            { 1, x, y, C }, { 1, x, y, C }, { 0, x, y, C }, { 0, x, y, C },
            { 1, x, y, C }, { 1, x, y, C }, { 0, x, y, C }, { 0, x, y, H },
        })
    else
        self:pointerSequence({
            { 0, x, y, H }, { 0, x, y, H },
            { 1, x, y, C }, { 1, x, y, C },
            { 0, x, y, C }, { 0, x, y, H },
        })
    end
    self.tap_wait = os.time()
    UIManager:scheduleIn(4, function()
        if not self.closed and self.tap_wait then
            self.tap_wait = nil
            self:debugNote("Bild blieb nach Tap unveraendert")
        end
    end)
end

-- Temporary diagnostics: shows what the view receives and sends.
local DEBUG_INPUT = false -- the popups overlay the page and cause extra e-ink refreshes
function NetSurfView:debugNote(text)
    if not DEBUG_INPUT then return end
    local ok, Notification = pcall(require, "ui/widget/notification")
    if ok and Notification then
        UIManager:show(Notification:new{ text = text, timeout = 1.5 })
    end
end

function NetSurfView:onTapView(_arg, ges)
    self:debugNote(string.format("tap %d,%d  rfb=%s  %s", ges.pos.x, ges.pos.y,
        self.rfb and "ok" or "nil", self.rfb and (self.rfb.w .. "x" .. self.rfb.h) or ""))
    self:click(ges.pos.x, ges.pos.y)
    return true
end

function NetSurfView:onHoldReleaseView(_arg, ges)
    self:click(ges.pos.x, ges.pos.y)
    return true
end

function NetSurfView:onDoubleTapView(_arg, ges)
    self:click(ges.pos.x, ges.pos.y)
    return true
end

function NetSurfView:wheel(clicks, down)
    local mask = down and 16 or 8 -- RFB buttons 5 / 4
    local x, y = math.floor(self.view_w / 2), math.floor(self.view_h / 2)
    local seq = { { 0, x, y } } -- hover over the page first
    for _ = 1, clicks do
        seq[#seq + 1] = { mask, x, y }
        seq[#seq + 1] = { 0, x, y }
    end
    self:pointerSequence(seq)
end

function NetSurfView:onSwipeView(_arg, ges)
    local dir = ges.direction
    self:debugNote("swipe " .. tostring(dir))
    if dir ~= "north" and dir ~= "south" then return true end
    local clicks = math.max(1, math.min(15, math.floor((ges.distance or 0) / Screen:scaleBySize(80))))
    self:wheel(clicks, dir == "north") -- finger up = content down
    return true
end

function NetSurfView:scrollPage(direction)
    self:rfbDo(function(r) r:tapKey(direction > 0 and 0xFF56 or 0xFF55) end) -- Page_Down / Page_Up
    self:wheel(6, direction > 0)
end

-- Clicks one of NetSurf's own toolbar buttons (0=back 1=forward 2=stop 3=reload).
function NetSurfView:navButton(index)
    local x, y = index * TOOLBAR_PX + TOOLBAR_PX / 2, TOOLBAR_PX / 2
    self:click(x, y)
end

function NetSurfView:zoomStep(sign)
    self:rfbDo(function(r)
        r:key(0xFFE3, true) -- Control_L
        r:tapKey(sign == "+" and 0x2B or 0x2D)
        r:key(0xFFE3, false)
    end)
end

-- Repaints the whole view after the on-screen keyboard / a dialog appeared or went
-- away (otherwise the keyboard ghost stays on the e-ink screen). Debounced, so
-- several triggers in a row cause only one refresh; "full" wins over "partial".
function NetSurfView:refreshAll(mode)
    if mode == "full" or self.refresh_mode == "full" then
        self.refresh_mode = "full"
    else
        self.refresh_mode = "partial"
    end
    if self.refresh_cb then UIManager:unschedule(self.refresh_cb) end
    self.refresh_cb = function()
        self.refresh_cb = nil
        local m = self.refresh_mode
        self.refresh_mode = nil
        if self.closed then return end
        UIManager:setDirty(self, m or "partial")
    end
    UIManager:scheduleIn(0.35, self.refresh_cb)
end

-- Hooks keyboard show/hide and closing of an InputDialog. Call AFTER
-- AppDockKeyboard.attach(dialog) so we wrap its versions of the handlers.
function NetSurfView:watchDialog(dialog)
    local view = self
    local function wrap(name, mode)
        local orig = dialog[name]
        dialog[name] = function(d, ...)
            local r
            if orig then r = orig(d, ...) end
            view:refreshAll(mode)
            return r
        end
    end
    wrap("onShowKeyboard", "partial")
    wrap("onCloseKeyboard", "partial")
    wrap("onCloseWidget", "full")
end

function NetSurfView:showAddressDialog()
    local dialog
    dialog = InputDialog:new{
        title = _("Open address or search"),
        input_hint = _("example.org or search terms"),
        input = "",
        buttons = { {
            { text = _("Cancel"), callback = function() UIManager:close(dialog); self:refreshAll("full") end },
            { text = _("Open"), is_enter_default = true, callback = function()
                local value = dialog:getInputText()
                UIManager:close(dialog)
                self:refreshAll("full")
                local url, err = toUrl(value)
                if not url then
                    if err then UIManager:show(InfoMessage:new{ text = err }) end
                    return
                end
                self:launch(url)
            end },
        } },
    }
    AppDockKeyboard.attach(dialog)
    self:watchDialog(dialog)
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- Types text into the focused field. NetSurf's VNC surface keeps only about one
-- pending input event and NetSurf is slow to redraw a 1264x1550 bitmap, so events
-- sent on a fixed timer overwrite each other and most characters get lost.
-- Therefore every key press waits until NetSurf has redrawn (the next pixel update
-- arrives) or a timeout passes before the next event is sent.
-- Capital letters get an explicit Shift because the VNC surface maps keysyms to
-- plain key codes.
local KEY_MIN_GAP = 0.12   -- minimum pause after a key press that triggers a redraw
local KEY_MAX_WAIT = 1.5   -- give up waiting for the redraw after this long
local KEY_RETRY_AFTER = 0.6 -- no redraw by then = NetSurf swallowed the key press: send it again
local MOD_GAP = 0.12       -- pause after Shift down/up

-- Characters that need Shift on a US keyboard -> the plain key that has to be pressed.
-- NetSurf's VNC surface only knows the PLAIN key codes (lowercase letters, digits,
-- unshifted punctuation). A keysym like 'W' or '?' is silently ignored, so we always
-- send the base key together with Shift.
local SHIFTED = {
    ["!"] = "1", ["@"] = "2", ["#"] = "3", ["$"] = "4", ["%"] = "5", ["^"] = "6",
    ["&"] = "7", ["*"] = "8", ["("] = "9", [")"] = "0", ["_"] = "-", ["+"] = "=",
    ["{"] = "[", ["}"] = "]", ["|"] = "\\", [":"] = ";", ['"'] = "'", ["<"] = ",",
    [">"] = ".", ["?"] = "/", ["~"] = "`",
}

function NetSurfView:typeText(text, with_enter)
    self.keyq = self.keyq or {}
    local n = 0
    local function add(sym, down) self.keyq[#self.keyq + 1] = { sym, down }; n = n + 1 end
    for _, cp in ipairs(codepoints(text)) do
        local sym, shift = nil, false
        if cp == 10 then sym = 0xFF0D
        elseif cp == 8 then sym = 0xFF08
        elseif cp >= 65 and cp <= 90 then sym, shift = cp + 32, true -- 'W' -> shift + 'w'
        elseif cp < 0x80 and SHIFTED[string.char(cp)] then
            sym, shift = SHIFTED[string.char(cp)]:byte(), true
        elseif cp < 0x100 then sym = cp
        else sym = 0x01000000 + cp end
        if shift then add(0xFFE1, true) end -- Shift_L
        add(sym, true)
        add(sym, false)
        if shift then add(0xFFE1, false) end
    end
    if with_enter then add(0xFF0D, true); add(0xFF0D, false) end
    self:debugNote(string.format("tippe %d Zeichen", #codepoints(text)))
    if not self.keying then
        self.keying = true
        UIManager:scheduleIn(0.25, function() self:pumpKeys() end) -- let the dialog/keyboard go away first
    end
end

function NetSurfView:pumpKeys()
    if self.closed then return end
    if self.pq_running and not self.key_sent then -- a tap is still being sent
        UIManager:scheduleIn(0.1, function() self:pumpKeys() end)
        return
    end
    local now = require("socket").gettime()
    local sent = self.key_sent
    if sent then
        local waited = now - sent.t
        local acked = (self.frame_count or 0) > sent.frames
        local done
        if sent.mod then
            done = waited >= MOD_GAP
        elseif sent.down then
            -- A normal key press makes NetSurf redraw (the character appears).
            if not acked and not sent.retried and waited >= KEY_RETRY_AFTER then
                sent.retried = true
                self:rfbDo(function(r) r:key(sent.sym, true) end)
            end
            done = (acked and waited >= KEY_MIN_GAP) or waited >= KEY_MAX_WAIT
        else
            done = waited >= 0.1
        end
        if not done then
            UIManager:scheduleIn(0.04, function() self:pumpKeys() end)
            return
        end
        self.key_sent = nil
    end
    local e = table.remove(self.keyq, 1)
    if not e then
        self.keying = false
        self:debugNote("Eingabe fertig")
        return
    end
    self:rfbDo(function(r) r:key(e[1], e[2]) end)
    self.key_sent = { t = now, frames = self.frame_count or 0, down = e[2],
                      mod = (e[1] == 0xFFE1), sym = e[1] }
    UIManager:scheduleIn(0.04, function() self:pumpKeys() end)
end

-- Tap a text field on the page first, then use this to type into it.
function NetSurfView:showTypeDialog()
    local dialog
    local function send(with_enter)
        local value = dialog:getInputText() or ""
        UIManager:close(dialog)
        self:refreshAll("full")
        self:typeText(value, with_enter)
    end
    dialog = InputDialog:new{
        title = _("Type into the selected field"),
        input = "",
        buttons = { {
            { text = _("Cancel"), callback = function() UIManager:close(dialog); self:refreshAll("full") end },
            { text = _("Type"), callback = function() send(false) end },
            { text = _("Type + Enter"), is_enter_default = true, callback = function() send(true) end },
        } },
    }
    AppDockKeyboard.attach(dialog)
    self:watchDialog(dialog)
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function NetSurfView:onCloseWidget()
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

-- Opens NetSurf full screen. `url` may be nil (blank page) or an http(s) URL.
function M.open(url)
    local ok, err = Proc.available()
    if not ok then
        UIManager:show(InfoMessage:new{ text = err })
        return false
    end
    local start_url = url and toUrl(url) or "about:blank"
    UIManager:show(NetSurfView:new{ url = start_url or "about:blank" })
    return true
end

M._test = { toUrl = toUrl, shq = shq, RFB = RFB, codepoints = codepoints }

return M
