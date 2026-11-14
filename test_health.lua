-- Logic and screen smoke test for appdock_health.lua. Run with:
--   APPDOCK_PLUGIN_DIR=appdock.koplugin/ lua test_health.lua
local dir = os.getenv("APPDOCK_PLUGIN_DIR") or "./appdock.koplugin/"
package.path = dir .. "?.lua;" .. package.path

local function baseClass(prototype)
    prototype = prototype or {}
    prototype.__index = prototype
    function prototype:extend(child)
        child = child or {}
        child.__index = child
        setmetatable(child, { __index = self })
        return child
    end
    function prototype:new(args)
        local instance = setmetatable(args or {}, self)
        if instance.init then instance:init() end
        return instance
    end
    function prototype:clear() for k in pairs(self) do if type(k) == "number" then self[k] = nil end end end
    function prototype:getSize() return { w = self.width or 10, h = self.height or 10 } end
    return prototype
end
local Widget = baseClass({})

local shown, scheduled = {}, {}
local saved = {}
_G.G_reader_settings = {
    readSetting = function(_, key, default) if saved[key] == nil then saved[key] = default end return saved[key] end,
    saveSetting = function(_, key, value) saved[key] = value end,
    flush = function() end,
}
local frontlight = { intensity = 5, warmth = 0, off = 0 }
local powerd = {
    fl_min = 0, fl_max = 24, fl_warmth_min = 0, fl_warmth_max = 100,
    setIntensity = function(_, v) frontlight.intensity = v end,
    setWarmth = function(_, v) frontlight.warmth = v end,
    turnOffFrontlight = function() frontlight.off = frontlight.off + 1 end,
    frontlightIntensity = function() return frontlight.intensity end,
}
package.preload["device"] = function()
    return {
        screen = { scaleBySize = function(_, n) return n end, getSize = function() return { w = 600, h = 800 } end },
        hasKeys = function() return false end,
        hasFrontlight = function() return true end,
        hasNaturalLight = function() return true end,
        getPowerDevice = function() return powerd end,
    }
end
package.preload["ui/uimanager"] = function()
    return {
        nextTick = function(_, cb) cb() end,
        scheduleIn = function(_, _, cb) scheduled[#scheduled + 1] = cb end,
        unschedule = function() end,
        setDirty = function() end,
        show = function(_, w) shown[#shown + 1] = w end,
        close = function() end,
    }
end
package.preload["gettext"] = function() return function(t) return t end end
package.preload["appdock_dialogs"] = function() return { ButtonDialog = Widget, ConfirmBox = Widget } end
package.preload["ffi/blitbuffer"] = function()
    return { COLOR_WHITE = 1, COLOR_BLACK = 0, COLOR_LIGHT_GRAY = 180, COLOR_DARK_GRAY = 80, COLOR_GRAY = 120 }
end
package.preload["ui/font"] = function() return { getFace = function() return {} end } end
package.preload["ui/geometry"] = function() return { new = function(_, a) return a end } end
package.preload["ui/gesturerange"] = function() return { new = function(_, a) return a end } end
package.preload["ui/widget/container/inputcontainer"] = function() return baseClass({}) end
package.preload["ui/widget/container/centercontainer"] = function() return Widget end
package.preload["ui/widget/container/framecontainer"] = function() return Widget end
package.preload["ui/widget/horizontalspan"] = function() return Widget end
package.preload["ui/widget/overlapgroup"] = function() return Widget end
package.preload["ui/widget/textwidget"] = function() return Widget end
package.preload["ui/widget/textboxwidget"] = function() return Widget end

local Health = require("appdock_health")
local failures = 0
local function check(name, cond)
    if not cond then failures = failures + 1; print("FAIL: " .. name) end
end

local saves = 0
local appdock = { settings = { language = "de", health = { eye = { points = "garbage" } } }, _saveSettings = function() saves = saves + 1 end }

-- config normalisation
local cfg = Health.config(appdock)
check("defaults restored", #cfg.eye.points == 4 and cfg.eye.points[2].t == 720)
check("stats default on", cfg.stats.enabled == true)
check("breaks clamp", cfg.breaks.interval == 30 and cfg.breaks.length == 5)

-- curve
local b, w = Health.curveAt(cfg.eye, 720)
check("midday anchor", b == 70 and w == 0)
b, w = Health.curveAt(cfg.eye, 570) -- halfway morning(420,40)..midday(720,70)
check("interpolation", math.abs(b - 55) < 0.01 and math.abs(w - 5) < 0.01)
b = Health.curveAt(cfg.eye, 30) -- wraps night(1350)->morning(420)
check("wraps midnight", math.abs(b - 20.88) < 0.1)
b = Health.curveAt(cfg.eye, 1400)
check("after night", math.abs(b - 17.45) < 0.1)

-- editing keeps order and gap
Health.setAnchor(appdock, 2, 100, "b", 150)
check("anchor clamped to gap", cfg.eye.points[2].t == 450 and cfg.eye.points[2].b == 100)
Health.setAnchor(appdock, 4, 5000)
check("night max", cfg.eye.points[4].t == 1439)
check("saved", saves >= 2)
check("preset", Health.applyPreset(appdock, "owl") and Health.config(appdock).eye.points[1].t == 510)
check("bad preset", Health.applyPreset(appdock, "nope") == false)

-- applying to the device
Health.setEyeEnabled(appdock, true)
check("intensity applied", frontlight.intensity > 0 and frontlight.intensity <= 24)
check("warmth applied", frontlight.warmth >= 0 and frontlight.warmth <= 100)
local before = frontlight.intensity
frontlight.intensity = 99
check("no re-apply without change", Health.applyEye(appdock, false) == false and frontlight.intensity == 99)
check("force re-apply", Health.applyEye(appdock, true) and frontlight.intensity == before)

-- formatting
check("duration 0", Health.formatDuration(0) == "0 min")
check("duration <1", Health.formatDuration(20) == "<1 min")
check("duration min", Health.formatDuration(42 * 60) == "42 min")
check("duration h", Health.formatDuration(3900) == "1 h 05 min")
check("clock", Health.formatClock(5) == "00:05" and Health.formatClock(1439) == "23:59")
check("german text", Health.t(appdock, "cat_title") == "Gesundheit und Lesen")
check("english text", Health.t({ settings = {} }, "cat_title") == "Health & reading")

-- statistics
Health.resetStats()
Health.addTime("read", 600)
Health.addTime("on", 1200)
Health.addTime("bogus", 5)
local r, o = Health.dayTotals(0)
check("today totals", r == 600 and o == 1200)
check("streak", Health.streak() == 1)
check("totals", Health.getStats().total_read == 600 and Health.getStats().total_on == 1200)

-- rows
local rows = Health.settingsRows(appdock, {})
check("five rows", #rows == 5 and rows[1].section == "Augenschutz")
check("eye row on", rows[1].subtitle:find("An ·", 1, true) ~= nil)

-- ticker: reading time, break reminder
local state = Health.attach(appdock)
local cfg2 = Health.config(appdock)
cfg2.breaks.enabled = true
cfg2.breaks.interval = 10
appdock.ui = { document = {} }
state.last_activity = os.time()
state.last_tick = os.time() - 60
Health.touch(state)
state.tick()
local read_after = Health.dayTotals(0)
check("reading counted", read_after >= 660)
state.streak = 10 * 60
shown = {}
state.last_activity = os.time()
state.tick()
check("break dialog shown", #shown == 1 and state.dialog_open == true)

-- screens build without error
for _, page in ipairs({ "eye", "stats", "care" }) do
    shown = {}
    local ok, err = pcall(Health.show, appdock, { requestRebuild = function() end }, page)
    check("screen " .. page .. " " .. tostring(err), ok and err == true and #shown == 1)
    if shown[1] then
        local screen = shown[1]
        check("screen layers " .. page, #screen.layers > 5 and #screen.hits > 0)
        -- tap the first hit: must not error
        local tapped, terr = pcall(function()
            for i = 1, #screen.hits do screen.hits[i].fn({ x = screen.hits[i].x + 2, y = screen.hits[i].y + 2 }) end
        end)
        check("taps " .. page .. " " .. tostring(terr), tapped)
    end
end

Health.detach(state)
if failures == 0 then print("test_health: all checks passed") else os.exit(1) end
