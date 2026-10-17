-- Local AppDock migration over the same Wi-Fi network.
-- The listener exists only for one transfer and accepts one-time pairing codes.
local JSON = require("json")
local DataStorage = require("datastorage")
local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
if not ok_lfs then lfs = require("lfs") end
local Transfer = {}
Transfer.PORT = 47621
Transfer.PROTOCOL = 1
Transfer.MAX_ASSET_BYTES = 2 * 1024 * 1024
Transfer.MAX_TOTAL_ASSET_BYTES = 8 * 1024 * 1024
Transfer.SETTINGS_KEYS = {
    "appdock_homescreen", "appdock_dchat_v1", "language", "night_mode",
}
local function randomCode()
    local file = io.open("/dev/urandom", "rb")
    local data = file and file:read(6) or nil
    if file then file:close() end
    if not data then return tostring(math.random(100000, 999999)) end
    local number = 0
    for index = 1, #data do number = (number * 257 + data:byte(index)) % 900000 end
    return string.format("%06d", number + 100000)
end
local function socketLib()
    local ok, socket = pcall(require, "socket")
    if not ok or not socket then return nil, "LuaSocket is unavailable." end
    return socket
end
local function readLine(client)
    local line, err = client:receive("*l")
    if not line then return nil, err or "The transfer connection closed." end
    if #line > 16 * 1024 * 1024 then return nil, "The transfer payload is too large." end
    return line
end
local function sendLine(client, value)
    local ok, err = client:send(value .. "\n")
    if not ok then return nil, err or "The transfer connection could not be written." end
    return true
end
local function base64Encode(data)
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local output = {}
    for index = 1, #data, 3 do
        local a, b, c = data:byte(index, index + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        output[#output + 1] = alphabet:sub(math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1)
            .. alphabet:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
            .. (b and alphabet:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1) or "=")
            .. (c and alphabet:sub(n % 64 + 1, n % 64 + 1) or "=")
    end
    return table.concat(output)
end
local function base64Decode(data)
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local output = {}
    data = tostring(data or ""):gsub("%s", "")
    if data == "" or #data % 4 ~= 0 or data:find("[^%w%+/=]") then return nil end
    for index = 1, #data, 4 do
        local a, b, c, d = data:sub(index, index + 3):match("^(%S)(%S)(%S)(%S)$")
        local va, vb = alphabet:find(a, 1, true), alphabet:find(b, 1, true)
        if not va or not vb then return nil end
        local vc = c == "=" and 0 or (alphabet:find(c, 1, true) or 0) - 1
        local vd = d == "=" and 0 or (alphabet:find(d, 1, true) or 0) - 1
        local n = (va - 1) * 262144 + (vb - 1) * 4096 + vc * 64 + vd
        output[#output + 1] = string.char(math.floor(n / 65536) % 256)
        if c ~= "=" then output[#output + 1] = string.char(math.floor(n / 256) % 256) end
        if d ~= "=" then output[#output + 1] = string.char(n % 256) end
    end
    return table.concat(output)
end
local function addCandidate(candidates, seen, path)
    if type(path) ~= "string" or path == "" or seen[path] then return end
    local file = io.open(path, "rb")
    if not file then return end
    local data = file:read(Transfer.MAX_ASSET_BYTES + 1)
    file:close()
    if type(data) ~= "string" or #data > Transfer.MAX_ASSET_BYTES then return end
    seen[path] = true
    candidates[#candidates + 1] = { source_path = path, name = path:match("([^/]+)$") or "asset", data = base64Encode(data) }
end
local function collectAssets(settings)
    local candidates, seen, total = {}, {}, 0
    local appdock = settings.appdock_homescreen
    local function candidate(path)
        if #candidates >= 16 or total >= Transfer.MAX_TOTAL_ASSET_BYTES then return end
        local before = #candidates
        addCandidate(candidates, seen, path)
        if #candidates > before then total = total + math.floor(#candidates[#candidates].data * 0.75) end
    end
    if type(appdock) == "table" then
        candidate(appdock.wallpaper and appdock.wallpaper.path)
        for _, path in pairs(appdock.plugin_logos or {}) do candidate(path) end
        for _, design in pairs((appdock.design or {}).installed or {}) do
            if type(design) == "table" then candidate(design.file); candidate(design.wallpaper_file) end
        end
    end
    return candidates
end
local function rewritePaths(value, path_map)
    if type(value) == "string" then return path_map[value] or value end
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = rewritePaths(item, path_map) end
    return result
end
function Transfer.collect()
    local settings = {}
    for _, key in ipairs(Transfer.SETTINGS_KEYS) do settings[key] = G_reader_settings:readSetting(key, nil) end
    return { protocol = Transfer.PROTOCOL, source = "AppDock", created_at = os.time(), settings = settings, assets = collectAssets(settings) }
end
function Transfer.apply(payload)
    if type(payload) ~= "table" or tonumber(payload.protocol) ~= Transfer.PROTOCOL then return false, "Unsupported AppDock backup format." end
    if type(payload.settings) ~= "table" then return false, "The backup contains no settings." end
    local path_map, imported = {}, 0
    local asset_root = DataStorage:getDataDir() .. "/appdock_migration_assets"
    pcall(lfs.mkdir, asset_root)
    for index, asset in ipairs(type(payload.assets) == "table" and payload.assets or {}) do
        if index > 16 or type(asset) ~= "table" or type(asset.data) ~= "string" then break end
        local bytes = base64Decode(asset.data)
        local name = tostring(asset.name or ("asset_" .. index)):gsub("[^%w%._%-]", "_"):sub(1, 96)
        if bytes and #bytes <= Transfer.MAX_ASSET_BYTES then
            local target = asset_root .. "/" .. name
            local file = io.open(target, "wb")
            if file then file:write(bytes); file:close(); path_map[asset.source_path] = target end
        end
    end
    for _, key in ipairs(Transfer.SETTINGS_KEYS) do
        if payload.settings[key] ~= nil then
            G_reader_settings:saveSetting(key, rewritePaths(payload.settings[key], path_map))
            imported = imported + 1
        end
    end
    return imported > 0, imported > 0 and ("Imported " .. tostring(imported) .. " AppDock data groups.") or "The backup contained no supported data."
end
function Transfer.startSender(code, timeout)
    local socket, err = socketLib()
    if not socket then return nil, err end
    local server, bind_err = socket.bind("*", Transfer.PORT)
    if not server then return nil, bind_err or "The migration port is unavailable." end
    server:settimeout(timeout or 120)
    local actual_port = select(2, server:getsockname()) or Transfer.PORT
    local client, accept_err = server:accept()
    if not client then server:close(); return nil, accept_err or "No device connected." end
    client:settimeout(timeout or 120)
    local request_line, request_err = readLine(client)
    if not request_line then client:close(); server:close(); return nil, request_err end
    local ok_request, request = pcall(JSON.decode, request_line, JSON.decode.simple)
    if not ok_request or type(request) ~= "table" or request.code ~= code then
        sendLine(client, JSON.encode({ ok = false, error = "Invalid pairing code." }))
        client:close(); server:close(); return nil, "The pairing code was rejected." end
    local ok_send, send_err = sendLine(client, JSON.encode({ ok = true, payload = Transfer.collect() }))
    client:close(); server:close()
    if not ok_send then return nil, send_err end
    return true, actual_port
end
function Transfer.receive(ip, code, timeout)
    local socket, err = socketLib()
    if not socket then return nil, err end
    if type(ip) ~= "string" or not ip:match("^[%w%.%-:]+$") then return nil, "Invalid source device address." end
    local client, connect_err = socket.tcp()
    if not client then return nil, connect_err end
    client:settimeout(timeout or 30)
    local connected, err_connect = client:connect(ip, Transfer.PORT)
    if not connected then client:close(); return nil, err_connect or "Could not connect to the source device." end
    local request_ok, request_err = sendLine(client, JSON.encode({ protocol = Transfer.PROTOCOL, code = tostring(code or "") }))
    if not request_ok then client:close(); return nil, request_err end
    local response_line, response_err = readLine(client)
    client:close()
    if not response_line then return nil, response_err end
    local ok_response, response = pcall(JSON.decode, response_line, JSON.decode.simple)
    if not ok_response or type(response) ~= "table" then return nil, "The source device returned invalid data." end
    if response.ok ~= true then return nil, response.error or "The pairing code was rejected." end
    if type(response.payload) ~= "table" then return nil, "The source device sent no backup." end
    if tonumber(response.payload.protocol) ~= Transfer.PROTOCOL then return nil, "Unsupported AppDock backup format." end
    return response.payload
end
Transfer.newCode = randomCode
Transfer._test = { randomCode = randomCode, collect = Transfer.collect, apply = Transfer.apply }
return Transfer
