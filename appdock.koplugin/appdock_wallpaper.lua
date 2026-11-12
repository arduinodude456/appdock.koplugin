--[[
Local wallpaper helper for AppDock. It never reads the network and only accepts
ordinary image files explicitly selected by the user.
--]]--

local ImageWidget = require("ui/widget/imagewidget")

local Wallpaper = {}

local ALLOWED_SUFFIXES = { png = true, jpg = true, jpeg = true, gif = true, webp = true, svg = true }

-- Only a missing wallpaper table denotes a new AppDock installation. An
-- explicit disabled setting, an unreadable path, and every user-selected path
-- are intentional choices and must therefore remain untouched.
function Wallpaper.ensureDefault(settings, default_path)
    if type(settings) ~= "table" or type(settings.wallpaper) == "table" then return false end
    if not Wallpaper.isValidPath(default_path) then return false end
    settings.wallpaper = {
        enabled = true,
        path = default_path,
        source = "appdock_default",
    }
    return true
end

function Wallpaper.isValidPath(path)
    if type(path) ~= "string" or #path == 0 or #path > 360 or path:find("%z") then return false end
    local suffix = path:match("%.([%a%d]+)$")
    return suffix and ALLOWED_SUFFIXES[suffix:lower()] == true or false
end

-- Decoding and scaling an image is by far the most expensive part of building
-- the homescreen, and the homescreen is rebuilt on every page change, search
-- keystroke and widget refresh. The scaled bitmap is therefore decoded once
-- and shared by later ImageWidgets (keyed by path, size, night-mode flag and
-- file modification time, so a changed file is always reloaded).
local lfs_ok, lfs = pcall(require, "libs/libkoreader-lfs")
-- The cache used to hold only 6 bitmaps. A homescreen already shows ~10
-- different logos plus the wallpaper, so every rebuild thrashed it and
-- re-decoded PNGs from flash. It is now a true LRU bounded by memory (not by
-- entry count), so everything on screen stays decoded between rebuilds.
local CACHE_BYTE_LIMIT = 24 * 1024 * 1024
local CACHE_ENTRY_LIMIT = 96
local cache, cache_order, cache_bytes, cache_sizes = {}, {}, 0, {}

local function bitmapBytes(bb)
    local ok, bytes = pcall(function()
        local stride = rawget(bb, "stride") or bb.stride
        if type(stride) == "number" and stride > 0 then return stride * bb:getHeight() end
        return bb:getWidth() * bb:getHeight() * 4
    end)
    return ok and bytes or 0
end

local function cacheKey(path, width, height, keep_original)
    if not lfs_ok or not lfs or not lfs.attributes then return nil end
    local attr = lfs.attributes(path)
    if type(attr) ~= "table" or attr.mode ~= "file" then return nil end
    return table.concat({ path, tostring(width), tostring(height), keep_original == true and "1" or "0",
        tostring(attr.modification), tostring(attr.size) }, "|")
end

local function cacheTouch(key)
    for index = #cache_order, 1, -1 do
        if cache_order[index] == key then
            if index ~= #cache_order then
                table.remove(cache_order, index)
                cache_order[#cache_order + 1] = key
            end
            return
        end
    end
end

local function cacheDrop(key)
    cache[key] = nil
    cache_bytes = cache_bytes - (cache_sizes[key] or 0)
    cache_sizes[key] = nil
end

local function cacheStore(key, bb)
    if cache[key] then
        cacheDrop(key)
        for index = #cache_order, 1, -1 do
            if cache_order[index] == key then table.remove(cache_order, index) break end
        end
    end
    local bytes = bitmapBytes(bb)
    cache[key] = bb
    cache_sizes[key] = bytes
    cache_bytes = cache_bytes + bytes
    cache_order[#cache_order + 1] = key
    while (#cache_order > CACHE_ENTRY_LIMIT or cache_bytes > CACHE_BYTE_LIMIT) and #cache_order > 1 do
        cacheDrop(table.remove(cache_order, 1))
    end
end

function Wallpaper.clearCache()
    cache, cache_order, cache_bytes, cache_sizes = {}, {}, 0, {}
end

function Wallpaper.buildPath(path, width, height, keep_original, no_cache)
    if not Wallpaper.isValidPath(path) then return nil end
    local key = not no_cache and cacheKey(path, width, height, keep_original) or nil
    if key and cache[key] then
        cacheTouch(key)
        local ok, image = pcall(ImageWidget.new, ImageWidget, {
            image = cache[key],
            image_disposable = false,
            width = width,
            height = height,
            scale_factor = 0,
            alpha = true,
            original_in_nightmode = keep_original == true,
        })
        if ok and image then return image end
        cacheDrop(key)
        for index = #cache_order, 1, -1 do
            if cache_order[index] == key then table.remove(cache_order, index) break end
        end
    end
    if not key then
        local file = io.open(path, "rb")
        if not file then return nil end
        file:close()
    end
    local ok, image = pcall(ImageWidget.new, ImageWidget, {
        file = path,
        width = width,
        height = height,
        scale_factor = 0,
        alpha = true,
        original_in_nightmode = keep_original == true,
    })
    if not ok or not image then return nil end
    local bb = rawget(image, "_bb")
    if key and bb and type(bb.getWidth) == "function" then
        -- The cache now owns the bitmap; the widget must not free it.
        image._bb_disposable = false
        cacheStore(key, bb)
    end
    return image
end

-- Decode a small preview before persisting a downloaded design background.
-- A suffix and a successful HTTP response alone do not prove that the file is an
-- image; without this guard an HTML error page can silently remove a theme's
-- background.
function Wallpaper.isUsableImage(path)
    local image = Wallpaper.buildPath(path, 16, 16, true, true)
    if not image then return false end
    if type(image.free) == "function" then pcall(function() image:free() end) end
    return true
end

function Wallpaper.build(appdock, width, height)
    local active_design = appdock and appdock.getActiveDesign and appdock:getActiveDesign() or nil
    if active_design and type(active_design.wallpaper_file) == "string" and active_design.wallpaper_file ~= "" then
        local keep_original = appdock.settings.beta and appdock.settings.beta.keep_wallpaper_original_in_night == true
        local design_wallpaper = Wallpaper.buildPath(active_design.wallpaper_file, width, height, keep_original)
        if design_wallpaper then return design_wallpaper end
    end
    local settings = appdock.settings.wallpaper or {}
    if settings.enabled ~= true then return nil end
    local keep_original = appdock.settings.beta and appdock.settings.beta.keep_wallpaper_original_in_night == true
    return Wallpaper.buildPath(settings.path, width, height, keep_original)
end

return Wallpaper
