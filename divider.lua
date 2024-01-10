--------------------------------------------------------------------------------
-- Usage:
--
-- Automatically inserts a line divider line before running certain commands.
-- The line is intended to make it easier to see where output from certain
-- commands begins and ends (for example, commpilers and build tools).
--
-- The "divider_line.commands" setting is a list of command names, separated by
-- spaces, which should display a divider line.
--
-- The "color.divider_line" and "color.divider_line_text" settings specify the
-- colors for the beginning divider line.  The "color.divider_line_end" setting
-- specifies the color for the ending divider lines.
--
-- Example setting usage:
--
--      Run "clink set divider_line.commands" to see the current command list.
--
--      Run "clink set divider_line.commands nmake msbuild dir findstr" to set
--      the command list to show a divider line for "nmake", "msbuild", "dir",
--      and "findstr" commands.
--
-- You can get fancy and do additional configuration via a Lua script.
-- E.g. override the top and bottom line characters, and some other things.
--
-- For example:
--
--      divider_line = divider_line or {}
--      divider_line.left_justify_top = true
--      divider_line.top_line_color = "38;5;25"
--      divider_line.top_line_hilite_color = "38;5;159"
--      divider_line.top_line_lolite_color = "38;5;39"
--      divider_line.top_line_char = "▁"
--      divider_line.bottom_line_char = "▔"
--      divider_line.bottom_line_hilite_color = "38;5;38"
--      divider_line.bottom_line_reverse_video = false
--
-- Produces:
--
--      █COMMAND in DIR at TIME█▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁
--      ...output...
--      ...output...
--      ...output...
--      ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔█took ELAPSED█
--
--------------------------------------------------------------------------------

if not clink.onbeginedit or not clink.onendedit or not console.cellcount then
    print('divider.lua requires a newer version of Clink; please upgrade.')
    return
end

settings.add(
    "color.divider_line",
    "sgr 30;48;5;25",
    "Color for command divider line")

settings.add(
    "color.divider_line_text",
    "",
    "Color for command divider line text",
    "When the color is blank, color.divider_line is used for the divider line text.")

settings.add(
    "color.divider_line_end",
    "sgr 38;5;25",
    "Color for command end divider line",
    "When the color is blank, the end line is omitted.")

settings.add(
    "divider_line.commands",
    "make nmake msbuild",
    "Show divider line before some commands",
    "This is a list of command names, separated by spaces.  When any of these\n"..
    "commands is entered, a divider line is displayed before invoking the\n"..
    "command, and another elapsed time line is displayed after the command\n"..
    "finishes.")

-- luacheck: globals divider_line
-- luacheck: globals flexprompt

divider_line = divider_line or {}

local function is_divider_command(line)
    if line then
        local s = string.explode(line)[1]
        local l = clink.lower(s)
        local commands = string.explode(clink.lower(settings.get("divider_line.commands")))
        for _,c in pairs(commands) do
            if c == l then
                return s
            end
        end
    end
end

local div_prompt = clink.promptfilter(999)
local div_begin

local function make_divider_begin(line, transient)
    local command = is_divider_command(line)
    if command then
        local line_color = "\x1b[0;" .. settings.get("color.divider_line") .. "m"
        local text_color = settings.get("color.divider_line_text")
        if not text_color or text_color == "" then
            text_color = line_color
        else
            text_color = "\x1b[0;" .. text_color .. "m"
        end

        local hilite = "\x1b[" .. (divider_line.top_line_hilite_color or "1;97") .. "m"
        local lolite = "\x1b[" .. (divider_line.top_line_lolite_color or "38;5;252") .. "m"
        local top_char = divider_line.top_line_char or "-"
        local nbsp = " "
        local div = string.format("%s%s%s in %s%s%s at %s%s",
                                  hilite, clink.upper(command), text_color,
                                  lolite, os.getcwd(), text_color,
                                  os.date(), text_color)
        if divider_line.left_justify_top then
            local cellcount = console.cellcount(div) + 2   -- spc + text + spc
            if cellcount >= console.getwidth() then
                div = text_color .. nbsp .. div .. nbsp
            else
                div = text_color .. nbsp .. div .. " " .. line_color
            end
        else
            local bar = string.rep(top_char, 4)
            div = line_color .. bar .. text_color .. " " .. div .. " " .. line_color .. bar
        end
        div = div .. string.rep(top_char, console.getwidth() - 1 - console.cellcount(div)) .. "\x1b[m\n"
        if transient and flexprompt and flexprompt.get_spacing and flexprompt.get_spacing() == "sparse" then
            div = "\n" .. div
        end
        return div
    end
end

local function maybe_print_divider_end()
    if not div_begin then
        return
    end

    local line_color = settings.get("color.divider_line_end")
    if not line_color or line_color == "" then
        return
    end
    line_color = "\x1b[0;" .. line_color .. "m"

    local duration = os.clock() - div_begin
    div_begin = nil

    local h, m, s
    local t = math.floor(duration * 10) % 10
    duration = math.floor(duration)
    s = (duration % 60)
    duration = math.floor(duration / 60)
    if duration > 0 then
        m = (duration % 60)
        duration = math.floor(duration / 60)
        if duration > 0 then
            h = duration
        end
    end

    local text
    text = s .. "." .. t .. "s"
    if m then
        text = m .. "m " .. text
        if h then
            text = h .. "h " .. text
        end
    end

    text = " took " .. text
    if divider_line.bottom_line_hilite_color then
        text = "\x1b[" .. divider_line.bottom_line_hilite_color .. "m" .. text
    elseif divider_line.bottom_line_reverse_video then
        text = "\x1b[7m" .. text
    end
    if divider_line.bottom_line_reverse_video then
        text = text .. " " -- A non-space invisible character.
    end

    local bottom_char = divider_line.bottom_line_char or "-"
    text = line_color .. string.rep(bottom_char, console.getwidth() - 1 - console.cellcount(text)) .. text .. "\x1b[m"
    clink.print(text)
end

local inited_beginedit
local div_can_divide = true

function div_prompt:filter(prompt) -- luacheck: no unused
    if not inited_beginedit then
        -- Defer adding the event handler for printing the divider end line to
        -- make sure it's printed AFTER flexprompt applies its 'spacing' mode.
        clink.onbeginedit(function ()
            maybe_print_divider_end()
            div_can_divide = true
        end)
        inited_beginedit= true
    end

    maybe_print_divider_end()
end

function div_prompt:transientfilter(prompt) -- luacheck: no unused
    local line = rl_state and rl_state.line_buffer
    local div = make_divider_begin(line, true)
    if div then
        div_can_divide = false
        return div .. prompt
    end
end

clink.onendedit(function (line)
    if is_divider_command(line) then
        div_begin = os.clock()
        if div_can_divide then
            local div = make_divider_begin(line)
            if div then
                clink.print(div, NONL) -- luacheck: globals NONL
            end
        end
    else
        div_begin = nil
    end
end)

