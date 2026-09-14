-- AppDock 2048 DApp
-- A compact, E-Ink friendly implementation with theme-derived tile colors.

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextWidget = require("ui/widget/textwidget")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local ok_theme, Theme = pcall(require, "appdock_theme")
local Screen = Device.screen

local function scale(value) return Screen:scaleBySize(value) end
local function paletteFor(context)
    local appdock = context and context.manager and context.manager.appdock
    if ok_theme and Theme.getPalette then
        local ok, palette = pcall(Theme.getPalette, appdock)
        if ok and palette then return palette end
    end
    return {
        background = Blitbuffer.COLOR_WHITE,
        surface = Blitbuffer.COLOR_LIGHT_GRAY,
        surface_variant = Blitbuffer.COLOR_GRAY_8,
        primary = Blitbuffer.COLOR_DARK_GRAY,
        on_primary = Blitbuffer.COLOR_WHITE,
        secondary = Blitbuffer.COLOR_GRAY_8,
        on_secondary = Blitbuffer.COLOR_BLACK,
        tertiary = Blitbuffer.COLOR_DARK_GRAY,
        on_tertiary = Blitbuffer.COLOR_WHITE,
        on_surface = Blitbuffer.COLOR_BLACK,
        on_variant = Blitbuffer.COLOR_DARK_GRAY,
        outline = Blitbuffer.COLOR_DARK_GRAY,
    }
end

local function stateFor(instance)
    if not instance.game_2048 then
        instance.game_2048 = { board = {}, score = 0, won = false, over = false }
        for i = 1, 16 do instance.game_2048.board[i] = 0 end
        -- The first two tiles are deterministic; later tiles are random.
        instance.game_2048.board[1] = 2
        instance.game_2048.board[6] = 2
        instance.game_2048.seed = os.time()
        math.randomseed(instance.game_2048.seed)
    end
    return instance.game_2048
end

local function emptyCells(board)
    local result = {}
    for i = 1, 16 do if board[i] == 0 then result[#result + 1] = i end end
    return result
end

local function addRandomTile(state)
    local cells = emptyCells(state.board)
    if #cells == 0 then return false end
    local index = cells[math.random(#cells)]
    state.board[index] = math.random(10) == 1 and 4 or 2
    return true
end

local function reset(state)
    state.board, state.score, state.won, state.over = {}, 0, false, false
    for i = 1, 16 do state.board[i] = 0 end
    addRandomTile(state)
    addRandomTile(state)
end

local function lineFor(board, direction, line)
    local result = {}
    for offset = 1, 4 do
        local row, col
        if direction == "left" then row, col = line, offset
        elseif direction == "right" then row, col = line, 5 - offset
        elseif direction == "up" then row, col = offset, line
        else row, col = 5 - offset, line end
        result[offset] = board[(row - 1) * 4 + col]
    end
    return result
end

local function writeLine(board, direction, line, values)
    for offset = 1, 4 do
        local row, col
        if direction == "left" then row, col = line, offset
        elseif direction == "right" then row, col = line, 5 - offset
        elseif direction == "up" then row, col = offset, line
        else row, col = 5 - offset, line end
        board[(row - 1) * 4 + col] = values[offset] or 0
    end
end

local function compress(values, state)
    local compact = {}
    for i = 1, 4 do if values[i] ~= 0 then compact[#compact + 1] = values[i] end end
    local merged, i = {}, 1
    while i <= #compact do
        if compact[i + 1] and compact[i] == compact[i + 1] then
            local value = compact[i] * 2
            merged[#merged + 1] = value
            state.score = state.score + value
            if value >= 2048 then state.won = true end
            i = i + 2
        else
            merged[#merged + 1] = compact[i]
            i = i + 1
        end
    end
    while #merged < 4 do merged[#merged + 1] = 0 end
    return merged
end

local function hasMoves(state)
    if #emptyCells(state.board) > 0 then return true end
    for row = 1, 4 do for col = 1, 4 do
        local value = state.board[(row - 1) * 4 + col]
        if col < 4 and value == state.board[(row - 1) * 4 + col + 1] then return true end
        if row < 4 and value == state.board[row * 4 + col] then return true end
    end end
    return false
end

local function move(state, direction)
    if state.over then return false end
    local before = {}
    for i = 1, 16 do before[i] = state.board[i] end
    for line = 1, 4 do writeLine(state.board, direction, line, compress(lineFor(before, direction, line), state)) end
    local changed = false
    for i = 1, 16 do if before[i] ~= state.board[i] then changed = true; break end end
    if changed then addRandomTile(state); state.over = not hasMoves(state) end
    return changed
end

local function tileColors(palette, value)
    if value == 0 then return palette.surface_variant, palette.on_variant end
    local colors = {
        [2] = { palette.surface, palette.on_surface },
        [4] = { palette.secondary, palette.on_secondary },
        [8] = { palette.primary, palette.on_primary },
        [16] = { palette.tertiary, palette.on_tertiary },
        [32] = { palette.primary, palette.on_primary },
        [64] = { palette.tertiary, palette.on_tertiary },
        [128] = { palette.secondary, palette.on_secondary },
        [256] = { palette.primary, palette.on_primary },
        [512] = { palette.tertiary, palette.on_tertiary },
        [1024] = { palette.primary, palette.on_primary },
        [2048] = { palette.tertiary, palette.on_tertiary },
    }
    return unpack(colors[value] or { palette.primary, palette.on_primary })
end

local DirectionButton = InputContainer:extend{ title = nil, callback = nil, width = 0, height = 0, background = nil, foreground = nil, px = nil }
function DirectionButton:init()
    local px = self.px or scale
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self[1] = FrameContainer:new{
        width = self.width, height = self.height, padding = 0, bordersize = 0,
        radius = px(8), background = self.background,
        OverlapGroup:new{ dimen = self.dimen, allow_mirroring = false,
            TextWidget:new{ text = self.title, face = Font:getFace("cfont", px(18)), fgcolor = self.foreground, bold = true,
                max_width = self.width - px(6), overlap_offset = { 0, math.max(0, math.floor((self.height - px(20)) / 2)) } },
        },
    }
    self.ges_events = { TapDirection = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end
function DirectionButton:paintTo(bb, x, y)
    local range = self.ges_events.TapDirection[1].range
    range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    return InputContainer.paintTo(self, bb, x, y)
end
function DirectionButton:onTapDirection()
    if self.callback then self.callback() end
    return true
end

local GamePane = InputContainer:extend{}
function GamePane:on2048Left() self.on_move("left"); return true end
function GamePane:on2048Right() self.on_move("right"); return true end
function GamePane:on2048Up() self.on_move("up"); return true end
function GamePane:on2048Down() self.on_move("down"); return true end
function GamePane:onSwipe2048(_, gesture)
    local direction = gesture and gesture.direction
    local moves = { west = "left", east = "right", north = "up", south = "down" }
    local move_direction = moves[direction]
    if move_direction and self.on_move then self.on_move(move_direction); return true end
    return false
end

local function buildBoard(state, palette, x, y, size, gap, px)
    local board = OverlapGroup:new{ dimen = Geom:new{ w = size, h = size }, allow_mirroring = false }
    local tile = math.floor((size - 3 * gap) / 4)
    for row = 1, 4 do for col = 1, 4 do
        local value = state.board[(row - 1) * 4 + col]
        local background, foreground = tileColors(palette, value)
        local text = value == 0 and "" or tostring(value)
        board[#board + 1] = FrameContainer:new{
            width = tile, height = tile, padding = 0, bordersize = 0, radius = px(6), background = background,
            CenterContainer:new{
                dimen = Geom:new{ w = tile, h = tile },
                TextWidget:new{ text = text, face = Font:getFace("cfont", value >= 1000 and px(14) or px(19)), fgcolor = foreground, bold = true, max_width = tile - px(4) },
            },
            overlap_offset = { (col - 1) * (tile + gap), (row - 1) * (tile + gap) },
        }
    end end
    board.overlap_offset = { x, y }
    return board
end

return {
    id = "game_2048",
    version = "1.0.4",
    title = "2048",
    subtitle = "Merge tiles and reach 2048",
    symbol = "2",
    logo = "other",
    buildPane = function(instance, context)
        local state = stateFor(instance)
        if not state.board[1] then reset(state) end
        local palette = paletteFor(context)
        local width, height = context.dimen.w, context.dimen.h
        local px = context.px or scale
        local margin, gap = px(12), px(7)
        local pane = GamePane:new{ dimen = Geom:new{ w = width, h = height } }
        pane.on_move = function(direction) if move(state, direction) then context.requestRebuild("ui") end end
        pane.ges_events = {
            Swipe2048 = { GestureRange:new{ ges = "swipe", range = pane.dimen } },
        }
        pane.key_events = {}
        local groups = Device.input and Device.input.group or {}
        if groups.Left then pane.key_events.MoveLeft = { { groups.Left }, event = "2048Left" } end
        if groups.Right then pane.key_events.MoveRight = { { groups.Right }, event = "2048Right" } end
        if groups.Up then pane.key_events.MoveUp = { { groups.Up }, event = "2048Up" } end
        if groups.Down then pane.key_events.MoveDown = { { groups.Down }, event = "2048Down" } end

        local header_h = px(48)
        local button_h = px(34)
        local board_size = math.min(width - 2 * margin, height - header_h - button_h - px(42))
        board_size = math.max(px(96), board_size)
        local board_x = math.floor((width - board_size) / 2)
        local board_y = header_h
        local layers = {
            FrameContainer:new{
                width = width, height = height, padding = 0, bordersize = 0, background = palette.background,
                WidgetContainer:new{ dimen = Geom:new{ w = width, h = height } },
            },
            TextWidget:new{ text = "2048", face = Font:getFace("cfont", px(22)), fgcolor = palette.on_surface, bold = true, overlap_offset = { margin, px(8) } },
            TextWidget:new{ text = (_("Score") .. ": " .. tostring(state.score)), face = Font:getFace("smallinfofont", px(11)), fgcolor = palette.on_variant, overlap_offset = { width - margin - px(105), px(15) }, max_width = px(105) },
            buildBoard(state, palette, board_x, board_y, board_size, gap, px),
        }
        local control_y = math.min(height - button_h - margin, board_y + board_size + px(8))
        local control_w = math.min(px(52), math.floor((width - 2 * margin - 3 * gap) / 4))
        local arrows = { { "←", "left" }, { "↑", "up" }, { "↓", "down" }, { "→", "right" } }
        for i, item in ipairs(arrows) do
            layers[#layers + 1] = DirectionButton:new{ title = item[1], width = control_w, height = button_h, px = px, background = palette.primary, foreground = palette.on_primary,
                callback = function() if move(state, item[2]) then context.requestRebuild("ui") end end,
                overlap_offset = { margin + (i - 1) * (control_w + gap), control_y } }
        end
        local status = state.over and _("Game over — press New game to restart") or (state.won and _("2048 reached — keep playing") or _("Swipe to move · arrows are a fallback"))
        if state.over then
            layers[#layers + 1] = DirectionButton:new{ title = _("New game"), width = math.min(px(100), width - 2 * margin), height = button_h, px = px, background = palette.secondary, foreground = palette.on_secondary,
                callback = function() reset(state); context.requestRebuild("ui") end, overlap_offset = { width - margin - math.min(px(100), width - 2 * margin), control_y } }
        end
        layers[#layers + 1] = TextWidget:new{ text = status, face = Font:getFace("smallinfofont", px(10)), fgcolor = palette.on_variant, max_width = width - 2 * margin, overlap_offset = { margin, height - px(16) } }
        pane[1] = OverlapGroup:new{ dimen = pane.dimen, allow_mirroring = false, unpack(layers) }
        return pane
    end,
}
