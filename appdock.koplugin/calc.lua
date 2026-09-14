--[[--
Calc for AppDock.

A scientific calculator and one-variable function plotter. Expressions are
parsed by a small allow-listed recursive-descent evaluator; Calc never invokes
loadstring or arbitrary Lua supplied by the user.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local Widget = require("ui/widget/widget")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Screen = Device.screen
local MAX_TOKENS = 256
local CONSTANTS = { pi = math.pi, e = math.exp(1) }
local FUNCTIONS = {
    sin = math.sin, cos = math.cos, tan = math.tan,
    asin = math.asin, acos = math.acos, atan = math.atan,
    sqrt = math.sqrt, abs = math.abs, exp = math.exp,
    ln = math.log, log = math.log10 or function(value) return math.log(value) / math.log(10) end,
    floor = math.floor, ceil = math.ceil,
}

local function scale(value) return Screen:scaleBySize(value) end
local function clamp(value, low, high) return math.max(low, math.min(high, value)) end
local function isFinite(value) return type(value) == "number" and value == value and math.abs(value) < 1e300 end
local function emptySizedWidget(width, height) return CenterContainer:new{ dimen = Geom:new{ w = width, h = height }, HorizontalSpan:new{ width = 0 } } end

local function normalize(source)
    source = tostring(source or "")
    source = source:gsub("×", "*"):gsub("÷", "/"):gsub("−", "-"):gsub("π", "pi")
    return source:gsub("%s+", "")
end

local function tokenize(source)
    source = normalize(source)
    if #source == 0 then return nil, _("Enter an expression.") end
    local tokens, position = {}, 1
    while position <= #source do
        if #tokens >= MAX_TOKENS then return nil, _("Expression is too long.") end
        local rest = source:sub(position)
        local number = rest:match("^%d*%.?%d+[eE][%+%-]?%d+") or rest:match("^%d*%.?%d+")
        if number then
            local value = tonumber(number)
            if not isFinite(value) then return nil, _("Invalid number.") end
            tokens[#tokens + 1] = { kind = "number", value = value }
            position = position + #number
        else
            local identifier = rest:match("^[%a_][%w_]*")
            if identifier then
                tokens[#tokens + 1] = { kind = "id", value = identifier:lower() }
                position = position + #identifier
            else
                local symbol = rest:sub(1, 1)
                if symbol == "+" or symbol == "-" or symbol == "*" or symbol == "/" or symbol == "^" or symbol == "(" or symbol == ")" or symbol == "," then
                    tokens[#tokens + 1] = { kind = symbol, value = symbol }
                    position = position + 1
                else
                    return nil, _("Unsupported character: ") .. symbol
                end
            end
        end
    end
    tokens[#tokens + 1] = { kind = "end" }
    return tokens
end

local function evaluate(source, variables)
    local tokens, tokenize_err = tokenize(source)
    if not tokens then return nil, tokenize_err end
    variables = variables or {}
    local index = 1
    local function current() return tokens[index] end
    local function take(kind)
        if current().kind ~= kind then return nil end
        local token = current(); index = index + 1; return token
    end
    local parseExpression, parseTerm, parsePower, parseUnary, parsePrimary
    parsePrimary = function()
        local token = current()
        if take("number") then return token.value end
        if token.kind == "id" then
            index = index + 1
            if take("(") then
                local argument, err = parseExpression()
                if not argument then return nil, err end
                if not take(")") then return nil, _("Missing closing parenthesis.") end
                local fn = FUNCTIONS[token.value]
                if not fn then return nil, _("Unsupported function: ") .. token.value end
                local ok, result = pcall(fn, argument)
                if not ok or not isFinite(result) then return nil, _("Function is undefined for this value.") end
                return result
            end
            if token.value == "x" then
                local value = tonumber(variables.x)
                if not isFinite(value) then return nil, _("x has no numeric value.") end
                return value
            end
            if CONSTANTS[token.value] then return CONSTANTS[token.value] end
            return nil, _("Unknown name: ") .. token.value
        end
        if take("(") then
            local value, err = parseExpression()
            if not value then return nil, err end
            if not take(")") then return nil, _("Missing closing parenthesis.") end
            return value
        end
        return nil, _("Expected a number, name or parenthesis.")
    end
    parseUnary = function()
        if take("+") then return parseUnary() end
        if take("-") then
            local value, err = parseUnary()
            return value and -value or nil, err
        end
        return parsePrimary()
    end
    parsePower = function()
        local left, err = parseUnary()
        if not left then return nil, err end
        if take("^") then
            local right, right_err = parsePower()
            if not right then return nil, right_err end
            local result = left ^ right
            if not isFinite(result) then return nil, _("Power result is outside Calc's safe range.") end
            return result
        end
        return left
    end
    parseTerm = function()
        local value, err = parsePower()
        if not value then return nil, err end
        while current().kind == "*" or current().kind == "/" do
            local operator = current().kind; index = index + 1
            local right, right_err = parsePower()
            if not right then return nil, right_err end
            if operator == "*" then value = value * right else
                if right == 0 then return nil, _("Division by zero.") end
                value = value / right
            end
            if not isFinite(value) then return nil, _("Result is outside Calc's safe range.") end
        end
        return value
    end
    parseExpression = function()
        local value, err = parseTerm()
        if not value then return nil, err end
        while current().kind == "+" or current().kind == "-" do
            local operator = current().kind; index = index + 1
            local right, right_err = parseTerm()
            if not right then return nil, right_err end
            value = operator == "+" and value + right or value - right
            if not isFinite(value) then return nil, _("Result is outside Calc's safe range.") end
        end
        return value
    end
    local value, err = parseExpression()
    if not value then return nil, err end
    if current().kind ~= "end" then return nil, _("Unexpected token in expression.") end
    return value
end

local function formatNumber(value)
    if not isFinite(value) then return _("undefined") end
    if value == math.floor(value) and math.abs(value) < 1e12 then return tostring(math.floor(value)) end
    return string.format("%.10g", value)
end

local function drawLine(bb, x0, y0, x1, y1, thickness, ink)
    local dx, dy = x1 - x0, y1 - y0
    local steps = math.max(math.abs(dx), math.abs(dy))
    if steps < 1 then bb:paintRect(math.floor(x0), math.floor(y0), thickness, thickness, ink); return end
    for step = 0, steps do bb:paintRect(math.floor(x0 + dx * step / steps), math.floor(y0 + dy * step / steps), thickness, thickness, ink) end
end

local PlotCanvas = Widget:extend{ expression = nil, x_min = -10, x_max = 10, width = nil, height = nil, grid_size = nil }
function PlotCanvas:getSize() return Geom:new{ w = self.width, h = self.height } end
function PlotCanvas:paintTo(bb, x, y)
    bb:paintRect(x, y, self.width, self.height, Blitbuffer.COLOR_WHITE)
    local grid = Blitbuffer.COLOR_LIGHT_GRAY
    local grid_size = self.grid_size or scale(30)
    for grid_x = x + grid_size, x + self.width, grid_size do bb:paintRect(grid_x, y, 1, self.height, grid) end
    for grid_y = y + grid_size, y + self.height, grid_size do bb:paintRect(x, grid_y, self.width, 1, grid) end
    local x_span = self.x_max - self.x_min
    if x_span <= 0 then return end
    local y_min, y_max = -10, 10
    local zero_x = x + clamp((-self.x_min / x_span) * self.width, 0, self.width)
    local zero_y = y + clamp((y_max / (y_max - y_min)) * self.height, 0, self.height)
    bb:paintRect(math.floor(zero_x), y, 1, self.height, Blitbuffer.COLOR_GRAY)
    bb:paintRect(x, math.floor(zero_y), self.width, 1, Blitbuffer.COLOR_GRAY)
    local last_x, last_y = nil, nil
    for pixel = 0, self.width - 1 do
        local variable_x = self.x_min + pixel / math.max(1, self.width - 1) * x_span
        local value = evaluate(self.expression, { x = variable_x })
        if isFinite(value) and value >= y_min * 8 and value <= y_max * 8 then
            local graph_y = y + (y_max - value) / (y_max - y_min) * self.height
            if last_x and math.abs(graph_y - last_y) < self.height * 0.8 then drawLine(bb, last_x, last_y, x + pixel, graph_y, 1, Blitbuffer.COLOR_BLACK) end
            last_x, last_y = x + pixel, graph_y
        else
            last_x, last_y = nil, nil
        end
    end
end

local CalcButton = InputContainer:extend{ title = nil, callback = nil, width = nil, height = nil, dimen = nil, highlight = false, px = nil }
function CalcButton:init()
    local px = self.px or scale
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self[1] = FrameContainer:new{ width = self.width, height = self.height, padding = 0, bordersize = 0, radius = math.floor(self.height * .28), background = self.highlight and Blitbuffer.COLOR_GRAY_8 or Blitbuffer.COLOR_LIGHT_GRAY,
        CenterContainer:new{ dimen = self.dimen, TextWidget:new{ text = self.title or "", face = Font:getFace("smallinfofont", px(10)), bold = true, max_width = self.width - px(5) } } }
    self.ges_events = { TapCalcButton = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end
function CalcButton:paintTo(bb, x, y)
    local range = self.ges_events.TapCalcButton[1].range; range.x, range.y, range.w, range.h = x, y, self.dimen.w, self.dimen.h
    return InputContainer.paintTo(self, bb, x, y)
end
function CalcButton:onTapCalcButton() if self.callback then self.callback() end return true end

local function stateFor(instance)
    instance.calc = instance.calc or { expression = "sin(pi/4)^2+cos(pi/4)^2", result = "", history = {}, x_min = -10, x_max = 10, status = _("Use x for plots, e.g. sin(x).") }
    return instance.calc
end

local function addHistory(state, expression, result)
    if #state.history > 0 and state.history[1].expression == expression then return end
    table.insert(state.history, 1, { expression = expression, result = result })
    while #state.history > 12 do table.remove(state.history) end
end

local function calculate(state)
    local value, err = evaluate(state.expression)
    if value then
        state.result = formatNumber(value)
        state.status = _("Calculated")
        addHistory(state, state.expression, state.result)
    else
        state.result = _("Error")
        state.status = tostring(err)
    end
end

local function editExpression(instance, context)
    local state = stateFor(instance)
    local dialog
    dialog = InputDialog:new{ title = _("Expression"), input = state.expression, input_hint = _("Example: sin(pi/4)^2"),
        buttons = { { { text = _("Cancel"), callback = function() UIManager:close(dialog) end }, { text = _("Use"), is_enter_default = true, callback = function()
            state.expression = dialog:getInputText() or ""; UIManager:close(dialog); calculate(state); context.requestRebuild("ui")
        end } } } }
    UIManager:show(dialog); dialog:onShowKeyboard()
end

local function editRange(instance, context)
    local state = stateFor(instance)
    local dialog
    dialog = InputDialog:new{ title = _("Plot range"), input = string.format("%.5g, %.5g", state.x_min, state.x_max), input_hint = _("x minimum, x maximum; e.g. -10, 10"),
        buttons = { { { text = _("Cancel"), callback = function() UIManager:close(dialog) end }, { text = _("Use range"), is_enter_default = true, callback = function()
            local first, second = (dialog:getInputText() or ""):match("^%s*([%+%-]?[%d%.]+)%s*,%s*([%+%-]?[%d%.]+)%s*$")
            UIManager:close(dialog)
            first, second = tonumber(first), tonumber(second)
            if first and second and isFinite(first) and isFinite(second) and second > first then state.x_min, state.x_max, state.status = first, second, _("Plot range updated") else state.status = _("Use two finite numbers with maximum greater than minimum.") end
            context.requestRebuild("ui")
        end } } } }
    UIManager:show(dialog); dialog:onShowKeyboard()
end

local function historyDialog(instance, context)
    local state = stateFor(instance)
    if #state.history == 0 then UIManager:show(InfoMessage:new{ text = _("No calculations yet.") }); return end
    local dialog, buttons = nil, {}
    for _, item in ipairs(state.history) do
        buttons[#buttons + 1] = { { text = item.expression .. " = " .. item.result, callback = function() state.expression = item.expression; UIManager:close(dialog); context.requestRebuild("ui") end } }
    end
    dialog = ButtonDialog:new{ title = _("Calculation history"), buttons = buttons }
    UIManager:show(dialog)
end

return {
    id = "calc",
    version = "1.0.1",
    title = "Calc",
    subtitle = "Scientific calculator and function plotter",
    symbol = "∑",
    logo = "calculator",
    buildPane = function(instance, context)
        local state = stateFor(instance)
        local width, height = context.dimen.w, context.dimen.h
        local px = context.px or scale
        local margin, gap = px(10), px(5)
        local row_y, button_h = px(78), px(28)
        local button_w = math.max(px(32), math.floor((width - 2 * margin - 4 * gap) / 5))
        local key_y = row_y + button_h + px(5)
        local plot_y = key_y + button_h + px(8)
        local plot_h = math.max(px(55), height - plot_y - px(20))
        local plot = PlotCanvas:new{ expression = state.expression, x_min = state.x_min, x_max = state.x_max, width = width - 2 * margin, height = plot_h, grid_size = px(30) }
        local layers = {
            FrameContainer:new{ width = width, height = height, padding = 0, bordersize = 0, background = Blitbuffer.COLOR_WHITE, emptySizedWidget(width, height) },
            TextWidget:new{ text = _("Calc"), face = Font:getFace("cfont", px(19)), bold = true, overlap_offset = { margin, px(7) } },
            TextWidget:new{ text = state.expression, face = Font:getFace("infont", px(13)), max_width = width - 2 * margin, overlap_offset = { margin, px(32) } },
            TextWidget:new{ text = "= " .. (state.result or ""), face = Font:getFace("cfont", px(18)), bold = true, max_width = width - 2 * margin, overlap_offset = { margin, px(53) } },
            CalcButton:new{ title = _("Expr"), width = button_w, height = button_h, px = px, callback = function() editExpression(instance, context) end, overlap_offset = { margin, row_y } },
            CalcButton:new{ title = _("="), width = button_w, height = button_h, px = px, highlight = true, callback = function() calculate(state); context.requestRebuild("ui") end, overlap_offset = { margin + (button_w + gap), row_y } },
            CalcButton:new{ title = _("History"), width = button_w, height = button_h, px = px, callback = function() historyDialog(instance, context) end, overlap_offset = { margin + (button_w + gap) * 2, row_y } },
            CalcButton:new{ title = _("Range"), width = button_w, height = button_h, px = px, callback = function() editRange(instance, context) end, overlap_offset = { margin + (button_w + gap) * 3, row_y } },
            CalcButton:new{ title = _("Plot"), width = button_w, height = button_h, px = px, highlight = true, callback = function() state.status = _("Plot refreshed"); context.requestRebuild("ui") end, overlap_offset = { margin + (button_w + gap) * 4, row_y } },
        }
        local keys = { "sin(", "cos(", "sqrt(", "pi", "x" }
        for index, token in ipairs(keys) do layers[#layers + 1] = CalcButton:new{ title = token, width = button_w, height = button_h, px = px, callback = function() state.expression = (state.expression or "") .. token; context.requestRebuild("ui") end, overlap_offset = { margin + (index - 1) * (button_w + gap), key_y } } end
        plot.overlap_offset = { margin, plot_y }
        layers[#layers + 1] = plot
        layers[#layers + 1] = TextWidget:new{ text = state.status or "", face = Font:getFace("smallinfofont", px(9)), max_width = width - 2 * margin, overlap_offset = { margin, height - px(14) } }
        local pane = WidgetContainer:new{ dimen = Geom:new{ w = width, h = height } }
        pane[1] = OverlapGroup:new{ dimen = pane.dimen, allow_mirroring = false, unpack(layers) }
        return pane
    end,
    test = { evaluate = evaluate, tokenize = tokenize, normalize = normalize, formatNumber = formatNumber, newState = function() return { expression = "", history = {}, x_min = -10, x_max = 10 } end },
}
