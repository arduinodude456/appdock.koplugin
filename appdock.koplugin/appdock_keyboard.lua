-- AppDock-owned keyboard for AppDock-owned text input surfaces.
-- KOReader dialogs outside AppDock remain untouched.
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")

local Screen = Device.screen
local function scale(n) return Screen:scaleBySize(n) end

local Key = InputContainer:extend{ label = "", callback = nil, width = 40, height = 38 }
function Key:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self.text_widget = TextWidget:new{
        text = self.label,
        face = Font:getFace("cfont", scale(16)),
        fgcolor = Blitbuffer.COLOR_BLACK,
        padding = 0,
    }
    self.frame = FrameContainer:new{
        width = self.width, height = self.height, padding = 0,
        bordersize = scale(1), color = Blitbuffer.COLOR_BLACK,
        radius = scale(8), background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{ dimen = self.dimen, self.text_widget },
    }
    self[1] = self.frame
    self.ges_events = { TapKey = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function Key:setLabel(label)
    self.label = label
    self.text_widget:setText(label)
end

function Key:setActive(active)
    self.active = active and true or false
end

function Key:paintTo(bb, x, y)
    local range = self.ges_events.TapKey[1].range
    range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    local inverted = self.active or self.pressed
    self.frame.background = inverted and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE
    self.frame.color = Blitbuffer.COLOR_BLACK
    self.text_widget.fgcolor = inverted and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
    return InputContainer.paintTo(self, bb, x, y)
end

function Key:onTapKey()
    self._press_generation = (self._press_generation or 0) + 1
    local generation = self._press_generation
    self.pressed = true
    UIManager:setDirty(self, "fast")
    if self.callback then self.callback() end
    UIManager:scheduleIn(0.2, function()
        if self._press_generation == generation then
            self.pressed = false
            UIManager:setDirty(self, "fast")
        end
    end)
    return true
end

local Keyboard = InputContainer:extend{
    value = "",
    on_submit = nil,
    on_cancel = nil,
    title = nil,
    placeholder = nil,
    numeric_only = false,
    secure = false,
}

local function appendKey(row, key, gap)
    table.insert(row, key)
    table.insert(row, VerticalSpan:new{ width = gap })
end

function Keyboard:init()
    self.width = math.min(Screen:getWidth() - scale(24), scale(640))
    self.width = math.max(scale(280), self.width)
    self.shift = true
    self.letter_keys = {}
    self.rows = self.numeric_only and {
        { "1", "2", "3" },
        { "4", "5", "6" },
        { "7", "8", "9" },
        { "←", "0" },
    } or {
        { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" },
        { "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P" },
        { "A", "S", "D", "F", "G", "H", "J", "K", "L" },
        { "Z", "X", "C", "V", "B", "N", "M", "←" },
        { "@", ".", ",", "?", "!", ":", ";", "-", "_", "/" },
    }

    local hint = self.placeholder or _("Search apps")
    self.title_widget = self.title and TextWidget:new{
        text = self.title,
        face = Font:getFace("smallinfofont", scale(15)),
        fgcolor = Blitbuffer.COLOR_BLACK,
        bold = true,
        max_width = self.width - scale(24),
    } or nil
    self.display = TextWidget:new{
        text = self.value ~= "" and self:_displayValue() or hint,
        face = Font:getFace("smallinfofont", scale(16)),
        fgcolor = Blitbuffer.COLOR_BLACK,
        padding = scale(8),
        max_width = self.width - scale(24),
    }

    local content = {}
    if self.title_widget then
        table.insert(content, self.title_widget)
        table.insert(content, VerticalSpan:new{ height = scale(4) })
    end
    table.insert(content, self.display)
    table.insert(content, VerticalSpan:new{ height = scale(8) })

    local key_height = scale(50)
    local key_gap = scale(4)
    for _, labels in ipairs(self.rows) do
        local row = HorizontalGroup:new{ align = "center" }
        local columns = self.numeric_only and 3 or #labels
        for _, label in ipairs(labels) do
            local key_label = label
            local key = Key:new{
                label = key_label,
                width = math.floor((self.width - scale(36)) / columns),
                height = key_height,
                callback = function() self:_press(key_label) end,
            }
            if key_label:match("^[A-Z]$") then
                self.letter_keys[#self.letter_keys + 1] = { key = key, letter = key_label }
            end
            appendKey(row, key, key_gap)
        end
        table.insert(content, row)
        table.insert(content, VerticalSpan:new{ height = scale(5) })
    end

    if not self.numeric_only then
        self.shift_key = Key:new{
            label = "⇧", width = math.floor(self.width * .16), height = key_height,
            callback = function() self.shift = not self.shift; self:_update() end,
        }
        local space = Key:new{
            label = _("SPACE"), width = math.floor(self.width * .42), height = key_height,
            callback = function() self:_press(" ") end,
        }
        local back = Key:new{
            label = "←", width = math.floor(self.width * .16), height = key_height,
            callback = function() self:_press("←") end,
        }
        local controls = HorizontalGroup:new{ align = "center" }
        appendKey(controls, self.shift_key, key_gap)
        appendKey(controls, space, key_gap)
        appendKey(controls, back, key_gap)
        table.insert(content, controls)
        table.insert(content, VerticalSpan:new{ height = scale(5) })
    end

    local clear = Key:new{
        label = _("Clear"), width = math.floor(self.width * .35), height = scale(46),
        callback = function() self.value = ""; self:_update() end,
    }
    local done = Key:new{
        label = _("Done"), width = math.floor(self.width * .55), height = scale(46),
        callback = function() if self.on_submit then self.on_submit(self.value) end end,
    }
    local actions = HorizontalGroup:new{ align = "center" }
    appendKey(actions, clear, key_gap)
    appendKey(actions, done, key_gap)
    table.insert(content, actions)

    content = VerticalGroup:new(content)
    local height = math.min(Screen:getHeight() - scale(20), content:getSize().h + scale(28))
    self.dimen = Geom:new{
        x = math.floor((Screen:getWidth() - self.width) / 2),
        y = math.floor((Screen:getHeight() - height) / 2),
        w = self.width, h = height,
    }
    self[1] = FrameContainer:new{
        width = self.width, height = height, padding = scale(12),
        bordersize = scale(2), color = Blitbuffer.COLOR_BLACK,
        radius = scale(18), background = Blitbuffer.COLOR_WHITE, content,
    }
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    self:_update()
end

function Keyboard:_displayValue()
    if self.secure then return string.rep("•", #self.value) end
    return self.value
end

function Keyboard:_press(key)
    if key == "←" then
        self.value = self.value:sub(1, -2)
    elseif key:match("^[A-Z]$") then
        if self.numeric_only then return end
        self.value = self.value .. (self.shift and key:upper() or key:lower())
        self.shift = false
    elseif key:match("^[a-z]$") then
        if self.numeric_only then return end
        self.value = self.value .. (self.shift and key:upper() or key:lower())
        self.shift = false
    else
        self.value = self.value .. key
    end
    self:_update()
end

function Keyboard:_update()
    self.display:setText(self.value ~= "" and self:_displayValue() or (self.placeholder or _("Search apps")))
    for _, item in ipairs(self.letter_keys) do
        item.key:setLabel(self.shift and item.letter or item.letter:lower())
    end
    if self.shift_key then self.shift_key:setActive(self.shift) end
    UIManager:setDirty(self, "ui")
end

function Keyboard:paintTo(bb, x, y)
    return InputContainer.paintTo(self, bb, self.dimen.x, self.dimen.y)
end

function Keyboard:onClose()
    if self.on_cancel then
        self.on_cancel()
    else
        UIManager:close(self)
    end
    return true
end

-- Replace only this AppDock-owned InputDialog's soft-keyboard callback. The
-- dialog remains in place, so its existing validation and action buttons stay
-- authoritative; Done copies the custom keyboard's value back to its input.
function Keyboard.attach(dialog, options)
    options = options or {}
    if type(dialog) ~= "table" or type(dialog.getInputText) ~= "function" or type(dialog.setInputText) ~= "function" then
        return false
    end
    if dialog.appdock_keyboard_attached then return true end
    local input_widget = dialog._input_widget
    if type(input_widget) ~= "table" then return false end

    local active_keyboard
    local function closeKeyboard()
        local keyboard = active_keyboard
        active_keyboard = nil
        if keyboard then UIManager:close(keyboard) end
    end
    local function showKeyboard()
        if active_keyboard then return true end
        local keyboard
        keyboard = Keyboard:new{
            value = dialog:getInputText() or "",
            title = options.title or dialog.title,
            placeholder = options.placeholder or dialog.input_hint,
            numeric_only = options.numeric_only or dialog.input_type == "number",
            secure = options.secure or false,
            on_cancel = closeKeyboard,
            on_submit = function(value)
                dialog:setInputText(value)
                closeKeyboard()
            end,
        }
        active_keyboard = keyboard
        UIManager:show(keyboard)
        return true
    end

    dialog.onShowKeyboard = showKeyboard
    input_widget.onShowKeyboard = showKeyboard
    input_widget.onTapTextBox = function() return showKeyboard() end
    dialog.appdock_keyboard_attached = true
    return true
end

-- UIManager has already started closing this widget when this hook runs.
-- Never call UIManager:close() from here again: it re-enters the widget
-- lifecycle and can leave KOReader's render mutex pointing at destroyed UI.
function Keyboard:onCloseWidget() return true end

return Keyboard
