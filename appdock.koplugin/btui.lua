-- Imported from audiobook.koplugin by stradichenko; see BLUETOOTH_LICENSE_NOTICE.md.
--[[--
Bluetooth UI functions for the Audiobook plugin.
Handles BT device menus, connect/disconnect, scan, and
the disconnect alert watcher.

All functions take `plugin` (the Audiobook WidgetContainer instance)
as their first parameter to access settings, bt_manager, etc.

@module btui
--]]

local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local BtUI = {}

--- Build the BT disconnect alert interval submenu.
function BtUI.buildBTDisconnectMenu(plugin)
    local options = {
        { label = _("Off"),  value = 0 },
        { label = _("15 s"), value = 15 },
        { label = _("30 s"), value = 30 },
        { label = _("60 s"), value = 60 },
    }
    local items = {}
    for _, opt in ipairs(options) do
        table.insert(items, {
            text = opt.label,
            checked_func = function()
                return plugin:getSetting("bt_disconnect_check", 30) == opt.value
            end,
            callback = function()
                plugin:setSetting("bt_disconnect_check", opt.value)
            end,
        })
    end
    return items
end

--- Top-level label for the Bluetooth menu entry.
-- Shows connected device name when available.
function BtUI.btMenuLabel(plugin)
    local bt = plugin.bt_manager
    if not bt then
        return _("Bluetooth (unavailable)")
    end
    -- On Kindle, BT is managed by the OS; show simple status
    if bt:getStackType() == "kindle" then
        local powered = bt:isPowered()
        return powered and _("Bluetooth (Kindle)") or _("Bluetooth (off)")
    end
    if not bt:isPowered() then
        return _("Bluetooth (off)")
    end
    -- Find a connected device to show its name
    local devices = bt:listAudioDevices()
    for _i, dev in ipairs(devices) do
        if dev.connected then
            local dname = dev.name ~= "" and dev.name or dev.address
            return T(_("BT: %1"), dname)
        end
    end
    -- Powered but nothing connected
    local saved = plugin:getSetting("bt_device_name", nil)
    if saved then
        return T(_("BT: %1 (not connected)"), saved)
    end
    return _("Bluetooth (on)")
end

function BtUI.buildBluetoothMenu(plugin)
    local bt = plugin.bt_manager
    local menu = {}

    if not bt then
        table.insert(menu, {
            text = _("Bluetooth unavailable"),
            enabled = false,
        })
        return menu
    end

    -- On Kindle, BT is managed by the Amazon firmware through the
    -- com.lab126.btfd LIPC service.  BTManager implements scan, pair,
    -- connect, disconnect and forget on top of it, so Kindle now uses
    -- the same device-list menu as every other platform (below).  The
    -- only Kindle-specific extra is a settings hint for pairing flows
    -- that need an on-screen confirmation dialog from the firmware.

    local powered = bt:isPowered()
    local menu = {}

    -- Power toggle
    table.insert(menu, {
        text = powered and _("Turn Bluetooth off") or _("Turn Bluetooth on"),
        callback = function()
            if powered then
                bt:powerOff()
                plugin:setSetting("bt_device_addr", nil)
                UIManager:show(InfoMessage:new{
                    text = _("Bluetooth turned off."),
                    timeout = 2,
                })
            else
                UIManager:show(InfoMessage:new{
                    text = _("Turning Bluetooth on…"),
                    timeout = 1,
                })
                local ok = bt:powerOn()
                if ok then
                    UIManager:show(InfoMessage:new{
                        text = _("Bluetooth is on."),
                        timeout = 2,
                    })
                else
                    local msg
                    if Device.isKobo and Device:isKobo() and bt:getStackType() == "bluez" then
                        msg = _("Failed to power on Bluetooth.\n\nOn some Kobo models, the Bluetooth hardware must first be initialized by the stock reading software. Please exit KOReader, pair your headphones in the Kobo library, then return to KOReader.\n\nIf Bluetooth was already working in the Kobo library, generate a bug report (Audiobook > Generate bug report) and share it on GitHub.")
                    else
                        msg = _("Failed to power on Bluetooth.")
                    end
                    UIManager:show(InfoMessage:new{
                        text = msg,
                        timeout = 8,
                    })
                end
            end
        end,
    })

    if not powered then
        return menu
    end

    -- Scan for devices
    table.insert(menu, {
        text = _("Scan for new devices..."),
        callback = function()
            BtUI.btScanAndShow(plugin)
        end,
    })

    -- List known / visible devices — single-tap to connect
    local devices = bt:listAudioDevices()
    if #devices == 0 then
        table.insert(menu, {
            text = _("No devices found. Tap Scan above."),
            enabled = false,
        })
    end
    for _, dev in ipairs(devices) do
        local label = dev.name ~= "" and dev.name or dev.address
        local icon = "  "
        if dev.connected then
            icon = "[*] "
        elseif dev.paired then
            icon = "✓ "
        end
        table.insert(menu, {
            text = icon .. label,
            -- Tap = connect (or disconnect if already connected)
            callback = function(touchmenu_instance)
                BtUI.btQuickConnect(plugin, dev, touchmenu_instance)
            end,
            -- Hold = show more actions (forget, info)
            hold_callback = function(touchmenu_instance)
                BtUI.btDeviceHoldMenu(plugin, dev, touchmenu_instance)
            end,
            checked_func = function()
                return dev.connected
            end,
        })
    end

    return menu
end

--- Quick connect/disconnect: tap on a device row in the BT menu.
function BtUI.btQuickConnect(plugin, dev, touchmenu_instance)
    local bt = plugin.bt_manager
    local name = dev.name ~= "" and dev.name or dev.address

    if dev.connected then
        -- Already connected → disconnect
        bt:disconnect(dev.address)
        dev.connected = false  -- update captured state so checked_func refreshes
        plugin:setSetting("bt_device_addr", nil)
        plugin:setSetting("bt_device_name", nil)
        UIManager:show(InfoMessage:new{
            text = T(_("Disconnected from %1."), name),
            timeout = 2,
        })
        -- Menu auto-refreshes via checked_func after callback returns
        return
    end

    -- Connecting
    UIManager:show(InfoMessage:new{
        text = T(_("Connecting to %1…\nVerifying audio…"), name),
        timeout = 8,
    })
    UIManager:scheduleIn(0.3, function()
        -- Pair first if needed
        if not dev.paired then
            local ok, err = bt:pair(dev.address)
            if ok then
                dev.paired = true
            else
                -- Pairing may report failure but the device could still be
                -- connectable (e.g. already paired from a previous session
                -- but D-Bus Paired property lagged behind).  Try connecting
                -- anyway instead of bailing out immediately.
                logger.warn("BtUI: pairing reported failure:", err,
                            "-- attempting connect anyway")
            end
        end
        local ok, err = bt:connect(dev.address)
        if ok then
            dev.connected = true  -- update captured state
            -- Remember this as the preferred device
            plugin:setSetting("bt_device_addr", dev.address)
            plugin:setSetting("bt_device_name", name)

            -- Re-probe audio player now that BT is connected and bluealsa
            -- may have been started by connect().
            local engine = plugin.tts_engine
            if engine then
                engine._cached_player = nil
                engine._no_real_audio_output = false
                engine.player_cmd = engine:findAudioPlayer()
            end

            -- Check if there's an actual audio output path to this BT device.
            -- On BlueZ Kobo without mtkbtmwrpcaudiosink, audio won't reach
            -- the headphones even if the connection succeeds.
            local has_bt_audio = engine and (
                engine.audio_player_type == "gst-bt"
                or engine.audio_player_type == "android"
                or engine.audio_player_type == "bluealsa")
            if has_bt_audio then
                UIManager:show(InfoMessage:new{
                    text = T(_("Connected to %1."), name),
                    timeout = 2,
                })
            else
                logger.warn("BtUI: BT connected but no BT audio sink found")
                UIManager:show(InfoMessage:new{
                    text = T(_("Connected to %1.\n\nNote: no Bluetooth audio sink was detected on this device. Audio may play through the internal speaker only.\n\nIf you hear no sound, your device model may not support Bluetooth audio streaming."), name),
                    timeout = 8,
                })
            end
            -- Scan for AVRCP media control input device (may appear after connect)
            UIManager:scheduleIn(2.0, function()
                local BtMediaControl = dofile(
                    (debug.getinfo(1, "S").source:match("^@(.*/)[^/]*$") or "./")
                    .. "btmediacontrol.lua")
                pcall(BtMediaControl.rescan)
            end)
        else
            logger.warn("BtUI: connection failed:", err)
            UIManager:show(InfoMessage:new{
                text = T(_("Connection failed: %1\n\nBluetooth will be turned off to prevent device standby issues."), err or "unknown"),
                timeout = 4,
            })
            -- Power off BT to prevent the Kobo standby death spiral:
            -- when BT is powered on, the kernel blocks writes to
            -- /sys/power/state, causing repeated standby failures
            -- that eventually escalate to a full device power-off.
            bt:powerOff()
        end
        -- Refresh the menu to show updated connection state
        if touchmenu_instance then
            touchmenu_instance:updateItems()
        end
    end)
end

--- Long-press on a device row: show additional actions.
function BtUI.btDeviceHoldMenu(plugin, dev, touchmenu_instance)
    local bt = plugin.bt_manager
    local name = dev.name ~= "" and dev.name or dev.address
    local ButtonDialog = require("ui/widget/buttondialog")

    local buttons = {}

    if dev.connected then
        table.insert(buttons, {{
            text = _("Disconnect"),
            callback = function()
                UIManager:close(plugin._bt_dialog)
                bt:disconnect(dev.address)
                plugin:setSetting("bt_device_addr", nil)
                plugin:setSetting("bt_device_name", nil)
                UIManager:show(InfoMessage:new{
                    text = T(_("Disconnected from %1."), name),
                    timeout = 2,
                })
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        }})
    else
        table.insert(buttons, {{
            text = _("Connect"),
            callback = function()
                UIManager:close(plugin._bt_dialog)
                BtUI.btQuickConnect(plugin, dev)
                if touchmenu_instance then
                    UIManager:scheduleIn(4, function()
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end)
                end
            end,
        }})
    end

    if dev.paired then
        table.insert(buttons, {{
            text = _("Forget (un-pair)"),
            callback = function()
                UIManager:close(plugin._bt_dialog)
                bt:remove(dev.address)
                if dev.address == plugin:getSetting("bt_device_addr", nil) then
                    plugin:setSetting("bt_device_addr", nil)
                    plugin:setSetting("bt_device_name", nil)
                end
                UIManager:show(InfoMessage:new{
                    text = T(_("Removed %1."), name),
                    timeout = 2,
                })
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        }})
    end

    table.insert(buttons, {{
        text = T(_("%1"), dev.address),
        enabled = false,
    }})

    table.insert(buttons, {{
        text = _("Cancel"),
        callback = function()
            UIManager:close(plugin._bt_dialog)
        end,
    }})

    plugin._bt_dialog = ButtonDialog:new{
        title = name,
        buttons = buttons,
    }
    UIManager:show(plugin._bt_dialog)
end

function BtUI.btScanAndShow(plugin)
    local bt = plugin.bt_manager

    -- Ensure powered
    if not bt:isPowered() then
        local ok = bt:powerOn()
        if not ok then
            local msg
            if Device.isKobo and Device:isKobo() and bt:getStackType() == "bluez" then
                msg = _("Could not power on Bluetooth.\n\nOn some Kobo models, the Bluetooth hardware must first be initialized by the stock reading software. Please exit KOReader, pair your headphones in the Kobo library, then return to KOReader.")
            else
                msg = _("Could not power on Bluetooth.")
            end
            UIManager:show(InfoMessage:new{
                text = msg,
                timeout = 8,
            })
            return
        end
    end

    UIManager:show(InfoMessage:new{
        text = _("Scanning for Bluetooth devices…\n\nPlease wait 8 seconds."),
        timeout = 2,
    })

    -- Run the scan in a deferred callback so the InfoMessage can render
    UIManager:scheduleIn(0.5, function()
        bt:startDiscovery()
        -- Wait for scan results, then stop and show device list
        UIManager:scheduleIn(8, function()
            bt:stopDiscovery()
            local devices = bt:listAudioDevices()
            local lines = {}
            for _, dev in ipairs(devices) do
                local tag = ""
                if dev.connected then
                    tag = " [*]"
                elseif dev.paired then
                    tag = " ✓"
                end
                local name = dev.name ~= "" and dev.name or dev.address
                table.insert(lines, name .. tag)
            end
            if #lines == 0 then
                table.insert(lines, _("No audio devices found."))
            end
            UIManager:show(InfoMessage:new{
                text = _("Scan complete:\n\n") .. table.concat(lines, "\n")
                    .. _("\n\nOpen the Bluetooth menu to connect."),
                timeout = 6,
            })
        end)
    end)
end

-- ── BT Disconnect Watcher ────────────────────────────────────────────

-- Start a low-frequency Bluetooth disconnect watcher while read-along
-- is active.  It checks, via D-Bus, whether any audio-related BT
-- device is still connected, and shows a notification if everything
-- disconnects.  Runs only while this plugin is in use to avoid
-- unnecessary battery drain.
function BtUI.startWatcher(plugin)
    -- On Kindle, we can't enumerate BT devices via BlueZ, so the
    -- disconnect watcher would always report "no devices". Skip it.
    if plugin.bt_manager:getStackType() == "kindle" then return end
    local interval = plugin:getSetting("bt_disconnect_check", 30)
    if interval == 0 then
        return  -- user disabled the alert
    end
    if plugin._bt_disconnect_watching then
        return
    end
    plugin._bt_disconnect_watching = true
    plugin._bt_last_connected = nil
    BtUI._scheduleBTDisconnectCheck(plugin)
end

function BtUI.stopWatcher(plugin)
    plugin._bt_disconnect_watching = false
end

function BtUI._scheduleBTDisconnectCheck(plugin)
    if not plugin._bt_disconnect_watching then
        return
    end
    -- Check at a coarse interval to keep overhead and wakeups low.
    local interval = plugin:getSetting("bt_disconnect_check", 30)
    if interval == 0 then
        plugin._bt_disconnect_watching = false
        return
    end
    UIManager:scheduleIn(interval, function()
        if not plugin._bt_disconnect_watching then
            return
        end

        local any_connected = false
        local ok, devices = pcall(plugin.bt_manager.listAudioDevices, plugin.bt_manager)
        if ok and devices then
            for _, dev in ipairs(devices) do
                if dev.connected then
                    any_connected = true
                    break
                end
            end
        end

        if plugin._bt_last_connected == nil then
            plugin._bt_last_connected = any_connected
        elseif plugin._bt_last_connected and not any_connected then
            plugin._bt_last_connected = any_connected
            UIManager:show(InfoMessage:new{
                text = _("Bluetooth audio device disconnected."),
                timeout = 4,
            })
        else
            plugin._bt_last_connected = any_connected
        end

        -- Reschedule next check while watcher is active
        if plugin._bt_disconnect_watching then
            BtUI._scheduleBTDisconnectCheck(plugin)
        end
    end)
end

return BtUI
