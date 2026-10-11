-- AppDock's offline bilingual suggestion database.
-- The accompanying TSV is intentionally plain text so it can be edited or
-- replaced without requiring SQLite or another native database on Kobo.
local Suggestions = {}
local cache = {}
local source = debug.getinfo(1, "S").source or ""
local base = source:match("^@(.*/)") or ""
local database_candidates = {}
if base ~= "" then database_candidates[#database_candidates + 1] = base .. "appdock_suggestions.db" end
if os.getenv then
    local plugin_dir = os.getenv("APPDOCK_PLUGIN_DIR")
    if plugin_dir and plugin_dir ~= "" then
        database_candidates[#database_candidates + 1] = plugin_dir:gsub("/$", "") .. "/appdock_suggestions.db"
    end
end
database_candidates[#database_candidates + 1] = "appdock_suggestions.db"
database_candidates[#database_candidates + 1] = "appdock.koplugin/appdock_suggestions.db"
local database_path = database_candidates[1] or "appdock_suggestions.db"

local function normalizedLanguage(language)
    return language == "de" and "de" or language == "en" and "en" or nil
end

-- A two-byte prefix keeps the lookup compact while still covering the common
-- German umlaut initials (they occupy two UTF-8 bytes). The final comparison
-- below remains exact, so this is only an acceleration index.
local function prefixKey(value)
    return (value or ""):lower():sub(1, 2)
end

local function load()
    if cache.all then return cache.all end
    local all = {}
    local file
    for _, candidate in ipairs(database_candidates) do
        file = io.open(candidate, "rb")
        if file then database_path = candidate; break end
    end
    if file then
        for line in file:lines() do
            if line:sub(1, 1) ~= "#" then
                local language, frequency, word = line:match("^([^\t]+)\t([^\t]+)\t(.+)$")
                frequency = tonumber(frequency)
                if (language == "de" or language == "en") and frequency and word and word ~= "" then
                    all[#all + 1] = { word = word, language = language, frequency = frequency }
                end
            end
        end
        file:close()
    end
    table.sort(all, function(a, b)
        if a.frequency == b.frequency then return a.word:lower() < b.word:lower() end
        return a.frequency > b.frequency
    end)
    local by_language = { de = {}, en = {}, all = all }
    local by_prefix = { de = {}, en = {}, all = {} }
    for _, item in ipairs(all) do
        local language = item.language
        local key = prefixKey(item.word)
        by_language[language][#by_language[language] + 1] = item
        by_prefix[language][key] = by_prefix[language][key] or {}
        by_prefix[language][key][#by_prefix[language][key] + 1] = item
        by_prefix.all[key] = by_prefix.all[key] or {}
        by_prefix.all[key][#by_prefix.all[key] + 1] = item
    end
    cache.all = all
    cache.by_language = by_language
    cache.by_prefix = by_prefix
    return all
end

function Suggestions.get(language)
    load()
    return cache.by_language[normalizedLanguage(language) or "all"] or cache.all
end

function Suggestions.match(language, prefix, limit)
    load()
    prefix = tostring(prefix or ""):lower()
    limit = math.max(1, math.min(8, tonumber(limit) or 3))
    local key_language = normalizedLanguage(language) or "all"
    local source = prefix == "" and (cache.by_language[key_language] or cache.all)
        or (#prefix < 2 and (cache.by_language[key_language] or cache.all))
        or ((cache.by_prefix[key_language] or {})[prefixKey(prefix)] or {})
    local result = {}
    for _, item in ipairs(source) do
        local word = item.word or ""
        local lower = word:lower()
        if word ~= "" and lower ~= prefix and (prefix == "" or lower:sub(1, #prefix) == prefix) then
            result[#result + 1] = item
            if #result >= limit then break end
        end
    end
    return result
end

function Suggestions.reload()
    cache = {}
end

function Suggestions.databasePath()
    return database_path
end

return Suggestions
