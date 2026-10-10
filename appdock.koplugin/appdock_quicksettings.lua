--[[--
AppDock's custom-drawn quick settings dropdown.
This is a KOReader overlay, not a ButtonDialog: its tiles, slider and sheet
are composed from native widget primitives and refresh their own regions.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local DAppLogo = require("appdock_logo")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalSpan = require("ui/widget/horizontalspan")
local AppDockDialogs = require("appdock_dialogs")
local InfoMessage = AppDockDialogs.InfoMessage
local DeviceControls = require("appdock_device_controls")
local InputContainer = require("ui/widget/container/inputcontainer")
local Layout = require("appdock_layout")
local Motion = require("appdock_motion")
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
    icon_kind = nil,
    subtitle = nil,
    active = false,
    callback = nil,
    width = nil,
    height = nil,
    compact = false,
    expressive = false,
    show_switch = false,
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

local QuickCloseButton = InputContainer:extend{
    sheet = nil,
    size = nil,
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
    outline = color(126, 123, 132, Blitbuffer.COLOR_GRAY),
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
    PALETTE.outline = palette.outline
    PALETTE.track = palette.track
end

local function emptySizedWidget(width, height)
    return CenterContainer:new{
        dimen = Geom:new{ w = width, h = height },
        HorizontalSpan:new{ width = 0 },
    }
end

local function bottomSwipeRange(dimen)
    local band_height = scale(76)
    return Geom:new{
        x = dimen.x or 0,
        y = (dimen.y or 0) + math.max(0, dimen.h - band_height),
        w = dimen.w,
        h = band_height,
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
    local symbol_size = math.max(scale(12), math.min(self.compact and scale(17) or (self.expressive and scale(22) or scale(20)), math.floor(self.height * .34)))
    local title_size = math.max(scale(8), math.min(self.compact and scale(11) or (self.expressive and scale(13) or scale(12)), math.floor(self.height * .20)))
    local subtitle_size = math.max(scale(7), math.min(self.compact and scale(9) or scale(10), math.floor(self.height * .16)))
    if self.expressive then
        title_size = Theme.adjustText(self.appdock, title_size, scale(8))
        subtitle_size = Theme.adjustText(self.appdock, subtitle_size, scale(7))
    end
    local text_width = math.max(scale(12), self.width - scale(14))
    local title = Theme.fitLabel(self.title or "", text_width, title_size, 0)
    local subtitle = Theme.fitLabel(self.subtitle or "", text_width, subtitle_size, 0)
    if self.expressive then
        -- Material-style quick settings keep a large circular icon and the
        -- label pair on one horizontal axis. This reads like Android's shade
        -- at a glance while remaining high-contrast on monochrome E-Ink.
        local icon_diameter = math.max(scale(30), math.min(scale(42), self.height - scale(28)))
        local icon_x = scale(14)
        local text_x = icon_x + icon_diameter + scale(11)
        local switch_width = self.show_switch and scale(40) or 0
        local available_text_width = math.max(scale(18), self.width - text_x - switch_width - scale(18))
        title = Theme.fitLabel(self.title or "", available_text_width, title_size, 0)
        subtitle = Theme.fitLabel(self.subtitle or "", available_text_width, subtitle_size, 0)
        local icon_ink = PALETTE.on_surface
        local icon_background = PALETTE.surface
        local icon_widget = self.icon_kind and DAppLogo:new{
            kind = self.icon_kind,
            size = math.min(scale(30), math.floor(icon_diameter * .68)),
            ink = icon_ink,
        } or TextWidget:new{
            text = self.symbol,
            face = Font:getFace("cfont", math.min(symbol_size, math.floor(icon_diameter * .54))),
            fgcolor = icon_ink, bold = true, padding = 0,
        }
        local icon_circle = FrameContainer:new{
            width = icon_diameter, height = icon_diameter, padding = 0, bordersize = 0,
            radius = math.floor(icon_diameter / 2), background = icon_background,
            CenterContainer:new{
                dimen = Geom:new{ w = icon_diameter, h = icon_diameter },
                icon_widget,
            },
        }
        local title_widget = TextWidget:new{
            text = title, face = Font:getFace("smallinfofont", title_size), fgcolor = foreground,
            bold = true, max_width = available_text_width, padding = 0,
        }
        local subtitle_widget = TextWidget:new{
            text = subtitle, face = Font:getFace("smallinfofont", subtitle_size),
            fgcolor = self.active and PALETTE.on_primary or PALETTE.on_variant,
            max_width = available_text_width, padding = 0,
        }
        local switch_entry
        if self.show_switch then
            local switch_height = scale(22)
            local track = FrameContainer:new{
                width = switch_width, height = switch_height, padding = 0, bordersize = 0,
                radius = math.floor(switch_height / 2),
                background = self.active and PALETTE.on_primary or PALETTE.track,
                emptySizedWidget(switch_width, switch_height),
            }
            local knob_size = math.max(scale(14), switch_height - scale(6))
            local knob = FrameContainer:new{
                width = knob_size, height = knob_size, padding = 0, bordersize = 0,
                radius = math.floor(knob_size / 2),
                background = self.active and PALETTE.primary or PALETTE.surface,
                emptySizedWidget(knob_size, knob_size),
                overlap_offset = {
                    self.active and switch_width - knob_size - scale(3) or scale(3),
                    math.floor((switch_height - knob_size) / 2),
                },
            }
            self._switch_knob = knob
            self._switch_width = switch_width
            self._switch_knob_size = knob_size
            switch_entry = {
                widget = OverlapGroup:new{
                    dimen = Geom:new{ w = switch_width, h = switch_height },
                    track, knob,
                },
                x = self.width - switch_width - scale(14),
                y = math.floor((self.height - switch_height) / 2),
            }
        end
        local entries = {
            { widget = icon_circle, x = icon_x, y = math.floor((self.height - icon_diameter) / 2) },
            { widget = title_widget, x = text_x, y = math.floor(self.height * .27) },
            { widget = subtitle_widget, x = text_x, y = math.floor(self.height * .54) },
        }
        if switch_entry then table.insert(entries, switch_entry) end
        self.layout = { title = title, subtitle = subtitle, expressive = true, icon_diameter = icon_diameter, icon_kind = self.icon_kind }
        self[1] = FrameContainer:new{
            width = self.width, height = self.height, padding = 0, bordersize = 0,
            radius = math.floor(self.height * .31), background = background,
            Layout.FixedStack:new{ width = self.width, height = self.height, entries = entries },
        }
        self.ges_events = { TapQuickTile = { GestureRange:new{ ges = "tap", range = self.dimen } } }
        return
    end
    local line_gap = math.max(scale(1), math.floor(self.height * .025))
    local minimum_symbol, minimum_title, minimum_subtitle = scale(10), scale(8), scale(7)
    local symbol_widget, title_widget, subtitle_widget, positions, stack_height
    local function buildStack(include_subtitle)
        symbol_widget = self.icon_kind and DAppLogo:new{ kind = self.icon_kind, size = symbol_size, ink = foreground }
            or TextWidget:new{ text = self.symbol, face = Font:getFace("cfont", symbol_size), fgcolor = foreground, bold = true, padding = 0 }
        title_widget = TextWidget:new{ text = title, face = Font:getFace("smallinfofont", title_size), fgcolor = foreground, bold = true, max_width = text_width, padding = 0 }
        subtitle_widget = include_subtitle and TextWidget:new{ text = subtitle, face = Font:getFace("smallinfofont", subtitle_size), fgcolor = self.active and PALETTE.on_primary or PALETTE.on_variant, max_width = text_width, padding = 0 } or nil
        local stack = subtitle_widget and { symbol_widget, title_widget, subtitle_widget } or { symbol_widget, title_widget }
        positions, stack_height = Theme.centeredStack(self.height, stack, line_gap, scale(3))
    end
    buildStack(true)
    local available_height = self.height - 2 * scale(3)
    local attempts = 0
    while stack_height > available_height and attempts < 48 do
        if symbol_size > minimum_symbol then
            symbol_size = symbol_size - scale(1)
        elseif title_size > minimum_title then
            title_size = title_size - scale(1)
        elseif subtitle_size > minimum_subtitle then
            subtitle_size = subtitle_size - scale(1)
        else
            break
        end
        title = Theme.fitLabel(self.title or "", text_width, title_size, 0)
        subtitle = Theme.fitLabel(self.subtitle or "", text_width, subtitle_size, 0)
        buildStack(true)
        attempts = attempts + 1
    end
    if stack_height > available_height then buildStack(false) end
    self.layout = { title = title, subtitle = subtitle_widget and subtitle or "", line_gap = line_gap, positions = positions, stack_height = stack_height, available_height = available_height, expressive = self.expressive == true, icon_kind = self.icon_kind }
    local switch_widget
    if self.show_switch then
        local switch_width = scale(42)
        local switch_height = scale(22)
        local track = FrameContainer:new{
            width = switch_width, height = switch_height, padding = 0,
            bordersize = scale(1), color = foreground,
            radius = math.floor(switch_height / 2),
            background = self.active and PALETTE.primary or PALETTE.track,
            emptySizedWidget(switch_width, switch_height),
        }
        local knob_size = math.max(scale(14), switch_height - scale(6))
        local knob = FrameContainer:new{
            width = knob_size, height = knob_size, padding = 0,
            bordersize = scale(1), color = self.active and PALETTE.primary or PALETTE.on_variant,
            radius = math.floor(knob_size / 2),
            background = self.active and PALETTE.on_primary or PALETTE.surface,
            emptySizedWidget(knob_size, knob_size),
            overlap_offset = {
                self.active and switch_width - knob_size - scale(3) or scale(3),
                math.floor((switch_height - knob_size) / 2),
            },
        }
        self._switch_knob = knob
        self._switch_width = switch_width
        self._switch_knob_size = knob_size
        switch_widget = {
            widget = OverlapGroup:new{
                dimen = Geom:new{ w = switch_width, h = switch_height },
                track, knob,
            },
            x = self.width - switch_width - scale(10), y = scale(8),
        }
    end
    local frame_style = Theme.getButtonFrameStyle(self.appdock, self.height, math.floor(self.height * .32))
    self[1] = FrameContainer:new{
        width = self.width,
        height = self.height,
        padding = 0,
        bordersize = frame_style.bordersize or 0,
        color = frame_style.color,
        radius = frame_style.radius or math.floor(self.height * (self.expressive and 0.40 or 0.32)),
        background = background,
        Layout.FixedStack:new{
            width = self.width,
            height = self.height,
            entries = {
                { widget = CenterContainer:new{ dimen = Geom:new{ w = self.width, h = symbol_widget:getSize().h }, symbol_widget }, x = 0, y = positions[1] },
                { widget = CenterContainer:new{ dimen = Geom:new{ w = self.width, h = title_widget:getSize().h }, title_widget }, x = 0, y = positions[2] },
                subtitle_widget and { widget = CenterContainer:new{ dimen = Geom:new{ w = self.width, h = subtitle_widget:getSize().h }, subtitle_widget }, x = 0, y = positions[3] } or nil,
                switch_widget,
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
    if self.callback and self.show_switch then
        local start = self.active and 1 or 0
        local finish = self.active and 0 or 1
        Motion.run(self, 3, 0.045, function(frame)
            local progress = (frame - 1) / 2
            local position = start + (finish - start) * progress
            if self._switch_knob then
                self._switch_knob.overlap_offset[1] = math.floor(scale(3) + position * (self._switch_width - self._switch_knob_size - scale(6)))
            end
        end, self.callback)
    elseif self.callback then
        UIManager:setDirty(self, "fast")
        self.callback()
    end
    return true
end

function QuickCloseButton:init()
    self.dimen = Geom:new{ w = self.size, h = self.size }
    local glyph = TextWidget:new{
        text = "×",
        face = Font:getFace("cfont", scale(23)),
        fgcolor = PALETTE.on_surface,
        padding = 0,
    }
    self[1] = FrameContainer:new{
        width = self.size, height = self.size, padding = 0, bordersize = 0,
        radius = math.floor(self.size / 2), background = PALETTE.surface_variant,
        CenterContainer:new{ dimen = self.dimen, glyph },
    }
    self.ges_events = { TapCloseQuickSettings = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function QuickCloseButton:paintTo(bb, x, y)
    local range = self.ges_events.TapCloseQuickSettings[1].range
    range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    return InputContainer.paintTo(self, bb, x, y)
end

function QuickCloseButton:onTapCloseQuickSettings()
    return self.sheet:onClose()
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
    local title_widget = TextWidget:new{ text = title, face = Font:getFace("smallinfofont", title_size), fgcolor = foreground, bold = true, max_width = text_width, padding = 0 }
    local message_widget = TextWidget:new{ text = message, face = Font:getFace("smallinfofont", message_size), fgcolor = message_color, max_width = text_width, padding = 0 }
    local positions = Theme.centeredStack(self.height, { title_widget, message_widget }, scale(3), scale(3))
    local title_y, message_y = positions[1], positions[2]
    local unread_marker = TextWidget:new{ text = notification.read and "" or "•", face = Font:getFace("cfont", scale(18)), fgcolor = foreground, padding = 0 }
    self[1] = FrameContainer:new{
        width = self.width, height = self.height, padding = 0, bordersize = 0,
        radius = scale(11), background = background,
        Layout.FixedStack:new{
            width = self.width,
            height = self.height,
            entries = {
                { widget = title_widget, x = scale(12), y = title_y },
                { widget = message_widget, x = scale(12), y = message_y },
                { widget = unread_marker, x = self.width - scale(18), y = scale(8) },
            },
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
    local inset = scale(15)
    local track_y = self.height - scale(19)
    local track_height = scale(7)
    local thumb_size = scale(15)
    local track_width = math.max(scale(24), self.width - 2 * inset)
    local fill_width = math.max(scale(3), math.floor(track_width * percentage))
    local level_text = enabled and string.format("%d%%", math.floor(percentage * 100 + 0.5)) or _("Unavailable")
    self.track_x, self.track_width = inset, track_width
    local thumb_x = math.max(inset - math.floor(thumb_size / 2), math.min(inset + track_width - math.floor(thumb_size / 2), inset + math.floor(track_width * percentage) - math.floor(thumb_size / 2)))
    local thumb_y = track_y - math.floor((thumb_size - track_height) / 2)
    local label_x = inset + scale(23)

    self[1] = OverlapGroup:new{
        dimen = Geom:new{ w = self.width, h = self.height },
        allow_mirroring = false,
        FrameContainer:new{
            width = self.width, height = self.height, padding = 0, bordersize = 0,
            radius = math.floor(self.height * .34), background = PALETTE.surface,
            emptySizedWidget(self.width, self.height),
        },
        DAppLogo:new{
            kind = "display", size = scale(18), ink = PALETTE.on_surface,
            overlap_offset = { inset, scale(8) },
        },
        TextWidget:new{
            text = _("Brightness"), face = Font:getFace("smallinfofont", scale(14)),
            fgcolor = PALETTE.on_surface, bold = true, padding = 0,
            overlap_offset = { label_x, scale(10) },
        },
        TextWidget:new{
            text = level_text,
            face = Font:getFace("smallinfofont", scale(13)),
            fgcolor = PALETTE.on_variant,
            overlap_offset = { self.width - inset - scale(44), scale(11) },
        },
        FrameContainer:new{
            width = track_width,
            height = track_height,
            padding = 0,
            bordersize = 0,
            radius = math.floor(track_height / 2),
            background = PALETTE.track,
            overlap_offset = { inset, track_y },
            emptySizedWidget(track_width, track_height),
        },
        FrameContainer:new{
            width = fill_width,
            height = track_height,
            padding = 0,
            bordersize = 0,
            radius = math.floor(track_height / 2),
            background = enabled and PALETTE.primary or PALETTE.surface_variant,
            overlap_offset = { inset, track_y },
            emptySizedWidget(fill_width, track_height),
        },
        FrameContainer:new{
            width = thumb_size, height = thumb_size, padding = 0,
            bordersize = scale(1), color = PALETTE.sheet,
            radius = math.floor(thumb_size / 2),
            background = enabled and PALETTE.on_primary or PALETTE.on_variant,
            overlap_offset = { thumb_x, thumb_y },
            emptySizedWidget(thumb_size, thumb_size),
        },
    }
    self._thumb_x, self._thumb_y = thumb_x, thumb_y
end

function BrightnessSlider:setBrightness(state)
    self.brightness = state
    self:build()
end

function BrightnessSlider:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
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
    local ratio = (ges_ev.pos.x - (self.dimen.x or 0) - (self.track_x or 0)) / math.max(1, self.track_width or self.dimen.w)
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
        self.key_events = self.key_events or {}
        self.key_events.Close = { { Device.input.group.Back } }
        local up, down = DeviceControls.pageKeyGroups()
        if up then self.key_events.BrightnessUp = { { up } } end
        if down then self.key_events.BrightnessDown = { { down } } end
    end
    self:rebuild(false)
    self.ges_events = {
        TapOutsideQuickSettings = {
            GestureRange:new{ ges = "tap", range = self.dimen },
        },
    }
    if not self.appdock:isSimpleModeEnabled("quick_settings") then
        self.ges_events.RevealRecentApps = {
            GestureRange:new{ ges = "swipe", direction = "north", range = function() return bottomSwipeRange(self.dimen) end },
        }
    end
end

function QuickSettings:onBrightnessUp()
    local state = DeviceControls.setBrightness(10)
    if state then self:rebuild(true); return true end
    return false
end
function QuickSettings:onBrightnessDown()
    local state = DeviceControls.setBrightness(-10)
    if state then self:rebuild(true); return true end
    return false
end
function QuickSettings:onKeyRepeat(key)
    local up, down = DeviceControls.pageKeyGroups()
    if up and key == up then DeviceControls.showPowerMenu(); return true end
    if down and key == down then DeviceControls.showScreensaver(); return true end
    return InputContainer.onKeyRepeat and InputContainer.onKeyRepeat(self, key) or false
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
    -- self:_refresh("ui", nil, false)
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
    AppDockDialogs.toggleWifi(NetworkMgr, wifi_on, callback)
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

function QuickSettings:rotateScreen()
    local ok, optionsutil = pcall(require, "ui/data/optionsutil")
    local modes = ok and type(optionsutil) == "table" and optionsutil.rotation_modes
    if type(modes) ~= "table" or #modes == 0 or type(Screen.getRotationMode) ~= "function" then
        UIManager:show(InfoMessage:new{ text = _("Screen rotation is unavailable on this device.") })
        return false
    end
    local read_ok, current_mode = pcall(Screen.getRotationMode, Screen)
    if not read_ok then
        UIManager:show(InfoMessage:new{ text = _("Screen rotation is unavailable on this device.") })
        return false
    end
    local next_mode = modes[1]
    for index, mode in ipairs(modes) do
        if mode == current_mode then next_mode = modes[index % #modes + 1]; break end
    end
    UIManager:close(self)
    UIManager:broadcastEvent(Event:new("SetRotationMode", next_mode))
    return true
end

function QuickSettings:onRevealRecentApps()
    if self.appdock:isSimpleModeEnabled("quick_settings") then return false end
    local manager = self.appdock and self.appdock:getDAppManager()
    if manager and type(manager.showRecentDrawer) == "function" then
        manager:showRecentDrawer(self, self.home, self)
        return true
    end
    return false
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
            if ok and NetworkMgr then AppDockDialogs.toggleWifi(NetworkMgr, true, function() end) end
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
    local maximum_sheet_height = math.floor(self.dimen.h * 0.86)
    local notification_title_height = scale(24)
    local notification_row_height = scale(42)
    local notification_action_height = scale(34)
    local simple_mode = type(self.appdock.isSimpleModeEnabled) == "function" and self.appdock:isSimpleModeEnabled("quick_settings")
    local expressive = not simple_mode and type(self.appdock.isExpressiveUiEnabled) == "function" and self.appdock:isExpressiveUiEnabled()
    local header_title = TextWidget:new{
        text = _("Quick settings"),
        face = Font:getFace("cfont", expressive and Theme.adjustText(self.appdock, scale(22), scale(16)) or scale(22)),
        fgcolor = PALETTE.on_surface,
        bold = true,
        padding = 0,
    }
    local header_subtitle = expressive and TextWidget:new{
        text = os.date("%A, %d %B"),
        face = Font:getFace("smallinfofont", Theme.adjustText(self.appdock, scale(11), scale(9))),
        fgcolor = PALETTE.on_variant,
        padding = 0,
    } or nil
    if expressive then
        margin = scale(18)
        gap = scale(8)
        header_height = scale(66)
        tile_height = scale(84)
        slider_height = scale(72)
        slider_spacing = scale(10)
        sheet_bottom = scale(14)
    elseif not simple_mode then
        margin = scale(18)
        gap = scale(6)
        header_height = scale(46)
        tile_height = scale(68)
        slider_height = scale(52)
        slider_spacing = scale(8)
        sheet_bottom = scale(12)
    end
    header_height = math.max(header_height, header_title:getSize().h + (header_subtitle and header_subtitle:getSize().h or 0) + scale(24))
    local selected_tile_ids = type(self.appdock.getQuickSettingsTiles) == "function"
        and self.appdock:getQuickSettingsTiles()
        or { "wifi", "night", "refresh", "edit" }
    local tile_rows = math.ceil(#selected_tile_ids / 2)
    local tile_area_height = tile_rows * tile_height + math.max(0, tile_rows - 1) * gap
    local notification_items = simple_mode and {} or self.appdock:getNotifications(3)
    local notification_count = #notification_items
    local show_notifications = not simple_mode
    local notification_height = notification_title_height + notification_count * (notification_row_height + gap) + (notification_count > 0 and notification_action_height + gap or 0)
    local natural_height = header_height + gap + tile_area_height + slider_spacing + slider_height + slider_spacing + notification_height + sheet_bottom
    local compact = natural_height > maximum_sheet_height
    if compact then
        margin = scale(16)
        gap = scale(7)
        header_height = scale(50)
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
        header_height = math.max(header_height, header_title:getSize().h + (header_subtitle and header_subtitle:getSize().h or 0) + scale(16))
        natural_height = header_height + gap + tile_area_height + slider_spacing + slider_height + slider_spacing + notification_height + sheet_bottom
        if self.dimen.h < scale(360) then
            show_notifications = false
            notification_items, notification_count, notification_height = {}, 0, 0
            local available_tile_height = self.dimen.h - header_height - gap - slider_spacing - slider_height - sheet_bottom - math.max(0, tile_rows - 1) * gap
            tile_height = math.max(scale(28), math.floor(available_tile_height / math.max(1, tile_rows)))
            tile_area_height = tile_rows * tile_height + math.max(0, tile_rows - 1) * gap
            natural_height = header_height + gap + tile_area_height + slider_spacing + slider_height + sheet_bottom
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
        bordersize = scale(1),
        color = PALETTE.outline,
        radius = expressive and scale(34) or scale(28),
        background = PALETTE.sheet,
        emptySizedWidget(width, self.sheet_height),
    }
    table.insert(content, self.sheet_frame)

    local header_title_y = expressive and scale(13) or math.max(scale(3), math.floor((header_height - header_title:getSize().h) / 2))
    if expressive then
        local pill_y = scale(4)
        table.insert(content, FrameContainer:new{
            width = width - 2 * margin, height = header_height - scale(8), padding = 0, bordersize = 0,
            radius = math.floor((header_height - scale(8)) / 2), background = PALETTE.surface,
            emptySizedWidget(width - 2 * margin, header_height - scale(8)), overlap_offset = { margin, pill_y },
        })
        local handle_width, handle_height = scale(36), scale(4)
        table.insert(content, FrameContainer:new{
            width = handle_width, height = handle_height, padding = 0, bordersize = 0,
            radius = math.floor(handle_height / 2), background = PALETTE.outline,
            emptySizedWidget(handle_width, handle_height),
            overlap_offset = { math.floor((width - handle_width) / 2), scale(6) },
        })
    end
    header_title.overlap_offset = { expressive and margin + scale(14) or margin, header_title_y }
    table.insert(content, header_title)
    if header_subtitle then
        header_subtitle.overlap_offset = { margin + scale(14), header_title_y + header_title:getSize().h + scale(2) }
        table.insert(content, header_subtitle)
    end
    local close_size = scale(36)
    local close = QuickCloseButton:new{ sheet = self, size = close_size }
    close.overlap_offset = {
        width - margin - close_size - (expressive and scale(8) or 0),
        math.max(scale(2), math.floor((header_height - close_size) / 2)),
    }
    table.insert(content, close)

    local tile_y = header_height + gap
    local tile_definitions = {
        wifi = {
            title = _("Wi-Fi"), symbol = "W", icon_kind = "network",
            subtitle = wifi_available and (wifi_on and _("On") or _("Off")) or _("Unavailable"),
            active = wifi_on,
            show_switch = true,
            callback = function() self:toggleWifi() end,
        },
        night = {
            title = _("Night"), symbol = "N", icon_kind = "display",
            subtitle = is_night and _("On") or _("Off"),
            active = is_night,
            show_switch = true,
            callback = function() self:toggleNightMode() end,
        },
        refresh = {
            title = _("Refresh"), symbol = "R", icon_kind = "sync",
            subtitle = _("Redraw"),
            active = false,
            callback = function() self:fullRefresh() end,
        },
        edit = {
            title = _("Edit"), symbol = "E", icon_kind = "settings",
            subtitle = _("Apps"),
            active = false,
            callback = function() self:openManager() end,
        },
        rotate = {
            title = _("Rotate"), symbol = "R", icon_kind = "rotation",
            subtitle = _("Orientation"), active = false,
            callback = function() self:rotateScreen() end,
        },
        sleep = {
            title = _("Sleep"), symbol = "Z", icon_kind = "timer",
            subtitle = _("Screen off"), active = false,
            callback = function() self:enterSleep() end,
        },
        power_saving = {
            title = _("Save power"), symbol = "P", icon_kind = "battery",
            subtitle = app_settings.power_saving and _("On") or _("Off"),
            active = app_settings.power_saving == true,
            show_switch = true,
            callback = function() self:togglePowerSaving() end,
        },
        wallpaper = {
            title = _("Background"), symbol = "B", icon_kind = "gallery",
            subtitle = wallpaper_settings.enabled and _("On") or _("Off"),
            active = wallpaper_settings.enabled == true,
            callback = function() self:toggleWallpaper() end,
        },
    }
    local tiles = {}
    for _, tile_id in ipairs(selected_tile_ids) do
        if tile_definitions[tile_id] then tiles[#tiles + 1] = tile_definitions[tile_id] end
    end
    local tile_icon_count = 0
    for index, tile in ipairs(tiles) do
        if tile.icon_kind then tile_icon_count = tile_icon_count + 1 end
        local col = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        table.insert(content, QuickTile:new{
            appdock = self.appdock,
            title = tile.title,
            symbol = tile.symbol,
            icon_kind = tile.icon_kind,
            subtitle = tile.subtitle,
            active = tile.active,
            callback = tile.callback,
            width = tile_width,
            height = tile_height,
            compact = compact,
            expressive = expressive,
            show_switch = tile.show_switch,
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
                width = action_width, height = notification_action_height, compact = true, expressive = expressive, overlap_offset = { margin, action_y },
            })
            table.insert(content, QuickTile:new{
                appdock = self.appdock, title = _("Clear all"), symbol = "×", subtitle = _("Inbox"), active = false, callback = function() self:clearNotifications() end,
                width = action_width, height = notification_action_height, compact = true, expressive = expressive, overlap_offset = { margin + action_width + gap, action_y },
            })
        end
    end
    self.layout = {
        simple_mode = simple_mode,
        expressive = expressive,
        tile_count = #tiles,
        tile_icon_count = tile_icon_count,
        has_close_button = type(close.onTapCloseQuickSettings) == "function",
        has_grab_handle = expressive,
        slider_has_thumb = self.slider._thumb_x ~= nil,
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
