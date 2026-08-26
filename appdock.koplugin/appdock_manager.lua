--[[--
Scrollable configuration dialog for AppDock.
--]]--

local ButtonDialog = require("ui/widget/buttondialog")
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

    local function refresh()
        UIManager:close(dialog)
        UIManager:nextTick(function()
            self:showDialog()
        end)
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
                text = string.format("%s: %s", stateLabel(appdock.settings.widgets[widget.id]), widget.title),
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
                text = string.format("%s: %s", stateLabel(appdock:isStoreWidgetEnabled(widget.widget_id)), widget.title),
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
                text = string.format("%s: %s", stateLabel(appdock:isPinned(app.id)), app.title),
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
