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
package.preload["appdock_logo"] = function() return Widget end
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
package.preload["ui/widget/inputdialog"] = function() return WidgetContainer end
package.preload["ui/widget/buttondialog"] = function() return WidgetContainer end
package.preload["ui/widget/infomessage"] = function() return WidgetContainer end
package.preload["ui/widget/widget"] = function() return Widget end
package.preload["ui/widget/container/widgetcontainer"] = function() return WidgetContainer end
package.preload["ui/widget/container/inputcontainer"] = function() return InputContainer end
package.preload["ui/widget/container/centercontainer"] = function() return CenterContainer end
package.preload["ui/widget/container/framecontainer"] = function() return FrameContainer end
package.preload["ui/widget/overlapgroup"] = function() return OverlapGroup end
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
        broadcastEvent = function(_, event) table.insert(log.events, event.name) end,
    }
end

local DAppManager = dofile(plugin_dir .. "appdock_dapps.lua")
local Device = require("device")
local Theme = require("appdock_theme")
local UIManager = require("ui/uimanager")
assert(Theme.ellipsize("ABCDE", 4) == "ABC…", "Text overflow must use a bounded one-line ellipsis")
assert(Theme.ellipsize("Äpfel", 4) == "Äpf…", "Text overflow must preserve complete UTF-8 characters")
assert(Theme.fitLabel("A long compact button label", 30, 10, 0):find("…", 1, true), "Narrow controls must shorten labels instead of allowing wrapped text")
local appdock = {
    settings = { widgets = { clock = true, status = true, reading_hint = true, store = {}, store_order = {} }, theme = { selected = "lavender", custom = {} }, layout = { app_spacing = 12, logo_shape = "rounded", search_enabled = false }, store = { installed = {} }, dapp_permissions = {}, widget_generator = { items = {}, next_id = 0 }, beta = { plugin_dapp_host = false } },
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
    getStoreWidgets = function() return { { widget_id = "quote_widget", title = "Quote Widget" }, { widget_id = "weather_widget", title = "Weather Widget" } } end,
    movePinned = function() log.moved_app = true; return true end,
    moveStoreWidget = function() log.moved_widget = true; return true end,
    setTheme = function(self, id) self.settings.theme = self.settings.theme or { custom = {} }; self.settings.theme.selected = id; return true end,
    createCustomTheme = function(self, title, hex)
        self.settings.theme = self.settings.theme or { custom = {} }
        self.settings.theme.custom = self.settings.theme.custom or {}
        self.settings.theme.custom.custom_test = { title = title, primary = hex }
        self.settings.theme.selected = "custom_test"
        return "custom_test"
    end,
    ui = {
        showFileManager = function(_, file) log.file_manager_file = file or true end,
        document = { file = "/books/example.epub" },
    },
}
local manager = DAppManager:new(appdock)
local catalog = manager:getCatalogApps()
assert(#catalog == 6 and catalog[1].id and catalog[2].id and catalog[3].id and catalog[4].id and catalog[5].id and catalog[6].id, "DApp registry must expose all built-in catalog apps")
local store_fixture = "/tmp/appdock_store_fixture.lua"
local store_file = assert(io.open(store_fixture, "wb"))
store_file:write("return { id = 'quote_card', title = 'Quote Card', version = '1.0.0', subtitle = 'Stored test DApp', openFile = function(instance, path) instance.opened_file = path; return true end, backgroundTick = function(instance, context) instance.background_runs = (instance.background_runs or 0) + 1; instance.background_context = context.background end, onAutostart = function(instance, context) instance.autostart_runs = (instance.autostart_runs or 0) + 1; instance.autostart_context = context.background end, buildPane = function(instance, context) return { dimen = context.dimen } end }")
store_file:close()
local installed, store_id = manager:loadStoreDApp(store_fixture, "fixtures/quote_card.lua")
assert(installed and store_id == "quote_card" and manager.definitions.quote_card, "Confirmed store DApps must be added to the AppDock registry")
assert(appdock.settings.store.installed.quote_card and appdock.settings.store.installed.quote_card.version == "1.0.0" and log.store_saved == 1, "Store DApps must persist their local installation record and version")
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
local navigation_bar, home_chip, recents_chip, close_chip = host_chrome[#host_chrome - 3], host_chrome[#host_chrome - 2], host_chrome[#host_chrome - 1], host_chrome[#host_chrome]
assert(navigation_bar.overlap_offset[2] == 750 and navigation_bar.height == 50, "DApp hosts must reserve a separate lower system-navigation bar")
assert(home_chip.overlap_offset[2] >= 750 and recents_chip.overlap_offset[2] == home_chip.overlap_offset[2] and close_chip.overlap_offset[2] == home_chip.overlap_offset[2], "Home, open-apps and close chips must share the lower navigation row")
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
settings_instance.settings_category = "display"
manager:activate("settings")
assert(settings_instance.pane.settings_layout.category == "display" and settings_instance.pane.settings_layout.row_count == 5, "Display category must include wallpaper and beta controls in the settings DApp state")
manager:showFrontlightSettings()
assert(log.events[#log.events] == "ShowFlDialog", "Brightness and warmth must use KOReader's native frontlight dialog")
manager:toggleColorTheme({ requestRebuild = function() log.settings_rebuilds = (log.settings_rebuilds or 0) + 1 end })
assert(log.events[#log.events] == "ToggleNightMode" and log.settings_rebuilds == 1, "Color themes must trigger KOReader's night-mode event")
settings_instance.settings_category = "other"
manager:activate("settings")
assert(settings_instance.pane.settings_layout.category == "other" and settings_instance.pane.settings_layout.row_count == 8, "Other category must include lockscreen, control center, DApp permissions, arrangement, about, language, startup, and refresh entries")
manager:showArrangementEditor(settings_instance, { requestRebuild = function() log.arrangement_rebuilds = (log.arrangement_rebuilds or 0) + 1 end })
local arrangement_dialog = log.shown[#log.shown]
assert(arrangement_dialog.title == "Arrange apps & widgets" and arrangement_dialog.buttons[#arrangement_dialog.buttons][1].text == "Done", "Settings must open one compact arrangement dialog with a Done action")
assert(#arrangement_dialog.buttons >= 6, "Settings arrangement dialog must list apps and widgets")

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
    if child.host == split_host and child.ges_events and child.ges_events.PanSplitDivider then split_divider = child; break end
end
assert(split_divider and split_divider.ges_events.PanReleaseSplitDivider, "Split screen must expose a draggable divider with pan and release gestures")
local first_height_before_drag = clock_instance.pane.dimen.h
assert(split_divider:onPanSplitDivider(nil, { pos = { y = 560 } }), "Dragging the split divider must be handled")
assert(clock_instance.pane.dimen.h > first_height_before_drag and settings_instance.pane.dimen.h < first_height_before_drag, "Dragging the divider downward must enlarge the upper pane and shrink the lower pane")
assert(clock_instance.visible and settings_instance.visible and clock_instance.in_split and settings_instance.in_split and #split_host.active_panes == 2, "Resizing split panes must keep both DApps active without leaving split screen")
local saves_before_split_release = log.store_saved or 0
assert(split_divider:onPanReleaseSplitDivider(nil, { pos = { y = 560 } }), "Releasing the split divider must be handled")
assert(appdock.settings.layout.split_ratio > .5 and (log.store_saved or 0) == saves_before_split_release + 1, "Releasing the divider must persist the bounded split ratio")
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
