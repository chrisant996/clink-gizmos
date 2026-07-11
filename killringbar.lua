--------------------------------------------------------------------------------
-- This script optionally prints a bar above the prompt, containing the
-- kill-ring text items.
--
-- To enable the kill-ring bar, run:
--
--      clink set killringbar.enable true
--
-- This script also adds two bindable commands:
--
--      luafunc:clink_popup_yank
--          Yank the selected kill-ring text from a searchable list.
--          The default key binding is Ctrl-X,Ctrl-Y unless already bound.
--
--      luafunc:clink_dump_kill_ring
--          Print the text in the kill-ring.
--          The default key binding is Ctrl-X,Ctrl-Alt-Y unless already bound.

if not rl or not rl.getkillringstring then
    log.info("killringbar.lua requires a newer version of Clink; please upgrade.")
    return
end

--------------------------------------------------------------------------------
-- Settings.

settings.add("killringbar.enable", false, "Show the kill-ring text above the prompt")
settings.add("killringbar.unicode_symbols", true, "Use Unicode symbols for control codes")

--------------------------------------------------------------------------------
-- Constants.

--local clreol = "\x1b[K"
local norm = "\x1b[m"
local bold = "\x1b[97m"
local cyan = "\x1b[36m"
local bg_color = "\x1b[49m"
local def_color = "\x1b[38;5;246m"
local gray_color = "\x1b[38;5;240m"
--local reverse = "\x1b[7m"
--local noreverse = "\x1b[27m"
local name_color = gray_color
local tag_color = def_color
local sep = ":"
local ellipsis = gray_color..unicode.char(0x2026)..def_color

--------------------------------------------------------------------------------
-- Internal state.

local last_index
local last_strings = {}
local unicode_symbols

--------------------------------------------------------------------------------
-- Helper functions.

local function make_text(entry)
    local i = gray_color..entry[1]..sep..def_color
    local t = tag_color..console.ellipsify(entry[2], 16, "right", ellipsis)..def_color
    return i..t
end

local function normalize(text, gray, def)
    gray = gray or gray_color
    def = def or def_color

    local out = {}
    for str, value in unicode.iter(text) do
        if value >= 0x00 and value < 0x20 then
            if unicode_symbols then
                table.insert(out, gray..unicode.char(0x2400 + value)..def)
            else
                table.insert(out, gray.."^"..string.char(64 + value)..def)
            end
        elseif value == 0x20 and unicode_symbols then
            table.insert(out, gray..unicode.char(0x2423)..def)
        elseif value == 0x7F then
            if unicode_symbols then
                table.insert(out, gray..unicode.char(0x2421)..def)
            else
                table.insert(out, gray.."^?"..def)
            end
        else
            table.insert(out, str)
        end
    end
    return table.concat(out)
end

local function make_bar()
    local ring = {}
    local cols = 0

    local count = rl.getkillringcount()
    for i = 1, count do
        local x = tostring(i)
        local s = rl.getkillringstring(i) or ""
        local n = normalize(s)
        local entry = { x, n }
        cols = cols + console.cellcount(x) + 1 + console.cellcount(n)
        table.insert(ring, entry)
    end

    local width = console.getwidth()
    local pieces = { name_color.."(kill-ring)"..def_color }
    local current = rl.getkillringindex()
    cols = console.cellcount(pieces[1])
    for i = 1, count, 1 do
        local index = (((current - 1) + count - (i - 1)) % count) + 1
        local entry = ring[index]
        local text = make_text(entry)
        local prefix = (cols > 0) and "  " or ""
        local cells = console.cellcount(prefix) + console.cellcount(text)
        local and_more = (i < count) and name_color..string.format("(and %u more)", count - (i - 1))..def_color
        local and_more_cells = and_more and console.cellcount(prefix..and_more) or 0
        if cols + cells >= width - and_more_cells then
            if and_more and and_more_cells < width then
                cols = cols + and_more_cells
                table.insert(pieces, prefix..and_more)
            end
            break
        end
        cols = cols + cells
        table.insert(pieces, prefix..text)
    end

    local text = ""
    if pieces[2] then
        local padding = string.rep(" ", width - 1 - cols)
        text = table.concat(pieces)
        assert(cols == console.cellcount(text))
        text = bg_color..def_color..text..padding..norm.."\n"
    end
    return text
end

--------------------------------------------------------------------------------
-- Prompt filter (shows the kill-ring bar).

local pf = clink.promptfilter(24)

function pf:filter(prompt) -- luacheck: no unused
    if settings.get("killringbar.enable") then
        last_index = rl.getkillringindex()
        last_strings = rl.getkillringstrings()
        return make_bar()..prompt
    end
end

--------------------------------------------------------------------------------
-- OnAfterCommand event (refreshes the kill-ring bar).

clink.onaftercommand(function()
    local kri = rl.getkillringindex()
    local krs = rl.getkillringstrings()
    local changed = (last_index ~= kri) or (#last_strings ~= #krs)
    if not changed then
        for i = #krs, 1, -1 do
            if last_strings[i] ~= krs[i] then
                changed = true
                break
            end
        end
    end
    if changed then
        last_strings = krs
        clink.refilterprompt()
    end
end)

--------------------------------------------------------------------------------
-- OnBeginEdit event (resets internal state).

clink.onbeginedit(function()
    last_index = nil
    last_strings = {}
    unicode_symbols = settings.get("killringbar.unicode_symbols")
end)

--------------------------------------------------------------------------------
-- Bindable commands.

if rl.describemacro then
    rl.describemacro("luafunc:clink_dump_kill_ring", "Print the text in the kill-ring")
    rl.describemacro("luafunc:clink_popup_yank", "Yank the selected kill-ring text from a searchable list")
end

local maybe_bind = {
    { [["\C-x\e\C-y]],      [["luafunc:clink_dump_kill_ring"]] },
    { [["\C-x\C-y"]],       [["luafunc:clink_popup_yank"]] },
    { [["\e[27;8;89~"]],    [["luafunc:clink_popup_yank"]] },
}

if rl.setbinding then
    for _, b in ipairs(maybe_bind) do
        if not rl.getbinding(b[1]) then
            rl.setbinding(b[1], b[2])
        end
    end
end

function clink_dump_kill_ring(rl_buffer) -- luacheck: no global
    rl_buffer:beginoutput()

    local kri = rl.getkillringindex()
    local krs = rl.getkillringstrings()

    for i = #krs, 1, -1 do
        local selected = norm
        local marker = ":"
        local num = string.format("%2u", i)
        if i == kri then
            selected = norm..bold
            marker = ">"
            num = cyan..num..gray_color
        else
            num = gray_color..num
        end
        local s = normalize(krs[i], nil, selected)
        clink.print(num..marker..selected..s..norm)
    end
end

function clink_popup_yank(rl_buffer) -- luacheck: no global
    local krc = rl.getkillringcount()
    local kri = rl.getkillringindex()
    local krs = rl.getkillringstrings()

    local items = {}
    for i = #krs, 1, -1 do
        local s = console.plaintext(normalize(krs[i]))
        local desc = string.format("%4s\t", string.format("(%u)", i))
        table.insert(items, { value=tostring(i), display=s, description=desc })
    end

    local initial_index = krc + 1 - kri
    local selected, shifted, index = clink.popuplist("Yank From Kill-Ring", items, initial_index) -- luacheck: no unused

    if selected then
        selected = tonumber(selected)
        rl_buffer:beginundogroup()
        rl.invokecommand("yank")
        for _ = (krc + kri - selected) % krc, 1, -1 do
            rl.invokecommand("yank-pop")
        end
        rl_buffer:endundogroup()
    end
end
