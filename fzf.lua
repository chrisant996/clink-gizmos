--------------------------------------------------------------------------------
-- FZF integration for Clink.
--
-- This requires Clink and FZF.
--  - Clink is available at https://chrisant996.github.io/clink
--  - FZF is available from https://github.com/junegunn/fzf
--
-- Either put fzf.exe in a directory listed in the system PATH environment
-- variable, or run 'clink set fzf.exe_location <put_full_exe_name_here>' to
-- tell Clink where to find fzf.exe (for example c:\tools\fzf.exe).
--
-- To use FZF integration, you may set key bindings manually in your .inputrc
-- file, or you may use the default key bindings.  To use the default key
-- bindings, run 'clink set fzf.default_bindings true'.
--
-- The key bindings when 'fzf.default_bindings' is true are as follows.  They
-- are presented in .inputrc file format for convenience, if you want to add
-- them to your .inputrc manually (perhaps with modifications).
--
--
--  NOTE:   If multiple copies of this script are loaded in the same Clink
--          session, only the last one initializes itself and the others are
--          ignored.
--
--
-- luacheck: push
-- luacheck: no max line length
--[[

# Default key bindings for fzf with Clink.
"\C-t":        "luafunc:fzf_file"           # Ctrl+T lists files recursively; choose one or multiple to insert them.
"\C-r":        "luafunc:fzf_history"        # Ctrl+R lists history entries; choose one to insert it.
"\M-c":        "luafunc:fzf_directory"      # Alt+C lists subdirectories; choose one to 'cd /d' to it.
"\M-b":        "luafunc:fzf_bindings"       # Alt+B lists key bindings; choose one to invoke it.
"\t":          "luafunc:fzf_tab"            # Tab uses fzf to filter match completions, but only when preceded by '**' (recursive).
"\e[27;5;32~": "luafunc:fzf_complete_force" # Ctrl+Space uses fzf to filter match completions (and supports '**' for recursive).

]]
--
-- The available settings are as follows.
-- The settings can be controlled via 'clink set'.
--
--      fzf.default_bindings    Controls whether to apply default bindings.
--                              This is false by default, to avoid interference
--                              with your existing key bindings.
--
--      fzf.exe_location        Specifies the location of fzf.exe if not in the
--                              system PATH.  This isn't just a directory name,
--                              it's the full path name of the exe file.
--                              For example, c:\tools\fzf.exe or etc.
--
--      fzf.allow_unsafe_query  Allows the fzf.exe_location setting to specify a
--                              file that doesn't end in ".exe".  In that case,
--                              it tries to still provide strong security
--                              protections by stripping unsafe characters from
--                              the input line before sending them to the
--                              non-exe fzf program.
--
--      fzf.show_descriptions   Show match descriptions when available.  Fzf
--                              searches in the description text as well.
--
--      fzf.color_descriptions  Apply color to match descriptions when shown.
--                              Uses the color.description setting, and adds
--                              the --ansi flag when invoking fzf.
--
--      fzf.height              Height to use for the fzf --height flag.  See
--                              fzf documentation on --height for values.
--
--
-- Optional:  You can set the following environment variables to customize the
-- behavior:
--
--          FZF_DEFAULT_OPTS    = fzf options applied to all fzf invocations.
--
--          FZF_CTRL_T_OPTS     = fzf options for fzf_file() function.
--          FZF_CTRL_R_OPTS     = fzf options for fzf_history() function.
--          FZF_ALT_C_OPTS      = fzf options for fzf_directory() function.
--          FZF_BINDINGS_OPTS   = fzf options for fzf_bindings() function.
--          FZF_COMPLETION_OPTS = fzf options for the completion functions
--                                (fzf_complete, fzf_menucomplete,
--                                fzf_selectcomplete, and etc).
--          FZF_COMPLETE_OPTS   = an older name for FZF_COMPLETION_OPTS.
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
--          If your terminal supports sixels and you configure fzf to use the
--          fzf-preview.cmd script, then you can set the environment variable
--          CLINK_FZF_PREVIEW_SIXELS to tell the fzf-preview.cmd script to tell
--          chafa to use sixels.  (Set it to any value except blank.)
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

-- luacheck: globals fzf_loader_arbiter
fzf_loader_arbiter = fzf_loader_arbiter or {}
if fzf_loader_arbiter.initialized then
    local msg = 'fzf.lua was already fully initialized'
    if fzf_loader_arbiter.loaded_source then
        msg = msg..' ('..fzf_loader_arbiter.loaded_source..')'
    end
    msg = msg..', but another copy got loaded later'
    local info = debug.getinfo(1, "S")
    local source = info and info.source or nil
    if source then
        msg = msg..' ('..source..')'
    end
    log.info(msg..'.')
    return
end

--------------------------------------------------------------------------------
-- Settings available via 'clink set'.
--
-- IMPORTANT:  These must be added upon load; attempting to defer this until
-- onbeginedit causes 'clink set' to not know about them.  This is the one part
-- of the script that can't fully support the goal of "newest version wins".

local function maybe_add(name, ...)
    if settings.get(name) == nil then
        settings.add(name, ...)
    end
end

maybe_add('fzf.height', '40%', 'Height to use for the --height flag')
maybe_add('fzf.exe_location', '', 'Location of fzf.exe if not on the PATH',
          "This isn't just a directory name, it's the full path name of the\n"..
          "exe file.  For example, c:\\tools\\fzf.exe or etc.")
maybe_add('fzf.allow_unsafe_query', false, 'Allow fzf.exe_location to not be an EXE file',
          "Allows the fzf.exe_location setting to not end in \".exe\".  In that\n"..
          "case, it tries to still provide strong security protections by stripping\n"..
          "unsafe characters from the input line before sending them to the non-exe\n"..
          "fzf program.")

if console.cellcount and console.plaintext then
    maybe_add('fzf.show_descriptions', true, 'Show match descriptions when available',
              'When enabled, fzf also searches in the match description text.')
    maybe_add('fzf.color_descriptions', false, 'Apply color to match descriptions when shown',
              'Uses the color defined in the color.description setting, and adds\n'..
              'the --ansi flag when invoking fzf.')
end

if rl.setbinding then
    maybe_add(
        'fzf.default_bindings',
        false,
        'Use default key bindings',
        'To avoid interference with your existing key bindings, key bindings for\n'..
        'fzf are initially not enabled.  Set this to true to enable the default\n'..
        'key bindings for fzf, or add bindings manually to your .inputrc file.\n\n'..
        'Changing this takes effect for the next Clink session.')
end

--------------------------------------------------------------------------------
-- Helpers.

local diag = false
local fzf_complete_intercept = false
local describemacro_list = {}
local interceptor

local function join_str(a, b)
    a = a or ''
    b = b or ''
    if a == '' then
        return b
    elseif b == '' then
        return a
    else
        return a..' '..b
    end
end

local function sgr(code)
    if not code then
        return '\x1b[m'
    elseif string.byte(code) == 0x1b then
        return code
    else
        return '\x1b['..code..'m'
    end
end

local function describe_commands()
    if describemacro_list then
        for _, d in ipairs(describemacro_list) do
            rl.describemacro(d.macro, d.desc)
        end
        describemacro_list = nil
    end
end

local function add_help_desc(macro, desc)
    if rl.describemacro and describemacro_list then
        table.insert(describemacro_list, { macro=macro, desc=desc })
    end
end

local function fix_unsafe_quotes(s)
    local fixed = ''
    local i = 1
    while i <= #s do
        -- Find open quote.  If none, all is well.
        local j = string.find(s, '"', i)
        if j then
            fixed = fixed..s:sub(i, j - 1)
        else
            fixed = fixed..s:sub(i)
            break
        end
        i = j + 1

        -- Find close quote.
        local t
        local k = string.find(s, '"', i)
        if k then
            t = s:sub(i, k - 1)
        else
            t = s:sub(i)
        end
        if t:find('[ +=;,]') then
            -- Convert the quotes, otherwise they can lead to CMD malfunctions
            -- if fzf later passes the description to another program (such as
            -- a preview script).
            if k then
                --fixed = fixed.."''"..t.."''"
                fixed = fixed.."“"..t.."”"
            else
                --fixed = fixed.."''"..t
                fixed = fixed.."”"..t
            end
        else
            -- The quotes are fine, so don't convert them.
            if k then
                fixed = fixed..'"'..t..'"'
            else
                fixed = fixed..'"'..t
            end
        end

        -- Next.
        if not k then
            break
        end
        i = k + 1
    end
    return fixed
end

local function need_cd_drive(dir)
    local drive = path.getdrive(dir)
    if drive then
        local cwd = os.getcwd()
        if cwd ~= "" then
            local cwd_drive = path.getdrive(cwd)
            if cwd_drive and cwd_drive:lower() == drive:lower() then
                return
            end
        end
    end
    return drive
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

local function make_query_string(rl_buffer, unsafe)
    local s = rl_buffer:getbuffer()

    -- Must strip % because there's no way to escape % when the command line
    -- gets processed first by cmd, as it does when using io.popen() and etc.
    -- This is the only thing that gets dropped; everything else gets escaped.
    s = s:gsub('%%', '')

    -- If the fzf command name isn't an .exe file then it may be able to safely
    -- handle certain characters in the query string.  In that case, strip them,
    -- and rely on fzf's fuzzy matching.
    if unsafe then
        s = s:gsub('[%%+=;,^|&<>"]', '')
        s = s:gsub('\\+$', '')
    elseif #s > 0 then
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
    end

    if #s > 0 then
        s = '--query "'..s..'"'
    end

    return s
end

local function get_fzf(mode, addl_options)
    local command = settings.get('fzf.exe_location')
    if not command or command == '' then
        command = 'fzf.exe'
    end
    command = command:gsub('"', '')

    -- It's important to invoke an .exe file, otherwise quoting for --query can
    -- malfunction and potentially fall into a code injection situation.  But if
    -- a non-exe file is specified and the fzf.allow_unsafe_query setting is
    -- enabled, then allow the non-exe file and compensate by stripping certain
    -- unsafe characters from the query string.
    local unsafe
    if settings.get('fzf.allow_unsafe_query') then
        unsafe = (path.getextension(command):lower() ~= ".exe")
    elseif path.getname(command) ~= command then
        local command_path = path.toparent(command)
        command = path.join(command_path, path.getbasename(command)..".exe")
    else
        command = path.getbasename(command)..".exe"
    end

    command = '"'..command..'"'

    local height = settings.get('fzf.height')
    if height and height ~= '' then
        command = join_str(command, '--height '..height)
    end

    command = join_str(command, addl_options)

    local options = os.getenv('FZF_DEFAULT_OPTS')
    if mode == 'complete' then
        options = join_str('--reverse', options)
        options = join_str(options, os.getenv('FZF_COMPLETION_OPTS') or os.getenv('FZF_COMPLETE_OPTS'))
    elseif mode == 'dirs' then
        options = join_str('--reverse --scheme=path', options)
        options = join_str(options, os.getenv('FZF_ALT_C_OPTS'))
    elseif mode == 'path' then
        options = join_str('--reverse --scheme=path', options)
        options = join_str(options, os.getenv('FZF_CTRL_T_OPTS'))
    elseif mode == 'history' then
        options = join_str('--scheme=history --bind=ctrl-r:toggle-sort', options)
        options = join_str(options, os.getenv('FZF_CTRL_R_OPTS'))
        options = join_str(options, '+m')
    elseif mode == 'bindings' then
        options = join_str(options, os.getenv('FZF_BINDINGS_OPTS'))
        options = join_str(options, '-i')
    else
        error('Unrecognized mode ('..tostring(mode)..').')
    end

    if options then
        command = join_str(command, options)
    end

    return command, unsafe
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
        if word:sub(-1) == "\\" then
            -- Double any trailing backslashes, per Windows quoting rules.
            word = word .. word:match("\\+$")
        end
        word = '"' .. word .. '"'
    end
    return word
end

local function escape_quotes(text)
    return text:gsub('"', '\\"')
end

local function chcp(cp)
    local ret
    if cp == 65001 then
        local r = io.popen('2>nul chcp')
        if r then
            local line = r:read()
            ret = line:match('%d+')
            r:close()
            cp = '65001'
        end
    end
    if type(cp) == 'string' then
        os.execute('>nul 2>nul chcp '..cp)
    end
    return ret
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

local function insert_matches(rl_buffer, first, last, has_quote, matches)
    if matches and matches[1] then
        local quote = has_quote or '"'

        rl_buffer:beginundogroup()
        rl_buffer:remove(first, last + 1)
        rl_buffer:setcursor(first)

        for _,match in ipairs(matches) do
            match = maybe_strip_icon(match)
            local use_quote = ((has_quote or need_quote(match)) and quote) or ''
            rl_buffer:insert(use_quote)
            rl_buffer:insert(match)
            rl_buffer:insert(use_quote)
            rl_buffer:insert(' ')
        end

        rl_buffer:endundogroup()
    end
end

local function fzf_recursive(rl_buffer, line_state, search, dirs_only) -- luacheck: no unused
    local dir, word
    dir = path.getdirectory(search)
    word = path.getname(search)

    local command, mode
    if dirs_only then
        command = get_alt_c_command(dir)
        mode = 'dirs'
    else
        command = get_ctrl_t_command(dir)
        mode = 'complete'
    end

    local first, last, has_quote, delimit = get_word_insert_bounds(line_state) -- luacheck: no unused

    local orig_cp = chcp(65001)

    local r = io.popen('2>nul '..command..' | '..get_fzf(mode)..' -q "'..word..'"')
    if not r then
        rl_buffer:ding()
        chcp(orig_cp)
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
    chcp(orig_cp)

    if match then
        insert_matches(rl_buffer, first, last, has_quote, { match })
    end
end

-- luacheck: globals fzf_complete_internal
function fzf_complete_internal(rl_buffer, line_state, force, completion_command)
    local search = is_trigger(line_state)
    if completion_command == '' then
        completion_command = nil
    end
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

-- Get binding for Tab, so that fzf_tab can forward to it.
local tab_binding = "complete"
if rl.getbinding then
    local tab = rl.getbinding([["\t"]])
    if tab == "complete" or
            tab == "menu-complete" or tab == "menu-complete-backward" or
            tab == "old-menu-complete" or tab == "old-menu-complete-backward" or
            tab == "clink-select-complete" or tab == "clink-popup-complete" then
        tab_binding = tab
    end
end

local function apply_default_bindings()
    if settings.get('fzf.default_bindings') then
        tab_binding = rl.getbinding([["\t"]])
        for _, keymap in ipairs({"emacs", "vi-command", "vi-insert"}) do
            rl.setbinding([["\C-t"]], [["luafunc:fzf_file"]], keymap)
            rl.setbinding([["\C-r"]], [["luafunc:fzf_history"]], keymap)
            rl.setbinding([["\M-c"]], [["luafunc:fzf_directory"]], keymap)
            rl.setbinding([["\M-b"]], [["luafunc:fzf_bindings"]], keymap)
            rl.setbinding([["\t"]], [["luafunc:fzf_tab"]], keymap)
            rl.setbinding([["\e[27;5;32~"]], [["luafunc:fzf_complete_force"]], keymap)
        end
    end
end

-- luacheck: globals fzf_complete
add_help_desc("luafunc:fzf_complete",
              "Use fzf for completion if ** is immediately before the cursor position")
function fzf_complete(rl_buffer, line_state)
    fzf_complete_internal(rl_buffer, line_state, false)
end

-- luacheck: globals fzf_menucomplete
add_help_desc("luafunc:fzf_menucomplete",
              "Use fzf for completion after ** otherwise use 'menu-complete' command")
function fzf_menucomplete(rl_buffer, line_state)
    fzf_complete_internal(rl_buffer, line_state, false, "menu-complete")
end

-- luacheck: globals fzf_oldmenucomplete
add_help_desc("luafunc:fzf_oldmenucomplete",
              "Use fzf for completion after ** otherwise use 'old-menu-complete' command")
function fzf_oldmenucomplete(rl_buffer, line_state)
    fzf_complete_internal(rl_buffer, line_state, false, "old-menu-complete")
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

-- luacheck: globals fzf_tab
add_help_desc("luafunc:fzf_tab",
              "Use fzf for completion if ** is immediately before the cursor position")
function fzf_tab(rl_buffer, line_state)
    fzf_complete_internal(rl_buffer, line_state, false, tab_binding)
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
    local fzf_command, unsafe = get_fzf('history', del_binding)
    local qs = make_query_string(rl_buffer, unsafe)
    local r = io.popen('2>nul '..history..' | '..fzf_command..' -i --tac '..qs)
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
        rl_buffer:insert(string.gsub(str, '^%s*%d+%s*(.-)$', '%1'))
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

    local first, last, has_quote, delimit = get_word_insert_bounds(line_state) -- luacheck: no unused

    local orig_cp = chcp(65001)

    local r = io.popen(command..' 2>nul | '..get_fzf('path')..' -i -m')
    if not r then
        rl_buffer:ding()
        chcp(orig_cp)
        return
    end

    local matches = {}
    for str in r:lines() do
        str = str and str:gsub('[\r\n]+', ' ') or ''
        str = str:gsub(' +$', '')
        if #str > 0 then
            table.insert(matches, str)
        end
    end

    r:close()
    chcp(orig_cp)

    insert_matches(rl_buffer, first, last, has_quote, matches)

    rl_buffer:refreshline()
end

-- luacheck: globals fzf_directory
add_help_desc("luafunc:fzf_directory",
              "List subdirectories; choose one to 'cd /d' to it")
function fzf_directory(rl_buffer, line_state)
    local dir = get_word_at_cursor(line_state)
    local command = get_alt_c_command(dir)

    local orig_cp = chcp(65001)

    local r = io.popen(command..' 2>nul | '..get_fzf('dirs')..' -i')
    if not r then
        rl_buffer:ding()
        chcp(orig_cp)
        return
    end

    local str = r:read('*all')
    str = str and str:gsub('[\r\n]', '') or ''

    r:close()
    chcp(orig_cp)

    if #str > 0 then
        str = maybe_strip_icon(str)
        rl_buffer:beginundogroup()
        rl_buffer:remove(0, -1)
        local drive = need_cd_drive(str)
        str = maybe_quote(str)
        if drive then
            rl_buffer:insert(drive..' & cd '..str)
        else
            rl_buffer:insert('cd '..str)
        end
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

    -- Start fzf.  Extra quotes are needed to work around CMD quoting issue.
    local line
    local r,w = io.popenrw('"'..get_fzf('bindings')..'"')
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

local function filter_matches(matches)
    if not fzf_complete_intercept then
        return
    end
    if #matches <= 1 then
        return
    end

    local show_descriptions = settings.get('fzf.show_descriptions')
    local color_description = settings.get('fzf.color_descriptions') and sgr(settings.get('color.description'))
    local norm = sgr()

    -- Match text to be displayed.
    local strings = {}
    local longest = 0
    local any_desc
    for _,m in ipairs(matches) do
        local s
        if m.display and console.plaintext then
            s = console.plaintext(m.display)
        else
            s = m.match
        end
        table.insert(strings, s)
        if show_descriptions then
            local cells = console.cellcount(s)
            if longest < cells then
                longest = cells
            end
            if m.description and m.description ~= '' then
                any_desc = true
            end
        end
    end

    -- Start fzf.  Extra quotes are needed to work around CMD quoting issue.
    local addl_options = (color_description and any_desc) and '--ansi' or nil
    local r,w = io.popenrw('"'..get_fzf('complete', addl_options)..'"')
    if not r or not w then
        return
    end

    -- Write matches to the write pipe.
    local which = {}
    for i,m in ipairs(matches) do
        local text = strings[i]
        if show_descriptions and m.description and m.description ~= '' then
            local desc = fix_unsafe_quotes(m.description)
            text = text..string.rep(' ', longest + 4 - console.cellcount(text))
            if color_description then
                text = text..color_description..desc..norm
            else
                text = text..console.plaintext(desc)
            end
        end
        -- Must use plaintext() because fzf always strips ANSI color codes when
        -- it writes the results, even when the --ansi flag is used.
        local plain = console.plaintext(text)
        if not which[plain] then
            which[plain] = m
        end
        w:write(text..'\n')
    end
    w:close()

    -- Read filtered matches.
    local ret = {}
    while (true) do
        local line = r:read('*line')
        if not line then
            break
        end
        local m = which[line]
        if m then
            table.insert(ret, m)
        end
    end
    r:close()

    -- Yay, successful; clear it to not ding.
    fzf_complete_intercept = false
    return ret
end

local function create_generator()
    if not interceptor then
        interceptor = clink.generator(0)
        function interceptor:generate(line_state, match_builder) -- luacheck: no unused
            if fzf_complete_intercept then
                -- Use two layers of onfiltermatches callbacks:
                --
                -- The generator runs early.  So the onfiltermatches callback
                -- function it registers is the first filter function.  But then
                -- other filter functions (e.g. to remove "hidden" matches) run
                -- AFTER fzf is invoked.  So fzf shows matches that should be
                -- hidden.  Oops.
                --
                -- To compensate, the first onfiltermatches callback function
                -- needs to register a second onfiltermatches callback function,
                -- which then ends up running LAST.  Then fzf doesn't list
                -- "hidden" matches.
                clink.onfiltermatches(function(matches)
                    clink.onfiltermatches(filter_matches)
                    return matches
                end)
            end
            return false
        end
    end
end

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
local infocommand = clink.argmatcher():addarg({fromhistory=true})
local ghosttext = clink.argmatcher():addarg({fromhistory=true})
local inputlabel = clink.argmatcher():addarg({fromhistory=true})
local inputlabelpos = clink.argmatcher():addarg({fromhistory=true})
local listlabel = clink.argmatcher():addarg({fromhistory=true})
local listlabelpos = clink.argmatcher():addarg({fromhistory=true})
local headerlabel = clink.argmatcher():addarg({fromhistory=true})
local headerlabelpos = clink.argmatcher():addarg({fromhistory=true})
local footerlabel = clink.argmatcher():addarg({fromhistory=true})
local footerlabelpos = clink.argmatcher():addarg({fromhistory=true})
local margin = clink.argmatcher():addarg({fromhistory=true, loopchars=',', '0', '1', '2'})
local padding = clink.argmatcher():addarg({fromhistory=true, loopchars=',', '0', '1', '2'})
local infostyle = addexarg(clink.argmatcher(), {
    nosort=true,
    { 'default',        'Display on the next line to the prompt' },
    { 'inline',         'Display on the same line as the prompt' },
    { 'hidden',         'Do not display finder info' },
})
local styles = addexarg(clink.argmatcher(), {
    nosort=true,
    { 'default',        'Borders between sections and around preview' },
    { 'minimal',        'Borders between sections' },
    { 'full',           'Borders around all sections' },
})
local prompt = clink.argmatcher():addarg({fromhistory=true, '"> "'})
local pointer = clink.argmatcher():addarg({fromhistory=true, '">"', '"*"'})
local marker = clink.argmatcher():addarg({fromhistory=true, '">"', '"*"'})
local multilinemarker = clink.argmatcher():addarg({fromhistory=true})
local header = clink.argmatcher():addarg({fromhistory=true})
local headerlines = clink.argmatcher():addarg({fromhistory=true})
local footer = clink.argmatcher():addarg({fromhistory=true})
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
local tailnum = clink.argmatcher():addarg({fromhistory=true})
local wrapsign = clink.argmatcher():addarg({fromhistory=true})
local numgap = clink.argmatcher():addarg({'0', '1', '2', '3', '4', '5'})
local freezeleft = clink.argmatcher():addarg({fromhistory=true})
local freezeright = clink.argmatcher():addarg({fromhistory=true})
local gutterchar = clink.argmatcher():addarg({fromhistory=true})
local gutterrawchar = clink.argmatcher():addarg({fromhistory=true})
local walkeropts = clink.argmatcher():addarg({
    nosort=true,
    'file',
    'file,follow',
    'file,follow,hidden',
    'file,hidden',
    'file,dir',
    'file,dir,follow',
    'file,dir,follow,hidden',
    'file,dir,hidden',
    'dir',
    'dir,follow',
    'dir,follow,hidden',
    'dir,hidden',
})
local walkerroot = clink.argmatcher()
walkerroot:addarg({
    clink.dirmatches,
    onlink=function(link, arg_index, word, word_index, line_state, user_data) -- luacheck: no unused
        local wc = line_state:getwordcount()
        if word_index < wc and not line_state:getword(word_index + 1):find("^%-") then
            -- The --walker-root flag accepts an unlimited number of dirs until
            -- another flag is encountered.
            return walkerroot
        end
    end,
})
local walkerskip = clink.argmatcher():addarg(clink.dirmatches)

local function create_argmatcher()
    local argmatcher = clink.argmatcher('fzf')
    if argmatcher.reset then
        argmatcher:reset()
    end

    addexflags(argmatcher, {
        opteq=true,
        -- SEARCH
        { '-e',                             'Enable Exact-match' },
        { '--exact',                        'Enable Exact-match' },
        { '-x',                             'Extended-search mode (enabled by default; +x or --no-extended to disable)' },
        { '+x',                             'Disable extended-search mode' },
        { '--extended',                     'Extended-search mode (enabled by default; +x or --no-extended to disable)' },
        { '--no-extended',                  'Disable extended-search mode' },
        { '-i',                             'Case-insensitive match (default: smart-case match; +i for case-sensitive match)' },
        { '+i',                             'Case-sensitive match' },
        { '--ignore-case',                  'Case-insensitive match (default: smart-case match; +i for case-sensitive match)' },
        { '--no-ignore-case',               'Case-sensitive match' },
        { '--smart-case',                   'Smart-case match (default); case-insensitive unless query contains uppercase' },
        { '--scheme='..scheme, 'SCHEME',    'Scoring scheme' },
        { '-n'..nth, ' N[,..]',             'Comma-separated list of field index expressions for limiting search scope (non-zero integer or range expression "1..4")' },
        { '--nth='..nth, 'N[,..]',          'Comma-separated list of field index expressions for limiting search scope (non-zero integer or range expression "1..4")' },
        { '--with-nth='..nth, 'N[,..]',     'Transform the presentation of each line using field index expressions' },
        { '--accept-nth='..nth, 'N[,..]',   'Define which fields to print on accept' },
        { '-d'..delim, ' STR',              'Field delimiter regex (default: AWK-style)' },
        { '--delimiter='..delim, 'STR',     'Field delimiter regex (default: AWK-style)' },
        { '+s',                             'Do not sort the result' },
        { '--no-sort',                      'Do not sort the result' },
        { '--literal',                      'Do not normalize latin script letters before matching' },
        { '--tail='..tailnum, 'NUM',        'Maximum number of items to keep in memory' },
        { '--disabled',                     'Do not perform search (simple selector interface)' },
        { '--tiebreak='..criteria, 'CRI[,..]', 'Comma-separated list of sort criteria to apply when the scores are tied (default: length)' },

        -- INPUT/OUTPUT
        { '--read0',                        'Read input delimited by ASCII NUL characters' },
        { '--print0',                       'Print output delimited by ASCII NUL characters' },
        { '--ansi',                         'Enable processing of ANSI color codes' },
        { '--sync',                         'Synchronous search for multi-staged filtering' },

        -- GLOBAL STYLE
        { '--style='..styles, 'PRESET',     'Apply a style preset' },
        { '--color='..colspec, 'COLSPEC',   'Base scheme and/or custom colors' },
        { '--black',                        'Use black background' },
        { '--no-color',                     'Disable colors' },
        { '--no-bold',                      'Do not use bold text' },
        { '--no-unicode',                   'Use ASCII characters instead of Unicode drawing characters' },

        -- DISPLAY MODE
        { '--height='..heights, 'HEIGHT[%]', 'Display fzf window below the cursor with the given height instead of using fullscreen' },
        { '--min-height='..minheight, 'HEIGHT', 'Minimum height when --height is given in percent (default: 10)' },
        { hide=true, '--tmux='..clink.argmatcher():addarg(), 'OPTS', '' },

        -- LAYOUT
        { '--layout='..layout, 'LAYOUT',    'Choose layout' },
        { '--reverse',                      'A synonym for --layout=reverse' },
        { '--margin='..margin, 'MARGIN',    'Screen margin (TRBL | TB,RL | T,RL,B | T,R,B,L)' },
        { '--padding='..padding, 'PADDING', 'Padding inside border (TRBL | TB,RL | T,RL,B | T,R,B,L)' },
        { '--border',                       'Draw border around the finder (default: rounded)' },
        { '--border='..borderstyle, 'STYLE', 'Draw border around the finder (default: rounded)', opteq=false },
        { '--border-label='..borderlabel, 'LABEL', 'Label to print on the border' },
        { '--border-label-pos='..borderlabelpos, 'N[:top|bottom]', 'Position of border label' },

        -- LIST SECTION
        { '-m',                             'Enable multi-select with tab/shift-tab' },
        { '--multi',                        'Enable multi-select with tab/shift-tab' },
        { '--multi='..multimax, 'MAX',      'Enable multi-select with tab/shift-tab', opteq=false },
        { '--highlight-line',               'Highlight the whole current line' },
        { '--cycle',                        'Enable cyclic scroll' },
        { '--wrap',                         'Enable line wrap' },
        { '--wrap-sign='..wrapsign, 'STR',  'Indicator for wrapped lines' },
        { '--no-multi-line',                'Disable multi-line display of items when using --read0' },
        { '--raw',                          'Enable raw mode (show non-matching items)' },
        { '--track',                        'Track the current selection when the result is updated' },
        { '--tac',                          'Reverse the order of the input' },
        { '--gap',                          'Render empty line between each item' },
        { '--gap='..numgap, 'N',            'Render N empty lines between each item', opteq=false },
        { '--gap-line',                     'Draw horizontal line on each gap' },
        { '--gap-line=',                     'Draw horizontal line on each gap' },
        { '--freeze-left='..freezeleft, 'N', 'Number of fields to freeze on the left' },
        { '--freeze-right='..freezeright, 'N', 'Number of fields to freeze on the right' },
        { '--keep-right',                   'Keep the right end of the line visible on overflow' },
        { '--scroll-off='..scrolloff, 'LINES', 'Number of screen lines to keep above or below when scrolling to the top or to the bottom (default: 0)' },
        { '--no-hscroll',                   'Disable horizontal scroll' },
        { '--hscroll-off='..hscrolloff, 'COLS', 'Number of screen columns to keep to the right of the highlighted substring (default: 10)' },
        { '--jump-labels='..jumplabels, 'CHARS', 'Label characters for jump and jump-accept' },
        { '--gutter='..gutterchar, 'CHAR',  'Character used in the gutter column' },
        { '--gutter-raw='..gutterrawchar, 'CHAR',  'Character used in the gutter column in raw mode' },
        { '--pointer='..pointer, 'STR',     'Pointer to the current line (default: \'>\')' },
        { '--marker='..marker, 'STR',       'Multi-select marker (default: \'>\')' },
        { '--marker-multi-line='..multilinemarker, 'STR', 'Multi-select marker for multi-line entries (3 elements for top, middle, and bottom)' },
        { '--ellipsis='..ellipsis, 'STR',   'Ellipsis to show when line is truncated (default: \'..\')' },
        { '--tabstop='..tabstop, 'SPACES',  'Number of spaces for a tab character (default: 8)' },
        { '--scrollbar',                    'Show scrollbar' },
        { '--scrollbar='..scrollbarchars, 'C1[C2]', 'Scrollbar character for main [and preview] window', opteq=false },
        { '--no-scrollbar',                 'Hide scrollbar' },
        { '--list-border',                  'Draw border around the list section' },
        { '--list-border='..borderstyle, 'STYLE', 'Draw border around the list section', opteq=false },
        { '--list-label='..listlabel, 'LABEL', 'Label to print on the list border' },
        { '--list-label-pos='..listlabelpos, 'N[:top|bottom]', 'Position of the list label' },

        -- INPUT SECTION
        { '--no-input',                     'Disable and hide the input section' },
        { '--no-mouse',                     'Disable mouse' },
        { '--prompt='..prompt, 'STR',       'Input prompt (default: \'> \')' },
        { '--info='..infostyle, 'STYLE',    'Finder info style' },
        { '--no-info',                      'Hide the finder info (synonym for --info=hidden)' },
        { '--info-command='..infocommand, 'COMMAND', 'Command to generate info line' },
        { '--separator='..separatorstr, 'STR', 'Hide info line separator' },
        { '--no-separator',                 'Hide info line separator' },
        { '--ghost='..ghosttext, 'TEXT',    'Ghost text to display when the input is empty' },
        { '--filepath-word',                'Make word-wise movements respect path separators' },
        { '--input-border',                 'Draw border around the input section' },
        { '--input-border='..borderstyle, 'STYLE', 'Draw border around the input section', opteq=false },
        { '--input-label='..inputlabel, 'LABEL', 'Label to print on the input border' },
        { '--input-label-pos='..inputlabelpos, 'N[:top|bottom]', 'Position of label on the input border' },

        -- PREVIEW WINDOW
        { '--preview='..previewcommand, 'COMMAND', 'Command to preview highlighted line ({})' },
        { '--preview-window='..previewopt, 'OPTS', 'Preview window layout (default: right,50%)' },
        { '--preview-border',               'Draw border around the preview window' },
        { '--preview-border='..borderstyle, 'STYLE', 'Draw border around the preview window', opteq=false },
        { '--preview-label='..previewlabel, 'LABEL', 'Label to print on preview window border' },
        { '--preview-label-pos='..previewlabelpos, 'N[:top|bottom]', 'Position of label on preview window border' },

        -- HEADER
        { '--header='..header, 'STR',       'String to print as header' },
        { '--header-lines='..headerlines, 'N', 'The first N lines of the input are treated as header' },
        { '--header-first',                 'Print header before the prompt line' },
        { '--header-border',                'Draw border around the header section' },
        { '--header-border='..borderstyle, 'STYLE', 'Draw border around the header section', opteq=false },
        { '--header-lines-border',          'Display header from --header-lines with a separate border' },
        { '--header-lines-border='..borderstyle, 'STYLE', 'Display header from --header-lines with a separate border', opteq=false },
        { '--header-label='..headerlabel, 'LABEL', 'Label to print on the header border' },
        { '--header-label-pos='..headerlabelpos, 'N[:top|bottom]', 'Position of label on the header border' },

        -- FOOTER
        { '--footer='..footer, 'STR',       'String to print footer' },
        { '--footer-border',                'Draw border around the footer section' },
        { '--footer-border='..borderstyle, 'STYLE', 'Draw border around the footer section', opteq=false },
        { '--footer-label='..footerlabel, 'LABEL', 'Label to print on the footer border' },
        { '--footer-label-pos='..footerlabelpos, 'N[:top|bottom]', 'Position of label on the footer border' },

        -- SCRIPTING
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

        -- KEY/EVENT BINDING
        { '--bind='..keybinds, 'KEYBINDS',  'Custom key bindings. Refer to the man page' },

        -- ADVANCED
        { hide=true, '--with-shell='..clink.argmatcher():addarg() },
        { hide=true, '--listen='..clink.argmatcher():addarg() },

        -- DIRECTORY TRAVERSAL
        { '--walker='..walkeropts, 'OPTS',  'Options for directory traversal when FZF_DEFAULT_COMMAND is not set' },
        { '--walker-root='..walkerroot, 'DIR [...]', 'List of directories to walk (default: .)' },
        { '--walker-skip='..walkerskip, 'DIRS', 'Comma-separated list of directory names to skip' },

        -- HISTORY
        { '--history=', 'FILE',             'History file' },
        { '--history-size='..historysize, 'N', 'Maximum number of history entries (default: 1000)' },

        -- SHELL INTEGRATION
        { hide=true, '--bash' },
        { hide=true, '--zsh' },
        { hide=true, '--fish' },

        -- HELP
        { '--version',                      'Display version information and exit' },
        { '-h',                             'Display help text' },
        { '--help',                         'Display help text' },
        --man

        -- ...LEFTOVER...
        { '--algo='..algos, 'TYPE',         'Fuzzy matching algorithm' },
    })
end

--------------------------------------------------------------------------------
-- Delayed initialization shim.  Check for multiple copies of the script being
-- loaded in the same session.  This became necessary because Cmder wanted to
-- include fzf.lua, but users may have already installed a separate copy of the
-- script.


-- luacheck: globals fzf_complete
if fzf_complete and (clink.version_encoded or 0) < 10030010 then
    -- argmatcher:reset() from v1.3.10 is needed in order supersede an
    -- existing fzf argument.
    log.info('An old fzf.lua is already loaded, and Clink 1.3.10 or newer is required to supersede it.')
    return
end

fzf_loader_arbiter.ensure_initialized = function()
    assert(not fzf_loader_arbiter.initialized)

    describe_commands()
    apply_default_bindings()
    create_generator()
    create_argmatcher()

    local info = debug.getinfo(1, "S")
    local source = info and info.source or nil

    fzf_loader_arbiter.initialized = true
    fzf_loader_arbiter.loaded_source = source
end

clink.onbeginedit(function ()
    -- Do delayed initialization if it hasn't happened yet.
    if fzf_loader_arbiter.ensure_initialized then
        fzf_loader_arbiter.ensure_initialized()
        fzf_loader_arbiter.ensure_initialized = nil
    end

    -- Reset the fzf completion hook.
    fzf_complete_intercept = false
end)

