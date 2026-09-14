--[[--
Small, dependency-free helpers for persisted AppDock ordering.
--]]--

local AppDockOrder = {}

function AppDockOrder.findPosition(list, value)
    for index, item in ipairs(list or {}) do
        if item == value then return index end
    end
    return nil
end

function AppDockOrder.move(list, value, delta)
    if type(list) ~= "table" then return false end
    local index = AppDockOrder.findPosition(list, value)
    if not index then return false end

    delta = tonumber(delta)
    if not delta or delta ~= math.floor(delta) or delta == 0 then return false end

    -- Movement commands may target an absolute edge (for example, "last").
    -- Clamp instead of rejecting a delta that crosses the list boundary.
    local target = math.max(1, math.min(#list, index + delta))
    if target == index then return false end
    table.remove(list, index)
    table.insert(list, target, value)
    return true
end

return AppDockOrder
