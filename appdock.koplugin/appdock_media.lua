--[[--
AppDock media session: one "now playing" entry shared between DApps and the
Android-style media notification.

A DApp that plays audio in the background registers a session with `Media.set`.
The quick settings shade renders it as an ongoing media card and the heads-up
toast announces track changes. The session only holds callbacks, so playback
state always stays owned by the DApp.

Session fields:
  owner      unique table identifying the session owner
  app        display name of the app, e.g. "YouTube Music"
  icon       DApp logo kind, e.g. "youtube_music"
  title      function() -> string
  artist     function() -> string
  playing    function() -> boolean
  position   function() -> seconds
  duration   function() -> seconds
  actions    { toggle, next, prev, stop, seek_to(ratio) }
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local Widget = require("ui/widget/widget")

local Media = { session = nil }

local function call(fn, default)
    if type(fn) ~= "function" then return default end
    local ok, value = pcall(fn)
    if ok and value ~= nil then return value end
    return default
end

function Media.set(session)
    if type(session) ~= "table" then return false end
    Media.session = session
    return true
end

function Media.clear(owner)
    if owner ~= nil and Media.session and Media.session.owner ~= owner then return false end
    Media.session = nil
    return true
end

function Media.isActive()
    return Media.session ~= nil
end

-- Plain-value copy of the session, safe to render from.
function Media.snapshot()
    local session = Media.session
    if not session then return nil end
    local duration = tonumber(call(session.duration, 0)) or 0
    local position = tonumber(call(session.position, 0)) or 0
    if duration > 0 then position = math.max(0, math.min(duration, position)) end
    return {
        app = tostring(session.app or "AppDock"),
        icon = session.icon,
        title = tostring(call(session.title, "")),
        artist = tostring(call(session.artist, "")),
        playing = call(session.playing, false) == true,
        position = position,
        duration = duration,
        ratio = duration > 0 and (position / duration) or 0,
    }
end

-- Runs one of the session actions. Returns true when the action existed.
function Media.invoke(action, argument)
    local session = Media.session
    local fn = session and session.actions and session.actions[action]
    if type(fn) ~= "function" then return false end
    local ok = pcall(fn, argument)
    return ok
end

-- Stops whatever is playing; used when AppDock itself shuts down.
function Media.stop()
    if Media.session then Media.invoke("stop") end
    Media.session = nil
end

function Media.formatTime(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

----------------------------------------------------------------
-- Glyphs: drawn with solid rectangles so they stay crisp on E-Ink
-- and never depend on font coverage for symbols like ⏭.
----------------------------------------------------------------

local Glyph = Widget:extend{
    kind = "play",
    size = 24,
    color = nil,
}

function Glyph:init()
    self.dimen = Geom:new{ w = self.size, h = self.size }
end

function Glyph:getSize()
    return self.dimen
end

local function triangle(bb, left, top, width, height, color, pointing_right)
    for row = 0, height - 1 do
        local distance = math.abs(row - (height - 1) / 2) / (height / 2)
        local row_width = math.max(1, math.floor(width * (1 - distance)))
        local x = pointing_right and left or (left + width - row_width)
        bb:paintRect(x, top + row, row_width, 1, color)
    end
end

function Glyph:paintTo(bb, x, y)
    local s = self.size
    local color = self.color or Blitbuffer.COLOR_BLACK
    local kind = self.kind
    if kind == "pause" then
        local bar_w = math.max(2, math.floor(s * .2))
        local bar_h = math.floor(s * .62)
        local top = y + math.floor((s - bar_h) / 2)
        bb:paintRect(x + math.floor(s * .24), top, bar_w, bar_h, color)
        bb:paintRect(x + s - math.floor(s * .24) - bar_w, top, bar_w, bar_h, color)
    elseif kind == "play" then
        local height = math.floor(s * .62)
        triangle(bb, x + math.floor(s * .3), y + math.floor((s - height) / 2), math.floor(s * .46), height, color, true)
    elseif kind == "next" or kind == "prev" then
        local height = math.floor(s * .56)
        local top = y + math.floor((s - height) / 2)
        local bar_w = math.max(2, math.floor(s * .1))
        local tri_w = math.floor(s * .38)
        if kind == "next" then
            triangle(bb, x + math.floor(s * .22), top, tri_w, height, color, true)
            bb:paintRect(x + s - math.floor(s * .22) - bar_w, top, bar_w, height, color)
        else
            bb:paintRect(x + math.floor(s * .22), top, bar_w, height, color)
            triangle(bb, x + s - math.floor(s * .22) - tri_w, top, tri_w, height, color, false)
        end
    elseif kind == "close" then
        local span = math.floor(s * .46)
        local left = x + math.floor((s - span) / 2)
        local top = y + math.floor((s - span) / 2)
        local thickness = math.max(2, math.floor(s * .09))
        for step = 0, span - 1 do
            bb:paintRect(left + step, top + step, thickness, thickness, color)
            bb:paintRect(left + span - 1 - step, top + step, thickness, thickness, color)
        end
    end
end

Media.Glyph = Glyph

return Media
