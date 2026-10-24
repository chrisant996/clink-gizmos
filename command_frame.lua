--------------------------------------------------------------------------------
-- This script automatically inserts divider lines before and after command
-- output.  Various settings allow configuring colors and other details about
-- the appearance.
--
-- The configuration settings are controlled by 'clink set'.
--
-- For example, 'clink set command_frame.enable true' turns on the command
-- frames.
--
--
-- PRIMARY ON/OFF SETTING:
--
--  command_frame.enable
--                  Set to true to enable printing command frame divider lines
--                  before and after command output.
--
--
-- CONFIGURATION SETTINGS:
--
--  command_frame.exit_code_coloring
--                  Set to true to color the bottom divider line based on the
--                  exit code.  Set to false to color it the same as the top.
--
--  command_frame.shape
--                  Set to 'round' for rounded corners, or 'square' for squared
--                  corners, or 'line' for straight divider lines.
--
--  command_frame.use_ascii
--                  Set to true to use only ASCII characters (the minus sign).
--
--  command_frame.auto_remove
--                  Set to true to automatically remove command frame divider
--                  lines when the exit code is 0 and the duration was short or
--                  the amount of output was short.
--                  See the 'command_frame.min_duration' and
--                  'command_frame.min_lines' settings.
--
--  command_frame.show_caption
--                  Include the command in a caption in the top divider line.
--
--  command_frame.show_cwd
--                  Include the current working directory in the top divider
--                  line.
--
--  command_frame.show_time
--                  Include the date and time in the top divider line.
--
--  command_frame.min_duration
--                  Only print the duration in the bottom divider line if it
--                  exceeds this many seconds.
--
--  command_frame.min_lines
--                  When command_frame.auto_remove is true, then the command
--                  frame divider lines may be removed if the command output was
--                  fewer than this many lines.
--
--  command_frame.always_commands
--                  A space-delimited list of commands.  Command frame divider
--                  lines are always printed for any command in this list.
--
--  command_frame.never_commands
--                  A space-delimited list of commands.  Command frame divider
--                  lines are never printed for any command in this list.
--
--
-- COLOR SETTINGS:
--
--  color.command_frame_top
--                  Color for the top divider line.
--
--  color.command_frame_succeeded
--                  Color for the bottom divider line when the exit code is 0
--                  and 'command_frame.exit_code_coloring' is true.
--
--  color.command_frame_failed
--                  Color for the bottom divider line when the exit code is
--                  non-zero and 'command_frame.exit_code_coloring' is true.
--
--  color.command_frame_caption
--                  Color for the command caption when the
--                  'command_frame.show_caption' setting is true.
--
--  color.command_frame_duration
--                  Color for the command duration in the bottom divider line.
--
--------------------------------------------------------------------------------

if not clink.onbeginedit or
        not clink.onendedit or
        not console.cellcount or
        not console.plaintext or
        not os.geterrorlevel or
        not clink.parseline or
        not console.getcursorpos or
        not unicode.char then
    print('command_frame.lua requires a newer version of Clink; please upgrade.')
    return
end

local settings_list = {
    ["command_frame.enable"] =
        {
            default = false,
            shortdesc = "Prints a frame around command output",
            longdesc =
                "When this is true, a frame is printed around command output.\n"..
                "Adjust the behavior by configuring other 'command_frame.*' settings.",
        },
    ["command_frame.exit_code_coloring"] =
        {
            default = true,
            shortdesc = "Color bottom line according to exit code",
            longdesc =
                "When this is false, the bottom line uses 'color.command_frame_top'.\n"..
                "When this is true, the bottom line is colored by the exit code:\n"..
                "Exit code zero uses 'color.command_frame_succeeded'.\n"..
                "Exit code non-zero uses 'color.command_frame_failed'.",
        },
    ["command_frame.shape"] =
        {
            default = { "round", "square", "line" },
            shortdesc = "The corner and line shape",
            longdesc =
                "This chooses the corner and line shape for the divider lines.  This has no"..
                "effect when 'command_frame.use_ascii' is true.",
        },
    ["command_frame.use_ascii"] =
        {
            default = false,
            shortdesc = "Uses ASCII characters for lines",
            longdesc =
                "When this is false, Unicode line drawing characters may be used.",
        },
    ["command_frame.auto_remove"] =
        {
            default = false,
            shortdesc = "Remove divider lines for short commands",
            longdesc =
                "When this is true and command's exit code is 0, then automatically try\n"..
                "to remove the divider lines if there was no output, or if the duration\n"..
                "was less than 'command_frame.min_duration' and the output was shorter than\n"..
                "'command_frame.min_lines' and the command is not in the list from\n"..
                "'command_frame.always_commands'.",
        },
    ["command_frame.show_caption"] =
        {
            default = true,
            shortdesc = "Print the command in the top line",
            longdesc =
                "When this is true, print the command as a caption in the top line.",
        },
    ["command_frame.show_cwd"] =
        {
            default = false,
            shortdesc = "Print the cwd in the top line",
            longdesc =
                "When this is true, print the current working directory in the top line.",
        },
    ["command_frame.show_time"] =
        {
            default = false,
            shortdesc = "Print the date and time in the top line",
            longdesc =
                "When this is true, print the date and time in the top line.",
        },
    ["command_frame.min_duration"] =
        {
            default = 3,
            shortdesc = "Minimum duration to print",
            longdesc =
                "Only print the duration in the bottom line when at least this many seconds.",
        },
    ["command_frame.min_lines"] =
        {
            default = 8,
            shortdesc = "Minimum lines of output",
            longdesc =
                "When 'command_frame.auto_remove' is true, then the frame may be removed if\n"..
                "the output is fewer than this many lines.\n"..
                "See the 'command_frame.auto_remove' setting for details.",
        },
    ["command_frame.always_commands"] =
        {
            default = "",
            shortdesc = "Commands that always add a frame",
            longdesc =
                "When 'command_frame.auto_remove' is true, then the frame may be removed if\n"..
                "the command name is not in this list (delimited by spaces).\n"..
                "See the 'command_frame.auto_remove' setting for details.",
        },
    ["command_frame.never_commands"] =
        {
            default = "",
            shortdesc = "Commands that never add a frame",
            longdesc =
                "When a command name is in this list (delimited by spaces), then a frame is\n"..
                "never printed for the command.",
        },
    ["color.command_frame_top"] =
        {
            default = "sgr 38;5;26",
            shortdesc = "Color for line before a command",
        },
    ["color.command_frame_failed"] =
        {
            default = "sgr 38;5;160",
            shortdesc = "Color for line after a failed command",
            longdesc =
                "When the color is blank, 'color.command_frame_top' is used.",
        },
    ["color.command_frame_succeeded"] =
        {
            default = "sgr 38;5;34",
            shortdesc = "Color for line after a successful command",
            longdesc =
                "When the color is blank, 'color.command_frame_top' is used.",
        },
    ["color.command_frame_caption"] =
        {
            default = "sgr 38;5;252;48;5;237",
            shortdesc = "Color for caption within a divider line",
            longdesc =
                "When the color is blank, the default terminal color is used.",
        },
    ["color.command_frame_duration"] =
        {
            default = "", --"sgr 38;5;172;48;5;237",
            shortdesc = "Color for duration in a divider line",
            longdesc =
                "When the color is blank, the color is based on the command's exit code.",
        },
}

for name,info in pairs(settings_list) do
    if info.longdesc then
        settings.add(name, info.default, info.shortdesc, info.longdesc)
    else
        settings.add(name, info.default, info.shortdesc)
    end
end

-- luacheck: globals flexprompt
-- luacheck: globals NONL

local U = unicode.char

local command_frame = {}
command_frame.shapes = {}
command_frame.shapes.round = {
    top_chars    = { U(0x256d), U(0x2500), U(0x256e) },
    bottom_chars = { U(0x2570), U(0x2500), U(0x256f) },
}
command_frame.shapes.square = {
    top_chars    = { U(0x250c), U(0x2500), U(0x2510) },
    bottom_chars = { U(0x2514), U(0x2500), U(0x2518) },
}
command_frame.shapes.line = {
    top_chars    = { U(0x2500) },
    bottom_chars = { U(0x2500) },
}

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
    local fullname = "command_frame."..name
    local value = settings.get(fullname)
    --[[
    local dflt = settings_list[fullname].default
    dflt = (type(dflt) == "table" and dflt[1]) or dflt
    if value ~= dflt then
        return value
    elseif command_frame[name] ~= nil then
        return command_frame[name]
    end
    --]]
    return value
end

local function get_color(name)
    local fullname = "color."..name
    local value = settings.get(fullname)
    --[[
    local descr = settings.get(fullname, true)
    local deflt = settings_list[fullname].default
    if descr ~= deflt then
        return value
    elseif command_frame["color_"..name] ~= nil then
        return command_frame["color_"..name]
    end
    --]]
    return value
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

local function get_top_chars()
    local shape = get_setting("shape")
    local chars = can_use_lines() and command_frame.shapes[shape].top_chars or { "-" }
    local left_corner = chars[1]
    local line_char = chars[3] and chars[2] or chars[1]
    local right_corner = chars[3] and chars[3] or chars[1]
    return left_corner, line_char, right_corner
end

local function get_bottom_chars()
    local shape = get_setting("shape")
    local chars = can_use_lines() and command_frame.shapes[shape].bottom_chars or { "-" }
    local left_corner = chars[1]
    local line_char = chars[3] and chars[2] or chars[1]
    local right_corner = chars[3] and chars[3] or chars[1]
    return left_corner, line_char, right_corner
end

local div_begin
local prev_begin_divider
local can_auto_remove

local function add_margin(text)
    return isnilorempty(text) and "" or (" "..text.." ")
end

local function trim(text)
    return text:gsub("^%s+", ""):gsub("%s+$", "")
end

local function format_error_level(errorlevel)
    local text = ""
    if errorlevel and errorlevel ~= 0 then
        if errorlevel >= -65535 and errorlevel <= 65535 then
            text = string.format(" exit %d ", errorlevel)
        else
            text = string.format(" exit 0x%x ", errorlevel)
        end
    end
    return text
end

local function format_command_duration(duration)
    local text = ""
    if duration and duration >= tonumber(get_setting("min_duration")) then
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

        text = s
        if t then
            text = text.."."..t
        end
        text = text.."s"
        if m then
            text = m.."m "..text
            if h then
                text = h.."h "..text
            end
        end

        text = " took "..text.." "
    end
    return text
end

local function format_command(line, width)
    local text = trim(line)
    text = console.ellipsify(text, width or (console.getwidth() / 2))
    return add_margin(text)
end

local padding_amount = 2

local function make_divider_begin(line)
    local terminal_width = console.getwidth()

    local line_color = sgr("0;"..get_color("command_frame_top"))
    local text_color = get_color("command_frame_caption")
    if isnilorempty(text_color) then
        text_color = sgr()
    else
        text_color = sgr("0;"..text_color)
    end

    local left_corner, line_char, right_corner = get_top_chars()
    local caption_limit = terminal_width / 2
    local cwd_limit = terminal_width / 3

    local div
    for i = 1, 4 do
        local div_left = table.concat({
            line_color,
            left_corner,
            string.rep(line_char, padding_amount),
        })

        if get_setting("show_caption") then
            div_left = table.concat({
                div_left,
                text_color,
                format_command(line, caption_limit),
                line_color,
                string.rep(line_char, padding_amount),
            })
        end

        if get_setting("show_cwd") then
            div_left = table.concat({
                div_left,
                add_margin(console.ellipsify(os.getcwd(), cwd_limit)),
            })
        end

        local div_right = table.concat({
            right_corner,
            sgr(),
        })

        if get_setting("show_time") and i <= 2 then
            div_right = table.concat({
                add_margin(trim(os.date())),
                string.rep(line_char, padding_amount),
                div_right,
            })
        end

        local used = console.cellcount(div_left) + console.cellcount(div_right)
        if used <= terminal_width then
            div = table.concat({
                div_left,
                string.rep(line_char, terminal_width - used),
                div_right,
            })
            break
        end

        if i ~= 2 then
            caption_limit = caption_limit * 9 / 10
            cwd_limit = cwd_limit * 9 / 10
        end
    end

    if not div then
        local line_width = terminal_width - console.cellcount(left_corner..right_corner)
        div = line_color..left_corner..string.rep(line_char, line_width)..right_corner..sgr()
    end

    return div
end

local function maybe_print_divider_end()
    local begin_time = div_begin
    if not begin_time then
        return
    end

    local duration = os.clock() - begin_time
    local terminal_width = console.getwidth()
    local errorlevel = os.geterrorlevel()
    local maybe_auto_remove = can_auto_remove and get_setting("auto_remove")

    div_begin = nil
    can_auto_remove = nil

    -- If the exit code was 0 then maybe remove the beginning divider line.
    if prev_begin_divider and
            (errorlevel or 0) == 0 and
            maybe_auto_remove then
        local n = 0
        local y = console.getnumlines()
        local plain = console.plaintext(prev_begin_divider)
        local min_duration = tonumber(get_setting("min_duration"))
        local min_lines = tonumber(get_setting("min_lines"))
        -- Always try to remove if there was no output, or try to remove if the
        -- output didn't exceed command_frame.min_lines and the duration didn't
        -- exceed command_frame.min_duration.
        while n < min_lines do
            y = y - 1
            n = n + 1
            local l = console.getlinetext(y)
            if #l >= terminal_width / 2 and l == plain:sub(1, #l) then
                local text = string.format("\x1b[%uA\x1b[M", n)
                if n > 1 then
                    text = text..string.format("\x1b[%uB", n - 1)
                end
                clink.print(text, NONL)
                return
            end
            if duration > min_duration then
                break
            end
        end
    end

    local line_color
    if not errorlevel or not get_setting("exit_code_coloring") then
        line_color = sgr("0;"..get_color("command_frame_top"))
    elseif tonumber(errorlevel) == 0 then
        line_color = sgr("0;"..get_color("command_frame_succeeded"))
    else
        line_color = sgr("0;"..get_color("command_frame_failed"))
    end

    local text_color = get_color("command_frame_duration")
    if isnilorempty(text_color) then
        text_color = line_color
    else
        text_color = sgr("0;"..text_color)
    end

    local left_corner, line_char, right_corner = get_bottom_chars()

    local div_left = table.concat({
        line_color,
        left_corner,
        string.rep(line_char, padding_amount),
        format_error_level(errorlevel),
    })

    local div_right = table.concat({
        text_color,
        format_command_duration(duration),
        line_color,
        string.rep(line_char, padding_amount),
        right_corner,
        sgr(),
    })

    local consumed_width = console.cellcount(div_left) + console.cellcount(div_right)
    if consumed_width > terminal_width - padding_amount then
        local line_width = terminal_width - console.cellcount(left_corner..right_corner)
        clink.print(line_color..left_corner..string.rep(line_char, line_width)..right_corner..sgr())
        return
    end

    local div = table.concat({
        -- "\r\n",
        div_left,
        line_color,
        string.rep(line_char, terminal_width - consumed_width),
        div_right,
    })

    clink.print(div, NONL)
    print()
end

--------------------------------------------------------------------------------
-- Shared functions.

local pf = clink.promptfilter(-999999)

function pf:filter(prompt) -- luacheck: no unused
    maybe_print_divider_end()
end

clink.onendedit(function(line)
    if line:gsub(" ", "") == "" then
        return
    end

    if not get_setting("enable") then
        return
    end

    -- Ignore commands that redirect to nul.  This also catches hidden commands
    -- invoked by the direnv.lua script.
    if line:find(">%s*[nN][uU][lL][%s;,+=()]") or
            line:find(">%s*[nN][uU][lL]$") then
        return
    end

    local conditional_commands = {}
    for _, c in ipairs(string.explode(clink.lower(get_setting("never_commands")))) do
        conditional_commands[clink.lower(c)] = "never"
    end
    for _, c in ipairs(string.explode(clink.lower(get_setting("always_commands")))) do
        conditional_commands[clink.lower(c)] = "always"
    end

    local always
    local commands = clink.parseline(line)
    for _, c in ipairs(commands) do
        local ls = c.line_state
        for i = 1, ls:getwordcount() do
            local w = path.getbasename(ls:getword(i))
            local x = conditional_commands[clink.lower(w)]
            if x == "never" then
                return
            elseif x == "always" then
                always = true
            end
        end
    end

    can_auto_remove = not always

    local div = make_divider_begin(line)
    if div then
        local x = console.getcursorpos()
        if x > 1 then
            print()
        end
        clink.print(div)
        div_begin = os.clock()
        prev_begin_divider = div
    end
end)
