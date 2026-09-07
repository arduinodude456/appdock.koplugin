-- Flat AppDock grid editor.
-- This intentionally uses one InputContainer and a small set of stable
-- FrameContainer rows. It does not use KOReader dialogs or nested controls.
local Blitbuffer = require("ffi/blitbuffer")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Font = require("ui/font")
local _ = require("gettext")

local scale = function(n) return math.max(1, math.floor((n or 0) * (Screen:getWidth() / 600))) end
local ink = Blitbuffer.COLOR_BLACK
local paper = Blitbuffer.COLOR_WHITE

local GridEditor = InputContainer:extend{ appdock = nil, parent_home = nil }

function GridEditor:init()
    self.width = math.min(Screen:getWidth() - scale(28), scale(520))
    self.row_width = self.width - scale(28)
    self.rows = {}
    self.ges_events = {}
    self:_addHeading(_("Widgets"))
    local widgets = {
        { id = "clock", title = _("Clock in status bar") },
        { id = "status", title = _("Device status card") },
        { id = "reading_hint", title = _("Current book card") },
    }
    for _, widget in ipairs(widgets) do
        self:_addToggle(widget.title, self.appdock.settings.widgets[widget.id], function()
            self.appdock:toggleWidget(widget.id)
        end)
    end
    self:_addHeading(_("Apps"))
    local catalog = type(self.appdock.getVisibleAppCatalog) == "function"
        and self.appdock:getVisibleAppCatalog() or self.appdock:getAppCatalog()
    local apps = {}
    for _, app in pairs(catalog) do table.insert(apps, app) end
    table.sort(apps, function(a, b) return a.title:lower() < b.title:lower() end)
    for _, app in ipairs(apps) do
        self:_addToggle(app.title, self.appdock:isPinned(app.id), function()
            self.appdock:togglePinned(app.id)
        end)
    end
    self:_addAction(_("Close"), function() UIManager:close(self) end)
    local content = { TextWidget:new{ text = _("Arrange apps"), face = Font:getFace("cfont", scale(20)), fgcolor = ink, padding = 0 }, VerticalSpan:new{ height = scale(10) } }
    for _, row in ipairs(self.rows) do
        table.insert(content, row.widget)
        table.insert(content, VerticalSpan:new{ height = scale(5) })
    end
    self.content = VerticalGroup:new(content)
    local content_height = self.content:getSize().h
    self.height = math.min(Screen:getHeight() - scale(24), content_height + scale(28))
    self.dimen = Geom:new{
        x = math.floor((Screen:getWidth() - self.width) / 2),
        y = math.floor((Screen:getHeight() - self.height) / 2),
        w = self.width, h = self.height,
    }
    self[1] = FrameContainer:new{
        width = self.width, height = self.height, padding = scale(14),
        bordersize = scale(2), color = ink, background = paper,
        radius = scale(20), self.content,
    }
end

function GridEditor:_addHeading(text)
    local widget = TextWidget:new{ text = text, face = Font:getFace("smallinfofont", scale(12)), fgcolor = Blitbuffer.COLOR_DARK_GRAY, padding = 0 }
    table.insert(self.rows, { widget = widget, height = scale(23), heading = true })
end

function GridEditor:_addToggle(text, enabled, callback)
    self:_addRow(text .. (enabled and "    ON" or "    OFF"), callback)
end

function GridEditor:_addAction(text, callback)
    self:_addRow(text, callback)
end

function GridEditor:_addRow(text, callback)
    local index = #self.rows + 1
    local row = FrameContainer:new{
        width = self.row_width, height = scale(40), padding = scale(9),
        bordersize = scale(1), color = ink, background = paper,
        radius = scale(10),
        TextWidget:new{ text = text, face = Font:getFace("smallinfofont", scale(13)), fgcolor = ink, padding = 0 },
    }
    table.insert(self.rows, { widget = row, height = scale(40), callback = callback })
    self.ges_events["TapGridRow" .. index] = {
        GestureRange:new{ ges = "tap", range = Geom:new{ x = 0, y = 0, w = self.row_width, h = scale(40) } },
    }
    self["onTapGridRow" .. index] = function()
        if callback then callback() end
        UIManager:setDirty(self, "ui")
        return true
    end
end

function GridEditor:paintTo(bb, x, y)
    local row_y = y + scale(14) + scale(30)
    for index, row in ipairs(self.rows) do
        local range_group = self.ges_events["TapGridRow" .. index]
        if range_group then
            local range = range_group[1].range
            range.x, range.y = x + scale(14), row_y
            range.w, range.h = self.row_width, row.height
        end
        row_y = row_y + row.height + scale(5)
    end
    -- The stable child tree is painted exactly once by InputContainer.
    return InputContainer.paintTo(self, bb, x, y)
end

function GridEditor:onCloseWidget()
    UIManager:close(self)
    return true
end

local AppDockManager = {}
function AppDockManager:show(args)
    local editor = GridEditor:new{ appdock = args.appdock, parent_home = args.parent_home }
    UIManager:show(editor)
end
return AppDockManager
