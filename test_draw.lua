-- AppDock Draw tests: palette invariants, layered editing, bounded binary
-- projects and the touch editing model of the paint-program interface.
local ffi = require("ffi")
local plugin_dir = os.getenv("APPDOCK_PLUGIN_DIR") or "/home/ubuntu/appdock.koplugin/appdock.koplugin/"
local function class(parent)
    local c={}; c.__index=c
    setmetatable(c,{__index=parent})
    function c:extend(fields) fields=fields or {}; fields.__index=fields; setmetatable(fields,{__index=self}); return fields end
    function c:new(args) local o=setmetatable(args or {},self); if o.init then o:init() end; return o end
    return c
end
local Widget=class()
function Widget:paintTo() end
local OverlapGroup=Widget:extend({})
function OverlapGroup:init() self.is_overlap_group=true end
local color_enabled = false
ffi.cdef[[
typedef struct {
    uint8_t red;
    uint8_t green;
    uint8_t blue;
    uint8_t alpha;
} AppDockDrawTestColor;
]]
local ColorRGB32 = ffi.metatype("AppDockDrawTestColor", {
    __eq = function(self, other)
        return self.red == other.red and self.green == other.green
            and self.blue == other.blue and self.alpha == other.alpha
    end,
})
package.preload["gettext"]=function() return function(s) return s end end
package.preload["ffi/blitbuffer"]=function() return {COLOR_WHITE=1,COLOR_BLACK=2,COLOR_GRAY_8=3,COLOR_LIGHT_GRAY=4,ColorRGB32=function(r,g,b,a) return ColorRGB32(r,g,b,a or 0xFF) end} end
package.preload["device"]=function() return {screen={getSize=function() return {w=600,h=800} end,scaleBySize=function(_,v) return v end,isColorEnabled=function() return color_enabled end}} end
package.preload["ui/geometry"]=function() return {new=function(_,a) return a end} end
package.preload["ui/gesturerange"]=function() return {new=function(_,a) return a end} end
package.preload["ui/font"]=function() return {getFace=function(_,name,size) return {name=name,size=size or 12} end} end
package.preload["ui/widget/textwidget"]=function()
    local Text=Widget:extend({})
    function Text:getSize()
        local size=self.face and self.face.size or 12
        return {w=#(self.text or "")*math.floor(size*.5),h=size}
    end
    function Text:setText(text) self.text=text end
    return Text
end
package.preload["ui/widget/container/inputcontainer"]=function() return Widget end
package.preload["ui/widget/container/widgetcontainer"]=function() return Widget end
package.preload["ui/widget/overlapgroup"]=function() return OverlapGroup end
package.preload["ui/uimanager"]=function() return {} end
local Draw=dofile(plugin_dir.."appdock_draw.lua")
for _,v in ipairs({0,1,127,254,255}) do
    local c=Draw.ditherChannel(v,3,5)
    assert(c==0 or c==255,"ordered dithering must emit binary channel values only")
end
assert(Draw.ditherChannel(0,0,0)==0 and Draw.ditherChannel(255,0,0)==255,"extremes are stable")
for r=0,255,17 do for g=0,255,17 do for b=0,255,17 do
    local id=Draw.paletteIndex(r,g,b,7,3,true)
    assert(id>=1 and id<=5,"the color reducer must use only white, black, red, green or blue")
end end end
local app=Draw:new(); app.width,app.height=12,8
local base=ffi.new("uint8_t[?]",96); ffi.fill(base,96,1)
app.layers={{name="Layer 1",width=12,height=8,pixels=base}}
assert(app:addLayer() and #app.layers==2 and app.active==2,"a new transparent layer must become active")
app:stamp(4,3,3,1)
assert(app.layers[2].pixels[3*12+4]==3,"brush writes to the active layer")
app:floodFill(0,0,2)
assert(app.layers[2].pixels[0]==2 and app.layers[2].pixels[3*12+4]==3,"fill replaces only the connected region")
local bytes=app:projectBytes()
local restored=Draw:new()
assert(restored:loadBytes(bytes),"a well-formed editable drawing must load")
assert(restored.width==12 and restored.height==8 and #restored.layers==2 and restored.active==2,"project metadata and layer count round-trip")
assert(restored.layers[2].pixels[3*12+4]==3,"layer pixels round-trip exactly")
local broken,err=restored:loadBytes("ADRAW1\0\1")
assert(not broken and type(err)=="string","truncated project files must be rejected safely")
assert(not restored:loadBytes("not a drawing"),"unrecognized files must be rejected")

----------------------------------------------------------------
-- Undo/redo and tools
----------------------------------------------------------------

app=Draw:new(); app.width,app.height=12,8
local canvas_base=ffi.new("uint8_t[?]",96); ffi.fill(canvas_base,96,1)
app.layers={{name="Layer 1",width=12,height=8,pixels=canvas_base,empty=true}}
assert(app:setTool("line") and app.tool=="line","a known tool must be selectable")
assert(not app:setTool("unknown"),"an unknown tool must be rejected")
assert(app:cycleBrush(1)==4 and app.brush_size==4,"the brush size must step up through the presets")
assert(app:cycleBrush(-1)==2 and app.brush_size==2,"the brush size must step back down")
assert(app:cycleBrush(-1)==1 and app:cycleBrush(-1)==1,"the brush size must stay within its bounds")
assert(app:cycleBrush(1)==2 and app:cycleBrush(1)==4 and app:cycleBrush(1)==7 and app:cycleBrush(1)==7,
    "the brush size must stop at the largest preset")

app:pushHistory()
app:stamp(2,2,2,1)
assert(app.layers[1].pixels[2*12+2]==2,"the stroke must reach the active layer")
assert(app:undo(),"undo must report success")
assert(app.layers[1].pixels[2*12+2]==1,"undo must restore the pixel")
assert(app:redo(),"redo must report success")
assert(app.layers[1].pixels[2*12+2]==2,"redo must reapply the pixel")
assert(not app:redo(),"an empty redo stack must report nothing to redo")

app:pushHistory()
app:stamp(5,5,3,1)
app:undo()
app:pushHistory()
app:stamp(6,6,4,1)
assert(not app:redo(),"a fresh edit must drop the redo branch")
assert(app.layers[1].pixels[6*12+6]==4,"the new edit must stay")

app:clear()
assert(app.layers[1].pixels[2*12+2]==1,"clearing must empty the active layer")
assert(app:undo() and app.layers[1].pixels[2*12+2]==2,"clearing must be undoable")
assert(app.history and #app.history <= 8,"the undo history must stay bounded")

assert(app:statusText():find("Line",1,true) and app:statusText():find("Layer",1,true),
    "the status line must name the active tool and layer")

----------------------------------------------------------------
-- Pane
----------------------------------------------------------------

local pane=app:buildPane({}, {dimen={w=600,h=800},requestRebuild=function() end,notify=function() end})
assert(pane.is_overlap_group and pane.dimen.w==600 and pane.dimen.h==800,
    "The Draw pane must position its toolbar and canvas in a screen-sized OverlapGroup")
local canvas,pen,chips,active_tool_button
local strip_symbols={}
for _,child in ipairs(pane) do
    if child.app==app then canvas=child end
    if child.symbol=="pen" then pen=child end
    if child.symbol=="trash" then chips=child end
    if child.symbol==app.tool then active_tool_button=child end
    if child.symbol and child.ges_events and child.ges_events.TapTool
        and child.overlap_offset and child.overlap_offset[2]==6 then
        strip_symbols[child.symbol]=true
    end
end
assert(canvas and canvas.overlap_offset[1]>0 and canvas.overlap_offset[2]>0,
    "The Draw canvas must be positioned below the toolbar instead of at the top-left origin")
assert(pen,"The Draw pane must construct one icon button per tool")
assert(active_tool_button and active_tool_button.active==true,
    "The selected tool must be highlighted in the tool strip")
for _,symbol in ipairs({"pen","eraser","line","rect","circle","fill","undo","redo","refresh"}) do
    assert(strip_symbols[symbol],"The tool strip must offer a "..symbol.." button")
end
assert(chips and chips.ges_events.TapChip,"The action bar must offer actionable chips")
pen:paintTo({paintRect=function() end},11,57)
assert(pen.ges_events.TapTool[1].range.x==11 and pen.ges_events.TapTool[1].range.y==57,
    "Toolbar hit geometry must follow its actual screen-space paint coordinates")
app.tool="eraser"
assert(pen:onTapTool() and app.tool=="pen",
    "The Draw tool button must still invoke its tool action")
assert(app:statusText():find("Pen",1,true),"Selecting a tool must update the status line")

local swatch
for _,child in ipairs(pane) do
    if child.ges_events and child.ges_events.TapSwatch and child.color_id==3 then swatch=child end
end
assert(swatch,"The options row must offer a swatch per palette color")
assert(swatch:onTapSwatch() and app.color==3,"A swatch must select its color")

local first_rect
local paint_x,paint_y=13,153
canvas:paintTo({paintRect=function(_,x,y,w,h,color) if not first_rect then first_rect={x=x,y=y,w=w,h=h,color=color} end end},paint_x,paint_y)
assert(first_rect and first_rect.x==paint_x and first_rect.y==paint_y and first_rect.color==1,
    "The first canvas paint must clear the correctly positioned drawing area to white")
local hit_range=canvas.ges_events.Paint[1].range()
assert(hit_range.x==paint_x and hit_range.y==paint_y,
    "Canvas pan/tap gesture bounds must follow the absolute paint position")
assert(canvas.ges_events.PaintTouch and canvas.ges_events.PaintRelease,
    "The canvas must receive the finger press and release of a stroke")

----------------------------------------------------------------
-- Touch editing model
----------------------------------------------------------------

-- Screen-space press for a given canvas pixel: the canvas maps its source
-- pixels onto the pane, so tests must convert the same way the widget does.
local function press(sx,sy)
    local x=canvas.origin_x+math.floor((sx+.5)*canvas.dimen.w/app.width)
    local y=canvas.origin_y+math.floor((sy+.5)*canvas.dimen.h/app.height)
    return nil,{pos={x=x,y=y}}
end
app.tool="pen"; app.color=2; app.brush_size=1
app:clear()
assert(canvas:onPaintTouch(press(3,2)),"a finger press must start a stroke")
assert(app.layers[app.active].pixels[2*app.width+3]==2,
    "The first touch of a stroke must already paint, instead of losing the first segment")
canvas:onPaint(press(6,2))
assert(app.layers[app.active].pixels[2*app.width+5]==2,"dragging must continue the stroke")
canvas:onPaintRelease(press(6,2))
assert(app.stroke==nil,"lifting the finger must end the stroke")
assert(app:undo(),"a completed stroke must be undoable as one step")
assert(app.layers[app.active].pixels[2*app.width+3]==1,"undo must remove the whole stroke")

app.tool="fill"
local fill_base=app.layers[app.active].pixels
canvas:onPaintTouch(press(0,0))
assert(app.fill_gesture==true,"The fill tool must run once per gesture")
local filled=app.layers[app.active].pixels
canvas:onPaint(press(4,4))
assert(app.layers[app.active].pixels==filled,"A panning finger must not re-flood the region")
canvas:onPaintRelease(press(4,4))
assert(app.fill_gesture==nil,"Releasing the finger must end the fill gesture")
assert(fill_base~=filled,"The fill must have replaced the layer pixels")

app.tool="rect"
canvas:onPaintTouch(press(1,1))
canvas:onPaint(press(5,5))
assert(app.stroke~=nil,"A shape tool must keep its stroke while the finger moves")
canvas:onPaintRelease(press(5,5))
assert(app.stroke==nil,"A shape tool must commit when the finger lifts")
assert(app.layers[app.active].pixels[1*app.width+1]==2,"The committed rectangle must reach the canvas")

local region_rects={}
canvas:paintRegionTo({paintRect=function(_,x,y,w,h) region_rects[#region_rects+1]={x=x,y=y,w=w,h=h} end},paint_x,paint_y,2,3,4,3)
assert(#region_rects>0,"A partial repaint must paint the requested region")
local region_rows,total_width={},0
for _,rect in ipairs(region_rects) do
    region_rows[rect.y]=true
    total_width=total_width+rect.w
    assert(rect.x>=paint_x,"A partial repaint must start at the canvas origin")
end
local row_count=0
for _ in pairs(region_rows) do row_count=row_count+1 end
assert(row_count==1,"A partial repaint must touch only the requested canvas row")
assert(total_width<canvas.dimen.w,
    "A partial repaint must cover less than the full canvas width instead of repainting everything")

color_enabled = true
local color_painted, color_error = pcall(canvas.paintTo, canvas, { paintRect = function() end }, paint_x, paint_y)
color_enabled = false
assert(color_painted, "A color canvas must not compare a BlitBuffer ColorRGB32 value with nil: " .. tostring(color_error))
;(function()
    local device = require("device")
    local old_size, old_scale = device.screen.getSize, device.screen.scaleBySize
    device.screen.getSize = function() return { w = 0, h = 0 } end
    device.screen.scaleBySize = function() return nil end
    local guarded = Draw:new()
    local started, guarded_pane = pcall(guarded.buildPane, guarded, {}, { dimen = { w = 0, h = 0 } })
    assert(started and guarded_pane and guarded.width >= 64 and guarded.height >= 64,
        "Draw must use bounded fallback dimensions when display scale or size is not ready")
    device.screen.getSize, device.screen.scaleBySize = old_size, old_scale
end)()
print("AppDock Draw tests passed")