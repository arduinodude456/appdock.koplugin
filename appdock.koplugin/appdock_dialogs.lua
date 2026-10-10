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
local Screen = Device.screen
local function scale(n) return Screen:scaleBySize(n) end
local function clamp(n, lo, hi) return math.max(lo, math.min(hi, n)) end
local function textWidget(text, width, size, bold)
    return TextWidget:new{
        text = tostring(text or ""), face = Font:getFace(bold and "cfont" or "smallinfofont", scale(size)),
        fgcolor = Blitbuffer.COLOR_BLACK, bold = bold or false, padding = 0, max_width = width,
    }
end
local Modal = InputContainer:extend{ mode=nil, title=nil, text=nil, buttons=nil, duration=nil }
function Modal:init()
    self.mode = self.mode or "buttons"
    if self.mode == "input" and not self.text then self.text = self.description end
    local screen = Screen.getSize and Screen:getSize()
        or { w=(Screen.getWidth and Screen:getWidth() or Screen.width or 600),
            h=(Screen.getHeight and Screen:getHeight() or Screen.height or 800) }
    self.screen_w, self.screen_h = screen.w, screen.h
    self.dimen = Geom:new{ x=0, y=0, w=screen.w, h=screen.h }
    self.margin = scale(16)
    self.card_w = math.min(screen.w - self.margin * 2, scale(560))
    self.card_x = math.floor((screen.w - self.card_w) / 2)
    self.max_card_h = screen.h - self.margin * 2
    self.title_h = self.title and scale(42) or scale(14)
    self.body_widget = self.text and textWidget(self.text, self.card_w - scale(36), 14, false) or nil
    local body_dims
    if self.body_widget and self.body_widget.getSize then
        local ok,dims=pcall(self.body_widget.getSize,self.body_widget)
        if ok then body_dims=dims end
    end
    self.body_h = self.body_widget and math.min(body_dims and body_dims.h or scale(48), math.floor(self.max_card_h * 0.42)) or 0
    self.input_h = self.mode == "input" and scale(56) or 0
    self.row_h = scale(46)
    self.footer_h = scale(52)
    self.top_h = self.margin + self.title_h + (self.body_h > 0 and scale(12) + self.body_h or 0) + scale(10)
    self.rows = self:_normalizeRows(self.buttons or {})
    if self.mode == "confirm" then
        self.rows = { {
            { text=self.ok_text or _("OK"), callback=self.ok_callback, is_default=true },
            { text=self.cancel_text or _("Cancel"), callback=self.cancel_callback },
        } }
    elseif self.mode == "info" then
        self.rows = { { { text=_("Done"), callback=function() self:close() end } } }
    end
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
        if #cells > 0 then normalized[#normalized+1] = cells end
    end
    return normalized
end
function Modal:_paginate()
    local fixed = self.top_h + self.footer_h + scale(14)
    self.visible_rows = math.max(1, math.floor((self.max_card_h-fixed)/self.row_h))
    self.pages = math.max(1, math.ceil(#self.rows/self.visible_rows))
    self.page = clamp(self.page or 1, 1, self.pages)
    self.card_h = math.min(self.max_card_h, fixed + math.min(#self.rows,self.visible_rows)*self.row_h)
    self.card_y = math.floor((self.screen_h-self.card_h)/2)
end
function Modal:getInputText() return self.input_value or "" end
function Modal:setInputText(value)
    self.input_value = tostring(value or "")
    self.input = self.input_value
end
function Modal:onShowKeyboard()
    if self.appdock_keyboard_attached then return false end
    local Keyboard = require("appdock_keyboard")
    Keyboard.attach(self, { title=self.title, placeholder=self.input_hint, numeric_only=self.input_type=="number", secure=self.secure })
    return self:onShowKeyboard()
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
function Modal:_paintText(bb, text, x, y, width, size, bold)
    local widget=textWidget(text,width,size,bold)
    local dims=widget.getSize and widget:getSize() or { h=scale(size+4) }
    widget:paintTo(bb,x,y)
    return dims.h
end
function Modal:paintTo(bb, x, y)
    x,y=0,0
    self._hits={}
    -- A quiet full-screen veil and a high-contrast rounded-card treatment.
    bb:paintRect(0,0,self.screen_w,self.screen_h,Blitbuffer.COLOR_WHITE)
    bb:paintRect(self.card_x,self.card_y,self.card_w,self.card_h,Blitbuffer.COLOR_WHITE)
    local border=math.max(1,scale(2))
    bb:paintRect(self.card_x,self.card_y,self.card_w,border,Blitbuffer.COLOR_BLACK)
    bb:paintRect(self.card_x,self.card_y+self.card_h-border,self.card_w,border,Blitbuffer.COLOR_BLACK)
    bb:paintRect(self.card_x,self.card_y,border,self.card_h,Blitbuffer.COLOR_BLACK)
    bb:paintRect(self.card_x+self.card_w-border,self.card_y,border,self.card_h,Blitbuffer.COLOR_BLACK)
    local pad=scale(18)
    local text_y=self.card_y+self.margin
    if self.title then self:_paintText(bb,self.title,self.card_x+pad,text_y,self.card_w-pad*2,18,true) end
    local y0=self.card_y+self.top_h
    if self.mode=="input" then
        local input_y=y0
        local input_h=scale(48)
        bb:paintRect(self.card_x+pad,input_y,self.card_w-pad*2,input_h,Blitbuffer.COLOR_WHITE)
        bb:paintRect(self.card_x+pad,input_y,self.card_w-pad*2,scale(1),Blitbuffer.COLOR_BLACK)
        bb:paintRect(self.card_x+pad,input_y+input_h-scale(1),self.card_w-pad*2,scale(1),Blitbuffer.COLOR_BLACK)
        self:_paintText(bb,(self.input_value~="" and self.input_value or self.input_hint or "Tap to enter text"),self.card_x+pad+scale(6),input_y+scale(12),self.card_w-pad*2-scale(12),14,false)
        self._hits[#self._hits+1]={x=self.card_x+pad,y=input_y,w=self.card_w-pad*2,h=input_h,input=true}
    elseif self.body_widget then
        local body_y=self.card_y+self.margin+self.title_h
        self.body_widget:paintTo(bb,self.card_x+pad,body_y)
    end
    local start=(self.page-1)*self.visible_rows+1
    local finish=math.min(#self.rows,start+self.visible_rows-1)
    local rows_drawn=0
    local rows_y=y0+self.input_h
    for index=start,finish do
        local row=self.rows[index]; local row_y=rows_y+rows_drawn*self.row_h
        local cols=#row>1 and 2 or 1
        for col,button in ipairs(row) do
            local gap=scale(6)
            local inner_w=self.card_w-pad*2
            local w=cols==1 and inner_w or math.floor((inner_w-gap)/2)
            local bx=self.card_x+pad+(cols==1 and 0 or (col-1)*(w+gap))
            local bg=(button.is_default or button.is_enter_default) and Blitbuffer.COLOR_GRAY_8 or Blitbuffer.COLOR_WHITE
            bb:paintRect(bx,row_y,w,self.row_h-scale(4),bg)
            bb:paintRect(bx,row_y,w,scale(1),Blitbuffer.COLOR_BLACK)
            bb:paintRect(bx,row_y+self.row_h-scale(5),w,scale(1),Blitbuffer.COLOR_BLACK)
            local title=tostring(button.text or "")
            self:_paintText(bb,title,bx+scale(7),row_y+scale(12),w-scale(14),13,true)
            self._hits[#self._hits+1]={x=bx,y=row_y,w=w,h=self.row_h,button=button}
        end
        rows_drawn=rows_drawn+1
    end
    if self.pages>1 then
        local footer_y=self.card_y+self.card_h-self.footer_h
        local label=string.format(_("Page %d of %d"),self.page,self.pages)
        self:_paintText(bb,label,self.card_x+pad,footer_y+scale(15),self.card_w-pad*2,12,false)
        if self.page>1 then self._hits[#self._hits+1]={x=self.card_x+pad,y=footer_y,w=scale(60),h=self.footer_h,action=function() self.page=self.page-1; UIManager:setDirty(self,"ui"); return true end} end
        if self.page<self.pages then self._hits[#self._hits+1]={x=self.card_x+self.card_w-pad-scale(60),y=footer_y,w=scale(60),h=self.footer_h,action=function() self.page=self.page+1; UIManager:setDirty(self,"ui"); return true end} end
    end
    for _, event in ipairs(self.ges_events.TapAppDockModal) do event.range.x,event.range.y,event.range.w,event.range.h=0,0,self.screen_w,self.screen_h end
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
