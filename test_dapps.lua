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
-- Walks a widget tree the way the renderer does: children live either in the
-- container itself or, for Layout.FixedStack, in its entries list.
local function walk_tree(widget, visit, depth)
    depth = depth or 0
    if depth > 12 or type(widget) ~= "table" then return end
    visit(widget)
    for _, child in ipairs(widget) do walk_tree(child, visit, depth + 1) end
    if type(widget.entries) == "table" then
        for _, entry in ipairs(widget.entries) do
            if type(entry) == "table" and entry.widget then walk_tree(entry.widget, visit, depth + 1) end
        end
    end
end
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
    function Logo:init() self.dimen = { w = self.size or 0, h = self.size or 0 } end
    function Logo.availableKinds() return { "app_store", "palette" } end
    return Logo
end
package.preload["appdock_keyboard"] = function() return WidgetContainer end
package.preload["appdock_motion"] = function()
    return {
        run = function(target, frames, _, draw, done, region)
            log.motion = log.motion or {}
            table.insert(log.motion, { target = target, frames = frames, region = region })
            for frame = 1, frames or 1 do
                if draw then draw(frame, frames or 1) end
            end
            if done then done() end
        end,
    }
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
                beginQuery = function(_, instance, query)
                    log.browser_query = query
                end,
                runPendingSearch = function()
                    log.browser_pending_runs = (log.browser_pending_runs or 0) + 1
                    return true
                end,
            }
        end,
    }
end
package.preload["ui/network/manager"] = function()
    return {
        isWifiOn = function() return wifi_on end,
        enableWifi = function(_, callback) wifi_on = true; callback(); return true end,
        disableWifi = function(_, callback) wifi_on = false; callback(); return true end,
    }
end
-- The YouTube DApp drives external tools and the BWR1 encoder. Its own test
-- file covers those modules; here it only has to satisfy the DApp contract.
package.preload["appdock_youtube"] = function()
    return {
        new = function()
            return {
                buildPane = function(_, instance, context)
                    return WidgetContainer:new{ dimen = { w = context.dimen.w, h = context.dimen.h } }
                end,
                player = { stop = function() log.youtube_player_stops = (log.youtube_player_stops or 0) + 1 end },
            }
        end,
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
package.preload["ui/widget/container/scrollablecontainer"] = function()
    WidgetContainer.getScrollbarWidth = function() return 8 end
    return WidgetContainer
end
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
package.preload["pluginloader"] = function() return { loadPlugins = function() return {} end } end
local AppDockClass = dofile(plugin_dir .. "main.lua")
local pinned_save_count = 0
local pinned_order_test = {
    settings = { pinned_apps = { "dapp:first", "dapp:second", "dapp:third" } },
    _saveSettings = function() pinned_save_count = pinned_save_count + 1 end,
}
assert(AppDockClass.movePinned(pinned_order_test, "dapp:third", -2), "The real AppDock:movePinned method must reorder pinned apps without a nil AppDockOrder error")
assert(pinned_order_test.settings.pinned_apps[1] == "dapp:third" and pinned_save_count == 1, "Moving a pinned app must persist the updated order exactly once")
assert(not AppDockClass.movePinned(pinned_order_test, "dapp:third", -1), "Moving an app beyond the first position must safely return false")
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
assert(quick_settings_source:find("symbol_widget = self.icon_kind and DAppLogo:new", 1, true) and quick_settings_source:find("padding = 0", 1, true) and quick_settings_source:find("while stack_height > available_height", 1, true), "Quick Settings tiles must use semantic icons, measured glyph boxes, and shrink before overflowing fixed controls")
local appstore_source = assert(io.open(plugin_dir .. "appdock_appstore.lua", "rb")):read("*a")
assert(appstore_source:find("local bar_height = scale(50)", 1, true) and appstore_source:find("local search_y = bar_height + scale(2)", 1, true), "AppStore must open with the Google Play app bar and its search pill")
assert(appstore_source:find("padding = 0", 1, true), "AppStore fixed-height labels must not inherit TextWidget vertical padding")
local homescreen_source = assert(io.open(plugin_dir .. "appdock_homescreen.lua", "rb")):read("*a")
local simple_mode_source = homescreen_source:match("function AppDockHomeScreen:_buildSimpleMode.-\nend") or ""
assert(homescreen_source:find("local search_y = top_line_height + scale(22)", 1, true) and homescreen_source:find("local block_y = search_y", 1, true) and homescreen_source:find("local card_y = block_y", 1, true), "Normal Homescreen must place one wide search pill directly under the status row before glance widgets")
assert(not simple_mode_source:find("Theme.centeredStack", 1, true) and not simple_mode_source:find("has_header_surface", 1, true), "Simple Mode must retain its independent reduced layout path")
assert(recents_source:find('title = "", symbol = "⌂", width = scale(72), height = scale(44)', 1, true), "Compact Open Apps navigation must not place a text label beneath its Home button")
assert(recents_source:find("local margin, gap = scale(10), scale(4)", 1, true) and recents_source:find("math.min(scale(50)", 1, true), "Settings must use visibly compact row and category spacing")
assert(recents_source:find("local card_height = expressive and scale(64) or scale(60)", 1, true) and recents_source:find("local gap = expressive and scale(6) or scale(6)", 1, true), "Open Apps must use visibly compact cards and list gaps")
assert(recents_source:find("local Layout = require(\"appdock_layout\")", 1, true) and recents_source:find("Layout.FixedStack:new", 1, true), "DApp settings and action controls must use fixed-bounds foreground drawing")
assert(quick_settings_source:find("tile_height = scale(68)", 1, true) and quick_settings_source:find("slider_spacing = scale(8)", 1, true), "Normal Quick Settings must use compact visible tile and sheet spacing")
assert(quick_settings_source:find("Layout.FixedStack:new", 1, true), "Quick Settings tiles and notifications must keep their text inside explicit fixed bounds")
assert(quick_settings_source:find("local QuickCloseButton = InputContainer:extend", 1, true) and quick_settings_source:find("function QuickCloseButton:onTapCloseQuickSettings", 1, true), "Quick Settings must provide a visible, working close control")
assert(quick_settings_source:find("local thumb_size = scale(15)", 1, true) and quick_settings_source:find("self.dimen.x, self.dimen.y = x, y", 1, true), "The brightness slider must draw a thumb and map absolute touch coordinates correctly")
assert(appstore_source:find("local row_height = scale(76)", 1, true) and appstore_source:find("local nav_height = scale(58)", 1, true), "AppStore must use compact Google Play list rows and a Play bottom navigation bar")
assert(homescreen_source:find("local label_height = scale(20)", 1, true) and homescreen_source:find("local label_gap = scale(3)", 1, true) and homescreen_source:find("local row_gap = scale(8)", 1, true), "Normal Homescreen app labels and rows must use compact visible spacing")
assert(appstore_source:find("Layout.FixedStack:new", 1, true) and homescreen_source:find("Layout.FixedStack:new", 1, true), "AppStore and Homescreen cards must draw text through the fixed-bounds container")
assert(simple_mode_source:find("local column_gap, row_gap, label_height = scale(12), scale(14), scale(22)", 1, true), "Simple Mode must retain its original app-grid spacing")
assert(homescreen_source:find("local page_size = 9", 1, true) and homescreen_source:find("local grid_width = width", 1, true), "Normal Homescreen must paginate nine apps on a screen-wide grid")
assert(homescreen_source:find('local dock_title = actual_recent_count > 0 and actual_recent_count == #shortcut_apps and _("Recently used") or _("Quick access")', 1, true) and homescreen_source:find("dock_padding = scale(10)", 1, true) and homescreen_source:find("has_app_dock_surface = #dock_apps > 0", 1, true), "Normal Homescreen must provide a compact rounded icon dock with an All apps action")
assert(homescreen_source:find("SwipeHomePage", 1, true) and homescreen_source:find("self:_showPage(self.page + 1)", 1, true) and not homescreen_source:find("Motion.run", 1, true), "Homescreen paging must switch app pages instantly, without animation")
device_controls_source = assert(io.open(plugin_dir .. "appdock_device_controls.lua", "rb")):read("*a")
assert(homescreen_source:find("BrightnessUp", 1, true) and homescreen_source:find("BrightnessDown", 1, true) and homescreen_source:find("function AppDockHomeScreen:_pageKey", 1, true), "Homescreen must bind the physical page keys to brightness controls")
assert(device_controls_source:find("function Controls:pageKeyGroups", 1, true) or device_controls_source:find("function Controls.pageKeyGroups", 1, true), "Device controls must resolve physical page-key groups")
assert(device_controls_source:find("Restart KOReader", 1, true) and device_controls_source:find("Power off", 1, true) and device_controls_source:find("Restart device", 1, true), "Upper page-key hold must expose the three power actions")
assert(device_controls_source:find("HappyReaderScreen", 1, true) and device_controls_source:find("happy_ereader_01.png", 1, true) and device_controls_source:find("scheduleIn(.75", 1, true), "Lower page-key hold must provide an animated happy e-reader screensaver")
assert(homescreen_source:find("local DuckDuckGoBar = InputContainer:extend", 1, true) and homescreen_source:find("duckduckgo = color(222, 88, 51", 1, true) and homescreen_source:find("self.page == 1 and layout.ddg_search ~= false", 1, true) and homescreen_source:find("function AppDockHomeScreen:runWebSearch", 1, true), "The first Homescreen page must offer the branded DuckDuckGo search bar")
assert(appstore_source:find('kind = "app_store"', 1, true) and appstore_source:find('text = _("AppDock Store")', 1, true) and appstore_source:find("local PlayNavTab = InputContainer:extend", 1, true), "AppStore must use the AppDock logo and wordmark with its category navigation")
local browser_source = assert(io.open(plugin_dir .. "appdock_browser.lua", "rb")):read("*a")
assert(browser_source:find("function Browser:beginQuery", 1, true) and browser_source:find("function Browser:runPendingSearch", 1, true) and browser_source:find("state.loading_query = type(query) == \"string\"", 1, true) and browser_source:find('UIManager:setDirty("all", "full")', 1, true) and browser_source:find("UIManager:nextTick(fullRefresh)", 1, true), "The Web Browser must run the pending DuckDuckGo query and request a queued full refresh")
assert(recents_source:find("local RecentDrawer", 1, true) and recents_source:find("function RecentDrawer:onShow", 1, true) and recents_source:find("function DAppManager:showRecentDrawer", 1, true) and recents_source:find("function DAppRecents:onRevealRecentApps", 1, true), "Recent Apps must be available through the animated global bottom drawer")
assert(quick_settings_source:find("local header_subtitle", 1, true) and quick_settings_source:find("local icon_diameter", 1, true) and quick_settings_source:find("BrightnessSlider", 1, true), "Expressive Quick Settings must use Android-style header, toggle tiles, and a prominent brightness card")
assert(quick_settings_source:find('icon_kind = "network"', 1, true) and quick_settings_source:find('icon_kind = "sync"', 1, true) and quick_settings_source:find('kind = self.icon_kind', 1, true), "Quick Settings must use meaningful drawn icons instead of letter placeholders")
local manager_source = assert(io.open(plugin_dir .. "appdock_manager.lua", "rb")):read("*a")
assert(manager_source:find("local function attachRecentSwipe", 1, true) and manager_source:find("appdock_recent_drawer", 1, true), "Manage AppDock must expose the same bottom-edge Recent Apps gesture")
local recent_catalog = {}
for _, id in ipairs({ "system:library", "system:menu", "system:history", "plugin:reader", "system:open_apps" }) do
    recent_catalog[id] = { id = id, title = id }
end
local recent_probe = setmetatable({
    settings = { recent_apps = { "plugin:removed", "system:history" } },
    getAppCatalog = function() return recent_catalog end,
    isSimpleModeAppAllowed = function() return true end,
    _saveSettings = function(self) self.saved = (self.saved or 0) + 1 end,
}, AppDockClass)
recent_probe:_recordRecentApp(recent_catalog["system:menu"])
recent_probe:_recordRecentApp(recent_catalog["system:library"])
recent_probe:_recordRecentApp(recent_catalog["plugin:reader"])
recent_probe:_recordRecentApp(recent_catalog["system:history"])
recent_probe:_recordRecentApp(recent_catalog["system:open_apps"])
local recent_result = recent_probe:getRecentApps(4)
assert(#recent_result == 4 and recent_result[1].id == "system:history" and recent_result[2].id == "plugin:reader" and recent_result[3].id == "system:library" and recent_result[4].id == "system:menu", "Recent apps must be MRU ordered, deduplicated, bounded to four, and exclude navigation entries")
assert(recent_probe.settings.recent_apps[1] == "system:history" and recent_probe.settings.recent_apps[4] == "system:menu", "Unknown recent app ids must be pruned from persistent settings")
recent_probe.settings.recent_apps = { "system:open_apps", "system:history" }
local cleaned_recents = recent_probe:getRecentApps(4)
assert(#cleaned_recents == 1 and cleaned_recents[1].id == "system:history", "Persisted navigation actions must not appear in quick access")
local launched_dapp
local launch_probe = setmetatable({
    settings = { recent_apps = {} },
    isSimpleModeAppAllowed = function() return true end,
    _saveSettings = function() end,
    getDAppManager = function() return { activate = function(_, id) launched_dapp = id end } end,
}, AppDockClass)
launch_probe:launchApp({ id = "dapp:reader", kind = "dapp", dapp_id = "reader" })
assert(launch_probe.settings.recent_apps[1] == "dapp:reader" and launched_dapp == "reader", "Launching a DApp must record it as the most recently used quick-access app")
local files_source = assert(io.open(plugin_dir .. "appdock_filemanager.lua", "rb")):read("*a")
assert(files_source:find("local margin, gap = scale(12), scale(8)", 1, true) and files_source:find("local search_h = scale(40)", 1, true), "Files must use compact Google Files spacing and a prominent search pill")
assert(files_source:find("Layout.FixedStack:new", 1, true) and files_source:find("function FileBrowser:openEntry", 1, true), "File rows and tiles must draw through fixed bounds and preserve safe open dispatch")
local sleepscreen_source = assert(io.open(plugin_dir .. "appdock_sleepscreen.lua", "rb")):read("*a")
assert(sleepscreen_source:find("function Sleep.show", 1, true) and sleepscreen_source:find("function Sleep.close", 1, true) and sleepscreen_source:find("Sleeping", 1, true), "The optional Sleep screen must provide a minimal full-screen show/close widget")
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
    getRecentApps = function(self, limit)
        local apps = {}
        for index = 1, math.min(limit or 4, #(self.test_recent_apps or {})) do apps[index] = self.test_recent_apps[index] end
        return apps
    end,
    seedDefaults = function() end,
    getStoreWidgets = function() return { { widget_id = "quote_widget", title = "Quote Widget" }, { widget_id = "weather_widget", title = "Weather Widget" } } end,
    getStoreWidgetPosition = function(_, widget_id) return widget_id == "quote_widget" and 1 or 2, 2 end,
    adjustStoreWidgetScale = function(self, widget_id, delta)
        self.settings.layout.widget_scales = self.settings.layout.widget_scales or {}
        local current = tonumber(self.settings.layout.widget_scales[widget_id]) or 1
        local next_scale = math.max(.75, math.min(1.5, current + delta))
        if next_scale == 1 then self.settings.layout.widget_scales[widget_id] = nil else self.settings.layout.widget_scales[widget_id] = next_scale end
        self:_saveSettings()
        return next_scale
    end,
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
assert(#catalog == 8 and catalog[1].id and catalog[2].id and catalog[3].id and catalog[4].id and catalog[5].id and catalog[6].id and catalog[7].id and catalog[8].id, "DApp registry must expose all built-in catalog apps")
for _, entry in ipairs(catalog) do
    if entry.id == "dapp:youtube" then log.youtube_entry = entry end
end
assert(log.youtube_entry and log.youtube_entry.logo == "youtube" and log.youtube_entry.kind == "dapp", "The built-in YouTube DApp must be part of the AppDock catalog")
do
    local draw_entry
    for _, entry in ipairs(catalog) do if entry.id == "dapp:draw" then draw_entry = entry end end
    local handlers = manager:getFileHandlers("sketch.adraw")
    assert(draw_entry and draw_entry.kind == "dapp" and #handlers == 1 and handlers[1].id == "draw", "The built-in Draw app must be listed and own the editable project file handler")
end
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
local filemanager_source = assert(io.open(plugin_dir .. "appdock_filemanager.lua", "rb")):read("*a")
assert(filemanager_source:find("local SearchPill = InputContainer:extend", 1, true) and filemanager_source:find("local CategoryCard = InputContainer:extend", 1, true) and filemanager_source:find("local FileTile = InputContainer:extend", 1, true), "Files must provide Google Files-style search, category and tile widgets")
assert(filemanager_source:find("google_files_style = true", 1, true) and filemanager_source:find("has_recent = #recent > 0", 1, true) and filemanager_source:find("has_categories = true", 1, true) and filemanager_source:find("two_column = true", 1, true), "Files must expose a two-column Google Files dashboard with recent files, categories and storage")
assert(filemanager_source:find('local STORAGE_ROOT = "/mnt/onboard"', 1, true) and filemanager_source:find('"Downloads", "Documents", "Images", "Videos", "Audio"', 1, true), "Files must define the Kobo internal storage root and standard folders")
assert(filemanager_source:find("function FileBrowser:sortMyFiles", 1, true) and filemanager_source:find("function FileBrowser:openInternalStorage", 1, true) and filemanager_source:find("non_destructive_sort = true", 1, true), "Files must provide non-destructive sorting and an explicit Internal Storage action")
assert(filemanager_source:find("AppDockKeyboard:new", 1, true) and not filemanager_source:find("InputDialog:new", 1, true), "Files search must use the AppDock keyboard instead of KOReader input dialogs")
assert(filemanager_source:find("ges = \"hold\"", 1, true) and filemanager_source:find("function FileBrowser:showEntryActions", 1, true), "Files must offer long-press actions")
assert(filemanager_source:find("Rename", 1, true) and filemanager_source:find("Open with ...", 1, true) and filemanager_source:find("Delete", 1, true) and filemanager_source:find("Move", 1, true) and filemanager_source:find("Copy", 1, true), "Files long-press actions must include rename, open with, delete, move and copy")
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
assert(appdock:adjustStoreWidgetScale("quote_widget", .25) == 1.25 and appdock.settings.layout.widget_scales.quote_widget == 1.25, "Homescreen editing must persist an individual Store widget size")
assert(appdock:adjustStoreWidgetScale("quote_widget", -.25) == 1 and appdock.settings.layout.widget_scales.quote_widget == nil, "Widget size controls must support stepping back to the default size")
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
-- The BWR Video Store DApp is an optional local fixture: the regression only
-- runs where the published catalog file has been checked out.
local bwr_store_file = os.getenv("APPDOCK_BWR_FIXTURE") or "/home/ubuntu/dapps-store-repo/bwr_video.lua"
local bwr_fixture = io.open(bwr_store_file, "rb")
if bwr_fixture then
    bwr_fixture:close()
    local bwr_installed, bwr_id = manager:loadStoreDApp(bwr_store_file, "bwr_video.lua")
    assert(bwr_installed and bwr_id == "bwr_video" and manager.definitions.bwr_video, "BWR Video must load through the actual Store DApp registration path")
    manager:activate("bwr_video")
    local bwr_instance = manager.instances.bwr_video
    assert(bwr_instance and bwr_instance.pane and bwr_instance.pane.dimen, "BWR Video must build through the actual AppDock host without a Player field")
    manager:closeDApp("bwr_video")
else
    print("AppDock DApp test: skipped the optional BWR Video fixture at " .. bwr_store_file)
end

manager:activate("analog_clock", "home")
assert(manager.active_id == "analog_clock" and #manager:getOpenApps() == 1, "Activating a DApp must retain it in the open-app list")
assert(log.dirties[#log.dirties].widget == manager.active_host and log.dirties[#log.dirties].kind == "ui", "Activating a DApp must request a next-tick redraw for the new host")
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
do
    local settings_search, android_category, android_row = false, false, false
    walk_tree(settings_instance.pane, function(node)
        settings_search = settings_search or node.settings_search == true
        android_category = android_category or (node.layout and node.layout.android_category == true)
        android_row = android_row or (node.layout and node.layout.android_row == true)
    end)
    assert(settings_instance.pane.settings_layout.android_style and settings_instance.pane.settings_layout.has_search and settings_instance.pane.settings_layout.uses_scroll, "Settings must expose the Android-style searchable and scrollable layout metadata")
    assert(settings_search and android_category and android_row, "Settings must render a search pill, icon categories, and Android-style preference rows")
end
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
assert(settings_instance.pane.settings_layout.category == "display" and settings_instance.pane.settings_layout.row_count == 11, "Display category must expose refresh, text and contrast controls alongside themes, launcher, wallpaper and beta settings")
do
    local appearance_preview, display_toggle = false, false
    walk_tree(settings_instance.pane, function(node)
        appearance_preview = appearance_preview or node.settings_appearance_preview == true
        display_toggle = display_toggle or (node.layout and node.layout.android_row == true and node.layout.is_toggle == true)
    end)
    assert(settings_instance.pane.settings_layout.has_appearance_preview and appearance_preview and display_toggle, "Display must show the Light/Dark appearance preview and native-style switches")
end
assert(appdock:setAccessibility({ text_scale = 1.3, high_contrast = true }) and Theme.getPalette(appdock).high_contrast, "Accessibility settings must persist a bounded text scale and activate the high-contrast palette")
manager:showFrontlightSettings()
assert(log.events[#log.events] == "ShowFlDialog", "Brightness and warmth must use KOReader's native frontlight dialog")
manager:toggleColorTheme({ requestRebuild = function() log.settings_rebuilds = (log.settings_rebuilds or 0) + 1 end })
assert(log.events[#log.events] == "ToggleNightMode" and log.settings_rebuilds == 1, "Color themes must trigger KOReader's night-mode event")
settings_instance.settings_category = "other"
manager:activate("settings")
assert(settings_instance.pane.settings_layout.category == "other" and settings_instance.pane.settings_layout.row_count == 10, "Other category must include the sleep screen and setup wizard alongside the opt-in local workspace, lockscreen, control center, permissions, arrangement and startup")
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
local simple_edit_button, simple_app_tile = nil, nil
walk_tree(simple_home[1], function(node)
    if node.title == "Edit" and type(node.onTapToggleHomeEdit) == "function" then simple_edit_button = node end
    if node.app and node.app.id == "dapp:first" and node.onHoldSelectAppTile then simple_app_tile = node end
end)
assert(simple_edit_button and simple_app_tile, "Simple Mode must expose a visible Edit button and recognizable app tiles")
local manager_count_before_hold = log.manager or 0
assert(simple_app_tile:onHoldSelectAppTile() and simple_home.edit_mode, "Long-pressing an app must enter edit mode directly")
assert((log.manager or 0) == manager_count_before_hold, "Long-pressing an app to edit the layout must not open a separate management dialog")
simple_home:finishLayoutEdit()
assert(simple_edit_button:onTapToggleHomeEdit() and simple_home.edit_mode, "Tapping the visible Edit button must enter layout editing directly")
simple_home:finishLayoutEdit()
assert(simple_home.simple_layout and simple_home.simple_layout.columns == 4 and simple_home.simple_layout.rows == 3 and simple_home.simple_layout.app_count == 2, "Simple homescreen must contain only the visible apps in a 4×3 grid")
assert(not simple_home.normal_layout, "Simple homescreen must not create any normal-mode expressive layout metadata")
assert(not simple_home._widget_tick, "Simple homescreen must not schedule hidden widget refreshes")
assert(not (simple_home.ges_events or {}).SwipeHomePage and not (simple_home.ges_events or {}).RevealRecentApps, "Simple homescreen must retain its previous gesture surface without animated paging or the Recent Apps drawer")
local QuickSettings = dofile(plugin_dir .. "appdock_quicksettings.lua")
local simple_quick_settings = QuickSettings:new{ appdock = appdock, home = simple_home }
assert(simple_quick_settings.layout.simple_mode and simple_quick_settings.layout.tile_count == 3 and simple_quick_settings.layout.tile_icon_count == 3 and not simple_quick_settings.layout.show_notifications, "Simple quick settings must contain three icon tiles, brightness, and no notifications")
assert(not simple_quick_settings.layout.expressive and simple_quick_settings.sheet_height < 400, "Simple quick settings must retain its existing compact non-expressive layout")
assert(simple_quick_settings.layout.has_close_button and not simple_quick_settings.layout.has_grab_handle and simple_quick_settings.layout.slider_has_thumb, "Simple Quick Settings must retain a close action and a visible brightness thumb without expressive extras")
assert(not simple_quick_settings.ges_events.RevealRecentApps, "Simple quick settings must not add the expressive Recent Apps drawer gesture")
appdock:setSimpleModeOption("homescreen", false)
appdock:setSimpleModeOption("quick_settings", false)
appdock:setSimpleModeOption("focus_apps", false)
appdock.test_recent_apps = {
    { id = "dapp:first", title = "First App" },
    { id = "dapp:second", title = "Second App" },
    { id = "system:library", title = "Library" },
    { id = "system:history", title = "History" },
}
local expressive_home = HomeScreen:new{ appdock = appdock }
assert(expressive_home.normal_layout and expressive_home.normal_layout.expressive and not expressive_home.normal_layout.has_header_surface and expressive_home.normal_layout.has_search_pill and expressive_home.normal_layout.has_app_dock_surface, "Normal homescreen must use a search-led Android layout with a rounded icon dock")
assert(expressive_home.normal_layout.grid_columns == 3 and expressive_home.normal_layout.grid_rows == 3 and expressive_home.normal_layout.page_size == 9 and expressive_home.normal_layout.grid_width == Device.screen:getSize().w, "Normal homescreen must use a full-width 3×3 app grid")
assert(expressive_home.normal_layout.quick_access_count == 4 and expressive_home.normal_layout.recent_count == 4, "Normal homescreen must show one row of four recent shortcuts")
assert(expressive_home.normal_layout.dock_item_count == 5, "The bottom dock must contain recent shortcuts and a fixed All apps action")
local drawer_dock_icon
walk_tree(expressive_home[1], function(node)
    if node.is_dock_item and node.symbol == "app_drawer" and node.hide_label then drawer_dock_icon = node end
end)
assert(drawer_dock_icon and drawer_dock_icon.dimen.h == drawer_dock_icon.tile_size, "The All apps action must use a compact icon-only launcher glyph in the dock")
assert(expressive_home.normal_layout.tile_size >= 62, "App tiles must remain comfortably sized alongside the quick-access row")
local many_pinned_apps = {}
for index = 1, 10 do many_pinned_apps[index] = { id = "test:grid:" .. index, title = "Grid App " .. index } end
local original_get_pinned_apps = appdock.getPinnedApps
local original_get_pinned_position, original_move_pinned = appdock.getPinnedPosition, appdock.movePinned
appdock.getPinnedApps = function() return many_pinned_apps end
appdock.getPinnedPosition = function(_, app_id)
    for index, app in ipairs(many_pinned_apps) do if app.id == app_id then return index, #many_pinned_apps end end
    return nil, #many_pinned_apps
end
appdock.movePinned = function(_, app_id, delta)
    local position
    for index, app in ipairs(many_pinned_apps) do if app.id == app_id then position = index; break end end
    if not position then return false end
    local target = math.max(1, math.min(#many_pinned_apps, position + delta))
    if target == position then return false end
    local app = table.remove(many_pinned_apps, position)
    table.insert(many_pinned_apps, target, app)
    return true
end
local editor_home = HomeScreen:new{ appdock = appdock, page = 1 }
editor_home:beginLayoutEdit(many_pinned_apps[1].id)
local draggable_tile, editable_widget, scale_up, done_button = nil, nil, nil, nil
walk_tree(editor_home[1], function(node)
    if node.app and node.app.id == many_pinned_apps[1].id and node.ges_events and node.ges_events.PanMoveAppTile then draggable_tile = node end
    if node.widget and node.widget.widget_id == "quote_widget" and node.ges_events and node.ges_events.PanMoveStoreWidget then editable_widget = node end
    if type(node.onTapAdjustStoreWidget) == "function" and node.widget_id == "quote_widget" and node.delta == .25 then scale_up = node end
    if node.title == "Done" and type(node.onTapToggleHomeEdit) == "function" then done_button = node end
end)
assert(editor_home.edit_mode and draggable_tile and editable_widget and scale_up and done_button, "Long-press edit mode must show the app grid, movable/resizable widgets, and a Done action")
assert(editor_home.normal_layout.widget_columns == 2, "Multiple Store widgets must use an Android-like two-column card grid")
assert(editor_home.normal_layout.glance_cards_hidden_for_edit == (appdock.settings.widgets.status == true or appdock.settings.widgets.reading_hint == true), "Non-editable glance cards must temporarily yield space while arranging Store widgets")
local initial_quote_position = editor_home.normal_layout.widget_positions.quote_widget
local initial_weather_position = editor_home.normal_layout.widget_positions.weather_widget
assert(initial_quote_position and initial_weather_position and initial_quote_position.y == initial_weather_position.y and initial_quote_position.x ~= initial_weather_position.x, "Widgets at their default size must share a balanced two-column row")
assert(scale_up:onTapAdjustStoreWidget() == 1.25 and appdock.settings.layout.widget_scales.quote_widget == 1.25, "Tapping a widget plus control must enlarge only that widget")
local has_size_indicator = false
walk_tree(editor_home[1], function(node) if node.text == "Size: 125%" then has_size_indicator = true end end)
assert(has_size_indicator, "The widget editor must display its current size beside the scale controls")
local quote_position = editor_home.normal_layout.widget_positions.quote_widget
local weather_position = editor_home.normal_layout.widget_positions.weather_widget
assert(quote_position and weather_position and quote_position.span == 2 and quote_position.width > weather_position.width and weather_position.y > quote_position.y, "Enlarging a widget must let it span the row while other widgets reflow below")
assert(editable_widget:onPanReleaseMoveStoreWidget(nil, { pos = { x = weather_position.x + weather_position.width / 2, y = weather_position.y + weather_position.height / 2 } }) and log.moved_widget, "Dragging a Store widget to another grid cell must reorder it")
local target_x = editor_home.normal_layout.grid_x + editor_home.normal_layout.cell_width + 4
local target_y = editor_home.normal_layout.grid_y + 4
assert(draggable_tile:onPanMoveAppTile(nil, { pos = { x = target_x, y = target_y } }), "App tiles must begin dragging in edit mode")
assert(draggable_tile:onPanReleaseMoveAppTile(nil, { pos = { x = target_x, y = target_y } }), "Releasing an app tile must complete a grid move")
assert(many_pinned_apps[2].id == "test:grid:1", "Dropping an app in the next grid cell must persist its new homescreen position")
assert(appdock:movePinned("test:grid:1", -1), "The layout-editor test must restore the original app ordering")
assert(done_button:onTapToggleHomeEdit() and not editor_home.edit_mode, "The visible Done action must end the edit mode")
appdock.getPinnedPosition, appdock.movePinned = original_get_pinned_position, original_move_pinned
local paged_home = HomeScreen:new{ appdock = appdock, page = 1 }
local visible_grid_apps = 0
walk_tree(paged_home[1], function(child)
    if child.app and type(child.app.id) == "string" and child.app.id:match("^test:grid:") then
        visible_grid_apps = visible_grid_apps + 1
        local offset = child.overlap_offset
        assert(offset and offset[1] >= 0 and offset[1] + (child.label_width or 0) <= Device.screen:getSize().w, "A full-width grid cell must remain inside the screen")
    end
end)
assert(paged_home.normal_layout.page_count == 2 and visible_grid_apps == 9, "A 3×3 app page must show nine apps before moving to the next page")
assert(paged_home.normal_layout.tile_size >= 62 and (paged_home.normal_layout.hidden_widgets_for_fit or paged_home.normal_layout.widget_columns == 2), "Optional Store widgets must reflow or yield space to keep paginated app tiles comfortably sized")
assert(paged_home:onSwipeHomePage(nil, { direction = "west" }) and paged_home.page == 2 and not paged_home._page_transition, "Swiping west must animate to the next homescreen page and finish cleanly")
assert(paged_home:onSwipeHomePage(nil, { direction = "east" }) and paged_home.page == 1, "Swiping east must animate back to the previous homescreen page")
appdock.getPinnedApps = original_get_pinned_apps
local saved_recent_apps = appdock.test_recent_apps
appdock.test_recent_apps = {}
local fallback_home = HomeScreen:new{ appdock = appdock }
assert(fallback_home.normal_layout.quick_access_count == 2 and fallback_home.normal_layout.recent_count == 0 and fallback_home.normal_layout.quick_access_title == "Quick access", "Pinned fallback tiles must be labelled Quick access when no app has been used recently")
appdock.test_recent_apps = saved_recent_apps
-- DuckDuckGo search bar on the first homescreen page -------------------------
local function find_widget_text(widget, needle)
    local found = false
    walk_tree(widget, function(node)
        if node.text == needle then found = true end
    end)
    return found
end
local function find_ddg_bars(widget)
    local bars = {}
    walk_tree(widget, function(node)
        if type(node.onTapDuckDuckGoSearch) == "function" and node.ges_events and node.ges_events.TapDuckDuckGoSearch then
            bars[#bars + 1] = node
        end
    end)
    return bars
end
local ddg_home = HomeScreen:new{ appdock = appdock, page = 1 }
local ddg_bars = find_ddg_bars(ddg_home[1])
assert(#ddg_bars == 1 and find_widget_text(ddg_bars[1], "Search with DuckDuckGo"), "The first homescreen page must show a single-line DuckDuckGo search pill")
local ddg_bar = ddg_bars[1]
local shown_before_ddg = #log.shown
assert(ddg_bar:onTapDuckDuckGoSearch() and #log.shown == shown_before_ddg + 1, "Tapping the DuckDuckGo bar must open the AppDock keyboard")
assert(ddg_home:runWebSearch("   koreader ducks   ") and log.browser_query == "koreader ducks", "The DuckDuckGo bar must hand the trimmed query to the Web Browser")
assert(manager.active_id == "web_browser" and log.browser_pending_runs == 1, "A DuckDuckGo search must open the Web Browser and run the pending query")
manager:closeDApp("web_browser")
local ddg_original_pins = appdock.getPinnedApps
appdock.getPinnedApps = function() return many_pinned_apps end
local page_two_home = HomeScreen:new{ appdock = appdock, page = 2 }
assert(#find_ddg_bars(page_two_home[1]) == 0, "The DuckDuckGo bar belongs to the first homescreen page only")
appdock.getPinnedApps = ddg_original_pins
local expressive_quick_settings = QuickSettings:new{ appdock = appdock, home = expressive_home }
assert(expressive_quick_settings.layout.expressive and not expressive_quick_settings.layout.simple_mode and expressive_quick_settings.sheet_height >= 0, "Normal quick settings must use expressive layout only outside Simple Mode")
assert(expressive_quick_settings.layout.tile_icon_count == expressive_quick_settings.layout.tile_count and expressive_quick_settings.layout.has_close_button and expressive_quick_settings.layout.has_grab_handle and expressive_quick_settings.layout.slider_has_thumb, "Expressive Quick Settings must show semantic icons, a grab handle, a working close action, and a thumb slider")
local expressive_close_button, expressive_icon_tiles = nil, 0
walk_tree(expressive_quick_settings[1], function(node)
    if type(node.onTapCloseQuickSettings) == "function" then expressive_close_button = node end
    if node.icon_kind then expressive_icon_tiles = expressive_icon_tiles + 1 end
end)
assert(expressive_close_button and expressive_icon_tiles == expressive_quick_settings.layout.tile_count, "Every normal Quick Settings tile must render its semantic icon, with an actionable close control")
local brightness_test = QuickSettings:new{ appdock = appdock, home = expressive_home }
brightness_test._brightnessState = function() return { min = 0, max = 100, current = 50 } end
brightness_test.setBrightness = function(self, value) self.test_brightness = value end
brightness_test:rebuild(false)
brightness_test.slider:paintTo(nil, 100, 300)
brightness_test.slider:onTapBrightness(nil, { pos = { x = 100 + brightness_test.slider.track_x + brightness_test.slider.track_width } })
assert(brightness_test.test_brightness == 100, "Brightness taps at the right edge must map to maximum intensity after screen positioning")
assert(expressive_quick_settings:onRevealRecentApps(), "The bottom-edge swipe must expose Recently used above Quick Settings")
local recent_drawer = log.shown[#log.shown]
assert(recent_drawer.covers_fullscreen == false and recent_drawer.sheet_height > 0 and recent_drawer.sheet_layer, "Recently used must open as a bounded animated bottom drawer")
recent_drawer:onShow()
local drawer_motions = 0
for _, motion in ipairs(log.motion or {}) do
    if motion.target == recent_drawer then drawer_motions = drawer_motions + 1 end
end
assert(recent_drawer.sheet_layer.overlap_offset[2] == recent_drawer.sheet_y and recent_drawer.sheet_y > 0 and recent_drawer.sheet_y < recent_drawer.dimen.h, "The Recently used drawer must settle at its bounded sheet position in the lower screen area")
assert(drawer_motions == 0, "The Recently used drawer must switch instantly instead of animating on E-Ink")
assert(expressive_close_button:onTapCloseQuickSettings(), "Tapping the visible close control must dismiss Quick Settings")

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
