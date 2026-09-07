-- AppDock-owned keyboard for AppDock-owned search surfaces.
-- KOReader dialogs elsewhere remain untouched.
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
    self[1] = FrameContainer:new{
        width = self.width, height = self.height, padding = 0,
        bordersize = scale(1), color = Blitbuffer.COLOR_BLACK,
        radius = scale(8), background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{
            dimen = self.dimen,
            TextWidget:new{ text = self.label, face = Font:getFace("cfont", scale(14)), fgcolor = Blitbuffer.COLOR_BLACK, padding = 0 },
        },
    }
    self.ges_events = { TapKey = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end
function Key:paintTo(bb, x, y)
    local range = self.ges_events.TapKey[1].range
    range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    return InputContainer.paintTo(self, bb, x, y)
end
function Key:onTapKey()
    if self.callback then self.callback() end
    return true
end
local Keyboard = InputContainer:extend{ value = "", on_submit = nil, on_cancel = nil }
function Keyboard:init()
    self.width = math.min(Screen:getWidth() - scale(24), scale(560))
    self.rows = {
        { "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P" },
        { "A", "S", "D", "F", "G", "H", "J", "K", "L" },
        { "Z", "X", "C", "V", "B", "N", "M", "←" },
    }
    self.display = TextWidget:new{ text = self.value ~= "" and self.value or _("Search apps"), face = Font:getFace("smallinfofont", scale(15)), fgcolor = Blitbuffer.COLOR_BLACK, padding = scale(8), max_width = self.width - scale(24) }
    local content = { self.display, VerticalSpan:new{ height = scale(8) } }
    for _, letters in ipairs(self.rows) do
        local row = HorizontalGroup:new{ align = "center" }
        for _, letter in ipairs(letters) do
            local key = Key:new{ label = letter, width = math.floor((self.width - scale(36)) / #letters), height = scale(36), callback = function() self:_press(letter) end }
            table.insert(row, key)
            table.insert(row, VerticalSpan:new{ width = scale(3) })
        end
        table.insert(content, row)
        table.insert(content, VerticalSpan:new{ height = scale(4) })
    end
    local space = Key:new{ label = "SPACE", width = math.floor(self.width * .44), height = scale(38), callback = function() self:_press(" ") end }
    local clear = Key:new{ label = _("Clear"), width = math.floor(self.width * .24), height = scale(38), callback = function() self.value = ""; self:_update() end }
    local done = Key:new{ label = _("Done"), width = math.floor(self.width * .24), height = scale(38), callback = function() if self.on_submit then self.on_submit(self.value) end end }
    table.insert(content, HorizontalGroup:new{ align = "center", space, VerticalSpan:new{ width = scale(4) }, clear, VerticalSpan:new{ width = scale(4) }, done })
    content = VerticalGroup:new(content)
    local height = math.min(Screen:getHeight() - scale(20), content:getSize().h + scale(28))
    self.dimen = Geom:new{ x = math.floor((Screen:getWidth() - self.width) / 2), y = math.floor((Screen:getHeight() - height) / 2), w = self.width, h = height }
    self[1] = FrameContainer:new{ width = self.width, height = height, padding = scale(12), bordersize = scale(2), color = Blitbuffer.COLOR_BLACK, radius = scale(18), background = Blitbuffer.COLOR_WHITE, content }
end
function Keyboard:_press(key)
    if key == "←" then self.value = self.value:sub(1, -2) else self.value = self.value .. key end
    self:_update()
end
function Keyboard:_update()
    self.display:setText(self.value ~= "" and self.value or _("Search apps"))
    UIManager:setDirty(self, "ui")
end
function Keyboard:paintTo(bb, x, y) return InputContainer.paintTo(self, bb, self.dimen.x, self.dimen.y) end
function Keyboard:onCloseWidget() if self.on_cancel then self.on_cancel() else UIManager:close(self) end; return true end
return Keyboard
