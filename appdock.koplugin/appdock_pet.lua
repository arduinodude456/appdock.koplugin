--[[--
AppDock pet (Funktionen > Haustier).

A small digital companion whose well-being follows how much and how often the
reader reads:

  * Today's reading time feeds it (daily goal: GOAL_MINUTES).
  * Reading on many of the last 7 days keeps it happy (frequency).
  * Total reading time lets it grow: level, and stage baby / young / adult.
  * It never dies. Without reading it only gets hungry, then sad and sleepy.

Only the reading seconds per calendar day are stored (settings.features.pet),
nothing else about the person. Time is counted while a KOReader book is open
(fed by appdock_health's ticker) and while DReader is on screen.

The sprites are generated from a few shapes (ellipses, triangles) with an
automatic outline, so there are no image assets to ship. Pixels are painted as
horizontal runs, which stays cheap and crisp on E-Ink.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local Color = require("appdock_color")
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")

local Screen = Device.screen

local Pet = {}
Pet._normalized = setmetatable({}, { __mode = "k" })

Pet.SPECIES = { "cat", "dog", "fox", "owl", "bunny" }
Pet.PLACES = { "home", "dreader", "everywhere" }

local GOAL_MINUTES = 20          -- reading per day that makes the pet full
local ACTIVE_DAY_SECONDS = 300   -- a day counts as "read" from 5 minutes on
local KEEP_DAYS = 60
local FLUSH_SECONDS = 300
local GRID = 20                  -- sprite grid is GRID x GRID cells

Pet.GOAL_MINUTES = GOAL_MINUTES

---------------------------------------------------------------------------
-- Text (German / English)
---------------------------------------------------------------------------

local STRINGS = {
    en = {
        cat = "Cat", dog = "Dog", fox = "Fox", owl = "Owl", bunny = "Bunny",
        default_name_cat = "Mochi", default_name_dog = "Biscuit", default_name_fox = "Rusty",
        default_name_owl = "Hoot", default_name_bunny = "Clover",
        mood_happy = "happy", mood_content = "content", mood_hungry = "hungry for a story",
        mood_sad = "lonely", mood_sleepy = "sleeping",
        stage_baby = "baby", stage_young = "young", stage_adult = "grown-up",
        say_happy = "Great reading today!", say_content = "Nice. A few more pages?",
        say_hungry = "Read something with me?", say_sad = "I missed you.",
        say_sleepy = "Zzz…",
        status_title = "%s the %s",
        status_body = "Level %d · %s · %s\nToday: %d / %d min of reading\nLast 7 days: %d of 7 days read\nReading streak: %d day(s)\nTotal: %s",
        status_next = "Next level in about %s of reading.",
        status_max = "Highest level reached.",
        hours_fmt = "%.1f h", min_fmt = "%d min",
    },
    de = {
        cat = "Katze", dog = "Hund", fox = "Fuchs", owl = "Eule", bunny = "Hase",
        default_name_cat = "Mochi", default_name_dog = "Keks", default_name_fox = "Rusty",
        default_name_owl = "Uhu", default_name_bunny = "Klee",
        mood_happy = "glücklich", mood_content = "zufrieden", mood_hungry = "hungrig nach Geschichten",
        mood_sad = "einsam", mood_sleepy = "schläft",
        stage_baby = "Baby", stage_young = "Jungtier", stage_adult = "erwachsen",
        say_happy = "Toll gelesen heute!", say_content = "Schön. Noch ein paar Seiten?",
        say_hungry = "Liest du mit mir?", say_sad = "Ich hab dich vermisst.",
        say_sleepy = "Zzz…",
        status_title = "%s (%s)",
        status_body = "Level %d · %s · %s\nHeute: %d / %d Min. gelesen\nLetzte 7 Tage: an %d von 7 Tagen gelesen\nLese-Serie: %d Tag(e)\nGesamt: %s",
        status_next = "Nächstes Level in etwa %s Lesezeit.",
        status_max = "Höchstes Level erreicht.",
        hours_fmt = "%.1f Std.", min_fmt = "%d Min.",
    },
}
Pet.STRINGS = STRINGS

local function lang(appdock)
    local settings = appdock and appdock.settings or {}
    return settings.language == "de" and "de" or "en"
end

function Pet.t(appdock, key, ...)
    local tbl = STRINGS[lang(appdock)] or STRINGS.en
    local text = tbl[key]
    if text == nil then text = STRINGS.en[key] end
    if text == nil then return key end
    if select("#", ...) > 0 and type(text) == "string" then return string.format(text, ...) end
    return text
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local function clamp(value, low, high) return math.max(low, math.min(high, value)) end

local function dayKey(timestamp) return os.date("%Y-%m-%d", timestamp or os.time()) end

local function noon(offset_days)
    local d = os.date("*t")
    return os.time{ year = d.year, month = d.month, day = d.day, hour = 12 } - (offset_days or 0) * 86400
end

local function validSpecies(species)
    for _, id in ipairs(Pet.SPECIES) do
        if id == species then return species end
    end
    return "cat"
end

local function validPlace(place)
    for _, id in ipairs(Pet.PLACES) do
        if id == place then return place end
    end
    return "home"
end

--- Normalizes a stored pet table (also used by appdock_features).
function Pet.normalize(stored)
    stored = type(stored) == "table" and stored or {}
    local days = {}
    if type(stored.days) == "table" then
        for key, seconds in pairs(stored.days) do
            if type(key) == "string" and key:match("^%d%d%d%d%-%d%d%-%d%d$") and tonumber(seconds) then
                days[key] = math.max(0, math.floor(tonumber(seconds)))
            end
        end
    end
    local name = type(stored.name) == "string" and stored.name:gsub("[%c]", ""):sub(1, 16) or ""
    return {
        enabled = stored.enabled == true,
        species = validSpecies(stored.species),
        name = name,
        place = validPlace(stored.place),
        adopted = math.max(0, math.floor(tonumber(stored.adopted) or 0)),
        total = math.max(0, math.floor(tonumber(stored.total) or 0)),
        days = days,
    }
end

--- The live pet table of an AppDock instance (normalized once).
function Pet.config(appdock)
    local settings = appdock.settings
    settings.features = type(settings.features) == "table" and settings.features or {}
    local features = settings.features
    if not Pet._normalized[features] then
        features.pet = Pet.normalize(features.pet)
        Pet._normalized[features] = true
    end
    return features.pet
end

function Pet.isEnabled(appdock)
    return appdock ~= nil and appdock.settings ~= nil and Pet.config(appdock).enabled == true
end

--- Whether the pet is shown at `where`: "home", "dreader" or "app".
function Pet.shownAt(appdock, where, dapp_id)
    if not Pet.isEnabled(appdock) then return false end
    local place = Pet.config(appdock).place
    if where == "home" then return true end
    if where == "app" then
        if place == "everywhere" then return true end
        return place == "dreader" and dapp_id == "dreader"
    end
    return false
end

function Pet.displayName(appdock)
    local cfg = Pet.config(appdock)
    if cfg.name ~= "" then return cfg.name end
    return Pet.t(appdock, "default_name_" .. cfg.species)
end

local function save(appdock)
    if appdock and type(appdock._saveSettings) == "function" then pcall(appdock._saveSettings, appdock) end
end

function Pet.setEnabled(appdock, enabled)
    local cfg = Pet.config(appdock)
    cfg.enabled = enabled == true
    if cfg.enabled and cfg.adopted == 0 then cfg.adopted = os.time() end
    save(appdock)
end

function Pet.setSpecies(appdock, species)
    Pet.config(appdock).species = validSpecies(species)
    save(appdock)
end

function Pet.setPlace(appdock, place)
    Pet.config(appdock).place = validPlace(place)
    save(appdock)
end

function Pet.setName(appdock, name)
    local clean = type(name) == "string" and name:gsub("[%c]", ""):gsub("^%s+", ""):gsub("%s+$", ""):sub(1, 16) or ""
    Pet.config(appdock).name = clean
    save(appdock)
end

--- Called by the reading ticker. Counts seconds for today and for the total.
function Pet.addReading(appdock, seconds)
    if not Pet.isEnabled(appdock) or type(seconds) ~= "number" or seconds <= 0 then return end
    local cfg = Pet.config(appdock)
    local key = dayKey()
    cfg.days[key] = (cfg.days[key] or 0) + seconds
    cfg.total = cfg.total + seconds
    Pet._dirty = true
    -- Old days are dropped rarely; two months of history are plenty.
    local count = 0
    for _ in pairs(cfg.days) do count = count + 1 end
    if count > KEEP_DAYS + 20 then
        local keys = {}
        for k in pairs(cfg.days) do keys[#keys + 1] = k end
        table.sort(keys)
        for index = 1, #keys - KEEP_DAYS do cfg.days[keys[index]] = nil end
    end
    local now = os.time()
    if not Pet._last_flush or now - Pet._last_flush >= FLUSH_SECONDS then Pet.flush(appdock) end
end

--- Writes pending reading time to the settings file (cheap when nothing changed).
function Pet.flush(appdock)
    if not Pet._dirty then return end
    Pet._dirty = false
    Pet._last_flush = os.time()
    save(appdock)
end

--- True while the person is reading in DReader (its window is the top widget).
function Pet.inDReader()
    local ok, top = pcall(function() return UIManager:getTopmostVisibleWidget() end)
    if not ok or type(top) ~= "table" then return false end
    for _, id in ipairs(top.dapp_ids or {}) do
        if id == "dreader" then return true end
    end
    return false
end

local function secondsOn(cfg, offset)
    return cfg.days[dayKey(noon(offset))] or 0
end

--- Mood, growth and figures, computed from the reading log only.
function Pet.status(appdock, now_hour)
    local cfg = Pet.config(appdock)
    local today = secondsOn(cfg, 0)
    local goal = GOAL_MINUTES * 60
    local fullness = clamp(today / goal, 0, 1)

    local active_days, since_read = 0, nil
    for offset = 0, 6 do
        if secondsOn(cfg, offset) >= ACTIVE_DAY_SECONDS then
            active_days = active_days + 1
            if since_read == nil then since_read = offset end
        end
    end
    if since_read == nil then
        since_read = 7
        for offset = 7, KEEP_DAYS do
            if secondsOn(cfg, offset) >= ACTIVE_DAY_SECONDS then since_read = offset; break end
        end
        if since_read == 7 and not next(cfg.days) then since_read = 1 end
    end

    local streak, start = 0, (today < ACTIVE_DAY_SECONDS) and 1 or 0
    for offset = start, KEEP_DAYS do
        if secondsOn(cfg, offset) >= ACTIVE_DAY_SECONDS then streak = streak + 1 else break end
    end

    local happiness = clamp(math.floor(active_days / 7 * 70 + fullness * 30 + 0.5), 0, 100)
    if since_read >= 3 then happiness = math.min(happiness, 25) end

    local hour = now_hour or tonumber(os.date("%H")) or 12
    local mood
    if hour >= 23 or hour < 6 then
        mood = "sleepy"
    elseif fullness >= 1 or (today >= ACTIVE_DAY_SECONDS and happiness >= 70) then
        mood = "happy"
    elseif today >= ACTIVE_DAY_SECONDS or happiness >= 45 then
        mood = "content"
    elseif since_read >= 2 then
        mood = "sad"
    elseif hour >= 12 then
        mood = "hungry"
    else
        mood = "content"
    end

    local hours = cfg.total / 3600
    local level = clamp(math.floor(math.sqrt(hours * 2)) + 1, 1, 99)
    local stage = level < 3 and "baby" or (level < 6 and "young" or "adult")
    local next_hours = ((level) ^ 2) / 2
    local to_next = level >= 99 and nil or math.max(0, next_hours - hours) * 3600

    return {
        mood = mood, happiness = happiness, fullness = fullness,
        level = level, stage = stage, streak = streak,
        today_min = math.floor(today / 60), active_days = active_days,
        total_seconds = cfg.total, to_next_seconds = to_next, since_read = since_read,
    }
end

local function formatDuration(appdock, seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    if seconds >= 3600 then return Pet.t(appdock, "hours_fmt", seconds / 3600) end
    return Pet.t(appdock, "min_fmt", math.max(1, math.floor(seconds / 60)))
end

function Pet.statusText(appdock)
    local cfg = Pet.config(appdock)
    local s = Pet.status(appdock)
    local title = Pet.t(appdock, "status_title", Pet.displayName(appdock), Pet.t(appdock, cfg.species))
    local body = Pet.t(appdock, "status_body", s.level, Pet.t(appdock, "stage_" .. s.stage),
        Pet.t(appdock, "mood_" .. s.mood), s.today_min, GOAL_MINUTES, s.active_days, s.streak,
        formatDuration(appdock, s.total_seconds))
    local next_line = s.to_next_seconds and Pet.t(appdock, "status_next", formatDuration(appdock, s.to_next_seconds))
        or Pet.t(appdock, "status_max")
    return title, body .. "\n\n" .. next_line, s
end

function Pet.say(appdock)
    return Pet.t(appdock, "say_" .. Pet.status(appdock).mood)
end

---------------------------------------------------------------------------
-- Sprites
---------------------------------------------------------------------------

-- Palette letters: B body, L light, D dark accent, P pink, W white, O orange,
-- R scarf red, K outline/eyes. Values are RGB; monochrome panels get the luma.
local PALETTES = {
    cat   = { B = {236, 160, 84}, L = {252, 232, 196}, D = {190, 110, 52}, P = {240, 140, 156}, K = {58, 40, 36} },
    dog   = { B = {196, 146, 98}, L = {246, 226, 196}, D = {128, 84, 54}, P = {236, 140, 150}, K = {58, 40, 36} },
    fox   = { B = {228, 108, 44}, L = {255, 246, 236}, D = {96, 56, 44}, P = {236, 140, 150}, K = {58, 40, 36} },
    owl   = { B = {160, 124, 92}, L = {238, 220, 186}, D = {110, 80, 58}, P = {236, 140, 150},
              W = {255, 255, 255}, O = {240, 170, 60}, K = {58, 40, 36} },
    bunny = { B = {240, 238, 244}, L = {255, 255, 255}, D = {200, 196, 208}, P = {246, 160, 180}, K = {70, 56, 70} },
}

local function newGrid()
    local grid = {}
    for y = 1, GRID do
        grid[y] = {}
        for x = 1, GRID do grid[y][x] = false end
    end
    return grid
end

local function put(grid, x, y, ch)
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
    if x >= 1 and x <= GRID and y >= 1 and y <= GRID then grid[y][x] = ch end
end

local function ellipse(grid, cx, cy, rx, ry, ch)
    for y = math.floor(cy - ry), math.ceil(cy + ry) do
        for x = math.floor(cx - rx), math.ceil(cx + rx) do
            local dx, dy = (x - cx) / rx, (y - cy) / ry
            if dx * dx + dy * dy <= 1.0 then put(grid, x, y, ch) end
        end
    end
end

local function rect(grid, x0, y0, x1, y1, ch)
    for y = y0, y1 do for x = x0, x1 do put(grid, x, y, ch) end end
end

local function sign(px, py, ax, ay, bx, by) return (px - bx) * (ay - by) - (ax - bx) * (py - by) end

local function triangle(grid, ax, ay, bx, by, cx, cy, ch)
    local min_x, max_x = math.floor(math.min(ax, bx, cx)), math.ceil(math.max(ax, bx, cx))
    local min_y, max_y = math.floor(math.min(ay, by, cy)), math.ceil(math.max(ay, by, cy))
    for y = min_y, max_y do
        for x = min_x, max_x do
            local d1, d2, d3 = sign(x, y, ax, ay, bx, by), sign(x, y, bx, by, cx, cy), sign(x, y, cx, cy, ax, ay)
            local has_neg = d1 < 0 or d2 < 0 or d3 < 0
            local has_pos = d1 > 0 or d2 > 0 or d3 > 0
            if not (has_neg and has_pos) then put(grid, x, y, ch) end
        end
    end
end

-- Eyes sit at EYE_Y, the nose at NOSE_Y, the mouth one row below the nose.
-- (Owl overrides these; see the species table.)
local EYE_L, EYE_R, EYE_Y, NOSE_Y = 7, 14, 10, 13

local SPECIES_ART = {
    cat = function(g)
        ellipse(g, 10.5, 16.5, 5.5, 3.5, "B")                 -- body
        ellipse(g, 10.5, 17, 3, 2.5, "L")                      -- belly
        ellipse(g, 10.5, 10.5, 7.5, 6, "B")                    -- head
        triangle(g, 3.5, 7, 3.5, 2, 8.5, 5, "B")               -- ears
        triangle(g, 17.5, 7, 17.5, 2, 12.5, 5, "B")
        triangle(g, 4.5, 6, 4.5, 3.5, 7, 5.2, "P")
        triangle(g, 16.5, 6, 16.5, 3.5, 14, 5.2, "P")
        ellipse(g, 10.5, 13.5, 3.2, 2.2, "L")                  -- muzzle
        rect(g, 10, 5, 10, 6, "D"); rect(g, 8, 5, 8, 5, "D"); rect(g, 12, 5, 12, 5, "D") -- forehead stripes
    end,
    dog = function(g)
        ellipse(g, 10.5, 16.5, 5.5, 3.5, "B")
        ellipse(g, 10.5, 17, 3, 2.5, "L")
        ellipse(g, 10.5, 10, 6.5, 6, "B")
        ellipse(g, 3.8, 10, 2.2, 5, "D")                       -- floppy ears
        ellipse(g, 17.2, 10, 2.2, 5, "D")
        ellipse(g, 10.5, 13.2, 3.6, 2.8, "L")                  -- muzzle
        ellipse(g, 7, 10.4, 2.3, 2.3, "D")                     -- eye patch
    end,
    fox = function(g)
        ellipse(g, 10.5, 16.5, 5.5, 3.5, "B")
        ellipse(g, 10.5, 17, 3, 2.5, "L")
        ellipse(g, 10.5, 10.5, 7, 5.6, "B")
        triangle(g, 3, 8, 3.5, 1.5, 8.5, 5.5, "B")             -- tall ears
        triangle(g, 18, 8, 17.5, 1.5, 12.5, 5.5, "B")
        triangle(g, 3.7, 4, 3.8, 1.5, 5.6, 3.2, "D")
        triangle(g, 17.3, 4, 17.2, 1.5, 15.4, 3.2, "D")
        triangle(g, 3.5, 11, 10.5, 17, 6.5, 11.2, "L")         -- white cheeks
        triangle(g, 17.5, 11, 10.5, 17, 14.5, 11.2, "L")
        ellipse(g, 10.5, 14, 2.4, 2, "L")
    end,
    owl = function(g)
        ellipse(g, 10.5, 11.5, 7.5, 7.5, "B")                  -- round body
        ellipse(g, 10.5, 15.5, 4.5, 3.5, "L")                  -- belly
        triangle(g, 3.5, 6, 4.5, 1.5, 8.5, 4.2, "D")           -- ear tufts
        triangle(g, 17.5, 6, 16.5, 1.5, 12.5, 4.2, "D")
        ellipse(g, 7, 9.5, 3.2, 3.2, "L")                      -- face discs
        ellipse(g, 14, 9.5, 3.2, 3.2, "L")
        ellipse(g, 7, 9.5, 2, 2, "W")
        ellipse(g, 14, 9.5, 2, 2, "W")
        triangle(g, 9.5, 11, 11.5, 11, 10.5, 13.5, "O")        -- beak
        rect(g, 5, 18, 7, 19, "O"); rect(g, 14, 18, 16, 19, "O") -- feet
    end,
    bunny = function(g)
        ellipse(g, 10.5, 16.8, 5.4, 3.2, "B")
        ellipse(g, 10.5, 17.2, 3, 2.4, "L")
        ellipse(g, 10.5, 12, 6.8, 5.4, "B")
        ellipse(g, 7, 5, 2, 4.8, "B")                          -- long ears
        ellipse(g, 14, 5, 2, 4.8, "B")
        ellipse(g, 7, 5.4, 0.9, 3.4, "P")
        ellipse(g, 14, 5.4, 0.9, 3.4, "P")
        ellipse(g, 10.5, 14.8, 3, 2, "L")
    end,
}

local EYES = {
    cat = { 7, 14, 10, 13 }, dog = { 7, 14, 10, 13 }, fox = { 7, 14, 10, 13 },
    owl = { 7, 14, 9, 11 }, bunny = { 7, 14, 11, 15 },
}

local function outline(grid)
    local marks = {}
    for y = 1, GRID do
        for x = 1, GRID do
            if not grid[y][x] then
                local near = (y > 1 and grid[y - 1][x]) or (y < GRID and grid[y + 1][x])
                    or (x > 1 and grid[y][x - 1]) or (x < GRID and grid[y][x + 1])
                if near then marks[#marks + 1] = { x, y } end
            end
        end
    end
    for _, m in ipairs(marks) do grid[m[2]][m[1]] = "K" end
end

local sprite_cache = {}

--- The 20x20 cell grid (letters, false = empty) of a species without face.
function Pet.baseSprite(species)
    species = validSpecies(species)
    if sprite_cache[species] then return sprite_cache[species] end
    local grid = newGrid()
    SPECIES_ART[species](grid)
    outline(grid)
    sprite_cache[species] = grid
    return grid
end

local function copyGrid(grid)
    local copy = {}
    for y = 1, GRID do
        copy[y] = {}
        for x = 1, GRID do copy[y][x] = grid[y][x] end
    end
    return copy
end

local function addFace(grid, species, mood, stage)
    local eyes = EYES[species] or EYES.cat
    local left, right, eye_y, nose_y = eyes[1], eyes[2], eyes[3], eyes[4]
    local function eye(x)
        if mood == "sleepy" then
            put(grid, x - 1, eye_y, "K"); put(grid, x, eye_y, "K"); put(grid, x + 1, eye_y, "K")
        elseif mood == "happy" then
            put(grid, x - 1, eye_y + 1, "K"); put(grid, x, eye_y, "K"); put(grid, x + 1, eye_y + 1, "K")
        else
            put(grid, x, eye_y, "K"); put(grid, x, eye_y + 1, "K")
            if species == "owl" then put(grid, x - 1, eye_y, "K"); put(grid, x - 1, eye_y + 1, "K") end
        end
    end
    eye(left); eye(right)
    if mood == "sad" then put(grid, left, eye_y + 2, "W"); end
    -- nose / mouth (the owl has a beak instead)
    if species ~= "owl" then
        put(grid, 10, nose_y, species == "dog" and "K" or "P"); put(grid, 11, nose_y, species == "dog" and "K" or "P")
        local my = nose_y + 1
        if mood == "happy" then
            put(grid, 9, my, "K"); put(grid, 12, my, "K"); put(grid, 10, my + 1, "K"); put(grid, 11, my + 1, "K")
        elseif mood == "sad" then
            put(grid, 10, my + 1, "K"); put(grid, 11, my + 1, "K"); put(grid, 9, my + 2, "K"); put(grid, 12, my + 2, "K")
        elseif mood == "hungry" then
            put(grid, 10, my, "K"); put(grid, 11, my, "K"); put(grid, 10, my + 1, "K"); put(grid, 11, my + 1, "K")
        elseif mood == "sleepy" then
            put(grid, 10, my, "K"); put(grid, 11, my, "K")
        else
            put(grid, 9, my, "K"); put(grid, 10, my + 1, "K"); put(grid, 11, my + 1, "K"); put(grid, 12, my, "K")
        end
    end
    -- cheeks when happy
    if mood == "happy" and species ~= "owl" then
        put(grid, left - 2, eye_y + 2, "P"); put(grid, right + 2, eye_y + 2, "P")
    end
    -- growth: grown-ups wear a small red scarf
    if stage == "adult" then
        for x = 7, 14 do put(grid, x, 19, "R") end
        for x = 8, 13 do put(grid, x, 18, "R") end
    end
end

--- A finished grid for a species, mood and stage (cached).
function Pet.sprite(species, mood, stage)
    species, mood, stage = validSpecies(species), mood or "content", stage or "baby"
    local key = species .. "/" .. mood .. "/" .. stage
    if sprite_cache[key] then return sprite_cache[key] end
    local grid = copyGrid(Pet.baseSprite(species))
    addFace(grid, species, mood, stage)
    sprite_cache[key] = grid
    return grid
end

---------------------------------------------------------------------------
-- Painting
---------------------------------------------------------------------------

-- True when the screen can show color: isColorScreen() or isColorEnabled().
local function canColor(_bb)
    return Color.isColor()
end
Pet.canColor = canColor

local function paletteColor(species, ch, colored)
    local palette = PALETTES[species] or PALETTES.cat
    local rgb = palette[ch] or palette.B
    if ch == "W" and not palette.W then rgb = { 255, 255, 255 } end
    if ch == "R" then rgb = { 196, 58, 58 } end
    if colored then
        return Color.make(rgb[1], rgb[2], rgb[3], true)
    end
    local luma = math.floor(0.299 * rgb[1] + 0.587 * rgb[2] + 0.114 * rgb[3])
    if ch == "K" then luma = 0 end
    if ch == "R" then luma = 90 end
    return Color.make(luma, luma, luma, false)
end

--- Paints a pet sprite into `size` x `size` pixels at (x, y). Babies are
--- drawn a little smaller than adults and stand on the bottom edge.
function Pet.paintSprite(bb, x, y, size, species, mood, stage)
    local grid = Pet.sprite(species, mood, stage)
    local cell = math.max(1, math.floor(size / GRID))
    local factor = stage == "baby" and 0.8 or (stage == "young" and 0.9 or 1)
    cell = math.max(1, math.floor(size * factor / GRID))
    local used = cell * GRID
    local ox = x + math.floor((size - used) / 2)
    local oy = y + size - used
    local colors = {}
    local colored = canColor(bb)
    for row = 1, GRID do
        local col = 1
        while col <= GRID do
            local ch = grid[row][col]
            if ch then
                local run = col
                while run < GRID and grid[row][run + 1] == ch do run = run + 1 end
                colors[ch] = colors[ch] or paletteColor(species, ch, colored)
                Color.paintRect(bb, ox + (col - 1) * cell, oy + (row - 1) * cell, (run - col + 1) * cell, cell, colors[ch], colored)
                col = run + 1
            else
                col = col + 1
            end
        end
    end
end

---------------------------------------------------------------------------
-- Widget
---------------------------------------------------------------------------

local PetWidget = InputContainer:extend{
    appdock = nil,
    size = 64,
    on_tap = nil,
    covers_fullscreen = false,
}

function PetWidget:init()
    self.dimen = Geom:new{ w = self.size, h = self.size }
    self.ges_events = { TapPet = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function PetWidget:getSize() return self.dimen end

function PetWidget:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local range = self.ges_events.TapPet[1].range
    range.x, range.y, range.w, range.h = x, y, self.size, self.size
    local ok, status = pcall(Pet.status, self.appdock)
    if not ok then return end
    pcall(Pet.paintSprite, bb, x, y, self.size, Pet.config(self.appdock).species, status.mood, status.stage)
end

function PetWidget:onTapPet()
    if self.on_tap then self.on_tap() else Pet.showStatus(self.appdock) end
    return true
end

--- A tappable pet of `size` pixels. Tapping opens the status card.
function Pet.widget(appdock, size, on_tap)
    return PetWidget:new{ appdock = appdock, size = size, on_tap = on_tap }
end

function Pet.showStatus(appdock)
    local title, body = Pet.statusText(appdock)
    local ok, Dialogs = pcall(require, "appdock_dialogs")
    if not ok or not Dialogs or not Dialogs.InfoMessage then return end
    UIManager:show(Dialogs.InfoMessage:new{ text = title .. "\n\n" .. body })
end

return Pet
