-- Standalone tests for appdock_text.lua.  They use a pixel mock so no full
-- KOReader runtime or framebuffer is required.
local plugin_dir = os.getenv("APPDOCK_PLUGIN_DIR")
if not plugin_dir then
    local source = debug.getinfo(1, "S").source
    source = source:sub(1, 1) == "@" and source:sub(2) or source
    plugin_dir = (source:match("^(.*[/\\])") or "./") .. "appdock.koplugin/"
end
if plugin_dir:sub(-1) ~= "/" then plugin_dir = plugin_dir .. "/" end

local function class(parent)
    local c = {}
    c.__index = c
    setmetatable(c, { __index = parent })
    function c:extend(fields)
        fields = fields or {}
        fields.__index = fields
        setmetatable(fields, { __index = self })
        return fields
    end
    function c:new(args)
        local object = setmetatable(args or {}, self)
        if object.init then object:init() end
        return object
    end
    return c
end

local function gray(value)
    return { value = value, color8 = true }
end

local function rgb(r, g, b)
    return { r = r, g = g, b = b, color8 = false }
end

local WHITE, BLACK = gray(255), gray(0)
local Blitbuffer = {
    COLOR_WHITE = WHITE,
    COLOR_BLACK = BLACK,
    isColor8 = function(color) return color and color.color8 == true end,
}
package.preload["ffi/blitbuffer"] = function() return Blitbuffer end

local function clone(pixel)
    return { r = pixel.r, g = pixel.g, b = pixel.b }
end

local function asRGB(color)
    if color.color8 then
        return { r = color.value, g = color.value, b = color.value }
    end
    return { r = color.r, g = color.g, b = color.b }
end

-- Same integer rounded alpha blend used by the assertions and mock compositor.
local function blend(base, foreground, alpha)
    local fg = asRGB(foreground)
    local function channel(background, component)
        local value = background * (255 - alpha) + component * alpha
        local adjusted = value + 128
        return math.floor((math.floor(adjusted / 256) + adjusted) / 256)
    end
    return {
        r = channel(base.r, fg.r),
        g = channel(base.g, fg.g),
        b = channel(base.b, fg.b),
    }
end

local function samePixel(actual, expected)
    return actual.r == expected.r and actual.g == expected.g and actual.b == expected.b
end

local function sourceBuffer(coverage, opaque_pixels)
    return {
        coverage = coverage,
        opaque_pixels = opaque_pixels,
        getHeight = function(self) return 1 end,
        getWidth = function(self) return #self.coverage end,
        free = function() end,
    }
end

local function destination(width, background, with_compositors)
    local dst = { pixels = {}, color_calls = 0, rgb_calls = 0, opaque_calls = 0 }
    for x = 1, width do dst.pixels[x] = clone(background) end
    function dst:blitFrom(source, x, y, offs_x, offs_y, width_to_blit)
        self.opaque_calls = self.opaque_calls + 1
        for column = 1, width_to_blit do
            self.pixels[x + column] = clone(source.opaque_pixels[offs_x + column])
        end
    end
    if with_compositors ~= false then
        function dst:colorblitFrom(source, x, y, offs_x, offs_y, width_to_blit, height, color)
            self.color_calls = self.color_calls + 1
            for column = 1, width_to_blit do
                local index = offs_x + column
                self.pixels[x + column] = blend(self.pixels[x + column], color, source.coverage[index])
            end
        end
        function dst:colorblitFromRGB32(source, x, y, offs_x, offs_y, width_to_blit, height, color)
            self.rgb_calls = self.rgb_calls + 1
            for column = 1, width_to_blit do
                local index = offs_x + column
                self.pixels[x + column] = blend(self.pixels[x + column], color, source.coverage[index])
            end
        end
    end
    return dst
end

local TextBoxWidget = class()
function TextBoxWidget:init()
    self.width = self.width or #(self.coverage or { 0 })
    self.fgcolor = self.fgcolor or BLACK
    self.bgcolor = self.bgcolor or WHITE
    self.coverage = self.coverage or { 0 }
    self.dimen = self.dimen or {}
end
function TextBoxWidget:_renderText(start_row_idx, end_row_idx)
    self.native_render_count = (self.native_render_count or 0) + 1
    self.native_last_render = {
        start_row_idx = start_row_idx,
        end_row_idx = end_row_idx,
        fgcolor = self.fgcolor,
        bgcolor = self.bgcolor,
    }
    if self.throw_render then error("forced native render failure") end
    local opaque = {}
    for index, coverage in ipairs(self.coverage) do
        opaque[index] = blend(asRGB(self.bgcolor), self.fgcolor, coverage)
    end
    self._bb = sourceBuffer(self.coverage, opaque)
end
function TextBoxWidget:paintTo(dst, x, y)
    self.native_paint_count = (self.native_paint_count or 0) + 1
    self.dimen.x, self.dimen.y = x, y
    dst:blitFrom(self._bb, x, y, 0, 0, self.width, self._bb:getHeight())
end
function TextBoxWidget:update()
    self.update_count = (self.update_count or 0) + 1
    self:_renderText(self.start_row_idx or 1, self.end_row_idx or 1)
end
function TextBoxWidget:setText(text)
    self.text = text
    self.set_text_count = (self.set_text_count or 0) + 1
    self:update()
end
function TextBoxWidget:free()
    self.free_count = (self.free_count or 0) + 1
    self._bb = nil
end
function TextBoxWidget:scrollDown()
    self.scroll_count = (self.scroll_count or 0) + 1
    self:_renderText(2, 2)
end
package.preload["ui/widget/textboxwidget"] = function() return TextBoxWidget end

local NativeRender, NativePaint = TextBoxWidget._renderText, TextBoxWidget.paintTo
local NativeUpdate, NativeSetText, NativeFree = TextBoxWidget.update, TextBoxWidget.setText, TextBoxWidget.free
local AppDockText = dofile(plugin_dir .. "appdock_text.lua")
local TransparentTextBoxWidget = AppDockText.TextBoxWidget

assert(TransparentTextBoxWidget ~= TextBoxWidget, "the transparent widget must be a local subclass")
assert(TextBoxWidget._renderText == NativeRender and TextBoxWidget.paintTo == NativePaint,
    "loading must not monkeypatch the native class")
assert(TransparentTextBoxWidget.update == NativeUpdate and TransparentTextBoxWidget.setText == NativeSetText
    and TransparentTextBoxWidget.free == NativeFree,
    "update, setText and free must remain inherited native methods")

local background = rgb(23, 67, 123)
local coverage = { 0, 64, 128, 255 }
local function assertMaskPaint(foreground, expects_rgb)
    local widget = TransparentTextBoxWidget:new{
        width = #coverage,
        coverage = coverage,
        fgcolor = foreground,
        bgcolor = rgb(210, 40, 70),
    }
    widget:_renderText(3, 7)
    assert(widget._appdock_transparent_text, "readonly text must be rendered into a mask")
    assert(widget.native_last_render.fgcolor == WHITE and widget.native_last_render.bgcolor == BLACK,
        "mask cache must be native white glyphs on black whitespace")
    assert(widget.fgcolor == foreground, "foreground must be restored after mask rendering")
    local dst = destination(#coverage, background)
    widget:paintTo(dst, 0, 0)
    assert(samePixel(dst.pixels[1], background), "black mask whitespace must leave a coloured background untouched")
    for index = 2, #coverage do
        assert(samePixel(dst.pixels[index], blend(background, foreground, coverage[index])),
            "antialias coverage must compose the requested foreground exactly")
    end
    if expects_rgb then
        assert(dst.rgb_calls == 1 and dst.color_calls == 0, "colour foreground must use colorblitFromRGB32")
    else
        assert(dst.color_calls == 1 and dst.rgb_calls == 0, "Color8 foreground must use colorblitFrom")
    end
    assert(widget.dimen.x == 0 and widget.dimen.y == 0, "paint must update dimen to actual destination coordinates")
end

assertMaskPaint(WHITE, false)
assertMaskPaint(BLACK, false)
assertMaskPaint(rgb(200, 31, 109), true)

local empty = TransparentTextBoxWidget:new{ width = 3, coverage = { 0, 0, 0 }, fgcolor = WHITE, bgcolor = BLACK }
empty:_renderText(1, 1)
local empty_dst = destination(3, background)
empty:paintTo(empty_dst, 0, 0)
for index = 1, 3 do
    assert(samePixel(empty_dst.pixels[index], background), "empty text must remain completely transparent")
end

local lifecycle = TransparentTextBoxWidget:new{ width = 1, coverage = { 255 }, fgcolor = WHITE, bgcolor = BLACK }
lifecycle:setText("new text")
lifecycle:update()
lifecycle:free()
assert(lifecycle.set_text_count == 1 and lifecycle.update_count == 2 and lifecycle.free_count == 1,
    "native setText, update and free must keep their lifecycle semantics")

local fallback = TransparentTextBoxWidget:new{ width = #coverage, coverage = coverage, fgcolor = BLACK, bgcolor = WHITE }
fallback:_renderText(4, 6)
local fallback_dst = destination(#coverage, background, false)
fallback:paintTo(fallback_dst, 9, 11)
assert(fallback.native_render_count == 2 and fallback.native_paint_count == 1,
    "missing compositor API must rebuild an opaque native cache and native-paint it")
assert(fallback.native_last_render.fgcolor == BLACK and fallback.native_last_render.bgcolor == WHITE,
    "opaque fallback must explicitly restore original colours")
assert(fallback_dst.opaque_calls == 1 and fallback.dimen.x == 9 and fallback.dimen.y == 11,
    "opaque fallback must paint at the requested coordinates")

local function assertNativeOnly(extra)
    local args = { width = 1, coverage = { 255 }, fgcolor = WHITE, bgcolor = BLACK }
    for key, value in pairs(extra) do args[key] = value end
    local widget = TransparentTextBoxWidget:new(args)
    widget:_renderText(1, 1)
    assert(not widget._appdock_transparent_text, "interactive/image/measurement text must keep native rendering")
    assert(widget.native_last_render.fgcolor == WHITE and widget.native_last_render.bgcolor == BLACK,
        "native-only modes must preserve their original foreground/background")
    local dst = destination(1, background)
    widget:paintTo(dst, 2, 4)
    assert(dst.opaque_calls == 1 and dst.color_calls == 0 and dst.rgb_calls == 0,
        "native-only modes must use the opaque native paint path")
end
assertNativeOnly{ editable = true }
assertNativeOnly{ images = {} }
assertNativeOnly{ select_mode = true }
assertNativeOnly{ highlight_text_selection = true }
assertNativeOnly{ for_measurement_only = true }

local broken = TransparentTextBoxWidget:new{ width = 1, coverage = { 255 }, fgcolor = rgb(3, 4, 5), bgcolor = rgb(6, 7, 8), throw_render = true }
local ok = pcall(function() broken:_renderText(1, 1) end)
assert(not ok and broken.fgcolor.r == 3 and broken.bgcolor.r == 6,
    "renderer errors must restore both original colours")

local existing = TextBoxWidget:new{ width = 1, coverage = { 255 }, fgcolor = WHITE, bgcolor = rgb(8, 9, 10) }
local original_bgcolor = existing.bgcolor
assert(AppDockText.makeTransparent(nil) == nil and AppDockText.makeTransparent("not an object") == nil,
    "makeTransparent must accept objects only")
assert(AppDockText.makeTransparent(existing) == existing and existing.update_count == 1,
    "an existing TextBox instance must be updated exactly once")
assert(existing.bgcolor == original_bgcolor and rawget(existing, "_renderText") ~= nil and rawget(existing, "paintTo") ~= nil,
    "instance adaptation must retain bgcolor and install only instance methods")
assert(TextBoxWidget._renderText == NativeRender and TextBoxWidget.paintTo == NativePaint,
    "makeTransparent must not mutate the global native class")
existing:paintTo(destination(1, background), 0, 0)

local scroll_child = TextBoxWidget:new{ width = 1, coverage = { 255 }, fgcolor = WHITE, bgcolor = BLACK }
local scroll = { text_widget = scroll_child }
assert(AppDockText.makeTransparent(scroll) == scroll_child and scroll_child.update_count == 1,
    "ScrollTextWidget-like objects must adapt only their text_widget once")
assert(AppDockText.makeTransparent(scroll) == scroll_child and scroll_child.update_count == 1,
    "instance adaptation must be idempotent")

local custom = AppDockText.textBox({ width = 1, coverage = { 255 }, fgcolor = BLACK }, WHITE)
assert(custom.bgcolor == WHITE and getmetatable(custom) == TransparentTextBoxWidget,
    "textBox helper must construct the local subclass and retain fallback background")

print("appdock_text tests: OK")
