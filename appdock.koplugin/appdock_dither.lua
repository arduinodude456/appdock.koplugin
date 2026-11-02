--[[--
AppDock Dither: in-place ordered dithering of a screen buffer onto the eight
fast E-Ink colors (black, white, red, green, blue, yellow, cyan, magenta).

Color E-Ink panels refresh these eight colors with the fast waveform; every
other color needs the slow full-color waveform. Window Mode (Beta) runs the
whole window surface through this filter so it can be refreshed quickly.

The filter is idempotent: pixels that already consist of pure 0/255 channels
stay unchanged, so repainting a partly dithered buffer is harmless. The Bayer
8x8 matrix is the same one AppDock Draw uses, so both look alike. The pattern
is applied in physical buffer coordinates, which makes it independent of the
screen rotation.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local ffi = require("ffi")
local bit = require("bit")

local band, rshift = bit.band, bit.rshift

local Dither = {}

-- 8x8 Bayer thresholds (2..254), identical to appdock_draw.lua.
local THRESHOLDS = ffi.new("uint8_t[64]")
do
    local m, n = { { 0, 2 }, { 3, 1 } }, 2
    local q = { { 0, 2 }, { 3, 1 } }
    while n < 8 do
        local nn, r = n * 2, {}
        for y = 0, nn - 1 do
            r[y + 1] = {}
            for x = 0, nn - 1 do
                r[y + 1][x + 1] = m[(y % n) + 1][(x % n) + 1] * 4 + q[math.floor(y / n) + 1][math.floor(x / n) + 1]
            end
        end
        m, n = r, nn
    end
    for y = 0, 7 do
        for x = 0, 7 do THRESHOLDS[y * 8 + x] = m[y + 1][x + 1] * 4 + 2 end
    end
end

-- 5/6-bit channel to 8-bit channel for RGB565 buffers.
local EXPAND5, EXPAND6 = ffi.new("uint8_t[32]"), ffi.new("uint8_t[64]")
for value = 0, 31 do EXPAND5[value] = math.floor(value * 255 / 31 + 0.5) end
for value = 0, 63 do EXPAND6[value] = math.floor(value * 255 / 63 + 0.5) end

local function ditherPacked(base, stride, x0, y0, x1, y1, channels)
    for y = y0, y1 do
        local row = base + y * stride
        local thresholds = THRESHOLDS + band(y, 7) * 8
        for x = x0, x1 do
            local pixel = row + x * channels
            local t = thresholds[band(x, 7)]
            pixel[0] = pixel[0] > t and 255 or 0
            pixel[1] = pixel[1] > t and 255 or 0
            pixel[2] = pixel[2] > t and 255 or 0
        end
    end
end

local function ditherRGB16(base, stride, x0, y0, x1, y1)
    for y = y0, y1 do
        local row = ffi.cast("uint16_t*", base + y * stride)
        local thresholds = THRESHOLDS + band(y, 7) * 8
        for x = x0, x1 do
            local value = row[x]
            local t = thresholds[band(x, 7)]
            local r = EXPAND5[rshift(value, 11)] > t and 0xF800 or 0
            local g = EXPAND6[band(rshift(value, 5), 0x3F)] > t and 0x07E0 or 0
            local b = EXPAND5[band(value, 0x1F)] > t and 0x001F or 0
            row[x] = r + g + b
        end
    end
end

local function ditherGray(base, stride, x0, y0, x1, y1)
    for y = y0, y1 do
        local row = base + y * stride
        local thresholds = THRESHOLDS + band(y, 7) * 8
        for x = x0, x1 do
            row[x] = row[x] > thresholds[band(x, 7)] and 255 or 0
        end
    end
end

-- Dithers the buffer in place; `region` ({ x, y, w, h } in logical screen
-- coordinates) limits the work to that area, nil means the whole buffer.
-- Returns true when the buffer type is supported.
function Dither.apply(bb, region)
    if not bb or not bb.data then return false end
    local kind = bb:getType()
    -- Raw (physical) geometry: independent of any screen rotation.
    local x0, y0, x1, y1 = 0, 0, bb.w - 1, bb.h - 1
    if region and bb.getPhysicalRect then
        local px, py, pw, ph = bb:getPhysicalRect(region.x, region.y, region.w, region.h)
        x0, y0 = math.max(0, px), math.max(0, py)
        x1, y1 = math.min(x1, px + pw - 1), math.min(y1, py + ph - 1)
    end
    if x1 < x0 or y1 < y0 then return true end
    local stride = bb.stride
    local base = ffi.cast("uint8_t*", bb.data)
    if kind == Blitbuffer.TYPE_BBRGB32 then
        ditherPacked(base, stride, x0, y0, x1, y1, 4)
    elseif kind == Blitbuffer.TYPE_BBRGB24 then
        ditherPacked(base, stride, x0, y0, x1, y1, 3)
    elseif kind == Blitbuffer.TYPE_BBRGB16 then
        ditherRGB16(base, stride, x0, y0, x1, y1)
    elseif kind == Blitbuffer.TYPE_BB8 then
        ditherGray(base, stride, x0, y0, x1, y1)
    else
        return false
    end
    return true
end

return Dither
