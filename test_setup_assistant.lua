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
local log = {
    offers = 0, saves = 0, sleep_show = 0, sleep_close = 0, home = 0,
    boot_callback = nil, shown = {}, closed = {}, manual_setup_calls = 0,
}

_G.G_reader_settings = {
    readSetting = function() return saved_settings end,
    saveSetting = function(_, _, value) saved_settings = value; log.saves = log.saves + 1 end,
    isTrue = function() return false end,
}

package.preload["gettext"] = function() return function(text) return text end end
package.preload["pluginloader"] = function() return { loadPlugins = function() return {} end } end
package.preload["ui/widget/container/widgetcontainer"] = function() return WidgetContainer end
package.preload["appdock_dialogs"] = function()
    return {
        ButtonDialog = WidgetContainer, InputDialog = WidgetContainer,
        ConfirmBox = WidgetContainer, InfoMessage = WidgetContainer,
    }
end
package.preload["ui/widget/buttondialog"] = function() return WidgetContainer end
package.preload["ui/widget/infomessage"] = function() return WidgetContainer end
package.preload["ffi/blitbuffer"] = function()
    return {
        COLOR_WHITE = 1, COLOR_BLACK = 0, COLOR_GRAY_8 = 200,
        COLOR_LIGHT_GRAY = 180, COLOR_DARK_GRAY = 80, COLOR_GRAY = 120, COLOR_GRAY_7 = 140,
    }
end
package.preload["device"] = function()
    return {
        screen = {
            scaleBySize = function(_, n) return n end,
            getSize = function() return { w = 600, h = 800 } end,
            isColorEnabled = function() return false end,
        },
        hasKeys = function() return false end,
    }
end
package.preload["ui/font"] = function() return { getFace = function() return {} end } end
package.preload["ui/geometry"] = function() return { new = function(_, args) return args end } end
package.preload["ui/gesturerange"] = function() return { new = function(_, args) return args end } end
package.preload["ui/widget/container/inputcontainer"] = function() return WidgetContainer end
package.preload["ui/widget/textwidget"] = function() return WidgetContainer end
package.preload["ui/uimanager"] = function()
    return {
        nextTick = function(_, callback) callback() end,
        scheduleIn = function() end,
        unschedule = function() end,
        setDirty = function() end,
        forceRePaint = function() end,
        show = function(_, widget) table.insert(log.shown, widget) end,
        close = function(_, widget)
            table.insert(log.closed, widget)
            if widget and widget.onCloseWidget then widget:onCloseWidget() end
        end,
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
package.preload["appdock_homescreen"] = function()
    local Home = baseClass(WidgetContainer)
    function Home:init() log.home = log.home + 1 end
    return Home
end
package.preload["appdock_boot"] = function()
    return {
        show = function(callback) log.boot_callback = callback end,
    }
end
package.preload["appdock_dapps"] = function()
    return {
        new = function()
            return {
                runPermittedAutostarts = function() end,
                restoreWorkspace = function() return false end,
                showFeatureDialog = function()
                    log.offers = log.offers + 1
                end,
                showSetupAssistant = function(_, instance, context, automatic)
                    log.manual_setup_calls = log.manual_setup_calls + 1
                    log.manual_setup_instance = instance
                    log.manual_setup_context = context
                    log.manual_setup_automatic = automatic
                    return true
                end,
            }
        end,
    }
end

local AppDock = dofile(plugin_dir .. "main.lua")
local ui = { menu = { registerToMainMenu = function() end } }
local first = AppDock:new{ ui = ui }
local first_status = first:getSetupAssistantStatus()
assert(first_status.version == "8.1.1" and not first_status.offered and not first_status.completed, "The setup wizard remains an independent manual flow")
assert(log.offers == 1 and first:shouldShowUpdateDialog(), "The update dialog must be shown on startup until explicitly dismissed")
assert(first:getFeaturePages()[1].image and first:getFeaturePages()[1].image:match("assets/logos/appdock%.png$"), "The update dialog must receive its packaged test image")
local manual_instance, manual_context = {}, {}
assert(first:showSetupAssistant(manual_instance, manual_context), "The manual wizard entry point must delegate to the DApp manager")
assert(log.manual_setup_calls == 1 and log.manual_setup_instance == manual_instance
    and log.manual_setup_context == manual_context and log.manual_setup_automatic == false,
    "The manual wizard must never be confused with the automatic update-notice flow")
assert(first:setSleepScreenEnabled(true) and first.settings.sleepscreen_enabled, "The Sleep screen toggle must persist locally")
first:onSuspend()
assert(log.sleep_show == 1, "An enabled Sleep screen must be shown on Suspend")
first:onResume()
assert(log.sleep_close == 1, "The Sleep screen must close on Resume")
first:completeSetupAssistant()
assert(first:getSetupAssistantStatus().completed and not first:shouldOfferSetupAssistant(), "Completing setup must prevent repeat offers for the same version")
local second = AppDock:new{ ui = ui }
assert(log.offers == 2 and second:shouldShowUpdateDialog(), "The update dialog must appear again after a normal Later or Done close")
assert(second:dismissUpdateDialog() and not second:shouldShowUpdateDialog(), "Don't show again must persist for the current AppDock version")
local third = AppDock:new{ ui = ui }
assert(log.offers == 2 and not third:shouldShowUpdateDialog(), "A dismissed update dialog must stay hidden after a KOReader restart")

-- A real boot screen finishes asynchronously. The update dialog must wait for
-- its callback; otherwise showHome() puts the homescreen on top of the dialog.
saved_settings = { launch_on_start = true, update_dialog = { dismissed_version = "" } }
local offers_before_boot = log.offers
local booted = AppDock:new{ ui = ui }
assert(log.boot_callback and log.offers == offers_before_boot, "The update dialog must wait while the boot screen is visible")
log.boot_callback()
assert(log.home > 0 and log.offers == offers_before_boot + 1, "The update dialog must appear after the homescreen finishes loading")

-- Exercise the actual DAppManager implementation, rather than only the
-- AppDock delegator above. These tiny module stubs are deliberately limited to
-- imports: the assistant itself must not need a homescreen or a live device.
package.preload["json"] = function() return { encode = function() return "{}" end, decode = function() return {} end } end
package.preload["datastorage"] = function() return { getDataDir = function() return "/tmp" end } end
package.preload["ui/event"] = function() return { new = function(_, name) return { name = name } end } end
package.preload["ui/widget/container/centercontainer"] = function() return WidgetContainer end
package.preload["ui/widget/container/framecontainer"] = function() return WidgetContainer end
package.preload["ui/widget/horizontalspan"] = function() return WidgetContainer end
package.preload["ui/widget/overlapgroup"] = function() return WidgetContainer end
package.preload["ui/widget/scrollhtmlwidget"] = function() return WidgetContainer end
package.preload["ui/widget/container/scrollablecontainer"] = function() return WidgetContainer end
package.preload["ui/widget/verticalgroup"] = function() return WidgetContainer end
package.preload["ui/widget/verticalspan"] = function() return WidgetContainer end
package.preload["ui/widget/widget"] = function() return WidgetContainer end
package.preload["appdock_device_controls"] = function() return {} end
package.preload["appdock_keyboard"] = function() return {} end
package.preload["appdock_logo"] = function() return WidgetContainer end
package.preload["appdock_layout"] = function() return {} end
package.preload["appdock_help"] = function() return {} end
package.preload["appdock_browser"] = function() return {} end
package.preload["appdock_filemanager"] = function() return {} end
package.preload["appdock_appstore"] = function() return {} end
package.preload["appdock_youtube"] = function() return {} end
package.preload["appdock_ytmusic"] = function() return {} end
package.preload["appdock_draw"] = function() return {} end
package.preload["libs/libkoreader-lfs"] = function() return {} end
-- main.lua probes the optional keyboard module during settings normalization.
-- Lua 5.1 can retain a loading sentinel after that optional require failed.
package.loaded["appdock_keyboard"] = nil

-- main.lua already loaded a compact DAppManager fake. Reload only this module
-- after its dependencies have been supplied, leaving the persisted-setting
-- checks above independent from UI-manager implementation details.
package.loaded["appdock_dapps"] = nil
package.preload["appdock_dapps"] = nil
local DAppManager = dofile(plugin_dir .. "appdock_dapps.lua")
local wizard_log = { completed = 0, rebuilds = 0, simple = {}, layout = {}, workspace = {} }
local wizard_appdock = {
    settings = {
        tbs_account = { username = "" },
        layout = { search_enabled = false },
        workspace = { restore_enabled = false },
    },
    getFeaturePages = function() return {} end,
    isSimpleModeEnabled = function() return false end,
    setSimpleModeOption = function(_, key, enabled) wizard_log.simple[key] = enabled; return true end,
    setLauncherLayout = function(_, changes) wizard_log.layout.search_enabled = changes.search_enabled; return true end,
    setWorkspaceRestoreEnabled = function(_, enabled) wizard_log.workspace.restore_enabled = enabled; return true end,
    setTBSAccount = function() return true end,
    completeSetupAssistant = function() wizard_log.completed = wizard_log.completed + 1; return true end,
}
local wizard_manager = setmetatable({ appdock = wizard_appdock }, DAppManager)
function wizard_manager:showSettingsNotice(text) wizard_log.notice = text end
local wizard_context = {
    requestRebuild = function(kind)
        wizard_log.rebuilds = wizard_log.rebuilds + 1
        wizard_log.rebuild_kind = kind
    end,
}
local function current_dialog()
    return log.shown[#log.shown]
end

local shown_before_wizard = #log.shown
assert(wizard_manager:showSetupAssistant({}, wizard_context, false), "The Settings callback must open the manual setup session")
local start_dialog = current_dialog()
assert(#log.shown == shown_before_wizard + 1 and start_dialog.title == "AppDock setup wizard", "The manual wizard must render its start dialog on the next UI turn")
assert(wizard_manager:showSetupAssistant({}, wizard_context, false) == false, "A second Settings tap must not stack another setup wizard")
start_dialog.buttons[1][1].callback()
local appearance_dialog = current_dialog()
assert(appearance_dialog.title:find("Setup 1/4", 1, true), "Starting the wizard must advance to the Android-style appearance step")
appearance_dialog.buttons[3][1].callback()
local search_dialog = current_dialog()
assert(search_dialog.title:find("Setup 2/4", 1, true), "A step transition must wait for the closed dialog before showing the next step")
search_dialog.buttons[3][1].callback()
local workspace_dialog = current_dialog()
assert(workspace_dialog.title:find("Setup 3/4", 1, true), "Skipping search must retain the workspace step")
workspace_dialog.buttons[3][1].callback()
local account_dialog = current_dialog()
assert(account_dialog.title:find("Setup 4/4", 1, true), "The final account step must be reachable after the preceding modal closes")
account_dialog.buttons[1][1].callback()
assert(wizard_log.completed == 1 and wizard_log.rebuilds == 1 and wizard_log.rebuild_kind == "ui", "Finishing manual setup must persist completion and refresh Settings exactly once")
assert(wizard_log.notice and wizard_log.notice:find("setup is complete", 1, true), "Completion notice must be shown only after the final dialog closes")

-- A cancel/outside-close must release the session guard without completing
-- setup, so the Settings row is reliably usable again.
assert(wizard_manager:showSetupAssistant({}, wizard_context, false), "The setup wizard must be reopenable after completion")
local dismissed_dialog = current_dialog()
require("ui/uimanager"):close(dismissed_dialog)
assert(wizard_manager:showSetupAssistant({}, wizard_context, false), "Closing the modal through the UI lifecycle must release the setup-session guard")
current_dialog().buttons[2][1].callback()
assert(wizard_log.completed == 1, "Cancelling a manual wizard must never mark setup as completed")

-- Preserve the legacy automatic page route for older callers, while keeping
-- it separate from the current boot/update-dialog policy.
wizard_appdock.getFeaturePages = function() return { { title = "Legacy page", text = "Compatible" } } end
assert(wizard_manager:showSetupAssistant(nil, nil, true), "The legacy automatic setup route must remain available")
local legacy_dialog = current_dialog()
assert(legacy_dialog.title:find("Legacy page", 1, true), "Legacy automatic callers must still receive feature pages")
legacy_dialog.buttons[1][1].callback()
assert(wizard_log.completed == 2, "Completing the legacy page route must retain its persisted-completion contract")

local dapps_source = assert(io.open(plugin_dir .. "appdock_dapps.lua", "rb")):read("*a")
assert(dapps_source:find('title = _("Setup Wizard")', 1, true)
    and dapps_source:find("self.appdock:showSetupAssistant(instance, context)", 1, true),
    "Settings must expose Setup Wizard and route its callback through the AppDock entry point")
print("Setup assistant test: OK")
