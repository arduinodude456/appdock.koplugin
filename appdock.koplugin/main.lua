--[[--
AppDock is an in-app homescreen for KOReader.
It exposes selected KOReader plugin menu actions as configurable app tiles.
--]]--

local MODULE_DIR = (debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "")
local APPDOCK_RELEASE = "8.2.14"
local AppDockRecovery
local recovery_context
do
    local ok, loaded = pcall(dofile, MODULE_DIR .. "appdock_recovery.lua")
    if ok and type(loaded) == "table" then
        AppDockRecovery = loaded
        local prepared, context = pcall(AppDockRecovery.prepare, MODULE_DIR, APPDOCK_RELEASE)
        if prepared then recovery_context = context end
    end
end

local AppDockDialogs = require("appdock_dialogs")
local ButtonDialog = AppDockDialogs.ButtonDialog
local InfoMessage = AppDockDialogs.InfoMessage
local PluginLoader = require("pluginloader")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local AppDockGroups = require("appdock_groups")
local AppDockOrder = require("appdock_order")

local DEFAULT_WALLPAPER_PATH = MODULE_DIR .. "assets/wallpaper/appdock_default.svg"

local AppDock = WidgetContainer:extend{
    name = "appdock",
    is_doc_only = false,
    settings_key = "appdock_homescreen",
}

-- Bump this only when a new AppDock release should offer the optional guide.
-- It is intentionally not a remote update check: all assistant state stays local.
local SETUP_ASSISTANT_VERSION = APPDOCK_RELEASE

local DEFAULT_SETTINGS = {
    pinned_apps = {
        "system:library",
        "dapp:web_browser",
        "dapp:file_manager",
        "dapp:app_store",
        "dapp:youtube",
        "dapp:youtube_music",
        "dapp:draw",
        "dapp:analog_clock",
        "dapp:settings",
        "dapp:help",
        "system:open_apps",
        "system:menu",
        "system:history",
        "system:manage",
    },
    recent_apps = {},
    app_groups = { next_id = 0, items = {} },
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
    layout = { app_spacing = 16, logo_shape = "rounded", search_enabled = false, ddg_search = true, split_ratio = .5, widget_scales = {} },
    launch_on_start = false,
    notifications = { items = {}, next_id = 0 },
    wallpaper = { enabled = true, path = DEFAULT_WALLPAPER_PATH, source = "appdock_default" },
    lockscreen = { enabled = false, method = "swipe", secret_hash = nil, profile_name = "", profile_image_path = "" },
    beta = { black_borders = false, keep_wallpaper_original_in_night = false, plugin_dapp_host = false, windows = false, manual_app_spacing = false, plugin_custom_logos = false },
    quick_settings = { tiles = { "wifi", "night", "refresh", "edit", "rotate", "sleep", "power_saving", "wallpaper" } },
    simple_mode = { homescreen = false, quick_settings = false, focus_apps = false },
    workspace = { restore_enabled = false, session = nil },
    accessibility = { text_scale = 1, high_contrast = false },
    dapp_permissions = {},
    widget_generator = { items = {}, next_id = 0 },
    -- Public cache only. The account/device credentials live separately under
    -- G_reader_settings["appdock_tbs_session"] and are never LAN-migrated.
    tbs_account = { enabled = false, username = "", display_name = "" },
    setup_assistant = { offered_version = "", completed_version = "" },
    update_dialog = { dismissed_version = "" },
    keyboard = { language = "auto", enabled = true },
    file_browser = { sort_category = "all", show_hidden = false, hidden_paths = {} },
    power_saving = false,
    volume_percent = 100,
    refresh_interval = 60,
    sleepscreen_enabled = false,
    -- Only a local selection lives in settings; media and presets have their
    -- own bounded registry in the KOReader data directory.
    sleepscreens = { active_id = nil },
    youtube = {
        ytdlp_path = "",
        ffmpeg_path = "",
        output_dir = "",
        music_dir = "",
        resolution_percent = 100,
        fps = 12,
        max_duration = 180,
        max_height = 480,
        dither = "ffmpeg",
        color_mode = false,
        color_dither = true,
    },
    layout_version = 25,
}


local function readFeaturePages()
    local pages, current = {}, nil
    local f = io.open(MODULE_DIR .. "features.adf", "rb")
    if not f then return pages end
    for line in f:lines() do
        line = line:gsub("\r$", "")
        if line == "[page]" then current = {}; pages[#pages + 1] = current
        elseif current then
            local key, value = line:match("^([%w_]+)=(.*)$")
            if key == "image" then
                local safe_path = value:gsub("\\", "/")
                if safe_path:match("^[%w_./%-]+$") and not safe_path:find("%.%.", 1, true) then
                    current.image = MODULE_DIR .. safe_path
                end
            elseif key then
                current[key] = value
            end
        end
    end
    f:close()
    return pages
end

function AppDock:getFeaturePages() return readFeaturePages() end

local function copyArray(source)
    local result = {}
    for index, value in ipairs(type(source) == "table" and source or {}) do
        result[index] = value
    end
    return result
end

-- Settings are user data: an interrupted transfer, an older AppDock release or
-- a manual edit must never turn a scalar value into a KOReader start-up crash.
local function tableValue(value, fallback)
    if type(value) == "table" then return value end
    return fallback or {}
end

-- The YouTube DApp owns its own tool paths and conversion defaults. They are
-- normalized in one place so a stored value can never break a conversion.
local YOUTUBE_RESOLUTIONS = { [100] = true, [75] = true, [50] = true, [35] = true }
local YOUTUBE_FRAME_RATES = { [7.5] = true, [10] = true, [12] = true, [15] = true }
local YOUTUBE_HEIGHTS = { [360] = true, [480] = true, [720] = true }
local YOUTUBE_AUDIO_VIDEO_DELAYS = { [0] = true, [0.1] = true, [0.25] = true, [0.5] = true, [1] = true, [2] = true }

local function boundedText(value, limit)
    if type(value) ~= "string" then return "" end
    return value:gsub("^%s+", ""):gsub("%s+$", ""):sub(1, limit)
end

local function normalizeYouTubeSettings(stored)
    stored = type(stored) == "table" and stored or {}
    local resolution = tonumber(stored.resolution_percent)
    local frame_rate = tonumber(stored.fps)
    local duration = tonumber(stored.max_duration)
    local height = tonumber(stored.max_height)
    local audio_video_delay = tonumber(stored.audio_video_delay)
    return {
        ytdlp_path = boundedText(stored.ytdlp_path, 360),
        ffmpeg_path = boundedText(stored.ffmpeg_path, 360),
        output_dir = boundedText(stored.output_dir, 360),
        -- The YouTube Music DApp keeps its tracks in their own folder; the tool
        -- paths and the length limit above are shared with the video DApp.
        music_dir = boundedText(stored.music_dir, 360),
        resolution_percent = (resolution and YOUTUBE_RESOLUTIONS[resolution]) and resolution or 100,
        fps = (frame_rate and YOUTUBE_FRAME_RATES[frame_rate]) and frame_rate or 12,
        max_duration = (duration and duration >= 0 and duration <= 3600) and math.floor(duration) or 180,
        max_height = (height and YOUTUBE_HEIGHTS[height]) and height or 480,
        dither = stored.dither == "bayer" and "bayer" or "ffmpeg",
        color_mode = stored.color_mode == true,
        color_dither = stored.color_dither ~= false,
        audio_video_delay = (audio_video_delay and audio_video_delay >= 0 and audio_video_delay <= 60)
            and audio_video_delay or 0,
    }
end

function AppDock:init()
    self:_loadSettings()
    if self.ui and self.ui.menu and self.ui.menu.registerToMainMenu then
        self.ui.menu:registerToMainMenu(self)
    end
    self:_scheduleScreenRefresh()
    self:_scheduleDAppTasks()
    UIManager:nextTick(function()
        local manager = self:getDAppManager()
        if manager and manager.runPermittedAutostarts then manager:runPermittedAutostarts() end
        local restored = manager and self.settings.workspace and self.settings.workspace.restore_enabled
            and manager.restoreWorkspace and manager:restoreWorkspace()
        local function finish_startup()
            if AppDockRecovery and recovery_context then pcall(AppDockRecovery.markHealthy, recovery_context) end
            local notice = AppDockRecovery and recovery_context and AppDockRecovery.consumeNotice and AppDockRecovery.consumeNotice(recovery_context)
            if notice and notice ~= "" then UIManager:show(InfoMessage:new{ text = notice }) end
            -- This callback runs only after the boot/lockscreen callback has
            -- shown the homescreen. Showing the dialog earlier lets the final
            -- showHome() call put the homescreen on top of it.
            UIManager:nextTick(function()
                if self:shouldShowUpdateDialog() and manager and manager.showFeatureDialog then
                    manager:showFeatureDialog()
                end
            end)
        end
        if self.settings.launch_on_start and not restored then
            self:showHome(false, function() UIManager:nextTick(finish_startup) end)
        else
            UIManager:nextTick(finish_startup)
        end
    end)
end

function AppDock:onSuspend()
    if self.settings.sleepscreen_enabled then
        local ok, SleepScreen = pcall(require, "appdock_sleepscreen")
        if ok and SleepScreen and SleepScreen.show then SleepScreen.show(self) end
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
    local stored = {}
    if _G.G_reader_settings and type(G_reader_settings.readSetting) == "function" then
        local ok, value = pcall(G_reader_settings.readSetting, G_reader_settings, self.settings_key, {})
        if ok and type(value) == "table" then stored = value end
    end
    local Wallpaper = require("appdock_wallpaper")
    -- A table means the user (or an earlier AppDock release) has already made
    -- a wallpaper choice. Only an entirely missing setting receives the local,
    -- bundled default; no existing path or disabled state is overwritten.
    if type(Wallpaper.ensureDefault) == "function" then
        Wallpaper.ensureDefault(stored, DEFAULT_WALLPAPER_PATH)
    elseif type(stored.wallpaper) ~= "table" then
        -- Keep minimal KOReader/test wallpaper adapters usable while retaining
        -- the exact same first-run-only behavior as the helper above.
        stored.wallpaper = { enabled = true, path = DEFAULT_WALLPAPER_PATH, source = "appdock_default" }
    end
    self.settings = {
        pinned_apps = copyArray(tableValue(stored.pinned_apps, DEFAULT_SETTINGS.pinned_apps)),
        recent_apps = copyArray(tableValue(stored.recent_apps, DEFAULT_SETTINGS.recent_apps)),
        app_groups = AppDockGroups.normalize(tableValue(stored.app_groups)),
        widgets = tableValue(stored.widgets, {
            clock = DEFAULT_SETTINGS.widgets.clock,
            status = DEFAULT_SETTINGS.widgets.status,
            reading_hint = DEFAULT_SETTINGS.widgets.reading_hint,
            store = {},
            store_order = {},
        }),
        did_seed = stored.did_seed or false,
        theme = tableValue(stored.theme, { selected = "lavender", custom = {} }),
        design = tableValue(stored.design, { active_id = nil, installed = {} }),
        plugin_logos = tableValue(stored.plugin_logos),
        store = tableValue(stored.store, { installed = {} }),
        layout = tableValue(stored.layout),
        launch_on_start = stored.launch_on_start == true,
        notifications = tableValue(stored.notifications, { items = {}, next_id = 0 }),
        wallpaper = tableValue(stored.wallpaper, { enabled = true, path = DEFAULT_WALLPAPER_PATH, source = "appdock_default" }),
        lockscreen = tableValue(stored.lockscreen, { enabled = false, method = "swipe", secret_hash = nil, profile_name = "", profile_image_path = "" }),
        beta = tableValue(stored.beta, { black_borders = false, keep_wallpaper_original_in_night = false, plugin_dapp_host = false, windows = false, manual_app_spacing = false, plugin_custom_logos = false }),
        quick_settings = tableValue(stored.quick_settings, { tiles = copyArray(DEFAULT_SETTINGS.quick_settings.tiles) }),
        simple_mode = tableValue(stored.simple_mode, { homescreen = false, quick_settings = false, focus_apps = false }),
        workspace = tableValue(stored.workspace, { restore_enabled = false, session = nil }),
        accessibility = tableValue(stored.accessibility, { text_scale = 1, high_contrast = false }),
        dapp_permissions = tableValue(stored.dapp_permissions),
        widget_generator = tableValue(stored.widget_generator, { items = {}, next_id = 0 }),
        tbs_account = tableValue(stored.tbs_account, { enabled = false, username = "", display_name = "" }),
        setup_assistant = tableValue(stored.setup_assistant, { offered_version = "", completed_version = "" }),
        update_dialog = tableValue(stored.update_dialog, { dismissed_version = "" }),
        keyboard = tableValue(stored.keyboard, { language = "auto" }),
        file_browser = tableValue(stored.file_browser, { sort_category = "all", show_hidden = false, hidden_paths = {} }),
        power_saving = stored.power_saving == true,
        volume_percent = math.max(0, math.min(100, tonumber(stored.volume_percent) or 100)),
        refresh_interval = tonumber(stored.refresh_interval) or DEFAULT_SETTINGS.refresh_interval,
        sleepscreen_enabled = stored.sleepscreen_enabled == true,
        sleepscreens = { active_id = type(stored.sleepscreens) == "table"
            and type(stored.sleepscreens.active_id) == "string"
            and #stored.sleepscreens.active_id <= 80
            and stored.sleepscreens.active_id:match("^[%w_%-]+$")
            and stored.sleepscreens.active_id or nil },
        youtube = normalizeYouTubeSettings(stored.youtube),
        layout_version = math.max(1, math.floor(tonumber(stored.layout_version) or 1)),
    }

    local normalized_recent, recent_seen = {}, {}
    for _, app_id in ipairs(self.settings.recent_apps) do
        if #normalized_recent >= 4 then break end
        if type(app_id) == "string" and #app_id <= 160 and app_id:match("^[%w:_%-]+$") and not recent_seen[app_id] then
            normalized_recent[#normalized_recent + 1] = app_id
            recent_seen[app_id] = true
        end
    end
    self.settings.recent_apps = normalized_recent

    self.settings.layout = self.settings.layout or {}
    if self.settings.launch_on_start == nil then self.settings.launch_on_start = false end
    self.settings.layout.app_spacing = tonumber(self.settings.layout.app_spacing) or DEFAULT_SETTINGS.layout.app_spacing
    self.settings.layout.app_spacing = math.max(8, math.min(34, self.settings.layout.app_spacing))
    self.settings.layout.logo_shape = self.settings.layout.logo_shape == "circle" and "circle" or "rounded"
    self.settings.layout.search_enabled = self.settings.layout.search_enabled == true
    -- The DuckDuckGo bar is opt-out: it stays visible unless it was disabled.
    self.settings.layout.ddg_search = self.settings.layout.ddg_search ~= false
    self.settings.layout.split_ratio = tonumber(self.settings.layout.split_ratio) or DEFAULT_SETTINGS.layout.split_ratio
    self.settings.layout.split_ratio = math.max(.20, math.min(.80, self.settings.layout.split_ratio))
    local widget_scales = {}
    for widget_id, factor in pairs(type(self.settings.layout.widget_scales) == "table" and self.settings.layout.widget_scales or {}) do
        factor = tonumber(factor)
        if type(widget_id) == "string" and #widget_id <= 120 and widget_id:match("^[%w:_%-]+$") and factor and factor >= .75 and factor <= 1.5 then
            widget_scales[widget_id] = math.floor(factor * 4 + .5) / 4
        end
    end
    self.settings.layout.widget_scales = widget_scales
    self.settings.refresh_interval = math.floor((tonumber(self.settings.refresh_interval) or DEFAULT_SETTINGS.refresh_interval) / 15 + .5) * 15
    self.settings.refresh_interval = math.max(15, math.min(300, self.settings.refresh_interval))

    if self.settings.layout_version < 18 then
        local migrated = copyArray(DEFAULT_SETTINGS.pinned_apps)
        for _, app_id in ipairs(self.settings.pinned_apps) do
            if app_id:match("^plugin:") or app_id:match("^dapp:") then
                table.insert(migrated, app_id)
            end
        end
        self.settings.pinned_apps = migrated
    end
    if self.settings.layout_version < 21 then
        -- Existing installations receive the YouTube tile once. Users who
        -- remove it afterwards keep their own launcher.
        local pinned_youtube = false
        for _, app_id in ipairs(self.settings.pinned_apps) do
            if app_id == "dapp:youtube" then pinned_youtube = true break end
        end
        if not pinned_youtube then
            local insert_at
            for index, app_id in ipairs(self.settings.pinned_apps) do
                if app_id == "dapp:app_store" then insert_at = index + 1 break end
            end
            table.insert(self.settings.pinned_apps, insert_at or (#self.settings.pinned_apps + 1), "dapp:youtube")
        end
    end
    if self.settings.layout_version < 22 then
        -- Existing releases defaulted every installation to Lua Bayer
        -- dithering. FFmpeg's native monochrome conversion is materially faster;
        -- users can still switch back to Bayer from YouTube settings.
        self.settings.youtube.dither = "ffmpeg"
    end
    if self.settings.layout_version < 23 then
        -- Offer the new built-in drawing app once without disturbing user order.
        local pinned_draw = false
        for _, app_id in ipairs(self.settings.pinned_apps) do
            if app_id == "dapp:draw" then pinned_draw = true break end
        end
        if not pinned_draw then
            local insert_at
            for index, app_id in ipairs(self.settings.pinned_apps) do
                if app_id == "dapp:youtube" then insert_at = index + 1 break end
            end
            table.insert(self.settings.pinned_apps, insert_at or (#self.settings.pinned_apps + 1), "dapp:draw")
        end
    end
    if self.settings.layout_version < 25 then
        -- Offer the new audio-only YouTube Music DApp once. It shares yt-dlp and
        -- ffmpeg with the YouTube DApp, so it costs no additional setup.
        local pinned_music = false
        for _, app_id in ipairs(self.settings.pinned_apps) do
            if app_id == "dapp:youtube_music" then pinned_music = true break end
        end
        if not pinned_music then
            local insert_at
            for index, app_id in ipairs(self.settings.pinned_apps) do
                if app_id == "dapp:youtube" or app_id == "dapp:draw" then insert_at = index + 1 break end
            end
            table.insert(self.settings.pinned_apps, insert_at or (#self.settings.pinned_apps + 1), "dapp:youtube_music")
        end
    end
    -- Folder ids share the same ordered list as apps, so normalize it after
    -- all legacy app migrations have finished. This also removes malformed
    -- group records before they can occupy an invisible grid cell.
    self:_normalizePinnedGroups()
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
    self.settings.widgets.store = tableValue(self.settings.widgets.store)
    self.settings.widgets.store_order = copyArray(self.settings.widgets.store_order)
    self.settings.theme = self.settings.theme or { selected = "lavender", custom = {} }
    self.settings.theme.selected = self.settings.theme.selected or "lavender"
    self.settings.theme.custom = tableValue(self.settings.theme.custom)
    self.settings.design = self.settings.design or { active_id = nil, installed = {} }
    self.settings.design.installed = tableValue(self.settings.design.installed)
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
    self.settings.store = tableValue(self.settings.store, { installed = {} })
    self.settings.store.installed = tableValue(self.settings.store.installed)
    self.settings.notifications = tableValue(self.settings.notifications, { items = {}, next_id = 0 })
    self.settings.notifications.items = tableValue(self.settings.notifications.items)
    self.settings.notifications.next_id = tonumber(self.settings.notifications.next_id) or 0
    self.settings.wallpaper = self.settings.wallpaper or { enabled = false, path = "" }
    self.settings.wallpaper.enabled = self.settings.wallpaper.enabled == true
    self.settings.wallpaper.path = type(self.settings.wallpaper.path) == "string" and self.settings.wallpaper.path:sub(1, 360) or ""
    self.settings.wallpaper.source = self.settings.wallpaper.source == "appdock_default" and "appdock_default" or "user"
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
    self.settings.beta.windows = self.settings.beta.windows == true
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
    local allowed_text_scales = { [0.5] = true, [0.75] = true, [0.9] = true, [1] = true, [1.15] = true, [1.3] = true, [1.5] = true }
    local stored_text_scale = tonumber(self.settings.accessibility.text_scale) or 1
    self.settings.accessibility.text_scale = allowed_text_scales[stored_text_scale] and stored_text_scale or 1
    self.settings.accessibility.high_contrast = self.settings.accessibility.high_contrast == true
    self.settings.dapp_permissions = tableValue(self.settings.dapp_permissions)
    self.settings.widget_generator = tableValue(self.settings.widget_generator, { items = {}, next_id = 0 })
    self.settings.widget_generator.items = tableValue(self.settings.widget_generator.items)
    self.settings.widget_generator.next_id = math.max(0, math.floor(tonumber(self.settings.widget_generator.next_id) or 0))
    -- Do not retain any historical credential fields that may have been stored
    -- by the pre-cloud prototype. DChat only needs this non-secret display
    -- cache; the device session is deliberately a separate setting group.
    local tbs = type(self.settings.tbs_account) == "table" and self.settings.tbs_account or {}
    local tbs_display_name = boundedText(tbs.display_name, 80)
    local tbs_username = boundedText(tbs.username, 80)
    self.settings.tbs_account = {
        enabled = tbs.enabled == true,
        username = tbs_username ~= "" and tbs_username or tbs_display_name,
        display_name = tbs_display_name,
    }
    self.settings.setup_assistant = type(self.settings.setup_assistant) == "table" and self.settings.setup_assistant or {}
    self.settings.setup_assistant.offered_version = type(self.settings.setup_assistant.offered_version) == "string" and self.settings.setup_assistant.offered_version:sub(1, 24) or ""
    self.settings.setup_assistant.completed_version = type(self.settings.setup_assistant.completed_version) == "string" and self.settings.setup_assistant.completed_version:sub(1, 24) or ""
    self.settings.update_dialog = type(self.settings.update_dialog) == "table" and self.settings.update_dialog or {}
    self.settings.update_dialog.dismissed_version = type(self.settings.update_dialog.dismissed_version) == "string"
        and self.settings.update_dialog.dismissed_version:sub(1, 24) or ""
    self.settings.keyboard = type(self.settings.keyboard) == "table" and self.settings.keyboard or {}
    self.settings.keyboard.language = (self.settings.keyboard.language == "de" or self.settings.keyboard.language == "en")
        and self.settings.keyboard.language or "auto"
    self.settings.keyboard.enabled = self.settings.keyboard.enabled ~= false
    local keyboard_ok, Keyboard = pcall(require, "appdock_keyboard")
    if keyboard_ok and Keyboard and Keyboard.setEnabled then Keyboard.setEnabled(self.settings.keyboard.enabled) end
    self.settings.file_browser = type(self.settings.file_browser) == "table" and self.settings.file_browser or {}
    local file_categories = { all = true, documents = true, images = true, videos = true, audio = true, apps = true, folders = true }
    self.settings.file_browser.sort_category = file_categories[self.settings.file_browser.sort_category]
        and self.settings.file_browser.sort_category or "all"
    self.settings.file_browser.show_hidden = self.settings.file_browser.show_hidden == true
    local normalized_hidden_paths = {}
    for path, hidden in pairs(type(self.settings.file_browser.hidden_paths) == "table" and self.settings.file_browser.hidden_paths or {}) do
        if hidden == true and type(path) == "string" and #path <= 360 and path:match("^/[^%z]+$") and not path:find("..", 1, true) then
            normalized_hidden_paths[path] = true
        end
    end
    self.settings.file_browser.hidden_paths = normalized_hidden_paths
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
                app_id = type(item.app_id) == "string" and item.app_id ~= "" and item.app_id:sub(1, 96) or nil,
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
    -- Cloud writes are debounced and intentionally happen after a local save;
    -- an unavailable connection can therefore never cost local settings.
    if not self._tbs_sync_suspended then
        local ok, Account = pcall(require, "appdock_tbs_account")
        if ok and Account and Account.queueSync then pcall(Account.queueSync, self) end
    end
end

function AppDock:getRelease()
    return APPDOCK_RELEASE
end

function AppDock:getTBSAccountStatus()
    local ok, Account = pcall(require, "appdock_tbs_account")
    if not ok or not Account or not Account.status then return { signed_in = false } end
    local status_ok, status = pcall(Account.status, self)
    return status_ok and type(status) == "table" and status or { signed_in = false }
end

function AppDock:showTBSAccount(instance, context)
    local ok, Account = pcall(require, "appdock_tbs_account")
    if not ok or not Account or not Account.showSettings then return false end
    local shown, result = pcall(Account.showSettings, self, context)
    return shown and result == true
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
    return true
end

function AppDock:completeSetupAssistant()
    self.settings.setup_assistant = self.settings.setup_assistant or {}
    self.settings.setup_assistant.offered_version = SETUP_ASSISTANT_VERSION
    self.settings.setup_assistant.completed_version = SETUP_ASSISTANT_VERSION
    self:_saveSettings()
    return true
end

-- The setup wizard is an explicit Settings action.  Keep that separate from
-- the release-notes dialog shown during startup: existing users may dismiss
-- release notes without accidentally completing the local setup flow.
function AppDock:showSetupAssistant(instance, context)
    local manager = self:getDAppManager()
    if not manager or type(manager.showSetupAssistant) ~= "function" then return false end
    return manager:showSetupAssistant(instance, context, false) ~= false
end

function AppDock:shouldShowUpdateDialog()
    local state = self.settings.update_dialog or {}
    return state.dismissed_version ~= SETUP_ASSISTANT_VERSION
end

function AppDock:dismissUpdateDialog()
    self.settings.update_dialog = self.settings.update_dialog or {}
    self.settings.update_dialog.dismissed_version = SETUP_ASSISTANT_VERSION
    self:_saveSettings()
    return true
end

function AppDock:resetUpdateDialog()
    self.settings.update_dialog = self.settings.update_dialog or {}
    self.settings.update_dialog.dismissed_version = ""
    self:_saveSettings()
    return true
end

function AppDock:getKeyboardLanguage()
    local keyboard = self.settings.keyboard or {}
    return (keyboard.language == "de" or keyboard.language == "en") and keyboard.language or "auto"
end

function AppDock:setKeyboardLanguage(language)
    if language ~= "auto" and language ~= "de" and language ~= "en" then return false end
    self.settings.keyboard = self.settings.keyboard or {}
    self.settings.keyboard.language = language
    self:_saveSettings()
    local ok, Keyboard = pcall(require, "appdock_keyboard")
    if ok and Keyboard and Keyboard.setLanguage then Keyboard.setLanguage(language) end
    return true
end

function AppDock:getKeyboardEnabled()
    return not (self.settings.keyboard and self.settings.keyboard.enabled == false)
end

function AppDock:setKeyboardEnabled(enabled)
    self.settings.keyboard = self.settings.keyboard or {}
    self.settings.keyboard.enabled = enabled == true
    self:_saveSettings()
    local ok, Keyboard = pcall(require, "appdock_keyboard")
    if ok and Keyboard and Keyboard.setEnabled then Keyboard.setEnabled(self.settings.keyboard.enabled) end
    return true
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
        local allowed_text_scales = { [0.5] = true, [0.75] = true, [0.9] = true, [1] = true, [1.15] = true, [1.3] = true, [1.5] = true }
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
        self.settings.layout.app_spacing = math.max(8, math.min(200, tonumber(changes.app_spacing) or 16))
    end
    if changes.logo_shape == "circle" or changes.logo_shape == "rounded" then
        self.settings.layout.logo_shape = changes.logo_shape
    end
    if changes.search_enabled ~= nil then
        self.settings.layout.search_enabled = not not changes.search_enabled
    end
    if changes.ddg_search ~= nil then
        self.settings.layout.ddg_search = not not changes.ddg_search
    end
    self:_saveSettings()
end

function AppDock:adjustStoreWidgetScale(widget_id, delta)
    if type(widget_id) ~= "string" or #widget_id > 120 or not widget_id:match("^[%w:_%-]+$") then return false end
    local known = false
    for _, widget in ipairs(self:getStoreWidgets()) do
        if widget.widget_id == widget_id then known = true; break end
    end
    if not known then return false end
    local scales = self.settings.layout.widget_scales or {}
    local current = tonumber(scales[widget_id]) or 1
    local next_scale = math.max(.75, math.min(1.5, current + (tonumber(delta) or 0)))
    next_scale = math.floor(next_scale * 4 + .5) / 4
    if next_scale == 1 then scales[widget_id] = nil else scales[widget_id] = next_scale end
    self.settings.layout.widget_scales = scales
    self:_saveSettings()
    return next_scale
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
    if key ~= "black_borders" and key ~= "keep_wallpaper_original_in_night" and key ~= "plugin_dapp_host" and key ~= "windows" and key ~= "manual_app_spacing" and key ~= "plugin_custom_logos" then return false end
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
function AppDock:getRefreshInterval()
    return tonumber(self.settings.refresh_interval) or 60
end
function AppDock:setRefreshInterval(seconds)
    seconds = math.floor((tonumber(seconds) or 60) / 15 + .5) * 15
    seconds = math.max(15, math.min(300, seconds))
    self.settings.refresh_interval = seconds
    self:_saveSettings()
    self:_scheduleScreenRefresh()
    return seconds
end

local QUICK_TILE_IDS = { wifi = true, night = true, refresh = true, edit = true, rotate = true, sleep = true, power_saving = true, wallpaper = true }

function AppDock:getQuickSettingsTiles()
    if self:isSimpleModeEnabled("quick_settings") then
        return { "wifi", "night", "power_saving", "rotate" }
    end
    local tile_settings = self.settings.quick_settings
    if tile_settings.rotation_tile_migrated ~= true then
        local tiles, has_rotate = {}, false
        for _, tile_id in ipairs(tile_settings.tiles or {}) do
            if tile_id == "draw" then
                if not has_rotate then tiles[#tiles + 1] = "rotate"; has_rotate = true end
            else
                tiles[#tiles + 1] = tile_id
                if tile_id == "rotate" then has_rotate = true end
            end
        end
        if not has_rotate then tiles[#tiles + 1] = "rotate" end
        tile_settings.tiles = tiles
        tile_settings.draw_tile_migrated = nil
        tile_settings.rotation_tile_migrated = true
    end
    local tiles, seen = {}, {}
    for _, tile_id in ipairs(tile_settings.tiles or {}) do
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

function AppDock:getYouTubeSettings()
    self.settings.youtube = normalizeYouTubeSettings(self.settings.youtube)
    return self.settings.youtube
end

-- Merges the given keys, normalizes the result and persists it. Unknown or
-- unusable values fall back to the DApp defaults instead of being stored.
function AppDock:setYouTubeSettings(changes)
    if type(changes) ~= "table" then return false end
    local merged = {}
    for key, value in pairs(self:getYouTubeSettings()) do merged[key] = value end
    for key, value in pairs(changes) do
        if type(key) == "string" and (type(value) == "string" or type(value) == "number" or type(value) == "boolean") then
            merged[key] = value
        end
    end
    self.settings.youtube = normalizeYouTubeSettings(merged)
    self:_saveSettings()
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

function AppDock:getUnreadNotificationCountForApp(app_id)
    if type(app_id) ~= "string" or app_id == "" then return 0 end
    local count = 0
    for _, item in ipairs(self.settings.notifications.items or {}) do
        if not item.read and item.app_id == app_id then count = count + 1 end
    end
    return count
end

function AppDock:_refreshNotificationBadges()
    if self._home_screen then UIManager:setDirty(self._home_screen, "ui") end
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
        app_id = type(payload.app_id) == "string" and payload.app_id ~= "" and payload.app_id:sub(1, 96) or nil,
        priority = payload.priority == "high" and "high" or "normal",
        created_at = os.time(),
        read = false,
    }
    table.insert(self.settings.notifications.items, 1, notification)
    while #self.settings.notifications.items > 50 do table.remove(self.settings.notifications.items) end
    self:_saveSettings()
    self:_refreshNotificationBadges()
    local ok, Notifications = pcall(require, "appdock_notifications")
    if ok and Notifications and Notifications.showToast then Notifications.showToast(notification) end
    return true, notification
end

function AppDock:markNotificationRead(id)
    for _, item in ipairs(self.settings.notifications.items or {}) do
        if item.id == id then
            item.read = true
            self:_saveSettings()
            self:_refreshNotificationBadges()
            return true
        end
    end
    return false
end

function AppDock:markAllNotificationsRead()
    for _, item in ipairs(self.settings.notifications.items or {}) do item.read = true end
    self:_saveSettings()
    self:_refreshNotificationBadges()
end

function AppDock:clearNotifications()
    self.settings.notifications.items = {}
    self:_saveSettings()
    self:_refreshNotificationBadges()
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
        UIManager:scheduleIn(math.max(self:getRefreshInterval(), self.settings.power_saving and 180 or 0), self._screen_refresh_tick)
    end
    UIManager:scheduleIn(math.max(self:getRefreshInterval(), self.settings.power_saving and 180 or 0), self._screen_refresh_tick)
end

function AppDock:_scheduleDAppTasks()
    if self._dapp_task_tick then UIManager:unschedule(self._dapp_task_tick) end
    -- DApps such as DChat may opt in to a one-minute background check; each
    -- DApp still enforces its own interval and explicit permission.
    self._dapp_task_tick = function()
        pcall(function()
            if not self.settings.power_saving then
                local manager = self:getDAppManager()
                if manager and manager.runPermittedBackgroundTasks then manager:runPermittedBackgroundTasks() end
            end
        end)
        if self._dapp_task_tick then UIManager:scheduleIn(60, self._dapp_task_tick) end
    end
    UIManager:scheduleIn(60, self._dapp_task_tick)
end

function AppDock:onCloseWidget()
    if self.dapp_manager and self.dapp_manager.stopBackgroundJobs then self.dapp_manager:stopBackgroundJobs() end
    if self.dapp_manager and self.dapp_manager.captureWorkspace then self.dapp_manager:captureWorkspace() end
    local account_ok, Account = pcall(require, "appdock_tbs_account")
    if account_ok and Account and Account.cancelQueuedSync then pcall(Account.cancelQueuedSync, self) end
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

function AppDock:_showSafeError(text)
    local ok, dialog = pcall(InfoMessage.new, InfoMessage, { text = text })
    if ok and dialog then pcall(UIManager.show, UIManager, dialog) end
    return false
end

function AppDock:showHome(skip_lock, on_ready)
    if self.settings.lockscreen.enabled and not skip_lock then
        local ok, LockScreen = pcall(require, "appdock_lockscreen")
        if ok and LockScreen and LockScreen.show then
            LockScreen.show(self, function() self:showHome(true, on_ready) end)
            return
        end
    end
    if not self._boot_shown then
        self._boot_shown = true
        local ok, Boot = pcall(require, "appdock_boot")
        if ok and Boot and Boot.show then
            Boot.show(function() self:showHome(true, on_ready) end)
            return
        end
    end
    local loaded, HomeScreen = pcall(require, "appdock_homescreen")
    if not loaded or not HomeScreen then
        return self:_showSafeError(_("AppDock homescreen could not be opened. Restart KOReader; the previous working plugin version can then be restored."))
    end
    local built, home = pcall(HomeScreen.new, HomeScreen, { appdock = self })
    if not built or not home then
        return self:_showSafeError(_("AppDock homescreen could not be built. Your local AppDock settings were kept unchanged."))
    end
    local shown = pcall(UIManager.show, UIManager, home)
    if not shown then return self:_showSafeError(_("AppDock homescreen could not be shown safely.")) end
    if on_ready then UIManager:nextTick(on_ready) end
    return true
end

function AppDock:showManager(home, selected_app)
    local loaded, AppDockManager = pcall(require, "appdock_manager")
    if not loaded or not AppDockManager or type(AppDockManager.show) ~= "function" then
        return self:_showSafeError(_("AppDock management is unavailable. Restart KOReader and try again."))
    end
    local shown = pcall(AppDockManager.show, AppDockManager, { appdock = self, parent_home = home, selected_app = selected_app })
    if not shown then return self:_showSafeError(_("AppDock management could not be opened safely.")) end
    return true
end

function AppDock:getDAppManager()
    if not self.dapp_manager then
        local loaded, DAppManager = pcall(require, "appdock_dapps")
        if not loaded or not DAppManager or type(DAppManager.new) ~= "function" then return nil end
        local created, manager = pcall(DAppManager.new, DAppManager, self)
        if not created or not manager then return nil end
        self.dapp_manager = manager
    end
    return self.dapp_manager
end

function AppDock:showOpenApps(home)
    local manager = self:getDAppManager()
    if manager and manager.showRecents then return manager:showRecents(home) end
    return self:_showSafeError(_("Open apps is unavailable because the AppDock DApp service could not be loaded."))
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
    if type(plugin_module) ~= "table" or type(plugin_module.name) ~= "string"
        or type(self.ui) ~= "table" or plugin_module.name == self.name then
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
        title = type(plugin_module.fullname) == "string" and plugin_module.fullname or plugin_module.name,
        subtitle = type(plugin_module.description) == "string" and plugin_module.description or plugin_module.name,
        actions = actions,
        instance = instance,
        custom_logo_path = self:getPluginLogo("plugin:" .. plugin_module.name),
        buildAppDockPane = type(instance.buildAppDockPane) == "function" and instance.buildAppDockPane or nil,
    }
end

function AppDock:getDAppApps()
    local manager = self:getDAppManager()
    if manager and manager.getCatalogApps then
        local ok, apps = pcall(manager.getCatalogApps, manager)
        if ok and type(apps) == "table" then return apps end
    end
    return {}
end

function AppDock:getPluginApps()
    local apps = {}
    local loaded, plugins = pcall(PluginLoader.loadPlugins, PluginLoader)
    if not loaded or type(plugins) ~= "table" then return apps end
    for _, plugin_module in ipairs(plugins) do
        local ok, app = pcall(self._makePluginApp, self, plugin_module)
        if ok and app then table.insert(apps, app) end
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

local function sameIdList(left, right)
    if #left ~= #right then return false end
    for index, value in ipairs(left) do
        if right[index] ~= value then return false end
    end
    return true
end

local function sameGroupState(left, right)
    left, right = type(left) == "table" and left or {}, type(right) == "table" and right or {}
    if tonumber(left.next_id) ~= tonumber(right.next_id) then return false end
    local left_items, right_items = left.items or {}, right.items or {}
    for id, left_group in pairs(left_items) do
        local right_group = right_items[id]
        if not right_group or left_group.title ~= right_group.title or not sameIdList(left_group.apps or {}, right_group.apps or {}) then
            return false
        end
    end
    for id in pairs(right_items) do
        if not left_items[id] then return false end
    end
    return true
end

-- Reconcile the persisted group map with the single ordered list that drives
-- the grid. A folder consumes one item in pinned_apps, and every child belongs
-- to at most one visible tile. Supplying a catalog additionally prunes apps
-- which are no longer launchable, matching the pre-folder pin cleanup.
function AppDock:_normalizePinnedGroups(catalog)
    local old_pins = self.settings.pinned_apps or {}
    local old_groups = self.settings.app_groups
    local groups = AppDockGroups.normalize(old_groups)
    local pins, visible_items, claimed_members, seen_tiles = {}, {}, {}, {}

    for _, item_id in ipairs(old_pins) do
        if AppDockGroups.isGroupId(item_id) then
            local record = groups.items[item_id]
            if record and not seen_tiles[item_id] then
                local members = {}
                for _, app_id in ipairs(record.apps) do
                    if not claimed_members[app_id] and (not catalog or catalog[app_id]) then
                        members[#members + 1] = app_id
                    end
                end
                if #members >= 2 then
                    record.apps = members
                    visible_items[item_id] = record
                    pins[#pins + 1] = item_id
                    seen_tiles[item_id] = true
                    for _, app_id in ipairs(members) do claimed_members[app_id] = true end
                elseif #members == 1 and not claimed_members[members[1]] then
                    -- A group must contain multiple apps. If a removed app
                    -- leaves one child, preserve that child at the same grid
                    -- position instead of silently losing its launch tile.
                    pins[#pins + 1] = members[1]
                    claimed_members[members[1]] = true
                end
            end
        elseif AppDockGroups.isValidAppId(item_id) and not seen_tiles[item_id]
                and not claimed_members[item_id] and (not catalog or catalog[item_id]) then
            pins[#pins + 1] = item_id
            seen_tiles[item_id] = true
            claimed_members[item_id] = true
        end
    end

    groups.items = visible_items
    self.settings.pinned_apps = pins
    self.settings.app_groups = groups
    return not sameIdList(old_pins, pins) or not sameGroupState(old_groups, groups)
end

function AppDock:getPinnedApps()
    local catalog = self:getAppCatalog()
    if self:_normalizePinnedGroups(catalog) then
        self:_saveSettings()
    end
    local apps = {}
    for _, item_id in ipairs(self.settings.pinned_apps) do
        if AppDockGroups.isGroupId(item_id) then
            local record = self.settings.app_groups.items[item_id]
            local members = {}
            for _, app_id in ipairs(record and record.apps or {}) do
                local app = catalog[app_id]
                if app and self:isSimpleModeAppAllowed(app) then members[#members + 1] = app end
            end
            if #members > 0 then
                table.insert(apps, {
                    id = item_id,
                    group_id = item_id,
                    title = record.title,
                    is_group = true,
                    group_apps = members,
                })
            end
        else
            local app = catalog[item_id]
            if app and self:isSimpleModeAppAllowed(app) then table.insert(apps, app) end
        end
    end
    return apps
end

function AppDock:_recordRecentApp(app)
    if type(app) ~= "table" or type(app.id) ~= "string" or app.id == "" then return false end
    if app.id == "system:manage" or app.id == "system:open_apps" then return false end

    local recent, seen = { app.id }, { [app.id] = true }
    for _, app_id in ipairs(self.settings.recent_apps or {}) do
        if type(app_id) == "string" and not seen[app_id] and #recent < 4 then
            recent[#recent + 1] = app_id
            seen[app_id] = true
        end
    end
    self.settings.recent_apps = recent
    self:_saveSettings()
    return true
end

function AppDock:getRecentApps(limit)
    limit = math.max(1, math.min(4, math.floor(tonumber(limit) or 4)))
    local catalog = self:getAppCatalog()
    local apps, valid_ids, seen = {}, {}, {}
    for _, app_id in ipairs(self.settings.recent_apps or {}) do
        local app = catalog[app_id]
        if type(app_id) == "string" and app and app_id ~= "system:manage" and app_id ~= "system:open_apps" and not seen[app_id] and self:isSimpleModeAppAllowed(app) then
            valid_ids[#valid_ids + 1] = app_id
            seen[app_id] = true
            if #apps < limit then apps[#apps + 1] = app end
        end
    end

    local changed = #valid_ids ~= #(self.settings.recent_apps or {})
    if not changed then
        for index, app_id in ipairs(valid_ids) do
            if self.settings.recent_apps[index] ~= app_id then changed = true; break end
        end
    end
    if changed then
        self.settings.recent_apps = valid_ids
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
    return AppDockGroups.findContaining(self.settings.app_groups, app_id) ~= nil
end

function AppDock:getPinnedPosition(app_id)
    for index, pinned_id in ipairs(self.settings.pinned_apps) do
        if pinned_id == app_id then return index, #self.settings.pinned_apps end
    end
    return nil, #self.settings.pinned_apps
end

function AppDock:movePinned(app_id, delta)
    if AppDockOrder.move(self.settings.pinned_apps, app_id, delta) then
        self:_saveSettings()
        return true
    end
    return false
end

function AppDock:togglePinned(app_id)
    if not AppDockGroups.isValidAppId(app_id) or AppDockGroups.isGroupId(app_id) then return false end
    for index, pinned_id in ipairs(self.settings.pinned_apps) do
        if pinned_id == app_id then
            table.remove(self.settings.pinned_apps, index)
            self:_saveSettings()
            return false
        end
    end

    local containing_group = AppDockGroups.findContaining(self.settings.app_groups, app_id)
    if containing_group then
        local record = self.settings.app_groups.items[containing_group]
        local remaining = {}
        for _, member_id in ipairs(record.apps) do
            if member_id ~= app_id then remaining[#remaining + 1] = member_id end
        end
        if #remaining >= 2 then
            record.apps = remaining
        else
            self.settings.app_groups.items[containing_group] = nil
            for index, pinned_id in ipairs(self.settings.pinned_apps) do
                if pinned_id == containing_group then
                    table.remove(self.settings.pinned_apps, index)
                    if remaining[1] then table.insert(self.settings.pinned_apps, index, remaining[1]) end
                    break
                end
            end
        end
        self:_normalizePinnedGroups()
        self:_saveSettings()
        return false
    end
    table.insert(self.settings.pinned_apps, app_id)
    self:_saveSettings()
    return true
end

function AppDock:isAppGroup(group_id)
    return AppDockGroups.isGroupId(group_id) and self.settings.app_groups.items[group_id] ~= nil
end

function AppDock:getAppGroup(group_id)
    local record = self:isAppGroup(group_id) and self.settings.app_groups.items[group_id] or nil
    if not record then return nil end
    return { id = group_id, title = record.title, apps = copyArray(record.apps) }
end

function AppDock:getAppGroupApps(group_id)
    local record = self:isAppGroup(group_id) and self.settings.app_groups.items[group_id] or nil
    if not record then return {} end
    local catalog, apps = self:getAppCatalog(), {}
    for _, app_id in ipairs(record.apps) do
        local app = catalog[app_id]
        if app and self:isSimpleModeAppAllowed(app) then apps[#apps + 1] = app end
    end
    return apps
end

function AppDock:createAppGroup(title, app_ids)
    local members, selected, first_position = {}, {}, nil
    for _, app_id in ipairs(type(app_ids) == "table" and app_ids or {}) do
        local position = AppDockOrder.findPosition(self.settings.pinned_apps, app_id)
        if AppDockGroups.isValidAppId(app_id) and not AppDockGroups.isGroupId(app_id) and position and not selected[app_id] then
            members[#members + 1], selected[app_id] = app_id, true
            first_position = math.min(first_position or position, position)
        end
    end
    if #members < 2 then return false, "Select at least two homescreen apps." end
    local groups = self.settings.app_groups
    local group_count = 0
    for _ in pairs(groups.items or {}) do group_count = group_count + 1 end
    if group_count >= AppDockGroups.MAX_GROUPS then return false, "The app group limit has been reached." end

    local group_id = AppDockGroups.nextId(groups)
    groups.items[group_id] = { title = AppDockGroups.sanitizeTitle(title), apps = members }
    local reordered = {}
    for index, item_id in ipairs(self.settings.pinned_apps) do
        if index == first_position then reordered[#reordered + 1] = group_id end
        if not selected[item_id] then reordered[#reordered + 1] = item_id end
    end
    self.settings.pinned_apps = reordered
    self:_normalizePinnedGroups()
    self:_saveSettings()
    return true, group_id
end

function AppDock:renameAppGroup(group_id, title)
    if not self:isAppGroup(group_id) then return false end
    self.settings.app_groups.items[group_id].title = AppDockGroups.sanitizeTitle(title)
    self:_saveSettings()
    return true
end

function AppDock:setAppGroupMembers(group_id, app_ids)
    if not self:isAppGroup(group_id) then return false, "The app group no longer exists." end
    local members, selected = {}, {}
    for _, app_id in ipairs(type(app_ids) == "table" and app_ids or {}) do
        if AppDockGroups.isValidAppId(app_id) and not AppDockGroups.isGroupId(app_id) and not selected[app_id] then
            members[#members + 1], selected[app_id] = app_id, true
            if #members >= AppDockGroups.MAX_MEMBERS then break end
        end
    end
    if #members < 2 then return false, "An app group needs at least two apps." end

    local groups = self.settings.app_groups
    local removed_from_group = {}
    for _, app_id in ipairs(groups.items[group_id].apps) do
        if not selected[app_id] then removed_from_group[#removed_from_group + 1] = app_id end
    end
    groups.items[group_id].apps = members
    local collapsed = {}
    for other_id, record in pairs(groups.items) do
        if other_id ~= group_id then
            local kept = {}
            for _, app_id in ipairs(record.apps) do
                if not selected[app_id] then kept[#kept + 1] = app_id end
            end
            if #kept >= 2 then
                record.apps = kept
            else
                groups.items[other_id] = nil
                collapsed[other_id] = kept[1]
            end
        end
    end
    local reordered, seen = {}, {}
    for _, item_id in ipairs(self.settings.pinned_apps) do
        if item_id == group_id then
            reordered[#reordered + 1], seen[item_id] = item_id, true
            -- Editing a folder is equivalent to moving an app out of it, not
            -- deleting that app. Keep removed members immediately after the
            -- folder so the user never loses a launch tile by mistake.
            for _, app_id in ipairs(removed_from_group) do
                if not seen[app_id] then
                    reordered[#reordered + 1], seen[app_id] = app_id, true
                end
            end
        elseif AppDockGroups.isGroupId(item_id) then
            local remaining = collapsed[item_id]
            if remaining and not selected[remaining] and not seen[remaining] then
                reordered[#reordered + 1], seen[remaining] = remaining, true
            elseif groups.items[item_id] and not seen[item_id] then
                reordered[#reordered + 1], seen[item_id] = item_id, true
            end
        elseif not selected[item_id] and not seen[item_id] then
            reordered[#reordered + 1], seen[item_id] = item_id, true
        end
    end
    self.settings.pinned_apps = reordered
    self:_normalizePinnedGroups()
    self:_saveSettings()
    return true
end

function AppDock:ungroupAppGroup(group_id)
    local record = self:isAppGroup(group_id) and self.settings.app_groups.items[group_id] or nil
    if not record then return false end
    local reordered = {}
    for _, item_id in ipairs(self.settings.pinned_apps) do
        if item_id == group_id then
            for _, app_id in ipairs(record.apps) do reordered[#reordered + 1] = app_id end
        else
            reordered[#reordered + 1] = item_id
        end
    end
    self.settings.app_groups.items[group_id] = nil
    self.settings.pinned_apps = reordered
    self:_normalizePinnedGroups()
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
    if not manager or type(manager.getStoreWidgets) ~= "function" then return available end
    local ok, widgets = pcall(manager.getStoreWidgets, manager)
    if not ok or type(widgets) ~= "table" then return available end
    for _, widget in ipairs(widgets) do
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
    if AppDockOrder.move(order, widget_id, delta) then
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
        local ok = pcall(item.callback)
        if ok then return true end
        return self:_showSafeError(_("This plugin action failed. AppDock remains open; try restarting the affected plugin."))
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
    self:_recordRecentApp(app)
    if app.kind == "dapp" then
        local manager = self:getDAppManager()
        if manager and manager.activate then return manager:activate(app.dapp_id, home) end
        return self:_showSafeError(_("This AppDock app is currently unavailable."))
    end

    if app.plugin_name and app.actions and self.settings.beta and self.settings.beta.plugin_dapp_host then
        local manager = self:getDAppManager()
        if manager and manager.activatePlugin then return manager:activatePlugin(app, home) end
        return self:_showSafeError(_("This plugin host is currently unavailable."))
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
