--[[
Shared declarative Sleepscreen renderer.

It accepts only a normalized declaration, uses no network services, and makes
all device-derived substitutions locally at build time.  The small clipping
container below uses a BlitBuffer viewport so text and cover images cannot
paint outside their declared percent rectangle.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local ImageWidget = require("ui/widget/imagewidget")
local TextWidget = require("ui/widget/textwidget")
-- TextBoxWidget is present in maintained KOReader releases and is needed for
-- wrapped card text.  Keep TextWidget as the compatibility fallback for older
-- releases which do not ship it.
local has_textboxwidget, TextBoxWidget = pcall(require, "ui/widget/textboxwidget")
if not has_textboxwidget then TextBoxWidget = nil end
local Widget = require("ui/widget/widget")
local Presets = require("appdock_sleepscreen_presets")

local Renderer = {}

local PREVIEW_VALUES = {
    time = "10:42",
    date = "Tuesday, 14 May 2024",
    battery = "73%",
    device = "KOReader",
    sleeping = "Sleeping",
}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function safeNumber(value, fallback)
    value = tonumber(value)
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then return fallback end
    return value
end

local function hasColorScreen()
    -- Some KOReader targets expose isColorScreen(), others only expose
    -- isColorEnabled(). Accept either so declared RGB colors are not silently
    -- converted to grayscale on color-capable readers.
    if Device and Device.screen then
        if type(Device.screen.isColorScreen) == "function" then
            local ok, enabled = pcall(Device.screen.isColorScreen, Device.screen)
            if ok and enabled == true then return true end
        end
        if type(Device.screen.isColorEnabled) == "function" then
            local ok, enabled = pcall(Device.screen.isColorEnabled, Device.screen)
            if ok and enabled == true then return true end
        end
    end
    return false
end

local function color(value, fallback, alpha)
    if type(value) ~= "string" then return fallback end
    local hex = value:match("^#?([%da-fA-F][%da-fA-F])([%da-fA-F][%da-fA-F])([%da-fA-F][%da-fA-F])$")
    if not hex then return fallback end
    local offset = value:sub(1, 1) == "#" and 2 or 1
    local red = tonumber(value:sub(offset, offset + 1), 16)
    local green = tonumber(value:sub(offset + 2, offset + 3), 16)
    local blue = tonumber(value:sub(offset + 4, offset + 5), 16)
    if hasColorScreen() and type(Blitbuffer.ColorRGB32) == "function" then
        alpha = alpha == nil and 1 or clamp(safeNumber(alpha, 1), 0, 1)
        local ok, rgb = pcall(Blitbuffer.ColorRGB32, red, green, blue, math.floor(alpha * 255 + 0.5))
        if ok and rgb then return rgb end
    end
    if type(Blitbuffer.colorFromString) == "function" then
        local ok, parsed = pcall(Blitbuffer.colorFromString, value)
        if ok and parsed then return parsed end
    end
    if type(Blitbuffer.Color8) == "function" then
        local luminance = math.floor((299 * red + 587 * green + 114 * blue) / 1000 + 0.5)
        local ok, grayscale = pcall(Blitbuffer.Color8, luminance)
        if ok and grayscale then return grayscale end
    end
    return fallback
end

local function paintRect(bb, x, y, width, height, fill)
    if not fill then return end
    -- blendRectRGB32 performs the actual source-over operation. Do not gate it
    -- on the device probe: some KOReader sleep/suspend paths expose a reduced
    -- Device.screen object even though the destination blitbuffer is RGB.
    if fill.alpha and fill.alpha < 255 and type(bb.blendRectRGB32) == "function" then
        bb:blendRectRGB32(x, y, width, height, fill)
    elseif hasColorScreen() and type(bb.paintRectRGB32) == "function" then
        bb:paintRectRGB32(x, y, width, height, fill)
    elseif bb.paintRect then
        bb:paintRect(x, y, width, height, fill)
    end
end

local function localPowerCapacity()
    if not Device or type(Device.getPowerDevice) ~= "function" then return nil end
    local ok, power = pcall(Device.getPowerDevice, Device)
    if not ok or not power or type(power.getCapacity) ~= "function" then return nil end
    local capacity_ok, capacity = pcall(power.getCapacity, power)
    capacity = tonumber(capacity)
    if not capacity_ok or not capacity or capacity ~= capacity then return nil end
    return math.floor(clamp(capacity, 0, 100) + 0.5) .. "%"
end

local function localDeviceName()
    -- Device.model is a user-facing local model label on normal KOReader
    -- targets.  Do not consult serials, books, or network-derived metadata.
    if Device and type(Device.model) == "string" and #Device.model > 0 then return Device.model end
    if Device and type(Device.device) == "string" and #Device.device > 0 then return Device.device end
    return "KOReader"
end

local function replacementValues(preview)
    if preview then
        local result = {}
        for key, value in pairs(PREVIEW_VALUES) do result[key] = value end
        return result
    end
    return {
        time = os.date("%H:%M"),
        date = os.date("%A, %d %B"),
        battery = localPowerCapacity() or "—",
        device = localDeviceName(),
        sleeping = "Sleeping",
    }
end

local function substitute(text, values)
    if type(text) ~= "string" then return "" end
    return (text:gsub("{([A-Za-z]+)}", function(name)
        return values[name] or "{" .. name .. "}"
    end))
end

local function childSize(child)
    if not child or type(child.getSize) ~= "function" then return { w = 0, h = 0 } end
    local ok, size = pcall(child.getSize, child)
    if not ok or type(size) ~= "table" then return { w = 0, h = 0 } end
    return { w = math.max(0, safeNumber(size.w, 0)), h = math.max(0, safeNumber(size.h, 0)) }
end

-- A viewport is the KOReader BlitBuffer clipping primitive.  The fallback is
-- only for narrow test mocks lacking viewport; regular TextWidget/ImageWidget
-- bounds still constrain the normal draw path in that case.
local ClippedElement = Widget:extend{
    width = 0,
    height = 0,
    child = nil,
    background = nil,
    align = "left",
    vertical_align = "center",
    background_alpha = 1,
    background_bb = nil,
    dimen = nil,
    _freed = false,
}

function ClippedElement:init()
    self.width = math.max(1, math.floor(safeNumber(self.width, 1)))
    self.height = math.max(1, math.floor(safeNumber(self.height, 1)))
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self.background_alpha = clamp(safeNumber(self.background_alpha, 1), 0, 1)
end

function ClippedElement:getSize()
    return self.dimen
end

function ClippedElement:paintTo(bb, x, y)
    if self.background and self.background_alpha > 0 then
        if self.background_alpha >= 1 then
            paintRect(bb, x, y, self.width, self.height, self.background)
        else
            -- Compose an opaque temporary rectangle and blend the result into
            -- the target. addblitFrom works for grayscale as well as RGB
            -- buffers, unlike an alpha field on ColorRGB32.
            if not self.background_bb
                or self.background_bb:getWidth() ~= self.width
                or self.background_bb:getHeight() ~= self.height
            then
                if self.background_bb then self.background_bb:free() end
                self.background_bb = Blitbuffer.new(self.width, self.height, bb:getType())
            end
            self.background_bb:fill(self.background)
            bb:addblitFrom(self.background_bb, x, y, 0, 0, self.width, self.height, self.background_alpha)
        end
    end
    if not self.child or type(self.child.paintTo) ~= "function" then return end
    local size = childSize(self.child)
    local child_x = 0
    if self.align == "center" then
        child_x = math.floor((self.width - size.w) / 2)
    elseif self.align == "right" then
        child_x = self.width - size.w
    end
    local child_y = self.vertical_align == "top" and 0 or math.floor((self.height - size.h) / 2)

    if bb.viewport then
        local ok, viewport = pcall(bb.viewport, bb, x, y, self.width, self.height)
        if ok and viewport then
            -- Viewport coordinates are local to the clipped sub-buffer.  Do
            -- not clamp offsets: positive values implement center/right (and
            -- vertical center) alignment for children smaller than the box;
            -- negative values crop oversized children through the viewport.
            local painted, paint_err = pcall(self.child.paintTo, self.child, viewport, child_x, child_y)
            if type(viewport.free) == "function" then pcall(viewport.free, viewport) end
            if not painted then error(paint_err, 0) end
            return
        end
    end
    self.child:paintTo(bb, x + child_x, y + child_y)
end

function ClippedElement:free()
    if self._freed then return end
    self._freed = true
    if self.child and type(self.child.free) == "function" then pcall(self.child.free, self.child) end
    self.child = nil
    if self.background_bb then self.background_bb:free(); self.background_bb = nil end
end

local SleepCanvas = Widget:extend{
    width = 0,
    height = 0,
    background = Blitbuffer.COLOR_WHITE,
    entries = nil,
    dimen = nil,
    _freed = false,
}

function SleepCanvas:init()
    self.width = math.max(1, math.floor(safeNumber(self.width, 1)))
    self.height = math.max(1, math.floor(safeNumber(self.height, 1)))
    self.entries = self.entries or {}
    self.dimen = Geom:new{ w = self.width, h = self.height }
end

function SleepCanvas:getSize()
    return self.dimen
end

function SleepCanvas:paintTo(bb, x, y)
    paintRect(bb, x, y, self.width, self.height, self.background)
    for _, entry in ipairs(self.entries) do
        if entry and entry.widget then entry.widget:paintTo(bb, x + entry.x, y + entry.y) end
    end
end

function SleepCanvas:free()
    if self._freed then return end
    self._freed = true
    for _, entry in ipairs(self.entries or {}) do
        if entry.widget and type(entry.widget.free) == "function" then pcall(entry.widget.free, entry.widget) end
    end
    self.entries = {}
end

local function toPixels(element, width, height)
    local x = math.floor(width * element.x / 100 + 0.5)
    local y = math.floor(height * element.y / 100 + 0.5)
    local w = math.max(1, math.floor(width * element.w / 100 + 0.5))
    local h = math.max(1, math.floor(height * element.h / 100 + 0.5))
    x = clamp(x, 0, math.max(0, width - 1))
    y = clamp(y, 0, math.max(0, height - 1))
    w = clamp(w, 1, width - x)
    h = clamp(h, 1, height - y)
    return x, y, w, h
end

local function faceFor(element, asset_paths, canvas_width)
    local name = element.font or "infofont"
    if name:sub(1, 6) == "asset:" then
        local asset_id = name:sub(7)
        local path = asset_paths and asset_paths[asset_id]
        -- normalize() has checked the declared font reference.  The renderer
        -- still treats a missing local file as a recoverable fallback.
        if type(path) == "string" then name = path else name = "infofont" end
    end
    local logical_size = safeNumber(element.font_size, 18)
    -- Element width only controls wrapping.  The declared font scale belongs
    -- to the 600px-wide canvas reference, so equal text stays equal-sized in
    -- narrow and wide boxes.  Tiny editor previews must still get a valid 1px
    -- face instead of being artificially enlarged to 6px.
    logical_size = clamp(logical_size * canvas_width / 600, 1, 160)
    local ok, face = pcall(Font.getFace, Font, name, logical_size)
    if ok and face then return face end
    local fallback_ok, fallback = pcall(Font.getFace, Font, "infofont", logical_size)
    return fallback_ok and fallback or nil
end

local function buildText(element, width, height, canvas_width, asset_paths, values)
    local text = substitute(element.text or "", values)
    local fg = color(element.color, Blitbuffer.COLOR_BLACK)
    local face = faceFor(element, asset_paths, canvas_width)
    if not face then return nil end
    if element.type == "card" and TextBoxWidget then
        local boxed_ok, boxed = pcall(TextBoxWidget.new, TextBoxWidget, {
            text = text,
            face = face,
            fgcolor = fg,
            bold = element.bold == true,
            width = width,
            height = height,
            alignment = element.align or "left",
            height_overflow_show_ellipsis = true,
        })
        if boxed_ok and boxed then return boxed end
    end
    local ok, widget = pcall(TextWidget.new, TextWidget, {
        text = text,
        face = face,
        fgcolor = fg,
        bold = element.bold == true,
        max_width = width,
        truncate_with_ellipsis = true,
        padding = 0,
    })
    return ok and widget or nil
end

local function selectedImagePath(element, asset_paths, cycle)
    local images = element.images or {}
    if #images == 0 then return nil end
    local current = math.floor(safeNumber(cycle, 0))
    local index = (current % #images) + 1
    local path = asset_paths and asset_paths[images[index]]
    return type(path) == "string" and path or nil
end

local function buildImage(path, width, height, fit)
    if not path then return nil end
    local function make(scale_factor)
        local ok, image = pcall(ImageWidget.new, ImageWidget, {
            file = path,
            width = width,
            height = height,
            scale_factor = scale_factor,
            original_in_nightmode = true,
        })
        return ok and image or nil
    end
    if fit ~= "cover" then return make(0) end

    -- ImageWidget's documented scale_factor=0 is contain.  Read the decoded
    -- native dimensions once, then make a second widget at the max factor so
    -- ImageWidget crops around its centered viewport without distortion.
    local probe = make(0)
    if not probe then return nil end
    local probe_ok = pcall(probe.getSize, probe)
    local got_w, source_w = pcall(probe.getOriginalWidth, probe)
    local got_h, source_h = pcall(probe.getOriginalHeight, probe)
    if type(probe.free) == "function" then pcall(probe.free, probe) end
    source_w = safeNumber(source_w, 0)
    source_h = safeNumber(source_h, 0)
    if not probe_ok or not got_w or not got_h or source_w <= 0 or source_h <= 0 then return make(0) end
    return make(math.max(width / source_w, height / source_h))
end

local function minutes(value)
    if type(value) ~= "string" then return nil end
    local hour, minute = value:match("^(%d%d):(%d%d)$")
    if not hour then return nil end
    return tonumber(hour) * 60 + tonumber(minute)
end

local function customWidgetText(element, definition, values, cycle)
    local widgets = definition.widgets or {}
    local selected
    for _, widget in ipairs(widgets) do
        if widget.id == element.widget_id then selected = widget; break end
    end
    if not selected then return "" end
    local now = minutes(os.date("%H:%M")) or 0
    for _, rule in ipairs(selected.schedule or {}) do
        local from, to = minutes(rule.from), minutes(rule.to)
        if from and to and ((from <= to and now >= from and now < to) or (from > to and (now >= from or now < to))) then
            return substitute(rule.text, values)
        end
    end
    if selected.frames and #selected.frames > 0 then
        local total, position = 0, math.floor(safeNumber(cycle, 0))
        for _, frame in ipairs(selected.frames) do total = total + math.max(1, tonumber(frame.duration) or 1) end
        position = total > 0 and (position % total) or 0
        for _, frame in ipairs(selected.frames) do
            local duration = math.max(1, tonumber(frame.duration) or 1)
            if position < duration then return substitute(frame.text, values) end
            position = position - duration
        end
    end
    return substitute(selected.text or "", values)
end

local function widgetText(element, values, definition, cycle)
    if element.widget_id then return customWidgetText(element, definition, values, cycle) end
    local source = element.source
    if source == "clock" then return values.time end
    if source == "date" then return values.date end
    if source == "battery" then return values.battery end
    if source == "device" then return values.device end
    return ""
end

local function safeDefinition(definition)
    local normalized = Presets.normalize(definition)
    if normalized then return normalized end
    return Presets.defaultPreset()
end

-- Build returns a normal KOReader Widget.  The caller owns it; its idempotent
-- free method is compatible with WidgetContainer's normal close-tree cleanup.
function Renderer.build(definition, width, height, options)
    options = type(options) == "table" and options or {}
    width = math.max(1, math.floor(safeNumber(width, 1)))
    height = math.max(1, math.floor(safeNumber(height, 1)))
    definition = safeDefinition(definition)
    local asset_paths = type(options.asset_paths) == "table" and options.asset_paths or {}
    local values = replacementValues(options.preview == true)
    local entries = {}

    for _, element in ipairs(definition.elements) do
        local x, y, element_width, element_height = toPixels(element, width, height)
        local child
        if element.type == "image" then
            child = buildImage(selectedImagePath(element, asset_paths, options.cycle), element_width, element_height, element.fit)
        elseif element.type == "widget" then
            local display = {}
            for key, value in pairs(element) do display[key] = value end
            display.text = widgetText(element, values, definition, options.cycle)
            child = buildText(display, element_width, element_height, width, asset_paths, values)
        else
            child = buildText(element, element_width, element_height, width, asset_paths, values)
        end
        -- The opacity is applied by ClippedElement via addblitFrom. Keep the
        -- temporary source color opaque so this also works on grayscale BBs.
        local background = element.background and color(element.background, nil) or nil
        -- image elements may have an explicit color behind letterboxed contain
        -- media; cards render their declared fill even when text creation fails.
        if child or background then
            table.insert(entries, {
                x = x,
                y = y,
                widget = ClippedElement:new{
                    width = element_width,
                    height = element_height,
                    child = child,
                    background = background,
                    background_alpha = element.background_alpha,
                    align = element.align or "left",
                    vertical_align = "center",
                },
            })
        end
    end

    return SleepCanvas:new{
        width = width,
        height = height,
        background = color(definition.background, Blitbuffer.COLOR_WHITE),
        entries = entries,
    }
end

Renderer._test = {
    preview_values = PREVIEW_VALUES,
    substitute = substitute,
    ClippedElement = ClippedElement,
    SleepCanvas = SleepCanvas,
}

return Renderer
