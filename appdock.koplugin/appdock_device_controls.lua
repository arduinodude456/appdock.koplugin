-- AppDock hardware controls: page-key brightness, power actions, and a small
-- animated e-ink screensaver.
local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Controls = {}
local Screen = Device.screen
local MODULE_DIR = (debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "")
local FRAME_PATHS = {
    MODULE_DIR .. "assets/screensaver/happy_ereader_01.png",
    MODULE_DIR .. "assets/screensaver/happy_ereader_02.png",
    MODULE_DIR .. "assets/screensaver/happy_ereader_03.png",
    MODULE_DIR .. "assets/screensaver/happy_ereader_04.png",
}
local function scale(value) return Screen:scaleBySize(value) end
local function fileExists(path)
    local file = io.open(path, "rb")
    if file then file:close(); return true end
    return false
end
local function brightnessState()
    local ok, result = pcall(function()
        local powerd = Device:getPowerDevice()
        if not powerd or type(powerd.frontlightIntensity) ~= "function" then return nil end
        local min, max = tonumber(powerd.fl_min), tonumber(powerd.fl_max)
        local current = tonumber(powerd:frontlightIntensity())
        if not min or not max or not current or max <= min then return nil end
        return { powerd = powerd, min = min, max = max, current = current }
    end)
    return ok and result or nil
end
local function setBrightness(delta)
    local state = brightnessState()
    if not state then return nil end
    local value = math.max(state.min, math.min(state.max, state.current + delta))
    local ok = pcall(function()
        if value == state.min then state.powerd:toggleFrontlight() else state.powerd:setIntensity(value) end
        if state.powerd.updateResumeFrontlightState then state.powerd:updateResumeFrontlightState() end
    end)
    if not ok then return nil end
    state.current = value
    return state
end

local BrightnessIndicator = WidgetContainer:extend{ percentage = 0, current = 0, maximum = 100, dimen = nil }
function BrightnessIndicator:init()
    local width, height = scale(82), scale(154)
    self.dimen = Geom:new{ w = width, h = height }
    local ratio = math.max(0, math.min(1, self.percentage / 100))
    local bar_h, bar_w = scale(84), scale(10)
    local filled_h = math.max(scale(2), math.floor(bar_h * ratio))
    local children = {
        FrameContainer:new{ width = width, height = height, padding = scale(10), bordersize = scale(1), color = Blitbuffer.COLOR_DARK_GRAY, radius = scale(16), background = Blitbuffer.COLOR_WHITE,
            VerticalGroup:new{
                TextWidget:new{ text = "☼", face = Font:getFace("cfont", scale(24)), fgcolor = Blitbuffer.COLOR_BLACK, padding = 0 },
                VerticalSpan:new{ width = scale(7) },
                FrameContainer:new{ width = bar_w, height = bar_h, padding = 0, bordersize = scale(1), color = Blitbuffer.COLOR_DARK_GRAY, radius = scale(5), background = Blitbuffer.COLOR_LIGHT_GRAY,
                    FrameContainer:new{ width = bar_w, height = filled_h, padding = 0, bordersize = 0, radius = scale(5), background = Blitbuffer.COLOR_BLACK, overlap_offset = { 0, bar_h - filled_h } },
                },
                VerticalSpan:new{ width = scale(7) },
                TextWidget:new{ text = string.format("%d%%", math.floor(self.percentage + .5)), face = Font:getFace("smallinfofont", scale(11)), fgcolor = Blitbuffer.COLOR_BLACK, padding = 0 },
            },
        },
    }
    self[1] = CenterContainer:new{ dimen = self.dimen, children[1] }
end

local HappyReaderScreen = InputContainer:extend{ frame = 1, dimen = nil, _tick = nil }
function HappyReaderScreen:init()
    self.dimen = Screen:getSize()
    if Device:hasKeys() then self.key_events.Close = { { Device.input.group.Back } } end
    self.ges_events = { CloseScreensaver = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    self:rebuild()
    self._tick = function()
        self.frame = self.frame % #FRAME_PATHS + 1
        self:rebuild()
        UIManager:setDirty(self, "ui")
        UIManager:scheduleIn(.75, self._tick)
    end
end
function HappyReaderScreen:rebuild()
    local width, height = self.dimen.w, self.dimen.h
    local image = fileExists(FRAME_PATHS[self.frame]) and ImageWidget:new{ file = FRAME_PATHS[self.frame], width = math.floor(width * .72), height = math.floor(height * .72), scale_factor = 0 } or TextWidget:new{ text = _("Have a nice reading break"), face = Font:getFace("cfont", scale(20)), fgcolor = Blitbuffer.COLOR_BLACK }
    self:clear()
    self[1] = FrameContainer:new{ width = width, height = height, padding = 0, bordersize = 0, background = Blitbuffer.COLOR_WHITE, CenterContainer:new{ dimen = self.dimen, image } }
end
function HappyReaderScreen:paintTo(bb, x, y)
    local range = self.ges_events.CloseScreensaver[1].range
    range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    return InputContainer.paintTo(self, bb, x, y)
end
function HappyReaderScreen:onCloseScreensaver()
    UIManager:close(self)
    return true
end
function HappyReaderScreen:onShow()
    UIManager:setDirty(self, "full")
    UIManager:scheduleIn(.75, self._tick)
    return true
end
function HappyReaderScreen:onCloseWidget()
    if self._tick then UIManager:unschedule(self._tick); self._tick = nil end
    UIManager:setDirty("all", "full")
end

function Controls.pageKeyGroups()
    if not Device:hasKeys() or not Device.input or not Device.input.group then return nil, nil end
    local group = Device.input.group
    -- KOReader's canonical groups are PgBack/PgFwd (RPgBack/LPgBack and
    -- RPgFwd/LPgFwd). Keep the longer aliases for older device adapters.
    return group.PgBack or group.PageUp or group.PageBackward or group.PagePrevious,
        group.PgFwd or group.PageDown or group.PageForward or group.PageNext
end
function Controls.showPowerMenu()
    local dialog
    local function closeThen(callback) return function() UIManager:close(dialog); UIManager:nextTick(callback) end end
    dialog = ButtonDialog:new{ title = _("Power"), buttons = {
        { { text = _("Restart KOReader"), callback = closeThen(function() if UIManager.restartKOReader then UIManager:restartKOReader() end end) } },
        { { text = _("Power off"), callback = closeThen(function() if UIManager.poweroff_action then UIManager.poweroff_action() else UIManager:broadcastEvent(require("ui/event"):new("PowerOff")) end end) } },
        { { text = _("Restart device"), callback = closeThen(function() if UIManager.reboot_action then UIManager.reboot_action() else UIManager:broadcastEvent(require("ui/event"):new("Reboot")) end end) } },
        { { text = _("Cancel"), callback = function() UIManager:close(dialog) end } },
    } }
    UIManager:show(dialog)
end
function Controls.showScreensaver()
    for _, path in ipairs(FRAME_PATHS) do if not fileExists(path) then return false end end
    UIManager:show(HappyReaderScreen:new{})
    return true
end
function Controls.brightnessState() return brightnessState() end
function Controls.setBrightness(delta) return setBrightness(delta) end
function Controls.buildIndicator(state)
    if not state then return nil end
    local percentage = (state.current - state.min) / (state.max - state.min) * 100
    return BrightnessIndicator:new{ percentage = percentage, overlap_offset = { Screen:getWidth() - scale(94), math.floor((Screen:getHeight() - scale(154)) / 2) } }
end
Controls._test = { BrightnessIndicator = BrightnessIndicator, HappyReaderScreen = HappyReaderScreen, frame_paths = FRAME_PATHS, brightnessState = brightnessState }
return Controls
