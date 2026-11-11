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
local Media = require("appdock_media")
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

-- Android-style ongoing media notification (one card, drawn from a Media
-- snapshot). Taps are resolved against the regions computed in init().
local MediaCard = InputContainer:extend{
    media = nil,
    width = nil,
    height = nil,
    compact = false,
    on_action = nil,
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

local Glass = require("appdock_glass")
local GC = Glass.COLORS

local function solid(c) return Glass.solid(c) end

-- The shade has one fixed look (dark blurred glass, orange accent) taken from
-- the reference screenshots; it does not follow the AppDock colour themes.
local PALETTE = {
    sheet = solid(Glass.rgba(34, 42, 70, 255, Blitbuffer.COLOR_GRAY_4)),
    surface = solid(Glass.rgba(46, 56, 90, 255, Blitbuffer.COLOR_GRAY_4)),
    surface_variant = solid(Glass.rgba(52, 62, 98, 255, Blitbuffer.COLOR_GRAY_4)),
    primary = solid(GC.active),
    on_primary = solid(GC.on_active),
    secondary = solid(Glass.rgba(60, 70, 108, 255, Blitbuffer.COLOR_GRAY_4)),
    on_secondary = solid(GC.white),
    on_surface = solid(GC.white),
    on_variant = solid(GC.sub_inactive),
    outline = solid(Glass.rgba(120, 130, 170, 255, Blitbuffer.COLOR_GRAY_8)),
    track = solid(Glass.rgba(78, 90, 130, 255, Blitbuffer.COLOR_GRAY_6)),
}

local function applyTheme() end

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
        -- Android 16 style pill: bare white icon, bold title, state line.
        local w, h = self.width, self.height
        local k = h / 136
        local function P(v) return math.max(1, math.floor(v * k + .5)) end
        local has_icon = self.icon_kind ~= nil
        local single_line = (self.subtitle or "") == ""
        local icon_size = P(55)
        local text_x = has_icon and P(128) or P(24)
        local tw = math.max(P(40), w - text_x - P(26))
        local fg = self.active and GC.on_active or GC.white
        local sub = self.active and GC.sub_active or GC.sub_inactive
        local title_widget = TextWidget:new{
            text = self.title or "", face = Font:getFace("cfont", P(27)), fgcolor = solid(fg),
            bold = true, max_width = tw, padding = 0,
        }
        local subtitle_widget = TextWidget:new{
            text = self.subtitle or "", face = Font:getFace("cfont", P(25)), fgcolor = solid(sub),
            bold = true, max_width = tw, padding = 0,
        }
        local icon_widget = Glass.hasIcon(self.icon_kind) and Glass.Icon:new{ kind = self.icon_kind, size = icon_size, color = fg }
            or DAppLogo:new{ kind = self.icon_kind, size = icon_size, ink = solid(fg) }
        local entries = {
            { widget = Glass.Shape:new{ width = w, height = h, radius = math.floor(h / 2), color = self.active and GC.active or GC.glass }, x = 0, y = 0 },
        }
        if has_icon then
            entries[#entries + 1] = { widget = icon_widget, x = P(77) - math.floor(icon_size / 2), y = math.floor((h - icon_size) / 2) }
        end
        if single_line then
            local tsize = title_widget:getSize()
            entries[#entries + 1] = { widget = title_widget, x = has_icon and text_x or math.floor((w - tsize.w) / 2), y = math.floor((h - tsize.h) / 2) }
        else
            entries[#entries + 1] = { widget = title_widget, x = text_x, y = P(50) - math.floor(title_widget:getSize().h / 2) }
            entries[#entries + 1] = { widget = subtitle_widget, x = text_x, y = P(91) - math.floor(subtitle_widget:getSize().h / 2) }
        end
        if self.show_corner ~= false and has_icon then
            local cs = P(13)
            entries[#entries + 1] = { widget = Glass.Icon:new{ kind = "corner", size = cs, color = GC.white_soft }, x = w - P(31), y = h - P(32) }
        end
        self.layout = { title = self.title or "", subtitle = self.subtitle or "", kind = "wide", icon_kind = self.icon_kind }
        self[1] = Layout.FixedStack:new{ width = w, height = h, entries = entries }
        self.ges_events = { TapQuickTile = { GestureRange:new{ ges = "tap", range = self.dimen } } }
        return
    end
    if self.kind == "circle" then
        -- Round button with the label (max. two lines) underneath.
        local d = self.circle_diameter or scale(52)
        local k = d / 117
        local function P(v) return math.max(1, math.floor(v * k + .5)) end
        local fg = self.active and GC.on_active or GC.white
        local icon_size = math.floor(d * .47)
        local icon_widget = Glass.hasIcon(self.icon_kind) and Glass.Icon:new{ kind = self.icon_kind, size = icon_size, color = fg }
            or DAppLogo:new{ kind = self.icon_kind, size = icon_size, ink = solid(fg) }
        local entries = {
            { widget = Glass.Shape:new{ width = d, height = d, radius = math.floor(d / 2), color = self.active and GC.active or GC.glass },
                x = math.floor((self.width - d) / 2), y = 0 },
            { widget = icon_widget, x = math.floor((self.width - icon_size) / 2), y = math.floor((d - icon_size) / 2) },
        }
        local label_lines = {}
        local label_size = P(25)
        if (self.title or "") ~= "" then
            local face = Font:getFace("cfont", label_size)
            local max_w = self.width - P(4)
            local function measure(text)
                local probe = TextWidget:new{ text = text, face = face, bold = true, padding = 0 }
                local width = probe:getSize().w
                if probe.free then probe:free() end
                return width
            end
            if measure(self.title) <= max_w then
                label_lines = { self.title }
            else
                -- greedy split at a space so "Autom. drehen" becomes two lines
                local words = {}
                for word in tostring(self.title):gmatch("%S+") do words[#words + 1] = word end
                local first = words[1] or ""
                local used = 1
                for index = 2, #words do
                    local candidate = first .. " " .. words[index]
                    if measure(candidate) <= max_w and index < #words then first = candidate; used = index else break end
                end
                local rest = table.concat(words, " ", used + 1)
                label_lines = { first }
                if rest ~= "" then label_lines[2] = rest end
            end
        end
        local line_h = 0
        for index, text in ipairs(label_lines) do
            if index > 2 then break end
            local widget = TextWidget:new{ text = text, face = Font:getFace("cfont", label_size), fgcolor = solid(GC.white), bold = true, max_width = self.width, padding = 0 }
            local size = widget:getSize()
            line_h = math.max(line_h, size.h)
            entries[#entries + 1] = {
                widget = widget,
                x = math.floor((self.width - size.w) / 2),
                y = d + P(15) + (index - 1) * P(30) - math.floor((size.h - P(30)) / 2),
            }
        end
        self.layout = { title = table.concat(label_lines, " "), subtitle = "", kind = "circle", icon_kind = self.icon_kind }
        self[1] = Layout.FixedStack:new{ width = self.width, height = self.height, entries = entries }
        self.ges_events = { TapQuickTile = { GestureRange:new{ ges = "tap", range = self.dimen } } }
        return
    end
    if self.kind == "bare" then
        -- Icon without any background (header buttons).
        local size = self.circle_diameter or scale(36)
        local icon_widget = Glass.hasIcon(self.icon_kind) and Glass.Icon:new{ kind = self.icon_kind, size = size, color = GC.white }
            or DAppLogo:new{ kind = self.icon_kind, size = size, ink = solid(GC.white) }
        self.layout = { title = "", subtitle = "", kind = "bare", icon_kind = self.icon_kind }
        self[1] = Layout.FixedStack:new{ width = self.width, height = self.height, entries = {
            { widget = icon_widget, x = math.floor((self.width - size) / 2), y = math.floor((self.height - size) / 2) },
        } }
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

function MediaCard:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local media = self.media or {}
    local W, H = self.width, self.height
    local pad = scale(14)
    local on, variant = PALETTE.on_surface, PALETTE.on_variant
    local button_d = self.compact and scale(38) or scale(46)
    local glyph = self.compact and scale(20) or scale(24)
    local logo_size = scale(16)
    local entries = {}
    local regions = {}
    local function add(widget, x, y) entries[#entries + 1] = { widget = widget, x = x, y = y } end

    -- Header: app icon + name, "this device" label, stop button.
    local header_y = scale(10)
    local close_d = scale(26)
    add(DAppLogo:new{ kind = media.icon or "music", size = logo_size, ink = variant }, pad, header_y)
    local app_size = scale(10)
    local device_label = _("This device")
    local device_w = math.min(math.floor(W * .3), scale(110))
    local app_w = W - pad * 2 - logo_size - scale(6) - device_w - close_d - scale(14)
    add(TextWidget:new{
        text = Theme.fitLabel(media.app or "", math.max(scale(20), app_w), app_size, 0),
        face = Font:getFace("smallinfofont", app_size), fgcolor = variant, padding = 0,
        max_width = math.max(scale(20), app_w),
    }, pad + logo_size + scale(6), header_y)
    local pill_h = scale(22)
    local pill_x = W - pad - close_d - scale(8) - device_w
    add(FrameContainer:new{
        width = device_w, height = pill_h, padding = 0, bordersize = 0,
        radius = math.floor(pill_h / 2), background = PALETTE.track,
        emptySizedWidget(device_w, pill_h),
    }, pill_x, header_y - scale(3))
    add(TextWidget:new{
        text = Theme.fitLabel(device_label, device_w - scale(10), scale(9), 0),
        face = Font:getFace("smallinfofont", scale(9)), fgcolor = on, padding = 0,
        max_width = device_w - scale(10),
    }, pill_x + scale(8), header_y)
    local close_x = W - pad - close_d
    add(Media.Glyph:new{ kind = "close", size = close_d, color = variant }, close_x, header_y - scale(5))
    regions.stop = { x = close_x - scale(8), y = 0, w = close_d + scale(16) + pad, h = scale(40) }

    -- Title / artist + big play-pause button.
    local text_w = W - pad * 2 - button_d - scale(12)
    local title_y = header_y + logo_size + scale(10)
    local title_size = self.compact and scale(12) or scale(14)
    local artist_size = self.compact and scale(10) or scale(11)
    local title_widget = TextWidget:new{
        text = Theme.fitLabel(media.title or "", text_w, title_size, 0),
        face = Font:getFace("smallinfofont", title_size), fgcolor = on, bold = true,
        max_width = text_w, padding = 0,
    }
    add(title_widget, pad, title_y)
    add(TextWidget:new{
        text = Theme.fitLabel(media.artist or "", text_w, artist_size, 0),
        face = Font:getFace("smallinfofont", artist_size), fgcolor = variant,
        max_width = text_w, padding = 0,
    }, pad, title_y + title_widget:getSize().h + scale(2))
    local button_x = W - pad - button_d
    local button_y = title_y - scale(4)
    add(FrameContainer:new{
        width = button_d, height = button_d, padding = 0, bordersize = 0,
        radius = math.floor(button_d / 2), background = on,
        emptySizedWidget(button_d, button_d),
    }, button_x, button_y)
    add(Media.Glyph:new{ kind = media.playing and "pause" or "play", size = glyph + scale(8), color = PALETTE.sheet },
        button_x + math.floor((button_d - glyph - scale(8)) / 2), button_y + math.floor((button_d - glyph - scale(8)) / 2))
    regions.toggle = { x = button_x - scale(6), y = button_y - scale(6), w = button_d + scale(12), h = button_d + scale(12) }

    -- Controls row: previous, progress, next.
    local row_h = scale(30)
    local row_y = H - pad - row_h + scale(2)
    local skip = scale(28)
    add(Media.Glyph:new{ kind = "prev", size = skip, color = on }, pad, row_y + math.floor((row_h - skip) / 2))
    add(Media.Glyph:new{ kind = "next", size = skip, color = on }, W - pad - skip, row_y + math.floor((row_h - skip) / 2))
    regions.prev = { x = 0, y = row_y - scale(6), w = pad + skip + scale(10), h = row_h + scale(12) }
    regions.next = { x = W - pad - skip - scale(10), y = row_y - scale(6), w = pad + skip + scale(10), h = row_h + scale(12) }
    local bar_x = pad + skip + scale(12)
    local bar_w = W - 2 * bar_x
    local bar_h = scale(4)
    local bar_y = row_y + math.floor((row_h - bar_h) / 2)
    add(FrameContainer:new{
        width = bar_w, height = bar_h, padding = 0, bordersize = 0,
        radius = math.floor(bar_h / 2), background = PALETTE.track,
        emptySizedWidget(bar_w, bar_h),
    }, bar_x, bar_y)
    local ratio = math.max(0, math.min(1, tonumber(media.ratio) or 0))
    local fill_w = math.floor(bar_w * ratio)
    if fill_w > 0 then
        add(FrameContainer:new{
            width = fill_w, height = bar_h, padding = 0, bordersize = 0,
            radius = math.floor(bar_h / 2), background = on,
            emptySizedWidget(fill_w, bar_h),
        }, bar_x, bar_y)
    end
    local thumb = scale(12)
    add(FrameContainer:new{
        width = thumb, height = thumb, padding = 0, bordersize = 0,
        radius = math.floor(thumb / 2), background = on,
        emptySizedWidget(thumb, thumb),
    }, math.max(bar_x, math.min(bar_x + bar_w - thumb, bar_x + fill_w - math.floor(thumb / 2))),
        bar_y + math.floor((bar_h - thumb) / 2))
    regions.seek = { x = bar_x, y = row_y - scale(6), w = bar_w, h = row_h + scale(12), bar_w = bar_w }

    self.regions = regions
    self[1] = FrameContainer:new{
        width = W, height = H, padding = 0, bordersize = 0,
        radius = scale(24), background = PALETTE.surface_variant,
        Layout.FixedStack:new{ width = W, height = H, entries = entries },
    }
    self.ges_events = { TapMedia = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function MediaCard:paintTo(bb, x, y)
    self._x, self._y = x, y
    local range = self.ges_events.TapMedia[1].range
    range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    return InputContainer.paintTo(self, bb, x, y)
end

function MediaCard:onTapMedia(_args, ges)
    local pos = ges and ges.pos
    if not pos or not self._x then return true end
    local px, py = pos.x - self._x, pos.y - self._y
    local function inside(region)
        return region and px >= region.x and px < region.x + region.w and py >= region.y and py < region.y + region.h
    end
    local regions = self.regions or {}
    local action, argument
    if inside(regions.toggle) then action = "toggle"
    elseif inside(regions.stop) then action = "stop"
    elseif inside(regions.prev) then action = "prev"
    elseif inside(regions.next) then action = "next"
    elseif inside(regions.seek) then
        action = "seek_to"
        argument = math.max(0, math.min(1, (px - regions.seek.x) / math.max(1, regions.seek.bar_w)))
    end
    if action and self.on_action then self.on_action(action, argument) end
    return true
end

function NotificationRow:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local notification = self.notification or {}
    local k = self.height / 84
    local function P(v) return math.max(1, math.floor(v * k + .5)) end
    local text_width = math.max(P(20), self.width - P(70))
    local title_widget = TextWidget:new{ text = tostring(notification.title or _("AppDock")), face = Font:getFace("cfont", P(25)), fgcolor = solid(GC.white), bold = true, max_width = text_width, padding = 0 }
    local message_widget = TextWidget:new{ text = tostring(notification.message or ""), face = Font:getFace("cfont", P(22)), fgcolor = solid(GC.sub_inactive), max_width = text_width, padding = 0 }
    local entries = {}
    if not notification.read then
        entries[#entries + 1] = { widget = Glass.Shape:new{ width = self.width, height = self.height, radius = P(24), color = GC.glass }, x = 0, y = 0 }
        entries[#entries + 1] = { widget = Glass.Shape:new{ width = P(14), height = P(14), radius = P(7), color = GC.active }, x = self.width - P(34), y = math.floor((self.height - P(14)) / 2) }
    end
    entries[#entries + 1] = { widget = title_widget, x = P(24), y = P(14) }
    entries[#entries + 1] = { widget = message_widget, x = P(24), y = P(14) + title_widget:getSize().h + P(4) }
    self[1] = Layout.FixedStack:new{ width = self.width, height = self.height, entries = entries }
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
    local ratio = 0
    if enabled then
        ratio = math.max(0, math.min(1, (state.current - state.min) / (state.max - state.min)))
    end
    local w, h = self.width, self.height
    local k = h / 136
    local function P(v) return math.max(1, math.floor(v * k + .5)) end
    local fill_width = enabled and math.floor(w * ratio) or 0
    local icon_size = P(53)
    self.track_x, self.track_width = 0, w
    self._thumb_x, self._thumb_y = fill_width, 0
    local entries = {
        { widget = Glass.Shape:new{ width = w, height = h, radius = math.floor(h / 2), color = GC.glass }, x = 0, y = 0 },
    }
    if fill_width > 0 then
        -- light fill with a straight right edge, like Android's slider
        entries[#entries + 1] = { widget = Glass.Shape:new{ width = w, height = h, radius = math.floor(h / 2), color = GC.fill, clip_w = fill_width }, x = 0, y = 0 }
    end
    entries[#entries + 1] = { widget = Glass.Icon:new{ kind = self.icon_kind or "sun", size = icon_size, color = GC.slider_icon }, x = P(80) - math.floor(icon_size / 2), y = math.floor((h - icon_size) / 2) }
    if self.show_corner then
        entries[#entries + 1] = { widget = Glass.Icon:new{ kind = "corner", size = P(13), color = GC.white_soft }, x = w - P(31), y = h - P(32) }
    end
    self[1] = Layout.FixedStack:new{ width = w, height = h, entries = entries }
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
    if self.on_set then self.on_set(value) else self.sheet:setBrightness(value) end
    return true
end

BrightnessSlider.onTapBrightness = BrightnessSlider._setFromGesture
BrightnessSlider.onPanBrightness = BrightnessSlider._setFromGesture
BrightnessSlider.onPanReleaseBrightness = BrightnessSlider._setFromGesture

-- System volume is only offered when the device layer exposes it
-- (Device:getVolume()/Device:setVolume(0..100)); otherwise the slider is
-- drawn empty and inert instead of pretending to work.
local function getVolume()
    local ok, data = pcall(function()
        if type(Device.getVolume) ~= "function" or type(Device.setVolume) ~= "function" then return nil end
        local current = tonumber(Device:getVolume())
        if not current then return nil end
        return { min = 0, max = 100, current = math.max(0, math.min(100, current)) }
    end)
    if ok and data then return data end
    return nil
end

local function getBatteryInfo()
    local ok, capacity, charging = pcall(function()
        local powerd = Device:getPowerDevice()
        return powerd:getCapacity(), powerd:isCharging()
    end)
    if ok and type(capacity) == "number" then return math.floor(capacity), charging == true end
    return nil, false
end

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

function QuickSettings:setVolume(value)
    local state = getVolume()
    if not state or not self.volume_slider then return end
    value = math.max(state.min, math.min(state.max, value))
    if pcall(function() Device:setVolume(value) end) then
        state.current = value
        self.volume_slider:setBrightness(state)
        self:_refresh("fast", self.volume_slider.dimen, true)
    end
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
    local sw, sh = self.dimen.w, self.dimen.h
    -- Every measurement below was taken from 1512-px-wide reference
    -- screenshots (short screen side) and is scaled to the real screen.
    local scale_factor = math.min(sw, sh) / 1512
    local function R(value) return math.max(1, math.floor(value * scale_factor + .5)) end
    -- Portrait: one centred column.  Landscape: tiles in a right-hand panel,
    -- the notification card on the left (as on Android tablets).
    local landscape = sw > sh * 1.15
    local simple_mode = type(self.appdock.isSimpleModeEnabled) == "function" and self.appdock:isSimpleModeEnabled("quick_settings")

    local panel_w = R(762)
    local x0 = landscape and (sw - R(224) - panel_w) or math.floor((sw - panel_w) / 2)
    local card_w = R(805)
    local card_x = landscape and R(202) or (x0 - R(22))
    if landscape then card_w = math.max(R(300), math.min(card_w, x0 - card_x - R(30))) end
    local status_left = landscape and card_x or x0
    local status_right = x0 + panel_w - R(7)

    -- State ---------------------------------------------------------------
    local brightness = self:_brightnessState()
    local volume = getVolume()
    local wifi_on, wifi_available = getWifiState()
    local is_night = G_reader_settings:isTrue("night_mode")
    local app_settings = self.appdock.settings or {}
    local wallpaper_settings = app_settings.wallpaper or {}
    local selected_tile_ids = type(self.appdock.getQuickSettingsTiles) == "function"
        and self.appdock:getQuickSettingsTiles()
        or { "wifi", "night", "refresh", "edit" }

    local tile_definitions = {
        wifi = {
            title = _("Wi-Fi"), icon_kind = "wifi",
            subtitle = wifi_available and (wifi_on and _("On") or _("Off")) or _("Unavailable"),
            active = wifi_on, wide = true,
            callback = function() self:toggleWifi() end,
        },
        night = {
            title = _("Night"), icon_kind = "moon",
            subtitle = is_night and _("On") or _("Off"),
            active = is_night, wide = true,
            callback = function() self:toggleNightMode() end,
        },
        refresh = {
            title = _("Refresh"), icon_kind = "refresh", active = false,
            callback = function() self:fullRefresh() end,
        },
        edit = {
            title = _("Edit"), icon_kind = "gear", active = false,
            callback = function() self:openManager() end,
        },
        rotate = {
            title = _("Rotate"), icon_kind = "rotate", active = false,
            callback = function() self:rotateScreen() end,
        },
        sleep = {
            title = _("Sleep"), icon_kind = "power", active = false,
            callback = function() self:enterSleep() end,
        },
        power_saving = {
            title = _("Save power"), icon_kind = "battery",
            subtitle = app_settings.power_saving and _("On") or _("Off"),
            active = app_settings.power_saving == true, wide = true,
            callback = function() self:togglePowerSaving() end,
        },
        wallpaper = {
            title = _("Background"), icon_kind = "image",
            active = wallpaper_settings.enabled == true,
            callback = function() self:toggleWallpaper() end,
        },
    }
    local wide_tiles, circle_tiles = {}, {}
    for _i, tile_id in ipairs(selected_tile_ids) do
        local definition = tile_definitions[tile_id]
        if definition then
            if definition.wide and #wide_tiles < 2 then
                wide_tiles[#wide_tiles + 1] = definition
            else
                circle_tiles[#circle_tiles + 1] = definition
            end
        end
    end

    -- Building ------------------------------------------------------------
    local content = OverlapGroup:new{
        dimen = Geom:new{ w = sw, h = sh },
        allow_mirroring = false,
    }
    local function add(widget, x, y)
        widget.overlap_offset = { math.floor(x), math.floor(y) }
        table.insert(content, widget)
        return widget
    end

    -- Status line: time + date on the left, wifi / battery on the right.
    local status_cy = R(48)
    local time_widget = TextWidget:new{ text = os.date("%H:%M"), face = Font:getFace("cfont", R(27)), fgcolor = solid(GC.white), bold = true, padding = 0 }
    add(time_widget, status_left, status_cy - math.floor(time_widget:getSize().h / 2))
    local date_widget = TextWidget:new{ text = os.date("%a, %d. %b"), face = Font:getFace("cfont", R(27)), fgcolor = solid(GC.white), bold = true, padding = 0 }
    add(date_widget, status_left + time_widget:getSize().w + R(20), status_cy - math.floor(date_widget:getSize().h / 2))
    local cursor = status_right
    local battery, charging = getBatteryInfo()
    if charging then
        add(Glass.Icon:new{ kind = "bolt", size = R(26), color = GC.white }, cursor - R(22), status_cy - R(13))
        cursor = cursor - R(24)
    end
    if battery then
        local bw, bh, inset = R(44), R(27), R(3)
        local bx = cursor - bw
        add(Glass.Shape:new{ width = bw, height = bh, radius = R(8), color = GC.white }, bx, status_cy - math.floor(bh / 2))
        add(Glass.Shape:new{ width = bw - 2 * inset, height = bh - 2 * inset, radius = R(6), color = GC.battery_in }, bx + inset, status_cy - math.floor(bh / 2) + inset)
        local battery_text = TextWidget:new{ text = tostring(battery), face = Font:getFace("cfont", R(19)), fgcolor = solid(GC.white), bold = true, padding = 0 }
        local bsize = battery_text:getSize()
        add(battery_text, bx + math.floor((bw - bsize.w) / 2), status_cy - math.floor(bsize.h / 2))
        cursor = bx - R(18)
    end
    if wifi_on then
        add(Glass.Icon:new{ kind = "wifi", size = R(32), color = GC.white }, cursor - R(32), status_cy - R(16))
    end

    -- Header buttons (edit / settings), 127 px below the top in the reference.
    local header_cy = R(127)
    local header_box, header_icon = R(64), R(36)
    for _i, entry in ipairs({ { kind = "pencil", cx = 644 }, { kind = "gear", cx = 727 } }) do
        add(QuickTile:new{
            appdock = self.appdock, title = "", icon_kind = entry.kind, kind = "bare",
            circle_diameter = header_icon, width = header_box, height = header_box,
            callback = function() self:openManager() end,
        }, x0 + R(entry.cx) - math.floor(header_box / 2), header_cy - math.floor(header_box / 2))
    end

    -- Two columns: pills on the left, sliders on the right.
    local tile_h = R(136)
    local col_w = R(370)
    local col2_x = x0 + panel_w - col_w
    local row1_y = R(186)
    local row2_y = row1_y + tile_h + R(20)
    local tile_icon_count = 0
    for index, tile in ipairs(wide_tiles) do
        tile_icon_count = tile_icon_count + 1
        add(QuickTile:new{
            appdock = self.appdock, title = tile.title, icon_kind = tile.icon_kind,
            subtitle = tile.subtitle, active = tile.active, callback = tile.callback,
            kind = "wide", width = col_w, height = tile_h,
        }, x0, index == 1 and row1_y or row2_y)
    end
    self.volume_slider = add(BrightnessSlider:new{
        sheet = self, width = col_w, height = tile_h, brightness = volume,
        icon_kind = "headphones", show_corner = false,
        on_set = function(value) self:setVolume(value) end,
    }, col2_x, row1_y)
    self.slider = add(BrightnessSlider:new{
        sheet = self, width = col_w, height = tile_h, brightness = brightness,
        icon_kind = "sun", show_corner = true,
    }, col2_x, row2_y)

    -- Round tiles: five columns, label underneath (max. two lines).
    local circle_d = R(117)
    local cell_w = math.floor(panel_w / 5)
    local circle_cell_h = circle_d + R(80)
    local circle_top = R(528)
    local circle_pitch = R(198)
    local circle_rows = math.ceil(#circle_tiles / 5)
    for index, tile in ipairs(circle_tiles) do
        tile_icon_count = tile_icon_count + 1
        local col = (index - 1) % 5
        local row = math.floor((index - 1) / 5)
        add(QuickTile:new{
            appdock = self.appdock, title = tile.title, icon_kind = tile.icon_kind,
            active = tile.active, callback = tile.callback,
            kind = "circle", circle_diameter = circle_d, width = cell_w, height = circle_cell_h,
        }, x0 + col * cell_w, circle_top + row * circle_pitch)
    end

    local panel_bottom = row2_y + tile_h
    local pager_y
    if circle_rows > 0 then
        pager_y = circle_top + (circle_rows - 1) * circle_pitch + R(209)
        panel_bottom = pager_y + R(20)
    end
    if pager_y and not simple_mode then
        local bar_w, bar_h = R(134), R(6)
        add(Glass.Shape:new{ width = bar_w, height = bar_h, radius = math.floor(bar_h / 2), color = GC.pager },
            x0 + math.floor((panel_w - bar_w) / 2), pager_y - math.floor(bar_h / 2))
    end

    -- Card column: ongoing media + notifications -------------------------------
    local card_y = landscape and R(94) or (panel_bottom + R(35))
    local media_snapshot = Media.snapshot()
    if media_snapshot then
        local media_h = scale(132)
        add(MediaCard:new{
            media = media_snapshot, width = card_w, height = media_h, compact = false,
            on_action = function(action, argument)
                Media.invoke(action, argument)
                self:rebuild(true)
            end,
        }, card_x, card_y)
        card_y = card_y + media_h + R(20)
    end
    local cards_top = card_y
    local show_notifications = not simple_mode
    local notification_items = show_notifications and self.appdock:getNotifications(3) or {}
    local unread_notifications = self.appdock:getUnreadNotificationCount()
    local cards_bottom = card_y
    if show_notifications then
        local card_radius = R(34)
        if #notification_items == 0 then
            local card_h = R(108)
            add(Glass.Shape:new{ width = card_w, height = card_h, radius = card_radius, color = GC.glass }, card_x, card_y)
            local empty = TextWidget:new{ text = _("No notifications"), face = Font:getFace("cfont", R(27)), fgcolor = solid(GC.white), bold = true, max_width = card_w - R(40), padding = 0 }
            local esize = empty:getSize()
            add(empty, card_x + math.floor((card_w - esize.w) / 2), card_y + math.floor((card_h - esize.h) / 2))
            cards_bottom = card_y + card_h
        else
            local pad, row_h, row_gap, action_h = R(16), R(84), R(8), R(56)
            local card_h = pad + #notification_items * (row_h + row_gap) + action_h + pad - row_gap
            add(Glass.Shape:new{ width = card_w, height = card_h, radius = card_radius, color = GC.glass }, card_x, card_y)
            for index, notification in ipairs(notification_items) do
                add(NotificationRow:new{
                    notification = notification, width = card_w - 2 * pad, height = row_h,
                    callback = function()
                        self.appdock:markNotificationRead(notification.id)
                        self:rebuild(true)
                    end,
                }, card_x + pad, card_y + pad + (index - 1) * (row_h + row_gap))
            end
            local action_y = card_y + card_h - pad - action_h
            local action_w = math.floor((card_w - 2 * pad - R(12)) / 2)
            add(QuickTile:new{
                appdock = self.appdock, title = _("Read all"), active = false, callback = function() self:markAllNotificationsRead() end,
                kind = "wide", width = action_w, height = action_h, show_corner = false,
            }, card_x + pad, action_y)
            add(QuickTile:new{
                appdock = self.appdock, title = _("Clear all"), active = false, callback = function() self:clearNotifications() end,
                kind = "wide", width = action_w, height = action_h, show_corner = false,
            }, card_x + pad + action_w + R(12), action_y)
            cards_bottom = card_y + card_h
        end
    end

    -- Hit areas: a tap outside all of them closes the shade.
    self.hit_rects = {
        Geom:new{ x = x0 - R(24), y = 0, w = panel_w + R(48), h = panel_bottom },
    }
    if cards_bottom > cards_top or media_snapshot then
        self.hit_rects[#self.hit_rects + 1] = Geom:new{ x = card_x, y = landscape and R(94) or (panel_bottom + R(35)), w = card_w, h = math.max(R(108), cards_bottom - (landscape and R(94) or (panel_bottom + R(35)))) }
    end
    self.sheet_frame = { dimen = self.hit_rects[1] }
    self.sheet_height = math.max(panel_bottom, cards_bottom)

    self.layout = {
        simple_mode = simple_mode,
        landscape_panel = landscape,
        glass = true,
        tile_count = #wide_tiles + #circle_tiles,
        tile_icon_count = tile_icon_count,
        has_close_button = true,
        has_grab_handle = pager_y ~= nil and not simple_mode,
        slider_has_thumb = self.slider._thumb_x ~= nil,
        show_notifications = show_notifications,
        compact = false,
        tile_y = row1_y,
        tile_height = tile_h,
        gap = R(20),
        slider_y = row2_y,
        slider_height = tile_h,
        content_bottom = math.max(panel_bottom, cards_bottom),
        sheet_height = self.sheet_height,
        panel_x = x0,
        panel_w = panel_w,
        card_x = card_x,
        card_w = card_w,
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
    -- Do not allocate or blit a second native buffer here. Some Android
    -- KOReader builds can destroy a Blitbuffer mutex while a queued repaint
    -- still references it, which crashes the process before Lua can recover.
    -- The Glass tiles and sheet are self-contained and remain fully usable.
    return InputContainer.paintTo(self, bb, x, y)
end

function QuickSettings:onTapOutsideQuickSettings(arg, ges_ev)
    if ges_ev and ges_ev.pos then
        for _i, rect in ipairs(self.hit_rects or {}) do
            if ges_ev.pos:intersectWith(rect) then return true end
        end
        self:onClose()
    end
    return true
end

function QuickSettings:onShow()
    self:_refresh("ui", nil, true)
    return true
end

function QuickSettings:onCloseWidget()
    self._backdrop = nil
    self:_refresh("ui", nil, true)
end

function QuickSettings:onClose()
    UIManager:close(self)
    self:_refresh("ui", nil, true)
    return true
end

return QuickSettings
