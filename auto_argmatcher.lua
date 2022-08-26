--------------------------------------------------------------------------------
-- Usage:
--
-- This script automatically creates argmatchers for commands by parsing the
-- help text output from the commands.  You must provide a config file that
-- lists the commands for which to auto-create argmatchers.
--
-- Because there is no universal convention for how to request help text from
-- programs, this cannot assume how to request help text.  So, you must provide
-- a config file tell it which commands, and how to safely request their help
-- text.
--
-- This loads auto_argmatcher.config files from all of the following locations:
--
--      - The Clink profile directory.
--      - The directory where this script is located.
--
--------------------------------------------------------------------------------
-- Config file format:
--
-- Each line in auto_argmatcher.config has the following format:
--
--      command help_flag parser modes
--
-- The parser runs "command help_flag" and parses the output text.
-- For example:
--
--      dir     /?  basic
--      where   /?  basic
--
-- Parsers:
--
--      basic           (default) Basic parser that extracts up to one flag and
--                      description per line.
--      curl            A simple parser that extracts multiple flags and a
--                      description per line; based on the format of the Curl
--                      tool for Windows.
--      gnu             Parser based on help text format of GNU tools like grep
--                      and sed.
--
-- Modes:
--
--      --smartcase     (default) Flags are case insensitive if all are listed
--                      in upper case.
--      --caseless      Treat flags as case insensitive.
--      --slashes       Some programs recognize both - and / flags, but only
--                      list the - flags in the help text.  This mode adds a /
--                      flag for each - flag (e.g. for -x, also adds /x).
--      --override_command  The 'help_flag' specifies the whole command to run.
--
-- Example for --override_command:
--
--      Suppose there is a doskey alias "ax" for "abc xyz $*".  The command to
--      run to get help text would not be "ax /?", so use --override_command:
--
--      ax    "abc xyz /?"    basic    --override_command
--
-- Notes:
--
--      Blank lines and lines beginning with # or ; or / are ignored.
--
--      Fields may be surrounded by double quotes if they contain spaces.  The
--      double quotes are not included as part of the string.  Double quotes may
--      be embedded by escaping with a backslash (\").  Note that backslash is
--      only an escape character when followed by a double quote (\"); any other
--      backslashes are kept as-is (so in "c:\dir\subdir" the backslashes are
--      not escapes).

--------------------------------------------------------------------------------
if not clink.oncommand or not clink.getargmatcher then
    print('auto_argmatcher.lua requires a newer version of Clink; please upgrade.')
    return
end

local help_parser = require('help_parser')

--------------------------------------------------------------------------------
local _config = {}

--------------------------------------------------------------------------------
local _modes = {
    ['--smartcase'] = { 'case', nil },
    ['--caseless'] = { 'case', 1 },
    ['--case'] = { 'case', 2 },
    ['--slashes'] = { 'slashes', 1 },
    ['--override-command'] = { 'override_command', true },
}

--------------------------------------------------------------------------------
local function explode(line)
    if not line:find('"') then
        return string.explode(line, ' \t')
    end

    local words = {}

    local word = ""
    local quote = false
    local i = 1
    while i <= #line do
        local c = line:sub(i, i)
        if c == '"' then
            quote = not quote
        elseif not quote and (c == ' ' or c == '\t') then
            if #word > 0 then
                table.insert(words, word)
                word = ""
            end
        else
            if quote and c == '\\' and line:sub(i + 1, i + 1) == '"' then
                word = word .. '"'
                i = i + 1
            else
                word = word .. c
            end
        end
        i = i + 1
    end
    if #word > 0 then
        table.insert(words, word)
    end

    return words
end

--------------------------------------------------------------------------------
local function load_config_file(name)
    local file = io.open(name)
    if not file then
        return
    end

    local any
    for line in file:lines() do
        if #line == 0 or line:find('^[#;/]') then -- luacheck: ignore 542
            -- Ignore the line.
        else
            -- First word is command, second word is flags (can be quoted).
            local words = explode(line)
            if words and words[1] then
                local c = { command=words[1], flags=words[2], parser=words[3] }

                for i = 3, #words do
                    local m = _modes[words[i]]
                    if m and m[1] then
                        c[m[1]] = m[2]
                    end
                end

                _config[words[1]] = c
                any = true
            end
        end
    end

    file:close()
    return any
end

--------------------------------------------------------------------------------
local function get_config_file(dir)
    if not dir or dir == '' then
        local info = debug.getinfo(1, 'S')
        local src = info.source
        if not src then
            error('unable to detect config file location.')
            return
        end
        src = src:gsub('^@', '')
        dir = path.getdirectory(src)
    end
    return path.join(dir, 'auto_argmatcher.config')
end

--------------------------------------------------------------------------------
local function load_config()
    _config = {}

    local any

    any = load_config_file(get_config_file(os.getenv('=clink.profile'))) or any -- luacheck: ignore 321
    any = load_config_file(get_config_file()) or any

    return any
end

--------------------------------------------------------------------------------
local function read_lines(command)
    local lines = {}

    if command and command ~= '' then
        local r = io.popen('2>nul ' .. command)
        if r then
            for line in r:lines() do
                if unicode.fromcodepage then
                    line = unicode.fromcodepage(line)
                end
                table.insert(lines, line)
            end
            r:close()
        end
    end

    return lines
end

--------------------------------------------------------------------------------
local function build_argmatcher(entry)
    -- Putting redirection first also works around the CMD problem when the
    -- command line starts with a quote.
    local command
    if entry.override_command then
        command = entry.flags
    else
        command = entry.command .. ' ' .. (entry.flags or '')
    end

    -- Choose which parser to use.
    local need_init = true

    -- Create a delayinit function.
    local function delayinit(argmatcher)
        -- Only init once.
        if not need_init then
            return
        end

        -- Capture the help text from the command.
        local lines = read_lines(command)

        -- Auto-detect GNU parser.
        local parser = entry.parser
        if not parser then
            local num = #lines
            for i = (num - 25 > 1) and (num - 25) or 1, num do
                if lines[i]:match('^GNU ') then
                    parser = 'gnu'
                    break
                end
            end
        end

        -- Parse the help text.
        help_parser.run(argmatcher, parser, lines, entry)
        need_init = false
    end

    -- Create an argmatcher with delayinit.
    clink.argmatcher(entry.command):setdelayinit(delayinit)
end

--------------------------------------------------------------------------------
local function oncommand(line_state, info)
    if clink.getargmatcher(line_state) then
        return
    end

    local file = clink.lower(path.getname(info.file))
    if file and file ~= "" then
        local entry = _config[file] or _config[path.getbasename(file)]
        if entry then
            build_argmatcher(entry)
            return
        end
    end

    local command = clink.lower(path.getname(info.command))
    if command and command ~= "" then
        local entry = _config[command] or _config[path.getbasename(command)]
        if entry then
            build_argmatcher(entry)
            return
        end
    end
end

--------------------------------------------------------------------------------
if load_config() then
    clink.oncommand(oncommand)
end
