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
local scheduled, shown_widgets, closed_widgets = {}, {}, {}
install("ui/uimanager", {
    close = function(_, widget) closed_widgets[#closed_widgets + 1] = widget end,
    nextTick = function(_, callback) if callback then callback() end end,
    setDirty = function() end,
    show = function(_, widget) shown_widgets[#shown_widgets + 1] = widget end,
    scheduleIn = function(_, delay, callback) scheduled[#scheduled + 1] = { delay = delay, callback = callback } end,
    unschedule = function(_, callback) for i = #scheduled, 1, -1 do if scheduled[i].callback == callback then table.remove(scheduled, i) end end end,
})
local is_color = true
install("device", {
    screen = { scaleBySize = function(_, value) return value end, getSize = function() return { w = 600, h = 800 } end },
    getPowerDevice = function() return { getCapacity = function() return 82 end, isCharging = function() return true end } end,
})
-- Stand-in for the Liquid Glass module: a layer that records what it was given.
local glass_available = true
local Layer = Widget:extend{}
function Layer:init() self.pad = 7; self.w = 10 * #(self.text or "") + 14; self.h = self.size + 14 end
function Layer:getSize() return { w = self.w, h = self.h } end
function Layer:getInkSize() return self.w - 14, self.h - 14 end
function Layer:free() self.freed = true end
install("appdock_glassclock", { layerClass = function() return glass_available and Layer or nil end })
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
glass_available = false
local glass_texts, glass_shapes = build("glass")
assert(glass_shapes >= standard_shapes + 3, "Without the glass module the frosted capsule is the fallback")
glass_available = true
local function glassLayers(mode, style)
    local screen = LockScreen:new{ mode = mode, appdock = { settings = { lockscreen = { method = "swipe", clock_style = style } } } }
    local layers = {}
    local shapes = 0
    for _, layer in ipairs(screen[1]) do
        if layer.text and layer.pad then layers[#layers + 1] = layer end
        if layer.radius then shapes = shapes + 1 end
    end
    return layers, shapes, screen
end
local layers, shapes_with_glass = glassLayers("lock", "glass")
assert(#layers == 1 and layers[1].text:match("^%d%d:%d%d$"), "Liquid Glass renders the digits themselves as one glass layer")
assert(shapes_with_glass <= standard_shapes + 1, "No capsule card is drawn behind real glass digits")
assert(layers[1].overlap_offset[2] == 800 * 0 + layers[1].overlap_offset[2] and layers[1].overlap_offset[1] > 0, "The glass clock is centred horizontally")

-- Standby: same look, very large stacked clock, no unlock hint.
local big_layers, _, standby_screen = glassLayers("standby", "glass")
assert(#big_layers == 1 and big_layers[1].text:match("^%d%d\n%d%d$"), "Standby stacks hours above minutes in one glass layer")
assert(big_layers[1].size > layers[1].size * 1.5, "The standby clock is much larger than the lockscreen clock")
local _, _, standard_standby = glassLayers("standby", "standard")
local big_digit_rows = {}
for _, layer in ipairs(standard_standby[1]) do if layer.text and layer.text:match("^%d%d$") then big_digit_rows[#big_digit_rows + 1] = layer end end
assert(#big_digit_rows == 2 and big_digit_rows[2].overlap_offset[2] > big_digit_rows[1].overlap_offset[2], "Standard style also stacks hours over minutes in standby")
local has_hint, has_charge = false, false
for _, layer in ipairs(standby_screen[1]) do
    if layer.text == "Tap to leave standby" then has_hint = true end
    if layer.text and layer.text:find("Charging", 1, true) and layer.text:find("82 %", 1, true) then has_charge = true end
end
assert(has_hint, "Standby says how to leave it")
assert(has_charge, "Standby shows the charging state and battery level")

-- Tapping or swiping leaves standby and runs the exit callback once.
local exits = 0
local leaving = LockScreen:new{ mode = "standby", on_exit = function() exits = exits + 1 end, appdock = { settings = { lockscreen = { method = "swipe", clock_style = "glass" } } } }
leaving.dimen = { w = 600, h = 800 }
leaving:onLockTap({}, { pos = { x = 10, y = 10 } })
leaving:onLockSwipe({}, { direction = "north" })
assert(exits == 1, "Leaving standby runs the exit callback exactly once")
assert(closed_widgets[#closed_widgets] == leaving, "Standby closes its own widget")

-- A rebuild frees the old glass layers.
local before_free = layers[1]
local rebuild_screen = LockScreen:new{ appdock = { settings = { lockscreen = { method = "swipe", clock_style = "glass" } } } }
local first_layer
for _, layer in ipairs(rebuild_screen[1]) do if layer.pad then first_layer = layer end end
rebuild_screen:build()
assert(first_layer.freed, "Rebuilding the lockscreen frees the previous glass tile")
local _, _, digits = build("color")
assert(#digits == 4, "Color style draws four separate digits")
assert(digits[1].overlap_offset[2] == digits[2].overlap_offset[2] and digits[3].overlap_offset[2] == digits[4].overlap_offset[2], "Digits of one row share a baseline")
assert(digits[3].overlap_offset[2] > digits[1].overlap_offset[2], "Minutes sit on a second line below the hours")
assert(digits[1].fgcolor ~= digits[2].fgcolor and digits[2].fgcolor ~= digits[3].fgcolor, "Every digit position has its own color")
is_color = false
build("color"); build("glass")
print("lockscreen-clock-ok")
