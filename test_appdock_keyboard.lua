local plugin_dir = os.getenv("APPDOCK_PLUGIN_DIR") or "./appdock.koplugin/"

local function class(prototype)
    prototype = prototype or {}
    prototype.__index = prototype
    function prototype:extend(child)
        child = child or {}
        child.__index = child
        setmetatable(child, { __index = self })
        return child
    end
    function prototype:new(args)
        local instance = setmetatable(args or {}, self)
        if instance.init then instance:init() end
        return instance
    end
    return prototype
end

local Widget = class({})
local InputContainer = Widget:extend({ paintTo = function() return true end })
local VerticalGroup = Widget:extend({
    getSize = function(self)
        local height = 0
        for _, child in ipairs(self) do
            height = height + (child.height or (child.dimen and child.dimen.h) or 22)
        end
        return { w = 500, h = height }
    end,
})
local TextWidget = Widget:extend({
    setText = function(self, text) self.text = text end,
    getSize = function() return { w = 120, h = 20 } end,
})
local ui = { scheduled = {}, dirty_modes = {}, next_ticks = {} }
function ui:setDirty(_, mode) table.insert(self.dirty_modes, mode) end
function ui:scheduleIn(delay, callback) table.insert(self.scheduled, { delay = delay, callback = callback }) end
function ui:unschedule(callback)
    for index = #self.scheduled, 1, -1 do if self.scheduled[index].callback == callback then table.remove(self.scheduled, index) end end
end
function ui:nextTick(callback) table.insert(self.next_ticks, callback) end
function ui:show(widget) self.shown = widget end
function ui:close(widget) self.closed = widget end

package.preload["ffi/blitbuffer"] = function() return { COLOR_BLACK = 0, COLOR_WHITE = 1 } end
package.preload["ui/widget/container/centercontainer"] = function() return Widget end
package.preload["device"] = function()
    return {
        screen = {
            scaleBySize = function(_, value) return value end,
            getWidth = function() return 900 end,
            getHeight = function() return 1200 end,
        },
        hasKeys = function() return false end,
    }
end
package.preload["ui/font"] = function() return { getFace = function(_, name, size) return { name = name, size = size } end } end
package.preload["ui/widget/container/framecontainer"] = function() return Widget end
package.preload["ui/geometry"] = function() return { new = function(_, values) return values end } end
package.preload["ui/gesturerange"] = function() return { new = function(_, values) return values end } end
package.preload["ui/widget/horizontalspan"] = function() return Widget end
package.preload["ui/widget/horizontalgroup"] = function() return Widget end
package.preload["ui/widget/container/inputcontainer"] = function() return InputContainer end
package.preload["ui/widget/container/leftcontainer"] = function() return Widget end
package.preload["ui/widget/textwidget"] = function() return TextWidget end
package.preload["ui/uimanager"] = function() return ui end
package.preload["ui/widget/verticalgroup"] = function() return VerticalGroup end
package.preload["ui/widget/verticalspan"] = function() return Widget end
package.preload["gettext"] = function() return function(text) return text end end
package.preload["appdock_suggestions"] = function() error("database unavailable during boot") end

local Keyboard = dofile(plugin_dir .. "appdock_keyboard.lua")
local keyboard = Keyboard:new{}
assert(keyboard.width == 900 and keyboard.dimen.w == 900, "Keyboard spans the full screen width")
assert(keyboard.dimen.x == 0 and keyboard.dimen.y + keyboard.dimen.h == 1200, "Keyboard is anchored to the bottom edge")
assert(keyboard.shift and keyboard.letter_keys[1].key.label == "Q", "Shift starts active and displays uppercase labels")
assert(keyboard.letter_keys[1].key.height == 93 and keyboard.shift_key, "Keyboard uses screen-scaled larger keys and exposes Shift/Caps Lock")
assert(keyboard.suggestion_keys[1].label ~= "…", "Keyboard must fall back safely when the database is unavailable")
assert(keyboard.dimen.h > 0 and #keyboard.suggestion_keys == 3, "Alphabetic keyboard must show three suggestion buttons")
keyboard:_typeLetter("a")
assert(keyboard.suggestion_keys[1].label ~= "…", "Database suggestions update with the typed prefix")
keyboard.value = ""
keyboard.shift = true
keyboard:_update()
keyboard:_typeLetter("q")
assert(keyboard.value == "Q" and not keyboard.shift and keyboard.letter_keys[1].key.label == "q", "Typing a letter consumes Shift and updates key labels")
keyboard:_typeLetter("w")
assert(keyboard.value == "Qw", "Unshifted input is lowercase")
keyboard.shift_key:onTapKey()
assert(keyboard.shift and keyboard.letter_keys[1].key.label == "Q", "Shift can be re-enabled and is visibly active")
keyboard.shift_key:onHoldKey()
assert(keyboard.caps_lock and keyboard.shift_key.active and keyboard.letter_keys[1].key.label == "Q", "Caps Lock stays visibly active after a long Shift press")
keyboard.shift_key:onHoldKey()
assert(not keyboard.caps_lock, "Caps Lock can be disabled again")
local tapped_item = keyboard.letter_keys[2]
local tapped_key = tapped_item.key
local before = keyboard.value
local expected_letter = (keyboard.caps_lock or keyboard.shift) and tapped_item.upper or tapped_item.lower
tapped_key:onTapKey()
assert(keyboard.value == before .. expected_letter, "A tapped letter enters its own character")
local unicode_keyboard = Keyboard:new{ value = "QwWÄ" }
unicode_keyboard:_backspace()
assert(unicode_keyboard.value == "QwW", "Backspace removes a complete UTF-8 special character")

local dialog = { title = "AppDock PIN", input_hint = "PIN", input_type = "number", text = "", _input_widget = {} }
function dialog:getInputText() return self.text end
function dialog:setInputText(value) self.text = value end
local live_value
assert(Keyboard.attach(dialog, { secure = true, on_change = function(value) live_value = value end }), "AppDock dialog accepts the keyboard adapter")
assert(dialog._input_widget.onTapTextBox(), "Tapping the dialog field opens the AppDock keyboard")
local numeric_keyboard = ui.shown
assert(numeric_keyboard.numeric_only and numeric_keyboard.secure, "Number dialogs use the numeric layout and secure display")
assert(numeric_keyboard.on_cancel and numeric_keyboard.on_submit, "Keyboard must expose explicit cancel and submit actions")
assert(numeric_keyboard.width == 900 and numeric_keyboard.dimen.x == 0 and numeric_keyboard.dimen.y + numeric_keyboard.dimen.h == 1200, "Numeric keyboard also spans the full width at the bottom")
assert(ui.closed == dialog, "The KOReader input dialog is closed before the AppDock keyboard is shown")
ui.closed = nil
local multiline_dialog = { title = "Markdown", input_hint = "Text", text = "", _input_widget = {} }
function multiline_dialog:getInputText() return self.text end
function multiline_dialog:setInputText(value) self.text = value end
assert(Keyboard.attach(multiline_dialog, { multiline = true }), "AppDock dialog adapter accepts multiline input")
assert(multiline_dialog._input_widget.onTapTextBox(), "Multiline dialog opens the AppDock keyboard")
assert(ui.shown.multiline and ui.shown.submit_key, "Dialog adapter forwards multiline mode and keeps a separate submit key")
ui.closed = nil
local cancel_calls = 0
local cancel_keyboard
cancel_keyboard = Keyboard:new{ on_cancel = function() cancel_calls = cancel_calls + 1; ui:close(cancel_keyboard) end }
cancel_keyboard.cancel_key:onTapKey()
assert(cancel_calls == 0 and ui.closed == nil and #ui.next_ticks == 1, "Cancel must wait until the keyboard key-dispatch callback has returned")
table.remove(ui.next_ticks, 1)()
assert(cancel_calls == 1 and ui.closed == cancel_keyboard, "Deferred Cancel must close the keyboard once without re-entering its key callback")
numeric_keyboard:_insert("1")
numeric_keyboard:_insert("2")
for _, item in ipairs(ui.scheduled) do item.callback() end
assert(numeric_keyboard.display.text:find("••", 1, true) == 1 and live_value == "12" and dialog.text == "12", "Secure values and the target field update live")
numeric_keyboard.on_submit(numeric_keyboard.value)
assert(dialog.text == "12" and ui.closed == numeric_keyboard, "Done returns the value to the original dialog")

local multiline_keyboard = Keyboard:new{ value = "erste", multiline = true }
assert(multiline_keyboard.multiline and multiline_keyboard.submit_key, "Multiline keyboard exposes a distinct top-bar submit key")
multiline_keyboard:_doneItem().callback()
assert(multiline_keyboard.value == "erste\n", "The return key inserts a line break instead of submitting")
multiline_keyboard:_pasteText("zweite\r\ndritte")
assert(multiline_keyboard.value == "erste\nzweite\ndritte", "Multiline paste preserves and normalizes line breaks")
local multiline_submitted
multiline_keyboard.on_submit = function(value) multiline_submitted = value end
multiline_keyboard.submit_key:onTapKey()
table.remove(ui.next_ticks, 1)()
assert(multiline_submitted == "erste\nzweite\ndritte", "The separate Done key submits the full multiline value")

assert(keyboard:_displayText():sub(1, 1) == "Q", "Short values remain fully visible")
assert(Keyboard.setLanguage("de") == "de" and Keyboard.getLanguage() == "de", "Keyboard language can be set persistently by AppDock Settings")
assert(Keyboard.isEnabled(), "The AppDock keyboard must remain enabled by default")
local native_dialog = { text = "", _input_widget = {}, appdock_keyboard_attached = nil }
function native_dialog:getInputText() return self.text end
function native_dialog:setInputText(value) self.text = value end
function native_dialog:onShowKeyboard() self.native_keyboard_opened = true; return true end
assert(Keyboard.setEnabled(false) == false and not Keyboard.isEnabled(), "AppDock Settings must be able to disable the custom keyboard")
assert(not Keyboard.attach(native_dialog) and not native_dialog.appdock_keyboard_attached,
    "When disabled, the AppDock adapter must leave the native dialog untouched")
assert(native_dialog:onShowKeyboard() and native_dialog.native_keyboard_opened,
    "A native dialog must keep its KOReader keyboard when the AppDock keyboard is disabled")
assert(Keyboard.setEnabled(true) and Keyboard.isEnabled(), "The custom keyboard must be re-enableable")
assert(Keyboard._test.resolvedLanguage("de") == "de" and Keyboard._test.resolvedLanguage("unsupported") == "en", "Keyboard resolves explicit and automatic languages safely")
print("AppDock keyboard test: OK")
