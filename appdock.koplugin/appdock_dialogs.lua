-- AppDock-owned modal surfaces. These deliberately avoid KOReader's
-- ButtonDialog/InputDialog/ConfirmBox/InfoMessage widgets while keeping the
-- small constructor/callback contracts used by AppDock's existing call sites.
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local ImageWidget
pcall(function() ImageWidget = require("ui/widget/imagewidget") end)
local Screen = Device.screen
local function scale(n) return Screen:scaleBySize(n) end
local function clamp(n, lo, hi) return math.max(lo, math.min(hi, n)) end
local function rgb(hex, alpha, fallback)
    local red = tonumber(hex:sub(2, 3), 16)
    local green = tonumber(hex:sub(4, 5), 16)
    local blue = tonumber(hex:sub(6, 7), 16)
    if type(Blitbuffer.ColorRGB32) == "function" then
        local ok, value = pcall(Blitbuffer.ColorRGB32, red, green, blue, alpha or 255)
        if ok and value then return value end
    end
    return fallback or Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_BLACK
end
local GRAY = {
    olive = Blitbuffer.COLOR_GRAY_8 or Blitbuffer.COLOR_DARK_GRAY,
    olive_dark = Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_BLACK,
    olive_soft = Blitbuffer.COLOR_LIGHT_GRAY or Blitbuffer.COLOR_WHITE,
    glass = Blitbuffer.COLOR_LIGHT_GRAY or Blitbuffer.COLOR_WHITE,
    panel = Blitbuffer.COLOR_WHITE, ink = Blitbuffer.COLOR_BLACK,
    muted = Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_BLACK,
    outline = Blitbuffer.COLOR_GRAY or Blitbuffer.COLOR_GRAY_8,
    disabled = Blitbuffer.COLOR_LIGHT_GRAY or Blitbuffer.COLOR_WHITE,
}
local color_enabled = false
if Screen and type(Screen.isColorEnabled) == "function" then
    local ok, value = pcall(Screen.isColorEnabled, Screen)
    color_enabled = ok and value == true
end
local function dialogColor(hex, alpha, grayscale)
    return color_enabled and rgb(hex, alpha, grayscale) or grayscale
end
local COLORS = {
    olive = dialogColor("#667744", 255, GRAY.olive), olive_dark = dialogColor("#40512A", 255, GRAY.olive_dark),
    olive_soft = dialogColor("#E8EDDE", 255, GRAY.olive_soft), glass = dialogColor("#F7F8F3", 168, GRAY.glass),
    panel = dialogColor("#FBFCF8", 255, GRAY.panel), ink = dialogColor("#26301D", 255, GRAY.ink),
    muted = dialogColor("#5C6553", 255, GRAY.muted), outline = dialogColor("#A8B196", 255, GRAY.outline),
    disabled = dialogColor("#E7E8E3", 255, GRAY.disabled),
    on_olive = dialogColor("#FFFFFF", 255, GRAY.panel),
}
local function drawRectRGB32(bb, x, y, width, height, fill)
    -- KOReader's BlitBuffer exposes paintRectRGB32 (rather than drawRectRGB32).
    -- Keep every custom RGB fill on that path; grayscale targets use paintRect.
    if color_enabled and bb.paintRectRGB32 then
        return bb:paintRectRGB32(x, y, width, height, fill)
    end
    return bb:paintRect(x, y, width, height, fill)
end
local function drawRoundedRect(bb, x, y, width, height, radius, fill)
    width, height = math.max(1, math.floor(width)), math.max(1, math.floor(height))
    radius = math.max(0, math.min(math.floor(radius or 0), math.floor(width / 2), math.floor(height / 2)))
    if radius == 0 then drawRectRGB32(bb, x, y, width, height, fill); return end
    for row = 0, height - 1 do
        local inset = 0
        if row < radius then
            local dy = radius - row - .5
            inset = math.max(0, math.ceil(radius - math.sqrt(math.max(0, radius * radius - dy * dy))))
        elseif row >= height - radius then
            local dy = row - (height - radius) + .5
            inset = math.max(0, math.ceil(radius - math.sqrt(math.max(0, radius * radius - dy * dy))))
        end
        drawRectRGB32(bb, x + inset, y + row, math.max(1, width - 2 * inset), 1, fill)
    end
end
local function drawGlassRoundedRect(bb, x, y, width, height, radius, opaque_fallback)
    width, height = math.max(1, math.floor(width)), math.max(1, math.floor(height))
    radius = math.max(0, math.min(math.floor(radius or 0), math.floor(width / 2), math.floor(height / 2)))
    local scratch
    if not bb.blendRectRGB32 and bb.addblitFrom and Blitbuffer.new and bb.getType then
        local ok, buffer = pcall(Blitbuffer.new, width, 1, bb:getType())
        if ok and buffer then scratch = buffer; pcall(scratch.fill, scratch, GRAY.panel) end
    end
    local glass_color
    if bb.blendRectRGB32 and type(Blitbuffer.ColorRGB32) == "function" then
        local ok, value = pcall(Blitbuffer.ColorRGB32, 248, 250, 242, 202)
        if ok then glass_color = value end
    end
    for row = 0, height - 1 do
        local inset = 0
        if row < radius then
            local dy = radius - row - .5
            inset = math.max(0, math.ceil(radius - math.sqrt(math.max(0, radius * radius - dy * dy))))
        elseif row >= height - radius then
            local dy = row - (height - radius) + .5
            inset = math.max(0, math.ceil(radius - math.sqrt(math.max(0, radius * radius - dy * dy))))
        end
        local row_x, row_width = x + inset, math.max(1, width - 2 * inset)
        if glass_color then
            local ok = pcall(bb.blendRectRGB32, bb, row_x, y + row, row_width, 1, glass_color)
            if not ok then bb:paintRect(row_x, y + row, row_width, 1, opaque_fallback) end
        elseif scratch then
            local ok = pcall(bb.addblitFrom, bb, scratch, row_x, y + row, 0, 0, row_width, 1, .78)
            if not ok then bb:paintRect(row_x, y + row, row_width, 1, opaque_fallback) end
        else
            bb:paintRect(row_x, y + row, row_width, 1, opaque_fallback)
        end
    end
    if scratch and scratch.free then pcall(scratch.free, scratch) end
end
local function paintFrostedVeil(bb, width, height)
    -- True backdrop blur is not available on all KOReader targets (especially
    -- grayscale E-Ink); alpha blending keeps the page visible through a soft,
    -- light-tinted veil and reads as frosted glass without replacing the page.
    if bb.blendRectRGB32 and type(Blitbuffer.ColorRGB32) == "function" then
        local ok, tint = pcall(Blitbuffer.ColorRGB32, 238, 241, 229, 112)
        if ok and tint then pcall(bb.blendRectRGB32, bb, 0, 0, width, height, tint); return end
    end
    if bb.addblitFrom and Blitbuffer.new and bb.getType then
        local ok, overlay = pcall(Blitbuffer.new, width, height, bb:getType())
        if ok and overlay then
            local fill = GRAY.glass
            pcall(overlay.fill, overlay, fill)
            pcall(bb.addblitFrom, bb, overlay, 0, 0, 0, 0, width, height, .34)
            if overlay.free then pcall(overlay.free, overlay) end
            return
        end
    end
    -- Safe fallback for reduced/mock buffers without alpha-compositing APIs.
    bb:paintRect(0, 0, width, height, GRAY.glass)
end
local function textWidth(face, text, fallback)
    if face and face.getWidth then
        local ok, width = pcall(face.getWidth, face, text)
        if ok and type(width) == "number" then return width end
    end
    return #text * fallback * 0.52
end
local function wrapText(text, width, face, size)
    local wrapped = {}
    local fallback = scale(size)
    for paragraph in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
        if paragraph == "" then
            wrapped[#wrapped + 1] = ""
        else
            local line = ""
            for word in paragraph:gmatch("%S+") do
                -- Break an unusually long token at UTF-8 codepoint boundaries
                -- rather than letting TextWidget silently clip it at max_width.
                if textWidth(face, word, fallback) > width then
                    if line ~= "" then wrapped[#wrapped + 1] = line; line = "" end
                    local chunk, position = "", 1
                    while position <= #word do
                        local byte = word:byte(position) or 0
                        local char_width = byte >= 240 and 4 or (byte >= 224 and 3 or (byte >= 192 and 2 or 1))
                        local character = word:sub(position, position + char_width - 1)
                        local candidate = chunk .. character
                        if chunk ~= "" and textWidth(face, candidate, fallback) > width then
                            wrapped[#wrapped + 1] = chunk
                            chunk = character
                        else
                            chunk = candidate
                        end
                        position = position + char_width
                    end
                    line = chunk
                else
                local candidate = line == "" and word or line .. " " .. word
                if line ~= "" and textWidth(face, candidate, fallback) > width then
                    wrapped[#wrapped + 1] = line
                    line = word
                else
                    line = candidate
                end
                end
            end
            if line ~= "" then wrapped[#wrapped + 1] = line end
        end
    end
    return table.concat(wrapped, "\n")
end
local function textWidget(text, width, size, bold, foreground)
    local face = Font:getFace(bold and "cfont" or "smallinfofont", scale(size))
    return TextWidget:new{
        text = tostring(text or ""), face = face,
        fgcolor = foreground or Blitbuffer.COLOR_BLACK, bold = bold or false, padding = 0, max_width = width,
    }
end
local function bodyTextWidget(text, width, size, foreground)
    local face = Font:getFace("smallinfofont", scale(size))
    local wrapped = wrapText(text, width, face, size)
    local lines = {}
    for line in (wrapped .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = TextWidget:new{
            text = line, face = face,
            fgcolor = foreground or Blitbuffer.COLOR_BLACK, padding = 0, max_width = width,
        }
    end
    -- Empty TextWidgets may report a zero-height size on some KOReader builds.
    -- Keep a full line slot for them so the paragraph/page counter after a
    -- deliberate blank line cannot overlap the preceding text.
    local line_height = scale(size + 4)
    for _, line in ipairs(lines) do
        local dims = line.getSize and line:getSize()
        if dims and type(dims.h) == "number" then
            line_height = math.max(line_height, dims.h)
        end
    end
    return {
        -- Keep the wrapped source for diagnostics and callers, but render each
        -- line as its own TextWidget. KOReader TextWidget is not consistently
        -- multiline across device builds, even when given explicit newlines.
        text = wrapped,
        lines = lines,
        line_height = line_height,
        getSize = function(self)
            return { w = width, h = #self.lines * self.line_height }
        end,
        paintTo = function(self, bb, x, y)
            local line_y = y
            for _, line in ipairs(self.lines) do
                line:paintTo(bb, x, line_y)
                line_y = line_y + self.line_height
            end
        end,
    }
end
local Modal = InputContainer:extend{ mode=nil, title=nil, text=nil, image=nil, image_alt=nil, buttons=nil, duration=nil }
function Modal:init()
    self.mode = self.mode or "buttons"
    if self.mode == "input" and not self.text then self.text = self.description end
    local screen = Screen.getSize and Screen:getSize()
        or { w=(Screen.getWidth and Screen:getWidth() or Screen.width or 600),
            h=(Screen.getHeight and Screen:getHeight() or Screen.height or 800) }
    self.screen_w, self.screen_h = screen.w, screen.h
    self.dimen = Geom:new{ x=0, y=0, w=screen.w, h=screen.h }
    self.margin = math.max(scale(10), math.min(scale(18), math.floor(screen.w / 12)))
    self.card_w = math.max(1, math.min(math.max(1, screen.w - self.margin * 2), scale(560)))
    self.card_x = math.floor((screen.w - self.card_w) / 2)
    self.max_card_h = math.max(scale(120), screen.h - self.margin * 2)
    self.content_w = self.card_w - scale(36)
    self.palette = COLORS
    self.gray = GRAY
    self.corner = scale(16)
    self.title_lines = self.title and bodyTextWidget(self.title, self.card_w - scale(48), 18, COLORS.ink) or nil
    self.title_h = self.title_lines and math.max(scale(32), self.title_lines:getSize().h) or scale(12)
    self.image_widget = nil
    self.image_w = 0
    self.image_h = 0
    if self.image and ImageWidget then
        local image_file = io.open(self.image, "rb")
        if image_file then
            image_file:close()
            local ok, widget = pcall(ImageWidget.new, ImageWidget, {
                file = self.image,
                -- The packaged preview is square. Keep the widget's target box
                -- square instead of passing a wide-and-short rectangle, which
                -- makes ImageWidget stretch the bitmap on some KOReader builds.
                width = scale(88),
                height = scale(88),
                scale_factor = 0,
                file_do_cache = false,
            })
            if ok and widget then
                self.image_widget = widget
                self.image_w = scale(88)
                self.image_h = scale(88)
            end
        end
    end
    self.body_widget = self.text and bodyTextWidget(self.text, self.card_w - scale(36), 14) or nil
    local body_dims
    if self.body_widget and self.body_widget.getSize then
        local ok,dims=pcall(self.body_widget.getSize,self.body_widget)
        if ok then body_dims=dims end
    end
    self.body_h = self.body_widget and math.min(body_dims and body_dims.h or scale(48), math.floor(self.max_card_h * 0.42)) or 0
    self.input_h = self.mode == "input" and scale(56) or 0
    self.row_h = scale(46)
    self.footer_h = scale(52)
    self.top_h = self.margin + self.title_h
        + (self.image_h > 0 and scale(8) + self.image_h or 0)
        + (self.body_h > 0 and scale(12) + self.body_h or 0) + scale(10)
    self.rows = self:_normalizeRows(self.buttons or {})
    if self.mode == "confirm" then
        self.rows = { {
            { text=self.ok_text or _("OK"), callback=self.ok_callback, is_default=true },
            { text=self.cancel_text or _("Cancel"), callback=self.cancel_callback },
        } }
    elseif self.mode == "info" then
        self.rows = { { { text=_("Done"), callback=function() self:close() end } } }
    end
    self:_measureButtonRows()
    self:_paginate()
    self._hits = {}
    self.ges_events = { TapAppDockModal = { GestureRange:new{ ges="tap", range=function() return self.dimen end } } }
    local DeviceModule = Device
    if DeviceModule.hasKeys and DeviceModule:hasKeys() and DeviceModule.input and DeviceModule.input.group then
        local back = DeviceModule.input.group.Back
        if back then self.key_events = { CloseAppDockModal = { back } } end
    end
    if self.mode == "input" then
        self.input_value = tostring(self.input or "")
        self.input_widget = { onShowKeyboard=function() return self:onShowKeyboard() end }
        self._input_widget = self.input_widget
    end
    if self.mode == "info" and self.duration ~= 0 and UIManager.scheduleIn then
        local delay = tonumber(self.duration) or 3.5
        self._auto_close = function() if not self._closed then self:close() end end
        UIManager:scheduleIn(delay, self._auto_close)
    end
end
function Modal:_normalizeRows(rows)
    local normalized = {}
    for _, row in ipairs(rows or {}) do
        local cells = {}
        if row.text then
            cells[1] = row
        else
            for _, button in ipairs(row or {}) do
                if type(button) == "table" then cells[#cells+1] = button end
            end
        end
        -- The renderer intentionally has at most two columns. Splitting wider
        -- caller-provided rows prevents overlapping labels and keeps each
        -- choice finger-sized on smaller E-Ink readers.
        for first = 1, #cells, 2 do
            local normalized_row = { cells[first] }
            if cells[first + 1] then normalized_row[#normalized_row + 1] = cells[first + 1] end
            if normalized_row[1] then normalized[#normalized + 1] = normalized_row end
        end
    end
    return normalized
end
function Modal:_measureButtonRows()
    self.row_heights, self.button_labels = {}, {}
    local pad, gap = scale(18), scale(6)
    local inner = self.card_w - 2 * pad
    for row_index, row in ipairs(self.rows) do
        local columns = #row > 1 and 2 or 1
        local cell_width = columns == 1 and inner or math.floor((inner - gap) / 2)
        local line_height, row_height = scale(17), scale(42)
        self.button_labels[row_index] = {}
        for col, button in ipairs(row) do
            local label = bodyTextWidget(tostring(button.text or ""), cell_width - scale(18), 13, COLORS.ink)
            self.button_labels[row_index][col] = label
            row_height = math.max(row_height, label:getSize().h + scale(12))
        end
        self.row_heights[row_index] = row_height + scale(4)
    end
end
function Modal:_paginate()
    local fixed = self.top_h + self.footer_h + scale(14) + self.input_h
    local available = math.max(scale(38), self.max_card_h - fixed)
    self.page_ranges = {}
    local first, height = 1, 0
    for index, row_height in ipairs(self.row_heights) do
        if height > 0 and height + row_height > available then
            self.page_ranges[#self.page_ranges + 1] = { first = first, last = index - 1, rows_height = height }
            first, height = index, 0
        end
        height = height + math.min(row_height, available)
    end
    if #self.row_heights > 0 then
        self.page_ranges[#self.page_ranges + 1] = { first = first, last = #self.row_heights, rows_height = height }
    end
    if #self.page_ranges == 0 then self.page_ranges[1] = { first = 1, last = 0, rows_height = 0 } end
    self.pages = #self.page_ranges
    self.page = clamp(self.page or 1, 1, self.pages)
    local current = self.page_ranges[self.page]
    self.card_h = math.min(self.max_card_h, fixed + current.rows_height)
    self.card_y = math.floor((self.screen_h - self.card_h) / 2)
end

function Modal:getInputText() return self.input_value or "" end
function Modal:setInputText(value)
    self.input_value = tostring(value or "")
    self.input = self.input_value
end
function Modal:_showNativeKeyboard()
    local ok, NativeInputDialog = pcall(require, "ui/widget/inputdialog")
    if not ok or not NativeInputDialog then return false end
    local native_dialog
    local native_buttons = {}
    for row_index, row in ipairs(self.buttons or {}) do
        native_buttons[row_index] = {}
        for button_index, button in ipairs(row or {}) do
            local native_button = {}
            for key, value in pairs(button) do native_button[key] = value end
            local callback = button.callback
            native_button.callback = function()
                if native_dialog and native_dialog.getInputText then
                    self:setInputText(native_dialog:getInputText())
                end
                if callback then return callback() end
            end
            native_buttons[row_index][button_index] = native_button
        end
    end
    local keyboard_options = self.appdock_keyboard_options or {}
    native_dialog = NativeInputDialog:new{
        title = self.title,
        input = self:getInputText(),
        input_hint = self.input_hint,
        input_type = self.input_type,
        secure = keyboard_options.secure or self.secure,
        buttons = native_buttons,
    }
    self:close()
    UIManager:show(native_dialog)
    if native_dialog.onShowKeyboard then native_dialog:onShowKeyboard() end
    return true
end
function Modal:onShowKeyboard()
    if self.appdock_keyboard_attached then return false end
    local Keyboard = require("appdock_keyboard")
    local keyboard_options = self.appdock_keyboard_options or {
        title = self.title,
        placeholder = self.input_hint,
        numeric_only = self.input_type == "number",
        secure = self.secure,
    }
    local attached = Keyboard.attach(self, keyboard_options)
    if attached then return self:onShowKeyboard() end
    return self:_showNativeKeyboard()
end
function Modal:close()
    if self._closed then return end
    self._closed = true
    if self._auto_close then if UIManager.unschedule then UIManager:unschedule(self._auto_close) end; self._auto_close=nil end
    UIManager:close(self)
end
function Modal:onCloseWidget() self._closed=true; if self._auto_close then if UIManager.unschedule then UIManager:unschedule(self._auto_close) end; self._auto_close=nil end end
function Modal:onCloseAppDockModal() self:close(); return true end
-- A held physical page key may keep repeating after a power modal is opened.
-- Consume those repeats here instead of letting KOReader dispatch them through
-- a newly replaced widget tree.
function Modal:onKeyRepeat() return true end
function Modal:_buttonCallback(button)
    if not button or button.enabled == false or button.disabled then return true end
    local callback=button.callback
    if callback then callback() end
    if not self._closed then self:close() end
    return true
end
function Modal:onTapAppDockModal(_, event)
    local p=event and event.pos
    if not p then return true end
    local x,y=p.x,p.y
    for _, hit in ipairs(self._hits) do
        if x>=hit.x and x<=hit.x+hit.w and y>=hit.y and y<=hit.y+hit.h then
            if hit.action then return hit.action() end
            if hit.button then return self:_buttonCallback(hit.button) end
            if hit.input then return self:onShowKeyboard() end
        end
    end
    if x<self.card_x or x>self.card_x+self.card_w or y<self.card_y or y>self.card_y+self.card_h then self:close() end
    return true
end
function Modal:_paintText(bb, text, x, y, width, size, bold, foreground)
    local widget=textWidget(text,width,size,bold,foreground)
    local dims=widget.getSize and widget:getSize() or { h=scale(size+4) }
    widget:paintTo(bb,x,y)
    return dims.h
end
function Modal:paintTo(bb, x, y)
    x, y = 0, 0
    self._hits = {}
    paintFrostedVeil(bb, self.screen_w, self.screen_h)
    local shadow = dialogColor("#DCE2D1", 255, GRAY.disabled)
    drawRoundedRect(bb, self.card_x + scale(2), self.card_y + scale(4), self.card_w, self.card_h, self.corner, shadow)
    drawGlassRoundedRect(bb, self.card_x, self.card_y, self.card_w, self.card_h, self.corner, COLORS.panel)
    local pad, border = scale(18), math.max(1, scale(1))
    -- Slim olive title rule, rather than a heavy full-width title band.
    drawRoundedRect(bb, self.card_x + pad, self.card_y + self.margin + self.title_h + scale(3),
        self.card_w - 2 * pad, scale(3), scale(2), COLORS.olive)
    local text_y = self.card_y + self.margin
    if self.title_lines then self.title_lines:paintTo(bb, self.card_x + pad, text_y) end
    local y0 = self.card_y + self.top_h
    if self.mode == "input" then
        local input_y, input_h = y0, scale(48)
        drawRoundedRect(bb, self.card_x + pad, input_y, self.card_w - pad * 2, input_h, scale(9), COLORS.olive_soft)
        self:_paintText(bb, (self.input_value ~= "" and self.input_value or self.input_hint or "Tap to enter text"),
            self.card_x + pad + scale(8), input_y + scale(12), self.card_w - pad * 2 - scale(16), 14, false, COLORS.ink)
        self._hits[#self._hits + 1] = { x = self.card_x + pad, y = input_y, w = self.card_w - pad * 2, h = input_h, input = true }
    else
        local body_y = self.card_y + self.margin + self.title_h + scale(14)
        if self.image_widget then
            body_y = body_y + scale(8)
            local image_x = self.card_x + pad + math.floor((self.content_w - self.image_w) / 2)
            self.image_widget:paintTo(bb, image_x, body_y)
            body_y = body_y + self.image_h
        end
        if self.body_widget then
            body_y = body_y + scale(8)
            self.body_widget:paintTo(bb, self.card_x + pad, body_y)
        end
    end
    local range = self.page_ranges[self.page]
    local rows_y, row_y = y0 + self.input_h, y0 + self.input_h
    for index = range.first, range.last do
        local row, row_height = self.rows[index], self.row_heights[index]
        local columns = #row > 1 and 2 or 1
        local gap, inner_w = scale(7), self.card_w - pad * 2
        local width = columns == 1 and inner_w or math.floor((inner_w - gap) / 2)
        for col, button in ipairs(row) do
            local bx = self.card_x + pad + (columns == 1 and 0 or (col - 1) * (width + gap))
            local disabled = button.enabled == false or button.disabled
            local primary = button.is_default or button.is_enter_default
            local fill = disabled and COLORS.disabled or (primary and COLORS.olive or COLORS.panel)
            local outline = disabled and COLORS.outline or (primary and COLORS.olive_dark or COLORS.outline)
            local foreground = disabled and COLORS.muted or (primary and COLORS.on_olive or COLORS.ink)
            drawRoundedRect(bb, bx, row_y, width, row_height - scale(4), scale(9), outline)
            drawRoundedRect(bb, bx + border, row_y + border, width - border * 2, row_height - scale(4) - border * 2,
                scale(8), fill)
            local label = self.button_labels[index][col]
            local size = label:getSize()
            for _, text_line in ipairs(label.lines) do text_line.fgcolor = foreground end
            label:paintTo(bb, bx + scale(9), row_y + math.max(scale(4), math.floor((row_height - size.h) / 2) - scale(2)))
            self._hits[#self._hits + 1] = { x = bx, y = row_y, w = width, h = row_height, button = button }
        end
        row_y = row_y + row_height
    end
    if self.pages > 1 then
        local footer_y = self.card_y + self.card_h - self.footer_h
        local label = string.format(_("Page %d of %d"), self.page, self.pages)
        self:_paintText(bb, label, self.card_x + math.floor((self.card_w - scale(100)) / 2), footer_y + scale(11), scale(100), 11, false, COLORS.muted)
        local button_w, button_h = scale(80), scale(32)
        if self.page > 1 then
            local bx = self.card_x + pad
            drawRoundedRect(bb, bx, footer_y + scale(7), button_w, button_h, scale(10), COLORS.olive_soft)
            self:_paintText(bb, _("‹ Previous"), bx + scale(5), footer_y + scale(16), button_w - scale(10), 10, true, COLORS.ink)
            self._hits[#self._hits + 1] = { x = bx, y = footer_y, w = button_w, h = self.footer_h, action = function()
                self.page = self.page - 1; self:_paginate(); UIManager:setDirty(self, "ui"); return true
            end }
        end
        if self.page < self.pages then
            local bx = self.card_x + self.card_w - pad - button_w
            drawRoundedRect(bb, bx, footer_y + scale(7), button_w, button_h, scale(10), COLORS.olive_soft)
            self:_paintText(bb, _("Next ›"), bx + scale(8), footer_y + scale(16), button_w - scale(12), 10, true, COLORS.ink)
            self._hits[#self._hits + 1] = { x = bx, y = footer_y, w = button_w, h = self.footer_h, action = function()
                self.page = self.page + 1; self:_paginate(); UIManager:setDirty(self, "ui"); return true
            end }
        end
    end
end
local ButtonDialog={}
function ButtonDialog:new(args) args=args or {}; args.mode="buttons"; return Modal:new(args) end
local InputDialog={}
function InputDialog:new(args) args=args or {}; args.mode="input"; return Modal:new(args) end
local ConfirmBox={}
function ConfirmBox:new(args) args=args or {}; args.mode="confirm"; return Modal:new(args) end
local InfoMessage={}
function InfoMessage:new(args) args=args or {}; args.mode="info"; return Modal:new(args) end
local function toggleWifi(NetworkMgr, wifi_on, callback)
    if not NetworkMgr then return false end
    if not wifi_on and NetworkMgr.pending_connection then
        UIManager:show(InfoMessage:new{ text=_("A previous Wi-Fi connection attempt is still running."), duration=3 })
        return false
    end
    local status=InfoMessage:new{ text=wifi_on and _("Turning off Wi-Fi…") or _("Connecting to Wi-Fi…"), duration=0 }
    UIManager:show(status)
    local finished=false
    local function finish()
        if not finished then finished=true; status:close() end
        if callback then callback() end
    end
    local ok,result
    if wifi_on and type(NetworkMgr.disableWifi)=="function" then
        ok,result=pcall(NetworkMgr.disableWifi,NetworkMgr,finish,true)
    elseif not wifi_on and type(NetworkMgr.enableWifi)=="function" then
        NetworkMgr.wifi_toggle_long_press=false
        ok,result=pcall(NetworkMgr.enableWifi,NetworkMgr,finish,true)
    else
        ok,result=false,"Wi-Fi controls are unavailable on this device."
    end
    if not ok or result==false then
        if not finished then finished=true; status:close() end
        UIManager:show(InfoMessage:new{ text=not ok and tostring(result) or _("Wi-Fi could not be changed."), duration=4 })
        return false
    end
    return true
end
return { Modal=Modal, ButtonDialog=ButtonDialog, InputDialog=InputDialog,
    ConfirmBox=ConfirmBox, InfoMessage=InfoMessage, toggleWifi=toggleWifi }
