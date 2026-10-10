-- AppDock Draw tests: palette invariants, layered editing and bounded binary projects.
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
local OverlapGroup=Widget:extend({})
function OverlapGroup:init() self.is_overlap_group=true end
package.preload["gettext"]=function() return function(s) return s end end
package.preload["ffi/blitbuffer"]=function() return {COLOR_WHITE=1,COLOR_BLACK=2,COLOR_GRAY_8=3,ColorRGB32=function(r,g,b) return {r,g,b} end} end
package.preload["device"]=function() return {screen={getWidth=function() return 600 end,getHeight=function() return 800 end,scaleBySize=function(_,v) return v end,isColorEnabled=function() return false end}} end
package.preload["ui/font"]=function() return {getFace=function() return {} end} end
package.preload["ui/geometry"]=function() return {new=function(_,a) return a end} end
package.preload["ui/gesturerange"]=function() return {new=function(_,a) return a end} end
package.preload["ui/widget/container/inputcontainer"]=function() return Widget end
package.preload["ui/widget/container/widgetcontainer"]=function() return Widget end
package.preload["ui/widget/overlapgroup"]=function() return OverlapGroup end
package.preload["ui/widget/textwidget"]=function() return Widget end
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
local pane=app:buildPane({}, {dimen={w=600,h=800},requestRebuild=function() end,notify=function() end})
assert(pane.is_overlap_group and pane.dimen.w==600 and pane.dimen.h==800,
    "The Draw pane must position its toolbar and canvas in a screen-sized OverlapGroup")
local canvas
for _,child in ipairs(pane) do if child.app==app then canvas=child; break end end
assert(canvas and canvas.overlap_offset[1]>0 and canvas.overlap_offset[2]>0,
    "The Draw canvas must be positioned below the toolbar instead of at the top-left origin")
local first_rect
canvas:paintTo({paintRect=function(_,x,y,w,h,color) if not first_rect then first_rect={x=x,y=y,w=w,h=h,color=color} end end},canvas.overlap_offset[1],canvas.overlap_offset[2])
assert(first_rect and first_rect.x==canvas.overlap_offset[1] and first_rect.y==canvas.overlap_offset[2]
    and first_rect.color==1,
    "The first canvas paint must clear the correctly positioned drawing area to white")
print("AppDock Draw tests passed")
