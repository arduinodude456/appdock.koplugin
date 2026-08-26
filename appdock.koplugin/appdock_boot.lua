-- AppDock Boot: two quiet E-Ink frames before the homescreen opens.

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local DAppLogo = require("appdock_logo")
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

local Boot = {}
local BootScreen = WidgetContainer:extend{ on_finish = nil, stage = 1, _advance = nil, _finish = nil, completed = false }

local function scale(value)
    return Device.screen:scaleBySize(value)
end

local function brandInk()
    if Device.screen:isColorEnabled() then return Blitbuffer.ColorRGB32(96, 178, 55, 0xFF) end
    return Blitbuffer.COLOR_DARK_GRAY
end

function BootScreen:rebuild()
    local width, height = self.dimen.w, self.dimen.h
    local logo_size = math.max(scale(84), math.min(math.floor(width * 0.44), math.floor(height * 0.36)))
    local children = { DAppLogo:new{ kind = "appdock", size = logo_size, ink = brandInk() } }
    if self.stage >= 2 then
        children[#children + 1] = VerticalSpan:new{ width = scale(15) }
        children[#children + 1] = TextWidget:new{ text = "AppDock", face = Font:getFace("cfont", scale(27)), fgcolor = Blitbuffer.COLOR_BLACK, bold = true }
        children[#children + 1] = VerticalSpan:new{ width = scale(5) }
        children[#children + 1] = TextWidget:new{ text = _("by @arduinodude456"), face = Font:getFace("smallinfofont", scale(12)), fgcolor = Blitbuffer.COLOR_DARK_GRAY }
    end
    self:clear()
    self[1] = FrameContainer:new{
        width = width, height = height, padding = 0, bordersize = 0, background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{ dimen = self.dimen, VerticalGroup:new(children) },
    }
end

function BootScreen:init()
    self.dimen = Geom:new{ w = Device.screen:getWidth(), h = Device.screen:getHeight() }
    self.stage = 1
    self:rebuild()
    self._advance = function()
        if self.completed then return end
        self.stage = 2
        self:rebuild()
        UIManager:setDirty(self, "ui")
        UIManager:scheduleIn(1.0, self._finish)
    end
    self._finish = function()
        if self.completed then return end
        self.completed = true
        UIManager:close(self)
        UIManager:nextTick(function()
            if self.on_finish then self.on_finish() end
        end)
    end
end

function BootScreen:onShow()
    UIManager:setDirty(self, "ui")
    UIManager:scheduleIn(0.95, self._advance)
    return true
end

function BootScreen:onCloseWidget()
    if self._advance then UIManager:unschedule(self._advance) end
    if self._finish then UIManager:unschedule(self._finish) end
end

function Boot.show(on_finish)
    UIManager:show(BootScreen:new{ on_finish = on_finish })
end

Boot._test = { BootScreen = BootScreen, brandInk = brandInk }

return Boot
