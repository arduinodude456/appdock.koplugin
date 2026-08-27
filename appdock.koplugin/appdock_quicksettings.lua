--[[--
AppDock's custom-drawn quick settings dropdown.
This is a KOReader overlay, not a ButtonDialog: its tiles, slider and sheet
are composed from native widget primitives and refresh their own regions.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local Theme = require("appdock_theme")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Screen = Device.screen

local QuickSettings = InputContainer:extend{
    appdock = nil,
    home = nil,
    dimen = nil,
    covers_fullscreen = false,
    sheet_height = nil,
}

local QuickTile = InputContainer:extend{
    appdock = nil,
    title = nil,
    symbol = nil,
    subtitle = nil,
    active = false,
    callback = nil,
    width = nil,
    height = nil,
    compact = false,
}

local BrightnessSlider = InputContainer:extend{
    sheet = nil,
    width = nil,
    height = nil,
    brightness = nil,
}

local NotificationRow = InputContainer:extend{
    notification = nil,
    callback = nil,
    width = nil,
    height = nil,
}

local function scale(value)
    return Screen:scaleBySize(value)
end

local function color(r, g, b, grayscale)
    if Screen:isColorEnabled() then
        return Blitbuffer.ColorRGB32(r, g, b, 0xFF)
    end
    return grayscale
end

local PALETTE = {
    sheet = color(250, 248, 255, Blitbuffer.COLOR_WHITE),
    surface = color(242, 240, 247, Blitbuffer.COLOR_LIGHT_GRAY),
    surface_variant = color(228, 225, 235, Blitbuffer.COLOR_GRAY_8),
    primary = color(214, 227, 255, Blitbuffer.COLOR_GRAY_8),
    on_primary = color(23, 59, 111, Blitbuffer.COLOR_DARK_GRAY),
    secondary = color(225, 221, 242, Blitbuffer.COLOR_GRAY_7),
    on_secondary = color(59, 54, 79, Blitbuffer.COLOR_DARK_GRAY),
    on_surface = color(31, 29, 36, Blitbuffer.COLOR_BLACK),
    on_variant = color(76, 73, 84, Blitbuffer.COLOR_DARK_GRAY),
    track = color(198, 196, 205, Blitbuffer.COLOR_GRAY),
}

local function applyTheme(appdock)
    local palette = Theme.getPalette(appdock)
    PALETTE.sheet = palette.dropdown or palette.background
    PALETTE.surface = palette.surface
    PALETTE.surface_variant = palette.surface_variant
    PALETTE.primary = palette.button or palette.primary
    PALETTE.on_primary = palette.on_button or palette.on_primary
    PALETTE.secondary = palette.secondary
    PALETTE.on_secondary = palette.on_secondary
    PALETTE.on_surface = palette.on_surface
    PALETTE.on_variant = palette.on_variant
    PALETTE.track = palette.track
end

local function emptySizedWidget(width, height)
    return CenterContainer:new{
        dimen = Geom:new{ w = width, h = height },
        HorizontalSpan:new{ width = 0 },
    }
end

local function getWifiState()
    local ok, NetworkMgr = pcall(require, "ui/network/manager")
    if not ok or not NetworkMgr or type(NetworkMgr.isWifiOn) ~= "function" then
        return false, false
    end
    local state_ok, wifi_on = pcall(NetworkMgr.isWifiOn, NetworkMgr)
    return state_ok and not not wifi_on, true
end

local function getBrightness()
    local ok, data = pcall(function()
        local powerd = Device:getPowerDevice()
        if not powerd or type(powerd.frontlightIntensity) ~= "function" then return nil end
        if type(powerd.fl_min) ~= "number" or type(powerd.fl_max) ~= "number" then return nil end
        return {
            powerd = powerd,
            min = powerd.fl_min,
            max = powerd.fl_max,
            current = powerd:frontlightIntensity(),
        }
    end)
    if ok and data and type(data.current) == "number" then
        return data
    end
    return nil
end

function QuickTile:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local background = self.active and PALETTE.primary or PALETTE.surface_variant
    local foreground = self.active and PALETTE.on_primary or PALETTE.on_surface
    local symbol_size = math.max(scale(12), math.min(self.compact and scale(17) or scale(20), math.floor(self.height * .34)))
    local title_size = math.max(scale(8), math.min(self.compact and scale(11) or scale(12), math.floor(self.height * .20)))
    local subtitle_size = math.max(scale(7), math.min(self.compact and scale(9) or scale(10), math.floor(self.height * .16)))
    local text_width = math.max(scale(12), self.width - scale(14))
    local title = Theme.fitLabel(self.title or "", text_width, title_size, 0)
    local subtitle = Theme.fitLabel(self.subtitle or "", text_width, subtitle_size, 0)
    local line_gap = math.max(0, math.floor(self.height * .01))
    self.layout = { title = title, subtitle = subtitle, line_gap = line_gap }
    local frame_style = Theme.getButtonFrameStyle(self.appdock, self.height, math.floor(self.height * .32))
    self[1] = FrameContainer:new{
        width = self.width,
        height = self.height,
        padding = 0,
        bordersize = frame_style.bordersize or 0,
        color = frame_style.color,
        radius = frame_style.radius or math.floor(self.height * 0.32),
        background = background,
        CenterContainer:new{
            dimen = Geom:new{ w = self.width, h = self.height },
            VerticalGroup:new{
                TextWidget:new{
                    text = self.symbol,
                    face = Font:getFace("cfont", symbol_size),
                    fgcolor = foreground,
                    bold = true,
                },
                VerticalSpan:new{ width = line_gap },
                TextWidget:new{
                    text = title,
                    face = Font:getFace("smallinfofont", title_size),
                    fgcolor = foreground,
                    bold = true,
                    max_width = text_width,
                },
                VerticalSpan:new{ width = line_gap },
                TextWidget:new{
                    text = subtitle,
                    face = Font:getFace("smallinfofont", subtitle_size),
                    fgcolor = self.active and PALETTE.on_primary or PALETTE.on_variant,
                    max_width = text_width,
                },
            },
        },
    }
    self.ges_events = {
        TapQuickTile = { GestureRange:new{ ges = "tap", range = self.dimen } },
    }
end

function QuickTile:paintTo(bb, x, y)
    local range = self.ges_events.TapQuickTile[1].range
    range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    return InputContainer.paintTo(self, bb, x, y)
end

function QuickTile:onTapQuickTile()
    if self.callback then self.callback() end
    return true
end

function NotificationRow:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local notification = self.notification or {}
    local background = notification.read and PALETTE.surface or PALETTE.primary
    local foreground = notification.read and PALETTE.on_surface or PALETTE.on_primary
    local message_color = notification.read and PALETTE.on_variant or PALETTE.on_primary
    local title_size = math.max(scale(8), math.min(scale(11), math.floor(self.height * .28)))
    local message_size = math.max(scale(7), math.min(scale(9), math.floor(self.height * .20)))
    local text_width = math.max(scale(12), self.width - scale(30))
    local title = Theme.fitLabel(notification.title or _("AppDock"), text_width, title_size, 0)
    local message = Theme.fitLabel(notification.message or "", text_width, message_size, 0)
    local title_y = math.max(scale(3), math.floor((self.height - title_size - message_size - scale(3)) / 2))
    local message_y = math.min(self.height - message_size - scale(3), title_y + title_size + scale(3))
    self[1] = FrameContainer:new{
        width = self.width, height = self.height, padding = 0, bordersize = 0,
        radius = scale(11), background = background,
        OverlapGroup:new{
            dimen = self.dimen,
            allow_mirroring = false,
            TextWidget:new{ text = title, face = Font:getFace("smallinfofont", title_size), fgcolor = foreground, bold = true, max_width = text_width, overlap_offset = { scale(12), title_y } },
            TextWidget:new{ text = message, face = Font:getFace("smallinfofont", message_size), fgcolor = message_color, max_width = text_width, overlap_offset = { scale(12), message_y } },
            TextWidget:new{ text = notification.read and "" or "•", face = Font:getFace("cfont", scale(18)), fgcolor = foreground, overlap_offset = { self.width - scale(18), scale(8) } },
        },
    }
    self.ges_events = { TapNotification = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function NotificationRow:paintTo(bb, x, y)
    local range = self.ges_events.TapNotification[1].range
    range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    return InputContainer.paintTo(self, bb, x, y)
end

function NotificationRow:onTapNotification()
    if self.callback then self.callback() end
    return true
end

function BrightnessSlider:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self:build()
    self.ges_events = {
        TapBrightness = { GestureRange:new{ ges = "tap", range = self.dimen } },
        PanBrightness = { GestureRange:new{ ges = "pan", range = self.dimen } },
        PanReleaseBrightness = { GestureRange:new{ ges = "pan_release", range = self.dimen } },
    }
end

function BrightnessSlider:build()
    local state = self.brightness
    local enabled = state ~= nil and state.max > state.min
    local percentage = 0
    if enabled then
        percentage = math.max(0, math.min(1, (state.current - state.min) / (state.max - state.min)))
    end
    local track_y = self.height - scale(16)
    local track_height = scale(12)
    local fill_width = math.max(scale(3), math.floor(self.width * percentage))
    local level_text = enabled and string.format("%d%%", math.floor(percentage * 100 + 0.5)) or _("Unavailable")

    self[1] = OverlapGroup:new{
        dimen = Geom:new{ w = self.width, h = self.height },
        allow_mirroring = false,
        TextWidget:new{
            text = _("Brightness"),
            face = Font:getFace("smallinfofont", scale(15)),
            fgcolor = PALETTE.on_surface,
            bold = true,
            overlap_offset = { 0, 0 },
        },
        TextWidget:new{
            text = level_text,
            face = Font:getFace("smallinfofont", scale(14)),
            fgcolor = PALETTE.on_variant,
            overlap_offset = { self.width - scale(48), scale(1) },
        },
        FrameContainer:new{
            width = self.width,
            height = track_height,
            padding = 0,
            bordersize = 0,
            radius = math.floor(track_height / 2),
            background = PALETTE.track,
            overlap_offset = { 0, track_y },
            emptySizedWidget(self.width, track_height),
        },
        FrameContainer:new{
            width = fill_width,
            height = track_height,
            padding = 0,
            bordersize = 0,
            radius = math.floor(track_height / 2),
            background = enabled and PALETTE.primary or PALETTE.surface_variant,
            overlap_offset = { 0, track_y },
            emptySizedWidget(fill_width, track_height),
        },
    }
end

function BrightnessSlider:setBrightness(state)
    self.brightness = state
    self:build()
end

function BrightnessSlider:paintTo(bb, x, y)
    local gestures = { "TapBrightness", "PanBrightness", "PanReleaseBrightness" }
    for _, name in ipairs(gestures) do
        local range = self.ges_events[name][1].range
        range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    end
    return InputContainer.paintTo(self, bb, x, y)
end

function BrightnessSlider:_setFromGesture(arg, ges_ev)
    -- InputContainer emits handlers as (configured_args, gesture_event).
    -- The leading argument is normally nil, while the second one contains pos.
    if not self.brightness or not ges_ev or not ges_ev.pos then return true end
    local ratio = (ges_ev.pos.x - (self.dimen.x or 0)) / self.dimen.w
    ratio = math.max(0, math.min(1, ratio))
    local value = math.floor(self.brightness.min + ratio * (self.brightness.max - self.brightness.min) + 0.5)
    self.sheet:setBrightness(value)
    return true
end

BrightnessSlider.onTapBrightness = BrightnessSlider._setFromGesture
BrightnessSlider.onPanBrightness = BrightnessSlider._setFromGesture
BrightnessSlider.onPanReleaseBrightness = BrightnessSlider._setFromGesture

function QuickSettings:show(args)
    UIManager:show(QuickSettings:new(args))
end

function QuickSettings:init()
    applyTheme(self.appdock)
    self.dimen = Screen:getSize()
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    self:rebuild(false)
    self.ges_events = {
        TapOutsideQuickSettings = {
            GestureRange:new{ ges = "tap", range = self.dimen },
        },
    }
end

function QuickSettings:_refresh(refreshtype, region, force)
    -- Mark every visible KOReader window dirty. This ensures that both the
    -- dropdown and the normal UI below it repaint after a system-state change.
    UIManager:setDirty("all", refreshtype or "ui", region)
    if force and UIManager.forceRePaint then
        UIManager:forceRePaint()
    end
end

function QuickSettings:_brightnessState()
    return getBrightness()
end

function QuickSettings:setBrightness(intensity)
    local state = self:_brightnessState()
    if not state then return end
    intensity = math.max(state.min, math.min(state.max, intensity))
    if intensity == state.current then return end

    local ok = pcall(function()
        if intensity == state.min then
            state.powerd:toggleFrontlight()
        else
            state.powerd:setIntensity(intensity)
        end
        if state.powerd.updateResumeFrontlightState then
            state.powerd:updateResumeFrontlightState()
        end
    end)
    if not ok then return end

    self.slider:setBrightness(self:_brightnessState())
    -- Fast updates while panning make the slider feel direct. The final
    -- regular refresh below keeps all normal KOReader UI surfaces in sync.
    self:_refresh("fast", self.slider.dimen, true)
    self:_refresh("ui", nil, false)
end

function QuickSettings:toggleWifi()
    local ok, NetworkMgr = pcall(require, "ui/network/manager")
    if not ok or not NetworkMgr or type(NetworkMgr.isWifiOn) ~= "function" then
        UIManager:show(InfoMessage:new{ text = _("Wi-Fi controls are unavailable on this device.") })
        return
    end
    local wifi_on = NetworkMgr:isWifiOn()
    local callback = function()
        self:rebuild(true)
    end
    if wifi_on then
        NetworkMgr:toggleWifiOff(callback, true)
    else
        NetworkMgr:toggleWifiOn(callback, false, true)
    end
end

function QuickSettings:toggleNightMode()
    UIManager:broadcastEvent(Event:new("ToggleNightMode"))
    self:rebuild(true)
end

function QuickSettings:openManager()
    UIManager:close(self)
    UIManager:nextTick(function()
        self.appdock:showManager(self.home)
    end)
end

function QuickSettings:fullRefresh()
    self:rebuild(false)
    self:_refresh("full", nil, true)
end

function QuickSettings:enterSleep()
    if type(Device.canSuspend) == "function" and Device:canSuspend() then
        UIManager:broadcastEvent(Event:new("RequestSuspend"))
    else
        UIManager:show(InfoMessage:new{ text = _("Sleep mode is unavailable on this device.") })
    end
end

function QuickSettings:togglePowerSaving()
    local enable = not self.appdock.settings.power_saving
    if enable then
        local wifi_on, wifi_available = getWifiState()
        if wifi_available and wifi_on then
            local ok, NetworkMgr = pcall(require, "ui/network/manager")
            if ok and NetworkMgr then NetworkMgr:toggleWifiOff(function() end, true) end
        end
        local brightness = self:_brightnessState()
        if brightness and brightness.current > brightness.min then pcall(brightness.powerd.toggleFrontlight, brightness.powerd) end
    end
    self.appdock:setPowerSaving(enable)
    self:rebuild(true)
end

function QuickSettings:toggleWallpaper()
    local wallpaper = self.appdock.settings.wallpaper or {}
    if not wallpaper.path or wallpaper.path == "" then
        UIManager:show(InfoMessage:new{ text = _("Choose a local background image in Settings → Display first.") })
        return
    end
    local enabled = self.appdock:setWallpaper(nil, not wallpaper.enabled)
    if not enabled and not wallpaper.enabled then
        UIManager:show(InfoMessage:new{ text = _("The saved background image is unavailable or unsupported.") })
    end
    self:rebuild(true)
end

function QuickSettings:markAllNotificationsRead()
    self.appdock:markAllNotificationsRead()
    self:rebuild(true)
end

function QuickSettings:clearNotifications()
    self.appdock:clearNotifications()
    self:rebuild(true)
end

function QuickSettings:rebuild(refresh)
    local width = self.dimen.w
    local margin = scale(22)
    local gap = scale(10)
    local header_height = scale(52)
    local tile_height = scale(76)
    local slider_height = scale(58)
    local slider_spacing = scale(12)
    local sheet_bottom = scale(18)
    local maximum_sheet_height = math.floor(self.dimen.h * 0.82)
    local notification_title_height = scale(24)
    local notification_row_height = scale(42)
    local notification_action_height = scale(34)
    local simple_mode = type(self.appdock.isSimpleModeEnabled) == "function" and self.appdock:isSimpleModeEnabled("quick_settings")
    local selected_tile_ids = type(self.appdock.getQuickSettingsTiles) == "function"
        and self.appdock:getQuickSettingsTiles()
        or { "wifi", "night", "refresh", "edit" }
    local tile_rows = math.ceil(#selected_tile_ids / 2)
    local tile_area_height = tile_rows * tile_height + math.max(0, tile_rows - 1) * gap
    local notification_items = simple_mode and {} or self.appdock:getNotifications(3)
    local notification_count = #notification_items
    local show_notifications = not simple_mode
    local notification_height = notification_title_height + notification_count * (notification_row_height + gap) + (notification_count > 0 and notification_action_height + gap or 0)
    local natural_height = header_height + tile_area_height + slider_spacing + slider_height + slider_spacing + notification_height + sheet_bottom
    local compact = natural_height > maximum_sheet_height
    if compact then
        margin = scale(16)
        gap = scale(7)
        header_height = scale(46)
        tile_height = scale(60)
        slider_height = scale(48)
        slider_spacing = scale(8)
        sheet_bottom = scale(12)
        notification_title_height = scale(20)
        notification_row_height = scale(36)
        notification_action_height = scale(30)
        notification_items = simple_mode and {} or self.appdock:getNotifications(1)
        notification_count = #notification_items
        notification_height = notification_title_height + notification_count * (notification_row_height + gap) + (notification_count > 0 and notification_action_height + gap or 0)
        tile_area_height = tile_rows * tile_height + math.max(0, tile_rows - 1) * gap
        natural_height = header_height + tile_area_height + slider_spacing + slider_height + slider_spacing + notification_height + sheet_bottom
        if self.dimen.h < scale(360) then
            show_notifications = false
            notification_items, notification_count, notification_height = {}, 0, 0
            local available_tile_height = self.dimen.h - header_height - slider_spacing - slider_height - sheet_bottom - math.max(0, tile_rows - 1) * gap
            tile_height = math.max(scale(28), math.floor(available_tile_height / math.max(1, tile_rows)))
            tile_area_height = tile_rows * tile_height + math.max(0, tile_rows - 1) * gap
            natural_height = header_height + tile_area_height + slider_spacing + slider_height + sheet_bottom
        end
    end
    local tile_width = math.floor((width - 2 * margin - gap) / 2)
    self.sheet_height = math.min(natural_height, self.dimen.h)

    local brightness = self:_brightnessState()
    local wifi_on, wifi_available = getWifiState()
    local is_night = G_reader_settings:isTrue("night_mode")
    local unread_notifications = self.appdock:getUnreadNotificationCount()
    local app_settings = self.appdock.settings or {}
    local wallpaper_settings = app_settings.wallpaper or {}

    local content = OverlapGroup:new{
        dimen = Geom:new{ w = width, h = self.dimen.h },
        allow_mirroring = false,
    }
    self.sheet_frame = FrameContainer:new{
        width = width,
        height = self.sheet_height,
        padding = 0,
        bordersize = 0,
        radius = scale(28),
        background = PALETTE.sheet,
        emptySizedWidget(width, self.sheet_height),
    }
    table.insert(content, self.sheet_frame)

    table.insert(content, TextWidget:new{
        text = _("Quick settings"),
        face = Font:getFace("cfont", scale(22)),
        fgcolor = PALETTE.on_surface,
        bold = true,
        overlap_offset = { margin, scale(16) },
    })
    local close = TextWidget:new{
        text = "×",
        face = Font:getFace("cfont", scale(24)),
        fgcolor = PALETTE.on_variant,
    }
    close.overlap_offset = { width - margin - close:getSize().w, scale(13) }
    table.insert(content, close)

    local tile_y = header_height
    local tile_definitions = {
        wifi = {
            title = _("Wi-Fi"), symbol = "W",
            subtitle = wifi_available and (wifi_on and _("On") or _("Off")) or _("Unavailable"),
            active = wifi_on,
            callback = function() self:toggleWifi() end,
        },
        night = {
            title = _("Night"), symbol = "N",
            subtitle = is_night and _("On") or _("Off"),
            active = is_night,
            callback = function() self:toggleNightMode() end,
        },
        refresh = {
            title = _("Refresh"), symbol = "R",
            subtitle = _("Redraw"),
            active = false,
            callback = function() self:fullRefresh() end,
        },
        edit = {
            title = _("Edit"), symbol = "E",
            subtitle = _("Apps"),
            active = false,
            callback = function() self:openManager() end,
        },
        sleep = {
            title = _("Sleep"), symbol = "Z",
            subtitle = _("Screen off"), active = false,
            callback = function() self:enterSleep() end,
        },
        power_saving = {
            title = _("Save power"), symbol = "P",
            subtitle = app_settings.power_saving and _("On") or _("Off"),
            active = app_settings.power_saving == true,
            callback = function() self:togglePowerSaving() end,
        },
        wallpaper = {
            title = _("Background"), symbol = "B",
            subtitle = wallpaper_settings.enabled and _("On") or _("Off"),
            active = wallpaper_settings.enabled == true,
            callback = function() self:toggleWallpaper() end,
        },
    }
    local tiles = {}
    for _, tile_id in ipairs(selected_tile_ids) do
        if tile_definitions[tile_id] then tiles[#tiles + 1] = tile_definitions[tile_id] end
    end
    for index, tile in ipairs(tiles) do
        local col = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        table.insert(content, QuickTile:new{
            appdock = self.appdock,
            title = tile.title,
            symbol = tile.symbol,
            subtitle = tile.subtitle,
            active = tile.active,
            callback = tile.callback,
            width = tile_width,
            height = tile_height,
            compact = compact,
            overlap_offset = {
                margin + col * (tile_width + gap),
                tile_y + row * (tile_height + gap),
            },
        })
    end

    self.slider = BrightnessSlider:new{
        sheet = self,
        width = width - 2 * margin,
        height = slider_height,
        brightness = brightness,
        overlap_offset = { margin, tile_y + tile_area_height + slider_spacing },
    }
    table.insert(content, self.slider)
    local notifications_y = self.slider.overlap_offset[2] + slider_height + slider_spacing
    if show_notifications then
        table.insert(content, TextWidget:new{
            text = unread_notifications > 0 and string.format(_("Notifications · %d unread"), unread_notifications) or _("Notifications · all caught up"),
            face = Font:getFace("smallinfofont", compact and scale(12) or scale(14)), fgcolor = PALETTE.on_surface, bold = true,
            overlap_offset = { margin, notifications_y },
        })
        if notification_count == 0 then
            table.insert(content, TextWidget:new{
                text = _("No notifications yet"), face = Font:getFace("smallinfofont", scale(10)), fgcolor = PALETTE.on_variant,
                overlap_offset = { margin, notifications_y + notification_title_height },
            })
        else
            for index, notification in ipairs(notification_items) do
                table.insert(content, NotificationRow:new{
                    notification = notification, width = width - 2 * margin, height = notification_row_height,
                    callback = function()
                        self.appdock:markNotificationRead(notification.id)
                        self:rebuild(true)
                    end,
                    overlap_offset = { margin, notifications_y + notification_title_height + (index - 1) * (notification_row_height + gap) },
                })
            end
            local action_y = notifications_y + notification_title_height + notification_count * (notification_row_height + gap)
            local action_width = math.floor((width - 2 * margin - gap) / 2)
            table.insert(content, QuickTile:new{
                appdock = self.appdock, title = _("Read all"), symbol = "✓", subtitle = _("Inbox"), active = false, callback = function() self:markAllNotificationsRead() end,
                width = action_width, height = notification_action_height, compact = true, overlap_offset = { margin, action_y },
            })
            table.insert(content, QuickTile:new{
                appdock = self.appdock, title = _("Clear all"), symbol = "×", subtitle = _("Inbox"), active = false, callback = function() self:clearNotifications() end,
                width = action_width, height = notification_action_height, compact = true, overlap_offset = { margin + action_width + gap, action_y },
            })
        end
    end
    self.layout = {
        simple_mode = simple_mode,
        tile_count = #tiles,
        show_notifications = show_notifications,
        compact = compact,
        tile_y = tile_y,
        tile_height = tile_height,
        gap = gap,
        slider_y = self.slider.overlap_offset[2],
        slider_height = slider_height,
        content_bottom = show_notifications and (notifications_y + notification_height) or (self.slider.overlap_offset[2] + slider_height),
        sheet_height = self.sheet_height,
    }

    self:clear()
    self[1] = content
    if refresh then
        self:_refresh("ui", nil, true)
    end
end

function QuickSettings:paintTo(bb, x, y)
    local range = self.ges_events.TapOutsideQuickSettings[1].range
    range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    return InputContainer.paintTo(self, bb, x, y)
end

function QuickSettings:onTapOutsideQuickSettings(arg, ges_ev)
    if self.sheet_frame and self.sheet_frame.dimen and ges_ev and ges_ev.pos
            and not ges_ev.pos:intersectWith(self.sheet_frame.dimen) then
        self:onClose()
    end
    return true
end

function QuickSettings:onShow()
    self:_refresh("ui", nil, true)
    return true
end

function QuickSettings:onCloseWidget()
    self:_refresh("ui", nil, true)
end

function QuickSettings:onClose()
    UIManager:close(self)
    self:_refresh("ui", nil, true)
    return true
end

return QuickSettings
