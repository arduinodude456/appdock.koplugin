--[[--
DockAI: a ChatGPT-style assistant for AppDock, using the authenticated dchat
Supabase proxy. Server-side device quotas and protected provider keys are
implemented in appdock_dockai_proxy.lua; this module retains presentation,
conversation storage and Markdown rendering. No provider key or admin password
is stored in local AppDock settings.
--]]--

local DockAI = {}
DockAI.__index = DockAI

-- Admin password validation is performed only by the server-side proxy.
DockAI.DEFAULT_DAILY_LIMIT = 25
DockAI.DEFAULT_WEEKLY_LIMIT = 100
DockAI.MAX_LIMIT = 100000
DockAI.DEFAULT_MODEL = "llama-3.3-70b-versatile"
DockAI.FALLBACK_MODELS = { "llama-3.3-70b-versatile", "llama-3.1-8b-instant", "openai/gpt-oss-20b", "openai/gpt-oss-120b" }
DockAI.ADMIN_SESSION_SECONDS = 300
DockAI.RATE_LIMIT_REST = 60
DockAI.KEY_FILES = { "/mnt/onboard/dockai_keys.txt", "/mnt/us/dockai_keys.txt", "dockai_keys.txt" }

-- How many of the latest messages (user + assistant) are sent along with a request.
local CONTEXT_MESSAGES = 5
DockAI.CONTEXT_MESSAGES = CONTEXT_MESSAGES
local MAX_STORED_MESSAGES = 40      -- per chat
local MAX_STORED_BYTES = 30000      -- per chat
local MAX_CHATS = 30
local MAX_MEMORIES = 25
local MAX_MEMORY_CHARS = 200
local MAX_MESSAGE_CHARS = 4000

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------
local function trim(value)
    return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Shortens a string to at most `max` bytes without splitting a UTF-8 character.
local function cut(text, max)
    text = tostring(text or "")
    if #text <= max then return text end
    local pos = max
    while pos > 0 do
        local byte = text:byte(pos + 1)
        if not byte or byte < 0x80 or byte >= 0xC0 then break end
        pos = pos - 1
    end
    return text:sub(1, pos)
end
DockAI.cut = cut

local function isGerman(appdock)
    local language = appdock and type(appdock.getKeyboardLanguage) == "function" and appdock:getKeyboardLanguage() or "auto"
    if language == "de" then return true elseif language == "en" then return false end
    local ok, code = pcall(function() return G_reader_settings:readSetting("language") end)
    return ok and type(code) == "string" and code:sub(1, 2) == "de"
end

function DockAI:tr(de, en)
    if self.german == nil then self.german = isGerman(self.appdock) end
    return self.german and de or en
end

local function clampLimit(value, default)
    value = tonumber(value)
    if not value then return default end
    value = math.floor(value)
    if value < 1 then return 1 end
    if value > DockAI.MAX_LIMIT then return DockAI.MAX_LIMIT end
    return value
end

----------------------------------------------------------------------
-- Markdown -> the small HTML subset crengine renders well
----------------------------------------------------------------------
local function escapeHtml(text)
    text = tostring(text or "")
    text = text:gsub("&", "&amp;")
    text = text:gsub("<", "&lt;")
    text = text:gsub(">", "&gt;")
    return text
end

local function inlineMarkdown(text)
    text = escapeHtml(text)
    text = text:gsub("`([^`]+)`", "<code>%1</code>")
    text = text:gsub("%*%*(.-)%*%*", "<b>%1</b>")
    text = text:gsub("__(.-)__", "<b>%1</b>")
    text = text:gsub("%*([^%s*][^*]-)%*", "<i>%1</i>")
    return text
end

function DockAI.markdownToHtml(markdown)
    local out = {}
    local paragraph, list_kind, in_code, code_lines, table_lines = {}, nil, false, {}, {}
    local function flushParagraph()
        if #paragraph > 0 then
            out[#out + 1] = "<p>" .. table.concat(paragraph, "<br/>") .. "</p>"
            paragraph = {}
        end
    end
    local function closeList()
        if list_kind then out[#out + 1] = "</" .. list_kind .. ">"; list_kind = nil end
    end
    local function flushTable()
        if #table_lines > 0 then
            out[#out + 1] = "<pre>" .. table.concat(table_lines, "\n") .. "</pre>"
            table_lines = {}
        end
    end
    for raw in (tostring(markdown or "") .. "\n"):gmatch("(.-)\r?\n") do
        if in_code then
            if raw:match("^%s*```") then
                out[#out + 1] = "<pre>" .. table.concat(code_lines, "\n") .. "</pre>"
                code_lines, in_code = {}, false
            else
                code_lines[#code_lines + 1] = escapeHtml(raw)
            end
        elseif raw:match("^%s*```") then
            flushParagraph(); closeList(); flushTable()
            in_code = true
        elseif raw:match("^%s*|") then
            flushParagraph(); closeList()
            if not raw:match("^%s*|[%s%-:|]+$") then table_lines[#table_lines + 1] = escapeHtml(raw) end
        else
            flushTable()
            local heading = raw:match("^%s*#+%s+(.+)$")
            local bullet = raw:match("^%s*[-*•]%s+(.+)$")
            local number = raw:match("^%s*%d+[.)]%s+(.+)$")
            if raw:match("^%s*$") then
                flushParagraph(); closeList()
            elseif raw:match("^%s*%-%-%-+%s*$") then
                flushParagraph(); closeList(); out[#out + 1] = "<hr/>"
            elseif heading then
                flushParagraph(); closeList()
                out[#out + 1] = "<p><b>" .. inlineMarkdown(heading) .. "</b></p>"
            elseif bullet or number then
                flushParagraph()
                local kind = bullet and "ul" or "ol"
                if list_kind ~= kind then closeList(); out[#out + 1] = "<" .. kind .. ">"; list_kind = kind end
                out[#out + 1] = "<li>" .. inlineMarkdown(bullet or number) .. "</li>"
            else
                closeList()
                paragraph[#paragraph + 1] = inlineMarkdown(raw)
            end
        end
    end
    if in_code then out[#out + 1] = "<pre>" .. table.concat(code_lines, "\n") .. "</pre>" end
    flushParagraph(); closeList(); flushTable()
    return table.concat(out, "\n")
end

----------------------------------------------------------------------
-- Construction and storage
----------------------------------------------------------------------
local function openStore()
    local LuaSettings = require("luasettings")
    local DataStorage = require("datastorage")
    return LuaSettings:open(DataStorage:getSettingsDir() .. "/appdock_dockai.lua")
end

local function defaultTransport(url, headers, body)
    local https = require("ssl.https")
    local ltn12 = require("ltn12")
    local socketutil = require("socketutil")
    local chunks = {}
    socketutil:set_timeout(15, 90)
    local ok, first, code, response_headers = pcall(function()
        return https.request{
            url = url,
            method = body and "POST" or "GET",
            headers = headers,
            source = body and ltn12.source.string(body) or nil,
            sink = ltn12.sink.table(chunks),
        }
    end)
    socketutil:reset_timeout()
    if not ok then return nil, tostring(first) end
    if type(code) ~= "number" then return nil, tostring(code or first) end
    return code, table.concat(chunks), response_headers
end

-- opts: store, transport, json, now (all optional, for tests)
function DockAI:new(appdock, opts)
    opts = opts or {}
    local object = setmetatable({
        appdock = appdock,
        store = opts.store or openStore(),
        transport = opts.transport or defaultTransport,
        json = opts.json or require("json"),
        now = opts.now or os.time,
        key_runtime = {},   -- per-key cooldown/disabled flags, by key text
    }, self)
    return object
end

function DockAI:_get(name, default)
    local value = self.store:readSetting(name)
    if value == nil then return default end
    return value
end

function DockAI:_set(name, value)
    self.store:saveSetting(name, value)
end

function DockAI:flush()
    if self.store.flush then pcall(self.store.flush, self.store) end
end

----------------------------------------------------------------------
-- Limits
----------------------------------------------------------------------
local function dayId(time)
    return os.date("%Y-%m-%d", time)
end

-- Weeks start on Monday.
local function weekId(time)
    local weekday = tonumber(os.date("%w", time)) or 0
    local back = (weekday + 6) % 7
    local noon = os.time{ year = tonumber(os.date("%Y", time)), month = tonumber(os.date("%m", time)), day = tonumber(os.date("%d", time)), hour = 12 }
    return os.date("%Y-%m-%d", noon - back * 86400), noon - back * 86400
end

function DockAI:getLimits()
    return clampLimit(self:_get("daily_limit"), DockAI.DEFAULT_DAILY_LIMIT),
        clampLimit(self:_get("weekly_limit"), DockAI.DEFAULT_WEEKLY_LIMIT)
end

function DockAI:setLimits(daily, weekly)
    if daily ~= nil then self:_set("daily_limit", clampLimit(daily, DockAI.DEFAULT_DAILY_LIMIT)) end
    if weekly ~= nil then self:_set("weekly_limit", clampLimit(weekly, DockAI.DEFAULT_WEEKLY_LIMIT)) end
    self:flush()
end

-- Starts a new day/week counter when the period changed.
function DockAI:_rollover()
    local now = self.now()
    local usage = self:_get("usage", {})
    if type(usage) ~= "table" then usage = {} end
    local day = dayId(now)
    local week = weekId(now)
    if usage.day ~= day then usage.day, usage.day_count = day, 0 end
    if usage.week ~= week then usage.week, usage.week_count = week, 0 end
    usage.day_count = tonumber(usage.day_count) or 0
    usage.week_count = tonumber(usage.week_count) or 0
    self:_set("usage", usage)
    return usage
end

function DockAI:usage()
    local usage = self:_rollover()
    local daily, weekly = self:getLimits()
    local info = {
        day_used = usage.day_count, day_limit = daily,
        week_used = usage.week_count, week_limit = weekly,
    }
    info.day_left = math.max(0, daily - usage.day_count)
    info.week_left = math.max(0, weekly - usage.week_count)
    info.left = math.min(info.day_left, info.week_left)
    if info.week_left <= 0 then info.blocked = "week"
    elseif info.day_left <= 0 then info.blocked = "day" end
    -- A reached weekly limit wins even if the day still has room.
    local now = self.now()
    local tomorrow = os.time{ year = tonumber(os.date("%Y", now)), month = tonumber(os.date("%m", now)), day = tonumber(os.date("%d", now)) + 1, hour = 0 }
    local _, monday = weekId(now)
    local next_monday = os.time{ year = tonumber(os.date("%Y", monday)), month = tonumber(os.date("%m", monday)), day = tonumber(os.date("%d", monday)) + 7, hour = 0 }
    info.day_resets_at, info.week_resets_at = tomorrow, next_monday
    return info
end

function DockAI:recordUse()
    local usage = self:_rollover()
    usage.day_count = usage.day_count + 1
    usage.week_count = usage.week_count + 1
    self:_set("usage", usage)
    self:flush()
end

function DockAI:resetUsage()
    self:_set("usage", nil)
    self:_rollover()
    self:flush()
end

function DockAI:limitText(info)
    info = info or self:usage()
    if info.blocked == "week" then
        return string.format(self:tr("Wochenlimit erreicht (%d/%d) · neu ab Montag", "Weekly limit reached (%d/%d) · resets Monday"), info.week_used, info.week_limit)
    elseif info.blocked == "day" then
        return string.format(self:tr("Tageslimit erreicht (%d/%d) · neu ab Mitternacht", "Daily limit reached (%d/%d) · resets at midnight"), info.day_used, info.day_limit)
    end
    return string.format(self:tr("Heute %d/%d · Woche %d/%d Nachrichten", "Today %d/%d · Week %d/%d messages"), info.day_used, info.day_limit, info.week_used, info.week_limit)
end

----------------------------------------------------------------------
-- API keys (admin) and rotation
----------------------------------------------------------------------
function DockAI:keys()
    local keys = self:_get("keys", {})
    if type(keys) ~= "table" then return {} end
    return keys
end

function DockAI.validKey(key)
    key = trim(key)
    return #key >= 20 and #key <= 200 and not key:find("%s") and key:match("^[%w_%-%.]+$") ~= nil
end

function DockAI.maskKey(key)
    key = tostring(key or "")
    if #key <= 8 then return "••••" end
    return key:sub(1, 4) .. "…" .. key:sub(-4)
end

function DockAI:addKey(key)
    key = trim(key)
    if not DockAI.validKey(key) then return false, "invalid" end
    local keys = self:keys()
    for _, existing in ipairs(keys) do
        if existing == key then self.key_runtime[key] = nil; return false, "duplicate" end
    end
    keys[#keys + 1] = key
    self:_set("keys", keys)
    self:flush()
    return true
end

function DockAI:removeKey(index)
    local keys = self:keys()
    local key = keys[index]
    if not key then return false end
    table.remove(keys, index)
    self.key_runtime[key] = nil
    self:_set("keys", keys)
    self:_set("key_index", 0)
    self:flush()
    return true
end

-- One key per line (lines starting with # are comments). Returns the number
-- of new keys. A file the admin places on the device spares typing 56
-- characters on an e-ink keyboard.
function DockAI:importKeys(path)
    local paths = path and { path } or DockAI.KEY_FILES
    for _, candidate in ipairs(paths) do
        local handle = io.open(candidate, "r")
        if handle then
            local added = 0
            for line in handle:lines() do
                line = trim(line)
                if line ~= "" and line:sub(1, 1) ~= "#" and self:addKey(line) then added = added + 1 end
            end
            handle:close()
            return added, candidate
        end
    end
    return nil
end

function DockAI:keyStatus(index)
    local key = self:keys()[index]
    local runtime = key and self.key_runtime[key]
    if not runtime then return "ok" end
    if runtime.disabled then return "disabled" end
    if runtime.rest_until and runtime.rest_until > self.now() then return "resting" end
    return "ok"
end

function DockAI:reviveKeys()
    self.key_runtime = {}
end

-- Round robin over keys that are neither disabled nor resting.
function DockAI:_pickKey(skip)
    local keys = self:keys()
    local count = #keys
    if count == 0 then return nil end
    local start = tonumber(self:_get("key_index", 0)) or 0
    for offset = 1, count do
        local index = ((start + offset - 1) % count) + 1
        if not (skip and skip[index]) then
            local runtime = self.key_runtime[keys[index]]
            local usable = not runtime or (not runtime.disabled and not (runtime.rest_until and runtime.rest_until > self.now()))
            if usable then return keys[index], index end
        end
    end
    return nil
end

----------------------------------------------------------------------
-- Models
----------------------------------------------------------------------
function DockAI:getModel()
    local model = self:_get("model", DockAI.DEFAULT_MODEL)
    if type(model) ~= "string" or model == "" then model = DockAI.DEFAULT_MODEL end
    return model
end

function DockAI:setModel(model)
    if type(model) == "string" and model ~= "" then self:_set("model", model); self:flush() end
end

function DockAI:modelList()
    local list, seen = {}, {}
    local function add(id) if type(id) == "string" and id ~= "" and not seen[id] then seen[id] = true; list[#list + 1] = id end end
    add(self:getModel())
    local cached = self:_get("models", {})
    if type(cached) == "table" then for _, id in ipairs(cached) do add(id) end end
    for _, id in ipairs(DockAI.FALLBACK_MODELS) do add(id) end
    return list
end

function DockAI.shortModelName(model)
    model = tostring(model or "")
    return (model:gsub("^.*/", ""))
end

-- Asks Groq which chat models exist (needs one working key).
function DockAI:refreshModels()
    local key = self:_pickKey()
    if not key then return nil, "no_keys" end
    local code, body = self.transport(DockAI.MODELS_ENDPOINT, { ["Authorization"] = "Bearer " .. key, ["Accept"] = "application/json" })
    if code ~= 200 then return nil, "http_" .. tostring(code) end
    local ok, data = pcall(self.json.decode, body)
    if not ok or type(data) ~= "table" or type(data.data) ~= "table" then return nil, "bad_response" end
    local models = {}
    for _, item in ipairs(data.data) do
        local id = type(item) == "table" and item.id
        if type(id) == "string" and not id:lower():find("whisper") and not id:lower():find("guard")
            and not id:lower():find("tts") and not id:lower():find("orpheus") and not id:lower():find("embed")
            and not id:lower():find("compound") and item.active ~= false then
            models[#models + 1] = id
        end
    end
    table.sort(models)
    while #models > 30 do table.remove(models) end
    if #models > 0 then self:_set("models", models); self:flush() end
    return models
end

----------------------------------------------------------------------
-- Persistent memories ("Erinnerungen")
----------------------------------------------------------------------
function DockAI:memories()
    local list = self:_get("memories", {})
    local clean = {}
    if type(list) == "table" then
        for _, item in ipairs(list) do
            if type(item) == "string" and trim(item) ~= "" then clean[#clean + 1] = item end
        end
    end
    return clean
end

-- Returns true, or false + "empty" / "duplicate" / "full".
function DockAI:addMemory(text)
    text = cut(trim((tostring(text or ""):gsub("%s+", " "))), MAX_MEMORY_CHARS)
    if #text < 3 then return false, "empty" end
    local list = self:memories()
    local lowered = text:lower()
    for _, item in ipairs(list) do
        if item:lower() == lowered then return false, "duplicate" end
    end
    if #list >= MAX_MEMORIES then return false, "full" end
    list[#list + 1] = text
    self:_set("memories", list)
    self:flush()
    return true
end

function DockAI:removeMemory(index)
    local list = self:memories()
    if not list[index] then return false end
    table.remove(list, index)
    self:_set("memories", list)
    self:flush()
    return true
end

function DockAI:clearMemories()
    self:_set("memories", {})
    self:flush()
end

local MEMORY_PREFIXES = {
    "^bitte%s+merke?'?%s+dir[:,]?%s*", "^merke?'?%s+dir[:,]?%s*",
    "^please%s+remember%s+that%s+", "^remember%s+that%s+",
    "^please%s+remember:%s*", "^remember:%s*",
}

-- "Merk dir, dass ich Alex heiße" -> "ich Alex heiße". Returns nil when the
-- message is not a memory request.
function DockAI.extractMemory(text)
    text = trim(text)
    local lowered = text:lower()
    for _, pattern in ipairs(MEMORY_PREFIXES) do
        local _, finish = lowered:find(pattern)
        if finish then
            local rest = text:sub(finish + 1)
            local _, lead_end = rest:lower():find("^dass%s+")
            if lead_end then rest = rest:sub(lead_end + 1) end
            rest = trim(rest)
            if #rest >= 3 then return rest end
        end
    end
    return nil
end

-- Memories travel inside the first message of the request, so they work with
-- the server-side system prompt without needing a separate "system" entry.
function DockAI:memoryBlock()
    local list = self:memories()
    if #list == 0 then return "" end
    local lines = { self:tr("[Gespeicherte Erinnerungen über den Nutzer – nutze sie nur, wenn sie zur Frage passen:",
        "[Saved memories about the user – use them only when relevant:") }
    for _, item in ipairs(list) do lines[#lines + 1] = "- " .. item end
    lines[#lines + 1] = "]"
    return table.concat(lines, "\n")
end

-- The messages sent to the model: the last CONTEXT_MESSAGES usable ones,
-- starting with a user message, with the memories in front of the first.
function DockAI:contextMessages(history)
    local usable = {}
    for _, entry in ipairs(history or {}) do
        if type(entry) == "table" and not entry.error and (entry.role == "user" or entry.role == "assistant")
            and type(entry.content) == "string" and entry.content ~= "" then
            usable[#usable + 1] = entry
        end
    end
    local first = math.max(1, #usable - CONTEXT_MESSAGES + 1)
    while usable[first] and usable[first].role ~= "user" do first = first + 1 end
    local messages = {}
    for index = first, #usable do
        messages[#messages + 1] = { role = usable[index].role, content = cut(usable[index].content, MAX_MESSAGE_CHARS) }
    end
    local block = self:memoryBlock()
    if block ~= "" and messages[1] then messages[1].content = block .. "\n\n" .. messages[1].content end
    return messages
end

----------------------------------------------------------------------
-- Chat completion with key rotation
----------------------------------------------------------------------
function DockAI:systemPrompt()
    return self:tr(
        "Du bist DockAI, ein hilfreicher Assistent in AppDock auf einem E-Reader. Antworte in der Sprache des Nutzers, klar und eher knapp. Nutze einfaches Markdown (Listen, **fett**, Code in Dreifach-Backticks) nur, wenn es hilft.",
        "You are DockAI, a helpful assistant inside AppDock on an e-reader. Reply in the user's language, clearly and fairly concisely. Use simple Markdown (lists, **bold**, fenced code) only when it helps.")
end

local function retryAfter(headers)
    local value = headers and (headers["retry-after"] or headers["Retry-After"])
    value = tonumber(value)
    if value and value > 0 then return math.min(value, 3600) end
    return DockAI.RATE_LIMIT_REST
end

local function stripThinking(text)
    text = tostring(text or "")
    text = text:gsub("<think>.-</think>%s*", "")
    return trim(text)
end

-- history: array of {role, content}. Returns text, or nil + error code + detail.
-- Error codes: no_keys, network, all_keys_failed, bad_response, model.
function DockAI:complete(history)
    local keys = self:keys()
    if #keys == 0 then return nil, "no_keys" end

    local messages = { { role = "system", content = self:systemPrompt() } }
    for _, entry in ipairs(self:contextMessages(history)) do messages[#messages + 1] = entry end

    local skip, last_code, last_detail = {}, nil, nil
    local model_fallbacks = 0
    local attempts = 0
    while attempts < #keys + 3 do
        attempts = attempts + 1
        local key, index = self:_pickKey(skip)
        if not key then break end
        local payload = self.json.encode{ model = self:getModel(), messages = messages, temperature = 0.7, max_tokens = 1024 }
        local code, body, headers = self.transport(DockAI.ENDPOINT, {
            ["Authorization"] = "Bearer " .. key,
            ["Content-Type"] = "application/json",
            ["Accept"] = "application/json",
            ["Content-Length"] = tostring(#payload),
        }, payload)
        if code == 200 then
            local ok, data = pcall(self.json.decode, body)
            local text = ok and type(data) == "table" and type(data.choices) == "table" and data.choices[1]
                and type(data.choices[1].message) == "table" and data.choices[1].message.content
            text = text and stripThinking(text)
            if not text or text == "" then return nil, "bad_response" end
            self:_set("key_index", index)
            self:flush()
            return text
        elseif code == nil then
            return nil, "network", body
        elseif code == 401 or code == 403 then
            self.key_runtime[key] = { disabled = true }
            skip[index] = true
            last_code = "all_keys_failed"
        elseif code == 429 then
            self.key_runtime[key] = { rest_until = self.now() + retryAfter(headers) }
            skip[index] = true
            last_code = "all_keys_failed"
        elseif code == 404 or (code == 400 and tostring(body):lower():find("model")) then
            -- The chosen model is gone: move to the next known one and retry.
            model_fallbacks = model_fallbacks + 1
            local candidates = self:modelList()
            local current = self:getModel()
            local replacement
            for _, id in ipairs(DockAI.FALLBACK_MODELS) do if id ~= current then replacement = id; break end end
            for position, id in ipairs(candidates) do if id == current and candidates[position + 1] then replacement = candidates[position + 1]; break end end
            if model_fallbacks > 3 or not replacement then return nil, "model", tostring(body) end
            self:setModel(replacement)
            attempts = attempts - 1
        elseif code >= 500 then
            self.key_runtime[key] = { rest_until = self.now() + 20 }
            skip[index] = true
            last_code, last_detail = "all_keys_failed", tostring(code)
        else
            return nil, "bad_response", tostring(code) .. " " .. tostring(body):sub(1, 160)
        end
    end
    return nil, last_code or "all_keys_failed", last_detail
end

function DockAI:errorText(code)
    if code == "no_keys" then
        return self:tr("DockAI ist noch nicht eingerichtet. Der Admin kann unter Einstellungen > DockAI Groq-API-Keys hinzufügen.",
            "DockAI is not set up yet. The admin can add Groq API keys under Settings > DockAI.")
    elseif code == "network" then
        return self:tr("Keine Verbindung zu Groq. Prüfe das WLAN und versuche es noch einmal. Diese Nachricht zählt nicht zu deinem Limit.",
            "Could not reach Groq. Check your Wi-Fi and try again. This message did not count towards your limit.")
    elseif code == "all_keys_failed" then
        return self:tr("Alle API-Keys sind gerade ausgelastet oder ungültig. Bitte versuche es in einer Minute noch einmal. Diese Nachricht zählt nicht zu deinem Limit.",
            "All API keys are busy or invalid right now. Please try again in a minute. This message did not count towards your limit.")
    elseif code == "model" then
        return self:tr("Das gewählte Modell ist nicht verfügbar. Wähle oben ein anderes Modell.",
            "The selected model is not available. Pick another model at the top.")
    end
    return self:tr("Die Antwort von Groq war unlesbar. Bitte versuche es noch einmal.", "Groq's answer could not be read. Please try again.")
end

----------------------------------------------------------------------
-- Conversation storage
----------------------------------------------------------------------
function DockAI:newChat()
    return { id = tostring(self.now()) .. "-" .. tostring(math.random(1000, 9999)), title = "", messages = {}, updated = self.now() }
end

function DockAI.chatTitle(messages)
    for _, entry in ipairs(messages or {}) do
        if entry.role == "user" and type(entry.content) == "string" then
            local text = trim((entry.content:gsub("%s+", " ")))
            if text ~= "" then
                local short = cut(text, 40)
                return short .. (#short < #text and "…" or "")
            end
        end
    end
    return ""
end

local function cleanMessages(list)
    local cleaned = {}
    if type(list) ~= "table" then return cleaned end
    for _, entry in ipairs(list) do
        if type(entry) == "table" and (entry.role == "user" or entry.role == "assistant") and type(entry.content) == "string" then
            cleaned[#cleaned + 1] = { role = entry.role, content = entry.content, error = entry.error and true or nil }
        end
    end
    return cleaned
end

-- All saved chats, newest first. The single chat of earlier releases becomes
-- the first entry.
function DockAI:loadChats()
    local raw = self:_get("chats", nil)
    local chats = {}
    if type(raw) == "table" then
        for _, item in ipairs(raw) do
            if type(item) == "table" and type(item.id) == "string" then
                local messages = cleanMessages(item.messages)
                if #messages > 0 then
                    chats[#chats + 1] = {
                        id = item.id, messages = messages, updated = tonumber(item.updated) or 0,
                        title = (type(item.title) == "string" and item.title ~= "") and item.title or DockAI.chatTitle(messages),
                    }
                end
            end
        end
    end
    if #chats == 0 then
        local legacy = cleanMessages(self:_get("chat", {}))
        if #legacy > 0 then
            local chat = self:newChat()
            chat.messages, chat.title = legacy, DockAI.chatTitle(legacy)
            chats[1] = chat
            self:saveChats(chats)
        end
    end
    table.sort(chats, function(a, b) return (a.updated or 0) > (b.updated or 0) end)
    return chats
end

function DockAI:saveChats(chats)
    local sorted = {}
    for _, chat in ipairs(chats or {}) do
        if #chat.messages > 0 then sorted[#sorted + 1] = chat end
    end
    table.sort(sorted, function(a, b) return (a.updated or 0) > (b.updated or 0) end)
    local stored = {}
    for index = 1, math.min(#sorted, MAX_CHATS) do
        local chat = sorted[index]
        local messages, bytes = {}, 0
        for position = #chat.messages, 1, -1 do
            local entry = chat.messages[position]
            bytes = bytes + #entry.content
            if #messages >= MAX_STORED_MESSAGES or bytes > MAX_STORED_BYTES then break end
            table.insert(messages, 1, { role = entry.role, content = entry.content, error = entry.error })
        end
        stored[#stored + 1] = {
            id = chat.id, messages = messages, updated = chat.updated or 0,
            title = (chat.title and chat.title ~= "") and chat.title or DockAI.chatTitle(messages),
        }
    end
    self:_set("chats", stored)
    self:_set("chat", nil)
    self:flush()
end

----------------------------------------------------------------------
-- Admin session
----------------------------------------------------------------------
function DockAI:checkPassword(input)
    return trim(input) == DockAI.ADMIN_PASSWORD
end

function DockAI:unlockAdmin(input)
    if not self:checkPassword(input) then return false end
    self.admin_until = self.now() + DockAI.ADMIN_SESSION_SECONDS
    return true
end

function DockAI:isAdmin()
    return self.admin_until ~= nil and self.admin_until > self.now()
end

function DockAI:lockAdmin()
    self.admin_until = nil
end

----------------------------------------------------------------------
-- UI: dialogs shared by settings and the app
----------------------------------------------------------------------
local function ui()
    return {
        UIManager = require("ui/uimanager"),
        ButtonDialog = require("ui/widget/buttondialog"),
        InfoMessage = require("ui/widget/infomessage"),
        ConfirmBox = require("ui/widget/confirmbox"),
        Keyboard = require("appdock_keyboard"),
    }
end

local function formatDate(time)
    return os.date("%d.%m. %H:%M", time)
end

function DockAI:showLimitInfo()
    local U = ui()
    local info = self:usage()
    local text = string.format(
        self:tr("Tageslimit: %d von %d Nachrichten benutzt (neu ab Mitternacht)\nWochenlimit: %d von %d Nachrichten benutzt (neu ab Montag)\n\nNur Antworten, die wirklich ankommen, zählen. Wenn eines der beiden Limits erreicht ist, pausiert DockAI bis zum Reset.",
            "Daily limit: %d of %d messages used (resets at midnight)\nWeekly limit: %d of %d messages used (resets on Monday)\n\nOnly replies that actually arrive count. When either limit is reached, DockAI pauses until it resets."),
        info.day_used, info.day_limit, info.week_used, info.week_limit)
    U.UIManager:show(U.InfoMessage:new{ text = text })
end

function DockAI:_promptText(title, placeholder, value, options, on_submit)
    local U = ui()
    options = options or {}
    local keyboard
    keyboard = U.Keyboard:new{
        title = title, placeholder = placeholder, value = value or "",
        secure = options.secure, numeric_only = options.numeric_only,
        on_cancel = function()
            U.UIManager:close(keyboard)
            if options.on_cancel then options.on_cancel() end
        end,
        on_submit = function(text)
            U.UIManager:nextTick(function()
                U.UIManager:close(keyboard)
                on_submit(text)
            end)
        end,
    }
    U.UIManager:show(keyboard)
end

function DockAI:_toast(text)
    local U = ui()
    U.UIManager:show(U.InfoMessage:new{ text = text, timeout = 4 })
end

function DockAI:showModelPicker(after)
    local U = ui()
    local dialog
    local buttons = {}
    local current = self:getModel()
    for _, id in ipairs(self:modelList()) do
        buttons[#buttons + 1] = { { text = (id == current and "✓ " or "") .. id, callback = function()
            self:setModel(id)
            U.UIManager:close(dialog)
            if after then after() end
        end } }
    end
    buttons[#buttons + 1] = { { text = self:tr("Modellliste aktualisieren", "Refresh model list"), callback = function()
        U.UIManager:close(dialog)
        U.UIManager:nextTick(function()
            local models, err = self:refreshModels()
            self:_toast(models and string.format(self:tr("%d Modelle gefunden.", "%d models found."), #models)
                or self:errorText(err == "no_keys" and "no_keys" or "network"))
            self:showModelPicker(after)
        end)
    end } }
    buttons[#buttons + 1] = { { text = self:tr("Schließen", "Close"), callback = function() U.UIManager:close(dialog) end } }
    dialog = U.ButtonDialog:new{ title = self:tr("Modell wählen", "Choose a model"), buttons = buttons }
    U.UIManager:show(dialog)
end

-- Memories ------------------------------------------------------------
function DockAI:showMemoryManager(after)
    local U = ui()
    local dialog
    local function finish() if after then pcall(after) end end
    local function reopen() U.UIManager:nextTick(function() self:showMemoryManager(after) end) end
    local list = self:memories()
    local buttons = {}
    for index, item in ipairs(list) do
        buttons[#buttons + 1] = { { text = "×  " .. cut(item, 70), callback = function()
            U.UIManager:close(dialog)
            self:removeMemory(index)
            finish(); reopen()
        end } }
    end
    if #buttons == 0 then
        buttons[1] = { { text = self:tr("Noch keine Erinnerungen", "No memories yet"), enabled = false, callback = function() end } }
    end
    buttons[#buttons + 1] = { { text = self:tr("+ Erinnerung hinzufügen", "+ Add memory"), callback = function()
        U.UIManager:close(dialog)
        self:_promptText(self:tr("Neue Erinnerung", "New memory"), self:tr("z. B. Ich heiße Alex", "e.g. My name is Alex"), "",
            { on_cancel = function() reopen() end },
            function(text)
                local ok, reason = self:addMemory(text)
                if not ok then
                    self:_toast(reason == "full" and string.format(self:tr("Maximal %d Erinnerungen. Lösche zuerst eine.", "At most %d memories. Delete one first."), MAX_MEMORIES)
                        or (reason == "duplicate" and self:tr("Diese Erinnerung gibt es schon.", "That memory already exists.")
                        or self:tr("Der Text ist zu kurz.", "That text is too short.")))
                end
                finish(); self:showMemoryManager(after)
            end)
    end } }
    if #list > 0 then
        buttons[#buttons + 1] = { { text = self:tr("Alle löschen", "Delete all"), callback = function()
            U.UIManager:close(dialog)
            U.UIManager:show(U.ConfirmBox:new{
                text = self:tr("Alle Erinnerungen löschen?", "Delete all memories?"),
                ok_text = self:tr("Löschen", "Delete"), cancel_text = self:tr("Abbrechen", "Cancel"),
                ok_callback = function() self:clearMemories(); finish(); self:showMemoryManager(after) end,
                cancel_callback = function() self:showMemoryManager(after) end,
            })
        end } }
    end
    buttons[#buttons + 1] = { { text = self:tr("Schließen", "Close"), callback = function() U.UIManager:close(dialog); finish() end } }
    dialog = U.ButtonDialog:new{
        title = string.format(self:tr("Erinnerungen (%d/%d) · Tippen zum Löschen", "Memories (%d/%d) · tap to delete"), #list, MAX_MEMORIES),
        buttons = buttons,
    }
    U.UIManager:show(dialog)
end

-- Admin ---------------------------------------------------------------
function DockAI:openAdmin(refresh)
    if self:isAdmin() then return self:showAdminDialog(refresh) end
    self:_promptText(self:tr("Admin-Passwort", "Admin password"), self:tr("Passwort", "Password"), "", { secure = true }, function(text)
        if self:unlockAdmin(text) then
            self:showAdminDialog(refresh)
        else
            self:_toast(self:tr("Falsches Passwort.", "Wrong password."))
        end
    end)
end

function DockAI:showKeyList(refresh)
    local U = ui()
    local dialog
    local buttons = {}
    local status_text = {
        ok = self:tr("aktiv", "active"),
        resting = self:tr("pausiert", "resting"),
        disabled = self:tr("ungültig", "rejected"),
    }
    for index, key in ipairs(self:keys()) do
        buttons[#buttons + 1] = { { text = string.format("%d · %s · %s", index, DockAI.maskKey(key), status_text[self:keyStatus(index)] or ""), callback = function()
            U.UIManager:close(dialog)
            U.UIManager:show(U.ConfirmBox:new{
                text = string.format(self:tr("Key %s entfernen?", "Remove key %s?"), DockAI.maskKey(key)),
                ok_text = self:tr("Entfernen", "Remove"), cancel_text = self:tr("Abbrechen", "Cancel"),
                ok_callback = function() self:removeKey(index); self:showKeyList(refresh) end,
                cancel_callback = function() self:showKeyList(refresh) end,
            })
        end } }
    end
    if #buttons == 0 then buttons[1] = { { text = self:tr("Noch keine Keys", "No keys yet"), enabled = false, callback = function() end } } end
    buttons[#buttons + 1] = { { text = self:tr("Alle Keys wieder aktivieren", "Re-enable all keys"), callback = function()
        self:reviveKeys(); U.UIManager:close(dialog); self:showKeyList(refresh)
    end } }
    buttons[#buttons + 1] = { { text = self:tr("Zurück", "Back"), callback = function() U.UIManager:close(dialog); self:showAdminDialog(refresh) end } }
    dialog = U.ButtonDialog:new{ title = self:tr("API-Keys (Tippen zum Entfernen)", "API keys (tap to remove)"), buttons = buttons }
    U.UIManager:show(dialog)
end

function DockAI:showAdminDialog(refresh)
    local U = ui()
    local dialog
    local function done() if refresh then pcall(refresh) end end
    local function reopen() U.UIManager:close(dialog); U.UIManager:nextTick(function() self:showAdminDialog(refresh) end) end
    local keys = self:keys()
    local active = 0
    for index = 1, #keys do if self:keyStatus(index) == "ok" then active = active + 1 end end
    local daily, weekly = self:getLimits()
    local buttons = {
        { { text = self:tr("API-Key hinzufügen", "Add API key"), callback = function()
            U.UIManager:close(dialog)
            self:_promptText(self:tr("Groq API-Key", "Groq API key"), "gsk_…", "", nil, function(text)
                local ok, reason = self:addKey(text)
                self:_toast(ok and self:tr("Key gespeichert.", "Key saved.")
                    or (reason == "duplicate" and self:tr("Diesen Key gibt es schon.", "This key already exists.")
                    or self:tr("Das sieht nicht wie ein API-Key aus.", "That does not look like an API key.")))
                done(); self:showAdminDialog(refresh)
            end)
        end } },
        { { text = self:tr("Keys aus Datei importieren", "Import keys from file"), callback = function()
            local added, path = self:importKeys()
            if added == nil then
                self:_toast(self:tr("Keine Datei gefunden. Lege dockai_keys.txt (ein Key pro Zeile) in den Hauptordner des Geräts.",
                    "No file found. Put dockai_keys.txt (one key per line) into the device's main folder."))
            else
                self:_toast(string.format(self:tr("%d neue Keys aus %s.", "%d new keys from %s."), added, tostring(path)))
            end
            done(); reopen()
        end } },
        { { text = string.format(self:tr("Keys verwalten (%d, %d aktiv)", "Manage keys (%d, %d active)"), #keys, active), callback = function()
            U.UIManager:close(dialog); self:showKeyList(refresh)
        end } },
        { { text = string.format(self:tr("Tageslimit: %d", "Daily limit: %d"), daily), callback = function()
            U.UIManager:close(dialog)
            self:_promptText(self:tr("Tageslimit (Nachrichten)", "Daily limit (messages)"), "25", tostring(daily), { numeric_only = true }, function(text)
                self:setLimits(tonumber(text), nil); done(); self:showAdminDialog(refresh)
            end)
        end } },
        { { text = string.format(self:tr("Wochenlimit: %d", "Weekly limit: %d"), weekly), callback = function()
            U.UIManager:close(dialog)
            self:_promptText(self:tr("Wochenlimit (Nachrichten)", "Weekly limit (messages)"), "100", tostring(weekly), { numeric_only = true }, function(text)
                self:setLimits(nil, tonumber(text)); done(); self:showAdminDialog(refresh)
            end)
        end } },
        { { text = self:tr("Modell: ", "Model: ") .. DockAI.shortModelName(self:getModel()), callback = function()
            U.UIManager:close(dialog)
            self:showModelPicker(function() done(); self:showAdminDialog(refresh) end)
        end } },
        { { text = self:tr("Zähler dieses Geräts zurücksetzen", "Reset this device's counters"), callback = function()
            self:resetUsage(); done(); reopen()
        end } },
        { { text = self:tr("Sperren und schließen", "Lock and close"), callback = function()
            self:lockAdmin(); U.UIManager:close(dialog); done()
        end } },
    }
    dialog = U.ButtonDialog:new{
        title = string.format(self:tr("DockAI Admin · %d Keys (%d aktiv)", "DockAI admin · %d keys (%d active)"), #keys, active),
        buttons = buttons,
    }
    U.UIManager:show(dialog)
end

----------------------------------------------------------------------
-- UI: settings category
----------------------------------------------------------------------
function DockAI:settingsRows(context)
    local info = self:usage()
    local function refresh() if context and context.requestRebuild then context.requestRebuild("ui") end end
    local keys = self:keys()
    local admin_subtitle
    if self:isAdmin() then
        admin_subtitle = string.format(self:tr("Entsperrt · %d API-Keys", "Unlocked · %d API keys"), #keys)
    else
        admin_subtitle = self:tr("Passwort erforderlich", "Password required")
    end
    return {
        {
            title = self:tr("Tageslimit", "Daily limit"),
            subtitle = string.format(self:tr("%d von %d Nachrichten benutzt · %d übrig", "%d of %d messages used · %d left"), info.day_used, info.day_limit, info.day_left),
            section = self:tr("Dein Kontingent", "Your allowance"),
            show_state = false,
            callback = function() self:showLimitInfo() end,
        },
        {
            title = self:tr("Wochenlimit", "Weekly limit"),
            subtitle = string.format(self:tr("%d von %d Nachrichten benutzt · %d übrig", "%d of %d messages used · %d left"), info.week_used, info.week_limit, info.week_left),
            section = self:tr("Dein Kontingent", "Your allowance"),
            show_state = false,
            callback = function() self:showLimitInfo() end,
        },
        {
            title = self:tr("Wann es zurückgesetzt wird", "When limits reset"),
            subtitle = string.format(self:tr("Tag: %s · Woche: %s", "Day: %s · Week: %s"), formatDate(info.day_resets_at), formatDate(info.week_resets_at)),
            section = self:tr("Dein Kontingent", "Your allowance"),
            show_state = false,
            callback = function() self:showLimitInfo() end,
        },
        {
            title = self:tr("Modell", "Model"),
            subtitle = DockAI.shortModelName(self:getModel()),
            section = self:tr("Chat", "Chat"),
            show_state = false,
            callback = function() self:showModelPicker(refresh) end,
        },
        {
            title = self:tr("Erinnerungen", "Memories"),
            subtitle = string.format(self:tr("%d gespeichert · fließen in jede Antwort ein", "%d saved · included in every reply"), #self:memories()),
            section = self:tr("Chat", "Chat"),
            show_state = false,
            callback = function() self:showMemoryManager(refresh) end,
        },
        {
            title = self:tr("Admin: API-Keys und Limits", "Admin: API keys and limits"),
            subtitle = admin_subtitle,
            section = self:tr("Admin", "Admin"),
            show_state = false,
            callback = function() self:openAdmin(refresh) end,
        },
    }
end

----------------------------------------------------------------------
-- UI: the chat pane (ChatGPT look)
----------------------------------------------------------------------
local CSS = [[
body { margin: 0; padding: 0; }
p { margin: 0 0 8px 0; }
ul, ol { margin: 0 0 8px 0; }
li { margin: 0 0 3px 0; }
h3 { margin: 6px 0 6px 0; }
pre { background-color: #F0F0F0; padding: 6px; font-size: 85%; margin: 0 0 8px 0; }
code { font-family: monospace; background-color: #F0F0F0; }
.u { text-align: right; margin: 12px 0 12px 0; }
.ub { display: inline-block; background-color: #E9E9E9; padding: 8px 14px 8px 14px; margin-left: 18%; text-align: left; }
.a { margin: 6px 0 16px 0; }
.err { color: #555555; font-style: italic; }
.dots { color: #777777; }
]]

local function transcriptHtml(self, chat, busy)
    local parts = {}
    for _, entry in ipairs(chat) do
        if entry.role == "user" then
            parts[#parts + 1] = '<div class="u"><div class="ub">' .. escapeHtml(entry.content):gsub("\n", "<br/>") .. "</div></div>"
        elseif entry.error then
            parts[#parts + 1] = '<div class="a err">' .. escapeHtml(entry.content):gsub("\n", "<br/>") .. "</div>"
        else
            parts[#parts + 1] = '<div class="a">' .. DockAI.markdownToHtml(entry.content) .. "</div>"
        end
    end
    if busy then parts[#parts + 1] = '<div class="a dots">' .. self:tr("DockAI denkt nach …", "DockAI is thinking …") .. "</div>" end
    return table.concat(parts, "\n")
end

-- Tap target: a transparent InputContainer (same pattern as AppDock's chips).
local tap_class
function DockAI._tapClass(blank)
    if tap_class then return tap_class end
    local Geom = require("ui/geometry")
    local GestureRange = require("ui/gesturerange")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local Tap = InputContainer:extend{ callback = nil, width = 0, height = 0 }
    function Tap:init()
        self.dimen = Geom:new{ w = self.width, h = self.height }
        self[1] = blank(self.width, self.height)
        self.ges_events = { TapDockAI = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    end
    function Tap:paintTo(bb, x, y)
        local range = self.ges_events.TapDockAI[1].range
        range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
        self.dimen.x, self.dimen.y = x, y
        return InputContainer.paintTo(self, bb, x, y)
    end
    function Tap:onTapDockAI()
        if self.callback then self.callback() end
        return true
    end
    tap_class = Tap
    return Tap
end

function DockAI:buildPane(instance, context)
    local Blitbuffer = require("ffi/blitbuffer")
    local Device = require("device")
    local Font = require("ui/font")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local Geom = require("ui/geometry")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local ScrollHtmlWidget = require("ui/widget/scrollhtmlwidget")
    local TextWidget = require("ui/widget/textwidget")
    local UIManager = require("ui/uimanager")
    local ConfirmBox = require("ui/widget/confirmbox")
    local Widget = require("ui/widget/widget")
    local WidgetContainer = require("ui/widget/container/widgetcontainer")
    local Keyboard = require("appdock_keyboard")

    local function scale(value) return Device.screen:scaleBySize(value) end
    local width, height = context.dimen.w, context.dimen.h

    ------------------------------------------------------------------
    -- State (survives rebuilds of the pane; chats are also stored on disk)
    ------------------------------------------------------------------
    local state = instance.dockai_state
    if state and not state.current then state = nil end   -- state of an older release
    if not state then
        local chats = self:loadChats()
        local wanted = self:_get("current_chat")
        local current
        for _, chat in ipairs(chats) do if chat.id == wanted then current = chat; break end end
        if not current and wanted == nil then current = chats[1] end
        state = { chats = chats, current = current or self:newChat(), draft = "", busy = false, sidebar = false, sidebar_page = 1 }
        instance.dockai_state = state
    end
    -- A reply that never came back must not lock the pane for good.
    if state.busy and (self.now() - (state.busy_since or 0)) > 150 then state.busy = false end

    local function rebuild() if context.requestRebuild then pcall(context.requestRebuild, "ui") end end

    -- Colours: pure black on white like ChatGPT; greys for the secondary parts.
    local BLACK, WHITE = Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_WHITE
    local function gray(level) return Blitbuffer.Color8(math.floor(255 * level + 0.5)) end
    local PILL = gray(0.93)
    local MUTED = Blitbuffer.COLOR_DARK_GRAY
    local HAIRLINE = gray(0.82)

    local function blank(w, h) return Widget:new{ dimen = Geom:new{ w = w, h = h } } end
    local function box(w, h, background, radius, border, border_color)
        return FrameContainer:new{
            width = w, height = h, padding = 0, margin = 0, bordersize = border or 0,
            color = border_color or HAIRLINE, radius = radius or 0, background = background,
            blank(w, h),
        }
    end
    local function label(text, size, color, bold, max_width)
        return TextWidget:new{
            text = text, face = Font:getFace(bold and "cfont" or "smallinfofont", size),
            fgcolor = color or BLACK, bold = bold == true, padding = 0, max_width = max_width,
        }
    end

    local Tap = DockAI._tapClass(blank)
    local info = self:usage()

    -- Every tap runs guarded: an error becomes a short message instead of a
    -- dead button, and can never leave the pane stuck in the "busy" state.
    local function guarded(fn)
        return function(...)
            local ok, err = pcall(fn, ...)
            if not ok then
                state.busy = false
                self:_toast("DockAI: " .. tostring(err):gsub("%s+", " "):sub(1, 140))
            end
        end
    end

    local function guardBusy()
        if state.busy then
            self:_toast(self:tr("DockAI antwortet gerade …", "DockAI is replying …"))
            return true
        end
        return false
    end

    ------------------------------------------------------------------
    -- Chats: saving, switching, deleting
    ------------------------------------------------------------------
    local function persist()
        local chat = state.current
        if #chat.messages > 0 then
            chat.updated = self.now()
            chat.title = DockAI.chatTitle(chat.messages)
            local known = false
            for _, item in ipairs(state.chats) do if item == chat then known = true; break end end
            if not known then table.insert(state.chats, 1, chat) end
        end
        table.sort(state.chats, function(a, b) return (a.updated or 0) > (b.updated or 0) end)
        self:saveChats(state.chats)
        self:_set("current_chat", chat.id)
        self:flush()
    end

    local function selectChat(chat)
        if guardBusy() then return end
        state.current, state.sidebar, state.draft = chat, false, ""
        self:_set("current_chat", chat.id)
        self:flush()
        rebuild()
    end

    local function startNewChat()
        if guardBusy() then return end
        if #state.current.messages > 0 then state.current = self:newChat() end   -- reuse an empty chat
        state.sidebar, state.draft = false, ""
        self:_set("current_chat", state.current.id)
        self:flush()
        rebuild()
    end

    local function deleteChat(chat)
        if guardBusy() then return end
        UIManager:show(ConfirmBox:new{
            text = string.format(self:tr("Chat „%s“ löschen?", "Delete chat “%s”?"), chat.title ~= "" and chat.title or DockAI.chatTitle(chat.messages)),
            ok_text = self:tr("Löschen", "Delete"), cancel_text = self:tr("Abbrechen", "Cancel"),
            ok_callback = function()
                for index, item in ipairs(state.chats) do
                    if item == chat then table.remove(state.chats, index); break end
                end
                if state.current == chat then state.current = self:newChat(); state.draft = "" end
                self:saveChats(state.chats)
                self:_set("current_chat", state.current.id)
                self:flush()
                rebuild()
            end,
        })
    end

    ------------------------------------------------------------------
    -- Sending
    ------------------------------------------------------------------
    local function send(text)
        text = trim(text)
        if text == "" or state.busy then return end
        local usage = self:usage()
        if usage.blocked then
            state.draft = text
            table.insert(state.current.messages, { role = "assistant", content = self:limitText(usage), error = true })
            rebuild()
            return
        end
        -- "Merk dir …" / "Remember that …" saves a permanent memory.
        local fact = DockAI.extractMemory(text)
        if fact and self:addMemory(fact) then
            self:_toast(self:tr("Erinnerung gespeichert.", "Memory saved."))
        end
        local chat = state.current
        table.insert(chat.messages, { role = "user", content = text })
        state.busy, state.busy_since, state.draft = true, self.now(), ""
        persist()
        rebuild()
        -- Let the "thinking" screen paint before the blocking request runs.
        UIManager:scheduleIn(0.3, function()
            local ok, reply, code = pcall(function() return self:complete(chat.messages) end)
            state.busy = false
            if ok and reply then
                self:recordUse()
                table.insert(chat.messages, { role = "assistant", content = reply })
            else
                local message = self:errorText(ok and code or "bad_response")
                if not ok then message = message .. " (" .. tostring(reply):gsub("%s+", " "):sub(1, 90) .. ")" end
                table.insert(chat.messages, { role = "assistant", content = message, error = true })
            end
            pcall(persist)
            rebuild()
        end)
    end

    local function openKeyboard()
        if state.busy then return end
        local usage = self:usage()
        if usage.blocked then self:showLimitInfo(); return end
        local keyboard
        keyboard = Keyboard:new{
            title = "DockAI",
            placeholder = self:tr("Nachricht an DockAI", "Message DockAI"),
            value = state.draft or "",
            multiline = true,
            on_change = function(value) state.draft = value or "" end,
            on_cancel = function() UIManager:close(keyboard); rebuild() end,
            on_submit = function(value)
                UIManager:nextTick(function()
                    UIManager:close(keyboard)
                    guarded(send)(value)
                end)
            end,
        }
        UIManager:show(keyboard)
    end

    ------------------------------------------------------------------
    -- Layout
    ------------------------------------------------------------------
    local margin = scale(14)
    local header_h = scale(56)
    local strip_h = scale(30)
    local input_h = scale(58)
    local input_gap = scale(10)
    local body_y = header_h + strip_h
    local body_h = math.max(scale(80), height - body_y - input_h - input_gap * 2)
    local round = scale(40)

    local pane = WidgetContainer:new{ dimen = Geom:new{ w = width, h = height } }
    local layers = {
        box(width, height, WHITE, 0, 0),
    }
    local function add(widget, x, y) widget.overlap_offset = { x, y }; layers[#layers + 1] = widget end
    local function tap(w, h, fn, x, y) add(Tap:new{ width = w, height = h, callback = guarded(fn) }, x, y) end
    local function centered(widget, x, y, w, h)
        add(widget, x + math.floor((w - widget:getSize().w) / 2), y + math.floor((h - widget:getSize().h) / 2))
    end

    -- The drawer: chat list, new chat, memories. While it is open only its own
    -- targets exist, so nothing underneath can swallow a tap.
    local function buildDrawer()
        local drawer_w = math.min(width - scale(56), math.max(scale(260), math.floor(width * 0.8)))
        local row_w = drawer_w - 2 * margin
        add(box(width - drawer_w, height, gray(0.72), 0, 0), drawer_w, 0)
        tap(width - drawer_w, height, function() state.sidebar = false; rebuild() end, drawer_w, 0)
        add(box(drawer_w, height, WHITE, 0, 0), 0, 0)
        add(box(1, height, gray(0.5), 0, 0), drawer_w - 1, 0)

        local heading = label("Chats", scale(21), BLACK, true)
        add(heading, margin, math.floor((header_h - heading:getSize().h) / 2))
        local close_x, close_y = drawer_w - margin - round, math.floor((header_h - round) / 2)
        add(box(round, round, WHITE, math.floor(round / 2), 1, HAIRLINE), close_x, close_y)
        centered(label("×", scale(24), BLACK, true), close_x, close_y, round, round)
        tap(round, round, function() state.sidebar = false; rebuild() end, close_x, close_y)
        add(box(drawer_w, 1, HAIRLINE, 0, 0), 0, header_h - 1)

        local new_h, new_y = scale(46), header_h + scale(10)
        add(box(row_w, new_h, WHITE, math.floor(new_h / 2), 1, HAIRLINE), margin, new_y)
        local new_label = label("✎  " .. self:tr("Neuer Chat", "New chat"), scale(14), BLACK, true, row_w - scale(32))
        add(new_label, margin + scale(18), new_y + math.floor((new_h - new_label:getSize().h) / 2))
        tap(row_w, new_h, startNewChat, margin, new_y)

        local foot_h = scale(46)
        local foot_y = height - foot_h - scale(12)
        add(box(drawer_w, 1, HAIRLINE, 0, 0), 0, foot_y - scale(8))
        add(box(row_w, foot_h, WHITE, math.floor(foot_h / 2), 1, HAIRLINE), margin, foot_y)
        local foot_label = label(string.format(self:tr("Erinnerungen (%d)", "Memories (%d)"), #self:memories()), scale(14), BLACK, false, row_w - scale(32))
        add(foot_label, margin + scale(18), foot_y + math.floor((foot_h - foot_label:getSize().h) / 2))
        tap(row_w, foot_h, function() self:showMemoryManager(rebuild) end, margin, foot_y)

        local pager_h = scale(34)
        local list_y = new_y + new_h + scale(12)
        local list_bottom = foot_y - scale(8) - pager_h
        local row_h = scale(46)
        local fit = math.max(1, math.floor((list_bottom - list_y) / row_h))
        local chats = state.chats
        local pages = math.max(1, math.ceil(#chats / fit))
        state.sidebar_page = math.min(pages, math.max(1, state.sidebar_page or 1))
        if #chats == 0 then
            add(label(self:tr("Noch keine Chats", "No chats yet"), scale(13), MUTED, false, row_w), margin + scale(4), list_y + scale(6))
        end
        local first = (state.sidebar_page - 1) * fit + 1
        for index = first, math.min(#chats, first + fit - 1) do
            local chat = chats[index]
            local y = list_y + (index - first) * row_h
            local row_inner = row_h - scale(4)
            local active = chat == state.current
            if active then add(box(row_w, row_inner, PILL, scale(12), 0), margin, y) end
            local title = label(chat.title ~= "" and chat.title or DockAI.chatTitle(chat.messages), scale(14), BLACK, active, row_w - scale(64))
            add(title, margin + scale(12), y + math.floor((row_inner - title:getSize().h) / 2))
            tap(row_w - scale(44), row_inner, function() selectChat(chat) end, margin, y)
            centered(label("×", scale(20), MUTED, true), margin + row_w - scale(44), y, scale(44), row_inner)
            tap(scale(44), row_inner, function() deleteChat(chat) end, margin + row_w - scale(44), y)
        end
        if pages > 1 then
            local pager_y = list_bottom + scale(2)
            local page_label = label(string.format("%d / %d", state.sidebar_page, pages), scale(13), MUTED)
            centered(page_label, 0, pager_y, drawer_w, pager_h)
            centered(label("‹", scale(24), BLACK, true), margin, pager_y, scale(60), pager_h)
            tap(scale(60), pager_h, function() state.sidebar_page = math.max(1, state.sidebar_page - 1); rebuild() end, margin, pager_y)
            centered(label("›", scale(24), BLACK, true), drawer_w - margin - scale(60), pager_y, scale(60), pager_h)
            tap(scale(60), pager_h, function() state.sidebar_page = math.min(pages, state.sidebar_page + 1); rebuild() end, drawer_w - margin - scale(60), pager_y)
        end
    end

    local function buildMain()
        -- Header: menu button, DockAI + model, new chat on the right.
        local menu_x, menu_y = margin - scale(4), math.floor((header_h - round) / 2)
        local bar_w, bar_h, bar_gap = scale(20), scale(2), scale(5)
        local bars_y = menu_y + math.floor((round - (bar_h * 3 + bar_gap * 2)) / 2)
        for i = 0, 2 do add(box(bar_w, bar_h, BLACK, 0, 0), menu_x + math.floor((round - bar_w) / 2), bars_y + i * (bar_h + bar_gap)) end
        tap(round + scale(8), header_h, function() state.sidebar, state.sidebar_page = true, 1; rebuild() end, menu_x - scale(4), 0)

        local title_x = menu_x + round + scale(6)
        local title = label("DockAI", scale(21), BLACK, true)
        add(title, title_x, math.floor((header_h - title:getSize().h) / 2))
        local model = label(DockAI.shortModelName(self:getModel()) .. " ⌄", scale(12), MUTED, false, math.max(scale(60), width - title_x - margin * 2 - scale(40) - title:getSize().w - round))
        add(model, title_x + title:getSize().w + scale(10), math.floor((header_h - model:getSize().h) / 2) + scale(2))
        tap(title:getSize().w + scale(10) + model:getSize().w + scale(8), header_h, function() self:showModelPicker(rebuild) end, title_x, 0)

        local new_x = width - margin - round
        add(box(round, round, WHITE, math.floor(round / 2), 1, HAIRLINE), new_x, math.floor((header_h - round) / 2))
        local pencil = label("✎", scale(18), BLACK, true)
        add(pencil, new_x + math.floor((round - pencil:getSize().w) / 2), math.floor((header_h - pencil:getSize().h) / 2))
        tap(round, round, startNewChat, new_x, math.floor((header_h - round) / 2))
        add(box(width, 1, HAIRLINE, 0, 0), 0, header_h - 1)

        -- Limit strip: always visible, with a thin usage bar.
        local strip_color = (info.blocked or info.left <= 3) and BLACK or MUTED
        local strip = label(self:limitText(info), scale(12), strip_color, info.blocked ~= nil or info.left <= 3, width - 2 * margin)
        add(strip, margin, header_h + math.floor((strip_h - strip:getSize().h) / 2) - scale(1))
        local bar_y = header_h + strip_h - scale(4)
        local usage_w = width - 2 * margin
        local fraction = math.min(1, math.max(info.day_used / math.max(1, info.day_limit), info.week_used / math.max(1, info.week_limit)))
        add(box(usage_w, scale(3), HAIRLINE, 0, 0), margin, bar_y)
        if fraction > 0 then add(box(math.max(scale(3), math.floor(usage_w * fraction)), scale(3), BLACK, 0, 0), margin, bar_y) end
        tap(width, strip_h, function() self:showLimitInfo() end, 0, header_h)

        -- Body: empty state or the transcript.
        local messages = state.current.messages
        if #messages == 0 and not state.busy then
            local greeting = label(self:tr("Wobei kann ich helfen?", "What can I help with?"), scale(24), BLACK, true, width - 2 * margin)
            local greeting_y = body_y + math.floor(body_h * .16)
            add(greeting, math.floor((width - greeting:getSize().w) / 2), greeting_y)
            local suggestions = {
                self:tr("Erkläre mir ein Thema einfach", "Explain a topic simply"),
                self:tr("Hilf mir, eine E-Mail zu schreiben", "Help me write an email"),
                self:tr("Gib mir ein kurzes Quiz", "Give me a short quiz"),
                self:tr("Empfiehl mir ein Buch", "Recommend me a book"),
            }
            local prompts = {
                self:tr("Erkläre mir ein spannendes Thema in einfachen Worten.", "Explain an interesting topic to me in simple words."),
                self:tr("Hilf mir, eine freundliche, kurze E-Mail zu schreiben. Frag mich, worum es geht.", "Help me write a short, friendly email. Ask me what it is about."),
                self:tr("Stelle mir ein kurzes Quiz mit 3 Fragen zu einem Thema deiner Wahl.", "Give me a short 3-question quiz on a topic of your choice."),
                self:tr("Empfiehl mir ein gutes Buch und sag kurz, warum.", "Recommend me a good book and say briefly why."),
            }
            local chip_h = scale(46)
            local chip_y = greeting_y + greeting:getSize().h + scale(26)
            for index, text in ipairs(suggestions) do
                local chip_w = width - 2 * margin
                if chip_y + chip_h > body_y + body_h then break end
                add(box(chip_w, chip_h, WHITE, math.floor(chip_h / 2), 1, HAIRLINE), margin, chip_y)
                local chip_label = label(text, scale(14), BLACK, false, chip_w - scale(32))
                add(chip_label, margin + scale(18), chip_y + math.floor((chip_h - chip_label:getSize().h) / 2))
                tap(chip_w, chip_h, function() send(prompts[index]) end, margin, chip_y)
                chip_y = chip_y + chip_h + scale(10)
            end
            local note = label(string.format(self:tr("Du hast %d Nachrichten heute und %d diese Woche übrig.", "You have %d messages left today and %d this week."), info.day_left, info.week_left), scale(12), MUTED, false, width - 2 * margin)
            if chip_y + note:getSize().h < body_y + body_h then
                add(note, math.floor((width - note:getSize().w) / 2), chip_y + scale(6))
                if #self:memories() == 0 then
                    local hint = label(self:tr("Tipp: „Merk dir …“ speichert etwas dauerhaft.", "Tip: “Remember that …” saves something permanently."), scale(12), MUTED, false, width - 2 * margin)
                    if chip_y + note:getSize().h + hint:getSize().h + scale(12) < body_y + body_h then
                        add(hint, math.floor((width - hint:getSize().w) / 2), chip_y + note:getSize().h + scale(12))
                    end
                end
            end
        else
            local scroll = ScrollHtmlWidget:new{
                html_body = transcriptHtml(self, messages, state.busy), css = CSS,
                width = width - 2 * margin, height = body_h,
                default_font_size = scale(16), dialog = context.host,
            }
            scroll.overlap_offset = { margin, body_y }
            layers[#layers + 1] = scroll
            pcall(function() scroll:scrollToRatio(1) end)
        end

        -- Input pill with the send button, like ChatGPT.
        local input_y = height - input_h - input_gap
        local send_size = scale(42)
        local pill_w = width - 2 * margin
        add(box(pill_w, input_h, PILL, math.floor(input_h / 2), 0), margin, input_y)
        local blocked = info.blocked ~= nil
        local placeholder
        if state.busy then placeholder = self:tr("DockAI antwortet …", "DockAI is replying …")
        elseif blocked then placeholder = self:limitText(info)
        elseif (state.draft or "") ~= "" then placeholder = (state.draft:gsub("%s+", " "))
        else placeholder = self:tr("Nachricht an DockAI", "Message DockAI") end
        local placeholder_widget = label(placeholder, scale(15), (state.draft or "") ~= "" and BLACK or MUTED, false, pill_w - send_size - scale(44))
        add(placeholder_widget, margin + scale(20), input_y + math.floor((input_h - placeholder_widget:getSize().h) / 2))
        tap(pill_w - send_size - scale(8), input_h, openKeyboard, margin, input_y)
        local send_x = margin + pill_w - send_size - math.floor((input_h - send_size) / 2)
        local send_y = input_y + math.floor((input_h - send_size) / 2)
        local active = (state.draft or "") ~= "" and not state.busy and not blocked
        add(box(send_size, send_size, active and BLACK or gray(0.75), math.floor(send_size / 2), 0), send_x, send_y)
        local arrow = label("↑", scale(20), WHITE, true)
        add(arrow, send_x + math.floor((send_size - arrow:getSize().w) / 2), send_y + math.floor((send_size - arrow:getSize().h) / 2))
        tap(send_size, send_size, function()
            if active then send(state.draft) else openKeyboard() end
        end, send_x, send_y)
    end

    if state.sidebar then buildDrawer() else buildMain() end

    local group = OverlapGroup:new{ dimen = pane.dimen, allow_mirroring = false }
    for _, layer in ipairs(layers) do table.insert(group, layer) end
    pane[1] = group
    pane.dockai_layout = { messages = #state.current.messages, busy = state.busy, blocked = info.blocked, sidebar = state.sidebar }
    return pane
end

return require("appdock_dockai_proxy")(DockAI)
