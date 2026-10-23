-- AppStore category for declarative sleep-screen presets.  Public browsing does
-- not require a TBS account; installing, activating and editing remain local.
local Blitbuffer = require("ffi/blitbuffer")
local AppDockDialogs = require("appdock_dialogs")
local ButtonDialog = AppDockDialogs.ButtonDialog
local ConfirmBox = AppDockDialogs.ConfirmBox
local InputDialog = AppDockDialogs.InputDialog
local InfoMessage = AppDockDialogs.InfoMessage
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local Layout = require("appdock_layout")
local OverlapGroup = require("ui/widget/overlapgroup")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Catalog = {}
local Screen = Device.screen
local PAGE_SIZE = 12
local MODULE_DIR = (debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "")

local function scale(value) return Screen:scaleBySize(value) end
local function trim(value) return type(value) == "string" and value:gsub("^%s+", ""):gsub("%s+$", "") or "" end
local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}; if seen[value] then return seen[value] end
    local result = {}; seen[value] = result
    for key, item in pairs(value) do result[copy(key, seen)] = copy(item, seen) end
    return result
end
local function notify(text) UIManager:show(InfoMessage:new{ text = text }) end
local function blank(width, height)
    local CenterContainer = require("ui/widget/container/centercontainer")
    return CenterContainer:new{ dimen = Geom:new{ w = width, h = height }, HorizontalSpan:new{ width = 0 } }
end
local function palette(appdock, ui)
    if ui and ui.PLAY then return ui.PLAY end
    local ok, Theme = pcall(require, "appdock_theme")
    if ok and Theme and Theme.getPalette then return Theme.getPalette(appdock) end
    return { background = Blitbuffer.COLOR_WHITE, surface = Blitbuffer.COLOR_LIGHT_GRAY,
        surface_variant = Blitbuffer.COLOR_GRAY_8, primary = Blitbuffer.COLOR_GRAY_8,
        on_primary = Blitbuffer.COLOR_BLACK, on_surface = Blitbuffer.COLOR_BLACK,
        on_variant = Blitbuffer.COLOR_DARK_GRAY, green = Blitbuffer.COLOR_BLACK,
        on_green = Blitbuffer.COLOR_WHITE, green_container = Blitbuffer.COLOR_LIGHT_GRAY,
        on_green_container = Blitbuffer.COLOR_BLACK, divider = Blitbuffer.COLOR_GRAY }
end
local function stateFor(instance)
    instance.app_store = instance.app_store or {}
    local state = instance.app_store.sleepscreen_catalog
    if not state then
        state = { view = "local", query = "", offset = 0, entries = nil, has_more = false,
            loading_error = nil, opened = nil, preview_paths = nil }
        instance.app_store.sleepscreen_catalog = state
    end
    state.view = state.view == "browse" and "browse" or "local"
    state.query = type(state.query) == "string" and state.query or ""
    state.offset = math.max(0, tonumber(state.offset) or 0)
    return state
end
local function safeRequire(name)
    local previous_path = package.path
    package.path = MODULE_DIR .. "?.lua;" .. previous_path
    local ok, module = pcall(require, name)
    package.path = previous_path
    return ok and module or nil
end
local function creatorName(entry)
    local creator = entry and entry.creator
    if type(creator) == "table" then return trim(creator.display_name) ~= "" and creator.display_name or (creator.account_id or _("Unknown creator")) end
    return _("Unknown creator")
end
local function recordName(record)
    return record and record.definition and record.definition.name or _("Untitled sleepscreen")
end
local function extension(path)
    return type(path) == "string" and path:lower():match("%.([a-z0-9]+)$") or nil
end
local function validId(id) return type(id) == "string" and id:match("^[A-Za-z0-9_-]+$") ~= nil end
local PREVIEW_EXTENSIONS = { png = true, jpg = true, jpeg = true, webp = true, ttf = true, otf = true }

local CatalogButton = InputContainer:extend{
    title = nil, subtitle = nil, callback = nil, width = nil, height = nil,
    background = nil, foreground = nil, dimen = nil, selected = false,
}
function CatalogButton:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local inset = scale(9)
    local title_size = math.max(scale(8), math.min(scale(14), math.floor(self.height * .25)))
    local subtitle_size = math.max(scale(7), math.min(scale(10), math.floor(self.height * .18)))
    local title = TextWidget:new{ text = self.title or "", face = Font:getFace("smallinfofont", title_size),
        fgcolor = self.foreground, bold = true, max_width = self.width - 2 * inset, padding = 0 }
    local subtitle = self.subtitle and self.subtitle ~= "" and TextWidget:new{ text = self.subtitle,
        face = Font:getFace("smallinfofont", subtitle_size), fgcolor = self.foreground,
        max_width = self.width - 2 * inset, padding = 0 } or nil
    local title_y = subtitle and math.max(inset, math.floor((self.height - title:getSize().h - subtitle:getSize().h - scale(2)) / 2))
        or math.max(inset, math.floor((self.height - title:getSize().h) / 2))
    self[1] = FrameContainer:new{ width = self.width, height = self.height, padding = 0,
        bordersize = self.selected and scale(1) or 0, color = self.foreground,
        radius = math.floor(self.height * .20), background = self.background,
        Layout.FixedStack:new{ width = self.width, height = self.height, entries = (function()
            local rows = { { widget = title, x = inset, y = title_y } }
            if subtitle then rows[#rows + 1] = { widget = subtitle, x = inset, y = title_y + title:getSize().h + scale(2) } end
            return rows
        end)() } }
    self.ges_events = { TapSleepCatalogButton = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end
function CatalogButton:paintTo(bb, x, y)
    local range = self.ges_events.TapSleepCatalogButton[1].range
    range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    return InputContainer.paintTo(self, bb, x, y)
end
function CatalogButton:onTapSleepCatalogButton() if self.callback then self.callback() end; return true end

local function storeModule() return safeRequire("appdock_sleepscreen_store") end
local function presetsModule() return safeRequire("appdock_sleepscreen_presets") end
local function rendererModule() return safeRequire("appdock_sleepscreen_renderer") end

local function localRecords(appdock)
    local Presets = presetsModule()
    if not Presets or not Presets.listLocal then return {} end
    local ok, records = pcall(Presets.listLocal, appdock)
    return ok and type(records) == "table" and records or {}
end
local function accountStatus(appdock)
    local Account = safeRequire("appdock_tbs_account")
    if not Account or not Account.status then return nil end
    local ok, status = pcall(Account.status, appdock)
    return ok and status or nil
end
local function isOwn(appdock, record)
    if not record or not record.remote_id then return false end
    local creator = record.creator
    local creator_id = type(creator) == "table" and creator.account_id or nil
    local status = accountStatus(appdock)
    return creator_id ~= nil and status and status.account_id == creator_id
end

-- The server returns BASE64 assets with `get`.  The renderer deliberately only
-- accepts local paths, so detail previews use a small temporary, non-published
-- cache. It is never passed to Store, and is removed when the detail changes.
local function removePreview(state)
    for _, path in pairs((state and state.preview_paths) or {}) do pcall(os.remove, path) end
    if state and state.preview_dir then
        local ok, lfs = pcall(require, "libs/libkoreader-lfs"); if not ok then ok, lfs = pcall(require, "lfs") end
        if ok and lfs then pcall(lfs.rmdir, state.preview_dir) end
    end
    if state then state.preview_paths = nil end
    if state then state.preview_dir = nil end
end
local function removeStalePreviews(root)
    local ok, lfs = pcall(require, "libs/libkoreader-lfs"); if not ok then ok, lfs = pcall(require, "lfs") end
    if not ok or not lfs then return end
    local base = root .. "/appdock_sleepscreen_preview"
    if lfs.attributes(base, "mode") ~= "directory" then return end
    for name in lfs.dir(base) do
        if name ~= "." and name ~= ".." and name:match("^session_[%w_-]+$") then
            local path = base .. "/" .. name
            local mode = lfs.attributes(path, "mode")
            local modified = lfs.attributes(path, "modification") or os.time()
            if mode == "directory" and os.time() - modified > 24 * 60 * 60 then
                for file in lfs.dir(path) do
                    if file ~= "." and file ~= ".." and file:match("^preview_[%w_-]+%.[a-z0-9]+$") then os.remove(path .. "/" .. file) end
                end
                pcall(lfs.rmdir, path)
            end
        end
    end
end
local function packagePreviewPaths(state, package)
    local Presets = presetsModule()
    if not Presets or not Presets.validatePackage then return nil, _("Package validation is unavailable.") end
    local definition, assets_or_err = Presets.validatePackage(package)
    if not definition then return nil, assets_or_err end
    local assets = assets_or_err
    local base = DataStorage:getDataDir() .. "/appdock_sleepscreen_preview"
    local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs"); if not ok_lfs then ok_lfs, lfs = pcall(require, "lfs") end
    if not ok_lfs then return nil, _("Local preview storage is unavailable.") end
    if lfs.attributes(base, "mode") ~= "directory" and not lfs.mkdir(base) then
        return nil, _("Could not create preview storage.")
    end
    -- Delete old previews before writing new paths, not afterwards: two presets
    -- may use the same declared asset IDs.
    removePreview(state)
    removeStalePreviews(DataStorage:getDataDir())
    local session = string.format("session_%x_%x", os.time(), math.random(1, 0x7fffffff))
    local directory = base .. "/" .. session
    if not lfs.mkdir(directory) then return nil, _("Could not create preview session.") end
    local paths = {}
    for _, asset in ipairs(definition.assets) do
        local path = directory .. "/preview_" .. asset.id .. "." .. asset.extension
        local file = io.open(path, "wb")
        if not file then
            for _, saved in pairs(paths) do os.remove(saved) end
            pcall(lfs.rmdir, directory)
            return nil, _("Could not write preview asset.")
        end
        local written = file:write(assets[asset.id])
        local closed = file:close()
        if not written or not closed then
            os.remove(path)
            for _, saved in pairs(paths) do os.remove(saved) end
            pcall(lfs.rmdir, directory)
            return nil, _("Could not write preview asset.")
        end
        paths[asset.id] = path
    end
    state.preview_paths = paths
    state.preview_dir = directory
    return paths
end

local function previewWidget(definition, asset_paths, width, height, appdock, colors)
    local Renderer = rendererModule()
    if Renderer and Renderer.build and definition then
        local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
        local factor = math.min(width / screen_w, height / screen_h)
        local render_w, render_h = math.max(1, math.floor(screen_w * factor)), math.max(1, math.floor(screen_h * factor))
        local ok, widget = pcall(Renderer.build, definition, render_w, render_h, {
            appdock = appdock, asset_paths = asset_paths or {}, preview = true, cycle = 0,
        })
        if ok and widget then
            return Layout.FixedStack:new{ width = width, height = height,
                entries = { { widget = widget, x = math.floor((width - render_w) / 2), y = math.floor((height - render_h) / 2) } } }
        end
    end
    return FrameContainer:new{ width = width, height = height, padding = 0, bordersize = 0,
        background = colors.surface, blank(width, height) }
end

-- Do not build renderer trees for every untrusted public result at once. The
-- public list can contain a full page of arbitrary user-authored elements and
-- asset references; creating dozens of native text/image widgets up front can
-- exhaust KOReader's UI memory while its ScrollableContainer is painting.
-- The complete, validated preview is built after the user opens one result.
local function publicPreviewPlaceholder(width, height, colors)
    local CenterContainer = require("ui/widget/container/centercontainer")
    return FrameContainer:new{ width = width, height = height, padding = 0, bordersize = 0,
        radius = scale(8), background = colors.surface_variant or colors.surface,
        CenterContainer:new{ dimen = Geom:new{ w = width, h = height }, TextWidget:new{
            text = _("Tap Open"), face = Font:getFace("smallinfofont", scale(9)),
            fgcolor = colors.on_variant, max_width = width - scale(8), padding = 0,
        } } }
end

function Catalog.refresh(instance, context, state)
    state = state or stateFor(instance)
    local Store = storeModule()
    if not Store or not Store.list then state.loading_error = _("The sleepscreen catalog is not available in this build."); return end
    local ok, response, err = pcall(Store.list, context.appdock, state.query, state.offset)
    if not ok or not response then state.entries, state.has_more, state.loading_error = nil, false, tostring(err or response or _("Catalog unavailable."))
    else
        state.entries = response.entries or {}
        state.has_more = response.has_more == true
        state.loading_error = nil
    end
    if context.requestRebuild then context.requestRebuild("ui") end
end

function Catalog.promptSearch(instance, context, state)
    local dialog
    dialog = InputDialog:new{ title = _("Search sleepscreens"), input = state.query or "", input_hint = _("Name or creator"), buttons = { {
        { text = _("Clear"), callback = function() state.query = ""; state.offset = 0; UIManager:close(dialog); Catalog.refresh(instance, context, state) end },
        { text = _("Cancel"), callback = function() UIManager:close(dialog) end },
        { text = _("Search"), is_enter_default = true, callback = function()
            state.query, state.offset = trim(dialog:getInputText()), 0; UIManager:close(dialog); Catalog.refresh(instance, context, state)
        end },
    } } }
    UIManager:show(dialog); if dialog.onShowKeyboard then dialog:onShowKeyboard() end
end

function Catalog.openRemote(instance, context, state, entry)
    local Store = storeModule()
    if not Store or not Store.get then notify(_("The sleepscreen catalog is not available.")); return end
    removePreview(state)
    local ok, response, package = pcall(Store.get, context.appdock, entry.id)
    if not ok or not response then notify(_("Could not open preset: ") .. tostring(package or response or "")); return end
    -- Accept both the contract's {entry, package} return value and the older
    -- two-value internal helper form so this UI remains forward compatible.
    if response.entry then state.opened = { entry = response.entry, package = response.package }
    else state.opened = { entry = response, package = package } end
    if not state.opened.entry then notify(_("The catalog response was incomplete.")); state.opened = nil; return end
    local paths, preview_err = packagePreviewPaths(state, state.opened.package)
    if not paths then
        notify(_("Could not preview this package: ") .. tostring(preview_err or ""))
        state.opened = nil; return
    end
    if context.requestRebuild then context.requestRebuild("ui") end
end

local function installPackage(context, state, use_after, edit_after)
    local opened = state.opened
    local Presets = presetsModule()
    if not opened or not opened.package or not Presets or not Presets.installPackage then notify(_("Open the complete preset before downloading it.")); return end
    local record, err = Presets.installPackage(context.appdock, opened.package, opened.entry)
    if not record then notify(_("Could not save preset locally: ") .. tostring(err or "")); return end
    if use_after and Presets.activate then
        local ok, activate_err = Presets.activate(context.appdock, record.id)
        if not ok then notify(_("Downloaded, but could not activate: ") .. tostring(activate_err or "")); return end
    end
    if edit_after then
        -- A public preset from another creator always becomes a new fork. Never
        -- carry its remote identity into the editor where it could update it.
        if not isOwn(context.appdock, record) then
            record.id, record.remote_id, record.revision, record.creator = nil, nil, nil, nil
        end
        local Editor = safeRequire("appdock_sleepscreen_editor")
        if Editor and Editor.show then Editor.show(context.appdock, context, record) end
    else notify(use_after and _("Downloaded and activated sleepscreen.") or _("Downloaded sleepscreen for offline use.")) end
    removePreview(state)
    state.opened = nil
    if context.requestRebuild then context.requestRebuild("ui") end
end

function Catalog.confirmDownload(context, state, use_after, edit_after)
    local opened = state.opened
    if not opened or not opened.entry then return end
    local assets = #((opened.package and opened.package.definition and opened.package.definition.assets) or {})
    local dialog
    dialog = ConfirmBox:new{ text = _("Download this sleepscreen for local offline use?") .. "\n\n"
            .. _("Name: ") .. tostring(opened.entry.name or "") .. "\n"
            .. _("Creator: ") .. creatorName(opened.entry) .. "\n"
            .. _("Assets: ") .. tostring(assets) .. "\n\n"
            .. _("Only the selected declarative preset and its assets are saved locally."),
        ok_text = edit_after and _("Download & edit") or (use_after and _("Download & use") or _("Download")),
        ok_callback = function() UIManager:close(dialog); installPackage(context, state, use_after, edit_after) end }
    UIManager:show(dialog)
end

function Catalog.renameLocal(instance, context, record)
    local dialog
    dialog = InputDialog:new{ title = _("Rename sleepscreen"), input = recordName(record), input_hint = _("Preset name"), buttons = { {
        { text = _("Cancel"), callback = function() UIManager:close(dialog) end },
        { text = _("Rename"), is_enter_default = true, callback = function()
            local name = trim(dialog:getInputText()); UIManager:close(dialog)
            if name == "" then notify(_("Enter a name.")); return end
            local draft = copy(record); draft.definition.name = name
            local Presets = presetsModule(); local saved, err = Presets and Presets.saveDraft and Presets.saveDraft(context.appdock, draft, record.id)
            if not saved then notify(_("Could not rename: ") .. tostring(err or "")) else notify(_("Sleepscreen renamed.")); if context.requestRebuild then context.requestRebuild("ui") end end
        end },
    } } }
    UIManager:show(dialog); if dialog.onShowKeyboard then dialog:onShowKeyboard() end
end

function Catalog.confirmRemove(context, record)
    local dialog
    dialog = ConfirmBox:new{ text = _("Remove this local sleepscreen?") .. "\n\n" .. recordName(record)
            .. "\n\n" .. _("The active preset will return to the default screen."), ok_text = _("Remove"),
        ok_callback = function()
            UIManager:close(dialog)
            local Presets = presetsModule(); local ok, err = Presets and Presets.remove and Presets.remove(context.appdock, record.id)
            if not ok then notify(_("Could not remove preset: ") .. tostring(err or "")) else notify(_("Removed local sleepscreen.")); if context.requestRebuild then context.requestRebuild("ui") end end
        end }
    UIManager:show(dialog)
end

function Catalog.confirmUnpublish(context, record)
    if not isOwn(context.appdock, record) then notify(_("Only the original creator can unpublish this preset.")); return end
    local dialog
    dialog = ConfirmBox:new{ text = _("Unpublish this public sleepscreen?") .. "\n\n" .. recordName(record)
            .. "\n\n" .. _("Your installed offline copy stays available."), ok_text = _("Unpublish"),
        ok_callback = function()
            UIManager:close(dialog)
            local Store = storeModule(); local ok, err = Store and Store.unpublish and Store.unpublish(context.appdock, record.remote_id, record.revision)
            if not ok then notify(_("Could not unpublish: ") .. tostring(err or "")); return end
            record.remote_id, record.revision = nil, nil
            local Presets = presetsModule(); if Presets and Presets.saveDraft then Presets.saveDraft(context.appdock, record, record.id) end
            notify(_("Sleepscreen unpublished. The local copy remains.")); if context.requestRebuild then context.requestRebuild("ui") end
        end }
    UIManager:show(dialog)
end

function Catalog.showLocalActions(instance, context, record)
    local dialog
    local buttons = {
        { { text = _("Rename"), callback = function() UIManager:close(dialog); Catalog.renameLocal(instance, context, record) end } },
        { { text = _("Remove local copy"), callback = function() UIManager:close(dialog); Catalog.confirmRemove(context, record) end } },
    }
    if isOwn(context.appdock, record) then
        buttons[#buttons + 1] = { { text = _("Unpublish"), callback = function() UIManager:close(dialog); Catalog.confirmUnpublish(context, record) end } }
    end
    buttons[#buttons + 1] = { { text = _("Cancel"), callback = function() UIManager:close(dialog) end } }
    dialog = ButtonDialog:new{ title = _("Sleepscreen actions"), buttons = buttons }
    UIManager:show(dialog)
end

local function normalButton(ui, args)
    if ui and ui.PlayPill then return ui.PlayPill:new(args) end
    return CatalogButton:new(args)
end
local function nav(ui, content, state, context, width, height, colors, store_state)
    local nav_height, nav_y = scale(58), height - scale(58)
    content[#content + 1] = FrameContainer:new{ width = width, height = nav_height, padding = 0, bordersize = 0,
        background = colors.background, blank(width, nav_height), overlap_offset = { 0, nav_y } }
    content[#content + 1] = FrameContainer:new{ width = width, height = scale(1), padding = 0, bordersize = 0,
        background = colors.divider or colors.surface_variant, blank(width, scale(1)), overlap_offset = { 0, nav_y } }
    local tabs = {
        { id = "all", label = _("For you"), icon = "grid" }, { id = "dapp", label = _("Apps"), icon = "apps" },
        { id = "widget", label = _("Widgets"), icon = "widgets" }, { id = "design", label = _("Designs"), icon = "designs" },
        { id = "sleepscreen", label = _("Sleepscreens"), icon = "designs" },
    }
    local tab_width = math.floor(width / #tabs)
    for index, tab in ipairs(tabs) do
        local active, x = tab.id == "sleepscreen", (index - 1) * tab_width
        if active then content[#content + 1] = FrameContainer:new{ width = tab_width - scale(10), height = nav_height - scale(14), padding = 0,
            bordersize = 0, radius = scale(14), background = colors.green_container or colors.primary,
            blank(tab_width - scale(10), nav_height - scale(14)), overlap_offset = { x + scale(5), nav_y + scale(7) } } end
        local callback = function()
            if tab.id ~= "sleepscreen" then
                removePreview(state); state.opened = nil
                if context.host and context.host.cropping_widget then context.host.cropping_widget = nil end
            end
            -- The category belongs to AppStore, not its nested catalog state.
            store_state.category = tab.id
            if context.requestRebuild then context.requestRebuild("ui") end
        end
        if ui and ui.PlayNavTab then content[#content + 1] = ui.PlayNavTab:new{ label = tab.label, icon = tab.icon, active = active,
            width = tab_width, height = nav_height, callback = callback, overlap_offset = { x, nav_y } }
        else content[#content + 1] = CatalogButton:new{ title = tab.label, width = tab_width, height = nav_height,
            background = active and (colors.primary or colors.surface) or colors.background, foreground = colors.on_surface,
            callback = callback, overlap_offset = { x, nav_y } } end
    end
    return nav_y
end

function Catalog.buildPane(instance, context, ui)
    local state, colors = stateFor(instance), palette(context.appdock, ui)
    local width, height = context.dimen.w, context.dimen.h
    local margin, gap = scale(12), scale(7)
    local content = OverlapGroup:new{ dimen = Geom:new{ w = width, h = height }, allow_mirroring = false,
        FrameContainer:new{ width = width, height = height, padding = 0, bordersize = 0, background = colors.background, blank(width, height) } }
    local nav_y = nav(ui, content, state, context, width, height, colors, instance.app_store)
    local title = TextWidget:new{ text = _("Sleepscreens"), face = Font:getFace("cfont", scale(19)), fgcolor = colors.on_surface, bold = true, padding = 0,
        overlap_offset = { margin, scale(10) } }
    content[#content + 1] = title
    content[#content + 1] = TextWidget:new{ text = _("Local drafts and public declarative presets"), face = Font:getFace("smallinfofont", scale(10)),
        fgcolor = colors.on_variant, max_width = width - 2 * margin, padding = 0, overlap_offset = { margin, scale(36) } }
    local top_y, tab_h = scale(54), scale(35)
    local half = math.floor((width - 2 * margin - gap) / 2)
    content[#content + 1] = normalButton(ui, { title = _("My drafts"), width = half, height = tab_h,
        background = state.view == "local" and (colors.green_container or colors.primary) or colors.surface,
        foreground = state.view == "local" and (colors.on_green_container or colors.on_surface) or colors.on_surface,
        callback = function() state.view = "local"; if context.requestRebuild then context.requestRebuild("ui") end end,
        overlap_offset = { margin, top_y } })
    content[#content + 1] = normalButton(ui, { title = _("Browse public"), width = width - 2 * margin - half - gap, height = tab_h,
        background = state.view == "browse" and (colors.green_container or colors.primary) or colors.surface,
        foreground = state.view == "browse" and (colors.on_green_container or colors.on_surface) or colors.on_surface,
        callback = function()
            state.view = "browse"; if not state.entries and not state.loading_error then Catalog.refresh(instance, context, state) elseif context.requestRebuild then context.requestRebuild("ui") end
        end, overlap_offset = { margin + half + gap, top_y } })
    local action_y = top_y + tab_h + gap
    if state.view == "browse" then
        content[#content + 1] = normalButton(ui, { title = state.query == "" and _("Search public sleepscreens") or (_("Search: ") .. state.query),
            glyph = ui and "search" or nil, width = width - 2 * margin, height = scale(37), background = colors.surface,
            foreground = colors.on_surface, callback = function() Catalog.promptSearch(instance, context, state) end,
            overlap_offset = { margin, action_y } })
        action_y = action_y + scale(44)
    else
        content[#content + 1] = normalButton(ui, { title = _("New sleepscreen"), width = width - 2 * margin, height = scale(37),
            background = colors.green or colors.primary, foreground = colors.on_green or colors.on_primary,
            callback = function() local Editor = safeRequire("appdock_sleepscreen_editor"); if Editor and Editor.show then Editor.show(context.appdock, context) end end,
            overlap_offset = { margin, action_y } })
        action_y = action_y + scale(44)
    end
    local row_width, row_height = width - 2 * margin, scale(118)
    local rows = {}
    local function appendCard(title_text, detail, definition, asset_paths, actions, defer_public_preview)
        local row_y = (#rows == 0 and 0 or rows._height or 0)
        local preview_w = math.max(scale(95), math.floor(row_width * .37))
        local actions_w, card_h = math.max(scale(78), math.floor(row_width * .22)), row_height
        local card_w = row_width - actions_w - gap
        local widget = defer_public_preview
            and publicPreviewPlaceholder(preview_w, card_h - scale(12), colors)
            or previewWidget(definition, asset_paths, preview_w, card_h - scale(12), context.appdock, colors)
        rows[#rows + 1] = FrameContainer:new{ width = card_w, height = card_h, padding = 0, bordersize = 0, radius = scale(12),
            background = colors.surface, Layout.FixedStack:new{ width = card_w, height = card_h, entries = {
                { widget = widget, x = scale(6), y = scale(6) },
                { widget = TextWidget:new{ text = title_text, face = Font:getFace("smallinfofont", scale(11)), fgcolor = colors.on_surface,
                    bold = true, max_width = card_w - preview_w - scale(16), padding = 0 }, x = preview_w + scale(10), y = scale(14) },
                { widget = TextWidget:new{ text = detail, face = Font:getFace("smallinfofont", scale(9)), fgcolor = colors.on_variant,
                    max_width = card_w - preview_w - scale(16), padding = 0 }, x = preview_w + scale(10), y = scale(38) },
            } }, overlap_offset = { 0, row_y } }
        local button_h = math.max(scale(24), math.floor((card_h - (#actions - 1) * gap) / #actions))
        for index, action in ipairs(actions) do
            rows[#rows + 1] = normalButton(ui, { title = action.title, width = actions_w, height = button_h,
                background = action.danger and (colors.surface_variant or colors.surface) or (action.primary and (colors.green or colors.primary) or colors.surface),
                foreground = action.primary and (colors.on_green or colors.on_primary) or colors.on_surface,
                callback = action.callback, overlap_offset = { card_w + gap, row_y + (index - 1) * (button_h + gap) } })
        end
        rows._height = row_y + card_h + gap
    end
    if state.view == "local" then
        local records = localRecords(context.appdock)
        if #records == 0 then
            appendCard(_("No local sleepscreens"), _("Create a draft; it works without an account."), nil, nil, {
                { title = _("New"), primary = true, callback = function() local Editor = safeRequire("appdock_sleepscreen_editor"); if Editor and Editor.show then Editor.show(context.appdock, context) end end },
            })
        else
            for record_index, record in ipairs(records) do
                local current_record = record
                local action_list = {
                    { title = _("Use"), primary = true, callback = function()
                        local Presets = presetsModule(); local ok, err = Presets and Presets.activate and Presets.activate(context.appdock, current_record.id)
                        if ok then notify(_("Sleepscreen activated.")); if context.requestRebuild then context.requestRebuild("ui") end else notify(_("Could not activate: ") .. tostring(err or "")) end
                    end },
                    { title = _("Edit"), callback = function()
                        local editor_record = copy(current_record)
                        if editor_record.remote_id and not isOwn(context.appdock, editor_record) then
                            editor_record.id, editor_record.remote_id, editor_record.revision, editor_record.creator = nil, nil, nil, nil
                        end
                        local Editor = safeRequire("appdock_sleepscreen_editor"); if Editor and Editor.show then Editor.show(context.appdock, context, editor_record) end
                    end },
                    { title = _("More"), callback = function() Catalog.showLocalActions(instance, context, current_record) end },
                }
                appendCard(recordName(current_record), current_record.remote_id and (_("Published · rev. ") .. tostring(current_record.revision or "?")) or _("Local draft"),
                    current_record.definition, current_record.asset_paths, action_list)
            end
        end
    elseif state.opened then
        local entry, package = state.opened.entry, state.opened.package
        appendCard(entry.name or _("Untitled sleepscreen"), _("Creator: ") .. creatorName(entry) .. _(" · Full package opened"),
            (package and package.definition) or entry.definition, state.preview_paths, {
                { title = _("Download & use"), primary = true, callback = function() Catalog.confirmDownload(context, state, true, false) end },
                { title = _("Download & edit"), callback = function() Catalog.confirmDownload(context, state, false, true) end },
                { title = _("Back to results"), callback = function() removePreview(state); state.opened = nil; if context.requestRebuild then context.requestRebuild("ui") end end },
            })
    elseif state.loading_error then
        appendCard(_("Catalog unavailable"), state.loading_error, nil, nil, { { title = _("Try again"), primary = true, callback = function() Catalog.refresh(instance, context, state) end } })
    elseif not state.entries then
        appendCard(_("Public catalog"), _("Browse public presets without an account."), nil, nil, { { title = _("Load catalog"), primary = true, callback = function() Catalog.refresh(instance, context, state) end } })
    elseif #state.entries == 0 then
        appendCard(_("No matching sleepscreens"), _("Change the search or try again later."), nil, nil, { { title = _("Search"), primary = true, callback = function() Catalog.promptSearch(instance, context, state) end } })
    else
        for entry_index, entry in ipairs(state.entries) do
            local current_entry = entry
            appendCard(current_entry.name or _("Untitled sleepscreen"), _("Creator: ") .. creatorName(current_entry), current_entry.definition, nil, {
                { title = _("Open"), primary = true, callback = function() Catalog.openRemote(instance, context, state, current_entry) end },
            }, true)
        end
        local pager_y = rows._height or 0
        if state.offset > 0 then rows[#rows + 1] = normalButton(ui, { title = _("Previous page"), width = math.floor((row_width - gap) / 2), height = scale(34),
            background = colors.surface, foreground = colors.on_surface, callback = function() state.offset = math.max(0, state.offset - PAGE_SIZE); Catalog.refresh(instance, context, state) end,
            overlap_offset = { 0, pager_y } }) end
        if state.has_more then rows[#rows + 1] = normalButton(ui, { title = _("Next page"), width = math.floor((row_width - gap) / 2), height = scale(34),
            background = colors.green or colors.primary, foreground = colors.on_green or colors.on_primary, callback = function() state.offset = state.offset + PAGE_SIZE; Catalog.refresh(instance, context, state) end,
            overlap_offset = { state.offset > 0 and math.floor((row_width - gap) / 2) + gap or 0, pager_y } }) end
        rows._height = pager_y + scale(41)
    end
    local list_height = math.max(scale(60), nav_y - action_y - margin)
    local content_height = math.max(list_height, rows._height or list_height)
    rows._height = nil
    local list_content = OverlapGroup:new{ dimen = Geom:new{ w = row_width, h = content_height }, allow_mirroring = false, unpack(rows) }
    local scrollable = ScrollableContainer:new{ dimen = Geom:new{ w = row_width + ScrollableContainer:getScrollbarWidth(), h = list_height },
        show_parent = context.host, list_content, overlap_offset = { margin, action_y } }
    content[#content + 1] = scrollable
    -- KOReader uses this marker on the widget shown by UIManager to route
    -- self-refreshes from children through the scroll viewport. Public
    -- previews contain renderer/image widgets; without the marker, a refresh
    -- during scrolling can target the full host and crash on affected builds.
    local pane = WidgetContainer:new{ dimen = Geom:new{ w = width, h = height }, content }
    pane.cropping_widget = scrollable
    if context.host then context.host.cropping_widget = scrollable end
    return pane
end

function Catalog.cleanup(instance)
    local state = instance and instance.app_store and instance.app_store.sleepscreen_catalog
    removePreview(state)
end
Catalog._test = { stateFor = stateFor, packagePreviewPaths = packagePreviewPaths, isOwn = isOwn, CatalogButton = CatalogButton }
return Catalog
