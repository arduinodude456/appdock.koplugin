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
    kind = nil,
    circle_diameter = nil,
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
    if self.kind == "wide" then
        -- Android-style pill tile: bare icon on the left, bold title and
        -- state line next to it, fully rounded ends.
        local h = self.height
        local icon_size = math.max(scale(16), math.min(scale(26), math.floor(h * .42)))
        local icon_x = math.floor(h * .36)
        local text_x = icon_x + icon_size + scale(12)
        local tw = math.max(scale(18), self.width - text_x - scale(16))
        local t_size = math.max(scale(9), math.min(scale(14), math.floor(h * .23)))
        local s_size = math.max(scale(8), math.min(scale(12), math.floor(h * .19)))
        local wide_title = Theme.fitLabel(self.title or "", tw, t_size, 0)
        local wide_subtitle = Theme.fitLabel(self.subtitle or "", tw, s_size, 0)
        local icon_widget = self.icon_kind and DAppLogo:new{ kind = self.icon_kind, size = icon_size, ink = foreground }
            or TextWidget:new{ text = self.symbol, face = Font:getFace("cfont", icon_size), fgcolor = foreground, bold = true, padding = 0 }
        local title_widget = TextWidget:new{
            text = wide_title, face = Font:getFace("smallinfofont", t_size), fgcolor = foreground,
            bold = true, max_width = tw, padding = 0,
        }
        local subtitle_widget = TextWidget:new{
            text = wide_subtitle, face = Font:getFace("smallinfofont", s_size),
            fgcolor = self.active and PALETTE.on_primary or PALETTE.on_variant, max_width = tw, padding = 0,
        }
        local positions = Theme.centeredStack(h, { title_widget, subtitle_widget }, scale(2), scale(3))
        self.layout = { title = wide_title, subtitle = wide_subtitle, kind = "wide", icon_kind = self.icon_kind }
        self[1] = FrameContainer:new{
            width = self.width, height = h, padding = 0, bordersize = 0,
            radius = math.floor(h / 2), background = background,
            Layout.FixedStack:new{
                width = self.width, height = h,
                entries = {
                    { widget = CenterContainer:new{ dimen = Geom:new{ w = icon_size, h = icon_size }, icon_widget }, x = icon_x, y = math.floor((h - icon_size) / 2) },
                    { widget = title_widget, x = text_x, y = positions[1] },
                    { widget = subtitle_widget, x = text_x, y = positions[2] },
                },
            },
        }
        self.ges_events = { TapQuickTile = { GestureRange:new{ ges = "tap", range = self.dimen } } }
        return
    end
    if self.kind == "circle" then
        -- Android-style round button with the label underneath.
        local d = self.circle_diameter or scale(52)
        local has_label = (self.title or "") ~= ""
        local icon_size = math.max(scale(14), math.min(scale(28), math.floor(d * .5)))
        local icon_widget = self.icon_kind and DAppLogo:new{ kind = self.icon_kind, size = icon_size, ink = foreground }
            or TextWidget:new{ text = self.symbol, face = Font:getFace("cfont", icon_size), fgcolor = foreground, bold = true, padding = 0 }
        local circle = FrameContainer:new{
            width = d, height = d, padding = 0, bordersize = 0,
            radius = math.floor(d / 2), background = background,
            CenterContainer:new{ dimen = Geom:new{ w = d, h = d }, icon_widget },
        }
        local entries = { { widget = circle, x = math.floor((self.width - d) / 2), y = 0 } }
        local label_text = ""
        if has_label then
            local label_size = scale(11)
            label_text = Theme.fitLabel(self.title, math.max(scale(20), self.width - scale(2)), label_size, 0)
            local label_widget = TextWidget:new{
                text = label_text, face = Font:getFace("smallinfofont", label_size),
                fgcolor = PALETTE.on_surface, max_width = self.width, padding = 0,
            }
            entries[2] = {
                widget = CenterContainer:new{ dimen = Geom:new{ w = self.width, h = label_widget:getSize().h }, label_widget },
                x = 0, y = d + scale(6),
            }
        end
        self.layout = { title = label_text, subtitle = "", kind = "circle", icon_kind = self.icon_kind }
        self[1] = FrameContainer:new{
            width = self.width, height = self.height, padding = 0, bordersize = 0,
            Layout.FixedStack:new{ width = self.width, height = self.height, entries = entries },
        }
        self.ges_events = { TapQuickTile = { GestureRange:new{ ges = "tap", range = self.dimen } } }
        return
    end
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
    if self.callback and self._switch_knob then
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
    local w, h = self.width, self.height
    -- The whole pill is the touch target; the fill never gets narrower than
    -- the icon circle, exactly like Android's brightness slider.
    local fill_width = enabled and math.max(h, math.floor(w * percentage)) or 0
    local icon_size = math.max(scale(16), math.min(scale(24), math.floor(h * .42)))
    self.track_x, self.track_width = 0, w
    self._thumb_x, self._thumb_y = fill_width, 0

    local children = {
        dimen = Geom:new{ w = w, h = h },
        allow_mirroring = false,
        FrameContainer:new{
            width = w, height = h, padding = 0, bordersize = 0,
            radius = math.floor(h / 2), background = PALETTE.surface_variant,
            emptySizedWidget(w, h),
        },
    }
    if fill_width > 0 then
        table.insert(children, FrameContainer:new{
            width = fill_width, height = h, padding = 0, bordersize = 0,
            radius = math.floor(h / 2), background = PALETTE.primary,
            overlap_offset = { 0, 0 },
            emptySizedWidget(fill_width, h),
        })
    end
    table.insert(children, DAppLogo:new{
        kind = "display", size = icon_size,
        ink = enabled and PALETTE.on_primary or PALETTE.on_variant,
        overlap_offset = { math.floor((h - icon_size) / 2), math.floor((h - icon_size) / 2) },
    })
    if not enabled then
        local label = TextWidget:new{
            text = _("Unavailable"), face = Font:getFace("smallinfofont", scale(12)),
            fgcolor = PALETTE.on_variant, padding = 0,
        }
        label.overlap_offset = { h + scale(4), math.floor((h - label:getSize().h) / 2) }
        table.insert(children, label)
    end
    self[1] = OverlapGroup:new(children)
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
    local screen_w = self.dimen.w
    -- On wide (landscape) screens the shade becomes a right-hand panel like
    -- Android tablets; on portrait screens it spans the full width.
    local landscape = screen_w > self.dimen.h * 1.15
    local sheet_w = landscape and math.floor(screen_w * 0.5) or screen_w
    local ox = screen_w - sheet_w
    local margin = scale(20)
    local gap = scale(10)
    local header_height = scale(60)
    local wide_height = scale(64)
    local slider_height = scale(56)
    local circle_d = scale(52)
    local circle_label = scale(24)
    local pager_height = scale(16)
    local sheet_bottom = scale(16)
    local maximum_sheet_height = math.floor(self.dimen.h * 0.92)
    local notification_title_height = scale(24)
    local notification_row_height = scale(42)
    local notification_action_height = scale(34)
    local simple_mode = type(self.appdock.isSimpleModeEnabled) == "function" and self.appdock:isSimpleModeEnabled("quick_settings")
    local expressive = not simple_mode and type(self.appdock.isExpressiveUiEnabled) == "function" and self.appdock:isExpressiveUiEnabled()

    local header_title = TextWidget:new{
        text = os.date("%A, %d %B"),
        face = Font:getFace("cfont", scale(20)),
        fgcolor = PALETTE.on_surface,
        bold = true,
        padding = 0,
    }

    -- State ---------------------------------------------------------------
    local brightness = self:_brightnessState()
    local wifi_on, wifi_available = getWifiState()
    local is_night = G_reader_settings:isTrue("night_mode")
    local unread_notifications = self.appdock:getUnreadNotificationCount()
    local app_settings = self.appdock.settings or {}
    local wallpaper_settings = app_settings.wallpaper or {}
    local selected_tile_ids = type(self.appdock.getQuickSettingsTiles) == "function"
        and self.appdock:getQuickSettingsTiles()
        or { "wifi", "night", "refresh", "edit" }

    local tile_definitions = {
        wifi = {
            title = _("Wi-Fi"), symbol = "W", icon_kind = "network",
            subtitle = wifi_available and (wifi_on and _("On") or _("Off")) or _("Unavailable"),
            active = wifi_on, wide = true,
            callback = function() self:toggleWifi() end,
        },
        night = {
            title = _("Night"), symbol = "N", icon_kind = "display",
            subtitle = is_night and _("On") or _("Off"),
            active = is_night, wide = true,
            callback = function() self:toggleNightMode() end,
        },
        refresh = {
            title = _("Refresh"), symbol = "R", icon_kind = "sync",
            subtitle = _("Redraw"), active = false,
            callback = function() self:fullRefresh() end,
        },
        edit = {
            title = _("Edit"), symbol = "E", icon_kind = "settings",
            subtitle = _("Apps"), active = false,
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
            active = app_settings.power_saving == true, wide = true,
            callback = function() self:togglePowerSaving() end,
        },
        wallpaper = {
            title = _("Background"), symbol = "B", icon_kind = "gallery",
            subtitle = wallpaper_settings.enabled and _("On") or _("Off"),
            active = wallpaper_settings.enabled == true,
            callback = function() self:toggleWallpaper() end,
        },
    }
    local wide_tiles, circle_tiles = {}, {}
    for _i, tile_id in ipairs(selected_tile_ids) do
        local definition = tile_definitions[tile_id]
        if definition then
            if definition.wide then
                wide_tiles[#wide_tiles + 1] = definition
            else
                circle_tiles[#circle_tiles + 1] = definition
            end
        end
    end

    -- Measuring -----------------------------------------------------------
    local inner_w = sheet_w - 2 * margin
    local cols = math.max(3, math.min(5, math.floor((inner_w + gap) / (scale(76) + gap))))
    local show_notifications, notification_items, notification_count, notification_height
    local wide_rows, circle_rows, wide_area, circle_area, natural_height
    local show_pager = not simple_mode
    local function recalc(max_notifications)
        show_notifications = not simple_mode and max_notifications > 0
        notification_items = show_notifications and self.appdock:getNotifications(max_notifications) or {}
        notification_count = #notification_items
        notification_height = show_notifications
            and (notification_title_height + notification_count * (notification_row_height + gap) + (notification_count > 0 and notification_action_height + gap or 0))
            or 0
        wide_rows = math.ceil(#wide_tiles / 2)
        circle_rows = math.ceil(#circle_tiles / cols)
        wide_area = wide_rows > 0 and (wide_rows * wide_height + (wide_rows - 1) * gap) or 0
        circle_area = circle_rows > 0 and (circle_rows * (circle_d + circle_label) + (circle_rows - 1) * gap) or 0
        natural_height = header_height
            + (wide_area > 0 and (wide_area + gap) or 0)
            + slider_height + gap
            + (circle_area > 0 and (circle_area + gap) or 0)
            + (show_pager and pager_height or 0)
            + (show_notifications and (notification_height + gap) or 0)
            + sheet_bottom
    end
    recalc(3)
    local compact = natural_height > maximum_sheet_height
    if compact then
        gap = scale(8)
        header_height = scale(50)
        wide_height = scale(52)
        slider_height = scale(46)
        circle_d = scale(44)
        circle_label = scale(20)
        pager_height = scale(12)
        sheet_bottom = scale(12)
        notification_title_height = scale(20)
        notification_row_height = scale(36)
        notification_action_height = scale(30)
        recalc(1)
        if natural_height > maximum_sheet_height or self.dimen.h < scale(360) then
            recalc(0)
        end
    end
    header_height = math.max(header_height, header_title:getSize().h + scale(16))
    local tile_width = math.floor((inner_w - gap) / 2)
    local cell_width = math.floor((inner_w - (cols - 1) * gap) / cols)
    self.sheet_height = math.min(natural_height, self.dimen.h)

    -- Building ------------------------------------------------------------
    local content = OverlapGroup:new{
        dimen = Geom:new{ w = screen_w, h = self.dimen.h },
        allow_mirroring = false,
    }
    self.sheet_frame = FrameContainer:new{
        width = sheet_w,
        height = self.sheet_height,
        padding = 0,
        bordersize = scale(1),
        color = PALETTE.outline,
        radius = scale(28),
        background = PALETTE.sheet,
        overlap_offset = { ox, 0 },
        emptySizedWidget(sheet_w, self.sheet_height),
    }
    table.insert(content, self.sheet_frame)

    -- Header: date on the left, settings + close buttons on the right.
    header_title.overlap_offset = { ox + margin, math.max(scale(3), math.floor((header_height - header_title:getSize().h) / 2)) }
    table.insert(content, header_title)
    local close_size = scale(36)
    local button_y = math.max(scale(2), math.floor((header_height - close_size) / 2))
    local close = QuickCloseButton:new{ sheet = self, size = close_size }
    close.overlap_offset = { ox + sheet_w - margin - close_size, button_y }
    table.insert(content, close)
    table.insert(content, QuickTile:new{
        appdock = self.appdock, title = "", symbol = "E", icon_kind = "settings",
        kind = "circle", circle_diameter = close_size,
        width = close_size, height = close_size, active = false,
        callback = function() self:openManager() end,
        overlap_offset = { ox + sheet_w - margin - 2 * close_size - gap, button_y },
    })

    local cursor_y = header_height
    local tile_icon_count = 0
    local first_tile_y = cursor_y

    -- Wide pill tiles (two per row).
    for index, tile in ipairs(wide_tiles) do
        if tile.icon_kind then tile_icon_count = tile_icon_count + 1 end
        local col = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        table.insert(content, QuickTile:new{
            appdock = self.appdock, title = tile.title, symbol = tile.symbol, icon_kind = tile.icon_kind,
            subtitle = tile.subtitle, active = tile.active, callback = tile.callback,
            kind = "wide", width = tile_width, height = wide_height,
            overlap_offset = { ox + margin + col * (tile_width + gap), cursor_y + row * (wide_height + gap) },
        })
    end
    if wide_area > 0 then cursor_y = cursor_y + wide_area + gap end

    -- Brightness pill.
    self.slider = BrightnessSlider:new{
        sheet = self,
        width = inner_w,
        height = slider_height,
        brightness = brightness,
        overlap_offset = { ox + margin, cursor_y },
    }
    table.insert(content, self.slider)
    local slider_y = cursor_y
    cursor_y = cursor_y + slider_height + gap

    -- Round tiles with labels underneath.
    local circle_cell_height = circle_d + circle_label
    for index, tile in ipairs(circle_tiles) do
        if tile.icon_kind then tile_icon_count = tile_icon_count + 1 end
        local col = (index - 1) % cols
        local row = math.floor((index - 1) / cols)
        table.insert(content, QuickTile:new{
            appdock = self.appdock, title = tile.title, symbol = tile.symbol, icon_kind = tile.icon_kind,
            subtitle = tile.subtitle, active = tile.active, callback = tile.callback,
            kind = "circle", circle_diameter = circle_d, width = cell_width, height = circle_cell_height,
            overlap_offset = { ox + margin + col * (cell_width + gap), cursor_y + row * (circle_cell_height + gap) },
        })
    end
    if circle_area > 0 then cursor_y = cursor_y + circle_area + gap end

    -- Page indicator (decorative, like Android's tile page bar).
    if show_pager then
        local bar_w, bar_h = scale(56), scale(4)
        table.insert(content, FrameContainer:new{
            width = bar_w, height = bar_h, padding = 0, bordersize = 0,
            radius = math.floor(bar_h / 2), background = PALETTE.track,
            emptySizedWidget(bar_w, bar_h),
            overlap_offset = { ox + math.floor((sheet_w - bar_w) / 2), cursor_y },
        })
        cursor_y = cursor_y + pager_height
    end

    -- Notifications ---------------------------------------------------------
    local notifications_y = cursor_y
    if show_notifications then
        table.insert(content, TextWidget:new{
            text = unread_notifications > 0 and string.format(_("Notifications · %d unread"), unread_notifications) or _("Notifications · all caught up"),
            face = Font:getFace("smallinfofont", compact and scale(12) or scale(14)), fgcolor = PALETTE.on_surface, bold = true,
            overlap_offset = { ox + margin, notifications_y },
        })
        if notification_count == 0 then
            table.insert(content, TextWidget:new{
                text = _("No notifications yet"), face = Font:getFace("smallinfofont", scale(10)), fgcolor = PALETTE.on_variant,
                overlap_offset = { ox + margin, notifications_y + notification_title_height },
            })
        else
            for index, notification in ipairs(notification_items) do
                table.insert(content, NotificationRow:new{
                    notification = notification, width = inner_w, height = notification_row_height,
                    callback = function()
                        self.appdock:markNotificationRead(notification.id)
                        self:rebuild(true)
                    end,
                    overlap_offset = { ox + margin, notifications_y + notification_title_height + (index - 1) * (notification_row_height + gap) },
                })
            end
            local action_y = notifications_y + notification_title_height + notification_count * (notification_row_height + gap)
            local action_width = math.floor((inner_w - gap) / 2)
            table.insert(content, QuickTile:new{
                appdock = self.appdock, title = _("Read all"), symbol = "✓", subtitle = _("Inbox"), active = false, callback = function() self:markAllNotificationsRead() end,
                width = action_width, height = notification_action_height, compact = true, overlap_offset = { ox + margin, action_y },
            })
            table.insert(content, QuickTile:new{
                appdock = self.appdock, title = _("Clear all"), symbol = "×", subtitle = _("Inbox"), active = false, callback = function() self:clearNotifications() end,
                width = action_width, height = notification_action_height, compact = true, overlap_offset = { ox + margin + action_width + gap, action_y },
            })
        end
    end
    self.layout = {
        simple_mode = simple_mode,
        expressive = expressive,
        landscape_panel = landscape,
        tile_count = #wide_tiles + #circle_tiles,
        tile_icon_count = tile_icon_count,
        has_close_button = type(close.onTapCloseQuickSettings) == "function",
        has_grab_handle = show_pager,
        slider_has_thumb = self.slider._thumb_x ~= nil,
        show_notifications = show_notifications,
        compact = compact,
        tile_y = first_tile_y,
        tile_height = wide_height,
        gap = gap,
        slider_y = slider_y,
        slider_height = slider_height,
        content_bottom = show_notifications and (notifications_y + notification_height) or cursor_y,
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
