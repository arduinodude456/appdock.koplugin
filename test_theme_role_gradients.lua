-- Role gradients (9.8.0): themes may define gradients for single color roles.
local color = { COLOR_WHITE = 1, COLOR_LIGHT_GRAY = 2, COLOR_GRAY_8 = 3, COLOR_GRAY_7 = 4, COLOR_DARK_GRAY = 5, COLOR_BLACK = 6, COLOR_GRAY = 7, ColorRGB32 = function(r, g, b) return string.format("%d,%d,%d", r, g, b) end }
package.preload["ffi/blitbuffer"] = function() return color end
local color_enabled = true
package.preload["device"] = function() return { screen = { isColorEnabled = function() return color_enabled end, scaleBySize = function(_, value) return value end } } end
local plugin_dir = os.getenv("APPDOCK_PLUGIN_DIR") or "appdock.koplugin/"
local Theme = assert(loadfile(plugin_dir .. "appdock_theme.lua"))()

local function paletteFor(settings) return Theme.getPalette({ settings = settings }) end
local aurora_settings = { theme = { selected = "aurora", custom = {}, night_mode = false } }
local roles = { primary = "on_primary", secondary = "on_secondary", tertiary = "on_tertiary", button = "on_button", surface = "on_surface", surface_variant = "on_variant" }

for _, night in ipairs({ false, true }) do
    aurora_settings.theme.night_mode = night
    local palette = paletteFor(aurora_settings)
    assert(palette.role_gradients, "Aurora must carry role gradients (night=" .. tostring(night) .. ")")
    for role, ink in pairs(roles) do
        local gradient = palette.role_gradients[role]
        assert(gradient and #gradient.stops == 3, "Aurora defines a 3-stop " .. role .. " gradient")
        for _, stop in ipairs(gradient.stops) do
            assert(Theme._test.contrastRatio(stop.hex, palette.hex[ink]) >= math.min(4.5, Theme._test.contrastRatio(palette.hex[role == "surface_variant" and "surface_variant" or role], palette.hex[ink])),
                string.format("%s stop %s must keep %s readable (night=%s)", role, stop.hex, ink, tostring(night)))
        end
    end
    assert(Theme.getRoleGradient({ settings = aurora_settings }, "button") ~= nil, "Theme.getRoleGradient returns the button gradient")
end

-- Roles without a gradient simply have none; other themes are unaffected.
local lavender = paletteFor({ theme = { selected = "lavender", custom = {} } })
assert(lavender.role_gradients == nil, "Themes without role gradients keep flat colors")

-- Custom themes can define them too; invalid entries are dropped.
local custom = paletteFor({ theme = { selected = "custom_x", custom = { custom_x = { title = "X", primary = "#88AAFF", gradients = { button = "#88AAFF,#AA88FF", bogus = "#000000,#111111", surface = "nonsense" } } } } })
assert(custom.role_gradients and custom.role_gradients.button and not custom.role_gradients.bogus and not custom.role_gradients.surface, "Custom role gradients are normalized and filtered")

-- Never on grayscale panels or in high contrast.
aurora_settings.theme.night_mode = false
aurora_settings.accessibility = { high_contrast = true }
assert(paletteFor(aurora_settings).role_gradients == nil, "High contrast disables role gradients")
aurora_settings.accessibility = nil
color_enabled = false
local gray = assert(loadfile(plugin_dir .. "appdock_theme.lua"))()
assert(gray.getPalette({ settings = aurora_settings }).role_gradients == nil, "Grayscale panels get no role gradients")
print("theme-role-gradients-ok")
