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

    local function moveRow(label, position, total, move_up, move_down)
        return {
            { text = "↑", enabled = position > 1, callback = function() if position > 1 then move_up(); refresh() end end },
            { text = string.format("%d/%d  %s", position, total, label), enabled = false },
            { text = "↓", enabled = position < total, callback = function() if position < total then move_down(); refresh() end end },
        }
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
            text = _("Arrange store widgets"),
            enabled = false,
        },
    })

    local widgets = appdock:getStoreWidgets()
    for position, widget in ipairs(widgets) do
        table.insert(buttons, moveRow(widget.title, position, #widgets,
            function() appdock:moveStoreWidget(widget.widget_id, -1) end,
            function() appdock:moveStoreWidget(widget.widget_id, 1) end))
    end

    table.insert(buttons, {
        {
            text = _("Store widgets"),
            enabled = false,
        },
    })

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
            text = _("Arrange apps"),
            enabled = false,
        },
    })

    local pinned = appdock:getPinnedApps()
    for position, app in ipairs(pinned) do
        table.insert(buttons, moveRow(app.title, position, #pinned,
            function() appdock:movePinned(app.id, -1) end,
            function() appdock:movePinned(app.id, 1) end))
    end

    table.insert(buttons, {
        {
            text = _("Apps"),
            enabled = false,
        },
    })

    local catalog = appdock:getAppCatalog()
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
