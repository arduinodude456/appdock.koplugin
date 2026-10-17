-- Suspend integration: no network activity, selected renderer, legacy fallback.
local plugin_dir = os.getenv("APPDOCK_PLUGIN_DIR") or "./appdock.koplugin/"
package.path = plugin_dir .. "?.lua;" .. package.path
local function class(base)
    local c = {}; c.__index = c; setmetatable(c, { __index = base })
    function c:extend(child)
        local result = class(self)
        for k, v in pairs(child or {}) do result[k] = v end
        return result
    end
    function c:new(args)
        local result = setmetatable(args or {}, self)
        if result.init then result:init() end
        return result
    end
    return c
end
local Widget = class()
local shown, closed, dirty = {}, {}, {}
package.preload["ui/uimanager"] = function() return {
    show = function(_, w) shown[#shown + 1] = w end,
    close = function(_, w) closed[#closed + 1] = w; if w.onCloseWidget then w:onCloseWidget() end end,
    setDirty = function(_, w, kind) dirty[#dirty + 1] = kind end,
} end
package.preload["gettext"] = function() return function(s) return s end end
package.preload["device"] = function() return { screen = {
    getWidth = function() return 600 end, getHeight = function() return 800 end,
    scaleBySize = function(_, n) return n end,
} } end
package.preload["ffi/blitbuffer"] = function() return { COLOR_BLACK = "black", COLOR_WHITE = "white" } end
package.preload["ui/font"] = function() return { getFace = function(_, name, size) return { name=name, size=size } end } end
for _, name in ipairs({ "ui/widget/container/centercontainer", "ui/widget/container/framecontainer",
    "ui/geometry", "ui/widget/textwidget", "ui/widget/verticalgroup", "ui/widget/verticalspan",
    "ui/widget/container/widgetcontainer" }) do
    package.preload[name] = function() return Widget end
end
local owner = { settings = { sleepscreen_enabled = true } }
local record = { definition = { name = "My sleep screen" }, asset_paths = { photo = "/managed/image.png" } }
local calls, default_calls, broken = {}, 0, false
package.preload["appdock_sleepscreen_presets"] = function() return {
    getActive = function(appdock) assert(appdock == owner); return record end,
    defaultPreset = function() default_calls = default_calls + 1; return {name="Default"} end,
} end
package.preload["appdock_sleepscreen_renderer"] = function() return {
    build = function(definition, w, h, options)
        assert(w==600 and h==800 and not options.preview)
        assert(options.appdock==owner)
        if broken then error("damaged preset") end
        calls[#calls+1] = { definition=definition, options=options }
        return { preset=true }
    end,
} end
local Sleep = require("appdock_sleepscreen")
Sleep.show(owner)
assert(#shown==1 and shown[1][1].preset)
assert(calls[1].definition==record.definition and calls[1].options.asset_paths==record.asset_paths)
assert(calls[1].options.cycle==1)
Sleep.show(owner)
assert(#shown==1, "repeated suspend must not stack screens")
shown[1]:onShow()
assert(dirty[#dirty]=="full")
shown[1]:onResume()
assert(Sleep.active==nil and #closed==1)
Sleep.close()
assert(#closed==1)
record = nil
Sleep.show(owner)
assert(default_calls==1 and calls[2].definition.name=="Default")
assert(calls[2].options.cycle==2)
Sleep.close()
broken = true
Sleep.show(owner)
assert(Sleep.active and not Sleep.active[1].preset, "broken preset must retain original screen")
Sleep.close()
assert(Sleep.active==nil)
print("PASS sleepscreen suspend integration and fallback")
