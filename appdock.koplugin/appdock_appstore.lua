--[[--
A small, explicit-trust AppStore for AppDock DApps.
It reads only a plain-text manifest from the owner-configured GitHub repository.
Catalog refresh never executes remote code; a user confirmation and Lua syntax
check are required before an individual DApp is installed or updated.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local DAppLogo = require("appdock_logo")
local Layout = require("appdock_layout")
local Theme = require("appdock_theme")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Widget = require("ui/widget/widget")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local AppDockKeyboard = require("appdock_keyboard")
local InfoMessage = require("ui/widget/infomessage")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextWidget = require("ui/widget/textwidget")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
if not ok_lfs then lfs = require("lfs") end

local Screen = Device.screen
local AppStore = {}
AppStore.__index = AppStore

local REPOSITORY = "https://raw.githubusercontent.com/arduinodude456/DApps/main/"
local MANIFEST_URL = REPOSITORY .. "dapps.txt"
local MAX_MANIFEST_BYTES = 128 * 1024
local MAX_DAPP_BYTES = 512 * 1024
local MAX_WIDGET_BYTES = 256 * 1024
local MAX_DESIGN_BYTES = 32 * 1024
local MAX_WALLPAPER_BYTES = 2 * 1024 * 1024
local DESIGN_IMAGE_SUFFIXES = { png = true, jpg = true, jpeg = true, webp = true }
local KNOWN_LOGOS = {}
for _, kind in ipairs(DAppLogo.availableKinds()) do KNOWN_LOGOS[kind] = true end

local function scale(value)
    return Screen:scaleBySize(value)
end

local function trim(value)
    return type(value) == "string" and value:gsub("^%s+", ""):gsub("%s+$", "") or ""
end

local function safeDesignImagePath(path)
    if type(path) ~= "string" or #path == 0 or #path > 180 or path:find("..", 1, true) then return false end
    if not path:match("^[%w%._/%-]+$") then return false end
    local suffix = path:match("%.([%w]+)$")
    return suffix and DESIGN_IMAGE_SUFFIXES[suffix:lower()] == true or false
end

local function saveFile(path, body)
    local temporary = path .. ".tmp"
    os.remove(temporary)
    local file, write_err = io.open(temporary, "wb")
    if not file then return false, write_err end
    local written, close_err = file:write(body)
    file:close()
    if not written then
        os.remove(temporary)
        return false, close_err
    end
    if not os.rename(temporary, path) then
        os.remove(temporary)
        return false, "could not replace local file"
    end
    return true
end

local function emptySizedWidget(width, height)
    return CenterContainer:new{
        dimen = Geom:new{ w = width, h = height },
        HorizontalSpan:new{ width = 0 },
    }
end

--[[--
The AppStore uses its own AppDock Store branding with a familiar catalog
layout: a fixed palette that remains readable on grayscale E-Ink, a top app
bar, search pill, recommendation cards and clear action rows.
--]]--

local function playColor(red, green, blue, grayscale)
    if Device.screen:isColorEnabled() then
        return Blitbuffer.ColorRGB32(red, green, blue, 0xFF)
    end
    return grayscale
end

local PLAY = {
    background = playColor(255, 255, 255, Blitbuffer.COLOR_WHITE),
    surface = playColor(241, 243, 244, Blitbuffer.COLOR_LIGHT_GRAY),
    surface_variant = playColor(232, 234, 237, Blitbuffer.COLOR_GRAY_8),
    on_surface = playColor(32, 33, 36, Blitbuffer.COLOR_BLACK),
    on_variant = playColor(95, 99, 104, Blitbuffer.COLOR_DARK_GRAY),
    outline = playColor(218, 220, 224, Blitbuffer.COLOR_GRAY),
    divider = playColor(232, 234, 237, Blitbuffer.COLOR_LIGHT_GRAY),
    green = playColor(1, 135, 95, Blitbuffer.COLOR_BLACK),
    on_green = playColor(255, 255, 255, Blitbuffer.COLOR_WHITE),
    green_container = playColor(226, 244, 236, Blitbuffer.COLOR_LIGHT_GRAY),
    on_green_container = playColor(0, 82, 58, Blitbuffer.COLOR_DARK_GRAY),
    icon_tints = {
        playColor(232, 240, 254, Blitbuffer.COLOR_LIGHT_GRAY),
        playColor(230, 246, 235, Blitbuffer.COLOR_LIGHT_GRAY),
        playColor(254, 243, 224, Blitbuffer.COLOR_LIGHT_GRAY),
        playColor(252, 232, 238, Blitbuffer.COLOR_LIGHT_GRAY),
        playColor(240, 235, 251, Blitbuffer.COLOR_LIGHT_GRAY),
    },
}

local function kindLabel(kind)
    if kind == "widget" then return _("Widget") end
    if kind == "design" then return _("Design") end
    return _("DApp")
end

local function actionStateLabel(state)
    if state == "update" then return _("Update available") end
    if state == "installed" then return _("Installed") end
    return _("Not installed")
end

local function fillTriangle(bb, x1, y1, x2, y2, x3, y3, ink)
    local first = math.floor(math.min(y1, y2, y3) + .5)
    local last = math.floor(math.max(y1, y2, y3) + .5)
    for row = first, last do
        local scan = row + .5
        local crossings = {}
        local function edge(ax, ay, bx, by)
            if (ay <= scan and by > scan) or (by <= scan and ay > scan) then
                crossings[#crossings + 1] = ax + (scan - ay) / (by - ay) * (bx - ax)
            end
        end
        edge(x1, y1, x2, y2)
        edge(x2, y2, x3, y3)
        edge(x3, y3, x1, y1)
        if #crossings >= 2 then
            local left, right = math.min(crossings[1], crossings[2]), math.max(crossings[1], crossings[2])
            local start_x = math.floor(left + .5)
            bb:paintRect(start_x, row, math.max(1, math.floor(right + .5) - start_x), 1, ink)
        end
    end
end

local function fillCircle(bb, center_x, center_y, radius, ink)
    local first = math.floor(center_y - radius + .5)
    local last = math.floor(center_y + radius + .5)
    for row = first, last do
        local dy = row + .5 - center_y
        local span = radius * radius - dy * dy
        if span > 0 then
            local half = math.sqrt(span)
            local start_x = math.floor(center_x - half + .5)
            bb:paintRect(start_x, row, math.max(1, math.floor(center_x + half + .5) - start_x), 1, ink)
        end
    end
end

local function fillRing(bb, center_x, center_y, radius, thickness, ink)
    local inner = math.max(0, radius - thickness)
    local first = math.floor(center_y - radius + .5)
    local last = math.floor(center_y + radius + .5)
    for row = first, last do
        local dy = row + .5 - center_y
        local outer_span = radius * radius - dy * dy
        if outer_span > 0 then
            local outer_half = math.sqrt(outer_span)
            local inner_span = inner * inner - dy * dy
            local inner_half = inner_span > 0 and math.sqrt(inner_span) or 0
            local left_start = math.floor(center_x - outer_half + .5)
            local left_end = math.floor(center_x - inner_half + .5)
            if left_end > left_start then bb:paintRect(left_start, row, left_end - left_start, 1, ink) end
            local right_start = math.floor(center_x + inner_half + .5)
            local right_end = math.floor(center_x + outer_half + .5)
            if right_end > right_start then bb:paintRect(right_start, row, right_end - right_start, 1, ink) end
        end
    end
end

local function fillLine(bb, x1, y1, x2, y2, thickness, ink)
    local steps = math.max(1, math.floor(math.max(math.abs(x2 - x1), math.abs(y2 - y1)) * 2))
    local half = math.floor(thickness / 2)
    for step = 0, steps do
        local progress = step / steps
        local px = x1 + (x2 - x1) * progress
        local py = y1 + (y2 - y1) * progress
        bb:paintRect(math.floor(px + .5) - half, math.floor(py + .5) - half, thickness, thickness, ink)
    end
end

local function fillArc(bb, center_x, center_y, radius, thickness, start_degrees, end_degrees, ink)
    local half = math.floor(thickness / 2)
    for angle = start_degrees, end_degrees, 5 do
        local radians = math.rad(angle)
        local px = center_x + radius * math.cos(radians)
        local py = center_y + radius * math.sin(radians)
        bb:paintRect(math.floor(px + .5) - half, math.floor(py + .5) - half, thickness, thickness, ink)
    end
end

local NavIcon = Widget:extend{
    size = 20,
    kind = "grid",
    ink = nil,
    dimen = nil,
}

function NavIcon:init()
    self.dimen = Geom:new{ w = self.size, h = self.size }
end

function NavIcon:paintTo(bb, x, y)
    local size = self.size
    local ink = self.ink or PLAY.on_variant
    local function block(px, py, width_ratio, height_ratio)
        bb:paintRect(
            math.floor(x + size * px),
            math.floor(y + size * py),
            math.max(1, math.floor(size * width_ratio)),
            math.max(1, math.floor(size * height_ratio)),
            ink)
    end
    if self.kind == "apps" then
        block(.10, .12, .80, .76)
    elseif self.kind == "widgets" then
        block(.06, .14, .88, .28)
        block(.06, .54, .40, .32)
        block(.54, .54, .40, .32)
    elseif self.kind == "designs" then
        fillCircle(bb, x + size * .5, y + size * .5, size * .40, ink)
    else
        block(.08, .10, .36, .32)
        block(.56, .10, .36, .32)
        block(.08, .58, .36, .32)
        block(.56, .58, .36, .32)
    end
end

-- Magnifier and refresh are drawn, not typed: KOReader's font stack does not
-- guarantee a glyph for the technical symbols, and drawn icons render
-- consistently across readers.
local PlayGlyph = Widget:extend{
    size = 18,
    kind = "search",
    ink = nil,
    dimen = nil,
}

function PlayGlyph:init()
    self.dimen = Geom:new{ w = self.size, h = self.size }
end

function PlayGlyph:paintTo(bb, x, y)
    local size = self.size
    local ink = self.ink or PLAY.on_surface
    local thickness = math.max(1, math.floor(size * .16))
    if self.kind == "refresh" then
        local center_x, center_y = x + size * .50, y + size * .52
        fillArc(bb, center_x, center_y, size * .34, thickness, -70, 250, ink)
        fillTriangle(bb,
            x + size * .60, y + size * .06,
            x + size * .99, y + size * .20,
            x + size * .60, y + size * .42,
            ink)
    else
        local center_x, center_y = x + size * .42, y + size * .42
        fillRing(bb, center_x, center_y, size * .30, thickness, ink)
        fillLine(bb, center_x + size * .22, center_y + size * .22, x + size * .94, y + size * .94, thickness, ink)
    end
end

local PlayPill = InputContainer:extend{
    title = nil,
    glyph = nil,
    width = nil,
    height = nil,
    background = nil,
    foreground = nil,
    bordersize = 0,
    border_color = nil,
    radius = nil,
    bold = true,
    callback = nil,
    dimen = nil,
}

function PlayPill:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local font_size = math.max(scale(8), math.min(scale(14), math.floor(self.height * .40)))
    local glyph_size = self.glyph and math.max(scale(10), math.min(scale(20), math.floor(self.height * .48))) or 0
    local text_x = 0
    if self.glyph and (self.title and self.title ~= "") then
        text_x = scale(12) + glyph_size + scale(10)
    end
    local label = nil
    if self.title and self.title ~= "" then
        local available = text_x > 0 and (self.width - text_x - scale(12)) or self.width
        label = Theme.fitLabel(self.title, available, font_size, scale(14))
    end
    local entries = {}
    if glyph_size > 0 then
        entries[#entries + 1] = {
            widget = PlayGlyph:new{ kind = self.glyph, size = glyph_size, ink = self.foreground },
            x = text_x > 0 and scale(12) or math.floor((self.width - glyph_size) / 2),
            y = math.max(0, math.floor((self.height - glyph_size) / 2)),
        }
    end
    if label then
        local text_widget = TextWidget:new{
            text = label,
            face = Font:getFace("smallinfofont", font_size),
            fgcolor = self.foreground,
            bold = self.bold,
            max_width = text_x > 0 and (self.width - text_x - scale(12)) or (self.width - scale(12)),
            padding = 0,
        }
        entries[#entries + 1] = {
            widget = text_widget,
            x = text_x > 0 and text_x or math.max(0, math.floor((self.width - text_widget:getSize().w) / 2)),
            y = math.max(0, math.floor((self.height - text_widget:getSize().h) / 2)),
        }
    end
    self[1] = FrameContainer:new{
        width = self.width,
        height = self.height,
        padding = 0,
        bordersize = self.bordersize or 0,
        color = self.border_color or Blitbuffer.COLOR_BLACK,
        radius = self.radius or math.floor(self.height / 2),
        background = self.background,
        Layout.FixedStack:new{
            width = self.width,
            height = self.height,
            entries = entries,
        },
    }
    self.ges_events = { TapPlayPill = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function PlayPill:paintTo(bb, x, y)
    local range = self.ges_events.TapPlayPill[1].range
    range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    return InputContainer.paintTo(self, bb, x, y)
end

function PlayPill:onTapPlayPill()
    if self.callback then self.callback() end
    return true
end

-- A Play list row: tinted app icon, title, metadata line and a state line.
-- The trailing install/open button is a sibling widget so the two touch
-- targets never overlap.
local PlayRow = InputContainer:extend{
    entry = nil,
    state = "install",
    logo = nil,
    tint = nil,
    width = nil,
    height = nil,
    reserve_right = 0,
    background = nil,
    callback = nil,
    dimen = nil,
}

function PlayRow:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local inset = scale(10)
    local icon_size = math.max(scale(30), math.min(scale(52), self.height - 2 * scale(11)))
    local text_x = inset + icon_size + scale(12)
    local text_width = math.max(scale(20), self.width - text_x - inset - (self.reserve_right or 0) - scale(6))
    local title_size = math.max(scale(10), math.min(scale(15), math.floor(self.height * .21)))
    local meta_size = math.max(scale(8), math.min(scale(11), math.floor(self.height * .145)))
    local entry = self.entry or {}
    local version = entry.version and (" · v" .. tostring(entry.version)) or ""
    local title = TextWidget:new{
        text = Theme.fitLabel(entry.title or "", text_width, title_size, 0),
        face = Font:getFace("smallinfofont", title_size),
        fgcolor = PLAY.on_surface,
        bold = true,
        max_width = text_width,
        padding = 0,
    }
    local meta = TextWidget:new{
        text = Theme.fitLabel(kindLabel(entry.kind) .. version, text_width, meta_size, 0),
        face = Font:getFace("smallinfofont", meta_size),
        fgcolor = PLAY.on_variant,
        max_width = text_width,
        padding = 0,
    }
    local state_text, state_color = actionStateLabel(self.state), PLAY.on_variant
    if self.state == "installed" then
        state_color = PLAY.green
    elseif self.state == "update" then
        state_color = PLAY.on_green_container
    end
    local state_widget = TextWidget:new{
        text = Theme.fitLabel(state_text, text_width, meta_size, 0),
        face = Font:getFace("smallinfofont", meta_size),
        fgcolor = state_color,
        bold = true,
        max_width = text_width,
        padding = 0,
    }
    local positions = Theme.centeredStack(self.height, { title, meta, state_widget }, scale(4), scale(6))
    local tile = FrameContainer:new{
        width = icon_size, height = icon_size, padding = 0, bordersize = 0,
        radius = math.floor(icon_size * .28),
        background = self.tint or PLAY.surface,
        CenterContainer:new{
            dimen = Geom:new{ w = icon_size, h = icon_size },
            DAppLogo:new{
                kind = self.logo or "app_store",
                size = math.max(scale(16), math.floor(icon_size * .62)),
                ink = PLAY.on_surface,
            },
        },
    }
    self[1] = FrameContainer:new{
        width = self.width, height = self.height, padding = 0, bordersize = 0,
        radius = math.floor(self.height * .22),
        background = self.background or PLAY.background,
        Layout.FixedStack:new{
            width = self.width, height = self.height,
            entries = {
                { widget = tile, x = inset, y = math.max(0, math.floor((self.height - icon_size) / 2)) },
                { widget = title, x = text_x, y = positions[1] },
                { widget = meta, x = text_x, y = positions[2] },
                { widget = state_widget, x = text_x, y = positions[3] },
            },
        },
    }
    self.ges_events = { TapPlayRow = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function PlayRow:paintTo(bb, x, y)
    local range = self.ges_events.TapPlayRow[1].range
    range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    return InputContainer.paintTo(self, bb, x, y)
end

function PlayRow:onTapPlayRow()
    if self.callback then self.callback() end
    return true
end

-- A "Recommended for you" style card with a tinted icon tile above the title.
local PlayCard = InputContainer:extend{
    entry = nil,
    logo = nil,
    tint = nil,
    width = nil,
    height = nil,
    callback = nil,
    dimen = nil,
}

function PlayCard:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local entry = self.entry or {}
    local tile_size = math.max(scale(28), math.min(scale(56), math.floor(self.height * .54)))
    local title_size = math.max(scale(8), math.min(scale(12), math.floor(self.height * .13)))
    local meta_size = math.max(scale(7), math.min(scale(10), math.floor(self.height * .105)))
    local text_width = math.max(scale(16), self.width - scale(10))
    local version = entry.version and ("v" .. tostring(entry.version)) or ""
    local title = TextWidget:new{
        text = Theme.fitLabel(entry.title or "", text_width, title_size, 0),
        face = Font:getFace("smallinfofont", title_size),
        fgcolor = PLAY.on_surface,
        bold = true,
        max_width = text_width,
        padding = 0,
    }
    local meta = TextWidget:new{
        text = Theme.fitLabel(kindLabel(entry.kind) .. (version ~= "" and (" · " .. version) or ""), text_width, meta_size, 0),
        face = Font:getFace("smallinfofont", meta_size),
        fgcolor = PLAY.on_variant,
        max_width = text_width,
        padding = 0,
    }
    local tile = FrameContainer:new{
        width = tile_size, height = tile_size, padding = 0, bordersize = 0,
        radius = math.floor(tile_size * .30),
        background = self.tint or PLAY.surface,
        CenterContainer:new{
            dimen = Geom:new{ w = tile_size, h = tile_size },
            DAppLogo:new{
                kind = self.logo or "app_store",
                size = math.max(scale(16), math.floor(tile_size * .62)),
                ink = PLAY.on_surface,
            },
        },
    }
    local title_y = tile_size + scale(8)
    self[1] = FrameContainer:new{
        width = self.width, height = self.height, padding = 0, bordersize = 0,
        radius = math.floor(self.height * .12),
        background = PLAY.background,
        Layout.FixedStack:new{
            width = self.width, height = self.height,
            entries = {
                { widget = tile, x = math.floor((self.width - tile_size) / 2), y = scale(4) },
                { widget = title, x = math.max(0, math.floor((self.width - title:getSize().w) / 2)), y = title_y },
                { widget = meta, x = math.max(0, math.floor((self.width - meta:getSize().w) / 2)), y = title_y + title_size + scale(4) },
            },
        },
    }
    self.ges_events = { TapPlayCard = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function PlayCard:paintTo(bb, x, y)
    local range = self.ges_events.TapPlayCard[1].range
    range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    return InputContainer.paintTo(self, bb, x, y)
end

function PlayCard:onTapPlayCard()
    if self.callback then self.callback() end
    return true
end

-- One tab of the Play bottom navigation (the AppStore category selector).
local PlayNavTab = InputContainer:extend{
    label = nil,
    icon = "grid",
    active = false,
    width = nil,
    height = nil,
    callback = nil,
    dimen = nil,
}

function PlayNavTab:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local icon_size = math.max(scale(12), math.min(scale(22), math.floor(self.height * .34)))
    local label_size = math.max(scale(8), math.min(scale(11), math.floor(self.height * .19)))
    local foreground = self.active and PLAY.green or PLAY.on_variant
    local label = TextWidget:new{
        text = Theme.fitLabel(self.label or "", self.width, label_size, scale(6)),
        face = Font:getFace("smallinfofont", label_size),
        fgcolor = foreground,
        bold = self.active,
        max_width = self.width - scale(6),
        padding = 0,
    }
    local icon_y = math.floor(self.height * .20)
    self[1] = Layout.FixedStack:new{
        width = self.width, height = self.height,
        entries = {
            { widget = NavIcon:new{ size = icon_size, kind = self.icon, ink = foreground }, x = math.floor((self.width - icon_size) / 2), y = icon_y },
            { widget = label, x = math.max(0, math.floor((self.width - label:getSize().w) / 2)), y = icon_y + icon_size + scale(4) },
        },
    }
    self.ges_events = { TapPlayNavTab = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function PlayNavTab:paintTo(bb, x, y)
    local range = self.ges_events.TapPlayNavTab[1].range
    range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    return InputContainer.paintTo(self, bb, x, y)
end

function PlayNavTab:onTapPlayNavTab()
    if self.callback then self.callback() end
    return true
end

local function fetchText(url, limit)
    local socket_url = require("socket.url")
    local socket = require("socket")
    local socketutil = require("socketutil")
    local parsed = socket_url.parse(url)
    if not parsed or parsed.scheme ~= "https" then return nil, _("Only HTTPS sources are allowed.") end
    local https = require("ssl.https")
    local chunks, received = {}, 0
    local function sink(chunk)
        if chunk then
            received = received + #chunk
            if received > limit then return nil, "response too large" end
            table.insert(chunks, chunk)
        end
        return 1
    end
    socketutil:set_timeout(12, 30)
    local ok, code, headers, status = pcall(function()
        return socket.skip(1, https.request{
            url = url,
            method = "GET",
            sink = sink,
            headers = {
                ["user-agent"] = socketutil.USER_AGENT,
                ["accept"] = "text/plain,text/x-lua,application/octet-stream;q=0.8,*/*;q=0.1",
            },
        })
    end)
    socketutil:reset_timeout()
    if not ok or not headers then return nil, status or _("Network request failed.") end
    if not code or code < 200 or code > 299 then return nil, status or _("Repository unavailable.") end
    return table.concat(chunks), nil
end

local function normalizedVersion(version)
    if type(version) ~= "string" then return nil end
    local normalized = version:match("^v?(%d+%.?%d*%.?%d*)$")
    if not normalized then return nil end
    local parts = {}
    for part in normalized:gmatch("%d+") do table.insert(parts, tonumber(part)) end
    return #parts > 0 and parts or nil
end

function AppStore.compareVersions(left, right)
    local left_parts, right_parts = normalizedVersion(left), normalizedVersion(right)
    if not left_parts or not right_parts then return nil end
    for index = 1, math.max(#left_parts, #right_parts) do
        local a, b = left_parts[index] or 0, right_parts[index] or 0
        if a ~= b then return a > b and 1 or -1 end
    end
    return 0
end

function AppStore.parseManifest(body)
    local entries, known = {}, {}
    for raw_line in (body or ""):gmatch("[^\r\n]+") do
        local value = raw_line:gsub("#.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
        local parts = {}
        for part in value:gmatch("[^|]+") do
            table.insert(parts, (part:gsub("^%s+", ""):gsub("%s+$", "")))
        end
        local path = parts[1] or value
        local version = normalizedVersion(parts[2]) and parts[2] or nil
        local logo = type(parts[3]) == "string" and KNOWN_LOGOS[parts[3]] and parts[3] or nil
        local kind = parts[4] == "widget" and "widget" or (parts[4] == "design" and "design" or "dapp")
        local expected_suffix = kind == "design" and "%.appdock%-design$" or "%.lua$"
        if path ~= "" and path:match("^[%w%._/%-]+$") and path:match(expected_suffix) and not path:find("..", 1, true) and not known[path] then
            known[path] = true
            local name = path:match("([^/]+)%.appdock%-design$") or path:match("([^/]+)%.lua$") or path
            name = name:gsub("[_%-]+", " "):gsub("%f[%a].", string.upper)
            table.insert(entries, { path = path, title = name, version = version, logo = logo, kind = kind })
        end
    end
    table.sort(entries, function(left, right) return left.title:lower() < right.title:lower() end)
    return entries
end

function AppStore.filterEntries(entries, query, category)
    local needle = trim(query or ""):lower()
    local result = {}
    for _, entry in ipairs(entries or {}) do
        local haystack = table.concat({ entry.title or "", entry.path or "", entry.kind or "" }, " "):lower()
        local matches_query = needle == "" or haystack:find(needle, 1, true)
        local matches_category = not category or category == "all" or entry.kind == category
        if matches_query and matches_category then table.insert(result, entry) end
    end
    return result
end

function AppStore:new()
    return setmetatable({}, self)
end

function AppStore:_ensureState(instance)
    instance.app_store = instance.app_store or {
        entries = nil,
        error = nil,
        refreshed = false,
        query = "",
        category = "all",
    }
    instance.app_store.query = type(instance.app_store.query) == "string" and instance.app_store.query or ""
    local category = instance.app_store.category
    instance.app_store.category = (category == "dapp" or category == "widget" or category == "design") and category or "all"
    return instance.app_store
end

function AppStore:promptSearch(instance, context)
    local state = self:_ensureState(instance)
    local dialog
    dialog = InputDialog:new{
        title = _("Search AppStore"),
        input = state.query or "",
        input_hint = _("Name, file path, DApp, widget, or design"),
        buttons = {
            {
                { text = _("Clear"), callback = function() state.query = ""; UIManager:close(dialog); context.requestRebuild("ui") end },
                { text = _("Cancel"), callback = function() UIManager:close(dialog) end },
                { text = _("Search"), is_enter_default = true, callback = function() state.query = trim(dialog:getInputText()); UIManager:close(dialog); context.requestRebuild("ui") end },
            },
        },
    }
    AppDockKeyboard.attach(dialog)
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function AppStore:cycleCategory(instance, context)
    local state = self:_ensureState(instance)
    local categories = { "all", "dapp", "widget", "design" }
    local position = 1
    for index, category in ipairs(categories) do
        if category == state.category then position = index; break end
    end
    state.category = categories[position % #categories + 1]
    context.requestRebuild("ui")
end

function AppStore:refresh(instance, context)
    local state = self:_ensureState(instance)
    local manifest, err = fetchText(MANIFEST_URL, MAX_MANIFEST_BYTES)
    state.entries = manifest and AppStore.parseManifest(manifest) or nil
    state.error = err
    state.refreshed = true
    context.requestRebuild("ui")
end

function AppStore:_storeDirectory()
    local path = DataStorage:getDataDir() .. "/appdock_dapps"
    if lfs.attributes(path, "mode") ~= "directory" then lfs.mkdir(path) end
    return path
end

function AppStore:_designDirectory()
    local path = DataStorage:getDataDir() .. "/appdock_designs"
    if lfs.attributes(path, "mode") ~= "directory" then lfs.mkdir(path) end
    return path
end

function AppStore:_entryState(context, entry)
    local definition, record
    if entry.kind == "design" then
        definition, record = context.appdock:getStoreDesignBySource(entry.path)
    elseif entry.kind == "widget" then
        definition, record = context.manager:getStoreWidgetBySource(entry.path)
    else
        definition, record = context.manager:getStoreDAppBySource(entry.path)
    end
    if not record then return "install", nil, nil end
    local installed_version = record.version or (definition and definition.version)
    if entry.version and (not installed_version or AppStore.compareVersions(entry.version, installed_version) == 1) then
        return "update", definition, record
    end
    return "installed", definition, record
end

function AppStore:confirmInstall(instance, context, entry)
    local state = self:_entryState(context, entry)
    if state == "installed" then
        if entry.kind == "design" then
            local design = context.appdock:getStoreDesignBySource(entry.path)
            if design and context.appdock:setStoreDesignActive(design.id) then
                UIManager:show(InfoMessage:new{ text = _("Activated ") .. entry.title .. _(". Its colors, styles, and background are now in use.") })
                context.requestRebuild("ui")
                return
            end
        end
        UIManager:show(InfoMessage:new{ text = entry.title .. _(" is already installed and up to date.") })
        return
    end
    local is_update = state == "update"
    local is_widget = entry.kind == "widget"
    local is_design = entry.kind == "design"
    local item_name = is_design and _("design") or (is_widget and _("widget") or _("DApp"))
    local action = is_update and _("Update") or _("Install")
    local message = is_update and (_("Update this installed ") .. item_name .. _(" from your trusted AppDock GitHub repository?\n\n")) or (_("Install this ") .. item_name .. _(" from your trusted AppDock GitHub repository?\n\n"))
    local dialog = ConfirmBox:new{
        text = message .. entry.path .. (entry.version and ("\n\n" .. _("Repository version: ") .. entry.version) or "") .. (is_design and _("\n\nA design is declarative data only. It is validated and applied locally; it never executes code.") or _("\n\nThe file is downloaded only after you choose this action. It will be validated before being added to AppDock.")),
        ok_text = action,
        ok_callback = function() self:install(instance, context, entry, is_update) end,
    }
    UIManager:show(dialog)
end

function AppStore:_parseDesign(body)
    local definition = {}
    local allowed = {
        id = true, title = true, version = true, highlight = true, background = true,
        button = true, text = true, dropdown = true, button_style = true, logo_shape = true, wallpaper = true,
    }
    for raw_line in (body or ""):gmatch("[^\r\n]+") do
        local key, value = raw_line:match("^%s*([%w_%-]+)%s*=%s*(.-)%s*$")
        if key and value and allowed[key] and definition[key] == nil then definition[key] = value end
    end
    if definition.wallpaper ~= nil and definition.wallpaper ~= "" and not safeDesignImagePath(definition.wallpaper) then
        return nil, _("The design wallpaper path is invalid.")
    end
    local normalized = Theme.normalizeDesignDefinition(definition)
    if not normalized then return nil, _("A design requires an id, title, five valid colors, and valid styles.") end
    return normalized
end

function AppStore:installDesign(instance, context, entry)
    local source, err = fetchText(REPOSITORY .. entry.path, MAX_DESIGN_BYTES)
    if not source then
        UIManager:show(InfoMessage:new{ text = _("Could not download this design: ") .. (err or "") })
        return
    end
    local definition, inspect_err = self:_parseDesign(source)
    if not definition then
        UIManager:show(InfoMessage:new{ text = _("This file is not a valid AppDock design.\n\n") .. tostring(inspect_err) })
        return
    end
    if entry.version and definition.version ~= entry.version then
        UIManager:show(InfoMessage:new{ text = _("The downloaded design version does not match the catalog entry.") })
        return
    end
    local installed, installed_id = context.appdock:getStoreDesignBySource(entry.path)
    if installed and installed_id ~= definition.id then
        UIManager:show(InfoMessage:new{ text = _("This update changes the design identity and was rejected.") })
        return
    end
    local design_directory = self:_designDirectory()
    local wallpaper_file = ""
    if definition.wallpaper and definition.wallpaper ~= "" then
        local image, image_err = fetchText(REPOSITORY .. definition.wallpaper, MAX_WALLPAPER_BYTES)
        if not image then
            UIManager:show(InfoMessage:new{ text = _("Could not download this design background: ") .. tostring(image_err or "") })
            return
        end
        local suffix = definition.wallpaper:match("%.([%w]+)$") or "png"
        wallpaper_file = design_directory .. "/" .. definition.id .. "_wallpaper." .. suffix:lower()
        local image_saved, image_save_err = saveFile(wallpaper_file, image)
        if not image_saved then
            UIManager:show(InfoMessage:new{ text = _("Could not save this design background: ") .. tostring(image_save_err or "") })
            return
        end
    end
    local filename = entry.path:gsub("[^%w%._%-]", "_")
    local target = design_directory .. "/" .. filename
    local saved, save_err = saveFile(target, source)
    if not saved then
        UIManager:show(InfoMessage:new{ text = _("Could not save this design: ") .. tostring(save_err or "") })
        return
    end
    local ok, stored = context.appdock:installStoreDesign(definition, entry.path, target, wallpaper_file)
    if not ok then
        UIManager:show(InfoMessage:new{ text = _("Could not activate this design: ") .. tostring(stored or "") })
        return
    end
    UIManager:show(InfoMessage:new{ text = _("Installed and activated ") .. entry.title .. _(". It now controls AppDock colors, background, buttons, and app logos.") })
    context.requestRebuild("ui")
end

function AppStore:install(instance, context, entry, is_update)
    if entry.kind == "design" then
        self:installDesign(instance, context, entry)
        return
    end
    local is_widget = entry.kind == "widget"
    local source, err = fetchText(REPOSITORY .. entry.path, is_widget and MAX_WIDGET_BYTES or MAX_DAPP_BYTES)
    if not source then
        UIManager:show(InfoMessage:new{ text = (is_widget and _("Could not download this widget: ") or _("Could not download this DApp: ")) .. (err or "") })
        return
    end
    local chunk, syntax_err = loadstring(source, "@appstore/" .. entry.path)
    if not chunk then
        UIManager:show(InfoMessage:new{ text = _("The downloaded DApp has invalid Lua syntax.\n\n") .. tostring(syntax_err) })
        return
    end
    local filename = entry.path:gsub("[^%w%._%-]", "_")
    local target = self:_storeDirectory() .. "/" .. filename
    local temporary = target .. ".tmp"
    os.remove(temporary)
    local file, write_err = io.open(temporary, "wb")
    if not file then
        UIManager:show(InfoMessage:new{ text = _("Could not save this DApp: ") .. tostring(write_err) })
        return
    end
    local written, close_err = file:write(source)
    file:close()
    if not written then
        os.remove(temporary)
        UIManager:show(InfoMessage:new{ text = _("Could not save this DApp: ") .. tostring(close_err) })
        return
    end
    local definition, inspect_err
    if is_widget then
        definition, inspect_err = context.manager:inspectStoreWidget(temporary)
    else
        definition, inspect_err = context.manager:inspectStoreDApp(temporary)
    end
    if not definition then
        os.remove(temporary)
        UIManager:show(InfoMessage:new{ text = (is_widget and _("This file is not a valid AppDock widget.\n\n") or _("This file is not a valid AppDock DApp.\n\n")) .. tostring(inspect_err) })
        return
    end
    if entry.version and definition.version ~= entry.version then
        os.remove(temporary)
        UIManager:show(InfoMessage:new{ text = is_widget and _("The downloaded widget version does not match the catalog entry.") or _("The downloaded DApp version does not match the catalog entry.") })
        return
    end
    local installed_definition, installed_record
    if is_widget then
        installed_definition, installed_record = context.manager:getStoreWidgetBySource(entry.path)
    else
        installed_definition, installed_record = context.manager:getStoreDAppBySource(entry.path)
    end
    if installed_definition and installed_definition.id ~= definition.id then
        os.remove(temporary)
        UIManager:show(InfoMessage:new{ text = _("This update changes the DApp identity and was rejected.") })
        return
    end
    if ((is_widget and context.manager.definitions[definition.id]) or (not is_widget and context.manager.widget_definitions[definition.id])) and not installed_record then
        os.remove(temporary)
        UIManager:show(InfoMessage:new{ text = is_widget and _("A different installed DApp already uses this id.") or _("A different installed widget already uses this id.") })
        return
    end
    if is_update and not installed_record then
        os.remove(temporary)
        UIManager:show(InfoMessage:new{ text = _("The installed DApp record is unavailable; refresh the catalog and try again.") })
        return
    end
    local backup = target .. ".previous"
    os.remove(backup)
    local had_target = lfs.attributes(target) ~= nil
    if had_target and not os.rename(target, backup) then
        os.remove(temporary)
        UIManager:show(InfoMessage:new{ text = _("The existing DApp could not be prepared for update.") })
        return
    end
    if not os.rename(temporary, target) then
        if had_target then os.rename(backup, target) end
        os.remove(temporary)
        UIManager:show(InfoMessage:new{ text = _("The downloaded DApp could not replace the previous version.") })
        return
    end
    local ok, result
    if is_widget then
        ok, result = context.manager:loadStoreWidget(target, entry.path, false, definition.id, installed_record ~= nil, target)
    else
        ok, result = context.manager:loadStoreDApp(target, entry.path, false, definition.id, installed_record ~= nil, target)
    end
    if not ok then
        os.remove(target)
        if had_target then os.rename(backup, target) end
        UIManager:show(InfoMessage:new{ text = (is_widget and _("This file is not a valid AppDock widget.\n\n") or _("This file is not a valid AppDock DApp.\n\n")) .. tostring(result) })
        return
    end
    os.remove(backup)
    local action = installed_record and _("Updated") or _("Installed")
    UIManager:show(InfoMessage:new{ text = action .. " " .. entry.title .. (is_widget and _(". It is now available on the AppDock homescreen.") or _(". It is now available in AppDock apps.")) })
    context.requestRebuild("ui")
end

function AppStore:confirmUninstallWidget(instance, context, entry, definition)
    local dialog
    dialog = ConfirmBox:new{
        text = _("Remove this Store widget from the AppDock homescreen?\n\n") .. entry.title,
        ok_text = _("Uninstall"),
        ok_callback = function()
            local ok, err = context.manager:uninstallStoreWidget(definition.id)
            UIManager:close(dialog)
            if ok then
                UIManager:show(InfoMessage:new{ text = _("Removed ") .. entry.title .. _(" from the AppDock homescreen.") })
                context.requestRebuild("ui")
            else
                UIManager:show(InfoMessage:new{ text = _("Could not remove this widget: ") .. tostring(err) })
            end
        end,
    }
    UIManager:show(dialog)
end

function AppStore:confirmUninstall(instance, context, entry, definition)
    local dialog
    dialog = ConfirmBox:new{
        text = _("Remove this DApp from AppDock?\n\n") .. entry.title .. _("\n\nIts installed Lua file and AppStore registration will be removed. Any saved documents created by the DApp are kept."),
        ok_text = _("Uninstall"),
        ok_callback = function()
            UIManager:close(dialog)
            local ok, err = context.manager:uninstallStoreDApp(definition.id)
            if ok then
                UIManager:show(InfoMessage:new{ text = _("Removed ") .. entry.title .. _(" from AppDock.") })
                context.requestRebuild("ui")
            else
                UIManager:show(InfoMessage:new{ text = _("Could not remove this DApp: ") .. tostring(err) })
            end
        end,
    }
    UIManager:show(dialog)
end

function AppStore:confirmUninstallDesign(instance, context, entry, definition)
    local dialog
    dialog = ConfirmBox:new{
        text = _("Remove this AppStore design?\n\n") .. entry.title .. _("\n\nIf it is active, AppDock returns to your existing theme, button style, and personal background settings."),
        ok_text = _("Uninstall"),
        ok_callback = function()
            local ok, err = context.appdock:uninstallStoreDesign(definition.id)
            if ok then
                UIManager:show(InfoMessage:new{ text = _("Removed ") .. entry.title .. _(". The previous AppDock appearance is restored.") })
                context.requestRebuild("ui")
            else
                UIManager:show(InfoMessage:new{ text = _("Could not remove this design: ") .. tostring(err) })
            end
        end,
    }
    UIManager:show(dialog)
end

function AppStore:_showStatus(entry, state)
    if state == "update" then return _("Update available") .. (entry.version and (" · " .. entry.version) or "") end
    if state == "installed" then return _("Installed") .. (entry.version and (" · " .. entry.version) or "") end
    return _("Not installed") .. (entry.version and (" · " .. entry.version) or "")
end

function AppStore:buildPane(instance, context)
    local state = self:_ensureState(instance)
    local width, height = context.dimen.w, context.dimen.h
    local margin, gap = scale(12), scale(8)
    local query = trim(state.query or "")
    local content = OverlapGroup:new{
        dimen = Geom:new{ w = width, h = height },
        allow_mirroring = false,
        FrameContainer:new{
            width = width, height = height, padding = 0, bordersize = 0,
            background = PLAY.background,
            emptySizedWidget(width, height),
        },
    }

    -- AppDock Store top bar: the plugin's own AppStore mark and wordmark,
    -- followed by search, refresh and the catalog profile chip.
    local bar_height = scale(50)
    local mark_size = scale(26)
    table.insert(content, DAppLogo:new{
        kind = "app_store",
        size = mark_size,
        ink = PLAY.on_surface,
        overlap_offset = { margin, math.floor((bar_height - mark_size) / 2) },
    })
    local wordmark = TextWidget:new{
        text = _("AppDock Store"),
        face = Font:getFace("cfont", scale(19)),
        fgcolor = PLAY.on_surface,
        bold = true,
        padding = 0,
    }
    wordmark.overlap_offset = {
        margin + mark_size + scale(9),
        math.max(scale(4), math.floor((bar_height - wordmark:getSize().h) / 2)),
    }
    table.insert(content, wordmark)

    local chip_size, chip_gap = scale(34), scale(6)
    local chip_y = math.floor((bar_height - chip_size) / 2)
    local avatar_x = width - margin - chip_size
    local refresh_x = avatar_x - chip_gap - chip_size
    local search_x = refresh_x - chip_gap - chip_size
    table.insert(content, PlayPill:new{
        glyph = "search", width = chip_size, height = chip_size,
        radius = math.floor(chip_size / 2),
        background = PLAY.surface, foreground = PLAY.on_surface,
        callback = function() self:promptSearch(instance, context) end,
        overlap_offset = { search_x, chip_y },
    })
    table.insert(content, PlayPill:new{
        glyph = "refresh", width = chip_size, height = chip_size,
        radius = math.floor(chip_size / 2),
        background = PLAY.surface, foreground = PLAY.on_surface,
        callback = function() self:refresh(instance, context) end,
        overlap_offset = { refresh_x, chip_y },
    })
    table.insert(content, PlayPill:new{
        title = "A", width = chip_size, height = chip_size,
        radius = math.floor(chip_size / 2),
        background = PLAY.green, foreground = PLAY.on_green,
        callback = function()
            UIManager:show(InfoMessage:new{
                text = _("Trusted AppDock catalog") .. "\n\n" .. REPOSITORY .. "\n\n" .. _("Installations, updates, and removals always require an explicit confirmation."),
            })
        end,
        overlap_offset = { avatar_x, chip_y },
    })

    local search_height = scale(44)
    local search_y = bar_height + scale(2)
    table.insert(content, PlayPill:new{
        glyph = "search",
        title = query == "" and _("Search for apps & games") or (_("Search: ") .. query),
        width = width - 2 * margin, height = search_height,
        radius = math.floor(search_height / 2),
        background = PLAY.surface,
        foreground = query == "" and PLAY.on_variant or PLAY.on_surface,
        bold = false,
        callback = function() self:promptSearch(instance, context) end,
        overlap_offset = { margin, search_y },
    })

    local body_y = search_y + search_height + gap
    local nav_height = scale(58)
    local list_bottom = height - nav_height - scale(6)
    local visible_entries = state.entries and AppStore.filterEntries(state.entries, query, state.category) or {}
    local catalog_ready = state.refreshed and not state.error and state.entries and #state.entries > 0

    if catalog_ready and #visible_entries > 0 then
        -- "Updates available" first, otherwise a recommendation shelf. Both are
        -- drawn from real catalog entries, never from invented ratings.
        local featured, featured_state = {}, "install"
        for _, entry in ipairs(visible_entries) do
            if #featured >= 3 then break end
            if self:_entryState(context, entry) == "update" then
                featured[#featured + 1] = entry
                featured_state = "update"
            end
        end
        if #featured == 0 then
            for index = 1, math.min(3, #visible_entries) do featured[#featured + 1] = visible_entries[index] end
        end
        -- Cards with a pending update carry an extra Play button below the card,
        -- so the shelf reserves that row before the list starts.
        local action_row = featured_state == "update" and scale(34) or 0
        -- The shelf is decoration on top of the real list, so a short screen
        -- gives the space to the list instead of squeezing both.
        local show_shelf = (list_bottom - body_y) >= (scale(180) + action_row)
        local heading = featured_state == "update" and _("Updates available") or _("Recommended for you")
        local heading_widget = TextWidget:new{
            text = heading,
            face = Font:getFace("cfont", scale(16)),
            fgcolor = PLAY.on_surface,
            bold = true,
            max_width = width - 2 * margin,
            padding = 0,
        }
        local card_gap = scale(8)
        local card_width = math.floor((width - 2 * margin - 2 * card_gap) / 3)
        local card_height = scale(98)
        if show_shelf then
            heading_widget.overlap_offset = { margin, body_y }
            table.insert(content, heading_widget)
            local card_y = body_y + scale(24)
            for index, entry in ipairs(featured) do
                local entry_state, definition = self:_entryState(context, entry)
                table.insert(content, PlayCard:new{
                    entry = entry,
                    logo = definition and definition.logo or entry.logo or "app_store",
                    tint = PLAY.icon_tints[(index - 1) % #PLAY.icon_tints + 1],
                    width = card_width, height = card_height,
                    callback = function() self:confirmInstall(instance, context, entry) end,
                    overlap_offset = { margin + (index - 1) * (card_width + card_gap), card_y },
                })
                if entry_state == "update" then
                    table.insert(content, PlayPill:new{
                        title = _("Update"), width = math.floor(card_width * .62), height = scale(26),
                        radius = scale(13),
                        background = PLAY.green, foreground = PLAY.on_green,
                        callback = function() self:confirmInstall(instance, context, entry) end,
                        overlap_offset = { margin + (index - 1) * (card_width + card_gap) + math.floor((card_width - math.floor(card_width * .62)) / 2), card_y + card_height + scale(4) },
                    })
                end
            end
        end

        local category_labels = { all = _("All items"), dapp = _("Apps"), widget = _("Widgets"), design = _("Designs") }
        local section_y = show_shelf and (body_y + scale(24) + card_height + action_row + scale(10)) or body_y
        local section_widget = TextWidget:new{
            text = (query == "" and category_labels[state.category] or (_("Results for ") .. query)) .. string.format("  ·  %d", #visible_entries),
            face = Font:getFace("cfont", scale(16)),
            fgcolor = PLAY.on_surface,
            bold = true,
            max_width = width - 2 * margin,
            padding = 0,
        }
        section_widget.overlap_offset = { margin, section_y }
        table.insert(content, section_widget)

        local list_y = section_y + scale(24)
        local row_width = width - 2 * margin
        local row_height = scale(76)
        local row_gap = scale(6)
        local action_width = math.min(scale(104), math.max(scale(76), math.floor(row_width * .26)))
        local cards = {}
        for index, entry in ipairs(visible_entries) do
            local row_y = (index - 1) * (row_height + row_gap)
            local action_state, definition = self:_entryState(context, entry)
            table.insert(cards, PlayRow:new{
                entry = entry,
                state = action_state,
                logo = definition and definition.logo or entry.logo or "app_store",
                tint = PLAY.icon_tints[(index - 1) % #PLAY.icon_tints + 1],
                width = row_width, height = row_height,
                reserve_right = action_width + gap,
                background = PLAY.background,
                callback = function() self:confirmInstall(instance, context, entry) end,
                overlap_offset = { 0, row_y },
            })
            if action_state == "installed" then
                local action_height = math.floor((row_height - gap) / 2)
                table.insert(cards, PlayPill:new{
                    title = entry.kind == "design" and _("Use") or _("Open"),
                    width = action_width, height = action_height,
                    background = PLAY.background, foreground = PLAY.green,
                    bordersize = scale(1), border_color = PLAY.green,
                    callback = function() self:confirmInstall(instance, context, entry) end,
                    overlap_offset = { row_width - action_width, row_y },
                })
                table.insert(cards, PlayPill:new{
                    title = _("Uninstall"),
                    width = action_width, height = row_height - action_height - gap,
                    background = PLAY.surface, foreground = PLAY.on_variant,
                    callback = function()
                        if entry.kind == "design" then
                            self:confirmUninstallDesign(instance, context, entry, definition)
                        elseif entry.kind == "widget" then
                            self:confirmUninstallWidget(instance, context, entry, definition)
                        else
                            self:confirmUninstall(instance, context, entry, definition)
                        end
                    end,
                    overlap_offset = { row_width - action_width, row_y + action_height + gap },
                })
            else
                table.insert(cards, PlayPill:new{
                    title = action_state == "update" and _("Update") or _("Install"),
                    width = action_width, height = math.max(scale(28), math.floor(row_height * .46)),
                    background = PLAY.green, foreground = PLAY.on_green,
                    callback = function() self:confirmInstall(instance, context, entry) end,
                    overlap_offset = { row_width - action_width, row_y + math.floor((row_height - math.max(scale(28), math.floor(row_height * .46))) / 2) },
                })
            end
        end
        local list_height = math.max(scale(40), list_bottom - list_y)
        local content_height = math.max(list_height, #visible_entries * (row_height + row_gap) - row_gap)
        local list_content = OverlapGroup:new{
            dimen = Geom:new{ w = row_width, h = content_height },
            allow_mirroring = false,
            unpack(cards),
        }
        table.insert(content, ScrollableContainer:new{
            -- ScrollableContainer paints its scrollbar inside its own width.
            -- Reserve that strip outside the actual row width so the trailing
            -- app actions never sit beneath the scrollbar while scrolling.
            dimen = Geom:new{ w = row_width + ScrollableContainer:getScrollbarWidth(), h = list_height },
            -- ScrollableContainer marks its show_parent dirty after every
            -- offset change. Without this, the framebuffer changes but an
            -- E-Ink device may not repaint the moved rows/scrollbar.
            show_parent = context.host,
            list_content,
            overlap_offset = { margin, list_y },
        })
    else
        local title, body, action_title, action
        if not state.refreshed then
            title = _("Load the Play catalog")
            body = _("Read the trusted catalog from ") .. REPOSITORY .. _(" to browse DApps, widgets, and designs.")
            action_title, action = _("Load catalog"), function() self:refresh(instance, context) end
        elseif state.error then
            title = _("Catalog unavailable")
            body = tostring(state.error)
            action_title, action = _("Try again"), function() self:refresh(instance, context) end
        elseif not state.entries or #state.entries == 0 then
            title = _("No store items listed")
            body = _("Add DApp, widget, or design paths to dapps.txt in the catalog repository.")
        elseif #visible_entries == 0 then
            title = _("No matching apps")
            body = query ~= "" and (_("Nothing matches “") .. query .. _("” in this category.")) or _("Change the search or the selected category.")
            action_title, action = _("Clear search"), function() state.query = ""; context.requestRebuild("ui") end
        else
            title = _("Nothing to show")
            body = _("Refresh the catalog to see the latest entries.")
            action_title, action = _("Refresh"), function() self:refresh(instance, context) end
        end
        local card_height = scale(120)
        local card_title = TextWidget:new{
            text = title,
            face = Font:getFace("cfont", scale(16)),
            fgcolor = PLAY.on_surface,
            bold = true,
            max_width = width - 2 * margin - 2 * scale(16),
            padding = 0,
        }
        local card_body = TextWidget:new{
            text = Theme.fitLabel(body, width - 2 * margin - 2 * scale(16), scale(11), 0),
            face = Font:getFace("smallinfofont", scale(11)),
            fgcolor = PLAY.on_variant,
            max_width = width - 2 * margin - 2 * scale(16),
            padding = 0,
        }
        table.insert(content, FrameContainer:new{
            width = width - 2 * margin, height = card_height, padding = 0, bordersize = 0,
            radius = scale(14), background = PLAY.surface,
            Layout.FixedStack:new{
                width = width - 2 * margin, height = card_height,
                entries = {
                    { widget = card_title, x = scale(16), y = scale(16) },
                    { widget = card_body, x = scale(16), y = scale(44) },
                },
            },
            overlap_offset = { margin, body_y },
        })
        if action then
            table.insert(content, PlayPill:new{
                title = action_title, width = math.min(scale(180), width - 2 * margin), height = scale(38),
                background = PLAY.green, foreground = PLAY.on_green,
                callback = action,
                overlap_offset = { margin, body_y + card_height - scale(52) },
            })
        end
    end

    -- Play bottom navigation, used as the category selector.
    local nav_y = height - nav_height
    table.insert(content, FrameContainer:new{
        width = width, height = nav_height, padding = 0, bordersize = 0,
        background = PLAY.background,
        emptySizedWidget(width, nav_height),
        overlap_offset = { 0, nav_y },
    })
    table.insert(content, FrameContainer:new{
        width = width, height = scale(1), padding = 0, bordersize = 0,
        background = PLAY.divider,
        emptySizedWidget(width, scale(1)),
        overlap_offset = { 0, nav_y },
    })
    local tabs = {
        { id = "all", label = _("For you"), icon = "grid" },
        { id = "dapp", label = _("Apps"), icon = "apps" },
        { id = "widget", label = _("Widgets"), icon = "widgets" },
        { id = "design", label = _("Designs"), icon = "designs" },
    }
    local tab_width = math.floor(width / #tabs)
    for index, tab in ipairs(tabs) do
        local active = state.category == tab.id
        local tab_x = (index - 1) * tab_width
        if active then
            local pill_height = nav_height - scale(14)
            table.insert(content, FrameContainer:new{
                width = tab_width - scale(18), height = pill_height, padding = 0, bordersize = 0,
                radius = math.floor(pill_height * .34),
                background = PLAY.green_container,
                emptySizedWidget(tab_width - scale(18), pill_height),
                overlap_offset = { tab_x + scale(9), nav_y + scale(7) },
            })
        end
        table.insert(content, PlayNavTab:new{
            label = tab.label,
            icon = tab.icon,
            active = active,
            width = tab_width, height = nav_height,
            callback = function()
                state.category = tab.id
                context.requestRebuild("ui")
            end,
            overlap_offset = { tab_x, nav_y },
        })
    end

    return WidgetContainer:new{
        dimen = Geom:new{ w = width, h = height },
        content,
    }
end

return AppStore
