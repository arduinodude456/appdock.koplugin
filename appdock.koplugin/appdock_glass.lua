--[[--
AppDock "glass" look for the quick settings shade.

* anti-aliased translucent pills / circles (row based alpha blending)
* vector icons rasterised once through a small signed-distance renderer, so
  they stay crisp and white on dark glass at any size (no PNG assets needed)
* a cheap backdrop blur: the screen below the shade is captured once,
  shrunk and enlarged again (smooth scaling) and tinted dark navy

Everything degrades gracefully on grayscale screens (opaque grays, no blur).
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Geom = require("ui/geometry")
local Widget = require("ui/widget/widget")

local Screen = Device.screen
local Glass = {}

local function isColor()
    local ok, value = pcall(Screen.isColorEnabled, Screen)
    return ok and value == true
end
Glass.isColor = isColor

-- Colours ----------------------------------------------------------------
function Glass.rgba(r, g, b, a, gray)
    return { r = r, g = g, b = b, a = a or 255, gray = gray or Blitbuffer.COLOR_DARK_GRAY }
end
local rgba = Glass.rgba

Glass.COLORS = {
    -- values measured from the reference screenshots
    tint        = rgba(4, 10, 34, 158, Blitbuffer.COLOR_BLACK),
    glass       = rgba(78, 92, 138, 104, Blitbuffer.COLOR_GRAY_4),
    glass_hi    = rgba(120, 134, 182, 120, Blitbuffer.COLOR_GRAY_6),
    active      = rgba(172, 58, 0, 255, Blitbuffer.COLOR_WHITE),
    fill        = rgba(214, 214, 228, 255, Blitbuffer.COLOR_GRAY_D),
    white       = rgba(255, 255, 255, 255, Blitbuffer.COLOR_WHITE),
    white_soft  = rgba(255, 255, 255, 170, Blitbuffer.COLOR_GRAY_D),
    sub_inactive = rgba(178, 187, 212, 255, Blitbuffer.COLOR_GRAY_D),
    sub_active  = rgba(244, 205, 188, 255, Blitbuffer.COLOR_BLACK),
    slider_icon = rgba(92, 98, 120, 255, Blitbuffer.COLOR_DARK_GRAY),
    on_active   = rgba(255, 255, 255, 255, Blitbuffer.COLOR_BLACK),
    battery_in  = rgba(10, 16, 38, 255, Blitbuffer.COLOR_BLACK),
    pager       = rgba(236, 236, 246, 200, Blitbuffer.COLOR_GRAY_D),
}

local native_cache = {}
local function nativeColor(c, alpha)
    local a = math.max(0, math.min(255, math.floor((alpha or c.a) + .5)))
    local key = c.r .. "," .. c.g .. "," .. c.b .. "," .. a
    local value = native_cache[key]
    -- ColorRGB32 values have a device-specific __eq metamethod which may
    -- dereference its other operand even when comparing against nil.
    if type(value) == "nil" then
        local ok, made = pcall(Blitbuffer.ColorRGB32, c.r, c.g, c.b, a)
        value = ok and made or false
        native_cache[key] = value
    end
    return value or nil
end

-- Opaque colour usable as TextWidget fgcolor / FrameContainer background.
function Glass.solid(c)
    if isColor() then
        local value = nativeColor(c, 255)
        if value then return value end
    end
    return c.gray
end

local function fillRun(bb, x, y, w, c, cover)
    if w <= 0 then return end
    cover = cover or 1
    if isColor() and bb.blendRectRGB32 then
        local alpha = c.a * cover
        if alpha < 1 then return end
        local value = nativeColor(c, alpha)
        if value then
            bb:blendRectRGB32(x, y, w, 1, value)
            return
        end
    end
    if cover >= 0.5 then bb:paintRect(x, y, w, 1, c.gray) end
end

-- Rounded shapes -----------------------------------------------------------
-- clip_w (optional) cuts the shape with a straight vertical edge, which is
-- how Android draws the fill of its slider pills.
function Glass.drawShape(bb, x, y, width, height, radius, c, clip_w)
    width, height = math.floor(width), math.floor(height)
    if width < 1 or height < 1 then return end
    radius = math.max(0, math.min(radius or 0, width / 2, height / 2))
    for row = 0, height - 1 do
        local yc = row + .5
        local dy = 0
        if yc < radius then dy = radius - yc
        elseif yc > height - radius then dy = yc - (height - radius) end
        local inset = 0
        if dy > 0 then inset = radius - math.sqrt(math.max(0, radius * radius - dy * dy)) end
        local left, right = inset, width - inset
        if clip_w and right > clip_w then right = clip_w end
        if right > left then
            local first = math.ceil(left)
            local last = math.floor(right)
            if last > first then fillRun(bb, x + first, y + row, last - first, c, 1) end
            local left_cover = first - left
            if left_cover > 0.04 and first - 1 >= 0 then fillRun(bb, x + first - 1, y + row, 1, c, left_cover) end
            local right_cover = right - last
            if right_cover > 0.04 and last >= first then fillRun(bb, x + last, y + row, 1, c, right_cover) end
        end
    end
end

-- Vector icons ----------------------------------------------------------------
local function rad(deg) return deg * math.pi / 180 end

local function newBuilder()
    local prims = {}
    local B = { prims = prims }
    function B.seg(ax, ay, bx, by, hw)
        local pad = hw + 0.03
        prims[#prims + 1] = {
            t = "seg", ax = ax, ay = ay, bx = bx, by = by, hw = hw,
            len2 = (bx - ax) ^ 2 + (by - ay) ^ 2,
            x0 = math.min(ax, bx) - pad, x1 = math.max(ax, bx) + pad,
            y0 = math.min(ay, by) - pad, y1 = math.max(ay, by) + pad,
        }
    end
    function B.poly(points, hw, closed)
        for i = 1, #points - 1 do B.seg(points[i][1], points[i][2], points[i + 1][1], points[i + 1][2], hw) end
        if closed then B.seg(points[#points][1], points[#points][2], points[1][1], points[1][2], hw) end
    end
    function B.arc(cx, cy, r, a0, a1, hw)
        local steps = math.max(6, math.ceil(math.abs(a1 - a0) / 9))
        local px, py
        for i = 0, steps do
            local a = rad(a0 + (a1 - a0) * i / steps)
            local x, y = cx + r * math.cos(a), cy - r * math.sin(a)
            if px then B.seg(px, py, x, y, hw) end
            px, py = x, y
        end
    end
    function B.arrow(cx, cy, r, a0, a1, len, hw)
        local dir = (a1 >= a0) and 1 or -1
        local a = rad(a1)
        local ex, ey = cx + r * math.cos(a), cy - r * math.sin(a)
        local tx, ty = dir * -math.sin(a), dir * -math.cos(a)
        local bx, by = -tx, -ty
        for _, theta in ipairs({ rad(38), rad(-38) }) do
            local rx = bx * math.cos(theta) - by * math.sin(theta)
            local ry = bx * math.sin(theta) + by * math.cos(theta)
            B.seg(ex, ey, ex + rx * len, ey + ry * len, hw)
        end
    end
    function B.disc(cx, cy, r)
        local pad = r + 0.03
        prims[#prims + 1] = { t = "disc", cx = cx, cy = cy, r = r, x0 = cx - pad, x1 = cx + pad, y0 = cy - pad, y1 = cy + pad }
    end
    function B.crescent(cx, cy, r, cx2, cy2, r2)
        local pad = r + 0.03
        prims[#prims + 1] = { t = "crescent", cx = cx, cy = cy, r = r, cx2 = cx2, cy2 = cy2, r2 = r2,
            x0 = cx - pad, x1 = cx + pad, y0 = cy - pad, y1 = cy + pad }
    end
    function B.corner()
        prims[#prims + 1] = { t = "corner", x0 = -1, x1 = 2, y0 = -1, y1 = 2 }
    end
    return B
end

local ICONS = {}
local HW = 0.05

ICONS.wifi = function(B)
    B.arc(.5, .80, .62, 45, 135, HW)
    B.arc(.5, .80, .38, 45, 135, HW)
    B.disc(.5, .80, .075)
end
ICONS.bluetooth = function(B)
    B.poly({ { .5, .10 }, { .5, .90 } }, .045)
    B.poly({ { .5, .10 }, { .74, .32 }, { .27, .70 } }, .045)
    B.poly({ { .5, .90 }, { .74, .68 }, { .27, .30 } }, .045)
end
ICONS.headphones = function(B)
    B.arc(.5, .56, .35, 0, 180, HW)
    B.seg(.15, .58, .15, .80, .08)
    B.seg(.85, .58, .85, .80, .08)
end
ICONS.sun = function(B)
    B.arc(.5, .5, .17, 0, 360, .045)
    for k = 0, 7 do
        local a = rad(k * 45)
        B.seg(.5 + .30 * math.cos(a), .5 - .30 * math.sin(a), .5 + .44 * math.cos(a), .5 - .44 * math.sin(a), .045)
    end
end
ICONS.rotate = function(B)
    B.arc(.5, .5, .30, 25, 155, HW); B.arrow(.5, .5, .30, 25, 155, .17, HW)
    B.arc(.5, .5, .30, 205, 335, HW); B.arrow(.5, .5, .30, 205, 335, .17, HW)
end
ICONS.refresh = function(B)
    B.arc(.5, .5, .32, 75, -215, HW); B.arrow(.5, .5, .32, 75, -215, .18, HW)
end
ICONS.power = function(B)
    B.arc(.5, .55, .33, 125, 415, HW)
    B.seg(.5, .12, .5, .52, HW)
end
ICONS.moon = function(B) B.crescent(.52, .5, .36, .70, .38, .30) end
ICONS.battery = function(B)
    B.poly({ { .12, .30 }, { .80, .30 }, { .80, .70 }, { .12, .70 } }, .045, true)
    B.seg(.89, .43, .89, .57, .04)
    B.seg(.24, .50, .56, .50, .09)
end
ICONS.image = function(B)
    B.poly({ { .14, .22 }, { .86, .22 }, { .86, .78 }, { .14, .78 } }, .045, true)
    B.poly({ { .14, .72 }, { .40, .46 }, { .56, .64 }, { .66, .54 }, { .86, .74 } }, .04)
    B.disc(.68, .38, .06)
end
ICONS.gear = function(B)
    B.arc(.5, .5, .15, 0, 360, .05)
    B.arc(.5, .5, .29, 0, 360, .045)
    for k = 0, 7 do
        local a = rad(k * 45)
        B.seg(.5 + .30 * math.cos(a), .5 - .30 * math.sin(a), .5 + .42 * math.cos(a), .5 - .42 * math.sin(a), .065)
    end
end
ICONS.pencil = function(B)
    B.poly({ { .46, .18 }, { .18, .18 }, { .18, .82 }, { .82, .82 }, { .82, .54 } }, .045)
    B.seg(.78, .14, .44, .48, .075)
    B.seg(.44, .48, .40, .60, .03)
end
ICONS.bolt = function(B)
    B.seg(.60, .06, .30, .54, .06)
    B.seg(.30, .54, .70, .46, .06)
    B.seg(.70, .46, .40, .94, .06)
end
ICONS.corner = function(B) B.corner() end

function Glass.hasIcon(kind) return ICONS[kind] ~= nil end

local function coverage(p, u, v, size)
    if u < p.x0 or u > p.x1 or v < p.y0 or v > p.y1 then return 0 end
    local d
    if p.t == "seg" then
        local t = 0
        if p.len2 > 0 then
            t = ((u - p.ax) * (p.bx - p.ax) + (v - p.ay) * (p.by - p.ay)) / p.len2
            if t < 0 then t = 0 elseif t > 1 then t = 1 end
        end
        local dx = p.ax + t * (p.bx - p.ax) - u
        local dy = p.ay + t * (p.by - p.ay) - v
        d = math.sqrt(dx * dx + dy * dy) - p.hw
    elseif p.t == "disc" then
        d = math.sqrt((u - p.cx) ^ 2 + (v - p.cy) ^ 2) - p.r
    elseif p.t == "crescent" then
        local outer = math.sqrt((u - p.cx) ^ 2 + (v - p.cy) ^ 2) - p.r
        local inner = p.r2 - math.sqrt((u - p.cx2) ^ 2 + (v - p.cy2) ^ 2)
        d = math.max(outer, inner)
    else -- corner: filled right triangle (1,0) (1,1) (0,1)
        d = math.max((1 - u - v) / 1.4142, u - 1, v - 1)
    end
    local a = .5 - d * size
    if a <= 0 then return 0 elseif a >= 1 then return 1 end
    return a
end

local runs_cache = {}
local function iconRuns(kind, size)
    local key = kind .. "|" .. size
    local runs = runs_cache[key]
    if runs then return runs end
    runs = {}
    local build = ICONS[kind]
    if build then
        local B = newBuilder()
        build(B)
        local inv = 1 / size
        for j = 0, size - 1 do
            local v = (j + .5) * inv
            local run_start, run_alpha
            for i = 0, size do
                local alpha = 0
                if i < size then
                    local u = (i + .5) * inv
                    for _, p in ipairs(B.prims) do
                        local a = coverage(p, u, v, size)
                        if a > alpha then alpha = a; if alpha >= 1 then break end end
                    end
                    alpha = math.floor(alpha * 8 + .5) / 8
                end
                if run_alpha and alpha ~= run_alpha then
                    if run_alpha > 0 then runs[#runs + 1] = { x = run_start, y = j, len = i - run_start, a = run_alpha } end
                    run_alpha = nil
                end
                if not run_alpha then run_start, run_alpha = i, alpha end
            end
        end
    end
    runs_cache[key] = runs
    return runs
end

function Glass.drawIcon(bb, x, y, size, kind, c)
    size = math.max(4, math.floor(size))
    for _, run in ipairs(iconRuns(kind, size)) do
        fillRun(bb, x + run.x, y + run.y, run.len, c, run.a)
    end
end

-- Blurred + tinted copy of whatever is currently on screen -------------------
-- True backdrop blur: the captured screen is shrunk and enlarged again with
-- smooth scaling (twice, so the result is a soft gaussian-like blur), then
-- tinted dark navy on colour screens. Every step is guarded: a failed blur
-- falls back to a plain tinted copy, and a failed copy returns nil so the
-- caller can use the frosted veil. Quick Settings must always open.
local function smoothScale(src, w, h)
    w, h = math.max(1, math.floor(w)), math.max(1, math.floor(h))
    local ok_mod, RenderImage = pcall(require, "ui/renderimage")
    if ok_mod and type(RenderImage) == "table" and RenderImage.scaleBlitBuffer then
        local ok, out = pcall(RenderImage.scaleBlitBuffer, RenderImage, src, w, h, false)
        if ok and out and out ~= src then return out end
    end
    if src.scale then
        local ok, out = pcall(src.scale, src, w, h)
        if ok and out and out ~= src then return out end
    end
    return nil
end

-- Pure-Lua fallback for builds without smooth scaling: sample a coarse grid
-- and paint bilinear-interpolated blocks. Slower, but runs once per opening.
local function manualBlur(src, width, height)
    local step = 8
    local cols, rows = math.ceil(width / step) + 1, math.ceil(height / step) + 1
    local grid = {}
    local box = step
    for j = 0, rows - 1 do
        local row = {}
        for i = 0, cols - 1 do
            local r, g, b, n = 0, 0, 0, 0
            for dy = -1, 1 do
                for dx = -1, 1 do
                    local px = math.max(0, math.min(width - 1, i * step + dx * box))
                    local py = math.max(0, math.min(height - 1, j * step + dy * box))
                    local c = src:getPixel(px, py)
                    local rgb = c.getColorRGB32 and c:getColorRGB32() or c
                    local cr = rgb.r or rgb.a or 0
                    local cg = rgb.g or rgb.a or 0
                    local cb = rgb.b or rgb.a or 0
                    r, g, b, n = r + cr, g + cg, b + cb, n + 1
                end
            end
            row[i] = { r / n, g / n, b / n }
        end
        grid[j] = row
    end
    local out = Blitbuffer.new(width, height, src:getType())
    local sub = 4
    for y = 0, height - 1, sub do
        local gy = y / step
        local j0 = math.floor(gy)
        local fy = gy - j0
        local j1 = math.min(rows - 1, j0 + 1)
        for x = 0, width - 1, sub do
            local gx = x / step
            local i0 = math.floor(gx)
            local fx = gx - i0
            local i1 = math.min(cols - 1, i0 + 1)
            local a, b, c, d = grid[j0][i0], grid[j0][i1], grid[j1][i0], grid[j1][i1]
            local r = (a[1] * (1 - fx) + b[1] * fx) * (1 - fy) + (c[1] * (1 - fx) + d[1] * fx) * fy
            local g = (a[2] * (1 - fx) + b[2] * fx) * (1 - fy) + (c[2] * (1 - fx) + d[2] * fx) * fy
            local bl = (a[3] * (1 - fx) + b[3] * fx) * (1 - fy) + (c[3] * (1 - fx) + d[3] * fx) * fy
            local color = Blitbuffer.ColorRGB32(math.floor(r + .5), math.floor(g + .5), math.floor(bl + .5), 255)
            out:paintRect(x, y, math.min(sub, width - x), math.min(sub, height - y), color)
        end
    end
    return out
end

local function blurBuffer(src, width, height)
    -- Two shrink/enlarge cycles: 1/10 and 1/28 of the screen resolution.
    local small = smoothScale(src, width / 10, height / 10)
    if small then
        local smaller = smoothScale(small, width / 28, height / 28)
        local base = smaller or small
        local up = smoothScale(base, width / 6, height / 6)
        if smaller and up then
            if small.free then pcall(small.free, small) end
            if base.free then pcall(base.free, base) end
            base = up
        elseif up then
            if base.free then pcall(base.free, base) end
            base = up
        elseif smaller and small.free then
            pcall(small.free, small)
        end
        local full = smoothScale(base, width, height)
        if base.free then pcall(base.free, base) end
        if full then return full end
    end
    local ok, out = pcall(manualBlur, src, width, height)
    if ok and out then return out end
    return nil
end

function Glass.buildBackdrop(bb, width, height, src_x, src_y)
    width, height = math.floor(width), math.floor(height)
    src_x, src_y = src_x or 0, src_y or 0
    local ok, result = pcall(function()
        local copy = Blitbuffer.new(width, height, bb:getType())
        copy:blitFrom(bb, 0, 0, src_x, src_y, width, height)
        local blurred = blurBuffer(copy, width, height)
        if blurred then
            if blurred:getType() ~= copy:getType() then
                local converted = Blitbuffer.new(width, height, copy:getType())
                converted:blitFrom(blurred, 0, 0, 0, 0, width, height)
                if blurred.free then pcall(blurred.free, blurred) end
                blurred = converted
            end
            if copy.free then pcall(copy.free, copy) end
            copy = blurred
        end
        if isColor() and copy.blendRectRGB32 then
            local value = nativeColor(Glass.COLORS.tint)
            if value then copy:blendRectRGB32(0, 0, width, height, value) end
        else
            -- Grayscale panels: keep the soft blurred page visible under a
            -- light veil so the gray glass shapes remain readable.
            local veil = Blitbuffer.new(width, height, copy:getType())
            veil:fill(Blitbuffer.COLOR_WHITE)
            if copy.addblitFrom then pcall(copy.addblitFrom, copy, veil, 0, 0, 0, 0, width, height, .45) end
            if veil.free then pcall(veil.free, veil) end
        end
        return copy
    end)
    if ok and result then return result end
    return nil
end

-- Widgets ---------------------------------------------------------------------------
local GlassShape = Widget:extend{ width = 0, height = 0, radius = 0, color = nil, clip_w = nil }
function GlassShape:init() self.dimen = Geom:new{ w = self.width, h = self.height } end
function GlassShape:getSize() return self.dimen end
function GlassShape:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    Glass.drawShape(bb, x, y, self.width, self.height, self.radius, self.color or Glass.COLORS.glass, self.clip_w)
end
Glass.Shape = GlassShape

local GlassIcon = Widget:extend{ kind = "wifi", size = 32, color = nil }
function GlassIcon:init() self.dimen = Geom:new{ w = self.size, h = self.size } end
function GlassIcon:getSize() return self.dimen end
function GlassIcon:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    Glass.drawIcon(bb, x, y, self.size, self.kind, self.color or Glass.COLORS.white)
end
Glass.Icon = GlassIcon

return Glass
