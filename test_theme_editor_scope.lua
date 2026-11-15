local plugin_dir = os.getenv("APPDOCK_PLUGIN_DIR") or "appdock.koplugin/"
local source_file = assert(io.open(plugin_dir .. "appdock_dapps.lua", "rb"))
local source = source_file:read("*a")
source_file:close()

local editor_source = assert(source:match("function DAppManager:showThemeEditor[%s%S]-\nend"), "Theme editor implementation must be present")
local shown
local environment = {
    DAppManager = {},
    Theme = {
        getThemeList = function()
            return { { id = "aurora", title = "Aurora", primary = "#7CF2C9", gradient = true } }
        end,
        resolveDefinition = function() return "aurora" end,
    },
    _ = function(text) return "translated:" .. text end,
    ButtonDialog = {
        new = function(_, args) return args end,
    },
    UIManager = {
        show = function(_, dialog) shown = dialog end,
        close = function() end,
    },
}
setmetatable(environment, { __index = _G })
local chunk = assert(loadstring(editor_source, "@appdock_dapps.lua:showThemeEditor"))
setfenv(chunk, environment)
chunk()

local manager = { appdock = { settings = {} } }
environment.DAppManager.showThemeEditor(manager, {}, {})
assert(shown and shown.title == "translated:Color themes", "Theme editor must open its translated color-theme dialog")
assert(shown.buttons[1][1].text:find("translated:gradient", 1, true), "Gradient label must call the gettext function rather than a shadowing loop variable")
print("theme-editor-gettext-ok")
