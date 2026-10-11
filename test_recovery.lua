-- Regression test: an interrupted AppDock boot must restore the last known good
-- plugin snapshot without requiring KOReader UI modules.
local base = os.tmpname() .. "-appdock-recovery"
os.remove(base)
os.execute("mkdir -p '" .. base .. "/data/appdock/recovery/last-good' '" .. base .. "/plugins/appdock.koplugin'")

local function write(path, value)
    local file = assert(io.open(path, "wb"))
    file:write(value)
    file:close()
end
local function read(path)
    local file = assert(io.open(path, "rb"))
    local value = file:read("*a")
    file:close()
    return value
end

write(base .. "/data/appdock/recovery/last-good/.appdock-version", "7.9.48")
write(base .. "/data/appdock/recovery/last-good/main.lua", "return 'known-good'")
write(base .. "/plugins/appdock.koplugin/main.lua", "return 'new-build'")
package.preload["datastorage"] = function()
    return { getDataDir = function() return base .. "/data" end }
end

local Recovery = assert(loadfile("appdock.koplugin/appdock_recovery.lua"))()
local current = base .. "/plugins/appdock.koplugin/"
local first = Recovery.prepare(current, "7.9.49")
assert(not first.recovered, "A first boot of a new version must arm rollback but continue normally")
local second = Recovery.prepare(current, "7.9.49")
assert(second.recovered, "An uncleared boot marker must restore the last known good snapshot")
assert(read(base .. "/plugins/appdock.koplugin/main.lua") == "return 'known-good'", "Recovery must replace the broken plugin tree with the snapshot")
assert(Recovery.consumeNotice(second):find("wiederhergestellt", 1, true), "Recovery must leave a user-visible local notice")
os.execute("rm -rf '" .. base .. "'")
print("appdock-recovery-ok")
