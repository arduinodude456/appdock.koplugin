-- The suspend path is entirely local: never fetch a catalog, media or account
-- state while a reader is going to sleep. A damaged/missing preset falls back
-- to the original AppDock screen instead of blocking suspend.
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

local Sleep = { active = nil, cycle = 0 }
local SleepScreen = WidgetContainer:extend{ covers_fullscreen = true }

function SleepScreen:init()
    self.dimen = Geom:new{ w = Device.screen:getWidth(), h = Device.screen:getHeight() }
    local rendered, preset_widget = pcall(function()
        local Presets = require("appdock_sleepscreen_presets")
        local Renderer = require("appdock_sleepscreen_renderer")
        local record = Presets.getActive(self.appdock)
        local definition = record and record.definition or Presets.defaultPreset()
        return Renderer.build(definition, self.dimen.w, self.dimen.h, {
            appdock = self.appdock,
            asset_paths = record and record.asset_paths or {},
            preview = false,
            cycle = self.cycle,
        })
    end)
    if rendered and preset_widget then
        self._preset_widget = preset_widget
        self[1] = preset_widget
        return
    end
    local scale = function(value) return Device.screen:scaleBySize(value) end
    local children = {
        TextWidget:new{ text = "AppDock", face = Font:getFace("cfont", scale(28)), fgcolor = Blitbuffer.COLOR_BLACK, bold = true, padding = 0 },
        VerticalSpan:new{ width = scale(8) },
        TextWidget:new{ text = _("by Quin Easwar and @arduinodude456"), face = Font:getFace("infofont", scale(18)), fgcolor = Blitbuffer.COLOR_BLACK, padding = 0 },
    }
    self[1] = FrameContainer:new{
        width = self.dimen.w, height = self.dimen.h, padding = 0, bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{ dimen = self.dimen, VerticalGroup:new(children) },
    }
end

function SleepScreen:onShow()
    UIManager:setDirty(self, "full")
    return true
end

function SleepScreen:onResume()
    if Sleep.active == self then Sleep.close() else UIManager:close(self) end
    return true
end

function SleepScreen:onCloseWidget()
    -- Renderer widget trees own their decoded images. KOReader's normal close
    -- path frees the tree; don't free the same Blitbuffer a second time here.
    if Sleep.active == self then Sleep.active = nil end
    UIManager:setDirty("all", "ui")
end

function Sleep.show(appdock)
    if Sleep.active then return end
    Sleep.cycle = Sleep.cycle + 1
    Sleep.active = SleepScreen:new{ appdock = appdock, cycle = Sleep.cycle }
    UIManager:show(Sleep.active, "full")
end

function Sleep.close()
    if Sleep.active then
        local active = Sleep.active
        Sleep.active = nil
        UIManager:close(active)
    end
end

Sleep._test = { SleepScreen = SleepScreen }
return Sleep
