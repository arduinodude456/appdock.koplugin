--[[--
AppDock Draw's KOReader stylus bridge.

KOReader already parses Kobo stylus contacts and exposes them through
Device.input:registerStylusCallback(input, slot). This is the same callback
path used by quicky.koplugin and avoids depending on private raw-event hooks.
--]]--

local Device = require("device")
local ok_input, Input = pcall(require, "device/input")
if not ok_input then Input = nil end

local Stylus = {
    canvas = nil,
    callback = nil,
    pressure = nil,
    pressure_hook_registered = false,
}

local function number(value)
    return tonumber(value)
end

local function normalizePressure(value)
    value = number(value)
    if not value then return nil end
    -- Kobo's pressure sensor is normally 0..4095. Some KOReader/device
    -- backends already expose a 0..1 value, so preserve that representation.
    if value > 1 then return math.max(0, math.min(1, value / 4095)) end
    return math.max(0, math.min(1, value))
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
        pressure = normalizePressure(slot.pressure or slot.p or self.pressure),
        id = slot.id,
    }
end

function Stylus:_registerPressureHook()
    if self.pressure_hook_registered or not Input
        or type(Input.registerEventAdjustHook) ~= "function" then return false end
    local ok = pcall(Input.registerEventAdjustHook, Input, function(_, event)
        -- Quicky's InputListener records this exact Kobo sensor value. The
        -- parsed stylus slot does not expose it reliably on every KOReader
        -- build, so retain the latest raw value as a callback fallback.
        if type(event) == "table" and tonumber(event.code) == 24 then
            self.pressure = tonumber(event.value)
        end
    end, { name = "AppDock Draw Kobo stylus pressure" })
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
        input:unregisterStylusCallback()
    end
    if self.canvas and type(self.canvas.finishStylus) == "function" then
        self.canvas:finishStylus()
    end
    self.canvas = nil
    self.callback = nil
    return true
end

return Stylus
