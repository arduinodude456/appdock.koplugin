-- Run with: lua test_sleepscreen_presets.lua
-- This uses only a temporary DataStorage root and mocks KOReader's JSON module.

local lfs = require("lfs")
local cjson = require("cjson")
local base = os.tmpname() .. "-appdock-sleepscreen"
assert(lfs.mkdir(base))

package.loaded.datastorage = nil
package.preload.datastorage = function()
    return { getDataDir = function() return base end }
end
package.loaded.json = nil
package.preload.json = function()
    return {
        encode = function(value) return cjson.encode(value) end,
        decode = function(value) return cjson.decode(value) end,
    }
end
-- The production module uses rapidjson.array where available.  This minimal
-- mock proves it remains compatible with an ordinary Lua 5.1 table API.
package.loaded.rapidjson = nil
package.preload.rapidjson = function()
    return { array = function(value) return value end }
end

local Presets = dofile("./appdock.koplugin/appdock_sleepscreen_presets.lua")

local function rmTree(path)
    local mode = lfs.attributes(path, "mode")
    if mode == "directory" then
        for name in lfs.dir(path) do
            if name ~= "." and name ~= ".." then rmTree(path .. "/" .. name) end
        end
        assert(os.remove(path))
    elseif mode then
        assert(os.remove(path))
    end
end

local function baseDefinition()
    return {
        schema_version = 1,
        name = "Test Sleep",
        description = "Validated local test definition.",
        background = "#ffffff",
        assets = {},
        elements = {
            { type = "text", x = 0, y = 0, w = 100, h = 10, text = "{time}", font = "cfont", font_size = 16, color = "#010203", align = "left" },
        },
        ignored = "must not survive normalize",
    }
end

local normalized = assert(Presets.normalize(baseDefinition()))
assert(normalized.background == "#FFFFFF" and normalized.ignored == nil)
assert(not Presets.normalize({ schema_version = 1, name = "bad", description = "", background = "#FFFFFF", assets = {}, elements = {
    { type = "text", x = 90, y = 0, w = 11, h = 5, text = "no" },
} }), "out-of-bounds elements must be rejected")
assert(not Presets.normalize({ schema_version = 1, name = "bad", description = "", background = "#FFFFFF", assets = {}, elements = {
    { type = "image", x = 0, y = 0, w = 20, h = 20, images = { "missing" } },
} }), "unknown image references must be rejected")
local too_long = baseDefinition()
too_long.elements[1].text = string.rep("x", 2001)
assert(not Presets.normalize(too_long), "element text must have a bounded size")

local source_png = base .. "/source.png"
local source = assert(io.open(source_png, "wb"))
source:write("\137PNG\r\n\26\n" .. string.rep("x", 40))
source:close()
local invalid_png = base .. "/invalid.png"
local invalid = assert(io.open(invalid_png, "wb"))
invalid:write("not a png")
invalid:close()

local draft = Presets.newDraft("Local Image")
assert(not Presets.importAsset(draft, invalid_png, "image"), "invalid signatures must fail before copying")
local image_id = assert(Presets.importAsset(draft, source_png, "image"))
assert(draft.asset_paths[image_id] and draft.definition.assets[1].id == image_id)
table.insert(draft.definition.elements, {
    type = "image", x = 10, y = 20, w = 80, h = 60, images = { image_id }, fit = "cover",
})
local appdock = { settings = {}, _saveSettings = function(self) self.saved = (self.saved or 0) + 1 end }
local record = assert(Presets.saveDraft(appdock, draft))
assert(record.id and record.asset_paths[image_id] ~= source_png)
assert(#Presets.listLocal(appdock) == 1)
assert(Presets.activate(appdock, record.id) and appdock.settings.sleepscreen_enabled)
assert(Presets.getActive(appdock).id == record.id)

local package = assert(Presets.exportPackage(record))
assert(package.assets[image_id] and not package.assets[image_id]:find("\n", 1, true), "package assets are MIME base64 data")
local before_fail = #Presets.listLocal(appdock)
local invalid_package = { definition = package.definition, assets = {} }
invalid_package.assets[image_id] = "AAAA"
assert(not Presets.installPackage(appdock, invalid_package, { id = "remote-1", revision = 1 }), "bad imported signature must fail")
assert(#Presets.listLocal(appdock) == before_fail, "failed imports must not alter existing registry entries")
local extra_package = { definition = package.definition, assets = {} }
extra_package.assets[image_id] = package.assets[image_id]
extra_package.assets.unexpected = package.assets[image_id]
assert(not Presets.installPackage(appdock, extra_package), "undeclared package assets must fail")

local installed = assert(Presets.installPackage(appdock, package, {
    id = "remote-1",
    revision = 2,
    creator = { account_id = "account-1", display_name = "Creator" },
}))
assert(installed.remote_id == "remote-1" and installed.revision == 2 and installed.creator.display_name == "Creator")
assert(#Presets.listLocal(appdock) == before_fail + 1)

record.remote_id, record.revision = "published-1", 3
record.creator = { account_id = "account-1", display_name = "Creator" }
record = assert(Presets.saveDraft(appdock, record, record.id))
assert(Presets.getActive(appdock).revision == 3, "a successful publish must persist its current revision")
record.remote_id, record.revision, record.creator = nil, nil, nil
record = assert(Presets.saveDraft(appdock, record, record.id))
assert(Presets.getActive(appdock).remote_id == nil, "unpublish must persist the removed public identity")

local fork = assert(Presets.saveDraft(appdock, record))
assert(Presets.remove(appdock, record.id))
assert(Presets.exportPackage(fork), "removing an original must preserve media referenced by a saved fork")
assert(Presets.activate(appdock, fork.id))

-- An imported but unused draft asset may exist while editing, but it can never
-- be published/exported after its image element has been removed.
local unused = Presets.newDraft("Unused")
local unused_id = assert(Presets.importAsset(unused, source_png, "image"))
local unused_record = assert(Presets.saveDraft(appdock, unused))
local filtered_package = assert(Presets.exportPackage(unused_record))
assert(#filtered_package.definition.assets == 0 and not filtered_package.assets[unused_id], "unreferenced local assets must not enter a package")
assert(unused_record.asset_paths[unused_id])

assert(Presets.remove(appdock, fork.id))
assert(appdock.settings.sleepscreens.active_id == nil, "removing the active record must restore the default selection")
assert(not Presets.getActive({ settings = { sleepscreens = { active_id = "../unsafe" } } }), "unsafe active ids must never be used")
assert(appdock.saved and appdock.saved >= 2)

rmTree(base)
print("sleepscreen-presets-ok")
