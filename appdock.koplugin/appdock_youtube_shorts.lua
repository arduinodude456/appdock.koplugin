--[[--
AppDock YouTube Shorts: a vertical, short-only feed built on the existing
YouTube downloader/player. Every feed entry originates from a YouTube Shorts
tab and keeps its canonical /shorts/<id> URL. Likes are local, private signals:
they contribute the creator and hashtags used for later feed sources.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Player = require("appdock_player")
local YouTube = require("appdock_youtube")

local Shorts = setmetatable({}, { __index = YouTube })
Shorts.__index = Shorts

local SHORTS_PER_FEED = 12
local DEFAULT_START_TAG = "trending"
local MAX_LIKE_PROFILES = 48
local MAX_LIKED_PROFILE_BYTES = 3900
local MAX_LOCAL_SEEN = 64
local MAX_INTERACTION_BYTES = 3900

local function scale(value)
    local ok, Device = pcall(require, "device")
    return ok and Device.screen:scaleBySize(value) or value
end

-- Shorts can be shown in a narrow split/window pane. The normal screen scale
-- is too large there, so prefer the host's pane-relative helper when present.
local function panePx(context, value)
    if context and type(context.px) == "function" then
        local ok, pixels = pcall(context.px, value)
        if ok and type(pixels) == "number" then return math.max(1, math.floor(pixels)) end
    end
    return math.max(1, math.floor(scale(value)))
end

local function fitText(value, width, font_size)
    value = tostring(value or "")
    local budget = math.max(3, math.floor(math.max(1, width) / math.max(1, font_size * .52)))
    if #value <= budget then return value end
    return value:sub(1, math.max(1, budget - 1)) .. "…"
end

local function emptySizedWidget(width, height)
    return WidgetContainer:new{ dimen = Geom:new{ w = width, h = height } }
end

-- The canvas must never overlap the title, status and transport controls: a
-- video frame refresh repaints only the canvas rectangle. Keeping that
-- rectangle in the middle band prevents a new frame from erasing metadata.
local function shortsLayout(context)
    local width = math.max(1, tonumber(context and context.dimen and context.dimen.w) or 1)
    local height = math.max(1, tonumber(context and context.dimen and context.dimen.h) or 1)
    local margin = math.min(math.max(2, panePx(context, 12)), math.max(2, math.floor(width * .08)))
    local gap = math.min(math.max(2, panePx(context, 6)), math.max(2, math.floor(width * .04)))
    local raw_margin, raw_gap = panePx(context, 12), panePx(context, 6)
    local raw_utility_h = math.min(math.max(panePx(context, 25), math.floor(height * .07)), panePx(context, 32))
    local raw_primary_h = math.min(math.max(panePx(context, 30), math.floor(height * .08)), panePx(context, 38))
    local raw_title_step, raw_source_step = panePx(context, 19), panePx(context, 16)
    local raw_detail_h = math.min(math.max(panePx(context, 44), math.floor(height * .12)), panePx(context, 58))
    local raw_header_h = raw_margin + raw_title_step + raw_source_step + raw_utility_h + raw_gap
    local raw_total = raw_header_h + raw_detail_h + raw_primary_h + raw_gap * 2 + raw_margin + 1
    local vertical_ratio = math.min(1, math.max(.1, (height - 1) / math.max(1, raw_total)))
    local function vertical(value) return math.max(1, math.floor(value * vertical_ratio)) end
    local vertical_margin, vertical_gap = vertical(raw_margin), vertical(raw_gap)
    local utility_h, primary_h = vertical(raw_utility_h), vertical(raw_primary_h)
    local title_y = vertical_margin
    local source_y = title_y + vertical(raw_title_step)
    local utility_y = source_y + vertical(raw_source_step)
    local header_h = utility_y + utility_h + vertical_gap
    local detail_h = vertical(raw_detail_h)
    local bottom_h = detail_h + primary_h + vertical_gap * 2 + vertical_margin
    local video_h = math.max(1, height - header_h - bottom_h)
    local video_w = math.max(1, math.min(width - margin * 2, math.floor(video_h * .68)))
    local video_x = math.max(margin, math.floor((width - video_w) / 2))
    local video_y = header_h
    local available = math.max(1, width - margin * 2)
    return {
        width = width, height = height, margin = margin, gap = gap,
        title_y = title_y, source_y = source_y, utility_y = utility_y,
        utility_h = utility_h, utility_w = math.max(1, math.floor((available - gap * 3) / 4)),
        video = { x = video_x, y = video_y, w = video_w, h = video_h },
        detail = { x = margin, y = video_y + video_h + gap, w = available, h = detail_h },
        primary_y = video_y + video_h + gap + detail_h + gap,
        primary_h = primary_h,
        primary_w = math.max(1, math.floor((available - gap * 2) / 3)),
    }
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

local function validVideoId(value)
    return type(value) == "string" and #value == 11 and value:match("^[%w_%-]+$") ~= nil
end

local function normalizedField(value)
    value = trim(value)
    return value ~= "" and value ~= "NA" and value ~= "null" and value or nil
end

local function normalizeTag(value)
    local tag = trim(value):gsub("^#+", ""):lower()
    tag = tag:gsub("[^%w_%-\128-\255]", "")
    if tag == "" or tag == "short" or tag == "shorts" or #tag > 80 then return nil end
    return tag
end

local function tagsFromText(value, maximum)
    local tags, seen = {}, {}
    for raw in tostring(value or ""):gmatch("[^,%s]+") do
        local tag = normalizeTag(raw)
        if tag and not seen[tag] then
            seen[tag] = true
            tags[#tags + 1] = tag
            if maximum and #tags >= maximum then break end
        end
    end
    return tags
end

local function tagsFromTitle(value)
    local tags, seen = {}, {}
    for raw in tostring(value or ""):gmatch("#([^%s#]+)") do
        local tag = normalizeTag(raw)
        if tag and not seen[tag] then
            seen[tag] = true
            tags[#tags + 1] = tag
        end
    end
    return tags
end

local function normalizeChannel(value)
    local channel = trim(value)
    channel = channel:gsub("^https?://[^/]+/", ""):gsub("/.*$", "")
    if channel:sub(1, 1) ~= "@" then return nil end
    channel = "@" .. channel:sub(2):gsub("[^%w%._%-]", "")
    return #channel > 1 and #channel <= 80 and channel or nil
end

local function normalizeChannelId(value)
    local channel = trim(value)
    return channel:match("^UC[%w_%-]+$") and channel or nil
end

local function encodePathSegment(value)
    local ok, socket_url = pcall(require, "socket.url")
    if ok and socket_url and socket_url.escape then return socket_url.escape(value) end
    return value:gsub("[^%w_%-]", function(byte) return string.format("%%%02X", byte:byte()) end)
end

local function isShortUrl(value, expected_id)
    local id = trim(value):match("^https?://[^/]*youtube%.com/shorts/([%w_%-]+)")
    return validVideoId(id) and (not expected_id or id == expected_id)
end

local function appendUnique(items, known, value)
    if value and not known[value] then
        known[value] = true
        items[#items + 1] = value
    end
end

-- Each record uses id|channel-or-channel-id|tag,tag. The values are restricted
-- to separators-free forms above, so old or truncated settings are harmlessly
-- ignored instead of becoming a source URL.
local function parseLikeProfiles(text, legacy_ids)
    local profiles, order = {}, {}
    for record in tostring(text or ""):gmatch("[^;]+") do
        local id, channel, tags = record:match("^([^|]*)|([^|]*)|([^|]*)$")
        if validVideoId(id) and not profiles[id] then
            local normalized_channel = normalizeChannel(channel) or normalizeChannelId(channel) or ""
            profiles[id] = { id = id, channel = normalized_channel, tags = tagsFromText(tags, 8) }
            order[#order + 1] = id
        end
    end
    for id in tostring(legacy_ids or ""):gmatch("[^,]+") do
        id = trim(id)
        if validVideoId(id) and not profiles[id] then
            profiles[id] = { id = id, channel = "", tags = {} }
            order[#order + 1] = id
        end
    end
    while #order > MAX_LIKE_PROFILES do
        local id = table.remove(order)
        profiles[id] = nil
    end
    return profiles, order
end

local function serializeLikeProfiles(profiles, order)
    local kept, ids, records = {}, {}, {}
    for _, id in ipairs(order or {}) do
        local profile = profiles and profiles[id]
        if profile and validVideoId(id) and not kept[id] then
            local channel = normalizeChannel(profile.channel) or normalizeChannelId(profile.channel) or ""
            local tags = table.concat(tagsFromText(table.concat(profile.tags or {}, ","), 8), ",")
            local record = id .. "|" .. channel .. "|" .. tags
            if #table.concat(records, ";") + #record + 1 > MAX_LIKED_PROFILE_BYTES then break end
            kept[id] = true
            ids[#ids + 1] = id
            records[#records + 1] = record
            if #ids >= MAX_LIKE_PROFILES then break end
        end
    end
    return table.concat(ids, ","), table.concat(records, ";")
end

local function parseInteractions(text)
    local interactions = {}
    for record in tostring(text or ""):gmatch("[^;]+") do
        local id, views, skips, seconds = record:match("^([^:]+):(%d+):(%d+):(%d+)$")
        if validVideoId(id) then
            interactions[id] = { views = tonumber(views) or 0, skips = tonumber(skips) or 0, seconds = tonumber(seconds) or 0 }
        end
    end
    return interactions
end

local function serializeInteractions(interactions)
    local rows = {}
    for id, item in pairs(interactions or {}) do
        if validVideoId(id) then
            rows[#rows + 1] = string.format("%s:%d:%d:%d", id,
                math.min(99, tonumber(item.views) or 0), math.min(99, tonumber(item.skips) or 0),
                math.min(9999, tonumber(item.seconds) or 0))
        end
    end
    table.sort(rows)
    local values, length = {}, 0
    for _, row in ipairs(rows) do
        if length + #row + 1 > MAX_INTERACTION_BYTES then break end
        values[#values + 1], length = row, length + #row + 1
    end
    return table.concat(values, ";")
end

local CenterProgress = InputContainer:extend{ ratio = 0, indeterminate = false, phase = 0, width = 0, height = 0 }

function CenterProgress:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
end

function CenterProgress:getSize() return self.dimen end

function CenterProgress:paintTo(bb, x, y)
    local bar_w, bar_h = math.min(self.width - scale(32), scale(260)), scale(7)
    local left = x + math.floor((self.width - bar_w) / 2)
    local top = y + math.floor((self.height - bar_h) / 2)
    local red = Blitbuffer.COLOR_RED or Blitbuffer.COLOR_DARK_GRAY
    bb:paintRect(left, top, bar_w, bar_h, Blitbuffer.COLOR_GRAY_8)
    local fill_w
    if self.indeterminate then
        fill_w = math.max(scale(22), math.floor(bar_w * .25))
        left = left + math.floor((bar_w - fill_w) * ((self.phase or 0) % 20) / 20)
    else
        fill_w = math.floor(bar_w * math.max(0, math.min(1, self.ratio or 0)))
    end
    if fill_w > 0 then bb:paintRect(left, top, fill_w, bar_h, red) end
end

local Chip = InputContainer:extend{
    title = "", symbol = "", width = 100, height = 34, callback = nil,
    background = Blitbuffer.COLOR_GRAY_8, foreground = Blitbuffer.COLOR_BLACK,
}

function Chip:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local font_size = scale(10)
    local text = (self.symbol or "") .. (self.symbol ~= "" and "  " or "") .. (self.title or "")
    text = fitText(text, math.max(1, self.width - scale(8)), font_size)
    self[1] = FrameContainer:new{
        width = self.width, height = self.height, padding = scale(4), bordersize = 0,
        background = self.background,
        CenterContainer:new{
            dimen = Geom:new{ w = math.max(1, self.width - scale(8)), h = math.max(1, self.height - scale(8)) },
            TextWidget:new{
                text = text, face = Font:getFace("smallinfofont", font_size),
                fgcolor = self.foreground, bold = true, padding = 0,
                max_width = math.max(1, self.width - scale(8)),
            },
        },
    }
    self.ges_events = { TapShortsAction = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function Chip:paintTo(bb, x, y)
    local range = self.ges_events.TapShortsAction[1].range
    range.x, range.y, range.w, range.h = x, y, self.width, self.height
    return InputContainer.paintTo(self, bb, x, y)
end

function Chip:onTapShortsAction()
    if self.callback then self.callback() end
    return true
end

local FeedSurface = InputContainer:extend{
    width = 0, height = 0, canvas = nil, callback = nil, swipe_callback = nil,
    gesture_inset_bottom = 0,
}

function FeedSurface:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self.ges_events = {
        TapShortsFeed = { GestureRange:new{ ges = "tap", range = self.dimen } },
        SwipeShortsFeed = { GestureRange:new{ ges = "swipe", range = self.dimen } },
    }
end

function FeedSurface:getSize() return self.dimen end

function FeedSurface:paintTo(bb, x, y)
    -- FeedSurface paints the canvas itself, so OverlapGroup cannot apply the
    -- canvas offset for us. Honour it explicitly; this also keeps Canvas'
    -- refresh origin aligned with the pixels it actually drew.
    if self.canvas then
        local offset = self.canvas.overlap_offset or { 0, 0 }
        self.canvas:paintTo(bb, x + (offset[1] or 0), y + (offset[2] or 0))
    end
    local available_height = math.max(1, self.height - math.max(0, self.gesture_inset_bottom or 0))
    for _, event in pairs(self.ges_events) do
        local range = event[1].range
        range.x, range.y, range.w, range.h = x, y, self.width, available_height
    end
end

function FeedSurface:onTapShortsFeed()
    if self.callback then self.callback() end
    return true
end

function FeedSurface:onSwipeShortsFeed(_, gesture_event)
    -- KOReader dispatches handlers as (widget, ges_ev). The old one-argument
    -- form treated the widget as the gesture, which made vertical swipes inert.
    if self.swipe_callback then self.swipe_callback(gesture_event) end
    return true
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
    if not state.shorts_likes then
        local settings = self.appdock and self.appdock:getYouTubeSettings() or {}
        state.shorts_likes, state.shorts_like_order = parseLikeProfiles(
            settings.shorts_liked_profiles, settings.shorts_liked_ids)
        state.interactions = parseInteractions(settings.shorts_interactions)
    end
    state.interactions = state.interactions or {}
    state.short_index = state.short_index or 1
    state.short_queue = state.short_queue or {}
    state.seen_ids = state.seen_ids or {}
    state.seen_order = state.seen_order or {}
    state.recommendation_source_index = state.recommendation_source_index or 0
    state.search_generation = state.search_generation or 0
    state.feed_generation = state.feed_generation or 0
    if state.pane_active == nil then state.pane_active = false end
    return state
end

function Shorts.isShortUrl(value, expected_id)
    return isShortUrl(value, expected_id)
end

function Shorts.parseShortsOutput(text, allow_canonical_fallback)
    local results, known = {}, {}
    for line in tostring(text or ""):gmatch("[^\r\n]+") do
        local fields = {}
        for value in (line .. "\t"):gmatch("(.-)\t") do fields[#fields + 1] = value end
        local id = fields[1]
        -- yt-dlp may normalize `webpage_url` to /watch. Conversely,
        -- `original_url` is often the playlist source (or NA), not the entry.
        -- Prefer either field only when it is the matching item URL. For a
        -- command explicitly scoped to a /shorts tab, reconstructing the
        -- canonical item endpoint from its emitted ID is safe and prevents an
        -- otherwise empty, permanently loading feed.
        local webpage_url
        for _, candidate in ipairs({ fields[7], fields[6] }) do
            if isShortUrl(candidate, id) then
                webpage_url = candidate
                break
            end
        end
        if not webpage_url and allow_canonical_fallback and validVideoId(id) then
            webpage_url = "https://www.youtube.com/shorts/" .. id
        end
        if validVideoId(id) and not known[id] and webpage_url then
            known[id] = true
            local duration = tonumber(fields[3])
            results[#results + 1] = {
                id = id,
                title = normalizedField(fields[2]) or id,
                duration = duration and duration > 0 and duration or nil,
                uploader = normalizedField(fields[4]),
                thumbnail = normalizedField(fields[5]),
                url = webpage_url,
                webpage_url = webpage_url,
                uploader_id = normalizeChannel(fields[8]),
                channel_id = normalizeChannelId(fields[9]),
            }
        end
    end
    return results
end

function Shorts.recommendationSources(settings, profiles, order)
    settings = settings or {}
    if not profiles then
        profiles, order = parseLikeProfiles(settings.shorts_liked_profiles, settings.shorts_liked_ids)
    end
    order = order or {}
    local sources, known_urls = {}, {}
    local function add(url, label, kind)
        if url and not known_urls[url] then
            known_urls[url] = true
            sources[#sources + 1] = { url = url, label = label, kind = kind }
        end
    end
    for _, tag in ipairs(tagsFromText(settings.shorts_hashtags, 16)) do
        add("https://www.youtube.com/hashtag/" .. encodePathSegment(tag) .. "/shorts", "#" .. tag, "hashtag")
    end
    -- Liked sources follow explicit topics. A refresh rotates through all of
    -- them, giving both chosen hashtags and local likes real input to the feed.
    local profile_tags, known_tags, channels, known_channels = {}, {}, {}, {}
    for _, id in ipairs(order) do
        local profile = profiles[id]
        if profile then
            for _, tag in ipairs(profile.tags or {}) do appendUnique(profile_tags, known_tags, tag) end
            local channel = normalizeChannel(profile.channel)
            if channel then appendUnique(channels, known_channels, channel) end
            local channel_id = normalizeChannelId(profile.channel)
            if channel_id then appendUnique(channels, known_channels, channel_id) end
        end
    end
    for _, tag in ipairs(profile_tags) do
        add("https://www.youtube.com/hashtag/" .. encodePathSegment(tag) .. "/shorts", "#" .. tag .. " · likes", "liked_hashtag")
    end
    for _, channel in ipairs(channels) do
        if channel:sub(1, 1) == "@" then
            add("https://www.youtube.com/" .. channel .. "/shorts", channel .. " · likes", "liked_channel")
        else
            add("https://www.youtube.com/channel/" .. channel .. "/shorts", "liked channel", "liked_channel")
        end
    end
    return sources
end

function Shorts.rankResults(results, profiles, seen, interactions)
    local ranked = {}
    for _, result in ipairs(results or {}) do
        if not (profiles and profiles[result.id]) and not (seen and seen[result.id]) then
            local score, result_tags = 0, tagsFromTitle(result.title)
            local result_tag_set = {}
            for _, tag in ipairs(result_tags) do result_tag_set[tag] = true end
            for _, profile in pairs(profiles or {}) do
                if profile.channel ~= "" and (profile.channel == result.uploader_id or profile.channel == result.channel_id) then
                    score = score + 20
                end
                for _, tag in ipairs(profile.tags or {}) do
                    if result_tag_set[tag] then score = score + 4 end
                end
            end
            local interaction = interactions and interactions[result.id]
            if interaction then
                score = score - (tonumber(interaction.skips) or 0) * 6
                score = score + math.min(8, (tonumber(interaction.seconds) or 0) / 15)
            end
            result.recommendation_score = score
            ranked[#ranked + 1] = result
        end
    end
    table.sort(ranked, function(left, right)
        if left.recommendation_score ~= right.recommendation_score then
            return left.recommendation_score > right.recommendation_score
        end
        return tostring(left.title):lower() < tostring(right.title):lower()
    end)
    return ranked
end

function Shorts:_rememberSeen(state, id)
    if not validVideoId(id) or state.seen_ids[id] then return end
    state.seen_ids[id] = true
    state.seen_order[#state.seen_order + 1] = id
    while #state.seen_order > MAX_LOCAL_SEEN do
        state.seen_ids[table.remove(state.seen_order, 1)] = nil
    end
end

function Shorts:_recommendationSources(state)
    local settings = self.appdock and self.appdock:getYouTubeSettings() or {}
    return Shorts.recommendationSources(settings, state.shorts_likes, state.shorts_like_order)
end

function Shorts:_recommendationQuery(state)
    local sources = self:_recommendationSources(state)
    if #sources == 0 then return _("Choose hashtags to start your Shorts feed") end
    return _("For you · ") .. sources[(state.recommendation_source_index % #sources) + 1].label
end

function Shorts:_persistLikes(state)
    local ids, profiles = serializeLikeProfiles(state.shorts_likes, state.shorts_like_order)
    if self.appdock and self.appdock.setYouTubeSettings then
        self.appdock:setYouTubeSettings({ shorts_liked_ids = ids, shorts_liked_profiles = profiles,
            shorts_interactions = serializeInteractions(state.interactions) })
    end
end

function Shorts:_contextIsActive(context)
    if not context then return false end
    if type(context.isActive) == "function" then
        local ok, active = pcall(context.isActive)
        if ok then return active == true end
    end
    if context.manager and context.host then
        return context.manager.active_host == context.host and not context.host._closed
    end
    -- Tests and older hosts do not expose an activity predicate.
    return true
end

function Shorts:_requestRebuild(instance, context, refresh_type)
    local state = self:_state(instance)
    if not self:_contextIsActive(context) then return false end
    if context and context.requestRebuild then
        -- Host rebuilds deactivate the old pane synchronously. Mark only this
        -- deliberate replacement as transient, so minimizing/switching apps
        -- still pauses the player instead of leaving it running offscreen.
        state.transient_rebuild = true
        context.requestRebuild(refresh_type or "ui")
        return true
    end
    if context and context.requestRefresh then
        context.requestRefresh(refresh_type or "ui")
        return true
    end
    return false
end

function Shorts:_pipelineContext(instance, context)
    if not context or context.shorts_pipeline_context then return context end
    local pipeline_context = {}
    for key, value in pairs(context) do pipeline_context[key] = value end
    pipeline_context.shorts_pipeline_context = true
    if context.requestRebuild then
        pipeline_context.requestRebuild = function(refresh_type)
            return self:_requestRebuild(instance, context, refresh_type)
        end
    end
    return pipeline_context
end

function Shorts:_recordInteraction(instance, result, field, amount)
    if not result or not validVideoId(result.id) then return end
    local state = self:_state(instance)
    local item = state.interactions[result.id] or { views = 0, skips = 0, seconds = 0 }
    item[field] = math.max(0, (tonumber(item[field]) or 0) + (amount or 1))
    state.interactions[result.id] = item
    self:_persistLikes(state)
end

function Shorts:_scheduleLoadingPulse(instance, context, state)
    if not state.search or state.loading_pulse_scheduled then return end
    state.loading_pulse_scheduled = true
    local function pulse()
        state.loading_pulse_scheduled = false
        if state.closed or not state.pane_active or not state.search or not self:_contextIsActive(context) then return end
        state.loading_phase = ((state.loading_phase or 0) + 1) % 20
        if state.loading_widget then state.loading_widget.phase = state.loading_phase end
        if context and context.requestRefresh then context.requestRefresh("fast") end
        self:_scheduleLoadingPulse(instance, context, state)
    end
    -- An indeterminate bar does not need ten full partial refreshes a second on
    -- E-Ink. One measured pulse is enough to communicate active work.
    UIManager:scheduleIn(0.8, pulse)
end

function Shorts:toggleLike(instance, context, result)
    local state = self:_state(instance)
    if not result or not validVideoId(result.id) then return end
    if state.shorts_likes[result.id] then
        state.shorts_likes[result.id] = nil
        for index, id in ipairs(state.shorts_like_order) do
            if id == result.id then table.remove(state.shorts_like_order, index); break end
        end
        state.note = _("Like removed")
    else
        local channel = normalizeChannel(result.uploader_id) or normalizeChannelId(result.channel_id) or ""
        state.shorts_likes[result.id] = {
            id = result.id,
            channel = channel,
            tags = tagsFromTitle(result.title),
        }
        for index = #state.shorts_like_order, 1, -1 do
            if state.shorts_like_order[index] == result.id then table.remove(state.shorts_like_order, index) end
        end
        table.insert(state.shorts_like_order, 1, result.id)
        while #state.shorts_like_order > MAX_LIKE_PROFILES do
            state.shorts_likes[table.remove(state.shorts_like_order)] = nil
        end
        state.note = _("Liked · later feeds use this creator and hashtags")
    end
    self:_persistLikes(state)
    self:_requestRebuild(instance, context, "fast")
end

function Shorts:_cancelSearch(state)
    if state.search and state.search.handle then self:_killDetached(state.search.handle) end
    if state.search then cleanupDirectory(state.search.work) end
    state.search = nil
    state.search_generation = (state.search_generation or 0) + 1
end

function Shorts:startSearch(instance, context, query)
    local state = self:_state(instance)
    local tools = state.tools or YouTube.detectTools(self:_settings())
    state.tools = tools
    if not tools.ytdlp then
        self:_notify(instance, context, _("yt-dlp was not found. Open Tool settings first."))
        return false
    end
    query = trim(query)
    if query ~= "" then
        local tags = tagsFromText(query, 16)
        if #tags == 0 then
            self:_notify(instance, context, _("Enter one or more hashtags, for example #cats."))
            return false
        end
        if self.appdock and self.appdock.setYouTubeSettings then
            self.appdock:setYouTubeSettings({ shorts_hashtags = table.concat(tags, ",") })
        end
    end
    local sources = self:_recommendationSources(state)
    if #sources == 0 then
        sources = Shorts.recommendationSources({ shorts_hashtags = DEFAULT_START_TAG },
            state.shorts_likes, state.shorts_like_order)
    end
    self:_cancelSearch(state)
    -- A pending prefetch belongs to the old feed as soon as a new source is
    -- requested. Its completion must not overwrite or autoplay in this queue.
    state.feed_generation = (state.feed_generation or 0) + 1
    state.recommendation_source_index = state.recommendation_source_index % #sources + 1
    local source = sources[state.recommendation_source_index]
    local work = jobDirectory()
    -- Do not use --flat-playlist here. Flat YouTube Shorts tabs omit the
    -- uploader/channel identifiers, which would make a Like unable to seed a
    -- creator-specific later feed. The list stays bounded to twelve items and
    -- still runs in the detached search process.
    local command = shellQuote(tools.ytdlp)
        .. " --no-warnings --no-cache-dir --ignore-errors"
        .. " --playlist-end " .. tostring(SHORTS_PER_FEED)
        .. " --print " .. shellQuote("%(id)s\t%(title)s\t%(duration)s\t%(uploader)s\t%(thumbnail)s\t%(webpage_url)s\t%(original_url)s\t%(uploader_id)s\t%(channel_id)s")
        .. " " .. shellQuote(source.url)
    local handle, err = self:_startDetached(command, work, "search")
    if not handle then
        cleanupDirectory(work)
        self:_notify(instance, context, err or _("The Shorts feed could not be started."))
        return false
    end
    local generation = state.search_generation + 1
    state.search_generation = generation
    local search = {
        handle = handle, work = work, source = source, started = os.time(), generation = generation,
        feed_generation = state.feed_generation,
    }
    state.search = search
    state.view, state.note = "search", _("Loading Shorts from ") .. source.label
    self:_requestRebuild(instance, context, "ui")
    local tick
    tick = function()
        if state.search ~= search or search.generation ~= state.search_generation or state.closed then return end
        if not state.pane_active or not self:_contextIsActive(context) then
            self:_cancelSearch(state)
            return
        end
        local code, log = self:_pollDetached(handle)
        if code == nil then
            if os.time() - search.started > 90 then
                self:_killDetached(handle)
                cleanupDirectory(work)
                if state.search == search then
                    state.search = nil
                    state.loading_pulse_scheduled = false
                    state.view, state.note = "home", _("The Shorts feed timed out.")
                    self:_requestRebuild(instance, context, "ui")
                end
                return
            end
            UIManager:scheduleIn(1, tick)
            return
        end
        cleanupDirectory(work)
        if state.search ~= search then return end
        state.search = nil
        state.loading_pulse_scheduled = false
        if code ~= 0 then
            state.view = "home"
            state.note = _("The Shorts feed could not be loaded. Check the network connection.")
        else
            local results = Shorts.rankResults(Shorts.parseShortsOutput(log, true), state.shorts_likes,
                state.seen_ids, state.interactions)
            -- `state.search == search` was checked above; retain the explicit
            -- generation too, so a future cancellation cannot install a stale
            -- queue in a new feed.
            if search.feed_generation ~= state.feed_generation then return end
            state.results, state.results_query = results, source.label
            state.short_queue, state.short_index = results, 1
            state.pending_next_index = nil
            state.view = "home"
            state.note = #results > 0
                and (_("Shorts ready from ") .. source.label)
                or _("No new Shorts found for this source. Try another hashtag.")
        end
        self:_requestRebuild(instance, context, "ui")
    end
    UIManager:scheduleIn(1, tick)
    return true
end

function Shorts:promptSearch(instance, context)
    local state = self:_state(instance)
    local initial = self.appdock and self.appdock:getYouTubeSettings().shorts_hashtags or state.query
    YouTube.promptText(_("Choose Shorts hashtags"), _("For example: #cats #technology"), initial, function(value)
        if value == "" then return end
        state.query = value
        self:reloadFeed(instance, context, value)
    end)
end

function Shorts:_current(state)
    local results = state.short_queue or state.results or {}
    return results[state.short_index] or results[1]
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

function Shorts:_startShort(instance, context, result, prefetch, prefetch_index)
    if type(result) ~= "table" or not validVideoId(result.id) or not isShortUrl(result.url, result.id) then
        self:_notify(instance, context, _("This entry is not a verified YouTube Short."))
        return nil
    end
    local slug = YouTube.slugify(result.title, result.id)
    local candidate = availableOutputPath(self:_outputDirectory(), slug)
    if result.thumbnail then self:_cacheThumbnail(result, candidate:gsub("%.bwr$", ".jpg")) end
    local job = self:_startJob(instance, self:_pipelineContext(instance, context), {
        kind = "url",
        source = result.url,
        title = result.title,
        video_id = result.id,
        duration = result.duration,
        slug = candidate:match("([^/]+)%.bwr$") or slug,
        prefetch = prefetch == true,
        prefetch_index = prefetch_index,
    })
    if not job then return nil end
    local state = self:_state(instance)
    job.shorts_queue = state.short_queue
    job.shorts_generation = state.feed_generation
    job.shorts_video_id = result.id
    job.shorts_target_index = prefetch_index or state.short_index
    -- `_startJob` can create an error-stage job when the detached downloader
    -- cannot be launched. The generic tick has no stage-error branch, so clear
    -- it here rather than blocking every Retry/Next action indefinitely.
    if job.stage == "error" then
        self:_failJob(instance, context, job, job.stage_message)
        return nil
    end
    return job
end

function Shorts:startVideo(instance, context, result)
    return self:_startShort(instance, context, result, false, nil)
end

function Shorts:_failJob(instance, context, job, message)
    YouTube._failJob(self, instance, context, job, message)
    local state = self:_state(instance)
    if state.job == job then state.job = nil end
    if state.pending_next_index == (job and job.prefetch_index) then state.pending_next_index = nil end
    state.view = "home"
    state.note = (job and job.stage_message) or message or _("The Short could not be loaded.")
    if state.pane_active then self:_requestRebuild(instance, context, "ui") end
end

function Shorts:_tick(instance, context)
    local state = self:_state(instance)
    local job = state.job
    YouTube._tick(self, instance, self:_pipelineContext(instance, context))
    -- The common pipeline returns early when it is entered with stage="error".
    -- That is useful for its diagnostic pane, but a Shorts feed has no such
    -- pane and would otherwise retain the failed job forever.
    if job and state.job == job and job.stage == "error" then
        self:_failJob(instance, context, job, job.stage_message)
    end
end

function Shorts:_cancelShortJob(instance)
    local state = self:_state(instance)
    if not state.job then return false end
    -- Do not let the generic cancellation synchronously rebuild an old pane:
    -- navigation will select the intended item before asking for one rebuild.
    YouTube.cancelJob(self, instance, nil)
    state.pending_next_index = nil
    return true
end

function Shorts:_playPath(instance, context, path)
    if not path then return false end
    local state = self:_state(instance)
    local result = self:_current(state)
    if result then
        self:_rememberSeen(state, result.id)
        self:_recordInteraction(instance, result, "views", 1)
    end
    local playing = YouTube.play(self, instance, context, path)
    if playing then state.view = "home" end
    return playing
end

function Shorts:_queuePrefetch(instance, context)
    local state = self:_state(instance)
    local next_index = state.short_index + 1
    local next_result = state.short_queue[next_index]
    if not next_result or next_result.path then return next_result and true or false end
    if state.job then
        if state.job.prefetch and state.job.prefetch_index == next_index then return true end
        return false
    end
    local job = self:_startShort(instance, context, next_result, true, next_index)
    if job then
        state.note = _("Current Short plays while the next one is loading")
        if context and context.requestRefresh then context.requestRefresh("fast") end
        return true
    end
    return false
end

function Shorts:togglePlayback(instance, context)
    local state = self:_state(instance)
    local result = self:_current(state)
    if not result then
        self:promptSearch(instance, context)
        return false
    end
    if result.path then
        if state.inline_playing == result.path and self.player.engine then
            self.player.engine:toggle()
            state.note = self.player.engine.paused and _("Paused") or _("Playing")
            self:_requestRebuild(instance, context, "fast")
            return true
        end
        local played = self:_playPath(instance, context, result.path)
        if played then self:_queuePrefetch(instance, context) end
        return played
    end
    if state.job and state.job.prefetch and state.job.prefetch_index == state.short_index then
        state.pending_next_index = state.short_index
        state.note = _("This Short is still loading and will start when ready")
        self:_requestRebuild(instance, context, "fast")
        return true
    end
    if state.job then
        state.note = _("This Short is already loading")
        if context and context.requestRefresh then context.requestRefresh("fast") end
        return true
    end
    return self:startVideo(instance, context, result) ~= nil
end

function Shorts:_selectShort(instance, context, target_index)
    local state = self:_state(instance)
    local result = state.short_queue[target_index]
    if not result then return false end
    self:stopInline(instance)
    if state.job then
        -- A second swipe while a conversion is running must select the new
        -- card, not silently retain the old prefetch and later autoplay it.
        if state.job.prefetch and state.job.prefetch_index == target_index
            and state.job.shorts_queue == state.short_queue
            and state.job.shorts_generation == state.feed_generation
        then
            state.short_index = target_index
            state.pending_next_index = target_index
            state.note = _("This Short is still loading")
            self:_requestRebuild(instance, context, "fast")
            return true
        end
        self:_cancelShortJob(instance)
    end
    state.short_index = target_index
    state.pending_next_index = nil
    if result.path then
        if self:_playPath(instance, context, result.path) then self:_queuePrefetch(instance, context) end
    else
        return self:startVideo(instance, context, result) ~= nil
    end
    return true
end

function Shorts:_playNext(instance, context)
    local state = self:_state(instance)
    if #state.short_queue == 0 then self:promptSearch(instance, context); return false end
    local current = self:_current(state)
    local next_index = state.short_index + 1
    if next_index > #state.short_queue then
        if current then self:_recordInteraction(instance, current, "skips", 1) end
        self:reloadFeed(instance, context)
        return true
    end
    -- The action that caused the move belongs to the item being left, not the
    -- next card which has not been viewed yet.
    if current then self:_recordInteraction(instance, current, "skips", 1) end
    return self:_selectShort(instance, context, next_index)
end

function Shorts:_playPrevious(instance, context)
    local state = self:_state(instance)
    if #state.short_queue == 0 then return false end
    if state.short_index <= 1 then
        state.note = _("This is the first Short")
        if context and context.requestRefresh then context.requestRefresh("fast") end
        return false
    end
    return self:_selectShort(instance, context, state.short_index - 1)
end

function Shorts:_finishJob(instance, context, job, without_audio)
    local before = self:_state(instance)
    -- A cancellation/reload may leave an already scheduled completion behind.
    -- Never let that stale completion mutate the replacement queue.
    if before.job ~= job then return end
    local is_prefetch = job and job.prefetch == true
    local prefetch_index = job and job.prefetch_index
    local target = job and job.target
    local queue_matches = job and job.shorts_queue == before.short_queue
        and job.shorts_generation == before.feed_generation
    -- The base completion would rebuild the job pane before Shorts has had a
    -- chance to attach the path and begin inline playback. Suppress that one
    -- intermediate rebuild; `_playPath` requests the final, correct pane.
    local suppress_base_rebuild = not is_prefetch
    if suppress_base_rebuild then before.view = "play" end
    YouTube._finishJob(self, instance, context, job, without_audio)
    local state = self:_state(instance)
    if suppress_base_rebuild and state.view == "play" then state.view = "home" end
    if state.closed or not target then return end
    if not queue_matches then
        state.note = _("A previous Shorts download finished after the feed changed")
        return
    end
    if is_prefetch then
        local next_result = state.short_queue[prefetch_index]
        if next_result and next_result.id == job.shorts_video_id then next_result.path = target else return end
        if state.pane_active and state.pending_next_index == prefetch_index then
            state.pending_next_index = nil
            state.short_index = prefetch_index
            self:_playPath(instance, context, target)
            self:_queuePrefetch(instance, context)
        else
            state.note = _("Next Short is ready")
            if state.pane_active then self:_requestRebuild(instance, context, "fast") end
        end
        return
    end
    local current = self:_current(state)
    if not current or current.id ~= job.shorts_video_id then return end
    current.path = target
    if state.pane_active then
        self:_playPath(instance, context, target)
        self:_queuePrefetch(instance, context)
    else
        state.note = _("Short is ready to play")
    end
end

function Shorts:reloadFeed(instance, context, query)
    local state = self:_state(instance)
    self:stopInline(instance)
    self:_cancelShortJob(instance)
    state.pending_next_index = nil
    state.results, state.short_queue, state.short_index = {}, {}, 1
    state.results_query = ""
    state.note = _("Refreshing Shorts…")
    return self:startSearch(instance, context, query or "")
end

function Shorts:openTools(instance, context)
    local state = self:_state(instance)
    self:stopInline(instance)
    state.view = "tools"
    self:_requestRebuild(instance, context, "ui")
end

function Shorts:_buildFeedPane(instance, context, state)
    local layout = shortsLayout(context)
    local width, height = layout.width, layout.height
    local margin, gap, video, detail = layout.margin, layout.gap, layout.video, layout.detail
    local result = self:_current(state)
    local active = result and result.path and state.inline_playing == result.path and self.player.engine
    local loading = state.search or (state.job and not state.job.prefetch)
    local empty_text
    if state.search then
        empty_text = _("Finding Shorts…")
    elseif state.job and not state.job.prefetch then
        empty_text = _("Loading this Short…")
    elseif not state.tools or not state.tools.ytdlp then
        empty_text = _("yt-dlp is not ready. Open Tools.")
    elseif not result then
        empty_text = state.note ~= "" and state.note or _("Choose Topics to start your Shorts feed")
    elseif result.path then
        empty_text = _("Tap Play to continue")
    else
        empty_text = _("Tap Play to load this Short")
    end
    local content = OverlapGroup:new{
        dimen = Geom:new{ w = width, h = height }, allow_mirroring = false,
        FrameContainer:new{
            width = width, height = height, padding = 0, bordersize = 0,
            background = Blitbuffer.COLOR_BLACK,
            emptySizedWidget(width, height),
        },
    }
    content.shorts_layout = layout

    local placeholder = FrameContainer:new{
        width = video.w, height = video.h, padding = 0, bordersize = 0,
        background = Blitbuffer.COLOR_DARK_GRAY,
        CenterContainer:new{
            dimen = Geom:new{ w = video.w, h = video.h },
            TextWidget:new{
                text = active and "" or "▶\n" .. fitText(empty_text, video.w - margin * 2, panePx(context, 11)),
                face = Font:getFace("smallinfofont", panePx(context, 11)), fgcolor = Blitbuffer.COLOR_WHITE,
                max_width = math.max(1, video.w - margin * 2), padding = 0,
            },
        },
    }
    placeholder.overlap_offset = { video.x, video.y }
    table.insert(content, placeholder)

    local canvas
    if active then
        canvas = Player.Canvas:new{ width = video.w, height = video.h }
        self.player.engine:setCanvas(canvas)
        self.player.engine:show(self.player.engine.position or 0)
    end
    local surface = FeedSurface:new{
        width = video.w, height = video.h, canvas = canvas,
        callback = function() self:togglePlayback(instance, context) end,
        swipe_callback = function(gesture)
            if gesture and gesture.direction == "north" then self:_playNext(instance, context)
            elseif gesture and gesture.direction == "south" then self:_playPrevious(instance, context) end
        end,
    }
    surface.overlap_offset = { video.x, video.y }
    table.insert(content, surface)

    if loading then
        self:_scheduleLoadingPulse(instance, context, state)
        local progress = CenterProgress:new{
            width = video.w, height = video.h,
            ratio = state.job and (state.job.percent or 0) / 100 or 0,
            indeterminate = not state.job, phase = state.loading_phase or 0,
        }
        state.loading_widget = progress
        progress.overlap_offset = { video.x, video.y }
        table.insert(content, progress)
    else
        state.loading_widget = nil
    end

    local header = TextWidget:new{
        text = "Shorts", face = Font:getFace("cfont", panePx(context, 16)),
        fgcolor = Blitbuffer.COLOR_WHITE, bold = true, padding = 0,
    }
    header.overlap_offset = { margin, layout.title_y }
    table.insert(content, header)
    local source = TextWidget:new{
        text = fitText(state.results_query and (_("For you · ") .. state.results_query) or self:_recommendationQuery(state),
            width - margin * 2, panePx(context, 9)),
        face = Font:getFace("smallinfofont", panePx(context, 9)), fgcolor = Blitbuffer.COLOR_GRAY_8,
        max_width = width - margin * 2, padding = 0,
    }
    source.overlap_offset = { margin, layout.source_y }
    table.insert(content, source)

    local utility_actions = {
        {
            symbol = state.shorts_likes[result and result.id or ""] and "♥" or "♡",
            title = result and (state.shorts_likes[result.id] and _("Liked") or _("Like")) or _("Like"),
            callback = function() self:toggleLike(instance, context, result) end,
        },
        { symbol = "#", title = _("Topics"), callback = function() self:promptSearch(instance, context) end },
        { symbol = "↻", title = _("Reload"), callback = function() self:reloadFeed(instance, context) end },
        { symbol = "⋮", title = _("Tools"), callback = function() self:openTools(instance, context) end },
    }
    for index, action in ipairs(utility_actions) do
        local chip = Chip:new{
            symbol = action.symbol, title = action.title, width = layout.utility_w, height = layout.utility_h,
            background = Blitbuffer.COLOR_GRAY_8, foreground = Blitbuffer.COLOR_BLACK, callback = action.callback,
        }
        chip.overlap_offset = { margin + (index - 1) * (layout.utility_w + gap), layout.utility_y }
        table.insert(content, chip)
    end

    local title = TextWidget:new{
        text = fitText(result and result.title or _("No Short selected"), detail.w, panePx(context, 11)),
        face = Font:getFace("smallinfofont", panePx(context, 11)), fgcolor = Blitbuffer.COLOR_WHITE,
        bold = true, max_width = detail.w, padding = 0,
    }
    title.overlap_offset = { detail.x, detail.y }
    table.insert(content, title)
    local meta = TextWidget:new{
        text = fitText(result and (result.uploader or _("YouTube")) or _("Swipe up/down on the video"), detail.w, panePx(context, 9)),
        face = Font:getFace("smallinfofont", panePx(context, 9)), fgcolor = Blitbuffer.COLOR_GRAY_8,
        max_width = detail.w, padding = 0,
    }
    meta.overlap_offset = { detail.x, detail.y + panePx(context, 16) }
    table.insert(content, meta)
    local note = TextWidget:new{
        text = fitText(loading and empty_text or (state.note ~= "" and state.note or _("Swipe for previous/next")),
            detail.w, panePx(context, 8)),
        face = Font:getFace("smallinfofont", panePx(context, 8)), fgcolor = Blitbuffer.COLOR_GRAY_8,
        max_width = detail.w, padding = 0,
    }
    note.overlap_offset = { detail.x, detail.y + panePx(context, 30) }
    table.insert(content, note)

    local narrow = layout.primary_w < panePx(context, 82)
    local playing = active and not self.player.engine.paused
    local primary_actions = {
        { symbol = "‹", title = narrow and _("Prev") or _("Previous"), callback = function() self:_playPrevious(instance, context) end },
        {
            symbol = playing and "Ⅱ" or "▶",
            title = playing and _("Pause") or _("Play"),
            callback = function() self:togglePlayback(instance, context) end,
        },
        { symbol = "›", title = narrow and _("Next") or _("Next"), callback = function() self:_playNext(instance, context) end },
    }
    for index, action in ipairs(primary_actions) do
        local chip = Chip:new{
            symbol = action.symbol, title = action.title, width = layout.primary_w, height = layout.primary_h,
            background = index == 2 and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_GRAY_8,
            foreground = Blitbuffer.COLOR_BLACK, callback = action.callback,
        }
        chip.overlap_offset = { margin + (index - 1) * (layout.primary_w + gap), layout.primary_y }
        table.insert(content, chip)
    end
    return content
end

function Shorts:_buildResultsPane(instance, context, state)
    return self:_buildFeedPane(instance, context, state)
end

function Shorts:_buildHomePane(instance, context, state)
    return self:_buildFeedPane(instance, context, state)
end

function Shorts:buildPane(instance, context)
    local state = self:_state(instance)
    state.closed = false
    state.pane_active = true
    if state.view == "home" and not state.tools.ready and not state.bootstrap_attempted
        and not (self.appdock and self.appdock.disableToolBootstrap) then
        self:_startToolBootstrap(instance, context, true)
    end
    if state.view == "home" and not state.feed_bootstrap_attempted and not state.search
        and #(state.short_queue or {}) == 0 and state.tools and state.tools.ytdlp then
        state.feed_bootstrap_attempted = true
        local start_feed = function()
            if not state.closed and state.pane_active and self:_contextIsActive(context)
                and not state.search and #(state.short_queue or {}) == 0
            then
                self:startSearch(instance, context, "")
            end
        end
        if UIManager.nextTick then UIManager:nextTick(start_feed) else UIManager:scheduleIn(0, start_feed) end
    end
    local content
    if state.view == "search" or (state.view == "job" and state.job) then
        content = self:_buildFeedPane(instance, context, state)
    elseif state.view == "setup" then
        content = YouTube._buildSetupPane(self, instance, context, state)
    elseif state.view == "tools" then
        content = YouTube._buildToolsPane(self, instance, context, state)
    else
        state.view = "home"
        content = self:_buildFeedPane(instance, context, state)
    end
    local pane = WidgetContainer:new{ dimen = Geom:new{ w = context.dimen.w, h = context.dimen.h } }
    pane[1] = content
    pane.onDeactivate = function()
        -- The host deactivates a pane before replacing it during a rebuild, but
        -- also when its DApp is minimized or hidden. Preserve the player only
        -- for an explicitly marked replacement; otherwise never keep video
        -- ticking into an offscreen pane.
        if state.transient_rebuild or state.inline_rebuild then
            state.transient_rebuild = false
            state.inline_rebuild = false
            return
        end
        state.pane_active = false
        state.loading_pulse_scheduled = false
        state.loading_widget = nil
        self:_cancelSearch(state)
        self:stopInline(instance)
    end
    return pane
end

function Shorts:onDAppClose(instance)
    local state = self:_state(instance)
    state.closed = true
    state.pane_active = false
    state.loading_pulse_scheduled = false
    self:_cancelSearch(state)
    if state.job then self:cancelJob(instance, nil) end
    self:stopInline(instance)
end

Shorts._test = {
    isShortUrl = Shorts.isShortUrl,
    parseShortsOutput = Shorts.parseShortsOutput,
    recommendationSources = Shorts.recommendationSources,
    rankResults = Shorts.rankResults,
    parseLikeProfiles = parseLikeProfiles,
    tagsFromText = tagsFromText,
    parseInteractions = parseInteractions,
    serializeInteractions = serializeInteractions,
    layout = shortsLayout,
    FeedSurface = FeedSurface,
}

return Shorts
