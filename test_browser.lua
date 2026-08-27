local function class(proto)
    proto = proto or {}; proto.__index = proto
    function proto:extend(child) child = child or {}; child.__index = child; setmetatable(child, { __index = self }); return child end
    function proto:new(values) local value = values or {}; setmetatable(value, self); if value.init then value:init() end; return value end
    return proto
end

local Widget = class({})
local WidgetContainer = Widget:extend({})
local InputContainer = WidgetContainer:extend({})
local function widgetModule() return WidgetContainer end

package.preload["ffi/blitbuffer"] = function() return { COLOR_WHITE = "white", COLOR_BLACK = "black", COLOR_DARK_GRAY = "dark", COLOR_LIGHT_GRAY = "light", COLOR_GRAY = "gray", COLOR_GRAY_8 = "g8", ColorRGB32 = function() return "rgb" end } end
package.preload["device"] = function() return { screen = { scaleBySize = function(_, value) return value end, isColorEnabled = function() return false end } } end
package.preload["datastorage"] = function() return { getDataDir = function() return "/tmp" end } end
package.preload["ui/font"] = function() return { getFace = function(_, name, size) return { name = name, size = size } end } end
package.preload["ui/geometry"] = function() return { new = function(_, values) return values end } end
package.preload["ui/gesturerange"] = function() return { new = function(_, values) return values end } end
package.preload["ui/widget/container/centercontainer"] = widgetModule
package.preload["ui/widget/container/framecontainer"] = widgetModule
package.preload["ui/widget/horizontalspan"] = widgetModule
package.preload["ui/widget/container/inputcontainer"] = function() return InputContainer end
package.preload["ui/widget/inputdialog"] = widgetModule
package.preload["ui/widget/overlapgroup"] = widgetModule
package.preload["ui/widget/scrollhtmlwidget"] = widgetModule
package.preload["ui/widget/textwidget"] = widgetModule
package.preload["ui/uimanager"] = function() return { show = function() end, close = function() end } end
package.preload["ui/widget/container/widgetcontainer"] = function() return WidgetContainer end
package.preload["appdock_theme"] = function() return { fitLabel = function(value) return value end } end
package.preload["gettext"] = function() return function(value) return value end end
package.preload["util"] = function() return { urlEncode = function(value) return value end } end
package.preload["socket.url"] = function() return { absolute = function(base, relative) if relative:match("^https?://") then return relative end return base:match("^(https?://[^/]+)") .. relative end } end

local Browser = dofile(os.getenv("BROWSER_SOURCE") or "/home/ubuntu/appdock-antigravity-release/appdock_browser.lua")
local html = [[<style>body { color: #123456; } @import url(evil.css);</style><form method="get" action="/search"><input type="search" name="q" placeholder="Search books"><button>Find</button></form><form method="post"><input name="x"></form><script>evil()</script>]]
local cleaned = Browser._test.sanitizeHtml(html)
assert(not cleaned:find("evil%(%") and not cleaned:find("<form", 1, true), "Browser HTML sanitization must remove scripts and rendered web forms")
local css = Browser._test.sanitizeCss("body { color: #123456; background: url(track.png); } @import url(evil.css); @font-face { src: url(font.woff); }")
assert(css:find("#123456", 1, true) and not css:find("url", 1, true) and not css:find("@import", 1, true), "Browser CSS sanitization must preserve readable declarations and remove resource loads")
assert(Browser._test.inlineStylesheets(html):find("#123456", 1, true), "Browser must retain safe embedded CSS rules")
local forms = Browser._test.extractSimpleForms(html, "https://example.org/page")
assert(#forms == 1 and forms[1].action == "https://example.org/search" and forms[1].name == "q" and forms[1].label == "Find", "Browser must expose only safe simple GET form actions")
print("Browser test: OK")
