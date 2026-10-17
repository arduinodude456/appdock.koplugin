--[[--
TBS account support for AppDock.

The reader talks only to the tbs-account Supabase Edge Function over HTTPS. A
per-device, high-entropy secret authenticates calls; the Supabase service-role
key stays exclusively inside the Edge Function. The saved migration snapshot
intentionally excludes lockscreen secrets, local file paths, DChat data and
other reader-specific credentials.
--]]--

local AppDockDialogs = require("appdock_dialogs")
local ButtonDialog = AppDockDialogs.ButtonDialog
local InfoMessage = AppDockDialogs.InfoMessage
local InputDialog = AppDockDialogs.InputDialog
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Account = {}

-- This is the existing DChat-DM Supabase project. Deploy the companion
-- `tbs-account` Edge Function there before enabling the feature in a release.
local DEFAULT_ENDPOINT = "https://qndwbriqomqqaqhkasbh.supabase.co/functions/v1/tbs-account"
-- Publishable keys may be embedded in clients. Never replace this with a
-- service-role/secret key; the function authenticates device credentials.
local DEFAULT_PUBLISHABLE_KEY = "sb_publishable_UAIcZameyUZHtEB-NY1ffQ_TfF67BjS"
local MAX_RESPONSE_BYTES = 160 * 1024
local MAX_SNAPSHOT_BYTES = 120 * 1024
local CONNECT_TIMEOUT = 10
local REQUEST_MAX_TIME = 25
local SESSION_KEY = "appdock_tbs_session"
local volatile_session = {}
local ACCOUNT_ID_PATTERN = "^[%x][%x][%x][%x][%x][%x][%x][%x]%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"
local DEVICE_ID_PATTERN = "^tbs_[%w_%-]+$"
local DEVICE_SECRET_PATTERN = "^[%w_%-]+$"

local SNAPSHOT_KEYS = {
    "pinned_apps", "widgets", "theme", "design", "layout", "beta",
    "quick_settings", "simple_mode", "accessibility", "dapp_permissions",
    "widget_generator", "keyboard", "file_browser", "power_saving",
    "volume_percent", "refresh_interval", "sleepscreen_enabled", "youtube",
    "app_groups", "folders", "wallpaper",
}

local function trim(value)
    if type(value) ~= "string" then return "" end
    return value:match("^%s*(.-)%s*$") or ""
end

local function safeText(value, maximum)
    return trim(value):gsub("[%c]", ""):sub(1, maximum)
end

local function validEndpoint(value)
    value = trim(value):gsub("/+$", "")
    if value == "" or #value > 240 or value:find("[%c%s]") then return nil end
    local ok, socket_url = pcall(require, "socket.url")
    if not ok or not socket_url then return nil end
    local parsed = socket_url.parse(value)
    if not parsed or parsed.scheme ~= "https" or not parsed.host or parsed.host == "" or parsed.userinfo or parsed.query or parsed.fragment then return nil end
    return value
end

local function isAccountId(value)
    return type(value) == "string" and value:lower():match(ACCOUNT_ID_PATTERN) ~= nil
end

local function isDeviceId(value)
    return type(value) == "string" and value:match(DEVICE_ID_PATTERN) ~= nil and #value >= 20 and #value <= 84
end

local function isDeviceSecret(value)
    return type(value) == "string" and value:match(DEVICE_SECRET_PATTERN) ~= nil and #value >= 32 and #value <= 128
end

local function copyTree(value, depth, budget)
    depth = depth or 0
    budget = budget or { left = 900 }
    if budget.left <= 0 or depth > 7 then return nil end
    if type(value) == "string" then
        budget.left = budget.left - 1
        return value:sub(1, 640)
    elseif type(value) == "number" then
        if value ~= value or value == math.huge or value == -math.huge then return nil end
        budget.left = budget.left - 1
        return value
    elseif type(value) == "boolean" then
        budget.left = budget.left - 1
        return value
    elseif type(value) ~= "table" then
        return nil
    end
    local copied = {}
    for key, child in pairs(value) do
        if budget.left <= 0 then break end
        local key_type = type(key)
        if (key_type == "string" and #key <= 96 and key:match("^[%w_:%-]+$") ) or (key_type == "number" and key >= 1 and key <= 1000 and math.floor(key) == key) then
            local converted = copyTree(child, depth + 1, budget)
            if converted ~= nil then copied[key] = converted end
        end
    end
    return copied
end

local PRIVATE_FIELD = {
    path = true, file = true, wallpaper_file = true, profile_image_path = true,
    secret = true, secret_hash = true, password = true, token = true,
    device_secret = true, recovery_code = true,
}

local function cloudCopyTree(value, depth, budget, field_name)
    if type(field_name) == "string" and PRIVATE_FIELD[field_name:lower()] then return nil end
    if type(value) == "string" and value:sub(1, 1) == "/" then return nil end
    if type(value) ~= "table" then return copyTree(value, depth, budget) end
    depth = depth or 0
    budget = budget or { left = 900 }
    if budget.left <= 0 or depth > 7 then return nil end
    local copied = {}
    for key, child in pairs(value) do
        if budget.left <= 0 then break end
        local key_type = type(key)
        if (key_type == "string" and #key <= 96 and key:match("^[%w_:%-]+$"))
            or (key_type == "number" and key >= 1 and key <= 1000 and math.floor(key) == key) then
            local converted = cloudCopyTree(child, depth + 1, budget, key_type == "string" and key or nil)
            if converted ~= nil then copied[key] = converted end
        end
    end
    return copied
end

local function normalizedSession(raw)
    raw = type(raw) == "table" and raw or {}
    local endpoint = validEndpoint(raw.endpoint) or DEFAULT_ENDPOINT
    local publishable_key = safeText(raw.publishable_key, 300)
    if publishable_key == "" then publishable_key = DEFAULT_PUBLISHABLE_KEY end
    local account_id = safeText(raw.account_id, 80):lower()
    local device_id = safeText(raw.device_id, 84)
    local device_secret = safeText(raw.device_secret, 128)
    return {
        endpoint = endpoint,
        publishable_key = publishable_key,
        account_id = isAccountId(account_id) and account_id or "",
        device_id = isDeviceId(device_id) and device_id or "",
        device_secret = isDeviceSecret(device_secret) and device_secret or "",
        username = safeText(raw.username, 80),
        display_name = safeText(raw.display_name, 80),
        sync_revision = math.max(0, math.floor(tonumber(raw.sync_revision) or 0)),
        last_synced_at = math.max(0, math.floor(tonumber(raw.last_synced_at) or 0)),
        sync_conflict = raw.sync_conflict == true,
        personalization = copyTree(raw.personalization, 0, { left = 120 }) or {},
        pending_installations = copyTree(raw.pending_installations, 0, { left = 160 }) or {},
    }
end

local function normalizedProfile(raw)
    raw = type(raw) == "table" and raw or {}
    local display_name = safeText(raw.display_name, 80)
    local username = safeText(raw.username, 80)
    return {
        enabled = raw.enabled == true,
        username = username ~= "" and username or display_name,
        display_name = display_name,
    }
end

local function readSession()
    if _G.G_reader_settings and type(G_reader_settings.readSetting) == "function" then
        local ok, stored = pcall(G_reader_settings.readSetting, G_reader_settings, SESSION_KEY, {})
        if ok then return normalizedSession(stored) end
    end
    return normalizedSession(volatile_session)
end

local function writeSession(session)
    session = normalizedSession(session)
    if _G.G_reader_settings and type(G_reader_settings.saveSetting) == "function" then
        local ok = pcall(G_reader_settings.saveSetting, G_reader_settings, SESSION_KEY, session)
        if ok then return true end
    end
    volatile_session = session
    return true
end

local function hasCredentials(account)
    return account and account.account_id ~= "" and account.device_id ~= "" and account.device_secret ~= ""
end

function Account.get(appdock)
    local session = readSession()
    local profile = normalizedProfile(appdock and appdock.settings and appdock.settings.tbs_account)
    session.display_name = profile.display_name
    session.username = profile.username
    return session
end

function Account.isSignedIn(appdock)
    return hasCredentials(Account.get(appdock))
end

function Account.status(appdock)
    local account = Account.get(appdock)
    return {
        signed_in = hasCredentials(account),
        account_id = account.account_id,
        display_name = account.display_name,
        last_synced_at = account.last_synced_at,
        sync_conflict = account.sync_conflict == true,
        pending_installation_count = #account.pending_installations,
    }
end

local function saveLocal(appdock, account)
    if not appdock or not appdock.settings then return false end
    account = normalizedSession(account)
    local display_name = safeText(account.display_name, 80)
    appdock.settings.tbs_account = {
        enabled = hasCredentials(account),
        username = safeText(account.username, 80) ~= "" and safeText(account.username, 80) or display_name,
        display_name = display_name,
    }
    writeSession(account)
    local was_suspended = appdock._tbs_sync_suspended
    appdock._tbs_sync_suspended = true
    if appdock._saveSettings then appdock:_saveSettings() end
    appdock._tbs_sync_suspended = was_suspended
    return true
end

local function apiRequest(account, action, payload, include_identity)
    local endpoint = validEndpoint(account.endpoint)
    if not endpoint then return nil, nil, _("The TBS account address is invalid.") end
    local ok_https, https = pcall(require, "ssl.https")
    local ok_socket, socket = pcall(require, "socket")
    local ok_ltn12, ltn12 = pcall(require, "ltn12")
    local ok_util, socketutil = pcall(require, "socketutil")
    local ok_json, JSON = pcall(require, "json")
    if not ok_https or not ok_socket or not ok_ltn12 or not ok_util or not ok_json then
        return nil, nil, _("HTTPS or JSON support is unavailable.")
    end
    local request_payload = type(payload) == "table" and copyTree(payload, 0, { left = 1000 }) or {}
    request_payload.action = action
    local encoded_ok, body = pcall(JSON.encode, request_payload)
    if not encoded_ok or type(body) ~= "string" or #body > MAX_SNAPSHOT_BYTES + 8192 then
        return nil, nil, _("The TBS account request is too large.")
    end
    local received, chunks = 0, {}
    local function sink(chunk, sink_err)
        if sink_err then return nil, sink_err end
        if chunk then
            received = received + #chunk
            if received > MAX_RESPONSE_BYTES then return nil, "response too large" end
            chunks[#chunks + 1] = chunk
        end
        return 1
    end
    local headers = {
        ["accept"] = "application/json",
        ["content-type"] = "application/json",
        ["content-length"] = tostring(#body),
        ["user-agent"] = "AppDock-TBS/1.0",
        ["apikey"] = account.publishable_key,
    }
    if include_identity then
        if not hasCredentials(account) then
            return nil, nil, _("Sign in to a TBS account first.")
        end
        headers["x-tbs-account-id"] = account.account_id
        headers["x-tbs-device-id"] = account.device_id
        headers["x-tbs-device-secret"] = account.device_secret
    end
    socketutil:set_timeout(CONNECT_TIMEOUT, REQUEST_MAX_TIME)
    local ok, code, response_headers, status = pcall(function()
        return socket.skip(1, https.request{ url = endpoint, method = "POST", source = ltn12.source.string(body), sink = sink, headers = headers })
    end)
    socketutil:reset_timeout()
    code = tonumber(code)
    local decoded = nil
    local raw = table.concat(chunks)
    if raw ~= "" then
        local decoded_ok, value = pcall(JSON.decode, raw, JSON.decode.simple)
        if decoded_ok and type(value) == "table" then decoded = value end
    end
    if not ok or not response_headers or not code then
        return nil, nil, _("TBS Account could not reach the service. Your local AppDock settings remain unchanged.")
    end
    local remote_message = decoded and decoded.error and safeText(decoded.error.message, 180) or ""
    if code < 200 or code > 299 then
        return decoded, code, remote_message ~= "" and remote_message or _("The TBS account service rejected the request.")
    end
    if not decoded then return nil, code, _("The TBS account service returned invalid data.") end
    return decoded, code
end

local function applyCredentials(appdock, result)
    result = type(result) == "table" and result or {}
    local current = Account.get(appdock)
    local account = normalizedSession({
        endpoint = current.endpoint,
        publishable_key = current.publishable_key,
        account_id = result.accountId,
        device_id = result.deviceId,
        device_secret = result.deviceSecret,
        sync_revision = result.snapshot and result.snapshot.revision or 0,
        personalization = result.snapshot and result.snapshot.personalization or {},
    })
    account.display_name = safeText(result.displayName, 80)
    account.username = account.display_name
    if not hasCredentials(account) then
        return nil, _("The TBS account service returned incomplete credentials.")
    end
    saveLocal(appdock, account)
    return account
end

function Account.register(appdock, display_name, device_name)
    local account = Account.get(appdock)
    local response, _, err = apiRequest(account, "register", {
        displayName = safeText(display_name, 80),
        deviceName = safeText(device_name, 80) ~= "" and safeText(device_name, 80) or "AppDock reader",
    }, false)
    if not response then return nil, err end
    local saved, save_err = applyCredentials(appdock, response)
    if not saved then return nil, save_err end
    return { account = saved, recovery_code = safeText(response.recoveryCode, 64), snapshot = response.snapshot }
end

function Account.migrate(appdock, account_id, recovery_code, device_name)
    local account = Account.get(appdock)
    local response, _, err = apiRequest(account, "migrate", {
        accountId = safeText(account_id, 80):lower(),
        recoveryCode = safeText(recovery_code, 80),
        deviceName = safeText(device_name, 80) ~= "" and safeText(device_name, 80) or "AppDock reader",
    }, false)
    if not response then return nil, err end
    local saved, save_err = applyCredentials(appdock, response)
    if not saved then return nil, save_err end
    return { account = saved, snapshot = response.snapshot }
end

local function installManifest(settings)
    local manifest = {}
    local installed = settings and settings.store and settings.store.installed or {}
    for id, record in pairs(type(installed) == "table" and installed or {}) do
        if type(id) == "string" and id:match("^[%w_%-]+$") and type(record) == "table" then
            manifest[#manifest + 1] = {
                id = id,
                kind = record.kind == "widget" and "widget" or "dapp",
                source_path = safeText(record.source_path, 280),
                version = safeText(record.version, 80),
            }
        end
    end
    table.sort(manifest, function(left, right) return left.id < right.id end)
    while #manifest > 80 do table.remove(manifest) end
    return manifest
end

function Account.buildSnapshot(appdock)
    local settings = appdock and appdock.settings or {}
    local saved = {}
    for _, key in ipairs(SNAPSHOT_KEYS) do
        if key == "wallpaper" then
            local wallpaper = type(settings.wallpaper) == "table" and settings.wallpaper or {}
            -- A reader-local custom image path has no meaning on another
            -- device. Only portable metadata for AppDock's bundled default
            -- travels; the receiving reader resolves its own plugin path.
            if wallpaper.source == "appdock_default" then
                saved.wallpaper = { enabled = wallpaper.enabled == true, source = "appdock_default" }
            end
        else
        local value = cloudCopyTree(settings[key], 0, { left = 250 })
        if value ~= nil then saved[key] = value end
        end
    end
    -- Only an installation manifest travels to another reader. Paths and actual
    -- Lua files remain local and are never uploaded; a later AppStore restore
    -- can reinstall catalog entries from this safe manifest.
    saved.install_manifest = installManifest(settings)
    return { version = 1, saved_at = os.time(), settings = saved }
end

local function snapshotFromResponse(response)
    local raw = type(response) == "table" and response.snapshot or nil
    if type(raw) ~= "table" then return nil end
    local state = type(raw.state) == "table" and raw.state or nil
    if not state or type(state.settings) ~= "table" then return nil end
    return {
        revision = math.max(0, math.floor(tonumber(raw.revision) or 0)),
        settings = copyTree(state.settings, 0, { left = 1300 }) or {},
        personalization = copyTree(raw.personalization, 0, { left = 160 }) or {},
    }
end

function Account.applySnapshot(appdock, snapshot)
    if not appdock or not appdock.settings or type(snapshot) ~= "table" then return false, _("The TBS account backup is invalid.") end
    local settings = type(snapshot.settings) == "table" and snapshot.settings or {}
    for _, key in ipairs(SNAPSHOT_KEYS) do
        if key == "wallpaper" then
            local wallpaper = type(settings.wallpaper) == "table" and settings.wallpaper or nil
            if wallpaper and wallpaper.source == "appdock_default" then
                local plugin_path = (appdock.path or ""):gsub("/+$", "")
                appdock.settings.wallpaper = {
                    enabled = wallpaper.enabled == true,
                    source = "appdock_default",
                    path = plugin_path .. "/assets/wallpaper/appdock_default.svg",
                }
            end
        elseif settings[key] ~= nil then
            appdock.settings[key] = cloudCopyTree(settings[key], 0, { left = 250 }) or appdock.settings[key]
        end
    end
    local account = Account.get(appdock)
    account.sync_revision = math.max(0, math.floor(tonumber(snapshot.revision) or account.sync_revision))
    account.sync_conflict = false
    account.personalization = copyTree(snapshot.personalization, 0, { left = 160 }) or account.personalization
    account.pending_installations = copyTree(settings.install_manifest, 0, { left = 160 }) or {}
    saveLocal(appdock, account)
    return true
end

function Account.sync(appdock)
    if not Account.isSignedIn(appdock) then return false, _("Sign in to a TBS account first.") end
    local account = Account.get(appdock)
    if account.sync_conflict then
        return false, _("A newer TBS account backup exists. Restore it on this reader before synchronizing again.")
    end
    local snapshot = Account.buildSnapshot(appdock)
    local response, code, err = apiRequest(account, "sync", {
        schemaVersion = 1,
        expectedRevision = account.sync_revision,
        state = snapshot,
        personalization = account.personalization,
    }, true)
    if code == 409 and response then
        local remote = snapshotFromResponse(response)
        if remote then
            -- Preserve local state rather than silently overwriting it. The user
            -- can explicitly run device migration to select the cloud snapshot.
            account.sync_revision = remote.revision
            account.sync_conflict = true
            saveLocal(appdock, account)
        end
        return false, _("A newer TBS account backup exists. Open TBS Account and migrate this reader to restore it.")
    end
    if not response then return false, err end
    local remote = snapshotFromResponse(response)
    if remote then
        account.sync_revision = remote.revision
        account.personalization = remote.personalization
    end
    account.pending_installations = copyTree(snapshot.settings.install_manifest, 0, { left = 160 }) or {}
    account.last_synced_at = os.time()
    account.sync_conflict = false
    saveLocal(appdock, account)
    return true
end

function Account.queueSync(appdock)
    if not Account.isSignedIn(appdock) or (appdock and appdock._tbs_sync_suspended) then return false end
    if appdock._tbs_sync_scheduled then return true end
    appdock._tbs_sync_scheduled = function()
        appdock._tbs_sync_scheduled = nil
        pcall(Account.sync, appdock)
    end
    if UIManager and UIManager.scheduleIn then
        UIManager:scheduleIn(4, appdock._tbs_sync_scheduled)
    elseif UIManager and UIManager.nextTick then
        UIManager:nextTick(appdock._tbs_sync_scheduled)
    else
        appdock._tbs_sync_scheduled()
    end
    return true
end

function Account.recordAppUse(appdock, app_id)
    if not Account.isSignedIn(appdock) or type(app_id) ~= "string" then return false end
    local account = Account.get(appdock)
    account.personalization = type(account.personalization) == "table" and account.personalization or {}
    local usage = type(account.personalization.app_usage) == "table" and account.personalization.app_usage or {}
    local current = math.max(0, math.floor(tonumber(usage[app_id]) or 0))
    usage[app_id] = math.min(1000, current + 1)
    account.personalization.app_usage = usage
    account.personalization.last_app = safeText(app_id, 96)
    saveLocal(appdock, account)
    Account.queueSync(appdock)
    return true
end

local function showNotice(text)
    UIManager:show(InfoMessage:new{ text = text })
end

local function attachKeyboard(dialog)
    local ok, Keyboard = pcall(require, "appdock_keyboard")
    if ok and Keyboard and Keyboard.attach then Keyboard.attach(dialog) end
end

local function showRecoveryCode(account, recovery_code, done)
    local message = _("TBS account created. Write down both values now; the recovery code is shown only once.")
        .. "\n\n" .. _("Account ID:") .. "\n" .. account.account_id
        .. "\n\n" .. _("Recovery code:") .. "\n" .. recovery_code
        .. "\n\n" .. _("Use them in TBS Account → Move to this reader when setting up another device.")
    local dialog
    dialog = ButtonDialog:new{
        title = _("Save your TBS recovery code"),
        buttons = { { { text = _("I wrote it down"), callback = function()
            UIManager:close(dialog)
            if done then done(true) end
        end } } },
        text = message,
    }
    UIManager:show(dialog)
end

local function promptRegistration(appdock, done)
    local dialog
    dialog = InputDialog:new{
        title = _("Create TBS account"),
        description = _("A TBS account backs up compact AppDock settings and anonymous preference signals for recommendations. It does not upload books, media, AppDock files, local paths, DChat messages, or lockscreen secrets."),
        input_hint = _("Display name"),
        input = "",
        buttons = { {
            { text = _("Cancel"), callback = function() UIManager:close(dialog); if done then done(false) end end },
            { text = _("Create"), is_enter_default = true, callback = function()
                local display_name = dialog:getInputText() or ""
                UIManager:close(dialog)
                local created, err = Account.register(appdock, display_name)
                if not created then showNotice(err or _("The TBS account could not be created.")); if done then done(false) end; return end
                showRecoveryCode(created.account, created.recovery_code, done)
            end },
        } },
    }
    attachKeyboard(dialog)
    UIManager:show(dialog)
    if dialog.onShowKeyboard then dialog:onShowKeyboard() end
end

local function promptMigrationCode(appdock, account_id, done)
    local dialog
    dialog = InputDialog:new{
        title = _("Move TBS account to this reader"),
        description = _("Enter the recovery code that was shown when the account was created."),
        input_hint = _("TBS-… recovery code"),
        input = "",
        buttons = { {
            { text = _("Cancel"), callback = function() UIManager:close(dialog); if done then done(false) end end },
            { text = _("Restore"), is_enter_default = true, callback = function()
                local recovery_code = dialog:getInputText() or ""
                UIManager:close(dialog)
                local migrated, err = Account.migrate(appdock, account_id, recovery_code)
                if not migrated then showNotice(err or _("The TBS account could not be restored.")); if done then done(false) end; return end
                local snapshot = snapshotFromResponse({ snapshot = migrated.snapshot })
                if snapshot then Account.applySnapshot(appdock, snapshot) end
                showNotice(_("TBS account restored. Compact settings and the app-installation manifest are available on this reader."))
                if done then done(true) end
            end },
        } },
    }
    attachKeyboard(dialog)
    UIManager:show(dialog)
    if dialog.onShowKeyboard then dialog:onShowKeyboard() end
end

local function promptMigration(appdock, done)
    local dialog
    dialog = InputDialog:new{
        title = _("Move TBS account to this reader"),
        description = _("Enter your TBS account ID, then the saved recovery code. This creates a new device credential without exposing the old reader's secret."),
        input_hint = _("Account ID"),
        input = "",
        buttons = { {
            { text = _("Cancel"), callback = function() UIManager:close(dialog); if done then done(false) end end },
            { text = _("Continue"), is_enter_default = true, callback = function()
                local account_id = trim(dialog:getInputText() or ""):lower()
                UIManager:close(dialog)
                if not isAccountId(account_id) then showNotice(_("Enter a valid TBS account ID.")); if done then done(false) end; return end
                promptMigrationCode(appdock, account_id, done)
            end },
        } },
    }
    attachKeyboard(dialog)
    UIManager:show(dialog)
    if dialog.onShowKeyboard then dialog:onShowKeyboard() end
end

function Account.require(appdock, feature_name, done)
    if Account.isSignedIn(appdock) then
        if done then done(true) end
        return true
    end
    local title = safeText(feature_name, 80)
    local dialog
    local function defer(callback)
        if UIManager.nextTick then UIManager:nextTick(callback) else callback() end
    end
    dialog = ButtonDialog:new{
        title = _("TBS account required") .. (title ~= "" and " · " .. title or ""),
        text = _("This feature requires a TBS account. It keeps compact AppDock settings and optional anonymous recommendation signals in your TBS cloud account. Create an account or move an existing account to this reader."),
        buttons = {
            { { text = _("Create TBS account"), callback = function()
                UIManager:close(dialog)
                defer(function() promptRegistration(appdock, done) end)
            end } },
            { { text = _("Move account to this reader"), callback = function()
                UIManager:close(dialog)
                defer(function() promptMigration(appdock, done) end)
            end } },
            { { text = _("Cancel"), callback = function()
                UIManager:close(dialog)
                if done then done(false) end
            end } },
        },
    }
    UIManager:show(dialog)
    return false
end

function Account.showSettings(appdock, context)
    local status = Account.status(appdock)
    if not status.signed_in then return Account.require(appdock, _("TBS Account"), function(ready)
        if ready and context and context.requestRebuild then context.requestRebuild("ui") end
    end) end
    local sync_label = status.sync_conflict and _("Conflict · restore required")
        or (status.last_synced_at > 0 and os.date("%Y-%m-%d %H:%M", status.last_synced_at) or _("Not yet"))
    local dialog
    dialog = ButtonDialog:new{
        title = _("TBS Account") .. "\n" .. (status.display_name ~= "" and status.display_name or status.account_id),
        text = _("Account ID:") .. "\n" .. status.account_id .. "\n\n" .. _("Last settings sync:") .. " " .. sync_label,
        buttons = {
            { { text = _("Sync now"), callback = function()
                UIManager:close(dialog)
                local ok, err = Account.sync(appdock)
                showNotice(ok and _("TBS account backup updated.") or (err or _("The backup could not be updated.")))
                if context and context.requestRebuild then context.requestRebuild("ui") end
            end } },
            { { text = _("Restore on this reader"), callback = function()
                UIManager:close(dialog)
                promptMigration(appdock, function(ready) if ready and context and context.requestRebuild then context.requestRebuild("ui") end end)
            end } },
            { { text = _("Saved app list") .. " (" .. tostring(status.pending_installation_count) .. ")", callback = function()
                UIManager:close(dialog)
                local current = Account.get(appdock)
                local rows = {}
                for _, record in ipairs(current.pending_installations or {}) do
                    if type(record) == "table" then
                        rows[#rows + 1] = safeText(record.id, 72)
                            .. (record.version and record.version ~= "" and (" · " .. safeText(record.version, 24)) or "")
                            .. (record.source_path and record.source_path ~= "" and ("\n" .. safeText(record.source_path, 160)) or "")
                    end
                end
                table.sort(rows)
                showNotice(#rows > 0
                    and (_("Apps remembered from the previous reader. AppStore installs remain individual, explicit actions:") .. "\n\n" .. table.concat(rows, "\n\n"))
                    or _("No saved AppStore installation list is available yet."))
            end } },
            { { text = _("How migration works"), callback = function()
                UIManager:close(dialog)
                showNotice(_("To set up a new reader, enter the Account ID shown here and the recovery code that was displayed when the account was created. The code cannot be shown again for security reasons."))
            end } },
            { { text = _("Done"), callback = function() UIManager:close(dialog) end } },
        },
    }
    UIManager:show(dialog)
    return true
end

Account._test = {
    normalize = normalizedSession,
    buildSnapshot = Account.buildSnapshot,
    snapshotFromResponse = snapshotFromResponse,
    installManifest = installManifest,
}

return Account
