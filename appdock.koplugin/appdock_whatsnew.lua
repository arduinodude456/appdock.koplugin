--[[--
AppDock "What's new" dialog.

Uses the card layout of the first-run setup assistant (white card, blue pill
button, page dots) to walk through the changes of the current release.
The wizard's own drawing helpers are reused, so both flows look identical.

* Opened automatically once per AppDock version (AppDock:shouldShowUpdateDialog),
  i.e. exactly once for everyone who updates; it only explains what is new in Settings
  and from Settings > Update notice.
* English and Deutsch, following the AppDock language setting.
* Finishing or skipping marks this version as seen.

To announce a new release, edit PAGES below: one entry per page, with the
strings for both languages.
--]]--

local Setup = require("appdock_setup")
local UIManager = require("ui/uimanager")
local GestureRange = require("ui/gesturerange")
local Device = require("device")

local SetupScreen = Setup._test.SetupScreen
local Screen = Device.screen
local function px(n) return Screen:scaleBySize(n) end

local WhatsNew = {}

---------------------------------------------------------------------------
-- Content
---------------------------------------------------------------------------

local STRINGS = {
    en = {
        intro_title = "What's new",
        intro_sub = "AppDock %s brings something new. Here is a quick tour.",
        start = "Show me", next = "Next", back = "Back", skip = "Skip", done = "Done",
        outro_title = "That's it!",
        outro_sub = "You can open this overview again under Update notice.",
        page_of = "%d of %d",
    },
    de = {
        intro_title = "Neuigkeiten",
        intro_sub = "AppDock %s bringt Neues mit. Hier die Kurzübersicht.",
        start = "Zeig's mir", next = "Weiter", back = "Zurück", skip = "Überspringen", done = "Fertig",
        outro_title = "Das war's!",
        outro_sub = "Diese Übersicht kannst du unter „Update-Hinweis“ erneut öffnen.",
        page_of = "%d von %d",
    },
}

-- glyph: single character shown in the blue circle.
-- Themed keyboard and dialogs first, then the "Health & reading" section of Settings.
local PAGES = {
    {
        glyph = "☾",
        en = {
            title = "A reworked Dark Mode",
            text = "The Dark Mode has been reworked and no longer simply inverts all colors, to create a visually higher-quality experience.",
        },
        de = {
            title = "Überarbeiteter Dark Mode",
            text = "Der Dark Mode wurde überarbeitet und invertiert jetzt nicht mehr bloß alle Farben, um ein visuell hochwertigeres Erlebnis zu schaffen.",
        },
    },
    {
        glyph = "◐",
        en = {
            title = "Themed Keyboard and Dialogs",
            text = "The AppDock keyboard and all AppDock dialogs now follow your active color theme. On color screens the keyboard is drawn in the eight fast E-Ink colors (black, white, red, green, blue, yellow, magenta and cyan) and dithered, so it keeps refreshing quickly. Everything else is unchanged.",
        },
        de = {
            title = "Themed Keyboard and Dialogs",
            text = "Die AppDock-Tastatur und alle AppDock-Dialoge folgen jetzt deinem aktiven Farbthema. Auf Farbdisplays wird die Tastatur in den acht schnellen E-Ink-Farben (Schwarz, Weiß, Rot, Grün, Blau, Gelb, Magenta und Cyan) gezeichnet und gedithert, damit sie weiterhin schnell aktualisiert. Alles andere bleibt unverändert.",
        },
    },
    {
        glyph = "+",
        en = {
            title = "New in Settings: Health & reading",
            text = "Settings has a new section called Health & reading. It collects everything that looks after your eyes and your reading habits. All of it is optional and off until you switch it on.",
        },
        de = {
            title = "Neu in den Einstellungen: Gesundheit und Lesen",
            text = "In den Einstellungen gibt es die neue Sektion „Gesundheit und Lesen“. Sie bündelt alles, was deine Augen und deine Lesegewohnheiten schont. Alles ist optional und bleibt aus, bis du es einschaltest.",
        },
    },
    {
        glyph = "☼",
        en = {
            title = "Eye protection: your day timeline",
            text = "Plan brightness and warmth by time of day. Four points (morning, midday, evening, night) form a curve on a 24-hour chart. Pick a point, tap the chart to move it, or start from a preset like Night owl. The light then follows the curve by itself.",
        },
        de = {
            title = "Augenschutz: deine Tages-Timeline",
            text = "Plane Helligkeit und Wärme nach Tageszeit. Vier Punkte (Morgen, Mittag, Abend, Nacht) bilden eine Kurve auf einem 24-Stunden-Diagramm. Wähle einen Punkt, tippe ins Diagramm, um ihn zu verschieben, oder starte mit einer Vorlage wie Nachteule. Das Licht folgt der Kurve dann von selbst.",
        },
    },
    {
        glyph = "≡",
        en = {
            title = "Statistics: reading and on-time",
            text = "See how long you read and how long your reader was on, today and over the last 7 days, with daily averages, totals and your reading streak. Counting stays on this device and can be switched off or reset at any time.",
        },
        de = {
            title = "Statistiken: Lesezeit und Reader-An-Zeit",
            text = "Sieh, wie lange du liest und wie lange dein Reader an war: heute und in den letzten 7 Tagen, mit Tagesdurchschnitt, Gesamtzeit und Lese-Serie. Gezählt wird nur auf diesem Gerät. Du kannst es jederzeit ausschalten oder zurücksetzen.",
        },
    },
    {
        glyph = "♪",
        en = {
            title = "Health: reading breaks and bedtime",
            text = "Get a gentle reminder to rest your eyes after a set reading time, and another one when it is time to go to bed, with an optional heads-up before. You choose the intervals and the times.",
        },
        de = {
            title = "Gesundheit: Lesepausen und Zubettgehen",
            text = "Lass dich nach einer festgelegten Lesezeit sanft an eine Augenpause erinnern und außerdem ans Zubettgehen, auf Wunsch mit Vorwarnung. Intervalle und Uhrzeiten stellst du selbst ein.",
        },
    },
}
WhatsNew.PAGES = PAGES

---------------------------------------------------------------------------
-- Widget
---------------------------------------------------------------------------

local NewsScreen = SetupScreen:extend{
    appdock = nil,
    on_done = nil,
    covers_fullscreen = true,
}

function NewsScreen:init()
    self.dimen = Screen:getSize()
    local settings = self.appdock and self.appdock.settings or {}
    local accessibility = type(settings.accessibility) == "table" and settings.accessibility or {}
    self.lang = settings.language == "de" and "de" or "en"
    self.text_scale = math.max(1, math.min(1.3, tonumber(accessibility.text_scale) or 1))
    -- index 0 = intro, 1..#PAGES = feature pages, #PAGES + 1 = outro
    self.index = 0
    self.page = "news"
    self.history = {}
    self.version = self.appdock and type(self.appdock.getRelease) == "function" and self.appdock:getRelease() or ""
    self.ges_events = { TapSetup = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    if Device.hasKeys and Device:hasKeys() and Device.input and Device.input.group
        and Device.input.group.Back then
        self.key_events = { SetupBack = { Device.input.group.Back } }
    end
    self:build()
end

function NewsScreen:t(key)
    local strings = STRINGS[self.lang] or STRINGS.en
    return strings[key] or STRINGS.en[key] or key
end

function NewsScreen:_last() return #PAGES + 1 end

function NewsScreen:goNext()
    if self.index >= self:_last() then self:finish() return end
    self.index = self.index + 1
    self:refresh()
end

function NewsScreen:goBack()
    if self.index > 0 then
        self.index = self.index - 1
        self:refresh()
    end
    return true
end

function NewsScreen:_dots()
    local total = self:_last() + 1
    local gap, size = px(12), px(6)
    local width = total * size + (total - 1) * gap
    local y = self.y + self.h + px(14)
    if y + size > self.dimen.h - px(6) then return end
    local x = math.floor((self.dimen.w - width) / 2)
    for i = 0, total - 1 do
        self:_box(x + i * (size + gap), y, size, size, {
            fill = i == self.index and self.c.accent or self.c.line, radius = math.floor(size / 2),
        })
    end
end

function NewsScreen:_page_news()
    local c = self.c
    local index = self.index
    if index == 0 then
        local y = self.y + math.floor(self.h * 0.30)
        y = y + self:_text(self:t("intro_title"), y, 28, c.ink, false, "center") + px(8)
        y = y + self:_para(string.format(self:t("intro_sub"), self.version ~= "" and self.version or "8"), y, 11, c.muted) + px(36)
        self:_centerPill(self:t("start"), y, function() self:goNext() end)
        self:_link(self:t("skip"), nil, self.bottom - px(18), "center", function() self:finish() end)
        return
    end
    if index == self:_last() then
        local y = self.y + math.floor(self.h * 0.28)
        y = y + self:_text(self:t("outro_title"), y, 28, c.ink, false, "center") + px(14)
        self:_para(self:t("outro_sub"), y, 11, c.muted)
        self:_centerPill(self:t("done"), self.bottom - math.floor(px(40) * math.min(self.text_scale, 1.15)) - px(12),
            function() self:finish() end)
        return
    end
    local page = PAGES[index]
    local copy = page[self.lang] or page.en
    local y = self.top + px(10)
    y = y + self:_icon(page.glyph, y) + px(14)
    y = y + self:_text(string.format(self:t("page_of"), index, #PAGES), y, 10, c.muted, false, "center") + px(8)
    y = y + self:_para(copy.title, y, 20, c.ink) + px(12)
    self:_para(copy.text, y, 11, c.muted)
    self:_footer(
        { label = self:t("back"), fn = function() self:goBack() end },
        { label = self:t("next"), fn = function() self:goNext() end })
end

function NewsScreen:finish()
    if self._finished then return end
    self._finished = true
    local appdock, on_done = self.appdock, self.on_done
    if appdock and type(appdock.dismissUpdateDialog) == "function" then
        pcall(appdock.dismissUpdateDialog, appdock)
    end
    UIManager:close(self)
    WhatsNew._current = nil
    if on_done then UIManager:nextTick(function() on_done(true) end) end
end

function NewsScreen:onSetupBack()
    if self.index == 0 then self:finish() else self:goBack() end
    return true
end

--- Shows the dialog. Returns false when it is already open.
function WhatsNew.show(appdock, on_done)
    if WhatsNew._current and WhatsNew._current._finished ~= true then return false end
    local screen = NewsScreen:new{ appdock = appdock, on_done = on_done }
    WhatsNew._current = screen
    UIManager:show(screen)
    return true
end

WhatsNew._test = { NewsScreen = NewsScreen, STRINGS = STRINGS }

return WhatsNew
