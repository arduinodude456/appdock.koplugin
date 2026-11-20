-- DockAI pane integration test using KOReader-shaped widget stubs and proxy stub.
package.path=(os.getenv("APPDOCK_PLUGIN_DIR") or "./appdock.koplugin/").."?.lua;"..package.path
package.cpath=package.cpath..";/usr/lib/x86_64-linux-gnu/lua/5.1/?.so"
local json=require("cjson")
local Base={}; Base.__index=Base
function Base:extend(t) t=t or {}; t.__index=t; return setmetatable(t,{__index=self}) end
function Base:new(t) local o=setmetatable(t or {},self); if o.init then o:init() end; return o end
function Base:getSize() if self.dimen then return {w=self.dimen.w,h=self.dimen.h} end; return {w=12*#(self.text or "x"),h=20} end
function Base:paintTo() end
local function class(name,extra) local c=Base:extend(extra or {}); package.preload[name]=function() return c end; return c end
class("ui/widget/widget"); class("ui/widget/container/widgetcontainer"); class("ui/widget/container/framecontainer"); class("ui/widget/container/inputcontainer"); class("ui/widget/overlapgroup"); class("ui/widget/textwidget"); class("ui/geometry"); class("ui/gesturerange")
local scrolls={}; local Scroll=class("ui/widget/scrollhtmlwidget"); function Scroll:init() scrolls[#scrolls+1]=self end
package.preload["ui/font"]=function() return {getFace=function(_,n,s) return {name=n,size=s} end} end
package.preload["device"]=function() return {screen={scaleBySize=function(_,v) return v end}} end
package.preload["ffi/blitbuffer"]=function() return {COLOR_BLACK=0,COLOR_WHITE=255,COLOR_DARK_GRAY=85,Color8=function(v) return v end} end
local scheduled,shown={},{}
package.preload["ui/uimanager"]=function() return {scheduleIn=function(_,d,f) scheduled[#scheduled+1]=f end,nextTick=function(_,f) f() end,show=function(_,w) shown[#shown+1]=w end,close=function() end} end
local keyboards={}
package.preload["appdock_keyboard"]=function() return {new=function(_,t) keyboards[#keyboards+1]=t; return t end} end
for _,n in ipairs({"ui/widget/buttondialog","ui/widget/infomessage","ui/widget/confirmbox"}) do package.preload[n]=function() return {new=function(_,t) t.is_dialog=true; return t end} end end
local identity={account_id="123e4567-e89b-42d3-a456-426614174000",device_id="tbs_abcdefghijklmnopqrs",device_secret=string.rep("S",40),publishable_key="sb_publishable_test"}
package.preload["appdock_tbs_account"]=function() return {get=function() return identity end} end
local usage={day_used=0,week_used=0,day_limit=25,week_limit=100,blocked=nil}
local replies=0
local function transport(url,headers,body)
  local request=json.decode(body)
  if request.action=="usage" then return 200,json.encode({usage=usage}) end
  if request.action=="chat" then replies=replies+1; usage.day_used=usage.day_used+1; usage.week_used=usage.week_used+1; return 200,json.encode({reply="Hello **there**",usage=usage}) end
  if request.action=="add_key" then return 200,json.encode({added=true}) end
  return 400,"{}"
end
local DockAI=require("appdock_dockai")
local storedata={}; local store={readSetting=function(_,k) return storedata[k] end,saveSetting=function(_,k,v) storedata[k]=v end,flush=function() end}
local ai=DockAI:new({}, {store=store,json=json,transport=transport,now=os.time}); ai.german=false
local context={dimen={w=600,h=800},requestRebuild=function() end,host={}}
local instance={}
local function walk(pane,visit) for _,layer in ipairs(pane[1]) do visit(layer) end end
local function texts(pane) local found={}; walk(pane,function(l) if l.text then found[#found+1]=l.text end end); return found end
local function has(list,needle) for _,t in ipairs(list) do if t:find(needle,1,true) then return true end end return false end
local pane=ai:buildPane(instance,context)
assert(has(texts(pane),"Today 0/25 · Week 0/100 messages"),"Server allowance appears in chat pane")
local chips={}; walk(pane,function(l) if l.callback and l.width and l.height>40 and l.height<50 then chips[#chips+1]=l end end)
assert(#chips>=3,"Suggestion chips are tappable")
chips[1].callback(); local state=instance.dockai_state
assert(state.busy and #state.chat==1,"Sending paints thinking state")
scheduled[1]()
assert(not state.busy and #state.chat==2 and state.chat[2].content=="Hello **there**" and replies==1,"Proxy reply is added")
assert(ai:usage().day_used==1 and ai:usage().week_used==1,"Usage display reflects server response")
pane=ai:buildPane(instance,context)
assert(#scrolls==1 and scrolls[1].html_body:find("<b>there</b>",1,true) and has(texts(pane),"Today 1/25"),"Transcript and quota redraw")
usage.day_used=25; usage.blocked="day"; pane=ai:buildPane(instance,context)
assert(has(texts(pane),"Daily limit reached (25/25)"),"Limit reached state is shown")
local send={}; walk(pane,function(l) if l.callback and l.width==42 then send[#send+1]=l end end)
local before=replies; send[1].callback(); assert(replies==before and #keyboards==0,"Client blocks obvious over-limit request")
local rows=ai:settingsRows(context); assert(rows[#rows].title=="Admin: add API key" and rows[#rows].subtitle:find("cannot view/remove",1,true),"Admin controls are add-only")
rows[#rows].callback(); assert(shown[#shown].is_dialog and #shown[#shown].buttons==2,"Admin dialog has no listing/removal controls")
shown[#shown].buttons[1][1].callback(); assert(keyboards[#keyboards].secure==true,"Admin password keyboard is secure")
keyboards[#keyboards].on_submit("passphrase")
assert(keyboards[#keyboards].secure==true,"API key keyboard is also secure")
keyboards[#keyboards].on_submit("gsk_AAAAAAAAAAAAAAAAAAAAAAAA")
assert(storedata.keys==nil,"No key is persisted locally")
print("dockai-pane-proxy-ok")
