local plugin_dir = os.getenv("APPDOCK_PLUGIN_DIR") or "./appdock.koplugin/"
local Groups = dofile(plugin_dir .. "appdock_groups.lua")

assert(Groups.isValidAppId("dapp:web_browser"))
assert(not Groups.isValidAppId("bad id"))
assert(Groups.isGroupId("folder:12"))
assert(not Groups.isGroupId("folder:0"))
assert(not Groups.isGroupId("dapp:folder"))

local normalized = Groups.normalize({
    next_id = 1,
    items = {
        ["folder:4"] = { title = "  Reading  ", apps = { "dapp:reader", "dapp:reader", "system:library", "not valid" } },
        ["folder:5"] = { title = "Single", apps = { "dapp:only" } },
        ["bad"] = { title = "Ignored", apps = { "dapp:a", "dapp:b" } },
    },
})
assert(normalized.next_id == 4, "next group id must never collide with persisted ids")
assert(normalized.items["folder:4"].title == "Reading", "group titles must be trimmed")
assert(#normalized.items["folder:4"].apps == 2, "members must be unique and valid")
assert(normalized.items["folder:5"] == nil, "single-member groups must not persist")
assert(Groups.nextId(normalized) == "folder:5", "new ids must be stable and collision-free")
assert(Groups.findContaining(normalized, "system:library") == "folder:4")
assert(Groups.findContaining(normalized, "dapp:missing") == nil)

print("app-groups-ok")
