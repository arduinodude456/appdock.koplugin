--[[--
AppDock BWR1: the monochrome raw-video container AppDock plays on E-Ink.

A BWR1 file is deliberately tiny and seekable:

    header: 32 bytes, little-endian
        0..3   "BWR1"
        4      version (1)
        5      pixel format (1 = 1 bit per pixel, MSB first, 1 = white)
        6..7   width  (u16, must be a multiple of 8)
        8..9   height (u16)
        10..11 frames per second * 100 (u16)
        12..15 frame count (u32)
        16..19 bytes per frame (u32)
        20..31 reserved, zero
    frames: 1-bit pixels, row-major, no per-row padding

The layout is byte-compatible with the `BWR1` files written by the
`videoplayer.koplugin` release "Snake" (`tools/make.py`). Frames are already
dithered, so playback only has to expand bits to bytes and blit them; that is
what keeps E-Ink refresh times low.

Two dithering paths exist and both write the same container:

* `Encoder:pack` (Bayer, the default) dithers grey frames inside AppDock with
  the same 8x8 ordered matrix `make.py` uses, so AppDock output matches the
  files the Snake player already knows.
* `BWR.ditherFromFfmpeg` accepts frames ffmpeg already reduced to 1 bit.

The pixel work runs on FFI buffers. A 1264x1680 frame costs roughly two
milliseconds on a desktop CPU, so a whole conversion stays interactive on the
device.
--]]--

local bit = require("bit")
local ffi = require("ffi")
local _ = require("gettext")

local BWR = {}

BWR.MAGIC = "BWR1"
BWR.HEADER_BYTES = 32
BWR.VERSION = 1
BWR.PIXEL_FORMAT_MONO1_MSB_WHITE = 1
BWR.MAX_FRAME_BYTES = 8 * 1024 * 1024
BWR.MAX_FRAMES = 500000
BWR.MAX_DIMENSION = 4096
BWR.MIN_FPS = 0.01
BWR.MAX_FPS = 30

-- The ordered matrix from videoplayer.koplugin/tools/make.py. Keeping the exact
-- values means AppDock, the Snake player and the desktop converter all produce
-- the same look for the same source frame.
local BAYER_8 = {
    { 0, 48, 12, 60, 3, 51, 15, 63 },
    { 32, 16, 44, 28, 35, 19, 47, 31 },
    { 8, 56, 4, 52, 11, 59, 7, 55 },
    { 40, 24, 36, 20, 43, 27, 39, 23 },
    { 2, 50, 14, 62, 1, 49, 13, 61 },
    { 34, 18, 46, 30, 33, 17, 45, 29 },
    { 10, 58, 6, 54, 9, 57, 5, 53 },
    { 42, 26, 38, 22, 41, 25, 45, 21 },
}

-- DITHER_LUTS[row_phase][column_phase][grey] is either zero or the single bit
-- that column_phase owns inside its output byte. One byte of output therefore
-- costs eight table lookups and one OR, which LuaJIT compiles to tight code.
local DITHER_LUTS = {}
for row_phase = 0, 7 do
    local row = {}
    for column_phase = 0, 7 do
        local threshold = BAYER_8[row_phase + 1][column_phase + 1] * 4 + 2
        local pixel_bit = 128
        for _ = 1, column_phase do pixel_bit = pixel_bit / 2 end
        local table_for_phase = ffi.new("uint8_t[256]")
        for grey = 0, 255 do
            table_for_phase[grey] = grey > threshold and pixel_bit or 0
        end
        row[column_phase] = table_for_phase
    end
    DITHER_LUTS[row_phase] = row
end

local bor = bit.bor

local function dither_frame(source, target, width, height)
    local row_bytes = width / 8
    local out = 0
    for y = 0, height - 1 do
        local luts = DITHER_LUTS[y % 8]
        local l0, l1, l2, l3 = luts[0], luts[1], luts[2], luts[3]
        local l4, l5, l6, l7 = luts[4], luts[5], luts[6], luts[7]
        local base = y * width
        for column = 0, row_bytes - 1 do
            local index = base + column * 8
            target[out] = bor(
                l0[source[index]], l1[source[index + 1]],
                l2[source[index + 2]], l3[source[index + 3]],
                l4[source[index + 4]], l5[source[index + 5]],
                l6[source[index + 6]], l7[source[index + 7]]
            )
            out = out + 1
        end
    end
end

-- Expanding a packed byte back into eight BB8 pixels writes two 32-bit words
-- per byte, so the lookup tables above are paired with these two.
local EXPAND_FIRST = ffi.new("uint32_t[256]")
local EXPAND_SECOND = ffi.new("uint32_t[256]")

local function spread_nibble(value)
    local packed = 0
    for pixel = 0, 3 do
        if bit.band(value, bit.rshift(0x08, pixel)) ~= 0 then
            packed = bor(packed, bit.lshift(0xFF, pixel * 8))
        end
    end
    return packed
end

for value = 0, 255 do
    EXPAND_FIRST[value] = spread_nibble(bit.rshift(value, 4))
    EXPAND_SECOND[value] = spread_nibble(bit.band(value, 0x0F))
end

BWR._test = {
    bayer = BAYER_8,
    ditherFrame = dither_frame,
}

----------------------------------------------------------------
-- Header helpers
----------------------------------------------------------------

local function u16_le(data, offset)
    local low, high = data:byte(offset, offset + 1)
    if not low or not high then return nil end
    return low + high * 256
end

local function u32_le(data, offset)
    local a, b, c, d = data:byte(offset, offset + 3)
    if not a or not b or not c or not d then return nil end
    return a + b * 256 + c * 65536 + d * 16777216
end

local function put_u16_le(value)
    value = math.floor(value) % 65536
    return string.char(value % 256, math.floor(value / 256) % 256)
end

local function put_u32_le(value)
    value = math.floor(value) % 4294967296
    return string.char(
        value % 256,
        math.floor(value / 256) % 256,
        math.floor(value / 65536) % 256,
        math.floor(value / 16777216) % 256
    )
end

BWR.putU16 = put_u16_le
BWR.putU32 = put_u32_le

function BWR.frameBytes(width, height)
    return (width / 8) * height
end

function BWR.durationSeconds(header)
    if not header or not header.fps or header.fps <= 0 then return 0 end
    return header.frames / header.fps
end

function BWR.buildHeader(width, height, fps, frames)
    local ok, err = BWR.validateGeometry(width, height, fps)
    if not ok then return nil, err end
    frames = math.floor(tonumber(frames) or 0)
    if frames < 0 or frames > BWR.MAX_FRAMES then
        return nil, _("The frame count is out of range.")
    end
    return BWR.MAGIC
        .. string.char(BWR.VERSION, BWR.PIXEL_FORMAT_MONO1_MSB_WHITE)
        .. put_u16_le(width)
        .. put_u16_le(height)
        .. put_u16_le(math.floor(fps * 100 + 0.5))
        .. put_u32_le(frames)
        .. put_u32_le(BWR.frameBytes(width, height))
        .. string.rep("\0", 12)
end

function BWR.validateGeometry(width, height, fps)
    width, height, fps = tonumber(width), tonumber(height), tonumber(fps)
    if not width or not height then return nil, _("The video size is missing.") end
    width, height = math.floor(width), math.floor(height)
    if width < 8 or height < 1 or width > BWR.MAX_DIMENSION or height > BWR.MAX_DIMENSION then
        return nil, _("The video size must be between 8x1 and 4096x4096.")
    end
    if width % 8 ~= 0 then
        return nil, _("The width must be divisible by 8 for the packed 1-bit layout.")
    end
    if not fps or fps < BWR.MIN_FPS or fps > BWR.MAX_FPS then
        return nil, _("The frame rate must be between 0.01 and 30 frames per second.")
    end
    return true
end

-- Accepts the 32 header bytes either as a string or from an open file handle.
-- File handles are userdata, so the check is for a readable object rather than
-- for a table.
function BWR.readHeader(source)
    local data
    if type(source) == "string" then
        data = source
    elseif source ~= nil and type(source.read) == "function" then
        data = source:read(BWR.HEADER_BYTES)
    else
        return nil, _("A BWR1 header needs a string or an open file.")
    end
    if not data or #data ~= BWR.HEADER_BYTES then
        return nil, _("The BWR1 file has no complete header.")
    end
    if data:sub(1, 4) ~= BWR.MAGIC then
        return nil, _("This is not a BWR1 raw-video file.")
    end
    local header = {
        version = data:byte(5),
        pixel_format = data:byte(6),
        width = u16_le(data, 7),
        height = u16_le(data, 9),
        fps_x100 = u16_le(data, 11),
        frames = u32_le(data, 13),
        frame_bytes = u32_le(data, 17),
    }
    if header.version ~= BWR.VERSION then
        return nil, _("Unsupported BWR1 version.") .. " " .. tostring(header.version)
    end
    if header.pixel_format ~= BWR.PIXEL_FORMAT_MONO1_MSB_WHITE then
        return nil, _("Unsupported BWR1 pixel format.")
    end
    if not header.width or not header.height
        or header.width < 8 or header.width % 8 ~= 0
        or header.height < 1
        or header.width > BWR.MAX_DIMENSION or header.height > BWR.MAX_DIMENSION
    then
        return nil, _("Invalid BWR1 dimensions.")
    end
    if not header.fps_x100 or header.fps_x100 < 1 or not header.frames
        or header.frames < 1 or header.frames > BWR.MAX_FRAMES
    then
        return nil, _("Invalid BWR1 timing or frame count.")
    end
    if header.frame_bytes ~= BWR.frameBytes(header.width, header.height)
        or header.frame_bytes > BWR.MAX_FRAME_BYTES
    then
        return nil, _("Invalid BWR1 frame size.")
    end
    header.fps = header.fps_x100 / 100
    return header
end

----------------------------------------------------------------
-- Dithering
----------------------------------------------------------------

local Encoder = {}
Encoder.__index = Encoder

-- Encodes grey frames (one byte per pixel, exactly width * height bytes) into
-- packed BWR1 frames. Buffers are reused, so a conversion allocates once.
function BWR.newEncoder(width, height)
    local ok, err = BWR.validateGeometry(width, height, 1)
    if not ok then return nil, err end
    return setmetatable({
        width = width,
        height = height,
        frame_bytes = BWR.frameBytes(width, height),
        source = ffi.new("uint8_t[?]", width * height),
        target = ffi.new("uint8_t[?]", BWR.frameBytes(width, height)),
    }, Encoder)
end

function Encoder:pack(grey)
    if type(grey) ~= "string" or #grey ~= self.width * self.height then
        return nil, _("The grey frame has the wrong size.")
    end
    ffi.copy(self.source, grey, self.width * self.height)
    dither_frame(self.source, self.target, self.width, self.height)
    return ffi.string(self.target, self.frame_bytes)
end

-- Copies a packed frame that ffmpeg already dithered, optionally inverting it.
-- ffmpeg writes "monow" with the opposite bit sense on some builds, so the
-- caller probes that once instead of guessing per frame.
function Encoder:packPreDithered(packed, invert)
    if type(packed) ~= "string" or #packed ~= self.frame_bytes then
        return nil, _("The dithered frame has the wrong size.")
    end
    if not invert then return packed end
    ffi.copy(self.target, packed, self.frame_bytes)
    for index = 0, self.frame_bytes - 1 do
        self.target[index] = bit.band(bit.bnot(self.target[index]), 0xFF)
    end
    return ffi.string(self.target, self.frame_bytes)
end

----------------------------------------------------------------
-- Decoding
----------------------------------------------------------------

local blitbuffer_module

local function getBlitbuffer()
    if blitbuffer_module == nil then
        local ok, module = pcall(require, "ffi/blitbuffer")
        blitbuffer_module = ok and module or false
    end
    return blitbuffer_module or nil
end

-- Expands one packed frame into an 8-bit Blitbuffer ready for blitting.
function BWR.expandFrame(packed, width, height)
    local Blitbuffer = getBlitbuffer()
    if not Blitbuffer then return nil, _("The E-Ink framebuffer module is unavailable.") end
    local frame_bytes = BWR.frameBytes(width, height)
    if type(packed) ~= "string" or #packed ~= frame_bytes then
        return nil, _("Cannot read a complete BWR1 frame.")
    end
    local bb = Blitbuffer.new(width, height, Blitbuffer.TYPE_BB8)
    local destination = ffi.cast("uint32_t*", bb.data)
    local output = 0
    for index = 0, frame_bytes - 1 do
        local value = packed:byte(index + 1)
        destination[output] = EXPAND_FIRST[value]
        destination[output + 1] = EXPAND_SECOND[value]
        output = output + 2
    end
    return bb
end

return BWR
