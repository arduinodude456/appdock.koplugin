local plugin_dir = os.getenv("APPDOCK_PLUGIN_DIR") or "/home/ubuntu/appdock.koplugin/appdock.koplugin/"
local Order = dofile(plugin_dir .. "appdock_order.lua")

local function assertList(actual, expected, message)
    assert(#actual == #expected, message .. " (length)")
    for index, value in ipairs(expected) do
        assert(actual[index] == value, message .. " (index " .. index .. ")")
    end
end

local apps = { "a", "b", "c", "d" }
assert(Order.move(apps, "b", -1))
assertList(apps, { "b", "a", "c", "d" }, "move up")
assert(Order.move(apps, "b", 3))
assertList(apps, { "a", "c", "d", "b" }, "move to last")
assert(Order.move(apps, "b", -99))
assertList(apps, { "b", "a", "c", "d" }, "move to first")
assert(not Order.move(apps, "missing", 1))
assert(not Order.move(apps, "b", 0))
assert(not Order.move(apps, "b", 1.5))
print("AppDock ordering test: OK")
