--[[--
Text-free raster surface layers for AppDock.

The bundled PNGs are real raster surfaces with transparent, shape-masked
edges. The legacy FrameContainer remains for layout and input geometry, but
its old flat color is never painted underneath the generated artwork.
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
}
local GLASS_ASSETS = {
    tile = "liquid_glass_tile.png",
    circle = "liquid_glass_circle.png",
    container = "liquid_glass_container.png",
    pill = "liquid_glass_pill.png",
}

local function emptySizedWidget(width, height)
    return CenterContainer:new{
        dimen = Geom:new{ w = width, h = height },
        HorizontalSpan:new{ width = 0 },
    }
end

local function imagePath(filename)
    if not filename then return nil end
    local path = MODULE_DIR .. "assets/surfaces/" .. filename
    local file = io.open(path, "rb")
    if not file then return nil end
    file:close()
    return path
end

local function assetPath(kind)
    return imagePath(ASSETS[kind or "container"])
end

local function glassPath(kind)
    return imagePath(GLASS_ASSETS[kind or "container"])
end

-- Builds a transparent hit/layout frame and layers shape-masked generated PNGs
-- on top. The legacy theme fill is deliberately not painted: it must not show
-- through or outside the liquid-glass surface.
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
            background = nil,
            emptySizedWidget(width, height),
        },
    }

    -- Liquid glass belongs to interactive surfaces, not the homescreen itself.
    -- Each variant has transparent pixels outside its own shape, because
    -- OverlapGroup does not clip children to a FrameContainer radius.
    if options.glass ~= false then
        local glass_path = glassPath(options.kind)
        local glass = glass_path and Wallpaper.buildPath(glass_path, width, height, true, true) or nil
        if glass then
            glass.overlap_offset = { 0, 0 }
            table.insert(layers, glass)
        end
    end
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
