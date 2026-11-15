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
-- Release tour: Cyber mode, shelf, pet and the new file chooser.
local PAGES = {
    {
        glyph = "◇",
        en = {
            title = "Cyber mode",
            text = "Pick the Cyber theme (Settings > Display > Theme) for a dark neon look: chamfered cards with glowing edges and a city skyline wallpaper. Under Settings > Display > Card style you can also switch the Cyber effects on or off, or leave them on automatic so they follow the theme.",
        },
        de = {
            title = "Cyber-Modus",
            text = "Wähle das Cyber-Theme (Einstellungen > Anzeige > Theme) für einen dunklen Neon-Look: abgeschrägte Karten mit leuchtenden Kanten und ein Hintergrund mit Skyline. Unter Einstellungen > Anzeige > Kartenstil kannst du die Cyber-Effekte außerdem ein- oder ausschalten oder auf Automatik lassen, dann folgen sie dem Theme.",
        },
    },
    {
        glyph = "▤",
        en = {
            title = "Shelf: your books at a glance",
            text = "Turn on Settings > Features > Enable shelf and swipe right on the first homescreen page. A wooden bookcase shows the books you read recently and some featured ones. Books you download with DLib appear here too. Tap a cover to open the book. On color screens the shelf is now drawn in full color.",
        },
        de = {
            title = "Regal: deine Bücher auf einen Blick",
            text = "Schalte unter Einstellungen > Funktionen „Regal aktivieren“ ein und wische auf der ersten Homescreen-Seite nach rechts. Ein Bücherregal aus Holz zeigt die zuletzt gelesenen und einige empfohlene Bücher. Auch Bücher, die du mit DLib herunterlädst, erscheinen hier. Tippe auf ein Cover, um das Buch zu öffnen. Auf Farbdisplays wird das Regal jetzt farbig gezeichnet.",
        },
    },
    {
        glyph = "♥",
        en = {
            title = "Reading pet",
            text = "Under Settings > Features you can adopt a pet that follows your reading: it is happy when you read every day, hungry when you do not, and grows with your total reading time. Choose a species, a name and where it appears. It never dies. On color screens it now has its real colors.",
        },
        de = {
            title = "Lese-Haustier",
            text = "Unter Einstellungen > Funktionen kannst du ein Haustier aufnehmen, das deinem Lesen folgt: Es freut sich, wenn du täglich liest, bekommt Hunger, wenn nicht, und wächst mit deiner gesamten Lesezeit. Wähle Tierart, Namen und wo es erscheint. Es stirbt nie. Auf Farbdisplays hat es jetzt seine echten Farben.",
        },
    },
    {
        glyph = "☰",
        en = {
            title = "New file chooser",
            text = "Wherever AppDock used to ask you to type a file path (wallpaper, lockscreen picture, plugin logos, sleepscreen assets, yt-dlp and ffmpeg, music and output folders) it now opens its own file chooser. Jump between Internal, SD card and Home, tap the path to go back, swipe up or down to page and swipe right to go up. Tap a file to preview it, then confirm with Select.",
        },
        de = {
            title = "Neuer Dateiwähler",
            text = "Überall, wo AppDock bisher einen Dateipfad zum Eintippen wollte (Hintergrundbild, Sperrbildschirm-Bild, Plugin-Logos, Schlafbild-Dateien, yt-dlp und ffmpeg, Musik- und Ausgabeordner), öffnet sich jetzt ein eigener Dateiwähler. Wechsle zwischen Intern, SD-Karte und Home, tippe auf den Pfad, um zurückzugehen, wische nach oben oder unten zum Blättern und nach rechts, um einen Ordner höher zu gehen. Tippe eine Datei an für die Vorschau und bestätige mit „Select“.",
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
