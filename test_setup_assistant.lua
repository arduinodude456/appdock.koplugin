local plugin_dir = os.getenv("APPDOCK_PLUGIN_DIR") or "./"

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
    return prototype
end

local WidgetContainer = baseClass({})
local saved_settings = {}
local log = { offers = 0, saves = 0, sleep_show = 0, sleep_close = 0 }

_G.G_reader_settings = {
    readSetting = function() return saved_settings end,
    saveSetting = function(_, _, value) saved_settings = value; log.saves = log.saves + 1 end,
    isTrue = function() return false end,
}

package.preload["gettext"] = function() return function(text) return text end end
package.preload["pluginloader"] = function() return { loadPlugins = function() return {} end } end
package.preload["ui/widget/container/widgetcontainer"] = function() return WidgetContainer end
package.preload["ui/widget/buttondialog"] = function() return WidgetContainer end
package.preload["ui/widget/infomessage"] = function() return WidgetContainer end
package.preload["ui/uimanager"] = function()
    return {
        nextTick = function(_, callback) callback() end,
        scheduleIn = function() end,
        unschedule = function() end,
        setDirty = function() end,
        forceRePaint = function() end,
        show = function() end,
    }
end
package.preload["appdock_theme"] = function()
    return { normalizeDesignDefinition = function() return nil end }
end
package.preload["appdock_wallpaper"] = function()
    return { isValidPath = function() return false end }
end
package.preload["appdock_sleepscreen"] = function()
    return {
        show = function() log.sleep_show = log.sleep_show + 1 end,
        close = function() log.sleep_close = log.sleep_close + 1 end,
    }
end
package.preload["appdock_dapps"] = function()
    return {
        new = function()
            return {
                runPermittedAutostarts = function() end,
                restoreWorkspace = function() return false end,
                showSetupAssistant = function(_, _, _, automatic)
                    assert(automatic == true, "Only the update-triggered assistant should use automatic mode")
                    log.offers = log.offers + 1
                end,
            }
        end,
    }
end

local AppDock = dofile(plugin_dir .. "main.lua")
local ui = { menu = { registerToMainMenu = function() end } }
local first = AppDock:new{ ui = ui }
local first_status = first:getSetupAssistantStatus()
assert(first_status.version == "6.0.6" and first_status.offered and not first_status.completed, "A new AppDock version must offer the assistant once and record that offer locally")
assert(log.offers == 1, "The update-triggered assistant must be shown once")
assert(first:setSleepScreenEnabled(true) and first.settings.sleepscreen_enabled, "The Sleep screen toggle must persist locally")
first:onSuspend()
assert(log.sleep_show == 1, "An enabled Sleep screen must be shown on Suspend")
first:onResume()
assert(log.sleep_close == 1, "The Sleep screen must close on Resume")
first:completeSetupAssistant()
assert(first:getSetupAssistantStatus().completed and not first:shouldOfferSetupAssistant(), "Completing setup must prevent repeat offers for the same version")
local second = AppDock:new{ ui = ui }
assert(log.offers == 1 and second:getSetupAssistantStatus().completed and not second:shouldOfferSetupAssistant(), "A completed local setup must not reappear after a KOReader restart")
print("Setup assistant test: OK")
