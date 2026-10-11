local color = { COLOR_WHITE = 1, COLOR_LIGHT_GRAY = 2, COLOR_GRAY_8 = 3, COLOR_GRAY_7 = 4, COLOR_DARK_GRAY = 5, COLOR_BLACK = 6, COLOR_GRAY = 7, ColorRGB32 = function(r, g, b) return string.format("%d,%d,%d", r, g, b) end }
package.preload["ffi/blitbuffer"] = function() return color end
package.preload["device"] = function() return { screen = { isColorEnabled = function() return true end, scaleBySize = function(_, value) return value end } } end
local Theme = assert(loadfile("appdock.koplugin/appdock_theme.lua"))()
local ink = Theme._test.readableInk("#808080", "#777777")
assert(Theme._test.contrastRatio("#808080", ink) >= 4.5, "Theme text must fall back to a WCAG-readable ink on low-contrast design backgrounds")
assert(#Theme.getThemeList({}) >= 4 and Theme.getActiveDesign({}) == nil, "Theme helpers must tolerate incomplete persisted settings")
local palette = Theme.getPalette({ settings = { theme = { selected = "lavender", custom = {} }, design = { active_id = "bad", installed = { bad = { id = "bad", title = "Bad", highlight = "#888888", background = "#808080", button = "#808080", text = "#777777", dropdown = "#808080" } } } } })
assert(palette and palette.background_hex == "#808080", "Low-contrast designs must retain their selected background while fixing text roles")
print("theme-contrast-ok")
