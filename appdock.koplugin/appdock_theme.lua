--[[--
Central color themes for AppDock. Color devices receive Material-You-like
palette variants, while grayscale E-Ink devices retain fixed contrast roles.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")

local Theme = {}

local MODULE_DIR = (debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "")

-- Built-in themes. The four classic themes only define a `primary` tint and
-- derive everything else from it. A theme may also carry the full set of
-- design roles (`background`, `text`, `button`, `dropdown`), a `gradient`
-- (stops + angle, see Theme.normalizeGradient) and a bundled `wallpaper`
-- (path relative to the plugin folder), exactly like an installed Store design.
local BUILTIN = {
    -- Aurora (9.6.0): northern lights. Deep night-sky navy that fades through
    -- teal and green into violet, with the same photo as the lockscreen.
    aurora = {
        title = "Aurora", primary = "#7CF2C9",
        background = "#0B1A36", text = "#E9F6F1", button = "#3FD0B0", dropdown = "#102448",
        gradient = { angle = 168, stops = { "#050E26", "#0A3550", "#117A68", "#3F3B8F" } },
        wallpaper = "assets/lockscreen/appdock_lockscreen_aurora.jpg",
    },
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

-- Store DApps do not all use the same palette field names. Keep explicit
-- foreground aliases in the public palette and derive every one from the
-- surface it is painted on. This prevents an installed design's decorative
-- text color from becoming invisible when a third-party DApp uses `text`,
-- `foreground` or `on_background` instead of AppDock's newer `on_surface`.
local function roleInk(surface, preferred)
    return readableInk(surface, preferred)
end

local function grayscaleInk(surface)
    -- A fixed COLOR_BLACK/COLOR_DARK_GRAY role is not safe for installed
    -- dark designs: on grayscale readers Forest's dark surfaces otherwise
    -- receive nearly invisible dark text. Choose the ink from the actual
    -- design surface, just like readableInk does for color devices.
    return relativeLuminance(surface) < 0.42 and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
end

-- AppDock owns its appearance mode. It never relies on KOReader's global
-- framebuffer inversion; all palette colors are painted as their final values.
local function isNight(appdock)
    local settings = appdock and appdock.settings or nil
    local theme = settings and settings.theme or nil
    return theme and theme.night_mode == true or false
end

local function color(hex, grayscale)
    local red, green, blue = rgb(hex)
    if not Device.screen:isColorEnabled() then
        local luminance = relativeLuminance(hex)
        -- Keep the established E-Ink roles in light mode; dark local surfaces
        -- must not fall back to those light roles now that KOReader no longer
        -- inverts the framebuffer for AppDock.
        if luminance < 0.015 then return Blitbuffer.COLOR_BLACK or grayscale end
        if luminance < 0.08 then return Blitbuffer.COLOR_DARK_GRAY or grayscale end
        return grayscale
    end
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

-- Gradients (9.6.0). A gradient is { angle = degrees, stops = { {pos, hex}, ... } }
-- with CSS semantics for the angle (0 = towards the top, 90 = towards the right,
-- 180 = towards the bottom). Accepted inputs:
--   "#112233,#445566,#778899"                       comma separated colors
--   { "#112233", "#445566" }                         list of colors
--   { from = "#..", via = "#..", to = "#..", angle } from / via / to
--   { stops = { "#..", { pos = .4, color = "#.." } }, angle = 160 }
-- Anything invalid yields nil, so a broken design simply has no gradient.
local MAX_GRADIENT_STOPS = 6

function Theme.normalizeGradient(value, default_angle)
    local colors, positions, angle = {}, {}, tonumber(default_angle)
    local function add(color, position)
        local hex = Theme.normalizeHex(type(color) == "table" and (color.color or color.hex or color[1]) or color)
        if not hex then return false end
        colors[#colors + 1] = hex
        positions[#positions + 1] = type(color) == "table" and tonumber(color.pos or color.position or color[2]) or position
        return true
    end
    if type(value) == "string" then
        for part in value:gmatch("[^,;%s]+") do
            if #colors >= MAX_GRADIENT_STOPS or not add(part) then return nil end
        end
    elseif type(value) == "table" then
        angle = tonumber(value.angle) or angle
        local list = value.stops or value.colors
        if type(list) ~= "table" then
            list = {}
            for _, key in ipairs({ "from", "via", "to" }) do
                if value[key] ~= nil then list[#list + 1] = value[key] end
            end
            if #list == 0 then list = value end
        end
        for _, item in ipairs(list) do
            if #colors >= MAX_GRADIENT_STOPS or not add(item) then return nil end
        end
    else
        return nil
    end
    if #colors < 2 then return nil end
    local stops = {}
    local previous = 0
    for index, hex in ipairs(colors) do
        local position = positions[index]
        if position == nil then position = (index - 1) / (#colors - 1) end
        position = math.max(previous, math.min(1, math.max(0, position)))
        previous = position
        stops[index] = { pos = position, hex = hex }
    end
    angle = angle or 180
    angle = angle - math.floor(angle / 360) * 360
    return { angle = angle, stops = stops }
end

function Theme.gradientSignature(gradient)
    -- Built-in themes may store simple color strings in `stops`, while active
    -- Store designs already carry normalized { pos, hex } entries. Normalize
    -- both forms before building the cache key; otherwise Aurora crashes as
    -- soon as the homescreen asks for its first palette.
    local normalized = Theme.normalizeGradient(gradient)
    if not normalized then return "-" end
    local parts = { tostring(normalized.angle) }
    for _, stop in ipairs(normalized.stops) do parts[#parts + 1] = tostring(stop.pos) .. stop.hex end
    return table.concat(parts, ":")
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
        table.insert(themes, { id = id, title = definition.title, primary = definition.primary, builtin = true,
            gradient = definition.gradient ~= nil })
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
            table.insert(themes, { id = id, title = type(definition.title) == "string" and definition.title or id, primary = definition.primary, builtin = false,
                gradient = Theme.normalizeGradient(definition.gradient, definition.gradient_angle) ~= nil })
        end
    end
    table.sort(themes, function(left, right)
        if left.builtin ~= right.builtin then return left.builtin end
        -- Aurora is the flagship theme of 9.6.0 and leads the list.
        if left.id == "aurora" or right.id == "aurora" then return left.id == "aurora" end
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
        return selected, {
            title = type(custom.title) == "string" and custom.title or selected,
            primary = Theme.normalizeHex(custom.primary),
            gradient = Theme.normalizeGradient(custom.gradient, custom.gradient_angle),
        }
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
        -- Optional (9.6.0): a gradient painted instead of the flat background.
        gradient = Theme.normalizeGradient(definition.gradient, definition.gradient_angle),
    }
end

-- getActiveDesign() runs for every app tile (logo shape + frame style) and for
-- every palette lookup, and each call re-validated five hex colors with
-- pattern matching. The normalized result is memoized per stored record and
-- revalidated through a cheap signature, so an edited design is still picked up.
local design_cache = setmetatable({}, { __mode = "k" })

-- Normalized gradients ({ angle, stops = { {pos, hex} } }) are summarised by
-- Theme.gradientSignature; a raw record that has not been normalized yet (a
-- string or a from/to table) falls back to its textual form.
local function designGradientSignature(record)
    local gradient = record.gradient
    if type(gradient) == "table" and type(gradient.stops) == "table"
        and type(gradient.stops[1]) == "table" and gradient.stops[1].hex then
        return Theme.gradientSignature(gradient)
    end
    return tostring(gradient) .. tostring(record.gradient_angle)
end

local function designSignature(record)
    return table.concat({
        tostring(record.id), tostring(record.title), tostring(record.version),
        tostring(record.highlight), tostring(record.background), tostring(record.button),
        tostring(record.text), tostring(record.dropdown), tostring(record.button_style),
        tostring(record.logo_shape), tostring(record.wallpaper), tostring(record.source_path),
        tostring(record.file), tostring(record.wallpaper_file),
        designGradientSignature(record),
    }, "\1")
end

function Theme.getActiveDesign(settings)
    local design = type(settings) == "table" and type(settings.design) == "table" and settings.design or nil
    local active_id = design and design.active_id
    local installed = design and type(design.installed) == "table" and design.installed or nil
    local record = type(active_id) == "string" and installed and installed[active_id] or nil
    if type(record) ~= "table" then return nil end
    local signature = designSignature(record)
    local entry = design_cache[record]
    if entry and entry.signature == signature then return entry.value end
    local value = Theme.normalizeDesignDefinition(record)
    design_cache[record] = { signature = signature, value = value }
    return value
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

-- Dark theme roles derived from the active theme/design. The background is a
-- near-black tinted with the theme's hue, text is a soft off-white, and the
-- accent colors are lifted until they read on the dark surface.
local function liftForDark(hex, background, minimum)
    local lifted = hex
    for _ = 1, 8 do
        if contrastRatio(lifted, background) >= minimum then break end
        lifted = mix("#FFFFFF", lifted, .22)
    end
    return lifted
end

local function darkRoles(primary, button)
    local background = mix(primary, "#111114", .09)
    local text = mix(primary, "#F1F1F4", .12)
    return {
        background = background,
        text = text,
        primary = liftForDark(primary, background, 3),
        button = liftForDark(button, background, 3),
        dropdown = mix(primary, "#1A1A1F", .10),
    }
end

local function computePalette(appdock)
    local settings = appdock and appdock.settings or nil
    local design = Theme.getActiveDesign(settings)
    local resolved_theme_id, definition = Theme.resolveDefinition(settings)
    local primary = Theme.normalizeHex(definition.primary) or BUILTIN.lavender.primary
    local background = "#FAF8FF"
    local text = "#1F1D24"
    local button = primary
    local dropdown = background
    local gradient
    if design then
        primary = design.highlight
        background = design.background
        text = design.text
        button = design.button
        dropdown = design.dropdown
        gradient = design.gradient
    elseif definition.background then
        -- A built-in theme with its own full role set (Aurora).
        primary = Theme.normalizeHex(definition.primary) or primary
        background = Theme.normalizeHex(definition.background) or background
        text = Theme.normalizeHex(definition.text) or text
        button = Theme.normalizeHex(definition.button) or primary
        dropdown = Theme.normalizeHex(definition.dropdown) or background
        gradient = Theme.normalizeGradient(definition.gradient)
    else
        gradient = definition.gradient
    end
    local night = isNight(appdock)
    if night then
        local dark = darkRoles(primary, button)
        background, text, primary, button, dropdown = dark.background, dark.text, dark.primary, dark.button, dark.dropdown
        -- The gradient keeps its character in dark mode but is pulled towards
        -- the dark background so text contrast is unaffected.
        if gradient then
            local darkened = {}
            for index, stop in ipairs(gradient.stops) do
                darkened[index] = { pos = stop.pos, hex = mix(stop.hex, background, .34) }
            end
            gradient = { angle = gradient.angle, stops = darkened }
        end
    end
    local high_contrast = settings and settings.accessibility and settings.accessibility.high_contrast == true
    if high_contrast then text = contrastInk(background) end
    -- Gradients are only drawn on color panels and never in high-contrast mode:
    -- on grayscale E-Ink they band badly and slow every refresh down.
    if high_contrast or not Device.screen:isColorEnabled() then gradient = nil end
    if gradient then
        -- Text sits on the gradient, so the readable ink is chosen against the
        -- worst (closest to the text) stop, not only against `background`.
        local worst = background
        local worst_ratio = contrastRatio(background, text)
        for _, stop in ipairs(gradient.stops) do
            local ratio = contrastRatio(stop.hex, text)
            if ratio < worst_ratio then worst, worst_ratio = stop.hex, ratio end
        end
        if worst_ratio < 4.5 then
            -- Never let the gradient make the theme's text unreadable.
            local safe = {}
            for index, stop in ipairs(gradient.stops) do
                local hex = stop.hex
                for _ = 1, 8 do
                    if contrastRatio(hex, text) >= 4.5 then break end
                    hex = mix(background, hex, .35)
                end
                safe[index] = { pos = stop.pos, hex = hex }
            end
            gradient = { angle = gradient.angle, stops = safe }
        end
    end
    local secondary = mix(primary, background, high_contrast and .62 or .42)
    local tertiary = mix(button, background, high_contrast and .72 or .56)
    local surface = high_contrast and background or mix(background, text, .93)
    local surface_variant = high_contrast and mix(text, background, .10) or mix(button, background, .25)
    local on_background = roleInk(background, text)
    local on_surface = roleInk(surface, text)
    local on_variant = roleInk(surface_variant, text)
    local on_dropdown = roleInk(dropdown, text)
    return {
        background = color(background, GRAYS.background),
        surface = color(surface, GRAYS.surface),
        surface_variant = color(surface_variant, GRAYS.surface_variant),
        primary = color(primary, GRAYS.primary),
        secondary = color(secondary, GRAYS.secondary),
        tertiary = color(tertiary, GRAYS.tertiary),
        button = color(button, GRAYS.primary),
        dropdown = color(dropdown, GRAYS.background),
        on_primary = color(roleInk(primary, text), grayscaleInk(primary)),
        on_secondary = color(roleInk(secondary, text), grayscaleInk(secondary)),
        on_tertiary = color(roleInk(tertiary, text), grayscaleInk(tertiary)),
        on_button = color(roleInk(button, text), grayscaleInk(button)),
        on_background = color(on_background, grayscaleInk(background)),
        on_surface = color(on_surface, grayscaleInk(surface)),
        on_variant = color(on_variant, grayscaleInk(surface_variant)),
        on_dropdown = color(on_dropdown, grayscaleInk(dropdown)),
        -- Compatibility aliases for Store DApps. They are deliberately colors,
        -- never the raw design string, so a DApp cannot accidentally paint
        -- unreadable text just by selecting a different AppDock color theme.
        text = color(on_background, grayscaleInk(background)),
        foreground = color(on_background, grayscaleInk(background)),
        outline = color(mix(on_surface, background, .48), GRAYS.outline),
        track = color(mix(roleInk(button, text), background, .52), GRAYS.track),
        -- nil when the active theme/design has no gradient (or the panel is
        -- grayscale / high contrast). Stops are hex strings; angle is CSS-style.
        gradient = gradient,
        primary_hex = primary,
        background_hex = background,
        text_hex = on_background,
        high_contrast = high_contrast,
        -- The same roles as plain hex strings. Surfaces that cannot use the
        -- Blitbuffer values directly (the dithered keyboard, the dialogs'
        -- translucent veil) derive their own colors from these.
        hex = {
            background = background, surface = surface, surface_variant = surface_variant,
            primary = primary, secondary = secondary, tertiary = tertiary,
            button = button, dropdown = dropdown,
            on_primary = roleInk(primary, text), on_button = roleInk(button, text),
            on_background = on_background, on_surface = on_surface,
            on_variant = on_variant, on_dropdown = on_dropdown,
            outline = mix(on_surface, background, .48),
        },
    }
end

-- The palette is a pure function of the theme settings and the panel's color
-- mode, so it is computed once per distinct combination instead of on every
-- homescreen build, dialog and DApp frame. A shallow copy is returned because
-- Store DApps receive this table and must not be able to alter the shared one.
local palette_cache, palette_cache_key = nil, nil

-- The running plugin instance registers itself here so surfaces that are
-- created without an appdock reference (dialogs, the keyboard) still follow the
-- active color theme.
local bound_appdock
function Theme.bind(appdock) bound_appdock = appdock end

function Theme.getPalette(appdock)
    appdock = appdock or bound_appdock
    local settings = appdock and appdock.settings or nil
    local design = Theme.getActiveDesign(settings)
    local resolved_theme_id, definition = Theme.resolveDefinition(settings)
    local high_contrast = settings and settings.accessibility and settings.accessibility.high_contrast == true
    local key = table.concat({
        Device.screen:isColorEnabled() and "c" or "g",
        isNight(appdock) and "d" or "l",
        high_contrast and "h" or "n",
        tostring(resolved_theme_id), tostring(definition and definition.primary),
        Theme.gradientSignature(definition and definition.gradient),
        design and designSignature(design) or "-",
    }, "\1")
    if palette_cache_key ~= key or not palette_cache then
        palette_cache = computePalette(appdock)
        palette_cache_key = key
    end
    local copy = {}
    for name, value in pairs(palette_cache) do copy[name] = value end
    if type(copy.hex) == "table" then
        local hex = {}
        for name, value in pairs(copy.hex) do hex[name] = value end
        copy.hex = hex
    end
    return copy
end

-- The active gradient ({ angle, stops = { {pos, hex} } }) or nil.
function Theme.getGradient(appdock)
    return Theme.getPalette(appdock).gradient
end

-- Absolute path of the wallpaper bundled with the active built-in theme
-- (Aurora), or nil. A Store design brings its own wallpaper and wins.
function Theme.getThemeWallpaper(appdock)
    appdock = appdock or bound_appdock
    local settings = appdock and appdock.settings or nil
    if Theme.getActiveDesign(settings) then return nil end
    local _, definition = Theme.resolveDefinition(settings)
    if type(definition.wallpaper) ~= "string" or definition.wallpaper == "" then return nil end
    return MODULE_DIR .. definition.wallpaper
end

-- Role colors of the active theme as hex strings (see computePalette).
function Theme.getHexRoles(appdock)
    return Theme.getPalette(appdock).hex
end

-- Small public color helpers for surfaces that build their own palette.
Theme.mixHex = mix
Theme.inkFor = contrastInk
Theme.toColor = color
Theme.isNight = function(appdock) return isNight(appdock or bound_appdock) end

function Theme.createCustom(settings, title, hex, gradient_to)
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
    local record = { title = label, primary = normalized }
    -- Optional second color: the custom theme then fades from its first color
    -- into this one.
    local second = Theme.normalizeHex(gradient_to)
    if second then record.gradient = Theme.normalizeGradient({ from = normalized, to = second, angle = 170 }) end
    settings.theme.custom[id] = record
    settings.theme.selected = id
    return id
end

Theme._test = {
    contrastRatio = contrastRatio,
    readableInk = readableInk,
    roleInk = roleInk,
}

return Theme
