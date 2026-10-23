-- AppDock-owned keyboard for AppDock-owned text input surfaces.
-- KOReader dialogs outside AppDock remain untouched.
--
-- GBoard-style layout, tuned for E-Ink:
--   * big keys (row height scales with the screen, ~8% of its height)
--   * QWERTZ / QWERTY, long-press for digits and umlauts/accents
--   * suggestion strip, auto-capitalisation, double-space -> ". "
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

local Screen = Device.screen
local function scale(n) return Screen:scaleBySize(n) end
local function ui(de, en) return ui_is_de and de or en end

-- Colour scheme. AppDock can override any entry with Keyboard.setTheme{...}
-- so the keyboard follows the system design.
local theme = {
    background   = Blitbuffer.COLOR_GRAY_E or Blitbuffer.COLOR_LIGHT_GRAY, -- keyboard panel (light system colour)
    key          = Blitbuffer.COLOR_WHITE,                                  -- normal keys (standard colour)
    key_text     = Blitbuffer.COLOR_BLACK,
    func         = Blitbuffer.COLOR_DARK_GRAY,                              -- shift, backspace, ?123 ... (dark system colour)
    func_text    = Blitbuffer.COLOR_WHITE,
    active       = Blitbuffer.COLOR_BLACK,                                  -- pressed/active toggle (shift, caps, tab)
    active_text  = Blitbuffer.COLOR_WHITE,
    primary      = Blitbuffer.COLOR_BLACK,                                  -- "Fertig"
    primary_text = Blitbuffer.COLOR_WHITE,
    hint         = Blitbuffer.COLOR_DARK_GRAY,
    border       = Blitbuffer.COLOR_BLACK,
}

-- Themes may arrive as Blitbuffer colours, 0-255 grey numbers or "#rrggbb"
-- strings. Anything else is rejected so a bad theme value can never reach
-- the widgets (it surfaced as "bad argument ... shapeLine" while painting).
local DEFAULT_THEME = {}
for name, color in pairs(theme) do DEFAULT_THEME[name] = color end

local function coerceColor(value)
    local t = type(value)
    if t == "cdata" then return value end
    if t == "table" then
        if type(value.getColor8) == "function" or value.a ~= nil or value.alpha ~= nil then return value end
        return nil
    end
    if t == "number" then
        local v = math.max(0, math.min(255, math.floor(value)))
        if Blitbuffer.Color8 then return Blitbuffer.Color8(v) end
        return nil
    end
    if t == "string" then
        local hex = value:match("^#?(%x%x%x%x%x%x)$")
        if hex then
            local r, g, b = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
            if Blitbuffer.ColorRGB32 then return Blitbuffer.ColorRGB32(r, g, b, 0xFF) end
            if Blitbuffer.Color8 then return Blitbuffer.Color8(math.floor(0.299 * r + 0.587 * g + 0.114 * b)) end
        end
    end
    return nil
end

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
    self.text_widget = TextWidget:new{
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
        self.hint_widget = TextWidget:new{
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
        local size = self.hint_widget:getSize()
        self.hint_widget:paintTo(bb, x + self.width - size.w - scale(6), y + scale(3))
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
    suggestions = nil,
    language = nil,
    modal = true,
}

function Keyboard:init()
    Keyboard.ensurePalette(self.appdock)
    ui_is_de = resolvedLanguage("auto") == "de"
    self.width = Screen:getWidth()
    local screen_h = Screen:getHeight()
    self.value = self.value or ""
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
        self.title_widget = TextWidget:new{
            text = self.title,
            face = Font:getFace("smallinfofont", math.floor(self.bar_h * 0.36)),
            fgcolor = theme.key_text,
            bold = true,
            max_width = inner,
        }
    end
    local cancel_w = math.floor(inner * 0.13)
    self.cancel_key = Key:new{
        label = "✕", width = cancel_w, height = self.bar_h, style = "func",
        font_size = math.floor(self.bar_h * 0.42),
        callback = function() self:_requestCancel() end,
    }
    local display_w = inner - cancel_w - self.gap
    self.display_pad = scale(10)
    self.display_font = math.floor(self.bar_h * 0.46)
    self.display_width = display_w
    self.display = TextWidget:new{
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
    self.top_bar = HorizontalGroup:new{
        align = "center",
        self.cancel_key,
        HorizontalSpan:new{ width = self.gap },
        display_frame,
    }
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
                self.letter_keys[#self.letter_keys + 1] = { key = item.key, lower = lower, upper = upper }
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
    local word = self.strip_labels and self.strip_labels[slot]
    if not word or word == "" then return end
    local token = trailingWord(self.value)
    self.value = self.value:sub(1, #self.value - #token) .. word .. " "
    self._prev_space = false
    self:_afterEdit()
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
    text = text:gsub("[\r\n]+", " ")
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
        self.top_bar:paintTo(bb, tx, ty)
        if self.alpha_strip and (self.mode == "letters" or self.mode == "symbols1" or self.mode == "symbols2") then
            self.alpha_strip:paintTo(bb, tx, ty + self.bar_h + self.gap)
        end
        return
    end
    InputContainer.paintTo(self, bb, d.x, d.y)
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

-- Override colours (any subset of: background, key, key_text, func,
-- func_text, active, active_text, primary, primary_text, hint, border).
-- Applies to keyboards opened afterwards.
function Keyboard.setTheme(overrides)
    if type(overrides) == "table" then
        for name, color in pairs(overrides) do
            if theme[name] ~= nil and color ~= nil then
                theme[name] = coerceColor(color) or DEFAULT_THEME[name]
            end
        end
    end
    return theme
end

-- Takes the same palette the file manager uses (Theme.getPalette): background,
-- surface, surface_alt, primary, secondary, on_primary, on_surface, on_variant,
-- outline. The keyboard follows the system design through it.
local palette_applied = false
function Keyboard.setPalette(palette)
    if type(palette) ~= "table" then return theme end
    local function pick(...)
        for _n, name in ipairs({ ... }) do
            local c = coerceColor(palette[name])
            if c then return c end
        end
    end
    local map = {
        background   = pick("surface_alt", "surface_variant", "secondary", "background"),
        key          = pick("surface", "background"),
        key_text     = pick("on_surface"),
        func         = pick("secondary", "surface_variant", "surface_alt"),
        func_text    = pick("on_surface"),
        active       = pick("primary"),
        active_text  = pick("on_primary"),
        primary      = pick("primary"),
        primary_text = pick("on_primary"),
        hint         = pick("on_variant", "on_surface"),
        border       = pick("outline", "on_variant"),
    }
    for name, color in pairs(map) do theme[name] = color end
    palette_applied = true
    return theme
end

-- Fallback when nobody called setPalette: ask appdock_theme directly.
function Keyboard.ensurePalette(appdock)
    if palette_applied then return end
    local ok, Theme = pcall(require, "appdock_theme")
    if ok and type(Theme) == "table" and type(Theme.getPalette) == "function" then
        local ok2, palette = pcall(Theme.getPalette, appdock)
        if ok2 then Keyboard.setPalette(palette) end
    end
end

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
            suggestions = options.suggestions,
            language = options.language,
            caps_lock = options.caps_lock == true,
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
