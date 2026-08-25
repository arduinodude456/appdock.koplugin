--[[--
AppDock notifications: local, passive inbox toasts for DApps.
The toast deliberately avoids animation and uses ordinary UI refreshes only.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local Screen = Device.screen

local Toast = InputContainer:extend{
    notification = nil,
    dimen = nil,
    covers_fullscreen = false,
}

local function scale(value)
    return Screen:scaleBySize(value)
end

local function emptySizedWidget(width, height)
    return CenterContainer:new{
        dimen = Geom:new{ w = width, h = height },
        HorizontalSpan:new{ width = 0 },
    }
end

function Toast:init()
    local screen = Screen:getSize()
    local margin, height = scale(16), scale(72)
    local width = math.max(scale(180), screen.w - 2 * margin)
    self.dimen = Geom:new{ x = margin, y = screen.h - height - margin, w = width, h = height }
    local notification = self.notification or {}
    local title = tostring(notification.title or "AppDock")
    local message = tostring(notification.message or "")
    self[1] = OverlapGroup:new{
        dimen = self.dimen,
        allow_mirroring = false,
        FrameContainer:new{
            width = width, height = height, padding = 0, bordersize = 0,
            radius = scale(15), background = Blitbuffer.COLOR_GRAY_8,
            emptySizedWidget(width, height),
        },
        TextWidget:new{
            text = title,
            face = Font:getFace("smallinfofont", scale(14)),
            fgcolor = Blitbuffer.COLOR_WHITE,
            bold = true,
            max_width = width - scale(46),
            overlap_offset = { scale(14), scale(12) },
        },
        TextWidget:new{
            text = message,
            face = Font:getFace("smallinfofont", scale(11)),
            fgcolor = Blitbuffer.COLOR_WHITE,
            max_width = width - scale(46),
            overlap_offset = { scale(14), scale(33) },
        },
        TextWidget:new{
            text = "×",
            face = Font:getFace("cfont", scale(19)),
            fgcolor = Blitbuffer.COLOR_WHITE,
            overlap_offset = { width - scale(27), scale(10) },
        },
    }
    self.ges_events = { TapDismissNotification = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    self._dismiss = function()
        if self._shown then UIManager:close(self) end
    end
end

function Toast:paintTo(bb, x, y)
    local range = self.ges_events.TapDismissNotification[1].range
    range.x, range.y, range.w, range.h = self.dimen.x, self.dimen.y, self.dimen.w, self.dimen.h
    return InputContainer.paintTo(self, bb, x, y)
end

function Toast:onShow()
    self._shown = true
    UIManager:setDirty(self, "ui")
    UIManager:scheduleIn(4, self._dismiss)
    return true
end

function Toast:onTapDismissNotification()
    UIManager:close(self)
    return true
end

function Toast:onCloseWidget()
    self._shown = false
    if self._dismiss then UIManager:unschedule(self._dismiss) end
    UIManager:setDirty("all", "ui")
end

local Notifications = {}

function Notifications.showToast(notification)
    UIManager:show(Toast:new{ notification = notification })
end

return Notifications
