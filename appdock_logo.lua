--[[--
Small, deterministic DApp logos for E-Ink displays.
They use only KOReader's BlitBuffer rectangles, so they scale cleanly and do
not require image assets or separate theme variants.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local Widget = require("ui/widget/widget")

local DAppLogo = Widget:extend{
    kind = "generic",
    size = 32,
    ink = Blitbuffer.COLOR_DARK_GRAY,
    dimen = nil,
}

local function line(bb, x0, y0, x1, y1, thickness, ink)
    local dx, dy = x1 - x0, y1 - y0
    local steps = math.max(math.abs(dx), math.abs(dy))
    if steps < 1 then
        bb:paintRect(math.floor(x0), math.floor(y0), thickness, thickness, ink)
        return
    end
    for step = 0, steps do
        local x = math.floor(x0 + dx * step / steps - thickness / 2)
        local y = math.floor(y0 + dy * step / steps - thickness / 2)
        bb:paintRect(x, y, thickness, thickness, ink)
    end
end

function DAppLogo:init()
    self.dimen = Geom:new{ w = self.size, h = self.size }
end

function DAppLogo:_paintClock(bb, x, y, size)
    local cx, cy = x + math.floor(size / 2), y + math.floor(size / 2)
    local radius = math.floor(size * 0.40)
    local dot = math.max(1, math.floor(size * 0.08))
    for index = 0, 11 do
        local angle = math.pi * 2 * index / 12
        local px = math.floor(cx + math.sin(angle) * radius - dot / 2)
        local py = math.floor(cy - math.cos(angle) * radius - dot / 2)
        bb:paintRect(px, py, dot, dot, self.ink)
    end
    line(bb, cx, cy, cx, cy - math.floor(radius * 0.58), math.max(1, dot), self.ink)
    line(bb, cx, cy, cx + math.floor(radius * 0.52), cy, math.max(1, dot), self.ink)
    bb:paintRect(cx - dot, cy - dot, dot * 2, dot * 2, self.ink)
end

function DAppLogo:_paintSettings(bb, x, y, size)
    local center = math.floor(size / 2)
    local spoke = math.max(2, math.floor(size * 0.12))
    local hub = math.max(4, math.floor(size * 0.36))
    local hub_x, hub_y = x + center - math.floor(hub / 2), y + center - math.floor(hub / 2)
    bb:paintRect(hub_x, hub_y, hub, hub, self.ink)
    bb:paintRect(x + center - math.floor(spoke / 2), y + math.floor(size * 0.06), spoke, math.floor(size * 0.25), self.ink)
    bb:paintRect(x + center - math.floor(spoke / 2), y + math.floor(size * 0.69), spoke, math.floor(size * 0.25), self.ink)
    bb:paintRect(x + math.floor(size * 0.06), y + center - math.floor(spoke / 2), math.floor(size * 0.25), spoke, self.ink)
    bb:paintRect(x + math.floor(size * 0.69), y + center - math.floor(spoke / 2), math.floor(size * 0.25), spoke, self.ink)
    local hole = math.max(2, math.floor(size * 0.15))
    bb:paintRect(x + center - math.floor(hole / 2), y + center - math.floor(hole / 2), hole, hole, Blitbuffer.COLOR_WHITE)
end

function DAppLogo:_paintHelp(bb, x, y, size)
    local cx = x + math.floor(size / 2)
    local top = y + math.floor(size * 0.13)
    local stroke = math.max(2, math.floor(size * 0.12))
    local arc = math.floor(size * 0.30)
    line(bb, cx - arc, top + arc, cx - arc, top, stroke, self.ink)
    line(bb, cx - arc, top, cx + arc, top, stroke, self.ink)
    line(bb, cx + arc, top, cx + arc, top + math.floor(arc * 0.55), stroke, self.ink)
    line(bb, cx + arc, top + math.floor(arc * 0.55), cx, top + math.floor(arc * 1.05), stroke, self.ink)
    line(bb, cx, top + math.floor(arc * 1.05), cx, top + math.floor(arc * 1.42), stroke, self.ink)
    bb:paintRect(cx - math.floor(stroke / 2), y + math.floor(size * 0.78), stroke, stroke, self.ink)
end

function DAppLogo:_paintAppDock(bb, x, y, size)
    local stroke = math.max(1, math.floor(size * 0.075))
    local function point(px, py) return x + math.floor(size * px), y + math.floor(size * py) end
    local function segment(x0, y0, x1, y1)
        local sx, sy = point(x0, y0)
        local ex, ey = point(x1, y1)
        line(bb, sx, sy, ex, ey, stroke, self.ink)
    end
    -- Friendly bunny mark derived from the user’s original ear, crown and sleepy-eye sketch.
    segment(0.35, 0.34, 0.20, 0.26); segment(0.20, 0.26, 0.12, 0.11); segment(0.12, 0.11, 0.19, 0.04)
    segment(0.19, 0.04, 0.31, 0.09); segment(0.31, 0.09, 0.43, 0.30); segment(0.43, 0.30, 0.35, 0.34)
    segment(0.65, 0.34, 0.71, 0.15); segment(0.71, 0.15, 0.80, 0.03); segment(0.80, 0.03, 0.89, 0.12)
    segment(0.89, 0.12, 0.84, 0.27); segment(0.84, 0.27, 0.65, 0.34)
    segment(0.35, 0.34, 0.46, 0.29); segment(0.46, 0.29, 0.57, 0.29); segment(0.57, 0.29, 0.65, 0.34)
    segment(0.35, 0.34, 0.28, 0.50); segment(0.28, 0.50, 0.28, 0.83)
    segment(0.65, 0.34, 0.72, 0.50); segment(0.72, 0.50, 0.72, 0.83)
    segment(0.39, 0.55, 0.43, 0.58); segment(0.43, 0.58, 0.47, 0.54)
    segment(0.54, 0.54, 0.58, 0.58); segment(0.58, 0.58, 0.62, 0.55)
end

function DAppLogo:_paintBrowser(bb, x, y, size)
    local cx, cy = x + math.floor(size / 2), y + math.floor(size / 2)
    local radius = math.floor(size * 0.40)
    local dot = math.max(1, math.floor(size * 0.07))
    for index = 0, 11 do
        local angle = math.pi * 2 * index / 12
        local px = math.floor(cx + math.sin(angle) * radius - dot / 2)
        local py = math.floor(cy - math.cos(angle) * radius - dot / 2)
        bb:paintRect(px, py, dot, dot, self.ink)
    end
    line(bb, cx - radius, cy, cx + radius, cy, dot, self.ink)
    line(bb, cx, cy - radius, cx, cy + radius, dot, self.ink)
    line(bb, cx - math.floor(radius * .72), cy - math.floor(radius * .55), cx + math.floor(radius * .72), cy - math.floor(radius * .55), dot, self.ink)
    line(bb, cx - math.floor(radius * .72), cy + math.floor(radius * .55), cx + math.floor(radius * .72), cy + math.floor(radius * .55), dot, self.ink)
end

function DAppLogo:_paintNetwork(bb, x, y, size)
    local dot = math.max(2, math.floor(size * 0.16))
    local cx = x + math.floor(size / 2)
    local top_y = y + math.floor(size * 0.18)
    local left_x = x + math.floor(size * 0.20)
    local right_x = x + math.floor(size * 0.80)
    local bottom_y = y + math.floor(size * 0.76)
    line(bb, cx, top_y, left_x, bottom_y, math.max(1, math.floor(size * 0.08)), self.ink)
    line(bb, cx, top_y, right_x, bottom_y, math.max(1, math.floor(size * 0.08)), self.ink)
    line(bb, left_x, bottom_y, right_x, bottom_y, math.max(1, math.floor(size * 0.08)), self.ink)
    for _, point in ipairs({ { cx, top_y }, { left_x, bottom_y }, { right_x, bottom_y } }) do
        bb:paintRect(point[1] - math.floor(dot / 2), point[2] - math.floor(dot / 2), dot, dot, self.ink)
    end
end

function DAppLogo:_paintDisplay(bb, x, y, size)
    local border = math.max(1, math.floor(size * 0.09))
    local screen_x = x + math.floor(size * 0.10)
    local screen_y = y + math.floor(size * 0.17)
    local screen_w = math.floor(size * 0.80)
    local screen_h = math.floor(size * 0.58)
    bb:paintRect(screen_x, screen_y, screen_w, screen_h, self.ink)
    bb:paintRect(screen_x + border, screen_y + border, screen_w - border * 2, screen_h - border * 2, Blitbuffer.COLOR_WHITE)
    bb:paintRect(x + math.floor(size * 0.39), y + math.floor(size * 0.82), math.floor(size * 0.22), math.max(1, border), self.ink)
end

function DAppLogo:_paintAppStore(bb, x, y, size)
    local border = math.max(1, math.floor(size * 0.08))
    local bag_x = x + math.floor(size * 0.16)
    local bag_y = y + math.floor(size * 0.34)
    local bag_w = math.floor(size * 0.68)
    local bag_h = math.floor(size * 0.50)
    bb:paintRect(bag_x, bag_y, bag_w, bag_h, self.ink)
    bb:paintRect(bag_x + border, bag_y + border, bag_w - border * 2, bag_h - border * 2, Blitbuffer.COLOR_WHITE)
    local handle_w = math.floor(size * 0.32)
    bb:paintRect(x + math.floor((size - handle_w) / 2), y + math.floor(size * 0.17), handle_w, border, self.ink)
    bb:paintRect(x + math.floor(size * 0.34), y + math.floor(size * 0.17), border, math.floor(size * 0.18), self.ink)
    bb:paintRect(x + math.floor(size * 0.62), y + math.floor(size * 0.17), border, math.floor(size * 0.18), self.ink)
end

function DAppLogo:_paintOther(bb, x, y, size)
    local dot = math.max(2, math.floor(size * 0.18))
    local cx = x + math.floor((size - dot) / 2)
    for _, factor in ipairs({ 0.19, 0.46, 0.73 }) do
        bb:paintRect(cx, y + math.floor(size * factor), dot, dot, self.ink)
    end
end

function DAppLogo:_paintFolder(bb, x, y, size)
    local border = math.max(1, math.floor(size * 0.08))
    local tab_h = math.floor(size * 0.22)
    local folder_y = y + math.floor(size * 0.30)
    bb:paintRect(x + math.floor(size * 0.12), y + math.floor(size * 0.13), math.floor(size * 0.38), tab_h, self.ink)
    bb:paintRect(x + math.floor(size * 0.08), folder_y, math.floor(size * 0.84), math.floor(size * 0.56), self.ink)
    bb:paintRect(x + math.floor(size * 0.08) + border, folder_y + border, math.floor(size * 0.84) - border * 2, math.floor(size * 0.56) - border * 2, Blitbuffer.COLOR_WHITE)
end

local EXTENDED_KINDS = {
    "archive", "bookmark", "calendar", "camera", "chat", "cloud", "code", "calculator",
    "dictionary", "document", "download", "gallery", "location", "mail", "map", "music",
    "notes", "podcast", "reading", "rss", "search", "security", "sync", "tasks", "terminal",
    "timer", "translate", "upload", "weather",
}

function DAppLogo.availableKinds()
    local kinds = {
        "analog_clock", "app_store", "appdock", "display", "file_manager", "help", "network", "other",
        "settings", "web_browser",
    }
    for index, kind in ipairs(EXTENDED_KINDS) do kinds[#kinds + 1] = kind end
    table.sort(kinds)
    return kinds
end

function DAppLogo:_paintExtended(bb, x, y, size, kind)
    local stroke = math.max(1, math.floor(size * 0.09))
    local thin = math.max(1, math.floor(size * 0.06))
    local cx, cy = x + math.floor(size / 2), y + math.floor(size / 2)
    local left, right = x + math.floor(size * 0.14), x + math.floor(size * 0.86)
    local top, bottom = y + math.floor(size * 0.14), y + math.floor(size * 0.86)
    local function rect(px, py, width, height)
        bb:paintRect(math.floor(px), math.floor(py), math.max(1, math.floor(width)), math.max(1, math.floor(height)), self.ink)
    end
    local function hollow(px, py, width, height, border)
        rect(px, py, width, height)
        bb:paintRect(math.floor(px + border), math.floor(py + border), math.max(1, math.floor(width - border * 2)), math.max(1, math.floor(height - border * 2)), Blitbuffer.COLOR_WHITE)
    end

    if kind == "document" or kind == "notes" then
        hollow(left, top, right - left, bottom - top, stroke)
        for row = 0, 2 do rect(x + math.floor(size * 0.28), y + math.floor(size * (0.35 + row * 0.16)), math.floor(size * 0.42), thin) end
        if kind == "notes" then rect(x + math.floor(size * 0.23), y + math.floor(size * 0.22), math.floor(size * 0.16), thin) end
    elseif kind == "tasks" then
        for row = 0, 2 do
            local row_y = y + math.floor(size * (0.25 + row * 0.22))
            hollow(x + math.floor(size * 0.16), row_y, math.floor(size * 0.16), math.floor(size * 0.16), thin)
            line(bb, x + math.floor(size * 0.18), row_y + math.floor(size * 0.08), x + math.floor(size * 0.22), row_y + math.floor(size * 0.13), thin, self.ink)
            line(bb, x + math.floor(size * 0.22), row_y + math.floor(size * 0.13), x + math.floor(size * 0.30), row_y + math.floor(size * 0.03), thin, self.ink)
            rect(x + math.floor(size * 0.40), row_y + math.floor(size * 0.07), math.floor(size * 0.40), thin)
        end
    elseif kind == "calendar" then
        hollow(left, y + math.floor(size * 0.20), right - left, math.floor(size * 0.65), stroke)
        rect(left, y + math.floor(size * 0.34), right - left, stroke)
        rect(x + math.floor(size * 0.30), top, stroke, math.floor(size * 0.18))
        rect(x + math.floor(size * 0.66), top, stroke, math.floor(size * 0.18))
        for row = 0, 1 do for column = 0, 2 do rect(x + math.floor(size * (0.29 + column * 0.18)), y + math.floor(size * (0.48 + row * 0.17)), thin * 2, thin * 2) end end
    elseif kind == "timer" then
        self:_paintClock(bb, x, y + math.floor(size * 0.06), math.floor(size * 0.88))
        rect(cx - stroke, top, stroke * 2, math.floor(size * 0.12))
        rect(x + math.floor(size * 0.69), y + math.floor(size * 0.20), stroke, math.floor(size * 0.14))
    elseif kind == "calculator" then
        hollow(left, top, right - left, bottom - top, stroke)
        rect(x + math.floor(size * 0.27), y + math.floor(size * 0.25), math.floor(size * 0.46), math.floor(size * 0.14))
        for row = 0, 1 do for column = 0, 2 do rect(x + math.floor(size * (0.27 + column * 0.18)), y + math.floor(size * (0.50 + row * 0.16)), math.floor(size * 0.10), math.floor(size * 0.10)) end end
    elseif kind == "dictionary" or kind == "reading" then
        line(bb, cx, top, cx, bottom, stroke, self.ink)
        line(bb, cx, top + stroke, left, y + math.floor(size * 0.27), stroke, self.ink)
        line(bb, left, y + math.floor(size * 0.27), left, bottom - stroke, stroke, self.ink)
        line(bb, left, bottom - stroke, cx, bottom, stroke, self.ink)
        line(bb, cx, top + stroke, right, y + math.floor(size * 0.27), stroke, self.ink)
        line(bb, right, y + math.floor(size * 0.27), right, bottom - stroke, stroke, self.ink)
        line(bb, right, bottom - stroke, cx, bottom, stroke, self.ink)
        if kind == "dictionary" then rect(x + math.floor(size * 0.29), y + math.floor(size * 0.42), math.floor(size * 0.13), thin) end
    elseif kind == "music" or kind == "podcast" then
        line(bb, x + math.floor(size * 0.61), top, x + math.floor(size * 0.61), y + math.floor(size * 0.68), stroke, self.ink)
        line(bb, x + math.floor(size * 0.61), top, x + math.floor(size * 0.82), y + math.floor(size * 0.22), stroke, self.ink)
        rect(x + math.floor(size * 0.25), y + math.floor(size * 0.65), math.floor(size * 0.22), math.floor(size * 0.16))
        rect(x + math.floor(size * 0.54), y + math.floor(size * 0.65), math.floor(size * 0.22), math.floor(size * 0.16))
        if kind == "podcast" then
            hollow(x + math.floor(size * 0.15), y + math.floor(size * 0.17), math.floor(size * 0.33), math.floor(size * 0.33), thin)
        end
    elseif kind == "gallery" then
        hollow(left, top, right - left, bottom - top, stroke)
        rect(x + math.floor(size * 0.29), y + math.floor(size * 0.31), math.floor(size * 0.13), math.floor(size * 0.13))
        line(bb, x + math.floor(size * 0.24), y + math.floor(size * 0.75), x + math.floor(size * 0.47), y + math.floor(size * 0.51), stroke, self.ink)
        line(bb, x + math.floor(size * 0.47), y + math.floor(size * 0.51), x + math.floor(size * 0.76), y + math.floor(size * 0.75), stroke, self.ink)
    elseif kind == "camera" then
        hollow(x + math.floor(size * 0.12), y + math.floor(size * 0.32), math.floor(size * 0.76), math.floor(size * 0.48), stroke)
        rect(x + math.floor(size * 0.31), y + math.floor(size * 0.22), math.floor(size * 0.25), math.floor(size * 0.12))
        hollow(x + math.floor(size * 0.36), y + math.floor(size * 0.43), math.floor(size * 0.28), math.floor(size * 0.28), stroke)
    elseif kind == "search" then
        hollow(x + math.floor(size * 0.17), y + math.floor(size * 0.17), math.floor(size * 0.46), math.floor(size * 0.46), stroke)
        line(bb, x + math.floor(size * 0.55), y + math.floor(size * 0.55), x + math.floor(size * 0.82), y + math.floor(size * 0.82), stroke, self.ink)
    elseif kind == "download" or kind == "upload" then
        local direction = kind == "download" and 1 or -1
        local start_y, end_y = direction == 1 and y + math.floor(size * 0.24) or y + math.floor(size * 0.69), direction == 1 and y + math.floor(size * 0.66) or y + math.floor(size * 0.27)
        line(bb, cx, start_y, cx, end_y, stroke, self.ink)
        line(bb, cx, end_y, x + math.floor(size * 0.38), end_y - direction * math.floor(size * 0.14), stroke, self.ink)
        line(bb, cx, end_y, x + math.floor(size * 0.62), end_y - direction * math.floor(size * 0.14), stroke, self.ink)
        rect(x + math.floor(size * 0.22), y + math.floor(size * 0.79), math.floor(size * 0.56), stroke)
    elseif kind == "cloud" then
        hollow(x + math.floor(size * 0.15), y + math.floor(size * 0.48), math.floor(size * 0.70), math.floor(size * 0.25), stroke)
        hollow(x + math.floor(size * 0.28), y + math.floor(size * 0.31), math.floor(size * 0.30), math.floor(size * 0.30), stroke)
        hollow(x + math.floor(size * 0.50), y + math.floor(size * 0.38), math.floor(size * 0.27), math.floor(size * 0.27), stroke)
    elseif kind == "terminal" then
        hollow(left, top, right - left, bottom - top, stroke)
        line(bb, x + math.floor(size * 0.28), y + math.floor(size * 0.38), x + math.floor(size * 0.43), y + math.floor(size * 0.50), thin, self.ink)
        line(bb, x + math.floor(size * 0.43), y + math.floor(size * 0.50), x + math.floor(size * 0.28), y + math.floor(size * 0.62), thin, self.ink)
        rect(x + math.floor(size * 0.51), y + math.floor(size * 0.63), math.floor(size * 0.20), thin)
    elseif kind == "code" then
        line(bb, x + math.floor(size * 0.38), y + math.floor(size * 0.26), x + math.floor(size * 0.20), cy, stroke, self.ink)
        line(bb, x + math.floor(size * 0.20), cy, x + math.floor(size * 0.38), y + math.floor(size * 0.74), stroke, self.ink)
        line(bb, x + math.floor(size * 0.62), y + math.floor(size * 0.26), x + math.floor(size * 0.80), cy, stroke, self.ink)
        line(bb, x + math.floor(size * 0.80), cy, x + math.floor(size * 0.62), y + math.floor(size * 0.74), stroke, self.ink)
    elseif kind == "weather" then
        for index = 0, 7 do
            local angle = math.pi * 2 * index / 8
            line(bb, cx + math.sin(angle) * size * 0.21, cy + math.cos(angle) * size * 0.21, cx + math.sin(angle) * size * 0.34, cy + math.cos(angle) * size * 0.34, thin, self.ink)
        end
        hollow(cx - math.floor(size * 0.15), cy - math.floor(size * 0.15), math.floor(size * 0.30), math.floor(size * 0.30), stroke)
    elseif kind == "translate" then
        hollow(left, top, right - left, bottom - top, stroke)
        rect(x + math.floor(size * 0.28), y + math.floor(size * 0.31), math.floor(size * 0.13), math.floor(size * 0.35))
        rect(x + math.floor(size * 0.22), y + math.floor(size * 0.48), math.floor(size * 0.25), thin)
        line(bb, x + math.floor(size * 0.57), y + math.floor(size * 0.34), x + math.floor(size * 0.73), y + math.floor(size * 0.65), thin, self.ink)
        line(bb, x + math.floor(size * 0.73), y + math.floor(size * 0.34), x + math.floor(size * 0.57), y + math.floor(size * 0.65), thin, self.ink)
    elseif kind == "map" or kind == "location" then
        if kind == "map" then
            line(bb, x + math.floor(size * 0.20), y + math.floor(size * 0.25), x + math.floor(size * 0.40), y + math.floor(size * 0.18), stroke, self.ink)
            line(bb, x + math.floor(size * 0.40), y + math.floor(size * 0.18), x + math.floor(size * 0.62), y + math.floor(size * 0.28), stroke, self.ink)
            line(bb, x + math.floor(size * 0.62), y + math.floor(size * 0.28), x + math.floor(size * 0.80), y + math.floor(size * 0.20), stroke, self.ink)
            line(bb, x + math.floor(size * 0.20), y + math.floor(size * 0.72), x + math.floor(size * 0.40), y + math.floor(size * 0.65), stroke, self.ink)
            line(bb, x + math.floor(size * 0.40), y + math.floor(size * 0.65), x + math.floor(size * 0.62), y + math.floor(size * 0.75), stroke, self.ink)
            line(bb, x + math.floor(size * 0.62), y + math.floor(size * 0.75), x + math.floor(size * 0.80), y + math.floor(size * 0.67), stroke, self.ink)
            line(bb, x + math.floor(size * 0.20), y + math.floor(size * 0.25), x + math.floor(size * 0.20), y + math.floor(size * 0.72), stroke, self.ink)
            line(bb, x + math.floor(size * 0.40), y + math.floor(size * 0.18), x + math.floor(size * 0.40), y + math.floor(size * 0.65), stroke, self.ink)
            line(bb, x + math.floor(size * 0.62), y + math.floor(size * 0.28), x + math.floor(size * 0.62), y + math.floor(size * 0.75), stroke, self.ink)
            line(bb, x + math.floor(size * 0.80), y + math.floor(size * 0.20), x + math.floor(size * 0.80), y + math.floor(size * 0.67), stroke, self.ink)
        else
            hollow(cx - math.floor(size * 0.18), y + math.floor(size * 0.17), math.floor(size * 0.36), math.floor(size * 0.36), stroke)
            line(bb, cx, y + math.floor(size * 0.50), cx, y + math.floor(size * 0.80), stroke, self.ink)
            line(bb, cx, y + math.floor(size * 0.80), x + math.floor(size * 0.40), y + math.floor(size * 0.63), stroke, self.ink)
            line(bb, cx, y + math.floor(size * 0.80), x + math.floor(size * 0.60), y + math.floor(size * 0.63), stroke, self.ink)
        end
    elseif kind == "security" then
        line(bb, cx, top, right, y + math.floor(size * 0.30), stroke, self.ink)
        line(bb, right, y + math.floor(size * 0.30), x + math.floor(size * 0.72), y + math.floor(size * 0.67), stroke, self.ink)
        line(bb, x + math.floor(size * 0.72), y + math.floor(size * 0.67), cx, bottom, stroke, self.ink)
        line(bb, cx, bottom, x + math.floor(size * 0.28), y + math.floor(size * 0.67), stroke, self.ink)
        line(bb, x + math.floor(size * 0.28), y + math.floor(size * 0.67), left, y + math.floor(size * 0.30), stroke, self.ink)
        line(bb, left, y + math.floor(size * 0.30), cx, top, stroke, self.ink)
        hollow(cx - thin, cy, thin * 2, math.floor(size * 0.22), thin)
    elseif kind == "archive" then
        hollow(left, y + math.floor(size * 0.31), right - left, math.floor(size * 0.52), stroke)
        hollow(x + math.floor(size * 0.10), y + math.floor(size * 0.20), math.floor(size * 0.80), math.floor(size * 0.16), stroke)
        rect(x + math.floor(size * 0.38), y + math.floor(size * 0.56), math.floor(size * 0.24), thin)
    elseif kind == "sync" then
        line(bb, x + math.floor(size * 0.22), y + math.floor(size * 0.42), x + math.floor(size * 0.68), y + math.floor(size * 0.42), stroke, self.ink)
        line(bb, x + math.floor(size * 0.68), y + math.floor(size * 0.42), x + math.floor(size * 0.57), y + math.floor(size * 0.29), stroke, self.ink)
        line(bb, x + math.floor(size * 0.68), y + math.floor(size * 0.42), x + math.floor(size * 0.57), y + math.floor(size * 0.55), stroke, self.ink)
        line(bb, x + math.floor(size * 0.78), y + math.floor(size * 0.63), x + math.floor(size * 0.32), y + math.floor(size * 0.63), stroke, self.ink)
        line(bb, x + math.floor(size * 0.32), y + math.floor(size * 0.63), x + math.floor(size * 0.43), y + math.floor(size * 0.50), stroke, self.ink)
        line(bb, x + math.floor(size * 0.32), y + math.floor(size * 0.63), x + math.floor(size * 0.43), y + math.floor(size * 0.76), stroke, self.ink)
    elseif kind == "mail" then
        hollow(left, y + math.floor(size * 0.27), right - left, math.floor(size * 0.50), stroke)
        line(bb, left + stroke, y + math.floor(size * 0.31), cx, y + math.floor(size * 0.55), thin, self.ink)
        line(bb, cx, y + math.floor(size * 0.55), right - stroke, y + math.floor(size * 0.31), thin, self.ink)
    elseif kind == "chat" then
        hollow(left, y + math.floor(size * 0.24), right - left, math.floor(size * 0.47), stroke)
        line(bb, x + math.floor(size * 0.35), y + math.floor(size * 0.71), x + math.floor(size * 0.27), y + math.floor(size * 0.83), stroke, self.ink)
        for index = 0, 2 do rect(x + math.floor(size * (0.32 + index * 0.18)), y + math.floor(size * 0.45), thin * 2, thin * 2) end
    elseif kind == "bookmark" then
        hollow(x + math.floor(size * 0.30), top, math.floor(size * 0.40), math.floor(size * 0.70), stroke)
        line(bb, x + math.floor(size * 0.30), y + math.floor(size * 0.84), cx, y + math.floor(size * 0.68), stroke, self.ink)
        line(bb, cx, y + math.floor(size * 0.68), x + math.floor(size * 0.70), y + math.floor(size * 0.84), stroke, self.ink)
    elseif kind == "rss" then
        rect(left, y + math.floor(size * 0.70), stroke * 2, stroke * 2)
        for radius_index = 1, 2 do
            local radius = math.floor(size * (0.18 + radius_index * 0.16))
            for step = 0, 8 do
                local angle = math.pi * 1.5 + math.pi * step / 16
                local px = left + math.cos(angle) * radius
                local py = y + math.floor(size * 0.70) + math.sin(angle) * radius
                rect(px, py, thin, thin)
            end
        end
    else
        rect(cx - math.floor(size * 0.18), cy - math.floor(size * 0.18), math.floor(size * 0.36), math.floor(size * 0.36))
    end
end

function DAppLogo:paintTo(bb, x, y)
    if self.kind == "analog_clock" then
        self:_paintClock(bb, x, y, self.size)
    elseif self.kind == "settings" then
        self:_paintSettings(bb, x, y, self.size)
    elseif self.kind == "file_manager" then
        self:_paintFolder(bb, x, y, self.size)
    elseif self.kind == "network" then
        self:_paintNetwork(bb, x, y, self.size)
    elseif self.kind == "display" then
        self:_paintDisplay(bb, x, y, self.size)
    elseif self.kind == "other" then
        self:_paintOther(bb, x, y, self.size)
    elseif self.kind == "app_store" then
        self:_paintAppStore(bb, x, y, self.size)
    elseif self.kind == "web_browser" then
        self:_paintBrowser(bb, x, y, self.size)
    elseif self.kind == "help" then
        self:_paintHelp(bb, x, y, self.size)
    elseif self.kind == "appdock" then
        self:_paintAppDock(bb, x, y, self.size)
    else
        for _, kind in ipairs(EXTENDED_KINDS) do
            if self.kind == kind then
                self:_paintExtended(bb, x, y, self.size, kind)
                return
            end
        end
        local mark = math.max(3, math.floor(self.size * 0.48))
        bb:paintRect(x + math.floor((self.size - mark) / 2), y + math.floor((self.size - mark) / 2), mark, mark, self.ink)
    end
end

return DAppLogo
