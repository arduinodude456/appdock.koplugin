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
    local selected_app = self.selected_app

    local function refresh()
        UIManager:close(dialog)
        UIManager:nextTick(function() self:showDialog() end)
    end

    local function closeAndShowHome()
        UIManager:close(dialog)
        if self.parent_home then
            -- Keep the existing homescreen widget alive. Closing and recreating
            -- it from a dialog callback can race KOReader's input/mutex cleanup.
            UIManager:nextTick(function()
                if self.parent_home.build then self.parent_home:build() end
                UIManager:setDirty(self.parent_home, "ui")
            end)
        end
    end

    local function showMoveMenu()
        local position, total = selected_app and appdock:getPinnedPosition(selected_app.id)
        if not position then return end
        -- ButtonDialog does not support stacking another modal reliably. Close
        -- the app menu first, then open the move menu on the next UI cycle.
        UIManager:close(dialog)
        UIManager:nextTick(function()
            local move_dialog
            local function move(delta)
                appdock:movePinned(selected_app.id, delta)
                UIManager:close(move_dialog)
                UIManager:nextTick(function()
                    self.selected_app = selected_app
                    self:showDialog()
                end)
            end
            move_dialog = ButtonDialog:new{
                title = string.format(_("Move %s (%d/%d)"), selected_app.title, position, total),
                buttons = {
                    { { text = _("Move up"), enabled = position > 1, callback = function() move(-1) end },
                      { text = _("Move down"), enabled = position < total, callback = function() move(1) end } },
                    { { text = _("Move to first"), enabled = position > 1, callback = function() move(-(position - 1)) end },
                      { text = _("Move to last"), enabled = position < total, callback = function() move(total - position) end } },
                    { { text = _("Done"), callback = function()
                        UIManager:close(move_dialog)
                        UIManager:nextTick(function()
                            self.selected_app = selected_app
                            self:showDialog()
                        end)
                    end } },
                },
            }
            UIManager:show(move_dialog)
        end)
    end

    if selected_app and selected_app.id and appdock:isPinned(selected_app.id) then
        table.insert(buttons, { { text = string.format(_("Selected app: %s"), selected_app.title), enabled = false } })
        table.insert(buttons, { { text = _("Move app"), callback = showMoveMenu } })
        table.insert(buttons, { { text = _("Remove from homescreen"), callback = function()
            appdock:togglePinned(selected_app.id)
            closeAndShowHome()
        end } })
        table.insert(buttons, { { text = _("Add another app"), callback = function()
            self.selected_app = nil
            refresh()
        end } })
        table.insert(buttons, { { text = _("Done"), callback = closeAndShowHome } })
        dialog = ButtonDialog:new{
            title = _("Manage app"),
            buttons = buttons,
        }
        UIManager:show(dialog)
        return
    end

    table.insert(buttons, { { text = _("Widgets"), enabled = false } })
    local widgets = {
        { id = "clock", title = _("Clock in status bar") },
        { id = "status", title = _("Device status card") },
        { id = "reading_hint", title = _("Current book card") },
    }
    for _, widget in ipairs(widgets) do
        table.insert(buttons, { { text = string.format("%s: %s", stateLabel(appdock.settings.widgets[widget.id]), widget.title), callback = function()
            appdock:toggleWidget(widget.id)
            refresh()
        end } })
    end

    table.insert(buttons, { { text = _("Store widgets"), enabled = false } })
    for _, widget in ipairs(appdock:getStoreWidgets()) do
        table.insert(buttons, { { text = string.format("%s: %s", stateLabel(appdock:isStoreWidgetEnabled(widget.widget_id)), widget.title), callback = function()
            appdock:toggleStoreWidget(widget.widget_id)
            refresh()
        end } })
    end

    table.insert(buttons, { { text = _("Apps — tap to add or remove"), enabled = false } })
    local catalog = type(appdock.getVisibleAppCatalog) == "function" and appdock:getVisibleAppCatalog() or appdock:getAppCatalog()
    local apps = {}
    for _, app in pairs(catalog) do table.insert(apps, app) end
    table.sort(apps, function(left, right) return left.title:lower() < right.title:lower() end)
    for _, app in ipairs(apps) do
        table.insert(buttons, { { text = string.format("%s: %s", stateLabel(appdock:isPinned(app.id)), app.title), callback = function()
            appdock:togglePinned(app.id)
            refresh()
        end } })
    end

    table.insert(buttons, { { text = _("Close"), callback = function() UIManager:close(dialog) end } })
    dialog = ButtonDialog:new{
        title = _("Manage AppDock"),
        buttons = buttons,
        rows_per_page = { 5, 6, 7 },
    }
    UIManager:show(dialog)
end

return AppDockManager
