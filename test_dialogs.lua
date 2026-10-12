-- AppDock custom-dialog tests: the range callback, callbacks and keyboard route must stay usable.
local plugin_dir = os.getenv("APPDOCK_PLUGIN_DIR") or "/home/ubuntu/appdock.koplugin/appdock.koplugin/"

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
        local instance = setmetatable(args or {}, self)
        if instance.init then instance:init() end
        return instance
    end
    return c
end

local Widget = class()
local InputContainer = Widget:extend({})
local TextWidget = Widget:extend({})
function TextWidget:init()
    self.dimen = { w = self.max_width or 120,
        h = self.text == "" and 0 or (self.face and self.face.size or 12) + 4 }
end
function TextWidget:getSize() return self.dimen end
function TextWidget:paintTo(bb, x, y)
    if bb and bb.text_calls then
        bb.text_calls[#bb.text_calls + 1] = { fgcolor = self.fgcolor, text = self.text,
            last_fill = bb.last_fill, x = x, y = y }
    end
end

local scheduled, closed = {}, {}
local shown = {}
local UIManager = {
    scheduleIn = function(_, seconds, callback) scheduled[#scheduled + 1] = { seconds = seconds, callback = callback } end,
    unschedule = function() end,
    close = function(_, widget)
        closed[#closed + 1] = widget
        if widget.onCloseWidget then widget:onCloseWidget() end
    end,
    show = function(_, widget) shown[#shown + 1] = widget end,
    setDirty = function() end,
}

package.preload["ffi/blitbuffer"] = function()
    return { COLOR_WHITE = 1, COLOR_BLACK = 2, COLOR_GRAY_8 = 3, COLOR_LIGHT_GRAY = 4 }
end
package.preload["device"] = function()
    return {
        screen = {
            getSize = function() return { w = 600, h = 800 } end,
            scaleBySize = function(_, value) return value end,
        },
        hasKeys = function() return false end,
    }
end
package.preload["ui/font"] = function() return { getFace = function(_, _, size) return { size = size or 12 } end } end
package.preload["ui/geometry"] = function() return { new = function(_, args) return args end } end
-- KOReader GestureRange stores the callback in `range`; it is not a Geom.
package.preload["ui/gesturerange"] = function() return { new = function(_, args) return args end } end
package.preload["ui/widget/container/inputcontainer"] = function() return InputContainer end
package.preload["ui/widget/textwidget"] = function() return TextWidget end
package.preload["ui/uimanager"] = function() return UIManager end
package.preload["gettext"] = function() return function(text) return text end end
local appdock_keyboard_enabled = true
package.preload["appdock_keyboard"] = function()
    return {
        setEnabled = function(enabled) appdock_keyboard_enabled = enabled ~= false end,
        attach = function(widget, options)
            if not appdock_keyboard_enabled then
                widget.appdock_keyboard_options = options
                return false
            end
            widget.appdock_keyboard_attached = true
            return true
        end,
    }
end
package.preload["ui/widget/inputdialog"] = function()
    local NativeInputDialog = InputContainer:extend({})
    function NativeInputDialog:getInputText() return self.input or "" end
    function NativeInputDialog:onShowKeyboard() self.native_keyboard_opened = true; return true end
    return NativeInputDialog
end

local Dialogs = dofile(plugin_dir .. "appdock_dialogs.lua")
local paints = 0
local bb = {
    rectangles = {}, text_calls = {},
    paintRect = function(self, x, y, width, height, color)
        paints = paints + 1
        self.last_fill = color
        self.rectangles[#self.rectangles + 1] = { x = x, y = y, w = width, h = height, color = color }
    end,
}
local info = Dialogs.InfoMessage:new{ title = "Status", text = "Connecting to Wi-Fi…", duration = 0 }
local paint_ok, paint_error = pcall(info.paintTo, info, bb, 0, 0)
assert(paint_ok, "A custom status dialog must paint without treating GestureRange.range as a geometry: " .. tostring(paint_error))
assert(paints > 0 and info.ges_events.TapAppDockModal[1].range() == info.dimen,
    "The status dialog must paint and its tap callback must resolve to the full-screen geometry")
assert(bb.text_calls[1] and bb.text_calls[1].fgcolor == 2 and bb.text_calls[1].last_fill == 4,
    "Dialog title text must be black over a light-gray title surface, never black over black")
assert(info:onKeyRepeat() == true, "A custom AppDock modal must consume held page-key repeats")
local update_text = "This is a deliberately long update description that must wrap inside the modal instead of running past the card width."
local update_dialog = Dialogs.Modal:new{ title = "AppDock updated", text = update_text }
assert(update_dialog.body_widget.text:find("\n", 1, true), "Update dialog text must be explicitly wrapped to the modal width")
assert(#update_dialog.body_widget.lines > 1, "Update dialog wrapped lines must each have their own single-line TextWidget")
local painted_lines_before = #bb.text_calls
update_dialog.body_widget:paintTo(bb, 10, 20)
assert(#bb.text_calls - painted_lines_before == #update_dialog.body_widget.lines,
    "Update dialog descriptions must paint every wrapped line instead of passing newlines to one TextWidget")
for index, line in ipairs(update_dialog.body_widget.lines) do
    assert(bb.text_calls[painted_lines_before + index].text == line.text,
        "Each update description line must be rendered as its own text operation")
end
local expected_body_height = 0
expected_body_height = #update_dialog.body_widget.lines * update_dialog.body_widget.line_height
assert(update_dialog.body_widget:getSize().h == expected_body_height,
    "Update dialog body height must account for each wrapped line")
local paragraph_dialog = Dialogs.Modal:new{ text = "Feature summary.\n\nPage 1 of 3" }
assert(#paragraph_dialog.body_widget.lines == 3 and paragraph_dialog.body_widget.lines[2].text == "",
    "Update dialog paragraph spacing must preserve an explicit blank line")
local paragraph_lines_before = #bb.text_calls
paragraph_dialog.body_widget:paintTo(bb, 10, 30)
local first_paragraph_line = bb.text_calls[paragraph_lines_before + 1]
local blank_paragraph_line = bb.text_calls[paragraph_lines_before + 2]
local page_counter_line = bb.text_calls[paragraph_lines_before + 3]
assert(blank_paragraph_line.y - first_paragraph_line.y == paragraph_dialog.body_widget.line_height
    and page_counter_line.y - blank_paragraph_line.y == paragraph_dialog.body_widget.line_height,
    "A zero-height empty TextWidget must still advance the page counter to a separate line")

local selected = false
local picker = Dialogs.ButtonDialog:new{
    title = "Choose",
    buttons = { { { text = "First choice", callback = function() selected = true end } } },
}
assert(pcall(picker.paintTo, picker, bb, 0, 0) and #picker._hits > 0, "An AppDock selection dialog must build visible tap targets")
for _, text_call in ipairs(bb.text_calls) do
    assert(text_call.fgcolor == 2, "Every label in AppDock dialogs must use black foreground text")
end
local first_hit = picker._hits[1]
local first_fill
for _, rect in ipairs(bb.rectangles) do
    if rect.x == first_hit.x and rect.y == first_hit.y and rect.w == first_hit.w then first_fill = rect.color; break end
end
assert(first_fill == 1, "Standard action labels must be drawn on a white button surface")
local selection_hit = picker._hits[1]
assert(picker:onTapAppDockModal(nil, { pos = { x = selection_hit.x + 1, y = selection_hit.y + 1 } })
    and selected and picker._closed, "Selecting a custom dialog row must run the callback and close the modal")

local confirmed = false
local confirm = Dialogs.ConfirmBox:new{ ok_callback = function() confirmed = true end }
assert(pcall(confirm.paintTo, confirm, bb, 0, 0) and #confirm._hits == 2, "An AppDock confirmation must expose both choices")
local confirm_hit = confirm._hits[1]
confirm:onTapAppDockModal(nil, { pos = { x = confirm_hit.x + 1, y = confirm_hit.y + 1 } })
assert(confirmed and confirm._closed, "The confirmation's positive action must run through the custom tap handler")

local submitted
local input_dialog
input_dialog = Dialogs.InputDialog:new{
    title = "Name",
    input = "before",
    input_hint = "Enter a name",
    buttons = { { { text = "Save", callback = function() submitted = input_dialog:getInputText() end } } },
}
input_dialog:onShowKeyboard()
assert(input_dialog.appdock_keyboard_attached, "The custom input dialog must still attach AppDock's keyboard")
input_dialog:setInputText("after")
assert(pcall(input_dialog.paintTo, input_dialog, bb, 0, 0) and #input_dialog._hits > 0, "The custom input dialog must paint an input hit target")
local save_hit = input_dialog._hits[#input_dialog._hits]
input_dialog:onTapAppDockModal(nil, { pos = { x = save_hit.x + 1, y = save_hit.y + 1 } })
assert(submitted == "after" and input_dialog._closed, "The custom input dialog must return the entered value to its action callback")

local native_submitted
local native_fallback_dialog
native_fallback_dialog = Dialogs.InputDialog:new{
    title = "Native fallback",
    input = "before",
    input_hint = "Enter a value",
    buttons = { { { text = "Save", callback = function() native_submitted = native_fallback_dialog:getInputText() end } } },
}
package.loaded["appdock_keyboard"].setEnabled(false)
package.loaded["appdock_keyboard"].attach(native_fallback_dialog, { secure = true })
assert(native_fallback_dialog:onShowKeyboard(), "Disabling AppDock's keyboard must open the native input route")
local native_input = shown[#shown]
assert(native_input.native_keyboard_opened and native_input.title == "Native fallback" and native_input.secure,
    "The native KOReader dialog must open its own keyboard with the original title and secure-input preference")
native_input.input = "typed natively"
native_input.buttons[1][1].callback()
assert(native_fallback_dialog:getInputText() == "typed natively" and native_submitted == "typed natively",
    "The native fallback must pass its entered value back into the AppDock action")
package.loaded["appdock_keyboard"].setEnabled(true)

assert(#closed == 4, "Info, confirmation, and both input dialogs must close through UIManager")
print("AppDock custom dialog tests passed")
