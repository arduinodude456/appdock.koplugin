-- AppDock BWR1 format test.
--
-- Verifies the container contract that the YouTube DApp writes and the player
-- reads, and checks the ordered dithering against an independent reference
-- implementation of the matrix used by videoplayer.koplugin's make.py.

local plugin_dir = os.getenv("APPDOCK_PLUGIN_DIR") or "/home/ubuntu/appdock.koplugin/appdock.koplugin/"
local ffi = require("ffi")

package.preload["gettext"] = function() return function(text) return text end end

local frames_allocated = 0
package.preload["ffi/blitbuffer"] = function()
    return {
        TYPE_BB8 = 1,
        COLOR_WHITE = "white", COLOR_BLACK = "black",
        COLOR_DARK_GRAY = "dark", COLOR_LIGHT_GRAY = "light", COLOR_GRAY = "gray",
        COLOR_GRAY_7 = "g7", COLOR_GRAY_8 = "g8",
        -- KOReader calls this as a module function: Blitbuffer.new(w, h, type)
        new = function(width, height)
            frames_allocated = frames_allocated + 1
            return {
                width = width,
                height = height,
                data = ffi.new("uint8_t[?]", width * height),
                getWidth = function(self) return self.width end,
                getHeight = function(self) return self.height end,
                free = function() end,
            }
        end,
    }
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

expectError(select(1, BWR.expandFrame("short", test_width, test_height)), select(2, BWR.expandFrame("short", test_width, test_height)), "A short frame must be rejected")

print("AppDock BWR1 test: OK")
