-- AppDock audio process-control and seek regression tests.

package.preload["gettext"] = function() return function(text) return text end end
package.preload["logger"] = function() return { info = function() end, warn = function() end, err = function() end } end

local Audio = dofile((os.getenv("APPDOCK_PLUGIN_DIR") or "/home/ubuntu/appdock.koplugin/appdock.koplugin/") .. "appdock_audio.lua")
local function u16(value)
    return string.char(value % 256, math.floor(value / 256) % 256)
end
local function u32(value)
    return string.char(value % 256, math.floor(value / 256) % 256,
        math.floor(value / 65536) % 256, math.floor(value / 16777216) % 256)
end

local wav_path = "/tmp/appdock audio sync test.wav"
local data_bytes = 17640 -- 100 ms of 44.1 kHz, 16-bit stereo PCM.
local format_chunk = "fmt " .. u32(16) .. u16(1) .. u16(2) .. u32(44100)
    .. u32(176400) .. u16(4) .. u16(16)
local list_chunk = "LIST" .. u32(16) .. "INFO" .. "INAM" .. u32(4) .. "Test"
local wav_header = "RIFF" .. u32(4 + #format_chunk + #list_chunk + 8 + data_bytes)
    .. "WAVE" .. format_chunk .. list_chunk .. "data" .. u32(data_bytes)
local wav = assert(io.open(wav_path, "wb"))
assert(wav:write(wav_header, string.rep("\0", data_bytes)))
assert(wav:close())
assert(math.abs(Audio.durationOf(wav_path) - 0.1) < 0.001,
    "The WAV duration parser must find the data chunk after LIST metadata")

local original_find, original_popen, original_execute = Audio.findCommand, io.popen, os.execute
local spawned, signals, next_pid = {}, {}, 9000
local audio_mode = "aplay"
Audio.findCommand = function(name)
    if name == "aplay" then return "/usr/bin/aplay" end
    if audio_mode == "gst" and name == "gst-launch-1.0" then return "/usr/bin/gst-launch-1.0" end
    if audio_mode == "gst" and name == "gst-inspect-1.0" then return "/usr/bin/gst-inspect-1.0" end
    if audio_mode == "gst" and name == "setsid" then return "/usr/bin/setsid" end
    return nil
end
io.popen = function(command)
    if command:find("gst%-inspect%-1%.0") then
        return { read = function() return "mtkbtmwrpcaudiosink" end, close = function() return true end }
    end
    spawned[#spawned + 1] = command
    next_pid = next_pid + 1
    local pid = next_pid
    return { read = function() return tostring(pid) end, close = function() return true end }
end
os.execute = function(command)
    signals[#signals + 1] = command
    return true
end

local aplay = Audio.new(wav_path)
assert(aplay.command_name == "aplay", "aplay must be selected when no MediaTek GStreamer sink is available")
assert(aplay:startFrom(0), "Audio playback must start")
assert(spawned[1]:find("/usr/bin/aplay", 1, true), "The selected backend must launch directly")
local aplay_pid = aplay.pid
aplay:pause()
assert(signals[#signals]:find("kill %-STOP " .. aplay_pid), "Pause must stop the actual aplay PID, not a nonexistent process group")
aplay:resume()
assert(signals[#signals]:find("kill %-CONT " .. aplay_pid), "Resume must continue the actual aplay PID")
assert(aplay:startFrom(0.01), "Seeking must restart aplay from a prepared WAV clip")
assert(signals[#signals]:find("kill %-TERM " .. aplay_pid), "A seek must terminate the previous aplay process")
local clip = assert(io.open(aplay.clip_path, "rb"))
local clip_info = assert(Audio.readWavInfo(clip))
assert(clip_info.data_offset == 44 and math.abs(clip_info.duration - 0.09) < 0.001,
    "Seek clips must use a valid canonical WAV header and start at the selected audio sample")
clip:close()
local seek_pid = aplay.pid
aplay:stop()
assert(signals[#signals]:find("kill %-TERM " .. seek_pid), "Stop must terminate the current aplay PID")

audio_mode = "gst"
local gst = Audio.new(wav_path)
assert(gst.command_name == "mtk-gstreamer", "The MediaTek sink must remain preferred when detected")
assert(gst:startFrom(0), "GStreamer playback must start")
local gst_command = spawned[#spawned]
assert(gst_command:find("tail %-c %+69", 1),
    "GStreamer must skip the RIFF and LIST chunks to reach the actual PCM payload")
assert(gst_command:find("fdsrc fd=0", 1, true) and not gst_command:find("wavparse", 1, true),
    "The MediaTek backend must use its known-good raw-PCM fdsrc pipeline without wavparse")
assert(gst_command:find("rate=44100,channels=2,layout=interleaved", 1, true),
    "Raw PCM caps must match the WAV format and specify interleaved channels")
assert(gst_command:find("setsid", 1, true),
    "The GStreamer pipeline must run in its own process group for reliable pause and stop")
local gst_pid = gst.pid
gst:pause()
assert(signals[#signals]:find("kill %-STOP %-" .. gst_pid), "GStreamer pause must signal its playback process group")
gst:stop()
assert(signals[#signals]:find("kill %-TERM %-" .. gst_pid), "GStreamer stop must terminate its playback process group")

Audio.findCommand, io.popen, os.execute = original_find, original_popen, original_execute
os.remove(wav_path)
print("AppDock audio process-control test: OK")
