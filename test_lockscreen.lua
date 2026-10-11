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
    function C:clear()
        for index = #self, 1, -1 do self[index] = nil end
    end
    return C
end
local function install(name, value) package.preload[name] = function() return value end end
local Widget = class()
local FrameContainer = class()
function FrameContainer:new(value)
    value = value or {}
    assert(value[1] ~= nil, "FrameContainer must have a child widget")
    setmetatable(value, { __index = self })
    if value.init then value:init() end
    return value
end
install("ui/widget/container/centercontainer", Widget)
install("ui/widget/container/framecontainer", FrameContainer)
install("ui/widget/container/inputcontainer", Widget)
install("ui/widget/overlapgroup", Widget)
install("ui/widget/textwidget", Widget)
install("ui/widget/horizontalspan", Widget)
install("ui/font", { getFace = function() return {} end })
install("ui/geometry", { new = function(_, value) return value end })
install("ui/gesturerange", { new = function(_, value) return value end })
install("ui/uimanager", { close = function() end, nextTick = function(_, callback) callback() end, setDirty = function() end, show = function() end })
install("device", { screen = { scaleBySize = function(_, value) return value end, getSize = function() return { w = 600, h = 800 } end } })
install("ffi/sha2", { md5 = function(value) return value end })
install("appdock_wallpaper", { buildPath = function() return nil end })
install("appdock_theme", { getPalette = function() return {} end })
install("appdock_keyboard", {})
install("gettext", function(value) return value end)

local LockScreen = assert(loadfile("appdock.koplugin/appdock_lockscreen.lua"))()
assert(LockScreen._test.lockMethod({ method = "pin" }) == "pin", "PIN profiles must select the PIN lock flow")
assert(LockScreen._test.lockMethod({ method = "pattern" }) == "pattern", "Pattern profiles must select the pattern lock flow")
assert(LockScreen._test.lockMethod({ method = "unknown" }) == "swipe" and LockScreen._test.lockMethod(nil) == "swipe", "Invalid and absent lock profiles must safely use swipe")
assert(LockScreen:new{ appdock = { settings = { lockscreen = { method = "swipe" } } } }, "Lockscreen must build without an empty FrameContainer child")
print("lockscreen-method-ok")
