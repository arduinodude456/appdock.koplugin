-- AppDock Draw: a fast, layered pixel canvas for E-Ink and color readers.
-- Project files are a compact binary format; no executable Lua is loaded.
local Blitbuffer = require("ffi/blitbuffer")
local ffi = require("ffi")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local Draw = {}
Draw.__index = Draw
local Screen = Device.screen
local MAGIC = "ADRAW1\0"
local save_sequence = 0
local Bayer = {
    { 0,48,12,60,3,51,15,63 }, { 32,16,44,28,35,19,47,31 },
    { 8,56,4,52,11,59,7,55 }, { 40,24,36,20,43,27,39,23 },
    { 2,50,14,62,1,49,13,61 }, { 34,18,46,30,33,19,47,31 },
    { 10,58,6,54,9,57,5,53 }, { 42,26,38,22,41,27,45,21 },
}
local palette = {
    {255,255,255}, {0,0,0}, {255,0,0}, {0,255,0}, {0,0,255},
}
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function scale(v) return Screen:scaleBySize(v) end
local function rgb(c)
    if Screen:isColorEnabled() then return Blitbuffer.ColorRGB32(c[1], c[2], c[3], 0xFF) end
    local y = math.floor((c[1] * 299 + c[2] * 587 + c[3] * 114) / 1000)
    return y > 127 and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
end
local function empty(width, height)
    return { width=width, height=height, pixels=ffi.new("uint8_t[?]", width*height) }
end
local function setPixel(layer, x, y, color)
    if x < 0 or y < 0 or x >= layer.width or y >= layer.height then return end
    layer.pixels[y * layer.width + x] = color
end
-- Public deterministic threshold helper; the output channel is always a pure
-- primary or zero, so the only rendered colors are RGB, black and white.
function Draw.ditherChannel(value, x, y)
    local t = Bayer[(y % 8)+1][(x % 8)+1] * 4 + 2
    return value > t and 255 or 0
end
function Draw.paletteIndex(r, g, b, x, y, enabled)
    if not enabled then
        return ((r*299 + g*587 + b*114) / 1000) >= 128 and 1 or 2
    end
    local rr, gg, bb = Draw.ditherChannel(r,x,y), Draw.ditherChannel(g,x,y), Draw.ditherChannel(b,x,y)
    if rr == 0 and gg == 0 and bb == 0 then return 2 end
    if rr == 255 and gg == 255 and bb == 255 then return 1 end
    if rr == 255 then return 3 end
    if gg == 255 then return 4 end
    return 5
end
local Canvas = InputContainer:extend{ app=nil, width=nil, height=nil, dimen=nil }
function Canvas:init()
    self.dimen = Geom:new{w=self.width,h=self.height}
    self.ges_events = {
        Paint = { GestureRange:new{ ges="pan", range=function() return self.dimen end } },
        PaintTap = { GestureRange:new{ ges="tap", range=function() return self.dimen end } },
        PaintRelease = { GestureRange:new{ ges="pan_release", range=function() return self.dimen end } },
    }
end
function Canvas:_point(ev)
    local p = ev and ev.pos
    if not p then return nil end
    local x = math.floor((p.x - (self.origin_x or 0)) * self.width / math.max(1,self.dimen.w))
    local y = math.floor((p.y - (self.origin_y or 0)) * self.height / math.max(1,self.dimen.h))
    return clamp(x,0,self.width-1), clamp(y,0,self.height-1), ev
end
function Canvas:_draw(ev, final)
    local x,y,event = self:_point(ev)
    if not x then return false end
    local app = self.app
    local brush = math.max(1, math.floor((app.brush_size or 1) * math.min(self.width/self.dimen.w,self.height/self.dimen.h) + .5))
    local color = app.tool == "eraser" and 1 or app.color
    local pressure = event and tonumber(event.pressure)
    if pressure and app.pressure_enabled then brush = math.max(1,math.floor(brush*clamp(pressure,0.1,1)+.5)) end
    if event and (event.tool == "eraser" or event.pointer_type == "eraser" or event.eraser == true) then color=1 end
    if event and (event.marker_button == true or event.stylus_button == true) then brush=math.max(brush,5) end
    if app.tool == "line" or app.tool == "rect" or app.tool == "circle" then
        if not app.start_point then app.start_point={x,y}; return true end
        if not final then return true end
        local x0,y0=app.start_point[1],app.start_point[2]
        if app.tool == "line" then
            local dx,dy=x-x0,y-y0; local n=math.max(math.abs(dx),math.abs(dy),1)
            for i=0,n do app:stamp(math.floor(x0+dx*i/n+.5),math.floor(y0+dy*i/n+.5),color,brush) end
        elseif app.tool == "rect" then
            for xx=math.min(x,x0),math.max(x,x0) do app:stamp(xx,y0,color,brush); app:stamp(xx,y,color,brush) end
            for yy=math.min(y,y0),math.max(y,y0) do app:stamp(x0,yy,color,brush); app:stamp(x,yy,color,brush) end
        else
            local radius=math.sqrt((x-x0)^2+(y-y0)^2)
            local segments=math.max(12,math.floor(radius*6))
            for i=0,segments do local a=2*math.pi*i/segments; app:stamp(math.floor(x0+math.cos(a)*radius+.5),math.floor(y0+math.sin(a)*radius+.5),color,brush) end
        end
        app.start_point=nil
    elseif app.tool == "fill" then
        app:floodFill(x,y,color)
    else
        local previous=app.last_point
        if previous then
            local dx,dy=x-previous[1],y-previous[2]; local n=math.max(math.abs(dx),math.abs(dy),1)
            for i=0,n do app:stamp(math.floor(previous[1]+dx*i/n+.5),math.floor(previous[2]+dy*i/n+.5),color,brush) end
        else app:stamp(x,y,color,brush) end
        app.last_point={x,y}
    end
    self:refreshFast()
    return true
end
function Canvas:onPaint(_,ev) return self:_draw(ev) end
function Canvas:onPaintTap(_,ev) self.app.last_point=nil; self.app.start_point=nil; return self:_draw(ev) end
function Canvas:onPaintRelease(_,ev) if ev then self:_draw(ev,true) end; self.app.last_point=nil; self.app.start_point=nil; return true end
function Canvas:paintTo(bb,x,y)
    self.origin_x,self.origin_y=x,y
    local app=self.app
    local layers=app.layers
    bb:paintRect(x,y,self.dimen.w,self.dimen.h,Blitbuffer.COLOR_WHITE)
    for py=0,self.height-1 do
        local run_color,run_start
        for px=0,self.width do
            local color_id
            if px<self.width then
                for li=#layers,1,-1 do
                    local id=layers[li].pixels[py*self.width+px]
                    if id and id~=0 then color_id=id; break end
                end
                color_id=color_id or 1
            end
            local c=color_id and palette[color_id] or nil
            local value=c and rgb(c)
            if px==0 then run_color,run_start=value,0
            elseif value~=run_color then
                local dx=x+math.floor(run_start*self.dimen.w/self.width)
                local ex=x+math.floor(px*self.dimen.w/self.width)
                bb:paintRect(dx,y+math.floor(py*self.dimen.h/self.height),math.max(1,ex-dx),math.max(1,math.ceil(self.dimen.h/self.height)),run_color)
                run_color,run_start=value,px
            end
        end
    end
end
function Canvas:refreshFast()
    if not self.origin_x or not UIManager.setDirty then return end
    if UIManager.widgetRepaint then UIManager:widgetRepaint(self,self.origin_x,self.origin_y) end
    UIManager:setDirty(nil,"fast",Geom:new{x=self.origin_x,y=self.origin_y,w=self.dimen.w,h=self.dimen.h})
    if UIManager.forceRePaint then UIManager:forceRePaint() end
    if UIManager.yieldToEPDC then UIManager:yieldToEPDC() end
end
local ToolButton=InputContainer:extend{label=nil,callback=nil,width=nil,height=nil,dimen=nil}
function ToolButton:init() self.dimen=Geom:new{w=self.width,h=self.height}; self.ges_events={TapToolButton={GestureRange:new{ges="tap",range=function() return self.dimen end}}} end
function ToolButton:onTapToolButton() if self.callback then self.callback() end; return true end
function ToolButton:paintTo(bb,x,y)
    local fg=Blitbuffer.COLOR_BLACK
    bb:paintRect(x,y,self.width,self.height,Blitbuffer.COLOR_GRAY_8)
    local t=TextWidget:new{text=self.label,face=Font:getFace("smallinfofont",scale(11)),fgcolor=fg,align="center",max_width=self.width-4}
    t:paintTo(bb,x+2,y+math.floor((self.height-scale(14))/2))
end
local function u16(n) return string.char(n%256,math.floor(n/256)%256) end
function Draw:new() return setmetatable({layers={},active=1,color=2,tool="pen",brush_size=2,color_dither=false,pressure_enabled=true},self) end
function Draw:ensure()
    if #self.layers==0 then
        local w=clamp(math.floor((Device.screen:getWidth()-scale(24))/scale(2)),64,480)
        local h=clamp(math.floor((Device.screen:getHeight()-scale(180))/scale(2)),64,640)
        self.width,self.height=w,h
        local base=ffi.new("uint8_t[?]",w*h); ffi.fill(base,w*h,1); self.layers={{name=_('Layer 1'),width=w,height=h,pixels=base}}
    end
end
function Draw:stamp(x,y,color_id,radius)
    local layer=self.layers[self.active]; if not layer then return end
    local r=math.max(0,math.floor((radius-1)/2))
    for yy=y-r,y+r do for xx=x-r,x+r do
        if (xx-x)^2+(yy-y)^2 <= r*r+math.max(1,r) then
            local pixel_color=color_id
            if self.color_dither and color_id>=3 and color_id<=5 then
                pixel_color=Draw.ditherChannel(140,xx,yy)==255 and color_id or 1
            end
            setPixel(layer,xx,yy,pixel_color)
        end
    end end
end
function Draw:floodFill(x,y,color_id)
    local layer=self.layers[self.active]; if not layer then return end
    local start=y*self.width+x; local target=layer.pixels[start]
    if target==color_id then return end
    local data=ffi.new("uint8_t[?]",self.width*self.height); ffi.copy(data,layer.pixels,self.width*self.height); local queue={start}; local head=1; data[start]=color_id
    while head<=#queue and head<=self.width*self.height do
        local at=queue[head]; head=head+1; local xx=(at-1)%self.width
        for _,n in ipairs({at-1,at+1,at-self.width,at+self.width}) do
            if n>=1 and n<=self.width*self.height and (n~=at-1 or xx>0) and (n~=at+1 or xx<self.width-1) and data[n]==target then
                data[n]=color_id; queue[#queue+1]=n
            end
        end
    end
    layer.pixels=data
end
function Draw:addLayer()
    if #self.layers>=6 then return false end
    self.layers[#self.layers+1]={name=_("Layer ")..tostring(#self.layers+1),width=self.width,height=self.height,pixels=ffi.new("uint8_t[?]",self.width*self.height)}
    self.active=#self.layers; return true
end
function Draw:nextLayer()
    if #self.layers>0 then self.active=self.active%#self.layers+1 end
end
function Draw:projectBytes()
    self:ensure()
    local out={MAGIC,u16(self.width),u16(self.height),string.char(#self.layers,self.active)}
    for _,layer in ipairs(self.layers) do out[#out+1]=ffi.string(layer.pixels,self.width*self.height) end
    return table.concat(out)
end
function Draw:loadBytes(bytes)
    if type(bytes)~="string" or #bytes < #MAGIC + 6 or bytes:sub(1,#MAGIC)~=MAGIC then return nil,_('Not an AppDock Draw project.') end
    local i=#MAGIC+1; local w=bytes:byte(i)+(bytes:byte(i+1) or 0)*256; i=i+2
    local h=bytes:byte(i)+(bytes:byte(i+1) or 0)*256; i=i+2
    local count=bytes:byte(i); local active=bytes:byte(i+1); i=i+2
    if w<1 or h<1 or w>480 or h>640 or not count or count<1 or count>6 or not active or active<1 or active>count or #bytes-i+1~=w*h*count then return nil,_('The drawing file is damaged or too large.') end
    local layers={}
    for n=1,count do
        local raw=bytes:sub(i,i+w*h-1)
        for index=1,#raw do if raw:byte(index)>5 then return nil,_('The drawing file contains an invalid color index.') end end
        local pixels=ffi.new("uint8_t[?]",w*h); ffi.copy(pixels,raw,w*h)
        layers[n]={name=_('Layer ')..n,width=w,height=h,pixels=pixels}; i=i+w*h
    end
    self.width,self.height,self.layers,self.active=w,h,layers,clamp(active or 1,1,count)
    return true
end
function Draw:saveProject()
    self:ensure()
    local dir=nil
    local ok,ds=pcall(require,"datastorage"); if ok and ds.getDataDir then dir=ds:getDataDir() end
    dir=(dir or "/tmp").."/appdock/draw"; os.execute("mkdir -p "..string.format("%q",dir))
    save_sequence=save_sequence+1
    local path=dir.."/drawing-"..os.date("%Y%m%d-%H%M%S").."-"..save_sequence..".adraw"
    local f,err=io.open(path,"wb"); if not f then return nil,err end
    f:write(self:projectBytes()); f:close(); return path
end
function Draw:projectDirectory()
    local dir="/tmp"; local ok,ds=pcall(require,"datastorage"); if ok and ds.getDataDir then dir=ds:getDataDir() end
    return dir.."/appdock/draw"
end
function Draw:loadLatestProject()
    local dir=self:projectDirectory()
    local pipe=io.popen("ls -1t "..string.format("%q",dir).."/*.adraw 2>/dev/null", "r")
    local path=pipe and pipe:read("*l"); if pipe then pipe:close() end
    if not path then return nil,_('No saved AppDock Draw project was found.') end
    local f,err=io.open(path,"rb"); if not f then return nil,err end
    local bytes=f:read("*a"); f:close()
    local ok_load,load_error=self:loadBytes(bytes)
    if not ok_load then return nil,load_error end
    return path
end
function Draw:loadPath(path)
    if type(path)~="string" or #path>4096 or not path:lower():match("%.adraw$") then return nil,_('Choose an .adraw project file.') end
    local f,err=io.open(path,"rb"); if not f then return nil,err end
    local size=f:seek("end")
    if not size or size>480*640*6+#MAGIC+6 then f:close(); return nil,_('The drawing file is too large.') end
    f:seek("set",0); local bytes=f:read("*a"); f:close()
    return self:loadBytes(bytes)
end
function Draw:exportJPEG()
    self:ensure()
    local dir="/tmp"; local ok,ds=pcall(require,"datastorage"); if ok and ds.getDataDir then dir=ds:getDataDir() end
    local base=dir.."/appdock/draw"; os.execute("mkdir -p "..string.format("%q",base))
    save_sequence=save_sequence+1
    local stem=base.."/drawing-"..os.date("%Y%m%d-%H%M%S").."-"..save_sequence
    local ppm, jpeg=stem..".ppm",stem..".jpg"
    local f,err=io.open(ppm,"wb"); if not f then return nil,err end
    f:write("P6\n",self.width," ",self.height,"\n255\n")
    for y=0,self.height-1 do for x=0,self.width-1 do
        local id=1
        for li=#self.layers,1,-1 do local v=self.layers[li].pixels[y*self.width+x]; if v and v~=0 then id=v; break end end
        local p=palette[id] or palette[1]
        local r,g,b=p[1],p[2],p[3]
        if self.color_dither then r,g,b=Draw.ditherChannel(r,x,y),Draw.ditherChannel(g,x,y),Draw.ditherChannel(b,x,y) end
        f:write(string.char(r,g,b))
    end end
    f:close()
    local pipe=io.popen("command -v ffmpeg 2>/dev/null","r"); local ffmpeg=pipe and pipe:read("*l"); if pipe then pipe:close() end
    if not ffmpeg then
        local data_dir
        local data_ok, data_storage=pcall(require,"datastorage")
        if data_ok and data_storage.getDataDir then data_dir=data_storage:getDataDir() end
        local bundled=(data_dir or "").."/appdock/tools/ffmpeg"
        local probe=io.open(bundled,"rb")
        if probe then probe:close(); ffmpeg=bundled end
    end
    if not ffmpeg then os.remove(ppm); return nil,_('JPEG export needs ffmpeg on the device.') end
    local ok=os.execute(string.format("%q -y -v error -i %q -q:v 2 %q >/dev/null 2>&1",ffmpeg,ppm,jpeg)); os.remove(ppm)
    if ok~=0 then return nil,_('JPEG export failed.') end
    return jpeg
end
function Draw:buildPane(instance,context)
    self:ensure()
    local dim=context.dimen; local w,h=dim.w,dim.h; local bar=scale(48); local margin=scale(4)
    local canvas_h=math.max(scale(60),h-bar-scale(48)-margin*3)
    local canvas_w=w-margin*2
    local canvas=Canvas:new{app=self,width=self.width,height=self.height}
    local pane=OverlapGroup:new{dimen=Geom:new{w=w,h=h},allow_mirroring=false}
    local controls={
        {_("Pen"),function() self.tool="pen" end},{_("Eraser"),function() self.tool="eraser" end},
        {_("Line"),function() self.tool="line" end},{_("Rect"),function() self.tool="rect" end},
        {_("Fill"),function() self.tool="fill" end},{_("Circle"),function() self.tool="circle" end},
        {_("Color"),function() self.color=self.color%5+1 end},
        {_("Dither"),function() self.color_dither=not self.color_dither end},
        {_("Brush"),function() local sizes={1,2,4,7}; for i,v in ipairs(sizes) do if v==self.brush_size then self.brush_size=sizes[i%#sizes+1]; return end end; self.brush_size=1 end},
        {_("Layer +"),function() self:addLayer() end},{_("Layer →"),function() self:nextLayer() end},{_("Load"),function() local path,err=self:loadLatestProject(); context.notify{title=_("Draw"),message=path or tostring(err)} end},{_("Save"),function() local path,err=self:saveProject(); context.notify{title=_("Draw"),message=path or tostring(err)} end},
        {_("JPEG"),function() local path,err=self:exportJPEG(); context.notify{title=_("Draw"),message=path or tostring(err)} end},
    }
    local cols=math.max(1,math.floor(w/scale(76))); local bw=math.floor((w-margin*2)/cols); local bh=scale(34)
    for i,item in ipairs(controls) do
        local x=margin+((i-1)%cols)*bw; local y=margin+math.floor((i-1)/cols)*bh
        if y+bh<=bar+scale(36) then pane[#pane+1]=ToolButton:new{label=item[1],callback=function() item[2](); context.requestRebuild("ui") end,width=bw-scale(3),height=bh-scale(3),overlap_offset={x,y}} end
    end
    local cy=bar+scale(38)
    canvas.dimen=Geom:new{x=margin,y=cy,w=canvas_w,h=canvas_h}
    canvas.ges_events.Paint[1].range=function() return canvas.dimen end
    canvas.ges_events.PaintTap[1].range=function() return canvas.dimen end
    canvas.ges_events.PaintRelease[1].range=function() return canvas.dimen end
    canvas.overlap_offset={margin,cy}; pane[#pane+1]=canvas
    pane.onDeactivate=function() end
    return pane
end
Draw.Canvas=Canvas
return Draw
