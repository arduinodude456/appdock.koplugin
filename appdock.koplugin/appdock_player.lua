--[[--
AppDock BWR1 player: the playback half of the YouTube DApp.

Playback follows the design that the `videoplayer.koplugin` release "Snake"
proved on E-Ink hardware:

* audio is the master clock; the frame to show is computed from the actually
  elapsed playback time, so `UIManager:scheduleIn` jitter can never accumulate
  into a drift,
* frames are already dithered and only have to be expanded to bytes and blitted,
* the widget asks for a `fast` refresh of its own rectangle instead of a full
  screen update, which is what makes 12 frames per second readable on E-Ink.

Everything here stays inside `context.dimen`, so the same player works in the
full-screen host and in split screen.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")

local Audio = require("appdock_audio")
local BWR = require("appdock_bwr")

local Screen = Device.screen

local Player = {}
Player.__index = Player

local function scale(value)
    return Screen:scaleBySize(value)
end

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

local function basename(path)
    return (path or ""):match("([^/]+)$") or path or ""
end

-- TextWidget wraps at max_width, which would overflow the fixed header band,
-- so long names are shortened first.
local function fitText(text, max_width, font_size)
    text = tostring(text or "")
    local budget = math.max(4, math.floor(max_width / math.max(1, font_size * 0.5)))
    if #text <= budget then return text end
    return text:sub(1, budget - 1) .. "…"
end

local function emptySizedWidget(width, height)
    return CenterContainer:new{ dimen = Geom:new{ w = width, h = height }, HorizontalSpan:new{ width = 0 } }
end

local function formatTime(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

Player.formatTime = formatTime

-- Sub-second wall clock. `ui/time` is the KOReader source of truth; luasocket
-- covers builds without it, and os.time() is the last resort.
local now_seconds

do
    local ok, Time = pcall(require, "ui/time")
    if ok and Time and Time.now and Time.to_s then
        local converted, probe = pcall(function() return Time.to_s(Time.now()) end)
        if converted and type(probe) == "number" then
            now_seconds = function() return Time.to_s(Time.now()) end
        end
    end
    if not now_seconds then
        local ok, socket = pcall(require, "socket")
        if ok and socket and socket.gettime then
            now_seconds = socket.gettime
        end
    end
    if not now_seconds then
        logger.info("appdock youtube: falling back to os.time() for playback timing")
        now_seconds = os.time
    end
end

Player.now = function() return now_seconds() end

----------------------------------------------------------------
-- Frame canvas
----------------------------------------------------------------

local Canvas = InputContainer:extend{
    engine = nil,
    frame = nil,
    width = nil,
    height = nil,
    dimen = nil,
    origin_x = 0,
    origin_y = 0,
}

function Canvas:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
end

function Canvas:getSize()
    return self.dimen
end

function Canvas:setFrame(frame)
    self.frame = frame
end

function Canvas:paintTo(bb, x, y)
    self.origin_x, self.origin_y = x, y
    self.painted = true
    bb:paintRect(x, y, self.width, self.height, Blitbuffer.COLOR_BLACK)
    if not self.frame then return end
    local source = self.frame
    local source_w, source_h = source:getWidth(), source:getHeight()
    local draw_w = math.min(self.width, source_w)
    local draw_h = math.min(self.height, source_h)
    local source_x = math.max(0, math.floor((source_w - draw_w) / 2))
    local source_y = math.max(0, math.floor((source_h - draw_h) / 2))
    local target_x = x + math.max(0, math.floor((self.width - draw_w) / 2))
    local target_y = y + math.max(0, math.floor((self.height - draw_h) / 2))
    bb:blitFrom(source, target_x, target_y, source_x, source_y, draw_w, draw_h)
end

-- Repaints only this rectangle. A full `ui` refresh for every frame would make
-- playback unusable on E-Ink.
function Canvas:refresh()
    -- Before the first paint the rectangle is unknown; the host repaint that
    -- follows a control press draws the frame anyway.
    if not self.painted or not UIManager.setDirty then return end
    if UIManager.widgetRepaint then UIManager:widgetRepaint(self, self.origin_x, self.origin_y) end
    UIManager:setDirty(nil, "fast", Geom:new{ x = self.origin_x, y = self.origin_y, w = self.width, h = self.height })
    if UIManager.forceRePaint then UIManager:forceRePaint() end
    if UIManager.yieldToEPDC then UIManager:yieldToEPDC() end
end

----------------------------------------------------------------
-- Engine
----------------------------------------------------------------

local Engine = {}
Engine.__index = Engine
local AUDIO_START_POLL_INTERVAL = 0.05
local AUDIO_START_TIMEOUT = 8

function Engine.open(video_path, wav_path, report, video_delay)
    local handle = io.open(video_path, "rb")
    local instance = setmetatable({
        handle = handle,
        path = video_path,
        wav_path = wav_path,
        report = report,
        paused = true,
        closed = false,
        frame = nil,
        frame_index = -1,
        position = 0,
        video_delay = clamp(tonumber(video_delay) or 0, 0, 60),
        anchor_wall = nil,
        anchor_position = 0,
        pending_start = nil,
        canvas = nil,
    }, Engine)
    if not handle then
        instance.error = _("The BWR1 file cannot be opened.")
        return instance
    end
    local header, err = BWR.readHeader(handle)
    if not header then
        handle:close()
        instance.handle = nil
        instance.error = err
        return instance
    end
    instance.header = header
    instance.fps = header.fps
    instance.duration = BWR.durationSeconds(header)
    instance.period = 1 / instance.fps
    if wav_path then
        instance.audio_duration = Audio.durationOf(wav_path)
        instance.clock_scale = 1
        if instance.audio_duration and instance.audio_duration > 0 and instance.duration > 0 then
            local scale_to_audio = instance.duration / instance.audio_duration
            -- Compensate only small frame/audio duration differences; do not
            -- stretch an intentionally mismatched or malformed track.
            if scale_to_audio >= 0.97 and scale_to_audio <= 1.03 then
                instance.clock_scale = scale_to_audio
            end
        end
        instance.audio = Audio.new(wav_path)
        instance.audio_error = instance.audio:getError()
    end
    instance.tick = function() instance:step() end
    return instance
end

function Engine:setCanvas(canvas)
    self.canvas = canvas
    if canvas then canvas.engine = self end
end

function Engine:status(message)
    if self.report then self.report(message) end
end

function Engine:currentTime()
    if not self.anchor_wall then return clamp(self.position or 0, 0, self.duration) end
    local elapsed = Player.now() - self.anchor_wall
    if elapsed < 0 then elapsed = 0 end
    return clamp(self.anchor_position + elapsed * (self.clock_scale or 1), 0, self.duration)
end

function Engine:audioTime(video_position)
    local scale_to_video = self.clock_scale or 1
    return clamp((tonumber(video_position) or 0) / scale_to_video, 0,
        self.audio_duration or self.duration)
end

function Engine:readFrame(index)
    if not self.handle or index < 0 or index >= self.header.frames then
        return nil, _("The frame is outside the BWR1 file.")
    end
    self.handle:seek("set", BWR.HEADER_BYTES + index * self.header.frame_bytes)
    local packed = self.handle:read(self.header.frame_bytes)
    if not packed or #packed ~= self.header.frame_bytes then
        return nil, _("Cannot read a complete BWR1 frame.")
    end
    return packed
end

function Engine:show(position)
    local index = clamp(math.floor(position * self.fps), 0, self.header.frames - 1)
    if index ~= self.frame_index or not self.frame then
        local packed, err = self:readFrame(index)
        if not packed then return nil, err end
        local frame, expand_error = BWR.expandFrame(packed, self.header.width, self.header.height)
        if not frame then return nil, expand_error end
        if self.frame then self.frame:free() end
        self.frame = frame
        self.frame_index = index
        if self.canvas then self.canvas:setFrame(frame) end
    end
    if self.canvas then self.canvas:refresh() end
    return true
end

function Engine:play()
    if self.error then return nil, self.error end
    if self.pending_start then return true end
    if self.audio then
        local ok, err = self.audio:startFrom(self:audioTime(self.position or 0))
        if not ok then
            self.audio_error = err
            self:status(err)
        elseif self.audio.requiresStartConfirmation and self.audio:requiresStartConfirmation() then
            local ready, ready_error = self.audio:isPlaybackReady()
            if not ready and not ready_error then
                self.pending_start = {
                    position = self.position or 0,
                    deadline = Player.now() + AUDIO_START_TIMEOUT,
                }
                self.anchor_wall, self.paused = nil, false
                self:status(_("Waiting for the audio clock…"))
                UIManager:unschedule(self.tick)
                UIManager:scheduleIn(AUDIO_START_POLL_INTERVAL, self.tick)
                return true
            elseif ready then
                self.pending_start = {
                    position = self.position or 0,
                    deadline = Player.now() + self.video_delay,
                    clock_ready = true,
                }
                self.anchor_wall, self.paused = nil, false
                self:status(_("Audio clock active; waiting for audible output…"))
                UIManager:unschedule(self.tick)
                UIManager:scheduleIn(AUDIO_START_POLL_INTERVAL, self.tick)
                return true
            end
        end
        if ok and not self.audio:requiresStartConfirmation() and self.video_delay > 0 then
            self.pending_start = {
                position = self.position or 0,
                deadline = Player.now() + self.video_delay,
                clock_ready = true,
            }
            self.anchor_wall, self.paused = nil, false
            self:status(_("Audio started; waiting for video offset…"))
            UIManager:unschedule(self.tick)
            UIManager:scheduleIn(AUDIO_START_POLL_INTERVAL, self.tick)
            return true
        end
    else
        self:status(_("Playing without companion audio."))
    end
    self.anchor_position, self.anchor_wall, self.paused = self.position or 0, Player.now(), false
    local ok, err = self:show(self.position or 0)
    if not ok then
        self.paused = true
        return nil, err
    end
    UIManager:unschedule(self.tick)
    UIManager:scheduleIn(self.period, self.tick)
    return true
end

function Engine:pause()
    if self.pending_start then
        self.position = self.pending_start.position
        self.pending_start = nil
        self.anchor_wall, self.paused = nil, true
        if self.audio then self.audio:stop() end
        UIManager:unschedule(self.tick)
        return
    end
    if self.paused then return end
    self.position = self:currentTime()
    self.anchor_wall, self.paused = nil, true
    if self.audio then self.audio:stop() end
    UIManager:unschedule(self.tick)
end

function Engine:toggle()
    if self.paused then return self:play() end
    self:pause()
    self:status(_("Paused"))
    return true
end

function Engine:jump(seconds)
    if self.error then return nil, self.error end
    if self.pending_start then
        self.position = clamp(self.pending_start.position + (tonumber(seconds) or 0), 0, self.duration)
        if self.audio then
            local ok, err = self.audio:startFrom(self:audioTime(self.position))
            if not ok then
                self.audio_error = err
                self:status(err)
            else
                self.pending_start.position = self.position
                self.pending_start.clock_ready = false
                self.pending_start.deadline = Player.now() + AUDIO_START_TIMEOUT
            end
        end
        return self:show(self.position)
    end
    local base = self.paused and (self.position or 0) or self:currentTime()
    self.position = clamp(base + (tonumber(seconds) or 0), 0, self.duration)
    if self.paused then
        if self.audio then self.audio:stop() end
    else
        if self.audio then
            local ok, err = self.audio:startFrom(self:audioTime(self.position))
            if not ok then
                self.audio_error = err
                self:status(err)
            end
        end
        self.anchor_position, self.anchor_wall = self.position, Player.now()
        UIManager:unschedule(self.tick)
        UIManager:scheduleIn(self.period, self.tick)
    end
    return self:show(self.position)
end

function Engine:restart()
    self.position = 0
    if self.paused then
        if self.audio then self.audio:stop() end
        return self:show(0)
    end
    return self:jump(0)
end

function Engine:step()
    if self.closed then return end
    if self.pending_start then
        local now = Player.now()
        local ready, start_error = self.audio:isPlaybackReady()
        if not self.pending_start.clock_ready and ready then
            self.pending_start.clock_ready = true
            -- The MTK sink reports its clock only after the audio process has
            -- started. Keep the user-configured video offset from this point;
            -- startupLatency() is only an optional hardware baseline and must
            -- never replace the setting with zero.
            self.pending_start.deadline = now + self.video_delay + self.audio:startupLatency()
            self:status(_("Audio clock active; waiting for audible output…"))
            UIManager:scheduleIn(AUDIO_START_POLL_INTERVAL, self.tick)
            return
        end
        if start_error or now >= self.pending_start.deadline then
            local position = self.pending_start.position
            self.pending_start = nil
            if start_error then
                self.audio_error = start_error
                self:status(start_error)
            elseif not ready then
                -- Do not stop audio merely because this firmware omitted the
                -- optional New clock line; keep the proven 7.8.26 pipeline.
                self:status(_("Audio clock was not reported; continuing playback."))
            end
            self.anchor_position, self.anchor_wall, self.paused = position, Player.now(), false
            local ok, err = self:show(position)
            if not ok then
                self.paused = true
                if self.audio then self.audio:stop() end
                self:status(err)
            else
                UIManager:unschedule(self.tick)
                UIManager:scheduleIn(self.period, self.tick)
            end
            return
        end
        UIManager:scheduleIn(AUDIO_START_POLL_INTERVAL, self.tick)
        return
    end
    if self.paused then return end
    self.position = self:currentTime()
    if self.position >= self.duration then
        self:show(self.duration)
        self:pause()
        self:status(_("Finished"))
        return
    end
    local ok, err = self:show(self.position)
    if not ok then
        self:pause()
        self:status(err)
        return
    end
    UIManager:scheduleIn(self.period, self.tick)
end

function Engine:close()
    if self.closed then return end
    self.closed = true
    self:pause()
    if self.audio then self.audio:stop() end
    if self.frame then
        self.frame:free()
        self.frame = nil
    end
    if self.handle then
        self.handle:close()
        self.handle = nil
    end
end

----------------------------------------------------------------
-- Controls
----------------------------------------------------------------

local Action = InputContainer:extend{
    label = nil,
    callback = nil,
    width = nil,
    height = nil,
    background = nil,
    dimen = nil,
}

function Action:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self.text_widget = TextWidget:new{
        text = self.label or "",
        face = Font:getFace("smallinfofont", scale(11)),
        bold = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
        max_width = math.max(1, self.width - scale(8)),
    }
    self[1] = FrameContainer:new{
        width = self.width,
        height = self.height,
        padding = 0,
        bordersize = 0,
        radius = math.max(2, math.floor(self.height * 0.28)),
        background = self.background or Blitbuffer.COLOR_LIGHT_GRAY,
        self.text_widget,
    }
    self.ges_events = { TapPlayerAction = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function Action:getSize()
    return self.dimen
end

function Action:setLabel(label)
    self.label = label
    if self.text_widget then self.text_widget:setText(label) end
end

function Action:paintTo(bb, x, y)
    local range = self.ges_events.TapPlayerAction[1].range
    range.x, range.y, range.w, range.h = x, y, self.width, self.height
    return InputContainer.paintTo(self, bb, x, y)
end

function Action:onTapPlayerAction()
    if self.callback then self.callback() end
    return true
end

Player.Canvas = Canvas
Player.Action = Action
Player.Engine = Engine

----------------------------------------------------------------
-- Pane
----------------------------------------------------------------

local function companionFor(path)
    local wav = path:gsub("%.bwr$", ".wav")
    local handle = io.open(wav, "rb")
    if handle then
        handle:close()
        return wav
    end
    return nil
end

Player.companionFor = companionFor

function Player:new(appdock)
    return setmetatable({ appdock = appdock, engine = nil, path = nil, note = "" }, Player)
end

function Player:load(instance, context, path)
    if type(path) ~= "string" or path == "" then
        return nil, _("No video file was given.")
    end
    if not path:lower():match("%.bwr$") then
        return nil, _("AppDock plays BWR1 files only.")
    end
    self:stop()
    self.path = path
    local wav = companionFor(path)
    local video_delay = 0
    if self.appdock and type(self.appdock.getYouTubeSettings) == "function" then
        local stored = self.appdock:getYouTubeSettings()
        if type(stored) == "table" then video_delay = tonumber(stored.audio_video_delay) or 0 end
    end
    local engine = Engine.open(path, wav, function(message)
        self.note = message
        if context and context.requestRefresh then context.requestRefresh("ui") end
    end, video_delay)
    if engine.error then
        self.note = engine.error
        return nil, engine.error
    end
    self.engine = engine
    self.note = wav and _("Companion WAV audio is used.") or _("No companion WAV file was found.")
    return true
end

function Player:stop()
    if self.engine then
        self.engine:close()
        self.engine = nil
    end
end

-- `options.on_back` adds a Library button in the top right corner, so a DApp
-- can leave playback without relying on the host navigation.
function Player:buildPane(instance, context, options)
    options = options or {}
    local width, height = context.dimen.w, context.dimen.h
    local margin, gap = scale(10), scale(6)
    local row_height = scale(34)
    local title_height = scale(42)
    local status_height = scale(22)
    local canvas_height = math.max(scale(80), height - title_height - row_height - status_height - gap * 3)
    local button_width = math.max(scale(46), math.floor((width - 2 * margin - 3 * gap) / 4))
    local controls_y = title_height + canvas_height + gap

    local canvas = Canvas:new{ width = width - 2 * margin, height = canvas_height }
    if self.engine then self.engine:setCanvas(canvas) end

    local play_button
    local function control(name)
        local engine = self.engine
        if not engine then
            UIManager:show(InfoMessage:new{ text = _("No video is loaded.") })
            return
        end
        if name == "toggle" then
            engine:toggle()
            if play_button then play_button:setLabel(engine.paused and _("Play") or _("Pause")) end
        elseif name == "back" then
            engine:jump(-5)
        elseif name == "forward" then
            engine:jump(5)
        elseif name == "restart" then
            engine:restart()
            if play_button then play_button:setLabel(engine.paused and _("Play") or _("Pause")) end
        end
        context.requestRefresh("ui")
    end

    play_button = Action:new{
        label = (self.engine and not self.engine.paused) and _("Pause") or _("Play"),
        width = button_width,
        height = row_height,
        background = Blitbuffer.COLOR_GRAY_8,
        callback = function() control("toggle") end,
    }

    local library_button = options.on_back and Action:new{
        label = "‹ " .. _("Library"),
        width = scale(96),
        height = scale(28),
        background = Blitbuffer.COLOR_GRAY_7,
        callback = options.on_back,
    } or nil

    local header = TextWidget:new{
        text = fitText(_("E-Ink video") .. " · " .. basename(self.path or ""),
            library_button and (width - 2 * margin - library_button.width - scale(8)) or (width - 2 * margin), 15),
        face = Font:getFace("cfont", scale(15)),
        bold = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
        max_width = library_button and (width - 2 * margin - library_button.width - scale(8)) or (width - 2 * margin),
        padding = 0,
    }

    local header_hint = self.engine
        and (string.format("%d fps · %s", math.floor(self.engine.fps + 0.5), formatTime(self.engine.duration)))
        or _("No BWR1 file is loaded.")
    local hint = TextWidget:new{
        text = header_hint,
        face = Font:getFace("smallinfofont", scale(9)),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        max_width = width - 2 * margin,
        padding = 0,
    }

    local status = TextWidget:new{
        text = fitText(self.note or "", width - 2 * margin, 9),
        face = Font:getFace("smallinfofont", scale(9)),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        max_width = width - 2 * margin,
        padding = 0,
    }

    local back_button = Action:new{
        label = "-5 s", width = button_width, height = row_height,
        callback = function() control("back") end,
    }
    local forward_button = Action:new{
        label = "+5 s", width = button_width, height = row_height,
        callback = function() control("forward") end,
    }
    local restart_button = Action:new{
        label = _("Restart"), width = button_width, height = row_height,
        background = Blitbuffer.COLOR_GRAY_7,
        callback = function() control("restart") end,
    }

    header.overlap_offset = { margin, scale(6) }
    hint.overlap_offset = { margin, scale(26) }
    if library_button then
        library_button.overlap_offset = { width - margin - library_button.width, scale(6) }
    end
    canvas.overlap_offset = { margin, title_height }
    back_button.overlap_offset = { margin, controls_y }
    play_button.overlap_offset = { margin + button_width + gap, controls_y }
    forward_button.overlap_offset = { margin + 2 * (button_width + gap), controls_y }
    restart_button.overlap_offset = { margin + 3 * (button_width + gap), controls_y }
    status.overlap_offset = { margin, controls_y + row_height + scale(4) }

    local children = {
        FrameContainer:new{
            width = width,
            height = height,
            padding = 0,
            bordersize = 0,
            background = Blitbuffer.COLOR_WHITE,
            emptySizedWidget(width, height),
        },
        header,
        hint,
        canvas,
    }
    if library_button then table.insert(children, library_button) end
    table.insert(children, back_button)
    table.insert(children, play_button)
    table.insert(children, forward_button)
    table.insert(children, restart_button)
    table.insert(children, status)

    local pane = WidgetContainer:new{ dimen = Geom:new{ w = width, h = height } }
    local content = OverlapGroup:new{
        dimen = Geom:new{ w = width, h = height },
        allow_mirroring = false,
    }
    for _, child in ipairs(children) do table.insert(content, child) end
    pane[1] = content

    pane.onDeactivate = function()
        if self.engine then
            self.engine:pause()
            self.engine:close()
            self.engine = nil
        end
    end
    return pane
end

return Player
