--------------------------------------------------------------------------------
-- FZF git integration for Clink.
-- Based on https://github.com/junegunn/fzf-git.sh
--
--
-- This provides Clink key bindings for git objects, powered by fzf.
--
-- Each key binding allows you to browse through git objects of a certain type,
-- and select the objects you want to insert into your command line.
--
--      Ctrl-G,?        : Show key bindings for fzf_git
--      Ctrl-G,Ctrl-F   : Use fzf for Files
--      Ctrl-G,Ctrl-B   : Use fzf for Branches
--      Ctrl-G,Ctrl-T   : Use fzf for Tags
--      Ctrl-G,Ctrl-R   : Use fzf for Remotes
--      Ctrl-G,Ctrl-H   : Use fzf for commit Hashes
--      Ctrl-G,Ctrl-S   : Use fzf for Stashes
--      Ctrl-G,Ctrl-L   : Use fzf for reflogs
--      Ctrl-G,Ctrl-W   : Use fzf for Worktrees
--      Ctrl-G,Ctrl-E   : Use fzf for Each ref (git for-each-ref)
--
--
-- REQUIREMENTS:
--
-- This requires Clink, FZF, and git:
--
--  - Clink is available at https://chrisant996.github.io/clink
--  - FZF is available from https://github.com/junegunn/fzf
--    (version 0.67.0 or newer work; older versions may or may not work)
--  - Git is available from https://git-scm.com/install
--    (version 2.48.1 or newer work; older versions may or may not work)
--
--
-- DEFAULT KEY BINDINGS:
--
-- The default key bindings are listed below in a format suitable for pasting
-- into your .inputrc file for convenience, for example if you want to modify
-- any of the bindings.  The default bindings can be disabled by running
-- 'clink set fzf_git.default_bindings false'.
--
-- luacheck: no max line length
--[[

# Default key bindings for fzf_git with Clink.

# Help bindings.
"\C-g?":            "luafunc:fzf_git_help"              # Ctrl-G,?
"\C-g\e[27;5;191~": "luafunc:fzf_git_help"              # Ctrl-G,Ctrl-/

# Ctrl-Letter bindings.
"\C-g\C-f":         "luafunc:fzf_git_files"             # Ctrl-G,Ctrl-F
"\C-g\C-b":         "luafunc:fzf_git_branches"          # Ctrl-G,Ctrl-B
"\C-g\C-t":         "luafunc:fzf_git_tags"              # Ctrl-G,Ctrl-T
"\C-g\C-r":         "luafunc:fzf_git_remotes"           # Ctrl-G,Ctrl-R
"\C-g\C-h":         "luafunc:fzf_git_commit_hashes"     # Ctrl-G,Ctrl-H
"\C-g\C-s":         "luafunc:fzf_git_stashes"           # Ctrl-G,Ctrl-S
"\C-g\C-l":         "luafunc:fzf_git_reflogs"           # Ctrl-G,Ctrl-L
"\C-g\C-w":         "luafunc:fzf_git_worktrees"         # Ctrl-G,Ctrl-W
"\C-g\C-e":         "luafunc:fzf_git_eachref"           # Ctrl-G,Ctrl-E

# Plain Letter bindings.
"\C-g\f":           "luafunc:fzf_git_files"             # Ctrl-G,F
"\C-g\b":           "luafunc:fzf_git_branches"          # Ctrl-G,B
"\C-g\t":           "luafunc:fzf_git_tags"              # Ctrl-G,T
"\C-g\r":           "luafunc:fzf_git_remotes"           # Ctrl-G,R
"\C-g\h":           "luafunc:fzf_git_commit_hashes"     # Ctrl-G,H
"\C-g\s":           "luafunc:fzf_git_stashes"           # Ctrl-G,S
"\C-g\l":           "luafunc:fzf_git_reflogs"           # Ctrl-G,L
"\C-g\w":           "luafunc:fzf_git_worktrees"         # Ctrl-G,W
"\C-g\e":           "luafunc:fzf_git_eachref"           # Ctrl-G,E

]]
-- CLINK SETTINGS:
--
-- The available settings are as follows.
-- These settings can be controlled via 'clink set'.
--
--      fzf_git.default_bindings    Controls whether to apply default
--                                  bindings.  This is true by default.
--
--
-- ENVIRONMENT VARIABLES:
--
-- You can optionally set the following environment variables to customize the
-- behavior.
--
--          BAT_STYLE               = Defines what will be passed to BAT via
--                                    its '--style="..."' flag.
--
--          FZF_GIT_CAT             = Defines the preview command used for
--                                    displaying the file.
--          FZF_GIT_COLOR           = Control colors in the list:
--                                    'always' (default) shows colors.
--                                    'never' suppresses colors.
--          FZF_GIT_PAGER           = Specifies the pager command for the
--                                    preview window.
--          FZF_GIT_PREVIEW_COLOR   = Control colors in the preview window:
--                                    'always' (default) shows colors.
--                                    'never' suppresses colors.
--
--          FZF_GIT_DEFAULT_COLORS  = Defines the default colors for fzf.
--                                    This is passed to fzf via the --color
--                                    flag.
--          FZF_GIT_EDITOR          = Defines the command for editing a file.
--                                    Falls back to %EDITOR% or notepad.exe if
--                                    not set.
--
--
-- KNOWN ISSUES:
--
--  - Ctrl-D in fzf_git_commit_hashes prints no output and doesn't allow
--    input to the pager.  This is an fzf bug, which is tracked in:
--    https://github.com/junegunn/fzf/issues/4260#issuecomment-3931448651
--  - In a shallow clone, fzf_git_files expands the sparse index to a full
--    index.  I'd like to somehow scope fzf_git_files better, but I'm not sure
--    what would be a good solution.
--  - If multiple copies of this script are loaded in the same Clink session,
--    the last one loaded takes responsibility to initialize itself, and the
--    others are ignored.

--------------------------------------------------------------------------------
-- Compatibility check.

if (clink.version_encoded or 0) < 10070000 then
    -- The git functions are needed from v1.7.0.
    print('fzf_git.lua requires a newer version of Clink; please upgrade.')
    return
end

-- luacheck: globals fzf_git_loader_arbiter
fzf_git_loader_arbiter = fzf_git_loader_arbiter or {}
if fzf_git_loader_arbiter.initialized then
    local msg = 'fzf_git.lua was already fully initialized'
    if fzf_git_loader_arbiter.loaded_source then
        msg = msg..' ('..fzf_git_loader_arbiter.loaded_source..')'
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

if rl.setbinding then
    maybe_add(
        'fzf_git.default_bindings',
        true,
        'Use default key bindings for fzf_git integration',
        'Set this to false if it interferes with your existing key bindings, and\n'..
        'you can add bindings manually to your .inputrc file.\n\n'..
        'Changing this takes effect for the next Clink session.')
end

--------------------------------------------------------------------------------
-- REVIEW:  what does the $(__fzf_git_pager) usage accomplish in fzf-git.sh?
--[=[
__fzf_git_pager() {
  local pager
  pager="${FZF_GIT_PAGER:-${GIT_PAGER:-$(git config --get core.pager 2> /dev/null)}}"
  echo "${pager:-cat}"
}
--]=]

--------------------------------------------------------------------------------
-- Helpers.

local diag

local describemacro_list = {}
local specific_hash
local __fzf_git_sh_path
local __fzf_git_cmd_path
local __fzf_git_cat_command

local function __fzf_git_color(preview)
    if os.getenv("NO_COLOR") then
        return "never"
    elseif preview and os.getenv("FZF_GIT_PREVIEW_COLOR") then
        return os.getenv("FZF_GIT_PREVIEW_COLOR")
    else
        local color = os.getenv("FZF_GIT_COLOR")
        return (color ~= "" and color or "always")
    end
end

local function __fzf_git_editor()
    return os.getenv("FZF_GIT_EDITOR") or os.getenv("EDITOR") or "notepad.exe"
end

local function search_in_paths(name)
    local paths = (os.getenv("path") or ""):explode(";")
    for _, dir in ipairs(paths) do
        local file = path.join(dir, name)
        if os.isfile(file) then
            return file, dir
        end
    end
end

local function get_git_bin_dir()
    local _, dir = search_in_paths("git.exe")
    if dir then
        dir = path.join(path.toparent(dir), "usr\\bin")
        if os.isfile(path.join(dir, "bash.exe")) then
            return dir
        end
    end
end

local function ensure_script_paths()
    if not __fzf_git_sh_path then
        local info = debug.getinfo(1, "S")
        if info.source and info.source:sub(1, 1) == "@" then
            local dir = path.toparent(info.source:sub(2))
            __fzf_git_sh_path = path.join(dir, "fzf_git_helper.sh")
            if not os.isfile(__fzf_git_sh_path) then
                log.info(string.format("File does not exist at '%s'.", __fzf_git_sh_path))
                __fzf_git_sh_path = nil
            end
            __fzf_git_cmd_path = path.join(dir, "fzf_git_helper.cmd")
            if not os.isfile(__fzf_git_cmd_path) then
                log.info(string.format("File does not exist at '%s'.", __fzf_git_cmd_path))
                __fzf_git_cmd_path = nil
            end
        elseif info.source then
            log.info(string.format("Unexpected source path '%s'.", info.source))
        else
            log.info(string.format("Unable to get source path for script."))
        end
    end
    return __fzf_git_sh_path and __fzf_git_cmd_path and true or nil
end

local function __fzf_git_sh()
    ensure_script_paths()
    return __fzf_git_sh_path
end

local function __fzf_git_cmd()
    ensure_script_paths()
    return __fzf_git_cmd_path
end

local function __fzf_git_cat()
    local cat = os.getenv("FZF_GIT_CAT")
    if cat then
        return cat
    end

    if __fzf_git_cat_command == nil then
        local def_style = os.getenv("BAT_STYLE") or "full"
        local def_color = __fzf_git_color(true)
        local def_opts = "--style=\""..def_style.."\" --color="..def_color.." --pager=never"

        -- Sometimes bat is installed as batcat
        cat = search_in_paths("batcat.exe")
        if not cat then
            cat = search_in_paths("bat.exe")
        end
        if cat then
            cat = cat.." "..def_opts
        else
            cat = "type"
        end
        __fzf_git_cat_command = cat
    end

    return __fzf_git_cat_command
end

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

local function _fzf_git_fzf(args)
    -- The fzf command path.
    local command = settings.get('fzf.exe_location')
    if not command or command == '' then
        command = 'fzf.exe'
    end
    command = command:gsub('"', '')
    command = '"'..command..'"'

    -- The fzf_git options for fzf.
    -- luacheck: globals __fzf_git_fzf
    local opts
    local def_colors = os.getenv("FZF_GIT_DEFAULT_COLORS") or "label:blue"
    local def_opts =
        '--height 50% --tmux 90%,70% '..
        '--layout reverse --multi --min-height 20+ --border rounded '..
        '--no-separator --header-border horizontal '..
        '--border-label-pos 2 '..
        '--color "'..def_colors..'" '..
        '--preview-window "right,50%" --preview-border line '..
        '--bind "ctrl-/:change-preview-window(down,50%|hidden|)" '..
        '--bind "shift-down:preview-down+preview-down,shift-up:preview-up+preview-up,preview-scroll-up:preview-up+preview-up,preview-scroll-down:preview-down+preview-down" '..
        ''
    if type(__fzf_git_fzf) == "function" then
        opts = __fzf_git_fzf(def_opts)
    elseif type(__fzf_git_fzf) == "string" then
        opts = __fzf_git_fzf
    end
    opts = opts or def_opts

    -- The additional args for fzf.
    opts = join_str(opts, args)

    return command, opts
end

local function git_check()
    -- git_check is the first thing to run in every command, so this is a
    -- great place to reinitialize the diag variable.
    diag = (tonumber(os.getenv("DEBUG_FZF_GIT") or "0") or 0) > 0

    local gitdir = git.getgitdir()
    if gitdir and path.getname(gitdir) == ".git" then
        return true
    end
end

local function need_quote(word)
    return word and word:find("[ &()[%]{}^=;!%%'+,`~]") and true
end

local function maybe_quote(word)
    if need_quote(word) then
        if word:sub(-1) == "\\" then
            -- Double any trailing backslashes, per Windows quoting rules.
            word = word..word:match("\\+$")
        end
        word = '"'..word..'"'
    end
    return word
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

local function insert_matches(rl_buffer, matches, post_process, expect)
    if matches and matches[1] then
        rl_buffer:beginundogroup()

        for _,match in ipairs(matches) do
            local text
            if not post_process then
                text = match
            else
                text = post_process(match, expect)
                -- nil = ignore the match.
                -- false = stop inserting matches.
                if text == false then
                    break
                end
            end
            if text then
                local q = need_quote(text) and '"' or ''
                rl_buffer:insert(q..text..q..' ')
            end
            expect = nil
        end

        rl_buffer:endundogroup()
    end
end

local function fix_single_quotes(s)
    local in_quote
    local ignore_quote
    local double_single_quote = 0
    local out = ""
    for i = 1, #s do
        local c = string.byte(s, i)
        if c == 39 then                 -- Single quote.
            ignore_quote = nil
            if in_quote then
                if double_single_quote > 0 then
                    double_single_quote = double_single_quote - 1
                    out = out..'\\"\\"'
                else
                    out = out..'\\"'
                end
            else
                out = out..'"'
            end
        elseif c == 92 then             -- Backslash.
            out = out..string.char(c)
            ignore_quote = (string.byte(s, i + 1) == 34)
        else
            out = out..string.char(c)
            if c == 34 and not ignore_quote then
                in_quote = not in_quote
            elseif c == 32 and in_quote and (string.byte(s, i + 1) == 39) then
                double_single_quote = 2
            end
            ignore_quote = nil
        end
    end
    return out
end

local function apply_replacements(command, fix_single_quotes_in_command)
    -- print("APPLY_REPLACEMENTS chkpt 1", command)
    if fix_single_quotes_in_command then
        command = fix_single_quotes(command)
    -- print("APPLY_REPLACEMENTS chkpt 2", command)
    end
    if not command:find("preview \"%$helper") then
        command = command:gsub("preview \"(.+[^\\])\"", "preview \"bash -c '%1'\"")
    end
    command = command:gsub("%$shell", "bash")
    command = command:gsub("%$helper", __fzf_git_cmd():gsub("\\", "\\\\"))
    command = command:gsub("/dev/tty", "con")
    command = command:gsub("%$__fzf_git", __fzf_git_sh():gsub("\\", "\\\\"))
    command = command:gsub("%$%(__fzf_git_color%)", __fzf_git_color())
    command = command:gsub("%$%(__fzf_git_color %.%)", __fzf_git_color(true))
    command = command:gsub("\\\n%s*", "")
    -- print("APPLY_REPLACEMENTS chkpt 3", command)
    return command
end

local function run_command(command, expect)
    if diag then
        print("RUN_COMMAND", command)
    end

    local r = io.popen(command)
    if not r then
        log.info("failed to run command:  "..command)
        return
    end

    local matches = {}
    for str in r:lines() do
        str = str and str:gsub('[\r\n]+', ' ') or ''
        str = str:gsub(' +$', '')
        if expect or str ~= "" then
            table.insert(matches, str)
        end
        expect = nil
    end

    r:close()

    return matches
end

local function do_fzf_git(rl_buffer, line_state, pipe_command, fzf_args, post_process) -- luacheck: no unused
    if not git_check() then
        rl_buffer:ding()
        return
    end

    if not ensure_script_paths() then
        rl_buffer:beginoutput()
        print("fzf_git error:  Unable to find support scripts; see clink.log for details.")
        return
    end

    local usrbin = get_git_bin_dir()
    if not usrbin then
        print("fzf_git error:  Unable to find git\\usr\\bin directory.")
        return
    end

    local expect = fzf_args:find("%-%-expect=") and true or nil

    fzf_args = apply_replacements(fzf_args)--, true--[[fix_single_quotes]])
    local program, options = _fzf_git_fzf(fzf_args)

    local orig_cp = chcp(65001)
    local old___fzf_git_color = os.getenv("__fzf_git_color")
    local old___fzf_git_color_ = os.getenv("__fzf_git_color_")
    local old___fzf_git_cat = os.getenv("__fzf_git_cat")
    local old___fzf_git_editor = os.getenv("__fzf_git_editor")
    local old___fzf_git_sh = os.getenv("__fzf_git_sh")
    local old_fzf_default_opts = os.getenv("FZF_DEFAULT_OPTS")
    local old_path = os.getenv("PATH")

    os.setenv("__fzf_git_color", __fzf_git_color())
    os.setenv("__fzf_git_color_", __fzf_git_color(true))
    os.setenv("__fzf_git_cat", __fzf_git_cat())
    os.setenv("__fzf_git_editor", __fzf_git_editor())
    os.setenv("__fzf_git_sh", __fzf_git_sh())
    os.setenv("FZF_DEFAULT_OPTS", join_str(old_fzf_default_opts, options))

    -- Prepend the Git bin dir to the system PATH so that bash, awk, sed, and
    -- so on can be found automatically, without needing to adjust the command
    -- syntax copied from the fzf-git.sh script.
    os.setenv("PATH", usrbin..";"..old_path)

    if diag then
        print("FZF_DEFAULT_OPTS", os.getenv("FZF_DEFAULT_OPTS"))
    end

    local matches
    if type(pipe_command) == "function" then
        if diag then
            print("POPENRW", program)
        end

        -- Start fzf first so its UI shows up immediately; otherwise any delay
        -- looks like the input wasn't registered.
        local r,w = io.popenrw(program)
        if r and w then
            -- Write matches to the write pipe.
            local input = pipe_command()
            if input then
                if type(input) == "function" then
                    for line in input() do
                        w:write(line..'\n')
                    end
                else
                    for _, s in ipairs(input) do
                        w:write(s..'\n')
                    end
                end
            end
            w:close()

            -- Read filtered matches.
            local keep_blank = expect
            matches = {}
            for line in r:lines() do
                if keep_blank or line ~= "" then
                    table.insert(matches, line)
                end
                keep_blank = nil
            end
            r:close()
        end
    elseif pipe_command then
        pipe_command = apply_replacements(pipe_command)
        matches = run_command(pipe_command..' | '..program, expect)
    else
        matches = run_command(program, expect)
    end

    os.setenv("PATH", old_path)

    os.setenv("FZF_DEFAULT_OPTS", old_fzf_default_opts)
    os.setenv("__fzf_git_sh", old___fzf_git_sh)
    os.setenv("__fzf_git_editor", old___fzf_git_editor)
    os.setenv("__fzf_git_cat", old___fzf_git_cat)
    os.setenv("__fzf_git_color_", old___fzf_git_color_)
    os.setenv("__fzf_git_color", old___fzf_git_color)

    chcp(orig_cp)

    if matches then
        insert_matches(rl_buffer, matches, post_process, expect)
        rl_buffer:refreshline()
    else
        rl_buffer:ding()
    end
end

--------------------------------------------------------------------------------
-- Functions for use with 'luafunc:' key bindings.

-- IMPORTANT:  Using execute-silent is part of a workaround for a known bug in
-- fzf which eats the next character of input (e.g. the leading ESC from ESC[A
-- i.e. the Up arrow key).  Using execute has others problems anyway, at least
-- on Windows -- for example, nano and other terminal based editors can't run
-- because stdin is still redirected.  So, the helper script uses the start
-- command as part of the workaround.
local bind_alt_e_edit_file = [[--bind "alt-e:execute-silent:$helper edit_file {}" ]]
local bind_alt_e_edit_tree_file = [[--bind "alt-e:execute-silent:$helper edit_tree_file {}" ]]

-- luacheck: globals fzf_git_commit_hashes
fzf_git_commit_hashes = nil

local function rl_setbinding_both(key, binding, keymap)
    rl.setbinding(key, binding, keymap)
    local key_no_ctrl = key:match([[^("\C%-g)\C%-(.)"$]])
    if key_no_ctrl then
        rl.setbinding(key_no_ctrl, binding, keymap)
    end
end

local function apply_default_bindings()
    if settings.get('fzf_git.default_bindings') then
        for _, keymap in ipairs({"emacs", "vi-command", "vi-insert"}) do
            rl.setbinding([["\C-g?"]], [["luafunc:fzf_git_help"]], keymap)
            rl.setbinding([["\C-g\e[27;5;191~"]], [["luafunc:fzf_git_help"]], keymap)
            rl_setbinding_both([["\C-g\C-f"]], [["luafunc:fzf_git_files"]], keymap)
            rl_setbinding_both([["\C-g\C-b"]], [["luafunc:fzf_git_branches"]], keymap)
            rl_setbinding_both([["\C-g\C-t"]], [["luafunc:fzf_git_tags"]], keymap)
            rl_setbinding_both([["\C-g\C-r"]], [["luafunc:fzf_git_remotes"]], keymap)
            rl_setbinding_both([["\C-g\C-h"]], [["luafunc:fzf_git_commit_hashes"]], keymap)
            rl_setbinding_both([["\C-g\C-s"]], [["luafunc:fzf_git_stashes"]], keymap)
            rl_setbinding_both([["\C-g\C-l"]], [["luafunc:fzf_git_reflogs"]], keymap)
            rl_setbinding_both([["\C-g\C-w"]], [["luafunc:fzf_git_worktrees"]], keymap)
            rl_setbinding_both([["\C-g\C-e"]], [["luafunc:fzf_git_eachref"]], keymap)
        end
    end
end

-- luacheck: globals fzf_git_help
add_help_desc("luafunc:fzf_git_help",
              "Show key bindings for fzf_git")
function fzf_git_help(rl_buffer, line_state) -- luacheck: no unused
    local bindings = { kcols=0 }
    local function get_best_binding(command, affinity)
        local best, desc
        local t = rl.getcommandbindings(command)
        if t then
            desc = t.desc
            if t.keys then
                for _, k in ipairs(t.keys) do
                    if command:find("commit_hashes") then
                        k = k:gsub("Bkspc", "C-h")
                    end
                    if affinity and k:find(affinity, 1, true) then
                        best = k
                        break
                    elseif k:match("^C%-g,C%-") and not affinity then
                        best = k
                        break
                    elseif not best then
                        best = k
                    end
                end
            end
        end
        local b = { key=(best or "not bound"), desc=(desc or command) }
        b.kcols = console.cellcount(b.key)
        table.insert(bindings, b)
        bindings.kcols = math.max(bindings.kcols, b.kcols)
    end

    rl_buffer:beginoutput()
    get_best_binding([["luafunc:fzf_git_help"]], "?")
    get_best_binding([["luafunc:fzf_git_files"]])
    get_best_binding([["luafunc:fzf_git_branches"]])
    get_best_binding([["luafunc:fzf_git_tags"]])
    get_best_binding([["luafunc:fzf_git_remotes"]])
    get_best_binding([["luafunc:fzf_git_commit_hashes"]])
    get_best_binding([["luafunc:fzf_git_stashes"]])
    get_best_binding([["luafunc:fzf_git_reflogs"]])
    get_best_binding([["luafunc:fzf_git_worktrees"]])
    get_best_binding([["luafunc:fzf_git_eachref"]])

    local width = console.getwidth()
    clink.print("\x1b[7mfzf_git Key Bindings\x1b[m")
    for _, b in ipairs(bindings) do
        local d = b.desc
        if console.ellipsify then
            d = console.ellipsify(d, width - 3 - bindings.kcols)
        end
        clink.print(string.format("%s%s : %s", b.key, string.rep(" ", bindings.kcols - b.kcols), d))
    end

    if settings.get('fzf.default_bindings') then
        print()
        print("Note:  Each default key binding is bound to both Ctrl-G,Ctrl-Letter and also")
        print("simply Ctrl-G,Letter.  If your terminal intercepts a Ctrl-Letter binding then")
        print("try the Ctrl-G,Letter binding instead.")
    end
end

-- luacheck: globals fzf_git_files
add_help_desc("luafunc:fzf_git_files",
              "Use fzf for Files")
function fzf_git_files(rl_buffer, line_state)
    if not git_check() then
        rl_buffer:ding()
        return
    end

    local _, _, root = git.getgitdir()
    root = root and root:lower()

    local function list_files()
        local files = {}

        -- Get changed files.
        local changed_files = run_command("git -c core.quotePath=false -c color.status="..__fzf_git_color().." status --short --no-branch --untracked-files=all")
        if not changed_files then
            return
        end
        for _, s in ipairs(changed_files) do
            if not s:match("^...%.%./") then
                table.insert(files, s)
            end
        end

        -- Get all files, but filter out changed files.
        local all_files = run_command("git -c core.quotePath=false ls-files "..maybe_quote(root))
        local filter_files = run_command("git -c core.quotePath=false status --short --untracked-files=no")
        local seen = {}
        if not all_files or not filter_files then
            return
        end
        for _, s in ipairs(filter_files) do
            seen[s:sub(4)] = true
        end
        for _, s in ipairs(all_files) do
            if not seen[s] and not s:match("^%.%./") then
                table.insert(files, "   "..s)
            end
        end

        -- Return the generated list of files.
        return files
    end

    local function post_process(item)
        return item:match("^...(.*)$")      -- | cut -c4-
                   :gsub("^.* -> ", "")     -- | sed 's/.* -> //'
    end

    do_fzf_git(rl_buffer, line_state,
        list_files,
        [[-m --ansi --nth 2..,.. \
        --border-label '📁 Files ' \
        --header 'CTRL-O (open in browser) ╱ ALT-E (open in editor)' \
        --bind "ctrl-o:execute-silent:$helper list_file {}" ]]..
        bind_alt_e_edit_file..
        [[--preview "$helper files {}"]],
        post_process
    )
end

-- luacheck: globals fzf_git_branches
add_help_desc("luafunc:fzf_git_branches",
              "Use fzf for Branches")
function fzf_git_branches(rl_buffer, line_state)
    if not git_check() then
        rl_buffer:ding()
        return
    end

    local alt_enter
    local alt_h
    local hash
    local function post_process(item, expect)
        if expect then
            item = item:lower()
            alt_enter = (item == "alt-enter")
            alt_h = (item == "alt-h")
        else
            item = item:gsub("^%* ", "")    -- | sed 's/^\* //'
                       :match("([^%s]+)")   -- | awk '{print $1}' # Slightly modified to work with hashes as well
            if alt_enter then
                -- Strip everything up to and including the last / character.
                item = item:gsub("^.*/([^/]+)$", "%1")  -- printf '%s\n' {+} | cut -c3- | sed 's@[^/]*/@@'
            elseif alt_h then
                -- IMPORTANT:  fzf-git uses
                --      --bind "alt-h:become:LIST_OPTS=\$(cut -c3- <<< {} | cut -d' ' -f1) $shell \"$__fzf_git\" --run hashes"
                -- but :become does not work on Windows.  To work around that,
                -- instead --except= is used to enable post-processing to
                -- massage the selected item appropriately.  And here is where
                -- the massaging is performed.
                hash = item
                return false    -- Cancels inserting matches.
            end
            return item
        end
    end

    local input_command = [[bash "]]..__fzf_git_sh():gsub("\\", "/")..[[" --list branches]]

    do_fzf_git(rl_buffer, line_state,
        nil,
        [[--ansi \
        --border-label '🌲 Branches ' \
        --header-lines 2 \
        --tiebreak begin \
        --preview-window down,border-top,40% \
        --color hl:underline,hl+:underline \
        --no-hscroll ]]..
            -- IMPORTANT:  This 'reload' bind supplies the input without harming
            -- the console mode.  Using GNU tools like bash and column result in
            -- the ESC and Arrow keys not working until a letter is pressed.
            -- But having fzf spawn the command works fine.
        [[--bind "start:reload:]]..input_command:gsub("\"", "\\\"")..[[" ]]..
        [[--bind 'ctrl-/:change-preview-window(down,70%|hidden|)' \
        --bind "ctrl-o:execute-silent:bash \"$__fzf_git\" --list branch {}" \
        --bind "alt-a:change-border-label(🌳 All branches)+reload:bash \"$__fzf_git\" --list all-branches" \
        --bind "alt-h:accept" \
        --bind "alt-enter:accept" \
        --expect=alt-enter,alt-h \
        --preview "$helper branches {}"]],
        post_process
    )

    if alt_h and hash then
        specific_hash = hash
        fzf_git_commit_hashes(rl_buffer, line_state)
        specific_hash = nil
    end
end

-- luacheck: globals fzf_git_tags
add_help_desc("luafunc:fzf_git_tags",
              "Use fzf for Tags")
function fzf_git_tags(rl_buffer, line_state)
    do_fzf_git(rl_buffer, line_state,
        [[git tag --sort -version:refname]],
        [[--preview-window right,70% \
        --border-label '📛 Tags ' \
        --header 'CTRL-O (open in browser)' \
        --bind "ctrl-o:execute-silent:bash \"$__fzf_git\" --list tag {}" \
        --bind 'alt-r:toggle-raw' ]]..
        [[--preview "git show --color=$(__fzf_git_color .) {}"]]
    )
end

-- luacheck: globals fzf_git_remotes
add_help_desc("luafunc:fzf_git_remotes",
              "Use fzf for Remotes")
function fzf_git_remotes(rl_buffer, line_state)
    if not git_check() then
        rl_buffer:ding()
        return
    end

    local function list_remotes()
        -- PROBLEM:
        --      fzf-git uses
        --          git remote -v | awk '{print $1 "\t" $2}' | uniq
        --      to generate the input for fzf.  But awk and/or uniq are
        --      corrupting the console mode, which causes fzf to be unable to
        --      respond to ESC or Arrow keys until after a letter is typed.
        -- WORKAROUND:
        --      Do post-processing in Lua instead of using GNU tools.
        -- OR AN ALTERNATE WORKAROUND:
        --      The other solution is to use a start:reload: bind to make fzf
        --      run the query itself instead of piping input.
        local uniq = {}
        local remotes = run_command("git remote -v")
        if not remotes then
            return
        end
        for _, r in ipairs(remotes) do
            if not remotes[r] then
                local fields = string.explode(r)
                table.insert(uniq, fields[1].."\t"..fields[2])
                remotes[r] = true
            end
        end
        return uniq
    end

    local function post_process(item)
        return item:match("^([^\t]*)\t")    -- | cut -d$'\t' -f1
    end

    do_fzf_git(rl_buffer, line_state,
        list_remotes,
        [[--tac \
        --border-label '📡 Remotes ' \
        --header 'CTRL-O (open in browser)' \
        --bind "ctrl-o:execute-silent:bash \"$__fzf_git\" --list remote {1}" \
        --preview-window right,70% ]]..
            -- IMPORTANT:  fzf-git uses
            --      --preview "git log --oneline --graph --date=short --color=$(__fzf_git_color .) --pretty='format:%C(auto)%cd %h%d %s' '{1}/$(git rev-parse --abbrev-ref HEAD)' --"]],
            -- which has been encapsulated into the helper script to port the
            -- use of $(...) into something that works on Windows.
        [[--preview "$helper remotes {1}"]],
        post_process
    )
end

local function fzf_git_tree_files(rl_buffer, line_state, ...)
    local args = ""
    local seen = {}
    for _, treeish in ipairs({...}) do
        if not seen[treeish] then
            seen[treeish] = true
            args = args..maybe_quote(treeish).." "
        end
    end

    -- NOTE:  fzf-git.sh applies `sort -u`.  The -u part is implemented above,
    -- but I see no value in sorting by hash.

    do_fzf_git(rl_buffer, line_state,
        [[git diff-tree --no-commit-id --name-only ]]..args..[[ -r]],
        [[-m \
        --border-label "📂 Files in $* " \
        --header 'CTRL-O (open in browser) ╱ ALT-E (open in editor)' \
        --bind "ctrl-o:execute-silent:bash \"$__fzf_git\" --list file {}" ]]..
        bind_alt_e_edit_tree_file..
        [[--preview "$helper tree_files {}"]]
    )
end

-- luacheck: globals fzf_git_commit_hashes
add_help_desc("luafunc:fzf_git_commit_hashes",
              "Use fzf for commit Hashes")
fzf_git_commit_hashes = function(rl_buffer, line_state) -- luacheck: no unused
    if not git_check() then
        rl_buffer:ding()
        return
    end

    local alt_f
    local hash
    local function post_process(item, expect)
        if expect then
            item = item:lower()
            alt_f = (item == "alt-f")
        else
            item = item:match("^%x+")
            if alt_f then
                -- IMPORTANT:  fzf-git uses
                --      --bind "alt-f:become:echo ::tree_files;
                --        awk 'match(\$0, /[a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9]*/) { print substr(\$0, RSTART, RLENGTH) }' {+f} |
                --          xargs bash \"$__fzf_git\" --run tree_files" \
                -- but :become does not work on Windows.  To work around that,
                -- instead --except= is used to enable post-processing to
                -- massage the selected item appropriately.  And here is where
                -- the massaging is performed.
                hash = item
                return false    -- Cancels inserting matches.
            end
            return item
        end
    end

    local old___fzf_git_indent = os.getenv("__fzf_git_indent")
    do
        local out = run_command("git rev-parse --short HEAD")
        local len = out and out[1] and #out[1] or 7
        os.setenv("__fzf_git_indent", "\x1b[38;5;238m-"..string.rep(" ", len).."\x1b[m")
    end

    -- specific_hash is a (local) "global" variable set by fzf_git_branches
    -- when it invokes fzf_git_commit_hashes, to control specifically which
    -- hash to show.  It could be passed as an argument instead, but that
    -- could prove to be a land mine if luafunc: macros are ever changed to
    -- pass more than two arguments to the function.  In contrast,
    -- fzf_git_tree_files is only a local function, so that issue doesn't
    -- to it in the same way.
    if diag and specific_hash then
        print("specific_hash", specific_hash)
    end

    do_fzf_git(rl_buffer, line_state,
        nil,
        [[--ansi --no-sort --bind 'ctrl-s:toggle-sort,alt-r:toggle-raw' \
        --nth 1,1 \
        --border-label '🍡 Hashes ' \
        --header-lines 2 \
        --bind 'start:reload:$helper load_hashes ]]..(specific_hash or "")..[[' \
        --bind "ctrl-o:execute-silent:bash \"$__fzf_git\" --list commit {1}" ]]..
-- TODO:  Ctrl-D prints no output and does not accept pager input.  This is an
-- fzf bug, tracked in:  https://github.com/junegunn/fzf/issues/4260#issuecomment-3931448651
        [[--bind "ctrl-d:execute:git diff --color=$(__fzf_git_color) {1}" \
        --bind "alt-a:change-border-label(🍇 All hashes)+reload:$helper load_all_hashes" ]]..
        [[--bind "alt-enter:accept" \
        --color hl:underline,hl+:underline \
        --expect=alt-f \
        --preview "$helper hashes_preview {1}"]],
        post_process
    )

    os.setenv("__fzf_git_indent", old___fzf_git_indent)

    if alt_f and hash then
        fzf_git_tree_files(rl_buffer, line_state, hash)
    end
end

-- luacheck: globals fzf_git_stashes
add_help_desc("luafunc:fzf_git_stashes",
              "Use fzf for Stashes")
function fzf_git_stashes(rl_buffer, line_state)
    local function post_process(item)
        return item:match("^([^:]+)")       -- | cut -d: -f1
    end

    do_fzf_git(rl_buffer, line_state,
        [[git stash list]],
        [[--border-label '🥡 Stashes ' \
        --header 'CTRL-X (drop stash)' \
        --bind 'ctrl-x:reload(git stash drop -q {1} & git stash list)' ]]..
        [[-d: --preview "git show --first-parent --color=$(__fzf_git_color .) {1}"]],
        post_process
    )
end

-- luacheck: globals fzf_git_reflogs
add_help_desc("luafunc:fzf_git_reflogs",
              "Use fzf for reflogs")
function fzf_git_reflogs(rl_buffer, line_state)
    local function post_process(item)
        return item:match("^([^%s]+)")      -- | awk '{print $1}'
    end

    do_fzf_git(rl_buffer, line_state,
        [[git reflog --color=$(__fzf_git_color) --format="%C(blue)%gD %C(yellow)%h%C(auto)%d %gs"]],
        [[--ansi \
        --border-label '📒 Reflogs ' \
        --bind 'alt-r:toggle-raw' ]]..
        [[--preview "git show --color=$(__fzf_git_color .) {1}"]],
        post_process
    )
end

-- luacheck: globals fzf_git_worktrees
add_help_desc("luafunc:fzf_git_worktrees",
              "Use fzf for Worktrees")
function fzf_git_worktrees(rl_buffer, line_state)
    local function post_process(item)
        return item:match("^([^%s]+)")      -- | awk '{print $1}'
    end

    do_fzf_git(rl_buffer, line_state,
        [[git worktree list]],
        [[--border-label '🌴 Worktrees ' \
        --header 'CTRL-X (remove worktree)' \
        --bind 'ctrl-x:reload(git worktree remove {1} > nul & git worktree list)' \
        --preview "$helper worktree {1} {2}"]],
        post_process
    )
end

-- luacheck: globals fzf_git_eachref
add_help_desc("luafunc:fzf_git_eachref",
              "Use fzf for Each ref (git for-each-ref)")
function fzf_git_eachref(rl_buffer, line_state) -- luacheck: no unused
    local function post_process(item)
        return string.explode(item)[2]-- | awk '{print $2}'
    end

    do_fzf_git(rl_buffer, line_state,
        nil,
        [[--ansi \
        --nth 2,2.. \
        --tiebreak begin \
        --border-label '☘️  Each ref ' \
        --header-lines 1 \
        --preview-window down,border-top,40% \
        --color hl:underline,hl+:underline \
        --no-hscroll \
        --bind 'start:reload:bash "$__fzf_git" --list refs' \
        --bind 'ctrl-/:change-preview-window(down,70%|hidden|)' \
        --bind "ctrl-o:execute-silent:bash \"$__fzf_git\" --list {1} {2}" \
        --bind "alt-e:execute:${EDITOR:-vim} <(git show {2}) < /dev/tty > /dev/tty" \
        --bind "alt-a:change-border-label(🍀 Every ref)+reload:bash \"$__fzf_git\" --list all-refs" ]]..
            -- IMPORTANT:  fzf-git uses
            --      --preview "git log --oneline --graph --date=short --color=$(__fzf_git_color .) --pretty='format:%C(auto)%cd %h%d %s' {2} --"
            -- which has been encapsulated into the helper script to solve the
            -- problem of quotes/parentheses/etc in a way that works on Windows.
        [[--preview "$helper eachref {2}"]],
        post_process
    )
end

--------------------------------------------------------------------------------
-- Delayed initialization shim.  Check for multiple copies of the script being
-- loaded in the same session.  This became necessary because Cmder wanted to
-- include fzf.lua, but users may have already installed a separate copy of the
-- script.

fzf_git_loader_arbiter.ensure_initialized = function()
    assert(not fzf_git_loader_arbiter.initialized)

    describe_commands()
    apply_default_bindings()

    local info = debug.getinfo(1, "S")
    local source = info and info.source or nil

    fzf_git_loader_arbiter.initialized = true
    fzf_git_loader_arbiter.loaded_source = source
end

clink.onbeginedit(function ()
    -- Do delayed initialization if it hasn't happened yet.
    if fzf_git_loader_arbiter.ensure_initialized then
        fzf_git_loader_arbiter.ensure_initialized()
        fzf_git_loader_arbiter.ensure_initialized = nil
    end

    -- Reset knowledge of bat or batcat, in case it gets installed later.
    __fzf_git_cat_command = nil
end)

