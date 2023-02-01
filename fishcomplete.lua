--------------------------------------------------------------------------------
-- PROTOTYPE SCRIPT -- Disabled by default; see below for how to enable it.
--------------------------------------------------------------------------------
-- Usage:
--
-- When a command is typed and it does not have an argmatcher, then fishcomplete
-- automatically checks if there is a .fish file by the same name in the same
-- directory as the command program, or in the directory specified by the
-- fishcomplete.completions_dir global variable.  If yes, then it attempts to
-- parse the .fish file and create a Clink argmatcher from it.
--
-- The following global configuration variables in Lua control how this script
-- functions:
--
--      clink_gizmos_fishcomplete
--              [true|false]  Set this to true to enable this script.  This
--              script is disabled by default.
--
--      fishcomplete.banner
--              [true|false]  Whether to show feedback at top of screen when
--              loading fish completions.
--
--      fishcomplete.completions_dir
--              [directory]  Path to fish completions files.
--
--
-- NOTE:  The fishcomplete script does not yet handle the -e or -w flags for
-- the fish "complete" command.  It attempts to handle simple fish completion
-- scripts, but it will likely malfunction with more sophisticated fish
-- completion scripts.

-- TODO: -e     : `complete -c command -e` erases wrapped "command".
-- TODO: -e arg : `complete -c command -e cmpltn` erases completion "cmpltn" from "command".
-- TODO: -w arg : `complete -c hub -w git` makes "hub" inherit the current state of "git" command completions.

if not clink_gizmos_fishcomplete then -- luacheck: no global
    return
end

if not clink.oncommand then
    print('fishcomplete.lua requires a newer version of Clink; please upgrade.')
    return
end

--------------------------------------------------------------------------------
-- Global config variables (set them in a separate Lua script, e.g. in your
-- Clink profile directory).

-- luacheck: globals fishcomplete
fishcomplete = fishcomplete or {}
if fishcomplete.banner == nil then
    fishcomplete.banner = true
end

-- luacheck: globals NONL

--------------------------------------------------------------------------------
-- Options helpers.

local match_longflag = '^(%-%-[^ \t]+)([ \t=])'
local match_shortflag = '^(%-[^ \t])([ \t])'
local match_oldflag = '^(%-[^ \t]+)([ \t=])'

local function initopt(state, options, line)
    state._options = options
    state._line = line
end

local function getopt(state)
    if state._line == '' then
        return
    end

    local f, delim = state._line:match(match_longflag)
    if f then
        state._line = state._line:gsub(match_longflag, '')
    else
        f, delim = state._line:match(match_shortflag)
        if f then
            state._line = state._line:gsub(match_shortflag, '')
        else
            f, delim = state._line:match(match_oldflag)
            if f then
                state._line = state._line:gsub(match_oldflag, '')
            else
                local words = string.explode(state._line, ' \t')
                state.failure = 'unexpected text "'..(words and words[1] or '')..'"'
                state.flags = nil
                return
            end
        end
    end

    if delim ~= '=' then
        state._line = state._line:gsub('^[ \t]+', '')
    end

    local opt = state._options[f]
    if not opt then
        state.failure = 'unrecognized flag '..f
        state.flags = nil
        return nil, nil, f
    end

    local arg
    if opt.arg then
        local i = 1
        local qc = state._line:match('^([\'"])')
        local end_match = qc
        if qc then
            i = 2
        else
            end_match = '[ \t]'
        end

        arg = ''

        local last = 0
        local nextstart = i
        local len = #state._line
        while i <= len do
            local ch = state._line:sub(i,i)
            if ch:match(end_match) then
                break
            elseif ch == [[\]] then
                arg = arg..state._line:sub(nextstart, last)
                i = i + 1
                nextstart = i
            end
            last = i
            i = i + 1
        end
        if last >= nextstart then
            arg = arg..state._line:sub(nextstart, last)
        end

        state._line = state._line:sub(last + 1)
        if qc then
            state._line = state._line:gsub('^'..qc, '')
        end
        state._line = state._line:gsub('^[ \t]+', '')
    end

    if opt.func then
        opt.func(state, arg)
    end

    return opt, arg, f
end

--------------------------------------------------------------------------------
-- Fish `complete` command parser.

local _command = {
    arg=true,
    func=function (state, arg)
        if state.command ~= arg then
            state.flags = nil
        end
    end
}

local _path = {
    -- This approximates the -p flag.
    arg=true,
    func=function (state, arg)
        if state.command ~= path.getbasename(arg) then
            state.flags = nil
        end
    end
}

local _condition = {
    arg=true,
    func=function (state, arg)
        if arg == '__fish_use_subcommand' then -- luacheck: ignore 542
        else
            state.flags = nil
            state.failure = 'unrecognized condition "'..arg..'"'
        end
    end
}

local _short_option = {
    arg=true,
    func=function (state, arg)
        table.insert(state.flags, '-'..arg)
    end
}

local _long_option = {
    arg=true,
    func=function (state, arg)
        table.insert(state.flags, '--'..arg)
    end
}

local _old_option = {
    arg=true,
    func=function (state, arg)
        table.insert(state.flags, '-'..arg)
    end
}

local _description = {
    arg=true,
    func=function (state, arg)
        state.desc = arg
    end
}

local _arguments = {
    arg=true,
    func=function (state, arg)
        if not state.linked_parser then
            state.linked_parser = clink.argmatcher()
        end
        -- TODO: handle quoted strings
        for _,s in ipairs(string.explode(arg)) do
            table.insert(state.matches, { match=s, type='arg' })
        end
    end
}

local _keep_order = {
    func=function (state, arg) -- luacheck: no unused
        state.nosort = true
    end
}

local _no_files = {
    func=function (state, arg) -- luacheck: no unused
        state.nofiles = true
    end
}

local _force_files = {
    func=function (state, arg) -- luacheck: no unused
        state.forcefiles = true
    end
}

local _require_parameter = {
    func=function (state, arg) -- luacheck: no unused
        if not state.linked_parser then
            state.linked_parser = clink.argmatcher()
        end
    end
}

local _exclusive = {
    func=function (state, arg) -- luacheck: no unused
        state.nofiles = true
        if not state.linked_parser then
            state.linked_parser = clink.argmatcher()
        end
    end
}

local _nyi = { nyi=true }
local _nyi_arg = { nyi=true, arg=true }

local options = {
    ['-c'] = _command,              ['--command'] = _command,
    ['-p'] = _path,                 ['--path'] = _path,
    ['-s'] = _short_option,         ['--short-option'] = _short_option,
    ['-l'] = _long_option,          ['--long-option'] = _long_option,
    ['-o'] = _old_option,           ['--old-option'] = _old_option,
    ['-d'] = _description,          ['--description'] = _description,
    ['-a'] = _arguments,            ['--arguments'] = _arguments,
    ['-k'] = _keep_order,           ['--keep-order'] = _keep_order,
    ['-f'] = _no_files,             ['--no-files'] = _no_files,
    ['-F'] = _force_files,          ['--force-files'] = _force_files,

    ['-r'] = _require_parameter,    ['--require-parameter'] = _require_parameter,
    ['-n'] = _condition,            ['--condition'] = _condition,

    ['-x'] = _exclusive,            ['--exclusive'] = _exclusive,

    ['-e'] = _nyi,                  ['--erase'] = _nyi,
    ['-w'] = _nyi_arg,              ['--wraps'] = _nyi_arg,
}

local function parse_fish_completions(name, fish)
    local file = io.open(fish, 'r')
    if not file then
        return
    end

    local parser = clink.argmatcher()
    local state

    local match_complete = '^complete[ \t]+'

    local i = 0
    for line in file:lines() do
        i = i + 1
        if line:match(match_complete) then
            state = {
                command=name,
                flags={},
                matches={},
            }

            initopt(state, options, line:gsub(match_complete, ''))

            while true do
                if not getopt(state) then
                    if not state.flags then
                        parser = nil
                    end
                    break
                end
            end

            if not parser then
                if state.failure then
                    state.failure = state.failure..' on line '..tostring(i)
                end
                break
            end

            if (state.desc and #state.desc > 0) or state.linked_parser then
                local descs = {}
                for _,f in ipairs(state.flags) do
                    local d = {}
                    if state.linked_parser then
                        table.insert(d, ' arg')
                    end
                    table.insert(d, state.desc)
                    descs[f] = d
                end
                parser:adddescriptions(descs)
            end

            if state.linked_parser then
                if state.forcefiles or not state.nofiles then
                    table.insert(state.matches, clink.filematches)
                end
                state.linked_parser:addarg(state.matches)
            end

            if state.linked_parser then
                for j = 1, #state.flags, 1 do
                    state.flags[j] = state.flags[j] .. state.linked_parser
                end
            end

            parser:addflags(state.flags)
        end
    end

    file:close()

    if not parser then
        return nil, state.failure
    end

    clink.arg.register_parser(name, parser)
    return true
end

local function oncommand(line_state, info)
    if info.file ~= '' and not clink.getargmatcher(line_state) then
        local dir = path.getdirectory(info.file)
        local name = path.getbasename(info.file)

        local fish = path.join(dir, name..'.fish')
        if not os.isfile(fish) then
            if not fishcomplete.completions_dir then
                return
            else
                fish = path.join(fishcomplete.completions_dir, name..'.fish')
                if not os.isfile(fish) then
                    return
                end
            end
        end

        local ok, failure = parse_fish_completions(name, fish)
        if not fishcomplete.banner then
            return
        end

        local top = '\x1b[s\x1b[H'
        local restore = '\x1b[K\x1b[m\x1b[u'

        fish = path.getname(fish)
        if ok then
            clink.print(top..'\x1b[0;48;5;56;1;97mCompletions loaded from "'..fish..'".'..restore, NONL)
        else
            if failure then
                failure = '; '..failure..'.'
            else
                failure = '.'
            end
            clink.print(top..'\x1b[0;48;5;52;1;97mFailed reading "'..fish..'"'..failure..restore, NONL)
        end
    end
end

clink.oncommand(oncommand)
