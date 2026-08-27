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
package.preload["socket.url"] = function()
    local function parse(url)
        local scheme, authority, tail = url:match("^(https?)://([^/]+)(.*)$")
        if not scheme then return nil end
        local path, query = tail:match("^([^?]*)%??(.*)$")
        return { scheme = scheme, host = authority:gsub(":%d+$", ""), path = path == "" and "/" or path, query = query ~= "" and query or nil }
    end
    return {
        parse = parse,
        absolute = function(base, relative)
            if relative:match("^https?://") then return relative end
            local parsed = assert(parse(base))
            return parsed.scheme .. "://" .. parsed.host .. (relative:match("^/") and relative or "/" .. relative)
        end,
        unescape = function(value) return (value:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)) end,
    }
end

local Browser = dofile(os.getenv("BROWSER_SOURCE") or "/home/ubuntu/appdock-antigravity-release/appdock_browser.lua")
local html = [[<style>body { color: #123456; } @import url(evil.css);</style><form method="get" action="/search"><input type="search" name="q" placeholder="Search books"><button>Find</button></form><form method="post"><input name="x"></form><script>evil()</script>]]
local cleaned = Browser._test.sanitizeHtml(html)
assert(not cleaned:find("evil%(%") and not cleaned:find("<form", 1, true), "Browser HTML sanitization must remove scripts and rendered web forms")
local css = Browser._test.sanitizeCss("body { color: #123456; background: url(track.png); } @import url(evil.css); @font-face { src: url(font.woff); }")
assert(css:find("#123456", 1, true) and not css:find("url", 1, true) and not css:find("@import", 1, true), "Browser CSS sanitization must preserve readable declarations and remove resource loads")
assert(Browser._test.inlineStylesheets(html):find("#123456", 1, true), "Browser must retain safe embedded CSS rules")
local forms = Browser._test.extractSimpleForms(html, "https://example.org/page")
assert(#forms == 1 and forms[1].action == "https://example.org/search" and forms[1].name == "q" and forms[1].label == "Find", "Browser must expose only safe simple GET form actions")
local rich_html = [[<!DOCTYPE html><html><head><title>Ignored</title><style>p { color: blue; }</style><script>evil()</script><link rel="stylesheet" href="evil.css" /></head><body><main style="background:url(track.png); color:#334455"><article><h1>Article</h1><blockquote>Quoted <b>text</b></blockquote><details><summary>More</summary><p>Readable detail</p></details><figure><img data-src="https://example.org/cover.jpg" alt="Cover" /><figcaption>A caption</figcaption></figure><iframe src="https://evil.example"></iframe><object>unsafe</object><a href="javascript:evil()">unsafe</a><br>after</article></main></body></html>]]
local prepared = Browser._test.prepareDocument(rich_html)
assert(not prepared:find("<head", 1, true) and not prepared:find("<script", 1, true) and not prepared:find("<iframe", 1, true) and not prepared:find("<object", 1, true) and not prepared:find("javascript:", 1, true), "Parser must remove inactive document, script, embedded-object and dangerous-link content")
assert(prepared:find("appdock-main", 1, true) and prepared:find("appdock-details", 1, true) and prepared:find("appdock-details-title", 1, true), "Parser must preserve semantic main and details content as readable E-Ink blocks")
assert(prepared:find("src=\"https://example.org/cover.jpg\"", 1, true) and not prepared:find("url%(", 1), "Parser must normalize safe lazy images and remove inline resource-loading styles")
assert(prepared:find("<blockquote", 1, true), "Parser must retain readable quotes")
assert(prepared:find("<figcaption", 1, true), "Parser must retain readable captions")
assert(prepared:find("<br/>", 1, true), "Parser must normalize readable line breaks")
local google_html = [[<html><body><a href="/url?q=https%3A%2F%2Fkoreader.rocks%2F"><h3>KOReader</h3></a><a href="https://www.google.com/search?q=other"><h3>Internal Google</h3></a></body></html>]]
assert(Browser._test.isGoogleSearch("https://www.google.com/search?q=KOReader") and Browser._test.unwrapGoogle("https://www.google.com/url?q=https%3A%2F%2Fkoreader.rocks%2F") == "https://koreader.rocks/", "Browser must recognize direct Google search pages and unwrap a Google result target")
local google_results = Browser._test.extractGoogleResults(google_html, "https://www.google.com/search?q=KOReader")
assert(#google_results == 1 and google_results[1].title == "KOReader" and google_results[1].url == "https://koreader.rocks/", "Browser must present external Google result links as direct readable targets")
assert(Browser._test.googleBlocked("Please enable JavaScript and complete CAPTCHA") and Browser._test.googleBlocked("<a href=\"/httpservice/retry/enablejs?sei=abc\">Continue</a>"), "Browser must identify Google verification and JavaScript-gate responses rather than attempting to bypass them")
assert(Browser._test.renderGoogleResults("KOReader", google_results):find("koreader.rocks", 1, true), "Browser must render Google results as browser-owned readable HTML cards")
print("Browser test: OK")
