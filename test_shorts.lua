-- Pure helper tests for the AppDock YouTube Shorts feed.
local function class(base)
    local c = {}
    c.__index = c
    function c:extend() return class(c) end
    function c:new(value) return setmetatable(value or {}, self) end
    return c
end
local Widget = class()
local Input = Widget:extend()
package.preload["ffi/blitbuffer"] = function() return { COLOR_BLACK = 0, COLOR_WHITE = 255 } end
package.preload["ui/widget/container/centercontainer"] = function() return Widget end
package.preload["ui/font"] = function() return { getFace = function(_, _, size) return { size = size } end } end
package.preload["ui/widget/container/framecontainer"] = function() return Widget end
package.preload["ui/geometry"] = function() return { new = function(_, value) return value end } end
package.preload["ui/widget/container/inputcontainer"] = function() return Input end
package.preload["ui/widget/container/overlapgroup"] = function() return Widget end
package.preload["ui/widget/textwidget"] = function() return Widget end
package.preload["ui/uimanager"] = function() return {} end
package.preload["ui/widget/container/widgetcontainer"] = function() return Widget end
package.preload["datastorage"] = function() return {} end
package.preload["gettext"] = function() return function(value) return value end end
package.preload["appdock_youtube"] = function() return { new = function() end, slugify = function(_, title, fallback) return title ~= "" and title or fallback end } end
package.preload["appdock_player"] = function() return {} end
package.preload["appdock_logo"] = function() return Widget end
package.preload["device"] = function() return { screen = { scaleBySize = function(_, value) return value end } } end

local Shorts = dofile((os.getenv("APPDOCK_PLUGIN_DIR") or ".") .. "/appdock_shorts.lua")
local tags = Shorts._test.extractHashtags("#Cats with #Cats and #e-ink")
assert(#tags == 2 and tags[1] == "cats" and tags[2] == "e-ink")
assert(Shorts._test.isShort({ duration = 45, title = "#shorts cat" }))
assert(not Shorts._test.isShort({ duration = 181, title = "#shorts long" }))
local ranked = Shorts._test.recommend({
    { id = "a", title = "#cats one", duration = 20 },
    { id = "b", title = "#tech two", duration = 20 },
}, { cats = 2 }, {})
assert(ranked[1].id == "a", "liked hashtags must influence recommendation order")
print("Shorts helper tests passed")
