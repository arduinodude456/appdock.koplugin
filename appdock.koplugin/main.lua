--[[--
AppDock is an in-app homescreen for KOReader.
It exposes selected KOReader plugin menu actions as configurable app tiles.
--]]--

local ButtonDialog = require("ui/widget/buttondialog")
local InfoMessage = require("ui/widget/infomessage")
local PluginLoader = require("pluginloader")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local AppDock = WidgetContainer:extend{
    name = "appdock",
    is_doc_only = false,
    settings_key = "appdock_homescreen",
}

local DEFAULT_SETTINGS = {
    pinned_apps = {
        "system:library",
        "dapp:web_browser",
        "dapp:file_manager",
        "dapp:app_store",
        "dapp:analog_clock",
        "dapp:settings",
        "dapp:help",
        "system:open_apps",
        "system:menu",
        "system:history",
        "system:manage",
    },
    widgets = {
        clock = true,
        status = true,
        reading_hint = true,
        store = {},
    },
    did_seed = false,
    theme = { selected = "lavender", custom = {} },
    store = { installed = {} },
    layout = { app_spacing = 16, logo_shape = "rounded", search_enabled = false },
    launch_on_start = false,
    notifications = { items = {}, next_id = 0 },
    layout_version = 13,
}

local function copyArray(source)
    local result = {}
    for index, value in ipairs(source or {}) do
        result[index] = value
    end
    return result
end

function AppDock:init()
    self:_loadSettings()
    self.ui.menu:registerToMainMenu(self)
    self:_scheduleScreenRefresh()
    if self.settings.launch_on_start then
        UIManager:nextTick(function() self:showHome() end)
    end
end

function AppDock:_loadSettings()
    local stored = G_reader_settings:readSetting(self.settings_key, {})
    self.settings = {
        pinned_apps = copyArray(stored.pinned_apps or DEFAULT_SETTINGS.pinned_apps),
        widgets = stored.widgets or {
            clock = DEFAULT_SETTINGS.widgets.clock,
            status = DEFAULT_SETTINGS.widgets.status,
            reading_hint = DEFAULT_SETTINGS.widgets.reading_hint,
            store = {},
        },
        did_seed = stored.did_seed or false,
        theme = stored.theme or { selected = "lavender", custom = {} },
        store = stored.store or { installed = {} },
        layout = stored.layout or {},
        launch_on_start = stored.launch_on_start == true,
        notifications = stored.notifications or { items = {}, next_id = 0 },
        layout_version = stored.layout_version or 1,
    }

    self.settings.layout = self.settings.layout or {}
    if self.settings.launch_on_start == nil then self.settings.launch_on_start = false end
    self.settings.layout.app_spacing = tonumber(self.settings.layout.app_spacing) or DEFAULT_SETTINGS.layout.app_spacing
    self.settings.layout.app_spacing = math.max(8, math.min(34, self.settings.layout.app_spacing))
    self.settings.layout.logo_shape = self.settings.layout.logo_shape == "circle" and "circle" or "rounded"
    self.settings.layout.search_enabled = self.settings.layout.search_enabled == true

    if self.settings.layout_version < DEFAULT_SETTINGS.layout_version then
        local migrated = copyArray(DEFAULT_SETTINGS.pinned_apps)
        for _, app_id in ipairs(self.settings.pinned_apps) do
            if app_id:match("^plugin:") or app_id:match("^dapp:") then
                table.insert(migrated, app_id)
            end
        end
        self.settings.pinned_apps = migrated
        self.settings.layout_version = DEFAULT_SETTINGS.layout_version
    end

    if self.settings.widgets.clock == nil then
        self.settings.widgets.clock = true
    end
    if self.settings.widgets.status == nil then
        self.settings.widgets.status = true
    end
    if self.settings.widgets.reading_hint == nil then
        self.settings.widgets.reading_hint = self.settings.widgets.hint ~= false
    end
    self.settings.widgets.hint = nil
    self.settings.widgets.store = self.settings.widgets.store or {}
    self.settings.theme = self.settings.theme or { selected = "lavender", custom = {} }
    self.settings.theme.selected = self.settings.theme.selected or "lavender"
    self.settings.theme.custom = self.settings.theme.custom or {}
    self.settings.store = self.settings.store or { installed = {} }
    self.settings.store.installed = self.settings.store.installed or {}
    self.settings.notifications = self.settings.notifications or { items = {}, next_id = 0 }
    self.settings.notifications.items = self.settings.notifications.items or {}
    self.settings.notifications.next_id = tonumber(self.settings.notifications.next_id) or 0
    local normalized_notifications = {}
    for _, item in ipairs(self.settings.notifications.items) do
        if type(item) == "table" and type(item.title) == "string" and type(item.message) == "string" then
            table.insert(normalized_notifications, {
                id = tonumber(item.id) or 0,
                title = item.title:sub(1, 72),
                message = item.message:sub(1, 240),
                source = type(item.source) == "string" and item.source:sub(1, 48) or "AppDock",
                priority = item.priority == "high" and "high" or "normal",
                created_at = tonumber(item.created_at) or os.time(),
                read = item.read == true,
            })
        end
    end
    while #normalized_notifications > 50 do table.remove(normalized_notifications) end
    self.settings.notifications.items = normalized_notifications
    self:_saveSettings()
end

function AppDock:_saveSettings()
    G_reader_settings:saveSetting(self.settings_key, self.settings)
end

function AppDock:setLaunchOnStart(enabled)
    self.settings.launch_on_start = not not enabled
    self:_saveSettings()
end

function AppDock:setLauncherLayout(changes)
    changes = changes or {}
    if changes.app_spacing then
        self.settings.layout.app_spacing = math.max(8, math.min(34, tonumber(changes.app_spacing) or 16))
    end
    if changes.logo_shape == "circle" or changes.logo_shape == "rounded" then
        self.settings.layout.logo_shape = changes.logo_shape
    end
    if changes.search_enabled ~= nil then
        self.settings.layout.search_enabled = not not changes.search_enabled
    end
    self:_saveSettings()
end

function AppDock:getNotifications(limit)
    local items, result = self.settings.notifications.items or {}, {}
    local max_items = math.max(1, math.min(50, tonumber(limit) or #items))
    for index, item in ipairs(items) do
        if index > max_items then break end
        table.insert(result, item)
    end
    return result
end

function AppDock:getUnreadNotificationCount()
    local count = 0
    for _, item in ipairs(self.settings.notifications.items or {}) do
        if not item.read then count = count + 1 end
    end
    return count
end

function AppDock:notify(payload)
    if type(payload) ~= "table" then return false, "Notification payload must be a table." end
    local title, message = payload.title, payload.message
    if type(title) ~= "string" or title:match("^%s*$") then return false, "Notification title is required." end
    if type(message) ~= "string" or message:match("^%s*$") then return false, "Notification message is required." end
    self.settings.notifications.next_id = self.settings.notifications.next_id + 1
    local notification = {
        id = self.settings.notifications.next_id,
        title = title:sub(1, 72),
        message = message:sub(1, 240),
        source = type(payload.source) == "string" and payload.source:sub(1, 48) or "AppDock",
        priority = payload.priority == "high" and "high" or "normal",
        created_at = os.time(),
        read = false,
    }
    table.insert(self.settings.notifications.items, 1, notification)
    while #self.settings.notifications.items > 50 do table.remove(self.settings.notifications.items) end
    self:_saveSettings()
    local ok, Notifications = pcall(require, "appdock_notifications")
    if ok and Notifications and Notifications.showToast then Notifications.showToast(notification) end
    return true, notification
end

function AppDock:markNotificationRead(id)
    for _, item in ipairs(self.settings.notifications.items or {}) do
        if item.id == id then
            item.read = true
            self:_saveSettings()
            return true
        end
    end
    return false
end

function AppDock:markAllNotificationsRead()
    for _, item in ipairs(self.settings.notifications.items or {}) do item.read = true end
    self:_saveSettings()
end

function AppDock:clearNotifications()
    self.settings.notifications.items = {}
    self:_saveSettings()
end

function AppDock:setTheme(theme_id)
    local Theme = require("appdock_theme")
    for _, theme in ipairs(Theme.getThemeList(self.settings)) do
        if theme.id == theme_id then
            self.settings.theme.selected = theme_id
            self:_saveSettings()
            return true
        end
    end
    return false
end

function AppDock:createCustomTheme(title, hex)
    local Theme = require("appdock_theme")
    local id = Theme.createCustom(self.settings, title, hex)
    if id then self:_saveSettings() end
    return id
end

function AppDock:_scheduleScreenRefresh()
    if self._screen_refresh_tick then
        UIManager:unschedule(self._screen_refresh_tick)
    end
    self._screen_refresh_tick = function()
        -- A periodic full refresh is deliberate on E-Ink: it clears ghosting
        -- and refreshes static status content. Interactive controls use their
        -- own regional fast refreshes instead.
        UIManager:setDirty("all", "full")
        if UIManager.forceRePaint then UIManager:forceRePaint() end
        UIManager:scheduleIn(60, self._screen_refresh_tick)
    end
    UIManager:scheduleIn(60, self._screen_refresh_tick)
end

function AppDock:onCloseWidget()
    if self._screen_refresh_tick then
        UIManager:unschedule(self._screen_refresh_tick)
    end
end

function AppDock:addToMainMenu(menu_items)
    menu_items.appdock_homescreen = {
        text = _("AppDock Homescreen"),
        sorting_hint = "tools",
        callback = function()
            self:showHome()
        end,
        sub_item_table = {
            {
                text = _("Open homescreen"),
                callback = function()
                    self:showHome()
                end,
            },
            {
                text = _("Manage apps and widgets"),
                callback = function()
                    self:showManager()
                end,
            },
        },
    }
end

function AppDock:showHome()
    if not self._boot_shown then
        self._boot_shown = true
        local ok, Boot = pcall(require, "appdock_boot")
        if ok and Boot and Boot.show then
            Boot.show(function() self:showHome() end)
            return
        end
    end
    local HomeScreen = require("appdock_homescreen")
    UIManager:show(HomeScreen:new{ appdock = self })
end

function AppDock:showManager(home)
    local AppDockManager = require("appdock_manager")
    AppDockManager:show{ appdock = self, parent_home = home }
end

function AppDock:getDAppManager()
    if not self.dapp_manager then
        local DAppManager = require("appdock_dapps")
        self.dapp_manager = DAppManager:new(self)
    end
    return self.dapp_manager
end

function AppDock:showOpenApps(home)
    self:getDAppManager():showRecents(home)
end

function AppDock:getSystemApps()
    return {
        {
            id = "system:library",
            title = _("Library"),
            subtitle = _("Return to the file manager"),
            callback = function()
                if self.ui.showFileManager then
                    self.ui:showFileManager()
                else
                    UIManager:show(InfoMessage:new{
                        text = _("The library is already available from KOReader's main menu."),
                    })
                end
            end,
        },
        {
            id = "system:menu",
            title = _("Menu"),
            subtitle = _("Open KOReader main menu"),
            callback = function()
                if self.ui.menu and self.ui.menu.onShowMenu then
                    self.ui.menu:onShowMenu()
                end
            end,
        },
        {
            id = "system:history",
            title = _("History"),
            subtitle = _("Recently opened books"),
            callback = function()
                if self.ui.history and self.ui.history.onShowHist then
                    self.ui.history:onShowHist()
                else
                    UIManager:show(InfoMessage:new{
                        text = _("Reading history is unavailable in this context."),
                    })
                end
            end,
        },
        {
            id = "system:open_apps",
            title = _("Open apps"),
            subtitle = _("Switch between open DApps"),
            callback = function(home)
                self:showOpenApps(home)
            end,
        },
        {
            id = "system:manage",
            title = _("Manage apps and widgets"),
            subtitle = _("Add or remove homescreen items"),
            callback = function(home)
                self:showManager(home)
            end,
        },
    }
end

function AppDock:_makePluginApp(plugin_module)
    if plugin_module.name == self.name then
        return nil
    end

    local instance = self.ui[plugin_module.name]
    if not instance or type(instance.addToMainMenu) ~= "function" then
        return nil
    end

    local menu_items = {}
    local ok = pcall(instance.addToMainMenu, instance, menu_items)
    if not ok then
        return nil
    end

    local actions = {}
    for key, item in pairs(menu_items) do
        if type(item) == "table" and (type(item.callback) == "function" or type(item.sub_item_table) == "table") then
            local action_title = item.text
            if type(item.text_func) == "function" then
                local text_ok, generated_title = pcall(item.text_func)
                action_title = text_ok and generated_title or nil
            end
            table.insert(actions, {
                key = key,
                title = type(action_title) == "string" and action_title or key,
                item = item,
            })
        end
    end

    if #actions == 0 then
        return nil
    end
    table.sort(actions, function(left, right)
        return left.title:lower() < right.title:lower()
    end)

    return {
        id = "plugin:" .. plugin_module.name,
        plugin_name = plugin_module.name,
        title = plugin_module.fullname or plugin_module.name,
        subtitle = plugin_module.description or plugin_module.name,
        actions = actions,
    }
end

function AppDock:getDAppApps()
    return self:getDAppManager():getCatalogApps()
end

function AppDock:getPluginApps()
    local apps = {}
    for _, plugin_module in ipairs(PluginLoader:loadPlugins()) do
        local app = self:_makePluginApp(plugin_module)
        if app then
            table.insert(apps, app)
        end
    end
    table.sort(apps, function(left, right)
        return left.title:lower() < right.title:lower()
    end)
    return apps
end

function AppDock:getAppCatalog()
    local catalog = {}
    for _, app in ipairs(self:getSystemApps()) do
        catalog[app.id] = app
    end
    for _, app in ipairs(self:getDAppApps()) do
        catalog[app.id] = app
    end
    for _, app in ipairs(self:getPluginApps()) do
        catalog[app.id] = app
    end
    return catalog
end

function AppDock:getPinnedApps()
    local catalog = self:getAppCatalog()
    local apps, cleaned = {}, {}
    for _, app_id in ipairs(self.settings.pinned_apps) do
        local app = catalog[app_id]
        if app then
            table.insert(apps, app)
            table.insert(cleaned, app_id)
        end
    end

    if #cleaned ~= #self.settings.pinned_apps then
        self.settings.pinned_apps = cleaned
        self:_saveSettings()
    end
    return apps
end

function AppDock:isPinned(app_id)
    for _, pinned_id in ipairs(self.settings.pinned_apps) do
        if pinned_id == app_id then
            return true
        end
    end
    return false
end

function AppDock:togglePinned(app_id)
    for index, pinned_id in ipairs(self.settings.pinned_apps) do
        if pinned_id == app_id then
            table.remove(self.settings.pinned_apps, index)
            self:_saveSettings()
            return false
        end
    end
    table.insert(self.settings.pinned_apps, app_id)
    self:_saveSettings()
    return true
end

function AppDock:toggleWidget(widget_id)
    self.settings.widgets[widget_id] = not self.settings.widgets[widget_id]
    self:_saveSettings()
    return self.settings.widgets[widget_id]
end

function AppDock:getStoreWidgets()
    local manager = self:getDAppManager()
    local widgets = {}
    for _, widget in ipairs(manager:getStoreWidgets()) do
        if self.settings.widgets.store[widget.widget_id] == nil then
            self.settings.widgets.store[widget.widget_id] = true
        end
        table.insert(widgets, widget)
    end
    self:_saveSettings()
    return widgets
end

function AppDock:isStoreWidgetEnabled(widget_id)
    return self.settings.widgets.store[widget_id] ~= false
end

function AppDock:toggleStoreWidget(widget_id)
    self.settings.widgets.store[widget_id] = not self:isStoreWidgetEnabled(widget_id)
    self:_saveSettings()
    return self.settings.widgets.store[widget_id]
end

function AppDock:seedDefaults()
    if self.settings.did_seed then
        return
    end

    local count = 0
    for _, app in ipairs(self:getPluginApps()) do
        if not self:isPinned(app.id) then
            table.insert(self.settings.pinned_apps, app.id)
            count = count + 1
            if count >= 2 then
                break
            end
        end
    end
    self.settings.did_seed = true
    self:_saveSettings()
end

function AppDock:_launchPluginAction(app, action)
    local item = action.item
    if type(item.callback) == "function" then
        item.callback()
        return
    end
    if type(item.sub_item_table) == "table" then
        local buttons = {}
        for _, submenu_item in ipairs(item.sub_item_table) do
            if type(submenu_item) == "table" and submenu_item.text then
                table.insert(buttons, { submenu_item })
            end
        end
        if #buttons > 0 then
            UIManager:show(ButtonDialog:new{
                title = action.title,
                buttons = buttons,
                rows_per_page = { 5, 6, 7 },
            })
            return
        end
    end
    UIManager:show(InfoMessage:new{
        text = _("This plugin action is not launchable."),
    })
end

function AppDock:launchApp(app, home)
    if app.kind == "dapp" then
        self:getDAppManager():activate(app.dapp_id, home)
        return
    end

    if app.id == "system:manage" or app.id == "system:open_apps" then
        app.callback(home)
        return
    end

    if home then
        UIManager:close(home)
    end

    if app.id == "system:library" then
        app.callback()
        UIManager:nextTick(function()
            UIManager:setDirty("all", "ui")
            if UIManager.forceRePaint then UIManager:forceRePaint() end
        end)
        return
    end

    if app.actions and #app.actions == 1 then
        self:_launchPluginAction(app, app.actions[1])
        return
    end

    if app.actions and #app.actions > 1 then
        local dialog
        local buttons = {}
        for _, action in ipairs(app.actions) do
            table.insert(buttons, {
                {
                    text = action.title,
                    callback = function()
                        UIManager:close(dialog)
                        UIManager:nextTick(function()
                            self:_launchPluginAction(app, action)
                        end)
                    end,
                },
            })
        end
        dialog = ButtonDialog:new{
            title = app.title,
            buttons = buttons,
            rows_per_page = { 5, 6, 7 },
        }
        UIManager:show(dialog)
        return
    end

    UIManager:show(InfoMessage:new{
        text = _("This plugin does not expose a launchable menu action."),
    })
end

return AppDock
