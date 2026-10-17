local plugin_dir = os.getenv("APPDOCK_PLUGIN_DIR") or "./appdock.koplugin/"

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
_G.G_reader_settings = {
    readSetting = function() return saved_settings end,
    saveSetting = function(_, _, value) saved_settings = value end,
}

package.preload["gettext"] = function() return function(text) return text end end
package.preload["pluginloader"] = function() return { loadPlugins = function() return {} end } end
package.preload["ui/widget/container/widgetcontainer"] = function() return WidgetContainer end
package.preload["ui/widget/imagewidget"] = function() return {} end
package.preload["appdock_dialogs"] = function() return { ButtonDialog = WidgetContainer, InfoMessage = WidgetContainer } end
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
package.preload["appdock_dapps"] = function()
    return {
        new = function()
            return {
                getCatalogApps = function()
                    return {
                        { id = "dapp:a", title = "Alpha", kind = "dapp", dapp_id = "a" },
                        { id = "dapp:b", title = "Beta", kind = "dapp", dapp_id = "b" },
                    }
                end,
                runPermittedAutostarts = function() end,
                getStoreWidgets = function() return {} end,
            }
        end,
    }
end

local AppDock = dofile(plugin_dir .. "main.lua")
local ui = { menu = { registerToMainMenu = function() end } }

-- Missing wallpaper settings represent a fresh installation: it gets the local
-- bundled background without requiring a setup-assistant path.
local fresh = AppDock:new{ ui = ui }
assert(fresh.settings.wallpaper.enabled and fresh.settings.wallpaper.source == "appdock_default")
assert(fresh.settings.wallpaper.path:match("assets/wallpaper/appdock_default%.svg$"))

-- An explicit custom wallpaper remains byte-for-byte selected when settings
-- are loaded, while the same app list is converted to one folder tile.
saved_settings = {
    wallpaper = { enabled = true, path = "/home/reader/custom.png", source = "user" },
    pinned_apps = { "dapp:a", "dapp:b", "system:library" },
    layout_version = 25,
}
local appdock = AppDock:new{ ui = ui }
assert(appdock.settings.wallpaper.path == "/home/reader/custom.png")
local ok, group_id = appdock:createAppGroup("  Reading  ", { "dapp:a", "dapp:b" })
assert(ok and group_id == "folder:1")
assert(#appdock.settings.pinned_apps == 2 and appdock.settings.pinned_apps[1] == group_id)
assert(appdock:getAppGroup(group_id).title == "Reading")
assert(#appdock:getAppGroupApps(group_id) == 2)
assert(appdock:movePinned(group_id, 1), "a folder must move exactly like one app tile")
assert(appdock.settings.pinned_apps[2] == group_id)
assert(appdock:renameAppGroup(group_id, "Books"))

-- Removing a member through management keeps it visible as a standalone tile;
-- moving an app between folder members must never silently discard it.
assert(appdock:setAppGroupMembers(group_id, { "dapp:b", "system:library" }))
assert(appdock.settings.pinned_apps[1] == group_id)
assert(appdock.settings.pinned_apps[2] == "dapp:a")
assert(appdock:isPinned("dapp:a") and appdock:isPinned("dapp:b"))
assert(appdock:ungroupAppGroup(group_id))
assert(not appdock:isAppGroup(group_id))
assert(#appdock.settings.app_groups.items == 0)

-- A saved group round-trips through a new AppDock instance with one order slot.
local again_ok, again_group = appdock:createAppGroup("Tools", { "dapp:a", "dapp:b" })
assert(again_ok)
local reloaded = AppDock:new{ ui = ui }
assert(reloaded:isAppGroup(again_group))
assert(reloaded:getPinnedPosition(again_group) ~= nil)
assert(#reloaded:getPinnedApps() == 2, "folder must occupy one grid slot after reload")

print("app-group-pinning-ok")
