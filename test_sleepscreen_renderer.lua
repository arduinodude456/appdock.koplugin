-- Renderer regressions: KOReader APIs are represented by strict, observable mocks.
local plugin_dir = os.getenv("APPDOCK_PLUGIN_DIR") or "./appdock.koplugin/"
package.path = plugin_dir .. "?.lua;" .. package.path

local function class(base)
    local result = {}
    result.__index = result
    setmetatable(result, { __index = base })
    function result:extend(child)
        local subtype = class(self)
        for key, value in pairs(child or {}) do subtype[key] = value end
        return subtype
    end
    function result:new(args)
        local object = setmetatable(args or {}, self)
        if object.init then object:init() end
        return object
    end
    return result
end

local Widget = class()
local color8_levels = {}
local Blitbuffer = {
    COLOR_BLACK = { gray = 0 },
    COLOR_WHITE = { gray = 255 },
    ColorRGB32 = function(red, green, blue, alpha)
        return { red = red, green = green, blue = blue, alpha = alpha }
    end,
    new = function(width, height)
        return {
            getWidth = function() return width end,
            getHeight = function() return height end,
            fill = function() end,
            free = function() end,
        }
    end,
    -- Force the renderer's documented grayscale fallback in these tests.
    colorFromString = function() return nil end,
    Color8 = function(level)
        color8_levels[#color8_levels + 1] = level
        return { gray = level }
    end,
}

local font_calls = {}
local Font = {
    getFace = function(_, name, size)
        font_calls[#font_calls + 1] = { name = name, size = size }
        if name == "/missing-font.ttf" then return nil end
        return { name = name, size = size }
    end,
}

local TextWidget = class(Widget)
function TextWidget:getSize()
    return { w = math.min(self.max_width or 0, 30), h = 10 }
end
function TextWidget:paintTo(bb, x, y)
    self.painted = { bb = bb, x = x, y = y }
end
function TextWidget:free()
    self.free_calls = (self.free_calls or 0) + 1
end

local TextBoxWidget = class(Widget)
function TextBoxWidget:init()
    self.kind = "textbox"
end
function TextBoxWidget:getSize()
    return { w = self.width, h = self.height }
end
function TextBoxWidget:paintTo(bb, x, y)
    self.painted = { bb = bb, x = x, y = y }
end
function TextBoxWidget:free()
    self.free_calls = (self.free_calls or 0) + 1
end

local Device = { model = "Mock KOReader" }
local image_sizes = {
    ["/one.png"] = { w = 100, h = 100 },
    ["/two.png"] = { w = 100, h = 50 },
}
local image_calls = {}
local ImageWidget = class(Widget)
function ImageWidget:new(args)
    local object = setmetatable(args or {}, self)
    object.kind = "image"
    object.source_size = image_sizes[object.file] or { w = 1, h = 1 }
    object.free_calls = 0
    image_calls[#image_calls + 1] = object
    return object
end
function ImageWidget:getSize()
    self.rendered = true
    return { w = self.width, h = self.height }
end
function ImageWidget:getOriginalWidth()
    return self.source_size.w
end
function ImageWidget:getOriginalHeight()
    return self.source_size.h
end
function ImageWidget:paintTo(bb, x, y)
    self.painted = { bb = bb, x = x, y = y }
end
function ImageWidget:free()
    self.free_calls = self.free_calls + 1
end

package.preload["ffi/blitbuffer"] = function() return Blitbuffer end
package.preload["device"] = function() return Device end
package.preload["ui/font"] = function() return Font end
package.preload["ui/geometry"] = function()
    return { new = function(_, value) return value end }
end
package.preload["ui/widget/imagewidget"] = function() return ImageWidget end
package.preload["ui/widget/textwidget"] = function() return TextWidget end
package.preload["ui/widget/textboxwidget"] = function() return TextBoxWidget end
package.preload["ui/widget/widget"] = function() return Widget end
package.preload["appdock_sleepscreen_presets"] = function()
    return {
        normalize = function(definition) return definition end,
        defaultPreset = function()
            return { schema_version = 1, name = "Default", background = "#FFFFFF", elements = {} }
        end,
    }
end

package.loaded["appdock_sleepscreen_renderer"] = nil
local Renderer = require("appdock_sleepscreen_renderer")

local function definition(elements, background)
    return {
        schema_version = 1,
        name = "Test",
        background = background or "#FFFFFF",
        elements = elements,
    }
end

-- A viewport is local to the clipping rectangle. Positive offsets are vital
-- for centered/right-aligned children that are smaller than their box.
local viewport_frees = 0
local viewport_calls = {}
local parent = {
    viewport = function(_, x, y, w, h)
        viewport_calls[#viewport_calls + 1] = { x = x, y = y, w = w, h = h }
        return {
            free = function() viewport_frees = viewport_frees + 1 end,
        }
    end,
}
local child_paints = {}
local clipped_child = {
    getSize = function() return { w = 30, h = 20 } end,
    paintTo = function(_, bb, x, y) child_paints[#child_paints + 1] = { bb = bb, x = x, y = y } end,
}
local centered = Renderer._test.ClippedElement:new{
    width = 100, height = 60, child = clipped_child, align = "center", vertical_align = "center",
}
centered:paintTo(parent, 7, 9)
assert(viewport_calls[1].x == 7 and viewport_calls[1].y == 9 and viewport_calls[1].w == 100 and viewport_calls[1].h == 60,
    "clipping must create exactly the element-local viewport")
assert(child_paints[1].x == 35 and child_paints[1].y == 20,
    "center alignment must retain positive local offsets")
assert(viewport_frees == 1, "the temporary viewport must be released after paint")

local right = Renderer._test.ClippedElement:new{
    width = 100, height = 60, child = clipped_child, align = "right", vertical_align = "top",
}
right:paintTo(parent, 0, 0)
assert(child_paints[2].x == 70 and child_paints[2].y == 0,
    "right alignment must retain the positive local x offset")
assert(viewport_frees == 2, "each viewport must be released exactly once")

-- Font size is referenced to the full canvas, never a narrow element. A tiny
-- preview still receives a valid 1px face rather than the old 6px floor.
local fonts_canvas = Renderer.build(definition({
    { type = "text", x = 0, y = 0, w = 10, h = 10, text = "Narrow", font_size = 24 },
    { type = "text", x = 10, y = 0, w = 80, h = 10, text = "Wide", font_size = 24 },
}), 600, 400, { preview = true })
local narrow = fonts_canvas.entries[1].widget.child
local wide = fonts_canvas.entries[2].widget.child
assert(narrow.face.size == 24 and wide.face.size == 24,
    "identical declared sizes must not vary with text-box width")
fonts_canvas:free()

local tiny_canvas = Renderer.build(definition({
    { type = "text", x = 0, y = 0, w = 100, h = 100, text = "Tiny", font_size = 8 },
}), 10, 10, { preview = true })
assert(tiny_canvas.entries[1].widget.child.face.size == 1,
    "shrunk preview text must use the proportional 1px minimum")
tiny_canvas:free()

-- Cards need true multiline layout and must retain text and horizontal
-- alignment in TextBoxWidget instead of receiving TextWidget truncation.
local cards_canvas = Renderer.build(definition({
    { type = "card", x = 0, y = 0, w = 50, h = 50, text = "Line one\nLine two", font_size = 20, align = "center" },
}), 600, 400, { preview = true })
local card = cards_canvas.entries[1].widget.child
assert(card.kind == "textbox" and card.text == "Line one\nLine two", "cards must use TextBoxWidget for multiline text")
assert(card.width == 300 and card.height == 200 and card.alignment == "center" and card.height_overflow_show_ellipsis,
    "cards must pass their real bounds and alignment to TextBoxWidget")
cards_canvas:free()

-- A custom font path is supplied directly to Font:getFace. If that face cannot
-- be opened, the documented infofont fallback remains usable.
local custom_canvas = Renderer.build(definition({
    { type = "text", x = 0, y = 0, w = 50, h = 10, text = "Custom", font = "asset:good", font_size = 18 },
    { type = "text", x = 0, y = 10, w = 50, h = 10, text = "Fallback", font = "asset:bad", font_size = 18 },
}), 600, 400, { asset_paths = { good = "/custom-font.ttf", bad = "/missing-font.ttf" } })
assert(custom_canvas.entries[1].widget.child.face.name == "/custom-font.ttf", "custom font assets must reach Font:getFace as paths")
assert(custom_canvas.entries[2].widget.child.face.name == "infofont", "unavailable custom fonts must fall back to infofont")
custom_canvas:free()

-- When the normal color parser is unavailable, different RGB declarations map
-- to distinct luminances instead of all becoming the same fallback color.
local colors_canvas = Renderer.build(definition({
    { type = "text", x = 0, y = 0, w = 20, h = 20, text = "Color", background = "#0000FF" },
}, "#FF0000"), 100, 100, {})
assert(colors_canvas.background.gray == 76 and colors_canvas.entries[1].widget.background.gray == 29,
    "grayscale fallback must preserve distinct red and blue luminance")
colors_canvas:free()

-- Color-capable readers must retain RGB declarations for both canvas and
-- element fills instead of sending them through the grayscale Color8 path.
Device.screen = { isColorEnabled = function() return true end }
local color_device_canvas = Renderer.build(definition({
    { type = "text", x = 0, y = 0, w = 20, h = 20, text = "Color", background = "#445566" },
}, "#112233"), 100, 100, {})
assert(color_device_canvas.background.red == 0x11 and color_device_canvas.background.green == 0x22
    and color_device_canvas.background.blue == 0x33,
    "color-capable readers must retain the declared canvas RGB value")
assert(color_device_canvas.entries[1].widget.background.red == 0x44
    and color_device_canvas.entries[1].widget.background.green == 0x55
    and color_device_canvas.entries[1].widget.background.blue == 0x66,
    "color-capable readers must retain the declared element RGB value")
color_device_canvas:free()

local transparent_canvas = Renderer.build(definition({
    { type = "text", x = 0, y = 0, w = 20, h = 20, text = "Color", background = "#445566", background_alpha = 0.35 },
}, "#112233"), 100, 100, {})
assert(transparent_canvas.entries[1].widget.background_alpha == 0.35,
    "element background opacity must be retained by the clipped element")
local alpha_blit
local target_bb = {
    getType = function() return "mock" end,
    addblitFrom = function(_, _, x, y, _, _, width, height, alpha)
        alpha_blit = { x = x, y = y, width = width, height = height, alpha = alpha }
    end,
    paintRect = function() end,
}
transparent_canvas:paintTo(target_bb, 0, 0)
assert(alpha_blit and alpha_blit.alpha == 0.35, "transparent backgrounds must use addblitFrom opacity compositing")
transparent_canvas:free()

local custom_definition = definition({
    { type = "widget", x = 0, y = 0, w = 100, h = 20, widget_id = "greeting", font = "infofont", font_size = 18, color = "#000000" },
})
custom_definition.widgets = {
    { id = "greeting", name = "Greeting", text = "Fallback", frames = { { text = "One", duration = 1 }, { text = "Two", duration = 1 } } },
}
local custom_canvas = Renderer.build(custom_definition, 100, 100, { preview = true, cycle = 1 })
assert(custom_canvas.entries[1].widget.child.text == "Two", "custom widget animation must select the frame for the current cycle")
custom_canvas:free()

local weather_definition = definition({
    { type = "widget", x = 0, y = 0, w = 100, h = 20, widget_id = "forecast", font = "infofont", font_size = 18, color = "#000000" },
})
weather_definition.widgets = { { id = "forecast", name = "Weather", text = "{temperature} · {weather}", weather = true,
    latitude = 52.52, longitude = 13.405, weather_cache = { temperature = "18.5°C", description = "Partly cloudy", updated = "2026-10-18 09:00" } } }
local weather_canvas = Renderer.build(weather_definition, 100, 100, { preview = false })
assert(weather_canvas.entries[1].widget.child.text == "18.5°C · Partly cloudy", "renderer must substitute only cached weather values without fetching")
weather_canvas:free()

-- contain delegates centering and original-size preservation to ImageWidget;
-- cover first probes actual original dimensions, then chooses the centered crop
-- scale for the selected image. Both the probe and returned widget free once.
image_calls = {}
local contain_canvas = Renderer.build(definition({
    { type = "image", x = 0, y = 0, w = 50, h = 100, images = { "one" }, fit = "contain" },
}), 200, 100, { asset_paths = { one = "/one.png" } })
local contain = image_calls[1]
assert(contain.file == "/one.png" and contain.width == 100 and contain.height == 100 and contain.scale_factor == 0,
    "contain must use ImageWidget's aspect-preserving, centered fit")
contain_canvas:free()
assert(contain.free_calls == 1, "the contain image must be freed once")

image_calls = {}
local cover_canvas = Renderer.build(definition({
    { type = "image", x = 0, y = 0, w = 100, h = 100, images = { "one", "two" }, fit = "cover" },
}), 200, 100, { asset_paths = { one = "/one.png", two = "/two.png" }, cycle = 1 })
assert(#image_calls == 2 and image_calls[1].file == "/two.png" and image_calls[1].scale_factor == 0,
    "cover must probe the cycle-selected image at contain scale")
local cover = image_calls[2]
assert(cover.file == "/two.png" and cover.width == 200 and cover.height == 100 and cover.scale_factor == 2,
    "cover must scale the selected image to the max dimension ratio for centered crop")
assert(image_calls[1].free_calls == 1, "the cover probe must be freed exactly once")
cover_canvas:free()
cover_canvas:free()
assert(cover.free_calls == 1, "canvas cleanup must free the returned cover image exactly once")

print("PASS sleepscreen renderer regressions")
