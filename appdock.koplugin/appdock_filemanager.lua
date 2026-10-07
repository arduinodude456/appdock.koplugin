--[[--
Own graphical File Manager for AppDock. The visual shell follows Google Files:
a search pill, recent files, category cards, storage shortcuts, and a clean
browse grid. Opening files still uses only KOReader's safe reader path or the
explicit AppDock DApp handlers.
--]]--
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local DocumentRegistry = require("document/documentregistry")
local Layout = require("appdock_layout")
local Theme = require("appdock_theme")
local FileManagerUtil = require("apps/filemanager/filemanagerutil")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local OverlapGroup = require("ui/widget/overlapgroup")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
if not ok_lfs then lfs = require("lfs") end

local Screen = Device.screen
local FileBrowser = {}
FileBrowser.__index = FileBrowser
local STORAGE_ROOT = "/mnt/onboard"
local STANDARD_FOLDERS = { "Downloads", "Documents", "Images", "Videos", "Audio" }

local function scale(value) return Screen:scaleBySize(value) end
local function color(r, g, b, grayscale)
    if Screen:isColorEnabled() then return Blitbuffer.ColorRGB32(r, g, b, 0xFF) end
    return grayscale
end
local PALETTE = {
    background = color(250, 248, 255, Blitbuffer.COLOR_WHITE),
    surface = color(255, 251, 247, Blitbuffer.COLOR_WHITE),
    surface_alt = color(246, 237, 231, Blitbuffer.COLOR_LIGHT_GRAY),
    primary = color(255, 224, 199, Blitbuffer.COLOR_GRAY_8),
    secondary = color(237, 225, 215, Blitbuffer.COLOR_LIGHT_GRAY),
    on_primary = color(91, 54, 32, Blitbuffer.COLOR_DARK_GRAY),
    on_surface = color(42, 35, 31, Blitbuffer.COLOR_BLACK),
    on_variant = color(104, 91, 83, Blitbuffer.COLOR_DARK_GRAY),
    outline = color(218, 204, 194, Blitbuffer.COLOR_LIGHT_GRAY),
}
local function applyTheme(appdock)
    local palette = Theme.getPalette(appdock)
    PALETTE.background, PALETTE.surface = palette.background, palette.surface
    PALETTE.primary, PALETTE.secondary = palette.primary, palette.secondary
    PALETTE.on_primary, PALETTE.on_surface = palette.on_primary, palette.on_surface
    PALETTE.on_variant = palette.on_variant
    PALETTE.outline = palette.outline or palette.surface_variant or palette.on_variant
end
local function emptySizedWidget(width, height)
    return CenterContainer:new{ dimen = Geom:new{ w = width, h = height }, HorizontalSpan:new{ width = 0 } }
end
local function basename(path) return path and path:match("([^/]+)$") or path end
local function parentPath(path)
    if not path or path == "/" then return "/" end
    local parent = path:match("^(.*)/[^/]+$")
    return not parent or parent == "" and "/" or parent
end
local function humanSize(size)
    size = tonumber(size) or 0
    if size < 1024 then return string.format("%d B", size) end
    if size < 1024 * 1024 then return string.format("%.1f KB", size / 1024) end
    if size < 1024 * 1024 * 1024 then return string.format("%.1f MB", size / (1024 * 1024)) end
    return string.format("%.1f GB", size / (1024 * 1024 * 1024))
end
local function extension(path)
    return path and path:lower():match("%.([^./]+)$") or ""
end
local function sortEntries(entries)
    table.sort(entries, function(a, b)
        if a.is_dir ~= b.is_dir then return a.is_dir end
        return a.name:lower() < b.name:lower()
    end)
end
local function iconFor(entry)
    if entry.is_dir then return "▰" end
    local ext = extension(entry.path)
    if ext == "jpg" or ext == "jpeg" or ext == "png" or ext == "gif" or ext == "webp" then return "▧" end
    if ext == "mp4" or ext == "mkv" or ext == "avi" or ext == "webm" then return "▹" end
    if ext == "mp3" or ext == "wav" or ext == "ogg" or ext == "flac" then return "♫" end
    if entry.is_lua then return "{}" end
    if entry.is_markup then return "≡" end
    if entry.supported then return "▤" end
    return "▧"
end
local function categoryFor(entry)
    if entry.is_dir then return "folders" end
    local ext = extension(entry.path)
    if ext == "jpg" or ext == "jpeg" or ext == "png" or ext == "gif" or ext == "webp" then return "images" end
    if ext == "mp4" or ext == "mkv" or ext == "avi" or ext == "webm" then return "videos" end
    if ext == "mp3" or ext == "wav" or ext == "ogg" or ext == "flac" then return "audio" end
    if ext == "apk" or ext == "lua" then return "apps" end
    return "documents"
end

local SearchPill = InputContainer:extend{ text = nil, callback = nil, width = nil, height = nil, dimen = nil }
function SearchPill:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local size = math.max(scale(10), math.floor(self.height * .32))
    local icon = TextWidget:new{ text = "⌕", face = Font:getFace("cfont", scale(17)), fgcolor = PALETTE.on_surface, padding = 0 }
    local label = TextWidget:new{ text = Theme.fitLabel(self.text or _("Search files"), self.width - scale(54), size, 0), face = Font:getFace("smallinfofont", size), fgcolor = PALETTE.on_variant, max_width = self.width - scale(54), padding = 0 }
    self[1] = FrameContainer:new{ width = self.width, height = self.height, padding = 0, bordersize = 0, radius = math.floor(self.height / 2), background = PALETTE.surface,
        Layout.FixedStack:new{ width = self.width, height = self.height, entries = {
            { widget = icon, x = scale(14), y = math.floor((self.height - scale(17)) / 2) },
            { widget = label, x = scale(42), y = math.floor((self.height - size) / 2) },
        } } }
    self.ges_events = { TapFileSearch = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end
function SearchPill:paintTo(bb, x, y)
    local range = self.ges_events.TapFileSearch[1].range; range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    return InputContainer.paintTo(self, bb, x, y)
end
function SearchPill:onTapFileSearch() if self.callback then self.callback() end return true end

local ActionPill = InputContainer:extend{ title = nil, symbol = nil, callback = nil, width = nil, height = nil, background = nil, foreground = nil, dimen = nil }
function ActionPill:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local size = math.max(scale(9), math.floor(self.height * .30))
    local symbol = TextWidget:new{ text = self.symbol or "", face = Font:getFace("cfont", scale(15)), fgcolor = self.foreground or PALETTE.on_surface, padding = 0 }
    local title = TextWidget:new{ text = Theme.fitLabel(self.title or "", self.width - scale(24), size, 0), face = Font:getFace("smallinfofont", size), fgcolor = self.foreground or PALETTE.on_surface, bold = true, max_width = self.width - scale(24), padding = 0 }
    self[1] = FrameContainer:new{ width = self.width, height = self.height, padding = 0, bordersize = 0, radius = math.floor(self.height * .35), background = self.background or PALETTE.surface,
        Layout.FixedStack:new{ width = self.width, height = self.height, entries = {
            { widget = symbol, x = scale(11), y = math.floor((self.height - scale(15)) / 2) },
            { widget = title, x = scale(32), y = math.floor((self.height - size) / 2) },
        } } }
    self.ges_events = { TapFileAction = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end
function ActionPill:paintTo(bb, x, y)
    local range = self.ges_events.TapFileAction[1].range; range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    return InputContainer.paintTo(self, bb, x, y)
end
function ActionPill:onTapFileAction() if self.callback then self.callback() end return true end

local CategoryCard = InputContainer:extend{ title = nil, subtitle = nil, symbol = nil, callback = nil, width = nil, height = nil, dimen = nil }
function CategoryCard:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local title_size = math.max(scale(9), math.floor(self.height * .23))
    local subtitle_size = math.max(scale(7), math.floor(self.height * .16))
    local icon = TextWidget:new{ text = self.symbol or "▧", face = Font:getFace("cfont", scale(19)), fgcolor = PALETTE.on_variant, padding = 0 }
    local title = TextWidget:new{ text = Theme.fitLabel(self.title or "", self.width - scale(56), title_size, 0), face = Font:getFace("smallinfofont", title_size), fgcolor = PALETTE.on_surface, bold = true, max_width = self.width - scale(56), padding = 0 }
    local subtitle = TextWidget:new{ text = Theme.fitLabel(self.subtitle or "", self.width - scale(56), subtitle_size, 0), face = Font:getFace("smallinfofont", subtitle_size), fgcolor = PALETTE.on_variant, max_width = self.width - scale(56), padding = 0 }
    self[1] = FrameContainer:new{ width = self.width, height = self.height, padding = 0, bordersize = 0, radius = scale(14), background = PALETTE.surface,
        Layout.FixedStack:new{ width = self.width, height = self.height, entries = {
            { widget = icon, x = scale(14), y = math.floor((self.height - scale(19)) / 2) },
            { widget = title, x = scale(48), y = scale(10) },
            { widget = subtitle, x = scale(48), y = self.height - subtitle_size - scale(10) },
        } } }
    self.layout = { google_files_category = true, title = self.title, subtitle = self.subtitle }
    self.ges_events = { TapFileCategory = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end
function CategoryCard:paintTo(bb, x, y)
    local range = self.ges_events.TapFileCategory[1].range; range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    return InputContainer.paintTo(self, bb, x, y)
end
function CategoryCard:onTapFileCategory() if self.callback then self.callback() end return true end

local FileTile = InputContainer:extend{ entry = nil, callback = nil, width = nil, height = nil, dimen = nil, recent = false }
function FileTile:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local entry = self.entry or {}
    local tile_icon = TextWidget:new{ text = iconFor(entry), face = Font:getFace("cfont", math.max(scale(22), math.floor(self.height * .30))), fgcolor = PALETTE.on_variant, padding = 0 }
    local title_size = math.max(scale(8), math.floor(self.height * .16))
    local detail_size = math.max(scale(7), math.floor(self.height * .13))
    local title = TextWidget:new{ text = Theme.fitLabel(entry.name or "", self.width - scale(12), title_size, 0), face = Font:getFace("smallinfofont", title_size), fgcolor = PALETTE.on_surface, bold = true, max_width = self.width - scale(12), padding = 0 }
    local detail = TextWidget:new{ text = entry.is_dir and _("Folder") or humanSize(entry.size), face = Font:getFace("smallinfofont", detail_size), fgcolor = PALETTE.on_variant, max_width = self.width - scale(12), padding = 0 }
    self[1] = FrameContainer:new{ width = self.width, height = self.height, padding = 0, bordersize = 0, radius = scale(13), background = PALETTE.surface_alt,
        Layout.FixedStack:new{ width = self.width, height = self.height, entries = {
            { widget = tile_icon, x = math.floor((self.width - scale(24)) / 2), y = math.floor(self.height * .22) },
            { widget = title, x = scale(7), y = self.height - title_size - detail_size - scale(13) },
            { widget = detail, x = scale(7), y = self.height - detail_size - scale(6) },
        } } }
    self.layout = { google_files_tile = true, name = entry.name, recent = self.recent }
    self.ges_events = { TapFileTile = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end
function FileTile:paintTo(bb, x, y)
    local range = self.ges_events.TapFileTile[1].range; range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    return InputContainer.paintTo(self, bb, x, y)
end
function FileTile:onTapFileTile() if self.callback then self.callback() end return true end

local FileRow = InputContainer:extend{ title = nil, subtitle = nil, symbol = nil, callback = nil, width = nil, height = nil, background = nil, foreground = nil, dimen = nil }
function FileRow:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local title_size = math.max(scale(9), math.floor(self.height * .28))
    local subtitle_size = math.max(scale(7), math.floor(self.height * .19))
    local icon = TextWidget:new{ text = self.symbol or "▧", face = Font:getFace("cfont", scale(17)), fgcolor = self.foreground or PALETTE.on_variant, padding = 0 }
    local title = TextWidget:new{ text = Theme.fitLabel(self.title or "", self.width - scale(54), title_size, 0), face = Font:getFace("smallinfofont", title_size), fgcolor = self.foreground or PALETTE.on_surface, bold = true, max_width = self.width - scale(54), padding = 0 }
    local subtitle = TextWidget:new{ text = Theme.fitLabel(self.subtitle or "", self.width - scale(54), subtitle_size, 0), face = Font:getFace("smallinfofont", subtitle_size), fgcolor = PALETTE.on_variant, max_width = self.width - scale(54), padding = 0 }
    self[1] = FrameContainer:new{ width = self.width, height = self.height, padding = 0, bordersize = 0, radius = scale(12), background = self.background or PALETTE.surface,
        Layout.FixedStack:new{ width = self.width, height = self.height, entries = {
            { widget = icon, x = scale(12), y = math.floor((self.height - scale(17)) / 2) },
            { widget = title, x = scale(42), y = scale(8) },
            { widget = subtitle, x = scale(42), y = self.height - subtitle_size - scale(8) },
        } } }
    self.layout = { google_files_row = true, title = self.title, subtitle = self.subtitle }
    self.ges_events = { TapFileRow = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end
function FileRow:paintTo(bb, x, y)
    local range = self.ges_events.TapFileRow[1].range; range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    return InputContainer.paintTo(self, bb, x, y)
end
function FileRow:onTapFileRow() if self.callback then self.callback() end return true end

function FileBrowser:new() return setmetatable({}, self) end
function FileBrowser:_ensureStandardFolders()
    -- These are only empty directory entries. Files are never moved or copied
    -- by the virtual sorter; users remain in control of their storage.
    pcall(function()
        local attributes = lfs.attributes(STORAGE_ROOT)
        if not attributes and lfs.mkdir then lfs.mkdir(STORAGE_ROOT) end
        for _, folder in ipairs(STANDARD_FOLDERS) do
            local path = STORAGE_ROOT .. "/" .. folder
            if not lfs.attributes(path) and lfs.mkdir then lfs.mkdir(path) end
        end
    end)
end
function FileBrowser:_ensureState(instance)
    self:_ensureStandardFolders()
    instance.file_browser = instance.file_browser or { path = STORAGE_ROOT, error = nil, entries = nil, home_mode = true, sort_mode = false, query = "", category = nil, recent_files = {} }
    instance.file_browser.sort_mode = instance.file_browser.sort_mode == true
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
                    name = name, path = fullpath, is_dir = attributes.mode == "directory", size = attributes.size,
                    supported = attributes.mode == "file" and DocumentRegistry:hasProvider(fullpath),
                    is_lua = attributes.mode == "file" and fullpath:lower():match("%.lua$") ~= nil,
                    is_markup = attributes.mode == "file" and (fullpath:lower():match("%.md$") or fullpath:lower():match("%.markdown$") or fullpath:lower():match("%.mdown$") or fullpath:lower():match("%.mkdn$")) ~= nil,
                    is_dreader = attributes.mode == "file" and (fullpath:lower():match("%.epub$") or fullpath:lower():match("%.html$") or fullpath:lower():match("%.htm$") or fullpath:lower():match("%.xhtml$") or fullpath:lower():match("%.md$") or fullpath:lower():match("%.markdown$")) ~= nil,
                })
            end
        end
    end
    sortEntries(entries)
    return entries
end
function FileBrowser:_readSortedEntries(root, limit)
    local entries, visited = {}, {}
    limit = limit or 500
    local function visit(path)
        if #entries >= limit or visited[path] then return end
        visited[path] = true
        local ok, iterator, directory_object = pcall(lfs.dir, path)
        if not ok or not iterator then return end
        for name in iterator, directory_object do
            if #entries >= limit then break end
            if name ~= "." and name ~= ".." then
                local fullpath = path == "/" and ("/" .. name) or (path .. "/" .. name)
                local attributes_ok, attributes = pcall(lfs.attributes, fullpath)
                if attributes_ok and attributes then
                    if attributes.mode == "directory" then
                        visit(fullpath)
                    elseif attributes.mode == "file" then
                        local entry = self:_readEntries(path)
                        -- Read the single file's metadata without changing the
                        -- visible filesystem; this also keeps handler flags in
                        -- one place for the normal and virtual views.
                        local found
                        for _, candidate in ipairs(entry or {}) do if candidate.path == fullpath then found = candidate; break end end
                        if found then
                            found.name = basename(fullpath)
                            found.sort_category = categoryFor(found)
                            found.virtual_path = fullpath
                            table.insert(entries, found)
                        end
                    end
                end
            end
        end
    end
    visit(root)
    table.sort(entries, function(a, b) return (a.sort_category or ""):lower() .. a.name:lower() < (b.sort_category or ""):lower() .. b.name:lower() end)
    return entries
end
function FileBrowser:refresh(instance, context)
    local state = self:_ensureState(instance)
    if state.sort_mode then state.entries, state.error = self:_readSortedEntries(STORAGE_ROOT), nil
    else state.entries, state.error = self:_readEntries(state.path) end
    context.requestRebuild("ui")
end
function FileBrowser:enterDirectory(instance, context, path)
    local state = self:_ensureState(instance); state.path, state.home_mode, state.sort_mode, state.category, state.query = path, false, false, nil, ""; self:refresh(instance, context)
end
function FileBrowser:showHome(instance, context)
    local state = self:_ensureState(instance); state.path, state.home_mode, state.sort_mode, state.category, state.query = STORAGE_ROOT, true, false, nil, ""; self:refresh(instance, context)
end
function FileBrowser:openInternalStorage(instance, context)
    local state = self:_ensureState(instance); state.path, state.home_mode, state.sort_mode, state.category, state.query = STORAGE_ROOT, false, false, nil, ""; self:refresh(instance, context)
end
function FileBrowser:sortMyFiles(instance, context)
    local state = self:_ensureState(instance); state.path, state.home_mode, state.sort_mode, state.category, state.query = STORAGE_ROOT, false, true, nil, ""; self:refresh(instance, context)
end
function FileBrowser:showSearch(instance, context)
    local state = self:_ensureState(instance)
    local dialog
    dialog = InputDialog:new{ title = _("Search files"), input = state.query or "", input_hint = _("Name or extension"), buttons = {
        { { text = _("Cancel"), callback = function() UIManager:close(dialog) end },
          { text = _("Search"), is_enter_default = true, callback = function()
              state.query = (dialog:getInputText() or ""):gsub("^%s+", ""):gsub("%s+$", ""); state.home_mode = false; UIManager:close(dialog); context.requestRebuild("ui")
          end } },
    } }
    UIManager:show(dialog)
end
function FileBrowser:setCategory(instance, context, category)
    local state = self:_ensureState(instance); state.home_mode, state.sort_mode, state.category, state.query = false, false, category, ""; context.requestRebuild("ui")
end
function FileBrowser:_handlers(context, path)
    return context.manager and context.manager.getFileHandlers and context.manager:getFileHandlers(path) or {}
end
function FileBrowser:openLuaFile(instance, context, path)
    local manager = context.manager
    if not manager or not manager.openDAppFile then UIManager:show(InfoMessage:new{ text = _("NightLua is not available in this AppDock session.") }); return end
    local ok, err = manager:openDAppFile("night_lua", path)
    if not ok then UIManager:show(InfoMessage:new{ text = _("Install NightLua from AppStore first.\n\n") .. tostring(err or "") }) end
end
function FileBrowser:openDReaderFile(instance, context, path)
    local manager = context.manager
    if not manager or not manager.openDAppFile then UIManager:show(InfoMessage:new{ text = _("DReader is not available in this AppDock session.") }); return end
    local ok, err = manager:openDAppFile("dreader", path)
    if not ok then UIManager:show(InfoMessage:new{ text = _("Install DReader from AppStore first.\n\n") .. tostring(err or "") }) end
end
function FileBrowser:openMarkUPFile(instance, context, path)
    local manager = context.manager
    if not manager or not manager.openDAppFile then UIManager:show(InfoMessage:new{ text = _("MarkUP is not available in this AppDock session.") }); return end
    local ok, err = manager:openDAppFile("markup", path)
    if not ok then UIManager:show(InfoMessage:new{ text = _("Install MarkUP from AppStore first.\n\n") .. tostring(err or "") }) end
end
function FileBrowser:openFile(instance, context, path, supported)
    if not supported then UIManager:show(InfoMessage:new{ text = _("KOReader has no reader engine for this file type.") }); return end
    local state = self:_ensureState(instance)
    table.insert(state.recent_files, 1, { name = basename(path), path = path, is_dir = false, size = 0, supported = true })
    while #state.recent_files > 8 do table.remove(state.recent_files) end
    UIManager:close(context.host)
    UIManager:nextTick(function() local ReaderUI = require("apps/reader/readerui"); ReaderUI:showReader(path) end)
end
function FileBrowser:openEntry(instance, context, entry)
    if entry.is_dir then self:enterDirectory(instance, context, entry.path); return end
    local handlers = self:_handlers(context, entry.path)
    if #handlers > 0 and context.manager and context.manager.showFileHandlerChoices then context.manager:showFileHandlerChoices(entry.path, handlers)
    elseif entry.is_lua then self:openLuaFile(instance, context, entry.path)
    elseif entry.is_markup then self:openMarkUPFile(instance, context, entry.path)
    elseif entry.is_dreader then self:openDReaderFile(instance, context, entry.path)
    else self:openFile(instance, context, entry.path, entry.supported) end
end
local function matches(entry, query, category)
    if query and query ~= "" then local hay = (entry.name .. " " .. entry.path):lower(); if not hay:find(query:lower(), 1, true) then return false end end
    return not category or (entry.sort_category or categoryFor(entry)) == category
end
function FileBrowser:_fileSubtitle(context, entry)
    if entry.is_dir then return _("Folder") end
    local handlers = self:_handlers(context, entry.path)
    if #handlers == 1 then return handlers[1].title .. " · " .. humanSize(entry.size) end
    if #handlers > 1 then return _("Open with AppDock") .. " · " .. humanSize(entry.size) end
    if entry.is_lua then return _("Open in NightLua") .. " · " .. humanSize(entry.size) end
    if entry.is_markup then return _("Open in MarkUP") .. " · " .. humanSize(entry.size) end
    if entry.is_dreader then return _("Open in DReader") .. " · " .. humanSize(entry.size) end
    if entry.supported then return _("Open document") .. " · " .. humanSize(entry.size) end
    return _("Unsupported file") .. " · " .. humanSize(entry.size)
end
function FileBrowser:_categoryData(entries)
    local specs = {
        { id = "documents", title = _("Documents"), symbol = "▤" }, { id = "images", title = _("Images"), symbol = "▧" },
        { id = "videos", title = _("Videos"), symbol = "▹" }, { id = "audio", title = _("Audio"), symbol = "♫" },
        { id = "apps", title = _("Apps"), symbol = "{}" }, { id = "folders", title = _("Folders"), symbol = "▰" },
    }
    for _, spec in ipairs(specs) do spec.count, spec.bytes = 0, 0 end
    for _, entry in ipairs(entries or {}) do for _, spec in ipairs(specs) do if categoryFor(entry) == spec.id then spec.count = spec.count + 1; spec.bytes = spec.bytes + (entry.size or 0) end end end
    return specs
end
function FileBrowser:_filteredEntries(state)
    local result = {}
    for _, entry in ipairs(state.entries or {}) do if matches(entry, state.query, state.category) then table.insert(result, entry) end end
    return result
end
function FileBrowser:_buildBrowseList(instance, context, state, entries, width, height)
    local list = VerticalGroup:new{}
    if #entries == 0 then
        table.insert(list, FileRow:new{ title = state.query ~= "" and _("No matching files") or _("This folder is empty"), subtitle = state.path, symbol = "⌕", width = width, height = scale(58), background = PALETTE.surface })
    else
        for _, entry in ipairs(entries) do
            table.insert(list, FileRow:new{ title = entry.name, subtitle = self:_fileSubtitle(context, entry), symbol = iconFor(entry), width = width, height = scale(54), background = entry.is_dir and PALETTE.primary or PALETTE.surface, foreground = entry.is_dir and PALETTE.on_primary or PALETTE.on_surface, callback = function() self:openEntry(instance, context, entry) end })
            table.insert(list, VerticalSpan:new{ width = scale(5) })
        end
    end
    return ScrollableContainer:new{ dimen = Geom:new{ w = width + ScrollableContainer:getScrollbarWidth(), h = height }, show_parent = context.host, list }
end
function FileBrowser:buildPane(instance, context)
    applyTheme(context.manager and context.manager.appdock)
    local state = self:_ensureState(instance)
    if not state.entries and not state.error then
        if state.sort_mode then state.entries, state.error = self:_readSortedEntries(STORAGE_ROOT), nil
        else state.entries, state.error = self:_readEntries(state.path) end
    end
    local pane = WidgetContainer:new{ dimen = Geom:new{ w = context.dimen.w, h = context.dimen.h } }
    local width, height = context.dimen.w, context.dimen.h
    local margin, gap = scale(12), scale(8)
    local search_h = scale(40)
    local content_y = margin + search_h + scale(10)
    local browse_button_h = scale(34)
    local home_width = math.max(scale(190), math.floor(width * .52))
    local side_x, side_w = margin + home_width + gap, width - margin - (margin + home_width + gap)
    local content_h = math.max(scale(80), height - content_y - margin)
    local root = OverlapGroup:new{ dimen = pane.dimen, allow_mirroring = false,
        FrameContainer:new{ width = width, height = height, padding = 0, bordersize = 0, background = PALETTE.background, emptySizedWidget(width, height) },
        SearchPill:new{ width = width - 2 * margin, height = search_h, text = state.query ~= "" and state.query or _("Search files"), callback = function() self:showSearch(instance, context) end, overlap_offset = { margin, margin } },
    }
    if state.error then
        table.insert(root, FileRow:new{ title = _("Folder unavailable"), subtitle = state.error, symbol = "!", width = width - 2 * margin, height = scale(58), background = PALETTE.secondary, overlap_offset = { margin, content_y } })
        pane[1] = root; pane.file_layout = { google_files_style = true, home_mode = state.home_mode, has_search = true, error = true }; return pane
    end
    local categories = self:_categoryData(state.entries)
    local recent = state.recent_files or {}
    if #recent == 0 then for _, entry in ipairs(state.entries) do if not entry.is_dir then table.insert(recent, entry); if #recent >= 4 then break end end end end
    local browse_entries = self:_filteredEntries(state)
    local category_label = state.sort_mode and _("Sorted files") or (state.category and (_("Category") .. " · " .. state.category) or _("All files"))
    if state.home_mode then
        table.insert(root, TextWidget:new{ text = _("Files"), face = Font:getFace("cfont", scale(18)), fgcolor = PALETTE.on_surface, bold = true, padding = 0, overlap_offset = { margin, content_y } })
        table.insert(root, TextWidget:new{ text = _("Recently used"), face = Font:getFace("smallinfofont", scale(11)), fgcolor = PALETTE.on_surface, bold = true, padding = 0, overlap_offset = { margin, content_y + scale(28) } })
        local recent_w, recent_h, recent_gap = math.max(scale(52), math.floor((home_width - scale(26)) / 3)), scale(105), scale(6)
        local recent_limit = math.min(3, #recent)
        for i = 1, recent_limit do table.insert(root, FileTile:new{ entry = recent[i], recent = true, width = recent_w, height = recent_h, callback = function() self:openEntry(instance, context, recent[i]) end, overlap_offset = { margin + (i - 1) * (recent_w + recent_gap), content_y + scale(48) } }) end
        if recent_limit == 0 then table.insert(root, TextWidget:new{ text = _("Your recent files will appear here"), face = Font:getFace("smallinfofont", scale(9)), fgcolor = PALETTE.on_variant, padding = 0, overlap_offset = { margin, content_y + scale(72) } }) end
        local cat_y = content_y + scale(166)
        table.insert(root, TextWidget:new{ text = _("Categories"), face = Font:getFace("smallinfofont", scale(11)), fgcolor = PALETTE.on_surface, bold = true, padding = 0, overlap_offset = { margin, cat_y } })
        local card_gap, card_w, card_h = scale(6), math.floor((home_width - scale(26)) / 2), scale(45)
        for i, spec in ipairs(categories) do
            local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
            table.insert(root, CategoryCard:new{ title = spec.title, subtitle = spec.count > 0 and (tostring(spec.count) .. " · " .. humanSize(spec.bytes)) or _("Browse"), symbol = spec.symbol, width = card_w, height = card_h, callback = function() self:setCategory(instance, context, spec.id) end, overlap_offset = { margin + col * (card_w + card_gap), cat_y + scale(22) + row * (card_h + card_gap) } })
        end
        local storage_y = cat_y + scale(22) + 3 * (card_h + card_gap) + scale(10)
        table.insert(root, TextWidget:new{ text = _("All storage"), face = Font:getFace("smallinfofont", scale(11)), fgcolor = PALETTE.on_surface, bold = true, padding = 0, overlap_offset = { margin, storage_y } })
        table.insert(root, ActionPill:new{ title = _("Internal storage"), symbol = "▥", width = card_w, height = browse_button_h, background = PALETTE.surface, callback = function() self:openInternalStorage(instance, context) end, overlap_offset = { margin, storage_y + scale(20) } })
        table.insert(root, ActionPill:new{ title = _("Sort my files"), symbol = "↕", width = card_w, height = browse_button_h, background = PALETTE.primary, foreground = PALETTE.on_primary, callback = function() self:sortMyFiles(instance, context) end, overlap_offset = { margin + card_w + card_gap, storage_y + scale(20) } })
    end
    -- The right side is the Google Files-style recent/browse surface.
    table.insert(root, FrameContainer:new{ width = side_w, height = content_h, padding = 0, bordersize = 0, radius = scale(15), background = PALETTE.surface, emptySizedWidget(side_w, content_h), overlap_offset = { side_x, content_y } })
    table.insert(root, TextWidget:new{ text = state.home_mode and _("Recently used") or category_label, face = Font:getFace("cfont", scale(16)), fgcolor = PALETTE.on_surface, bold = true, padding = 0, overlap_offset = { side_x + scale(12), content_y + scale(12) } })
    table.insert(root, ActionPill:new{ title = state.home_mode and _("Browse") or _("Home"), symbol = state.home_mode and "☷" or "⌂", width = scale(76), height = browse_button_h, background = PALETTE.surface_alt, callback = function() if state.home_mode then self:openInternalStorage(instance, context) else self:showHome(instance, context) end end, overlap_offset = { side_x + side_w - scale(88), content_y + scale(8) } })
    local right_y = content_y + scale(54)
    if state.home_mode then
        local right_entries = {}
        for _, entry in ipairs(recent) do table.insert(right_entries, entry) end
        if #right_entries == 0 then right_entries = browse_entries end
        local tile_w, tile_h, tile_gap = math.max(scale(50), math.floor((side_w - scale(30)) / 3)), scale(100), scale(6)
        for i, entry in ipairs(right_entries) do
            local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
            if row * (tile_h + tile_gap) + tile_h > content_h - scale(60) then break end
            table.insert(root, FileTile:new{ entry = entry, recent = true, width = tile_w, height = tile_h, callback = function() self:openEntry(instance, context, entry) end, overlap_offset = { side_x + scale(10) + col * (tile_w + tile_gap), right_y + row * (tile_h + tile_gap) } })
        end
    else
        table.insert(root, self:_buildBrowseList(instance, context, state, browse_entries, side_w - scale(20), content_h - scale(65)))
        root[#root].overlap_offset = { side_x + scale(10), right_y }
    end
    pane[1] = root
    pane.file_layout = { google_files_style = true, home_mode = state.home_mode, sort_mode = state.sort_mode, storage_root = STORAGE_ROOT, standard_folders = STANDARD_FOLDERS, has_search = true, has_recent = #recent > 0, has_categories = true, has_storage = true, category = state.category, query = state.query, two_column = true, recent_count = #recent, non_destructive_sort = true }
    return pane
end
return FileBrowser
