--[[--
AppDock's Material-You-inspired E-Ink homescreen.
It adopts Android 16 / Material 3 Expressive principles that work without
motion: calm surfaces, coherent theme colors, pronounced shapes, glanceable
cards and a regular three-column icon grid.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputDialog = require("ui/widget/inputdialog")
local InputContainer = require("ui/widget/container/inputcontainer")
local DAppLogo = require("appdock_logo")
local Theme = require("appdock_theme")
local Wallpaper = require("appdock_wallpaper")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
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
    background = nil,
    foreground = nil,
    symbol = nil,
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

local StoreWidgetCard = WidgetContainer:extend{
    widget = nil,
    appdock = nil,
    width = nil,
    height = nil,
    background = nil,
    foreground = nil,
}

local SearchBar = InputContainer:extend{
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
    PALETTE.primary_container = palette.primary
    PALETTE.on_primary_container = palette.on_primary
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

local function greeting()
    local hour = tonumber(os.date("%H")) or 12
    if hour < 11 then return _("Good morning") end
    if hour < 18 then return _("Good afternoon") end
    return _("Good evening")
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
    local title_size = math.max(scale(8), math.min(scale(13), math.floor(self.height * .25)))
    local body_size = math.max(scale(9), math.min(scale(16), math.floor(self.height * .30)))
    local text_width = math.max(scale(12), self.width - 2 * scale(18))
    local title = Theme.fitLabel(self.title or "", text_width, title_size, 0)
    local body = Theme.fitLabel(self.body or "", text_width, body_size, 0)
    local content = VerticalGroup:new{
        TextWidget:new{
            text = title,
            face = Font:getFace("smallinfofont", title_size),
            fgcolor = self.foreground or PALETTE.on_surface_variant,
            bold = true,
            max_width = text_width,
        },
        VerticalSpan:new{ width = scale(4) },
        TextWidget:new{
            text = body,
            face = Font:getFace("smallinfofont", body_size),
            fgcolor = self.foreground or PALETTE.on_surface,
            max_width = text_width,
        },
    }
    self[1] = FrameContainer:new{
        width = self.width,
        height = self.height,
        padding = 0,
        bordersize = self.appdock and self.appdock.settings.beta and self.appdock.settings.beta.black_borders and scale(1) or 0,
        color = Blitbuffer.COLOR_BLACK,
        radius = math.floor(self.height * 0.30),
        background = self.background or PALETTE.surface,
        CenterContainer:new{
            dimen = Geom:new{ w = self.width, h = self.height },
            content,
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
            face = Font:getFace("smallinfofont", scale(12)),
            fgcolor = self.foreground or PALETTE.on_surface,
            max_width = self.width - scale(20),
        }
    end
    self[1] = FrameContainer:new{
        width = self.width,
        height = self.height,
        padding = 0,
        bordersize = self.appdock and self.appdock.settings.beta and self.appdock.settings.beta.black_borders and scale(1) or 0,
        color = Blitbuffer.COLOR_BLACK,
        radius = math.floor(self.height * 0.28),
        background = self.background or PALETTE.surface,
        CenterContainer:new{
            dimen = self.dimen,
            content,
        },
    }
end

function SearchBar:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local query_text = self.query ~= "" and (_("Search: ") .. self.query) or _("Search apps")
    local label_size = math.max(scale(9), math.min(scale(14), math.floor(self.height * .42)))
    local label = Theme.fitLabel("⌕  " .. query_text, self.width, label_size, scale(20))
    self[1] = FrameContainer:new{
        width = self.width, height = self.height, padding = 0, bordersize = 0,
        radius = math.floor(self.height * 0.36), background = PALETTE.surface_variant,
        CenterContainer:new{
            dimen = self.dimen,
            TextWidget:new{ text = label, face = Font:getFace("smallinfofont", label_size), fgcolor = PALETTE.on_surface_variant, max_width = self.width - scale(20) },
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

function AppTile:init()
    self.label_height = self.label_height or scale(28)
    self.dimen = Geom:new{
        w = self.tile_size,
        h = self.tile_size + scale(6) + self.label_height,
    }

    local icon = self.app.logo and DAppLogo:new{
        kind = self.app.logo,
        size = math.floor(self.tile_size * 0.52),
        ink = self.foreground or PALETTE.on_primary_container,
    } or TextWidget:new{
        text = self.symbol or iconFor(self.app),
        face = Font:getFace("cfont", math.floor(self.tile_size * 0.40)),
        fgcolor = self.foreground or PALETTE.on_primary_container,
        bold = true,
    }
    local tile = FrameContainer:new{
        width = self.tile_size,
        height = self.tile_size,
        padding = 0,
        bordersize = self.appdock.settings.beta and self.appdock.settings.beta.black_borders and scale(1) or 0,
        color = Blitbuffer.COLOR_BLACK,
        radius = self.shape == "circle" and math.floor(self.tile_size / 2) or math.floor(self.tile_size * 0.32),
        background = self.background or PALETTE.primary_container,
        CenterContainer:new{
            dimen = Geom:new{ w = self.tile_size, h = self.tile_size },
            icon,
        },
    }
    local label_size = math.max(scale(8), math.min(scale(13), self.label_height - scale(6)))
    local label_text = Theme.fitLabel(self.app.title or "", self.tile_size, label_size, 0)
    self.layout = { label = label_text, label_size = label_size }
    local label = TextWidget:new{
        text = label_text,
        face = Font:getFace("smallinfofont", label_size),
        fgcolor = PALETTE.on_surface,
        max_width = self.tile_size,
    }

    self[1] = VerticalGroup:new{
        tile,
        VerticalSpan:new{ width = scale(6) },
        CenterContainer:new{
            dimen = Geom:new{ w = self.tile_size, h = self.label_height },
            label,
        },
    }
    self.ges_events = {
        TapSelectAppTile = {
            GestureRange:new{ ges = "tap", range = self.dimen },
        },
        HoldSelectAppTile = {
            GestureRange:new{ ges = "hold", range = self.dimen },
        },
    }
end

function AppTile:paintTo(bb, x, y)
    local range = self.ges_events.TapSelectAppTile[1].range
    range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    local hold_range = self.ges_events.HoldSelectAppTile[1].range
    hold_range.x, hold_range.y, hold_range.w, hold_range.h = x, y, self.dimen.w, self.dimen.h
    return InputContainer.paintTo(self, bb, x, y)
end

function AppTile:onTapSelectAppTile()
    self.appdock:launchApp(self.app, self.home)
    return true
end

function AppTile:onHoldSelectAppTile()
    self.appdock:showManager(self.home)
    return true
end

function AppDockHomeScreen:init()
    applyTheme(self.appdock)
    self.dimen = Screen:getSize()
    self.page = self.page or 1
    self.appdock:seedDefaults()

    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    self:build()
    self:_scheduleStoreWidgetRefresh()
end

function AppDockHomeScreen:_scheduleStoreWidgetRefresh()
    if self._widget_tick then UIManager:unschedule(self._widget_tick) end
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
    local dialog
    dialog = InputDialog:new{
        title = _("Search AppDock apps"),
        input_hint = _("App name"),
        input = self.search_query or "",
        buttons = {
            {
                { text = _("Clear"), callback = function() self.search_query = ""; UIManager:close(dialog); self:build(); UIManager:setDirty(self, "ui") end },
                { text = _("Search"), is_enter_default = true, callback = function() self.search_query = dialog:getInputText() or ""; UIManager:close(dialog); self:build(); UIManager:setDirty(self, "ui") end },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function AppDockHomeScreen:_pageInfo(apps)
    local per_page = 6
    local pages = math.max(1, math.ceil(#apps / per_page))
    if self.page > pages then self.page = pages end
    local first = (self.page - 1) * per_page + 1
    local visible = {}
    for index = first, math.min(first + per_page - 1, #apps) do
        table.insert(visible, apps[index])
    end
    return visible, pages
end

function AppDockHomeScreen:_showPage(page)
    UIManager:close(self)
    UIManager:nextTick(function()
        UIManager:show(AppDockHomeScreen:new{
            appdock = self.appdock,
            page = page,
        })
    end)
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
        fgcolor = PALETTE.on_surface_variant,
        overlap_offset = { margin, scale(10) },
    }
    table.insert(dashboard, left)

    local right_text = self.appdock.settings.widgets.status and safeBatteryText() or nil
    local quick_size = scale(28)
    local quick_x = width - margin - quick_size
    if right_text then
        local right = TextWidget:new{
            text = right_text,
            face = Font:getFace("smallinfofont", scale(13)),
            fgcolor = PALETTE.on_surface_variant,
        }
        quick_x = width - margin - right:getSize().w - scale(10) - quick_size
        right.overlap_offset = { width - margin - right:getSize().w, scale(11) }
        table.insert(dashboard, right)
    end
    table.insert(dashboard, AppTile:new{
        appdock = self.appdock,
        home = self,
        app = { id = "system:quick_settings", title = "" },
        symbol = "⌄",
        tile_size = quick_size,
        label_height = 0,
        background = PALETTE.surface_variant,
        foreground = PALETTE.on_surface_variant,
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

function AppDockHomeScreen:build()
    local width, height = self.dimen.w, self.dimen.h
    local margin = scale(22)
    local top_line_height = scale(30)
    local header_y = top_line_height + scale(18)
    local layout = self.appdock.settings.layout or {}
    local tile_size = math.floor(math.min(width * 0.20, height * 0.13))
    tile_size = math.max(scale(62), math.min(tile_size, scale(110)))
    local tile_gap = scale(math.max(8, math.min(34, tonumber(layout.app_spacing) or 16)))
    local label_height = scale(28)
    local apps = self.appdock:getPinnedApps()
    local search_query = (self.search_query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if layout.search_enabled and search_query ~= "" then
        local filtered = {}
        for _, app in ipairs(apps) do
            if (app.title or ""):lower():find(search_query, 1, true) then table.insert(filtered, app) end
        end
        apps = filtered
    end
    local visible_apps, page_count = self:_pageInfo(apps)

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

    table.insert(dashboard, TextWidget:new{
        text = greeting(),
        face = Font:getFace("cfont", scale(28)),
        fgcolor = PALETTE.on_surface,
        bold = true,
        overlap_offset = { margin, header_y },
    })
    table.insert(dashboard, TextWidget:new{
        text = os.date("%A, %d %B"),
        face = Font:getFace("smallinfofont", scale(15)),
        fgcolor = PALETTE.on_surface_variant,
        overlap_offset = { margin, header_y + scale(36) },
    })

    local card_y = header_y + scale(66)
    if layout.search_enabled then
        table.insert(dashboard, SearchBar:new{
            appdock = self.appdock, home = self, width = width - 2 * margin, height = scale(42),
            query = self.search_query or "", overlap_offset = { margin, header_y + scale(70) },
        })
        card_y = header_y + scale(122)
    end
    if self.appdock.settings.widgets.status then
        local status_body = safeBatteryText() or _("All systems ready")
        table.insert(dashboard, InfoCard:new{
            appdock = self.appdock,
            width = math.floor((width - 2 * margin - scale(10)) * 0.42),
            height = scale(62),
            title = _("Device"),
            body = status_body,
            background = PALETTE.secondary_container,
            foreground = PALETTE.on_secondary_container,
            overlap_offset = { margin, card_y },
        })
    end

    if self.appdock.settings.widgets.reading_hint then
        local reading_x = self.appdock.settings.widgets.status
            and margin + math.floor((width - 2 * margin - scale(10)) * 0.42) + scale(10)
            or margin
        local reading_width = self.appdock.settings.widgets.status
            and width - margin - reading_x
            or width - 2 * margin
        table.insert(dashboard, InfoCard:new{
            appdock = self.appdock,
            width = reading_width,
            height = scale(62),
            title = _("Continue reading"),
            body = currentBookText(self.appdock),
            background = PALETTE.primary_container,
            foreground = PALETTE.on_primary_container,
            overlap_offset = { reading_x, card_y },
        })
    end

    local has_cards = self.appdock.settings.widgets.status or self.appdock.settings.widgets.reading_hint
    local widget_y = card_y + (has_cards and scale(62) or 0) + (has_cards and scale(12) or 0)
    local widget_height = scale(98)
    local visible_widgets = {}
    for _, widget in ipairs(self.appdock:getStoreWidgets()) do
        if self.appdock:isStoreWidgetEnabled(widget.widget_id) then table.insert(visible_widgets, widget) end
    end
    for index, widget in ipairs(visible_widgets) do
        table.insert(dashboard, StoreWidgetCard:new{
            widget = widget,
            appdock = self.appdock,
            width = width - 2 * margin,
            height = widget_height,
            background = index % 2 == 0 and PALETTE.secondary_container or PALETTE.primary_container,
            foreground = index % 2 == 0 and PALETTE.on_secondary_container or PALETTE.on_primary_container,
            overlap_offset = { margin, widget_y + (index - 1) * (widget_height + scale(10)) },
        })
    end
    local widget_space = #visible_widgets * widget_height + math.max(0, #visible_widgets - 1) * scale(10)
    local grid_y = widget_y + widget_space + scale(34)
    local grid_width = tile_size * 3 + tile_gap * 2
    local grid_x = math.floor((width - grid_width) / 2)
    local row_gap = scale(18)
    for index, app in ipairs(visible_apps) do
        local col = (index - 1) % 3
        local row = math.floor((index - 1) / 3)
        local tone = toneFor(app, index)
        table.insert(dashboard, AppTile:new{
            appdock = self.appdock,
            home = self,
            app = app,
            tile_size = tile_size,
            label_height = label_height,
            shape = layout.logo_shape,
            background = tone.background,
            foreground = tone.foreground,
            overlap_offset = {
                grid_x + col * (tile_size + tile_gap),
                grid_y + row * (tile_size + label_height + row_gap),
            },
        })
    end

    if page_count > 1 then
        local nav_y = height - scale(48)
        local nav_center = math.floor(width / 2)
        if self.page > 1 then
            table.insert(dashboard, self:_navControl("‹", nav_center - scale(64), nav_y, function()
                self:_showPage(self.page - 1)
            end))
        end
        if self.page < page_count then
            table.insert(dashboard, self:_navControl("›", nav_center + scale(34), nav_y, function()
                self:_showPage(self.page + 1)
            end))
        end
        local page_label = TextWidget:new{
            text = string.format("%d / %d", self.page, page_count),
            face = Font:getFace("smallinfofont", scale(13)),
            fgcolor = PALETTE.on_surface_variant,
            overlap_offset = { nav_center - scale(12), nav_y + scale(8) },
        }
        table.insert(dashboard, page_label)
    end

    self[1] = dashboard
end

function AppDockHomeScreen:onClose()
    if self._widget_tick then UIManager:unschedule(self._widget_tick); self._widget_tick = nil end
    UIManager:close(self)
    return true
end

return AppDockHomeScreen
