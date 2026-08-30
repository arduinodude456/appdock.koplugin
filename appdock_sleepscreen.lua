local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Sleep = { active = nil }
local SleepScreen = WidgetContainer:extend{}

function SleepScreen:init()
    self.dimen = Geom:new{ w = Device.screen:getWidth(), h = Device.screen:getHeight() }
    local scale = function(value) return Device.screen:scaleBySize(value) end
    local children = {
        TextWidget:new{ text = "AppDock", face = Font:getFace("cfont", scale(28)), fgcolor = Blitbuffer.COLOR_BLACK, bold = true, padding = 0 },
        VerticalSpan:new{ width = scale(8) },
        TextWidget:new{ text = _("Sleeping"), face = Font:getFace("infofont", scale(18)), fgcolor = Blitbuffer.COLOR_BLACK, padding = 0 },
    }
    self[1] = FrameContainer:new{
        width = self.dimen.w,
        height = self.dimen.h,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{ dimen = self.dimen, VerticalGroup:new(children) },
    }
end

function SleepScreen:onShow()
    UIManager:setDirty(self, "full")
    return true
end

function SleepScreen:onResume()
    UIManager:close(self)
    if Sleep.active == self then Sleep.active = nil end
end

function SleepScreen:onCloseWidget()
    UIManager:setDirty("all", "ui")
end

function Sleep.show()
    if Sleep.active then return end
    Sleep.active = SleepScreen:new{}
    UIManager:show(Sleep.active, "full")
end

function Sleep.close()
    if Sleep.active then
        UIManager:close(Sleep.active)
        Sleep.active = nil
    end
end

Sleep._test = { SleepScreen = SleepScreen }

return Sleep
