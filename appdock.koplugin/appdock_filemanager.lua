--[[--
AppDock File Manager 2.0

Visual shell inspired by Google Files: search bar, recent files, category cards,
storage overview and a clean browse view (list or grid) with a toolbar, sorting,
paging, multi-select and bulk actions.

Safety rules (unchanged):
* "Sort my files" is purely virtual. Nothing is created, renamed or moved by it.
* Files are opened only through KOReader's reader path or explicit AppDock DApps.
* All write operations are restricted to the internal storage root.
--]]--
local Blitbuffer = require("ffi/blitbuffer")
local AppDockDialogs = require("appdock_dialogs")
local ButtonDialog = AppDockDialogs.ButtonDialog
local ConfirmBox = AppDockDialogs.ConfirmBox
local InfoMessage = AppDockDialogs.InfoMessage
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local DocumentRegistry = require("document/documentregistry")
local Theme = require("appdock_theme")
local AppDockKeyboard = require("appdock_keyboard")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
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
local IMAGE_EXTENSIONS = { jpg=true, jpeg=true, png=true, gif=true, webp=true, bmp=true, tif=true, tiff=true, heic=true, avif=true, svg=true }
local VIDEO_EXTENSIONS = { mp4=true, m4v=true, mkv=true, avi=true, webm=true, mov=true, flv=true, ts=true, mpg=true, mpeg=true }
VIDEO_EXTENSIONS["3gp"] = true
local AUDIO_EXTENSIONS = { mp3=true, wav=true, ogg=true, oga=true, flac=true, aac=true, m4a=true, opus=true, wma=true, aiff=true, alac=true }
local APP_EXTENSIONS = { apk=true, lua=true, luac=true, sh=true, py=true, js=true, bin=true, appimage=true, desktop=true, exe=true }
local CATEGORY_ORDER = { "documents", "images", "videos", "audio", "apps", "folders" }
local RECENT_LIMIT = 12
local SCAN_NODE_LIMIT = 20000
local SEARCH_NODE_LIMIT = 30000
local SEARCH_RESULT_LIMIT = 400
local VIRTUAL_SORT_LIMIT = 3000

---------------------------------------------------------------------------
-- Look & feel
---------------------------------------------------------------------------
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
local ACCENTS = {
    documents = { bg = color(222, 233, 255, Blitbuffer.COLOR_LIGHT_GRAY), fg = color(33, 82, 170, Blitbuffer.COLOR_BLACK), tag = "DOC" },
    images    = { bg = color(219, 242, 226, Blitbuffer.COLOR_LIGHT_GRAY), fg = color(30, 115, 62, Blitbuffer.COLOR_BLACK), tag = "IMG" },
    videos    = { bg = color(255, 225, 220, Blitbuffer.COLOR_LIGHT_GRAY), fg = color(176, 52, 40, Blitbuffer.COLOR_BLACK), tag = "VID" },
    audio     = { bg = color(240, 226, 255, Blitbuffer.COLOR_LIGHT_GRAY), fg = color(112, 60, 170, Blitbuffer.COLOR_BLACK), tag = "AUD" },
    apps      = { bg = color(255, 240, 200, Blitbuffer.COLOR_LIGHT_GRAY), fg = color(140, 90, 0, Blitbuffer.COLOR_BLACK), tag = "APP" },
    folders   = { bg = color(255, 233, 186, Blitbuffer.COLOR_LIGHT_GRAY), fg = color(176, 112, 0, Blitbuffer.COLOR_BLACK), tag = "" },
    other     = { bg = color(232, 232, 236, Blitbuffer.COLOR_LIGHT_GRAY), fg = color(80, 80, 90, Blitbuffer.COLOR_BLACK), tag = "FILE" },
}
local function applyTheme(appdock)
    local palette = Theme.getPalette(appdock)
    PALETTE.background, PALETTE.surface = palette.background, palette.surface
    PALETTE.primary, PALETTE.secondary = palette.primary, palette.secondary
    PALETTE.on_primary, PALETTE.on_surface = palette.on_primary, palette.on_surface
    PALETTE.on_variant = palette.on_variant
    PALETTE.outline = palette.outline or palette.surface_variant or palette.on_variant
    PALETTE.surface_alt = palette.surface_alt or palette.surface_variant or palette.secondary or PALETTE.surface_alt
end

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
local function trim(value)
    return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end
local function basename(path) return path and path:match("([^/]+)$") or path end
local function parentPath(path)
    if not path or path == "/" then return "/" end
    local parent = path:match("^(.*)/[^/]+$")
    if not parent or parent == "" then return "/" end
    return parent
end
local function isInside(path, root)
    return type(path) == "string" and (path == root or path:sub(1, #root + 1) == root .. "/")
end
local function validStoragePath(path)
    -- Reject path traversal ("/../"), but allow names that merely contain "..".
    return type(path) == "string" and isInside(path, STORAGE_ROOT)
        and not path:find("/%.%./") and not path:find("/%.%.$")
end
local function humanSize(size)
    size = tonumber(size) or 0
    if size < 1024 then return string.format("%d B", size) end
    if size < 1024 * 1024 then return string.format("%.1f KB", size / 1024) end
    if size < 1024 * 1024 * 1024 then return string.format("%.1f MB", size / (1024 * 1024)) end
    return string.format("%.1f GB", size / (1024 * 1024 * 1024))
end
local function formatDate(timestamp, with_time)
    timestamp = tonumber(timestamp)
    if not timestamp or timestamp <= 0 then return "" end
    local ok, text = pcall(os.date, with_time and "%Y-%m-%d %H:%M" or "%Y-%m-%d", timestamp)
    return ok and text or ""
end
local function extension(path)
    return path and path:lower():match("%.([^./]+)$") or ""
end
local function naturalKey(name)
    return (tostring(name or ""):lower():gsub("%d+", function(digits)
        if #digits < 12 then return string.rep("0", 12 - #digits) .. digits end
        return digits
    end))
end
local function clamp(value, low, high) return math.max(low, math.min(high, value)) end
local function lstat(path)
    if lfs.symlinkattributes then return lfs.symlinkattributes(path) end
    return lfs.attributes(path)
end
local function hiddenPath(path)
    for part in tostring(path or ""):gmatch("/([^/]+)") do
        if part:sub(1, 1) == "." then return true end
    end
    return false
end
local function categoryOf(path, is_dir)
    if is_dir then return "folders" end
    local ext = extension(path)
    if IMAGE_EXTENSIONS[ext] then return "images" end
    if VIDEO_EXTENSIONS[ext] then return "videos" end
    if AUDIO_EXTENSIONS[ext] then return "audio" end
    -- Note: the executable bit is deliberately ignored. FAT storage reports
    -- every file as executable, which used to turn all files into "Apps".
    if APP_EXTENSIONS[ext] then return "apps" end
    return "documents"
end
local function categoryFor(entry) return categoryOf(entry.path, entry.is_dir) end
local function categoryTitle(id)
    if id == "documents" then return _("Documents") end
    if id == "images" then return _("Images") end
    if id == "videos" then return _("Videos") end
    if id == "audio" then return _("Audio") end
    if id == "apps" then return _("Apps") end
    if id == "folders" then return _("Folders") end
    return _("All files")
end
local function sortLabel(by)
    if by == "date" then return _("Date") end
    if by == "size" then return _("Size") end
    if by == "type" then return _("Type") end
    return _("Name")
end
local function displayPath(path)
    if not path or path == STORAGE_ROOT then return _("Internal storage") end
    if not isInside(path, STORAGE_ROOT) then return path end
    local relative = path:sub(#STORAGE_ROOT + 2)
    return _("Internal storage") .. " › " .. (relative:gsub("/", " › "))
end
local function typeLabel(entry)
    if entry.is_dir then return _("Folder") end
    local cat = categoryFor(entry)
    local names = { documents = _("Document"), images = _("Image"), videos = _("Video"), audio = _("Audio"), apps = _("App / script") }
    local ext = extension(entry.path)
    return (names[cat] or _("File")) .. (ext ~= "" and (" (" .. ext:upper() .. ")") or "")
end

local function compareText(a, b)
    if a == b then return 0 end
    return a < b and -1 or 1
end
local function sortEntries(entries, prefs, grouped)
    prefs = prefs or {}
    local by, desc = prefs.sort_by or "name", prefs.sort_desc == true
    table.sort(entries, function(a, b)
        if grouped then
            local ga, gb = a.sort_category or "", b.sort_category or ""
            if ga ~= gb then return ga < gb end
        elseif a.is_dir ~= b.is_dir then
            return a.is_dir
        end
        local result = 0
        if by == "date" then result = (a.modified or 0) - (b.modified or 0)
        elseif by == "size" then result = (a.size or 0) - (b.size or 0)
        elseif by == "type" then result = compareText(extension(a.path), extension(b.path)) end
        if result > 0 then result = 1 elseif result < 0 then result = -1 end
        if result == 0 then result = compareText(a.sort_key or "", b.sort_key or "") end
        if result == 0 then return (a.path or "") < (b.path or "") end
        if desc then return result > 0 end
        return result < 0
    end)
end

-- Names must survive FAT32 (the usual format of the reader's storage).
local function validName(name)
    name = trim(name)
    if name == "" or name == "." or name == ".." then return nil, _("Please enter a valid file name.") end
    if name:find("[/\\:%*%?\"<>|]") then return nil, _("A name cannot contain / \\ : * ? \" < > |") end
    if #name > 200 then return nil, _("This name is too long.") end
    return name
end
local function uniquePath(directory, name)
    local candidate = directory .. "/" .. name
    if not lfs.attributes(candidate) then return candidate end
    local stem, ext = name:match("^(.*)(%.[^./]+)$")
    if not stem or stem == "" then stem, ext = name, "" end
    for index = 1, 999 do
        candidate = string.format("%s/%s (%d)%s", directory, stem, index, ext)
        if not lfs.attributes(candidate) then return candidate end
    end
    return nil
end

---------------------------------------------------------------------------
-- File operations (all confined to STORAGE_ROOT)
---------------------------------------------------------------------------
local function copyFile(source, target)
    local input = io.open(source, "rb")
    if not input then return false, _("The file could not be read.") end
    local output = io.open(target, "wb")
    if not output then input:close(); return false, _("The destination could not be written.") end
    local ok = true
    -- Chunked copy: big videos must not be loaded into the reader's small RAM.
    while true do
        local chunk = input:read(262144)
        if not chunk then break end
        if not output:write(chunk) then ok = false; break end
    end
    input:close()
    local closed = output:close()
    if not ok or not closed then
        os.remove(target)
        return false, _("The file could not be written. Is the storage full?")
    end
    return true
end

local function removeTree(path)
    local attributes = lstat(path)
    if not attributes then return false, _("The item no longer exists.") end
    -- Never follow symlinks: delete the link itself, not what it points to.
    if attributes.mode == "link" then
        if os.remove(path) then return true end
        return false, _("The file could not be deleted.")
    end
    if attributes.mode == "directory" then
        local ok, iterator, directory_object = pcall(lfs.dir, path)
        if not ok or not iterator then return false, _("The folder could not be read.") end
        for name in iterator, directory_object do
            if name ~= "." and name ~= ".." then
                local child_ok, child_err = removeTree(path .. "/" .. name)
                if not child_ok then return false, child_err end
            end
        end
        if lfs.rmdir(path) then return true end
        return false, _("The folder could not be deleted.")
    end
    if os.remove(path) then return true end
    return false, _("The file could not be deleted.")
end

local function removePath(path)
    if not validStoragePath(path) or path == STORAGE_ROOT then
        return false, _("This item cannot be deleted.")
    end
    return removeTree(path)
end

local function copyPath(source, target, depth)
    depth = depth or 0
    if depth > 32 then return false, _("The folder structure is too deep.") end
    local attributes = lstat(source)
    if not attributes then return false, _("Source does not exist.") end
    if attributes.mode == "link" then return true end
    if attributes.mode == "directory" then
        if not lfs.mkdir(target) then return false, _("The folder could not be created.") end
        local ok, iterator, directory_object = pcall(lfs.dir, source)
        if not ok or not iterator then return false, _("The folder could not be read.") end
        for name in iterator, directory_object do
            if name ~= "." and name ~= ".." then
                local child_ok, child_err = copyPath(source .. "/" .. name, target .. "/" .. name, depth + 1)
                if not child_ok then return false, child_err end
            end
        end
        return true
    end
    return copyFile(source, target)
end

-- Copy or move one item into a directory. A name clash never overwrites:
-- the new item becomes "name (1).ext".
local function transfer(source, destination, move)
    if not validStoragePath(source) or not validStoragePath(destination) then
        return false, _("Invalid destination.")
    end
    local destination_attributes = lfs.attributes(destination)
    if not destination_attributes or destination_attributes.mode ~= "directory" then
        return false, _("The destination folder does not exist.")
    end
    local source_attributes = lfs.attributes(source)
    if not source_attributes then return false, _("Source does not exist.") end
    if move and parentPath(source) == destination then
        return false, _("The item is already in this folder.")
    end
    if source_attributes.mode == "directory" and isInside(destination, source) then
        return false, _("A folder cannot be copied into itself.")
    end
    local target = uniquePath(destination, basename(source))
    if not target then return false, _("A file or folder with this name already exists.") end
    if move and os.rename(source, target) then return true, nil, target end
    local ok, err = copyPath(source, target)
    if not ok then
        if lfs.attributes(target) then removeTree(target) end
        return false, err
    end
    if move then
        local removed, remove_err = removePath(source)
        if not removed then return false, remove_err end
    end
    return true, nil, target
end

local function countChildren(path)
    local ok, iterator, directory_object = pcall(lfs.dir, path)
    if not ok or not iterator then return 0 end
    local count = 0
    for name in iterator, directory_object do
        if name ~= "." and name ~= ".." then count = count + 1 end
    end
    return count
end

local function diskUsage(path)
    local ok_util, util = pcall(require, "util")
    if not ok_util or type(util) ~= "table" or type(util.diskUsage) ~= "function" then return nil end
    local ok, usage = pcall(util.diskUsage, path)
    if not ok or type(usage) ~= "table" then return nil end
    local total = tonumber(usage.total or usage.size)
    local available = tonumber(usage.available or usage.free or usage.avail)
    local used = tonumber(usage.used) or (total and available and (total - available))
    if not total or total <= 0 or not used then return nil end
    return { total = total, used = clamp(used, 0, total) }
end

---------------------------------------------------------------------------
-- Widget helpers
---------------------------------------------------------------------------
local function emptySizedWidget(width, height)
    return CenterContainer:new{ dimen = Geom:new{ w = width, h = height }, HorizontalSpan:new{ width = 0 } }
end
local function hspan(width) return HorizontalSpan:new{ width = width } end
local function vspan(height) return VerticalSpan:new{ width = height } end
local function label(text, size, fg, bold, max_width, font)
    return TextWidget:new{
        text = text or "", face = Font:getFace(font or "smallinfofont", size),
        fgcolor = fg or PALETTE.on_surface, bold = bold == true, max_width = max_width, padding = 0,
    }
end
-- Absolute placement of a few children inside a fixed box.
local function stack(width, height, entries)
    local group = OverlapGroup:new{ dimen = Geom:new{ w = width, h = height }, allow_mirroring = false }
    for _i, item in ipairs(entries) do
        item.widget.overlap_offset = { item.x, item.y }
        table.insert(group, item.widget)
    end
    return group
end
local function rowOf(margin, gap, widgets)
    local row = HorizontalGroup:new{ align = "center", hspan(margin) }
    for index, widget in ipairs(widgets) do
        if index > 1 then table.insert(row, hspan(gap)) end
        table.insert(row, widget)
    end
    return row
end
local function divider(width)
    return FrameContainer:new{ width = width, height = scale(1), padding = 0, bordersize = 0, background = PALETTE.outline, emptySizedWidget(width, scale(1)) }
end
local function centeredText(width, height, text, size, fg, bold)
    local widget = label(text, size, fg, bold, width - scale(16))
    return CenterContainer:new{ dimen = Geom:new{ w = width, h = height }, widget }
end

-- Drawn icons: no dependency on exotic font glyphs.
local function folderGlyph(size, fg)
    local w, h = math.floor(size * .52), math.floor(size * .40)
    local tab_w, tab_h = math.floor(w * .42), math.max(scale(3), math.floor(h * .22))
    return OverlapGroup:new{
        dimen = Geom:new{ w = w, h = h }, allow_mirroring = false,
        FrameContainer:new{ width = tab_w, height = tab_h + scale(2), padding = 0, bordersize = 0, radius = scale(2), background = fg, emptySizedWidget(tab_w, tab_h + scale(2)) },
        FrameContainer:new{ width = w, height = h - tab_h, padding = 0, bordersize = 0, radius = scale(3), background = fg, emptySizedWidget(w, h - tab_h), overlap_offset = { 0, tab_h } },
    }
end
local function magnifier(size, fg)
    local ring = math.floor(size * .72)
    local thickness = math.max(scale(2), math.floor(size * .11))
    return OverlapGroup:new{
        dimen = Geom:new{ w = size, h = size }, allow_mirroring = false,
        FrameContainer:new{ width = ring, height = ring, padding = 0, bordersize = thickness, color = fg, radius = math.floor(ring / 2), emptySizedWidget(ring - 2 * thickness, ring - 2 * thickness) },
        FrameContainer:new{ width = thickness * 2, height = thickness * 2, padding = 0, bordersize = 0, radius = thickness, background = fg, emptySizedWidget(thickness * 2, thickness * 2), overlap_offset = { ring - thickness, ring - thickness } },
    }
end
local function checkbox(size, checked)
    local border = scale(2)
    return FrameContainer:new{
        width = size, height = size, padding = 0, bordersize = border,
        color = checked and PALETTE.on_primary or PALETTE.on_variant, radius = math.floor(size * .25),
        background = checked and PALETTE.on_primary or PALETTE.surface,
        emptySizedWidget(size - 2 * border, size - 2 * border),
    }
end

-- Rounded badge: folder glyph or the file's extension, tinted per category.
local FileIcon = WidgetContainer:extend{ entry = nil, category = nil, tag = nil, size = nil }
function FileIcon:init()
    local size = self.size
    local entry = self.entry or {}
    local category = self.category or categoryFor(entry)
    local accent = ACCENTS[category] or ACCENTS.other
    local content
    if category == "folders" then
        content = folderGlyph(size, accent.fg)
    else
        local tag = self.tag
        if not tag then
            local ext = extension(entry.path)
            tag = ext ~= "" and ext:upper():sub(1, 4) or accent.tag
        end
        local unit = scale(10) / 10
        local nominal = math.max(9, math.floor(size / unit * .27))
        content = label(tag, nominal, accent.fg, true, size - scale(4))
    end
    self.dimen = Geom:new{ w = size, h = size }
    self[1] = FrameContainer:new{
        width = size, height = size, padding = 0, bordersize = 0, radius = math.floor(size * .24), background = accent.bg,
        CenterContainer:new{ dimen = Geom:new{ w = size, h = size }, content },
    }
end

---------------------------------------------------------------------------
-- Touch widgets
---------------------------------------------------------------------------
local Tappable = InputContainer:extend{ callback = nil, hold_callback = nil, width = nil, height = nil, dimen = nil }
function Tappable:setHitArea()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    -- The ranges share the dimen table, so painting only has to move dimen.
    self.ges_events = { TapAppDock = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    if self.hold_callback then
        self.ges_events.HoldAppDock = { GestureRange:new{ ges = "hold", range = self.dimen } }
    end
end
function Tappable:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    return InputContainer.paintTo(self, bb, x, y)
end
function Tappable:onTapAppDock() if self.callback then self.callback() end return true end
function Tappable:onHoldAppDock() if self.hold_callback then self.hold_callback() end return true end

local Button = Tappable:extend{ title = "", font_size = 17, background = nil, foreground = nil, flat = false, active = false }
function Button:init()
    self:setHitArea()
    local fg = self.foreground or PALETTE.on_surface
    local bg = self.background or PALETTE.surface
    if self.active then bg, fg = PALETTE.primary, PALETTE.on_primary end
    local border = self.flat and 0 or scale(1)
    local inner_w, inner_h = self.width - 2 * border, self.height - 2 * border
    local frame_bg = bg
    if self.flat then frame_bg = self.active and bg or self.background end
    self[1] = FrameContainer:new{
        width = self.width, height = self.height, padding = 0, bordersize = border, color = PALETTE.outline,
        radius = math.min(scale(24), math.floor(self.height / 2)), background = frame_bg,
        CenterContainer:new{ dimen = Geom:new{ w = inner_w, h = inner_h }, label(self.title, self.font_size, fg, true, inner_w - scale(8)) },
    }
end

local SearchBar = Tappable:extend{ text = "", active = false }
function SearchBar:init()
    self:setHitArea()
    local border = scale(1)
    local inner_w, inner_h = self.width - 2 * border, self.height - 2 * border
    local icon_size = scale(20)
    local text = label(self.text, 18, self.active and PALETTE.on_surface or PALETTE.on_variant, self.active, self.width - scale(72))
    local text_h = text:getSize().h
    self[1] = FrameContainer:new{
        width = self.width, height = self.height, padding = 0, bordersize = border, color = PALETTE.outline,
        radius = math.floor(self.height / 2), background = PALETTE.surface,
        stack(inner_w, inner_h, {
            { widget = magnifier(icon_size, PALETTE.on_variant), x = scale(18), y = math.floor((inner_h - icon_size) / 2) },
            { widget = text, x = scale(52), y = math.floor((inner_h - text_h) / 2) },
        }),
    }
end

local FileRow = Tappable:extend{ entry = nil, title = nil, subtitle = nil, selecting = false, selected = false }
function FileRow:init()
    self:setHitArea()
    local width, height = self.width, self.height
    local pad = scale(10)
    local icon_size = height - 2 * pad
    local x = scale(4)
    local items = {}
    if self.selecting then
        local box = scale(24)
        table.insert(items, { widget = checkbox(box, self.selected), x = x, y = math.floor((height - box) / 2) })
        x = x + box + scale(12)
    end
    table.insert(items, { widget = FileIcon:new{ entry = self.entry, size = icon_size }, x = x, y = pad })
    x = x + icon_size + scale(14)
    local text_w = width - x - scale(8)
    local fg = self.selected and PALETTE.on_primary or PALETTE.on_surface
    local title = label(self.title, 20, fg, true, text_w)
    local subtitle = label(self.subtitle, 15, self.selected and PALETTE.on_primary or PALETTE.on_variant, false, text_w)
    local gap = scale(2)
    local title_h, subtitle_h = title:getSize().h, subtitle:getSize().h
    local y = math.max(0, math.floor((height - title_h - subtitle_h - gap) / 2))
    table.insert(items, { widget = title, x = x, y = y })
    table.insert(items, { widget = subtitle, x = x, y = y + title_h + gap })
    self.layout = { google_files_row = true, title = self.title, subtitle = self.subtitle }
    self[1] = FrameContainer:new{
        width = width, height = height, padding = 0, bordersize = 0, radius = scale(12),
        background = self.selected and PALETTE.primary or nil,
        stack(width, height, items),
    }
end

local FileTile = Tappable:extend{ entry = nil, detail = nil, selecting = false, selected = false, recent = false }
function FileTile:init()
    self:setHitArea()
    local width, height = self.width, self.height
    local entry = self.entry or {}
    local border = scale(1)
    local inner_w, inner_h = width - 2 * border, height - 2 * border
    local icon_size = math.min(math.floor(height * .42), inner_w - scale(24))
    local top = scale(10)
    local fg = self.selected and PALETTE.on_primary or PALETTE.on_surface
    local name = label(entry.name or "", 16, fg, true, inner_w - scale(14))
    local detail = label(self.detail or "", 13, self.selected and PALETTE.on_primary or PALETTE.on_variant, false, inner_w - scale(14))
    local name_size, detail_size = name:getSize(), detail:getSize()
    local name_y = top + icon_size + scale(8)
    local items = {
        { widget = FileIcon:new{ entry = entry, size = icon_size }, x = math.floor((inner_w - icon_size) / 2), y = top },
        { widget = name, x = math.max(scale(6), math.floor((inner_w - name_size.w) / 2)), y = name_y },
        { widget = detail, x = math.max(scale(6), math.floor((inner_w - detail_size.w) / 2)), y = name_y + name_size.h + scale(1) },
    }
    if self.selecting then
        table.insert(items, { widget = checkbox(scale(22), self.selected), x = scale(8), y = scale(8) })
    end
    self.layout = { google_files_tile = true, name = entry.name, recent = self.recent }
    self[1] = FrameContainer:new{
        width = width, height = height, padding = 0, bordersize = border, color = PALETTE.outline, radius = scale(14),
        background = self.selected and PALETTE.primary or PALETTE.surface,
        stack(inner_w, inner_h, items),
    }
end

local CategoryCard = Tappable:extend{ title = nil, subtitle = nil, category = "documents" }
function CategoryCard:init()
    self:setHitArea()
    local border = scale(1)
    local inner_w, inner_h = self.width - 2 * border, self.height - 2 * border
    local badge = inner_h - 2 * scale(8)
    local x = scale(10) + badge + scale(12)
    local text_w = inner_w - x - scale(8)
    local title = label(self.title, 18, PALETTE.on_surface, true, text_w)
    local subtitle = label(self.subtitle, 14, PALETTE.on_variant, false, text_w)
    local title_h, subtitle_h = title:getSize().h, subtitle:getSize().h
    local y = math.max(0, math.floor((inner_h - title_h - subtitle_h) / 2))
    self.layout = { google_files_category = true, title = self.title, subtitle = self.subtitle }
    self[1] = FrameContainer:new{
        width = self.width, height = self.height, padding = 0, bordersize = border, color = PALETTE.outline, radius = scale(16), background = PALETTE.surface,
        stack(inner_w, inner_h, {
            { widget = FileIcon:new{ category = self.category, size = badge }, x = scale(10), y = scale(8) },
            { widget = title, x = x, y = y },
            { widget = subtitle, x = x, y = y + title_h },
        }),
    }
end

-- Static blocks -----------------------------------------------------------
local function titleBlock(width, height, title, subtitle)
    local main = label(title, 20, PALETTE.on_surface, true, width, "cfont")
    local sub = label(subtitle, 14, PALETTE.on_variant, false, width)
    local main_h, sub_h = main:getSize().h, sub:getSize().h
    local y = math.max(0, math.floor((height - main_h - sub_h) / 2))
    return stack(width, height, { { widget = main, x = 0, y = y }, { widget = sub, x = 0, y = y + main_h } })
end
local function sectionTitle(width, text)
    return label(text, 19, PALETTE.on_surface, true, width, "cfont")
end
local function messageCard(width, height, title, subtitle)
    local border = scale(1)
    local inner_w, inner_h = width - 2 * border, height - 2 * border
    local main = label(title, 18, PALETTE.on_surface, true, inner_w - scale(24))
    local sub = label(subtitle or "", 14, PALETTE.on_variant, false, inner_w - scale(24))
    local main_size, sub_size = main:getSize(), sub:getSize()
    local y = math.max(0, math.floor((inner_h - main_size.h - sub_size.h) / 2))
    return FrameContainer:new{
        width = width, height = height, padding = 0, bordersize = border, color = PALETTE.outline, radius = scale(16), background = PALETTE.surface,
        stack(inner_w, inner_h, {
            { widget = main, x = math.floor((inner_w - main_size.w) / 2), y = y },
            { widget = sub, x = math.floor((inner_w - sub_size.w) / 2), y = y + main_size.h },
        }),
    }
end
local function storageCard(width, height, usage)
    local border, pad = scale(1), scale(14)
    local inner_w, inner_h = width - 2 * border, height - 2 * border
    local bar_w, bar_h = inner_w - 2 * pad, scale(10)
    local ratio = clamp(usage.used / usage.total, 0, 1)
    local fill_w = ratio > 0 and math.max(bar_h, math.floor(bar_w * ratio)) or 0
    local title = label(_("Internal storage"), 18, PALETTE.on_surface, true, bar_w)
    local sub = label(string.format(_("%s used of %s"), humanSize(usage.used), humanSize(usage.total)), 14, PALETTE.on_variant, false, bar_w)
    local title_h, sub_h = title:getSize().h, sub:getSize().h
    local gap = math.max(scale(4), math.floor((inner_h - title_h - bar_h - sub_h) / 4))
    local y_title = gap
    local y_bar = y_title + title_h + gap
    local y_sub = y_bar + bar_h + gap
    local track = FrameContainer:new{ width = bar_w, height = bar_h, padding = 0, bordersize = 0, radius = math.floor(bar_h / 2), background = PALETTE.secondary, emptySizedWidget(bar_w, bar_h) }
    local items = {
        { widget = title, x = pad, y = y_title },
        { widget = track, x = pad, y = y_bar },
    }
    if fill_w > 0 then
        table.insert(items, { widget = FrameContainer:new{ width = fill_w, height = bar_h, padding = 0, bordersize = 0, radius = math.floor(bar_h / 2), background = PALETTE.on_primary, emptySizedWidget(fill_w, bar_h) }, x = pad, y = y_bar })
    end
    table.insert(items, { widget = sub, x = pad, y = y_sub })
    return FrameContainer:new{
        width = width, height = height, padding = 0, bordersize = border, color = PALETTE.outline, radius = scale(16), background = PALETTE.surface,
        stack(inner_w, inner_h, items),
    }
end

-- Vertical budget of the home screen (in density independent units). If the
-- screen is short, tiles shrink first, then the storage card disappears.
local function homeMetrics(height, landscape, want_storage)
    local unit = scale(100) / 100
    local available = height / unit
    local m = { tile = 112, card = 60, chip = 44, storage = 80, storage_on = want_storage, cat_rows = landscape and 2 or 3, chip_rows = landscape and 1 or 2 }
    local function total()
        local sum = 16 + 48 + 14 + 28 + m.tile + 14 + 28 + m.cat_rows * m.card + (m.cat_rows - 1) * 8 + 14
            + m.chip_rows * m.chip + (m.chip_rows - 1) * 8 + 16
        if m.storage_on then sum = sum + m.storage + 14 end
        return sum
    end
    local guard = 0
    while total() > available and guard < 60 do
        guard = guard + 1
        if m.tile > 84 then m.tile = m.tile - 4
        elseif m.card > 50 then m.card = m.card - 2
        elseif m.storage_on then m.storage_on = false
        elseif m.chip > 40 then m.chip = m.chip - 2
        else break end
    end
    return m
end

---------------------------------------------------------------------------
-- State and preferences
---------------------------------------------------------------------------
function FileBrowser:new() return setmetatable({}, self) end
function FileBrowser:_ensureStandardFolders()
    -- Sort my files is strictly virtual: it must never create category folders,
    -- move a file or otherwise alter the reader's storage.
    return true
end
function FileBrowser:_preferences(context)
    local appdock = context and context.manager and context.manager.appdock
    local preferences, owner
    if appdock and type(appdock.settings) == "table" then
        appdock.settings.file_browser = type(appdock.settings.file_browser) == "table" and appdock.settings.file_browser or {}
        preferences, owner = appdock.settings.file_browser, appdock
    else
        self._fallback_preferences = self._fallback_preferences or {}
        preferences, owner = self._fallback_preferences, nil
    end
    preferences.sort_category = preferences.sort_category or "all"
    preferences.show_hidden = preferences.show_hidden == true
    preferences.hidden_paths = type(preferences.hidden_paths) == "table" and preferences.hidden_paths or {}
    preferences.sort_by = preferences.sort_by or "name"
    preferences.sort_desc = preferences.sort_desc == true
    preferences.view_mode = preferences.view_mode == "grid" and "grid" or "list"
    preferences.recent = type(preferences.recent) == "table" and preferences.recent or {}
    return preferences, owner
end
function FileBrowser:_savePreferences(context)
    local _preferences, appdock = self:_preferences(context)
    if appdock and appdock._saveSettings then appdock:_saveSettings() end
end
function FileBrowser:_ensureState(instance, context)
    self:_ensureStandardFolders()
    instance.file_browser = instance.file_browser or {
        path = STORAGE_ROOT, error = nil, entries = nil, home_mode = true, sort_mode = false, query = "", category = nil, recent_files = {},
    }
    local state = instance.file_browser
    state.sort_mode = state.sort_mode == true
    state.query = state.query or ""
    state.page = state.page or 1
    state.selecting = state.selecting == true
    state.selected = type(state.selected) == "table" and state.selected or {}
    return state
end
local function resetView(state)
    state.page, state.selecting, state.selected = 1, false, {}
    state.query, state.search_entries, state.search_truncated = "", nil, false
    state.search_origin, state.search_scope = nil, nil
    state.entries, state.error = nil, nil
end

function FileBrowser:_rememberRecent(context, path)
    local preferences = self:_preferences(context)
    local list = { path }
    for _i, existing in ipairs(preferences.recent) do
        if existing ~= path and #list < RECENT_LIMIT then table.insert(list, existing) end
    end
    preferences.recent = list
    self:_savePreferences(context)
end
function FileBrowser:_recentEntries(context, state)
    if state.recent_cache then return state.recent_cache end
    local preferences = self:_preferences(context)
    local entries, alive, changed = {}, {}, false
    for _i, path in ipairs(preferences.recent) do
        local attributes = type(path) == "string" and lfs.attributes(path) or nil
        if attributes and attributes.mode == "file" then
            local entry = self:_entryFromAttributes(path, basename(path), attributes)
            if entry then table.insert(entries, entry); table.insert(alive, path) end
        else
            changed = true
        end
    end
    if changed then preferences.recent = alive; self:_savePreferences(context) end
    state.recent_cache = entries
    return entries
end

---------------------------------------------------------------------------
-- Reading storage
---------------------------------------------------------------------------
function FileBrowser:_entryFromAttributes(fullpath, name, attributes)
    if type(fullpath) ~= "string" or type(name) ~= "string" or type(attributes) ~= "table" then return nil end
    if attributes.mode ~= "directory" and attributes.mode ~= "file" then return nil end
    local is_file = attributes.mode == "file"
    local lower = fullpath:lower()
    return {
        name = name, path = fullpath, is_dir = not is_file, size = tonumber(attributes.size) or 0,
        modified = tonumber(attributes.modification) or 0,
        sort_key = naturalKey(name),
        -- `supported` is resolved lazily (see _isSupported): asking the document
        -- registry for every file of a big folder made listings slow.
        supported = nil,
        is_executable = is_file and type(attributes.permissions) == "string" and attributes.permissions:find("x", 1, true) ~= nil,
        is_hidden = hiddenPath(fullpath),
        is_lua = is_file and lower:match("%.lua$") ~= nil,
        is_markup = is_file and (lower:match("%.md$") or lower:match("%.markdown$") or lower:match("%.mdown$") or lower:match("%.mkdn$")) ~= nil,
        is_dreader = is_file and (lower:match("%.epub$") or lower:match("%.html$") or lower:match("%.htm$") or lower:match("%.xhtml$") or lower:match("%.md$") or lower:match("%.markdown$")) ~= nil,
    }
end
function FileBrowser:_isSupported(entry)
    if entry.is_dir then return false end
    if entry.supported == nil then
        local ok, value = pcall(DocumentRegistry.hasProvider, DocumentRegistry, entry.path)
        entry.supported = ok and value == true
    end
    return entry.supported
end

function FileBrowser:_readEntries(path, preferences)
    if type(path) ~= "string" or path == "" then return nil, _("This folder cannot be read.") end
    preferences = preferences or {}
    local entries = {}
    local ok, iterator, directory_object = pcall(lfs.dir, path)
    if not ok or not iterator then return nil, _("This folder cannot be read.") end
    for name in iterator, directory_object do
        if name ~= "." and name ~= ".." and (preferences.show_hidden == true or name:sub(1, 1) ~= ".") then
            local fullpath = path == "/" and ("/" .. name) or (path .. "/" .. name)
            local attributes_ok, attributes = pcall(lfs.attributes, fullpath)
            if attributes_ok and attributes then
                local entry = self:_entryFromAttributes(fullpath, name, attributes)
                if entry then table.insert(entries, entry) end
            end
        end
    end
    sortEntries(entries, preferences, false)
    return entries
end

function FileBrowser:_readSortedEntries(root, limit, hidden_paths, show_hidden, preferences)
    if type(root) ~= "string" or not isInside(root, STORAGE_ROOT) then
        return nil, _("This folder cannot be read.")
    end
    local entries, visited = {}, {}
    limit = math.max(1, math.floor(tonumber(limit) or VIRTUAL_SORT_LIMIT))
    hidden_paths = type(hidden_paths) == "table" and hidden_paths or {}
    local function include(entry)
        local hidden = entry.is_hidden or hidden_paths[entry.path] == true
        entry.is_hidden_for_sort = hidden
        return show_hidden == true or not hidden
    end
    local function visit(path, required)
        if #entries >= limit or visited[path] then return true end
        visited[path] = true
        local ok, iterator, directory_object = pcall(lfs.dir, path)
        if not ok or not iterator then return not required end
        for name in iterator, directory_object do
            if #entries >= limit then break end
            if name ~= "." and name ~= ".." then
                local fullpath = path == "/" and ("/" .. name) or (path .. "/" .. name)
                local link = lstat(fullpath)
                if link and link.mode ~= "link" then
                    if link.mode == "directory" then
                        -- A virtual sort never follows symlinks. This keeps a
                        -- reader's storage tree bounded and prevents cycles.
                        local entry = self:_entryFromAttributes(fullpath, name, link)
                        if entry then
                            entry.sort_category = "folders"
                            entry.virtual_path = fullpath
                            if include(entry) then table.insert(entries, entry) end
                            -- A hidden directory also hides its descendants
                            -- until the user explicitly asks to show hidden
                            -- items. Nothing on disk is renamed or moved.
                            if show_hidden == true or not entry.is_hidden_for_sort then visit(fullpath, false) end
                        end
                    elseif link.mode == "file" then
                        local entry = self:_entryFromAttributes(fullpath, name, link)
                        if entry then
                            entry.sort_category = categoryFor(entry)
                            entry.virtual_path = fullpath
                            if include(entry) then table.insert(entries, entry) end
                        end
                    end
                end
            end
        end
        return true
    end
    if not visit(root, true) then return nil, _("This folder cannot be read.") end
    sortEntries(entries, preferences or { sort_by = "name" }, true)
    return entries
end

-- Recursive name search below `root` (bounded, never follows symlinks).
function FileBrowser:_readSearch(root, query, preferences)
    if type(root) ~= "string" or not isInside(root, STORAGE_ROOT) then root = STORAGE_ROOT end
    local needle = trim(query):lower()
    local results, nodes, truncated = {}, 0, false
    local show_hidden = preferences and preferences.show_hidden == true
    local function visit(path, depth)
        if truncated or depth > 16 then return end
        local ok, iterator, directory_object = pcall(lfs.dir, path)
        if not ok or not iterator then return end
        for name in iterator, directory_object do
            if truncated then return end
            if name ~= "." and name ~= ".." and (show_hidden or name:sub(1, 1) ~= ".") then
                nodes = nodes + 1
                if nodes > SEARCH_NODE_LIMIT or #results >= SEARCH_RESULT_LIMIT then truncated = true; return end
                local fullpath = path .. "/" .. name
                local attributes = lstat(fullpath)
                if attributes and attributes.mode ~= "link" then
                    if name:lower():find(needle, 1, true) then
                        local entry = self:_entryFromAttributes(fullpath, name, attributes)
                        if entry then table.insert(results, entry) end
                    end
                    if attributes.mode == "directory" then visit(fullpath, depth + 1) end
                end
            end
        end
    end
    visit(root, 0)
    sortEntries(results, preferences, false)
    return results, truncated
end

-- Cheap statistics for the category cards (extension based, no registry calls).
function FileBrowser:_scanStats(preferences)
    local stats = { truncated = false }
    for _i, id in ipairs(CATEGORY_ORDER) do stats[id] = { count = 0, bytes = 0 } end
    local nodes = 0
    local show_hidden = preferences and preferences.show_hidden == true
    local function visit(path, depth)
        if stats.truncated or depth > 14 then return end
        local ok, iterator, directory_object = pcall(lfs.dir, path)
        if not ok or not iterator then return end
        for name in iterator, directory_object do
            if stats.truncated then return end
            if name ~= "." and name ~= ".." and (show_hidden or name:sub(1, 1) ~= ".") then
                nodes = nodes + 1
                if nodes > SCAN_NODE_LIMIT then stats.truncated = true; return end
                local fullpath = path .. "/" .. name
                local attributes = lstat(fullpath)
                if attributes and attributes.mode == "directory" then
                    stats.folders.count = stats.folders.count + 1
                    visit(fullpath, depth + 1)
                elseif attributes and attributes.mode == "file" then
                    local bucket = stats[categoryOf(fullpath, false)]
                    bucket.count = bucket.count + 1
                    bucket.bytes = bucket.bytes + (tonumber(attributes.size) or 0)
                end
            end
        end
    end
    visit(STORAGE_ROOT, 0)
    return stats
end

local function matches(entry, query, category)
    if query and query ~= "" then
        local hay = (entry.name .. " " .. entry.path):lower()
        if not hay:find(query:lower(), 1, true) then return false end
    end
    return not category or category == "all" or (entry.sort_category or categoryFor(entry)) == category
end
function FileBrowser:_filteredEntries(state)
    local result = {}
    for _i, entry in ipairs(state.entries or {}) do
        if matches(entry, state.query, state.category) then table.insert(result, entry) end
    end
    return result
end
function FileBrowser:_visibleEntries(state)
    if state.sort_mode then return self:_filteredEntries(state) end
    if state.query ~= "" then return state.search_entries or {} end
    return state.entries or {}
end
function FileBrowser:_resort(state, preferences)
    if state.entries then sortEntries(state.entries, preferences, state.sort_mode) end
    if state.search_entries then sortEntries(state.search_entries, preferences, false) end
end

function FileBrowser:_load(state, preferences)
    if state.sort_mode then
        state.entries, state.error = self:_readSortedEntries(STORAGE_ROOT, nil, preferences.hidden_paths, preferences.show_hidden, preferences)
    else
        state.entries, state.error = self:_readEntries(state.path, preferences)
    end
    if state.query ~= "" and not state.sort_mode then
        state.search_entries, state.search_truncated = self:_readSearch(state.search_scope or state.path, state.query, preferences)
    end
end

---------------------------------------------------------------------------
-- Navigation
---------------------------------------------------------------------------
function FileBrowser:refresh(instance, context)
    local state = self:_ensureState(instance, context)
    state.recent_cache, state.disk = nil, nil
    if not state.home_mode then self:_load(state, self:_preferences(context)) end
    context.requestRebuild("ui")
end
function FileBrowser:enterDirectory(instance, context, path)
    local attributes = type(path) == "string" and lfs.attributes(path) or nil
    if not attributes or attributes.mode ~= "directory" then
        UIManager:show(InfoMessage:new{ text = _("This folder does not exist.") })
        return
    end
    local state = self:_ensureState(instance, context)
    resetView(state)
    state.path, state.home_mode, state.sort_mode, state.category = path, false, false, nil
    self:refresh(instance, context)
end
function FileBrowser:showHome(instance, context)
    local state = self:_ensureState(instance, context)
    resetView(state)
    state.path, state.home_mode, state.sort_mode, state.category = STORAGE_ROOT, true, false, nil
    self:refresh(instance, context)
end
function FileBrowser:openInternalStorage(instance, context)
    self:enterDirectory(instance, context, STORAGE_ROOT)
end
function FileBrowser:sortMyFiles(instance, context, category)
    local preferences = self:_preferences(context)
    if category then preferences.sort_category = category end
    self:_savePreferences(context)
    local state = self:_ensureState(instance, context)
    resetView(state)
    state.path, state.home_mode, state.sort_mode, state.category = STORAGE_ROOT, false, true, preferences.sort_category or "all"
    self:refresh(instance, context)
end
function FileBrowser:setCategory(instance, context, category)
    self:sortMyFiles(instance, context, category)
end
-- One step back: clears selection/search first, then goes up a folder, then home.
function FileBrowser:goUp(instance, context)
    local state = self:_ensureState(instance, context)
    if state.home_mode then return false end
    if state.selecting then self:setSelecting(instance, context, false); return true end
    if state.query ~= "" then self:clearSearch(instance, context); return true end
    if state.sort_mode or state.path == STORAGE_ROOT or not isInside(state.path, STORAGE_ROOT) then
        self:showHome(instance, context)
    else
        self:enterDirectory(instance, context, parentPath(state.path))
    end
    return true
end
function FileBrowser:onBack(instance, context) return self:goUp(instance, context) end

---------------------------------------------------------------------------
-- Search
---------------------------------------------------------------------------
function FileBrowser:showSearch(instance, context)
    local state = self:_ensureState(instance, context)
    local keyboard
    keyboard = AppDockKeyboard:new{
        title = _("Search files"),
        placeholder = _("Name or extension"),
        value = state.query or "",
        on_change = function() end,
        on_cancel = function() UIManager:close(keyboard) end,
        on_submit = function(value)
            UIManager:nextTick(function() UIManager:close(keyboard) end)
            UIManager:nextTick(function() self:applySearch(instance, context, value) end)
        end,
    }
    UIManager:show(keyboard)
end
function FileBrowser:applySearch(instance, context, value)
    value = trim(value)
    if value == "" then self:clearSearch(instance, context); return end
    local state = self:_ensureState(instance, context)
    local preferences = self:_preferences(context)
    if state.query == "" then
        state.search_origin = state.home_mode and "home" or (state.sort_mode and "sort" or "folder")
    end
    state.query, state.page, state.selecting, state.selected = value, 1, false, {}
    if not state.sort_mode then
        if state.home_mode then state.path = STORAGE_ROOT end
        state.home_mode = false
        state.search_scope = state.path
        local info = InfoMessage:new{ text = _("Searching…") }
        UIManager:show(info)
        if UIManager.forceRePaint then UIManager:forceRePaint() end
        state.search_entries, state.search_truncated = self:_readSearch(state.search_scope, value, preferences)
        UIManager:close(info)
        if not state.entries then state.entries, state.error = self:_readEntries(state.path, preferences) end
    end
    state.home_mode = false
    context.requestRebuild("ui")
end
function FileBrowser:clearSearch(instance, context)
    local state = self:_ensureState(instance, context)
    local origin = state.search_origin
    state.query, state.search_entries, state.search_truncated, state.search_origin, state.search_scope = "", nil, false, nil, nil
    state.page, state.selecting, state.selected = 1, false, {}
    if origin == "home" then self:showHome(instance, context) else context.requestRebuild("ui") end
end

---------------------------------------------------------------------------
-- View options: sorting, grid/list, hidden files
---------------------------------------------------------------------------
function FileBrowser:setSort(instance, context, by, descending)
    local preferences = self:_preferences(context)
    if by then preferences.sort_by = by end
    if descending ~= nil then preferences.sort_desc = descending end
    self:_savePreferences(context)
    local state = self:_ensureState(instance, context)
    self:_resort(state, preferences)
    state.page = 1
    context.requestRebuild("ui")
end
function FileBrowser:setView(instance, context, mode)
    local preferences = self:_preferences(context)
    preferences.view_mode = mode == "grid" and "grid" or "list"
    self:_savePreferences(context)
    self:_ensureState(instance, context).page = 1
    context.requestRebuild("ui")
end
function FileBrowser:showSortOptions(instance, context)
    local preferences = self:_preferences(context)
    local dialog
    local function mark(active, text) return (active and "•  " or "     ") .. text end
    local buttons = {}
    for _i, by in ipairs({ "name", "date", "size", "type" }) do
        local default_desc = (by == "date" or by == "size")
        buttons[#buttons + 1] = { { text = mark(preferences.sort_by == by, sortLabel(by)), callback = function()
            UIManager:close(dialog)
            self:setSort(instance, context, by, preferences.sort_by == by and preferences.sort_desc or default_desc)
        end } }
    end
    buttons[#buttons + 1] = {
        { text = mark(not preferences.sort_desc, _("Ascending")), callback = function() UIManager:close(dialog); self:setSort(instance, context, nil, false) end },
        { text = mark(preferences.sort_desc, _("Descending")), callback = function() UIManager:close(dialog); self:setSort(instance, context, nil, true) end },
    }
    dialog = ButtonDialog:new{ title = _("Sort by"), buttons = buttons }
    UIManager:show(dialog)
end
function FileBrowser:toggleSortHidden(instance, context)
    local preferences = self:_preferences(context)
    preferences.show_hidden = not preferences.show_hidden
    self:_savePreferences(context)
    local state = self:_ensureState(instance, context)
    state.stats, state.page = nil, 1
    self:refresh(instance, context)
end
function FileBrowser:setEntryHidden(instance, context, entry, hidden)
    if not entry or not entry.virtual_path then return false end
    local preferences = self:_preferences(context)
    if hidden then preferences.hidden_paths[entry.virtual_path] = true else preferences.hidden_paths[entry.virtual_path] = nil end
    self:_savePreferences(context)
    self:refresh(instance, context)
    return true
end
function FileBrowser:showSortPicker(instance, context)
    local dialog
    local buttons = {}
    for _i, id in ipairs({ "all", "documents", "images", "videos", "audio", "apps", "folders" }) do
        buttons[#buttons + 1] = { { text = categoryTitle(id), callback = function() UIManager:close(dialog); self:sortMyFiles(instance, context, id) end } }
    end
    dialog = ButtonDialog:new{ title = _("Sort my files · virtual only"), buttons = buttons }
    UIManager:show(dialog)
end

---------------------------------------------------------------------------
-- Selection
---------------------------------------------------------------------------
function FileBrowser:setSelecting(instance, context, on, first_entry)
    local state = self:_ensureState(instance, context)
    state.selecting, state.selected = on == true, {}
    if on and first_entry then state.selected[first_entry.path] = first_entry end
    context.requestRebuild("ui")
end
function FileBrowser:toggleSelected(instance, context, entry)
    local state = self:_ensureState(instance, context)
    if state.selected[entry.path] then state.selected[entry.path] = nil else state.selected[entry.path] = entry end
    context.requestRebuild("ui")
end
function FileBrowser:selectAll(instance, context)
    local state = self:_ensureState(instance, context)
    local entries = self:_visibleEntries(state)
    local all = #entries > 0
    for _i, entry in ipairs(entries) do
        if not state.selected[entry.path] then all = false; break end
    end
    state.selected = {}
    if not all then
        for _i, entry in ipairs(entries) do state.selected[entry.path] = entry end
    end
    context.requestRebuild("ui")
end
function FileBrowser:_selectedList(state)
    local list = {}
    for _path, entry in pairs(state.selected or {}) do table.insert(list, entry) end
    table.sort(list, function(a, b) return a.path < b.path end)
    return list
end

---------------------------------------------------------------------------
-- File actions
---------------------------------------------------------------------------
function FileBrowser:_afterFileAction(instance, context, ok, err, message)
    local state = self:_ensureState(instance, context)
    state.stats, state.selecting, state.selected = nil, false, {}
    UIManager:show(InfoMessage:new{ text = ok and (message or _("Files updated.")) or (err or _("The file action failed.")), timeout = ok and 2 or nil })
    self:refresh(instance, context)
end
function FileBrowser:showRename(instance, context, entry)
    local keyboard
    keyboard = AppDockKeyboard:new{
        title = _("Rename"), placeholder = _("New name"), value = entry.name,
        on_cancel = function() UIManager:close(keyboard) end,
        on_submit = function(value)
            UIManager:nextTick(function() UIManager:close(keyboard) end)
            local name, problem = validName(value)
            if not name then UIManager:show(InfoMessage:new{ text = problem }); return end
            if name == entry.name then return end
            local target = parentPath(entry.path) .. "/" .. name
            -- FAT is case-insensitive: "a.txt" -> "A.txt" is a legal rename.
            if lfs.attributes(target) and name:lower() ~= entry.name:lower() then
                UIManager:show(InfoMessage:new{ text = _("A file or folder with this name already exists.") })
                return
            end
            local ok, err = os.rename(entry.path, target)
            if not ok then
                UIManager:show(InfoMessage:new{ text = _("Rename failed.") .. " " .. tostring(err or "") })
                return
            end
            self:_afterFileAction(instance, context, true, nil, _("Renamed."))
        end,
    }
    UIManager:show(keyboard)
end
function FileBrowser:showNewFolder(instance, context)
    local state = self:_ensureState(instance, context)
    if state.sort_mode or state.home_mode or state.query ~= "" or not validStoragePath(state.path) then
        UIManager:show(InfoMessage:new{ text = _("Open a folder first to create a new folder in it.") })
        return
    end
    local keyboard
    keyboard = AppDockKeyboard:new{
        title = _("New folder"), placeholder = _("Folder name"), value = "",
        on_cancel = function() UIManager:close(keyboard) end,
        on_submit = function(value)
            UIManager:nextTick(function() UIManager:close(keyboard) end)
            local name, problem = validName(value)
            if not name then UIManager:show(InfoMessage:new{ text = problem }); return end
            local target = state.path .. "/" .. name
            if lfs.attributes(target) then
                UIManager:show(InfoMessage:new{ text = _("A file or folder with this name already exists.") })
                return
            end
            if lfs.mkdir(target) then
                self:_afterFileAction(instance, context, true, nil, _("Folder created."))
            else
                UIManager:show(InfoMessage:new{ text = _("The folder could not be created.") })
            end
        end,
    }
    UIManager:show(keyboard)
end
function FileBrowser:showDetails(instance, context, entry)
    local attributes = lfs.attributes(entry.path) or {}
    local lines = {
        entry.name, "",
        _("Location") .. ": " .. displayPath(parentPath(entry.path)),
        _("Type") .. ": " .. typeLabel(entry),
    }
    if entry.is_dir then
        table.insert(lines, _("Contains") .. ": " .. string.format(_("%d items"), countChildren(entry.path)))
    else
        table.insert(lines, _("Size") .. ": " .. humanSize(attributes.size or entry.size) .. " (" .. tostring(attributes.size or entry.size or 0) .. " B)")
    end
    local modified = formatDate(attributes.modification or entry.modified, true)
    if modified ~= "" then table.insert(lines, _("Modified") .. ": " .. modified) end
    UIManager:show(InfoMessage:new{ text = table.concat(lines, "\n") })
end

function FileBrowser:_runTransfer(instance, context, items, destination, move)
    local info = InfoMessage:new{ text = _("Working…") }
    UIManager:show(info)
    if UIManager.forceRePaint then UIManager:forceRePaint() end
    local done, failed, first_error = 0, 0, nil
    for _i, item in ipairs(items) do
        local ok, err = transfer(item.path, destination, move)
        if ok then done = done + 1 else failed = failed + 1; first_error = first_error or err end
    end
    UIManager:close(info)
    if failed == 0 then
        self:_afterFileAction(instance, context, true, nil, move and _("Moved.") or _("Copied."))
    else
        self:_afterFileAction(instance, context, false, string.format(_("%d of %d items failed."), failed, #items) .. "\n" .. tostring(first_error or ""))
    end
end
function FileBrowser:copyOrMove(instance, context, entry, destination, move)
    if not validStoragePath(destination) then return self:_afterFileAction(instance, context, false, _("Invalid destination.")) end
    self:_runTransfer(instance, context, { entry }, destination, move)
end
function FileBrowser:showFolderPicker(instance, context, path, on_choose)
    path = (validStoragePath(path) and lfs.attributes(path, "mode") == "directory") and path or STORAGE_ROOT
    local folders = {}
    local ok, iterator, directory_object = pcall(lfs.dir, path)
    if ok and iterator then
        for name in iterator, directory_object do
            if name:sub(1, 1) ~= "." then
                local attributes = lstat(path .. "/" .. name)
                if attributes and attributes.mode == "directory" then table.insert(folders, name) end
            end
        end
    end
    table.sort(folders, function(a, b) return naturalKey(a) < naturalKey(b) end)
    local dialog
    local buttons = {
        { { text = _("Use this folder"), callback = function() UIManager:close(dialog); UIManager:nextTick(function() on_choose(path) end) end } },
    }
    if path ~= STORAGE_ROOT then
        buttons[#buttons + 1] = { { text = "‹  " .. _("Up"), callback = function()
            UIManager:close(dialog)
            UIManager:nextTick(function() self:showFolderPicker(instance, context, parentPath(path), on_choose) end)
        end } }
    end
    for index, name in ipairs(folders) do
        if index > 200 then break end
        buttons[#buttons + 1] = { { text = name .. "  ›", callback = function()
            UIManager:close(dialog)
            UIManager:nextTick(function() self:showFolderPicker(instance, context, path .. "/" .. name, on_choose) end)
        end } }
    end
    dialog = ButtonDialog:new{ title = displayPath(path), buttons = buttons, rows_per_page = { 5, 6, 7 } }
    UIManager:show(dialog)
end
function FileBrowser:chooseDestination(instance, context, items, move)
    local dialog
    local function pick(destination)
        UIManager:close(dialog)
        UIManager:nextTick(function() self:_runTransfer(instance, context, items, destination, move) end)
    end
    local buttons = { { { text = _("Internal storage"), callback = function() pick(STORAGE_ROOT) end } } }
    for _i, folder in ipairs(STANDARD_FOLDERS) do
        if lfs.attributes(STORAGE_ROOT .. "/" .. folder, "mode") == "directory" then
            buttons[#buttons + 1] = { { text = folder, callback = function() pick(STORAGE_ROOT .. "/" .. folder) end } }
        end
    end
    buttons[#buttons + 1] = { { text = _("Choose folder…"), callback = function()
        UIManager:close(dialog)
        UIManager:nextTick(function()
            self:showFolderPicker(instance, context, STORAGE_ROOT, function(destination)
                self:_runTransfer(instance, context, items, destination, move)
            end)
        end)
    end } }
    local title = move and _("Move to") or _("Copy to")
    if #items > 1 then title = title .. string.format("  (%d)", #items) end
    dialog = ButtonDialog:new{ title = title, buttons = buttons, rows_per_page = { 5, 6, 7 } }
    UIManager:show(dialog)
end
function FileBrowser:showDestinationMenu(instance, context, entry, move)
    self:chooseDestination(instance, context, { entry }, move)
end
function FileBrowser:confirmDelete(instance, context, items)
    local text
    if #items == 1 then
        text = _("Delete this item permanently?") .. "\n\n" .. items[1].path
    else
        text = string.format(_("Delete %d items permanently?"), #items)
    end
    UIManager:show(ConfirmBox:new{ text = text, ok_text = _("Delete"), ok_callback = function()
        local info = InfoMessage:new{ text = _("Working…") }
        UIManager:show(info)
        if UIManager.forceRePaint then UIManager:forceRePaint() end
        local failed, first_error = 0, nil
        for _i, item in ipairs(items) do
            local ok, err = removePath(item.path)
            if not ok then failed = failed + 1; first_error = first_error or err end
        end
        UIManager:close(info)
        if failed == 0 then
            self:_afterFileAction(instance, context, true, nil, _("Deleted."))
        else
            self:_afterFileAction(instance, context, false, string.format(_("%d of %d items failed."), failed, #items) .. "\n" .. tostring(first_error or ""))
        end
    end })
end

function FileBrowser:showEntryActions(instance, context, entry)
    local dialog
    local function closeThen(callback) return function() UIManager:close(dialog); UIManager:nextTick(callback) end end
    local state = self:_ensureState(instance, context)
    local buttons = {
        { { text = entry.is_dir and _("Open folder") or _("Open"), callback = closeThen(function() self:openEntry(instance, context, entry) end) } },
    }
    local handlers = not entry.is_dir and self:_handlers(context, entry.path) or {}
    if #handlers > 0 and context.manager and context.manager.showFileHandlerChoices then
        table.insert(buttons, { { text = _("Open with ..."), callback = closeThen(function() context.manager:showFileHandlerChoices(entry.path, handlers) end) } })
    end
    table.insert(buttons, { { text = _("Select"), callback = closeThen(function() self:setSelecting(instance, context, true, entry) end) },
                            { text = _("Details"), callback = closeThen(function() self:showDetails(instance, context, entry) end) } })
    table.insert(buttons, { { text = _("Rename"), callback = closeThen(function() self:showRename(instance, context, entry) end) } })
    table.insert(buttons, { { text = _("Move"), callback = closeThen(function() self:showDestinationMenu(instance, context, entry, true) end) },
                            { text = _("Copy"), callback = closeThen(function() self:showDestinationMenu(instance, context, entry, false) end) } })
    if state.sort_mode and entry.virtual_path then
        local preferences = self:_preferences(context)
        local hidden = preferences.hidden_paths[entry.virtual_path] == true
        table.insert(buttons, { { text = hidden and _("Show in Sort my files") or _("Hide from Sort my files"), callback = closeThen(function()
            self:setEntryHidden(instance, context, entry, not hidden)
        end) } })
    end
    table.insert(buttons, { { text = _("Delete"), callback = closeThen(function() self:confirmDelete(instance, context, { entry }) end) } })
    dialog = ButtonDialog:new{ title = entry.name, buttons = buttons, rows_per_page = { 5, 6, 7 } }
    UIManager:show(dialog)
end

function FileBrowser:showMenu(instance, context)
    local state = self:_ensureState(instance, context)
    local preferences = self:_preferences(context)
    local dialog
    local function closeThen(callback) return function() UIManager:close(dialog); UIManager:nextTick(callback) end end
    local buttons = {}
    if not state.sort_mode and state.query == "" then
        table.insert(buttons, { { text = _("New folder"), callback = closeThen(function() self:showNewFolder(instance, context) end) } })
    end
    table.insert(buttons, { { text = _("Select items"), callback = closeThen(function() self:setSelecting(instance, context, true) end) } })
    if state.sort_mode then
        table.insert(buttons, { { text = _("Filter by type"), callback = closeThen(function() self:showSortPicker(instance, context) end) } })
    end
    table.insert(buttons, { { text = preferences.show_hidden and _("Hide hidden files") or _("Show hidden files"), callback = closeThen(function() self:toggleSortHidden(instance, context) end) } })
    table.insert(buttons, { { text = _("Refresh"), callback = closeThen(function() state.stats = nil; self:refresh(instance, context) end) } })
    table.insert(buttons, { { text = _("Home"), callback = closeThen(function() self:showHome(instance, context) end) } })
    dialog = ButtonDialog:new{ title = _("Files"), buttons = buttons }
    UIManager:show(dialog)
end

---------------------------------------------------------------------------
-- Opening files
---------------------------------------------------------------------------
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
    UIManager:close(context.host)
    UIManager:nextTick(function() local ReaderUI = require("apps/reader/readerui"); ReaderUI:showReader(path) end)
end
function FileBrowser:openEntry(instance, context, entry)
    if entry.is_dir then self:enterDirectory(instance, context, entry.path); return end
    local state = self:_ensureState(instance, context)
    local handlers = self:_handlers(context, entry.path)
    local supported = self:_isSupported(entry)
    local opens = (#handlers > 0 and context.manager and context.manager.showFileHandlerChoices) or entry.is_lua or entry.is_markup or entry.is_dreader or supported
    if opens then
        self:_rememberRecent(context, entry.path)
        state.recent_cache = nil
    end
    if #handlers > 0 and context.manager and context.manager.showFileHandlerChoices then context.manager:showFileHandlerChoices(entry.path, handlers)
    elseif entry.is_lua then self:openLuaFile(instance, context, entry.path)
    elseif entry.is_markup then self:openMarkUPFile(instance, context, entry.path)
    elseif entry.is_dreader then self:openDReaderFile(instance, context, entry.path)
    else self:openFile(instance, context, entry.path, supported) end
end

---------------------------------------------------------------------------
-- Building the screen
---------------------------------------------------------------------------
function FileBrowser:_fileSubtitle(context, entry, show_location)
    local parts = {}
    if show_location then table.insert(parts, displayPath(parentPath(entry.path))) end
    table.insert(parts, entry.is_dir and _("Folder") or humanSize(entry.size))
    if not show_location then
        local date = formatDate(entry.modified)
        if date ~= "" then table.insert(parts, date) end
    end
    if not entry.is_dir and not show_location then
        local handlers = self:_handlers(context, entry.path)
        if #handlers == 1 and handlers[1].title then table.insert(parts, tostring(handlers[1].title))
        elseif #handlers > 1 then table.insert(parts, _("Open with AppDock"))
        elseif entry.is_lua then table.insert(parts, "NightLua")
        elseif entry.is_markup then table.insert(parts, "MarkUP")
        elseif entry.is_dreader then table.insert(parts, "DReader")
        elseif not self:_isSupported(entry) then table.insert(parts, _("Unsupported")) end
    end
    return table.concat(parts, "  ·  ")
end

function FileBrowser:_categoryData(stats)
    local specs = {}
    for _i, id in ipairs(CATEGORY_ORDER) do
        local spec = { id = id, title = categoryTitle(id), count = 0, bytes = 0, known = stats ~= nil }
        if stats and stats[id] then spec.count, spec.bytes = stats[id].count, stats[id].bytes end
        table.insert(specs, spec)
    end
    return specs
end

function FileBrowser:_buildSearchRow(instance, context, state, width, margin)
    local height = scale(48)
    local searching = state.query ~= ""
    local clear_w = searching and (height + scale(8)) or 0
    local widgets = {
        SearchBar:new{
            width = width - 2 * margin - clear_w, height = height, active = searching,
            text = searching and state.query or _("Search files"),
            callback = function() self:showSearch(instance, context) end,
        },
    }
    if searching then
        table.insert(widgets, Button:new{ title = "×", font_size = 26, width = height, height = height, callback = function() self:clearSearch(instance, context) end })
    end
    return rowOf(margin, scale(8), widgets)
end

function FileBrowser:_buildToolbar(instance, context, state, preferences, width, margin, total)
    local height, gap = scale(48), scale(6)
    local back_w = scale(48)
    local searching = state.query ~= ""
    if state.selecting then
        local count = 0
        for _path in pairs(state.selected) do count = count + 1 end
        local all_w = scale(64)
        local title_w = width - 2 * margin - back_w - all_w - 2 * gap
        return rowOf(margin, gap, {
            Button:new{ title = "×", font_size = 26, width = back_w, height = height, callback = function() self:setSelecting(instance, context, false) end },
            titleBlock(title_w, height, string.format(_("%d selected"), count), string.format(_("%d items"), total)),
            Button:new{ title = _("All"), font_size = 16, width = all_w, height = height, callback = function() self:selectAll(instance, context) end },
        })
    end
    local menu_w, sort_w, view_w = scale(48), scale(68), scale(64)
    local title_w = width - 2 * margin - back_w - menu_w - sort_w - view_w - 4 * gap
    local show_view = title_w >= scale(110)
    if not show_view then title_w = title_w + view_w + gap end
    local title, subtitle
    if searching then
        title = _("Search results")
        subtitle = state.query .. "  ·  " .. string.format(_("%d items"), total) .. (state.search_truncated and "+" or "")
    elseif state.sort_mode then
        title = categoryTitle(state.category or "all")
        subtitle = _("Virtual view · nothing is moved")
    else
        title = state.path == STORAGE_ROOT and _("Internal storage") or basename(state.path)
        subtitle = displayPath(state.path)
    end
    local widgets = {
        Button:new{ title = "‹", font_size = 30, width = back_w, height = height, callback = function() self:goUp(instance, context) end },
        titleBlock(title_w, height, title, subtitle),
        Button:new{ title = _("Sort"), font_size = 16, width = sort_w, height = height, callback = function() self:showSortOptions(instance, context) end },
    }
    if show_view then
        table.insert(widgets, Button:new{
            title = preferences.view_mode == "grid" and _("List") or _("Grid"), font_size = 16, width = view_w, height = height,
            callback = function() self:setView(instance, context, preferences.view_mode == "grid" and "list" or "grid") end,
        })
    end
    table.insert(widgets, Button:new{ title = "···", font_size = 24, width = menu_w, height = height, callback = function() self:showMenu(instance, context) end })
    return rowOf(margin, gap, widgets)
end

function FileBrowser:_fillBrowse(content, instance, context, state, preferences, width, height, landscape)
    local margin, gap = scale(16), scale(8)
    local entries = self:_visibleEntries(state)
    local total = #entries
    local grid = preferences.view_mode == "grid"
    local search_h, tool_h = scale(48), scale(48)
    table.insert(content, vspan(margin))
    table.insert(content, self:_buildSearchRow(instance, context, state, width, margin))
    table.insert(content, vspan(scale(10)))
    table.insert(content, self:_buildToolbar(instance, context, state, preferences, width, margin, total))
    table.insert(content, vspan(scale(8)))
    local used = margin + search_h + scale(10) + tool_h + scale(8)
    local bar_h = state.selecting and scale(52) or 0
    local footer_h = scale(44)
    local reserve = margin + footer_h + (bar_h > 0 and (bar_h + scale(8)) or 0)
    local list_h = math.max(scale(80), height - used - reserve)

    local row_h = scale(64)
    local per_page, columns, tile_h, tile_w = 1, 1, scale(124), 0
    if grid then
        columns = landscape and 5 or 3
        tile_w = math.floor((width - 2 * margin - (columns - 1) * gap) / columns)
        local rows = math.max(1, math.floor((list_h + gap) / (tile_h + gap)))
        per_page = rows * columns
    else
        per_page = math.max(1, math.floor(list_h / (row_h + scale(1))))
    end
    local pages = math.max(1, math.ceil(total / per_page))
    state.page = clamp(state.page or 1, 1, pages)
    local first = (state.page - 1) * per_page + 1
    local last = math.min(total, first + per_page - 1)
    local used_list = 0
    local searching = state.query ~= ""

    if total == 0 then
        local title = searching and _("No matching files") or _("This folder is empty")
        local subtitle = searching and _("Try a different name or extension") or displayPath(state.path)
        if state.sort_mode and not searching then title, subtitle = _("Nothing to show here"), _("Files of this type will appear here") end
        table.insert(content, rowOf(margin, 0, { messageCard(width - 2 * margin, math.min(list_h, scale(110)), title, subtitle) }))
        used_list = math.min(list_h, scale(110))
    elseif grid then
        local index = first
        while index <= last do
            local tiles = {}
            for _col = 1, columns do
                if index > last then break end
                local entry = entries[index]
                table.insert(tiles, FileTile:new{
                    entry = entry, detail = entry.is_dir and _("Folder") or humanSize(entry.size), width = tile_w, height = tile_h,
                    selecting = state.selecting, selected = state.selected[entry.path] ~= nil,
                    callback = function()
                        if state.selecting then self:toggleSelected(instance, context, entry) else self:openEntry(instance, context, entry) end
                    end,
                    hold_callback = function()
                        if state.selecting then self:toggleSelected(instance, context, entry) else self:showEntryActions(instance, context, entry) end
                    end,
                })
                index = index + 1
            end
            table.insert(content, rowOf(margin, gap, tiles))
            table.insert(content, vspan(gap))
            used_list = used_list + tile_h + gap
        end
    else
        for index = first, last do
            local entry = entries[index]
            local selected = state.selected[entry.path] ~= nil
            local more_w = state.selecting and 0 or scale(48)
            local widgets = {
                FileRow:new{
                    entry = entry, title = entry.name, subtitle = self:_fileSubtitle(context, entry, searching),
                    width = width - 2 * margin - more_w, height = row_h, selecting = state.selecting, selected = selected,
                    callback = function()
                        if state.selecting then self:toggleSelected(instance, context, entry) else self:openEntry(instance, context, entry) end
                    end,
                    hold_callback = function()
                        if state.selecting then self:toggleSelected(instance, context, entry) else self:showEntryActions(instance, context, entry) end
                    end,
                },
            }
            if more_w > 0 then
                table.insert(widgets, Button:new{
                    title = "···", font_size = 22, flat = true, width = more_w, height = row_h,
                    callback = function() self:showEntryActions(instance, context, entry) end,
                })
            end
            table.insert(content, rowOf(margin, 0, widgets))
            table.insert(content, rowOf(margin, 0, { divider(width - 2 * margin) }))
            used_list = used_list + row_h + scale(1)
        end
    end
    table.insert(content, vspan(math.max(0, list_h - used_list)))

    -- Footer: item count / paging.
    local pager_w = scale(56)
    local info
    if pages > 1 then
        info = string.format("%d / %d  ·  %s", state.page, pages, string.format(_("%d items"), total))
    else
        info = string.format(_("%d items"), total) .. "  ·  " .. sortLabel(preferences.sort_by)
    end
    local previous_widget = emptySizedWidget(pager_w, footer_h)
    local next_widget = emptySizedWidget(pager_w, footer_h)
    if state.page > 1 then
        previous_widget = Button:new{ title = "‹", font_size = 28, width = pager_w, height = footer_h, callback = function()
            state.page = state.page - 1; context.requestRebuild("ui")
        end }
    end
    if state.page < pages then
        next_widget = Button:new{ title = "›", font_size = 28, width = pager_w, height = footer_h, callback = function()
            state.page = state.page + 1; context.requestRebuild("ui")
        end }
    end
    table.insert(content, rowOf(margin, 0, { previous_widget, centeredText(width - 2 * margin - 2 * pager_w, footer_h, info, 15, PALETTE.on_variant, false), next_widget }))

    if bar_h > 0 then
        table.insert(content, vspan(scale(8)))
        local selected_items = self:_selectedList(state)
        local button_w = math.floor((width - 2 * margin - 2 * gap) / 3)
        local function needSelection(action)
            return function()
                local items = self:_selectedList(state)
                if #items == 0 then UIManager:show(InfoMessage:new{ text = _("Select at least one item first."), timeout = 2 }); return end
                action(items)
            end
        end
        table.insert(content, rowOf(margin, gap, {
            Button:new{ title = _("Move"), width = button_w, height = bar_h, active = #selected_items > 0, callback = needSelection(function(items) self:chooseDestination(instance, context, items, true) end) },
            Button:new{ title = _("Copy"), width = button_w, height = bar_h, callback = needSelection(function(items) self:chooseDestination(instance, context, items, false) end) },
            Button:new{ title = _("Delete"), width = button_w, height = bar_h, callback = needSelection(function(items) self:confirmDelete(instance, context, items) end) },
        }))
    end
    return pages, total
end

function FileBrowser:_fillHome(content, instance, context, state, preferences, width, height, landscape)
    local margin, gap, section = scale(16), scale(8), scale(14)
    local inner_w = width - 2 * margin
    if state.disk == nil then state.disk = diskUsage(STORAGE_ROOT) or false end
    local metrics = homeMetrics(height, landscape, state.disk ~= false)

    -- Category numbers are computed after the first paint so the home screen
    -- appears instantly even with a huge library.
    if not state.stats and not state.stats_pending then
        state.stats_pending = true
        UIManager:nextTick(function()
            local ok, stats = pcall(self._scanStats, self, preferences)
            state.stats = ok and stats or { truncated = false }
            state.stats_pending = false
            context.requestRebuild("ui")
        end)
    end

    table.insert(content, vspan(margin))
    table.insert(content, self:_buildSearchRow(instance, context, state, width, margin))
    table.insert(content, vspan(section))

    -- Recent files
    local recent = self:_recentEntries(context, state)
    table.insert(content, rowOf(margin, 0, { sectionTitle(inner_w, _("Recent files")) }))
    table.insert(content, vspan(scale(6)))
    local tile_h = scale(metrics.tile)
    if #recent == 0 then
        table.insert(content, rowOf(margin, 0, { messageCard(inner_w, tile_h, _("No recent files yet"), _("Files you open will show up here")) }))
    else
        local tile_count = landscape and 5 or 3
        local tile_w = math.floor((inner_w - (tile_count - 1) * gap) / tile_count)
        local tiles = {}
        for index = 1, math.min(tile_count, #recent) do
            local entry = recent[index]
            table.insert(tiles, FileTile:new{
                entry = entry, recent = true, detail = humanSize(entry.size), width = tile_w, height = tile_h,
                callback = function() self:openEntry(instance, context, entry) end,
                hold_callback = function() self:showEntryActions(instance, context, entry) end,
            })
        end
        table.insert(content, rowOf(margin, gap, tiles))
    end
    table.insert(content, vspan(section))

    -- Categories
    table.insert(content, rowOf(margin, 0, { sectionTitle(inner_w, _("Categories")) }))
    table.insert(content, vspan(scale(6)))
    local columns = landscape and 3 or 2
    local card_w = math.floor((inner_w - (columns - 1) * gap) / columns)
    local card_h = scale(metrics.card)
    local specs = self:_categoryData(state.stats)
    local index = 1
    while index <= #specs do
        local cards = {}
        for _col = 1, columns do
            local spec = specs[index]
            if not spec then break end
            local subtitle
            if not spec.known then subtitle = _("Browse")
            elseif spec.count == 0 then subtitle = _("Empty")
            elseif spec.id == "folders" then subtitle = tostring(spec.count) .. (state.stats.truncated and "+" or "")
            else subtitle = tostring(spec.count) .. (state.stats.truncated and "+" or "") .. "  ·  " .. humanSize(spec.bytes) end
            table.insert(cards, CategoryCard:new{
                title = spec.title, subtitle = subtitle, category = spec.id, width = card_w, height = card_h,
                callback = function() self:setCategory(instance, context, spec.id) end,
            })
            index = index + 1
        end
        table.insert(content, rowOf(margin, gap, cards))
        if index <= #specs then table.insert(content, vspan(gap)) end
    end
    table.insert(content, vspan(section))

    -- Storage
    if metrics.storage_on and state.disk then
        table.insert(content, rowOf(margin, 0, { storageCard(inner_w, scale(metrics.storage), state.disk) }))
        table.insert(content, vspan(section))
    end

    -- Quick access
    local chips = { { title = _("Internal storage"), callback = function() self:openInternalStorage(instance, context) end } }
    local shortcuts = 0
    for _i, folder in ipairs(STANDARD_FOLDERS) do
        if shortcuts < 2 and lfs.attributes(STORAGE_ROOT .. "/" .. folder, "mode") == "directory" then
            shortcuts = shortcuts + 1
            table.insert(chips, { title = folder, callback = function() self:enterDirectory(instance, context, STORAGE_ROOT .. "/" .. folder) end })
        end
    end
    table.insert(chips, { title = _("Sort my files"), active = true, callback = function() self:showSortPicker(instance, context) end })
    local chip_columns = landscape and 4 or 2
    local chip_w = math.floor((inner_w - (chip_columns - 1) * gap) / chip_columns)
    local chip_h = scale(metrics.chip)
    local chip_index = 1
    while chip_index <= #chips do
        local row = {}
        for _col = 1, chip_columns do
            local chip = chips[chip_index]
            if not chip then break end
            table.insert(row, Button:new{ title = chip.title, active = chip.active, width = chip_w, height = chip_h, callback = chip.callback })
            chip_index = chip_index + 1
        end
        table.insert(content, rowOf(margin, gap, row))
        if chip_index <= #chips then table.insert(content, vspan(gap)) end
    end
    return #recent
end

function FileBrowser:buildPane(instance, context)
    applyTheme(context.manager and context.manager.appdock)
    local state = self:_ensureState(instance, context)
    local preferences = self:_preferences(context)
    local width, height = context.dimen.w, context.dimen.h
    local landscape = width > height * 1.15
    if not state.home_mode and not state.entries and not state.error then
        self:_load(state, preferences)
    end
    local pane = WidgetContainer:new{ dimen = Geom:new{ w = width, h = height } }
    local content = VerticalGroup:new{ align = "left" }
    local recent_count, pages, total = 0, 1, 0
    if state.error then
        local margin = scale(16)
        table.insert(content, vspan(margin))
        table.insert(content, self:_buildSearchRow(instance, context, state, width, margin))
        table.insert(content, vspan(scale(16)))
        table.insert(content, rowOf(margin, 0, { messageCard(width - 2 * margin, scale(120), _("Folder unavailable"), state.error) }))
        table.insert(content, vspan(scale(12)))
        table.insert(content, rowOf(margin, 0, { Button:new{ title = _("Home"), active = true, width = width - 2 * margin, height = scale(48), callback = function() self:showHome(instance, context) end } }))
    elseif state.home_mode then
        recent_count = self:_fillHome(content, instance, context, state, preferences, width, height, landscape)
    else
        pages, total = self:_fillBrowse(content, instance, context, state, preferences, width, height, landscape)
    end
    pane[1] = FrameContainer:new{ width = width, height = height, padding = 0, bordersize = 0, background = PALETTE.background, content }
    pane.file_layout = {
        google_files_style = true, home_mode = state.home_mode, sort_mode = state.sort_mode, storage_root = STORAGE_ROOT,
        standard_folders = STANDARD_FOLDERS, has_search = true, has_recent = recent_count > 0, has_categories = true, has_storage = true,
        category = state.category, query = state.query, two_column = false, recent_count = recent_count,
        non_destructive_sort = true, persistent_sort_preferences = true, error = state.error ~= nil or nil,
        view_mode = preferences.view_mode, sort_by = preferences.sort_by, sort_desc = preferences.sort_desc,
        selecting = state.selecting, page = state.page, pages = pages, item_count = total, paged = true,
    }
    return pane
end

return FileBrowser
