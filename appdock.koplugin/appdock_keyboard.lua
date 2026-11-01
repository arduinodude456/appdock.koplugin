-- AppDock-owned keyboard for AppDock-owned text input surfaces.
-- KOReader dialogs outside AppDock remain untouched.
--
-- GBoard-style layout, tuned for E-Ink:
--   * big keys (row height scales with the screen, ~8% of its height)
--   * QWERTZ / QWERTY, long-press for digits and umlauts/accents
--   * suggestion strip, auto-capitalisation, double-space -> ". "
--   * swipe typing: wipe over the letters, a comet-tail trail follows the
--     finger and the matching word is inserted (options.swipe = false disables)
--   * emoji panel (categories + recents), clipboard history panel
--   * partial "fast" refreshes only (top bar / changed keys), no per-key flashing
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
-- The dictionary is optional at boot. It is required lazily only when a
-- keyboard is actually created, so a missing/broken database cannot prevent
-- AppDock from opening.
local SuggestionDatabase
local configured_language = "auto"
local keyboard_enabled = true
local ui_is_de = false

-- All keyboard texts avoid KOReader's xtext shaper (use_xtext = false): its
-- shapeLine() raised "index out of range" while painting. The classic
-- RenderText path is plenty for keys and the input line.
local function newText(args)
    args.use_xtext = false
    return TextWidget:new(args)
end

local Screen = Device.screen
local function scale(n) return Screen:scaleBySize(n) end
local function ui(de, en) return ui_is_de and de or en end

-- Fixed black/white colour scheme (no theme support).
local theme = {
    background   = Blitbuffer.COLOR_WHITE,
    key          = Blitbuffer.COLOR_WHITE,
    key_text     = Blitbuffer.COLOR_BLACK,
    func         = Blitbuffer.COLOR_LIGHT_GRAY,
    func_text    = Blitbuffer.COLOR_BLACK,
    active       = Blitbuffer.COLOR_BLACK,
    active_text  = Blitbuffer.COLOR_WHITE,
    primary      = Blitbuffer.COLOR_BLACK,
    primary_text = Blitbuffer.COLOR_WHITE,
    hint         = Blitbuffer.COLOR_DARK_GRAY,
    border       = Blitbuffer.COLOR_BLACK,
}

local function normalizeLanguage(language)
    if language == "de" or language == "en" then return language end
    return "auto"
end

local function resolvedLanguage(language)
    language = normalizeLanguage(language or configured_language)
    if language ~= "auto" then return language end
    local reader_language
    if _G.G_reader_settings and type(G_reader_settings.readSetting) == "function" then
        local ok, value = pcall(G_reader_settings.readSetting, G_reader_settings, "language")
        if ok then reader_language = value end
    end
    return reader_language == "de" and "de" or "en"
end

----------------------------------------------------------------------
-- Text helpers (UTF-8 aware)
----------------------------------------------------------------------
local LOWER_TO_UPPER, UPPER_TO_LOWER = {}, {}
for code = string.byte("a"), string.byte("z") do
    local lower, upper = string.char(code), string.char(code - 32)
    LOWER_TO_UPPER[lower], UPPER_TO_LOWER[upper] = upper, lower
end
for lower, upper in pairs({
    ["ä"] = "Ä", ["ö"] = "Ö", ["ü"] = "Ü", ["ß"] = "ẞ",
    ["á"] = "Á", ["à"] = "À", ["é"] = "É", ["è"] = "È", ["ê"] = "Ê",
    ["í"] = "Í", ["ó"] = "Ó", ["ò"] = "Ò", ["ú"] = "Ú", ["ù"] = "Ù",
    ["š"] = "Š", ["ç"] = "Ç", ["ñ"] = "Ñ",
}) do
    LOWER_TO_UPPER[lower], UPPER_TO_LOWER[upper] = upper, lower
end

local function casePair(label)
    if LOWER_TO_UPPER[label] then return label, LOWER_TO_UPPER[label] end
    if UPPER_TO_LOWER[label] then return UPPER_TO_LOWER[label], label end
end

local function firstChar(s)
    return s:match("^[%z\1-\127\194-\244][\128-\191]*") or ""
end

local function capitalizeFirst(word)
    local c = firstChar(word)
    local up = LOWER_TO_UPPER[c]
    if up then return up .. word:sub(#c + 1) end
    return word
end

local function lowerUtf8(s)
    s = s:lower()
    s = s:gsub("\195([\132\150\156])", function(c) return "\195" .. string.char(c:byte() + 32) end)
    return s
end

local function charCount(s)
    local _, n = s:gsub("[^\128-\191]", "")
    return n
end

local function utf8Tail(s, n)
    local i, count = #s, 0
    while i >= 1 do
        local b = s:byte(i)
        if b < 0x80 or b >= 0xC0 then
            count = count + 1
            if count == n then break end
        end
        i = i - 1
    end
    return s:sub(math.max(i, 1))
end

local function utf8Head(s, n)
    local count, i, len = 0, 1, #s
    while i <= len do
        local b = s:byte(i)
        if b < 0x80 or b >= 0xC0 then
            count = count + 1
            if count > n then return s:sub(1, i - 1) end
        end
        i = i + 1
    end
    return s
end

local function removeLastUTF8Character(value)
    local index = #value
    if index == 0 then return value end
    while index > 1 do
        local byte = value:byte(index)
        if byte < 0x80 or byte >= 0xC0 then break end
        index = index - 1
    end
    return value:sub(1, index - 1)
end

local function removeLastWord(value)
    value = value:gsub("%s+$", "")
    local i = #value
    while i >= 1 do
        local b = value:byte(i)
        if b == 32 or b == 9 or b == 10 then break end
        i = i - 1
    end
    return value:sub(1, i)
end

-- The word being typed: ASCII alphanumerics plus Latin-1/Latin-Extended-A
-- letters (ä ö ü ß é ñ ...). Emoji and symbols end the word.
local function trailingWord(value)
    local i = #value
    local start = i + 1
    while i >= 1 do
        local b = value:byte(i)
        if (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122) then
            start = i
            i = i - 1
        elseif b >= 0x80 and b < 0xC0 and i > 1 then
            local lead = value:byte(i - 1)
            if lead == 0xC3 or lead == 0xC4 or lead == 0xC5 then
                start = i - 1
                i = i - 2
            else
                break
            end
        else
            break
        end
    end
    return value:sub(start)
end

local function trim(text)
    text = tostring(text or "")
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
    return text
end

local function splitWords(s)
    local t = {}
    for w in s:gmatch("%S+") do t[#t + 1] = w end
    return t
end

local function now()
    local ok, socket = pcall(require, "socket")
    if ok and socket and socket.gettime then return socket.gettime() end
    return os.time()
end

----------------------------------------------------------------------
-- Suggestions are loaded from the bilingual offline database. A caller can
-- still pass a small context-specific list through `suggestions`.
----------------------------------------------------------------------
local FALLBACK_SUGGESTIONS = { "AppDock", "Einstellungen", "Settings", "Search", "Browser", "Dateien" }
local function loadSiblingDatabase()
    local source = debug.getinfo(1, "S").source or ""
    local directory = source:match("^@(.*/)")
    if directory then
        local ok, loaded = pcall(dofile, directory .. "appdock_suggestions.lua")
        if ok and type(loaded) == "table" then return loaded end
    end
    if package.searchpath then
        local module_path = package.searchpath("appdock_suggestions", package.path or "")
        if module_path then
            local ok, loaded = pcall(dofile, module_path)
            if ok and type(loaded) == "table" then return loaded end
        end
    end
    return nil
end
local function loadSuggestions(language)
    if not SuggestionDatabase then
        local ok, loaded = pcall(require, "appdock_suggestions")
        if ok and type(loaded) == "table" then SuggestionDatabase = loaded end
    end
    if SuggestionDatabase and type(SuggestionDatabase.get) == "function" then
        local ok, result = pcall(SuggestionDatabase.get, language)
        if ok and type(result) == "table" and #result > 0 then return result end
    end
    -- KOReader can load a module from its plugin directory without adding
    -- that directory to package.path. Re-load the sibling module by absolute
    -- path so its own debug source points at the shipped .db file.
    local sibling = loadSiblingDatabase()
    if sibling and type(sibling.get) == "function" then
        local ok, result = pcall(sibling.get, language)
        if ok and type(result) == "table" and #result > 0 then
            SuggestionDatabase = sibling
            return result
        end
    end
    return FALLBACK_SUGGESTIONS
end

----------------------------------------------------------------------
-- Clipboard history and recent emojis (persisted, flushed on close)
----------------------------------------------------------------------
local MAX_CLIPS, MAX_RECENT_EMOJIS, MAX_CLIP_BYTES = 10, 24, 1000
local clip_history, recent_emojis
local store_dirty = false
local settings_store

local function getStore()
    if settings_store ~= nil then return settings_store or nil end
    local ok, result = pcall(function()
        local DataStorage = require("datastorage")
        local LuaSettings = require("luasettings")
        return LuaSettings:open(DataStorage:getSettingsDir() .. "/appdock_keyboard.lua")
    end)
    settings_store = ok and result or false
    return ok and result or nil
end

local function loadPersisted()
    if clip_history then return end
    clip_history, recent_emojis = {}, {}
    local store = getStore()
    if not store then return end
    local clips = store:readSetting("clipboard")
    if type(clips) == "table" then
        for _i, v in ipairs(clips) do
            if type(v) == "string" and v ~= "" and #clip_history < MAX_CLIPS then clip_history[#clip_history + 1] = v end
        end
    end
    local recents = store:readSetting("recent_emojis")
    if type(recents) == "table" then
        for _i, v in ipairs(recents) do
            if type(v) == "string" and v ~= "" and #recent_emojis < MAX_RECENT_EMOJIS then recent_emojis[#recent_emojis + 1] = v end
        end
    end
end

local function flushPersisted()
    if not store_dirty then return end
    store_dirty = false
    local store = getStore()
    if store then
        pcall(function()
            store:saveSetting("clipboard", clip_history or {})
            store:saveSetting("recent_emojis", recent_emojis or {})
            store:flush()
        end)
    end
end

local function addClip(text)
    loadPersisted()
    text = trim(text)
    if text == "" then return end
    if #text > MAX_CLIP_BYTES then
        text = text:sub(1, MAX_CLIP_BYTES)
        local b = text:byte(#text)
        while b and b >= 0x80 and b < 0xC0 do
            text = text:sub(1, -2)
            b = text:byte(#text)
        end
        if b and b >= 0xC0 then text = text:sub(1, -2) end
    end
    for i = #clip_history, 1, -1 do
        if clip_history[i] == text then table.remove(clip_history, i) end
    end
    table.insert(clip_history, 1, text)
    while #clip_history > MAX_CLIPS do table.remove(clip_history) end
    store_dirty = true
end

local function recordEmoji(emoji)
    loadPersisted()
    for i = #recent_emojis, 1, -1 do
        if recent_emojis[i] == emoji then table.remove(recent_emojis, i) end
    end
    table.insert(recent_emojis, 1, emoji)
    while #recent_emojis > MAX_RECENT_EMOJIS do table.remove(recent_emojis) end
    store_dirty = true
end

local function getSystemClipboard()
    local ok, text = pcall(function()
        if Device.input and type(Device.input.getClipboardText) == "function" then
            return Device.input.getClipboardText()
        end
    end)
    if ok and type(text) == "string" then return text end
    return ""
end

local function setSystemClipboard(text)
    pcall(function()
        if Device.input and type(Device.input.setClipboardText) == "function" then
            Device.input.setClipboardText(text)
        end
    end)
end

----------------------------------------------------------------------
-- Static data
----------------------------------------------------------------------
-- Single code points only (no ZWJ sequences), so they also render with
-- KOReader's monochrome emoji fallback font.
local EMOJI_CATEGORIES = {
    { icon = "🙂", words = splitWords("😀 😃 😄 😁 😆 😅 😂 🤣 🙂 😉 😊 😇 😍 😘 😋 😜 🤔 😐 😑 😶 🙄 😏 😴 😌 😎 🤓 😢 😭 😤 😡 😱 😳 🥳 🥺 😬 😷 🤒 🤗") },
    { icon = "👍", words = splitWords("👍 👎 👌 ✌ 🤞 🤟 🤘 👈 👉 👆 👇 ✋ 🖐 👋 🤝 🙏 👏 🙌 💪 🤙 ✍ 👀 👂 👃 🧠 💋 🙋 🤷 🤦 🙈 🙉 🙊") },
    { icon = "❤", words = splitWords("❤ 🧡 💛 💚 💙 💜 🖤 🤍 💔 💕 💖 💯 ✔ ✖ ❌ ⭕ ⚠ ❓ ❗ ➕ ➖ ➡ ⬅ ⬆ ⬇ 🔥 ✨ ⭐ 🎉 🎊 💡 ✅") },
    { icon = "🐶", words = splitWords("🐶 🐱 🐭 🐰 🦊 🐻 🐼 🐨 🐯 🦁 🐮 🐷 🐸 🐵 🐔 🐧 🐦 🦉 🐴 🐝 🦋 🐢 🐍 🐙 🐬 🐳 🌲 🌳 🌸 🌹 🌻 ☀ 🌙 ⛅ ☔ ❄ ⚡ 🌈") },
    { icon = "🍎", words = splitWords("🍎 🍌 🍇 🍓 🍒 🍑 🍋 🍉 🍕 🍔 🍟 🌭 🥪 🌮 🍝 🍜 🍣 🍰 🎂 🍩 🍪 🍫 🍿 ☕ 🍵 🍺 🍷 🥂 🍸 🥤 🍞 🧀 🥚 🥓 🥗") },
    { icon = "🚗", words = splitWords("🚗 🚕 🚌 🚲 ✈ 🚀 🚂 ⛵ 🏠 🏢 ⏰ 📱 💻 📷 📚 📖 ✏ 📝 📌 🔑 🔒 💰 🎁 🎵 🎮 ⚽ 🏆 🔔 📅 📧 📎 🔍 ⚙") },
}

local SYMBOL_PAGES = {
    symbols1 = {
        { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" },
        splitWords("@ # $ € & - + ( ) /"),
        { '"', "'", ":", ";", "!", "?", "_" },
        toggle_label = "=\\<", toggle_target = "symbols2",
    },
    symbols2 = {
        splitWords("~ ` | • √ π ÷ × § \\"),
        splitWords("£ ¢ ¥ ^ ° = { } < >"),
        splitWords("% © ® ™ [ ] *"),
        toggle_label = "?123", toggle_target = "symbols1",
    },
}

local ALTERNATES = {
    de = { a = { "ä", "á", "à" }, o = { "ö", "ó" }, u = { "ü", "ú" }, s = { "ß" },
           e = { "é", "è" }, i = { "í" }, c = { "ç" }, n = { "ñ" } },
    en = { a = { "á", "à", "ä" }, e = { "é", "è" }, i = { "í" }, o = { "ó", "ö" },
           u = { "ü", "ú" }, c = { "ç" }, n = { "ñ" }, s = { "ß" } },
}

----------------------------------------------------------------------
-- Label safety. KOReader's TextWidget raises "bad argument #2 to shapeLine
-- (index out of range)" while *painting* when its text is odd (invalid
-- UTF-8, control characters) or has to be clipped. Labels are therefore
-- cleaned and pre-shortened to fit before they reach the widget.
----------------------------------------------------------------------
local function cleanUtf8(s)
    s = tostring(s or "")
    s = (s:gsub("[\9\10\13]", " "))
    s = (s:gsub("[%z\1-\8\11\12\14-\31\127]", ""))
    local out, i, n = {}, 1, #s
    while i <= n do
        local b = s:byte(i)
        local len = (b < 0x80 and 1) or (b >= 0xC2 and b < 0xE0 and 2)
            or (b >= 0xE0 and b < 0xF0 and 3) or (b >= 0xF0 and b < 0xF5 and 4) or 0
        local valid = len > 0 and i + len - 1 <= n
        if valid then
            for k = 1, len - 1 do
                local c = s:byte(i + k)
                if c < 0x80 or c > 0xBF then valid = false; break end
            end
        end
        if valid then
            out[#out + 1] = s:sub(i, i + len - 1)
            i = i + len
        else
            i = i + 1
        end
    end
    s = table.concat(out)
    if s == "" then s = " " end
    return s
end

local function fitText(text, face, width)
    if not width or width <= 0 then return text end
    local ok, RenderText = pcall(require, "ui/rendertext")
    if ok and type(RenderText) == "table" and type(RenderText.getSubTextByWidth) == "function" then
        local ok2, sub = pcall(RenderText.getSubTextByWidth, RenderText, text, face, width, true, false)
        if ok2 and type(sub) == "string" and sub ~= "" then return sub end
    end
    return text
end

----------------------------------------------------------------------
-- Key widget
----------------------------------------------------------------------
local Key = InputContainer:extend{
    label = "", callback = nil, hold_callback = nil, hint = nil,
    width = 40, height = 38, font_size = 22,
    style = nil,        -- nil | "func" (grey) | "primary" (black)
    align = nil,        -- nil (centered) | "left"
    keep_font = false,  -- do not shrink the font for longer labels
    no_clip = false,    -- never truncate (single glyph keys)
}

function Key:init()
    self.range = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self.label = cleanUtf8(self.label)
    local size = self.font_size
    if not self.keep_font and charCount(self.label) >= 3 then size = math.floor(size * 0.55) end
    local border = scale(1)
    local side_pad = scale(6)
    local face = Font:getFace("cfont", size)
    self._face = face
    if self.align == "left" then
        self._fit_width = self.width - 2 * (scale(12) + border + side_pad)
    elseif not self.no_clip then
        self._fit_width = self.width - 2 * (side_pad + border)
    end
    self.label = fitText(self.label, face, self._fit_width)
    -- The text already fits, so TextWidget never has to clip (that path is
    -- what raised the shapeLine error).
    self.text_widget = newText{
        text = self.label,
        face = face,
        fgcolor = Blitbuffer.COLOR_BLACK,
        padding = 0,
    }
    local inner_dimen = Geom:new{ w = self.width - 2 * border, h = self.height - 2 * border }
    local inner
    if self.align == "left" then
        inner = LeftContainer:new{
            dimen = inner_dimen,
            HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = scale(12) }, self.text_widget },
        }
    else
        inner = CenterContainer:new{ dimen = inner_dimen, self.text_widget }
    end
    self.frame = FrameContainer:new{
        width = self.width, height = self.height, padding = 0,
        bordersize = border, color = Blitbuffer.COLOR_BLACK,
        radius = scale(8), background = Blitbuffer.COLOR_WHITE,
        inner,
    }
    if self.hint and self.hint ~= "" then
        self.hint_widget = newText{
            text = self.hint,
            face = Font:getFace("cfont", math.max(scale(9), math.floor(self.height * 0.2))),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            padding = 0,
        }
    end
    self[1] = self.frame
    self.ges_events = {
        TapKey = { GestureRange:new{ ges = "tap", range = self.range } },
        HoldKey = { GestureRange:new{ ges = "hold", range = self.range } },
    }
end

function Key:setLabel(label)
    label = fitText(cleanUtf8(label), self._face, self._fit_width)
    if self.label == label then return end
    self.label = label
    self.text_widget:setText(label)
end

function Key:setActive(active)
    self.active = active and true or false
end

function Key:_colors()
    if self.active then return theme.active, theme.active_text, true end
    if self.style == "primary" then return theme.primary, theme.primary_text, true end
    if self.style == "func" then return theme.func, theme.func_text, true end
    return theme.key, theme.key_text, false
end

function Key:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local r = self.range
    r.x, r.y, r.w, r.h = x, y, self.dimen.w, self.dimen.h
    local bg, fg, dark = self:_colors()
    self.frame.background = bg
    self.frame.color = theme.border
    self.text_widget.fgcolor = fg
    if not pcall(InputContainer.paintTo, self, bb, x, y) then
        -- Last line of defence: a label that cannot be painted is replaced
        -- instead of taking KOReader down.
        pcall(function()
            self.label = "?"
            self.text_widget:setText("?")
        end)
        pcall(InputContainer.paintTo, self, bb, x, y)
    end
    if self.hint_widget then
        self.hint_widget.fgcolor = dark and fg or theme.hint
        pcall(function()
            local size = self.hint_widget:getSize()
            self.hint_widget:paintTo(bb, x + self.width - size.w - scale(6), y + scale(3))
        end)
    end
end

-- No press animation on purpose: every extra refresh is expensive on E-Ink.
-- The changed text in the top bar is the feedback.
function Key:onTapKey()
    if self.callback then self.callback(self) end
    return true
end

function Key:onHoldKey()
    if self.hold_callback then
        self.hold_callback(self)
    elseif self.callback then
        self.callback(self)
    end
    return true
end

----------------------------------------------------------------------
-- Keyboard
----------------------------------------------------------------------
local Keyboard = InputContainer:extend{
    value = "",
    on_submit = nil,
    on_cancel = nil,
    on_change = nil,
    title = nil,
    placeholder = nil,
    numeric_only = false,
    secure = false,
    multiline = false,
    suggestions = nil,
    language = nil,
    swipe = true,       -- Wisch-Eingabe (Gboard-Stil) mit Spur
    modal = true,
}

function Keyboard:init()
    ui_is_de = resolvedLanguage("auto") == "de"
    self.width = Screen:getWidth()
    local screen_h = Screen:getHeight()
    self.value = self.value or ""
    self.multiline = self.multiline == true
    self.language = resolvedLanguage(self.language)
    self.caps_lock = self.caps_lock == true
    self.pages = {}
    self.letter_keys = {}
    self.suggestion_keys = nil
    self.alt_options = nil
    self.strip_labels = { "", "", "" }
    self.suggestion_source = self.suggestions or loadSuggestions(self.language)
    self.suggestion_database = not self.suggestions and SuggestionDatabase or nil
    self.suggest_enabled = not self.secure and not self.numeric_only
    self.mode = self.numeric_only and "numeric" or "letters"
    -- on_change can be expensive (it mirrors into a native dialog), so it is
    -- debounced instead of running on every keystroke.
    self._emit_change = function()
        if self.on_change then self.on_change(self.value) end
    end
    self._prev_space = false

    -- Metrics: everything derives from the screen so the keys stay big on
    -- any E-Ink device (portrait ~8% of screen height per row).
    local landscape = self.width > screen_h
    self.gap = scale(4)
    self.pad = scale(6)
    self.border = scale(1)
    self.inner_width = self.width - 2 * (self.pad + self.border)
    self.row_h = math.max(scale(46), math.floor(screen_h * (landscape and 0.105 or 0.078)))
    self.bar_h = math.floor(self.row_h * 0.78)
    self.strip_h = math.floor(self.row_h * 0.72)

    self.shift = (not self.secure) and self:_autoShift() or false

    -- Speed: a tap should fire on release, not after the double-tap timeout.
    local input = Device.input
    if input then
        self._saved_double_tap = input.disable_double_tap
        input.disable_double_tap = true
        self._double_tap_changed = true
    end

    self:_buildTop()
    self[1] = self:_getPage(self.mode)
    self.key_events = self.key_events or {}
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end

    -- Swipe typing: touch starts the path, pan extends it, release decodes it.
    -- Pan/release use the whole screen so a finger leaving the keyboard
    -- still ends the swipe cleanly.
    self.swipe_enabled = self.swipe ~= false and self.suggest_enabled
    self.ges_events = self.ges_events or {}
    if self.swipe_enabled then
        local keyboard = self
        local function keyboard_range() return keyboard.dimen end
        local screen_range = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
        self.ges_events.SwipeTouch = { GestureRange:new{ ges = "touch", range = keyboard_range } }
        self.ges_events.SwipePan = { GestureRange:new{ ges = "pan", range = screen_range } }
        self.ges_events.SwipePanRelease = { GestureRange:new{ ges = "pan_release", range = screen_range } }
        self.ges_events.SwipeSwipe = { GestureRange:new{ ges = "swipe", range = screen_range } }
    end
    self:_update()
    self._ready = true
end

----------------------------------------------------------------------
-- Layout helpers
----------------------------------------------------------------------
function Keyboard:_vgap(height)
    return VerticalSpan:new{ width = height or self.gap }
end

-- items: { label, weight, callback, hold, style, hint, font, active, align,
-- keep_font } or { spacer = weight }. `units` = how many weight-1 keys span
-- the full width (10 for the letter grid).
function Keyboard:_makeRow(items, height, units)
    units = units or 10
    local gap = self.gap
    local pw = (self.inner_width - (units - 1) * gap) / units
    local widths, last_key = {}, nil
    local used, prev_key = 0, false
    for i, item in ipairs(items) do
        local w
        if item.spacer then
            w = math.floor(item.spacer * (pw + gap))
            prev_key = false
        else
            if prev_key then used = used + gap end
            w = math.floor(item.weight * pw + (item.weight - 1) * gap)
            last_key = i
            prev_key = true
        end
        widths[i] = w
        used = used + w
    end
    if last_key then widths[last_key] = widths[last_key] + (self.inner_width - used) end

    local group = HorizontalGroup:new{ align = "center" }
    local keys = {}
    prev_key = false
    for i, item in ipairs(items) do
        if item.spacer then
            table.insert(group, HorizontalSpan:new{ width = widths[i] })
            prev_key = false
        else
            if prev_key then table.insert(group, HorizontalSpan:new{ width = gap }) end
            local key = Key:new{
                label = item.label or "",
                width = widths[i],
                height = height,
                font_size = item.font or math.floor(height * 0.36),
                style = item.style,
                hint = item.hint,
                align = item.align,
                keep_font = item.keep_font,
                no_clip = item.no_clip or item.letter ~= nil or (item.keep_font and item.align ~= "left"),
                callback = item.callback,
                hold_callback = item.hold,
            }
            if item.active then key:setActive(true) end
            item.key = key
            keys[#keys + 1] = key
            table.insert(group, key)
            prev_key = true
        end
    end
    return group, keys
end

function Keyboard:_buildTop()
    local inner = self.inner_width
    if self.title then
        self.title_widget = newText{
            text = self.title,
            face = Font:getFace("smallinfofont", math.floor(self.bar_h * 0.36)),
            fgcolor = theme.key_text,
            bold = true,
            max_width = inner,
        }
    end
    local cancel_w = math.floor(inner * (self.multiline and 0.11 or 0.13))
    self.cancel_key = Key:new{
        label = "✕", width = cancel_w, height = self.bar_h, style = "func",
        font_size = math.floor(self.bar_h * 0.42),
        callback = function() self:_requestCancel() end,
    }
    local submit_w = self.multiline and math.floor(inner * 0.17) or 0
    local display_w = inner - cancel_w - submit_w - self.gap * (self.multiline and 2 or 1)
    self.display_pad = scale(10)
    self.display_font = math.floor(self.bar_h * 0.46)
    self.display_width = display_w
    self.display = newText{
        text = " ",
        face = Font:getFace("smallinfofont", self.display_font),
        fgcolor = theme.key_text,
        padding = 0,
        max_width = display_w - 2 * self.display_pad,
    }
    local bs = scale(1)
    local display_frame = FrameContainer:new{
        width = display_w, height = self.bar_h, padding = 0,
        bordersize = bs, color = theme.border, radius = scale(8),
        background = theme.key,
        LeftContainer:new{
            dimen = Geom:new{ w = display_w - 2 * bs, h = self.bar_h - 2 * bs },
            HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = self.display_pad }, self.display },
        },
    }
    local top_items = {
        align = "center",
        self.cancel_key,
        HorizontalSpan:new{ width = self.gap },
        display_frame,
    }
    if self.multiline then
        self.submit_key = Key:new{
            label = ui("Fertig", "Done"), width = submit_w, height = self.bar_h,
            style = "primary", font_size = math.floor(self.bar_h * 0.34),
            callback = function() self:_submit() end,
        }
        table.insert(top_items, HorizontalSpan:new{ width = self.gap })
        table.insert(top_items, self.submit_key)
    end
    self.top_bar = HorizontalGroup:new(top_items)
end

function Keyboard:_wrapPage(strip, body_rows)
    local content = { align = "left" }
    local title_h = 0
    if self.title_widget then
        table.insert(content, self.title_widget)
        table.insert(content, self:_vgap())
        title_h = self.title_widget:getSize().h + self.gap
    end
    table.insert(content, self.top_bar)
    table.insert(content, self:_vgap())
    local strip_total = 0
    if strip then
        table.insert(content, strip)
        table.insert(content, self:_vgap())
        strip_total = self.strip_h + self.gap
    end
    for index, row in ipairs(body_rows) do
        if index > 1 then table.insert(content, self:_vgap()) end
        table.insert(content, row)
    end
    local group = VerticalGroup:new(content)
    local height = group:getSize().h + 2 * (self.pad + self.border)
    if not self.kb_h then
        self.kb_h = math.min(Screen:getHeight(), height)
        self.dimen = Geom:new{ x = 0, y = Screen:getHeight() - self.kb_h, w = self.width, h = self.kb_h }
        self.top_h = self.border + self.pad + title_h + self.bar_h + self.gap + strip_total
    end
    return FrameContainer:new{
        width = self.width, height = self.kb_h, padding = self.pad,
        bordersize = self.border, color = theme.border,
        radius = scale(8), background = theme.background,
        group,
    }
end

----------------------------------------------------------------------
-- Common keys
----------------------------------------------------------------------
function Keyboard:_backspaceItem(weight)
    return {
        label = "⌫", weight = weight or 1.5, style = "func",
        callback = function() self:_backspace() end,
        hold = function() self:_backspaceWord() end,
    }
end

function Keyboard:_doneItem(weight)
    if self.multiline then
        return { label = "↵", weight = weight or 1.5, style = "func", callback = function() self:_insert("\n") end }
    end
    return { label = ui("Fertig", "Done"), weight = weight or 1.5, style = "primary", callback = function() self:_submit() end }
end

function Keyboard:_spaceItem(weight)
    return {
        label = self.language == "de" and "Deutsch" or "English", weight = weight or 4,
        callback = function() self:_pressSpace() end,
        hold = function() self:_switchLanguage() end,
    }
end

function Keyboard:_bottomRow(left_label, left_callback)
    local items = {
        { label = left_label, weight = 1.5, style = "func", callback = left_callback },
        { label = ",", weight = 1, callback = function() self:_insert(",") end },
        { label = "🙂", weight = 1, style = "func", no_clip = true, callback = function() self:_setMode("emoji") end },
        self:_spaceItem(4),
        { label = ".", weight = 1, callback = function() self:_insert(".") end },
        self:_doneItem(1.5),
    }
    return (self:_makeRow(items, self.row_h))
end

----------------------------------------------------------------------
-- Pages
----------------------------------------------------------------------
function Keyboard:_getStrip()
    if self.alpha_strip then return self.alpha_strip end
    self.suggestion_keys = {}
    local items = {
        { label = "📋", weight = 1, style = "func", font = math.floor(self.strip_h * 0.5), no_clip = true,
          callback = function() self:_openClipboard() end },
    }
    for slot = 1, 3 do
        items[#items + 1] = {
            label = "", weight = 3, font = math.floor(self.strip_h * 0.42),
            callback = function() self:_stripTap(slot) end, slot = slot,
        }
    end
    self.alpha_strip = (self:_makeRow(items, self.strip_h))
    for _i, item in ipairs(items) do
        if item.slot and item.key then self.suggestion_keys[item.slot] = item.key end
    end
    return self.alpha_strip
end

function Keyboard:_alternates(ch, digit)
    local base = ALTERNATES[self.language] and ALTERNATES[self.language][ch]
    local opts = {}
    if base then for _i, v in ipairs(base) do opts[#opts + 1] = v end end
    if digit then opts[#opts + 1] = digit end
    while #opts > 3 do table.remove(opts, #opts - (digit and 1 or 0)) end
    if #opts == 0 then return nil end
    return opts
end

function Keyboard:_buildLetters()
    self.letter_keys = {}
    self.shift_key = nil
    self._case_state = nil
    self._shift_state = nil
    local de = self.language == "de"
    local rows = { de and "qwertzuiop" or "qwertyuiop", "asdfghjkl", de and "yxcvbnm" or "zxcvbnm" }
    local body = {}
    for r, chars in ipairs(rows) do
        local items = {}
        if r == 2 then items[#items + 1] = { spacer = 0.5 } end
        if r == 3 then
            items[#items + 1] = {
                label = "⇧", weight = 1.5, style = "func", is_shift = true,
                callback = function() self:_toggleShift() end,
                hold = function() self:_toggleCaps() end,
            }
        end
        local col = 0
        for ch in chars:gmatch(".") do
            col = col + 1
            local digit = (r == 1) and tostring(col % 10) or nil
            local opts = self:_alternates(ch, digit)
            items[#items + 1] = {
                label = ch, weight = 1, letter = ch,
                hint = digit or (opts and opts[1]),
                callback = function() self:_typeLetter(ch) end,
                hold = function() self:_holdLetter(ch, opts) end,
            }
        end
        if r == 2 then items[#items + 1] = { spacer = 0.5 } end
        if r == 3 then items[#items + 1] = self:_backspaceItem(1.5) end
        local group = self:_makeRow(items, self.row_h)
        for _i, item in ipairs(items) do
            if item.letter and item.key then
                local lower, upper = casePair(item.letter)
                self.letter_keys[#self.letter_keys + 1] = { key = item.key, lower = lower, upper = upper, ch = item.letter }
            elseif item.is_shift then
                self.shift_key = item.key
            end
        end
        body[#body + 1] = group
    end
    body[#body + 1] = self:_bottomRow("?123", function() self:_setMode("symbols1") end)
    return self:_wrapPage(self:_getStrip(), body)
end

function Keyboard:_buildSymbols(which)
    local def = SYMBOL_PAGES[which]
    local body = {}
    for r = 1, 3 do
        local items = {}
        if r == 3 then
            items[#items + 1] = {
                label = def.toggle_label, weight = 1.5, style = "func",
                callback = function() self:_setMode(def.toggle_target) end,
            }
        end
        for _i, ch in ipairs(def[r]) do
            items[#items + 1] = { label = ch, weight = 1, callback = function() self:_insert(ch) end }
        end
        if r == 3 then items[#items + 1] = self:_backspaceItem(1.5) end
        body[#body + 1] = (self:_makeRow(items, self.row_h))
    end
    body[#body + 1] = self:_bottomRow("ABC", function() self:_setMode("letters") end)
    return self:_wrapPage(self:_getStrip(), body)
end

function Keyboard:_emojiCategories()
    loadPersisted()
    local cats = { { icon = "🕘", words = recent_emojis } }
    for _i, cat in ipairs(EMOJI_CATEGORIES) do cats[#cats + 1] = cat end
    return cats
end

function Keyboard:_buildEmoji()
    local cats = self:_emojiCategories()
    if not self.emoji_cat then self.emoji_cat = (#recent_emojis > 0) and 1 or 2 end
    self.emoji_cat = math.max(1, math.min(self.emoji_cat, #cats))
    local words = cats[self.emoji_cat].words
    local per_page, columns = 24, 8
    local pages = math.max(1, math.ceil(#words / per_page))
    self.emoji_page = math.max(1, math.min(self.emoji_page or 1, pages))

    local tabs = {}
    for index, cat in ipairs(cats) do
        tabs[#tabs + 1] = {
            label = cat.icon, weight = 1, style = "func", no_clip = true,
            active = (index == self.emoji_cat), font = math.floor(self.strip_h * 0.5),
            callback = function() self.emoji_cat = index; self.emoji_page = 1; self:_setMode("emoji") end,
        }
    end
    local strip = (self:_makeRow(tabs, self.strip_h, #cats))

    local body = {}
    for r = 1, 3 do
        local items = {}
        for c = 1, columns do
            local emoji = words[(self.emoji_page - 1) * per_page + (r - 1) * columns + c]
            items[#items + 1] = {
                label = emoji or " ", weight = 1, keep_font = true, font = math.floor(self.row_h * 0.5),
                callback = emoji and function() recordEmoji(emoji); self:_insert(emoji) end or nil,
            }
        end
        body[#body + 1] = (self:_makeRow(items, self.row_h, columns))
    end
    local function turn(delta)
        self.emoji_page = ((self.emoji_page - 1 + delta) % pages) + 1
        self:_setMode("emoji")
    end
    local controls = {
        { label = "ABC", weight = 1.5, style = "func", callback = function() self:_setMode("letters") end },
        { label = "‹", weight = 1, style = "func", callback = function() turn(-1) end },
        { label = "›", weight = 1, style = "func", callback = function() turn(1) end },
        { label = pages > 1 and (self.emoji_page .. "/" .. pages) or " ", weight = 5 },
        self:_backspaceItem(1.5),
    }
    body[#body + 1] = (self:_makeRow(controls, self.row_h))
    return self:_wrapPage(strip, body)
end

local function oneLine(text, max_chars)
    text = text:gsub("%s+", " ")
    return utf8Head(text, max_chars or 120)
end

function Keyboard:_buildClipboard()
    loadPersisted()
    local actions = {
        { label = ui("Kopieren", "Copy"), weight = 3, style = "func", callback = function() self:_clipCopy(false) end },
        { label = ui("Ausschneiden", "Cut"), weight = 4, style = "func", callback = function() self:_clipCopy(true) end },
        { label = ui("Einfügen", "Paste"), weight = 3, style = "func", callback = function() self:_clipPasteLatest() end },
    }
    local strip = (self:_makeRow(actions, self.strip_h))

    local per_page = 5
    local pages = math.max(1, math.ceil(#clip_history / per_page))
    self.clip_page = math.max(1, math.min(self.clip_page or 1, pages))
    local region_h = 3 * self.row_h + 2 * self.gap
    local entry_h = math.floor((region_h - (per_page - 1) * self.gap) / per_page)
    local body = {}
    for i = 1, per_page do
        local index = (self.clip_page - 1) * per_page + i
        local text = clip_history[index]
        local label = text and oneLine(text) or " "
        if not text and i == 1 and #clip_history == 0 then label = ui("Zwischenablage leer", "Clipboard is empty") end
        local item = {
            label = label, weight = 10, align = "left", keep_font = true,
            font = math.floor(entry_h * 0.42),
        }
        if text then
            item.callback = function() self:_pasteText(text) end
            item.hold = function()
                table.remove(clip_history, index)
                store_dirty = true
                self:_setMode("clipboard")
            end
        end
        body[#body + 1] = (self:_makeRow({ item }, entry_h))
    end
    local leftover = region_h - (per_page * entry_h + (per_page - 1) * self.gap)
    if leftover > 0 then body[#body + 1] = self:_vgap(leftover - self.gap > 0 and leftover - self.gap or 1) end
    local function turn(delta)
        self.clip_page = ((self.clip_page - 1 + delta) % pages) + 1
        self:_setMode("clipboard")
    end
    local controls = {
        { label = "ABC", weight = 1.5, style = "func", callback = function() self:_setMode("letters") end },
        { label = "🙂", weight = 1, style = "func", no_clip = true, callback = function() self:_setMode("emoji") end },
        { label = "‹", weight = 1, style = "func", callback = function() turn(-1) end },
        { label = "›", weight = 1, style = "func", callback = function() turn(1) end },
        { label = pages > 1 and (self.clip_page .. "/" .. pages) or " ", weight = 4 },
        self:_backspaceItem(1.5),
    }
    body[#body + 1] = (self:_makeRow(controls, self.row_h))
    return self:_wrapPage(strip, body)
end

function Keyboard:_buildNumeric()
    local body = {}
    local rows = { { "1", "2", "3" }, { "4", "5", "6" }, { "7", "8", "9" }, { "-", "0", "." } }
    for _i, labels in ipairs(rows) do
        local items = {}
        for _j, d in ipairs(labels) do
            items[#items + 1] = {
                label = d, weight = 1, font = math.floor(self.row_h * 0.45),
                callback = function() self:_insert(d) end,
            }
        end
        body[#body + 1] = (self:_makeRow(items, self.row_h, 3))
    end
    body[#body + 1] = (self:_makeRow({ self:_backspaceItem(1), self:_doneItem(2) }, self.row_h, 3))
    return self:_wrapPage(nil, body)
end

local PAGE_BUILDERS = {
    letters = function(self) return self:_buildLetters() end,
    symbols1 = function(self) return self:_buildSymbols("symbols1") end,
    symbols2 = function(self) return self:_buildSymbols("symbols2") end,
    emoji = function(self) return self:_buildEmoji() end,
    clipboard = function(self) return self:_buildClipboard() end,
    numeric = function(self) return self:_buildNumeric() end,
}

function Keyboard:_getPage(name)
    local page = self.pages[name]
    if not page then
        page = PAGE_BUILDERS[name](self)
        self.pages[name] = page
    end
    return page
end

function Keyboard:_setMode(mode, silent)
    self.mode = mode
    self.alt_options = nil
    if mode == "emoji" or mode == "clipboard" then self.pages[mode] = nil end
    self[1] = self:_getPage(mode)
    if not silent then self:_update("ui") end
end

----------------------------------------------------------------------
-- Editing logic
----------------------------------------------------------------------
function Keyboard:_autoShift()
    if self.numeric_only or self.secure then return false end
    local v = self.value or ""
    return v == "" or v:match("[%.%!%?]%s+$") ~= nil or v:match("\n$") ~= nil
end

function Keyboard:_afterEdit(refresh_mode)
    if self.caps_lock then
        self.shift = true
    else
        self.shift = self:_autoShift()
    end
    self:_update(refresh_mode)
end

function Keyboard:_insert(text)
    self.value = self.value .. text
    self.alt_options = nil
    self._prev_space = false
    self:_afterEdit()
end

function Keyboard:_typeLetter(ch)
    local lower, upper = casePair(ch)
    self:_insert((self.caps_lock or self.shift) and upper or lower)
end

function Keyboard:_casedOption(option)
    if option == "ß" or not (self.caps_lock or self.shift) then return option end
    return LOWER_TO_UPPER[option] or option
end

function Keyboard:_holdLetter(ch, opts)
    if not opts or #opts == 0 then return self:_typeLetter(ch) end
    if #opts == 1 then return self:_insert(self:_casedOption(opts[1])) end
    self.alt_options = opts
    self:_update()
end

function Keyboard:_pressSpace()
    local v = self.value
    if self._prev_space and not self.secure and not self.numeric_only and v:match("[^%s%p] $") then
        self.value = v:sub(1, -2) .. ". "
    else
        self.value = v .. " "
    end
    self.alt_options = nil
    self._prev_space = true
    self:_afterEdit()
end

function Keyboard:_backspace()
    local sr = self.swipe_result
    if sr and self.value == sr.value_after then
        -- Like Gboard: backspace right after a swiped word removes the whole word.
        self.value = sr.before
        self.swipe_result = nil
        self.alt_options = nil
        self._prev_space = false
        self:_afterEdit()
        return
    end
    self.value = removeLastUTF8Character(self.value)
    self.alt_options = nil
    self._prev_space = false
    self:_afterEdit()
end

function Keyboard:_backspaceWord()
    self.value = removeLastWord(self.value)
    self.alt_options = nil
    self._prev_space = false
    self:_afterEdit()
end

function Keyboard:_toggleShift()
    local t = now()
    if self._last_shift_tap and (t - self._last_shift_tap) < 0.45 then
        self.caps_lock, self.shift = true, true
        self._last_shift_tap = nil
    else
        if self.caps_lock then
            self.caps_lock, self.shift = false, false
        else
            self.shift = not self.shift
        end
        self._last_shift_tap = t
    end
    self:_update()
end

function Keyboard:_toggleCaps()
    self.caps_lock = not self.caps_lock
    self.shift = self.caps_lock
    self._last_shift_tap = nil
    self:_update()
end

function Keyboard:_switchLanguage()
    self.language = self.language == "de" and "en" or "de"
    if not self.suggestions then
        self.suggestion_source = loadSuggestions(self.language)
        self.suggestion_database = SuggestionDatabase
    end
    self.pages.letters = nil
    self:_setMode("letters")
end

function Keyboard:_submit()
    if self._submit_requested then return true end
    self._submit_requested = true
    -- Defer: on_submit closes this keyboard, which must not happen while
    -- UIManager is still dispatching the key tap.
    UIManager:nextTick(function()
        if self.on_submit then self.on_submit(self.value) end
    end)
    return true
end

----------------------------------------------------------------------
-- Suggestions
----------------------------------------------------------------------
function Keyboard:_matchWords(prefix)
    self._match_cache = self._match_cache or {}
    local cache_key = self.language .. ":" .. prefix
    local cached = self._match_cache[cache_key]
    if cached then return cached end
    local result = self:_matchWordsUncached(prefix)
    self._match_cache[cache_key] = result
    return result
end

function Keyboard:_matchWordsUncached(prefix)
    local result = {}
    if self.suggestion_database and type(self.suggestion_database.match) == "function" then
        local ok, matches = pcall(self.suggestion_database.match, self.language, prefix, 3)
        if ok and type(matches) == "table" then
            for _i, candidate in ipairs(matches) do
                local word = type(candidate) == "table" and candidate.word or tostring(candidate)
                if word ~= "" then result[#result + 1] = word end
            end
            return result
        end
    end
    for _i, candidate in ipairs(self.suggestion_source or {}) do
        local word = type(candidate) == "table" and candidate.word or tostring(candidate)
        local candidate_lower = lowerUtf8(word)
        if word ~= "" and candidate_lower ~= prefix and (prefix == "" or candidate_lower:sub(1, #prefix) == prefix) then
            result[#result + 1] = word
            if #result == 3 then break end
        end
    end
    return result
end

function Keyboard:_adaptCase(word, token)
    if token ~= "" then
        if UPPER_TO_LOWER[firstChar(token)] then return capitalizeFirst(word) end
        return word
    end
    if self.shift or self.caps_lock then return capitalizeFirst(word) end
    return word
end

function Keyboard:_stripLabels()
    local labels = { "", "", "" }
    if self.alt_options then
        for slot = 1, 3 do
            local option = self.alt_options[slot]
            labels[slot] = option and self:_casedOption(option) or ""
        end
        return labels
    end
    if not self.suggest_enabled then return labels end
    local sr = self.swipe_result
    if sr and self.value == sr.value_after then
        for slot = 1, 3 do labels[slot] = sr.labels[slot] or "" end
        return labels
    end
    local token = trailingWord(self.value)
    local words = self:_matchWords(lowerUtf8(token))
    for slot = 1, 3 do
        labels[slot] = words[slot] and self:_adaptCase(words[slot], token) or ""
    end
    return labels
end

function Keyboard:_stripTap(slot)
    if self.alt_options then
        local option = self.alt_options[slot]
        if option then
            self:_insert(self:_casedOption(option))
        else
            self.alt_options = nil
            self:_update()
        end
        return
    end
    local sr = self.swipe_result
    if sr and self.value == sr.value_after then
        local pick = sr.labels[slot]
        if pick and pick ~= "" then
            self.value = sr.base .. pick .. " "
            sr.value_after = self.value
            self._prev_space = false
            self:_afterEdit()
        end
        return
    end
    local word = self.strip_labels and self.strip_labels[slot]
    if not word or word == "" then return end
    local token = trailingWord(self.value)
    self.value = self.value:sub(1, #self.value - #token) .. word .. " "
    self._prev_space = false
    self:_afterEdit()
end

----------------------------------------------------------------------
-- Swipe typing (Gboard style): drag over the letters, a word appears.
--   * the finger leaves a tapering "comet tail" while it moves
--   * on release the path is matched against the dictionary (key positions
--     are compared with the path, frequency breaks ties)
--   * best word is inserted with a trailing space, the 2 runners-up appear in
--     the suggestion strip; backspace right afterwards removes the whole word
----------------------------------------------------------------------
local SWIPE_POINTS = 24          -- resampling resolution used for matching
local SWIPE_MATCH_LIMIT = 500    -- dictionary candidates per start letter
local SWIPE_MAX_COST = 1.15      -- max mean path distance (in key sizes)
local SWIPE_TRAIL_MAX = 40       -- points of the comet tail

local BASE_LETTER = {
    ["ä"] = "a", ["ö"] = "o", ["ü"] = "u", ["ß"] = "s",
    ["á"] = "a", ["à"] = "a", ["é"] = "e", ["è"] = "e", ["ê"] = "e",
    ["í"] = "i", ["ó"] = "o", ["ò"] = "o", ["ú"] = "u", ["ù"] = "u",
    ["š"] = "s", ["ç"] = "c", ["ñ"] = "n",
}
-- Words starting with an umlaut live under their own dictionary prefix.
local SWIPE_PREFIX_ALTS = { de = { a = { "ä" }, o = { "ö" }, u = { "ü" } } }

-- Lower-case word -> base letters a-z (umlauts folded, repeats collapsed,
-- because a swipe only passes a letter once). nil = not swipeable.
local function swipeLetters(lower_word)
    local out = {}
    for c in lower_word:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        local letter
        if #c == 1 then
            local b = c:byte()
            if b >= 97 and b <= 122 then letter = c end
        else
            letter = BASE_LETTER[c]
        end
        if not letter then return nil end
        if letter ~= out[#out] then out[#out + 1] = letter end
    end
    return table.concat(out)
end

local function polyLength(pts)
    local len = 0
    for i = 2, #pts do
        local dx, dy = pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y
        len = len + math.sqrt(dx * dx + dy * dy)
    end
    return len
end

local function smoothPath(pts)
    if #pts < 3 then return pts end
    local out = { pts[1] }
    for i = 2, #pts - 1 do
        out[#out + 1] = {
            x = (pts[i - 1].x + pts[i].x + pts[i + 1].x) / 3,
            y = (pts[i - 1].y + pts[i].y + pts[i + 1].y) / 3,
        }
    end
    out[#out + 1] = pts[#pts]
    return out
end

-- n points at equal arc-length distance along the polyline.
local function resamplePath(pts, n)
    local total = polyLength(pts)
    local out = { { x = pts[1].x, y = pts[1].y } }
    if total > 0 and #pts >= 2 then
        local step = total / (n - 1)
        local px, py = pts[1].x, pts[1].y
        local need, seg = step, 2
        while #out < n - 1 and seg <= #pts do
            local qx, qy = pts[seg].x, pts[seg].y
            local dx, dy = qx - px, qy - py
            local d = math.sqrt(dx * dx + dy * dy)
            if d >= need and d > 0 then
                local t = need / d
                px, py = px + dx * t, py + dy * t
                out[#out + 1] = { x = px, y = py }
                need = step
            else
                need = need - d
                px, py = qx, qy
                seg = seg + 1
            end
        end
    end
    local last = pts[#pts]
    while #out < n do out[#out + 1] = { x = last.x, y = last.y } end
    return out
end

local function nearestKeys(layout, x, y, max_dist, count)
    local ux, uy = x / layout.kw, y / layout.kh
    local found = {}
    for _i, k in ipairs(layout.keys) do
        local dx, dy = k.ux - ux, k.uy - uy
        local d = math.sqrt(dx * dx + dy * dy)
        if d <= max_dist then found[#found + 1] = { key = k, d = d } end
    end
    table.sort(found, function(a, b) return a.d < b.d end)
    while #found > count do table.remove(found) end
    return found
end

local function unionBox(a, b)
    if not a then return b end
    if not b then return a end
    return {
        x1 = math.min(a.x1, b.x1), y1 = math.min(a.y1, b.y1),
        x2 = math.max(a.x2, b.x2), y2 = math.max(a.y2, b.y2),
    }
end

-- Key centres in screen pixels (and in "key units", where one key is 1x1).
-- Needs the letter page to have been painted at least once.
function Keyboard:_swipeLayout()
    if self.mode ~= "letters" then return nil end
    local keys, sum_w, sum_h = {}, 0, 0
    for _i, item in ipairs(self.letter_keys or {}) do
        local d = item.key and item.key.dimen
        if d and item.ch and d.x and d.y and (d.x ~= 0 or d.y ~= 0) and d.w > 0 and d.h > 0 then
            keys[#keys + 1] = { ch = item.ch, cx = d.x + d.w / 2, cy = d.y + d.h / 2 }
            sum_w, sum_h = sum_w + d.w, sum_h + d.h
        end
    end
    if #keys < 20 then return nil end
    local layout = { keys = keys, kw = sum_w / #keys, kh = sum_h / #keys }
    for _i, k in ipairs(keys) do
        k.ux, k.uy = k.cx / layout.kw, k.cy / layout.kh
    end
    return layout
end

function Keyboard:_swipeCandidates(prefix)
    self._swipe_cands = self._swipe_cands or {}
    local cache_key = self.language .. ":" .. prefix
    local cached = self._swipe_cands[cache_key]
    if cached then return cached end
    local out, seen = {}, {}
    local function add(word)
        if type(word) ~= "string" or word == "" then return end
        if lowerUtf8(firstChar(word)) ~= prefix then return end
        local lower = lowerUtf8(word)
        if seen[lower] then return end
        local letters = swipeLetters(lower)
        if not letters or #letters < 2 then return end
        seen[lower] = true
        out[#out + 1] = { word = word, letters = letters }
    end
    local db = self.suggestion_database
    if db and type(db.match) == "function" then
        local ok, matches = pcall(db.match, self.language, prefix, SWIPE_MATCH_LIMIT)
        if ok and type(matches) == "table" then
            for _i, candidate in ipairs(matches) do
                add(type(candidate) == "table" and candidate.word or tostring(candidate))
            end
        end
    end
    for _i, candidate in ipairs(self.suggestion_source or {}) do
        add(type(candidate) == "table" and candidate.word or tostring(candidate))
    end
    self._swipe_cands[cache_key] = out
    return out
end

-- Returns up to 3 dictionary words, best first (or nil).
function Keyboard:_decodeSwipe(points)
    local layout = self:_swipeLayout()
    if not layout or #points < 2 then return nil end
    local path = smoothPath(points)
    local units = {}
    for i, p in ipairs(path) do units[i] = { x = p.x / layout.kw, y = p.y / layout.kh } end
    local path_len = polyLength(units)
    if path_len < 1.2 then return nil end

    local starts = nearestKeys(layout, path[1].x, path[1].y, 1.4, 3)
    local ends = nearestKeys(layout, path[#path].x, path[#path].y, 1.4, 4)
    if #starts == 0 or #ends == 0 then return nil end
    local end_ok, key_by_ch = {}, {}
    for _i, e in ipairs(ends) do end_ok[e.key.ch] = true end
    for _i, k in ipairs(layout.keys) do key_by_ch[k.ch] = k end

    local sampled = resamplePath(units, SWIPE_POINTS)
    local best = {}
    for _i, s in ipairs(starts) do
        local prefixes = { s.key.ch }
        local alts = SWIPE_PREFIX_ALTS[self.language] and SWIPE_PREFIX_ALTS[self.language][s.key.ch]
        if alts then
            for _j, a in ipairs(alts) do prefixes[#prefixes + 1] = a end
        end
        for _j, prefix in ipairs(prefixes) do
            for rank, cand in ipairs(self:_swipeCandidates(prefix)) do
                local letters = cand.letters
                local n = #letters
                if end_ok[letters:sub(n, n)] then
                    local ideal, complete = {}, true
                    for k = 1, n do
                        local key = key_by_ch[letters:sub(k, k)]
                        if not key then complete = false; break end
                        ideal[k] = { x = key.ux, y = key.uy }
                    end
                    if complete then
                        local ideal_len = polyLength(ideal)
                        local ratio = ideal_len > 0 and (path_len / ideal_len) or 0
                        if ratio >= 0.55 and ratio <= 2.2 then
                            local ref = resamplePath(ideal, SWIPE_POINTS)
                            local sum = 0
                            for k = 1, SWIPE_POINTS do
                                local dx, dy = sampled[k].x - ref[k].x, sampled[k].y - ref[k].y
                                sum = sum + math.sqrt(dx * dx + dy * dy)
                            end
                            local cost = sum / SWIPE_POINTS
                            if cost <= SWIPE_MAX_COST then
                                -- frequency prior: earlier in the list = more common
                                local score = cost + 0.035 * math.log(rank)
                                if #best < 3 or score < best[#best].score then
                                    best[#best + 1] = { word = cand.word, score = score }
                                    table.sort(best, function(a, b) return a.score < b.score end)
                                    while #best > 3 do table.remove(best) end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    if #best == 0 then return nil end
    local words = {}
    for i, b in ipairs(best) do words[i] = b.word end
    return words
end

function Keyboard:_swipeStartKey(x, y)
    local layout = self:_swipeLayout()
    if not layout then return nil end
    local found = nearestKeys(layout, x, y, 0.75, 1)
    return found[1] and found[1].key or nil
end

----------------------------------------------------------------------
-- Swipe gestures and comet tail
----------------------------------------------------------------------
function Keyboard:_refreshBox(box, mode)
    if not box or not self.dimen then return end
    local d = self.dimen
    local x1, y1 = math.max(math.floor(box.x1), d.x), math.max(math.floor(box.y1), d.y)
    local x2, y2 = math.min(math.ceil(box.x2), d.x + d.w), math.min(math.ceil(box.y2), d.y + d.h)
    if x2 <= x1 or y2 <= y1 then return end
    self:_refresh(mode or "fast", Geom:new{ x = x1, y = y1, w = x2 - x1, h = y2 - y1 })
end

function Keyboard:_swipeTrailAdd(sw)
    local trail = self._trail
    if not self._trail_active or not trail then
        trail = { { x = sw.points[1].x, y = sw.points[1].y } }
        self._trail = trail
        self._trail_active = true
        self._trail_bbox = nil
        self._trail_dirty = nil
    end
    if #sw.points > 1 then
        local p = sw.points[#sw.points]
        trail[#trail + 1] = { x = p.x, y = p.y }
    end
    while #trail > SWIPE_TRAIL_MAX do table.remove(trail, 1) end

    local minx, miny, maxx, maxy = math.huge, math.huge, -math.huge, -math.huge
    for _i, p in ipairs(trail) do
        if p.x < minx then minx = p.x end
        if p.x > maxx then maxx = p.x end
        if p.y < miny then miny = p.y end
        if p.y > maxy then maxy = p.y end
    end
    local m = scale(10)
    local box = { x1 = minx - m, y1 = miny - m, x2 = maxx + m, y2 = maxy + m }
    self._trail_dirty = unionBox(self._trail_dirty, unionBox(self._trail_bbox, box))
    self._trail_bbox = box

    -- E-Ink cannot follow every touch sample; refresh a few times per second.
    local t = now()
    if t - (self._trail_refresh_t or 0) >= 0.04 then
        self._trail_refresh_t = t
        local dirty = self._trail_dirty
        self._trail_dirty = nil
        self:_refreshBox(dirty, "fast")
    end
end

-- Tapering black stroke: thin at the tail, thick at the fingertip.
function Keyboard:_paintTrail(bb)
    local trail = self._trail
    if not self._trail_active or not trail or #trail == 0 then return end
    local d = self.dimen
    local n = #trail
    local min_t, max_t = scale(2), scale(8)
    local color = Blitbuffer.COLOR_BLACK
    local function stamp(x, y, size)
        local half = math.floor(size / 2)
        local rx, ry = math.floor(x) - half, math.floor(y) - half
        local rw, rh = size, size
        if rx < d.x then rw = rw - (d.x - rx); rx = d.x end
        if ry < d.y then rh = rh - (d.y - ry); ry = d.y end
        if rx + rw > d.x + d.w then rw = d.x + d.w - rx end
        if ry + rh > d.y + d.h then rh = d.y + d.h - ry end
        if rw > 0 and rh > 0 then bb:paintRect(rx, ry, rw, rh, color) end
    end
    for i = 1, n do
        local f = i / n
        local size = math.max(1, math.floor(min_t + (max_t - min_t) * f * f))
        local p, q = trail[i], trail[i - 1]
        if q then
            local dx, dy = p.x - q.x, p.y - q.y
            local dist = math.sqrt(dx * dx + dy * dy)
            local steps = math.max(1, math.ceil(dist / math.max(1, size / 2)))
            for s = 1, steps do
                stamp(q.x + dx * s / steps, q.y + dy * s / steps, size)
            end
        else
            stamp(p.x, p.y, size)
        end
    end
end

function Keyboard:_swipeClearTrail()
    local box = self._trail_bbox
    self._trail_active, self._trail, self._trail_bbox, self._trail_dirty = false, nil, nil, nil
    return box
end

function Keyboard:onSwipeTouch(_args, ges)
    self._touch_seen = true
    self._swipe = nil
    if self._trail_active then self:_refreshBox(self:_swipeClearTrail(), "fast") end
    if self.mode ~= "letters" or not ges or not ges.pos then return false end
    local key = self:_swipeStartKey(ges.pos.x, ges.pos.y)
    if key then
        self._swipe = { points = { { x = ges.pos.x, y = ges.pos.y } }, key = key, active = false }
    end
    return false -- never consume: a normal tap must still reach the key
end

function Keyboard:onSwipePan(_args, ges)
    if self.mode ~= "letters" then return false end
    local pos = ges and ges.pos
    if not pos then return false end
    local sw = self._swipe
    if not sw then
        if self._touch_seen then return false end
        -- Devices that never send "touch": start with the first pan sample.
        local key = self:_swipeStartKey(pos.x, pos.y)
        if not key then return false end
        sw = { points = {}, key = key, active = false }
        self._swipe = sw
    end
    local pts = sw.points
    local last = pts[#pts]
    if last then
        local dx, dy = pos.x - last.x, pos.y - last.y
        if dx * dx + dy * dy < scale(3) * scale(3) then return true end
    end
    pts[#pts + 1] = { x = pos.x, y = pos.y }
    sw.active = true
    self:_swipeTrailAdd(sw)
    return true
end

function Keyboard:onSwipePanRelease(_args, ges)
    return self:_swipeEnd(ges, true)
end

function Keyboard:onSwipeSwipe(_args, ges)
    return self:_swipeEnd(ges, false)
end

function Keyboard:_swipeEnd(ges, is_release)
    local sw = self._swipe
    self._swipe = nil
    if not sw then return false end
    local pts = sw.points
    local pos = ges and ges.pos
    if is_release and pos then
        local last = pts[#pts]
        if not last or last.x ~= pos.x or last.y ~= pos.y then
            pts[#pts + 1] = { x = pos.x, y = pos.y }
        end
    elseif not is_release and #pts <= 1 and ges and ges.relative and pts[1] then
        -- Fast flick without pan samples: use it as a straight line.
        if ges.relative.x ~= 0 or ges.relative.y ~= 0 then
            pts[#pts + 1] = { x = pts[1].x + ges.relative.x, y = pts[1].y + ges.relative.y }
        end
    end

    local trail_box = self:_swipeClearTrail()
    local ok, words = pcall(self._decodeSwipe, self, pts)
    if not ok then
        pcall(function() require("logger").warn("AppDock swipe failed:", words) end)
        words = nil
    end
    if words and #words > 0 then
        self:_commitSwipe(words)
        return true
    end

    -- Nothing recognised. A tiny drag is just a sloppy tap on the start key.
    local layout = self:_swipeLayout()
    if sw.key and layout and polyLength(pts) < layout.kw * 0.9 then
        self:_typeLetter(sw.key.ch)
        self:_refreshBox(trail_box, "fast")
    else
        self:_update("ui")
    end
    return true
end

function Keyboard:_commitSwipe(words)
    local before = self.value
    local base = before
    if base ~= "" and not base:match("[%s%(%[{]$") then base = base .. " " end
    local labels = {}
    for i = 1, 3 do
        labels[i] = words[i] and self:_adaptCase(words[i], "") or ""
    end
    self.value = base .. labels[1] .. " "
    self.swipe_result = { before = before, base = base, labels = labels, value_after = self.value }
    self.alt_options = nil
    self._prev_space = false
    self:_afterEdit("ui")
end

----------------------------------------------------------------------
-- Clipboard actions
----------------------------------------------------------------------
function Keyboard:_openClipboard()
    loadPersisted()
    local text = trim(getSystemClipboard())
    if text ~= "" and text ~= clip_history[1] then addClip(text) end
    self.clip_page = 1
    self:_setMode("clipboard")
end

function Keyboard:_clipCopy(cut)
    if trim(self.value) == "" then return end
    addClip(self.value)
    setSystemClipboard(self.value)
    if cut then
        self.value = ""
        self._prev_space = false
        self.shift = self.caps_lock or self:_autoShift()
    end
    self.clip_page = 1
    self:_setMode("clipboard")
end

function Keyboard:_pasteText(text)
    if self.multiline then
        text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
    else
        text = text:gsub("[\r\n]+", " ")
    end
    self:_setMode("letters", true)
    self.value = self.value .. text
    self.alt_options = nil
    self._prev_space = false
    self:_afterEdit("ui")
end

function Keyboard:_clipPasteLatest()
    local text = trim(getSystemClipboard())
    if text == "" then text = clip_history and clip_history[1] or "" end
    if text and text ~= "" then self:_pasteText(text) end
end

----------------------------------------------------------------------
-- Display / refresh
----------------------------------------------------------------------
function Keyboard:_displayText()
    if self.value == "" then
        return self.placeholder or _("Search apps"), true
    end
    local shown
    if self.secure then
        shown = string.rep("•", charCount(self.value))
    else
        shown = (self.value:gsub("[\r\n]+", " "))
    end
    local max_chars = math.max(8, math.floor((self.display_width - 2 * self.display_pad) / (self.display_font * 0.58)) - 1)
    if charCount(shown) > max_chars then shown = "…" .. utf8Tail(shown, max_chars - 1) end
    return shown .. "|", false
end

function Keyboard:_topRegion()
    return Geom:new{ x = self.dimen.x, y = self.dimen.y, w = self.dimen.w, h = self.top_h }
end

function Keyboard:_refresh(mode, region)
    if not self._shown or not region then return end
    local r = region:copy()
    UIManager:setDirty(self, function() return mode, r end)
end

-- refresh_mode: nil = minimal "fast" refresh, "ui" = whole keyboard.
function Keyboard:_update(refresh_mode)
    local text, is_placeholder = self:_displayText()
    self.display:setText(text)
    self.display.fgcolor = is_placeholder and theme.hint or theme.key_text

    local alpha_mode = self.mode == "letters" or self.mode == "symbols1" or self.mode == "symbols2"
    if self.suggestion_keys and #self.suggestion_keys > 0 and alpha_mode then
        local labels = self:_stripLabels()
        self.strip_labels = labels
        for slot, key in ipairs(self.suggestion_keys) do key:setLabel(labels[slot] or "") end
    end

    local state = self.caps_lock and 2 or (self.shift and 1 or 0)
    local upper = state > 0
    local relabel = self._case_state ~= upper
    if relabel then
        for _i, item in ipairs(self.letter_keys) do
            item.key:setLabel(upper and item.upper or item.lower)
        end
        self._case_state = upper
    end
    local shift_changed = self._shift_state ~= state
    if shift_changed then
        self._shift_state = state
        if self.shift_key then
            self.shift_key:setLabel(state == 2 and "⇧⇧" or "⇧")
            self.shift_key:setActive(state > 0)
        end
    end

    if refresh_mode then
        self:_refresh(refresh_mode, self.dimen)
    elseif relabel and self.mode == "letters" then
        self:_refresh("fast", self.dimen)
    else
        self:_refresh("fast", self:_topRegion())
        if shift_changed and self.mode == "letters" and self.shift_key and self.shift_key.dimen.x then
            self:_refresh("fast", self.shift_key.dimen)
        end
    end
    if relabel or shift_changed or refresh_mode then self._cache_valid = false end
    if self.on_change and self._ready then
        UIManager:unschedule(self._emit_change)
        UIManager:scheduleIn(0.4, self._emit_change)
    end
end

-- The static part of the keyboard (all keys) is rendered once into a cache
-- and blitted afterwards; per keystroke only the top bar and suggestion strip
-- are painted again. This removes most of the per-tap CPU cost.
function Keyboard:paintTo(bb, x, y)
    self._shown = true
    local d = self.dimen
    local cache = self._cache
    local bb_type = bb:getType()
    if cache and self._cache_valid and self._cache_type == bb_type
        and cache:getWidth() == d.w and cache:getHeight() == d.h then
        bb:blitFrom(cache, d.x, d.y, 0, 0, d.w, d.h)
        local tx = d.x + self.border + self.pad
        local ty = d.y + self.border + self.pad + (self.title_widget and (self.title_widget:getSize().h + self.gap) or 0)
        pcall(function() self.top_bar:paintTo(bb, tx, ty) end)
        if self.alpha_strip and (self.mode == "letters" or self.mode == "symbols1" or self.mode == "symbols2") then
            pcall(function() self.alpha_strip:paintTo(bb, tx, ty + self.bar_h + self.gap) end)
        end
        pcall(self._paintTrail, self, bb)
        return
    end
    if not pcall(InputContainer.paintTo, self, bb, d.x, d.y) then
        -- Never let a text-rendering error kill KOReader: blank the free-form
        -- texts and paint once more.
        pcall(function() self.display:setText(" ") end)
        if self.title_widget then pcall(function() self.title_widget:setText(" ") end) end
        pcall(InputContainer.paintTo, self, bb, d.x, d.y)
    end
    pcall(function()
        if not cache or self._cache_type ~= bb_type or cache:getWidth() ~= d.w or cache:getHeight() ~= d.h then
            if cache then cache:free() end
            cache = Blitbuffer.new(d.w, d.h, bb_type)
            self._cache = cache
            self._cache_type = bb_type
        end
        cache:blitFrom(bb, 0, 0, d.x, d.y, d.w, d.h)
        self._cache_valid = true
    end)
    -- Drawn after the cache snapshot so the trail never ends up in the cache.
    pcall(self._paintTrail, self, bb)
end

function Keyboard:_requestCancel()
    if self._cancel_requested then return true end
    self._cancel_requested = true
    -- Cancel can be tapped from inside this widget. Defer its callback so
    -- UIManager does not destroy the keyboard while it is dispatching a key.
    UIManager:nextTick(function()
        if self.on_cancel then
            self.on_cancel()
        else
            UIManager:close(self)
        end
    end)
    return true
end
function Keyboard:onClose()
    return self:_requestCancel()
end

function Keyboard.open(options)
    local keyboard = Keyboard:new(options or {})
    UIManager:show(keyboard)
    return keyboard
end

-- The DApp manager calls this when the Settings choice changes. Existing
-- keyboards keep their active input uninterrupted; every newly opened one
-- immediately uses the selected dictionary.
function Keyboard.setLanguage(language)
    configured_language = normalizeLanguage(language)
    return configured_language
end

-- Theme support was removed: the keyboard is always black and white.
-- These stubs only keep older callers (setTheme/setPalette) from failing.
function Keyboard.setTheme() return theme end
function Keyboard.setPalette() return theme end
function Keyboard.ensurePalette() end

function Keyboard.getLanguage()
    return configured_language
end

function Keyboard.setEnabled(enabled)
    keyboard_enabled = enabled ~= false
    return keyboard_enabled
end

function Keyboard.isEnabled()
    return keyboard_enabled
end

-- The native dialog is only a compatibility object now. It is closed before
-- the AppDock keyboard is shown, so the typed value can be mirrored directly
-- into the owning surface without a second KOReader input field.
function Keyboard.attach(dialog, options)
    options = options or {}
    if type(dialog) ~= "table" or type(dialog.getInputText) ~= "function" or type(dialog.setInputText) ~= "function" then
        return false
    end
    if not keyboard_enabled then
        dialog.appdock_keyboard_options = options
        return false
    end
    if dialog.appdock_keyboard_attached then return true end
    local input_widget = dialog._input_widget
    if type(input_widget) ~= "table" then return false end

    local active_keyboard
    local function findButtonCallback(kind)
        for _i, row in ipairs(dialog.buttons or {}) do
            for _j, button in ipairs(row or {}) do
                local text = tostring(button.text or ""):lower()
                if kind == "submit" and button.is_enter_default then return button.callback end
                if kind == "cancel" and (text == _("Cancel"):lower() or text == _("Abbrechen"):lower()) then return button.callback end
            end
        end
    end
    local function closeKeyboard()
        local keyboard = active_keyboard
        active_keyboard = nil
        if keyboard then UIManager:close(keyboard) end
    end
    -- The native dialog may already be closed; never let it take KOReader down.
    local function safeSetText(value)
        pcall(function() dialog:setInputText(value) end)
    end
    local function showKeyboard()
        if active_keyboard then return true end
        -- The AppDock dialog is already removed before the keyboard appears.
        -- Remember that state so Cancel does not close the same widget twice.
        local dialog_was_closed = dialog._closed == true
        local okv, initial_value = pcall(function() return dialog:getInputText() end)
        if not okv or type(initial_value) ~= "string" then initial_value = "" end
        -- Build the keyboard first: if that fails the dialog stays untouched.
        local ok, keyboard = pcall(Keyboard.new, Keyboard, {
            value = initial_value,
            title = options.title or dialog.title,
            placeholder = options.placeholder or dialog.input_hint,
            numeric_only = options.numeric_only or dialog.input_type == "number",
            secure = options.secure or false,
            multiline = options.multiline == true,
            suggestions = options.suggestions,
            language = options.language,
            caps_lock = options.caps_lock == true,
            swipe = options.swipe,
            on_change = function(value)
                safeSetText(value)
                if options.on_change then pcall(options.on_change, value) end
            end,
            on_cancel = function()
                local callback = findButtonCallback("cancel")
                closeKeyboard()
                -- Native KOReader dialogs still need their callback; AppDock's
                -- modal marks itself closed during the first close and must
                -- not receive a second UIManager:close call.
                if callback and not dialog_was_closed and dialog._closed ~= true then
                    pcall(callback)
                end
            end,
            on_submit = function(value)
                safeSetText(value)
                if options.on_change then pcall(options.on_change, value) end
                closeKeyboard()
                local callback = findButtonCallback("submit")
                if callback then callback() end
            end,
        })
        if not ok or not keyboard then
            pcall(function() require("logger").warn("AppDock keyboard failed:", keyboard) end)
            return false
        end
        if not dialog_was_closed then UIManager:close(dialog) end
        active_keyboard = keyboard
        UIManager:show(keyboard)
        return true
    end

    dialog.onShowKeyboard = showKeyboard
    input_widget.onShowKeyboard = showKeyboard
    input_widget.onTapTextBox = function() return showKeyboard() end
    dialog.appdock_keyboard_attached = true
    return true
end

-- UIManager has already started closing this widget when this hook runs.
-- Never call UIManager:close() from here again: it re-enters the widget
-- lifecycle and can leave KOReader's render mutex pointing at destroyed UI.
function Keyboard:onCloseWidget()
    self._shown = false
    self._swipe, self._trail, self._trail_active, self.swipe_result = nil, nil, false, nil
    if self._emit_change then UIManager:unschedule(self._emit_change) end
    if self._cache then
        pcall(function() self._cache:free() end)
        self._cache = nil
    end
    if self._double_tap_changed and Device.input then
        Device.input.disable_double_tap = self._saved_double_tap
        self._double_tap_changed = false
    end
    flushPersisted()
    return true
end

Keyboard._test = {
    normalizeLanguage = normalizeLanguage,
    resolvedLanguage = resolvedLanguage,
    trailingWord = trailingWord,
    removeLastWord = removeLastWord,
    lowerUtf8 = lowerUtf8,
}

return Keyboard
