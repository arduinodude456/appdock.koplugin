-- AppDock BWR1/BWR2 format test.
--
-- Verifies the container contract that the YouTube DApp writes and the player
-- reads, and checks the ordered dithering against an independent reference
-- implementation of the matrix used by videoplayer.koplugin's make.py.

local plugin_dir = os.getenv("APPDOCK_PLUGIN_DIR") or "/home/ubuntu/appdock.koplugin/appdock.koplugin/"
local ffi = require("ffi")
ffi.cdef[[typedef struct ColorRGB32 { uint8_t r; uint8_t g; uint8_t b; uint8_t alpha; } ColorRGB32;]]

package.preload["gettext"] = function() return function(text) return text end end

local frames_allocated = 0
local color_enabled = true
local function rgba(r, g, b, a) return ffi.new("ColorRGB32", { r = r, g = g, b = b, alpha = a or 255 }) end
package.preload["ffi/blitbuffer"] = function()
    return {
        TYPE_BB8 = 1,
        TYPE_BBRGB32 = 5,
        COLOR_WHITE = "white", COLOR_BLACK = "black",
        COLOR_DARK_GRAY = "dark", COLOR_LIGHT_GRAY = "light", COLOR_GRAY = "gray",
        COLOR_GRAY_7 = "g7", COLOR_GRAY_8 = "g8",
        ColorRGB32 = rgba,
        -- KOReader calls this as a module function: Blitbuffer.new(w, h, type)
        new = function(width, height, pixel_type)
            frames_allocated = frames_allocated + 1
            return {
                width = width,
                height = height,
                data = pixel_type == 5 and ffi.new("ColorRGB32[?]", width * height)
                    or ffi.new("uint8_t[?]", width * height),
                getWidth = function(self) return self.width end,
                getHeight = function(self) return self.height end,
                free = function() end,
            }
        end,
    }
end
package.preload["device"] = function()
    return { screen = { isColorEnabled = function() return color_enabled end } }
end

local BWR = dofile(plugin_dir .. "appdock_bwr.lua")

local function expectError(value, err, message)
    assert(value == nil, message .. " (expected failure)")
    assert(type(err) == "string" and #err > 0, message .. " (expected an error message)")
end

----------------------------------------------------------------
-- Header
----------------------------------------------------------------

local width, height, fps = 632, 840, 12
local header = BWR.buildHeader(width, height, fps, 240)
assert(type(header) == "string" and #header == BWR.HEADER_BYTES, "A BWR1 header must be exactly 32 bytes")
assert(header:sub(1, 4) == "BWR1", "A BWR1 header must start with its magic")

local parsed = BWR.readHeader(header)
assert(parsed, "A written header must parse again")
assert(parsed.width == width and parsed.height == height, "Header round-trip must keep the dimensions")
assert(parsed.fps == fps and parsed.fps_x100 == 1200, "Header round-trip must keep the frame rate")
assert(parsed.frames == 240, "Header round-trip must keep the frame count")
assert(parsed.frame_bytes == (width / 8) * height, "Header round-trip must keep the packed frame size")
assert(BWR.durationSeconds(parsed) == 20, "Duration must be frame count divided by frame rate")

-- The layout has to stay byte compatible with videoplayer.koplugin's make.py.
assert(header:byte(5) == 1 and header:byte(6) == 1, "Version and pixel format must match the BWR1 specification")

expectError(select(1, BWR.readHeader("NOPE" .. header:sub(5))), select(2, BWR.readHeader("NOPE" .. header:sub(5))), "A foreign magic must be rejected")
expectError(select(1, BWR.readHeader(header:sub(1, 20))), select(2, BWR.readHeader(header:sub(1, 20))), "A truncated header must be rejected")

local corrupted = header:sub(1, 16) .. BWR.putU32(1) .. header:sub(21)
local corrupt_value, corrupt_error = BWR.readHeader(corrupted)
assert(corrupt_value == nil and type(corrupt_error) == "string", "A wrong frame size must be rejected")

----------------------------------------------------------------
-- Geometry
----------------------------------------------------------------

assert(BWR.validateGeometry(632, 840, 12), "A valid geometry must pass")
expectError(select(1, BWR.validateGeometry(630, 840, 12)), select(2, BWR.validateGeometry(630, 840, 12)), "A width that is not a multiple of 8 must be rejected")
expectError(select(1, BWR.validateGeometry(632, 840, 45)), select(2, BWR.validateGeometry(632, 840, 45)), "An out-of-range frame rate must be rejected")
expectError(select(1, BWR.buildHeader(630, 840, 12, 1)), select(2, BWR.buildHeader(630, 840, 12, 1)), "buildHeader must validate its geometry")
assert(BWR.frameBytes(632, 840) == 79 * 840, "Frame size must be width/8 times height")

----------------------------------------------------------------
-- Dithering against an independent reference
----------------------------------------------------------------

local BAYER = BWR._test.bayer

local function referencePack(grey, frame_width, frame_height)
    local out = {}
    for y = 0, frame_height - 1 do
        for column = 0, frame_width / 8 - 1 do
            local byte = 0
            for bit_index = 0, 7 do
                local x = column * 8 + bit_index
                local value = grey[y * frame_width + x + 1]
                local threshold = BAYER[(y % 8) + 1][(x % 8) + 1] * 4 + 2
                if value > threshold then
                    byte = byte + 128 / (2 ^ bit_index)
                end
            end
            out[#out + 1] = byte
        end
    end
    return out
end

local test_width, test_height = 64, 24
local grey = {}
for y = 0, test_height - 1 do
    for x = 0, test_width - 1 do
        grey[y * test_width + x + 1] = ((x * 4 + y * 7) % 256)
    end
end
local grey_string = string.char(unpack(grey))

local encoder = assert(BWR.newEncoder(test_width, test_height))
local packed = assert(encoder:pack(grey_string))
assert(#packed == (test_width / 8) * test_height, "A packed frame must have width/8 * height bytes")

local reference = referencePack(grey, test_width, test_height)
local mismatches = 0
for index = 1, #reference do
    if packed:byte(index) ~= reference[index] then mismatches = mismatches + 1 end
end
assert(mismatches == 0, "AppDock dithering must match the make.py matrix byte for byte (" .. mismatches .. " mismatches)")

-- Extreme values have to stay predictable: pure white is all ones, pure black
-- is all zeros, because BWR1 stores 1 for white.
local white = assert(encoder:pack(string.rep("\255", test_width * test_height)))
local black = assert(encoder:pack(string.rep("\0", test_width * test_height)))
assert(white == string.rep("\255", #white), "A white frame must pack to all ones")
assert(black == string.rep("\0", #black), "A black frame must pack to all zeros")

expectError(select(1, encoder:pack("short")), select(2, encoder:pack("short")), "A frame of the wrong size must be rejected")

----------------------------------------------------------------
-- Pre-dithered frames and expansion
----------------------------------------------------------------

local predithered = assert(encoder:packPreDithered(white))
assert(predithered == white, "Without inversion a pre-dithered frame must pass through unchanged")
local inverted = assert(encoder:packPreDithered(white, true))
assert(inverted == string.rep("\0", #inverted), "Inversion must flip every bit of a pre-dithered frame")

local expansion = assert(BWR.expandFrame(packed, test_width, test_height))
assert(expansion.width == test_width and expansion.height == test_height, "An expanded frame must keep its dimensions")
assert(frames_allocated == 1, "Expanding a frame must allocate exactly one framebuffer")
local data = ffi.cast("uint8_t*", expansion.data)
for index = 0, (test_width / 8) * test_height - 1 do
    local value = packed:byte(index + 1)
    for bit_index = 0, 7 do
        local expected = (math.floor(value / (2 ^ (7 - bit_index))) % 2 == 1) and 255 or 0
        assert(data[index * 8 + bit_index] == expected,
            "Expansion must turn bit " .. bit_index .. " of byte " .. index .. " into a full byte")
    end
end
assert(BWR.expandFrame(packed, test_width, test_height, expansion) == expansion and frames_allocated == 1,
    "A supplied BWR framebuffer must be reused without another allocation")

expectError(select(1, BWR.expandFrame("short", test_width, test_height)), select(2, BWR.expandFrame("short", test_width, test_height)), "A short frame must be rejected")

----------------------------------------------------------------
-- BWR2 compression, keyframe index and random access
----------------------------------------------------------------

local bwr2_path = os.tmpname()
local bwr2_handle = assert(io.open(bwr2_path, "w+b"))
local writer = assert(BWR.newWriter(bwr2_handle, test_width, test_height, 12, 4))
local frame_bytes = BWR.frameBytes(test_width, test_height)
local black_frame, white_frame = string.rep("\0", frame_bytes), string.rep("\255", frame_bytes)

local legacy_path = os.tmpname()
local legacy_file = assert(io.open(legacy_path, "w+b"))
assert(legacy_file:write(assert(BWR.buildHeader(test_width, test_height, 12, 2)), black_frame, white_frame))
legacy_file:close()
legacy_file = assert(io.open(legacy_path, "rb"))
local legacy_header = assert(BWR.readHeader(legacy_file))
assert(legacy_header.format == "BWR1", "Old raw BWR1 files must remain recognized")
local legacy_reader = assert(BWR.newReader(legacy_file, legacy_header))
assert(legacy_reader:readFrame(0) == black_frame and legacy_reader:readFrame(1) == white_frame,
    "The indexed reader must retain backward-compatible random access to raw BWR1 frames")
legacy_file:close()
os.remove(legacy_path)

local bwr2_frames = {}
for index = 0, 23 do
    local frame = math.floor(index / 6) % 2 == 0 and black_frame or white_frame
    if index % 6 == 3 then
        local changed = frame:byte(21) == 0 and 255 or 0
        frame = frame:sub(1, 20) .. string.char(changed) .. frame:sub(22)
    end
    bwr2_frames[index + 1] = frame
    assert(writer:writeFrame(frame), "BWR2 must accept a complete packed frame")
end
assert(writer:finish(), "BWR2 must finalize its index and frame count")
local bwr2_bytes = writer.bytes_written
bwr2_handle:close()

local bwr2_file = assert(io.open(bwr2_path, "rb"))
local bwr2_header = assert(BWR.readHeader(bwr2_file))
assert(bwr2_header.format == "BWR2" and bwr2_header.version == 2, "The new writer must mark output as BWR2")
assert(bwr2_header.key_interval == 4 and bwr2_header.frames == #bwr2_frames,
    "BWR2 must preserve frame count and keyframe interval")
local reader = assert(BWR.newReader(bwr2_file, bwr2_header))
for _, index in ipairs({ 0, 1, 3, 4, 7, 8, 17, 23, 10, 11, 2, 15 }) do
    local decoded, decode_error = reader:readFrame(index)
    assert(decoded == bwr2_frames[index + 1], "BWR2 seek/decode must reproduce frame " .. index .. ": " .. tostring(decode_error))
end
local skip_reader = assert(BWR.newReader(bwr2_file, bwr2_header))
local decoded_packets = 0
local read_packet = skip_reader._readPacket
skip_reader._readPacket = function(self, ...)
    decoded_packets = decoded_packets + 1
    return read_packet(self, ...)
end
assert(skip_reader:readFrame(8) == bwr2_frames[9], "A fresh cache must read its keyframe")
assert(skip_reader:readFrame(10) == bwr2_frames[11], "A skipped-frame read must still return the requested image")
assert(decoded_packets == 3,
    "A forward skip inside one keyframe group must advance from the cached frame, not decode the prefix twice")
assert(bwr2_bytes < BWR.HEADER_BYTES + #bwr2_frames * frame_bytes,
    "Repeated and near-static frames must compress materially below the BWR1 raw size")
bwr2_file:close()
os.remove(bwr2_path)

----------------------------------------------------------------
-- BRC2 color mode: only pure RGB primaries, black and white
----------------------------------------------------------------

local color_encoder = assert(BWR.newColorEncoder(8, 8))
local red_rgb = string.rep(string.char(255, 0, 0), 64)
local red_indices = assert(color_encoder:pack(red_rgb, false))
assert(#red_indices == 64, "The color encoder must return one palette index per pixel")
for i = 1, #red_indices do assert(red_indices:byte(i) == 3, "Exact red must never become a mixed color") end
local gray_rgb = string.rep(string.char(128, 128, 128), 64)
local gray_indices = assert(color_encoder:pack(gray_rgb, true))
local saw_black, saw_white = false, false
for i=1,#gray_indices do
    local index=gray_indices:byte(i)
    assert(index==1 or index==2, "Neutral grays may dither only between white and black")
    if index==1 then saw_white=true else saw_black=true end
end
assert(saw_black and saw_white, "Color dithering must spatially dither neutral midtones")

local brc_path = os.tmpname()
local brc_file = assert(io.open(brc_path, "w+b"))
local color_writer = assert(BWR.newColorWriter(brc_file, 8, 8, 12, 2))
assert(color_writer:writeFrame(red_indices) and color_writer:writeFrame(gray_indices))
assert(color_writer:finish(), "BRC2 must finalize the indexed color track")
brc_file:close()
brc_file=assert(io.open(brc_path,"rb"))
local color_header=assert(BWR.readHeader(brc_file))
assert(color_header.format=="BRC2" and color_header.is_color and color_header.pixel_format==2
    and color_header.frame_bytes==64, "BRC2 must explicitly identify indexed five-color frames")
local color_reader=assert(BWR.newReader(brc_file,color_header))
assert(color_reader:readFrame(0)==red_indices and color_reader:readFrame(1)==gray_indices,
    "BRC2 seeking must preserve palette indices exactly")
local rgb_frame=assert(BWR.expandColorFrame(red_indices,8,8))
local red_pixel=ffi.cast("ColorRGB32*",rgb_frame.data)[0]
assert(red_pixel.r==255 and red_pixel.g==0 and red_pixel.b==0 and red_pixel.alpha==255,
    "Color display expansion must write pure red without channel mixing")
assert(BWR.expandColorFrame(red_indices,8,8,rgb_frame)==rgb_frame,
    "A supplied color framebuffer must be reused")
local palette_frame=assert(BWR.expandColorFrame(string.char(1,2,3,4,5,0,6,3),8,1))
local expanded=ffi.cast("ColorRGB32*",palette_frame.data)
local expected_colors={{255,255,255},{0,0,0},{255,0,0},{0,255,0},{0,0,255},{255,255,255},{255,255,255},{255,0,0}}
for index,expected_color in ipairs(expected_colors) do
    local pixel=expanded[index-1]
    assert(pixel.r==expected_color[1] and pixel.g==expected_color[2] and pixel.b==expected_color[3]
        and pixel.alpha==255, "Fast color expansion must preserve palette index "..(index-1))
end
color_enabled=false
local grey_frame=assert(BWR.expandColorFrame(string.char(1,2,3,4,5,0,6,3),8,1))
local grey_pixels=ffi.cast("uint8_t*",grey_frame.data)
local expected_luminance={255,0,76,150,29,255,255,76}
for index,expected_value in ipairs(expected_luminance) do
    assert(grey_pixels[index-1]==expected_value, "Fast monochrome expansion must preserve palette luminance")
end
color_enabled=true
brc_file:close(); os.remove(brc_path)

print("AppDock BWR1/BWR2/BRC2 test: OK")
