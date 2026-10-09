--[[--
AppDock audio output for BWR1 playback.

E-Ink readers have no audio framework that KOReader could drive directly, so the
player hands the companion WAV file to whatever the device already provides:

* `gst-launch-1.0` with `mtkbtmwrpcaudiosink` on MediaTek Kobo models, which is
  also the route an already paired Bluetooth headset uses,
* `aplay`, or
* `tinyplay`.

The same layering is used by the `videoplayer.koplugin` "Snake" release; this
module keeps only what playback needs and adds the process-group handling that
makes pause and seek reliable.
--]]--

local logger = require("logger")
local _ = require("gettext")

local Audio = {}
Audio.__index = Audio

local function shellQuote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function u16(data, offset)
    local low, high = data:byte(offset, offset + 1)
    if not low or not high then return nil end
    return low + high * 256
end

local function u32(data, offset)
    local a, b, c, d = data:byte(offset, offset + 3)
    if not a or not b or not c or not d then return nil end
    return a + b * 256 + c * 65536 + d * 16777216
end

local function putU32(value)
    value = math.floor(value) % 4294967296
    return string.char(
        value % 256,
        math.floor(value / 256) % 256,
        math.floor(value / 65536) % 256,
        math.floor(value / 16777216) % 256
    )
end

function Audio.findCommand(name)
    local pipe = io.popen("command -v " .. name .. " 2>/dev/null", "r")
    if not pipe then return nil end
    local path = pipe:read("*l")
    pipe:close()
    if path and path ~= "" then return path end
    return nil
end

function Audio.parseWavHeader(header)
    if not header or #header < 44 then return nil end
    if header:sub(1, 4) ~= "RIFF" or header:sub(9, 12) ~= "WAVE" then return nil end
    local sample_rate = u32(header, 25)
    local block_align = u16(header, 33)
    local data_bytes = u32(header, 41)
    if not sample_rate or not block_align or not data_bytes then return nil end
    if sample_rate < 1 or block_align < 1 then return nil end
    return {
        sample_rate = sample_rate,
        block_align = block_align,
        data_bytes = data_bytes,
        duration = data_bytes / (sample_rate * block_align),
    }
end

function Audio.durationOf(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local info = Audio.parseWavHeader(file:read(44))
    file:close()
    return info and info.duration or nil
end

function Audio.new(path)
    local instance = setmetatable({
        path = path,
        clip_path = nil,
        pid = nil,
        paused = false,
        command = nil,
        command_name = nil,
        start_log = nil,
    }, Audio)

    local gst_launch = Audio.findCommand("gst-launch-1.0")
    local gst_inspect = Audio.findCommand("gst-inspect-1.0")
    if gst_launch and gst_inspect then
        local probe = io.popen(shellQuote(gst_inspect) .. " mtkbtmwrpcaudiosink 2>/dev/null", "r")
        local output = probe and probe:read("*a") or ""
        if probe then probe:close() end
        if output:find("mtkbtmwrpcaudiosink", 1, true) then
            instance.command = gst_launch
            instance.command_name = "mtk-gstreamer"
        end
    end
    if not instance.command then
        instance.command = Audio.findCommand("aplay")
        instance.command_name = instance.command and "aplay" or nil
    end
    if not instance.command then
        instance.command = Audio.findCommand("tinyplay")
        instance.command_name = instance.command and "tinyplay" or nil
    end
    logger.info("appdock youtube: audio backend", instance.command_name or "none")
    return instance
end

function Audio:isAvailable()
    return self.command ~= nil
end

function Audio:getError()
    if self.command then return nil end
    return _("No supported WAV audio output was found. AppDock uses gst-launch-1.0 with mtkbtmwrpcaudiosink, aplay or tinyplay.")
end

-- `aplay` and `tinyplay` cannot seek, so a seek is served by writing a small
-- WAV clip that starts at the requested offset.
function Audio:_makeClip(start_seconds)
    start_seconds = math.max(0, tonumber(start_seconds) or 0)
    if start_seconds <= 0 then return self.path end
    local input = io.open(self.path, "rb")
    if not input then return nil end
    local header = input:read(44)
    local info = Audio.parseWavHeader(header)
    if not info then
        input:close()
        return nil
    end
    local requested = math.floor(start_seconds * info.sample_rate) * info.block_align
    local offset = math.min(info.data_bytes, requested)
    input:seek("set", 44 + offset)
    local remaining = info.data_bytes - offset
    local output_path = os.tmpname()
    local output = io.open(output_path, "wb")
    if not output then
        input:close()
        return nil
    end
    output:write(header:sub(1, 4) .. putU32(36 + remaining) .. header:sub(9, 40) .. putU32(remaining))
    while remaining > 0 do
        local chunk = input:read(math.min(65536, remaining))
        if not chunk or #chunk == 0 then break end
        output:write(chunk)
        remaining = remaining - #chunk
    end
    output:close()
    input:close()
    return output_path
end

function Audio:startFrom(seconds)
    if not self.command then return nil, self:getError() end
    local probe = io.open(self.path, "rb")
    if not probe then return nil, _("The companion WAV file cannot be opened.") end
    probe:close()
    self:stop()
    self.clip_path = self:_makeClip(seconds or 0)
    if not self.clip_path then
        return nil, _("The companion WAV file could not be prepared for this position.")
    end

    local command
    if self.command_name == "mtk-gstreamer" then
        local pipeline = "tail -c +45 " .. shellQuote(self.clip_path)
            .. " | exec " .. shellQuote(self.command)
            .. " fdsrc fd=0 ! audio/x-raw,format=S16LE,rate=44100,channels=2"
            .. " ! audioconvert ! audioresample ! mtkbtmwrpcaudiosink"
        local setsid = Audio.findCommand("setsid")
        command = setsid and (shellQuote(setsid) .. " sh -c " .. shellQuote(pipeline))
            or ("sh -c " .. shellQuote(pipeline))
        self.start_log = os.tmpname()
        command = command .. " >" .. shellQuote(self.start_log) .. " 2>&1"
    elseif self.command_name == "aplay" then
        command = shellQuote(self.command) .. " -q " .. shellQuote(self.clip_path)
    else
        command = shellQuote(self.command) .. " " .. shellQuote(self.clip_path)
    end

    local launch_tail = self.start_log and " & echo $!" or " >/dev/null 2>&1 & echo $!"
    local pipe = io.popen(command .. launch_tail, "r")
    if not pipe then return nil, _("The audio process could not be started.") end
    self.pid = tonumber(pipe:read("*l"))
    pipe:close()
    if not self.pid then return nil, _("The audio process returned no identifier.") end
    logger.info("appdock youtube: audio started", self.command_name, "pid", self.pid)
    self.paused = false
    return true
end

-- The raw PCM pipeline is unchanged from 7.8.26. Its normal GStreamer output
-- is used only to let the player anchor the first frame to the MTK sink clock.
function Audio:requiresStartConfirmation()
    return self.command_name == "mtk-gstreamer"
end

-- Kobo's MTK Bluetooth sink reports New clock before its hardware/ring buffer
-- becomes audible. On the affected Kobo firmware this measured startup
-- latency is about four seconds; aplay/tinyplay do not use this compensation.
function Audio:startupLatency()
    return self:requiresStartConfirmation() and 4.0 or 0
end

function Audio:isPlaybackReady()
    if not self:requiresStartConfirmation() then return true end
    if not self.start_log then return false end
    local log = io.open(self.start_log, "rb")
    if not log then return false end
    local output = log:read("*a") or ""
    log:close()
    if output:find("New clock:", 1, true) then return true end
    if output:find("ERROR:", 1, true) then
        return nil, output:match("ERROR:[^\r\n]*") or output
    end
    return false
end

function Audio:pause()
    if self.pid and not self.paused then
        os.execute("kill -STOP -" .. tostring(self.pid) .. " 2>/dev/null")
        self.paused = true
    end
end

function Audio:resume()
    if self.pid and self.paused then
        os.execute("kill -CONT -" .. tostring(self.pid) .. " 2>/dev/null")
        self.paused = false
    end
end

function Audio:stop()
    if self.pid then
        os.execute("kill -TERM -" .. tostring(self.pid) .. " 2>/dev/null")
        self.pid = nil
    end
    if self.clip_path and self.clip_path ~= self.path then
        os.remove(self.clip_path)
    end
    self.clip_path = nil
    if self.start_log then
        os.remove(self.start_log)
        self.start_log = nil
    end
    self.paused = false
end

return Audio
