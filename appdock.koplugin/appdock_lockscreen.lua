--[[
AppDock's local access screen. It protects the AppDock homescreen only; it is
not a replacement for a device-level lockscreen or encrypted device storage.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextWidget = require("ui/widget/textwidget")
local VerticalSpan = require("ui/widget/verticalspan")
local UIManager = require("ui/uimanager")
local Device = require("device")
local sha2 = require("ffi/sha2")
local Wallpaper = require("appdock_wallpaper")
local AppDockKeyboard = require("appdock_keyboard")
local _ = require("gettext")

local Screen = Device.screen
local MODULE_DIR = (debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "")
local HERO_PATH = MODULE_DIR .. "assets/lockscreen/appdock_lockscreen_hero.png"

local LockScreen = InputContainer:extend{
    appdock = nil,
    on_unlock = nil,
    dimen = nil,
    covers_fullscreen = true,
    pattern = "",
    status = nil,
}

local function scale(value) return Screen:scaleBySize(value) end
local function digest(value) return sha2.md5("appdock-lock-v1:" .. tostring(value or "")) end

function LockScreen.hash(value)
    return digest(value)
end

function LockScreen:freeImages()
    for _, image in ipairs({ self._hero, self._avatar }) do
        pcall(function() image:free() end)
    end
    self._hero, self._avatar = nil, nil
end

function LockScreen:build()
    self:freeImages()
    local width, height = self.dimen.w, self.dimen.h
    local method = self.appdock.settings.lockscreen.method or "swipe"
    local profile = self.appdock.settings.lockscreen or {}
    local margin = scale(22)
    local now = os.date("%H:%M")
    local date = os.date("%A, %d. %B")
    local profile_name = type(profile.profile_name) == "string" and profile.profile_name ~= "" and profile.profile_name or _("Welcome back")
    local hero = Wallpaper.buildPath(HERO_PATH, width, height, true)
    self._hero = hero

    -- Android-inspired hierarchy: wallpaper, compact status/date row, centered
    -- identity, then the unlock affordance at the bottom. Keep the controls
    -- high-contrast and mostly geometric for E-Ink screens.
    local avatar_size = scale(72)
    local avatar_y = math.floor(height * 0.30)
    local name_y = avatar_y + avatar_size + scale(16)
    local method_y = math.floor(height * 0.64)
    local bottom_y = height - scale(72)
    local layers = {
        hero or FrameContainer:new{ width = width, height = height, padding = 0, bordersize = 0, background = Blitbuffer.COLOR_WHITE },
        FrameContainer:new{ width = width - 2 * margin, height = scale(76), padding = 0, bordersize = scale(1), color = Blitbuffer.COLOR_BLACK, radius = scale(22), background = Blitbuffer.COLOR_WHITE, overlap_offset = { margin, scale(18) },
            TextWidget:new{ text = "APPDOCK", face = Font:getFace("smallinfofont", scale(9)), fgcolor = Blitbuffer.COLOR_DARK_GRAY, bold = true, overlap_offset = { scale(16), scale(10) } },
            TextWidget:new{ text = now, face = Font:getFace("cfont", scale(32)), fgcolor = Blitbuffer.COLOR_BLACK, bold = true, overlap_offset = { scale(15), scale(25) } },
            TextWidget:new{ text = date, face = Font:getFace("smallinfofont", scale(10)), fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = width - scale(56), alignment = "right", overlap_offset = { scale(16), scale(47) } },
        },
        FrameContainer:new{ width = avatar_size, height = avatar_size, padding = 0, bordersize = scale(2), color = Blitbuffer.COLOR_BLACK, radius = math.floor(avatar_size / 2), background = Blitbuffer.COLOR_WHITE, overlap_offset = { math.floor((width - avatar_size) / 2), avatar_y },
            CenterContainer:new{ dimen = Geom:new{ w = avatar_size, h = avatar_size }, TextWidget:new{ text = "A", face = Font:getFace("cfont", scale(28)), fgcolor = Blitbuffer.COLOR_BLACK, bold = true } } },
        TextWidget:new{ text = profile_name, face = Font:getFace("cfont", scale(22)), fgcolor = Blitbuffer.COLOR_BLACK, bold = true, max_width = width - 2 * margin, alignment = "center", overlap_offset = { margin, name_y } },
        TextWidget:new{ text = self.status or _("AppDock is locked"), face = Font:getFace("smallinfofont", scale(11)), fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = width - 2 * margin, alignment = "center", overlap_offset = { margin, name_y + scale(31) } },
    }

    local avatar = Wallpaper.buildPath(profile.profile_image_path, avatar_size, avatar_size, true)
    self._avatar = avatar
    if avatar then
        avatar.overlap_offset = { math.floor((width - avatar_size) / 2), avatar_y }
        layers[3] = avatar
    end

    if method == "pattern" then
        local cell, gap = scale(48), scale(14)
        local grid_w = cell * 3 + gap * 2
        local start_x = math.floor((width - grid_w) / 2)
        local start_y = method_y
        layers[#layers + 1] = TextWidget:new{ text = _("Draw your pattern"), face = Font:getFace("smallinfofont", scale(12)), fgcolor = Blitbuffer.COLOR_BLACK, bold = true, max_width = width - 2 * margin, alignment = "center", overlap_offset = { margin, start_y - scale(34) } }
        for index = 1, 9 do
            local column, row = (index - 1) % 3, math.floor((index - 1) / 3)
            local chosen = self.pattern:find(tostring(index), 1, true) ~= nil
            layers[#layers + 1] = FrameContainer:new{
                width = cell, height = cell, padding = scale(15), bordersize = scale(2), color = Blitbuffer.COLOR_BLACK,
                radius = math.floor(cell / 2), background = chosen and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
                overlap_offset = { start_x + column * (cell + gap), start_y + row * (cell + gap) },
            }
        end
    elseif method == "pin" then
        layers[#layers + 1] = FrameContainer:new{ width = scale(220), height = scale(42), padding = 0, bordersize = scale(1), color = Blitbuffer.COLOR_BLACK, radius = scale(21), background = Blitbuffer.COLOR_WHITE,
            CenterContainer:new{ dimen = Geom:new{ w = scale(220), h = scale(42) }, TextWidget:new{ text = _("Tap to enter PIN"), face = Font:getFace("smallinfofont", scale(12)), fgcolor = Blitbuffer.COLOR_BLACK, bold = true } }, overlap_offset = { math.floor((width - scale(220)) / 2), method_y + scale(12) } }
    else
        layers[#layers + 1] = FrameContainer:new{ width = math.min(scale(250), width - 2 * scale(40)), height = scale(46), padding = 0, bordersize = scale(1), color = Blitbuffer.COLOR_BLACK, radius = scale(23), background = Blitbuffer.COLOR_WHITE,
            CenterContainer:new{ dimen = Geom:new{ w = math.min(scale(250), width - 2 * scale(40)), h = scale(46) }, TextWidget:new{ text = _("Swipe up to unlock"), face = Font:getFace("smallinfofont", scale(12)), fgcolor = Blitbuffer.COLOR_BLACK, bold = true } }, overlap_offset = { math.floor((width - math.min(scale(250), width - 2 * scale(40))) / 2), method_y + scale(16) } }
    end

    layers[#layers + 1] = TextWidget:new{ text = _("This device is protected by AppDock"), face = Font:getFace("smallinfofont", scale(9)), fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = width - 2 * margin, alignment = "center", overlap_offset = { margin, bottom_y } }
    self:clear()
    self[1] = OverlapGroup:new{ dimen = self.dimen, allow_mirroring = false, unpack(layers) }
end

function LockScreen:onCloseWidget() self:freeImages() end

function LockScreen:init()
    self.dimen = Screen:getSize()
    self:build()
    self.ges_events = { UnlockGesture = { GestureRange:new{ ges = "swipe", range = self.dimen } }, UnlockTap = { GestureRange:new{ ges = "tap", range = self.dimen } } }
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
    if self.appdock.settings.lockscreen.method == "swipe" and gesture and gesture.direction then self:_unlock(); return true end
    return false
end

function LockScreen:onUnlockTap(event, gesture)
    local settings = self.appdock.settings.lockscreen
    if settings.method == "swipe" then return true end
    if settings.method == "pin" then
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
    if settings.method == "pattern" and gesture and gesture.pos then
        local cell = scale(48)
        local gap = scale(14)
        local start_x = math.floor((self.dimen.w - (cell * 3 + gap * 2)) / 2)
        local start_y = math.floor(self.dimen.h * 0.64)
        local column = math.floor((gesture.pos.x - start_x) / (cell + gap))
        local row = math.floor((gesture.pos.y - start_y) / (cell + gap))
        if column >= 0 and column < 3 and row >= 0 and row < 3 then
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

return LockScreen
