-- AppDock-owned Bluetooth controls.
--
-- This is an independent implementation. It supports Kobo's standard BlueZ
-- D-Bus API and the Kobo MediaTek service used by Libra Colour devices. It
-- does not depend on audiobook.koplugin or on bluetoothctl being installed.
local UIManager = require("ui/uimanager")
local ButtonDialog = require("ui/widget/buttondialog")
local InfoMessage = require("ui/widget/infomessage")

local Bluetooth = {}
local DESTINATION = "org.bluez"
local ADAPTER = "/org/bluez/hci0"
local ADAPTER_IFACE = "org.bluez.Adapter1"
local DEVICE_IFACE = "org.bluez.Device1"
local PROPERTIES = "org.freedesktop.DBus.Properties"
local OBJECT_MANAGER = "org.freedesktop.DBus.ObjectManager"

local function has_command(command)
    local pipe = io.popen("command -v " .. command .. " 2>/dev/null", "r")
    if not pipe then return false end
    local result = pipe:read("*l") or ""
    pipe:close()
    return result ~= ""
end

local function dbus(command)
    if not has_command("dbus-send") then return "", false end
    local pipe = io.popen(command .. " 2>&1; echo __APPDOCK_BT_EXIT:$?", "r")
    if not pipe then return "", false end
    local output = pipe:read("*a") or ""
    pipe:close()
    local code = output:match("__APPDOCK_BT_EXIT:(%d+)%s*$")
    output = output:gsub("__APPDOCK_BT_EXIT:%d+%s*$", "")
    return output, code == "0"
end

local function detect_destination()
    if not has_command("dbus-send") then return nil end
    local output, ok = dbus("dbus-send --system --print-reply --reply-timeout=1500 " ..
        "--dest=org.freedesktop.DBus /org/freedesktop/DBus " ..
        "org.freedesktop.DBus.NameHasOwner string:'com.kobo.mtk.bluedroid'")
    if ok and output:match("boolean true") then return "com.kobo.mtk.bluedroid" end
    local _, bluez_ok = dbus("dbus-send --system --print-reply --reply-timeout=1500 " ..
        "--dest=org.freedesktop.DBus /org/freedesktop/DBus " ..
        "org.freedesktop.DBus.NameHasOwner string:'org.bluez'")
    if bluez_ok then return "org.bluez" end
    return nil
end

local function command(method, path, arguments)
    return string.format("dbus-send --system --print-reply --reply-timeout=5000 --dest=%s %s %s %s",
        DESTINATION, path, method, arguments or "")
end

local function get_property(path, iface, property)
    return dbus(command(PROPERTIES .. ".Get", path,
        string.format("string:'%s' string:'%s'", iface, property)))
end

local function set_powered(value)
    return dbus(command(PROPERTIES .. ".Set", ADAPTER,
        string.format("string:'%s' string:'Powered' variant:boolean:%s", ADAPTER_IFACE, value and "true" or "false")))
end

local function is_powered()
    local output, ok = get_property(ADAPTER, ADAPTER_IFACE, "Powered")
    return ok and output:match("boolean true") ~= nil
end

local function device_path(address)
    return "/org/bluez/hci0/dev_" .. address:gsub(":", "_")
end

local function list_devices()
    local output, ok = dbus(command(OBJECT_MANAGER .. ".GetManagedObjects", "/", ""))
    if not ok then return {} end
    local devices = {}
    local path
    local current
    for line in output:gmatch("[^\n]+") do
        local found = line:match("object path (.*)")
        if found then
            path = found:gsub("%s+$", "")
            current = path:match("/dev_([%x_]+)$") and { path = path, name = "", address = path:match("/dev_(.+)$"):gsub("_", ":") } or nil
            if current then devices[#devices + 1] = current end
        elseif current and line:match('string "Name"') then
            current._next = "name"
        elseif current and line:match('string "Alias"') then
            current._next = "alias"
        elseif current and line:match('string "Connected"') then
            current._next = "connected"
        elseif current and line:match('string "Paired"') then
            current._next = "paired"
        elseif current and current._next and line:match('string "(.-)"') then
            local value = line:match('string "(.-)"')
            if current._next == "name" or (current._next == "alias" and current.name == "") then current.name = value end
            current._next = nil
        elseif current and current._next and line:match("boolean (true|false)") then
            local value = line:match("boolean (true|false)") == "true"
            if current._next == "connected" then current.connected = value end
            if current._next == "paired" then current.paired = value end
            current._next = nil
        end
    end
    return devices
end

local function notify(text)
    UIManager:show(InfoMessage:new{ text = text, timeout = 5 })
end

function Bluetooth.show()
    local destination = detect_destination()
    if not destination then
        notify("Bluetooth ist auf diesem Gerät nicht verfügbar: Kein BlueZ-/Kobo-Bluetooth-D-Bus-Dienst gefunden.")
        return
    end
    DESTINATION = destination
    local on = is_powered()
    local dialog
    local buttons = {
        { { text = on and "Bluetooth ausschalten" or "Bluetooth einschalten", callback = function()
            local _, ok = set_powered(not on)
            UIManager:close(dialog)
            if ok then Bluetooth.show() else notify("Bluetooth konnte nicht umgeschaltet werden.") end
        end } },
    }
    if on then
        buttons[#buttons + 1] = { { text = "Nach Geräten suchen", callback = function()
            local _, ok = dbus(command(ADAPTER_IFACE .. ".StartDiscovery", ADAPTER))
            UIManager:close(dialog)
            notify(ok and "Bluetooth-Suche gestartet. Öffne die Einstellungen erneut für Ergebnisse." or "Bluetooth-Suche konnte nicht gestartet werden.")
        end } }
        for _, device in ipairs(list_devices()) do
            local label = (device.name ~= "" and device.name or device.address)
            buttons[#buttons + 1] = { { text = (device.connected and "Trennen: " or "Verbinden: ") .. label, callback = function()
                local method = device.connected and DEVICE_IFACE .. ".Disconnect" or DEVICE_IFACE .. ".Connect"
                local _, ok = dbus(command(method, device.path))
                UIManager:close(dialog)
                notify(ok and ((device.connected and "Getrennt: " or "Verbunden: ") .. label) or "Bluetooth-Geräteaktion fehlgeschlagen.")
            end } }
        end
    end
    buttons[#buttons + 1] = { { text = "AppDock-eigene Bluetooth-Steuerung", enabled = false } }
    buttons[#buttons + 1] = { { text = "Schließen", callback = function() UIManager:close(dialog) end } }
    dialog = ButtonDialog:new{ title = "Bluetooth (" .. (destination == "com.kobo.mtk.bluedroid" and "Kobo MTK" or "BlueZ") .. ")", buttons = buttons, rows_per_page = { 5, 7 } }
    UIManager:show(dialog)
end

return Bluetooth
