--[[--
AppDock BWR1/BWR2/BRC2: monochrome and indexed five-color video containers.

A legacy BWR1 file is deliberately simple and seekable:

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

The BWR1 layout remains byte-compatible with files written by the
`videoplayer.koplugin` release "Snake" (`tools/make.py`). New AppDock conversions
use BWR2 for monochrome or BRC2 for indexed-color output. Both use independently
decodable keyframes, a keyframe index at the end of the file and compressed XOR
deltas, keeping seeking bounded to one GOP. BRC2 stores one palette index per
pixel, restricted to white, black and pure red/green/blue; no mixed RGB pixels
are stored. Existing BWR1/BWR2 output remains byte-compatible.

Two dithering paths supply frames to the BWR2 writer:

* `Encoder:pack` dithers grey frames inside AppDock with the same 8x8 ordered
  matrix `make.py` uses, so users can choose output that matches the Snake
  player.
* `Encoder:packPreDithered` accepts frames ffmpeg already reduced to 1 bit; this
  is the default monochrome conversion path because it is substantially faster.
* `ColorEncoder:pack` maps RGB frames to the five-color palette and can use an
  ordered matrix to spatially dither between palette entries.
--]]--

local bit = require("bit")
local ffi = require("ffi")
local _ = require("gettext")

local BWR = {}

BWR.MAGIC = "BWR1"
BWR.MAGIC_V2 = "BWR2"
BWR.MAGIC_COLOR_V2 = "BRC2"
BWR.HEADER_BYTES = 32
BWR.VERSION = 1
BWR.VERSION_V2 = 2
BWR.PIXEL_FORMAT_MONO1_MSB_WHITE = 1
BWR.PIXEL_FORMAT_PALETTE5_INDEX8 = 2
BWR.MAX_FRAME_BYTES = 8 * 1024 * 1024
BWR.MAX_FRAMES = 500000
BWR.MAX_DIMENSION = 4096
BWR.MIN_FPS = 0.01
BWR.MAX_FPS = 30
BWR.DEFAULT_KEYFRAME_INTERVAL = 12

-- zlib is optional. KOReader builds generally expose libz; when they do, BWR2
-- uses fast level-1 DEFLATE. The built-in zero-run codec remains available on
-- builds without it, so BWR2 never requires an additional executable.
local zlib
do
    pcall(ffi.cdef, [[
        typedef unsigned char appdock_z_Bytef;
        typedef unsigned long appdock_z_uLong;
        int compress2(appdock_z_Bytef *dest, appdock_z_uLong *destLen,
                     const appdock_z_Bytef *source, appdock_z_uLong sourceLen, int level);
        appdock_z_uLong compressBound(appdock_z_uLong sourceLen);
        int uncompress(appdock_z_Bytef *dest, appdock_z_uLong *destLen,
                       const appdock_z_Bytef *source, appdock_z_uLong sourceLen);
    ]])
    for _, name in ipairs({ "z", "libz.so.1", "libz.so" }) do
        local ok, library = pcall(ffi.load, name)
        if ok then zlib = library; break end
    end
end

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
function BWR.colorFrameBytes(width, height)
    return width * height
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

-- BWR2 keeps the BWR1 geometry fields but stores a keyframe interval and the
-- byte offset of its compact keyframe index in the formerly reserved bytes.
function BWR.buildHeaderV2(width, height, fps, frames, key_interval, index_offset, format, pixel_format)
    local ok, err = BWR.validateGeometry(width, height, fps)
    if not ok then return nil, err end
    frames = math.floor(tonumber(frames) or 0)
    key_interval = math.floor(tonumber(key_interval) or BWR.DEFAULT_KEYFRAME_INTERVAL)
    index_offset = math.floor(tonumber(index_offset) or 0)
    if frames < 0 or frames > BWR.MAX_FRAMES then return nil, _("The frame count is out of range.") end
    if key_interval < 1 or key_interval > 65535 then return nil, _("The BWR2 keyframe interval is out of range.") end
    if index_offset < 0 or index_offset > 4294967295 then return nil, _("The BWR2 index offset is out of range.") end
    format = format == BWR.MAGIC_COLOR_V2 and BWR.MAGIC_COLOR_V2 or BWR.MAGIC_V2
    pixel_format = format == BWR.MAGIC_COLOR_V2 and BWR.PIXEL_FORMAT_PALETTE5_INDEX8 or BWR.PIXEL_FORMAT_MONO1_MSB_WHITE
    local frame_bytes = pixel_format == BWR.PIXEL_FORMAT_PALETTE5_INDEX8 and BWR.colorFrameBytes(width, height) or BWR.frameBytes(width, height)
    if frame_bytes > BWR.MAX_FRAME_BYTES then return nil, _("The video frame exceeds the supported size.") end
    return format
        .. string.char(BWR.VERSION_V2, pixel_format)
        .. put_u16_le(width)
        .. put_u16_le(height)
        .. put_u16_le(math.floor(fps * 100 + 0.5))
        .. put_u32_le(frames)
        .. put_u32_le(frame_bytes)
        .. put_u16_le(key_interval)
        .. put_u16_le(0) -- flags reserved
        .. put_u32_le(index_offset)
        .. string.rep("\0", 4)
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
        return nil, _("A BWR header needs a string or an open file.")
    end
    if not data or #data ~= BWR.HEADER_BYTES then
        return nil, _("The BWR file has no complete header.")
    end
    local magic = data:sub(1, 4)
    local is_color = magic == BWR.MAGIC_COLOR_V2
    local is_v2 = magic == BWR.MAGIC_V2 or is_color
    if magic ~= BWR.MAGIC and not is_v2 then return nil, _("This is not an AppDock BWR video file.") end
    local header = {
        format = magic,
        version = data:byte(5),
        pixel_format = data:byte(6),
        width = u16_le(data, 7),
        height = u16_le(data, 9),
        fps_x100 = u16_le(data, 11),
        frames = u32_le(data, 13),
        frame_bytes = u32_le(data, 17),
    }
    local expected_version = is_v2 and BWR.VERSION_V2 or BWR.VERSION
    if header.version ~= expected_version then
        return nil, _("Unsupported BWR video version.") .. " " .. tostring(header.version)
    end
    if (is_color and header.pixel_format ~= BWR.PIXEL_FORMAT_PALETTE5_INDEX8)
        or (not is_color and header.pixel_format ~= BWR.PIXEL_FORMAT_MONO1_MSB_WHITE) then
        return nil, _("Unsupported BWR pixel format.")
    end
    if not header.width or not header.height
        or header.width < 8 or header.width % 8 ~= 0
        or header.height < 1
        or header.width > BWR.MAX_DIMENSION or header.height > BWR.MAX_DIMENSION
    then
        return nil, _("Invalid BWR dimensions.")
    end
    if not header.fps_x100 or header.fps_x100 < 1 or not header.frames
        or header.frames < 1 or header.frames > BWR.MAX_FRAMES
    then
        return nil, _("Invalid BWR timing or frame count.")
    end
    local expected_frame_bytes = is_color and BWR.colorFrameBytes(header.width, header.height)
        or BWR.frameBytes(header.width, header.height)
    if header.frame_bytes ~= expected_frame_bytes or header.frame_bytes > BWR.MAX_FRAME_BYTES then
        return nil, _("Invalid BWR frame size.")
    end
    if is_v2 then
        header.key_interval = u16_le(data, 21)
        header.index_offset = u32_le(data, 25)
        if not header.key_interval or header.key_interval < 1
            or not header.index_offset or header.index_offset < BWR.HEADER_BYTES
        then
            return nil, _("Invalid BWR2 keyframe index.")
        end
    end
    header.fps = header.fps_x100 / 100
    header.is_color = is_color
    return header
end

----------------------------------------------------------------
-- BWR2 writer
----------------------------------------------------------------

local function rle_encode(data)
    local output, index, length = {}, 1, #data
    while index <= length do
        local value = data:byte(index)
        if value == 0 then
            local finish = index + 1
            while finish <= length and finish - index < 128 and data:byte(finish) == 0 do
                finish = finish + 1
            end
            output[#output + 1] = string.char(finish - index - 1)
            index = finish
        else
            local start = index
            index = index + 1
            while index <= length and index - start < 128 and data:byte(index) ~= 0 do
                index = index + 1
            end
            local count = index - start
            output[#output + 1] = string.char(127 + count)
            output[#output + 1] = data:sub(start, index - 1)
        end
    end
    return table.concat(output)
end

local Writer = {}
Writer.__index = Writer

local function new_writer(handle, width, height, fps, key_interval, format, pixel_format, frame_bytes)
    if not handle or type(handle.write) ~= "function" or type(handle.seek) ~= "function" then
        return nil, _("A BWR2 writer needs a seekable output file.")
    end
    local ok, err = BWR.validateGeometry(width, height, fps)
    if not ok then return nil, err end
    key_interval = math.floor(tonumber(key_interval) or BWR.DEFAULT_KEYFRAME_INTERVAL)
    if key_interval < 1 or key_interval > 65535 then return nil, _("The BWR2 keyframe interval is out of range.") end
    format = format or BWR.MAGIC_V2
    pixel_format = pixel_format or BWR.PIXEL_FORMAT_MONO1_MSB_WHITE
    frame_bytes = frame_bytes or (pixel_format == BWR.PIXEL_FORMAT_PALETTE5_INDEX8
        and BWR.colorFrameBytes(width, height) or BWR.frameBytes(width, height))
    local header, header_error = BWR.buildHeaderV2(width, height, fps, 0, key_interval, 0, format, pixel_format)
    if not header then return nil, header_error end
    local positioned = handle:seek("set", 0)
    if positioned == nil then return nil, _("The BWR2 output file cannot be positioned.") end
    local written, write_error = handle:write(header)
    if not written then return nil, write_error or _("The BWR2 header could not be written.") end
    local writer = setmetatable({
        handle = handle,
        width = width,
        height = height,
        fps = fps,
        frame_bytes = frame_bytes,
        format = format,
        pixel_format = pixel_format,
        key_interval = key_interval,
        frames = 0,
        key_offsets = {},
        previous_frame = nil,
        previous = ffi.new("uint8_t[?]", frame_bytes),
        delta = ffi.new("uint8_t[?]", frame_bytes),
        bytes_written = BWR.HEADER_BYTES,
        finished = false,
    }, Writer)
    if zlib then
        writer.z_input = ffi.new("uint8_t[?]", frame_bytes)
        writer.z_bound = tonumber(zlib.compressBound(frame_bytes))
        writer.z_output = ffi.new("uint8_t[?]", writer.z_bound)
        writer.z_output_length = ffi.new("appdock_z_uLong[1]")
    end
    return writer
end
function BWR.newWriter(handle, width, height, fps, key_interval)
    return new_writer(handle, width, height, fps, key_interval,
        BWR.MAGIC_V2, BWR.PIXEL_FORMAT_MONO1_MSB_WHITE)
end
function BWR.newColorWriter(handle, width, height, fps, key_interval)
    local ok, err = BWR.validateGeometry(width, height, fps)
    if not ok then return nil, err end
    return new_writer(handle, width, height, fps, key_interval,
        BWR.MAGIC_COLOR_V2, BWR.PIXEL_FORMAT_PALETTE5_INDEX8)
end

function Writer:_compress(source)
    if not zlib then return nil end
    local input = source
    if type(source) == "string" then
        ffi.copy(self.z_input, source, self.frame_bytes)
        input = self.z_input
    end
    self.z_output_length[0] = self.z_bound
    local status = zlib.compress2(
        self.z_output, self.z_output_length, input, self.frame_bytes, 1)
    if status ~= 0 then return nil end
    return ffi.string(self.z_output, tonumber(self.z_output_length[0]))
end

function Writer:_writePacket(codec, payload)
    local packet = string.char(codec) .. payload
    if #packet > 4294967295 then return nil, _("A BWR2 frame packet is too large.") end
    local written, err = self.handle:write(put_u32_le(#packet), packet)
    if not written then return nil, err or _("A BWR2 frame could not be written.") end
    self.bytes_written = self.bytes_written + 4 + #packet
    return true
end

function Writer:writeFrame(frame)
    if self.finished then return nil, _("The BWR2 writer is already finished.") end
    if type(frame) ~= "string" or #frame ~= self.frame_bytes then
        return nil, _("The packed frame has the wrong size for BWR2.")
    end
    if self.frames >= BWR.MAX_FRAMES then return nil, _("The BWR2 frame limit was reached.") end
    local offset, seek_error = self.handle:seek("cur")
    if offset == nil or offset > 4294967295 then
        return nil, seek_error or _("The BWR2 file exceeded its 32-bit offset limit.")
    end

    local frame_index = self.frames
    local is_keyframe = frame_index % self.key_interval == 0
    local ok, err
    if is_keyframe then
        local compressed = self:_compress(frame)
        if compressed and #compressed < self.frame_bytes then
            ok, err = self:_writePacket(1, compressed) -- DEFLATE keyframe
        else
            ok, err = self:_writePacket(0, frame) -- raw keyframe
        end
    elseif frame == self.previous_frame then
        ok, err = self:_writePacket(4, "") -- repeat previous frame
    else
        ffi.copy(self.delta, frame, self.frame_bytes)
        local words = math.floor(self.frame_bytes / 4)
        local delta_words = ffi.cast("uint32_t*", self.delta)
        local previous_words = ffi.cast("const uint32_t*", self.previous)
        for index = 0, words - 1 do
            delta_words[index] = bit.bxor(delta_words[index], previous_words[index])
        end
        for index = words * 4, self.frame_bytes - 1 do
            self.delta[index] = bit.bxor(self.delta[index], self.previous[index])
        end
        local compressed = self:_compress(self.delta)
        -- DEFLATE is implemented in C. On ordinary moving footage it already
        -- gives a compact packet, so avoid a second full Lua-level scan. Run
        -- the zero-run codec only when DEFLATE is not clearly compact.
        if compressed and #compressed < self.frame_bytes * 0.75 then
            ok, err = self:_writePacket(2, compressed) -- DEFLATE XOR delta
        else
            local rle = rle_encode(ffi.string(self.delta, self.frame_bytes))
            if compressed and #compressed < #rle and #compressed < self.frame_bytes then
                ok, err = self:_writePacket(2, compressed) -- DEFLATE XOR delta
            elseif #rle < self.frame_bytes then
                ok, err = self:_writePacket(3, rle) -- zero-run XOR delta
            else
                ok, err = self:_writePacket(0, frame) -- raw absolute fallback
            end
        end
    end
    if not ok then return nil, err end
    if is_keyframe then self.key_offsets[#self.key_offsets + 1] = offset end
    ffi.copy(self.previous, frame, self.frame_bytes)
    self.previous_frame = frame
    self.frames = self.frames + 1
    return true
end

function Writer:finish()
    if self.finished then return true end
    if self.frames < 1 then return nil, _("A BWR2 file must contain at least one frame.") end
    local index_offset, seek_error = self.handle:seek("cur")
    if index_offset == nil or index_offset > 4294967295 then
        return nil, seek_error or _("The BWR2 index exceeded its 32-bit offset limit.")
    end
    for _, offset in ipairs(self.key_offsets) do
        local written, err = self.handle:write(put_u32_le(offset))
        if not written then return nil, err or _("The BWR2 keyframe index could not be written.") end
    end
    local header, header_error = BWR.buildHeaderV2(
        self.width, self.height, self.fps, self.frames, self.key_interval, index_offset,
        self.format, self.pixel_format)
    if not header then return nil, header_error end
    local positioned, position_error = self.handle:seek("set", 0)
    if positioned == nil then return nil, position_error or _("The BWR2 header could not be updated.") end
    local written, write_error = self.handle:write(header)
    if not written then return nil, write_error or _("The BWR2 header could not be updated.") end
    self.handle:seek("end")
    self.bytes_written = index_offset + #self.key_offsets * 4
    self.finished = true
    return true
end

----------------------------------------------------------------
-- BWR readers
----------------------------------------------------------------

local Reader = {}
Reader.__index = Reader

local function rle_decode(data, output, expected_bytes)
    local input_index, output_index = 1, 0
    while input_index <= #data do
        local control = data:byte(input_index)
        input_index = input_index + 1
        local count
        if control < 128 then
            count = control + 1
            if output_index + count > expected_bytes then return nil end
            ffi.fill(output + output_index, count, 0)
        else
            count = control - 127
            if output_index + count > expected_bytes or input_index + count - 1 > #data then return nil end
            ffi.copy(output + output_index, data:sub(input_index, input_index + count - 1), count)
            input_index = input_index + count
        end
        output_index = output_index + count
    end
    if output_index ~= expected_bytes then return nil end
    return true
end

local function xor_delta(reader, previous)
    if not previous then return nil, _("A BWR2 delta frame has no previous frame.") end
    ffi.copy(reader.previous, previous, reader.frame_bytes)
    for index = 0, reader.frame_bytes - 1 do
        reader.output[index] = bit.bxor(reader.delta[index], reader.previous[index])
    end
    return ffi.string(reader.output, reader.frame_bytes)
end

function BWR.newReader(handle, header)
    if not handle or type(handle.read) ~= "function" or type(handle.seek) ~= "function" then
        return nil, _("A BWR reader needs a seekable input file.")
    end
    local reader = setmetatable({
        handle = handle,
        header = header,
        frame_bytes = header.frame_bytes,
        cache_index = -1,
        cache_frame = nil,
    }, Reader)
    if header.format ~= BWR.MAGIC_V2 and header.format ~= BWR.MAGIC_COLOR_V2 then return reader end

    local group_count = math.ceil(header.frames / header.key_interval)
    local file_end, seek_error = handle:seek("end")
    if file_end == nil then return nil, seek_error or _("The BWR2 file size cannot be checked.") end
    if header.index_offset + group_count * 4 > file_end then
        return nil, _("The BWR2 keyframe index is truncated.")
    end
    handle:seek("set", header.index_offset)
    local index_data = handle:read(group_count * 4)
    if not index_data or #index_data ~= group_count * 4 then
        return nil, _("The BWR2 keyframe index cannot be read.")
    end
    reader.key_offsets = {}
    local previous_offset = BWR.HEADER_BYTES - 1
    for group = 0, group_count - 1 do
        local offset = u32_le(index_data, group * 4 + 1)
        if not offset or offset <= previous_offset or offset >= header.index_offset then
            return nil, _("The BWR2 keyframe index contains an invalid offset.")
        end
        reader.key_offsets[group + 1] = offset
        previous_offset = offset
    end
    reader.file_end = file_end
    reader.zlib_available = zlib ~= nil
    reader.output = ffi.new("uint8_t[?]", header.frame_bytes)
    reader.delta = ffi.new("uint8_t[?]", header.frame_bytes)
    reader.previous = ffi.new("uint8_t[?]", header.frame_bytes)
    if zlib then
        reader.z_input = ffi.new("uint8_t[?]", header.frame_bytes + 1024)
        reader.z_output_length = ffi.new("appdock_z_uLong[1]")
    end
    handle:seek("set", BWR.HEADER_BYTES)
    return reader
end

function Reader:_inflate(payload)
    if not zlib then return nil, _("This BWR2 video needs the system zlib library to decode a frame.") end
    if #payload > self.frame_bytes + 1024 then return nil, _("The BWR2 compressed frame is too large.") end
    ffi.copy(self.z_input, payload, #payload)
    self.z_output_length[0] = self.frame_bytes
    local status = zlib.uncompress(self.output, self.z_output_length, self.z_input, #payload)
    if status ~= 0 or tonumber(self.z_output_length[0]) ~= self.frame_bytes then
        return nil, _("The BWR2 compressed frame is invalid.")
    end
    return true
end

function Reader:_readPacket(previous, keyframe)
    local packet_start = self.handle:seek("cur")
    if not packet_start or packet_start + 4 > self.header.index_offset then
        return nil, _("The BWR2 frame packet is missing.")
    end
    local length_data = self.handle:read(4)
    local length = length_data and #length_data == 4 and u32_le(length_data, 1) or nil
    local max_packet = self.frame_bytes + math.floor(self.frame_bytes / 1000) + 1024
    if not length or length < 1 or length > max_packet
        or packet_start + 4 + length > self.header.index_offset
    then
        return nil, _("The BWR2 frame packet has an invalid size.")
    end
    local packet = self.handle:read(length)
    if not packet or #packet ~= length then return nil, _("The BWR2 frame packet is truncated.") end
    local codec = packet:byte(1)
    local payload = packet:sub(2)
    local packed
    if codec == 0 then
        if #payload ~= self.frame_bytes then return nil, _("The raw BWR2 frame has the wrong size.") end
        ffi.copy(self.output, payload, self.frame_bytes)
        packed = ffi.string(self.output, self.frame_bytes)
    elseif codec == 1 then
        if not keyframe then return nil, _("A BWR2 keyframe appeared outside the keyframe index.") end
        local ok, err = self:_inflate(payload)
        if not ok then return nil, err end
        packed = ffi.string(self.output, self.frame_bytes)
    elseif codec == 2 then
        if keyframe or not previous then return nil, _("A BWR2 delta cannot begin a keyframe group.") end
        local ok, err = self:_inflate(payload)
        if not ok then return nil, err end
        ffi.copy(self.delta, self.output, self.frame_bytes)
        packed, err = xor_delta(self, previous)
        if not packed then return nil, err end
    elseif codec == 3 then
        if keyframe or not previous then return nil, _("A BWR2 delta cannot begin a keyframe group.") end
        if not rle_decode(payload, self.delta, self.frame_bytes) then
            return nil, _("The BWR2 zero-run frame is invalid.")
        end
        packed = xor_delta(self, previous)
        if not packed then return nil, _("The BWR2 delta frame is invalid.") end
    elseif codec == 4 then
        if keyframe or not previous or #payload ~= 0 then
            return nil, _("The BWR2 repeated frame is invalid.")
        end
        packed = previous
        ffi.copy(self.output, packed, self.frame_bytes)
    else
        return nil, _("Unknown BWR2 frame codec.")
    end
    return packed
end

function Reader:readFrame(index)
    index = math.floor(tonumber(index) or -1)
    if index < 0 or index >= self.header.frames then return nil, _("The frame is outside the BWR video.") end
    if self.header.format ~= BWR.MAGIC_V2 and self.header.format ~= BWR.MAGIC_COLOR_V2 then
        self.handle:seek("set", BWR.HEADER_BYTES + index * self.frame_bytes)
        local packed = self.handle:read(self.frame_bytes)
        if not packed or #packed ~= self.frame_bytes then return nil, _("Cannot read a complete BWR1 frame.") end
        return packed
    end
    if index == self.cache_index then return self.cache_frame end

    local first, previous
    local key_interval = self.header.key_interval
    local can_advance_cache = self.cache_index >= 0
        and index > self.cache_index
        and math.floor(index / key_interval) == math.floor(self.cache_index / key_interval)
    if can_advance_cache then
        -- Playback can skip frames when decoding or display work runs late. Keep
        -- the last decoded frame and advance from it instead of replaying the
        -- already-decoded prefix of this keyframe group on every skip.
        first = self.cache_index + 1
        previous = self.cache_frame
    else
        local group = math.floor(index / key_interval)
        first = group * key_interval
        self.handle:seek("set", self.key_offsets[group + 1])
    end
    local packed, decode_error
    for frame_index = first, index do
        packed, decode_error = self:_readPacket(previous, frame_index % key_interval == 0)
        if not packed then
            return nil, _("Cannot decode BWR2 frame ") .. tostring(frame_index) .. ": " .. tostring(decode_error)
        end
        previous = packed
    end
    self.cache_index, self.cache_frame = index, packed
    return packed
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

-- Indexed color is restricted to the five exact, unmixed colors below. The
-- lookup table stores the best pair and interpolation threshold for each
-- 5:5:5 RGB bucket; frame conversion then needs only one lookup per pixel.
BWR.COLOR_PALETTE = {
    { 255, 255, 255 }, -- 1 white
    {   0,   0,   0 }, -- 2 black
    { 255,   0,   0 }, -- 3 pure red
    {   0, 255,   0 }, -- 4 pure green
    {   0,   0, 255 }, -- 5 pure blue
}
local COLOR_LUT
local function buildColorLUT()
    if COLOR_LUT then return end
    COLOR_LUT = ffi.new("uint16_t[32768]")
    for ri = 0, 31 do
        for gi = 0, 31 do
            for bi = 0, 31 do
                local r, g, b = ri * 8 + 4, gi * 8 + 4, bi * 8 + 4
                local best_a, best_b, best_t, best_error = 1, 2, 0, math.huge
                for a = 1, 5 do
                    local ca = BWR.COLOR_PALETTE[a]
                    for c = a + 1, 5 do
                        local cb = BWR.COLOR_PALETTE[c]
                        local dr, dg, db = cb[1]-ca[1], cb[2]-ca[2], cb[3]-ca[3]
                        local denom = dr*dr + dg*dg + db*db
                        local t = ((r-ca[1])*dr + (g-ca[2])*dg + (b-ca[3])*db) / denom
                        t = math.max(0, math.min(1, t))
                        local er = r - (ca[1] + t*dr)
                        local eg = g - (ca[2] + t*dg)
                        local eb = b - (ca[3] + t*db)
                        local score = er*er + eg*eg + eb*eb
                        if score < best_error then best_a,best_b,best_t,best_error=a,c,t,score end
                    end
                end
                local threshold = math.floor(best_t * 64 + 0.5)
                if threshold > 64 then threshold = 64 end
                local index = ri * 1024 + gi * 32 + bi
                COLOR_LUT[index] = best_a + best_b * 8 + threshold * 64
            end
        end
    end
end
local ColorEncoder = {}
ColorEncoder.__index = ColorEncoder
function BWR.newColorEncoder(width, height)
    local ok, err = BWR.validateGeometry(width, height, 1)
    if not ok then return nil, err end
    local size = width * height
    if size > BWR.MAX_FRAME_BYTES then return nil, _("The color frame exceeds the supported size.") end
    buildColorLUT()
    return setmetatable({ width=width, height=height, frame_bytes=size,
        source=ffi.new("uint8_t[?]", size*3), target=ffi.new("uint8_t[?]", size) }, ColorEncoder)
end
function ColorEncoder:pack(rgb, dither)
    local pixels = self.width * self.height
    if type(rgb) ~= "string" or #rgb ~= pixels*3 then return nil, _("The RGB frame has the wrong size.") end
    ffi.copy(self.source, rgb, pixels*3)
    local source, target = self.source, self.target
    local width, height = self.width, self.height
    local matrix = BAYER_8
    local use_dither = dither ~= false
    for y=0,height-1 do
        local mrow=matrix[(y % 8)+1]
        local offset = y * width * 3
        local output = y * width
        local xphase = 0
        for x=0,width-1 do
            local table_index = bit.rshift(source[offset], 3) * 1024
                + bit.rshift(source[offset + 1], 3) * 32
                + bit.rshift(source[offset + 2], 3)
            local code = COLOR_LUT[table_index]
            local a = bit.band(code, 7)
            local b = bit.band(bit.rshift(code, 3), 7)
            local threshold = bit.rshift(code, 6)
            local choose_b
            if use_dither then choose_b=mrow[xphase + 1] < threshold
            else choose_b=threshold >= 32 end
            target[output]=choose_b and b or a
            offset = offset + 3
            output=output+1
            xphase = xphase + 1
            if xphase == 8 then xphase = 0 end
        end
    end
    return ffi.string(target,pixels)
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
function BWR.expandFrame(packed, width, height, target_buffer)
    local Blitbuffer = getBlitbuffer()
    if not Blitbuffer then return nil, _("The E-Ink framebuffer module is unavailable.") end
    local frame_bytes = BWR.frameBytes(width, height)
    if type(packed) ~= "string" or #packed ~= frame_bytes then
        return nil, _("Cannot read a complete BWR1 frame.")
    end
    local bb = target_buffer or Blitbuffer.new(width, height, Blitbuffer.TYPE_BB8)
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

local COLOR_RGB32_LUT
local COLOR_LUMINANCE_LUT = ffi.new("uint8_t[6]", { 255, 255, 0, 76, 150, 29 })

local function getColorRGB32LUT(Blitbuffer)
    if not COLOR_RGB32_LUT then
        local colors = ffi.new("ColorRGB32[6]")
        for index, color in ipairs(BWR.COLOR_PALETTE) do
            colors[index] = Blitbuffer.ColorRGB32(color[1], color[2], color[3], 0xFF)
        end
        COLOR_RGB32_LUT = colors
    end
    return COLOR_RGB32_LUT
end

function BWR.expandColorFrame(packed, width, height, target_buffer)
    local Blitbuffer = getBlitbuffer()
    if not Blitbuffer then return nil, _("The E-Ink framebuffer module is unavailable.") end
    local expected=width*height
    if type(packed)~="string" or #packed~=expected then return nil, _("Cannot read a complete BRC2 color frame.") end
    local Device=require("device")
    local color_screen=Device.screen and Device.screen.isColorEnabled and Device.screen:isColorEnabled()
    local bb=target_buffer
    if not bb then
        if color_screen and Blitbuffer.TYPE_BBRGB32 then
            local ok,result=pcall(Blitbuffer.new,width,height,Blitbuffer.TYPE_BBRGB32)
            if ok then bb=result end
        end
        if not bb then bb=Blitbuffer.new(width,height,Blitbuffer.TYPE_BB8); color_screen=false end
    end
    local source=ffi.cast("const uint8_t*",packed)
    if color_screen then
        local destination=ffi.cast("ColorRGB32*",bb.data)
        local colors=getColorRGB32LUT(Blitbuffer)
        for index=0,expected-1 do
            local color_index=source[index]
            if color_index < 1 or color_index > 5 then color_index=1 end
            destination[index]=colors[color_index]
        end
    else
        local bytes=ffi.cast("uint8_t*",bb.data)
        for index=0,expected-1 do
            local color_index=source[index]
            if color_index < 1 or color_index > 5 then color_index=0 end
            bytes[index]=COLOR_LUMINANCE_LUT[color_index]
        end
    end
    return bb
end

return BWR
