--------------------------------------------------------------------------------
-- This script automatically inserts a line divider line before running certain
-- commands.  The line is intended to make it easier to see where output from
-- certain commands begins and ends (for example, commpilers and build tools).
--
--
--TODO: document new behaviors.
--
--
-- Settings:
--
--      The "divider_line.commands" setting is a list of command names,
--      separated by spaces, which should display a divider line.
--
--      The "color.divider_line" and "color.divider_line_text" settings specify
--      the colors for the beginning divider line.  The "color.divider_line_end"
--      setting specifies the color for the ending divider lines.
--
--
--TODO: document new settings.
--
--
-- Example setting usage:
--
--      Run "clink set divider_line.commands" to see the current command list.
--
--      Run "clink set divider_line.commands nmake msbuild dir findstr" to set
--      the command list to show a divider line for "nmake", "msbuild", "dir",
--      and "findstr" commands.
--
-- Advanced configuration:
--
--      You can get fancy and do additional configuration via a Lua script.
--      E.g. override the top and bottom line characters, and some other things.
--
--      Example:
--
--          divider_line = divider_line or {}
--          divider_line.left_justify_top = true
--          divider_line.top_line_hilite_color = "38;5;159"
--          divider_line.top_line_lolite_color = "38;5;39"
--          divider_line.top_line_char = "▁"
--          divider_line.bottom_line_char = "▔"
--          divider_line.bottom_line_hilite_color = "38;5;38"
--          divider_line.bottom_line_reverse_video = false
--
--      Produces:
--
--          █COMMAND in DIR at TIME█▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁
--          ...output...
--          ...output...
--          ...output...
--          ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔█took ELAPSED█
--
--------------------------------------------------------------------------------

if not clink.onbeginedit or not clink.onendedit or not console.cellcount then
    print('divider.lua requires a newer version of Clink; please upgrade.')
    return
end

local settings_list = {
    ["divider_line.commands"] =
        {
            default = "make nmake msbuild",
            shortdesc = "Show divider line before some commands",
            longdesc =
                "This is a list of command names, separated by spaces.  When any of these\n"..
                "commands is entered, a divider line is displayed before invoking the\n"..
                "command, and another elapsed time line is displayed after the command\n"..
                "finishes.",
        },
    ["divider_line.use_ascii"] =
        {
            default = false,
            shortdesc = "Uses ASCII characters for lines",
            longdesc =
                "When this is false, Unicode line drawing characters may be used.",
        },
    ["color.divider_line"] =
        {
            default = "sgr 30;48;5;25",
            shortdesc = "Color for command divider line",
        },
    ["color.divider_line_text"] =
        {
            default = "",
            shortdesc = "Color for command divider line text",
            longdesc =
                "When the color is blank, color.divider_line is used for the divider line text.",
        },
    ["color.divider_line_end"] =
        {
            default = "sgr 38;5;25",
            shortdesc = "Color for command end divider line",
            longdesc =
                "When the color is blank, the end line is omitted.",
        },
    ["color.divider_line_end_text"] =
        {
            default = "",
            shortdesc = "Color for duration in command end divider line",
            longdesc =
                "When the color is blank, color.divider_line is used for the duration text.",
        },
    ["color.transient_divider_line"] =
        {
            default = "38;5;240",
            shortdesc = "Color for transient divider line",
            longdesc =
                "When a command duration exceeds divider_line.min_duration seconds but the\n"..
                "command was not in divider_line.commands, then the transient prompt shows\n"..
                "a divider line with the duration so it stays visible for old commands.\n"..
                "When this color is blank, the transient divider line is omitted.",
        },
    ["color.transient_divider_text"] =
        {
            default = "38;5;214",
            shortdesc = "Color for duration text in transient line",
            longdesc =
                "This is the color for the duration text in the transient divider line.",
        },
    ["divider_line.transient_duration"] =
        {
            default = 3,
            shortdesc = "Minimum duration for transient divider line",
        },
    ["divider_line.transient_mode"] =
        {
            default = {"off","duration","always"},
            shortdesc = "Controls when to show transient divider line",
            longdesc =
                "Optionally, divider line can shown before a transient prompt, if transient\n"..
                "prompts are enabled (by the prompt.transient setting).\n"..
                "When this is 'off' then no transient divider line is shown.\n"..
                "When this is 'duration' then a transient divider line is shown when the\n"..
                "duration of the preceding command exceeds divider_line.transient_duration,\n"..
                "and the divider line includes the duration.\n"..
                "When this is 'always' then a transient divider line is shown unless the\n"..
                "command line was empty.  If the duration exceeds divider.transient_duration,\n"..
                "the divider line includes the duration.",
        },
}

for name,info in pairs(settings_list) do
    if info.longdesc then
        settings.add(name, info.default, info.shortdesc, info.longdesc)
    else
        settings.add(name, info.default, info.shortdesc)
    end
end

-- luacheck: globals divider_line
-- luacheck: globals flexprompt

divider_line = divider_line or {}

local function sgr(code)
    if not code then
        return "\x1b[m"
    elseif string.byte(code) == 0x1b then
        return code
    else
        return "\x1b["..code.."m"
    end
end

local function get_setting(name)
    local fullname = "divider_line." .. name
    local value = settings.get(fullname)
    local dflt = settings_list[fullname].default
    dflt = (type(dflt) == "table" and dflt[1]) or dflt
    if value ~= dflt then
        return value
    elseif divider_line[name] ~= nil then
        return divider_line[name]
    else
        return value
    end
end

local function get_color(name)
    local fullname = "color." .. name
    local value = settings.get(fullname)
    local descr = settings.get(fullname, true)
    local deflt = settings_list[fullname].default
    if descr ~= deflt then
        return value
    elseif divider_line["color_" .. name] ~= nil then
        return divider_line["color_" .. name]
    else
        return value
    end
end

local function isnilorempty(s)
    return s == nil or s == ""
end

local function can_use_lines()
    if get_setting("use_ascii") then
        return false
    elseif flexprompt and flexprompt.get_charset and flexprompt.get_charset() ~= "unicode" then
        return false
    else
        return true
    end
end

local function can_use_fancy_line()
    if not divider_line.no_fancy_line then
        return can_use_lines()
    end
end

local function is_divider_command(line)
    if line then
        if clink.parseline then
            local divider_line_commands = {}
            for _,c in ipairs(string.explode(clink.lower(get_setting("commands")))) do
                divider_line_commands[clink.lower(c)] = c
            end
            local commands = clink.parseline(line)
            for _,c in ipairs(commands) do
                local ls = c.line_state
                for i = 1, ls:getwordcount() do
                    local w = path.getbasename(ls:getword(i))
                    local x = divider_line_commands[clink.lower(w)]
                    if x then
                        return x
                    end
                end
            end
        else
            local s = string.explode(line)[1]
            local l = clink.lower(s)
            local commands = string.explode(clink.lower(get_setting("commands")))
            for _,c in pairs(commands) do
                if c == l then
                    return s
                end
            end
        end
    end
end

local pf = clink.promptfilter(999)

local nbsp = " "                      -- A non-space invisible character.

local div_begin
local div_mode_command
local div_mode_transient

local transient_duration
local transient_line_color
local transient_duration_color

local function get_command_duration(begin_time)
    if begin_time then
        local duration = os.clock() - begin_time

        local h, m, s
        local t = math.floor(duration * 10) % 10
        duration = math.floor(duration)
        s = (duration % 60)
        duration = math.floor(duration / 60)
        if duration > 0 then
            t = nil -- Don't show tenths of seconds if duration exceeds 60 sec.
            m = (duration % 60)
            duration = math.floor(duration / 60)
            if duration > 0 then
                h = duration
            end
        end

        local text = s
        if t then
            text = text .. "." .. t
        end
        text = text .. "s"
        if m then
            text = m .. "m " .. text
            if h then
                text = h .. "h " .. text
            end
        end

        return text
    end
end

local function make_divider_begin(line, transient)
    local command = is_divider_command(line)
    if command then
        local line_color = sgr("0;" .. get_color("divider_line"))
        local text_color = get_color("divider_line_text")
        if not text_color or text_color == "" then
            text_color = line_color
        else
            text_color = sgr("0;" .. text_color)
        end

        local hilite = sgr(divider_line.top_line_hilite_color or "1;97")
        local lolite = sgr(divider_line.top_line_lolite_color or "38;5;252")
        local top_char = divider_line.top_line_char or "-"
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
        local max_width = console.getwidth() - (divider_line.align_right and 0 or 1)
        div = div .. string.rep(top_char, max_width - console.cellcount(div)) .. sgr() .. "\n"
        if transient and flexprompt and flexprompt.get_spacing and flexprompt.get_spacing() == "sparse" then
            div = "\n" .. div
        end
        return div
    end
end

local function maybe_print_divider_end()
    local begin_time
    if div_mode_command then
        begin_time = div_begin
        div_mode_command = nil
    end
    if not begin_time then
        return
    end

    local line_color = get_color("divider_line_end")
    if not line_color or line_color == "" then
        return
    end
    line_color = sgr("0;" .. line_color)

    local text = get_command_duration(begin_time)
    local max_width = console.getwidth() - (divider_line.align_right and 0 or 1)
    local dur_color = get_color("divider_line_end_text")
    local bottom_char = (divider_line.bottom_line_char or
                         (can_use_lines() and "─" or "-"))

    if not divider_line.bottom_line_reverse_video then
        if dur_color and dur_color ~= "" then
            text = sgr(dur_color) .. text
        end
    end

    text = " " .. text
    if not divider_line.no_took then
        text = " took" .. text
    end

    if divider_line.bottom_line_reverse_video then
        text = sgr("7") .. text
        text = text .. nbsp
    end

    text = line_color .. string.rep(bottom_char, max_width - console.cellcount(text)) .. text .. sgr()
    clink.print(text)
end

-- Divider line for commands:  This involves a header (divider line before the
-- command), and a footer (divider line after the command).

local inited_beginedit
local div_can_divide = true

local function filter_div_prompt()
    if not inited_beginedit then
        -- Defer adding the event handler for printing the divider end line to
        -- make sure it's printed AFTER flexprompt applies its 'spacing' mode.
        clink.onbeginedit(function ()
            maybe_print_divider_end()
            div_can_divide = true
        end)
        inited_beginedit = true
    end

    maybe_print_divider_end()
end

local function transientfilter_div_prompt(prompt)
    local line = rl_state and rl_state.line_buffer
    local div = make_divider_begin(line, true)
    if div then
        div_can_divide = false
        return div .. prompt
    end
end

local function onendedit_div_prompt(line)
    if is_divider_command(line) then
        div_mode_command = true
        if isnilorempty(get_color("divider_line_end")) then
            div_mode_transient = true
        end
        if div_can_divide then
            local div = make_divider_begin(line)
            if div then
                clink.print(div, NONL) -- luacheck: globals NONL
            end
        end
    end
end

-- Transient divider line:  This uses left + right transient prompts to show
-- duration of old commands even after the normal prompt (with duration) has
-- been replaced by a transient prompt (which generally doesn't show duration).

local _transient_duration

local function transientfilter_transient_line_prompt(prompt)
    _transient_duration = nil
    if div_mode_transient then
        _transient_duration = transient_duration
        div_mode_transient = nil
    end
    if _transient_duration then
        local line
        local max_width = console.getwidth() - (divider_line.align_right and 0 or 1)
        transient_line_color = sgr(get_color("transient_divider_line"))
        transient_duration_color = sgr(get_color("transient_divider_text"))

        local c = can_use_lines() and "─" or "_"
        local s = _transient_duration
        if s ~= "" then
            s = " "..sgr(transient_duration_color)..s..sgr()
            if not divider_line.no_took then
                s = " took"..s
            end
            _transient_duration = s
        end

        line = string.rep(c, max_width - console.cellcount(s))..s
        local prologue = sgr(transient_line_color)..line..sgr().."\n"
        return prologue..prompt
    end
end

local function transientrightfilter_transient_line_prompt()
    if _transient_duration and _transient_duration ~= "" and div_can_divide then
        if can_use_fancy_line() then
            local width = console.cellcount(_transient_duration)
            local right = string.rep("─", width)..sgr()
            -- Prepend line corners.
            right = "\x1b[A\x1b[D".."╮".."\x1b[B\x1b[D".."╰"..right
            -- Compensate for corners being counted as part of the string width.
            right = string.format("\x1b[%uC"..right, console.cellcount(right) - width)
            -- Handle right alignment.
            if not divider_line.align_right then
                right = right..sgr().." "
            end
            -- Finally prepend the line color.
            right = sgr(transient_line_color)..right
            return right, false
        end
    end
end

local function onendedit_transient_line_prompt(line)
    if not div_mode_command and not div_mode_transient then
        local is_empty = (line:gsub("%s+$", "") == "")
        if not is_empty then
            div_mode_transient = true
        end
    end
    transient_duration = nil
end

clink.onbeginedit(function()
    if div_mode_transient then
        local transient_mode = get_setting("transient_mode")
        if transient_mode and transient_mode ~= "off" then
            local elapsed, dur
            local min_dur = math.max(get_setting("transient_duration"), 0)
            if div_begin then
                elapsed = os.clock() - div_begin
            end
            if elapsed and elapsed >= min_dur then
                dur = get_command_duration(div_begin)
            end
            if not dur and transient_mode == "always" then
                dur = ""
            end
            if dur then
                transient_duration = dur
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- Shared functions.

function pf:filter(prompt) -- luacheck: no unused
    return filter_div_prompt(prompt)
end

function pf:transientfilter(prompt) -- luacheck: no unused
    local p1, ok1 = transientfilter_div_prompt(prompt)
    if p1 then
        prompt = p1
    end
    local p2, ok2 = transientfilter_transient_line_prompt(prompt)
    if p2 then
        prompt = p2
    end
    if p1 or p2 then
        local ok
        if ok1 == false or ok2 == false then
            ok = false
        end
        return prompt, ok
    end
end

function pf:transientrightfilter(prompt) -- luacheck: no unused
    return transientrightfilter_transient_line_prompt(prompt)
end

clink.onendedit(function(line)
    div_begin = os.clock()
    div_mode_command = nil
    div_mode_transient = nil
    onendedit_div_prompt(line)
    onendedit_transient_line_prompt(line)
end)

