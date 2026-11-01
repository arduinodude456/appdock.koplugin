--[[--
AppDock Draw's KOReader stylus bridge.

KOReader already parses Kobo stylus contacts and exposes them through
Device.input:registerStylusCallback(input, slot). This is the same callback
path used by quicky.koplugin and avoids depending on private raw-event hooks.
--]]--

local Device = require("device")
local ok_input, Input = pcall(require, "device/input")
if not ok_input then Input = nil end

local EV_ABS = 3

local Stylus = {
    canvas = nil,
    callback = nil,
    pressure = nil,
    pressure_hook_registered = false,
    raw_scale = false,   -- true once a raw (>1) pressure value was seen
    max_pressure = 4095, -- Kobo's pressure sensor is normally 0..4095
}

local function number(value)
    return tonumber(value)
end

local function clamp01(value)
    return math.max(0, math.min(1, value))
end

-- Some KOReader/device backends already expose a 0..1 value, others the raw
-- 0..4095 sensor value. The first value above 1 proves the raw scale; from then
-- on every value is divided, so a raw reading of 1 (the lightest touch) is no
-- longer mistaken for full pressure.
function Stylus:_normalizePressure(value)
    value = number(value)
    if not value then return nil end
    if value > 1 then self.raw_scale = true end
    if self.raw_scale then
        if value > self.max_pressure then self.max_pressure = value end
        return clamp01(value / self.max_pressure)
    end
    return clamp01(value)
end

function Stylus:_sample(input, slot)
    if type(slot) ~= "table" then return nil end
    local x, y = number(slot.x), number(slot.y)
    if not x or not y then return nil end

    local eraser = input and input.stylus_eraser_active == true
    local marker = input and input.stylus_highlighter_active == true
    local tool = tostring(slot.tool or slot.tool_type or ""):lower()
    if tool:find("eraser", 1, true) or tool:find("rubber", 1, true) then eraser = true end
    if tool:find("highlight", 1, true) or tool:find("marker", 1, true) then marker = true end

    return {
        pos = { x = x, y = y },
        pointer_type = "stylus",
        tool = eraser and "eraser" or "stylus",
        stylus = true,
        eraser = eraser,
        marker_button = marker,
        pressure = self:_normalizePressure(slot.pressure or slot.p or self.pressure),
        -- Canvas:handleStylusSample uses the id to tell one contact from the
        -- next. A missing id must not look like "no contact yet", otherwise
        -- every sample would start a new stroke and a new undo entry.
        id = slot.id or slot.tracking_id or 0,
    }
end

function Stylus:_registerPressureHook()
    if self.pressure_hook_registered then return true end
    -- The hook chain lives on the Input *instance* (Device.input). Registering
    -- on the class table from require("device/input") is shadowed by the
    -- instance's own eventAdjustHook, so the hook would never run and pressure
    -- would silently stay nil.
    local target = Device and Device.input
    if not (target and type(target.registerEventAdjustHook) == "function") then target = Input end
    if not target or type(target.registerEventAdjustHook) ~= "function" then return false end
    local configured_pressure_code = tonumber(target.pressure_event) or 58
    local ok = pcall(target.registerEventAdjustHook, target, function(input, event)
        -- KOReader configures Kobo Elipsa/Sage/Libra-family devices with
        -- ABS_MT_PRESSURE (Linux code 58). Code 24 is ABS_PRESSURE and is only
        -- the legacy fallback on older devices; do not read it when KOReader
        -- explicitly selected another pressure axis.
        local pressure_code = tonumber(input and input.pressure_event) or configured_pressure_code
        if type(event) == "table" and (event.type == nil or event.type == EV_ABS)
            and tonumber(event.code) == pressure_code then
            self.pressure = tonumber(event.value)
        end
    end, { name = "AppDock Draw KOReader pressure axis" })
    if ok then self.pressure_hook_registered = true end
    return ok
end

function Stylus:_callback(input, slot)
    local canvas = self.canvas
    if not canvas then return false end
    -- KOReader routes the lift through the stylus callback as the same slot
    -- with id == -1. It has no meaningful drawing point and must never enter
    -- handleStylusSample, otherwise a lift can be mistaken for a new point.
    if type(slot) == "table" and slot.id == -1 then
        -- Forget the last pressure so the next stroke does not start with it.
        self.pressure = nil
        if type(canvas.finishStylus) == "function" then canvas:finishStylus() end
        return true
    end
    local sample = self:_sample(input, slot)
    if not sample then return false end
    if type(canvas.handleStylusSample) ~= "function" then return false end
    return canvas:handleStylusSample(sample, sample.id)
end

function Stylus:activate(canvas)
    if not canvas then return false end
    local input = Device and Device.input
    if not input or type(input.registerStylusCallback) ~= "function" then return false end
    self:_registerPressureHook()
    if self.canvas and self.canvas ~= canvas then self:deactivate(self.canvas) end
    if self.canvas == canvas and self.callback then return true end

    self.canvas = canvas
    self.callback = function(device_input, slot)
        return self:_callback(device_input, slot)
    end
    input:registerStylusCallback(self.callback)
    return true
end

function Stylus:deactivate(canvas)
    if canvas and self.canvas ~= canvas then return false end
    local input = Device and Device.input
    if input and type(input.unregisterStylusCallback) == "function" and self.callback then
        -- Do not remove a callback another plugin installed in the meantime.
        local current = input.stylus_callback
        if current == nil or current == self.callback then
            input:unregisterStylusCallback()
        end
    end
    local previous = self.canvas
    self.canvas = nil
    self.callback = nil
    self.pressure = nil
    if previous and type(previous.finishStylus) == "function" then
        previous:finishStylus()
    end
    return true
end

return Stylus
