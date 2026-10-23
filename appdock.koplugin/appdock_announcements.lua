--[[--
Remote AppDock announcements.

The notice document is intentionally plain JSON in the trusted AppDock
repository. It can be changed without releasing a new plugin version.
--]]
local JSON = require("json")

local Announcements = {}

Announcements.URL = "https://raw.githubusercontent.com/arduinodude456/appdock.koplugin/main/appdock_notice.json"
Announcements.MAX_BYTES = 32768

local function trim(value)
    return type(value) == "string" and (value:match("^%s*(.-)%s*$") or "") or ""
end

local function bounded(value, limit)
    value = trim(value)
    return value:sub(1, limit)
end

local function validNotice(value)
    if type(value) ~= "table" then return nil end
    local id = bounded(value.id, 96)
    local title = bounded(value.title, 96)
    local message = bounded(value.message, 900)
    if id == "" or title == "" or message == "" then return nil end
    if value.enabled == false then return nil end
    local expires = tonumber(value.expires_at)
    if expires and expires > 0 and os.time() > expires then return nil end
    return {
        id = id,
        title = title,
        message = message,
        details = bounded(value.details, 1200),
        priority = value.priority == "high" and "high" or "normal",
        source = bounded(value.source, 64),
    }
end

function Announcements.parse(body)
    if type(body) ~= "string" or #body == 0 or #body > Announcements.MAX_BYTES then return nil end
    local ok, decoded = pcall(JSON.decode, body, JSON.decode.simple)
    if not ok then return nil end
    if type(decoded) == "table" and type(decoded.notices) == "table" then
        local newest
        for _, item in ipairs(decoded.notices) do
            local notice = validNotice(item)
            if notice then newest = notice; break end
        end
        return newest
    end
    return validNotice(decoded)
end

function Announcements.fetch()
    local ok_https, https = pcall(require, "ssl.https")
    local ok_ltn12, ltn12 = pcall(require, "ltn12")
    local ok_socketutil, socketutil = pcall(require, "socketutil")
    if not ok_https or not ok_ltn12 then return nil, "HTTPS support is unavailable." end

    local chunks, length = {}, 0
    local function sink(chunk, err)
        if err then return nil, err end
        if chunk then
            length = length + #chunk
            if length > Announcements.MAX_BYTES then return nil, "Announcement is too large." end
            chunks[#chunks + 1] = chunk
        end
        return 1
    end
    if ok_socketutil and socketutil.set_timeout then socketutil:set_timeout(8, 15) end
    local url = Announcements.URL .. "?t=" .. tostring(os.time())
    local request_ok, response_ok, code = pcall(https.request, {
        url = url,
        method = "GET",
        sink = sink,
        headers = {
            ["accept"] = "application/json",
            ["cache-control"] = "no-cache",
            ["user-agent"] = "AppDock-Notice/1.0",
        },
    })
    if ok_socketutil and socketutil.reset_timeout then socketutil:reset_timeout() end
    if not request_ok or not response_ok or tonumber(code) ~= 200 then
        return nil, "Announcement service unavailable."
    end
    return Announcements.parse(table.concat(chunks))
end

return Announcements
