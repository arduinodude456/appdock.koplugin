--[[--
AppDock YouTube: search, download and convert videos to compressed BWR2 for E-Ink.

The DApp never talks to YouTube itself. It drives two well-known command line
tools that the user installs once:

* `yt-dlp` resolves and downloads a video,
* `ffmpeg` decodes it to grey frames and extracts the companion WAV file.

FFmpeg performs the 1-bit dithering by default for speed; its `monow` bit sense
is probed at runtime. The optional AppDock Bayer mode uses the same 8x8 ordered
matrix as the `videoplayer.koplugin` release "Snake". Existing BWR1 videos
remain readable; new AppDock output uses compressed BWR2.

Playback is handled by `appdock_player.lua` and stays inside `context.dimen`.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local ffi = require("ffi")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local ImageWidget
pcall(function() ImageWidget = require("ui/widget/imagewidget") end)
local HorizontalSpan = require("ui/widget/horizontalspan")
local AppDockDialogs = require("appdock_dialogs")
local InfoMessage = AppDockDialogs.InfoMessage
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = AppDockDialogs.InputDialog
local OverlapGroup = require("ui/widget/overlapgroup")
local TextWidget = require("ui/widget/textwidget")
local TextBoxWidget = require("appdock_text").TextBoxWidget
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local AppDockKeyboard = require("appdock_keyboard")
local BWR = require("appdock_bwr")
local DAppLogo = require("appdock_logo")
local Player = require("appdock_player")

local Screen = Device.screen

local YouTube = {}
YouTube.__index = YouTube

local function scale(value)
    return Screen:scaleBySize(value)
end

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

local function trim(value)
    if type(value) ~= "string" then return "" end
    return value:match("^%s*(.-)%s*$") or ""
end

local function basename(path)
    return (path or ""):match("([^/]+)$") or path or ""
end

local function fileExists(path)
    local handle = path and io.open(path, "rb")
    if handle then handle:close(); return true end
    return false
end

-- TextWidget wraps at max_width, which would overflow a fixed-height row, so
-- long strings are shortened first. `keep_end` keeps the informative tail of a
-- path visible instead of its beginning.
local function fitText(text, max_width, font_size, keep_end)
    text = tostring(text or "")
    local budget = math.max(4, math.floor(max_width / math.max(1, font_size * 0.5)))
    if #text <= budget then return text end
    if keep_end then return "…" .. text:sub(#text - budget + 2) end
    return text:sub(1, budget - 1) .. "…"
end

YouTube.fitText = fitText

local function shellQuote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function emptySizedWidget(width, height)
    return CenterContainer:new{ dimen = Geom:new{ w = width, h = height }, HorizontalSpan:new{ width = 0 } }
end

local function formatDuration(seconds)
    seconds = tonumber(seconds)
    if not seconds or seconds <= 0 then return "" end
    seconds = math.floor(seconds)
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    if hours > 0 then
        return string.format("%d:%02d:%02d", hours, minutes, seconds % 60)
    end
    return string.format("%d:%02d", minutes, seconds % 60)
end

local function humanSize(bytes)
    bytes = tonumber(bytes) or 0
    if bytes >= 1024 * 1024 * 1024 then return string.format("%.1f GB", bytes / 1024 / 1024 / 1024) end
    if bytes >= 1024 * 1024 then return string.format("%.1f MB", bytes / 1024 / 1024) end
    if bytes >= 1024 then return string.format("%.0f kB", bytes / 1024) end
    return tostring(math.floor(bytes)) .. " B"
end

YouTube.formatDuration = formatDuration
YouTube.humanSize = humanSize

----------------------------------------------------------------
-- YouTube look: colours and small drawing helpers
----------------------------------------------------------------

-- true: dark theme like the YouTube app, false: light theme. Home, Watch and
-- Results use these colours; the Tools, Setup and download progress screens
-- keep the plain white layout.
local YT_DARK = true

local function gray(level)
    return Blitbuffer.Color8(level)
end

local YT = YT_DARK and {
    bg = gray(0x0F), fg = gray(0xFF), sub = gray(0xAA),
    chip = gray(0x27), chip_fg = gray(0xFF),
    chip_on = gray(0xFF), chip_on_fg = gray(0x0F),
    thumb = gray(0x27), line = gray(0x2E),
    avatar = gray(0x55), avatar_fg = gray(0xFF),
    badge = gray(0x00), badge_fg = gray(0xFF),
} or {
    bg = gray(0xFF), fg = gray(0x0F), sub = gray(0x60),
    chip = gray(0xF2), chip_fg = gray(0x0F),
    chip_on = gray(0x0F), chip_on_fg = gray(0xFF),
    thumb = gray(0xE5), line = gray(0xE5),
    avatar = gray(0x8A), avatar_fg = gray(0xFF),
    badge = gray(0x00), badge_fg = gray(0xFF),
}

-- Number of UTF-8 characters (Lua 5.1 has no utf8 library).
local function charCount(text)
    return select(2, tostring(text or ""):gsub("[^\128-\191]", ""))
end

-- Byte length of the first `count` UTF-8 characters.
local function utf8Prefix(text, count)
    local index, seen = 1, 0
    while index <= #text and seen < count do
        local byte = text:byte(index)
        local step = 1
        if byte >= 240 then step = 4 elseif byte >= 224 then step = 3 elseif byte >= 192 then step = 2 end
        index = index + step
        seen = seen + 1
    end
    return math.min(#text, index - 1)
end

-- Splits a title into at most `max_lines` lines at word boundaries. The last
-- line may still be too long; TextWidget shortens it with an ellipsis.
local function wrapLines(text, max_width, font_size, max_lines)
    text = trim(tostring(text or ""))
    local budget = math.max(6, math.floor(max_width / math.max(1, scale(font_size) * 0.52)))
    local lines, rest = {}, text
    while #lines < max_lines - 1 and charCount(rest) > budget do
        local stop = utf8Prefix(rest, budget)
        local head = rest:sub(1, stop)
        local space = head:match("^.*()%s")
        local cut = (space and space > 1) and space or stop
        lines[#lines + 1] = trim(rest:sub(1, cut))
        rest = trim(rest:sub(cut + 1))
    end
    lines[#lines + 1] = rest
    return lines
end

local function paintRound(bb, x, y, w, h, color, radius)
    if w <= 0 or h <= 0 then return end
    radius = math.min(radius or 0, math.floor(math.min(w, h) / 2))
    if radius > 1 and bb.paintRoundedRect then
        bb:paintRoundedRect(x, y, w, h, color, radius)
    else
        bb:paintRect(x, y, w, h, color)
    end
end

local function paintDisc(bb, center_x, center_y, radius, color)
    if bb.paintCircle then
        bb:paintCircle(center_x, center_y, radius, color)
    else
        paintRound(bb, center_x - radius, center_y - radius, radius * 2, radius * 2, color, radius)
    end
end

local function ageLabel(timestamp)
    timestamp = tonumber(timestamp)
    if not timestamp or timestamp <= 0 then return "" end
    local delta = math.max(0, os.time() - timestamp)
    if delta < 3600 then
        return string.format(_("%d min ago"), math.max(1, math.floor(delta / 60)))
    elseif delta < 86400 then
        return string.format(_("%d h ago"), math.floor(delta / 3600))
    elseif delta < 86400 * 30 then
        return string.format(_("%d d ago"), math.floor(delta / 86400))
    end
    return string.format(_("%d mo ago"), math.floor(delta / (86400 * 30)))
end

-- "YouTube · 1.2 MB · 4 h ago", the counterpart of "channel · views · age".
local function entryMeta(entry)
    local parts = { "YouTube" }
    if (entry.size or 0) > 0 then parts[#parts + 1] = humanSize(entry.size) end
    local age = ageLabel(entry.modified)
    if age ~= "" then parts[#parts + 1] = age end
    return table.concat(parts, " · ")
end

local function chipWidth(text)
    return scale(26) + charCount(text) * scale(10)
end

----------------------------------------------------------------
-- Pure helpers (unit tested)
----------------------------------------------------------------

-- Accepts every link shape a reader is likely to paste and returns the video
-- id, or nil when the text is not a YouTube link.
function YouTube.parseVideoId(value)
    local text = trim(value)
    if text == "" then return nil end
    local id = text:match("[?&]v=([%w%-_]+)")
    if id then return id end
    id = text:match("youtu%.be/([%w%-_]+)")
    if id then return id end
    id = text:match("youtube%.com/shorts/([%w%-_]+)")
    if id then return id end
    id = text:match("youtube%.com/live/([%w%-_]+)")
    if id then return id end
    id = text:match("youtube%.com/embed/([%w%-_]+)")
    if id then return id end
    id = text:match("youtube%-nocookie%.com/embed/([%w%-_]+)")
    if id then return id end
    return nil
end

-- Everything that is a link becomes a download, everything else a search.
function YouTube.classifyInput(value)
    local text = trim(value)
    if text == "" then return nil end
    if text:match("^%a[%w+%.%-]*://") then
        local id = YouTube.parseVideoId(text)
        if id then return "video", id end
        if text:match("youtube%.com") or text:match("youtu%.be") then
            return "unsupported", text
        end
        return "unsupported", text
    end
    if text:match("^[%w%-_]+$") and #text == 11 and not text:match("^%d+$") then
        return "video", text
    end
    return "search", text
end

function YouTube.watchUrl(id)
    return "https://www.youtube.com/watch?v=" .. tostring(id or "")
end

-- Turns a title into a file name that needs no escaping in a shell command but
-- still keeps letters such as umlauts. Bytes above 127 are copied verbatim so
-- UTF-8 sequences survive; everything else is reduced to letters, digits, "-",
-- "_" and single underscores between words.
function YouTube.slugify(title, fallback)
    local text = trim(title):gsub("&amp;", "&")
    local out = {}
    for index = 1, #text do
        local byte = text:byte(index)
        local character = text:sub(index, index)
        if byte >= 128 then
            out[#out + 1] = character
        elseif byte == 38 then
            out[#out + 1] = " and "
        elseif (byte >= 48 and byte <= 57) or (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122)
            or character == "-" or character == "_"
        then
            out[#out + 1] = character
        else
            out[#out + 1] = " "
        end
    end
    text = table.concat(out):gsub("%s+", "_"):gsub("_+", "_"):gsub("^_", ""):gsub("_$", "")
    if #text > 58 then
        text = text:sub(1, 58)
        -- Never cut a UTF-8 sequence in half.
        while #text > 0 do
            local byte = text:byte(#text)
            if byte >= 128 and byte < 192 then text = text:sub(1, #text - 1) else break end
        end
        text = text:gsub("_$", "")
    end
    if text == "" then text = trim(fallback) ~= "" and trim(fallback) or "video" end
    return text
end

-- Parses the tab separated output of `yt-dlp --print`. Entries without an id
-- are dropped instead of producing an unusable row.
function YouTube.parseSearchOutput(text)
    local results = {}
    for line in tostring(text or ""):gmatch("[^\r\n]+") do
        local id, title, duration, uploader, thumbnail = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
        if not id then
            id, title, duration, uploader = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
        end
        if id and id:match("^[%w%-_]+$") and #id >= 5 then
            local seconds = tonumber(duration)
            results[#results + 1] = {
                id = id,
                title = trim(title) ~= "" and trim(title) or id,
                duration = seconds and seconds > 0 and seconds or nil,
                uploader = trim(uploader) ~= "" and trim(uploader) or nil,
                thumbnail = trim(thumbnail) ~= "" and trim(thumbnail) or nil,
                url = YouTube.watchUrl(id),
            }
        end
    end
    return results
end

function YouTube:_cacheThumbnail(result, target_path)
    if type(result) ~= "table" or not result.id then return nil end
    local cache = self:_outputDirectory() .. "/.thumbnails"
    os.execute("mkdir -p " .. shellQuote(cache) .. " >/dev/null 2>&1")
    local path = target_path or (cache .. "/" .. result.id .. ".jpg")
    result.thumbnail_path = path
    if result.thumbnail and not fileExists(path) then
        local download = "(command -v curl >/dev/null 2>&1 && curl -L --fail --max-time 15 -sS -o "
            .. shellQuote(path) .. " " .. shellQuote(result.thumbnail)
            .. " || (command -v wget >/dev/null 2>&1 && wget -q -T 15 -O "
            .. shellQuote(path) .. " " .. shellQuote(result.thumbnail) .. "))"
        os.execute("setsid sh -c " .. shellQuote(download) .. " >/dev/null 2>&1 &")
    end
    return path
end

-- Reads the download percentage out of a yt-dlp/youtube-dl progress line.
function YouTube.parseProgress(text)
    local last
    for line in tostring(text or ""):gmatch("[^\r\n]+") do
        local value = line:match("^%[download%]%s+([%d%.]+)%%")
        if not value then
            value = line:match("APPDOCK_PROGRESS%s+([%d%.]+)")
        end
        local number = tonumber(value)
        if number then last = clamp(number, 0, 100) end
    end
    return last
end

-- YouTube's default browser clients have recently been switched to streaming
-- modes that frequently return expired or forbidden media URLs to yt-dlp. The
-- Android client still supplies a direct, modest-quality stream, which is a
-- better fit for this E-Ink converter and does not require a JS runtime.
local YOUTUBE_PLAYER_CLIENT = "youtube:player_client=android"

function YouTube.buildDownloadCommand(ytdlp, ffmpeg, source_file, source, max_height)
    local height = tonumber(max_height) or 480
    local format = string.format(
        "bv*[height<=%d][ext=mp4]+ba[ext=m4a]/b[height<=%d]/bv*[height<=%d]+ba/b[height<=%d]/b",
        height, height, height, height
    )
    return shellQuote(ytdlp)
        .. " --no-playlist --newline --no-warnings --no-cache-dir"
        .. " --extractor-args " .. shellQuote(YOUTUBE_PLAYER_CLIENT)
        -- YouTube serves the selected stream as DASH fragments. Fetching four of
        -- them at a time is yt-dlp's documented way to use the available
        -- bandwidth and shortens the download noticeably on reader Wi-Fi.
        .. " --concurrent-fragments 4"
        .. " --merge-output-format mp4"
        .. " --ffmpeg-location " .. shellQuote(ffmpeg)
        .. " -f " .. shellQuote(format)
        .. " -o " .. shellQuote(source_file)
        .. " " .. shellQuote(source)
end

-- Keep the visible failure reason short and actionable. The complete yt-dlp
-- diagnostic remains available below it in the job pane.
function YouTube.describeDownloadFailure(log)
    local lower = tostring(log or ""):lower()
    if lower:find("sign in to confirm", 1, true) and lower:find("not a bot", 1, true) then
        return _("YouTube blocked this reader's guest session. Wait and try again; some videos require a signed-in session.")
    end
    if lower:find("http error 403", 1, true) or lower:find("403 forbidden", 1, true) then
        return _("YouTube rejected the video stream (403). Try again later.")
    end
    if lower:find("po token", 1, true) then
        return _("YouTube requested an access token for this video. Try another public video.")
    end
    if lower:find("requested format is not available", 1, true) then
        return _("This video has no compatible stream at the selected source quality.")
    end
    if lower:find("network is unreachable", 1, true) or lower:find("connection", 1, true) then
        return _("The network connection failed while downloading the video.")
    end
    return _("The download failed. See the yt-dlp details below.")
end

-- ffmpeg filter chain that letterboxes the source into the BWR2 frame.
function YouTube.buildFilter(width, height, fps, dithered, color_mode)
    -- The normal monochrome path immediately reduces the scaled image to one
    -- bit, so Lanczos detail is discarded by the next filter while consuming a
    -- large part of the conversion time. Keep Lanczos only for the explicitly
    -- selected Snake-compatible Bayer path; FFmpeg's monow and BRC2 RGB paths
    -- use its much faster scaler without changing their output contracts.
    local scale_flags = (color_mode or dithered) and "fast_bilinear" or "lanczos"
    local chain = string.format(
        "fps=%s,scale=%d:%d:force_original_aspect_ratio=decrease:flags=%s,"
            .. "pad=%d:%d:(ow-iw)/2:(oh-ih)/2:color=white,format=%s",
        tostring(fps), width, height, scale_flags, width, height, color_mode and "rgb24" or "gray"
    )
    if dithered then chain = chain .. ",format=monow" end
    return chain
end

function YouTube.frameSize(percent)
    local width = Screen:getWidth()
    local height = Screen:getHeight()
    local factor = clamp(tonumber(percent) or 100, 25, 100) / 100
    local frame_width = math.floor(width * factor / 8) * 8
    local frame_height = math.floor(height * factor)
    return math.max(8, frame_width), math.max(8, frame_height)
end

local RESOLUTIONS = { 100, 75, 50, 35 }
local FRAME_RATES = { 7.5, 10, 12, 15 }
local DURATIONS = { 60, 180, 600, 0 }

YouTube.RESOLUTIONS = RESOLUTIONS
YouTube.FRAME_RATES = FRAME_RATES
YouTube.DURATIONS = DURATIONS

function YouTube.cycle(list, current)
    for index, value in ipairs(list) do
        if value == current then
            return list[index % #list + 1]
        end
    end
    return list[1]
end

function YouTube.durationLabel(seconds)
    seconds = tonumber(seconds) or 0
    if seconds <= 0 then return _("Full length") end
    if seconds % 60 == 0 and seconds >= 60 then return string.format("%d min", seconds / 60) end
    return formatDuration(seconds)
end

function YouTube.audioVideoDelayLabel(seconds)
    seconds = tonumber(seconds) or 0
    if seconds <= 0 then return _("Immediately") end
    return string.format("%.2g s", seconds)
end

function YouTube.resolutionLabel(percent)
    local width, height = YouTube.frameSize(percent)
    return string.format("%d%% · %dx%d", percent, width, height)
end

----------------------------------------------------------------
-- Tool discovery
----------------------------------------------------------------

local TOOL_FOLDERS = {
    "/mnt/onboard/.adds/appdock/tools",
    "/mnt/onboard/.adds/koreader/tools",
    "/mnt/us/extensions/appdock/tools",
    "/usr/local/bin",
    "/usr/bin",
    "/bin",
    "/opt/bin",
    "/opt/usr/bin",
    "/data/data/com.termux/files/usr/bin",
}

local function isExecutable(path)
    if type(path) ~= "string" or path == "" then return false end
    local handle = io.open(path, "rb")
    if not handle then return false end
    handle:close()
    return true
end

local function whichCommand(name)
    local pipe = io.popen("command -v " .. name .. " 2>/dev/null", "r")
    if not pipe then return nil end
    local path = pipe:read("*l")
    pipe:close()
    if path and path ~= "" then return trim(path) end
    return nil
end

function YouTube.toolFolders()
    local folders = {}
    local ok, data_dir = pcall(function() return DataStorage:getDataDir() end)
    if ok and type(data_dir) == "string" and data_dir ~= "" then
        folders[#folders + 1] = data_dir .. "/appdock/tools"
        folders[#folders + 1] = data_dir .. "/../tools"
    end
    for loop_index, folder in ipairs(TOOL_FOLDERS) do folders[#folders + 1] = folder end
    return folders
end

function YouTube.locateTool(names, explicit)
    if type(explicit) == "string" and explicit ~= "" then
        if isExecutable(explicit) then return explicit end
        return nil, _("The configured path does not exist.")
    end
    for loop_index, name in ipairs(names) do
        local found = whichCommand(name)
        if found and isExecutable(found) then return found end
    end
    for loop_index, folder in ipairs(YouTube.toolFolders()) do
        for loop_index, name in ipairs(names) do
            local candidate = folder .. "/" .. name
            if isExecutable(candidate) then return candidate end
        end
    end
    return nil
end

function YouTube.detectTools(settings)
    settings = settings or {}
    local tools = {}
    tools.ytdlp, tools.ytdlp_error = YouTube.locateTool({ "yt-dlp" }, settings.ytdlp_path)
    tools.ffmpeg, tools.ffmpeg_error = YouTube.locateTool({ "ffmpeg" }, settings.ffmpeg_path)
    if not tools.ytdlp and settings.ytdlp_path and settings.ytdlp_path ~= "" then
        tools.ytdlp = YouTube.locateTool({ "yt-dlp" })
        if tools.ytdlp then tools.ytdlp_error = nil end
    end
    if not tools.ffmpeg and settings.ffmpeg_path and settings.ffmpeg_path ~= "" then
        tools.ffmpeg = YouTube.locateTool({ "ffmpeg" })
        if tools.ffmpeg then tools.ffmpeg_error = nil end
    end
    tools.ready = (tools.ytdlp ~= nil) and (tools.ffmpeg ~= nil)
    return tools
end

-- Download only upstream standalone builds whose OS/architecture is known.
-- Older or unidentified ARMv7 libc versions use yt-dlp's Python zipapp with an
-- isolated Alpine/musl Python runtime. The device's libc is never replaced.
-- Android/Bionic and unknown architectures are not given Linux binaries.
function YouTube.bootstrapPlan(info)
    info = info or {}
    if info.android then return nil, "Android/Bionic is not supported by the automatic Linux tool installer." end
    local arch = info.arch or ""
    local is_armv7 = arch == "armv7l" or arch == "armv7" or arch == "armhf"
    local function olderThan(version, required_major, required_minor)
        if type(version) == "table" then
            return version.major < required_major
                or (version.major == required_major and version.minor < required_minor)
        end
        if type(version) == "number" then return version < required_major * 100 + required_minor end
        return false
    end
    if info.musl and not is_armv7 and olderThan(info.musl_version, 1, 2) then
        return nil, "The official yt-dlp musl build needs musl 1.2 or newer."
    end
    local ytdlp_asset, ffmpeg_arch
    if arch == "x86_64" or arch == "amd64" then
        if not info.musl and olderThan(info.glibc, 2, 17) then
            return nil, "The official yt-dlp Linux build needs glibc 2.17 or newer."
        end
        ytdlp_asset = info.musl and "yt-dlp_musllinux" or "yt-dlp_linux"
        ffmpeg_arch = "amd64"
    elseif arch == "aarch64" or arch == "arm64" then
        if not info.musl and olderThan(info.glibc, 2, 17) then
            return nil, "The official yt-dlp aarch64 build needs glibc 2.17 or newer."
        end
        ytdlp_asset = info.musl and "yt-dlp_musllinux_aarch64" or "yt-dlp_linux_aarch64"
        ffmpeg_arch = "arm64"
    elseif is_armv7 then
        local version = info.glibc
        local version_unknown = type(version) ~= "table" and type(version) ~= "number"
        if info.musl or version_unknown or olderThan(version, 2, 17) then
            local python_asset = "appdock-youtube-armhf-musl-python-3.12.15.tar.gz"
            return {
                ytdlp_asset = "yt-dlp",
                ytdlp_zip = false,
                ytdlp_python = true,
                python_musl = true,
                python_asset = python_asset,
                python_root = "python-runtime",
                python_url = "https://github.com/arduinodude456/appdock.koplugin/releases/download/v7.8.22/" .. python_asset,
                python_sha256 = "5348e11472e5ca6c07d7b0ec75a2f1df1d181be7eb52d9e3cafb43267b1f916c",
                ffmpeg_arch = "armhf",
                ytdlp_base = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/",
                ffmpeg_url = "https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-armhf-static.tar.xz",
            }
        end
        local too_old = type(version) == "table" and (version.major < 2 or (version.major == 2 and version.minor < 31))
            or type(version) == "number" and version < 231
        if too_old then
            local ytdlp_asset = "yt-dlp"
            local python_asset = "python-headless-3.13.9-linux-arm.zip"
            return {
                ytdlp_asset = ytdlp_asset,
                ytdlp_zip = false,
                ytdlp_python = true,
                python_asset = python_asset,
                python_root = "python-headless-3.13.9-linux-arm",
                python_url = "https://github.com/bjia56/portable-python/releases/download/cpython-v3.13.9-build.0/" .. python_asset,
                python_sha256 = "a29499df42ae58d47e9080cae5500ba6aa5f1d7ec93407831ea565e40b117175",
                ffmpeg_arch = "armhf",
                ytdlp_base = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/",
                ffmpeg_url = "https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-armhf-static.tar.xz",
            }
        end
        ytdlp_asset = "yt-dlp_linux_armv7l.zip"
        ffmpeg_arch = "armhf"
    elseif arch == "armv6l" or arch == "armel" then
        return nil, "The official yt-dlp standalone release does not provide a compatible ARMv6 build."
    else
        return nil, "Automatic tool installation is not available for this Linux architecture: " .. tostring(arch)
    end
    return {
        ytdlp_asset = ytdlp_asset,
        ytdlp_zip = ytdlp_asset:match("%.zip$") ~= nil,
        ffmpeg_arch = ffmpeg_arch,
        ytdlp_base = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/",
        ffmpeg_url = "https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-" .. ffmpeg_arch .. "-static.tar.xz",
    }
end

function YouTube.parseGlibcVersion(getconf_output, ldd_output)
    local major, minor = tostring(getconf_output or ""):match("(%d+)%.(%d+)")
    local ldd = tostring(ldd_output or "")
    local lower = ldd:lower()
    if not major and not lower:find("musl", 1, true)
        and (lower:find("glibc", 1, true) or lower:find("gnu libc", 1, true)
            or lower:find("gnu c library", 1, true)) then
        major, minor = ldd:match("(%d+)%.(%d+)")
    end
    if not major or not minor then return nil end
    return { major = tonumber(major), minor = tonumber(minor) }
end

local function detectBootstrapPlatform()
    local function commandOutput(command, include_stderr)
        local pipe = io.popen(command .. (include_stderr and " 2>&1" or " 2>/dev/null"), "r")
        if not pipe then return "" end
        local value = pipe:read("*a") or ""
        pipe:close()
        return trim(value)
    end
    local arch = commandOutput("uname -m")
    local ldd = commandOutput("ldd --version", true)
    local libc = commandOutput("getconf GNU_LIBC_VERSION")
    local glibc = YouTube.parseGlibcVersion(libc, ldd)
    if not glibc then
        glibc = YouTube.parseGlibcVersion("", commandOutput("/lib/libc.so.6", true))
    end
    local musl_major, musl_minor = ldd:lower():match("musl.-(%d+)%.(%d+)")
    local musl_version = musl_major and musl_minor and {
        major = tonumber(musl_major), minor = tonumber(musl_minor),
    } or nil
    return {
        arch = arch,
        musl = ldd:lower():find("musl", 1, true) ~= nil,
        musl_version = musl_version,
        glibc = glibc,
        android = type(Device.isAndroid) == "function" and Device:isAndroid() or false,
    }
end

YouTube.detectBootstrapPlatform = detectBootstrapPlatform

----------------------------------------------------------------
-- Small widgets
----------------------------------------------------------------

local Pill = InputContainer:extend{
    text = nil,
    callback = nil,
    hold_callback = nil,
    width = nil,
    height = nil,
    background = nil,
    foreground = nil,
    font_size = nil,
    bold = nil,
    align = "center",
    dimen = nil,
}

function Pill:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self.text_widget = TextWidget:new{
        text = fitText(self.text or "", math.max(1, self.width - scale(12)), self.font_size or 11),
        face = Font:getFace("smallinfofont", scale(self.font_size or 11)),
        bold = self.bold ~= false,
        fgcolor = self.foreground or Blitbuffer.COLOR_BLACK,
        max_width = math.max(1, self.width - scale(12)),
    }
    self[1] = FrameContainer:new{
        width = self.width,
        height = self.height,
        padding = 0,
        bordersize = 0,
        radius = math.max(2, math.floor(self.height / 2)),
        background = self.background or Blitbuffer.COLOR_LIGHT_GRAY,
        self.text_widget,
    }
    local events = { TapPill = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    if self.hold_callback then
        events.HoldPill = { GestureRange:new{ ges = "hold", range = self.dimen } }
    end
    self.ges_events = events
end

function Pill:getSize()
    return self.dimen
end

function Pill:setText(text)
    self.text = text
    if self.text_widget then
        self.text_widget:setText(fitText(text or "", math.max(1, self.width - scale(12)), self.font_size or 11))
    end
end

function Pill:paintTo(bb, x, y)
    local range = self.ges_events.TapPill[1].range
    range.x, range.y, range.w, range.h = x, y, self.width, self.height
    if self.ges_events.HoldPill then
        local hold = self.ges_events.HoldPill[1].range
        hold.x, hold.y, hold.w, hold.h = x, y, self.width, self.height
    end
    return InputContainer.paintTo(self, bb, x, y)
end

function Pill:onTapPill()
    if self.callback then self.callback() end
    return true
end

function Pill:onHoldPill()
    if self.hold_callback then self.hold_callback() end
    return true
end

local ProgressBar = InputContainer:extend{
    ratio = 0,
    indeterminate = false,
    position = 0,
    segment_ratio = 0.2,
    background_color = nil,
    foreground_color = nil,
    border_color = nil,
    width = nil,
    height = nil,
    dimen = nil,
}

function ProgressBar:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
end

function ProgressBar:getSize()
    return self.dimen
end

function ProgressBar:paintTo(bb, x, y)
    local border = math.max(1, scale(1))
    local background = self.background_color or Blitbuffer.COLOR_WHITE
    local foreground = self.foreground_color or Blitbuffer.COLOR_BLACK
    local outline = self.border_color or Blitbuffer.COLOR_BLACK
    bb:paintRect(x, y, self.width, self.height, background)
    bb:paintRect(x, y, self.width, border, outline)
    bb:paintRect(x, y + self.height - border, self.width, border, outline)
    bb:paintRect(x, y, border, self.height, outline)
    bb:paintRect(x + self.width - border, y, border, self.height, outline)
    local inner_w = math.max(0, self.width - 2 * border)
    if self.indeterminate then
        local filled = math.max(1, math.floor(inner_w * clamp(self.segment_ratio or 0.2, 0.05, 1) + 0.5))
        local travel = math.max(0, inner_w - filled)
        local offset = math.floor(travel * clamp(self.position or 0, 0, 1) + 0.5)
        bb:paintRect(x + border + offset, y + border, filled, self.height - 2 * border, foreground)
    else
        local filled = math.floor(inner_w * clamp(self.ratio or 0, 0, 1) + 0.5)
        if filled > 0 then
            bb:paintRect(x + border, y + border, filled, self.height - 2 * border, foreground)
        end
    end
end

local function setProgressBarPercent(widget, percent)
    if not widget then return false end
    widget.ratio = clamp((tonumber(percent) or 0) / 100, 0, 1)
    return true
end

local function progressBarPulsePosition(phase)
    phase = math.floor(tonumber(phase) or 0) % 8
    return phase <= 4 and phase / 4 or (8 - phase) / 4
end

local function setProgressBarPulse(widget, phase)
    if not widget then return false end
    widget.position = progressBarPulsePosition(phase)
    return true
end

YouTube.Pill = Pill
YouTube.ProgressBar = ProgressBar

----------------------------------------------------------------
-- Instance state
----------------------------------------------------------------

local DEFAULT_SETTINGS = {
    ytdlp_path = "",
    ffmpeg_path = "",
    output_dir = "",
    music_dir = "",
    resolution_percent = 100,
    fps = 12,
    max_duration = 180,
    max_height = 480,
    dither = "ffmpeg",
    color_mode = false,
    color_dither = true,
    audio_video_delay = 0,
}

local AUDIO_VIDEO_DELAYS = { 0, 0.1, 0.25, 0.5, 1, 2 }

function YouTube:new(appdock)
    return setmetatable({ appdock = appdock, player = Player:new(appdock) }, YouTube)
end

local function normalizeSettings(values)
    local allowed_resolutions = { [100] = true, [75] = true, [50] = true, [35] = true }
    local allowed_fps = { [7.5] = true, [10] = true, [12] = true, [15] = true }
    local allowed_heights = { [360] = true, [480] = true, [720] = true }
    values.output_dir = type(values.output_dir) == "string" and trim(values.output_dir):sub(1, 360) or ""
    values.music_dir = type(values.music_dir) == "string" and trim(values.music_dir):sub(1, 360) or ""
    values.ytdlp_path = type(values.ytdlp_path) == "string" and trim(values.ytdlp_path):sub(1, 360) or ""
    values.ffmpeg_path = type(values.ffmpeg_path) == "string" and trim(values.ffmpeg_path):sub(1, 360) or ""
    local resolution, fps = tonumber(values.resolution_percent), tonumber(values.fps)
    local duration, height, delay = tonumber(values.max_duration), tonumber(values.max_height), tonumber(values.audio_video_delay)
    values.resolution_percent = allowed_resolutions[resolution] and resolution or DEFAULT_SETTINGS.resolution_percent
    values.fps = allowed_fps[fps] and fps or DEFAULT_SETTINGS.fps
    values.max_duration = duration and duration >= 0 and duration <= 3600 and math.floor(duration) or DEFAULT_SETTINGS.max_duration
    values.max_height = allowed_heights[height] and height or DEFAULT_SETTINGS.max_height
    values.audio_video_delay = delay and delay >= 0 and delay <= 60 and delay or DEFAULT_SETTINGS.audio_video_delay
    values.dither = values.dither == "bayer" and "bayer" or "ffmpeg"
    values.color_mode = values.color_mode == true
    values.color_dither = values.color_dither ~= false
    return values
end

function YouTube:_settings()
    local values = {}
    for key, value in pairs(DEFAULT_SETTINGS) do values[key] = value end
    local appdock = self.appdock
    if appdock and type(appdock.getYouTubeSettings) == "function" then
        local stored = appdock:getYouTubeSettings()
        for key, value in pairs(type(stored) == "table" and stored or {}) do values[key] = value end
    end
    return normalizeSettings(values)
end

function YouTube:_patchSettings(patch)
    local appdock = self.appdock
    if appdock and type(appdock.setYouTubeSettings) == "function" then
        return appdock:setYouTubeSettings(patch)
    end
    return false
end

function YouTube:_outputDirectory()
    local settings = self:_settings()
    local path = trim(settings.output_dir)
    if path == "" then
        local ok, data_dir = pcall(function() return DataStorage:getDataDir() end)
        local base = ok and data_dir or "/tmp"
        path = base .. "/appdock/videos"
    end
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok then ok, lfs = pcall(require, "lfs") end
    if ok and lfs then
        local parent = path:match("^(.*)/[^/]+$")
        if parent then
            local function ensure(folder)
                if folder == "" or folder == "/" then return true end
                if lfs.attributes(folder, "mode") ~= "directory" then
                    ensure(folder:match("^(.*)/[^/]+$") or "")
                    pcall(lfs.mkdir, folder)
                end
                return lfs.attributes(folder, "mode") == "directory"
            end
            ensure(parent)
        end
        if lfs.attributes(path, "mode") ~= "directory" then pcall(lfs.mkdir, path) end
    end
    return path
end

function YouTube:_state(instance)
    instance.youtube = instance.youtube or {
        view = "home",
        query = "",
        url = "",
        results = nil,
        results_query = "",
        result_page = 1,
        library = nil,
        library_page = 1,
        library_scanned = 0,
        job = nil,
        note = "",
        tools = nil,
        playing = nil,
    }
    local state = instance.youtube
    if not state.tools then state.tools = YouTube.detectTools(self:_settings()) end
    return state
end

function YouTube:_notify(instance, context, text)
    local state = self:_state(instance)
    state.note = text
    if context and context.requestRefresh then context.requestRefresh("ui") end
end

function YouTube:redetect(instance, context)
    local state = self:_state(instance)
    state.tools = YouTube.detectTools(self:_settings())
    if state.tools.ready then
        state.bootstrap = nil
        state.bootstrap_attempted = true
        state.view = "home"
    end
    self:_notify(instance, context, state.tools.ready
        and _("yt-dlp and ffmpeg are ready.")
        or _("yt-dlp or ffmpeg is still missing."))
    if context and context.requestRebuild then context.requestRebuild("ui") end
end

----------------------------------------------------------------
-- Library
----------------------------------------------------------------

function YouTube:scanLibrary(instance, context)
    local state = self:_state(instance)
    local directory = self:_outputDirectory()
    local entries = {}
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok then ok, lfs = pcall(require, "lfs") end
    if not ok or not lfs then
        state.library = {}
        return state.library
    end
    local names = {}
    local listed = pcall(function()
        for name in lfs.dir(directory) do
            if type(name) == "string" and name:lower():match("%.bwr$") then names[#names + 1] = name end
        end
    end)
    if not listed then
        state.library = {}
        state.note = _("The video folder cannot be read.")
        return state.library
    end
    table.sort(names)
    for loop_index, name in ipairs(names) do
        local path = directory .. "/" .. name
        local opened, handle = pcall(io.open, path, "rb")
        if opened and handle then
            local header_ok, header = pcall(BWR.readHeader, handle)
            pcall(function() handle:close() end)
            if header_ok and header then
                local attributes_ok, attributes = pcall(lfs.attributes, path)
                attributes = attributes_ok and attributes or {}
                local wav = path:gsub("%.bwr$", ".wav")
                local wav_handle = io.open(wav, "rb")
                if wav_handle then wav_handle:close() else wav = nil end
                entries[#entries + 1] = {
                    path = path,
                    name = name,
                    title = name:gsub("%.bwr$", ""):gsub("_", " "),
                    subtitle = string.format("YouTube · %s", formatDuration(BWR.durationSeconds(header))),
                    duration = BWR.durationSeconds(header),
                    value = formatDuration(BWR.durationSeconds(header)),
                    size = attributes.size or 0,
                    modified = attributes.modification or 0,
                    has_audio = wav ~= nil,
                    thumbnail_path = path:gsub("%.bwr$", ".jpg"),
                    video_card = true,
                }
            end
        end
    end
    table.sort(entries, function(left, right) return (left.modified or 0) > (right.modified or 0) end)
    state.library = entries
    state.library_scanned = os.time()
    state.library_page = clamp(state.library_page or 1, 1, math.max(1, math.ceil(#entries / 6)))
    return entries
end

----------------------------------------------------------------
-- Detached command helpers
----------------------------------------------------------------

local function readFile(path)
    local handle = io.open(path, "rb")
    if not handle then return nil end
    local content = handle:read("*a")
    handle:close()
    return content
end

local function writeFile(path, content)
    local handle = io.open(path, "wb")
    if not handle then return false end
    handle:write(content)
    handle:close()
    return true
end

local function removeFile(path)
    if path then os.remove(path) end
end

-- Starts a command detached and reports completion through an exit marker file,
-- so the UI thread never waits for a slow download or merge step.
function YouTube:_startDetached(command, work_dir, tag)
    local log_path = work_dir .. "/" .. tag .. ".log"
    local exit_path = work_dir .. "/" .. tag .. ".exit"
    removeFile(exit_path)
    removeFile(log_path)
    -- Run the command in its own subshell: its `set -e` must not bypass the
    -- outer shell's exit-marker write on failure. Redirect the whole command
    -- group so diagnostics are available when the UI receives that marker.
    local runner = "(\n" .. command .. "\n) >" .. shellQuote(log_path)
        .. " 2>&1; code=$?; echo $code >" .. shellQuote(exit_path)
    local quoted_runner = shellQuote(runner)
    local launch = "if command -v setsid >/dev/null 2>&1; then setsid sh -c " .. quoted_runner
        .. " </dev/null >/dev/null 2>&1 & else sh -c " .. quoted_runner
        .. " </dev/null >/dev/null 2>&1 & fi; echo $!"
    local pipe = io.popen(launch, "r")
    if not pipe then return nil, _("The command could not be started.") end
    local read_ok, line = pcall(function() return pipe:read("*l") end)
    pcall(function() pipe:close() end)
    local pid = read_ok and tonumber(line) or nil
    if not pid or pid <= 0 then return nil, _("The command could not be started.") end
    return { pid = pid, log = log_path, exit = exit_path }
end

function YouTube.liveLogPreview(text)
    text = tostring(text or "")
        :gsub("\27%[[%d;?]*[%a]", "")
        :gsub("\r\n", "\n")
        :gsub("\r", "\n")
        :gsub("[%z\1-\9\11\12\14-\31\127]", " ")
    local lines = {}
    for line in text:gmatch("[^\n]+") do
        line = trim(line):gsub("%s+", " ")
        if line ~= "" then
            lines[#lines + 1] = line
        end
    end
    local preview = {}
    for index = math.max(1, #lines - 4), #lines do
        preview[#preview + 1] = lines[index]
    end
    return #preview > 0 and table.concat(preview, "\n") or _("Waiting for shell output…")
end

function YouTube:_pollDetached(handle)
    if not handle then return nil end
    local marker = readFile(handle.exit)
    if marker == nil then return nil end
    -- The marker is written by a background process. Ignore a partially written
    -- file instead of turning it into a false failure while it is still open.
    local code_text = marker:match("^%s*([%-]?%d+)%s*\n$")
    local code = code_text and tonumber(code_text) or nil
    if code == nil then return nil end
    return code, readFile(handle.log) or ""
end

function YouTube:_killDetached(handle)
    if handle and handle.pid then
        os.execute("kill -TERM -" .. tostring(handle.pid) .. " 2>/dev/null")
        os.execute("kill -TERM " .. tostring(handle.pid) .. " 2>/dev/null")
        os.execute("kill -KILL -" .. tostring(handle.pid) .. " 2>/dev/null")
        os.execute("kill -KILL " .. tostring(handle.pid) .. " 2>/dev/null")
    end
end

YouTube._readFile = readFile
YouTube._writeFile = writeFile

----------------------------------------------------------------
-- Job pipeline
----------------------------------------------------------------

-- The old UI loop read only two frames before sleeping for one full second,
-- limiting conversion to 2 fps regardless of encoder speed. Use bounded batches
-- and short video ticks while keeping each UI-thread turn time-limited.
local VIDEO_TICK_INTERVAL = 0.01
-- Conversion runs between E-Ink UI turns. Allow a larger but still bounded turn
-- so fast FFmpeg/FFI paths spend less time returning through the scheduler.
-- The hard CPU budget still returns control frequently on slower Kobo CPUs.
local VIDEO_TICK_CPU_BUDGET = 0.30
-- Real footage remains limited by the CPU budget below; this higher ceiling is
-- mainly useful for cheap/repeated frames and avoids scheduler overhead.
local VIDEO_MAX_FRAMES_PER_TICK = 128
-- Keep a small bounded pipe read: it removes most Lua/FFI round trips while
-- remaining far below the memory peak that the old parallel FFmpeg passes used.
-- The device-wide conversion lock still prevents two decoders competing for RAM.
local VIDEO_READ_BATCH_FRAMES = 4
-- Two decode threads materially improve ARM reader throughput. Filter work stays
-- single-threaded because the raw-frame pipe and Lua encoder are the memory
-- sensitive part of this pipeline.
local FFMPEG_DECODE_THREADS = 2
local PROGRESS_REFRESH_INTERVAL = 0.75
-- Rebuilding the job pane is the most expensive part of a conversion tick. A
-- long video does not need a 1.3 Hz progress repaint, so the video stage updates
-- the bar less often than the download stage, which only parses text.
local VIDEO_PROGRESS_REFRESH_INTERVAL = 1.5

local function monotonicNow()
    if Player and type(Player.now) == "function" then
        local ok, value = pcall(Player.now)
        if ok and type(value) == "number" then return value end
    end
    return os.time()
end

local job_sequence = 0
-- Converting is intentionally device-wide, not only per DApp instance. Window
-- mode and restored workspaces can otherwise launch two FFmpeg pipelines and
-- make the reader kill KOReader under memory pressure.
local ACTIVE_CONVERSION

local function claimConversion(job)
    if ACTIVE_CONVERSION then return false end
    ACTIVE_CONVERSION = job
    return true
end

local function releaseConversion(job)
    if ACTIVE_CONVERSION == job then ACTIVE_CONVERSION = nil end
end
local function jobDirectory()
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok then ok, lfs = pcall(require, "lfs") end
    local base = os.getenv("TMPDIR") or "/tmp"
    for attempt = 1, 8 do
        job_sequence = job_sequence + 1
        local name = string.format("appdock-yt-%d-%d-%d", os.time(), job_sequence, math.random(1000, 9999))
        local path = base .. "/" .. name
        if ok and lfs then
            pcall(lfs.mkdir, path)
            if lfs.attributes(path, "mode") == "directory" then return path end
        else
            local created = os.execute("mkdir " .. shellQuote(path) .. " >/dev/null 2>&1")
            if created == true or created == 0 then return path end
        end
    end
    return nil, _("A temporary video folder could not be created.")
end

local function cleanupDirectory(path)
    if not path then return end
    os.execute("rm -rf " .. shellQuote(path))
end

function YouTube.managedToolDirectory()
    local ok, data_dir = pcall(function() return DataStorage:getDataDir() end)
    if not ok or type(data_dir) ~= "string" or data_dir == "" then return nil end
    return data_dir .. "/appdock/tools"
end

function YouTube.buildBootstrapCommand(tool_dir, work_dir, plan, need_ytdlp, need_ffmpeg)
    if type(tool_dir) ~= "string" or type(work_dir) ~= "string" or type(plan) ~= "table" then
        return nil, "Invalid automatic tool-install configuration."
    end
    local q = shellQuote
    local lines = {
        "set -eu",
        "tools=" .. q(tool_dir),
        "work=" .. q(work_dir),
        "status=" .. q(work_dir .. "/bootstrap.status"),
        "mkdir -p \"$tools\" \"$work\"",
        "tmp=\"$tools/.appdock-setup-$$\"",
        "mkdir -p \"$tmp\"",
        "cleanup() { rm -rf \"$tmp\"; }",
        "trap cleanup EXIT",
        "trap 'exit 1' HUP INT TERM",
        "set_status() { printf '%s\\n' \"$1\" > \"$status\"; printf '[setup] %s\\n' \"$1\"; }",
        "download() { url=\"$1\"; dest=\"$2\"; name=${dest##*/}; printf '[download] %s\\n' \"$name\"; if command -v curl >/dev/null 2>&1; then curl -fL --retry 2 --connect-timeout 25 --max-time 1200 -# -o \"$dest\" \"$url\"; elif command -v wget >/dev/null 2>&1; then wget -T 25 -t 3 -O \"$dest\" \"$url\"; else echo 'Neither curl nor wget is installed.' >&2; return 127; fi; }",
    }
    if need_ytdlp then
        local asset = plan.ytdlp_asset
        local url = plan.ytdlp_base .. asset
        lines[#lines + 1] = "set_status 'Downloading yt-dlp from the official GitHub release…'"
        lines[#lines + 1] = "download " .. q(url) .. " \"$tmp/yt-dlp.pkg\""
        lines[#lines + 1] = "set_status 'Downloading the yt-dlp SHA-256 manifest…'"
        lines[#lines + 1] = "download " .. q(plan.ytdlp_base .. "SHA2-256SUMS") .. " \"$tmp/SHA2-256SUMS\""
        lines[#lines + 1] = "set_status 'Calculating yt-dlp SHA-256 (large files may take a while on eReaders)…'"
        lines[#lines + 1] = "expected=$(awk -v name=" .. q(asset) .. " '$2 == name || $2 == \"*\" name { print $1; exit }' \"$tmp/SHA2-256SUMS\")"
        lines[#lines + 1] = "actual=$(sha256sum \"$tmp/yt-dlp.pkg\" | awk '{print $1}')"
        lines[#lines + 1] = "test -n \"$expected\" && test \"$expected\" = \"$actual\" || { echo 'yt-dlp SHA-256 verification failed.' >&2; exit 1; }"
        lines[#lines + 1] = "set_status 'yt-dlp checksum verified; preparing executable…'"
        if plan.ytdlp_python then
            if plan.python_musl then
                lines[#lines + 1] = "set_status 'Downloading the bundled ARMHF musl Python runtime…'"
                lines[#lines + 1] = "download " .. q(plan.python_url) .. " \"$tmp/python-runtime.pkg\""
                lines[#lines + 1] = "set_status 'Verifying bundled musl Python SHA-256…'"
                lines[#lines + 1] = "expected=" .. q(plan.python_sha256)
                lines[#lines + 1] = "actual=$(sha256sum \"$tmp/python-runtime.pkg\" | awk '{print $1}')"
                lines[#lines + 1] = "test \"$expected\" = \"$actual\" || { echo 'Bundled musl Python SHA-256 verification failed.' >&2; exit 1; }"
                lines[#lines + 1] = "set_status 'Extracting the ARMHF musl Python runtime…'"
                lines[#lines + 1] = "mkdir -p \"$tmp/python-extract\""
                lines[#lines + 1] = "tar -xzf \"$tmp/python-runtime.pkg\" -C \"$tmp/python-extract\" || { echo 'Could not unpack the ARMHF musl Python runtime; tar/gzip may be missing.' >&2; exit 1; }"
                lines[#lines + 1] = "test -x \"$tmp/python-extract/" .. plan.python_root .. "/lib/ld-musl-armhf.so.1\" && test -x \"$tmp/python-extract/" .. plan.python_root .. "/usr/bin/python3.12\" && test -s \"$tmp/python-extract/" .. plan.python_root .. "/etc/ssl/cert.pem\" || { echo 'The ARMHF musl Python runtime is incomplete.' >&2; exit 1; }"
                lines[#lines + 1] = "mv \"$tmp/python-extract/" .. plan.python_root .. "\" \"$tmp/python-runtime\""
                lines[#lines + 1] = "cp \"$tmp/yt-dlp.pkg\" \"$tmp/yt-dlp.pyz\""
                lines[#lines + 1] = "printf '%s\\n' '#!/bin/sh' 'case \"$0\" in */*) d=${0%/*} ;; *) d=. ;; esac' 'r=\"$d/python-runtime\"' 'export PYTHONHOME=\"$r/usr\"' 'export PYTHONNOUSERSITE=1' 'export SSL_CERT_FILE=\"$r/etc/ssl/cert.pem\"' 'export SSL_CERT_DIR=\"$r/etc/ssl/certs\"' 'export LD_LIBRARY_PATH=\"$r/lib:$r/usr/lib:$r/usr/lib/python3.12/lib-dynload\"' 'exec \"$r/lib/ld-musl-armhf.so.1\" \"$r/usr/bin/python3.12\" \"$d/yt-dlp.pyz\" \"$@\"' > \"$tmp/yt-dlp.new\""
            else
                lines[#lines + 1] = "set_status 'Downloading the portable ARM Python runtime…'"
                lines[#lines + 1] = "download " .. q(plan.python_url) .. " \"$tmp/python-runtime.pkg\""
                lines[#lines + 1] = "set_status 'Verifying portable Python SHA-256…'"
                lines[#lines + 1] = "expected=" .. q(plan.python_sha256)
                lines[#lines + 1] = "actual=$(sha256sum \"$tmp/python-runtime.pkg\" | awk '{print $1}')"
                lines[#lines + 1] = "test \"$expected\" = \"$actual\" || { echo 'Portable Python SHA-256 verification failed.' >&2; exit 1; }"
                lines[#lines + 1] = "set_status 'Extracting the portable ARM Python runtime…'"
                lines[#lines + 1] = "mkdir -p \"$tmp/python-extract\""
                lines[#lines + 1] = "if command -v unzip >/dev/null 2>&1; then unzip -q \"$tmp/python-runtime.pkg\" -d \"$tmp/python-extract\"; elif command -v busybox >/dev/null 2>&1; then busybox unzip -q \"$tmp/python-runtime.pkg\" -d \"$tmp/python-extract\"; else echo 'unzip (or BusyBox with unzip) is required for the portable ARM Python runtime.' >&2; exit 1; fi"
                lines[#lines + 1] = "test -f \"$tmp/python-extract/" .. plan.python_root .. "/bin/python3.13\" || { echo 'The portable ARM Python archive is incomplete.' >&2; exit 1; }"
                lines[#lines + 1] = "chmod 755 \"$tmp/python-extract/" .. plan.python_root .. "/bin/python3.13\""
                lines[#lines + 1] = "mv \"$tmp/python-extract/" .. plan.python_root .. "\" \"$tmp/python-runtime\""
                lines[#lines + 1] = "cp \"$tmp/yt-dlp.pkg\" \"$tmp/yt-dlp.pyz\""
                lines[#lines + 1] = "printf '%s\\n' '#!/bin/sh' 'case \"$0\" in */*) d=${0%/*} ;; *) d=. ;; esac' 'exec \"$d/python-runtime/bin/python3.13\" \"$d/yt-dlp.pyz\" \"$@\"' > \"$tmp/yt-dlp.new\""
            end
        elseif plan.ytdlp_zip then
            lines[#lines + 1] = "set_status 'Extracting the ARMv7 yt-dlp runtime…'"
            lines[#lines + 1] = "mkdir -p \"$tmp/yt-dlp-runtime\""
            lines[#lines + 1] = "if command -v unzip >/dev/null 2>&1; then unzip -q \"$tmp/yt-dlp.pkg\" -d \"$tmp/yt-dlp-runtime\"; elif command -v busybox >/dev/null 2>&1; then busybox unzip -q \"$tmp/yt-dlp.pkg\" -d \"$tmp/yt-dlp-runtime\"; else echo 'unzip (or BusyBox with unzip) is required for the ARMv7 yt-dlp build.' >&2; exit 1; fi"
            lines[#lines + 1] = "test -f \"$tmp/yt-dlp-runtime/yt-dlp_linux_armv7l\" || { echo 'The ARMv7 yt-dlp archive is missing its executable.' >&2; exit 1; }"
            lines[#lines + 1] = "chmod 755 \"$tmp/yt-dlp-runtime/yt-dlp_linux_armv7l\""
            lines[#lines + 1] = "printf '%s\\n' '#!/bin/sh' 'case \"$0\" in */*) d=${0%/*} ;; *) d=. ;; esac' 'exec \"$d/yt-dlp-runtime/yt-dlp_linux_armv7l\" \"$@\"' > \"$tmp/yt-dlp.new\""
        else
            lines[#lines + 1] = "cp \"$tmp/yt-dlp.pkg\" \"$tmp/yt-dlp.new\""
        end
        lines[#lines + 1] = "chmod 755 \"$tmp/yt-dlp.new\""
        lines[#lines + 1] = "set_status 'Starting yt-dlp compatibility check (up to 2 minutes)…'"
        lines[#lines + 1] = "check_ytdlp_version() { \"$1\" --version & check_pid=$!; printf '[check] yt-dlp --version started (pid %s)\\n' \"$check_pid\"; elapsed=0; while kill -0 \"$check_pid\" 2>/dev/null; do if [ \"$elapsed\" -ge 120 ]; then kill -TERM \"$check_pid\" 2>/dev/null || true; sleep 2; kill -KILL \"$check_pid\" 2>/dev/null || true; wait \"$check_pid\" 2>/dev/null || true; return 124; fi; if [ $((elapsed % 10)) -eq 0 ]; then printf '[check] still running (%ss of 120s)\\n' \"$elapsed\"; fi; sleep 1; elapsed=$((elapsed + 1)); done; wait \"$check_pid\"; }"
        lines[#lines + 1] = "if check_ytdlp_version \"$tmp/yt-dlp.new\"; then set_status 'yt-dlp compatibility check passed.'; else check_rc=$?; if [ \"$check_rc\" -eq 124 ]; then echo 'yt-dlp compatibility check timed out after 120 seconds.' >&2; else echo 'Downloaded yt-dlp cannot run on this device.' >&2; fi; exit 1; fi"
    end
    if need_ffmpeg then
        local url = plan.ffmpeg_url
        lines[#lines + 1] = "set_status 'Downloading FFmpeg static build…'"
        lines[#lines + 1] = "download " .. q(url) .. " \"$tmp/ffmpeg.tar.xz\""
        lines[#lines + 1] = "set_status 'Verifying FFmpeg archive…'"
        lines[#lines + 1] = "download " .. q(url .. ".md5") .. " \"$tmp/ffmpeg.md5\""
        lines[#lines + 1] = "expected=$(awk 'NR == 1 { print $1 }' \"$tmp/ffmpeg.md5\")"
        lines[#lines + 1] = "actual=$(md5sum \"$tmp/ffmpeg.tar.xz\" | awk '{print $1}')"
        lines[#lines + 1] = "test -n \"$expected\" && test \"$expected\" = \"$actual\" || { echo 'FFmpeg archive checksum verification failed.' >&2; exit 1; }"
        lines[#lines + 1] = "mkdir -p \"$tmp/extracted\""
        lines[#lines + 1] = "tar -xJf \"$tmp/ffmpeg.tar.xz\" -C \"$tmp/extracted\" || { echo 'Could not unpack the FFmpeg archive (tar/xz may be missing). ' >&2; exit 1; }"
        lines[#lines + 1] = "ffmpeg_source=$(find \"$tmp/extracted\" -type f -name ffmpeg -print | head -n 1)"
        lines[#lines + 1] = "test -n \"$ffmpeg_source\" || { echo 'The FFmpeg archive did not contain an executable.' >&2; exit 1; }"
        lines[#lines + 1] = "cp \"$ffmpeg_source\" \"$tmp/ffmpeg.new\" && chmod 755 \"$tmp/ffmpeg.new\""
        lines[#lines + 1] = "if \"$tmp/ffmpeg.new\" -version > \"$tmp/ffmpeg-version.log\" 2>&1; then head -n 2 \"$tmp/ffmpeg-version.log\"; else cat \"$tmp/ffmpeg-version.log\" >&2; echo 'Downloaded FFmpeg cannot run on this device.' >&2; exit 1; fi"
        lines[#lines + 1] = "license=$(find \"$tmp/extracted\" -type f -iname GPLv3.txt -print | head -n 1)"
        lines[#lines + 1] = "if [ -n \"$license\" ]; then cp \"$license\" \"$tools/ffmpeg-GPLv3.txt\"; fi"
    end
    if need_ytdlp then
        lines[#lines + 1] = "test ! -e \"$tools/yt-dlp\" || { echo 'An AppDock yt-dlp file appeared during setup; refusing to replace it.' >&2; exit 1; }"
        if plan.ytdlp_python then
            lines[#lines + 1] = "test ! -e \"$tools/python-runtime\" && test ! -e \"$tools/yt-dlp.pyz\" || { echo 'An AppDock Python runtime or yt-dlp zipapp appeared during setup; refusing to replace it.' >&2; exit 1; }"
            lines[#lines + 1] = "mv \"$tmp/python-runtime\" \"$tools/python-runtime\""
            lines[#lines + 1] = "if ! mv \"$tmp/yt-dlp.pkg\" \"$tools/yt-dlp.pyz\"; then rm -rf \"$tools/python-runtime\"; exit 1; fi"
            lines[#lines + 1] = "if ! mv \"$tmp/yt-dlp.new\" \"$tools/yt-dlp\"; then rm -rf \"$tools/python-runtime\"; rm -f \"$tools/yt-dlp.pyz\"; exit 1; fi"
        elseif plan.ytdlp_zip then
            lines[#lines + 1] = "test ! -e \"$tools/yt-dlp-runtime\" || { echo 'An AppDock yt-dlp runtime appeared during setup; refusing to replace it.' >&2; exit 1; }"
            lines[#lines + 1] = "mv \"$tmp/yt-dlp-runtime\" \"$tools/yt-dlp-runtime\""
            lines[#lines + 1] = "if ! mv \"$tmp/yt-dlp.new\" \"$tools/yt-dlp\"; then rm -rf \"$tools/yt-dlp-runtime\"; exit 1; fi"
        else
            lines[#lines + 1] = "mv \"$tmp/yt-dlp.new\" \"$tools/yt-dlp\""
        end
    end
    if need_ffmpeg then
        lines[#lines + 1] = "test ! -e \"$tools/ffmpeg\" || { echo 'An AppDock ffmpeg file appeared during setup; refusing to replace it.' >&2; exit 1; }"
        lines[#lines + 1] = "mv \"$tmp/ffmpeg.new\" \"$tools/ffmpeg\""
    end
    lines[#lines + 1] = "set_status 'Installation complete.'"
    return table.concat(lines, "\n")
end

-- Declare this before the asynchronous bootstrap closures below. Defining it
-- later would make those closures resolve `hostIsActive` as a nil global.
local function hostIsActive(context)
    if not context then return false end
    local manager = context.manager
    if not manager or not context.host then return true end
    return manager.active_host == context.host
end

function YouTube:_startToolBootstrap(instance, context, defer_rebuild)
    local state = self:_state(instance)
    if state.bootstrap and state.bootstrap.handle then return true end
    state.tools = YouTube.detectTools(self:_settings())
    if state.tools.ready then
        state.view = "home"
        state.bootstrap_attempted = true
        if not defer_rebuild and context and context.requestRebuild then context.requestRebuild("ui") end
        return true
    end
    local info = detectBootstrapPlatform()
    local plan, plan_error = YouTube.bootstrapPlan(info)
    if not plan then
        state.bootstrap_attempted = true
        state.bootstrap = { error = plan_error, status = _("Automatic setup is not supported on this device.") }
        state.view = "setup"
        if not defer_rebuild and context and context.requestRebuild then context.requestRebuild("ui") end
        return false
    end
    local tool_dir = YouTube.managedToolDirectory()
    if not tool_dir then
        state.bootstrap_attempted = true
        state.bootstrap = { error = _("KOReader's data folder could not be found.") }
        state.view = "setup"
        if not defer_rebuild and context and context.requestRebuild then context.requestRebuild("ui") end
        return false
    end
    local work, work_error = jobDirectory()
    if not work then
        state.bootstrap_attempted = true
        state.bootstrap = { error = work_error }
        state.view = "setup"
        return false
    end
    local command, command_error = YouTube.buildBootstrapCommand(
        tool_dir, work, plan, state.tools.ytdlp == nil, state.tools.ffmpeg == nil)
    if not command then
        state.bootstrap_attempted = true
        state.bootstrap = { error = command_error }
        state.view = "setup"
        return false
    end
    local handle, start_error = self:_startDetached(command, work, "bootstrap")
    if not handle then
        cleanupDirectory(work)
        state.bootstrap_attempted = true
        state.bootstrap = { error = start_error or _("The download process could not be started.") }
        state.view = "setup"
        return false
    end
    state.bootstrap_attempted = true
    state.bootstrap = {
        handle = handle,
        work = work,
        started = os.time(),
        status = _("Starting automatic tool setup…"),
        live_output = YouTube.liveLogPreview(""),
        install_ytdlp = state.tools.ytdlp == nil,
        install_ffmpeg = state.tools.ffmpeg == nil,
    }
    state.view = "setup"
    if not defer_rebuild and context and context.requestRebuild then context.requestRebuild("ui") end
    local tick
    tick = function()
        local bootstrap = state.bootstrap
        if not bootstrap or bootstrap.handle ~= handle then return end
        local code, log = self:_pollDetached(handle)
        if code == nil and os.time() - bootstrap.started > 1800 then
            self:_killDetached(handle)
            code, log = 124, _("Tool setup timed out after 30 minutes.")
        end
        if code == nil then
            local status = readFile(work .. "/bootstrap.status")
            if status and trim(status) ~= "" then bootstrap.status = trim(status) end
            bootstrap.progress_phase = ((bootstrap.progress_phase or 0) + 1) % 8
            setProgressBarPulse(bootstrap.progress_widget, bootstrap.progress_phase)
            local live_output = YouTube.liveLogPreview(readFile(handle.log) or "")
            if live_output ~= bootstrap.live_output then
                bootstrap.live_output = live_output
                if bootstrap.live_widget and bootstrap.live_widget.setText then
                    bootstrap.live_widget:setText(live_output)
                end
            end
            if context and hostIsActive(context) then
                -- Rebuild the visible setup pane so the pulse and live log are
                -- painted from current state, even when a nested widget's
                -- partial repaint would otherwise be skipped by the host.
                if context.requestRebuild then context.requestRebuild("fast")
                elseif context.requestRefresh then context.requestRefresh("fast") end
            end
            UIManager:scheduleIn(2, tick)
            return
        end
        bootstrap.live_output = YouTube.liveLogPreview(log or "")
        if bootstrap.live_widget and bootstrap.live_widget.setText then
            bootstrap.live_widget:setText(bootstrap.live_output)
        end
        cleanupDirectory(work)
        bootstrap.handle = nil
        if code == 0 then
            local tool_dir = YouTube.managedToolDirectory()
            local patch = {}
            if bootstrap.install_ytdlp then patch.ytdlp_path = tool_dir .. "/yt-dlp" end
            if bootstrap.install_ffmpeg then patch.ffmpeg_path = tool_dir .. "/ffmpeg" end
            self:_patchSettings(patch)
        end
        local tools = YouTube.detectTools(self:_settings())
        state.tools = tools
        if code == 0 and tools.ready then
            state.bootstrap = nil
            state.view = "home"
            state.note = _("Setup complete. Search for a video.")
        else
            local tail = trim((log or ""):sub(-420))
            bootstrap.error = tail ~= "" and tail or _("The automatic download failed. Check the network connection and try again.")
            bootstrap.status = _("Automatic setup could not finish.")
        end
        if context and hostIsActive(context) and context.requestRebuild then context.requestRebuild("ui") end
    end
    UIManager:scheduleIn(2, tick)
    return true
end

-- Runs a small ffmpeg job and reads the first output byte, to learn how this
-- ffmpeg build writes `monow`. Returns true when bit 1 means black.
function YouTube._probeMonow(ffmpeg, width, height, filter)
    local directory = jobDirectory()
    if not directory then return nil end
    local input_path = directory .. "/probe.gray"
    local output_path = directory .. "/probe.mono"
    local ok_input = writeFile(input_path, string.rep("\255", 64 * 64))
    if not ok_input then
        cleanupDirectory(directory)
        return nil
    end
    local command = shellQuote(ffmpeg)
        .. " -nostdin -hide_banner -loglevel error -f rawvideo -pix_fmt gray -s 64x64"
        .. " -i " .. shellQuote(input_path)
        .. " -vf " .. shellQuote(filter)
        .. " -frames:v 1 -pix_fmt monow -f rawvideo " .. shellQuote(output_path) .. " 2>/dev/null"
    os.execute(command)
    local first_byte = readFile(output_path)
    cleanupDirectory(directory)
    if not first_byte or #first_byte < 1 then return nil end
    local value = first_byte:byte(1)
    if value == 0 then return true end
    if value == 255 then return false end
    return nil
end

function YouTube:_startJob(instance, context, spec)
    local state = self:_state(instance)
    if type(spec) ~= "table" or (spec.kind ~= "file" and spec.kind ~= "url")
        or trim(spec.source) == "" or trim(spec.slug) == "" or tostring(spec.slug):find("/", 1, true) then
        self:_notify(instance, context, _("The selected video is incomplete. Please search again and retry."))
        return nil
    end
    if state.job then
        self:_notify(instance, context, _("A video conversion is already running."))
        return nil
    end
    if ACTIVE_CONVERSION then
        self:_notify(instance, context, _("Another AppDock video conversion is already running. Please wait for it to finish."))
        return nil
    end
    if spec.kind == "file" and not fileExists(spec.source) then
        self:_notify(instance, context, _("The video file cannot be opened."))
        return nil
    end
    local settings = self:_settings()
    local tools = state.tools or YouTube.detectTools(settings)
    state.tools = tools

    if spec.kind ~= "file" and not tools.ytdlp then
        self:_notify(instance, context, _("yt-dlp was not found. Add it to the AppDock tools folder or configure its path."))
        return nil
    end
    if not tools.ffmpeg then
        self:_notify(instance, context, _("ffmpeg was not found. Add it to the AppDock tools folder or configure its path."))
        return nil
    end

    local output_directory = self:_outputDirectory()
    local output_probe = io.open(output_directory .. "/.appdock-write-probe", "wb")
    if not output_probe then
        self:_notify(instance, context, _("The video folder cannot be written. Choose another output folder."))
        return nil
    end
    output_probe:close()
    os.remove(output_directory .. "/.appdock-write-probe")
    local work, work_error = jobDirectory()
    if not work then
        self:_notify(instance, context, work_error or _("A temporary video folder could not be created."))
        return nil
    end
    local target = output_directory .. "/" .. spec.slug .. ".bwr"
    local job = {
        kind = spec.kind,
        source = spec.source,
        title = spec.title or spec.slug,
        video_id = spec.video_id,
        -- A Shorts prefetch uses the same bounded conversion pipeline but must
        -- not replace the currently visible player pane while it runs.
        prefetch = spec.prefetch == true,
        prefetch_index = spec.prefetch_index,
        duration = spec.duration,
        work = work,
        target = target,
        partial_target = target .. ".part",
        wav = target:gsub("%.bwr$", ".wav"),
        source_file = work .. "/source.media",
        stage = "download",
        stage_message = _("Preparing"),
        percent = 0,
        frames = 0,
        expected_frames = spec.duration and spec.duration > 0
            and math.floor(math.min(spec.duration, settings.max_duration > 0 and settings.max_duration or spec.duration) * settings.fps)
            or nil,
        started = os.time(),
        log_tail = "",
    }
    os.remove(job.partial_target)
    if not claimConversion(job) then
        cleanupDirectory(work)
        self:_notify(instance, context, _("Another AppDock video conversion is already running. Please wait for it to finish."))
        return nil
    end
    state.job = job
    if not job.prefetch then state.view = "job" end
    state.note = ""

    if spec.kind == "file" then
        job.source_file = spec.source
        job.stage = "video"
        job.stage_message = _("Converting video")
        self:_startVideoStage(instance, context, job)
    else
        local command = YouTube.buildDownloadCommand(
            tools.ytdlp, tools.ffmpeg, job.source_file, spec.source, settings.max_height)
        local handle, err = self:_startDetached(command, work, "download")
        if not handle then
            job.stage = "error"
            job.stage_message = err or _("The download could not be started.")
        else
            job.download = handle
        end
    end

    if not job.prefetch and context and context.requestRebuild then context.requestRebuild("ui") end
    if job.stage == "error" then releaseConversion(job) end
    self:_schedule(instance, context)
    return job
end

function YouTube:_startVideoStage(instance, context, job)
    local settings = self:_settings()
    local tools = self:_state(instance).tools
    local width, height = YouTube.frameSize(settings.resolution_percent)
    local color_mode = settings.color_mode == true
    local dithered = not color_mode and settings.dither == "ffmpeg"

    local filter = YouTube.buildFilter(width, height, settings.fps, dithered, color_mode)
    local inversion
    if dithered then
        -- The `monow` bit sense is a property of the FFmpeg build, not of the
        -- frame geometry, so the probe result is kept per binary. A second
        -- conversion on the same reader then skips the extra FFmpeg run.
        local state = self:_state(instance)
        state.monow_inversion = state.monow_inversion or {}
        inversion = state.monow_inversion[tools.ffmpeg]
        if inversion == nil then
            inversion = YouTube._probeMonow(tools.ffmpeg, width, height, filter)
            if inversion ~= nil then state.monow_inversion[tools.ffmpeg] = inversion end
        end
        if inversion == nil then
            -- Unknown bit sense: fall back to the deterministic Bayer path.
            dithered = false
            filter = YouTube.buildFilter(width, height, settings.fps, false)
            job.log_tail = _("ffmpeg did not report a usable 1-bit mode; AppDock dithers the frames itself.")
        end
    end

    local encoder, encoder_error
    if color_mode then encoder, encoder_error = BWR.newColorEncoder(width, height)
    else encoder, encoder_error = BWR.newEncoder(width, height) end
    if not encoder then
        job.stage = "error"
        job.stage_message = encoder_error
        return
    end

    local handle = io.open(job.partial_target, "wb")
    if not handle then
        job.stage = "error"
        job.stage_message = _("The target file cannot be written. Choose another output folder.")
        return
    end
    local writer, writer_error
    if color_mode then writer, writer_error = BWR.newColorWriter(handle, width, height, settings.fps)
    else writer, writer_error = BWR.newWriter(handle, width, height, settings.fps) end
    if not writer then
        handle:close()
        job.stage = "error"
        job.stage_message = writer_error
        return
    end

    local error_log = job.work .. "/ffmpeg.log"
    local command = shellQuote(tools.ffmpeg)
        .. " -nostdin -hide_banner -loglevel error -threads " .. tostring(FFMPEG_DECODE_THREADS) .. " -filter_threads 1"
        .. " -i " .. shellQuote(job.source_file)
        .. (settings.max_duration > 0 and (" -t " .. tostring(settings.max_duration)) or "")
        .. " -an -sn -dn -vf " .. shellQuote(filter)
        .. " -pix_fmt " .. (color_mode and "rgb24" or (dithered and "monow" or "gray"))
        .. " -f rawvideo - 2>" .. shellQuote(error_log)
    local pipe = io.popen(command, "r")
    if not pipe then
        handle:close()
        job.stage = "error"
        job.stage_message = _("ffmpeg could not be started.")
        return
    end

    job.stage = "video"
    job.stage_message = _("Converting video")
    job.interval = VIDEO_TICK_INTERVAL
    job.width, job.height = width, height
    job.encoder = encoder
    job.handle = handle
    job.writer = writer
    job.pipe = pipe
    job.dithered = dithered
    job.color_mode = color_mode
    job.color_dither = settings.color_dither ~= false
    job.invert = inversion == true
    job.error_log = error_log
    job.frame_bytes = color_mode and (width * height * 3)
        or (dithered and BWR.frameBytes(width, height) or (width * height))
    job.read_buffer, job.read_pos = "", 1
    job.read_batch_bytes = job.frame_bytes * VIDEO_READ_BATCH_FRAMES
    job.percent = 0
end

function YouTube:_finishVideoStage(instance, context, job)
    local handle = job.handle
    local frame_count = job.frames
    if job.pipe then
        local close_ok, close_result, close_reason, close_code = pcall(function() return job.pipe:close() end)
        job.pipe = nil
        if not close_ok or close_result == false or (close_reason == "exit" and close_code and close_code ~= 0) then
            local log = readFile(job.error_log) or ""
            job.stage = "error"
            job.stage_message = _("ffmpeg stopped before the video was complete.") .. "\n" .. trim(log:sub(-400))
            return
        end
    end
    if handle then
        if frame_count > 0 then
            local finished_ok, finalized, finalize_error = pcall(function()
                return job.writer and job.writer:finish()
            end)
            if not finished_ok or not finalized then
                pcall(function() handle:close() end)
                job.handle, job.writer = nil, nil
                job.stage = "error"
                job.stage_message = (finished_ok and finalize_error) or _("The BWR2 video index could not be finalized.")
                return
            end
        else
            os.remove(job.partial_target)
        end
        local closed = pcall(function() handle:close() end)
        if not closed then
            job.handle, job.writer, job.encoder = nil, nil, nil
            job.stage = "error"
            job.stage_message = _("The BWR2 video file could not be closed safely.")
            return
        end
    end
    job.handle = nil
    job.writer = nil
    job.encoder = nil

    if frame_count == 0 then
        local log = readFile(job.error_log) or ""
        job.stage = "error"
        job.stage_message = _("ffmpeg produced no video frames.") .. "\n" .. trim(log:sub(-400))
        return
    end

    if not os.rename(job.partial_target, job.target) then
        job.stage = "error"
        job.stage_message = _("The converted video could not be installed safely.")
        return
    end
    job.stage = "audio"
    job.stage_message = _("Extracting audio")
    job.percent = 96
    job.interval = 1
    -- Start audio only after the raw-frame pipe and BWR writer are closed. Two
    -- concurrent FFmpeg readers caused avoidable OOM crashes on Kobo devices.
    self:_startAudioStage(instance, context, job)
    if not job.audio and job.audio_code == nil then
        self:_finishJob(instance, context, job, true)
    end
end

-- Extracts the companion WAV only after frame conversion is complete. Keeping
-- one FFmpeg process at a time prevents the reader from killing KOReader when
-- two decoders compete for memory.
function YouTube:_startAudioStage(instance, context, job)
    if job.audio or job.audio_code ~= nil then return job.audio end
    local settings = self:_settings()
    local tools = self:_state(instance).tools
    if not tools or not tools.ffmpeg then
        job.audio_failed = true
        return nil
    end
    local command = shellQuote(tools.ffmpeg)
        .. " -nostdin -hide_banner -loglevel error -threads " .. tostring(FFMPEG_DECODE_THREADS) .. " -filter_threads 1 -y"
        .. " -i " .. shellQuote(job.source_file)
        .. (settings.max_duration > 0 and (" -t " .. tostring(settings.max_duration)) or "")
        .. " -vn -sn -dn -af " .. shellQuote(
            "silenceremove=start_periods=1:start_duration=0.05:start_threshold=-50dB,"
            .. "aresample=async=1:first_pts=0")
        .. " -c:a pcm_s16le -ar 44100 -ac 2 -f wav " .. shellQuote(job.wav)
    local detached = self:_startDetached(command, job.work, "audio")
    if detached then
        job.audio = detached
    else
        job.audio_failed = true
    end
    return job.audio
end

-- Collects the parallel audio pass as soon as it exits, so neither the frame
-- conversion nor the final stage has to wait for it twice.
function YouTube:_pollAudioStage(job)
    if not job.audio then return nil end
    local code, log = self:_pollDetached(job.audio)
    if code == nil then return nil end
    job.audio = nil
    job.audio_code = code
    if code ~= 0 then job.log_tail = (log or ""):sub(-300) end
    return code
end

function YouTube:_finishJob(instance, context, job, without_audio)
    local wav_handle = io.open(job.wav, "rb")
    if wav_handle then
        wav_handle:close()
    elseif not without_audio then
        job.wav = nil
    end
    job.percent = 100
    job.stage = "done"
    job.stage_message = _("Finished")
    local frame_count = job.frames
    local fps = tonumber(self:_settings().fps) or DEFAULT_SETTINGS.fps
    local seconds = frame_count > 0 and (frame_count / math.max(1, fps)) or 0
    self:_notify(instance, context, string.format(
        _("Saved %s · %d frames · %s"),
        basename(job.target), frame_count, formatDuration(seconds)
    ))
    local appdock = self.appdock
    if appdock and type(appdock.notify) == "function" then
        pcall(function()
            appdock:notify({
                title = _("YouTube video ready"),
                message = basename(job.target),
                source = _("YouTube"),
                app_id = "dapp:youtube",
            })
        end)
    end
    self:_cleanupJob(job)
    releaseConversion(job)
    local state = self:_state(instance)
    state.job = nil
    self:scanLibrary(instance, context)
    state.selected_path = job.target
    -- A rebuild would close the player pane, so a finished job never
    -- interrupts ongoing playback; the library is already up to date.
    if not job.prefetch and state.view ~= "play" then
        state.view = "home"
        state.watching = true
        if context and context.requestRebuild then context.requestRebuild("ui") end
    end
end

function YouTube:_failJob(instance, context, job, message)
    job.stage = "error"
    job.stage_message = message or _("The conversion failed.")
    job.percent = 0
    -- Always close pipes and temporary writers on error. Keeping an orphaned
    -- ffmpeg pipe alive after a Lua-side encoder failure made later conversions
    -- unstable as well.
    self:_cleanupJob(job)
    releaseConversion(job)
    if job.wav then os.remove(job.wav) end
    if context and context.requestRefresh then context.requestRefresh("ui") end
end

function YouTube:_cleanupJob(job)
    self:_killDetached(job.download)
    self:_killDetached(job.audio)
    if job.pipe then
        pcall(function() job.pipe:close() end)
        job.pipe = nil
    end
    if job.handle then
        pcall(function() job.handle:close() end)
        job.handle = nil
    end
    if job.partial_target then os.remove(job.partial_target) end
    cleanupDirectory(job.work)
end

function YouTube:cancelJob(instance, context)
    local state = self:_state(instance)
    local job = state.job
    if not job then return end
    self:_cleanupJob(job)
    releaseConversion(job)
    state.job = nil
    state.view = "home"
    self:_notify(instance, context, _("Conversion cancelled."))
    if context and context.requestRebuild then context.requestRebuild("ui") end
end

function YouTube:_schedule(instance, context)
    local state = self:_state(instance)
    local job = state.job
    if not job then return end
    job.tick = job.tick or function() self:_tick(instance, context) end
    UIManager:scheduleIn(job.interval or 1, job.tick)
end

function YouTube:_tick(instance, context)
    local state = self:_state(instance)
    local job = state.job
    if not job then return end
    local settings = self:_settings()

    if job.stage == "download" then
        if not job.download then
            self:_failJob(instance, context, job, _("The download could not be started."))
            return
        end
        local code, log = self:_pollDetached(job.download)
        if log then
            job.log_tail = log:sub(-300)
            local percent = YouTube.parseProgress(log)
            if percent then job.percent = percent * 0.35 end
            job.stage_message = percent
                and string.format(_("Downloading %d%%"), math.floor(percent))
                or _("Downloading")
        end
        if code ~= nil then
            job.download = nil
            local source_handle = io.open(job.source_file, "rb")
            local source_size = source_handle and source_handle:seek("end") or 0
            if source_handle then source_handle:close() end
            if code ~= 0 or not source_handle or not source_size or source_size <= 0 then
                job.log_tail = trim((log or ""):sub(-700))
                self:_failJob(instance, context, job, YouTube.describeDownloadFailure(log))
                return
            end
            self:_startVideoStage(instance, context, job)
        end
    elseif job.stage == "video" then
        if state.job ~= job or not job.pipe or not job.encoder or not job.writer or not job.frame_bytes then
            self:_failJob(instance, context, job, _("The video converter stopped unexpectedly."))
            return
        end
        local tick_started = os.clock()
        for _ = 1, VIDEO_MAX_FRAMES_PER_TICK do
            local frame
            if job.read_pos + job.frame_bytes - 1 <= #job.read_buffer then
                frame = job.read_buffer:sub(job.read_pos, job.read_pos + job.frame_bytes - 1)
                job.read_pos = job.read_pos + job.frame_bytes
            else
                local read_ok, chunk = pcall(function() return job.pipe:read(job.read_batch_bytes or job.frame_bytes) end)
                if not read_ok then
                    self:_failJob(instance, context, job, _("The video converter stopped unexpectedly."))
                    return
                end
                if not chunk or #chunk < job.frame_bytes then
                    self:_finishVideoStage(instance, context, job)
                    break
                end
                job.read_buffer, job.read_pos = chunk, job.frame_bytes + 1
                frame = chunk:sub(1, job.frame_bytes)
            end
            local packed, encode_error
            local packed_ok, packed_result, packed_message = pcall(function()
                if job.color_mode then return job.encoder:pack(frame, job.color_dither) end
                if job.dithered then return job.encoder:packPreDithered(frame, job.invert) end
                return job.encoder:pack(frame)
            end)
            if not packed_ok then
                self:_failJob(instance, context, job, _("The video frame encoder failed."))
                return
            end
            packed, encode_error = packed_result, packed_message
            if not packed then
                self:_failJob(instance, context, job, encode_error)
                return
            end
            local write_ok, written, write_error = pcall(function() return job.writer:writeFrame(packed) end)
            if not write_ok or not written then
                self:_failJob(instance, context, job, write_ok and write_error or _("The video output could not be written."))
                return
            end
            job.frames = job.frames + 1
            if os.clock() - tick_started >= VIDEO_TICK_CPU_BUDGET then break end
        end
        if job.stage == "video" then
            if job.expected_frames and job.expected_frames > 0 then
                job.percent = 35 + 61 * clamp(job.frames / job.expected_frames, 0, 1)
                job.stage_message = string.format(
                    _("Converting video · frame %d of about %d"), job.frames, job.expected_frames)
            else
                job.percent = 60
                job.stage_message = string.format(_("Converting video · frame %d"), job.frames)
            end
        end
    elseif job.stage == "audio" then
        if job.audio then
            self:_pollAudioStage(job)
            if not job.audio then
                self:_finishJob(instance, context, job, job.audio_code ~= 0)
                return
            end
            job.stage_message = _("Extracting audio")
        else
            -- The pass finished while the frames were still converting, or it
            -- never started. Either way the job can settle now.
            self:_finishJob(instance, context, job, job.audio_code ~= 0)
            return
        end
    else
        return
    end

    setProgressBarPercent(job.progress_widget, job.percent)
    if job.stage_widget and job.stage_widget.setText then
        job.stage_widget:setText(fitText(job.stage_message or "", job.stage_widget_width or 160, 11))
    end
    local refresh_now = monotonicNow()
    local refresh_interval = job.stage == "video" and VIDEO_PROGRESS_REFRESH_INTERVAL or PROGRESS_REFRESH_INTERVAL
    if not job.last_progress_refresh or refresh_now - job.last_progress_refresh >= refresh_interval then
        job.last_progress_refresh = refresh_now
        if hostIsActive(context) then
            -- The progress bar is nested in the DApp pane. Rebuilding at this
            -- throttled cadence makes the host paint a fresh widget tree while
            -- keeping the E-Ink refresh partial and avoiding per-frame rebuilds.
            if context.requestRebuild then context.requestRebuild("fast")
            elseif context.requestRefresh then context.requestRefresh("fast") end
        end
    end
    if job.stage == "error" then
        -- Nothing is running any more: show the message and stop ticking.
        self:_cleanupJob(job)
        releaseConversion(job)
        if hostIsActive(context) and context.requestRebuild and self:_state(instance).view ~= "play" then
            context.requestRebuild("ui")
        end
        return
    end
    if state.job == job then
        UIManager:scheduleIn(job.interval or 1, job.tick)
    end
end

function YouTube:startSearch(instance, context, query)
    local state = self:_state(instance)
    local tools = state.tools or YouTube.detectTools(self:_settings())
    state.tools = tools
    if not tools.ytdlp then
        self:_notify(instance, context, _("yt-dlp was not found. Add it to the AppDock tools folder or configure its path."))
        return false
    end
    query = trim(query)
    if query == "" then return false end
    local work, work_error = jobDirectory()
    if not work then
        self:_notify(instance, context, work_error or _("A temporary search folder could not be created."))
        return false
    end
    local command = shellQuote(tools.ytdlp)
        .. " --no-warnings --no-cache-dir --flat-playlist --ignore-errors"
        .. " --print " .. shellQuote("%(id)s\t%(title)s\t%(duration)s\t%(uploader)s\t%(thumbnail)s")
        .. " " .. shellQuote("ytsearch8:" .. query)
    local handle, err = self:_startDetached(command, work, "search")
    if not handle then
        self:_notify(instance, context, err or _("The search could not be started."))
        return false
    end
    state.search = { handle = handle, work = work, query = query, started = os.time() }
    state.view = "search"
    state.note = _("Searching YouTube")
    if context and context.requestRebuild then context.requestRebuild("ui") end
    local tick
    tick = function()
        local code, log = self:_pollDetached(handle)
        if code == nil then
            if os.time() - state.search.started > 90 then
                self:_killDetached(handle)
                cleanupDirectory(work)
                state.search = nil
                state.view = "home"
                state.note = _("The search timed out.")
                if context and context.requestRebuild then context.requestRebuild("ui") end
                return
            end
            UIManager:scheduleIn(1, tick)
            return
        end
        cleanupDirectory(work)
        state.search = nil
        if code ~= 0 and trim(log or "") == "" then
            state.note = _("The search failed.") .. " " .. _("Check the network connection.")
            state.view = "home"
        else
            local results = YouTube.parseSearchOutput(log)
            for loop_index, result in ipairs(results) do self:_cacheThumbnail(result) end
            state.results = results
            state.results_query = query
            state.result_page = 1
            state.view = #results > 0 and "results" or "home"
            state.note = #results > 0 and "" or _("No results were returned.")
            if #results > 0 and context and context.requestRebuild then
                UIManager:scheduleIn(3, function() context.requestRebuild("ui") end)
            end
        end
        if context and context.requestRebuild then context.requestRebuild("ui") end
    end
    UIManager:scheduleIn(1, tick)
    return true
end

local function availableOutputPath(directory, slug)
    for index = 1, 50 do
        local suffix = index == 1 and "" or "-" .. tostring(index)
        local candidate = directory .. "/" .. slug .. suffix .. ".bwr"
        local handle = io.open(candidate, "rb")
        if not handle then return candidate end
        handle:close()
    end
    return directory .. "/" .. slug .. "-" .. tostring(os.time()) .. ".bwr"
end

function YouTube:startVideo(instance, context, result)
    if type(result) ~= "table" or trim(result.id) == "" then
        self:_notify(instance, context, _("This video result is incomplete. Please search again."))
        return nil
    end
    local slug = YouTube.slugify(result.title, result.id)
    local directory = self:_outputDirectory()
    local candidate = availableOutputPath(directory, slug)
    slug = basename(candidate):gsub("%.bwr$", "")
    if result.thumbnail then
        self:_cacheThumbnail(result, candidate:gsub("%.bwr$", ".jpg"))
    end
    return self:_startJob(instance, context, {
        kind = "url",
        source = result.url or YouTube.watchUrl(result.id),
        title = result.title,
        video_id = result.id,
        duration = result.duration,
        slug = slug,
    })
end

function YouTube:startLocalFile(instance, context, path)
    path = trim(path)
    if path == "" then return nil end
    local handle = io.open(path, "rb")
    if not handle then
        self:_notify(instance, context, _("The video file cannot be opened."))
        return nil
    end
    handle:close()
    local slug = YouTube.slugify(basename(path):gsub("%.[%w]+$", ""), "video")
    local directory = self:_outputDirectory()
    local candidate = availableOutputPath(directory, slug)
    return self:_startJob(instance, context, {
        kind = "file",
        source = path,
        title = basename(path),
        duration = nil,
        slug = basename(candidate):gsub("%.bwr$", ""),
    })
end

----------------------------------------------------------------
-- Rows
----------------------------------------------------------------

local Row = InputContainer:extend{
    title = nil,
    subtitle = nil,
    value = nil,
    callback = nil,
    hold_callback = nil,
    width = nil,
    height = nil,
    background = nil,
    bordered = false,
    video_card = false,
    thumbnail_text = "▶",
    thumbnail_path = nil,
    thumbnail_source_path = nil,
    dimen = nil,
}

local function fitThumbnailFrame(source, target_width, target_height)
    local source_width, source_height = source:getWidth(), source:getHeight()
    local factor = math.min(target_width / source_width, target_height / source_height)
    local width = math.max(1, math.floor(source_width * factor))
    local height = math.max(1, math.floor(source_height * factor))
    local scaled = Blitbuffer.new(width, height, Blitbuffer.TYPE_BB8)
    local source_data = ffi.cast("uint8_t*", source.data)
    local scaled_data = ffi.cast("uint8_t*", scaled.data)
    for y = 0, height - 1 do
        local source_y = math.min(source_height - 1, math.floor(y * source_height / height))
        for x = 0, width - 1 do
            local source_x = math.min(source_width - 1, math.floor(x * source_width / width))
            scaled_data[y * width + x] = source_data[source_y * source_width + source_x]
        end
    end
    return scaled
end

function Row:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local padding = scale(8)
    self.thumbnail_width = self.video_card and math.floor(self.width * 0.34) or 0
    local text_left = padding + self.thumbnail_width + (self.video_card and padding or 0)
    local themed = self.themed == true
    local text_width = math.max(1, self.width - text_left - padding - (themed and scale(10) or scale(46)))
    local title_size = themed and 13 or 12
    local title_color = themed and YT.fg or Blitbuffer.COLOR_BLACK
    local sub_color = themed and YT.sub or Blitbuffer.COLOR_DARK_GRAY
    local title_lines = themed and wrapLines(self.title or "", text_width, title_size, 2)
        or { fitText(self.title or "", text_width, 12) }
    self.title_widgets = {}
    for line_index, line in ipairs(title_lines) do
        self.title_widgets[line_index] = TextWidget:new{
            text = line,
            face = Font:getFace("smallinfofont", scale(title_size)),
            bold = not themed,
            fgcolor = title_color,
            max_width = text_width,
        }
    end
    self.subtitle_widget = TextWidget:new{
        text = fitText(self.subtitle or "", text_width, 9, true),
        face = Font:getFace("smallinfofont", scale(themed and 10 or 9)),
        fgcolor = sub_color,
        max_width = text_width,
    }
    self.value_widget = TextWidget:new{
        text = fitText(self.value or "", scale(44), 10),
        face = Font:getFace("smallinfofont", scale(10)),
        fgcolor = sub_color,
        max_width = scale(44),
    }
    if self.video_card then
        local image_ok = false
        if fileExists(self.thumbnail_source_path) then
            local ok, frame = pcall(function()
                local handle = io.open(self.thumbnail_source_path, "rb")
                if not handle then return nil end
                local header = BWR.readHeader(handle)
                if not header then handle:close(); return nil end
                handle:seek("set", BWR.HEADER_BYTES)
                local packed = handle:read(header.frame_bytes)
                handle:close()
                if not packed or #packed ~= header.frame_bytes then return nil end
                return BWR.expandFrame(packed, header.width, header.height)
            end)
            if ok and frame then
                self.thumbnail_frame = fitThumbnailFrame(frame, self.thumbnail_width, math.max(1, self.height - padding * 2))
                frame:free()
            end
        elseif ImageWidget and fileExists(self.thumbnail_path) then
            local ok, image = pcall(ImageWidget.new, ImageWidget, {
                file = self.thumbnail_path,
                width = math.max(1, self.thumbnail_width),
                height = math.max(1, self.height - padding * 2),
                file_do_cache = false,
            })
            if ok and image then
                self.thumbnail_widget = image
                self.has_thumbnail_image = true
                image_ok = true
            end
        end
        if not self.thumbnail_frame and not image_ok then
            self.thumbnail_widget = TextWidget:new{
                text = self.thumbnail_text or "▶",
                face = Font:getFace("cfont", scale(20)),
                fgcolor = themed and YT.sub or Blitbuffer.COLOR_WHITE,
                padding = 0,
            }
        end
    end
    local events = { TapRow = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    if self.hold_callback then
        events.HoldRow = { GestureRange:new{ ges = "hold", range = self.dimen } }
    end
    self.ges_events = events
end

function Row:getSize()
    return self.dimen
end

function Row:paintTo(bb, x, y)
    local background = self.background or Blitbuffer.COLOR_LIGHT_GRAY
    bb:paintRect(x, y, self.width, self.height, background)
    if self.bordered then
        local thickness = math.max(1, scale(1))
        bb:paintRect(x, y, self.width, thickness, Blitbuffer.COLOR_BLACK)
        bb:paintRect(x, y + self.height - thickness, self.width, thickness, Blitbuffer.COLOR_BLACK)
        bb:paintRect(x, y, thickness, self.height, Blitbuffer.COLOR_BLACK)
        bb:paintRect(x + self.width - thickness, y, thickness, self.height, Blitbuffer.COLOR_BLACK)
    end
    local padding = scale(8)
    if self.video_card then
        if self.thumbnail_frame then
            local draw_w, draw_h = self.thumbnail_width, self.height - padding * 2
            local source_w, source_h = self.thumbnail_frame:getWidth(), self.thumbnail_frame:getHeight()
            bb:paintRect(x + padding, y + padding, draw_w, draw_h, Blitbuffer.COLOR_BLACK)
            bb:blitFrom(self.thumbnail_frame,
                x + padding + math.floor((draw_w - source_w) / 2),
                y + padding + math.floor((draw_h - source_h) / 2),
                0, 0, source_w, source_h)
        elseif not self.has_thumbnail_image then
            bb:paintRect(x + padding, y + padding, self.thumbnail_width, self.height - padding * 2,
                self.themed and YT.thumb or Blitbuffer.COLOR_DARK_GRAY)
        end
        if not self.thumbnail_frame then
            local thumb_size = self.thumbnail_widget:getSize()
            self.thumbnail_widget:paintTo(bb,
                x + padding + math.floor((self.thumbnail_width - thumb_size.w) / 2),
                y + math.floor((self.height - thumb_size.h) / 2))
        end
    end
    local text_x = x + padding + self.thumbnail_width + (self.video_card and padding or 0)
    local line_y = y + scale(5)
    for loop_index, widget in ipairs(self.title_widgets) do
        widget:paintTo(bb, text_x, line_y)
        line_y = line_y + (self.themed and widget:getSize().h or scale(16))
    end
    self.subtitle_widget:paintTo(bb, text_x, self.themed and (line_y + scale(2)) or (y + scale(21)))
    local value_size = self.value_widget:getSize()
    self.value_widget:paintTo(bb, x + self.width - padding - value_size.w, y + math.floor((self.height - value_size.h) / 2))
    local range = self.ges_events.TapRow[1].range
    range.x, range.y, range.w, range.h = x, y, self.width, self.height
    if self.ges_events.HoldRow then
        local hold = self.ges_events.HoldRow[1].range
        hold.x, hold.y, hold.w, hold.h = x, y, self.width, self.height
    end
end

function Row:onTapRow()
    if self.callback then self.callback() end
    return true
end

function Row:onHoldRow()
    if self.hold_callback then self.hold_callback() end
    return true
end

YouTube.Row = Row

----------------------------------------------------------------
-- YouTube style widgets: Btn (chips, pills), NavTab, Card
----------------------------------------------------------------

-- Loads the first BWR frame (library videos) or a cached JPEG (search
-- results) and fits it into width x height.
local function loadThumbnail(source_path, image_path, width, height)
    local result = {}
    if fileExists(source_path) then
        local ok, frame = pcall(function()
            local handle = io.open(source_path, "rb")
            if not handle then return nil end
            local header = BWR.readHeader(handle)
            if not header then handle:close(); return nil end
            handle:seek("set", BWR.HEADER_BYTES)
            local packed = handle:read(header.frame_bytes)
            handle:close()
            if not packed or #packed ~= header.frame_bytes then return nil end
            return BWR.expandFrame(packed, header.width, header.height)
        end)
        if ok and frame then
            result.frame = fitThumbnailFrame(frame, math.max(1, width), math.max(1, height))
            frame:free()
        end
    elseif ImageWidget and fileExists(image_path) then
        local ok, image = pcall(ImageWidget.new, ImageWidget, {
            file = image_path,
            width = math.max(1, width),
            height = math.max(1, height),
            file_do_cache = false,
        })
        if ok and image then result.image = image end
    end
    return result
end

local Btn = InputContainer:extend{
    text = "",
    callback = nil,
    hold_callback = nil,
    width = nil,
    height = nil,
    background = nil,
    foreground = nil,
    font_size = 11,
    bold = true,
    align = "center",
    radius = nil,
    dimen = nil,
}

function Btn:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self.pad = scale(10)
    local max_w = math.max(1, self.width - self.pad * 2)
    self.text_widget = TextWidget:new{
        text = fitText(self.text or "", max_w, self.font_size),
        face = Font:getFace("smallinfofont", scale(self.font_size)),
        bold = self.bold ~= false,
        fgcolor = self.foreground or YT.chip_fg,
        max_width = max_w,
        padding = 0,
    }
    local events = { TapBtn = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    if self.hold_callback then
        events.HoldBtn = { GestureRange:new{ ges = "hold", range = self.dimen } }
    end
    self.ges_events = events
end

function Btn:getSize()
    return self.dimen
end

function Btn:paintTo(bb, x, y)
    if self.background then
        paintRound(bb, x, y, self.width, self.height, self.background, self.radius or scale(8))
    end
    local size = self.text_widget:getSize()
    local text_x = x + math.floor((self.width - size.w) / 2)
    if self.align == "left" then text_x = x + self.pad end
    self.text_widget:paintTo(bb, text_x, y + math.floor((self.height - size.h) / 2))
    local range = self.ges_events.TapBtn[1].range
    range.x, range.y, range.w, range.h = x, y, self.width, self.height
    if self.ges_events.HoldBtn then
        local hold = self.ges_events.HoldBtn[1].range
        hold.x, hold.y, hold.w, hold.h = x, y, self.width, self.height
    end
end

function Btn:onTapBtn()
    if self.callback then self.callback() end
    return true
end

function Btn:onHoldBtn()
    if self.hold_callback then self.hold_callback() end
    return true
end

-- Bottom navigation entry: icon above a small label. `plus` draws the round
-- "create" button in the middle instead.
local NavTab = InputContainer:extend{
    icon = "",
    label = "",
    active = false,
    plus = false,
    callback = nil,
    width = nil,
    height = nil,
    dimen = nil,
}

function NavTab:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local color = self.active and YT.fg or YT.sub
    self.icon_widget = TextWidget:new{
        text = self.icon or "",
        face = Font:getFace("cfont", scale(self.plus and 22 or 18)),
        bold = self.active == true,
        fgcolor = self.plus and YT.fg or color,
        padding = 0,
    }
    if not self.plus then
        self.label_widget = TextWidget:new{
            text = fitText(self.label or "", self.width - scale(4), 9),
            face = Font:getFace("smallinfofont", scale(9)),
            bold = self.active == true,
            fgcolor = color,
            max_width = math.max(1, self.width - scale(4)),
            padding = 0,
        }
    end
    self.ges_events = { TapNavTab = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function NavTab:getSize()
    return self.dimen
end

function NavTab:paintTo(bb, x, y)
    local icon_size = self.icon_widget:getSize()
    if self.plus then
        local radius = scale(17)
        paintDisc(bb, x + math.floor(self.width / 2), y + math.floor(self.height / 2), radius, YT.chip)
        self.icon_widget:paintTo(bb,
            x + math.floor((self.width - icon_size.w) / 2),
            y + math.floor((self.height - icon_size.h) / 2))
    else
        local label_size = self.label_widget:getSize()
        local total = icon_size.h + scale(2) + label_size.h
        local top = y + math.floor((self.height - total) / 2)
        self.icon_widget:paintTo(bb, x + math.floor((self.width - icon_size.w) / 2), top)
        self.label_widget:paintTo(bb, x + math.floor((self.width - label_size.w) / 2), top + icon_size.h + scale(2))
    end
    local range = self.ges_events.TapNavTab[1].range
    range.x, range.y, range.w, range.h = x, y, self.width, self.height
end

function NavTab:onTapNavTab()
    if self.callback then self.callback() end
    return true
end

-- Feed card: large 16:9 thumbnail with a duration badge, below it a channel
-- avatar, a two line title and a "YouTube · size · age" line.
local Card = InputContainer:extend{
    entry = nil,
    width = nil,
    height = nil,
    thumb_h = nil,
    callback = nil,
    hold_callback = nil,
    dimen = nil,
}

function Card:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local entry = self.entry or {}
    self.avatar_d = scale(32)
    self.text_left = self.avatar_d + scale(10)
    local text_w = math.max(1, self.width - self.text_left - scale(4))
    self.title_widgets = {}
    for line_index, line in ipairs(wrapLines(entry.title or "", text_w, 12, 2)) do
        self.title_widgets[line_index] = TextWidget:new{
            text = line,
            face = Font:getFace("smallinfofont", scale(12)),
            fgcolor = YT.fg,
            max_width = text_w,
            padding = 0,
        }
    end
    self.meta_widget = TextWidget:new{
        text = fitText(entry.meta or entryMeta(entry), text_w, 10),
        face = Font:getFace("smallinfofont", scale(10)),
        fgcolor = YT.sub,
        max_width = text_w,
        padding = 0,
    }
    local title = tostring(entry.title or "")
    if title == "" then title = "?" end
    self.initial_widget = TextWidget:new{
        text = title:sub(1, utf8Prefix(title, 1)):upper(),
        face = Font:getFace("cfont", scale(14)),
        bold = true,
        fgcolor = YT.avatar_fg,
        padding = 0,
    }
    if entry.value and entry.value ~= "" then
        self.badge_widget = TextWidget:new{
            text = entry.value,
            face = Font:getFace("smallinfofont", scale(10)),
            bold = true,
            fgcolor = YT.badge_fg,
            padding = 0,
        }
    end
    local thumb = loadThumbnail(entry.path, entry.thumbnail_path, self.width, self.thumb_h)
    self.thumbnail_frame = thumb.frame
    self.thumbnail_image = thumb.image
    if not thumb.frame and not thumb.image then
        self.placeholder = TextWidget:new{
            text = "▶",
            face = Font:getFace("cfont", scale(34)),
            fgcolor = YT.sub,
            padding = 0,
        }
    end
    local events = { TapCard = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    if self.hold_callback then
        events.HoldCard = { GestureRange:new{ ges = "hold", range = self.dimen } }
    end
    self.ges_events = events
end

function Card:getSize()
    return self.dimen
end

function Card:paintTo(bb, x, y)
    local thumb_h = self.thumb_h
    bb:paintRect(x, y, self.width, thumb_h, self.thumbnail_frame and Blitbuffer.COLOR_BLACK or YT.thumb)
    local img_x, img_y, img_w, img_h = x, y, self.width, thumb_h
    if self.thumbnail_frame then
        local frame_w, frame_h = self.thumbnail_frame:getWidth(), self.thumbnail_frame:getHeight()
        img_x = x + math.floor((self.width - frame_w) / 2)
        img_y = y + math.floor((thumb_h - frame_h) / 2)
        img_w, img_h = frame_w, frame_h
        bb:blitFrom(self.thumbnail_frame, img_x, img_y, 0, 0, frame_w, frame_h)
    elseif self.thumbnail_image then
        local size = self.thumbnail_image:getSize()
        img_x = x + math.floor((self.width - size.w) / 2)
        img_y = y + math.floor((thumb_h - size.h) / 2)
        img_w, img_h = size.w, size.h
        self.thumbnail_image:paintTo(bb, img_x, img_y)
    elseif self.placeholder then
        local size = self.placeholder:getSize()
        self.placeholder:paintTo(bb,
            x + math.floor((self.width - size.w) / 2),
            y + math.floor((thumb_h - size.h) / 2))
    end
    if self.badge_widget then
        local size = self.badge_widget:getSize()
        local badge_w, badge_h = size.w + scale(10), size.h + scale(4)
        local badge_x = img_x + img_w - badge_w - scale(6)
        local badge_y = img_y + img_h - badge_h - scale(6)
        paintRound(bb, badge_x, badge_y, badge_w, badge_h, YT.badge, scale(4))
        self.badge_widget:paintTo(bb, badge_x + scale(5), badge_y + scale(2))
    end
    local info_y = y + thumb_h + scale(10)
    local radius = math.floor(self.avatar_d / 2)
    paintDisc(bb, x + radius, info_y + radius, radius, YT.avatar)
    local initial_size = self.initial_widget:getSize()
    self.initial_widget:paintTo(bb,
        x + radius - math.floor(initial_size.w / 2),
        info_y + radius - math.floor(initial_size.h / 2))
    local text_x = x + self.text_left
    local line_y = info_y - scale(2)
    for loop_index, widget in ipairs(self.title_widgets) do
        widget:paintTo(bb, text_x, line_y)
        line_y = line_y + widget:getSize().h
    end
    self.meta_widget:paintTo(bb, text_x, line_y + scale(2))
    local range = self.ges_events.TapCard[1].range
    range.x, range.y, range.w, range.h = x, y, self.width, self.height
    if self.ges_events.HoldCard then
        local hold = self.ges_events.HoldCard[1].range
        hold.x, hold.y, hold.w, hold.h = x, y, self.width, self.height
    end
end

function Card:onTapCard()
    if self.callback then self.callback() end
    return true
end

function Card:onHoldCard()
    if self.hold_callback then self.hold_callback() end
    return true
end

-- Compact "‹  1 / 3  ›" pager in the chip style.
local function ytPager(width, height, page, total_pages, on_prev, on_next)
    local button_w = math.min(scale(44), math.floor(width / 3))
    local widgets = {}
    widgets[1] = Btn:new{
        text = "‹", width = button_w, height = height, font_size = 14,
        background = YT.chip, foreground = YT.chip_fg, callback = on_prev,
        overlap_offset = { 0, 0 },
    }
    local label = TextWidget:new{
        text = string.format("%d / %d", page, total_pages),
        face = Font:getFace("smallinfofont", scale(10)),
        fgcolor = YT.sub,
        padding = 0,
    }
    local label_size = label:getSize()
    label.overlap_offset = {
        math.floor((width - label_size.w) / 2),
        math.floor((height - label_size.h) / 2),
    }
    widgets[2] = label
    widgets[3] = Btn:new{
        text = "›", width = button_w, height = height, font_size = 14,
        background = YT.chip, foreground = YT.chip_fg, callback = on_next,
        overlap_offset = { width - button_w, 0 },
    }
    return widgets
end

-- Round channel avatar with the first letter of the title.
local Avatar = InputContainer:extend{
    letter = "?",
    diameter = nil,
    dimen = nil,
}

function Avatar:init()
    self.dimen = Geom:new{ w = self.diameter, h = self.diameter }
    self.letter_widget = TextWidget:new{
        text = self.letter,
        face = Font:getFace("cfont", math.max(scale(10), math.floor(self.diameter * 0.45))),
        bold = true,
        fgcolor = YT.avatar_fg,
        padding = 0,
    }
end

function Avatar:getSize()
    return self.dimen
end

function Avatar:paintTo(bb, x, y)
    local radius = math.floor(self.diameter / 2)
    paintDisc(bb, x + radius, y + radius, radius, YT.avatar)
    local size = self.letter_widget:getSize()
    self.letter_widget:paintTo(bb, x + radius - math.floor(size.w / 2), y + radius - math.floor(size.h / 2))
end

local Logo = InputContainer:extend{
    height = nil,
    dimen = nil,
}

function Logo:init()
    self.logo_w = math.floor(self.height * 1.42)
    self.dimen = Geom:new{ w = self.logo_w, h = self.height }
    self.red = Blitbuffer.ColorRGB32 and Blitbuffer.ColorRGB32(0xFF, 0x00, 0x00, 0xFF) or gray(0x55)
end

function Logo:getSize()
    return self.dimen
end

function Logo:paintTo(bb, x, y)
    paintRound(bb, x, y, self.logo_w, self.height, self.red, math.floor(self.height * 0.3))
    local tri_h = math.floor(self.height * 0.5)
    local tri_w = math.floor(tri_h * 0.85)
    local left = x + math.floor((self.logo_w - tri_w) / 2) + math.floor(tri_w * 0.08)
    local middle = y + math.floor(self.height / 2)
    for column = 0, tri_w - 1 do
        local half = math.floor((tri_h / 2) * (1 - column / tri_w))
        bb:paintRect(left + column, middle - half, 1, half * 2 + 1, Blitbuffer.COLOR_WHITE)
    end
end

local function firstLetter(text)
    text = tostring(text or "")
    if text == "" then return "?" end
    return text:sub(1, utf8Prefix(text, 1)):upper()
end

-- Full-screen page with the YouTube background colour.
local function ytPage(width, height)
    return OverlapGroup:new{
        dimen = Geom:new{ w = width, h = height },
        allow_mirroring = false,
        FrameContainer:new{
            width = width, height = height, padding = 0, bordersize = 0,
            background = YT.bg,
            emptySizedWidget(width, height),
        },
    }
end


local MiniPlayer = InputContainer:extend{
    canvas = nil,
    width = nil,
    height = nil,
    callback = nil,
    dimen = nil,
    -- A MiniPlayer can carry controls inside its own lower edge. An OverlapGroup
    -- propagates events to the widgets it inserted first, so without this inset
    -- the player would swallow the taps meant for those controls.
    gesture_inset_bottom = 0,
}

function MiniPlayer:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self.ges_events = { TapMiniPlayer = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function MiniPlayer:getSize()
    return self.dimen
end

function MiniPlayer:paintTo(bb, x, y)
    if self.canvas then self.canvas:paintTo(bb, x, y) end
    local range = self.ges_events.TapMiniPlayer[1].range
    local inset = math.max(0, math.min(self.height - 1, tonumber(self.gesture_inset_bottom) or 0))
    range.x, range.y, range.w, range.h = x, y, self.width, math.max(1, self.height - inset)
end

function MiniPlayer:onTapMiniPlayer()
    if self.callback then self.callback() end
    return true
end

----------------------------------------------------------------
-- Dialogs
----------------------------------------------------------------

local function promptText(title, hint, initial, on_submit)
    local dialog
    dialog = InputDialog:new{
        title = title,
        input = initial or "",
        input_hint = hint or "",
        buttons = {
            {
                { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
                {
                    text = _("OK"),
                    is_enter_default = true,
                    callback = function()
                        local value = trim(dialog:getInputText())
                        UIManager:close(dialog)
                        on_submit(value)
                    end,
                },
            },
        },
    }
    AppDockKeyboard.attach(dialog)
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

YouTube.promptText = promptText

function YouTube:promptSearch(instance, context)
    local state = self:_state(instance)
    promptText(_("Search YouTube"), _("Song, channel or topic"), state.query, function(value)
        if value == "" then return end
        state.query = value
        self:startSearch(instance, context, value)
    end)
end

function YouTube:promptLink(instance, context)
    local state = self:_state(instance)
    promptText(_("Open YouTube link"), _("https://www.youtube.com/watch?v=..."), state.url, function(value)
        if value == "" then return end
        state.url = value
        local kind, payload = YouTube.classifyInput(value)
        if kind == "video" then
            self:startVideo(instance, context, {
                id = payload,
                title = payload,
                url = YouTube.watchUrl(payload),
            })
        elseif kind == "search" then
            state.query = payload
            self:startSearch(instance, context, payload)
        else
            self:_notify(instance, context, _("That link is not a supported YouTube address."))
        end
    end)
end

function YouTube:promptLocalFile(instance, context)
    promptText(_("Convert a local video"), _("Absolute path to a video file"), "", function(value)
        if value == "" then return end
        self:startLocalFile(instance, context, value)
    end)
end

function YouTube:editToolPath(instance, context, key, title, hint)
    local settings = self:_settings()
    promptText(title, hint, settings[key], function(value)
        local patch = {}
        patch[key] = value
        self:_patchSettings(patch)
        self:redetect(instance, context)
    end)
end

function YouTube:editAudioVideoDelay(instance, context)
    local settings = self:_settings()
    promptText(
        _("Video start after audio"),
        _("Delay in seconds (0–60; decimals allowed)"),
        string.format("%g", settings.audio_video_delay or 0),
        function(value)
            value = trim(value):gsub(",", ".")
            local delay = tonumber(value)
            if not delay or delay < 0 or delay > 60 then
                self:_notify(instance, context, _("Enter a number between 0 and 60 seconds."))
                return
            end
            self:_patchSettings({ audio_video_delay = delay })
            if context and context.requestRebuild then context.requestRebuild("ui") end
        end)
end

function YouTube:cycleSetting(instance, context, key)
    local settings = self:_settings()
    local patch = {}
    if key == "resolution_percent" then
        patch.resolution_percent = YouTube.cycle(RESOLUTIONS, settings.resolution_percent)
    elseif key == "fps" then
        patch.fps = YouTube.cycle(FRAME_RATES, settings.fps)
    elseif key == "max_duration" then
        patch.max_duration = YouTube.cycle(DURATIONS, settings.max_duration)
    elseif key == "max_height" then
        patch.max_height = YouTube.cycle({ 360, 480, 720 }, settings.max_height)
    elseif key == "dither" then
        patch.dither = settings.dither == "ffmpeg" and "bayer" or "ffmpeg"
    elseif key == "color_mode" then
        patch.color_mode = not settings.color_mode
    elseif key == "color_dither" then
        patch.color_dither = not settings.color_dither
    elseif key == "audio_video_delay" then
        patch.audio_video_delay = YouTube.cycle(AUDIO_VIDEO_DELAYS, settings.audio_video_delay)
    end
    self:_patchSettings(patch)
    if context and context.requestRebuild then context.requestRebuild("ui") end
end

function YouTube:confirmDelete(instance, context, entry)
    local dialog
    dialog = InputDialog:new{
        title = _("Delete this video from the Library?") .. "\n" .. tostring(entry.name or ""),
        input = "",
        input_hint = _("Delete removes only the converted files; the original source is kept."),
        buttons = {
            {
                { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
                {
                    text = _("Delete"),
                    callback = function()
                        UIManager:close(dialog)
                        local video_removed = os.remove(entry.path)
                        os.remove(entry.path:gsub("%.bwr$", ".wav"))
                        -- Remove legacy downloaded thumbnails as well; current
                        -- thumbnails are read directly from the first BWR frame.
                        os.remove(entry.path:gsub("%.bwr$", ".jpg"))
                        if not video_removed and fileExists(entry.path) then
                            self:_notify(instance, context, _("The video could not be deleted."))
                        else
                            self:scanLibrary(instance, context)
                            self:_notify(instance, context, _("Deleted") .. " " .. entry.name)
                        end
                        if context and context.requestRebuild then context.requestRebuild("ui") end
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
end

function YouTube:play(instance, context, path)
    local state = self:_state(instance)
    state.selected_path = path
    state.view = "home"
    state.watching = true
    local ok = self:toggleInline(instance, context, path)
    if not ok and context and context.requestRebuild then context.requestRebuild("ui") end
    return ok
end

function YouTube:stopInline(instance)
    local state = self:_state(instance)
    if state.inline_playing then
        self.player:stop()
        state.inline_playing = nil
    end
end

function YouTube:toggleInline(instance, context, path)
    local state = self:_state(instance)
    if not path then
        self:promptSearch(instance, context)
        return false
    end
    if state.inline_playing ~= path or not self.player.engine then
        self:stopInline(instance)
        local ok, err = self.player:load(instance, context, path)
        if not ok then
            self:_notify(instance, context, err or _("The video cannot be played."))
            return false
        end
        state.inline_playing = path
        local started, start_error = self.player.engine:play()
        if not started then
            self:stopInline(instance)
            self:_notify(instance, context, start_error or _("The video cannot be played."))
            return false
        end
    else
        self.player.engine:toggle()
    end
    state.selected_path = path
    state.view = "home"
    state.watching = true
    state.inline_rebuild = true
    if context and context.requestRebuild then context.requestRebuild("ui") end
    return true
end

function YouTube:openInlineFullscreen(instance, context, path)
    local state = self:_state(instance)
    if not state.inline_playing or state.inline_playing ~= path or not self.player.engine then
        if not self:toggleInline(instance, context, path) then return false end
    end
    state.playing = path
    state.fullscreen = true
    state.inline_rebuild = false
    state.return_to_inline = false
    state.view = "play"
    local entered = context and context.requestFullscreen and context.requestFullscreen(true)
    if not entered and context and context.requestRebuild then context.requestRebuild("ui") end
    return true
end

----------------------------------------------------------------
-- Pane
----------------------------------------------------------------

local function listPager(width, height, page, total_pages, on_prev, on_next)
    local gap = scale(6)
    local button_width = math.max(scale(40), math.floor((width - gap * 2) * 0.25))
    local label_width = width - button_width * 2 - gap * 2
    local widgets = {}
    widgets[1] = Pill:new{
        text = "‹", width = button_width, height = height,
        callback = on_prev,
        overlap_offset = { 0, 0 },
    }
    local label = TextWidget:new{
        text = string.format("%d / %d", page, total_pages),
        face = Font:getFace("smallinfofont", scale(10)),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        max_width = math.max(1, label_width),
        padding = 0,
    }
    widgets[2] = label
    label.overlap_offset = { button_width + gap, math.max(0, math.floor((height - label:getSize().h) / 2)) }
    widgets[3] = Pill:new{
        text = "›", width = button_width, height = height,
        callback = on_next,
        overlap_offset = { width - button_width, 0 },
    }
    return widgets
end

local function buildList(content, entries, page, per_page, offset_y, row_height, gap, on_tap, on_hold, offset_x, list_width, themed)
    local start_index = (page - 1) * per_page + 1
    for slot = 1, per_page do
        local entry = entries[start_index + slot - 1]
        if not entry then break end
        local subtitle = table.concat({
            entry.subtitle or "",
        }, " · ")
        local row = Row:new{
            title = entry.title,
            subtitle = subtitle,
            value = entry.value,
            width = list_width or content.dimen.w - 2 * scale(12),
            height = row_height,
            bordered = entry.highlight == true,
            themed = themed == true,
            background = themed and YT.bg or nil,
            video_card = entry.video_card == true,
            thumbnail_text = entry.thumbnail_text or "▶",
            thumbnail_path = entry.thumbnail_path,
            thumbnail_source_path = entry.path,
            callback = function() if on_tap then on_tap(entry) end end,
            hold_callback = on_hold and function() on_hold(entry) end or nil,
        }
        row.overlap_offset = { offset_x or scale(12), offset_y + (slot - 1) * (row_height + gap) }
        table.insert(content, row)
    end
end

-- Home is the YouTube feed (chips, card grid, bottom navigation). Tapping a
-- card opens the watch page: player on the left, details underneath and an
-- "Up next" rail on the right, as in the YouTube app.
function YouTube:_openLibrary(instance, context)
    local state = self:_state(instance)
    self:stopInline(instance)
    state.library = self:scanLibrary(instance, context)
    state.library_mode = true
    state.result_page = 1
    state.view = "results"
    context.requestRebuild("ui")
end

function YouTube:_goFeed(instance, context)
    local state = self:_state(instance)
    self:stopInline(instance)
    state.watching = false
    state.feed_page = 1
    context.requestRebuild("ui")
end

function YouTube:_buildFeedPane(instance, context, state)
    local width, height = context.dimen.w, context.dimen.h
    local margin, gap = scale(12), scale(12)
    local landscape = width > height * 1.2
    local header_h, chips_h, nav_h = scale(46), scale(40), scale(54)
    local content = ytPage(width, height)

    -- Header: logo and wordmark on the left, search and menu on the right.
    local logo = Logo:new{ height = scale(20) }
    logo.overlap_offset = { margin, math.floor((header_h - scale(20)) / 2) }
    table.insert(content, logo)
    local brand = TextWidget:new{
        text = "YouTube", face = Font:getFace("cfont", scale(17)), bold = true,
        fgcolor = YT.fg, padding = 0,
    }
    brand.overlap_offset = { margin + logo.logo_w + scale(8), math.floor((header_h - brand:getSize().h) / 2) }
    table.insert(content, brand)
    local button_h = scale(36)
    local button_y = math.floor((header_h - button_h) / 2)
    local search_w = scale(44)
    table.insert(content, Btn:new{
        text = "⌕", width = search_w, height = button_h, font_size = 18, bold = false,
        foreground = YT.fg,
        callback = function() self:promptSearch(instance, context) end,
        overlap_offset = { width - margin - search_w, button_y },
    })
    local tools = state.tools or YouTube.detectTools(self:_settings())
    local tools_w = tools.ready and scale(36) or scale(64)
    table.insert(content, Btn:new{
        text = tools.ready and "⋮" or _("Tools"),
        width = tools_w, height = button_h,
        font_size = tools.ready and 18 or 11, bold = not tools.ready,
        foreground = YT.fg,
        background = (not tools.ready) and YT.chip or nil,
        callback = function() state.view = "tools"; context.requestRebuild("ui") end,
        overlap_offset = { width - margin - search_w - gap - tools_w, button_y },
    })

    local library = state.library or self:scanLibrary(instance, context)

    -- Card grid geometry.
    local cols = landscape and 3 or 2
    local grid_top = header_h + chips_h + scale(6)
    local grid_bottom = height - nav_h - scale(4)
    local avail = grid_bottom - grid_top
    local card_w = math.floor((width - margin * 2 - gap * (cols - 1)) / cols)
    local text_h = scale(68)
    local thumb_h = math.floor(card_w * 9 / 16)
    if thumb_h + text_h > avail then thumb_h = math.max(scale(80), avail - text_h) end
    local card_h = thumb_h + text_h
    local rows = math.max(1, math.floor((avail + gap) / (card_h + gap)))
    local per_page = cols * rows
    local total_pages = math.max(1, math.ceil(#library / per_page))
    state.feed_page = clamp(state.feed_page or 1, 1, total_pages)

    -- Chip row (All / Library / Paste link / Search results) and pager.
    local chip_h = scale(30)
    local chip_y = header_h + math.floor((chips_h - chip_h) / 2)
    local chips = {
        { text = _("All"), active = true, callback = function()
            state.feed_page = 1; context.requestRebuild("ui")
        end },
        { text = _("Library"), callback = function() self:_openLibrary(instance, context) end },
        { text = _("Paste link"), callback = function() self:promptLink(instance, context) end },
    }
    if state.results and #state.results > 0 then
        chips[#chips + 1] = { text = _("Search results"), callback = function()
            state.library_mode = false; state.result_page = 1; state.view = "results"
            context.requestRebuild("ui")
        end }
    end
    local pager_w = total_pages > 1 and scale(150) or 0
    local chip_x = margin
    local chip_limit = width - margin - pager_w - (pager_w > 0 and gap or 0)
    for loop_index, chip in ipairs(chips) do
        local chip_w = chipWidth(chip.text)
        if chip_x + chip_w > chip_limit then break end
        table.insert(content, Btn:new{
            text = chip.text, width = chip_w, height = chip_h, font_size = 11,
            background = chip.active and YT.chip_on or YT.chip,
            foreground = chip.active and YT.chip_on_fg or YT.chip_fg,
            callback = chip.callback,
            overlap_offset = { chip_x, chip_y },
        })
        chip_x = chip_x + chip_w + scale(8)
    end
    if total_pages > 1 then
        local pager = ytPager(pager_w, chip_h, state.feed_page, total_pages,
            function()
                state.feed_page = math.max(1, state.feed_page - 1)
                context.requestRebuild("ui")
            end,
            function()
                state.feed_page = math.min(total_pages, state.feed_page + 1)
                context.requestRebuild("ui")
            end)
        for loop_index, widget in ipairs(pager) do
            widget.overlap_offset = {
                width - margin - pager_w + widget.overlap_offset[1],
                chip_y + widget.overlap_offset[2],
            }
            table.insert(content, widget)
        end
    end

    -- Cards.
    if #library == 0 then
        local title = TextWidget:new{
            text = _("No videos yet"), face = Font:getFace("cfont", scale(18)), bold = true,
            fgcolor = YT.fg, padding = 0,
        }
        local hint = TextWidget:new{
            text = _("Search YouTube or paste a link to start"),
            face = Font:getFace("smallinfofont", scale(11)), fgcolor = YT.sub,
            max_width = width - 2 * margin, padding = 0,
        }
        local middle = grid_top + math.floor(avail / 2)
        title.overlap_offset = { math.floor((width - title:getSize().w) / 2), middle - scale(54) }
        hint.overlap_offset = { math.floor((width - hint:getSize().w) / 2), middle - scale(24) }
        table.insert(content, title)
        table.insert(content, hint)
        local empty_w, empty_h = scale(130), scale(36)
        table.insert(content, Btn:new{
            text = "⌕  " .. _("Search"), width = empty_w, height = empty_h, font_size = 12,
            background = YT.chip_on, foreground = YT.chip_on_fg,
            callback = function() self:promptSearch(instance, context) end,
            overlap_offset = { math.floor(width / 2) - empty_w - scale(6), middle + scale(8) },
        })
        table.insert(content, Btn:new{
            text = "↗  " .. _("Paste link"), width = empty_w, height = empty_h, font_size = 12,
            background = YT.chip, foreground = YT.chip_fg,
            callback = function() self:promptLink(instance, context) end,
            overlap_offset = { math.floor(width / 2) + scale(6), middle + scale(8) },
        })
    else
        local first = (state.feed_page - 1) * per_page
        for slot = 1, per_page do
            local entry = library[first + slot]
            if not entry then break end
            local grid_col = (slot - 1) % cols
            local grid_row = math.floor((slot - 1) / cols)
            local card = Card:new{
                entry = entry, width = card_w, height = card_h, thumb_h = thumb_h,
                callback = function() self:play(instance, context, entry.path) end,
                hold_callback = function() self:confirmDelete(instance, context, entry) end,
            }
            card.overlap_offset = {
                margin + grid_col * (card_w + gap),
                grid_top + grid_row * (card_h + gap),
            }
            table.insert(content, card)
        end
    end

    -- Bottom navigation: Home, Shorts, +, Subscriptions, You.
    local footer = FrameContainer:new{
        width = width, height = nav_h, padding = 0, bordersize = 0,
        background = YT.bg, emptySizedWidget(width, nav_h),
    }
    footer.overlap_offset = { 0, height - nav_h }
    table.insert(content, footer)
    local line_h = math.max(1, scale(1))
    local line = FrameContainer:new{
        width = width, height = line_h, padding = 0, bordersize = 0,
        background = YT.line, emptySizedWidget(width, line_h),
    }
    line.overlap_offset = { 0, height - nav_h }
    table.insert(content, line)
    local tab_w = math.min(math.floor(width / 5), scale(120))
    local tabs_x = math.floor((width - tab_w * 5) / 2)
    local tabs = {
        { icon = "⌂", label = _("Home"), active = true, callback = function()
            self:_goFeed(instance, context)
        end },
        { icon = "▶", label = _("Shorts"), callback = function()
            self:_notify(instance, context, _("Shorts are not available in the offline DApp."))
        end },
        { icon = "+", plus = true, callback = function() self:promptLink(instance, context) end },
        { icon = "▣", label = _("Subscriptions"), callback = function()
            self:_notify(instance, context, _("Subscriptions are not available in the offline DApp."))
        end },
        { icon = "▤", label = _("You"), callback = function() self:_openLibrary(instance, context) end },
    }
    for tab_index, tab in ipairs(tabs) do
        table.insert(content, NavTab:new{
            icon = tab.icon, label = tab.label, active = tab.active, plus = tab.plus,
            callback = tab.callback, width = tab_w, height = nav_h - line_h,
            overlap_offset = { tabs_x + (tab_index - 1) * tab_w, height - nav_h + line_h },
        })
    end
    return content
end

function YouTube:_buildWatchPane(instance, context, state)
    local width, height = context.dimen.w, context.dimen.h
    local margin, gap = scale(12), scale(10)
    local landscape = width > height * 1.2
    local top_h = scale(40)
    local library = state.library or self:scanLibrary(instance, context)
    local selected_path = state.inline_playing or state.selected_path
    local selected
    for loop_index, entry in ipairs(library) do
        if entry.path == selected_path then selected = entry; break end
    end
    if not selected then
        -- The video was deleted or is gone: fall back to the feed.
        state.watching = false
        return self:_buildFeedPane(instance, context, state)
    end

    local rail_w = landscape and math.floor(width * 0.30) or (width - 2 * margin)
    local main_w = landscape and (width - rail_w - margin * 3) or (width - 2 * margin)
    local rail_x = margin * 2 + main_w
    local content = ytPage(width, height)

    -- Slim top bar with the back arrow.
    local back_w, back_h = scale(44), scale(34)
    table.insert(content, Btn:new{
        text = "‹", width = back_w, height = back_h, font_size = 22, bold = false,
        foreground = YT.fg,
        callback = function() self:_goFeed(instance, context) end,
        overlap_offset = { margin, math.floor((top_h - back_h) / 2) },
    })
    local brand = TextWidget:new{
        text = "YouTube", face = Font:getFace("cfont", scale(14)), bold = true,
        fgcolor = YT.fg, padding = 0,
    }
    brand.overlap_offset = { margin + back_w + scale(6), math.floor((top_h - brand:getSize().h) / 2) }
    table.insert(content, brand)

    -- Player.
    local hero_y = top_h
    local below_h = landscape and scale(215) or scale(330)
    local hero_h = math.max(scale(100), math.min(math.floor(main_w * 9 / 16), height - top_h - below_h))
    local inline_active = state.inline_playing == selected.path and self.player.engine
    local hero_canvas = Player.Canvas:new{ width = main_w, height = hero_h }
    if inline_active then
        self.player.engine:setCanvas(hero_canvas)
        self.player.engine:show(self.player.engine.position or 0)
    end
    local hero = MiniPlayer:new{
        canvas = hero_canvas, width = main_w, height = hero_h,
        callback = function() self:toggleInline(instance, context, selected.path) end,
    }
    hero.overlap_offset = { margin, hero_y }
    table.insert(content, hero)
    if not inline_active then
        local hero_icon = TextWidget:new{
            text = "▶", face = Font:getFace("cfont", scale(36)),
            fgcolor = Blitbuffer.COLOR_WHITE, padding = 0,
        }
        hero_icon.overlap_offset = {
            margin + math.floor((main_w - hero_icon:getSize().w) / 2),
            hero_y + math.floor((hero_h - hero_icon:getSize().h) / 2),
        }
        table.insert(content, hero_icon)
    end

    -- Title and meta line.
    local text_y = hero_y + hero_h + gap
    local title = TextWidget:new{
        text = fitText(selected.title, main_w, 16),
        face = Font:getFace("cfont", scale(16)), bold = true, fgcolor = YT.fg,
        max_width = main_w, padding = 0,
    }
    title.overlap_offset = { margin, text_y }
    table.insert(content, title)
    local meta_text = entryMeta(selected)
    if selected.value and selected.value ~= "" then meta_text = selected.value .. " · " .. meta_text end
    local meta = TextWidget:new{
        text = fitText(meta_text, main_w, 10),
        face = Font:getFace("smallinfofont", scale(10)), fgcolor = YT.sub,
        max_width = main_w, padding = 0,
    }
    meta.overlap_offset = { margin, text_y + scale(26) }
    table.insert(content, meta)

    -- Channel row: avatar, name, primary Play/Pause button.
    local row_y = text_y + scale(52)
    local avatar_d = scale(36)
    local avatar = Avatar:new{ letter = firstLetter(selected.title), diameter = avatar_d }
    avatar.overlap_offset = { margin, row_y }
    table.insert(content, avatar)
    local name_x = margin + avatar_d + scale(10)
    local name = TextWidget:new{
        text = "YouTube", face = Font:getFace("cfont", scale(14)), bold = true,
        fgcolor = YT.fg, padding = 0,
    }
    name.overlap_offset = { name_x, row_y }
    table.insert(content, name)
    local audio = TextWidget:new{
        text = selected.has_audio and _("With audio") or _("No audio"),
        face = Font:getFace("smallinfofont", scale(10)), fgcolor = YT.sub, padding = 0,
    }
    audio.overlap_offset = { name_x, row_y + name:getSize().h }
    table.insert(content, audio)
    local play_w, play_h = scale(112), scale(34)
    local playing = inline_active and not self.player.engine.paused
    table.insert(content, Btn:new{
        text = playing and ("Ⅱ  " .. _("Pause")) or ("▶  " .. _("Play")),
        width = play_w, height = play_h, font_size = 12,
        background = YT.chip_on, foreground = YT.chip_on_fg, radius = play_h,
        callback = function() self:toggleInline(instance, context, selected.path) end,
        overlap_offset = { margin + main_w - play_w, row_y + math.floor((avatar_d - play_h) / 2) },
    })

    -- Action chips (like Share / Download / Report in the app).
    local actions_y = row_y + avatar_d + gap
    local action_h = scale(32)
    local actions = {
        { text = "⛶  " .. _("Fullscreen"), callback = function()
            self:openInlineFullscreen(instance, context, selected.path)
        end },
        { text = "↗  " .. _("Share"), callback = function() self:promptLink(instance, context) end },
        { text = "⇩  " .. _("Download"), callback = function() self:promptSearch(instance, context) end },
        { text = _("Delete"), callback = function() self:confirmDelete(instance, context, selected) end },
    }
    local action_w = math.floor((main_w - gap * (#actions - 1)) / #actions)
    for action_index, action in ipairs(actions) do
        table.insert(content, Btn:new{
            text = action.text, width = action_w, height = action_h, font_size = 11,
            background = YT.chip, foreground = YT.chip_fg, radius = action_h,
            callback = action.callback,
            overlap_offset = { margin + (action_index - 1) * (action_w + gap), actions_y },
        })
    end

    -- Details box where the app shows the comments.
    local details_y = actions_y + action_h + gap
    local details_h = scale(46)
    local details = string.format("%s · %s · %s",
        _("Stored on this device"), humanSize(selected.size), selected.name or "")
    table.insert(content, Btn:new{
        text = details, width = main_w, height = details_h, font_size = 10, bold = false,
        align = "left", background = YT.chip, foreground = YT.chip_fg, radius = scale(12),
        overlap_offset = { margin, details_y },
    })

    -- Up next.
    local others = {}
    for loop_index, entry in ipairs(library) do
        if entry.path ~= selected.path then others[#others + 1] = entry end
    end
    if landscape then
        local rail_y = top_h
        local avail = height - rail_y - margin
        local text_h = scale(68)
        local thumb_h = math.floor(rail_w * 9 / 16)
        if thumb_h + text_h > avail then thumb_h = math.max(scale(80), avail - text_h) end
        local card_h = thumb_h + text_h
        local fit = math.max(1, math.floor((avail + gap) / (card_h + gap)))
        for rail_index = 1, math.min(#others, fit) do
            local entry = others[rail_index]
            local card = Card:new{
                entry = entry, width = rail_w, height = card_h, thumb_h = thumb_h,
                callback = function() self:play(instance, context, entry.path) end,
                hold_callback = function() self:confirmDelete(instance, context, entry) end,
            }
            card.overlap_offset = { rail_x, rail_y + (rail_index - 1) * (card_h + gap) }
            table.insert(content, card)
        end
    else
        local list_w = width - 2 * margin
        local row_h = math.max(scale(60), math.floor(list_w * 0.34 * 9 / 16) + scale(16))
        local rail_y = details_y + details_h + gap
        local list_top = rail_y + scale(28)
        local count = math.min(#others, math.floor((height - list_top - margin + gap) / (row_h + gap)))
        if count >= 1 then
            local rail_title = TextWidget:new{
                text = _("Up next"), face = Font:getFace("cfont", scale(15)), bold = true,
                fgcolor = YT.fg, padding = 0,
            }
            rail_title.overlap_offset = { margin, rail_y }
            table.insert(content, rail_title)
            local entries = {}
            for rail_index = 1, count do
                local entry = others[rail_index]
                entries[rail_index] = {
                    title = entry.title, subtitle = entryMeta(entry), value = "",
                    video_card = true, thumbnail_path = entry.thumbnail_path,
                    path = entry.path, result = entry,
                }
            end
            buildList(content, entries, 1, count, list_top, row_h, gap,
                function(entry) self:play(instance, context, entry.path) end,
                nil, margin, list_w, true)
        end
    end
    return content
end

function YouTube:_buildHomePane(instance, context, state)
    if state.watching then
        return self:_buildWatchPane(instance, context, state)
    end
    return self:_buildFeedPane(instance, context, state)
end

function YouTube:_buildSearchPane(instance, context, state)
    local width, height = context.dimen.w, context.dimen.h
    local margin = scale(12)
    local content = OverlapGroup:new{
        dimen = Geom:new{ w = width, h = height },
        allow_mirroring = false,
        FrameContainer:new{
            width = width, height = height, padding = 0, bordersize = 0,
            background = Blitbuffer.COLOR_WHITE,
            emptySizedWidget(width, height),
        },
    }
    local title = TextWidget:new{
        text = _("Searching YouTube"),
        face = Font:getFace("cfont", scale(17)),
        bold = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
        padding = 0,
    }
    title.overlap_offset = { margin, scale(16) }
    table.insert(content, title)
    local hint = TextWidget:new{
        text = state.note ~= "" and state.note or _("Please wait"),
        face = Font:getFace("smallinfofont", scale(11)),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        max_width = width - 2 * margin,
        padding = 0,
    }
    hint.overlap_offset = { margin, scale(46) }
    table.insert(content, hint)
    return content
end

function YouTube:_buildResultsPane(instance, context, state)
    local width, height = context.dimen.w, context.dimen.h
    local margin, gap = scale(12), scale(8)
    local content = ytPage(width, height)
    local results = state.library_mode and (state.library or {}) or (state.results or {})

    -- Top bar: back arrow and a search field showing the current query.
    local top_h = scale(48)
    local back_w, control_h = scale(44), scale(36)
    local control_y = math.floor((top_h - control_h) / 2)
    table.insert(content, Btn:new{
        text = "‹", width = back_w, height = control_h, font_size = 22, bold = false,
        foreground = YT.fg,
        callback = function()
            state.library_mode = false
            state.view = "home"
            context.requestRebuild("ui")
        end,
        overlap_offset = { margin, control_y },
    })
    local field_x = margin + back_w + scale(6)
    local field_text
    if state.library_mode then
        field_text = _("Library") .. string.format(" · %d video(s)", #results)
    else
        field_text = "⌕  " .. (state.results_query or "")
    end
    table.insert(content, Btn:new{
        text = field_text, width = width - field_x - margin, height = control_h,
        font_size = 12, bold = false, align = "left",
        background = YT.chip, foreground = YT.chip_fg, radius = control_h,
        callback = (not state.library_mode) and function() self:promptSearch(instance, context) end or nil,
        overlap_offset = { field_x, control_y },
    })

    local entries = {}
    for loop_index, result in ipairs(results) do
        local subtitle
        if state.library_mode then
            subtitle = entryMeta(result)
            if result.value and result.value ~= "" then subtitle = result.value .. " · " .. subtitle end
        else
            local parts = { result.uploader or _("Unknown channel") }
            if result.duration then parts[#parts + 1] = formatDuration(result.duration) end
            subtitle = table.concat(parts, " · ")
        end
        entries[#entries + 1] = {
            title = result.title,
            subtitle = subtitle,
            value = "",
            video_card = true,
            thumbnail_text = "▶",
            thumbnail_path = result.thumbnail_path,
            path = result.path,
            result = result,
        }
    end

    local list_w = width - 2 * margin
    local pager_height = scale(30)
    local footer_y = height - pager_height - scale(8)
    local top = top_h + scale(6)
    local row_height = clamp(
        math.floor(list_w * 0.34 * 9 / 16) + scale(16),
        scale(70),
        math.max(scale(70), math.floor((footer_y - top) / 2)))
    local per_page = math.max(1, math.floor((footer_y - top - scale(4) + gap) / (row_height + gap)))
    local total_pages = math.max(1, math.ceil(#entries / per_page))
    state.result_page = clamp(state.result_page or 1, 1, total_pages)
    buildList(content, entries, state.result_page, per_page, top, row_height, gap, function(entry)
        if state.library_mode then self:play(instance, context, entry.result.path)
        else self:startVideo(instance, context, entry.result) end
    end, state.library_mode and function(entry)
        self:confirmDelete(instance, context, entry.result)
    end or nil, margin, list_w, true)

    if total_pages > 1 then
        local pager_w = scale(200)
        local pager = ytPager(pager_w, pager_height, state.result_page, total_pages,
            function()
                state.result_page = math.max(1, state.result_page - 1)
                context.requestRebuild("ui")
            end,
            function()
                state.result_page = math.min(total_pages, state.result_page + 1)
                context.requestRebuild("ui")
            end)
        local pager_x = math.floor((width - pager_w) / 2)
        for loop_index, widget in ipairs(pager) do
            widget.overlap_offset = { pager_x + widget.overlap_offset[1], footer_y + widget.overlap_offset[2] }
            table.insert(content, widget)
        end
    end
    return content
end

function YouTube:_buildJobPane(instance, context, state)
    local width, height = context.dimen.w, context.dimen.h
    local margin = scale(12)
    local job = state.job
    local content = OverlapGroup:new{
        dimen = Geom:new{ w = width, h = height },
        allow_mirroring = false,
        FrameContainer:new{
            width = width, height = height, padding = 0, bordersize = 0,
            background = Blitbuffer.COLOR_WHITE,
            emptySizedWidget(width, height),
        },
    }
    local title = TextWidget:new{
        text = fitText(job and job.title or _("Conversion"), width - 2 * margin, 16),
        face = Font:getFace("cfont", scale(16)),
        bold = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
        max_width = width - 2 * margin,
        padding = 0,
    }
    title.overlap_offset = { margin, scale(14) }
    table.insert(content, title)

    local bar = ProgressBar:new{
        ratio = job and (job.percent or 0) / 100 or 0,
        width = width - 2 * margin,
        height = scale(18),
    }
    if job then job.progress_widget = bar end
    bar.overlap_offset = { margin, scale(48) }
    table.insert(content, bar)

    local stage = TextWidget:new{
        text = fitText(job and job.stage_message or "", width - 2 * margin, 11),
        face = Font:getFace("smallinfofont", scale(11)),
        fgcolor = Blitbuffer.COLOR_BLACK,
        max_width = width - 2 * margin,
        padding = 0,
    }
    if job then
        job.stage_widget = stage
        job.stage_widget_width = width - 2 * margin
    end
    stage.overlap_offset = { margin, scale(74) }
    table.insert(content, stage)

    if job and job.log_tail and job.log_tail ~= "" then
        local log = TextWidget:new{
            text = fitText(trim(job.log_tail:gsub("%s+", " ")), width - 2 * margin, 9),
            face = Font:getFace("smallinfofont", scale(9)),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            max_width = width - 2 * margin,
            padding = 0,
        }
        log.overlap_offset = { margin, scale(96) }
        table.insert(content, log)
    end

    local button_width = math.floor((width - 2 * margin - scale(6)) / 2)
    local cancel = Pill:new{
        text = (job and job.stage == "error") and _("Back") or _("Cancel"),
        width = button_width,
        height = scale(34),
        background = Blitbuffer.COLOR_GRAY_7,
        callback = function() self:cancelJob(instance, context) end,
        overlap_offset = { margin, height - scale(48) },
    }
    table.insert(content, cancel)

    local hint_text = (job and job.stage == "error")
        and _("Adjust the tools or settings and start again.")
        or _("AppDock stays responsive; you can leave this screen and the job keeps running.")
    local hint = TextWidget:new{
        text = hint_text,
        face = Font:getFace("smallinfofont", scale(9)),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        max_width = width - 2 * margin - button_width - scale(6),
        padding = 0,
    }
    hint.overlap_offset = { margin + button_width + scale(6), height - scale(44) }
    table.insert(content, hint)
    return content
end

function YouTube:_buildToolsPane(instance, context, state)
    local width, height = context.dimen.w, context.dimen.h
    local margin, gap = scale(12), scale(6)
    local settings = self:_settings()
    local tools = state.tools or YouTube.detectTools(settings)
    local content = OverlapGroup:new{
        dimen = Geom:new{ w = width, h = height },
        allow_mirroring = false,
        FrameContainer:new{
            width = width, height = height, padding = 0, bordersize = 0,
            background = Blitbuffer.COLOR_WHITE,
            emptySizedWidget(width, height),
        },
    }
    local back_width = scale(76)
    local back = Pill:new{
        text = "‹ " .. _("Back"),
        width = back_width,
        height = scale(30),
        background = Blitbuffer.COLOR_GRAY_8,
        callback = function()
            state.view = state.bootstrap and state.bootstrap.error and "setup" or "home"
            context.requestRebuild("ui")
        end,
        overlap_offset = { margin, scale(10) },
    }
    table.insert(content, back)
    local title = TextWidget:new{
        text = _("Video tools"),
        face = Font:getFace("cfont", scale(17)),
        bold = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
        padding = 0,
    }
    title.overlap_offset = { margin + back_width + scale(8), scale(14) }
    table.insert(content, title)

    local rows = {
        {
            title = "yt-dlp",
            subtitle = tools.ytdlp or _("Not found. Tap to enter the path."),
            value = tools.ytdlp and _("Found") or _("Missing"),
            action = function()
                self:editToolPath(instance, context, "ytdlp_path", _("yt-dlp path"),
                    _("Absolute path to the yt-dlp executable"))
            end,
        },
        {
            title = "ffmpeg",
            subtitle = tools.ffmpeg or _("Not found. Tap to enter the path."),
            value = tools.ffmpeg and _("Found") or _("Missing"),
            action = function()
                self:editToolPath(instance, context, "ffmpeg_path", _("ffmpeg path"),
                    _("Absolute path to the ffmpeg executable"))
            end,
        },
        {
            title = _("Output folder"),
            subtitle = self:_outputDirectory(),
            value = _("Edit"),
            action = function()
                self:editToolPath(instance, context, "output_dir", _("Output folder"),
                    _("Absolute folder for .bwr and .wav files"))
            end,
        },
        {
            title = _("Dithering"),
            subtitle = settings.dither == "ffmpeg"
                and _("ffmpeg converts to 1 bit (fast)")
                or _("AppDock Bayer matrix (matches the Snake player)"),
            value = settings.dither == "ffmpeg" and "ffmpeg" or "bayer",
            action = function() self:cycleSetting(instance, context, "dither") end,
        },
        {
            title = _("Color playback"),
            subtitle = settings.color_mode
                and _("Pure red, green, blue, black and white; older videos remain unchanged")
                or _("Optional five-color output for color E-Ink screens"),
            value = settings.color_mode and _("On") or _("Off"),
            action = function() self:cycleSetting(instance, context, "color_mode") end,
        },
        {
            title = _("Color dithering"),
            subtitle = _("Uses an 8x8 ordered pattern to mix the five exact palette colors"),
            value = settings.color_dither and _("On") or _("Off"),
            action = function() self:cycleSetting(instance, context, "color_dither") end,
        },
        {
            title = _("Maximum source quality"),
            subtitle = _("yt-dlp downloads at most this height"),
            value = string.format("%dp", settings.max_height),
            action = function() self:cycleSetting(instance, context, "max_height") end,
        },
        {
            title = _("Resolution"),
            subtitle = _("Frame size of the converted video"),
            value = YouTube.resolutionLabel(settings.resolution_percent),
            action = function() self:cycleSetting(instance, context, "resolution_percent") end,
        },
        {
            title = _("Frame rate"),
            subtitle = _("Lower rates refresh faster on E-Ink"),
            value = string.format("%g fps", settings.fps),
            action = function() self:cycleSetting(instance, context, "fps") end,
        },
        {
            title = _("Video start after audio"),
            subtitle = _("Positive value delays the video after audio starts"),
            value = string.format("%g s", settings.audio_video_delay or 0),
            action = function() self:editAudioVideoDelay(instance, context) end,
        },
        {
            title = _("Maximum length"),
            subtitle = _("Longer videos need more space and time"),
            value = YouTube.durationLabel(settings.max_duration),
            action = function() self:cycleSetting(instance, context, "max_duration") end,
        },
    }

    local row_height = scale(44)
    local top = scale(48)
    local pager_height = scale(30)
    local note_height = scale(52) + pager_height
    local footer_y = height - pager_height - scale(4)
    local available = math.max(row_height, footer_y - scale(4) - top - gap)
    local per_page = math.max(1, math.floor(available / (row_height + gap)))
    local total_pages = math.max(1, math.ceil(#rows / per_page))
    state.tools_page = clamp(state.tools_page or 1, 1, total_pages)
    local first_row = (state.tools_page - 1) * per_page
    for slot = 1, per_page do
        local row = rows[first_row + slot]
        if not row then break end
        local widget = Row:new{
            title = row.title,
            subtitle = row.subtitle,
            value = row.value,
            width = width - 2 * margin,
            height = row_height,
            callback = row.action,
        }
        widget.overlap_offset = { margin, top + (slot - 1) * (row_height + gap) }
        table.insert(content, widget)
    end

    if total_pages > 1 then
        local pager = listPager(width - 2 * margin, pager_height, state.tools_page, total_pages,
            function()
                state.tools_page = math.max(1, state.tools_page - 1)
                context.requestRebuild("ui")
            end,
            function()
                state.tools_page = math.min(total_pages, state.tools_page + 1)
                context.requestRebuild("ui")
            end)
        for loop_index, widget in ipairs(pager) do
            widget.overlap_offset = { margin + widget.overlap_offset[1], footer_y + widget.overlap_offset[2] }
            table.insert(content, widget)
        end
    end

    local detect = Pill:new{
        text = _("Detect tools again"),
        width = scale(150),
        height = scale(32),
        background = Blitbuffer.COLOR_GRAY_8,
        callback = function() self:redetect(instance, context) end,
        overlap_offset = { margin, height - note_height },
    }
    table.insert(content, detect)

    local hint = TextWidget:new{
        text = _("If setup cannot fetch the tools, add yt-dlp and ffmpeg to the AppDock tools folder or enter their full paths. AppDock does not bundle them."),
        face = Font:getFace("smallinfofont", scale(9)),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        max_width = width - 2 * margin,
        padding = 0,
    }
    hint.overlap_offset = { margin, height - note_height + scale(36) }
    table.insert(content, hint)
    return content
end

function YouTube:_buildSetupPane(instance, context, state)
    local width, height = context.dimen.w, context.dimen.h
    local margin = scale(18)
    local bootstrap = state.bootstrap or {}
    local content = OverlapGroup:new{
        dimen = Geom:new{ w = width, h = height },
        allow_mirroring = false,
        FrameContainer:new{
            width = width, height = height, padding = 0, bordersize = 0,
            background = Blitbuffer.COLOR_WHITE,
            emptySizedWidget(width, height),
        },
    }
    local title = TextWidget:new{
        text = bootstrap.error and _("YouTube setup needs attention") or _("Preparing YouTube"),
        face = Font:getFace("cfont", scale(17)),
        bold = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
        padding = 0,
    }
    title.overlap_offset = { margin, scale(20) }
    table.insert(content, title)
    local status_text = bootstrap.status or _("Checking for yt-dlp and ffmpeg…")
    local status = TextWidget:new{
        text = fitText(status_text, width - 2 * margin, 11),
        face = Font:getFace("smallinfofont", scale(11)),
        fgcolor = Blitbuffer.COLOR_BLACK,
        max_width = width - 2 * margin,
        padding = 0,
    }
    status.overlap_offset = { margin, scale(58) }
    table.insert(content, status)

    if not bootstrap.error then
        local progress = ProgressBar:new{
            width = width - 2 * margin,
            height = scale(18),
            indeterminate = true,
            position = progressBarPulsePosition(bootstrap.progress_phase or 0),
        }
        bootstrap.progress_widget = progress
        progress.overlap_offset = { margin, scale(88) }
        table.insert(content, progress)
        local explanation = TextWidget:new{
            text = _("The first setup downloads the official yt-dlp release and a static FFmpeg build into KOReader's data folder. You can leave this screen open while the tools are prepared."),
            face = Font:getFace("smallinfofont", scale(9)),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            max_width = width - 2 * margin,
            padding = 0,
        }
        explanation.overlap_offset = { margin, scale(120) }
        table.insert(content, explanation)
    else
        local error = TextWidget:new{
            text = fitText(bootstrap.error, width - 2 * margin, 9),
            face = Font:getFace("smallinfofont", scale(9)),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            max_width = width - 2 * margin,
            padding = 0,
        }
        error.overlap_offset = { margin, scale(90) }
        table.insert(content, error)
        local retry = Pill:new{
            text = _("Retry setup"),
            width = scale(142),
            height = scale(34),
            background = Blitbuffer.COLOR_GRAY_8,
            callback = function()
                state.bootstrap = nil
                state.bootstrap_attempted = false
                self:_startToolBootstrap(instance, context)
            end,
        }
        retry.overlap_offset = { margin, scale(130) }
        table.insert(content, retry)
    end
    local output_label = TextWidget:new{
        text = _("Live shell output"),
        face = Font:getFace("smallinfofont", scale(9)),
        bold = true,
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        padding = 0,
    }
    output_label.overlap_offset = { margin, bootstrap.error and scale(174) or scale(158) }
    table.insert(content, output_label)
    local output_widget = TextBoxWidget:new{
        bgcolor = Blitbuffer.COLOR_WHITE,
        text = bootstrap.live_output or YouTube.liveLogPreview(""),
        face = Font:getFace("smallinfofont", scale(9)),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        width = width - 2 * margin,
        alignment = "left",
    }
    bootstrap.live_widget = output_widget
    output_widget.overlap_offset = { margin, bootstrap.error and scale(192) or scale(176) }
    table.insert(content, output_widget)
    local tools_button = Pill:new{
        text = _("Tool settings"),
        width = scale(142),
        height = scale(34),
        background = Blitbuffer.COLOR_GRAY_6,
        callback = function()
            state.view = "tools"
            if context.requestRebuild then context.requestRebuild("ui") end
        end,
    }
    tools_button.overlap_offset = { margin, height - scale(48) }
    table.insert(content, tools_button)
    return content
end

function YouTube:buildPane(instance, context)
    local state = self:_state(instance)
    if state.view == "home" and not state.tools.ready and not state.bootstrap_attempted
        and not (self.appdock and self.appdock.disableToolBootstrap) then
        self:_startToolBootstrap(instance, context, true)
    end
    local pane
    if state.view == "play" and state.playing then
        pane = self.player:buildPane(instance, context, {
            fullscreen = state.fullscreen == true,
            keep_engine_on_deactivate = function() return state.return_to_inline == true end,
            on_back = function()
                local path = state.playing
                local keep_inline = path and state.inline_playing == path
                state.view = "home"
                state.playing = nil
                state.fullscreen = false
                state.return_to_inline = keep_inline == true
                if keep_inline then
                    state.inline_playing = path
                else
                    state.inline_playing = nil
                    self.player:stop()
                end
                local exited = context.requestFullscreen and context.requestFullscreen(false)
                if not exited and context.requestRebuild then context.requestRebuild("ui") end
            end,
        })
        local previous = pane.onDeactivate
        pane.onDeactivate = function()
            if previous then previous() end
            state.view = "home"
            state.playing = nil
            if state.return_to_inline then
                state.return_to_inline = false
            else
                state.fullscreen = false
                state.inline_playing = nil
            end
        end
        return pane
    end

    local content
    if state.view == "results" then
        content = self:_buildResultsPane(instance, context, state)
    elseif state.view == "search" then
        content = self:_buildSearchPane(instance, context, state)
    elseif state.view == "job" and state.job then
        content = self:_buildJobPane(instance, context, state)
    elseif state.view == "setup" then
        content = self:_buildSetupPane(instance, context, state)
    elseif state.view == "tools" then
        content = self:_buildToolsPane(instance, context, state)
    else
        state.view = "home"
        content = self:_buildHomePane(instance, context, state)
    end

    pane = WidgetContainer:new{ dimen = Geom:new{ w = context.dimen.w, h = context.dimen.h } }
    pane[1] = content
    pane.onDeactivate = function()
        -- `play()` loads the engine before requesting the host rebuild. The
        -- outgoing library pane is deactivated during that rebuild, so only
        -- stop here when navigation is not transitioning into the player or
        -- refreshing the inline mini-player.
        if state.inline_rebuild then
            state.inline_rebuild = false
        elseif state.view ~= "play" then
            self.player:stop()
            state.inline_playing = nil
        end
    end
    return pane
end

YouTube._test = {
    buildFilter = YouTube.buildFilter,
    bootstrapPlan = YouTube.bootstrapPlan,
    buildBootstrapCommand = YouTube.buildBootstrapCommand,
    parseGlibcVersion = YouTube.parseGlibcVersion,
    liveLogPreview = YouTube.liveLogPreview,
    classifyInput = YouTube.classifyInput,
    parseSearchOutput = YouTube.parseSearchOutput,
    parseProgress = YouTube.parseProgress,
    parseVideoId = YouTube.parseVideoId,
    buildDownloadCommand = YouTube.buildDownloadCommand,
    describeDownloadFailure = YouTube.describeDownloadFailure,
    setProgressBarPercent = setProgressBarPercent,
    setProgressBarPulse = setProgressBarPulse,
    slugify = YouTube.slugify,
    cycle = YouTube.cycle,
    durationLabel = YouTube.durationLabel,
    frameSize = YouTube.frameSize,
    normalizeSettings = normalizeSettings,
    availableOutputPath = availableOutputPath,
}

return YouTube
