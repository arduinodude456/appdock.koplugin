-- AppDock-owned Bluetooth controls.
--
-- This module intentionally uses only the device's standard bluetoothctl
-- command interface. It does not copy or link to another plugin's source.
-- Pairing and firmware initialization remain the responsibility of the
-- device's Bluetooth stack.
local UIManager = require("ui/uimanager")
local AppDockDialogs = require("appdock_dialogs")
local ButtonDialog = AppDockDialogs.ButtonDialog
local InfoMessage = AppDockDialogs.InfoMessage
local Bluetooth = {}

local function commandAvailable()
    local pipe = io.popen("command -v bluetoothctl 2>/dev/null", "r")
    if not pipe then return false end
    local path = pipe:read("*l") or ""
    pipe:close()
    return path ~= ""
end

local function shellQuote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function run(arguments)
    if not commandAvailable() then return nil, "bluetoothctl" end
    local pipe = io.popen("timeout 10 bluetoothctl " .. arguments .. " 2>/dev/null", "r")
    if not pipe then return nil, "Bluetooth konnte nicht gestartet werden." end
    local output = pipe:read("*a") or ""
    local ok = pipe:close()
    return output, ok and nil or "Bluetooth-Befehl fehlgeschlagen."
end

local function powered()
    local output = run("show")
    if not output then return nil end
    return output:match("Powered:%s*yes") ~= nil
end

local function devices()
    local output = run("devices") or ""
    local result = {}
    for address, name in output:gmatch("Device%s+([%x:]+)%s+(.+)") do
        result[#result + 1] = { address = address, name = name:gsub("%s+$", "") }
    end
    local paired = run("paired-devices") or ""
    for address in paired:gmatch("Device%s+([%x:]+)") do
        for _, device in ipairs(result) do
            if device.address == address then device.paired = true end
        end
    end
    return result
end

local function notify(text)
    UIManager:show(InfoMessage:new{ text = text, timeout = 4 })
end

function Bluetooth.show()
    if not commandAvailable() then
        notify("Bluetooth ist auf diesem Gerät nicht verfügbar. bluetoothctl wurde nicht gefunden.")
        return
    end
    local is_on = powered() == true
    local dialog
    local buttons = {
        { { text = is_on and "Bluetooth ausschalten" or "Bluetooth einschalten", callback = function()
            local _, err = run(is_on and "power off" or "power on")
            UIManager:close(dialog)
            if err then notify(err) else Bluetooth.show() end
        end } },
    }
    if is_on then
        buttons[#buttons + 1] = { { text = "Nach Geräten suchen", callback = function()
            run("scan on")
            UIManager:close(dialog)
            notify("Bluetooth-Suche gestartet. Öffne die Einstellungen erneut, um neue Geräte zu sehen.")
        end } }
        for _, device in ipairs(devices()) do
            local label = device.name ~= "" and device.name or device.address
            buttons[#buttons + 1] = { { text = "Verbinden: " .. label, callback = function()
                local _, err = run("connect " .. shellQuote(device.address))
                UIManager:close(dialog)
                notify(err or ("Verbunden mit " .. label .. "."))
            end } }
            buttons[#buttons + 1] = { { text = "Trennen: " .. label, callback = function()
                local _, err = run("disconnect " .. shellQuote(device.address))
                UIManager:close(dialog)
                notify(err or ("Verbindung mit " .. label .. " getrennt."))
            end } }
        end
    end
    buttons[#buttons + 1] = { { text = "AppDock-eigene Bluetooth-Steuerung", enabled = false } }
    buttons[#buttons + 1] = { { text = "Schließen", callback = function() UIManager:close(dialog) end } }
    dialog = ButtonDialog:new{ title = "Bluetooth", buttons = buttons, rows_per_page = { 5, 7 } }
    UIManager:show(dialog)
end

return Bluetooth
