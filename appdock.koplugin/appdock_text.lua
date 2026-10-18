-- Safe compatibility facade for Store DApps.
--
-- The custom transparent TextBox subclass introduced in AppDock 8.2.14 caused
-- Store DApps to fail while building panes on some KOReader devices. Keep the
-- API stable, but return KOReader's native widget until the mask renderer can
-- be validated against those runtimes. DApps pass an explicit surface bgcolor
-- so text remains legible during this compatibility fallback.
local NativeTextBoxWidget = require("ui/widget/textboxwidget")

local M = {
    TextBoxWidget = NativeTextBoxWidget,
}

-- Compatibility no-op: callers may still request transparent adaptation, but
-- this release deliberately leaves the KOReader widget and its draw methods
-- untouched.
function M.makeTransparent(widget)
    if type(widget) ~= "table" then return nil end
    return widget.text_widget or widget
end

function M.textBox(options, background)
    local args = {}
    for key, value in pairs(options or {}) do
        args[key] = value
    end
    if background ~= nil then
        args.bgcolor = background
    end
    return NativeTextBoxWidget:new(args)
end

return M
