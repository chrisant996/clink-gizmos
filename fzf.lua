--------------------------------------------------------------------------------
-- FZF integration for Clink.
--
-- Clink is available at https://chrisant996.github.io/clink
-- FZF is available from https://nicedoc.io/junegunn/fzf
--
-- Either put fzf.exe in a directory listed in the system PATH environment
-- variable, or run 'clink set fzf.exe_location <directoryname>' to tell Clink
-- where to find fzf.exe.
--
-- To use FZF integration, you may set key bindings manually in your .inputrc
-- file, or you may use the default key bindings.  To use the default key
-- bindings, run 'clink set fzf.default_bindings true'.
--
-- The key bindings when 'fzf.default_bindings' is true are as follows.  They
-- are presented in .inputrc file format for convenience, if you want to add
-- them to your .inputrc manually (perhaps with modifications).
--
-- luacheck: push
-- luacheck: no max line length
--[[

# Default key bindings for fzf with Clink.
"\C-t":        "luafunc:fzf_file"           # Ctrl+T lists files recursively; choose one or multiple to insert them.
"\C-r":        "luafunc:fzf_history"        # Ctrl+R lists history entries; choose one to insert it.
"\M-c":        "luafunc:fzf_directory"      # Alt+C lists subdirectories; choose one to 'cd /d' to it.
"\M-b":        "luafunc:fzf_bindings"       # Alt+B lists key bindings; choose one to invoke it.
"\t":          "luafunc:fzf_complete"       # Tab uses fzf to filter match completions, but only when preceded by '**' (recursive).
"\e[27;5;32~": "luafunc:fzf_complete_force" # Ctrl+Space uses fzf to filter match completions (and supports '**' for recursive).

]]
--
-- Optional:  You can set the following environment variables to customize the
-- behavior:
--
--          FZF_CTRL_T_OPTS     = fzf options for fzf_file() function.
--          FZF_CTRL_R_OPTS     = fzf options for fzf_history() function.
--          FZF_ALT_C_OPTS      = fzf options for fzf_directory() function.
--          FZF_BINDINGS_OPTS   = fzf options for fzf_bindings() function.
--          FZF_COMPLETE_OPTS   = fzf options for fzf_complete() and
--                                fzf_complete_force() and fzf_selectcomplete()
--                                functions.
--
--          FZF_CTRL_T_COMMAND  = command to run for collecting files for
--                                fzf_file() function.
--          FZF_ALT_C_COMMAND   = command to run for collecting directories for
--                                fzf_directory() function.
--
--          FZF_COMPLETION_DIR_COMMANDS = commands that should complete only
--                                        directories, separated by spaces.
--
--          FZF_ICON_WIDTH      = number of cells/spaces to strip from the
--                                beginning of each match, to remove icons that
--                                inserted by customized FZF_CTRL_T_COMMAND and
--                                FZF_ALT_C_COMMAND commands.
--
-- To get file icons to show up in FZF, you can use DIRX v0.9 or newer with
-- Clink v1.6.5, and set the FZF env vars like this:
--
--      set FZF_CTRL_T_COMMAND=dirx.exe /b /s /X:d /a:-s-h --bare-relative --icons=always --utf8 $dir
--      set FZF_ALT_C_COMMAND=dirx.exe /b /s /X:d /a:d-s-h --bare-relative --icons=always --utf8 $dir
--      set FZF_ICON_WIDTH=2
--
-- If you want it to recurse into hidden directories, then remove the `/X:d`
-- part from the commands in the environment variables.
--
-- If you want it to list hidden files and directories, then remove the `-h`
-- part at the end of the `/a:` flags in the environment variables.
--
-- DIRX is available at https://github.com/chrisant996/dirx
-- Clink is available at https://github.com/chrisant996/clink
--
-- luacheck: pop

--------------------------------------------------------------------------------
-- Compatibility check.
if not io.popenrw then
    print('fzf.lua requires a newer version of Clink; please upgrade.')
    return
end

--------------------------------------------------------------------------------
-- Settings available via 'clink set'.

settings.add('fzf.height', '40%', 'Height to use for the --height flag')
settings.add('fzf.exe_location', '', 'Location of fzf.exe if not on the PATH')

if rl.setbinding then

    settings.add(
        'fzf.default_bindings',
        false,
        'Use default key bindings',
        'To avoid interference with your existing key bindings, key bindings for\n'..
        'fzf are initially not enabled.  Set this to true to enable the default\n'..
        'key bindings for fzf, or add bindings manually to your .inputrc file.\n\n'..
        'Changing this takes effect for the next Clink session.')

    if settings.get('fzf.default_bindings') then
        rl.setbinding([["\C-t"]], [["luafunc:fzf_file"]])
        rl.setbinding([["\C-r"]], [["luafunc:fzf_history"]])
        rl.setbinding([["\M-c"]], [["luafunc:fzf_directory"]])
        rl.setbinding([["\M-b"]], [["luafunc:fzf_bindings"]])
        rl.setbinding([["\t"]], [["luafunc:fzf_complete"]])
        rl.setbinding([["\e[27;5;32~"]], [["luafunc:fzf_complete_force"]])
    end

end

--------------------------------------------------------------------------------
-- Helpers.

local diag = false
local fzf_complete_intercept = false

local function add_help_desc(macro, desc)
    if rl.describemacro then
        rl.describemacro(macro, desc)
    end
end

local function maybe_strip_icon(str)
    local width = os.getenv("FZF_ICON_WIDTH")
    if width then
        width = tonumber(width)
        if width and width > 0 then
            if unicode.iter then
                local iter = unicode.iter(str)
                local c = iter()
                if c then
                    return str:sub(#c + (width - 1) + 1)
                end
            else
                if str:byte() == 32 then
                    return str:sub(width + 1)
                elseif width > 1 then
                    local tmp = str:match("^[^ ]+(.*)$")
                    if tmp then
                        return tmp:sub(width)
                    end
                end
            end
        end
    end
    return str
end

local function make_query_string(rl_buffer)
    local s = rl_buffer:getbuffer()

    -- Must strip % because there's no way to escape % when the command line
    -- gets processed first by cmd, as it does when using io.popen() and etc.
    -- This is the only thing that gets dropped; everything else gets escaped.
    s = s:gsub('%%', '')

    if #s > 0 then
        -- Must double ^ so it roundtrips correctly.
        s = s:gsub('%^', '^^')

        -- The 2N rule for escaping quotes and backslashes:
        --
        -- - 2n backslashes followed by a quotation mark produce n backslashes
        --   followed by begin/end quote. This does not become part of the
        --   parsed argument, but toggles the "in quotes" mode.
        -- - (2n) + 1 backslashes followed by a quotation mark again produce n
        --   backslashes followed by a quotation mark literal ("). This does not
        --   toggle the "in quotes" mode.
        -- - n backslashes not followed by a quotation mark simply produce n
        --   backslashes.
        --
        -- https://learn.microsoft.com/en-us/windows/win32/api/shellapi/nf-shellapi-commandlinetoargvw
        local tmp = ''
        local i = 1
        while i <= #s do
            local pre,suf = s:match('^(.-)(\\*)"', i)
            if pre and suf then
                tmp = tmp..pre..suf..suf..'\\"'
                i = i + #pre + #suf + 1
            else
                tmp = tmp..s:sub(i)
                break
            end
        end
        s = tmp

        -- Must double any trailing \ characters and add another, since we're
        -- about to append a trailing double quote (same 2N rule as above).
        local pre,suf = s:match('^(.-)(\\*)$')
        if pre and suf then
            s = pre..suf..suf
        end

        s = '--query "'..s..'"'
    end

    return s
end

local function get_fzf(env, addl_options)
    local command = settings.get('fzf.exe_location')
    if not command or command == '' then
        command = 'fzf.exe'
    end
    command = command:gsub('"', '')

    -- It's important to invoke an .exe file, otherwise quoting for --query can
    -- malfunction and potentially fall into a code injection situation.
    if path.getname(command) ~= command then
        local command_path = path.toparent(command)
        command = path.join(command_path, path.getbasename(command)..".exe")
    else
        command = path.getbasename(command)..".exe"
    end

    local height = settings.get('fzf.height')
    if height and height ~= '' then
        command = '"'..command..'" --height '..height
    end

    if addl_options then
        command = command..' '..addl_options
    end

    if env then
        local options = os.getenv(env)
        if options then
            command = command..' '..options
        end
    end

    return command
end

local function get_clink()
    local exe = CLINK_EXE
    if not exe or exe == '' then
        return ''
    end
    return '"'..exe..'"'
end

local function need_quote(word)
    return word and word:find("[ &()[%]{}^=;!%%'+,`~]") and true
end

local function maybe_quote(word)
    if need_quote(word) then
        word = '"' .. word .. '"'
    end
    return word
end

local function escape_quotes(text)
    return text:gsub('"', '\\"')
end

local function replace_dir(str, word)
    if word == '.' then
        word = nil
    end
    if word then
        if word:find('^%.[/\\]') then
            word = word:match('^%.[/\\]+(.*)$')
        end
        word = rl.expandtilde(word)
        if not os.isdir(word) then
            word = word.."*"
        end
        word = maybe_quote(word)
    end
    return str:gsub('$dir', word or '')
end

local function get_word_at_cursor(line_state)
    if line_state:getwordcount() > 0 then
        local info = line_state:getwordinfo(line_state:getwordcount())
        if info then
            local line = line_state:getline()
            local word = line:sub(info.offset, line_state:getcursor() - 1)
            if word and #word > 0 then
                word = word:gsub('"', '')
                word = word:gsub("'", '')
                return word
            end
        end
    end
end

local function get_word_insert_bounds(line_state)
    if line_state:getwordcount() > 0 then
        local info = line_state:getwordinfo(line_state:getwordcount())
        if info then
            local first = info.offset
            local last = line_state:getcursor() - 1
            local quote
            local delimit
            if info.quoted then
                local line = line_state:getline()
                first = first - 1
                quote = line:sub(first, first)
                local eq = line:sub(last + 1, last + 1)
                if eq == '' or eq == ' ' or eq == '\t' then
                    delimit = true
                end
            end
            return first, last, quote, delimit
        end
    end
end

local function get_ctrl_t_command(dir)
    local command = os.getenv('FZF_CTRL_T_COMMAND')
    if not command then
        command = 'dir /b /s /a:-s $dir'
    end
    command = replace_dir(command, dir)
    return command
end

local function get_alt_c_command(dir)
    local command = os.getenv('FZF_ALT_C_COMMAND')
    if not command then
        command = 'dir /b /s /a:d-s $dir'
    end
    command = replace_dir(command, dir)
    return command
end

local function is_trigger(line_state)
    local word = get_word_at_cursor(line_state)
    if word and word:sub(#word - 1) == '**' then
        return word:sub(1, #word - 2)
    end
end

local function is_dir_command(line_state)
    local command = line_state:getword(1)
    local dir_commands = os.getenv('FZF_COMPLETION_DIR_COMMANDS') or 'cd chdir rd rmdir pushd'
    for _,c in ipairs(string.explode(dir_commands)) do
        if string.equalsi(c, command) then
            return true
        end
    end
end

local function fzf_recursive(rl_buffer, line_state, search, dirs_only) -- luacheck: no unused
    local dir, word
    dir = path.getdirectory(search)
    word = path.getname(search)

    local command
    if dirs_only then
        command = get_alt_c_command(dir)
    else
        command = get_ctrl_t_command(dir)
    end

    local first, last, has_quote, delimit = get_word_insert_bounds(line_state) -- luacheck: no unused
    local quote = has_quote or '"'

    local r = io.popen('2>nul '..command..' | '..get_fzf('FZF_COMPLETE_OPTS')..' -q "'..word..'"')
    if not r then
        rl_buffer:ding()
        return
    end

    -- Read filtered matches.
    local match
    while (true) do
        local line = r:read('*line')
        if not line then
            break
        end
        if not match then
            match = line
        end
    end
    r:close()

    if not match then
        return
    end
    match = maybe_strip_icon(match)

    -- Insert match.
    local use_quote = ((has_quote or need_quote(match)) and quote) or ''
    rl_buffer:beginundogroup()
    rl_buffer:remove(first, last + 1)
    rl_buffer:setcursor(first)
    rl_buffer:insert(use_quote)
    rl_buffer:insert(match)
    rl_buffer:insert(use_quote)
    rl_buffer:insert(' ')
    rl_buffer:endundogroup()
end

-- luacheck: globals fzf_complete_internal
function fzf_complete_internal(rl_buffer, line_state, force, completion_command)
    local search = is_trigger(line_state)
    if search then
        -- Gather files and/or dirs recursively, and show them in fzf.
        local dirs_only = is_dir_command(line_state)
        fzf_recursive(rl_buffer, line_state, search, dirs_only)
        rl_buffer:refreshline()
    elseif not force then
        -- Invoke the normal complete command.
        rl.invokecommand(completion_command or 'complete')
    else
        -- Intercept matches Use match filtering to let
        fzf_complete_intercept = true
        rl.invokecommand(completion_command or 'complete')
        if fzf_complete_intercept then
            rl_buffer:ding()
        end
        fzf_complete_intercept = false
        rl_buffer:refreshline()
    end
end

--------------------------------------------------------------------------------
-- Functions for use with 'luafunc:' key bindings.

-- luacheck: globals fzf_complete
add_help_desc("luafunc:fzf_complete",
              "Use fzf for completion if ** is immediately before the cursor position")
function fzf_complete(rl_buffer, line_state)
    fzf_complete_internal(rl_buffer, line_state, false)
end

-- luacheck: globals fzf_selectcomplete
add_help_desc("luafunc:fzf_selectcomplete",
              "Use fzf for completion after ** otherwise use 'clink-select-complete' command")
function fzf_selectcomplete(rl_buffer, line_state)
    fzf_complete_internal(rl_buffer, line_state, false, "clink-select-complete")
end

-- luacheck: globals fzf_complete_force
add_help_desc("luafunc:fzf_complete_force",
              "Use fzf for completion")
function fzf_complete_force(rl_buffer, line_state)
    fzf_complete_internal(rl_buffer, line_state, true)
end

-- luacheck: globals fzf_history
add_help_desc("luafunc:fzf_history",
              "List history entries; choose one to insert it (press DEL to delete selected history entry)")
function fzf_history(rl_buffer)
    local clink_command = get_clink()
    if #clink_command == 0 then
        rl_buffer:ding()
        return
    end

    -- Build command to get history for the current Clink session.
    local history = clink_command..' --session '..clink.getsession()..' history --time-format " "'
    if diag then
        history = history..' --diag'
    end

    -- Make key binding for DEL to delete a history entry.
    local history_delete = escape_quotes(clink_command..' --session '..clink.getsession()..' history delete {1}')
    local history_reload = escape_quotes(history)
    local del_binding = '--bind "del:execute-silent('..history_delete..')+reload('..history_reload..')"'

    -- This produces a '--query' string by stripping certain problematic
    -- characters from the input line.  This still does a good job of matching,
    -- because fzf uses fuzzy matching.
    local qs = make_query_string(rl_buffer)
    local r = io.popen('2>nul '..history..' | '..get_fzf('FZF_CTRL_R_OPTS', del_binding)..' -i --tac '..qs)
    if not r then
        rl_buffer:ding()
        return
    end

    local str = r:read('*all')
    str = str and str:gsub('[\r\n]', '') or ''
    r:close()

    -- If something was selected, insert it.
    if #str > 0 then
        rl_buffer:beginundogroup()
        rl_buffer:remove(0, -1)
        rl_buffer:insert(str)
        rl_buffer:endundogroup()
    end

    rl_buffer:refreshline()
end

-- luacheck: globals fzf_file
add_help_desc("luafunc:fzf_file",
              "List files recursively; choose one or multiple to insert them")
function fzf_file(rl_buffer, line_state)
    local dir = get_word_at_cursor(line_state)
    local command = get_ctrl_t_command(dir)

    local r = io.popen(command..' 2>nul | '..get_fzf('FZF_CTRL_T_OPTS')..' -i -m')
    if not r then
        rl_buffer:ding()
        return
    end

    local str = r:read('*line')
    str = str and str:gsub('[\r\n]+', ' ') or ''
    str = str:gsub(' +$', '')
    r:close()

    if #str > 0 then
        str = maybe_strip_icon(str)
        rl_buffer:insert(maybe_quote(str))
    end

    rl_buffer:refreshline()
end

-- luacheck: globals fzf_directory
add_help_desc("luafunc:fzf_directory",
              "List subdirectories; choose one to 'cd /d' to it")
function fzf_directory(rl_buffer, line_state)
    local dir = get_word_at_cursor(line_state)
    local command = get_alt_c_command(dir)

    local r = io.popen(command..' 2>nul | '..get_fzf('FZF_ALT_C_OPTS')..' -i')
    if not r then
        rl_buffer:ding()
        return
    end

    local str = r:read('*all')
    str = str and str:gsub('[\r\n]', '') or ''
    r:close()

    if #str > 0 then
        str = maybe_strip_icon(str)
        rl_buffer:beginundogroup()
        rl_buffer:remove(0, -1)
        rl_buffer:insert('cd /d '..str)
        rl_buffer:endundogroup()
        rl_buffer:refreshline()
        rl.invokecommand('accept-line')
        return
    end

    rl_buffer:refreshline()
end

-- luacheck: globals fzf_bindings
add_help_desc("luafunc:fzf_bindings",
              "List key bindings; choose one to invoke it")
function fzf_bindings(rl_buffer)
    if not rl.getkeybindings then
        rl_buffer:beginoutput()
        print('fzf_bindings() in fzf.lua requires a newer version of Clink; please upgrade.')
        return
    end

    local bindings = rl.getkeybindings()
    if #bindings <= 0 then
        rl_buffer:refreshline()
        return
    end

    local line
    local r,w = io.popenrw(get_fzf('FZF_BINDINGS_OPTS')..' -i')
    if r and w then
        -- Write key bindings to the write pipe.
        for _,kb in ipairs(bindings) do
            w:write(kb.key..' : '..kb.binding..'\n')
        end
        w:close()

        -- Read filtered matches.
        line = r:read('*line')
        r:close()
    end

    rl_buffer:refreshline()

    if line and #line > 0 then
        local binding = line:sub(#bindings[1].key + 3 + 1)
        rl.invokecommand(binding)
    end
end

--------------------------------------------------------------------------------
-- Match generator.

local function filter_matches(matches, completion_type, filename_completion_desired) -- luacheck: no unused
    if not fzf_complete_intercept then
        return
    end
    if #matches <= 1 then
        return
    end

    -- Start fzf.
    local r,w = io.popenrw(get_fzf('FZF_COMPLETE_OPTS'))
    if not r or not w then
        return
    end

    -- Write matches to the write pipe.
    local which = {}
    for _,m in ipairs(matches) do
        if m.display and console.plaintext then
            local text = console.plaintext(m.display)
            table.insert(which, text)
            w:write(text..'\n')
        else
            table.insert(which, m.match)
            w:write(m.match..'\n')
        end
    end
    w:close()

    -- Read filtered matches.
    local ret = {}
    while (true) do
        local line = r:read('*line')
        if not line then
            break
        end
        for i,m in ipairs(matches) do
            if line == which[i] then
                table.insert(ret, m)
            end
        end
    end
    r:close()

    -- Yay, successful; clear it to not ding.
    fzf_complete_intercept = false
    return ret
end

local interceptor = clink.generator(0)
function interceptor:generate(line_state, match_builder) -- luacheck: no unused
    if fzf_complete_intercept then
        clink.onfiltermatches(filter_matches)
    end
    return false
end

clink.onbeginedit(function ()
    fzf_complete_intercept = false
end)

--------------------------------------------------------------------------------
-- Argmatcher helpers (based on modules\arghelper.lua from
-- https://github.com/vladimir-kotikov/clink-completions).

local tmp = clink.argmatcher and clink.argmatcher() or clink.arg.new_parser()
local meta = getmetatable(tmp)

local addexarg
local addexflags

do
    local link = "link"..tmp
    local meta_link = getmetatable(link)

    local function is_parser(x)
        return getmetatable(x) == meta
    end

    local function is_link(x)
        return getmetatable(x) == meta_link
    end

    local function add_elm(elm, list, descriptions, hide, in_opteq)
        local arg
        local opteq = in_opteq
        if elm[1] then
            arg = elm[1]
        else
            if type(elm) == "table" and not is_link(elm) and not is_parser(elm) then
                return
            end
            arg = elm
        end
        if elm.opteq ~= nil then
            opteq = elm.opteq
        end

        local t = type(arg)
        local arglinked = is_link(arg)
        if arglinked or is_parser(arg) then
            t = "matcher"
        elseif t == "table" then
            if elm[4] then
                t = "nested"
            else
                for _,scan in ipairs(elm) do
                    if type(scan) == "table" then
                        t = "nested"
                        break
                    end
                end
            end
        end
        if t == "string" or t == "number" or t == "matcher" then
            if t == "matcher" then
                table.insert(list, arg)
                if opteq and arglinked and clink.argmatcher then
                    local altkey
                    if arg._key:sub(-1) == '=' then
                        altkey = arg._key:sub(1, #arg._key - 1)
                    else
                        altkey = arg._key..'='
                    end
                    table.insert(hide, altkey)
                    table.insert(list, { altkey..arg._matcher })
                end
            else
                table.insert(list, tostring(arg))
            end
            if elm[2] and descriptions then
                local name = arglinked and arg._key or arg
                if elm[3] then
                    descriptions[name] = { elm[2], elm[3] }
                else
                    descriptions[name] = { elm[2] }
                end
            end
            if elm.hide then
                local name = arglinked and arg._key or arg
                table.insert(hide, name)
            end
        elseif t == "function" then
            table.insert(list, arg)
        elseif t == "nested" then
            for _,sub_elm in ipairs(elm) do
                add_elm(sub_elm, list, descriptions, hide, opteq)
            end
        else
            pause("unrecognized input table format.")
            error("unrecognized input table format.")
        end
    end

    local function build_lists(tbl)
        local list = {}
        local descriptions = (not ARGHELPER_DISABLE_DESCRIPTIONS) and {} -- luacheck: no global
        local hide = {}
        if type(tbl) ~= "table" then
            pause('table expected.')
            error('table expected.')
        end
        for _,elm in ipairs(tbl) do
            local t = type(elm)
            if t == "table" then
                add_elm(elm, list, descriptions, hide, tbl.opteq)
            elseif t == "string" or t == "number" or t == "function" then
                table.insert(list, elm)
            end
        end
        list.fromhistory = tbl.fromhistory
        list.nosort = tbl.nosort
        return list, descriptions, hide
    end

    do
        addexflags = function(parser, tbl)
            local flags, descriptions, hide = build_lists(tbl)
            parser:addflags(flags)
            if descriptions then
                parser:adddescriptions(descriptions)
            end
            if hide then
                parser:hideflags(hide)
            end
            return parser
        end
    end

    do
        addexarg = function(parser, tbl)
            local args, descriptions = build_lists(tbl)
            parser:addarg(args)
            if descriptions then
                parser:adddescriptions(descriptions)
            end
            return parser
        end
    end
end

--------------------------------------------------------------------------------
-- Argmatcher.

-- luacheck: no max line length

local algos = addexarg(clink.argmatcher(), {
    { 'v1',             'Optimal scoring algorithm (quality)' },
    { 'v2',             'Faster but not guaranteed to find the optimal result (performance)' },
})
local scheme = clink.argmatcher():addarg({'default', 'path', 'history'})
local nth = clink.argmatcher():addarg({fromhistory=true, loopchars=','})
local delim = clink.argmatcher():addarg({fromhistory=true})
local criteria = clink.argmatcher():addarg({
    loopchars=',',
    { 'length',         'Prefers line with shorter length' },
    { 'chunk',          'Prefers line with shorter matched chunk' },
    { 'begin',          'Prefers line with matched substring closer to the beginning' },
    { 'end',            'Prefers line with matched substring closer to the end' },
    { 'index',          'Prefers line that appeared earlier in the input stream' },
})
local multimax = clink.argmatcher():addarg({fromhistory=true})
local keybinds = clink.argmatcher():addarg({fromhistory=true, loopchars=','})
local scrolloff = clink.argmatcher():addarg({fromhistory=true, '0'})
local hscrolloff = clink.argmatcher():addarg({fromhistory=true, '10'})
local jumplabels = clink.argmatcher():addarg({fromhistory=true})
local heights = clink.argmatcher():addarg({fromhistory=true, '10', '15', '20', '25%', '30%', '40%', '50%'})
local minheight = clink.argmatcher():addarg({fromhistory=true, '10'})
local layout = addexarg(clink.argmatcher(), {
    nosort=true,
    { 'default',        'Display from the bottom of the screen' },
    { 'reverse',        'Display from the top of the screen' },
    { 'reverse-list',   'Display from the top of the screen, prompt at the bottom' },
})
local borderstyle = clink.argmatcher():addarg({
    nosort=true,
    'rounded',
    'sharp',
    'bold',
    'double',
    'horizontal',
    'vertical',
    'top',
    'bottom',
    'left',
    'right',
    'none',
})
local borderlabel = clink.argmatcher():addarg({fromhistory=true})
local borderlabelpos = clink.argmatcher():addarg({fromhistory=true})
local margin = clink.argmatcher():addarg({fromhistory=true, loopchars=',', '0', '1', '2'})
local padding = clink.argmatcher():addarg({fromhistory=true, loopchars=',', '0', '1', '2'})
local infostyle = addexarg(clink.argmatcher(), {
    nosort=true,
    { 'default',        'Display on the next line to the prompt' },
    { 'inline',         'Display on the same line as the prompt' },
    { 'hidden',         'Do not display finder info' },
})
local prompt = clink.argmatcher():addarg({fromhistory=true, '"> "'})
local pointer = clink.argmatcher():addarg({fromhistory=true, '">"', '"*"'})
local marker = clink.argmatcher():addarg({fromhistory=true, '">"', '"*"'})
local header = clink.argmatcher():addarg({fromhistory=true})
local headerlines = clink.argmatcher():addarg({fromhistory=true})
local ellipsis = clink.argmatcher():addarg({fromhistory=true, '..', '...', '…'})
local tabstop = clink.argmatcher():addarg({fromhistory=true, '8'})
local colspec = clink.argmatcher():addarg({fromhistory=true, loopchars=','})
local historysize = clink.argmatcher():addarg({fromhistory=true, '1000'})
local previewcommand = clink.argmatcher():addarg({fromhistory=true})
local previewopt = clink.argmatcher():addarg({
    fromhistory=true,
    loopchars=',:',
    'up', 'down', 'left', 'right',
    '10%', '20%', '25%', '30%', '40%', '50%', '60%', '70%', '75%', '80%', '90%',
    'wrap', 'nowrap',
    'cycle', 'nocycle',
    'follow', 'nofollow',
    'hidden', 'nohidden',
    'border',
    'border-rounded', 'border-sharp',
    'border-horizontal', 'border-vertical',
    'border-top', 'border-bottom', 'border-left', 'border-right',
    'border-none',
    '+SCROLL[OFFSETS][/DENOM]',
    '~HEADER_LINES',
    'default',
})
local previewlabel = clink.argmatcher():addarg({fromhistory=true})
local previewlabelpos = clink.argmatcher():addarg({fromhistory=true})
local query = clink.argmatcher():addarg({fromhistory=true})
local filter = clink.argmatcher():addarg({fromhistory=true})
local expect = clink.argmatcher():addarg({fromhistory=true, loopchars=','})
local separatorstr = clink.argmatcher():addarg({fromhistory=true})
local scrollbarchars = clink.argmatcher():addarg({fromhistory=true})

addexflags(clink.argmatcher('fzf'), {
    opteq=true,
    -- Search options
    { '-x',                             'Extended-search mode (enabled by default; +x or --no-extended to disable)' },
    { '+x',                             'Disable extended-search mode' },
    { '--extended',                     'Extended-search mode (enabled by default; +x or --no-extended to disable)' },
    { '--no-extended',                  'Disable extended-search mode' },
    { '-e',                             'Enable Exact-match' },
    { '--exact',                        'Enable Exact-match' },
    { '-i',                             'Case-insensitive match (default: smart-case match; +i for case-sensitive match)' },
    { '+i',                             'Case-sensitive match' },
    { '--literal',                      'Do not normalize latin script letters before matching' },
    { '--scheme='..scheme, 'SCHEME',    'Scoring scheme' },
    { '--algo='..algos, 'TYPE',         'Fuzzy matching algorithm' },
    { '-n'..nth, ' N[,..]',             'Comma-separated list of field index expressions for limiting search scope (non-zero integer or range expression "1..4")' },
    { '--nth='..nth, 'N[,..]',          'Comma-separated list of field index expressions for limiting search scope (non-zero integer or range expression "1..4")' },
    { '--with-nth='..nth, 'N[,..]',     'Transform the presentation of each line using field index expressions' },
    { '-d'..delim, ' STR',              'Field delimiter regex (default: AWK-style)' },
    { '--delimiter='..delim, 'STR',     'Field delimiter regex (default: AWK-style)' },
    { '--disabled',                     'Do not perform search (simple selector interface)' },
    { '+s',                             'Do not sort the result' },
    { '--no-sort',                      'Do not sort the result' },
    { '--track',                        'Track the current selection when the result is updated' },
    { '--tac',                          'Reverse the order of the input' },
    { '--tiebreak='..criteria, 'CRI[,..]', 'Comma-separated list of sort criteria to apply when the scores are tied (default: length)' },

    -- Interface options
    { '-m',                             'Enable multi-select with tab/shift-tab' },
    { '--multi',                        'Enable multi-select with tab/shift-tab' },
    { '--multi='..multimax, 'MAX',      'Enable multi-select with tab/shift-tab', opteq=false },
    { '--no-mouse',                     'Disable mouse' },
    { '--bind='..keybinds, 'KEYBINDS',  'Custom key bindings. Refer to the man page' },
    { '--cycle',                        'Enable cyclic scroll' },
    { '--keep-right',                   'Keep the right end of the line visible on overflow' },
    { '--scroll-off='..scrolloff, 'LINES', 'Number of screen lines to keep above or below when scrolling to the top or to the bottom (default: 0)' },
    { '--no-hscroll',                   'Disable horizontal scroll' },
    { '--hscroll-off='..hscrolloff, 'COLS', 'Number of screen columns to keep to the right of the highlighted substring (default: 10)' },
    { '--filepath-word',                'Make word-wise movements respect path separators' },
    { '--jump-labels='..jumplabels, 'CHARS', 'Label characters for jump and jump-accept' },

    -- Layout options
    { '--height='..heights, 'HEIGHT[%]', 'Display fzf window below the cursor with the given height instead of using fullscreen' },
    { '--min-height='..minheight, 'HEIGHT', 'Minimum height when --height is given in percent (default: 10)' },
    { '--layout='..layout, 'LAYOUT',    'Choose layout' },
    { '--reverse',                      'A synonym for --layout=reverse' },
    { '--border',                       'Draw border around the finder (default: rounded)' },
    { '--border='..borderstyle, 'STYLE', 'Draw border around the finder (default: rounded)', opteq=false },
    { '--border-label='..borderlabel, 'LABEL', 'Label to print on the border' },
    { '--border-label-pos='..borderlabelpos, 'N[:top|bottom]', 'Position of border label' },
    { '--no-unicode',                   'Use ASCII characters instead of Unicode drawing characters' },
    { '--margin='..margin, 'MARGIN',    'Screen margin (TRBL | TB,RL | T,RL,B | T,R,B,L)' },
    { '--padding='..padding, 'PADDING', 'Padding inside border (TRBL | TB,RL | T,RL,B | T,R,B,L)' },
    { '--info='..infostyle, 'STYLE',    'Finder info style' },
    { '--no-info',                      'Hide the finder info (synonym for --info=hidden)' },
    { '--separator='..separatorstr, 'STR', 'Hide info line separator' },
    { '--no-separator',                 'Hide info line separator' },
    { '--scrollbar',                    'Show scrollbar' },
    { '--scrollbar='..scrollbarchars, 'C1[C2]', 'Scrollbar character for main [and preview] window', opteq=false },
    { '--no-scrollbar',                 'Hide scrollbar' },
    { '--prompt='..prompt, 'STR',       "Input prompt (default: '> ')" },
    { '--pointer='..pointer, 'STR',     "Pointer to the current line (default: '>')" },
    { '--marker='..marker, 'STR',       "Multi-select marker (default: '>')" },
    { '--header='..header, 'STR',       "String to print as header" },
    { '--header-lines='..headerlines, 'N', 'The first N lines of the input are treated as header' },
    { '--header-first',                 'Print header before the prompt line' },
    { '--ellipsis='..ellipsis, 'STR',   "Ellipsis to show when line is truncated (default: '..')" },

    -- Display options
    { '--ansi',                         'Enable processing of ANSI color codes' },
    { '--tabstop='..tabstop, 'SPACES',  'Number of spaces for a tab character (default: 8)' },
    { '--color='..colspec, 'COLSPEC',   'Base scheme and/or custom colors' },
    { '--no-bold',                      'Do not use bold text' },
    { '--black',                        'Use black background' },

    -- History options
    { '--history=', 'FILE',             'History file' },
    { '--history-size='..historysize, 'N', 'Maximum number of history entries (default: 1000)' },

    -- Preview options
    { '--preview='..previewcommand, 'COMMAND', 'Command to preview highlighted line ({})' },
    { '--preview-label='..previewlabel, 'LABEL', 'Label to print on preview window border' },
    { '--preview-label-pos='..previewlabelpos, 'N[:top|bottom]', 'Position of label on preview window border' },
    { '--preview-window='..previewopt, 'OPTS', 'Preview window layout (default: right,50%)' },

    -- Scripting options
    { '-q'..query, ' STR',              'Start the finder with the given query' },
    { '--query='..query, 'STR',         'Start the finder with the given query' },
    { '-1',                             'Automatically select the only match' },
    { '--select-1',                     'Automatically select the only match' },
    { '-0',                             'Exit immediately when there\'s no match' },
    { '--exit-0',                       'Exit immediately when there\'s no match' },
    { '-f'..filter, ' STR',             'Filter mode. Do not start interactive finder' },
    { '--filter='..filter, 'STR',       'Filter mode. Do not start interactive finder' },
    { '--print-query',                  'Print query as the first line' },
    { '--expect='..expect, 'KEYS',      'Comma-separated list of keys to complete fzf' },
    { '--no-expect',                    'Clear list of keys to complete fzf' },
    { '--read0',                        'Read input delimited by ASCII NUL characters' },
    { '--print0',                       'Print output delimited by ASCII NUL characters' },
    { '--sync',                         'Synchronous search for multi-staged filtering' },
    { '--version',                      'Display version information and exit' },
    { '-h',                             'Display help text' },
    { '--help',                         'Display help text' },
})

