local plugin_dir = os.getenv("APPDOCK_PLUGIN_DIR") or "/home/ubuntu/koreader-homescreen/appdock.koplugin/"

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
        if instance._init then instance:_init() end
        if instance.init then instance:init() end
        return instance
    end
    function prototype:getSize()
        if self.dimen then return self.dimen end
        return { w = self.width or 0, h = self.height or 0 }
    end
    function prototype:clear() while table.remove(self) do end end
    return prototype
end

local Widget = baseClass({})
local WidgetContainer = Widget:extend({})
local InputContainer = WidgetContainer:extend({})
function InputContainer:paintTo() end
local FrameContainer = WidgetContainer:extend({})
local CenterContainer = WidgetContainer:extend({})
local OverlapGroup = WidgetContainer:extend({})
local VerticalGroup = WidgetContainer:extend({})
local HorizontalSpan = WidgetContainer:extend({})
local VerticalSpan = WidgetContainer:extend({})

local log = { shown = {}, closed = {}, dirties = {}, scheduled = {}, events = {} }
local wifi_on = false
_G.G_reader_settings = { isTrue = function() return false end, readSetting = function(_, key) return key == "language" and "en" or nil end }

package.preload["ffi/blitbuffer"] = function()
    return {
        COLOR_WHITE = "white", COLOR_BLACK = "black", COLOR_DARK_GRAY = "dark", COLOR_LIGHT_GRAY = "light",
        COLOR_GRAY = "gray", COLOR_GRAY_7 = "g7", COLOR_GRAY_8 = "g8",
        ColorRGB32 = function(r, g, b, a) return string.format("%d,%d,%d,%d", r, g, b, a) end,
    }
end
package.preload["device"] = function()
    return {
        screen = { getSize = function() return { w = 600, h = 800 } end, scaleBySize = function(_, n) return n end, isColorEnabled = function() return false end },
        hasKeys = function() return false end,
    }
end
package.preload["gettext"] = function() return function(text) return text end end
package.preload["datastorage"] = function() return { getDataDir = function() return "/tmp/appdock_test_data" end } end
package.preload["ui/font"] = function() return { getFace = function(_, name, size) return { name = name, size = size or 12 } end } end
package.preload["ui/geometry"] = function() return { new = function(_, args) return args end } end
package.preload["ui/gesturerange"] = function() return { new = function(_, args) return args end } end
package.preload["ui/event"] = function() return { new = function(_, name) return { name = name } end } end
package.preload["appdock_theme"] = function()
    return dofile(plugin_dir .. "appdock_theme.lua")
end
package.preload["appdock_logo"] = function()
    local Logo = Widget:extend({})
    function Logo.availableKinds() return { "app_store", "palette" } end
    return Logo
end
package.preload["appdock_appstore"] = function()
    return {
        new = function()
            return {
                buildPane = function(_, instance, context)
                    return WidgetContainer:new{ dimen = { w = context.dimen.w, h = context.dimen.h } }
                end,
            }
        end,
    }
end
package.preload["appdock_filemanager"] = function()
    return {
        new = function()
            return {
                buildPane = function(_, instance, context)
                    return WidgetContainer:new{ dimen = { w = context.dimen.w, h = context.dimen.h } }
                end,
            }
        end,
    }
end
package.preload["appdock_browser"] = function()
    return {
        new = function()
            return {
                buildPane = function(_, instance, context)
                    return WidgetContainer:new{ dimen = { w = context.dimen.w, h = context.dimen.h } }
                end,
            }
        end,
    }
end
package.preload["ui/network/manager"] = function()
    return {
        isWifiOn = function() return wifi_on end,
        toggleWifiOn = function(_, callback) wifi_on = true; callback() end,
        toggleWifiOff = function(_, callback) wifi_on = false; callback() end,
    }
end
package.preload["ui/widget/confirmbox"] = function() return WidgetContainer end
package.preload["ui/widget/inputdialog"] = function() return WidgetContainer end
package.preload["ui/widget/buttondialog"] = function() return WidgetContainer end
package.preload["ui/widget/infomessage"] = function() return WidgetContainer end
package.preload["ui/widget/widget"] = function() return Widget end
package.preload["ui/widget/imagewidget"] = function() return Widget end
package.preload["ui/widget/container/widgetcontainer"] = function() return WidgetContainer end
package.preload["ui/widget/container/inputcontainer"] = function() return InputContainer end
package.preload["ui/widget/container/centercontainer"] = function() return CenterContainer end
package.preload["ui/widget/container/framecontainer"] = function() return FrameContainer end
package.preload["ui/widget/overlapgroup"] = function() return OverlapGroup end
package.preload["ui/widget/container/scrollablecontainer"] = function() return WidgetContainer end
package.preload["ui/widget/verticalgroup"] = function() return VerticalGroup end
package.preload["ui/widget/horizontalspan"] = function() return HorizontalSpan end
package.preload["ui/widget/verticalspan"] = function() return VerticalSpan end
package.preload["ui/widget/scrollhtmlwidget"] = function() return WidgetContainer end
package.preload["ui/widget/textwidget"] = function()
    local Text = Widget:extend({})
    function Text:getSize()
        local size = self.face and self.face.size or 12
        return { w = #(self.text or "") * math.floor(size * .5), h = size }
    end
    return Text
end
package.preload["ui/uimanager"] = function()
    return {
        show = function(_, widget) table.insert(log.shown, widget) end,
        close = function(_, widget) table.insert(log.closed, widget); if widget.onCloseWidget then widget:onCloseWidget() end end,
        nextTick = function(_, callback) callback() end,
        scheduleIn = function(_, seconds, callback) table.insert(log.scheduled, callback) end,
        unschedule = function() end,
        setDirty = function(_, widget, kind, region) table.insert(log.dirties, { widget = widget, kind = kind, region = region }) end,
        forceRePaint = function() end,
        yieldToEPDC = function() log.epdc_yields = (log.epdc_yields or 0) + 1 end,
        broadcastEvent = function(_, event) table.insert(log.events, event.name) end,
    }
end

local DAppManager = dofile(plugin_dir .. "appdock_dapps.lua")
local Device = require("device")
local Theme = require("appdock_theme")
local UIManager = require("ui/uimanager")
local Layout = require("appdock_layout")
local fixed_stack_paints = {}
local fixed_stack = Layout.FixedStack:new{
    width = 40,
    height = 20,
    entries = {
        { widget = { getSize = function() return { w = 18, h = 8 } end, paintTo = function(_, _, x, y) table.insert(fixed_stack_paints, { x = x, y = y }) end }, x = -10, y = 30 },
        { widget = { getSize = function() return { w = 12, h = 6 } end, paintTo = function(_, _, x, y) table.insert(fixed_stack_paints, { x = x, y = y }) end }, x = 99, y = 99 },
    },
}
fixed_stack:paintTo({}, 100, 200)
assert(fixed_stack:getSize().w == 40 and fixed_stack:getSize().h == 20, "Fixed text stacks must consume exactly their declared card bounds")
assert(fixed_stack_paints[1].x == 100 and fixed_stack_paints[1].y == 212 and fixed_stack_paints[2].x == 128 and fixed_stack_paints[2].y == 214, "Fixed text stacks must clamp every child inside its card before painting")
assert(Theme.ellipsize("ABCDE", 4) == "ABC…", "Text overflow must use a bounded one-line ellipsis")
assert(Theme.ellipsize("Äpfel", 4) == "Äpf…", "Text overflow must preserve complete UTF-8 characters")
assert(Theme.fitLabel("A long compact button label", 30, 10, 0):find("…", 1, true), "Narrow controls must shorten labels instead of allowing wrapped text")
local stack_positions, stack_total = Theme.centeredStack(80, { 18, 12, 10 }, 4, 3)
assert(stack_total == 44 and stack_positions[1] >= 3 and stack_positions[2] >= stack_positions[1] + 20 and stack_positions[3] >= stack_positions[2] + 14, "Compact text stacks must reduce gaps while keeping every line ordered and inside a padded control")
local recents_source = assert(io.open(plugin_dir .. "appdock_dapps.lua", "rb")):read("*a")
local open_apps_title_count = select(2, recents_source:gsub('text = _%("Open apps"%)', ""))
assert(open_apps_title_count == 1 and recents_source:find("local y = header_height + gap", 1, true), "Open Apps must draw one measured header and begin cards below it")
local quick_settings_source = assert(io.open(plugin_dir .. "appdock_quicksettings.lua", "rb")):read("*a")
assert(quick_settings_source:find("local function buildStack", 1, true) and quick_settings_source:find("Theme.centeredStack(self.height, stack", 1, true) and quick_settings_source:find("local tile_y = header_height + gap", 1, true), "Quick Settings must measure tile text and reserve a header gap before tiles")
assert(quick_settings_source:find("symbol_widget = TextWidget:new", 1, true) and quick_settings_source:find("padding = 0", 1, true) and quick_settings_source:find("while stack_height > available_height", 1, true), "Quick Settings tiles must use unpadded measured glyph boxes and shrink before overflowing fixed controls")
local appstore_source = assert(io.open(plugin_dir .. "appdock_appstore.lua", "rb")):read("*a")
assert(appstore_source:find("local header_height = math.max", 1, true) and appstore_source:find("local list_y, card_height = action_y", 1, true), "AppStore rows must begin after their measured header and control rows")
assert(appstore_source:find("padding = 0", 1, true), "AppStore fixed-height labels must not inherit TextWidget vertical padding")
local homescreen_source = assert(io.open(plugin_dir .. "appdock_homescreen.lua", "rb")):read("*a")
local simple_mode_source = homescreen_source:match("function AppDockHomeScreen:_buildSimpleMode.-\nend") or ""
assert(homescreen_source:find("local header_positions = Theme.centeredStack", 1, true) and homescreen_source:find("local card_y = header_y + header_height", 1, true), "Normal Homescreen cards must begin after measured greeting lines")
assert(not simple_mode_source:find("Theme.centeredStack", 1, true) and not simple_mode_source:find("has_header_surface", 1, true), "Simple Mode must retain its independent reduced layout path")
assert(recents_source:find('title = "", symbol = "⌂", width = scale(72), height = scale(44)', 1, true), "Compact Open Apps navigation must not place a text label beneath its Home button")
assert(recents_source:find("local margin, gap = scale(10), scale(4)", 1, true) and recents_source:find("math.min(scale(50)", 1, true), "Settings must use visibly compact row and category spacing")
assert(recents_source:find("local card_height = expressive and scale(64) or scale(60)", 1, true) and recents_source:find("local gap = expressive and scale(6) or scale(6)", 1, true), "Open Apps must use visibly compact cards and list gaps")
assert(recents_source:find("local Layout = require(\"appdock_layout\")", 1, true) and recents_source:find("Layout.FixedStack:new", 1, true), "DApp settings and action controls must use fixed-bounds foreground drawing")
assert(quick_settings_source:find("tile_height = scale(68)", 1, true) and quick_settings_source:find("slider_spacing = scale(8)", 1, true), "Normal Quick Settings must use compact visible tile and sheet spacing")
assert(quick_settings_source:find("Layout.FixedStack:new", 1, true), "Quick Settings tiles and notifications must keep their text inside explicit fixed bounds")
assert(appstore_source:find("local compact_height = scale(42)", 1, true) and appstore_source:find("local list_y, card_height", 1, true) and appstore_source:find("scale(58)", 1, true), "AppStore must use compact visible controls and catalog cards")
assert(homescreen_source:find("local label_height = scale(20)", 1, true) and homescreen_source:find("local label_gap = scale(3)", 1, true) and homescreen_source:find("local row_gap = scale(12)", 1, true), "Normal Homescreen app labels and rows must use compact visible spacing")
assert(appstore_source:find("Layout.FixedStack:new", 1, true) and homescreen_source:find("Layout.FixedStack:new", 1, true), "AppStore and Homescreen cards must draw text through the fixed-bounds container")
assert(simple_mode_source:find("local column_gap, row_gap, label_height = scale(12), scale(14), scale(22)", 1, true), "Simple Mode must retain its original app-grid spacing")
local files_source = assert(io.open(plugin_dir .. "appdock_filemanager.lua", "rb")):read("*a")
assert(files_source:find("local margin, gap = scale(12), scale(5)", 1, true) and files_source:find("local row_height = scale(54)", 1, true), "Files must use compact visible rows and gaps")
assert(files_source:find("Layout.FixedStack:new", 1, true), "File rows must draw labels through the same fixed-bounds container")
local design_definition = Theme.normalizeDesignDefinition({
    id = "galaxy", title = "Galaxy", version = "1.0.0", highlight = "#A98BFF", background = "#111126",
    button = "#282653", text = "#F8F7FF", dropdown = "#181634", button_style = "3d", logo_shape = "circle",
})
assert(design_definition and design_definition.id == "galaxy" and design_definition.button_style == "3d" and design_definition.logo_shape == "circle", "A Store design must normalize all declared appearance fields")
assert(not Theme.normalizeDesignDefinition({ id = "unsafe/id", title = "Bad", highlight = "#000000", background = "#000000", button = "#000000", text = "#FFFFFF", dropdown = "#000000" }), "Design ids must stay local-safe and require every declared color")
local AppStoreParser = dofile(plugin_dir .. "appdock_appstore.lua")
local design_entries = AppStoreParser.parseManifest("designs/galaxy.appdock-design | 1.0.0 | palette | design\nquote_widget.lua | 1.0.0 | help | widget")
assert(#design_entries == 2 and design_entries[1].kind == "design" and design_entries[1].path == "designs/galaxy.appdock-design", "The AppStore catalog must accept isolated declarative design entries")
assert(#AppStoreParser.filterEntries(design_entries, "", "design") == 1 and #AppStoreParser.filterEntries(design_entries, "", "widget") == 1, "The AppStore category filter must isolate designs from widgets")
local parsed_design = assert(AppStoreParser:_parseDesign("id=forest\ntitle=Forest\nversion=1.0.0\nhighlight=#A5D6A7\nbackground=#122219\nbutton=#2D6745\ntext=#EFF8E9\ndropdown=#183125\nbutton_style=rounded\nlogo_shape=rounded\nwallpaper=designs/wallpapers/forest.png"))
assert(parsed_design.id == "forest" and parsed_design.wallpaper == "designs/wallpapers/forest.png", "A declarative design must parse only its allowed appearance values")
assert(not AppStoreParser:_parseDesign("id=forest\ntitle=Forest\nhighlight=#A5D6A7\nbackground=#122219\nbutton=#2D6745\ntext=#EFF8E9\ndropdown=#183125\nwallpaper=../forest.png"), "A design must reject traversal paths in its optional wallpaper")
local appdock = {
    settings = { widgets = { clock = true, status = true, reading_hint = true, store = {}, store_order = {} }, theme = { selected = "lavender", custom = {} }, design = { active_id = nil, installed = {} }, plugin_logos = {}, layout = { app_spacing = 12, logo_shape = "rounded", search_enabled = false }, store = { installed = {} }, workspace = { restore_enabled = false, session = nil }, accessibility = { text_scale = 1, high_contrast = false }, dapp_permissions = {}, widget_generator = { items = {}, next_id = 0 }, setup_assistant = { offered_version = "", completed_version = "" }, beta = { plugin_dapp_host = false, black_borders = false, keep_wallpaper_original_in_night = false, manual_app_spacing = false, plugin_custom_logos = false }, simple_mode = { homescreen = false, quick_settings = false, focus_apps = false }, quick_settings = { tiles = { "wifi", "night", "refresh", "edit", "sleep", "power_saving" } }, notifications = { items = {} }, power_saving = false },
    toggleWidget = function(self, id) self.settings.widgets[id] = not self.settings.widgets[id] end,
    showHome = function(_, skip_lock) log.home = (log.home or 0) + 1; log.last_home_skip_lock = skip_lock end,
    showManager = function() log.manager = (log.manager or 0) + 1 end,
    _saveSettings = function(self) log.store_saved = (log.store_saved or 0) + 1 end,
    notify = function(_, payload) log.plugin_notification = payload; return true, payload end,
    getDAppPermissions = function(self, id)
        local permissions = self.settings.dapp_permissions[id] or {}
        return { background = permissions.background == true, autostart = permissions.autostart == true }
    end,
    getPinnedApps = function() return { { id = "dapp:first", title = "First App" }, { id = "dapp:second", title = "Second App" } } end,
    seedDefaults = function() end,
    getStoreWidgets = function() return { { widget_id = "quote_widget", title = "Quote Widget" }, { widget_id = "weather_widget", title = "Weather Widget" } } end,
    isStoreWidgetEnabled = function() return true end,
    isSimpleModeEnabled = function(self, option) return self.settings.simple_mode[option] == true end,
    isExpressiveUiEnabled = function(self)
        return not self:isSimpleModeEnabled("homescreen") and not self:isSimpleModeEnabled("quick_settings") and not self:isSimpleModeEnabled("focus_apps")
    end,
    setSimpleModeOption = function(self, option, enabled) self.settings.simple_mode[option] = enabled == true; self:_saveSettings(); return true end,
    getQuickSettingsTiles = function(self) return self:isSimpleModeEnabled("quick_settings") and { "wifi", "night", "power_saving" } or self.settings.quick_settings.tiles end,
    getNotifications = function() return {} end,
    getUnreadNotificationCount = function() return 0 end,
    movePinned = function() log.moved_app = true; return true end,
    moveStoreWidget = function() log.moved_widget = true; return true end,
    setTheme = function(self, id) self.settings.theme = self.settings.theme or { custom = {} }; self.settings.theme.selected = id; return true end,
    setAccessibility = function(self, changes)
        if changes.text_scale ~= nil then self.settings.accessibility.text_scale = changes.text_scale end
        if changes.high_contrast ~= nil then self.settings.accessibility.high_contrast = changes.high_contrast == true end
        self:_saveSettings()
        return true
    end,
    setWorkspaceRestoreEnabled = function(self, enabled)
        self.settings.workspace.restore_enabled = enabled == true
        if not enabled then self.settings.workspace.session = nil end
        self:_saveSettings()
        return true
    end,
    completeSetupAssistant = function(self)
        self.settings.setup_assistant.offered_version = "6.0.6"
        self.settings.setup_assistant.completed_version = "6.0.6"
        self:_saveSettings()
    end,
    setLauncherLayout = function(self, changes) for key, value in pairs(changes or {}) do self.settings.layout[key] = value end; self:_saveSettings(); return true end,
    setBetaOption = function(self, key, enabled) self.settings.beta[key] = enabled == true; self:_saveSettings(); return true end,
    getPluginApps = function(self) return { { id = "plugin:text_editor", title = "Text editor", custom_logo_path = self.settings.plugin_logos["plugin:text_editor"] } } end,
    setPluginLogo = function(self, app_id, path)
        if self.settings.beta.plugin_custom_logos ~= true or app_id ~= "plugin:text_editor" then return false end
        self.settings.plugin_logos[app_id] = path or nil; self:_saveSettings(); return true
    end,
    createCustomTheme = function(self, title, hex)
        self.settings.theme = self.settings.theme or { custom = {} }
        self.settings.theme.custom = self.settings.theme.custom or {}
        self.settings.theme.custom.custom_test = { title = title, primary = hex }
        self.settings.theme.selected = "custom_test"
        return "custom_test"
    end,
    getActiveDesign = function(self) return Theme.getActiveDesign(self.settings) end,
    getStoreDesignBySource = function(self, source_path)
        for id, design in pairs(self.settings.design.installed) do
            if design.source_path == source_path then return design, id end
        end
        return nil, nil
    end,
    setStoreDesignActive = function(self, id) self.settings.design.active_id = id; self:_saveSettings(); return true end,
    uninstallStoreDesign = function(self, id) self.settings.design.installed[id] = nil; if self.settings.design.active_id == id then self.settings.design.active_id = nil end; self:_saveSettings(); return true end,
    ui = {
        showFileManager = function(_, file) log.file_manager_file = file or true end,
        document = { file = "/books/example.epub" },
    },
}
appdock.settings.design.installed.galaxy = {
    id = "galaxy", title = "Galaxy", version = "1.0.0", highlight = "#A98BFF", background = "#111126",
    button = "#282653", text = "#F8F7FF", dropdown = "#181634", button_style = "3d", logo_shape = "circle",
    source_path = "designs/galaxy.appdock-design", wallpaper_file = "/tmp/galaxy.png",
}
appdock.settings.design.active_id = "galaxy"
local active_design = appdock:getActiveDesign()
assert(active_design and active_design.id == "galaxy" and active_design.wallpaper_file == "/tmp/galaxy.png", "Active designs must retain their validated local wallpaper record")
assert(Theme.getAppLogoShape(appdock) == "circle" and Theme.getPalette(appdock).primary_hex == "#A98BFF", "An active design must override the launcher logo form and highlight color")
assert(Theme.getButtonFrameStyle(appdock, 48, 12).bordersize == 1, "The Galaxy design must select the visible 3D button frame")
local manager = DAppManager:new(appdock)
appdock.getDAppManager = function() return manager end
appdock.getStoreWidgets = function()
    local function buildWidget(_, context) return WidgetContainer:new{ dimen = context.dimen } end
    return {
        { widget_id = "quote_widget", title = "Quote Widget", definition = { buildWidget = buildWidget }, instance = {} },
        { widget_id = "weather_widget", title = "Weather Widget", definition = { buildWidget = buildWidget }, instance = {} },
    }
end
assert(not appdock:setPluginLogo("plugin:text_editor", "/books/logo.png"), "Custom non-DApp plugin logos must remain unavailable until their Beta option is enabled")
assert(appdock:setBetaOption("plugin_custom_logos", true) and appdock:setPluginLogo("plugin:text_editor", "/books/logo.png") and appdock.settings.plugin_logos["plugin:text_editor"] == "/books/logo.png", "Enabled custom plugin logos must stay isolated to the selected non-DApp plugin")
appdock:setBetaOption("manual_app_spacing", true)
assert(appdock.settings.beta.manual_app_spacing and appdock:setLauncherLayout({ app_spacing = 21 }) and appdock.settings.layout.app_spacing == 21, "Manual spacing Beta must persist a bounded launcher spacing value through the layout contract")
local catalog = manager:getCatalogApps()
assert(#catalog == 6 and catalog[1].id and catalog[2].id and catalog[3].id and catalog[4].id and catalog[5].id and catalog[6].id, "DApp registry must expose all built-in catalog apps")
local store_saves_before_install = log.store_saved or 0
local store_fixture = "/tmp/appdock_store_fixture.lua"
local store_file = assert(io.open(store_fixture, "wb"))
store_file:write("return { id = 'quote_card', title = 'Quote Card', version = '1.0.0', subtitle = 'Stored test DApp', openFile = function(instance, path) instance.opened_file = path; return true end, backgroundTick = function(instance, context) instance.background_runs = (instance.background_runs or 0) + 1; instance.background_context = context.background end, onAutostart = function(instance, context) instance.autostart_runs = (instance.autostart_runs or 0) + 1; instance.autostart_context = context.background end, buildPane = function(instance, context) return { dimen = context.dimen } end }")
store_file:close()
local installed, store_id = manager:loadStoreDApp(store_fixture, "fixtures/quote_card.lua")
assert(installed and store_id == "quote_card" and manager.definitions.quote_card, "Confirmed store DApps must be added to the AppDock registry")
assert(appdock.settings.store.installed.quote_card and appdock.settings.store.installed.quote_card.version == "1.0.0" and log.store_saved == store_saves_before_install + 1, "Store DApps must persist their local installation record and version")
manager:runPermittedAutostarts()
manager:runPermittedBackgroundTasks()
assert(not manager.instances.quote_card, "Store DApp background hooks must not instantiate or run without explicit permissions")
appdock.settings.dapp_permissions.quote_card = { autostart = true, background = true }
manager:runPermittedAutostarts()
manager:runPermittedBackgroundTasks()
assert(manager.instances.quote_card.autostart_runs == 1 and manager.instances.quote_card.background_runs == 1 and manager.instances.quote_card.autostart_context and manager.instances.quote_card.background_context, "Only explicitly permitted Store DApp hooks must receive a local background context")
local permissions_ok, permissions_err = pcall(function()
    manager:showDAppPermissions(manager.instances.quote_card, { requestRebuild = function() end })
end)
assert(permissions_ok, "Opening the DApp-permissions control must not shadow gettext with a loop index: " .. tostring(permissions_err))
assert(log.shown[#log.shown].title == "DApp permissions", "The DApp-permissions control must list eligible Store DApps")
local known_definition, known_record = manager:getStoreDAppBySource("fixtures/quote_card.lua")
assert(known_definition and known_definition.id == "quote_card" and known_record.file == store_fixture, "Store DApps must be discoverable by their repository path")
local opened, open_err = manager:openDAppFile("quote_card", "/books/example.lua")
assert(opened and not open_err and manager.active_id == "quote_card" and manager.instances.quote_card.opened_file == "/books/example.lua", "Store DApps with an openFile contract must receive files and become active")
manager:closeDApp("quote_card")
local updated_fixture = "/tmp/appdock_store_update_fixture.lua"
local update_file = assert(io.open(updated_fixture, "wb"))
update_file:write("return { id = 'quote_card', title = 'Quote Card', version = '1.1.0', subtitle = 'Updated test DApp', buildPane = function(instance, context) return { dimen = context.dimen } end }")
update_file:close()
local replaced, replace_id = manager:loadStoreDApp(updated_fixture, "fixtures/quote_card.lua", false, "quote_card", true, store_fixture)
assert(replaced and replace_id == "quote_card" and manager.definitions.quote_card.version == "1.1.0", "A confirmed update must replace only the matching installed Store DApp")
assert(appdock.settings.store.installed.quote_card.file == store_fixture and appdock.settings.store.installed.quote_card.version == "1.1.0", "Updated Store metadata must retain the canonical local file and new version")
local removed = assert(manager:uninstallStoreDApp("quote_card"))
assert(removed and not manager.definitions.quote_card and not appdock.settings.store.installed.quote_card and not io.open(store_fixture, "rb"), "Uninstall must remove Store registry, persisted metadata, and the local Lua file")
os.remove(updated_fixture)

local workspace_fixture = "/tmp/appdock_workspace_fixture.lua"
local workspace_file = assert(io.open(workspace_fixture, "wb"))
workspace_file:write("return { id = 'workspace_card', title = 'Workspace Card', version = '1.0.0', workspace_restore = true, file_extensions = { 'note', 'MD' }, file_handler_title = 'Open note workspace', openFile = function(instance, path) instance.opened_file = path; return true end, serializeState = function() return { filter = 'today', page = 2 } end, restoreState = function(instance, state) instance.restored_filter = state.filter; instance.restored_page = state.page end, buildPane = function(instance, context) return { dimen = context.dimen } end } ")
workspace_file:close()
local workspace_installed, workspace_id = manager:loadStoreDApp(workspace_fixture, "fixtures/workspace_card.lua")
assert(workspace_installed and workspace_id == "workspace_card", "A Store DApp may opt in to the local workspace contract")
local note_handlers = manager:getFileHandlers("/books/today.note")
assert(#note_handlers == 1 and note_handlers[1].id == "workspace_card" and note_handlers[1].title == "Open note workspace", "Declared file extensions must be normalized and exposed through the central handler registry")
appdock.settings.workspace = { restore_enabled = true, session = nil }
manager:activate("workspace_card")
assert(manager:captureWorkspace() and appdock.settings.workspace.session.apps[1].id == "workspace_card" and appdock.settings.workspace.session.apps[1].state.filter == "today", "Workspace capture must store only the explicitly permitted DApp and its small local state")
local restored_manager = DAppManager:new(appdock)
assert(restored_manager:restoreWorkspace() and restored_manager.instances.workspace_card.restored_filter == "today" and restored_manager.instances.workspace_card.restored_page == 2, "Workspace restoration must run the optional local restore hook before rendering the permitted DApp")
appdock.settings.workspace.restore_enabled = false
assert(not manager:captureWorkspace(), "Disabled workspace restoration must not persist new session state")
assert(manager:closeDApp("workspace_card") and manager:uninstallStoreDApp("workspace_card"), "Workspace fixture cleanup must remove the temporary open DApp and its stored test file")

package.preload["document/documentregistry"] = function() return { hasProvider = function() return false end } end
package.preload["apps/filemanager/filemanagerutil"] = function() return { getHomeFolder = function() return "/tmp" end } end
package.preload["libs/libkoreader-lfs"] = function()
    return {
        dir = function()
            local returned = false
            return function()
                if returned then return nil end
                returned = true
                return "notes.md"
            end
        end,
        attributes = function() return { mode = "file", size = 16 } end,
    }
end
local FileBrowser = dofile(os.getenv("APPDOCK_FILEMANAGER_PATH") or (plugin_dir .. "appdock_filemanager.lua"))
local markdown_entries = assert(FileBrowser:new():_readEntries("/books"))
assert(#markdown_entries == 1 and markdown_entries[1].is_markup, "The AppDock Filebrowser must identify supported Markdown suffixes as MarkUP files")
local markup_open = {}
local markup_manager = {
    openDAppFile = function(_, id, path)
        markup_open.id, markup_open.path = id, path
        return true
    end,
}
FileBrowser:new():openMarkUPFile({}, { manager = markup_manager }, "/books/notes.md")
assert(markup_open.id == "markup" and markup_open.path == "/books/notes.md", "The AppDock Filebrowser must open Markdown files through the MarkUP Store DApp")
local guarded_instance = { definition = { canClose = function() return false, "Save first" end } }
manager.instances.dirty_document = guarded_instance
table.insert(manager.open_order, "dirty_document")
assert(manager:closeDApp("dirty_document") == false and manager.instances.dirty_document == guarded_instance, "A DApp with unsaved changes must be able to refuse closing and remain open")
manager.instances.dirty_document = nil
for order_index, open_id in ipairs(manager.open_order) do
    if open_id == "dirty_document" then table.remove(manager.open_order, order_index); break end
end

local widget_fixture = "/tmp/appdock_store_widget_fixture.lua"
local widget_file = assert(io.open(widget_fixture, "wb"))
widget_file:write("return { id = 'quote_widget', title = 'Quote Widget', version = '1.0.0', subtitle = 'Rotating test widget', buildWidget = function(instance, context) return { dimen = context.dimen } end }")
widget_file:close()
local widget_installed, widget_id = manager:loadStoreWidget(widget_fixture, "quote_widget.lua")
assert(widget_installed and widget_id == "quote_widget" and manager.widget_definitions.quote_widget, "Store widgets must load through their separate registry")
assert(appdock.settings.store.installed.quote_widget.kind == "widget" and appdock.settings.store.installed.quote_widget.version == "1.0.0", "Store widgets must persist their type and version")
local widgets = manager:getStoreWidgets()
assert(#widgets == 1 and widgets[1].widget_id == "quote_widget" and widgets[1].definition.buildWidget, "Installed Store widgets must be exposed to the homescreen")
appdock.settings.widgets.store = {}
local widget_removed = assert(manager:uninstallStoreWidget("quote_widget"))
assert(widget_removed and not manager.widget_definitions.quote_widget and not appdock.settings.store.installed.quote_widget and not io.open(widget_fixture, "rb"), "Widget uninstall must remove registry, metadata, and Lua file")

local generated_id, generated_spec = manager:createGeneratedWidget({ title = "Morning panel", text = "Read calmly", show_time = true, show_battery = true })
assert(generated_id == "generated_widget_1" and generated_spec.title == "Morning panel" and appdock.settings.widgets.store[generated_id], "WidgetGenerator must persist a bounded, enabled declarative widget without creating Lua source")
local generated_widgets = manager:getStoreWidgets()
assert(#generated_widgets == 1 and generated_widgets[1].widget_id == generated_id and generated_widgets[1].kind == "generated_widget", "Generated widgets must enter the same homescreen widget registry as Store widgets")
local generated_pane = generated_widgets[1].definition.buildWidget(generated_widgets[1].instance, { dimen = { w = 360, h = 96 } })
assert(generated_pane and generated_pane.dimen.w == 360, "Generated widgets must render local text and permitted system fields through the homescreen contract")
local update_ok, updated_generated = manager:updateGeneratedWidget(generated_id, { title = "Evening panel", text = "Rest", show_date = true })
assert(update_ok and updated_generated.title == "Evening panel" and not updated_generated.show_time and updated_generated.show_date, "WidgetGenerator updates must replace only the declarative configuration")
assert(manager:removeGeneratedWidget(generated_id) and not appdock.settings.widget_generator.items[generated_id] and appdock.settings.widgets.store[generated_id] == nil, "Removing a generated widget must clear its local registry, visibility state, and ordering data")

package.preload["bit"] = function()
    local Bit = {}
    function Bit.band(a, b) local result, place = 0, 1; while a > 0 or b > 0 do if a % 2 == 1 and b % 2 == 1 then result = result + place end; a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2 end; return result end
    function Bit.bor(a, b) local result, place = 0, 1; while a > 0 or b > 0 do if a % 2 == 1 or b % 2 == 1 then result = result + place end; a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2 end; return result end
    function Bit.rshift(a, n) return math.floor(a / 2 ^ n) end
    function Bit.lshift(a, n) return a * 2 ^ n end
    return Bit
end
local bwr_store_file = "/home/ubuntu/dapps-store-repo/bwr_video.lua"
local bwr_installed, bwr_id = manager:loadStoreDApp(bwr_store_file, "bwr_video.lua")
assert(bwr_installed and bwr_id == "bwr_video" and manager.definitions.bwr_video, "BWR Video must load through the actual Store DApp registration path")
manager:activate("bwr_video")
local bwr_instance = manager.instances.bwr_video
assert(bwr_instance and bwr_instance.pane and bwr_instance.pane.dimen, "BWR Video must build through the actual AppDock host without a Player field")
manager:closeDApp("bwr_video")

manager:activate("analog_clock", "home")
assert(manager.active_id == "analog_clock" and #manager:getOpenApps() == 1, "Activating a DApp must retain it in the open-app list")
local host_chrome = manager.active_host[1]
manager.showQuickSettingsFromHost = function(_, host) log.quick_settings_host = host end
local host_quick_access
for _, child in ipairs(host_chrome) do if child.symbol == "⌄" then host_quick_access = child; break end end
assert(host_quick_access and host_quick_access.overlap_offset[2] < 52, "Each DApp host must expose a compact appbar control-center entry")
host_quick_access:onTapDAppAction()
assert(log.quick_settings_host == manager.active_host, "The DApp-host control-center entry must open Quick Settings without leaving a DApp")
local home_chip, recents_chip, close_chip
for _, child in ipairs(host_chrome) do
    if child.symbol == "⌂" then home_chip = child end
    if child.symbol == "□" then recents_chip = child end
    if child.symbol == "×" then close_chip = child end
end
assert(manager.active_host.chrome_layout and manager.active_host.chrome_layout.expressive and manager.active_host.chrome_layout.navigation_height == 58 and manager.active_host.chrome_layout.has_navigation_pill, "Normal AppDock mode must use the larger expressive app bar and lower navigation pill")
assert(home_chip.overlap_offset[2] >= 742 and recents_chip.overlap_offset[2] == home_chip.overlap_offset[2] and close_chip.overlap_offset[2] == home_chip.overlap_offset[2], "Home, open-apps and close chips must share the lower navigation row")
assert(home_chip.overlap_offset[1] < recents_chip.overlap_offset[1] and recents_chip.overlap_offset[1] < close_chip.overlap_offset[1] and math.abs((recents_chip.overlap_offset[1] + math.floor(recents_chip.width / 2)) - 300) <= 1, "System actions must be centered and ordered Home, Open Apps, Close")
local home_closed = false
for _, closed_widget in ipairs(log.closed) do if closed_widget == "home" then home_closed = true; break end end
assert(home_closed, "DApp activation must close the homescreen host")
local clock_instance = manager.instances.analog_clock
assert(clock_instance.pane and clock_instance.pane.dimen, "Analog Clock must build a pane within its assigned context")

manager:showRecents()
assert(#manager:getOpenApps() == 1, "Opening recents must not close a DApp")
manager:activate("settings")
assert(manager.active_id == "settings" and #manager:getOpenApps() == 2, "Settings must be a separately tracked DApp")
local settings_instance = manager.instances.settings
assert(settings_instance.pane and settings_instance.pane.dimen, "Settings must build a pane within its assigned context")
assert(settings_instance.pane.settings_layout.category == "network" and settings_instance.pane.settings_layout.row_count == 1, "Bluetooth must stay hidden on unsupported hardware")
manager:toggleWifiFromSettings({ requestRebuild = function() log.wifi_rebuilds = (log.wifi_rebuilds or 0) + 1 end })
assert(wifi_on and log.wifi_rebuilds == 1, "Wi-Fi settings action must toggle the native network state")
local bluetooth_actions = 0
Device.isKobo = function() return true end
Device.model = "Kobo_monza"
appdock.ui.Bluetooth = {
    addToMainMenu = function(_, menu_items)
        menu_items.bluetooth = { sub_item_table = { { text = "Turn Bluetooth on", callback = function() bluetooth_actions = bluetooth_actions + 1 end } } }
    end,
}
manager:activate("settings")
assert(settings_instance.pane.settings_layout.category == "network" and settings_instance.pane.settings_layout.row_count == 2, "Bluetooth must appear only on Kobo Libra Colour")
manager:showBluetoothSettings()
local bluetooth_dialog = log.shown[#log.shown]
assert(bluetooth_dialog.title:find("Bluetooth · Kobo Libra Colour", 1, true) and bluetooth_dialog.buttons[1][1].text == "Turn Bluetooth on", "Kobo Libra Colour Bluetooth must use the installed plugin menu")
bluetooth_dialog.buttons[1][1].callback()
assert(bluetooth_actions == 1, "AppDock must delegate Bluetooth actions to the installed plugin instead of issuing driver commands")
appdock.ui.Bluetooth = nil
local shown_before_missing_plugin = #log.shown
manager:showBluetoothSettings()
assert(#log.shown == shown_before_missing_plugin + 1, "Kobo Libra Colour without a Bluetooth plugin must receive an availability notice")
local storage_root = "/tmp/appdock_test_data"
os.execute("mkdir -p " .. storage_root .. "/books")
local storage_fixture = assert(io.open(storage_root .. "/books/sample.epub", "wb"))
storage_fixture:write(string.rep("x", 1536))
storage_fixture:close()
settings_instance.settings_category = "storage"
manager:activate("settings")
local function findStorageSegments(node)
    if type(node) ~= "table" then return nil end
    if type(node.segments) == "table" then return node.segments end
    for child_index, child in ipairs(node) do
        local found = findStorageSegments(child)
        if found then return found end
    end
    return nil
end
local storage_segments = findStorageSegments(settings_instance.pane)
assert(storage_segments and storage_segments[1] and storage_segments[1].bytes >= 1536 and storage_segments[1].title == "books", "Storage breakdown must retain LuaFileSystem iterator state and report readable local files")
assert(settings_instance.pane.settings_layout.integrity and settings_instance.pane.settings_layout.integrity.missing == 0, "Storage settings must expose a local read-only integrity status without marking valid Store records as missing")
settings_instance.settings_category = "display"
manager:activate("settings")
assert(settings_instance.pane.settings_layout.category == "display" and settings_instance.pane.settings_layout.row_count == 10, "Display category must expose text and contrast controls alongside themes, launcher, wallpaper and beta settings")
assert(appdock:setAccessibility({ text_scale = 1.3, high_contrast = true }) and Theme.getPalette(appdock).high_contrast, "Accessibility settings must persist a bounded text scale and activate the high-contrast palette")
manager:showFrontlightSettings()
assert(log.events[#log.events] == "ShowFlDialog", "Brightness and warmth must use KOReader's native frontlight dialog")
manager:toggleColorTheme({ requestRebuild = function() log.settings_rebuilds = (log.settings_rebuilds or 0) + 1 end })
assert(log.events[#log.events] == "ToggleNightMode" and log.settings_rebuilds == 1, "Color themes must trigger KOReader's night-mode event")
settings_instance.settings_category = "other"
manager:activate("settings")
assert(settings_instance.pane.settings_layout.category == "other" and settings_instance.pane.settings_layout.row_count == 10, "Other category must include the setup wizard alongside the opt-in local workspace, lockscreen, control center, permissions, arrangement and startup")
assert(settings_instance.pane.settings_layout.text_scale == 1.3 and settings_instance.pane.settings_layout.high_contrast and not settings_instance.pane.settings_layout.workspace_enabled, "Settings metadata must expose the applied local accessibility and workspace state")
local setup_dialogs_before = #log.shown
manager:showSetupAssistant(settings_instance, { requestRebuild = function() log.setup_rebuilds = (log.setup_rebuilds or 0) + 1 end }, false)
local setup_start = log.shown[#log.shown]
assert(#log.shown == setup_dialogs_before + 1 and setup_start.title == "AppDock setup wizard", "Settings must expose an always-available manual setup assistant")
setup_start.buttons[1][1].callback()
local appearance_step = log.shown[#log.shown]
assert(appearance_step.title:find("Setup 1/3", 1, true), "The setup assistant must start with an explicit appearance choice")
appearance_step.buttons[3][1].callback()
local search_step = log.shown[#log.shown]
assert(search_step.title:find("Setup 2/3", 1, true), "Skipping appearance must retain current Simple Mode and advance safely")
search_step.buttons[3][1].callback()
local workspace_step = log.shown[#log.shown]
assert(workspace_step.title:find("Setup 3/3", 1, true), "Skipping app search must advance to the local workspace choice")
workspace_step.buttons[3][1].callback()
assert(appdock.settings.setup_assistant.completed_version == "6.0.6" and not appdock:isSimpleModeEnabled("homescreen") and (log.setup_rebuilds or 0) == 1, "Finishing without changes must record setup locally and leave Simple Mode untouched")
assert(appdock:setWorkspaceRestoreEnabled(true), "Local workspace restoration must be explicitly enabled through a persisted setting")
manager:activate("settings")
assert(manager.instances.settings.pane.settings_layout.workspace_enabled, "Settings must immediately expose the opt-in local workspace state")
manager:showArrangementEditor(settings_instance, { requestRebuild = function() log.arrangement_rebuilds = (log.arrangement_rebuilds or 0) + 1 end })
local arrangement_dialog = log.shown[#log.shown]
assert(arrangement_dialog.title == "Arrange apps & widgets" and arrangement_dialog.buttons[#arrangement_dialog.buttons][1].text == "Done", "Settings must open one compact arrangement dialog with a Done action")
assert(#arrangement_dialog.buttons >= 6, "Settings arrangement dialog must list apps and widgets")
settings_instance.settings_category = "simple"
manager:activate("settings")
assert(settings_instance.pane.settings_layout.category == "simple" and settings_instance.pane.settings_layout.row_count == 3, "Simple Mode must expose three independent settings switches")
assert(appdock:setSimpleModeOption("homescreen", true) and appdock:setSimpleModeOption("quick_settings", true) and appdock:setSimpleModeOption("focus_apps", true), "Simple Mode switches must be independently persisted")
local HomeScreen = dofile(plugin_dir .. "appdock_homescreen.lua")
local simple_home = HomeScreen:new{ appdock = appdock }
assert(simple_home.simple_layout and simple_home.simple_layout.columns == 4 and simple_home.simple_layout.rows == 3 and simple_home.simple_layout.app_count == 2, "Simple homescreen must contain only the visible apps in a 4×3 grid")
assert(not simple_home.normal_layout, "Simple homescreen must not create any normal-mode expressive layout metadata")
assert(not simple_home._widget_tick, "Simple homescreen must not schedule hidden widget refreshes")
local QuickSettings = dofile(plugin_dir .. "appdock_quicksettings.lua")
local simple_quick_settings = QuickSettings:new{ appdock = appdock, home = simple_home }
assert(simple_quick_settings.layout.simple_mode and simple_quick_settings.layout.tile_count == 3 and not simple_quick_settings.layout.show_notifications, "Simple quick settings must contain the three required tiles, brightness, and no notifications")
assert(not simple_quick_settings.layout.expressive and simple_quick_settings.sheet_height < 400, "Simple quick settings must retain its existing compact non-expressive layout")
appdock:setSimpleModeOption("homescreen", false)
appdock:setSimpleModeOption("quick_settings", false)
appdock:setSimpleModeOption("focus_apps", false)
local expressive_home = HomeScreen:new{ appdock = appdock }
assert(expressive_home.normal_layout and expressive_home.normal_layout.expressive and expressive_home.normal_layout.has_header_surface and expressive_home.normal_layout.has_app_dock_surface, "Normal homescreen must restore expressive Material surfaces only after Simple Mode is disabled")
local expressive_quick_settings = QuickSettings:new{ appdock = appdock, home = expressive_home }
assert(expressive_quick_settings.layout.expressive and not expressive_quick_settings.layout.simple_mode and expressive_quick_settings.sheet_height >= 0, "Normal quick settings must use expressive layout only outside Simple Mode")

local recents = {}
manager:showDAppActions("analog_clock", recents)
local actions = log.shown[#log.shown]
assert(actions.title == "Analog Clock" and actions.buttons[1][1].text == "Splitscreen", "Long press must first expose the Splitscreen action")
actions.buttons[1][1].callback()
local picker = log.shown[#log.shown]
assert(picker.title == "Choose second app" and picker.buttons[1][1].text == "Settings", "Split selection must show the other open DApp")
picker.buttons[1][1].callback()
assert(manager.active_host and manager.active_host.split, "Selecting two open DApps must create a split-screen host")
assert(#manager.active_host.active_panes == 2, "Split screen must build two active DApp panes")
assert(clock_instance.in_split and settings_instance.in_split, "Both DApps must be marked as running in split screen")
assert(clock_instance.pane.dimen.h < 400 and settings_instance.pane.dimen.h < 400, "Each split DApp must receive a reduced pane height")
local split_host = manager.active_host
local split_divider
for _, child in ipairs(split_host[1]) do
    if child.width == 600 and child.height == 8 then split_divider = child; break end
end
assert(split_divider and split_host.ges_events.PanSplitHost and split_host.ges_events.PanReleaseSplitHost and split_host._split_touch_range and split_host._split_touch_range.h > 8, "Split screen must expose a broad absolute host touch zone instead of a divider-owned gesture")
local first_height_before_drag = clock_instance.pane.dimen.h
local chrome_before_drag = split_host[1]
local fast_before_drag = #log.dirties
local yields_before_drag = log.epdc_yields or 0
assert(split_host:onPanSplitHost(nil, { pos = { y = 560 } }), "Dragging the split divider downward through the host must be handled")
assert(split_host._split_last_y == 560, "Host split dragging must retain the latest touch position for the release fallback")
assert(split_host[1] ~= chrome_before_drag and split_host.split_ratio > .5 and clock_instance.pane.dimen.h > first_height_before_drag, "A downward pan must visibly rebuild the split panes during the gesture")
assert(#log.dirties > fast_before_drag and log.dirties[#log.dirties].kind == "fast" and (log.epdc_yields or 0) > yields_before_drag, "Live split resizing must request a fast E-Ink refresh and yield to the controller")
local chrome_after_down = split_host[1]
assert(split_host:onPanSplitHost(nil, { pos = { y = 360 } }), "Dragging the same divider back upward through the host must be handled")
assert(split_host._split_last_y == 360 and split_host[1] ~= chrome_after_down and split_host.split_ratio < .5, "An upward pan after a downward pan must remain bound to the same absolute host gesture surface")
assert(clock_instance.visible and settings_instance.visible and clock_instance.in_split and settings_instance.in_split and #split_host.active_panes == 2, "Resizing split panes must keep both DApps active without leaving split screen")
local saves_before_split_release = log.store_saved or 0
assert(split_host:onPanReleaseSplitHost(nil, {}), "Releasing the split divider without a final position must use the previous host pan position")
assert(clock_instance.pane.dimen.h < first_height_before_drag and appdock.settings.layout.split_ratio < .5 and (log.store_saved or 0) == saves_before_split_release + 1, "Releasing the divider must rebuild and persist the final upward split position")
local split_context = manager:_newContext(manager.active_host, clock_instance, clock_instance.pane.dimen)
assert(split_context.scale == split_context.ui_scale and split_context.scale < 1 and split_context.scale >= 0.45, "Split DApps must receive a bounded relative UI scale")
assert(split_context.px(40) < 40 and split_context.px(40) >= 1, "Relative DApp pixels must shrink safely in split screen")
local half_pane = split_context.relative(0.5, 0.5)
assert(half_pane.w == math.floor(clock_instance.pane.dimen.w * 0.5 + 0.5) and half_pane.h == math.floor(clock_instance.pane.dimen.h * 0.5 + 0.5), "Relative DApp geometry must use the assigned local pane")

manager:showRecentsFromHost(manager.active_host)
assert(#manager:getOpenApps() == 2 and not clock_instance.visible and not settings_instance.visible, "Leaving split screen must retain both DApps in recents")
manager:activate("help")
local help_instance = manager.instances.help
assert(help_instance and help_instance.pane and help_instance.pane.dimen, "Help must build an offline DApp pane")
assert(help_instance.pane.help_layout and help_instance.pane.help_layout.language == "en", "Help must inherit English as the current default language without changing KOReader UI language")
local help_test = manager.help._test
assert(#help_test.sections >= 14, "Help must cover the complete current AppDock feature set in separate chapters")
assert(#help_test.search("de", "Benachrichtigungen") >= 1 and #help_test.search("en", "Gmail") >= 1, "Help search must work locally in both languages")
assert(#help_test.normalizeQuery(string.rep("x", 120)) == 80, "Help search input must be bounded")
assert(help_test.render("de", "Inbox"):find("Lokale Benachrichtigungen", 1, true), "German help must render the notification chapter")
assert(help_test.render("en", "Gmail"):find("Gmail Notifications", 1, true), "English help must render Gmail guidance")
manager:closeDApp("help")
manager:activate("web_browser")
local browser_instance = manager.instances.web_browser
assert(browser_instance and browser_instance.pane and browser_instance.pane.dimen, "Web Browser must build a DApp pane")
manager:closeDApp("web_browser")
manager:activate("file_manager")
local file_manager_instance = manager.instances.file_manager
assert(file_manager_instance and file_manager_instance.pane and file_manager_instance.pane.dimen, "File Manager must build a DApp pane")
assert(file_manager_instance and file_manager_instance.pane and file_manager_instance.pane.dimen, "File Manager must remain a self-contained DApp pane")
manager:closeDApp("file_manager")
manager:closeDApp("analog_clock")
assert(#manager:getOpenApps() == 1 and manager.instances.analog_clock == nil, "Closing a DApp must remove it from recents")
local hosted_action_calls = 0
local hosted_pane_builds = 0
local hosted_host_context
local hosted_plugin = {
    plugin_name = "hosted_test_plugin",
    title = "Hosted Test Plugin",
    instance = {},
    buildAppDockPane = function(_, context)
        hosted_pane_builds = hosted_pane_builds + 1
        hosted_host_context = context
        return WidgetContainer:new{ dimen = context.dimen }
    end,
    actions = {
        {
            title = "Send AppDock notification",
            item = { callback = function()
                hosted_action_calls = hosted_action_calls + 1
                return true
            end },
        },
    },
}
assert(manager:activatePlugin(hosted_plugin), "The Plugin-in-DApp beta must create a dedicated AppDock host session for a published plugin action")
local hosted_id = "plugin_host:hosted_test_plugin"
local hosted_instance = manager.instances[hosted_id]
assert(hosted_instance and hosted_instance.pane and hosted_pane_builds == 1 and hosted_instance.pane.plugin_host_layout and hosted_instance.pane.plugin_host_layout.using_plugin_pane and hosted_instance.pane.plugin_host_layout.can_split == false, "A cooperating plugin must render its local pane inside the explicit non-splittable AppDock host")
assert(hosted_action_calls == 1, "A plugin with one published main-menu action must start it automatically after the AppDock host is shown")
local hosted_context = manager:_newContext(manager.active_host, hosted_instance, hosted_instance.pane.dimen)
assert(manager:_invokePluginHostItem(hosted_instance, hosted_context, hosted_plugin.actions[1].item) and hosted_action_calls == 2, "Plugin host actions must preserve the existing no-argument plugin callback contract")
assert(hosted_host_context and hosted_host_context.notify({ title = "Plugin result", message = "Completed locally" }), "A cooperating plugin pane must receive an explicit local AppDock context")
assert(log.plugin_notification and log.plugin_notification.title == "Plugin result" and log.plugin_notification.source == "Hosted Test Plugin", "Plugin host context notifications must be routed through AppDock notifications with a truthful source")
local hosted_open
for open_index, open_app in ipairs(manager:getOpenApps()) do if open_app.id == hosted_id then hosted_open = open_app; break end end
assert(hosted_open and hosted_open.is_plugin_host and hosted_open.can_split == false and hosted_open.subtitle == "Plugin host · Beta", "Open Apps must identify beta plugin hosts and their split-screen limit")
manager:showDAppActions(hosted_id)
local hosted_actions = log.shown[#log.shown]
assert(hosted_actions.buttons[1][1].text == "Plugin host beta · Split screen unavailable", "Plugin host long-press actions must not offer split screen")
manager:startSplit(hosted_id, "settings")
assert(log.plugin_notification and log.plugin_notification.title == "Plugin host beta" and manager.active_host and manager.active_host.dapp_id == hosted_id, "Split creation must defensively reject a plugin host even if called directly through an AppDock notification")
manager:closeDApp(hosted_id)
assert(manager.instances[hosted_id] == nil and manager.plugin_definitions[hosted_id] == nil, "Closing a plugin host must clear its transient AppDock session definition")
local fallback_plugin = {
    plugin_name = "fallback_test_plugin",
    title = "Fallback Test Plugin",
    actions = { { title = "Legacy action", item = { callback = function() return true end } } },
}
assert(manager:activatePlugin(fallback_plugin), "A normal plugin without a pane contract must still receive the AppDock beta action host")
local fallback_instance = manager.instances["plugin_host:fallback_test_plugin"]
assert(fallback_instance and fallback_instance.pane and fallback_instance.pane.plugin_host_layout and not fallback_instance.pane.plugin_host_layout.using_plugin_pane and fallback_instance.pane.plugin_host_layout.action_count == 1 and fallback_instance.pane.plugin_host_layout.can_split == false, "The fallback plugin host must retain its local AppDock menu and the split-screen ban")
local texteditor_received_adapter = false
local texteditor_like_item = {
    callback = function(touchmenu_instance)
        texteditor_received_adapter = type(touchmenu_instance) == "table" and type(touchmenu_instance.updateItems) == "function"
        touchmenu_instance.item_table = { { text = "New file", callback = function() return true end } }
        touchmenu_instance.page = 1
        touchmenu_instance:updateItems()
    end,
}
local texteditor_context = manager:_newContext(manager.active_host, fallback_instance, fallback_instance.pane.dimen)
local texteditor_shown_before = #log.shown
assert(manager:_invokePluginHostItem(fallback_instance, texteditor_context, texteditor_like_item) and texteditor_received_adapter, "Text editor-style callbacks must receive the compatible TouchMenu adapter")
assert(#log.shown == texteditor_shown_before and fallback_instance.plugin_overlay and fallback_instance.plugin_overlay.kind == "actions" and fallback_instance.plugin_overlay.actions[1].text == "New file", "Text editor-style dynamic menus must rebuild as AppDock overlays instead of raw plugin dialogs")
local appstore_launches = 0
local appstore_like_items = { { text = "App Store", callback = function() appstore_launches = appstore_launches + 1 end } }
manager:_showPluginHostMenu(fallback_instance, texteditor_context, appstore_like_items, "App Store")
local appstore_host_overlay = fallback_instance.plugin_overlay
assert(appstore_host_overlay and appstore_host_overlay.title == "App Store" and manager:_invokePluginOverlayAction(fallback_instance, texteditor_context, appstore_host_overlay.actions[1]), "AppStore-style no-argument callbacks must run from the AppDock overlay")
assert(appstore_launches == 1 and not fallback_instance.plugin_overlay, "AppStore-style callbacks must dismiss their AppDock overlay without opening a raw plugin dialog")
local appstore_direct_plugin = { plugin_name = "appstore_direct", title = "App Store", actions = { { title = "App Store", item = appstore_like_items[1] } } }
assert(manager:activatePlugin(appstore_direct_plugin) and appstore_launches == 2, "AppStore-style single launch actions must run immediately after their AppDock host opens")
manager:closeDApp("plugin_host:appstore_direct")
local texteditor_direct_plugin = {
    plugin_name = "texteditor_direct",
    title = "Text editor",
    actions = {
        {
            title = "Text editor",
            item = { sub_item_table_func = function()
                return { { text = "New file", callback = function() return true end } }
            end },
        },
    },
}
local texteditor_direct_shown_before = #log.shown
assert(manager:activatePlugin(texteditor_direct_plugin), "Text editor-style dynamic plugins must activate through the AppDock host")
local texteditor_direct_instance = manager.instances["plugin_host:texteditor_direct"]
assert(#log.shown == texteditor_direct_shown_before + 1 and texteditor_direct_instance and texteditor_direct_instance.plugin_overlay and texteditor_direct_instance.plugin_overlay.title == "Text editor" and texteditor_direct_instance.plugin_overlay.actions[1].text == "New file", "Text editor-style single menu actions must open their dynamic first submenu as an AppDock overlay")
manager:closeDApp("plugin_host:texteditor_direct")

local raw_plugin_dialog_calls = 0
local raw_dialog = {
    title = "Legacy plugin dialog",
    text = "Plugin asks for confirmation",
    buttons = { { { text = "Continue", is_enter_default = true, callback = function() raw_plugin_dialog_calls = raw_plugin_dialog_calls + 1 end } } },
}
local raw_dialog_shown_before = #log.shown
assert(manager:_invokePluginHostItem(fallback_instance, texteditor_context, { callback = function() UIManager:show(raw_dialog) end }), "A plugin callback that opens a standard dialog must remain launchable")
assert(#log.shown == raw_dialog_shown_before and fallback_instance.plugin_overlay and fallback_instance.plugin_overlay.kind == "actions" and fallback_instance.plugin_overlay.widget == raw_dialog, "Standard plugin dialogs must be captured as AppDock overlays")
assert(manager:_invokePluginOverlayAction(fallback_instance, texteditor_context, fallback_instance.plugin_overlay.actions[1]) and raw_plugin_dialog_calls == 1, "Captured plugin dialog actions must retain their callback behavior")

local raw_message = { title = "Legacy plugin message", text = "A bounded message" }
assert(manager:_invokePluginHostItem(fallback_instance, texteditor_context, { callback = function() UIManager:show(raw_message) end }), "A plugin callback that opens an information message must remain launchable")
assert(fallback_instance.plugin_overlay and fallback_instance.plugin_overlay.kind == "message" and fallback_instance.plugin_overlay.widget == raw_message, "Plugin information messages must be captured as AppDock message overlays")
manager:_dismissPluginOverlay(fallback_instance, texteditor_context, raw_message)

local raw_input = {
    title = "Legacy plugin input",
    input = "initial value",
    input_hint = "Enter a value",
    buttons = { { { text = "Save", callback = function() end } } },
    getInputText = function(self) return self.input end,
    setInputText = function(self, value) self.input = value end,
    onShowKeyboard = function() raw_plugin_dialog_calls = raw_plugin_dialog_calls + 100 end,
}
assert(manager:_invokePluginHostItem(fallback_instance, texteditor_context, { callback = function() UIManager:show(raw_input); raw_input:onShowKeyboard() end }), "A plugin callback that opens an input dialog must remain launchable")
assert(fallback_instance.plugin_overlay and fallback_instance.plugin_overlay.kind == "input" and raw_plugin_dialog_calls == 1, "Plugin input dialogs must be captured before their native keyboard is opened")
manager:_dismissPluginOverlay(fallback_instance, texteditor_context, raw_input)
manager:closeDApp("plugin_host:fallback_test_plugin")
manager:showHomeFromHost({})
assert(log.last_home_skip_lock == true, "Normal DApp host navigation must return home without incorrectly re-locking AppDock")
print("AppDock DApp test: OK")
