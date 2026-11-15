--[[--
AppDock card skins (9.7.0).

Every card type of the homescreen can be restyled on its own:

    kind "app"     app icon plates (also the dock)
    kind "info"    the Device / Continue-reading cards
    kind "widget"  Store widget cards

A card is either
    * "theme"  - whatever the active theme brings (nothing for the classic
                 themes, a chamfered neon look for the Cyber theme),
    * "shape"  - a drawn shape (rounded, square, chamfer, cyber, hex, pill,
                 circle, brackets, frameless), or
    * "image"  - a picture of the reader's choice, clipped to that shape.

Settings live in settings.skin:
    { effects = "auto" | "on" | "off",         -- Cyber decoration
      app = { mode, shape, image, dim }, info = {...}, widget = {...} }

Everything is painted from row spans, so a shape costs a handful of paintRect
calls and works on color and grayscale panels alike. Nothing animates.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Geom = require("ui/geometry")
local Theme = require("appdock_theme")
local Wallpaper = require("appdock_wallpaper")
local Widget = require("ui/widget/widget")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local Screen = Device.screen

local Skin = {}

Skin.KINDS = { "app", "info", "widget" }

-- Shapes the reader can pick. `circle` only makes sense for square plates.
Skin.SHAPES = {
    { id = "rounded", title = "Rounded" },
    { id = "square", title = "Square" },
    { id = "chamfer", title = "Chamfer (cut corners)" },
    { id = "cyber", title = "Cyber (diagonal cut)" },
    { id = "hex", title = "Hexagon" },
    { id = "pill", title = "Pill" },
    { id = "circle", title = "Circle" },
    { id = "brackets", title = "Corner brackets" },
    { id = "frameless", title = "Frameless" },
}

local SHAPE_IDS = {}
for _, shape in ipairs(Skin.SHAPES) do SHAPE_IDS[shape.id] = true end

-- What the Cyber theme uses while a kind is left on "theme".
local CYBER_SHAPE = { app = "cyber", info = "chamfer", widget = "cyber" }

Skin.DIM_STEPS = { 0, 25, 50, 75 }

local function scale(value)
    return Screen:scaleBySize(value)
end

local function clamp(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

----------------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------------

local function skinSettings(appdock)
    local settings = appdock and appdock.settings or nil
    local skin = settings and settings.skin or nil
    return type(skin) == "table" and skin or {}
end

-- Bring a stored settings table into a known shape. Called when settings load
-- and after every change, so the rest of the module can trust the fields.
function Skin.normalize(skin)
    skin = type(skin) == "table" and skin or {}
    local result = {}
    result.effects = (skin.effects == "on" or skin.effects == "off") and skin.effects or "auto"
    for _, kind in ipairs(Skin.KINDS) do
        local raw = type(skin[kind]) == "table" and skin[kind] or {}
        local mode = (raw.mode == "shape" or raw.mode == "image") and raw.mode or "theme"
        local dim = tonumber(raw.dim)
        if dim then dim = clamp(math.floor(dim / 25 + .5) * 25, 0, 75) end
        result[kind] = {
            mode = mode,
            shape = SHAPE_IDS[raw.shape] and raw.shape or "rounded",
            image = Wallpaper.isValidPath(raw.image) and raw.image or "",
            dim = dim,
        }
    end
    return result
end

function Skin.isCyberActive(appdock)
    local settings = appdock and appdock.settings or nil
    local effects = skinSettings(appdock).effects
    if effects == "off" then return false end
    if effects == "on" then return true end
    if not settings then return false end
    -- An installed Store design brings its own look; never layer neon on it.
    if Theme.getActiveDesign(settings) then return false end
    local selected = Theme.resolveDefinition(settings)
    return selected == "cyber"
end

local function readable(path)
    local file = io.open(path, "rb")
    if not file then return false end
    file:close()
    return true
end

-- Returns nil when the card keeps its classic rendering, otherwise
-- { kind, shape, image, dim, cyber }.
function Skin.resolve(appdock, kind)
    local skin = skinSettings(appdock)
    local cfg = type(skin[kind]) == "table" and skin[kind] or {}
    local cyber = Skin.isCyberActive(appdock)
    local mode = cfg.mode or "theme"
    local shape = SHAPE_IDS[cfg.shape] and cfg.shape or "rounded"
    local image = nil
    if mode == "image" and Wallpaper.isValidPath(cfg.image) and readable(cfg.image) then
        image = cfg.image
        -- A picture without an explicit shape keeps the theme's silhouette.
        if cfg.shape == nil or (cfg.shape == "rounded" and cyber) then shape = cyber and CYBER_SHAPE[kind] or "rounded" end
    elseif mode == "shape" then
        -- keep `shape`
    else
        if not cyber then return nil end
        shape = CYBER_SHAPE[kind] or "chamfer"
    end
    if not image and shape == "rounded" and not cyber then return nil end
    local dim = tonumber(cfg.dim)
    if dim == nil then dim = image and (kind == "app" and 25 or 35) or 0 end
    return { kind = kind, mode = mode, shape = shape, image = image, dim = dim, cyber = cyber }
end

----------------------------------------------------------------------------
-- Geometry: row spans
----------------------------------------------------------------------------

-- Returns f(row) -> x0, x1 (inclusive, relative to the box) or nil, for a box
-- of w x h. `cut` is the corner size in pixels (chamfer / cyber / hex depth,
-- or the radius of rounded corners).
local function makeSpans(shape, w, h, cut)
    cut = math.max(0, math.floor(cut or 0))
    if shape == "chamfer" then
        return function(row)
            local d = math.max(0, cut - row, cut - (h - 1 - row))
            if d * 2 >= w then return nil end
            return d, w - 1 - d
        end
    elseif shape == "cyber" then
        return function(row)
            local left = math.max(0, cut - (h - 1 - row))
            local right = math.max(0, cut - row)
            if left + right >= w then return nil end
            return left, w - 1 - right
        end
    elseif shape == "hex" then
        local half = (h - 1) / 2
        local depth = math.min(cut, math.floor(w / 2) - 1)
        return function(row)
            local t = half > 0 and math.abs(row - half) / half or 0
            local d = math.floor(depth * t + .5)
            if d * 2 >= w then return nil end
            return d, w - 1 - d
        end
    elseif shape == "pill" or shape == "circle" then
        local radius = math.min(w, h) / 2
        local centre = (h - 1) / 2
        return function(row)
            local dy = math.abs(row - centre)
            if dy > radius then return nil end
            local d = math.floor(radius - math.sqrt(math.max(0, radius * radius - dy * dy)) + .5)
            if d * 2 >= w then return nil end
            return d, w - 1 - d
        end
    elseif shape == "rounded" then
        local radius = math.max(0, math.min(cut, math.floor(math.min(w, h) / 2)))
        return function(row)
            local edge = math.min(row, h - 1 - row)
            local d = 0
            if edge < radius then
                local dy = radius - edge - .5
                d = math.floor(radius - math.sqrt(math.max(0, radius * radius - dy * dy)) + .5)
            end
            if d * 2 >= w then return nil end
            return d, w - 1 - d
        end
    end
    -- square, brackets, frameless
    return function() return 0, w - 1 end
end

Skin._makeSpans = makeSpans

-- Corner size used for a plate of this size (pixels).
local function cutFor(shape, w, h)
    local base = math.min(w, h)
    if shape == "rounded" then return math.floor(base * .30) end
    if shape == "hex" then return math.floor(base * .26) end
    return clamp(math.floor(base * .22), 4, scale(28))
end

-- Calls fn(x0, x1, row0, row1) for every group of consecutive rows that share
-- the same span, so a rectangle costs one call and an arc only a few.
local function forRuns(spans, h, fn)
    local run_x0, run_x1, run_start
    for row = 0, h - 1 do
        local x0, x1 = spans(row)
        if x0 ~= run_x0 or x1 ~= run_x1 then
            if run_x0 then fn(run_x0, run_x1, run_start, row - 1) end
            run_x0, run_x1, run_start = x0, x1, row
        end
    end
    if run_x0 then fn(run_x0, run_x1, run_start, h - 1) end
end

local function fillShape(bb, x, y, w, h, spans, color)
    if not color then return end
    forRuns(spans, h, function(x0, x1, r0, r1)
        bb:paintRect(x + x0, y + r0, x1 - x0 + 1, r1 - r0 + 1, color)
    end)
end

-- Outline of thickness `border` that follows the span function: rows on the
-- top/bottom edge are filled completely, the rest only left and right pieces.
-- `inner` is the span function of the box inset by `border`.
local function strokeShape(bb, x, y, w, h, spans, inner, border, color)
    if not color or border <= 0 then return end
    local limit = h - 1 - border
    for row = 0, h - 1 do
        local x0, x1 = spans(row)
        if x0 then
            local ix0, ix1
            if row >= border and row <= limit then ix0, ix1 = inner(row - border) end
            if ix0 then
                local left, right = border + ix0, border + ix1
                if left > x0 then bb:paintRect(x + x0, y + row, left - x0, 1, color) end
                if x1 > right then bb:paintRect(x + right + 1, y + row, x1 - right, 1, color) end
            else
                bb:paintRect(x + x0, y + row, x1 - x0 + 1, 1, color)
            end
        end
    end
end

local function innerCut(shape, cut, border)
    if shape == "rounded" then return math.max(0, cut - border) end
    return math.max(0, cut - math.floor(border * .586))
end

Skin._test = { forRuns = forRuns, cutFor = cutFor }

----------------------------------------------------------------------------
-- Image cache (cover-fit, decoded once per path/size/mtime)
----------------------------------------------------------------------------

local lfs_ok, lfs = pcall(require, "libs/libkoreader-lfs")
local IMAGE_BYTE_LIMIT = 8 * 1024 * 1024
local image_cache, image_order, image_bytes = {}, {}, 0

local function dropImage(key)
    local entry = image_cache[key]
    if not entry then return end
    image_cache[key] = nil
    image_bytes = image_bytes - entry.bytes
    pcall(function() entry.bb:free() end)
    for index = #image_order, 1, -1 do
        if image_order[index] == key then table.remove(image_order, index) break end
    end
end

function Skin.clearCache()
    while #image_order > 0 do dropImage(image_order[1]) end
end

local function hexToRgb(hex)
    hex = Theme.normalizeHex(hex) or "#808080"
    return tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16)
end

-- Flattens `source` onto the veil color and fades it towards that color by
-- `dim` percent. Doing this once on the cached bitmap avoids any per-paint
-- alpha blending (and any dependency on Blitbuffer blend helpers).
local function flatten(source, w, h, veil_hex, dim)
    local rgb = Blitbuffer.new(w, h, Blitbuffer.TYPE_BBRGB32)
    rgb:blitFrom(source, 0, 0, 0, 0, w, h)
    source:free()
    local vr, vg, vb = hexToRgb(veil_hex)
    local keep = 1 - clamp((tonumber(dim) or 0) / 100, 0, 1)
    pcall(function()
        for row = 0, h - 1 do
            local pixels = rgb:getPixelP(0, row)
            for col = 0, w - 1 do
                local p = pixels[col]
                local a = p.alpha / 255
                local f = a * keep
                p.r = math.floor(p.r * f + vr * (1 - f) + .5)
                p.g = math.floor(p.g * f + vg * (1 - f) + .5)
                p.b = math.floor(p.b * f + vb * (1 - f) + .5)
                p.alpha = 255
            end
        end
    end)
    return rgb
end

local function loadCover(path, w, h, veil_hex, dim)
    if not Wallpaper.isValidPath(path) or w < 2 or h < 2 then return nil end
    local stamp = ""
    if lfs_ok and lfs and lfs.attributes then
        local attr = lfs.attributes(path)
        if type(attr) ~= "table" or attr.mode ~= "file" then return nil end
        stamp = tostring(attr.modification) .. ":" .. tostring(attr.size)
    end
    local key = table.concat({ path, w, h, stamp, tostring(veil_hex), tostring(dim) }, "|")
    local entry = image_cache[key]
    if entry then
        for index = #image_order, 1, -1 do
            if image_order[index] == key then
                table.remove(image_order, index)
                image_order[#image_order + 1] = key
                break
            end
        end
        return entry.bb
    end
    local ok, bb = pcall(function()
        local RenderImage = require("ui/renderimage")
        -- Bound the decoded size first (a phone photo is far larger than a
        -- card), then crop to the card's aspect ratio and scale exactly.
        local limit = clamp(math.max(w, h) * 2, 64, 1200)
        local source = RenderImage:renderImageFile(path, false, limit, limit)
        if not source then return nil end
        local sw, sh = source:getWidth(), source:getHeight()
        local factor = math.max(w / sw, h / sh)
        local cw = math.min(sw, math.max(1, math.floor(w / factor + .5)))
        local ch = math.min(sh, math.max(1, math.floor(h / factor + .5)))
        local cx, cy = math.floor((sw - cw) / 2), math.floor((sh - ch) / 2)
        local crop = Blitbuffer.new(cw, ch, source:getType())
        crop:blitFrom(source, 0, 0, cx, cy, cw, ch)
        source:free()
        local scaled = RenderImage:scaleBlitBuffer(crop, w, h, true)
        return flatten(scaled, w, h, veil_hex, dim)
    end)
    if not ok or not bb then return nil end
    local bytes = w * h * 4
    image_cache[key] = { bb = bb, bytes = bytes }
    image_order[#image_order + 1] = key
    image_bytes = image_bytes + bytes
    while image_bytes > IMAGE_BYTE_LIMIT and #image_order > 1 do dropImage(image_order[1]) end
    return bb
end

----------------------------------------------------------------------------
-- Colors
----------------------------------------------------------------------------

local function roles(appdock)
    local palette = Theme.getPalette(appdock)
    return palette, palette.hex or {}
end

local function toColor(hex, fallback)
    if not hex then return fallback end
    return Theme.toColor(hex, fallback or Blitbuffer.COLOR_GRAY)
end

local function blackBorders(appdock)
    local beta = appdock and appdock.settings and appdock.settings.beta
    return beta and beta.black_borders == true or false
end

----------------------------------------------------------------------------
-- Cyber decoration
----------------------------------------------------------------------------

local function bar(bb, x, y, w, h, color)
    if w > 0 and h > 0 then bb:paintRect(x, y, w, h, color) end
end

-- L-shaped corner mark. (sx, sy) are +1/-1: the direction the arms extend.
local function cornerMark(bb, cx, cy, length, thick, sx, sy, color)
    local hx = sx > 0 and cx or cx - length + 1
    local vy = sy > 0 and cy or cy - length + 1
    local hy = sy > 0 and cy or cy - thick + 1
    local vx = sx > 0 and cx or cx - thick + 1
    bar(bb, hx, hy, length, thick, color)
    bar(bb, vx, vy, thick, length, color)
end

local function decorateCyber(bb, x, y, w, h, shape, cut, border, accent, accent_dim, scan, kind)
    local thick = math.max(2, scale(2))
    local gap = border + math.max(2, scale(3))
    local length = clamp(math.floor(math.min(w, h) * .24), scale(8), scale(26))
    if shape == "brackets" then
        cornerMark(bb, x + 1, y + 1, length, thick, 1, 1, accent)
        cornerMark(bb, x + w - 2, y + 1, length, thick, -1, 1, accent)
        cornerMark(bb, x + 1, y + h - 2, length, thick, 1, -1, accent)
        cornerMark(bb, x + w - 2, y + h - 2, length, thick, -1, -1, accent)
        return
    end
    if scan and h >= scale(40) then
        local step = math.max(4, scale(4))
        local right = x + w
        for row = gap + step, h - gap - 1, step do
            local x0 = (shape == "cyber") and math.max(0, cut - (h - 1 - row)) or 0
            local x1 = (shape == "cyber") and math.max(0, cut - row) or 0
            bar(bb, x + gap + x0, y + row, w - 2 * gap - x0 - x1, 1, scan)
        end
    end
    -- Two opposite corners carry a bright mark; with the diagonal cut they are
    -- the two corners that remain square.
    cornerMark(bb, x + gap, y + gap, length, thick, 1, 1, accent)
    cornerMark(bb, x + w - 1 - gap, y + h - 1 - gap, length, thick, -1, -1, accent)
    -- Data pips on wide cards, like a HUD readout.
    if kind ~= "app" and w >= scale(110) and h >= scale(52) then
        local pip_h = math.max(2, scale(3))
        local px = x + w - gap - (shape == "cyber" and cut or 0) - scale(8)
        local py = y + gap
        for index = 1, 3 do
            local pw = scale(12) - (index - 1) * scale(3)
            bar(bb, px - pw, py, pw, pip_h, index == 1 and accent or accent_dim)
            px = px - pw - scale(3)
        end
    end
end

----------------------------------------------------------------------------
-- Plate widget: fill / image / outline / decoration around one child
----------------------------------------------------------------------------

local SkinPlate = WidgetContainer:extend{
    cfg = nil,
    appdock = nil,
    width = nil,
    height = nil,
    fill = nil,         -- Blitbuffer color of the face
    fill_hex = nil,
    selected = false,
}

function SkinPlate:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
end

function SkinPlate:getSize()
    return self.dimen
end

function SkinPlate:paintTo(bb, x, y)
    local w, h = self.width, self.height
    local cfg = self.cfg
    local shape = cfg.shape
    local palette, hex = roles(self.appdock)
    local black = blackBorders(self.appdock)
    local cut = cutFor(shape, w, h)
    local spans = makeSpans(shape, w, h, cut)
    local frameless = shape == "frameless" or shape == "brackets"

    local border = black and scale(1) or math.max(2, scale(2))
    if self.selected then border = math.max(border, scale(3)) end
    local accent = toColor(hex.primary, palette.primary)
    local border_color
    if black then border_color = Blitbuffer.COLOR_BLACK
    elseif self.selected then border_color = palette.on_primary
    elseif cfg.cyber then border_color = accent
    else border_color = palette.outline end

    if not frameless then
        fillShape(bb, x, y, w, h, spans, self.fill or palette.surface)
    end
    if cfg.image then
        local cover = loadCover(cfg.image, w, h, self.fill_hex or hex.surface, cfg.dim)
        if cover then
            forRuns(spans, h, function(x0, x1, r0, r1)
                bb:blitFrom(cover, x + x0, y + r0, x0, r0, x1 - x0 + 1, r1 - r0 + 1)
            end)
        end
    end

    -- The child (icon, card text, store widget) sits on top of the face.
    WidgetContainer.paintTo(self, bb, x, y)

    if not frameless then
        local inner = makeSpans(shape, w - 2 * border, h - 2 * border, innerCut(shape, cut, border))
        strokeShape(bb, x, y, w, h, spans, inner, border, border_color)
    end
    if cfg.cyber then
        local accent_dim = toColor(Theme.mixHex(hex.primary or "#00F0FF", hex.background or "#000000", .45), palette.secondary)
        local scan
        if Screen:isColorEnabled() and not palette.high_contrast then
            scan = toColor(Theme.mixHex(hex.primary or "#00F0FF", hex.surface or "#000000", .12), nil)
        end
        pcall(decorateCyber, bb, x, y, w, h, shape, cut, border, accent, accent_dim, scan, cfg.kind)
    end
end

-- Builds a plate around `content` (a widget of the plate's own size). Returns
-- nil when the card has no skin so callers keep their classic frame.
function Skin.plate(appdock, kind, opts)
    local cfg = Skin.resolve(appdock, kind)
    if not cfg then return nil end
    if opts.prefer_circle and (cfg.mode ~= "shape" or cfg.shape == "rounded") then cfg.shape = "circle" end
    local ok, plate = pcall(function()
        return SkinPlate:new{
            cfg = cfg, appdock = appdock, width = opts.width, height = opts.height,
            fill = opts.fill, fill_hex = opts.fill_hex, selected = opts.selected == true, opts.content,
        }
    end)
    if not ok then return nil end
    return plate, cfg
end

----------------------------------------------------------------------------
-- Shadow (neon offset in Cyber, hard gray shadow otherwise)
----------------------------------------------------------------------------

local SkinShadow = Widget:extend{
    cfg = nil,
    appdock = nil,
    width = nil,
    height = nil,
}

function SkinShadow:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
end

function SkinShadow:getSize()
    return self.dimen
end

function SkinShadow:paintTo(bb, x, y)
    local palette, hex = roles(self.appdock)
    local color = palette.surface_variant
    if self.cfg.cyber and hex.primary then
        color = toColor(Theme.mixHex(hex.primary, hex.background or "#000000", .38), color)
    end
    local cut = cutFor(self.cfg.shape, self.width, self.height)
    fillShape(bb, x, y, self.width, self.height, makeSpans(self.cfg.shape, self.width, self.height, cut), color)
end

-- Returns a shadow widget (to be inserted at x+depth, y+depth) or nil when the
-- card has no skin or its shape casts none.
function Skin.shadow(appdock, kind, width, height, force_shape)
    if blackBorders(appdock) then return nil end
    local cfg = Skin.resolve(appdock, kind)
    if not cfg then return nil end
    if force_shape then cfg.shape = force_shape end
    if cfg.shape == "frameless" or cfg.shape == "brackets" then return nil end
    local ok, shadow = pcall(function()
        return SkinShadow:new{ cfg = cfg, appdock = appdock, width = width, height = height }
    end)
    if not ok then return nil end
    return shadow
end

----------------------------------------------------------------------------
-- Settings helpers used by the menu
----------------------------------------------------------------------------

function Skin.describe(appdock, kind)
    local skin = skinSettings(appdock)
    local cfg = type(skin[kind]) == "table" and skin[kind] or {}
    if cfg.mode == "image" and cfg.image and cfg.image ~= "" then
        return "image", (cfg.image:match("([^/\\]+)$") or cfg.image)
    elseif cfg.mode == "shape" then
        return "shape", cfg.shape or "rounded"
    end
    return "theme", nil
end

function Skin.shapeTitle(id)
    for _, shape in ipairs(Skin.SHAPES) do
        if shape.id == id then return shape.title end
    end
    return id
end

return Skin
