--[[--
AppDock "Health & reading" (Gesundheit und Lesen).

Three parts, all local and optional:

* Eye protection: brightness and warmth follow a 24 h curve made of four
  anchor points (morning, midday, evening, night). The editor is a "day
  timeline": tap the chart to move the selected anchor, tap an anchor to pick it.
* Statistics: reading time and reader-on time per day (kept in a separate
  G_reader_settings key, so counting never triggers a settings sync).
* Health: reading-break and bedtime reminders.

The module is split in a pure logic part (curve, stats, formatting; testable
without KOReader widgets) and the screens at the bottom, which reuse the card
drawing helpers of the setup assistant.
--]]--

local Device = require("device")
local UIManager = require("ui/uimanager")

local Health = {}

local TICK_SECONDS = 60
local MAX_TICK_GAP = 150      -- a longer gap means the device slept: do not count it
local READING_IDLE = 180      -- no page turn for 3 min: not reading any more
local BREAK_GAP = 300         -- 5 min without reading ends a continuous reading session
local MIN_GAP = 30            -- minimum distance between two anchors (minutes)
local STATS_KEY = "appdock_health_stats"
local KEEP_DAYS = 90

---------------------------------------------------------------------------
-- Strings (own table, follows the AppDock language like the setup assistant)
---------------------------------------------------------------------------

local STRINGS = {
    en = {
        cat_title = "Health & reading", cat_sub = "Eyes, statistics, breaks",
        sec_eye = "Eye protection", sec_stats = "Statistics", sec_care = "Health",
        eye_row_title = "Eye protection schedule",
        eye_row_off = "Off · brightness and warmth by time of day",
        eye_row_on = "On · now %d%% brightness, %d%% warmth",
        eye_row_on_nowarm = "On · now %d%% brightness",
        stats_row_title = "Reading time & reader on-time",
        stats_row_sub = "Today: %s reading · %s on",
        stats_toggle_title = "Record statistics",
        stats_toggle_on = "Counting reading and on-time on this device",
        stats_toggle_off = "Nothing is counted",
        break_row_title = "Reading break reminder",
        break_row_on = "Every %d min of reading · %d min break",
        bed_row_title = "Bedtime reminder",
        bed_row_on = "At %s · heads-up %s",
        off = "Off",
        eye_title = "Eye protection",
        eye_sub = "Brightness and warmth follow your day. Pick a point, then tap the chart to move it.",
        auto = "Adjust automatically", auto_sub_on = "Checked every minute", auto_sub_off = "Nothing is changed",
        tab_b = "Brightness", tab_w = "Warmth",
        morning = "Morning", midday = "Midday", evening = "Evening", night = "Night",
        now_line = "Now (%s): brightness %d%% · warmth %d%%",
        now_line_nowarm = "Now (%s): brightness %d%%",
        no_warm = "This device has no warm light. Only brightness is scheduled.",
        no_light = "This device has no frontlight control.",
        presets = "Presets", p_standard = "Standard", p_owl = "Night owl", p_early = "Early bird", p_warm = "Cosy",
        done = "Done",
        stats_title = "Statistics", record = "Record times",
        today = "Today", reading = "Reading time", on_time = "Reader on",
        last7 = "Last 7 days", legend = "Dark: reading · light: reader on",
        avg = "Daily average (7 days)", total = "Total", streak = "Reading streak",
        days = "%d day(s)", reset = "Reset statistics",
        reset_confirm = "Delete all recorded reading and on-time statistics?",
        cancel = "Cancel", delete = "Delete",
        care_title = "Health",
        break_sec = "Reading breaks", break_toggle = "Remind me to take breaks",
        break_every = "Remind after", break_len = "Break length",
        bed_sec = "Bedtime", bed_toggle = "Remind me to go to bed",
        bed_at = "Bedtime", bed_lead = "Heads-up before", test = "Show a test reminder",
        minutes = "%d min",
        break_title = "Time for a reading break",
        break_text = "You have been reading for %d minutes. Rest your eyes for %d minutes and look into the distance.",
        later = "Remind me in 10 min", ok = "OK",
        bed_pre_title = "Bedtime in %d minutes",
        bed_pre_text = "Finish your chapter, dim the light and wind down.",
        bed_now_title = "Time to go to bed",
        bed_now_text = "It is %s. Sleep well!",
        light_off = "Turn light off",
        weekdays = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" },
    },
    de = {
        cat_title = "Gesundheit und Lesen", cat_sub = "Augen, Statistiken, Pausen",
        sec_eye = "Augenschutz", sec_stats = "Statistiken", sec_care = "Gesundheit",
        eye_row_title = "Augenschutz-Zeitplan",
        eye_row_off = "Aus · Helligkeit und Wärme nach Tageszeit",
        eye_row_on = "An · jetzt %d %% Helligkeit, %d %% Wärme",
        eye_row_on_nowarm = "An · jetzt %d %% Helligkeit",
        stats_row_title = "Lesezeit & Reader-An-Zeit",
        stats_row_sub = "Heute: %s gelesen · %s an",
        stats_toggle_title = "Statistiken erfassen",
        stats_toggle_on = "Lese- und Einschaltzeit werden auf diesem Gerät gezählt",
        stats_toggle_off = "Es wird nichts gezählt",
        break_row_title = "Lesepausen-Erinnerung",
        break_row_on = "Alle %d Min. Lesen · %d Min. Pause",
        bed_row_title = "Zubettgeh-Erinnerung",
        bed_row_on = "Um %s · Vorwarnung %s",
        off = "Aus",
        eye_title = "Augenschutz",
        eye_sub = "Helligkeit und Wärme folgen deinem Tag. Wähle einen Punkt und tippe ins Diagramm, um ihn zu verschieben.",
        auto = "Automatisch anpassen", auto_sub_on = "Wird jede Minute geprüft", auto_sub_off = "Es wird nichts verändert",
        tab_b = "Helligkeit", tab_w = "Wärme",
        morning = "Morgen", midday = "Mittag", evening = "Abend", night = "Nacht",
        now_line = "Jetzt (%s): Helligkeit %d %% · Wärme %d %%",
        now_line_nowarm = "Jetzt (%s): Helligkeit %d %%",
        no_warm = "Dieses Gerät hat kein Warmlicht. Es wird nur die Helligkeit geplant.",
        no_light = "Dieses Gerät hat keine steuerbare Beleuchtung.",
        presets = "Vorlagen", p_standard = "Standard", p_owl = "Nachteule", p_early = "Frühaufsteher", p_warm = "Gemütlich",
        done = "Fertig",
        stats_title = "Statistiken", record = "Zeiten erfassen",
        today = "Heute", reading = "Lesezeit", on_time = "Reader an",
        last7 = "Letzte 7 Tage", legend = "Dunkel: gelesen · hell: Reader an",
        avg = "Ø pro Tag (7 Tage)", total = "Gesamt", streak = "Lese-Serie",
        days = "%d Tag(e)", reset = "Statistik zurücksetzen",
        reset_confirm = "Alle erfassten Lese- und Einschaltzeiten löschen?",
        cancel = "Abbrechen", delete = "Löschen",
        care_title = "Gesundheit",
        break_sec = "Lesepausen", break_toggle = "An Lesepausen erinnern",
        break_every = "Erinnern nach", break_len = "Pausenlänge",
        bed_sec = "Zubettgehen", bed_toggle = "Ans Zubettgehen erinnern",
        bed_at = "Schlafenszeit", bed_lead = "Vorwarnung", test = "Testerinnerung zeigen",
        minutes = "%d Min.",
        break_title = "Zeit für eine Lesepause",
        break_text = "Du liest seit %d Minuten. Gönn deinen Augen %d Minuten Pause und schau in die Ferne.",
        later = "In 10 Min. erinnern", ok = "Okay",
        bed_pre_title = "Schlafenszeit in %d Minuten",
        bed_pre_text = "Beende dein Kapitel, dimme das Licht und komm zur Ruhe.",
        bed_now_title = "Zeit fürs Bett",
        bed_now_text = "Es ist %s Uhr. Schlaf gut!",
        light_off = "Licht ausschalten",
        weekdays = { "So", "Mo", "Di", "Mi", "Do", "Fr", "Sa" },
    },
}
Health.STRINGS = STRINGS

function Health.lang(appdock)
    local settings = appdock and appdock.settings or {}
    return settings.language == "de" and "de" or "en"
end

--- Translated string; extra arguments are passed to string.format.
function Health.t(appdock, key, ...)
    local table_for = STRINGS[Health.lang(appdock)] or STRINGS.en
    local text = table_for[key]
    if text == nil then text = STRINGS.en[key] end
    if text == nil then return key end
    if select("#", ...) > 0 and type(text) == "string" then return string.format(text, ...) end
    return text
end

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

local function round(value) return math.floor(value + 0.5) end

local function int(value, fallback)
    value = tonumber(value)
    if not value or value ~= value then return fallback end
    return round(value)
end

function Health.nowMinute()
    local d = os.date("*t")
    return d.hour * 60 + d.min
end

function Health.formatClock(minute)
    minute = clamp(int(minute, 0), 0, 1439)
    return string.format("%02d:%02d", math.floor(minute / 60), minute % 60)
end

--- "1 h 05 min", "42 min" or "<1 min".
function Health.formatDuration(seconds)
    seconds = math.max(0, int(seconds, 0))
    local minutes = math.floor(seconds / 60)
    if minutes < 1 then return seconds > 0 and "<1 min" or "0 min" end
    if minutes < 60 then return string.format("%d min", minutes) end
    return string.format("%d h %02d min", math.floor(minutes / 60), minutes % 60)
end

local function dayKey(timestamp) return os.date("%Y-%m-%d", timestamp or os.time()) end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

local ANCHOR_IDS = { "morning", "midday", "evening", "night" }
Health.ANCHOR_IDS = ANCHOR_IDS

local function defaultPoints()
    return {
        { id = "morning", t = 420, b = 40, w = 10 },
        { id = "midday", t = 720, b = 70, w = 0 },
        { id = "evening", t = 1140, b = 40, w = 50 },
        { id = "night", t = 1350, b = 15, w = 90 },
    }
end

local normalized = setmetatable({}, { __mode = "k" })

--- Returns settings.health, normalised in place (once per settings table).
function Health.config(appdock)
    local settings = appdock.settings
    if type(settings.health) ~= "table" then settings.health = {} end
    local h = settings.health
    if normalized[h] then return h end

    h.eye = type(h.eye) == "table" and h.eye or {}
    h.eye.enabled = h.eye.enabled == true
    local defaults = defaultPoints()
    local stored = type(h.eye.points) == "table" and h.eye.points or {}
    local points = {}
    for index, def in ipairs(defaults) do
        local p = type(stored[index]) == "table" and stored[index] or {}
        points[index] = {
            id = def.id,
            t = clamp(int(p.t, def.t), 0, 1439),
            b = clamp(int(p.b, def.b), 0, 100),
            w = clamp(int(p.w, def.w), 0, 100),
        }
    end
    local valid = true
    for index = 2, 4 do
        if points[index].t < points[index - 1].t + MIN_GAP then valid = false end
    end
    h.eye.points = valid and points or defaults

    h.stats = type(h.stats) == "table" and h.stats or {}
    h.stats.enabled = h.stats.enabled ~= false

    h.breaks = type(h.breaks) == "table" and h.breaks or {}
    h.breaks.enabled = h.breaks.enabled == true
    h.breaks.interval = clamp(int(h.breaks.interval, 30), 10, 120)
    h.breaks.length = clamp(int(h.breaks.length, 5), 1, 30)

    h.bed = type(h.bed) == "table" and h.bed or {}
    h.bed.enabled = h.bed.enabled == true
    h.bed.time = clamp(int(h.bed.time, 23 * 60), 0, 1439)
    h.bed.lead = clamp(int(h.bed.lead, 15), 0, 60)
    h.bed.last_pre = type(h.bed.last_pre) == "string" and h.bed.last_pre or ""
    h.bed.last_now = type(h.bed.last_now) == "string" and h.bed.last_now or ""

    normalized[h] = true
    return h
end

local function save(appdock)
    if type(appdock._saveSettings) == "function" then appdock:_saveSettings() end
end

---------------------------------------------------------------------------
-- Eye protection: the curve
---------------------------------------------------------------------------

--- Brightness and warmth (0..100) at `minute` of the day: linear between the
--- four anchors, wrapping around midnight.
function Health.curveAt(eye, minute)
    local points = eye.points
    minute = minute % 1440
    local prev, nxt
    for index = 1, #points do
        if points[index].t <= minute then prev = points[index] end
    end
    local prev_t, next_t
    if prev then
        prev_t = prev.t
        for index = 1, #points do
            if points[index].t > minute then nxt = points[index]; break end
        end
        if nxt then next_t = nxt.t else nxt = points[1]; next_t = nxt.t + 1440 end
    else
        prev = points[#points]; prev_t = prev.t - 1440
        nxt = points[1]; next_t = nxt.t
    end
    local span = next_t - prev_t
    local fraction = span > 0 and (minute - prev_t) / span or 0
    return prev.b + (nxt.b - prev.b) * fraction, prev.w + (nxt.w - prev.w) * fraction
end

--- Moves one anchor: `t` (minute) and/or `key` ("b" or "w") with `value`.
function Health.setAnchor(appdock, index, t, key, value)
    local eye = Health.config(appdock).eye
    local point = eye.points[index]
    if not point then return end
    if t then
        local low = index > 1 and eye.points[index - 1].t + MIN_GAP or 0
        local high = index < #eye.points and eye.points[index + 1].t - MIN_GAP or 1439
        point.t = clamp(int(t, point.t), low, math.max(low, high))
    end
    if key == "b" or key == "w" then point[key] = clamp(int(value, point[key]), 0, 100) end
    save(appdock)
end

local function shifted(points, delta, db, dw)
    for _, p in ipairs(points) do
        p.t = clamp(p.t + delta, 0, 1439)
        p.b = clamp(p.b + db, 0, 100)
        p.w = clamp(p.w + dw, 0, 100)
    end
    return points
end

local PRESETS = {
    standard = function() return defaultPoints() end,
    owl = function() return shifted(defaultPoints(), 90, 0, 0) end,
    early = function() return shifted(defaultPoints(), -90, 0, 0) end,
    warm = function() return shifted(defaultPoints(), 0, -10, 35) end,
}
Health.PRESET_IDS = { "standard", "owl", "early", "warm" }

function Health.applyPreset(appdock, id)
    local builder = PRESETS[id]
    if not builder then return false end
    local h = Health.config(appdock)
    h.eye.points = builder()
    normalized[h] = nil
    Health.config(appdock)
    save(appdock)
    return true
end

function Health.setEyeEnabled(appdock, enabled)
    Health.config(appdock).eye.enabled = enabled == true
    save(appdock)
    if enabled then Health.applyEye(appdock, true) end
end

---------------------------------------------------------------------------
-- Eye protection: talking to the frontlight
---------------------------------------------------------------------------

local function powerDevice()
    local ok, powerd = pcall(function() return Device:getPowerDevice() end)
    return ok and type(powerd) == "table" and powerd or nil
end

local function deviceFlag(name)
    if type(Device[name]) ~= "function" then return false end
    local ok, value = pcall(Device[name], Device)
    return ok and value == true
end

function Health.hasFrontlight() return deviceFlag("hasFrontlight") and powerDevice() ~= nil end
function Health.hasWarmth() return Health.hasFrontlight() and deviceFlag("hasNaturalLight") end

--- Sets the light to the curve value of "now". Unless `force`, nothing happens
--- when the target barely moved, so a manual change stays until the curve moves on.
function Health.applyEye(appdock, force)
    local eye = Health.config(appdock).eye
    if not eye.enabled or not Health.hasFrontlight() then return false end
    local b, w = Health.curveAt(eye, Health.nowMinute())
    b, w = round(b), round(w)
    local last = Health._last_applied
    if not force and last and math.abs(last.b - b) < 2 and math.abs(last.w - w) < 2 then return false end
    local powerd = powerDevice()
    if not powerd then return false end
    pcall(function()
        local low, high = tonumber(powerd.fl_min) or 0, tonumber(powerd.fl_max) or 100
        if b <= 0 then
            if type(powerd.turnOffFrontlight) == "function" then powerd:turnOffFrontlight()
            elseif type(powerd.toggleFrontlight) == "function" and powerd:frontlightIntensity() > low then
                powerd:toggleFrontlight()
            end
        else
            powerd:setIntensity(clamp(low + round(b / 100 * (high - low)), low, high))
        end
        if Health.hasWarmth() and type(powerd.setWarmth) == "function" then
            local wlow, whigh = tonumber(powerd.fl_warmth_min) or 0, tonumber(powerd.fl_warmth_max) or 100
            powerd:setWarmth(clamp(wlow + round(w / 100 * (whigh - wlow)), wlow, whigh))
        end
        if powerd.updateResumeFrontlightState then powerd:updateResumeFrontlightState() end
    end)
    Health._last_applied = { b = b, w = w }
    return true
end

local function turnLightOff()
    local powerd = powerDevice()
    if not powerd then return end
    pcall(function()
        if type(powerd.turnOffFrontlight) == "function" then powerd:turnOffFrontlight()
        elseif type(powerd.toggleFrontlight) == "function" then powerd:toggleFrontlight() end
        if powerd.updateResumeFrontlightState then powerd:updateResumeFrontlightState() end
    end)
    Health._last_applied = nil
end

---------------------------------------------------------------------------
-- Statistics
---------------------------------------------------------------------------

local function loadStats()
    if Health._stats then return Health._stats end
    local stored = {}
    if _G.G_reader_settings and type(G_reader_settings.readSetting) == "function" then
        local ok, value = pcall(G_reader_settings.readSetting, G_reader_settings, STATS_KEY, {})
        if ok and type(value) == "table" then stored = value end
    end
    stored.days = type(stored.days) == "table" and stored.days or {}
    stored.total_read = math.max(0, tonumber(stored.total_read) or 0)
    stored.total_on = math.max(0, tonumber(stored.total_on) or 0)
    stored.since = type(stored.since) == "string" and stored.since or dayKey()
    Health._stats = stored
    return stored
end

local function flushPet(appdock)
    local ok, Pet = pcall(require, "appdock_pet")
    if ok and Pet and Pet.flush then pcall(Pet.flush, appdock) end
end

local function flushStats(hard)
    local stats = Health._stats
    if not stats or not _G.G_reader_settings then return end
    pcall(G_reader_settings.saveSetting, G_reader_settings, STATS_KEY, stats)
    if hard and type(G_reader_settings.flush) == "function" then pcall(G_reader_settings.flush, G_reader_settings) end
end

local function pruneDays(stats)
    local keys = {}
    for key in pairs(stats.days) do keys[#keys + 1] = key end
    if #keys <= KEEP_DAYS + 30 then return end
    table.sort(keys)
    for index = 1, #keys - KEEP_DAYS do stats.days[keys[index]] = nil end
end

--- kind: "read" or "on"
function Health.addTime(kind, seconds)
    if (kind ~= "read" and kind ~= "on") or seconds <= 0 then return end
    local stats = loadStats()
    local key = dayKey()
    local day = stats.days[key]
    if not day then
        day = { read = 0, on = 0 }
        stats.days[key] = day
        pruneDays(stats)
    end
    day[kind] = (tonumber(day[kind]) or 0) + seconds
    stats["total_" .. (kind == "read" and "read" or "on")] = stats["total_" .. (kind == "read" and "read" or "on")] + seconds
end

function Health.getStats() return loadStats() end

function Health.resetStats()
    Health._stats = { days = {}, total_read = 0, total_on = 0, since = dayKey() }
    flushStats(true)
end

--- Seconds recorded for the day `offset` days before today.
function Health.dayTotals(offset)
    local stats = loadStats()
    local d = os.date("*t")
    local stamp = os.time{ year = d.year, month = d.month, day = d.day, hour = 12 } - (offset or 0) * 86400
    local day = stats.days[dayKey(stamp)] or {}
    return tonumber(day.read) or 0, tonumber(day.on) or 0, os.date("*t", stamp).wday
end

--- Consecutive days (ending today, or yesterday while today is still empty)
--- with at least 5 minutes of reading.
function Health.streak()
    local count, start = 0, 0
    if Health.dayTotals(0) < 300 then start = 1 end
    for offset = start, KEEP_DAYS do
        if Health.dayTotals(offset) >= 300 then count = count + 1 else break end
    end
    return count
end

function Health.weekAverages()
    local read, on = 0, 0
    for offset = 0, 6 do
        local r, o = Health.dayTotals(offset)
        read, on = read + r, on + o
    end
    return read / 7, on / 7
end

---------------------------------------------------------------------------
-- Reminders (dialogs)
---------------------------------------------------------------------------

local function showDialog(appdock, title, text, buttons)
    local ok_dialogs, Dialogs = pcall(require, "appdock_dialogs")
    local ButtonDialog = ok_dialogs and Dialogs.ButtonDialog or require("ui/widget/buttondialog")
    local dialog
    local function wrap(callback)
        return function()
            UIManager:close(dialog)
            if callback then callback() end
        end
    end
    local rows = {}
    for _, button in ipairs(buttons) do
        rows[#rows + 1] = { { text = button.text, callback = wrap(button.callback) } }
    end
    dialog = ButtonDialog:new{ title = title .. "\n\n" .. text, buttons = rows }
    UIManager:show(dialog)
    return dialog
end

function Health.showBreakReminder(appdock, state, minutes)
    local cfg = Health.config(appdock).breaks
    local interval = minutes or cfg.interval
    if state then state.dialog_open = true end
    showDialog(appdock, Health.t(appdock, "break_title"),
        Health.t(appdock, "break_text", interval, cfg.length), {
            { text = Health.t(appdock, "ok"), callback = function()
                if state then state.dialog_open = false; state.streak = 0 end
            end },
            { text = Health.t(appdock, "later"), callback = function()
                if state then state.dialog_open = false; state.streak = math.max(0, cfg.interval * 60 - 600) end
            end },
        })
end

function Health.showBedReminder(appdock, state, lead_minutes)
    local cfg = Health.config(appdock).bed
    if state then state.dialog_open = true end
    local function closed() if state then state.dialog_open = false end end
    local title, text
    if lead_minutes then
        title = Health.t(appdock, "bed_pre_title", lead_minutes)
        text = Health.t(appdock, "bed_pre_text")
    else
        title = Health.t(appdock, "bed_now_title")
        text = Health.t(appdock, "bed_now_text", Health.formatClock(cfg.time))
    end
    showDialog(appdock, title, text, {
        { text = Health.t(appdock, "ok"), callback = closed },
        { text = Health.t(appdock, "later"), callback = function()
            closed()
            if state then state.bed_snooze_until = Health.nowMinute() + 10 end
        end },
        { text = Health.t(appdock, "light_off"), callback = function() closed(); turnLightOff() end },
    })
end

---------------------------------------------------------------------------
-- Runtime: one ticker per AppDock instance
---------------------------------------------------------------------------

local function inReader(state)
    local ui = state.appdock and state.appdock.ui
    return type(ui) == "table" and ui.document ~= nil
end

local function account(state, now)
    local appdock = state.appdock
    local cfg = Health.config(appdock)
    local dt = state.last_tick and (now - state.last_tick) or 0
    state.last_tick = now
    if dt < 0 or dt > MAX_TICK_GAP then dt = 0 end
    local reading = inReader(state) and state.last_activity ~= nil and (now - state.last_activity) <= READING_IDLE
    if cfg.stats.enabled then
        Health.addTime("on", dt)
        if reading then Health.addTime("read", dt) end
    end
    -- The reading pet is fed by reading in a book and by DReader on screen.
    if dt > 0 then
        local pet_ok, Pet = pcall(require, "appdock_pet")
        if pet_ok and Pet and Pet.isEnabled(appdock) and (reading or Pet.inDReader()) then
            pcall(Pet.addReading, appdock, dt)
        end
    end
    if reading then
        state.streak = (state.streak or 0) + dt
    elseif not state.last_activity or (now - state.last_activity) > BREAK_GAP then
        state.streak = 0
    end
    return cfg
end

local function checkReminders(state, cfg, now)
    local appdock = state.appdock
    if state.dialog_open then return end
    if cfg.breaks.enabled and inReader(state) and (state.streak or 0) >= cfg.breaks.interval * 60 then
        Health.showBreakReminder(appdock, state)
        return
    end
    if cfg.bed.enabled then
        local minute = Health.nowMinute()
        local snooze = state.bed_snooze_until
        if snooze then
            if minute < snooze and snooze - minute <= 15 then return end
            state.bed_snooze_until = nil
            if minute - snooze >= 0 and minute - snooze < 30 then
                Health.showBedReminder(appdock, state, nil)
                return
            end
        end
        local today = dayKey(now)
        local until_bed = (cfg.bed.time - minute) % 1440
        local since_bed = (minute - cfg.bed.time) % 1440
        if since_bed <= 10 and cfg.bed.last_now ~= today then
            cfg.bed.last_now = today
            cfg.bed.last_pre = today
            save(appdock)
            Health.showBedReminder(appdock, state, nil)
        elseif cfg.bed.lead > 0 and until_bed > 0 and until_bed <= cfg.bed.lead and cfg.bed.last_pre ~= today then
            cfg.bed.last_pre = today
            save(appdock)
            Health.showBedReminder(appdock, state, until_bed)
        end
    end
end

--- Starts the ticker for an AppDock instance. Returns the state table.
function Health.attach(appdock)
    if appdock.health_state then Health.detach(appdock.health_state) end
    local state = { appdock = appdock, last_tick = os.time(), streak = 0, ticks = 0 }
    state.tick = function()
        if state.detached then return end
        local ok, err = pcall(function()
            local now = os.time()
            local cfg = account(state, now)
            state.ticks = state.ticks + 1
            if state.ticks % 5 == 0 then flushStats(false) end
            Health.applyEye(appdock, false)
            checkReminders(state, cfg, now)
        end)
        if not ok then
            local logger_ok, logger = pcall(require, "logger")
            if logger_ok then logger.warn("AppDock health tick failed:", err) end
        end
        UIManager:scheduleIn(TICK_SECONDS, state.tick)
    end
    appdock.health_state = state
    UIManager:scheduleIn(3, function()
        if state.detached then return end
        pcall(Health.applyEye, appdock, true)
    end)
    UIManager:scheduleIn(TICK_SECONDS, state.tick)
    return state
end

function Health.detach(state)
    if not state or state.detached then return end
    pcall(function() account(state, os.time()) end)
    state.detached = true
    if UIManager.unschedule then UIManager:unschedule(state.tick) end
    flushStats(true)
    flushPet(state.appdock)
end

--- A page turn or reader start: the person is reading right now.
function Health.touch(state)
    if state and not state.detached then state.last_activity = os.time() end
end

function Health.onSuspend(state)
    if not state or state.detached then return end
    pcall(function() account(state, os.time()) end)
    state.last_tick = nil
    state.streak = 0
    flushStats(true)
    flushPet(state.appdock)
end

function Health.onResume(state)
    if not state or state.detached then return end
    state.last_tick = os.time()
    state.streak = 0
    if inReader(state) then state.last_activity = os.time() end
    pcall(Health.applyEye, state.appdock, true)
end

function Health.onCloseDocument(state)
    if not state or state.detached then return end
    pcall(function() account(state, os.time()) end)
    state.last_activity = nil
    state.streak = 0
    flushStats(true)
    flushPet(state.appdock)
end

---------------------------------------------------------------------------
-- Rows for the Settings category
---------------------------------------------------------------------------

--- Settings rows (title, subtitle, callback) in three sections.
function Health.settingsRows(appdock, context)
    local cfg = Health.config(appdock)
    local t = function(key, ...) return Health.t(appdock, key, ...) end
    local function rebuild() if context and context.requestRebuild then context.requestRebuild("ui") end end
    local function open(page)
        return function() Health.show(appdock, context, page) end
    end

    local eye_sub
    if cfg.eye.enabled then
        local b, w = Health.curveAt(cfg.eye, Health.nowMinute())
        eye_sub = Health.hasWarmth() and t("eye_row_on", round(b), round(w)) or t("eye_row_on_nowarm", round(b))
    else
        eye_sub = t("eye_row_off")
    end
    local read_today, on_today = Health.dayTotals(0)

    return {
        { section = t("sec_eye"), title = t("eye_row_title"), subtitle = eye_sub, icon = "display",
            show_state = false, callback = open("eye") },
        { section = t("sec_stats"), title = t("stats_row_title"),
            subtitle = t("stats_row_sub", Health.formatDuration(read_today), Health.formatDuration(on_today)),
            icon = "timer", show_state = false, callback = open("stats") },
        { section = t("sec_stats"), title = t("stats_toggle_title"),
            subtitle = cfg.stats.enabled and t("stats_toggle_on") or t("stats_toggle_off"),
            icon = "timer", enabled = cfg.stats.enabled,
            callback = function()
                cfg.stats.enabled = not cfg.stats.enabled
                save(appdock)
                rebuild()
            end },
        { section = t("sec_care"), title = t("break_row_title"),
            subtitle = cfg.breaks.enabled and t("break_row_on", cfg.breaks.interval, cfg.breaks.length) or t("off"),
            icon = "bookmark", show_state = false, callback = open("care") },
        { section = t("sec_care"), title = t("bed_row_title"),
            subtitle = cfg.bed.enabled and t("bed_row_on", Health.formatClock(cfg.bed.time),
                cfg.bed.lead > 0 and t("minutes", cfg.bed.lead) or t("off")) or t("off"),
            icon = "analog_clock", show_state = false, callback = open("care") },
    }
end

---------------------------------------------------------------------------
-- Screens (built on the setup assistant's card helpers)
---------------------------------------------------------------------------

local screen_class

local function getScreenClass()
    if screen_class then return screen_class end
    local Blitbuffer = require("ffi/blitbuffer")
    local Geom = require("ui/geometry")
    local GestureRange = require("ui/gesturerange")
    local Font = require("ui/font")
    local TextWidget = require("ui/widget/textwidget")
    local Setup = require("appdock_setup")
    local SetupScreen = Setup._test.SetupScreen
    local Screen = Device.screen
    local function px(n) return Screen:scaleBySize(n) end

    local function rgb(r, g, b, fallback)
        if type(Blitbuffer.ColorRGB32) == "function" then
            local ok, value = pcall(Blitbuffer.ColorRGB32, r, g, b, 0xFF)
            if ok and value then return value end
        end
        return fallback
    end

    local HealthScreen = SetupScreen:extend{
        appdock = nil, context = nil, on_close = nil, covers_fullscreen = true,
    }

    function HealthScreen:init()
        self.dimen = Screen:getSize()
        local settings = self.appdock and self.appdock.settings or {}
        local accessibility = type(settings.accessibility) == "table" and settings.accessibility or {}
        self.lang = Health.lang(self.appdock)
        self.text_scale = math.max(1, math.min(1.3, tonumber(accessibility.text_scale) or 1))
        self.page = self.page or "eye"
        self.series = "b"
        self.sel = 2
        self.history = {}
        self.ges_events = { TapSetup = { GestureRange:new{ ges = "tap", range = self.dimen } } }
        if Device.hasKeys and Device:hasKeys() and Device.input and Device.input.group
            and Device.input.group.Back then
            self.key_events = { SetupBack = { Device.input.group.Back } }
        end
        self:build()
    end

    function HealthScreen:t(key, ...) return Health.t(self.appdock, key, ...) end
    function HealthScreen:_dots() end

    function HealthScreen:close()
        if self._closed then return end
        self._closed = true
        UIManager:close(self)
        if self.on_close then UIManager:nextTick(self.on_close) end
    end

    function HealthScreen:onSetupBack() self:close(); return true end
    function HealthScreen:goBack() self:close(); return true end

    -- Taps pass their position so the chart can be used as a slider.
    function HealthScreen:onTapSetup(_, gesture)
        local pos = gesture and gesture.pos
        if not pos then return true end
        for index = #self.hits, 1, -1 do
            local hit = self.hits[index]
            if pos.x >= hit.x and pos.x < hit.x + hit.w and pos.y >= hit.y and pos.y < hit.y + hit.h then
                hit.fn(pos)
                return true
            end
        end
        return true
    end

    -- self.c is created by SetupScreen:build() before the page builders run;
    -- the warm tones are added to it on first use.
    local function colours(self)
        local c = self.c
        if not c.warm then
            c.warm = rgb(230, 126, 34, c.accent)
            c.warm_off = rgb(250, 219, 190, c.accent_off)
        end
        return c
    end

    function HealthScreen:_textRight(text, y, size, colour, bold, x, w)
        local widget = TextWidget:new{
            text = text, face = self:_font(size, bold), fgcolor = colour, bold = bold, max_width = w, padding = 0,
        }
        local width = w
        local ok, dims = pcall(widget.getSize, widget)
        if ok and type(dims) == "table" and dims.w then width = math.min(dims.w, w) end
        widget.overlap_offset = { x + w - width, y }
        self.layers[#self.layers + 1] = widget
        return ok and dims.h or px(size)
    end

    function HealthScreen:_chip(label, x, y, w, selected, fn, colour)
        local c = colours(self)
        colour = colour or c.accent
        local h = math.floor(px(34) * math.min(self.text_scale, 1.15))
        local text = TextWidget:new{
            text = label, face = self:_font(11, true), fgcolor = selected and c.on_accent or colour,
            bold = true, max_width = w - px(8), padding = 0,
        }
        self:_box(x, y, w, h, {
            fill = selected and colour or c.bg, border = math.max(1, px(1)), color = colour,
            radius = math.floor(h / 2), child = text,
        })
        if fn then self:_hit(x, y, w, h, fn) end
        return h
    end

    --- Row of equally wide chips; entries: { label, selected, fn, colour }.
    function HealthScreen:_chipRow(y, entries)
        local gap = px(6)
        local w = math.floor((self.cw - gap * (#entries - 1)) / #entries)
        local h = 0
        for index, entry in ipairs(entries) do
            h = self:_chip(entry.label, self.cx + (index - 1) * (w + gap), y, w, entry.selected, entry.fn, entry.colour)
        end
        return h
    end

    function HealthScreen:_switch(y, label, sub, on, fn)
        local c = colours(self)
        local h = math.floor(px(46) * math.min(self.text_scale, 1.2))
        local sw, sh = px(46), px(26)
        local text_w = self.cw - sw - px(14)
        local label_h = self:_text(label, y + px(4), 14, c.ink, false, "left", self.cx, text_w)
        if sub then self:_text(sub, y + px(4) + label_h, 10, c.muted, false, "left", self.cx, text_w) end
        local sx, sy = self.cx + self.cw - sw, y + math.floor((h - sh) / 2)
        self:_box(sx, sy, sw, sh, { fill = on and c.accent or c.accent_off, radius = math.floor(sh / 2) })
        local knob = sh - px(6)
        self:_box(on and (sx + sw - knob - px(3)) or (sx + px(3)), sy + px(3), knob, knob,
            { fill = c.on_accent, radius = math.floor(knob / 2) })
        self:_hit(self.cx, y, self.cw, h, fn)
        return h
    end

    function HealthScreen:_stepper(y, label, value, minus, plus)
        local c = colours(self)
        local h = math.floor(px(44) * math.min(self.text_scale, 1.2))
        local button, value_w = px(38), px(76)
        local right = button * 2 + value_w
        self:_text(label, y + math.floor((h - px(16)) / 2), 13, c.ink, false, "left", self.cx, self.cw - right - px(8))
        local x = self.cx + self.cw - right
        local function square(sx, glyph, fn)
            local text = TextWidget:new{ text = glyph, face = self:_font(16, true), fgcolor = c.accent, bold = true, padding = 0 }
            self:_box(sx, y + math.floor((h - button) / 2), button, button, {
                border = math.max(1, px(1)), color = c.accent, radius = px(8), fill = c.bg, child = text,
            })
            self:_hit(sx - px(2), y, button + px(4), h, fn)
        end
        square(x, "−", minus)
        self:_text(value, y + math.floor((h - px(16)) / 2), 13, c.ink, true, "center", x + button, value_w)
        square(x + button + value_w, "+", plus)
        return h
    end

    function HealthScreen:_section(y, label)
        local c = colours(self)
        local h = self:_text(label, y, 12, c.accent, true, "left")
        self:_divider(y + h + px(4))
        return h + px(10)
    end

    function HealthScreen:_title(y, title, sub)
        local c = colours(self)
        y = y + self:_text(title, y, 22, c.ink, true, "left") + px(4)
        if sub then y = y + self:_para(sub, y, 10, c.muted, "left") + px(4) end
        return y
    end

    -- Eye protection ----------------------------------------------------

    function HealthScreen:_applyLive()
        local eye = Health.config(self.appdock).eye
        if eye.enabled then Health.applyEye(self.appdock, true) end
    end

    function HealthScreen:_chartTap(geo, pos)
        local eye = Health.config(self.appdock).eye
        local minute = clamp((pos.x - geo.ix) / geo.iw * 1440, 0, 1439)
        local value = clamp((geo.iy + geo.ih - pos.y) / geo.ih * 100, 0, 100)
        Health.setAnchor(self.appdock, self.sel, math.floor(minute / 15 + 0.5) * 15, self.series, math.floor(value / 5 + 0.5) * 5)
        self:_applyLive()
        self:refresh()
        return eye
    end

    function HealthScreen:_drawChart(y, h)
        local c = colours(self)
        local eye = Health.config(self.appdock).eye
        local pad = px(6)
        local geo = { ix = self.cx + pad, iy = y + pad, iw = self.cw - 2 * pad, ih = h - 2 * pad }
        local series, other = self.series, self.series == "b" and "w" or "b"
        local main_fill = series == "b" and c.accent_off or c.warm_off
        local main_dark = series == "b" and c.accent or c.warm

        self:_box(self.cx, y, self.cw, h, { border = math.max(1, px(1)), color = c.border, radius = px(6), fill = c.bg })
        self:_hit(self.cx, y, self.cw, h, function(pos) self:_chartTap(geo, pos) end)

        local cols = 24
        local col_w = geo.iw / cols
        for index = 0, cols - 1 do
            local b, w = Health.curveAt(eye, index * 60 + 30)
            local main_value = series == "b" and b or w
            local other_value = other == "b" and b or w
            local bar_h = math.max(px(2), math.floor(main_value / 100 * geo.ih))
            local bar_x = math.floor(geo.ix + index * col_w + px(1))
            local bar_w = math.max(px(2), math.floor(col_w - px(2)))
            self:_box(bar_x, geo.iy + geo.ih - bar_h, bar_w, bar_h, { fill = main_fill })
            local dot = px(5)
            local dot_y = geo.iy + geo.ih - math.floor(other_value / 100 * geo.ih) - math.floor(dot / 2)
            self:_box(bar_x + math.floor((bar_w - dot) / 2), clamp(dot_y, geo.iy, geo.iy + geo.ih - dot), dot, dot,
                { fill = c.ink, radius = math.floor(dot / 2) })
        end

        local now_x = math.floor(geo.ix + Health.nowMinute() / 1440 * geo.iw)
        self:_box(now_x, geo.iy, math.max(1, px(2)), geo.ih, { fill = c.muted })

        for index, point in ipairs(eye.points) do
            local value = series == "b" and point.b or point.w
            local size = px(24)
            local cx = math.floor(geo.ix + point.t / 1440 * geo.iw)
            local cy = math.floor(geo.iy + geo.ih - value / 100 * geo.ih)
            cx = clamp(cx, self.cx + math.floor(size / 2), self.cx + self.cw - math.floor(size / 2))
            cy = clamp(cy, y + math.floor(size / 2), y + h - math.floor(size / 2))
            local selected = index == self.sel
            local text = TextWidget:new{
                text = tostring(index), face = self:_font(10, true), bold = true, padding = 0,
                fgcolor = selected and c.on_accent or main_dark,
            }
            self:_box(cx - math.floor(size / 2), cy - math.floor(size / 2), size, size, {
                fill = selected and main_dark or c.bg, border = math.max(1, px(2)), color = main_dark,
                radius = math.floor(size / 2), child = text,
            })
            local hit = px(44)
            self:_hit(cx - math.floor(hit / 2), cy - math.floor(hit / 2), hit, hit, function()
                self.sel = index
                self:refresh()
            end)
        end

        local label_y = y + h + px(2)
        local label_w = px(30)
        for _, hour in ipairs({ 0, 6, 12, 18, 24 }) do
            local lx = math.floor(geo.ix + hour / 24 * geo.iw - label_w / 2)
            lx = clamp(lx, self.cx, self.cx + self.cw - label_w)
            self:_text(tostring(hour), label_y, 9, c.muted, false, "center", lx, label_w)
        end
        return h + px(18)
    end

    function HealthScreen:_page_eye()
        local c = colours(self)
        local appdock = self.appdock
        local cfg = Health.config(appdock)
        local eye = cfg.eye
        local has_light, has_warm = Health.hasFrontlight(), Health.hasWarmth()
        if not has_warm then self.series = "b" end

        local y = self:_title(self.top, self:t("eye_title"), self:t("eye_sub")) + px(2)
        y = y + self:_switch(y, self:t("auto"), eye.enabled and self:t("auto_sub_on") or self:t("auto_sub_off"), eye.enabled,
            function()
                Health.setEyeEnabled(appdock, not eye.enabled)
                self:refresh()
            end) + px(4)
        if not has_light then
            y = y + self:_para(self:t("no_light"), y, 10, c.muted, "left") + px(4)
        elseif not has_warm then
            y = y + self:_para(self:t("no_warm"), y, 10, c.muted, "left") + px(4)
        end

        if has_warm then
            y = y + self:_chipRow(y, {
                { label = "☼ " .. self:t("tab_b"), selected = self.series == "b",
                    fn = function() self.series = "b"; self:refresh() end },
                { label = "◐ " .. self:t("tab_w"), selected = self.series == "w", colour = c.warm,
                    fn = function() self.series = "w"; self:refresh() end },
            }) + px(8)
        end

        local chart_h = math.max(px(96), math.min(px(150), math.floor(self.h * 0.19)))
        y = y + self:_drawChart(y, chart_h) + px(6)

        local anchors = {}
        for index, id in ipairs(ANCHOR_IDS) do
            anchors[index] = { label = index .. " " .. self:t(id), selected = index == self.sel,
                fn = function() self.sel = index; self:refresh() end }
        end
        y = y + self:_chipRow(y, anchors) + px(8)

        local point = eye.points[self.sel]
        local key = self.series
        local readout = string.format("%s · %s · %s %d %%", self:t(ANCHOR_IDS[self.sel]), Health.formatClock(point.t),
            self:t(key == "b" and "tab_b" or "tab_w"), point[key])
        y = y + self:_text(readout, y, 12, c.ink, true, "center") + px(6)

        local function nudge(t_delta, v_delta)
            return function()
                local p = eye.points[self.sel]
                Health.setAnchor(appdock, self.sel, t_delta and (p.t + t_delta) or nil, v_delta and key or nil,
                    v_delta and (p[key] + v_delta) or nil)
                self:_applyLive()
                self:refresh()
            end
        end
        y = y + self:_chipRow(y, {
            { label = "− 5 %", fn = nudge(nil, -5) }, { label = "+ 5 %", fn = nudge(nil, 5) },
            { label = "− 15 min", fn = nudge(-15, nil) }, { label = "+ 15 min", fn = nudge(15, nil) },
        }) + px(10)

        y = y + self:_text(self:t("presets"), y, 10, c.muted, true, "left") + px(3)
        local presets = {}
        for _, id in ipairs(Health.PRESET_IDS) do
            presets[#presets + 1] = { label = self:t("p_" .. id), fn = function()
                Health.applyPreset(appdock, id)
                self:_applyLive()
                self:refresh()
            end }
        end
        y = y + self:_chipRow(y, presets) + px(8)

        local b, w = Health.curveAt(eye, Health.nowMinute())
        local now_text = has_warm and self:t("now_line", Health.formatClock(Health.nowMinute()), round(b), round(w))
            or self:t("now_line_nowarm", Health.formatClock(Health.nowMinute()), round(b))
        self:_text(now_text, y, 10, c.muted, false, "center")

        self:_footer(nil, { label = self:t("done"), fn = function() self:close() end })
    end

    -- Statistics --------------------------------------------------------

    function HealthScreen:_tile(x, y, w, h, label, value)
        local c = colours(self)
        self:_box(x, y, w, h, { border = math.max(1, px(1)), color = c.border, radius = px(8), fill = c.bg })
        self:_text(label, y + px(8), 10, c.muted, false, "center", x, w)
        self:_text(value, y + px(26), 18, c.ink, true, "center", x, w)
    end

    function HealthScreen:_page_stats()
        local c = colours(self)
        local appdock = self.appdock
        local cfg = Health.config(appdock)
        local stats = Health.getStats()

        local y = self:_title(self.top, self:t("stats_title"))
        y = y + self:_switch(y, self:t("record"), nil, cfg.stats.enabled, function()
            cfg.stats.enabled = not cfg.stats.enabled
            save(appdock)
            self:refresh()
        end) + px(6)

        local read_today, on_today = Health.dayTotals(0)
        y = y + self:_text(self:t("today"), y, 10, c.muted, true, "left") + px(4)
        local gap = px(10)
        local tile_w, tile_h = math.floor((self.cw - gap) / 2), px(58)
        self:_tile(self.cx, y, tile_w, tile_h, self:t("reading"), Health.formatDuration(read_today))
        self:_tile(self.cx + tile_w + gap, y, tile_w, tile_h, self:t("on_time"), Health.formatDuration(on_today))
        y = y + tile_h + px(14)

        y = y + self:_text(self:t("last7"), y, 10, c.muted, true, "left") + px(4)
        local chart_h = math.max(px(80), math.min(px(130), math.floor(self.h * 0.17)))
        self:_box(self.cx, y, self.cw, chart_h, { border = math.max(1, px(1)), color = c.border, radius = px(6), fill = c.bg })
        local days, max_on = {}, 1
        for offset = 6, 0, -1 do
            local r, o, wday = Health.dayTotals(offset)
            days[#days + 1] = { read = r, on = math.max(o, r), wday = wday }
            max_on = math.max(max_on, o, r)
        end
        local pad = px(8)
        local col_w = (self.cw - 2 * pad) / 7
        local inner_h = chart_h - 2 * pad
        local weekdays = self:t("weekdays")
        for index, day in ipairs(days) do
            local x = self.cx + pad + (index - 1) * col_w
            local bar_w = math.max(px(6), math.floor(col_w * 0.6))
            local bx = math.floor(x + (col_w - bar_w) / 2)
            local on_h = day.on > 0 and math.max(px(3), math.floor(day.on / max_on * inner_h)) or 0
            local read_h = day.read > 0 and math.max(px(3), math.floor(day.read / max_on * inner_h)) or 0
            if on_h > 0 then self:_box(bx, y + pad + inner_h - on_h, bar_w, on_h, { fill = c.accent_off }) end
            if read_h > 0 then
                local narrow = math.max(px(4), math.floor(bar_w * 0.55))
                self:_box(bx + math.floor((bar_w - narrow) / 2), y + pad + inner_h - read_h, narrow, read_h, { fill = c.accent })
            end
            self:_text(weekdays[day.wday] or "", y + chart_h + px(2), 9, c.muted, false, "center", math.floor(x), math.floor(col_w))
        end
        y = y + chart_h + px(20)
        y = y + self:_text(self:t("legend"), y, 9, c.muted, false, "center") + px(10)

        local avg_read, avg_on = Health.weekAverages()
        local function line(label, value)
            self:_text(label, y, 12, c.ink, false, "left", self.cx, math.floor(self.cw * 0.6))
            self:_textRight(value, y, 12, c.ink, true, self.cx + math.floor(self.cw * 0.5), math.floor(self.cw * 0.5))
            y = y + px(24)
            self:_divider(y - px(4))
        end
        line(self:t("avg") .. " · " .. self:t("reading"), Health.formatDuration(avg_read))
        line(self:t("avg") .. " · " .. self:t("on_time"), Health.formatDuration(avg_on))
        line(self:t("total") .. " · " .. self:t("reading"), Health.formatDuration(stats.total_read))
        line(self:t("total") .. " · " .. self:t("on_time"), Health.formatDuration(stats.total_on))
        line(self:t("streak"), self:t("days", Health.streak()))
        y = y + px(6)

        self:_link(self:t("reset"), nil, y, "center", function()
            local ok, Dialogs = pcall(require, "appdock_dialogs")
            local ConfirmBox = ok and Dialogs.ConfirmBox or require("ui/widget/confirmbox")
            UIManager:show(ConfirmBox:new{
                text = self:t("reset_confirm"), ok_text = self:t("delete"), cancel_text = self:t("cancel"),
                ok_callback = function() Health.resetStats(); self:refresh() end,
            })
        end)
        self:_footer(nil, { label = self:t("done"), fn = function() self:close() end })
    end

    -- Health (reminders) --------------------------------------------------

    function HealthScreen:_page_care()
        local c = colours(self)
        local appdock = self.appdock
        local cfg = Health.config(appdock)
        local function change(fn) return function() fn(); save(appdock); self:refresh() end end

        local y = self:_title(self.top, self:t("care_title"))
        y = y + self:_section(y, self:t("break_sec"))
        y = y + self:_switch(y, self:t("break_toggle"), nil, cfg.breaks.enabled,
            change(function() cfg.breaks.enabled = not cfg.breaks.enabled end))
        if cfg.breaks.enabled then
            y = y + self:_stepper(y, self:t("break_every"), self:t("minutes", cfg.breaks.interval),
                change(function() cfg.breaks.interval = clamp(cfg.breaks.interval - 5, 10, 120) end),
                change(function() cfg.breaks.interval = clamp(cfg.breaks.interval + 5, 10, 120) end))
            y = y + self:_stepper(y, self:t("break_len"), self:t("minutes", cfg.breaks.length),
                change(function() cfg.breaks.length = clamp(cfg.breaks.length - 1, 1, 30) end),
                change(function() cfg.breaks.length = clamp(cfg.breaks.length + 1, 1, 30) end))
        end
        y = y + px(12)

        y = y + self:_section(y, self:t("bed_sec"))
        y = y + self:_switch(y, self:t("bed_toggle"), nil, cfg.bed.enabled,
            change(function() cfg.bed.enabled = not cfg.bed.enabled end))
        if cfg.bed.enabled then
            y = y + self:_stepper(y, self:t("bed_at"), Health.formatClock(cfg.bed.time),
                change(function() cfg.bed.time = (cfg.bed.time - 15) % 1440 end),
                change(function() cfg.bed.time = (cfg.bed.time + 15) % 1440 end))
            y = y + self:_stepper(y, self:t("bed_lead"), cfg.bed.lead > 0 and self:t("minutes", cfg.bed.lead) or self:t("off"),
                change(function() cfg.bed.lead = clamp(cfg.bed.lead - 5, 0, 60) end),
                change(function() cfg.bed.lead = clamp(cfg.bed.lead + 5, 0, 60) end))
        end
        y = y + px(14)

        self:_link(self:t("test"), nil, y, "center", function()
            if cfg.bed.enabled and not cfg.breaks.enabled then
                Health.showBedReminder(appdock, nil, cfg.bed.lead > 0 and cfg.bed.lead or nil)
            else
                Health.showBreakReminder(appdock, nil)
            end
        end)
        self:_footer(nil, { label = self:t("done"), fn = function() self:close() end })
    end

    screen_class = HealthScreen
    return HealthScreen
end

--- Opens one of the pages: "eye", "stats" or "care".
function Health.show(appdock, context, page)
    local ok, HealthScreen = pcall(getScreenClass)
    if not ok then
        local logger_ok, logger = pcall(require, "logger")
        if logger_ok then logger.warn("AppDock health screen unavailable:", HealthScreen) end
        return false
    end
    local screen = HealthScreen:new{
        appdock = appdock, context = context, page = page or "eye",
        on_close = function()
            if context and context.requestRebuild then context.requestRebuild("ui") end
        end,
    }
    UIManager:show(screen)
    return true
end

Health._test = { clamp = clamp, defaultPoints = defaultPoints, loadStats = loadStats }

return Health
