--[[--
Gradient backgrounds for AppDock themes (9.6.0).

A theme (built-in, custom or an installed Store design) may carry a gradient:
    { angle = degrees, stops = { { pos = 0..1, hex = "#RRGGBB" }, ... } }
The angle follows CSS: 0 = towards the top, 90 = towards the right, 180 =
towards the bottom (a plain top-to-bottom fade).

The gradient is painted with a few dozen solid rectangles instead of per-pixel
writes: an axis-aligned gradient is a stack of bands, a diagonal one a coarse
grid of cells. That is fast enough to run on every repaint, needs no cached
bitmap and compresses perfectly on E-Ink (color panels dither flat areas
cleanly). Grayscale panels and high-contrast mode never receive a gradient;
Theme.getPalette() simply returns none there, so every caller falls back to the
flat background without any special handling.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local Widget = require("ui/widget/widget")

local Theme = require("appdock_theme")

local Gradient = {}

-- Bands along the gradient direction and cells across it. A step of ~1/56 of
-- the screen is below what the eye separates on a dithered color E-Ink panel.
local BANDS = 56
local CROSS_CELLS = 36

local function channels(hex)
    return tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16)
end

local function prepareStops(gradient)
    local stops = {}
    for index, stop in ipairs(gradient.stops) do
        local r, g, b = channels(stop.hex)
        stops[index] = { pos = stop.pos, r = r, g = g, b = b }
    end
    return stops
end

local function colorAt(stops, t)
    if t <= stops[1].pos then
        local first = stops[1]
        return first.r, first.g, first.b
    end
    for index = 2, #stops do
        local right = stops[index]
        if t <= right.pos then
            local left = stops[index - 1]
            local span = right.pos - left.pos
            local f = span > 0 and (t - left.pos) / span or 1
            return left.r + (right.r - left.r) * f, left.g + (right.g - left.g) * f, left.b + (right.b - left.b) * f
        end
    end
    local last = stops[#stops]
    return last.r, last.g, last.b
end

local function rgb(r, g, b)
    return Blitbuffer.ColorRGB32(math.floor(r + .5), math.floor(g + .5), math.floor(b + .5), 0xFF)
end

--- Paints `gradient` into the rectangle (x, y, w, h) of `bb`.
function Gradient.paint(bb, x, y, w, h, gradient)
    if type(gradient) ~= "table" or type(gradient.stops) ~= "table" or #gradient.stops < 2 or w <= 0 or h <= 0 then
        return false
    end
    local stops = prepareStops(gradient)
    local radians = math.rad(tonumber(gradient.angle) or 180)
    local dx, dy = math.sin(radians), -math.cos(radians)
    -- Round away float noise so exactly vertical / horizontal gradients stay
    -- a single column / row of bands.
    if math.abs(dx) < 1e-6 then dx = 0 end
    if math.abs(dy) < 1e-6 then dy = 0 end
    -- CSS gradient line length: the projection of the box onto the direction.
    local length = math.abs(w * dx) + math.abs(h * dy)
    if length <= 0 then return false end

    local columns = dx == 0 and 1 or (dy == 0 and BANDS or CROSS_CELLS)
    local rows = dy == 0 and 1 or (dx == 0 and BANDS or math.floor(CROSS_CELLS * h / math.max(1, w) + .5))
    columns = math.max(1, math.min(columns, w))
    rows = math.max(1, math.min(rows, h))
    if dx ~= 0 and dy ~= 0 then rows = math.max(rows, 24) end

    local cell_w, cell_h = w / columns, h / rows
    for row = 0, rows - 1 do
        local top = y + math.floor(row * cell_h)
        local bottom = y + math.floor((row + 1) * cell_h)
        if row == rows - 1 then bottom = y + h end
        local center_y = (row + .5) * cell_h - h / 2
        for column = 0, columns - 1 do
            local left = x + math.floor(column * cell_w)
            local right = x + math.floor((column + 1) * cell_w)
            if column == columns - 1 then right = x + w end
            local center_x = (column + .5) * cell_w - w / 2
            local t = .5 + (center_x * dx + center_y * dy) / length
            t = math.max(0, math.min(1, t))
            local r, g, b = colorAt(stops, t)
            bb:paintRect(left, top, right - left, bottom - top, rgb(r, g, b))
        end
    end
    return true
end

local GradientFill = Widget:extend{
    width = nil,
    height = nil,
    gradient = nil,
    dimen = nil,
}

function GradientFill:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
end

function GradientFill:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    Gradient.paint(bb, x, y, self.width, self.height, self.gradient)
end

--- A widget that paints `gradient` over width x height.
function Gradient.widget(width, height, gradient)
    return GradientFill:new{ width = width, height = height, gradient = gradient }
end

--- The gradient of the active theme, or nil (see the note at the top).
function Gradient.active(appdock)
    local ok, gradient = pcall(Theme.getGradient, appdock)
    return ok and gradient or nil
end

--- Full-size background for a screen: the gradient widget when the active
--- theme has one, otherwise `flat()`, which must return the usual flat fill.
function Gradient.background(width, height, flat, appdock)
    local gradient = Gradient.active(appdock)
    if gradient then
        local ok, widget = pcall(Gradient.widget, width, height, gradient)
        if ok and widget then return widget end
    end
    return flat()
end

Gradient._test = { colorAt = colorAt, prepareStops = prepareStops }

return Gradient
