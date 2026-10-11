-- Regression tests for the KOReader stylus callback used by AppDock Draw.
local plugin_dir = os.getenv("APPDOCK_PLUGIN_DIR") or "/home/ubuntu/appdock.koplugin/appdock.koplugin/"

local registered, registered_callback = 0, nil
local unregistered = 0
local input = {
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

local function emit(flags, slot)
    assert(registered_callback(flags or {}, slot), "A valid KOReader stylus slot must reach Draw")
end

emit({ stylus_eraser_active = true }, { id = 101, x = 120, y = 160, tool = "pen", pressure = 2048 })
assert(samples[1].sample.eraser and samples[1].sample.tool == "eraser", "KOReader eraser state must select eraser input")
assert(math.abs(samples[1].sample.pressure - 2048 / 4095) < 0.0001, "Raw Kobo pressure must be normalized")

emit({ stylus_highlighter_active = true }, { id = 102, x = 220, y = 260, tool = "pen", p = 4095 })
assert(samples[2].sample.marker_button and not samples[2].sample.eraser, "KOReader highlighter state must select marker input")
assert(samples[2].sample.pressure == 1, "Maximum raw pressure must normalize to one")

emit({}, { id = 103, x = 320, y = 360, tool = "eraser", pressure = .5 })
assert(samples[3].sample.eraser, "A parsed eraser tool must also be accepted")
assert(samples[3].sample.pressure == .5, "Already normalized pressure must remain unchanged")

assert(Stylus:deactivate(canvas), "Leaving Draw must unregister the stylus callback")
assert(unregistered == 1 and not registered_callback, "KOReader stylus callback must be removed on pane deactivation")
print("AppDock stylus callback tests passed")
