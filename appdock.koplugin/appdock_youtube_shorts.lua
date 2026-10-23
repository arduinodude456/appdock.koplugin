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
    local text = (self.symbol or "") .. (self.symbol ~= "" and "  " or "") .. (self.title or "")
    self[1] = FrameContainer:new{
        width = self.width, height = self.height, padding = scale(4), bordersize = 0,
        background = self.background,
        CenterContainer:new{
            dimen = Geom:new{ w = self.width - scale(8), h = self.height - scale(8) },
            TextWidget:new{
                text = text, face = Font:getFace("smallinfofont", scale(10)),
                fgcolor = self.foreground, bold = true, padding = 0,
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
    if self.canvas then self.canvas:paintTo(bb, x, y) end
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

function FeedSurface:onSwipeShortsFeed(gesture)
    if self.swipe_callback then self.swipe_callback(gesture) end
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
    return state
end

function Shorts.isShortUrl(value, expected_id)
    return isShortUrl(value, expected_id)
end

function Shorts.parseShortsOutput(text)
    local results, known = {}, {}
    for line in tostring(text or ""):gmatch("[^\r\n]+") do
        local fields = {}
        for value in (line .. "\t"):gmatch("(.-)\t") do fields[#fields + 1] = value end
        local id = fields[1]
        -- A full yt-dlp extraction normalizes `webpage_url` to /watch even
        -- when the item was enumerated from a Shorts tab. `original_url`
        -- retains the tab's /shorts/<id> identity and is therefore the field
        -- that must pass the strict feed check.
        local webpage_url = fields[7] or fields[6]
        if validVideoId(id) and not known[id] and isShortUrl(webpage_url, id) then
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
        if state.closed or not state.search then return end
        state.loading_phase = ((state.loading_phase or 0) + 1) % 20
        if state.loading_widget then state.loading_widget.phase = state.loading_phase end
        if context and context.requestRefresh then context.requestRefresh("fast") end
        self:_scheduleLoadingPulse(instance, context, state)
    end
    UIManager:scheduleIn(0.1, pulse)
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
    if context and context.requestRebuild then context.requestRebuild("fast") end
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
    local search = { handle = handle, work = work, source = source, started = os.time(), generation = generation }
    state.search = search
    state.view, state.note = "search", _("Loading Shorts from ") .. source.label
    if context and context.requestRebuild then context.requestRebuild("ui") end
    local tick
    tick = function()
        if state.search ~= search or search.generation ~= state.search_generation or state.closed then return end
        local code, log = self:_pollDetached(handle)
        if code == nil then
            if os.time() - search.started > 90 then
                self:_killDetached(handle)
                cleanupDirectory(work)
                if state.search == search then
                    state.search = nil
                    state.loading_pulse_scheduled = false
                    state.view, state.note = "home", _("The Shorts feed timed out.")
                    if context and context.requestRebuild then context.requestRebuild("ui") end
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
            local results = Shorts.rankResults(Shorts.parseShortsOutput(log), state.shorts_likes,
                state.seen_ids, state.interactions)
            state.results, state.results_query = results, source.label
            state.short_queue, state.short_index = results, 1
            state.view = "home"
            state.note = #results > 0
                and (_("Shorts ready from ") .. source.label)
                or _("No new Shorts found for this source. Try another hashtag.")
        end
        if context and context.requestRebuild then context.requestRebuild("ui") end
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
        self:startSearch(instance, context, value)
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
    return self:_startJob(instance, context, {
        kind = "url",
        source = result.url,
        title = result.title,
        video_id = result.id,
        duration = result.duration,
        slug = candidate:match("([^/]+)%.bwr$") or slug,
        prefetch = prefetch == true,
        prefetch_index = prefetch_index,
    })
end

function Shorts:startVideo(instance, context, result)
    return self:_startShort(instance, context, result, false, nil)
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
            if context and context.requestRefresh then context.requestRefresh("fast") end
            return true
        end
        local played = self:_playPath(instance, context, result.path)
        if played then self:_queuePrefetch(instance, context) end
        return played
    end
    if state.job and state.job.prefetch and state.job.prefetch_index == state.short_index then
        state.pending_next_index = state.short_index
        state.note = _("This Short is still loading and will start when ready")
        if context and context.requestRebuild then context.requestRebuild("fast") end
        return true
    end
    return self:startVideo(instance, context, result) ~= nil
end

function Shorts:_playNext(instance, context)
    local state = self:_state(instance)
    if #state.short_queue == 0 then self:promptSearch(instance, context); return end
    local next_index = state.short_index + 1
    if next_index > #state.short_queue then
        state.note = _("Loading a fresh Shorts feed")
        self:startSearch(instance, context, "")
        return
    end
    state.short_index = next_index
    local result = state.short_queue[next_index]
    self:_recordInteraction(instance, result, "skips", 1)
    if result.path then
        if self:_playPath(instance, context, result.path) then self:_queuePrefetch(instance, context) end
    elseif state.job and state.job.prefetch and state.job.prefetch_index == next_index then
        state.pending_next_index = next_index
        state.note = _("Next Short is still loading")
        if context and context.requestRebuild then context.requestRebuild("fast") end
    else
        self:startVideo(instance, context, result)
    end
end

function Shorts:_playPrevious(instance, context)
    local state = self:_state(instance)
    if #state.short_queue == 0 then return end
    state.short_index = state.short_index <= 1 and #state.short_queue or state.short_index - 1
    local result = self:_current(state)
    if result and result.path then
        if self:_playPath(instance, context, result.path) then self:_queuePrefetch(instance, context) end
    else
        self:startVideo(instance, context, result)
    end
end

function Shorts:_finishJob(instance, context, job, without_audio)
    local is_prefetch = job and job.prefetch == true
    local prefetch_index = job and job.prefetch_index
    local target = job and job.target
    YouTube._finishJob(self, instance, context, job, without_audio)
    local state = self:_state(instance)
    if state.closed or not target then return end
    if is_prefetch then
        local next_result = state.short_queue[prefetch_index]
        if next_result then next_result.path = target end
        if state.pending_next_index == prefetch_index then
            state.pending_next_index = nil
            state.short_index = prefetch_index
            self:_playPath(instance, context, target)
            self:_queuePrefetch(instance, context)
        else
            state.note = _("Next Short is ready")
            if context and context.requestRebuild then context.requestRebuild("fast") end
        end
        return
    end
    local current = self:_current(state)
    if current and current.id == job.video_id then current.path = target end
    self:_playPath(instance, context, target)
    self:_queuePrefetch(instance, context)
end

function Shorts:_buildFeedPane(instance, context, state)
    local width, height = context.dimen.w, context.dimen.h
    local margin = scale(14)
    local video_width = math.min(width - scale(28), math.floor(width * 0.58))
    local video_left = math.floor((width - video_width) / 2)
    local result = self:_current(state)
    local active = result and result.path and state.inline_playing == result.path and self.player.engine
    local content = OverlapGroup:new{
        dimen = Geom:new{ w = width, h = height }, allow_mirroring = false,
        FrameContainer:new{
            width = width, height = height, padding = 0, bordersize = 0,
            background = Blitbuffer.COLOR_BLACK,
            CenterContainer:new{
                dimen = Geom:new{ w = width, h = height },
                TextWidget:new{
                    text = result and "▶" or "#  Shorts",
                    face = Font:getFace("cfont", scale(result and 44 or 24)),
                    fgcolor = Blitbuffer.COLOR_WHITE, bold = true, padding = 0,
                },
            },
        },
    }
    local loading = state.search or (state.job and not state.job.prefetch)
    if loading then
        self:_scheduleLoadingPulse(instance, context, state)
        local progress = CenterProgress:new{
            width = width,
            height = height,
            ratio = state.job and (state.job.percent or 0) / 100 or 0,
            indeterminate = not state.job,
            phase = state.loading_phase or 0,
        }
        state.loading_widget = progress
        progress.overlap_offset = { 0, 0 }
        table.insert(content, progress)
    end
    local canvas
    if active then
        canvas = Player.Canvas:new{ width = video_width, height = height }
        self.player.engine:setCanvas(canvas)
        self.player.engine:show(self.player.engine.position or 0)
        canvas.overlap_offset = { video_left, 0 }
    end
    local surface = FeedSurface:new{
        width = width, height = height, canvas = canvas, gesture_inset_bottom = scale(128),
        callback = function() self:togglePlayback(instance, context) end,
        swipe_callback = function(gesture)
            if gesture and gesture.direction == "north" then self:_playNext(instance, context)
            elseif gesture and gesture.direction == "south" then self:_playPrevious(instance, context) end
        end,
    }
    table.insert(content, surface)
    local header = TextWidget:new{
        text = "Shorts", face = Font:getFace("cfont", scale(16)),
        fgcolor = Blitbuffer.COLOR_WHITE, bold = true, padding = 0,
    }
    header.overlap_offset = { margin, margin }
    table.insert(content, header)
    local source = TextWidget:new{
        text = state.results_query and (_("For you · ") .. state.results_query) or self:_recommendationQuery(state),
        face = Font:getFace("smallinfofont", scale(9)), fgcolor = Blitbuffer.COLOR_GRAY_8,
        max_width = width - margin * 2, padding = 0,
    }
    source.overlap_offset = { margin, scale(38) }
    table.insert(content, source)
    local top_actions = {
        { symbol = "⌕", title = "", callback = function() self:promptSearch(instance, context) end },
        { symbol = "⋮", title = "", callback = function() self:promptSearch(instance, context) end },
    }
    local top_size, top_gap = scale(34), scale(5)
    for index, action in ipairs(top_actions) do
        local chip = Chip:new{
            symbol = action.symbol, title = action.title, width = top_size, height = top_size,
            background = Blitbuffer.COLOR_BLACK, foreground = Blitbuffer.COLOR_WHITE,
            callback = action.callback,
        }
        chip.overlap_offset = { width - margin - (2 - index + 1) * (top_size + top_gap), scale(8) }
        table.insert(content, chip)
    end
    local title = TextWidget:new{
        text = result and (result.title or "") or _("Set hashtags to receive only YouTube Shorts"),
        face = Font:getFace("smallinfofont", scale(11)), fgcolor = Blitbuffer.COLOR_WHITE,
        max_width = width - margin * 2, padding = 0,
    }
    title.overlap_offset = { video_left + margin, height - scale(96) }
    table.insert(content, title)
    local meta = TextWidget:new{
        text = result and (result.uploader or _("YouTube")) or _("Tap to play · swipe up for next"),
        face = Font:getFace("smallinfofont", scale(10)), fgcolor = Blitbuffer.COLOR_GRAY_8,
        max_width = width - margin * 2, padding = 0,
    }
    meta.overlap_offset = { video_left + margin, height - scale(70) }
    table.insert(content, meta)
    local action_w, action_h, action_gap = scale(52), scale(40), scale(6)
    local actions = {
        {
            symbol = state.shorts_likes[result and result.id or ""] and "♥" or "♡",
            title = result and (state.shorts_likes[result.id] and _("Liked") or _("Like")) or "",
            callback = function() self:toggleLike(instance, context, result) end,
        },
        { symbol = "↗", title = _("Share"), callback = function() self:promptSearch(instance, context) end },
        { symbol = "›", title = _("Next"), callback = function() self:_playNext(instance, context) end },
        { symbol = "#", title = _("Topics"), callback = function() self:promptSearch(instance, context) end },
    }
    for index, action in ipairs(actions) do
        local chip = Chip:new{
            symbol = action.symbol, title = action.title, width = action_w, height = action_h,
            background = Blitbuffer.COLOR_BLACK, foreground = Blitbuffer.COLOR_WHITE, callback = action.callback,
        }
        chip.overlap_offset = { width - margin - action_w, math.floor(height * .47) + (index - 1) * (action_h + action_gap) }
        table.insert(content, chip)
    end
    local footer = TextWidget:new{
        text = loading and (state.search and _("Finding your first Short…") or _("Loading the next Short…"))
            or (state.note ~= "" and state.note or _("Swipe up for next · tap to pause")),
        face = Font:getFace("smallinfofont", scale(9)), fgcolor = Blitbuffer.COLOR_GRAY_8,
        max_width = width - margin * 2, padding = 0,
    }
    footer.overlap_offset = { video_left + margin, height - scale(38) }
    table.insert(content, footer)
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
    if state.view == "home" and not state.tools.ready and not state.bootstrap_attempted
        and not (self.appdock and self.appdock.disableToolBootstrap) then
        self:_startToolBootstrap(instance, context, true)
    end
    if state.view == "home" and not state.feed_bootstrap_attempted and not state.search
        and #(state.short_queue or {}) == 0 and state.tools and state.tools.ytdlp then
        state.feed_bootstrap_attempted = true
        local start_feed = function()
            if not state.closed and not state.search and #(state.short_queue or {}) == 0 then
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
        -- A DApp pane is rebuilt frequently while the prefetched file progresses.
        -- Keep the inline player alive across those transient replacements; the
        -- DApp definition calls onDAppClose for a real close.
        state.inline_rebuild = false
    end
    return pane
end

function Shorts:onDAppClose(instance)
    local state = self:_state(instance)
    state.closed = true
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
}

return Shorts
