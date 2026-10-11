-- Regression tests for the Kobo raw stylus bridge used by AppDock Draw.
local plugin_dir = os.getenv("APPDOCK_PLUGIN_DIR") or "/home/ubuntu/appdock.koplugin/appdock.koplugin/"

local registered_hook
local original_calls = 0
local recorded_subtools = {}
local detector = {
    feedEvent = function(_, events)
        original_calls = original_calls + 1
        return events
    end,
}
local screen = {
    width = 600,
    height = 800,
    DEVICE_ROTATED_UPRIGHT = 0,
    DEVICE_ROTATED_COUNTER_CLOCKWISE = 1,
    DEVICE_ROTATED_CLOCKWISE = 2,
    DEVICE_ROTATED_UPSIDE_DOWN = 3,
    rotation = 0,
    getWidth = function(self) return self.width end,
    getHeight = function(self) return self.height end,
    getRotationMode = function(self) return self.rotation end,
}
local device = {
    isKobo = true,
    screen = screen,
    input = {
        gesture_detector = detector,
        setCurrentMtSlotChecked = function(_, field, value)
            recorded_subtools[#recorded_subtools + 1] = { field = field, value = value }
        end,
    },
}

package.preload["device"] = function() return device end
package.preload["device/input"] = function()
    return {
        registerEventAdjustHook = function(_, callback)
            registered_hook = callback
        end,
    }
end

local Stylus = dofile(plugin_dir .. "appdock_stylus.lua")
assert(Stylus:ensureEventHook() and registered_hook,
    "The Kobo event-adjust hook must register once before Draw activates")

local samples, finished = {}, {}
local canvas = {
    handleStylusSample = function(_, sample, tracking_id)
        samples[#samples + 1] = { sample = sample, tracking_id = tracking_id }
        return true
    end,
    finishStylus = function(_, tracking_id)
        finished[#finished + 1] = tracking_id
        return true
    end,
}
local original_feed = detector.feedEvent
assert(Stylus:activate(canvas), "The raw stylus listener must wrap KOReader's gesture detector")
assert(detector.feedEvent ~= original_feed,
    "Activating Draw must preserve and wrap the previous gesture-detector callback")

local function raw(code, value)
    registered_hook(device.input, { code = code, value = value }, {})
end

-- Eraser + pressure: this is the important path from quicky.koplugin. Pressure
-- must remain associated with the same tracking slot instead of hiding eraser.
raw(47, 0) -- ABS_MT_SLOT
raw(57, 101) -- ABS_MT_TRACKING_ID
raw(331, 1) -- Kobo eraser button
raw(24, 2048) -- Kobo pressure sensor
detector.feedEvent(detector, { { slot = 0, id = 101, x = 120, y = 160, tool = 1 } })
assert(#samples == 1 and samples[1].tracking_id == 101,
    "A pen slot must reach the active Draw canvas")
assert(samples[1].sample.eraser and samples[1].sample.tool == "eraser",
    "The Kobo eraser button must select eraser input")
assert(math.abs(samples[1].sample.pressure - 2048 / 4095) < 0.0001,
    "Raw Kobo pressure must be normalized to Draw's 0..1 pressure range")
assert(recorded_subtools[#recorded_subtools].field == "subtool"
        and recorded_subtools[#recorded_subtools].value == 2,
    "The parsed KOReader slot must retain the eraser subtype")

-- A new tracking id must reset the previous button state. Marker input remains
-- a pen color with the Draw marker-width flag instead of becoming an eraser.
raw(57, 202)
raw(332, 1)
raw(24, 4095)
detector.feedEvent(detector, { { slot = 0, id = 202, x = 220, y = 260, tool = 1 } })
assert(#samples == 2 and samples[2].tracking_id == 202,
    "A second stylus contact must be delivered independently")
assert(samples[2].sample.marker_button and not samples[2].sample.eraser,
    "The Kobo marker button must set Draw's marker flag without selecting eraser")
assert(samples[2].sample.pressure == 1,
    "Maximum raw pressure must normalize to one")

-- Match Quicky's screen-rotation handling so the Draw canvas receives display
-- coordinates rather than the unrotated kernel axis.
screen.rotation = screen.DEVICE_ROTATED_COUNTER_CLOCKWISE
raw(57, 303)
detector.feedEvent(detector, { { slot = 0, id = 303, x = 50, y = 20, tool = 1 } })
assert(samples[3].sample.pos.x == 20 and samples[3].sample.pos.y == 750,
    "Stylus coordinates must follow KOReader's counter-clockwise rotation mapping")
screen.rotation = screen.DEVICE_ROTATED_UPRIGHT

-- A released parsed slot must close precisely the active raw stroke; normal
-- KOReader gesture processing still receives every packet.
raw(57, -1)
detector.feedEvent(detector, { { slot = 0, id = -1 } })
assert(finished[#finished] == 303,
    "Lifting the stylus must finish the stroke tied to its tracking id")
assert(original_calls == 4,
    "The wrapper must always forward raw packets to KOReader's original gesture detector")

assert(Stylus:deactivate(canvas), "Deactivating Draw must restore normal input")
assert(detector.feedEvent == original_feed,
    "Leaving Draw must restore the exact prior gesture-detector callback")
print("AppDock stylus tests passed")
