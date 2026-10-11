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
    cache.all = all
    return all
end

function Suggestions.get(language)
    local result = {}
    for _, item in ipairs(load()) do
        if not language or item.language == language then
            result[#result + 1] = item
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
