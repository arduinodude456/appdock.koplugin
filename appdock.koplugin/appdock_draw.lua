--[[--
AppDock Draw: a layered VECTOR canvas for E-Ink and color readers.

Everything you draw is stored as vector objects (freehand paths, lines,
rectangles, circles) with their own brush, width and color. That makes
editing possible that a pixel canvas cannot offer:

* lasso selection, move, scale, rotate, duplicate, delete, recolor,
* zoom (pinch/spread or buttons) and pan (hand tool),
* object eraser (removes whole strokes), fill of closed shapes,
* several brushes (fountain pen, fineliner, pencil, calligraphy, brush, marker).

Color rule for E-Ink: while drawing, only the 8 "fast" colors
#ffffff #000000 #ff0000 #00ff00 #0000ff #ff00ff #ffff00 #00ffff are ever
written to the framebuffer for a fast refresh. Every other color is ordered-
dithered (Bayer 8x8) from those eight. The true color is rendered only on a
full refresh (Refresh button, or the optional automatic refresh after a pause).

Project files stay a compact binary format (ADRAW3); no executable Lua is loaded.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local ffi = require("ffi")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local Widget = require("ui/widget/widget")
local AppDockDialogs = require("appdock_dialogs")
local AppDockKeyboard = require("appdock_keyboard")
local Stylus = require("appdock_stylus")
local _ = require("gettext")

local Draw = {}
Draw.__index = Draw
local Screen = Device.screen
local MAGIC = "ADRAW3\0"
local save_sequence = 0
local MAX_HISTORY = 40
local MAX_LAYERS = 6
local MAX_DOC = 4096
local MAX_SIZE = 40
local MAX_POINTS = 60000

local floor, ceil, max, min, sqrt = math.floor, math.ceil, math.max, math.min, math.sqrt
local huge = math.huge
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

-- The eight colors that may be drawn with a fast refresh.
local palette = {
    {255,255,255}, {0,0,0}, {255,0,0}, {0,255,0}, {0,0,255},
    {255,0,255}, {255,255,0}, {0,255,255},
}
Draw.palette = palette
local COLOR_NAMES = {
    _("White"), _("Black"), _("Red"), _("Green"), _("Blue"),
    _("Magenta"), _("Yellow"), _("Cyan"),
}
-- Extra colors offered in the style dialog; they are dithered while drawing.
local EXTRA_COLORS = {
    {255,128,0}, {139,69,19}, {255,192,203}, {128,0,128},
    {0,128,128}, {0,0,128}, {128,128,0}, {128,0,0},
    {0,128,0}, {255,215,0}, {192,192,192}, {128,128,128},
    {64,64,64}, {135,206,235}, {255,160,122}, {210,180,140},
}
local TOOL_LABELS = {
    pen = _("Pen"), eraser = _("Eraser"), lasso = _("Lasso"), line = _("Line"),
    rect = _("Rectangle"), circle = _("Circle"), fill = _("Fill"), hand = _("Hand"),
}
Draw.brushSizes = { 1, 2, 3, 5, 8, 12, 18, 28 }

local KIND_ID = { path = 1, line = 2, rect = 3, circle = 4 }
local KIND_NAME = { "path", "line", "rect", "circle" }

local function clamp(v, lo, hi) return max(lo, min(hi, v)) end
local function hypot(a, b) return sqrt(a * a + b * b) end
local function scale(v) return Screen:scaleBySize(v) end
local function copyColor(c) return { c[1], c[2], c[3] } end
local function sameColor(a, b)
    return a and b and a[1] == b[1] and a[2] == b[2] and a[3] == b[3] or false
end
local function hasColorScreen()
    if type(Screen.isColorScreen) == "function" then
        local ok, enabled = pcall(Screen.isColorScreen, Screen)
        if ok and enabled == true then return true end
    end
    if type(Screen.isColorEnabled) == "function" then
        local ok, enabled = pcall(Screen.isColorEnabled, Screen)
        if ok and enabled == true then return true end
    end
    return false
end
local function safeScale(value)
    local ok, scaled = pcall(scale, value)
    scaled = ok and tonumber(scaled) or nil
    if not scaled or scaled ~= scaled or scaled == huge or scaled == -huge or scaled <= 0 then
        return max(1, floor(tonumber(value) or 1))
    end
    return max(1, floor(scaled + .5))
end
local function safeDimension(value, fallback, maximum)
    value = tonumber(value)
    if not value or value ~= value or value == huge or value == -huge or value < 1 then value = fallback end
    return clamp(floor(value), 1, maximum or 4096)
end
local function screenMetric(method, field, fallback)
    local value
    if type(Screen[method]) == "function" then
        local ok, result = pcall(Screen[method], Screen)
        if ok then value = result end
    end
    return safeDimension(value or Screen[field], fallback)
end

-- Sub-second monotonic clock for refresh throttling.
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
        local ok_socket, socket = pcall(require, "socket")
        if ok_socket and socket and socket.gettime then now_seconds = socket.gettime end
    end
    now_seconds = now_seconds or function() return os.time() end
end
local function monotonicNow()
    local ok, value = pcall(now_seconds)
    return ok and tonumber(value) or os.time()
end

----------------------------------------------------------------
-- Ordered dithering (Bayer 8x8) onto the 8 fast colors
----------------------------------------------------------------

local BAYER_T = {}
do
    local m, n = { { 0, 2 }, { 3, 1 } }, 2
    local q = { { 0, 2 }, { 3, 1 } }
    while n < 8 do
        local nn, r = n * 2, {}
        for y = 0, nn - 1 do
            r[y + 1] = {}
            for x = 0, nn - 1 do
                r[y + 1][x + 1] = m[(y % n) + 1][(x % n) + 1] * 4 + q[floor(y / n) + 1][floor(x / n) + 1]
            end
        end
        m, n = r, nn
    end
    for y = 0, 7 do
        for x = 0, 7 do BAYER_T[y * 8 + x + 1] = m[y + 1][x + 1] * 4 + 2 end
    end
end

-- Public deterministic threshold: a channel value becomes 0 or 255.
function Draw.ditherChannel(value, x, y)
    return value > BAYER_T[(y % 8) * 8 + (x % 8) + 1] and 255 or 0
end

-- Maps any RGB color to one of the 8 fast colors at a screen position.
function Draw.fastColorAt(r, g, b, x, y)
    local t = BAYER_T[(y % 8) * 8 + (x % 8) + 1]
    return r > t and 255 or 0, g > t and 255 or 0, b > t and 255 or 0
end

function Draw.parseRGB(text)
    if type(text) ~= "string" then return nil end
    text = text:match("^%s*(.-)%s*$") or ""
    local hex = text:match("^#?(%x%x%x%x%x%x)$")
    if hex then
        return tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
    end
    local r, g, b = text:match("^(%d+)%s*[,;]%s*(%d+)%s*[,;]%s*(%d+)$")
    r, g, b = tonumber(r), tonumber(g), tonumber(b)
    if not r or not g or not b or r > 255 or g > 255 or b > 255 then return nil end
    return r, g, b
end

----------------------------------------------------------------
-- Brushes
----------------------------------------------------------------

local BRUSH_ORDER = { "pen", "fineliner", "pencil", "calligraphy", "brush", "marker" }
local BRUSH_INDEX = {}
for index, name in ipairs(BRUSH_ORDER) do BRUSH_INDEX[name] = index end
-- scale: width relative to the chosen size; pressure/min: width follows pen
-- pressure down to `min`; pattern: solid, half (50 % stipple), grain (~67 %).
local BRUSH = {
    pen         = { label = _("Fountain pen"), pressure = true,  min = 0.30, scale = 1.0, pattern = "solid", shape = "round" },
    fineliner   = { label = _("Fineliner"),    pressure = false, min = 1,    scale = 0.7, pattern = "solid", shape = "round" },
    pencil      = { label = _("Pencil"),       pressure = true,  min = 0.50, scale = 0.9, pattern = "grain", shape = "round" },
    calligraphy = { label = _("Calligraphy"),  pressure = false, min = 1,    scale = 1.6, pattern = "solid", shape = "nib" },
    brush       = { label = _("Brush"),        pressure = true,  min = 0.08, scale = 2.0, pattern = "solid", shape = "round" },
    marker      = { label = _("Marker"),       pressure = false, min = 1,    scale = 3.5, pattern = "half",  shape = "square" },
}
Draw.brushes = BRUSH
Draw.brushOrder = BRUSH_ORDER

local function strokeWidth(prof, size, p)
    local w = size * prof.scale
    if prof.pressure then w = w * (prof.min + (1 - prof.min) * (p or 1)) end
    return w
end

----------------------------------------------------------------
-- Vector objects
----------------------------------------------------------------

local function newObject(kind, brush, size, color)
    return { kind = kind, brush = brush, size = size, color = color, x = {}, y = {}, p = {}, n = 0 }
end
local function addPoint(o, x, y, p)
    local n = o.n + 1
    o.n = n
    o.x[n], o.y[n], o.p[n] = x, y, p or 1
    o.bb = nil
end
-- Shares the (immutable once committed) point arrays.
local function copyObject(o)
    return { kind = o.kind, brush = o.brush, size = o.size, color = o.color, fill = o.fill,
        x = o.x, y = o.y, p = o.p, n = o.n, bb = o.bb }
end
local function objectBBox(o)
    local bb = o.bb
    if bb then return bb end
    local x0, y0, x1, y1 = huge, huge, -huge, -huge
    if o.kind == "circle" and o.n >= 2 then
        local r = hypot(o.x[2] - o.x[1], o.y[2] - o.y[1])
        x0, y0, x1, y1 = o.x[1] - r, o.y[1] - r, o.x[1] + r, o.y[1] + r
    else
        for i = 1, o.n do
            if o.x[i] < x0 then x0 = o.x[i] end
            if o.x[i] > x1 then x1 = o.x[i] end
            if o.y[i] < y0 then y0 = o.y[i] end
            if o.y[i] > y1 then y1 = o.y[i] end
        end
    end
    local prof = BRUSH[o.brush] or BRUSH.pen
    local pad = o.size * prof.scale * 0.75 + 2
    bb = { x0 - pad, y0 - pad, x1 + pad, y1 + pad }
    o.bb = bb
    return bb
end
local function unionBox(a, b)
    if not a then return b and { b[1], b[2], b[3], b[4] } end
    if not b then return a end
    return { min(a[1], b[1]), min(a[2], b[2]), max(a[3], b[3]), max(a[4], b[4]) }
end

local function distPointSeg(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local l2 = dx * dx + dy * dy
    local t = 0
    if l2 > 0 then t = clamp(((px - ax) * dx + (py - ay) * dy) / l2, 0, 1) end
    return hypot(px - (ax + t * dx), py - (ay + t * dy))
end
local function pointInPoly(x, y, xs, ys, n)
    local inside = false
    local j = n
    for i = 1, n do
        local yi, yj = ys[i], ys[j]
        if (yi > y) ~= (yj > y) then
            local cross = xs[i] + (y - yi) * (xs[j] - xs[i]) / (yj - yi)
            if x < cross then inside = not inside end
        end
        j = i
    end
    return inside
end
local function isClosedPath(o)
    if o.kind ~= "path" or o.n < 4 then return false end
    return hypot(o.x[1] - o.x[o.n], o.y[1] - o.y[o.n]) <= max(10, o.size * 3)
end
local function isClosedShape(o)
    return o.kind == "rect" or o.kind == "circle" or isClosedPath(o)
end
local function insideObject(o, x, y)
    if o.kind == "rect" then
        return x >= min(o.x[1], o.x[2]) and x <= max(o.x[1], o.x[2])
            and y >= min(o.y[1], o.y[2]) and y <= max(o.y[1], o.y[2])
    elseif o.kind == "circle" then
        return hypot(x - o.x[1], y - o.y[1]) <= hypot(o.x[2] - o.x[1], o.y[2] - o.y[1])
    elseif o.kind == "path" then
        return pointInPoly(x, y, o.x, o.y, o.n)
    end
    return false
end
-- Distance from a point to the object's outline (0 inside a filled shape).
local function distToObject(o, x, y)
    local kind, xs, ys = o.kind, o.x, o.y
    if o.fill and insideObject(o, x, y) then return 0 end
    if kind == "circle" then
        return math.abs(hypot(x - xs[1], y - ys[1]) - hypot(xs[2] - xs[1], ys[2] - ys[1]))
    elseif kind == "rect" then
        local x0, x1 = min(xs[1], xs[2]), max(xs[1], xs[2])
        local y0, y1 = min(ys[1], ys[2]), max(ys[1], ys[2])
        return min(distPointSeg(x, y, x0, y0, x1, y0), distPointSeg(x, y, x1, y0, x1, y1),
            distPointSeg(x, y, x1, y1, x0, y1), distPointSeg(x, y, x0, y1, x0, y0))
    elseif o.n == 1 then
        return hypot(x - xs[1], y - ys[1])
    end
    local best = huge
    for i = 2, o.n do
        local d = distPointSeg(x, y, xs[i - 1], ys[i - 1], xs[i], ys[i])
        if d < best then best = d end
    end
    return best
end

local function transformObject(o, t, cx, cy)
    local cosr, sinr = math.cos(t.rot), math.sin(t.rot)
    local function tp(x, y)
        local vx, vy = (x - cx) * t.s, (y - cy) * t.s
        return cx + vx * cosr - vy * sinr + t.dx, cy + vx * sinr + vy * cosr + t.dy
    end
    local new = newObject(o.kind, o.brush, clamp(o.size * t.s, 0.5, 200), o.color)
    new.fill = o.fill
    if o.kind == "rect" and math.abs(t.rot) > 1e-6 then
        -- A rotated rectangle is no longer axis aligned: becomes a closed path.
        new.kind = "path"
        local x0, y0, x1, y1 = o.x[1], o.y[1], o.x[2], o.y[2]
        local corners = { { x0, y0 }, { x1, y0 }, { x1, y1 }, { x0, y1 }, { x0, y0 } }
        for _index, c in ipairs(corners) do
            local tx, ty = tp(c[1], c[2])
            addPoint(new, tx, ty, 1)
        end
    else
        for i = 1, o.n do
            local tx, ty = tp(o.x[i], o.y[i])
            addPoint(new, tx, ty, o.p[i])
        end
    end
    return new
end

----------------------------------------------------------------
-- Painter: clipped, pattern-aware, dithering span writer
----------------------------------------------------------------

local Painter = {}
Painter.__index = Painter

local function newPainter(draw, clip, mode, color_mode)
    return setmetatable({
        draw = draw, cx0 = clip[1], cy0 = clip[2], cx1 = clip[3], cy1 = clip[4],
        mode = mode, color_mode = color_mode, r = 0, g = 0, b = 0, exact = true, pattern = "solid",
    }, Painter)
end

function Painter:setColor(c)
    local r, g, b = c[1], c[2], c[3]
    self.r, self.g, self.b = r, g, b
    if self.mode == "true" then
        self.exact = true
    elseif self.color_mode then
        self.exact = (r == 0 or r == 255) and (g == 0 or g == 255) and (b == 0 or b == 255)
    else
        self.exact = (r == g and g == b and (r == 0 or r == 255))
    end
end
function Painter:setPattern(pattern) self.pattern = pattern or "solid" end

local function patternAllows(pattern, px, py)
    if pattern == "solid" then return true end
    if pattern == "half" then return (px + py) % 2 == 0 end
    return (px * 37 + py * 91 + px * py) % 3 ~= 0
end

-- One horizontal run of pixels. Non-fast colors are dithered per pixel from the
-- 8 fast colors (or black/white on gray screens) unless the painter renders true colors.
function Painter:span(x, y, w)
    x, y = floor(x), floor(y)
    local x1 = x + floor(w) - 1
    if y < self.cy0 or y > self.cy1 then return end
    if x < self.cx0 then x = self.cx0 end
    if x1 > self.cx1 then x1 = self.cx1 end
    if x1 < x then return end
    local pattern, exact = self.pattern, self.exact
    local draw, r, g, b = self.draw, self.r, self.g, self.b
    if pattern == "solid" and exact then
        draw(x, y, x1 - x + 1, 1, r, g, b)
        return
    end
    local color_mode = self.color_mode
    local lum = (r * 299 + g * 587 + b * 114) / 1000
    local row = (y % 8) * 8
    local run_start, run_key
    for px = x, x1 + 1 do
        local key
        if px <= x1 and patternAllows(pattern, px, y) then
            if exact then
                key = 1
            else
                local t = BAYER_T[row + (px % 8) + 1]
                if color_mode then
                    key = 2 + (r > t and 4 or 0) + (g > t and 2 or 0) + (b > t and 1 or 0)
                else
                    key = lum > t and 9 or 2
                end
            end
        end
        if key ~= run_key then
            if run_key then
                local len = px - run_start
                if run_key == 1 then
                    draw(run_start, y, len, 1, r, g, b)
                else
                    local code = run_key - 2
                    draw(run_start, y, len, 1,
                        code >= 4 and 255 or 0, (code % 4) >= 2 and 255 or 0, (code % 2) == 1 and 255 or 0)
                end
            end
            run_start, run_key = px, key
        end
    end
end

function Painter:rect(x, y, w, h)
    x, y = floor(x), floor(y)
    local x1, y1 = x + floor(w) - 1, y + floor(h) - 1
    x, y = max(x, self.cx0), max(y, self.cy0)
    x1, y1 = min(x1, self.cx1), min(y1, self.cy1)
    if x1 < x or y1 < y then return end
    if self.pattern == "solid" and self.exact then
        self.draw(x, y, x1 - x + 1, y1 - y + 1, self.r, self.g, self.b)
        return
    end
    for yy = y, y1 do self:span(x, yy, x1 - x + 1) end
end

function Painter:disc(cx, cy, d)
    local r = d * 0.5
    if r < 0.75 then return self:span(floor(cx), floor(cy), 1) end
    local ya = max(self.cy0, ceil(cy - r - 0.5))
    local yb = min(self.cy1, floor(cy + r - 0.5))
    local r2 = r * r
    for y = ya, yb do
        local dy = y + 0.5 - cy
        local half = sqrt(max(0, r2 - dy * dy))
        local xa, xb = ceil(cx - half - 0.5), floor(cx + half - 0.5)
        if xb < xa then xb = xa end
        self:span(xa, y, xb - xa + 1)
    end
end

function Painter:square(cx, cy, d)
    local w = max(1, floor(d + 0.5))
    local x0, y0 = floor(cx - d / 2 + 0.5), floor(cy - d / 2 + 0.5)
    for y = max(self.cy0, y0), min(self.cy1, y0 + w - 1) do self:span(x0, y, w) end
end

-- Flat calligraphy nib held at 45 degrees.
function Painter:nib(cx, cy, d)
    local len = max(1, d)
    local thick = max(1, floor(d * 0.18 + 0.5))
    local k = len * 0.5 * 0.7071
    local steps = max(1, floor(len * 0.7071))
    for i = 0, steps do
        local t = i / steps * 2 - 1
        self:span(floor(cx + t * k - thick * 0.5 + 0.5), floor(cy - t * k + 0.5), thick)
    end
end

function Painter:stamp(prof, cx, cy, d)
    local shape = prof.shape
    if shape == "nib" then self:nib(cx, cy, d)
    elseif shape == "square" then self:square(cx, cy, d)
    else self:disc(cx, cy, d) end
end

-- Stamps along a segment; the start point is expected to be stamped already.
function Painter:segment(prof, x0, y0, d0, x1, y1, d1)
    local dx, dy = x1 - x0, y1 - y0
    local dist = hypot(dx, dy)
    local step = max(1, max(d0, d1) / 4)
    local n = max(1, ceil(dist / step))
    for i = 1, n do
        local t = i / n
        self:stamp(prof, x0 + dx * t, y0 + dy * t, d0 + (d1 - d0) * t)
    end
end

-- 1 px line; `dash` > 0 gives dashes of that length.
function Painter:line(x0, y0, x1, y1, dash)
    local dx, dy = x1 - x0, y1 - y0
    local n = max(floor(math.abs(dx)), floor(math.abs(dy)), 1)
    for i = 0, n do
        if not dash or dash <= 0 or (i % (dash * 2)) < dash then
            self:span(floor(x0 + dx * i / n + 0.5), floor(y0 + dy * i / n + 0.5), 1)
        end
    end
end

local function fillPolygon(P, xs, ys, n)
    local miny, maxy = huge, -huge
    for i = 1, n do
        if ys[i] < miny then miny = ys[i] end
        if ys[i] > maxy then maxy = ys[i] end
    end
    for y = max(P.cy0, floor(miny)), min(P.cy1, ceil(maxy)) do
        local yc = y + 0.5
        local hits, k = {}, 0
        local j = n
        for i = 1, n do
            local yi, yj = ys[i], ys[j]
            if (yi <= yc and yj > yc) or (yj <= yc and yi > yc) then
                k = k + 1
                hits[k] = xs[i] + (yc - yi) * (xs[j] - xs[i]) / (yj - yi)
            end
            j = i
        end
        table.sort(hits)
        for a = 1, k - 1, 2 do
            local xa, xb = ceil(hits[a] - 0.5), floor(hits[a + 1] - 0.5)
            if xb >= xa then P:span(xa, y, xb - xa + 1) end
        end
    end
end

----------------------------------------------------------------
-- Painter backends
----------------------------------------------------------------

local blit_cache = { [true] = {}, [false] = {} }
local function blitColor(r, g, b, color_mode)
    r, g, b = floor(r), floor(g), floor(b)
    local key = r * 65536 + g * 256 + b
    local cache = blit_cache[color_mode and true or false]
    local color = cache[key]
    if not color then
        if color_mode then
            color = Blitbuffer.colorFromString(string.format("#%02x%02x%02x", r, g, b))
        else
            local lum = floor((r * 299 + g * 587 + b * 114) / 1000)
            local ok, gray = pcall(Blitbuffer.Color8, lum)
            color = ok and gray or (lum > 127 and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK)
        end
        cache[key] = color
    end
    return color
end
local function paintColorRect(bb, x, y, w, h, color, color_mode)
    -- KOReader's color E-Ink buffers need the RGB-specific API.
    if color_mode and type(bb.paintRectRGB32) == "function" then
        bb:paintRectRGB32(x, y, w, h, color)
    else
        bb:paintRect(x, y, w, h, color)
    end
end
local function screenPainter(bb, clip, mode)
    local color_mode = hasColorScreen()
    local function draw(x, y, w, h, r, g, b)
        paintColorRect(bb, x, y, w, h, blitColor(r, g, b, color_mode), color_mode)
    end
    return newPainter(draw, clip, mode, color_mode)
end
local function memoryPainter(buf, w, h)
    local function draw(x, y, ww, hh, r, g, b)
        for yy = y, y + hh - 1 do
            local base = (yy * w + x) * 3
            for k = 0, ww - 1 do
                local i = base + k * 3
                buf[i], buf[i + 1], buf[i + 2] = r, g, b
            end
        end
    end
    return newPainter(draw, { 0, 0, w - 1, h - 1 }, "true", true)
end
-- Chrome painted with a fast refresh uses the same 8-color dithering as the canvas.
local function paintDitheredRect(bb, x, y, w, h, c)
    local P = screenPainter(bb, { x, y, x + w - 1, y + h - 1 }, "fast")
    P:setColor(c)
    P:setPattern("solid")
    P:rect(x, y, w, h)
end

----------------------------------------------------------------
-- Vector rendering
----------------------------------------------------------------

local function drawObject(P, o, v)
    local s = v.s
    local bb = objectBBox(o)
    local ox, oy = v.ox, v.oy
    if ox + bb[3] * s < P.cx0 or ox + bb[1] * s > P.cx1 or oy + bb[4] * s < P.cy0 or oy + bb[2] * s > P.cy1 then
        return
    end
    local prof = BRUSH[o.brush] or BRUSH.pen
    local xs, ys, ps, kind = o.x, o.y, o.p, o.kind
    if o.fill then
        P:setColor(o.fill)
        P:setPattern("solid")
        if kind == "rect" then
            local x0, x1 = ox + min(xs[1], xs[2]) * s, ox + max(xs[1], xs[2]) * s
            local y0, y1 = oy + min(ys[1], ys[2]) * s, oy + max(ys[1], ys[2]) * s
            P:rect(floor(x0 + 0.5), floor(y0 + 0.5), floor(x1 - x0 + 0.5) + 1, floor(y1 - y0 + 0.5) + 1)
        elseif kind == "circle" then
            P:disc(ox + xs[1] * s, oy + ys[1] * s, hypot(xs[2] - xs[1], ys[2] - ys[1]) * s * 2)
        elseif kind == "path" and o.n >= 3 then
            local sxs, sys = {}, {}
            for i = 1, o.n do sxs[i], sys[i] = ox + xs[i] * s, oy + ys[i] * s end
            fillPolygon(P, sxs, sys, o.n)
        end
    end
    if o.size <= 0 then return end
    P:setColor(o.color)
    P:setPattern(prof.pattern)
    local function dia(i) return max(1, strokeWidth(prof, o.size, ps[i]) * s) end
    if kind == "path" then
        local px, py, pd = ox + xs[1] * s, oy + ys[1] * s, dia(1)
        P:stamp(prof, px, py, pd)
        for i = 2, o.n do
            local cx, cy, cd = ox + xs[i] * s, oy + ys[i] * s, dia(i)
            P:segment(prof, px, py, pd, cx, cy, cd)
            px, py, pd = cx, cy, cd
        end
    elseif kind == "line" then
        local d = dia(1)
        local x0, y0, x1, y1 = ox + xs[1] * s, oy + ys[1] * s, ox + xs[2] * s, oy + ys[2] * s
        P:stamp(prof, x0, y0, d)
        P:segment(prof, x0, y0, d, x1, y1, d)
    elseif kind == "rect" then
        local d = dia(1)
        local x0, y0, x1, y1 = ox + xs[1] * s, oy + ys[1] * s, ox + xs[2] * s, oy + ys[2] * s
        local cx = { x0, x1, x1, x0, x0 }
        local cy = { y0, y0, y1, y1, y0 }
        P:stamp(prof, cx[1], cy[1], d)
        for i = 2, 5 do P:segment(prof, cx[i - 1], cy[i - 1], d, cx[i], cy[i], d) end
    elseif kind == "circle" then
        local d = dia(1)
        local cx, cy = ox + xs[1] * s, oy + ys[1] * s
        local r = hypot(xs[2] - xs[1], ys[2] - ys[1]) * s
        local segs = clamp(ceil(r * 0.8), 24, 360)
        local px, py = cx + r, cy
        P:stamp(prof, px, py, d)
        for i = 1, segs do
            local a = 2 * math.pi * i / segs
            local nx, ny = cx + math.cos(a) * r, cy + math.sin(a) * r
            P:segment(prof, px, py, d, nx, ny, d)
            px, py = nx, ny
        end
    end
end

-- Rounded boxes (fall back to square ones when the blitbuffer lacks rounded painting).
local function fillRound(bb, x, y, w, h, color, radius)
    if w < 1 or h < 1 then return end
    radius = min(floor(radius or 0), floor(min(w, h) / 2))
    if radius >= 2 and bb.paintRoundedRect then
        local ok = pcall(bb.paintRoundedRect, bb, x, y, w, h, color, radius)
        if ok then return end
    end
    bb:paintRect(x, y, w, h, color)
end
local function roundBox(bb, x, y, w, h, radius, fill, outline, border)
    border = border or max(1, safeScale(1))
    if outline then
        fillRound(bb, x, y, w, h, outline, radius)
        fillRound(bb, x + border, y + border, w - border * 2, h - border * 2, fill, max(0, radius - border))
    else
        fillRound(bb, x, y, w, h, fill, radius)
    end
end

-- Page backgrounds (stored in the flags of layer 1, so older readers still open the file).
local PAPERS = { "blank", "lines", "wide", "grid", "small", "dots", "margin" }
local PAPER_INDEX = {}
for index, name in ipairs(PAPERS) do PAPER_INDEX[name] = index - 1 end
local PAPER_LABELS = {
    blank = _("Blank"), lines = _("Ruled"), wide = _("Wide ruled"), grid = _("Grid"),
    small = _("Small grid"), dots = _("Dotted"), margin = _("Ruled + margin"),
}
local PAPER_INK = { 170, 170, 170 }

local function drawPaper(P, doc_w, doc_h, v, kind)
    if not kind or kind == "blank" then return end
    local cx0, cy0, cx1, cy1 = P.cx0, P.cy0, P.cx1, P.cy1
    if cx1 < cx0 or cy1 < cy0 then return end
    local s = v.s
    local th = max(1, floor(s + 0.5))
    P:setColor(PAPER_INK)
    P:setPattern("solid")
    local function hlines(step, top, thick)
        local k = max(0, ceil((((cy0 - v.oy) / s) - top) / step))
        while true do
            local dy = top + k * step
            if dy >= doc_h then break end
            local sy = floor(v.oy + dy * s)
            if sy > cy1 then break end
            P:rect(cx0, sy, cx1 - cx0 + 1, thick)
            k = k + 1
        end
    end
    local function vlines(step, left, thick)
        local k = max(0, ceil((((cx0 - v.ox) / s) - left) / step))
        while true do
            local dx = left + k * step
            if dx >= doc_w then break end
            local sx = floor(v.ox + dx * s)
            if sx > cx1 then break end
            P:rect(sx, cy0, thick, cy1 - cy0 + 1)
            k = k + 1
        end
    end
    if kind == "lines" then
        hlines(safeScale(40), safeScale(60), th)
    elseif kind == "wide" then
        hlines(safeScale(56), safeScale(70), th)
    elseif kind == "margin" then
        hlines(safeScale(40), safeScale(60), th)
        vlines(1e9, safeScale(70), th * 2)
    elseif kind == "grid" then
        local step = safeScale(30)
        hlines(step, step, th); vlines(step, step, th)
    elseif kind == "small" then
        local step = safeScale(15)
        hlines(step, step, th); vlines(step, step, th)
    elseif kind == "dots" then
        local step = safeScale(30)
        local d = max(2, th * 2)
        local ky = max(1, ceil(((cy0 - v.oy) / s) / step) - 1)
        while true do
            local dy = ky * step
            if dy >= doc_h then break end
            local sy = floor(v.oy + dy * s)
            if sy > cy1 then break end
            local kx = max(1, ceil(((cx0 - v.ox) / s) / step) - 1)
            while true do
                local dx = kx * step
                if dx >= doc_w then break end
                local sx = floor(v.ox + dx * s)
                if sx > cx1 then break end
                P:rect(sx - floor(d / 2), sy - floor(d / 2), d, d)
                kx = kx + 1
            end
            ky = ky + 1
        end
    end
end

local function renderDocument(app, P, v, border)
    local x0, y0 = v.ox, v.oy
    local x1, y1 = v.ox + app.width * v.s, v.oy + app.height * v.s
    local save = { P.cx0, P.cy0, P.cx1, P.cy1 }
    -- Objects never paint outside the page.
    P.cx0, P.cy0 = max(P.cx0, floor(x0)), max(P.cy0, floor(y0))
    P.cx1, P.cy1 = min(P.cx1, ceil(x1) - 1), min(P.cy1, ceil(y1) - 1)
    if P.cx1 >= P.cx0 and P.cy1 >= P.cy0 then
        local sel, st = app.sel, app.stroke
        for li, layer in ipairs(app.layers) do
            if not layer.hidden then
                if layer.bg then
                    P:setColor(layer.bg)
                    P:setPattern("solid")
                    P:rect(floor(x0), floor(y0), ceil(x1) - floor(x0), ceil(y1) - floor(y0))
                    if layer.paper then drawPaper(P, app.width, app.height, v, layer.paper) end
                end
                local preview = sel and sel.preview and li == sel.layer and sel.preview or nil
                for _index, o in ipairs(layer.objects) do
                    drawObject(P, preview and preview[o] or o, v)
                end
                if st and st.obj and st.layer == li then drawObject(P, st.obj, v) end
            end
        end
    end
    P.cx0, P.cy0, P.cx1, P.cy1 = save[1], save[2], save[3], save[4]
    if border then
        P:setColor({ 0, 0, 0 })
        P:setPattern("solid")
        local bx0, by0 = floor(x0) - 1, floor(y0) - 1
        local bw, bh = ceil(x1) - floor(x0) + 2, ceil(y1) - floor(y0) + 2
        P:rect(bx0, by0, bw, 1)
        P:rect(bx0, by0 + bh - 1, bw, 1)
        P:rect(bx0, by0, 1, bh)
        P:rect(bx0 + bw - 1, by0, 1, bh)
    end
end

-- Selection frame, handles and the lasso path while it is being drawn.
local function selHandles(box, v)
    local x0, y0 = v.ox + box[1] * v.s, v.oy + box[2] * v.s
    local x1, y1 = v.ox + box[3] * v.s, v.oy + box[4] * v.s
    local corners = { { x0, y0 }, { x1, y0 }, { x1, y1 }, { x0, y1 } }
    local rotate = { (x0 + x1) / 2, y0 - safeScale(30) }
    -- Near the top edge of the page the rotate handle would be unreachable: put it below.
    if rotate[2] < max(v.oy, 0) + safeScale(8) then rotate[2] = y1 + safeScale(30) end
    return corners, rotate, x0, y0, x1, y1
end

local function drawOverlays(canvas, P, v)
    local app = canvas.app
    local sel = app.sel
    if sel then
        local box = sel.pbbox or sel.bbox
        local corners, rot, x0, y0, x1, y1 = selHandles(box, v)
        P:setColor({ 0, 0, 0 })
        P:setPattern("solid")
        P:line(x0, y0, x1, y0, 4); P:line(x1, y0, x1, y1, 4)
        P:line(x1, y1, x0, y1, 4); P:line(x0, y1, x0, y0, 4)
        P:line((x0 + x1) / 2, rot[2] > y1 and y1 or y0, rot[1], rot[2], 0)
        local hs = safeScale(18)
        for _index, c in ipairs(corners) do
            local hx, hy = floor(c[1] - hs / 2), floor(c[2] - hs / 2)
            P:setColor({ 255, 255, 255 }); P:rect(hx, hy, hs, hs)
            P:setColor({ 0, 0, 0 })
            P:rect(hx, hy, hs, 2); P:rect(hx, hy + hs - 2, hs, 2)
            P:rect(hx, hy, 2, hs); P:rect(hx + hs - 2, hy, 2, hs)
        end
        P:setColor({ 0, 0, 0 })
        P:disc(rot[1], rot[2], hs + safeScale(2))
        P:setColor({ 255, 255, 255 })
        P:disc(rot[1], rot[2], max(2, hs - safeScale(4)))
        P:setColor({ 0, 0, 0 })
        P:disc(rot[1], rot[2], max(1, floor(hs / 4)))
    end
    local st = app.stroke
    if st and st.tool == "lasso" and st.px then
        P:setColor({ 0, 0, 0 })
        P:setPattern("solid")
        for i = 2, #st.px do P:line(st.px[i - 1], st.py[i - 1], st.px[i], st.py[i], 4) end
    end
end

----------------------------------------------------------------
-- Icon painting
----------------------------------------------------------------

local function paintGlyph(bb, x, y, width, height, kind, ink)
    local size = max(6, min(width, height) - safeScale(10))
    local ox = x + floor((width - size) / 2)
    local oy = y + floor((height - size) / 2)
    local stroke = max(1, floor(size * 0.11))
    local thin = max(1, floor(size * 0.07))
    local function rect(px, py, w, h)
        bb:paintRect(floor(px), floor(py), max(1, floor(w)), max(1, floor(h)), ink)
    end
    local disc
    local function line(x0, y0, x1, y1, thickness)
        thickness = thickness or stroke
        local steps = max(math.abs(x1 - x0), math.abs(y1 - y0))
        local round = thickness >= 3
        if steps < 1 then
            if round then return disc(x0, y0, floor(thickness / 2)) end
            return rect(x0 - thickness / 2, y0 - thickness / 2, thickness, thickness)
        end
        for step = 0, steps, (round and 1.5 or 1) do
            local px = x0 + (x1 - x0) * step / steps
            local py = y0 + (y1 - y0) * step / steps
            if round then disc(px, py, floor(thickness / 2))
            else rect(px - thickness / 2, py - thickness / 2, thickness, thickness) end
        end
    end
    local function hollow(px, py, w, h, thickness)
        thickness = thickness or stroke
        rect(px, py, w, thickness); rect(px, py + h - thickness, w, thickness)
        rect(px, py, thickness, h); rect(px + w - thickness, py, thickness, h)
    end
    disc = function(cx, cy, radius)
        radius = floor(radius)
        for row = -radius, radius do
            local span = floor(sqrt(max(0, radius * radius - row * row)) + .5)
            rect(cx - span, cy + row, span * 2 + 1, 1)
        end
    end
    local function ring(cx, cy, radius, thickness, dashed)
        for step = 0, 48 do
            if not dashed or (step % 4) < 2 then
                local angle = 2 * math.pi * step / 48
                rect(cx + math.cos(angle) * radius - thickness / 2,
                    cy + math.sin(angle) * radius - thickness / 2, thickness, thickness)
            end
        end
    end

    if kind == "pen" then
        line(ox + size * 0.22, oy + size * 0.78, ox + size * 0.72, oy + size * 0.28, stroke)
        line(ox + size * 0.30, oy + size * 0.86, ox + size * 0.80, oy + size * 0.36, thin)
        line(ox + size * 0.14, oy + size * 0.90, ox + size * 0.62, oy + size * 0.90, thin)
    elseif kind == "eraser" then
        line(ox + size * 0.30, oy + size * 0.24, ox + size * 0.74, oy + size * 0.68, stroke * 2)
        line(ox + size * 0.18, oy + size * 0.60, ox + size * 0.54, oy + size * 0.96, stroke)
        line(ox + size * 0.10, oy + size * 0.96, ox + size * 0.86, oy + size * 0.96, thin)
    elseif kind == "lasso" then
        ring(ox + size * 0.5, oy + size * 0.44, size * 0.34, stroke, true)
        line(ox + size * 0.56, oy + size * 0.76, ox + size * 0.72, oy + size * 0.94, thin)
    elseif kind == "hand" then
        line(ox + size * 0.50, oy + size * 0.10, ox + size * 0.50, oy + size * 0.90, stroke)
        line(ox + size * 0.10, oy + size * 0.50, ox + size * 0.90, oy + size * 0.50, stroke)
        line(ox + size * 0.50, oy + size * 0.10, ox + size * 0.38, oy + size * 0.24, thin)
        line(ox + size * 0.50, oy + size * 0.10, ox + size * 0.62, oy + size * 0.24, thin)
        line(ox + size * 0.50, oy + size * 0.90, ox + size * 0.38, oy + size * 0.76, thin)
        line(ox + size * 0.50, oy + size * 0.90, ox + size * 0.62, oy + size * 0.76, thin)
    elseif kind == "line" then
        line(ox + size * 0.18, oy + size * 0.80, ox + size * 0.82, oy + size * 0.20, stroke)
        disc(ox + size * 0.18, oy + size * 0.80, max(1, floor(thin)))
        disc(ox + size * 0.82, oy + size * 0.20, max(1, floor(thin)))
    elseif kind == "rect" then
        hollow(ox + size * 0.16, oy + size * 0.26, size * 0.68, size * 0.48, stroke)
    elseif kind == "circle" then
        ring(ox + size * 0.5, oy + size * 0.5, size * 0.32, stroke)
    elseif kind == "fill" then
        rect(ox + size * 0.30, oy + size * 0.22, size * 0.40, size * 0.06)
        for row = 0, floor(size * 0.34) do
            local inset = floor(row * 0.35)
            rect(ox + size * 0.22 + inset, oy + size * 0.30 + row, size * 0.56 - inset * 2, 1)
        end
        disc(ox + size * 0.74, oy + size * 0.80, max(1, floor(size * 0.10)))
        rect(ox + size * 0.74, oy + size * 0.62, thin, size * 0.14)
    elseif kind == "undo" or kind == "redo" then
        local direction = kind == "undo" and -1 or 1
        local cx, cy, radius = ox + size * 0.5, oy + size * 0.60, size * 0.30
        for step = 0, 24 do
            local angle = math.pi * step / 24
            rect(cx + direction * math.cos(angle) * radius - thin / 2, cy - math.sin(angle) * radius - thin / 2, thin, thin)
        end
        local tip_x = cx + direction * radius
        for row = 0, floor(size * 0.18) do rect(tip_x - thin, cy - size * 0.16 + row, thin * 2, 1) end
        rect(cx - radius, cy, radius * 2, thin)
    elseif kind == "refresh" then
        ring(ox + size * 0.5, oy + size * 0.5, size * 0.30, stroke)
        rect(ox + size * 0.50, oy + size * 0.10, size * 0.22, stroke)
        rect(ox + size * 0.62, oy + size * 0.10, stroke, size * 0.22)
    elseif kind == "save" then
        hollow(ox + size * 0.16, oy + size * 0.16, size * 0.68, size * 0.68, stroke)
        rect(ox + size * 0.32, oy + size * 0.20, size * 0.36, size * 0.24)
        rect(ox + size * 0.28, oy + size * 0.58, size * 0.44, size * 0.22)
    elseif kind == "open" then
        rect(ox + size * 0.14, oy + size * 0.34, size * 0.72, size * 0.48)
        rect(ox + size * 0.14, oy + size * 0.22, size * 0.34, size * 0.14)
        rect(ox + size * 0.14, oy + size * 0.48, size * 0.72, thin)
    elseif kind == "minus" then
        rect(ox + size * 0.26, oy + size * 0.46, size * 0.48, stroke)
    elseif kind == "plus" then
        rect(ox + size * 0.26, oy + size * 0.46, size * 0.48, stroke)
        rect(ox + size * 0.46, oy + size * 0.26, stroke, size * 0.48)
    elseif kind == "more" then
        local radius = max(1, floor(size * 0.09))
        for index = 0, 2 do disc(ox + size * (0.22 + index * 0.28), oy + size * 0.5, radius) end
    elseif kind == "layers" then
        hollow(ox + size * 0.30, oy + size * 0.12, size * 0.56, size * 0.40, thin)
        hollow(ox + size * 0.14, oy + size * 0.40, size * 0.56, size * 0.40, stroke)
    elseif kind == "style" then
        disc(ox + size * 0.5, oy + size * 0.5, max(1, floor(size * 0.30)))
    elseif kind == "finger" then
        -- Pointing finger above a small palm.
        line(ox + size * 0.42, oy + size * 0.14, ox + size * 0.42, oy + size * 0.52, stroke * 2)
        hollow(ox + size * 0.22, oy + size * 0.52, size * 0.56, size * 0.36, thin)
        line(ox + size * 0.62, oy + size * 0.40, ox + size * 0.62, oy + size * 0.54, stroke)
        line(ox + size * 0.76, oy + size * 0.46, ox + size * 0.76, oy + size * 0.56, stroke)
    elseif kind == "paper" then
        hollow(ox + size * 0.20, oy + size * 0.10, size * 0.60, size * 0.80, stroke)
        rect(ox + size * 0.30, oy + size * 0.32, size * 0.40, thin)
        rect(ox + size * 0.30, oy + size * 0.50, size * 0.40, thin)
        rect(ox + size * 0.30, oy + size * 0.68, size * 0.40, thin)
    elseif kind == "export" then
        line(ox + size * 0.50, oy + size * 0.58, ox + size * 0.50, oy + size * 0.12, stroke)
        line(ox + size * 0.50, oy + size * 0.12, ox + size * 0.34, oy + size * 0.28, stroke)
        line(ox + size * 0.50, oy + size * 0.12, ox + size * 0.66, oy + size * 0.28, stroke)
        hollow(ox + size * 0.18, oy + size * 0.52, size * 0.64, size * 0.38, thin)
    elseif kind == "check" then
        line(ox + size * 0.20, oy + size * 0.54, ox + size * 0.42, oy + size * 0.76, stroke)
        line(ox + size * 0.42, oy + size * 0.76, ox + size * 0.82, oy + size * 0.26, stroke)
    else
        hollow(ox + size * 0.16, oy + size * 0.16, size * 0.68, size * 0.68, stroke)
    end
end

----------------------------------------------------------------
-- Toolbar widgets
----------------------------------------------------------------

local ToolButton = InputContainer:extend{
    symbol = nil, label = nil, active = false, disabled = false,
    callback = nil, width = nil, height = nil, dimen = nil,
}

function ToolButton:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    if self.label and self.width >= safeScale(38) and self.height >= safeScale(28) then
        self.label_widget = TextWidget:new{
            text = self.label,
            face = Font:getFace("smallinfofont", safeScale(9)),
            max_width = max(1, self.width - safeScale(4)),
            padding = 0,
        }
    end
    self.ges_events = { TapTool = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end
function ToolButton:getSize() return self.dimen end
function ToolButton:setActive(active) self.active = active and true or false end
function ToolButton:setDisabled(disabled) self.disabled = disabled and true or false end

function ToolButton:paintTo(bb, x, y)
    local w, h = self.width, self.height
    local inset = max(1, safeScale(1))
    local disabled = self.disabled
    local background = disabled and Blitbuffer.COLOR_WHITE
        or (self.active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_LIGHT_GRAY)
    local ink = disabled and Blitbuffer.COLOR_GRAY
        or (self.active and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK)
    local outline = disabled and Blitbuffer.COLOR_GRAY or Blitbuffer.COLOR_BLACK
    bb:paintRect(x, y, w, h, Blitbuffer.COLOR_WHITE)
    roundBox(bb, x, y, w, h, floor(min(w, h) * 0.3), background, outline, inset)
    local label_height = self.label_widget and safeScale(12) or 0
    local icon_height = max(1, h - label_height)
    paintGlyph(bb, x, y, w, icon_height, self.symbol, ink)
    if self.label_widget then
        self.label_widget.fgcolor = ink
        local text_size = self.label_widget:getSize()
        self.label_widget:paintTo(bb, x + floor((w - text_size.w) / 2),
            y + icon_height + floor((label_height - text_size.h) / 2))
    end
    self.dimen.x, self.dimen.y, self.dimen.w, self.dimen.h = x, y, w, h
end

function ToolButton:onTapTool()
    if self.callback and not self.disabled then self.callback() end
    return true
end

local ColorSwatch = InputContainer:extend{
    color_id = 1, active = false, callback = nil, width = nil, height = nil, dimen = nil,
}

function ColorSwatch:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.ges_events = { TapSwatch = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end
function ColorSwatch:getSize() return self.dimen end
function ColorSwatch:setActive(active) self.active = active and true or false end

function ColorSwatch:paintTo(bb, x, y)
    local w, h = self.width, self.height
    local entry = palette[clamp(tonumber(self.color_id) or 1, 1, #palette)]
    local border = self.active and max(3, safeScale(3)) or max(1, safeScale(1))
    local radius = floor(min(w, h) * 0.3)
    bb:paintRect(x, y, w, h, Blitbuffer.COLOR_WHITE)
    roundBox(bb, x, y, w, h, radius, Blitbuffer.COLOR_WHITE, self.active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_GRAY, border)
    border = border + max(1, safeScale(1)) + floor(radius * 0.3)
    paintDitheredRect(bb, x + border, y + border, w - border * 2, h - border * 2, entry)
    self.dimen.x, self.dimen.y, self.dimen.w, self.dimen.h = x, y, w, h
end
function ColorSwatch:onTapSwatch()
    if self.callback then self.callback() end
    return true
end

local Chip = InputContainer:extend{
    text = nil, symbol = nil, color = nil, preview = nil, active = false,
    callback = nil, width = nil, height = nil, dimen = nil,
}

function Chip:_reserved()
    local reserved = safeScale(16)
    if self.symbol then reserved = reserved + safeScale(16) end
    if self.color then reserved = reserved + (self.color_size or 0) + safeScale(4) end
    if self.preview then reserved = reserved + max(0, self.height - safeScale(8)) end
    return reserved
end
function Chip:_makeText()
    if self.text_widget then pcall(function() self.text_widget:free() end) end
    self.text_widget = TextWidget:new{
        text = tostring(self.text or ""),
        face = Font:getFace("smallinfofont", safeScale(12)),
        bold = true,
        max_width = max(1, self.width - self:_reserved()),
        padding = 0,
    }
end
function Chip:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.color_size = self.color and min(safeScale(18), max(1, self.width - safeScale(22))) or 0
    self:_makeText()
    self.ges_events = { TapChip = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end
function Chip:getSize() return self.dimen end
function Chip:setActive(active) self.active = active and true or false end
function Chip:setText(text)
    self.text = text
    self:_makeText()
end

function Chip:paintTo(bb, x, y)
    local w, h = self.width, self.height
    local inset = max(1, safeScale(1))
    local background = self.active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_LIGHT_GRAY
    local ink = self.active and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
    bb:paintRect(x, y, w, h, Blitbuffer.COLOR_WHITE)
    roundBox(bb, x, y, w, h, floor(h * 0.4), background, Blitbuffer.COLOR_BLACK, inset)
    local icon_size = min(h - safeScale(10), safeScale(18))
    if self.symbol and icon_size > 4 then
        paintGlyph(bb, x + safeScale(4), y + floor((h - icon_size) / 2), icon_size, icon_size, self.symbol, ink)
    end
    if self.color and self.color_size > 0 then
        local color_x, color_y = x + safeScale(4), y + floor((h - self.color_size) / 2)
        bb:paintRect(color_x, color_y, self.color_size, self.color_size, Blitbuffer.COLOR_BLACK)
        if self.color_size > 2 then
            paintDitheredRect(bb, color_x + 1, color_y + 1, self.color_size - 2, self.color_size - 2, self.color)
        end
    end
    if self.text_widget then
        self.text_widget.fgcolor = ink
        local size = self.text_widget:getSize()
        local text_x
        if self.symbol then
            text_x = x + safeScale(6) + icon_size
        elseif self.color then
            text_x = x + safeScale(4) + self.color_size + safeScale(6)
        else
            text_x = floor(x + (w - size.w) / 2)
        end
        self.text_widget:paintTo(bb, text_x, y + floor((h - size.h) / 2))
    end
    self.dimen.x, self.dimen.y, self.dimen.w, self.dimen.h = x, y, w, h
end
function Chip:onTapChip()
    if self.callback then self.callback() end
    return true
end

local Backdrop = Widget:extend{ width = nil, height = nil }
function Backdrop:init() self.dimen = Geom:new{ w = self.width, h = self.height } end
function Backdrop:paintTo(bb, x, y)
    bb:paintRect(x, y, self.width, self.height, Blitbuffer.COLOR_WHITE)
end

local Outline = Widget:extend{ width = nil, height = nil, thickness = 2 }
function Outline:init() self.dimen = Geom:new{ w = self.width, h = self.height } end
function Outline:paintTo(bb, x, y)
    local t = self.thickness
    roundBox(bb, x, y, self.width, self.height, safeScale(5), Blitbuffer.COLOR_WHITE, Blitbuffer.COLOR_BLACK, t)
end

local StatusLine = Widget:extend{ text = "", width = nil, height = nil }
function StatusLine:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self:setText(self.text)
end
function StatusLine:setText(text)
    self.text = text
    if self.text_widget then pcall(function() self.text_widget:free() end) end
    self.text_widget = TextWidget:new{
        text = tostring(text or ""),
        face = Font:getFace("smallinfofont", safeScale(11)),
        max_width = max(1, self.width),
        padding = 0,
    }
end
function StatusLine:paintTo(bb, x, y)
    bb:paintRect(x, y, self.width, self.height, Blitbuffer.COLOR_WHITE)
    local size = self.text_widget:getSize()
    self.text_widget:paintTo(bb, x + max(0, self.width - size.w), y + floor((self.height - size.h) / 2))
end

----------------------------------------------------------------
-- Style dialog: brush, stroke width and color
----------------------------------------------------------------

local function sampleObject(brush, size, color, x, y, w, h)
    local o = newObject("path", brush, size, color)
    local n = 40
    for i = 0, n do
        local t = i / n
        addPoint(o, x + w * 0.08 + w * 0.84 * t, y + h * 0.5 + math.sin(t * math.pi * 2) * h * 0.24,
            0.2 + 0.8 * math.sin(t * math.pi))
    end
    return o
end

local StyleDialog = InputContainer:extend{ app = nil, on_change = nil, on_close = nil, dimen = nil }

function StyleDialog:init()
    self.texts = {}
    self:_build()
    local sw, sh = safeDimension(Screen:getWidth(), 600), safeDimension(Screen:getHeight(), 800)
    self.ges_events = { TapDialog = { GestureRange:new{ ges = "tap", range = Geom:new{ x = 0, y = 0, w = sw, h = sh } } } }
end

function StyleDialog:_text(key, text, size, bold)
    local id = key .. "|" .. tostring(text) .. "|" .. size
    local widget = self.texts[id]
    if not widget then
        widget = TextWidget:new{ text = tostring(text), face = Font:getFace("smallinfofont", size), bold = bold,
            padding = 0, max_width = self.dimen.w }
        self.texts[id] = widget
    end
    return widget
end

function StyleDialog:_build()
    local app = self.app
    local sw, sh = safeDimension(Screen:getWidth(), 600), safeDimension(Screen:getHeight(), 800)
    local pad, gap = safeScale(10), safeScale(6)
    local w = min(sw - safeScale(12), safeScale(640))
    local inner = w - pad * 2
    local items = {}
    local function add(item) items[#items + 1] = item; return item end
    local y = pad

    local title_h = safeScale(36)
    add{ kind = "title", x = pad, y = y, w = inner - safeScale(104), h = title_h, text = _("Brush & color") }
    add{ kind = "button", x = pad + inner - safeScale(96), y = y, w = safeScale(96), h = title_h, text = _("Done"),
        action = function() self:close() end }
    y = y + title_h + pad
    local preview_h = safeScale(78)
    add{ kind = "preview", x = pad, y = y, w = inner, h = preview_h }
    y = y + preview_h + pad

    add{ kind = "label", x = pad, y = y, w = inner, h = safeScale(18), text = _("Brush") }
    y = y + safeScale(20)
    local cols = inner >= safeScale(540) and 6 or 3
    local cell_w = floor((inner - gap * (cols - 1)) / cols)
    local cell_h = safeScale(66)
    for index, name in ipairs(BRUSH_ORDER) do
        local col, row = (index - 1) % cols, floor((index - 1) / cols)
        add{ kind = "brush", name = name, x = pad + col * (cell_w + gap), y = y + row * (cell_h + gap), w = cell_w, h = cell_h,
            action = function() self:_setBrush(name) end }
    end
    y = y + ceil(#BRUSH_ORDER / cols) * (cell_h + gap) + safeScale(2)

    add{ kind = "label", x = pad, y = y, w = inner, h = safeScale(18), text = _("Stroke width") }
    y = y + safeScale(20)
    local slots = #Draw.brushSizes + 2
    local size_w = floor((inner - gap * (slots - 1)) / slots)
    local size_h = safeScale(52)
    add{ kind = "step", symbol = "minus", x = pad, y = y, w = size_w, h = size_h,
        action = function() self:_setSize(Draw.nextSize(app.brush_size, -1)) end }
    for index, value in ipairs(Draw.brushSizes) do
        add{ kind = "size", value = value, x = pad + index * (size_w + gap), y = y, w = size_w, h = size_h,
            action = function() self:_setSize(value) end }
    end
    add{ kind = "step", symbol = "plus", x = pad + (slots - 1) * (size_w + gap), y = y, w = size_w, h = size_h,
        action = function() self:_setSize(Draw.nextSize(app.brush_size, 1)) end }
    y = y + size_h + pad

    add{ kind = "label", x = pad, y = y, w = inner, h = safeScale(18), text = _("Color") }
    y = y + safeScale(20)
    local per_row = 8
    local sw_w = floor((inner - gap * (per_row - 1)) / per_row)
    local sw_h = safeScale(42)
    for index, color in ipairs(palette) do
        add{ kind = "color", color = color, x = pad + (index - 1) * (sw_w + gap), y = y, w = sw_w, h = sw_h,
            action = function() self:_setColor(color) end }
    end
    y = y + sw_h + gap
    for index, color in ipairs(EXTRA_COLORS) do
        local col, row = (index - 1) % per_row, floor((index - 1) / per_row)
        add{ kind = "color", color = color, x = pad + col * (sw_w + gap), y = y + row * (sw_h + gap), w = sw_w, h = sw_h,
            action = function() self:_setColor(color) end }
    end
    y = y + ceil(#EXTRA_COLORS / per_row) * (sw_h + gap)
    add{ kind = "button", x = pad, y = y, w = safeScale(150), h = safeScale(40), text = _("RGB / hex…"),
        action = function() self:_openRGB() end }
    add{ kind = "note", x = pad + safeScale(160), y = y, w = inner - safeScale(160), h = safeScale(40),
        text = _("Drawing uses 8 fast colors; others are dithered until a full refresh.") }
    y = y + safeScale(40) + pad

    local h = y
    local fx, fy = floor((sw - w) / 2), max(safeScale(6), floor((sh - h) / 2))
    self.items = items
    self.dimen = Geom:new{ x = fx, y = fy, w = w, h = h }
end

function StyleDialog:getSize() return self.dimen end

function StyleDialog:_changed()
    if self.on_change then pcall(self.on_change) end
    UIManager:setDirty(self, "ui", self.dimen)
end
function StyleDialog:_setBrush(name) self.app.brush = name; self:_changed() end
function StyleDialog:_setSize(size) self.app:setBrushSize(size); self:_changed() end
function StyleDialog:_setColor(color) self.app.color = copyColor(color); self:_changed() end
function StyleDialog:_openRGB()
    local app = self.app
    local current = app.color
    local dialog
    dialog = AppDockDialogs.InputDialog:new{
        title = _("RGB color"),
        text = _("Enter a six-digit hex color or three RGB channel values."),
        input = string.format("#%02X%02X%02X", current[1], current[2], current[3]),
        input_hint = _("#RRGGBB or R,G,B"),
        buttons = { {
            { text = _("Cancel") },
            { text = _("Apply"), is_enter_default = true, callback = function()
                local r, g, b = Draw.parseRGB(dialog:getInputText())
                if r == nil then return end
                app:setRGBColor(r, g, b)
                self:_changed()
            end },
        } },
    }
    AppDockKeyboard.attach(dialog)
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function StyleDialog:close()
    UIManager:close(self)
    if self.on_close then pcall(self.on_close) end
end

function StyleDialog:onTapDialog(_arg, ges)
    local pos, d = ges and ges.pos, self.dimen
    if not pos then return true end
    if pos.x < d.x or pos.y < d.y or pos.x >= d.x + d.w or pos.y >= d.y + d.h then
        self:close()
        return true
    end
    for _index, item in ipairs(self.items) do
        if item.action and pos.x >= d.x + item.x and pos.x < d.x + item.x + item.w
            and pos.y >= d.y + item.y and pos.y < d.y + item.y + item.h then
            item.action()
            return true
        end
    end
    return true
end

function StyleDialog:paintTo(bb, _x, _y)
    local app, d = self.app, self.dimen
    local color_mode = hasColorScreen()
    -- The dialog is refreshed with the normal UI waveform, so it may show true colors.
    local function painterFor(x0, y0, x1, y1)
        return screenPainter(bb, { x0, y0, x1, y1 }, "true")
    end
    local border = max(2, safeScale(2))
    bb:paintRect(d.x - 2, d.y - 2, d.w + 4, d.h + 4, Blitbuffer.COLOR_WHITE)
    roundBox(bb, d.x, d.y, d.w, d.h, safeScale(16), Blitbuffer.COLOR_WHITE, Blitbuffer.COLOR_BLACK, border)
    local RR = safeScale(9)
    local function text(key, str, size, bold, x, y, w, h, center, ink)
        local widget = self:_text(key, str, size, bold)
        widget.fgcolor = ink or Blitbuffer.COLOR_BLACK
        local sz = widget:getSize()
        local tx = center and (x + floor((w - min(sz.w, w)) / 2)) or x
        widget:paintTo(bb, tx, y + floor((h - sz.h) / 2))
    end
    local function sample(brush, size, color, x, y, w, h)
        local P = painterFor(x, y, x + w - 1, y + h - 1)
        local prof = BRUSH[brush]
        local fit_size = min(size, max(1, floor(h * 0.4 / prof.scale)))
        drawObject(P, sampleObject(brush, fit_size, color, x, y, w, h), { ox = 0, oy = 0, s = 1 })
    end

    for _index, item in ipairs(self.items) do
        local x, y, w, h = d.x + item.x, d.y + item.y, item.w, item.h
        local kind = item.kind
        if kind == "title" then
            text("title", item.text, safeScale(16), true, x, y, w, h)
        elseif kind == "label" then
            text("label", item.text, safeScale(11), true, x, y, w, h)
        elseif kind == "note" then
            local widget = TextWidget:new{ text = item.text, face = Font:getFace("smallinfofont", safeScale(10)),
                max_width = w, padding = 0 }
            widget:paintTo(bb, x, y + floor((h - widget:getSize().h) / 2))
            widget:free()
        elseif kind == "button" then
            roundBox(bb, x, y, w, h, RR, Blitbuffer.COLOR_LIGHT_GRAY, Blitbuffer.COLOR_BLACK, max(1, safeScale(1)))
            text("btn", item.text, safeScale(13), true, x, y, w, h, true)
        elseif kind == "preview" then
            roundBox(bb, x, y, w, h, RR, Blitbuffer.COLOR_WHITE, Blitbuffer.COLOR_BLACK, max(1, safeScale(1)))
            sample(app.brush, app.brush_size, app.color, x + safeScale(6), y + 3, w - safeScale(12), h - 6)
        elseif kind == "brush" then
            local active = app.brush == item.name
            roundBox(bb, x, y, w, h, RR, Blitbuffer.COLOR_WHITE, Blitbuffer.COLOR_BLACK,
                active and max(3, safeScale(3)) or max(1, safeScale(1)))
            local label_h = safeScale(16)
            sample(item.name, min(app.brush_size, 10), app.color, x + 3, y + 3, w - 6, h - label_h - 4)
            text("bl", BRUSH[item.name].label, safeScale(10), active, x, y + h - label_h - 2, w, label_h, true)
        elseif kind == "step" then
            roundBox(bb, x, y, w, h, RR, Blitbuffer.COLOR_LIGHT_GRAY, Blitbuffer.COLOR_BLACK, max(1, safeScale(1)))
            paintGlyph(bb, x, y, w, h, item.symbol, Blitbuffer.COLOR_BLACK)
        elseif kind == "size" then
            local active = app.brush_size == item.value
            roundBox(bb, x, y, w, h, RR, active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
                Blitbuffer.COLOR_BLACK, max(1, safeScale(1)))
            local ink = active and { 255, 255, 255 } or { 0, 0, 0 }
            local P = painterFor(x, y, x + w - 1, y + h - 1)
            P:setColor(ink)
            P:disc(x + w / 2, y + safeScale(17), min(item.value, safeScale(26)))
            text("sz", tostring(item.value), safeScale(10), active, x, y + h - safeScale(16), w, safeScale(14), true,
                active and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK)
        elseif kind == "color" then
            local active = sameColor(app.color, item.color)
            local inset = active and max(3, safeScale(3)) or max(1, safeScale(1))
            roundBox(bb, x, y, w, h, RR, active and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_GRAY,
                active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_GRAY, inset)
            inset = inset + max(1, safeScale(1)) + floor(RR * 0.25)
            local P = painterFor(x + inset, y + inset, x + w - inset - 1, y + h - inset - 1)
            P:setColor(item.color)
            P:rect(x + inset, y + inset, w - inset * 2, h - inset * 2)
        end
    end
    local _unused = color_mode
end

----------------------------------------------------------------
-- Background dialog: page paper (blank, ruled, grid, dots ...)
----------------------------------------------------------------

local PaperDialog = InputContainer:extend{ app = nil, on_change = nil, on_close = nil, dimen = nil }

function PaperDialog:init()
    self.texts = {}
    self:_build()
    local sw, sh = safeDimension(Screen:getWidth(), 600), safeDimension(Screen:getHeight(), 800)
    self.ges_events = { TapDialog = { GestureRange:new{ ges = "tap", range = Geom:new{ x = 0, y = 0, w = sw, h = sh } } } }
end

function PaperDialog:_build()
    local sw, sh = safeDimension(Screen:getWidth(), 600), safeDimension(Screen:getHeight(), 800)
    local pad, gap = safeScale(10), safeScale(8)
    local w = min(sw - safeScale(12), safeScale(540))
    local inner = w - pad * 2
    local items = {}
    local function add(item) items[#items + 1] = item; return item end
    local y = pad
    local title_h = safeScale(36)
    add{ kind = "title", x = pad, y = y, w = inner - safeScale(104), h = title_h, text = _("Page background") }
    add{ kind = "button", x = pad + inner - safeScale(96), y = y, w = safeScale(96), h = title_h, text = _("Done"),
        action = function() self:close() end }
    y = y + title_h + pad
    local cols = inner >= safeScale(440) and 4 or 3
    local cell_w = floor((inner - gap * (cols - 1)) / cols)
    local cell_h = floor(cell_w * 1.2)
    for index, name in ipairs(PAPERS) do
        local col, row = (index - 1) % cols, floor((index - 1) / cols)
        add{ kind = "paper", name = name, x = pad + col * (cell_w + gap), y = y + row * (cell_h + gap),
            w = cell_w, h = cell_h, action = function() self:_set(name) end }
    end
    y = y + ceil(#PAPERS / cols) * (cell_h + gap) + pad - gap
    self.items = items
    self.dimen = Geom:new{ x = floor((sw - w) / 2), y = max(safeScale(6), floor((sh - y) / 2)), w = w, h = y }
end

PaperDialog._text = StyleDialog._text
PaperDialog.getSize = StyleDialog.getSize
PaperDialog.close = StyleDialog.close
PaperDialog.onTapDialog = StyleDialog.onTapDialog

function PaperDialog:_set(name)
    self.app:setPaper(name)
    if self.on_change then pcall(self.on_change) end
    UIManager:setDirty(self, "ui", self.dimen)
end

function PaperDialog:paintTo(bb, _x, _y)
    local app, d = self.app, self.dimen
    local RR = safeScale(9)
    bb:paintRect(d.x - 2, d.y - 2, d.w + 4, d.h + 4, Blitbuffer.COLOR_WHITE)
    roundBox(bb, d.x, d.y, d.w, d.h, safeScale(16), Blitbuffer.COLOR_WHITE, Blitbuffer.COLOR_BLACK, max(2, safeScale(2)))
    local current = app:getPaper()
    local function text(key, str, size, bold, x, y, w, h, center)
        local widget = self:_text(key, str, size, bold)
        widget.fgcolor = Blitbuffer.COLOR_BLACK
        local sz = widget:getSize()
        local tx = center and (x + floor((w - min(sz.w, w)) / 2)) or x
        widget:paintTo(bb, tx, y + floor((h - sz.h) / 2))
    end
    for _index, item in ipairs(self.items) do
        local x, y, w, h = d.x + item.x, d.y + item.y, item.w, item.h
        if item.kind == "title" then
            text("title", item.text, safeScale(16), true, x, y, w, h)
        elseif item.kind == "button" then
            roundBox(bb, x, y, w, h, RR, Blitbuffer.COLOR_LIGHT_GRAY, Blitbuffer.COLOR_BLACK, max(1, safeScale(1)))
            text("btn", item.text, safeScale(13), true, x, y, w, h, true)
        elseif item.kind == "paper" then
            local active = current == item.name
            roundBox(bb, x, y, w, h, RR, Blitbuffer.COLOR_WHITE, Blitbuffer.COLOR_BLACK,
                active and max(3, safeScale(3)) or max(1, safeScale(1)))
            local label_h = safeScale(20)
            local pad = safeScale(8)
            local px, py = x + pad, y + pad
            local pw, ph = w - pad * 2, h - label_h - pad * 2
            bb:paintRect(px, py, pw, ph, Blitbuffer.COLOR_WHITE)
            local s = 0.32
            local P = screenPainter(bb, { px, py, px + pw - 1, py + ph - 1 }, "true")
            drawPaper(P, pw / s, ph / s, { ox = px, oy = py, s = s }, item.name)
            bb:paintRect(px, py, pw, 1, Blitbuffer.COLOR_GRAY); bb:paintRect(px, py + ph - 1, pw, 1, Blitbuffer.COLOR_GRAY)
            bb:paintRect(px, py, 1, ph, Blitbuffer.COLOR_GRAY); bb:paintRect(px + pw - 1, py, 1, ph, Blitbuffer.COLOR_GRAY)
            text("pl", PAPER_LABELS[item.name] or item.name, safeScale(11), active, x, y + h - label_h - safeScale(4), w, label_h, true)
        end
    end
end

----------------------------------------------------------------
-- Canvas
----------------------------------------------------------------

local Canvas = InputContainer:extend{ app = nil, width = nil, height = nil, dimen = nil }

local PRESSURE_CURVES = { soft = { gamma = 0.6 }, linear = { gamma = 1 }, firm = { gamma = 1.7 } }
local PALM_WINDOW = 0.8
local TRANSIENT_WINDOW = 0.6
local PAINT_INTERVAL = 0.016
local MIN_ZOOM, MAX_ZOOM = 0.25, 8

local function isStylusEvent(ev)
    if not ev then return false end
    return ev.pointer_type == "stylus" or ev.pointer_type == "pen" or ev.pointer_type == "eraser"
        or ev.tool == "stylus" or ev.tool == "pen" or ev.tool == "eraser"
        or ev.stylus == true or ev.eraser == true
        or ev.marker_button == true or ev.stylus_button == true
end

function Canvas:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    local function range() return self.dimen end
    self.ges_events = {
        Paint = { GestureRange:new{ ges = "pan", range = range } },
        PaintTap = { GestureRange:new{ ges = "tap", range = range } },
        PaintRelease = { GestureRange:new{ ges = "pan_release", range = range } },
        PaintTouch = { GestureRange:new{ ges = "touch", range = range } },
        PaintTwoTap = { GestureRange:new{ ges = "two_finger_tap", range = range } },
        PaintTwoSwipe = { GestureRange:new{ ges = "two_finger_swipe", range = range } },
        PaintPinch = { GestureRange:new{ ges = "pinch", range = range } },
        PaintSpread = { GestureRange:new{ ges = "spread", range = range } },
    }
    self.last_refresh = 0
end

-- Document -> screen transform of the current zoom/pan.
function Canvas:_view()
    local app = self.app
    local s = (self.fit or 1) * (app.zoom or 1)
    return {
        s = s,
        ox = self.origin_x + self.dimen.w / 2 + (app.pan_x or 0) - app.width * s / 2,
        oy = self.origin_y + self.dimen.h / 2 + (app.pan_y or 0) - app.height * s / 2,
    }
end

function Canvas:_rect()
    return { self.origin_x, self.origin_y, self.origin_x + self.dimen.w - 1, self.origin_y + self.dimen.h - 1 }
end

function Canvas:_clampPan()
    local app = self.app
    local s = (self.fit or 1) * (app.zoom or 1)
    local mx = app.width * s / 2 + self.dimen.w / 2 - safeScale(40)
    local my = app.height * s / 2 + self.dimen.h / 2 - safeScale(40)
    app.pan_x = clamp(app.pan_x or 0, -mx, mx)
    app.pan_y = clamp(app.pan_y or 0, -my, my)
end

-- Document coordinates of a touch (clamped to the page).
function Canvas:_point(ev)
    local p = ev and ev.pos
    if not p or not self.origin_x then return nil end
    local v = self:_view()
    local app = self.app
    return clamp((p.x - v.ox) / v.s, 0, app.width), clamp((p.y - v.oy) / v.s, 0, app.height), ev
end

function Canvas:_modeFor(ev)
    local app = self.app
    if app.tool == "eraser" then return "eraser" end
    if ev then
        if self:_isEraserEnd(ev) and app.eraser_end_action ~= "off" then return "eraser" end
        if ev.marker_button == true or ev.stylus_button == true then
            if app.side_button_action == "marker" then return "marker" end
            if app.side_button_action == "eraser" then return "eraser" end
        end
    end
    return "pen"
end
function Canvas:_isEraserEnd(ev)
    return ev and (ev.tool == "eraser" or ev.pointer_type == "eraser" or ev.eraser == true) or false
end

-- Pen pressure after the chosen curve (1 for fingers or when pressure is off).
function Canvas:_pressureFor(ev)
    local app = self.app
    local pressure = ev and tonumber(ev.pressure)
    local stylus = isStylusEvent(ev) or self._stylus_tracking_id ~= nil
    local curve = PRESSURE_CURVES[app.pressure_curve or "linear"]
    if stylus and curve and pressure and pressure > 0 and app.pressure_enabled then
        return clamp(pressure, 0, 1) ^ curve.gamma
    end
    return 1
end

function Canvas:_containsPoint(ev)
    local p = ev and ev.pos
    if not p or not self.origin_x or not self.origin_y then return false end
    return p.x >= self.origin_x and p.y >= self.origin_y
        and p.x < self.origin_x + self.dimen.w and p.y < self.origin_y + self.dimen.h
end

function Canvas:_rejectFinger(ev)
    if isStylusEvent(ev) then return false end
    local app = self.app
    -- Panning and selecting with a finger stays possible next to a pen.
    if app.tool == "hand" then return false end
    if self._raw_stylus_active or self._stylus_tracking_id ~= nil then return true end
    if app:fingerIgnored() then return true end
    if self._last_pen_time and monotonicNow() - self._last_pen_time < PALM_WINDOW then return true end
    return false
end

function Canvas:_cancelFingerStroke()
    local app = self.app
    local transient = self._finger_edit
    if not transient then return false end
    if app.history[#app.history] ~= transient.entry then
        self._finger_edit = nil
        return false
    end
    if app.stroke or monotonicNow() - transient.time < TRANSIENT_WINDOW then
        app.stroke, app.fill_gesture = nil, nil
        app:discardLastEdit()
        self._finger_edit = nil
        if self.origin_x then self:refreshFast() end
        return true
    end
    return false
end

function Canvas:handleStylusSample(ev, tracking_id)
    local app = self.app
    app.pen_seen = true
    self._last_pen_time = monotonicNow()
    if not self:_containsPoint(ev) then
        if self._stylus_tracking_id == tracking_id then self:finishStylus(tracking_id) end
        return false
    end
    if self._stylus_tracking_id ~= nil and self._stylus_tracking_id ~= tracking_id then
        self:finishStylus(self._stylus_tracking_id)
    end
    self._raw_stylus_active = true
    if self._stylus_tracking_id == nil then
        self:_cancelFingerStroke()
        self._stylus_tracking_id = tracking_id
        return self:_begin(ev)
    end
    return self:_continue(ev)
end

function Canvas:finishStylus(tracking_id)
    if tracking_id ~= nil and self._stylus_tracking_id ~= tracking_id then return false end
    local was_raw_stylus = self._raw_stylus_active == true
    self._last_pen_time = monotonicNow()
    self:_commit()
    self._stylus_tracking_id = nil
    if was_raw_stylus and UIManager.nextTick then
        self._ignore_gesture_after_stylus = true
        UIManager:nextTick(function()
            self._ignore_gesture_after_stylus = nil
            if self._stylus_tracking_id == nil then self._raw_stylus_active = nil end
        end)
    else
        self._raw_stylus_active = nil
    end
    self:_notifySoon()
    return true
end

-- Undo/redo buttons and status line are repainted only after the pen has been idle for a
-- moment. Repainting them right at pen-up queued extra e-ink updates and stalled the
-- live preview of the next stroke.
function Canvas:_notifySoon()
    local app = self.app
    if not (app and app.notifyChange) then return end
    if not (UIManager.scheduleIn and UIManager.unschedule) then app:notifyChange() return end
    if self._notify_cb then UIManager:unschedule(self._notify_cb) end
    self._notify_cb = function()
        self._notify_cb = nil
        if self._dead then return end
        if app.stroke or self._stylus_tracking_id ~= nil then self:_notifySoon() return end
        app:notifyChange()
    end
    UIManager:scheduleIn(0.8, self._notify_cb)
end

----------------------------------------------------------------
-- Canvas: refresh handling
----------------------------------------------------------------

function Canvas:_markDirty(x0, y0, x1, y1, render)
    if not self.origin_x then return end
    local c = self:_rect()
    x0, y0 = max(floor(x0), c[1]), max(floor(y0), c[2])
    x1, y1 = min(ceil(x1), c[3]), min(ceil(y1), c[4])
    if x1 < x0 or y1 < y0 then return end
    local pend = self._pend
    if pend then
        pend[1], pend[2] = min(pend[1], x0), min(pend[2], y0)
        pend[3], pend[4] = max(pend[3], x1), max(pend[4], y1)
    else
        self._pend = { x0, y0, x1, y1 }
    end
    if render then self._pend_render = true end
    self:_flush(false)
end

function Canvas:_flush(force)
    local box = self._pend
    if not box or self._dead then return end
    local now = monotonicNow()
    local interval = PAINT_INTERVAL
    if self._pend_render then
        local area = (box[3] - box[1] + 1) * (box[4] - box[2] + 1)
        interval = area > self.dimen.w * self.dimen.h / 4 and 0.12 or 0.04
    end
    if not force and now - (self._last_paint or 0) < interval then
        if UIManager.scheduleIn and not self._flush_scheduled then
            self._flush_scheduled = true
            UIManager:scheduleIn(interval, function()
                self._flush_scheduled = false
                self._last_paint = 0
                self:_flush(false)
            end)
        end
        return
    end
    self._pend = nil
    local render = self._pend_render
    self._pend_render = false
    self._last_paint = now
    if render and Screen.bb then self:_renderTo(Screen.bb, box, "fast") end
    if not UIManager.setDirty then return end
    UIManager:setDirty(nil, "fast", Geom:new{ x = box[1], y = box[2], w = box[3] - box[1] + 1, h = box[4] - box[2] + 1 })
    if force or now - (self.last_refresh or 0) >= 0.04 then
        self.last_refresh = now
        if UIManager.forceRePaint then UIManager:forceRePaint() end
    end
end

-- Renders the document into `bb` for the given screen rectangle.
-- mode "fast": only the 8 fast colors (dithered); mode "true": real colors.
function Canvas:_renderTo(bb, clip, mode)
    if not self.origin_x then return end
    local c = self:_rect()
    local x0, y0 = max(clip[1], c[1]), max(clip[2], c[2])
    local x1, y1 = min(clip[3], c[3]), min(clip[4], c[4])
    if x1 < x0 or y1 < y0 then return end
    bb:paintRect(x0, y0, x1 - x0 + 1, y1 - y0 + 1, Blitbuffer.COLOR_WHITE)
    local P = screenPainter(bb, { x0, y0, x1, y1 }, mode)
    local v = self:_view()
    renderDocument(self.app, P, v, true)
    drawOverlays(self, P, v)
end

function Canvas:paintTo(bb, x, y)
    self.origin_x, self.origin_y = x, y
    self.dimen.x, self.dimen.y = x, y
    self._pend, self._pend_render = nil, false
    self:_renderTo(bb, self:_rect(), self.render_true and "true" or "fast")
end

-- Re-renders the whole canvas with the fast waveform (dithered colors).
function Canvas:refreshFast()
    if not self.origin_x or not UIManager.setDirty then return end
    self._pend, self._pend_render = nil, false
    if Screen.bb then self:_renderTo(Screen.bb, self:_rect(), "fast") end
    UIManager:setDirty(nil, "fast", Geom:new{ x = self.origin_x, y = self.origin_y, w = self.dimen.w, h = self.dimen.h })
    if UIManager.forceRePaint then UIManager:forceRePaint() end
    if UIManager.yieldToEPDC then UIManager:yieldToEPDC() end
end

-- Full refresh: the canvas is rendered in true colors and flashed to the screen.
function Canvas:fullRefresh()
    if not self.origin_x or not UIManager.setDirty then return end
    self._pend, self._pend_render = nil, false
    self.render_true = true
    if Screen.bb then self:_renderTo(Screen.bb, self:_rect(), "true") end
    UIManager:setDirty(nil, "full", Geom:new{ x = self.origin_x, y = self.origin_y, w = self.dimen.w, h = self.dimen.h })
    if UIManager.forceRePaint then UIManager:forceRePaint() end
end

function Canvas:_cancelAutoRefresh()
    if self._auto_cb and UIManager.unschedule then UIManager:unschedule(self._auto_cb) end
    self._auto_cb = nil
end
function Canvas:_scheduleAutoRefresh()
    self:_cancelAutoRefresh()
    local secs = tonumber(self.app.auto_refresh) or 0
    if secs <= 0 or self._dead or not UIManager.scheduleIn then return end
    self._auto_cb = function()
        self._auto_cb = nil
        if not self._dead and not self.app.stroke then self:fullRefresh() end
    end
    UIManager:scheduleIn(secs, self._auto_cb)
end

function Canvas:zoomBy(factor, ax, ay)
    local app = self.app
    if not self.origin_x then return false end
    local v = self:_view()
    ax = ax or (self.origin_x + self.dimen.w / 2)
    ay = ay or (self.origin_y + self.dimen.h / 2)
    local z = clamp((app.zoom or 1) * factor, MIN_ZOOM, MAX_ZOOM)
    if z == app.zoom then return false end
    local docx, docy = (ax - v.ox) / v.s, (ay - v.oy) / v.s
    app.zoom = z
    local s2 = (self.fit or 1) * z
    app.pan_x = (ax - docx * s2) - self.origin_x - self.dimen.w / 2 + app.width * s2 / 2
    app.pan_y = (ay - docy * s2) - self.origin_y - self.dimen.h / 2 + app.height * s2 / 2
    self:_clampPan()
    self.render_true = false
    self:refreshFast()
    if app.on_view_change then pcall(app.on_view_change) end
    return true
end

function Canvas:resetView()
    local app = self.app
    app.zoom, app.pan_x, app.pan_y = 1, 0, 0
    self.render_true = false
    self:refreshFast()
    if app.on_view_change then pcall(app.on_view_change) end
end

----------------------------------------------------------------
-- Canvas: editing
----------------------------------------------------------------

function Canvas:_paintLive(obj, i)
    if not self.origin_x or not Screen.bb then return end
    local v = self:_view()
    local P = screenPainter(Screen.bb, self:_rect(), "fast")
    local prof = BRUSH[obj.brush] or BRUSH.pen
    P:setColor(obj.color)
    P:setPattern(prof.pattern)
    local s = v.s
    local function dia(k) return max(1, strokeWidth(prof, obj.size, obj.p[k]) * s) end
    local cx, cy, cd = v.ox + obj.x[i] * s, v.oy + obj.y[i] * s, dia(i)
    local x0, y0, x1, y1 = cx, cy, cx, cy
    if i == 1 then
        P:stamp(prof, cx, cy, cd)
    else
        local px, py, pd = v.ox + obj.x[i - 1] * s, v.oy + obj.y[i - 1] * s, dia(i - 1)
        P:segment(prof, px, py, pd, cx, cy, cd)
        x0, y0, x1, y1 = min(px, cx), min(py, cy), max(px, cx), max(py, cy)
        cd = max(cd, pd)
    end
    local pad = cd * 0.75 + 2
    self:_markDirty(x0 - pad, y0 - pad, x1 + pad, y1 + pad, false)
end

-- Screen rectangle of a document bounding box.
function Canvas:_docBox(b, pad)
    local v = self:_view()
    pad = pad or 0
    return v.ox + b[1] * v.s - pad, v.oy + b[2] * v.s - pad, v.ox + b[3] * v.s + pad, v.oy + b[4] * v.s + pad
end

function Canvas:_selHit(pos)
    local sel = self.app.sel
    if not sel then return nil end
    local v = self:_view()
    local corners, rot, x0, y0, x1, y1 = selHandles(sel.bbox, v)
    local reach = safeScale(26)
    if hypot(pos.x - rot[1], pos.y - rot[2]) <= reach then return "rotate" end
    for _index, c in ipairs(corners) do
        if hypot(pos.x - c[1], pos.y - c[2]) <= reach then return "scale" end
    end
    if pos.x >= x0 and pos.x <= x1 and pos.y >= y0 and pos.y <= y1 then return "move" end
    return nil
end

function Canvas:_begin(ev)
    local app = self.app
    if not self.origin_x or not ev or not ev.pos then return false end
    app:ensure()
    self.render_true = false
    self:_cancelAutoRefresh()
    local mode = self:_modeFor(ev)
    local tool = app.tool
    local pos = ev.pos
    -- The eraser end of a pen erases whatever drawing tool is selected.
    if mode == "eraser" and tool ~= "lasso" and tool ~= "hand" then tool = "eraser" end

    if tool == "hand" then
        app.stroke = { tool = "hand", sx = pos.x, sy = pos.y, pan_x0 = app.pan_x or 0, pan_y0 = app.pan_y or 0 }
        return true
    end

    if tool == "lasso" then
        local hit = self:_selHit(pos)
        if hit then
            local sel = app.sel
            local cx, cy = (sel.bbox[1] + sel.bbox[3]) / 2, (sel.bbox[2] + sel.bbox[4]) / 2
            app.stroke = { tool = "sel", handle = hit, sx = pos.x, sy = pos.y, cx = cx, cy = cy, layer = sel.layer,
                t = { dx = 0, dy = 0, s = 1, rot = 0 }, moved = false }
            return true
        end
        if app.sel then
            local old = app.sel.bbox
            app.sel = nil
            local x0, y0, x1, y1 = self:_docBox(old, safeScale(50))
            self:_markDirty(x0, y0, x1, y1, true)
        end
        app.stroke = { tool = "lasso", px = { pos.x }, py = { pos.y }, layer = app.active }
        return true
    end

    local x, y = self:_point(ev)
    if not x then return false end
    app:pushHistory()
    if self._stylus_tracking_id == nil then
        self._finger_edit = { entry = app.history[#app.history], time = monotonicNow() }
    else
        self._finger_edit = nil
    end

    if tool == "fill" then
        local changed = app:fillAt(x, y, app.color)
        app.fill_gesture = true
        app.stroke = nil
        if not changed then app:discardLastEdit() end
        self:refreshFast()
        return true
    end

    if tool == "eraser" then
        app.stroke = { tool = "eraser", layer = app.active, erased = false, lx = x, ly = y,
            big = self:_isEraserEnd(ev) }
        self:_eraseAt(app.stroke, x, y)
        return true
    end

    local brush = app.brush
    if mode == "marker" and tool == "pen" then brush = "marker" end
    local kind = tool == "pen" and "path" or tool
    local obj = newObject(kind, brush, app.brush_size, copyColor(app.color))
    local p = tool == "pen" and self:_pressureFor(ev) or 1
    addPoint(obj, x, y, p)
    app.stroke = { tool = tool, obj = obj, layer = app.active, mode = mode, x0 = x, y0 = y }
    if tool == "pen" then
        self:_paintLive(obj, 1)
    else
        addPoint(obj, x, y, 1)
    end
    return true
end

function Canvas:_eraseAt(st, x, y)
    local app = self.app
    local layer = app.layers[st.layer]
    if not layer then return end
    local v = self:_view()
    local r = max(app.brush_size * 1.5, 6 / v.s) * (st.big and 2 or 1)
    local step = max(r / 2, 1 / v.s)
    local dist = hypot(x - st.lx, y - st.ly)
    local n = max(1, ceil(dist / step))
    local dirty
    local objs = layer.objects
    for k = 1, n do
        local ex, ey = st.lx + (x - st.lx) * k / n, st.ly + (y - st.ly) * k / n
        for i = #objs, 1, -1 do
            local o = objs[i]
            local bb = objectBBox(o)
            if ex >= bb[1] - r and ex <= bb[3] + r and ey >= bb[2] - r and ey <= bb[4] + r then
                local prof = BRUSH[o.brush] or BRUSH.pen
                if distToObject(o, ex, ey) <= r + strokeWidth(prof, o.size, 1) * 0.5 then
                    table.remove(objs, i)
                    st.erased = true
                    dirty = unionBox(dirty, bb)
                end
            end
        end
    end
    st.lx, st.ly = x, y
    if dirty then
        local x0, y0, x1, y1 = self:_docBox(dirty, 2)
        self:_markDirty(x0, y0, x1, y1, true)
    end
end

-- Updates the live transform of the selection while a handle is dragged.
function Canvas:_dragSelection(ev)
    local app, st, sel = self.app, self.app.stroke, self.app.sel
    if not sel then return true end
    local v = self:_view()
    local pos = ev.pos
    local t = { dx = 0, dy = 0, s = 1, rot = 0 }
    local cxs, cys = v.ox + st.cx * v.s, v.oy + st.cy * v.s
    if st.handle == "move" then
        t.dx, t.dy = (pos.x - st.sx) / v.s, (pos.y - st.sy) / v.s
    elseif st.handle == "scale" then
        local d0 = max(8, hypot(st.sx - cxs, st.sy - cys))
        t.s = clamp(hypot(pos.x - cxs, pos.y - cys) / d0, 0.1, 10)
    else
        t.rot = atan2(pos.y - cys, pos.x - cxs) - atan2(st.sy - cys, st.sx - cxs)
    end
    if hypot(pos.x - st.sx, pos.y - st.sy) > safeScale(6) then st.moved = true end
    if not st.moved then return true end
    st.t = t
    local preview, box = {}, nil
    for _index, o in ipairs(sel.objs) do
        local copy = transformObject(o, t, st.cx, st.cy)
        preview[o] = copy
        box = unionBox(box, objectBBox(copy))
    end
    local old = sel.pbbox or sel.bbox
    sel.preview, sel.pbbox = preview, box
    local dirty = unionBox(old, box)
    local x0, y0, x1, y1 = self:_docBox(dirty, safeScale(50))
    self:_markDirty(x0, y0, x1, y1, true)
    return true
end

function Canvas:_continue(ev, final)
    local app = self.app
    if not ev or not ev.pos then return false end
    if app.fill_gesture then return true end
    local st = app.stroke
    if not st then return self:_begin(ev) end
    local pos, tool = ev.pos, st.tool

    if tool == "hand" then
        app.pan_x = st.pan_x0 + (pos.x - st.sx)
        app.pan_y = st.pan_y0 + (pos.y - st.sy)
        self:_clampPan()
        self:_markDirty(self.origin_x, self.origin_y, self.origin_x + self.dimen.w, self.origin_y + self.dimen.h, true)
        return true
    elseif tool == "lasso" then
        local n = #st.px
        if hypot(pos.x - st.px[n], pos.y - st.py[n]) >= 3 then
            st.px[n + 1], st.py[n + 1] = pos.x, pos.y
            local P = screenPainter(Screen.bb, self:_rect(), "fast")
            P:setColor({ 0, 0, 0 })
            P:line(st.px[n], st.py[n], pos.x, pos.y, 4)
            self:_markDirty(min(st.px[n], pos.x) - 2, min(st.py[n], pos.y) - 2,
                max(st.px[n], pos.x) + 2, max(st.py[n], pos.y) + 2, false)
        end
        return true
    elseif tool == "sel" then
        return self:_dragSelection(ev)
    end

    local x, y = self:_point(ev)
    if not x then return false end
    if tool == "eraser" then
        self:_eraseAt(st, x, y)
        return true
    end
    local obj = st.obj
    if tool == "pen" then
        local v = self:_view()
        local n = obj.n
        local p = self:_pressureFor(ev)
        local dsx, dsy = (x - obj.x[n]) * v.s, (y - obj.y[n]) * v.s
        if dsx * dsx + dsy * dsy < 0.25 and math.abs(p - obj.p[n]) < 0.02 then return true end
        if n >= MAX_POINTS then return true end
        addPoint(obj, x, y, p)
        self:_paintLive(obj, obj.n)
        return true
    end
    -- Shape tools: the second point follows the finger, preview is re-rendered.
    local before = objectBBox(obj)
    local old = { before[1], before[2], before[3], before[4] }
    obj.x[2], obj.y[2] = x, y
    obj.bb = nil
    local dirty = unionBox(old, objectBBox(obj))
    local x0, y0, x1, y1 = self:_docBox(dirty, 2)
    self:_markDirty(x0, y0, x1, y1, true)
    return true
end

-- Completes the current contact: commits the object, selection or transform.
function Canvas:_commit()
    local app = self.app
    local st = app.stroke
    app.stroke, app.fill_gesture = nil, nil
    if not st then
        self:_flush(true)
        return
    end
    local tool = st.tool
    local layer = app.layers[st.layer or app.active]
    local discard = false
    if tool == "pen" then
        if layer and st.obj then layer.objects[#layer.objects + 1] = st.obj end
    elseif tool == "line" or tool == "rect" or tool == "circle" then
        local o = st.obj
        local v = self:_view()
        if layer and o and hypot(o.x[2] - o.x[1], o.y[2] - o.y[1]) * v.s >= 2 then
            layer.objects[#layer.objects + 1] = o
        else
            discard = true
            if o then
                local x0, y0, x1, y1 = self:_docBox(objectBBox(o), 2)
                self:_markDirty(x0, y0, x1, y1, true)
            end
        end
    elseif tool == "eraser" then
        discard = not st.erased
    elseif tool == "lasso" then
        self:_finishLasso(st)
    elseif tool == "sel" then
        self:_commitTransform(st)
    end
    if discard then app:discardLastEdit() end
    self:_flush(true)
    self:_scheduleAutoRefresh()
    if tool ~= "lasso" and tool ~= "hand" and not discard then self:_notifySoon() end
end

function Canvas:_finishLasso(st)
    local app = self.app
    local v = self:_view()
    local layer = app.layers[st.layer]
    local n = #st.px
    local xs, ys = {}, {}
    local bx0, by0, bx1, by1 = huge, huge, -huge, -huge
    for i = 1, n do
        xs[i], ys[i] = (st.px[i] - v.ox) / v.s, (st.py[i] - v.oy) / v.s
        bx0, by0 = min(bx0, st.px[i]), min(by0, st.py[i])
        bx1, by1 = max(bx1, st.px[i]), max(by1, st.py[i])
    end
    local selected = {}
    if layer and n >= 3 and (bx1 - bx0) > safeScale(8) and (by1 - by0) > safeScale(8) then
        for _index, o in ipairs(layer.objects) do
            local samples = {}
            if o.kind == "rect" then
                local x0, y0, x1, y1 = o.x[1], o.y[1], o.x[2], o.y[2]
                samples = { { x0, y0 }, { x1, y0 }, { x1, y1 }, { x0, y1 } }
            elseif o.kind == "circle" then
                local r = hypot(o.x[2] - o.x[1], o.y[2] - o.y[1])
                samples = { { o.x[1], o.y[1] }, { o.x[1] + r, o.y[1] }, { o.x[1] - r, o.y[1] },
                    { o.x[1], o.y[1] + r }, { o.x[1], o.y[1] - r } }
            elseif o.kind == "line" then
                samples = { { o.x[1], o.y[1] }, { (o.x[1] + o.x[2]) / 2, (o.y[1] + o.y[2]) / 2 }, { o.x[2], o.y[2] } }
            else
                for i = 1, o.n do samples[i] = { o.x[i], o.y[i] } end
            end
            local inside = 0
            for _i, pt in ipairs(samples) do
                if pointInPoly(pt[1], pt[2], xs, ys, n) then inside = inside + 1 end
            end
            if #samples > 0 and inside / #samples >= 0.5 then selected[#selected + 1] = o end
        end
    elseif layer and n >= 1 and (bx1 - bx0) <= safeScale(14) and (by1 - by0) <= safeScale(14) then
        -- A tap (no loop) selects the object under the pen.
        local px, py = xs[1], ys[1]
        local reach = safeScale(16) / v.s
        local best, best_d
        for _index, o in ipairs(layer.objects) do
            local d = distToObject(o, px, py)
            if d <= reach and (not best_d or d < best_d) then best, best_d = o, d end
        end
        if best then selected[1] = best end
    end
    app.sel = #selected > 0 and app:makeSelection(st.layer, selected) or nil
    self:_markDirty(bx0 - safeScale(50), by0 - safeScale(50), bx1 + safeScale(50), by1 + safeScale(50), true)
    if app.sel then
        local x0, y0, x1, y1 = self:_docBox(app.sel.bbox, safeScale(50))
        self:_markDirty(x0, y0, x1, y1, true)
    end
end

function Canvas:_commitTransform(st)
    local app = self.app
    local sel = app.sel
    if not sel then return end
    if not st.moved then
        -- A tap on the selection opens its action menu.
        if app.on_selection_tap then app.on_selection_tap() end
        return
    end
    local layer = app.layers[sel.layer]
    local preview = sel.preview
    sel.preview, sel.pbbox = nil, nil
    if not layer or not preview then return end
    app:pushHistory()
    local new_objs = {}
    for i, o in ipairs(layer.objects) do
        local replaced = preview[o]
        if replaced then
            layer.objects[i] = replaced
            new_objs[#new_objs + 1] = replaced
        end
    end
    app.sel = app:makeSelection(sel.layer, new_objs)
    local dirty = unionBox(sel.bbox, app.sel.bbox)
    local x0, y0, x1, y1 = self:_docBox(dirty, safeScale(50))
    self:_markDirty(x0, y0, x1, y1, true)
end

----------------------------------------------------------------
-- Canvas: gesture entry points
----------------------------------------------------------------

function Canvas:onPaint(_arg, ev)
    if self._raw_stylus_active then return true end
    if self:_rejectFinger(ev) then return true end
    return self:_continue(ev)
end

function Canvas:onPaintTouch(_arg, ev)
    if self._raw_stylus_active then return true end
    if self:_rejectFinger(ev) then return true end
    return self:_begin(ev)
end

function Canvas:onPaintTap(_arg, ev)
    if self._raw_stylus_active or self._ignore_gesture_after_stylus then
        self._raw_stylus_active = nil
        self._ignore_gesture_after_stylus = nil
        return true
    end
    if self:_rejectFinger(ev) then return true end
    local app = self.app
    if app.stroke or app.fill_gesture then
        -- The press already opened the stroke; the tap completes that contact.
        local st = app.stroke
        if st and (st.tool == "pen" or st.tool == "eraser") then self._tap_commit = true end
        self:_commit()
        if app.notifyChange then app:notifyChange() end
        return true
    end
    -- A tap without a preceding touch (e.g. synthesized): behave like touch + release.
    if self:_begin(ev) then
        self:_commit()
        if app.notifyChange then app:notifyChange() end
    end
    return true
end

function Canvas:onPaintRelease(_arg, ev)
    if self._raw_stylus_active then
        self:finishStylus(self._stylus_tracking_id)
        return true
    end
    local app = self.app
    if not app.stroke and not app.fill_gesture and self:_rejectFinger(ev) then return true end
    if ev and app.stroke then self:_continue(ev, true) end
    self:_commit()
    if app.notifyChange then app:notifyChange() end
    return true
end

function Canvas:_twoFingerEdit(redo)
    local app = self.app
    if app.two_finger_gestures == false or self._raw_stylus_active then return true end
    self:_cancelFingerStroke()
    local changed
    if redo then changed = app:redo() else changed = app:undo() end
    if changed then
        self:refreshFast()
        if app.notifyChange then app:notifyChange() end
    end
    return true
end
function Canvas:onPaintTwoTap() return self:_twoFingerEdit(false) end
function Canvas:onPaintTwoSwipe() return self:_twoFingerEdit(true) end

function Canvas:onPaintPinch(_arg, ev)
    if self._raw_stylus_active then return true end
    self:_cancelFingerStroke()
    local pos = ev and ev.pos
    self:zoomBy(1 / 1.4, pos and pos.x, pos and pos.y)
    return true
end
function Canvas:onPaintSpread(_arg, ev)
    if self._raw_stylus_active then return true end
    self:_cancelFingerStroke()
    local pos = ev and ev.pos
    self:zoomBy(1.4, pos and pos.x, pos and pos.y)
    return true
end

----------------------------------------------------------------
-- Document model
----------------------------------------------------------------

local function newLayer(name, with_bg)
    return { name = name, objects = {}, hidden = false, bg = with_bg and { 255, 255, 255 } or nil }
end
local function copyList(list)
    local copy = {}
    for i = 1, #list do copy[i] = list[i] end
    return copy
end

local function u16(n) n = floor(n); return string.char(n % 256, floor(n / 256) % 256) end
local function u32(n)
    n = floor(n)
    return string.char(n % 256, floor(n / 256) % 256, floor(n / 65536) % 256, floor(n / 16777216) % 256)
end

function Draw:new()
    return setmetatable({
        layers = {}, active = 1,
        color = { 0, 0, 0 }, tool = "pen", brush = "pen", brush_size = 3,
        pressure_enabled = true,
        touch_policy = "auto",          -- "auto" | "pen" | "both"
        side_button_action = "marker",  -- "marker" | "eraser" | "off"
        eraser_end_action = "erase",    -- "erase" | "off"
        pressure_curve = "linear",      -- "off" | "soft" | "linear" | "firm"
        two_finger_gestures = true,
        auto_refresh = 0,               -- seconds of idle time before a true-color full refresh; 0 = off
        zoom = 1, pan_x = 0, pan_y = 0,
        history = {}, redo_stack = {},
    }, self)
end

function Draw:ensure()
    self.color = self.color or { 0, 0, 0 }
    if #self.layers == 0 then
        local size
        if Screen.getSize then
            local ok, result = pcall(Screen.getSize, Screen)
            if ok and type(result) == "table" then size = result end
        end
        local screen_w = safeDimension(size and size.w, screenMetric("getWidth", "width", 600))
        local screen_h = safeDimension(size and size.h, screenMetric("getHeight", "height", 800))
        -- One document unit is one screen pixel at 100 % zoom.
        self.width = clamp(screen_w - safeScale(24), 64, MAX_DOC)
        self.height = clamp(screen_h - safeScale(180), 64, MAX_DOC)
        self.layers = { newLayer(_("Layer 1"), true) }
        self.active = 1
    end
    self.history = self.history or {}
    self.redo_stack = self.redo_stack or {}
    self.zoom, self.pan_x, self.pan_y = self.zoom or 1, self.pan_x or 0, self.pan_y or 0
end

function Draw:layer() return self.layers[self.active] end

-- The page background lives on the first layer that owns a background color.
function Draw:paperLayer()
    self:ensure()
    for _index, layer in ipairs(self.layers) do
        if layer.bg then return layer end
    end
    return self.layers[1]
end
function Draw:getPaper()
    local layer = self:paperLayer()
    return layer and layer.paper or "blank"
end
function Draw:setPaper(kind)
    local layer = self:paperLayer()
    if not layer or not PAPER_INDEX[kind] then return false end
    layer.paper = kind ~= "blank" and kind or nil
    self.dirty = true
    return true
end

function Draw:setRGBColor(r, g, b)
    r, g, b = tonumber(r), tonumber(g), tonumber(b)
    if not r or not g or not b or r < 0 or g < 0 or b < 0 or r > 255 or g > 255 or b > 255 then
        return nil, _("RGB channels must be between 0 and 255.")
    end
    self.color = { floor(r + 0.5), floor(g + 0.5), floor(b + 0.5) }
    return self.color
end

function Draw.nextSize(current, delta)
    local sizes = Draw.brushSizes
    if delta > 0 then
        for _index, size in ipairs(sizes) do if size > current then return size end end
        return min(MAX_SIZE, current + 1)
    end
    for index = #sizes, 1, -1 do
        if sizes[index] < current then return sizes[index] end
    end
    return 1
end

function Draw:setBrushSize(size)
    self.brush_size = clamp(floor((tonumber(size) or 1) + 0.5), 1, MAX_SIZE)
    return self.brush_size
end

function Draw:cycleBrush(delta)
    return self:setBrushSize(Draw.nextSize(self.brush_size or 1, delta or 1))
end

function Draw:addLayer()
    if #self.layers >= MAX_LAYERS then return false end
    self.layers[#self.layers + 1] = newLayer(_("Layer ") .. tostring(#self.layers + 1), false)
    self.active = #self.layers
    self.sel = nil
    return true
end

function Draw:nextLayer()
    if #self.layers > 0 then self.active = self.active % #self.layers + 1; self.sel = nil end
end

function Draw:fingerIgnored()
    return self.touch_policy == "pen" or (self.touch_policy == "auto" and self.pen_seen == true)
end

function Draw:setTool(tool)
    if not TOOL_LABELS[tool] then return false end
    if tool ~= "lasso" then self.sel = nil end
    self.tool = tool
    return true
end

function Draw:layerIsEmpty(index)
    local layer = self.layers[index]
    if not layer then return true end
    local bg = layer.bg
    local blank = bg == nil or (index == 1 and bg[1] == 255 and bg[2] == 255 and bg[3] == 255)
    return #layer.objects == 0 and blank
end

function Draw:clear()
    local layer = self:layer()
    if not layer then return false end
    self:pushHistory()
    layer.objects = {}
    layer.bg = self.active == 1 and { 255, 255, 255 } or nil
    self.sel = nil
    return true
end

----------------------------------------------------------------
-- Selection operations
----------------------------------------------------------------

function Draw:makeSelection(layer_index, objs)
    local set, box = {}, nil
    for _index, o in ipairs(objs) do
        set[o] = true
        box = unionBox(box, objectBBox(o))
    end
    return { layer = layer_index, objs = objs, set = set, bbox = box or { 0, 0, 0, 0 } }
end

function Draw:_selectionLayer()
    local sel = self.sel
    return sel and self.layers[sel.layer] or nil, sel
end

function Draw:deleteSelection()
    local layer, sel = self:_selectionLayer()
    if not layer then return false end
    self:pushHistory()
    local keep = {}
    for _index, o in ipairs(layer.objects) do
        if not sel.set[o] then keep[#keep + 1] = o end
    end
    layer.objects = keep
    self.sel = nil
    return true
end

function Draw:duplicateSelection()
    local layer, sel = self:_selectionLayer()
    if not layer then return false end
    self:pushHistory()
    local copies = {}
    local offset = { dx = 20, dy = 20, s = 1, rot = 0 }
    for _index, o in ipairs(sel.objs) do
        local copy = transformObject(o, offset, 0, 0)
        for i = 1, copy.n do
            copy.x[i] = clamp(copy.x[i], 0, self.width)
            copy.y[i] = clamp(copy.y[i], 0, self.height)
        end
        copy.bb = nil
        layer.objects[#layer.objects + 1] = copy
        copies[#copies + 1] = copy
    end
    self.sel = self:makeSelection(sel.layer, copies)
    return true
end

-- Applies the current color and/or stroke width to every selected object.
function Draw:restyleSelection(color, size)
    local layer, sel = self:_selectionLayer()
    if not layer then return false end
    self:pushHistory()
    local new_objs = {}
    for i, o in ipairs(layer.objects) do
        if sel.set[o] then
            local c = copyObject(o)
            if color then c.color = copyColor(color) end
            if size then c.size = size; c.bb = nil end
            layer.objects[i] = c
            new_objs[#new_objs + 1] = c
        end
    end
    self.sel = self:makeSelection(sel.layer, new_objs)
    return true
end

function Draw:reorderSelection(to_front)
    local layer, sel = self:_selectionLayer()
    if not layer then return false end
    self:pushHistory()
    local chosen, others = {}, {}
    for _index, o in ipairs(layer.objects) do
        if sel.set[o] then chosen[#chosen + 1] = o else others[#others + 1] = o end
    end
    local result = {}
    if to_front then
        for _i, o in ipairs(others) do result[#result + 1] = o end
        for _i, o in ipairs(chosen) do result[#result + 1] = o end
    else
        for _i, o in ipairs(chosen) do result[#result + 1] = o end
        for _i, o in ipairs(others) do result[#result + 1] = o end
    end
    layer.objects = result
    return true
end

-- Tap with the fill tool: fills the topmost closed shape under the point, or
-- the whole layer background if there is none. Returns true when anything changed.
function Draw:fillAt(x, y, color)
    local layer = self:layer()
    if not layer then return false end
    for i = #layer.objects, 1, -1 do
        local o = layer.objects[i]
        if isClosedShape(o) and insideObject(o, x, y) then
            if sameColor(o.fill, color) then return false end
            local c = copyObject(o)
            c.fill = copyColor(color)
            layer.objects[i] = c
            return true
        end
    end
    if sameColor(layer.bg, color) then return false end
    layer.bg = copyColor(color)
    return true
end

----------------------------------------------------------------
-- Undo/redo (snapshot of the active layer's object list)
----------------------------------------------------------------

function Draw:pushHistory()
    self:ensure()
    local layer = self:layer()
    if not layer then return false end
    self.history[#self.history + 1] = {
        layer = self.active, objects = copyList(layer.objects), bg = layer.bg,
        prev_redo = self.redo_stack, prev_dirty = self.dirty,
    }
    while #self.history > MAX_HISTORY do table.remove(self.history, 1) end
    self.redo_stack = {}
    self.dirty = true
    return true
end

local function restoreEntry(self, entry)
    local layer = self.layers[entry.layer]
    if not layer then return nil end
    local current = { layer = entry.layer, objects = copyList(layer.objects), bg = layer.bg }
    layer.objects = copyList(entry.objects)
    layer.bg = entry.bg
    self.sel = nil
    return current
end

function Draw:undo()
    self:ensure()
    local entry = table.remove(self.history)
    if not entry then return false end
    local current = restoreEntry(self, entry)
    if not current then return false end
    self.redo_stack[#self.redo_stack + 1] = current
    self.dirty = true
    return true
end

function Draw:redo()
    self:ensure()
    local entry = table.remove(self.redo_stack)
    if not entry then return false end
    local current = restoreEntry(self, entry)
    if not current then return false end
    self.history[#self.history + 1] = current
    self.dirty = true
    return true
end

-- Removes the newest edit as if it never happened (no redo entry).
function Draw:discardLastEdit()
    self:ensure()
    local entry = table.remove(self.history)
    if not entry then return false end
    if not restoreEntry(self, entry) then return false end
    self.redo_stack = entry.prev_redo or {}
    if entry.prev_dirty ~= nil then self.dirty = entry.prev_dirty end
    return true
end

function Draw:notifyChange()
    if type(self.on_change) == "function" then pcall(self.on_change) end
end

function Draw:removeLayer()
    self:ensure()
    if #self.layers <= 1 then return false end
    local removed_paper = self.layers[self.active] and self.layers[self.active].paper
    table.remove(self.layers, self.active)
    self.active = clamp(self.active, 1, #self.layers)
    if self.layers[1] and not self.layers[1].bg then
        self.layers[1].bg = { 255, 255, 255 }
        self.layers[1].paper = removed_paper
    end
    self.history, self.redo_stack, self.sel = {}, {}, nil
    self.dirty = true
    return true
end

function Draw:newDrawing()
    local keep_paper = self.layers and #self.layers > 0 and self:getPaper() or nil
    self.layers, self.history, self.redo_stack = {}, {}, {}
    self.active, self.stroke, self.sel, self.dirty = 1, nil, nil, false
    self.zoom, self.pan_x, self.pan_y = 1, 0, 0
    self.current_path = nil
    self:ensure()
    if keep_paper then self:setPaper(keep_paper); self.dirty = false end
    return true
end

function Draw:statusText()
    local label = TOOL_LABELS[self.tool] or _("Pen")
    local color = self.color or palette[2]
    local color_name
    for index, entry in ipairs(palette) do
        if sameColor(entry, color) then color_name = COLOR_NAMES[index] end
    end
    color_name = color_name or string.format("#%02X%02X%02X", color[1], color[2], color[3])
    return string.format("%s · %d px · %s · %s", label, self.brush_size or 1, color_name,
        string.format(_("Layer %d/%d"), self.active or 1, #self.layers))
end

----------------------------------------------------------------
-- Project files (ADRAW3: compact vector format)
----------------------------------------------------------------

function Draw:projectBytes()
    self:ensure()
    local c = self.color
    local out = { MAGIC, u16(self.width), u16(self.height),
        string.char(#self.layers, self.active, c[1], c[2], c[3]) }
    for _index, layer in ipairs(self.layers) do
        local bg = layer.bg
        out[#out + 1] = string.char((layer.hidden and 1 or 0) + (bg and 2 or 0) + (PAPER_INDEX[layer.paper or "blank"] or 0) * 4)
        if bg then out[#out + 1] = string.char(bg[1], bg[2], bg[3]) end
        out[#out + 1] = u32(#layer.objects)
        for _i, o in ipairs(layer.objects) do
            local fill = o.fill
            out[#out + 1] = string.char(KIND_ID[o.kind] or 1, BRUSH_INDEX[o.brush] or 1,
                clamp(floor(o.size * 4 + 0.5), 1, 255), o.color[1], o.color[2], o.color[3], fill and 1 or 0)
            if fill then out[#out + 1] = string.char(fill[1], fill[2], fill[3]) end
            out[#out + 1] = u16(o.n)
            local chunk = {}
            for i = 1, o.n do
                chunk[i] = u16(clamp(floor(o.x[i] * 8 + 0.5), 0, 65535)) .. u16(clamp(floor(o.y[i] * 8 + 0.5), 0, 65535))
                    .. string.char(clamp(floor((o.p[i] or 1) * 255 + 0.5), 0, 255))
            end
            out[#out + 1] = table.concat(chunk)
        end
    end
    return table.concat(out)
end

function Draw:loadBytes(bytes)
    if type(bytes) ~= "string" or #bytes < #MAGIC + 10 then return nil, _('Not an AppDock Draw project.') end
    local head = bytes:sub(1, #MAGIC)
    if head ~= MAGIC then
        if head == "ADRAW1\0" or head == "ADRAW2\0" then
            return nil, _('This drawing uses the old pixel format and cannot be opened.')
        end
        return nil, _('Not an AppDock Draw project.')
    end
    local damaged = _('The drawing file is damaged or too large.')
    local len, pos, bad = #bytes, #MAGIC + 1, false
    local function u8()
        local v = bytes:byte(pos)
        if not v then bad = true; return 0 end
        pos = pos + 1
        return v
    end
    local function r16() local a = u8(); local b = u8(); return a + b * 256 end
    local function r32() local a = r16(); local b = r16(); return a + b * 65536 end
    local w, h = r16(), r16()
    local count, active = u8(), u8()
    local cr, cg, cb = u8(), u8(), u8()
    if bad or w < 1 or h < 1 or w > MAX_DOC or h > MAX_DOC or count < 1 or count > MAX_LAYERS
        or active < 1 or active > count then
        return nil, damaged
    end
    local layers = {}
    for n = 1, count do
        local flags = u8()
        local layer = { name = _('Layer ') .. n, objects = {}, hidden = flags % 2 == 1 }
        local paper = PAPERS[floor(flags / 4) % 8 + 1]
        if paper and paper ~= "blank" then layer.paper = paper end
        if floor(flags / 2) % 2 == 1 then
            local r, g, b = u8(), u8(), u8()
            layer.bg = { r, g, b }
        end
        local nobj = r32()
        if bad or nobj > len then return nil, damaged end
        for k = 1, nobj do
            local kind = KIND_NAME[u8()]
            local brush_index, size4 = u8(), u8()
            local r, g, b = u8(), u8(), u8()
            local has_fill = u8()
            local fill
            if has_fill == 1 then
                local fr, fg, fb = u8(), u8(), u8()
                fill = { fr, fg, fb }
            end
            local np = r16()
            if bad or not kind or np < 1 or (kind ~= "path" and np ~= 2)
                or brush_index < 1 or brush_index > #BRUSH_ORDER or pos + np * 5 - 1 > len then
                return nil, damaged
            end
            local o = newObject(kind, BRUSH_ORDER[brush_index], max(0.25, size4 / 4), { r, g, b })
            o.fill = fill
            for i = 1, np do
                local px, py, pp = r16(), r16(), u8()
                addPoint(o, px / 8, py / 8, pp / 255)
            end
            layer.objects[#layer.objects + 1] = o
        end
        layers[n] = layer
    end
    if bad then return nil, damaged end
    self.width, self.height, self.layers, self.active = w, h, layers, active
    self.color = { cr, cg, cb }
    self.history, self.redo_stack, self.sel, self.stroke = {}, {}, nil, nil
    self.zoom, self.pan_x, self.pan_y = 1, 0, 0
    self.dirty = false
    return true
end

local function dataDir()
    local dir = "/tmp"
    local ok, ds = pcall(require, "datastorage")
    if ok and ds.getDataDir then dir = ds:getDataDir() end
    return dir
end

function Draw:projectDirectory() return dataDir() .. "/appdock/draw" end

function Draw:saveProject()
    self:ensure()
    local dir = self:projectDirectory()
    os.execute("mkdir -p " .. string.format("%q", dir))
    save_sequence = save_sequence + 1
    local path = dir .. "/drawing-" .. os.date("%Y%m%d-%H%M%S") .. "-" .. save_sequence .. ".adraw"
    local f, err = io.open(path, "wb")
    if not f then return nil, err end
    f:write(self:projectBytes())
    f:close()
    return path
end

function Draw:loadLatestProject()
    local dir = self:projectDirectory()
    local pipe = io.popen("ls -1t " .. string.format("%q", dir) .. "/*.adraw 2>/dev/null", "r")
    local path = pipe and pipe:read("*l")
    if pipe then pipe:close() end
    if not path then return nil, _('No saved AppDock Draw project was found.') end
    local f, err = io.open(path, "rb")
    if not f then return nil, err end
    local bytes = f:read("*a")
    f:close()
    local ok_load, load_error = self:loadBytes(bytes)
    if not ok_load then return nil, load_error end
    return path
end

function Draw:loadPath(path)
    if type(path) ~= "string" or #path > 4096 or not path:lower():match("%.adraw$") then
        return nil, _('Choose an .adraw project file.')
    end
    local f, err = io.open(path, "rb")
    if not f then return nil, err end
    local size = f:seek("end")
    if not size or size > 32 * 1024 * 1024 then f:close(); return nil, _('The drawing file is too large.') end
    f:seek("set", 0)
    local bytes = f:read("*a")
    f:close()
    return self:loadBytes(bytes)
end

function Draw:listProjects(limit)
    local dir = self:projectDirectory()
    local pipe = io.popen("ls -1t " .. string.format("%q", dir) .. "/*.adraw 2>/dev/null", "r")
    local list = {}
    if pipe then
        for path in pipe:lines() do
            local y, mo, d, hh, mi = path:match("drawing%-(%d%d%d%d)(%d%d)(%d%d)%-(%d%d)(%d%d)%d%d")
            list[#list + 1] = {
                path = path,
                label = y and string.format("%s-%s-%s  %s:%s", y, mo, d, hh, mi) or (path:match("([^/]+)$") or path),
            }
            if #list >= (limit or 8) then break end
        end
        pipe:close()
    end
    return list
end

function Draw:saveCurrent()
    self:ensure()
    if self.current_path then
        local file = io.open(self.current_path, "wb")
        if file then
            file:write(self:projectBytes())
            file:close()
            self.dirty = false
            return self.current_path, true
        end
    end
    return self:saveCopy()
end

function Draw:saveCopy()
    local path, err = self:saveProject()
    if not path then return nil, err end
    self.current_path, self.dirty = path, false
    return path, false
end

function Draw:openProject(path)
    local ok, err = self:loadPath(path)
    if not ok then return nil, err end
    self.current_path, self.dirty = path, false
    return path
end

-- Rasterizes the drawing in true colors at 1 unit = 1 pixel (RGB bytes).
function Draw:renderRGB()
    self:ensure()
    local w, h = self.width, self.height
    local buf = ffi.new("uint8_t[?]", w * h * 3)
    ffi.fill(buf, w * h * 3, 255)
    renderDocument(self, memoryPainter(buf, w, h), { ox = 0, oy = 0, s = 1 }, false)
    return buf, w, h
end

-- Pure-Lua PNG writer (stored deflate blocks): last resort when no encoder is available.
local function writeRawPNG(path, buf, w, h)
    local ok_bit, bit = pcall(require, "bit")
    if not ok_bit then return false end
    local band, bxor, rshift = bit.band, bit.bxor, bit.rshift
    local tbl = {}
    for n = 0, 255 do
        local c = n
        for _k = 1, 8 do
            if band(c, 1) == 1 then c = bxor(0xEDB88320, rshift(c, 1)) else c = rshift(c, 1) end
        end
        tbl[n] = c
    end
    local function crcUpdate(c, ptr, len)
        for i = 0, len - 1 do c = bxor(tbl[band(bxor(c, ptr[i]), 255)], rshift(c, 8)) end
        return c
    end
    local function be32(n)
        return string.char(band(rshift(n, 24), 255), band(rshift(n, 16), 255), band(rshift(n, 8), 255), band(n, 255))
    end
    local row = w * 3 + 1
    local raw = ffi.new("uint8_t[?]", row * h)
    for y = 0, h - 1 do
        raw[y * row] = 0
        ffi.copy(raw + y * row + 1, buf + y * w * 3, w * 3)
    end
    local rawlen = row * h
    local a, b = 1, 0
    for i = 0, rawlen - 1 do
        a = (a + raw[i]) % 65521
        b = (b + a) % 65521
    end
    local blocks = ceil(rawlen / 65535)
    local plen = 2 + rawlen + blocks * 5 + 4
    local payload = ffi.new("uint8_t[?]", plen)
    payload[0], payload[1] = 0x78, 0x01
    local pos, off = 2, 0
    while off < rawlen do
        local n = min(65535, rawlen - off)
        payload[pos] = (off + n >= rawlen) and 1 or 0
        payload[pos + 1], payload[pos + 2] = n % 256, floor(n / 256)
        payload[pos + 3], payload[pos + 4] = (65535 - n) % 256, floor((65535 - n) / 256)
        ffi.copy(payload + pos + 5, raw + off, n)
        pos, off = pos + 5 + n, off + n
    end
    local adler = b * 65536 + a
    payload[pos], payload[pos + 1] = floor(adler / 16777216) % 256, floor(adler / 65536) % 256
    payload[pos + 2], payload[pos + 3] = floor(adler / 256) % 256, adler % 256
    local function chunk(f, kind, data, len, ptr)
        f:write(be32(len), kind)
        local c = 0xFFFFFFFF
        for i = 1, 4 do c = bxor(tbl[band(bxor(c, kind:byte(i)), 255)], rshift(c, 8)) end
        if ptr then
            f:write(ffi.string(ptr, len))
            c = crcUpdate(c, ptr, len)
        elseif data then
            f:write(data)
            for i = 1, #data do c = bxor(tbl[band(bxor(c, data:byte(i)), 255)], rshift(c, 8)) end
        end
        f:write(be32(bxor(c, 0xFFFFFFFF)))
    end
    local f = io.open(path, "wb")
    if not f then return false end
    f:write("\137PNG\r\n\26\n")
    chunk(f, "IHDR", be32(w) .. be32(h) .. string.char(8, 2, 0, 0, 0), 13)
    chunk(f, "IDAT", nil, plen, payload)
    chunk(f, "IEND", "", 0)
    f:close()
    return true
end

local EXPORT_DIR = "/mnt/onboard/Images"

local function fileSize(path)
    local f = io.open(path, "rb")
    if not f then return 0 end
    local size = f:seek("end") or 0
    f:close()
    return size
end

local function writableDir(dir)
    os.execute("mkdir -p " .. string.format("%q", dir) .. " 2>/dev/null")
    local probe = dir .. "/.appdock_write_test"
    local f = io.open(probe, "wb")
    if not f then return false end
    f:close()
    os.remove(probe)
    return true
end

-- Exports the drawing as an image into /mnt/onboard/Images (JPEG, PNG as fallback).
function Draw:exportImage()
    self:ensure()
    local dir = EXPORT_DIR
    if not writableDir(dir) then
        dir = dataDir() .. "/appdock/draw"
        if not writableDir(dir) then return nil, _("The export folder is not writable.") end
    end
    save_sequence = save_sequence + 1
    local stem = dir .. "/drawing-" .. os.date("%Y%m%d-%H%M%S") .. "-" .. save_sequence
    local buf, w, h = self:renderRGB()

    -- 1) KOReader's own encoders.
    local ok_bb, bb = pcall(function()
        local b = Blitbuffer.new(w, h, Blitbuffer.TYPE_BBRGB24)
        local base = ffi.cast("uint8_t*", b.data)
        for y = 0, h - 1 do ffi.copy(base + y * b.stride, buf + y * w * 3, w * 3) end
        return b
    end)
    if ok_bb and bb then
        local jpeg = stem .. ".jpg"
        if bb.writeToFile then
            pcall(bb.writeToFile, bb, jpeg, "jpg", 92)
            if fileSize(jpeg) > 0 then pcall(bb.free, bb); return jpeg end
            os.remove(jpeg)
        end
        local png = stem .. ".png"
        if bb.writePNG then
            pcall(bb.writePNG, bb, png)
            if fileSize(png) > 0 then pcall(bb.free, bb); return png end
            os.remove(png)
        end
        pcall(bb.free, bb)
    end

    -- 2) ffmpeg, when the device has one.
    local ffmpeg
    local pipe = io.popen("command -v ffmpeg 2>/dev/null", "r")
    ffmpeg = pipe and pipe:read("*l")
    if pipe then pipe:close() end
    if not ffmpeg or ffmpeg == "" then
        local bundled = dataDir() .. "/appdock/tools/ffmpeg"
        local probe = io.open(bundled, "rb")
        if probe then probe:close(); ffmpeg = bundled else ffmpeg = nil end
    end
    if ffmpeg then
        local ppm, jpeg = stem .. ".ppm", stem .. ".jpg"
        local f = io.open(ppm, "wb")
        if f then
            f:write("P6\n", w, " ", h, "\n255\n")
            f:write(ffi.string(buf, w * h * 3))
            f:close()
            local ok = os.execute(string.format("%q -y -v error -i %q -q:v 2 %q >/dev/null 2>&1", ffmpeg, ppm, jpeg))
            os.remove(ppm)
            if (ok == 0 or ok == true) and fileSize(jpeg) > 0 then return jpeg end
            os.remove(jpeg)
        end
    end

    -- 3) Built-in PNG writer.
    local png = stem .. ".png"
    local ok_png, wrote = pcall(writeRawPNG, png, buf, w, h)
    if ok_png and wrote and fileSize(png) > 0 then return png end
    os.remove(png)
    return nil, _("The image could not be exported.")
end
Draw.exportJPEG = Draw.exportImage

----------------------------------------------------------------
-- Pane
----------------------------------------------------------------

local TOOL_ORDER = { "pen", "eraser", "lasso", "line", "rect", "circle", "fill", "hand" }

local function fileName(path)
    return tostring(path or ""):match("([^/]+)$") or tostring(path or "")
end

function Draw:buildPane(instance, context)
    self:ensure()
    self.stroke = nil
    context = type(context) == "table" and context or {}
    local fallback_size = {}
    if type(Screen.getSize) == "function" then
        local size_ok, size = pcall(Screen.getSize, Screen)
        if size_ok and type(size) == "table" then fallback_size = size end
    end
    local dim = type(context.dimen) == "table" and context.dimen or fallback_size
    local w = safeDimension(dim.w, self.width + safeScale(24), 4096)
    local h = safeDimension(dim.h, self.height + safeScale(180), 4096)

    local margin = safeScale(6)
    local gap = safeScale(4)
    local tool_bar_h = safeScale(46)
    local option_bar_h = safeScale(40)
    local action_bar_h = safeScale(44)
    local frame = max(2, safeScale(2))

    -- The canvas viewport fills the free area; the page sits centered inside it
    -- and is fitted at 100 % zoom, so there is room to zoom out and pan.
    local area_y = tool_bar_h + option_bar_h + margin * 2
    local area_w = max(safeScale(60), w - margin * 2)
    local area_h = max(safeScale(60), h - area_y - action_bar_h - margin)
    local canvas_w = max(1, area_w - 2 * frame)
    local canvas_h = max(1, area_h - 2 * frame)
    local fit = max(0.05, min(canvas_w / self.width, canvas_h / self.height))
    local canvas_x = margin + frame
    local canvas_y = area_y + frame

    local pane = OverlapGroup:new{ dimen = Geom:new{ w = w, h = h }, allow_mirroring = false }
    local function add(widget, x, y)
        widget.overlap_offset = { x, y }
        pane[#pane + 1] = widget
        return widget
    end
    add(Backdrop:new{ width = w, height = h }, 0, 0)

    local pane_x, pane_y, painted = 0, 0, false
    local suspended = false   -- true while the style dialog covers the chrome
    pane.paintTo = function(group, bb, x, y)
        pane_x, pane_y, painted = x, y, true
        return OverlapGroup.paintTo(group, bb, x, y)
    end
    local function rebuild()
        if context.requestRebuild then context.requestRebuild("ui") end
    end
    local function paintDirect(widget)
        if not painted or suspended then return end
        local bb = Screen.bb
        local offset = widget and widget.overlap_offset
        if not bb or not offset then return end
        local x, y = pane_x + offset[1], pane_y + offset[2]
        widget:paintTo(bb, x, y)
        if UIManager.setDirty then
            UIManager:setDirty(nil, "fast", Geom:new{ x = x, y = y, w = widget.dimen.w, h = widget.dimen.h })
        end
    end
    local function notify(message)
        if context.notify then context.notify{ title = _("Draw"), message = tostring(message) } end
    end

    local function showMenu(title, rows)
        local dialog
        local buttons = {}
        for _index, row in ipairs(rows) do
            buttons[#buttons + 1] = { {
                text = row.text,
                callback = function()
                    UIManager:close(dialog)
                    if row.run then UIManager:nextTick(row.run) end
                end,
            } }
        end
        buttons[#buttons + 1] = { { text = _("Close"), callback = function() UIManager:close(dialog) end } }
        dialog = AppDockDialogs.ButtonDialog:new{ title = title, buttons = buttons, rows_per_page = { 5, 6, 7 } }
        UIManager:show(dialog)
    end
    local function confirm(text, ok_text, action)
        UIManager:show(AppDockDialogs.ConfirmBox:new{ text = text, ok_text = ok_text, ok_callback = action })
    end
    local function guardUnsaved(action)
        if self.dirty then
            confirm(_("This drawing has unsaved changes. Discard them?"), _("Discard"), action)
        else
            action()
        end
    end

    local canvas
    local tool_buttons, swatches = {}, {}
    local style_chip, zoom_chip, undo_button, redo_button, status, finger_button

    local function statusString()
        local text = string.format("%s · %s · %d px · %d%%", TOOL_LABELS[self.tool] or _("Pen"),
            (BRUSH[self.brush] or BRUSH.pen).label, self.brush_size or 1, floor((self.zoom or 1) * 100 + 0.5))
        if self.dirty then text = text .. " · " .. _("unsaved") end
        if self:fingerIgnored() then text = text .. " · " .. _("pen only") end
        return text
    end
    local function styleText()
        return string.format("%s · %d px", (BRUSH[self.brush] or BRUSH.pen).label, self.brush_size or 1)
    end
    local function refreshTools()
        for tool, button in pairs(tool_buttons) do
            button:setActive(self.tool == tool)
            paintDirect(button)
        end
    end
    local function refreshColors()
        for index, swatch in ipairs(swatches) do
            swatch:setActive(sameColor(self.color, palette[index]))
            paintDirect(swatch)
        end
    end
    local function refreshStyle()
        if not style_chip then return end
        style_chip.color = self.color
        style_chip:setText(styleText())
        paintDirect(style_chip)
    end
    local function refreshZoom()
        if zoom_chip then
            zoom_chip:setText(string.format("%d%%", floor((self.zoom or 1) * 100 + 0.5)))
            paintDirect(zoom_chip)
        end
    end
    local function refreshHistory()
        if undo_button then undo_button:setDisabled(#self.history == 0); paintDirect(undo_button) end
        if redo_button then redo_button:setDisabled(#self.redo_stack == 0); paintDirect(redo_button) end
    end
    local function refreshStatus()
        if status then status:setText(statusString()); paintDirect(status) end
        if finger_button then
            local want = not self:fingerIgnored()
            if finger_button.active ~= want then
                finger_button:setActive(want)
                paintDirect(finger_button)
            end
        end
    end
    self.on_change = function()
        refreshHistory()
        refreshStatus()
    end
    self.on_view_change = function()
        refreshZoom()
        refreshStatus()
    end

    -- Actions -------------------------------------------------------------------
    local function afterPixelsChanged()
        if canvas then canvas:refreshFast() end
        refreshHistory()
        refreshStatus()
    end
    local function doSave()
        local path, overwritten = self:saveCurrent()
        if not path then
            notify(overwritten or _("The drawing could not be saved."))
        else
            notify((overwritten and _("Saved changes to ") or _("Saved as ")) .. fileName(path))
        end
        refreshStatus()
    end
    local function doOpen()
        local list = self:listProjects(8)
        if #list == 0 then notify(_("No saved drawings yet. Use Save first.")); return end
        local rows = {}
        for _index, item in ipairs(list) do
            local label = item.label
            if item.path == self.current_path then label = label .. "  " .. _("(open)") end
            rows[#rows + 1] = {
                text = label,
                run = function()
                    guardUnsaved(function()
                        local ok, err = self:openProject(item.path)
                        if ok then rebuild() else notify(err or _("The drawing could not be opened.")) end
                    end)
                end,
            }
        end
        showMenu(_("Open drawing"), rows)
    end
    local function openLayers()
        local rows = {}
        for index = #self.layers, 1, -1 do
            local layer = self.layers[index]
            rows[#rows + 1] = {
                text = string.format("%s %s%s%s", index == self.active and "[x]" or "[ ]",
                    string.format(_("Layer %d"), index), self:layerIsEmpty(index) and (" " .. _("(empty)")) or "",
                    layer.hidden and (" " .. _("(hidden)")) or ""),
                run = function() self.active = index; self.sel = nil; rebuild() end,
            }
        end
        local current = self:layer()
        rows[#rows + 1] = {
            text = current and current.hidden and _("Show current layer") or _("Hide current layer"),
            run = function()
                if current then current.hidden = not current.hidden end
                afterPixelsChanged()
                rebuild()
            end,
        }
        if #self.layers < MAX_LAYERS then
            rows[#rows + 1] = {
                text = string.format(_("New layer (%d/%d)"), #self.layers + 1, MAX_LAYERS),
                run = function() self:addLayer(); rebuild() end,
            }
        end
        if #self.layers > 1 then
            rows[#rows + 1] = {
                text = _("Delete current layer"),
                run = function()
                    local function remove() self:removeLayer(); rebuild() end
                    if not self:layerIsEmpty(self.active) then
                        confirm(_("Delete this layer and everything on it? Undo history will be cleared."), _("Delete"), remove)
                    else
                        remove()
                    end
                end,
            }
        end
        showMenu(_("Layers"), rows)
    end
    local function openStylus()
        local function nextOf(list, current)
            for index, value in ipairs(list) do
                if value == current then return list[index % #list + 1] end
            end
            return list[1]
        end
        local policy_labels = { auto = _("Auto"), pen = _("Pen only"), both = _("Finger and pen") }
        local side_labels = { marker = _("Marker"), eraser = _("Eraser"), off = _("Off") }
        local end_labels = { erase = _("Erase"), off = _("Off") }
        local curve_labels = { off = _("Off"), soft = _("Soft"), linear = _("Linear"), firm = _("Firm") }
        showMenu(_("Stylus & touch"), {
            { text = string.format(_("Touch input: %s"), policy_labels[self.touch_policy] or policy_labels.auto),
              run = function()
                  self.touch_policy = nextOf({ "auto", "pen", "both" }, self.touch_policy)
                  refreshStatus()
                  openStylus()
              end },
            { text = string.format(_("Pen side button: %s"), side_labels[self.side_button_action] or side_labels.marker),
              run = function()
                  self.side_button_action = nextOf({ "marker", "eraser", "off" }, self.side_button_action)
                  openStylus()
              end },
            { text = string.format(_("Pen eraser end: %s"), end_labels[self.eraser_end_action] or end_labels.erase),
              run = function()
                  self.eraser_end_action = nextOf({ "erase", "off" }, self.eraser_end_action)
                  openStylus()
              end },
            { text = string.format(_("Pressure curve: %s"), curve_labels[self.pressure_curve] or curve_labels.linear),
              run = function()
                  self.pressure_curve = nextOf({ "off", "soft", "linear", "firm" }, self.pressure_curve)
                  openStylus()
              end },
            { text = self.two_finger_gestures and _("Two-finger undo/redo: on") or _("Two-finger undo/redo: off"),
              run = function()
                  self.two_finger_gestures = not self.two_finger_gestures
                  openStylus()
              end },
        })
    end
    -- Closing a dialog leaves ghosts of it on the e-ink panel: repaint everything and
    -- flash the whole screen once (the canvas is drawn in true colors).
    local function afterDialogClosed()
        suspended = false
        UIManager:nextTick(function()
            refreshTools()
            refreshColors()
            refreshStyle()
            refreshStatus()
            if canvas then canvas.render_true = true end
            UIManager:setDirty("all", "full")
        end)
    end
    local function openStyleDialog()
        suspended = true
        local dialog
        dialog = StyleDialog:new{
            app = self,
            on_change = function()
                -- Picking a brush or color while the eraser/hand is active means "draw".
                if self.tool == "eraser" or self.tool == "hand" then self:setTool("pen") end
            end,
            on_close = afterDialogClosed,
        }
        UIManager:show(dialog, "ui", dialog.dimen)
    end
    local function openPaperDialog()
        suspended = true
        local dialog
        dialog = PaperDialog:new{ app = self, on_close = afterDialogClosed }
        UIManager:show(dialog, "ui", dialog.dimen)
    end
    local function toggleFinger()
        if self:fingerIgnored() then self.touch_policy = "both" else self.touch_policy = "pen" end
        refreshStatus()
    end
    local function openSelectionMenu()
        if not self.sel then return end
        local function run(fn)
            return function()
                if fn() then
                    if canvas then canvas:refreshFast() end
                    refreshHistory()
                    refreshStatus()
                end
            end
        end
        showMenu(_("Selection"), {
            { text = _("Duplicate"), run = run(function() return self:duplicateSelection() end) },
            { text = _("Apply current color"), run = run(function() return self:restyleSelection(self.color, nil) end) },
            { text = _("Apply current stroke width"), run = run(function() return self:restyleSelection(nil, self.brush_size) end) },
            { text = _("Bring to front"), run = run(function() return self:reorderSelection(true) end) },
            { text = _("Send to back"), run = run(function() return self:reorderSelection(false) end) },
            { text = _("Delete"), run = run(function() return self:deleteSelection() end) },
            { text = _("Deselect"), run = run(function() self.sel = nil; return true end) },
        })
    end
    self.on_selection_tap = openSelectionMenu

    local function openMore()
        local auto_labels = { [0] = _("off"), [3] = "3 s", [6] = "6 s", [10] = "10 s" }
        showMenu(_("Draw menu"), {
            { text = _("Layers…"), run = openLayers },
            { text = _("Page background…"), run = openPaperDialog },
            { text = self:fingerIgnored() and _("Finger drawing: off (tap to turn on)") or _("Finger drawing: on (tap to turn off)"),
              run = toggleFinger },
            { text = _("Stylus & touch…"), run = openStylus },
            { text = _("Full refresh (true colors)"), run = function() if canvas then canvas:fullRefresh() end end },
            { text = string.format(_("Auto full refresh after pause: %s"), auto_labels[self.auto_refresh or 0] or "off"),
              run = function()
                  local order = { [0] = 3, [3] = 6, [6] = 10, [10] = 0 }
                  self.auto_refresh = order[self.auto_refresh or 0] or 0
                  if canvas then canvas:_scheduleAutoRefresh() end
                  notify(string.format(_("Auto full refresh: %s"), auto_labels[self.auto_refresh] or "off"))
              end },
            { text = _("Reset zoom and position"), run = function() if canvas then canvas:resetView() end end },
            { text = _("New drawing"), run = function()
                guardUnsaved(function() self:newDrawing(); rebuild() end)
            end },
            { text = _("Save as new copy"), run = function()
                local path, err = self:saveCopy()
                notify(path and (_("Saved as ") .. fileName(path)) or err)
                refreshStatus()
            end },
            { text = _("Export image to Images folder"), run = function()
                local path, err = self:exportImage()
                notify(path and (_("Exported to ") .. path) or err)
            end },
            { text = self.pressure_enabled and _("Pen pressure: on (tap to turn off)") or _("Pen pressure: off (tap to turn on)"), run = function()
                self.pressure_enabled = not self.pressure_enabled
                notify(self.pressure_enabled and _("Pen pressure is on.") or _("Pen pressure is off."))
            end },
            { text = _("Clear current layer"), run = function()
                confirm(_("Clear the current layer? You can still undo this."), _("Clear"), function()
                    if self:clear() then afterPixelsChanged() end
                end)
            end },
        })
    end

    -- Tool strip ------------------------------------------------------------------
    local slots = #TOOL_ORDER + 2
    local strip_width = w - margin * 2
    local button_w = floor((strip_width - gap * (slots - 1)) / slots)
    if button_w < safeScale(20) and slots > 1 then
        gap = max(1, floor((strip_width - safeScale(20) * slots) / (slots - 1)))
        button_w = max(1, floor((strip_width - gap * (slots - 1)) / slots))
    end
    local button_h = tool_bar_h - gap
    for index, tool in ipairs(TOOL_ORDER) do
        tool_buttons[tool] = add(ToolButton:new{
            symbol = tool, label = TOOL_LABELS[tool], active = self.tool == tool,
            width = button_w, height = button_h,
            callback = function()
                local had_selection = self.sel ~= nil
                self:setTool(tool)
                refreshTools()
                refreshStatus()
                if had_selection and canvas then canvas:refreshFast() end
            end,
        }, margin + (index - 1) * (button_w + gap), margin)
    end
    undo_button = add(ToolButton:new{
        symbol = "undo", label = _("Undo"), width = button_w, height = button_h,
        disabled = #self.history == 0,
        callback = function() if self:undo() then afterPixelsChanged() end end,
    }, margin + #TOOL_ORDER * (button_w + gap), margin)
    redo_button = add(ToolButton:new{
        symbol = "redo", label = _("Redo"), width = button_w, height = button_h,
        disabled = #self.redo_stack == 0,
        callback = function() if self:redo() then afterPixelsChanged() end end,
    }, margin + (#TOOL_ORDER + 1) * (button_w + gap), margin)

    -- Options row: quick colors, style dialog, zoom, refresh, layers -----------------
    local option_y = tool_bar_h + margin
    local swatch_size = option_bar_h - gap
    local x = margin
    local function room() return w - margin - x end

    local min_style = safeScale(120)
    local swatch_total = #palette * (swatch_size + gap)
    if room() >= swatch_total + min_style + gap then
        for index = 1, #palette do
            swatches[index] = add(ColorSwatch:new{
                color_id = index, active = sameColor(self.color, palette[index]),
                width = swatch_size, height = swatch_size,
                callback = function()
                    self.color = copyColor(palette[index])
                    if self.tool == "eraser" or self.tool == "hand" then self:setTool("pen"); refreshTools() end
                    refreshColors()
                    refreshStyle()
                    refreshStatus()
                end,
            }, x, option_y)
            x = x + swatch_size + gap
        end
    end

    local zoom_total = swatch_size * 3 + safeScale(52) + gap * 4 + swatch_size + gap
    local layers_w = safeScale(104)
    local style_w = clamp(room() - zoom_total - layers_w - gap * 2, min_style, safeScale(260))
    style_w = min(style_w, room())
    style_chip = add(Chip:new{
        text = styleText(), color = self.color, width = style_w, height = swatch_size,
        callback = openStyleDialog,
    }, x, option_y)
    x = x + style_w + gap

    if room() >= zoom_total then
        add(ToolButton:new{
            symbol = "minus", width = swatch_size, height = swatch_size,
            callback = function() if canvas then canvas:zoomBy(1 / 1.4) end end,
        }, x, option_y)
        x = x + swatch_size + gap
        zoom_chip = add(Chip:new{
            text = string.format("%d%%", floor((self.zoom or 1) * 100 + 0.5)),
            width = safeScale(52), height = swatch_size,
            callback = function() if canvas then canvas:resetView() end end,
        }, x, option_y)
        x = x + safeScale(52) + gap
        add(ToolButton:new{
            symbol = "plus", width = swatch_size, height = swatch_size,
            callback = function() if canvas then canvas:zoomBy(1.4) end end,
        }, x, option_y)
        x = x + swatch_size + gap
        add(ToolButton:new{
            symbol = "refresh", width = swatch_size, height = swatch_size,
            callback = function() if canvas then canvas:fullRefresh() end end,
        }, x, option_y)
        x = x + swatch_size + gap
    end
    if room() >= safeScale(74) then
        add(Chip:new{
            text = string.format(_("Layer %d/%d"), self.active or 1, #self.layers),
            symbol = "layers", width = room(), height = swatch_size, callback = openLayers,
        }, x, option_y)
    end

    -- Canvas ---------------------------------------------------------------------
    add(Outline:new{ width = canvas_w + 2 * frame, height = canvas_h + 2 * frame, thickness = frame },
        canvas_x - frame, canvas_y - frame)
    canvas = Canvas:new{ app = self, width = canvas_w, height = canvas_h }
    canvas.fit = fit
    canvas.dimen = Geom:new{ x = canvas_x, y = canvas_y, w = canvas_w, h = canvas_h }
    for _name, event in pairs(canvas.ges_events) do
        event[1].range = function() return canvas.dimen end
    end
    add(canvas, canvas_x, canvas_y)
    canvas:_clampPan()
    Stylus:activate(canvas)

    -- Action bar -----------------------------------------------------------------
    local action_y = h - action_bar_h
    local action_h = action_bar_h - gap
    local toggle_w = max(safeScale(52), floor(action_h * 1.45))
    local action_w = max(safeScale(56), floor((w - margin * 2 - gap * 6 - toggle_w * 2) * 0.17))
    local bx = margin
    local function addChip(symbol, text, callback)
        add(Chip:new{ text = text, symbol = symbol, width = action_w, height = action_h, callback = callback }, bx, action_y)
        bx = bx + action_w + gap
    end
    addChip("save", _("Save"), doSave)
    addChip("open", _("Open"), doOpen)
    add(ToolButton:new{
        symbol = "paper", label = _("Page"), width = toggle_w, height = action_h, callback = openPaperDialog,
    }, bx, action_y)
    bx = bx + toggle_w + gap
    finger_button = add(ToolButton:new{
        symbol = "finger", label = _("Finger"), width = toggle_w, height = action_h,
        active = not self:fingerIgnored(), callback = toggleFinger,
    }, bx, action_y)
    bx = bx + toggle_w + gap
    addChip("more", _("More"), openMore)
    local status_x = bx + gap
    status = add(StatusLine:new{
        text = statusString(), width = max(safeScale(40), w - margin - status_x), height = action_h,
    }, status_x, action_y)

    pane.onDeactivate = function()
        canvas._dead = true
        if canvas._notify_cb and UIManager.unschedule then UIManager:unschedule(canvas._notify_cb) end
        canvas:_cancelAutoRefresh()
        Stylus:deactivate(canvas)
        if self.canvas == canvas then self.canvas = nil end
        self.on_change, self.on_view_change, self.on_selection_tap = nil, nil, nil
    end
    self.canvas = canvas
    return pane
end

Draw.Canvas = Canvas
Draw.ToolButton = ToolButton
Draw.ColorSwatch = ColorSwatch
Draw.Chip = Chip
Draw.StyleDialog = StyleDialog
Draw.PaperDialog = PaperDialog
Draw.Painter = Painter
Draw.newPainter = newPainter
Draw.renderDocument = renderDocument
Draw.newObject = newObject
Draw.addPoint = addPoint
Draw.transformObject = transformObject
return Draw
