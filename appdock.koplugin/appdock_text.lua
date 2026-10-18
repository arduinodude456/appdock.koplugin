-- Transparent text rendering for AppDock text boxes.
-- This deliberately extends (and never changes) KOReader's TextBoxWidget.
local Blitbuffer = require("ffi/blitbuffer")
local NativeTextBoxWidget = require("ui/widget/textboxwidget")

local TransparentTextBoxWidget = NativeTextBoxWidget:extend{}

local function canUseTransparentText(widget)
    return not widget.editable
        and not widget.images
        and not widget.select_mode
        and not widget.highlight_text_selection
        and not widget.for_measurement_only
end

local function setDimenPosition(widget, x, y)
    if widget.dimen then
        widget.dimen.x = x
        widget.dimen.y = y
    end
end

-- Calling through pcall is intentional: temporary colours must never leak when
-- a font or renderer raises an error.
local function callNativeRender(widget, native_render, start_row_idx, end_row_idx, fgcolor, bgcolor)
    local previous_fgcolor, previous_bgcolor = widget.fgcolor, widget.bgcolor
    widget.fgcolor, widget.bgcolor = fgcolor, bgcolor
    local ok, err = pcall(native_render, widget, start_row_idx, end_row_idx)
    widget.fgcolor, widget.bgcolor = previous_fgcolor, previous_bgcolor
    if not ok then
        error(err, 0)
    end
end

local function renderOpaque(widget, native_render, start_row_idx, end_row_idx, fgcolor, bgcolor)
    -- Explicitly install the original colours at this callsite.  This matters
    -- after a previously cached white-on-black alpha mask.
    widget._appdock_transparent_text = nil
    return callNativeRender(widget, native_render, start_row_idx, end_row_idx, fgcolor, bgcolor)
end

local function renderText(widget, native_render, start_row_idx, end_row_idx)
    local original_fgcolor, original_bgcolor = widget.fgcolor, widget.bgcolor

    if not canUseTransparentText(widget) then
        return renderOpaque(widget, native_render, start_row_idx, end_row_idx,
            original_fgcolor, original_bgcolor)
    end

    if Blitbuffer.COLOR_WHITE == nil or Blitbuffer.COLOR_BLACK == nil then
        return renderOpaque(widget, native_render, start_row_idx, end_row_idx,
            original_fgcolor, original_bgcolor)
    end

    -- KOReader's native renderer creates and caches self._bb.  White glyphs on
    -- black produce exactly the coverage mask expected by colorblitFrom*.
    callNativeRender(widget, native_render, start_row_idx, end_row_idx,
        Blitbuffer.COLOR_WHITE, Blitbuffer.COLOR_BLACK)
    widget._appdock_transparent_text = true
    widget._appdock_transparent_start_row_idx = start_row_idx
    widget._appdock_transparent_end_row_idx = end_row_idx
    widget._appdock_transparent_fgcolor = original_fgcolor
    widget._appdock_transparent_bgcolor = original_bgcolor
end

local function getMethod(object, name)
    local ok, method = pcall(function() return object[name] end)
    if ok and type(method) == "function" then
        return method
    end
end

local function maskHeight(mask)
    local get_height = getMethod(mask, "getHeight")
    if not get_height then return nil end
    local ok, height = pcall(get_height, mask)
    if ok then return height end
end

local function compositorFor(destination, fgcolor)
    if type(Blitbuffer.isColor8) ~= "function" then return nil end
    local ok, is_color8 = pcall(Blitbuffer.isColor8, fgcolor)
    if not ok then return nil end

    if is_color8 then
        return getMethod(destination, "colorblitFrom")
    end
    return getMethod(destination, "colorblitFromRGB32")
end

local function rerenderAndPaintOpaque(widget, native_render, native_paint,
        destination, x, y)
    local start_row_idx = widget._appdock_transparent_start_row_idx
    local end_row_idx = widget._appdock_transparent_end_row_idx
    local fgcolor = widget._appdock_transparent_fgcolor
    local bgcolor = widget._appdock_transparent_bgcolor

    -- A transparent cache always records these values.  Keep the native paint
    -- fallback safe even with a third-party TextBox implementation.
    if start_row_idx ~= nil and end_row_idx ~= nil then
        renderOpaque(widget, native_render, start_row_idx, end_row_idx, fgcolor, bgcolor)
    else
        widget._appdock_transparent_text = nil
    end
    setDimenPosition(widget, x, y)
    return native_paint(widget, destination, x, y)
end

local function paintText(widget, native_render, native_paint, destination, x, y)
    setDimenPosition(widget, x, y)
    if not widget._appdock_transparent_text then
        return native_paint(widget, destination, x, y)
    end

    local mask = widget._bb
    local fgcolor = widget._appdock_transparent_fgcolor
    local height = mask and maskHeight(mask)
    local compositor = destination and compositorFor(destination, fgcolor)
    if not mask or not height or not compositor then
        return rerenderAndPaintOpaque(widget, native_render, native_paint, destination, x, y)
    end

    local ok = pcall(compositor, destination, mask, x, y, 0, 0, widget.width, height, fgcolor)
    if ok then
        return
    end

    -- Old/partial Blitbuffer builds may expose a method which still cannot
    -- compose this buffer.  Rebuild the normal opaque cache rather than leave
    -- a partially-painted mask on screen.
    return rerenderAndPaintOpaque(widget, native_render, native_paint, destination, x, y)
end

local native_render = NativeTextBoxWidget._renderText
local native_paint = NativeTextBoxWidget.paintTo

function TransparentTextBoxWidget:_renderText(start_row_idx, end_row_idx)
    return renderText(self, native_render, start_row_idx, end_row_idx)
end

function TransparentTextBoxWidget:paintTo(destination, x, y)
    return paintText(self, native_render, native_paint, destination, x, y)
end

local function installOnInstance(widget)
    if type(widget) ~= "table" then return nil end
    if widget._appdock_transparent_text_installed then return widget end

    local instance_render = widget._renderText
    local instance_paint = widget.paintTo
    if type(instance_render) ~= "function" or type(instance_paint) ~= "function" then
        return nil
    end

    -- Keep the captured methods only on this object.  No TextBoxWidget or
    -- ScrollTextWidget class is patched.
    widget._appdock_transparent_text_installed = true
    widget._appdock_transparent_native_render = instance_render
    widget._appdock_transparent_native_paint = instance_paint
    widget._renderText = function(self, start_row_idx, end_row_idx)
        return renderText(self, self._appdock_transparent_native_render,
            start_row_idx, end_row_idx)
    end
    widget.paintTo = function(self, destination, x, y)
        return paintText(self, self._appdock_transparent_native_render,
            self._appdock_transparent_native_paint, destination, x, y)
    end

    -- Existing ScrollTextWidget.text_widget instances already have an opaque
    -- cache.  Rebuild it once as a mask; retain their supplied bgcolor for all
    -- native fallback paths.
    if type(widget.update) == "function" then
        widget:update()
    end
    return widget
end

local M = {
    TextBoxWidget = TransparentTextBoxWidget,
}

-- Accept either a TextBoxWidget itself or a ScrollTextWidget-like object that
-- owns its TextBoxWidget in .text_widget.
function M.makeTransparent(widget)
    if type(widget) ~= "table" then return nil end
    return installOnInstance(widget.text_widget or widget)
end

function M.textBox(options, background)
    local args = {}
    for key, value in pairs(options or {}) do
        args[key] = value
    end
    if background ~= nil then
        args.bgcolor = background
    end
    return TransparentTextBoxWidget:new(args)
end

return M
