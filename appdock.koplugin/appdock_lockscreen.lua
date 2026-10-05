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

function LockScreen:build()
    local width, height = self.dimen.w, self.dimen.h
    local method = self.appdock.settings.lockscreen.method or "swipe"
    local title = method == "pin" and _("Enter your PIN") or method == "pattern" and _("Draw your pattern") or _("Swipe to unlock")
    local detail = method == "swipe" and _("Swipe anywhere to continue") or method == "pattern" and _("Connect four points in order") or _("Use your AppDock PIN")
    local profile = self.appdock.settings.lockscreen or {}
    local margin = scale(18)
    local card_x, card_y = margin, scale(112)
    local card_w = width - 2 * margin
    local card_h = math.min(scale(540), height - card_y - scale(52))
    local now = os.date("%H:%M")
    local date = os.date("%A, %d %B")
    local profile_name = type(profile.profile_name) == "string" and profile.profile_name ~= "" and profile.profile_name or _("Welcome back")
    local hero = Wallpaper.buildPath(HERO_PATH, width, height, true)
    local layers = {
        hero or FrameContainer:new{ width = width, height = height, padding = 0, bordersize = 0, background = Blitbuffer.COLOR_WHITE,
            CenterContainer:new{ dimen = self.dimen, TextWidget:new{ text = "", face = Font:getFace("cfont", scale(1)) } } },
        FrameContainer:new{ width = width - 2 * margin, height = scale(72), padding = scale(12), bordersize = scale(1), color = Blitbuffer.COLOR_BLACK, radius = scale(18), background = Blitbuffer.COLOR_BLACK, overlap_offset = { margin, scale(22) },
            TextWidget:new{ text = "APPDOCK", face = Font:getFace("smallinfofont", scale(10)), fgcolor = Blitbuffer.COLOR_WHITE, bold = true, overlap_offset = { scale(14), scale(10) } },
            TextWidget:new{ text = now, face = Font:getFace("cfont", scale(27)), fgcolor = Blitbuffer.COLOR_WHITE, bold = true, overlap_offset = { scale(14), scale(23) } },
            TextWidget:new{ text = date, face = Font:getFace("smallinfofont", scale(10)), fgcolor = Blitbuffer.COLOR_LIGHT_GRAY, max_width = width - 2 * margin - scale(28), alignment = "right", overlap_offset = { scale(14), scale(39) } },
        },
        FrameContainer:new{ width = card_w, height = card_h, padding = scale(2), bordersize = scale(2), color = Blitbuffer.COLOR_BLACK, radius = scale(20), background = Blitbuffer.COLOR_WHITE, overlap_offset = { card_x, card_y },
            CenterContainer:new{ dimen = Geom:new{ w = card_w, h = card_h }, TextWidget:new{ text = "", face = Font:getFace("cfont", scale(1)) } } },
        FrameContainer:new{ width = scale(86), height = scale(6), padding = 0, bordersize = 0, radius = scale(3), background = Blitbuffer.ColorRGB32(255, 99, 83, 0xFF), overlap_offset = { math.floor((width - scale(86)) / 2), card_y + scale(18) } },
        TextWidget:new{ text = profile_name, face = Font:getFace("cfont", scale(22)), fgcolor = Blitbuffer.COLOR_BLACK, bold = true, max_width = width - 2 * margin, alignment = "center", overlap_offset = { margin, card_y + scale(106) } },
        TextWidget:new{ text = self.status or detail, face = Font:getFace("smallinfofont", scale(12)), fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = width - scale(64), alignment = "center", overlap_offset = { scale(32), card_y + scale(136) } },
        TextWidget:new{ text = title, face = Font:getFace("smallinfofont", scale(12)), fgcolor = Blitbuffer.COLOR_BLACK, bold = true, max_width = width - 2 * margin, alignment = "center", overlap_offset = { margin, card_y + scale(290) } },
        TextWidget:new{ text = method == "swipe" and "↔" or "• • •", face = Font:getFace("cfont", scale(24)), fgcolor = Blitbuffer.COLOR_BLACK, bold = true, max_width = width - 2 * margin, alignment = "center", overlap_offset = { margin, card_y + scale(198) } },
    }
    local avatar_size = scale(58)
    local avatar = Wallpaper.buildPath(profile.profile_image_path, avatar_size, avatar_size, true)
    if avatar then
        avatar.overlap_offset = { math.floor((width - avatar_size) / 2), card_y + scale(42) }
        layers[#layers + 1] = avatar
    else
        layers[#layers + 1] = FrameContainer:new{ width = avatar_size, height = avatar_size, padding = 0, bordersize = scale(2), color = Blitbuffer.COLOR_BLACK, radius = math.floor(avatar_size / 2), background = Blitbuffer.COLOR_LIGHT_GRAY,
            CenterContainer:new{ dimen = Geom:new{ w = avatar_size, h = avatar_size }, TextWidget:new{ text = "A", face = Font:getFace("cfont", scale(24)), fgcolor = Blitbuffer.COLOR_BLACK, bold = true } }, overlap_offset = { math.floor((width - avatar_size) / 2), card_y + scale(42) } }
    end
    if method == "pattern" then
        local cell, gap = scale(34), scale(10)
        local start_x = math.floor((width - (cell * 3 + gap * 2)) / 2)
        local start_y = card_y + scale(324)
        for index = 1, 9 do
            local column, row = (index - 1) % 3, math.floor((index - 1) / 3)
            local chosen = self.pattern:find(tostring(index), 1, true) ~= nil
            local button = FrameContainer:new{
                width = cell, height = cell, padding = 0, bordersize = scale(1), color = Blitbuffer.COLOR_BLACK,
                radius = math.floor(cell / 2), background = chosen and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
                CenterContainer:new{ dimen = Geom:new{ w = cell, h = cell }, TextWidget:new{ text = tostring(index), face = Font:getFace("smallinfofont", scale(13)), fgcolor = chosen and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK, bold = true } },
            }
            button.overlap_offset = { start_x + column * (cell + gap), start_y + row * (cell + gap) }
            layers[#layers + 1] = button
        end
    elseif method == "pin" then
        layers[#layers + 1] = TextWidget:new{ text = _("Tap anywhere to enter PIN"), face = Font:getFace("smallinfofont", scale(12)), fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = width - 2 * margin, alignment = "center", overlap_offset = { margin, card_y + scale(324) } }
    else
        layers[#layers + 1] = FrameContainer:new{ width = math.min(scale(220), width - 2 * scale(48)), height = scale(34), padding = 0, bordersize = scale(1), color = Blitbuffer.COLOR_BLACK, radius = scale(17), background = Blitbuffer.COLOR_WHITE,
            CenterContainer:new{ dimen = Geom:new{ w = math.min(scale(220), width - 2 * scale(48)), h = scale(34) }, TextWidget:new{ text = _("Swipe to open AppDock"), face = Font:getFace("smallinfofont", scale(11)), fgcolor = Blitbuffer.COLOR_BLACK, bold = true } }, overlap_offset = { math.floor((width - math.min(scale(220), width - 2 * scale(48))) / 2), card_y + scale(324) } }
    end
    layers[#layers + 1] = TextWidget:new{ text = _("Your private AppDock space"), face = Font:getFace("smallinfofont", scale(9)), fgcolor = Blitbuffer.COLOR_WHITE, max_width = width - 2 * margin, alignment = "center", overlap_offset = { margin, height - scale(28) } }
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
        AppDockKeyboard.attach(dialog, { secure = true })
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
