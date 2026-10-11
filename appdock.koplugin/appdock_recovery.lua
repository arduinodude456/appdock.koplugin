-- Local AppDock boot recovery. This module deliberately has no KOReader UI
-- dependencies so it can run before the rest of AppDock is required.
local Recovery = {}

local function trimPath(path)
    return type(path) == "string" and path:gsub("/+$", "") or ""
end

local function shellQuote(value)
    return "'" .. tostring(value or ""):gsub("'", "'\\''") .. "'"
end

local function commandOk(command)
    local first, second, third = os.execute(command)
    return first == true or first == 0 or (second == "exit" and third == 0)
end

local function readFile(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local value = file:read("*a")
    file:close()
    return value
end

local function writeFile(path, value)
    local file = io.open(path, "wb")
    if not file then return false end
    file:write(value or "")
    file:close()
    return true
end

local function removeFile(path)
    if path then os.remove(path) end
end

local function recoveryRoot()
    local ok, DataStorage = pcall(require, "datastorage")
    if not ok or not DataStorage or type(DataStorage.getDataDir) ~= "function" then return nil end
    local data_ok, data_dir = pcall(DataStorage.getDataDir, DataStorage)
    if not data_ok or type(data_dir) ~= "string" or data_dir == "" then return nil end
    return trimPath(data_dir) .. "/appdock/recovery"
end

local function snapshotVersion(root)
    local value = readFile(root .. "/last-good/.appdock-version")
    return type(value) == "string" and (value:match("^%s*(.-)%s*$") or "") or ""
end

local function validSnapshot(root)
    return snapshotVersion(root) ~= "" and readFile(root .. "/last-good/main.lua") ~= nil
end

local function saveSnapshot(context)
    local root, module_dir = context.root, context.module_dir
    if not root or not module_dir or context.recovered or snapshotVersion(root) == context.version then return true end
    local temporary = root .. "/last-good.tmp"
    local last_good = root .. "/last-good"
    local command = "mkdir -p " .. shellQuote(root)
        .. " && rm -rf " .. shellQuote(temporary)
        .. " && mkdir -p " .. shellQuote(temporary)
        .. " && cp -R " .. shellQuote(module_dir .. "/.") .. " " .. shellQuote(temporary .. "/")
        .. " && printf %s " .. shellQuote(context.version) .. " > " .. shellQuote(temporary .. "/.appdock-version")
        .. " && rm -rf " .. shellQuote(last_good)
        .. " && mv " .. shellQuote(temporary) .. " " .. shellQuote(last_good)
    return commandOk(command)
end

local function restoreSnapshot(context)
    local root, module_dir = context.root, context.module_dir
    if not validSnapshot(root) then return false end
    local staging = module_dir .. ".recovery-staging"
    local failed = module_dir .. ".failed-" .. tostring(os.time())
    local command = "rm -rf " .. shellQuote(staging)
        .. " && mkdir -p " .. shellQuote(staging)
        .. " && cp -R " .. shellQuote(root .. "/last-good/.") .. " " .. shellQuote(staging .. "/")
    if not commandOk(command) then return false end
    if os.rename(module_dir, failed) then
        if os.rename(staging, module_dir) then return true end
        -- Restore the current directory if the staging rename was interrupted.
        os.rename(failed, module_dir)
        return false
    end
    -- Very unusual filesystem layouts can reject a directory rename. The copy
    -- fallback remains atomic enough for the next KOReader start because the
    -- complete staged snapshot already exists beside the live plugin folder.
    return commandOk("rm -rf " .. shellQuote(module_dir) .. " && mv " .. shellQuote(staging) .. " " .. shellQuote(module_dir))
end

function Recovery.prepare(module_dir, version)
    local root = recoveryRoot()
    local context = {
        root = root,
        module_dir = trimPath(module_dir),
        version = type(version) == "string" and version or "",
        recovered = false,
    }
    if not root or context.module_dir == "" or context.version == "" then return context end
    commandOk("mkdir -p " .. shellQuote(root))
    local pending_path = root .. "/boot-pending"
    local pending_version = readFile(pending_path)
    pending_version = type(pending_version) == "string" and (pending_version:match("^%s*(.-)%s*$") or "") or ""
    if pending_version ~= "" and pending_version == context.version and validSnapshot(root) then
        if restoreSnapshot(context) then
            context.recovered = true
            writeFile(root .. "/recovery-notice", "AppDock konnte nach dem Update nicht sicher starten. Die letzte funktionierende Version wurde wiederhergestellt. Bitte KOReader einmal neu starten.")
        end
        removeFile(pending_path)
        return context
    end
    if snapshotVersion(root) ~= context.version then
        writeFile(pending_path, context.version)
    else
        removeFile(pending_path)
    end
    return context
end

function Recovery.markHealthy(context)
    if type(context) ~= "table" or context.recovered then return false end
    if context.root then removeFile(context.root .. "/boot-pending") end
    return saveSnapshot(context)
end

function Recovery.consumeNotice(context)
    if type(context) ~= "table" or not context.root then return nil end
    local path = context.root .. "/recovery-notice"
    local value = readFile(path)
    removeFile(path)
    return value
end

Recovery._test = {
    trimPath = trimPath,
    shellQuote = shellQuote,
}

return Recovery
