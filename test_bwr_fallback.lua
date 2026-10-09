-- BWR2 must remain readable when the platform has no loadable system zlib.

package.preload["gettext"] = function() return function(text) return text end end
local ffi = require("ffi")
local plugin_dir = os.getenv("APPDOCK_PLUGIN_DIR") or "/home/ubuntu/appdock.koplugin/appdock.koplugin/"
local original_load = ffi.load
ffi.load = function() error("zlib intentionally disabled by regression test") end
local BWR = dofile(plugin_dir .. "appdock_bwr.lua")
ffi.load = original_load

local width, height, fps, interval = 64, 24, 12, 4
local frame_bytes = BWR.frameBytes(width, height)
local black, white = string.rep("\0", frame_bytes), string.rep("\255", frame_bytes)
local frames = {}
local path = os.tmpname()
local file = assert(io.open(path, "w+b"))
local writer = assert(BWR.newWriter(file, width, height, fps, interval))
for index = 0, 23 do
    local frame = math.floor(index / 6) % 2 == 0 and black or white
    if index % 6 == 3 then
        frame = frame:sub(1, 30) .. string.char(frame:byte(31) == 0 and 255 or 0) .. frame:sub(32)
    end
    frames[index + 1] = frame
    assert(writer:writeFrame(frame))
end
assert(writer:finish())
local encoded_size = writer.bytes_written
file:close()

file = assert(io.open(path, "rb"))
local header = assert(BWR.readHeader(file))
local reader = assert(BWR.newReader(file, header))
for index = 0, #frames - 1 do
    assert(reader:readFrame(index) == frames[index + 1], "The built-in codec must decode frame " .. index)
end
assert(encoded_size < BWR.HEADER_BYTES + #frames * frame_bytes,
    "The built-in zero-run and repeat codecs must compress without zlib")
file:close()
os.remove(path)
print("AppDock BWR2 no-zlib fallback test: OK")
