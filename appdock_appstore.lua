--[[--
A small, explicit-trust AppStore for AppDock DApps.
It reads only a plain-text manifest from the owner-configured GitHub repository.
Catalog refresh never executes remote code; a user confirmation and Lua syntax
check are required before an individual DApp is installed.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local InfoMessage = require("ui/widget/infomessage")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextWidget = require("ui/widget/textwidget")
local Theme = require("appdock_theme")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
if not ok_lfs then lfs = require("lfs") end

local Screen = Device.screen
local AppStore = {}
AppStore.__index = AppStore

local REPOSITORY = "https://raw.githubusercontent.com/arduinodude456/DApps/main/"
local MANIFEST_URL = REPOSITORY .. "dapps.txt"
local MAX_MANIFEST_BYTES = 128 * 1024
local MAX_DAPP_BYTES = 512 * 1024

local function scale(value)
    return Screen:scaleBySize(value)
end

local function emptySizedWidget(width, height)
    return CenterContainer:new{
        dimen = Geom:new{ w = width, h = height },
        HorizontalSpan:new{ width = 0 },
    }
end

local StoreButton = InputContainer:extend{
    title = nil,
    subtitle = nil,
    callback = nil,
    width = nil,
    height = nil,
    background = nil,
    foreground = nil,
    dimen = nil,
}

function StoreButton:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self[1] = FrameContainer:new{
        width = self.width,
        height = self.height,
        padding = 0,
        bordersize = 0,
        radius = math.floor(self.height * 0.24),
        background = self.background,
        CenterContainer:new{
            dimen = Geom:new{ w = self.width, h = self.height },
            VerticalGroup:new{
                TextWidget:new{
                    text = self.title or "",
                    face = Font:getFace("smallinfofont", scale(14)),
                    fgcolor = self.foreground,
                    bold = true,
                    max_width = self.width - scale(22),
                },
                VerticalSpan:new{ width = scale(2) },
                TextWidget:new{
                    text = self.subtitle or "",
                    face = Font:getFace("smallinfofont", scale(10)),
                    fgcolor = self.foreground,
                    max_width = self.width - scale(22),
                },
            },
        },
    }
    self.ges_events = {
        TapAppStoreButton = { GestureRange:new{ ges = "tap", range = self.dimen } },
    }
end

function StoreButton:paintTo(bb, x, y)
    local range = self.ges_events.TapAppStoreButton[1].range
    range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    return InputContainer.paintTo(self, bb, x, y)
end

function StoreButton:onTapAppStoreButton()
    if self.callback then self.callback() end
    return true
end

local function fetchText(url, limit)
    local socket_url = require("socket.url")
    local socket = require("socket")
    local socketutil = require("socketutil")
    local parsed = socket_url.parse(url)
    if not parsed or parsed.scheme ~= "https" then return nil, _("Only HTTPS sources are allowed.") end
    local https = require("ssl.https")
    local chunks, received = {}, 0
    local function sink(chunk)
        if chunk then
            received = received + #chunk
            if received > limit then return nil, "response too large" end
            table.insert(chunks, chunk)
        end
        return 1
    end
    socketutil:set_timeout(12, 30)
    local ok, code, headers, status = pcall(function()
        return socket.skip(1, https.request{
            url = url,
            method = "GET",
            sink = sink,
            headers = {
                ["user-agent"] = socketutil.USER_AGENT,
                ["accept"] = "text/plain,text/x-lua,application/octet-stream;q=0.8,*/*;q=0.1",
            },
        })
    end)
    socketutil:reset_timeout()
    if not ok or not headers then return nil, status or _("Network request failed.") end
    if not code or code < 200 or code > 299 then return nil, status or _("Repository unavailable.") end
    return table.concat(chunks), nil
end

function AppStore.parseManifest(body)
    local entries, known = {}, {}
    for raw_line in (body or ""):gmatch("[^\r\n]+") do
        local path = raw_line:gsub("#.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if path ~= "" and path:match("^[%w%._/%-]+%.lua$") and not path:find("..", 1, true) and not known[path] then
            known[path] = true
            local name = path:match("([^/]+)%.lua$") or path
            name = name:gsub("[_%-]+", " "):gsub("%f[%a].", string.upper)
            table.insert(entries, { path = path, title = name })
        end
    end
    table.sort(entries, function(left, right) return left.title:lower() < right.title:lower() end)
    return entries
end

function AppStore:new()
    return setmetatable({}, self)
end

function AppStore:_ensureState(instance)
    instance.app_store = instance.app_store or {
        entries = nil,
        error = nil,
        refreshed = false,
    }
    return instance.app_store
end

function AppStore:refresh(instance, context)
    local state = self:_ensureState(instance)
    local manifest, err = fetchText(MANIFEST_URL, MAX_MANIFEST_BYTES)
    state.entries = manifest and AppStore.parseManifest(manifest) or nil
    state.error = err
    state.refreshed = true
    context.requestRebuild("ui")
end

function AppStore:_storeDirectory()
    local path = DataStorage:getDataDir() .. "/appdock_dapps"
    if lfs.attributes(path, "mode") ~= "directory" then lfs.mkdir(path) end
    return path
end

function AppStore:confirmInstall(instance, context, entry)
    local dialog = ConfirmBox:new{
        text = _("Install this DApp from your trusted AppDock GitHub repository?\n\n") .. entry.path .. _("\n\nThe file is downloaded only after you choose Install. It will run as a KOReader Lua DApp after installation."),
        ok_text = _("Install"),
        ok_callback = function() self:install(instance, context, entry) end,
    }
    UIManager:show(dialog)
end

function AppStore:install(instance, context, entry)
    local source, err = fetchText(REPOSITORY .. entry.path, MAX_DAPP_BYTES)
    if not source then
        UIManager:show(InfoMessage:new{ text = _("Could not download this DApp: ") .. (err or "") })
        return
    end
    local chunk, syntax_err = loadstring(source, "@appstore/" .. entry.path)
    if not chunk then
        UIManager:show(InfoMessage:new{ text = _("The downloaded DApp has invalid Lua syntax.\n\n") .. tostring(syntax_err) })
        return
    end
    local filename = entry.path:gsub("[^%w%._%-]", "_")
    local target = self:_storeDirectory() .. "/" .. filename
    local file, write_err = io.open(target, "wb")
    if not file then
        UIManager:show(InfoMessage:new{ text = _("Could not save this DApp: ") .. tostring(write_err) })
        return
    end
    file:write(source)
    file:close()
    local ok, load_err = context.manager:loadStoreDApp(target, entry.path)
    if not ok then
        os.remove(target)
        UIManager:show(InfoMessage:new{ text = _("This file is not a valid AppDock DApp.\n\n") .. tostring(load_err) })
        return
    end
    UIManager:show(InfoMessage:new{ text = _("Installed ") .. entry.title .. _(". It is now available in AppDock apps.") })
    context.requestRebuild("ui")
end

function AppStore:buildPane(instance, context)
    local state = self:_ensureState(instance)
    local palette = Theme.getPalette(context.manager.appdock)
    local width, height = context.dimen.w, context.dimen.h
    local margin, gap = scale(14), scale(8)
    local content = OverlapGroup:new{
        dimen = Geom:new{ w = width, h = height },
        allow_mirroring = false,
        FrameContainer:new{
            width = width, height = height, padding = 0, bordersize = 0,
            background = palette.background,
            emptySizedWidget(width, height),
        },
        TextWidget:new{
            text = _("AppStore"),
            face = Font:getFace("cfont", scale(21)),
            fgcolor = palette.on_surface,
            bold = true,
            overlap_offset = { margin, scale(12) },
        },
        TextWidget:new{
            text = _("Trusted DApps from arduinodude456/DApps"),
            face = Font:getFace("smallinfofont", scale(10)),
            fgcolor = palette.on_variant,
            max_width = width - 2 * margin,
            overlap_offset = { margin, scale(40) },
        },
    }
    local refresh_width = math.floor((width - 2 * margin - gap) * 0.42)
    table.insert(content, StoreButton:new{
        title = _("Refresh catalog"), subtitle = _("Read dapps.txt"),
        width = refresh_width, height = scale(46),
        background = palette.primary, foreground = palette.on_primary,
        callback = function() self:refresh(instance, context) end,
        overlap_offset = { margin, scale(58) },
    })
    table.insert(content, StoreButton:new{
        title = _("Install safely"), subtitle = _("Confirmation required"),
        width = width - 2 * margin - refresh_width - gap, height = scale(46),
        background = palette.secondary, foreground = palette.on_secondary,
        callback = function() self:confirmInstall(instance, context, { path = "example.lua", title = _("Choose a catalog entry first") }) end,
        overlap_offset = { margin + refresh_width + gap, scale(58) },
    })

    local list_y, card_height = scale(114), scale(58)
    if not state.refreshed then
        table.insert(content, StoreButton:new{
            title = _("Catalog ready"),
            subtitle = _("Refresh after dapps.txt is published in your repository."),
            width = width - 2 * margin, height = card_height,
            background = palette.surface, foreground = palette.on_surface,
            overlap_offset = { margin, list_y },
        })
    elseif state.error then
        table.insert(content, StoreButton:new{
            title = _("Catalog unavailable"), subtitle = state.error,
            width = width - 2 * margin, height = card_height,
            background = palette.tertiary, foreground = palette.on_tertiary,
            overlap_offset = { margin, list_y },
        })
    elseif not state.entries or #state.entries == 0 then
        table.insert(content, StoreButton:new{
            title = _("No DApps listed"), subtitle = _("Add relative .lua paths to dapps.txt."),
            width = width - 2 * margin, height = card_height,
            background = palette.surface, foreground = palette.on_surface,
            overlap_offset = { margin, list_y },
        })
    else
        local max_cards = math.max(1, math.floor((height - list_y - margin) / (card_height + gap)))
        for index, entry in ipairs(state.entries) do
            if index > max_cards then break end
            table.insert(content, StoreButton:new{
                title = entry.title, subtitle = entry.path,
                width = width - 2 * margin, height = card_height,
                background = index % 2 == 0 and palette.secondary or palette.surface,
                foreground = index % 2 == 0 and palette.on_secondary or palette.on_surface,
                callback = function() self:confirmInstall(instance, context, entry) end,
                overlap_offset = { margin, list_y + (index - 1) * (card_height + gap) },
            })
        end
    end
    return WidgetContainer:new{
        dimen = Geom:new{ w = width, h = height },
        content,
    }
end

return AppStore
