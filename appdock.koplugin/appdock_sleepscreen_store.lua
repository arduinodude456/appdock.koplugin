--[[--
Sleep-Screen store API client.

This module intentionally does not reuse appdock_tbs_account's private,
small-snapshot request helper: a portable Sleep-Screen package may carry up to
6 MiB of binary assets (and nearly 9 MiB JSON).  It derives the sibling Edge
Function address only from Account.get(), sends the publishable key on every
request, and sends opaque device credentials only in private write headers.
--]]--

local Account = require("appdock_tbs_account")

local Store = {}

local MAX_REQUEST_BYTES = 9 * 1024 * 1024
-- A get response wraps a valid 9 MiB package in entry metadata, so reserve a
-- small, bounded envelope rather than silently truncating a valid download.
local MAX_RESPONSE_BYTES = MAX_REQUEST_BYTES + 128 * 1024
local CONNECT_TIMEOUT = 10
local REQUEST_MAX_TIME = 45
local UUID_PATTERN = "^[%x][%x][%x][%x][%x][%x][%x][%x]%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"
local DEVICE_ID_PATTERN = "^tbs_[%w_%-]+$"
local DEVICE_SECRET_PATTERN = "^[%w_%-]+$"

local function trim(value)
    if type(value) ~= "string" then return "" end
    return value:match("^%s*(.-)%s*$") or ""
end

local function safeText(value, maximum)
    return trim(value):gsub("[%c]", ""):sub(1, maximum)
end

local function validUUID(value)
    return type(value) == "string" and value:lower():match(UUID_PATTERN) ~= nil
end

local function validEndpoint(value)
    value = trim(value):gsub("/+$", "")
    if value == "" or #value > 240 or value:find("[%c%s]") then return nil end
    local ok, socket_url = pcall(require, "socket.url")
    if not ok or not socket_url or type(socket_url.parse) ~= "function" then return nil end
    local parsed = socket_url.parse(value)
    if not parsed or parsed.scheme ~= "https" or not parsed.host or parsed.host == ""
        or parsed.userinfo or parsed.query or parsed.fragment then return nil end
    return value
end

local function endpointFor(account)
    local account_endpoint = validEndpoint(type(account) == "table" and account.endpoint or nil)
    if not account_endpoint or not account_endpoint:match("/tbs%-account$") then
        return nil, "The TBS account address cannot provide a Sleep-Screen store address."
    end
    return account_endpoint:sub(1, #account_endpoint - #"tbs-account") .. "tbs-sleepscreens"
end

local function isSignedIn(account)
    return type(account) == "table"
        and validUUID(account.account_id)
        and type(account.device_id) == "string" and #account.device_id >= 20 and #account.device_id <= 84
        and account.device_id:match(DEVICE_ID_PATTERN) ~= nil
        and type(account.device_secret) == "string" and #account.device_secret >= 32 and #account.device_secret <= 128
        and account.device_secret:match(DEVICE_SECRET_PATTERN) ~= nil
end

local function publishableKey(account)
    local key = safeText(type(account) == "table" and account.publishable_key or nil, 300)
    -- The client must never be configured to send a service/secret key.  Both
    -- current sb_publishable_* keys and legacy JWT anon keys are public keys.
    if key == "" or key:lower():find("service", 1, true) or key:lower():find("secret", 1, true) then return nil end
    if not key:match("^sb_publishable_[A-Za-z0-9_%-]+$") and not key:match("^eyJ[A-Za-z0-9_%-%.]+$") then return nil end
    return key
end

local function integer(value, minimum, maximum)
    if type(value) ~= "number" or value ~= math.floor(value) or value < minimum or value > maximum then return nil end
    return value
end

local function remoteMessage(decoded, fallback)
    local message = decoded and decoded.error and safeText(decoded.error.message, 180) or ""
    return message ~= "" and message or fallback
end

local function apiRequest(appdock, action, payload, private)
    local account = Account.get(appdock)
    local endpoint, endpoint_err = endpointFor(account)
    if not endpoint then return nil, nil, endpoint_err end
    local key = publishableKey(account)
    if not key then return nil, nil, "The Sleep-Screen store publishable key is invalid." end
    if private and not isSignedIn(account) then return nil, nil, "Sign in to a TBS account first." end

    local ok_https, https = pcall(require, "ssl.https")
    local ok_ltn12, ltn12 = pcall(require, "ltn12")
    local ok_util, socketutil = pcall(require, "socketutil")
    local ok_json, JSON = pcall(require, "json")
    if not ok_https or not ok_ltn12 or not ok_util or not ok_json then
        return nil, nil, "HTTPS or JSON support is unavailable."
    end

    -- This is deliberately shallow: package.assets can be ~8 MiB base64 and
    -- must not pass through Account.copyTree or any fixed-node copy routine.
    local request_payload = { action = action }
    for field, value in pairs(type(payload) == "table" and payload or {}) do request_payload[field] = value end
    local encoded_ok, body = pcall(JSON.encode, request_payload)
    if not encoded_ok or type(body) ~= "string" or #body > MAX_REQUEST_BYTES then
        return nil, nil, "The Sleep-Screen request is too large."
    end

    local received, chunks = 0, {}
    local function sink(chunk, sink_err)
        if sink_err then return nil, sink_err end
        if chunk then
            received = received + #chunk
            if received > MAX_RESPONSE_BYTES then return nil, "response too large" end
            chunks[#chunks + 1] = chunk
        end
        return 1
    end
    local headers = {
        ["accept"] = "application/json",
        ["content-type"] = "application/json",
        ["content-length"] = tostring(#body),
        ["user-agent"] = "AppDock-Sleepscreens/1.0",
        ["apikey"] = key,
    }
    if private then
        headers["x-tbs-account-id"] = account.account_id
        headers["x-tbs-device-id"] = account.device_id
        headers["x-tbs-device-secret"] = account.device_secret
    end

    if socketutil.set_timeout then socketutil:set_timeout(CONNECT_TIMEOUT, REQUEST_MAX_TIME) end
    local invoked, ok, code, response_headers = pcall(https.request, {
        url = endpoint,
        method = "POST",
        source = ltn12.source.string(body),
        sink = sink,
        headers = headers,
    })
    if socketutil.reset_timeout then socketutil:reset_timeout() end
    code = tonumber(code)
    local raw = table.concat(chunks)
    local decoded
    if raw ~= "" then
        local decoded_ok, value = pcall(JSON.decode, raw, JSON.decode.simple)
        if decoded_ok and type(value) == "table" then decoded = value end
    end
    if not invoked or not ok or not response_headers or not code then
        return nil, nil, "The Sleep-Screen store could not be reached. Local presets remain unchanged."
    end
    if code < 200 or code > 299 then
        return decoded, code, remoteMessage(decoded, "The Sleep-Screen store rejected the request.")
    end
    if not decoded then return nil, code, "The Sleep-Screen store returned invalid data." end
    return decoded, code
end

local function validEntry(entry)
    return type(entry) == "table"
        and validUUID(entry.id)
        and type(entry.name) == "string"
        and type(entry.description) == "string"
        and type(entry.creator) == "table"
        and validUUID(entry.creator.account_id)
        and type(entry.creator.display_name) == "string"
        and integer(entry.revision, 1, 9007199254740991) ~= nil
        and type(entry.definition) == "table"
end

function Store.list(appdock, query, offset)
    query = safeText(query, 80)
    offset = offset == nil and 0 or integer(offset, 0, 10000)
    if not offset then return nil, "The Sleep-Screen catalog page is invalid." end
    local response, _, err = apiRequest(appdock, "list", { query = query, offset = offset, limit = 12 }, false)
    if not response or err then return nil, err end
    if type(response.entries) ~= "table" or type(response.has_more) ~= "boolean" or #response.entries > 12 then
        return nil, "The Sleep-Screen store returned an invalid catalog."
    end
    for _, entry in ipairs(response.entries) do
        if not validEntry(entry) then return nil, "The Sleep-Screen store returned an invalid catalog entry." end
    end
    return { entries = response.entries, has_more = response.has_more }
end

function Store.get(appdock, id)
    id = safeText(id, 80):lower()
    if not validUUID(id) then return nil, "The Sleep-Screen ID is invalid." end
    local response, _, err = apiRequest(appdock, "get", { id = id }, false)
    if not response or err then return nil, err end
    if not validEntry(response.entry) or response.entry.id ~= id or type(response.package) ~= "table"
        or type(response.package.definition) ~= "table" or type(response.package.assets) ~= "table" then
        return nil, "The Sleep-Screen store returned an invalid download."
    end
    -- The backend is authoritative for publication status.  Do not try direct
    -- asset URLs or fall back to a stale package when it returns 404/503.
    return { entry = response.entry, package = response.package }
end

function Store.publish(appdock, package, id, expected_revision)
    if type(package) ~= "table" then return nil, "The Sleep-Screen package is invalid." end
    local payload = { package = package }
    if id ~= nil then
        id = safeText(id, 80):lower()
        expected_revision = integer(expected_revision, 1, 9007199254740991)
        if not validUUID(id) or not expected_revision then return nil, "The Sleep-Screen revision is invalid." end
        payload.id = id
        payload.expected_revision = expected_revision
    elseif expected_revision ~= nil then
        return nil, "Only an existing Sleep-Screen may have an expected revision."
    end
    local response, _, err = apiRequest(appdock, "publish", payload, true)
    if not response or err then return nil, err end
    if not validEntry(response.entry) then return nil, "The Sleep-Screen store returned an invalid publication." end
    return response.entry
end

function Store.unpublish(appdock, id, expected_revision)
    id = safeText(id, 80):lower()
    expected_revision = integer(expected_revision, 1, 9007199254740991)
    if not validUUID(id) or not expected_revision then return nil, "The Sleep-Screen revision is invalid." end
    local response, _, err = apiRequest(appdock, "unpublish", { id = id, expected_revision = expected_revision }, true)
    if not response or err then return nil, err end
    if response.ok ~= true then return nil, "The Sleep-Screen store returned an invalid withdrawal." end
    return true
end

Store._test = {
    endpointFor = endpointFor,
    isSignedIn = isSignedIn,
    publishableKey = publishableKey,
    apiRequest = apiRequest,
    MAX_REQUEST_BYTES = MAX_REQUEST_BYTES,
    MAX_RESPONSE_BYTES = MAX_RESPONSE_BYTES,
}

return Store
