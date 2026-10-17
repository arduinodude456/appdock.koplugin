local plugin_dir = os.getenv("APPDOCK_PLUGIN_DIR") or "./appdock.koplugin/"
package.path = plugin_dir .. "?.lua;" .. package.path

local saves = 0
local reader_settings = {}
_G.G_reader_settings = {
    readSetting = function(_, key, fallback) return reader_settings[key] or fallback end,
    saveSetting = function(_, key, value) reader_settings[key] = value end,
}
package.preload["gettext"] = function() return function(text) return text end end
package.preload["socket.url"] = function()
    return {
        parse = function(value)
            local scheme, host = tostring(value):match("^(https?)://([^/%?#]+)")
            return scheme and { scheme = scheme, host = host } or nil
        end,
    }
end
package.preload["ui/uimanager"] = function()
    return {
        show = function() end,
        close = function() end,
        scheduleIn = function() end,
        nextTick = function(_, callback) if callback then callback() end end,
    }
end
package.preload["appdock_dialogs"] = function()
    local function constructor(args)
        args = args or {}
        function args:getInputText() return self.input or "" end
        function args:onShowKeyboard() end
        return args
    end
    return {
        ButtonDialog = { new = function(_, args) return constructor(args) end },
        InputDialog = { new = function(_, args) return constructor(args) end },
        InfoMessage = { new = function(_, args) return constructor(args) end },
    }
end

local Account = require("appdock_tbs_account")

local raw = {
    endpoint = "https://example.test/functions/v1/tbs-account/",
    publishable_key = "sb_publishable_example",
    account_id = "e7c931e2-0a70-4a53-96f3-e7947939f7b9",
    device_id = "tbs_abcdefghijklmnopqrstuv",
    device_secret = "abcdefghijklmnopqrstuvwxzy0123456789AB",
    display_name = " Reader ",
    sync_revision = 4,
}
reader_settings.appdock_tbs_session = raw
local normalized = Account._test.normalize(raw)
assert(normalized.endpoint == "https://example.test/functions/v1/tbs-account", "endpoint must be canonicalised")
assert(normalized.display_name == "Reader", "display name must be trimmed")
assert(normalized.account_id == raw.account_id, "valid account id must survive")

local appdock = {
    settings = {
        tbs_account = { enabled = true, username = "Reader", display_name = "Reader" },
        pinned_apps = { "system:library", "dapp:youtube" },
        widgets = { clock = true },
        theme = { selected = "lavender" },
        layout = { app_spacing = 16 },
        quick_settings = { tiles = { "wifi" } },
        youtube = { fps = 12, output_dir = "/mnt/onboard/videos" },
        wallpaper = { enabled = true, source = "appdock_default", path = "/home/device/appdock/assets/wallpaper/appdock_default.svg" },
        lockscreen = { enabled = true, secret_hash = "must-not-leak" },
        dapp_permissions = { dchat = { background = true } },
        store = { installed = {
            dock_update = { kind = "dapp", source_path = "dock_update.lua", file = "/private/dock_update.lua", version = "1.2.0" },
            weather = { kind = "widget", source_path = "weather_widget.lua", file = "/private/weather.lua", version = "1.0.0" },
        } },
    },
    path = "/home/device/appdock.koplugin",
    _saveSettings = function() saves = saves + 1 end,
}
assert(Account.isSignedIn(appdock), "a complete opaque device identity must be signed in")
local snapshot = Account._test.buildSnapshot(appdock)
assert(snapshot.settings.pinned_apps[2] == "dapp:youtube", "launcher state must be in the snapshot")
assert(snapshot.settings.youtube.output_dir == nil, "absolute device-local paths must not be exported")
assert(snapshot.settings.wallpaper.source == "appdock_default" and snapshot.settings.wallpaper.path == nil, "the bundled default wallpaper travels as portable metadata only")
assert(snapshot.settings.lockscreen == nil, "lockscreen secrets must never be exported")
assert(snapshot.settings.install_manifest[1].file == nil, "installation manifest must not upload local paths")
assert(#snapshot.settings.install_manifest == 2, "all installed-app records need a compact manifest")

local restored = {
    revision = 9,
    personalization = { app_usage = { youtube = 2 } },
    settings = {
        pinned_apps = { "dapp:app_store" },
        layout = { app_spacing = 24 },
        wallpaper = { enabled = true, source = "appdock_default" },
        install_manifest = { { id = "dock_update", kind = "dapp", source_path = "dock_update.lua", version = "1.2.0" } },
    },
}
local ok, err = Account.applySnapshot(appdock, restored)
assert(ok, err)
assert(appdock.settings.pinned_apps[1] == "dapp:app_store", "restored launcher state must be applied")
assert(appdock.settings.wallpaper.path == "/home/device/appdock.koplugin/assets/wallpaper/appdock_default.svg", "the bundled background must be reconstructed from the receiver's local plugin path")
assert(reader_settings.appdock_tbs_session.sync_revision == 9, "cloud revision must be retained after restore")
assert(reader_settings.appdock_tbs_session.device_secret == raw.device_secret, "device secret must be kept in a separate local setting group")
assert(#reader_settings.appdock_tbs_session.pending_installations == 1, "stored installations must remain available for AppStore restoration")
assert(appdock.settings.tbs_account.device_secret == nil, "the transferable AppDock settings must not hold the device secret")
assert(saves > 0, "account operations must persist locally")

print("TBS account test: OK")
