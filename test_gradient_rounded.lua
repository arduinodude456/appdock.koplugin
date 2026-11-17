-- Rounded / decorated gradients (9.8.0).
local function install(name, value) package.preload[name] = function() return value end end
install("ffi/blitbuffer", { ColorRGB32 = function(r, g, b) return { r = r, g = g, b = b } end })
install("ui/geometry", { new = function(_, v) return v end })
local Widget = { extend = function(self, proto) proto.__index = proto; return setmetatable(proto, { __index = self }) end,
    new = function(self, v) setmetatable(v, { __index = self }); if v.init then v:init() end; return v end }
install("ui/widget/widget", Widget)
install("appdock_theme", { getRoleGradient = function(_, role) return role == "button" and { angle = 90, stops = { { pos = 0, hex = "#000000" }, { pos = 1, hex = "#FFFFFF" } } } or nil end })
local plugin_dir = os.getenv("APPDOCK_PLUGIN_DIR") or "appdock.koplugin/"
local Gradient = assert(loadfile(plugin_dir .. "appdock_gradient.lua"))()

local function recorder()
    local rects = {}
    return { paintRect = function(_, x, y, w, h, c) rects[#rects + 1] = { x = x, y = y, w = w, h = h, c = c } end }, rects
end
local gradient = { angle = 90, stops = { { pos = 0, hex = "#000000" }, { pos = 1, hex = "#FFFFFF" } } }
local bb, rects = recorder()
assert(Gradient.paintRounded(bb, 10, 20, 100, 40, 16, gradient), "paintRounded paints")
local area, min_x, max_x, rows = 0, 1e9, -1, {}
for _, r in ipairs(rects) do
    area = area + r.w * r.h
    assert(r.x >= 10 and r.x + r.w <= 110 and r.y >= 20 and r.y + r.h <= 60, "rects stay inside the box")
    for y = r.y, r.y + r.h - 1 do rows[y] = true end
end
local count = 0
for _ in pairs(rows) do count = count + 1 end
assert(count == 40, "every row of the box is painted (" .. count .. ")")
assert(area < 100 * 40 and area > 100 * 40 * .9, "corners are cut out: area " .. area)
-- Horizontal gradient runs light to dark across x.
local first, last = rects[1], rects[#rects]
assert(rects[1].y == 20 and #rects > 10, "top corner rows are painted separately")
local left_color, right_color
for _, r in ipairs(rects) do
    if r.y == 40 and r.x == 10 then left_color = r.c end
    if r.y == 40 and r.x + r.w == 110 then right_color = r.c end
end
assert(left_color and right_color and left_color.r < right_color.r, "angle 90 fades left to right")

-- decorate(): the frame loses its flat fill while painting, regains it after.
local painted_background
local frame = { width = 100, height = 40, radius = 16, background = "flat", paintTo = function(self, b, x, y) painted_background = self.background; return "done" end }
Gradient.decorate(frame, gradient, 16)
local bb2, rects2 = recorder()
assert(frame:paintTo(bb2, 0, 0) == "done" and #rects2 > 0 and painted_background == nil, "gradient replaces the flat fill during paint")
assert(frame.background == "flat", "flat color restored for later readers")
-- A failing painter falls back to the flat fill.
local broken = { paintRect = function() error("boom") end }
frame:paintTo(broken, 0, 0)
assert(painted_background == "flat", "flat fallback when the gradient cannot be painted")
assert(Gradient.role({}, "button") and Gradient.role({}, "primary") == nil, "Gradient.role asks the theme")
print("gradient-rounded-ok")
