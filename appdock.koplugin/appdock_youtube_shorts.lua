--[[--
AppDock YouTube Shorts: a vertical, short-only feed built on the existing
YouTube downloader/player. Search results are limited to <= 180 seconds,
likes are persisted as recommendation signals, and the next item is prepared
while the current item is playing.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/container/overlapgroup")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local YouTube = require("appdock_youtube")

local Shorts = setmetatable({}, { __index = YouTube })
Shorts.__index = Shorts

local function scale(value)
    local ok, Device = pcall(require, "device")
    return ok and Device.screen:scaleBySize(value) or value
end

local function trim(value)
    return type(value) == "string" and (value:match("^%s*(.-)%s*$") or "") or ""
end

local function shellQuote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function jobDirectory()
    local base = os.getenv("TMPDIR") or "/tmp"
    local path = string.format("%s/appdock-shorts-%d-%d", base, os.time(), math.random(1000, 9999))
    os.execute("mkdir -p " .. shellQuote(path) .. " >/dev/null 2>&1")
    return path
end

local function cleanupDirectory(path)
    if path then os.execute("rm -rf " .. shellQuote(path)) end
end

local Chip = InputContainer:extend{ title = "", symbol = "", width = 100, height = 34, callback = nil,
    background = Blitbuffer.COLOR_GRAY_8, foreground = Blitbuffer.COLOR_BLACK }
function Chip:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local text = (self.symbol or "") .. (self.symbol ~= "" and "  " or "") .. (self.title or "")
    self[1] = FrameContainer:new{
        width = self.width, height = self.height, padding = scale(4), bordersize = 0,
        background = self.background,
        CenterContainer:new{ dimen = Geom:new{ w = self.width - scale(8), h = self.height - scale(8) },
            TextWidget:new{ text = text, face = Font:getFace("smallinfofont", scale(10)),
                fgcolor = self.foreground, bold = true, padding = 0 } },
    }
    self.ges_events = { TapShortsAction = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end
function Chip:paintTo(bb, x, y)
    self.ges_events.TapShortsAction[1].range.x, self.ges_events.TapShortsAction[1].range.y = x, y
    return InputContainer.paintTo(self, bb, x, y)
end
function Chip:onTapShortsAction()
    if self.callback then self.callback() end
    return true
end

local function likedSet(text)
    local result = {}
    for id in tostring(text or ""):gmatch("[^,]+") do result[trim(id)] = true end
    return result
end

function Shorts:new(appdock)
    local instance = YouTube.new(self, appdock)
    setmetatable(instance, Shorts)
    instance.shorts = true
    return instance
end

function Shorts:_state(instance)
    local state = YouTube._state(self, instance)
    state.shorts = true
    state.shorts_likes = state.shorts_likes or likedSet(self.appdock and self.appdock:getYouTubeSettings().shorts_liked_ids)
    state.short_index = state.short_index or 1
    state.short_queue = state.short_queue or {}
    return state
end

function Shorts:_recommendationQuery(state)
    local settings = self.appdock and self.appdock:getYouTubeSettings() or {}
    local tags = trim(settings.shorts_hashtags or "")
    if tags == "" then tags = trim(state.query or "") end
    return tags ~= "" and (tags .. " #shorts") or "#shorts"
end

function Shorts:toggleLike(instance, context, result)
    local state = self:_state(instance)
    if not result or not result.id then return end
    state.shorts_likes[result.id] = not state.shorts_likes[result.id]
    local ids = {}
    for id, liked in pairs(state.shorts_likes) do if liked then ids[#ids + 1] = id end end
    table.sort(ids)
    if self.appdock and self.appdock.setYouTubeSettings then
        self.appdock:setYouTubeSettings({ shorts_liked_ids = table.concat(ids, ",") })
    end
    state.note = state.shorts_likes[result.id] and _("Liked · recommendations updated") or _("Like removed")
    if context and context.requestRebuild then context.requestRebuild("ui") end
end

function Shorts:startSearch(instance, context, query)
    local state = self:_state(instance)
    local tools = state.tools or YouTube.detectTools(self:_settings())
    state.tools = tools
    query = trim(query)
    if query == "" then return false end
    local search_query = query:lower():find("#shorts", 1, true) and query or (query .. " #shorts")
    if self.appdock and self.appdock.setYouTubeSettings then
        self.appdock:setYouTubeSettings({ shorts_hashtags = query:gsub("#shorts", ""):gsub("%s+", " "):match("^%s*(.-)%s*$") or "" })
    end
    if not tools.ytdlp then
        self:_notify(instance, context, _("yt-dlp was not found. Open Tool settings first."))
        return false
    end
    local work = jobDirectory()
    local command = shellQuote(tools.ytdlp)
        .. " --no-warnings --no-cache-dir --flat-playlist --ignore-errors"
        .. " --match-filter " .. shellQuote("duration <= 180")
        .. " --print " .. shellQuote("%(id)s\t%(title)s\t%(duration)s\t%(uploader)s\t%(thumbnail)s")
        .. " " .. shellQuote("ytsearch12:" .. search_query)
    local handle, err = self:_startDetached(command, work, "search")
    if not handle then
        cleanupDirectory(work)
        self:_notify(instance, context, err or _("The Shorts search could not be started."))
        return false
    end
    state.search = { handle = handle, work = work, query = search_query, started = os.time() }
    state.view, state.note = "search", _("Finding Shorts")
    if context and context.requestRebuild then context.requestRebuild("ui") end
    local tick
    tick = function()
        local code, log = self:_pollDetached(handle)
        if not code then
            if os.time() - state.search.started > 90 then
                self:_killDetached(handle); cleanupDirectory(work); state.search = nil
                state.view, state.note = "home", _("The Shorts search timed out.")
                if context and context.requestRebuild then context.requestRebuild("ui") end
                return
            end
            UIManager:scheduleIn(1, tick)
            return
        end
        cleanupDirectory(work); state.search = nil
        local results = YouTube.parseSearchOutput(log or "")
        local filtered = {}
        for _, result in ipairs(results) do
            if result.duration and result.duration <= 180 then
                self:_cacheThumbnail(result)
                filtered[#filtered + 1] = result
            end
        end
        state.results, state.results_query = filtered, search_query
        state.short_queue, state.short_index = filtered, 1
        state.result_page = 1
        state.view = #filtered > 0 and "results" or "home"
        state.note = #filtered > 0 and _("Shorts feed ready") or _("No Shorts found. Try another hashtag.")
        if context and context.requestRebuild then context.requestRebuild("ui") end
    end
    UIManager:scheduleIn(1, tick)
    return true
end

function Shorts:_current(state)
    local results = state.short_queue or state.results or {}
    return results[state.short_index] or results[1]
end

function Shorts:_playPath(instance, context, path)
    if not path then return false end
    if not self:play(instance, context, path) then return false end
    return self:openInlineFullscreen(instance, context, path)
end

function Shorts:_playNext(instance, context)
    local state = self:_state(instance)
    local results = state.short_queue or {}
    if #results == 0 then return end
    state.short_index = state.short_index >= #results and 1 or state.short_index + 1
    local result = results[state.short_index]
    if result.path then self:_playPath(instance, context, result.path) else self:startVideo(instance, context, result) end
end

function Shorts:_buildFeedPane(instance, context, state)
    local width, height = context.dimen.w, context.dimen.h
    local margin = scale(14)
    local result = self:_current(state)
    local dark = Blitbuffer.COLOR_BLACK
    local light = Blitbuffer.COLOR_WHITE
    local content = OverlapGroup:new{ dimen = Geom:new{ w = width, h = height }, allow_mirroring = false,
        FrameContainer:new{ width = width, height = height, padding = 0, bordersize = 0, background = dark,
            CenterContainer:new{ dimen = Geom:new{ w = width, h = height }, TextWidget:new{
                text = result and "▶" or "#  Shorts", face = Font:getFace("cfont", scale(result and 44 or 24)),
                fgcolor = light, bold = true, padding = 0 } } } }
    local header = TextWidget:new{ text = "YouTube Shorts", face = Font:getFace("cfont", scale(16)),
        fgcolor = light, bold = true, padding = 0 }
    header.overlap_offset = { margin, margin }; table.insert(content, header)
    local hint = TextWidget:new{ text = result and (result.title or "") or _("Short-only recommendations from your hashtags and likes"),
        face = Font:getFace("smallinfofont", scale(11)), fgcolor = light, max_width = width - margin * 2, padding = 0 }
    hint.overlap_offset = { margin, height - scale(126) }; table.insert(content, hint)
    local meta = TextWidget:new{ text = result and ("#shorts  ·  " .. (result.uploader or _("YouTube"))) or self:_recommendationQuery(state),
        face = Font:getFace("smallinfofont", scale(10)), fgcolor = Blitbuffer.COLOR_GRAY_8, max_width = width - margin * 2, padding = 0 }
    meta.overlap_offset = { margin, height - scale(101) }; table.insert(content, meta)
    local gap, button_h = scale(6), scale(34)
    local button_w = math.floor((width - margin * 2 - gap * 2) / 3)
    local actions = {
        { symbol = state.shorts_likes[result and result.id or ""] and "♥" or "♡", title = result and _("Liked") or _("Like"), callback = function() self:toggleLike(instance, context, result) end },
        { symbol = "›", title = _("Next"), callback = function() self:_playNext(instance, context) end },
        { symbol = "⌕", title = _("Hashtags"), callback = function() self:promptSearch(instance, context) end },
    }
    for index, action in ipairs(actions) do
        local chip = Chip:new{ symbol = action.symbol, title = action.title, width = button_w, height = button_h,
            background = Blitbuffer.COLOR_GRAY_8, callback = action.callback }
        chip.overlap_offset = { margin + (index - 1) * (button_w + gap), height - scale(62) }
        table.insert(content, chip)
    end
    local footer = TextWidget:new{ text = state.note ~= "" and state.note or _("Swipe-like feed · next video is prepared in the background"),
        face = Font:getFace("smallinfofont", scale(9)), fgcolor = Blitbuffer.COLOR_GRAY_8, max_width = width - margin * 2, padding = 0 }
    footer.overlap_offset = { margin, height - scale(22) }; table.insert(content, footer)
    return content
end

function Shorts:_buildResultsPane(instance, context, state)
    local results = state.results or {}
    state.short_queue = results
    return self:_buildFeedPane(instance, context, state)
end

function Shorts:_buildHomePane(instance, context, state)
    if not state.results or #state.results == 0 then
        state.query = state.query ~= "" and state.query or self:_recommendationQuery(state)
    end
    return self:_buildFeedPane(instance, context, state)
end

function Shorts:_finishJob(instance, context, job, without_audio)
    local state = self:_state(instance)
    local is_prefetch = job and job.prefetch == true
    YouTube._finishJob(self, instance, context, job, without_audio)
    if is_prefetch then
        state.prefetched_path = job.target
        local results = state.short_queue or {}
        local next_result = results[state.short_index + 1]
        if next_result then next_result.path = job.target end
        state.view = "play"
        return
    end
    if job and job.target and state.shorts then
        self:_playPath(instance, context, job.target)
        local results = state.short_queue or {}
        local next_result = results[state.short_index + 1]
        if next_result and not next_result.path then
            local prefetched = self:startVideo(instance, context, next_result)
            if prefetched then
                prefetched.prefetch = true
                state.view = "play"
            end
        end
    end
end

return Shorts
