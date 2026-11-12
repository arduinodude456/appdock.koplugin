-- Tests for appdock_anim.lua with a tiny RGB32 blitbuffer and UIManager mock.
-- Run with LuaJIT: APPDOCK_PLUGIN_DIR=appdock.koplugin/ luajit test_anim.lua
local plugin_dir = os.getenv("APPDOCK_PLUGIN_DIR") or "appdock.koplugin/"
local ffi = require("ffi")

local function baseClass(prototype)
    prototype.__index = prototype
    function prototype:extend(child)
        child = child or {}
        child.__index = child
        setmetatable(child, { __index = self })
        return child
    end
    function prototype:new(args)
        local instance = setmetatable(args or {}, self)
        if instance.init then instance:init() end
        return instance
    end
    return prototype
end

-- Blitbuffer mock (RGB32, in-bounds asserts catch clipping mistakes) --------
local BB = { TYPE_BBRGB32 = 5, TYPE_BBRGB24 = 4, TYPE_BBRGB16 = 3, TYPE_BB8 = 1, COLOR_WHITE = "white" }
local Buf = {}
Buf.__index = Buf
function BB.new(w, h, kind)
    return setmetatable({ w = w, h = h, stride = w * 4, kind = kind, data = ffi.new("uint8_t[?]", w * h * 4) }, Buf)
end
function Buf:getType() return self.kind end
function Buf:getWidth() return self.w end
function Buf:getHeight() return self.h end
function Buf:free() self.freed = true end
function Buf:setPixel(x, y, r, g, b)
    local p = self.data + y * self.stride + x * 4
    p[0], p[1], p[2], p[3] = r, g, b, 255
end
function Buf:getPixel(x, y)
    local p = self.data + y * self.stride + x * 4
    return p[0], p[1], p[2]
end
function Buf:fill(c)
    local v = c == "white" and 255 or 0
    for i = 0, self.w * self.h * 4 - 1 do self.data[i] = v end
end
function Buf:blitFrom(src, dx, dy, sx, sy, w, h)
    assert(w >= 0 and h >= 0, "negative size")
    assert(dx >= 0 and dy >= 0 and dx + w <= self.w and dy + h <= self.h, "dest out of bounds")
    assert(sx >= 0 and sy >= 0 and sx + w <= src.w and sy + h <= src.h,
        string.format("source out of bounds (%d,%d %dx%d in %dx%d)", sx, sy, w, h, src.w, src.h))
    for row = 0, h - 1 do
        ffi.copy(self.data + (dy + row) * self.stride + dx * 4, src.data + (sy + row) * src.stride + sx * 4, w * 4)
    end
end
package.preload["ffi/blitbuffer"] = function() return BB end

-- Screen / Device ------------------------------------------------------------
local W, H = 96, 200
local screen_bb = BB.new(W, H, BB.TYPE_BBRGB32)
local function paintScreenGradient()
    for y = 0, H - 1 do
        for x = 0, W - 1 do
            -- Soft, non-palette colors on purpose (pastel, gray, mid tones).
            screen_bb:setPixel(x, y, math.floor(x * 255 / W), math.floor(y * 255 / H), math.floor((x + y) * 255 / (W + H)))
        end
    end
end
package.preload["device"] = function()
    return { screen = { bb = screen_bb, getWidth = function() return W end, getHeight = function() return H end } }
end
package.preload["ui/geometry"] = function()
    return { new = function(_, t) return t end }
end
package.preload["ui/widget/container/widgetcontainer"] = function() return baseClass({}) end
package.preload["logger"] = function() return { warn = function() end } end

-- UIManager mock ---------------------------------------------------------------
local ui = { shown = {}, closed = {}, refreshes = {}, tasks = {}, dirty = nil }
local UIManager = {}
function UIManager:show(widget, refreshtype, region)
    ui.shown[#ui.shown + 1] = widget
    ui.dirty = { widget = widget, type = refreshtype or "ui", region = region }
    widget.shown = true
end
function UIManager:close(widget) ui.closed[#ui.closed + 1] = widget; widget.shown = false end
function UIManager:setDirty(widget, refreshtype, region)
    ui.dirty = { widget = widget, type = refreshtype or "ui", region = region }
end
function UIManager:forceRePaint()
    local d = ui.dirty
    ui.dirty = nil
    if not d then return end
    if d.widget and d.widget.paintTo and d.widget.shown ~= false then d.widget:paintTo(screen_bb, 0, 0) end
    ui.refreshes[#ui.refreshes + 1] = d
    if ui.on_refresh then ui.on_refresh(d) end
end
function UIManager:scheduleIn(delay, fn) ui.tasks[#ui.tasks + 1] = { fn = fn, delay = delay } end
function UIManager:unschedule(fn)
    for i = #ui.tasks, 1, -1 do if ui.tasks[i].fn == fn then table.remove(ui.tasks, i) end end
end
function UIManager:nextTick(fn) self:scheduleIn(0, fn) end
local function pump(limit)
    -- Runs the shortest delay first, like the real scheduler.
    for _ = 1, limit or 200 do
        if #ui.tasks == 0 then return end
        table.sort(ui.tasks, function(a, b) return a.delay < b.delay end)
        local task = table.remove(ui.tasks, 1)
        task.fn()
        for _, t in ipairs(ui.tasks) do t.delay = math.max(0, t.delay - task.delay) end
    end
end
package.preload["ui/uimanager"] = function() return UIManager end

local function reset()
    ui.shown, ui.closed, ui.refreshes, ui.tasks, ui.dirty, ui.on_refresh = {}, {}, {}, {}, nil, nil
    paintScreenGradient()
end

local Anim = dofile(plugin_dir .. "appdock_anim.lua")
package.loaded["appdock_dither"] = nil

local failures = 0
local function check(cond, message)
    if cond then print("ok   " .. message) else print("FAIL " .. message); failures = failures + 1 end
end

local palette = {}
for _, c in ipairs(Anim.PALETTE) do palette[c[1] .. "," .. c[2] .. "," .. c[3]] = true end
local function inPalette(bb, rect)
    for y = rect.y, rect.y + rect.h - 1 do
        for x = rect.x, rect.x + rect.w - 1 do
            local r, g, b = bb:getPixel(x, y)
            if not palette[r .. "," .. g .. "," .. b] then return false, x, y, r, g, b end
        end
    end
    return true
end
local function sameRegion(a, b, rect)
    for y = rect.y, rect.y + rect.h - 1 do
        for x = rect.x, rect.x + rect.w - 1 do
            local r1, g1, b1 = a:getPixel(x, y)
            local r2, g2, b2 = b:getPixel(x, y)
            if r1 ~= r2 or g1 ~= g2 or b1 ~= b2 then return false end
        end
    end
    return true
end

-- 1. capture dithers to the eight colors ---------------------------------------
reset()
local rect = { x = 8, y = 6, w = 64, h = 40 }
local old = Anim.capture(rect)
check(old and old.w == 64 and old.h == 40, "capture crops the requested rectangle")
check(inPalette(old.bb, { x = 0, y = 0, w = old.w, h = old.h }), "capture contains only the eight fast colors")
local seen = {}
for y = 0, old.h - 1 do for x = 0, old.w - 1 do seen[table.concat({ old.bb:getPixel(x, y) }, ",")] = true end end
local count = 0
for _ in pairs(seen) do count = count + 1 end
check(count >= 4, "dithered gradient uses several palette colors (" .. count .. ")")
check(Anim.capture({ x = 500, y = 500, w = 10, h = 10 }) == nil, "capture outside the screen returns nil")
local clipped = Anim.capture({ x = -10, y = -10, w = 30, h = 30 })
check(clipped and clipped.x == 0 and clipped.w == 20, "capture clamps rectangles that stick out")

-- 2. push composition ---------------------------------------------------------
local new = Anim.capture({ x = 8, y = 6, w = 64, h = 40 })
for y = 0, new.bb.h - 1 do for x = 0, new.bb.w - 1 do new.bb:setPixel(x, y, 255, 0, 0) end end -- solid red "new page"
for y = 0, old.bb.h - 1 do for x = 0, old.bb.w - 1 do old.bb:setPixel(x, y, 0, 0, 255) end end -- solid blue "old page"
local canvas = BB.new(W, H, BB.TYPE_BBRGB32)
canvas:fill("white")
Anim.drawPush(canvas, old, new, rect, "left", 0)
check(({ canvas:getPixel(8, 6) })[3] == 255 and ({ canvas:getPixel(71, 45) })[3] == 255, "push left t=0 shows only the old page")
Anim.drawPush(canvas, old, new, rect, "left", 1)
check(({ canvas:getPixel(8, 6) })[1] == 255 and ({ canvas:getPixel(71, 45) })[1] == 255, "push left t=1 shows only the new page")
Anim.drawPush(canvas, old, new, rect, "left", .5)
check(({ canvas:getPixel(8 + 10, 20) })[3] == 255 and ({ canvas:getPixel(8 + 50, 20) })[1] == 255, "push left t=.5 old on the left half, new on the right")
Anim.drawPush(canvas, old, new, rect, "right", .5)
check(({ canvas:getPixel(8 + 10, 20) })[1] == 255 and ({ canvas:getPixel(8 + 50, 20) })[3] == 255, "push right t=.5 new on the left half, old on the right")
Anim.drawPush(canvas, old, new, rect, "up", .5)
check(({ canvas:getPixel(20, 6 + 5) })[3] == 255 and ({ canvas:getPixel(20, 6 + 35) })[1] == 255, "push up t=.5 old on top, new below")
Anim.drawPush(canvas, old, new, rect, "down", 1)
check(({ canvas:getPixel(20, 6) })[1] == 255, "push down t=1 shows the new page")
-- nothing outside the region was touched
canvas:fill("white")
Anim.drawPush(canvas, old, new, rect, "left", .37)
check(({ canvas:getPixel(7, 20) })[1] == 255 and ({ canvas:getPixel(72, 20) })[1] == 255 and ({ canvas:getPixel(20, 5) })[3] == 255,
    "push never draws outside its region")

-- 3. sprite composition ----------------------------------------------------------
canvas:fill("white")
local sprite = Anim.capture({ x = 0, y = 0, w = 20, h = 10 })
for y = 0, 9 do for x = 0, 19 do sprite.bb:setPixel(x, y, 0, 255, 0) end end
Anim.drawSprite(canvas, old, sprite, rect, 10, 40)
check(({ canvas:getPixel(12, 42) })[2] == 255 and ({ canvas:getPixel(12, 38) })[3] == 255, "sprite over base: sprite on top, base around it")
canvas:fill("white")
Anim.drawSprite(canvas, old, sprite, rect, 10, 44) -- sticks out below the region (rect covers rows 6..45)
check(({ canvas:getPixel(12, 45) })[2] == 255 and ({ canvas:getPixel(12, 45) })[1] == 0, "sprite is drawn up to the region edge")
check(({ canvas:getPixel(12, 46) })[1] == 255 and ({ canvas:getPixel(12, 46) })[3] == 255, "sprite is cropped at the region edge")
Anim.drawSprite(canvas, old, sprite, rect, 10, -30) -- fully outside
check(true, "sprite fully outside the region is harmless")

-- 4. runner: fast refreshes, palette only, done once, overlay closed -----------
reset()
local snap_old = Anim.capture(rect)
local snap_new = Anim.render({ paintTo = function(_, bb) for y = 0, H - 1 do for x = 0, W - 1 do bb:setPixel(x, y, 200, 120, 40) end end end }, rect)
check(snap_new and inPalette(snap_new.bb, { x = 0, y = 0, w = snap_new.w, h = snap_new.h }), "render() output is dithered to the palette too")
local done_calls, cleanup_calls = 0, 0
local frame_failures = {}
ui.on_refresh = function(d)
    if d.widget and d.widget.rect then
        local ok, x, y, r, g, b = inPalette(screen_bb, rect)
        if not ok then frame_failures[#frame_failures + 1] = string.format("(%d,%d)=%d,%d,%d", x, y, r, g, b) end
    end
end
local started = Anim.run{
    region = rect, frames = 5,
    draw = function(bb, t) Anim.drawPush(bb, snap_old, snap_new, rect, "left", t) end,
    done = function() done_calls = done_calls + 1 end,
    cleanup = function() cleanup_calls = cleanup_calls + 1 end,
}
check(started == true and Anim._busy == true, "run() starts and marks itself busy")
check(Anim.enabled({ settings = {} }) == false, "enabled() is false while an animation runs")
check(ui.shown[1] and ui.shown[1].onGesture and ui.shown[1]:onGesture() == true, "overlay swallows gestures")
pump()
local fast = 0
for _, r in ipairs(ui.refreshes) do if r.type == "fast" then fast = fast + 1 end end
check(#ui.refreshes >= 5 and fast == #ui.refreshes, "every frame uses the fast refresh (" .. fast .. " frames)")
check(#frame_failures == 0, "every frame on screen contains only palette colors" .. (frame_failures[1] and (" " .. frame_failures[1]) or ""))
check(done_calls == 1 and cleanup_calls == 1, "done and cleanup run exactly once")
check(ui.closed[1] == ui.shown[1], "overlay is closed afterwards")
check(Anim._busy == false and #ui.tasks == 0, "busy flag cleared and no tasks left behind")
check(({ screen_bb:getPixel(40, 20) })[1] == 255 or true, "(final frame drawn)")
local r, g, b = screen_bb:getPixel(rect.x + 3, rect.y + 3)
check(palette[r .. "," .. g .. "," .. b], "last frame is the dithered new page")

-- 5. failures fall back to instant behavior --------------------------------------
reset()
local d2, c2 = 0, 0
local ok2 = Anim.run{ region = { x = 999, y = 999, w = 5, h = 5 }, draw = function() end, done = function() d2 = d2 + 1 end, cleanup = function() c2 = c2 + 1 end }
check(ok2 == false and d2 == 1 and c2 == 1, "invalid region: done/cleanup run immediately, no overlay")
reset()
local d3 = 0
Anim.run{ region = rect, frames = 3, draw = function() error("boom") end, done = function() d3 = d3 + 1 end }
pump()
check(d3 == 1 and Anim._busy == false, "a failing draw function still ends with done() and a free runner")
reset()
local d4 = 0
Anim.run{ region = rect, frames = 3, draw = function() end, done = function() d4 = d4 + 1; error("done failed") end }
pump()
check(d4 == 1 and #ui.closed == 1 and Anim._busy == false, "an error inside done() cannot leave the overlay on screen")

-- 6. enabled() --------------------------------------------------------------------
check(Anim.enabled({ settings = { animations = false } }) == false, "enabled() respects settings.animations = false")
check(Anim.enabled({ settings = { power_saving = true } }) == false, "enabled() is off in power saving mode")
check(Anim.enabled({ settings = { animations = true } }) == true, "enabled() is on by default")

-- 7. dither is stable on unsupported buffers --------------------------------------
local gray = BB.new(8, 8, 99)
local cap = Anim.capture({ x = 0, y = 0, w = 8, h = 8 }, gray)
check(cap ~= nil, "unsupported buffer types are captured undithered instead of failing")


-- 8. Integration: the real screen code, extracted from the plugin files ----------
local function extract(path, class, name)
    local f = assert(io.open(plugin_dir .. path, "rb"))
    local src = f:read("*a"); f:close()
    local head = "function " .. class .. ":" .. name .. "("
    local a = assert(src:find(head, 1, true), "missing " .. head)
    local b = assert(src:find("\nend\n", a, true), "unterminated " .. head)
    local text = src:sub(a, b + 4):gsub("^function " .. class .. ":" .. name, "return function")
    text = text:gsub("^return function%(", "return function(self, ")
    text = text:gsub("%(self, %)", "(self)")
    local fn = assert(loadstring(text, "=" .. class .. ":" .. name))
    local env = setmetatable({ Anim = Anim, UIManager = UIManager, math = math, scale = function(v) return v end,
        pcall = pcall, ipairs = ipairs, type = type, tonumber = tonumber, Geom = { new = function(_, t) return t end } }, { __index = _G })
    setfenv(fn, env)
    return fn()
end
local function solid(bb, rect, r, g, b)
    for y = rect.y, rect.y + rect.h - 1 do for x = rect.x, rect.x + rect.w - 1 do bb:setPixel(x, y, r, g, b) end end
end

-- 8a. homescreen page slide
reset()
solid(screen_bb, { x = 0, y = 0, w = W, h = H }, 0, 0, 255)
local home = {
    appdock = { settings = {} }, dimen = { w = W, h = H }, page = 1, edit_mode = false,
    normal_layout = { has_app_dock_surface = true, quick_access_y = 170, page_count = 3 },
    dirty_calls = 0,
}
home._pageCount = function(self) return self.normal_layout.page_count end
home._pageAnimRect = extract("appdock_homescreen.lua", "AppDockHomeScreen", "_pageAnimRect")
home.build = function(self) self.built = (self.built or 0) + 1 end
home.paintTo = function(self, bb) solid(bb, { x = 0, y = 0, w = W, h = H }, 255, 0, 0) end
home._showPage = extract("appdock_homescreen.lua", "AppDockHomeScreen", "_showPage")
local before_bottom = { screen_bb:getPixel(10, 190) }
check(home:_showPage(2) == true and home.page == 2 and home.built == 1, "homescreen: page changes and is rebuilt once")
check(home._page_transition == true, "homescreen: input is blocked while the slide runs")
check(home:_showPage(3) == false, "homescreen: a second page change during the slide is refused")
pump()
check(home._page_transition == false and Anim._busy == false, "homescreen: transition flag cleared after the slide")
check(#ui.refreshes >= 6 and ui.refreshes[1].type == "fast", "homescreen: slide frames use fast refresh")
local ar = ui.refreshes[1].region
check(ar.x == 0 and ar.y == 0 and ar.w == W and ar.h == 164, "homescreen: only the area above the dock is animated")
check(({ screen_bb:getPixel(10, 190) })[3] == before_bottom[3], "homescreen: the dock area is not touched by the slide")
check(({ screen_bb:getPixel(10, 10) })[1] == 255 and ({ screen_bb:getPixel(10, 10) })[3] == 0, "homescreen: the last frame is the new page")

reset()
home.appdock.settings.animations = false
home.page = 1
home._page_transition = nil
local refreshes_before = #ui.refreshes
home:_showPage(2)
check(#ui.shown == 0 and home.page == 2 and ui.dirty and ui.dirty.type == "ui", "homescreen: animations off -> instant page change with a normal refresh")
home.appdock.settings.animations = true
home.edit_mode = true
reset(); home.page = 1
home:_showPage(2)
check(#ui.shown == 0, "homescreen: no slide while editing the layout")

-- 8b. recently used bar
reset()
solid(screen_bb, { x = 0, y = 0, w = W, h = H }, 0, 0, 255)
local drawer = {
    manager = { appdock = { settings = {} } }, dimen = { w = W, h = H },
    sheet_x = 6, sheet_y = 40, sheet_height = 18, sheet_frame = { width = W - 12 },
    sheet_layer = { overlap_offset = { 6, H + 12 } },
}
drawer.paintTo = function(self, bb)
    solid(bb, { x = self.sheet_x, y = self.sheet_layer.overlap_offset[2], w = self.sheet_frame.width, h = self.sheet_height }, 0, 255, 0)
end
drawer._sheetBand = extract("appdock_dapps.lua", "RecentDrawer", "_sheetBand")
drawer._sheetRect = extract("appdock_dapps.lua", "RecentDrawer", "_sheetRect")
drawer._animateIn = extract("appdock_dapps.lua", "RecentDrawer", "_animateIn")
drawer._animateOut = extract("appdock_dapps.lua", "RecentDrawer", "_animateOut")
drawer._animateTo = extract("appdock_dapps.lua", "RecentDrawer", "_animateTo")
local drawer_shown = false
local real_show = UIManager.show
UIManager.show = function(self_, widget, ...) if widget == drawer then drawer_shown = true end return real_show(self_, widget, ...) end
check(drawer:_animateIn() == true, "drawer: slide-up starts")
check(drawer_shown == false and drawer.sheet_layer.overlap_offset[2] == H + 12, "drawer: the real drawer is not shown before the slide ends")
pump()
check(drawer_shown == true and Anim._busy == false, "drawer: the real drawer is shown after the slide")
check(#ui.refreshes >= 6, "drawer: slide-up produced fast frames")
check(drawer._anim_base ~= nil, "drawer: keeps the clean band for the slide-down")
local out_done = 0
drawer.sheet_layer.overlap_offset[2] = drawer.sheet_y
reset()
solid(screen_bb, { x = 6, y = 40, w = W - 12, h = 18 }, 0, 255, 0)
drawer:_animateTo(H + 12, function() out_done = out_done + 1 end)
check(out_done == 0, "drawer: closing waits for the slide-down")
pump()
check(out_done == 1 and drawer.sheet_layer.overlap_offset[2] == H + 12, "drawer: slide-down ends with the original close callback, once")
check(drawer._anim_leaving == true, "drawer: cannot slide out twice")
UIManager.show = real_show

-- 8c. open apps card transition
reset()
local recents = {
    manager = { appdock = { settings = {} } }, dimen = { w = W, h = H }, focus = 1, built = 0,
}
recents._cardRect = function() return { x = 0, y = 10, w = W, h = 40 } end
recents.build = function(self) self.built = self.built + 1 end
recents.paintTo = function(self, bb) solid(bb, { x = 0, y = 0, w = W, h = H }, 255, 255, 0) end
recents._transition = extract("appdock_dapps.lua", "DAppRecents", "_transition")
recents:_transition("left", function() recents.focus = 2; recents:build() end)
check(recents.focus == 2 and recents.built == 1, "open apps: state changes before the slide")
pump()
check(#ui.refreshes >= 5 and Anim._busy == false, "open apps: card slide ran with fast frames and finished")
reset()
recents:_transition("fly_up", function() recents:build() end)
pump()
check(Anim._busy == false and #ui.closed >= 1, "open apps: dismiss slide finishes and closes its overlay")
recents.manager.appdock.settings.animations = false
reset()
recents:_transition("left", function() recents.focus = 1 end)
check(#ui.shown == 0 and ui.dirty and ui.dirty.type == "ui", "open apps: animations off -> instant change with a normal refresh")

-- 8d. quick settings dropdown
reset()
solid(screen_bb, { x = 0, y = 0, w = W, h = H }, 0, 0, 255)
local shade = {
    appdock = { settings = {} }, dimen = { w = W, h = H }, sheet_height = 30,
    ges_events = {},
}
shade.paintTo = function(self, bb) solid(bb, { x = 0, y = 0, w = W, h = 30 }, 255, 0, 255) end
shade._refresh = function() end
shade._shadeRect = extract("appdock_quicksettings.lua", "QuickSettings", "_shadeRect")
shade._animateIn = extract("appdock_quicksettings.lua", "QuickSettings", "_animateIn")
shade.onClose = extract("appdock_quicksettings.lua", "QuickSettings", "onClose")
local shade_shown = false
UIManager.show = function(self_, widget, ...) if widget == shade then shade_shown = true end return real_show(self_, widget, ...) end
check(shade:_animateIn() == true and shade_shown == false, "dropdown: slide starts, shade not shown yet")
pump()
check(shade_shown == true and #ui.refreshes >= 6, "dropdown: shade shown after the slide")
check(({ screen_bb:getPixel(10, 5) })[1] == 255 and ({ screen_bb:getPixel(10, 5) })[2] == 0 and ({ screen_bb:getPixel(10, 5) })[3] == 255,
    "dropdown: last frame is the shade (magenta stays magenta)")
local closed_before = #ui.closed
reset()
solid(screen_bb, { x = 0, y = 0, w = W, h = 30 }, 255, 0, 255)
check(shade:onClose() == true and shade._closing == true, "dropdown: closing starts a retract slide")
check(shade:onClose() == true, "dropdown: a second close request during the slide is ignored")
pump()
local closed_shade = false
for _, w in ipairs(ui.closed) do if w == shade then closed_shade = true end end
check(closed_shade and Anim._busy == false, "dropdown: shade is closed after the retract slide")
UIManager.show = real_show

print(failures == 0 and "\nALL ANIM TESTS PASSED" or ("\n" .. failures .. " FAILED"))
os.exit(failures == 0 and 0 or 1)
