--[[--
Screen rotation for AppDock (9.6.0).

Until 9.5.x AppDock could only rotate by hand (Quick Settings > Rotate), and
it did so badly: the tile broadcast KOReader's SetRotationMode event, KOReader
rotated its own FileManager/Reader, but every AppDock screen kept the pixel
size it was built with. The result was a homescreen drawn for the old
orientation, cropped or stretched, until something forced a rebuild.

This module fixes that in two parts:

  1. Relayout. Every full-screen AppDock widget registers itself with
     Rotation.attach(). Whatever rotates the screen (the G-sensor, the Rotate
     tile, KOReader's own menu) ends in Screen:setRotationMode(), which is
     wrapped once here. The wrapper tells every live AppDock widget, which then
     reads the new screen size, rebuilds its layout in place and repaints with
     one clean full refresh. The KOReader events SetRotationMode / ScreenResize /
     SetDimensions are handled as well, so no path is missed.

  2. Auto-rotate. With a rotation sensor (Device:hasGSensor()) AppDock follows
     the sensor while AppDock is on screen. The switch lives in Settings >
     Display and as the "Auto-rotate" Quick Settings tile. KOReader's own
     preference (used while reading) is never changed: it is restored as soon
     as the last AppDock screen is closed.
--]]--

local Device = require("device")
local UIManager = require("ui/uimanager")

local Screen = Device.screen

local Rotation = {}

-- Widgets that are currently alive. Weak keys: a widget that is dropped without
-- onCloseWidget must not be kept alive by this table.
local live = setmetatable({}, { __mode = "k" })
local bound_appdock
local hooked = false
local sensor_applied = false

local RELAYOUT_DELAY = 0.05
local RELAYOUT_RETRIES = 6

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

function Rotation.bind(appdock) bound_appdock = appdock end

function Rotation.hasSensor()
    local ok, has = pcall(function() return Device.hasGSensor and Device:hasGSensor() end)
    return ok and has == true
end

--- true when AppDock should follow the rotation sensor. Defaults to on.
function Rotation.isAuto(appdock)
    appdock = appdock or bound_appdock
    local settings = appdock and appdock.settings or nil
    local rotation = settings and type(settings.rotation) == "table" and settings.rotation or nil
    if rotation and rotation.auto == false then return false end
    return true
end

local function koreaderFollowsSensor()
    local ok, ignored = pcall(function()
        return G_reader_settings and G_reader_settings:isTrue("input_ignore_gsensor")
    end)
    return not (ok and ignored == true)
end

local function toggleSensor(on)
    if not Rotation.hasSensor() or type(Device.toggleGSensor) ~= "function" then return false end
    return pcall(Device.toggleGSensor, Device, on == true)
end

---------------------------------------------------------------------------
-- Sensor: AppDock's preference while AppDock is on screen
---------------------------------------------------------------------------

local function liveCount()
    local count = 0
    for widget in pairs(live) do
        if not widget._rotation_closed then count = count + 1 end
    end
    return count
end

--- Applies AppDock's auto-rotate preference (call whenever it changes or an
--- AppDock screen appears).
function Rotation.apply(appdock)
    if not Rotation.hasSensor() then return false end
    sensor_applied = true
    return toggleSensor(Rotation.isAuto(appdock))
end

--- Gives the sensor back to KOReader once no AppDock screen is left.
function Rotation.release()
    if not sensor_applied or liveCount() > 0 then return false end
    sensor_applied = false
    return toggleSensor(koreaderFollowsSensor())
end

function Rotation.setAuto(appdock, enabled)
    appdock = appdock or bound_appdock
    if not appdock or type(appdock.settings) ~= "table" then return false end
    appdock.settings.rotation = type(appdock.settings.rotation) == "table" and appdock.settings.rotation or {}
    appdock.settings.rotation.auto = enabled == true
    if type(appdock._saveSettings) == "function" then appdock:_saveSettings() end
    Rotation.apply(appdock)
    return appdock.settings.rotation.auto
end

---------------------------------------------------------------------------
-- Manual rotation (Quick Settings > Rotate)
---------------------------------------------------------------------------

--- Rotates to the next mode. KOReader's FileManager / Reader normally applies
--- the SetRotationMode event; when nobody does (AppDock running without them)
--- the mode is set directly after a short wait.
function Rotation.cycle()
    local ok, optionsutil = pcall(require, "ui/data/optionsutil")
    local modes = ok and type(optionsutil) == "table" and optionsutil.rotation_modes
    if type(modes) ~= "table" or #modes == 0 or type(Screen.getRotationMode) ~= "function" then
        return false, "unavailable"
    end
    local read_ok, current = pcall(Screen.getRotationMode, Screen)
    if not read_ok then return false, "unavailable" end
    local next_mode = modes[1]
    for index, mode in ipairs(modes) do
        if mode == current then next_mode = modes[index % #modes + 1]; break end
    end
    local Event = require("ui/event")
    UIManager:broadcastEvent(Event:new("SetRotationMode", next_mode))
    UIManager:scheduleIn(.4, function()
        local now_ok, now = pcall(Screen.getRotationMode, Screen)
        if now_ok and now == current and type(Screen.setRotationMode) == "function" then
            pcall(Screen.setRotationMode, Screen, next_mode)
        end
    end)
    return true
end

---------------------------------------------------------------------------
-- Relayout
---------------------------------------------------------------------------

-- Updates widget.dimen in place. Many widgets captured `self.dimen` itself as
-- a touch range; mutating the table keeps those ranges correct.
local function refreshDimen(widget, size)
    if type(widget.dimen) == "table" then
        widget.dimen.w, widget.dimen.h = size.w, size.h
    else
        widget.dimen = size
    end
end

local function needsRelayout(widget, size)
    local dimen = widget.dimen
    local mode_ok, mode = pcall(Screen.getRotationMode, Screen)
    if widget._rotation_mode ~= nil and mode_ok and mode ~= widget._rotation_mode then return true, mode end
    if type(dimen) ~= "table" then return true, mode end
    return dimen.w ~= size.w or dimen.h ~= size.h, mode
end

local function relayout(widget, spec)
    local size = Screen:getSize()
    local changed, mode = needsRelayout(widget, size)
    if not changed then return false end
    widget._rotation_mode = mode
    refreshDimen(widget, size)
    local ok, err = pcall(spec.relayout, widget, size)
    if not ok then
        local logger_ok, logger = pcall(require, "logger")
        if logger_ok then logger.warn("AppDock relayout failed:", err) end
        if spec.close_on_failure then UIManager:close(widget) end
        return false
    end
    -- One clean full refresh: partial updates after a rotation leave ghosts of
    -- the old orientation on E-Ink.
    UIManager:setDirty(widget, "full")
    return true
end

local function scheduleRelayout(widget, spec)
    widget._rotation_generation = (widget._rotation_generation or 0) + 1
    local generation = widget._rotation_generation
    local attempts = 0
    local function check()
        if widget._rotation_generation ~= generation or widget._rotation_closed then return end
        attempts = attempts + 1
        if relayout(widget, spec) then return end
        -- The rotation may not have been applied yet when the event reached
        -- us (widgets above KOReader's own handler run first): look again.
        if attempts < RELAYOUT_RETRIES then UIManager:scheduleIn(RELAYOUT_DELAY * (attempts + 1), check) end
    end
    UIManager:scheduleIn(RELAYOUT_DELAY, check)
end

local specs = setmetatable({}, { __mode = "k" })

--- Tells every live AppDock widget that the screen was rotated.
function Rotation.notify()
    for widget in pairs(live) do
        local spec = specs[widget]
        if spec and not widget._rotation_closed then scheduleRelayout(widget, spec) end
    end
end

--- Wraps Screen:setRotationMode once, so every way of rotating is noticed.
function Rotation.hook()
    if hooked then return true end
    if type(Screen.setRotationMode) ~= "function" then return false end
    local original = Screen.setRotationMode
    Screen.setRotationMode = function(self, mode, ...)
        local before_ok, before = pcall(self.getRotationMode, self)
        local result = original(self, mode, ...)
        local after_ok, after = pcall(self.getRotationMode, self)
        if not (before_ok and after_ok) or before ~= after then Rotation.notify() end
        return result
    end
    hooked = true
    return true
end

--- Makes `Class` (a full-screen AppDock widget class) follow rotations.
---   spec.relayout(widget, size)  rebuild the widget for the new size (the
---                                widget's `dimen` is already updated)
---   spec.close_on_failure        close the widget when relayout throws
function Rotation.attach(Class, spec)
    if type(Class) ~= "table" or type(spec) ~= "table" or type(spec.relayout) ~= "function" then return Class end
    if rawget(Class, "_rotation_attached") then return Class end
    Class._rotation_attached = true
    Rotation.hook()

    local original_init = Class.init
    Class.init = function(self, ...)
        live[self] = true
        specs[self] = spec
        self._rotation_closed = false
        local mode_ok, mode = pcall(Screen.getRotationMode, Screen)
        if mode_ok then self._rotation_mode = mode end
        Rotation.apply()
        if original_init then return original_init(self, ...) end
    end

    local original_close = Class.onCloseWidget
    Class.onCloseWidget = function(self, ...)
        self._rotation_closed = true
        live[self] = nil
        specs[self] = nil
        -- Let go of the sensor only when no AppDock screen follows this one
        -- (a host replaced by the homescreen opens its successor first).
        UIManager:scheduleIn(.6, function() Rotation.release() end)
        if original_close then return original_close(self, ...) end
    end

    -- KOReader events; the Screen hook above makes these redundant but they
    -- cost nothing and cover builds where the method is not wrapped.
    local function handler(self)
        if specs[self] then scheduleRelayout(self, spec) end
        return false
    end
    Class.onSetRotationMode = Class.onSetRotationMode or handler
    Class.onScreenResize = Class.onScreenResize or handler
    Class.onSetDimensions = Class.onSetDimensions or handler
    return Class
end

Rotation._test = { live = live, relayout = relayout, needsRelayout = needsRelayout }

return Rotation
