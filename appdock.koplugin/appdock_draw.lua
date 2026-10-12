--[[--
AppDock Draw: a layered pixel canvas for E-Ink and color readers.

The user interface follows a conventional paint program: a labeled tool strip
with the active tool highlighted, a color and brush row, the canvas, and an
action bar with the current tool state. Editing works the way a drawing app is
expected to work on a touch screen:

* a stroke starts with the finger press (`touch`), so the first segment is never
  lost,
* freehand tools paint continuously while the finger moves,
* shape tools preview the shape live and only commit it when the finger lifts,
* a tap paints a single dot (or, for the fill tool, floods the region),
* only the affected canvas region is repainted, which keeps strokes responsive.

Project files stay a compact binary format; no executable Lua is loaded.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local ffi = require("ffi")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local AppDockDialogs = require("appdock_dialogs")
local AppDockKeyboard = require("appdock_keyboard")
local Stylus = require("appdock_stylus")
local _ = require("gettext")

local Draw = {}
Draw.__index = Draw
local Screen = Device.screen
local MAGIC_V1 = "ADRAW1\0"
local MAGIC = "ADRAW2\0"
local save_sequence = 0
local MAX_HISTORY = 8
local Bayer = {
    { 0,48,12,60,3,51,15,63 }, { 32,16,44,28,35,19,47,31 },
    { 8,56,4,52,11,59,7,55 }, { 40,24,36,20,43,27,39,23 },
    { 2,50,14,62,1,49,13,61 }, { 34,18,46,30,33,19,47,31 },
    { 10,58,6,54,9,57,5,53 }, { 42,26,38,22,41,27,45,21 },
}
local palette = {
    {255,255,255}, {0,0,0}, {255,0,0}, {0,255,0}, {0,0,255},
}
Draw.palette = palette
local COLOR_NAMES = { _("White"), _("Black"), _("Red"), _("Green"), _("Blue") }
local TOOL_LABELS = {
    pen = _("Pen"), eraser = _("Eraser"), line = _("Line"),
    rect = _("Rectangle"), circle = _("Circle"), fill = _("Fill"),
}
Draw.brushSizes = { 1, 2, 4, 7 }

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function scale(v) return Screen:scaleBySize(v) end
local function copyPalette(source)
    local copied = {}
    for index, color in ipairs(source or palette) do
        copied[index] = { color[1], color[2], color[3] }
    end
    return copied
end
local function colorPalette(app) return app and app.palette or palette end
local function hasColorScreen()
    -- Match Minecraft: its color renderer uses isColorEnabled(). Also accept
    -- isColorScreen() so Paint still renders RGB on color hardware when the
    -- document-rendering preference is off.
    if type(Screen.isColorScreen) == "function" then
        local ok, enabled = pcall(Screen.isColorScreen, Screen)
        if ok and enabled == true then return true end
    end
    if type(Screen.isColorEnabled) == "function" then
        local ok, enabled = pcall(Screen.isColorEnabled, Screen)
        if ok and enabled == true then return true end
    end
    return false
end
local function safeScale(value)
    local ok, scaled = pcall(scale, value)
    scaled = ok and tonumber(scaled) or nil
    if not scaled or scaled ~= scaled or scaled == math.huge or scaled == -math.huge or scaled <= 0 then
        return math.max(1, math.floor(tonumber(value) or 1))
    end
    return math.max(1, math.floor(scaled + .5))
end
local function safeDimension(value, fallback, maximum)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge or value < 1 then value = fallback end
    return clamp(math.floor(value), 1, maximum or 4096)
end
local function screenMetric(method, field, fallback)
    local value
    if type(Screen[method]) == "function" then
        local ok, result = pcall(Screen[method], Screen)
        if ok then value = result end
    end
    return safeDimension(value or Screen[field], fallback)
end
local rgb_cache = {}
local function rgb(c, color_mode)
    if color_mode == nil then color_mode = hasColorScreen() end
    if color_mode then
        local key = c[1] * 65536 + c[2] * 256 + c[3]
        local color = rgb_cache[key]
        if not color then
            color = Blitbuffer.colorFromString(string.format("#%02x%02x%02x", c[1], c[2], c[3]))
            rgb_cache[key] = color
        end
        return color
    end
    local y = math.floor((c[1] * 299 + c[2] * 587 + c[3] * 114) / 1000)
    return y > 127 and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
end
local function paintColorRect(bb, x, y, w, h, color, color_mode)
    if color_mode == nil then color_mode = hasColorScreen() end
    -- KOReader's color E-Ink buffers require the RGB-specific API. paintRect()
    -- may reduce ColorRGB32 to luminance, leaving Paint monochrome while the
    -- serialized project still contains the original RGB values.
    if color_mode and type(bb.paintRectRGB32) == "function" then
        bb:paintRectRGB32(x, y, w, h, color)
    else
        bb:paintRect(x, y, w, h, color)
    end
end
local function empty(width, height)
    return { width = width, height = height, pixels = ffi.new("uint8_t[?]", width * height), empty = true }
end
local function setPixel(layer, x, y, color)
    if x < 0 or y < 0 or x >= layer.width or y >= layer.height then return end
    layer.pixels[y * layer.width + x] = color
    layer.empty = false
end

-- Sub-second wall clock for stroke refresh throttling. `ui/time` is KOReader's
-- monotonic source; os.time() is the coarse last resort.
local now_seconds
do
    local ok, Time = pcall(require, "ui/time")
    if ok and Time and Time.now and Time.to_s then
        local converted, probe = pcall(function() return Time.to_s(Time.now()) end)
        if converted and type(probe) == "number" then
            now_seconds = function() return Time.to_s(Time.now()) end
        end
    end
    if not now_seconds then
        local ok, socket = pcall(require, "socket")
        if ok and socket and socket.gettime then now_seconds = socket.gettime end
    end
    now_seconds = now_seconds or function() return os.time() end
end
local function monotonicNow()
    local ok, value = pcall(now_seconds)
    return ok and tonumber(value) or os.time()
end

-- Public deterministic threshold and legacy primary-color quantizer. The
-- project palette itself can also contain arbitrary RGB colors.
function Draw.ditherChannel(value, x, y)
    local t = Bayer[(y % 8)+1][(x % 8)+1] * 4 + 2
    return value > t and 255 or 0
end
function Draw.paletteIndex(r, g, b, x, y, enabled)
    if not enabled then
        return ((r*299 + g*587 + b*114) / 1000) >= 128 and 1 or 2
    end
    local rr, gg, bb = Draw.ditherChannel(r,x,y), Draw.ditherChannel(g,x,y), Draw.ditherChannel(b,x,y)
    if rr == 0 and gg == 0 and bb == 0 then return 2 end
    if rr == 255 and gg == 255 and bb == 255 then return 1 end
    if rr == 255 then return 3 end
    if gg == 255 then return 4 end
    return 5
end

function Draw.parseRGB(text)
    if type(text) ~= "string" then return nil end
    text = text:match("^%s*(.-)%s*$") or ""
    local hex = text:match("^#?(%x%x%x%x%x%x)$")
    if hex then
        return tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
    end
    local r, g, b = text:match("^(%d+)%s*[,;]%s*(%d+)%s*[,;]%s*(%d+)$")
    r, g, b = tonumber(r), tonumber(g), tonumber(b)
    if not r or not g or not b or r > 255 or g > 255 or b > 255 then return nil end
    return r, g, b
end

----------------------------------------------------------------
-- Icon painting
----------------------------------------------------------------

-- Small procedural glyphs keep the toolbar readable at launcher scale without
-- shipping image assets.
local function paintGlyph(bb, x, y, width, height, kind, ink)
    local size = math.max(6, math.min(width, height) - safeScale(10))
    local ox = x + math.floor((width - size) / 2)
    local oy = y + math.floor((height - size) / 2)
    local stroke = math.max(1, math.floor(size * 0.11))
    local thin = math.max(1, math.floor(size * 0.07))
    local function rect(px, py, w, h)
        bb:paintRect(math.floor(px), math.floor(py), math.max(1, math.floor(w)), math.max(1, math.floor(h)), ink)
    end
    local function line(x0, y0, x1, y1, thickness)
        thickness = thickness or stroke
        local steps = math.max(math.abs(x1 - x0), math.abs(y1 - y0))
        if steps < 1 then return rect(x0 - thickness / 2, y0 - thickness / 2, thickness, thickness) end
        for step = 0, steps do
            local px = x0 + (x1 - x0) * step / steps
            local py = y0 + (y1 - y0) * step / steps
            rect(px - thickness / 2, py - thickness / 2, thickness, thickness)
        end
    end
    local function hollow(px, py, w, h, thickness)
        thickness = thickness or stroke
        rect(px, py, w, thickness)
        rect(px, py + h - thickness, w, thickness)
        rect(px, py, thickness, h)
        rect(px + w - thickness, py, thickness, h)
    end
    local function disc(cx, cy, radius)
        for row = -radius, radius do
            local span = math.floor(math.sqrt(math.max(0, radius * radius - row * row)) + .5)
            rect(cx - span, cy + row, span * 2 + 1, 1)
        end
    end
    local function ring(cx, cy, radius, thickness)
        for step = 0, 48 do
            local angle = 2 * math.pi * step / 48
            rect(cx + math.cos(angle) * radius - thickness / 2,
                cy + math.sin(angle) * radius - thickness / 2, thickness, thickness)
        end
    end

    if kind == "pen" then
        line(ox + size * 0.22, oy + size * 0.78, ox + size * 0.72, oy + size * 0.28, stroke)
        line(ox + size * 0.30, oy + size * 0.86, ox + size * 0.80, oy + size * 0.36, thin)
        line(ox + size * 0.14, oy + size * 0.90, ox + size * 0.62, oy + size * 0.90, thin)
    elseif kind == "eraser" then
        line(ox + size * 0.30, oy + size * 0.24, ox + size * 0.74, oy + size * 0.68, stroke * 2)
        line(ox + size * 0.18, oy + size * 0.60, ox + size * 0.54, oy + size * 0.96, stroke)
        line(ox + size * 0.10, oy + size * 0.96, ox + size * 0.86, oy + size * 0.96, thin)
    elseif kind == "line" then
        line(ox + size * 0.18, oy + size * 0.80, ox + size * 0.82, oy + size * 0.20, stroke)
        disc(ox + size * 0.18, oy + size * 0.80, math.max(1, math.floor(thin)))
        disc(ox + size * 0.82, oy + size * 0.20, math.max(1, math.floor(thin)))
    elseif kind == "rect" then
        hollow(ox + size * 0.16, oy + size * 0.26, size * 0.68, size * 0.48, stroke)
    elseif kind == "circle" then
        ring(ox + size * 0.5, oy + size * 0.5, size * 0.32, stroke)
    elseif kind == "fill" then
        -- A tipped bucket: a trapezoid body with a drop falling from its lip.
        rect(ox + size * 0.30, oy + size * 0.22, size * 0.40, size * 0.06)
        for row = 0, math.floor(size * 0.34) do
            local inset = math.floor(row * 0.35)
            rect(ox + size * 0.22 + inset, oy + size * 0.30 + row, size * 0.56 - inset * 2, 1)
        end
        disc(ox + size * 0.74, oy + size * 0.80, math.max(1, math.floor(size * 0.10)))
        rect(ox + size * 0.74, oy + size * 0.62, thin, size * 0.14)
    elseif kind == "undo" or kind == "redo" then
        local direction = kind == "undo" and -1 or 1
        local cx, cy, radius = ox + size * 0.5, oy + size * 0.60, size * 0.30
        for step = 0, 24 do
            local angle = math.pi * step / 24
            local px = cx + direction * math.cos(angle) * radius
            local py = cy - math.sin(angle) * radius
            rect(px - thin / 2, py - thin / 2, thin, thin)
        end
        local tip_x = cx + direction * radius
        for row = 0, math.floor(size * 0.18) do
            rect(tip_x - thin, cy - size * 0.16 + row, thin * 2, 1)
        end
        rect(cx - radius, cy, radius * 2, thin)
    elseif kind == "refresh" then
        ring(ox + size * 0.5, oy + size * 0.5, size * 0.30, stroke)
        rect(ox + size * 0.50, oy + size * 0.10, size * 0.22, stroke)
        rect(ox + size * 0.62, oy + size * 0.10, stroke, size * 0.22)
    elseif kind == "trash" then
        rect(ox + size * 0.20, oy + size * 0.30, size * 0.60, size * 0.56)
        rect(ox + size * 0.14, oy + size * 0.22, size * 0.72, size * 0.08)
        rect(ox + size * 0.40, oy + size * 0.12, size * 0.20, size * 0.08)
    elseif kind == "save" then
        hollow(ox + size * 0.16, oy + size * 0.16, size * 0.68, size * 0.68, stroke)
        rect(ox + size * 0.32, oy + size * 0.20, size * 0.36, size * 0.24)
        rect(ox + size * 0.28, oy + size * 0.58, size * 0.44, size * 0.22)
    elseif kind == "open" then
        rect(ox + size * 0.14, oy + size * 0.34, size * 0.72, size * 0.48)
        rect(ox + size * 0.14, oy + size * 0.22, size * 0.34, size * 0.14)
        rect(ox + size * 0.14, oy + size * 0.48, size * 0.72, thin)
    elseif kind == "image" then
        hollow(ox + size * 0.12, oy + size * 0.18, size * 0.76, size * 0.64, stroke)
        disc(ox + size * 0.34, oy + size * 0.38, math.max(1, math.floor(size * 0.07)))
        line(ox + size * 0.22, oy + size * 0.74, ox + size * 0.50, oy + size * 0.48, thin)
        line(ox + size * 0.50, oy + size * 0.48, ox + size * 0.78, oy + size * 0.74, thin)
    elseif kind == "layer_add" then
        hollow(ox + size * 0.12, oy + size * 0.18, size * 0.56, size * 0.42, stroke)
        rect(ox + size * 0.62, oy + size * 0.56, size * 0.26, stroke)
        rect(ox + size * 0.72, oy + size * 0.46, stroke, size * 0.26)
    elseif kind == "layer_next" then
        hollow(ox + size * 0.12, oy + size * 0.18, size * 0.56, size * 0.42, stroke)
        line(ox + size * 0.62, oy + size * 0.70, ox + size * 0.88, oy + size * 0.70, stroke)
        line(ox + size * 0.76, oy + size * 0.60, ox + size * 0.88, oy + size * 0.70, thin)
        line(ox + size * 0.76, oy + size * 0.80, ox + size * 0.88, oy + size * 0.70, thin)
    elseif kind == "minus" then
        rect(ox + size * 0.26, oy + size * 0.46, size * 0.48, stroke)
    elseif kind == "plus" then
        rect(ox + size * 0.26, oy + size * 0.46, size * 0.48, stroke)
        rect(ox + size * 0.46, oy + size * 0.26, stroke, size * 0.48)
    elseif kind == "dot" then
        disc(ox + size * 0.5, oy + size * 0.5, math.max(1, math.floor(size * 0.22)))
    else
        hollow(ox + size * 0.16, oy + size * 0.16, size * 0.68, size * 0.68, stroke)
    end
end

----------------------------------------------------------------
-- Toolbar widgets
----------------------------------------------------------------

local ToolButton = InputContainer:extend{
    symbol = nil,
    label = nil,
    active = false,
    callback = nil,
    width = nil,
    height = nil,
    dimen = nil,
}

function ToolButton:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    if self.label and self.width >= safeScale(38) and self.height >= safeScale(28) then
        self.label_widget = TextWidget:new{
            text = self.label,
            face = Font:getFace("smallinfofont", safeScale(9)),
            max_width = math.max(1, self.width - safeScale(4)),
            padding = 0,
        }
    end
    self.ges_events = { TapTool = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function ToolButton:getSize() return self.dimen end

function ToolButton:setActive(active) self.active = active and true or false end

function ToolButton:paintTo(bb, x, y)
    local w, h = self.width, self.height
    local inset = math.max(1, safeScale(1))
    local background = self.active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_LIGHT_GRAY
    local ink = self.active and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
    bb:paintRect(x, y, w, h, background)
    -- A thin outline keeps the light-gray buttons visible on white panes.
    bb:paintRect(x, y, w, inset, Blitbuffer.COLOR_BLACK)
    bb:paintRect(x, y + h - inset, w, inset, Blitbuffer.COLOR_BLACK)
    bb:paintRect(x, y, inset, h, Blitbuffer.COLOR_BLACK)
    bb:paintRect(x + w - inset, y, inset, h, Blitbuffer.COLOR_BLACK)
    local label_height = self.label_widget and safeScale(12) or 0
    local icon_height = math.max(1, h - label_height)
    paintGlyph(bb, x, y, w, icon_height, self.symbol, ink)
    if self.label_widget then
        self.label_widget.fgcolor = ink
        local text_size = self.label_widget:getSize()
        self.label_widget:paintTo(bb,
            x + math.floor((w - text_size.w) / 2),
            y + icon_height + math.floor((label_height - text_size.h) / 2))
    end
    self.dimen.x, self.dimen.y, self.dimen.w, self.dimen.h = x, y, w, h
end

function ToolButton:onTapTool()
    if self.callback then self.callback() end
    return true
end

local ColorSwatch = InputContainer:extend{
    color_id = 1,
    active = false,
    callback = nil,
    width = nil,
    height = nil,
    dimen = nil,
}

function ColorSwatch:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.ges_events = { TapSwatch = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function ColorSwatch:getSize() return self.dimen end

function ColorSwatch:setActive(active) self.active = active and true or false end

function ColorSwatch:paintTo(bb, x, y)
    local w, h = self.width, self.height
    local colors = self.palette or palette
    local entry = colors[clamp(tonumber(self.color_id) or 1, 1, #colors)]
    local border = self.active and math.max(2, safeScale(2)) or math.max(1, safeScale(1))
    bb:paintRect(x, y, w, h, self.active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_LIGHT_GRAY)
    local color_mode = hasColorScreen()
    paintColorRect(bb, x + border, y + border, w - border * 2, h - border * 2,
        rgb(entry, color_mode), color_mode)
    if self.active then
        bb:paintRect(x + w - border * 3, y + border, border, border, Blitbuffer.COLOR_BLACK)
    end
    self.dimen.x, self.dimen.y, self.dimen.w, self.dimen.h = x, y, w, h
end

function ColorSwatch:onTapSwatch()
    if self.callback then self.callback() end
    return true
end

local Chip = InputContainer:extend{
    text = nil,
    symbol = nil,
    color = nil,
    active = false,
    callback = nil,
    width = nil,
    height = nil,
    dimen = nil,
}

function Chip:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.color_size = self.color and math.min(safeScale(18), math.max(1, self.width - safeScale(22))) or 0
    local text_width = math.max(1, self.width - safeScale(16)
        - (self.symbol and safeScale(16) or 0)
        - (self.color and self.color_size + safeScale(4) or 0))
    self.text_widget = TextWidget:new{
        text = tostring(self.text or ""),
        face = Font:getFace("smallinfofont", safeScale(12)),
        bold = true,
        max_width = text_width,
        padding = 0,
    }
    self.ges_events = { TapChip = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function Chip:getSize() return self.dimen end

function Chip:setActive(active) self.active = active and true or false end

function Chip:paintTo(bb, x, y)
    local w, h = self.width, self.height
    local inset = math.max(1, safeScale(1))
    local background = self.active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_LIGHT_GRAY
    local ink = self.active and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
    bb:paintRect(x, y, w, h, background)
    bb:paintRect(x, y, w, inset, Blitbuffer.COLOR_BLACK)
    bb:paintRect(x, y + h - inset, w, inset, Blitbuffer.COLOR_BLACK)
    bb:paintRect(x, y, inset, h, Blitbuffer.COLOR_BLACK)
    bb:paintRect(x + w - inset, y, inset, h, Blitbuffer.COLOR_BLACK)
    local icon_size = math.min(h - safeScale(10), safeScale(18))
    if self.symbol and icon_size > 4 then
        paintGlyph(bb, x + safeScale(4), y + math.floor((h - icon_size) / 2), icon_size, icon_size, self.symbol, ink)
    end
    if self.color and self.color_size > 0 then
        local color_x, color_y = x + safeScale(4), y + math.floor((h - self.color_size) / 2)
        bb:paintRect(color_x, color_y, self.color_size, self.color_size, Blitbuffer.COLOR_BLACK)
        if self.color_size > 2 then
            local color_mode = hasColorScreen()
            paintColorRect(bb, color_x + 1, color_y + 1, self.color_size - 2, self.color_size - 2,
                rgb(self.color, color_mode), color_mode)
        end
    end
    if self.text_widget then
        local size = self.text_widget:getSize()
        local text_x
        if self.symbol then
            text_x = x + safeScale(6) + icon_size
        elseif self.color then
            text_x = x + safeScale(4) + self.color_size + safeScale(4)
        else
            text_x = math.floor(x + (w - size.w) / 2)
        end
        self.text_widget:paintTo(bb, text_x, y + math.floor((h - size.h) / 2))
    end
    self.dimen.x, self.dimen.y, self.dimen.w, self.dimen.h = x, y, w, h
end

function Chip:onTapChip()
    if self.callback then self.callback() end
    return true
end

----------------------------------------------------------------
-- Canvas
----------------------------------------------------------------

local Canvas = InputContainer:extend{ app=nil, width=nil, height=nil, dimen=nil }

function Canvas:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.ges_events = {
        Paint = { GestureRange:new{ ges="pan", range=function() return self.dimen end } },
        PaintTap = { GestureRange:new{ ges="tap", range=function() return self.dimen end } },
        PaintRelease = { GestureRange:new{ ges="pan_release", range=function() return self.dimen end } },
        PaintTouch = { GestureRange:new{ ges="touch", range=function() return self.dimen end } },
    }
    self.last_refresh = 0
end

function Canvas:_point(ev)
    local p = ev and ev.pos
    if not p then return nil end
    local x = math.floor((p.x - (self.origin_x or 0)) * self.width / math.max(1, self.dimen.w))
    local y = math.floor((p.y - (self.origin_y or 0)) * self.height / math.max(1, self.dimen.h))
    return clamp(x, 0, self.width - 1), clamp(y, 0, self.height - 1), ev
end

function Canvas:_brushFor(ev)
    local app = self.app
    -- Keep the selected logical diameter. Scaling it down by the reduced-size
    -- canvas collapsed common presets to the same one-pixel stamp.
    local brush = math.max(1, math.floor((app.brush_size or 1) + .5))
    local pressure = ev and tonumber(ev.pressure)
    local stylus = ev and (ev.pointer_type == "stylus" or ev.pointer_type == "pen"
        or ev.tool == "stylus" or ev.tool == "pen" or ev.stylus == true)
    -- Touch pressure varies by device and may be a small positive value. Only
    -- apply pressure when the event explicitly identifies a pen.
    if stylus and pressure and pressure > 0 and app.pressure_enabled then
        brush = math.max(1, math.floor(brush * clamp(pressure, 0.1, 1) + .5))
    end
    if ev and (ev.marker_button == true or ev.stylus_button == true) then brush = math.max(brush, 5) end
    return brush
end

-- Kobo's stylus packets are delivered before KOReader turns them into generic
-- gestures. `appdock_stylus` forwards those packets here with pressure and
-- button state intact. Keep that stroke separate from the subsequent generic
-- touch/pan callbacks, otherwise the same pen sample would be committed twice.
function Canvas:_containsPoint(ev)
    local p = ev and ev.pos
    if not p or not self.origin_x or not self.origin_y then return false end
    return p.x >= self.origin_x and p.y >= self.origin_y
        and p.x < self.origin_x + self.dimen.w and p.y < self.origin_y + self.dimen.h
end

function Canvas:handleStylusSample(ev, tracking_id)
    if not self:_containsPoint(ev) then
        if self._stylus_tracking_id == tracking_id then self:finishStylus(tracking_id) end
        return false
    end
    if self._stylus_tracking_id ~= nil and self._stylus_tracking_id ~= tracking_id then
        self:finishStylus(self._stylus_tracking_id)
    end
    self._raw_stylus_active = true
    if self._stylus_tracking_id == nil then
        self._stylus_tracking_id = tracking_id
        return self:_begin(ev)
    end
    return self:_continue(ev)
end

function Canvas:finishStylus(tracking_id)
    if tracking_id ~= nil and self._stylus_tracking_id ~= tracking_id then return false end
    local was_raw_stylus = self._raw_stylus_active == true
    local app = self.app
    local stroke = app and app.stroke
    if stroke and (stroke.tool == "line" or stroke.tool == "rect" or stroke.tool == "circle") then
        stroke.snapshot = nil
    end
    if app then
        app.stroke = nil
        app.fill_gesture = nil
    end
    self._stylus_tracking_id = nil
    -- `feedEvent` forwards to KOReader after this callback. Keep a short
    -- one-turn guard so the matching generic tap/release cannot stamp the same
    -- stylus contact a second time; it clears even when KOReader emits no
    -- gesture callback for the release.
    if was_raw_stylus and UIManager.nextTick then
        self._ignore_gesture_after_stylus = true
        UIManager:nextTick(function()
            self._ignore_gesture_after_stylus = nil
            if self._stylus_tracking_id == nil then self._raw_stylus_active = nil end
        end)
    else
        self._raw_stylus_active = nil
    end
    if self.origin_x then self:_refreshStroke({ 0, 0, self.width - 1, self.height - 1 }, true) end
    return true
end

function Canvas:_colorFor(ev)
    local app = self.app
    if app.tool == "eraser" then return 1 end
    if ev and (ev.tool == "eraser" or ev.pointer_type == "eraser" or ev.eraser == true) then return 1 end
    return app.color
end

local function isShapeTool(tool)
    return tool == "line" or tool == "rect" or tool == "circle"
end

function Canvas:_paintShape(stroke, x, y, color, brush)
    local app = self.app
    local x0, y0 = stroke.x0, stroke.y0
    if stroke.tool == "line" then
        local dx, dy = x - x0, y - y0
        local n = math.max(math.abs(dx), math.abs(dy), 1)
        for i = 0, n do app:stamp(math.floor(x0 + dx * i / n + .5), math.floor(y0 + dy * i / n + .5), color, brush) end
    elseif stroke.tool == "rect" then
        for xx = math.min(x, x0), math.max(x, x0) do app:stamp(xx, y0, color, brush); app:stamp(xx, y, color, brush) end
        for yy = math.min(y, y0), math.max(y, y0) do app:stamp(x0, yy, color, brush); app:stamp(x, yy, color, brush) end
    else
        local radius = math.sqrt((x - x0) ^ 2 + (y - y0) ^ 2)
        local segments = math.max(16, math.floor(radius * 6))
        for i = 0, segments do
            local a = 2 * math.pi * i / segments
            app:stamp(math.floor(x0 + math.cos(a) * radius + .5), math.floor(y0 + math.sin(a) * radius + .5), color, brush)
        end
    end
end

-- Starts a stroke on finger down, so the first segment is never lost the way it
-- was when only `pan` events were handled.
function Canvas:_begin(ev)
    local x, y = self:_point(ev)
    if not x then return false end
    local app = self.app
    app:ensure()
    app:pushHistory()
    local brush = self:_brushFor(ev)
    local color = self:_colorFor(ev)
    local stroke = {
        tool = app.tool,
        x0 = x, y0 = y,
        last = { x, y },
        color = color,
        brush = brush,
        box = { x, y, x, y },
    }
    if isShapeTool(stroke.tool) then
        local layer = app.layers[app.active]
        if layer then
            local snapshot = ffi.new("uint8_t[?]", app.width * app.height)
            ffi.copy(snapshot, layer.pixels, app.width * app.height)
            stroke.snapshot = snapshot
            stroke.snapshot_layer = app.active
        end
    elseif stroke.tool == "fill" then
        app:floodFill(x, y, color)
        stroke.box = { 0, 0, app.width - 1, app.height - 1 }
        app.stroke = nil
        -- A panning finger must not re-flood the region for every touch sample.
        app.fill_gesture = true
        self:_refreshStroke(stroke.box)
        return true
    else
        app:stamp(x, y, color, brush)
    end
    app.stroke = stroke
    self:_refreshStroke(stroke.box)
    return true
end

function Canvas:_continue(ev, final)
    local app = self.app
    local stroke = app.stroke
    local x, y = self:_point(ev)
    if not x then return false end
    if app.fill_gesture then return true end
    if not stroke then
        -- A pan without a preceding touch (e.g. a gesture that started outside
        -- the canvas) still draws instead of being dropped.
        return self:_begin(ev)
    end
    local box = stroke.box
    local function extend(x0, y0, x1, y1)
        box[1] = math.min(box[1], x0); box[2] = math.min(box[2], y0)
        box[3] = math.max(box[3], x1); box[4] = math.max(box[4], y1)
    end
    -- Pressure can change during a contact. Recompute the brush for every raw
    -- stylus sample instead of freezing the width at pen-down.
    local brush = self:_brushFor(ev)
    if ev and (ev.pointer_type == "stylus" or ev.tool == "stylus" or ev.stylus == true) then
        stroke.brush = brush
    end
    local pad = math.max(1, math.floor(brush / 2) + 1)

    if isShapeTool(stroke.tool) then
        local layer = app.layers[stroke.snapshot_layer]
        if stroke.snapshot and layer then
            ffi.copy(layer.pixels, stroke.snapshot, app.width * app.height)
            layer.empty = false
        end
        extend(math.min(stroke.x0, x) - pad, math.min(stroke.y0, y) - pad,
            math.max(stroke.x0, x) + pad, math.max(stroke.y0, y) + pad)
        self:_paintShape(stroke, x, y, stroke.color, brush)
    else
        local previous = stroke.last
        extend(math.min(previous[1], x) - pad, math.min(previous[2], y) - pad,
            math.max(previous[1], x) + pad, math.max(previous[2], y) + pad)
        local dx, dy = x - previous[1], y - previous[2]
        local n = math.max(math.abs(dx), math.abs(dy), 1)
        for i = 0, n do
            app:stamp(math.floor(previous[1] + dx * i / n + .5), math.floor(previous[2] + dy * i / n + .5),
                stroke.color, brush)
        end
    end
    stroke.last = { x, y }
    self:_refreshStroke(box, final)
    if final then
        app.stroke = nil
        if isShapeTool(stroke.tool) then stroke.snapshot = nil end
    end
    return true
end

-- Paint changed pixels immediately and enqueue every dirty region. Styluses
-- produce more packets than fingers, so only the explicitly blocking repaint
-- is throttled; scheduling UI work from the input callback loses visible
-- intermediate states on some Kobo/KOReader combinations.
function Canvas:_refreshStroke(box, force)
    if not box or not self.origin_x then return end
    local app = self.app
    local x0 = clamp(box[1], 0, app.width - 1)
    local y0 = clamp(box[2], 0, app.height - 1)
    local x1 = clamp(box[3], 0, app.width - 1)
    local y1 = clamp(box[4], 0, app.height - 1)
    if x1 < x0 or y1 < y0 then return end
    local bb = Screen.bb
    if bb then self:paintRegionTo(bb, self.origin_x, self.origin_y, x0, y0, x1, y1) end
    if not UIManager.setDirty then return end
    local scale_x = self.dimen.w / self.width
    local scale_y = self.dimen.h / self.height
    local region = Geom:new{
        x = self.origin_x + math.floor(x0 * scale_x),
        y = self.origin_y + math.floor(y0 * scale_y),
        w = math.max(1, math.ceil((x1 - x0 + 1) * scale_x)),
        h = math.max(1, math.ceil((y1 - y0 + 1) * scale_y)),
    }
    -- setDirty is non-blocking and must happen for every sample, otherwise
    -- KOReader may coalesce away the tiny regions between two fast points.
    UIManager:setDirty(nil, "fast", region)
    local now = monotonicNow()
    if force or now - (self.last_refresh or 0) >= 0.04 then
        self.last_refresh = now
        if UIManager.forceRePaint then UIManager:forceRePaint() end
        -- Never wait for EPDC in the middle of a stylus contact. Do it only
        -- for the final sample, after the complete stroke is in the buffer.
        if force and UIManager.yieldToEPDC then UIManager:yieldToEPDC() end
    end
end

function Canvas:onPaint(_, ev)
    if self._raw_stylus_active then return true end
    return self:_continue(ev)
end

function Canvas:onPaintTouch(_, ev)
    if self._raw_stylus_active then return true end
    return self:_begin(ev)
end

function Canvas:onPaintTap(_, ev)
    if self._raw_stylus_active or self._ignore_gesture_after_stylus then
        self._raw_stylus_active = nil
        self._ignore_gesture_after_stylus = nil
        return true
    end
    local app = self.app
    app.stroke = nil
    app.fill_gesture = nil
    local x, y = self:_point(ev)
    if not x then return false end
    app:ensure()
    app:pushHistory()
    local brush = self:_brushFor(ev)
    local color = self:_colorFor(ev)
    if app.tool == "fill" then
        app:floodFill(x, y, color)
        self:_refreshStroke({ 0, 0, app.width - 1, app.height - 1 }, true)
    else
        app:stamp(x, y, color, brush)
        local pad = math.max(1, math.floor(brush / 2) + 1)
        self:_refreshStroke({ x - pad, y - pad, x + pad, y + pad }, true)
    end
    return true
end

function Canvas:onPaintRelease(_, ev)
    if self._raw_stylus_active then
        -- The public stylus callback supplies contact samples, but KOReader's
        -- generic pan_release is the reliable end-of-contact notification.
        -- Finish here so lifting and touching down elsewhere starts a new
        -- stroke instead of extending the previous one.
        self:finishStylus(self._stylus_tracking_id)
        return true
    end
    local app = self.app
    if ev and app.stroke then self:_continue(ev, true) end
    app.stroke = nil
    app.fill_gesture = nil
    self:_refreshStroke({ 0, 0, app.width - 1, app.height - 1 }, true)
    return true
end

-- Paints the given source-pixel rectangle into the framebuffer.
function Canvas:paintRegionTo(bb, x, y, sx0, sy0, sx1, sy1)
    local app = self.app
    local layers = app.layers
    local color_mode = hasColorScreen()
    sx0 = clamp(sx0, 0, self.width - 1)
    sx1 = clamp(sx1, 0, self.width - 1)
    sy0 = clamp(sy0, 0, self.height - 1)
    sy1 = clamp(sy1, 0, self.height - 1)
    local row_height = math.max(1, math.ceil(self.dimen.h / self.height))
    for py = sy0, sy1 do
        -- Keep a palette index alongside the BlitBuffer color. On color devices
        -- ColorRGB32 is FFI cdata; comparing it to the nil sentinel at the end of
        -- a scanline invokes its __eq metamethod with a missing self argument and
        -- crashes Draw before the first frame is displayed.
        local run_id, run_color, run_start
        for px = sx0, sx1 + 1 do
            local color_id
            if px <= sx1 then
                for li = #layers, 1, -1 do
                    local layer = layers[li]
                    if not layer.empty then
                        local value = layer.pixels[py * self.width + px]
                        if value and value ~= 0 then color_id = value; break end
                    end
                end
                color_id = color_id or 1
            end
            local entry = color_id and colorPalette(app)[color_id] or nil
            local value = entry and rgb(entry, color_mode)
            if px == sx0 then
                run_id, run_color, run_start = color_id, value, px
            elseif color_id ~= run_id then
                local dx = x + math.floor(run_start * self.dimen.w / self.width)
                local ex = x + math.floor(px * self.dimen.w / self.width)
                paintColorRect(bb, dx, y + math.floor(py * self.dimen.h / self.height),
                    math.max(1, ex - dx), row_height, run_color, color_mode)
                run_id, run_color, run_start = color_id, value, px
            end
        end
    end
end

function Canvas:paintTo(bb, x, y)
    self.origin_x, self.origin_y = x, y
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_WHITE)
    self:paintRegionTo(bb, x, y, 0, 0, self.width - 1, self.height - 1)
end

function Canvas:refreshFast()
    if not self.origin_x or not UIManager.setDirty then return end
    if UIManager.widgetRepaint then UIManager:widgetRepaint(self, self.origin_x, self.origin_y) end
    UIManager:setDirty(nil, "fast", Geom:new{ x = self.origin_x, y = self.origin_y, w = self.dimen.w, h = self.dimen.h })
    if UIManager.forceRePaint then UIManager:forceRePaint() end
    if UIManager.yieldToEPDC then UIManager:yieldToEPDC() end
end

local function u16(n) return string.char(n%256,math.floor(n/256)%256) end

function Draw:new()
    return setmetatable({
        layers = {}, active = 1, color = 2, tool = "pen", brush_size = 2,
        color_dither = false, pressure_enabled = true,
        palette = copyPalette(palette),
        history = {}, redo_stack = {},
    }, self)
end

function Draw:ensure()
    self.palette = self.palette or copyPalette(palette)
    if #self.layers==0 then
        local size
        if Screen.getSize then
            local ok, result = pcall(Screen.getSize, Screen)
            if ok and type(result) == "table" then size = result end
        end
        local screen_w = safeDimension(size and size.w, screenMetric("getWidth", "width", 600))
        local screen_h = safeDimension(size and size.h, screenMetric("getHeight", "height", 800))
        -- Some device adapters return zero or nil for small scale requests
        -- during early display initialization. Never use such a value as a
        -- divisor or FFI allocation input; Draw must still open with a bounded
        -- fallback canvas.
        local step = safeScale(2)
        local w=clamp(math.floor((screen_w-safeScale(24))/step),64,480)
        local h=clamp(math.floor((screen_h-safeScale(180))/step),64,640)
        self.width,self.height=w,h
        local base=ffi.new("uint8_t[?]",w*h); ffi.fill(base,w*h,1); self.layers={{name=_('Layer 1'),width=w,height=h,pixels=base,empty=true}}
    end
    self.history = self.history or {}
    self.redo_stack = self.redo_stack or {}
end

function Draw:layer()
    return self.layers[self.active]
end

function Draw:setRGBColor(r, g, b)
    r, g, b = tonumber(r), tonumber(g), tonumber(b)
    if not r or not g or not b or r < 0 or g < 0 or b < 0 or r > 255 or g > 255 or b > 255 then
        return nil, _("RGB channels must be between 0 and 255.")
    end
    r, g, b = math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5)
    self.palette = self.palette or copyPalette(palette)
    for index, color in ipairs(self.palette) do
        if color[1] == r and color[2] == g and color[3] == b then
            self.color = index
            return index
        end
    end
    if #self.palette >= 255 then return nil, _("The drawing already contains 255 distinct colors.") end
    self.palette[#self.palette + 1] = { r, g, b }
    self.color = #self.palette
    return self.color
end

function Draw:stamp(x,y,color_id,radius)
    local layer=self.layers[self.active]; if not layer then return end
    local diameter=math.max(1,math.floor((tonumber(radius) or 1)+.5))
    local first=-math.floor(diameter/2)
    local last=first+diameter-1
    local center=(first+last)/2
    local radius2=(diameter/2)^2
    for yy=y+first,y+last do for xx=x+first,x+last do
        if (xx-x-center)^2+(yy-y-center)^2 <= radius2 then
            local pixel_color=color_id
            if self.color_dither and color_id>=3 and color_id<=5 then
                pixel_color=Draw.ditherChannel(140,xx,yy)==255 and color_id or 1
            end
            setPixel(layer,xx,yy,pixel_color)
        end
    end end
end

function Draw:floodFill(x,y,color_id)
    local layer=self.layers[self.active]; if not layer then return end
    local start=y*self.width+x; local target=layer.pixels[start]
    if target==color_id then return end
    local data=ffi.new("uint8_t[?]",self.width*self.height); ffi.copy(data,layer.pixels,self.width*self.height); local queue={start}; local head=1; data[start]=color_id
    while head<=#queue and head<=self.width*self.height do
        local at=queue[head]; head=head+1; local xx=(at-1)%self.width
        for _,n in ipairs({at-1,at+1,at-self.width,at+self.width}) do
            if n>=1 and n<=self.width*self.height and (n~=at-1 or xx>0) and (n~=at+1 or xx<self.width-1) and data[n]==target then
                data[n]=color_id; queue[#queue+1]=n
            end
        end
    end
    layer.pixels=data
    layer.empty=false
end

function Draw:addLayer()
    if #self.layers>=6 then return false end
    self.layers[#self.layers+1]={name=_("Layer ")..tostring(#self.layers+1),width=self.width,height=self.height,pixels=ffi.new("uint8_t[?]",self.width*self.height),empty=true}
    self.active=#self.layers; return true
end

function Draw:nextLayer()
    if #self.layers>0 then self.active=self.active%#self.layers+1 end
end

function Draw:setTool(tool)
    if not TOOL_LABELS[tool] then return false end
    self.tool = tool
    return true
end

function Draw:cycleBrush(delta)
    local sizes = Draw.brushSizes
    local index = 1
    for position, size in ipairs(sizes) do
        if size == self.brush_size then index = position break end
    end
    index = clamp(index + (delta or 1), 1, #sizes)
    self.brush_size = sizes[index]
    return self.brush_size
end

function Draw:clear()
    local layer = self:layer()
    if not layer then return false end
    self:pushHistory()
    ffi.fill(layer.pixels, self.width * self.height, 1)
    layer.empty = true
    return true
end

----------------------------------------------------------------
-- Undo/redo
----------------------------------------------------------------

local function snapshot(layer, width, height)
    local bytes = ffi.new("uint8_t[?]", width * height)
    ffi.copy(bytes, layer.pixels, width * height)
    return bytes
end

function Draw:pushHistory()
    self:ensure()
    local layer = self:layer()
    if not layer then return false end
    self.history[#self.history+1] = {
        layer = self.active,
        pixels = snapshot(layer, self.width, self.height),
        width = self.width,
        height = self.height,
    }
    while #self.history > MAX_HISTORY do table.remove(self.history, 1) end
    -- A fresh edit drops the redo branch, exactly like a paint program.
    self.redo_stack = {}
    return true
end

function Draw:undo()
    self:ensure()
    local entry = table.remove(self.history)
    if not entry then return false end
    local layer = self.layers[entry.layer]
    if not layer then return false end
    self.redo_stack[#self.redo_stack+1] = {
        layer = entry.layer,
        pixels = snapshot(layer, self.width, self.height),
        width = self.width,
        height = self.height,
    }
    ffi.copy(layer.pixels, entry.pixels, self.width * self.height)
    layer.empty = false
    return true
end

function Draw:redo()
    self:ensure()
    local entry = table.remove(self.redo_stack)
    if not entry then return false end
    local layer = self.layers[entry.layer]
    if not layer then return false end
    self.history[#self.history+1] = {
        layer = entry.layer,
        pixels = snapshot(layer, self.width, self.height),
        width = self.width,
        height = self.height,
    }
    ffi.copy(layer.pixels, entry.pixels, self.width * self.height)
    layer.empty = false
    return true
end

function Draw:statusText()
    local label = TOOL_LABELS[self.tool] or _("Pen")
    local color_id = clamp(self.color or 1, 1, #(self.palette or palette))
    local color_name = COLOR_NAMES[color_id]
    if not color_name then
        local color = colorPalette(self)[color_id] or palette[1]
        color_name = string.format("RGB #%02X%02X%02X", color[1], color[2], color[3])
    end
    return string.format("%s · %d px · %s · %s", label, self.brush_size or 1,
        color_name,
        string.format(_("Layer %d/%d"), self.active or 1, #self.layers))
end

----------------------------------------------------------------
-- Project files
----------------------------------------------------------------

function Draw:projectBytes()
    self:ensure()
    local selected_color = clamp(self.color or 1, 1, #self.palette)
    local out={MAGIC,u16(self.width),u16(self.height),string.char(#self.layers,self.active,#self.palette,selected_color)}
    for _, color in ipairs(self.palette) do
        out[#out+1] = string.char(color[1], color[2], color[3])
    end
    for _,layer in ipairs(self.layers) do out[#out+1]=ffi.string(layer.pixels,self.width*self.height) end
    return table.concat(out)
end

function Draw:loadBytes(bytes)
    if type(bytes)~="string" or #bytes < #MAGIC_V1 + 6 then return nil,_('Not an AppDock Draw project.') end
    local version2 = bytes:sub(1,#MAGIC) == MAGIC
    if not version2 and bytes:sub(1,#MAGIC_V1) ~= MAGIC_V1 then return nil,_('Not an AppDock Draw project.') end
    local i=#MAGIC+1; local w=bytes:byte(i)+(bytes:byte(i+1) or 0)*256; i=i+2
    local h=bytes:byte(i)+(bytes:byte(i+1) or 0)*256; i=i+2
    local count=bytes:byte(i); local active=bytes:byte(i+1)
    local palette_count, selected_color, loaded_palette
    if version2 then
        palette_count, selected_color = bytes:byte(i+2), bytes:byte(i+3)
        i = i + 4
        if not palette_count or palette_count < #palette or palette_count > 255
            or not selected_color or selected_color < 1 or selected_color > palette_count then
            return nil,_('The drawing file has an invalid color palette.')
        end
        loaded_palette = {}
        for color_id = 1, palette_count do
            local r, g, b = bytes:byte(i, i + 2)
            if not r or not g or not b then return nil,_('The drawing file is damaged or too large.') end
            loaded_palette[color_id] = { r, g, b }
            i = i + 3
        end
    else
        i = i + 2
        loaded_palette, selected_color = copyPalette(palette), 2
        palette_count = #loaded_palette
    end
    if w<1 or h<1 or w>480 or h>640 or not count or count<1 or count>6 or not active or active<1 or active>count or #bytes-i+1~=w*h*count then return nil,_('The drawing file is damaged or too large.') end
    local layers={}
    for n=1,count do
        local raw=bytes:sub(i,i+w*h-1)
        for index=1,#raw do if raw:byte(index)>palette_count then return nil,_('The drawing file contains an invalid color index.') end end
        local pixels=ffi.new("uint8_t[?]",w*h); ffi.copy(pixels,raw,w*h)
        layers[n]={name=_('Layer ')..n,width=w,height=h,pixels=pixels,empty=false}; i=i+w*h
    end
    self.width,self.height,self.layers,self.active=w,h,layers,clamp(active or 1,1,count)
    self.palette, self.color = loaded_palette, selected_color
    self.history,self.redo_stack={},{}
    return true
end

function Draw:saveProject()
    self:ensure()
    local dir=nil
    local ok,ds=pcall(require,"datastorage"); if ok and ds.getDataDir then dir=ds:getDataDir() end
    dir=(dir or "/tmp").."/appdock/draw"; os.execute("mkdir -p "..string.format("%q",dir))
    save_sequence=save_sequence+1
    local path=dir.."/drawing-"..os.date("%Y%m%d-%H%M%S").."-"..save_sequence..".adraw"
    local f,err=io.open(path,"wb"); if not f then return nil,err end
    f:write(self:projectBytes()); f:close(); return path
end

function Draw:projectDirectory()
    local dir="/tmp"; local ok,ds=pcall(require,"datastorage"); if ok and ds.getDataDir then dir=ds:getDataDir() end
    return dir.."/appdock/draw"
end

function Draw:loadLatestProject()
    local dir=self:projectDirectory()
    local pipe=io.popen("ls -1t "..string.format("%q",dir).."/*.adraw 2>/dev/null", "r")
    local path=pipe and pipe:read("*l"); if pipe then pipe:close() end
    if not path then return nil,_('No saved AppDock Draw project was found.') end
    local f,err=io.open(path,"rb"); if not f then return nil,err end
    local bytes=f:read("*a"); f:close()
    local ok_load,load_error=self:loadBytes(bytes)
    if not ok_load then return nil,load_error end
    return path
end

function Draw:loadPath(path)
    if type(path)~="string" or #path>4096 or not path:lower():match("%.adraw$") then return nil,_('Choose an .adraw project file.') end
    local f,err=io.open(path,"rb"); if not f then return nil,err end
    local size=f:seek("end")
    if not size or size>480*640*6+#MAGIC+8+255*3 then f:close(); return nil,_('The drawing file is too large.') end
    f:seek("set",0); local bytes=f:read("*a"); f:close()
    return self:loadBytes(bytes)
end

function Draw:exportJPEG()
    self:ensure()
    local dir="/tmp"; local ok,ds=pcall(require,"datastorage"); if ok and ds.getDataDir then dir=ds:getDataDir() end
    local base=dir.."/appdock/draw"; os.execute("mkdir -p "..string.format("%q",base))
    save_sequence=save_sequence+1
    local stem=base.."/drawing-"..os.date("%Y%m%d-%H%M%S").."-"..save_sequence
    local ppm, jpeg=stem..".ppm",stem..".jpg"
    local f,err=io.open(ppm,"wb"); if not f then return nil,err end
    f:write("P6\n",self.width," ",self.height,"\n255\n")
    for y=0,self.height-1 do for x=0,self.width-1 do
        local id=1
        for li=#self.layers,1,-1 do local v=self.layers[li].pixels[y*self.width+x]; if v and v~=0 then id=v; break end end
        local p=colorPalette(self)[id] or palette[1]
        local r,g,b=p[1],p[2],p[3]
        if self.color_dither then r,g,b=Draw.ditherChannel(r,x,y),Draw.ditherChannel(g,x,y),Draw.ditherChannel(b,x,y) end
        f:write(string.char(r,g,b))
    end end
    f:close()
    local pipe=io.popen("command -v ffmpeg 2>/dev/null","r"); local ffmpeg=pipe and pipe:read("*l"); if pipe then pipe:close() end
    if not ffmpeg then
        local data_dir
        local data_ok, data_storage=pcall(require,"datastorage")
        if data_ok and data_storage.getDataDir then data_dir=data_storage:getDataDir() end
        local bundled=(data_dir or "").."/appdock/tools/ffmpeg"
        local probe=io.open(bundled,"rb")
        if probe then probe:close(); ffmpeg=bundled end
    end
    if not ffmpeg then os.remove(ppm); return nil,_('JPEG export needs ffmpeg on the device.') end
    local ok=os.execute(string.format("%q -y -v error -i %q -q:v 2 %q >/dev/null 2>&1",ffmpeg,ppm,jpeg)); os.remove(ppm)
    if ok~=0 then return nil,_('JPEG export failed.') end
    return jpeg
end

----------------------------------------------------------------
-- Pane
----------------------------------------------------------------

local TOOL_ORDER = { "pen", "eraser", "line", "rect", "circle", "fill" }

function Draw:buildPane(instance, context)
    self:ensure()
    self.stroke = nil
    context = type(context) == "table" and context or {}
    local fallback_size = {}
    if type(Screen.getSize) == "function" then
        local size_ok, size = pcall(Screen.getSize, Screen)
        if size_ok and type(size) == "table" then fallback_size = size end
    end
    local dim = type(context.dimen) == "table" and context.dimen or fallback_size
    local w = safeDimension(dim.w, self.width * safeScale(2), 4096)
    local h = safeDimension(dim.h, self.height * safeScale(2), 4096)

    local margin = safeScale(6)
    local gap = safeScale(4)
    local tool_bar_h = safeScale(40)
    local option_bar_h = safeScale(36)
    local action_bar_h = safeScale(38)
    local canvas_y = tool_bar_h + option_bar_h + margin * 2
    local canvas_h = math.max(safeScale(60), h - canvas_y - action_bar_h - margin)
    local canvas_w = math.max(safeScale(60), w - margin * 2)

    local pane = OverlapGroup:new{ dimen = Geom:new{ w = w, h = h }, allow_mirroring = false }

    local function rebuild()
        if context.requestRebuild then context.requestRebuild("ui") end
    end

    local function openRGBPicker()
        local current = colorPalette(self)[clamp(self.color or 1, 1, #colorPalette(self))] or palette[1]
        local dialog
        dialog = AppDockDialogs.InputDialog:new{
            title = _("RGB color"),
            text = _("Enter a six-digit hex color or three RGB channel values."),
            input = string.format("#%02X%02X%02X", current[1], current[2], current[3]),
            input_hint = _("#RRGGBB or R,G,B"),
            buttons = {
                {
                    { text = _("Cancel") },
                    {
                        text = _("Apply"),
                        is_enter_default = true,
                        callback = function()
                            local r, g, b = Draw.parseRGB(dialog:getInputText())
                            if r == nil then
                                if context.notify then context.notify(_("Use #RRGGBB or three channel values such as 128,64,255.")) end
                                return
                            end
                            local color_id, err = self:setRGBColor(r, g, b)
                            if not color_id then
                                if context.notify then context.notify(err) end
                                return
                            end
                            rebuild()
                        end,
                    },
                },
            },
        }
        AppDockKeyboard.attach(dialog)
        UIManager:show(dialog)
        dialog:onShowKeyboard()
    end

    -- Tool strip ------------------------------------------------------------
    local tool_buttons = {}
    local extra = {
        { "undo", _("Undo"), function() self:undo() end, true },
        { "redo", _("Redo"), function() self:redo() end, true },
        { "refresh", _("Clean screen"), function()
            -- A drawing app needs an occasional full refresh to clear E-Ink
            -- ghosting; nothing on the canvas changes, so no rebuild follows.
            if UIManager.setDirty then UIManager:setDirty(nil, "full") end
            if UIManager.forceRePaint then UIManager:forceRePaint() end
        end, false, _("Refresh") },
    }
    local slots = #TOOL_ORDER + #extra
    -- Keep the strip inside the pane even in a narrow split or window pane by
    -- shrinking the gap before the buttons become too small to tap.
    local strip_width = w - margin * 2
    local button_w = math.floor((strip_width - gap * (slots - 1)) / slots)
    if button_w < safeScale(20) and slots > 1 then
        gap = math.max(1, math.floor((strip_width - safeScale(20) * slots) / (slots - 1)))
        button_w = math.max(1, math.floor((strip_width - gap * (slots - 1)) / slots))
    end
    local button_h = tool_bar_h - gap
    for index, tool in ipairs(TOOL_ORDER) do
        local button = ToolButton:new{
            symbol = tool,
            label = TOOL_LABELS[tool],
            active = self.tool == tool,
            width = button_w,
            height = button_h,
            callback = function()
                self:setTool(tool)
                rebuild()
            end,
            overlap_offset = { margin + (index - 1) * (button_w + gap), margin },
        }
        tool_buttons[tool] = button
        pane[#pane + 1] = button
    end
    for index, entry in ipairs(extra) do
        local position = #TOOL_ORDER + index
        pane[#pane + 1] = ToolButton:new{
            symbol = entry[1],
            label = entry[5] or entry[2],
            width = button_w,
            height = button_h,
            callback = function()
                entry[3]()
                if entry[4] then rebuild() end
            end,
            overlap_offset = { margin + (position - 1) * (button_w + gap), margin },
        }
    end

    -- Options row: colors, brush size, layers, dithering --------------------
    local option_y = tool_bar_h + margin
    local swatch_size = option_bar_h - gap
    local swatches = {}
    for index = 1, #palette do
        local swatch = ColorSwatch:new{
            color_id = index,
            active = self.color == index,
            width = swatch_size,
            height = swatch_size,
            callback = function()
                self.color = index
                rebuild()
            end,
            overlap_offset = { margin + (index - 1) * (swatch_size + gap), option_y },
        }
        swatches[index] = swatch
        pane[#pane + 1] = swatch
    end

    local picker_x = margin + #palette * (swatch_size + gap) + gap
    local picker_width = math.max(safeScale(46), math.min(safeScale(60), swatch_size + safeScale(26)))
    pane[#pane + 1] = Chip:new{
        text = "RGB",
        color = colorPalette(self)[clamp(self.color or 1, 1, #colorPalette(self))],
        active = self.color > #palette,
        width = picker_width,
        height = swatch_size,
        callback = openRGBPicker,
        overlap_offset = { picker_x, option_y },
    }

    local size_x = picker_x + picker_width + gap
    local size_button = math.max(safeScale(20), math.floor(swatch_size * 0.8))
    local size_center_y = option_y + math.floor((swatch_size - size_button) / 2)
    pane[#pane + 1] = ToolButton:new{
        symbol = "minus",
        width = size_button,
        height = size_button,
        callback = function()
            self:cycleBrush(-1)
            rebuild()
        end,
        overlap_offset = { size_x, size_center_y },
    }
    -- The current brush size is shown as text, like the size readout of a paint
    -- program, instead of a glyph the user has to interpret.
    local size_label_width = math.max(size_button, safeScale(46))
    pane[#pane + 1] = Chip:new{
        text = string.format("%d px", self.brush_size or 1),
        width = size_label_width,
        height = swatch_size,
        overlap_offset = { size_x + size_button + gap, option_y },
    }
    local plus_x = size_x + size_button + gap + size_label_width + gap
    pane[#pane + 1] = ToolButton:new{
        symbol = "plus",
        width = size_button,
        height = size_button,
        callback = function()
            self:cycleBrush(1)
            rebuild()
        end,
        overlap_offset = { plus_x, size_center_y },
    }

    local layer_x = plus_x + size_button + gap
    pane[#pane + 1] = ToolButton:new{
        symbol = "layer_add",
        width = size_button,
        height = size_button,
        callback = function()
            self:addLayer()
            rebuild()
        end,
        overlap_offset = { layer_x, size_center_y },
    }
    pane[#pane + 1] = ToolButton:new{
        symbol = "layer_next",
        width = size_button,
        height = size_button,
        callback = function()
            self:nextLayer()
            rebuild()
        end,
        overlap_offset = { layer_x + size_button + gap, size_center_y },
    }

    local dither_width = w - (layer_x + size_button * 2 + gap * 2) - margin
    if dither_width >= safeScale(52) then
        pane[#pane + 1] = Chip:new{
            text = _("Dither"),
            active = self.color_dither,
            width = dither_width,
            height = swatch_size,
            callback = function()
                self.color_dither = not self.color_dither
                rebuild()
            end,
            overlap_offset = { w - margin - dither_width, option_y },
        }
    end

    -- Canvas ---------------------------------------------------------------
    local canvas = Canvas:new{ app = self, width = self.width, height = self.height }
    canvas.dimen = Geom:new{ x = margin, y = canvas_y, w = canvas_w, h = canvas_h }
    canvas.ges_events.Paint[1].range = function() return canvas.dimen end
    canvas.ges_events.PaintTap[1].range = function() return canvas.dimen end
    canvas.ges_events.PaintRelease[1].range = function() return canvas.dimen end
    canvas.ges_events.PaintTouch[1].range = function() return canvas.dimen end
    canvas.overlap_offset = { margin, canvas_y }
    pane[#pane + 1] = canvas
    -- Raw Kobo stylus samples are needed for pressure and the physical eraser
    -- and marker buttons. The listener is attached only while this pane lives,
    -- so no other AppDock screen observes or changes touch handling.
    Stylus:activate(canvas)

    -- Action bar ------------------------------------------------------------
    local action_y = h - action_bar_h
    local actions = {
        -- symbol, label, action, reports a file path
        { "trash", _("Clear"), function() self:clear() end, false },
        { "save", _("Save"), function() return self:saveProject() end, true },
        { "open", _("Open"), function() return self:loadLatestProject() end, true },
        { "image", _("JPEG"), function() return self:exportJPEG() end, true },
    }
    local action_w = math.max(safeScale(48), math.floor((w - margin * 2 - gap * (#actions - 1)) * 0.52 / #actions))
    for index, entry in ipairs(actions) do
        pane[#pane + 1] = Chip:new{
            text = entry[2],
            symbol = entry[1],
            width = action_w,
            height = action_bar_h - gap,
            callback = function()
                local result, message = entry[3]()
                if entry[4] and context.notify then
                    context.notify{ title = _("Draw"), message = tostring(result or message) }
                end
                rebuild()
            end,
            overlap_offset = { margin + (index - 1) * (action_w + gap), action_y },
        }
    end

    local status = TextWidget:new{
        text = self:statusText(),
        face = Font:getFace("smallinfofont", safeScale(11)),
        max_width = math.max(safeScale(40), w - margin * 2 - action_w * #actions - gap * #actions),
        padding = 0,
    }
    local status_size = status:getSize()
    status.overlap_offset = {
        w - margin - math.min(status_size.w, math.max(safeScale(40), w - margin * 2 - action_w * #actions - gap * #actions)),
        action_y + math.floor((action_bar_h - status_size.h) / 2),
    }
    pane[#pane + 1] = status

    pane.onDeactivate = function()
        Stylus:deactivate(canvas)
        if self.canvas == canvas then self.canvas = nil end
    end
    self.canvas = canvas
    return pane
end

Draw.Canvas = Canvas
Draw.ToolButton = ToolButton
Draw.ColorSwatch = ColorSwatch
Draw.Chip = Chip
return Draw
