--[[--
Snake for AppDock.

An offline E-Ink adaptation of the classic grid game. Only the playfield is
drawn for each movement step and refreshed with KOReader's fast waveform.
Static controls are rebuilt only when status or score changes.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Screen = Device.screen

local GRID_W = 20
local GRID_H = 14
local START_STEP_SECONDS = 0.16
local MIN_STEP_SECONDS = 0.075

local direction_delta = {
    left = { x = -1, y = 0 }, right = { x = 1, y = 0 },
    up = { x = 0, y = -1 }, down = { x = 0, y = 1 },
}
local opposite = { left = "right", right = "left", up = "down", down = "up" }

local function scale(value) return Screen:scaleBySize(value) end
local function clamp(value, low, high) return math.max(low, math.min(high, value)) end

local function emptySizedWidget(width, height)
    return CenterContainer:new{ dimen = Geom:new{ w = width, h = height }, HorizontalSpan:new{ width = 0 } }
end

local SnakeSession = {}
SnakeSession.__index = SnakeSession

function SnakeSession.new(on_event)
    local self = setmetatable({
        canvas = nil, paused = true, over = false, won = false, score = 0,
        snake = {}, food = nil, direction = "right", pending_direction = "right",
        food_cursor = 0, frames = 0, on_event = on_event,
    }, SnakeSession)
    self._tick = function() self:tick() end
    self:reset(true)
    return self
end

function SnakeSession:setCanvas(canvas)
    self.canvas = canvas
    if canvas then canvas.session = self end
end

function SnakeSession:emit(kind, message)
    if self.on_event then self.on_event(kind, message) end
end

function SnakeSession:isOccupied(x, y, last_index)
    last_index = last_index or #self.snake
    for index = 1, last_index do
        local segment = self.snake[index]
        if segment.x == x and segment.y == y then return true end
    end
    return false
end

function SnakeSession:spawnFood()
    local total = GRID_W * GRID_H
    if #self.snake >= total then
        self:finish()
        return false
    end
    for attempt = 1, total do
        self.food_cursor = (self.food_cursor + 73) % total
        local x = self.food_cursor % GRID_W
        local y = math.floor(self.food_cursor / GRID_W)
        if not self:isOccupied(x, y) then
            self.food = { x = x, y = y }
            return true
        end
    end
    self:finish()
    return false
end

function SnakeSession:reset(silent)
    UIManager:unschedule(self._tick)
    self.paused, self.over, self.won = true, false, false
    self.score, self.frames, self.food_cursor = 0, 0, 0
    self.direction, self.pending_direction = "right", "right"
    self.snake = { { x = 12, y = 7 }, { x = 11, y = 7 }, { x = 10, y = 7 } }
    self:spawnFood()
    if not silent then self:emit("ready", _("Ready — choose a direction or tap Play.")) end
end

function SnakeSession:stepSeconds()
    return math.max(MIN_STEP_SECONDS, START_STEP_SECONDS - math.floor(self.score / 4) * 0.012)
end

function SnakeSession:start()
    if self.over or self.won then self:reset() end
    if not self.paused then return true end
    self.paused = false
    self:emit("playing", _("Use the arrows to steer."))
    UIManager:unschedule(self._tick)
    UIManager:scheduleIn(self:stepSeconds(), self._tick)
    return true
end

function SnakeSession:pause()
    if self.paused then return end
    self.paused = true
    UIManager:unschedule(self._tick)
    self:emit("paused", _("Paused. Tap Play to continue."))
end

function SnakeSession:crash()
    self.over, self.paused = true, true
    UIManager:unschedule(self._tick)
    self:emit("crash", _("Game over — score: ") .. tostring(self.score) .. _(". Tap Restart."))
end

function SnakeSession:finish()
    self.won, self.paused = true, true
    UIManager:unschedule(self._tick)
    self:emit("complete", _("Board cleared! Tap Restart for another run."))
end

function SnakeSession:setDirection(direction)
    if not direction_delta[direction] or opposite[self.direction] == direction then return false end
    self.pending_direction = direction
    return true
end

function SnakeSession:inputDirection(direction)
    if self.over or self.won then self:reset() end
    local accepted = self:setDirection(direction)
    if self.paused then self:start() end
    if self.canvas then self.canvas:refreshFast() end
    return accepted
end

function SnakeSession:step()
    if self.paused or self.over or self.won then return false end
    self.direction = self.pending_direction
    local delta = direction_delta[self.direction]
    local head = self.snake[1]
    local next_x, next_y = head.x + delta.x, head.y + delta.y
    if next_x < 0 or next_x >= GRID_W or next_y < 0 or next_y >= GRID_H then
        self:crash()
        return false
    end
    local eating = self.food and next_x == self.food.x and next_y == self.food.y
    local collision_last = eating and #self.snake or #self.snake - 1
    if self:isOccupied(next_x, next_y, collision_last) then
        self:crash()
        return false
    end
    table.insert(self.snake, 1, { x = next_x, y = next_y })
    if eating then
        self.score = self.score + 1
        self:emit("score", _("Score: ") .. tostring(self.score))
        if not self:spawnFood() then return false end
    else
        table.remove(self.snake)
    end
    self.frames = self.frames + 1
    return true
end

function SnakeSession:tick()
    if not self:step() then
        if self.canvas then self.canvas:refreshFast() end
        return
    end
    if self.canvas then self.canvas:refreshFast() end
    UIManager:scheduleIn(self:stepSeconds(), self._tick)
end

local SnakeCanvas = InputContainer:extend{
    session = nil, width = nil, height = nil, dimen = nil,
    _origin_x = 0, _origin_y = 0, _cell = 1, _board_x = 0, _board_y = 0,
}

function SnakeCanvas:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self.ges_events = { TapSnakeStart = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function SnakeCanvas:_layout(x, y)
    local cell = math.max(3, math.floor(math.min((self.width - 8) / GRID_W, (self.height - 8) / GRID_H)))
    self._cell = cell
    self._board_x = x + math.floor((self.width - GRID_W * cell) / 2)
    self._board_y = y + math.floor((self.height - GRID_H * cell) / 2)
end

function SnakeCanvas:_paintCell(bb, grid_x, grid_y, color, inset)
    inset = inset or 0
    local size = math.max(1, self._cell - inset * 2)
    bb:paintRect(self._board_x + grid_x * self._cell + inset, self._board_y + grid_y * self._cell + inset, size, size, color)
end

function SnakeCanvas:paintTo(bb, x, y)
    local range = self.ges_events.TapSnakeStart[1].range
    range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    self._origin_x, self._origin_y = x, y
    self:_layout(x, y)
    bb:paintRect(x, y, self.width, self.height, Blitbuffer.COLOR_WHITE)
    local board_w, board_h = GRID_W * self._cell, GRID_H * self._cell
    bb:paintRect(self._board_x - 2, self._board_y - 2, board_w + 4, board_h + 4, Blitbuffer.COLOR_BLACK)
    bb:paintRect(self._board_x, self._board_y, board_w, board_h, Blitbuffer.COLOR_WHITE)
    local session = self.session
    if not session then return end
    if session.food then
        self:_paintCell(bb, session.food.x, session.food.y, Blitbuffer.COLOR_DARK_GRAY, math.max(1, math.floor(self._cell / 4)))
    end
    for index, segment in ipairs(session.snake) do
        self:_paintCell(bb, segment.x, segment.y, Blitbuffer.COLOR_BLACK, index == 1 and 0 or 1)
        if index == 1 and self._cell >= 9 then
            local eye = math.max(1, math.floor(self._cell / 6))
            local eye_y = self._board_y + segment.y * self._cell + math.floor(self._cell / 3)
            bb:paintRect(self._board_x + segment.x * self._cell + math.floor(self._cell / 4), eye_y, eye, eye, Blitbuffer.COLOR_WHITE)
            bb:paintRect(self._board_x + segment.x * self._cell + math.floor(self._cell * .62), eye_y, eye, eye, Blitbuffer.COLOR_WHITE)
        end
    end
end

function SnakeCanvas:refreshFast()
    if not UIManager.widgetRepaint or not UIManager.setDirty then return false end
    UIManager:widgetRepaint(self, self._origin_x, self._origin_y)
    UIManager:setDirty(nil, "fast", Geom:new{ x = self._origin_x, y = self._origin_y, w = self.width, h = self.height })
    if UIManager.forceRePaint then UIManager:forceRePaint() end
    if UIManager.yieldToEPDC then UIManager:yieldToEPDC() end
    return true
end

function SnakeCanvas:onTapSnakeStart()
    if self.session then
        if self.session.over or self.session.won then self.session:reset() end
        self.session:start()
        self:refreshFast()
    end
    return true
end

local GameButton = InputContainer:extend{ title = "", width = nil, height = nil, callback = nil, primary = false, dimen = nil }
function GameButton:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self[1] = FrameContainer:new{
        width = self.width, height = self.height, padding = 0, bordersize = 0,
        radius = math.max(4, math.floor(self.height * .24)),
        background = self.primary and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_LIGHT_GRAY,
        CenterContainer:new{ dimen = self.dimen, TextWidget:new{
            text = self.title, face = Font:getFace("smallinfofont", math.max(scale(8), math.floor(self.height * .31))),
            fgcolor = self.primary and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK, bold = true,
            max_width = self.width - scale(8),
        } },
    }
    self.ges_events = { TapSnakeButton = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end
function GameButton:paintTo(bb, x, y)
    local range = self.ges_events.TapSnakeButton[1].range
    range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    return InputContainer.paintTo(self, bb, x, y)
end
function GameButton:onTapSnakeButton() if self.callback then self.callback() end; return true end

local SnakePane = InputContainer:extend{ session = nil }
function SnakePane:_direction(direction)
    if self.session then self.session:inputDirection(direction) end
    return true
end
function SnakePane:onSnakeLeft() return self:_direction("left") end
function SnakePane:onSnakeRight() return self:_direction("right") end
function SnakePane:onSnakeUp() return self:_direction("up") end
function SnakePane:onSnakeDown() return self:_direction("down") end
function SnakePane:onSwipeSnake(_, gesture)
    local directions = { west = "left", east = "right", north = "up", south = "down" }
    local direction = gesture and directions[gesture.direction]
    if direction then return self:_direction(direction) end
    return false
end
function SnakePane:onSnakeToggle()
    if self.session then
        if self.session.paused then self.session:start() else self.session:pause() end
        if self.session.canvas then self.session.canvas:refreshFast() end
    end
    return true
end

local function stateFor(instance, context)
    if instance.snake then return instance.snake end
    local state = { status = _("Ready — choose a direction or tap Play."), session = nil }
    state.session = SnakeSession.new(function(kind, message)
        state.status = message
        if context and context.requestRebuild and (kind == "ready" or kind == "playing" or kind == "paused" or kind == "crash" or kind == "complete" or kind == "score") then
            context.requestRebuild("ui")
        end
    end)
    instance.snake = state
    return state
end

return {
    id = "snake",
    version = "1.0.1",
    title = "Snake",
    subtitle = "Fast-refresh grid runner",
    symbol = "S",
    logo = "other",
    buildPane = function(instance, context)
        local state = stateFor(instance, context)
        local width, height = context.dimen.w, context.dimen.h
        local px = context.px or scale
        local margin, gap = px(10), px(6)
        local header_h, action_h, direction_h, footer_h = px(38), px(31), px(31), px(15)
        local arena_h = math.max(px(100), height - header_h - action_h - direction_h - footer_h - 4 * gap)
        local arena_y = header_h
        local action_y = arena_y + arena_h + gap
        local direction_y = action_y + action_h + gap
        local pane = SnakePane:new{ dimen = Geom:new{ w = width, h = height }, session = state.session }
        function pane:onDeactivate()
            if self.session then self.session:pause() end
        end
        pane.ges_events = { SwipeSnake = { GestureRange:new{ ges = "swipe", range = pane.dimen } } }
        pane.key_events = {}
        local groups = Device.input and Device.input.group or {}
        if groups.Left then pane.key_events.SnakeLeft = { { groups.Left }, event = "SnakeLeft" } end
        if groups.Right then pane.key_events.SnakeRight = { { groups.Right }, event = "SnakeRight" } end
        if groups.Up then pane.key_events.SnakeUp = { { groups.Up }, event = "SnakeUp" } end
        if groups.Down then pane.key_events.SnakeDown = { { groups.Down }, event = "SnakeDown" } end
        if groups.Press then pane.key_events.SnakeToggle = { { groups.Press }, event = "SnakeToggle" } end
        if groups.Select then pane.key_events.SnakeToggleSelect = { { groups.Select }, event = "SnakeToggle" } end
        local arena = SnakeCanvas:new{ width = width - 2 * margin, height = arena_h, session = state.session }
        state.session:setCanvas(arena)
        local action_w = math.floor((width - 2 * margin - gap) / 2)
        local direction_w = math.floor((width - 2 * margin - 3 * gap) / 4)
        local play_title = (state.session.over or state.session.won) and _("Play") or (state.session.paused and _("Play") or _("Pause"))
        local layers = {
            FrameContainer:new{ width = width, height = height, padding = 0, bordersize = 0, background = Blitbuffer.COLOR_WHITE, emptySizedWidget(width, height) },
            TextWidget:new{ text = "SNAKE", face = Font:getFace("cfont", px(19)), fgcolor = Blitbuffer.COLOR_BLACK, bold = true, max_width = width - 2 * margin, overlap_offset = { margin, px(6) } },
            TextWidget:new{ text = _("Score ") .. tostring(state.session.score), face = Font:getFace("smallinfofont", px(10)), fgcolor = Blitbuffer.COLOR_DARK_GRAY, bold = true, max_width = px(75), overlap_offset = { width - margin - px(75), px(13) } },
            arena,
            GameButton:new{ title = play_title, primary = true, width = action_w, height = action_h, callback = function()
                if state.session.over or state.session.won then state.session:reset(); context.requestRebuild("ui")
                elseif state.session.paused then state.session:start()
                else state.session:pause() end
            end, overlap_offset = { margin, action_y } },
            GameButton:new{ title = _("Restart"), width = action_w, height = action_h, callback = function() state.session:reset(); context.requestRebuild("ui") end, overlap_offset = { margin + action_w + gap, action_y } },
            GameButton:new{ title = _("LEFT"), width = direction_w, height = direction_h, callback = function() state.session:inputDirection("left") end, overlap_offset = { margin, direction_y } },
            GameButton:new{ title = _("UP"), width = direction_w, height = direction_h, callback = function() state.session:inputDirection("up") end, overlap_offset = { margin + direction_w + gap, direction_y } },
            GameButton:new{ title = _("DOWN"), width = direction_w, height = direction_h, callback = function() state.session:inputDirection("down") end, overlap_offset = { margin + 2 * (direction_w + gap), direction_y } },
            GameButton:new{ title = _("RIGHT"), width = direction_w, height = direction_h, callback = function() state.session:inputDirection("right") end, overlap_offset = { margin + 3 * (direction_w + gap), direction_y } },
            TextWidget:new{ text = state.status .. " " .. _("Swipe or use arrows to steer."), face = Font:getFace("smallinfofont", px(8)), fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = width - 2 * margin, overlap_offset = { margin, height - footer_h } },
        }
        arena.overlap_offset = { margin, arena_y }
        pane[1] = OverlapGroup:new{ dimen = pane.dimen, allow_mirroring = false, unpack(layers) }
        return pane
    end,
    onClose = function(instance)
        local state = instance and instance.snake
        if state and state.session then state.session:pause() end
    end,
    _test = { SnakeSession = SnakeSession, GRID_W = GRID_W, GRID_H = GRID_H, START_STEP_SECONDS = START_STEP_SECONDS, MIN_STEP_SECONDS = MIN_STEP_SECONDS },
}
