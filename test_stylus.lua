-- Regression tests for the KOReader stylus callback used by AppDock Draw.
local plugin_dir = os.getenv("APPDOCK_PLUGIN_DIR") or "/home/ubuntu/appdock.koplugin/appdock.koplugin/"

local registered, registered_callback = 0, nil
local pressure_hook
local unregistered = 0
local input = {
    pressure_event = 58,
    registerStylusCallback = function(_, callback)
        registered = registered + 1
        registered_callback = callback
    end,
    unregisterStylusCallback = function()
        unregistered = unregistered + 1
        registered_callback = nil
    end,
}
local device = { input = input, isKobo = true }
package.preload["device"] = function() return device end
package.preload["device/input"] = function()
    return {
        registerEventAdjustHook = function(_, callback) pressure_hook = callback end,
    }
end

local Stylus = dofile(plugin_dir .. "appdock_stylus.lua")
local samples, finished = {}, {}
local canvas = {
    handleStylusSample = function(_, sample, tracking_id)
        samples[#samples + 1] = { sample = sample, tracking_id = tracking_id }
        return true
    end,
    finishStylus = function()
        finished[#finished + 1] = true
        return true
    end,
}

assert(Stylus:activate(canvas), "Draw must register KOReader's public stylus callback")
assert(registered == 1 and registered_callback, "The stylus callback must be installed exactly once")
assert(pressure_hook, "Draw must register the raw Kobo pressure fallback")

local function emit(flags, slot)
    assert(registered_callback(flags or {}, slot), "A valid KOReader stylus slot must reach Draw")
end

pressure_hook(input, { code = 24, value = 2048 })
assert(not samples[1], "Legacy ABS_PRESSURE code 24 must not override KOReader's configured axis")
pressure_hook(input, { code = 58, value = 2048 })
emit({ stylus_eraser_active = true }, { id = 101, x = 120, y = 160, tool = "pen" })
assert(samples[1].sample.eraser and samples[1].sample.tool == "eraser", "KOReader eraser state must select eraser input")
assert(math.abs(samples[1].sample.pressure - 2048 / 4095) < 0.0001, "Raw Kobo pressure must be normalized")

pressure_hook(input, { code = 58, value = 4095 })
emit({ stylus_highlighter_active = true }, { id = 102, x = 220, y = 260, tool = "pen" })
assert(samples[2].sample.marker_button and not samples[2].sample.eraser, "KOReader highlighter state must select marker input")
assert(samples[2].sample.pressure == 1, "Maximum raw pressure must normalize to one")

emit({}, { id = 103, x = 320, y = 360, tool = "eraser", pressure = .5 })
assert(samples[3].sample.eraser, "A parsed eraser tool must also be accepted")
assert(samples[3].sample.pressure == .5, "Already normalized pressure must remain unchanged")

assert(registered_callback({}, { id = -1, slot = 0 }), "The KOReader lift slot must be consumed")
assert(#finished == 1, "A stylus lift must finish the active stroke instead of becoming a new point")

assert(Stylus:deactivate(canvas), "Leaving Draw must unregister the stylus callback")
assert(unregistered == 1 and not registered_callback, "KOReader stylus callback must be removed on pane deactivation")
print("AppDock stylus callback tests passed")
