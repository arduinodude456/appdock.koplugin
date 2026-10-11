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

local function channelLuminance(channel)
    local value = (tonumber(channel) or 0) / 255
    if value <= 0.03928 then return value / 12.92 end
    return ((value + 0.055) / 1.055) ^ 2.4
end

local function relativeLuminance(hex)
    local red, green, blue = rgb(hex)
    if not red then return 0 end
    return channelLuminance(red) * 0.2126 + channelLuminance(green) * 0.7152 + channelLuminance(blue) * 0.0722
end

local function contrastRatio(first, second)
    local left, right = relativeLuminance(first), relativeLuminance(second)
    if left < right then left, right = right, left end
    return (left + 0.05) / (right + 0.05)
end

local function contrastInk(hex)
    -- Pure black/white are deliberate only as fallbacks. They guarantee that
    -- one option clears the readable-text threshold even on mid-gray palettes.
    local dark_ratio = contrastRatio(hex, "#000000")
    local light_ratio = contrastRatio(hex, "#FFFFFF")
    return dark_ratio >= light_ratio and "#000000" or "#FFFFFF"
end

-- Store designs remain permissive so existing user-installed themes keep
-- working, but no text role is ever allowed to inherit an unreadable ink.
local function readableInk(surface, preferred)
    local candidate = Theme.normalizeHex(preferred)
    if candidate and contrastRatio(surface, candidate) >= 4.5 then return candidate end
    return contrastInk(surface)
end

local function grayscaleInk(surface)
    -- A fixed COLOR_BLACK/COLOR_DARK_GRAY role is not safe for installed
    -- dark designs: on grayscale readers Forest's dark surfaces otherwise
    -- receive nearly invisible dark text. Choose the ink from the actual
    -- design surface, just like readableInk does for color devices.
    return relativeLuminance(surface) < 0.42 and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
end

local function color(hex, grayscale)
    local red, green, blue = rgb(hex)
    if not Device.screen:isColorEnabled() then return grayscale end
    return Blitbuffer.ColorRGB32(red, green, blue, 0xFF)
end

-- Use this only for colors deliberately drawn during a fast-refresh animation.
-- The static UI must continue to use `color()` above.
function Theme.fastColor(red, green, blue, grayscale)
    if not Device.screen:isColorEnabled() then
        return ((red or 0) + (green or 0) + (blue or 0)) >= 384 and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
    end
    local candidates = {
        { 0, 0, 0 }, { 255, 255, 255 }, { 255, 0, 0 },
        { 0, 255, 0 }, { 0, 0, 255 }, { 255, 255, 0 },
    }
    local best, best_distance
    for _, candidate in ipairs(candidates) do
        local dr, dg, db = (red or 0) - candidate[1], (green or 0) - candidate[2], (blue or 0) - candidate[3]
        local distance = dr * dr + dg * dg + db * db
        if not best_distance or distance < best_distance then best, best_distance = candidate, distance end
    end
    return Blitbuffer.ColorRGB32(best[1], best[2], best[3], 0xFF)
end

function Theme.normalizeHex(value)
    if type(value) ~= "string" then return nil end
    local hex = value:gsub("^%s+", ""):gsub("%s+$", "")
    if hex:match("^%x%x%x%x%x%x$") then hex = "#" .. hex end
    if not hex:match("^#%x%x%x%x%x%x$") then return nil end
    return hex:upper()
end

function Theme.ellipsize(value, maximum_characters)
    local text = type(value) == "string" and value or tostring(value or "")
    text = text:gsub("[\r\n]+", " ")
    local maximum = math.max(1, math.floor(tonumber(maximum_characters) or 1))
    local position, characters = 1, 0
    while position <= #text do
        local byte = text:byte(position) or 0
        local width = byte >= 240 and 4 or (byte >= 224 and 3 or (byte >= 192 and 2 or 1))
        if characters >= maximum then
            local visible = math.max(1, maximum - 1)
            local end_position, visible_characters = 1, 0
            while end_position <= #text and visible_characters < visible do
                local visible_byte = text:byte(end_position) or 0
                end_position = end_position + (visible_byte >= 240 and 4 or (visible_byte >= 224 and 3 or (visible_byte >= 192 and 2 or 1)))
                visible_characters = visible_characters + 1
            end
            return text:sub(1, end_position - 1) .. "…"
        end
        position = position + width
        characters = characters + 1
    end
    return text
end

function Theme.fitLabel(value, width, font_size, padding)
    local available = math.max(1, math.floor((tonumber(width) or 0) - (tonumber(padding) or 0)))
    local average_character_width = math.max(4, math.floor((tonumber(font_size) or 10) * .56))
    return Theme.ellipsize(value, math.max(1, math.floor(available / average_character_width)))
end

function Theme.textSize(appdock, logical_size, minimum)
    local requested = appdock and appdock.settings and appdock.settings.accessibility and tonumber(appdock.settings.accessibility.text_scale) or 1
    local allowed = { [.5] = true, [.75] = true, [.9] = true, [1] = true, [1.15] = true, [1.3] = true, [1.5] = true }
    if not allowed[requested] then requested = 1 end
    local base = Device.screen:scaleBySize(tonumber(logical_size) or 10)
    local floor_size = Device.screen:scaleBySize(tonumber(minimum) or 7)
    return math.max(floor_size, math.floor(base * requested + .5))
end

function Theme.adjustText(appdock, scaled_size, minimum)
    local requested = appdock and appdock.settings and appdock.settings.accessibility and tonumber(appdock.settings.accessibility.text_scale) or 1
    local allowed = { [.5] = true, [.75] = true, [.9] = true, [1] = true, [1.15] = true, [1.3] = true, [1.5] = true }
    if not allowed[requested] then requested = 1 end
    return math.max(tonumber(minimum) or 1, math.floor((tonumber(scaled_size) or 1) * requested + .5))
end

function Theme.centeredStack(container_height, items, gap, padding)
    local heights, total = {}, 0
    -- AppDock text stacks use a compact rhythm on E-Ink: callers retain their
    -- relative spacing, but the rendered gap is reduced before positioning.
    -- Simple Mode does not use this helper and therefore keeps its layout.
    local requested_gap = math.max(0, tonumber(gap) or 0)
    local safe_gap = requested_gap > 0 and math.max(1, math.floor(requested_gap * 0.55 + .5)) or 0
    local safe_padding = math.max(0, tonumber(padding) or 0)
    for index, item in ipairs(items or {}) do
        local size = type(item) == "table" and type(item.getSize) == "function" and item:getSize() or nil
        local height = size and tonumber(size.h) or tonumber(item) or 0
        heights[index] = math.max(0, math.floor(height + .5))
        total = total + heights[index]
    end
    if #heights > 1 then total = total + safe_gap * (#heights - 1) end
    local y = math.max(safe_padding, math.floor(((tonumber(container_height) or 0) - total) / 2))
    local positions = {}
    for index, height in ipairs(heights) do
        positions[index] = y
        y = y + height + safe_gap
    end
    return positions, total
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
    settings = type(settings) == "table" and settings or {}
    local theme = type(settings.theme) == "table" and settings.theme or {}
    local custom = type(theme.custom) == "table" and theme.custom or {}
    local themes = Theme.getBuiltinThemes()
    for id, definition in pairs(custom) do
        if type(id) == "string" and type(definition) == "table" and Theme.normalizeHex(definition.primary) then
            table.insert(themes, { id = id, title = type(definition.title) == "string" and definition.title or id, primary = definition.primary, builtin = false })
        end
    end
    table.sort(themes, function(left, right)
        if left.builtin ~= right.builtin then return left.builtin end
        return left.title < right.title
    end)
    return themes
end

function Theme.resolveDefinition(settings)
    local theme = type(settings) == "table" and type(settings.theme) == "table" and settings.theme or {}
    local selected = type(theme.selected) == "string" and theme.selected or "lavender"
    if BUILTIN[selected] then return selected, BUILTIN[selected] end
    local custom = type(theme.custom) == "table" and theme.custom[selected] or nil
    if type(custom) == "table" and Theme.normalizeHex(custom.primary) then
        return selected, { title = type(custom.title) == "string" and custom.title or selected, primary = Theme.normalizeHex(custom.primary) }
    end
    return "lavender", BUILTIN.lavender
end

function Theme.normalizeDesignDefinition(definition)
    if type(definition) ~= "table" then return nil end
    local id = type(definition.id) == "string" and definition.id:match("^%s*(.-)%s*$") or ""
    local title = type(definition.title) == "string" and definition.title:match("^%s*(.-)%s*$") or ""
    local highlight = Theme.normalizeHex(definition.highlight)
    local background = Theme.normalizeHex(definition.background)
    local button = Theme.normalizeHex(definition.button)
    local text = Theme.normalizeHex(definition.text)
    local dropdown = Theme.normalizeHex(definition.dropdown)
    if not id:match("^[%w_%-]+$") or title == "" or #title > 48 then return nil end
    if not highlight or not background or not button or not text or not dropdown then return nil end
    return {
        id = id,
        title = title,
        version = type(definition.version) == "string" and definition.version or nil,
        highlight = highlight,
        background = background,
        button = button,
        text = text,
        dropdown = dropdown,
        button_style = definition.button_style == "3d" and "3d" or "rounded",
        logo_shape = definition.logo_shape == "circle" and "circle" or "rounded",
        wallpaper = type(definition.wallpaper) == "string" and definition.wallpaper or "",
        source_path = type(definition.source_path) == "string" and definition.source_path or "",
        file = type(definition.file) == "string" and definition.file or "",
        wallpaper_file = type(definition.wallpaper_file) == "string" and definition.wallpaper_file or "",
    }
end

function Theme.getActiveDesign(settings)
    local design = type(settings) == "table" and type(settings.design) == "table" and settings.design or nil
    local active_id = design and design.active_id
    local installed = design and type(design.installed) == "table" and design.installed or nil
    local record = type(active_id) == "string" and installed and installed[active_id] or nil
    return Theme.normalizeDesignDefinition(record)
end

function Theme.getAppLogoShape(appdock)
    local settings = appdock and appdock.settings or nil
    local design = Theme.getActiveDesign(settings)
    if design then return design.logo_shape end
    return settings and settings.layout and settings.layout.logo_shape == "circle" and "circle" or "rounded"
end

function Theme.getButtonFrameStyle(appdock, height, rounded_radius)
    local design = Theme.getActiveDesign(appdock and appdock.settings)
    if not design or design.button_style ~= "3d" then
        return { radius = rounded_radius, bordersize = 0, color = nil }
    end
    local border = math.max(1, Device.screen:scaleBySize(1))
    local ink = readableInk(design.background, design.text)
    return {
        radius = math.max(border * 2, math.floor((tonumber(height) or 20) * .14)),
        bordersize = border,
        color = color(mix(ink, design.background, .46), GRAYS.outline),
    }
end

function Theme.getPalette(appdock)
    local settings = appdock and appdock.settings or nil
    local design = Theme.getActiveDesign(settings)
    local resolved_theme_id, definition = Theme.resolveDefinition(settings)
    local primary = Theme.normalizeHex(definition.primary) or BUILTIN.lavender.primary
    local background = "#FAF8FF"
    local text = "#1F1D24"
    local button = primary
    local dropdown = background
    if design then
        primary = design.highlight
        background = design.background
        text = design.text
        button = design.button
        dropdown = design.dropdown
    end
    local high_contrast = settings and settings.accessibility and settings.accessibility.high_contrast == true
    if high_contrast then text = contrastInk(background) end
    local secondary = mix(primary, background, high_contrast and .62 or .42)
    local tertiary = mix(button, background, high_contrast and .72 or .56)
    local surface = high_contrast and background or mix(background, text, .93)
    local surface_variant = high_contrast and mix(text, background, .10) or mix(button, background, .25)
    local on_surface = readableInk(surface, text)
    local on_variant = readableInk(surface_variant, text)
    return {
        background = color(background, GRAYS.background),
        surface = color(surface, GRAYS.surface),
        surface_variant = color(surface_variant, GRAYS.surface_variant),
        primary = color(primary, GRAYS.primary),
        secondary = color(secondary, GRAYS.secondary),
        tertiary = color(tertiary, GRAYS.tertiary),
        button = color(button, GRAYS.primary),
        dropdown = color(dropdown, GRAYS.background),
        on_primary = color(readableInk(primary, text), grayscaleInk(primary)),
        on_secondary = color(readableInk(secondary, text), grayscaleInk(secondary)),
        on_tertiary = color(readableInk(tertiary, text), grayscaleInk(tertiary)),
        on_button = color(readableInk(button, text), grayscaleInk(button)),
        on_surface = color(on_surface, grayscaleInk(surface)),
        on_variant = color(on_variant, grayscaleInk(surface_variant)),
        outline = color(mix(on_surface, background, .48), GRAYS.outline),
        track = color(mix(readableInk(button, text), background, .52), GRAYS.track),
        primary_hex = primary,
        background_hex = background,
        high_contrast = high_contrast,
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

Theme._test = {
    contrastRatio = contrastRatio,
    readableInk = readableInk,
}

return Theme
