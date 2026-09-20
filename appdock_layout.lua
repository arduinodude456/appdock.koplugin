--[[
Shared fixed-bounds layout primitives for AppDock.

FixedStack paints children inside the enclosing card and clamps positions and
sizes. This keeps text and controls from leaking out of rounded surfaces when
font metrics or accessibility scaling differ between KOReader builds.
--]]--

local Geom = require("ui/geometry")
local Widget = require("ui/widget/widget")

local FixedStack = Widget:extend{
    width = nil,
    height = nil,
    entries = nil,
    dimen = nil,
}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function safeSize(widget)
    if not widget or type(widget.getSize) ~= "function" then return { w = 0, h = 0 } end
    local size = widget:getSize() or {}
    return { w = math.max(0, tonumber(size.w) or 0), h = math.max(0, tonumber(size.h) or 0) }
end

function FixedStack:init()
    self.width = math.max(0, math.floor(tonumber(self.width) or 0))
    self.height = math.max(0, math.floor(tonumber(self.height) or 0))
    self.dimen = Geom:new{ w = self.width, h = self.height }
end

function FixedStack:getSize()
    return self.dimen
end

function FixedStack:paintTo(bb, x, y)
    for _, entry in ipairs(self.entries or {}) do
        local child = entry and entry.widget
        if child then
            local size = safeSize(child)
            local max_x = math.max(0, self.dimen.w - size.w)
            local max_y = math.max(0, self.dimen.h - size.h)
            local child_x = clamp(math.floor(tonumber(entry.x) or 0), 0, max_x)
            local child_y = clamp(math.floor(tonumber(entry.y) or 0), 0, max_y)
            child:paintTo(bb, x + child_x, y + child_y)
        end
    end
end

return {
    FixedStack = FixedStack,
}
