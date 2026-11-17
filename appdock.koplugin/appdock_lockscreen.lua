--[[--
AppDock's local access screen. It protects the AppDock homescreen only; it is
not a replacement for a device-level lockscreen or encrypted device storage.

The lockscreen is always shown (it can no longer be switched off); the weakest
setting is "swipe up to unlock". Two stages:

  wall    Full-bleed aurora photo, big clock, date, optional profile chip and a
          "swipe up" hint. With the swipe method, swiping up unlocks.
  secret  PIN / pattern only. Swiping up blurs the photo with the same backdrop
          blur as the quick settings shade and shows a round glass keypad on
          top of it. Swiping down (or "Cancel") returns to the photo.

Everything degrades gracefully: if the photo cannot be decoded, a dark navy
fill is used; if the blur fails, a translucent tint is drawn over the photo.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local sha2 = require("ffi/sha2")
local Glass = require("appdock_glass")
local Rotation = require("appdock_rotation")
local Wallpaper = require("appdock_wallpaper")
local _ = require("gettext")

local Screen = Device.screen
local GC = Glass.COLORS

local MODULE_DIR = (debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "")
local AURORA_PATH = MODULE_DIR .. "assets/lockscreen/appdock_lockscreen_aurora.jpg"

local MIN_SECRET, MAX_SECRET = 4, 32
local MAX_PATTERN = 9

local LockScreen = InputContainer:extend{
    appdock = nil,
    on_unlock = nil,
    dimen = nil,
    covers_fullscreen = true,
    stage = "wall",
    pin = "",
    pattern = "",
    status = nil,
    status_is_error = false,
}

local function scale(value) return Screen:scaleBySize(value) end
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

-- Clock styles (9.8.0): "standard" (one big line), "glass" (Liquid Glass: the
-- time on a frosted glass capsule) and "color" (hours and minutes stacked on
-- two big lines, every digit in its own color).
local CLOCK_STYLES = { "standard", "glass", "color" }
local function clockStyle(profile)
    local style = type(profile) == "table" and profile.clock_style or nil
    for _, known in ipairs(CLOCK_STYLES) do
        if style == known then return style end
    end
    return "standard"
end

-- One color per digit position (hour tens/ones, minute tens/ones); the gray is
-- what grayscale panels show instead.
local COLOR_DIGITS = {
    Glass.rgba(255, 92, 122, 255, Blitbuffer.COLOR_WHITE),
    Glass.rgba(255, 184, 77, 255, Blitbuffer.COLOR_GRAY_D),
    Glass.rgba(77, 227, 180, 255, Blitbuffer.COLOR_WHITE),
    Glass.rgba(90, 180, 255, 255, Blitbuffer.COLOR_GRAY_D),
}
local GLASS_RIM = Glass.rgba(255, 255, 255, 105, Blitbuffer.COLOR_GRAY_D)
local GLASS_BODY = Glass.rgba(70, 86, 138, 96, Blitbuffer.COLOR_GRAY_4)
local GLASS_SHINE = Glass.rgba(255, 255, 255, 38, Blitbuffer.COLOR_GRAY_6)

local function secretMatches(profile, value)
    return type(profile) == "table" and type(profile.secret_hash) == "string"
        and profile.secret_hash ~= "" and LockScreen.hash(value) == profile.secret_hash
end

local function inRect(pos, rect)
    return pos ~= nil and rect ~= nil and pos.x >= rect.x and pos.x < rect.x + rect.w
        and pos.y >= rect.y and pos.y < rect.y + rect.h
end

-- Round-key grid used by both PIN and pattern. The grid is placed in the free
-- band between `top_min` and `bottom_limit` (slightly above its centre).
local function keypadLayout(width, top_min, bottom_limit)
    local margin = scale(20)
    local gap_ratio = .20
    local available = math.max(1, bottom_limit - top_min)
    local by_width = math.floor((width - 2 * margin) / (3 + 2 * gap_ratio))
    local by_height = math.floor(available / (4 + 3 * gap_ratio))
    local d = math.max(scale(34), math.min(scale(92), by_width, by_height))
    local gap = math.max(scale(8), math.floor(d * gap_ratio))
    local grid_w, grid_h = 3 * d + 2 * gap, 4 * d + 3 * gap
    return {
        d = d, gap = gap, width = grid_w, height = grid_h,
        x = math.floor((width - grid_w) / 2),
        y = top_min + math.floor(math.max(0, available - grid_h) * .55),
    }
end

local function keyOrigin(layout, column, row)
    return layout.x + column * (layout.d + layout.gap), layout.y + row * (layout.d + layout.gap)
end

-- Photo: "cover" scaled and centre cropped to exactly the screen. Returns nil
-- when the image cannot be decoded.
local function buildWall(width, height, like_bb)
    local ok, result = pcall(function()
        local RenderImage = require("ui/renderimage")
        local source = RenderImage:renderImageFile(AURORA_PATH, false)
        if not source then return nil end
        local sw, sh = source:getWidth(), source:getHeight()
        local factor = math.max(width / sw, height / sh)
        local tw, th = math.ceil(sw * factor), math.ceil(sh * factor)
        local scaled = source
        if (tw ~= sw or th ~= sh) and RenderImage.scaleBlitBuffer then
            scaled = RenderImage:scaleBlitBuffer(source, tw, th, true) or source
            tw, th = scaled:getWidth(), scaled:getHeight()
        end
        local out = Blitbuffer.new(width, height, like_bb:getType())
        out:blitFrom(scaled, 0, 0, math.max(0, math.floor((tw - width) / 2)), math.max(0, math.floor((th - height) / 2)), width, height)
        if scaled.free then pcall(scaled.free, scaled) end
        -- Grayscale panels: slightly darker so the white clock stays readable.
        if not Glass.isColor() and out.darkenRect then pcall(out.darkenRect, out, 0, 0, width, height, .35) end
        return out
    end)
    if ok and result then return result end
    return nil
end

function LockScreen:freeImages()
    if self._avatar and type(self._avatar.free) == "function" then pcall(function() self._avatar:free() end) end
    self._avatar = nil
end

function LockScreen:freeBuffers()
    for _, key in ipairs({ "_wall", "_backdrop" }) do
        local bb = self[key]
        if bb and bb.free then pcall(bb.free, bb) end
        self[key] = nil
    end
    self._wall_failed, self._backdrop_failed = nil, nil
end

-- The blurred backdrop is dark navy on colour screens but a light veil on
-- grayscale panels, so text colours depend on the stage.
local function inkColor(stage, soft, error_state)
    if Glass.isColor() then
        if error_state then return Glass.solid(GC.sub_active) end
        return Glass.solid(soft and GC.sub_inactive or GC.white)
    end
    if stage == "secret" then return Blitbuffer.COLOR_BLACK end
    return soft and Blitbuffer.COLOR_GRAY_D or Blitbuffer.COLOR_WHITE
end

function LockScreen:build()
    self:freeImages()
    local width, height = self.dimen.w, self.dimen.h
    local profile = settingsFor(self.appdock)
    local method = lockMethod(profile)
    local stage = self.stage
    local layers = {}
    self._keys, self._hint_rect, self._cancel_rect = {}, nil, nil

    local function add(widget, x, y)
        widget.overlap_offset = { x, y }
        layers[#layers + 1] = widget
        return widget
    end
    local function text(value, face_name, size, color, bold)
        return TextWidget:new{
            text = value, face = Font:getFace(face_name, size), fgcolor = color,
            bold = bold == true, max_width = width - 2 * scale(16), padding = 0,
        }
    end
    local function sizeOf(widget)
        local info = widget:getSize()
        return info and info.w or 0, info and info.h or 0
    end
    -- Adds `value` horizontally centred inside [box_x, box_x + box_w].
    local function addCentered(value, face_name, size, color, y, bold, box_x, box_w)
        box_x, box_w = box_x or 0, box_w or width
        local widget = text(value, face_name, size, color, bold)
        local w, h = sizeOf(widget)
        add(widget, box_x + math.floor((box_w - w) / 2), y)
        return h
    end
    local function circle(x, y, d, color)
        add(Glass.Shape:new{ width = d, height = d, radius = math.floor(d / 2), color = color }, x, y)
    end

    local profile_name = type(profile.profile_name) == "string" and profile.profile_name:match("^%s*(.-)%s*$") or ""
    local has_image = type(profile.profile_image_path) == "string" and profile.profile_image_path ~= ""

    local function addAvatar(x, y, size)
        circle(x, y, size, GC.glass_hi)
        local avatar = has_image and Wallpaper.buildPath(profile.profile_image_path, size, size, true) or nil
        self._avatar = avatar
        if avatar then
            add(avatar, x, y)
        else
            local initial = (profile_name ~= "" and profile_name:sub(1, 1) or "A"):upper()
            local widget = text(initial, "cfont", math.floor(size * .46), inkColor("wall", false), true)
            local w, h = sizeOf(widget)
            add(widget, x + math.floor((size - w) / 2), y + math.floor((size - h) / 2))
        end
    end

    if stage == "wall" then
        local margin = math.max(scale(16), math.floor(width * .06))
        local white, soft = inkColor("wall", false), inkColor("wall", true)
        local y = math.max(scale(46), math.floor(height * .085))
        local style = clockStyle(profile)
        local clock_h
        if style == "color" then
            -- Hours on the first line, minutes on the second, one color per digit.
            local size = math.max(scale(64), math.floor(height * .125))
            local face = Font:getFace("cfont", size)
            local cell = 0
            for digit = 0, 9 do
                local probe = TextWidget:new{ text = tostring(digit), face = face, bold = true, padding = 0 }
                cell = math.max(cell, (probe:getSize() or {}).w or 0)
                if probe.free then pcall(probe.free, probe) end
            end
            local gap = math.floor(cell * .08)
            local row_x = math.floor((width - (2 * cell + gap)) / 2)
            local rows = { os.date("%H"), os.date("%M") }
            local cursor, line_h = y, 0
            for row = 1, 2 do
                for column = 1, 2 do
                    local digit = rows[row]:sub(column, column)
                    local ink = Glass.isColor() and Glass.solid(COLOR_DIGITS[(row - 1) * 2 + column]) or ((column == 1) and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_GRAY_D)
                    local widget = text(digit, "cfont", size, ink, true)
                    local w, h = sizeOf(widget)
                    line_h = h
                    add(widget, row_x + (column - 1) * (cell + gap) + math.floor((cell - w) / 2), cursor)
                end
                cursor = cursor + math.floor(line_h * .84)
            end
            clock_h = cursor - y + math.floor(line_h * .16)
        elseif style == "glass" then
            local size = math.max(scale(54), math.floor(height * .085))
            local widget = text(os.date("%H:%M"), "cfont", size, white, true)
            local w, h = sizeOf(widget)
            local card_w = math.min(width - 2 * margin, w + 2 * scale(28))
            local card_h = h + 2 * scale(10)
            local card_x = math.floor((width - card_w) / 2)
            local radius = math.floor(card_h * .34)
            local rim = math.max(1, scale(2))
            -- Rim light, frosted body, soft specular highlight on the upper half.
            add(Glass.Shape:new{ width = card_w, height = card_h, radius = radius, color = GLASS_RIM }, card_x, y)
            add(Glass.Shape:new{ width = card_w - 2 * rim, height = card_h - 2 * rim, radius = math.max(1, radius - rim), color = GLASS_BODY }, card_x + rim, y + rim)
            if Glass.isColor() then
                local shine_inset = scale(8)
                add(Glass.Shape:new{ width = card_w - 2 * shine_inset, height = math.floor(card_h * .42), radius = math.floor(card_h * .2), color = GLASS_SHINE }, card_x + shine_inset, y + rim + scale(2))
            end
            add(widget, card_x + math.floor((card_w - w) / 2), y + math.floor((card_h - h) / 2))
            clock_h = card_h
        else
            clock_h = addCentered(os.date("%H:%M"), "cfont", math.max(scale(54), math.floor(height * .085)), white, y, true)
        end
        y = y + clock_h + scale(style == "glass" and 10 or 2)
        local date_h = addCentered(os.date("%A, %d. %B"), "smallinfofont", scale(15), soft, y, false, margin, width - 2 * margin)
        y = y + date_h + scale(18)

        -- Optional profile chip (name and/or picture).
        if profile_name ~= "" or has_image then
            local label = text(profile_name ~= "" and profile_name or _("AppDock"), "cfont", scale(16), white, true)
            label.max_width = math.floor(width * .5)
            local label_w, label_h = sizeOf(label)
            local avatar_size = scale(38)
            local pad = scale(8)
            local chip_h = avatar_size + 2 * pad
            local chip_w = pad + avatar_size + scale(10) + label_w + scale(18)
            local chip_x = math.floor((width - chip_w) / 2)
            add(Glass.Shape:new{ width = chip_w, height = chip_h, radius = math.floor(chip_h / 2), color = GC.tint }, chip_x, y)
            addAvatar(chip_x + pad, y + pad, avatar_size)
            add(label, chip_x + pad + avatar_size + scale(10), y + math.floor((chip_h - label_h) / 2))
        end

        -- Bottom hint: chevron + pill.
        local label_text = method == "pin" and _("Swipe up to enter PIN")
            or method == "pattern" and _("Swipe up to draw pattern")
            or _("Swipe up to unlock")
        local hint = text(label_text, "smallinfofont", scale(14), white, true)
        local hint_w, hint_h = sizeOf(hint)
        local pill_h = scale(46)
        local pill_w = math.min(width - 2 * margin, hint_w + scale(56))
        local pill_x = math.floor((width - pill_w) / 2)
        local pill_y = height - pill_h - math.max(scale(44), math.floor(height * .05))
        local chevron = scale(30)
        add(Glass.Icon:new{ kind = "chevron_up", size = chevron, color = GC.white }, math.floor((width - chevron) / 2), pill_y - chevron - scale(6))
        add(Glass.Shape:new{ width = pill_w, height = pill_h, radius = math.floor(pill_h / 2), color = GC.tint }, pill_x, pill_y)
        add(hint, pill_x + math.floor((pill_w - hint_w) / 2), pill_y + math.floor((pill_h - hint_h) / 2))
        -- Generous tap target as a fallback for people who do not swipe.
        local tap_y = pill_y - chevron - scale(12)
        self._hint_rect = { x = 0, y = tap_y, w = width, h = height - tap_y }
    else
        local white, soft = inkColor("secret", false), inkColor("secret", true)
        local avatar_size = scale(58)
        local y = math.max(scale(28), math.floor(height * .045))
        addAvatar(math.floor((width - avatar_size) / 2), y, avatar_size)
        y = y + avatar_size + scale(8)
        local name_h = addCentered(profile_name ~= "" and profile_name or _("AppDock"), "cfont", scale(18), white, y, true)
        y = y + name_h + scale(4)
        local default_status = method == "pattern" and _("Tap your pattern") or _("Enter your PIN")
        local status_color = self.status_is_error and inkColor("secret", true, true) or soft
        local status_h = addCentered(self.status or default_status, "smallinfofont", scale(13), status_color, y)
        y = y + status_h + scale(16)

        if method == "pin" then
            local dot, gap = scale(14), scale(14)
            local entered = #self.pin
            local count = math.max(MIN_SECRET, math.min(entered, 16))
            local row_w = count * dot + (count - 1) * gap
            local x = math.floor((width - row_w) / 2)
            for index = 1, count do
                circle(x + (index - 1) * (dot + gap), y, dot, index <= entered and GC.white or GC.glass_hi)
            end
            y = y + dot + scale(18)
        end

        local cancel_h = scale(40)
        local bottom_limit = height - math.max(scale(56), math.floor(height * .07)) - cancel_h
        local layout = keypadLayout(width, y, bottom_limit)
        local d = layout.d
        local font_size = math.floor(d * .40)
        local value_now = method == "pin" and self.pin or self.pattern
        local can_submit = #value_now >= MIN_SECRET

        local function addKey(column, row, value, label, icon, active)
            local x, ky = keyOrigin(layout, column, row)
            circle(x, ky, d, active and GC.active or GC.glass)
            local ink = active and GC.on_active or GC.white
            if icon then
                local icon_size = math.floor(d * .46)
                add(Glass.Icon:new{ kind = icon, size = icon_size, color = ink }, x + math.floor((d - icon_size) / 2), ky + math.floor((d - icon_size) / 2))
            else
                local widget = text(label, "cfont", font_size, Glass.isColor() and Glass.solid(ink) or (active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE), true)
                local w, h = sizeOf(widget)
                add(widget, x + math.floor((d - w) / 2), ky + math.floor((d - h) / 2))
            end
            self._keys[#self._keys + 1] = { x = x, y = ky, w = d, h = d, value = value }
        end

        for index = 1, 9 do
            local column, row = (index - 1) % 3, math.floor((index - 1) / 3)
            local selected = method == "pattern" and self.pattern:find(tostring(index), 1, true) ~= nil
            addKey(column, row, tostring(index), tostring(index), nil, selected)
        end
        addKey(0, 3, "back", nil, "backspace", false)
        if method == "pin" then addKey(1, 3, "0", "0", nil, false) end
        addKey(2, 3, "ok", nil, "check", can_submit)

        local cancel_label = text(_("Cancel"), "smallinfofont", scale(14), white, true)
        local cancel_label_w, cancel_label_h = sizeOf(cancel_label)
        local cancel_w = math.max(scale(140), cancel_label_w + scale(40))
        local cancel_y = bottom_limit + scale(10)
        add(cancel_label, math.floor((width - cancel_label_w) / 2), cancel_y + math.floor((cancel_h - cancel_label_h) / 2))
        self._cancel_rect = { x = math.floor((width - cancel_w) / 2), y = cancel_y, w = cancel_w, h = cancel_h }
    end

    self:clear()
    self[1] = OverlapGroup:new{ dimen = self.dimen, allow_mirroring = false, unpack(layers) }
end

function LockScreen:init()
    self.dimen = Screen:getSize()
    self:build()
    self.ges_events = {
        LockSwipe = { GestureRange:new{ ges = "swipe", range = self.dimen } },
        LockTap = { GestureRange:new{ ges = "tap", range = self.dimen } },
    }
end

function LockScreen:_paintBackground(bb, x, y)
    local width, height = self.dimen.w, self.dimen.h
    if not self._wall and not self._wall_failed then
        self._wall = buildWall(width, height, bb)
        self._wall_failed = self._wall == nil
    end
    local source = self._wall
    if self.stage == "secret" and self._wall then
        -- Same backdrop blur as the quick settings shade: captured once from
        -- the clean photo, then simply blitted on every repaint.
        if not self._backdrop and not self._backdrop_failed then
            self._backdrop = Glass.buildBackdrop(self._wall, width, height, 0, 0)
            self._backdrop_failed = self._backdrop == nil
        end
        source = self._backdrop or self._wall
    end
    local drawn = false
    if source then drawn = pcall(bb.blitFrom, bb, source, x, y, 0, 0, width, height) end
    if not drawn then
        bb:paintRect(x, y, width, height, Glass.solid(Glass.rgba(8, 18, 48, 255, Blitbuffer.COLOR_BLACK)))
    elseif self.stage == "secret" and source == self._wall then
        -- Blur failed: at least calm the photo down with the same tint.
        Glass.drawShape(bb, x, y, width, height, 0, GC.tint)
    end
end

function LockScreen:paintTo(bb, x, y)
    for _, name in ipairs({ "LockSwipe", "LockTap" }) do
        local range = self.ges_events[name][1].range
        range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    end
    self:_paintBackground(bb, x, y)
    return InputContainer.paintTo(self, bb, x, y)
end

function LockScreen:onCloseWidget()
    self:freeImages()
    self:freeBuffers()
end

function LockScreen:_refresh(mode)
    UIManager:setDirty(self, mode or "ui")
end

function LockScreen:_unlock()
    UIManager:close(self)
    UIManager:nextTick(function() if self.on_unlock then self.on_unlock() end end)
end

function LockScreen:_setStage(stage)
    if self.stage == stage then return end
    self.stage = stage
    self.pin, self.pattern, self.status, self.status_is_error = "", "", nil, false
    self:build()
    self:_refresh("flashui")
end

function LockScreen:_advance()
    if lockMethod(settingsFor(self.appdock)) == "swipe" then
        self:_unlock()
    else
        self:_setStage("secret")
    end
end

function LockScreen:_reject(message)
    self.status = message or _("That does not match. Try again.")
    self.status_is_error = true
    self.pin, self.pattern = "", ""
    self:build()
    self:_refresh("ui")
end

function LockScreen:_submit()
    local profile = settingsFor(self.appdock)
    local method = lockMethod(profile)
    local value = method == "pin" and self.pin or self.pattern
    if #value < MIN_SECRET then
        self.status = method == "pin" and _("Enter at least 4 digits.") or _("Tap at least 4 points.")
        self.status_is_error = true
        self:build()
        self:_refresh("ui")
        return
    end
    if secretMatches(profile, value) then self:_unlock() else self:_reject() end
end

function LockScreen:_press(value)
    local profile = settingsFor(self.appdock)
    local method = lockMethod(profile)
    if value == "ok" then return self:_submit() end
    local field = method == "pin" and "pin" or "pattern"
    local current = self[field]
    if value == "back" then
        current = current:sub(1, -2)
    elseif method == "pin" then
        if #current >= MAX_SECRET then return end
        current = current .. value
    else
        if current:find(value, 1, true) or #current >= MAX_PATTERN then return end
        current = current .. value
    end
    self[field] = current
    self.status, self.status_is_error = nil, false
    -- A pattern is accepted as soon as it matches, so people with a 4-point
    -- pattern do not need the confirm key.
    if method == "pattern" and #current >= MIN_SECRET and secretMatches(profile, current) then
        return self:_unlock()
    end
    self:build()
    self:_refresh("ui")
end

function LockScreen:onLockSwipe(args, ges)
    local direction = ges and ges.direction
    local up = direction == "north" or direction == "northeast" or direction == "northwest"
    local down = direction == "south" or direction == "southeast" or direction == "southwest"
    if self.stage == "wall" then
        if up then self:_advance() end
    elseif down then
        self:_setStage("wall")
    end
    return true
end

function LockScreen:onLockTap(args, ges)
    local pos = ges and ges.pos
    if not pos then return true end
    if self.stage == "wall" then
        if inRect(pos, self._hint_rect) then self:_advance() end
        return true
    end
    if inRect(pos, self._cancel_rect) then
        self:_setStage("wall")
        return true
    end
    for _, key in ipairs(self._keys or {}) do
        if inRect(pos, key) then
            self:_press(key.value)
            break
        end
    end
    return true
end

function LockScreen.show(appdock, callback)
    local widget = LockScreen:new{ appdock = appdock, on_unlock = callback }
    UIManager:show(widget)
    return widget
end

LockScreen.CLOCK_STYLES = CLOCK_STYLES
LockScreen.clockStyle = clockStyle

LockScreen._test = {
    lockMethod = lockMethod,
    clockStyle = clockStyle,
    keypadLayout = keypadLayout,
    keyOrigin = keyOrigin,
    secretMatches = secretMatches,
}

-- Rotation (9.6.0): the photo is cropped to the screen, so it is rebuilt too.
Rotation.attach(LockScreen, { relayout = function(self)
    self:freeBuffers()
    self:build()
end })

return LockScreen
