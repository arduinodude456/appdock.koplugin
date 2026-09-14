-- AppDock notification reference DApp.
-- Demonstrates the local context.notify contract introduced in AppDock 2.1.0.

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
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local function scale(value)
    return Device.screen:scaleBySize(value)
end

local function emptySizedWidget(width, height)
    return CenterContainer:new{
        dimen = Geom:new{ w = width, h = height },
        HorizontalSpan:new{ width = 0 },
    }
end

local SendButton = InputContainer:extend{ width = nil, height = nil, callback = nil }

function SendButton:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self[1] = FrameContainer:new{
        width = self.width, height = self.height, padding = 0, bordersize = 0,
        radius = scale(14), background = Blitbuffer.COLOR_GRAY_8,
        CenterContainer:new{
            dimen = self.dimen,
            TextWidget:new{ text = _("Send status message"), face = Font:getFace("smallinfofont", scale(13)), fgcolor = Blitbuffer.COLOR_WHITE, bold = true, max_width = self.width - scale(18) },
        },
    }
    self.ges_events = { TapSendStatus = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function SendButton:paintTo(bb, x, y)
    local range = self.ges_events.TapSendStatus[1].range
    range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    return InputContainer.paintTo(self, bb, x, y)
end

function SendButton:onTapSendStatus()
    if self.callback then self.callback() end
    return true
end

local function sendStatus(instance, context, skip_rebuild)
    instance.status_message_count = (instance.status_message_count or 0) + 1
    if type(context.notify) ~= "function" then
        instance.status_message_result = _("AppDock 2.1.0 is required")
        if not skip_rebuild then context.requestRebuild("ui") end
        return false
    end
    local ok = context.notify({
        title = _("Status Message"),
        message = string.format(_("Everything is working. Test message %d."), instance.status_message_count),
        priority = "normal",
    })
    instance.status_message_result = ok and _("Status message sent to Notifications") or _("Status message could not be saved")
    if not skip_rebuild then context.requestRebuild("ui") end
    return ok
end

return {
    id = "status_message",
    version = "1.0.0",
    title = "Status Message",
    subtitle = "Test local AppDock notifications",
    symbol = "!",
    logo = "help",
    buildPane = function(instance, context)
        local width, height = context.dimen.w, context.dimen.h
        local margin = scale(18)
        if not instance.status_message_open_notice then
            instance.status_message_open_notice = true
            sendStatus(instance, context, true)
        end
        local pane = WidgetContainer:new{ dimen = Geom:new{ w = width, h = height } }
        pane[1] = OverlapGroup:new{
            dimen = pane.dimen,
            allow_mirroring = false,
            FrameContainer:new{ width = width, height = height, padding = 0, bordersize = 0, background = Blitbuffer.COLOR_WHITE, emptySizedWidget(width, height) },
            TextWidget:new{ text = _("Status Message"), face = Font:getFace("cfont", scale(22)), fgcolor = Blitbuffer.COLOR_BLACK, bold = true, overlap_offset = { margin, margin } },
            TextWidget:new{ text = _("A small reference DApp for AppDock’s local notification API."), face = Font:getFace("smallinfofont", scale(12)), fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = width - 2 * margin, overlap_offset = { margin, margin + scale(32) } },
            FrameContainer:new{ width = width - 2 * margin, height = scale(78), padding = 0, bordersize = 0, radius = scale(13), background = Blitbuffer.COLOR_LIGHT_GRAY, emptySizedWidget(width - 2 * margin, scale(78)), overlap_offset = { margin, margin + scale(66) } },
            TextWidget:new{ text = instance.status_message_result or _("Ready to send a status message"), face = Font:getFace("smallinfofont", scale(12)), fgcolor = Blitbuffer.COLOR_BLACK, max_width = width - 4 * margin, overlap_offset = { 2 * margin, margin + scale(88) } },
            SendButton:new{ width = width - 2 * margin, height = scale(48), callback = function() sendStatus(instance, context) end, overlap_offset = { margin, margin + scale(164) } },
            TextWidget:new{ text = _("Open Quick Settings to view the saved inbox entry."), face = Font:getFace("smallinfofont", scale(10)), fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = width - 2 * margin, overlap_offset = { margin, margin + scale(222) } },
        }
        return pane
    end,
}
