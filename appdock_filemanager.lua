--[[--
Own graphical File Manager for AppDock. It deliberately lists the file system
itself instead of delegating visual control to KOReader's FileManager, while
using ReaderUI for the only safe document-opening path.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local DocumentRegistry = require("document/documentregistry")
local Theme = require("appdock_theme")
local FileManagerUtil = require("apps/filemanager/filemanagerutil")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local InfoMessage = require("ui/widget/infomessage")
local OverlapGroup = require("ui/widget/overlapgroup")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
-- KOReader bundles LuaFileSystem under this name; the fallback keeps standalone
-- Lua-based checks usable without changing the device code path.
local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
if not ok_lfs then lfs = require("lfs") end

local Screen = Device.screen
local FileBrowser = {}
FileBrowser.__index = FileBrowser

local function scale(value)
    return Screen:scaleBySize(value)
end

local function color(r, g, b, grayscale)
    if Screen:isColorEnabled() then return Blitbuffer.ColorRGB32(r, g, b, 0xFF) end
    return grayscale
end

local PALETTE = {
    background = color(250, 248, 255, Blitbuffer.COLOR_WHITE),
    surface = color(242, 240, 247, Blitbuffer.COLOR_LIGHT_GRAY),
    primary = color(214, 227, 255, Blitbuffer.COLOR_GRAY_8),
    secondary = color(235, 225, 255, Blitbuffer.COLOR_LIGHT_GRAY),
    on_primary = color(23, 59, 111, Blitbuffer.COLOR_DARK_GRAY),
    on_surface = color(31, 29, 36, Blitbuffer.COLOR_BLACK),
    on_variant = color(76, 73, 84, Blitbuffer.COLOR_DARK_GRAY),
}

local function applyTheme(appdock)
    local palette = Theme.getPalette(appdock)
    PALETTE.background = palette.background
    PALETTE.surface = palette.surface
    PALETTE.primary = palette.primary
    PALETTE.secondary = palette.secondary
    PALETTE.on_primary = palette.on_primary
    PALETTE.on_surface = palette.on_surface
    PALETTE.on_variant = palette.on_variant
end

local function emptySizedWidget(width, height)
    return CenterContainer:new{
        dimen = Geom:new{ w = width, h = height },
        HorizontalSpan:new{ width = 0 },
    }
end

local ToolbarButton = InputContainer:extend{
    title = nil,
    callback = nil,
    width = nil,
    height = nil,
    background = nil,
    foreground = nil,
    dimen = nil,
}

local FileRow = InputContainer:extend{
    title = nil,
    subtitle = nil,
    callback = nil,
    width = nil,
    height = nil,
    background = nil,
    foreground = nil,
    dimen = nil,
}

function ToolbarButton:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self[1] = FrameContainer:new{
        width = self.width,
        height = self.height,
        padding = 0,
        bordersize = 0,
        radius = math.floor(self.height * 0.32),
        background = self.background or PALETTE.surface,
        CenterContainer:new{
            dimen = Geom:new{ w = self.width, h = self.height },
            TextWidget:new{
                text = self.title or "",
                face = Font:getFace("smallinfofont", scale(11)),
                fgcolor = self.foreground or PALETTE.on_surface,
                bold = true,
                max_width = self.width - scale(10),
            },
        },
    }
    self.ges_events = {
        TapFileToolbar = { GestureRange:new{ ges = "tap", range = self.dimen } },
    }
end

function ToolbarButton:paintTo(bb, x, y)
    local range = self.ges_events.TapFileToolbar[1].range
    range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    return InputContainer.paintTo(self, bb, x, y)
end

function ToolbarButton:onTapFileToolbar()
    if self.callback then self.callback() end
    return true
end

function FileRow:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local title = TextWidget:new{
        text = self.title or "",
        face = Font:getFace("smallinfofont", scale(13)),
        fgcolor = self.foreground or PALETTE.on_surface,
        bold = true,
        max_width = self.width - scale(26),
    }
    local subtitle = TextWidget:new{
        text = self.subtitle or "",
        face = Font:getFace("smallinfofont", scale(10)),
        fgcolor = PALETTE.on_variant,
        max_width = self.width - scale(26),
    }
    self[1] = FrameContainer:new{
        width = self.width,
        height = self.height,
        padding = 0,
        bordersize = 0,
        radius = scale(12),
        background = self.background or PALETTE.surface,
        CenterContainer:new{
            dimen = Geom:new{ w = self.width, h = self.height },
            VerticalGroup:new{
                title,
                VerticalSpan:new{ width = scale(2) },
                subtitle,
            },
        },
    }
    self.ges_events = {
        TapFileRow = { GestureRange:new{ ges = "tap", range = self.dimen } },
    }
end

function FileRow:paintTo(bb, x, y)
    local range = self.ges_events.TapFileRow[1].range
    range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    return InputContainer.paintTo(self, bb, x, y)
end

function FileRow:onTapFileRow()
    if self.callback then self.callback() end
    return true
end

local function basename(path)
    return path and path:match("([^/]+)$") or path
end

local function parentPath(path)
    if not path or path == "/" then return "/" end
    local parent = path:match("^(.*)/[^/]+$")
    if not parent or parent == "" then return "/" end
    return parent
end

local function humanSize(size)
    size = tonumber(size) or 0
    if size < 1024 then return string.format("%d B", size) end
    if size < 1024 * 1024 then return string.format("%.1f KB", size / 1024) end
    return string.format("%.1f MB", size / (1024 * 1024))
end

local function sortEntries(entries)
    table.sort(entries, function(left, right)
        if left.is_dir ~= right.is_dir then return left.is_dir end
        return left.name:lower() < right.name:lower()
    end)
end

function FileBrowser:new()
    return setmetatable({}, self)
end

function FileBrowser:_ensureState(instance)
    instance.file_browser = instance.file_browser or {
        path = FileManagerUtil.getHomeFolder(),
        error = nil,
        entries = nil,
    }
    return instance.file_browser
end

function FileBrowser:_readEntries(path)
    local entries = {}
    local ok, iterator, directory_object = pcall(lfs.dir, path)
    if not ok then return nil, _("This folder cannot be read.") end
    for name in iterator, directory_object do
        if name ~= "." and name ~= ".." then
            local fullpath = path == "/" and ("/" .. name) or (path .. "/" .. name)
            local attributes_ok, attributes = pcall(lfs.attributes, fullpath)
            if attributes_ok and attributes and (attributes.mode == "directory" or attributes.mode == "file") then
                table.insert(entries, {
                    name = name,
                    path = fullpath,
                    is_dir = attributes.mode == "directory",
                    size = attributes.size,
                    supported = attributes.mode == "file" and DocumentRegistry:hasProvider(fullpath),
                    is_lua = attributes.mode == "file" and fullpath:lower():match("%.lua$") ~= nil,
                })
            end
        end
    end
    sortEntries(entries)
    return entries
end

function FileBrowser:refresh(instance, context)
    local state = self:_ensureState(instance)
    local entries, err = self:_readEntries(state.path)
    state.entries = entries
    state.error = err
    context.requestRebuild("ui")
end

function FileBrowser:enterDirectory(instance, context, path)
    local state = self:_ensureState(instance)
    state.path = path
    self:refresh(instance, context)
end

function FileBrowser:openLuaFile(instance, context, path)
    local manager = context.manager
    if not manager or not manager.openDAppFile then
        UIManager:show(InfoMessage:new{ text = _("NightLua is not available in this AppDock session.") })
        return
    end
    local ok, err = manager:openDAppFile("night_lua", path)
    if not ok then
        UIManager:show(InfoMessage:new{ text = _("Install NightLua from AppStore first.\n\n") .. tostring(err or "") })
    end
end

function FileBrowser:openFile(instance, context, path, supported)
    if not supported then
        UIManager:show(InfoMessage:new{ text = _("KOReader has no reader engine for this file type.") })
        return
    end
    UIManager:close(context.host)
    UIManager:nextTick(function()
        local ReaderUI = require("apps/reader/readerui")
        ReaderUI:showReader(path)
    end)
end

function FileBrowser:buildPane(instance, context)
    applyTheme(context.manager and context.manager.appdock)
    local state = self:_ensureState(instance)
    if not state.entries and not state.error then
        state.entries, state.error = self:_readEntries(state.path)
    end
    local pane = WidgetContainer:new{ dimen = Geom:new{ w = context.dimen.w, h = context.dimen.h } }
    local width, height = context.dimen.w, context.dimen.h
    local margin, gap = scale(14), scale(8)
    local action_y, action_height = scale(54), scale(38)
    -- Keep a real visual gap between the final toolbar row and the scroller.
    -- The old 84px reservation started the list underneath a 34px high button.
    local toolbar_height = action_y + action_height + scale(10)
    local row_height = scale(64)
    local small_width = math.max(scale(46), math.floor((width - 2 * margin - 2 * gap) / 3))
    local list_width = width - 2 * margin
    local list = VerticalGroup:new{}

    if state.error then
        table.insert(list, FileRow:new{
            title = _("Folder unavailable"), subtitle = state.error,
            width = list_width, height = row_height,
            background = PALETTE.secondary, foreground = PALETTE.on_surface,
        })
    elseif #state.entries == 0 then
        table.insert(list, FileRow:new{
            title = _("This folder is empty"), subtitle = state.path,
            width = list_width, height = row_height,
            background = PALETTE.surface, foreground = PALETTE.on_surface,
        })
    else
        for entry_index, entry in ipairs(state.entries) do
            local title = entry.is_dir and ("Folder · " .. entry.name) or entry.name
            local subtitle
            if entry.is_dir then
                subtitle = entry.path
            elseif entry.is_lua then
                subtitle = _("Open in NightLua") .. " · " .. humanSize(entry.size)
            elseif entry.supported then
                subtitle = _("Open document") .. " · " .. humanSize(entry.size)
            else
                subtitle = _("Unsupported file") .. " · " .. humanSize(entry.size)
            end
            table.insert(list, FileRow:new{
                title = title,
                subtitle = subtitle,
                width = list_width,
                height = row_height,
                background = entry.is_dir and PALETTE.primary or PALETTE.surface,
                foreground = entry.is_dir and PALETTE.on_primary or PALETTE.on_surface,
                callback = function()
                    if entry.is_dir then
                        self:enterDirectory(instance, context, entry.path)
                    elseif entry.is_lua then
                        self:openLuaFile(instance, context, entry.path)
                    else
                        self:openFile(instance, context, entry.path, entry.supported)
                    end
                end,
            })
            table.insert(list, VerticalSpan:new{ width = gap })
        end
    end

    local visible_list_height = math.max(scale(80), height - toolbar_height - margin)
    local scroller = ScrollableContainer:new{
        dimen = Geom:new{ w = list_width + ScrollableContainer:getScrollbarWidth(), h = visible_list_height },
        show_parent = context.host,
        list,
    }
    scroller.overlap_offset = { margin, toolbar_height }
    pane.layout = {
        action_y = action_y,
        action_height = action_height,
        toolbar_height = toolbar_height,
        scroller_y = toolbar_height,
        scroller_height = visible_list_height,
        gap = gap,
    }

    pane[1] = OverlapGroup:new{
        dimen = pane.dimen,
        allow_mirroring = false,
        FrameContainer:new{
            width = width, height = height, padding = 0, bordersize = 0,
            background = PALETTE.background,
            emptySizedWidget(width, height),
        },
        TextWidget:new{
            text = _("Files"), face = Font:getFace("cfont", scale(20)),
            fgcolor = PALETTE.on_surface, bold = true,
            overlap_offset = { margin, scale(8) },
        },
        TextWidget:new{
            text = state.path, face = Font:getFace("smallinfofont", scale(11)),
            fgcolor = PALETTE.on_variant, max_width = width - 2 * margin,
            overlap_offset = { margin, scale(36) },
        },
        ToolbarButton:new{
            title = _("Up"), width = small_width, height = action_height,
            background = PALETTE.surface, callback = function() self:enterDirectory(instance, context, parentPath(state.path)) end,
            overlap_offset = { margin, action_y },
        },
        ToolbarButton:new{
            title = _("Home"), width = small_width, height = action_height,
            background = PALETTE.secondary, callback = function() self:enterDirectory(instance, context, FileManagerUtil.getHomeFolder()) end,
            overlap_offset = { margin + small_width + gap, action_y },
        },
        ToolbarButton:new{
            title = _("Refresh"), width = small_width, height = action_height,
            background = PALETTE.primary, foreground = PALETTE.on_primary, callback = function() self:refresh(instance, context) end,
            overlap_offset = { margin + (small_width + gap) * 2, action_y },
        },
        scroller,
    }
    return pane
end

return FileBrowser
