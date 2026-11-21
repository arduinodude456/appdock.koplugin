-- Server-backed DockAI adapter. API keys never enter local settings or UI lists.
return function(DockAI)
    local trim = function(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
    local originalNew = DockAI.new
    DockAI.PROXY_ENDPOINT = "https://qndwbriqomqqaqhkasbh.supabase.co/functions/v1/dockai"

    function DockAI:new(appdock, opts)
        local object = originalNew(self, appdock, opts)
        -- Remove secrets/counters created by earlier local-only releases.
        object:_set("keys", nil); object:_set("key_index", nil); object:_set("usage", nil); object:flush()
        object.server_usage, object.server_usage_error, object.admin_until = nil, nil, nil
        return object
    end

    function DockAI:_serverRequest(payload)
        local account = require("appdock_tbs_account").get(self.appdock)
        if not account or account.account_id == "" or account.device_id == "" or account.device_secret == "" then return nil, "auth_required" end
        local ok, body = pcall(self.json.encode, payload)
        if not ok or type(body) ~= "string" then return nil, "bad_request" end
        local code, raw = self.transport(DockAI.PROXY_ENDPOINT, {
            ["Content-Type"] = "application/json", ["Accept"] = "application/json", ["Content-Length"] = tostring(#body),
            ["apikey"] = account.publishable_key,
            ["x-tbs-account-id"] = account.account_id, ["x-tbs-device-id"] = account.device_id,
            ["x-tbs-device-secret"] = account.device_secret,
        }, body)
        if type(code) ~= "number" then return nil, "network" end
        local decoded, response = pcall(self.json.decode, raw or "{}")
        if not decoded or type(response) ~= "table" then return nil, "bad_response" end
        return response, nil, code
    end

    function DockAI:keys() return {} end
    function DockAI:removeKey() return false end
    function DockAI:importKeys() return nil end
    function DockAI:reviveKeys() end
    function DockAI:setLimits() end
    function DockAI:getLimits() return DockAI.DEFAULT_DAILY_LIMIT, DockAI.DEFAULT_WEEKLY_LIMIT end
    function DockAI:recordUse() end
    function DockAI:resetUsage() self:refreshUsage(true) end

    -- The pane is rebuilt after every tap, so this must not hit the network
    -- each time (a slow connection froze the whole chat). The result is reused
    -- for a minute; after a failure the next try waits 20 seconds.
    function DockAI:refreshUsage(force)
        local now = self.now()
        if not force and self.usage_checked_at and now < self.usage_checked_at then
            return self.server_usage
        end
        local ok, response, err, code = pcall(self._serverRequest, self, { action = "usage" })
        if not ok then response, err, code = nil, "network", nil end
        if response and code == 200 and type(response.usage) == "table" then
            self.server_usage, self.server_usage_error = response.usage, nil
            self.usage_checked_at = now + 60
            return self.server_usage
        end
        self.server_usage_error = err or (response and response.error and response.error.code) or "network"
        self.usage_checked_at = now + 20
        return nil, self.server_usage_error
    end

    function DockAI:usage()
        local v = self.server_usage or {}
        local info = {
            day_used = tonumber(v.day_used) or 0, day_limit = tonumber(v.day_limit) or DockAI.DEFAULT_DAILY_LIMIT,
            week_used = tonumber(v.week_used) or 0, week_limit = tonumber(v.week_limit) or DockAI.DEFAULT_WEEKLY_LIMIT,
            day_resets_at = tonumber(v.day_resets_at) or self.now() + 86400,
            week_resets_at = tonumber(v.week_resets_at) or self.now() + 7 * 86400,
            blocked = v.blocked,
        }
        info.day_left = math.max(0, info.day_limit - info.day_used)
        info.week_left = math.max(0, info.week_limit - info.week_used)
        info.left = math.min(info.day_left, info.week_left)
        if not info.blocked then
            if info.week_left <= 0 then info.blocked = "week" elseif info.day_left <= 0 then info.blocked = "day" end
        end
        return info
    end

    function DockAI:limitText(info)
        info = info or self:usage()
        if self.server_usage_error == "auth_required" then
            return self:tr("Bitte zuerst bei einem TBS-Konto anmelden.", "Sign in to a TBS account to use DockAI.")
        elseif info.blocked == "week" then
            return string.format(self:tr("Wochenlimit erreicht (%d/%d) · neu ab Montag UTC", "Weekly limit reached (%d/%d) · resets Monday UTC"), info.week_used, info.week_limit)
        elseif info.blocked == "day" then
            return string.format(self:tr("Tageslimit erreicht (%d/%d) · neu um Mitternacht UTC", "Daily limit reached (%d/%d) · resets at midnight UTC"), info.day_used, info.day_limit)
        end
        return string.format(self:tr("Heute %d/%d · Woche %d/%d Nachrichten", "Today %d/%d · Week %d/%d messages"), info.day_used, info.day_limit, info.week_used, info.week_limit)
    end

    function DockAI:complete(history)
        -- Last DockAI.CONTEXT_MESSAGES messages (5) plus the saved memories.
        local messages = self:contextMessages(history)
        if #messages == 0 then return nil, "bad_response" end
        local response, err, code = self:_serverRequest({ action = "chat", model = self:getModel(), messages = messages })
        if response and response.usage then
            self.server_usage = response.usage
            self.usage_checked_at = self.now() + 60
        end
        if not response then return nil, err end
        if code == 200 and type(response.reply) == "string" and response.reply ~= "" then return response.reply end
        local e = response.error or {}
        if e.code == "limit" then return nil, "limit" end
        if e.code == "auth_required" then return nil, "auth_required" end
        if e.code == "no_keys" then return nil, "no_keys" end
        if e.code == "provider" then return nil, "all_keys_failed" end
        return nil, code == 502 and "network" or "bad_response"
    end

    function DockAI:addKey(key, password)
        key = trim(key)
        if #key < 20 or #key > 200 or key:find("%s") or not key:match("^[%w_%-%.]+$") then return false, "invalid" end
        local response, err, code = self:_serverRequest({ action = "add_key", admin_password = password, api_key = key })
        if not response then return false, err end
        if code == 200 and response.added then return true end
        local e = response.error or {}
        if e.code == "duplicate" then return false, "duplicate" end
        if e.code == "admin_denied" then return false, "wrong_password" end
        if e.code == "invalid_input" then return false, "invalid" end
        return false, "server_error"
    end

    function DockAI:checkPassword() return false end
    function DockAI:unlockAdmin() return false end
    function DockAI:isAdmin() return false end
    function DockAI:lockAdmin() self.admin_password = nil end
    function DockAI:openAdmin(refresh) self:showAdminDialog(refresh) end
    function DockAI:showKeyList()
        self:_toast(self:tr("API-Keys sind in AppDock weder sichtbar noch löschbar.", "API keys cannot be viewed or removed in AppDock."))
    end
    function DockAI:showAdminDialog(refresh)
        local U = require("ui/uimanager")
        local ButtonDialog = require("ui/widget/buttondialog")
        local dialog
        local buttons = {
            { { text = self:tr("API-Key hinzufügen", "Add API key"), callback = function()
                U:close(dialog)
                self:_promptText(self:tr("Admin-Passwort", "Admin password"), self:tr("Passwort", "Password"), "", { secure = true }, function(password)
                    self:_promptText(self:tr("Groq API-Key", "Groq API key"), "gsk_…", "", { secure = true }, function(key)
                        local ok, reason = self:addKey(key, password)
                        self:_toast(ok and self:tr("Key sicher auf dem Server gespeichert.", "API key saved securely on the server.")
                            or (reason == "duplicate" and self:tr("Diesen Key gibt es bereits.", "This key already exists.")
                            or (reason == "wrong_password" and self:tr("Admin-Passwort falsch.", "Incorrect admin password.")
                            or self:tr("Key konnte nicht hinzugefügt werden. Konto/Verbindung prüfen.", "Could not add key. Check account/connection."))))
                        if refresh then pcall(refresh) end
                        self:showAdminDialog(refresh)
                    end)
                end)
            end } },
            { { text = self:tr("Schließen", "Close"), callback = function() U:close(dialog); if refresh then pcall(refresh) end end } },
        }
        dialog = ButtonDialog:new{ title = self:tr("DockAI Admin · nur hinzufügen", "DockAI admin · add only"), buttons = buttons }
        U:show(dialog)
    end

    function DockAI:showModelPicker(after)
        local U = require("ui/uimanager")
        local ButtonDialog = require("ui/widget/buttondialog")
        local dialog
        local buttons = {}
        local current = self:getModel()
        for _, id in ipairs(DockAI.FALLBACK_MODELS) do
            buttons[#buttons + 1] = { { text = (id == current and "✓ " or "") .. id, callback = function()
                self:setModel(id); U:close(dialog); if after then after() end
            end } }
        end
        buttons[#buttons + 1] = { { text = self:tr("Schließen", "Close"), callback = function() U:close(dialog) end } }
        dialog = ButtonDialog:new{ title = self:tr("Modell wählen", "Choose a model"), buttons = buttons }
        U:show(dialog)
    end

    function DockAI:errorText(code)
        if code == "auth_required" then return self:tr("Bitte melde dich zuerst bei einem TBS-Konto an.", "Please sign in to a TBS account first.") end
        if code == "limit" then return self:limitText(self:usage()) end
        if code == "no_keys" then return self:tr("DockAI ist noch nicht eingerichtet. Der Admin kann einen API-Key hinzufügen.", "DockAI is not set up yet. The admin can add an API key.") end
        if code == "network" then return self:tr("Verbindung fehlgeschlagen. Diese Anfrage wurde nicht gezählt.", "Connection failed. This request was not counted.") end
        if code == "all_keys_failed" then return self:tr("Alle API-Keys sind ausgelastet oder ungültig. Bitte später erneut versuchen.", "All API keys are busy or invalid. Please try again later.") end
        return self:tr("DockAI konnte die Anfrage nicht bearbeiten.", "DockAI could not process the request.")
    end

    local oldBuildPane = DockAI.buildPane
    function DockAI:buildPane(instance, context)
        self:refreshUsage()
        return oldBuildPane(self, instance, context)
    end
    local oldSettingsRows = DockAI.settingsRows
    function DockAI:settingsRows(context)
        self:refreshUsage()
        local rows = oldSettingsRows(self, context)
        local admin = rows and rows[#rows]
        if admin then
            admin.title = self:tr("Admin: API-Key hinzufügen", "Admin: add API key")
            admin.subtitle = self:tr("Passwort erforderlich · keine Einsicht/Entfernung", "Password required · cannot view/remove")
        end
        return rows
    end
    return DockAI
end
