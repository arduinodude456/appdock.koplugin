--[[--
Scrollable configuration dialog for AppDock.
--]]--

local ButtonDialog = require("appdock_ui").ButtonDialog
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local AppDockManager = {}

local function stateLabel(enabled)
    return enabled and _("Added") or _("Add")
end

function AppDockManager:show(args)
    local manager = setmetatable(args, { __index = self })
    manager:showDialog()
end

function AppDockManager:showDialog()
    local appdock = self.appdock
    local buttons = {}
    local dialog

    -- Keep one manager surface alive while toggling items. Rebuilding and
    -- closing a native-backed popup from inside its own gesture callback can
    -- race KOReader's renderer on Android/eInk builds.
    local function refresh()
        UIManager:setDirty(nil, "ui")
    end

    table.insert(buttons, {
        {
            text = _("Widgets"),
            enabled = false,
        },
    })

    local widgets = {
        { id = "clock", title = _("Clock in status bar") },
        { id = "status", title = _("Device status card") },
        { id = "reading_hint", title = _("Current book card") },
    }
    for _, widget in ipairs(widgets) do
        table.insert(buttons, {
            {
                text = widget.title, switch = true, value = appdock.settings.widgets[widget.id],
                callback = function()
                    appdock:toggleWidget(widget.id)
                    refresh()
                end,
            },
        })
    end

    table.insert(buttons, {
        {
            text = _("Store widgets"),
            enabled = false,
        },
    })

    local widgets = appdock:getStoreWidgets()

    for _, widget in ipairs(widgets) do
        table.insert(buttons, {
            {
                text = widget.title, switch = true, value = appdock:isStoreWidgetEnabled(widget.widget_id),
                callback = function()
                    appdock:toggleStoreWidget(widget.widget_id)
                    refresh()
                end,
            },
        })
    end

    table.insert(buttons, {
        {
            text = _("Apps"),
            enabled = false,
        },
    })

    local catalog = type(appdock.getVisibleAppCatalog) == "function" and appdock:getVisibleAppCatalog() or appdock:getAppCatalog()
    local apps = {}
    for _, app in pairs(catalog) do
        table.insert(apps, app)
    end
    table.sort(apps, function(left, right)
        return left.title:lower() < right.title:lower()
    end)

    for _, app in ipairs(apps) do
        table.insert(buttons, {
            {
                text = app.title, switch = true, value = appdock:isPinned(app.id),
                callback = function()
                    appdock:togglePinned(app.id)
                    refresh()
                end,
            },
        })
    end

    table.insert(buttons, {
        {
            text = _("Close"),
            callback = function()
                UIManager:close(dialog)
            end,
        },
    })

    dialog = ButtonDialog:new{
        title = _("Manage AppDock"),
        buttons = buttons,
        rows_per_page = { 5, 6, 7 },
    }
    UIManager:show(dialog)
end

return AppDockManager
