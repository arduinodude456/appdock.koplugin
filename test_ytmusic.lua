-- AppDock YouTube Music DApp test.
--
-- Covers the audio-only download contract, the WAV conversion pipeline and the
-- library scan. The conversion part runs a real ffmpeg against a locally
-- generated audio clip; when ffmpeg is unavailable it is skipped instead of
-- failing.

local plugin_dir = os.getenv("APPDOCK_PLUGIN_DIR") or "/home/ubuntu/appdock.koplugin/appdock.koplugin/"
local data_dir = "/tmp/appdock_ytmusic_test"
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
package.preload["ui/widget/imagewidget"] = function() return WidgetContainer end
package.preload["appdock_keyboard"] = function() return { attach = function() end } end
package.preload["appdock_logo"] = function()
    local Logo = Widget:extend({})
    function Logo:init() self.dimen = { w = self.size or 0, h = self.size or 0 } end
    return Logo
end
package.preload["libs/libkoreader-lfs"] = function() return lfs end

local scheduled, scheduled_delays, schedule_counts = {}, {}, {}
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
        setDirty = function() end,
        widgetRepaint = function() end,
        forceRePaint = function() end,
        yieldToEPDC = function() end,
        show = function() end,
        close = function() end,
    }
end

local AppDockDialogs = dofile(plugin_dir .. "appdock_dialogs.lua")
local Audio = dofile(plugin_dir .. "appdock_audio.lua")
local YouTube = dofile(plugin_dir .. "appdock_youtube.lua")
local Music = dofile(plugin_dir .. "appdock_ytmusic.lua")

local helpers = Music._test

----------------------------------------------------------------
-- Audio-only download contract
----------------------------------------------------------------

local search_command = helpers.buildSearchCommand("/tools/yt-dlp", "Daft Punk discovery")
assert(search_command:find("ytsearch8:Daft Punk discovery", 1, true),
    "Music search must pass the complete query as a yt-dlp search expression")
assert(search_command:find("--flat-playlist", 1, true) and search_command:find("--playlist-end 8", 1, true),
    "Music search must return a bounded list of lightweight search results")
assert(search_command:find("--skip-download", 1, true),
    "Searching must only fetch metadata; downloading begins only after the user chooses a result")
assert(not search_command:find("--ignore-errors", 1, true),
    "Search errors must not be hidden by yt-dlp's ignore-errors mode")
assert(search_command:find("youtube:player_client=android", 1, true),
    "Music search must use the same resilient YouTube client as audio downloads")
assert(search_command:find("--socket-timeout 20", 1, true),
    "Music search must not hang indefinitely on a slow or stalled network")
assert(helpers.buildSearchCommand("/tools/yt-dlp", "  ") == nil,
    "An empty search query must not start yt-dlp")

local download = helpers.buildAudioDownloadCommand(
    "/tools/yt-dlp", "/tmp/source.media", "https://www.youtube.com/watch?v=abc12345678")
assert(download:find("bestaudio", 1, true), "Music downloads must ask for the audio-only stream")
assert(not download:find("bv*", 1, true) and not download:find("merge%-output%-format"),
    "Music downloads must never fetch or merge a video stream")
assert(download:find("%-%-extractor%-args 'youtube:player_client=android'", 1),
    "Music downloads must use the same working Android client as the video DApp")
assert(download:find("%-%-concurrent%-fragments 4", 1), "Music downloads must fetch fragments concurrently")

local wav_command = helpers.buildWavCommand("/tools/ffmpeg", "/tmp/source.media", "/tmp/track.wav", 180)
assert(wav_command:find("pcm_s16le", 1, true) and wav_command:find("44100", 1, true),
    "The conversion must produce 16-bit 44.1 kHz PCM that the AppDock audio backends accept")
assert(wav_command:find("%-t 180", 1), "The maximum length must bound the conversion")
assert(wav_command:find("%-vn", 1), "The conversion must ignore the video stream")
assert(not helpers.buildWavCommand("/tools/ffmpeg", "/tmp/s.mp4", "/tmp/t.wav", 0):find("%-t ", 1),
    "A zero maximum length must mean unlimited")

----------------------------------------------------------------
-- Cover handling
----------------------------------------------------------------

local urls = helpers.coverUrls({ id = "abc12345678", thumbnail = "https://i.ytimg.com/vi/abc12345678/hqdefault.jpg" })
assert(urls[1] == "https://i.ytimg.com/vi/abc12345678/maxresdefault.jpg",
    "The full-color poster frame must be preferred for cover art")
assert(urls[2] == "https://i.ytimg.com/vi/abc12345678/hqdefault.jpg", "The always available poster must be the fallback")
assert(#urls == 2, "A thumbnail that equals a fallback must not be requested twice")
assert(#helpers.coverUrls({ thumbnail = "https://example.org/poster.jpg" }) == 1,
    "A result without an id must fall back to its own thumbnail URL")
assert(#helpers.coverUrls({}) == 0, "A result without any image must request nothing")

local cover_command = helpers.buildCoverCommand(urls, "/tmp/cover.jpg")
assert(cover_command:find("curl", 1, true) and cover_command:find("wget", 1, true),
    "The cover download must work with curl or wget")
assert(cover_command:find("test %-s", 1), "An empty cover download must be treated as a failure")
assert(cover_command:find("maxresdefault", 1, true), "The cover command must carry the poster URLs")

----------------------------------------------------------------
-- Naming and position formatting
----------------------------------------------------------------

assert(helpers.titleFromFile("Rick_Astley_-_Never_Gonna_Give_You_Up.wav") == "Rick Astley - Never Gonna Give You Up",
    "Track names must be readable again")
assert(helpers.titleFromFile("song.MP3") == "song", "Other extensions must still be stripped")
assert(helpers.formatPosition(62, 185) == "1:02 / 3:05", "Positions must be shown as a clock")
assert(helpers.formatPosition(5, 0) == "0:05", "A track without a known duration must show the position only")

----------------------------------------------------------------
-- Pane construction and library
----------------------------------------------------------------

local settings = {
    ytdlp_path = "/tools/yt-dlp",
    ffmpeg_path = "/tools/ffmpeg",
    output_dir = data_dir .. "/videos",
    music_dir = data_dir .. "/music",
    max_duration = 180,
}

local appdock = {
    disableToolBootstrap = true,
    settings = {},
    getYouTubeSettings = function() return settings end,
    setYouTubeSettings = function(_, changes)
        for key, value in pairs(changes) do settings[key] = value end
        return true
    end,
    notify = function() end,
    getDAppManager = function() return nil end,
}

local music = Music:new(appdock)
local context = {
    dimen = { w = 600, h = 748 },
    requestRebuild = function() end,
    requestRefresh = function() end,
}

local instance = {}
local state = music:_state(instance)
state.tools = { ytdlp = "/tools/yt-dlp", ffmpeg = "/tools/ffmpeg", ready = true }

local home_pane = music:buildPane(instance, context)
assert(home_pane and home_pane[1], "The music home pane must build")
assert(state.view == "home", "A DApp without tools must land on its library, not on setup")

-- yt-dlp can return a non-zero status after YouTube has already yielded some
-- usable search rows (for example, one blocked result in an otherwise valid
-- result page). Keep and display those rows rather than reporting total failure.
local search_instance = {}
local search_state = music:_state(search_instance)
search_state.tools = { ytdlp = "/tools/yt-dlp", ffmpeg = "/tools/ffmpeg", ready = true }
local captured_search_command, fake_handle = nil, {}
local old_start_detached = music._startDetached
local old_poll_detached = Music._pollDetached
music._startDetached = function(_, command, _, tag)
    captured_search_command = command
    assert(tag == "search", "Search must use its own detached result log")
    return fake_handle
end
Music._pollDetached = function(handle)
    assert(handle == fake_handle, "Search polling must inspect the started search process")
    return 1, "abc12345678\tDaft Punk - One More Time\t320\tDaft Punk\thttps://i.ytimg.com/vi/abc12345678/hqdefault.jpg\n"
end
assert(music:startSearch(search_instance, context, "Daft Punk"), "Music search must start")
assert(captured_search_command and captured_search_command:find("ytsearch8:Daft Punk", 1, true),
    "The detached search must receive the user's actual query")
assert(#scheduled > 0, "A running Music search must schedule result polling")
table.remove(scheduled, 1)()
music._startDetached = old_start_detached
Music._pollDetached = old_poll_detached
assert(search_state.view == "results" and #search_state.results == 1,
    "Usable YouTube search results must survive a non-zero yt-dlp exit status")
assert(search_state.results[1].uploader == "Daft Punk" and search_state.results[1].title == "Daft Punk - One More Time",
    "Music search must retain the result artist and title")
assert(search_state.note:find("available results", 1, true),
    "Partial result sets must be shown with a clear partial-results notice")

-- A missing ffmpeg must not hide search results behind the shared tool setup
-- pane: yt-dlp is sufficient to search and display results; ffmpeg is only
-- required after the user selects a track for conversion.
local setup_pane_built = false
appdock.getDAppManager = function()
    return { youtube = {
        _state = function() return { bootstrap_attempted = true } end,
        _buildSetupPane = function() setup_pane_built = true; return emptySizedWidget(600, 748) end,
    } }
end
local partial_tools_instance = {}
local partial_tools_state = music:_state(partial_tools_instance)
partial_tools_state.tools = { ytdlp = "/tools/yt-dlp", ffmpeg = nil, ready = false }
partial_tools_state.view = "results"
partial_tools_state.search_query = "Daft Punk"
partial_tools_state.results = {
    { id = "abc12345678", title = "Daft Punk - One More Time", uploader = "Daft Punk", duration = 320 },
}
local partial_tools_pane = music:buildPane(partial_tools_instance, context)
assert(not setup_pane_built,
    "Missing ffmpeg must not replace the active search-results pane with tool setup")
local visible_result_row
for _, widget in ipairs(partial_tools_pane[1]) do
    if widget.title == "Daft Punk - One More Time" then visible_result_row = widget; break end
end
assert(visible_result_row and visible_result_row.dimen.w > 0 and visible_result_row.dimen.h > 0
        and visible_result_row.overlap_offset and visible_result_row.overlap_offset[2] > 0,
    "The results pane must contain a laid-out, visible row even when ffmpeg is unavailable")
appdock.getDAppManager = function() return nil end

-- A failed/empty search must stay on a visible diagnostic pane; the old
-- behavior returned to the empty library and left only a tiny footer message.
local failed_search_instance = {}
local failed_search_state = music:_state(failed_search_instance)
failed_search_state.tools = { ytdlp = "/tools/yt-dlp", ffmpeg = "/tools/ffmpeg", ready = true }
local failed_handle = {}
music._startDetached = function() return failed_handle end
Music._pollDetached = function(handle)
    assert(handle == failed_handle, "The failed search must poll its detached process")
    return 1, "ERROR: [youtube:search] HTTP Error 403: Forbidden\n"
end
assert(music:startSearch(failed_search_instance, context, "hallo"), "A normal word must start a Music search")
table.remove(scheduled, 1)()
assert(failed_search_state.view == "search_error" and failed_search_state.search_error:find("403", 1, true),
    "A search failure must preserve the yt-dlp diagnostic in a visible error state")
local failed_pane = music:buildPane(failed_search_instance, context)
assert(failed_pane and failed_pane[1], "The failed-search diagnostic pane must remain renderable")
local failed_content = failed_pane[1]
local found_retry, found_back = false, false
for _, widget in ipairs(failed_content) do
    if widget.text == "Try again" then found_retry = true end
    if widget.text == "‹ Back to library" then found_back = true end
end
assert(found_retry and found_back, "The error pane must expose retry and return-to-library actions")
music._startDetached = old_start_detached
Music._pollDetached = old_poll_detached

local library = music:scanLibrary(instance, context)
assert(type(library) == "table" and #library == 0, "An empty music folder must produce an empty library")

----------------------------------------------------------------
-- Conversion pipeline (real ffmpeg)
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
    print("AppDock YouTube Music test: OK (conversion skipped, ffmpeg is unavailable)")
    return
end

local source = data_dir .. "/source.m4a"
assert(os.execute(string.format(
    "%s -y -hide_banner -loglevel error -f lavfi -i sine=frequency=440:duration=2 -c:a aac %s",
    ffmpeg, source)) == 0, "The test clip must be generated")

local function drain(target, timeout_seconds)
    local deadline = os.time() + (timeout_seconds or 120)
    while os.time() < deadline do
        if #scheduled > 0 then
            local callback = table.remove(scheduled, 1)
            local delay = tonumber(scheduled_delays[callback]) or 0
            if delay > 0 then os.execute(string.format("sleep %.3f", math.min(delay, 1))) end
            callback()
        else
            local job = target.music and target.music.job
            if not job or job.stage == "error" then return job end
            os.execute("sleep 0.2")
        end
    end
    error("The music conversion did not settle within the timeout")
end

settings.ffmpeg_path = ffmpeg
local local_instance = {}
state = music:_state(local_instance)
state.tools = YouTube.detectTools(settings)
state.tools.ytdlp = state.tools.ytdlp or "/tools/yt-dlp"
assert(music:startLocalFile(local_instance, context, source), "The music conversion job must start")
local job = drain(local_instance)
assert(job == nil, "The music job must finish, but ended with: " .. tostring(job and job.stage_message))

local tracks = music:scanLibrary(local_instance, context)
assert(#tracks == 1, "Exactly one converted track must appear in the music library")
local track = tracks[1]
assert(track.path:match("%.wav$"), "Music tracks must be stored as WAV files")
assert(track.duration and math.abs(track.duration - 2) < 0.4,
    "The converted track must keep the source duration, found " .. tostring(track.duration))
assert(track.size > 44, "The converted track must contain audio data")
assert(not track.path:match("%.bwr$"), "Music must never produce a converted video file")

local artist_file = assert(io.open(music:artistPathFor(track.path), "wb"))
artist_file:write("Test Artist")
artist_file:close()
tracks = music:scanLibrary(local_instance, context)
track = tracks[1]
assert(track.artist == "Test Artist", "The library must restore the saved artist for the player screen")
state.play = {
    path = track.path,
    title = track.title,
    artist = track.artist,
    paused = true,
    offset = 0,
    started_at = os.time(),
    duration = track.duration,
}
local player_pane = music:_buildPlayerPane(local_instance, context, state)
assert(player_pane[1].background == "black", "The now-playing screen must use YouTube Music's dark full-player treatment")
local found_artist, found_mix = false, false
for _, widget in ipairs(player_pane) do
    if widget.text == "Test Artist" then found_artist = true end
    if widget.text and widget.text:find("Mix —", 1, true) then found_mix = true end
end
assert(found_artist and found_mix, "The player must show artist attribution and a compact mix footer")

local handle = assert(io.open(track.path, "rb"))
local info = assert(Audio.readWavInfo(handle))
handle:close()
assert(info.sample_rate == 44100 and info.channels == 2 and info.bits_per_sample == 16,
    "The companion WAV must be the format the AppDock audio backends expect")

assert(lfs.attributes(data_dir .. "/music", "mode") == "directory",
    "The configured music folder must be created before a download")

settings.music_dir = ""
assert(music:musicDirectory() == data_dir .. "/appdock/music",
    "The default music folder must live in KOReader's data directory")
assert(lfs.attributes(data_dir .. "/appdock/music", "mode") == "directory",
    "The default music folder must be created on demand")
settings.music_dir = data_dir .. "/music"

-- Closing the DApp must stop playback and drop a pending search, but leave a
-- finished library intact.
music:onDAppClose(local_instance)
assert(local_instance.music.play == nil, "Closing the music DApp must stop playback")
assert(#music:scanLibrary(local_instance, context) == 1, "Closing the music DApp must keep downloaded tracks")

print("AppDock YouTube Music test: OK")
