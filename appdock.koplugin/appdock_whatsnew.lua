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
local Rotation = require("appdock_rotation")
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
-- Release tour (9.10.0): DockAI, Liquid Glass clock, standby while charging, keyboard fix.
local PAGES = {
    {
        glyph = "✦",
        en = {
            title = "DockAI",
            text = "A new ChatGPT-style assistant powered by Groq. Every AppDock user has a daily and a weekly message limit; you see it in the app and under Settings > DockAI. The admin can add any number of Groq API keys there (password required); requests rotate through the keys and skip keys that are busy or rejected.",
        },
        de = {
            title = "DockAI",
            text = "Ein neuer Assistent im ChatGPT-Stil, angetrieben von Groq. Jeder AppDock-Nutzer hat ein Tages- und ein Wochenlimit für Nachrichten; du siehst es in der App und unter Einstellungen > DockAI. Der Admin kann dort beliebig viele Groq-API-Keys eintragen (Passwort nötig); Anfragen wechseln reihum zwischen den Keys und überspringen Keys, die ausgelastet oder abgelehnt sind.",
        },
    },
    {
        glyph = "◇",
        en = {
            title = "Real Liquid Glass clock",
            text = "The Liquid Glass clock style (Settings > Lockscreen > Clock style) no longer puts the time on a glass card: the digits themselves are glass. The wallpaper bends at their edges like in a thick lens, a bright rim catches the light and a soft shadow lifts them off the screen. Grayscale screens get a stronger rim so the digits stay readable.",
        },
        de = {
            title = "Echte Liquid-Glass-Uhr",
            text = "Der Uhrenstil Liquid Glass (Einstellungen > Sperrbildschirm > Uhrenstil) legt die Zeit nicht mehr auf eine Glaskarte: Die Ziffern selbst sind aus Glas. Der Hintergrund bricht sich an ihren Kanten wie in einer dicken Linse, ein heller Rand fängt das Licht und ein weicher Schatten hebt sie vom Bildschirm ab. Auf Graustufen-Displays ist der Rand kräftiger, damit die Ziffern gut lesbar bleiben.",
        },
    },
    {
        glyph = "☾",
        en = {
            title = "Standby while charging",
            text = "When the eReader is plugged in, AppDock asks whether it should go to standby. Standby looks like the lockscreen, only with a very large clock (hours above minutes), the date and the battery level. It follows your clock style. Tap the screen to leave; unplugging the charger ends it too. Under Settings > Lockscreen > Standby you can switch the question to automatic or off, or start standby right away.",
        },
        de = {
            title = "Standby beim Laden",
            text = "Sobald der eReader am Ladegerät hängt, fragt AppDock, ob er in den Standby gehen soll. Standby sieht aus wie der Sperrbildschirm, nur mit einer sehr großen Uhr (Stunden über Minuten), dem Datum und dem Akkustand. Er folgt deinem Uhrenstil. Tippe auf den Bildschirm, um ihn zu verlassen; auch das Abziehen des Ladegeräts beendet ihn. Unter Einstellungen > Sperrbildschirm > Standby kannst du die Frage auf automatisch oder aus stellen oder den Standby sofort starten.",
        },
    },
    {
        glyph = "⌨",
        en = {
            title = "Keyboard preview fixed",
            text = "The text preview above the AppDock keyboard now measures the real width of what you type. Wide letters and emoji no longer push the end of the text behind the right edge: the cursor always stays visible and the beginning is shortened with an ellipsis instead.",
        },
        de = {
            title = "Tastatur-Vorschau repariert",
            text = "Die Textvorschau über der AppDock-Tastatur misst jetzt die echte Breite dessen, was du tippst. Breite Buchstaben und Emojis schieben das Textende nicht mehr hinter den rechten Rand: Der Cursor bleibt immer sichtbar, stattdessen wird der Anfang mit einer Ellipse gekürzt.",
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

Rotation.attach(NewsScreen, { relayout = function(self) self:build() end })

WhatsNew._test = { NewsScreen = NewsScreen, STRINGS = STRINGS }

return WhatsNew
