--[[--
AppDock Anim: short slide animations for E-Ink.

Rules every animation here follows:
  * All frames use only the eight fast E-Ink colors (black, white, red,
    green, blue, #ff00ff, #ffff00, #00ffff). The screen content is captured
    once, run through the Bayer dither of appdock_dither.lua, and the frames
    are then plain copies of those already dithered pixels. Nothing is
    dithered per frame, so the pattern moves with the content and does not
    shimmer.
  * Every frame is refreshed with the "fast" waveform, restricted to the
    moving region.
  * When the last frame is on screen the overlay is closed with the same
    regional "fast" refresh. There is no extra full/partial refresh before or
    after the animation, so the transition cannot flash.
  * The overlay swallows touch gestures while it runs, so a second swipe or
    a tap cannot start something in the middle of a transition.
  * Anything that fails (missing buffer type, painting error, ...) falls back
    to the instant behavior: `done` is always called exactly once.

Typical use:

    local old = Anim.capture(rect)              -- before the change
    change_the_ui()
    local new = Anim.render(widget, rect)       -- after the change, offscreen
    Anim.run{
        region = rect,
        draw = function(bb, t) Anim.drawPush(bb, old, new, rect, "left", t) end,
        done = function() ... end,
        cleanup = function() Anim.free(old); Anim.free(new) end,
    }
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Dither = require("appdock_dither")

local ok_logger, logger = pcall(require, "logger")
if not ok_logger then logger = { warn = function() end } end

local Screen = Device.screen

local Anim = {
    frames = 6,
    interval = 0.03,
    -- The only colors that may appear while something moves.
    PALETTE = {
        { 0, 0, 0 }, { 255, 255, 255 },
        { 255, 0, 0 }, { 0, 255, 0 }, { 0, 0, 255 },
        { 255, 0, 255 }, { 255, 255, 0 }, { 0, 255, 255 },
    },
    _busy = false,
}

-- Easing -------------------------------------------------------------------
local function clamp01(value) return math.max(0, math.min(1, tonumber(value) or 0)) end
function Anim.easeInOut(t) return -(math.cos(math.pi * clamp01(t)) - 1) / 2 end
function Anim.easeOut(t) t = clamp01(t); return 1 - (1 - t) ^ 3 end
function Anim.easeIn(t) t = clamp01(t); return t ^ 3 end

-- Helpers ------------------------------------------------------------------
local function round(value) return math.floor((tonumber(value) or 0) + 0.5) end

local function clampRect(rect, max_w, max_h)
    if type(rect) ~= "table" then return nil end
    local x0, y0 = math.max(0, round(rect.x)), math.max(0, round(rect.y))
    local x1, y1 = math.min(max_w, round(rect.x + rect.w)), math.min(max_h, round(rect.y + rect.h))
    if x1 <= x0 or y1 <= y0 then return nil end
    return { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
end

function Anim.screenRect()
    return { x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
end

-- Animations can be switched off in the AppDock settings and are skipped in
-- power saving mode and while another animation is still running.
function Anim.enabled(appdock)
    local reason
    local settings = appdock and appdock.settings
    if Anim._busy then reason = "busy (previous animation still running)"
    elseif type(settings) == "table" and settings.animations == false then reason = "switched off in the menu"
    elseif type(settings) == "table" and settings.power_saving == true then reason = "power saving mode is on"
    elseif not (Screen and Screen.bb) then reason = "no screen buffer" end
    Anim.last_reason = reason or "ok"
    return reason == nil
end

function Anim.free(snapshot)
    if type(snapshot) == "table" and snapshot.bb then
        if snapshot.bb.free then pcall(snapshot.bb.free, snapshot.bb) end
        snapshot.bb = nil
    end
end

-- A copy of the current screen, untouched (not dithered). Use it as the base
-- canvas when a widget has to be painted offscreen on top of what is shown.
function Anim.copyScreen()
    local width, height = Screen:getWidth(), Screen:getHeight()
    local copy = Blitbuffer.new(width, height, Screen.bb:getType())
    copy:blitFrom(Screen.bb, 0, 0, 0, 0, width, height)
    return copy
end

-- Captures `rect` (screen coordinates) of `src` (default: the screen) and
-- dithers it to the eight fast colors. Returns a snapshot or nil.
function Anim.capture(rect, src)
    src = src or Screen.bb
    local r = clampRect(rect, src:getWidth(), src:getHeight())
    if not r then return nil end
    local ok, snapshot = pcall(function()
        local bb = Blitbuffer.new(r.w, r.h, src:getType())
        bb:blitFrom(src, 0, 0, r.x, r.y, r.w, r.h)
        -- Unsupported buffer types simply stay as they are.
        pcall(Dither.apply, bb)
        return { bb = bb, x = r.x, y = r.y, w = r.w, h = r.h }
    end)
    if ok then return snapshot end
    Anim.last_reason = "capture failed: " .. tostring(snapshot); logger.warn("AppDock animation: capture failed", snapshot)
    return nil
end

-- Paints `widget` offscreen and captures `rect` of the result. By default the
-- widget is painted on a copy of the current screen, so transparent widgets
-- (drawers, shades) show what is behind them. Pass your own `canvas` to
-- control that; the caller frees a canvas it passes in.
function Anim.render(widget, rect, canvas)
    local owned = canvas == nil
    local ok, snapshot = pcall(function()
        canvas = canvas or Anim.copyScreen()
        widget:paintTo(canvas, 0, 0)
        return Anim.capture(rect, canvas)
    end)
    if owned and canvas and canvas.free then pcall(canvas.free, canvas) end
    if ok then return snapshot end
    Anim.last_reason = "render failed: " .. tostring(snapshot); logger.warn("AppDock animation: offscreen render failed", snapshot)
    return nil
end

-- Copies the part (sx, sy, sw, sh) of a snapshot (default: all of it) to the
-- screen at (dest_x, dest_y), cropped to `clip`.
function Anim.blit(dst, snapshot, dest_x, dest_y, clip, sx, sy, sw, sh)
    if not snapshot or not snapshot.bb then return false end
    sx, sy = sx or 0, sy or 0
    sw, sh = sw or (snapshot.w - sx), sh or (snapshot.h - sy)
    dest_x, dest_y = round(dest_x), round(dest_y)
    local x0, y0 = math.max(dest_x, clip.x), math.max(dest_y, clip.y)
    local x1, y1 = math.min(dest_x + sw, clip.x + clip.w), math.min(dest_y + sh, clip.y + clip.h)
    if x1 <= x0 or y1 <= y0 then return false end
    dst:blitFrom(snapshot.bb, x0, y0, sx + (x0 - dest_x), sy + (y0 - dest_y), x1 - x0, y1 - y0)
    return true
end

-- Frame compositions ---------------------------------------------------------
-- Both snapshots cover `rect`. direction is the way the content travels:
-- "left" = old leaves to the left and new arrives from the right.
function Anim.drawPush(dst, old, new, rect, direction, t)
    local horizontal = direction == "left" or direction == "right"
    local span = horizontal and rect.w or rect.h
    local offset = round(clamp01(t) * span)
    local old_x, old_y, new_x, new_y = rect.x, rect.y, rect.x, rect.y
    if direction == "left" then old_x, new_x = rect.x - offset, rect.x + span - offset
    elseif direction == "right" then old_x, new_x = rect.x + offset, rect.x - span + offset
    elseif direction == "up" then old_y, new_y = rect.y - offset, rect.y + span - offset
    else old_y, new_y = rect.y + offset, rect.y - span + offset end
    Anim.blit(dst, old, old_x, old_y, rect)
    Anim.blit(dst, new, new_x, new_y, rect)
end

-- A sprite (snapshot of a sheet, shade or card) moves over a static base.
-- (x, y) is where the sprite's top-left corner is drawn.
function Anim.drawSprite(dst, base, sprite, rect, x, y)
    Anim.blit(dst, base, base.x, base.y, rect)
    Anim.blit(dst, sprite, x, y, rect)
end

-- Runner ---------------------------------------------------------------------
local Overlay = WidgetContainer:extend{ name = "AppDockAnimOverlay" }

function Overlay:init()
    self.dimen = Geom:new{ x = self.rect.x, y = self.rect.y, w = self.rect.w, h = self.rect.h }
end

function Overlay:paintTo(bb)
    if self.draw then self.draw(bb) end
end

-- Touch input never reaches the widgets below while frames are running.
function Overlay:onGesture() return true end

--[[--
opts:
  region   {x, y, w, h}  screen rectangle that moves (refreshed every frame)
  draw     function(bb, t, rect): paint frame `t` (0..1, already eased)
  done     function(): the new state; runs once after the last frame
  after    function(): optional callback after the overlay is closed
  close_refresh false: close the overlay without enqueueing another refresh
  cleanup  function(): free snapshots; runs once, after done
  frames, interval, ease: optional
Returns true when the animation started. When it could not start `done` and
`cleanup` have already run, so callers never need an extra fallback branch.
--]]--
function Anim.run(opts)
    local function bail()
        if opts.done then pcall(opts.done) end
        if opts.cleanup then pcall(opts.cleanup) end
        return false
    end
    local rect = clampRect(opts.region, Screen:getWidth(), Screen:getHeight())
    if not rect or Anim._busy or type(opts.draw) ~= "function" then return bail() end

    local frames = math.max(2, math.floor(opts.frames or Anim.frames))
    local interval = tonumber(opts.interval) or Anim.interval
    local ease = opts.ease or Anim.easeInOut
    -- Let the first show paint the first moved frame instead of painting a
    -- static t=0 frame and then repainting it again when the timer starts.
    local progress, frame, finished = ease(1 / frames), 1, false
    local overlay, tick, finish

    local started = pcall(function()
        overlay = Overlay:new{ rect = rect }
        overlay.draw = function(bb)
            local ok, err = pcall(opts.draw, bb, progress, rect)
            if not ok then Anim.last_reason = "frame failed: " .. tostring(err); logger.warn("AppDock animation: frame failed", err) end
        end
    end)
    if not started then return bail() end

    finish = function()
        if finished then return end
        finished = true
        Anim._busy = false
        UIManager:unschedule(tick)
        UIManager:unschedule(finish)
        if opts.done then
            local ok, err = pcall(opts.done)
            if not ok then logger.warn("AppDock animation: done failed", err) end
        end
        -- Keep the hand-off in the same regional fast-refresh path as the
        -- frames. A partial/full settle here causes a visible flash on E-Ink.
        local closed
        if opts.close_refresh == false then
            closed = pcall(UIManager.close, UIManager, overlay)
        else
            closed = pcall(UIManager.close, UIManager, overlay, "fast", overlay.dimen)
        end
        if not closed then
            pcall(UIManager.close, UIManager, overlay)
        end
        if opts.after then
            local ok, err = pcall(opts.after)
            if not ok then logger.warn("AppDock animation: after failed", err) end
        end
        if opts.cleanup then pcall(opts.cleanup) end
    end

    tick = function()
        if finished then return end
        frame = frame + 1
        progress = ease(frame / frames)
        local ok = pcall(function()
            UIManager:setDirty(overlay, "fast", overlay.dimen)
            if UIManager.forceRePaint then UIManager:forceRePaint() end
        end)
        if not ok or frame >= frames then
            finish()
        else
            UIManager:scheduleIn(interval, tick)
        end
    end

    Anim._busy = true
    -- Register the overlay without making UIManager repaint it. Paint the
    -- first moved frame directly into the already visible screen buffer, then
    -- enqueue only the refresh that actually displays that frame. This avoids
    -- the extra static/old-screen refresh immediately before the animation.
    local shown = pcall(UIManager.show, UIManager, overlay)
    if not shown then
        Anim._busy = false
        return bail()
    end
    local first_painted = false
    if type(UIManager.widgetRepaint) == "function" then
        first_painted = pcall(UIManager.widgetRepaint, UIManager, overlay, rect.x, rect.y)
    end
    if first_painted then
        pcall(UIManager.setDirty, UIManager, nil, "fast", rect)
        if UIManager.forceRePaint then UIManager:forceRePaint() end
    else
        pcall(UIManager.setDirty, UIManager, overlay, "fast", rect)
        if UIManager.forceRePaint then UIManager:forceRePaint() end
    end
    -- Safety net: whatever happens, the overlay never stays on screen.
    UIManager:scheduleIn(8 + frames * 0.6, finish)
    UIManager:scheduleIn(interval, tick)
    return true
end

return Anim
