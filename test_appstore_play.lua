-- AppDock Store integration test.
-- It runs the real appdock_theme, appdock_layout and appdock_appstore sources
-- against a small KOReader stand-in that actually paints the widget tree, so
-- layout and painter regressions fail here instead of on the device.
local plugin_dir = os.getenv("APPDOCK_PLUGIN_DIR") or "./appdock.koplugin/"

local function baseClass(prototype)
    prototype = prototype or {}
    prototype.__index = prototype
    function prototype:extend(child)
        child = child or {}
        child.__index = child
        setmetatable(child, { __index = self })
        return child
    end
    function prototype:new(args)
        local instance = setmetatable(args or {}, self)
        if instance.init then instance:init() end
        return instance
    end
    return prototype
end

local paints, rects, texts = 0, 0, {}
local closed = {}

local Widget = baseClass({})
function Widget:getSize()
    if self.dimen then return self.dimen end
    return { w = self.width or 0, h = self.height or 0 }
end
function Widget:paintTo() paints = paints + 1 end

local WidgetContainer = Widget:extend({})
function WidgetContainer:paintTo(bb, x, y)
    paints = paints + 1
    for _, child in ipairs(self) do
        local offset = child.overlap_offset or { 0, 0 }
        child:paintTo(bb, x + (offset[1] or 0), y + (offset[2] or 0))
    end
end

local InputContainer = WidgetContainer:extend({})
local CenterContainer = WidgetContainer:extend({})
function CenterContainer:paintTo(bb, x, y)
    paints = paints + 1
    for _, child in ipairs(self) do
        local size = child:getSize()
        local box = self.dimen or { w = size.w, h = size.h }
        child:paintTo(bb, x + math.floor((box.w - size.w) / 2), y + math.floor((box.h - size.h) / 2))
    end
end

local TextWidget = Widget:extend({})
function TextWidget:init()
    self.text = self.text or ""
    texts[#texts + 1] = self.text
end
function TextWidget:setText(value) self.text = value end
function TextWidget:getSize()
    local size = self.face and self.face.size or 10
    return { w = math.floor(#self.text * size * .55), h = math.floor(size * 1.35) }
end
function TextWidget:paintTo() paints = paints + 1 end

local function widgetModule() return WidgetContainer end
local bb = { paintRect = function() rects = rects + 1 end }
local shown = {}

package.preload["ffi/blitbuffer"] = function()
    return {
        COLOR_WHITE = "white", COLOR_BLACK = "black", COLOR_DARK_GRAY = "dark",
        COLOR_LIGHT_GRAY = "light", COLOR_GRAY = "gray", COLOR_GRAY_7 = "g7", COLOR_GRAY_8 = "g8",
        ColorRGB32 = function() return "rgb" end,
    }
end
package.preload["device"] = function()
    return { screen = { scaleBySize = function(_, value) return value end, isColorEnabled = function() return true end } }
end
package.preload["datastorage"] = function() return { getDataDir = function() return "/tmp" end } end
package.preload["ui/font"] = function() return { getFace = function(_, name, size) return { name = name, size = size } end } end
package.preload["ui/geometry"] = function() return { new = function(_, values) return values end } end
package.preload["ui/gesturerange"] = function() return { new = function(_, values) return values end } end
package.preload["ui/widget/widget"] = function() return Widget end
package.preload["ui/widget/container/centercontainer"] = function() return CenterContainer end
package.preload["ui/widget/container/framecontainer"] = function() return WidgetContainer end
package.preload["ui/widget/container/inputcontainer"] = function() return InputContainer end
package.preload["ui/widget/container/scrollablecontainer"] = function()
    WidgetContainer.getScrollbarWidth = function() return 8 end
    return WidgetContainer
end
package.preload["ui/widget/container/widgetcontainer"] = function() return WidgetContainer end
package.preload["ui/widget/horizontalspan"] = function() return Widget end
package.preload["ui/widget/inputdialog"] = function() return Widget end
package.preload["ui/widget/overlapgroup"] = function() return WidgetContainer end
package.preload["ui/widget/textwidget"] = function() return TextWidget end
package.preload["ui/widget/confirmbox"] = function() return Widget end
package.preload["ui/widget/infomessage"] = function() return Widget end
package.preload["ui/uimanager"] = function()
    return {
        show = function(_, widget) shown[#shown + 1] = widget end,
        close = function(first, second) closed[#closed + 1] = second or first end,
        nextTick = function() end,
        setDirty = function() end,
    }
end
package.preload["appdock_keyboard"] = function() return { attach = function() return true end } end
package.preload["gettext"] = function() return function(value) return value end end

local Theme = dofile(plugin_dir .. "appdock_theme.lua")
local Layout = dofile(plugin_dir .. "appdock_layout.lua")
-- The raster logo widget is exercised by its own test; the store only needs a
-- deterministic placeholder that paints.
local DAppLogo = Widget:extend({ kind = "generic", size = 16, ink = nil })
function DAppLogo:init() self.dimen = { w = self.size, h = self.size } end
function DAppLogo:paintTo() paints = paints + 1 end
function DAppLogo.availableKinds() return { "app_store", "palette", "reading", "analog_clock" } end
package.loaded["appdock_theme"] = Theme
package.loaded["appdock_layout"] = Layout
package.loaded["appdock_logo"] = DAppLogo
local AppStore = dofile(plugin_dir .. "appdock_appstore.lua")

-- Catalog manifest parsing stays unchanged -----------------------------------
local entries = AppStore.parseManifest("apps/reader.lua|2.0|reading|dapp\ndesigns/calm.appdock-design|1.1|palette|design\nwidgets/clock.lua|0.9|analog_clock|widget\n# comment\nbroken.exe|1|help|dapp\n")
assert(#entries == 3, "AppStore must keep parsing the plain-text catalog manifest")
local by_kind = {}
for _, entry in ipairs(entries) do by_kind[entry.kind] = entry end
assert(by_kind.dapp and by_kind.dapp.title == "Reader" and by_kind.widget and by_kind.design, "AppStore must expose typed catalog entries")
assert(#AppStore.filterEntries(entries, "clock", "widget") == 1 and #AppStore.filterEntries(entries, "", "design") == 1, "AppStore category and text filters must keep working")

-- Rendering ------------------------------------------------------------------
local installed = {
    ["apps/reader.lua"] = { id = "reader", version = "2.0" },
}
local appdock = {
    settings = { layout = {} },
    uninstallStoreDApp = function(self, id) self.uninstalled_id = id; return true end,
    getStoreDesignBySource = function() return nil, nil end,
    getStoreDAppBySource = function(_, path)
        local record = installed[path]
        if not record then return nil, nil end
        local definition = { id = record.id, title = "Reader", version = record.version, logo = "reading" }
        return definition, record
    end,
    getStoreWidgetBySource = function() return nil, nil end,
}
local rebuilds = 0
local context = {
    appdock = appdock,
    manager = appdock,
    instance = {},
    host = {},
    dimen = { w = 600, h = 700 },
    requestRebuild = function() rebuilds = rebuilds + 1 end,
}

local store = AppStore:new()
local state = store:_ensureState(context.instance)
state.refreshed, state.entries, state.error, state.query, state.category = true, entries, nil, "", "all"
local pane = store:buildPane(context.instance, context)
assert(pane and pane.dimen and pane.dimen.w == 600 and pane.dimen.h == 700, "AppStore must return a pane that fills its assigned rectangle")

local function has_text(needle)
    for _, value in ipairs(texts) do
        if value == needle or value:find(needle, 1, true) then return true end
    end
    return false
end
paints, rects = 0, 0
pane:paintTo(bb, 0, 0)
assert(paints >= 40, "The AppStore pane must paint its full widget tree")
assert(rects >= 60, "The AppDock Store mark, navigation icons and surfaces must paint real pixels")

for _, label in ipairs({ "AppDock Store", "All items", "For you", "Apps", "Widgets", "Designs", "Install" }) do
    assert(has_text(label), "The AppDock Store layout must render the label: " .. label)
end
assert(not has_text("Google Play"), "The AppDock Store must not use Google Play branding")
assert(has_text("Recommended for you"), "Without pending updates the shelf heading must be Recommended for you")
assert(has_text("Search for apps & games"), "The Play search pill must be visible on the store home")
assert(has_text("Open") and has_text("Uninstall"), "Installed catalog entries must expose Play-style Open and Uninstall actions")
assert(has_text("Installed") and has_text("Open"), "An installed catalog entry must offer the Play Open action")
assert(has_text("Reader") and has_text("DApp · v2.0"), "Catalog rows must show the entry title and its real metadata")

-- Empty, error and search states --------------------------------------------
local function text_of_state(changes)
    local store_state = store:_ensureState(context.instance)
    -- Lua table literals cannot carry explicit nils, so the transient error is
    -- always cleared before the requested overrides are applied.
    store_state.error = nil
    for key, value in pairs(changes) do store_state[key] = value end
    texts = {}
    local empty_pane = store:buildPane(context.instance, context)
    empty_pane:paintTo(bb, 0, 0)
    return texts
end

local function contains(list, needle)
    for _, value in ipairs(list) do
        if value == needle then return true end
    end
    return false
end

local unloaded = text_of_state({ refreshed = false, entries = nil, error = nil, query = "", category = "all" })
assert(contains(unloaded, "Load the Play catalog") and contains(unloaded, "Load catalog"), "An unloaded catalog must offer the Play-style load action")
local failed = text_of_state({ refreshed = true, entries = nil, error = "Repository unavailable." })
assert(contains(failed, "Catalog unavailable") and contains(failed, "Try again"), "A failed refresh must be reported inside the Play surface")
local filtered = text_of_state({ refreshed = true, entries = entries, error = nil, query = "nothing-matches", category = "all" })
assert(contains(filtered, "No matching apps") and contains(filtered, "Clear search"), "An empty search result must stay inside the Play surface")
local scoped = text_of_state({ refreshed = true, entries = entries, error = nil, query = "", category = "design" })
assert(contains(scoped, "Designs · 1") or contains(scoped, "Designs  ·  1"), "The category tab must scope the visible catalog list")
assert(contains(scoped, "Recommended for you"), "Without pending updates the shelf must fall back to Recommended for you")
installed["apps/reader.lua"] = { id = "reader", version = "0.5" }
local outdated = text_of_state({ refreshed = true, entries = entries, error = nil, query = "", category = "all" })
assert(contains(outdated, "Updates available") and contains(outdated, "Update") and contains(outdated, "Update available"), "A newer catalog version must offer the Play update action")
installed["apps/reader.lua"] = { id = "reader", version = "2.0" }

-- Interaction ----------------------------------------------------------------
local state = store:_ensureState(context.instance)
state.refreshed, state.entries, state.error, state.query, state.category = true, entries, nil, "", "all"

local function walk(widget, visit, found)
    found = found or {}
    if type(widget) == "table" then
        visit(widget, found)
        for _, child in ipairs(widget) do walk(child, visit, found) end
        if type(widget.entries) == "table" then
            for _, entry in ipairs(widget.entries) do
                if type(entry) == "table" and entry.widget then walk(entry.widget, visit, found) end
            end
        end
    end
    return found
end

-- KOReader maps the gesture event "TapPlayPill" onto onTapPlayPill.
local function find_control(widget, event)
    return walk(widget, function(node, found)
        if node.ges_events and node.ges_events[event] and type(node["on" .. event]) == "function" then
            found[#found + 1] = node
        end
    end)
end

local function find_by_label(widget, label)
    return walk(widget, function(node, found)
        if node.title == label or node.label == label then found[#found + 1] = node end
    end)
end

pane = store:buildPane(context.instance, context)
local install_pills = find_by_label(pane, "Install")
assert(#install_pills > 0 and #find_control(pane, "TapPlayPill") > 0, "Catalog rows must expose tappable Play controls")
local before = #shown
install_pills[1]:onTapPlayPill()
assert(#shown == before + 1, "Tapping Install must open the explicit confirmation step")
store:confirmUninstall(context.instance, context, entries[1], { id = "reader" })
local uninstall_dialog = shown[#shown]
assert(uninstall_dialog and uninstall_dialog.ok_callback, "Installed DApps must expose an uninstall confirmation")
uninstall_dialog.ok_callback()
assert(appdock.uninstalled_id == "reader" and closed[#closed] == uninstall_dialog, "DApp uninstall must close the confirmation dialog before removing the DApp")

pane = store:buildPane(context.instance, context)
local widget_tabs = find_by_label(pane, "Widgets")
assert(#widget_tabs > 0, "The Play bottom navigation must render its Widgets tab")
widget_tabs[1]:onTapPlayNavTab()
assert(state.category == "widget" and rebuilds > 0, "Tapping a Play navigation tab must switch the catalog category")

assert(state.category == "widget", "The Widgets tab must stay selected until another tab is chosen")
state.category = "all"
pane = store:buildPane(context.instance, context)
assert(#find_control(pane, "TapPlayCard") > 0, "The recommendation shelf must expose tappable cards")
assert(#find_control(pane, "TapPlayRow") >= #entries, "Every visible catalog entry must render a Play list row")
assert(#find_control(pane, "TapPlayNavTab") == 4, "The Play bottom navigation must render all four category tabs")
local scrollers = walk(pane, function(node, found)
    if node.show_parent == context.host and node.dimen then found[#found + 1] = node end
end)
local first_row = find_control(pane, "TapPlayRow")[1]
assert(#scrollers > 0 and first_row and scrollers[1].dimen.w == first_row.width + 8, "The AppStore scroller must reserve its scrollbar outside the row/action width")
local search_pills = find_by_label(pane, "Search for apps & games")
assert(#search_pills > 0, "The Play search pill must open the catalog search dialog")
local glyphs = walk(pane, function(node, found)
    if node.size and (node.kind == "search" or node.kind == "refresh") then found[#found + 1] = node end
end)
assert(#glyphs >= 3, "The Play app bar must draw its own magnifier and refresh icons instead of relying on font glyphs")

print("AppStore Play test: OK")
