--[[--
AppDock DApps: stateful in-app tools built around a pane contract.
DApps know only their assigned context.dimen, which makes the same instances
usable in a later split-screen host without global-layout rewrites.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local DataStorage = require("datastorage")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local DAppLogo = require("appdock_logo")
local Theme = require("appdock_theme")
local Help = require("appdock_help")
local WebBrowser = require("appdock_browser")
local FileBrowser = require("appdock_filemanager")
local AppStore = require("appdock_appstore")
local InfoMessage = require("ui/widget/infomessage")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextWidget = require("ui/widget/textwidget")
local ScrollHtmlWidget = require("ui/widget/scrollhtmlwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
if not ok_lfs then lfs = require("lfs") end

local Screen = Device.screen
local ACTIVE_APPDOCK = nil

local DAppManager = {}
DAppManager.__index = DAppManager

local DAppHost = InputContainer:extend{
    manager = nil,
    dapp_id = nil,
    dapp_ids = nil,
    split = false,
    active_pane = nil,
    active_panes = nil,
    split_ratio = nil,
    _split_content_top = nil,
    _split_available = nil,
    _split_touch_range = nil,
    _split_last_y = nil,
    dimen = nil,
    covers_fullscreen = true,
}

local DAppRecents = InputContainer:extend{
    manager = nil,
    dimen = nil,
    covers_fullscreen = true,
}

local ActionChip = InputContainer:extend{
    title = nil,
    symbol = nil,
    callback = nil,
    hold_callback = nil,
    logo = nil,
    width = nil,
    height = nil,
    background = nil,
    foreground = nil,
}

local SplitDivider = InputContainer:extend{
    host = nil,
    width = nil,
    height = nil,
    dimen = nil,
}

local SettingsCategory = InputContainer:extend{
    title = nil,
    logo = nil,
    selected = false,
    callback = nil,
    width = nil,
    height = nil,
}

local SettingsRow = InputContainer:extend{
    title = nil,
    subtitle = nil,
    enabled = false,
    show_state = true,
    callback = nil,
    width = nil,
    height = nil,
}

local StorageSummary = Widget:extend{
    width = nil,
    height = nil,
    segments = nil,
}

local StorageDApps = Widget:extend{
    width = nil,
    height = nil,
    entries = nil,
}

local ClockFace = Widget:extend{
    dimen = nil,
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
    background = color(250, 248, 255, Blitbuffer.COLOR_WHITE),
    surface = color(242, 240, 247, Blitbuffer.COLOR_LIGHT_GRAY),
    surface_variant = color(228, 225, 235, Blitbuffer.COLOR_GRAY_8),
    primary = color(214, 227, 255, Blitbuffer.COLOR_GRAY_8),
    on_primary = color(23, 59, 111, Blitbuffer.COLOR_DARK_GRAY),
    secondary = color(225, 221, 242, Blitbuffer.COLOR_GRAY_7),
    on_secondary = color(59, 54, 79, Blitbuffer.COLOR_DARK_GRAY),
    on_surface = color(31, 29, 36, Blitbuffer.COLOR_BLACK),
    on_variant = color(76, 73, 84, Blitbuffer.COLOR_DARK_GRAY),
    outline = color(121, 117, 128, Blitbuffer.COLOR_GRAY),
}

local function applyTheme(appdock)
    ACTIVE_APPDOCK = appdock
    local palette = Theme.getPalette(appdock)
    PALETTE.background = palette.background
    PALETTE.surface = palette.surface
    PALETTE.surface_variant = palette.surface_variant
    PALETTE.primary = palette.button or palette.primary
    PALETTE.on_primary = palette.on_button or palette.on_primary
    PALETTE.secondary = palette.secondary
    PALETTE.on_secondary = palette.on_secondary
    PALETTE.on_surface = palette.on_surface
    PALETTE.on_variant = palette.on_variant
    PALETTE.outline = palette.outline
end

local function emptySizedWidget(width, height)
    return CenterContainer:new{
        dimen = Geom:new{ w = width, h = height },
        HorizontalSpan:new{ width = 0 },
    }
end

local LEGACY_FILE_HANDLERS = {
    night_lua = { "lua" },
    dreader = { "epub", "html", "htm", "xhtml" },
    markup = { "md", "markdown", "mdown", "mkdn" },
}

local function normalizedExtensions(source)
    local result, seen = {}, {}
    for extension_index, extension in ipairs(type(source) == "table" and source or {}) do
        local normalized = type(extension) == "string" and extension:lower():gsub("^%.", "") or ""
        if normalized:match("^[a-z0-9]+$") and #normalized <= 12 and not seen[normalized] and #result < 12 then
            result[#result + 1], seen[normalized] = normalized, true
        end
    end
    return result
end

local function safeSessionValue(value, depth, budget)
    local value_type = type(value)
    if value_type == "nil" or value_type == "boolean" then return value end
    if value_type == "number" then
        if value ~= value or value == math.huge or value == -math.huge then return nil, false end
        return value
    end
    if value_type == "string" then
        if #value > 1024 then return value:sub(1, 1024) end
        return value
    end
    if value_type ~= "table" or depth >= 3 then return nil, false end
    local result, count = {}, 0
    for key, item in pairs(value) do
        count = count + 1
        if count > 24 or budget.remaining <= 0 then return nil, false end
        local key_type = type(key)
        if not ((key_type == "number" and key >= 1 and key <= 24 and math.floor(key) == key) or (key_type == "string" and #key <= 48 and key:match("^[%w_%-]+$"))) then return nil, false end
        if key_type == "string" then
            local normalized_key = key:lower()
            if normalized_key:find("content", 1, true) or normalized_key:find("document", 1, true) or normalized_key:find("token", 1, true)
                    or normalized_key:find("secret", 1, true) or normalized_key:find("password", 1, true) or normalized_key == "key" then
                return nil, false
            end
        end
        budget.remaining = budget.remaining - 1
        local copied, valid = safeSessionValue(item, depth + 1, budget)
        if valid == false then return nil, false end
        result[key] = copied
    end
    return result
end

local function sanitizeSessionState(value)
    if value == nil then return nil end
    local copied, valid = safeSessionValue(value, 0, { remaining = 96 })
    if valid == false then return nil end
    return copied
end

local function paintLine(bb, x0, y0, x1, y1, thickness, ink)
    local dx, dy = x1 - x0, y1 - y0
    local steps = math.max(math.abs(dx), math.abs(dy))
    if steps < 1 then
        bb:paintRect(math.floor(x0), math.floor(y0), thickness, thickness, ink)
        return
    end
    for step = 0, steps do
        local x = math.floor(x0 + dx * step / steps - thickness / 2)
        local y = math.floor(y0 + dy * step / steps - thickness / 2)
        bb:paintRect(x, y, thickness, thickness, ink)
    end
end

local function humanSize(bytes)
    if bytes >= 1024 * 1024 then return string.format("%.1f MB", bytes / (1024 * 1024)) end
    if bytes >= 1024 then return string.format("%.1f KB", bytes / 1024) end
    return string.format("%d B", bytes)
end

local function safeAttributes(path, selector)
    local ok, value = pcall(lfs.attributes, path, selector)
    if not ok then return nil end
    return value
end

local function safeDirectory(path)
    local ok, iterator, state = pcall(lfs.dir, path)
    if not ok or type(iterator) ~= "function" then return nil, nil end
    return iterator, state
end

local function directorySize(path, depth, budget)
    if not path or depth > 5 or budget.count >= budget.limit then return 0 end
    local mode = safeAttributes(path, "mode")
    if mode == "file" then
        budget.count = budget.count + 1
        return tonumber(safeAttributes(path, "size")) or 0
    end
    if mode ~= "directory" then return 0 end
    local total = 0
    local iterator, state = safeDirectory(path)
    if not iterator then return 0 end
    for name in iterator, state do
        if name ~= "." and name ~= ".." and budget.count < budget.limit then
            total = total + directorySize(path .. "/" .. name, depth + 1, budget)
        end
    end
    return total
end

local function collectDAppStorage(appdock, manager)
    local entries, installed = {}, appdock and appdock.settings and appdock.settings.store and appdock.settings.store.installed or {}
    for id, record in pairs(installed or {}) do
        if record and record.file then
            local budget = { count = 0, limit = 1200 }
            local bytes = directorySize(record.file, 0, budget)
            local definition = manager and manager.definitions and manager.definitions[id]
            table.insert(entries, { id = id, title = definition and definition.title or id, bytes = bytes })
        end
    end
    table.sort(entries, function(left, right)
        if left.bytes == right.bytes then return left.title:lower() < right.title:lower() end
        return left.bytes > right.bytes
    end)
    return entries
end

local function collectStorageSegments(appdock, manager)
    local data_dir = DataStorage:getDataDir()
    local entries, total, budget = {}, 0, { count = 0, limit = 3000 }
    local iterator, state = safeDirectory(data_dir)
    if iterator then
        for name in iterator, state do
            if name ~= "." and name ~= ".." then
                local bytes = directorySize(data_dir .. "/" .. name, 0, budget)
                if bytes > 0 then
                    table.insert(entries, { title = name, bytes = bytes })
                    total = total + bytes
                end
            end
        end
    end
    table.sort(entries, function(left, right) return left.bytes > right.bytes end)
    local segments, top_count = {}, math.min(4, #entries)
    for index = 1, top_count do table.insert(segments, entries[index]) end
    local remainder = 0
    for index = top_count + 1, #entries do remainder = remainder + entries[index].bytes end
    if remainder > 0 then table.insert(segments, { title = _("Other"), bytes = remainder }) end
    if total == 0 then
        local dapps = collectDAppStorage(appdock, manager)
        for _, entry in ipairs(dapps) do total = total + entry.bytes end
        if total > 0 then segments = { { title = _("Installed DApps"), bytes = total } } end
    end
    if total == 0 then table.insert(segments, { title = _("AppDock data scan pending"), bytes = 0 }) end
    return segments, total, budget.count, collectDAppStorage(appdock, manager)
end

function StorageSummary:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
end

function StorageSummary:getSize()
    return self.dimen
end

function StorageSummary:paintTo(bb, x, y)
    local palette = { PALETTE.primary, PALETTE.secondary, PALETTE.on_surface, PALETTE.outline, PALETTE.surface_variant }
    local bar_y, bar_h = y + scale(10), scale(22)
    local total = 0
    for _, segment in ipairs(self.segments or {}) do total = total + segment.bytes end
    total = math.max(1, total)
    local cursor = x
    for index, segment in ipairs(self.segments or {}) do
        local width = index == #(self.segments or {}) and (x + self.width - cursor) or math.max(scale(2), math.floor(self.width * segment.bytes / total))
        bb:paintRect(cursor, bar_y, width, bar_h, palette[(index - 1) % #palette + 1])
        cursor = cursor + width
    end
    local legend_y = bar_y + bar_h + scale(16)
    for index, segment in ipairs(self.segments or {}) do
        local row_y = legend_y + (index - 1) * scale(24)
        bb:paintRect(x, row_y + scale(3), scale(10), scale(10), palette[(index - 1) % #palette + 1])
        local label = Theme.fitLabel(segment.title .. "  " .. humanSize(segment.bytes), self.width - scale(18), scale(12), 0)
        local text = TextWidget:new{ text = label, face = Font:getFace("smallinfofont", scale(12)), fgcolor = PALETTE.on_surface, max_width = self.width - scale(18) }
        text:paintTo(bb, x + scale(18), row_y)
    end
end

function StorageDApps:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
end

function StorageDApps:getSize()
    return self.dimen
end

function StorageDApps:paintTo(bb, x, y)
    local entries = self.entries or {}
    local title = TextWidget:new{ text = Theme.fitLabel(_("DApp storage usage"), self.width, scale(15), 0), face = Font:getFace("cfont", scale(15)), fgcolor = PALETTE.on_surface, bold = true, max_width = self.width }
    title:paintTo(bb, x, y)
    if #entries == 0 then
        TextWidget:new{ text = Theme.fitLabel(_("No installed DApps found"), self.width, scale(11), 0), face = Font:getFace("smallinfofont", scale(11)), fgcolor = PALETTE.on_variant, max_width = self.width }:paintTo(bb, x, y + scale(25))
        return
    end
    local max_bytes = math.max(1, entries[1].bytes)
    for index, entry in ipairs(entries) do
        if index > 6 then break end
        local row_y = y + scale(25) + (index - 1) * scale(29)
        local label = Theme.fitLabel(string.format("%s  ·  %s", entry.title, humanSize(entry.bytes)), self.width, scale(11), 0)
        TextWidget:new{ text = label, face = Font:getFace("smallinfofont", scale(11)), fgcolor = PALETTE.on_surface, max_width = self.width }:paintTo(bb, x, row_y)
        bb:paintRect(x, row_y + scale(18), math.max(scale(3), math.floor((self.width - scale(8)) * entry.bytes / max_bytes)), scale(4), PALETTE.primary)
    end
end

function ActionChip:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local foreground = self.foreground or PALETTE.on_surface
    local title_size = math.max(scale(8), math.min(scale(12), math.floor(self.height * .30)))
    local title = Theme.fitLabel(self.title or "", self.width, title_size, scale(12))
    local has_icon = self.logo or (self.symbol and self.symbol ~= "")
    local icon_size = math.max(scale(14), math.min(scale(24), math.floor(self.height * .52)))
    local icon_widget = nil
    if has_icon then
        icon_widget = self.logo and DAppLogo:new{
            kind = self.logo, size = icon_size, ink = foreground,
        } or TextWidget:new{
            text = self.symbol, face = Font:getFace("cfont", icon_size), fgcolor = foreground, bold = true, padding = 0,
        }
    end
    local title_widget = title ~= "" and TextWidget:new{
        text = title, face = Font:getFace("smallinfofont", title_size), fgcolor = foreground,
        bold = true, max_width = math.max(scale(8), self.width - scale(12)), padding = 0,
    } or nil
    local items = icon_widget and (title_widget and { icon_widget, title_widget } or { icon_widget }) or (title_widget and { title_widget } or {})
    local positions = Theme.centeredStack(self.height, items, title_widget and scale(2) or 0, scale(2))
    local layers = {}
    if icon_widget then
        table.insert(layers, CenterContainer:new{
            dimen = Geom:new{ w = self.width, h = icon_widget:getSize().h },
            icon_widget,
            overlap_offset = { 0, positions[1] },
        })
    end
    if title ~= "" then
        local title_index = icon_widget and 2 or 1
        table.insert(layers, CenterContainer:new{
            dimen = Geom:new{ w = self.width, h = title_widget:getSize().h },
            title_widget,
            overlap_offset = { 0, positions[title_index] },
        })
    end
    self.layout = { title = title, positions = positions, has_icon = has_icon }
    local frame_style = Theme.getButtonFrameStyle(ACTIVE_APPDOCK, self.height, math.floor(self.height * .36))
    self[1] = FrameContainer:new{
        width = self.width,
        height = self.height,
        padding = 0,
        bordersize = frame_style.bordersize or 0,
        color = frame_style.color,
        radius = frame_style.radius or math.floor(self.height * 0.36),
        background = self.background or PALETTE.surface_variant,
        OverlapGroup:new{ dimen = self.dimen, allow_mirroring = false, unpack(layers) },
    }
    self.ges_events = {
        TapDAppAction = { GestureRange:new{ ges = "tap", range = self.dimen } },
        HoldDAppAction = { GestureRange:new{ ges = "hold", range = self.dimen } },
    }
end

function ActionChip:paintTo(bb, x, y)
    for _, event_name in ipairs({ "TapDAppAction", "HoldDAppAction" }) do
        local range = self.ges_events[event_name][1].range
        range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    end
    return InputContainer.paintTo(self, bb, x, y)
end

function ActionChip:onTapDAppAction()
    if self.callback then self.callback() end
    return true
end

function ActionChip:onHoldDAppAction()
    if self.hold_callback then self.hold_callback() end
    return true
end

function SplitDivider:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self[1] = FrameContainer:new{
        width = self.width, height = self.height, padding = 0, bordersize = 0,
        background = PALETTE.outline,
        emptySizedWidget(self.width, self.height),
    }
end

function SplitDivider:paintTo(bb, x, y)
    return InputContainer.paintTo(self, bb, x, y)
end

function SettingsCategory:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local background = self.selected and PALETTE.primary or PALETTE.surface
    local foreground = self.selected and PALETTE.on_primary or PALETTE.on_surface
    local title_size = Theme.adjustText(ACTIVE_APPDOCK, math.max(scale(7), math.min(scale(9), math.floor(self.height * .18))), scale(7))
    local title = Theme.fitLabel(self.title or "", self.width, title_size, scale(8))
    local frame_style = Theme.getButtonFrameStyle(ACTIVE_APPDOCK, self.height, scale(13))
    self[1] = FrameContainer:new{
        width = self.width,
        height = self.height,
        padding = 0,
        bordersize = frame_style.bordersize or 0,
        color = frame_style.color,
        radius = frame_style.radius or scale(13),
        background = background,
        CenterContainer:new{
            dimen = Geom:new{ w = self.width, h = self.height },
            VerticalGroup:new{
                DAppLogo:new{ kind = self.logo, size = scale(20), ink = foreground },
                VerticalSpan:new{ width = scale(2) },
                TextWidget:new{
                    text = title,
                    face = Font:getFace("smallinfofont", title_size),
                    fgcolor = foreground,
                    bold = true,
                    max_width = self.width - scale(8),
                },
            },
        },
    }
    self.ges_events = {
        TapSettingsCategory = { GestureRange:new{ ges = "tap", range = self.dimen } },
    }
end

function SettingsCategory:paintTo(bb, x, y)
    local range = self.ges_events.TapSettingsCategory[1].range
    range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    return InputContainer.paintTo(self, bb, x, y)
end

function SettingsCategory:onTapSettingsCategory()
    if self.callback then self.callback() end
    return true
end

function SettingsRow:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local state = self.show_state and (self.enabled and _("On") or _("Off")) or ""
    local detail = self.subtitle or ""
    if state ~= "" then detail = detail .. " · " .. state end
    local title_size = Theme.adjustText(ACTIVE_APPDOCK, math.max(scale(10), math.min(scale(15), math.floor(self.height * .34))), scale(9))
    local detail_size = Theme.adjustText(ACTIVE_APPDOCK, math.max(scale(8), math.min(scale(12), math.floor(self.height * .26))), scale(7))
    local text_width = math.max(scale(14), self.width - scale(26))
    local title = Theme.fitLabel(self.title or "", text_width, title_size, 0)
    detail = Theme.fitLabel(detail, text_width, detail_size, 0)
    local title_widget = TextWidget:new{ text = title, face = Font:getFace("smallinfofont", title_size), fgcolor = self.enabled and PALETTE.on_primary or PALETTE.on_surface, bold = true, max_width = text_width, padding = 0 }
    local detail_widget = TextWidget:new{ text = detail, face = Font:getFace("smallinfofont", detail_size), fgcolor = self.enabled and PALETTE.on_primary or PALETTE.on_variant, max_width = text_width, padding = 0 }
    local positions = Theme.centeredStack(self.height, { title_widget, detail_widget }, scale(3), scale(4))
    local title_y, detail_y = positions[1], positions[2]
    self.layout = { title = title, detail = detail, title_y = title_y, detail_y = detail_y }
    local frame_style = Theme.getButtonFrameStyle(ACTIVE_APPDOCK, self.height, math.floor(self.height * .28))
    self[1] = FrameContainer:new{
        width = self.width,
        height = self.height,
        padding = 0,
        bordersize = frame_style.bordersize or 0,
        color = frame_style.color,
        radius = frame_style.radius or math.floor(self.height * .28),
        background = self.enabled and PALETTE.primary or PALETTE.surface,
        OverlapGroup:new{
            dimen = self.dimen, allow_mirroring = false,
            title_widget,
            detail_widget,
        },
    }
    title_widget.overlap_offset = { scale(13), title_y }
    detail_widget.overlap_offset = { scale(13), detail_y }
    self.ges_events = {
        TapDAppSetting = { GestureRange:new{ ges = "tap", range = self.dimen } },
    }
end

function SettingsRow:paintTo(bb, x, y)
    local range = self.ges_events.TapDAppSetting[1].range
    range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    return InputContainer.paintTo(self, bb, x, y)
end

function SettingsRow:onTapDAppSetting()
    if self.callback then self.callback() end
    return true
end

function ClockFace:paintTo(bb, x, y)
    local size = math.min(self.dimen.w, self.dimen.h)
    local cx, cy = x + math.floor(size / 2), y + math.floor(size / 2)
    local radius = math.floor(size * 0.42)
    local marker_size = math.max(1, scale(2))
    local hour = tonumber(os.date("%H")) or 0
    local minute = tonumber(os.date("%M")) or 0

    for index = 0, 11 do
        local angle = math.pi * 2 * index / 12
        local marker_radius = radius * 0.88
        local mx = math.floor(cx + math.sin(angle) * marker_radius - marker_size / 2)
        local my = math.floor(cy - math.cos(angle) * marker_radius - marker_size / 2)
        local size_for_marker = index % 3 == 0 and marker_size * 2 or marker_size
        bb:paintRect(mx, my, size_for_marker, size_for_marker, PALETTE.outline)
    end

    local hour_angle = math.pi * 2 * ((hour % 12) + minute / 60) / 12
    local minute_angle = math.pi * 2 * minute / 60
    paintLine(bb, cx, cy,
        cx + math.sin(hour_angle) * radius * 0.50,
        cy - math.cos(hour_angle) * radius * 0.50,
        math.max(2, scale(3)), PALETTE.on_surface)
    paintLine(bb, cx, cy,
        cx + math.sin(minute_angle) * radius * 0.76,
        cy - math.cos(minute_angle) * radius * 0.76,
        math.max(1, scale(2)), PALETTE.on_primary)
    bb:paintRect(cx - scale(3), cy - scale(3), scale(6), scale(6), PALETTE.on_surface)
end

function DAppManager:new(appdock)
    applyTheme(appdock)
    local manager = setmetatable({
        appdock = appdock,
        open_order = {},
        instances = {},
        active_id = nil,
        active_host = nil,
        definitions = {},
        plugin_definitions = {},
        widget_definitions = {},
        widget_instances = {},
        generated_widget_instances = {},
        browser = WebBrowser:new(),
        file_browser = FileBrowser:new(),
        app_store = AppStore:new(),
        help = Help:new({
            scale = scale, palette = PALETTE, Geom = Geom, Font = Font,
            WidgetContainer = WidgetContainer, FrameContainer = FrameContainer,
            OverlapGroup = OverlapGroup, TextWidget = TextWidget,
            ScrollHtmlWidget = ScrollHtmlWidget, ActionChip = ActionChip,
            InputDialog = InputDialog, UIManager = UIManager, _ = _,
            emptySizedWidget = emptySizedWidget,
        }),
    }, self)
    manager:_registerBuiltins()
    manager:_loadStoredDApps()
    return manager
end

function DAppManager:_registerBuiltins()
    self.definitions.analog_clock = {
        id = "analog_clock",
        title = _("Analog Clock"),
        subtitle = _("A calm, minute-updating clock"),
        symbol = "C",
        logo = "analog_clock",
        workspace_restore = true,
        buildPane = function(instance, context)
            return self:_buildClockPane(instance, context)
        end,
    }
    self.definitions.help = {
        id = "help",
        title = _("Help"),
        subtitle = _("Learn AppDock on your device"),
        symbol = "?",
        logo = "help",
        workspace_restore = true,
        buildPane = function(instance, context)
            return self:_buildHelpPane(instance, context)
        end,
    }
    self.definitions.web_browser = {
        id = "web_browser",
        title = _("Web Browser"),
        subtitle = _("DuckDuckGo HTML and readable web pages"),
        symbol = "W",
        logo = "web_browser",
        buildPane = function(instance, context)
            return self.browser:buildPane(instance, context)
        end,
        onClose = function(instance)
            if self.browser.cleanup then self.browser:cleanup(instance) end
        end,
    }
    self.definitions.app_store = {
        id = "app_store",
        title = _("AppStore"),
        subtitle = _("Discover trusted AppDock DApps"),
        symbol = "A",
        logo = "app_store",
        buildPane = function(instance, context)
            return self.app_store:buildPane(instance, context)
        end,
    }
    self.definitions.file_manager = {
        id = "file_manager",
        title = _("File Manager"),
        subtitle = _("Browse your KOReader library"),
        symbol = "F",
        logo = "file_manager",
        buildPane = function(instance, context)
            return self.file_browser:buildPane(instance, context)
        end,
    }
    self.definitions.settings = {
        id = "settings",
        title = _("Settings"),
        subtitle = _("Configure AppDock"),
        symbol = "S",
        logo = "settings",
        workspace_restore = true,
        buildPane = function(instance, context)
            return self:_buildSettingsPane(instance, context)
        end,
    }
end

function DAppManager:_loadStoredDApps()
    local installed = self.appdock.settings.store and self.appdock.settings.store.installed or {}
    for id, item in pairs(installed) do
        if item and item.file then
            if item.kind == "widget" then
                self:loadStoreWidget(item.file, item.source_path, true, id)
            else
                self:loadStoreDApp(item.file, item.source_path, true, id)
            end
        end
    end
end

function DAppManager:inspectStoreWidget(file, expected_id)
    local ok, definition = pcall(dofile, file)
    if not ok then return nil, definition end
    if type(definition) ~= "table" or type(definition.id) ~= "string" or type(definition.title) ~= "string" or type(definition.buildWidget) ~= "function" then
        return nil, _("A store widget must return id, title, and buildWidget.")
    end
    if definition.id:match("[^%w_%-]") or (expected_id and definition.id ~= expected_id) then
        return nil, _("The widget id is invalid.")
    end
    return definition
end

function DAppManager:inspectStoreDApp(file, expected_id)
    local ok, definition = pcall(dofile, file)
    if not ok then return nil, definition end
    if type(definition) ~= "table" or type(definition.id) ~= "string" or type(definition.title) ~= "string" or type(definition.buildPane) ~= "function" then
        return nil, _("A store DApp must return id, title, and buildPane.")
    end
    if definition.id:match("[^%w_%-]") or (expected_id and definition.id ~= expected_id) then
        return nil, _("The DApp id is invalid.")
    end
    return definition
end

function DAppManager:loadStoreDApp(file, source_path, restoring, expected_id, allow_replace, stored_file)
    local definition, inspect_err = self:inspectStoreDApp(file, expected_id)
    if not definition then return false, inspect_err end
    local installed = self.appdock.settings.store and self.appdock.settings.store.installed or {}
    local existing_record = installed[definition.id]
    if self.definitions[definition.id] and not restoring and not (allow_replace and existing_record) then
        return false, _("A DApp with this id already exists.")
    end
    local registered = {
        id = definition.id,
        title = definition.title,
        subtitle = definition.subtitle or _("Installed from AppStore"),
        symbol = definition.symbol or "D",
        logo = definition.logo or "app_store",
        version = type(definition.version) == "string" and definition.version or nil,
        buildPane = definition.buildPane,
        openFile = type(definition.openFile) == "function" and definition.openFile or nil,
        file_extensions = normalizedExtensions(definition.file_extensions),
        file_handler_title = type(definition.file_handler_title) == "string" and Theme.ellipsize(definition.file_handler_title, 48) or nil,
        workspace_restore = definition.workspace_restore == true,
        serializeState = type(definition.serializeState) == "function" and definition.serializeState or nil,
        restoreState = type(definition.restoreState) == "function" and definition.restoreState or nil,
        backgroundTick = type(definition.backgroundTick) == "function" and definition.backgroundTick or nil,
        onAutostart = type(definition.onAutostart) == "function" and definition.onAutostart or nil,
    }
    self.definitions[definition.id] = registered
    if self.instances[definition.id] then
        self.instances[definition.id].definition = registered
        self.instances[definition.id].pane = nil
    end
    if not restoring then
        self.appdock.settings.store = self.appdock.settings.store or { installed = {} }
        self.appdock.settings.store.installed = self.appdock.settings.store.installed or {}
        self.appdock.settings.store.installed[definition.id] = {
            kind = "dapp",
            file = stored_file or file,
            source_path = source_path,
            version = registered.version,
        }
        self.appdock:_saveSettings()
    end
    return true, definition.id
end

function DAppManager:getFileHandlers(path)
    local extension = type(path) == "string" and path:lower():match("%.([a-z0-9]+)$") or nil
    if not extension then return {} end
    local handlers = {}
    for id, definition in pairs(self.definitions) do
        if definition.openFile then
            local extensions = definition.file_extensions
            if #extensions == 0 then extensions = LEGACY_FILE_HANDLERS[id] or {} end
            for extension_index, supported_extension in ipairs(extensions) do
                if supported_extension == extension then
                    handlers[#handlers + 1] = {
                        id = id,
                        title = definition.file_handler_title or (_("Open in ") .. definition.title),
                        app_title = definition.title,
                        logo = definition.logo,
                    }
                    break
                end
            end
        end
    end
    table.sort(handlers, function(left, right) return left.title:lower() < right.title:lower() end)
    return handlers
end

function DAppManager:showFileHandlerChoices(path, handlers)
    if type(path) ~= "string" or type(handlers) ~= "table" or #handlers == 0 then return false end
    if #handlers == 1 then return self:openDAppFile(handlers[1].id, path) end
    local dialog
    local buttons = {}
    for handler_index, handler in ipairs(handlers) do
        buttons[#buttons + 1] = {
            { text = handler.title, callback = function()
                UIManager:close(dialog)
                self:openDAppFile(handler.id, path)
            end },
        }
    end
    dialog = ButtonDialog:new{ title = _("Open with"), buttons = buttons, rows_per_page = { 5, 6, 7 } }
    UIManager:show(dialog)
    return true
end

function DAppManager:loadStoreWidget(file, source_path, restoring, expected_id, allow_replace, stored_file)
    local definition, inspect_err = self:inspectStoreWidget(file, expected_id)
    if not definition then return false, inspect_err end
    local installed = self.appdock.settings.store and self.appdock.settings.store.installed or {}
    local existing_record = installed[definition.id]
    if self.widget_definitions[definition.id] and not restoring and not (allow_replace and existing_record) then
        return false, _("A store widget with this id already exists.")
    end
    if self.definitions[definition.id] then
        return false, _("A DApp already uses this widget id.")
    end
    local registered = {
        id = definition.id,
        title = definition.title,
        subtitle = definition.subtitle or _("Installed from AppStore"),
        symbol = definition.symbol or "W",
        logo = definition.logo or "app_store",
        version = type(definition.version) == "string" and definition.version or nil,
        buildWidget = definition.buildWidget,
    }
    self.widget_definitions[definition.id] = registered
    self.widget_instances[definition.id] = self.widget_instances[definition.id] or { id = definition.id, definition = registered }
    self.widget_instances[definition.id].definition = registered
    if not restoring then
        self.appdock.settings.store = self.appdock.settings.store or { installed = {} }
        self.appdock.settings.store.installed = self.appdock.settings.store.installed or {}
        self.appdock.settings.store.installed[definition.id] = {
            kind = "widget",
            file = stored_file or file,
            source_path = source_path,
            version = registered.version,
        }
        self.appdock:_saveSettings()
    end
    return true, definition.id
end

function DAppManager:getStoreWidgetBySource(source_path)
    local installed = self.appdock.settings.store and self.appdock.settings.store.installed or {}
    for id, record in pairs(installed) do
        if record and record.kind == "widget" and record.source_path == source_path and self.widget_definitions[id] then
            return self.widget_definitions[id], record
        end
    end
    return nil, nil
end

function DAppManager:getStoreWidgets()
    local widgets = {}
    for id, definition in pairs(self.widget_definitions) do
        table.insert(widgets, {
            id = "widget:" .. id,
            widget_id = id,
            title = definition.title,
            subtitle = definition.subtitle,
            symbol = definition.symbol,
            logo = definition.logo,
            definition = definition,
            instance = self.widget_instances[id],
            kind = "widget",
        })
    end
    local generated = self.appdock.settings.widget_generator and self.appdock.settings.widget_generator.items or {}
    for id, item in pairs(generated) do
        local definition = self:_generatedWidgetDefinition(id, item)
        local instance = self.generated_widget_instances[id] or { id = id, definition = definition }
        instance.definition = definition
        self.generated_widget_instances[id] = instance
        table.insert(widgets, {
            id = "widget:" .. id,
            widget_id = id,
            title = definition.title,
            subtitle = definition.subtitle,
            symbol = definition.symbol,
            logo = definition.logo,
            definition = definition,
            instance = instance,
            kind = "generated_widget",
        })
    end
    table.sort(widgets, function(left, right) return left.title:lower() < right.title:lower() end)
    return widgets
end

function DAppManager:_generatedWidgetDefinition(id, item)
    local manager = self
    return {
        id = id,
        title = item.title,
        subtitle = _("Created with WidgetGenerator"),
        symbol = "W",
        logo = "settings",
        buildWidget = function(instance, context)
            return manager:_buildGeneratedWidget(instance, context, item)
        end,
    }
end

function DAppManager:_buildGeneratedWidget(instance, context, item)
    applyTheme(self.appdock)
    local width, height = context.dimen.w, context.dimen.h
    local margin = math.max(6, math.floor(math.min(width, height) * 0.07))
    local lines = {}
    if item.text and item.text ~= "" then lines[#lines + 1] = item.text end
    if item.show_time then lines[#lines + 1] = os.date("%H:%M") end
    if item.show_date then lines[#lines + 1] = os.date("%d.%m.%Y") end
    if item.show_battery then
        local ok, capacity = pcall(function()
            local powerd = Device:getPowerDevice()
            return powerd and powerd.getCapacity and powerd:getCapacity() or nil
        end)
        if ok and type(capacity) == "number" then lines[#lines + 1] = string.format(_("Battery %d%%"), math.floor(capacity + 0.5)) end
    end
    if #lines == 0 then lines[1] = _("Configure this widget in WidgetGenerator.") end
    local content = {
        FrameContainer:new{ width = width, height = height, padding = 0, bordersize = 0, radius = math.max(4, math.floor(height * 0.12)), background = PALETTE.surface_variant or PALETTE.surface, emptySizedWidget(width, height) },
        TextWidget:new{ text = item.title, face = Font:getFace("smallinfofont", math.max(10, scale(12))), bold = true, fgcolor = PALETTE.on_surface, max_width = width - 2 * margin, overlap_offset = { margin, margin } },
    }
    local y = margin + math.max(16, scale(18))
    for line_index, line in ipairs(lines) do
        content[#content + 1] = TextWidget:new{ text = line, face = Font:getFace("smallinfofont", math.max(9, scale(10))), fgcolor = PALETTE.on_variant, max_width = width - 2 * margin, overlap_offset = { margin, y } }
        y = y + math.max(13, scale(15))
    end
    return OverlapGroup:new{ dimen = Geom:new{ w = width, h = height }, allow_mirroring = false, unpack(content) }
end

function DAppManager:getGeneratedWidgets()
    local items, results = self.appdock.settings.widget_generator.items, {}
    for id, item in pairs(items) do
        results[#results + 1] = { id = id, title = item.title, text = item.text, show_time = item.show_time, show_date = item.show_date, show_battery = item.show_battery }
    end
    table.sort(results, function(left, right) return left.title:lower() < right.title:lower() end)
    return results
end

function DAppManager:_normalizedGeneratedWidget(spec)
    spec = type(spec) == "table" and spec or {}
    local title = type(spec.title) == "string" and spec.title:sub(1, 36):match("^%s*(.-)%s*$") or ""
    if title == "" then title = _("Custom widget") end
    return {
        title = title,
        text = type(spec.text) == "string" and spec.text:sub(1, 180) or "",
        show_time = spec.show_time == true,
        show_date = spec.show_date == true,
        show_battery = spec.show_battery == true,
    }
end

function DAppManager:createGeneratedWidget(spec)
    local config = self.appdock.settings.widget_generator
    local count = 0
    for _id in pairs(config.items) do count = count + 1 end
    if count >= 20 then return nil, _("You can create up to 20 custom widgets.") end
    config.next_id = (tonumber(config.next_id) or 0) + 1
    local id = "generated_widget_" .. config.next_id
    config.items[id] = self:_normalizedGeneratedWidget(spec)
    self.appdock.settings.widgets.store[id] = true
    self.appdock:_saveSettings()
    return id, config.items[id]
end

function DAppManager:updateGeneratedWidget(id, spec)
    local items = self.appdock.settings.widget_generator.items
    if not items[id] then return false, _("This custom widget no longer exists.") end
    items[id] = self:_normalizedGeneratedWidget(spec)
    self.generated_widget_instances[id] = nil
    self.appdock:_saveSettings()
    return true, items[id]
end

function DAppManager:removeGeneratedWidget(id)
    local items = self.appdock.settings.widget_generator.items
    if not items[id] then return false, _("This custom widget no longer exists.") end
    items[id] = nil
    self.generated_widget_instances[id] = nil
    self.appdock.settings.widgets.store[id] = nil
    local order = self.appdock.settings.widgets.store_order or {}
    for index = #order, 1, -1 do if order[index] == id then table.remove(order, index) end end
    self.appdock:_saveSettings()
    return true
end

function DAppManager:uninstallStoreWidget(id)
    local installed = self.appdock.settings.store and self.appdock.settings.store.installed or {}
    local record = installed[id]
    if not record or record.kind ~= "widget" or not record.file then return false, _("This store widget is not installed.") end
    local removed, remove_err = os.remove(record.file)
    if not removed and lfs.attributes(record.file) then return false, remove_err or _("The widget file could not be removed.") end
    self.widget_definitions[id] = nil
    self.widget_instances[id] = nil
    installed[id] = nil
    self.appdock.settings.widgets.store[id] = nil
    self.appdock:_saveSettings()
    return true
end

function DAppManager:getStoreDAppBySource(source_path)
    local installed = self.appdock.settings.store and self.appdock.settings.store.installed or {}
    for id, record in pairs(installed) do
        if record and record.source_path == source_path and self.definitions[id] then
            return self.definitions[id], record
        end
    end
    return nil, nil
end

function DAppManager:uninstallStoreDApp(id)
    local installed = self.appdock.settings.store and self.appdock.settings.store.installed or {}
    local record = installed[id]
    if not record or not record.file then return false, _("This DApp is not installed from the AppStore.") end
    local removed, remove_err = os.remove(record.file)
    if not removed and lfs.attributes(record.file) then return false, remove_err or _("The DApp file could not be removed.") end
    if self.active_host then
        for _, active_id in ipairs(self.active_host.dapp_ids or {}) do
            if active_id == id then UIManager:close(self.active_host); break end
        end
    end
    self:closeDApp(id)
    self.definitions[id] = nil
    self.instances[id] = nil
    installed[id] = nil
    self.appdock:_saveSettings()
    return true
end

function DAppManager:getCatalogApps()
    local apps = {}
    for _, definition in pairs(self.definitions) do
        table.insert(apps, {
            id = "dapp:" .. definition.id,
            dapp_id = definition.id,
            title = definition.title,
            subtitle = definition.subtitle,
            symbol = definition.symbol,
            logo = definition.logo,
            kind = "dapp",
        })
    end
    table.sort(apps, function(left, right) return left.title:lower() < right.title:lower() end)
    return apps
end

function DAppManager:_instanceFor(id)
    local instance = self.instances[id]
    if instance then return instance end
    local definition = self.definitions[id] or self.plugin_definitions[id]
    if not definition then return nil end
    instance = {
        id = id,
        definition = definition,
        last_active = nil,
        visible = false,
        pane = nil,
    }
    self.instances[id] = instance
    return instance
end

function DAppManager:_touchOpen(id)
    for index, open_id in ipairs(self.open_order) do
        if open_id == id then table.remove(self.open_order, index); break end
    end
    table.insert(self.open_order, 1, id)
end

function DAppManager:getOpenApps()
    local apps = {}
    for index, id in ipairs(self.open_order) do
        local instance = self.instances[id]
        if instance then
            local is_plugin_host = instance.definition.host_kind == "plugin"
            table.insert(apps, {
                id = id,
                title = instance.definition.title,
                subtitle = is_plugin_host and _("Plugin host · Beta") or (instance.in_split and _("In split screen") or (instance.visible and _("Active") or _("Open"))),
                symbol = instance.definition.symbol,
                logo = instance.definition.logo,
                last_active = instance.last_active,
                can_split = instance.definition.can_split ~= false,
                is_plugin_host = is_plugin_host,
            })
        end
    end
    return apps
end

function DAppManager:captureWorkspace()
    local workspace = self.appdock.settings.workspace or {}
    if workspace.restore_enabled ~= true then return false end
    local records = {}
    for open_index, id in ipairs(self.open_order) do
        local instance = self.instances[id]
        local definition = instance and instance.definition or nil
        if definition and definition.workspace_restore == true and definition.host_kind ~= "plugin" and #records < 4 then
            local state
            if definition.serializeState then
                local ok, serialized = pcall(definition.serializeState, instance)
                if ok then state = sanitizeSessionState(serialized) end
            end
            records[#records + 1] = { id = id, state = state }
        end
    end
    workspace.session = { version = 1, active_id = self.active_id, apps = records, saved_at = os.time() }
    self.appdock.settings.workspace = workspace
    self.appdock:_saveSettings()
    return true
end

function DAppManager:restoreWorkspace()
    local workspace = self.appdock.settings.workspace or {}
    local session = workspace.restore_enabled == true and workspace.session or nil
    if self._workspace_restored or type(session) ~= "table" or session.version ~= 1 then return false end
    self._workspace_restored = true
    local allowed, active_id = {}, type(session.active_id) == "string" and session.active_id or nil
    for record_index, record in ipairs(type(session.apps) == "table" and session.apps or {}) do
        if #allowed >= 4 then break end
        local id = type(record) == "table" and record.id or nil
        local definition = type(id) == "string" and self.definitions[id] or nil
        if definition and definition.workspace_restore == true and definition.host_kind ~= "plugin" then
            local instance = self:_instanceFor(id)
            instance.workspace_state = sanitizeSessionState(record.state)
            self:_touchOpen(id)
            allowed[#allowed + 1] = id
        end
    end
    if active_id and self.instances[active_id] then
        self:activate(active_id)
        return true
    end
    if allowed[1] then
        self:activate(allowed[1])
        return true
    end
    return false
end

function DAppManager:_pluginHostContext(instance, context)
    return {
        appdock = self.appdock,
        manager = self,
        instance = instance,
        plugin = instance.definition.plugin_app,
        notify = function(payload)
            payload = type(payload) == "table" and payload or {}
            payload.source = payload.source or instance.definition.title
            return self.appdock:notify(payload)
        end,
        requestRefresh = context.requestRefresh,
        requestRebuild = context.requestRebuild,
        ui = {
            showMessage = function(title, message)
                instance.plugin_overlay = { kind = "message", title = title, message = message }
                context.requestRebuild("ui")
            end,
        },
    }
end

local function pluginDialogActions(widget)
    local actions = {}
    for _, row in ipairs(type(widget) == "table" and widget.buttons or {}) do
        for _, button in ipairs(type(row) == "table" and row or {}) do
            if type(button) == "table" then
                local label = button.text
                if type(button.text_func) == "function" then
                    local text_ok, generated = pcall(button.text_func)
                    label = text_ok and generated or label
                end
                if type(label) == "string" and label ~= "" then
                    actions[#actions + 1] = {
                        text = label,
                        callback = type(button.callback) == "function" and button.callback or nil,
                        enabled = button.enabled ~= false,
                        primary = button.is_enter_default == true,
                    }
                end
            end
        end
    end
    return actions
end

function DAppManager:_setPluginOverlay(instance, context, overlay)
    instance.plugin_overlay = overlay
    context.requestRebuild("ui")
end

function DAppManager:_dismissPluginOverlay(instance, context, widget)
    if widget and instance.plugin_captured_widgets then instance.plugin_captured_widgets[widget] = nil end
    instance.plugin_overlay = nil
    context.requestRebuild("ui")
end

function DAppManager:_capturePluginWidget(instance, context, widget)
    if type(widget) ~= "table" then return false end
    local title = type(widget.title) == "string" and widget.title or instance.definition.title
    local actions = pluginDialogActions(widget)
    local kind
    if type(widget.getInputText) == "function" or (type(widget.input) == "string" and #actions > 0) then
        kind = "input"
    elseif #actions > 0 then
        kind = "actions"
    elseif type(widget.text) == "string" then
        kind = "message"
    else
        return false
    end
    instance.plugin_captured_widgets = instance.plugin_captured_widgets or {}
    instance.plugin_captured_widgets[widget] = true
    if kind == "input" and type(widget.onShowKeyboard) == "function" then
        widget.appdock_bridge_original_on_show_keyboard = widget.onShowKeyboard
        widget.onShowKeyboard = function() return true end
    end
    instance.plugin_overlay = {
        kind = kind,
        title = title,
        message = type(widget.text) == "string" and widget.text or (type(widget.description) == "string" and widget.description or ""),
        input_hint = type(widget.input_hint) == "string" and widget.input_hint or "",
        widget = widget,
        actions = actions,
        page = 1,
    }
    return true
end

function DAppManager:_runPluginWidgetBridge(instance, context, callback, ...)
    local original_show, original_close = UIManager.show, UIManager.close
    local captured = false
    UIManager.show = function(ui_manager, widget)
        if self:_capturePluginWidget(instance, context, widget) then
            captured = true
            return true
        end
        return original_show(ui_manager, widget)
    end
    UIManager.close = function(ui_manager, widget)
        if instance.plugin_captured_widgets and instance.plugin_captured_widgets[widget] then
            instance.plugin_captured_widgets[widget] = nil
            if instance.plugin_overlay and instance.plugin_overlay.widget == widget then instance.plugin_overlay = nil end
            captured = true
            return true
        end
        return original_close(ui_manager, widget)
    end
    local ok, accepted, reason = pcall(callback, ...)
    UIManager.show, UIManager.close = original_show, original_close
    if captured then context.requestRebuild("ui") end
    return ok, accepted, reason
end

function DAppManager:_showPluginInputEditor(instance, context, overlay)
    local widget = overlay and overlay.widget
    if not widget then return end
    local input = type(widget.getInputText) == "function" and widget:getInputText() or widget.input or ""
    local dialog
    dialog = InputDialog:new{
        title = _("AppDock input") .. " · " .. (overlay.title or instance.definition.title),
        input = type(input) == "string" and input or "",
        input_hint = overlay.input_hint or "",
        buttons = {
            {
                { text = _("Cancel"), callback = function() UIManager:close(dialog) end },
                { text = _("Save"), is_enter_default = true, callback = function()
                    local value = dialog:getInputText()
                    if type(widget.setInputText) == "function" then
                        pcall(widget.setInputText, widget, value)
                    else
                        widget.input = value
                    end
                    UIManager:close(dialog)
                    context.requestRebuild("ui")
                end },
            },
        },
    }
    UIManager:show(dialog)
    if dialog.onShowKeyboard then dialog:onShowKeyboard() end
end

function DAppManager:_invokePluginOverlayAction(instance, context, action)
    local overlay = instance.plugin_overlay
    if not overlay or type(action) ~= "table" or action.enabled == false then return false end
    if action.kind == "edit" then
        self:_showPluginInputEditor(instance, context, overlay)
        return true
    end
    local widget = overlay.widget
    instance.plugin_overlay = nil
    if type(action.callback) ~= "function" then
        self:_dismissPluginOverlay(instance, context, widget)
        return true
    end
    local ok, accepted, reason = self:_runPluginWidgetBridge(instance, context, action.callback)
    if not ok or accepted == false then
        local detail = type(reason) == "string" and reason or (ok and _("The plugin dialog action was not accepted.") or tostring(accepted))
        self.appdock:notify({ title = _("Plugin dialog action failed"), message = detail:sub(1, 240), source = instance.definition.title, priority = "high" })
        return false
    end
    if not instance.plugin_overlay then context.requestRebuild("ui") end
    return true
end

function DAppManager:_buildPluginHostOverlay(instance, context)
    local overlay = instance.plugin_overlay
    if type(overlay) ~= "table" then return nil end
    local width, height = context.dimen.w, context.dimen.h
    local margin, gap = scale(14), scale(8)
    local card_width = width - 2 * margin
    local title = overlay.title or instance.definition.title
    local actions = overlay.actions or {}
    local elements = {
        FrameContainer:new{ width = width, height = height, padding = 0, bordersize = 0, background = PALETTE.surface, emptySizedWidget(width, height) },
        TextWidget:new{ text = title, face = Font:getFace("cfont", scale(19)), fgcolor = PALETTE.on_surface, bold = true, max_width = card_width, overlap_offset = { margin, margin } },
    }
    local y = margin + scale(31)
    if overlay.kind == "input" then
        local value = type(overlay.widget) == "table" and (type(overlay.widget.getInputText) == "function" and overlay.widget:getInputText() or overlay.widget.input) or ""
        elements[#elements + 1] = TextWidget:new{ text = type(value) == "string" and value ~= "" and value or (overlay.input_hint ~= "" and overlay.input_hint or _("No text entered")), face = Font:getFace("smallinfofont", scale(12)), fgcolor = PALETTE.on_variant, max_width = card_width, overlap_offset = { margin, y } }
        y = y + scale(30)
        elements[#elements + 1] = SettingsRow:new{ title = _("Edit text"), subtitle = _("Open AppDock text input"), enabled = true, show_state = false, width = card_width, height = scale(48), callback = function() self:_invokePluginOverlayAction(instance, context, { kind = "edit", enabled = true }) end, overlap_offset = { margin, y } }
        y = y + scale(56)
    elseif type(overlay.message) == "string" and overlay.message ~= "" then
        elements[#elements + 1] = TextWidget:new{ text = overlay.message, face = Font:getFace("smallinfofont", scale(12)), fgcolor = PALETTE.on_variant, max_width = card_width, overlap_offset = { margin, y } }
        y = y + scale(46)
    end
    if #actions == 0 then
        actions = { { text = _("Close"), enabled = true } }
    end
    local per_page = 4
    local total_pages = math.max(1, math.ceil(#actions / per_page))
    overlay.page = math.max(1, math.min(overlay.page or 1, total_pages))
    local first = (overlay.page - 1) * per_page + 1
    for action_index = first, math.min(#actions, first + per_page - 1) do
        local action = actions[action_index]
        elements[#elements + 1] = SettingsRow:new{
            title = action.text or _("Plugin action"), subtitle = action.enabled == false and _("Unavailable") or _("Plugin action in AppDock"), enabled = action.primary == true, show_state = false,
            width = card_width, height = scale(48), callback = function() self:_invokePluginOverlayAction(instance, context, action) end,
            overlap_offset = { margin, y },
        }
        y = y + scale(56)
    end
    if total_pages > 1 then
        local half = math.floor((card_width - gap) / 2)
        elements[#elements + 1] = ActionChip:new{ title = _("‹ Previous"), width = half, height = scale(38), callback = function() overlay.page = math.max(1, overlay.page - 1); context.requestRebuild("ui") end, overlap_offset = { margin, height - margin - scale(38) } }
        elements[#elements + 1] = ActionChip:new{ title = _("Next ›"), width = half, height = scale(38), callback = function() overlay.page = math.min(total_pages, overlay.page + 1); context.requestRebuild("ui") end, overlap_offset = { margin + half + gap, height - margin - scale(38) } }
    elseif overlay.kind ~= "input" then
        elements[#elements + 1] = ActionChip:new{ title = _("Dismiss"), width = card_width, height = scale(38), callback = function() self:_dismissPluginOverlay(instance, context, overlay.widget) end, overlap_offset = { margin, height - margin - scale(38) } }
    end
    return OverlapGroup:new{ dimen = context.dimen, allow_mirroring = false, unpack(elements) }
end

function DAppManager:_newPluginMenuAdapter(instance, context, title, items, dialog)
    local manager = self
    local adapter = {
        item_table = items or {},
        page = 1,
        _dialog = dialog,
    }
    function adapter:updateItems()
        if self._dialog then UIManager:close(self._dialog) end
        manager:_showPluginHostMenu(instance, context, self.item_table, title)
    end
    return adapter
end

function DAppManager:_invokePluginHostItem(instance, context, item, menu_adapter)
    if type(item) ~= "table" then return false end
    local enabled = item.enabled ~= false
    if enabled and type(item.enabled_func) == "function" then
        local enabled_ok, enabled_result = pcall(item.enabled_func)
        enabled = enabled_ok and enabled_result == true
    end
    if not enabled then
        self.appdock:notify({
            title = _("Plugin action unavailable"),
            message = _("This plugin action is currently unavailable."),
            source = instance.definition.title,
            priority = "high",
        })
        return false
    end
    if type(item.callback) == "function" then
        local adapter = menu_adapter or self:_newPluginMenuAdapter(instance, context, instance.definition.title, {}, nil)
        local ok, accepted, reason = self:_runPluginWidgetBridge(instance, context, item.callback, adapter)
        if not ok or accepted == false then
            local detail = type(reason) == "string" and reason or (ok and _("The plugin action was not accepted.") or tostring(accepted))
            self.appdock:notify({
                title = _("Plugin action could not start"),
                message = detail:sub(1, 240),
                source = instance.definition.title,
                priority = "high",
            })
            return false
        end
        return true
    end
    local children = item.sub_item_table
    if type(children) ~= "table" and type(item.sub_item_table_func) == "function" then
        local generated_ok, generated = pcall(item.sub_item_table_func)
        children = generated_ok and generated or nil
    end
    if type(children) == "table" then
        self:_showPluginHostMenu(instance, context, children, item.text or instance.definition.title)
        return true
    end
    self.appdock:notify({
        title = _("Plugin menu entry unavailable"),
        message = _("This plugin menu entry is not launchable in the AppDock beta host."),
        source = instance.definition.title,
        priority = "high",
    })
    return false
end

function DAppManager:_showPluginHostMenu(instance, context, items, title)
    local actions = {}
    for item_index, item in ipairs(items or {}) do
        if type(item) == "table" then
            local label = item.text
            if type(item.text_func) == "function" then
                local text_ok, generated = pcall(item.text_func)
                label = text_ok and generated or label
            end
            if type(label) == "string" and label ~= "" then
                local selected_item = item
                actions[#actions + 1] = {
                    text = label,
                    enabled = item.enabled ~= false,
                    callback = function()
                        local adapter = self:_newPluginMenuAdapter(instance, context, title, items, nil)
                        return self:_invokePluginHostItem(instance, context, selected_item, adapter)
                    end,
                }
            end
        end
    end
    if #actions == 0 then
        self.appdock:notify({
            title = _("Plugin menu unavailable"),
            message = _("This plugin menu has no launchable entries."),
            source = instance.definition.title,
            priority = "high",
        })
        return
    end
    self:_setPluginOverlay(instance, context, { kind = "actions", title = title, actions = actions, page = 1 })
end

function DAppManager:_buildPluginHostPane(instance, context)
    local width, height = context.dimen.w, context.dimen.h
    local plugin_app = instance.definition.plugin_app or {}
    local actions = plugin_app.actions or {}
    if type(plugin_app.buildAppDockPane) == "function" then
        local plugin_context = self:_pluginHostContext(instance, context)
        plugin_context.dimen = context.dimen
        plugin_context.ui_scale = context.ui_scale
        plugin_context.scale = context.scale
        plugin_context.px = context.px
        if not instance.plugin_host_opened and type(plugin_app.instance) == "table" and type(plugin_app.instance.onAppDockHostOpened) == "function" then
            instance.plugin_host_opened = true
            pcall(plugin_app.instance.onAppDockHostOpened, plugin_app.instance, plugin_context)
        end
        local built_ok, plugin_pane = self:_runPluginWidgetBridge(instance, plugin_context, plugin_app.buildAppDockPane, plugin_app.instance, plugin_context)
        if built_ok and type(plugin_pane) == "table" then
            plugin_pane.plugin_host_layout = { is_plugin_host = true, action_count = #actions, can_split = false, using_plugin_pane = true }
            return plugin_pane
        end
    end
    local pane = FrameContainer:new{
        width = width, height = height, padding = 0, bordersize = 0,
        background = PALETTE.background,
        emptySizedWidget(width, height),
    }
    local content = OverlapGroup:new{
        dimen = context.dimen,
        allow_mirroring = false,
        TextWidget:new{ text = plugin_app.title or instance.definition.title, face = Font:getFace("cfont", scale(21)), fgcolor = PALETTE.on_surface, bold = true, max_width = width - scale(36), overlap_offset = { scale(18), scale(18) } },
        TextWidget:new{ text = _("Plugin host · Beta · Split screen unavailable"), face = Font:getFace("smallinfofont", scale(11)), fgcolor = PALETTE.on_variant, max_width = width - scale(36), overlap_offset = { scale(18), scale(48) } },
        TextWidget:new{ text = _("Choose a plugin action. Compatible plugins may send local AppDock notifications through the host context."), face = Font:getFace("smallinfofont", scale(11)), fgcolor = PALETTE.on_variant, max_width = width - scale(36), overlap_offset = { scale(18), scale(68) } },
    }
    local shown_count = math.min(#actions, 5)
    local has_more = #actions > shown_count
    local row_count = shown_count + (has_more and 1 or 0)
    if row_count == 0 then
        content[#content + 1] = TextWidget:new{ text = _("This plugin currently exposes no launchable AppDock action."), face = Font:getFace("smallinfofont", scale(13)), fgcolor = PALETTE.on_surface, max_width = width - scale(36), overlap_offset = { scale(18), scale(116) } }
    else
        local top, gap = scale(104), scale(8)
        local row_height = math.max(scale(42), math.min(scale(58), math.floor((height - top - scale(18) - gap * (row_count - 1)) / row_count)))
        for action_index = 1, shown_count do
            local selected_action = actions[action_index]
            content[#content + 1] = SettingsRow:new{
                title = selected_action.title or _("Plugin action"),
                subtitle = _("Run through the AppDock beta host"), show_state = false,
                width = width - scale(36), height = row_height,
                callback = function() self:_invokePluginHostItem(instance, context, selected_action.item) end,
                overlap_offset = { scale(18), top + (action_index - 1) * (row_height + gap) },
            }
        end
        if has_more then
            content[#content + 1] = SettingsRow:new{
                title = _("More plugin actions"), subtitle = _("Open the remaining published menu entries"), show_state = false,
                width = width - scale(36), height = row_height,
                callback = function() self:_showPluginHostMenu(instance, context, actions, plugin_app.title or instance.definition.title) end,
                overlap_offset = { scale(18), top + shown_count * (row_height + gap) },
            }
        end
    end
    pane[1] = content
    pane.plugin_host_layout = { is_plugin_host = true, action_count = #actions, can_split = false }
    return pane
end

function DAppManager:activatePlugin(plugin_app, home)
    if type(plugin_app) ~= "table" or type(plugin_app.plugin_name) ~= "string" or type(plugin_app.actions) ~= "table" then return false end
    local id = "plugin_host:" .. plugin_app.plugin_name
    self.plugin_definitions[id] = {
        id = id,
        title = plugin_app.title or plugin_app.plugin_name,
        subtitle = _("Plugin host · Beta"),
        symbol = (plugin_app.title or plugin_app.plugin_name):sub(1, 1):upper(),
        host_kind = "plugin",
        can_split = false,
        plugin_app = plugin_app,
        buildPane = function(host_instance, host_context) return self:_buildPluginHostPane(host_instance, host_context) end,
    }
    self:activate(id, home)
    if #plugin_app.actions == 1 then
        local single_action = plugin_app.actions[1]
        UIManager:nextTick(function()
            local host = self.active_host
            local instance = self.instances[id]
            if host and instance and host.dapp_id == id and instance.visible then
                local context = self:_newContext(host, instance)
                self:_invokePluginHostItem(instance, context, single_action.item)
            end
        end)
    end
    return true
end

function DAppManager:_newContext(host, instance, assigned_dimen)
    local width, height = host.dimen.w, host.dimen.h
    local appbar_height = scale(52)
    assigned_dimen = assigned_dimen or Geom:new{ x = 0, y = appbar_height, w = width, h = height - appbar_height }
    -- New DApps should scale type and spacing from the actual pane they receive.
    -- Existing DApps may keep using Screen:scaleBySize() and context.dimen.
    local baseline_width, baseline_height = 600, 748
    local ui_scale = math.max(0.45, math.min(1.40, math.min(assigned_dimen.w / baseline_width, assigned_dimen.h / baseline_height)))
    return {
        manager = self,
        appdock = self.appdock,
        instance = instance,
        host = host,
        -- Single and split hosts both hand out an explicit local pane rectangle.
        dimen = assigned_dimen,
        -- `scale` / `ui_scale` are relative to a 600 × 748 content pane.
        -- `px(value)` keeps an E-Ink-safe minimum of one device pixel.
        scale = ui_scale,
        ui_scale = ui_scale,
        base_dimen = { w = baseline_width, h = baseline_height },
        px = function(value) return math.max(1, math.floor((tonumber(value) or 0) * ui_scale + 0.5)) end,
        relative = function(width_ratio, height_ratio)
            return Geom:new{
                w = math.max(1, math.floor(assigned_dimen.w * math.max(0, tonumber(width_ratio) or 0) + 0.5)),
                h = math.max(1, math.floor(assigned_dimen.h * math.max(0, tonumber(height_ratio) or 0) + 0.5)),
            }
        end,
        requestRefresh = function(refreshtype, region)
            if self.active_host == host then
                UIManager:setDirty(host, refreshtype or "ui", region)
                if UIManager.forceRePaint then UIManager:forceRePaint() end
            end
        end,
        requestRebuild = function(refreshtype)
            if self.active_host == host then
                host:rebuild()
                UIManager:setDirty(host, refreshtype or "ui")
                if UIManager.forceRePaint then UIManager:forceRePaint() end
            end
        end,
        notify = function(payload)
            payload = type(payload) == "table" and payload or {}
            payload.source = payload.source or instance.definition.title or instance.id
            return self.appdock:notify(payload)
        end,
    }
end

function DAppManager:_backgroundContext(instance)
    return {
        manager = self,
        appdock = self.appdock,
        instance = instance,
        background = true,
        now = os.time(),
        notify = function(payload)
            payload = type(payload) == "table" and payload or {}
            payload.source = payload.source or instance.definition.title or instance.id
            return self.appdock:notify(payload)
        end,
    }
end

function DAppManager:runPermittedAutostarts()
    for id, definition in pairs(self.definitions) do
        local permissions = self.appdock:getDAppPermissions(id)
        if permissions.autostart and definition.onAutostart then
            local instance = self:_instanceFor(id)
            pcall(definition.onAutostart, instance, self:_backgroundContext(instance))
        end
    end
end

function DAppManager:runPermittedBackgroundTasks()
    for id, definition in pairs(self.definitions) do
        local permissions = self.appdock:getDAppPermissions(id)
        if permissions.background and definition.backgroundTick then
            local instance = self:_instanceFor(id)
            pcall(definition.backgroundTick, instance, self:_backgroundContext(instance))
        end
    end
end

function DAppManager:activate(id, home)
    local instance = self:_instanceFor(id)
    if not instance then return end
    if home then UIManager:close(home) end
    if self.active_host then UIManager:close(self.active_host) end
    self.active_id = id
    instance.last_active = os.time()
    instance.visible = true
    self:_touchOpen(id)
    instance.in_split = false
    self:captureWorkspace()
    local host = DAppHost:new{ manager = self, dapp_id = id, dapp_ids = { id }, split = false }
    self.active_host = host
    UIManager:show(host)
end

function DAppManager:openDAppFile(id, file)
    local instance = self:_instanceFor(id)
    if not instance then return false, _("This DApp is not installed.") end
    local handler = instance.definition.openFile
    if not handler then return false, _("This DApp cannot open files from AppDock Files.") end
    local ok, accepted, reason = pcall(handler, instance, file)
    if not ok then return false, accepted end
    if not accepted then return false, reason or _("The DApp could not open this file.") end
    self:activate(id)
    return true
end

function DAppManager:showDAppActions(id, recents)
    local instance = self.instances[id]
    if not instance then return end
    if instance.definition.can_split == false then
        local dialog
        dialog = ButtonDialog:new{
            title = instance.definition.title,
            buttons = {
                { { text = _("Plugin host beta · Split screen unavailable"), enabled = false } },
                { { text = _("Close app"), callback = function()
                    UIManager:close(dialog)
                    self:closeDApp(id)
                    if recents then recents:build(); UIManager:setDirty(recents, "ui") end
                end } },
            },
        }
        UIManager:show(dialog)
        return
    end
    local dialog
    dialog = ButtonDialog:new{
        title = instance.definition.title,
        buttons = {
            {
                {
                    text = _("Splitscreen"),
                    callback = function()
                        UIManager:close(dialog)
                        UIManager:nextTick(function() self:beginSplitSelection(id, recents) end)
                    end,
                },
            },
            {
                {
                    text = _("Close app"),
                    callback = function()
                        UIManager:close(dialog)
                        self:closeDApp(id)
                        if recents then
                            recents:build()
                            UIManager:setDirty(recents, "ui")
                        end
                    end,
                },
            },
        },
        rows_per_page = { 5, 6, 7 },
    }
    UIManager:show(dialog)
end

function DAppManager:beginSplitSelection(first_id, recents)
    local first_instance = self.instances[first_id]
    if not first_instance or first_instance.definition.can_split == false then
        self.appdock:notify({ title = _("Plugin host beta"), message = _("Plugin host beta sessions cannot use split screen."), source = first_instance and first_instance.definition.title or "AppDock", priority = "high" })
        return
    end
    local candidates = {}
    for _, app in ipairs(self:getOpenApps()) do
        if app.id ~= first_id and app.can_split ~= false then table.insert(candidates, app) end
    end
    if #candidates == 0 then
        UIManager:show(InfoMessage:new{
            text = _("Open another DApp first, then choose it for split screen."),
        })
        return
    end

    local dialog
    local buttons = {}
    for _, app in ipairs(candidates) do
        table.insert(buttons, {
            {
                text = app.title,
                callback = function()
                    UIManager:close(dialog)
                    if recents then UIManager:close(recents) end
                    UIManager:nextTick(function() self:startSplit(first_id, app.id) end)
                end,
            },
        })
    end
    dialog = ButtonDialog:new{
        title = _("Choose second app"),
        buttons = buttons,
        rows_per_page = { 5, 6, 7 },
    }
    UIManager:show(dialog)
end

function DAppManager:startSplit(first_id, second_id)
    if first_id == second_id then return end
    local first = self.instances[first_id]
    local second = self.instances[second_id]
    if not first or not second then return end
    if first.definition.can_split == false or second.definition.can_split == false then
        local blocked = first.definition.can_split == false and first or second
        self.appdock:notify({ title = _("Plugin host beta"), message = _("Plugin host beta sessions cannot use split screen."), source = blocked.definition.title, priority = "high" })
        return
    end
    if self.active_host then UIManager:close(self.active_host) end

    local now = os.time()
    self.active_id = nil
    for _, instance in ipairs({ first, second }) do
        instance.last_active = now
        instance.visible = true
        instance.in_split = true
        self:_touchOpen(instance.id)
    end
    self:captureWorkspace()
    local host = DAppHost:new{
        manager = self,
        dapp_ids = { first_id, second_id },
        split = true,
    }
    self.active_host = host
    UIManager:show(host)
end

function DAppManager:detachHost(host)
    if self.active_host ~= host then return end
    for _, id in ipairs(host.dapp_ids or { self.active_id }) do
        local instance = self.instances[id]
        if instance and instance.pane and instance.pane.onDeactivate then
            instance.pane:onDeactivate()
        end
        if instance then
            instance.visible = false
            instance.in_split = false
            instance.pane = nil
        end
    end
    self.active_host = nil
    self.active_id = nil
    self:captureWorkspace()
end

function DAppManager:closeDApp(id)
    local instance = self.instances[id]
    if not instance then return end
    if type(instance.definition.canClose) == "function" then
        local checked, allowed, message = pcall(instance.definition.canClose, instance)
        if not checked or allowed == false then
            UIManager:show(InfoMessage:new{ text = tostring(message or _("This app has unsaved changes.")) })
            return false
        end
    end
    if self.active_id == id and self.active_host then
        UIManager:close(self.active_host)
    end
    for index, open_id in ipairs(self.open_order) do
        if open_id == id then table.remove(self.open_order, index); break end
    end
    if type(instance.definition.onClose) == "function" then pcall(instance.definition.onClose, instance) end
    if instance.definition.host_kind == "plugin" then self.plugin_definitions[id] = nil end
    self.instances[id] = nil
    if self.active_id == id then self.active_id = nil end
    self:captureWorkspace()
    return true
end

function DAppManager:showRecents(home)
    if home then UIManager:close(home) end
    if self.active_host then UIManager:close(self.active_host) end
    UIManager:show(DAppRecents:new{ manager = self })
end

function DAppManager:showHomeFromHost(host)
    UIManager:close(host)
    UIManager:nextTick(function() self.appdock:showHome(true) end)
end

function DAppManager:showRecentsFromHost(host)
    UIManager:close(host)
    UIManager:nextTick(function() self:showRecents() end)
end

function DAppManager:openManagerFromHost(host)
    UIManager:close(host)
    UIManager:nextTick(function() self.appdock:showManager() end)
end

function DAppManager:showQuickSettingsFromHost(host)
    local QuickSettings = require("appdock_quicksettings")
    QuickSettings:show{ appdock = self.appdock, home = host }
end

function DAppManager:_wifiState()
    local ok, NetworkMgr = pcall(require, "ui/network/manager")
    if not ok or not NetworkMgr or type(NetworkMgr.isWifiOn) ~= "function" then
        return false, false, nil
    end
    local state_ok, wifi_on = pcall(NetworkMgr.isWifiOn, NetworkMgr)
    return state_ok and not not wifi_on, state_ok, NetworkMgr
end

function DAppManager:toggleWifiFromSettings(context)
    local wifi_on, available, NetworkMgr = self:_wifiState()
    if not available then
        UIManager:show(InfoMessage:new{ text = _("Wi-Fi controls are unavailable on this device.") })
        return
    end
    local callback = function() context.requestRebuild("ui") end
    if wifi_on then
        NetworkMgr:toggleWifiOff(callback, true)
    else
        NetworkMgr:toggleWifiOn(callback, false, true)
    end
end

function DAppManager:isKoboLibraColour()
    local is_kobo = type(Device.isKobo) == "function" and Device:isKobo()
    return is_kobo and Device.model == "Kobo_monza"
end

function DAppManager:_bluetoothPlugin()
    local ui = self.appdock and self.appdock.ui or {}
    local plugin = ui.Bluetooth or ui.bluetooth
    return plugin and type(plugin.addToMainMenu) == "function" and plugin or nil
end

function DAppManager:showBluetoothSettings()
    if not self:isKoboLibraColour() then
        self:showSettingsNotice(_("Bluetooth controls are shown only on Kobo Libra Colour."))
        return
    end
    local plugin = self:_bluetoothPlugin()
    if not plugin then
        self:showSettingsNotice(_("Bluetooth support requires a separately installed KOReader Bluetooth plugin. AppDock does not control Bluetooth drivers itself. Third-party MTK Bluetooth support can be experimental; returning to Nickel may require a reboot."))
        return
    end
    local menu_items = {}
    local ok = pcall(plugin.addToMainMenu, plugin, menu_items)
    local entry = ok and menu_items.bluetooth or nil
    if type(entry) ~= "table" or type(entry.sub_item_table) ~= "table" then
        self:showSettingsNotice(_("The installed Bluetooth plugin does not provide a compatible settings menu."))
        return
    end
    local function show_items(items, title)
        local dialog
        local buttons = {}
        for item_index, item in ipairs(items) do
            if type(item) == "table" then
                local label = item.text
                if type(item.text_func) == "function" then
                    local text_ok, generated = pcall(item.text_func)
                    label = text_ok and generated or label
                end
                if type(label) == "string" then
                    buttons[#buttons + 1] = { { text = label, callback = function()
                        UIManager:close(dialog)
                        if type(item.callback) == "function" then item.callback()
                        elseif type(item.sub_item_table) == "table" then show_items(item.sub_item_table, label)
                        elseif type(item.sub_item_table_func) == "function" then
                            local sub_ok, sub_items = pcall(item.sub_item_table_func)
                            if sub_ok and type(sub_items) == "table" then show_items(sub_items, label) else self:showSettingsNotice(_("Bluetooth plugin menu is unavailable.")) end
                        end
                    end } }
                end
            end
        end
        buttons[#buttons + 1] = { { text = _("Back"), callback = function() UIManager:close(dialog) end } }
        dialog = ButtonDialog:new{ title = title, buttons = buttons }
        UIManager:show(dialog)
    end
    show_items(entry.sub_item_table, _("Bluetooth · Kobo Libra Colour") .. "\n" .. _("External plugin only. Third-party MTK Bluetooth may be experimental; returning to Nickel can require a reboot."))
end

function DAppManager:showFrontlightSettings()
    UIManager:broadcastEvent(Event:new("ShowFlDialog"))
end

function DAppManager:toggleColorTheme(context)
    UIManager:broadcastEvent(Event:new("ToggleNightMode"))
    context.requestRebuild("ui")
end

function DAppManager:showSettingsNotice(text)
    UIManager:show(InfoMessage:new{ text = text })
end

function DAppManager:getIntegrityStatus()
    local installed = self.appdock.settings.store and self.appdock.settings.store.installed or {}
    local app_count, missing_count = 0, 0
    for _, record in pairs(installed) do
        app_count = app_count + 1
        local file = type(record) == "table" and type(record.file) == "string" and io.open(record.file, "rb") or nil
        if not file then
            missing_count = missing_count + 1
        else
            file:close()
        end
    end
    local workspace = self.appdock.settings.workspace or {}
    local session_apps = workspace.session and type(workspace.session.apps) == "table" and #workspace.session.apps or 0
    return {
        installed = app_count,
        missing = missing_count,
        open = #self.open_order,
        workspace_enabled = workspace.restore_enabled == true,
        session_apps = session_apps,
    }
end

function DAppManager:showAccessibilityEditor(instance, context)
    local current = self.appdock.settings.accessibility or { text_scale = 1, high_contrast = false }
    local dialog
    local function choose(changes)
        if self.appdock:setAccessibility(changes) then
            UIManager:close(dialog)
            context.requestRebuild("ui")
        end
    end
    dialog = ButtonDialog:new{
        title = _("Accessibility") .. "\n" .. string.format(_("Text size: %d%% · contrast: %s"), math.floor((current.text_scale or 1) * 100 + .5), current.high_contrast and _("high") or _("standard")),
        buttons = {
            { { text = "90%", callback = function() choose({ text_scale = .9 }) end }, { text = "100%", callback = function() choose({ text_scale = 1 }) end } },
            { { text = "115%", callback = function() choose({ text_scale = 1.15 }) end }, { text = "130%", callback = function() choose({ text_scale = 1.3 }) end } },
            { { text = current.high_contrast and _("Use standard contrast") or _("Use high contrast"), callback = function() choose({ high_contrast = not current.high_contrast }) end } },
            { { text = _("Cancel"), callback = function() UIManager:close(dialog) end } },
        },
    }
    UIManager:show(dialog)
end

function DAppManager:showWorkspaceEditor(instance, context)
    local workspace = self.appdock.settings.workspace or { restore_enabled = false, session = nil }
    local session_apps = workspace.session and type(workspace.session.apps) == "table" and #workspace.session.apps or 0
    local dialog
    dialog = ButtonDialog:new{
        title = _("Local workspace") .. "\n" .. string.format(_("%d restorable local app(s)"), session_apps),
        buttons = {
            { { text = workspace.restore_enabled and _("Disable and clear") or _("Enable restoration"), callback = function()
                self.appdock:setWorkspaceRestoreEnabled(not workspace.restore_enabled)
                UIManager:close(dialog)
                context.requestRebuild("ui")
            end } },
            { { text = _("Cancel"), callback = function() UIManager:close(dialog) end } },
        },
    }
    UIManager:show(dialog)
end

function DAppManager:showIntegrityStatus()
    local status = self:getIntegrityStatus()
    local issue = status.missing > 0 and string.format(_("%d Store file(s) are missing."), status.missing) or _("No missing Store DApp files found.")
    self:showSettingsNotice(string.format(_("Local AppDock status\n\nStore items: %d\nOpen apps: %d\nWorkspace restoration: %s\nSaved local apps: %d\n\n%s\n\nNo files were changed."), status.installed, status.open, status.workspace_enabled and _("enabled") or _("disabled"), status.session_apps, issue))
end

function DAppManager:showArrangementEditor(instance, context)
    local dialog
    local buttons = {
        { { text = _("Apps"), enabled = false } },
    }
    local pinned = self.appdock:getPinnedApps()
    local function addMoveRow(item, position, total, move)
        table.insert(buttons, {
            {
                text = "↑",
                enabled = position > 1,
                callback = function()
                    if position > 1 then
                        move(-1)
                        UIManager:close(dialog)
                        UIManager:nextTick(function() self:showArrangementEditor(instance, context) end)
                        context.requestRebuild("ui")
                    end
                end,
            },
            { text = string.format("%d/%d  %s", position, total, item.title), enabled = false },
            {
                text = "↓",
                enabled = position < total,
                callback = function()
                    if position < total then
                        move(1)
                        UIManager:close(dialog)
                        UIManager:nextTick(function() self:showArrangementEditor(instance, context) end)
                        context.requestRebuild("ui")
                    end
                end,
            },
        })
    end
    for position, app in ipairs(pinned) do
        addMoveRow(app, position, #pinned, function(delta) self.appdock:movePinned(app.id, delta) end)
    end
    table.insert(buttons, { { text = _("Store widgets"), enabled = false } })
    local widgets = self.appdock:getStoreWidgets()
    for position, widget in ipairs(widgets) do
        addMoveRow(widget, position, #widgets, function(delta) self.appdock:moveStoreWidget(widget.widget_id, delta) end)
    end
    table.insert(buttons, { { text = _("Done"), callback = function() UIManager:close(dialog); context.requestRebuild("ui") end } })
    dialog = ButtonDialog:new{
        title = _("Arrange apps & widgets"),
        buttons = buttons,
    }
    UIManager:show(dialog)
end

function DAppManager:showThemeEditor(instance, context)
    local dialog
    local buttons = {}
    local themes = Theme.getThemeList(self.appdock.settings)
    for _, theme in ipairs(themes) do
        table.insert(buttons, {
            {
                text = theme.title .. "  " .. theme.primary,
                callback = function()
                    self.appdock:setTheme(theme.id)
                    UIManager:close(dialog)
                    context.requestRebuild("ui")
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = _("Create custom theme"),
            callback = function()
                UIManager:close(dialog)
                self:showCustomThemeNameDialog(instance, context)
            end,
        },
    })
    dialog = ButtonDialog:new{
        title = _("Color themes"),
        buttons = buttons,
        rows_per_page = { 5, 6, 7 },
    }
    UIManager:show(dialog)
end

function DAppManager:showStoreDesignEditor(instance, context)
    local design = self.appdock:getActiveDesign()
    if not design then
        self:showSettingsNotice(_("No Store design is active. Open AppStore → Category: Designs to browse available designs."))
        return
    end
    local dialog
    dialog = ButtonDialog:new{
        title = _("Active Store design") .. "\n" .. design.title .. " · " .. (design.button_style == "3d" and _("3D buttons") or _("Rounded buttons")) .. " · " .. (design.logo_shape == "circle" and _("circle logos") or _("rounded logos")),
        buttons = {
            { { text = _("Use personal appearance"), callback = function()
                self.appdock:setStoreDesignActive(nil)
                UIManager:close(dialog)
                context.requestRebuild("ui")
            end } },
            { { text = _("Keep design"), callback = function() UIManager:close(dialog) end } },
        },
    }
    UIManager:show(dialog)
end

function DAppManager:showLanguageSelector(context)
    local Language = require("ui/language")
    local dialog
    local current = G_reader_settings:readSetting("language") or "C"
    local function choose(locale)
        UIManager:close(dialog)
        if current ~= locale then Language:changeLanguage(locale) end
    end
    dialog = ButtonDialog:new{
        title = _("UI language"),
        buttons = {
            { { text = (current == "de" and "✓ " or "") .. _("German"), callback = function() choose("de") end },
              { text = (current == "C" and "✓ " or "") .. _("English"), callback = function() choose("C") end } },
            { { text = _("Cancel"), callback = function() UIManager:close(dialog) end } },
        },
    }
    UIManager:show(dialog)
end

function DAppManager:showLauncherLayout(instance, context)
    local layout = self.appdock.settings.layout
    local dialog
    local function choose(changes)
        self.appdock:setLauncherLayout(changes)
        UIManager:close(dialog)
        context.requestRebuild("ui")
    end
    dialog = ButtonDialog:new{
        title = _("Launcher layout") .. "\n" .. string.format(_("Spacing: %d · Shape: %s · Search: %s"), layout.app_spacing, layout.logo_shape == "circle" and _("Circle") or _("Rounded Box"), layout.search_enabled and _("On") or _("Off")),
        buttons = {
            { { text = _("Compact spacing"), callback = function() choose({ app_spacing = 10 }) end }, { text = _("Comfortable spacing"), callback = function() choose({ app_spacing = 16 }) end } },
            { { text = _("Wide spacing"), callback = function() choose({ app_spacing = 24 }) end }, { text = layout.logo_shape == "circle" and _("Use rounded boxes") or _("Use circles"), callback = function() choose({ logo_shape = layout.logo_shape == "circle" and "rounded" or "circle" }) end } },
            { { text = layout.search_enabled and _("Disable app search") or _("Enable app search"), callback = function() choose({ search_enabled = not layout.search_enabled }) end } },
            { { text = _("Set spacing manually (Beta)"), callback = function() UIManager:close(dialog); self:showManualAppSpacingDialog(instance, context) end } },
            { { text = _("Cancel"), callback = function() UIManager:close(dialog) end } },
        },
    }
    UIManager:show(dialog)
end

function DAppManager:showWallpaperEditor(instance, context)
    local dialog
    local wallpaper = self.appdock.settings.wallpaper
    dialog = InputDialog:new{
        title = _("Homescreen background image"),
        description = _("Local PNG, JPG, GIF, WEBP or SVG path. The image stays on this device."),
        input_hint = _("Full image path"),
        input = wallpaper.path or "",
        buttons = { {
            { text = _("Disable"), callback = function() self.appdock:setWallpaper(nil, false); UIManager:close(dialog); context.requestRebuild("ui") end },
            { text = _("Use image"), is_enter_default = true, callback = function()
                local enabled = self.appdock:setWallpaper(dialog:getInputText() or "", true)
                UIManager:close(dialog)
                if not enabled then self:showSettingsNotice(_("Choose an existing PNG, JPG, GIF, WEBP or SVG file.")) end
                context.requestRebuild("ui")
            end },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function DAppManager:showLockscreenSecretDialog(instance, context, method)
    local dialog
    dialog = InputDialog:new{
        title = method == "pattern" and _("Set AppDock pattern") or _("Set AppDock PIN"),
        description = method == "pattern" and _("Use 4–9 different digits from 1 to 9. Tap these points on the lockscreen in the same order.") or _("Choose a 4–32 digit AppDock PIN."),
        input_hint = method == "pattern" and _("Example: 1258") or _("PIN"),
        input = "",
        input_type = "number",
        buttons = { {
            { text = _("Cancel"), callback = function() UIManager:close(dialog) end },
            { text = _("Save"), is_enter_default = true, callback = function()
                local secret = dialog:getInputText() or ""
                if method == "pattern" then
                    local unique = {}
                    for digit in secret:gmatch(".") do unique[digit] = (unique[digit] or 0) + 1 end
                    for point, count in pairs(unique) do if count > 1 then UIManager:close(dialog); self:showSettingsNotice(_("A pattern cannot repeat a point.")); return end end
                    if secret:match("[^1-9]") then UIManager:close(dialog); self:showSettingsNotice(_("Patterns use only points 1–9.")); return end
                end
                local ok = self.appdock:setLockscreen(method, secret)
                UIManager:close(dialog)
                if not ok then self:showSettingsNotice(_("Use between 4 and 32 characters.")) end
                context.requestRebuild("ui")
            end },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function DAppManager:showLockscreenNameDialog(instance, context)
    local lockscreen = self.appdock.settings.lockscreen
    local dialog
    dialog = InputDialog:new{
        title = _("Lockscreen name"),
        description = _("Optional local display name. It is shown only on the AppDock lockscreen."),
        input_hint = _("Name (optional)"),
        input = lockscreen.profile_name or "",
        buttons = { {
            { text = _("Cancel"), callback = function() UIManager:close(dialog) end },
            { text = _("Save"), is_enter_default = true, callback = function()
                self.appdock:setLockscreenProfile(dialog:getInputText() or "", lockscreen.profile_image_path)
                UIManager:close(dialog)
                context.requestRebuild("ui")
            end },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function DAppManager:showLockscreenProfileImageDialog(instance, context)
    local lockscreen = self.appdock.settings.lockscreen
    local dialog
    dialog = InputDialog:new{
        title = _("Lockscreen profile image"),
        description = _("Optional local PNG, JPG, GIF, WEBP or SVG path. The image stays on this device and is not used as device security."),
        input_hint = _("Full local image path"),
        input = lockscreen.profile_image_path or "",
        buttons = { {
            { text = _("Clear image"), callback = function()
                self.appdock:setLockscreenProfile(lockscreen.profile_name, "")
                UIManager:close(dialog)
                context.requestRebuild("ui")
            end },
            { text = _("Use image"), is_enter_default = true, callback = function()
                local saved = self.appdock:setLockscreenProfile(lockscreen.profile_name, dialog:getInputText() or "")
                UIManager:close(dialog)
                if not saved then self:showSettingsNotice(_("Choose an existing local PNG, JPG, GIF, WEBP or SVG file.")) end
                context.requestRebuild("ui")
            end },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function DAppManager:showLockscreenEditor(instance, context)
    local lockscreen = self.appdock.settings.lockscreen
    local dialog
    dialog = ButtonDialog:new{
        title = _("AppDock lockscreen") .. "\n" .. _("This protects AppDock only, not device storage."),
        buttons = {
            { { text = (lockscreen.enabled and lockscreen.method == "swipe" and "✓ " or "") .. _("Swipe to unlock"), callback = function() self.appdock:setLockscreen("swipe"); UIManager:close(dialog); context.requestRebuild("ui") end } },
            { { text = (lockscreen.enabled and lockscreen.method == "pin" and "✓ " or "") .. _("PIN"), callback = function() UIManager:close(dialog); self:showLockscreenSecretDialog(instance, context, "pin") end } },
            { { text = (lockscreen.enabled and lockscreen.method == "pattern" and "✓ " or "") .. _("Pattern"), callback = function() UIManager:close(dialog); self:showLockscreenSecretDialog(instance, context, "pattern") end } },
            { { text = _("Name") .. ": " .. ((lockscreen.profile_name and lockscreen.profile_name ~= "") and lockscreen.profile_name or _("Not set")), callback = function() UIManager:close(dialog); self:showLockscreenNameDialog(instance, context) end } },
            { { text = lockscreen.profile_image_path and lockscreen.profile_image_path ~= "" and _("Change profile image") or _("Add profile image"), callback = function() UIManager:close(dialog); self:showLockscreenProfileImageDialog(instance, context) end } },
            { { text = _("Disable lockscreen"), callback = function() self.appdock:disableLockscreen(); UIManager:close(dialog); context.requestRebuild("ui") end } },
            { { text = _("Cancel"), callback = function() UIManager:close(dialog) end } },
        },
    }
    UIManager:show(dialog)
end

function DAppManager:showManualAppSpacingDialog(instance, context)
    if self.appdock.settings.beta.manual_app_spacing ~= true then
        self:showSettingsNotice(_("Enable manual app spacing in Beta features first."))
        return
    end
    local dialog
    dialog = InputDialog:new{
        title = _("Manual app spacing"),
        description = _("Choose a value from 8 to 34 pixels. This controls the distance between homescreen apps."),
        input_hint = _("8–34"), input_type = "number", input = tostring(self.appdock.settings.layout.app_spacing or 16),
        buttons = { {
            { text = _("Cancel"), callback = function() UIManager:close(dialog) end },
            { text = _("Save"), is_enter_default = true, callback = function()
                local value = tonumber(dialog:getInputText() or "")
                UIManager:close(dialog)
                if not value or value < 8 or value > 34 then
                    self:showSettingsNotice(_("Enter a whole number from 8 to 34."))
                    return
                end
                self.appdock:setLauncherLayout({ app_spacing = math.floor(value) })
                context.requestRebuild("ui")
            end },
        } },
    }
    UIManager:show(dialog); dialog:onShowKeyboard()
end

function DAppManager:showPluginLogoPathDialog(instance, context, app)
    local dialog
    dialog = InputDialog:new{
        title = _("Plugin logo") .. " · " .. app.title,
        description = _("Choose an existing local PNG, JPG, GIF, WEBP or SVG file. This logo is used only for this non-DApp plugin tile."),
        input_hint = _("Full local image path"), input = app.custom_logo_path or "",
        buttons = { {
            { text = _("Clear logo"), callback = function()
                self.appdock:setPluginLogo(app.id, nil)
                UIManager:close(dialog); context.requestRebuild("ui")
            end },
            { text = _("Use image"), is_enter_default = true, callback = function()
                local saved = self.appdock:setPluginLogo(app.id, dialog:getInputText() or "")
                UIManager:close(dialog)
                if not saved then self:showSettingsNotice(_("Choose an existing local PNG, JPG, GIF, WEBP or SVG file.")) end
                context.requestRebuild("ui")
            end },
        } },
    }
    UIManager:show(dialog); dialog:onShowKeyboard()
end

function DAppManager:showPluginLogoEditor(instance, context)
    if self.appdock.settings.beta.plugin_custom_logos ~= true then
        self:showSettingsNotice(_("Enable custom plugin logos in Beta features first."))
        return
    end
    local apps, buttons = self.appdock:getPluginApps(), {}
    local dialog
    for _, app in ipairs(apps) do
        buttons[#buttons + 1] = { { text = app.custom_logo_path and ("✓ " .. app.title) or app.title, callback = function()
            UIManager:close(dialog)
            self:showPluginLogoPathDialog(instance, context, app)
        end } }
    end
    if #buttons == 0 then
        self:showSettingsNotice(_("No compatible non-DApp plugin tiles are currently available."))
        return
    end
    buttons[#buttons + 1] = { { text = _("Cancel"), callback = function() UIManager:close(dialog) end } }
    dialog = ButtonDialog:new{ title = _("Custom plugin logos"), buttons = buttons, rows_per_page = { 4, 5, 6 } }
    UIManager:show(dialog)
end

function DAppManager:showBetaFeatures(instance, context)
    local beta = self.appdock.settings.beta
    local dialog
    local function toggle(key)
        self.appdock:setBetaOption(key, not beta[key])
        UIManager:close(dialog)
        context.requestRebuild("ui")
    end
    dialog = ButtonDialog:new{
        title = _("Beta features"),
        buttons = {
            { { text = (beta.plugin_dapp_host and "✓ " or "") .. _("Run plugin tiles in AppDock hosts (Beta · no split screen)"), callback = function() toggle("plugin_dapp_host") end } },
            { { text = (beta.manual_app_spacing and "✓ " or "") .. _("Manual app spacing"), callback = function() toggle("manual_app_spacing") end } },
            { { text = (beta.plugin_custom_logos and "✓ " or "") .. _("Custom logos for non-DApp plugins"), callback = function() toggle("plugin_custom_logos") end } },
            { { text = _("Cancel"), callback = function() UIManager:close(dialog) end } },
        },
    }
    UIManager:show(dialog)
end

function DAppManager:showControlCenterEditor(instance, context)
    local labels = {
        wifi = _("Wi-Fi"), night = _("Night mode"), refresh = _("Refresh"), edit = _("Edit apps"),
        sleep = _("Sleep"), power_saving = _("Save power"), wallpaper = _("Background image"),
    }
    local dialog
    local function show()
        local current = {}
        for _, tile_id in ipairs(self.appdock:getQuickSettingsTiles()) do current[tile_id] = true end
        local buttons = {}
        for _, tile_id in ipairs({ "wifi", "night", "refresh", "edit", "sleep", "power_saving", "wallpaper" }) do
            buttons[#buttons + 1] = { { text = (current[tile_id] and "✓ " or "") .. labels[tile_id], callback = function()
                self.appdock:setQuickTileEnabled(tile_id, not current[tile_id])
                UIManager:close(dialog)
                UIManager:nextTick(function() show() end)
                context.requestRebuild("ui")
            end } }
        end
        buttons[#buttons + 1] = { { text = _("Done"), callback = function() UIManager:close(dialog); context.requestRebuild("ui") end } }
        dialog = ButtonDialog:new{ title = _("Control center tiles"), buttons = buttons, rows_per_page = { 4, 5, 6 } }
        UIManager:show(dialog)
    end
    show()
end

function DAppManager:showDAppPermissions(instance, context)
    local eligible = {}
    for id, definition in pairs(self.definitions) do
        if definition.backgroundTick or definition.onAutostart then
            eligible[#eligible + 1] = { id = id, definition = definition }
        end
    end
    table.sort(eligible, function(left, right) return left.definition.title:lower() < right.definition.title:lower() end)
    if #eligible == 0 then
        self:showSettingsNotice(_("No installed DApp currently declares a background or autostart capability."))
        return
    end
    local dialog
    local function showEditor(entry)
        local permissions = self.appdock:getDAppPermissions(entry.id)
        local editor
        editor = ButtonDialog:new{
            title = entry.definition.title .. "\n" .. _("Permissions apply only while KOReader is running."),
            buttons = {
                { { text = (permissions.background and "✓ " or "") .. _("Run in background for notifications"), enabled = entry.definition.backgroundTick ~= nil, callback = function()
                    self.appdock:setDAppPermission(entry.id, "background", not permissions.background)
                    UIManager:close(editor); UIManager:nextTick(function() showEditor(entry) end); context.requestRebuild("ui")
                end } },
                { { text = (permissions.autostart and "✓ " or "") .. _("Start automatically"), enabled = entry.definition.onAutostart ~= nil, callback = function()
                    self.appdock:setDAppPermission(entry.id, "autostart", not permissions.autostart)
                    UIManager:close(editor); UIManager:nextTick(function() showEditor(entry) end); context.requestRebuild("ui")
                end } },
                { { text = _("Done"), callback = function() UIManager:close(editor) end } },
            },
        }
        UIManager:show(editor)
    end
    local buttons = {}
    for entry_index, entry in ipairs(eligible) do
        local permissions = self.appdock:getDAppPermissions(entry.id)
        local status = (permissions.background and _("background") or _("no background")) .. " · " .. (permissions.autostart and _("autostart") or _("manual"))
        buttons[#buttons + 1] = { { text = entry.definition.title .. " — " .. status, callback = function() UIManager:close(dialog); showEditor(entry) end } }
    end
    buttons[#buttons + 1] = { { text = _("Done"), callback = function() UIManager:close(dialog) end } }
    dialog = ButtonDialog:new{ title = _("DApp permissions"), buttons = buttons }
    UIManager:show(dialog)
end

function DAppManager:showCustomThemeNameDialog(instance, context)
    local dialog
    dialog = InputDialog:new{
        title = _("New AppDock theme"),
        input_hint = _("Theme name"),
        input = "",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function() UIManager:close(dialog) end,
                },
                {
                    text = _("Next"),
                    is_enter_default = true,
                    callback = function()
                        local title = dialog:getInputText()
                        UIManager:close(dialog)
                        self:showCustomThemeColorDialog(instance, context, title)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function DAppManager:showCustomThemeColorDialog(instance, context, title)
    local dialog
    dialog = InputDialog:new{
        title = _("Theme accent color"),
        description = _("Enter a six-digit color such as #4F8CC9."),
        input_hint = _("#RRGGBB"),
        input = "#4F8CC9",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function() UIManager:close(dialog) end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local id = self.appdock:createCustomTheme(title, dialog:getInputText())
                        UIManager:close(dialog)
                        if not id then
                            self:showSettingsNotice(_("Enter both a theme name and a valid six-digit color."))
                            return
                        end
                        context.requestRebuild("ui")
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function DAppManager:_buildClockPane(instance, context)
    local pane = WidgetContainer:new{
        dimen = Geom:new{ w = context.dimen.w, h = context.dimen.h },
    }
    local diameter = math.floor(math.min(context.dimen.w - scale(44), context.dimen.h * 0.67))
    local clock_x = math.floor((context.dimen.w - diameter) / 2)
    local clock_y = scale(24)
    local face = FrameContainer:new{
        width = diameter,
        height = diameter,
        padding = 0,
        bordersize = scale(2),
        radius = math.floor(diameter / 2),
        background = PALETTE.surface,
        color = PALETTE.outline,
        ClockFace:new{ dimen = Geom:new{ w = diameter, h = diameter } },
    }
    pane[1] = OverlapGroup:new{
        dimen = pane.dimen,
        allow_mirroring = false,
        face,
        TextWidget:new{
            text = os.date("%H:%M"),
            face = Font:getFace("cfont", scale(25)),
            fgcolor = PALETTE.on_surface,
            bold = true,
            overlap_offset = { math.floor((context.dimen.w - scale(85)) / 2), clock_y + diameter + scale(14) },
        },
        TextWidget:new{
            text = os.date("%A, %d %B"),
            face = Font:getFace("smallinfofont", scale(14)),
            fgcolor = PALETTE.on_variant,
            overlap_offset = { math.floor((context.dimen.w - scale(150)) / 2), clock_y + diameter + scale(47) },
        },
    }
    face.overlap_offset = { clock_x, clock_y }

    function pane:onDeactivate()
        if self._tick then UIManager:unschedule(self._tick) end
    end
    pane._tick = function()
        if context.manager.active_host == context.host then
            context.requestRebuild("fast")
        end
    end
    local seconds = tonumber(os.date("%S")) or 0
    UIManager:scheduleIn(math.max(1, 60 - seconds), pane._tick)
    return pane
end

function DAppManager:_buildHelpPane(instance, context)
    return self.help:buildPane(instance, context)
end

function DAppManager:_buildSettingsPane(instance, context)
    local pane = WidgetContainer:new{
        dimen = Geom:new{ w = context.dimen.w, h = context.dimen.h },
    }
    local width, height = context.dimen.w, context.dimen.h
    local margin, gap = scale(10), scale(4)
    local sidebar_width = math.min(scale(82), math.max(scale(68), math.floor(width * 0.18)))
    local content_x = margin + sidebar_width + gap
    local content_width = width - content_x - margin
    local row_height = math.max(scale(42), math.min(scale(50), math.floor((height - scale(64) - gap * 2) / 3)))
    local category_height
    local categories = {
        { id = "network", title = _("Network"), subtitle = _("Connections"), logo = "network" },
        { id = "display", title = _("Display"), subtitle = _("Light and theme"), logo = "display" },
        { id = "storage", title = _("Storage"), subtitle = _("Space usage"), logo = "archive" },
        { id = "simple", title = _("Simple Mode"), subtitle = _("Focus mode"), logo = "other" },
        { id = "other", title = _("Other"), subtitle = _("AppDock"), logo = "other" },
    }
    category_height = math.max(scale(40), math.min(scale(58), math.floor((height - 2 * margin - (#categories - 1) * gap) / #categories)))
    instance.settings_category = instance.settings_category or "network"
    local selected_id = instance.settings_category
    local wifi_on, wifi_available = self:_wifiState()
    local selected_theme_id, selected_theme = Theme.resolveDefinition(self.appdock.settings)
    local selected_theme_title = selected_theme.title or selected_theme_id
    local active_design = self.appdock:getActiveDesign()
    local night_mode = G_reader_settings:isTrue("night_mode")
    local wallpaper_settings = self.appdock.settings.wallpaper or { enabled = false, path = "" }
    local beta_settings = self.appdock.settings.beta or { black_borders = false, keep_wallpaper_original_in_night = false }
    local lockscreen_settings = self.appdock.settings.lockscreen or { enabled = false, method = "swipe" }
    local workspace_settings = self.appdock.settings.workspace or { restore_enabled = false, session = nil }
    local accessibility_settings = self.appdock.settings.accessibility or { text_scale = 1, high_contrast = false }
    local rows_by_category = {
        network = {
            {
                title = _("Wi-Fi"),
                subtitle = wifi_available and _("Internet connection") or _("Unavailable"),
                enabled = wifi_on,
                callback = function() self:toggleWifiFromSettings(context) end,
            },
        },
        display = {
            {
                title = _("Brightness & warmth"),
                subtitle = _("Open native light controls"),
                show_state = false,
                callback = function() self:showFrontlightSettings() end,
            },
            {
                title = _("Color themes"),
                subtitle = selected_theme_title .. " · " .. selected_theme.primary,
                show_state = false,
                callback = function() self:showThemeEditor(instance, context) end,
            },
            {
                title = _("Store design"),
                subtitle = active_design and (active_design.title .. " · " .. (active_design.button_style == "3d" and _("3D") or _("rounded"))) or _("Not active · browse AppStore designs"),
                show_state = false,
                callback = function() self:showStoreDesignEditor(instance, context) end,
            },
            {
                title = _("Launcher layout"),
                subtitle = string.format(_("%d px spacing · %s · search %s"), self.appdock.settings.layout.app_spacing, self.appdock.settings.layout.logo_shape == "circle" and _("circle") or _("rounded"), self.appdock.settings.layout.search_enabled and _("on") or _("off")),
                show_state = false,
                callback = function() self:showLauncherLayout(instance, context) end,
            },
            {
                title = _("Text & contrast"),
                subtitle = string.format(_("%d%% text · %s contrast"), math.floor((accessibility_settings.text_scale or 1) * 100 + .5), accessibility_settings.high_contrast and _("high") or _("standard")),
                show_state = false,
                callback = function() self:showAccessibilityEditor(instance, context) end,
            },
            {
                title = _("Background image"),
                subtitle = wallpaper_settings.enabled and _("Enabled · local file") or _("Disabled"),
                show_state = false,
                callback = function() self:showWallpaperEditor(instance, context) end,
            },
            {
                title = _("Black outlines"),
                subtitle = beta_settings.black_borders and _("Visible around AppDock controls") or _("Not shown"),
                enabled = beta_settings.black_borders,
                callback = function()
                    self.appdock:setBetaOption("black_borders", not beta_settings.black_borders)
                    context.requestRebuild("ui")
                end,
            },
            {
                title = _("Keep background image in night mode"),
                subtitle = beta_settings.keep_wallpaper_original_in_night and _("Original image is retained") or _("Standard night processing"),
                enabled = beta_settings.keep_wallpaper_original_in_night,
                callback = function()
                    self.appdock:setBetaOption("keep_wallpaper_original_in_night", not beta_settings.keep_wallpaper_original_in_night)
                    context.requestRebuild("ui")
                end,
            },
            {
                title = _("Custom plugin logos"),
                subtitle = beta_settings.plugin_custom_logos and _("Choose a local logo for a non-DApp plugin") or _("Enable in Beta features first"),
                show_state = false,
                callback = function() self:showPluginLogoEditor(instance, context) end,
            },
            {
                title = _("Beta features"),
                subtitle = (beta_settings.manual_app_spacing and _("manual spacing") or _("fixed spacing")) .. " · " .. (beta_settings.plugin_custom_logos and _("plugin logos") or _("standard logos")),
                show_state = false,
                callback = function() self:showBetaFeatures(instance, context) end,
            },
        },
        storage = {
            {
                title = _("Storage & integrity"),
                subtitle = _("Calculating local AppDock data"),
                show_state = false,
                callback = function() self:showIntegrityStatus() end,
            },
        },
        simple = {
            {
                title = _("Simple homescreen"),
                subtitle = _("Apps only · 4×3 grid"),
                enabled = self.appdock:isSimpleModeEnabled("homescreen"),
                callback = function()
                    self.appdock:setSimpleModeOption("homescreen", not self.appdock:isSimpleModeEnabled("homescreen"))
                    context.requestRebuild("ui")
                end,
            },
            {
                title = _("Simple quick settings"),
                subtitle = _("Wi-Fi, Night, Save power, brightness"),
                enabled = self.appdock:isSimpleModeEnabled("quick_settings"),
                callback = function()
                    self.appdock:setSimpleModeOption("quick_settings", not self.appdock:isSimpleModeEnabled("quick_settings"))
                    context.requestRebuild("ui")
                end,
            },
            {
                title = _("Quick find"),
                subtitle = _("Settings, files, reading, browser"),
                enabled = self.appdock:isSimpleModeEnabled("focus_apps"),
                callback = function()
                    self.appdock:setSimpleModeOption("focus_apps", not self.appdock:isSimpleModeEnabled("focus_apps"))
                    context.requestRebuild("ui")
                end,
            },
        },
        other = {
            {
                title = _("Lockscreen"),
                subtitle = lockscreen_settings.enabled and (lockscreen_settings.method == "pin" and _("PIN") or lockscreen_settings.method == "pattern" and _("Pattern") or _("Swipe")) or _("Disabled"),
                show_state = false,
                callback = function() self:showLockscreenEditor(instance, context) end,
            },
            {
                title = _("Control center"),
                subtitle = _("Choose quick setting tiles"),
                show_state = false,
                callback = function() self:showControlCenterEditor(instance, context) end,
            },
            {
                title = _("DApp permissions"),
                subtitle = _("Background and automatic start"),
                show_state = false,
                callback = function() self:showDAppPermissions(instance, context) end,
            },
            {
                title = _("Arrange apps & widgets"),
                subtitle = _("Order shown on the homescreen"),
                show_state = false,
                callback = function() self:showArrangementEditor(instance, context) end,
            },
            {
                title = _("About AppDock"),
                subtitle = _( "Version 6.0.4 · Continuity"),
                show_state = false,
                callback = function()
                    self:showSettingsNotice(_("AppDock 6.0.4 · Continuity\n\nThis maintenance update now reduces the actual visible heights and outer gaps of standard AppDock surfaces, not only internal text rhythm. Settings rows, Open Apps cards, Quick Settings tiles, Homescreen labels and cards, AppStore controls, Files rows and navigation are all visibly more compact while retaining safe unpadded glyph measurement. Simple Mode keeps its existing reduced appearance. Optional workspace restoration only resumes explicitly permitted local DApps. Files can use registered local DApp handlers, and Settings adds text size, contrast and read-only local integrity status."))
                end,
            },
            {
                title = _("UI language"),
                subtitle = (G_reader_settings:readSetting("language") == "de") and _("German · restart required") or _("English · restart required"),
                show_state = false,
                callback = function() self:showLanguageSelector(context) end,
            },
            {
                title = _("Open AppDock on startup"),
                subtitle = self.appdock.settings.launch_on_start and _("Enabled") or _("Disabled"),
                enabled = self.appdock.settings.launch_on_start,
                callback = function()
                    self.appdock:setLaunchOnStart(not self.appdock.settings.launch_on_start)
                    context.requestRebuild("ui")
                end,
            },
            {
                title = _("Local workspace"),
                subtitle = workspace_settings.restore_enabled and _("Restore permitted local apps") or _("Disabled · no session is restored"),
                enabled = workspace_settings.restore_enabled,
                callback = function() self:showWorkspaceEditor(instance, context) end,
            },
            {
                title = _("Refresh"),
                subtitle = _("Not implemented"),
                show_state = false,
                callback = function() self:showSettingsNotice(_("Refresh settings are not implemented yet.")) end,
            },
        },
    }
    if self:isKoboLibraColour() then
        table.insert(rows_by_category.network, {
            title = _("Bluetooth"),
            subtitle = self:_bluetoothPlugin() and _("Open installed Bluetooth plugin") or _("Install a compatible Bluetooth plugin"),
            show_state = false,
            callback = function() self:showBluetoothSettings() end,
        })
    end
    local selected_category = categories[1]
    for category_index, category in ipairs(categories) do
        if category.id == selected_id then selected_category = category; break end
    end
    local rows = rows_by_category[selected_category.id]
    row_height = math.max(scale(40), math.min(scale(50), math.floor((height - scale(64) - gap * math.max(0, #rows - 1)) / #rows)))
    local storage_segments, storage_total, storage_file_count, storage_dapps
    if selected_category.id == "storage" then
        local storage_ok
        storage_ok, storage_segments, storage_total, storage_file_count, storage_dapps = pcall(collectStorageSegments, self.appdock, self)
        if not storage_ok then
            storage_segments, storage_total, storage_file_count, storage_dapps = { { title = _("AppDock data scan unavailable"), bytes = 0 } }, 0, 0, {}
        end
        rows[1].subtitle = humanSize(storage_total) .. " · " .. tostring(storage_file_count) .. " files scanned"
    end
    local content = OverlapGroup:new{
        dimen = pane.dimen,
        allow_mirroring = false,
        FrameContainer:new{
            width = width, height = height, padding = 0, bordersize = 0,
            background = PALETTE.background,
            emptySizedWidget(width, height),
        },
        TextWidget:new{
            text = selected_category.title,
            face = Font:getFace("cfont", scale(20)),
            fgcolor = PALETTE.on_surface,
            bold = true,
            overlap_offset = { content_x, scale(10) },
        },
        TextWidget:new{
            text = selected_category.subtitle,
            face = Font:getFace("smallinfofont", scale(11)),
            fgcolor = PALETTE.on_variant,
            max_width = content_width,
            overlap_offset = { content_x, scale(32) },
        },
    }
    for category_index, category in ipairs(categories) do
        table.insert(content, SettingsCategory:new{
            title = category.title,
            logo = category.logo,
            selected = category.id == selected_category.id,
            width = sidebar_width,
            height = category_height,
            callback = function()
                instance.settings_category = category.id
                context.requestRebuild("ui")
            end,
            overlap_offset = { margin, margin + (category_index - 1) * (category_height + gap) },
        })
    end
    for row_index, row in ipairs(rows) do
        table.insert(content, SettingsRow:new{
            title = row.title,
            subtitle = row.subtitle,
            enabled = row.enabled or false,
            show_state = row.show_state ~= false,
            width = content_width,
            height = row_height,
            callback = row.callback,
            overlap_offset = { content_x, scale(56) + (row_index - 1) * (row_height + gap) },
        })
    end
    if selected_category.id == "storage" then
        table.insert(content, StorageSummary:new{
            width = content_width,
            height = scale(180),
            segments = storage_segments,
            overlap_offset = { content_x, scale(128) },
        })
        table.insert(content, StorageDApps:new{
            width = content_width,
            height = scale(220),
            entries = storage_dapps,
            overlap_offset = { content_x, scale(320) },
        })
    end
    pane.settings_layout = {
        category = selected_category.id,
        sidebar_width = sidebar_width,
        content_x = content_x,
        content_width = content_width,
        category_height = category_height,
        row_height = row_height,
        row_count = #rows,
        text_scale = accessibility_settings.text_scale or 1,
        high_contrast = accessibility_settings.high_contrast == true,
        workspace_enabled = workspace_settings.restore_enabled == true,
        integrity = selected_category.id == "storage" and self:getIntegrityStatus() or nil,
    }
    pane[1] = content
    return pane
end

function DAppHost:init()
    self.dimen = Screen:getSize()
    self.split_ratio = self:_initialSplitRatio()
    self.ges_events = {
        PanSplitHost = { GestureRange:new{ ges = "pan", range = function() return self._split_touch_range end } },
        PanReleaseSplitHost = { GestureRange:new{ ges = "pan_release", range = function() return self._split_touch_range end } },
    }
    if Device:hasKeys() then self.key_events.Close = { { Device.input.group.Back } } end
    self:rebuild()
end

function DAppHost:_initialSplitRatio()
    local settings = self.manager and self.manager.appdock and self.manager.appdock.settings or {}
    local layout = settings.layout or {}
    local ratio = tonumber(layout.split_ratio) or .5
    return math.max(.20, math.min(.80, ratio))
end

function DAppHost:setSplitFromGesture(position_y, persist)
    if not self.split or not self._split_content_top or not self._split_available or self._split_available <= 0 then return false end
    local ratio = (tonumber(position_y) - self._split_content_top) / self._split_available
    ratio = math.max(.20, math.min(.80, ratio))
    local changed = math.abs((self.split_ratio or .5) - ratio) >= .003
    self.split_ratio = ratio
    if persist then
        local appdock = self.manager and self.manager.appdock
        if appdock and appdock.settings then
            appdock.settings.layout = appdock.settings.layout or {}
            appdock.settings.layout.split_ratio = ratio
            if appdock._saveSettings then appdock:_saveSettings() end
        end
    end
    if changed or persist then
        self:rebuild(true)
        UIManager:setDirty(self, persist and "ui" or "fast")
        if not persist and UIManager.forceRePaint then UIManager:forceRePaint() end
        if not persist and UIManager.yieldToEPDC then UIManager:yieldToEPDC() end
    end
    return true
end

function DAppHost:_moveSplitFromGesture(arg, gesture_event, persist)
    local position = gesture_event and gesture_event.pos
    local y = position and position.y or self._split_last_y
    if not y then return false end
    self._split_last_y = y
    return self:setSplitFromGesture(y, persist)
end

function DAppHost:onPanSplitHost(arg, gesture_event)
    return self:_moveSplitFromGesture(arg, gesture_event, false)
end

function DAppHost:onPanReleaseSplitHost(arg, gesture_event)
    return self:_moveSplitFromGesture(arg, gesture_event, true)
end

function DAppHost:rebuild(preserve_active)
    applyTheme(self.manager.appdock)
    local width, height = self.dimen.w, self.dimen.h
    local expressive = type(self.manager.appdock.isExpressiveUiEnabled) == "function" and self.manager.appdock:isExpressiveUiEnabled()
    local appbar_height = expressive and scale(58) or scale(52)
    local navigation_height = expressive and scale(58) or scale(50)
    local content_top, content_bottom = appbar_height, height - navigation_height
    local ids = self.dapp_ids or { self.dapp_id }
    self.dapp_ids = ids
    if not preserve_active then
        for _, pane in ipairs(self.active_panes or {}) do
            if pane.onDeactivate then pane:onDeactivate() end
        end
    end
    self.active_panes = {}
    local pane_regions
    if self.split and #ids == 2 then
        local divider = scale(8)
        local available = math.max(1, content_bottom - content_top - divider)
        local minimum_height = math.min(math.max(scale(84), math.floor(available * .20)), math.floor(available / 2))
        local ratio = math.max(.20, math.min(.80, self.split_ratio or self:_initialSplitRatio()))
        local first_height = math.floor(available * ratio + .5)
        first_height = math.max(minimum_height, math.min(available - minimum_height, first_height))
        self.split_ratio = first_height / available
        self._split_content_top, self._split_available = content_top, available
        pane_regions = {
            Geom:new{ x = 0, y = content_top, w = width, h = first_height },
            Geom:new{ x = 0, y = content_top + first_height + divider, w = width, h = available - first_height },
        }
    else
        self.split = false
        self._split_content_top, self._split_available = nil, nil
        pane_regions = { Geom:new{ x = 0, y = content_top, w = width, h = math.max(1, content_bottom - content_top) } }
    end

    local title = self.split and _("Split screen") or self.manager.instances[ids[1]].definition.title
    local host_title = TextWidget:new{
        text = title,
        face = Font:getFace("smallinfofont", expressive and Theme.adjustText(self.manager.appdock, scale(17), scale(11)) or scale(17)),
        fgcolor = PALETTE.on_surface,
        bold = true,
        max_width = width - scale(100),
        padding = 0,
    }
    local host_title_y = math.max(scale(2), math.floor((appbar_height - host_title:getSize().h) / 2))
    host_title.overlap_offset = { expressive and scale(28) or scale(18), host_title_y }
    local quick_action = ActionChip:new{
        title = "", symbol = "⌄", width = scale(34), height = scale(34),
        background = expressive and PALETTE.primary or PALETTE.surface_variant,
        foreground = expressive and PALETTE.on_primary or PALETTE.on_variant,
        callback = function() self.manager:showQuickSettingsFromHost(self) end,
        overlap_offset = { width - (expressive and scale(52) or scale(46)), math.max(scale(4), math.floor((appbar_height - scale(34)) / 2)) },
    }
    local chrome = OverlapGroup:new{
        dimen = Geom:new{ w = width, h = height },
        allow_mirroring = false,
        FrameContainer:new{
            width = width, height = height, padding = 0, bordersize = 0,
            background = PALETTE.background,
            emptySizedWidget(width, height),
        },
        FrameContainer:new{
            width = width, height = appbar_height, padding = 0, bordersize = 0,
            background = PALETTE.surface,
            emptySizedWidget(width, appbar_height),
        },
        host_title,
        quick_action,
    }
    if expressive then
        table.insert(chrome, FrameContainer:new{
            width = width - scale(36), height = scale(42), padding = 0, bordersize = 0,
            radius = scale(21), background = PALETTE.surface_variant,
            emptySizedWidget(width - scale(36), scale(42)), overlap_offset = { scale(18), scale(8) },
        })
        table.remove(chrome, 3)
        table.remove(chrome, 3)
        table.insert(chrome, host_title)
        table.insert(chrome, quick_action)
    end

    for index, id in ipairs(ids) do
        local instance = self.manager:_instanceFor(id)
        local region = pane_regions[index]
        local context = self.manager:_newContext(self, instance, region)
        if instance.workspace_state ~= nil and instance.definition.restoreState and not instance._workspace_state_applied then
            pcall(instance.definition.restoreState, instance, instance.workspace_state, context)
            instance._workspace_state_applied = true
            instance.workspace_state = nil
        end
        local pane = instance.definition.buildPane(instance, context)
        instance.pane = pane
        instance.visible = true
        instance.in_split = self.split
        pane.overlap_offset = { region.x, region.y }
        table.insert(self.active_panes, pane)
        table.insert(chrome, pane)
        if instance.definition.host_kind == "plugin" then
            local overlay = self.manager:_buildPluginHostOverlay(instance, context)
            if overlay then
                overlay.overlap_offset = { region.x, region.y }
                table.insert(chrome, overlay)
            end
        end
    end
    self.active_pane = self.active_panes[1]

    self._split_touch_range = nil
    if self.split then
        local divider_y = pane_regions[2].y - scale(3)
        local touch_padding = math.max(scale(18), scale(8))
        self._split_touch_range = Geom:new{
            x = 0, y = math.max(0, divider_y - touch_padding),
            w = width, h = scale(8) + 2 * touch_padding,
        }
        table.insert(chrome, SplitDivider:new{
            width = width, height = scale(8),
            overlap_offset = { 0, divider_y },
        })
    end

    local chip_size, chip_gap = expressive and scale(38) or scale(34), expressive and scale(12) or scale(11)
    local navigation_height = expressive and scale(58) or scale(50)
    local navigation_y = height - navigation_height
    local navigation_width = chip_size * 3 + chip_gap * 2
    local navigation_x = math.floor((width - navigation_width) / 2)
    local chip_y = navigation_y + math.floor((navigation_height - chip_size) / 2)
    table.insert(chrome, FrameContainer:new{
        width = width, height = navigation_height, padding = 0, bordersize = 0,
        background = PALETTE.surface,
        emptySizedWidget(width, navigation_height),
        overlap_offset = { 0, navigation_y },
    })
    if expressive then
        table.insert(chrome, FrameContainer:new{
            width = navigation_width + scale(20), height = chip_size + scale(10), padding = 0, bordersize = 0,
            radius = math.floor((chip_size + scale(10)) / 2), background = PALETTE.surface_variant,
            emptySizedWidget(navigation_width + scale(20), chip_size + scale(10)),
            overlap_offset = { navigation_x - scale(10), navigation_y + math.floor((navigation_height - chip_size - scale(10)) / 2) },
        })
    end
    table.insert(chrome, ActionChip:new{
        title = "", symbol = "⌂", width = chip_size, height = chip_size,
        callback = function() self.manager:showHomeFromHost(self) end,
        overlap_offset = { navigation_x, chip_y },
    })
    table.insert(chrome, ActionChip:new{
        title = "", symbol = "□", width = chip_size, height = chip_size,
        callback = function() self.manager:showRecentsFromHost(self) end,
        overlap_offset = { navigation_x + chip_size + chip_gap, chip_y },
    })
    table.insert(chrome, ActionChip:new{
        title = "", symbol = "×", width = chip_size, height = chip_size,
        callback = function()
            if self.split then
                self.manager:showRecentsFromHost(self)
            else
                self.manager:closeDApp(ids[1])
                UIManager:nextTick(function() self.manager.appdock:showHome(true) end)
            end
        end,
        overlap_offset = { navigation_x + 2 * (chip_size + chip_gap), chip_y },
    })
    self.chrome_layout = {
        expressive = expressive,
        appbar_height = appbar_height,
        navigation_height = navigation_height,
        has_navigation_pill = expressive,
    }
    self:clear()
    self[1] = chrome
end

function DAppHost:onCloseWidget()
    self.manager:detachHost(self)
    UIManager:setDirty("all", "ui")
end

function DAppHost:onClose()
    UIManager:close(self)
    return true
end

function DAppRecents:init()
    self.dimen = Screen:getSize()
    if Device:hasKeys() then self.key_events.Close = { { Device.input.group.Back } } end
    self:build()
end

function DAppRecents:build()
    local width, height = self.dimen.w, self.dimen.h
    local expressive = type(self.manager.appdock.isExpressiveUiEnabled) == "function" and self.manager.appdock:isExpressiveUiEnabled()
    local margin = expressive and scale(14) or scale(18)
    local card_width = width - 2 * margin
    local card_height = expressive and scale(64) or scale(60)
    local gap = expressive and scale(6) or scale(6)
    local heading_title = TextWidget:new{
        text = _("Open apps"),
        face = Font:getFace("cfont", expressive and Theme.adjustText(self.manager.appdock, scale(23), scale(16)) or scale(25)),
        fgcolor = PALETTE.on_surface,
        bold = true,
        padding = 0,
        padding = 0,
    }
    local heading_subtitle = TextWidget:new{
        text = _("Hold an app to start split screen"),
        face = Font:getFace("smallinfofont", expressive and scale(11) or scale(12)),
        fgcolor = PALETTE.on_variant,
        max_width = card_width,
        padding = 0,
    }
    local header_height = math.max(expressive and scale(56) or scale(54), heading_title:getSize().h + heading_subtitle:getSize().h + scale(8))
    local header_positions = Theme.centeredStack(header_height, { heading_title, heading_subtitle }, scale(4), scale(5))
    heading_title.overlap_offset = { expressive and margin + scale(14) or margin, header_positions[1] }
    heading_subtitle.overlap_offset = { margin, header_positions[2] }
    local content = OverlapGroup:new{
        dimen = Geom:new{ w = width, h = height },
        allow_mirroring = false,
        FrameContainer:new{
            width = width, height = height, padding = 0, bordersize = 0,
            background = PALETTE.background,
            emptySizedWidget(width, height),
        },
    }
    if expressive then
        table.insert(content, FrameContainer:new{
            width = width - 2 * margin, height = header_height - scale(6), padding = 0, bordersize = 0,
            radius = math.floor((header_height - scale(6)) / 2), background = PALETTE.surface,
            emptySizedWidget(width - 2 * margin, header_height - scale(6)), overlap_offset = { margin, scale(3) },
        })
    end
    table.insert(content, heading_title)
    table.insert(content, heading_subtitle)
    local open_apps = self.manager:getOpenApps()
    if #open_apps == 0 then
        table.insert(content, TextWidget:new{
            text = _("No DApps are open yet."),
            face = Font:getFace("smallinfofont", scale(16)),
            fgcolor = PALETTE.on_variant,
            overlap_offset = { margin, header_height + gap },
        })
    end
    for index, app in ipairs(open_apps) do
        local y = header_height + gap + (index - 1) * (card_height + gap)
        table.insert(content, ActionChip:new{
            title = app.title,
            symbol = app.symbol,
            logo = app.logo,
            width = card_width, height = card_height,
            background = expressive and (index % 2 == 0 and PALETTE.secondary or PALETTE.surface) or PALETTE.surface,
            foreground = PALETTE.on_surface,
            callback = function()
                UIManager:close(self)
                UIManager:nextTick(function() self.manager:activate(app.id) end)
            end,
            hold_callback = function()
                self.manager:showDAppActions(app.id, self)
            end,
            overlap_offset = { margin, y },
        })
        table.insert(content, ActionChip:new{
            title = "", symbol = "×", width = scale(30), height = scale(30),
            background = PALETTE.surface_variant, foreground = PALETTE.on_variant,
            callback = function()
                self.manager:closeDApp(app.id)
                self:build()
                UIManager:setDirty(self, "ui")
            end,
            overlap_offset = { width - margin - scale(38), y + math.floor((card_height - scale(30)) / 2) },
        })
    end
    table.insert(content, ActionChip:new{
        title = "", symbol = "⌂", width = scale(72), height = scale(44),
        background = PALETTE.primary, foreground = PALETTE.on_primary,
        callback = function()
            UIManager:close(self)
            UIManager:nextTick(function() self.manager.appdock:showHome(true) end)
        end,
        overlap_offset = { margin, height - (expressive and scale(56) or scale(54)) },
    })
    self:clear()
    self[1] = content
end

function DAppRecents:onClose()
    UIManager:close(self)
    UIManager:nextTick(function() self.manager.appdock:showHome(true) end)
    return true
end

return DAppManager
