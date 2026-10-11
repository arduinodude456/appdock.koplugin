local plugin_dir = os.getenv("APPDOCK_PLUGIN_DIR") or "appdock.koplugin/"
local Database = dofile(plugin_dir .. "appdock_suggestions.lua")
local all = Database.get()
local german, english = 0, 0
for _, item in ipairs(all) do
    assert((item.language == "de" or item.language == "en") and item.word ~= "" and item.frequency > 0)
    if item.language == "de" then german = german + 1 else english = english + 1 end
end
assert(german >= 1000 and english >= 1000, "The suggestion database must contain both languages")
assert(Database.get("de")[1].language == "de" and Database.get("en")[1].language == "en", "Language filtering must work")
assert(Database.databasePath():match("appdock_suggestions%.db$"), "Database path must point to the editable TSV database")
print("Suggestion database test: OK")
