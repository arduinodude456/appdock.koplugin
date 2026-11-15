--[[--
AppDock file chooser.

A full-screen picker that replaces every "type in a file path" dialog:

    local FileChooser = require("appdock_filechooser")
    FileChooser.pick{
        title = _("Choose picture"),
        mode = "file",                     -- "file" (default) or "folder"
        path = current_value,              -- file or folder to start at (optional)
        extensions = FileChooser.IMAGES,   -- or filter = function(name, fullpath) ... end
        hint = _("PNG, JPG, GIF, WEBP or SVG"),
        allow_clear = true, clear_text = _("Remove"),
        on_select = function(path) ... end,
        on_clear = function() ... end,     -- only with allow_clear
        on_cancel = function() ... end,
    }

Ergonomics:
  * big touch rows, folders first, natural sort, paging that fills the screen
  * location chips (internal storage, SD card, home, KOReader, root)
  * tappable breadcrumb, "up" button, swipe right = up, swipe up/down = page,
    hardware page keys and Back key
  * a file is selected with one tap (live preview for pictures) and confirmed
    with the big button, so a stray tap never commits
  * "Hidden" toggle, theme colors, color-aware painting (appdock_color)
--]]--

local Blitbuffer = require("ffi/blitbuffer") -- luacheck: ignore
local Color = require("appdock_color")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
if not ok_lfs then lfs = require("lfs") end
local ok_theme, Theme = pcall(require, "appdock_theme")
if not ok_theme or type(Theme) ~= "table" or type(Theme.getPalette) ~= "function" then Theme = nil end
local ImageWidget
pcall(function() ImageWidget = require("ui/widget/imagewidget") end)

local Screen = Device.screen
local floor, max, min = math.floor, math.max, math.min

local M = {}

M.IMAGES = { png = true, jpg = true, jpeg = true, gif = true, webp = true, svg = true, bmp = true }
M.RASTER_IMAGES = { png = true, jpg = true, jpeg = true, gif = true, webp = true, bmp = true }
M.VIDEOS = { mp4 = true, m4v = true, mkv = true, avi = true, webm = true, mov = true, flv = true, ts = true, mpg = true, mpeg = true, ["3gp"] = true }
M.AUDIO = { mp3 = true, wav = true, ogg = true, flac = true, aac = true, m4a = true, opus = true }
M.FONTS = { ttf = true, otf = true }

local ENTRY_LIMIT = 4000
local PREVIEW_MAX_BYTES = 6 * 1024 * 1024
local show_hidden_default = false -- remembered for the session

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function scale(n) return Screen:scaleBySize(n) end
local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local function parentPath(path)
    if not path or path == "/" then return "/" end
    local parent = path:match("^(.*)/[^/]+$")
    if not parent or parent == "" then return "/" end
    return parent
end
local function baseName(path)
    if path == "/" then return "/" end
    return path:match("([^/]+)$") or path
end
local function extOf(name)
    return (name and name:lower():match("%.([^./]+)$")) or ""
end
local function isDir(path)
    return type(path) == "string" and path ~= "" and lfs.attributes(path, "mode") == "directory"
end
local function isInside(path, root)
    if root == "/" then return true end
    return path == root or path:sub(1, #root + 1) == root .. "/"
end
local function naturalKey(name)
    return (tostring(name or ""):lower():gsub("%d+", function(d)
        if #d < 12 then return string.rep("0", 12 - #d) .. d end
        return d
    end))
end
local function humanSize(size)
    size = tonumber(size) or 0
    if size < 1024 then return string.format("%d B", size) end
    if size < 1024 * 1024 then return string.format("%.1f KB", size / 1024) end
    if size < 1024 * 1024 * 1024 then return string.format("%.1f MB", size / (1024 * 1024)) end
    return string.format("%.1f GB", size / (1024 * 1024 * 1024))
end
local function formatDate(ts)
    ts = tonumber(ts)
    if not ts or ts <= 0 then return "" end
    local ok, text = pcall(os.date, "%Y-%m-%d", ts)
    return ok and text or ""
end
local function joinNonEmpty(sep, ...)
    local parts = {}
    for _i = 1, select("#", ...) do
        local v = select(_i, ...)
        if v and v ~= "" then parts[#parts + 1] = v end
    end
    return table.concat(parts, sep)
end

-- Rounded rectangle from horizontal spans (cheap and crisp on E-Ink).
local function roundRect(bb, x, y, w, h, r, color, mode)
    w, h = floor(w), floor(h)
    if w <= 0 or h <= 0 then return end
    r = max(0, min(floor(r or 0), floor(w / 2), floor(h / 2)))
    if r == 0 then Color.paintRect(bb, x, y, w, h, color, mode); return end
    if h - 2 * r > 0 then Color.paintRect(bb, x, y + r, w, h - 2 * r, color, mode) end
    for row = 0, r - 1 do
        local dy = r - row - .5
        local inset = max(0, math.ceil(r - math.sqrt(max(0, r * r - dy * dy))))
        local span = max(1, w - 2 * inset)
        Color.paintRect(bb, x + inset, y + row, span, 1, color, mode)
        Color.paintRect(bb, x + inset, y + h - 1 - row, span, 1, color, mode)
    end
end
local function roundFrame(bb, x, y, w, h, r, t, color, fill, mode)
    roundRect(bb, x, y, w, h, r, color, mode)
    roundRect(bb, x + t, y + t, w - 2 * t, h - 2 * t, max(0, r - t), fill, mode)
end

---------------------------------------------------------------------------
-- Storage locations (the chips)
---------------------------------------------------------------------------
local function locations()
    local list, seen = {}, {}
    local function add(label, path)
        if type(path) == "string" and path ~= "" and not seen[path] and isDir(path) then
            seen[path] = true
            list[#list + 1] = { label = label, path = path }
        end
    end
    add(_("Internal"), "/mnt/onboard")
    add(_("SD card"), "/mnt/sd")
    add(_("Home"), Device.home_dir)
    local ok, DataStorage = pcall(require, "datastorage")
    if ok and DataStorage and DataStorage.getDataDir then
        local ok_dir, dir = pcall(DataStorage.getDataDir, DataStorage)
        if ok_dir then add("KOReader", dir) end
    end
    add(_("Root"), "/")
    return list
end

---------------------------------------------------------------------------
-- Widget
---------------------------------------------------------------------------
local Chooser = InputContainer:extend{
    title = nil, mode = "file", path = nil, extensions = nil, filter = nil, hint = nil,
    allow_clear = false, clear_text = nil,
    on_select = nil, on_clear = nil, on_cancel = nil,
    covers_fullscreen = true,
}

local ACCENT = {
    folder = { 255, 233, 186, 176, 112, 0 },
    image  = { 219, 242, 226, 30, 115, 62 },
    video  = { 255, 225, 220, 176, 52, 40 },
    audio  = { 240, 226, 255, 112, 60, 170 },
    font   = { 222, 233, 255, 33, 82, 170 },
    code   = { 255, 240, 200, 140, 90, 0 },
    other  = { 232, 232, 236, 80, 80, 90 },
}
local function accentFor(entry)
    if entry.is_dir then return ACCENT.folder end
    local ext = extOf(entry.name)
    if M.IMAGES[ext] then return ACCENT.image end
    if M.VIDEOS[ext] then return ACCENT.video end
    if M.AUDIO[ext] then return ACCENT.audio end
    if M.FONTS[ext] then return ACCENT.font end
    if ext == "lua" or ext == "sh" or ext == "py" or ext == "js" or ext == "bin" or ext == "" then return ACCENT.code end
    return ACCENT.other
end

function Chooser:init()
    local size = Screen:getSize()
    self.screen_w, self.screen_h = size.w, size.h
    self.dimen = Geom:new{ x = 0, y = 0, w = size.w, h = size.h }
    self.ges_events = {
        TapAppDockChooser = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
        SwipeAppDockChooser = { GestureRange:new{ ges = "swipe", range = function() return self.dimen end } },
    }
    if Device.hasKeys and Device:hasKeys() and Device.input and Device.input.group then
        local group = Device.input.group
        self.key_events = {}
        if group.Back then self.key_events.BackAppDockChooser = { group.Back } end
        if group.PgFwd then self.key_events.NextAppDockChooser = { group.PgFwd } end
        if group.PgBack then self.key_events.PrevAppDockChooser = { group.PgBack } end
    end
    self.show_hidden = show_hidden_default
    self.mode = self.mode == "folder" and "folder" or "file"
    self.ext_set = type(self.extensions) == "table" and self.extensions or nil
    self.places = locations()
    self._hits = {}
    self._tw = {}
    self._tw_count = 0
    self._counts = {}
    self:_computeColors()

    -- Start location: a file selects itself inside its folder.
    local start = trim(self.path)
    local preselect
    if start ~= "" and not isDir(start) and lfs.attributes(start, "mode") == "file" then
        preselect = start
        start = parentPath(start)
    end
    while start ~= "" and start ~= "/" and not isDir(start) do start = parentPath(start) end
    if not isDir(start) then
        start = nil
        for _i, place in ipairs(self.places) do start = place.path; break end
        start = start or "/"
    end
    self:_layout()
    self:_load(start, preselect)
end

function Chooser:_computeColors()
    local hex
    if Theme then
        local ok, palette = pcall(Theme.getPalette)
        if ok and type(palette) == "table" and type(palette.hex) == "table" then hex = palette.hex end
    end
    hex = hex or {}
    local mode = Color.isColor()
    self.color_mode = mode
    local function parse(value, fallback)
        value = type(value) == "string" and value or fallback
        local r, g, b = value:match("^#?(%x%x)(%x%x)(%x%x)$")
        if not r then r, g, b = fallback:match("^#?(%x%x)(%x%x)(%x%x)$") end
        return Color.make(tonumber(r, 16), tonumber(g, 16), tonumber(b, 16), mode)
    end
    self.c = {
        bg = parse(hex.background, "#FFFFFF"),
        surface = parse(hex.surface, "#EEEEEE"),
        variant = parse(hex.surface_variant, "#E4E4E4"),
        primary = parse(hex.primary, "#444444"),
        on_primary = parse(hex.on_primary, "#FFFFFF"),
        ink = parse(hex.on_background, "#000000"),
        on_surface = parse(hex.on_surface, "#000000"),
        muted = parse(hex.on_variant, "#555555"),
        outline = parse(hex.outline, "#AAAAAA"),
    }
end

function Chooser:_layout()
    local w, h = self.screen_w, self.screen_h
    self.pad = scale(16)
    self.header_h = scale(70)
    self.chips_h = scale(54)
    self.crumb_h = scale(44)
    self.info_h = scale(86)
    self.buttons_h = scale(78)
    local list_h = h - self.header_h - self.chips_h - self.crumb_h - self.info_h - self.buttons_h
    local min_row = scale(60)
    self.rows_per_page = max(3, floor(list_h / min_row))
    self.row_h = floor(list_h / self.rows_per_page)
    self.list_h = self.row_h * self.rows_per_page
    -- Whatever does not divide evenly is given to the header, so the footer
    -- always sits on the bottom edge.
    self.header_h = self.header_h + (h - (self.header_h + self.chips_h + self.crumb_h + self.list_h + self.info_h + self.buttons_h))
    self.list_y = self.header_h + self.chips_h + self.crumb_h
    self.info_y = self.list_y + self.list_h
    self.buttons_y = self.info_y + self.info_h
    self.width = w
end

---------------------------------------------------------------------------
-- Text (cached TextWidgets)
---------------------------------------------------------------------------
function Chooser:_freeText()
    for _key, widget in pairs(self._tw) do
        if widget and widget.free then pcall(widget.free, widget) end
    end
    self._tw, self._tw_count = {}, 0
end

function Chooser:_text(str, size, bold, color_name, max_w)
    str = tostring(str or "")
    local key = table.concat({ str, size, bold and 1 or 0, color_name, max_w or 0 }, "\1")
    local widget = self._tw[key]
    if not widget then
        if self._tw_count > 250 then self:_freeText() end
        widget = TextWidget:new{
            text = str, face = Font:getFace(bold and "cfont" or "smallinfofont", scale(size)),
            fgcolor = self.c[color_name], bold = bold or false, padding = 0, max_width = max_w,
        }
        self._tw[key] = widget
        self._tw_count = self._tw_count + 1
    end
    return widget, widget:getSize()
end

--- Draws text; returns its width and height.
function Chooser:_drawText(bb, str, x, y, size, bold, color_name, max_w)
    local widget, dim = self:_text(str, size, bold, color_name, max_w)
    widget:paintTo(bb, x, y)
    return dim.w, dim.h
end

--- Draws text centered in a box.
function Chooser:_drawCentered(bb, str, bx, by, bw, bh, size, bold, color_name)
    local widget, dim = self:_text(str, size, bold, color_name, bw - scale(8))
    widget:paintTo(bb, bx + floor((bw - dim.w) / 2), by + floor((bh - dim.h) / 2))
end

---------------------------------------------------------------------------
-- Directory handling
---------------------------------------------------------------------------
function Chooser:_accepts(name, full)
    if self.filter then
        local ok, result = pcall(self.filter, name, full)
        return ok and result ~= false and result ~= nil
    end
    if self.ext_set then return self.ext_set[extOf(name)] == true end
    return true
end

function Chooser:_read(path)
    local entries = {}
    local ok, iterator, dir_obj = pcall(lfs.dir, path)
    if not ok or not iterator then return nil end
    for name in iterator, dir_obj do
        if name ~= "." and name ~= ".." and (self.show_hidden or name:sub(1, 1) ~= ".") then
            local full = (path == "/" and "" or path) .. "/" .. name
            local attrs = lfs.attributes(full)
            if attrs then
                local dir = attrs.mode == "directory"
                if dir or (self.mode == "file" and attrs.mode == "file" and self:_accepts(name, full)) then
                    entries[#entries + 1] = {
                        name = name, path = full, is_dir = dir, size = attrs.size or 0,
                        modified = attrs.modification or 0, key = naturalKey(name),
                    }
                    if #entries >= ENTRY_LIMIT then break end
                end
            end
        end
    end
    table.sort(entries, function(a, b)
        if a.is_dir ~= b.is_dir then return a.is_dir end
        if a.key ~= b.key then return a.key < b.key end
        return a.name < b.name
    end)
    return entries
end

function Chooser:_load(path, preselect)
    local entries = self:_read(path)
    self._unreadable = entries == nil
    self.entries = entries or {}
    self.path = path
    self.page = 1
    self.selected = nil
    self:_freePreview()
    if preselect then
        for index, entry in ipairs(self.entries) do
            if entry.path == preselect then
                self.selected = entry.path
                self.page = floor((index - 1) / self.rows_per_page) + 1
                break
            end
        end
    end
    self.pages = max(1, math.ceil(#self.entries / self.rows_per_page))
    self:_freeText()
end

function Chooser:_childCount(entry)
    local cached = self._counts[entry.path]
    if cached then return cached end
    local count = 0
    local ok, iterator, dir_obj = pcall(lfs.dir, entry.path)
    if ok and iterator then
        for name in iterator, dir_obj do
            if name ~= "." and name ~= ".." and (self.show_hidden or name:sub(1, 1) ~= ".") then
                count = count + 1
                if count >= 999 then break end
            end
        end
    else
        count = -1
    end
    self._counts[entry.path] = count
    return count
end

function Chooser:_activePlace()
    local best
    for _i, place in ipairs(self.places) do
        if isInside(self.path, place.path) and (not best or #place.path > #best.path) then best = place end
    end
    return best
end

function Chooser:_atTop()
    if self.path == "/" then return true end
    for _i, place in ipairs(self.places) do
        if place.path == self.path and place.path ~= "/" then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------
function Chooser:_freePreview()
    if self._preview and self._preview.widget and self._preview.widget.free then
        pcall(self._preview.widget.free, self._preview.widget)
    end
    self._preview = nil
end

function Chooser:_previewFor(entry, size)
    if self._preview and self._preview.path == entry.path and self._preview.size == size then
        return self._preview.widget
    end
    self:_freePreview()
    local widget
    if ImageWidget and M.RASTER_IMAGES[extOf(entry.name)] and entry.size <= PREVIEW_MAX_BYTES then
        local ok, made = pcall(ImageWidget.new, ImageWidget, {
            file = entry.path, width = size, height = size, scale_factor = 0, file_do_cache = false,
        })
        if ok and made then widget = made end
    end
    self._preview = { path = entry.path, size = size, widget = widget or false }
    return widget
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
function Chooser:_dirty() UIManager:setDirty(self, "ui") end

function Chooser:_enter(path)
    self:_load(path)
    self:_dirty()
end

function Chooser:_up()
    if self.path == "/" then return end
    local child = self.path
    self:_load(parentPath(self.path))
    -- Land on the folder we just left, like a desktop file manager.
    for index, entry in ipairs(self.entries) do
        if entry.path == child then self.page = floor((index - 1) / self.rows_per_page) + 1; break end
    end
    self:_dirty()
end

function Chooser:_gotoPage(page)
    page = max(1, min(self.pages, page))
    if page == self.page then return false end
    self.page = page
    self:_dirty()
    return true
end

function Chooser:_toggleHidden()
    self.show_hidden = not self.show_hidden
    show_hidden_default = self.show_hidden
    self._counts = {}
    local keep = self.selected
    self:_load(self.path, keep)
    self:_dirty()
end

function Chooser:_finish(callback, ...)
    if self._finished then return end
    self._finished = true
    UIManager:close(self)
    if callback then
        local value = ...
        UIManager:nextTick(function() callback(value) end)
    end
end

function Chooser:_confirm()
    if self.mode == "folder" then
        self:_finish(self.on_select, self.path)
    elseif self.selected then
        self:_finish(self.on_select, self.selected)
    end
end

function Chooser:_cancel() self:_finish(self.on_cancel) end
function Chooser:_clear() self:_finish(self.on_clear) end

function Chooser:_tapEntry(entry)
    if entry.is_dir then self:_enter(entry.path); return end
    if self.selected == entry.path then self:_confirm(); return end
    self.selected = entry.path
    self:_dirty()
end

---------------------------------------------------------------------------
-- Painting
---------------------------------------------------------------------------
function Chooser:_hit(x, y, w, h, action)
    self._hits[#self._hits + 1] = { x = x, y = y, w = w, h = h, action = action }
end

function Chooser:_pill(bb, x, y, w, h, label, size, active, enabled, action)
    local c, mode = self.c, self.color_mode
    local fill, ink = c.surface, c.on_surface
    if active then fill, ink = c.primary, c.on_primary end
    if enabled == false then fill, ink = c.variant, c.muted end
    roundFrame(bb, x, y, w, h, floor(h / 2), max(1, scale(1)), c.outline, fill, mode)
    self:_drawCentered(bb, label, x, y, w, h, size, true, active and "on_primary" or (enabled == false and "muted" or "on_surface"))
    if action and enabled ~= false then self:_hit(x - scale(2), y - scale(4), w + scale(4), h + scale(8), action) end
end

function Chooser:_icon(bb, entry, x, y, size)
    local accent, mode = accentFor(entry), self.color_mode
    local bg = Color.make(accent[1], accent[2], accent[3], mode)
    local fg = Color.make(accent[4], accent[5], accent[6], mode)
    roundRect(bb, x, y, size, size, floor(size * .24), bg, mode)
    if entry.is_dir then
        local w, h = floor(size * .56), floor(size * .42)
        local fx, fy = x + floor((size - w) / 2), y + floor((size - h) / 2)
        local tab_w, tab_h = floor(w * .42), max(scale(3), floor(h * .22))
        roundRect(bb, fx, fy, tab_w, tab_h + scale(2), scale(2), fg, mode)
        roundRect(bb, fx, fy + tab_h, w, h - tab_h, scale(3), fg, mode)
    else
        local ext = extOf(entry.name)
        local tag = ext ~= "" and ext:upper():sub(1, 4) or "FILE"
        -- Icon text has its own accent color, so it gets a dedicated cached widget.
        local key = "icon\1" .. tag .. "\1" .. accent[4] .. "," .. accent[5] .. "," .. accent[6] .. "\1" .. size
        local tagw = self._tw[key]
        if not tagw then
            tagw = TextWidget:new{ text = tag, face = Font:getFace("cfont", scale(12)), fgcolor = fg, bold = true, padding = 0, max_width = size - scale(4) }
            self._tw[key] = tagw
            self._tw_count = self._tw_count + 1
        end
        local td = tagw:getSize()
        tagw:paintTo(bb, x + floor((size - td.w) / 2), y + floor((size - td.h) / 2))
    end
end

function Chooser:_paintHeader(bb, x, y)
    local c, mode = self.c, self.color_mode
    local pad, h = self.pad, self.header_h
    Color.paintRect(bb, x, y, self.width, h, c.bg, mode)
    local btn = scale(46)
    local by = y + floor((h - btn) / 2)
    -- Up button
    local can_up = self.path ~= "/"
    roundFrame(bb, x + pad, by, btn, btn, floor(btn / 2), max(1, scale(1)), c.outline, can_up and c.surface or c.variant, mode)
    self:_drawCentered(bb, "‹", x + pad, by - scale(2), btn, btn, 26, true, can_up and "on_surface" or "muted")
    if can_up then self:_hit(x + pad - scale(4), y, btn + scale(12), h, function() self:_up() end) end
    -- Cancel button
    roundFrame(bb, x + self.width - pad - btn, by, btn, btn, floor(btn / 2), max(1, scale(1)), c.outline, c.surface, mode)
    self:_drawCentered(bb, "×", x + self.width - pad - btn, by - scale(2), btn, btn, 26, true, "on_surface")
    self:_hit(x + self.width - pad - btn - scale(8), y, btn + scale(16), h, function() self:_cancel() end)
    -- Title + hint
    local tx = x + pad + btn + scale(14)
    local tw = self.width - 2 * pad - 2 * btn - scale(28)
    local title_text = self.title or _("Choose file")
    local _w, tdim = self:_text(title_text, 20, true, "ink", tw)
    local th = tdim.h
    local sub = self.hint
    if not sub or sub == "" then sub = self.mode == "folder" and _("Open a folder, then use it") or "" end
    local sh = 0
    if sub ~= "" then sh = select(2, self:_text(sub, 14, false, "muted", tw)).h end
    local top = y + floor((h - th - (sh > 0 and sh + scale(2) or 0)) / 2)
    self:_drawText(bb, title_text, tx, top, 20, true, "ink", tw)
    if sh > 0 then self:_drawText(bb, sub, tx, top + th + scale(2), 14, false, "muted", tw) end
end

function Chooser:_paintChips(bb, x, y)
    local c, mode = self.c, self.color_mode
    local pad = self.pad
    Color.paintRect(bb, x, y, self.width, self.chips_h, c.bg, mode)
    local active = self:_activePlace()
    local cx = x + pad
    local ch = scale(38)
    local cy = y + floor((self.chips_h - ch) / 2)
    for _i, place in ipairs(self.places) do
        local _widget, dim = self:_text(place.label, 15, true, "on_surface", nil)
        local w = dim.w + scale(28)
        if cx + w > x + self.width - pad then break end
        local is_active = active and active.path == place.path
        self:_pill(bb, cx, cy, w, ch, place.label, 15, is_active, true, function() self:_enter(place.path) end)
        cx = cx + w + scale(8)
    end
end

function Chooser:_crumbs()
    local place = self:_activePlace()
    local root_path, root_label = "/", "/"
    if place then root_path, root_label = place.path, place.label end
    local segments = { { label = root_label, path = root_path } }
    local relative = root_path == "/" and self.path:sub(2) or self.path:sub(#root_path + 2)
    local current = root_path == "/" and "" or root_path
    for part in relative:gmatch("[^/]+") do
        current = current .. "/" .. part
        segments[#segments + 1] = { label = part, path = current }
    end
    return segments
end

function Chooser:_paintCrumbs(bb, x, y)
    local c, mode = self.c, self.color_mode
    local pad = self.pad
    Color.paintRect(bb, x, y, self.width, self.crumb_h, c.bg, mode)
    -- Hidden toggle on the right.
    local hidden_label = _("Hidden")
    local _widget, hd = self:_text(hidden_label, 14, true, "on_surface", nil)
    local hw, hh = hd.w + scale(26), scale(32)
    local hx = x + self.width - pad - hw
    self:_pill(bb, hx, y + floor((self.crumb_h - hh) / 2), hw, hh, (self.show_hidden and "✓ " or "") .. hidden_label, 14, self.show_hidden, true, function() self:_toggleHidden() end)
    -- Breadcrumb, shortened from the left when it does not fit.
    local segments = self:_crumbs()
    local avail = hx - scale(10) - (x + pad)
    local sep_w = select(2, self:_text(" › ", 16, false, "muted", nil)).w
    local shown, used = {}, 0
    for index = #segments, 1, -1 do
        local seg = segments[index]
        local dim = select(2, self:_text(seg.label, 16, index == #segments, "ink", nil))
        local need = dim.w + (#shown > 0 and sep_w or 0)
        if #shown > 0 and used + need > avail - (index > 1 and (sep_w + scale(24)) or 0) then
            shown.cut = index
            break
        end
        table.insert(shown, 1, seg)
        used = used + need
    end
    local cx = x + pad
    local line_y = y + floor((self.crumb_h - select(2, self:_text("Ag", 16, true, "ink", nil)).h) / 2)
    if shown.cut then
        local w = self:_drawText(bb, "…", cx, line_y, 16, true, "muted", nil)
        local target = segments[shown.cut].path
        self:_hit(cx - scale(6), y, w + sep_w, self.crumb_h, function() self:_enter(target) end)
        cx = cx + w
        cx = cx + self:_drawText(bb, " › ", cx, line_y, 16, false, "muted", nil)
    end
    for index, seg in ipairs(shown) do
        local last = seg.path == self.path
        local maxw = max(scale(40), avail - (cx - (x + pad)))
        local w = self:_drawText(bb, seg.label, cx, line_y, 16, last, last and "ink" or "muted", maxw)
        if not last then
            local target = seg.path
            self:_hit(cx - scale(6), y, w + scale(12), self.crumb_h, function() self:_enter(target) end)
        end
        cx = cx + w
        if index < #shown then cx = cx + self:_drawText(bb, " › ", cx, line_y, 16, false, "muted", nil) end
    end
    -- Hairline under the crumbs.
    Color.paintRect(bb, x + pad, y + self.crumb_h - 1, self.width - 2 * pad, max(1, scale(1)), c.outline, mode)
end

function Chooser:_paintList(bb, x, y)
    local c, mode = self.c, self.color_mode
    local pad = self.pad
    Color.paintRect(bb, x, y, self.width, self.list_h, c.bg, mode)
    if #self.entries == 0 then
        local message, detail
        if self._unreadable then
            message, detail = _("This folder cannot be opened"), _("Go back and pick another place.")
        elseif self.mode == "folder" then
            message, detail = _("No subfolders here"), _("You can still use this folder.")
        else
            message, detail = _("Nothing to choose here"), self.hint ~= "" and self.hint or _("Open another folder.")
        end
        self:_drawCentered(bb, message, x, y + floor(self.list_h / 2) - scale(30), self.width, scale(30), 20, true, "ink")
        if detail then self:_drawCentered(bb, detail, x + pad, y + floor(self.list_h / 2), self.width - 2 * pad, scale(30), 15, false, "muted") end
        return
    end
    local first = (self.page - 1) * self.rows_per_page + 1
    local last = min(#self.entries, first + self.rows_per_page - 1)
    local icon = self.row_h - 2 * scale(11)
    for index = first, last do
        local entry = self.entries[index]
        local ry = y + (index - first) * self.row_h
        local selected = (not entry.is_dir) and self.selected == entry.path
        if selected then
            roundRect(bb, x + scale(8), ry + scale(3), self.width - scale(16), self.row_h - scale(6), scale(14), c.primary, mode)
        end
        local name_ink = selected and "on_primary" or "ink"
        local sub_ink = selected and "on_primary" or "muted"
        self:_icon(bb, entry, x + pad, ry + floor((self.row_h - icon) / 2), icon)
        local tx = x + pad + icon + scale(14)
        local right_pad = scale(44)
        local tw = self.width - (tx - x) - right_pad - pad
        local subtitle
        if entry.is_dir then
            local count = self:_childCount(entry)
            subtitle = count < 0 and _("Cannot be opened")
                or joinNonEmpty("  ·  ", count == 1 and _("1 item") or string.format(_("%d items"), count), formatDate(entry.modified))
        else
            subtitle = joinNonEmpty("  ·  ", humanSize(entry.size), formatDate(entry.modified))
        end
        local nh = select(2, self:_text(entry.name, 19, entry.is_dir, name_ink, tw)).h
        local sh = select(2, self:_text(subtitle, 14, false, sub_ink, tw)).h
        local top = ry + floor((self.row_h - nh - sh - scale(2)) / 2)
        self:_drawText(bb, entry.name, tx, top, 19, entry.is_dir, name_ink, tw)
        self:_drawText(bb, subtitle, tx, top + nh + scale(2), 14, false, sub_ink, tw)
        -- Trailing marker: chevron for folders, check for the selection.
        local mark = entry.is_dir and "›" or (selected and "✓" or nil)
        if mark then
            self:_drawCentered(bb, mark, x + self.width - pad - scale(36), ry, scale(36), self.row_h, entry.is_dir and 26 or 22, true, selected and "on_primary" or "muted")
        end
        if not selected and index < last then
            Color.paintRect(bb, x + pad + icon + scale(14), ry + self.row_h - 1, self.width - 2 * pad - icon - scale(14), max(1, scale(1)), c.variant, mode)
        end
        self:_hit(x, ry, self.width, self.row_h, function() self:_tapEntry(entry) end)
    end
end

function Chooser:_paintInfo(bb, x, y)
    local c, mode = self.c, self.color_mode
    local pad = self.pad
    Color.paintRect(bb, x, y, self.width, self.info_h, c.bg, mode)
    local card_h = self.info_h - scale(12)
    local cx, cy, cw = x + pad, y + scale(4), self.width - 2 * pad
    roundFrame(bb, cx, cy, cw, card_h, scale(16), max(1, scale(1)), c.outline, c.surface, mode)
    local thumb = card_h - scale(16)
    local tx0 = cx + scale(8)
    local ty0 = cy + scale(8)
    local title, subtitle, entry

    if self.mode == "folder" then
        entry = { name = baseName(self.path), path = self.path, is_dir = true }
        title = _("Use this folder") .. ":  " .. (self.path == "/" and "/" or baseName(self.path))
        subtitle = self.path
    elseif self.selected then
        for _i, e in ipairs(self.entries) do if e.path == self.selected then entry = e; break end end
    end
    if self.mode == "file" then
        if entry then
            title = entry.name
            subtitle = joinNonEmpty("  ·  ", humanSize(entry.size), self.path)
        else
            title = _("Tap a file to select it")
            subtitle = self.hint or ""
        end
    end

    local text_x = tx0
    if entry then
        local preview = (not entry.is_dir) and self:_previewFor(entry, thumb) or nil
        if preview then
            local ok = pcall(function()
                local size = preview:getSize()
                preview:paintTo(bb, tx0 + floor((thumb - size.w) / 2), ty0 + floor((thumb - size.h) / 2))
            end)
            if not ok then self:_icon(bb, entry, tx0, ty0, thumb) end
        else
            self:_icon(bb, entry, tx0, ty0, thumb)
        end
        text_x = tx0 + thumb + scale(12)
    else
        text_x = tx0 + scale(6)
    end
    local tw = cx + cw - text_x - scale(12)
    local nh = select(2, self:_text(title, 17, true, "ink", tw)).h
    local sh = 0
    if subtitle and subtitle ~= "" then sh = select(2, self:_text(subtitle, 13, false, "muted", tw)).h end
    local top = cy + floor((card_h - nh - (sh > 0 and sh + scale(2) or 0)) / 2)
    self:_drawText(bb, title, text_x, top, 17, true, "ink", tw)
    if sh > 0 then self:_drawText(bb, subtitle, text_x, top + nh + scale(2), 13, false, "muted", tw) end
end

function Chooser:_paintButtons(bb, x, y)
    local c, mode = self.c, self.color_mode
    local pad = self.pad
    Color.paintRect(bb, x, y, self.width, self.buttons_h, c.bg, mode)
    local bh = scale(54)
    local by = y + floor((self.buttons_h - bh) / 2)
    local cx = x + pad
    -- Pager
    local pw = scale(52)
    self:_pill(bb, cx, by, pw, bh, "‹", 24, false, self.page > 1, function() self:_gotoPage(self.page - 1) end)
    cx = cx + pw + scale(6)
    local label = string.format("%d / %d", self.page, self.pages)
    local lw = max(scale(62), select(2, self:_text(label, 16, true, "ink", nil)).w + scale(12))
    self:_drawCentered(bb, label, cx, by, lw, bh, 16, true, "ink")
    cx = cx + lw + scale(6)
    self:_pill(bb, cx, by, pw, bh, "›", 24, false, self.page < self.pages, function() self:_gotoPage(self.page + 1) end)
    cx = cx + pw + scale(12)
    -- Clear + select share the rest of the row.
    local right = x + self.width - pad
    if self.allow_clear then
        local text = self.clear_text or _("Clear")
        local cw = max(scale(96), select(2, self:_text(text, 16, true, "on_surface", nil)).w + scale(30))
        cw = min(cw, floor((right - cx) * .42))
        self:_pill(bb, cx, by, cw, bh, text, 16, false, true, function() self:_clear() end)
        cx = cx + cw + scale(8)
    end
    local can_select = self.mode == "folder" or self.selected ~= nil
    local text = self.mode == "folder" and _("Use folder") or _("Select")
    self:_pill(bb, cx, by, max(scale(80), right - cx), bh, text, 18, can_select, can_select, function() self:_confirm() end)
end

function Chooser:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    self._hits = {}
    Color.paintRect(bb, x, y, self.screen_w, self.screen_h, self.c.bg, self.color_mode)
    self:_paintHeader(bb, x, y)
    self:_paintChips(bb, x, y + self.header_h)
    self:_paintCrumbs(bb, x, y + self.header_h + self.chips_h)
    self:_paintList(bb, x, y + self.list_y)
    self:_paintInfo(bb, x, y + self.info_y)
    self:_paintButtons(bb, x, y + self.buttons_y)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
function Chooser:onTapAppDockChooser(_args, ges)
    local pos = ges and ges.pos
    if not pos then return true end
    for index = #self._hits, 1, -1 do
        local hit = self._hits[index]
        if pos.x >= hit.x and pos.x < hit.x + hit.w and pos.y >= hit.y and pos.y < hit.y + hit.h then
            hit.action()
            return true
        end
    end
    return true
end

function Chooser:onSwipeAppDockChooser(_args, ges)
    local dir = ges and ges.direction
    if dir == "north" then self:_gotoPage(self.page + 1)
    elseif dir == "south" then self:_gotoPage(self.page - 1)
    elseif dir == "east" then self:_up() end
    return true
end

function Chooser:onBackAppDockChooser()
    if self:_atTop() then self:_cancel() else self:_up() end
    return true
end
function Chooser:onNextAppDockChooser() self:_gotoPage(self.page + 1); return true end
function Chooser:onPrevAppDockChooser() self:_gotoPage(self.page - 1); return true end
function Chooser:onKeyRepeat() return true end

function Chooser:onCloseWidget()
    self:_freePreview()
    self:_freeText()
    UIManager:setDirty(nil, "ui")
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

--- Opens the chooser. See the header comment for the options.
function M.pick(options)
    options = options or {}
    local widget = Chooser:new{
        title = options.title, mode = options.mode, path = options.path,
        extensions = options.extensions, filter = options.filter, hint = options.hint,
        allow_clear = options.allow_clear == true and type(options.on_clear) == "function",
        clear_text = options.clear_text,
        on_select = options.on_select, on_clear = options.on_clear, on_cancel = options.on_cancel,
    }
    UIManager:show(widget)
    return widget
end

M.Chooser = Chooser
return M
