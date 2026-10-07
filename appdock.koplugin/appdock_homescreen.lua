--[[--
AppDock's Android-inspired E-Ink launcher.
It adopts a compact status row, a single-line search pill, glanceable widgets,
a labeled app grid and a fixed icon-only dock, with high-contrast surfaces that
remain legible and inexpensive to refresh on E-Ink screens.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalSpan = require("ui/widget/horizontalspan")
local AppDockKeyboard = require("appdock_keyboard")
local DeviceControls = require("appdock_device_controls")
local InputContainer = require("ui/widget/container/inputcontainer")
local DAppLogo = require("appdock_logo")
local Layout = require("appdock_layout")
local Theme = require("appdock_theme")
local Wallpaper = require("appdock_wallpaper")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Screen = Device.screen

local AppDockHomeScreen = InputContainer:extend{
    appdock = nil,
    page = 1,
    covers_fullscreen = true,
}

local AppTile = InputContainer:extend{
    app = nil,
    appdock = nil,
    home = nil,
    tile_size = nil,
    label_height = nil,
    label_width = nil,
    background = nil,
    foreground = nil,
    symbol = nil,
    hide_label = false,
    is_dock_item = false,
    shape = "rounded",
}

local InfoCard = WidgetContainer:extend{
    width = nil,
    height = nil,
    title = nil,
    body = nil,
    background = nil,
    foreground = nil,
}

local StoreWidgetCard = InputContainer:extend{
    widget = nil,
    appdock = nil,
    home = nil,
    width = nil,
    height = nil,
    background = nil,
    foreground = nil,
    edit_mode = false,
    widget_scale = 1,
    widget_position = nil,
}

local WidgetScaleButton = InputContainer:extend{
    home = nil,
    widget_id = nil,
    delta = nil,
    title = nil,
    width = nil,
    height = nil,
}

local HomeEditButton = InputContainer:extend{
    home = nil,
    width = nil,
    height = nil,
    title = nil,
}

local SearchBar = InputContainer:extend{
    appdock = nil,
    home = nil,
    width = nil,
    height = nil,
    query = "",
}

local SearchGlyph = Widget:extend{
    size = 16,
    ink = nil,
    dimen = nil,
}

local AppDrawerGlyph = Widget:extend{
    size = 32,
    ink = nil,
    dimen = nil,
}

local DuckDuckGoBar = InputContainer:extend{
    appdock = nil,
    home = nil,
    width = nil,
    height = nil,
    query = "",
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

-- A single calm blue-lilac Material-You-like palette. On monochrome devices,
-- every surface maps to a KOReader gray level with the same contrast role.
local PALETTE = {
    background = color(250, 248, 255, Blitbuffer.COLOR_WHITE),
    surface = color(242, 240, 247, Blitbuffer.COLOR_LIGHT_GRAY),
    surface_variant = color(229, 226, 236, Blitbuffer.COLOR_GRAY_8),
    primary_container = color(214, 227, 255, Blitbuffer.COLOR_GRAY_8),
    on_primary_container = color(23, 59, 111, Blitbuffer.COLOR_DARK_GRAY),
    secondary_container = color(225, 221, 242, Blitbuffer.COLOR_GRAY_7),
    on_secondary_container = color(59, 54, 79, Blitbuffer.COLOR_DARK_GRAY),
    tertiary_container = color(239, 216, 244, Blitbuffer.COLOR_GRAY_7),
    on_tertiary_container = color(83, 45, 90, Blitbuffer.COLOR_DARK_GRAY),
    on_surface = color(31, 29, 36, Blitbuffer.COLOR_BLACK),
    on_surface_variant = color(76, 73, 84, Blitbuffer.COLOR_DARK_GRAY),
    outline = color(121, 117, 128, Blitbuffer.COLOR_GRAY),
    -- DuckDuckGo's own brand accent. It deliberately survives every AppDock
    -- theme so the search bar keeps its recognizable identity; on monochrome
    -- panels it becomes a solid black badge with a white magnifier.
    duckduckgo = color(222, 88, 51, Blitbuffer.COLOR_BLACK),
    on_duckduckgo = color(255, 255, 255, Blitbuffer.COLOR_WHITE),
}

local APP_TONES = {
    { background = PALETTE.primary_container, foreground = PALETTE.on_primary_container },
    { background = PALETTE.secondary_container, foreground = PALETTE.on_secondary_container },
    { background = PALETTE.tertiary_container, foreground = PALETTE.on_tertiary_container },
}

local function applyTheme(appdock)
    local palette = Theme.getPalette(appdock)
    PALETTE.background = palette.background
    PALETTE.surface = palette.surface
    PALETTE.surface_variant = palette.surface_variant
    PALETTE.primary_container = palette.button or palette.primary
    PALETTE.on_primary_container = palette.on_button or palette.on_primary
    PALETTE.secondary_container = palette.secondary
    PALETTE.on_secondary_container = palette.on_secondary
    PALETTE.tertiary_container = palette.tertiary
    PALETTE.on_tertiary_container = palette.on_tertiary
    PALETTE.on_surface = palette.on_surface
    PALETTE.on_surface_variant = palette.on_variant
    PALETTE.outline = palette.outline
    APP_TONES[1] = { background = PALETTE.primary_container, foreground = PALETTE.on_primary_container }
    APP_TONES[2] = { background = PALETTE.secondary_container, foreground = PALETTE.on_secondary_container }
    APP_TONES[3] = { background = PALETTE.tertiary_container, foreground = PALETTE.on_tertiary_container }
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

local function safeBatteryText()
    local ok, capacity = pcall(function()
        local powerd = Device:getPowerDevice()
        if not powerd then return nil end
        return powerd:getCapacity()
    end)
    if ok and type(capacity) == "number" then
        return string.format(_("Battery %d%%"), math.floor(capacity + 0.5))
    end
    return nil
end

local function currentBookText(appdock)
    local document = appdock.ui and appdock.ui.document
    if document and type(document.file) == "string" then
        local filename = document.file:match("([^/\\]+)$")
        if filename and filename ~= "" then
            return filename
        end
    end
    return _("Choose a book from your library")
end

local function appSectionLabel(count)
    return string.format(_("Apps  ·  %d"), tonumber(count) or 0)
end

local function iconFor(app)
    local symbols = {
        ["system:library"] = "B",
        ["system:menu"] = "M",
        ["system:history"] = "V",
        ["system:manage"] = "E",
    }
    if symbols[app.id] then
        return symbols[app.id]
    end
    return (app.title or "?"):sub(1, 1):upper()
end

local function toneFor(app, index)
    local system_tones = {
        ["system:library"] = 1,
        ["system:menu"] = 2,
        ["system:history"] = 3,
        ["system:manage"] = 1,
    }
    return APP_TONES[system_tones[app.id] or ((index - 1) % #APP_TONES + 1)]
end

function InfoCard:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local title_size = Theme.adjustText(self.appdock, math.max(scale(12), math.min(scale(16), math.floor(self.height * .22))), scale(10))
    local body_size = Theme.adjustText(self.appdock, math.max(scale(14), math.min(scale(20), math.floor(self.height * .32))), scale(11))
    local text_width = math.max(scale(12), self.width - 2 * scale(18))
    local title = Theme.fitLabel(self.title or "", text_width, title_size, 0)
    local body = Theme.fitLabel(self.body or "", text_width, body_size, 0)
    local title_widget = TextWidget:new{ text = title, face = Font:getFace("smallinfofont", title_size), fgcolor = PALETTE.on_surface_variant, bold = true, max_width = text_width, padding = 0 }
    local body_widget = TextWidget:new{ text = body, face = Font:getFace("smallinfofont", body_size), fgcolor = PALETTE.on_surface, max_width = text_width, padding = 0 }
    local positions = Theme.centeredStack(self.height, { title_widget, body_widget }, scale(4), scale(5))
    self[1] = FrameContainer:new{
        width = self.width,
        height = self.height,
        padding = 0,
        bordersize = scale(1),
        color = self.appdock and self.appdock.settings.beta and self.appdock.settings.beta.black_borders and Blitbuffer.COLOR_BLACK or PALETTE.outline,
        radius = math.floor(self.height * 0.34),
        background = self.background or PALETTE.surface,
        Layout.FixedStack:new{
            width = self.width,
            height = self.height,
            entries = {
                { widget = title_widget, x = scale(18), y = positions[1] },
                { widget = body_widget, x = scale(18), y = positions[2] },
            },
        },
    }
end

function StoreWidgetCard:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local definition = self.widget.definition
    local context = {
        appdock = self.appdock,
        manager = self.appdock:getDAppManager(),
        dimen = self.dimen,
    }
    local ok, content = pcall(definition.buildWidget, self.widget.instance, context)
    if not ok or not content then
        content = TextWidget:new{
            text = _("This widget could not be displayed."),
            face = Font:getFace("smallinfofont", Theme.adjustText(self.appdock, scale(12), scale(9))),
            fgcolor = self.foreground or PALETTE.on_surface,
            max_width = self.width - scale(20),
        }
    end
    local card_children = { CenterContainer:new{ dimen = self.dimen, content } }
    if self.edit_mode then
        local button_size, button_gap = scale(32), scale(6)
        local scale_percent = math.floor((tonumber(self.widget_scale) or 1) * 100 + .5)
        card_children[#card_children + 1] = TextWidget:new{
            text = string.format(_("Size: %d%%"), scale_percent),
            face = Font:getFace("smallinfofont", scale(11)),
            fgcolor = self.foreground or PALETTE.on_surface,
            max_width = scale(78), padding = 0,
            overlap_offset = { self.width - 2 * button_size - 2 * button_gap - scale(80), button_gap + scale(7) },
        }
        card_children[#card_children + 1] = WidgetScaleButton:new{
            home = self.home, widget_id = self.widget.widget_id, delta = -.25,
            title = "−", width = button_size, height = button_size,
            overlap_offset = { self.width - 2 * button_size - 2 * button_gap, button_gap },
        }
        card_children[#card_children + 1] = WidgetScaleButton:new{
            home = self.home, widget_id = self.widget.widget_id, delta = .25,
            title = "+", width = button_size, height = button_size,
            overlap_offset = { self.width - button_size - button_gap, button_gap },
        }
        self.ges_events = {
            PanMoveStoreWidget = { GestureRange:new{ ges = "pan", range = self.dimen } },
            PanReleaseMoveStoreWidget = { GestureRange:new{ ges = "pan_release", range = self.dimen } },
        }
    end
    self[1] = FrameContainer:new{
        width = self.width,
        height = self.height,
        padding = 0,
        bordersize = scale(1),
        color = self.appdock.settings.beta and self.appdock.settings.beta.black_borders and Blitbuffer.COLOR_BLACK or PALETTE.outline,
        radius = math.floor(self.height * 0.30),
        background = self.background or PALETTE.surface,
        OverlapGroup:new{ dimen = self.dimen, allow_mirroring = false, unpack(card_children) },
    }
end

function StoreWidgetCard:paintTo(bb, x, y)
    if self.ges_events then
        for _, name in ipairs({ "PanMoveStoreWidget", "PanReleaseMoveStoreWidget" }) do
            local range = self.ges_events[name][1].range
            range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
        end
    end
    return InputContainer.paintTo(self, bb, x, y)
end

function StoreWidgetCard:onPanMoveStoreWidget()
    return self.edit_mode == true
end

function StoreWidgetCard:onPanReleaseMoveStoreWidget(_, gesture_event)
    local pos = gesture_event and gesture_event.pos
    if not self.edit_mode or not pos or not self.home then return false end
    return self.home:moveStoreWidgetToPoint(self.widget.widget_id, pos.x, pos.y)
end

function WidgetScaleButton:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self[1] = FrameContainer:new{
        width = self.width, height = self.height, padding = 0, bordersize = 0,
        radius = math.floor(self.height / 2),
        background = self.delta < 0 and PALETTE.surface_variant or PALETTE.primary_container,
        CenterContainer:new{ dimen = self.dimen, TextWidget:new{
            text = self.title, face = Font:getFace("cfont", scale(15)),
            fgcolor = PALETTE.on_surface, bold = true, padding = 0,
        } },
    }
    self.ges_events = { TapAdjustStoreWidget = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function WidgetScaleButton:paintTo(bb, x, y)
    local range = self.ges_events.TapAdjustStoreWidget[1].range
    range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    return InputContainer.paintTo(self, bb, x, y)
end

function WidgetScaleButton:onTapAdjustStoreWidget()
    return self.home and self.home:adjustStoreWidgetScale(self.widget_id, self.delta) or false
end

function HomeEditButton:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self[1] = FrameContainer:new{
        width = self.width, height = self.height, padding = scale(4), bordersize = 0,
        radius = math.floor(self.height / 2), background = PALETTE.primary_container,
        CenterContainer:new{ dimen = self.dimen, TextWidget:new{
            text = self.title or _("Done"), face = Font:getFace("smallinfofont", scale(12)),
            fgcolor = PALETTE.on_primary_container, bold = true, padding = 0,
        } },
    }
    self.ges_events = { TapToggleHomeEdit = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function HomeEditButton:paintTo(bb, x, y)
    local range = self.ges_events.TapToggleHomeEdit[1].range
    range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    return InputContainer.paintTo(self, bb, x, y)
end

function HomeEditButton:onTapToggleHomeEdit()
    if self.home then
        if self.home.edit_mode then self.home:finishLayoutEdit()
        else self.home:beginLayoutEdit() end
    end
    return true
end

function SearchBar:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local query_text = self.query ~= "" and (_("Search: ") .. self.query) or _("Search apps")
    local label_size = Theme.adjustText(self.appdock, math.max(scale(9), math.min(scale(14), math.floor(self.height * .42))), scale(9))
    local label = Theme.fitLabel("⌕  " .. query_text, self.width, label_size, scale(20))
    self[1] = FrameContainer:new{
        width = self.width, height = self.height, padding = 0, bordersize = 0,
        radius = math.floor(self.height * 0.36), background = PALETTE.surface_variant,
        CenterContainer:new{
            dimen = self.dimen,
            TextWidget:new{ text = label, face = Font:getFace("smallinfofont", label_size), fgcolor = PALETTE.on_surface_variant, max_width = self.width - scale(20), padding = 0 },
        },
    }
    self.ges_events = { TapSearchApps = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function SearchBar:paintTo(bb, x, y)
    local range = self.ges_events.TapSearchApps[1].range
    range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    return InputContainer.paintTo(self, bb, x, y)
end

function SearchBar:onTapSearchApps()
    self.home:showAppSearch()
    return true
end

function SearchGlyph:init()
    self.dimen = Geom:new{ w = self.size, h = self.size }
end

function SearchGlyph:paintTo(bb, x, y)
    local size = self.size
    local ink = self.ink or PALETTE.on_duckduckgo
    local thickness = math.max(1, math.floor(size * .15))
    local radius = size * .30
    local center_x, center_y = x + size * .38, y + size * .38
    local steps = math.max(16, math.floor(size * 4))
    for step = 0, steps - 1 do
        local angle = math.pi * 2 * step / steps
        bb:paintRect(
            math.floor(center_x + math.cos(angle) * radius),
            math.floor(center_y + math.sin(angle) * radius),
            thickness, thickness, ink)
    end
    local handle_x, handle_y = center_x + radius * .70, center_y + radius * .70
    local handle_steps = math.max(3, math.floor(size * .34))
    for step = 0, handle_steps do
        bb:paintRect(math.floor(handle_x + step * .72), math.floor(handle_y + step * .72), thickness, thickness, ink)
    end
end

function DuckDuckGoBar:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local padding = math.max(scale(7), math.floor(self.height * .16))
    local badge_size = math.max(scale(24), self.height - 2 * padding)
    local text_x = padding + badge_size + scale(12)
    local trailing_size = scale(20)
    local text_width = math.max(scale(20), self.width - text_x - padding - trailing_size - scale(14))
    local title_size = Theme.adjustText(self.appdock, math.max(scale(12), math.min(scale(17), math.floor(self.height * .34))), scale(10))
    local query = type(self.query) == "string" and self.query or ""
    local prompt = TextWidget:new{
        text = Theme.fitLabel(query ~= "" and query or _("Search with DuckDuckGo"), text_width, title_size, 0),
        face = Font:getFace("smallinfofont", title_size),
        fgcolor = query ~= "" and PALETTE.on_surface or PALETTE.on_surface_variant,
        max_width = text_width,
        padding = 0,
    }
    local glyph_size = math.floor(badge_size * .62)
    local badge = FrameContainer:new{
        width = badge_size, height = badge_size, padding = 0, bordersize = 0,
        radius = math.floor(badge_size / 2),
        background = PALETTE.duckduckgo,
        Layout.FixedStack:new{
            width = badge_size, height = badge_size,
            entries = {
                {
                    widget = SearchGlyph:new{ size = glyph_size, ink = PALETTE.on_duckduckgo },
                    x = math.floor((badge_size - glyph_size) / 2),
                    y = math.floor((badge_size - glyph_size) / 2),
                },
            },
        },
    }
    local trailing = SearchGlyph:new{ size = trailing_size, ink = PALETTE.on_surface_variant }
    local prompt_y = math.floor((self.height - prompt:getSize().h) / 2)
    local trailing_y = math.floor((self.height - trailing_size) / 2)
    self[1] = FrameContainer:new{
        width = self.width,
        height = self.height,
        padding = 0,
        bordersize = scale(1),
        color = PALETTE.outline,
        radius = math.floor(self.height / 2),
        background = PALETTE.surface,
        Layout.FixedStack:new{
            width = self.width,
            height = self.height,
            entries = {
                { widget = badge, x = padding, y = math.floor((self.height - badge_size) / 2) },
                { widget = prompt, x = text_x, y = prompt_y },
                { widget = trailing, x = self.width - padding - trailing_size, y = trailing_y },
            },
        },
    }
    self.ges_events = {
        TapDuckDuckGoSearch = { GestureRange:new{ ges = "tap", range = self.dimen } },
    }
end

function DuckDuckGoBar:paintTo(bb, x, y)
    local range = self.ges_events.TapDuckDuckGoSearch[1].range
    range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    return InputContainer.paintTo(self, bb, x, y)
end

function DuckDuckGoBar:onTapDuckDuckGoSearch()
    self.home:showWebSearch()
    return true
end

function AppTile:init()
    self.label_height = self.label_height or scale(28)
    local label_width = math.max(self.tile_size, tonumber(self.label_width) or self.tile_size)
    self.dimen = Geom:new{
        w = label_width,
        h = self.tile_size + (self.hide_label and 0 or scale(6) + self.label_height),
    }

    local icon_size = math.floor(self.tile_size * 0.52)
    local is_plugin = type(self.app.id) == "string" and self.app.id:match("^plugin:") ~= nil
    local builtin_logos = {
        ["system:library"] = "file_manager",
        ["system:menu"] = "settings",
        ["system:history"] = "analog_clock",
        ["system:open_apps"] = "app_store",
        ["system:manage"] = "app_store",
    }
    local logo_kind = self.app.logo or builtin_logos[self.app.id]
    local icon = self.symbol == "app_drawer" and AppDrawerGlyph:new{
        size = icon_size, ink = self.foreground or PALETTE.on_primary_container,
    } or nil
    if not icon then icon = is_plugin and self.app.custom_logo_path and Wallpaper.buildPath(self.app.custom_logo_path, icon_size, icon_size, true) or nil end
    if not icon and logo_kind then icon = DAppLogo:new{
        kind = logo_kind,
        size = icon_size,
        ink = self.foreground or PALETTE.on_primary_container,
    } end
    if not icon then icon = TextWidget:new{
        text = self.symbol or iconFor(self.app),
        face = Font:getFace("cfont", math.floor(self.tile_size * 0.40)),
        fgcolor = self.foreground or PALETTE.on_primary_container,
        bold = true,
    } end
    local requested_shape = Theme.getAppLogoShape(self.appdock) or self.shape
    local frame_style = Theme.getButtonFrameStyle(self.appdock, self.tile_size, math.floor(self.tile_size * 0.32))
    local has_black_border = self.appdock.settings.beta and self.appdock.settings.beta.black_borders
    local selected_for_edit = self.home and self.home.edit_mode and self.home.selected_app_id == self.app.id
    local tile = FrameContainer:new{
        width = self.tile_size,
        height = self.tile_size,
        padding = 0,
        bordersize = has_black_border and scale(1) or (selected_for_edit and scale(2) or (frame_style.bordersize or 0)),
        color = has_black_border and Blitbuffer.COLOR_BLACK or (selected_for_edit and PALETTE.primary or frame_style.color),
        radius = requested_shape == "circle" and math.floor(self.tile_size / 2) or (frame_style.radius or math.floor(self.tile_size * 0.32)),
        background = self.background or PALETTE.primary_container,
        CenterContainer:new{
            dimen = Geom:new{ w = self.tile_size, h = self.tile_size },
            icon,
        },
    }
    local label_size = math.max(scale(8), math.min(scale(13), self.label_height - scale(6)))
    if self.home and self.home.appdock and self.home.appdock.isExpressiveUiEnabled and self.home.appdock:isExpressiveUiEnabled() then
        label_size = Theme.adjustText(self.appdock, label_size, scale(8))
    end
    local label_text = Theme.fitLabel(self.app.title or "", label_width, label_size, 0)
    self.layout = { label = label_text, label_size = label_size }
    local label = TextWidget:new{
        text = label_text,
        face = Font:getFace("smallinfofont", label_size),
        fgcolor = PALETTE.on_surface,
        max_width = label_width,
        padding = 0,
    }

    if self.hide_label then
        self[1] = CenterContainer:new{ dimen = self.dimen, tile }
    else
        self[1] = VerticalGroup:new{
            CenterContainer:new{
                dimen = Geom:new{ w = label_width, h = self.tile_size },
                tile,
            },
            VerticalSpan:new{ width = scale(6) },
            CenterContainer:new{
                dimen = Geom:new{ w = label_width, h = self.label_height },
                label,
            },
        }
    end
    self.ges_events = {
        TapSelectAppTile = {
            GestureRange:new{ ges = "tap", range = self.dimen },
        },
        HoldSelectAppTile = {
            GestureRange:new{ ges = "hold", range = self.dimen },
        },
    }
    if self.home and self.home.edit_mode and not self.is_dock_item then
        self.ges_events.PanMoveAppTile = { GestureRange:new{ ges = "pan", range = self.dimen } }
        self.ges_events.PanReleaseMoveAppTile = { GestureRange:new{ ges = "pan_release", range = self.dimen } }
    end
end

function AppTile:paintTo(bb, x, y)
    local drag_pos = self.home and self.home.edit_mode and self.home.drag_app_id == self.app.id and self.home.drag_pos
    if drag_pos then
        x = math.floor(drag_pos.x - self.dimen.w / 2)
        y = math.floor(drag_pos.y - self.dimen.h / 2)
    end
    local range = self.ges_events.TapSelectAppTile[1].range
    range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    local hold_range = self.ges_events.HoldSelectAppTile[1].range
    hold_range.x, hold_range.y, hold_range.w, hold_range.h = x, y, self.dimen.w, self.dimen.h
    if self.ges_events.PanMoveAppTile then
        for _, name in ipairs({ "PanMoveAppTile", "PanReleaseMoveAppTile" }) do
            local pan_range = self.ges_events[name][1].range
            pan_range.x, pan_range.y, pan_range.w, pan_range.h = x, y, self.dimen.w, self.dimen.h
        end
    end
    return InputContainer.paintTo(self, bb, x, y)
end

function AppTile:onTapSelectAppTile()
    if self.home and self.home.edit_mode then
        if self.is_dock_item then return true end
        self.home.selected_app_id = self.app.id
        self.home:build()
        UIManager:setDirty(self.home, "ui")
        return true
    end
    UIManager:setDirty(self, "fast")
    self.appdock:launchApp(self.app, self.home)
    return true
end

function AppTile:onHoldSelectAppTile()
    if self.is_dock_item then return true end
    if self.home and self.home.edit_mode then
        self.appdock:showManager(self.home, self.app)
    else
        self.home:beginLayoutEdit(self.app.id)
    end
    return true
end

function AppTile:onPanMoveAppTile(_, gesture_event)
    if not self.home or not self.home.edit_mode or not gesture_event or not gesture_event.pos then return false end
    self.home.drag_app_id = self.app.id
    self.home.drag_pos = gesture_event.pos
    UIManager:setDirty(self.home, "fast")
    return true
end

function AppTile:onPanReleaseMoveAppTile(_, gesture_event)
    if not self.home or not self.home.edit_mode then return false end
    local pos = gesture_event and gesture_event.pos or self.home.drag_pos
    local moved = self.home:moveAppToPoint(self.app.id, pos)
    self.home.drag_app_id, self.home.drag_pos = nil, nil
    UIManager:setDirty(self.home, "ui")
    return moved or true
end

function AppDockHomeScreen:init()
    applyTheme(self.appdock)
    self.dimen = Screen:getSize()
    self.page = self.page or 1
    self.appdock:seedDefaults()

    if not self.appdock:isSimpleModeEnabled("homescreen") then
        self.ges_events = {
            SwipeHomePage = {
                GestureRange:new{ ges = "swipe", range = function() return self:_appGridSwipeRange() end },
            },
            RevealRecentApps = {
                GestureRange:new{ ges = "swipe", direction = "north", range = function() return bottomSwipeRange(self.dimen) end },
            },
        }
    end

    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
        local page_up, page_down = DeviceControls.pageKeyGroups()
        if page_up then self.key_events.BrightnessUp = { { page_up } } end
        if page_down then self.key_events.BrightnessDown = { { page_down } } end
    end
    self._page_hold_shown = { up = false, down = false }
    self:build()
    self:_scheduleStoreWidgetRefresh()
end

function AppDockHomeScreen:_showBrightnessIndicator(state)
    self._brightness_notice = state
    self._brightness_notice_generation = (self._brightness_notice_generation or 0) + 1
    local generation = self._brightness_notice_generation
    -- Do not replace the homescreen tree while KOReader is still dispatching
    -- the physical-key event. On some readers that races the framebuffer
    -- repaint and leaves its temporary framebuffer object unset.
    UIManager:nextTick(function()
        if self._brightness_notice_generation ~= generation then return end
        local ok = pcall(function()
            self:build()
            UIManager:setDirty(self, "ui")
        end)
        if not ok then
            self._brightness_notice = nil
        end
    end)
    UIManager:scheduleIn(1.35, function()
        if self._brightness_notice_generation == generation then
            self._brightness_notice = nil
            UIManager:nextTick(function()
                local ok = pcall(function()
                    self:build()
                    UIManager:setDirty(self, "ui")
                end)
                if not ok then self._brightness_notice = nil end
            end)
        end
    end)
end
function AppDockHomeScreen:_pageKey(direction)
    self._page_hold_shown = self._page_hold_shown or { up = false, down = false }
    -- A fresh key-down starts a new press/hold gesture. The repeat handler
    -- below turns a real hardware hold into the power/screensaver action.
    self._page_hold_shown[direction] = false
    local delta = direction == "up" and 10 or -10
    local state = DeviceControls.setBrightness(delta)
    if state then self:_showBrightnessIndicator(state) end
    return true
end
function AppDockHomeScreen:_pageKeyRepeat(direction)
    self._page_hold_shown = self._page_hold_shown or { up = false, down = false }
    if self._page_hold_shown[direction] then return true end
    self._page_hold_shown[direction] = true
    if direction == "up" then
        DeviceControls.showPowerMenu()
    else
        DeviceControls.showScreensaver()
    end
    return true
end
function AppDockHomeScreen:onKeyRepeat(key)
    local page_up, page_down = DeviceControls.pageKeyGroups()
    if page_up and key and key.match and key:match({ page_up }) then return self:_pageKeyRepeat("up") end
    if page_down and key and key.match and key:match({ page_down }) then return self:_pageKeyRepeat("down") end
    return InputContainer.onKeyRepeat(self, key)
end
function AppDockHomeScreen:onBrightnessUp()
    return self:_pageKey("up")
end
function AppDockHomeScreen:onBrightnessDown()
    return self:_pageKey("down")
end
function AppDockHomeScreen:_appendBrightnessIndicator(dashboard)
    if self._brightness_notice then
        local indicator = DeviceControls.buildIndicator(self._brightness_notice)
        if indicator then table.insert(dashboard, indicator) end
    end
end

function AppDockHomeScreen:_scheduleStoreWidgetRefresh()
    if self._widget_tick then UIManager:unschedule(self._widget_tick) end
    if self.appdock:isSimpleModeEnabled("homescreen") then return end
    local has_visible_widget = false
    for _, widget in ipairs(self.appdock:getStoreWidgets()) do
        if self.appdock:isStoreWidgetEnabled(widget.widget_id) then has_visible_widget = true; break end
    end
    if not has_visible_widget then return end
    self._widget_tick = function()
        self:build()
        UIManager:setDirty(self, "ui")
        UIManager:scheduleIn(180, self._widget_tick)
    end
    UIManager:scheduleIn(180, self._widget_tick)
end

function AppDockHomeScreen:showAppSearch()
    local keyboard
    keyboard = AppDockKeyboard:new{
        title = _("Search AppDock apps"),
        placeholder = _("App name"),
        value = self.search_query or "",
        on_change = function(value)
            self.search_query = value or ""
            self:build()
            UIManager:setDirty(self, "ui")
        end,
        on_cancel = function() UIManager:close(keyboard) end,
        on_submit = function(value)
            self.search_query = value or ""
            self:build()
            UIManager:setDirty(self, "ui")
            -- Close after the touch dispatch has returned, so the keyboard
            -- is no longer destroyed from inside its own Done callback.
            UIManager:nextTick(function()
                if keyboard then UIManager:close(keyboard) end
            end)
        end,
    }
    UIManager:show(keyboard)
end

-- The DuckDuckGo bar hands the typed query to AppDock's JavaScript-free Web
-- Browser DApp, which already renders html.duckduckgo.com results.
function AppDockHomeScreen:showWebSearch()
    local keyboard
    keyboard = AppDockKeyboard:new{
        title = _("DuckDuckGo"),
        placeholder = _("Search the web privately"),
        value = self.web_query or "",
        on_cancel = function() UIManager:close(keyboard) end,
        on_submit = function(value)
            local query = (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
            UIManager:nextTick(function()
                if keyboard then UIManager:close(keyboard) end
                self:runWebSearch(query)
            end)
        end,
    }
    UIManager:show(keyboard)
end

function AppDockHomeScreen:runWebSearch(query)
    query = type(query) == "string" and query:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if query == "" then return false end
    self.web_query = query
    local manager = self.appdock and self.appdock:getDAppManager()
    if not manager then return false end
    if type(manager.openWebSearch) == "function" then
        return manager:openWebSearch(query, self) and true or false
    end
    if type(manager.activate) == "function" then
        manager:activate("web_browser", self)
        return true
    end
    return false
end

function AppDockHomeScreen:_pageInfo(apps, per_page)
    per_page = math.max(1, tonumber(per_page) or 6)
    local pages = math.max(1, math.ceil(#apps / per_page))
    if self.page > pages then self.page = pages end
    local first = (self.page - 1) * per_page + 1
    local visible = {}
    for index = first, math.min(first + per_page - 1, #apps) do
        table.insert(visible, apps[index])
    end
    return visible, pages
end

function AppDockHomeScreen:_appGridSwipeRange()
    local layout = self.normal_layout or {}
    local top = tonumber(layout.grid_y) or scale(180)
    local grid_height = tonumber(layout.grid_height) or scale(260)
    return Geom:new{ x = 0, y = top, w = self.dimen.w, h = grid_height }
end

function AppDockHomeScreen:_pageCount()
    local layout = self.normal_layout or self.simple_layout or {}
    return math.max(1, tonumber(layout.page_count) or 1)
end

function AppDockHomeScreen:_showPage(page)
    local page_count = self:_pageCount()
    page = math.max(1, math.min(page_count, tonumber(page) or self.page))
    if page == self.page or self._page_transition then return false end
    self.page = page
    self:build()
    self._page_transition = false
    UIManager:setDirty(self, "ui")
    return true
end

function AppDockHomeScreen:beginLayoutEdit(selected_app_id)
    self.edit_mode = true
    self.selected_app_id = selected_app_id
    self.drag_app_id, self.drag_pos = nil, nil
    self:build()
    UIManager:setDirty(self, "ui")
    return true
end

function AppDockHomeScreen:finishLayoutEdit()
    self.edit_mode = false
    self.drag_app_id, self.drag_pos, self.selected_app_id = nil, nil, nil
    self:build()
    UIManager:setDirty(self, "ui")
    return true
end

function AppDockHomeScreen:moveAppToPoint(app_id, pos)
    local layout = self.normal_layout or self.simple_layout
    if not self.edit_mode or not layout or not pos then return false end
    local position, total = self.appdock:getPinnedPosition(app_id)
    if not position then return false end
    local columns = math.max(1, tonumber(layout.grid_columns or layout.columns) or 3)
    local rows = math.max(1, tonumber(layout.grid_rows or layout.rows) or 3)
    local page_size = tonumber(layout.page_size) or columns * rows
    local cell_width = tonumber(layout.cell_width) or (layout.grid_width or self.dimen.w) / columns
    local grid_x, grid_y = tonumber(layout.grid_x) or 0, tonumber(layout.grid_y) or 0
    local row_pitch = tonumber(layout.row_pitch) or math.max(1, (layout.grid_height or self.dimen.h) / rows)
    local col = math.max(0, math.min(columns - 1, math.floor((pos.x - grid_x) / math.max(1, cell_width))))
    local row = math.max(0, math.min(rows - 1, math.floor((pos.y - grid_y) / math.max(1, row_pitch))))
    local target = math.max(1, math.min(total, (self.page - 1) * page_size + row * columns + col + 1))
    local moved = self.appdock:movePinned(app_id, target - position)
    if moved then self:build(); UIManager:setDirty(self, "ui") end
    return moved
end

function AppDockHomeScreen:adjustStoreWidgetScale(widget_id, delta)
    if not self.appdock or type(self.appdock.adjustStoreWidgetScale) ~= "function" then return false end
    local result = self.appdock:adjustStoreWidgetScale(widget_id, delta)
    if result then self:build(); UIManager:setDirty(self, "ui") end
    return result
end

function AppDockHomeScreen:moveStoreWidgetToPoint(widget_id, x, y)
    if y == nil then y, x = x, nil end
    local positions = self.normal_layout and self.normal_layout.widget_positions or {}
    local target_id, nearest = nil, nil
    for _, item in pairs(positions) do
        local center_x = item.x and item.x + (item.width or 0) / 2
        local center_y = item.y + item.height / 2
        local distance = x and center_x and math.sqrt((x - center_x) ^ 2 + (y - center_y) ^ 2)
            or math.abs(y - center_y)
        if not nearest or distance < nearest then target_id, nearest = item.widget_id, distance end
    end
    if not target_id or target_id == widget_id then return false end
    local current_position = self.appdock:getStoreWidgetPosition(widget_id)
    local target_position = self.appdock:getStoreWidgetPosition(target_id)
    if not current_position or not target_position then return false end
    local moved = self.appdock:moveStoreWidget(widget_id, target_position - current_position)
    if moved then self:build(); UIManager:setDirty(self, "ui") end
    return moved
end

function AppDockHomeScreen:onSwipeHomePage(_, gesture_event)
    if self.appdock:isSimpleModeEnabled("homescreen") or self._page_transition or not gesture_event then return false end
    if gesture_event.direction == "west" then
        return self:_showPage(self.page + 1)
    elseif gesture_event.direction == "east" then
        return self:_showPage(self.page - 1)
    end
    return false
end

function AppDockHomeScreen:onRevealRecentApps()
    if self.appdock:isSimpleModeEnabled("homescreen") then return false end
    local manager = self.appdock and self.appdock:getDAppManager()
    if manager and type(manager.showRecentDrawer) == "function" then
        manager:showRecentDrawer(self, self)
        return true
    end
    return false
end

function AppDockHomeScreen:_navControl(symbol, x, y, callback)
    local size = scale(30)
    return AppTile:new{
        appdock = self.appdock,
        home = self,
        app = { id = "system:page_control", title = "" },
        symbol = symbol,
        tile_size = size,
        label_height = 0,
        background = PALETTE.surface_variant,
        foreground = PALETTE.on_surface_variant,
        onTapSelectAppTile = function(tile)
            callback(tile)
            return true
        end,
        onHoldSelectAppTile = function()
            return true
        end,
        overlap_offset = { x, y },
    }
end

function AppDockHomeScreen:showQuickSettings()
    local QuickSettings = require("appdock_quicksettings")
    QuickSettings:show{
        appdock = self.appdock,
        home = self,
    }
end

function AppDockHomeScreen:_addTopSystemLine(dashboard, width, margin)
    local left = TextWidget:new{
        text = self.appdock.settings.widgets.clock and os.date("%H:%M") or "",
        face = Font:getFace("smallinfofont", scale(14)),
        fgcolor = PALETTE.on_surface,
        overlap_offset = { margin, scale(10) },
    }
    table.insert(dashboard, left)

    local right_text = self.appdock.settings.widgets.status and safeBatteryText() or nil
    if right_text then right_text = right_text:match("(%d+%%)") or right_text end
    local quick_size = scale(28)
    local quick_x = width - margin - quick_size
    if right_text then
        local right = TextWidget:new{
            text = right_text,
            face = Font:getFace("smallinfofont", scale(13)),
            fgcolor = PALETTE.on_surface,
        }
        quick_x = width - margin - right:getSize().w - scale(10) - quick_size
        right.overlap_offset = { width - margin - right:getSize().w, scale(11) }
        table.insert(dashboard, right)
    end
    local expressive = type(self.appdock.isExpressiveUiEnabled) == "function" and self.appdock:isExpressiveUiEnabled()
    table.insert(dashboard, AppTile:new{
        appdock = self.appdock,
        home = self,
        app = { id = "system:quick_settings", title = "" },
        symbol = "⌄",
        tile_size = quick_size,
        label_height = 0,
        background = expressive and PALETTE.primary_container or PALETTE.surface_variant,
        foreground = expressive and PALETTE.on_primary_container or PALETTE.on_surface_variant,
        onTapSelectAppTile = function()
            self:showQuickSettings()
            return true
        end,
        onHoldSelectAppTile = function()
            return true
        end,
        overlap_offset = { quick_x, scale(5) },
    })
end

local function addEditGridCells(container, columns, rows, x, y, cell_width, row_pitch, cell_height)
    for row = 0, rows - 1 do
        for col = 0, columns - 1 do
            local cell_width_inner = math.max(scale(12), cell_width - scale(5))
            local cell_height_inner = math.max(scale(12), cell_height - scale(4))
            table.insert(container, FrameContainer:new{
                width = cell_width_inner,
                height = cell_height_inner,
                padding = 0,
                bordersize = scale(1),
                color = PALETTE.outline,
                radius = scale(8),
                background = PALETTE.surface,
                emptySizedWidget(cell_width_inner, cell_height_inner),
                overlap_offset = { x + col * cell_width + scale(2), y + row * row_pitch },
            })
        end
    end
end

function AppDockHomeScreen:_buildSimpleMode(width, height)
    local margin = scale(16)
    local column_gap, row_gap, label_height = scale(12), scale(14), scale(22)
    local apps = self.appdock:getPinnedApps()
    local visible_apps, page_count = self:_pageInfo(apps, 12)
    local grid_width = width - 2 * margin
    local by_width = math.floor((grid_width - 3 * column_gap) / 4)
    local by_height = math.floor((height - 2 * margin - 2 * row_gap - 3 * label_height) / 3)
    local tile_size = math.max(scale(40), math.min(by_width, by_height, scale(92)))
    local grid_height = 3 * (tile_size + label_height) + 2 * row_gap
    local grid_y = math.max(margin, math.floor((height - grid_height) / 2))
    local grid_x = math.floor((width - (4 * tile_size + 3 * column_gap)) / 2)
    local dashboard = OverlapGroup:new{
        dimen = Geom:new{ w = width, h = height },
        allow_mirroring = false,
        FrameContainer:new{
            width = width, height = height, padding = 0, bordersize = 0,
            background = PALETTE.background,
            emptySizedWidget(width, height),
        },
    }
    local cell_width = tile_size + column_gap
    local row_pitch = tile_size + label_height + row_gap
    if self.edit_mode then
        addEditGridCells(dashboard, 4, 3, grid_x, grid_y, cell_width, row_pitch, tile_size + label_height)
    end
    for index, app in ipairs(visible_apps) do
        local col = (index - 1) % 4
        local row = math.floor((index - 1) / 4)
        local tone = toneFor(app, index)
        table.insert(dashboard, AppTile:new{
            appdock = self.appdock,
            home = self,
            app = app,
            tile_size = tile_size,
            label_height = label_height,
            shape = self.appdock.settings.layout.logo_shape,
            background = tone.background,
            foreground = tone.foreground,
            overlap_offset = {
                grid_x + col * (tile_size + column_gap),
                grid_y + row * (tile_size + label_height + row_gap),
            },
        })
    end
    if page_count > 1 then
        local nav_y = height - scale(38)
        local nav_center = math.floor(width / 2)
        if self.page > 1 then table.insert(dashboard, self:_navControl("‹", nav_center - scale(64), nav_y, function() self:_showPage(self.page - 1) end)) end
        if self.page < page_count then table.insert(dashboard, self:_navControl("›", nav_center + scale(34), nav_y, function() self:_showPage(self.page + 1) end)) end
        table.insert(dashboard, TextWidget:new{
            text = string.format("%d / %d", self.page, page_count),
            face = Font:getFace("smallinfofont", scale(12)), fgcolor = PALETTE.on_surface_variant,
            overlap_offset = { nav_center - scale(12), nav_y + scale(8) },
        })
    end
    self:_addTopSystemLine(dashboard, width, margin)
    if grid_y > scale(58) then
        table.insert(dashboard, TextWidget:new{
            text = self.edit_mode and _("Drag apps to move · tap Done to finish") or appSectionLabel(#apps),
            face = Font:getFace("smallinfofont", Theme.adjustText(self.appdock, scale(14), scale(10))),
            fgcolor = PALETTE.on_surface_variant,
            bold = true,
            padding = 0,
            max_width = width - 2 * margin - scale(92),
            overlap_offset = { margin, margin + scale(38) },
        })
    end
        table.insert(dashboard, HomeEditButton:new{
            home = self, title = self.edit_mode and _("Done") or _("Edit"), width = scale(78), height = scale(32),
            overlap_offset = { width - margin - scale(78), margin + scale(38) },
        })
    self.simple_layout = {
        columns = 4, rows = 3, grid_columns = 4, grid_rows = 3,
        tile_size = tile_size, app_count = #visible_apps, page_count = page_count,
        page_size = 12, grid_x = grid_x, grid_y = grid_y,
        grid_width = 4 * tile_size + 3 * column_gap,
        grid_height = grid_height, cell_width = cell_width, row_pitch = row_pitch,
        app_section = true,
    }
    self:_appendBrightnessIndicator(dashboard)
    self[1] = dashboard
end

function AppDockHomeScreen:build()
    local width, height = self.dimen.w, self.dimen.h
    if self.appdock:isSimpleModeEnabled("homescreen") then
        self:_buildSimpleMode(width, height)
        return
    end
    local expressive = type(self.appdock.isExpressiveUiEnabled) == "function" and self.appdock:isExpressiveUiEnabled()
    local margin = scale(22)
    local top_line_height = scale(30)
    local search_y = top_line_height + scale(22)
    local ddg_search_height = scale(54)
    local layout = self.appdock.settings.layout or {}
    local label_height = scale(20)
    local label_gap = scale(3)
    local apps = self.appdock:getPinnedApps()
    local search_query = (self.search_query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if layout.search_enabled and search_query ~= "" then
        local filtered = {}
        for _, app in ipairs(apps) do
            if (app.title or ""):lower():find(search_query, 1, true) then table.insert(filtered, app) end
        end
        apps = filtered
    end
    local page_size = 9
    local visible_apps, page_count = self:_pageInfo(apps, page_size)

    local dashboard = OverlapGroup:new{
        dimen = Geom:new{ w = width, h = height },
        allow_mirroring = false,
        FrameContainer:new{
            width = width,
            height = height,
            padding = 0,
            bordersize = 0,
            background = PALETTE.background,
            emptySizedWidget(width, height),
        },
    }

    local wallpaper = Wallpaper.build(self.appdock, width, height)
    if wallpaper then
        wallpaper.overlap_offset = { 0, 0 }
        table.insert(dashboard, wallpaper)
    end

    self:_addTopSystemLine(dashboard, width, margin)
    local block_y = search_y
    -- The DuckDuckGo bar belongs to the first homescreen page only: swiping to
    -- the next app page keeps the grid uncluttered.
    if self.page == 1 and layout.ddg_search ~= false then
        local bar_height = ddg_search_height
        table.insert(dashboard, DuckDuckGoBar:new{
            appdock = self.appdock, home = self, width = width - 2 * margin, height = bar_height,
            query = self.web_query or "", overlap_offset = { margin, block_y },
        })
        block_y = block_y + bar_height + scale(8)
    end
    local card_y = block_y
    if layout.search_enabled then
        table.insert(dashboard, SearchBar:new{
            appdock = self.appdock, home = self, width = width - 2 * margin, height = scale(38),
            query = self.search_query or "", overlap_offset = { margin, block_y },
        })
        card_y = block_y + scale(38) + scale(12)
    end
    local show_status_card = not self.edit_mode and self.appdock.settings.widgets.status == true
    local show_reading_card = not self.edit_mode and self.appdock.settings.widgets.reading_hint == true
    local visible_widgets = {}
    for _, widget in ipairs(self.appdock:getStoreWidgets()) do
        if self.appdock:isStoreWidgetEnabled(widget.widget_id) then table.insert(visible_widgets, widget) end
    end

    local recent_apps = {}
    if type(self.appdock.getRecentApps) == "function" then
        local ok, loaded_apps = pcall(self.appdock.getRecentApps, self.appdock, 4)
        if ok and type(loaded_apps) == "table" then recent_apps = loaded_apps end
    end
    local actual_recent_count = #recent_apps
    local shortcut_apps, seen_shortcuts = {}, {}
    for _, app in ipairs(recent_apps) do
        if #shortcut_apps >= 4 then break end
        if type(app) == "table" and type(app.id) == "string" and not seen_shortcuts[app.id] then
            shortcut_apps[#shortcut_apps + 1] = app
            seen_shortcuts[app.id] = true
        end
    end
    if #shortcut_apps < 4 then
        for _, app in ipairs(self.appdock:getPinnedApps()) do
            if #shortcut_apps >= 4 then break end
            if type(app) == "table" and type(app.id) == "string" and app.id ~= "system:manage" and app.id ~= "system:open_apps" and not seen_shortcuts[app.id] then
                shortcut_apps[#shortcut_apps + 1] = app
                seen_shortcuts[app.id] = true
            end
        end
    end

    local dock_apps = {}
    for _, app in ipairs(shortcut_apps) do dock_apps[#dock_apps + 1] = app end
    local all_apps_app
    if type(self.appdock.getSystemApps) == "function" then
        local ok, system_apps = pcall(self.appdock.getSystemApps, self.appdock)
        if ok and type(system_apps) == "table" then
            for _, app in ipairs(system_apps) do
                if app.id == "system:manage" then all_apps_app = app; break end
            end
        end
    end
    if not all_apps_app then
        all_apps_app = {
            id = "system:manage", title = _("All apps"),
            callback = function(home) self.appdock:showManager(home) end,
        }
    end
    dock_apps[#dock_apps + 1] = all_apps_app

    local row_gap = scale(8)
    local tile_gap = scale(math.max(8, math.min(34, tonumber(layout.app_spacing) or 16)))
    local dock_gap = scale(10)
    local dock_padding = scale(10)
    local dock_inner_width = width - 2 * margin - 2 * dock_padding
    local dock_slot_width = math.floor((dock_inner_width - math.max(0, #dock_apps - 1) * dock_gap) / math.max(1, #dock_apps))
    local dock_tile_size = math.max(scale(42), math.min(scale(64), math.floor(dock_slot_width)))
    local dock_height = 2 * dock_padding + dock_tile_size
    local dock_y = height - margin - dock_height
    local info_card_height = scale(78)
    local widget_gap = scale(10)
    local widget_columns = #visible_widgets > 1 and 2 or 1
    local widget_cell_width = math.floor((width - 2 * margin - (widget_columns - 1) * widget_gap) / widget_columns)
    local widget_metrics = {}
    local widget_slots = {}
    local widget_scales = layout.widget_scales or {}
    local next_widget_row, next_widget_col = 0, 0
    for _, widget in ipairs(visible_widgets) do
        local factor = math.max(.75, math.min(1.5, tonumber(widget_scales[widget.widget_id]) or 1))
        local span = widget_columns == 2 and factor > 1 and 2 or 1
        if span == 2 and next_widget_col > 0 then
            next_widget_row, next_widget_col = next_widget_row + 1, 0
        end
        local slot_index = #widget_slots + 1
        widget_slots[slot_index] = { row = next_widget_row, col = next_widget_col, span = span }
        widget_metrics[widget.widget_id] = {
            factor = factor,
            width = math.floor((span == 2 and width - 2 * margin or widget_cell_width) * math.min(1, factor)),
            height = scale(112 * factor),
        }
        if span == 2 then
            next_widget_row, next_widget_col = next_widget_row + 1, 0
        else
            next_widget_col = next_widget_col + 1
            if next_widget_col >= widget_columns then next_widget_row, next_widget_col = next_widget_row + 1, 0 end
        end
    end
    local function measureWidgetRows()
        local row_count = 0
        local row_heights = {}
        for index, widget in ipairs(visible_widgets) do
            local row = widget_slots[index] and widget_slots[index].row or math.floor((index - 1) / widget_columns)
            row_count = math.max(row_count, row + 1)
            local metrics = widget_metrics[widget.widget_id] or { height = scale(112) }
            row_heights[row] = math.max(row_heights[row] or 0, metrics.height)
        end
        local total = 0
        for row = 0, row_count - 1 do
            total = total + (row_heights[row] or scale(112))
            if row < row_count - 1 then total = total + widget_gap end
        end
        return total, row_heights, row_count
    end
    local function measuredGridY()
        local has_cards = show_status_card or show_reading_card
        local widget_y = card_y + (has_cards and info_card_height or 0) + (has_cards and scale(10) or 0)
        local widget_space = measureWidgetRows()
        return widget_y + widget_space + scale(24), widget_y, widget_space
    end
    local function maxGridTileSize()
        local grid_y = measuredGridY()
        local page_nav_space = page_count > 1 and scale(34) or 0
        local bottom = dock_y - (#dock_apps > 0 and scale(8) or 0) - page_nav_space
        return math.floor((bottom - grid_y - 2 * row_gap - 3 * (label_gap + label_height)) / 3)
    end
    local widgets_hidden_for_fit = false
    while not self.edit_mode and maxGridTileSize() < scale(62) do
        if #visible_widgets > 0 then
            visible_widgets = {}
            widgets_hidden_for_fit = true
        elseif show_reading_card then
            show_reading_card = false
        elseif show_status_card then
            show_status_card = false
        else
            break
        end
    end

    if show_status_card then
        local status_body = safeBatteryText() or _("All systems ready")
        table.insert(dashboard, InfoCard:new{
            appdock = self.appdock,
            width = math.floor((width - 2 * margin - scale(10)) * 0.42),
            height = info_card_height,
            title = _("Device"),
            body = status_body,
            background = PALETTE.surface,
            foreground = PALETTE.on_surface,
            overlap_offset = { margin, card_y },
        })
    end

    if show_reading_card then
        local reading_x = show_status_card
            and margin + math.floor((width - 2 * margin - scale(10)) * 0.42) + scale(10)
            or margin
        local reading_width = show_status_card
            and width - margin - reading_x
            or width - 2 * margin
        table.insert(dashboard, InfoCard:new{
            appdock = self.appdock,
            width = reading_width,
            height = info_card_height,
            title = _("Continue reading"),
            body = currentBookText(self.appdock),
            background = PALETTE.surface_variant,
            foreground = PALETTE.on_surface,
            overlap_offset = { reading_x, card_y },
        })
    end

    local grid_y, widget_y, widget_space = measuredGridY()
    local _measured_widget_space, widget_row_heights, widget_row_count = measureWidgetRows()
    local widget_positions = {}
    local widget_row_offsets = {}
    local widget_cursor_y = widget_y
    for row = 0, widget_row_count - 1 do
        widget_row_offsets[row] = widget_cursor_y
        widget_cursor_y = widget_cursor_y + (widget_row_heights[row] or scale(112)) + widget_gap
    end
    for index, widget in ipairs(visible_widgets) do
        local metrics = widget_metrics[widget.widget_id] or { width = widget_cell_width, height = scale(112), factor = 1 }
        local slot = widget_slots[index] or { row = math.floor((index - 1) / widget_columns), col = (index - 1) % widget_columns, span = 1 }
        local slot_width = slot.span == 2 and width - 2 * margin or widget_cell_width
        local slot_x = margin + slot.col * (widget_cell_width + widget_gap)
        local widget_x = slot_x + math.floor((slot_width - metrics.width) / 2)
        local widget_y_pos = widget_row_offsets[slot.row] or widget_y
        widget_positions[widget.widget_id] = {
            widget_id = widget.widget_id, x = widget_x, y = widget_y_pos,
            width = metrics.width, height = metrics.height, index = index, row = slot.row, column = slot.col, span = slot.span,
        }
        table.insert(dashboard, StoreWidgetCard:new{
            widget = widget,
            appdock = self.appdock,
            home = self,
            edit_mode = self.edit_mode,
            widget_scale = metrics.factor,
            widget_position = index,
            width = metrics.width,
            height = metrics.height,
            background = PALETTE.surface,
            foreground = PALETTE.on_surface,
            overlap_offset = { widget_x, widget_y_pos },
        })
    end
    local page_nav_space = page_count > 1 and scale(34) or 0
    local grid_bottom = dock_y - (#dock_apps > 0 and scale(8) or 0) - page_nav_space
    local available_tile_size = math.floor((grid_bottom - grid_y - 2 * row_gap - 3 * (label_gap + label_height)) / 3)
    local preferred_tile_size = math.floor(math.min(width * 0.20, height * 0.13))
    local tile_size = math.max(scale(36), math.min(scale(110), preferred_tile_size, math.floor(width / 3) - tile_gap, available_tile_size))
    local grid_width = width
    local grid_x = 0
    local column_width = math.floor(grid_width / 3)
    local grid_rows = 3
    local grid_height = grid_rows * (tile_size + label_gap + label_height) + 2 * row_gap
    local app_grid = OverlapGroup:new{ dimen = Geom:new{ w = width, h = height }, allow_mirroring = false }
    if self.edit_mode then
        addEditGridCells(app_grid, 3, 3, grid_x, grid_y, column_width,
            tile_size + label_gap + label_height + row_gap, tile_size + label_gap + label_height)
    end
    table.insert(app_grid, TextWidget:new{
        text = self.edit_mode and _("Drag apps · Store widgets use − / +") or appSectionLabel(#apps),
        face = Font:getFace("smallinfofont", Theme.adjustText(self.appdock, scale(14), scale(10))),
        fgcolor = PALETTE.on_surface_variant,
        bold = true,
        max_width = width - 2 * margin - scale(92),
        padding = 0,
        overlap_offset = { margin, grid_y - scale(20) },
    })
    table.insert(app_grid, HomeEditButton:new{
        home = self, title = self.edit_mode and _("Done") or _("Edit"), width = scale(78), height = scale(30),
        overlap_offset = { width - margin - scale(78), grid_y - scale(32) },
    })
    for index, app in ipairs(visible_apps) do
        local col = (index - 1) % 3
        local row = math.floor((index - 1) / 3)
        local tone = toneFor(app, index)
        table.insert(app_grid, AppTile:new{
            appdock = self.appdock,
            home = self,
            app = app,
            tile_size = tile_size,
            label_height = label_height,
            label_width = column_width,
            shape = layout.logo_shape,
            background = tone.background,
            foreground = tone.foreground,
            overlap_offset = {
                grid_x + col * column_width,
                grid_y + row * (tile_size + label_gap + label_height + row_gap),
            },
        })
    end

    if page_count > 1 then
        local nav_y = grid_y + grid_height + scale(2)
        local nav_center = math.floor(width / 2)
        if self.page > 1 then
            table.insert(app_grid, self:_navControl("‹", nav_center - scale(64), nav_y, function()
                self:_showPage(self.page - 1)
            end))
        end
        if self.page < page_count then
            table.insert(app_grid, self:_navControl("›", nav_center + scale(34), nav_y, function()
                self:_showPage(self.page + 1)
            end))
        end
        local page_label = TextWidget:new{
            text = string.format("%d / %d", self.page, page_count),
            face = Font:getFace("smallinfofont", scale(13)),
            fgcolor = PALETTE.on_surface_variant,
            overlap_offset = { nav_center - scale(12), nav_y + scale(8) },
        }
        table.insert(app_grid, page_label)
    end

    table.insert(dashboard, app_grid)
    self._app_grid = app_grid
    local dock_title = actual_recent_count > 0 and actual_recent_count == #shortcut_apps and _("Recently used") or _("Quick access")
    if #dock_apps > 0 then
        table.insert(dashboard, FrameContainer:new{
            width = width - 2 * margin,
            height = dock_height,
            padding = 0,
            bordersize = scale(1),
            color = PALETTE.outline,
            radius = math.floor(dock_height / 2),
            background = PALETTE.surface,
            emptySizedWidget(width - 2 * margin, dock_height),
            overlap_offset = { margin, dock_y },
        })
        local tile_y = dock_y + dock_padding
        for index, app in ipairs(dock_apps) do
            local is_all_apps = app.id == "system:manage"
            if is_all_apps and #shortcut_apps > 0 then
                local separator_x = margin + dock_padding + (index - 1) * (dock_slot_width + dock_gap) - math.floor(dock_gap / 2)
                table.insert(dashboard, FrameContainer:new{
                    width = scale(1), height = scale(34), padding = 0, bordersize = 0,
                    background = PALETTE.outline, emptySizedWidget(scale(1), scale(34)),
                    overlap_offset = { separator_x, dock_y + math.floor((dock_height - scale(34)) / 2) },
                })
            end
            local tone = toneFor(app, index)
            local slot_x = margin + dock_padding + (index - 1) * (dock_slot_width + dock_gap)
            table.insert(dashboard, AppTile:new{
                appdock = self.appdock,
                home = self,
                app = app,
                tile_size = dock_tile_size,
                label_height = 0,
                label_width = dock_slot_width,
                hide_label = true,
                is_dock_item = true,
                symbol = is_all_apps and "app_drawer" or nil,
                shape = layout.logo_shape,
                background = tone.background,
                foreground = tone.foreground,
                overlap_offset = { slot_x, tile_y },
            })
        end
    end

    self.normal_layout = {
        expressive = expressive,
        has_header_surface = false,
        has_search_pill = self.page == 1 and layout.ddg_search ~= false,
        has_app_dock_surface = #dock_apps > 0,
        app_section = true,
        grid_columns = 3,
        grid_rows = grid_rows,
        grid_width = grid_width,
        grid_x = grid_x,
        cell_width = column_width,
        row_pitch = tile_size + label_gap + label_height + row_gap,
        widget_positions = widget_positions,
        tile_size = tile_size,
        grid_y = grid_y,
        grid_height = grid_height,
        page_size = 9,
        page_count = page_count,
        quick_access_count = #shortcut_apps,
        dock_item_count = #dock_apps,
        widget_columns = widget_columns,
        widget_grid_height = _measured_widget_space,
        glance_cards_hidden_for_edit = self.edit_mode and (self.appdock.settings.widgets.status == true or self.appdock.settings.widgets.reading_hint == true),
        recent_count = actual_recent_count,
        quick_access_title = dock_title,
        quick_access_y = dock_y,
        hidden_widgets_for_fit = widgets_hidden_for_fit,
    }
    self:_appendBrightnessIndicator(dashboard)
    self[1] = dashboard
end

function AppDockHomeScreen:onClose()
    if self._widget_tick then UIManager:unschedule(self._widget_tick); self._widget_tick = nil end
    UIManager:close(self)
    return true
end

function AppDrawerGlyph:init()
    self.dimen = Geom:new{ w = self.size, h = self.size }
    self.lens = SearchGlyph:new{ size = math.max(7, math.floor(self.size * .40)), ink = self.ink or PALETTE.on_primary_container }
end

function AppDrawerGlyph:paintTo(bb, x, y)
    local size = self.size
    local ink = self.ink or PALETTE.on_primary_container
    local cell = math.max(2, math.floor(size * .25))
    local gap = math.max(2, math.floor(size * .12))
    local origin = math.floor((size - 2 * cell - gap) / 2)
    for row = 0, 1 do
        for col = 0, 1 do
            bb:paintRect(x + origin + col * (cell + gap), y + origin + row * (cell + gap), cell, cell, ink)
        end
    end
    self.lens:paintTo(bb, x + size - self.lens.size, y + size - self.lens.size)
end

return AppDockHomeScreen
