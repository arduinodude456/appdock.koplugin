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

--- Paints `gradient` into a rounded rectangle (buttons, chips, cards).
--- Rows are painted in strips (single rows inside the rounded corners so the
--- curve stays smooth); each strip is one rect for a vertical gradient or a
--- short run of cells for other angles.
function Gradient.paintRounded(bb, x, y, w, h, radius, gradient)
    if type(gradient) ~= "table" or type(gradient.stops) ~= "table" or #gradient.stops < 2 or w <= 0 or h <= 0 then
        return false
    end
    radius = math.max(0, math.min(math.floor(tonumber(radius) or 0), math.floor(math.min(w, h) / 2)))
    if radius <= 1 then return Gradient.paint(bb, x, y, w, h, gradient) end
    local stops = prepareStops(gradient)
    local radians = math.rad(tonumber(gradient.angle) or 180)
    local dx, dy = math.sin(radians), -math.cos(radians)
    if math.abs(dx) < 1e-6 then dx = 0 end
    if math.abs(dy) < 1e-6 then dy = 0 end
    local length = math.abs(w * dx) + math.abs(h * dy)
    if length <= 0 then return false end
    local cells = dx == 0 and 1 or math.max(1, math.min(CROSS_CELLS, math.floor(w / 3)))
    local body_step = math.max(1, math.ceil((h - 2 * radius) / 40))
    local row = 0
    while row < h do
        local step = 1
        if row >= radius and row < h - radius then step = math.min(body_step, h - radius - row) end
        -- Horizontal inset of the rounded corner at the strip's vertical centre.
        local centre = row + step / 2
        local inset = 0
        if centre < radius then
            local d = radius - centre
            inset = radius - math.sqrt(math.max(0, radius * radius - d * d))
        elseif centre > h - radius then
            local d = centre - (h - radius)
            inset = radius - math.sqrt(math.max(0, radius * radius - d * d))
        end
        inset = math.floor(inset + .5)
        local span = w - 2 * inset
        if span > 0 then
            local center_y = centre - h / 2
            local count = math.max(1, math.min(cells, span))
            for column = 0, count - 1 do
                local left = inset + math.floor(column * span / count)
                local right = inset + math.floor((column + 1) * span / count)
                if column == count - 1 then right = inset + span end
                local center_x = (left + right) / 2 - w / 2
                local t = .5 + (center_x * dx + center_y * dy) / length
                t = math.max(0, math.min(1, t))
                local r, g, b = colorAt(stops, t)
                bb:paintRect(x + left, y + row, right - left, step, rgb(r, g, b))
            end
        end
        row = row + step
    end
    return true
end

--- Makes `frame` (a FrameContainer with a rounded `radius`) paint `gradient`
--- instead of its flat `background`. The border, content and tap handling of
--- the frame are untouched; the flat color is kept as the fallback if the
--- gradient cannot be painted. Returns the frame.
function Gradient.decorate(frame, gradient, radius)
    if type(frame) ~= "table" or type(gradient) ~= "table" then return frame end
    local flat = frame.background
    local original = frame.paintTo
    frame.paintTo = function(self, bb, x, y)
        local width = self.width or (self.dimen and self.dimen.w) or 0
        local height = self.height or (self.dimen and self.dimen.h) or 0
        local painted = false
        if width > 0 and height > 0 then
            local ok, result = pcall(Gradient.paintRounded, bb, x, y, width, height, radius or self.radius or 0, gradient)
            painted = ok and result == true
        end
        -- The frame itself paints the flat fallback only when the gradient failed.
        self.background = (not painted) and flat or nil
        local value = original(self, bb, x, y)
        self.background = flat
        return value
    end
    frame.background = nil
    return frame
end

--- Gradient of one color role of the active theme (see Theme.GRADIENT_ROLES).
function Gradient.role(appdock, role)
    local ok, gradient = pcall(Theme.getRoleGradient, appdock, role)
    return ok and gradient or nil
end

Gradient._test = { colorAt = colorAt, prepareStops = prepareStops }

return Gradient
