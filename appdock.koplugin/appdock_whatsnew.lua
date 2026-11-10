--[[--
AppDock "What's new" dialog.

Uses the card layout of the first-run setup assistant (white card, blue pill
button, page dots) to walk through the changes of the current release.
The wizard's own drawing helpers are reused, so both flows look identical.

* Opened automatically once per AppDock version (AppDock:shouldShowUpdateDialog)
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
        intro_sub = "Here is what changed in AppDock %s.",
        start = "Show me", next = "Next", back = "Back", skip = "Skip", done = "Done",
        outro_title = "That's it!",
        outro_sub = "You can open this overview again in Settings under Update notice.",
        page_of = "%d of %d",
    },
    de = {
        intro_title = "Neuigkeiten",
        intro_sub = "Das hat sich in AppDock %s geändert.",
        start = "Zeig's mir", next = "Weiter", back = "Zurück", skip = "Überspringen", done = "Fertig",
        outro_title = "Das war's!",
        outro_sub = "Du kannst diese Übersicht jederzeit in den Einstellungen unter „Update-Hinweis“ erneut öffnen.",
        page_of = "%d von %d",
    },
}

-- glyph: single character shown in the blue circle.
local PAGES = {
    {
        glyph = "♪",
        en = {
            title = "Music keeps playing",
            text = "Close YouTube Music and the track plays on in the background. A notification at the top shows what is playing. When a track ends, the next one in your library starts.",
        },
        de = {
            title = "Musik läuft weiter",
            text = "Schließt du YouTube Music, spielt der Titel im Hintergrund weiter. Eine Benachrichtigung oben zeigt, was läuft. Endet ein Titel, startet der nächste aus deiner Bibliothek.",
        },
    },
    {
        glyph = "▶",
        en = {
            title = "Media card in quick settings",
            text = "Swipe down to see the media card, just like on Android: play and pause, previous and next, tap the progress bar to jump, and × to stop.",
        },
        de = {
            title = "Medienkarte in den Schnelleinstellungen",
            text = "Wische nach unten und sieh die Medienkarte wie bei Android: Wiedergabe und Pause, Zurück und Weiter, Tippen auf den Fortschrittsbalken springt, × beendet die Wiedergabe.",
        },
    },
    {
        glyph = "≡",
        en = {
            title = "All apps from the recents bar",
            text = "Swipe up from the bottom edge and tap All apps. You get a searchable list of every app, sorted A to Z. Swipe left or right to change pages.",
        },
        de = {
            title = "Alle Apps in der Leiste",
            text = "Wische vom unteren Rand nach oben und tippe auf „All apps“. Du bekommst eine durchsuchbare Liste aller Apps von A bis Z. Mit Wischen nach links oder rechts blätterst du.",
        },
    },
    {
        glyph = "+",
        en = {
            title = "Faster homescreen",
            text = "The homescreen now does less redundant work while it is built. It looks and works exactly as before.",
        },
        de = {
            title = "Schnellerer Startbildschirm",
            text = "Der Startbildschirm erledigt beim Aufbau weniger doppelte Arbeit. Aussehen und Funktionen bleiben unverändert.",
        },
    },
}
-- Last page: an announcement, not a change in this release.
PAGES[#PAGES + 1] = {
    glyph = "»",
    en = {
        title = "Coming soon: Android 4.4.2",
        text = "Android 4.4.2 for AppDock will be released soon. Stay tuned for the update!",
    },
    de = {
        title = "Demnächst: Android 4.4.2",
        text = "Android 4.4.2 für AppDock wird demnächst veröffentlicht. Bleib gespannt auf das Update!",
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
