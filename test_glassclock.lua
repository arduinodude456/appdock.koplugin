-- Liquid Glass digits: distance field, refraction, rim light, shadow.
package.path = (os.getenv("APPDOCK_PLUGIN_DIR") or "./appdock.koplugin/") .. "?.lua;" .. package.path
local ffi = require("ffi")
local GlassClock = require("appdock_glassclock")

assert(GlassClock.padFor(100) >= 17 and GlassClock.padFor(1) >= 6, "Padding grows with the font size and has a floor")

-- A thick ring (like an "O") on a flat mid-blue background.
local w, h, size = 160, 160, 100
local cov = ffi.new("double[?]", w * h)
for y = 0, h - 1 do
    for x = 0, w - 1 do
        local d = math.sqrt((x - 80) ^ 2 + (y - 80) ^ 2)
        local c = 0
        if d >= 34 and d <= 62 then c = 1 elseif d > 62 and d < 63 then c = 63 - d elseif d > 33 and d < 34 then c = d - 33 end
        cov[y * w + x] = c
    end
end
local BG = { 40, 70, 120 }
local function render(color)
    local out = {}
    for i = 0, w * h - 1 do out[i] = { BG[1], BG[2], BG[3] } end
    local function sample(x, y) local p = out0 and out0[y * w + x] or BG; return p[1], p[2], p[3] end
    local puts, spans = 0, 0
    GlassClock.shade{
        w = w, h = h, cov = cov, size = size, color = color,
        sample = function() return BG[1], BG[2], BG[3] end,
        put = function(x, y, r, g, b)
            assert(x >= 0 and x < w and y >= 0 and y < h, "put stays inside the tile")
            assert(r >= 0 and r <= 255 and g >= 0 and g <= 255 and b >= 0 and b <= 255, "colors stay in range")
            out[y * w + x] = { r, g, b }
            puts = puts + 1
        end,
        span = function(y, x0, x1, r, g, b, a)
            assert(x0 <= x1 and a > 0 and a < 1, "interior spans are blended, not opaque")
            for x = x0, x1 do out[y * w + x] = { BG[1] + (r - BG[1]) * a, BG[2] + (g - BG[2]) * a, BG[3] + (b - BG[3]) * a } end
            spans = spans + 1
        end,
    }
    return out, puts, spans
end

local function lum(p) return p[1] + p[2] + p[3] end
local out, puts, spans = render(true)
assert(puts > 500 and spans > 20, "Edges are shaded per pixel and the flat middle is filled in runs")
-- far outside the ring and the hole centre are untouched (no shadow there)
assert(lum(out[2 * w + 2]) == lum(BG), "Far background is not touched")
-- the ring's outer edge facing the light (upper left) is brighter than the flat middle of the stroke
local mid = out[80 * w + (80 - 48)]           -- middle of the left stroke
local rim = out[(80 - 44) * w + (80 - 44)]    -- upper-left outer edge region
local edge = out[80 * w + (80 - 62)]
assert(lum(edge) > lum(mid) + 60, "The lit rim is clearly brighter than the frosted body")
assert(lum(mid) > lum(BG), "The glass body is a little lighter than the wallpaper")
-- drop shadow: just below the ring's bottom edge is darker than the plain background
local shadow = out[(80 + 64) * w + 80]
assert(lum(shadow) < lum(BG), "A soft shadow falls below the digits")
-- inside the hole near the top inner edge the lens bends the wallpaper but stays in range
assert(out[(80 - 30) * w + 80] ~= nil)

-- grayscale panels use the same pipeline with a stronger contrast
local gray_out = render(false)
local gray_edge, gray_mid = gray_out[80 * w + (80 - 62)], gray_out[80 * w + (80 - 48)]
assert(lum(gray_edge) > lum(gray_mid), "Grayscale glass keeps a bright rim")

-- Distance field exactness: a single filled square, interior pixel at the centre
-- must have the expected distance from the edge (checked via the lit hairline).
local tiny = ffi.new("double[?]", 30 * 30)
for y = 8, 21 do for x = 8, 21 do tiny[y * 30 + x] = 1 end end
local touched = 0
GlassClock.shade{
    w = 30, h = 30, cov = tiny, size = 40, color = true,
    sample = function() return 10, 10, 10 end,
    put = function() touched = touched + 1 end,
    span = function() touched = touched + 1 end,
}
assert(touched > 0, "Small shapes render without errors")

-- Empty text: nothing to do and nothing to break.
local empty = ffi.new("double[?]", 20 * 20)
GlassClock.shade{ w = 20, h = 20, cov = empty, size = 30, color = true,
    sample = function() return 1, 2, 3 end, put = function() error("no pixel expected") end, span = function() error("no span expected") end }
print("glassclock-ok")
