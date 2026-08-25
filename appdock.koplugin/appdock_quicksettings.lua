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
    PALETTE.sheet = palette.background
    PALETTE.surface = palette.surface
    PALETTE.surface_variant = palette.surface_variant
    PALETTE.primary = palette.primary
    PALETTE.on_primary = palette.on_primary
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
    local symbol_size = self.compact and scale(17) or scale(20)
    local title_size = self.compact and scale(11) or scale(12)
    local subtitle_size = self.compact and scale(9) or scale(10)
    self[1] = FrameContainer:new{
        width = self.width,
        height = self.height,
        padding = 0,
        bordersize = 0,
        radius = math.floor(self.height * 0.32),
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
                VerticalSpan:new{ width = scale(1) },
                TextWidget:new{
                    text = self.title,
                    face = Font:getFace("smallinfofont", title_size),
                    fgcolor = foreground,
                    bold = true,
                    max_width = self.width - scale(14),
                },
                VerticalSpan:new{ width = scale(1) },
                TextWidget:new{
                    text = self.subtitle or "",
                    face = Font:getFace("smallinfofont", subtitle_size),
                    fgcolor = self.active and PALETTE.on_primary or PALETTE.on_variant,
                    max_width = self.width - scale(14),
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
    local natural_height = header_height + 2 * tile_height + gap + slider_spacing + slider_height + sheet_bottom
    local compact = natural_height > maximum_sheet_height
    if compact then
        margin = scale(16)
        gap = scale(7)
        header_height = scale(46)
        tile_height = scale(60)
        slider_height = scale(48)
        slider_spacing = scale(8)
        sheet_bottom = scale(12)
        natural_height = header_height + 2 * tile_height + gap + slider_spacing + slider_height + sheet_bottom
    end
    local tile_width = math.floor((width - 2 * margin - gap) / 2)
    self.sheet_height = math.min(natural_height, self.dimen.h)

    local brightness = self:_brightnessState()
    local wifi_on, wifi_available = getWifiState()
    local is_night = G_reader_settings:isTrue("night_mode")

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
    local tiles = {
        {
            title = _("Wi-Fi"), symbol = "W",
            subtitle = wifi_available and (wifi_on and _("On") or _("Off")) or _("Unavailable"),
            active = wifi_on,
            callback = function() self:toggleWifi() end,
        },
        {
            title = _("Night"), symbol = "N",
            subtitle = is_night and _("On") or _("Off"),
            active = is_night,
            callback = function() self:toggleNightMode() end,
        },
        {
            title = _("Refresh"), symbol = "R",
            subtitle = _("Redraw"),
            active = false,
            callback = function() self:fullRefresh() end,
        },
        {
            title = _("Edit"), symbol = "E",
            subtitle = _("Apps"),
            active = false,
            callback = function() self:openManager() end,
        },
    }
    for index, tile in ipairs(tiles) do
        local col = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        table.insert(content, QuickTile:new{
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
        overlap_offset = { margin, tile_y + 2 * (tile_height + gap) + slider_spacing },
    }
    table.insert(content, self.slider)
    self.layout = {
        compact = compact,
        tile_y = tile_y,
        tile_height = tile_height,
        gap = gap,
        slider_y = self.slider.overlap_offset[2],
        slider_height = slider_height,
        content_bottom = self.slider.overlap_offset[2] + slider_height,
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
