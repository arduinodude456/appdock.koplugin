--[[--
AppDock "Funktionen" / "Features" (Settings category).

Three optional features, all off by default:

  * Shelf   - a first homescreen page that looks like a bookcase with two
              rows of covers: "Recently read" and "Featured".
  * Focus   - hides games and YouTube everywhere AppDock lists apps and keeps
              notification toasts from interrupting reading.
  * Pet     - settings for the reading pet (see appdock_pet.lua).

Settings live in settings.features = { shelf = {enabled}, focus = {enabled},
pet = {...} }. Covers come from KOReader's reading history and, when the
CoverBrowser plugin is active, from its cover cache; otherwise a drawn
placeholder cover with the file name is shown.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local Color = require("appdock_color")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")

local Screen = Device.screen
local function scale(n) return Screen:scaleBySize(n) end

local pet_ok, Pet = pcall(require, "appdock_pet")
if not pet_ok then Pet = nil end

local Features = {}

---------------------------------------------------------------------------
-- Text (German / English)
---------------------------------------------------------------------------

local STRINGS = {
    en = {
        cat_title = "Features", cat_sub = "Shelf, focus mode, pet",
        sec_home = "Homescreen", sec_focus = "Focus", sec_pet = "Pet",
        shelf_title = "Enable shelf",
        shelf_on = "First homescreen page shows a bookcase · swipe right",
        shelf_off = "Off · no shelf page",
        focus_title = "Focus mode",
        focus_on = "Games and YouTube hidden · no notification pop-ups",
        focus_off = "Off · everything visible",
        pet_title = "Reading pet",
        pet_on = "%s the %s · level %d",
        pet_off = "Off · a companion that follows your reading",
        pet_species_title = "Animal", pet_species_sub = "Currently: %s",
        pet_place_title = "Show pet", pet_name_title = "Name",
        pet_name_sub = "%s · tap to rename",
        pet_status_title = "How is my pet?", pet_status_sub = "Mood, level, reading streak",
        place_home = "On the homescreen",
        place_dreader = "Homescreen + book in DReader",
        place_everywhere = "Everywhere",
        pick_species = "Choose an animal", pick_place = "Where should the pet appear?",
        name_dialog = "Name your pet", save = "Save", cancel = "Cancel",
        shelf_recent = "Recently read", shelf_featured = "Featured",
        shelf_empty = "No books yet. Open a book and it appears here.",
    },
    de = {
        cat_title = "Funktionen", cat_sub = "Regal, Fokus-Modus, Haustier",
        sec_home = "Homescreen", sec_focus = "Fokus", sec_pet = "Haustier",
        shelf_title = "Regal aktivieren",
        shelf_on = "1. Homescreen-Seite zeigt ein Bücherregal · nach rechts wischen",
        shelf_off = "Aus · keine Regal-Seite",
        focus_title = "Fokus-Modus",
        focus_on = "Spiele und YouTube ausgeblendet · keine Benachrichtigungs-Pop-ups",
        focus_off = "Aus · alles sichtbar",
        pet_title = "Lese-Haustier",
        pet_on = "%s (%s) · Level %d",
        pet_off = "Aus · ein Begleiter, der deine Lesezeit verfolgt",
        pet_species_title = "Tierart", pet_species_sub = "Aktuell: %s",
        pet_place_title = "Anzeigeort", pet_name_title = "Name",
        pet_name_sub = "%s · zum Umbenennen tippen",
        pet_status_title = "Wie geht es meinem Tier?", pet_status_sub = "Stimmung, Level, Lese-Serie",
        place_home = "Auf dem Homescreen",
        place_dreader = "Homescreen + Buch in DReader",
        place_everywhere = "Überall",
        pick_species = "Tierart wählen", pick_place = "Wo soll das Tier erscheinen?",
        name_dialog = "Gib deinem Tier einen Namen", save = "Speichern", cancel = "Abbrechen",
        shelf_recent = "Zuletzt gelesen", shelf_featured = "Empfohlen",
        shelf_empty = "Noch keine Bücher. Öffne ein Buch, dann erscheint es hier.",
    },
}

function Features.t(appdock, key, ...)
    local settings = appdock and appdock.settings or {}
    local tbl = STRINGS[settings.language == "de" and "de" or "en"]
    local text = tbl[key]
    if text == nil then text = STRINGS.en[key] end
    if text == nil then return key end
    if select("#", ...) > 0 then return string.format(text, ...) end
    return text
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

local function save(appdock)
    if appdock and type(appdock._saveSettings) == "function" then pcall(appdock._saveSettings, appdock) end
end

function Features.config(appdock)
    local settings = appdock.settings
    settings.features = type(settings.features) == "table" and settings.features or {}
    local features = settings.features
    features.shelf = type(features.shelf) == "table" and features.shelf or {}
    features.shelf.enabled = features.shelf.enabled == true
    features.focus = type(features.focus) == "table" and features.focus or {}
    features.focus.enabled = features.focus.enabled == true
    return features
end

function Features.isShelfEnabled(appdock)
    return appdock ~= nil and appdock.settings ~= nil
        and Features.config(appdock).shelf.enabled == true
        and not (appdock.isSimpleModeEnabled and appdock:isSimpleModeEnabled("homescreen"))
end

function Features.isFocusEnabled(appdock)
    return appdock ~= nil and appdock.settings ~= nil and Features.config(appdock).focus.enabled == true
end

--- Apps that focus mode hides: YouTube (all three DApps) and games.
local BLOCKED_IDS = {
    youtube = true, youtube_shorts = true, youtube_music = true, doom = true,
}

function Features.isFocusBlocked(appdock, app)
    if not Features.isFocusEnabled(appdock) or type(app) ~= "table" then return false end
    if app.kind == "game" then return true end
    local id = type(app.id) == "string" and app.id:match("^dapp:(.+)$") or nil
    if id then
        if BLOCKED_IDS[id] then return true end
        local installed = appdock.settings.store and appdock.settings.store.installed or {}
        local record = installed[id]
        if type(record) == "table" then
            if record.is_game == true then return true end
            local source = type(record.source_path) == "string" and record.source_path:lower() or ""
            if source:match("^games/") or source:find("/games/", 1, true) then return true end
        end
    end
    local title = type(app.title) == "string" and app.title:lower() or ""
    return title:find("youtube", 1, true) ~= nil
end

function Features.setShelfEnabled(appdock, enabled)
    Features.config(appdock).shelf.enabled = enabled == true
    local home = appdock._home_screen
    if home then home.shelf_view = false end
    save(appdock)
end

--- Turning focus mode on also closes open games/YouTube instances.
function Features.setFocusEnabled(appdock, enabled)
    Features.config(appdock).focus.enabled = enabled == true
    if enabled and appdock.dapp_manager and appdock.dapp_manager.getOpenApps then
        local manager = appdock.dapp_manager
        for _, open_app in ipairs(manager:getOpenApps()) do
            local definition = manager.definitions[open_app.id] or (manager.plugin_definitions and manager.plugin_definitions[open_app.id])
            local app = { id = "dapp:" .. open_app.id, title = definition and definition.title or open_app.title or open_app.id }
            if Features.isFocusBlocked(appdock, app) then pcall(manager.closeDApp, manager, open_app.id) end
        end
    end
    save(appdock)
end

---------------------------------------------------------------------------
-- Dialogs and settings rows
---------------------------------------------------------------------------

local function choiceDialog(appdock, title, options, on_pick)
    local ok, Dialogs = pcall(require, "appdock_dialogs")
    local ButtonDialog = ok and Dialogs.ButtonDialog or require("ui/widget/buttondialog")
    local dialog
    local rows = {}
    for _, option in ipairs(options) do
        rows[#rows + 1] = { { text = option.text, callback = function()
            UIManager:close(dialog)
            on_pick(option.id)
        end } }
    end
    dialog = ButtonDialog:new{ title = title, buttons = rows }
    UIManager:show(dialog)
end

local function nameDialog(appdock, on_done)
    local ok, Dialogs = pcall(require, "appdock_dialogs")
    local InputDialog = ok and Dialogs.InputDialog or require("ui/widget/inputdialog")
    local dialog
    dialog = InputDialog:new{
        title = Features.t(appdock, "name_dialog"),
        input = Pet and Pet.config(appdock).name or "",
        buttons = { {
            { text = Features.t(appdock, "cancel"), callback = function() UIManager:close(dialog) end },
            { text = Features.t(appdock, "save"), is_enter_default = true, callback = function()
                local value = dialog:getInputText()
                UIManager:close(dialog)
                on_done(value)
            end },
        } },
    }
    UIManager:show(dialog)
    if dialog.onShowKeyboard then dialog:onShowKeyboard() end
end

function Features.settingsRows(appdock, context)
    local t = function(key, ...) return Features.t(appdock, key, ...) end
    local function rebuild() if context and context.requestRebuild then context.requestRebuild("ui") end end
    local cfg = Features.config(appdock)
    local rows = {
        { section = t("sec_home"), title = t("shelf_title"), icon = "reading",
            subtitle = cfg.shelf.enabled and t("shelf_on") or t("shelf_off"),
            enabled = cfg.shelf.enabled,
            callback = function()
                Features.setShelfEnabled(appdock, not cfg.shelf.enabled)
                rebuild()
            end },
        { section = t("sec_focus"), title = t("focus_title"), icon = "timer",
            subtitle = cfg.focus.enabled and t("focus_on") or t("focus_off"),
            enabled = cfg.focus.enabled,
            callback = function()
                Features.setFocusEnabled(appdock, not cfg.focus.enabled)
                rebuild()
            end },
    }
    if not Pet then return rows end

    local pet = Pet.config(appdock)
    local status = pet.enabled and Pet.status(appdock) or nil
    rows[#rows + 1] = { section = t("sec_pet"), title = t("pet_title"), icon = "bookmark",
        subtitle = pet.enabled and t("pet_on", Pet.displayName(appdock), Pet.t(appdock, pet.species), status.level) or t("pet_off"),
        enabled = pet.enabled,
        callback = function()
            Pet.setEnabled(appdock, not pet.enabled)
            rebuild()
        end }
    if pet.enabled then
        rows[#rows + 1] = { section = t("sec_pet"), title = t("pet_species_title"), icon = "bookmark",
            subtitle = t("pet_species_sub", Pet.t(appdock, pet.species)), show_state = false,
            callback = function()
                local options = {}
                for _, id in ipairs(Pet.SPECIES) do options[#options + 1] = { id = id, text = Pet.t(appdock, id) } end
                choiceDialog(appdock, t("pick_species"), options, function(id) Pet.setSpecies(appdock, id); rebuild() end)
            end }
        rows[#rows + 1] = { section = t("sec_pet"), title = t("pet_place_title"), icon = "bookmark",
            subtitle = t("place_" .. pet.place), show_state = false,
            callback = function()
                local options = {}
                for _, id in ipairs(Pet.PLACES) do options[#options + 1] = { id = id, text = t("place_" .. id) } end
                choiceDialog(appdock, t("pick_place"), options, function(id) Pet.setPlace(appdock, id); rebuild() end)
            end }
        rows[#rows + 1] = { section = t("sec_pet"), title = t("pet_name_title"), icon = "bookmark",
            subtitle = t("pet_name_sub", Pet.displayName(appdock)), show_state = false,
            callback = function()
                nameDialog(appdock, function(value) Pet.setName(appdock, value); rebuild() end)
            end }
        rows[#rows + 1] = { section = t("sec_pet"), title = t("pet_status_title"), icon = "bookmark",
            subtitle = t("pet_status_sub"), show_state = false,
            callback = function() Pet.showStatus(appdock) end }
    end
    return rows
end

---------------------------------------------------------------------------
-- Shelf data: covers from reading history / CoverBrowser cache
---------------------------------------------------------------------------

local lfs_ok, lfs = pcall(require, "libs/libkoreader-lfs")
if not lfs_ok then lfs_ok, lfs = pcall(require, "lfs") end

local BOOK_EXT = { epub = true, pdf = true, mobi = true, azw3 = true, fb2 = true, cbz = true, djvu = true, txt = true, html = true, htm = true }

local function fileExists(path)
    return lfs_ok and lfs and type(path) == "string" and lfs.attributes(path, "mode") == "file"
end

local function bookTitle(path)
    return (path:match("([^/]+)%.[^./]+$") or path):gsub("[_%.]+", " ")
end

local function percentFinished(path)
    local ok, value = pcall(function()
        local DocSettings = require("docsettings")
        if DocSettings.hasSidecarFile and not DocSettings:hasSidecarFile(path) then return nil end
        local doc = DocSettings:open(path)
        local percent = doc:readSetting("percent_finished")
        if doc.close then doc:close() end
        return percent
    end)
    return ok and tonumber(value) or nil
end

--- Books downloaded with DLib (newest first): { file, title, cover }.
-- DLib keeps them in the settings key "appdock_dlib_v1" (recents).
local function dlibBooks()
    local books = {}
    local ok = pcall(function()
        local raw = G_reader_settings and G_reader_settings:readSetting("appdock_dlib_v1")
        if type(raw) ~= "table" or type(raw.recents) ~= "table" then return end
        for _, r in ipairs(raw.recents) do
            if type(r) == "table" and fileExists(r.path) then
                local title = type(r.title) == "string" and r.title ~= "" and r.title or bookTitle(r.path)
                books[#books + 1] = {
                    file = r.path, title = title,
                    cover = (type(r.cover) == "string" and fileExists(r.cover)) and r.cover or nil,
                }
            end
        end
    end)
    if not ok then return {} end
    return books
end

--- { recent = { {file,title,progress}, ... }, featured = { ... } }
function Features.shelfData(slots)
    local recent, featured, seen = {}, {}, {}
    local history = {}
    local ok, ReadHistory = pcall(require, "readhistory")
    if ok and ReadHistory and type(ReadHistory.hist) == "table" then
        for _, item in ipairs(ReadHistory.hist) do
            if type(item) == "table" and fileExists(item.file) and not seen[item.file] then
                seen[item.file] = true
                history[#history + 1] = { file = item.file, title = bookTitle(item.file) }
            end
        end
    end
    for index = 1, math.min(slots, #history) do
        local book = history[index]
        book.progress = percentFinished(book.file)
        recent[#recent + 1] = book
    end
    -- Books downloaded with DLib come first on the second shelf (unless they
    -- already stand on the first one); the rest of the history follows.
    local on_shelf = {}
    for _, book in ipairs(recent) do on_shelf[book.file] = true end
    for _, book in ipairs(dlibBooks()) do
        if #featured >= slots then break end
        if not on_shelf[book.file] then
            on_shelf[book.file] = true
            seen[book.file] = true
            book.progress = percentFinished(book.file)
            featured[#featured + 1] = book
        end
    end
    -- Featured: unfinished books first (most advanced first), then the rest of
    -- the history, then books next to the latest one.
    local pool = {}
    for index = slots + 1, #history do
        local book = history[index]
        if on_shelf[book.file] then book = nil end
        if book then
        book.progress = percentFinished(book.file)
        pool[#pool + 1] = book
        end
    end
    local function unfinished(book) return book.progress and book.progress > 0 and book.progress < 0.98 end
    table.sort(pool, function(a, b)
        local ua, ub = unfinished(a) and 1 or 0, unfinished(b) and 1 or 0
        if ua ~= ub then return ua > ub end
        return (a.progress or 0) > (b.progress or 0)
    end)
    for _, book in ipairs(pool) do
        if #featured < slots then featured[#featured + 1] = book end
    end
    if #featured < slots and history[1] and lfs_ok and lfs then
        local dir = history[1].file:match("^(.*)/[^/]+$")
        local names = {}
        if dir and lfs.attributes(dir, "mode") == "directory" then
            for name in lfs.dir(dir) do
                local ext = name:lower():match("%.([a-z0-9]+)$")
                if ext and BOOK_EXT[ext] then names[#names + 1] = name end
            end
        end
        table.sort(names)
        for _, name in ipairs(names) do
            local path = dir .. "/" .. name
            if #featured >= slots then break end
            if not seen[path] then
                seen[path] = true
                featured[#featured + 1] = { file = path, title = bookTitle(path) }
            end
        end
    end
    if #featured < slots and lfs_ok and lfs then
        local home_dir = G_reader_settings and G_reader_settings.readSetting and G_reader_settings:readSetting("home_dir")
        local function scan(dir, depth)
            if #featured >= slots or depth > 2 or lfs.attributes(dir, "mode") ~= "directory" then return end
            local subdirs = {}
            for name in lfs.dir(dir) do
                if name:sub(1, 1) ~= "." then
                    local path = dir .. "/" .. name
                    local mode = lfs.attributes(path, "mode")
                    local ext = name:lower():match("%.([a-z0-9]+)$")
                    if mode == "file" and ext and BOOK_EXT[ext] and not seen[path] and #featured < slots then
                        seen[path] = true
                        featured[#featured + 1] = { file = path, title = bookTitle(path) }
                    elseif mode == "directory" then subdirs[#subdirs + 1] = path end
                end
            end
            table.sort(subdirs)
            for _, sub in ipairs(subdirs) do scan(sub, depth + 1) end
        end
        if type(home_dir) == "string" then pcall(scan, home_dir, 0) end
    end
    return { recent = recent, featured = featured }
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local COLORED = false
-- Color on color screens (colorFromString), luminance gray otherwise.
local function rgb(r, g, b)
    return Color.make(r, g, b, COLORED)
end
local function fill(bb, x, y, w, h, color)
    Color.paintRect(bb, x, y, w, h, color, COLORED)
end
local function frame(bb, x, y, w, h, t, color)
    Color.paintBorder(bb, x, y, w, h, t, color, COLORED)
end

Features._covers = {}
Features._cover_order = {}

local function freeCover(key)
    local bb = Features._covers[key]
    if bb and bb ~= false and bb.free then pcall(bb.free, bb) end
    Features._covers[key] = nil
end

--- A cover scaled to fit `w` x `h`, or nil (cached; at most 16 kept).
local function scaledCover(file, w, h)
    local key = file .. "|" .. w .. "x" .. h
    local cached = Features._covers[key]
    if cached ~= nil then return cached or nil end
    local result = false
    pcall(function()
        local BookInfoManager = require("bookinfomanager")
        local info = BookInfoManager:getBookInfo(file, true)
        if info and info.has_cover and info.cover_bb and info.cover_w and info.cover_h then
            local factor = math.min(w / info.cover_w, h / info.cover_h)
            local sw, sh = math.max(1, math.floor(info.cover_w * factor)), math.max(1, math.floor(info.cover_h * factor))
            local RenderImage = require("ui/renderimage")
            result = RenderImage:scaleBlitBuffer(info.cover_bb, sw, sh) or false
        end
    end)
    Features._covers[key] = result
    Features._cover_order[#Features._cover_order + 1] = key
    while #Features._cover_order > 16 do freeCover(table.remove(Features._cover_order, 1)) end
    return result or nil
end

--- A cover from a plain image file (DLib's downloaded cover), scaled to fit.
local function scaledImageFile(path, w, h)
    local key = "img|" .. path .. "|" .. w .. "x" .. h
    local cached = Features._covers[key]
    if cached ~= nil then return cached or nil end
    local result = false
    pcall(function()
        local RenderImage = require("ui/renderimage")
        local bb = RenderImage:renderImageFile(path, false)
        if bb then
            local factor = math.min(w / bb:getWidth(), h / bb:getHeight())
            local sw, sh = math.max(1, math.floor(bb:getWidth() * factor)), math.max(1, math.floor(bb:getHeight() * factor))
            result = RenderImage:scaleBlitBuffer(bb, sw, sh, true) or false
        end
    end)
    Features._covers[key] = result
    Features._cover_order[#Features._cover_order + 1] = key
    while #Features._cover_order > 16 do freeCover(table.remove(Features._cover_order, 1)) end
    return result or nil
end

local function hashShade(text)
    local sum = 0
    for index = 1, #text do sum = (sum * 31 + text:byte(index)) % 9973 end
    return sum
end

local ShelfView = InputContainer:extend{
    appdock = nil, home = nil, width = 0, height = 0,
}

function ShelfView:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self.ges_events = { TapShelf = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    self.slots = {}
    local margin = scale(22)
    self.book_w = math.max(scale(64), math.min(scale(96), math.floor((self.width - 2 * margin - 3 * scale(12)) / 4)))
    self.book_h = math.floor(self.book_w * 1.45)
    self.columns = 6
    self.data = Features.shelfData(self.columns)
    self.margin = margin
end

local function drawBook(bb, x, y, w, h, book, title_cache, appdock)
    local cover = scaledCover(book.file, w, h) or (book.cover and scaledImageFile(book.cover, w, h))
    local draw_w, draw_h = w, h
    if cover then
        draw_w, draw_h = cover:getWidth(), cover:getHeight()
        local ox = x + math.floor((w - draw_w) / 2)
        bb:blitFrom(cover, ox, y + h - draw_h, 0, 0, draw_w, draw_h)
        frame(bb, ox, y + h - draw_h, draw_w, draw_h, 1, rgb(0, 0, 0))
        x = ox
    else
        local shade = hashShade(book.title)
        local base = rgb(110 + shade % 90, 90 + math.floor(shade / 7) % 90, 80 + math.floor(shade / 13) % 90)
        fill(bb, x, y, w, h, base)
        frame(bb, x, y, w, h, 1, rgb(0, 0, 0))
        fill(bb, x, y, scale(5), h, rgb(60, 50, 45))
        local widget = title_cache[book.file]
        if not widget then
            local ok, TextBoxWidget = pcall(require, "ui/widget/textboxwidget")
            if ok then
                local made, instance = pcall(TextBoxWidget.new, TextBoxWidget, {
                    text = book.title, face = Font:getFace("cfont", scale(10)),
                    width = w - scale(14), height = h - scale(16), height_adjust = true,
                    height_overflow_show_ellipsis = true, alignment = "center",
                    fgcolor = Blitbuffer.COLOR_WHITE,
                })
                if made then widget = instance; title_cache[book.file] = widget end
            end
        end
        if widget then
            local size = widget:getSize()
            pcall(widget.paintTo, widget, bb, x + scale(9), y + math.max(scale(6), math.floor((h - size.h) / 2)))
        end
        draw_w = w
    end
    if book.progress and book.progress > 0 then
        local bar_y = y + h + scale(3)
        fill(bb, x, bar_y, draw_w, scale(3), rgb(204, 204, 204))
        fill(bb, x, bar_y, math.floor(draw_w * math.min(1, book.progress)), scale(3), rgb(0, 0, 0))
    end
end

function ShelfView:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local range = self.ges_events.TapShelf[1].range
    range.x, range.y, range.w, range.h = x, y, self.width, self.height
    self.slots = {}
    self._title_cache = self._title_cache or {}
    COLORED = Color.isColor()

    local width, height, margin = self.width, self.height, self.margin
    local wood_dark, wood, wood_light = rgb(92, 62, 38), rgb(139, 98, 62), rgb(176, 132, 88)
    local back = rgb(70, 48, 30)
    -- Case: back panel and side walls.
    fill(bb, x, y, width, height, rgb(232, 224, 210))
    local case_x, case_w = x + margin - scale(10), width - 2 * margin + scale(20)
    local case_y, case_h = y + scale(34), height - scale(34) - scale(60)
    fill(bb, case_x, case_y, case_w, case_h, back)
    fill(bb, case_x, case_y, scale(10), case_h, wood)
    fill(bb, case_x + case_w - scale(10), case_y, scale(10), case_h, wood)
    fill(bb, case_x, case_y, case_w, scale(10), wood_light)

    local rows = {
        { label = Features.t(self.appdock, "shelf_recent"), books = self.data.recent },
        { label = Features.t(self.appdock, "shelf_featured"), books = self.data.featured },
    }
    local row_h = math.floor((case_h - scale(10)) / 2)
    local label_face = Font:getFace("cfont", scale(12))
    local text_ok, RenderText = pcall(require, "ui/rendertext")
    local any = false
    for row_index, row in ipairs(rows) do
        local row_top = case_y + scale(10) + (row_index - 1) * row_h
        local plank_y = row_top + row_h - scale(12)
        fill(bb, case_x, plank_y, case_w, scale(12), wood)
        fill(bb, case_x, plank_y, case_w, scale(3), wood_light)
        fill(bb, case_x, plank_y + scale(12), case_w, scale(2), wood_dark)
        if text_ok then
            pcall(RenderText.renderUtf8Text, RenderText, bb, case_x + scale(18), row_top + scale(16), label_face, row.label, true, false, rgb(240, 225, 200))
        end
        local avail_h = row_h - scale(12) - scale(30) - scale(6)
        local book_h = math.min(self.book_h, avail_h)
        local book_w = math.floor(book_h / 1.45)
        local gap = scale(10)
        local left, right = case_x + scale(22), case_x + case_w - scale(22)
        local book_y = plank_y - scale(5) - book_h
        local cursor = left
        for index, book in ipairs(row.books) do
            if cursor + book_w > right then break end
            drawBook(bb, cursor, book_y, book_w, book_h, book, self._title_cache, self.appdock)
            self.slots[#self.slots + 1] = { x = cursor, y = book_y, w = book_w, h = book_h, file = book.file }
            any = true
            cursor = cursor + book_w + gap
        end
        -- Decorative spines fill the rest of the plank so it looks stocked.
        local seed = row_index * 7
        local spine_colors = {
            { 120, 60, 55 }, { 55, 85, 110 }, { 90, 110, 65 }, { 150, 115, 60 },
            { 85, 60, 105 }, { 60, 95, 95 }, { 140, 85, 70 },
        }
        while cursor + scale(14) <= right do
            seed = seed + 1
            local sw = scale(12) + (seed * 5) % scale(10)
            local sh = math.floor(book_h * (0.62 + ((seed * 13) % 30) / 100))
            if cursor + sw > right then break end
            local c = spine_colors[seed % #spine_colors + 1]
            fill(bb, cursor, plank_y - scale(5) - sh, sw, sh, rgb(c[1], c[2], c[3]))
            frame(bb, cursor, plank_y - scale(5) - sh, sw, sh, 1, rgb(40, 28, 20))
            fill(bb, cursor + 2, plank_y - scale(5) - sh + scale(8), sw - 4, scale(2), rgb(225, 205, 150))
            cursor = cursor + sw + scale(2)
        end
    end
    -- Floor strip under the case, with the pet standing next to it.
    fill(bb, x, case_y + case_h, width, scale(8), wood_dark)
    if not any and text_ok then
        local face = Font:getFace("smallinfofont", scale(12))
        local message = Features.t(self.appdock, "shelf_empty")
        pcall(RenderText.renderUtf8Text, RenderText, bb, x + margin, case_y + case_h + scale(28), face, message, true, false, rgb(85, 85, 85))
    end
end

function ShelfView:onTapShelf(_, gesture_event)
    local pos = gesture_event and gesture_event.pos
    if not pos then return false end
    for _, slot in ipairs(self.slots or {}) do
        if pos.x >= slot.x and pos.x < slot.x + slot.w and pos.y >= slot.y and pos.y < slot.y + slot.h + scale(6) then
            Features.openBook(self.appdock, self.home, slot.file)
            return true
        end
    end
    return false
end

function Features.openBook(appdock, home, file)
    if not fileExists(file) then return false end
    local function open()
        local ok, ReaderUI = pcall(require, "apps/reader/readerui")
        if ok and ReaderUI and ReaderUI.showReader then ReaderUI:showReader(file) end
    end
    if home then UIManager:close(home) end
    UIManager:nextTick(open)
    return true
end

--- The shelf page as a widget of `width` x `height`; the home screen decides
--- the page dots and swipes.
function Features.buildShelf(home, width, height)
    return ShelfView:new{ appdock = home.appdock, home = home, width = width, height = height }
end

return Features
