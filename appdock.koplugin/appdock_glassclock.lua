--[[--
Liquid Glass digits for the AppDock lockscreen and the standby screen.

The digits themselves are the glass, not a card behind them:

  * the glyphs are rasterised once into a coverage mask,
  * an exact Euclidean distance field (Felzenszwalb) tells every pixel how
    far it is from the digit's edge,
  * near the edge the background is *refracted* (sampled from a displaced
    position, with a slight colour split on colour panels), like a thick
    lens bending the wallpaper behind it,
  * a bright rim light (strongest where the edge faces the light and where
    it faces away), a hairline edge, an inner highlight and a soft drop
    shadow give the glass its depth,
  * the flat middle of each stroke is a faint frosted tint that is a touch
    brighter at the top.

Everything is computed once per text and cached as a small bitmap that is
blitted on every repaint. The shading itself (`GlassClock.shade`) is pure
Lua on plain callbacks, so it can be tested off-device. If anything fails on
a device, the widget falls back to plain white digits.
--]]--

local ffi = require("ffi")

local GlassClock = {}

local INF = 1e12

----------------------------------------------------------------------
-- Exact Euclidean distance transform (squared), in place.
-- `f` is a double[w*h] holding 0 for feature pixels and INF elsewhere.
----------------------------------------------------------------------
local function edt2d(f, w, h)
    local n = math.max(w, h)
    local v = ffi.new("int32_t[?]", n + 2)
    local z = ffi.new("double[?]", n + 3)
    local col = ffi.new("double[?]", n + 2)
    local out = ffi.new("double[?]", n + 2)
    local BIG = INF * 4

    local function pass(len)
        local k = 0
        v[0] = 0
        z[0] = -BIG
        z[1] = BIG
        for q = 1, len - 1 do
            local s
            while true do
                local vk = v[k]
                s = ((col[q] + q * q) - (col[vk] + vk * vk)) / (2 * q - 2 * vk)
                if s <= z[k] and k > 0 then k = k - 1 else break end
            end
            k = k + 1
            v[k] = q
            z[k] = s
            z[k + 1] = BIG
        end
        k = 0
        for q = 0, len - 1 do
            while z[k + 1] < q do k = k + 1 end
            local vk = v[k]
            out[q] = (q - vk) * (q - vk) + col[vk]
        end
    end

    for x = 0, w - 1 do
        for y = 0, h - 1 do col[y] = f[y * w + x] end
        pass(h)
        for y = 0, h - 1 do f[y * w + x] = out[y] end
    end
    for y = 0, h - 1 do
        local base = y * w
        for x = 0, w - 1 do col[x] = f[base + x] end
        pass(w)
        for x = 0, w - 1 do f[base + x] = out[x] end
    end
end

-- Signed distance in pixels: positive inside the glyph, negative outside,
-- zero on the edge. Built from the 0.5 coverage contour.
local function signedDistance(cov, w, h)
    local n = w * h
    local inside = ffi.new("double[?]", n)
    local outside = ffi.new("double[?]", n)
    for i = 0, n - 1 do
        if cov[i] >= 0.5 then
            inside[i], outside[i] = INF, 0
        else
            inside[i], outside[i] = 0, INF
        end
    end
    edt2d(inside, w, h)
    edt2d(outside, w, h)
    local sd = ffi.new("float[?]", n)
    for i = 0, n - 1 do
        if cov[i] >= 0.5 then
            sd[i] = math.sqrt(inside[i]) - 0.5
        else
            sd[i] = -(math.sqrt(outside[i]) - 0.5)
        end
    end
    return sd
end

----------------------------------------------------------------------
-- Look
----------------------------------------------------------------------
local LIGHT_X, LIGHT_Y = -0.50, -0.866  -- towards the light: up and left

-- Pad around the glyphs so refraction, rim and shadow never hit the border.
function GlassClock.padFor(size)
    return math.max(6, math.ceil(size * 0.17))
end

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

--[[--
Shades one text.

args:
  w, h       tile size in pixels
  cov        double/float[w*h] glyph coverage 0..1
  size       font size in pixels (all effect widths scale with it)
  color      true on colour panels (colour split, subtler body tint)
  sample(x, y)            -> r, g, b of the untouched background (clamped)
  put(x, y, r, g, b)      write one opaque pixel
  span(y, x0, x1, r, g, b, a)  blend colour (alpha 0..1) over a run of
                          background pixels (inclusive x0..x1)
--]]--
function GlassClock.shade(args)
    local w, h, cov, size = args.w, args.h, args.cov, args.size
    local sample, put, span = args.sample, args.put, args.span
    local color = args.color ~= false
    local sd = signedDistance(cov, w, h)

    local R = math.max(3, math.floor(size * 0.060 + 0.5))        -- rim / lens depth
    local SR = math.max(4, math.floor(size * 0.075 + 0.5))       -- shadow reach
    local off = math.max(1, math.floor(size * 0.026 + 0.5))      -- shadow drop
    local mmax = math.min(R * 1.7, size * 0.10)                -- max refraction
    local contrast = color and 1 or 1.7

    local function shadowAlpha(x, y)
        local sy = y - off
        if sy < 0 then return 0 end
        local d = sd[sy * w + x]
        if d > 0 then d = 0 end
        local ds = -d
        if ds >= SR then return 0 end
        local k = 1 - ds / SR
        return (color and 0.34 or 0.62) * k * k
    end

    local function body(y)
        local yn = y / math.max(1, h - 1)
        return clamp(0.12 + 0.11 * (1 - yn) + (contrast - 1) * 0.18, 0, 0.7)
    end

    local floor = math.floor
    for y = 0, h - 1 do
        local run0
        local interior_a = body(y)
        for x = 0, w - 1 do
            local i = y * w + x
            local c = cov[i]
            local in_run = false
            if c > 0.004 then
                local d = sd[i]
                if d < 0 then d = 0 end
                if c >= 0.996 and d > R + 1 then
                    in_run = true
                    if not run0 then run0 = x end
                else
                    -- gradient of the distance field -> outward normal
                    local x1, x2 = x - 2, x + 2
                    local y1, y2 = y - 2, y + 2
                    if x1 < 0 then x1 = 0 end
                    if x2 > w - 1 then x2 = w - 1 end
                    if y1 < 0 then y1 = 0 end
                    if y2 > h - 1 then y2 = h - 1 end
                    local gx = (sd[y * w + x2] - sd[y * w + x1]) / math.max(1, x2 - x1)
                    local gy = (sd[y2 * w + x] - sd[y1 * w + x]) / math.max(1, y2 - y1)
                    local glen = math.sqrt(gx * gx + gy * gy)
                    local nx, ny, facing = 0, 0, 0
                    if glen > 0.12 then
                        nx, ny = -gx / glen, -gy / glen     -- outward
                        facing = nx * LIGHT_X + ny * LIGHT_Y
                    end
                    local t = clamp(d / R, 0, 1)
                    local inv = 1 - t

                    -- Refraction: look through the lens at a displaced spot.
                    local m = mmax * inv * inv
                    local r, g, b
                    if color then
                        local rx = clamp(floor(x + nx * m * 1.14 + 0.5), 0, w - 1)
                        local ry = clamp(floor(y + ny * m * 1.14 + 0.5), 0, h - 1)
                        local gx2 = clamp(floor(x + nx * m + 0.5), 0, w - 1)
                        local gy2 = clamp(floor(y + ny * m + 0.5), 0, h - 1)
                        local bx = clamp(floor(x + nx * m * 0.86 + 0.5), 0, w - 1)
                        local by = clamp(floor(y + ny * m * 0.86 + 0.5), 0, h - 1)
                        r = select(1, sample(rx, ry))
                        g = select(2, sample(gx2, gy2))
                        b = select(3, sample(bx, by))
                    else
                        local sx = clamp(floor(x + nx * m + 0.5), 0, w - 1)
                        local sy = clamp(floor(y + ny * m + 0.5), 0, h - 1)
                        r, g, b = sample(sx, sy)
                    end

                    -- Slightly deeper tint right at the lens border.
                    local dk = 0.10 * inv * math.sqrt(inv)
                    r, g, b = r * (1 - dk), g * (1 - dk), b * (1 - dk)

                    -- Frosted body.
                    local ba = interior_a
                    r, g, b = r + (255 - r) * ba, g + (255 - g) * ba, b + (255 - b) * ba

                    -- Rim light: strong where the edge faces the light, and
                    -- a weaker bounce on the opposite side.
                    local I
                    if facing > 0 then I = 0.38 + 0.62 * facing * facing
                    else I = 0.34 + 0.46 * facing * facing end
                    local rim = I * inv * inv
                    local hair = clamp(1 - d / 1.9, 0, 1) * 0.70
                    local ra = clamp(rim * 0.92 + hair * (0.55 + 0.45 * I), 0, 1)
                    if not color then ra = clamp(ra * 1.1, 0, 1) end
                    r, g, b = r + (255 - r) * ra, g + (255 - g) * ra, b + (255 - b) * ra

                    -- Inner highlight band on the lit side.
                    if facing > 0 and t < 1 then
                        local e = (t - 0.62) / 0.16
                        local ih = 0.17 * facing * math.exp(-e * e)
                        r, g, b = r + 255 * ih, g + 255 * ih, b + 255 * ih
                    end

                    -- Composite over the (shadowed) untouched background.
                    local br, bg, bb2 = sample(x, y)
                    if c < 0.996 then
                        local sa = shadowAlpha(x, y)
                        if sa > 0 then br, bg, bb2 = br * (1 - sa), bg * (1 - sa), bb2 * (1 - sa) end
                        r = br + (r - br) * c
                        g = bg + (g - bg) * c
                        b = bb2 + (b - bb2) * c
                    end
                    put(x, y, clamp(floor(r + 0.5), 0, 255), clamp(floor(g + 0.5), 0, 255), clamp(floor(b + 0.5), 0, 255))
                end
            else
                local sa = shadowAlpha(x, y)
                if sa > 0.01 then
                    local br, bg, bb2 = sample(x, y)
                    put(x, y, floor(br * (1 - sa) + 0.5), floor(bg * (1 - sa) + 0.5), floor(bb2 * (1 - sa) + 0.5))
                end
            end
            if not in_run and run0 then
                span(y, run0, x - 1, 238, 244, 255, interior_a)
                run0 = nil
            end
        end
        if run0 then span(y, run0, w - 1, 238, 244, 255, interior_a) end
    end
end

----------------------------------------------------------------------
-- KOReader glue
----------------------------------------------------------------------

-- Reads the glyph coverage into a double[w*h] mask. `paint(mask)` draws
-- black text onto the white 8-bit buffer it receives.
local function maskFromPaint(paint, w, h)
    local Blitbuffer = require("ffi/blitbuffer")
    local mask = Blitbuffer.new(w, h, Blitbuffer.TYPE_BB8)
    mask:fill(Blitbuffer.COLOR_WHITE)
    paint(mask)
    local cov = ffi.new("double[?]", w * h)
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            local px = mask:getPixel(x, y)
            if px.getColor8 then px = px:getColor8() end
            cov[y * w + x] = (255 - (px.a or 255)) / 255
        end
    end
    if mask.free then pcall(mask.free, mask) end
    return cov
end

-- Builds the glass tile for the text drawn by `paint(mask)` on top of what
-- `bb` currently shows at (x, y). Returns a blitbuffer of w*h or raises.
function GlassClock.buildTile(bb, x, y, w, h, paint, size, color)
    local Blitbuffer = require("ffi/blitbuffer")
    local cov = maskFromPaint(paint, w, h)
    local src = Blitbuffer.new(w, h, bb:getType())
    src:blitFrom(bb, 0, 0, x, y, w, h)
    local tile = Blitbuffer.new(w, h, bb:getType())
    tile:blitFrom(src, 0, 0, 0, 0, w, h)

    local function sample(px, py)
        local c = src:getPixel(px, py)
        local rgb = c.getColorRGB32 and c:getColorRGB32() or c
        local r = rgb.r or rgb.a or 0
        return r, rgb.g or rgb.a or r, rgb.b or rgb.a or r
    end
    local function put(px, py, r, g, b)
        tile:setPixel(px, py, Blitbuffer.ColorRGB32(r, g, b, 255))
    end
    local function span(py, x0, x1, r, g, b, a)
        if x1 < x0 then return end
        if tile.blendRectRGB32 then
            tile:blendRectRGB32(x0, py, x1 - x0 + 1, 1, Blitbuffer.ColorRGB32(r, g, b, math.floor(a * 255 + 0.5)))
            return
        end
        for px = x0, x1 do
            local sr, sg, sb = sample(px, py)
            put(px, py, math.floor(sr + (r - sr) * a + 0.5), math.floor(sg + (g - sg) * a + 0.5), math.floor(sb + (b - sb) * a + 0.5))
        end
    end

    local ok, err = pcall(GlassClock.shade, {
        w = w, h = h, cov = cov, size = size, color = color,
        sample = sample, put = put, span = span,
    })
    for _, buffer in ipairs({ src }) do if buffer.free then pcall(buffer.free, buffer) end end
    if not ok then
        if tile.free then pcall(tile.free, tile) end
        error(err)
    end
    return tile
end

-- Widget -------------------------------------------------------------------
-- One line of glass digits. Place it in an OverlapGroup; it reads the
-- background it sits on the first time it is painted.
local function newLayerClass()
    local Widget = require("ui/widget/widget")
    local Geom = require("ui/geometry")
    local TextWidget = require("ui/widget/textwidget")
    local Font = require("ui/font")
    local Blitbuffer = require("ffi/blitbuffer")
    local logger = require("logger")

    local Layer = Widget:extend{ text = "", size = 64, color = true, face_name = "cfont", line_step = 0.80 }

    local function freeAll(list)
        for _, widget in ipairs(list or {}) do
            if widget and widget.free then pcall(widget.free, widget) end
        end
    end

    local function makeLines(self, fgcolor)
        local widgets, width, height = {}, 0, 0
        local index = 0
        for line in (tostring(self.text) .. "\n"):gmatch("(.-)\n") do
            index = index + 1
            local widget = TextWidget:new{
                text = line == "" and " " or line, face = Font:getFace(self.face_name, self.size),
                fgcolor = fgcolor, bold = true, padding = 0,
            }
            local info = widget:getSize()
            widgets[index] = { widget = widget, w = info.w, h = info.h }
            width = math.max(width, info.w)
        end
        -- Lines are stacked closer than their boxes: digits have no descenders.
        local step = widgets[1] and math.floor(widgets[1].h * (#widgets > 1 and self.line_step or 1)) or 0
        for i, item in ipairs(widgets) do
            item.x = math.floor((width - item.w) / 2)
            item.y = (i - 1) * step
            height = math.max(height, item.y + item.h)
        end
        return widgets, width, height
    end

    function Layer:_measure()
        freeAll((function() local l = {} for _, it in ipairs(self.mask_lines or {}) do l[#l + 1] = it.widget end return l end)())
        self.mask_lines, self.ink_w, self.ink_h = makeLines(self, Blitbuffer.COLOR_BLACK)
        self.pad = GlassClock.padFor(self.size)
        self.w = self.ink_w + 2 * self.pad
        self.h = self.ink_h + 2 * self.pad
        self.dimen = Geom:new{ w = self.w, h = self.h }
    end

    function Layer:init() self:_measure() end
    function Layer:getSize() return self.dimen end

    -- The glyph box without padding, for centring the digits themselves.
    function Layer:getInkSize() return self.ink_w, self.ink_h end

    function Layer:freeTile()
        if self.tile and self.tile.free then pcall(self.tile.free, self.tile) end
        self.tile = nil
    end

    function Layer:setText(text)
        if text == self.text then return false end
        self.text = text
        self:freeTile()
        self.failed = nil
        freeAll((function() local l = {} for _, it in ipairs(self.plain_lines or {}) do l[#l + 1] = it.widget end return l end)())
        self.plain_lines = nil
        self:_measure()
        return true
    end

    function Layer:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        if not self.tile and not self.failed then
            local pad, lines = self.pad, self.mask_lines
            local ok, tile = pcall(GlassClock.buildTile, bb, x, y, self.w, self.h, function(mask)
                for _, item in ipairs(lines) do item.widget:paintTo(mask, pad + item.x, pad + item.y) end
            end, self.size, self.color)
            if ok and tile then
                self.tile = tile
            else
                self.failed = true
                logger.warn("AppDock: glass clock failed, using plain digits: " .. tostring(tile))
            end
        end
        if self.tile then
            if pcall(bb.blitFrom, bb, self.tile, x, y, 0, 0, self.w, self.h) then return end
        end
        -- Fallback: plain white digits (still readable on the wallpaper).
        if not self.plain_lines then self.plain_lines = makeLines(self, Blitbuffer.COLOR_WHITE) end
        for _, item in ipairs(self.plain_lines) do
            item.widget:paintTo(bb, x + self.pad + item.x, y + self.pad + item.y)
        end
    end

    function Layer:free()
        self:freeTile()
        for _, key in ipairs({ "mask_lines", "plain_lines" }) do
            local widgets = {}
            for _, item in ipairs(self[key] or {}) do widgets[#widgets + 1] = item.widget end
            freeAll(widgets)
            self[key] = nil
        end
    end

    return Layer
end

local layer_class
-- Returns the widget class, or nil when KOReader's widget stack is missing.
function GlassClock.layerClass()
    if layer_class == nil then
        local ok, class = pcall(newLayerClass)
        layer_class = ok and class or false
    end
    return layer_class or nil
end

return GlassClock
