--[[--
A compact, JavaScript-free browser engine for AppDock DApps.
It accepts only HTTP(S), fetches server-rendered HTML, and renders it through
KOReader's MuPDF-backed ScrollHtmlWidget.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local OverlapGroup = require("ui/widget/overlapgroup")
local ScrollHtmlWidget = require("ui/widget/scrollhtmlwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Theme = require("appdock_theme")
local util = require("util")
local _ = require("gettext")

local Screen = Device.screen
local Browser = {}
Browser.__index = Browser

local MAX_BODY_BYTES = 2 * 1024 * 1024
local MAX_IMAGE_BYTES = 1536 * 1024
local MAX_IMAGE_TOTAL_BYTES = 5 * 1024 * 1024
local MAX_IMAGES_PER_PAGE = 8
local MAX_CSS_BYTES = 192 * 1024
local MAX_STYLESHEETS = 3
local REQUEST_TIMEOUT = 12
local REQUEST_MAX_TIME = 30
local DUCKDUCKGO_HTML = "https://html.duckduckgo.com/html/?q="
local GOOGLE_SEARCH = "https://www.google.com/search?gbv=1&filter=0&num=10&hl=de&q="
local BROWSER_USER_AGENT = "Mozilla/5.0 (Linux; Android 12; eReader) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36"

local BrowserButton = InputContainer:extend{
    title = nil,
    callback = nil,
    width = nil,
    height = nil,
    background = nil,
    foreground = nil,
    dimen = nil,
}

local function scale(value)
    return Screen:scaleBySize(value)
end

local function color(r, g, b, grayscale)
    if Screen:isColorEnabled() then
        return Blitbuffer.ColorRGB32(r, g, b, 0xFF)
    end
    return grayscale
end

local PALETTE = {
    surface = color(242, 240, 247, Blitbuffer.COLOR_LIGHT_GRAY),
    primary = color(214, 227, 255, Blitbuffer.COLOR_GRAY_8),
    on_primary = color(23, 59, 111, Blitbuffer.COLOR_DARK_GRAY),
    on_surface = color(31, 29, 36, Blitbuffer.COLOR_BLACK),
    on_variant = color(76, 73, 84, Blitbuffer.COLOR_DARK_GRAY),
    outline = color(121, 117, 128, Blitbuffer.COLOR_GRAY),
    background = color(250, 248, 255, Blitbuffer.COLOR_WHITE),
}

local BROWSER_CSS = [[
  html, body { margin: 0; padding: 0; font-family: sans-serif; line-height: 1.35; }
  body { color: #202020; background: #ffffff; }
  h1 { font-size: 1.45em; margin: 0.7em 0 0.35em; border-bottom: 1px solid #777777; padding-bottom: 0.2em; }
  h2 { font-size: 1.24em; margin: 0.9em 0 0.35em; }
  h3 { font-size: 1.08em; margin: 0.8em 0 0.3em; }
  h4, h5, h6 { font-size: 1em; margin: 0.7em 0 0.25em; }
  p, li { margin: 0.32em 0; }
  ul, ol { margin: 0.45em 0 0.55em 1.2em; padding: 0; }
  blockquote { margin: 0.65em 0; padding: 0.2em 0 0.2em 0.75em; border-left: 0.35em solid #777777; color: #454545; }
  dl { margin: 0.55em 0; } dt { font-weight: bold; margin-top: 0.45em; } dd { margin: 0.16em 0 0.35em 1em; }
  figure { margin: 0.65em 0; } figcaption { color: #555555; font-size: 0.88em; margin: 0.25em 0; }
  hr { border: 0; border-top: 1px solid #888888; margin: 0.9em 0; }
  mark { background: #e5e5e5; color: #202020; }
  a { color: #173b6f; text-decoration: underline; }
  pre, code { white-space: pre-wrap; }
  img { display: block; max-width: 100%; height: auto; margin: 0.7em auto; }
  table { width: 100%; border-collapse: collapse; margin: 0.75em 0; font-size: 0.90em; }
  caption { font-weight: bold; text-align: left; margin: 0.3em 0; }
  th, td { border: 1px solid #555555; padding: 0.28em 0.35em; vertical-align: top; }
  th { background: #e9e9e9; font-weight: bold; }
  .appdock-image-fallback { color: #555555; font-style: italic; }
  .appdock-google-result { border: 1px solid #777777; padding: 0.35em 0.5em; margin: 0.45em 0; }
  .appdock-google-result small { color: #555555; word-break: break-all; }
  .appdock-google-notice { border-left: 0.35em solid #777777; padding-left: 0.6em; color: #444444; }
  .appdock-main { max-width: 100%; }
  .appdock-details { border: 1px solid #999999; padding: 0.25em 0.5em; margin: 0.55em 0; }
  .appdock-details-title { margin-top: 0.2em; }
  video, audio, canvas, svg, iframe, form, button, input, select, textarea { display: none; }
]]

local function emptySizedWidget(width, height)
    return CenterContainer:new{
        dimen = Geom:new{ w = width, h = height },
        HorizontalSpan:new{ width = 0 },
    }
end

function BrowserButton:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local label_size = math.max(scale(8), math.min(scale(12), math.floor(self.height * .42)))
    local label = Theme.fitLabel(self.title or "", self.width, label_size, scale(12))
    self[1] = FrameContainer:new{
        width = self.width,
        height = self.height,
        padding = 0,
        bordersize = 0,
        radius = math.floor(self.height * 0.32),
        background = self.background or PALETTE.surface,
        CenterContainer:new{
            dimen = Geom:new{ w = self.width, h = self.height },
            TextWidget:new{
                text = label,
                face = Font:getFace("smallinfofont", label_size),
                fgcolor = self.foreground or PALETTE.on_surface,
                bold = true,
                max_width = self.width - scale(12),
            },
        },
    }
    self.ges_events = {
        TapBrowserAction = { GestureRange:new{ ges = "tap", range = self.dimen } },
    }
end

function BrowserButton:paintTo(bb, x, y)
    local range = self.ges_events.TapBrowserAction[1].range
    range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    return InputContainer.paintTo(self, bb, x, y)
end

function BrowserButton:onTapBrowserAction()
    if self.callback then self.callback() end
    return true
end

local function isHttpUrl(url)
    return type(url) == "string" and url:match("^https?://") ~= nil
end

local function normalizeUrl(value)
    if type(value) ~= "string" then return nil, _("Enter a URL or search query.") end
    local url = value:gsub("^%s+", ""):gsub("%s+$", "")
    if url == "" then return nil, _("Enter a URL or search query.") end
    local explicit_scheme = url:match("^[%a][%w+.-]*:")
    if explicit_scheme and not url:match("^https?://") then
        return nil, _("Only HTTP and HTTPS addresses are supported.")
    end
    if not url:match("^[%a][%w+.-]*://") then
        url = "https://" .. url
    end
    if not isHttpUrl(url) then
        return nil, _("Only HTTP and HTTPS addresses are supported.")
    end
    return url
end

local function unwrapDuckDuckGo(url)
    local socket_url = require("socket.url")
    local parsed = socket_url.parse(url)
    if not parsed or not parsed.host or not parsed.host:match("duckduckgo%.com$") then return url end
    if not parsed.path or not parsed.path:match("^/l/") or not parsed.query then return url end
    for key, value in parsed.query:gmatch("([^&=]+)=([^&]*)") do
        if key == "uddg" then
            return socket_url.unescape(value)
        end
    end
    return url
end

local function isGoogleHost(host)
    host = type(host) == "string" and host:lower() or ""
    return host:match("^google%.[%a%.]+$") ~= nil or host:match("%.google%.[%a%.]+$") ~= nil
end

local function isGoogleSearch(url)
    local socket_url = require("socket.url")
    local parsed = socket_url.parse(url)
    return parsed and isGoogleHost(parsed.host) and parsed.path == "/search" or false
end

local function queryParameter(url, wanted)
    local socket_url = require("socket.url")
    local parsed = socket_url.parse(url)
    if not parsed or not parsed.query then return nil end
    for key, value in parsed.query:gmatch("([^&=]+)=([^&]*)") do
        if socket_url.unescape(key) == wanted then return socket_url.unescape(value:gsub("+", " ")) end
    end
    return nil
end

local function unwrapGoogle(url)
    local socket_url = require("socket.url")
    local parsed = socket_url.parse(url)
    if not parsed or not isGoogleHost(parsed.host) or parsed.path ~= "/url" then return url end
    return queryParameter(url, "q") or queryParameter(url, "url") or url
end

local function sanitizeHtml(html)
    -- The browser intentionally has no active web platform. Strip the most
    -- problematic blocks before passing the remaining server-rendered HTML to MuPDF.
    html = tostring(html or ""):sub(1, MAX_BODY_BYTES)
    html = html:gsub("<!%-%-.-%-%->", "")
    html = html:gsub("<![Dd][Oo][Cc][Tt][Yy][Pp][Ee][^>]*>", "")
    html = html:gsub("<[Hh][Ee][Aa][Dd][^>]*>.-</[Hh][Ee][Aa][Dd]%s*>", "")
    html = html:gsub("<[sS][cC][rR][iI][pP][tT][^>]*>.-</[sS][cC][rR][iI][pP][tT]%s*>", "")
    html = html:gsub("<[iI][fF][rR][aA][mM][eE][^>]*>.-</[iI][fF][rR][aA][mM][eE]%s*>", "")
    html = html:gsub("<[nN][oO][sS][cC][rR][iI][pP][tT][^>]*>.-</[nN][oO][sS][cC][rR][iI][pP][tT]%s*>", "")
    html = html:gsub("<[Tt][Ee][Mm][Pp][Ll][Aa][Tt][Ee][^>]*>.-</[Tt][Ee][Mm][Pp][Ll][Aa][Tt][Ee]%s*>", "")
    html = html:gsub("<[Oo][Bb][Jj][Ee][Cc][Tt][^>]*>.-</[Oo][Bb][Jj][Ee][Cc][Tt]%s*>", "")
    html = html:gsub("<[Ee][Mm][Bb][Ee][Dd][^>]*>", "")
    html = html:gsub("<[Ss][Tt][Yy][Ll][Ee][^>]*>.-</[Ss][Tt][Yy][Ll][Ee]%s*>", "")
    html = html:gsub("<[Bb][Aa][Ss][Ee][^>]*>", "")
    html = html:gsub("<[Mm][Ee][Tt][Aa][^>]*>", "")
    html = html:gsub("<[Ll][Ii][Nn][Kk][^>]*>", "")
    html = html:gsub("<[fF][oO][rR][mM][^>]*>.-</[fF][oO][rR][mM]%s*>", "")
    html = html:gsub("%s[oO][nN][%w_-]+%s*=%s*\"[^\"]*\"", "")
    html = html:gsub("%s[oO][nN][%w_-]+%s*=%s*'[^']*'", "")
    html = html:gsub("%s[oO][nN][%w_-]+%s*=%s*[^%s>]+", "")
    html = html:gsub("%s[hH][rR][eE][fF]%s*=%s*\"%s*[jJ][aA][vV][aA][sS][cC][rR][iI][pP][tT]:[^\"]*\"", "")
    html = html:gsub("%s[hH][rR][eE][fF]%s*=%s*'%s*[jJ][aA][vV][aA][sS][cC][rR][iI][pP][tT]:[^']*'", "")
    html = html:gsub("%s[hH][rR][eE][fF]%s*=%s*[jJ][aA][vV][aA][sS][cC][rR][iI][pP][tT]:[^%s>]*", "")
    html = html:gsub("%s[sS][rR][cC]%s*=%s*(['\"])[dD][aA][tT][aA]:.-\1", "")
    html = html:gsub("%s[sS][rR][cC]%s*=%s*[dD][aA][tT][aA]:[^%s>]*", "")
    return html
end

local function sanitizeCss(css)
    if type(css) ~= "string" then return "" end
    css = css:sub(1, MAX_CSS_BYTES)
    css = css:gsub("/%*.-%*/", "")
    css = css:gsub("@[Ii][Mm][Pp][Oo][Rr][Tt][^;]*;", "")
    css = css:gsub("@[Ff][Oo][Nn][Tt]%-[Ff][Aa][Cc][Ee]%s*%b{}", "")
    css = css:gsub("[Uu][Rr][Ll]%s*%b()", "")
    css = css:gsub("[Ee][Xx][Pp][Rr][Ee][Ss][Ss][Ii][Oo][Nn]%s*%b()", "")
    css = css:gsub("[Bb][Ee][Hh][Aa][Vv][Ii][Oo][Rr]%s*:[^;}]*;?", "")
    return css
end

local function inlineStylesheets(html)
    local parts, total = {}, 0
    for css in (html or ""):gmatch("<[Ss][Tt][Yy][Ll][Ee][^>]*>(.-)</[Ss][Tt][Yy][Ll][Ee]%s*>") do
        if total >= MAX_CSS_BYTES then break end
        css = sanitizeCss(css)
        if css ~= "" then
            css = css:sub(1, MAX_CSS_BYTES - total)
            parts[#parts + 1] = css
            total = total + #css
        end
    end
    return table.concat(parts, "\n")
end

local function escapeHtml(value)
    return tostring(value or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")
end

local function getHtmlAttribute(tag, name)
    local prefix = "[" .. name:sub(1, 1):lower() .. name:sub(1, 1):upper() .. "]"
    for index = 2, #name do
        prefix = prefix .. "[" .. name:sub(index, index):lower() .. name:sub(index, index):upper() .. "]"
    end
    prefix = "%s" .. prefix
    local double = tag:match(prefix .. "%s*=%s*\"([^\"]*)\"")
    if double then return double end
    local single = tag:match(prefix .. "%s*=%s*'([^']*)'")
    if single then return single end
    return tag:match(prefix .. "%s*=%s*([^%s>]+)")
end

local function sanitizeInlineStyle(value)
    local style = sanitizeCss(value or "")
    style = style:gsub("[Dd][Ii][Ss][Pp][Ll][Aa][Yy]%s*:%s*[Nn][Oo][Nn][Ee]%s*;?", "")
    style = style:gsub("[Vv][Ii][Ss][Ii][Bb][Ii][Ll][Ii][Tt][Yy]%s*:%s*[Hh][Ii][Dd][Dd][Ee][Nn]%s*;?", "")
    style = style:gsub("[Pp][Oo][Ss][Ii][Tt][Ii][Oo][Nn]%s*:%s*[Ff][Ii][Xx][Ee][Dd]%s*;?", "")
    return style
end

local function sanitizeInlineStyles(html)
    local function quoted(prefix, value)
        local clean = sanitizeInlineStyle(value)
        return clean ~= "" and prefix .. "\"" .. escapeHtml(clean) .. "\"" or ""
    end
    html = html:gsub("(%s[Ss][Tt][Yy][Ll][Ee]%s*=%s*)\"([^\"]*)\"", quoted)
    html = html:gsub("(%s[Ss][Tt][Yy][Ll][Ee]%s*=%s*)'([^']*)'", function(prefix, value)
        local clean = sanitizeInlineStyle(value)
        return clean ~= "" and prefix .. "'" .. clean:gsub("'", "") .. "'" or ""
    end)
    return html
end

local function normalizeLazyImages(html)
    return html:gsub("(<[Ii][Mm][Gg][^>]*)(/?>)", function(tag, ending)
        if getHtmlAttribute(tag, "src") then return tag .. ending end
        local source = getHtmlAttribute(tag, "data-src") or getHtmlAttribute(tag, "data-original") or getHtmlAttribute(tag, "data-lazy-src")
        if not source then
            local source_set = getHtmlAttribute(tag, "srcset") or getHtmlAttribute(tag, "data-srcset")
            source = source_set and source_set:match("^%s*([^,%s]+)") or nil
        end
        if source and source ~= "" and not source:match("^[dD][aA][tT][aA]:") and not source:match("^[jJ][aA][vV][aA][sS][cC][rR][iI][pP][tT]:") then
            return tag .. " src=\"" .. escapeHtml(source) .. "\"" .. ending
        end
        return tag .. ending
    end)
end

local function normalizeSemanticHtml(html)
    html = html:gsub("<[Mm][Aa][Ii][Nn][^>]*>", "<div class=\"appdock-main\">")
    html = html:gsub("</[Mm][Aa][Ii][Nn]%s*>", "</div>")
    html = html:gsub("<[Aa][Rr][Tt][Ii][Cc][Ll][Ee][^>]*>", "<article class=\"appdock-main\">")
    html = html:gsub("<[Dd][Ee][Tt][Aa][Ii][Ll][Ss][^>]*>", "<section class=\"appdock-details\">")
    html = html:gsub("</[Dd][Ee][Tt][Aa][Ii][Ll][Ss]%s*>", "</section>")
    html = html:gsub("<[Ss][Uu][Mm][Mm][Aa][Rr][Yy][^>]*>", "<h3 class=\"appdock-details-title\">")
    html = html:gsub("</[Ss][Uu][Mm][Mm][Aa][Rr][Yy]%s*>", "</h3>")
    html = html:gsub("<[Bb][Rr][^>]*>", "<br/>")
    return html
end

local function prepareDocument(html)
    return normalizeLazyImages(normalizeSemanticHtml(sanitizeInlineStyles(sanitizeHtml(html))))
end

local function stripHtml(value)
    local clean = tostring(value or ""):gsub("<[^>]->", ""):gsub("%s+", " ")
    return clean:gsub("^%s+", ""):gsub("%s+$", "")
end

local function decodeHtml(value)
    value = stripHtml(value)
    value = value:gsub("&amp;", "&"):gsub("&quot;", "\""):gsub("&#39;", "'"):gsub("&lt;", "<"):gsub("&gt;", ">")
    return value
end

local function extractGoogleResults(html, page_url)
    local socket_url = require("socket.url")
    local results, seen = {}, {}
    for tag, body in (html or ""):gmatch("(<[Aa][^>]*>)(.-)</[Aa]%s*>") do
        if body:lower():find("<h3", 1, true) then
            local href = getHtmlAttribute(tag, "href")
            if href and href ~= "" then
                local target = unwrapGoogle(socket_url.absolute(page_url, href))
                local parsed = socket_url.parse(target)
                local title = decodeHtml(body)
                if title ~= "" and isHttpUrl(target) and parsed and parsed.host and not isGoogleHost(parsed.host) and not seen[target] then
                    results[#results + 1] = { title = title, url = target }
                    seen[target] = true
                    if #results >= 10 then break end
                end
            end
        end
    end
    return results
end

local function googleBlocked(html)
    local lower = (html or ""):lower()
    return lower:find("unusual traffic", 1, true) or lower:find("captcha", 1, true) or lower:find("enable javascript", 1, true) or lower:find("javascript is required", 1, true) or lower:find("httpservice/retry/enablejs", 1, true) or lower:find("emsg=sg_rel", 1, true)
end

local function renderGoogleResults(query, results, notice)
    local parts = { "<h1>Google</h1>", "<p><b>Search:</b> " .. escapeHtml(query or "") .. "</p>" }
    if notice and notice ~= "" then parts[#parts + 1] = "<p class=\"appdock-google-notice\">" .. escapeHtml(notice) .. "</p>" end
    if #results == 0 and not notice then parts[#parts + 1] = "<p>No readable Google results were returned.</p>" end
    for index, item in ipairs(results) do
        parts[#parts + 1] = "<section class=\"appdock-google-result\"><p><b>" .. index .. ".</b> <a href=\"" .. escapeHtml(item.url) .. "\">" .. escapeHtml(item.title) .. "</a><br/><small>" .. escapeHtml(item.url) .. "</small></p></section>"
    end
    return table.concat(parts, "\n")
end

local function extractSimpleForms(html, page_url)
    local socket_url = require("socket.url")
    local forms = {}
    for form_tag, body in (html or ""):gmatch("(<[Ff][Oo][Rr][Mm][^>]*>)(.-)</[Ff][Oo][Rr][Mm]%s*>") do
        if #forms >= 4 then break end
        local method = (getHtmlAttribute(form_tag, "method") or "get"):lower()
        local action = getHtmlAttribute(form_tag, "action") or page_url
        local input_tag = body:match("(<[Ii][Nn][Pp][Uu][Tt][^>]*>)")
        local input = input_tag and getHtmlAttribute(input_tag, "name")
        local input_type = input_tag and (getHtmlAttribute(input_tag, "type") or "text"):lower() or ""
        if method == "get" and input and input:match("^[%a_][%w_%-]*$") and (input_type == "" or input_type == "text" or input_type == "search" or input_type == "email") then
            local submit_tag = body:match("<[Bb][Uu][Tt][Tt][Oo][Nn][^>]*>(.-)</[Bb][Uu][Tt][Tt][Oo][Nn]>")
            local target = socket_url.absolute(page_url, action)
            if isHttpUrl(target) then
                forms[#forms + 1] = {
                    action = target, name = input,
                    label = stripHtml(submit_tag) ~= "" and stripHtml(submit_tag) or _("Submit"),
                    hint = getHtmlAttribute(input_tag, "placeholder") or input,
                    value = getHtmlAttribute(input_tag, "value") or "",
                }
            end
        end
    end
    return forms
end

local function imageExtension(content_type, url)
    local content = (content_type or ""):lower()
    if content:find("png", 1, true) then return "png" end
    if content:find("jpeg", 1, true) or content:find("jpg", 1, true) then return "jpg" end
    if content:find("gif", 1, true) then return "gif" end
    if content:find("webp", 1, true) then return "webp" end
    local clean_url = tostring(url or ""):gsub("[?#].*$", "")
    local suffix = clean_url:match("%.([%a%d]+)$")
    if suffix and ({ png = true, jpg = true, jpeg = true, gif = true, webp = true })[suffix:lower()] then
        return suffix:lower() == "jpeg" and "jpg" or suffix:lower()
    end
    return nil
end

local function fetchImage(url, redirects)
    redirects = redirects or 0
    if redirects > 5 then return nil, nil, "too many redirects" end
    local socket_url = require("socket.url")
    local socket = require("socket")
    local socketutil = require("socketutil")
    local parsed = socket_url.parse(url)
    if not parsed or (parsed.scheme ~= "http" and parsed.scheme ~= "https") then return nil, nil, "unsupported image address" end
    local http = parsed.scheme == "https" and require("ssl.https") or require("socket.http")
    local chunks, received = {}, 0
    local started_at = os.time()
    local function sink(chunk)
        if os.time() - started_at > REQUEST_MAX_TIME then return nil, "response timed out" end
        if chunk then
            received = received + #chunk
            if received > MAX_IMAGE_BYTES then return nil, "image too large" end
            table.insert(chunks, chunk)
        end
        return 1
    end
    socketutil:set_timeout(REQUEST_TIMEOUT, REQUEST_MAX_TIME)
    local ok, code, headers, status = pcall(function()
        return socket.skip(1, http.request{
            url = url,
            method = "GET",
            sink = sink,
            headers = { ["user-agent"] = BROWSER_USER_AGENT, ["accept"] = "image/png,image/jpeg,image/gif,image/webp;q=0.9,*/*;q=0.1" },
        })
    end)
    socketutil:reset_timeout()
    if not ok or not headers then return nil, nil, status or "image request failed" end
    if code and code >= 300 and code < 400 and headers.location then
        return fetchImage(socket_url.absolute(url, headers.location), redirects + 1)
    end
    if not code or code < 200 or code > 299 then return nil, nil, status or "image request failed" end
    local content_type = (headers["content-type"] or ""):lower()
    if not content_type:find("image/", 1, true) then return nil, nil, "unsupported image type" end
    return table.concat(chunks), content_type
end

local function clearImages(state)
    for _, path in ipairs(state.image_paths or {}) do pcall(os.remove, path) end
    state.image_paths = {}
    state.image_resource_directory = nil
end

local function prepareImages(html, page_url, state)
    clearImages(state)
    local socket_url = require("socket.url")
    local cache_dir = DataStorage:getDataDir() .. "/cache/appdock-browser-images"
    if not util.makePath or not util.makePath(cache_dir) then return html end
    local image_count, total_bytes = 0, 0
    local resolved = {}
    local function fallback(tag)
        local alt = getHtmlAttribute(tag, "alt") or _("Image unavailable")
        return "<p class=\"appdock-image-fallback\">[" .. escapeHtml(alt) .. "]</p>"
    end
    local function rewrite(tag)
        if not tag:match("^<[iI][mM][gG][%s/>]") then return tag end
        local source = getHtmlAttribute(tag, "src")
        if not source or source == "" then return fallback(tag) end
        local source_scheme = source:match("^[%a][%w+.-]*:")
        if source_scheme and not isHttpUrl(source) then return fallback(tag) end
        if source:match("^//") then
            local page = socket_url.parse(page_url)
            source = (page and page.scheme or "https") .. ":" .. source
        end
        local image_url = socket_url.absolute(page_url, source)
        if not isHttpUrl(image_url) then return fallback(tag) end
        local cached = resolved[image_url]
        if cached then return "<img src=\"" .. cached .. "\" alt=\"" .. escapeHtml(getHtmlAttribute(tag, "alt") or "") .. "\" />" end
        if image_count >= MAX_IMAGES_PER_PAGE or total_bytes >= MAX_IMAGE_TOTAL_BYTES then return fallback(tag) end
        local bytes, content_type = fetchImage(image_url)
        local extension = bytes and imageExtension(content_type, image_url)
        if not bytes or not extension or total_bytes + #bytes > MAX_IMAGE_TOTAL_BYTES then return fallback(tag) end
        image_count = image_count + 1
        total_bytes = total_bytes + #bytes
        local filename = string.format("page-%d-%d.%s", os.time(), image_count, extension)
        local path = cache_dir .. "/" .. filename
        local file = io.open(path, "wb")
        if not file then return fallback(tag) end
        file:write(bytes)
        file:close()
        resolved[image_url] = filename
        table.insert(state.image_paths, path)
        state.image_resource_directory = cache_dir
        return "<img src=\"" .. filename .. "\" alt=\"" .. escapeHtml(getHtmlAttribute(tag, "alt") or "") .. "\" />"
    end
    return html:gsub("(<[^>]+>)", rewrite)
end

local function fetchUrl(url, redirects)
    redirects = redirects or 0
    if redirects > 5 then return nil, _("Too many redirects.") end
    local socket_url = require("socket.url")
    local socket = require("socket")
    local socketutil = require("socketutil")
    local ltn12 = require("ltn12")
    local parsed = socket_url.parse(url)
    if not parsed or (parsed.scheme ~= "http" and parsed.scheme ~= "https") then
        return nil, _("Only HTTP and HTTPS addresses are supported.")
    end

    local http = parsed.scheme == "https" and require("ssl.https") or require("socket.http")
    local chunks, received = {}, 0
    local started_at = os.time()
    local function sink(chunk, err)
        if os.time() - started_at > REQUEST_MAX_TIME then return nil, "response timed out" end
        if chunk then
            received = received + #chunk
            if received > MAX_BODY_BYTES then return nil, "response too large" end
            table.insert(chunks, chunk)
        end
        return 1
    end

    socketutil:set_timeout(REQUEST_TIMEOUT, REQUEST_MAX_TIME)
    local ok, code, headers, status = pcall(function()
        return socket.skip(1, http.request{
            url = url,
            method = "GET",
            sink = sink,
            headers = {
                ["user-agent"] = BROWSER_USER_AGENT,
                ["accept"] = "text/html,application/xhtml+xml;q=0.9,*/*;q=0.2",
            },
        })
    end)
    socketutil:reset_timeout()
    if not ok then return nil, _("Network request failed.") end
    if not headers then return nil, status or _("Network or remote server unavailable.") end
    if code and code >= 300 and code < 400 and headers.location then
        return fetchUrl(socket_url.absolute(url, headers.location), redirects + 1)
    end
    if not code or code < 200 or code > 299 then
        return nil, status or _("Remote server error or unavailable.")
    end
    local content_type = (headers["content-type"] or ""):lower()
    if content_type ~= "" and not content_type:find("html", 1, true) and not content_type:find("xhtml", 1, true) then
        return nil, _("This address did not return an HTML page.")
    end
    return table.concat(chunks), nil
end

local function fetchStylesheet(url, redirects)
    redirects = redirects or 0
    if redirects > 3 then return nil end
    local socket_url = require("socket.url")
    local socket = require("socket")
    local socketutil = require("socketutil")
    local parsed = socket_url.parse(url)
    if not parsed or (parsed.scheme ~= "http" and parsed.scheme ~= "https") then return nil end
    local http = parsed.scheme == "https" and require("ssl.https") or require("socket.http")
    local chunks, received = {}, 0
    local started_at = os.time()
    local function sink(chunk)
        if os.time() - started_at > REQUEST_MAX_TIME then return nil, "response timed out" end
        if chunk then
            received = received + #chunk
            if received > MAX_CSS_BYTES then return nil, "stylesheet too large" end
            chunks[#chunks + 1] = chunk
        end
        return 1
    end
    socketutil:set_timeout(REQUEST_TIMEOUT, REQUEST_MAX_TIME)
    local ok, code, headers = pcall(function()
        return socket.skip(1, http.request{
            url = url, method = "GET", sink = sink,
            headers = { ["user-agent"] = BROWSER_USER_AGENT, ["accept"] = "text/css,text/plain;q=0.6,*/*;q=0.1" },
        })
    end)
    socketutil:reset_timeout()
    if not ok or not headers then return nil end
    if code and code >= 300 and code < 400 and headers.location then return fetchStylesheet(socket_url.absolute(url, headers.location), redirects + 1) end
    if not code or code < 200 or code > 299 then return nil end
    local content_type = (headers["content-type"] or ""):lower()
    if content_type ~= "" and not content_type:find("css", 1, true) and not content_type:find("text/plain", 1, true) then return nil end
    return sanitizeCss(table.concat(chunks))
end

local function externalStylesheets(html, page_url)
    local socket_url = require("socket.url")
    local parts, count, total = {}, 0, 0
    for tag in (html or ""):gmatch("<[Ll][Ii][Nn][Kk][^>]*>") do
        if count >= MAX_STYLESHEETS or total >= MAX_CSS_BYTES then break end
        local rel = (getHtmlAttribute(tag, "rel") or ""):lower()
        local href = getHtmlAttribute(tag, "href")
        if rel:find("stylesheet", 1, true) and href then
            local scheme = href:match("^[%a][%w+.-]*:")
            if not scheme or isHttpUrl(href) then
                local target = socket_url.absolute(page_url, href)
                if isHttpUrl(target) then
                    local css = fetchStylesheet(target)
                    if css and css ~= "" then
                        css = css:sub(1, MAX_CSS_BYTES - total)
                        parts[#parts + 1] = css
                        count, total = count + 1, total + #css
                    end
                end
            end
        end
    end
    return table.concat(parts, "\n")
end

local function pageStylesheet(html, page_url)
    local inline = inlineStylesheets(html)
    local external = externalStylesheets(html, page_url)
    return BROWSER_CSS .. "\n" .. inline .. "\n" .. external
end

function Browser:new()
    return setmetatable({}, self)
end

function Browser:_ensureState(instance)
    instance.browser = instance.browser or {
        url = nil,
        html = nil,
        history = {},
        title = _("Web Browser"),
        error = nil,
        is_home = true,
        image_paths = {},
        image_resource_directory = nil,
        forms = {},
        page_css = BROWSER_CSS,
        google_query = nil,
    }
    return instance.browser
end

function Browser:showAddressDialog(instance, context, search)
    local state = self:_ensureState(instance)
    local dialog
    dialog = InputDialog:new{
        title = search and _("Search DuckDuckGo") or _("Open web address"),
        input_hint = search and _("Search the web") or _("example.org"),
        input = search and "" or (state.url or ""),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function() UIManager:close(dialog) end,
                },
                {
                    text = search and _("Search") or _("Open"),
                    is_enter_default = true,
                    callback = function()
                        local value = dialog:getInputText()
                        UIManager:close(dialog)
                        if search then
                            self:search(instance, context, value)
                        else
                            self:navigate(instance, context, value, true)
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Browser:showGoogleSearchDialog(instance, context)
    local dialog
    dialog = InputDialog:new{
        title = _("Google search"),
        input_hint = _("Search Google"),
        input = "",
        buttons = { {
            { text = _("Cancel"), callback = function() UIManager:close(dialog) end },
            { text = _("Search"), is_enter_default = true, callback = function()
                local query = dialog:getInputText() or ""
                UIManager:close(dialog)
                self:googleSearch(instance, context, query)
            end },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Browser:search(instance, context, query)
    local util = require("util")
    query = (query or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if query == "" then return end
    self:navigate(instance, context, DUCKDUCKGO_HTML .. util.urlEncode(query), true)
end

function Browser:googleSearch(instance, context, query)
    query = (query or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if query == "" then return end
    self:navigate(instance, context, GOOGLE_SEARCH .. util.urlEncode(query), true)
end

function Browser:reload(instance, context)
    local state = self:_ensureState(instance)
    if state.url then self:navigate(instance, context, state.url, false) end
end

function Browser:goHome(instance, context)
    local state = self:_ensureState(instance)
    state.url = nil
    state.html = nil
    clearImages(state)
    state.error = nil
    state.title = _("Web Browser")
    state.is_home = true
    state.forms = {}
    state.page_css = BROWSER_CSS
    state.google_query = nil
    context.requestRebuild("ui")
end

function Browser:showFormDialog(instance, context, form)
    if not form then return end
    local dialog
    dialog = InputDialog:new{
        title = form.label,
        input_hint = form.hint,
        input = form.value or "",
        buttons = { {
            { text = _("Cancel"), callback = function() UIManager:close(dialog) end },
            { text = form.label, is_enter_default = true, callback = function()
                local value = dialog:getInputText() or ""
                UIManager:close(dialog)
                local separator = form.action:find("?", 1, true) and "&" or "?"
                self:navigate(instance, context, form.action .. separator .. form.name .. "=" .. util.urlEncode(value), true)
            end },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Browser:cleanup(instance)
    if instance and instance.browser then clearImages(instance.browser) end
end

function Browser:navigate(instance, context, target, add_history)
    local state = self:_ensureState(instance)
    local socket_url = require("socket.url")
    local url
    local has_explicit_scheme = type(target) == "string" and target:match("^[%a][%w+.-]*:")
    if state.url and type(target) == "string" and not has_explicit_scheme and not target:match("^//") then
        url = socket_url.absolute(state.url, target)
    else
        url = normalizeUrl(target)
    end
    if not url then
        state.error = _("Only HTTP and HTTPS addresses are supported.")
        context.requestRebuild("ui")
        return
    end
    url = unwrapDuckDuckGo(url)
    url = unwrapGoogle(url)
    if not isHttpUrl(url) then
        state.error = _("Only HTTP and HTTPS addresses are supported.")
        context.requestRebuild("ui")
        return
    end
    local html, err = fetchUrl(url)
    if not html then
        state.error = tostring(err or _("Unable to open this page."))
        context.requestRebuild("ui")
        return
    end
    if add_history and state.url and state.url ~= url then
        table.insert(state.history, state.url)
        if #state.history > 20 then table.remove(state.history, 1) end
    end
    state.url = url
    state.google_query = isGoogleSearch(url) and queryParameter(url, "q") or nil
    if state.google_query then
        local results = extractGoogleResults(html, url)
        local blocked = googleBlocked(html)
        local notice = blocked and _("Google requested JavaScript or verification for this request. No verification is bypassed; try again later or use DuckDuckGo.") or nil
        state.forms = {}
        state.page_css = BROWSER_CSS
        state.html = renderGoogleResults(state.google_query, results, notice)
    else
        state.forms = extractSimpleForms(html, url)
        state.page_css = pageStylesheet(html, url)
        state.html = prepareImages(prepareDocument(html), url, state)
    end
    state.error = nil
    state.is_home = false
    state.title = url:match("^https?://([^/%?#]+)") or _("Web Browser")
    context.requestRebuild("ui")
end

function Browser:goBack(instance, context)
    local state = self:_ensureState(instance)
    local previous = table.remove(state.history)
    if previous then self:navigate(instance, context, previous, false) end
end

function Browser:followLink(instance, context, link)
    local target = type(link) == "table" and (link.uri or link.href) or link
    if type(target) ~= "string" or target == "" then return end
    self:navigate(instance, context, target, true)
end

function Browser:buildPane(instance, context)
    local state = self:_ensureState(instance)
    local pane = WidgetContainer:new{
        dimen = Geom:new{ w = context.dimen.w, h = context.dimen.h },
    }
    local width, height = context.dimen.w, context.dimen.h
    local margin, gap, button_height = scale(12), scale(6), scale(36)
    local has_form = state.forms and state.forms[1]
    local button_count = has_form and 5 or 4
    local button_width = math.floor((width - 2 * margin - (button_count - 1) * gap) / button_count)
    local toolbar_height = button_height + scale(48)
    local content = OverlapGroup:new{
        dimen = pane.dimen,
        allow_mirroring = false,
        FrameContainer:new{
            width = width, height = height, padding = 0, bordersize = 0,
            background = PALETTE.background,
            emptySizedWidget(width, height),
        },
        BrowserButton:new{
            title = _("Address"), width = button_width, height = button_height,
            background = PALETTE.primary, foreground = PALETTE.on_primary,
            callback = function() self:showAddressDialog(instance, context, false) end,
            overlap_offset = { margin, scale(8) },
        },
        BrowserButton:new{
            title = _("Google"), width = button_width, height = button_height,
            background = PALETTE.surface, foreground = PALETTE.on_surface,
            callback = function() self:showGoogleSearchDialog(instance, context) end,
            overlap_offset = { margin + button_width + gap, scale(8) },
        },
        BrowserButton:new{
            title = _("Back"), width = button_width, height = button_height,
            background = PALETTE.surface, foreground = PALETTE.on_surface,
            callback = function() self:goBack(instance, context) end,
            overlap_offset = { margin + (button_width + gap) * 2, scale(8) },
        },
        BrowserButton:new{
            title = state.is_home and _("Reload") or _("Home"), width = button_width, height = button_height,
            background = PALETTE.surface, foreground = PALETTE.on_surface,
            callback = function()
                if state.is_home then self:reload(instance, context) else self:goHome(instance, context) end
            end,
            overlap_offset = { margin + (button_width + gap) * 3, scale(8) },
        },
        TextWidget:new{
            text = state.error or ((state.title or _("Web Browser")) .. (state.url and " · " .. state.url or "")),
            face = Font:getFace("smallinfofont", scale(11)),
            fgcolor = state.error and PALETTE.on_variant or PALETTE.on_surface,
            max_width = width - 2 * margin,
            overlap_offset = { margin, button_height + scale(16) },
        },
    }
    if has_form then
        table.insert(content, BrowserButton:new{
            title = has_form.label, width = button_width, height = button_height,
            background = PALETTE.surface, foreground = PALETTE.on_surface,
            callback = function() self:showFormDialog(instance, context, has_form) end,
            overlap_offset = { margin + (button_width + gap) * 4, scale(8) },
        })
    end
    if state.html and not state.error then
        local scroll = ScrollHtmlWidget:new{
            html_body = state.html,
            css = state.page_css or BROWSER_CSS,
            html_resource_directory = state.image_resource_directory,
            width = width - margin * 2,
            height = height - toolbar_height - margin,
            default_font_size = scale(16),
            dialog = context.host,
            html_link_tapped_callback = function(link)
                self:followLink(instance, context, link)
            end,
        }
        scroll.overlap_offset = { margin, toolbar_height }
        table.insert(content, scroll)
    elseif state.error then
        table.insert(content, TextWidget:new{
            text = _("Try another address or search term."),
            face = Font:getFace("smallinfofont", scale(15)),
            fgcolor = PALETTE.on_variant,
            max_width = width - 2 * margin,
            overlap_offset = { margin, toolbar_height + scale(18) },
        })
    else
        local quick_width = math.floor((width - 2 * margin - gap) / 2)
        local quick_height = scale(62)
        table.insert(content, TextWidget:new{
            text = _("A quiet, JavaScript-free browser"),
            face = Font:getFace("cfont", scale(20)),
            fgcolor = PALETTE.on_surface,
            bold = true,
            overlap_offset = { margin, toolbar_height + scale(16) },
        })
        table.insert(content, TextWidget:new{
            text = _("Search the web or open a familiar reading destination."),
            face = Font:getFace("smallinfofont", scale(13)),
            fgcolor = PALETTE.on_variant,
            max_width = width - 2 * margin,
            overlap_offset = { margin, toolbar_height + scale(48) },
        })
        local destinations = {
            { title = _("Google"), callback = function() self:showGoogleSearchDialog(instance, context) end },
            { title = _("Wikipedia"), callback = function() self:navigate(instance, context, "https://en.wikipedia.org/wiki/Main_Page", true) end },
            { title = _("Project Gutenberg"), callback = function() self:navigate(instance, context, "https://www.gutenberg.org/", true) end },
            { title = _("KOReader"), callback = function() self:navigate(instance, context, "https://koreader.rocks/", true) end },
        }
        for index, destination in ipairs(destinations) do
            local column = (index - 1) % 2
            local row = math.floor((index - 1) / 2)
            table.insert(content, BrowserButton:new{
                title = destination.title,
                width = quick_width, height = quick_height,
                background = index == 1 and PALETTE.primary or PALETTE.surface,
                foreground = index == 1 and PALETTE.on_primary or PALETTE.on_surface,
                callback = destination.callback,
                overlap_offset = { margin + column * (quick_width + gap), toolbar_height + scale(78) + row * (quick_height + gap) },
            })
        end
    end
    pane[1] = content
    return pane
end

Browser._test = {
    sanitizeHtml = sanitizeHtml,
    sanitizeCss = sanitizeCss,
    inlineStylesheets = inlineStylesheets,
    prepareDocument = prepareDocument,
    normalizeLazyImages = normalizeLazyImages,
    extractSimpleForms = extractSimpleForms,
    isGoogleSearch = isGoogleSearch,
    unwrapGoogle = unwrapGoogle,
    extractGoogleResults = extractGoogleResults,
    googleBlocked = googleBlocked,
    renderGoogleResults = renderGoogleResults,
}

return Browser
