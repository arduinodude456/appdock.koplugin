--[[--
A small, explicit-trust AppStore for AppDock DApps.
It reads only a plain-text manifest from the owner-configured GitHub repository.
Catalog refresh never executes remote code; a user confirmation and Lua syntax
check are required before an individual DApp is installed or updated.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local DAppLogo = require("appdock_logo")
local Theme = require("appdock_theme")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local InfoMessage = require("ui/widget/infomessage")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextWidget = require("ui/widget/textwidget")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local UIManager = require("ui/uimanager")
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
local MAX_WIDGET_BYTES = 256 * 1024
local MAX_DESIGN_BYTES = 32 * 1024
local MAX_WALLPAPER_BYTES = 2 * 1024 * 1024
local DESIGN_IMAGE_SUFFIXES = { png = true, jpg = true, jpeg = true, webp = true }
local KNOWN_LOGOS = {}
for _, kind in ipairs(DAppLogo.availableKinds()) do KNOWN_LOGOS[kind] = true end

local function scale(value)
    return Screen:scaleBySize(value)
end

local function trim(value)
    return type(value) == "string" and value:gsub("^%s+", ""):gsub("%s+$", "") or ""
end

local function safeDesignImagePath(path)
    if type(path) ~= "string" or #path == 0 or #path > 180 or path:find("..", 1, true) then return false end
    if not path:match("^[%w%._/%-]+$") then return false end
    local suffix = path:match("%.([%w]+)$")
    return suffix and DESIGN_IMAGE_SUFFIXES[suffix:lower()] == true or false
end

local function saveFile(path, body)
    local temporary = path .. ".tmp"
    os.remove(temporary)
    local file, write_err = io.open(temporary, "wb")
    if not file then return false, write_err end
    local written, close_err = file:write(body)
    file:close()
    if not written then
        os.remove(temporary)
        return false, close_err
    end
    if not os.rename(temporary, path) then
        os.remove(temporary)
        return false, "could not replace local file"
    end
    return true
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
    logo = nil,
    callback = nil,
    width = nil,
    height = nil,
    background = nil,
    foreground = nil,
    dimen = nil,
}

function StoreButton:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local inset = scale(9)
    local icon_size = self.logo and math.min(scale(30), math.max(scale(16), self.height - 2 * inset)) or 0
    local text_x = inset + (self.logo and icon_size + scale(8) or 0)
    local text_width = math.max(scale(18), self.width - text_x - inset)
    local title_size = math.max(scale(9), math.min(scale(13), math.floor(self.height * .28)))
    local subtitle_size = math.max(scale(7), math.min(scale(9), math.floor(self.height * .20)))
    local has_subtitle = self.subtitle and self.subtitle ~= ""
    local title = Theme.fitLabel(self.title or "", text_width, title_size, 0)
    local subtitle = Theme.fitLabel(self.subtitle or "", text_width, subtitle_size, 0)
    local title_widget = TextWidget:new{ text = title, face = Font:getFace("smallinfofont", title_size), fgcolor = self.foreground, bold = true, max_width = text_width }
    local subtitle_widget = has_subtitle and TextWidget:new{ text = subtitle, face = Font:getFace("smallinfofont", subtitle_size), fgcolor = self.foreground, max_width = text_width } or nil
    local items = subtitle_widget and { title_widget, subtitle_widget } or { title_widget }
    local positions = Theme.centeredStack(self.height, items, scale(3), scale(4))
    local title_y, subtitle_y = positions[1], positions[2]
    self.layout = { title = title, subtitle = subtitle, title_y = title_y, subtitle_y = subtitle_y }
    local layers = {
        title_widget,
    }
    title_widget.overlap_offset = { text_x, title_y }
    if self.logo then
        table.insert(layers, DAppLogo:new{
            kind = self.logo,
            size = icon_size,
            ink = self.foreground,
            overlap_offset = { inset, math.max(0, math.floor((self.height - icon_size) / 2)) },
        })
    end
    if has_subtitle then
        subtitle_widget.overlap_offset = { text_x, subtitle_y }
        table.insert(layers, subtitle_widget)
    end
    self[1] = FrameContainer:new{
        width = self.width,
        height = self.height,
        padding = 0,
        bordersize = self.frame_style and self.frame_style.bordersize or 0,
        color = self.frame_style and self.frame_style.color or nil,
        radius = self.frame_style and self.frame_style.radius or math.floor(self.height * 0.24),
        background = self.background,
        OverlapGroup:new{ dimen = self.dimen, allow_mirroring = false, unpack(layers) },
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

local function normalizedVersion(version)
    if type(version) ~= "string" then return nil end
    local normalized = version:match("^v?(%d+%.?%d*%.?%d*)$")
    if not normalized then return nil end
    local parts = {}
    for part in normalized:gmatch("%d+") do table.insert(parts, tonumber(part)) end
    return #parts > 0 and parts or nil
end

function AppStore.compareVersions(left, right)
    local left_parts, right_parts = normalizedVersion(left), normalizedVersion(right)
    if not left_parts or not right_parts then return nil end
    for index = 1, math.max(#left_parts, #right_parts) do
        local a, b = left_parts[index] or 0, right_parts[index] or 0
        if a ~= b then return a > b and 1 or -1 end
    end
    return 0
end

function AppStore.parseManifest(body)
    local entries, known = {}, {}
    for raw_line in (body or ""):gmatch("[^\r\n]+") do
        local value = raw_line:gsub("#.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
        local parts = {}
        for part in value:gmatch("[^|]+") do
            table.insert(parts, (part:gsub("^%s+", ""):gsub("%s+$", "")))
        end
        local path = parts[1] or value
        local version = normalizedVersion(parts[2]) and parts[2] or nil
        local logo = type(parts[3]) == "string" and KNOWN_LOGOS[parts[3]] and parts[3] or nil
        local kind = parts[4] == "widget" and "widget" or (parts[4] == "design" and "design" or "dapp")
        local expected_suffix = kind == "design" and "%.appdock%-design$" or "%.lua$"
        if path ~= "" and path:match("^[%w%._/%-]+$") and path:match(expected_suffix) and not path:find("..", 1, true) and not known[path] then
            known[path] = true
            local name = path:match("([^/]+)%.appdock%-design$") or path:match("([^/]+)%.lua$") or path
            name = name:gsub("[_%-]+", " "):gsub("%f[%a].", string.upper)
            table.insert(entries, { path = path, title = name, version = version, logo = logo, kind = kind })
        end
    end
    table.sort(entries, function(left, right) return left.title:lower() < right.title:lower() end)
    return entries
end

function AppStore.filterEntries(entries, query, category)
    local needle = trim(query or ""):lower()
    local result = {}
    for _, entry in ipairs(entries or {}) do
        local haystack = table.concat({ entry.title or "", entry.path or "", entry.kind or "" }, " "):lower()
        local matches_query = needle == "" or haystack:find(needle, 1, true)
        local matches_category = not category or category == "all" or entry.kind == category
        if matches_query and matches_category then table.insert(result, entry) end
    end
    return result
end

function AppStore:new()
    return setmetatable({}, self)
end

function AppStore:_ensureState(instance)
    instance.app_store = instance.app_store or {
        entries = nil,
        error = nil,
        refreshed = false,
        query = "",
        category = "all",
    }
    instance.app_store.query = type(instance.app_store.query) == "string" and instance.app_store.query or ""
    local category = instance.app_store.category
    instance.app_store.category = (category == "dapp" or category == "widget" or category == "design") and category or "all"
    return instance.app_store
end

function AppStore:promptSearch(instance, context)
    local state = self:_ensureState(instance)
    local dialog
    dialog = InputDialog:new{
        title = _("Search AppStore"),
        input = state.query or "",
        input_hint = _("Name, file path, DApp, widget, or design"),
        buttons = {
            {
                { text = _("Clear"), callback = function() state.query = ""; UIManager:close(dialog); context.requestRebuild("ui") end },
                { text = _("Cancel"), callback = function() UIManager:close(dialog) end },
                { text = _("Search"), is_enter_default = true, callback = function() state.query = trim(dialog:getInputText()); UIManager:close(dialog); context.requestRebuild("ui") end },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function AppStore:cycleCategory(instance, context)
    local state = self:_ensureState(instance)
    local categories = { "all", "dapp", "widget", "design" }
    local position = 1
    for index, category in ipairs(categories) do
        if category == state.category then position = index; break end
    end
    state.category = categories[position % #categories + 1]
    context.requestRebuild("ui")
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

function AppStore:_designDirectory()
    local path = DataStorage:getDataDir() .. "/appdock_designs"
    if lfs.attributes(path, "mode") ~= "directory" then lfs.mkdir(path) end
    return path
end

function AppStore:_entryState(context, entry)
    local definition, record
    if entry.kind == "design" then
        definition, record = context.appdock:getStoreDesignBySource(entry.path)
    elseif entry.kind == "widget" then
        definition, record = context.manager:getStoreWidgetBySource(entry.path)
    else
        definition, record = context.manager:getStoreDAppBySource(entry.path)
    end
    if not record then return "install", nil, nil end
    local installed_version = record.version or (definition and definition.version)
    if entry.version and (not installed_version or AppStore.compareVersions(entry.version, installed_version) == 1) then
        return "update", definition, record
    end
    return "installed", definition, record
end

function AppStore:confirmInstall(instance, context, entry)
    local state = self:_entryState(context, entry)
    if state == "installed" then
        if entry.kind == "design" then
            local design = context.appdock:getStoreDesignBySource(entry.path)
            if design and context.appdock:setStoreDesignActive(design.id) then
                UIManager:show(InfoMessage:new{ text = _("Activated ") .. entry.title .. _(". Its colors, styles, and background are now in use.") })
                context.requestRebuild("ui")
                return
            end
        end
        UIManager:show(InfoMessage:new{ text = entry.title .. _(" is already installed and up to date.") })
        return
    end
    local is_update = state == "update"
    local is_widget = entry.kind == "widget"
    local is_design = entry.kind == "design"
    local item_name = is_design and _("design") or (is_widget and _("widget") or _("DApp"))
    local action = is_update and _("Update") or _("Install")
    local message = is_update and (_("Update this installed ") .. item_name .. _(" from your trusted AppDock GitHub repository?\n\n")) or (_("Install this ") .. item_name .. _(" from your trusted AppDock GitHub repository?\n\n"))
    local dialog = ConfirmBox:new{
        text = message .. entry.path .. (entry.version and ("\n\n" .. _("Repository version: ") .. entry.version) or "") .. (is_design and _("\n\nA design is declarative data only. It is validated and applied locally; it never executes code.") or _("\n\nThe file is downloaded only after you choose this action. It will be validated before being added to AppDock.")),
        ok_text = action,
        ok_callback = function() self:install(instance, context, entry, is_update) end,
    }
    UIManager:show(dialog)
end

function AppStore:_parseDesign(body)
    local definition = {}
    local allowed = {
        id = true, title = true, version = true, highlight = true, background = true,
        button = true, text = true, dropdown = true, button_style = true, logo_shape = true, wallpaper = true,
    }
    for raw_line in (body or ""):gmatch("[^\r\n]+") do
        local key, value = raw_line:match("^%s*([%w_%-]+)%s*=%s*(.-)%s*$")
        if key and value and allowed[key] and definition[key] == nil then definition[key] = value end
    end
    if definition.wallpaper ~= nil and definition.wallpaper ~= "" and not safeDesignImagePath(definition.wallpaper) then
        return nil, _("The design wallpaper path is invalid.")
    end
    local normalized = Theme.normalizeDesignDefinition(definition)
    if not normalized then return nil, _("A design requires an id, title, five valid colors, and valid styles.") end
    return normalized
end

function AppStore:installDesign(instance, context, entry)
    local source, err = fetchText(REPOSITORY .. entry.path, MAX_DESIGN_BYTES)
    if not source then
        UIManager:show(InfoMessage:new{ text = _("Could not download this design: ") .. (err or "") })
        return
    end
    local definition, inspect_err = self:_parseDesign(source)
    if not definition then
        UIManager:show(InfoMessage:new{ text = _("This file is not a valid AppDock design.\n\n") .. tostring(inspect_err) })
        return
    end
    if entry.version and definition.version ~= entry.version then
        UIManager:show(InfoMessage:new{ text = _("The downloaded design version does not match the catalog entry.") })
        return
    end
    local installed, installed_id = context.appdock:getStoreDesignBySource(entry.path)
    if installed and installed_id ~= definition.id then
        UIManager:show(InfoMessage:new{ text = _("This update changes the design identity and was rejected.") })
        return
    end
    local design_directory = self:_designDirectory()
    local wallpaper_file = ""
    if definition.wallpaper and definition.wallpaper ~= "" then
        local image, image_err = fetchText(REPOSITORY .. definition.wallpaper, MAX_WALLPAPER_BYTES)
        if not image then
            UIManager:show(InfoMessage:new{ text = _("Could not download this design background: ") .. tostring(image_err or "") })
            return
        end
        local suffix = definition.wallpaper:match("%.([%w]+)$") or "png"
        wallpaper_file = design_directory .. "/" .. definition.id .. "_wallpaper." .. suffix:lower()
        local image_saved, image_save_err = saveFile(wallpaper_file, image)
        if not image_saved then
            UIManager:show(InfoMessage:new{ text = _("Could not save this design background: ") .. tostring(image_save_err or "") })
            return
        end
    end
    local filename = entry.path:gsub("[^%w%._%-]", "_")
    local target = design_directory .. "/" .. filename
    local saved, save_err = saveFile(target, source)
    if not saved then
        UIManager:show(InfoMessage:new{ text = _("Could not save this design: ") .. tostring(save_err or "") })
        return
    end
    local ok, stored = context.appdock:installStoreDesign(definition, entry.path, target, wallpaper_file)
    if not ok then
        UIManager:show(InfoMessage:new{ text = _("Could not activate this design: ") .. tostring(stored or "") })
        return
    end
    UIManager:show(InfoMessage:new{ text = _("Installed and activated ") .. entry.title .. _(". It now controls AppDock colors, background, buttons, and app logos.") })
    context.requestRebuild("ui")
end

function AppStore:install(instance, context, entry, is_update)
    if entry.kind == "design" then
        self:installDesign(instance, context, entry)
        return
    end
    local is_widget = entry.kind == "widget"
    local source, err = fetchText(REPOSITORY .. entry.path, is_widget and MAX_WIDGET_BYTES or MAX_DAPP_BYTES)
    if not source then
        UIManager:show(InfoMessage:new{ text = (is_widget and _("Could not download this widget: ") or _("Could not download this DApp: ")) .. (err or "") })
        return
    end
    local chunk, syntax_err = loadstring(source, "@appstore/" .. entry.path)
    if not chunk then
        UIManager:show(InfoMessage:new{ text = _("The downloaded DApp has invalid Lua syntax.\n\n") .. tostring(syntax_err) })
        return
    end
    local filename = entry.path:gsub("[^%w%._%-]", "_")
    local target = self:_storeDirectory() .. "/" .. filename
    local temporary = target .. ".tmp"
    os.remove(temporary)
    local file, write_err = io.open(temporary, "wb")
    if not file then
        UIManager:show(InfoMessage:new{ text = _("Could not save this DApp: ") .. tostring(write_err) })
        return
    end
    local written, close_err = file:write(source)
    file:close()
    if not written then
        os.remove(temporary)
        UIManager:show(InfoMessage:new{ text = _("Could not save this DApp: ") .. tostring(close_err) })
        return
    end
    local definition, inspect_err
    if is_widget then
        definition, inspect_err = context.manager:inspectStoreWidget(temporary)
    else
        definition, inspect_err = context.manager:inspectStoreDApp(temporary)
    end
    if not definition then
        os.remove(temporary)
        UIManager:show(InfoMessage:new{ text = (is_widget and _("This file is not a valid AppDock widget.\n\n") or _("This file is not a valid AppDock DApp.\n\n")) .. tostring(inspect_err) })
        return
    end
    if entry.version and definition.version ~= entry.version then
        os.remove(temporary)
        UIManager:show(InfoMessage:new{ text = is_widget and _("The downloaded widget version does not match the catalog entry.") or _("The downloaded DApp version does not match the catalog entry.") })
        return
    end
    local installed_definition, installed_record
    if is_widget then
        installed_definition, installed_record = context.manager:getStoreWidgetBySource(entry.path)
    else
        installed_definition, installed_record = context.manager:getStoreDAppBySource(entry.path)
    end
    if installed_definition and installed_definition.id ~= definition.id then
        os.remove(temporary)
        UIManager:show(InfoMessage:new{ text = _("This update changes the DApp identity and was rejected.") })
        return
    end
    if ((is_widget and context.manager.definitions[definition.id]) or (not is_widget and context.manager.widget_definitions[definition.id])) and not installed_record then
        os.remove(temporary)
        UIManager:show(InfoMessage:new{ text = is_widget and _("A different installed DApp already uses this id.") or _("A different installed widget already uses this id.") })
        return
    end
    if is_update and not installed_record then
        os.remove(temporary)
        UIManager:show(InfoMessage:new{ text = _("The installed DApp record is unavailable; refresh the catalog and try again.") })
        return
    end
    local backup = target .. ".previous"
    os.remove(backup)
    local had_target = lfs.attributes(target) ~= nil
    if had_target and not os.rename(target, backup) then
        os.remove(temporary)
        UIManager:show(InfoMessage:new{ text = _("The existing DApp could not be prepared for update.") })
        return
    end
    if not os.rename(temporary, target) then
        if had_target then os.rename(backup, target) end
        os.remove(temporary)
        UIManager:show(InfoMessage:new{ text = _("The downloaded DApp could not replace the previous version.") })
        return
    end
    local ok, result
    if is_widget then
        ok, result = context.manager:loadStoreWidget(target, entry.path, false, definition.id, installed_record ~= nil, target)
    else
        ok, result = context.manager:loadStoreDApp(target, entry.path, false, definition.id, installed_record ~= nil, target)
    end
    if not ok then
        os.remove(target)
        if had_target then os.rename(backup, target) end
        UIManager:show(InfoMessage:new{ text = (is_widget and _("This file is not a valid AppDock widget.\n\n") or _("This file is not a valid AppDock DApp.\n\n")) .. tostring(result) })
        return
    end
    os.remove(backup)
    local action = installed_record and _("Updated") or _("Installed")
    UIManager:show(InfoMessage:new{ text = action .. " " .. entry.title .. (is_widget and _(". It is now available on the AppDock homescreen.") or _(". It is now available in AppDock apps.")) })
    context.requestRebuild("ui")
end

function AppStore:confirmUninstallWidget(instance, context, entry, definition)
    local dialog
    dialog = ConfirmBox:new{
        text = _("Remove this Store widget from the AppDock homescreen?\n\n") .. entry.title,
        ok_text = _("Uninstall"),
        ok_callback = function()
            local ok, err = context.manager:uninstallStoreWidget(definition.id)
            UIManager:close(dialog)
            if ok then
                UIManager:show(InfoMessage:new{ text = _("Removed ") .. entry.title .. _(" from the AppDock homescreen.") })
                context.requestRebuild("ui")
            else
                UIManager:show(InfoMessage:new{ text = _("Could not remove this widget: ") .. tostring(err) })
            end
        end,
    }
    UIManager:show(dialog)
end

function AppStore:confirmUninstall(instance, context, entry, definition)
    local dialog = ConfirmBox:new{
        text = _("Remove this DApp from AppDock?\n\n") .. entry.title .. _("\n\nIts installed Lua file and AppStore registration will be removed. Any saved documents created by the DApp are kept."),
        ok_text = _("Uninstall"),
        ok_callback = function()
            local ok, err = context.manager:uninstallStoreDApp(definition.id)
            if ok then
                UIManager:show(InfoMessage:new{ text = _("Removed ") .. entry.title .. _(" from AppDock.") })
                context.requestRebuild("ui")
            else
                UIManager:show(InfoMessage:new{ text = _("Could not remove this DApp: ") .. tostring(err) })
            end
        end,
    }
    UIManager:show(dialog)
end

function AppStore:confirmUninstallDesign(instance, context, entry, definition)
    local dialog
    dialog = ConfirmBox:new{
        text = _("Remove this AppStore design?\n\n") .. entry.title .. _("\n\nIf it is active, AppDock returns to your existing theme, button style, and personal background settings."),
        ok_text = _("Uninstall"),
        ok_callback = function()
            local ok, err = context.appdock:uninstallStoreDesign(definition.id)
            if ok then
                UIManager:show(InfoMessage:new{ text = _("Removed ") .. entry.title .. _(". The previous AppDock appearance is restored.") })
                context.requestRebuild("ui")
            else
                UIManager:show(InfoMessage:new{ text = _("Could not remove this design: ") .. tostring(err) })
            end
        end,
    }
    UIManager:show(dialog)
end

function AppStore:_showStatus(entry, state)
    if state == "update" then return _("Update available") .. (entry.version and (" · " .. entry.version) or "") end
    if state == "installed" then return _("Installed") .. (entry.version and (" · " .. entry.version) or "") end
    return _("Not installed") .. (entry.version and (" · " .. entry.version) or "")
end

function AppStore:buildPane(instance, context)
    local state = self:_ensureState(instance)
    local palette = Theme.getPalette(context.manager.appdock)
    local width, height = context.dimen.w, context.dimen.h
    local margin, gap = scale(14), scale(8)
    local heading_title = TextWidget:new{ text = _("AppStore"), face = Font:getFace("cfont", scale(21)), fgcolor = palette.on_surface, bold = true }
    local heading_subtitle = TextWidget:new{ text = _("Trusted DApps, widgets, and designs from arduinodude456/DApps"), face = Font:getFace("smallinfofont", scale(10)), fgcolor = palette.on_variant, max_width = width - 2 * margin }
    local header_height = math.max(scale(52), heading_title:getSize().h + heading_subtitle:getSize().h + scale(10))
    local header_positions = Theme.centeredStack(header_height, { heading_title, heading_subtitle }, scale(4), scale(4))
    heading_title.overlap_offset = { margin, header_positions[1] }
    heading_subtitle.overlap_offset = { margin, header_positions[2] }
    local content = OverlapGroup:new{
        dimen = Geom:new{ w = width, h = height },
        allow_mirroring = false,
        FrameContainer:new{
            width = width, height = height, padding = 0, bordersize = 0,
            background = palette.background,
            emptySizedWidget(width, height),
        },
        heading_title,
        heading_subtitle,
    }
    local action_y = header_height + gap
    local compact_height = scale(46)
    local refresh_width = math.floor((width - 2 * margin - gap) * 0.44)
    table.insert(content, StoreButton:new{
        title = _("Refresh catalog"), subtitle = _("Read apps, widgets, designs"),
        logo = "sync",
        width = refresh_width, height = compact_height,
        background = palette.primary, foreground = palette.on_primary,
        callback = function() self:refresh(instance, context) end,
        overlap_offset = { margin, action_y },
    })
    table.insert(content, StoreButton:new{
        title = _("Safe updates"), subtitle = _("Confirmation required"),
        logo = "app_store",
        width = width - 2 * margin - refresh_width - gap, height = compact_height,
        background = palette.secondary, foreground = palette.on_secondary,
        callback = function()
            UIManager:show(InfoMessage:new{ text = _("Installations, updates, and removals always require an explicit confirmation.") })
        end,
        overlap_offset = { margin + refresh_width + gap, action_y },
    })
    local query = trim(state.query or "")
    local category_labels = { all = _("All"), dapp = _("Apps"), widget = _("Widgets"), design = _("Designs") }
    table.insert(content, StoreButton:new{
        title = query == "" and _("Search catalog") or (_("Search: ") .. query),
        subtitle = query == "" and _("Filter loaded apps, widgets, and designs") or _("Tap to change or clear this local filter"),
        logo = "app_store",
        width = width - 2 * margin, height = scale(42),
        background = palette.surface_variant or palette.surface, foreground = palette.on_surface_variant or palette.on_surface,
        callback = function() self:promptSearch(instance, context) end,
        overlap_offset = { margin, action_y + compact_height + gap },
    })
    table.insert(content, StoreButton:new{
        title = _("Category: ") .. (category_labels[state.category] or category_labels.all),
        subtitle = _("Tap to switch between all, apps, widgets, and designs"),
        logo = "palette",
        width = width - 2 * margin, height = scale(42),
        background = palette.button or palette.primary, foreground = palette.on_button or palette.on_primary,
        frame_style = Theme.getButtonFrameStyle(context.appdock, scale(42), math.floor(scale(42) * .24)),
        callback = function() self:cycleCategory(instance, context) end,
        overlap_offset = { margin, action_y + compact_height + gap + scale(42) + gap },
    })

    local list_y, card_height = action_y + compact_height + gap + scale(42) + gap + scale(42) + gap, scale(68)
    if not state.refreshed then
        table.insert(content, StoreButton:new{
            title = _("Catalog ready"),
            subtitle = _("Refresh after catalog entries are published."),
            logo = "app_store",
            width = width - 2 * margin, height = card_height,
            background = palette.surface, foreground = palette.on_surface,
            overlap_offset = { margin, list_y },
        })
    elseif state.error then
        table.insert(content, StoreButton:new{
            title = _("Catalog unavailable"), subtitle = state.error,
            logo = "app_store",
            width = width - 2 * margin, height = card_height,
            background = palette.tertiary, foreground = palette.on_tertiary,
            overlap_offset = { margin, list_y },
        })
    elseif not state.entries or #state.entries == 0 then
        table.insert(content, StoreButton:new{
            title = _("No store items listed"), subtitle = _("Add DApps, widgets, or design paths to dapps.txt."),
            logo = "app_store",
            width = width - 2 * margin, height = card_height,
            background = palette.surface, foreground = palette.on_surface,
            overlap_offset = { margin, list_y },
        })
    else
        local visible_entries = AppStore.filterEntries(state.entries, query, state.category)
        if #visible_entries == 0 then
            table.insert(content, StoreButton:new{
                title = _("No matching store items"), subtitle = _("Change the search or category filter."),
                logo = "app_store",
                width = width - 2 * margin, height = card_height,
                background = palette.surface, foreground = palette.on_surface,
                overlap_offset = { margin, list_y },
            })
            return WidgetContainer:new{ dimen = Geom:new{ w = width, h = height }, content }
        end
        local card_width = width - 2 * margin
        local action_width = math.min(scale(82), math.max(scale(62), math.floor(card_width * 0.25)))
        local primary_width = card_width - action_width - gap
        local cards = {}
        for index, entry in ipairs(visible_entries) do
            local row_y = (index - 1) * (card_height + gap)
            local action_state, definition = self:_entryState(context, entry)
            local status = self:_showStatus(entry, action_state)
            local background = index % 2 == 0 and palette.secondary or palette.surface
            local foreground = index % 2 == 0 and palette.on_secondary or palette.on_surface
            table.insert(cards, StoreButton:new{
                title = entry.title,
                subtitle = status,
                logo = definition and definition.logo or entry.logo or "app_store",
                width = primary_width, height = card_height,
                background = background, foreground = foreground,
                frame_style = Theme.getButtonFrameStyle(context.appdock, card_height, math.floor(card_height * .24)),
                callback = function() self:confirmInstall(instance, context, entry) end,
                overlap_offset = { 0, row_y },
            })
            if action_state == "installed" then
                local action_height = math.floor((card_height - gap) / 2)
                table.insert(cards, StoreButton:new{
                    title = entry.kind == "design" and _("Use") or _("Installed"), subtitle = "",
                    width = action_width, height = action_height,
                    background = palette.button or palette.primary, foreground = palette.on_button or palette.on_primary,
                    frame_style = Theme.getButtonFrameStyle(context.appdock, action_height, math.floor(action_height * .24)),
                    callback = function() self:confirmInstall(instance, context, entry) end,
                    overlap_offset = { primary_width + gap, row_y },
                })
                table.insert(cards, StoreButton:new{
                    title = _("Uninstall"), subtitle = "",
                    width = action_width, height = card_height - action_height - gap,
                    background = palette.tertiary, foreground = palette.on_tertiary,
                    callback = function()
                        if entry.kind == "design" then
                            self:confirmUninstallDesign(instance, context, entry, definition)
                        elseif entry.kind == "widget" then
                            self:confirmUninstallWidget(instance, context, entry, definition)
                        else
                            self:confirmUninstall(instance, context, entry, definition)
                        end
                    end,
                    overlap_offset = { primary_width + gap, row_y + action_height + gap },
                })
            else
                table.insert(cards, StoreButton:new{
                    title = action_state == "update" and _("Update") or _("Install"), subtitle = "",
                    width = action_width, height = card_height,
                    background = palette.button or palette.primary, foreground = palette.on_button or palette.on_primary,
                    frame_style = Theme.getButtonFrameStyle(context.appdock, card_height, math.floor(card_height * .24)),
                    callback = function() self:confirmInstall(instance, context, entry) end,
                    overlap_offset = { primary_width + gap, row_y },
                })
            end
        end
        local list_height = math.max(scale(40), height - list_y - margin)
        local content_height = math.max(list_height, #visible_entries * (card_height + gap) - gap)
        local list_content = OverlapGroup:new{
            dimen = Geom:new{ w = card_width, h = content_height },
            allow_mirroring = false,
            unpack(cards),
        }
        table.insert(content, ScrollableContainer:new{
            dimen = Geom:new{ w = card_width, h = list_height },
            -- ScrollableContainer marks its show_parent dirty after every
            -- offset change. Without this, the framebuffer changes but an
            -- E-Ink device may not repaint the moved cards/scrollbar.
            show_parent = context.host,
            list_content,
            overlap_offset = { margin, list_y },
        })
    end
    return WidgetContainer:new{
        dimen = Geom:new{ w = width, h = height },
        content,
    }
end

return AppStore
