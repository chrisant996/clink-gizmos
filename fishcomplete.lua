--------------------------------------------------------------------------------
-- PROTOTYPE SCRIPT -- Disabled by default; see below for how to enable it.
--------------------------------------------------------------------------------
-- Usage:
--
-- When a command is typed and it does not have an argmatcher, then fishcomplete
-- automatically checks if there is a .fish file by the same name in the same
-- directory as the command program, or in an autocomplete or complete
-- subdirectory below it, or in the directory specified by the
-- fishcomplete.completions_dir setting.  If yes, then it attempts to parse the
-- .fish file and generate a Clink argmatcher from it.
--
-- To enable it, run:
--
--      clink set fishcomplete.enable true
--
-- If fishcomplete is enabled, then by default it shows feedback at the top of
-- the screen when attempting to load *.fish completion files.  If you want to
-- disable the feedback, you can run "clink set fishcomplete.banner false".
--
-- You can optionally configure a directory containing *.fish completion files
-- by running "clink set fishcomplete.completions_dir c:\some\dir".  This
-- directory is searched last, if a .fish file isn't found by the default search
-- strategy.
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
    "any autocomplete or complete subdirectory below that directory.")

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
            local opt = arg:match('__fish_contains_opt%s+(.*)$')
            if opt then
                local conditions = {}
                local t = string.explode(opt)
                local short
                for _,s in ipairs(t) do
                    if s == '-s' then
                        short = true
                    elseif short then
                        short = false
                        table.insert(conditions, '-'..s)
                    else
                        table.insert(conditions, '--'..s)
                    end
                end
                if conditions[1] then
                    state.condition_contains_opt = conditions
                end
            end
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
            local desc, quote, esc
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

            if state.condition_contains_opt then
                local conditions = commands[state.command].conditions or {}
                for _,f in ipairs(state.flags) do
                    conditions[f] = state.condition_contains_opt
                end
                commands[state.command].conditions = conditions
            end
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

    local function spairs(t, order)
        local keys = {}
        local num = 0
        for k in pairs(t) do
            num = num + 1
            keys[num] = k
        end

        if order then
            table.sort(keys, function(a,b) return order(t, a, b) end)
        else
            table.sort(keys)
        end

        local i = 0
        return function()
            i = i + 1
            if keys[i] then
                return keys[i], t[keys[i]]
            end
        end
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
        local first_conditions = true
        for cname,c in spairs(commands) do
            if not first then
                o:write('\n')
            end

            o:write('------------------------------------------------------------------------------\n')
            o:write('-- '..cname:upper()..'\n')
            o:write('\n')

            if first then
                first = nil
                o:write('-- luacheck: no max line length\n')
                o:write('\n')
                o:write('pcall(require, "arghelper")\n')
                o:write('\n')
            end

            if c.conditions and first_conditions then
                first_conditions = nil
                -- IMPORTANT: Keep in sync with onarg_contains_opt().
                o:write('local function onarg_contains_opt(arg_index, word, _, _, user_data)\n')
                o:write('  if arg_index == 0 then\n')
                o:write('    local present = user_data.present\n')
                o:write('    if not present then\n')
                o:write('      present = {}\n')
                o:write('      user_data.present = present\n')
                o:write('    end\n')
                o:write('    present[word] = true\n')
                o:write('  end\n')
                o:write('end\n')
                o:write('\n')
                -- IMPORTANT: Keep in sync with do_filter().
                o:write('local function do_filter(matches, conditions, user_data)\n')
                o:write('  local ret = {}\n')
                o:write('  local present = user_data.present or {}\n')
                o:write('  for _,m in ipairs(matches) do\n')
                o:write('    local test_list = conditions[m.match]\n')
                o:write('    if test_list then\n')
                o:write('      local ok\n')
                o:write('      for _,test in ipairs(test_list) do\n')
                o:write('        if present[test] then\n')
                o:write('          ok = true\n')
                o:write('          break\n')
                o:write('        end\n')
                o:write('      end\n')
                o:write('      if not ok then\n')
                o:write('        goto continue\n')
                o:write('      end\n')
                o:write('    end\n')
                o:write('    table.insert(ret, m)\n')
                o:write('::continue::\n')
                o:write('  end\n')
                o:write('  return ret\n')
                o:write('end\n')
                o:write('\n')
            end

            -- Make linked argmatchers.
            if c.links then
                for lname,l in spairs(c.links) do
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
                        for _,arg in ipairs(l) do
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

            -- Make conditions table.
            if c.conditions then
                o:write('local '..cname..'__hide_unless = {\n')
                for k,values in spairs(c.conditions) do
                    o:write('  ["'..k..'"] = { ')
                    for i,value in ipairs(values) do
                        if i > 1 then
                            o:write(', ')
                        end
                        o:write('"'..escape_string(value)..'"')
                    end
                    o:write(' },\n')
                end
                o:write('}\n')
                o:write('\n')
            end

            -- Make command argmatcher.
            o:write('clink.argmatcher("'..cname..'")\n')
            if c.descs then
                o:write(':adddescriptions({\n')
                for f,d in spairs(c.descs) do
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
                if c.conditions then
                    o:write('  onarg = onarg_contains_opt,\n')
                    o:write('  function(_, _, _, _, user_data) clink.onfiltermatches(function(matches) return do_filter(matches, '..cname..'__hide_unless, user_data) end) end,\n') -- luacheck: no max line length
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

-- IMPORTANT: Keep in sync with convert().
local function onarg_contains_opt(arg_index, word, word_index, line_state, user_data) -- luacheck: no unused
    if arg_index == 0 then
        local present = user_data.present
        if not present then
            present = {}
            user_data.present = present
        end
        present[word] = true
    end
end

-- IMPORTANT: Keep in sync with convert().
local function do_filter(matches, conditions, user_data)
    local ret = {}
    local present = user_data.present or {}
    for _,m in ipairs(matches) do
        local test_list = conditions[m.match]
        if test_list then
            local ok
            for _,test in ipairs(test_list) do
                if present[test] then
                    ok = true
                    break
                end
            end
            if not ok then
                goto continue
            end
        end
        table.insert(ret, m)
::continue::
    end
    return ret
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
        if c.conditions then
            local conditions = c.conditions
            flags.onarg = onarg_contains_opt
            table.insert(flags, function (word, word_index, line_state, match_builder, user_data) -- luacheck: no unused
                clink.onfiltermatches(function (matches)
                    return do_filter(matches, conditions, user_data)
                end)
            end)
        end
        am:addflags(flags)
    end
end

local top = '\x1b[s\x1b[H'
local restore = '\x1b[K\x1b[m\x1b[u'
local okbanner = '0;48;5;56;1;97'
local errbanner = '0;48;5;88;1;97'

local function banner(sgr, msg)
    if settings.get("fishcomplete.banner") then
        if console.ellipsify then
            msg = console.ellipsify(msg, console.getwidth() - 1)
        end
        clink.print(string.format("%s\x1b[%sm%s%s", top, sgr, msg, restore), NONL)
    end
end

local function oncommand(_, info)
    if info.file ~= '' and
            not clink.getargmatcher(info.command) and
            not clink.getargmatcher(info.file) then
        local dir = path.getdirectory(info.file)
        local basename = path.getbasename(info.file)

        local fish = path.join(dir, basename..'.fish')
        if not os.isfile(fish) then
            fish = path.join(path.join(dir, 'autocomplete'), basename..'.fish')
            if not os.isfile(fish) then
                fish = path.join(path.join(dir, 'complete'), basename..'.fish')
                if not os.isfile(fish) then
                    local completions_dir = settings.get('fishcomplete.completions_dir') or ''
                    if completions_dir == '' then
                        return
                    end
                    fish = path.join(completions_dir, basename..'.fish')
                    if not os.isfile(fish) then
                        return
                    end
                end
            end
        end

        local name = path.getname(fish)
        local msg = string.format('Parsing file completions from "%s".', name)
        log.info(msg)
        banner(okbanner, msg)

        local commands, failures = parse_fish_completions(basename, fish)
        generate_completions(commands)

        if not failures then
            banner(okbanner, string.format('Completions loaded from "%s".', name))
        else
            for _,f in ipairs(failures) do
                log.info(f)
            end
            local failure = failures[1]
            failure = failure and '; '..failure..'.' or '.'
            banner(errbanner, string.format('Failed reading "%s"%s', name, failure))
        end
    end
end

if clink.argmatcherloader then
    -- argmatcherloader can handle doskey aliases as well, and doesn't have to
    -- wait for a space after the command word.
    -- Using 40 puts this ahead of carapace (50).
    clink.argmatcherloader(40, function(command_word, quoted)
        oncommand(nil, { command=command_word, file=command_word, quoted=quoted, type="executable" })
    end)
else
    clink.oncommand(oncommand)
end
