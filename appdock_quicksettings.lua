--[[--
AppDock's custom-drawn quick settings dropdown.
This overlay uses native KOReader primitives and role-based theme colors.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local Layout = require("appdock_layout")
local Motion = require("appdock_motion")
local Theme = require("appdock_theme")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Screen = Device.screen
local QuickSettings = InputContainer:extend{ appdock = nil, home = nil, dimen = nil, covers_fullscreen = false, sheet_height = nil }
local QuickTile = InputContainer:extend{ appdock = nil, title = nil, symbol = nil, subtitle = nil, active = false, callback = nil, width = nil, height = nil, compact = false, expressive = false, show_switch = false }
local BrightnessSlider = InputContainer:extend{ sheet = nil, width = nil, height = nil, brightness = nil }
local NotificationRow = InputContainer:extend{ notification = nil, callback = nil, width = nil, height = nil }

local function scale(value) return Screen:scaleBySize(value) end
local function color(r, g, b, grayscale)
    return Screen:isColorEnabled() and Blitbuffer.ColorRGB32(r, g, b, 0xFF) or grayscale
end
local PALETTE = {
    sheet = color(250, 248, 255, Blitbuffer.COLOR_WHITE), surface = color(242, 240, 247, Blitbuffer.COLOR_LIGHT_GRAY),
    surface_variant = color(228, 225, 235, Blitbuffer.COLOR_GRAY_8), primary = color(214, 227, 255, Blitbuffer.COLOR_GRAY_8),
    on_primary = color(23, 59, 111, Blitbuffer.COLOR_DARK_GRAY), secondary = color(225, 221, 242, Blitbuffer.COLOR_GRAY_7),
    on_surface = color(31, 29, 36, Blitbuffer.COLOR_BLACK), on_variant = color(76, 73, 84, Blitbuffer.COLOR_DARK_GRAY),
    track = color(198, 196, 205, Blitbuffer.COLOR_GRAY), outline = color(121, 117, 128, Blitbuffer.COLOR_GRAY),
}
local function applyTheme(appdock)
    local palette = Theme.getPalette(appdock)
    PALETTE.sheet, PALETTE.surface, PALETTE.surface_variant = palette.dropdown or palette.background, palette.surface, palette.surface_variant
    PALETTE.primary, PALETTE.on_primary = palette.button or palette.primary, palette.on_button or palette.on_primary
    PALETTE.secondary, PALETTE.on_surface, PALETTE.on_variant, PALETTE.track, PALETTE.outline = palette.secondary, palette.on_surface, palette.on_variant, palette.track, palette.outline
end
local function emptySizedWidget(width, height)
    return CenterContainer:new{ dimen = Geom:new{ w = width, h = height }, HorizontalSpan:new{ width = 0 } }
end
local function getWifiState()
    local ok, manager = pcall(require, "ui/network/manager")
    if not ok or not manager or type(manager.isWifiOn) ~= "function" then return false, false end
    local state_ok, enabled = pcall(manager.isWifiOn, manager)
    return state_ok and not not enabled, true
end
local function getBrightness()
    local ok, data = pcall(function()
        local powerd = Device:getPowerDevice()
        if not powerd or type(powerd.frontlightIntensity) ~= "function" or type(powerd.fl_min) ~= "number" or type(powerd.fl_max) ~= "number" then return nil end
        return { powerd = powerd, min = powerd.fl_min, max = powerd.fl_max, current = powerd:frontlightIntensity() }
    end)
    return ok and data and type(data.current) == "number" and data or nil
end

function QuickTile:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local background, foreground = self.active and PALETTE.primary or PALETTE.surface_variant, self.active and PALETTE.on_primary or PALETTE.on_surface
    local symbol_size = math.max(scale(12), math.min(self.compact and scale(17) or (self.expressive and scale(22) or scale(20)), math.floor(self.height * .34)))
    local title_size = math.max(scale(8), math.min(self.compact and scale(11) or (self.expressive and scale(13) or scale(12)), math.floor(self.height * .20)))
    local subtitle_size = math.max(scale(7), math.min(self.compact and scale(9) or scale(10), math.floor(self.height * .16)))
    if self.expressive then title_size, subtitle_size = Theme.adjustText(self.appdock, title_size, scale(8)), Theme.adjustText(self.appdock, subtitle_size, scale(7)) end
    local text_width = math.max(scale(12), self.width - scale(14))
    local title, subtitle = Theme.fitLabel(self.title or "", text_width, title_size, 0), Theme.fitLabel(self.subtitle or "", text_width, subtitle_size, 0)
    local symbol = TextWidget:new{ text = self.symbol, face = Font:getFace("cfont", symbol_size), fgcolor = foreground, bold = true, padding = 0 }
    local title_widget = TextWidget:new{ text = title, face = Font:getFace("smallinfofont", title_size), fgcolor = foreground, bold = true, max_width = text_width, padding = 0 }
    local subtitle_widget = TextWidget:new{ text = subtitle, face = Font:getFace("smallinfofont", subtitle_size), fgcolor = foreground, max_width = text_width, padding = 0 }
    local positions = Theme.centeredStack(self.height, { symbol, title_widget, subtitle_widget }, math.max(scale(1), math.floor(self.height * .025)), scale(3))
    local switch_entry
    if self.show_switch then
        local switch_width, switch_height = scale(42), scale(22)
        local knob_size = math.max(scale(14), switch_height - scale(6))
        local knob = FrameContainer:new{ width = knob_size, height = knob_size, padding = 0, bordersize = scale(1), color = self.active and PALETTE.primary or PALETTE.on_variant, radius = math.floor(knob_size / 2), background = self.active and PALETTE.on_primary or PALETTE.surface, emptySizedWidget(knob_size, knob_size), overlap_offset = { self.active and switch_width - knob_size - scale(3) or scale(3), math.floor((switch_height - knob_size) / 2) } }
        self._switch_knob, self._switch_width, self._switch_knob_size = knob, switch_width, knob_size
        switch_entry = { widget = OverlapGroup:new{ dimen = Geom:new{ w = switch_width, h = switch_height }, FrameContainer:new{ width = switch_width, height = switch_height, padding = 0, bordersize = scale(1), color = foreground, radius = math.floor(switch_height / 2), background = self.active and PALETTE.primary or PALETTE.track, emptySizedWidget(switch_width, switch_height) }, knob }, x = self.width - switch_width - scale(10), y = scale(8) }
    end
    local entries = { { widget = CenterContainer:new{ dimen = Geom:new{ w = self.width, h = symbol:getSize().h }, symbol }, x = 0, y = positions[1] }, { widget = CenterContainer:new{ dimen = Geom:new{ w = self.width, h = title_widget:getSize().h }, title_widget }, x = 0, y = positions[2] }, { widget = CenterContainer:new{ dimen = Geom:new{ w = self.width, h = subtitle_widget:getSize().h }, subtitle_widget }, x = 0, y = positions[3] } }
    if switch_entry then entries[#entries + 1] = switch_entry end
    self[1] = FrameContainer:new{ width = self.width, height = self.height, padding = 0, bordersize = 0, radius = math.floor(self.height * (self.expressive and .40 or .32)), background = background, Layout.FixedStack:new{ width = self.width, height = self.height, entries = entries } }
    self.ges_events = { TapQuickTile = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end
function QuickTile:paintTo(bb, x, y) self.ges_events.TapQuickTile[1].range.x, self.ges_events.TapQuickTile[1].range.y, self.ges_events.TapQuickTile[1].range.w, self.ges_events.TapQuickTile[1].range.h = x, y, self.dimen.w, self.dimen.h; return InputContainer.paintTo(self, bb, x, y) end
function QuickTile:onTapQuickTile()
    if self.callback and self.show_switch then
        local start, finish = self.active and 1 or 0, self.active and 0 or 1
        Motion.run(self, 3, .045, function(frame) if self._switch_knob then self._switch_knob.overlap_offset[1] = math.floor(scale(3) + ((frame - 1) / 2) * (finish - start) * (self._switch_width - self._switch_knob_size - scale(6))) end end, self.callback)
    elseif self.callback then UIManager:setDirty(self, "fast"); self.callback() end
    return true
end

function NotificationRow:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local notification = self.notification or {}
    local background, foreground = notification.read and PALETTE.surface or PALETTE.primary, notification.read and PALETTE.on_surface or PALETTE.on_primary
    local title_size, message_size = math.max(scale(8), math.min(scale(11), math.floor(self.height * .28))), math.max(scale(7), math.min(scale(9), math.floor(self.height * .20)))
    local title = TextWidget:new{ text = Theme.fitLabel(notification.title or _("AppDock"), self.width - scale(30), title_size, 0), face = Font:getFace("smallinfofont", title_size), fgcolor = foreground, bold = true, padding = 0 }
    local message = TextWidget:new{ text = Theme.fitLabel(notification.message or "", self.width - scale(30), message_size, 0), face = Font:getFace("smallinfofont", message_size), fgcolor = notification.read and PALETTE.on_variant or PALETTE.on_primary, padding = 0 }
    local positions = Theme.centeredStack(self.height, { title, message }, scale(3), scale(3))
    self[1] = FrameContainer:new{ width = self.width, height = self.height, padding = 0, bordersize = 0, radius = scale(11), background = background, Layout.FixedStack:new{ width = self.width, height = self.height, entries = { { widget = title, x = scale(12), y = positions[1] }, { widget = message, x = scale(12), y = positions[2] }, { widget = TextWidget:new{ text = notification.read and "" or "•", face = Font:getFace("cfont", scale(18)), fgcolor = foreground, padding = 0 }, x = self.width - scale(18), y = scale(8) } } } }
    self.ges_events = { TapNotification = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end
function NotificationRow:paintTo(bb, x, y) self.ges_events.TapNotification[1].range.x, self.ges_events.TapNotification[1].range.y, self.ges_events.TapNotification[1].range.w, self.ges_events.TapNotification[1].range.h = x, y, self.dimen.w, self.dimen.h; return InputContainer.paintTo(self, bb, x, y) end
function NotificationRow:onTapNotification() if self.callback then self.callback() end; return true end

function BrightnessSlider:init() self.dimen = Geom:new{ w = self.width, h = self.height }; self:build(); self.ges_events = { TapBrightness = { GestureRange:new{ ges = "tap", range = self.dimen } }, PanBrightness = { GestureRange:new{ ges = "pan", range = self.dimen } }, PanReleaseBrightness = { GestureRange:new{ ges = "pan_release", range = self.dimen } } } end
function BrightnessSlider:build()
    local state, enabled = self.brightness, self.brightness ~= nil and self.brightness.max > self.brightness.min
    local percentage = enabled and math.max(0, math.min(1, (state.current - state.min) / (state.max - state.min))) or 0
    local track_y, track_height, fill_width = self.height - scale(16), scale(12), math.max(scale(3), math.floor(self.width * percentage))
    self[1] = OverlapGroup:new{ dimen = Geom:new{ w = self.width, h = self.height }, allow_mirroring = false, TextWidget:new{ text = _("Brightness"), face = Font:getFace("smallinfofont", scale(15)), fgcolor = PALETTE.on_surface, bold = true, overlap_offset = { 0, 0 } }, TextWidget:new{ text = enabled and string.format("%d%%", math.floor(percentage * 100 + .5)) or _("Unavailable"), face = Font:getFace("smallinfofont", scale(14)), fgcolor = PALETTE.on_variant, overlap_offset = { self.width - scale(48), scale(1) } }, FrameContainer:new{ width = self.width, height = track_height, padding = 0, bordersize = 0, radius = math.floor(track_height / 2), background = PALETTE.track, overlap_offset = { 0, track_y }, emptySizedWidget(self.width, track_height) }, FrameContainer:new{ width = fill_width, height = track_height, padding = 0, bordersize = 0, radius = math.floor(track_height / 2), background = enabled and PALETTE.primary or PALETTE.surface_variant, overlap_offset = { 0, track_y }, emptySizedWidget(fill_width, track_height) } }
end
function BrightnessSlider:setBrightness(state) self.brightness = state; self:build() end
function BrightnessSlider:paintTo(bb, x, y) for _, name in ipairs({ "TapBrightness", "PanBrightness", "PanReleaseBrightness" }) do local range = self.ges_events[name][1].range; range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h end; return InputContainer.paintTo(self, bb, x, y) end
function BrightnessSlider:_setFromGesture(_, ges_ev) if not self.brightness or not ges_ev or not ges_ev.pos then return true end; local ratio = math.max(0, math.min(1, (ges_ev.pos.x - (self.dimen.x or 0)) / self.dimen.w)); self.sheet:setBrightness(math.floor(self.brightness.min + ratio * (self.brightness.max - self.brightness.min) + .5)); return true end
BrightnessSlider.onTapBrightness, BrightnessSlider.onPanBrightness, BrightnessSlider.onPanReleaseBrightness = BrightnessSlider._setFromGesture, BrightnessSlider._setFromGesture, BrightnessSlider._setFromGesture

function QuickSettings:show(args) UIManager:show(QuickSettings:new(args)) end
function QuickSettings:init() applyTheme(self.appdock); self.dimen = Screen:getSize(); if Device:hasKeys() then self.key_events.Close = { { Device.input.group.Back } } end; self:rebuild(false); self.ges_events = { TapOutsideQuickSettings = { GestureRange:new{ ges = "tap", range = self.dimen } } } end
function QuickSettings:_refresh(refreshtype, region, force) UIManager:setDirty("all", refreshtype or "ui", region); if force and UIManager.forceRePaint then UIManager:forceRePaint() end end
function QuickSettings:_brightnessState() return getBrightness() end
function QuickSettings:setBrightness(intensity)
    local state = self:_brightnessState(); if not state then return end
    intensity = math.max(state.min, math.min(state.max, intensity)); if intensity == state.current then return end
    local ok = pcall(function() if intensity == state.min then state.powerd:toggleFrontlight() else state.powerd:setIntensity(intensity) end; if state.powerd.updateResumeFrontlightState then state.powerd:updateResumeFrontlightState() end end)
    if ok then self.slider:setBrightness(self:_brightnessState()); self:_refresh("fast", self.slider.dimen, true) end
end
function QuickSettings:toggleWifi() local ok, manager = pcall(require, "ui/network/manager"); if not ok or not manager or type(manager.isWifiOn) ~= "function" then UIManager:show(InfoMessage:new{ text = _("Wi-Fi controls are unavailable on this device.") }); return end; local callback = function() self:rebuild(true) end; if manager:isWifiOn() then manager:toggleWifiOff(callback, true) else manager:toggleWifiOn(callback, false, true) end end
function QuickSettings:toggleNightMode() UIManager:broadcastEvent(Event:new("ToggleNightMode")); self:rebuild(true) end
function QuickSettings:openManager() UIManager:close(self); UIManager:nextTick(function() self.appdock:showManager(self.home) end) end
function QuickSettings:fullRefresh() self:rebuild(false); self:_refresh("full", nil, true) end
function QuickSettings:enterSleep() if type(Device.canSuspend) == "function" and Device:canSuspend() then UIManager:broadcastEvent(Event:new("RequestSuspend")) else UIManager:show(InfoMessage:new{ text = _("Sleep mode is unavailable on this device.") }) end end
function QuickSettings:togglePowerSaving() local enable = not self.appdock.settings.power_saving; if enable then local wifi_on, wifi_available = getWifiState(); if wifi_available and wifi_on then local ok, manager = pcall(require, "ui/network/manager"); if ok and manager then manager:toggleWifiOff(function() end, true) end end; local brightness = self:_brightnessState(); if brightness and brightness.current > brightness.min then pcall(brightness.powerd.toggleFrontlight, brightness.powerd) end end; self.appdock:setPowerSaving(enable); self:rebuild(true) end
function QuickSettings:toggleWallpaper() local wallpaper = self.appdock.settings.wallpaper or {}; if not wallpaper.path or wallpaper.path == "" then UIManager:show(InfoMessage:new{ text = _("Choose a local background image in Settings → Display first.") }); return end; local enabled = self.appdock:setWallpaper(nil, not wallpaper.enabled); if not enabled and not wallpaper.enabled then UIManager:show(InfoMessage:new{ text = _("The saved background image is unavailable or unsupported.") }) end; self:rebuild(true) end
function QuickSettings:markAllNotificationsRead() self.appdock:markAllNotificationsRead(); self:rebuild(true) end
function QuickSettings:clearNotifications() self.appdock:clearNotifications(); self:rebuild(true) end

function QuickSettings:rebuild(refresh)
    local width, height = self.dimen.w, self.dimen.h
    local simple_mode = type(self.appdock.isSimpleModeEnabled) == "function" and self.appdock:isSimpleModeEnabled("quick_settings")
    local expressive = not simple_mode and type(self.appdock.isExpressiveUiEnabled) == "function" and self.appdock:isExpressiveUiEnabled()
    local margin, gap, header_height, tile_height, slider_height, spacing, bottom = scale(expressive and 18 or 16), scale(7), scale(expressive and 50 or 46), scale(expressive and 68 or 64), scale(expressive and 52 or 48), scale(8), scale(12)
    local title = TextWidget:new{ text = _("Quick settings"), face = Font:getFace("cfont", Theme.adjustText(self.appdock, scale(22), scale(16))), fgcolor = PALETTE.on_surface, bold = true, padding = 0 }
    header_height = math.max(header_height, title:getSize().h + scale(18))
    local ids = type(self.appdock.getQuickSettingsTiles) == "function" and self.appdock:getQuickSettingsTiles() or { "wifi", "night", "refresh", "edit" }
    local rows, tile_area = math.ceil(#ids / 2), math.ceil(#ids / 2) * tile_height + math.max(0, math.ceil(#ids / 2) - 1) * gap
    local notifications = simple_mode and {} or self.appdock:getNotifications(2)
    local notification_height = simple_mode and 0 or scale(22) + #notifications * (scale(38) + gap) + (#notifications > 0 and scale(32) + gap or 0)
    local natural_height = header_height + gap + tile_area + spacing + slider_height + spacing + notification_height + bottom
    if natural_height > math.floor(height * .82) then margin, tile_height, slider_height, bottom, notifications = scale(14), scale(56), scale(44), scale(10), simple_mode and {} or self.appdock:getNotifications(1); tile_area = rows * tile_height + math.max(0, rows - 1) * gap; notification_height = simple_mode and 0 or scale(20) + #notifications * (scale(34) + gap) + (#notifications > 0 and scale(28) + gap or 0); natural_height = header_height + gap + tile_area + spacing + slider_height + spacing + notification_height + bottom end
    local tile_width = math.floor((width - 2 * margin - gap) / 2); self.sheet_height = math.min(natural_height, height)
    local wifi_on, wifi_available = getWifiState(); local night = G_reader_settings:isTrue("night_mode"); local settings = self.appdock.settings or {}; local wallpaper = settings.wallpaper or {}
    local content = OverlapGroup:new{ dimen = Geom:new{ w = width, h = height }, allow_mirroring = false }
    self.sheet_frame = FrameContainer:new{ width = width, height = self.sheet_height, padding = 0, bordersize = 0, radius = expressive and scale(34) or scale(28), background = PALETTE.sheet, emptySizedWidget(width, self.sheet_height) }; table.insert(content, self.sheet_frame)
    title.overlap_offset = { margin, math.max(scale(3), math.floor((header_height - title:getSize().h) / 2)) }; table.insert(content, title)
    local close = TextWidget:new{ text = "×", face = Font:getFace("cfont", scale(24)), fgcolor = PALETTE.on_variant }; close.overlap_offset = { width - margin - close:getSize().w, scale(4) }; table.insert(content, close)
    local definitions = { wifi = { title = _("Wi-Fi"), symbol = "W", subtitle = wifi_available and (wifi_on and _("On") or _("Off")) or _("Unavailable"), active = wifi_on, show_switch = true, callback = function() self:toggleWifi() end }, night = { title = _("Night"), symbol = "N", subtitle = night and _("On") or _("Off"), active = night, show_switch = true, callback = function() self:toggleNightMode() end }, refresh = { title = _("Refresh"), symbol = "R", subtitle = _("Redraw"), callback = function() self:fullRefresh() end }, edit = { title = _("Edit"), symbol = "E", subtitle = _("Apps"), callback = function() self:openManager() end }, sleep = { title = _("Sleep"), symbol = "Z", subtitle = _("Screen off"), callback = function() self:enterSleep() end }, power_saving = { title = _("Save power"), symbol = "P", subtitle = settings.power_saving and _("On") or _("Off"), active = settings.power_saving == true, show_switch = true, callback = function() self:togglePowerSaving() end }, wallpaper = { title = _("Background"), symbol = "B", subtitle = wallpaper.enabled and _("On") or _("Off"), active = wallpaper.enabled == true, callback = function() self:toggleWallpaper() end } }
    local tiles = {}; for _, id in ipairs(ids) do if definitions[id] then tiles[#tiles + 1] = definitions[id] end end
    local tile_y = header_height + gap; for index, tile in ipairs(tiles) do local col, row = (index - 1) % 2, math.floor((index - 1) / 2); table.insert(content, QuickTile:new{ appdock = self.appdock, title = tile.title, symbol = tile.symbol, subtitle = tile.subtitle, active = tile.active, callback = tile.callback, width = tile_width, height = tile_height, compact = natural_height > math.floor(height * .82), expressive = expressive, show_switch = tile.show_switch, overlap_offset = { margin + col * (tile_width + gap), tile_y + row * (tile_height + gap) } }) end
    self.slider = BrightnessSlider:new{ sheet = self, width = width - 2 * margin, height = slider_height, brightness = getBrightness(), overlap_offset = { margin, tile_y + tile_area + spacing } }; table.insert(content, self.slider)
    local notifications_y = self.slider.overlap_offset[2] + slider_height + spacing
    if not simple_mode then table.insert(content, TextWidget:new{ text = self.appdock:getUnreadNotificationCount() > 0 and string.format(_("Notifications · %d unread"), self.appdock:getUnreadNotificationCount()) or _("Notifications · all caught up"), face = Font:getFace("smallinfofont", scale(13)), fgcolor = PALETTE.on_surface, bold = true, overlap_offset = { margin, notifications_y } }); for index, notification in ipairs(notifications) do table.insert(content, NotificationRow:new{ notification = notification, width = width - 2 * margin, height = scale(36), callback = function() self.appdock:markNotificationRead(notification.id); self:rebuild(true) end, overlap_offset = { margin, notifications_y + scale(22) + (index - 1) * (scale(36) + gap) } }) end end
    self.layout = { simple_mode = simple_mode, expressive = expressive, tile_count = #tiles, sheet_height = self.sheet_height }; self:clear(); self[1] = content; if refresh then self:_refresh("ui", nil, true) end
end
function QuickSettings:paintTo(bb, x, y) local range = self.ges_events.TapOutsideQuickSettings[1].range; range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h; return InputContainer.paintTo(self, bb, x, y) end
function QuickSettings:onTapOutsideQuickSettings(_, ges_ev) if self.sheet_frame and self.sheet_frame.dimen and ges_ev and ges_ev.pos and not ges_ev.pos:intersectWith(self.sheet_frame.dimen) then self:onClose() end; return true end
function QuickSettings:onShow() self:_refresh("ui", nil, true); return true end
function QuickSettings:onCloseWidget() self:_refresh("ui", nil, true) end
function QuickSettings:onClose() UIManager:close(self); self:_refresh("ui", nil, true); return true end
return QuickSettings
