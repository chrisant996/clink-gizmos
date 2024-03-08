--------------------------------------------------------------------------------
-- PROTOTYPE SCRIPT -- Disabled by default; see below for how to enable it.
--------------------------------------------------------------------------------
-- Usage:
--
-- When a command is typed and it does not have an argmatcher, then fishcomplete
-- automatically checks if there is a .fish file by the same name in the same
-- directory as the command program, or in an autocomplete subdirectory below
-- it, or in the directory specified by the fishcomplete.completions_dir
-- setting.  If yes, then it attempts to parse the .fish file and generate a
-- Clink argmatcher from it.
--
-- To enable it, run:
--
--      clink set fishcomplete.enable true
--
-- If fishcomplete is enabled, then by default it shows feedback at the top of
-- the screen when attempting to load .fish completion files.  If you want to
-- disable the feedback, you can run "clink set fishcomplete.banner false".
--
-- You can optionally configure a directory containing .fish completion files by
-- running "clink set fishcomplete.completions_dir c:\some\dir".  The specified
-- directory is searched in additon to the directory containing the
-- corresponding command program, and any autocomplete subdirectory below that
-- directory.
--
-- NOTE:  The fishcomplete script does not yet handle the -e or -w flags for
-- the fish "complete" command.  It attempts to handle simple fish completion
-- scripts, but it will likely malfunction with more sophisticated fish
-- completion scripts.  It cannot handle the fish scripting language, apart from
-- the "complete" command itself.

-- TODO: -e     : `complete -c command -e` erases wrapped "command".
-- TODO: -e arg : `complete -c command -e cmpltn` erases completion "cmpltn" from "command".
-- TODO: -w arg : `complete -c hub -w git` makes "hub" inherit the current state of "git" command completions.

local standalone = clink and not clink.argmatcher and not clink.arg and true

if not standalone then

settings.add("fishcomplete.enable", false, "Auto-translate fish completion files",
    "When this is enabled and a command is typed that doesn't have an argmatcher,\n"..
    "then this automatically looks for a .fish file by the same name.  If found,\n"..
    "it attempts to parse the .fish file and generate a Clink argmatcher from it.")
settings.add("fishcomplete.banner", true, "Show feedback when loading .fish files")
settings.add("fishcomplete.completions_dir", "", "Path to .fish completion files",
    "This specifies a directory to search for .fish completion files.  This is in\n"..
    "addition to the directory containing the corresponding command program, and\n"..
    "any autocomplete subdirectory below that directory.")

if not settings.get("fishcomplete.enable") then
    return
end

if not clink.oncommand then
    print('fishcomplete.lua requires a newer version of Clink; please upgrade.')
    return
end

end -- not standalone

-- luacheck: globals NONL

--------------------------------------------------------------------------------
-- Options helpers.

local match_longflag = '^(%-%-[^ \t]+)([ \t=])'
local match_shortflag = '^(%-[^ \t])([ \t])'
local match_oldflag = '^(%-[^ \t]+)([ \t=])'

local function initopt(state, options, line)
    state._options = options
    state._line = line.." "
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

local function trim(s)
    return s:gsub('^ +', ''):gsub(' +$', '')
end

local _command = {
    arg=true,
    func=function (state, arg)
        state.command = arg
    end
}

local _path = {
    -- This approximates the -p flag.
    arg=true,
    func=function (state, arg)
        state.command = path.getbasename(arg)
    end
}

local _condition = {
    arg=true,
    func=function (state, arg)
        if arg == '__fish_use_subcommand' then -- luacheck: ignore 542
        elseif arg:find('__fish_contains_opt') then -- luacheck: ignore 542
            -- For now, just always include the flag.
            -- FUTURE: This could be supported by using the `onarg` callback
            -- to inspect flags in the input line.
        else
            state.failures = state.failures or {}
            table.insert(state.failures, 'unrecognized condition "'..arg..'"')
        end
    end
}

local _short_option = {
    arg=true,
    func=function (state, arg)
        if not state.command then
            state.failures = state.failures or {}
            table.insert(state.failures, 'missing command for short option "-'..arg..'"')
        else
            table.insert(state.flags, '-'..arg)
        end
    end
}

local _long_option = {
    arg=true,
    func=function (state, arg)
        if not state.command then
            state.failures = state.failures or {}
            table.insert(state.failures, 'missing command for long option "--'..arg..'"')
        else
            table.insert(state.flags, '--'..arg)
        end
    end
}

local _old_option = {
    arg=true,
    func=function (state, arg)
        if not state.command then
            state.failures = state.failures or {}
            table.insert(state.failures, 'missing command for old option "-'..arg..'"')
        else
            table.insert(state.flags, '-'..arg)
        end
    end
}

local _description = {
    arg=true,
    func=function (state, arg)
        state.desc = arg
    end
}

-- TODO: Support multi-line arguments, as in rg.fish.
-- NOTE: The {..} globbing syntax is more complicated than I'm willing to
-- support at this time.
local _arguments = {
    arg=true,
    func=function (state, arg)
        state.linked_parser = true
        if arg:find('^%#') then -- luacheck: ignore 542
            -- Ignore comment lines.
        elseif arg:find('^%{') then
            arg = arg:gsub('^%{(.*)}$', '%1')
            local s1 = ''
            local s2 = ''
            local desc, quote
            for i = 1, #arg do
                local c = arg:sub(i, i)
                if not desc then
                    if c == '\t' then
                        desc = true
                        quote = false
                    else
                        s1 = s1..c
                    end
                else
                    if esc then
                        s2 = s2..c
                        esc = nil
                    elseif quote then
                        if c == '\\' then
                            esc = true
                        elseif c == '\'' then
                            quote = nil
                        else
                            s2 = s2..c
                        end
                    else
                        if c == '\'' then
                            quote = true
                        elseif c == ',' then
                            table.insert(state.matches, { match=trim(s1), desc=trim(s2) })
                            s1 = ''
                            s2 = ''
                            desc = nil
                        end
                    end
                end
            end
            if s1 ~= '' then
                table.insert(state.matches, { match=trim(s1), desc=trim(s2) })
            end
        else
            for _,s in ipairs(string.explode(arg)) do
                table.insert(state.matches, { match=trim(s) })
            end
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
        state.linked_parser = true
    end
}

local _exclusive = {
    func=function (state, arg) -- luacheck: no unused
        state.nofiles = true
        state.linked_parser = true
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

    local failures
    local commands = {}
    local state = {}

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

            while getopt(state) do -- luacheck: ignore 542
            end

            commands[state.command] = commands[state.command] or {}

            local lp
            local lpname
            if state.linked_parser then
                local s1 = state.command:gsub('[^A-Za-z]', '')
                local s2 = ''
                for _,f in ipairs(state.flags) do
                    if #s2 < #f then
                        s2 = f
                    end
                end
                s2 = s2:gsub('[^A-Za-z]', '')
                if s2 == '' then
                    state.failures = state.failures or {}
                    table.insert(state.failures, 'missing flag')
                    state.linked_parser = nil
                else
                    lpname = s1..'_'..s2
                    if state.forcefiles or not state.nofiles then
                        table.insert(state.matches, clink.filematches)
                    end
                    lp = state.matches or {}
                    commands[state.command].links = commands[state.command].links or {}
                    commands[state.command].links[lpname] = lp
                end
            end

            if state.failures then
                failures = failures or {}
                for _,f in ipairs(state.failures) do
                    table.insert(failures, f..' on line '..tostring(i))
                end
            end

            if (state.desc and #state.desc > 0) or state.linked_parser then
                local descs = commands[state.command].descs or {}
                for _,f in ipairs(state.flags) do
                    local d = {}
                    if state.linked_parser then
                        table.insert(d, ' arg')
                    end
                    table.insert(d, state.desc or '')
                    descs[f] = d
                end
                commands[state.command].descs = descs
            end

            local flags = commands[state.command].flags or {}
            for _,f in ipairs(state.flags) do
                local flag = { f }
                if lpname and lp then
                    table.insert(flag, lpname)
                end
                table.insert(flags, flag)
            end
            commands[state.command].flags = flags
        end
    end

    file:close()

    return commands, failures
end

if standalone then
    require('modules/dumpvar')

    local function escape_string(s)
        return s:gsub('(["\\])', '\\%1')
    end

    local function convert()
        local red = '\x1b[91m'
        local green = '\x1b[92m'
        local norm = '\x1b[m'

        local infile = arg[1]
        local outfile = arg[2]

        if not infile then
            clink.print(red..'Missing input file.'..norm)
            os.exit(1)
        end

        if not outfile then
            local dir = path.getdirectory(infile)
            local name = path.getbasename(infile)
            outfile = path.join(dir, name)..'.lua'
        end
        if os.isdir(outfile) then
            outfile = path.join(outfile, path.getbasename(infile)..'.lua')
        end

        local o, msg = io.open(outfile, 'w')
        if not o then
            msg = msg and '; '..msg or ''
            msg = string.gsub(msg..'.', '%.+$', '.')
            clink.print(red..'Error opening "'..outfile..'" for write'..msg..norm)
            os.exit(1)
        end

        local commands, failures = parse_fish_completions(path.getbasename(infile), infile)

        -- For each command.
        local first = true
        for cname,c in pairs(commands) do
            if not first then
                o:write('\n')
            end

            o:write('------------------------------------------------------------------------------\n')
            o:write('-- '..cname:upper()..'\n')
            o:write('\n')

            if first then
                first = nil
                o:write('local function try_require(module)\n')
                o:write('    local r\n')
                o:write('    pcall(function() r = require(module) end)\n')
                o:write('    return r\n')
                o:write('end\n')
                o:write('\n')
                o:write('try_require("arghelper")\n')
                o:write('\n')
            end

            -- Make linked argmatchers.
            local links = {}
            if c.links then
                for lname,l in pairs(c.links) do
                    local any_desc
                    o:write('local '..lname..' = clink.argmatcher():addarg({')
                    for i,arg in ipairs(l) do
                        if i > 1 then
                            o:write(', ')
                        end
                        o:write('"'..escape_string(arg.match)..'"')
                        if arg.desc and arg.desc ~= '' then
                            any_desc = true
                        end
                    end
                    o:write('})')
                    if any_desc then
                        o:write(':adddescriptions({\n')
                        for i,arg in ipairs(l) do
                            if arg.desc and arg.desc ~= '' then
                                o:write('  ["'..escape_string(arg.match)..'"] = "'..escape_string(arg.desc)..'",\n')
                            end
                        end
                        o:write('})')
                    end
                    o:write('\n')
                end
                o:write('\n')
            end

            -- Make command argmatcher.
            o:write('clink.argmatcher("'..cname..'")\n')
            if c.descs then
                o:write(':adddescriptions({\n')
                for f,d in pairs(c.descs) do
                    o:write('  ["'..f..'"] = { "'..escape_string(d[1])..'"')
                    if d[2] then
                        o:write(', "'..escape_string(d[2])..'"')
                    end
                    o:write(' },\n')
                    assert(not d[3])
                end
                o:write('})\n')
            end
            do
                o:write(':addflags({\n')
                for _,f in ipairs(c.flags) do
                    o:write('  "'..f[1]..'"')
                    if f[2] then
                        o:write('..'..f[2])
                    end
                    o:write(',\n')
                end
                o:write('})\n')
            end
        end

        o:close()

        if failures then
            clink.print(red..'Failure(s) while converting the completion script:'..norm)
            for _,f in ipairs(failures) do
                print(f)
            end
            os.exit(1)
        else
            clink.print(green..'Successful conversion.'..norm)
        end
    end

    return convert()
end

local function generate_completions(commands)
    -- For each command.
    for cname,c in pairs(commands) do
        -- Make linked argmatchers.
        local links = {}
        if c.links then
            for lname,l in pairs(c.links) do
                local am = clink.argmatcher()
                am:addarg(l)
                links[lname] = am
            end
        end

        -- Make command argmatcher.
        local flags = {}
        local am = clink.argmatcher(cname)
        if c.descs then
            am:adddescriptions(c.descs)
        end
        for _,f in ipairs(c.flags) do
            if f[2] then
                table.insert(flags, f[1]..links[f[2]])
            else
                table.insert(flags, f[1])
            end
        end
        am:addflags(flags)
    end
end

local function oncommand(line_state, info)
    if info.file ~= '' and not clink.getargmatcher(line_state) then
        local dir = path.getdirectory(info.file)
        local name = path.getbasename(info.file)

        local fish = path.join(dir, name..'.fish')
        if not os.isfile(fish) then
            fish = path.join(path.join(dir, 'autocomplete'), name..'.fish')
            if not os.isfile(fish) then
                local completions_dir = settings.get('fishcomplete.completions_dir') or ''
                if completions_dir == '' then
                    return
                end
                fish = path.join(completions_dir, name..'.fish')
                if not os.isfile(fish) then
                    return
                end
            end
        end

        local commands, failures = parse_fish_completions(name, fish)
        generate_completions(commands)

        if not settings.get('fishcomplete.banner') then
            return
        end

        local top = '\x1b[s\x1b[H'
        local restore = '\x1b[K\x1b[m\x1b[u'

        fish = path.getname(fish)
        if not failures then
            clink.print(top..'\x1b[0;48;5;56;1;97mCompletions loaded from "'..fish..'".'..restore, NONL)
        else
            local failure = failures[1]
            failure = failure and '; '..failure..'.' or '.'
            clink.print(top..'\x1b[0;48;5;52;1;97mFailed reading "'..fish..'"'..failure..restore, NONL)
        end
    end
end

clink.oncommand(oncommand)
