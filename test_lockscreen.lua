local function class()
    local C = {}
    function C:extend(proto)
        proto = proto or {}
        proto.__index = proto
        setmetatable(proto, { __index = self })
        return proto
    end
    return C
end
local function install(name, value) package.preload[name] = function() return value end end
local Widget = class()
install("ui/widget/container/centercontainer", Widget)
install("ui/widget/container/framecontainer", Widget)
install("ui/widget/container/inputcontainer", Widget)
install("ui/widget/overlapgroup", Widget)
install("ui/widget/textwidget", Widget)
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
print("lockscreen-method-ok")
