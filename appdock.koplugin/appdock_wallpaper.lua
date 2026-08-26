--[[
Local wallpaper helper for AppDock. It never reads the network and only accepts
ordinary image files explicitly selected by the user.
--]]--

local ImageWidget = require("ui/widget/imagewidget")

local Wallpaper = {}

local ALLOWED_SUFFIXES = { png = true, jpg = true, jpeg = true, gif = true, webp = true, svg = true }

function Wallpaper.isValidPath(path)
    if type(path) ~= "string" or #path == 0 or #path > 360 or path:find("%z") then return false end
    local suffix = path:match("%.([%a%d]+)$")
    return suffix and ALLOWED_SUFFIXES[suffix:lower()] == true or false
end

function Wallpaper.buildPath(path, width, height, keep_original)
    if not Wallpaper.isValidPath(path) then return nil end
    local file = io.open(path, "rb")
    if not file then return nil end
    file:close()
    local ok, image = pcall(ImageWidget.new, ImageWidget, {
        file = path,
        width = width,
        height = height,
        scale_factor = 0,
        original_in_nightmode = keep_original == true,
    })
    return ok and image or nil
end

function Wallpaper.build(appdock, width, height)
    local settings = appdock.settings.wallpaper or {}
    if settings.enabled ~= true then return nil end
    local keep_original = appdock.settings.beta and appdock.settings.beta.keep_wallpaper_original_in_night == true
    return Wallpaper.buildPath(settings.path, width, height, keep_original)
end

return Wallpaper
