--[[--
Calendar for AppDock.
A local-first, E-Ink-friendly monthly calendar with persistent appointments.
No network access, synchronization, background jobs, or system-calendar access.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
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
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
if not ok_lfs then lfs = require("lfs") end

local STORE_DIR = DataStorage:getDataDir() .. "/appdock_calendar"
local STORE_FILE = STORE_DIR .. "/events.lua"
local MAX_EVENTS = 600
local MAX_TITLE_BYTES = 96
local MAX_NOTE_BYTES = 360
local WEEKDAYS = { _("Mon"), _("Tue"), _("Wed"), _("Thu"), _("Fri"), _("Sat"), _("Sun") }
local MONTHS = { _("January"), _("February"), _("March"), _("April"), _("May"), _("June"), _("July"), _("August"), _("September"), _("October"), _("November"), _("December") }

local function clamp(value, low, high) return math.max(low, math.min(high, value)) end
local function trim(value) return type(value) == "string" and value:gsub("^%s+", ""):gsub("%s+$", "") or "" end
local function empty(width, height) return CenterContainer:new{ dimen = Geom:new{ w = width, h = height }, HorizontalSpan:new{ width = 0 } } end
local function smallFace(width) return Font:getFace("smallinfofont", math.max(8, math.floor(width / 55))) end
local function normalFace(width) return Font:getFace("smallinfofont", math.max(10, math.floor(width / 40))) end
local function titleFace(width) return Font:getFace("cfont", math.max(17, math.floor(width / 26))) end

-- Date arithmetic --------------------------------------------------------------
local Date = {}

function Date.isLeap(year) return year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0) end
function Date.daysInMonth(year, month)
    local normal = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    if month == 2 and Date.isLeap(year) then return 29 end
    return normal[month]
end
function Date.valid(year, month, day)
    return type(year) == "number" and type(month) == "number" and type(day) == "number" and year >= 1 and month >= 1 and month <= 12 and day >= 1 and day <= Date.daysInMonth(year, month)
end
-- 0 = Sunday, 1 = Monday ... 6 = Saturday. Pure Gregorian arithmetic avoids
-- time-zone/DST changes when viewing distant months.
function Date.weekdaySunday(year, month, day)
    local offsets = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }
    if month < 3 then year = year - 1 end
    return (year + math.floor(year / 4) - math.floor(year / 100) + math.floor(year / 400) + offsets[month] + day) % 7
end
function Date.weekdayMonday(year, month, day) return (Date.weekdaySunday(year, month, day) + 6) % 7 end
function Date.key(year, month, day) return string.format("%04d-%02d-%02d", year, month, day) end
function Date.parse(key)
    if type(key) ~= "string" then return nil end
    local y, m, d = key:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if Date.valid(y, m, d) then return y, m, d end
end
function Date.shiftMonth(year, month, delta)
    month = month + delta
    while month < 1 do month, year = month + 12, year - 1 end
    while month > 12 do month, year = month - 12, year + 1 end
    return year, month
end
function Date.today()
    local now = os.date("*t")
    return now.year, now.month, now.day
end
function Date.long(key)
    local y, m, d = Date.parse(key)
    return y and (d .. " " .. MONTHS[m] .. " " .. y) or key
end

-- Local store -----------------------------------------------------------------
local Store = {}

local function serialize(value, indent)
    indent = indent or ""
    local kind = type(value)
    if kind == "number" then return tostring(value) end
    if kind == "boolean" then return value and "true" or "false" end
    if kind == "string" then return string.format("%q", value) end
    if kind ~= "table" then return "nil" end
    local out, deeper = { "{" }, indent .. "  "
    for index, item in ipairs(value) do out[#out + 1] = "\n" .. deeper .. serialize(item, deeper) .. "," end
    local keys = {}
    for key in pairs(value) do if type(key) ~= "number" or key < 1 or key > #value or key % 1 ~= 0 then keys[#keys + 1] = key end end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do
        local encoded = type(key) == "string" and (key:match("^[%a_][%w_]*$") and key or "[" .. string.format("%q", key) .. "]") or "[" .. tostring(key) .. "]"
        out[#out + 1] = "\n" .. deeper .. encoded .. " = " .. serialize(value[key], deeper) .. ","
    end
    if #out > 1 then out[#out + 1] = "\n" .. indent end
    out[#out + 1] = "}"
    return table.concat(out)
end

local function defaultStore() return { version = 1, events = {}, next_id = 1 } end

function Store.ensure()
    local attr = lfs.attributes(STORE_DIR)
    if attr and attr.mode == "directory" then return true end
    return lfs.mkdir(STORE_DIR)
end

local function validEvent(item)
    if type(item) ~= "table" or not Date.parse(item.date) then return nil end
    local title = trim(item.title):sub(1, MAX_TITLE_BYTES)
    if title == "" then return nil end
    return { id = math.max(1, math.floor(tonumber(item.id) or 1)), date = item.date, title = title, note = trim(item.note):sub(1, MAX_NOTE_BYTES) }
end

function Store.load()
    local data = defaultStore()
    local chunk = loadfile(STORE_FILE)
    if not chunk then return data end
    setfenv(chunk, {})
    local ok, loaded = pcall(chunk)
    if not ok or type(loaded) ~= "table" or loaded.version ~= 1 then return data end
    data.next_id = math.max(1, math.floor(tonumber(loaded.next_id) or 1))
    if type(loaded.events) == "table" then
        for _, event in ipairs(loaded.events) do
            local clean = validEvent(event)
            if clean and #data.events < MAX_EVENTS then data.events[#data.events + 1] = clean; data.next_id = math.max(data.next_id, clean.id + 1) end
        end
    end
    return data
end

function Store.save(data)
    if not Store.ensure() then return nil, _("Calendar could not create its storage folder.") end
    local temporary = STORE_FILE .. ".tmp"
    local file, err = io.open(temporary, "wb")
    if not file then return nil, err or _("Calendar could not save its events.") end
    local ok, write_err = file:write("return " .. serialize(data) .. "\n")
    file:close()
    if not ok then os.remove(temporary); return nil, write_err end
    local renamed, rename_err = os.rename(temporary, STORE_FILE)
    if not renamed then os.remove(temporary); return nil, rename_err end
    return true
end

-- App state -------------------------------------------------------------------
local function stateFor(instance)
    if instance.calendar then return instance.calendar end
    local year, month, day = Date.today()
    instance.calendar = { store = Store.load(), year = year, month = month, selected = Date.key(year, month, day), view = "month", notice = nil }
    return instance.calendar
end

local function eventsFor(state, key)
    local result = {}
    for _, event in ipairs(state.store.events) do if event.date == key then result[#result + 1] = event end end
    table.sort(result, function(a, b) return a.id < b.id end)
    return result
end

local function countFor(state, key)
    local count = 0
    for _, event in ipairs(state.store.events) do if event.date == key then count = count + 1 end end
    return count
end

local function save(state)
    local ok, err = Store.save(state.store)
    state.notice = ok and nil or (err or _("Calendar could not save its events."))
    return ok
end

local function selectDate(state, key)
    local year, month = Date.parse(key)
    if year then state.year, state.month, state.selected = year, month, key end
end

-- E-Ink widgets ---------------------------------------------------------------
local Action = InputContainer:extend{ title = nil, subtitle = nil, callback = nil, width = nil, height = nil, background = nil, foreground = nil, dimen = nil }
function Action:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local children = { TextWidget:new{ text = self.title or "", face = smallFace(self.width), fgcolor = self.foreground or Blitbuffer.COLOR_BLACK, bold = true, max_width = self.width - 8 } }
    if self.subtitle then children[#children + 1] = TextWidget:new{ text = self.subtitle, face = smallFace(self.width), fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = self.width - 8 } end
    self[1] = FrameContainer:new{ width = self.width, height = self.height, padding = 0, bordersize = 0, radius = math.max(4, math.floor(self.height * .23)), background = self.background or Blitbuffer.COLOR_LIGHT_GRAY, CenterContainer:new{ dimen = self.dimen, VerticalGroup:new{ unpack(children) } } }
    self.ges_events = { TapCalendarAction = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end
function Action:paintTo(bb, x, y) local range = self.ges_events.TapCalendarAction[1].range; range.x, range.y, range.w, range.h = x, y, self.width, self.height; return InputContainer.paintTo(self, bb, x, y) end
function Action:onTapCalendarAction() if self.callback then self.callback() end; return true end

local DayCell = InputContainer:extend{ day = nil, events = 0, selected = false, today = false, callback = nil, width = nil, height = nil, dimen = nil }
function DayCell:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local background = self.selected and Blitbuffer.COLOR_GRAY_8 or (self.today and Blitbuffer.COLOR_LIGHT_GRAY or Blitbuffer.COLOR_WHITE)
    local label = tostring(self.day)
    if self.events > 0 then label = label .. " •" end
    self[1] = FrameContainer:new{ width = self.width, height = self.height, padding = 0, bordersize = self.today and 1 or 0, radius = math.max(2, math.floor(self.height * .18)), background = background, CenterContainer:new{ dimen = self.dimen, TextWidget:new{ text = label, face = smallFace(self.width), fgcolor = Blitbuffer.COLOR_BLACK, bold = self.selected or self.today, max_width = self.width - 3 } } }
    self.ges_events = { TapCalendarDay = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end
function DayCell:paintTo(bb, x, y) local range = self.ges_events.TapCalendarDay[1].range; range.x, range.y, range.w, range.h = x, y, self.width, self.height; return InputContainer.paintTo(self, bb, x, y) end
function DayCell:onTapCalendarDay() if self.callback then self.callback() end; return true end

local function background(width, height) return FrameContainer:new{ width = width, height = height, padding = 0, bordersize = 0, background = Blitbuffer.COLOR_WHITE, empty(width, height) } end
local function refresh(context) context.requestRebuild("ui") end

local function addEvent(instance, context)
    local state, dialog = stateFor(instance), nil
    dialog = InputDialog:new{ title = _("Add event for ") .. Date.long(state.selected), input = "", input_hint = _("Event title"), buttons = { { { text = _("Cancel"), callback = function() UIManager:close(dialog) end }, { text = _("Add"), is_enter_default = true, callback = function()
        local title = trim(dialog:getInputText()):sub(1, MAX_TITLE_BYTES)
        if title == "" then UIManager:show(InfoMessage:new{ text = _("Please enter an event title.") }); return end
        if #state.store.events >= MAX_EVENTS then UIManager:show(InfoMessage:new{ text = _("Calendar has reached its local event limit.") }); return end
        state.store.events[#state.store.events + 1] = { id = state.store.next_id, date = state.selected, title = title, note = "" }
        state.store.next_id = state.store.next_id + 1
        UIManager:close(dialog); save(state); refresh(context)
    end } } } }
    UIManager:show(dialog); dialog:onShowKeyboard()
end

local function deleteEvent(state, context, event)
    UIManager:show(ConfirmBox:new{ text = _("Remove this event?\n\n") .. event.title, ok_text = _("Remove"), ok_callback = function()
        for index, item in ipairs(state.store.events) do if item.id == event.id then table.remove(state.store.events, index); break end end
        save(state); refresh(context)
    end })
end

local function monthAction(instance, context, action)
    local state = stateFor(instance)
    if action == "previous" then state.year, state.month = Date.shiftMonth(state.year, state.month, -1)
    elseif action == "next" then state.year, state.month = Date.shiftMonth(state.year, state.month, 1)
    elseif action == "today" then local y, m, d = Date.today(); state.year, state.month, state.selected = y, m, Date.key(y, m, d)
    elseif action == "details" then state.view = "day"
    elseif action == "add" then addEvent(instance, context); return
    end
    refresh(context)
end

local function monthPane(instance, context)
    local state, width, height = stateFor(instance), context.dimen.w, context.dimen.h
    local px = context.px or function(value) return value end
    local margin, gap = math.max(px(5), math.floor(width / 70)), math.max(px(3), math.floor(width / 150))
    local header_h, nav_h, weekday_h = math.max(px(24), math.floor(height / 17)), math.max(px(24), math.floor(height / 18)), math.max(px(16), math.floor(height / 28))
    local detail_h = math.max(px(52), math.floor(height / 6))
    local grid_y = margin + header_h + gap + nav_h + gap + weekday_h
    local cell_w = math.max(px(18), math.floor((width - 2 * margin - 6 * gap) / 7))
    local cell_h = math.max(px(22), math.floor((height - grid_y - detail_h - 3 * gap) / 6))
    local grid_h = 6 * cell_h + 5 * gap
    local today_y, today_m, today_d = Date.today()
    local elements = { background(width, height), TextWidget:new{ text = MONTHS[state.month] .. " " .. state.year, face = titleFace(width), bold = true, fgcolor = Blitbuffer.COLOR_BLACK, overlap_offset = { margin, margin } } }
    local nav_w = math.floor((width - 2 * margin - 2 * gap) / 3)
    elements[#elements + 1] = Action:new{ title = "‹", width = nav_w, height = nav_h, callback = function() monthAction(instance, context, "previous") end, overlap_offset = { margin, margin + header_h } }
    elements[#elements + 1] = Action:new{ title = _("Today"), width = nav_w, height = nav_h, background = Blitbuffer.COLOR_GRAY_8, callback = function() monthAction(instance, context, "today") end, overlap_offset = { margin + nav_w + gap, margin + header_h } }
    elements[#elements + 1] = Action:new{ title = "›", width = nav_w, height = nav_h, callback = function() monthAction(instance, context, "next") end, overlap_offset = { margin + 2 * (nav_w + gap), margin + header_h } }
    for index, name in ipairs(WEEKDAYS) do
        elements[#elements + 1] = TextWidget:new{ text = name, face = smallFace(cell_w), bold = true, fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = cell_w, overlap_offset = { margin + (index - 1) * (cell_w + gap), grid_y - weekday_h } }
    end
    local first = Date.weekdayMonday(state.year, state.month, 1)
    local days = Date.daysInMonth(state.year, state.month)
    for slot = 0, 41 do
        local day = slot - first + 1
        local row, column = math.floor(slot / 7), slot % 7
        local x, y = margin + column * (cell_w + gap), grid_y + row * (cell_h + gap)
        if day >= 1 and day <= days then
            local key = Date.key(state.year, state.month, day)
            elements[#elements + 1] = DayCell:new{ day = day, events = countFor(state, key), selected = key == state.selected, today = state.year == today_y and state.month == today_m and day == today_d, width = cell_w, height = cell_h, callback = function() selectDate(state, key); refresh(context) end, overlap_offset = { x, y } }
        else elements[#elements + 1] = empty(cell_w, cell_h); elements[#elements].overlap_offset = { x, y } end
    end
    local detail_y = grid_y + grid_h + gap
    local selected_events = eventsFor(state, state.selected)
    local subtitle = #selected_events == 0 and _("No events") or (#selected_events == 1 and selected_events[1].title or (#selected_events .. " " .. _("events")))
    local detail_w = math.floor((width - 2 * margin - gap) * .66)
    elements[#elements + 1] = Action:new{ title = Date.long(state.selected), subtitle = subtitle, width = detail_w, height = detail_h, callback = function() monthAction(instance, context, "details") end, overlap_offset = { margin, detail_y } }
    elements[#elements + 1] = Action:new{ title = _("+ Event"), width = width - 2 * margin - detail_w - gap, height = detail_h, background = Blitbuffer.COLOR_GRAY_8, callback = function() monthAction(instance, context, "add") end, overlap_offset = { margin + detail_w + gap, detail_y } }
    if state.notice then elements[#elements + 1] = TextWidget:new{ text = state.notice, face = smallFace(width), fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = width - 2 * margin, overlap_offset = { margin, math.max(margin, detail_y - weekday_h) } } end
    return OverlapGroup:new{ dimen = Geom:new{ w = width, h = height }, allow_mirroring = false, unpack(elements) }
end

local function dayPane(instance, context)
    local state, width, height = stateFor(instance), context.dimen.w, context.dimen.h
    local px = context.px or function(value) return value end
    local margin, gap, head_h, action_h = math.max(px(7), math.floor(width / 65)), math.max(px(4), math.floor(width / 140)), math.max(px(30), math.floor(height / 14)), math.max(px(30), math.floor(height / 15))
    local elements = { background(width, height), TextWidget:new{ text = Date.long(state.selected), face = titleFace(width), bold = true, fgcolor = Blitbuffer.COLOR_BLACK, overlap_offset = { margin, margin } } }
    local half = math.floor((width - 2 * margin - gap) / 2)
    elements[#elements + 1] = Action:new{ title = _("‹ Month"), width = half, height = action_h, callback = function() state.view = "month"; refresh(context) end, overlap_offset = { margin, margin + head_h } }
    elements[#elements + 1] = Action:new{ title = _("+ Event"), width = half, height = action_h, background = Blitbuffer.COLOR_GRAY_8, callback = function() addEvent(instance, context) end, overlap_offset = { margin + half + gap, margin + head_h } }
    local y = margin + head_h + action_h + 2 * gap
    local events = eventsFor(state, state.selected)
    if #events == 0 then elements[#elements + 1] = TextWidget:new{ text = _("No events planned for this day."), face = normalFace(width), fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = width - 2 * margin, overlap_offset = { margin, y + gap } } end
    for index, event in ipairs(events) do
        if y + action_h > height - margin then break end
        elements[#elements + 1] = Action:new{ title = event.title, subtitle = _("Tap to remove"), width = width - 2 * margin, height = action_h, callback = function() deleteEvent(state, context, event) end, overlap_offset = { margin, y } }
        y = y + action_h + gap
    end
    return OverlapGroup:new{ dimen = Geom:new{ w = width, h = height }, allow_mirroring = false, unpack(elements) }
end

local function persistentPane(pane, state)
    function pane:onDeactivate() save(state) end
    return pane
end

return {
    id = "calendar",
    version = "1.0.2",
    title = "Calendar",
    subtitle = "Local monthly planner",
    symbol = "C",
    logo = "calendar",
    buildPane = function(instance, context)
        local state = stateFor(instance)
        if state.view == "day" then return persistentPane(dayPane(instance, context), state) end
        return persistentPane(monthPane(instance, context), state)
    end,
}
