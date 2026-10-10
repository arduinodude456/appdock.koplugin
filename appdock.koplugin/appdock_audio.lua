--[[--
AppDock audio output for BWR1/BWR2 playback.

E-Ink readers have no audio framework that KOReader could drive directly, so the
player hands the companion WAV file to whatever the device already provides:

* `gst-launch-1.0` with `mtkbtmwrpcaudiosink` on MediaTek Kobo models, which is
  also the route an already paired Bluetooth headset uses,
* `aplay`, or
* `tinyplay`.

The same backend choices are used by the `videoplayer.koplugin` "Snake" release.
RIFF chunks are parsed rather than assuming a fixed 44-byte WAV header. The
MediaTek GStreamer backend streams just the WAV's PCM data into `fdsrc`, matching
the working Kobo playback path without requiring the optional `wavparse` plugin.
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

local function putU16(value)
    value = math.floor(value) % 65536
    return string.char(value % 256, math.floor(value / 256) % 256)
end

function Audio.findCommand(name)
    local pipe = io.popen("command -v " .. name .. " 2>/dev/null", "r")
    if not pipe then return nil end
    local path = pipe:read("*l")
    pipe:close()
    if path and path ~= "" then return path end
    return nil
end

local function parseFormatChunk(data)
    if not data or #data < 16 then return nil end
    local format = u16(data, 1)
    local channels = u16(data, 3)
    local sample_rate = u32(data, 5)
    local block_align = u16(data, 13)
    local bits_per_sample = u16(data, 15)
    if not format or not channels or not sample_rate or not block_align then return nil end
    if channels < 1 or sample_rate < 1 or block_align < 1 then return nil end
    return {
        format = format,
        channels = channels,
        sample_rate = sample_rate,
        block_align = block_align,
        bits_per_sample = bits_per_sample,
    }
end

function Audio.parseWavHeader(header)
    if not header or #header < 12 then return nil end
    if header:sub(1, 4) ~= "RIFF" or header:sub(9, 12) ~= "WAVE" then return nil end
    local offset, format, data_bytes, data_offset = 13, nil, nil, nil
    while offset + 7 <= #header do
        local id, size = header:sub(offset, offset + 3), u32(header, offset + 4)
        if not size then return nil end
        local payload = offset + 8
        if id == "fmt " then
            format = parseFormatChunk(header:sub(payload, math.min(#header, payload + size - 1)))
        elseif id == "data" then
            data_bytes, data_offset = size, payload - 1
        end
        if format and data_bytes then
            format.data_bytes, format.data_offset = data_bytes, data_offset
            format.duration = data_bytes / (format.sample_rate * format.block_align)
            return format
        end
        offset = payload + size + (size % 2)
    end
    return nil
end

-- Walk RIFF chunks by seeking instead of reading the audio payload. This also
-- handles LIST/JUNK chunks emitted by ffmpeg before or between fmt/data.
function Audio.readWavInfo(file)
    if not file then return nil end
    local file_size = file:seek("end")
    if not file_size or file_size < 12 then return nil end
    file:seek("set", 0)
    local riff = file:read(12)
    if not riff or #riff ~= 12 or riff:sub(1, 4) ~= "RIFF" or riff:sub(9, 12) ~= "WAVE" then return nil end
    local offset, format, data_bytes, data_offset = 13, nil, nil, nil
    local chunks = 0
    while offset + 7 <= file_size and chunks < 4096 do
        chunks = chunks + 1
        file:seek("set", offset - 1)
        local chunk = file:read(8)
        if not chunk or #chunk ~= 8 then return nil end
        local id, size = chunk:sub(1, 4), u32(chunk, 5)
        if not size or size > file_size then return nil end
        local payload_offset = offset + 7
        if id == "fmt " then
            format = parseFormatChunk(file:read(math.min(size, 64)))
        elseif id == "data" then
            data_bytes = math.min(size, math.max(0, file_size - payload_offset))
            data_offset = payload_offset
        end
        if format and data_bytes then
            format.data_bytes, format.data_offset = data_bytes, data_offset
            format.duration = data_bytes / (format.sample_rate * format.block_align)
            return format
        end
        offset = payload_offset + size + (size % 2) + 1
    end
    return nil
end

function Audio.durationOf(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local info = Audio.readWavInfo(file)
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
        process_group = false,
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
    local info = Audio.readWavInfo(input)
    if not info or info.format ~= 1 or info.bits_per_sample ~= 16 then
        input:close()
        return nil
    end
    local requested = math.floor(start_seconds * info.sample_rate) * info.block_align
    local offset = math.min(info.data_bytes, requested)
    offset = offset - offset % info.block_align
    input:seek("set", info.data_offset + offset)
    local remaining = info.data_bytes - offset
    remaining = remaining - remaining % info.block_align
    local output_path = os.tmpname()
    local output = io.open(output_path, "wb")
    if not output then
        input:close()
        return nil
    end
    output:write("RIFF" .. putU32(36 + remaining) .. "WAVEfmt " .. putU32(16)
        .. putU16(info.format) .. putU16(info.channels) .. putU32(info.sample_rate)
        .. putU32(info.sample_rate * info.block_align) .. putU16(info.block_align)
        .. putU16(info.bits_per_sample) .. "data" .. putU32(remaining))
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
        local input = io.open(self.clip_path, "rb")
        local info = input and Audio.readWavInfo(input) or nil
        if input then input:close() end
        if not info or info.format ~= 1 or info.bits_per_sample ~= 16 then
            return nil, _("The companion WAV must contain 16-bit PCM for the MediaTek audio output.")
        end
        -- The Kobo MTK sink worked with raw PCM through fdsrc in 7.8.51.
        -- Using wavparse here silently fails on some device builds where that
        -- optional GStreamer parser is absent. Skip the RIFF chunks precisely
        -- (including LIST/JUNK metadata) and feed the PCM with its real caps.
        local pipeline = "tail -c +" .. tostring(info.data_offset + 1) .. " "
            .. shellQuote(self.clip_path)
            .. " | exec " .. shellQuote(self.command)
            .. " fdsrc fd=0 ! audio/x-raw,format=S16LE,rate=" .. tostring(info.sample_rate)
            .. ",channels=" .. tostring(info.channels)
            .. ",layout=interleaved"
            .. " ! audioconvert ! audioresample ! mtkbtmwrpcaudiosink"
        local setsid = Audio.findCommand("setsid")
        if setsid then
            command = shellQuote(setsid) .. " sh -c " .. shellQuote(pipeline)
            self.process_group = true
        else
            command = "sh -c " .. shellQuote(pipeline)
            self.process_group = false
        end
    elseif self.command_name == "aplay" then
        command = shellQuote(self.command) .. " -q " .. shellQuote(self.clip_path)
    else
        command = shellQuote(self.command) .. " " .. shellQuote(self.clip_path)
    end
    local pipe = io.popen(command .. " >/dev/null 2>&1 & echo $!", "r")
    if not pipe then return nil, _("The audio process could not be started.") end
    self.pid = tonumber(pipe:read("*l"))
    pipe:close()
    if not self.pid then return nil, _("The audio process returned no identifier.") end
    logger.info("appdock youtube: audio started", self.command_name, "pid", self.pid)
    self.paused = false
    return true
end

function Audio:pause()
    if self.pid and not self.paused then
        os.execute("kill -STOP " .. (self.process_group and "-" or "")
            .. tostring(self.pid) .. " 2>/dev/null")
        self.paused = true
    end
end

function Audio:resume()
    if self.pid and self.paused then
        os.execute("kill -CONT " .. (self.process_group and "-" or "")
            .. tostring(self.pid) .. " 2>/dev/null")
        self.paused = false
    end
end

function Audio:stop()
    if self.pid then
        os.execute("kill -TERM " .. (self.process_group and "-" or "")
            .. tostring(self.pid) .. " 2>/dev/null")
        self.pid = nil
    end
    self.process_group = false
    if self.clip_path and self.clip_path ~= self.path then
        os.remove(self.clip_path)
    end
    self.clip_path = nil
    self.paused = false
end

return Audio
