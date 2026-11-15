--[[--
AppDock power-off animation, played by the "Exit" app before AppDock closes
and KOReader shows through again. Like a CRT switching off:

    1. the picture is squeezed from the top and bottom into a bright line,
    2. the line shrinks sideways into a dot,
    3. the dot goes out and the screen is black for a moment.

It is built on appdock_anim.lua, so it follows the same E-Ink rules (eight fast
colors, regional fast refresh, touch swallowed while it runs) and is skipped when
animations are off, in power saving mode, or when it cannot start. `finish` is
always called exactly once, whether the animation ran or not.
--]]--

local Anim = require("appdock_anim")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local UIManager = require("ui/uimanager")

local Screen = Device.screen

local Shutdown = {}

-- Share of the animation (0..1) used by each phase.
local SQUEEZE_END = 0.55
local SHRINK_END = 0.85

local function lerp(a, b, t) return a + (b - a) * t end
local function clamp01(t) return math.max(0, math.min(1, t)) end
local function round(v) return math.floor(v + .5) end

-- Paints frame `t` (0..1, linear) over the whole `rect`. `old` is the
-- snapshot of the screen as it was. Exposed for tests.
function Shutdown.drawFrame(bb, old, rect, t, line_color)
    local black = Blitbuffer.COLOR_BLACK
    local w, h = rect.w, rect.h
    local cx, cy = rect.x + math.floor(w / 2), rect.y + math.floor(h / 2)
    local line_h = math.max(2, Screen:scaleBySize(3))
    local dot = math.max(line_h + 2, Screen:scaleBySize(7))
    bb:paintRect(rect.x, rect.y, w, h, black)
    if t < SQUEEZE_END then
        local u = Anim.easeInOut(t / SQUEEZE_END)
        local band = round(lerp(h, line_h, u * u))
        if band <= line_h * 2 then
            bb:paintRect(rect.x, cy - math.floor(line_h / 2), w, line_h, line_color)
        else
            local offset = math.floor((h - band) / 2)
            Anim.blit(bb, old, rect.x, rect.y + offset, rect, 0, offset, w, band)
        end
    elseif t < SHRINK_END then
        local v = (t - SQUEEZE_END) / (SHRINK_END - SQUEEZE_END)
        local e = Anim.easeIn(v)
        local lw = math.max(dot, round(lerp(w, dot, e)))
        local lh = math.max(line_h, round(lerp(line_h, dot, e)))
        bb:paintRect(cx - math.floor(lw / 2), cy - math.floor(lh / 2), lw, lh, line_color)
    elseif t < 0.95 then
        local v = clamp01((t - SHRINK_END) / (0.95 - SHRINK_END))
        local size = math.max(2, round(lerp(dot, 2, v)))
        bb:paintRect(cx - math.floor(size / 2), cy - math.floor(size / 2), size, size, line_color)
    end
    -- t >= 0.95: plain black.
end

local function lineColor(appdock)
    if not Screen:isColorEnabled() then return Blitbuffer.COLOR_WHITE end
    local ok, cyber = pcall(function() return require("appdock_skin").isCyberActive(appdock) end)
    if ok and cyber then return Blitbuffer.ColorRGB32(0, 255, 255, 0xFF) end
    return Blitbuffer.COLOR_WHITE
end

function Shutdown.run(appdock, finish)
    local called = false
    local function once()
        if called then return end
        called = true
        finish()
    end
    if not Anim.enabled(appdock) then
        once()
        return false
    end
    local rect = Anim.screenRect()
    local old = Anim.capture(rect)
    if not old then
        once()
        return false
    end
    local color = lineColor(appdock)
    return Anim.run{
        region = rect,
        frames = 12,
        interval = 0.04,
        ease = function(t) return t end,
        draw = function(bb, t) Shutdown.drawFrame(bb, old, rect, t, color) end,
        -- The last frame is black; closing the overlay without a refresh keeps
        -- it from flashing before the full refresh below clears the screen.
        close_refresh = false,
        done = once,
        cleanup = function() Anim.free(old) end,
    }
end

return Shutdown
