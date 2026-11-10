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
    local margin = math.max(scale(10), math.min(scale(16), math.floor(screen.w / 12)))
    local height = math.min(math.max(scale(76), scale(82)), math.max(scale(76), screen.h - margin * 2))
    local width = math.max(1, screen.w - 2 * margin)
    local x = math.max(0, math.floor((screen.w - width) / 2))
    self.dimen = Geom:new{ x = x, y = math.max(0, screen.h - height - margin), w = width, h = height }
    local notification = self.notification or {}
    local title = tostring(notification.title or "AppDock")
    local message = tostring(notification.message or "")
    self[1] = OverlapGroup:new{
        dimen = self.dimen,
        allow_mirroring = false,
        FrameContainer:new{
            width = width, height = height, padding = 0, bordersize = math.max(1, scale(1)),
            color = Blitbuffer.COLOR_BLACK, radius = scale(15), background = Blitbuffer.COLOR_WHITE,
            emptySizedWidget(width, height),
        },
        FrameContainer:new{
            width = width - scale(2), height = scale(28), padding = 0, bordersize = 0,
            radius = scale(12), background = Blitbuffer.COLOR_BLACK,
            emptySizedWidget(width - scale(2), scale(28)), overlap_offset = { scale(1), scale(1) },
        },
        TextWidget:new{
            text = title,
            face = Font:getFace("smallinfofont", scale(14)),
            fgcolor = Blitbuffer.COLOR_WHITE,
            bold = true,
            max_width = width - scale(46),
            overlap_offset = { scale(14), scale(8) },
        },
        TextWidget:new{
            text = message,
            face = Font:getFace("smallinfofont", scale(11)),
            fgcolor = Blitbuffer.COLOR_BLACK,
            max_width = width - scale(46),
            overlap_offset = { scale(14), scale(40) },
        },
        TextWidget:new{
            text = "×",
            face = Font:getFace("cfont", scale(19)),
            fgcolor = Blitbuffer.COLOR_WHITE,
            overlap_offset = { width - scale(27), scale(6) },
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

----------------------------------------------------------------
-- Media heads-up: Android-style "now playing" card at the top edge.
-- It announces a background track and disappears on its own; the ongoing
-- card with the controls lives in the quick settings shade.
----------------------------------------------------------------

local MediaToast = InputContainer:extend{
    media = nil,
    dimen = nil,
    covers_fullscreen = false,
}

function MediaToast:init()
    local Media = require("appdock_media")
    local DAppLogo = require("appdock_logo")
    local screen = Screen:getSize()
    local media = self.media or {}
    local margin = math.max(scale(10), math.min(scale(16), math.floor(screen.w / 12)))
    local width = math.min(screen.w - 2 * margin, scale(560))
    local height = scale(86)
    local x = math.floor((screen.w - width) / 2)
    self.dimen = Geom:new{ x = x, y = margin, w = width, h = height }

    local pad = scale(14)
    local logo_size = scale(16)
    local button_d = scale(44)
    local text_x = pad
    local text_w = width - pad * 2 - button_d - scale(10)
    local app_x = pad + logo_size + scale(6)

    local entries = {
        FrameContainer:new{
            width = width, height = height, padding = 0, bordersize = math.max(1, scale(1)),
            color = Blitbuffer.COLOR_BLACK, radius = scale(20), background = Blitbuffer.COLOR_WHITE,
            emptySizedWidget(width, height),
        },
        DAppLogo:new{
            kind = media.icon or "music", size = logo_size, ink = Blitbuffer.COLOR_BLACK,
            overlap_offset = { pad, scale(10) },
        },
        TextWidget:new{
            text = tostring(media.app or "AppDock"),
            face = Font:getFace("smallinfofont", scale(10)),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = text_w - logo_size,
            padding = 0, overlap_offset = { app_x, scale(10) },
        },
        TextWidget:new{
            text = tostring(media.title or ""),
            face = Font:getFace("smallinfofont", scale(14)),
            fgcolor = Blitbuffer.COLOR_BLACK, bold = true, max_width = text_w,
            padding = 0, overlap_offset = { text_x, scale(32) },
        },
        TextWidget:new{
            text = tostring(media.artist or ""),
            face = Font:getFace("smallinfofont", scale(11)),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = text_w,
            padding = 0, overlap_offset = { text_x, scale(55) },
        },
        FrameContainer:new{
            width = button_d, height = button_d, padding = 0, bordersize = 0,
            radius = math.floor(button_d / 2), background = Blitbuffer.COLOR_BLACK,
            emptySizedWidget(button_d, button_d),
            overlap_offset = { width - pad - button_d, math.floor((height - button_d) / 2) },
        },
        Media.Glyph:new{
            kind = media.playing and "pause" or "play", size = button_d, color = Blitbuffer.COLOR_WHITE,
            overlap_offset = { width - pad - button_d, math.floor((height - button_d) / 2) },
        },
    }
    local group = OverlapGroup:new{ dimen = self.dimen, allow_mirroring = false }
    for _, widget in ipairs(entries) do table.insert(group, widget) end
    self[1] = group
    self.ges_events = { TapDismissMedia = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    self._dismiss = function()
        if self._shown then UIManager:close(self) end
    end
end

function MediaToast:paintTo(bb, x, y)
    local range = self.ges_events.TapDismissMedia[1].range
    range.x, range.y, range.w, range.h = self.dimen.x, self.dimen.y, self.dimen.w, self.dimen.h
    return InputContainer.paintTo(self, bb, x, y)
end

function MediaToast:onShow()
    self._shown = true
    UIManager:setDirty(self, "ui")
    UIManager:scheduleIn(4, self._dismiss)
    return true
end

function MediaToast:onTapDismissMedia()
    UIManager:close(self)
    return true
end

function MediaToast:onCloseWidget()
    self._shown = false
    if self._dismiss then UIManager:unschedule(self._dismiss) end
    UIManager:setDirty("all", "ui")
end

local Notifications = {}

function Notifications.showToast(notification)
    UIManager:show(Toast:new{ notification = notification })
end

-- Only one media heads-up at a time: a quick track change replaces it.
function Notifications.showMedia(media)
    if type(media) ~= "table" then return end
    if Notifications._media_toast and Notifications._media_toast._shown then
        UIManager:close(Notifications._media_toast)
    end
    local toast = MediaToast:new{ media = media }
    Notifications._media_toast = toast
    UIManager:show(toast)
end

return Notifications
