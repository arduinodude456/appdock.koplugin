--[[--
Text-free raster surface layers for AppDock.

The bundled PNGs are deliberately neutral alpha overlays: the underlying
FrameContainer keeps receiving the active Theme palette color, while the
raster art contributes only tactile rim, grain and depth. This gives every
built-in/custom theme a colored surface without shipping any SVG artwork.
--]]--

local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalSpan = require("ui/widget/horizontalspan")
local OverlapGroup = require("ui/widget/overlapgroup")
local Wallpaper = require("appdock_wallpaper")

local Surface = {}

local MODULE_DIR = (debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "")
local ASSETS = {
    tile = "tile_overlay.png",
    circle = "circle_overlay.png",
    container = "container_overlay.png",
    pill = "pill_overlay.png",
    background = "liquid_glass_background.png",
}

local function emptySizedWidget(width, height)
    return CenterContainer:new{
        dimen = Geom:new{ w = width, h = height },
        HorizontalSpan:new{ width = 0 },
    }
end

local function assetPath(kind)
    local filename = ASSETS[kind or "container"]
    if not filename then return nil end
    local path = MODULE_DIR .. "assets/surfaces/" .. filename
    local file = io.open(path, "rb")
    if not file then return nil end
    file:close()
    return path
end

-- Builds an ordinary themed FrameContainer and layers one generated PNG on
-- top. The PNG has alpha and no baked-in color, so theme changes only require
-- rebuilding the normal AppDock view; no image variants are needed.
function Surface.build(options)
    options = options or {}
    local width = math.max(1, math.floor(tonumber(options.width) or 1))
    local height = math.max(1, math.floor(tonumber(options.height) or 1))
    local layers = {
        dimen = Geom:new{ w = width, h = height },
        allow_mirroring = false,
        overlap_offset = options.overlap_offset,
        FrameContainer:new{
            width = width,
            height = height,
            padding = 0,
            bordersize = options.bordersize or 0,
            color = options.color,
            radius = options.radius or 0,
            background = options.background,
            emptySizedWidget(width, height),
        },
    }

    local path = assetPath(options.kind)
    local texture = path and Wallpaper.buildPath(path, width, height, true, true) or nil
    if texture then
        texture.overlap_offset = { 0, 0 }
        table.insert(layers, texture)
    end

    for _, child in ipairs(options.children or {}) do
        table.insert(layers, child)
    end

    return OverlapGroup:new(layers)
end

return Surface
