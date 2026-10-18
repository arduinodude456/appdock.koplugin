-- Native editor for declarative AppDock sleep-screen presets.
-- Draft edits stay in this widget until Save; the active/saved record is never
-- mutated through a shared table reference.
local Blitbuffer = require("ffi/blitbuffer")
local AppDockDialogs = require("appdock_dialogs")
local ButtonDialog = AppDockDialogs.ButtonDialog
local ConfirmBox = AppDockDialogs.ConfirmBox
local InputDialog = AppDockDialogs.InputDialog
local InfoMessage = AppDockDialogs.InfoMessage
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

local Editor = {}
local Screen = Device.screen
local MODULE_DIR = (debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "")

local function requireAppDockModule(name)
    local previous_path = package.path
    package.path = MODULE_DIR .. "?.lua;" .. previous_path
    local ok, module = pcall(require, name)
    package.path = previous_path
    return ok and module or nil
end

local function scale(value) return Screen:scaleBySize(value) end
local function trim(value) return type(value) == "string" and value:gsub("^%s+", ""):gsub("%s+$", "") or "" end
local function shorten(value, limit)
    value = tostring(value or "")
    if #value <= limit then return value end
    return value:sub(1, math.max(1, limit - 1)) .. "…"
end
local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}; seen[value] = result
    for key, item in pairs(value) do result[copy(key, seen)] = copy(item, seen) end
    return result
end
local function notify(text) UIManager:show(InfoMessage:new{ text = text }) end
local function palette(appdock)
    local ok, Theme = pcall(require, "appdock_theme")
    if ok and Theme and Theme.getPalette then return Theme.getPalette(appdock) end
    return { background = Blitbuffer.COLOR_WHITE, surface = Blitbuffer.COLOR_LIGHT_GRAY,
        surface_variant = Blitbuffer.COLOR_GRAY_8, primary = Blitbuffer.COLOR_GRAY_8,
        on_primary = Blitbuffer.COLOR_BLACK, on_surface = Blitbuffer.COLOR_BLACK,
        on_variant = Blitbuffer.COLOR_DARK_GRAY, tertiary = Blitbuffer.COLOR_DARK_GRAY,
        on_tertiary = Blitbuffer.COLOR_WHITE }
end
local function blank(width, height)
    local CenterContainer = require("ui/widget/container/centercontainer")
    return CenterContainer:new{ dimen = Geom:new{ w = width, h = height }, HorizontalSpan:new{ width = 0 } }
end

-- A deliberately small touch target used everywhere in the editor.  Controls
-- never share a GestureRange with the preview, which prevents tap-through.
local EditorButton = InputContainer:extend{
    title = nil, subtitle = nil, callback = nil, width = nil, height = nil,
    background = nil, foreground = nil, selected = false, dimen = nil,
}
function EditorButton:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local inset, title_size = scale(9), math.max(scale(8), math.floor(self.height * .25))
    local sub_size = math.max(scale(7), math.floor(self.height * .18))
    local title = TextWidget:new{ text = self.title or "", face = Font:getFace("smallinfofont", title_size),
        fgcolor = self.foreground, bold = true, max_width = self.width - 2 * inset, padding = 0 }
    local subtitle = self.subtitle and self.subtitle ~= "" and TextWidget:new{
        text = self.subtitle, face = Font:getFace("smallinfofont", sub_size), fgcolor = self.foreground,
        max_width = self.width - 2 * inset, padding = 0 } or nil
    local ty = subtitle and math.max(inset, math.floor((self.height - title:getSize().h - subtitle:getSize().h - scale(2)) / 2))
        or math.max(inset, math.floor((self.height - title:getSize().h) / 2))
    self[1] = FrameContainer:new{ width = self.width, height = self.height, padding = 0,
        bordersize = self.selected and scale(1) or 0, color = self.foreground,
        radius = math.floor(self.height * .22), background = self.background,
        Layout.FixedStack:new{ width = self.width, height = self.height, entries = (function()
            local entries = { { widget = title, x = inset, y = ty } }
            if subtitle then entries[#entries + 1] = { widget = subtitle, x = inset, y = ty + title:getSize().h + scale(2) } end
            return entries
        end)() } }
    self.ges_events = { TapSleepEditorButton = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end
function EditorButton:paintTo(bb, x, y)
    local range = self.ges_events.TapSleepEditorButton[1].range
    range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    return InputContainer.paintTo(self, bb, x, y)
end
function EditorButton:onTapSleepEditorButton() if self.callback then self.callback() end; return true end

local SleepEditor = InputContainer:extend{
    appdock = nil, context = nil, record = nil, draft = nil, original = nil,
    selected = nil, section = nil, dirty = false, dimen = nil, covers_fullscreen = true,
}

function SleepEditor:_presets()
    return requireAppDockModule("appdock_sleepscreen_presets")
end
function SleepEditor:_renderer()
    return requireAppDockModule("appdock_sleepscreen_renderer")
end
function SleepEditor:_store()
    return requireAppDockModule("appdock_sleepscreen_store")
end
function SleepEditor:_rebuildHost()
    if self.context and self.context.requestRebuild then self.context.requestRebuild("ui") end
end
function SleepEditor:_changed()
    self.dirty = true
    self:rebuild()
    UIManager:setDirty(self, "ui")
    if UIManager.forceRePaint then UIManager:forceRePaint() end
end
function SleepEditor:_definition()
    self.draft.definition = self.draft.definition or { schema_version = 1, name = "Untitled sleepscreen", description = "", background = "#FFFFFF", elements = {}, assets = {} }
    self.draft.definition.elements = self.draft.definition.elements or {}
    self.draft.definition.assets = self.draft.definition.assets or {}
    self.draft.definition.widgets = self.draft.definition.widgets or {}
    return self.draft.definition
end
function SleepEditor:_element()
    local items = self:_definition().elements
    if self.selected and items[self.selected] then return items[self.selected] end
    self.selected = #items > 0 and 1 or nil
    return self.selected and items[self.selected] or nil
end
function SleepEditor:init()
    self.dimen = Geom:new{ w = Screen:getWidth(), h = Screen:getHeight() }
    local Presets = self:_presets()
    local source = self.record and copy(self.record) or (Presets and Presets.newDraft and Presets.newDraft() or nil)
    self.draft = source or { definition = { schema_version = 1, name = "Untitled sleepscreen", description = "", background = "#FFFFFF", elements = {}, assets = {} }, asset_paths = {} }
    self.draft.asset_paths = self.draft.asset_paths or {}
    self.original = copy(self.draft)
    self.selected = #self:_definition().elements > 0 and 1 or nil
    self.section = self.section or "screen"
    self:rebuild()
end

function SleepEditor:_showInput(title, value, hint, apply)
    local dialog
    dialog = InputDialog:new{ title = title, input = tostring(value or ""), input_hint = hint or "",
        buttons = { {
            { text = _("Cancel"), callback = function() UIManager:close(dialog) end },
            { text = _("Apply"), is_enter_default = true, callback = function()
                local entered = trim(dialog:getInputText())
                UIManager:close(dialog)
                local ok, err = apply(entered)
                if ok == false then notify(tostring(err or _("That value is not valid."))) else self:_changed() end
            end },
        } } }
    UIManager:show(dialog)
    if dialog.onShowKeyboard then dialog:onShowKeyboard() end
end

function SleepEditor:_addElement(kind)
    local definition = self:_definition()
    if #definition.elements >= 32 then notify(_("A sleepscreen can contain at most 32 elements.")); return end
    local element = { type = kind, x = 8, y = 8, w = 84, h = kind == "text" and 16 or 24,
        color = "#000000", background = "#FFFFFF", align = "left", font = "cfont", font_size = 20,
        bold = false }
    if kind == "text" then element.text = _("New text")
    elseif kind == "card" then element.text = _("Card text")
    elseif kind == "widget" then element.source = "clock"
    elseif kind == "image" then element.images = {}; element.fit = "contain" end
    definition.elements[#definition.elements + 1] = element
    self.selected = #definition.elements
    self.section = "edit"
    self:_changed()
end

function SleepEditor:showAddMenu()
    local dialog
    dialog = ButtonDialog:new{ title = _("Add element"), text = _("Elements are declarative and stay inside the selected percentage bounds."), buttons = {
        { { text = _("Text"), callback = function() UIManager:close(dialog); self:_addElement("text") end } },
        { { text = _("Image"), callback = function() UIManager:close(dialog); self:_addElement("image") end } },
        { { text = _("Card"), callback = function() UIManager:close(dialog); self:_addElement("card") end } },
        { { text = _("Widget"), callback = function() UIManager:close(dialog); self:_addElement("widget") end } },
        { { text = _("Cancel"), callback = function() UIManager:close(dialog) end } },
    } }
    UIManager:show(dialog)
end

function SleepEditor:_customWidgets()
    local definition = self:_definition()
    definition.widgets = definition.widgets or {}
    return definition.widgets
end

function SleepEditor:_selectedCustomWidget()
    local widgets = self:_customWidgets()
    for _, widget in ipairs(widgets) do
        if widget.id == self.selected_widget_id then return widget end
    end
    return widgets[1]
end

function SleepEditor:_createCustomWidget()
    local widgets = self:_customWidgets()
    if #widgets >= 16 then notify(_("A sleepscreen can contain at most 16 custom widgets.")); return end
    local widget = { id = "widget-" .. tostring(os.time()) .. "-" .. tostring(#widgets + 1), name = _("New widget"), text = "{time}" }
    widgets[#widgets + 1] = widget
    self.selected_widget_id = widget.id
    local element = self:_element()
    if element and element.type == "widget" then element.source = nil; element.widget_id = widget.id end
    self.section = "widgets"
    self:_changed()
end

function SleepEditor:_deleteCustomWidget(widget)
    local widgets = self:_customWidgets()
    for index, candidate in ipairs(widgets) do
        if candidate.id == widget.id then table.remove(widgets, index); break end
    end
    for _, element in ipairs(self:_definition().elements) do
        if element.widget_id == widget.id then element.widget_id = nil; element.source = "clock" end
    end
    self.selected_widget_id = widgets[1] and widgets[1].id or nil
    self:_changed()
end

function SleepEditor:_refreshWeather(widget)
    local ok, Weather = pcall(require, "appdock_sleepscreen_weather")
    if not ok or not Weather or not Weather.fetch then notify(_("Weather support is unavailable.")); return end
    local result, err = Weather.fetch(widget.latitude, widget.longitude)
    if not result then notify(_("Could not update weather: ") .. tostring(err or "")); return end
    widget.weather_cache = result
    self:_changed()
    notify(_("Weather updated: ") .. result.temperature .. " · " .. result.description)
end


function SleepEditor:showFontMenu()
    local element = self:_element(); if not element then return end
    local fonts = { "cfont", "infofont", "smallinfofont" }
    local buttons, dialog = {}, nil
    for _, asset in ipairs(self:_definition().assets) do
        if asset.kind == "font" then fonts[#fonts + 1] = "asset:" .. asset.id end
    end
    for _, name in ipairs(fonts) do
        buttons[#buttons + 1] = { { text = name, callback = function()
            element.font = name; self:_changed(); UIManager:close(dialog)
        end } }
    end
    buttons[#buttons + 1] = { { text = _("Import TTF/OTF font"), callback = function() UIManager:close(dialog); self:chooseAsset("font") end } }
    buttons[#buttons + 1] = { { text = _("Cancel"), callback = function() UIManager:close(dialog) end } }
    -- Lua closures above need the local assigned before a button can be tapped.
    dialog = ButtonDialog:new{ title = _("Font"), text = _("Built-in fonts or an imported TTF/OTF asset."), buttons = buttons }
    UIManager:show(dialog)
end

function SleepEditor:_afterAsset(path, kind)
    if type(path) ~= "string" or path == "" then return end
    local Presets = self:_presets()
    if not Presets or not Presets.importAsset then notify(_("Sleep-screen asset import is unavailable.")); return end
    local asset_id, err = Presets.importAsset(self.draft, path, kind)
    if not asset_id then notify(_("Could not import asset: ") .. tostring(err or "")); return end
    local element = self:_element()
    if kind == "font" and element then element.font = "asset:" .. asset_id end
    if kind == "image" and element then
        if element.type ~= "image" then element.type = "image"; element.images = {}; element.source = nil end
        element.images = element.images or {}; element.images[#element.images + 1] = asset_id
    end
    self:_changed()
    notify(_("Imported asset: ") .. asset_id)
end

-- FileChooser is optional in older KOReader builds.  The explicit path dialog
-- remains a safe fallback and is useful on devices without a touchscreen file
-- chooser.  No URL is ever accepted as an asset path.
function SleepEditor:chooseAsset(kind)
    local ok, FileChooser = pcall(require, "ui/widget/filechooser")
    if ok and FileChooser and FileChooser.new then
        local chooser
        local chooser_ui = { selected_files = {}, folder_shortcuts = {
            getShortcutFullName = function() return nil end,
            hasShortcut = function() return false end, hasFolderShortcut = function() return false end,
        } }
        local created, widget = pcall(function() return FileChooser:new{
            name = "appdock_sleepscreen_asset", ui = chooser_ui, path = Device.home_dir or "/", show_path = true,
            title_text = kind == "font" and _("Choose TTF or OTF font") or _("Choose image"),
            file_filter = function(path)
                local ext = type(path) == "string" and path:lower():match("%.([a-z0-9]+)$")
                return kind == "font" and (ext == "ttf" or ext == "otf")
                    or kind == "image" and (ext == "png" or ext == "jpg" or ext == "jpeg" or ext == "webp")
            end,
        } end)
        if created and widget then
            chooser = widget
            local editor = self
            function chooser:onFileSelect(item)
                local path = item and item.path
                UIManager:close(self)
                local selected = function() if path then editor:_afterAsset(path, kind) end end
                if UIManager.nextTick then UIManager:nextTick(selected) else selected() end
                return true
            end
            UIManager:show(chooser); return
        end
    end
    self:_showInput(kind == "font" and _("Import font path") or _("Import image path"), "",
        kind == "font" and _("Local .ttf or .otf file") or _("Local .png, .jpg, .jpeg, or .webp file"),
        function(path)
            if path:find("://", 1, true) or path:sub(1, 1) ~= "/" then return false, _("Choose a local absolute file path.") end
            self:_afterAsset(path, kind); return true
        end)
end

function SleepEditor:showImageMenu()
    local element = self:_element(); if not element then return end
    local dialog
    dialog = ButtonDialog:new{ title = _("Image"), text = _("Import one or more local images. Multiple images rotate once per sleep cycle."), buttons = {
        { { text = _("Add image"), callback = function() UIManager:close(dialog); self:chooseAsset("image") end } },
        { { text = _("Fit: ") .. (element.fit == "cover" and _("Cover") or _("Contain")), callback = function()
            element.fit = element.fit == "cover" and "contain" or "cover"; self:_changed(); UIManager:close(dialog)
        end } },
        { { text = _("Clear images"), callback = function()
            element.type, element.images, element.fit = "text", nil, nil
            element.text = ""; self:_changed(); UIManager:close(dialog)
        end } },
        { { text = _("Cancel"), callback = function() UIManager:close(dialog) end } },
    } }
    UIManager:show(dialog)
end

function SleepEditor:moveSelected(delta)
    local definition, index = self:_definition(), self.selected
    if not index then return end
    local next_index = index + delta
    if next_index < 1 or next_index > #definition.elements then return end
    definition.elements[index], definition.elements[next_index] = definition.elements[next_index], definition.elements[index]
    self.selected = next_index; self:_changed()
end
function SleepEditor:removeSelected()
    local definition, index = self:_definition(), self.selected
    if not index then return end
    table.remove(definition.elements, index); self.selected = math.min(index, #definition.elements)
    if #definition.elements == 0 then self.selected = nil end
    self:_changed()
end

function SleepEditor:_save(activate)
    local Presets = self:_presets()
    if not Presets or not Presets.saveDraft then notify(_("Sleep-screen storage is unavailable.")); return nil end
    local saved, err = Presets.saveDraft(self.appdock, self.draft, self.record and self.record.id or nil)
    if not saved then notify(_("Could not save draft: ") .. tostring(err or "")); return nil end
    self.record, self.draft, self.original, self.dirty = saved, copy(saved), copy(saved), false
    local activation_error
    if activate then
        if Presets.activate then
            local activated, activate_err = Presets.activate(self.appdock, saved.id)
            if not activated then activation_error = activate_err end
        else
            activation_error = _("Activation is unavailable.")
        end
    end
    self:_rebuildHost(); self:rebuild(); UIManager:setDirty(self, "ui")
    if activation_error then notify(_("Saved, but could not activate: ") .. tostring(activation_error or ""))
    elseif activate then notify(_("Saved and activated sleepscreen."))
    else notify(_("Sleep-screen draft saved locally.")) end
    return saved
end
function SleepEditor:save() self:_save(false) end
function SleepEditor:saveAndActivate() self:_save(true) end

function SleepEditor:_publishAfterAccount()
    local saved = self:_save(false); if not saved then return end
    local Presets, Store = self:_presets(), self:_store()
    if not Presets or not Store or not Presets.exportPackage or not Store.publish then notify(_("Publishing is unavailable.")); return end
    local package, export_err = Presets.exportPackage(saved)
    if not package then notify(_("Could not prepare preset: ") .. tostring(export_err or "")); return end
    local assets = #((package.definition or {}).assets or {})
    local weather_widgets = 0
    for _, widget in ipairs((package.definition or {}).widgets or {}) do
        if widget.weather then weather_widgets = weather_widgets + 1 end
    end
    local remote_id, revision = saved.remote_id, saved.revision
    local creator_label = _("your TBS account")
    local account_ok, Account = pcall(require, "appdock_tbs_account")
    if account_ok and Account and Account.status then
        local status_ok, status = pcall(Account.status, self.appdock)
        if status_ok and type(status) == "table" then
            creator_label = status.display_name or status.account_id or creator_label
            if remote_id and (not saved.creator or saved.creator.account_id ~= status.account_id) then
                remote_id, revision = nil, nil
            end
        end
    end
    local dialog
    dialog = ConfirmBox:new{
        text = _("Publish sleepscreen publicly?") .. "\n\n" .. _("Name: ") .. tostring((package.definition or {}).name or "")
            .. "\n" .. _("Creator: ") .. tostring(creator_label) .. "\n" .. _("Assets shared: ") .. tostring(assets)
            .. "\n" .. _("Weather widgets: ") .. tostring(weather_widgets)
            .. "\n\n" .. _("Only this preset definition and the selected assets are shared. Weather widget coordinates and cached conditions are included if configured. No books, local paths, device values, or account secrets are uploaded."),
        ok_text = remote_id and _("Update public preset") or _("Publish"),
        ok_callback = function()
            UIManager:close(dialog)
            local entry, err = Store.publish(self.appdock, package, remote_id, remote_id and revision or nil)
            if not entry then notify(_("Could not publish: ") .. tostring(err or "")); return end
            self.record.remote_id, self.record.revision, self.record.creator = entry.id, entry.revision, entry.creator
            self.draft.remote_id, self.draft.revision, self.draft.creator = entry.id, entry.revision, entry.creator
            local persisted, persist_err = Presets.saveDraft(self.appdock, self.draft, self.record.id)
            if persisted then self.record, self.draft, self.original = persisted, copy(persisted), copy(persisted) end
            if not persisted then
                notify(_("Published, but the local publication revision could not be saved: ") .. tostring(persist_err or ""))
            end
            self.dirty = false; self:_rebuildHost(); self:rebuild(); notify(_("Sleepscreen published."))
        end,
    }
    UIManager:show(dialog)
end

function SleepEditor:publish()
    local ok, Account = pcall(require, "appdock_tbs_account")
    if not ok or not Account or not Account.require then notify(_("TBS account support is unavailable.")); return end
    Account.require(self.appdock, _("Publish sleepscreen"), function(ready)
        if ready then self:_publishAfterAccount() end
    end)
end

function SleepEditor:closeEditor()
    if not self.dirty then UIManager:close(self); return end
    local dialog
    dialog = ConfirmBox:new{ text = _("Discard unsaved sleep-screen changes?"), ok_text = _("Discard"),
        ok_callback = function() UIManager:close(dialog); UIManager:close(self) end }
    UIManager:show(dialog)
end

function SleepEditor:_preview(width, height, colors)
    local Renderer = self:_renderer()
    if Renderer and Renderer.build then
        local ok, widget = pcall(Renderer.build, self:_definition(), width, height, {
            appdock = self.appdock, asset_paths = self.draft.asset_paths, preview = true, cycle = 0,
        })
        if ok and widget then return widget end
    end
    return FrameContainer:new{ width = width, height = height, padding = 0, bordersize = 0,
        background = colors.surface, blank(width, height) }
end

local function sectionDefinitions()
    return {
        { id = "screen", title = _("Screen") },
        { id = "elements", title = _("Elements") },
        { id = "widgets", title = _("Custom widgets") },
        { id = "edit", title = _("Edit") },
        { id = "save", title = _("Save") },
    }
end

function SleepEditor:_sectionTabs(width, colors)
    local sections, entries = sectionDefinitions(), {}
    local gap, height = scale(4), scale(32)
    local tab_width = math.max(1, math.floor((width - gap * (#sections - 1)) / #sections))
    for index, section in ipairs(sections) do
        local id, title = section.id, section.title
        local selected = self.section == id
        local button_width = index == #sections and width - (index - 1) * (tab_width + gap) or tab_width
        entries[#entries + 1] = { widget = EditorButton:new{
            title = title, width = button_width, height = height, selected = selected,
            background = selected and colors.primary or (colors.surface_variant or colors.surface),
            foreground = selected and colors.on_primary or colors.on_surface,
            callback = function()
                self.section = id
                self:rebuild()
                UIManager:setDirty(self, "ui")
            end,
        }, x = (index - 1) * (tab_width + gap), y = 0 }
    end
    return Layout.FixedStack:new{ width = width, height = height, entries = entries }
end

function SleepEditor:_sectionRows(panel_width, colors)
    local items = {}
    local definition, element = self:_definition(), self:_element()
    local padding, gap = scale(8), scale(6)
    local VerticalSpan = require("ui/widget/verticalspan")

    local function addGroup(title, description, fields)
        local content_width = math.max(scale(80), panel_width - padding * 2)
        local cell_width = math.max(1, math.floor((content_width - gap) / 2))
        local button_height = scale(46)
        local heading = TextWidget:new{ text = title, face = Font:getFace("cfont", scale(11)),
            fgcolor = colors.on_surface, bold = true, max_width = content_width, padding = 0 }
        local hint = description and description ~= "" and TextWidget:new{
            text = description, face = Font:getFace("smallinfofont", scale(8)),
            fgcolor = colors.on_variant, max_width = content_width, padding = 0,
        } or nil
        local entries = {
            { widget = heading, x = padding, y = padding },
        }
        local y = padding + heading:getSize().h + scale(2)
        if hint then
            entries[#entries + 1] = { widget = hint, x = padding, y = y }
            y = y + hint:getSize().h + scale(5)
        else
            y = y + scale(5)
        end

        local column = 0
        for _, field in ipairs(fields) do
            local wide = field.wide == true
            if wide and column == 1 then y = y + button_height + gap; column = 0 end
            local button_width = wide and content_width or cell_width
            local x = padding + (wide and 0 or column * (cell_width + gap))
            local selected = field.selected == true
            local button = EditorButton:new{
                title = field.title, subtitle = shorten(field.value or "", 38),
                callback = field.callback, width = button_width, height = button_height,
                selected = selected,
                background = field.background or (selected and colors.primary or (colors.surface_variant or colors.surface)),
                foreground = field.foreground or (selected and colors.on_primary or colors.on_surface),
            }
            entries[#entries + 1] = { widget = button, x = x, y = y }
            if wide then
                y = y + button_height + gap
            elseif column == 0 then
                column = 1
            else
                column = 0
                y = y + button_height + gap
            end
        end
        if column == 1 then y = y + button_height + gap end
        local card_height = y + padding
        items[#items + 1] = FrameContainer:new{
            width = panel_width, height = card_height, padding = 0, bordersize = 0,
            radius = scale(9), background = colors.surface,
            Layout.FixedStack:new{ width = panel_width, height = card_height, entries = entries },
        }
        items[#items + 1] = VerticalSpan:new{ width = scale(7) }
    end

    local function field(title, value, callback, options)
        options = options or {}
        return { title = title, value = tostring(value or ""), callback = callback,
            wide = options.wide, selected = options.selected,
            background = options.background, foreground = options.foreground }
    end

    if self.section == "screen" then
        addGroup(_("Screen basics"), _("Name and describe this sleep screen, then choose its background."), {
            field(_("Name"), definition.name, function()
                self:_showInput(_("Preset name"), definition.name, _("1–80 characters"), function(value)
                    if value == "" or #value > 80 then return false, _("Use a name from 1 to 80 characters.") end
                    definition.name = value; return true
                end)
            end),
            field(_("Description"), definition.description ~= "" and definition.description or _("Optional"), function()
                self:_showInput(_("Description"), definition.description or "", _("Optional, up to 500 characters"), function(value)
                    if #value > 500 then return false, _("Use at most 500 characters.") end
                    definition.description = value; return true
                end)
            end),
            field(_("Background"), definition.background or "#FFFFFF", function()
                self:_showInput(_("Background color"), definition.background, _("#RRGGBB"), function(value)
                    if not value:match("^#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$") then return false, _("Use #RRGGBB.") end
                    definition.background = value:upper(); return true
                end)
            end),
        })
    elseif self.section == "elements" then
        addGroup(_("Add an element"), _("Build the screen from simple text, images, cards, or live widgets."), {
            field(_("Text"), _("Text block"), function() self:_addElement("text") end),
            field(_("Image"), _("Local image"), function() self:_addElement("image") end),
            field(_("Card"), _("Text card"), function() self:_addElement("card") end),
            field(_("Widget"), _("Clock, date, battery"), function() self:_addElement("widget") end),
            field(_("Custom widget"), _("Create and connect a live-preview widget"), function() self:_addElement("widget"); self:_createCustomWidget() end),
        })
        local element_fields = {}
        for index, candidate in ipairs(definition.elements) do
            local element_index = index
            local summary = candidate.text or candidate.source or ""
            if candidate.type == "image" then summary = string.format(_("%d image(s)"), #(candidate.images or {})) end
            if summary == "" then summary = _("Tap to edit this element") end
            element_fields[#element_fields + 1] = field(
                string.format("%02d · %s", index, candidate.type or _("element")), summary,
                function()
                    self.selected, self.section = element_index, "edit"
                    self:rebuild(); UIManager:setDirty(self, "ui")
                end,
                { wide = true, selected = element_index == self.selected })
        end
        if #element_fields == 0 then
            element_fields[1] = field(_("No elements yet"), _("Add one above to start arranging your screen."),
                function() self:showAddMenu() end, { wide = true })
        end
        addGroup(_("Layers"), _("Select a layer to edit its content, position, or style."), element_fields)
    elseif self.section == "widgets" then
        local widget_fields = {
            field(_("Create custom widget"), _("Start with a live-preview widget"), function() self:_createCustomWidget() end, { wide = true }),
        }
        local gettext = _
        for _, selected_widget in ipairs(self:_customWidgets()) do
            local summary = selected_widget.text or gettext("No text")
            if selected_widget.weather then summary = gettext("Open-Meteo weather") .. " · " .. (selected_widget.weather_cache and selected_widget.weather_cache.temperature or gettext("not fetched")) end
            if selected_widget.frames then summary = summary .. " · " .. tostring(#selected_widget.frames) .. gettext(" frames") end
            widget_fields[#widget_fields + 1] = field((self.selected_widget_id == selected_widget.id and "● " or "") .. selected_widget.name,
                summary, function() self.selected_widget_id = selected_widget.id; self:_changed() end, { wide = true, selected = self.selected_widget_id == selected_widget.id })
        end
        addGroup(_("Widget library"), _("Select a widget to edit it. Changes appear in the preview as soon as you apply them."), widget_fields)
        local widget = self:_selectedCustomWidget()
        if widget then
            self.selected_widget_id = widget.id
            addGroup(_("Edit: ") .. widget.name, _("Reusable content, time rules, animation, and live data."), {
                field(_("Name"), widget.name, function() self:_showInput(_("Widget name"), widget.name, _("1–60 characters"), function(value)
                    if value == "" or #value > 60 then return false, _("Use a name from 1 to 60 characters.") end
                    widget.name = value; return true
                end) end, { wide = true }),
                field(_("Text template"), widget.text or "", function() self:_showInput(_("Widget text"), widget.text or "", _("{time}, {date}, {battery}, {device}, {temperature}, {weather}"), function(value)
                    if #value > 2000 then return false, _("Use at most 2000 characters.") end
                    widget.text = value; return true
                end) end, { wide = true }),
                field(_("Animation frames"), widget.frames and tostring(#widget.frames) or _("Off"), function()
                    local values = {}; for _, frame in ipairs(widget.frames or {}) do values[#values + 1] = frame.text end
                    self:_showInput(_("Animation frames"), table.concat(values, "|"), _("Separate frames with |"), function(value)
                        local frames = {}
                        if value ~= "" then for frame in (value .. "|"):gmatch("(.-)|") do frames[#frames + 1] = { text = frame, duration = 1 } end end
                        if #frames > 12 then return false, _("Use at most 12 frames.") end
                        widget.frames = #frames > 0 and frames or nil
                        return true
                    end)
                end, { wide = true }),
                field(_("Time rules"), widget.schedule_text or _("Off"), function()
                    self:_showInput(_("Time-based texts"), widget.schedule_text or "", _("06:00-12:00=Good morning;18:00-23:59=Good evening"), function(value)
                        local schedule = {}
                        for rule in (value .. ";"):gmatch("(.-);") do
                            local from, to, text = rule:match("^(%d%d:%d%d)%-(%d%d:%d%d)=(.*)$")
                            if from then schedule[#schedule + 1] = { from = from, to = to, text = text }
                            elseif rule ~= "" then return false, _("Use HH:MM-HH:MM=Text; separate rules with semicolons.") end
                        end
                        if #schedule > 12 then return false, _("Use at most 12 time rules.") end
                        widget.schedule, widget.schedule_text = #schedule > 0 and schedule or nil, value
                        return true
                    end)
                end, { wide = true }),
                field(_("Weather API"), widget.weather and _("Open-Meteo enabled") or _("Off · no API key needed"), function()
                    widget.weather = not widget.weather
                    if widget.weather then widget.latitude, widget.longitude = widget.latitude or "52.5200", widget.longitude or "13.4050" end
                    self:_changed()
                end),
            })
            if widget.weather then
                addGroup(_("Open-Meteo · current conditions"), _("Public weather API; no key required. Fetch manually so sleep-screen rendering never waits on the network."), {
                    field(_("Latitude"), widget.latitude or "52.5200", function() self:_showInput(_("Latitude"), widget.latitude or "52.5200", _("−90 to 90"), function(value)
                        local n = tonumber(value); if not n or n < -90 or n > 90 then return false, _("Enter a latitude from −90 to 90.") end
                        widget.latitude = value; return true
                    end) end),
                    field(_("Longitude"), widget.longitude or "13.4050", function() self:_showInput(_("Longitude"), widget.longitude or "13.4050", _("−180 to 180"), function(value)
                        local n = tonumber(value); if not n or n < -180 or n > 180 then return false, _("Enter a longitude from −180 to 180.") end
                        widget.longitude = value; return true
                    end) end),
                    field(_("Fetch current weather"), widget.weather_cache and ((widget.weather_cache.temperature or "") .. " · " .. (widget.weather_cache.description or "")) or _("Tap to fetch"), function() self:_refreshWeather(widget) end, { wide = true }),
                })
            end
            local bound = false
            for _, layer in ipairs(definition.elements) do if layer.type == "widget" and layer.widget_id == widget.id then bound = true end end
            addGroup(_("Use this widget"), bound and _("This widget is shown in a screen layer; preview reflects your edits.") or _("Add it to the selected layer to see it on the preview."), {
                field(bound and _("Widget is connected") or _("Add to selected widget layer"), element and element.type == "widget" and _("Use selected layer") or _("Create a widget layer first in Elements"), function()
                    if element and element.type == "widget" then element.source, element.widget_id = nil, widget.id; self:_changed()
                    else notify(_("Add a Widget element first in the Elements tab.")) end
                end, { wide = true }),
                field(_("Delete widget"), _("Remove it from the library and layers"), function() self:_deleteCustomWidget(widget) end, { wide = true, background = colors.tertiary, foreground = colors.on_tertiary }),
            })
        end
    elseif self.section == "edit" then
        if not element then
            addGroup(_("Nothing selected"), _("Choose an element from the Elements tab, or add your first one."), {
                field(_("Open elements"), _("Add or select a layer"), function()
                    self.section = "elements"; self:rebuild(); UIManager:setDirty(self, "ui")
                end, { wide = true }),
            })
        else
            addGroup(_("Layout & order"), _("Coordinates and size are percentages of the screen."), {
                field(_("Position x / y"), string.format("%s%% / %s%%", tostring(element.x or 0), tostring(element.y or 0)), function()
                    self:_showInput(_("Position x,y (%)"), string.format("%s,%s", tostring(element.x or 0), tostring(element.y or 0)), _("Example: 10,15"), function(value)
                        local x, y = value:match("^(%d+)%s*,%s*(%d+)$"); x, y = tonumber(x), tonumber(y)
                        if not x or not y or x > 100 or y > 100 or x + (tonumber(element.w) or 1) > 100 or y + (tonumber(element.h) or 1) > 100 then return false, _("Bounds must stay inside 0 to 100 percent.") end
                        element.x, element.y = x, y; return true
                    end)
                end),
                field(_("Size w / h"), string.format("%s%% / %s%%", tostring(element.w or 0), tostring(element.h or 0)), function()
                    self:_showInput(_("Size width,height (%)"), string.format("%s,%s", tostring(element.w or 1), tostring(element.h or 1)), _("Example: 80,20"), function(value)
                        local w, h = value:match("^(%d+)%s*,%s*(%d+)$"); w, h = tonumber(w), tonumber(h)
                        if not w or not h or w < 1 or h < 1 or w > 100 or h > 100 or (tonumber(element.x) or 0) + w > 100 or (tonumber(element.y) or 0) + h > 100 then return false, _("Bounds must stay inside 0 to 100 percent.") end
                        element.w, element.h = w, h; return true
                    end)
                end),
                field(_("Move earlier"), _("Change layer order"), function() self:moveSelected(-1) end),
                field(_("Move later"), _("Change layer order"), function() self:moveSelected(1) end),
                field(_("Remove element"), _("Delete this draft layer"), function() self:removeSelected() end, {
                    wide = true, background = colors.tertiary, foreground = colors.on_tertiary,
                }),
            })

            local content_fields = {}
            if element.type == "text" or element.type == "card" then
                content_fields[#content_fields + 1] = field(_("Text"), element.text or _("Empty"), function()
                    self:_showInput(_("Text"), element.text, _("Use {time}, {date}, {battery}, {device}, or {sleeping}"), function(value)
                        element.text = value; return true
                    end)
                end, { wide = true })
            elseif element.type == "widget" and element.widget_id then
                content_fields[#content_fields + 1] = field(_("Custom widget"), element.widget_id, function()
                    self.selected_widget_id, self.section = element.widget_id, "widgets"
                    self:rebuild(); UIManager:setDirty(self, "ui")
                end, { wide = true })
            elseif element.type == "widget" then
                content_fields[#content_fields + 1] = field(_("Widget source"), element.source or "clock", function()
                    local dialog; local choices = { "clock", "date", "battery", "device" }; local buttons = {}
                    for _, source in ipairs(choices) do
                        local selected_source = source
                        buttons[#buttons + 1] = { { text = selected_source, callback = function()
                            element.source = selected_source; UIManager:close(dialog); self:_changed()
                        end } }
                    end
                    buttons[#buttons + 1] = { { text = _("Cancel"), callback = function() UIManager:close(dialog) end } }
                    dialog = ButtonDialog:new{ title = _("Widget source"), buttons = buttons }; UIManager:show(dialog)
                end, { wide = true })
            elseif element.type == "image" then
                content_fields[#content_fields + 1] = field(_("Images & fit"),
                    string.format(_("%d image(s) · %s"), #(element.images or {}), element.fit or "contain"),
                    function() self:showImageMenu() end, { wide = true })
            end
            if #content_fields > 0 then
                addGroup(_("Content"), _("Edit what this layer displays."), content_fields)
            end

            if element.type ~= "image" then
                addGroup(_("Appearance"), _("Tune typography and contrast for this layer."), {
                    field(_("Font"), element.font or "cfont", function() self:showFontMenu() end),
                    field(_("Font size"), tostring(element.font_size or 20), function()
                        self:_showInput(_("Font size"), element.font_size or 20, _("8–96"), function(value)
                            local n = tonumber(value)
                            if not n or n < 8 or n > 96 then return false, _("Use a size from 8 to 96.") end
                            element.font_size = math.floor(n); return true
                        end)
                    end),
                    field(_("Text color"), element.color or "#000000", function()
                        self:_showInput(_("Text color"), element.color or "#000000", _("#RRGGBB"), function(value)
                            if not value:match("^#[0-9A-Fa-f]+$") or #value ~= 7 then return false, _("Use #RRGGBB.") end
                            element.color = value:upper(); return true
                        end)
                    end),
                    field(_("Element background"), element.background or "#FFFFFF", function()
                        self:_showInput(_("Element background"), element.background or "#FFFFFF", _("#RRGGBB"), function(value)
                            if not value:match("^#[0-9A-Fa-f]+$") or #value ~= 7 then return false, _("Use #RRGGBB.") end
                            element.background = value:upper(); return true
                        end)
                    end),
                    field(_("Background opacity"), string.format("%d%%", math.floor((element.background_alpha == nil and 1 or element.background_alpha) * 100 + 0.5)), function()
                        self:_showInput(_("Background opacity"), math.floor((element.background_alpha == nil and 1 or element.background_alpha) * 100 + 0.5), _("0–100%"), function(value)
                            local n = tonumber(value)
                            if not n or n < 0 or n > 100 then return false, _("Use a value from 0 to 100%.") end
                            element.background_alpha = n / 100
                            return true
                        end)
                    end),
                    field(_("Alignment"), element.align or "left", function()
                        local dialog; local buttons = {}
                        for _, align in ipairs({ "left", "center", "right" }) do
                            local selected_align = align
                            buttons[#buttons + 1] = { { text = selected_align, callback = function()
                                element.align = selected_align; UIManager:close(dialog); self:_changed()
                            end } }
                        end
                        dialog = ButtonDialog:new{ title = _("Text alignment"), buttons = buttons }; UIManager:show(dialog)
                    end),
                    field(_("Bold"), element.bold and _("On") or _("Off"), function()
                        element.bold = not element.bold; self:_changed()
                    end),
                })
            end
        end
    else
        addGroup(_("Save your work"), self.dirty and _("You have unsaved changes.") or _("Changes stay local until you save."), {
            field(_("Save draft"), _("Keep editing later"), function() self:save() end),
            field(_("Save & activate"), _("Use this while sleeping"), function() self:saveAndActivate() end),
        })
        addGroup(_("Share or leave"), _("Publishing is optional and requires confirmation."), {
            field(_("Publish"), _("Share this preset publicly"), function() self:publish() end, { wide = true }),
            field(_("Close editor"), self.dirty and _("Review unsaved changes") or _("Return to catalog"), function() self:closeEditor() end, { wide = true }),
        })
    end
    return items
end

function SleepEditor:rebuild()
    local colors, width, height = palette(self.appdock), self.dimen.w, self.dimen.h
    local margin, gap = scale(8), scale(7)
    local horizontal = width >= height
    local preview_w, preview_h, controls_x, controls_y, controls_w, controls_h
    if horizontal then
        preview_w = math.max(scale(140), math.floor(width * .56) - margin * 2)
        preview_h = height - margin * 2
        controls_x, controls_y = preview_w + margin * 2, margin
        controls_w, controls_h = width - controls_x - margin, height - margin * 2
    else
        preview_w = width - margin * 2
        preview_h = math.max(scale(150), math.floor(height * .38))
        controls_x, controls_y = margin, preview_h + margin * 2
        controls_w, controls_h = preview_w, height - controls_y - margin
    end
    -- Fit the reader's aspect ratio in the reserved preview area. Stretching
    -- the layout would make the instant preview differ from the sleep screen.
    local box_w, box_h = preview_w, preview_h
    local factor = math.min(box_w / width, box_h / height)
    preview_w, preview_h = math.max(1, math.floor(width * factor)), math.max(1, math.floor(height * factor))
    local preview_x = margin + math.floor((box_w - preview_w) / 2)
    local preview_y = margin + math.floor((box_h - preview_h) / 2)
    local preview = self:_preview(preview_w, preview_h, colors)
    local control_width = controls_w - ScrollableContainer:getScrollbarWidth()
    local rows = self:_sectionRows(control_width, colors)
    local list = require("ui/widget/verticalgroup"):new(rows)
    local header_height, tab_height = scale(32), scale(32)
    local panel_gap = scale(5)
    local tabs_y = controls_y + header_height
    local body_y = tabs_y + tab_height + panel_gap
    local body_height = math.max(scale(60), controls_h - header_height - tab_height - panel_gap * 2)
    local status = self.dirty and _("Unsaved changes") or (self.record and _("Saved draft") or _("New draft"))
    local tabs = self:_sectionTabs(controls_w, colors)
    tabs.overlap_offset = { controls_x, tabs_y }
    local scroller = ScrollableContainer:new{
        dimen = Geom:new{ w = controls_w, h = body_height }, show_parent = self,
        list, overlap_offset = { controls_x, body_y },
    }
    self:clear()
    self[1] = OverlapGroup:new{ dimen = self.dimen, allow_mirroring = false,
        FrameContainer:new{ width = width, height = height, padding = 0, bordersize = 0, background = colors.background, blank(width, height) },
        FrameContainer:new{ width = preview_w, height = preview_h, padding = 0, bordersize = scale(1), color = colors.on_variant,
            background = colors.surface, preview, overlap_offset = { preview_x, preview_y } },
        TextWidget:new{ text = _("Live preview"), face = Font:getFace("smallinfofont", scale(10)), fgcolor = colors.on_surface,
            bold = true, padding = 0, overlap_offset = { preview_x + scale(8), preview_y + scale(7) } },
        TextWidget:new{ text = _("Sleep-screen editor"), face = Font:getFace("cfont", scale(13)), fgcolor = colors.on_surface,
            bold = true, max_width = controls_w, padding = 0, overlap_offset = { controls_x, controls_y } },
        TextWidget:new{ text = status .. _(" · Preview updates live"), face = Font:getFace("smallinfofont", scale(8)), fgcolor = colors.on_variant,
            max_width = controls_w, padding = 0, overlap_offset = { controls_x, controls_y + scale(17) } },
        tabs,
        scroller,
    }
end
function SleepEditor:onCloseWidget()
    -- Explicitly detach temporary widget references so renderer image widgets can
    -- release their Blitbuffers through the normal KOReader close path.
    self._preview_widget = nil
    self:clear()
    UIManager:setDirty("all", "ui")
end

function Editor.show(appdock, context, record)
    local widget = SleepEditor:new{ appdock = appdock, context = context, record = record and copy(record) or nil }
    UIManager:show(widget, "full")
    return widget
end
Editor._test = { SleepEditor = SleepEditor, EditorButton = EditorButton, copy = copy }
return Editor
