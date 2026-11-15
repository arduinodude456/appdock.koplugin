local color = { COLOR_WHITE = 1, COLOR_LIGHT_GRAY = 2, COLOR_GRAY_8 = 3, COLOR_GRAY_7 = 4, COLOR_DARK_GRAY = 5, COLOR_BLACK = 6, COLOR_GRAY = 7, ColorRGB32 = function(r, g, b) return string.format("%d,%d,%d", r, g, b) end }
package.preload["ffi/blitbuffer"] = function() return color end
local color_enabled = true
package.preload["device"] = function() return { screen = { isColorEnabled = function() return color_enabled end, scaleBySize = function(_, value) return value end } } end
local Theme = assert(loadfile("appdock.koplugin/appdock_theme.lua"))()
local ink = Theme._test.readableInk("#808080", "#777777")
assert(Theme._test.contrastRatio("#808080", ink) >= 4.5, "Theme text must fall back to a WCAG-readable ink on low-contrast design backgrounds")
assert(#Theme.getThemeList({}) >= 4 and Theme.getActiveDesign({}) == nil, "Theme helpers must tolerate incomplete persisted settings")
local palette = Theme.getPalette({ settings = { theme = { selected = "lavender", custom = {} }, design = { active_id = "bad", installed = { bad = { id = "bad", title = "Bad", highlight = "#888888", background = "#808080", button = "#808080", text = "#777777", dropdown = "#808080" } } } } })
assert(palette and palette.background_hex == "#808080", "Low-contrast designs must retain their selected background while fixing text roles")
assert(palette.text == palette.on_background and palette.foreground == palette.on_background and palette.on_dropdown, "Store DApps receive readable compatibility foreground roles for every themed surface")
local aurora = Theme.getPalette({ settings = { theme = { selected = "aurora", custom = {}, night_mode = false } } })
assert(aurora.gradient and #aurora.gradient.stops == 4, "The built-in Aurora theme must build its palette from raw color-string stops")
assert(Theme.gradientSignature({ angle = 168, stops = { "#050E26", "#0A3550", "#117A68", "#3F3B8F" } }) ~= "-", "Raw gradient stop strings must produce a valid cache signature")
color_enabled = false
local gray_theme = assert(loadfile("appdock.koplugin/appdock_theme.lua"))()
local forest = gray_theme.getPalette({ settings = { theme = { selected = "lavender", custom = {} }, design = { active_id = "forest", installed = { forest = { id = "forest", title = "Forest", highlight = "#A5D6A7", background = "#122219", button = "#2D6745", text = "#EFF8E9", dropdown = "#183125" } } } } })
assert(forest.on_surface == color.COLOR_WHITE and forest.on_variant == color.COLOR_WHITE, "dark Forest surfaces must use white text on grayscale readers")
local gray_dark = gray_theme.getPalette({ settings = { theme = { selected = "lavender", custom = {}, night_mode = true } } })
assert((gray_dark.background == color.COLOR_BLACK or gray_dark.background == color.COLOR_DARK_GRAY) and gray_dark.on_surface == color.COLOR_WHITE, "AppDock's dark theme must remain dark and readable on grayscale readers")
-- AppDock's own dark mode uses final palette colors and ignores KOReader's
-- global night-mode/inversion state.
color_enabled = true
package.loaded["device"].screen.night_mode = true
local night = assert(loadfile("appdock.koplugin/appdock_theme.lua"))()
local settings = { settings = { theme = { selected = "lavender", custom = {}, night_mode = false } } }
local light = night.getPalette(settings)
assert(light.hex.background == "#FAF8FF", "KOReader night mode must not enable AppDock's dark palette")
settings.settings.theme.night_mode = true
local dark = night.getPalette(settings)
local function lum(hex) return night._test.contrastRatio(hex, "#000000") end
local function colorFromHex(hex)
    return string.format("%d,%d,%d", tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16))
end
assert(lum(dark.hex.background) < 1.6, "Dark mode background must be near black")
assert(night._test.contrastRatio(dark.hex.on_background, dark.hex.background) >= 7, "Dark mode text must be clearly readable")
assert(night._test.contrastRatio(dark.hex.primary, dark.hex.background) >= 3, "Dark mode accents must be visible on the dark surface")
assert(dark.hex.background ~= "#FAF8FF", "Dark mode must not reuse the light palette")
assert(dark.background == colorFromHex(dark.hex.background), "Dark palette colors must be painted directly without pre-inversion")
print("theme-contrast-ok")
