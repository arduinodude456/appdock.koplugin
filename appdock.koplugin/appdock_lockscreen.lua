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
local UIManager = require("ui/uimanager")
local Device = require("device")
local sha2 = require("ffi/sha2")
local Wallpaper = require("appdock_wallpaper")
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
local function digest(value) return sha2.md5("appdock-lock-v1:" .. tostring(value or "")) end

function LockScreen.hash(value)
    return digest(value)
end

function LockScreen:build()
    local width, height = self.dimen.w, self.dimen.h
    local method = self.appdock.settings.lockscreen.method or "swipe"
    local title = method == "pin" and _("Enter AppDock PIN") or method == "pattern" and _("Draw your pattern") or _("Swipe to unlock")
    local detail = method == "swipe" and _("Swipe in any direction") or method == "pattern" and _("Connect the numbered points") or _("Use the PIN chosen in AppDock settings")
    local profile = self.appdock.settings.lockscreen or {}
    local layers = {
        FrameContainer:new{ width = width, height = height, padding = 0, bordersize = 0, background = Blitbuffer.COLOR_BLACK,
            CenterContainer:new{ dimen = self.dimen, TextWidget:new{ text = "", face = Font:getFace("cfont", scale(1)) } } },
        TextWidget:new{ text = "AppDock", face = Font:getFace("cfont", scale(30)), fgcolor = Blitbuffer.COLOR_WHITE, bold = true, overlap_offset = { math.floor((width - scale(142)) / 2), math.floor(height * 0.22) } },
        TextWidget:new{ text = title, face = Font:getFace("smallinfofont", scale(17)), fgcolor = Blitbuffer.COLOR_WHITE, bold = true, overlap_offset = { math.floor((width - scale(190)) / 2), math.floor(height * 0.35) } },
        TextWidget:new{ text = self.status or detail, face = Font:getFace("smallinfofont", scale(12)), fgcolor = Blitbuffer.COLOR_LIGHT_GRAY, max_width = width - scale(48), overlap_offset = { scale(24), math.floor(height * 0.42) } },
    }
    if type(profile.profile_name) == "string" and profile.profile_name ~= "" then
        layers[#layers + 1] = TextWidget:new{ text = profile.profile_name, face = Font:getFace("smallinfofont", scale(15)), fgcolor = Blitbuffer.COLOR_WHITE, bold = true, max_width = width - scale(64), overlap_offset = { scale(32), math.floor(height * 0.29) } }
    end
    local avatar_size = scale(52)
    local avatar = Wallpaper.buildPath(profile.profile_image_path, avatar_size, avatar_size, true)
    if avatar then
        avatar.overlap_offset = { math.floor((width - avatar_size) / 2), math.floor(height * 0.47) }
        layers[#layers + 1] = avatar
    end
    if method == "pattern" then
        local cell = scale(46)
        local gap = scale(14)
        local start_x = math.floor((width - (cell * 3 + gap * 2)) / 2)
        local start_y = math.floor(height * 0.52)
        for index = 1, 9 do
            local column, row = (index - 1) % 3, math.floor((index - 1) / 3)
            local chosen = self.pattern:find(tostring(index), 1, true) ~= nil
            local button = FrameContainer:new{
                width = cell, height = cell, padding = 0, bordersize = scale(1), color = Blitbuffer.COLOR_WHITE,
                radius = math.floor(cell / 2), background = chosen and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK,
                CenterContainer:new{ dimen = Geom:new{ w = cell, h = cell }, TextWidget:new{ text = tostring(index), face = Font:getFace("cfont", scale(17)), fgcolor = chosen and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE, bold = true } },
            }
            button.overlap_offset = { start_x + column * (cell + gap), start_y + row * (cell + gap) }
            layers[#layers + 1] = button
        end
    elseif method == "pin" then
        layers[#layers + 1] = TextWidget:new{ text = _("Tap anywhere to enter PIN"), face = Font:getFace("smallinfofont", scale(13)), fgcolor = Blitbuffer.COLOR_WHITE, overlap_offset = { math.floor((width - scale(170)) / 2), math.floor(height * 0.58) } }
    end
    self:clear()
    self[1] = OverlapGroup:new{ dimen = self.dimen, allow_mirroring = false, unpack(layers) }
end

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
        local InputDialog = require("ui/widget/inputdialog")
        local dialog
        dialog = InputDialog:new{
            title = _("AppDock PIN"), input = "", input_type = "number", input_hint = _("PIN"),
            buttons = { { { text = _("Cancel"), callback = function() UIManager:close(dialog) end }, { text = _("Unlock"), is_enter_default = true, callback = function()
                local value = dialog:getInputText() or ""
                UIManager:close(dialog)
                if settings.secret_hash and LockScreen.hash(value) == settings.secret_hash then self:_unlock() else self:_reject() end
            end } } },
        }
        UIManager:show(dialog); dialog:onShowKeyboard()
        return true
    end
    if settings.method == "pattern" and gesture and gesture.pos then
        local cell = scale(46)
        local gap = scale(14)
        local start_x = math.floor((self.dimen.w - (cell * 3 + gap * 2)) / 2)
        local start_y = math.floor(self.dimen.h * 0.52)
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
