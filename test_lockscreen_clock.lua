-- Lockscreen clock styles (9.8.0): standard, glass, color.
local function class()
    local C = {}
    function C:new(value)
        value = value or {}
        setmetatable(value, { __index = self })
        if value.init then value:init() end
        return value
    end
    function C:extend(proto)
        proto = proto or {}
        proto.__index = proto
        setmetatable(proto, { __index = self })
        return proto
    end
    function C:clear() for i = #self, 1, -1 do self[i] = nil end end
    return C
end
local function install(name, value) package.preload[name] = function() return value end end
local Widget = class()
local Text = Widget:extend{}
function Text:getSize() return { w = 10 * #(self.text or ""), h = 30 } end
local Overlap = Widget:extend{}
local Shape = Widget:extend{}
function Shape:getSize() return { w = self.width, h = self.height } end
local color = { COLOR_WHITE = "w", COLOR_BLACK = "b", COLOR_GRAY_D = "gd", COLOR_GRAY_4 = "g4", COLOR_GRAY_6 = "g6", COLOR_DARK_GRAY = "dg", COLOR_LIGHT_GRAY = "lg" }
install("ffi/blitbuffer", color)
install("ui/widget/container/inputcontainer", Widget)
install("ui/widget/overlapgroup", Overlap)
install("ui/widget/textwidget", Text)
install("ui/font", { getFace = function(_, name, size) return { name = name, size = size } end })
install("ui/gesturerange", { new = function(_, value) return value end })
install("ui/uimanager", { close = function() end, nextTick = function() end, setDirty = function() end, show = function() end })
local is_color = true
install("device", { screen = { scaleBySize = function(_, value) return value end, getSize = function() return { w = 600, h = 800 } end } })
install("ffi/sha2", { md5 = function(value) return value end })
install("appdock_wallpaper", { buildPath = function() return nil end })
install("appdock_rotation", { attach = function() end })
local function rgba(r, g, b, a, gray) return { r = r, g = g, b = b, a = a, gray = gray } end
install("appdock_glass", {
    rgba = rgba, isColor = function() return is_color end, solid = function(c) return c.r .. "," .. c.g .. "," .. c.b end,
    COLORS = setmetatable({}, { __index = function() return rgba(1, 2, 3, 255, "x") end }),
    Shape = Shape, Icon = Widget:extend{},
})
install("gettext", function(value) return value end)
local plugin_dir = os.getenv("APPDOCK_PLUGIN_DIR") or "appdock.koplugin/"
local LockScreen = assert(loadfile(plugin_dir .. "appdock_lockscreen.lua"))()

assert(LockScreen.clockStyle({ clock_style = "glass" }) == "glass" and LockScreen.clockStyle({ clock_style = "color" }) == "color", "Known clock styles are kept")
assert(LockScreen.clockStyle({ clock_style = "nope" }) == "standard" and LockScreen.clockStyle(nil) == "standard", "Unknown or absent styles fall back to standard")

local function build(style)
    local screen = LockScreen:new{ appdock = { settings = { lockscreen = { method = "swipe", clock_style = style } } } }
    local group = screen[1]
    local texts, shapes, digits = 0, 0, {}
    for _, layer in ipairs(group) do
        if layer.text then
            texts = texts + 1
            if layer.text:match("^%d$") then digits[#digits + 1] = layer end
        end
        if layer.radius then shapes = shapes + 1 end
    end
    return texts, shapes, digits
end

local _, standard_shapes = build("standard")
local glass_texts, glass_shapes = build("glass")
assert(glass_shapes >= standard_shapes + 3, "Liquid Glass draws rim, body and shine behind the clock")
local _, _, digits = build("color")
assert(#digits == 4, "Color style draws four separate digits")
assert(digits[1].overlap_offset[2] == digits[2].overlap_offset[2] and digits[3].overlap_offset[2] == digits[4].overlap_offset[2], "Digits of one row share a baseline")
assert(digits[3].overlap_offset[2] > digits[1].overlap_offset[2], "Minutes sit on a second line below the hours")
assert(digits[1].fgcolor ~= digits[2].fgcolor and digits[2].fgcolor ~= digits[3].fgcolor, "Every digit position has its own color")
is_color = false
build("color"); build("glass")
print("lockscreen-clock-ok")
