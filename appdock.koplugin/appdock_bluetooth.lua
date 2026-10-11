local UIManager = require("ui/uimanager")
local AppDockDialogs = require("appdock_dialogs")
local ButtonDialog, InfoMessage = AppDockDialogs.ButtonDialog, AppDockDialogs.InfoMessage
local BT = {}
local manager
local function path() return (debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "") .. "btmanager.lua" end
local function get()
    if manager then return manager end
    local ok, value = pcall(dofile, path())
    if not ok or type(value) ~= "table" then return nil end
    manager = setmetatable({}, { __index = value })
    return manager
end
function BT.show()
    local bt = get()
    if not bt then UIManager:show(InfoMessage:new{ text = "Bluetooth ist auf diesem Gerät nicht verfügbar." }); return end
    local powered_ok, powered_value = pcall(bt.isPowered, bt)
    local powered = powered_ok and powered_value == true
    local dialog
    local buttons = {{ text = powered and "Bluetooth ausschalten" or "Bluetooth einschalten", callback = function() if powered then bt:powerOff() else bt:powerOn() end; UIManager:close(dialog); BT.show() end }}
    if powered then
        table.insert(buttons, { text = "Nach Geräten suchen", callback = function() bt:startDiscovery(); UIManager:close(dialog); BT.show() end })
        local ok, devices = pcall(bt.listAudioDevices, bt)
        if ok and devices then for _, dev in ipairs(devices) do
            local name = (dev.name and dev.name ~= "" and dev.name or dev.address)
            table.insert(buttons, { text = (dev.connected and "Trennen: " or "Verbinden: ") .. name, callback = function() if dev.connected then bt:disconnect(dev.address) else bt:connect(dev.address) end; UIManager:close(dialog); BT.show() end })
        end end
    end
    table.insert(buttons, { text = "Hinweis: Bluetooth-Code aus audiobook.koplugin (nicht von AppDock)", enabled = false })
    table.insert(buttons, { text = "Schließen", callback = function() UIManager:close(dialog) end })
    dialog = ButtonDialog:new{ title = "Bluetooth", buttons = buttons, rows_per_page = { 5, 7 } }
    UIManager:show(dialog)
end
return BT
