-- AppDock UI primitives.
-- This module intentionally avoids KOReader's stock dialogs.  It provides a
-- small, high-contrast Material-like surface that remains cheap to redraw on
-- eInk devices.
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Font = require("ui/font")
local _ = require("gettext")

local UI = {}
local scale = function(n) return math.max(1, math.floor((n or 0) * (Screen:getWidth() / 600))) end
local palette = {
    background = Blitbuffer.COLOR_WHITE,
    surface = Blitbuffer.COLOR_WHITE,
    ink = Blitbuffer.COLOR_BLACK,
    muted = Blitbuffer.COLOR_DARK_GRAY,
    accent = Blitbuffer.COLOR_BLACK,
}
local function face(size, bold)
    return Font:getFace(bold and "cfont" or "smallinfofont", scale(size))
end
local function label(text, size, bold, color)
    return TextWidget:new{ text = tostring(text or ""), face = face(size or 15, bold), fgcolor = color or palette.ink, padding = 0 }
end
local function buttonFrame(width, height, active)
    return FrameContainer:new{
        width = width, height = height, padding = scale(7), bordersize = scale(1),
        color = palette.ink, background = active and palette.ink or palette.surface,
        radius = scale(12),
    }
end

local AppButton = InputContainer:extend{ text = "", callback = nil, width = 120, height = 42, active = false }
function AppButton:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self[1] = buttonFrame(self.width, self.height, self.active)
    self[1][1] = CenterContainer:new{ dimen = self.dimen, label(self.text, 13, true, self.active and palette.surface or palette.ink) }
    self.ges_events = { tap = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end
function AppButton:paintTo(bb, x, y)
    self.ges_events.tap[1].range.x, self.ges_events.tap[1].range.y = x, y
    return InputContainer.paintTo(self, bb, x, y)
end
function AppButton:onTap()
    -- Keep feedback synchronous: the grid editor may close this popup
    -- immediately, so no callback may touch a widget on a later tick.
    if self[1] then self[1].background = palette.ink end
    UIManager:setDirty(nil, "ui", self.dimen)
    if self.callback then self.callback() end
    return true
end

local AppSwitch = InputContainer:extend{ value = false, callback = nil, width = 58, height = 32 }
function AppSwitch:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self.track = FrameContainer:new{ width = self.width, height = self.height, padding = 0, bordersize = scale(1), color = palette.ink, background = self.value and palette.ink or palette.surface, radius = self.height / 2 }
    self.knob = FrameContainer:new{ width = scale(22), height = scale(22), padding = 0, bordersize = scale(1), color = palette.ink, background = self.value and palette.surface or palette.ink, radius = scale(11) }
    self.visual = HorizontalGroup:new{ align = "center", self.track, VerticalSpan:new{ width = -self.width + scale(25) }, self.knob }
    self.ges_events = { tap = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end
function AppSwitch:paintTo(bb, x, y)
    self.ges_events.tap[1].range.x, self.ges_events.tap[1].range.y = x, y
    self.track.background = self.value and palette.ink or palette.surface
    self.knob.background = self.value and palette.surface or palette.ink
    self.visual:paintTo(bb, x, y + math.floor((self.height - self.visual:getSize().h) / 2))
end
function AppSwitch:onTap()
    self.value = not self.value
    if self.callback then self.callback(self.value) end
    UIManager:setDirty(nil, "ui", self.dimen)
    return true
end

local AppPopup = InputContainer:extend{ title = "", buttons = nil, width = nil, rows_per_page = nil }
function AppPopup:init()
    self.width = self.width or math.min(Screen:getWidth() - scale(28), scale(520))
    self.buttons = self.buttons or {}
    self.rows = {}
    for _, row in ipairs(self.buttons) do
        local item = row[1] or row
        local text = item.text or ""
        local disabled = item.enabled == false
        local b = AppButton:new{ text = text, width = self.width - scale(28), height = scale(disabled and 30 or 44), active = false,
            callback = disabled and nil or function() if item.callback then item.callback() end; UIManager:setDirty(nil, "ui") end }
        if disabled then b[1] = CenterContainer:new{ dimen = b.dimen, label(text, 12, true, palette.muted) } end
        if item.switch and not disabled then
            local sw = AppSwitch:new{ value = item.value, callback = function() if item.callback then item.callback() end end }
            b[1] = FrameContainer:new{ width = b.width, height = b.height, padding = scale(8), bordersize = scale(1), color = palette.ink, background = palette.surface, radius = scale(12), HorizontalGroup:new{ align = "center", label(text, 13, true), VerticalSpan:new{ width = b.width - scale(100) }, sw } }
        end
        table.insert(self.rows, b)
    end
    local children = { label(self.title, 20, true), VerticalSpan:new{ height = scale(10) } }
    for _, b in ipairs(self.rows) do table.insert(children, b); table.insert(children, VerticalSpan:new{ height = scale(6) }) end
    table.insert(children, VerticalSpan:new{ height = scale(4) })
    self.content = VerticalGroup:new(children)
    local h = math.min(Screen:getHeight() - scale(30), self.content:getSize().h + scale(28))
    self.dimen = Geom:new{ x = math.floor((Screen:getWidth() - self.width) / 2), y = math.floor((Screen:getHeight() - h) / 2), w = self.width, h = h }
    self[1] = FrameContainer:new{ width = self.width, height = h, padding = scale(14), bordersize = scale(2), color = palette.ink, background = palette.surface, radius = scale(20), self.content }
end
function AppPopup:paintTo(bb, x, y)
    return InputContainer.paintTo(self, self.dimen.x, self.dimen.y)
end
function AppPopup:onCloseWidget() UIManager:close(self); return true end

local Keyboard = InputContainer:extend{ owner = nil, width = nil }
function Keyboard:init()
    self.width = self.width or Screen:getWidth() - scale(28)
    local keys = { "1 2 3 4 5 6 7 8 9 0", "Q W E R T Y U I O P", "A S D F G H J K L", "Z X C V B N M", "←   SPACE   ✓" }
    local rows = {}
    for _, line in ipairs(keys) do
        local row = HorizontalGroup:new{ align = "center" }
        for key in line:gmatch("%S+") do
            local w = key == "SPACE" and self.width * .42 or self.width * .085
            local text = key
            local b = AppButton:new{ text = text, width = math.floor(w), height = scale(35), callback = function()
                if self.owner then self.owner:_key(text) end
            end }
            table.insert(row, b)
            table.insert(row, VerticalSpan:new{ width = scale(3) })
        end
        table.insert(rows, row); table.insert(rows, VerticalSpan:new{ height = scale(4) })
    end
    self[1] = VerticalGroup:new(rows)
    self.dimen = Geom:new{ w = self.width, h = self[1]:getSize().h }
end

local AppInputDialog = InputContainer:extend{ title = "", input = "", buttons = nil, input_hint = "" }
function AppInputDialog:init()
    self.value = tostring(self.input or "")
    self.buttons = self.buttons or {}
    self.width = math.min(Screen:getWidth() - scale(28), scale(520))
    self.input_box = FrameContainer:new{ width = self.width - scale(28), height = scale(42), padding = scale(8), bordersize = scale(1), color = palette.ink, background = palette.surface, radius = scale(10), label(self.value ~= "" and self.value or self.input_hint, 14, false, self.value ~= "" and palette.ink or palette.muted) }
    self.keyboard = Keyboard:new{ owner = self, width = self.width - scale(28) }
    local content = { label(self.title, 20, true), VerticalSpan:new{ height = scale(10) }, self.input_box, VerticalSpan:new{ height = scale(8) }, self.keyboard, VerticalSpan:new{ height = scale(8) } }
    for _, row in ipairs(self.buttons) do local item = row[1] or row; table.insert(content, AppButton:new{ text = item.text, width = self.width - scale(28), height = scale(42), callback = function() if item.callback then item.callback() end end }); table.insert(content, VerticalSpan:new{ height = scale(5) }) end
    self.content = VerticalGroup:new(content)
    local h = math.min(Screen:getHeight() - scale(20), self.content:getSize().h + scale(28))
    self.dimen = Geom:new{ x = math.floor((Screen:getWidth() - self.width) / 2), y = math.floor((Screen:getHeight() - h) / 2), w = self.width, h = h }
    self[1] = FrameContainer:new{ width = self.width, height = h, padding = scale(14), bordersize = scale(2), color = palette.ink, background = palette.surface, radius = scale(20), self.content }
end
function AppInputDialog:_key(key)
    if key == "✓" then return end
    if key == "←" then self.value = self.value:sub(1, -2)
    elseif key == "SPACE" then self.value = self.value .. " "
    else self.value = self.value .. key end
    self.input_box[1] = label(self.value ~= "" and self.value or self.input_hint, 14, false, self.value ~= "" and palette.ink or palette.muted)
    UIManager:setDirty(nil, "ui", self.dimen)
end
function AppInputDialog:getInputText() return self.value end
function AppInputDialog:onShowKeyboard() return true end
function AppInputDialog:paintTo(bb, x, y) return InputContainer.paintTo(self, self.dimen.x, self.dimen.y) end

local AppSnackbar = InputContainer:extend{ text = "", timeout = 3 }
function AppSnackbar:init()
    local width = math.min(Screen:getWidth() - scale(28), scale(520))
    self.dimen = Geom:new{ x = scale(14), y = Screen:getHeight() - scale(72), w = width, h = scale(48) }
    self[1] = FrameContainer:new{ width = width, height = self.dimen.h, padding = scale(12), bordersize = scale(1), color = palette.ink, background = palette.surface, radius = scale(14), label(self.text, 13, false) }
    if self.timeout then UIManager:scheduleIn(self.timeout, function() UIManager:close(self) end) end
end
function AppSnackbar:paintTo(bb, x, y) return InputContainer.paintTo(self, self.dimen.x, self.dimen.y) end

UI.AppButton = AppButton
UI.AppSwitch = AppSwitch
UI.ButtonDialog = AppPopup
UI.InputDialog = AppInputDialog
UI.InfoMessage = AppSnackbar
UI.showPopup = function(popup) UIManager:show(popup); return popup end
return UI
