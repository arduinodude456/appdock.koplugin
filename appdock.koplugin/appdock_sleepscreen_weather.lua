-- Optional, user-triggered Open-Meteo fetch for custom sleep-screen widgets.
-- The renderer never performs network I/O; callers persist the returned cache.
local Weather = {}

local function coordinate(value, minimum, maximum)
    local number = tonumber(value)
    if not number or number ~= number or number < minimum or number > maximum then return nil end
    return string.format("%.4f", number)
end

function Weather.fetch(latitude, longitude)
    latitude = coordinate(latitude, -90, 90)
    longitude = coordinate(longitude, -180, 180)
    if not latitude or not longitude then return nil, "Enter a valid latitude and longitude." end

    local ok_https, https = pcall(require, "ssl.https")
    local ok_ltn12, ltn12 = pcall(require, "ltn12")
    local ok_json, JSON = pcall(require, "json")
    local ok_socketutil, socketutil = pcall(require, "socketutil")
    if not ok_https or not ok_ltn12 or not ok_json then return nil, "HTTPS/JSON support is unavailable." end

    local chunks, length = {}, 0
    local function sink(chunk, err)
        if err then return nil, err end
        if chunk then
            length = length + #chunk
            if length > 65536 then return nil, "Weather response is too large." end
            chunks[#chunks + 1] = chunk
        end
        return 1
    end
    if ok_socketutil and socketutil.set_timeout then socketutil:set_timeout(8, 15) end
    local request_ok, response_ok, code = pcall(https.request, {
        url = "https://api.open-meteo.com/v1/forecast?latitude=" .. latitude .. "&longitude=" .. longitude .. "&current=temperature_2m,weather_code&temperature_unit=celsius&timezone=auto",
        method = "GET", sink = sink, headers = { ["accept"] = "application/json", ["user-agent"] = "AppDock-Sleepscreen/1.0" },
    })
    if ok_socketutil and socketutil.reset_timeout then socketutil:reset_timeout() end
    if not request_ok or not response_ok or tonumber(code) ~= 200 then return nil, "Weather service unavailable (HTTP " .. tostring(code or "network error") .. ")." end
    local decoded_ok, response = pcall(JSON.decode, table.concat(chunks), JSON.decode.simple)
    local current = decoded_ok and type(response) == "table" and response.current
    local temperature = type(current) == "table" and tonumber(current.temperature_2m)
    local weather_code = type(current) == "table" and tonumber(current.weather_code)
    if not temperature or not weather_code then return nil, "Weather service returned incomplete data." end
    local descriptions = {
        [0] = "Clear", [1] = "Mostly clear", [2] = "Partly cloudy", [3] = "Overcast",
        [45] = "Fog", [48] = "Rime fog", [51] = "Light drizzle", [53] = "Drizzle", [55] = "Heavy drizzle",
        [56] = "Freezing drizzle", [57] = "Heavy freezing drizzle", [61] = "Light rain", [63] = "Rain", [65] = "Heavy rain",
        [66] = "Freezing rain", [67] = "Heavy freezing rain", [71] = "Light snow", [73] = "Snow", [75] = "Heavy snow",
        [77] = "Snow grains", [80] = "Rain showers", [81] = "Heavy showers", [82] = "Violent showers",
        [85] = "Snow showers", [86] = "Heavy snow showers", [95] = "Thunderstorm", [96] = "Thunderstorm with hail", [99] = "Heavy thunderstorm with hail",
    }
    return { temperature = string.format("%.1f°C", temperature), description = descriptions[weather_code] or ("Weather " .. tostring(weather_code)),
        updated = os.date("%Y-%m-%d %H:%M") }
end

return Weather
