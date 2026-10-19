-- Regression for the long-press -> Add another App -> Create app group flow.
local plugin_dir = os.getenv("APPDOCK_PLUGIN_DIR") or "./appdock.koplugin/"
if plugin_dir:sub(-1) ~= "/" then plugin_dir = plugin_dir .. "/" end

local function identity(text) return text end
package.preload["gettext"] = function() return identity end

local UIManager = { closed = {}, last_shown = nil }
function UIManager:close(widget)
    assert(widget, "UIManager:close must receive a dialog")
    assert(not self.closed[widget], "a dialog was closed twice")
    self.closed[widget] = true
end
function UIManager:nextTick(callback) callback() end
function UIManager:show(widget)
    assert(not self.closed[widget], "a closed dialog must not be shown again")
    self.last_shown = widget
end
package.preload["ui/uimanager"] = function() return UIManager end

local ButtonDialog = {}
function ButtonDialog:new(args)
    args = args or {}
    args.is_button_dialog = true
    return args
end
local InfoMessage = { new = function(_, args) return args end }
package.preload["appdock_dialogs"] = function()
    return { ButtonDialog = ButtonDialog, InfoMessage = InfoMessage }
end
package.preload["appdock_keyboard"] = function()
    return { new = function(_, args) return args end }
end

local AppDockManager = dofile(plugin_dir .. "appdock_manager.lua")
local alpha = { id = "dapp:alpha", title = "Alpha", is_group = false }
local beta = { id = "dapp:beta", title = "Beta", is_group = false }
local group_record
local pinned_apps = { alpha, beta }
local appdock = {
    settings = { widgets = { clock = false, status = false, reading_hint = false } },
    getPinnedApps = function() return pinned_apps end,
    getVisibleAppCatalog = function() return { alpha, beta } end,
    getAppCatalog = function() return { [alpha.id] = alpha, [beta.id] = beta } end,
    getStoreWidgets = function() return {} end,
    isSimpleModeEnabled = function() return false end,
    isPinned = function(_, id) return id == alpha.id or id == beta.id end,
    isStoreWidgetEnabled = function() return false end,
    getDAppManager = function() return nil end,
    createAppGroup = function(_, title, members)
        assert(#members == 2, "the selected apps must reach createAppGroup")
        group_record = { id = "folder:1", title = title, apps = { members[1], members[2] } }
        pinned_apps = { { id = group_record.id, group_id = group_record.id, title = group_record.title, is_group = true } }
        return true, group_record.id
    end,
    isAppGroup = function(_, id) return group_record ~= nil and id == group_record.id end,
    getAppGroup = function() return group_record end,
}

local manager = setmetatable({
    appdock = appdock,
    selected_app = alpha,
}, { __index = AppDockManager })

local function findButton(dialog, predicate)
    for _, row in ipairs(dialog.buttons or {}) do
        for _, button in ipairs(row) do
            if predicate(button) then return button end
        end
    end
    error("Expected button was not found")
end

manager:showDialog()
local selected_app_dialog = UIManager.last_shown
findButton(selected_app_dialog, function(button) return button.text == "Add another app" end).callback()
local manager_dialog = UIManager.last_shown
findButton(manager_dialog, function(button) return button.text == "Create app group" end).callback()

local create_dialog = UIManager.last_shown
findButton(create_dialog, function(button) return button.text == "Add: Alpha" end).callback()
create_dialog = UIManager.last_shown
findButton(create_dialog, function(button) return button.text == "Add: Beta" end).callback()
create_dialog = UIManager.last_shown
local create_button = findButton(create_dialog, function(button)
    return button.text == "Create app group (2 apps)"
end)
assert(create_button.enabled, "Create must be enabled for two selected apps")
create_button.callback()
assert(group_record and group_record.id == "folder:1", "the group must be created successfully")
assert(UIManager.last_shown.title == "Manage app group", "the new group management dialog must open")

findButton(UIManager.last_shown, function(button) return button.text == "Manage group apps" end).callback()
local members_dialog = UIManager.last_shown
assert(findButton(members_dialog, function(button) return button.text == "Remove: Alpha" end),
    "the group member editor must build translated Remove labels without shadowing gettext")
findButton(members_dialog, function(button) return button.text == "Cancel" end).callback()
findButton(UIManager.last_shown, function(button) return button.text == "Done" end).callback()
manager.selected_app = nil
manager:showDialog()
assert(findButton(UIManager.last_shown, function(button) return button.text == "Manage group: App group" end),
    "the manager home must build its existing-group entry without shadowing gettext")
print("appdock_manager group creation test: OK")
