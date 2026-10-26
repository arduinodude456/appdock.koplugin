--[[--
A small, explicit-trust AppStore for AppDock DApps.
It reads only a plain-text manifest from the owner-configured GitHub repository.
Catalog refresh never executes remote code; a user confirmation and Lua syntax
check are required before an individual DApp is installed or updated.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local AppDockDialogs = require("appdock_dialogs")
local ConfirmBox = AppDockDialogs.ConfirmBox
local DataStorage = require("datastorage")
local Device = require("device")
local DAppLogo = require("appdock_logo")
local Layout = require("appdock_layout")
local Theme = require("appdock_theme")
local Wallpaper = require("appdock_wallpaper")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Widget = require("ui/widget/widget")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = AppDockDialogs.InputDialog
local AppDockKeyboard = require("appdock_keyboard")
local InfoMessage = AppDockDialogs.InfoMessage
local OverlapGroup = require("ui/widget/overlapgroup")
local TextWidget = require("ui/widget/textwidget")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local MODULE_DIR = (debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "")
local function requireAppDockModule(name)
    local previous_path = package.path
    package.path = MODULE_DIR .. "?.lua;" .. previous_path
    local ok, module = pcall(require, name)
    package.path = previous_path
    return ok and module or nil
end

local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
if not ok_lfs then lfs = require("lfs") end

local Screen = Device.screen
local AppStore = {}
AppStore.__index = AppStore

local REPOSITORY = "https://raw.githubusercontent.com/arduinodude456/DApps/main/"
local MANIFEST_URL = REPOSITORY .. "dapps.txt"
local GAMES_MANIFEST_URL = REPOSITORY .. "games.txt"
local MAX_MANIFEST_BYTES = 128 * 1024
local MAX_DAPP_BYTES = 2 * 1024 * 1024
local MAX_GAME_PACKAGE_BYTES = 32 * 1024 * 1024
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

local fetchText
local function fetchBinary(url, limit) return fetchText(url, limit) end
local function resolveRepositoryAsset(design_source, asset)
    if type(asset) ~= "string" or asset == "" then return asset end
    if asset:sub(1, 8) == "designs/" then return asset end
    local directory = type(design_source) == "string" and design_source:match("^(.*)/[^/]+$") or ""
    return directory ~= "" and (directory .. "/" .. asset) or asset
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
The AppStore uses its own AppDock Store branding with the Google Play layout:
Material-blue palette (readable on grayscale E-Ink), search pill, filter chips,
a hero banner, app rows with install pills and a bottom navigation with an
icon pill.
--]]--

local function playColor(red, green, blue, grayscale)
    if Device.screen:isColorEnabled() then
        return Blitbuffer.ColorRGB32(red, green, blue, 0xFF)
    end
    return grayscale
end

-- Key names (`green`, `on_green`, `green_container`, ...) are kept on purpose:
-- appdock_sleepscreen_catalog receives this table and reads those keys. They now
-- hold the Google Play (Material 3) blue instead of green.
local IS_COLOR = Device.screen:isColorEnabled()
local PLAY = {
    background = playColor(255, 255, 255, Blitbuffer.COLOR_WHITE),
    surface = playColor(240, 244, 249, Blitbuffer.COLOR_LIGHT_GRAY),
    surface_variant = playColor(221, 227, 234, Blitbuffer.COLOR_GRAY_8),
    nav = playColor(240, 244, 249, Blitbuffer.COLOR_WHITE),
    on_surface = playColor(31, 31, 31, Blitbuffer.COLOR_BLACK),
    on_variant = playColor(68, 71, 70, Blitbuffer.COLOR_DARK_GRAY),
    outline = playColor(196, 199, 197, Blitbuffer.COLOR_GRAY),
    divider = playColor(227, 227, 227, Blitbuffer.COLOR_LIGHT_GRAY),
    green = playColor(11, 87, 208, Blitbuffer.COLOR_BLACK),
    on_green = playColor(255, 255, 255, Blitbuffer.COLOR_WHITE),
    green_container = playColor(211, 227, 253, Blitbuffer.COLOR_LIGHT_GRAY),
    on_green_container = playColor(4, 30, 73, Blitbuffer.COLOR_DARK_GRAY),
    icon_tints = {
        playColor(232, 240, 254, Blitbuffer.COLOR_LIGHT_GRAY),
        playColor(230, 246, 235, Blitbuffer.COLOR_LIGHT_GRAY),
        playColor(254, 243, 224, Blitbuffer.COLOR_LIGHT_GRAY),
        playColor(252, 232, 238, Blitbuffer.COLOR_LIGHT_GRAY),
        playColor(240, 235, 251, Blitbuffer.COLOR_LIGHT_GRAY),
    },
}

local function textWidth(text, face_name, size, bold)
    local widget = TextWidget:new{
        text = text,
        face = Font:getFace(face_name, size),
        bold = bold,
        padding = 0,
    }
    local measured = widget:getSize().w
    widget:free()
    return measured
end

local function kindLabel(kind)
    if kind == "widget" then return _("Widget") end
    if kind == "design" then return _("Design") end
    if kind == "game" then return _("Game") end
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
    elseif self.kind == "game" then
        block(.08, .18, .84, .64)
        block(.24, .08, .16, .24)
        block(.60, .08, .16, .24)
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
    elseif self.kind == "back" then
        fillLine(bb, x + size * .14, y + size * .50, x + size * .86, y + size * .50, thickness, ink)
        fillLine(bb, x + size * .14, y + size * .50, x + size * .50, y + size * .14, thickness, ink)
        fillLine(bb, x + size * .14, y + size * .50, x + size * .50, y + size * .86, thickness, ink)
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
    local version = entry.version and (" • v" .. tostring(entry.version)) or ""
    local title = TextWidget:new{
        text = Theme.fitLabel(entry.title or "", text_width, title_size, 0),
        face = Font:getFace("smallinfofont", title_size),
        fgcolor = PLAY.on_surface,
        bold = false,
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
    -- Play shows a small rounded "rating" pill under the metadata. We have no
    -- ratings, so the pill carries the install state, and only when there is
    -- something to say (installed / update) so plain rows stay clean.
    local state_widget
    if self.state == "installed" or self.state == "update" then
        local state_color, state_background = PLAY.on_green_container, PLAY.green_container
        if self.state == "update" then
            state_color, state_background = PLAY.on_green, PLAY.green
        end
        local pill_pad_x, pill_pad_y = scale(8), scale(3)
        local state_text = TextWidget:new{
            text = Theme.fitLabel(actionStateLabel(self.state), text_width - 2 * pill_pad_x, meta_size, 0),
            face = Font:getFace("smallinfofont", meta_size),
            fgcolor = state_color,
            bold = true,
            max_width = text_width - 2 * pill_pad_x,
            padding = 0,
        }
        local pill_height = state_text:getSize().h + 2 * pill_pad_y
        state_widget = FrameContainer:new{
            padding = pill_pad_y,
            padding_left = pill_pad_x,
            padding_right = pill_pad_x,
            bordersize = 0,
            radius = math.floor(pill_height / 2),
            background = state_background,
            state_text,
        }
    end
    -- Stack title / meta / pill from real widget heights (no overlap); the pill
    -- is dropped when the row is too short for it.
    local line_gap = scale(3)
    local title_h, meta_h = title:getSize().h, meta:getSize().h
    local stack_h = title_h + line_gap + meta_h
    if state_widget then
        local with_pill = stack_h + line_gap + state_widget:getSize().h
        if with_pill <= self.height - scale(4) then stack_h = with_pill else state_widget = nil end
    end
    local top_y = math.max(0, math.floor((self.height - stack_h) / 2))
    local title_y = top_y
    local meta_y = title_y + title_h + line_gap
    local state_y = meta_y + meta_h + line_gap
    local tile = FrameContainer:new{
        width = icon_size, height = icon_size, padding = 0, bordersize = 0,
        radius = math.floor(icon_size * .22),
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
    local row_entries = {
        { widget = tile, x = inset, y = math.max(0, math.floor((self.height - icon_size) / 2)) },
        { widget = title, x = text_x, y = title_y },
        { widget = meta, x = text_x, y = meta_y },
    }
    if state_widget then table.insert(row_entries, { widget = state_widget, x = text_x, y = state_y }) end
    self[1] = FrameContainer:new{
        width = self.width, height = self.height, padding = 0, bordersize = 0,
        radius = math.floor(self.height * .22),
        background = self.background or PLAY.background,
        Layout.FixedStack:new{
            width = self.width, height = self.height,
            entries = row_entries,
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

-- Play-style hero banner: big rounded block, badge top-left, title bottom-left.
local PlayBanner = InputContainer:extend{
    entry = nil,
    logo = nil,
    badge = nil,
    width = nil,
    height = nil,
    background = nil,
    foreground = nil,
    callback = nil,
    dimen = nil,
}

function PlayBanner:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local entry = self.entry or {}
    local pad = scale(16)
    local foreground = self.foreground or PLAY.on_green
    local logo_size = math.floor(self.height * .54)
    local text_width = math.max(scale(40), self.width - 2 * pad - logo_size - scale(12))
    local title_size = math.max(scale(13), math.min(scale(20), math.floor(self.height * .15)))
    local sub_size = math.max(scale(9), math.min(scale(12), math.floor(self.height * .105)))
    local version = entry.version and (" • v" .. tostring(entry.version)) or ""
    local title = TextWidget:new{
        text = Theme.fitLabel(entry.title or "", text_width, title_size, 0),
        face = Font:getFace("cfont", title_size),
        fgcolor = foreground,
        bold = true,
        max_width = text_width,
        padding = 0,
    }
    local sub = TextWidget:new{
        text = Theme.fitLabel(kindLabel(entry.kind) .. version, text_width, sub_size, 0),
        face = Font:getFace("smallinfofont", sub_size),
        fgcolor = foreground,
        max_width = text_width,
        padding = 0,
    }
    local sub_y = self.height - pad - sub:getSize().h
    local title_y = sub_y - title:getSize().h - scale(2)
    local entries = {
        {
            widget = DAppLogo:new{ kind = self.logo or "app_store", size = logo_size, ink = foreground },
            x = self.width - pad - logo_size,
            y = math.floor((self.height - logo_size) / 2),
        },
        { widget = title, x = pad, y = title_y },
        { widget = sub, x = pad, y = sub_y },
    }
    if self.badge and self.badge ~= "" then
        local badge_size = math.max(scale(8), math.min(scale(10), math.floor(self.height * .08)))
        local badge_text = TextWidget:new{
            text = self.badge,
            face = Font:getFace("smallinfofont", badge_size),
            fgcolor = PLAY.green,
            bold = true,
            padding = 0,
        }
        local badge_pad = scale(4)
        local badge_height = badge_text:getSize().h + 2 * badge_pad
        table.insert(entries, {
            widget = FrameContainer:new{
                padding = badge_pad,
                padding_left = scale(10),
                padding_right = scale(10),
                bordersize = 0,
                radius = math.floor(badge_height / 2),
                background = PLAY.on_green,
                badge_text,
            },
            x = pad, y = math.floor(pad * .75),
        })
    end
    self[1] = FrameContainer:new{
        width = self.width, height = self.height, padding = 0, bordersize = 0,
        radius = scale(18),
        background = self.background or PLAY.green,
        Layout.FixedStack:new{
            width = self.width, height = self.height,
            entries = entries,
        },
    }
    self.ges_events = { TapPlayBanner = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function PlayBanner:paintTo(bb, x, y)
    local range = self.ges_events.TapPlayBanner[1].range
    range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    return InputContainer.paintTo(self, bb, x, y)
end

function PlayBanner:onTapPlayBanner()
    if self.callback then self.callback() end
    return true
end

-- Hero image of the app page (like the Meowdoku reference): scaled to the full
-- pane width whatever its original size, cropped at the bottom, and blended
-- into white more and more towards the bottom. The result is rendered once
-- into an RGB32 buffer and cached, so rebuilds and repaints stay cheap.
local HERO_FADE_TOP = .35
local hero_cache = { key = nil, bb = nil, previous = nil }

local function buildHeroImage(file, width, height)
    local key = tostring(file) .. ":" .. width .. "x" .. height
    if hero_cache.key == key and hero_cache.bb then return hero_cache.bb end
    local ok, result = pcall(function()
        local RenderImage = require("ui/renderimage")
        local ffi = require("ffi")
        local source = RenderImage:renderImageFile(file, false)
        if not source then error("unreadable image") end
        local source_w, source_h = source:getWidth(), source:getHeight()
        if source_w < 1 or source_h < 1 then
            source:free()
            error("empty image")
        end
        local scaled = source
        if RenderImage.scaleBlitBuffer and source_w ~= width then
            local scaled_h = math.max(1, math.floor(width * source_h / source_w + .5))
            scaled = RenderImage:scaleBlitBuffer(source, width, scaled_h, true) or source
        end
        local out = Blitbuffer.new(width, height, Blitbuffer.TYPE_BBRGB32)
        out:fill(Blitbuffer.COLOR_WHITE)
        local visible_w = math.min(width, scaled:getWidth())
        local visible_h = math.min(height, scaled:getHeight())
        out:blitFrom(scaled, 0, 0, 0, 0, visible_w, visible_h)
        scaled:free()
        local base = ffi.cast("uint8_t*", out.data)
        local stride = out.stride
        local lut = ffi.new("uint8_t[256]")
        local span = math.max(1, visible_h - 1)
        for row = 0, visible_h - 1 do
            local t = row / span
            local alpha = HERO_FADE_TOP + (1 - HERO_FADE_TOP) * t * t
            local offset = 255 * alpha
            for value = 0, 255 do
                lut[value] = math.min(255, math.floor(value * (1 - alpha) + offset + .5))
            end
            local line = base + row * stride
            for column = 0, width * 4 - 1, 4 do
                line[column] = lut[line[column]]
                line[column + 1] = lut[line[column + 1]]
                line[column + 2] = lut[line[column + 2]]
            end
        end
        return out
    end)
    if not ok or not result then return nil end
    -- Keep one older buffer alive: the previous pane may still be painted once.
    if hero_cache.previous then hero_cache.previous:free() end
    hero_cache.previous = hero_cache.bb
    hero_cache.key, hero_cache.bb = key, result
    return result
end

local PlayHeroImage = Widget:extend{
    image = nil,
    width = nil,
    height = nil,
    dimen = nil,
}

function PlayHeroImage:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
end

function PlayHeroImage:paintTo(bb, x, y)
    if self.image then bb:blitFrom(self.image, x, y, 0, 0, self.width, self.height) end
end

-- The buffer belongs to hero_cache, not to the widget.
function PlayHeroImage:free() end

-- One tab of the Play bottom navigation (the AppStore category selector).
local PlayNavTab = InputContainer:extend{
    label = nil,
    icon = "grid",
    active = false,
    show_pill = false,
    width = nil,
    height = nil,
    callback = nil,
    dimen = nil,
}

function PlayNavTab:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local icon_size = math.max(scale(12), math.min(scale(22), math.floor(self.height * .34)))
    local label_size = math.max(scale(8), math.min(scale(11), math.floor(self.height * .19)))
    local foreground = self.active and (self.show_pill and PLAY.on_green_container or PLAY.green) or PLAY.on_variant
    local label = TextWidget:new{
        text = Theme.fitLabel(self.label or "", self.width, label_size, scale(6)),
        face = Font:getFace("smallinfofont", label_size),
        fgcolor = foreground,
        bold = self.active,
        max_width = self.width - scale(6),
        padding = 0,
    }
    local icon_y = math.floor(self.height * (self.show_pill and .17 or .20))
    local label_y = icon_y + icon_size + (self.show_pill and scale(9) or scale(4))
    local entries = {}
    -- Play marks the active destination with a pill behind the ICON only; the
    -- label stays below it. Opt-in so the sleepscreen pane keeps its own look.
    if self.show_pill and self.active then
        local pill_pad = scale(5)
        local pill_height = icon_size + 2 * pill_pad
        local pill_width = math.min(self.width - scale(8), icon_size * 2 + scale(20))
        table.insert(entries, {
            widget = FrameContainer:new{
                width = pill_width, height = pill_height, padding = 0, bordersize = 0,
                radius = math.floor(pill_height / 2),
                background = PLAY.green_container,
                emptySizedWidget(pill_width, pill_height),
            },
            x = math.floor((self.width - pill_width) / 2),
            y = math.max(0, icon_y - pill_pad),
        })
    end
    table.insert(entries, { widget = NavIcon:new{ size = icon_size, kind = self.icon, ink = foreground }, x = math.floor((self.width - icon_size) / 2), y = icon_y })
    table.insert(entries, { widget = label, x = math.max(0, math.floor((self.width - label:getSize().w) / 2)), y = label_y })
    self[1] = Layout.FixedStack:new{
        width = self.width, height = self.height,
        entries = entries,
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

fetchText = function(url, limit)
    local socket_url = require("socket.url")
    local socket = require("socket")
    local socketutil = require("socketutil")
    local parsed = socket_url.parse(url)
    if not parsed or parsed.scheme ~= "https" then return nil, _("Only HTTPS sources are allowed.") end
    local https = require("ssl.https")
    local chunks, received, too_large = {}, 0, false
    local function sink(chunk)
        if chunk then
            received = received + #chunk
            if received > limit then too_large = true; return nil, "response too large" end
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
    if too_large then return nil, _("The file is larger than the allowed download size.") end
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

function AppStore.parseManifest(body, default_kind)
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
        local declared_kind = parts[4] or default_kind
        local kind = declared_kind == "widget" and "widget"
            or (declared_kind == "design" and "design")
            or (declared_kind == "game" and "game")
            or (default_kind == "game" and "game" or "dapp")
        local expected_suffix = kind == "design" and "%.appdock%-design$" or "%.lua$"
        if path ~= "" and path:match("^[%w%._/%-]+$") and path:match(expected_suffix) and not path:find("..", 1, true) and not known[path] then
            known[path] = true
            local name = path:match("([^/]+)%.appdock%-design$") or path:match("([^/]+)%.lua$") or path
            name = name:gsub("[_%-]+", " "):gsub("%f[%a].", string.upper)
            local package = parts[5]
            if kind == "game" and (not package or package == "") then package = path:gsub("%.lua$", ".zip") end
            if package and (not package:match("^[%w%._/%-]+$") or package:find("..", 1, true)) then package = nil end
            table.insert(entries, { path = path, title = name, version = version, logo = logo, kind = kind, package = package })
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
    -- `sleepscreen` is a store surface, not a manifest item kind. Keeping it
    -- separate preserves the existing dapp/widget/design manifest semantics.
    if type(instance.app_store.detail) ~= "table" or type(instance.app_store.detail.path) ~= "string" then
        instance.app_store.detail = nil
    end
    local filter = instance.app_store.filter
    instance.app_store.filter = (filter == "update" or filter == "installed") and filter or "all"
    instance.app_store.category = (category == "dapp" or category == "widget" or category == "design" or category == "game" or category == "sleepscreen") and category or "all"
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
    local categories = { "all", "dapp", "widget", "design", "game", "sleepscreen" }
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
    local games_manifest, games_err = fetchText(GAMES_MANIFEST_URL, MAX_MANIFEST_BYTES)
    state.entries = manifest and games_manifest and AppStore.parseManifest(manifest) or nil
    if state.entries and games_manifest then
        local game_entries = AppStore.parseManifest(games_manifest, "game")
        for _, entry in ipairs(game_entries) do state.entries[#state.entries + 1] = entry end
        table.sort(state.entries, function(left, right) return left.title:lower() < right.title:lower() end)
    end
    state.error = err or games_err
    state.refreshed = true
    state.images = nil
    context.requestRebuild("ui")
end

function AppStore:_storeDirectory()
    local path = DataStorage:getDataDir() .. "/appdock_dapps"
    if lfs.attributes(path, "mode") ~= "directory" then lfs.mkdir(path) end
    return path
end

local function shellQuote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

function AppStore:_addonsDirectory()
    local path = os.getenv("APPDOCK_ADDS_DIR") or "/mnt/onboard/.adds"
    if lfs.attributes(path, "mode") ~= "directory" and not lfs.mkdir(path) then return nil end
    return path
end

local function zipExtractorCommand()
    local probe = io.popen("command -v unzip 2>/dev/null", "r")
    local executable = probe and probe:read("*l")
    if probe then probe:close() end
    if executable and executable ~= "" then return "unzip" end

    probe = io.popen("command -v busybox 2>/dev/null", "r")
    executable = probe and probe:read("*l")
    if probe then probe:close() end
    if executable and executable ~= "" then
        local has_unzip = os.execute("busybox unzip --help >/dev/null 2>&1")
        if has_unzip == true or has_unzip == 0 then return "busybox unzip" end
    end
    return nil
end

function AppStore:installGamePackage(entry)
    local package = entry.package or entry.path:gsub("%.lua$", ".zip")
    local archive, err = fetchBinary(REPOSITORY .. package, MAX_GAME_PACKAGE_BYTES)
    if not archive then return false, err end
    local staging = self:_storeDirectory() .. "/.game-package-" .. entry.path:gsub("[^%w%._%-]", "_") .. ".zip"
    local saved, save_err = saveFile(staging, archive)
    if not saved then return false, save_err end

    local unzip = zipExtractorCommand()
    if not unzip then os.remove(staging); return false, _("No ZIP extractor is available (unzip or BusyBox with unzip).") end
    local list = io.popen(unzip .. " -lq " .. shellQuote(staging) .. " 2>/dev/null", "r")
    if not list then os.remove(staging); return false, _("The ZIP extractor could not inspect the game package.") end
    local entry_count = 0
    for name in list:lines() do
        local path = name:match("^%s*%d+%s+[%d%-]+%s+%d%d?:%d%d%s+(.+)$")
        if path then
            entry_count = entry_count + 1
            local unsafe_parent = path == ".." or path:match("^%.%./") or path:match("/%.%./") or path:match("/%.%.$")
            if path:sub(1, 1) == "/" or path:find("\\", 1, true) or unsafe_parent then
                list:close(); os.remove(staging)
                return false, _("The game package contains an unsafe path.")
            end
        end
    end
    local listed_ok = list:close()
    if (listed_ok ~= true and listed_ok ~= 0) or entry_count == 0 then
        os.remove(staging)
        return false, _("The ZIP extractor could not inspect the game package.")
    end
    local addons = self:_addonsDirectory()
    if not addons then os.remove(staging); return false, _("The .adds directory could not be created.") end
    local tested = os.execute(unzip .. " -tq " .. shellQuote(staging) .. " >/dev/null 2>&1")
    if tested ~= true and tested ~= 0 then os.remove(staging); return false, _("The game package is damaged.") end
    local extracted = os.execute(unzip .. " -oq " .. shellQuote(staging) .. " -d " .. shellQuote(addons) .. " >/dev/null 2>&1")
    os.remove(staging)
    if extracted ~= true and extracted ~= 0 then return false, _("The game package could not be installed into .adds.") end
    -- These packages are produced from FAT/Windows workspaces, so ZIP entries
    -- can lose Unix execute bits and unzip creates mode 0644. Game launchers
    -- follow the catalog convention <game>/bin/<game>.
    local game_name = entry.path:match("([^/]+)%.lua$")
    if not game_name or not game_name:match("^[%w_-]+$") then
        return false, _("The game entry does not identify a valid executable.")
    end
    local executable = addons .. "/" .. game_name .. "/bin/" .. game_name
    if lfs.attributes(executable, "mode") ~= "file" then
        return false, _("The game package does not contain its expected executable.")
    end
    local chmod = os.execute("chmod 755 " .. shellQuote(executable) .. " >/dev/null 2>&1")
    if chmod ~= true and chmod ~= 0 then
        return false, _("The game executable could not be marked as runnable.")
    end
    return true
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
    local is_game = entry.kind == "game"
    local item_name = is_design and _("design") or (is_widget and _("widget") or (is_game and _("game") or _("DApp")))
    local action = is_update and _("Update") or _("Install")
    local message = is_update and (_("Update this installed ") .. item_name .. _(" from your trusted AppDock GitHub repository?\n\n")) or (_("Install this ") .. item_name .. _(" from your trusted AppDock GitHub repository?\n\n"))
    local dialog = ConfirmBox:new{
        text = message .. entry.path .. (is_game and ("\n" .. (entry.package or entry.path:gsub("%.lua$", ".zip"))) or "") .. (entry.version and ("\n\n" .. _("Repository version: ") .. entry.version) or "") .. (is_design and _("\n\nA design is declarative data only. It is validated and applied locally; it never executes code.") or (is_game and _("\n\nThe Lua file and its ZIP package will be downloaded only after you choose this action. The package is extracted into .adds and both files are validated before installation.") or _("\n\nThe file is downloaded only after you choose this action. It will be validated before being added to AppDock."))),
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
        local image, image_err = fetchBinary(REPOSITORY .. resolveRepositoryAsset(entry.path, definition.wallpaper), MAX_WALLPAPER_BYTES)
        if not image then
            UIManager:show(InfoMessage:new{ text = _("Could not download this design background: ") .. tostring(image_err or "") })
            return
        end
        local suffix = definition.wallpaper:match("%.([%w]+)$") or "png"
        wallpaper_file = design_directory .. "/" .. definition.id .. "_wallpaper." .. suffix:lower()
        -- Keep an image suffix on the temporary path: Wallpaper.buildPath
        -- intentionally rejects files whose extensions are not image types.
        local candidate = wallpaper_file .. ".candidate." .. suffix:lower()
        os.remove(candidate)
        local image_saved, image_save_err = saveFile(candidate, image)
        if not image_saved then
            UIManager:show(InfoMessage:new{ text = _("Could not save this design background: ") .. tostring(image_save_err or "") })
            return
        end
        if not Wallpaper.isUsableImage(candidate) then
            os.remove(candidate)
            UIManager:show(InfoMessage:new{ text = _("The downloaded design background is not a readable image.") })
            return
        end
        if not os.rename(candidate, wallpaper_file) then
            os.remove(candidate)
            UIManager:show(InfoMessage:new{ text = _("Could not install this design background.") })
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
    if entry.kind == "game" then
        local package_ok, package_err = self:installGamePackage(entry)
        if not package_ok then
            os.remove(temporary)
            UIManager:show(InfoMessage:new{ text = _("Could not install the game package: ") .. tostring(package_err or "") })
            return
        end
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

function AppStore:_cacheDirectory()
    local path = DataStorage:getDataDir() .. "/appdock_store_cache"
    if lfs.attributes(path, "mode") ~= "directory" then lfs.mkdir(path) end
    return path
end

-- Optional background image of an app: the same repository path as the app
-- file, but with an image suffix (`tools/notes.lua` -> `tools/notes.png` or
-- `tools/notes.jpg`). Every failure (missing file, offline, broken image) ends
-- in "no image"; it must never raise.
function AppStore:_findDetailImage(entry)
    local base = (entry.path:gsub("%.appdock%-design$", ""):gsub("%.lua$", ""))
    local directory = self:_cacheDirectory()
    local suffixes = { "png", "jpg" }
    local function cachePath(remote) return directory .. "/" .. (remote:gsub("[^%w%._%-]", "_")) end
    for index = 1, #suffixes do
        local suffix = suffixes[index]
        local remote = base .. "." .. suffix
        if safeDesignImagePath(remote) then
            local body = fetchBinary(REPOSITORY .. remote, MAX_WALLPAPER_BYTES)
            if body and #body > 0 then
                local target = cachePath(remote)
                local candidate = target .. ".candidate." .. suffix
                os.remove(candidate)
                if saveFile(candidate, body) then
                    if Wallpaper.isUsableImage(candidate) and os.rename(candidate, target) then
                        return target
                    end
                    os.remove(candidate)
                end
            end
        end
    end
    -- Offline fallback: an image fetched in an earlier session.
    for index = 1, #suffixes do
        local remote = base .. "." .. suffixes[index]
        if safeDesignImagePath(remote) then
            local target = cachePath(remote)
            if lfs.attributes(target, "mode") == "file" and Wallpaper.isUsableImage(target) then
                return target
            end
        end
    end
    return nil
end

function AppStore:openDetail(instance, context, entry)
    local state = self:_ensureState(instance)
    state.images = state.images or {}
    if state.images[entry.path] == nil then
        local ok, found = pcall(self._findDetailImage, self, entry)
        state.images[entry.path] = ok and found or false
    end
    state.detail = entry
    context.requestRebuild("ui")
end

function AppStore:closeDetail(instance, context)
    local state = self:_ensureState(instance)
    state.detail = nil
    context.requestRebuild("ui")
end

function AppStore:_appendNav(content, state, context, width, height, nav_height)
    local nav_y = height - nav_height
    table.insert(content, FrameContainer:new{
        width = width, height = nav_height, padding = 0, bordersize = 0,
        background = PLAY.nav,
        emptySizedWidget(width, nav_height),
        overlap_offset = { 0, nav_y },
    })
    local tabs = {
        { id = "all", label = _("For you"), icon = "grid" },
        { id = "dapp", label = _("Apps"), icon = "apps" },
        { id = "game", label = _("Games"), icon = "game" },
        { id = "widget", label = _("Widgets"), icon = "widgets" },
        { id = "design", label = _("Designs"), icon = "designs" },
        { id = "sleepscreen", label = _("Sleepscreens"), icon = "designs" },
    }
    local tab_width = math.floor(width / #tabs)
    for index, tab in ipairs(tabs) do
        local tab_x = (index - 1) * tab_width
        table.insert(content, PlayNavTab:new{
            label = tab.label,
            icon = tab.icon,
            active = state.category == tab.id,
            show_pill = true,
            width = tab_width, height = nav_height,
            callback = function()
                state.category = tab.id
                state.detail = nil
                context.requestRebuild("ui")
            end,
            overlap_offset = { tab_x, nav_y },
        })
    end
end

-- Play-style app page: banner (optional background image), title, stats,
-- install actions. Installing still goes through the confirmation dialog.
function AppStore:buildDetail(instance, context)
    local state = self:_ensureState(instance)
    local entry = state.detail
    local width, height = context.dimen.w, context.dimen.h
    local margin, gap = scale(16), scale(8)
    local nav_height = scale(62)
    local entry_state, definition = self:_entryState(context, entry)
    local logo = definition and definition.logo or entry.logo or "app_store"
    local content = OverlapGroup:new{
        dimen = Geom:new{ w = width, h = height },
        allow_mirroring = false,
        FrameContainer:new{
            width = width, height = height, padding = 0, bordersize = 0,
            background = PLAY.background,
            emptySizedWidget(width, height),
        },
    }

    -- The top part stays free for the art (back button + image); text starts
    -- below it and is drawn over the faded image, as on the Play page.
    local banner_height = math.min(scale(190), math.floor(height * .28))
    local image_path = state.images and state.images[entry.path] or nil

    local back_size = scale(40)
    local back_pill = PlayPill:new{
        glyph = "back", width = back_size, height = back_size,
        radius = math.floor(back_size / 2),
        background = PLAY.background, foreground = PLAY.on_surface,
        callback = function() self:closeDetail(instance, context) end,
        overlap_offset = { scale(10), scale(10) },
    }

    local text_width = width - 2 * margin
    local y = banner_height + scale(14)
    local kind_widget = TextWidget:new{
        text = kindLabel(entry.kind),
        face = Font:getFace("cfont", scale(15)),
        fgcolor = PLAY.green,
        max_width = text_width,
        padding = 0,
    }
    kind_widget.overlap_offset = { margin, y }
    table.insert(content, kind_widget)
    y = y + kind_widget:getSize().h + scale(2)

    local title_size = scale(26)
    local title_widget = TextWidget:new{
        text = Theme.fitLabel(entry.title or "", text_width, title_size, 0),
        face = Font:getFace("cfont", title_size),
        fgcolor = PLAY.on_surface,
        max_width = text_width,
        padding = 0,
    }
    title_widget.overlap_offset = { margin, y }
    table.insert(content, title_widget)
    y = y + title_widget:getSize().h + scale(14)

    -- Stats row: icon tile followed by three value/label columns.
    local tile_size = scale(56)
    table.insert(content, FrameContainer:new{
        width = tile_size, height = tile_size, padding = 0, bordersize = 0,
        radius = math.floor(tile_size * .22),
        background = PLAY.icon_tints[1],
        CenterContainer:new{
            dimen = Geom:new{ w = tile_size, h = tile_size },
            DAppLogo:new{ kind = logo, size = math.floor(tile_size * .62), ink = PLAY.on_surface },
        },
        overlap_offset = { margin, y },
    })
    local stats = {
        { value = entry.version and ("v" .. tostring(entry.version)) or "–", label = _("Version") },
        { value = kindLabel(entry.kind), label = _("Type") },
        { value = actionStateLabel(entry_state), label = _("Status") },
    }
    local stats_x = margin + tile_size + scale(12)
    local column_width = math.floor((width - margin - stats_x) / #stats)
    for index, stat in ipairs(stats) do
        local value_widget = TextWidget:new{
            text = Theme.fitLabel(stat.value, column_width, scale(13), scale(4)),
            face = Font:getFace("cfont", scale(13)),
            fgcolor = PLAY.on_surface,
            bold = true,
            max_width = column_width - scale(4),
            padding = 0,
        }
        local label_widget = TextWidget:new{
            text = Theme.fitLabel(stat.label, column_width, scale(11), scale(4)),
            face = Font:getFace("smallinfofont", scale(11)),
            fgcolor = PLAY.on_variant,
            max_width = column_width - scale(4),
            padding = 0,
        }
        local block_height = value_widget:getSize().h + scale(4) + label_widget:getSize().h
        local block_y = y + math.floor((tile_size - block_height) / 2)
        local column_x = stats_x + (index - 1) * column_width
        value_widget.overlap_offset = { column_x, block_y }
        label_widget.overlap_offset = { column_x, block_y + value_widget:getSize().h + scale(4) }
        table.insert(content, value_widget)
        table.insert(content, label_widget)
    end
    y = y + tile_size + scale(18)

    -- Actions.
    local action_height = scale(42)
    if entry_state == "installed" then
        local action_width = math.min(scale(170), math.floor((text_width - gap) / 2))
        table.insert(content, PlayPill:new{
            title = entry.kind == "design" and _("Use") or _("Open"),
            width = action_width, height = action_height,
            background = PLAY.background, foreground = PLAY.green,
            bordersize = scale(1), border_color = PLAY.green,
            callback = function() self:confirmInstall(instance, context, entry) end,
            overlap_offset = { margin, y },
        })
        table.insert(content, PlayPill:new{
            title = _("Uninstall"),
            width = action_width, height = action_height,
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
            overlap_offset = { margin + action_width + gap, y },
        })
    else
        table.insert(content, PlayPill:new{
            title = entry_state == "update" and _("Update") or _("Install"),
            width = math.min(scale(200), text_width), height = action_height,
            background = PLAY.green, foreground = PLAY.on_green,
            callback = function() self:confirmInstall(instance, context, entry) end,
            overlap_offset = { margin, y },
        })
    end
    y = y + action_height + scale(14)

    local info_size = scale(11)
    for _, line in ipairs({
        entry.path,
        _("Installations, updates, and removals always require an explicit confirmation."),
    }) do
        local info_widget = TextWidget:new{
            text = Theme.fitLabel(line, text_width, info_size, 0),
            face = Font:getFace("smallinfofont", info_size),
            fgcolor = PLAY.on_variant,
            max_width = text_width,
            padding = 0,
        }
        info_widget.overlap_offset = { margin, y }
        table.insert(content, info_widget)
        y = y + info_widget:getSize().h + scale(4)
    end

    -- Art layer goes right above the white page background (index 2), under
    -- all text. No image, or any failure while building it: tinted banner with
    -- the app logo instead.
    local art
    if image_path then
        local hero_height = math.max(banner_height, math.min(height - nav_height, y + scale(24)))
        local hero_bb = buildHeroImage(image_path, width, hero_height)
        if hero_bb then
            art = PlayHeroImage:new{ image = hero_bb, width = width, height = hero_height, overlap_offset = { 0, 0 } }
        end
    end
    if not art then
        local logo_size = math.floor(banner_height * .48)
        art = FrameContainer:new{
            width = width, height = banner_height, padding = 0, bordersize = 0,
            background = PLAY.green_container,
            CenterContainer:new{
                dimen = Geom:new{ w = width, h = banner_height },
                DAppLogo:new{ kind = logo, size = logo_size, ink = PLAY.on_green_container },
            },
            overlap_offset = { 0, 0 },
        }
    end
    table.insert(content, 2, art)

    table.insert(content, back_pill)
    self:_appendNav(content, state, context, width, height, nav_height)
    return WidgetContainer:new{
        dimen = Geom:new{ w = width, h = height },
        content,
    }
end

function AppStore:buildPane(instance, context)
    local state = self:_ensureState(instance)
    -- Sleepscreens have a separate data source and local-draft lifecycle.  The
    -- catalog owns its pane, while this explicit UI table lets it retain the
    -- existing Store bottom-navigation look without depending on private globals.
    if state.category == "sleepscreen" then
        local Catalog = requireAppDockModule("appdock_sleepscreen_catalog")
        if Catalog and Catalog.buildPane then
            return Catalog.buildPane(instance, context, {
                PlayPill = PlayPill,
                PlayNavTab = PlayNavTab,
                PLAY = PLAY,
                scale = scale,
                emptySizedWidget = emptySizedWidget,
            })
        end
        -- A missing optional UI module must not make the established catalog
        -- unusable on an interrupted plugin update.
        state.category = "all"
    end
    if state.detail then
        local ok, pane = pcall(self.buildDetail, self, instance, context)
        if ok and pane then return pane end
        -- A broken detail page must never lock the store: fall back to the list.
        state.detail = nil
    end
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

    -- Top bar in the Play phone layout: store mark on the left (like the Play
    -- logo), one wide search pill, then refresh and the profile avatar.
    local bar_height = scale(56)
    local control_height = scale(44)
    local round_size = scale(36)
    local mark_size = scale(28)
    table.insert(content, DAppLogo:new{
        kind = "app_store",
        size = mark_size,
        ink = PLAY.on_surface,
        overlap_offset = { margin, math.floor((bar_height - mark_size) / 2) },
    })
    local round_y = math.floor((bar_height - round_size) / 2)
    local avatar_x = width - margin - round_size
    local refresh_x = avatar_x - gap - round_size
    local search_x = margin + mark_size + scale(10)
    table.insert(content, PlayPill:new{
        glyph = "search",
        title = query == "" and _("Search for apps & games") or (_("Search: ") .. query),
        width = refresh_x - gap - search_x, height = control_height,
        radius = math.floor(control_height / 2),
        background = PLAY.surface,
        foreground = query == "" and PLAY.on_variant or PLAY.on_surface,
        bold = false,
        callback = function() self:promptSearch(instance, context) end,
        overlap_offset = { search_x, math.floor((bar_height - control_height) / 2) },
    })
    table.insert(content, PlayPill:new{
        glyph = "refresh", width = round_size, height = round_size,
        radius = math.floor(round_size / 2),
        background = PLAY.surface, foreground = PLAY.on_surface,
        callback = function() self:refresh(instance, context) end,
        overlap_offset = { refresh_x, round_y },
    })
    table.insert(content, PlayPill:new{
        title = "A", width = round_size, height = round_size,
        radius = math.floor(round_size / 2),
        background = PLAY.green, foreground = PLAY.on_green,
        callback = function()
            UIManager:show(InfoMessage:new{
                text = _("Trusted AppDock catalog") .. "\n\n" .. REPOSITORY .. "\n\n" .. _("Installations, updates, and removals always require an explicit confirmation."),
            })
        end,
        overlap_offset = { avatar_x, round_y },
    })

    -- Play filter chips ("Top charts", "Premium", ...): here they filter by
    -- install state. Selected = tonal blue (solid on grayscale panels, where
    -- two light grays would look identical).
    local chip_height = scale(34)
    local chip_font = math.max(scale(8), math.min(scale(14), math.floor(chip_height * .40)))
    local chip_selected_bg = IS_COLOR and PLAY.green_container or PLAY.green
    local chip_selected_fg = IS_COLOR and PLAY.on_green_container or PLAY.on_green
    local chip_x = margin
    local chips = {
        { id = "all", label = _("All") },
        { id = "update", label = _("Updates") },
        { id = "installed", label = _("Installed") },
    }
    local active_chip = state.filter or "all"
    for _, chip in ipairs(chips) do
        local active = active_chip == chip.id
        local chip_width = textWidth(chip.label, "smallinfofont", chip_font, active) + scale(38)
        if chip_x + chip_width > width - margin then break end
        table.insert(content, PlayPill:new{
            title = chip.label, width = chip_width, height = chip_height,
            background = active and chip_selected_bg or PLAY.surface,
            foreground = active and chip_selected_fg or PLAY.on_surface,
            bold = active,
            callback = function()
                state.filter = chip.id
                context.requestRebuild("ui")
            end,
            overlap_offset = { chip_x, bar_height },
        })
        chip_x = chip_x + chip_width + gap
    end

    local body_y = bar_height + chip_height + scale(14)
    local nav_height = scale(62)
    local list_bottom = height - nav_height - scale(6)
    local visible_entries = state.entries and AppStore.filterEntries(state.entries, query, state.category) or {}
    if active_chip ~= "all" then
        local filtered = {}
        for _, entry in ipairs(visible_entries) do
            local entry_state = self:_entryState(context, entry)
            if entry_state == "update" or (active_chip == "installed" and entry_state == "installed") then
                filtered[#filtered + 1] = entry
            end
        end
        visible_entries = filtered
    end
    local catalog_ready = state.refreshed and not state.error and state.entries and #state.entries > 0

    if catalog_ready and #visible_entries > 0 then
        -- Hero: first pending update, otherwise the first catalog entry. Hidden
        -- while searching (Play shows plain results then) and on short screens.
        -- Tablet-style layout: as many columns as fit (1-3), like the Play
        -- tablet screenshot with its row of hero cards and the app grid below.
        local columns = math.max(1, math.min(3, math.floor((width - 2 * margin) / scale(290))))
        local column_gap = scale(10)
        local cell_width = math.floor((width - 2 * margin - (columns - 1) * column_gap) / columns)
        local action_label_width = 0
        for _, label in ipairs({ _("Install"), _("Update"), _("Open"), _("Use"), _("Uninstall") }) do
            action_label_width = math.max(action_label_width, textWidth(label, "smallinfofont", scale(14), true))
        end
        local action_pill_width = math.max(scale(76), math.min(scale(130), action_label_width + scale(30)))

        local heroes = {}
        if query == "" then
            for _, entry in ipairs(visible_entries) do
                if #heroes >= columns then break end
                if self:_entryState(context, entry) == "update" then heroes[#heroes + 1] = entry end
            end
            for _, entry in ipairs(visible_entries) do
                if #heroes >= columns then break end
                local already = false
                for _, chosen in ipairs(heroes) do
                    if chosen == entry then already = true end
                end
                if not already then heroes[#heroes + 1] = entry end
            end
        end
        local banner_height = scale(132)
        local hero_row_height = scale(62)
        local hero_gap = scale(8)
        local hero_total = banner_height + hero_gap + hero_row_height
        local show_hero = #heroes > 0 and (list_bottom - body_y) >= hero_total + scale(28) + scale(120)
        local section_y = body_y
        if show_hero then
            local hero_action_height = math.max(scale(28), math.floor(hero_row_height * .58))
            local hero_backgrounds = { PLAY.green, PLAY.on_green_container }
            local hero_row_y = body_y + banner_height + hero_gap
            for hero_index, hero in ipairs(heroes) do
                local hero_state, hero_definition = self:_entryState(context, hero)
                local hero_x = margin + (hero_index - 1) * (cell_width + column_gap)
                local hero_logo = hero_definition and hero_definition.logo or hero.logo or "app_store"
                local function open_hero() self:openDetail(instance, context, hero) end
                local function act_hero() self:confirmInstall(instance, context, hero) end
                table.insert(content, PlayBanner:new{
                    entry = hero, logo = hero_logo,
                    badge = hero_state == "update" and _("Update available") or _("Recommended"),
                    width = cell_width, height = banner_height,
                    background = hero_backgrounds[(hero_index - 1) % #hero_backgrounds + 1],
                    foreground = PLAY.on_green,
                    callback = open_hero,
                    overlap_offset = { hero_x, body_y },
                })
                table.insert(content, PlayRow:new{
                    entry = hero, state = hero_state, logo = hero_logo,
                    tint = PLAY.icon_tints[(hero_index - 1) % #PLAY.icon_tints + 1],
                    width = cell_width, height = hero_row_height,
                    reserve_right = action_pill_width + gap,
                    background = PLAY.background,
                    callback = open_hero,
                    overlap_offset = { hero_x, hero_row_y },
                })
                local hero_action_y = hero_row_y + math.floor((hero_row_height - hero_action_height) / 2)
                local hero_action_x = hero_x + cell_width - action_pill_width
                if hero_state == "installed" then
                    table.insert(content, PlayPill:new{
                        title = hero.kind == "design" and _("Use") or _("Open"),
                        width = action_pill_width, height = hero_action_height,
                        background = PLAY.background, foreground = PLAY.green,
                        bordersize = scale(1), border_color = PLAY.green,
                        callback = act_hero,
                        overlap_offset = { hero_action_x, hero_action_y },
                    })
                else
                    table.insert(content, PlayPill:new{
                        title = hero_state == "update" and _("Update") or _("Install"),
                        width = action_pill_width, height = hero_action_height,
                        background = PLAY.green, foreground = PLAY.on_green,
                        callback = act_hero,
                        overlap_offset = { hero_action_x, hero_action_y },
                    })
                end
            end
            section_y = hero_row_y + hero_row_height + scale(18)
        end

        local category_labels = { all = _("Suggested for you"), dapp = _("Apps"), game = _("Games"), widget = _("Widgets"), design = _("Designs") }
        local section_widget = TextWidget:new{
            text = (query == "" and category_labels[state.category] or (_("Results for ") .. query)) .. string.format("  •  %d", #visible_entries),
            face = Font:getFace("cfont", scale(17)),
            fgcolor = PLAY.on_surface,
            bold = false,
            max_width = width - 2 * margin,
            padding = 0,
        }
        section_widget.overlap_offset = { margin, section_y }
        table.insert(content, section_widget)

        local list_y = section_y + scale(30)
        local row_width = width - 2 * margin
        local row_height = columns > 1 and scale(84) or scale(76)
        local row_gap = scale(6)
        local action_width = action_pill_width
        local cards = {}
        for index, entry in ipairs(visible_entries) do
            local row_y = math.floor((index - 1) / columns) * (row_height + row_gap)
            local action_state, definition = self:_entryState(context, entry)
            if columns > 1 then
                -- Grid cell like Play's "Suggested for you": no buttons, a tap
                -- opens the app page where install/open/uninstall live.
                table.insert(cards, PlayRow:new{
                    entry = entry,
                    state = action_state,
                    logo = definition and definition.logo or entry.logo or "app_store",
                    tint = PLAY.icon_tints[(index - 1) % #PLAY.icon_tints + 1],
                    width = cell_width, height = row_height,
                    reserve_right = 0,
                    background = PLAY.background,
                    callback = function() self:openDetail(instance, context, entry) end,
                    overlap_offset = { ((index - 1) % columns) * (cell_width + column_gap), row_y },
                })
            else
            table.insert(cards, PlayRow:new{
                entry = entry,
                state = action_state,
                logo = definition and definition.logo or entry.logo or "app_store",
                tint = PLAY.icon_tints[(index - 1) % #PLAY.icon_tints + 1],
                width = row_width, height = row_height,
                reserve_right = action_width + gap,
                background = PLAY.background,
                callback = function() self:openDetail(instance, context, entry) end,
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
        end
        local list_height = math.max(scale(40), list_bottom - list_y)
        local grid_rows = math.ceil(#visible_entries / columns)
        local content_height = math.max(list_height, grid_rows * (row_height + row_gap) - row_gap)
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
            body = _("Read the trusted catalogs from ") .. REPOSITORY .. _(" to browse apps, games, widgets, and designs.")
            action_title, action = _("Load catalog"), function() self:refresh(instance, context) end
        elseif state.error then
            title = _("Catalog unavailable")
            body = tostring(state.error)
            action_title, action = _("Try again"), function() self:refresh(instance, context) end
        elseif not state.entries or #state.entries == 0 then
            title = _("No store items listed")
            body = _("Add DApp, game, widget, or design paths to dapps.txt or games.txt in the catalog repository.")
        elseif #visible_entries == 0 then
            title = _("No matching apps")
            body = query ~= "" and (_("Nothing matches “") .. query .. _("” in this category.")) or _("Change the search or the selected category.")
            action_title, action = _("Clear search"), function() state.query = ""; state.filter = "all"; context.requestRebuild("ui") end
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
    self:_appendNav(content, state, context, width, height, nav_height)

    return WidgetContainer:new{
        dimen = Geom:new{ w = width, h = height },
        content,
    }
end

return AppStore
