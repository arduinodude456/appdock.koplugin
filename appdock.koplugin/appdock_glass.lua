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
    if value == nil then
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

-- Blurred, darkened copy of whatever is currently on screen ---------------------
function Glass.buildBackdrop(bb, width, height)
    local ok, copy = pcall(function()
        local buffer = Blitbuffer.new(width, height, bb:getType())
        buffer:blitFrom(bb, 0, 0, 0, 0, width, height)
        return buffer
    end)
    if not ok or not copy then return nil end
    local result = copy
    if isColor() then
        local ok_ri, RenderImage = pcall(require, "ui/renderimage")
        if ok_ri and RenderImage and RenderImage.scaleBlitBuffer then
            local ok_blur, blurred = pcall(function()
                -- Shrink hard, then grow in two smooth steps: a large soft blur.
                local tiny = RenderImage:scaleBlitBuffer(copy, math.max(6, math.floor(width / 26)), math.max(6, math.floor(height / 26)), true)
                local mid = RenderImage:scaleBlitBuffer(tiny, math.max(12, math.floor(width / 7)), math.max(12, math.floor(height / 7)), true)
                return RenderImage:scaleBlitBuffer(mid, width, height, true)
            end)
            if ok_blur and blurred then
                result = blurred
            else
                -- scaleBlitBuffer may already have freed the copy: re-grab it.
                local ok_again, again = pcall(function()
                    local buffer = Blitbuffer.new(width, height, bb:getType())
                    buffer:blitFrom(bb, 0, 0, 0, 0, width, height)
                    return buffer
                end)
                if ok_again and again then result = again else return nil end
            end
        end
    end
    local tint = Glass.COLORS.tint
    if isColor() and result.blendRectRGB32 then
        local value = nativeColor(tint)
        if value then pcall(result.blendRectRGB32, result, 0, 0, width, height, value) end
    else
        pcall(result.paintRect, result, 0, 0, width, height, Blitbuffer.COLOR_BLACK)
    end
    return result
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
