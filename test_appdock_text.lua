-- Tests for the AppDock text compatibility facade. No KOReader runtime needed.
local plugin_dir = os.getenv("APPDOCK_PLUGIN_DIR")
if not plugin_dir then
    local source = debug.getinfo(1, "S").source
    source = source:sub(1, 1) == "@" and source:sub(2) or source
    plugin_dir = (source:match("^(.*[/\\])") or "./") .. "appdock.koplugin/"
end
if plugin_dir:sub(-1) ~= "/" then plugin_dir = plugin_dir .. "/" end

local NativeTextBoxWidget = { new_calls = 0 }
function NativeTextBoxWidget:new(args)
    self.new_calls = self.new_calls + 1
    local widget = {}
    for key, value in pairs(args or {}) do widget[key] = value end
    widget.native_widget = true
    return widget
end
package.preload["ui/widget/textboxwidget"] = function() return NativeTextBoxWidget end

local AppDockText = dofile(plugin_dir .. "appdock_text.lua")
assert(AppDockText.TextBoxWidget == NativeTextBoxWidget,
    "The compatibility facade must expose KOReader's native TextBoxWidget")

local existing = { bgcolor = "surface", paintTo = function() end }
local original_paint = existing.paintTo
assert(AppDockText.makeTransparent(existing) == existing,
    "The compatibility adaptation must leave a native widget usable")
assert(existing.paintTo == original_paint and existing.bgcolor == "surface",
    "The fallback must not replace methods or colors on a widget")
assert(AppDockText.makeTransparent(nil) == nil and AppDockText.makeTransparent("bad") == nil,
    "Invalid values must remain harmless")

local child = { bgcolor = "panel" }
assert(AppDockText.makeTransparent({ text_widget = child }) == child,
    "ScrollTextWidget-like inputs must still return their native text widget")

local options = { text = "hello", width = 120, bgcolor = "bubble" }
local widget = AppDockText.textBox(options, "parent-surface")
assert(widget.native_widget and widget.text == "hello" and widget.width == 120,
    "textBox must create a native KOReader widget and preserve its options")
assert(widget.bgcolor == "parent-surface" and options.bgcolor == "bubble",
    "The explicit fallback surface must be applied without mutating the caller's options")
print("appdock_text compatibility tests: OK")
