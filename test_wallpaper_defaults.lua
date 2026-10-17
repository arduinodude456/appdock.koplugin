package.preload["ui/widget/imagewidget"] = function() return {} end
local Wallpaper = dofile("./appdock.koplugin/appdock_wallpaper.lua")

local fresh = {}
assert(Wallpaper.ensureDefault(fresh, "/tmp/appdock_default.svg"), "fresh settings must receive the bundled default")
assert(fresh.wallpaper.enabled and fresh.wallpaper.path == "/tmp/appdock_default.svg")
assert(fresh.wallpaper.source == "appdock_default")

local custom = { wallpaper = { enabled = true, path = "/home/user/custom.png", source = "user" } }
assert(not Wallpaper.ensureDefault(custom, "/tmp/appdock_default.svg"), "a user wallpaper must never be replaced")
assert(custom.wallpaper.path == "/home/user/custom.png" and custom.wallpaper.enabled)

local disabled = { wallpaper = { enabled = false, path = "" } }
assert(not Wallpaper.ensureDefault(disabled, "/tmp/appdock_default.svg"), "an explicit disabled wallpaper must be respected")
assert(disabled.wallpaper.enabled == false)

print("wallpaper-defaults-ok")
