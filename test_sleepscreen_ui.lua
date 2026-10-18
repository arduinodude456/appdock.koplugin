-- Focused UI contract test: real AppStore/Catalog/Editor callbacks against
-- compact KOReader stand-ins.  It intentionally mocks the core API boundary.
local plugin_dir = os.getenv("APPDOCK_PLUGIN_DIR") or "./appdock.koplugin/"
package.path = plugin_dir .. "?.lua;" .. package.path

local function class(parent)
    local c = {}; c.__index = c; setmetatable(c, { __index = parent })
    function c:extend(fields) fields = fields or {}; fields.__index = fields; setmetatable(fields, { __index = self }); return fields end
    function c:new(args) local object = setmetatable(args or {}, self); if object.init then object:init() end; return object end
    return c
end
local Widget = class()
function Widget:getSize() return self.dimen or { w = self.width or 0, h = self.height or 0 } end
function Widget:paintTo() end
function Widget:clear() for index = #self, 1, -1 do self[index] = nil end end
local Container = Widget:extend({})
function Container:paintTo(bb, x, y)
    for _, child in ipairs(self) do
        if child.paintTo then local offset = child.overlap_offset or { 0, 0 }; child:paintTo(bb, (x or 0) + (offset[1] or 0), (y or 0) + (offset[2] or 0)) end
    end
end
local InputContainer, WidgetContainer = Container:extend({}), Container:extend({})
local TextWidget = Widget:extend({})
function TextWidget:init() self.text = self.text or "" end
function TextWidget:getSize() local size = self.face and self.face.size or 10; return { w = math.max(1, #self.text * math.floor(size * .55)), h = size + 3 } end
local shown, closed, dirty = {}, {}, 0
local UIManager = {
    show = function(_, widget) shown[#shown + 1] = widget end,
    close = function(_, widget) closed[#closed + 1] = widget; if widget and widget.onCloseWidget then widget:onCloseWidget() end end,
    setDirty = function() dirty = dirty + 1 end, forceRePaint = function() end, nextTick = function(_, fn) if fn then fn() end end,
}
local InputDialog = InputContainer:extend({})
function InputDialog:getInputText() return self.input or "" end
function InputDialog:onShowKeyboard() self.keyboard_opened = true; return true end
local Dialog = InputContainer:extend({})

package.preload["ffi/blitbuffer"] = function() return { COLOR_WHITE = "white", COLOR_BLACK = "black", COLOR_DARK_GRAY = "dark", COLOR_LIGHT_GRAY = "light", COLOR_GRAY = "gray", COLOR_GRAY_8 = "g8", ColorRGB32 = function() return "rgb" end } end
package.preload["device"] = function() return { screen = { getWidth = function() return 800 end, getHeight = function() return 600 end, scaleBySize = function(_, n) return n end, isColorEnabled = function() return true end } } end
package.preload["datastorage"] = function() return { getDataDir = function() return "/tmp" end } end
package.preload["ui/font"] = function() return { getFace = function(_, name, size) return { name = name, size = size or 10 } end } end
package.preload["ui/geometry"] = function() return { new = function(_, values) return values end } end
package.preload["ui/gesturerange"] = function() return { new = function(_, values) return values end } end
package.preload["ui/widget/widget"] = function() return Widget end
package.preload["ui/widget/container/inputcontainer"] = function() return InputContainer end
package.preload["ui/widget/container/widgetcontainer"] = function() return WidgetContainer end
package.preload["ui/widget/container/framecontainer"] = function() return Container end
package.preload["ui/widget/container/centercontainer"] = function() return Container end
package.preload["ui/widget/container/scrollablecontainer"] = function() Container.getScrollbarWidth = function() return 8 end; return Container end
package.preload["ui/widget/horizontalspan"] = function() return Widget end
package.preload["ui/widget/verticalspan"] = function() return Widget end
package.preload["ui/widget/verticalgroup"] = function() return Container end
package.preload["ui/widget/overlapgroup"] = function() return Container end
package.preload["ui/widget/textwidget"] = function() return TextWidget end
package.preload["ui/widget/inputdialog"] = function() return InputDialog end
package.preload["ui/uimanager"] = function() return UIManager end
package.preload["gettext"] = function() return function(text) return text end end
package.preload["appdock_dialogs"] = function() return { ButtonDialog = Dialog, ConfirmBox = Dialog, InputDialog = InputDialog, InfoMessage = Dialog } end
package.preload["appdock_keyboard"] = function() return { attach = function() return true end } end
package.preload["appdock_wallpaper"] = function() return { isUsableImage = function() return true end } end
package.preload["appdock_layout"] = function() return { FixedStack = Container } end
package.preload["appdock_theme"] = function()
    return { fitLabel = function(text) return text end, centeredStack = function(_, entries, gap) local ys, y = {}, gap or 0; for i, entry in ipairs(entries) do ys[i] = y; y = y + (entry:getSize().h or 0) + (gap or 0) end; return ys end,
        getPalette = function() return { background = "bg", surface = "surface", surface_variant = "variant", primary = "primary", on_primary = "onprimary", on_surface = "ink", on_variant = "muted", tertiary = "danger", on_tertiary = "white" } end }
end
local Logo = Widget:extend({})
function Logo:init() self.dimen = { w = self.size or 16, h = self.size or 16 } end
function Logo.availableKinds() return { "app_store", "palette", "reading", "analog_clock" } end
package.preload["appdock_logo"] = function() return Logo end

local saved, activated, installed, published, listed = {}, nil, 0, nil, 0
local activation_fails = false
local function definition(name)
    return { schema_version = 1, name = name or "New", description = "", background = "#FFFFFF", elements = {}, assets = {} }
end
package.preload["appdock_sleepscreen_presets"] = function()
    return {
        newDraft = function(name) return { definition = definition(name), asset_paths = {} } end,
        listLocal = function() return saved end,
        saveDraft = function(_, draft, id)
            local record = { id = id or ("local-" .. tostring(#saved + 1)), definition = draft.definition, asset_paths = draft.asset_paths or {}, remote_id = draft.remote_id, revision = draft.revision, creator = draft.creator }
            local replaced = false; for index, old in ipairs(saved) do if old.id == record.id then saved[index], replaced = record, true end end
            if not replaced then saved[#saved + 1] = record end
            return record
        end,
        activate = function(_, id)
            activated = id
            if activation_fails then return nil, "simulated activation error" end
            return true
        end,
        remove = function(_, id) for index, record in ipairs(saved) do if record.id == id then table.remove(saved, index); return true end end; return nil, "missing" end,
        importAsset = function(draft, path, kind)
            local id = kind .. "_" .. tostring(#(draft.definition.assets or {}) + 1); draft.definition.assets[#draft.definition.assets + 1] = { id = id, kind = kind, extension = kind == "font" and "ttf" or "png" }; draft.asset_paths[id] = path; return id
        end,
        exportPackage = function(record) return { definition = record.definition, assets = {} } end,
        validatePackage = function(package) return package.definition, {} end,
        installPackage = function(_, package, entry) installed = installed + 1; return { id = "installed", definition = package.definition, asset_paths = package.asset_paths or {}, remote_id = entry.id, revision = entry.revision, creator = entry.creator } end,
    }
end
package.preload["appdock_sleepscreen_renderer"] = function()
    return { build = function(def, width, height, options) return WidgetContainer:new{ dimen = { w = width, h = height }, rendered_definition = def, rendered_options = options } end }
end
package.preload["appdock_sleepscreen_store"] = function()
    return {
        list = function(_, query, offset) listed = listed + 1; assert(offset == 0); return { entries = { { id = "remote-1", name = "Ocean", description = "Calm", creator = { account_id = "other", display_name = "Mira" }, revision = 3, definition = definition("Ocean") } }, has_more = true } end,
        get = function(_, id) assert(id == "remote-1"); return { entry = { id = id, name = "Ocean", creator = { account_id = "other", display_name = "Mira" }, revision = 3, definition = definition("Ocean") }, package = { definition = definition("Ocean"), assets = {}, asset_paths = {} } } end,
        publish = function(_, package, id, revision) published = { package = package, id = id, revision = revision }; return { id = id or "published-1", revision = 4, creator = { account_id = "me", display_name = "Me" } } end,
        unpublish = function() return true end,
    }
end
package.preload["appdock_tbs_account"] = function()
    return { require = function(_, _, done) done(true); return true end, status = function() return { account_id = "me", signed_in = true } end }
end

local function walk(widget, visit, found)
    found = found or {}
    if type(widget) == "table" then
        visit(widget, found)
        for _, child in ipairs(widget) do walk(child, visit, found) end
        if type(widget.entries) == "table" then for _, entry in ipairs(widget.entries) do if entry.widget then walk(entry.widget, visit, found) end end end
    end
    return found
end
local function named(widget, title)
    return walk(widget, function(node, found) if node.title == title or node.label == title then found[#found + 1] = node end end)
end
local function hasText(widget, fragment)
    return #walk(widget, function(node, found)
        if type(node.text) == "string" and node.text:find(fragment, 1, true) then found[#found + 1] = node end
    end) > 0
end

local AppStore = dofile(plugin_dir .. "appdock_appstore.lua")
local instance, rebuilds = {}, 0
local context = { appdock = { settings = {} }, manager = { appdock = {}, getStoreDAppBySource = function() return nil end, getStoreWidgetBySource = function() return nil end }, host = {}, dimen = { w = 800, h = 600 }, requestRebuild = function() rebuilds = rebuilds + 1 end }
local store = AppStore:new()
local state = store:_ensureState(instance)
local store_pane = store:buildPane(instance, context)
local tabs = named(store_pane, "Sleepscreens")
assert(#tabs > 0 and #walk(store_pane, function(node, found) if node.ges_events and node.ges_events.TapPlayNavTab then found[#found + 1] = node end end) == 5, "AppStore must expose five bottom navigation tabs including Sleepscreens")
local original_package_path = package.path
-- KOReader or another plugin may replace package.path while handling an event.
-- AppDock's dynamic screens must still resolve their own sibling modules.
package.path = "./plugins/vocabbuilder.koplugin/lib/?.lua;./plugins/wallabag.koplugin/lib/?.lua;"
tabs[1]:onTapPlayNavTab()
assert(state.category == "sleepscreen", "Sleepscreens tab must select the separate catalog category")

local catalog_pane = store:buildPane(instance, context)
local Catalog = package.loaded.appdock_sleepscreen_catalog
assert(Catalog, "AppStore must load its catalog from the AppDock plugin directory")
assert(#named(catalog_pane, "New sleepscreen") > 0, "Local catalog must offer draft creation without an account")
named(catalog_pane, "Apps")[1]:onTapPlayNavTab()
assert(state.category == "dapp", "Leaving Sleepscreens must switch the parent Store category, not just a nested field")
state.category = "sleepscreen"
catalog_pane = store:buildPane(instance, context)
named(catalog_pane, "New sleepscreen")[1]:onTapPlayPill()
local editor = shown[#shown]
assert(editor and editor.draft and editor.draft.definition and editor[1], "New-draft callback must open the native live-preview editor")
package.path = original_package_path
local screen_tab, elements_tab, save_tab = named(editor, "Screen")[1], named(editor, "Elements")[1], named(editor, "Save")[1]
assert(screen_tab and screen_tab.selected and elements_tab and save_tab, "Editor must group controls into clear Screen, Elements, Edit, and Save sections")
elements_tab.callback()
assert(editor.section == "elements" and #named(editor, "Text") > 0 and #named(editor, "Image") > 0,
    "Elements section must offer visual building blocks instead of mixing them with screen settings")
save_tab = named(editor, "Save")[1]
save_tab.callback()
assert(editor.section == "save" and #named(editor, "Save draft") > 0 and #named(editor, "Publish") > 0,
    "Save section must keep local save, activation, and public sharing together")
local landscape_dimen = editor.dimen
editor.dimen = { w = 400, h = 800 }
editor:rebuild()
assert(editor[1].dimen.w == 400 and editor[1].dimen.h == 800 and #named(editor, "Save draft") > 0,
    "Editor sections and save actions must remain available in portrait layout")
editor.dimen = landscape_dimen
editor:rebuild()
editor:_addElement("text")
assert(#editor.draft.definition.elements == 1 and dirty > 0 and editor.section == "edit",
    "Adding an element must open its grouped editor and refresh the instant preview")
assert(#named(editor, "Position x / y") > 0 and #named(editor, "Text") > 0 and #named(editor, "Font") > 0,
    "Selected elements must expose grouped layout, content, and appearance controls")
editor:_showInput("Text", "New text", "", function(value) editor.draft.definition.elements[1].text = value; return true end)
local field = shown[#shown]; field.input = "Instant value"; field.buttons[1][2].callback()
assert(editor.draft.definition.elements[1].text == "Instant value", "Applying an editor field must immediately update the underlying draft")
-- Creating a custom widget from the element picker must connect it immediately
-- and expose its controls in the live-preview Custom widgets section.
editor:_addElement("widget")
editor:_createCustomWidget()
local created_widget = editor.draft.definition.widgets[1]
assert(created_widget and editor.draft.definition.elements[2].widget_id == created_widget.id,
    "new custom widgets must be connected to the selected screen layer without a picker dialog")
assert(editor.section == "widgets" and #named(editor, "Text template") > 0 and #named(editor, "Weather API") > 0,
    "custom widget controls must be presented together in the live-preview editor")
local dirty_before_activation = dirty
activation_fails = true
editor:saveAndActivate()
activation_fails = false
assert(not editor.dirty and dirty > dirty_before_activation and hasText(editor, "Saved draft")
    and not hasText(editor, "Unsaved changes") and shown[#shown].text:find("Saved, but could not activate", 1, true),
    "A failed activation must still refresh the editor to the successfully saved state")
editor:publish()
local consent = shown[#shown]
assert(consent.text:find("Name:", 1, true) and consent.text:find("Creator:", 1, true) and consent.text:find("Assets shared:", 1, true) and consent.text:find("No books", 1, true), "Publish must show exact name, creator, asset count, and privacy notice before sharing")
consent.ok_callback()
assert(published and published.package and published.package.definition.name, "Publish must save/export then call the Store API after explicit TBS account approval")
assert(editor.record.remote_id == "published-1" and editor.record.revision == 4, "Publishing must retain the returned identity/revision for later updates")
local local_editor_pane = store:buildPane(instance, context)
named(local_editor_pane, "Edit")[1]:onTapPlayPill()
assert(shown[#shown].record.id == editor.record.id, "An owned/local draft edit must reuse its local identity")

local catalog_state = instance.app_store.sleepscreen_catalog
catalog_state.view, catalog_state.entries, catalog_state.opened = "browse", nil, nil
Catalog.refresh(instance, context, catalog_state)
assert(listed == 1 and catalog_state.entries[1].creator.display_name == "Mira", "Public browsing must call Store.list without an account and retain creator data")
local public_results_pane = store:buildPane(instance, context)
assert(#named(public_results_pane, "Open") == 1, "Rendering public results must preserve the gettext function and show an Open action")
Catalog.openRemote(instance, context, catalog_state, catalog_state.entries[1])
assert(catalog_state.opened and installed == 0, "Opening a remote preset may load its full preview but must not install it")
Catalog.confirmDownload(context, catalog_state, true, false)
local download_consent = shown[#shown]
assert(download_consent.text:find("Download", 1, true) and download_consent.text:find("Creator: Mira", 1, true), "Download must require an explicit creator-labelled confirmation")
download_consent.ok_callback()
assert(installed == 1 and activated == "installed", "Confirmed download-and-use must install then activate locally")

Catalog.openRemote(instance, context, catalog_state, catalog_state.entries[1])
Catalog.confirmDownload(context, catalog_state, false, true)
shown[#shown].ok_callback()
local fork_editor = shown[#shown]
assert(fork_editor.record and fork_editor.record.id == nil and fork_editor.record.remote_id == nil,
    "Editing another creator's download must start a new local fork, never retain its remote identity")
editor:_addElement("card")
editor:closeEditor()
local discard = shown[#shown]
assert(discard.text:find("Discard unsaved", 1, true) and discard.ok_callback,
    "Closing a changed editor must request explicit discard confirmation")

print("Sleepscreen UI test: OK")
