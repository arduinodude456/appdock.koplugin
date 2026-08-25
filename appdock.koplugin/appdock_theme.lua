--[[--
Central color themes for AppDock. Color devices receive Material-You-like
palette variants, while grayscale E-Ink devices retain fixed contrast roles.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")

local Theme = {}

local BUILTIN = {
    lavender = { title = "Lavender", primary = "#D6E3FF" },
    ocean = { title = "Ocean", primary = "#C6E7F5" },
    forest = { title = "Forest", primary = "#CDEBD5" },
    sunset = { title = "Sunset", primary = "#FFE0C2" },
}

local GRAYS = {
    background = Blitbuffer.COLOR_WHITE,
    surface = Blitbuffer.COLOR_LIGHT_GRAY,
    surface_variant = Blitbuffer.COLOR_GRAY_8,
    primary = Blitbuffer.COLOR_GRAY_8,
    secondary = Blitbuffer.COLOR_GRAY_7,
    tertiary = Blitbuffer.COLOR_GRAY_7,
    on_primary = Blitbuffer.COLOR_DARK_GRAY,
    on_secondary = Blitbuffer.COLOR_DARK_GRAY,
    on_tertiary = Blitbuffer.COLOR_DARK_GRAY,
    on_surface = Blitbuffer.COLOR_BLACK,
    on_variant = Blitbuffer.COLOR_DARK_GRAY,
    outline = Blitbuffer.COLOR_GRAY,
    track = Blitbuffer.COLOR_GRAY,
}

local function rgb(hex)
    local normalized = Theme.normalizeHex(hex)
    if not normalized then return nil end
    return tonumber(normalized:sub(2, 3), 16), tonumber(normalized:sub(4, 5), 16), tonumber(normalized:sub(6, 7), 16)
end

local function toHex(red, green, blue)
    return string.format("#%02X%02X%02X", math.max(0, math.min(255, math.floor(red + 0.5))), math.max(0, math.min(255, math.floor(green + 0.5))), math.max(0, math.min(255, math.floor(blue + 0.5))))
end

local function mix(first, second, first_weight)
    local r1, g1, b1 = rgb(first)
    local r2, g2, b2 = rgb(second)
    local second_weight = 1 - first_weight
    return toHex(r1 * first_weight + r2 * second_weight, g1 * first_weight + g2 * second_weight, b1 * first_weight + b2 * second_weight)
end

local function contrastInk(hex)
    local red, green, blue = rgb(hex)
    local luminance = (red * 299 + green * 587 + blue * 114) / 255000
    return luminance > 0.58 and "#1F1D24" or "#FFFFFF"
end

local function color(hex, grayscale)
    if not Device.screen:isColorEnabled() then return grayscale end
    local red, green, blue = rgb(hex)
    return Blitbuffer.ColorRGB32(red, green, blue, 0xFF)
end

function Theme.normalizeHex(value)
    if type(value) ~= "string" then return nil end
    local hex = value:gsub("^%s+", ""):gsub("%s+$", "")
    if hex:match("^%x%x%x%x%x%x$") then hex = "#" .. hex end
    if not hex:match("^#%x%x%x%x%x%x$") then return nil end
    return hex:upper()
end

function Theme.getBuiltinThemes()
    local themes = {}
    for id, definition in pairs(BUILTIN) do
        table.insert(themes, { id = id, title = definition.title, primary = definition.primary, builtin = true })
    end
    table.sort(themes, function(left, right) return left.title < right.title end)
    return themes
end

function Theme.getThemeList(settings)
    local themes = Theme.getBuiltinThemes()
    for id, definition in pairs((settings.theme and settings.theme.custom) or {}) do
        if Theme.normalizeHex(definition.primary) then
            table.insert(themes, { id = id, title = definition.title or id, primary = definition.primary, builtin = false })
        end
    end
    table.sort(themes, function(left, right)
        if left.builtin ~= right.builtin then return left.builtin end
        return left.title < right.title
    end)
    return themes
end

function Theme.resolveDefinition(settings)
    local theme = settings and settings.theme or {}
    local selected = theme.selected or "lavender"
    if BUILTIN[selected] then return selected, BUILTIN[selected] end
    local custom = theme.custom and theme.custom[selected]
    if custom and Theme.normalizeHex(custom.primary) then
        return selected, { title = custom.title or selected, primary = Theme.normalizeHex(custom.primary) }
    end
    return "lavender", BUILTIN.lavender
end

function Theme.getPalette(appdock)
    local settings = appdock and appdock.settings or nil
    local _, definition = Theme.resolveDefinition(settings)
    local primary = Theme.normalizeHex(definition.primary) or BUILTIN.lavender.primary
    local secondary = mix(primary, "#E7E1F2", 0.30)
    local tertiary = mix(primary, "#F0D8F4", 0.20)
    return {
        background = color("#FAF8FF", GRAYS.background),
        surface = color("#F2F0F7", GRAYS.surface),
        surface_variant = color("#E5E2EC", GRAYS.surface_variant),
        primary = color(primary, GRAYS.primary),
        secondary = color(secondary, GRAYS.secondary),
        tertiary = color(tertiary, GRAYS.tertiary),
        on_primary = color(contrastInk(primary), GRAYS.on_primary),
        on_secondary = color(contrastInk(secondary), GRAYS.on_secondary),
        on_tertiary = color(contrastInk(tertiary), GRAYS.on_tertiary),
        on_surface = color("#1F1D24", GRAYS.on_surface),
        on_variant = color("#4C4954", GRAYS.on_variant),
        outline = color("#797580", GRAYS.outline),
        track = color("#C6C4CD", GRAYS.track),
        primary_hex = primary,
    }
end

function Theme.createCustom(settings, title, hex)
    local normalized = Theme.normalizeHex(hex)
    local label = type(title) == "string" and title:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if label == "" or not normalized then return nil end
    settings.theme = settings.theme or { selected = "lavender", custom = {} }
    settings.theme.custom = settings.theme.custom or {}
    local base_id = label:lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
    if base_id == "" then base_id = "custom" end
    local id, suffix = "custom_" .. base_id, 2
    while settings.theme.custom[id] do
        id = "custom_" .. base_id .. "_" .. suffix
        suffix = suffix + 1
    end
    settings.theme.custom[id] = { title = label, primary = normalized }
    settings.theme.selected = id
    return id
end

return Theme
