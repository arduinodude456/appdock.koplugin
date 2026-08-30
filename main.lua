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

-- Bump this only when a new AppDock release should offer the optional guide.
-- It is intentionally not a remote update check: all assistant state stays local.
local SETUP_ASSISTANT_VERSION = "6.0.6"

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
        store_order = {},
    },
    did_seed = false,
    theme = { selected = "lavender", custom = {} },
    design = { active_id = nil, installed = {} },
    plugin_logos = {},
    store = { installed = {} },
    layout = { app_spacing = 16, logo_shape = "rounded", search_enabled = false, split_ratio = .5 },
    launch_on_start = false,
    notifications = { items = {}, next_id = 0 },
    wallpaper = { enabled = false, path = "" },
    lockscreen = { enabled = false, method = "swipe", secret_hash = nil, profile_name = "", profile_image_path = "" },
    beta = { black_borders = false, keep_wallpaper_original_in_night = false, plugin_dapp_host = false, manual_app_spacing = false, plugin_custom_logos = false },
    quick_settings = { tiles = { "wifi", "night", "refresh", "edit", "sleep", "power_saving", "wallpaper" } },
    simple_mode = { homescreen = false, quick_settings = false, focus_apps = false },
    workspace = { restore_enabled = false, session = nil },
    accessibility = { text_scale = 1, high_contrast = false },
    dapp_permissions = {},
    widget_generator = { items = {}, next_id = 0 },
    setup_assistant = { offered_version = "", completed_version = "" },
    power_saving = false,
    sleepscreen_enabled = false,
    layout_version = 19,
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
    self:_scheduleDAppTasks()
    UIManager:nextTick(function()
        local manager = self:getDAppManager()
        if manager and manager.runPermittedAutostarts then manager:runPermittedAutostarts() end
        local restored = manager and self.settings.workspace and self.settings.workspace.restore_enabled
            and manager.restoreWorkspace and manager:restoreWorkspace()
        if self.settings.launch_on_start and not restored then self:showHome() end
        if self:shouldOfferSetupAssistant() and manager and manager.showSetupAssistant then
            -- Record the offer first, so closing the dialog does not repeatedly
            -- interrupt later KOReader starts for this same AppDock version.
            self:markSetupAssistantOffered()
            manager:showSetupAssistant(nil, nil, true)
        end
    end)
end

function AppDock:onSuspend()
    if self.settings.sleepscreen_enabled then
        local ok, SleepScreen = pcall(require, "appdock_sleepscreen")
        if ok and SleepScreen and SleepScreen.show then SleepScreen.show() end
    end
    -- Lock only after an actual device suspend/resume cycle. Normal DApp
    -- navigation must not be mistaken for a fresh AppDock entry.
    self._lock_after_resume = self.settings
        and self.settings.lockscreen
        and self.settings.lockscreen.enabled == true
    if self.dapp_manager and self.dapp_manager.captureWorkspace then self.dapp_manager:captureWorkspace() end
end

function AppDock:onResume()
    local ok, SleepScreen = pcall(require, "appdock_sleepscreen")
    if ok and SleepScreen and SleepScreen.close then SleepScreen.close() end
    if not self._lock_after_resume then return end
    self._lock_after_resume = false
    UIManager:nextTick(function() self:showHome() end)
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
            store_order = {},
        },
        did_seed = stored.did_seed or false,
        theme = stored.theme or { selected = "lavender", custom = {} },
        design = stored.design or { active_id = nil, installed = {} },
        plugin_logos = stored.plugin_logos or {},
        store = stored.store or { installed = {} },
        layout = stored.layout or {},
        launch_on_start = stored.launch_on_start == true,
        notifications = stored.notifications or { items = {}, next_id = 0 },
        wallpaper = stored.wallpaper or { enabled = false, path = "" },
        lockscreen = stored.lockscreen or { enabled = false, method = "swipe", secret_hash = nil, profile_name = "", profile_image_path = "" },
        beta = stored.beta or { black_borders = false, keep_wallpaper_original_in_night = false, plugin_dapp_host = false, manual_app_spacing = false, plugin_custom_logos = false },
        quick_settings = stored.quick_settings or { tiles = copyArray(DEFAULT_SETTINGS.quick_settings.tiles) },
        simple_mode = stored.simple_mode or { homescreen = false, quick_settings = false, focus_apps = false },
        workspace = stored.workspace or { restore_enabled = false, session = nil },
        accessibility = stored.accessibility or { text_scale = 1, high_contrast = false },
        dapp_permissions = stored.dapp_permissions or {},
        widget_generator = stored.widget_generator or { items = {}, next_id = 0 },
        setup_assistant = stored.setup_assistant or { offered_version = "", completed_version = "" },
        power_saving = stored.power_saving == true,
        sleepscreen_enabled = stored.sleepscreen_enabled == true,
        layout_version = stored.layout_version or 1,
    }

    self.settings.layout = self.settings.layout or {}
    if self.settings.launch_on_start == nil then self.settings.launch_on_start = false end
    self.settings.layout.app_spacing = tonumber(self.settings.layout.app_spacing) or DEFAULT_SETTINGS.layout.app_spacing
    self.settings.layout.app_spacing = math.max(8, math.min(34, self.settings.layout.app_spacing))
    self.settings.layout.logo_shape = self.settings.layout.logo_shape == "circle" and "circle" or "rounded"
    self.settings.layout.search_enabled = self.settings.layout.search_enabled == true
    self.settings.layout.split_ratio = tonumber(self.settings.layout.split_ratio) or DEFAULT_SETTINGS.layout.split_ratio
    self.settings.layout.split_ratio = math.max(.20, math.min(.80, self.settings.layout.split_ratio))

    if self.settings.layout_version < 18 then
        local migrated = copyArray(DEFAULT_SETTINGS.pinned_apps)
        for _, app_id in ipairs(self.settings.pinned_apps) do
            if app_id:match("^plugin:") or app_id:match("^dapp:") then
                table.insert(migrated, app_id)
            end
        end
        self.settings.pinned_apps = migrated
    end
    if self.settings.layout_version < DEFAULT_SETTINGS.layout_version then self.settings.layout_version = DEFAULT_SETTINGS.layout_version end

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
    self.settings.widgets.store_order = self.settings.widgets.store_order or {}
    self.settings.theme = self.settings.theme or { selected = "lavender", custom = {} }
    self.settings.theme.selected = self.settings.theme.selected or "lavender"
    self.settings.theme.custom = self.settings.theme.custom or {}
    self.settings.design = self.settings.design or { active_id = nil, installed = {} }
    self.settings.design.installed = self.settings.design.installed or {}
    local Theme = require("appdock_theme")
    local normalized_designs = {}
    for id, record in pairs(self.settings.design.installed) do
        local normalized = Theme.normalizeDesignDefinition(record)
        if normalized and normalized.id == id then
            normalized.source_path = type(record.source_path) == "string" and record.source_path:sub(1, 180) or ""
            normalized.file = type(record.file) == "string" and record.file:sub(1, 360) or ""
            normalized.wallpaper_file = type(record.wallpaper_file) == "string" and record.wallpaper_file:sub(1, 360) or ""
            normalized_designs[id] = normalized
        end
    end
    self.settings.design.installed = normalized_designs
    if type(self.settings.design.active_id) ~= "string" or not normalized_designs[self.settings.design.active_id] then
        self.settings.design.active_id = nil
    end
    self.settings.plugin_logos = self.settings.plugin_logos or {}
    local Wallpaper = require("appdock_wallpaper")
    local normalized_plugin_logos = {}
    for app_id, path in pairs(self.settings.plugin_logos) do
        if type(app_id) == "string" and app_id:match("^plugin:[%w_%-]+$") and type(path) == "string" and Wallpaper.isValidPath(path) then
            local logo_file = io.open(path, "rb")
            if logo_file then logo_file:close(); normalized_plugin_logos[app_id] = path:sub(1, 360) end
        end
    end
    self.settings.plugin_logos = normalized_plugin_logos
    self.settings.store = self.settings.store or { installed = {} }
    self.settings.store.installed = self.settings.store.installed or {}
    self.settings.notifications = self.settings.notifications or { items = {}, next_id = 0 }
    self.settings.notifications.items = self.settings.notifications.items or {}
    self.settings.notifications.next_id = tonumber(self.settings.notifications.next_id) or 0
    self.settings.wallpaper = self.settings.wallpaper or { enabled = false, path = "" }
    self.settings.wallpaper.enabled = self.settings.wallpaper.enabled == true
    self.settings.wallpaper.path = type(self.settings.wallpaper.path) == "string" and self.settings.wallpaper.path:sub(1, 360) or ""
    self.settings.lockscreen = self.settings.lockscreen or { enabled = false, method = "swipe", secret_hash = nil, profile_name = "", profile_image_path = "" }
    self.settings.lockscreen.enabled = self.settings.lockscreen.enabled == true
    if self.settings.lockscreen.method ~= "pin" and self.settings.lockscreen.method ~= "pattern" then self.settings.lockscreen.method = "swipe" end
    self.settings.lockscreen.secret_hash = type(self.settings.lockscreen.secret_hash) == "string" and self.settings.lockscreen.secret_hash or nil
    self.settings.lockscreen.profile_name = type(self.settings.lockscreen.profile_name) == "string" and (self.settings.lockscreen.profile_name:sub(1, 36):match("^%s*(.-)%s*$") or "") or ""
    local profile_path = type(self.settings.lockscreen.profile_image_path) == "string" and self.settings.lockscreen.profile_image_path:sub(1, 360) or ""
    if profile_path ~= "" and Wallpaper.isValidPath(profile_path) then
        local profile_file = io.open(profile_path, "rb")
        if profile_file then profile_file:close() else profile_path = "" end
    else
        profile_path = ""
    end
    self.settings.lockscreen.profile_image_path = profile_path
    self.settings.beta = self.settings.beta or {}
    self.settings.beta.black_borders = self.settings.beta.black_borders == true
    self.settings.beta.keep_wallpaper_original_in_night = self.settings.beta.keep_wallpaper_original_in_night == true
    self.settings.beta.plugin_dapp_host = self.settings.beta.plugin_dapp_host == true
    self.settings.beta.manual_app_spacing = self.settings.beta.manual_app_spacing == true
    self.settings.beta.plugin_custom_logos = self.settings.beta.plugin_custom_logos == true
    self.settings.quick_settings = self.settings.quick_settings or {}
    self.settings.quick_settings.tiles = copyArray(self.settings.quick_settings.tiles or DEFAULT_SETTINGS.quick_settings.tiles)
    self.settings.simple_mode = self.settings.simple_mode or {}
    self.settings.simple_mode.homescreen = self.settings.simple_mode.homescreen == true
    self.settings.simple_mode.quick_settings = self.settings.simple_mode.quick_settings == true
    self.settings.simple_mode.focus_apps = self.settings.simple_mode.focus_apps == true
    self.settings.workspace = type(self.settings.workspace) == "table" and self.settings.workspace or { restore_enabled = false, session = nil }
    self.settings.workspace.restore_enabled = self.settings.workspace.restore_enabled == true
    if type(self.settings.workspace.session) ~= "table" or self.settings.workspace.session.version ~= 1 then
        self.settings.workspace.session = nil
    end
    self.settings.accessibility = type(self.settings.accessibility) == "table" and self.settings.accessibility or { text_scale = 1, high_contrast = false }
    local allowed_text_scales = { [0.9] = true, [1] = true, [1.15] = true, [1.3] = true }
    local stored_text_scale = tonumber(self.settings.accessibility.text_scale) or 1
    self.settings.accessibility.text_scale = allowed_text_scales[stored_text_scale] and stored_text_scale or 1
    self.settings.accessibility.high_contrast = self.settings.accessibility.high_contrast == true
    self.settings.dapp_permissions = self.settings.dapp_permissions or {}
    self.settings.widget_generator = self.settings.widget_generator or { items = {}, next_id = 0 }
    self.settings.widget_generator.items = type(self.settings.widget_generator.items) == "table" and self.settings.widget_generator.items or {}
    self.settings.widget_generator.next_id = math.max(0, math.floor(tonumber(self.settings.widget_generator.next_id) or 0))
    self.settings.setup_assistant = type(self.settings.setup_assistant) == "table" and self.settings.setup_assistant or {}
    self.settings.setup_assistant.offered_version = type(self.settings.setup_assistant.offered_version) == "string" and self.settings.setup_assistant.offered_version:sub(1, 24) or ""
    self.settings.setup_assistant.completed_version = type(self.settings.setup_assistant.completed_version) == "string" and self.settings.setup_assistant.completed_version:sub(1, 24) or ""
    local normalized_generated = {}
    local generated_count = 0
    for id, item in pairs(self.settings.widget_generator.items) do
        if generated_count >= 20 then break end
        if type(id) == "string" and id:match("^generated_widget_%d+$") and type(item) == "table" then
            local title = type(item.title) == "string" and item.title:sub(1, 36) or _("Custom widget")
            title = title:match("^%s*(.-)%s*$") or ""
            if title == "" then title = _("Custom widget") end
            normalized_generated[id] = {
                title = title,
                text = type(item.text) == "string" and item.text:sub(1, 180) or "",
                show_time = item.show_time == true,
                show_date = item.show_date == true,
                show_battery = item.show_battery == true,
            }
            generated_count = generated_count + 1
        end
    end
    self.settings.widget_generator.items = normalized_generated
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

function AppDock:getSetupAssistantStatus()
    local state = self.settings.setup_assistant or {}
    return {
        version = SETUP_ASSISTANT_VERSION,
        offered = state.offered_version == SETUP_ASSISTANT_VERSION,
        completed = state.completed_version == SETUP_ASSISTANT_VERSION,
    }
end

function AppDock:shouldOfferSetupAssistant()
    local status = self:getSetupAssistantStatus()
    return not status.completed and not status.offered
end

function AppDock:markSetupAssistantOffered()
    self.settings.setup_assistant = self.settings.setup_assistant or {}
    self.settings.setup_assistant.offered_version = SETUP_ASSISTANT_VERSION
    self:_saveSettings()
end

function AppDock:completeSetupAssistant()
    self.settings.setup_assistant = self.settings.setup_assistant or {}
    self.settings.setup_assistant.offered_version = SETUP_ASSISTANT_VERSION
    self.settings.setup_assistant.completed_version = SETUP_ASSISTANT_VERSION
    self:_saveSettings()
end

function AppDock:setLaunchOnStart(enabled)
    self.settings.launch_on_start = not not enabled
    self:_saveSettings()
end

function AppDock:setWorkspaceRestoreEnabled(enabled)
    self.settings.workspace = self.settings.workspace or { restore_enabled = false, session = nil }
    self.settings.workspace.restore_enabled = enabled == true
    if not self.settings.workspace.restore_enabled then self.settings.workspace.session = nil end
    self:_saveSettings()
    return true
end

function AppDock:setAccessibility(changes)
    changes = type(changes) == "table" and changes or {}
    self.settings.accessibility = self.settings.accessibility or { text_scale = 1, high_contrast = false }
    if changes.text_scale ~= nil then
        local allowed_text_scales = { [0.9] = true, [1] = true, [1.15] = true, [1.3] = true }
        local requested = tonumber(changes.text_scale)
        if not allowed_text_scales[requested] then return false end
        self.settings.accessibility.text_scale = requested
    end
    if changes.high_contrast ~= nil then self.settings.accessibility.high_contrast = changes.high_contrast == true end
    self:_saveSettings()
    return true
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

function AppDock:setWallpaper(path, enabled)
    local Wallpaper = require("appdock_wallpaper")
    if type(path) == "string" then self.settings.wallpaper.path = path:sub(1, 360) end
    if enabled ~= nil then self.settings.wallpaper.enabled = enabled == true and Wallpaper.isValidPath(self.settings.wallpaper.path) end
    self:_saveSettings()
    return self.settings.wallpaper.enabled
end

function AppDock:getActiveDesign()
    local Theme = require("appdock_theme")
    return Theme.getActiveDesign(self.settings)
end

function AppDock:getStoreDesignBySource(source_path)
    for id, record in pairs((self.settings.design and self.settings.design.installed) or {}) do
        if record and record.source_path == source_path then return record, id end
    end
    return nil, nil
end

function AppDock:installStoreDesign(definition, source_path, design_file, wallpaper_file)
    local Theme = require("appdock_theme")
    local normalized = Theme.normalizeDesignDefinition(definition)
    if not normalized then return false, "The design definition is invalid." end
    if type(source_path) ~= "string" or type(design_file) ~= "string" then return false, "The design source is invalid." end
    self.settings.design = self.settings.design or { active_id = nil, installed = {} }
    self.settings.design.installed = self.settings.design.installed or {}
    local current = self.settings.design.installed[normalized.id]
    if current and current.source_path ~= source_path then return false, "A different design already uses this id." end
    local previous_wallpaper_file = current and current.wallpaper_file or ""
    normalized.source_path = source_path:sub(1, 180)
    normalized.file = design_file:sub(1, 360)
    normalized.wallpaper_file = type(wallpaper_file) == "string" and wallpaper_file:sub(1, 360) or ""
    self.settings.design.installed[normalized.id] = normalized
    if previous_wallpaper_file ~= "" and previous_wallpaper_file ~= normalized.wallpaper_file then os.remove(previous_wallpaper_file) end
    self.settings.design.active_id = normalized.id
    self:_saveSettings()
    return true, normalized
end

function AppDock:setStoreDesignActive(id)
    if id == nil then
        self.settings.design.active_id = nil
    elseif type(id) == "string" and self.settings.design and self.settings.design.installed and self.settings.design.installed[id] then
        self.settings.design.active_id = id
    else
        return false
    end
    self:_saveSettings()
    return true
end

function AppDock:getPluginLogo(app_id)
    local logos = self.settings.plugin_logos or {}
    return type(app_id) == "string" and logos[app_id] or nil
end

function AppDock:setPluginLogo(app_id, path)
    if self.settings.beta.plugin_custom_logos ~= true or type(app_id) ~= "string" or not app_id:match("^plugin:[%w_%-]+$") then return false end
    self.settings.plugin_logos = self.settings.plugin_logos or {}
    if path == nil or path == "" then
        self.settings.plugin_logos[app_id] = nil
        self:_saveSettings()
        return true
    end
    local Wallpaper = require("appdock_wallpaper")
    local candidate = type(path) == "string" and path:sub(1, 360) or ""
    if not Wallpaper.isValidPath(candidate) then return false end
    local logo_file = io.open(candidate, "rb")
    if not logo_file then return false end
    logo_file:close()
    self.settings.plugin_logos[app_id] = candidate
    self:_saveSettings()
    return true
end

function AppDock:uninstallStoreDesign(id)
    local designs = self.settings.design and self.settings.design.installed or {}
    local record = designs[id]
    if not record then return false, "This AppStore design is not installed." end
    for _, path in ipairs({ record.file, record.wallpaper_file }) do
        if type(path) == "string" and path ~= "" then os.remove(path) end
    end
    designs[id] = nil
    if self.settings.design.active_id == id then self.settings.design.active_id = nil end
    self:_saveSettings()
    return true
end

function AppDock:setBetaOption(key, enabled)
    if key ~= "black_borders" and key ~= "keep_wallpaper_original_in_night" and key ~= "plugin_dapp_host" and key ~= "manual_app_spacing" and key ~= "plugin_custom_logos" then return false end
    self.settings.beta[key] = enabled == true
    self:_saveSettings()
    return true
end

function AppDock:setLockscreen(method, secret)
    local LockScreen = require("appdock_lockscreen")
    if method ~= "swipe" and method ~= "pin" and method ~= "pattern" then return false end
    if method ~= "swipe" and (type(secret) ~= "string" or #secret < 4 or #secret > 32) then return false end
    self.settings.lockscreen.method = method
    self.settings.lockscreen.enabled = true
    self.settings.lockscreen.secret_hash = method == "swipe" and nil or LockScreen.hash(secret)
    self:_saveSettings()
    return true
end

function AppDock:disableLockscreen()
    self.settings.lockscreen.enabled = false
    self.settings.lockscreen.secret_hash = nil
    self:_saveSettings()
end

function AppDock:setLockscreenProfile(name, image_path)
    local lockscreen = self.settings.lockscreen
    local profile_name = type(name) == "string" and (name:sub(1, 36):match("^%s*(.-)%s*$") or "") or ""
    local profile_image_path = lockscreen.profile_image_path or ""
    if image_path == nil or image_path == "" then
        profile_image_path = ""
    elseif type(image_path) == "string" then
        local Wallpaper = require("appdock_wallpaper")
        local candidate = image_path:sub(1, 360)
        if not Wallpaper.isValidPath(candidate) then return false end
        local file = io.open(candidate, "rb")
        if not file then return false end
        file:close()
        profile_image_path = candidate
    else
        return false
    end
    lockscreen.profile_name = profile_name
    lockscreen.profile_image_path = profile_image_path
    self:_saveSettings()
    return true
end

function AppDock:setSleepScreenEnabled(enabled)
    self.settings.sleepscreen_enabled = enabled == true
    self:_saveSettings()
    return self.settings.sleepscreen_enabled
end

function AppDock:setPowerSaving(enabled)
    self.settings.power_saving = enabled == true
    self:_saveSettings()
    self:_scheduleScreenRefresh()
end

local QUICK_TILE_IDS = { wifi = true, night = true, refresh = true, edit = true, sleep = true, power_saving = true, wallpaper = true }

function AppDock:getQuickSettingsTiles()
    if self:isSimpleModeEnabled("quick_settings") then
        return { "wifi", "night", "power_saving" }
    end
    local tiles, seen = {}, {}
    for _, tile_id in ipairs(self.settings.quick_settings.tiles or {}) do
        if QUICK_TILE_IDS[tile_id] and not seen[tile_id] then
            tiles[#tiles + 1] = tile_id
            seen[tile_id] = true
        end
    end
    self.settings.quick_settings.tiles = tiles
    return tiles
end

function AppDock:setQuickTileEnabled(tile_id, enabled)
    if not QUICK_TILE_IDS[tile_id] then return false end
    local tiles = self:getQuickSettingsTiles()
    local position
    for index, value in ipairs(tiles) do if value == tile_id then position = index; break end end
    if enabled and not position then tiles[#tiles + 1] = tile_id end
    if not enabled and position then table.remove(tiles, position) end
    self.settings.quick_settings.tiles = tiles
    self:_saveSettings()
    return true
end

local SIMPLE_MODE_APP_IDS = {
    ["system:library"] = true,
    ["dapp:settings"] = true,
    ["dapp:file_manager"] = true,
    ["dapp:dreader"] = true,
    ["dapp:book_translator"] = true,
    ["dapp:web_browser"] = true,
}

local SIMPLE_MODE_APP_TITLES = {
    ["settings"] = true,
    ["file browser"] = true,
    ["file manager"] = true,
    ["dreader"] = true,
    ["library"] = true,
    ["booktranslator"] = true,
    ["book translator"] = true,
    ["internet browser"] = true,
    ["web browser"] = true,
}

function AppDock:isSimpleModeEnabled(option)
    return self.settings.simple_mode and self.settings.simple_mode[option] == true
end

-- The expressive Material-oriented surface is a normal-mode presentation only.
-- Any selected Simple Mode component deliberately keeps its established layout.
function AppDock:isExpressiveUiEnabled()
    return not self:isSimpleModeEnabled("homescreen")
        and not self:isSimpleModeEnabled("quick_settings")
        and not self:isSimpleModeEnabled("focus_apps")
end

function AppDock:setSimpleModeOption(option, enabled)
    if option ~= "homescreen" and option ~= "quick_settings" and option ~= "focus_apps" then return false end
    self.settings.simple_mode = self.settings.simple_mode or {}
    self.settings.simple_mode[option] = enabled == true
    if option == "focus_apps" and enabled and self.dapp_manager then
        for _, open_app in ipairs(self.dapp_manager:getOpenApps()) do
            local definition = self.dapp_manager.definitions[open_app.id] or self.dapp_manager.plugin_definitions[open_app.id]
            local app = { id = "dapp:" .. open_app.id, title = definition and definition.title or open_app.title or open_app.id }
            if not self:isSimpleModeAppAllowed(app) then self.dapp_manager:closeDApp(open_app.id) end
        end
    end
    self:_saveSettings()
    return true
end

function AppDock:isSimpleModeAppAllowed(app)
    if not self:isSimpleModeEnabled("focus_apps") then return true end
    if type(app) ~= "table" then return false end
    if SIMPLE_MODE_APP_IDS[app.id] then return true end
    local title = type(app.title) == "string" and app.title:lower():match("^%s*(.-)%s*$") or ""
    return SIMPLE_MODE_APP_TITLES[title] == true
end

function AppDock:getDAppPermissions(id)
    local stored = self.settings.dapp_permissions[id] or {}
    return { background = stored.background == true, autostart = stored.autostart == true }
end

function AppDock:setDAppPermission(id, key, enabled)
    if type(id) ~= "string" or (key ~= "background" and key ~= "autostart") then return false end
    self.settings.dapp_permissions[id] = self.settings.dapp_permissions[id] or {}
    self.settings.dapp_permissions[id][key] = enabled == true
    self:_saveSettings()
    if key == "autostart" and enabled then
        local manager = self:getDAppManager()
        if manager and manager.runPermittedAutostarts then manager:runPermittedAutostarts() end
    end
    return true
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
        UIManager:scheduleIn(self.settings.power_saving and 180 or 60, self._screen_refresh_tick)
    end
    UIManager:scheduleIn(self.settings.power_saving and 180 or 60, self._screen_refresh_tick)
end

function AppDock:_scheduleDAppTasks()
    if self._dapp_task_tick then UIManager:unschedule(self._dapp_task_tick) end
    self._dapp_task_tick = function()
        if not self.settings.power_saving then
            local manager = self:getDAppManager()
            if manager and manager.runPermittedBackgroundTasks then manager:runPermittedBackgroundTasks() end
        end
        UIManager:scheduleIn(120, self._dapp_task_tick)
    end
    UIManager:scheduleIn(120, self._dapp_task_tick)
end

function AppDock:onCloseWidget()
    if self.dapp_manager and self.dapp_manager.captureWorkspace then self.dapp_manager:captureWorkspace() end
    if self._screen_refresh_tick then
        UIManager:unschedule(self._screen_refresh_tick)
    end
    if self._dapp_task_tick then UIManager:unschedule(self._dapp_task_tick) end
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

function AppDock:showHome(skip_lock)
    if self.settings.lockscreen.enabled and not skip_lock then
        local ok, LockScreen = pcall(require, "appdock_lockscreen")
        if ok and LockScreen and LockScreen.show then
            LockScreen.show(self, function() self:showHome(true) end)
            return
        end
    end
    if not self._boot_shown then
        self._boot_shown = true
        local ok, Boot = pcall(require, "appdock_boot")
        if ok and Boot and Boot.show then
            Boot.show(function() self:showHome(true) end)
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
        if type(item) == "table" and (type(item.callback) == "function" or type(item.sub_item_table) == "table" or type(item.sub_item_table_func) == "function") then
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
        instance = instance,
        custom_logo_path = self:getPluginLogo("plugin:" .. plugin_module.name),
        buildAppDockPane = type(instance.buildAppDockPane) == "function" and instance.buildAppDockPane or nil,
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

function AppDock:getVisibleAppCatalog()
    local catalog, visible = self:getAppCatalog(), {}
    for id, app in pairs(catalog) do
        if self:isSimpleModeAppAllowed(app) then visible[id] = app end
    end
    return visible
end

function AppDock:getPinnedApps()
    local catalog = self:getAppCatalog()
    local apps, cleaned = {}, {}
    for _, app_id in ipairs(self.settings.pinned_apps) do
        local app = catalog[app_id]
        if app then
            if self:isSimpleModeAppAllowed(app) then table.insert(apps, app) end
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

local function moveValue(list, value, delta)
    local index
    for position, item in ipairs(list or {}) do
        if item == value then index = position; break end
    end
    if not index then return false end
    local target = index + delta
    if target < 1 or target > #list then return false end
    list[index], list[target] = list[target], list[index]
    return true
end

function AppDock:getPinnedPosition(app_id)
    for index, pinned_id in ipairs(self.settings.pinned_apps) do
        if pinned_id == app_id then return index, #self.settings.pinned_apps end
    end
    return nil, #self.settings.pinned_apps
end

function AppDock:movePinned(app_id, delta)
    if moveValue(self.settings.pinned_apps, app_id, delta) then
        self:_saveSettings()
        return true
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
    local available, by_id = {}, {}
    for _, widget in ipairs(manager:getStoreWidgets()) do
        if self.settings.widgets.store[widget.widget_id] == nil then
            self.settings.widgets.store[widget.widget_id] = true
        end
        by_id[widget.widget_id] = widget
    end
    local stored_order, order, seen = self.settings.widgets.store_order or {}, {}, {}
    for _, widget_id in ipairs(stored_order) do
        if by_id[widget_id] then available[#available + 1] = by_id[widget_id]; seen[widget_id] = true; order[#order + 1] = widget_id end
    end
    local remaining = {}
    for widget_id, widget in pairs(by_id) do
        if not seen[widget_id] then remaining[#remaining + 1] = widget end
    end
    table.sort(remaining, function(left, right) return left.title:lower() < right.title:lower() end)
    for _, widget in ipairs(remaining) do
        available[#available + 1] = widget
        order[#order + 1] = widget.widget_id
    end
    self.settings.widgets.store_order = order
    self:_saveSettings()
    return available
end

function AppDock:isStoreWidgetEnabled(widget_id)
    return self.settings.widgets.store[widget_id] ~= false
end

function AppDock:getStoreWidgetPosition(widget_id)
    local order = self.settings.widgets.store_order or {}
    for index, value in ipairs(order) do
        if value == widget_id then return index, #order end
    end
    return nil, #order
end

function AppDock:moveStoreWidget(widget_id, delta)
    local order = self.settings.widgets.store_order or {}
    local known = {}
    local available = self:getStoreWidgets()
    for _, widget in ipairs(available) do known[widget.widget_id] = true end
    if not known[widget_id] then return false end
    if moveValue(order, widget_id, delta) then
        self.settings.widgets.store_order = order
        self:_saveSettings()
        return true
    end
    return false
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
    if not self:isSimpleModeAppAllowed(app) then
        UIManager:show(InfoMessage:new{ text = _("This app is hidden by Simple Mode. Disable Quick find in Settings to use it again.") })
        return false
    end
    if app.kind == "dapp" then
        self:getDAppManager():activate(app.dapp_id, home)
        return
    end

    if app.plugin_name and app.actions and self.settings.beta and self.settings.beta.plugin_dapp_host then
        self:getDAppManager():activatePlugin(app, home)
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
