--[[--
AppDock YouTube Music: audio-only YouTube downloads with full-color cover art.

The DApp shares the YouTube search and the same two command line tools, but it
never downloads or converts video:

* one `yt-dlp` pass fetches the best available audio-only stream, which is a
  fraction of a video download,
* one `ffmpeg` pass turns that stream into the companion 16-bit WAV the AppDock
  player already understands,
* the cover is fetched as an ordinary full-color JPEG (16:9 poster frame), so a
  track costs no frame conversion, no dithering and no video storage.

Playback reuses `appdock_audio.lua`, so the same `gst-launch-1.0`, `aplay` or
`tinyplay` backends that play YouTube video audio play music tracks too.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalSpan = require("ui/widget/horizontalspan")
local AppDockDialogs = require("appdock_dialogs")
local InputDialog = AppDockDialogs.InputDialog
local OverlapGroup = require("ui/widget/overlapgroup")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local AppDockKeyboard = require("appdock_keyboard")
local Audio = require("appdock_audio")
local Player = require("appdock_player")
local Wallpaper = require("appdock_wallpaper")
local YouTube = require("appdock_youtube")

local Screen = Device.screen

local Music = {}
Music.__index = Music

local Pill = YouTube.Pill
local Row = YouTube.Row
local ProgressBar = YouTube.ProgressBar

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

local function shellQuote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function emptySizedWidget(width, height)
    return CenterContainer:new{ dimen = Geom:new{ w = width, h = height }, HorizontalSpan:new{ width = 0 } }
end

local function fileExists(path)
    local handle = path and io.open(path, "rb")
    if handle then handle:close(); return true end
    return false
end

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

-- `appdock_player` owns the sub-second wall clock AppDock uses for playback
-- timing, so music positions follow the same source of truth as video audio.
local function monotonicNow()
    if Player and type(Player.now) == "function" then
        local ok, value = pcall(Player.now)
        if ok and type(value) == "number" then return value end
    end
    return os.time()
end

local function setBarRatio(widget, ratio)
    if not widget then return false end
    widget.ratio = clamp(tonumber(ratio) or 0, 0, 1)
    return true
end

local function lfsModule()
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok then ok, lfs = pcall(require, "lfs") end
    return ok and lfs or nil
end

local function ensureDirectory(path)
    if not path or path == "" then return false end
    local lfs = lfsModule()
    if lfs and lfs.attributes and lfs.attributes(path, "mode") == "directory" then return true end
    if lfs and lfs.mkdir then
        local parent = path:match("^(.*)/[^/]+$")
        if parent then ensureDirectory(parent) end
        lfs.mkdir(path)
    end
    os.execute("mkdir -p " .. shellQuote(path) .. " >/dev/null 2>&1")
    return true
end

local function cleanupDirectory(path)
    if not path or path == "" then return end
    os.execute("rm -rf " .. shellQuote(path) .. " >/dev/null 2>&1")
end

local function jobDirectory()
    local base = os.getenv("TMPDIR") or "/tmp"
    local path = string.format("%s/appdock-ytm-%d-%d", base, os.time(), math.random(1000, 9999))
    ensureDirectory(path)
    return path
end

-- `Artist - Title` style file names are common for music, so the readable name
-- keeps the separator instead of turning it into an underscore.
local function titleFromFile(name)
    local text = tostring(name or ""):gsub("%.[%w][%w%d]*$", "")
    text = text:gsub("_+", " "):gsub("%s+", " ")
    return trim(text) ~= "" and trim(text) or _("Untitled track")
end

----------------------------------------------------------------
-- Detached command helpers
----------------------------------------------------------------

function Music:_startDetached(command, work_dir, tag)
    local log_path = work_dir .. "/" .. tag .. ".log"
    local exit_path = work_dir .. "/" .. tag .. ".exit"
    os.remove(exit_path)
    os.remove(log_path)
    local runner = "(\n" .. command .. "\n) >" .. shellQuote(log_path)
        .. " 2>&1; code=$?; echo $code >" .. shellQuote(exit_path)
    local quoted_runner = shellQuote(runner)
    local launch = "if command -v setsid >/dev/null 2>&1; then setsid sh -c " .. quoted_runner
        .. " </dev/null >/dev/null 2>&1 & else sh -c " .. quoted_runner
        .. " </dev/null >/dev/null 2>&1 & fi; echo $!"
    local pipe = io.popen(launch, "r")
    if not pipe then return nil, _("The command could not be started.") end
    local pid = tonumber(pipe:read("*l"))
    pipe:close()
    return { pid = pid, log = log_path, exit = exit_path }
end

function Music._pollDetached(handle)
    if not handle then return nil end
    local marker = readFile(handle.exit)
    if marker == nil then return nil end
    local code = tonumber(trim(marker)) or 1
    return code, readFile(handle.log) or ""
end

function Music._killDetached(handle)
    if handle and handle.pid then
        os.execute("kill -TERM -" .. tostring(handle.pid) .. " 2>/dev/null")
        os.execute("kill -TERM " .. tostring(handle.pid) .. " 2>/dev/null")
        os.execute("kill -KILL -" .. tostring(handle.pid) .. " 2>/dev/null")
        os.execute("kill -KILL " .. tostring(handle.pid) .. " 2>/dev/null")
    end
end

----------------------------------------------------------------
-- Pure helpers (unit tested)
----------------------------------------------------------------

-- Audio-only download. `bestaudio` keeps yt-dlp from ever fetching a video
-- stream, so there is nothing to merge and nothing to convert frame by frame.
function Music.buildAudioDownloadCommand(ytdlp, source_file, source)
    return shellQuote(ytdlp)
        .. " --no-playlist --newline --no-warnings --no-cache-dir"
        .. " --extractor-args " .. shellQuote("youtube:player_client=android")
        .. " --concurrent-fragments 4"
        .. " -f " .. shellQuote("bestaudio[ext=m4a]/bestaudio[ext=webm]/bestaudio/best")
        .. " -o " .. shellQuote(source_file)
        .. " " .. shellQuote(source)
end

function Music.buildWavCommand(ffmpeg, source_file, target, max_duration)
    local seconds = tonumber(max_duration) or 0
    return shellQuote(ffmpeg)
        .. " -nostdin -hide_banner -loglevel error -y"
        .. " -i " .. shellQuote(source_file)
        .. (seconds > 0 and (" -t " .. tostring(math.floor(seconds))) or "")
        .. " -vn -sn -dn -af " .. shellQuote("aresample=async=1:first_pts=0")
        .. " -c:a pcm_s16le -ar 44100 -ac 2 -f wav " .. shellQuote(target)
end

-- YouTube poster frames are ordinary JPEGs. `maxresdefault` is the full-color
-- original when the uploader provided one, `hqdefault` always exists, and the
-- search result's own URL is the last fallback.
function Music.coverUrls(result)
    result = type(result) == "table" and result or {}
    local urls, seen = {}, {}
    local function add(url)
        url = trim(url)
        if url ~= "" and not seen[url] then
            seen[url] = true
            urls[#urls + 1] = url
        end
    end
    local id = result.id
    if not id and result.thumbnail then
        id = result.thumbnail:match("/vi/([%w%-_]+)/")
    end
    if id then
        add("https://i.ytimg.com/vi/" .. id .. "/maxresdefault.jpg")
        add("https://i.ytimg.com/vi/" .. id .. "/hqdefault.jpg")
    end
    add(result.thumbnail)
    return urls
end

function Music.buildCoverCommand(urls, target)
    urls = type(urls) == "table" and urls or {}
    if #urls == 0 then return nil end
    local quoted = {}
    for index, url in ipairs(urls) do quoted[index] = shellQuote(url) end
    local script = "for u in " .. table.concat(quoted, " ") .. "; do"
        .. " if command -v curl >/dev/null 2>&1; then"
        .. " curl -L --fail --max-time 30 -sS -o " .. shellQuote(target) .. ' "$u" && break;'
        .. " elif command -v wget >/dev/null 2>&1; then"
        .. " wget -q -T 30 -O " .. shellQuote(target) .. ' "$u" && break;'
        .. " else exit 1; fi; done"
        .. " && test -s " .. shellQuote(target)
    return "sh -c " .. shellQuote(script)
end

----------------------------------------------------------------
-- Instance state
----------------------------------------------------------------

function Music:new(appdock)
    return setmetatable({ appdock = appdock }, self)
end

function Music:_settings()
    if self.appdock and type(self.appdock.getYouTubeSettings) == "function" then
        return self.appdock:getYouTubeSettings()
    end
    return {}
end

function Music:_patchSettings(changes)
    if self.appdock and type(self.appdock.setYouTubeSettings) == "function" then
        return self.appdock:setYouTubeSettings(changes)
    end
    return false
end

function Music:_state(instance)
    instance.music = instance.music or {
        view = "home",
        note = "",
        tools = nil,
        library = nil,
        library_page = 1,
        selected_path = nil,
        results = nil,
        results_page = 1,
        job = nil,
        play = nil,
        play_page = 1,
        tools_page = 1,
    }
    local state = instance.music
    state.tools = state.tools or YouTube.detectTools(self:_settings())
    return state
end

function Music:_notify(instance, context, text)
    local state = self:_state(instance)
    state.note = text
    if context and context.requestRefresh then context.requestRefresh("ui") end
end

function Music:_youtube()
    local appdock = self.appdock
    if not appdock or type(appdock.getDAppManager) ~= "function" then return nil end
    local manager = appdock:getDAppManager()
    return manager and manager.youtube or nil
end

function Music:musicDirectory()
    local settings = self:_settings()
    local path = trim(settings.music_dir)
    if path == "" then
        local ok, data_dir = pcall(function() return DataStorage:getDataDir() end)
        local base = ok and data_dir or "/tmp"
        path = base .. "/appdock/music"
    end
    ensureDirectory(path)
    return path
end

function Music:coverPathFor(path)
    return (path or ""):gsub("%.[Ww][Aa][Vv]$", ".jpg")
end

function Music:artistPathFor(path)
    return (path or ""):gsub("%.[Ww][Aa][Vv]$", ".artist")
end

----------------------------------------------------------------
-- Library
----------------------------------------------------------------

function Music:scanLibrary(instance, context)
    local state = self:_state(instance)
    local directory = self:musicDirectory()
    local entries = {}
    local lfs = lfsModule()
    if lfs and lfs.dir then
        for name in lfs.dir(directory) do
            if name:match("%.[Ww][Aa][Vv]$") then
                local path = directory .. "/" .. name
                local attributes = lfs.attributes and lfs.attributes(path)
                local cover = self:coverPathFor(path)
                entries[#entries + 1] = {
                    path = path,
                    title = titleFromFile(name),
                    artist = trim(readFile(self:artistPathFor(path)) or ""),
                    duration = Audio.durationOf(path),
                    cover = cover,
                    has_cover = fileExists(cover),
                    size = attributes and attributes.size or 0,
                    modified = attributes and attributes.modification or 0,
                }
            end
        end
    else
        -- Without LuaFileSystem the folder is still readable through `ls`, so a
        -- reader that lacks the module is not left with an empty library.
        local pipe = io.popen("ls -1 " .. shellQuote(directory) .. " 2>/dev/null", "r")
        if pipe then
            for name in pipe:lines() do
                if name:match("%.[Ww][Aa][Vv]$") then
                    local path = directory .. "/" .. name
                    local cover = self:coverPathFor(path)
                    entries[#entries + 1] = {
                        path = path,
                        title = titleFromFile(name),
                        artist = trim(readFile(self:artistPathFor(path)) or ""),
                        duration = Audio.durationOf(path),
                        cover = cover,
                        has_cover = fileExists(cover),
                        size = 0,
                        modified = 0,
                    }
                end
            end
            pipe:close()
        end
    end
    table.sort(entries, function(left, right) return (left.modified or 0) > (right.modified or 0) end)
    state.library = entries
    state.library_page = clamp(state.library_page or 1, 1, math.max(1, math.ceil(#entries / 6)))
    return entries
end

function Music:_library(instance, context)
    local state = self:_state(instance)
    if not state.library then self:scanLibrary(instance, context) end
    return state.library or {}
end

----------------------------------------------------------------
-- Playback
----------------------------------------------------------------

function Music:_elapsed(play, now)
    if not play then return 0 end
    local reference = play.paused and (play.paused_at or play.started_at) or now
    return math.max(0, (play.offset or 0) + (reference - play.started_at))
end

function Music:playEntry(instance, context, path, start_seconds)
    local state = self:_state(instance)
    if not fileExists(path) then
        self:_notify(instance, context, _("This track is no longer available."))
        return false
    end
    self:stopPlayback(instance)
    local audio = Audio.new(path)
    local error_message = audio:getError()
    if error_message then
        self:_notify(instance, context, error_message)
        return false
    end
    local offset = math.max(0, tonumber(start_seconds) or 0)
    local started, start_error = audio:startFrom(offset)
    if not started then
        self:_notify(instance, context, start_error or _("The track could not be started."))
        return false
    end
    state.play = {
        path = path,
        title = titleFromFile(basename(path)),
        artist = "",
        audio = audio,
        offset = offset,
        started_at = monotonicNow(),
        paused = false,
        duration = Audio.durationOf(path),
    }
    for _, entry in ipairs(self:_library(instance, context)) do
        if entry.path == path then
            state.play.title = entry.title or state.play.title
            state.play.artist = entry.artist or ""
            break
        end
    end
    state.selected_path = path
    state.view = "player"
    self:_schedulePlayTick(instance, context)
    if context and context.requestRebuild then context.requestRebuild("ui") end
    return true
end

function Music:stopPlayback(instance)
    local state = self:_state(instance)
    local play = state.play
    if not play then return end
    if play.audio then play.audio:stop() end
    state.play = nil
    if play.tick then play.tick = nil end
end

function Music:togglePlayback(instance, context)
    local state = self:_state(instance)
    local play = state.play
    if not play or not play.audio then
        local selected = state.selected_path
        if not selected then
            local library = self:_library(instance, context)
            selected = library[1] and library[1].path
        end
        if not selected then return false end
        return self:playEntry(instance, context, selected, 0)
    end
    if play.paused then
        play.audio:resume()
        play.started_at = monotonicNow() - ((play.paused_at or play.started_at) - play.started_at)
        play.paused, play.paused_at = false, nil
    else
        play.audio:pause()
        play.paused, play.paused_at = true, monotonicNow()
    end
    if context and context.requestRebuild then context.requestRebuild("ui") end
    self:_schedulePlayTick(instance, context)
    return true
end

function Music:seek(instance, context, delta)
    local state = self:_state(instance)
    local play = state.play
    if not play then return false end
    local now = monotonicNow()
    local target = clamp(self:_elapsed(play, now) + (tonumber(delta) or 0), 0, play.duration or math.huge)
    return self:playEntry(instance, context, play.path, target)
end

function Music:_schedulePlayTick(instance, context)
    local state = self:_state(instance)
    local play = state.play
    if not play or play.paused then return end
    if play.tick then return end
    play.tick = function()
        local current = self:_state(instance).play
        if not current or current ~= play then return end
        play.tick = nil
        local now = monotonicNow()
        local elapsed = self:_elapsed(play, now)
        local duration = play.duration or 0
        if duration > 0 and elapsed >= duration then
            if state.repeat_track then
                self:playEntry(instance, context, play.path, 0)
            else
                self:stopPlayback(instance)
                if context and context.requestRebuild then context.requestRebuild("ui") end
            end
            return
        end
        if play.time_widget and play.time_widget.setText then
            play.time_widget:setText(Music.formatPosition(elapsed))
        end
        setBarRatio(play.progress_widget, duration > 0 and elapsed / duration or 0)
        local manager = context and context.manager
        if not manager or not context.host or manager.active_host == context.host then
            if context and context.requestRefresh then context.requestRefresh("fast")
            elseif context and context.requestRebuild then context.requestRebuild("fast") end
        end
        self:_schedulePlayTick(instance, context)
    end
    UIManager:scheduleIn(1, play.tick)
end

function Music.formatPosition(elapsed, duration)
    local function clock(seconds)
        seconds = math.max(0, math.floor(tonumber(seconds) or 0))
        return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
    end
    if duration and duration > 0 then
        return clock(elapsed) .. " / " .. clock(duration)
    end
    return clock(elapsed)
end

----------------------------------------------------------------
-- Search and download
----------------------------------------------------------------

function Music.buildSearchCommand(ytdlp, query)
    query = trim(query)
    if query == "" then return nil end
    return shellQuote(ytdlp)
        .. " --no-warnings --no-cache-dir --flat-playlist --skip-download"
        .. " --socket-timeout 20 --retries 1 --extractor-retries 1 --playlist-end 8"
        .. " --extractor-args " .. shellQuote("youtube:player_client=android")
        .. " --print " .. shellQuote("%(id)s\t%(title)s\t%(duration)s\t%(uploader)s\t%(thumbnail)s")
        .. " " .. shellQuote("ytsearch8:" .. query)
end

function Music:startSearch(instance, context, query)
    local state = self:_state(instance)
    local tools = state.tools or YouTube.detectTools(self:_settings())
    state.tools = tools
    query = trim(query)
    if query == "" then return false end
    state.search_query = query
    if not tools.ytdlp then
        state.view = "search_error"
        state.search_error = _("yt-dlp was not found. Add it to the AppDock tools folder or configure its path.")
        state.note = ""
        if context and context.requestRebuild then context.requestRebuild("ui") end
        return false
    end
    local work = jobDirectory()
    local command = Music.buildSearchCommand(tools.ytdlp, query)
    local handle, start_error = self:_startDetached(command, work, "search")
    if not handle then
        cleanupDirectory(work)
        state.view = "search_error"
        state.search_error = start_error or _("The search could not be started.")
        state.note = ""
        if context and context.requestRebuild then context.requestRebuild("ui") end
        return false
    end
    state.view = "search"
    state.note = string.format(_("Searching YouTube Music for “%s”…"), query)
    state.search_error = nil
    state.search_handle = handle
    state.search_work = work
    state.search_query = query
    state.search_started = os.time()
    state.results = nil
    if context and context.requestRebuild then context.requestRebuild("ui") end
    local tick
    tick = function()
        if self:_state(instance).search_handle ~= handle then return end
        local code, log = Music._pollDetached(handle)
        if code == nil then
            if os.time() - (state.search_started or os.time()) >= 90 then
                Music._killDetached(handle)
                cleanupDirectory(work)
                state.search_handle, state.search_work = nil, nil
                state.view = "search_error"
                state.search_error = _("The search timed out. Check the connection and try again.")
                state.note = ""
                if context and context.requestRebuild then context.requestRebuild("ui") end
                return
            end
            UIManager:scheduleIn(1, tick)
            return
        end
        state.search_handle = nil
        state.search_work = nil
        cleanupDirectory(work)
        local results = YouTube.parseSearchOutput(log)
        if #results == 0 then
            local detail = trim(log or ""):gsub("\27%[[%d;]*[A-Za-z]", "")
            if detail ~= "" then detail = detail:sub(-220):gsub("\r", " "):gsub("\n+", " · ") end
            if code ~= 0 then
                state.search_error = detail ~= "" and detail or _("yt-dlp returned an error. Check the connection and the yt-dlp version.")
            else
                state.search_error = _("yt-dlp returned no results. Check the connection and try another search.")
            end
            state.view = "search_error"
            state.note = ""
        else
            state.results = results
            state.results_page = 1
            state.search_error = nil
            state.view = "results"
            state.note = code ~= 0 and _("Showing available results; some YouTube results could not be loaded.") or ""
            local youtube = self:_youtube()
            if youtube and type(youtube._cacheThumbnail) == "function" then
                for _, result in ipairs(results) do pcall(youtube._cacheThumbnail, youtube, result) end
            end
        end
        if context and context.requestRebuild then context.requestRebuild("ui") end
    end
    UIManager:scheduleIn(1, tick)
    return true
end

function Music:promptSearch(instance, context)
    local state = self:_state(instance)
    local dialog
    dialog = InputDialog:new{
        title = _("Search YouTube Music"),
        input = "",
        input_hint = _("Song, artist or link"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function() UIManager:close(dialog) end,
                },
                {
                    text = _("Search"),
                    is_enter_default = true,
                    callback = function()
                        local text = trim(dialog:getInputText())
                        UIManager:close(dialog)
                        if text == "" then return end
                        -- Plain text is always a music search (including an
                        -- 11-character term). Only a pasted URL is treated as
                        -- a direct download/open request.
                        local is_url = text:match("^%a[%w+%.%-]*://") ~= nil
                        local kind, value
                        if is_url then
                            kind, value = YouTube.classifyInput(text)
                        else
                            kind, value = "search", text
                        end
                        if kind == "video" then
                            self:startDownload(instance, context, {
                                id = value,
                                title = value,
                                url = YouTube.watchUrl(value),
                            })
                        elseif kind == "search" then
                            self:startSearch(instance, context, value)
                        else
                            state.view = "search_error"
                            state.search_query = text
                            state.search_error = _("That link is not a supported YouTube address.")
                            state.note = ""
                            if context and context.requestRebuild then context.requestRebuild("ui") end
                        end
                    end,
                },
            },
        },
    }
    AppDockKeyboard.attach(dialog)
    UIManager:show(dialog)
    dialog:onShowKeyboard()
    return true
end

function Music:_startJob(instance, context, spec)
    local state = self:_state(instance)
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
    local directory = self:musicDirectory()
    local work = jobDirectory()
    local slug = YouTube.slugify(spec.title, spec.id)
    local target = directory .. "/" .. slug .. ".wav"
    local job = {
        kind = spec.kind,
        source = spec.source,
        title = spec.title or slug,
        artist = trim(spec.artist or ""),
        slug = slug,
        video_id = spec.video_id,
        thumbnail = spec.thumbnail,
        work = work,
        target = target,
        cover = directory .. "/" .. slug .. ".jpg",
        source_file = work .. "/source.media",
        stage = "download",
        stage_message = _("Preparing"),
        percent = 0,
        started = os.time(),
        log_tail = "",
    }
    state.job = job
    state.view = "job"
    state.note = ""
    if spec.kind == "file" then
        job.source_file = spec.source
        job.stage = "convert"
        job.stage_message = _("Converting to WAV")
        self:_startConversionStage(instance, context, job)
    else
        local command = Music.buildAudioDownloadCommand(tools.ytdlp, job.source_file, spec.source)
        local handle, start_error = self:_startDetached(command, work, "download")
        if not handle then
            job.stage = "error"
            job.stage_message = start_error or _("The download could not be started.")
        else
            job.download = handle
        end
    end
    if context and context.requestRebuild then context.requestRebuild("ui") end
    self:_schedule(instance, context)
    return job
end

function Music:startDownload(instance, context, result)
    if type(result) ~= "table" or trim(result.url or "") == "" then return false end
    return self:_startJob(instance, context, {
        kind = "url",
        source = result.url,
        title = result.title or result.id,
        artist = result.uploader,
        video_id = result.id,
        thumbnail = result.thumbnail,
        duration = result.duration,
    }) ~= nil
end

-- A local audio or video file is converted the same way, so a track recorded
-- elsewhere on the reader can join the library without a download.
function Music:startLocalFile(instance, context, path)
    if type(path) ~= "string" or not fileExists(path) then
        self:_notify(instance, context, _("The selected file is not available."))
        return nil
    end
    local title = basename(path):gsub("%.[^.]+$", "")
    return self:_startJob(instance, context, { kind = "file", source = path, title = title })
end

-- The cover download runs next to the conversion; it is fast and never blocks
-- the finished track.
function Music:_startCoverStage(instance, context, job)
    local result = { id = job.video_id, thumbnail = job.thumbnail }
    if not result.id and not result.thumbnail then return nil end
    local urls = Music.coverUrls(result)
    local command = Music.buildCoverCommand(urls, job.cover)
    if not command then return nil end
    local handle = self:_startDetached(command, job.work, "cover")
    job.cover_handle = handle
    return handle
end

function Music:_startConversionStage(instance, context, job)
    local settings = self:_settings()
    local tools = self:_state(instance).tools
    if not tools or not tools.ffmpeg then
        job.stage = "error"
        job.stage_message = _("ffmpeg was not found. Add it to the AppDock tools folder or configure its path.")
        return
    end
    self:_startCoverStage(instance, context, job)
    local command = Music.buildWavCommand(tools.ffmpeg, job.source_file, job.target, settings.max_duration)
    local handle, start_error = self:_startDetached(command, job.work, "convert")
    if not handle then
        job.stage = "error"
        job.stage_message = start_error or _("The conversion could not be started.")
        return
    end
    job.convert = handle
    job.stage = "convert"
    job.stage_message = _("Converting to WAV")
    job.interval = 1
end

function Music:_cleanupJob(job)
    Music._killDetached(job.download)
    Music._killDetached(job.convert)
    Music._killDetached(job.cover_handle)
    job.download, job.convert, job.cover_handle = nil, nil, nil
    cleanupDirectory(job.work)
end

function Music:_failJob(instance, context, job, message)
    job.stage = "error"
    job.stage_message = message or _("The download failed.")
    job.percent = 0
    Music._killDetached(job.cover_handle)
    job.cover_handle = nil
    if context and context.requestRefresh then context.requestRefresh("ui") end
end

function Music:_finishJob(instance, context, job)
    local handle = io.open(job.target, "rb")
    local has_track = false
    if handle then
        local info = Audio.readWavInfo(handle)
        has_track = info ~= nil
        handle:close()
    end
    if not has_track then
        os.remove(job.target)
        self:_failJob(instance, context, job, _("The conversion produced no playable audio file."))
        return
    end
    -- Give a still-running cover download a moment, but never block the track.
    local cover_code = Music._pollDetached(job.cover_handle)
    job.cover_handle = nil
    job.stage = "done"
    job.percent = 100
    job.stage_message = _("Finished")
    local state = self:_state(instance)
    self:_cleanupJob(job)
    state.job = nil
    if trim(job.artist or "") ~= "" then
        writeFile(self:artistPathFor(job.target), trim(job.artist))
    end
    self:scanLibrary(instance, context)
    state.selected_path = job.target
    local duration = Audio.durationOf(job.target)
    self:_notify(instance, context, string.format(
        _("Saved %s · %s"), basename(job.target), YouTube.formatDuration(duration)))
    local appdock = self.appdock
    if appdock and type(appdock.notify) == "function" then
        pcall(function()
            appdock:notify({
                title = _("YouTube Music track ready"),
                message = basename(job.target),
                source = _("YouTube Music"),
                app_id = "dapp:youtube_music",
            })
        end)
    end
    if cover_code ~= nil and cover_code ~= 0 then
        state.note = _("The track is ready, but the cover image could not be downloaded.")
    end
    state.view = state.play and "player" or "home"
    if context and context.requestRebuild then context.requestRebuild("ui") end
end

function Music:cancelJob(instance, context)
    local state = self:_state(instance)
    local job = state.job
    if not job then return end
    self:_cleanupJob(job)
    os.remove(job.target)
    state.job = nil
    state.view = "home"
    self:_notify(instance, context, _("Download cancelled."))
    if context and context.requestRebuild then context.requestRebuild("ui") end
end

function Music:_schedule(instance, context)
    local state = self:_state(instance)
    local job = state.job
    if not job then return end
    job.tick = job.tick or function() self:_tick(instance, context) end
    UIManager:scheduleIn(job.interval or 1, job.tick)
end

function Music:_tick(instance, context)
    local state = self:_state(instance)
    local job = state.job
    if not job then return end

    if job.stage == "download" then
        if not job.download then
            self:_failJob(instance, context, job, _("The download could not be started."))
            return
        end
        local code, log = Music._pollDetached(job.download)
        if log then
            job.log_tail = log:sub(-300)
            local percent = YouTube.parseProgress(log)
            if percent then job.percent = percent * 0.4 end
            job.stage_message = percent
                and string.format(_("Downloading audio %d%%"), math.floor(percent))
                or _("Downloading audio")
        end
        if code ~= nil then
            job.download = nil
            local source_handle = io.open(job.source_file, "rb")
            if code ~= 0 or not source_handle then
                job.log_tail = trim((log or ""):sub(-700))
                self:_failJob(instance, context, job, YouTube.describeDownloadFailure(log))
                return
            end
            source_handle:close()
            job.video_id = job.video_id or tostring(job.source):match("[?&]v=([%w%-_]+)")
            job.percent = 45
            self:_startConversionStage(instance, context, job)
        end
    elseif job.stage == "convert" then
        if not job.convert then
            self:_failJob(instance, context, job, _("The conversion could not be started."))
            return
        end
        local code, log = Music._pollDetached(job.convert)
        if code ~= nil then
            job.convert = nil
            if code ~= 0 then
                job.log_tail = trim((log or ""):sub(-500))
                self:_failJob(instance, context, job, _("The audio track could not be converted to WAV."))
                return
            end
            job.percent = 96
            self:_finishJob(instance, context, job)
            return
        end
        job.stage_message = _("Converting to WAV")
    else
        return
    end

    setBarRatio(job.progress_widget, (job.percent or 0) / 100)
    if job.stage_widget and job.stage_widget.setText then
        job.stage_widget:setText(YouTube.fitText(job.stage_message or "", job.stage_widget_width or 160, 11))
    end
    local manager = context and context.manager
    if not manager or not context.host or manager.active_host == context.host then
        if context and context.requestRebuild then context.requestRebuild("fast")
        elseif context and context.requestRefresh then context.requestRefresh("fast") end
    end
    if job.stage == "error" then return end
    if state.job == job then
        UIManager:scheduleIn(job.interval or 1, job.tick)
    end
end

----------------------------------------------------------------
-- Panes
----------------------------------------------------------------

function Music:_paneShell(width, height)
    return OverlapGroup:new{
        dimen = Geom:new{ w = width, h = height },
        allow_mirroring = false,
        FrameContainer:new{
            width = width, height = height, padding = 0, bordersize = 0,
            background = Blitbuffer.COLOR_WHITE,
            emptySizedWidget(width, height),
        },
    }
end

function Music:_buildCover(cover_path, box_width, box_height)
    local widget
    if cover_path and fileExists(cover_path) then
        widget = Wallpaper.buildPath(cover_path, box_width, box_height, true)
    end
    if widget then
        return CenterContainer:new{ dimen = Geom:new{ w = box_width, h = box_height }, widget }
    end
    local placeholder = TextWidget:new{
        text = "♪",
        face = Font:getFace("cfont", scale(48)),
        fgcolor = Blitbuffer.COLOR_WHITE,
        padding = 0,
    }
    return CenterContainer:new{
        dimen = Geom:new{ w = box_width, h = box_height },
        FrameContainer:new{
            width = box_width, height = box_height, padding = 0, bordersize = 0,
            background = Blitbuffer.COLOR_GRAY_8,
            emptySizedWidget(box_width, box_height),
            CenterContainer:new{ dimen = Geom:new{ w = box_width, h = box_height }, placeholder },
        },
    }
end

function Music:_buildHomePane(instance, context, state)
    local width, height = context.dimen.w, context.dimen.h
    local margin, gap = scale(12), scale(8)
    local content = self:_paneShell(width, height)
    local library = self:_library(instance, context)

    -- The host already labels the window "YouTube Music"; show the page name
    -- here instead of duplicating the app title inside the pane.
    local header = TextWidget:new{
        text = _("Home"),
        face = Font:getFace("cfont", scale(17)),
        bold = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
        padding = 0,
    }
    header.overlap_offset = { margin, scale(8) }
    table.insert(content, header)

    local settings_pill = Pill:new{
        text = _("Tools"),
        width = scale(84),
        height = scale(30),
        background = Blitbuffer.COLOR_GRAY_7,
        callback = function()
            state.view = "tools"
            if context.requestRebuild then context.requestRebuild("ui") end
        end,
        overlap_offset = { width - margin - scale(84), scale(6) },
    }
    table.insert(content, settings_pill)

    local search_pill = Pill:new{
        text = "⌕  " .. _("Search music"),
        width = width - 2 * margin,
        height = scale(36),
        background = Blitbuffer.COLOR_GRAY_8,
        callback = function() self:promptSearch(instance, context) end,
        overlap_offset = { margin, scale(38) },
    }
    table.insert(content, search_pill)

    local hero_top = scale(82)
    local hero_height = math.max(scale(132), math.floor(height * 0.26))
    local selected
    for _, entry in ipairs(library) do
        if entry.path == state.selected_path then selected = entry break end
    end
    selected = selected or library[1]
    if selected then state.selected_path = selected.path end

    local playing = state.play and selected and state.play.path == selected.path
    if selected then
        local cover_box_w = math.floor(hero_height * 16 / 9)
        cover_box_w = math.min(cover_box_w, math.floor(width * 0.5))
        local cover = self:_buildCover(selected.cover, cover_box_w, hero_height)
        cover.overlap_offset = { margin, hero_top }
        table.insert(content, cover)

        local info_x = margin + cover_box_w + gap
        local info_width = math.max(scale(80), width - info_x - margin)
        local title = TextWidget:new{
            text = YouTube.fitText(selected.title, info_width, 14),
            face = Font:getFace("cfont", scale(14)),
            bold = true,
            fgcolor = Blitbuffer.COLOR_BLACK,
            max_width = info_width,
            padding = 0,
        }
        title.overlap_offset = { info_x, hero_top + scale(4) }
        table.insert(content, title)

        local detail = TextWidget:new{
            text = playing
                and Music.formatPosition(self:_elapsed(state.play, monotonicNow()), state.play.duration)
                or YouTube.formatDuration(selected.duration),
            face = Font:getFace("smallinfofont", scale(11)),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            max_width = info_width,
            padding = 0,
        }
        detail.overlap_offset = { info_x, hero_top + scale(26) }
        table.insert(content, detail)
        if playing then state.play.time_widget = detail end

        table.insert(content, Pill:new{
            text = (playing and not state.play.paused) and ("Ⅱ  " .. _("Pause")) or ("▶  " .. _("Play")),
            width = math.min(scale(110), info_width),
            height = scale(32),
            background = Blitbuffer.COLOR_LIGHT_GRAY,
            callback = function() self:playEntry(instance, context, selected.path, 0) end,
            overlap_offset = { info_x, hero_top + hero_height - scale(34) },
        })
    else
        -- A useful, intentional empty state instead of a dead Play button and
        -- a large blank pane.
        local card_width = width - 2 * margin
        table.insert(content, FrameContainer:new{
            width = card_width, height = hero_height,
            padding = 0, bordersize = scale(1), color = Blitbuffer.COLOR_GRAY_7,
            radius = scale(10), background = Blitbuffer.COLOR_LIGHT_GRAY,
            emptySizedWidget(card_width, hero_height),
            overlap_offset = { margin, hero_top },
        })
        local empty_title = TextWidget:new{
            text = _("Your music starts here"),
            face = Font:getFace("cfont", scale(16)),
            bold = true, fgcolor = Blitbuffer.COLOR_BLACK, padding = 0,
        }
        empty_title.overlap_offset = {
            math.floor((width - empty_title:getSize().w) / 2), hero_top + scale(22),
        }
        table.insert(content, empty_title)
        local hint_text = YouTube.fitText(
            _("Search for a song, artist or album. Saved tracks will appear in your library."),
            card_width - scale(24), 10)
        local empty_hint = TextWidget:new{
            text = hint_text,
            face = Font:getFace("smallinfofont", scale(10)),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            max_width = card_width - scale(24),
            padding = 0,
        }
        empty_hint.overlap_offset = {
            margin + math.floor((card_width - empty_hint:getSize().w) / 2), hero_top + scale(54),
        }
        table.insert(content, empty_hint)
        local cta_width = math.min(scale(150), card_width - scale(24))
        table.insert(content, Pill:new{
            text = "⌕  " .. _("Search music"),
            width = cta_width, height = scale(34),
            background = Blitbuffer.COLOR_GRAY_8,
            callback = function() self:promptSearch(instance, context) end,
            overlap_offset = {
                math.floor((width - cta_width) / 2), hero_top + hero_height - scale(46),
            },
        })
    end

    local list_top = hero_top + hero_height + scale(10)
    local row_height, row_gap = scale(52), scale(6)
    local footer_height = scale(34)
    local available = math.max(row_height, height - list_top - footer_height - scale(8))
    local per_page = math.max(1, math.floor(available / (row_height + row_gap)))
    local total_pages = math.max(1, math.ceil(#library / per_page))
    state.library_page = clamp(state.library_page or 1, 1, total_pages)
    local first = (state.library_page - 1) * per_page
    for slot = 1, per_page do
        local entry = library[first + slot]
        if not entry then break end
        local row = Row:new{
            title = entry.title,
            subtitle = entry.has_cover and _("With cover art") or _("No cover art"),
            value = YouTube.formatDuration(entry.duration) or YouTube.humanSize(entry.size),
            width = width - 2 * margin,
            height = row_height,
            video_card = true,
            thumbnail_path = entry.cover,
            callback = function() self:playEntry(instance, context, entry.path, 0) end,
            hold_callback = function()
                local dialog
                dialog = AppDockDialogs.ButtonDialog:new{
                    title = entry.title,
                    buttons = {
                        {
                            {
                                text = _("Play"),
                                callback = function()
                                    UIManager:close(dialog)
                                    self:playEntry(instance, context, entry.path, 0)
                                end,
                            },
                            {
                                text = _("Delete"),
                                callback = function()
                                    UIManager:close(dialog)
                                    if state.play and state.play.path == entry.path then self:stopPlayback(instance) end
                                    os.remove(entry.path)
                                    os.remove(entry.cover)
                                    os.remove(self:artistPathFor(entry.path))
                                    self:scanLibrary(instance, context)
                                    self:_notify(instance, context, _("Track deleted."))
                                    if context.requestRebuild then context.requestRebuild("ui") end
                                end,
                            },
                        },
                    },
                }
                UIManager:show(dialog)
            end,
        }
        row.overlap_offset = { margin, list_top + (slot - 1) * (row_height + row_gap) }
        table.insert(content, row)
    end

    local footer_y = height - footer_height
    if #library > 0 and total_pages > 1 then
        local page_width = scale(120)
        local pager_left = Pill:new{
            text = "‹ " .. _("Back"),
            width = page_width, height = scale(30),
            background = Blitbuffer.COLOR_GRAY_8,
            callback = function()
                state.library_page = math.max(1, state.library_page - 1)
                if context.requestRebuild then context.requestRebuild("ui") end
            end,
            overlap_offset = { margin, footer_y },
        }
        local pager_right = Pill:new{
            text = _("More") .. " ›",
            width = page_width, height = scale(30),
            background = Blitbuffer.COLOR_GRAY_8,
            callback = function()
                state.library_page = math.min(total_pages, state.library_page + 1)
                if context.requestRebuild then context.requestRebuild("ui") end
            end,
            overlap_offset = { width - margin - page_width, footer_y },
        }
        local page_label = TextWidget:new{
            text = string.format(_("Page %d of %d"), state.library_page, total_pages),
            face = Font:getFace("smallinfofont", scale(10)),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            padding = 0,
        }
        page_label.overlap_offset = {
            math.floor((width - page_label:getSize().w) / 2), footer_y + scale(8) }
        table.insert(content, pager_left)
        table.insert(content, pager_right)
        table.insert(content, page_label)
    end

    if state.note and state.note ~= "" then
        local note = TextWidget:new{
            text = YouTube.fitText(state.note, width - 2 * margin, 9),
            face = Font:getFace("smallinfofont", scale(9)),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            max_width = width - 2 * margin,
            padding = 0,
        }
        note.overlap_offset = { margin, height - scale(16) }
        table.insert(content, note)
    end
    return content
end

function Music:_buildSearchPane(instance, context, state)
    local width, height = context.dimen.w, context.dimen.h
    local margin = scale(18)
    local gap = scale(8)
    local content = self:_paneShell(width, height)
    local failed = state.view == "search_error"
    local title = TextWidget:new{
        text = failed and _("YouTube Music search did not return results") or _("Searching YouTube Music"),
        face = Font:getFace("cfont", scale(17)),
        bold = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
        padding = 0,
    }
    title.overlap_offset = { margin, scale(24) }
    table.insert(content, title)
    if failed then
        local diagnostic = TextBoxWidget:new{
            text = state.search_error or "",
            face = Font:getFace("smallinfofont", scale(10)),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            width = width - 2 * margin,
            alignment = "left",
        }
        diagnostic.overlap_offset = { margin, scale(62) }
        table.insert(content, diagnostic)
        local button_width = math.floor((width - 2 * margin - gap) / 2)
        table.insert(content, Pill:new{
            text = "‹ " .. _("Back to library"),
            width = button_width, height = scale(34),
            background = Blitbuffer.COLOR_GRAY_8,
            callback = function()
                state.view, state.search_error = "home", nil
                if context.requestRebuild then context.requestRebuild("ui") end
            end,
            overlap_offset = { margin, scale(152) },
        })
        table.insert(content, Pill:new{
            text = _("Try again"),
            width = button_width, height = scale(34),
            background = Blitbuffer.COLOR_LIGHT_GRAY,
            callback = function() self:startSearch(instance, context, state.search_query or "") end,
            overlap_offset = { margin + button_width + gap, scale(152) },
        })
    else
        local note = TextWidget:new{
            text = YouTube.fitText(state.note or "", width - 2 * margin, 10),
            face = Font:getFace("smallinfofont", scale(10)),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            max_width = width - 2 * margin,
            padding = 0,
        }
        note.overlap_offset = { margin, scale(92) }
        table.insert(content, note)
        local bar = ProgressBar:new{
            width = width - 2 * margin, height = scale(18),
            indeterminate = true, position = 0.5,
        }
        bar.overlap_offset = { margin, scale(60) }
        table.insert(content, bar)
    end
    return content
end

function Music:_buildResultsPane(instance, context, state)
    local width, height = context.dimen.w, context.dimen.h
    local margin, gap = scale(12), scale(6)
    local content = self:_paneShell(width, height)
    local back = Pill:new{
        text = "‹ " .. _("Back"),
        width = scale(76), height = scale(30),
        background = Blitbuffer.COLOR_GRAY_8,
        callback = function()
            state.view = "home"
            if context.requestRebuild then context.requestRebuild("ui") end
        end,
        overlap_offset = { margin, scale(10) },
    }
    table.insert(content, back)
    local title = TextWidget:new{
        text = YouTube.fitText((state.search_query and state.search_query ~= "")
            and (_("Results: ") .. state.search_query) or _("Results"), width - 2 * margin - scale(92), 14),
        face = Font:getFace("cfont", scale(17)),
        bold = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
        padding = 0,
    }
    title.overlap_offset = { margin + scale(84), scale(14) }
    table.insert(content, title)

    local results = state.results or {}
    local row_height, row_gap = scale(52), scale(6)
    local top = scale(48)
    local footer_height = scale(34)
    local available = math.max(row_height, height - top - footer_height - scale(6))
    local per_page = math.max(1, math.floor(available / (row_height + row_gap)))
    local total_pages = math.max(1, math.ceil(#results / per_page))
    state.results_page = clamp(state.results_page or 1, 1, total_pages)
    local first = (state.results_page - 1) * per_page
    for slot = 1, per_page do
        local result = results[first + slot]
        if not result then break end
        local row = Row:new{
            title = result.title,
            subtitle = result.uploader or result.id,
            value = YouTube.formatDuration(result.duration) or _("Audio"),
            width = width - 2 * margin,
            height = row_height,
            video_card = true,
            thumbnail_path = result.thumbnail_path,
            callback = function() self:startDownload(instance, context, result) end,
        }
        row.overlap_offset = { margin, top + (slot - 1) * (row_height + row_gap) }
        table.insert(content, row)
    end

    if total_pages > 1 then
        local page_width = scale(120)
        local footer_y = height - footer_height
        table.insert(content, Pill:new{
            text = "‹ " .. _("Back"), width = page_width, height = scale(30),
            background = Blitbuffer.COLOR_GRAY_8,
            callback = function()
                state.results_page = math.max(1, state.results_page - 1)
                if context.requestRebuild then context.requestRebuild("ui") end
            end,
            overlap_offset = { margin, footer_y },
        })
        table.insert(content, Pill:new{
            text = _("More") .. " ›", width = page_width, height = scale(30),
            background = Blitbuffer.COLOR_GRAY_8,
            callback = function()
                state.results_page = math.min(total_pages, state.results_page + 1)
                if context.requestRebuild then context.requestRebuild("ui") end
            end,
            overlap_offset = { width - margin - page_width, footer_y },
        })
    end
    local hint = TextWidget:new{
        text = _("Tap a result to download its audio and cover. No video is downloaded or converted."),
        face = Font:getFace("smallinfofont", scale(9)),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        max_width = width - 2 * margin,
        padding = 0,
    }
    hint.overlap_offset = { margin, height - scale(18) }
    table.insert(content, hint)
    return content
end

function Music:_buildJobPane(instance, context, state)
    local width, height = context.dimen.w, context.dimen.h
    local margin = scale(12)
    local job = state.job
    local content = self:_paneShell(width, height)
    local title = TextWidget:new{
        text = YouTube.fitText(job and job.title or _("Track"), width - 2 * margin, 16),
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
        width = width - 2 * margin, height = scale(18),
    }
    if job then job.progress_widget = bar end
    bar.overlap_offset = { margin, scale(48) }
    table.insert(content, bar)
    local stage = TextWidget:new{
        text = YouTube.fitText(job and job.stage_message or "", width - 2 * margin, 11),
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
            text = YouTube.fitText(trim(job.log_tail:gsub("%s+", " ")), width - 2 * margin, 9),
            face = Font:getFace("smallinfofont", scale(9)),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            max_width = width - 2 * margin,
            padding = 0,
        }
        log.overlap_offset = { margin, scale(96) }
        table.insert(content, log)
    end
    local button_width = math.floor((width - 2 * margin - scale(6)) / 2)
    table.insert(content, Pill:new{
        text = (job and job.stage == "error") and _("Back") or _("Cancel"),
        width = button_width, height = scale(34),
        background = Blitbuffer.COLOR_GRAY_7,
        callback = function() self:cancelJob(instance, context) end,
        overlap_offset = { margin, height - scale(48) },
    })
    local hint = TextWidget:new{
        text = (job and job.stage == "error")
            and _("Adjust the tools or the folder and start again.")
            or _("AppDock stays responsive; you can leave this screen and the download keeps running."),
        face = Font:getFace("smallinfofont", scale(9)),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        max_width = width - 2 * margin - button_width - scale(6),
        padding = 0,
    }
    hint.overlap_offset = { margin + button_width + scale(6), height - scale(44) }
    table.insert(content, hint)
    return content
end

function Music:skipTrack(instance, context, direction)
    local state = self:_state(instance)
    local play = state.play
    local library = self:_library(instance, context)
    if #library == 0 then return false end
    local current = 1
    for index, entry in ipairs(library) do
        if play and entry.path == play.path then current = index; break end
    end
    if state.shuffle and #library > 1 and (tonumber(direction) or 1) > 0 then
        local next_index = current
        while next_index == current do next_index = math.random(1, #library) end
        return self:playEntry(instance, context, library[next_index].path, 0)
    end
    local next_index = ((current - 1 + (tonumber(direction) or 1)) % #library) + 1
    return self:playEntry(instance, context, library[next_index].path, 0)
end

function Music:_buildPlayerPane(instance, context, state)
    local width, height = context.dimen.w, context.dimen.h
    local margin, gap = scale(18), scale(8)
    local dark = height >= scale(500)
    local content = OverlapGroup:new{
        dimen = Geom:new{ w = width, h = height },
        allow_mirroring = false,
        FrameContainer:new{
            width = width, height = height, padding = 0, bordersize = 0,
            background = Blitbuffer.COLOR_BLACK,
            emptySizedWidget(width, height),
        },
    }
    local play = state.play
    local entry
    for _, candidate in ipairs(self:_library(instance, context)) do
        if candidate.path == (play and play.path) then entry = candidate break end
    end
    local white = Blitbuffer.COLOR_WHITE
    local dim = Blitbuffer.COLOR_GRAY_8
    local back = Pill:new{
        text = "⌄", width = scale(42), height = scale(34), font_size = 18,
        background = Blitbuffer.COLOR_BLACK, foreground = white,
        callback = function()
            state.view = "home"
            if context.requestRebuild then context.requestRebuild("ui") end
        end,
        overlap_offset = { margin, scale(5) },
    }
    table.insert(content, back)
    local header = TextWidget:new{
        text = "YouTube Music",
        face = Font:getFace("cfont", scale(14)),
        fgcolor = white,
        padding = 0,
    }
    header.overlap_offset = { margin + scale(48), scale(13) }
    table.insert(content, header)
    local mode = TextWidget:new{
        text = "♫  AUDIO",
        face = Font:getFace("smallinfofont", scale(10)),
        bold = true,
        fgcolor = white,
        padding = 0,
    }
    local mode_size = mode:getSize()
    mode.overlap_offset = { math.floor((width - mode_size.w) / 2), scale(14) }
    table.insert(content, mode)
    local tools = Pill:new{
        text = "⋮", width = scale(36), height = scale(34), font_size = 18,
        background = Blitbuffer.COLOR_BLACK, foreground = white,
        callback = function()
            state.view = "tools"
            if context.requestRebuild then context.requestRebuild("ui") end
        end,
        overlap_offset = { width - margin - scale(36), scale(5) },
    }
    table.insert(content, tools)

    local cover_top = scale(48)
    local cover_size
    if dark then
        cover_size = math.min(width - 2 * margin, math.floor(height * 0.41), height - scale(360))
    else
        cover_size = math.min(width - 2 * margin, math.floor(height * 0.30))
    end
    cover_size = math.max(scale(90), cover_size)
    local cover = self:_buildCover(entry and entry.cover or self:coverPathFor(play and play.path), cover_size, cover_size)
    cover.overlap_offset = { math.floor((width - cover_size) / 2), cover_top }
    table.insert(content, cover)

    local title_y = cover_top + cover_size + scale(14)
    local title = TextWidget:new{
        text = YouTube.fitText(play and play.title or "", width - 2 * margin, 16),
        face = Font:getFace("cfont", scale(16)),
        bold = true,
        fgcolor = white,
        max_width = width - 2 * margin,
        padding = 0,
    }
    title.overlap_offset = { margin, title_y }
    table.insert(content, title)
    local artist = TextWidget:new{
        text = YouTube.fitText(play and play.artist ~= "" and play.artist or (entry and entry.artist or "YouTube Music"), width - 2 * margin, 12),
        face = Font:getFace("smallinfofont", scale(12)),
        fgcolor = dim,
        max_width = width - 2 * margin,
        padding = 0,
    }
    artist.overlap_offset = { margin, title_y + scale(25) }
    table.insert(content, artist)

    local info_y = title_y + scale(48)
    if dark then
        local chip_gap = scale(8)
        local chip_width = math.floor((width - 2 * margin - 2 * chip_gap) / 3)
        local like_key = play and play.path or ""
        local liked = state.liked_paths and state.liked_paths[like_key]
        table.insert(content, Pill:new{
            text = liked and "♥  Liked" or "♡  Like", width = chip_width, height = scale(32),
            background = dim, foreground = white,
            callback = function()
                state.liked_paths = state.liked_paths or {}
                state.liked_paths[like_key] = not state.liked_paths[like_key]
                if context.requestRebuild then context.requestRebuild("ui") end
            end,
            overlap_offset = { margin, info_y },
        })
        table.insert(content, Pill:new{
            text = "▤  Saved", width = chip_width, height = scale(32),
            background = dim, foreground = white,
            callback = function()
                UIManager:show(AppDockDialogs.InfoMessage:new{
                    text = (play and play.title or "") .. "\n\n" .. (play and play.path or ""),
                })
            end,
            overlap_offset = { margin + chip_width + chip_gap, info_y },
        })
        table.insert(content, Pill:new{
            text = "⋯  More", width = chip_width, height = scale(32),
            background = dim, foreground = white,
            callback = function()
                UIManager:show(AppDockDialogs.InfoMessage:new{
                    text = (play and play.title or "") .. "\n\n" .. (play and play.artist or "YouTube Music"),
                })
            end,
            overlap_offset = { margin + 2 * (chip_width + chip_gap), info_y },
        })
    end

    local bar_y = info_y + (dark and scale(44) or scale(10))
    local bar = ProgressBar:new{
        ratio = play and play.duration and play.duration > 0
            and clamp(self:_elapsed(play, monotonicNow()) / play.duration, 0, 1) or 0,
        width = width - 2 * margin, height = scale(10),
        background_color = dim, foreground_color = white, border_color = dim,
    }
    bar.overlap_offset = { margin, bar_y }
    table.insert(content, bar)
    if play then play.progress_widget = bar end
    local time_widget = TextWidget:new{
        text = Music.formatPosition(self:_elapsed(play, monotonicNow())),
        face = Font:getFace("smallinfofont", scale(10)),
        fgcolor = dim,
        padding = 0,
    }
    time_widget.overlap_offset = { margin, bar_y + scale(14) }
    table.insert(content, time_widget)
    if play then play.time_widget = time_widget end
    local duration_widget = TextWidget:new{
        text = play and play.duration and Music.formatPosition(play.duration) or "0:00",
        face = Font:getFace("smallinfofont", scale(10)),
        fgcolor = dim,
        padding = 0,
    }
    local duration_size = duration_widget:getSize()
    duration_widget.overlap_offset = { width - margin - duration_size.w, bar_y + scale(14) }
    table.insert(content, duration_widget)

    local controls_y = bar_y + scale(38)
    local control_gap = scale(6)
    local control_width = math.floor((width - 2 * margin - 4 * control_gap) / 5)
    local paused = play and play.paused
    local controls = {
        { text = "⤨", callback = function() state.shuffle = not state.shuffle end },
        { text = "|◀", callback = function() self:skipTrack(instance, context, -1) end },
        { text = paused and "▶" or "Ⅱ", primary = true, callback = function() self:togglePlayback(instance, context) end },
        { text = "▶|", callback = function() self:skipTrack(instance, context, 1) end },
        { text = state.repeat_track and "↻ 1" or "↻", callback = function() state.repeat_track = not state.repeat_track end },
    }
    for index, control in ipairs(controls) do
        local button = control
        table.insert(content, Pill:new{
            text = button.text,
            width = button.primary and scale(52) or control_width,
            height = button.primary and scale(52) or scale(42),
            font_size = button.primary and 23 or 17,
            background = button.primary and white or Blitbuffer.COLOR_BLACK,
            foreground = button.primary and Blitbuffer.COLOR_BLACK or white,
            callback = function()
                button.callback()
                if context.requestRebuild then context.requestRebuild("ui") end
            end,
            overlap_offset = {
                button.primary and math.floor((width - scale(52)) / 2) or (margin + (index - 1) * (control_width + control_gap)),
                controls_y,
            },
        })
    end

    if dark then
        local footer_y = height - scale(34)
        local divider = FrameContainer:new{
            width = width - 2 * margin, height = scale(1), padding = 0, bordersize = 0,
            background = dim, emptySizedWidget(width - 2 * margin, scale(1)),
        }
        divider.overlap_offset = { margin, footer_y - scale(8) }
        table.insert(content, divider)
        local mix = TextWidget:new{
            text = YouTube.fitText("Mix — " .. (play and play.title or "YouTube Music"), width - 2 * margin, 11),
            face = Font:getFace("smallinfofont", scale(11)),
            fgcolor = white,
            max_width = width - 2 * margin,
            padding = 0,
        }
        local mix_size = mix:getSize()
        mix.overlap_offset = { math.floor((width - mix_size.w) / 2), footer_y + scale(2) }
        table.insert(content, mix)
    end
    return content
end

function Music:_buildToolsPane(instance, context, state)
    local width, height = context.dimen.w, context.dimen.h
    local margin, gap = scale(12), scale(6)
    local settings = self:_settings()
    local tools = state.tools or YouTube.detectTools(settings)
    local content = self:_paneShell(width, height)
    local back = Pill:new{
        text = "‹ " .. _("Back"),
        width = scale(76), height = scale(30),
        background = Blitbuffer.COLOR_GRAY_8,
        callback = function()
            state.view = "home"
            if context.requestRebuild then context.requestRebuild("ui") end
        end,
        overlap_offset = { margin, scale(10) },
    }
    table.insert(content, back)
    local title = TextWidget:new{
        text = _("Music tools"),
        face = Font:getFace("cfont", scale(17)),
        bold = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
        padding = 0,
    }
    title.overlap_offset = { margin + scale(84), scale(14) }
    table.insert(content, title)

    local rows = {
        {
            title = "yt-dlp",
            subtitle = tools.ytdlp or _("Not found. Tap to enter the path."),
            value = tools.ytdlp and _("Found") or _("Missing"),
            action = function()
                self:editSetting(instance, context, "ytdlp_path", _("yt-dlp path"),
                    _("Absolute path to the yt-dlp executable"))
            end,
        },
        {
            title = "ffmpeg",
            subtitle = tools.ffmpeg or _("Not found. Tap to enter the path."),
            value = tools.ffmpeg and _("Found") or _("Missing"),
            action = function()
                self:editSetting(instance, context, "ffmpeg_path", _("ffmpeg path"),
                    _("Absolute path to the ffmpeg executable"))
            end,
        },
        {
            title = _("Music folder"),
            subtitle = self:musicDirectory(),
            value = _("Edit"),
            action = function()
                self:editSetting(instance, context, "music_dir", _("Music folder"),
                    _("Absolute folder for .wav tracks and their .jpg covers"))
            end,
        },
        {
            title = _("Maximum length"),
            subtitle = _("Longer tracks need more space on the reader"),
            value = YouTube.durationLabel(settings.max_duration),
            action = function()
                self:_patchSettings({ max_duration = YouTube.cycle(YouTube.DURATIONS, settings.max_duration) })
                self:refreshPane(context)
            end,
        },
    }

    local row_height = scale(48)
    local top = scale(48)
    for index, row in ipairs(rows) do
        local widget = Row:new{
            title = row.title,
            subtitle = row.subtitle,
            value = row.value,
            width = width - 2 * margin,
            height = row_height,
            callback = row.action,
        }
        widget.overlap_offset = { margin, top + (index - 1) * (row_height + gap) }
        table.insert(content, widget)
    end

    local detect = Pill:new{
        text = _("Detect tools again"),
        width = scale(150), height = scale(32),
        background = Blitbuffer.COLOR_GRAY_8,
        callback = function()
            state.tools = YouTube.detectTools(self:_settings())
            if state.tools.ready then
                self:_notify(instance, context, _("yt-dlp and ffmpeg are ready."))
            else
                self:_notify(instance, context, _("yt-dlp or ffmpeg is still missing."))
            end
            if context.requestRebuild then context.requestRebuild("ui") end
        end,
        overlap_offset = { margin, height - scale(84) },
    }
    table.insert(content, detect)

    local setup = Pill:new{
        text = _("Automatic setup"),
        width = scale(150), height = scale(32),
        background = Blitbuffer.COLOR_GRAY_6,
        callback = function()
            local youtube = self:_youtube()
            if not youtube then
                self:_notify(instance, context, _("Automatic setup is unavailable right now."))
                return
            end
            local youtube_state = youtube:_state(instance)
            youtube_state.bootstrap = nil
            youtube_state.bootstrap_attempted = false
            state.view = "setup"
            youtube:_startToolBootstrap(instance, context)
        end,
        overlap_offset = { width - margin - scale(150), height - scale(84) },
    }
    table.insert(content, setup)

    local hint = TextWidget:new{
        text = _("YouTube Music uses the same local yt-dlp and ffmpeg as the YouTube DApp. AppDock never bundles them."),
        face = Font:getFace("smallinfofont", scale(9)),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        max_width = width - 2 * margin,
        padding = 0,
    }
    hint.overlap_offset = { margin, height - scale(44) }
    table.insert(content, hint)
    return content
end

function Music:editSetting(instance, context, key, title, hint)
    local settings = self:_settings()
    local dialog
    dialog = InputDialog:new{
        title = title,
        input = settings[key] or "",
        input_hint = hint,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function() UIManager:close(dialog) end,
                },
                {
                    text = _("Save"),
                    callback = function()
                        local value = trim(dialog:getInputText())
                        UIManager:close(dialog)
                        local patch = {}
                        patch[key] = value
                        self:_patchSettings(patch)
                        local state = self:_state(instance)
                        state.tools = YouTube.detectTools(self:_settings())
                        self:_notify(instance, context, _("Saved."))
                        if context.requestRebuild then context.requestRebuild("ui") end
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    AppDockKeyboard.attach(dialog)
    dialog:onShowKeyboard()
    return true
end

function Music:refreshPane(context)
    if context and context.requestRebuild then context.requestRebuild("ui") end
end

function Music:buildPane(instance, context)
    local state = self:_state(instance)
    local tools = state.tools or YouTube.detectTools(self:_settings())
    state.tools = tools

    -- Missing tools reuse the YouTube setup flow: it installs the same two
    -- executables and reports its live progress with the same pane.
    -- Search results only require yt-dlp. Do not replace an active search,
    -- its diagnostics, or the results list with the shared setup pane merely
    -- because ffmpeg is unavailable; ffmpeg is needed only when a result is
    -- selected for conversion.
    if not tools.ready and (state.view == "home" or state.view == "tools") then
        local youtube = self:_youtube()
        if youtube and youtube._buildSetupPane then
            local youtube_state = youtube:_state(instance)
            if not youtube_state.bootstrap_attempted and not (self.appdock and self.appdock.disableToolBootstrap) then
                youtube:_startToolBootstrap(instance, context, true)
            end
            local pane = WidgetContainer:new{ dimen = Geom:new{ w = context.dimen.w, h = context.dimen.h } }
            pane[1] = youtube:_buildSetupPane(instance, context, youtube_state)
            return pane
        end
    end

    local content
    if state.view == "player" and state.play then
        content = self:_buildPlayerPane(instance, context, state)
    elseif state.view == "results" then
        content = self:_buildResultsPane(instance, context, state)
    elseif state.view == "search" or state.view == "search_error" then
        content = self:_buildSearchPane(instance, context, state)
    elseif state.view == "job" and state.job then
        content = self:_buildJobPane(instance, context, state)
    elseif state.view == "tools" then
        content = self:_buildToolsPane(instance, context, state)
    else
        state.view = "home"
        content = self:_buildHomePane(instance, context, state)
    end

    local pane = WidgetContainer:new{ dimen = Geom:new{ w = context.dimen.w, h = context.dimen.h } }
    pane[1] = content
    pane.onDeactivate = function()
        -- Playback keeps running while the user leaves the pane, matching the
        -- YouTube MiniPlayer. The DApp definition stops it when the app closes.
    end
    return pane
end

function Music:onDAppClose(instance)
    self:stopPlayback(instance)
    local state = self:_state(instance)
    if state.job then
        -- A running download keeps going in the background; only the visible
        -- state is dropped so the next visit starts from the library.
        state.view = "home"
    end
    if state.search_handle then
        Music._killDetached(state.search_handle)
        state.search_handle = nil
        if state.search_work then cleanupDirectory(state.search_work) end
        state.search_work = nil
    end
end

Music._test = {
    buildSearchCommand = Music.buildSearchCommand,
    buildAudioDownloadCommand = Music.buildAudioDownloadCommand,
    buildWavCommand = Music.buildWavCommand,
    coverUrls = Music.coverUrls,
    buildCoverCommand = Music.buildCoverCommand,
    titleFromFile = titleFromFile,
    formatPosition = Music.formatPosition,
}

return Music
