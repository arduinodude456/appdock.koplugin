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
local TextWidget = Widget:extend({ setText = function(self, text) self.text = text end })
local ui = { scheduled = {}, dirty_modes = {} }
function ui:setDirty(_, mode) table.insert(self.dirty_modes, mode) end
function ui:scheduleIn(delay, callback) table.insert(self.scheduled, { delay = delay, callback = callback }) end
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
package.preload["ui/widget/horizontalgroup"] = function() return Widget end
package.preload["ui/widget/container/inputcontainer"] = function() return InputContainer end
package.preload["ui/widget/textwidget"] = function() return TextWidget end
package.preload["ui/uimanager"] = function() return ui end
package.preload["ui/widget/verticalgroup"] = function() return VerticalGroup end
package.preload["ui/widget/verticalspan"] = function() return Widget end
package.preload["gettext"] = function() return function(text) return text end end

local Keyboard = dofile(plugin_dir .. "appdock_keyboard.lua")
local keyboard = Keyboard:new{}
assert(keyboard.width == 900 and keyboard.dimen.w == 900, "Keyboard spans the full screen width")
assert(keyboard.dimen.x == 0 and keyboard.dimen.y + keyboard.dimen.h == 1200, "Keyboard is anchored to the bottom edge")
assert(keyboard.shift and keyboard.letter_keys[1].key.label == "Q", "Shift starts active and displays uppercase labels")
keyboard:_press("Q")
assert(keyboard.value == "Q" and not keyboard.shift and keyboard.letter_keys[1].key.label == "q", "Typing a letter consumes Shift and updates key labels")
keyboard:_press("W")
assert(keyboard.value == "Qw", "Unshifted input is lowercase")
keyboard.shift_key:onTapKey()
assert(keyboard.shift and keyboard.letter_keys[1].key.label == "Q", "Shift can be re-enabled and is visibly active")
local tapped_key = keyboard.letter_keys[2].key
local before = keyboard.value
tapped_key:onTapKey()
assert(tapped_key.pressed and keyboard.value == before .. "W", "A tapped key shows temporary pressed feedback and enters its own character")
assert(ui.dirty_modes[#ui.dirty_modes] == "fast", "Key entry requests a fast partial refresh")
assert(ui.scheduled[#ui.scheduled].delay == 0.12, "Pressed feedback uses a short non-blocking interval")
for _, item in ipairs(ui.scheduled) do item.callback() end
assert(not tapped_key.pressed, "Pressed feedback clears after its short display interval")
keyboard.symbol_key:onTapKey()
assert(keyboard.symbols_page and keyboard.symbol_key.label == "ABC", "Symbol page opens and offers a way back to letters")
local umlaut_key
for _, item in ipairs(keyboard.letter_keys) do
    if item.lower == "ä" then umlaut_key = item.key; break end
end
assert(umlaut_key and umlaut_key.label == "ä", "Symbol page includes German special characters")
keyboard.shift_key:onTapKey()
assert(umlaut_key.label == "Ä", "Shift updates case on the symbol page too")
umlaut_key:onTapKey()
assert(keyboard.value == "QwWÄ", "Special character is entered with the active case")
keyboard:_press("←")
assert(keyboard.value == "QwW", "Backspace removes a complete UTF-8 special character")
keyboard.symbol_key:onTapKey()
assert(not keyboard.symbols_page and keyboard.symbol_key.label == "?123", "Keyboard returns to the letter page")

local dialog = { title = "AppDock PIN", input_hint = "PIN", input_type = "number", text = "", _input_widget = {} }
function dialog:getInputText() return self.text end
function dialog:setInputText(value) self.text = value end
assert(Keyboard.attach(dialog, { secure = true }), "AppDock dialog accepts the keyboard adapter")
assert(dialog._input_widget.onTapTextBox(), "Tapping the dialog field opens the AppDock keyboard")
local numeric_keyboard = ui.shown
assert(numeric_keyboard.numeric_only and numeric_keyboard.secure, "Number dialogs use the numeric layout and secure display")
assert(numeric_keyboard.width == 900 and numeric_keyboard.dimen.x == 0 and numeric_keyboard.dimen.y + numeric_keyboard.dimen.h == 1200, "Numeric keyboard also spans the full width at the bottom")
numeric_keyboard:_press("1")
numeric_keyboard:_press("2")
assert(numeric_keyboard.display.text == "••", "Secure values are masked")
numeric_keyboard.on_submit(numeric_keyboard.value)
assert(dialog.text == "12" and ui.closed == numeric_keyboard, "Done returns the value to the original dialog")

print("AppDock keyboard test: OK")
