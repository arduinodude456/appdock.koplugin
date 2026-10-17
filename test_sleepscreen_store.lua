local plugin_dir = os.getenv("APPDOCK_PLUGIN_DIR") or "./appdock.koplugin/"
package.path = plugin_dir .. "?.lua;" .. package.path

local account = {
    endpoint = "https://example.test/functions/v1/tbs-account",
    publishable_key = "sb_publishable_example_key",
    account_id = "e7c931e2-0a70-4a53-96f3-e7947939f7b9",
    device_id = "tbs_abcdefghijklmnopqrstuv",
    device_secret = "abcdefghijklmnopqrstuvwxzy0123456789AB",
}
local response_payload
local network = {}
local encoded_size

package.preload["appdock_tbs_account"] = function()
    return { get = function() return account end }
end
package.preload["socket.url"] = function()
    return { parse = function(value)
        local scheme, host = tostring(value):match("^(https?)://([^/%?#]+)")
        return scheme and { scheme = scheme, host = host } or nil
    end }
end
package.preload["ltn12"] = function()
    return { source = { string = function(body) return body end } }
end
package.preload["socketutil"] = function()
    return { set_timeout = function() end, reset_timeout = function() end }
end
package.preload["json"] = function()
    local decoder = setmetatable({ simple = {} }, { __call = function() return response_payload end })
    return {
        encode = function(payload)
            network.payload = payload
            if encoded_size then return string.rep("x", encoded_size) end
            return "{}"
        end,
        decode = decoder,
    }
end
package.preload["ssl.https"] = function()
    return { request = function(options)
        network.options = options
        local accepted, sink_err = options.sink("mock-response")
        assert(accepted, sink_err)
        return true, 200, {}, "HTTP/1.1 200 OK"
    end }
end

local Store = require("appdock_sleepscreen_store")
local id = "a7c931e2-0a70-4a53-96f3-e7947939f7b9"
local entry = {
    id = id,
    name = "Paper clock",
    description = "Plain",
    creator = { account_id = account.account_id, display_name = "Reader" },
    revision = 1,
    definition = { schema_version = 1, elements = {}, assets = {} },
}

assert(Store._test.endpointFor(account) == "https://example.test/functions/v1/tbs-sleepscreens", "store endpoint must replace only final /tbs-account")
local broken = {}
for key, value in pairs(account) do broken[key] = value end
broken.endpoint = "https://example.test/functions/v1/not-account"
assert(Store._test.endpointFor(broken) == nil, "store must not derive arbitrary sibling endpoints")

response_payload = { entries = { entry }, has_more = false }
local listed, list_err = Store.list({}, " paper ", 0)
assert(listed, list_err)
assert(#listed.entries == 1 and network.payload.action == "list", "public list must use the documented action")
assert(network.options.url == "https://example.test/functions/v1/tbs-sleepscreens", "list must target the derived endpoint")
assert(network.options.headers["apikey"] == account.publishable_key, "public calls must send the publishable key")
assert(network.options.headers["x-tbs-device-secret"] == nil, "public list must never send device credentials")

response_payload = { entry = entry, package = { definition = entry.definition, assets = {} } }
local downloaded, get_err = Store.get({}, id)
assert(downloaded, get_err)
assert(network.payload.action == "get" and network.payload.id == id, "get must use the documented payload")
assert(network.options.headers["x-tbs-device-secret"] == nil, "public get must never send device credentials")

response_payload = { entry = entry }
local package = { definition = entry.definition, assets = { cover = "iVBORw0KGgo=" } }
local published, publish_err = Store.publish({}, package)
assert(published, publish_err)
assert(network.payload.action == "publish" and network.payload.package == package, "publish must preserve the package without snapshot copying")
assert(network.options.headers["x-tbs-account-id"] == account.account_id, "private publish must send only header credentials")
assert(network.options.headers["x-tbs-device-id"] == account.device_id and network.options.headers["x-tbs-device-secret"] == account.device_secret,
    "private publish must authenticate with the opaque device pair")

response_payload = { ok = true }
local unpublished, unpublish_err = Store.unpublish({}, id, 1)
assert(unpublished, unpublish_err)
assert(network.payload.action == "unpublish" and network.payload.expected_revision == 1, "unpublish must send its CAS revision")

-- A package encoded to the full documented 9 MiB request cap is accepted.  This
-- specifically guards against accidentally routing it through Account.apiRequest
-- (which has a much smaller snapshot cap).
encoded_size = Store._test.MAX_REQUEST_BYTES
response_payload = { entry = entry }
local at_limit, at_limit_err = Store.publish({}, package)
assert(at_limit, at_limit_err)
assert(network.options.headers["content-length"] == tostring(Store._test.MAX_REQUEST_BYTES), "the bounded client must support a 9 MiB package request")
encoded_size = Store._test.MAX_REQUEST_BYTES + 1
local too_large, too_large_err = Store.publish({}, package)
assert(too_large == nil and tostring(too_large_err):find("too large", 1, true), "oversized requests must fail locally and bounded")

print("Sleepscreen store test: OK")
