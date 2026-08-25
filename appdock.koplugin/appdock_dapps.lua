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

local DAppManager = {}
DAppManager.__index = DAppManager

local DAppHost = InputContainer:extend{
    manager = nil,
    dapp_id = nil,
    dapp_ids = nil,
    split = false,
    active_pane = nil,
    active_panes = nil,
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

local HELP_HTML = [[
<h1>AppDock Hilfe</h1>
<p>AppDock ist dein anpassbarer KOReader-Homescreen. Alle Funktionen bleiben innerhalb von KOReader und sind für E-Ink optimiert.</p>
<h2>Homescreen</h2>
<p>Tippe eine Kachel an, um eine App zu starten. Halte eine Kachel gedrückt, um Apps und Widgets zu verwalten. Die Systemzeile öffnet über den Abwärtspfeil die Schnellzugriffe.</p>
<h2>Schnellzugriff</h2>
<p>Hier findest du Helligkeit, WLAN, Nachtmodus, manuelle Aktualisierung und den AppDock-Editor. Der Helligkeitsregler nutzt schnelle regionale E-Ink-Updates; zusätzlich aktualisiert AppDock den Bildschirm alle 60 Sekunden vollständig.</p>
<h2>DApps und Open apps</h2>
<p>DApps bleiben nach dem Verlassen logisch geöffnet. In Open apps kannst du sie wiederherstellen oder schließen. Analog Clock, Settings, File Manager, Web Browser und diese Hilfe-DApp gehören dazu.</p>
<h2>Splitscreen</h2>
<p>Öffne zwei DApps. Halte in Open apps eine App gedrückt, wähle Splitscreen und danach die zweite offene App. Beide laufen in getrennten Flächen mit gemeinsamer Systemleiste.</p>
<h2>Web Browser</h2>
<p>Der Browser zeigt serverseitig bereitgestellte Webseiten. Address öffnet HTTP- oder HTTPS-Adressen, Search nutzt DuckDuckGo HTML. JavaScript, Formulare, Downloads und eingebettete Medien bleiben bewusst deaktiviert.</p>
<h2>Hinweis</h2>
<p>Für die beste E-Ink-Darstellung verwende kurze Interaktionen und lasse die periodische Aktualisierung aktiv. Diese Hilfe ist offline verfügbar und funktioniert auch im Splitscreen.</p>
]]

local HELP_CSS = [[
body { font-family: sans-serif; line-height: 1.38; color: #202020; background: #ffffff; }
h1 { font-size: 1.5em; margin: 0.45em 0 0.45em; }
h2 { font-size: 1.16em; margin: 0.9em 0 0.25em; }
p { margin: 0.25em 0 0.5em; }
]]

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
    local palette = Theme.getPalette(appdock)
    PALETTE.background = palette.background
    PALETTE.surface = palette.surface
    PALETTE.surface_variant = palette.surface_variant
    PALETTE.primary = palette.primary
    PALETTE.on_primary = palette.on_primary
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
    local ok, iterator = pcall(lfs.dir, path)
    if not ok then return nil end
    return iterator
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
    local iterator = safeDirectory(path)
    if not iterator then return 0 end
    for name in iterator do
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
    local iterator = safeDirectory(data_dir)
    if iterator then
        for name in iterator do
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
        local label = segment.title .. "  " .. humanSize(segment.bytes)
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
    local title = TextWidget:new{ text = _("DApp storage usage"), face = Font:getFace("cfont", scale(15)), fgcolor = PALETTE.on_surface, bold = true, max_width = self.width }
    title:paintTo(bb, x, y)
    if #entries == 0 then
        TextWidget:new{ text = _("No installed DApps found"), face = Font:getFace("smallinfofont", scale(11)), fgcolor = PALETTE.on_variant, max_width = self.width }:paintTo(bb, x, y + scale(25))
        return
    end
    local max_bytes = math.max(1, entries[1].bytes)
    for index, entry in ipairs(entries) do
        if index > 6 then break end
        local row_y = y + scale(25) + (index - 1) * scale(29)
        local label = string.format("%s  ·  %s", entry.title, humanSize(entry.bytes))
        TextWidget:new{ text = label, face = Font:getFace("smallinfofont", scale(11)), fgcolor = PALETTE.on_surface, max_width = self.width }:paintTo(bb, x, row_y)
        bb:paintRect(x, row_y + scale(18), math.max(scale(3), math.floor((self.width - scale(8)) * entry.bytes / max_bytes)), scale(4), PALETTE.primary)
    end
end

function ActionChip:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local icon = self.logo and DAppLogo:new{
        kind = self.logo,
        size = scale(24),
        ink = self.foreground or PALETTE.on_surface,
    } or TextWidget:new{
        text = self.symbol or "",
        face = Font:getFace("cfont", scale(20)),
        fgcolor = self.foreground or PALETTE.on_surface,
        bold = true,
    }
    self[1] = FrameContainer:new{
        width = self.width,
        height = self.height,
        padding = 0,
        bordersize = 0,
        radius = math.floor(self.height * 0.36),
        background = self.background or PALETTE.surface_variant,
        CenterContainer:new{
            dimen = Geom:new{ w = self.width, h = self.height },
            VerticalGroup:new{
                icon,
                VerticalSpan:new{ width = scale(2) },
                TextWidget:new{
                    text = self.title or "",
                    face = Font:getFace("smallinfofont", scale(12)),
                    fgcolor = self.foreground or PALETTE.on_surface,
                    max_width = self.width - scale(12),
                },
            },
        },
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

function SettingsCategory:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local background = self.selected and PALETTE.primary or PALETTE.surface
    local foreground = self.selected and PALETTE.on_primary or PALETTE.on_surface
    self[1] = FrameContainer:new{
        width = self.width,
        height = self.height,
        padding = 0,
        bordersize = 0,
        radius = scale(13),
        background = background,
        CenterContainer:new{
            dimen = Geom:new{ w = self.width, h = self.height },
            VerticalGroup:new{
                DAppLogo:new{ kind = self.logo, size = scale(20), ink = foreground },
                VerticalSpan:new{ width = scale(2) },
                TextWidget:new{
                    text = self.title or "",
                    face = Font:getFace("smallinfofont", scale(9)),
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
    self[1] = FrameContainer:new{
        width = self.width,
        height = self.height,
        padding = 0,
        bordersize = 0,
        radius = math.floor(self.height * 0.28),
        background = self.enabled and PALETTE.primary or PALETTE.surface,
        CenterContainer:new{
            dimen = Geom:new{ w = self.width, h = self.height },
            VerticalGroup:new{
                TextWidget:new{
                    text = self.title,
                    face = Font:getFace("smallinfofont", scale(15)),
                    fgcolor = self.enabled and PALETTE.on_primary or PALETTE.on_surface,
                    bold = true,
                    max_width = self.width - scale(26),
                },
                VerticalSpan:new{ width = scale(3) },
                TextWidget:new{
                    text = detail,
                    face = Font:getFace("smallinfofont", scale(12)),
                    fgcolor = self.enabled and PALETTE.on_primary or PALETTE.on_variant,
                    max_width = self.width - scale(26),
                },
            },
        },
    }
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
        widget_definitions = {},
        widget_instances = {},
        browser = WebBrowser:new(),
        file_browser = FileBrowser:new(),
        app_store = AppStore:new(),
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
    table.sort(widgets, function(left, right) return left.title:lower() < right.title:lower() end)
    return widgets
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
    local definition = self.definitions[id]
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
            table.insert(apps, {
                id = id,
                title = instance.definition.title,
                subtitle = instance.in_split and _("In split screen") or (instance.visible and _("Active") or _("Open")),
                symbol = instance.definition.symbol,
                logo = instance.definition.logo,
                last_active = instance.last_active,
            })
        end
    end
    return apps
end

function DAppManager:_newContext(host, instance, assigned_dimen)
    local width, height = host.dimen.w, host.dimen.h
    local appbar_height = scale(52)
    assigned_dimen = assigned_dimen or Geom:new{ x = 0, y = appbar_height, w = width, h = height - appbar_height }
    return {
        manager = self,
        instance = instance,
        host = host,
        -- Single and split hosts both hand out an explicit local pane rectangle.
        dimen = assigned_dimen,
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
    }
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
    local candidates = {}
    for _, app in ipairs(self:getOpenApps()) do
        if app.id ~= first_id then table.insert(candidates, app) end
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
    if self.active_host then UIManager:close(self.active_host) end

    local now = os.time()
    self.active_id = nil
    for _, instance in ipairs({ first, second }) do
        instance.last_active = now
        instance.visible = true
        instance.in_split = true
        self:_touchOpen(instance.id)
    end
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
end

function DAppManager:closeDApp(id)
    local instance = self.instances[id]
    if not instance then return end
    if self.active_id == id and self.active_host then
        UIManager:close(self.active_host)
    end
    for index, open_id in ipairs(self.open_order) do
        if open_id == id then table.remove(self.open_order, index); break end
    end
    self.instances[id] = nil
    if self.active_id == id then self.active_id = nil end
end

function DAppManager:showRecents(home)
    if home then UIManager:close(home) end
    if self.active_host then UIManager:close(self.active_host) end
    UIManager:show(DAppRecents:new{ manager = self })
end

function DAppManager:showHomeFromHost(host)
    UIManager:close(host)
    UIManager:nextTick(function() self.appdock:showHome() end)
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
            { { text = layout.search_enabled and _("Disable app search") or _("Enable app search (Beta)"), callback = function() choose({ search_enabled = not layout.search_enabled }) end } },
            { { text = _("Cancel"), callback = function() UIManager:close(dialog) end } },
        },
    }
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
    local pane = WidgetContainer:new{
        dimen = Geom:new{ w = context.dimen.w, h = context.dimen.h },
    }
    local margin = scale(14)
    local scroll = ScrollHtmlWidget:new{
        html_body = HELP_HTML,
        css = HELP_CSS,
        width = context.dimen.w - 2 * margin,
        height = context.dimen.h - 2 * margin,
        default_font_size = scale(16),
        dialog = context.host,
    }
    scroll.overlap_offset = { margin, margin }
    pane[1] = OverlapGroup:new{
        dimen = pane.dimen,
        allow_mirroring = false,
        FrameContainer:new{
            width = pane.dimen.w, height = pane.dimen.h, padding = 0, bordersize = 0,
            background = PALETTE.background,
            emptySizedWidget(pane.dimen.w, pane.dimen.h),
        },
        scroll,
    }
    return pane
end

function DAppManager:_buildSettingsPane(instance, context)
    local pane = WidgetContainer:new{
        dimen = Geom:new{ w = context.dimen.w, h = context.dimen.h },
    }
    local width, height = context.dimen.w, context.dimen.h
    local margin, gap = scale(12), scale(8)
    local sidebar_width = math.min(scale(82), math.max(scale(68), math.floor(width * 0.18)))
    local content_x = margin + sidebar_width + gap
    local content_width = width - content_x - margin
    local row_height = math.max(scale(52), math.min(scale(62), math.floor((height - scale(78) - gap * 2) / 3)))
    local category_height = math.min(scale(70), math.floor((height - 2 * margin - 3 * gap) / 4))
    local categories = {
        { id = "network", title = _("Network"), subtitle = _("Connections"), logo = "network" },
        { id = "display", title = _("Display"), subtitle = _("Light and theme"), logo = "display" },
        { id = "storage", title = _("Storage"), subtitle = _("Space usage"), logo = "archive" },
        { id = "other", title = _("Other"), subtitle = _("AppDock"), logo = "other" },
    }
    instance.settings_category = instance.settings_category or "network"
    local selected_id = instance.settings_category
    local wifi_on, wifi_available = self:_wifiState()
    local selected_theme_id, selected_theme = Theme.resolveDefinition(self.appdock.settings)
    local selected_theme_title = selected_theme.title or selected_theme_id
    local night_mode = G_reader_settings:isTrue("night_mode")
    local rows_by_category = {
        network = {
            {
                title = _("Wi-Fi"),
                subtitle = wifi_available and _("Internet connection") or _("Unavailable"),
                enabled = wifi_on,
                callback = function() self:toggleWifiFromSettings(context) end,
            },
            {
                title = _("Bluetooth"),
                subtitle = _("Not available in KOReader"),
                show_state = false,
                callback = function() self:showSettingsNotice(_("Bluetooth settings are not available in KOReader yet.")) end,
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
                title = _("Launcher layout"),
                subtitle = string.format(_("%d px spacing · %s · search %s"), self.appdock.settings.layout.app_spacing, self.appdock.settings.layout.logo_shape == "circle" and _("circle") or _("rounded"), self.appdock.settings.layout.search_enabled and _("on") or _("off")),
                show_state = false,
                callback = function() self:showLauncherLayout(instance, context) end,
            },
        },
        storage = {
            {
                title = _("Storage usage"),
                subtitle = _("Calculating local AppDock data"),
                show_state = false,
            },
        },
        other = {
            {
                title = _("Layout"),
                subtitle = _("Apps, widgets and home screen"),
                show_state = false,
                callback = function() self:openManagerFromHost(context.host) end,
            },
            {
                title = _("About AppDock"),
                subtitle = _("Version 2.0.1 and help"),
                show_state = false,
                callback = function()
                    self:showSettingsNotice(_("AppDock 2.0.1\n\nStable release: launcher layout controls, optional app search, storage overview, custom themes and AppStore."))
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
                title = _("Refresh"),
                subtitle = _("Not implemented"),
                show_state = false,
                callback = function() self:showSettingsNotice(_("Refresh settings are not implemented yet.")) end,
            },
        },
    }
    local selected_category = categories[1]
    for category_index, category in ipairs(categories) do
        if category.id == selected_id then selected_category = category; break end
    end
    local rows = rows_by_category[selected_category.id]
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
            overlap_offset = { content_x, scale(14) },
        },
        TextWidget:new{
            text = selected_category.subtitle,
            face = Font:getFace("smallinfofont", scale(11)),
            fgcolor = PALETTE.on_variant,
            max_width = content_width,
            overlap_offset = { content_x, scale(41) },
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
            overlap_offset = { content_x, scale(64) + (row_index - 1) * (row_height + gap) },
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
    }
    pane[1] = content
    return pane
end

function DAppHost:init()
    self.dimen = Screen:getSize()
    if Device:hasKeys() then self.key_events.Close = { { Device.input.group.Back } } end
    self:rebuild()
end

function DAppHost:rebuild()
    applyTheme(self.manager.appdock)
    local width, height = self.dimen.w, self.dimen.h
    local appbar_height = scale(52)
    local ids = self.dapp_ids or { self.dapp_id }
    self.dapp_ids = ids

    for _, pane in ipairs(self.active_panes or {}) do
        if pane.onDeactivate then pane:onDeactivate() end
    end
    self.active_panes = {}

    local pane_regions
    if self.split and #ids == 2 then
        local divider = scale(3)
        local available = height - appbar_height - divider
        local first_height = math.floor(available / 2)
        pane_regions = {
            Geom:new{ x = 0, y = appbar_height, w = width, h = first_height },
            Geom:new{ x = 0, y = appbar_height + first_height + divider, w = width, h = available - first_height },
        }
    else
        self.split = false
        pane_regions = { Geom:new{ x = 0, y = appbar_height, w = width, h = height - appbar_height } }
    end

    local title = self.split and _("Split screen") or self.manager.instances[ids[1]].definition.title
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
        TextWidget:new{
            text = title,
            face = Font:getFace("smallinfofont", scale(17)),
            fgcolor = PALETTE.on_surface,
            bold = true,
            overlap_offset = { scale(18), scale(17) },
        },
    }

    for index, id in ipairs(ids) do
        local instance = self.manager:_instanceFor(id)
        local region = pane_regions[index]
        local context = self.manager:_newContext(self, instance, region)
        local pane = instance.definition.buildPane(instance, context)
        instance.pane = pane
        instance.visible = true
        instance.in_split = self.split
        pane.overlap_offset = { region.x, region.y }
        table.insert(self.active_panes, pane)
        table.insert(chrome, pane)
    end
    self.active_pane = self.active_panes[1]

    if self.split then
        table.insert(chrome, FrameContainer:new{
            width = width, height = scale(3), padding = 0, bordersize = 0,
            background = PALETTE.outline,
            emptySizedWidget(width, scale(3)),
            overlap_offset = { 0, pane_regions[2].y - scale(3) },
        })
    end

    local chip_size = scale(34)
    table.insert(chrome, ActionChip:new{
        title = "", symbol = "⌂", width = chip_size, height = chip_size,
        callback = function() self.manager:showHomeFromHost(self) end,
        overlap_offset = { width - scale(18) - chip_size * 3 - scale(12), scale(9) },
    })
    table.insert(chrome, ActionChip:new{
        title = "", symbol = "□", width = chip_size, height = chip_size,
        callback = function() self.manager:showRecentsFromHost(self) end,
        overlap_offset = { width - scale(18) - chip_size * 2 - scale(6), scale(9) },
    })
    table.insert(chrome, ActionChip:new{
        title = "", symbol = "×", width = chip_size, height = chip_size,
        callback = function()
            if self.split then
                self.manager:showRecentsFromHost(self)
            else
                self.manager:closeDApp(ids[1])
                UIManager:nextTick(function() self.manager.appdock:showHome() end)
            end
        end,
        overlap_offset = { width - scale(18) - chip_size, scale(9) },
    })
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
    local margin = scale(22)
    local card_width = width - 2 * margin
    local card_height = scale(76)
    local gap = scale(12)
    local content = OverlapGroup:new{
        dimen = Geom:new{ w = width, h = height },
        allow_mirroring = false,
        FrameContainer:new{
            width = width, height = height, padding = 0, bordersize = 0,
            background = PALETTE.background,
            emptySizedWidget(width, height),
        },
        TextWidget:new{
            text = _("Open apps"),
            face = Font:getFace("cfont", scale(25)),
            fgcolor = PALETTE.on_surface,
            bold = true,
            overlap_offset = { margin, scale(20) },
        },
        TextWidget:new{
            text = _("Hold an app to start split screen"),
            face = Font:getFace("smallinfofont", scale(12)),
            fgcolor = PALETTE.on_variant,
            overlap_offset = { margin, scale(52) },
        },
    }
    local open_apps = self.manager:getOpenApps()
    if #open_apps == 0 then
        table.insert(content, TextWidget:new{
            text = _("No DApps are open yet."),
            face = Font:getFace("smallinfofont", scale(16)),
            fgcolor = PALETTE.on_variant,
            overlap_offset = { margin, scale(80) },
        })
    end
    for index, app in ipairs(open_apps) do
        local y = scale(74) + (index - 1) * (card_height + gap)
        table.insert(content, ActionChip:new{
            title = app.title,
            symbol = app.symbol,
            logo = app.logo,
            width = card_width, height = card_height,
            background = PALETTE.surface, foreground = PALETTE.on_surface,
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
            overlap_offset = { width - margin - scale(38), y + scale(23) },
        })
    end
    table.insert(content, ActionChip:new{
        title = _("Home"), symbol = "⌂", width = scale(72), height = scale(44),
        background = PALETTE.primary, foreground = PALETTE.on_primary,
        callback = function()
            UIManager:close(self)
            UIManager:nextTick(function() self.manager.appdock:showHome() end)
        end,
        overlap_offset = { margin, height - scale(60) },
    })
    self:clear()
    self[1] = content
end

function DAppRecents:onClose()
    UIManager:close(self)
    UIManager:nextTick(function() self.manager.appdock:showHome() end)
    return true
end

return DAppManager
