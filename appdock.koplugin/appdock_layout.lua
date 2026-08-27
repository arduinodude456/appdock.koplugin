--[[
Shared fixed-bounds layout primitives for AppDock.

Unlike OverlapGroup, FixedStack does not rely on per-child overlap offsets.
Every child is painted explicitly after its enclosing FrameContainer has drawn
its background, and every coordinate is clamped to the stack's own bounds.
This keeps labels inside their visible card even on KOReader builds whose text
metrics differ from the build used during development.
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
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

function FixedStack:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
end

function FixedStack:getSize()
    return self.dimen
end

function FixedStack:paintTo(bb, x, y)
    for _, entry in ipairs(self.entries or {}) do
        local child = entry and entry.widget
        if child then
            local child_size = child:getSize()
            local max_x = math.max(0, self.dimen.w - child_size.w)
            local max_y = math.max(0, self.dimen.h - child_size.h)
            local child_x = clamp(math.floor(entry.x or 0), 0, max_x)
            local child_y = clamp(math.floor(entry.y or 0), 0, max_y)
            child:paintTo(bb, x + child_x, y + child_y)
        end
    end
end

return {
    FixedStack = FixedStack,
}
