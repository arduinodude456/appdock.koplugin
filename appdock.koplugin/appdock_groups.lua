--[[--
Small, dependency-free helpers for safely persisted AppDock app groups.
A group is represented by one stable ``folder:<number>`` tile id in the pinned
order and a record with a short title plus at least two application ids.
--]]--

local AppDockGroups = {}

AppDockGroups.PREFIX = "folder:"
AppDockGroups.MAX_GROUPS = 48
AppDockGroups.MAX_MEMBERS = 32

function AppDockGroups.isValidAppId(id)
    return type(id) == "string" and #id > 0 and #id <= 160 and id:match("^[%w:_%-]+$") ~= nil
end

function AppDockGroups.isGroupId(id)
    return type(id) == "string" and id:match("^folder:[1-9]%d*$") ~= nil
end

function AppDockGroups.sanitizeTitle(title)
    title = type(title) == "string" and title:sub(1, 36) or ""
    title = title:match("^%s*(.-)%s*$") or ""
    return title ~= "" and title or "App group"
end

local function copyMembers(members)
    local result, seen = {}, {}
    for _, app_id in ipairs(type(members) == "table" and members or {}) do
        if AppDockGroups.isValidAppId(app_id) and not seen[app_id] then
            result[#result + 1] = app_id
            seen[app_id] = true
            if #result >= AppDockGroups.MAX_MEMBERS then break end
        end
    end
    return result
end

function AppDockGroups.copyRecord(record)
    if type(record) ~= "table" then return nil end
    local members = copyMembers(record.apps)
    if #members < 2 then return nil end
    return {
        title = AppDockGroups.sanitizeTitle(record.title),
        apps = members,
    }
end

-- Normalize untrusted persisted input without touching the pinned order. The
-- caller owns order reconciliation because it knows which group ids occupy a
-- homescreen cell.
function AppDockGroups.normalize(stored)
    stored = type(stored) == "table" and stored or {}
    local normalized = { next_id = 0, items = {} }
    local ids = {}
    for id in pairs(type(stored.items) == "table" and stored.items or {}) do
        if AppDockGroups.isGroupId(id) then ids[#ids + 1] = id end
    end
    table.sort(ids)
    local largest_id, accepted = 0, 0
    for _, id in ipairs(ids) do
        if accepted >= AppDockGroups.MAX_GROUPS then break end
        local record = AppDockGroups.copyRecord(stored.items[id])
        if record then
            normalized.items[id] = record
            accepted = accepted + 1
            local numeric_id = tonumber(id:match("^folder:(%d+)$")) or 0
            largest_id = math.max(largest_id, numeric_id)
        end
    end
    local requested_next = math.floor(tonumber(stored.next_id) or 0)
    normalized.next_id = math.max(largest_id, math.min(999999, math.max(0, requested_next)))
    return normalized
end

function AppDockGroups.nextId(groups)
    groups.items = type(groups.items) == "table" and groups.items or {}
    local next_id = math.max(0, math.floor(tonumber(groups.next_id) or 0))
    repeat
        next_id = next_id + 1
    until not groups.items[AppDockGroups.PREFIX .. next_id]
    groups.next_id = next_id
    return AppDockGroups.PREFIX .. next_id
end

function AppDockGroups.findContaining(groups, app_id)
    if not AppDockGroups.isValidAppId(app_id) then return nil end
    for group_id, record in pairs((groups and groups.items) or {}) do
        for _, member_id in ipairs(record.apps or {}) do
            if member_id == app_id then return group_id end
        end
    end
    return nil
end

return AppDockGroups
