--[[--
AppDock YouTube Shorts: a local, E-Ink friendly vertical Shorts feed.

The existing YouTube DApp remains the download/player backend. This module owns
only the Shorts feed, local likes and recommendation order. Likes never leave
the device.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/container/overlapgroup")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local DataStorage = require("datastorage")
local _ = require("gettext")

local YouTube = require("appdock_youtube")
local Player = require("appdock_player")
local DAppLogo = require("appdock_logo")
local Screen = require("device").screen

local Shorts = {}
Shorts.__index = Shorts

local function scale(value) return Screen:scaleBySize(value) end
local function trim(value) return type(value) == "string" and (value:match("^%s*(.-)%s*$") or "") or "" end
local function fit(text, max_chars)
    text = trim(text)
    if #text <= max_chars then return text end
    return text:sub(1, math.max(1, max_chars - 1)) .. "…"
end
local function fileExists(path)
    local f = path and io.open(path, "rb")
    if f then f:close(); return true end
    return false
end

function Shorts.extractHashtags(text)
    local tags, seen = {}, {}
    for tag in tostring(text or ""):gmatch("#([%w_%-]+)") do
        tag = tag:lower()
        if not seen[tag] then seen[tag] = true; tags[#tags + 1] = tag end
    end
    return tags
end

function Shorts.isShort(result)
    if type(result) ~= "table" then return false end
    local duration = tonumber(result.duration)
    if not duration or duration <= 0 or duration > 180 then return false end
    local text = (result.title or "") .. " " .. (result.description or "")
    return text:lower():find("#short", 1, true) ~= nil or result.short == true
end

function Shorts.recommend(results, liked_tags, liked_ids)
    local ranked = {}
    liked_tags, liked_ids = liked_tags or {}, liked_ids or {}
    for index, result in ipairs(results or {}) do
        local score = 0
        for _, tag in ipairs(Shorts.extractHashtags(result.title .. " " .. (result.description or ""))) do
            score = score + (tonumber(liked_tags[tag]) or 0) * 10
        end
        if liked_ids[result.id] then score = score + 1000 end
        ranked[#ranked + 1] = { result = result, score = score - index / 1000 }
    end
    table.sort(ranked, function(a, b) return a.score > b.score end)
    local ordered = {}
    for _, item in ipairs(ranked) do ordered[#ordered + 1] = item.result end
    return ordered
end

local Button = InputContainer:extend{ text = "", width = 100, height = 34, callback = nil, inverse = false }
function Button:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self[1] = FrameContainer:new{
        width = self.width, height = self.height, padding = scale(5), bordersize = 1,
        background = self.inverse and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
        TextWidget:new{
            text = self.text, face = Font:getFace("smallinfofont", scale(11)), bold = true,
            fgcolor = self.inverse and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK,
            max_width = self.width - scale(10), align = "center",
        },
    }
    self.ges_events = { TapButton = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end
function Button:getSize() return self.dimen end
function Button:paintTo(bb, x, y)
    local range = self.ges_events.TapButton[1].range
    range.x, range.y, range.w, range.h = x, y, self.width, self.height
    return InputContainer.paintTo(self, bb, x, y)
end
function Button:onTapButton()
    if self.callback then self.callback() end
    return true
end
function Shorts:new(appdock)
    local object = setmetatable({ appdock = appdock, youtube = YouTube:new(appdock), player = Player:new(appdock) }, self)
    return object
end

function Shorts:_store()
    local key = "appdock_shorts_state"
    local value = _G.G_reader_settings and G_reader_settings:readSetting(key, {}) or {}
    if type(value) ~= "table" then value = {} end
    value.likes = type(value.likes) == "table" and value.likes or {}
    value.tags = type(value.tags) == "table" and value.tags or {}
    return value
end
function Shorts:_save(store)
    if _G.G_reader_settings and type(G_reader_settings.saveSetting) == "function" then
        G_reader_settings:saveSetting("appdock_shorts_state", store)
    end
end
function Shorts:_state(instance)
    instance.shorts = instance.shorts or {
        view = "feed", feed = nil, index = 1, note = "", searched = false,
        prefetching = {}, helper = {}, selected_path = nil,
    }
    return instance.shorts
end
function Shorts:_libraryPath(result)
    if type(result) ~= "table" then return nil end
    local slug = YouTube.slugify(result.title, result.id)
    local dir = self.youtube:_outputDirectory()
    local exact = dir .. "/" .. slug .. ".bwr"
    if fileExists(exact) then return exact end
    local pipe = io.popen("find " .. string.format("%q", dir) .. " -maxdepth 1 -type f -name " .. string.format("%q", slug .. "*.bwr") .. " 2>/dev/null", "r")
    local path = pipe and pipe:read("*l") or nil
    if pipe then pipe:close() end
    return path
end
function Shorts:_refreshFeed(instance, context)
    local state = self:_state(instance)
    local helper_state = self.youtube:_state(state.helper)
    local candidates = helper_state.results or {}
    local shorts = {}
    for _, result in ipairs(candidates) do
        -- The query is already constrained to #shorts. yt-dlp's flat search
        -- output does not always include the hashtag in the title, so the
        -- duration gate is the reliable second half of the filter.
        if Shorts.isShort(result) or (tonumber(result.duration) and tonumber(result.duration) <= 180) then
            result.short = true
            result.tags = Shorts.extractHashtags(result.title)
            result.path = self:_libraryPath(result)
            shorts[#shorts + 1] = result
        end
    end
    local store = self:_store()
    state.feed = Shorts.recommend(shorts, store.tags, store.likes)
    if state.index > #state.feed then state.index = math.max(1, #state.feed) end
    if #state.feed > 0 then self:_prefetch(instance, context, 0) end
end
function Shorts:_ensureSearch(instance, context)
    local state = self:_state(instance)
    local helper_state = self.youtube:_state(state.helper)
    if helper_state.search then return end
    if not state.searched then
        state.searched = true
        self.youtube:startSearch(state.helper, context, "#shorts")
        return
    end
    if helper_state.results and not state.feed then self:_refreshFeed(instance, context) end
end
function Shorts:_prefetch(instance, context, offset)
    local state = self:_state(instance)
    local result = state.feed and state.feed[state.index + (offset or 1)]
    if not result or result.path or state.prefetching[result.id] then return end
    state.prefetching[result.id] = true
    self.youtube:startVideo(state.helper, context, result)
end
function Shorts:_like(instance, context, result)
    if not result then return end
    local store = self:_store()
    local liked = store.likes[result.id] == true
    store.likes[result.id] = not liked
    for _, tag in ipairs(result.tags or Shorts.extractHashtags(result.title)) do
        store.tags[tag] = math.max(0, (tonumber(store.tags[tag]) or 0) + (liked and -1 or 1))
    end
    self:_save(store)
    self:_refreshFeed(instance, context)
    self:_notify(instance, context, liked and _("Like removed · recommendations updated") or _("Liked locally · recommendations updated"))
end
function Shorts:_notify(instance, context, text)
    self:_state(instance).note = text
    if context and context.requestRebuild then context.requestRebuild("ui") end
end
function Shorts:_playCurrent(instance, context)
    local state = self:_state(instance)
    local result = state.feed and state.feed[state.index]
    if not result then return end
    result.path = result.path or self:_libraryPath(result)
    if not result.path then
        self:_notify(instance, context, _("This Short is still loading. The next clip is being prepared in the background."))
        self:_prefetch(instance, context, 1)
        return
    end
    self.youtube:stopInline(state.helper)
    if self.youtube:toggleInline(state.helper, context, result.path) then
        state.selected_path = result.path
        self:_prefetch(instance, context, 1)
    end
end
function Shorts:next(instance, context)
    local state = self:_state(instance)
    if not state.feed or #state.feed == 0 then return end
    self.youtube:stopInline(state.helper)
    state.index = state.index % #state.feed + 1
    self:_playCurrent(instance, context)
    self:_prefetch(instance, context, 1)
end
function Shorts:previous(instance, context)
    local state = self:_state(instance)
    if not state.feed or #state.feed == 0 then return end
    self.youtube:stopInline(state.helper)
    state.index = (state.index - 2) % #state.feed + 1
    self:_playCurrent(instance, context)
end
function Shorts:_buildEmpty(instance, context, message)
    local w, h, m = context.dimen.w, context.dimen.h, scale(16)
    local group = OverlapGroup:new{ dimen = Geom:new{ w = w, h = h }, FrameContainer:new{ width = w, height = h, padding = 0, bordersize = 0, background = Blitbuffer.COLOR_WHITE, CenterContainer:new{ dimen = Geom:new{ w = w, h = h }, TextWidget:new{ text = message, face = Font:getFace("cfont", scale(15)), max_width = w - 2 * m, align = "center" } } } }
    return group
end
function Shorts:buildPane(instance, context)
    local state = self:_state(instance)
    self:_ensureSearch(instance, context)
    if not state.feed then
        local helper = self.youtube:_state(state.helper)
        if helper.search then return self:_buildEmpty(instance, context, _("Loading Shorts…")) end
        if helper.results then self:_refreshFeed(instance, context) end
    end
    if not state.feed or #state.feed == 0 then
        return self:_buildEmpty(instance, context, state.note ~= "" and state.note or _("No Shorts found. Check the network and try again."))
    end
    local result = state.feed[state.index]
    result.path = result.path or self:_libraryPath(result)
    local w, h, m, gap = context.dimen.w, context.dimen.h, scale(12), scale(8)
    local header, footer = scale(48), scale(42)
    local canvas_h = math.max(scale(180), h - header - footer - scale(118))
    local group = OverlapGroup:new{ dimen = Geom:new{ w = w, h = h }, allow_mirroring = false,
        FrameContainer:new{ width = w, height = h, padding = 0, bordersize = 0, background = Blitbuffer.COLOR_WHITE, CenterContainer:new{ dimen = Geom:new{ w = w, h = h }, HorizontalSpan:new{ width = 0 } } } }
    table.insert(group, FrameContainer:new{ width = w, height = header, padding = 0, bordersize = 0, background = Blitbuffer.COLOR_BLACK, CenterContainer:new{ dimen = Geom:new{ w = w, h = header }, TextWidget:new{ text = "YouTube  #Shorts", face = Font:getFace("cfont", scale(16)), bold = true, fgcolor = Blitbuffer.COLOR_WHITE } } })
    local logo = DAppLogo:new{ kind = "youtube", size = scale(26), ink = Blitbuffer.COLOR_WHITE }; logo.overlap_offset = { m, scale(11) }; table.insert(group, logo)
    local canvas = Player.Canvas:new{ width = w - 2 * m, height = canvas_h }
    local inline = state.selected_path == result.path and self.youtube.player.engine
    if inline then self.youtube.player.engine:setCanvas(canvas); self.youtube.player.engine:show(self.youtube.player.engine.position or 0) end
    canvas.overlap_offset = { m, header + gap }; table.insert(group, canvas)
    if not inline then table.insert(group, TextWidget:new{ text = "▶", face = Font:getFace("cfont", scale(38)), fgcolor = Blitbuffer.COLOR_BLACK, overlap_offset = { math.floor(w / 2 - scale(12)), header + math.floor(canvas_h / 2) } }) end
    local store = self:_store()
    local liked = result.id and store.likes[result.id] == true
    local info_y = header + canvas_h + gap
    local title = TextWidget:new{ text = fit(result.title, 52), face = Font:getFace("cfont", scale(15)), bold = true, max_width = w - 2 * m, overlap_offset = { m, info_y } }; table.insert(group, title)
    local tags = Shorts.extractHashtags(result.title)
    local meta = TextWidget:new{ text = "@" .. fit(result.uploader or "youtube", 20) .. "  " .. (#tags > 0 and ("#" .. table.concat(tags, "  #")) or "#shorts"), face = Font:getFace("smallinfofont", scale(10)), fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = w - 2 * m, overlap_offset = { m, info_y + scale(22) } }; table.insert(group, meta)
    local button_w = math.floor((w - 2 * m - 2 * gap) / 3)
    local like = Button:new{ text = liked and "♥  Liked" or "♡  Like", width = button_w, height = scale(30), inverse = liked, callback = function() self:_like(instance, context, result) end }; like.overlap_offset = { m, info_y + scale(48) }; table.insert(group, like)
    local next_btn = Button:new{ text = "Next  ›", width = button_w, height = scale(30), callback = function() self:next(instance, context) end }; next_btn.overlap_offset = { m + button_w + gap, info_y + scale(48) }; table.insert(group, next_btn)
    local load = result.path and _("Ready") or (state.prefetching[result.id] and _("Preloading…") or _("Tap to load"))
    local status = TextWidget:new{ text = state.note ~= "" and state.note or load, face = Font:getFace("smallinfofont", scale(10)), fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = w - 2 * m, overlap_offset = { m, info_y + scale(84) } }; table.insert(group, status)
    local footer_bar = FrameContainer:new{ width = w, height = footer, padding = 0, bordersize = 0, background = Blitbuffer.COLOR_BLACK, CenterContainer:new{ dimen = Geom:new{ w = w, h = footer }, TextWidget:new{ text = "‹  Previous                 Next  ›", face = Font:getFace("smallinfofont", scale(11)), fgcolor = Blitbuffer.COLOR_WHITE } } }; footer_bar.overlap_offset = { 0, h - footer }; table.insert(group, footer_bar)
    local previous = Button:new{ text = "‹", width = scale(52), height = scale(30), inverse = true, callback = function() self:previous(instance, context) end }; previous.overlap_offset = { m, h - footer + scale(6) }; table.insert(group, previous)
    local next_bottom = Button:new{ text = "›", width = scale(52), height = scale(30), inverse = true, callback = function() self:next(instance, context) end }; next_bottom.overlap_offset = { w - m - scale(52), h - footer + scale(6) }; table.insert(group, next_bottom)
    if result.path and not inline then self:_playCurrent(instance, context) end
    return group
end
function Shorts:stop(instance)
    if instance and instance.shorts then
        self.youtube:stopInline(instance.shorts.helper)
    end
end

Shorts._test = { extractHashtags = Shorts.extractHashtags, isShort = Shorts.isShort, recommend = Shorts.recommend }
return Shorts
