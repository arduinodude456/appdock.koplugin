-- AppDock YouTube DApp test.
--
-- Covers the pure helpers, tool discovery and the complete conversion
-- pipeline. The conversion part runs a real ffmpeg against a locally generated
-- clip, so the compressed BWR2 file it produces is decoded again and inspected. When
-- ffmpeg is unavailable the conversion section is skipped instead of failing.

local plugin_dir = os.getenv("APPDOCK_PLUGIN_DIR") or "/home/ubuntu/appdock.koplugin/appdock.koplugin/"
local data_dir = "/tmp/appdock_youtube_test"
local ffi = require("ffi")
local lfs = require("lfs")

os.execute("rm -rf " .. data_dir)
assert(lfs.mkdir(data_dir), "The test data directory must be creatable")

----------------------------------------------------------------
-- KOReader stubs
----------------------------------------------------------------

local function baseClass(prototype)
    prototype = prototype or {}
    prototype.__index = prototype
    function prototype:extend(child)
        child = child or {}
        child.__index = child
        setmetatable(child, { __index = self })
        return child
    end
    function prototype:new(args)
        local instance = setmetatable(args or {}, self)
        if instance._init then instance:_init() end
        if instance.init then instance:init() end
        return instance
    end
    function prototype:getSize()
        if self.dimen then return self.dimen end
        return { w = self.width or 0, h = self.height or 0 }
    end
    function prototype:clear() while table.remove(self) do end end
    return prototype
end

local Widget = baseClass({})
local WidgetContainer = Widget:extend({})
local InputContainer = WidgetContainer:extend({})
function InputContainer:paintTo() end
local FrameContainer = WidgetContainer:extend({})
local CenterContainer = WidgetContainer:extend({})
local OverlapGroup = WidgetContainer:extend({})
local HorizontalSpan = Widget:extend({})

local TextWidget = Widget:extend({})
function TextWidget:getSize()
    local size = self.face and self.face.size or 12
    return { w = #(self.text or "") * math.floor(size * .5), h = size }
end
function TextWidget:setText(text) self.text = text end

package.preload["gettext"] = function() return function(text) return text end end
package.preload["logger"] = function()
    return { info = function() end, warn = function() end, err = function() end, dbg = function() end }
end
package.preload["datastorage"] = function()
    return { getDataDir = function() return data_dir end }
end
package.preload["device"] = function()
    return {
        screen = {
            getSize = function() return { w = 600, h = 800 } end,
            getWidth = function() return 600 end,
            getHeight = function() return 800 end,
            scaleBySize = function(_, value) return value end,
        },
        hasKeys = function() return false end,
    }
end
package.preload["ffi/blitbuffer"] = function()
    return {
        TYPE_BB8 = 1,
        COLOR_WHITE = "white", COLOR_BLACK = "black",
        COLOR_DARK_GRAY = "dark", COLOR_LIGHT_GRAY = "light", COLOR_GRAY = "gray",
        COLOR_GRAY_7 = "g7", COLOR_GRAY_8 = "g8",
        new = function(width, height)
            return {
                width = width, height = height,
                data = ffi.new("uint8_t[?]", width * height),
                getWidth = function(self) return self.width end,
                getHeight = function(self) return self.height end,
                free = function() end,
            }
        end,
    }
end
package.preload["ui/font"] = function()
    return { getFace = function(_, name, size) return { name = name, size = size or 12 } end }
end
package.preload["ui/geometry"] = function() return { new = function(_, args) return args end } end
package.preload["ui/gesturerange"] = function() return { new = function(_, args) return args end } end
package.preload["ui/widget/widget"] = function() return Widget end
package.preload["ui/widget/container/widgetcontainer"] = function() return WidgetContainer end
package.preload["ui/widget/container/inputcontainer"] = function() return InputContainer end
package.preload["ui/widget/container/centercontainer"] = function() return CenterContainer end
package.preload["ui/widget/container/framecontainer"] = function() return FrameContainer end
package.preload["ui/widget/overlapgroup"] = function() return OverlapGroup end
package.preload["ui/widget/horizontalspan"] = function() return HorizontalSpan end
package.preload["ui/widget/textwidget"] = function() return TextWidget end
package.preload["ui/widget/textboxwidget"] = function() return TextWidget end
package.preload["ui/widget/infomessage"] = function() return WidgetContainer end
package.preload["ui/widget/inputdialog"] = function() return WidgetContainer end
package.preload["appdock_keyboard"] = function() return WidgetContainer end
package.preload["appdock_logo"] = function()
    local Logo = Widget:extend({})
    function Logo:init() self.dimen = { w = self.size or 0, h = self.size or 0 } end
    return Logo
end
package.preload["libs/libkoreader-lfs"] = function() return lfs end

local scheduled, scheduled_delays, schedule_counts = {}, {}, {}
local ui_log = { dirties = 0, shows = 0 }
package.preload["ui/uimanager"] = function()
    return {
        scheduleIn = function(_, delay, callback)
            table.insert(scheduled, callback)
            scheduled_delays[callback] = delay
            schedule_counts[callback] = (schedule_counts[callback] or 0) + 1
        end,
        unschedule = function(_, callback)
            for index, entry in ipairs(scheduled) do
                if entry == callback then table.remove(scheduled, index); break end
            end
        end,
        nextTick = function(_, callback) table.insert(scheduled, callback) end,
        setDirty = function() ui_log.dirties = ui_log.dirties + 1 end,
        widgetRepaint = function() end,
        forceRePaint = function() end,
        yieldToEPDC = function() end,
        show = function() ui_log.shows = ui_log.shows + 1 end,
        close = function() ui_log.shows = math.max(0, ui_log.shows - 1) end,
    }
end

local BWR = dofile(plugin_dir .. "appdock_bwr.lua")
local Player = dofile(plugin_dir .. "appdock_player.lua")
local YouTube = dofile(plugin_dir .. "appdock_youtube.lua")

----------------------------------------------------------------
-- Pure helpers
----------------------------------------------------------------

local helpers = YouTube._test

assert(helpers.parseVideoId("https://www.youtube.com/watch?v=dQw4w9WgXcQ") == "dQw4w9WgXcQ", "watch links must resolve to a video id")
assert(helpers.parseVideoId("https://youtu.be/dQw4w9WgXcQ?t=42") == "dQw4w9WgXcQ", "short links must resolve to a video id")
assert(helpers.parseVideoId("https://www.youtube.com/shorts/abcdefghijk") == "abcdefghijk", "shorts links must resolve to a video id")
assert(helpers.parseVideoId("https://www.youtube.com/live/abcdefghijk") == "abcdefghijk", "live links must resolve to a video id")
assert(helpers.parseVideoId("https://www.youtube.com/embed/abcdefghijk") == "abcdefghijk", "embed links must resolve to a video id")
assert(helpers.parseVideoId("https://example.org/watch?v=abcdefghijk") == "abcdefghijk", "a v parameter must be accepted regardless of host")
assert(helpers.parseVideoId("no link here") == nil, "plain text must not resolve to a video id")

assert(helpers.classifyInput("https://youtu.be/abcdefghijk") == "video", "A YouTube link must be treated as a video")
assert(helpers.classifyInput("https://example.org/page") == "unsupported", "A foreign link must be reported as unsupported")
assert(helpers.classifyInput("rick astley") == "search", "Plain text must become a search")
assert(helpers.classifyInput("   ") == nil, "Empty input must be ignored")

assert(helpers.slugify("Rick Astley - Never Gonna Give You Up (Official Video)") == "Rick_Astley_-_Never_Gonna_Give_You_Up_Official_Video",
    "Titles must become shell safe file names")
assert(helpers.slugify("Rock & Roll") == "Rock_and_Roll", "Ampersands must become readable words")
assert(helpers.slugify("Ärger & Lärm: Teil 1/2") == "Ärger_and_Lärm_Teil_1_2",
    "Letters beyond ASCII must survive so German titles stay readable")
assert(helpers.slugify("!!!") == "video", "A title without usable characters must fall back to a default")
assert(#helpers.slugify(string.rep("x", 200)) <= 58, "Slugs must stay bounded")
assert(helpers.slugify(string.rep("ä", 40)):sub(-1) ~= "\196" or #helpers.slugify(string.rep("ä", 40)) % 2 == 0,
    "A truncated slug must not end inside a UTF-8 sequence")

local results = helpers.parseSearchOutput("abc12345678\tFirst video\t212\tChannel One\n"
    .. "xyz98765432\tSecond video\tNA\tChannel Two\n"
    .. "broken line without tabs\n"
    .. "\tMissing id\t10\tChannel Three\n")
assert(#results == 2, "Only well formed search rows must survive parsing")
assert(results[1].id == "abc12345678" and results[1].duration == 212 and results[1].uploader == "Channel One",
    "Search rows must keep id, duration and channel")
assert(results[1].url == "https://www.youtube.com/watch?v=abc12345678", "Search rows must expose a watch url")
assert(results[2].duration == nil, "A missing duration must stay empty instead of becoming zero")

assert(helpers.parseProgress("[download]   0.0% of 10.00MiB at 1.00MiB/s ETA 00:10\n"
    .. "[download]  42.5% of 10.00MiB at 1.00MiB/s ETA 00:05\n"
    .. "[download] 100.0% of 10.00MiB in 00:09\n") == 100, "The last download percentage must win")
assert(helpers.parseProgress("no progress here") == nil, "A log without progress must report nothing")
local download_command = helpers.buildDownloadCommand(
    "/tools/yt-dlp", "/tools/ffmpeg", "/tmp/source.media", "https://www.youtube.com/watch?v=abc12345678", 480)
assert(download_command:find("%-%-extractor%-args 'youtube:player_client=android'", 1)
    and download_command:find("%-%-merge%-output%-format mp4", 1),
    "Video downloads must use yt-dlp's Android client to avoid browser-client streaming failures")
assert(helpers.describeDownloadFailure("ERROR: Sign in to confirm you're not a bot")
    :find("guest session", 1, true), "Bot challenges must explain why a public-video download cannot continue")
assert(helpers.describeDownloadFailure("ERROR: unable to download video data: HTTP Error 403: Forbidden")
    :find("403", 1, true), "HTTP 403 failures must be named explicitly")
local progress_widget = { ratio = 0 }
assert(helpers.setProgressBarPercent(progress_widget, 42.5) and progress_widget.ratio == 0.425,
    "A video tick must be able to update the already-built progress widget with its latest percentage")
helpers.setProgressBarPercent(progress_widget, 140)
assert(progress_widget.ratio == 1, "A progress bar must clamp completed progress to its full width")
local pulse_widget = { position = 0 }
helpers.setProgressBarPulse(pulse_widget, 2)
assert(pulse_widget.position == 0.5, "The setup progress pulse must move across its bar")
helpers.setProgressBarPulse(pulse_widget, 6)
assert(pulse_widget.position == 0.5, "The setup progress pulse must move back instead of sticking at the edge")
assert(helpers.liveLogPreview("\27[32mfirst line\27[0m\rprogress 1%\rprogress 2%\nsecond\nthird\nfourth\nfifth\nsixth")
    == "second\nthird\nfourth\nfifth\nsixth",
    "The live shell preview must remove terminal colors and keep only the latest five lines")
assert(helpers.liveLogPreview(string.rep("x", 200)) == string.rep("x", 200),
    "The live shell preview must preserve long error lines for the wrapping text box")

local filter = helpers.buildFilter(632, 840, 12, false)
assert(filter:find("fps=12", 1, true) and filter:find("scale=632:840", 1, true), "The filter must carry rate and size")
assert(filter:find("pad=632:840", 1, true) and filter:find("color=white", 1, true), "The filter must letterbox on white")
assert(not filter:find("monow", 1, true), "The Bayer path must not ask ffmpeg for 1-bit output")
assert(helpers.buildFilter(632, 840, 12, true):find("format=monow", 1, true), "The ffmpeg path must request monow output")

local frame_width, frame_height = helpers.frameSize(100)
assert(frame_width == 600 and frame_height == 800, "The full resolution must follow the device screen")
assert(frame_width % 8 == 0, "A frame width must be divisible by 8")
local half_width, half_height = helpers.frameSize(50)
assert(half_width == 296 and half_height == 400, "Half resolution must be half of the screen, rounded to a byte")

assert(helpers.cycle({ 60, 180, 600, 0 }, 600) == 0, "Cycling must wrap around")
assert(helpers.cycle({ 60, 180, 600, 0 }, 42) == 60, "An unknown value must fall back to the first entry")
assert(helpers.durationLabel(0) == "Full length", "Zero must mean full length")
assert(helpers.durationLabel(180) == "3 min", "Whole minutes must read as minutes")

----------------------------------------------------------------
-- Settings plumbing
----------------------------------------------------------------

local stored = { output_dir = data_dir .. "/videos" }
local appdock = {
    disableToolBootstrap = true,
    getYouTubeSettings = function() return stored end,
    setYouTubeSettings = function(_, patch)
        for key, value in pairs(patch) do stored[key] = value end
        return true
    end,
    notify = function() return true end,
}
local youtube = YouTube:new(appdock)
local instance = {}
local rebuild_calls = 0
local last_rebuild_type
local context = {
    dimen = { w = 600, h = 748 },
    requestRefresh = function() end,
    requestRebuild = function(refresh_type)
        rebuild_calls = rebuild_calls + 1
        last_rebuild_type = refresh_type
    end,
}
local state = youtube:_state(instance)
assert(state.view == "home", "A new instance must start on the home view")
assert(type(state.tools) == "table", "Tool detection must always produce a result table")

local settings = youtube:_settings()
assert(settings.fps == 12 and settings.dither == "ffmpeg" and settings.resolution_percent == 100,
    "Defaults must match the documented values")
youtube:cycleSetting(instance, context, "fps")
assert(youtube:_settings().fps == 15, "Cycling the frame rate must move to the next step")
youtube:cycleSetting(instance, context, "dither")
assert(youtube:_settings().dither == "bayer", "Cycling the dither mode must switch to Bayer")
youtube:cycleSetting(instance, context, "dither")
assert(youtube:_settings().dither == "ffmpeg", "Cycling the dither mode must return to fast ffmpeg")

local detached_dir = data_dir .. "/detached-test"
assert(lfs.mkdir(detached_dir), "The detached-process test directory must be creatable")
local detached = assert(youtube:_startDetached("sleep 1; printf done", detached_dir, "probe"))
assert(youtube:_pollDetached(detached) == nil,
    "Starting a slow background command must return before its exit marker is written")
local detached_code, detached_log
local detached_deadline = os.time() + 10
repeat
    os.execute("sleep 0.1")
    detached_code, detached_log = youtube:_pollDetached(detached)
until detached_code ~= nil or os.time() >= detached_deadline
assert(detached_code == 0 and detached_log:find("done", 1, true),
    "The detached command must report its exit status and captured output")
detached = assert(youtube:_startDetached(
    "set -eu\nprintf 'diagnostic-line\\n' >&2\nexit 23", detached_dir, "failure"))
detached_deadline = os.time() + 10
repeat
    os.execute("sleep 0.1")
    detached_code, detached_log = youtube:_pollDetached(detached)
until detached_code ~= nil or os.time() >= detached_deadline
assert(detached_code == 23 and detached_log:find("diagnostic-line", 1, true),
    "A failing set -e command must still write its exit marker and preserve its diagnostic log")
os.execute("rm -rf " .. detached_dir)

local bootstrap = helpers.bootstrapPlan
local detected_glibc = helpers.parseGlibcVersion("", "ldd (GNU libc) 2.28")
assert(detected_glibc and detected_glibc.major == 2 and detected_glibc.minor == 28,
    "The platform detector must recover glibc versions from ldd when getconf is unavailable")
local detected_from_libc = helpers.parseGlibcVersion("", "GNU C Library (GNU libc) stable release version 2.28")
assert(detected_from_libc and detected_from_libc.major == 2 and detected_from_libc.minor == 28,
    "The platform detector must recognize the glibc version banner as a final fallback")
assert(helpers.parseGlibcVersion("", "musl libc (armhf) 1.2.5") == nil,
    "A musl version must not be misclassified as glibc")
local x64_plan = bootstrap{ arch = "x86_64" }
assert(x64_plan.ytdlp_asset == "yt-dlp_linux" and x64_plan.ffmpeg_arch == "amd64",
    "x86_64 should map to the official Linux yt-dlp and static FFmpeg assets")
local arm64_musl = bootstrap{ arch = "aarch64", musl = true }
assert(arm64_musl.ytdlp_asset == "yt-dlp_musllinux_aarch64" and arm64_musl.ffmpeg_arch == "arm64",
    "aarch64 musl should select the upstream musl yt-dlp build")
local armv7_plan = bootstrap{ arch = "armv7l", glibc = { major = 2, minor = 31 } }
assert(armv7_plan.ytdlp_zip and armv7_plan.ffmpeg_arch == "armhf",
    "ARMv7 should select the upstream standalone archive and armhf FFmpeg")
local armv7_legacy_plan = bootstrap{ arch = "armv7l", glibc = { major = 2, minor = 28 } }
assert(armv7_legacy_plan.ytdlp_python and armv7_legacy_plan.ytdlp_asset == "yt-dlp"
    and armv7_legacy_plan.python_sha256 == "a29499df42ae58d47e9080cae5500ba6aa5f1d7ec93407831ea565e40b117175",
    "ARMv7 with glibc 2.17 through 2.30 must select the checksummed portable Python path")
local armv7_musl_plan = bootstrap{ arch = "armv7l", glibc = { major = 2, minor = 16 } }
assert(armv7_musl_plan.ytdlp_python and armv7_musl_plan.python_musl
    and armv7_musl_plan.python_asset == "appdock-youtube-armhf-musl-python-3.12.15.tar.gz"
    and armv7_musl_plan.python_sha256 == "5348e11472e5ca6c07d7b0ec75a2f1df1d181be7eb52d9e3cafb43267b1f916c"
    and armv7_musl_plan.python_url:find("releases/download/v7.8.22/", 1, true),
    "ARMv7 below glibc 2.17 must use the checksummed isolated musl runtime asset")
local armv7_unknown_libc = bootstrap{ arch = "armv7l" }
assert(armv7_unknown_libc.ytdlp_python and armv7_unknown_libc.python_musl,
    "ARMv7 with an unknown libc version must use the isolated musl runtime, not fail on glibc detection")
local armv7_old_musl = bootstrap{ arch = "armv7l", musl = true, musl_version = { major = 1, minor = 1 } }
assert(armv7_old_musl.ytdlp_python and armv7_old_musl.python_musl,
    "ARMv7 musl devices must use the bundled musl Python runtime regardless of the system musl version")
assert(not bootstrap{ arch = "x86_64", android = true }, "Android must not receive Linux/glibc binaries")
assert(not bootstrap{ arch = "x86_64", glibc = { major = 2, minor = 16 } },
    "x86_64 with old glibc must be rejected before download")
assert(not bootstrap{ arch = "aarch64", musl = true, musl_version = { major = 1, minor = 1 } },
    "aarch64 with old musl must be rejected before download")
local script = helpers.buildBootstrapCommand(
    data_dir .. "/appdock/tools", data_dir .. "/setup-work", x64_plan, true, true)
assert(script:find("SHA2%-256SUMS") and script:find("sha256sum") and script:find("md5sum"),
    "The installer must verify upstream checksums")
assert(script:find("Downloading the yt-dlp SHA-256 manifest", 1, true)
    and script:find("Calculating yt-dlp SHA-256", 1, true),
    "The setup status must distinguish fetching the checksum manifest from hashing the binary")
assert(script:find("Starting yt-dlp compatibility check (up to 2 minutes)", 1, true)
    and script:find("yt-dlp compatibility check timed out after 120 seconds", 1, true),
    "A stuck yt-dlp version check must be bounded and report a clear timeout")
assert(script:find("set_status", 1, true) and script:find("[setup] %s", 1, true)
    and script:find("-# -o", 1, true) and script:find("still running", 1, true),
    "Bootstrap output must include stage changes, visible download progress, and compatibility-check heartbeats")
assert(script:find("yt%-dlp_linux") and script:find("ffmpeg%-release%-amd64%-static"),
    "The generated installer must use the selected upstream assets")
assert(script:find("%$tools/yt%-dlp") and script:find("%$tools/ffmpeg"),
    "The installer must put tools in KOReader's data folder")
assert(script:find("ffmpeg%-GPLv3%.txt"), "The FFmpeg distribution license should be preserved")
local bootstrap_script_path = data_dir .. "/bootstrap-test.sh"
local bootstrap_script_file = assert(io.open(bootstrap_script_path, "wb"))
bootstrap_script_file:write(script)
bootstrap_script_file:close()
assert(os.execute("sh -n " .. bootstrap_script_path) == 0, "The generated installer script must be valid POSIX shell")
os.remove(bootstrap_script_path)
local armv7_script = helpers.buildBootstrapCommand(
    data_dir .. "/appdock/tools", data_dir .. "/setup-armv7", armv7_plan, true, false)
assert(armv7_script:find('unzip -q "$tmp/yt-dlp.pkg" -d "$tmp/yt-dlp-runtime"', 1, true),
    "ARMv7 setup must extract the complete zip archive, including its internal runtime files")
assert(armv7_script:find('exec "$d/yt-dlp-runtime/yt-dlp_linux_armv7l" "$@"', 1, true),
    "ARMv7 setup must install a wrapper that keeps yt-dlp beside its _internal runtime")
local armv7_script_path = data_dir .. "/bootstrap-armv7-test.sh"
local armv7_script_file = assert(io.open(armv7_script_path, "wb"))
armv7_script_file:write(armv7_script)
armv7_script_file:close()
assert(os.execute("sh -n " .. armv7_script_path) == 0, "The ARMv7 installer script must be valid POSIX shell")
os.remove(armv7_script_path)
local armv7_python_script = helpers.buildBootstrapCommand(
    data_dir .. "/appdock/tools", data_dir .. "/setup-armv7-python", armv7_legacy_plan, true, false)
assert(armv7_python_script:find("portable Python SHA-256", 1, true)
    and armv7_python_script:find("python-headless-3.13.9-linux-arm.zip", 1, true)
    and armv7_python_script:find('test -f "$tmp/python-extract/python-headless-3.13.9-linux-arm/bin/python3.13"', 1, true)
    and armv7_python_script:find('chmod 755 "$tmp/python-extract/python-headless-3.13.9-linux-arm/bin/python3.13"', 1, true)
    and armv7_python_script:find('exec "$d/python-runtime/bin/python3.13" "$d/yt-dlp.pyz" "$@"', 1, true),
    "Older ARMv7 setup must verify and wrap the portable Python runtime with the yt-dlp zipapp")
local armv7_python_script_path = data_dir .. "/bootstrap-armv7-python-test.sh"
local armv7_python_script_file = assert(io.open(armv7_python_script_path, "wb"))
armv7_python_script_file:write(armv7_python_script)
armv7_python_script_file:close()
assert(os.execute("sh -n " .. armv7_python_script_path) == 0,
    "The ARMv7 Python-fallback installer script must be valid POSIX shell")
os.remove(armv7_python_script_path)
local armv7_musl_script = helpers.buildBootstrapCommand(
    data_dir .. "/appdock/tools", data_dir .. "/setup-armv7-musl", armv7_musl_plan, true, false)
assert(armv7_musl_script:find("appdock-youtube-armhf-musl-python-3.12.15.tar.gz", 1, true)
    and armv7_musl_script:find("5348e11472e5ca6c07d7b0ec75a2f1df1d181be7eb52d9e3cafb43267b1f916c", 1, true)
    and armv7_musl_script:find('tar -xzf "$tmp/python-runtime.pkg"', 1, true)
    and armv7_musl_script:find('test -s "$tmp/python-extract/python-runtime/etc/ssl/cert.pem"', 1, true),
    "Legacy ARMv7 setup must download, hash-check, unpack and validate the bundled musl runtime")
assert(armv7_musl_script:find('export PYTHONHOME="$r/usr"', 1, true)
    and armv7_musl_script:find('export SSL_CERT_FILE="$r/etc/ssl/cert.pem"', 1, true)
    and armv7_musl_script:find('exec "$r/lib/ld-musl-armhf.so.1" "$r/usr/bin/python3.12" "$d/yt-dlp.pyz" "$@"', 1, true)
    and not armv7_musl_script:find("unzip", 1, true),
    "The musl wrapper must use only its bundled loader, Python libraries, and CA bundle")
local armv7_musl_script_path = data_dir .. "/bootstrap-armv7-musl-test.sh"
local armv7_musl_script_file = assert(io.open(armv7_musl_script_path, "wb"))
armv7_musl_script_file:write(armv7_musl_script)
armv7_musl_script_file:close()
assert(os.execute("sh -n " .. armv7_musl_script_path) == 0,
    "The ARMv7 musl-runtime installer script must be valid POSIX shell")
os.remove(armv7_musl_script_path)

----------------------------------------------------------------
-- Pane construction
----------------------------------------------------------------

for _, view in ipairs({ "home", "tools" }) do
    state.view = view
    local pane = youtube:buildPane(instance, context)
    assert(pane and pane.dimen and pane.dimen.w == 600, "The " .. view .. " pane must fill the assigned rectangle")
    assert(pane.onDeactivate, "Every pane must expose onDeactivate")
end
state.view = "setup"
state.bootstrap = { error = "Download failed" }
assert(youtube:buildPane(instance, context), "The setup error/retry pane must build")
state.bootstrap = nil

local auto_settings = { output_dir = data_dir .. "/videos" }
local auto_appdock = {
    getYouTubeSettings = function() return auto_settings end,
    setYouTubeSettings = function(_, patch)
        for key, value in pairs(patch) do auto_settings[key] = value end
        return true
    end,
    notify = function() return true end,
}
local auto_youtube = YouTube:new(auto_appdock)
local auto_instance = {}
local auto_state = auto_youtube:_state(auto_instance)
local scheduled_before_setup = #scheduled
auto_youtube._startDetached = function(_, command, work, tag)
    auto_state.bootstrap_command = command
    auto_state.bootstrap_work = work
    assert(tag == "bootstrap", "First-open setup must use the bootstrap job")
    return { pid = 123, log = work .. "/bootstrap.log", exit = work .. "/bootstrap.exit" }
end
assert(auto_youtube:buildPane(auto_instance, context), "The first-open setup pane must build")
assert(auto_state.view == "setup" and auto_state.bootstrap.handle,
    "Opening YouTube without yt-dlp should immediately start setup")
assert(auto_state.bootstrap.install_ytdlp and not auto_state.bootstrap.install_ffmpeg,
    "First-open setup should install only missing tools")
assert(auto_state.bootstrap_command:find("SHA2%-256SUMS"), "First-open setup must verify the yt-dlp release")
local bootstrap_tick = scheduled[#scheduled]
assert(type(bootstrap_tick) == "function", "Automatic tool setup must schedule a progress tick")
auto_youtube._pollDetached = function(_, handle)
    assert(handle == auto_state.bootstrap.handle, "The setup tick must poll its bootstrap process")
    return nil
end
local rebuilds_before_bootstrap_tick = rebuild_calls
assert(YouTube._writeFile(auto_state.bootstrap.handle.log, "[check] live version output\n"),
    "The fake bootstrap log should be writable")
local tick_ok, tick_error = pcall(bootstrap_tick)
assert(tick_ok, "The asynchronous setup tick must not call an undefined hostIsActive helper: " .. tostring(tick_error))
assert(rebuild_calls == rebuilds_before_bootstrap_tick + 1,
    "An active first-run setup tick must rebuild its progress pane")
assert(last_rebuild_type == "fast", "Progress updates must use an E-Ink-friendly partial rebuild")
assert(auto_state.bootstrap.live_output:find("live version output", 1, true)
    and auto_state.bootstrap.live_widget.text:find("live version output", 1, true),
    "The setup tick must stream the current log tail into its visible widget")
assert(auto_state.bootstrap.progress_widget and auto_state.bootstrap.progress_widget.indeterminate
    and auto_state.bootstrap.progress_widget.position == 0.25,
    "The setup tick must advance the visible indeterminate progress bar")
assert(auto_youtube:buildPane(auto_instance, context), "The setup pane must rebuild after a progress update")
assert(auto_state.bootstrap.progress_widget.position == 0.25,
    "Rebuilding the setup pane must preserve the current progress pulse position")
while #scheduled > scheduled_before_setup do table.remove(scheduled) end
os.execute("rm -rf " .. auto_state.bootstrap_work)

state.view = "results"
state.results = { { id = "abc12345678", title = "Video", duration = 100, uploader = "Channel", url = "https://www.youtube.com/watch?v=abc12345678" } }
state.results_query = "test"
state.result_page = 1
assert(youtube:buildPane(instance, context), "The results pane must build")
state.view = "home"

----------------------------------------------------------------
-- Conversion pipeline
----------------------------------------------------------------

local function findCommand(name)
    local pipe = io.popen("command -v " .. name .. " 2>/dev/null", "r")
    if not pipe then return nil end
    local path = pipe:read("*l")
    pipe:close()
    return path and path ~= "" and path or nil
end

local ffmpeg = findCommand("ffmpeg")
if not ffmpeg then
    print("AppDock YouTube test: OK (conversion skipped, ffmpeg is unavailable)")
    return
end

local source = data_dir .. "/source.mp4"
assert(os.execute(string.format(
    "%s -y -hide_banner -loglevel error -f lavfi -i testsrc2=size=320x240:rate=24:duration=2"
    .. " -f lavfi -i sine=frequency=440:duration=2 -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest %s",
    ffmpeg, source)) == 0, "The test clip must be generated")

-- Ticks are driven by hand so the whole job runs without a real UI loop.
local function drain(instance, timeout_seconds)
    local deadline = os.time() + (timeout_seconds or 120)
    while os.time() < deadline do
        if #scheduled > 0 then
            local callback = table.remove(scheduled, 1)
            local delay = tonumber(scheduled_delays[callback]) or 0
            if delay > 0 then os.execute(string.format("sleep %.3f", delay)) end
            callback()
        else
            local job = instance.youtube and instance.youtube.job
            if not job or job.stage == "error" then return job end
            os.execute("sleep 0.2")
        end
    end
    error("The conversion did not settle within the timeout")
end

local function runConversion(dither_mode, label, seconds)
    stored.dither = dither_mode
    stored.max_duration = 60
    stored.fps = 12
    stored.resolution_percent = 100
    stored.output_dir = data_dir .. "/videos-" .. dither_mode
    local local_instance = {}
    local observed_progress_ratio = 0
    local video_fast_rebuild = false
    local local_context
    local_context = {
        dimen = { w = 600, h = 748 },
        requestRefresh = function(refresh_type)
            local job = local_instance.youtube and local_instance.youtube.job
            if job and job.progress_widget then
                observed_progress_ratio = job.progress_widget.ratio
            end
        end,
        requestRebuild = function(refresh_type)
            if refresh_type == "fast" then
                video_fast_rebuild = true
                youtube:buildPane(local_instance, local_context)
                local job = local_instance.youtube and local_instance.youtube.job
                if job and job.progress_widget then observed_progress_ratio = job.progress_widget.ratio end
            end
        end,
    }
    assert(youtube:startLocalFile(local_instance, local_context, source), "The conversion job must start")
    local progress_pane = youtube:buildPane(local_instance, local_context)
    assert(progress_pane and local_instance.youtube.job.progress_widget,
        "The job pane must bind its progress bar to the active conversion job")
    local conversion_job = local_instance.youtube.job
    assert(scheduled_delays[conversion_job.tick] <= 0.1,
        "Video conversion must use frequent short ticks instead of sleeping a full second")
    local job = drain(local_instance)
    assert(job == nil, label .. ": the job must finish, but ended with: " .. tostring(job and job.stage_message))
    assert(schedule_counts[conversion_job.tick] <= 6,
        "A short conversion must process frames in batches rather than taking one UI tick per two frames")
    assert(observed_progress_ratio > 0 and video_fast_rebuild,
        "Video ticks must rebuild the active pane with current progress using an E-Ink-friendly partial update")
    local library = local_instance.youtube.library
    assert(#library == 1, label .. ": exactly one converted video must appear in the library")
    local entry = library[1]
    assert(entry.has_audio, label .. ": a companion WAV file must exist")

    local handle = assert(io.open(entry.path, "rb"))
    local header = assert(BWR.readHeader(handle))
    assert(header.format == "BWR2", label .. ": new conversions must use the indexed compressed format")
    assert(header.width == 600 and header.height == 800, label .. ": the frame must follow the device screen")
    assert(header.fps == 12, label .. ": the header must keep the configured frame rate")
    local expected = seconds * header.fps
    assert(header.frames >= expected - 4 and header.frames <= expected + 4,
        label .. ": about " .. expected .. " frames were expected, found " .. header.frames)
    assert(math.abs(BWR.durationSeconds(header) - seconds) < 0.5, label .. ": the duration must match the clip")

    local engine = assert(Player.Engine.open(entry.path, entry.path:gsub("%.bwr$", ".wav"), function() end))
    assert(not engine.error, label .. ": the player must accept the produced file")
    local ui_player = Player:new(appdock)
    local loaded, load_error = ui_player:load({}, {}, entry.path)
    assert(loaded, label .. ": the player UI loader must accept BWR2: " .. tostring(load_error))
    ui_player:stop()
    assert(engine.audio_duration and engine.audio_duration > 0,
        label .. ": the player must read the companion WAV duration for timing calibration")
    assert(math.abs(engine:audioTime(engine.duration / 2) - engine.audio_duration / 2) < 0.001,
        label .. ": seeks must map the calibrated video position back onto the WAV timeline")
    local real_clock, simulated_clock = Player.now, 100
    Player.now = function() return simulated_clock end
    engine.anchor_wall, engine.anchor_position = simulated_clock, 0
    simulated_clock = simulated_clock + engine.audio_duration / 2
    assert(math.abs(engine:currentTime() - engine.duration / 2) < 0.001,
        label .. ": the video clock must follow the companion audio timeline (scale="
            .. tostring(engine.clock_scale) .. ", audio=" .. tostring(engine.audio_duration)
            .. ", video=" .. tostring(engine.duration) .. ", time=" .. tostring(engine:currentTime()) .. ")")
    local original_audio = engine.audio
    local audio_ready = false
    local stopped_audio = false
    engine.audio = {
        startFrom = function() return true end,
        requiresStartConfirmation = function() return true end,
        isPlaybackReady = function() return audio_ready end,
        stop = function() stopped_audio = true end,
    }
    engine.audio_error = nil
    engine.position, engine.anchor_wall, engine.paused = 0, nil, true
    assert(engine:play() and not engine.pending_start and engine.anchor_wall == simulated_clock
        and not engine.paused,
        label .. ": video must start immediately while the audio backend initializes")
    engine:pause()
    assert(stopped_audio, label .. ": pausing after synchronized startup must stop audio")
    engine:pause()
    engine.audio = original_audio
    Player.now = real_clock
    engine.anchor_wall, engine.position = nil, 0
    local white, black, total = 0, 0, 0
    for _, index in ipairs({ 0, math.floor(header.frames / 2), header.frames - 1 }) do
        local packed = assert(engine:readFrame(index))
        for byte_index = 1, #packed do
            local value = packed:byte(byte_index)
            if value == 255 then white = white + 1 end
            if value == 0 then black = black + 1 end
            total = total + 1
        end
    end
    assert(white < total and black < total, label .. ": the frames must not be uniformly black or white")
    local frame = assert(BWR.expandFrame(engine:readFrame(0), header.width, header.height))
    assert(frame.width == header.width and frame.height == header.height, label .. ": the frame must expand to the header size")
    engine:close()
    handle:close()
    return entry
end

local bayer_entry = runConversion("bayer", "Bayer path", 2)
assert(bayer_entry.size > 0, "The Bayer conversion must write bytes")

-- Playback view: the pane has to build around the loaded engine, and its
-- deactivation must release the engine and return to the library.
do
    local play_instance = {}
    local play_context = {
        dimen = { w = 600, h = 748 },
        requestRefresh = function() end,
        requestRebuild = function() end,
    }
    local library_pane = youtube:buildPane(play_instance, play_context)
    assert(youtube:play(play_instance, play_context, bayer_entry.path), "Playing a converted video must succeed")
    assert(play_instance.youtube.view == "play", "Starting playback must switch to the play view")
    library_pane:onDeactivate()
    assert(youtube.player.engine and not youtube.player.engine.error,
        "Deactivating the old library pane must not close the engine just loaded for playback")
    local play_pane = youtube:buildPane(play_instance, play_context)
    assert(play_pane and play_pane.dimen.w == 600, "The play pane must fill the assigned rectangle")
    assert(type(play_pane.onDeactivate) == "function", "The play pane must release playback when it is left")
    assert(youtube.player.engine and not youtube.player.engine.error, "The play pane must hold a usable engine")
    play_pane:onDeactivate()
    assert(youtube.player.engine == nil, "Leaving the play pane must close the engine")
    assert(play_instance.youtube.view == "home", "Leaving the play pane must return to the library")
    assert(youtube:buildPane(play_instance, play_context), "The library must build again after playback")
end

-- The ffmpeg path probes this build's monow bit sense, so it has to land on the
-- same contract even when the probe has to invert.
local ffmpeg_entry = runConversion("ffmpeg", "ffmpeg path", 2)
assert(ffmpeg_entry.size > 0, "The ffmpeg conversion must write bytes")

----------------------------------------------------------------
-- Failure handling
----------------------------------------------------------------

local missing_instance = {}
local missing_context = { dimen = { w = 600, h = 748 }, requestRefresh = function() end, requestRebuild = function() end }
assert(youtube:startLocalFile(missing_instance, missing_context, data_dir .. "/does-not-exist.mp4") == nil,
    "A missing source file must be refused")
assert(missing_instance.youtube.note ~= "", "A refused conversion must explain itself")

print("AppDock YouTube test: OK")
