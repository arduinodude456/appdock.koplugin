--[[--
AppDock Draw's Kobo stylus bridge.

KOReader's normal gesture events intentionally omit Kobo's raw stylus details.
This small adapter follows the input path used by quicky.koplugin: it records the
Kobo-specific kernel codes before they are parsed, then observes the parsed
multi-touch slots immediately before KOReader's gesture detector consumes them.
Only an active Draw canvas receives these samples; all normal KOReader input is
always passed on unchanged.
--]]--

local Device = require("device")
local Screen = Device.screen
local ok_input, Input = pcall(require, "device/input")
if not ok_input then Input = nil end

local Stylus = {
    canvas = nil,
    detector = nil,
    original_feed_event = nil,
    wrapper = nil,
    event_hook_registered = false,
    current_slot = 0,
    slots = {},
    tracks = {},
    active_tracks_by_slot = {},
}

-- Input-event constants from Kobo's stylus driver. 331 and 332 are the
-- eraser and highlighter buttons used by the Kobo Stylus; code 24 carries
-- pressure values in the 0..4095 range.
local CODES = {
    ABS_MT_SLOT = 47,
    ABS_MT_TRACKING_ID = 57,
    KOBO_STYLUS_SENSOR = 24,
    KOBO_STYLUS_ERASER = 331,
    KOBO_STYLUS_MARKER = 332,
}
local SUBTOOLS = { pen = 1, eraser = 2, marker = 3 }
local MAX_PRESSURE = 4095

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local function screenValue(method, field, fallback)
    local value
    if Screen and type(Screen[method]) == "function" then
        local ok, result = pcall(Screen[method], Screen)
        if ok then value = result end
    end
    value = tonumber(value or (Screen and Screen[field]))
    return value and value > 0 and value or fallback
end

function Stylus:_isKobo()
    local is_kobo = Device and Device.isKobo
    if type(is_kobo) == "function" then
        local ok, value = pcall(is_kobo, Device)
        return ok and value == true
    end
    return is_kobo == true
end

function Stylus:_slotState(slot, create)
    slot = tonumber(slot) or 0
    local state = self.slots[slot]
    if not state and create then
        state = { mode = "pen" }
        self.slots[slot] = state
    end
    return state, slot
end

function Stylus:_setCurrentSubtool(mode)
    -- Mirror Quicky's parsed-slot marker while Draw is active. This lets
    -- KOReader retain the correct stylus subtype without changing input while
    -- another AppDock screen is shown.
    if not self.canvas then return end
    local input = Device and Device.input
    if input and type(input.setCurrentMtSlotChecked) == "function" then
        pcall(input.setCurrentMtSlotChecked, input, "subtool", SUBTOOLS[mode] or SUBTOOLS.pen)
    end
end

function Stylus:eventAdjustmentHook(_, event)
    if not self:_isKobo() or type(event) ~= "table" then return end
    local code, value = event.code, event.value
    if code == CODES.ABS_MT_SLOT then
        self.current_slot = tonumber(value) or 0
        return
    end

    local state, slot = self:_slotState(self.current_slot, code ~= CODES.ABS_MT_TRACKING_ID or value ~= -1)
    if code == CODES.ABS_MT_TRACKING_ID then
        if value == -1 then
            local previous = self.slots[slot]
            if previous and previous.id ~= nil then self.tracks[previous.id] = nil end
            self.slots[slot] = nil
        else
            state = state or { mode = "pen" }
            state.id, state.mode, state.pressure = value, "pen", nil
            self.slots[slot] = state
            self.tracks[value] = state
        end
    elseif state and code == CODES.KOBO_STYLUS_ERASER then
        state.mode = value == 1 and "eraser" or "pen"
        self:_setCurrentSubtool(state.mode)
    elseif state and code == CODES.KOBO_STYLUS_MARKER then
        state.mode = value == 1 and "marker" or "pen"
        self:_setCurrentSubtool(state.mode)
    elseif state and code == CODES.KOBO_STYLUS_SENSOR then
        state.pressure = tonumber(value)
    end
end

function Stylus:_stateFor(event)
    local slot = tonumber(event and event.slot)
    local state = slot ~= nil and self.slots[slot] or nil
    if not state and event and event.id ~= nil then state = self.tracks[event.id] end
    return state, slot
end

function Stylus:_modeFor(event, state)
    if state and (state.mode == "eraser" or state.mode == "marker") then return state.mode end
    local subtool = event and tonumber(event.subtool)
    if subtool == SUBTOOLS.eraser then return "eraser" end
    if subtool == SUBTOOLS.marker then return "marker" end
    return "pen"
end

function Stylus:_screenPoint(event)
    local raw_x, raw_y = tonumber(event and event.x), tonumber(event and event.y)
    if not raw_x or not raw_y then return nil end
    local width = screenValue("getWidth", "width", 0)
    local height = screenValue("getHeight", "height", 0)
    if width <= 0 or height <= 0 then return nil end

    local rotation
    if Screen and type(Screen.getRotationMode) == "function" then
        local ok, value = pcall(Screen.getRotationMode, Screen)
        if ok then rotation = value end
    end
    local x, y = raw_x, raw_y
    if rotation == (Screen and Screen.DEVICE_ROTATED_COUNTER_CLOCKWISE) then
        x, y = raw_y, height - raw_x
    elseif rotation == (Screen and Screen.DEVICE_ROTATED_CLOCKWISE) then
        x, y = width - raw_y, raw_x
    elseif rotation == (Screen and Screen.DEVICE_ROTATED_UPSIDE_DOWN) then
        x, y = width - raw_x, height - raw_y
    end
    if x < 0 or y < 0 or x > width or y > height then return nil end
    return x, y
end

function Stylus:_sampleFor(event)
    if type(event) ~= "table" or event.id == nil or event.id == -1 then return nil end
    local state = self:_stateFor(event)
    local mode = self:_modeFor(event, state)
    local tool = tonumber(event.tool)
    -- KOReader uses tool=1 for a pen. A remembered subtype is accepted too,
    -- because some Kobo firmware reports the button event one packet before
    -- the pen tool type reaches the parsed slot.
    if tool ~= 1 and mode == "pen" then return nil end
    local x, y = self:_screenPoint(event)
    if not x then return nil end
    local pressure = state and tonumber(state.pressure) or nil
    if pressure then pressure = clamp(pressure / MAX_PRESSURE, 0, 1) end
    return {
        pos = { x = x, y = y },
        pointer_type = "stylus",
        tool = mode == "eraser" and "eraser" or "stylus",
        stylus = true,
        eraser = mode == "eraser",
        marker_button = mode == "marker",
        pressure = pressure,
    }
end

function Stylus:_feedEvents(events)
    local canvas = self.canvas
    if not canvas or type(events) ~= "table" then return end
    for _, event in pairs(events) do
        if type(event) == "table" then
            local slot = tonumber(event.slot) or 0
            if event.id == -1 then
                local tracking_id = self.active_tracks_by_slot[slot]
                if type(canvas.finishStylus) == "function" then canvas:finishStylus(tracking_id) end
                self.active_tracks_by_slot[slot] = nil
            else
                local sample = self:_sampleFor(event)
                if sample and type(canvas.handleStylusSample) == "function" then
                    self.active_tracks_by_slot[slot] = event.id
                    canvas:handleStylusSample(sample, event.id)
                end
            end
        end
    end
end

function Stylus:ensureEventHook()
    if self.event_hook_registered or not Input or type(Input.registerEventAdjustHook) ~= "function" then return false end
    local ok = pcall(Input.registerEventAdjustHook, Input, function(input, event, hook_params)
        self:eventAdjustmentHook(input, event, hook_params)
    end, { name = "AppDock Draw Kobo stylus" })
    if ok then self.event_hook_registered = true end
    return ok
end

function Stylus:activate(canvas)
    if not canvas then return false end
    self:ensureEventHook()
    if self.canvas == canvas and self.wrapper then return true end
    if self.canvas and self.canvas ~= canvas then self:deactivate(self.canvas) end

    local detector = Device and Device.input and Device.input.gesture_detector
    if not detector or type(detector.feedEvent) ~= "function" then return false end
    local original = detector.feedEvent
    local wrapper = function(detector_self, events)
        self:_feedEvents(events)
        return original(detector_self, events)
    end
    self.canvas, self.detector = canvas, detector
    self.original_feed_event, self.wrapper = original, wrapper
    detector.feedEvent = wrapper
    return true
end

function Stylus:deactivate(canvas)
    if canvas and self.canvas ~= canvas then return false end
    local active = self.canvas
    if active and type(active.finishStylus) == "function" then active:finishStylus() end
    if self.detector and self.detector.feedEvent == self.wrapper then
        self.detector.feedEvent = self.original_feed_event
    end
    self.canvas = nil
    self.active_tracks_by_slot = {}
    return true
end

Stylus.CODES = CODES
return Stylus
