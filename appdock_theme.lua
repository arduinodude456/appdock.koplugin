--[[--
Central visual language for AppDock.

The palette is deliberately role-based: every surface, text color and control
gets a predictable contrast role on both colour and grayscale E-Ink screens.
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

function Theme.normalizeHex(value)
    if type(value) ~= "string" then return nil end
    local hex = value:gsub("^%s+", ""):gsub("%s+$", "")
    if hex:match("^%x%x%x%x%x%x$") then hex = "#" .. hex end
    if not hex:match("^#%x%x%x%x%x%x$") then return nil end
    return hex:upper()
end

local function rgb(hex)
    local value = Theme.normalizeHex(hex)
    if not value then return nil end
    return tonumber(value:sub(2, 3), 16), tonumber(value:sub(4, 5), 16), tonumber(value:sub(6, 7), 16)
end

local function toHex(red, green, blue)
    return string.format("#%02X%02X%02X",
        math.max(0, math.min(255, math.floor(red + .5))),
        math.max(0, math.min(255, math.floor(green + .5))),
        math.max(0, math.min(255, math.floor(blue + .5))))
end

local function mix(first, second, first_weight)
    local r1, g1, b1 = rgb(first)
    local r2, g2, b2 = rgb(second)
    local second_weight = 1 - first_weight
    return toHex(r1 * first_weight + r2 * second_weight,
        g1 * first_weight + g2 * second_weight,
        b1 * first_weight + b2 * second_weight)
end

local function contrastInk(hex)
    local red, green, blue = rgb(hex)
    local luminance = (red * 299 + green * 587 + blue * 114) / 255000
    return luminance > .58 and "#1F1D24" or "#FFFFFF"
end

local function color(hex, grayscale)
    if not Device.screen:isColorEnabled() then return grayscale end
    local red, green, blue = rgb(hex)
    return Blitbuffer.ColorRGB32(red, green, blue, 0xFF)
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
            local finish, count = 1, 0
            while finish <= #text and count < visible do
                local next_byte = text:byte(finish) or 0
                finish = finish + (next_byte >= 240 and 4 or (next_byte >= 224 and 3 or (next_byte >= 192 and 2 or 1)))
                count = count + 1
            end
            return text:sub(1, finish - 1) .. "…"
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

local TEXT_SCALES = { [.5] = true, [.75] = true, [.9] = true, [1] = true, [1.15] = true, [1.3] = true, [1.5] = true }
local function textScale(appdock)
    local value = appdock and appdock.settings and appdock.settings.accessibility
        and tonumber(appdock.settings.accessibility.text_scale) or 1
    return TEXT_SCALES[value] and value or 1
end

function Theme.textSize(appdock, logical_size, minimum)
    local base = Device.screen:scaleBySize(tonumber(logical_size) or 10)
    local floor_size = Device.screen:scaleBySize(tonumber(minimum) or 7)
    return math.max(floor_size, math.floor(base * textScale(appdock) + .5))
end

function Theme.adjustText(appdock, scaled_size, minimum)
    return math.max(tonumber(minimum) or 1, math.floor((tonumber(scaled_size) or 1) * textScale(appdock) + .5))
end

function Theme.centeredStack(container_height, items, gap, padding)
    local heights, total = {}, 0
    local safe_gap = (tonumber(gap) or 0) > 0 and math.max(1, math.floor((tonumber(gap) or 0) * .55 + .5)) or 0
    for index, item in ipairs(items or {}) do
        local size = type(item) == "table" and type(item.getSize) == "function" and item:getSize() or nil
        heights[index] = math.max(0, math.floor((size and size.h or tonumber(item) or 0) + .5))
        total = total + heights[index]
    end
    if #heights > 1 then total = total + safe_gap * (#heights - 1) end
    local y = math.max(tonumber(padding) or 0, math.floor(((tonumber(container_height) or 0) - total) / 2))
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
        themes[#themes + 1] = { id = id, title = definition.title, primary = definition.primary, builtin = true }
    end
    table.sort(themes, function(left, right) return left.title < right.title end)
    return themes
end

function Theme.getThemeList(settings)
    local themes = Theme.getBuiltinThemes()
    for id, definition in pairs((settings and settings.theme and settings.theme.custom) or {}) do
        if Theme.normalizeHex(definition.primary) then
            themes[#themes + 1] = { id = id, title = definition.title or id, primary = definition.primary, builtin = false }
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

function Theme.normalizeDesignDefinition(definition)
    if type(definition) ~= "table" then return nil end
    local id = type(definition.id) == "string" and definition.id:match("^%s*(.-)%s*$") or ""
    local title = type(definition.title) == "string" and definition.title:match("^%s*(.-)%s*$") or ""
    local values = { highlight = Theme.normalizeHex(definition.highlight), background = Theme.normalizeHex(definition.background), button = Theme.normalizeHex(definition.button), text = Theme.normalizeHex(definition.text), dropdown = Theme.normalizeHex(definition.dropdown) }
    if not id:match("^[%w_%-]+$") or title == "" or #title > 48 then return nil end
    for _, value in pairs(values) do if not value then return nil end end
    return {
        id = id, title = title, version = type(definition.version) == "string" and definition.version or nil,
        highlight = values.highlight, background = values.background, button = values.button,
        text = values.text, dropdown = values.dropdown,
        button_style = definition.button_style == "3d" and "3d" or "rounded",
        logo_shape = definition.logo_shape == "circle" and "circle" or "rounded",
        wallpaper = type(definition.wallpaper) == "string" and definition.wallpaper or "",
        source_path = type(definition.source_path) == "string" and definition.source_path or "",
        file = type(definition.file) == "string" and definition.file or "",
        wallpaper_file = type(definition.wallpaper_file) == "string" and definition.wallpaper_file or "",
    }
end

function Theme.getActiveDesign(settings)
    local design = settings and settings.design
    local active_id = design and design.active_id
    local record = type(active_id) == "string" and design.installed and design.installed[active_id] or nil
    return Theme.normalizeDesignDefinition(record)
end

function Theme.getAppLogoShape(appdock)
    local settings = appdock and appdock.settings
    local design = Theme.getActiveDesign(settings)
    if design then return design.logo_shape end
    return settings and settings.layout and settings.layout.logo_shape == "circle" and "circle" or "rounded"
end

function Theme.getButtonFrameStyle(appdock, height, rounded_radius)
    local design = Theme.getActiveDesign(appdock and appdock.settings)
    if not design or design.button_style ~= "3d" then return { radius = rounded_radius, bordersize = 0, color = nil } end
    local border = math.max(1, Device.screen:scaleBySize(1))
    return { radius = math.max(border * 2, math.floor((tonumber(height) or 20) * .14)), bordersize = border, color = color(mix(design.text, design.background, .46), GRAYS.outline) }
end

function Theme.getPalette(appdock)
    local settings = appdock and appdock.settings or nil
    local design = Theme.getActiveDesign(settings)
    local _, definition = Theme.resolveDefinition(settings)
    local primary, background, text, button, dropdown = Theme.normalizeHex(definition.primary) or BUILTIN.lavender.primary, "#FAF8FF", "#1F1D24", nil, nil
    button, dropdown = primary, background
    if design then primary, background, text, button, dropdown = design.highlight, design.background, design.text, design.button, design.dropdown end
    if settings and settings.accessibility and settings.accessibility.high_contrast then text = contrastInk(background) end
    local high_contrast = settings and settings.accessibility and settings.accessibility.high_contrast == true
    local secondary = mix(primary, background, high_contrast and .62 or .42)
    local tertiary = mix(button, background, high_contrast and .72 or .56)
    local surface = high_contrast and background or mix(background, text, .93)
    local surface_variant = high_contrast and mix(text, background, .10) or mix(button, background, .25)
    return {
        background = color(background, GRAYS.background), surface = color(surface, GRAYS.surface), surface_variant = color(surface_variant, GRAYS.surface_variant),
        primary = color(primary, GRAYS.primary), secondary = color(secondary, GRAYS.secondary), tertiary = color(tertiary, GRAYS.tertiary),
        button = color(button, GRAYS.primary), dropdown = color(dropdown, GRAYS.background),
        on_primary = color(design and text or contrastInk(primary), GRAYS.on_primary), on_secondary = color(design and text or contrastInk(secondary), GRAYS.on_secondary),
        on_tertiary = color(design and text or contrastInk(tertiary), GRAYS.on_tertiary), on_button = color(design and text or contrastInk(button), GRAYS.on_primary),
        on_surface = color(text, GRAYS.on_surface), on_variant = color(mix(text, background, .70), GRAYS.on_variant),
        outline = color(mix(text, background, .48), GRAYS.outline), track = color(mix(button, background, .52), GRAYS.track),
        primary_hex = primary, high_contrast = high_contrast,
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
    while settings.theme.custom[id] do id, suffix = "custom_" .. base_id .. "_" .. suffix, suffix + 1 end
    settings.theme.custom[id] = { title = label, primary = normalized }
    settings.theme.selected = id
    return id
end

return Theme
