-- Small, deterministic eInk motion helper.
-- Every frame invalidates exactly once with a fast refresh. Animations are
-- deliberately short so they never keep a stale widget alive for long.
local UIManager = require("ui/uimanager")
local Motion = {}
function Motion.run(target, frames, interval, draw, done, region)
    frames = math.max(1, math.floor(frames or 1))
    interval = tonumber(interval) or 0.045
    local frame = 0
    local tick
    tick = function()
        frame = frame + 1
        if draw then draw(frame, frames) end
        UIManager:setDirty(target, "fast", region)
        if UIManager.forceRePaint then UIManager:forceRePaint() end
        if frame < frames then
            UIManager:scheduleIn(interval, tick)
        elseif done then
            -- Clear accumulated ghosting after the last fast frame. A full
            -- refresh here is intentional and happens only once per gesture.
            UIManager:setDirty("all", "full")
            if UIManager.forceRePaint then UIManager:forceRePaint() end
            done()
        end
    end
    tick()
end
return Motion
