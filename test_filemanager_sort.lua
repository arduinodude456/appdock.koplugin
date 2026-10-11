-- Regression test: virtual file sorting must scan each folder once and preserve files.
local function class()
    local C = {}
    function C:extend(proto)
        proto = proto or {}
        proto.__index = proto
        setmetatable(proto, { __index = self })
        return proto
    end
    return C
end
local function install(name, value) package.preload[name] = function() return value end end
local Widget, Input = class(), class()
local root = "/mnt/onboard/appdock-sort-regression"
local directories = {
    [root] = { ".", "..", "Books", "Media", "zebra.epub", "loop" },
    [root .. "/Books"] = { ".", "..", "Deep" },
    [root .. "/Books/Deep"] = { ".", "..", "notes.md" },
    [root .. "/Media"] = { ".", "..", "photo.png", "song.mp3" },
}
local attributes = {
    [root] = { mode = "directory" },
    [root .. "/Books"] = { mode = "directory" },
    [root .. "/Books/Deep"] = { mode = "directory" },
    [root .. "/Media"] = { mode = "directory" },
    [root .. "/zebra.epub"] = { mode = "file", size = 11 },
    [root .. "/Books/Deep/notes.md"] = { mode = "file", size = 12 },
    [root .. "/Media/photo.png"] = { mode = "file", size = 13 },
    [root .. "/Media/song.mp3"] = { mode = "file", size = 14 },
}
local lfs_calls = 0
local lfs = {
    dir = function(path)
        lfs_calls = lfs_calls + 1
        local names = directories[path]
        if not names then error("unreadable directory") end
        local index = 0
        return function()
            index = index + 1
            return names[index]
        end
    end,
    attributes = function(path) return attributes[path] end,
    symlinkattributes = function(path) return path == root .. "/loop" and { mode = "link" } or nil end,
    mkdir = function() return true end,
}
install("libs/libkoreader-lfs", lfs)
install("ffi/blitbuffer", { COLOR_WHITE = 1, COLOR_LIGHT_GRAY = 2, COLOR_GRAY_8 = 3, COLOR_DARK_GRAY = 4, COLOR_BLACK = 5, ColorRGB32 = function() return 0 end })
install("appdock_dialogs", { ButtonDialog = Widget, ConfirmBox = Widget, InfoMessage = Widget })
install("ui/widget/container/centercontainer", Widget)
install("device", { screen = { scaleBySize = function(_, value) return value end, isColorEnabled = function() return false end } })
install("document/documentregistry", { hasProvider = function(_, path) return path:match("%.epub$") ~= nil end })
install("appdock_layout", { FixedStack = Widget })
install("appdock_theme", { fitLabel = function(value) return value end, getPalette = function() return { background = 1, surface = 1, primary = 1, secondary = 1, on_primary = 1, on_surface = 1, on_variant = 1, outline = 1 } end })
install("apps/filemanager/filemanagerutil", {})
install("appdock_keyboard", Widget)
install("ui/font", { getFace = function() return {} end })
install("ui/widget/container/framecontainer", Widget)
install("ui/geometry", { new = function(_, value) return value end })
install("ui/gesturerange", { new = function(_, value) return value end })
install("ui/widget/horizontalspan", Widget)
install("ui/widget/container/inputcontainer", Input)
install("ui/widget/overlapgroup", Widget)
install("ui/widget/container/scrollablecontainer", Widget)
install("ui/widget/textwidget", Widget)
install("ui/uimanager", { show = function() end, close = function() end, nextTick = function(_, callback) callback() end })
install("ui/widget/verticalgroup", Widget)
install("ui/widget/verticalspan", Widget)
install("ui/widget/container/widgetcontainer", Widget)
install("gettext", function(value) return value end)

local FileBrowser = assert(loadfile("appdock.koplugin/appdock_filemanager.lua"))()
local browser = FileBrowser:new()
local entries, err = browser:_readSortedEntries(root)
assert(not err and #entries == 4, "Virtual sorting must collect every readable file exactly once")
assert(entries[1].sort_category == "audio" and entries[2].sort_category == "documents" and entries[3].sort_category == "documents" and entries[4].sort_category == "images", "Virtual sorting must group categories and sort names deterministically")
assert(lfs_calls == 4, "Virtual sorting must visit folders once instead of rescanning their parent for each file")
assert(not browser:_readSortedEntries("/tmp"), "Virtual sorting must not escape the device storage root")
print("filemanager-sort-ok")
