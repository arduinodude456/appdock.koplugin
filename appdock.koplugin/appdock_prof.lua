--[[--
AppDock performance profiler (9.11.0).

Measures wall-clock time of the paths that make AppDock feel slow and writes
every slow step to `appdock_perf.log` in the KOReader data directory:

  * module loading (the first `require` of every appdock_* file: this is
    Lua source parsing on a slow ARM CPU)
  * homescreen build / page change
  * opening a DApp (pane build, host build)
  * dropdown (quick settings) and open apps
  * every screen repaint (`UIManager._repaint`), split into "our" paint time

The profiler is cheap (two clock reads per wrapped call) and only writes lines
that exceed a threshold. Create an empty file `appdock_noprofile` in the data
directory to switch it off completely.
--]]--

local Prof = { installed = false, threshold_ms = 25 }

local DataStorage_ok, DataStorage = pcall(require, "datastorage")
local time_ok, time = pcall(require, "ui/time")
local use_ui_time = time_ok and type(time) == "table" and type(time.now) == "function"
    and type(time.since) == "function" and type(time.to_ms) == "function"

local function now()
    if use_ui_time then return time.now() end
    return os.clock()
end

local function elapsed_ms(t0)
    if use_ui_time then return time.to_ms(time.since(t0)) end
    return (os.clock() - t0) * 1000
end
Prof.now, Prof.elapsed_ms = now, elapsed_ms

local log_path
local function logPath()
    if log_path then return log_path end
    local dir = "."
    if DataStorage_ok and DataStorage and DataStorage.getDataDir then
        local ok, value = pcall(DataStorage.getDataDir, DataStorage)
        if ok and type(value) == "string" then dir = value end
    end
    log_path = dir .. "/appdock_perf.log"
    Prof.dir = dir
    return log_path
end

local written = 0
function Prof.log(line)
    local path = logPath()
    local fh = io.open(path, "a")
    if not fh then return end
    fh:write(os.date("%H:%M:%S "), line, "\n")
    written = written + #line + 10
    fh:close()
    -- Keep the log small: roll it over after ~256 KB.
    if written > 262144 then
        written = 0
        pcall(os.remove, path .. ".old")
        pcall(os.rename, path, path .. ".old")
    end
end

--- Wraps tbl[name] so calls slower than `threshold` ms are logged.
-- `label` may be a string or a function(...) returning one (receives the call
-- arguments, e.g. to name the DApp being built).
function Prof.wrap(tbl, name, label, threshold)
    local original = type(tbl) == "table" and tbl[name]
    if type(original) ~= "function" then return false end
    local wrapped_marker = "__appdock_prof_" .. name
    if rawget(tbl, wrapped_marker) then return false end
    rawset(tbl, wrapped_marker, true)
    threshold = threshold or Prof.threshold_ms
    local function finish(text, t0, ...)
        local took = elapsed_ms(t0)
        if took >= threshold then
            Prof.log(string.format("%-46s %7.0f ms", text, took))
        end
        return ...
    end
    tbl[name] = function(...)
        local t0 = now()
        local text = label
        if type(label) == "function" then
            local ok, result = pcall(label, ...)
            text = ok and result or name
        end
        return finish(text or name, t0, original(...))
    end
    return true
end

local function wrapMany(tbl, prefix, names, threshold)
    for _, name in ipairs(names) do
        Prof.wrap(tbl, name, prefix .. name, threshold)
    end
end

-- What to instrument once a module has been loaded.
local TARGETS = {
    appdock_homescreen = function(M)
        wrapMany(M, "home.", { "init", "build", "_showPage", "_buildShelfPage", "_buildSimpleMode",
            "showQuickSettings", "onRevealRecentApps", "onSwipeHomePage", "showAppGroup", "relayout" }, 15)
    end,
    appdock_dapps = function(M)
        wrapMany(M, "dapps.", { "activate", "openWindow", "startSplit", "showRecents", "showRecentsFromHost",
            "showHomeFromHost", "showQuickSettingsFromHost", "openDAppFile", "_instanceFor", "_newContext" }, 15)
        Prof.wrap(M, "_buildPaneSafely", function(_, instance)
            return "dapps.buildPane[" .. tostring(instance and instance.id or "?") .. "]"
        end, 15)
    end,
    appdock_quicksettings = function(M)
        wrapMany(M, "quick.", { "new", "show", "init", "build", "buildPanel", "open", "refresh" }, 15)
    end,
    appdock_keyboard = function(M)
        wrapMany(M, "kbd.", { "new", "init", "build", "show", "open" }, 15)
    end,
    appdock_filemanager = function(M)
        wrapMany(M, "files.", { "new", "init", "build", "buildPane", "refresh", "reload", "open", "scan" }, 15)
    end,
}

local function instrumentModule(name, module)
    if type(module) ~= "table" then return end
    local target = TARGETS[name]
    if target then pcall(target, module) end
end

local function installRequire()
    local original_require = require
    local depth = 0
    _G.require = function(name)
        if type(name) ~= "string" or package.loaded[name] ~= nil or not name:find("^appdock_") then
            return original_require(name)
        end
        -- First load of an AppDock module: this is parse + run time of the file.
        local t0 = now()
        depth = depth + 1
        local ok, module = pcall(original_require, name)
        depth = depth - 1
        local took = elapsed_ms(t0)
        if took >= 8 then
            Prof.log(string.format("%-46s %7.0f ms", string.rep("  ", depth) .. "load " .. name, took))
        end
        if not ok then error(module, 0) end
        instrumentModule(name, module)
        return module
    end
    -- Modules that were already loaded before the profiler came up.
    for name in pairs(TARGETS) do
        if package.loaded[name] then instrumentModule(name, package.loaded[name]) end
    end
end

local function installPaintTimer()
    local ok, UIManager = pcall(require, "ui/uimanager")
    if not ok or type(UIManager) ~= "table" then return end
    -- Total time KOReader spends in one repaint pass (widget paintTo calls plus
    -- handing the regions to the e-ink driver).
    Prof.wrap(UIManager, "_repaint", "ui.repaint", 60)
    Prof.wrap(UIManager, "forceRePaint", "ui.forceRePaint", 60)
    Prof.wrap(UIManager, "yieldToEPDC", "ui.yieldToEPDC", 40)
end

function Prof.install()
    if Prof.installed then return true end
    local dir_ok = pcall(logPath)
    if dir_ok and Prof.dir then
        local marker = io.open(Prof.dir .. "/appdock_noprofile", "r")
        if marker then marker:close(); return false end
    end
    Prof.installed = true
    Prof.log("---- AppDock profiler started (slow steps only) ----")
    pcall(installRequire)
    pcall(installPaintTimer)
    return true
end

return Prof
