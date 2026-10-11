--[[--
AppDock's local access screen. It protects the AppDock homescreen only; it is
not a replacement for a device-level lockscreen or encrypted device storage.
--]]--

local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local Device = require("device")
local sha2 = require("ffi/sha2")
local Wallpaper = require("appdock_wallpaper")
local Theme = require("appdock_theme")
local AppDockKeyboard = require("appdock_keyboard")
local _ = require("gettext")

local Screen = Device.screen

local LockScreen = InputContainer:extend{
    appdock = nil,
    on_unlock = nil,
    dimen = nil,
    covers_fullscreen = true,
    pattern = "",
    status = nil,
}

local function scale(value) return Screen:scaleBySize(value) end
local function emptySizedWidget(width, height)
    return CenterContainer:new{
        dimen = Geom:new{ w = width, h = height },
        HorizontalSpan:new{ width = 0 },
    }
end
local function digest(value) return sha2.md5("appdock-lock-v1:" .. tostring(value or "")) end

function LockScreen.hash(value)
    return digest(value)
end

local function settingsFor(appdock)
    local settings = appdock and type(appdock.settings) == "table" and appdock.settings or {}
    return type(settings.lockscreen) == "table" and settings.lockscreen or {}
end

local function lockMethod(profile)
    if type(profile) == "table" and (profile.method == "pin" or profile.method == "pattern") then
        return profile.method
    end
    return "swipe"
end

local function patternBounds(dimen, minimum_y, footer_y)
    local margin = scale(22)
    local gap = math.max(scale(8), math.floor(dimen.w * .025))
    local cell = math.max(scale(30), math.min(scale(52), math.floor((dimen.w - 2 * margin - 2 * gap) / 3)))
    local grid_w, grid_h = cell * 3 + gap * 2, cell * 3 + gap * 2
    local max_y = math.max(minimum_y, footer_y - grid_h - scale(18))
    return {
        cell = cell,
        gap = gap,
        width = grid_w,
        height = grid_h,
        x = math.max(margin, math.floor((dimen.w - grid_w) / 2)),
        y = max_y,
    }
end

function LockScreen:freeImages()
    if self._avatar and type(self._avatar.free) == "function" then pcall(function() self._avatar:free() end) end
    self._avatar = nil
end

function LockScreen:build()
    self:freeImages()
    local width, height = self.dimen.w, self.dimen.h
    local profile = settingsFor(self.appdock)
    local method = lockMethod(profile)
    local palette = Theme.getPalette(self.appdock)
    local margin = math.max(scale(16), math.floor(width * .045))
    local footer_y = math.max(scale(16), height - scale(34))
    local now = os.date("%H:%M")
    local date = os.date("%A, %d. %B")
    local profile_name = type(profile.profile_name) == "string" and profile.profile_name:match("^%s*(.-)%s*$") or ""
    if profile_name == "" then profile_name = _("Welcome back") end

    -- A deliberate flat hierarchy avoids a colour-photo hero that dithers badly
    -- on E-Ink. All surfaces use the active AppDock theme and retain a readable
    -- foreground through Theme.getPalette's contrast roles.
    local card_w = math.max(1, width - margin * 2)
    local card_h = math.min(math.max(scale(128), math.floor(height * .20)), scale(172))
    local card_y = math.max(scale(118), math.floor(height * .245))
    local avatar_size = math.min(scale(68), math.max(scale(44), math.floor(card_h * .52)))
    local avatar_x = margin + scale(18)
    local avatar_y = card_y + math.floor((card_h - avatar_size) / 2)
    local text_x = avatar_x + avatar_size + scale(16)
    local text_w = math.max(scale(80), margin + card_w - text_x - scale(18))
    local method_y = card_y + card_h + scale(30)

    local layers = {
        FrameContainer:new{
            width = width, height = height, padding = 0, bordersize = 0,
            background = palette.background,
            emptySizedWidget(width, height),
        },
        FrameContainer:new{
            width = width, height = math.max(scale(5), math.floor(height * .008)), padding = 0, bordersize = 0,
            background = palette.primary, overlap_offset = { 0, 0 },
            emptySizedWidget(width, math.max(scale(5), math.floor(height * .008))),
        },
        TextWidget:new{
            text = _("APPDOCK"), face = Font:getFace("smallinfofont", scale(10)), fgcolor = palette.on_primary,
            bold = true, max_width = math.floor(width * .42), padding = 0, overlap_offset = { margin, scale(18) },
        },
        TextWidget:new{
            text = _("LOCKED"), face = Font:getFace("smallinfofont", scale(9)), fgcolor = palette.on_variant,
            bold = true, max_width = math.floor(width * .28), alignment = "right", padding = 0,
            overlap_offset = { width - margin - math.floor(width * .28), scale(19) },
        },
        TextWidget:new{
            text = now, face = Font:getFace("cfont", math.max(scale(30), math.floor(height * .055))), fgcolor = palette.on_surface,
            bold = true, max_width = width - 2 * margin, alignment = "center", padding = 0,
            overlap_offset = { margin, scale(40) },
        },
        TextWidget:new{
            text = date, face = Font:getFace("smallinfofont", scale(11)), fgcolor = palette.on_variant,
            max_width = width - 2 * margin, alignment = "center", padding = 0,
            overlap_offset = { margin, scale(91) },
        },
        FrameContainer:new{
            width = card_w, height = card_h, padding = 0, bordersize = math.max(1, scale(1)), color = palette.outline,
            radius = scale(14), background = palette.surface, overlap_offset = { margin, card_y },
            emptySizedWidget(card_w, card_h),
        },
        FrameContainer:new{
            width = avatar_size, height = avatar_size, padding = 0, bordersize = math.max(1, scale(2)), color = palette.outline,
            radius = math.floor(avatar_size / 2), background = palette.primary, overlap_offset = { avatar_x, avatar_y },
            CenterContainer:new{
                dimen = Geom:new{ w = avatar_size, h = avatar_size },
                TextWidget:new{ text = profile_name:sub(1, 1):upper(), face = Font:getFace("cfont", math.floor(avatar_size * .42)), fgcolor = palette.on_primary, bold = true, padding = 0 },
            },
        },
        TextWidget:new{
            text = profile_name, face = Font:getFace("cfont", scale(20)), fgcolor = palette.on_surface,
            bold = true, max_width = text_w, padding = 0, overlap_offset = { text_x, avatar_y + scale(6) },
        },
        TextWidget:new{
            text = self.status or _("AppDock is locked"), face = Font:getFace("smallinfofont", scale(11)), fgcolor = palette.on_variant,
            max_width = text_w, padding = 0, overlap_offset = { text_x, avatar_y + math.floor(avatar_size * .60) },
        },
    }

    local avatar = Wallpaper.buildPath(profile.profile_image_path, avatar_size, avatar_size, true)
    self._avatar = avatar
    if avatar then
        avatar.overlap_offset = { avatar_x, avatar_y }
        layers[#layers + 1] = avatar
    end

    if method == "pattern" then
        local bounds = patternBounds(self.dimen, method_y + scale(28), footer_y)
        self._pattern_bounds = bounds
        layers[#layers + 1] = TextWidget:new{
            text = _("Draw your pattern"), face = Font:getFace("smallinfofont", scale(12)), fgcolor = palette.on_surface,
            bold = true, max_width = width - 2 * margin, alignment = "center", padding = 0,
            overlap_offset = { margin, bounds.y - scale(32) },
        }
        for index = 1, 9 do
            local column, row = (index - 1) % 3, math.floor((index - 1) / 3)
            local chosen = self.pattern:find(tostring(index), 1, true) ~= nil
            local x = bounds.x + column * (bounds.cell + bounds.gap)
            local y = bounds.y + row * (bounds.cell + bounds.gap)
            layers[#layers + 1] = FrameContainer:new{
                width = bounds.cell, height = bounds.cell, padding = 0, bordersize = math.max(1, scale(2)), color = palette.outline,
                radius = math.floor(bounds.cell / 2), background = chosen and palette.primary or palette.surface,
                overlap_offset = { x, y },
                CenterContainer:new{
                    dimen = Geom:new{ w = bounds.cell, h = bounds.cell },
                    TextWidget:new{ text = tostring(index), face = Font:getFace("smallinfofont", scale(11)), fgcolor = chosen and palette.on_primary or palette.on_surface, bold = true, padding = 0 },
                },
            }
        end
    else
        self._pattern_bounds = nil
        local action_w = math.min(math.max(scale(210), math.floor(width * .58)), width - 2 * margin)
        local action_h = scale(48)
        local action_y = math.min(method_y, footer_y - action_h - scale(34))
        local label = method == "pin" and _("Tap to enter PIN") or _("Swipe up to unlock")
        layers[#layers + 1] = TextWidget:new{
            text = method == "pin" and _("Enter your AppDock PIN") or _("Swipe anywhere upwards"),
            face = Font:getFace("smallinfofont", scale(11)), fgcolor = palette.on_variant,
            max_width = width - 2 * margin, alignment = "center", padding = 0,
            overlap_offset = { margin, action_y - scale(26) },
        }
        layers[#layers + 1] = FrameContainer:new{
            width = action_w, height = action_h, padding = 0, bordersize = math.max(1, scale(1)), color = palette.outline,
            radius = math.floor(action_h / 2), background = method == "pin" and palette.surface or palette.primary,
            overlap_offset = { math.floor((width - action_w) / 2), action_y },
            CenterContainer:new{
                dimen = Geom:new{ w = action_w, h = action_h },
                TextWidget:new{ text = label, face = Font:getFace("smallinfofont", scale(12)), fgcolor = method == "pin" and palette.on_surface or palette.on_primary, bold = true, padding = 0 },
            },
        }
    end

    layers[#layers + 1] = TextWidget:new{
        text = _("This lock protects AppDock, not device storage"), face = Font:getFace("smallinfofont", scale(9)), fgcolor = palette.on_variant,
        max_width = width - 2 * margin, alignment = "center", padding = 0, overlap_offset = { margin, footer_y },
    }
    self:clear()
    self[1] = OverlapGroup:new{ dimen = self.dimen, allow_mirroring = false, unpack(layers) }
end

function LockScreen:onCloseWidget() self:freeImages() end

function LockScreen:init()
    self.dimen = Screen:getSize()
    self:build()
    self.ges_events = {
        UnlockGesture = { GestureRange:new{ ges = "swipe", range = self.dimen } },
        UnlockTap = { GestureRange:new{ ges = "tap", range = self.dimen } },
    }
end

function LockScreen:paintTo(bb, x, y)
    for _, name in ipairs({ "UnlockGesture", "UnlockTap" }) do
        local range = self.ges_events[name][1].range
        range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    end
    return InputContainer.paintTo(self, bb, x, y)
end

function LockScreen:_unlock()
    UIManager:close(self)
    UIManager:nextTick(function() if self.on_unlock then self.on_unlock() end end)
end

function LockScreen:_reject()
    self.status = _("That does not match. Try again.")
    self.pattern = ""
    self:build()
    UIManager:setDirty(self, "ui")
end

function LockScreen:onUnlockGesture(event, gesture)
    if lockMethod(settingsFor(self.appdock)) == "swipe" and gesture and gesture.direction then self:_unlock(); return true end
    return false
end

function LockScreen:onUnlockTap(event, gesture)
    local settings = settingsFor(self.appdock)
    local method = lockMethod(settings)
    if method == "swipe" then return true end
    if method == "pin" then
        local AppDockDialogs = require("appdock_dialogs")
        local InputDialog = AppDockDialogs.InputDialog
        local dialog
        dialog = InputDialog:new{
            title = _("AppDock PIN"), input = "", input_type = "number", input_hint = _("PIN"),
            buttons = { { { text = _("Cancel"), callback = function() UIManager:close(dialog) end }, { text = _("Unlock"), is_enter_default = true, callback = function()
                local value = dialog:getInputText() or ""
                UIManager:close(dialog)
                if settings.secret_hash and LockScreen.hash(value) == settings.secret_hash then self:_unlock() else self:_reject() end
            end } } },
        }
        AppDockKeyboard.attach(dialog, { secure = true })
        UIManager:show(dialog); dialog:onShowKeyboard()
        return true
    end
    local bounds = self._pattern_bounds
    if method == "pattern" and bounds and gesture and gesture.pos then
        local column = math.floor((gesture.pos.x - bounds.x) / (bounds.cell + bounds.gap))
        local row = math.floor((gesture.pos.y - bounds.y) / (bounds.cell + bounds.gap))
        local within_cell = column >= 0 and column < 3 and row >= 0 and row < 3
            and gesture.pos.x < bounds.x + column * (bounds.cell + bounds.gap) + bounds.cell
            and gesture.pos.y < bounds.y + row * (bounds.cell + bounds.gap) + bounds.cell
        if within_cell then
            local point = tostring(row * 3 + column + 1)
            if not self.pattern:find(point, 1, true) then self.pattern = self.pattern .. point; self:build(); UIManager:setDirty(self, "ui") end
            if #self.pattern >= 4 then
                if settings.secret_hash and LockScreen.hash(self.pattern) == settings.secret_hash then self:_unlock() else self:_reject() end
            end
        end
    end
    return true
end

function LockScreen.show(appdock, callback)
    UIManager:show(LockScreen:new{ appdock = appdock, on_unlock = callback })
end

LockScreen._test = { patternBounds = patternBounds, lockMethod = lockMethod }

return LockScreen
