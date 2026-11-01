--[[--
AppDock first-run setup.

A full-screen, card-style assistant modelled on the Android / One UI setup flow:
Welcome -> Copy apps and data -> TBS account -> Search -> Items to review ->
Appearance -> Device -> Extras -> Wiki -> "You're all set up!".

* Shown once to every reader that has not completed it (see
  AppDock:shouldRunSetup); it can be repeated from Settings.
* A TBS account is offered instead of a Google account, and only when this
  reader does not already hold one.
* Languages: English (default) and Deutsch. The wizard carries its own string
  table so the choice applies immediately, independent of KOReader's language.
* Choices are collected and written in one go on "Finish"; only accessibility
  options (needed to read the wizard itself) apply immediately.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")

local Screen = Device.screen

local Setup = {}

Setup.WIKI_URL = "https://github.com/arduinodude456/appdock.koplugin/wiki"
Setup.REPO_URL = "https://github.com/arduinodude456/appdock.koplugin"

---------------------------------------------------------------------------
-- Strings
---------------------------------------------------------------------------

local STRINGS = {
    en = {
        lang_name = "English",
        welcome = "Welcome!",
        welcome_sub = "Let's set up AppDock on your reader.",
        start = "Start", next = "Next", back = "Back", skip = "Skip", finish = "Finish",
        accessibility = "Accessibility",
        acc_title = "Accessibility",
        acc_text = "Text size",
        acc_normal = "Normal", acc_large = "Large", acc_xlarge = "Extra large",
        acc_contrast = "High contrast",
        on = "On", off = "Off", close = "Close", cancel = "Cancel", ok = "OK",
        copy_title = "Copy apps and data",
        copy_text = "You can restore your TBS account, settings and app list from another reader.",
        dont_copy = "Don't copy",
        restore_id_title = "Account ID", restore_id_hint = "TBS account ID",
        restore_code_title = "Recovery code", restore_code_hint = "TBS-… recovery code",
        restore_bad_id = "Enter a valid TBS account ID.",
        restore_done = "TBS account restored.",
        account_title = "Create your TBS account",
        account_sub = "A TBS account backs up compact AppDock settings. No books, media or files are uploaded.",
        account_hint = "Display name",
        have_account = "Already have an account?",
        creating = "Creating your TBS account…",
        recovery_title = "Save your recovery code",
        recovery_text = "Write down both values now. The recovery code is shown only once. You need them to move to another reader.",
        account_id = "Account ID", recovery_code = "Recovery code",
        wrote_down = "I wrote it down",
        search_title = "Choose your search provider",
        search_text = "This decides whether the AppDock homescreen shows a search bar. Searches open in the AppDock browser.",
        search_ddg = "DuckDuckGo", search_ddg_sub = "Search bar on the homescreen",
        search_none = "No search bar", search_none_sub = "Keep the homescreen clean",
        legal_title = "A few items to review",
        legal_sub = "Your data will be used according to our Privacy Policy.",
        legal_privacy = "AppDock Privacy Policy",
        legal_backup = "Settings backup to TBS account",
        legal_signals = "Anonymous app-usage signals",
        optional = "optional",
        details = "Details",
        agree_all = "I have read and agree to all of the above.",
        legal_privacy_text = "AppDock keeps its settings locally on this reader. A TBS account additionally stores compact settings and recently used apps (no books, media, file paths, profile picture or username) for up to 7 months, so you can move to another reader. You can request deletion at any time.",
        legal_backup_text = "After you change settings, a compact copy is uploaded to your TBS account. If this is off, nothing is uploaded automatically; “Sync now” in TBS Account still works.",
        legal_signals_text = "Counts how often you open each app (numbers only) so AppDock can recommend apps. Stored in your TBS account.",
        appearance_title = "Appearance",
        appearance_text = "Pick a colour theme and the shape of your app icons. You can change both later in Settings.",
        theme = "Theme", shape = "App icons",
        shape_rounded = "Rounded squares", shape_circle = "Circles",
        device_title = "Which device is this?",
        device_text = "The name is used for this reader in your TBS account and in AppDock.",
        device_label = "Device", detected = "detected", other = "Other…",
        device_prompt = "Device name", device_hint = "e.g. My Kobo",
        device_choose = "Choose your device",
        extras_title = "A few extras",
        extras_text = "Optional. Everything here can be changed later in Settings.",
        extra_launch = "Open AppDock when KOReader starts",
        extra_restore = "Reopen my last apps after a restart",
        extra_sleep = "Show the AppDock sleep screen",
        extra_power = "Power saving mode",
        wiki_title = "Read the AppDock Wiki?",
        wiki_text = "The wiki explains the homescreen, the AppStore, DApps, themes and more. It opens in the AppDock browser (internet needed).",
        not_now = "Not now", open_wiki = "Open wiki",
        wiki_failed = "The wiki could not be opened here. You can find it at:",
        done_title = "You're all set up!",
        sum_theme = "Theme", sum_device = "Device", sum_account = "TBS account", sum_language = "Language",
        sum_none = "none", sum_skipped = "skipped", sum_signed_in = "signed in",
        no_network = "No internet connection. Connect to Wi-Fi and try again.",
        failed = "That did not work. Please try again.",
        theme_lavender = "Lavender", theme_ocean = "Ocean", theme_forest = "Forest", theme_sunset = "Sunset",
    },
    de = {
        lang_name = "Deutsch",
        welcome = "Willkommen!",
        welcome_sub = "Richten wir AppDock auf deinem Lesegerät ein.",
        start = "Start", next = "Weiter", back = "Zurück", skip = "Überspringen", finish = "Fertig",
        accessibility = "Bedienungshilfen",
        acc_title = "Bedienungshilfen",
        acc_text = "Textgröße",
        acc_normal = "Normal", acc_large = "Groß", acc_xlarge = "Sehr groß",
        acc_contrast = "Hoher Kontrast",
        on = "An", off = "Aus", close = "Schließen", cancel = "Abbrechen", ok = "OK",
        copy_title = "Apps und Daten kopieren",
        copy_text = "Du kannst dein TBS-Konto, deine Einstellungen und die App-Liste von einem anderen Lesegerät übernehmen.",
        dont_copy = "Nicht kopieren",
        restore_id_title = "Konto-ID", restore_id_hint = "TBS-Konto-ID",
        restore_code_title = "Wiederherstellungscode", restore_code_hint = "TBS-… Wiederherstellungscode",
        restore_bad_id = "Gib eine gültige TBS-Konto-ID ein.",
        restore_done = "TBS-Konto wiederhergestellt.",
        account_title = "TBS-Konto erstellen",
        account_sub = "Ein TBS-Konto sichert kompakte AppDock-Einstellungen. Es werden keine Bücher, Medien oder Dateien hochgeladen.",
        account_hint = "Anzeigename",
        have_account = "Schon ein Konto?",
        creating = "TBS-Konto wird erstellt…",
        recovery_title = "Wiederherstellungscode sichern",
        recovery_text = "Notiere dir jetzt beide Werte. Der Wiederherstellungscode wird nur einmal angezeigt. Du brauchst sie, um auf ein anderes Lesegerät umzuziehen.",
        account_id = "Konto-ID", recovery_code = "Wiederherstellungscode",
        wrote_down = "Habe ich notiert",
        search_title = "Suchanbieter wählen",
        search_text = "Damit legst du fest, ob der AppDock-Startbildschirm eine Suchleiste zeigt. Suchanfragen öffnen sich im AppDock-Browser.",
        search_ddg = "DuckDuckGo", search_ddg_sub = "Suchleiste auf dem Startbildschirm",
        search_none = "Keine Suchleiste", search_none_sub = "Startbildschirm aufgeräumt lassen",
        legal_title = "Ein paar Punkte zur Prüfung",
        legal_sub = "Deine Daten werden gemäß unserer Datenschutzerklärung verwendet.",
        legal_privacy = "AppDock-Datenschutzerklärung",
        legal_backup = "Einstellungs-Backup im TBS-Konto",
        legal_signals = "Anonyme App-Nutzungssignale",
        optional = "optional",
        details = "Details",
        agree_all = "Ich habe alles gelesen und stimme allem zu.",
        legal_privacy_text = "AppDock speichert seine Einstellungen lokal auf diesem Lesegerät. Ein TBS-Konto speichert zusätzlich kompakte Einstellungen und zuletzt genutzte Apps (keine Bücher, Medien, Dateipfade, kein Profilbild und kein Benutzername) für bis zu 7 Monate, damit du auf ein anderes Lesegerät umziehen kannst. Du kannst jederzeit die Löschung beantragen.",
        legal_backup_text = "Nach Änderungen an den Einstellungen wird eine kompakte Kopie in dein TBS-Konto hochgeladen. Ist die Option aus, wird nichts automatisch hochgeladen; „Jetzt sichern“ im TBS-Konto funktioniert weiterhin.",
        legal_signals_text = "Zählt, wie oft du jede App öffnest (nur Zahlen), damit AppDock Apps empfehlen kann. Gespeichert in deinem TBS-Konto.",
        appearance_title = "Erscheinungsbild",
        appearance_text = "Wähle ein Farbthema und die Form deiner App-Symbole. Beides lässt sich später in den Einstellungen ändern.",
        theme = "Thema", shape = "App-Symbole",
        shape_rounded = "Abgerundete Quadrate", shape_circle = "Kreise",
        device_title = "Welches Gerät ist das?",
        device_text = "Der Name wird für dieses Lesegerät in deinem TBS-Konto und in AppDock verwendet.",
        device_label = "Gerät", detected = "erkannt", other = "Andere…",
        device_prompt = "Gerätename", device_hint = "z. B. Mein Kobo",
        device_choose = "Gerät auswählen",
        extras_title = "Noch ein paar Extras",
        extras_text = "Optional. Alles hier lässt sich später in den Einstellungen ändern.",
        extra_launch = "AppDock beim Start von KOReader öffnen",
        extra_restore = "Zuletzt geöffnete Apps nach Neustart wieder öffnen",
        extra_sleep = "AppDock-Ruhebildschirm anzeigen",
        extra_power = "Energiesparmodus",
        wiki_title = "AppDock-Wiki lesen?",
        wiki_text = "Das Wiki erklärt Startbildschirm, AppStore, DApps, Themes und mehr. Es öffnet sich im AppDock-Browser (Internet nötig).",
        not_now = "Jetzt nicht", open_wiki = "Wiki öffnen",
        wiki_failed = "Das Wiki konnte hier nicht geöffnet werden. Du findest es unter:",
        done_title = "Alles eingerichtet!",
        sum_theme = "Thema", sum_device = "Gerät", sum_account = "TBS-Konto", sum_language = "Sprache",
        sum_none = "keins", sum_skipped = "übersprungen", sum_signed_in = "angemeldet",
        no_network = "Keine Internetverbindung. Verbinde dich mit WLAN und versuche es erneut.",
        failed = "Das hat nicht geklappt. Bitte versuche es erneut.",
        theme_lavender = "Lavendel", theme_ocean = "Ozean", theme_forest = "Wald", theme_sunset = "Sonnenuntergang",
    },
}
Setup.STRINGS = STRINGS

local DEVICE_PRESETS = {
    { name = "Kobo Libra Colour", kind = "kobo" },
    { name = "Kobo Clara Colour", kind = "kobo" },
    { name = "Kobo Clara BW", kind = "kobo" },
    { name = "Kobo Libra 2", kind = "kobo" },
    { name = "Kobo Sage", kind = "kobo" },
    { name = "Kobo Elipsa 2E", kind = "kobo" },
    { name = "Tolino Shine Color", kind = "tolino" },
    { name = "Tolino Vision Color", kind = "tolino" },
    { name = "Tolino Epos 3", kind = "tolino" },
    { name = "Kindle", kind = "kindle" },
    { name = "PocketBook", kind = "pocketbook" },
    { name = "reMarkable", kind = "remarkable" },
    { name = "Boox", kind = "boox" },
}
Setup.DEVICE_PRESETS = DEVICE_PRESETS

local TEXT_SCALES = { 1, 1.15, 1.3 }

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function px(n) return Screen:scaleBySize(n) end

local function rgb(r, g, b, fallback)
    -- Always try real RGB: on colour panels it is true blue, on greyscale
    -- panels KOReader converts it to a dark grey that stays readable.
    if type(Blitbuffer.ColorRGB32) == "function" then
        local ok, value = pcall(Blitbuffer.ColorRGB32, r, g, b, 0xFF)
        if ok and value then return value end
    end
    return fallback
end

local function palette()
    return {
        bg = Blitbuffer.COLOR_WHITE,
        ink = Blitbuffer.COLOR_BLACK,
        muted = Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_BLACK,
        border = rgb(218, 220, 224, Blitbuffer.COLOR_GRAY or Blitbuffer.COLOR_DARK_GRAY),
        line = rgb(232, 234, 237, Blitbuffer.COLOR_LIGHT_GRAY or Blitbuffer.COLOR_WHITE),
        accent = rgb(26, 115, 232, Blitbuffer.COLOR_BLACK),
        accent_off = rgb(168, 199, 250, Blitbuffer.COLOR_LIGHT_GRAY or Blitbuffer.COLOR_WHITE),
        on_accent = Blitbuffer.COLOR_WHITE,
    }
end

local function sizeOf(widget, fallback_w, fallback_h)
    if type(widget) == "table" and type(widget.getSize) == "function" then
        local ok, size = pcall(widget.getSize, widget)
        if ok and type(size) == "table" and size.w and size.h then return size end
    end
    return { w = fallback_w or 0, h = fallback_h or px(20) }
end

local function trim(value)
    return type(value) == "string" and (value:match("^%s*(.-)%s*$") or "") or ""
end

--- Best-effort guess of this reader's model; empty when unknown.
function Setup.detectDevice()
    local model = type(Device.model) == "string" and Device.model:lower() or ""
    local function flag(name)
        if type(Device[name]) ~= "function" then return false end
        local ok, value = pcall(Device[name], Device)
        return ok and value == true
    end
    local known = {
        { "monza", "Kobo Libra Colour" }, { "spacolour", "Kobo Clara Colour" },
        { "spabw", "Kobo Clara BW" }, { "goldfinch", "Kobo Clara 2E" },
        { "kobo_io", "Kobo Libra 2" }, { "cadmus", "Kobo Sage" },
        { "condor", "Kobo Elipsa 2E" }, { "europa", "Kobo Elipsa" },
    }
    for _, entry in ipairs(known) do
        if model:find(entry[1], 1, true) then return entry[2], "kobo" end
    end
    if flag("isKobo") then return "Kobo", "kobo" end
    if flag("isKindle") then return "Kindle", "kindle" end
    if flag("isPocketBook") then return "PocketBook", "pocketbook" end
    if flag("isRemarkable") then return "reMarkable", "remarkable" end
    if flag("isAndroid") then return "Boox", "boox" end
    return "", ""
end

local function safeRequire(name)
    local ok, module = pcall(require, name)
    if ok and type(module) == "table" then return module end
    return nil
end

---------------------------------------------------------------------------
-- Widget
---------------------------------------------------------------------------

local SetupScreen = InputContainer:extend{
    appdock = nil,
    on_done = nil,
    options = nil,
    covers_fullscreen = true,
}

local PAGE_ORDER = {
    "welcome", "copy", "account", "recovery", "search", "legal",
    "appearance", "device", "extras", "wiki", "done",
}
Setup.PAGE_ORDER = PAGE_ORDER

function SetupScreen:init()
    self.dimen = Screen:getSize()
    self.options = self.options or {}
    local settings = self.appdock and self.appdock.settings or {}
    local accessibility = type(settings.accessibility) == "table" and settings.accessibility or {}
    self.lang = settings.language == "de" and "de" or "en"
    self.text_scale = math.max(1, math.min(1.3, tonumber(accessibility.text_scale) or 1))
    self.signed_in = self:_isSignedIn()
    self.page = "welcome"
    self.history = {}
    local name, kind = Setup.detectDevice()
    self.device = { name = name, kind = kind, detected = name }
    local layout = type(settings.layout) == "table" and settings.layout or {}
    local theme = type(settings.theme) == "table" and settings.theme or {}
    local privacy = type(settings.privacy) == "table" and settings.privacy or {}
    local workspace = type(settings.workspace) == "table" and settings.workspace or {}
    self.choice = {
        theme = type(theme.selected) == "string" and theme.selected or "lavender",
        logo_shape = layout.logo_shape == "circle" and "circle" or "rounded",
        search = (layout.search_enabled == true and layout.ddg_search ~= false) and "ddg" or "none",
        agree_privacy = false,
        cloud_backup = privacy.cloud_backup ~= false,
        share_usage = privacy.share_app_usage ~= false,
        launch_on_start = settings.launch_on_start == true,
        restore = workspace.restore_enabled == true,
        sleepscreen = settings.sleepscreen_enabled == true,
        power_saving = settings.power_saving == true,
        want_wiki = false,
    }
    self.account_name = ""
    self.account_status = self.signed_in and "signed_in" or nil
    self.ges_events = { TapSetup = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    if Device.hasKeys and Device:hasKeys() and Device.input and Device.input.group
        and Device.input.group.Back then
        self.key_events = { SetupBack = { Device.input.group.Back } }
    end
    self:build()
end

function SetupScreen:t(key)
    local table_for = STRINGS[self.lang] or STRINGS.en
    return table_for[key] or STRINGS.en[key] or key
end

function SetupScreen:_isSignedIn()
    local Account = safeRequire("appdock_tbs_account")
    if not Account or type(Account.isSignedIn) ~= "function" then return false end
    local ok, value = pcall(Account.isSignedIn, self.appdock)
    return ok and value == true
end

function SetupScreen:_visible(id)
    if id == "copy" or id == "account" then return not self.signed_in end
    if id == "recovery" then return self.recovery ~= nil end
    return true
end

function SetupScreen:_neighbour(step)
    local index
    for i, id in ipairs(PAGE_ORDER) do if id == self.page then index = i end end
    index = (index or 1) + step
    while index >= 1 and index <= #PAGE_ORDER do
        if self:_visible(PAGE_ORDER[index]) then return PAGE_ORDER[index] end
        index = index + step
    end
    return nil
end

function SetupScreen:goTo(id, remember)
    if not id then return end
    if remember ~= false then self.history[#self.history + 1] = self.page end
    self.page = id
    self:refresh()
end

function SetupScreen:goNext() self:goTo(self:_neighbour(1)) end

function SetupScreen:goBack()
    while #self.history > 0 do
        local previous = table.remove(self.history)
        if self:_visible(previous) and previous ~= "recovery" then
            self.page = previous
            self:refresh()
            return true
        end
    end
    return false
end

function SetupScreen:refresh()
    self:build()
    UIManager:setDirty(self, "ui")
end

-- Drawing ---------------------------------------------------------------

function SetupScreen:_font(size, bold)
    return Font:getFace(bold and "cfont" or "smallinfofont", math.floor(px(size) * self.text_scale))
end

function SetupScreen:_text(text, y, size, colour, bold, align, x, w)
    x = x or self.cx
    w = w or self.cw
    local widget = TextWidget:new{
        text = text, face = self:_font(size, bold), fgcolor = colour, bold = bold,
        max_width = w, padding = 0,
    }
    local height = sizeOf(widget, w, px(size)).h
    local holder = widget
    if align == "center" then
        holder = CenterContainer:new{ dimen = Geom:new{ w = w, h = height }, widget }
    end
    holder.overlap_offset = { x, y }
    self.layers[#self.layers + 1] = holder
    return height
end

function SetupScreen:_para(text, y, size, colour, align)
    local widget = TextBoxWidget:new{
        text = text, face = self:_font(size, false), width = self.cw,
        alignment = align or "center", fgcolor = colour,
    }
    widget.overlap_offset = { self.cx, y }
    self.layers[#self.layers + 1] = widget
    return sizeOf(widget, self.cw, px(size) * 3).h
end

function SetupScreen:_box(x, y, w, h, opts)
    local box = FrameContainer:new{
        width = w, height = h, padding = 0, margin = 0,
        bordersize = opts.border or 0, color = opts.color, radius = opts.radius or 0,
        background = opts.fill, overlap_offset = { x, y },
        CenterContainer:new{ dimen = Geom:new{ w = w, h = h }, opts.child or HorizontalSpan:new{ width = 0 } },
    }
    self.layers[#self.layers + 1] = box
    return box
end

function SetupScreen:_hit(x, y, w, h, fn)
    self.hits[#self.hits + 1] = { x = x, y = y, w = w, h = h, fn = fn }
end

function SetupScreen:_pill(label, x, y, w, enabled, fn)
    local c = self.c
    local h = math.floor(px(46) * math.min(self.text_scale, 1.15))
    local text = TextWidget:new{
        text = label, face = self:_font(14, true), fgcolor = c.on_accent, bold = true,
        max_width = w - px(16), padding = 0,
    }
    self:_box(x, y, w, h, {
        fill = enabled and c.accent or c.accent_off, radius = math.floor(h / 2), child = text,
    })
    if enabled and fn then self:_hit(x, y, w, h, fn) end
    return h
end

function SetupScreen:_link(label, x, y, align, fn)
    local c = self.c
    local widget = TextWidget:new{
        text = label, face = self:_font(13, true), fgcolor = c.accent, bold = true,
        max_width = math.floor(self.cw / 2), padding = 0,
    }
    local size = sizeOf(widget, #label * px(8), px(18))
    local w = math.min(size.w, math.floor(self.cw / 2))
    local lx = align == "right" and (self.cx + self.cw - w) or (align == "center" and (self.cx + math.floor((self.cw - w) / 2)) or x or self.cx)
    widget.overlap_offset = { lx, y }
    self.layers[#self.layers + 1] = widget
    local pad = px(10)
    self:_hit(lx - pad, y - pad, w + 2 * pad, size.h + 2 * pad, fn)
    return size.h
end

function SetupScreen:_icon(glyph, y)
    local c = self.c
    local size = px(32)
    local text = TextWidget:new{ text = glyph, face = self:_font(15, true), fgcolor = c.accent, bold = true, padding = 0 }
    self:_box(math.floor(self.x + (self.w - size) / 2), y, size, size, {
        border = math.max(1, px(2)), color = c.accent, radius = math.floor(size / 2), fill = c.bg, child = text,
    })
    return size
end

function SetupScreen:_divider(y)
    self:_box(self.cx, y, self.cw, math.max(1, px(1)), { fill = self.c.line })
end

-- A radio/check row. Returns the height it used.
function SetupScreen:_row(y, row)
    local c = self.c
    local height = math.floor(px(52) * math.min(self.text_scale, 1.2))
    local dot = px(22)
    local dot_y = y + math.floor((height - dot) / 2)
    local checked = row.checked == true
    self:_box(self.cx, dot_y, dot, dot, {
        border = math.max(1, px(2)), color = checked and c.accent or c.muted,
        radius = math.floor(dot / 2), fill = c.bg,
    })
    if checked then
        local filled = px(10)
        self:_box(self.cx + math.floor((dot - filled) / 2), dot_y + math.floor((dot - filled) / 2), filled, filled,
            { fill = c.accent, radius = math.floor(filled / 2) })
    end
    local text_x = self.cx + dot + px(14)
    local text_w = self.cw - dot - px(14)
    local used = height
    local label_h = self:_text(row.label, y + px(8), 14, c.ink, false, "left", text_x, text_w)
    local sub_y = y + px(8) + label_h
    if row.sub then
        sub_y = sub_y + px(1)
        self:_text(row.sub, sub_y, 10, c.muted, false, "left", text_x, text_w)
    end
    if row.details then
        local details_y = y + height - px(2)
        local link_h = self:_link(self:t("details"), text_x, details_y, "left", row.details)
        used = height + link_h
    end
    self:_hit(self.cx, y, self.cw, height, row.fn)
    if not row.no_line then self:_divider(y + used) end
    return used + px(2)
end

function SetupScreen:_field(y, value, hint, fn)
    local c = self.c
    local height = px(46)
    local shown = value ~= "" and value or hint
    local text = TextWidget:new{
        text = shown, face = self:_font(13, false),
        fgcolor = value ~= "" and c.ink or c.muted, max_width = self.cw - px(28), padding = 0,
    }
    self:_box(self.cx, y, self.cw, height, {
        border = math.max(1, px(1)), color = c.muted, radius = px(5), fill = c.bg,
    })
    text.overlap_offset = { self.cx + px(14), y + math.floor((height - sizeOf(text, 0, px(16)).h) / 2) }
    self.layers[#self.layers + 1] = text
    self:_hit(self.cx, y, self.cw, height, fn)
    return height
end

function SetupScreen:_dropdown(y, label, fn)
    local c = self.c
    local height = px(44)
    self:_divider(y)
    self:_divider(y + height)
    self:_text(label, y + math.floor((height - px(16)) / 2), 13, c.ink, false, "left", self.cx, self.cw - px(30))
    self:_text("▾", y + math.floor((height - px(16)) / 2), 13, c.muted, false, "right", self.cx + self.cw - px(24), px(24))
    self:_hit(self.cx, y, self.cw, height, fn)
    return height
end

function SetupScreen:build()
    local c = palette()
    self.c = c
    self.layers = {}
    self.hits = {}
    local W, H = self.dimen.w, self.dimen.h
    local margin = math.max(px(14), math.floor(W * 0.05))
    local card_w = math.min(W - 2 * margin, px(560))
    local card_h = math.min(H - 2 * margin - px(16), math.max(px(340), math.floor(card_w * 1.6)))
    local card_x = math.floor((W - card_w) / 2)
    local card_y = math.floor((H - card_h) / 2) - px(8)
    local pad = px(24)
    self.x, self.y, self.w, self.h = card_x, card_y, card_w, card_h
    self.cx, self.cw = card_x + pad, card_w - 2 * pad
    self.top, self.bottom = card_y + pad, card_y + card_h - pad

    self.layers[1] = FrameContainer:new{
        width = W, height = H, padding = 0, bordersize = 0, background = c.bg,
        CenterContainer:new{ dimen = Geom:new{ w = W, h = H }, HorizontalSpan:new{ width = 0 } },
    }
    self:_box(card_x, card_y, card_w, card_h, {
        border = math.max(1, px(1)), color = c.border, radius = px(4), fill = c.bg,
    })

    local builder = self["_page_" .. self.page]
    if builder then builder(self) end
    self:_dots()

    self:clear()
    self[1] = OverlapGroup:new{ dimen = self.dimen, allow_mirroring = false, unpack(self.layers) }
end

function SetupScreen:_dots()
    local order = {}
    for _, id in ipairs(PAGE_ORDER) do
        if self:_visible(id) and id ~= "recovery" then order[#order + 1] = id end
    end
    local gap, size = px(12), px(6)
    local total = #order * size + (#order - 1) * gap
    local y = self.y + self.h + px(14)
    if y + size > self.dimen.h - px(6) then return end
    local x = math.floor((self.dimen.w - total) / 2)
    local current = self.page == "recovery" and "account" or self.page
    for index, id in ipairs(order) do
        self:_box(x + (index - 1) * (size + gap), y, size, size, {
            fill = id == current and self.c.accent or self.c.line, radius = math.floor(size / 2),
        })
    end
end

-- Pages ------------------------------------------------------------------

function SetupScreen:_footer(left, right)
    local y = self.bottom - math.floor(px(46) * math.min(self.text_scale, 1.15))
    if left then
        self:_link(left.label, self.cx, y + px(13), "left", left.fn)
    end
    if right then
        local w = math.min(px(124), math.floor(self.cw * 0.45))
        self:_pill(right.label, self.cx + self.cw - w, y, w, right.enabled ~= false, right.fn)
    end
end

function SetupScreen:_centerPill(label, y, fn)
    local w = math.min(px(170), self.cw)
    return self:_pill(label, self.cx + math.floor((self.cw - w) / 2), y, w, true, fn)
end

function SetupScreen:_page_welcome()
    local c = self.c
    local y = self.y + math.floor(self.h * 0.30)
    y = y + self:_text(self:t("welcome"), y, 28, c.ink, false, "center") + px(8)
    y = y + self:_text(self:t("welcome_sub"), y, 11, c.muted, false, "center") + px(40)
    local label = self:t("lang_name") .. "  ▾"
    y = y + self:_text(label, y, 12, c.ink, false, "center") + px(14)
    self:_hit(self.cx, y - px(44), self.cw, px(44), function() self:_chooseLanguage() end)
    self:_centerPill(self:t("start"), y, function() self:goNext() end)
    self:_link(self:t("accessibility"), nil, self.bottom - px(18), "center", function() self:_showAccessibility() end)
end

function SetupScreen:_page_copy()
    local c = self.c
    local y = self.top + px(8)
    y = y + self:_icon("↔", y) + px(14)
    y = y + self:_text(self:t("copy_title"), y, 24, c.ink, false, "center") + px(10)
    y = y + self:_para(self:t("copy_text"), y, 12, c.muted) + px(10)
    self:_footer(
        { label = self:t("dont_copy"), fn = function() self.account_status = nil; self:goNext() end },
        { label = self:t("next"), fn = function() self:_restoreAccount() end })
end

function SetupScreen:_page_account()
    local c = self.c
    local y = self.top + px(4)
    y = y + self:_icon("T", y) + px(12)
    y = y + self:_text(self:t("account_title"), y, 24, c.ink, false, "center") + px(8)
    y = y + self:_para(self:t("account_sub"), y, 11, c.muted) + px(18)
    y = y + self:_field(y, self.account_name, self:t("account_hint"), function() self:_editName() end) + px(10)
    y = y + self:_link(self:t("have_account"), nil, y, "left", function() self:_restoreAccount() end)
    self:_footer(
        { label = self:t("skip"), fn = function() self.account_status = "skipped"; self:goNext() end },
        { label = self:t("next"), fn = function() self:_createAccount() end })
end

function SetupScreen:_page_recovery()
    local c = self.c
    local recovery = self.recovery or {}
    local y = self.top + px(4)
    y = y + self:_icon("!", y) + px(12)
    y = y + self:_text(self:t("recovery_title"), y, 22, c.ink, false, "center") + px(8)
    y = y + self:_para(self:t("recovery_text"), y, 11, c.muted) + px(14)
    y = y + self:_text(self:t("account_id"), y, 10, c.muted, false, "left") + px(2)
    y = y + self:_para(recovery.account_id or "", y, 11, c.ink, "left") + px(10)
    y = y + self:_text(self:t("recovery_code"), y, 10, c.muted, false, "left") + px(2)
    y = y + self:_para(recovery.code or "", y, 12, c.ink, "left")
    self:_footer(nil, { label = self:t("wrote_down"), fn = function()
        self.recovery = nil
        self:goTo(self:_neighbour(1), false)
    end })
end

function SetupScreen:_page_search()
    local c = self.c
    local y = self.top + px(4)
    y = y + self:_icon("?", y) + px(12)
    y = y + self:_text(self:t("search_title"), y, 22, c.ink, false, "center") + px(8)
    y = y + self:_para(self:t("search_text"), y, 11, c.muted) + px(14)
    local function pick(value) return function() self.choice.search = value; self:refresh() end end
    self:_divider(y)
    y = y + self:_row(y, { label = self:t("search_ddg"), sub = self:t("search_ddg_sub"), checked = self.choice.search == "ddg", fn = pick("ddg") })
    y = y + self:_row(y, { label = self:t("search_none"), sub = self:t("search_none_sub"), checked = self.choice.search == "none", fn = pick("none") })
    self:_footer({ label = self:t("back"), fn = function() self:goBack() end },
        { label = self:t("next"), fn = function() self:goNext() end })
end

function SetupScreen:_info(text, duration)
    local Dialogs = safeRequire("appdock_dialogs")
    if Dialogs and Dialogs.InfoMessage then
        UIManager:show(Dialogs.InfoMessage:new{ text = text, duration = duration or 5 })
    end
end

function SetupScreen:_page_legal()
    local c = self.c
    local has_account = self.account_status == "signed_in" or self.signed_in
    local y = self.top
    y = y + self:_icon("1", y) + px(10)
    y = y + self:_text(self:t("legal_title"), y, 22, c.ink, false, "center") + px(6)
    y = y + self:_para(self:t("legal_sub"), y, 11, c.muted) + px(10)
    local function show(key) return function() self:_info(self:t(key), 20) end end
    local function sync_agree()
        self.choice.agree_all = self.choice.agree_privacy
            and (not has_account or (self.choice.cloud_backup and self.choice.share_usage))
    end
    local rows = {
        { label = self:t("legal_privacy"), checked = self.choice.agree_privacy, details = show("legal_privacy_text"),
          fn = function() self.choice.agree_privacy = not self.choice.agree_privacy; self:refresh() end },
    }
    if has_account then
        rows[#rows + 1] = { label = self:t("legal_backup") .. " (" .. self:t("optional") .. ")", checked = self.choice.cloud_backup,
            details = show("legal_backup_text"),
            fn = function() self.choice.cloud_backup = not self.choice.cloud_backup; self:refresh() end }
        rows[#rows + 1] = { label = self:t("legal_signals") .. " (" .. self:t("optional") .. ")", checked = self.choice.share_usage,
            details = show("legal_signals_text"),
            fn = function() self.choice.share_usage = not self.choice.share_usage; self:refresh() end }
    end
    for _, row in ipairs(rows) do y = y + self:_row(y, row) end
    y = y + px(8)
    sync_agree()
    self:_row(y, { label = self:t("agree_all"), checked = self.choice.agree_all, fn = function()
        local value = not (self.choice.agree_privacy and (not has_account or (self.choice.cloud_backup and self.choice.share_usage)))
        self.choice.agree_privacy = value
        if has_account then self.choice.cloud_backup, self.choice.share_usage = value, value end
        self:refresh()
    end })
    self:_footer({ label = self:t("back"), fn = function() self:goBack() end },
        { label = self:t("next"), enabled = self.choice.agree_privacy, fn = function() self:goNext() end })
end

function SetupScreen:_themeList()
    local Theme = safeRequire("appdock_theme")
    local list = {}
    if Theme and type(Theme.getThemeList) == "function" then
        local ok, value = pcall(Theme.getThemeList, self.appdock.settings)
        if ok and type(value) == "table" then list = value end
    end
    if #list == 0 then list = { { id = "lavender", title = "Lavender" } } end
    return list
end

function SetupScreen:_themeTitle(theme)
    local key = "theme_" .. tostring(theme.id)
    local translated = (STRINGS[self.lang] or {})[key]
    return translated or theme.title or theme.id
end

function SetupScreen:_page_appearance()
    local c = self.c
    local y = self.top
    y = y + self:_icon("2", y) + px(10)
    y = y + self:_text(self:t("appearance_title"), y, 22, c.ink, false, "center") + px(6)
    y = y + self:_para(self:t("appearance_text"), y, 11, c.muted) + px(8)
    y = y + self:_text(self:t("theme"), y, 10, c.muted, true, "left") + px(2)
    for _, theme in ipairs(self:_themeList()) do
        y = y + self:_row(y, { label = self:_themeTitle(theme), checked = self.choice.theme == theme.id,
            fn = function() self.choice.theme = theme.id; self:refresh() end })
    end
    y = y + px(6)
    y = y + self:_text(self:t("shape"), y, 10, c.muted, true, "left") + px(2)
    y = y + self:_row(y, { label = self:t("shape_rounded"), checked = self.choice.logo_shape == "rounded",
        fn = function() self.choice.logo_shape = "rounded"; self:refresh() end })
    y = y + self:_row(y, { label = self:t("shape_circle"), checked = self.choice.logo_shape == "circle",
        fn = function() self.choice.logo_shape = "circle"; self:refresh() end })
    self:_footer({ label = self:t("back"), fn = function() self:goBack() end },
        { label = self:t("next"), fn = function() self:goNext() end })
end

function SetupScreen:_page_device()
    local c = self.c
    local y = self.top + px(4)
    y = y + self:_icon("3", y) + px(10)
    y = y + self:_text(self:t("device_title"), y, 22, c.ink, false, "center") + px(8)
    y = y + self:_para(self:t("device_text"), y, 11, c.muted) + px(16)
    y = y + self:_text(self:t("device_label"), y, 10, c.muted, true, "left") + px(2)
    local name = self.device.name ~= "" and self.device.name or "—"
    if self.device.detected ~= "" and self.device.name == self.device.detected then
        name = name .. "  (" .. self:t("detected") .. ")"
    end
    y = y + self:_dropdown(y, name, function() self:_chooseDevice() end)
    self:_footer({ label = self:t("back"), fn = function() self:goBack() end },
        { label = self:t("next"), fn = function() self:goNext() end })
end

function SetupScreen:_page_extras()
    local c = self.c
    local y = self.top
    y = y + self:_icon("4", y) + px(10)
    y = y + self:_text(self:t("extras_title"), y, 22, c.ink, false, "center") + px(6)
    y = y + self:_para(self:t("extras_text"), y, 11, c.muted) + px(8)
    local function toggle(key) return function() self.choice[key] = not self.choice[key]; self:refresh() end end
    local rows = {
        { "extra_launch", "launch_on_start" }, { "extra_restore", "restore" },
        { "extra_sleep", "sleepscreen" }, { "extra_power", "power_saving" },
    }
    self:_divider(y)
    for _, spec in ipairs(rows) do
        y = y + self:_row(y, { label = self:t(spec[1]), checked = self.choice[spec[2]], fn = toggle(spec[2]) })
    end
    self:_footer({ label = self:t("back"), fn = function() self:goBack() end },
        { label = self:t("next"), fn = function() self:goNext() end })
end

function SetupScreen:_page_wiki()
    local c = self.c
    local y = self.top + px(10)
    y = y + self:_icon("?", y) + px(14)
    y = y + self:_text(self:t("wiki_title"), y, 24, c.ink, false, "center") + px(10)
    y = y + self:_para(self:t("wiki_text"), y, 11, c.muted) + px(12)
    y = y + self:_para("github.com/arduinodude456/appdock.koplugin", y, 10, c.ink) + px(4)
    self:_footer(
        { label = self:t("not_now"), fn = function() self.choice.want_wiki = false; self:goNext() end },
        { label = self:t("open_wiki"), fn = function() self.choice.want_wiki = true; self:goNext() end })
end

function SetupScreen:_summary()
    local theme_title = self.choice.theme
    for _, theme in ipairs(self:_themeList()) do
        if theme.id == self.choice.theme then theme_title = self:_themeTitle(theme) end
    end
    local account = self:t("sum_skipped")
    if self.account_status == "signed_in" or self.account_status == "created" then
        account = self:t("sum_signed_in")
    end
    return {
        self:t("sum_language") .. ": " .. self:t("lang_name"),
        self:t("sum_theme") .. ": " .. theme_title,
        self:t("sum_device") .. ": " .. (self.device.name ~= "" and self.device.name or self:t("sum_none")),
        self:t("sum_account") .. ": " .. account,
    }
end

function SetupScreen:_page_done()
    local c = self.c
    local y = self.y + math.floor(self.h * 0.22)
    y = y + self:_text(self:t("done_title"), y, 28, c.ink, false, "center") + px(18)
    for _, line in ipairs(self:_summary()) do
        y = y + self:_text(line, y, 11, c.muted, false, "center") + px(4)
    end
    self:_centerPill(self:t("finish"), self.bottom - math.floor(px(40) * math.min(self.text_scale, 1.15)) - px(12),
        function() self:finish() end)
end

-- Actions ----------------------------------------------------------------

function SetupScreen:_dialogs()
    return safeRequire("appdock_dialogs")
end

function SetupScreen:_afterClose(callback)
    if UIManager.nextTick then UIManager:nextTick(callback) else callback() end
end

function SetupScreen:_chooseLanguage()
    local Dialogs = self:_dialogs()
    if not Dialogs or not Dialogs.ButtonDialog then return end
    local dialog
    local buttons = {}
    for _, code in ipairs({ "en", "de" }) do
        buttons[#buttons + 1] = { { text = STRINGS[code].lang_name .. (code == self.lang and "  ✓" or ""), callback = function()
            UIManager:close(dialog)
            self.lang = code
            self:_afterClose(function() self:refresh() end)
        end } }
    end
    dialog = Dialogs.ButtonDialog:new{ title = "Language / Sprache", buttons = buttons }
    UIManager:show(dialog)
end

function SetupScreen:_showAccessibility()
    local Dialogs = self:_dialogs()
    if not Dialogs or not Dialogs.ButtonDialog then return end
    local dialog
    local settings = self.appdock.settings
    local contrast = type(settings.accessibility) == "table" and settings.accessibility.high_contrast == true
    local names = { self:t("acc_normal"), self:t("acc_large"), self:t("acc_xlarge") }
    local buttons = {}
    for index, scale_value in ipairs(TEXT_SCALES) do
        buttons[#buttons + 1] = { { text = self:t("acc_text") .. ": " .. names[index] .. (scale_value == self.text_scale and "  ✓" or ""),
            callback = function()
                UIManager:close(dialog)
                self.text_scale = scale_value
                if self.appdock.setAccessibility then self.appdock:setAccessibility({ text_scale = scale_value }) end
                self:_afterClose(function() self:refresh() end)
            end } }
    end
    buttons[#buttons + 1] = { { text = self:t("acc_contrast") .. ": " .. (contrast and self:t("on") or self:t("off")), callback = function()
        UIManager:close(dialog)
        if self.appdock.setAccessibility then self.appdock:setAccessibility({ high_contrast = not contrast }) end
        self:_afterClose(function() self:refresh() end)
    end } }
    buttons[#buttons + 1] = { { text = self:t("close"), callback = function() UIManager:close(dialog) end } }
    dialog = Dialogs.ButtonDialog:new{ title = self:t("acc_title"), buttons = buttons }
    UIManager:show(dialog)
end

-- Shows a text prompt on top of the wizard. `done(value)` gets nil on cancel.
function SetupScreen:_prompt(title, hint, initial, done)
    local Dialogs = self:_dialogs()
    if not Dialogs or not Dialogs.InputDialog then return end
    local dialog
    dialog = Dialogs.InputDialog:new{
        title = title, input_hint = hint, input = initial or "",
        buttons = { {
            { text = self:t("cancel"), callback = function() UIManager:close(dialog); self:_afterClose(function() done(nil) end) end },
            { text = self:t("ok"), is_enter_default = true, callback = function()
                local value = trim(dialog:getInputText() or "")
                UIManager:close(dialog)
                self:_afterClose(function() done(value) end)
            end },
        } },
    }
    local Keyboard = safeRequire("appdock_keyboard")
    if Keyboard and Keyboard.attach then pcall(Keyboard.attach, dialog) end
    UIManager:show(dialog)
    if dialog.onShowKeyboard then dialog:onShowKeyboard() end
end

function SetupScreen:_editName()
    self:_prompt(self:t("account_title"), self:t("account_hint"), self.account_name, function(value)
        if value then self.account_name = value:sub(1, 80) end
        self:refresh()
    end)
end

function SetupScreen:_chooseDevice()
    local Dialogs = self:_dialogs()
    if not Dialogs or not Dialogs.ButtonDialog then return end
    local dialog
    local buttons = {}
    local function mark(name) return name == self.device.name and "  ✓" or "" end
    for _, preset in ipairs(DEVICE_PRESETS) do
        local label = preset.name .. (preset.name == self.device.detected and ("  (" .. self:t("detected") .. ")") or "") .. mark(preset.name)
        buttons[#buttons + 1] = { { text = label, callback = function()
            UIManager:close(dialog)
            self.device.name, self.device.kind = preset.name, preset.kind
            self:_afterClose(function() self:refresh() end)
        end } }
    end
    buttons[#buttons + 1] = { { text = self:t("other"), callback = function()
        UIManager:close(dialog)
        self:_afterClose(function()
            self:_prompt(self:t("device_prompt"), self:t("device_hint"), "", function(value)
                if value and value ~= "" then self.device.name, self.device.kind = value:sub(1, 60), "other" end
                self:refresh()
            end)
        end)
    end } }
    dialog = Dialogs.ButtonDialog:new{ title = self:t("device_choose"), buttons = buttons, rows_per_page = { 6, 7, 8 } }
    UIManager:show(dialog)
end

function SetupScreen:_withNetwork(callback)
    local NetworkMgr = safeRequire("ui/network/manager")
    if NetworkMgr and type(NetworkMgr.runWhenOnline) == "function" then
        NetworkMgr:runWhenOnline(callback)
    else
        callback()
    end
end

function SetupScreen:_createAccount()
    local Account = safeRequire("appdock_tbs_account")
    if not Account or type(Account.register) ~= "function" then self:_info(self:t("failed")); return end
    self:_withNetwork(function()
        local name = self.account_name ~= "" and self.account_name or (self.device.name ~= "" and self.device.name or "AppDock")
        local created, err = Account.register(self.appdock, name, self.device.name)
        if not created then
            self:_info(err or self:t("failed"))
            return
        end
        self.signed_in = true
        self.account_status = "created"
        self.recovery = {
            account_id = created.account and created.account.account_id or "",
            code = created.recovery_code or "",
        }
        self:goTo("recovery")
    end)
end

function SetupScreen:_restoreAccount()
    local Account = safeRequire("appdock_tbs_account")
    if not Account or type(Account.migrate) ~= "function" then self:_info(self:t("failed")); return end
    self:_prompt(self:t("restore_id_title"), self:t("restore_id_hint"), "", function(account_id)
        if not account_id then return end
        account_id = account_id:lower()
        if #account_id ~= 36 or not account_id:match("^[%x%-]+$") then
            self:_info(self:t("restore_bad_id"))
            return
        end
        self:_prompt(self:t("restore_code_title"), self:t("restore_code_hint"), "", function(code)
            if not code or code == "" then return end
            self:_withNetwork(function()
                local migrated, err = Account.migrate(self.appdock, account_id, code, self.device.name)
                if not migrated then self:_info(err or self:t("failed")); return end
                if type(Account.snapshotFromResponse) == "function" and type(Account.applySnapshot) == "function" then
                    local snapshot = Account.snapshotFromResponse({ snapshot = migrated.snapshot })
                    if snapshot then pcall(Account.applySnapshot, self.appdock, snapshot) end
                end
                self.signed_in = true
                self.account_status = "signed_in"
                self:_info(self:t("restore_done"))
                self:goTo("search")
            end)
        end)
    end)
end

-- Writes every collected choice. Each step is isolated so one failing setter
-- can never block the remaining options or the completion flag.
function SetupScreen:apply()
    local appdock, choice = self.appdock, self.choice
    local function try(fn, ...)
        local ok, err = pcall(fn, ...)
        if not ok then
            local logger = safeRequire("logger")
            if logger and logger.err then logger.err("AppDock setup: " .. tostring(err)) end
        end
    end
    if appdock.setTheme then try(appdock.setTheme, appdock, choice.theme) end
    if appdock.setLauncherLayout then
        try(appdock.setLauncherLayout, appdock, {
            logo_shape = choice.logo_shape,
            search_enabled = choice.search == "ddg",
            ddg_search = choice.search == "ddg" or nil,
        })
    end
    if appdock.setDevice then try(appdock.setDevice, appdock, self.device.name, self.device.kind) end
    if appdock.setPrivacyOption then
        try(appdock.setPrivacyOption, appdock, "cloud_backup", choice.cloud_backup)
        try(appdock.setPrivacyOption, appdock, "share_app_usage", choice.share_usage)
    end
    if appdock.setLaunchOnStart then try(appdock.setLaunchOnStart, appdock, choice.launch_on_start) end
    if appdock.setWorkspaceRestoreEnabled then try(appdock.setWorkspaceRestoreEnabled, appdock, choice.restore) end
    if appdock.setSleepScreenEnabled then try(appdock.setSleepScreenEnabled, appdock, choice.sleepscreen) end
    if appdock.setPowerSaving then try(appdock.setPowerSaving, appdock, choice.power_saving) end
    if appdock.setKeyboardLanguage then try(appdock.setKeyboardLanguage, appdock, self.lang) end
    if appdock.completeSetup then try(appdock.completeSetup, appdock, { language = self.lang }) end
end

function SetupScreen:finish()
    if self._finished then return end
    self._finished = true
    self:apply()
    local appdock, want_wiki = self.appdock, self.choice.want_wiki
    local on_done, lang = self.on_done, self.lang
    UIManager:close(self)
    UIManager:nextTick(function()
        if on_done then on_done(true) end
        if want_wiki then Setup.openWiki(appdock, lang) end
    end)
end

function Setup.openWiki(appdock, lang)
    local function open()
        local manager = appdock and appdock.getDAppManager and appdock:getDAppManager()
        if manager and type(manager.openWebURL) == "function" and manager:openWebURL(Setup.WIKI_URL) then return end
        local Dialogs = safeRequire("appdock_dialogs")
        if Dialogs and Dialogs.InfoMessage then
            local text = (STRINGS[lang] or STRINGS.en).wiki_failed
            UIManager:show(Dialogs.InfoMessage:new{ text = text .. "\n" .. Setup.WIKI_URL, duration = 10 })
        end
    end
    local NetworkMgr = safeRequire("ui/network/manager")
    if NetworkMgr and type(NetworkMgr.runWhenOnline) == "function" then
        NetworkMgr:runWhenOnline(open)
    else
        open()
    end
end

function SetupScreen:onTapSetup(_, gesture)
    local pos = gesture and gesture.pos
    if not pos then return true end
    for index = #self.hits, 1, -1 do
        local hit = self.hits[index]
        if pos.x >= hit.x and pos.x < hit.x + hit.w and pos.y >= hit.y and pos.y < hit.y + hit.h then
            hit.fn()
            return true
        end
    end
    return true
end

-- The wizard is deliberately not dismissable by Back; Back steps backwards.
function SetupScreen:onSetupBack()
    self:goBack()
    return true
end

function SetupScreen:paintTo(bb, x, y)
    local range = self.ges_events.TapSetup[1].range
    range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    return InputContainer.paintTo(self, bb, x, y)
end

--- Shows the setup. `on_done(true)` runs after "Finish".
function Setup.show(appdock, on_done, options)
    local screen = SetupScreen:new{ appdock = appdock, on_done = on_done, options = options }
    UIManager:show(screen)
    Setup._current = screen
    return true
end

Setup._test = { SetupScreen = SetupScreen }

return Setup
