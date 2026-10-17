--[[
Declarative local Sleepscreen presets.

The registry deliberately lives outside AppDock settings: settings only retain the
active local id.  This keeps binary asset data and editable layouts out of the
normal settings file and makes an interrupted write recoverable.
--]]

local DataStorage = require("datastorage")
local JSON = require("json")
local mime = require("mime")
local has_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
if not has_lfs then lfs = require("lfs") end
local has_rapidjson, rapidjson = pcall(require, "rapidjson")

local Presets = {}

local MAX_ELEMENTS = 32
local MAX_ASSETS = 12
local MAX_IMAGE_BYTES = 2 * 1024 * 1024
local MAX_FONT_BYTES = 1024 * 1024
local MAX_ASSET_BYTES = 6 * 1024 * 1024
local MAX_PACKAGE_BYTES = 9 * 1024 * 1024
-- Keep this bounded independently of the 500-character description.  The
-- backend uses the same 2000-byte element text ceiling.
local MAX_TEXT_BYTES = 2000

local BUILTIN_FONTS = { cfont = true, infofont = true, smallinfofont = true }
local IMAGE_EXTENSIONS = { png = true, jpg = true, jpeg = true, webp = true }
local FONT_EXTENSIONS = { ttf = true, otf = true }
local ELEMENT_TYPES = { text = true, card = true, widget = true, image = true }
local WIDGET_SOURCES = { clock = true, date = true, battery = true, device = true }
local ALIGNMENTS = { left = true, center = true, right = true }
local FITS = { contain = true, cover = true }

local function fail(message)
    return nil, message
end

-- rapidjson distinguishes an empty [] from an empty {}.  Definitions have
-- arrays for assets/elements whereas package.assets and registry.records are
-- objects, so only use this marker for arrays.
local function newArray()
    if has_rapidjson and type(rapidjson.array) == "function" then return rapidjson.array({}) end
    return {}
end

local function isFiniteNumber(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isInteger(value)
    return isFiniteNumber(value) and value == math.floor(value)
end

local function isId(value)
    return type(value) == "string" and #value >= 1 and #value <= 64
        and value:match("^[A-Za-z0-9_-]+$") ~= nil
end

local function isLocalId(value)
    return isId(value) and #value <= 80
end

local function isColor(value)
    return type(value) == "string" and value:match("^#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$") ~= nil
end

local function asArray(value, limit)
    if type(value) ~= "table" then return nil end
    local count = #value
    if count > limit then return nil end
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key > count or key ~= math.floor(key) then return nil end
    end
    return count
end

local function extensionOf(path)
    if type(path) ~= "string" then return nil end
    local extension = path:match("%.([A-Za-z0-9]+)$")
    return extension and extension:lower() or nil
end

local function expectedKindForExtension(extension)
    if IMAGE_EXTENSIONS[extension] then return "image" end
    if FONT_EXTENSIONS[extension] then return "font" end
    return nil
end

local function assetLimit(kind)
    return kind == "image" and MAX_IMAGE_BYTES or MAX_FONT_BYTES
end

local function sleepRoot()
    local root = DataStorage:getDataDir()
    if type(root) ~= "string" or root == "" or root:find("%z") then return nil end
    return root .. "/appdock_sleepscreens"
end

local function ensureDirectory(path)
    if not path then return nil, "local data directory unavailable" end
    if lfs.attributes(path, "mode") == "directory" then return true end
    local ok, err = lfs.mkdir(path)
    if ok or lfs.attributes(path, "mode") == "directory" then return true end
    return nil, err or "could not create local data directory"
end

local function ensureStorage()
    local root = sleepRoot()
    local ok, err = ensureDirectory(root)
    if not ok then return nil, err end
    ok, err = ensureDirectory(root .. "/assets")
    if not ok then return nil, err end
    return root
end

local nonce = 0
local function newId(prefix)
    -- The identifier is only a local file/registry name, never an authority
    -- token.  The changing nonce avoids collisions even on devices without a
    -- useful random source.
    nonce = nonce + 1
    local random = math.random(0, 0x7fffffff)
    return string.format("%s-%08x-%08x-%04x", prefix, os.time() % 0x7fffffff, random, nonce % 0xffff)
end

local function safeManagedPath(root, path, extension)
    if type(path) ~= "string" or not root or path:find("%z") or path:find("..", 1, true) then return false end
    local base = root .. "/assets/"
    if path:sub(1, #base) ~= base then return false end
    if not path:match("^[%w%._/%-]+$") then return false end
    return extensionOf(path) == extension
end

local function readBounded(path, maximum)
    if type(path) ~= "string" or path:find("%z") then return nil, "invalid asset path" end
    local file, open_err = io.open(path, "rb")
    if not file then return nil, open_err or "could not read asset" end
    local data = file:read(maximum + 1)
    local close_ok = file:close()
    if not data or not close_ok then return nil, "could not read asset" end
    if #data > maximum then return nil, "asset exceeds its size limit" end
    return data
end

local function hasAssetSignature(data, kind, extension)
    if type(data) ~= "string" or #data == 0 then return false end
    if kind == "image" then
        if extension == "png" then return data:sub(1, 8) == "\137PNG\r\n\26\n" end
        if extension == "jpg" or extension == "jpeg" then return data:sub(1, 3) == "\255\216\255" end
        if extension == "webp" then return data:sub(1, 4) == "RIFF" and data:sub(9, 12) == "WEBP" end
    elseif kind == "font" then
        if extension == "ttf" then
            local signature = data:sub(1, 4)
            return signature == "\000\001\000\000" or signature == "true" or signature == "typ1"
        end
        if extension == "otf" then return data:sub(1, 4) == "OTTO" end
    end
    return false
end

local function readVerifiedAsset(path, asset)
    local data, err = readBounded(path, assetLimit(asset.kind))
    if not data then return nil, err end
    if not hasAssetSignature(data, asset.kind, asset.extension) then
        return nil, "asset signature does not match declared type"
    end
    return data
end

local function copyTable(source)
    local result = {}
    for key, value in pairs(source or {}) do result[key] = value end
    return result
end

local function atomicWrite(path, data)
    local temporary = path .. ".tmp-" .. newId("write")
    local file, open_err = io.open(temporary, "wb")
    if not file then return nil, open_err or "could not open local registry" end
    local wrote, write_err = file:write(data)
    if file.flush then file:flush() end
    local close_ok, close_err = file:close()
    if not wrote or not close_ok then
        os.remove(temporary)
        return nil, write_err or close_err or "could not write local registry"
    end
    if not os.rename(temporary, path) then
        os.remove(temporary)
        return nil, "could not replace local registry"
    end
    return true
end

local function encodeJSON(value)
    local ok, encoded = pcall(JSON.encode, value)
    if not ok or type(encoded) ~= "string" then return nil, "could not encode JSON" end
    return encoded
end

local function decodeJSON(data)
    if type(data) ~= "string" or #data > MAX_PACKAGE_BYTES then return nil, "invalid JSON data" end
    local ok, decoded, err = pcall(JSON.decode, data)
    if not ok or type(decoded) ~= "table" then return nil, err or "invalid JSON data" end
    return decoded
end

local function registryPath(root)
    return root .. "/registry.json"
end

local function loadRegistry(root)
    local file = io.open(registryPath(root), "rb")
    if not file then return { version = 1, records = {} } end
    local data = file:read(MAX_PACKAGE_BYTES + 1)
    file:close()
    if not data or #data > MAX_PACKAGE_BYTES then return { version = 1, records = {} } end
    local decoded = decodeJSON(data)
    if type(decoded) ~= "table" or decoded.version ~= 1 or type(decoded.records) ~= "table" then
        -- A corrupt registry is never overwritten until a caller explicitly
        -- saves something.  Existing managed assets remain untouched.
        return { version = 1, records = {} }
    end
    return decoded
end

local function saveRegistry(root, registry)
    local encoded, err = encodeJSON(registry)
    if not encoded then return nil, err end
    if #encoded > MAX_PACKAGE_BYTES then return nil, "local registry is too large" end
    return atomicWrite(registryPath(root), encoded)
end

local function normalizeAsset(asset)
    if type(asset) ~= "table" or not isId(asset.id) then return nil, "invalid asset id" end
    if asset.kind ~= "image" and asset.kind ~= "font" then return nil, "invalid asset kind" end
    if type(asset.extension) ~= "string" then return nil, "invalid asset extension" end
    local extension = asset.extension:lower()
    if expectedKindForExtension(extension) ~= asset.kind then return nil, "asset extension does not match asset kind" end
    return { id = asset.id, kind = asset.kind, extension = extension }
end

local function normalizeElement(element, asset_by_id)
    if type(element) ~= "table" or not ELEMENT_TYPES[element.type] then return nil, "invalid element type" end
    local result = { type = element.type }
    for _, key in ipairs({ "x", "y", "w", "h" }) do
        if not isFiniteNumber(element[key]) then return nil, "invalid element bounds" end
        result[key] = element[key]
    end
    if result.x < 0 or result.y < 0 or result.w <= 0 or result.h <= 0
        or result.x + result.w > 100 or result.y + result.h > 100 then
        return nil, "element bounds must remain within 0..100 percent"
    end

    if element.text ~= nil then
        if type(element.text) ~= "string" or #element.text > MAX_TEXT_BYTES then return nil, "invalid element text" end
        result.text = element.text
    end
    if element.color ~= nil then
        if not isColor(element.color) then return nil, "invalid element color" end
        result.color = element.color:upper()
    end
    if element.background ~= nil then
        if not isColor(element.background) then return nil, "invalid element background" end
        result.background = element.background:upper()
    end
    if element.bold ~= nil then
        if type(element.bold) ~= "boolean" then return nil, "invalid element bold value" end
        result.bold = element.bold
    end
    if element.align ~= nil then
        if not ALIGNMENTS[element.align] then return nil, "invalid element alignment" end
        result.align = element.align
    end
    if element.fit ~= nil then
        if result.type ~= "image" or not FITS[element.fit] then return nil, "invalid image fit" end
        result.fit = element.fit
    end
    if element.font_size ~= nil then
        if not isInteger(element.font_size) or element.font_size < 8 or element.font_size > 96 then
            return nil, "invalid font size"
        end
        result.font_size = element.font_size
    end
    if element.font ~= nil then
        if type(element.font) ~= "string" then return nil, "invalid font" end
        if BUILTIN_FONTS[element.font] then
            result.font = element.font
        else
            local font_id = element.font:match("^asset:([A-Za-z0-9_-]+)$")
            if not font_id or not asset_by_id[font_id] or asset_by_id[font_id].kind ~= "font" then
                return nil, "unknown font asset"
            end
            result.font = "asset:" .. font_id
        end
    end
    if element.source ~= nil then
        if result.type ~= "widget" or not WIDGET_SOURCES[element.source] then return nil, "invalid widget source" end
        result.source = element.source
    end
    if element.images ~= nil then
        if result.type ~= "image" then return nil, "only image elements may reference images" end
        local count = asArray(element.images, MAX_ASSETS)
        if not count or count == 0 then return nil, "invalid image asset list" end
        result.images = {}
        local seen = {}
        for index, asset_id in ipairs(element.images) do
            if not isId(asset_id) or seen[asset_id] or not asset_by_id[asset_id] or asset_by_id[asset_id].kind ~= "image" then
                return nil, "unknown image asset"
            end
            seen[asset_id] = true
            result.images[index] = asset_id
        end
    end

    if result.type == "widget" and not result.source then return nil, "widget requires a source" end
    if result.type == "image" and not result.images then return nil, "image requires an image asset" end
    if (result.type == "text" or result.type == "card") and result.text == nil then
        return nil, "text and card elements require text"
    end
    return result
end

-- Validate every field accepted by the public JSON definition.  The returned
-- table is newly allocated so unknown fields can never flow into a renderer.
function Presets.normalize(definition)
    if type(definition) ~= "table" or definition.schema_version ~= 1 then return fail("unsupported sleepscreen schema") end
    if type(definition.name) ~= "string" or #definition.name < 1 or #definition.name > 80 then return fail("invalid preset name") end
    if definition.description ~= nil and (type(definition.description) ~= "string" or #definition.description > 500) then
        return fail("invalid preset description")
    end
    if not isColor(definition.background) then return fail("invalid background color") end
    local asset_count = asArray(definition.assets, MAX_ASSETS)
    local element_count = asArray(definition.elements, MAX_ELEMENTS)
    if asset_count == nil or element_count == nil then return fail("invalid element or asset list") end

    local result = {
        schema_version = 1,
        name = definition.name,
        description = definition.description or "",
        background = definition.background:upper(),
        assets = newArray(),
        elements = newArray(),
    }
    local asset_by_id = {}
    for index, asset in ipairs(definition.assets) do
        local normalized, err = normalizeAsset(asset)
        if not normalized then return fail(err) end
        if asset_by_id[normalized.id] then return fail("duplicate asset id") end
        asset_by_id[normalized.id] = normalized
        result.assets[index] = normalized
    end
    for index, element in ipairs(definition.elements) do
        local normalized, err = normalizeElement(element, asset_by_id)
        if not normalized then return fail(err) end
        result.elements[index] = normalized
    end
    return result
end

function Presets.defaultPreset()
    return {
        schema_version = 1,
        name = "AppDock Sleep",
        description = "A simple local AppDock sleep screen.",
        background = "#FFFFFF",
        assets = newArray(),
        elements = {
            { type = "text", x = 10, y = 39, w = 80, h = 12, text = "AppDock", font = "cfont", font_size = 30, color = "#000000", bold = true, align = "center" },
            { type = "text", x = 10, y = 53, w = 80, h = 8, text = "{sleeping}", font = "infofont", font_size = 18, color = "#000000", align = "center" },
        },
    }
end

function Presets.newDraft(name)
    local definition = Presets.defaultPreset()
    if name ~= nil then
        if type(name) == "string" and #name >= 1 and #name <= 80 then definition.name = name end
    end
    return { definition = definition, asset_paths = {} }
end

local function normalizedRecord(root, id, raw)
    if not isLocalId(id) or type(raw) ~= "table" then return nil end
    local definition = Presets.normalize(raw.definition)
    if not definition or type(raw.asset_paths) ~= "table" then return nil end
    local paths, declared = {}, {}
    for _, asset in ipairs(definition.assets) do declared[asset.id] = asset end
    for asset_id, path in pairs(raw.asset_paths) do
        local asset = declared[asset_id]
        if not asset or not safeManagedPath(root, path, asset.extension) then return nil end
        paths[asset_id] = path
    end
    -- Local records are complete layouts; an asset path must exist for every
    -- declared asset.  This avoids rendering a path that has escaped storage.
    for asset_id in pairs(declared) do if not paths[asset_id] then return nil end end
    local record = { id = id, definition = definition, asset_paths = paths }
    if type(raw.remote_id) == "string" and #raw.remote_id <= 80 and raw.remote_id:match("^[A-Za-z0-9%-]+$") then record.remote_id = raw.remote_id end
    if isInteger(raw.revision) and raw.revision >= 1 then record.revision = raw.revision end
    if type(raw.creator) == "table" then
        local creator = {}
        if type(raw.creator.account_id) == "string" and #raw.creator.account_id <= 128 then creator.account_id = raw.creator.account_id end
        if type(raw.creator.display_name) == "string" and #raw.creator.display_name <= 160 then creator.display_name = raw.creator.display_name end
        if next(creator) then record.creator = creator end
    end
    return record
end

function Presets.listLocal(appdock)
    local root = ensureStorage()
    if not root then return {} end
    local registry = loadRegistry(root)
    local records = {}
    for id, raw in pairs(registry.records or {}) do
        local record = normalizedRecord(root, id, raw)
        if record then table.insert(records, record) end
    end
    table.sort(records, function(left, right)
        local left_name, right_name = left.definition.name:lower(), right.definition.name:lower()
        return left_name == right_name and left.id < right.id or left_name < right_name
    end)
    return records
end

local function findRecord(root, id)
    if not isLocalId(id) then return nil end
    local registry = loadRegistry(root)
    local raw = registry.records and registry.records[id]
    return normalizedRecord(root, id, raw), registry
end

local function referencedAssets(definition)
    local used = {}
    for _, element in ipairs(definition.elements) do
        local font_id = type(element.font) == "string" and element.font:match("^asset:(.+)$") or nil
        if font_id then used[font_id] = true end
        for _, image_id in ipairs(element.images or {}) do used[image_id] = true end
    end
    return used
end

local function completeDraft(root, draft)
    if type(draft) ~= "table" or type(draft.asset_paths) ~= "table" then return nil, "invalid draft" end
    local definition, err = Presets.normalize(draft.definition)
    if not definition then return nil, err end
    local paths, assets = {}, {}
    for _, asset in ipairs(definition.assets) do assets[asset.id] = asset end
    for key in pairs(draft.asset_paths) do if not assets[key] then return nil, "draft has an unknown asset path" end end
    for asset_id, asset in pairs(assets) do
        local path = draft.asset_paths[asset_id]
        if not safeManagedPath(root, path, asset.extension) then return nil, "draft asset path is outside managed storage" end
        local data, asset_err = readVerifiedAsset(path, asset)
        if not data then return nil, asset_err end
        paths[asset_id] = path
    end
    return definition, paths
end

-- Forks can share immutable managed asset files. Only collect files no saved
-- record references, otherwise deleting/editing one preset damages another.
local function collectUnusedPaths(root, registry, candidates)
    local used = {}
    for _, raw in pairs(registry.records or {}) do
        for _, path in pairs(type(raw.asset_paths) == "table" and raw.asset_paths or {}) do
            if type(path) == "string" then used[path] = true end
        end
    end
    for _, path in pairs(candidates or {}) do
        if not used[path] and safeManagedPath(root, path, extensionOf(path)) then os.remove(path) end
    end
end

function Presets.saveDraft(appdock, draft, id)
    local root, root_err = ensureStorage()
    if not root then return fail(root_err) end
    if id ~= nil and not isLocalId(id) then return fail("invalid local preset id") end
    local definition, paths_or_err = completeDraft(root, draft)
    if not definition then return fail(paths_or_err) end
    local paths = paths_or_err
    local registry = loadRegistry(root)
    registry.records = registry.records or {}
    local old_record
    if id then old_record = normalizedRecord(root, id, registry.records[id]) end
    id = id or newId("ss")
    local record = { id = id, definition = definition, asset_paths = paths }
    -- Callers edit complete records. Adopt the current metadata, not stale
    -- registry metadata: a publication may have just gained its next revision
    -- or have been withdrawn. This is never server-side ownership authority.
    record.remote_id, record.revision, record.creator = draft.remote_id, draft.revision, draft.creator
    record = normalizedRecord(root, id, record)
    registry.records[id] = record
    local ok, err = saveRegistry(root, registry)
    if not ok then return fail(err) end

    -- Commit precedes garbage collection: a failed cleanup can only leave an
    -- unused asset, never make the saved record incomplete.
    if old_record then
        collectUnusedPaths(root, registry, old_record.asset_paths)
    end
    return record
end

function Presets.getActive(appdock)
    local id = appdock and appdock.settings and appdock.settings.sleepscreens and appdock.settings.sleepscreens.active_id
    if not isLocalId(id) then return nil end
    local root = ensureStorage()
    if not root then return nil end
    local record = findRecord(root, id)
    return record
end

function Presets.activate(appdock, id)
    if not appdock or type(appdock.settings) ~= "table" then return fail("AppDock settings unavailable") end
    if not isLocalId(id) then return fail("invalid local preset id") end
    local root, root_err = ensureStorage()
    if not root then return fail(root_err) end
    local record = findRecord(root, id)
    if not record then return fail("local preset not found") end
    appdock.settings.sleepscreens = { active_id = id }
    appdock.settings.sleepscreen_enabled = true
    if type(appdock._saveSettings) == "function" then appdock:_saveSettings() end
    return true
end

function Presets.remove(appdock, id)
    if not isLocalId(id) then return fail("invalid local preset id") end
    local root, root_err = ensureStorage()
    if not root then return fail(root_err) end
    local record, registry = findRecord(root, id)
    if not record then return fail("local preset not found") end
    registry.records[id] = nil
    local ok, err = saveRegistry(root, registry)
    if not ok then return fail(err) end
    collectUnusedPaths(root, registry, record.asset_paths)
    if appdock and appdock.settings and appdock.settings.sleepscreens and appdock.settings.sleepscreens.active_id == id then
        appdock.settings.sleepscreens = { active_id = nil }
        if type(appdock._saveSettings) == "function" then appdock:_saveSettings() end
    end
    return true
end

function Presets.importAsset(draft, path, kind)
    local root, root_err = ensureStorage()
    if not root then return fail(root_err) end
    if type(draft) ~= "table" or type(draft.definition) ~= "table" or type(draft.asset_paths) ~= "table" then return fail("invalid draft") end
    if kind ~= "image" and kind ~= "font" then return fail("invalid asset kind") end
    if type(path) ~= "string" or #path == 0 or #path > 1024 or path:find("%z") then return fail("invalid source asset path") end
    local extension = extensionOf(path)
    if expectedKindForExtension(extension) ~= kind then return fail("asset extension does not match selected kind") end
    local asset_data, asset_err = readBounded(path, assetLimit(kind))
    if not asset_data then return fail(asset_err) end
    if not hasAssetSignature(asset_data, kind, extension) then return fail("asset signature does not match selected kind") end

    -- Verify that adding the descriptor cannot exceed the public schema cap.
    local count = asArray(draft.definition.assets, MAX_ASSETS)
    if count == nil or count >= MAX_ASSETS then return fail("maximum asset count reached") end
    local asset_id
    repeat asset_id = newId("asset") until not draft.asset_paths[asset_id]
    local target = root .. "/assets/" .. asset_id .. "." .. extension
    local ok, err = atomicWrite(target, asset_data)
    if not ok then return fail(err) end
    table.insert(draft.definition.assets, { id = asset_id, kind = kind, extension = extension })
    draft.asset_paths[asset_id] = target
    return asset_id
end

local function assertReferencedAssets(definition)
    local used = referencedAssets(definition)
    for _, asset in ipairs(definition.assets) do
        if not used[asset.id] then return nil, "package contains an unreferenced asset" end
    end
    return true
end

function Presets.exportPackage(record)
    if type(record) ~= "table" then return fail("invalid local preset") end
    local definition, err = Presets.normalize(record.definition)
    if not definition then return fail(err) end
    -- Imported media may be unused after an element/font is removed. Exclude
    -- such media from the transport rather than sharing it or blocking Publish.
    local used, filtered_assets = referencedAssets(definition), newArray()
    for _, asset in ipairs(definition.assets) do
        if used[asset.id] then table.insert(filtered_assets, asset) end
    end
    definition.assets = filtered_assets
    if type(record.asset_paths) ~= "table" then return fail("local preset has no asset paths") end
    local root, root_err = ensureStorage()
    if not root then return fail(root_err) end
    local package, total = { definition = definition, assets = {} }, 0
    for _, asset in ipairs(definition.assets) do
        local path = record.asset_paths[asset.id]
        if not safeManagedPath(root, path, asset.extension) then return fail("asset path is outside managed storage") end
        local data, asset_err = readVerifiedAsset(path, asset)
        if not data then return fail(asset_err) end
        total = total + #data
        if total > MAX_ASSET_BYTES then return fail("assets exceed package size limit") end
        local encoded = mime.b64(data)
        if type(encoded) ~= "string" then return fail("could not encode asset") end
        package.assets[asset.id] = encoded
    end
    local encoded, encode_err = encodeJSON(package)
    if not encoded then return fail(encode_err) end
    if #encoded > MAX_PACKAGE_BYTES then return fail("package exceeds JSON size limit") end
    return package
end

local function decodeBase64(encoded, maximum)
    if type(encoded) ~= "string" or #encoded == 0 or #encoded > math.ceil(maximum / 3) * 4 then return nil, "invalid base64 asset" end
    -- Lua patterns do not implement regex {0,2}; check the three permitted
    -- standard-base64 padding forms explicitly and reject all whitespace.
    local base64_chars = "[A-Za-z0-9+/]*"
    local valid_padding = encoded:match("^" .. base64_chars .. "$")
        or encoded:match("^" .. base64_chars .. "=$")
        or encoded:match("^" .. base64_chars .. "==$" )
    if #encoded % 4 ~= 0 or not valid_padding then return nil, "invalid base64 asset" end
    local padding = encoded:sub(-2) == "==" and 2 or (encoded:sub(-1) == "=" and 1 or 0)
    local expected = (#encoded / 4) * 3 - padding
    if expected < 0 or expected > maximum then return nil, "asset exceeds its size limit" end
    local ok, data = pcall(mime.unb64, encoded)
    if not ok or type(data) ~= "string" or #data ~= expected then return nil, "invalid base64 asset" end
    return data
end

local function normalizedEntry(entry)
    if entry == nil then return {} end
    if type(entry) ~= "table" then return nil, "invalid store entry" end
    local result = {}
    if entry.id ~= nil then
        if type(entry.id) ~= "string" or #entry.id < 1 or #entry.id > 80 or not entry.id:match("^[A-Za-z0-9%-]+$") then return nil, "invalid remote preset id" end
        result.remote_id = entry.id
    end
    if entry.revision ~= nil then
        if not isInteger(entry.revision) or entry.revision < 1 then return nil, "invalid remote revision" end
        result.revision = entry.revision
    end
    if entry.creator ~= nil then
        if type(entry.creator) ~= "table" then return nil, "invalid remote creator" end
        local creator = {}
        if entry.creator.account_id ~= nil then
            if type(entry.creator.account_id) ~= "string" or #entry.creator.account_id > 128 then return nil, "invalid creator account" end
            creator.account_id = entry.creator.account_id
        end
        if entry.creator.display_name ~= nil then
            if type(entry.creator.display_name) ~= "string" or #entry.creator.display_name > 160 then return nil, "invalid creator name" end
            creator.display_name = entry.creator.display_name
        end
        result.creator = creator
    end
    return result
end

-- A full preview must pass the same binary/schema checks as installation,
-- without registering a local preset or trusting server-supplied file paths.
function Presets.validatePackage(package)
    if type(package) ~= "table" or type(package.assets) ~= "table" then return fail("invalid sleepscreen package") end
    local encoded_package, package_err = encodeJSON(package)
    if not encoded_package then return fail(package_err) end
    if #encoded_package > MAX_PACKAGE_BYTES then return fail("package exceeds JSON size limit") end
    local definition, definition_err = Presets.normalize(package.definition)
    if not definition then return fail(definition_err) end
    local referenced, ref_err = assertReferencedAssets(definition)
    if not referenced then return fail(ref_err) end

    local asset_values, total = {}, 0
    for key in pairs(package.assets) do
        if not isId(key) then return fail("invalid package asset key") end
    end
    for _, asset in ipairs(definition.assets) do
        local encoded = package.assets[asset.id]
        local data, decode_err = decodeBase64(encoded, assetLimit(asset.kind))
        if not data then return fail(decode_err) end
        if not hasAssetSignature(data, asset.kind, asset.extension) then return fail("asset signature does not match declared type") end
        total = total + #data
        if total > MAX_ASSET_BYTES then return fail("assets exceed package size limit") end
        asset_values[asset.id] = data
    end
    for asset_id in pairs(package.assets) do
        local found = false
        for _, asset in ipairs(definition.assets) do if asset.id == asset_id then found = true; break end end
        if not found then return fail("package contains an undeclared asset") end
    end
    return definition, asset_values
end

function Presets.installPackage(appdock, package, entry)
    local definition, values_or_err = Presets.validatePackage(package)
    if not definition then return fail(values_or_err) end
    local asset_values = values_or_err
    local remote, remote_err = normalizedEntry(entry)
    if not remote then return fail(remote_err) end
    local root, root_err = ensureStorage()
    if not root then return fail(root_err) end
    local id, staged, finals = newId("ss"), {}, {}
    for _, asset in ipairs(definition.assets) do
        local final_path = root .. "/assets/" .. id .. "-" .. asset.id .. "." .. asset.extension
        local staged_path = final_path .. ".incoming-" .. newId("asset")
        local ok, write_err = atomicWrite(staged_path, asset_values[asset.id])
        if not ok then
            for _, path in pairs(staged) do os.remove(path) end
            return fail(write_err)
        end
        staged[asset.id], finals[asset.id] = staged_path, final_path
    end
    for asset_id, staged_path in pairs(staged) do
        if not os.rename(staged_path, finals[asset_id]) then
            for _, leftover in pairs(staged) do os.remove(leftover) end
            for _, final_path in pairs(finals) do os.remove(final_path) end
            return fail("could not commit package assets")
        end
    end

    local registry = loadRegistry(root)
    registry.records = registry.records or {}
    local record = { id = id, definition = definition, asset_paths = finals }
    for key, value in pairs(remote) do record[key] = value end
    registry.records[id] = record
    local ok, save_err = saveRegistry(root, registry)
    if not ok then
        for _, final_path in pairs(finals) do os.remove(final_path) end
        return fail(save_err)
    end
    return record
end

-- Kept intentionally small for mock-based tests and for callers that need the
-- documented limits without duplicating them.
Presets._test = {
    root = sleepRoot,
    hasAssetSignature = hasAssetSignature,
    limits = { elements = MAX_ELEMENTS, assets = MAX_ASSETS, image_bytes = MAX_IMAGE_BYTES, font_bytes = MAX_FONT_BYTES, package_bytes = MAX_PACKAGE_BYTES },
}

return Presets
