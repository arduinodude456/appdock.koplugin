-- DockAI proxy boundary and markdown regression tests.
package.path = (os.getenv("APPDOCK_PLUGIN_DIR") or "./appdock.koplugin/") .. "?.lua;" .. package.path
local json = require("cjson")
local session = { account_id="123e4567-e89b-42d3-a456-426614174000", device_id="tbs_abcdefghijklmnopqrs", device_secret=string.rep("S", 40), publishable_key="sb_publishable_test" }
package.preload["appdock_tbs_account"] = function() return { get = function() return session end } end
local DockAI = require("appdock_dockai")
local function store()
  local data = {}
  return { readSetting=function(_,k) return data[k] end, saveSetting=function(_,k,v) data[k]=v end, flush=function() end, data=data }
end
local calls, usage = {}, { day_used=0, week_used=0, day_limit=25, week_limit=100, day_resets_at="2026-11-21T00:00:00Z", week_resets_at="2026-11-23T00:00:00Z", blocked=nil }
local function transport(url, headers, body)
  local req=json.decode(body); calls[#calls+1]={url=url,headers=headers,body=req}
  if req.action=="usage" then return 200,json.encode({usage=usage}) end
  if req.action=="add_key" then
    if req.admin_password=="right-password" then return 200,json.encode({added=true}) end
    return 401,json.encode({error={code="admin_denied"}})
  end
  if req.action=="chat" then
    usage.day_used=usage.day_used+1; usage.week_used=usage.week_used+1
    return 200,json.encode({reply="Hello **world**",usage=usage})
  end
  return 400,"{}"
end
local localStore=store()
local ai=DockAI:new({}, {store=localStore,transport=transport,json=json,now=function() return 1794996000 end})
ai.german=false
local history={
  {role="user",content="one"},{role="assistant",content="answer one"},
  {role="user",content="two"},{role="assistant",content="answer two"},
  {role="user",content="three"},{role="assistant",content="answer three"},
  {role="user",content="four"},{role="assistant",content="answer four"},
}
assert(ai:addMemory("User prefers concise answers"),"A valid DockAI memory is saved")
local contextMessages=ai:contextMessages(history)
assert(#contextMessages==4 and contextMessages[1].role=="user","Model context starts at the last complete user turn")
assert(contextMessages[1].content:find("Saved memories about the user",1,true),"Saved memories are included in the first context message")
assert(not contextMessages[1].content:find("one",1,true),"Older turns are omitted from bounded model context")
local legacyStore=store()
legacyStore.data.chat={{role="user",content="legacy question"},{role="assistant",content="legacy answer"}}
local legacyAI=DockAI:new({}, {store=legacyStore,transport=transport,json=json,now=function() return 1794996000 end})
local migrated=legacyAI:loadChats()
assert(#migrated==1 and migrated[1].messages[1].content=="legacy question","Legacy single chat migrates into the new chat list")
assert(legacyStore.data.chat==nil and legacyStore.data.chats[1].id==migrated[1].id,"Migration persists the new format and clears the old setting")
local html=DockAI.markdownToHtml("# Title\nHello **bold** and `x<y` and *it*\n\n- one\n- two\n\n1. first\n2. second\n\n```lua\nlocal a = 1 < 2\n```")
assert(html:find("<p><b>Title</b></p>",1,true) and html:find("<b>bold</b>",1,true) and html:find("<i>it</i>",1,true))
assert(html:find("<code>x&lt;y</code>",1,true) and html:find("<ul>",1,true) and html:find("<ol>",1,true))
assert(not DockAI.markdownToHtml("<script>x</script>"):find("<script>",1,true))

ai:refreshUsage()
assert(ai:usage().day_used==0 and ai:usage().day_limit==25 and ai:usage().week_limit==100,"Quota display comes from server response")
local answer,err=ai:complete({{role="user",content="hi"}})
assert(answer=="Hello **world**" and not err,"Chat returns proxy reply")
local call=calls[#calls]
assert(call.url==DockAI.PROXY_ENDPOINT and call.headers.apikey=="sb_publishable_test")
assert(call.headers["x-tbs-device-id"]==session.device_id and call.headers["x-tbs-device-secret"]==session.device_secret)
assert(call.body.action=="chat" and call.body.messages[1].role=="user" and call.body.model==DockAI.DEFAULT_MODEL)
assert(ai:usage().day_used==1 and ai:usage().week_used==1,"Proxy's usage snapshot updates local display")
assert(#ai:keys()==0 and ai:removeKey(1)==false,"Keys cannot be viewed or removed from the client")
assert(ai:addKey("gsk_AAAAAAAAAAAAAAAAAAAAAAAA","wrong-password")==false,"Wrong password is rejected by server")
assert(ai:addKey("gsk_AAAAAAAAAAAAAAAAAAAAAAAA","right-password")==true,"Admin can add a key through the server")
local admin=calls[#calls]
assert(admin.body.action=="add_key" and admin.body.admin_password=="right-password" and admin.body.api_key=="gsk_AAAAAAAAAAAAAAAAAAAAAAAA")
assert(localStore.data.keys==nil,"API key is not stored locally")
usage.day_used=25; usage.blocked="day"
ai:refreshUsage(true)
assert(ai:usage().blocked=="day" and ai:limitText():find("Daily limit reached",1,true),"Server daily limit is presented")
local before=#calls
session.device_secret=""
local noauth,autherr=ai:complete({{role="user",content="hello"}})
assert(noauth==nil and autherr=="auth_required" and #calls==before,"No TBS device credentials means no proxy call")
print("dockai-proxy-ok")
