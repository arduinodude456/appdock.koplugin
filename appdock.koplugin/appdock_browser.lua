--[[--
A compact, JavaScript-free browser engine for AppDock DApps.
It accepts only HTTP(S), fetches server-rendered HTML, and renders it through
KOReader's MuPDF-backed ScrollHtmlWidget.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
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
local _ = require("gettext")

local Screen = Device.screen
local Browser = {}
Browser.__index = Browser

local MAX_BODY_BYTES = 2 * 1024 * 1024
local REQUEST_TIMEOUT = 12
local REQUEST_MAX_TIME = 30
local DUCKDUCKGO_HTML = "https://html.duckduckgo.com/html/?q="

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
  h1 { font-size: 1.45em; margin: 0.7em 0 0.35em; }
  h2, h3 { margin: 0.8em 0 0.35em; }
  p, li { margin: 0.32em 0; }
  a { color: #173b6f; text-decoration: underline; }
  pre, code { white-space: pre-wrap; }
  img, video, audio, canvas, svg, iframe, form, button, input, select, textarea { display: none; }
]]

local function emptySizedWidget(width, height)
    return CenterContainer:new{
        dimen = Geom:new{ w = width, h = height },
        HorizontalSpan:new{ width = 0 },
    }
end

function BrowserButton:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
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
                text = self.title or "",
                face = Font:getFace("smallinfofont", scale(12)),
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

local function sanitizeHtml(html)
    -- The browser intentionally has no active web platform. Strip the most
    -- problematic blocks before passing the remaining server-rendered HTML to MuPDF.
    html = html:gsub("<[sS][cC][rR][iI][pP][tT][^>]*>.-</[sS][cC][rR][iI][pP][tT]%s*>", "")
    html = html:gsub("<[iI][fF][rR][aA][mM][eE][^>]*>.-</[iI][fF][rR][aA][mM][eE]%s*>", "")
    html = html:gsub("<[nN][oO][sS][cC][rR][iI][pP][tT][^>]*>.-</[nN][oO][sS][cC][rR][iI][pP][tT]%s*>", "")
    html = html:gsub("<[fF][oO][rR][mM][^>]*>.-</[fF][oO][rR][mM]%s*>", "")
    html = html:gsub("%s[oO][nN][%w_-]+%s*=%s*(['\"]).-\1", "")
    html = html:gsub("%s[hH][rR][eE][fF]%s*=%s*(['\"])[jJ][aA][vV][aA][sS][cC][rR][iI][pP][tT]:.-\1", "")
    return html
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
                ["user-agent"] = socketutil.USER_AGENT,
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

function Browser:search(instance, context, query)
    local util = require("util")
    query = (query or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if query == "" then return end
    self:navigate(instance, context, DUCKDUCKGO_HTML .. util.urlEncode(query), true)
end

function Browser:reload(instance, context)
    local state = self:_ensureState(instance)
    if state.url then self:navigate(instance, context, state.url, false) end
end

function Browser:goHome(instance, context)
    local state = self:_ensureState(instance)
    state.url = nil
    state.html = nil
    state.error = nil
    state.title = _("Web Browser")
    state.is_home = true
    context.requestRebuild("ui")
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
    state.html = sanitizeHtml(html)
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
    local button_width = math.floor((width - 2 * margin - 3 * gap) / 4)
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
            title = _("Search"), width = button_width, height = button_height,
            background = PALETTE.surface, foreground = PALETTE.on_surface,
            callback = function() self:showAddressDialog(instance, context, true) end,
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
    if state.html and not state.error then
        local scroll = ScrollHtmlWidget:new{
            html_body = state.html,
            css = BROWSER_CSS,
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
            { title = _("DuckDuckGo"), callback = function() self:showAddressDialog(instance, context, true) end },
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

return Browser
