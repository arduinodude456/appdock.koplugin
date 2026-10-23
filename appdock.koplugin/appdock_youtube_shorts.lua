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

local DeviceModule
local function scale(value)
    if DeviceModule == nil then
        local ok, Device = pcall(require, "device")
        DeviceModule = ok and Device or false
    end
    return DeviceModule and DeviceModule.screen:scaleBySize(value) or value
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

local Widget = require("ui/widget/widget")
local TextBoxOK, TextBoxWidget = pcall(require, "ui/widget/textboxwidget")
if not TextBoxOK then TextBoxWidget = nil end

-- Palette: a pure black canvas with white content and a few greys, which
-- stays crisp on e-ink and still looks right on colour panels.
local WHITE = Blitbuffer.COLOR_WHITE
local BLACK = Blitbuffer.COLOR_BLACK
local LIGHT = Blitbuffer.COLOR_GRAY_B or Blitbuffer.COLOR_LIGHT_GRAY or Blitbuffer.COLOR_GRAY_8
local TRACK = Blitbuffer.COLOR_GRAY_4 or Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_GRAY_8
local ACCENT = Blitbuffer.COLOR_RED or Blitbuffer.COLOR_GRAY_8 or Blitbuffer.COLOR_DARK_GRAY

----------------------------------------------------------------------------
-- Drawing primitives. Icons are drawn from shapes, not font glyphs, because
-- symbols such as heart or magnifier are missing in many e-reader fonts.
----------------------------------------------------------------------------

local function fillDisk(bb, cx, cy, r, color)
    if r <= 0 then return end
    for dy = -r, r do
        local dx = math.floor(math.sqrt(r * r - dy * dy) + 0.5)
        bb:paintRect(cx - dx, cy + dy, dx * 2 + 1, 1, color)
    end
end

local function fillRoundRect(bb, x, y, w, h, r, color)
    if w <= 0 or h <= 0 then return end
    r = math.max(0, math.min(r, math.floor(math.min(w, h) / 2)))
    if r == 0 then bb:paintRect(x, y, w, h, color); return end
    bb:paintRect(x + r, y, w - 2 * r, h, color)
    bb:paintRect(x, y + r, r, h - 2 * r, color)
    bb:paintRect(x + w - r, y + r, r, h - 2 * r, color)
    fillDisk(bb, x + r, y + r, r, color)
    fillDisk(bb, x + w - r - 1, y + r, r, color)
    fillDisk(bb, x + r, y + h - r - 1, r, color)
    fillDisk(bb, x + w - r - 1, y + h - r - 1, r, color)
end

local function thickLine(bb, x1, y1, x2, y2, thickness, color)
    local steps = math.max(math.abs(x2 - x1), math.abs(y2 - y1), 1)
    local half = math.floor(thickness / 2)
    for i = 0, steps do
        local x = math.floor(x1 + (x2 - x1) * i / steps + 0.5)
        local y = math.floor(y1 + (y2 - y1) * i / steps + 0.5)
        bb:paintRect(x - half, y - half, thickness, thickness, color)
    end
end

local function fillTriangleRight(bb, x, y, w, h, color)
    for j = 0, h - 1 do
        local peak = 1 - math.abs((2 * j + 1) / h - 1)
        local row_w = math.floor(w * peak + 0.5)
        if row_w > 0 then bb:paintRect(x, y + j, row_w, 1, color) end
    end
end

-- Classic implicit heart curve, scanned row by row. `s` is the half width.
local function fillHeart(bb, cx, cy, s, color)
    if s < 2 then return end
    local k = s / 1.25
    local extent = math.ceil(1.15 * k)
    for dy = -extent, extent do
        local y = 0.1 - dy / k
        local run_start
        for dx = -s, s + 1 do
            local inside = false
            if dx <= s then
                local x = dx / k
                local a = x * x + y * y - 1
                inside = a * a * a - x * x * y * y * y <= 0
            end
            if inside and not run_start then
                run_start = dx
            elseif not inside and run_start then
                bb:paintRect(cx + run_start, cy + dy, dx - run_start, 1, color)
                run_start = nil
            end
        end
    end
end

local function drawGlyph(bb, kind, cx, cy, s, fg, bg, filled)
    local t = math.max(2, math.floor(s * 0.22))
    local half = math.floor(t / 2)
    if kind == "heart" then
        local oy = cy + math.floor(s * 0.05)
        fillHeart(bb, cx, oy, s, fg)
        if not filled then fillHeart(bb, cx, oy + 1, s - t - 1, bg) end
    elseif kind == "search" then
        local r = math.floor(s * 0.62)
        local ox, oy = cx - math.floor(s * 0.18), cy - math.floor(s * 0.18)
        fillDisk(bb, ox, oy, r, fg)
        fillDisk(bb, ox, oy, r - t, bg)
        local a = math.floor(r * 0.72)
        thickLine(bb, ox + a, oy + a, cx + s - half, cy + s - half, t, fg)
    elseif kind == "share" then
        local w = math.floor(s * 0.8)
        local bottom = cy + math.floor(s * 0.85)
        local tray_top = cy + math.floor(s * 0.15)
        bb:paintRect(cx - w, tray_top, t, bottom - tray_top + 1, fg)
        bb:paintRect(cx + w - t + 1, tray_top, t, bottom - tray_top + 1, fg)
        bb:paintRect(cx - w, bottom - t + 1, 2 * w + 1, t, fg)
        local tip = cy - math.floor(s * 0.85)
        local head = math.floor(s * 0.5)
        bb:paintRect(cx - half, tip + t, t, s, fg)
        thickLine(bb, cx - head, tip + head, cx, tip, t, fg)
        thickLine(bb, cx + head, tip + head, cx, tip, t, fg)
    elseif kind == "next" then
        local w, h = math.floor(s * 0.8), math.floor(s * 0.45)
        thickLine(bb, cx - w, cy - h, cx, cy + h, t, fg)
        thickLine(bb, cx + w, cy - h, cx, cy + h, t, fg)
    elseif kind == "hash" then
        local d, l = math.floor(s * 0.3), math.floor(s * 0.85)
        bb:paintRect(cx - d - half, cy - l, t, 2 * l + 1, fg)
        bb:paintRect(cx + d - half, cy - l, t, 2 * l + 1, fg)
        bb:paintRect(cx - l, cy - d - half, 2 * l + 1, t, fg)
        bb:paintRect(cx - l, cy + d - half, 2 * l + 1, t, fg)
    elseif kind == "more" then
        local r, gap = math.max(2, math.floor(t * 0.9)), math.floor(s * 0.62)
        for i = -1, 1 do fillDisk(bb, cx, cy + i * gap, r, fg) end
    elseif kind == "play" then
        local h, w = math.floor(s * 1.5), math.floor(s * 1.3)
        fillTriangleRight(bb, cx - math.floor(w * 0.35), cy - math.floor(h / 2), w, h, fg)
    elseif kind == "pause" then
        local bar, h = math.max(3, math.floor(s * 0.4)), math.floor(s * 1.4)
        bb:paintRect(cx - bar - math.floor(bar / 2), cy - math.floor(h / 2), bar, h, fg)
        bb:paintRect(cx + math.floor(bar / 2), cy - math.floor(h / 2), bar, h, fg)
    elseif kind == "logo" then
        local h = math.floor(s * 1.42)
        fillRoundRect(bb, cx - s, cy - math.floor(h / 2), s * 2, h, math.floor(h * 0.3), ACCENT)
        local tw, th = math.floor(s * 0.62), math.floor(s * 0.8)
        fillTriangleRight(bb, cx - math.floor(tw * 0.32), cy - math.floor(th / 2), tw, th, WHITE)
    end
end

local function makeText(text, name, size, color, bold, max_width)
    return TextWidget:new{
        text = (text and text ~= "") and text or " ",
        face = Font:getFace(name, size), fgcolor = color, bgcolor = BLACK,
        bold = bold or false, max_width = max_width, padding = 0,
    }
end

-- Multi-line text when TextBoxWidget exists, else a single truncated line.
local function textBlock(text, size, color, width, lines, align)
    local face = Font:getFace("smallinfofont", size)
    if TextBoxWidget then
        local ok, widget = pcall(TextBoxWidget.new, TextBoxWidget, {
            text = (text and text ~= "") and text or " ", face = face, width = width,
            fgcolor = color, bgcolor = BLACK, alignment = align or "left",
            height = math.floor(size * 1.5 * lines),
            height_adjust = true, height_overflow_show_ellipsis = true,
        })
        if ok and widget then return widget end
    end
    return makeText(text, "smallinfofont", size, color, false, width)
end

----------------------------------------------------------------------------
-- Widgets
----------------------------------------------------------------------------

-- Black page with a framed well where the video is shown.
local Backdrop = Widget:extend{ width = 0, height = 0, well = nil, rule_y = nil }

function Backdrop:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
end

function Backdrop:getSize() return self.dimen end

function Backdrop:paintTo(bb, x, y)
    bb:paintRect(x, y, self.width, self.height, BLACK)
    if self.rule_y then bb:paintRect(x, y + self.rule_y, self.width, 1, TRACK) end
    local well = self.well
    if well then
        local b = math.max(2, scale(2))
        local wx, wy = x + well.x - b, y + well.y - b
        local ww, wh = well.w + b * 2, well.h + b * 2
        bb:paintRect(wx, wy, ww, b, TRACK)
        bb:paintRect(wx, wy + wh - b, ww, b, TRACK)
        bb:paintRect(wx, wy, b, wh, TRACK)
        bb:paintRect(wx + ww - b, wy, b, wh, TRACK)
    end
end

-- A bare icon, optionally inside a ring, optionally tappable.
local Icon = InputContainer:extend{
    kind = "heart", size = 40, disk = false, filled = false,
    foreground = WHITE, background = BLACK, callback = nil,
}

function Icon:init()
    self.dimen = Geom:new{ w = self.size, h = self.size }
    if self.callback then
        self.pad = scale(6)
        self.hit = Geom:new{ x = 0, y = 0, w = self.size + self.pad * 2, h = self.size + self.pad * 2 }
        self.ges_events = { TapShortsAction = { GestureRange:new{ ges = "tap", range = self.hit } } }
    end
end

function Icon:getSize() return self.dimen end

function Icon:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    if self.hit then self.hit.x, self.hit.y = x - self.pad, y - self.pad end
    local r = math.floor(self.size / 2)
    local cx, cy = x + r, y + r
    local s
    if self.kind == "logo" then
        s = r
    elseif self.disk then
        fillDisk(bb, cx, cy, r, self.foreground)
        fillDisk(bb, cx, cy, r - math.max(2, math.floor(r * 0.08)), self.background)
        s = math.floor(self.size * 0.26)
    else
        s = math.floor(self.size * 0.36)
    end
    drawGlyph(bb, self.kind, cx, cy, s, self.foreground, self.background, self.filled)
end

function Icon:onTapShortsAction()
    if self.callback then self.callback() end
    return true
end

-- Round action button with a caption underneath. Active state inverts it.
local ActionButton = InputContainer:extend{
    kind = "heart", label = "", active = false, width = 56, size = 44, callback = nil,
}

function ActionButton:init()
    self.label_widget = makeText(self.label, "smallinfofont", scale(9), WHITE, true, self.width)
    self.gap = scale(3)
    self.dimen = Geom:new{ w = self.width, h = self.size + self.gap + self.label_widget:getSize().h }
    self.hit = Geom:new{ x = 0, y = 0, w = self.dimen.w, h = self.dimen.h }
    self.ges_events = { TapShortsAction = { GestureRange:new{ ges = "tap", range = self.hit } } }
end

function ActionButton:getSize() return self.dimen end

function ActionButton:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    self.hit.x, self.hit.y = x, y
    local r = math.floor(self.size / 2)
    local cx, cy = x + math.floor(self.width / 2), y + r
    local fg, bg = WHITE, BLACK
    if self.active then fg, bg = BLACK, WHITE end
    fillDisk(bb, cx, cy, r, WHITE)
    fillDisk(bb, cx, cy, r - math.max(2, math.floor(r * 0.08)), bg)
    drawGlyph(bb, self.kind, cx, cy, math.floor(self.size * 0.28), fg, bg, self.active)
    local label_w = self.label_widget:getSize().w
    self.label_widget:paintTo(bb, x + math.floor((self.width - label_w) / 2), y + self.size + self.gap)
end

function ActionButton:onTapShortsAction()
    if self.callback then self.callback() end
    return true
end

-- Centered loading bar with a caption, drawn over the video well.
local CenterProgress = InputContainer:extend{
    ratio = 0, indeterminate = false, phase = 0, width = 0, height = 0, label = nil,
}

function CenterProgress:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    if self.label and self.label ~= "" then
        self.label_widget = makeText(self.label, "smallinfofont", scale(11), WHITE, true,
            math.max(scale(40), self.width - scale(24)))
    end
end

function CenterProgress:getSize() return self.dimen end

-- Moving elements must be pure black and white. Grey levels break the fast
-- dirty refresh on e-ink, so the track is a 2px checkerboard and the fill is
-- solid white inside a white frame.
local function ditherRect(bb, x, y, w, h)
    bb:paintRect(x, y, w, h, BLACK)
    local cell = 2
    for row = 0, math.ceil(h / cell) - 1 do
        local row_h = math.min(cell, h - row * cell)
        for col = row % 2, math.ceil(w / cell) - 1, 2 do
            bb:paintRect(x + col * cell, y + row * cell, math.min(cell, w - col * cell), row_h, WHITE)
        end
    end
end

function CenterProgress:paintTo(bb, x, y)
    local bar_w = math.max(scale(60), math.min(self.width - scale(48), scale(220)))
    local frame = math.max(2, scale(2))
    local inner_h = math.max(4, scale(6))
    local bar_h = inner_h + frame * 2
    local left = x + math.floor((self.width - bar_w) / 2)
    local top = y + math.floor((self.height - bar_h) / 2)
    if self.label_widget then
        local size = self.label_widget:getSize()
        self.label_widget:paintTo(bb, x + math.floor((self.width - size.w) / 2), top - size.h - scale(12))
    end
    bb:paintRect(left, top, bar_w, bar_h, WHITE)
    local ix, iy, iw = left + frame, top + frame, bar_w - frame * 2
    ditherRect(bb, ix, iy, iw, inner_h)
    local fill_x, fill_w = ix, 0
    if self.indeterminate then
        fill_w = math.max(scale(26), math.floor(iw * 0.3))
        local p = (self.phase or 0) % 20
        local t = p < 10 and p / 10 or (20 - p) / 10
        fill_x = ix + math.floor((iw - fill_w) * t)
    else
        fill_w = math.floor(iw * math.max(0, math.min(1, self.ratio or 0)))
    end
    if fill_w > 0 then bb:paintRect(fill_x, iy, fill_w, inner_h, WHITE) end
end

-- Tap and swipe surface that sits exactly on the video well, so it never
-- overlaps the header, the info block or the action buttons.
local FeedSurface = InputContainer:extend{
    width = 0, height = 0, canvas = nil, callback = nil, swipe_callback = nil,
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
    for _, event in pairs(self.ges_events) do
        local range = event[1].range
        range.x, range.y, range.w, range.h = x, y, self.width, self.height
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
        local webpage_url = (isShortUrl(fields[7], id) and trim(fields[7]))
            or (isShortUrl(fields[6], id) and trim(fields[6])) or nil
        if validVideoId(id) and not known[id] and webpage_url then
            known[id] = true
            local duration = tonumber(fields[3])
            results[#results + 1] = {
                id = id,
                order = #results + 1,
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
        -- Equal scores keep the order YouTube returned them in.
        return (left.order or 0) < (right.order or 0)
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
        if channel == "" then self:_enrichLike(instance, context, result.id) end
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
    -- A flat listing returns the whole Shorts tab in seconds. A full
    -- extraction of every item took minutes on an e-reader and caused the
    -- "timed out" message. Flat entries have no creator, so a Like looks the
    -- creator up afterwards in the background (see _enrichLike).
    local command = shellQuote(tools.ytdlp)
        .. " --no-warnings --no-cache-dir --ignore-errors --flat-playlist"
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
            if os.time() - search.started > 120 then
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
    if result.thumbnail then self:_cacheThumbnail(result, (candidate:gsub("%.bwr$", ".jpg"))) end
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
        state.play_started, state.play_result_id = os.time(), result.id
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
            if context and context.requestRebuild then context.requestRebuild("fast") end
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
    self:_leave(instance, self:_current(state))
    state.short_index = next_index
    local result = state.short_queue[next_index]
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
    self:_leave(instance, self:_current(state))
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

-- Flat feeds carry no creator. After a Like, look the creator up once in a
-- detached process and store it, so later feeds can use it.
function Shorts:_enrichLike(instance, context, id)
    local state = self:_state(instance)
    local profile = state.shorts_likes[id]
    if not profile or profile.channel ~= "" or not (state.tools and state.tools.ytdlp) then return end
    state.enriching = state.enriching or {}
    if state.enriching[id] then return end
    state.enriching[id] = true
    local work = jobDirectory()
    local command = shellQuote(state.tools.ytdlp)
        .. " --no-warnings --no-cache-dir --skip-download --print "
        .. shellQuote("%(uploader_id)s\t%(channel_id)s")
        .. " " .. shellQuote("https://www.youtube.com/shorts/" .. id)
    local handle = self:_startDetached(command, work, "enrich")
    if not handle then
        cleanupDirectory(work)
        state.enriching[id] = nil
        return
    end
    local started = os.time()
    local tick
    tick = function()
        if state.closed then
            self:_killDetached(handle)
            cleanupDirectory(work)
            state.enriching[id] = nil
            return
        end
        local code, log = self:_pollDetached(handle)
        if code == nil and os.time() - started < 60 then
            UIManager:scheduleIn(2, tick)
            return
        end
        if code == nil then self:_killDetached(handle) end
        cleanupDirectory(work)
        state.enriching[id] = nil
        if code ~= 0 then return end
        local user_id, channel_id = tostring(log or ""):match("([^\t\r\n]*)\t([^\t\r\n]*)")
        local channel = normalizeChannel(user_id) or normalizeChannelId(channel_id)
        local current = state.shorts_likes[id]
        if channel and current and current.channel == "" then
            current.channel = channel
            self:_persistLikes(state)
        end
    end
    UIManager:scheduleIn(2, tick)
end

-- Called when the person leaves a Short. Records the watch time and counts a
-- skip only when the Short was left almost immediately.
function Shorts:_leave(instance, result)
    local state = self:_state(instance)
    if not result or not state.play_started or state.play_result_id ~= result.id then return end
    local watched = math.max(0, os.time() - state.play_started)
    state.play_started, state.play_result_id = nil, nil
    local item = state.interactions[result.id] or { views = 0, skips = 0, seconds = 0 }
    item.seconds = (tonumber(item.seconds) or 0) + math.min(watched, 600)
    if watched < 4 then item.skips = (tonumber(item.skips) or 0) + 1 end
    state.interactions[result.id] = item
    self:_persistLikes(state)
end

function Shorts:shareCurrent(instance, context)
    local state = self:_state(instance)
    local result = self:_current(state)
    if not result or not validVideoId(result.id) then
        self:_notify(instance, context, _("Nothing to share yet."))
        return
    end
    local url = "https://www.youtube.com/shorts/" .. result.id
    local copied = false
    local ok_device, Device = pcall(require, "device")
    if ok_device and Device and Device.input and Device.input.setClipboardText then
        copied = pcall(Device.input.setClipboardText, url)
    end
    local ok_msg, InfoMessage = pcall(require, "ui/widget/infomessage")
    if ok_msg and InfoMessage then
        UIManager:show(InfoMessage:new{
            text = (copied and _("Link copied:") or _("Link:")) .. "\n" .. url,
            timeout = 8,
        })
    end
end

function Shorts:clearLikes(instance, context)
    local ok, ConfirmBox = pcall(require, "ui/widget/confirmbox")
    local function clear()
        local state = self:_state(instance)
        state.shorts_likes, state.shorts_like_order = {}, {}
        state.interactions = {}
        state.note = _("Likes cleared")
        self:_persistLikes(state)
        if context and context.requestRebuild then context.requestRebuild("fast") end
    end
    if ok and ConfirmBox then
        UIManager:show(ConfirmBox:new{
            text = _("Clear all liked Shorts and the viewing history used for recommendations?"),
            ok_text = _("Clear"),
            ok_callback = clear,
        })
    else
        clear()
    end
end

function Shorts:showMenu(instance, context)
    local ok, ButtonDialog = pcall(require, "ui/widget/buttondialog")
    if not ok or not ButtonDialog then
        self:promptSearch(instance, context)
        return
    end
    local dialog
    local function entry(text, action)
        return { { text = text, callback = function()
            UIManager:close(dialog)
            action()
        end } }
    end
    dialog = ButtonDialog:new{
        title = _("Shorts"),
        buttons = {
            entry(_("Choose hashtags"), function() self:promptSearch(instance, context) end),
            entry(_("Reload feed"), function() self:startSearch(instance, context, "") end),
            entry(_("Clear likes"), function() self:clearLikes(instance, context) end),
        },
    }
    UIManager:show(dialog)
end

function Shorts:_buildFeedPane(instance, context, state)
    local width, height = context.dimen.w, context.dimen.h
    local margin = scale(14)
    local result = self:_current(state)
    local engine = self.player and self.player.engine
    local active = result and result.path and state.inline_playing == result.path and engine
    local paused = active and engine.paused
    local loading = state.search or (state.job and not state.job.prefetch)
    local queue = state.short_queue or {}

    -- Layout: header on top, info block at the bottom, a 9:16 video well in
    -- between. Action buttons sit beside the well when the side gutter is wide
    -- enough, otherwise in a row below the info block.
    local header_h = math.min(scale(60), math.floor(height * 0.12))
    local info_h = math.min(scale(108), math.floor(height * 0.34))
    local action_size, action_w, action_h, action_gap = scale(44), scale(56), scale(68), scale(8)
    local function layout(bottom_h)
        local band_h = math.max(scale(80), height - header_h - bottom_h)
        local video_w = math.max(scale(90), math.min(width - margin * 2, math.floor(band_h * 9 / 16)))
        return band_h, video_w
    end
    local bottom_h = info_h
    local band_h, video_w = layout(bottom_h)
    local side = (width - video_w) / 2 >= action_w + margin * 2
    if not side then
        bottom_h = info_h + action_h + margin
        band_h, video_w = layout(bottom_h)
    end
    local band_top, video_h = header_h, band_h
    local video_left = math.floor((width - video_w) / 2)

    local content = OverlapGroup:new{ dimen = Geom:new{ w = width, h = height }, allow_mirroring = false }
    local function put(widget, x, y)
        widget.overlap_offset = { math.floor(x), math.floor(y) }
        table.insert(content, widget)
        return widget
    end

    put(Backdrop:new{
        width = width, height = height, rule_y = header_h - 1,
        well = { x = video_left, y = band_top, w = video_w, h = video_h },
    }, 0, 0)

    -- Video surface (taps and swipes) with the inline player canvas.
    local canvas
    if active then
        canvas = Player.Canvas:new{ width = video_w, height = video_h }
        engine:setCanvas(canvas)
        engine:show(engine.position or 0)
    end
    put(FeedSurface:new{
        width = video_w, height = video_h, canvas = canvas,
        callback = function() self:togglePlayback(instance, context) end,
        swipe_callback = function(gesture)
            if gesture and gesture.direction == "north" then self:_playNext(instance, context)
            elseif gesture and gesture.direction == "south" then self:_playPrevious(instance, context) end
        end,
    }, video_left, band_top)

    -- Center overlay: loading bar, or a big play / hashtag hint when idle.
    if loading then
        self:_scheduleLoadingPulse(instance, context, state)
        local label
        if state.job then
            label = _("Preparing video") .. " " .. tostring(math.floor(state.job.percent or 0)) .. "%"
        else
            label = _("Finding Shorts…")
        end
        local progress = CenterProgress:new{
            width = video_w, height = video_h, label = label,
            ratio = state.job and (state.job.percent or 0) / 100 or 0,
            indeterminate = not state.job, phase = state.loading_phase or 0,
        }
        state.loading_widget = progress
        put(progress, video_left, band_top)
    else
        state.loading_widget = nil
        if not active or paused then
            local size = scale(76)
            local cy = band_top + math.floor(video_h / 2)
            if result then
                put(Icon:new{ kind = "play", size = size, disk = true },
                    video_left + (video_w - size) / 2, cy - size / 2)
            else
                put(Icon:new{ kind = "hash", size = size, disk = true },
                    video_left + (video_w - size) / 2, cy - size)
                local hint_w = video_w - margin * 2
                local head = makeText(_("Pick your topics"), "cfont", scale(15), WHITE, true, hint_w)
                put(head, video_left + (video_w - head:getSize().w) / 2, cy + scale(14))
                local hint = textBlock(_("Tap here and enter a few hashtags to fill your feed."),
                    scale(11), LIGHT, hint_w, 3, "center")
                put(hint, video_left + margin, cy + scale(14) + head:getSize().h + scale(6))
            end
        end
    end

    -- Header.
    local logo_size, icon_size = scale(30), scale(38)
    put(Icon:new{ kind = "logo", size = logo_size }, margin, (header_h - logo_size) / 2)
    local title = makeText("Shorts", "cfont", scale(20), WHITE, true)
    local title_x = margin + logo_size + scale(10)
    put(title, title_x, (header_h - title:getSize().h) / 2)
    local icons_left = width - margin - icon_size * 2 - scale(6)
    put(Icon:new{ kind = "search", size = icon_size,
        callback = function() self:promptSearch(instance, context) end },
        icons_left, (header_h - icon_size) / 2)
    put(Icon:new{ kind = "more", size = icon_size,
        callback = function() self:showMenu(instance, context) end },
        width - margin - icon_size, (header_h - icon_size) / 2)
    local source_x = title_x + title:getSize().w + scale(12)
    local source_w = icons_left - scale(10) - source_x
    if source_w > scale(60) then
        local source = makeText(
            state.results_query and (_("For you · ") .. state.results_query) or self:_recommendationQuery(state),
            "smallinfofont", scale(10), LIGHT, false, source_w)
        put(source, source_x, (header_h - source:getSize().h) / 2)
    end

    -- Info block under the video.
    local info_w = math.min(width - margin * 2, math.max(video_w, scale(360)))
    local info_x = math.floor((width - info_w) / 2)
    local y = band_top + band_h + scale(8)
    local counter
    if #queue > 0 then
        counter = makeText(string.format("%d / %d", math.min(state.short_index or 1, #queue), #queue),
            "smallinfofont", scale(10), LIGHT)
    end
    local counter_w = counter and counter:getSize().w or 0
    local creator = makeText(result and (result.uploader or result.uploader_id) or _("YouTube Shorts"),
        "cfont", scale(13), WHITE, true, info_w - counter_w - scale(10))
    put(creator, info_x, y)
    if counter then
        put(counter, info_x + info_w - counter_w, y + (creator:getSize().h - counter:getSize().h) / 2)
    end
    y = y + creator:getSize().h + scale(4)
    local headline = textBlock(result and result.title or _("Your Shorts feed starts with a few hashtags"),
        scale(12), WHITE, info_w, 2)
    put(headline, info_x, y)
    y = y + headline:getSize().h + scale(6)
    local note = state.note
    local footer = makeText((note and note ~= "") and note or _("Swipe up for next · tap to pause"),
        "smallinfofont", scale(9), LIGHT, false, info_w)
    put(footer, info_x, y)

    -- Actions.
    local liked = result and state.shorts_likes[result.id] ~= nil
    local actions = {
        { kind = "heart", label = liked and _("Liked") or _("Like"), active = liked,
          callback = function() self:toggleLike(instance, context, result) end },
        { kind = "share", label = _("Share"),
          callback = function() self:shareCurrent(instance, context) end },
        { kind = "hash", label = _("Topics"),
          callback = function() self:promptSearch(instance, context) end },
        { kind = "next", label = _("Next"),
          callback = function() self:_playNext(instance, context) end },
    }
    local function button(action)
        return ActionButton:new{
            kind = action.kind, label = action.label, active = action.active or false,
            width = action_w, size = action_size, callback = action.callback,
        }
    end
    if side then
        local total = #actions * action_h + (#actions - 1) * action_gap
        local ax = video_left + video_w + margin
        local ay = math.max(band_top + margin, band_top + band_h - total - margin)
        for index, action in ipairs(actions) do
            put(button(action), ax, ay + (index - 1) * (action_h + action_gap))
        end
    else
        local cell = math.floor((width - margin * 2) / #actions)
        local ay = height - action_h - scale(8)
        for index, action in ipairs(actions) do
            put(button(action), margin + (index - 1) * cell + math.floor((cell - action_w) / 2), ay)
        end
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
