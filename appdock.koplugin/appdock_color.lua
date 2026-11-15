--[[--
AppDock color helper.

One place for the rules that every color-aware painter follows:

  * Color detection: the screen counts as color when Screen:isColorScreen()
    OR Screen:isColorEnabled() says so (targets expose one or the other).
  * Color colors are built with Blitbuffer.colorFromString("#rrggbb").
  * Color rectangles are filled with bb:paintRectRGB32 (KOReader's RGB path);
    grayscale targets get a Color8 luminance value and plain bb:paintRect.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")

local Screen = Device.screen
local floor, max = math.floor, math.max

local Color = {}

local function call(method)
    if Screen and type(Screen[method]) == "function" then
        local ok, value = pcall(Screen[method], Screen)
        return ok and value == true
    end
    return false
end

--- True when the screen can show color (isColorScreen or isColorEnabled).
function Color.isColor()
    return call("isColorScreen") or call("isColorEnabled")
end

local cache = { [true] = {}, [false] = {} }

--- A Blitbuffer color for r, g, b (0-255). `color_mode` defaults to Color.isColor().
function Color.make(r, g, b, color_mode)
    if color_mode == nil then color_mode = Color.isColor() end
    color_mode = color_mode and true or false
    r, g, b = floor(r), floor(g), floor(b)
    local key = r * 65536 + g * 256 + b
    local store = cache[color_mode]
    local value = store[key]
    if value then return value end
    if color_mode then
        if type(Blitbuffer.colorFromString) == "function" then
            local ok, parsed = pcall(Blitbuffer.colorFromString, string.format("#%02x%02x%02x", r, g, b))
            if ok and parsed then value = parsed end
        end
        if not value and Blitbuffer.ColorRGB32 then
            local ok, parsed = pcall(Blitbuffer.ColorRGB32, r, g, b, 0xFF)
            if ok and parsed then value = parsed end
        end
    end
    if not value then
        local luma = floor((r * 299 + g * 587 + b * 114) / 1000)
        local ok, gray = pcall(Blitbuffer.Color8, luma)
        value = ok and gray or (luma > 127 and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK)
    end
    store[key] = value
    return value
end

--- Fills a rectangle. Color targets use paintRectRGB32.
function Color.paintRect(bb, x, y, w, h, color, color_mode)
    if w <= 0 or h <= 0 then return end
    if color_mode == nil then color_mode = Color.isColor() end
    if color_mode and type(bb.paintRectRGB32) == "function" then
        local ok = pcall(bb.paintRectRGB32, bb, x, y, w, h, color)
        if ok then return end
    end
    bb:paintRect(x, y, w, h, color)
end

--- Draws a rectangular border of thickness `t` inside (x, y, w, h).
function Color.paintBorder(bb, x, y, w, h, t, color, color_mode)
    t = max(1, floor(t or 1))
    Color.paintRect(bb, x, y, w, t, color, color_mode)
    Color.paintRect(bb, x, y + h - t, w, t, color, color_mode)
    Color.paintRect(bb, x, y + t, t, h - 2 * t, color, color_mode)
    Color.paintRect(bb, x + w - t, y + t, t, h - 2 * t, color, color_mode)
end

return Color
