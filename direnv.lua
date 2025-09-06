--------------------------------------------------------------------------------
-- DIRENV is disabled by default; see help text below for how to enable it.
--------------------------------------------------------------------------------
local help_text = {}
local function add_help(command, help)
    help_text[command] = help
end

add_help("", {
"DIRENV for Clink",
"",
"This is conceptually similar to the direnv tool from https://direnv.net and",
"https://github.com/direnv/direnv, but is designed for use with Clink.",
"",
"The idea is that when changing current directories from one command prompt to",
"the next, this script looks for a .env file or .env.cmd file.  If it finds one",
"then it applies environment variables from it to the current environment.",
"When changing away to a different directory, then it unsets any environment",
"variables that were applied from the most recent .env or .env.cmd file.",
"",
"By default, direnv starts out disabled and does nothing at all.  To enable",
"it, run 'clink set direnv.enable true'.  Once enabled, it only works in",
"directories it's been told to trust.",
"",
"By default, direnv starts out with no trust.  It only loads environment",
"variables from specific .env or .env.cmd files that have been explicitly",
"allowed.  Run 'direnv allow directory_name' to tell direnv to allow the .env or",
".env.cmd file in a specific directory, or run 'direnv allow path\\.env' or",
"'direnv allow path\\.env.cmd' to allow a specific .env or .env.cmd file.",
"",
"The format for a .env file is one variable definition per line, and each",
"variable definition is a name, an equal sign, and a value.  For example:",
"  VAR_NAME=VALUE",
"",
"The format for a .env.cmd file is a normal batch script, but the script is",
"executed in a separate hidden CMD session.  Any environment variable changes",
"are copied from the hidden CMD into the current CMD session.",
"",
"Available commands:",
"  allow                 Allow loading .env or .env.cmd file from dir.",
"  deny                  Deny loading .env or .env.cmd file from dir.",
"  edit                  Open correponding .env or .env.cmdfile in an editor.",
"  exec                  Execute command after loading environment.",
"  help                  Show this help text.",
"  list                  List allowed .env and .env.cmd files.",
"  prune                 Prune the trust list to remove outdated allowed files.",
"  reload                Trigger an env reload.",
"",
"For help on a specific command, run 'direnv <command> --help'.",
"For example 'direnv exec --help'.",
"",
"Clink settings for direnv:",
"  direnv.enable         True enables direnv or false (the default) disables it.",
"  direnv.banner         True (the default) shows feedback when loading .env or",
"                        .env.cmd files.",
"  direnv.hide_env_diff  True hides env changes or false (the default) shows",
"                        which environment variables are applied.",
"  color.direnv_banner   The color for direnv banner messages.",
"",
"Notes:",
"- The https://direnv.net project supports .envrc shell scripts, but those",
"  don't work with CMD on Windows.  As a compromise, direnv for Clink supports",
"  .env.cmd scripts.",
"- Direnv for Clink can only be invoked from a Clink prompt.  Maybe someday",
"  it will support being invoked from a batch script.",
})

--------------------------------------------------------------------------------
if not clink.parseline then
    print('direnv.lua requires a newer version of Clink; please upgrade.')
    return
end

local direnv_banner = "0;3;38;5;136"

local standalone = clink and not clink.argmatcher and not clink.arg and true
if not standalone then

settings.add("direnv.enable", false, "Auto-apply env vars for directories",
    "When this is enabled and the current directory (or any of its parents)\n"..
    "contains a .env or .env.cmd file, then environment variable assignments are\n"..
    "automatically applied from it.  When the current directory changes again to\n"..
    "somewhere else, then the variables are restored to their previous values.")
settings.add("direnv.banner", true, "Show feedback when loading environment")
settings.add("direnv.hide_env_diff", false, "Hides feedback about environment changes")
settings.add("color.direnv_banner", direnv_banner, "Color for direnv banner messages")

end

local last_dotenv
local last_dir
local envrestore = {}
local trust_list = {}
local provide_line

local norm = "\x1b[m"
local red = "\x1b[31m"

local function sgr(code)
    if not code then
        return "\x1b[m"
    elseif string.byte(code) == 0x1b then
        return code
    else
        return "\x1b["..code.."m"
    end
end

local function banner(msg, force)
    if force or standalone or settings.get("direnv.banner") then
        local bannercolor = sgr(standalone and direnv_banner or settings.get("color.direnv_banner"))
        clink.print(bannercolor..msg..norm)
    end
end

local function report_error(msg)
    clink.print(red.."direnv: error "..msg..norm)
end

local function strip_trailing_backslash(dir)
    dir = path.normalise(dir)
    dir = path.getdirectory(path.join(dir, ""))
    return dir
end

local function echo_up()
    return (clink.getansihost and clink.getansihost() ~= "clink") and " & echo \x1b[2A" or ""
end

--------------------------------------------------------------------------------
local function save_envrestore()
    if clink.opensessionstream then
        local e = clink.opensessionstream("direnv_restore", "w")
        if e then
            for name, value in pairs(envrestore) do
                e:write(string.format("%s=%s\n", name, value))
            end
            e:close()
        end
    end
end

local function clear_envrestore()
    if clink.opensessionstream then
        local e = clink.opensessionstream("direnv_restore", "w")
        if e then
            e:close()
        end
    end
end

--------------------------------------------------------------------------------
local function get_trust_filename()
    local profile_dir = os.getenv("=clink.profile")
    if profile_dir and profile_dir ~= "" then
        local filename = path.join(profile_dir, "direnv_trust")
        return filename
    end
end

local function is_env_file(target)
    local lower = path.getname(target):lower()
    if lower == ".env" then return true
    elseif lower == ".env.cmd" then return true
    end
end

local function is_trusted(name, list)
    list = list or trust_list
    local index = list[name:lower()]
    if index then
        local entry = list[index]
        local t = os.globfiles(entry.file, 2)
        if t[1] and t[1].mtime and t[1].mtime == entry.timestamp then
            return true
        end
    end
    -- FUTURE: if inclusion list support is added (a config file listing trusted
    -- paths and/or trusted path prefixes), then check if name is a symlink and
    -- compare its target against the inclusion list.
end

local function make_trust_entry(file)
    local t = os.globfiles(file, 2)
    if t[1] and t[1].mtime then
        return {file=file, timestamp=t[1].mtime}
    end
end

local function reindex_trust(list)
    for num = #list, 1, -1 do
        if not list[num] then
            table.remove(list, num)
        end
    end
    for num, entry in ipairs(list) do
        list[entry.file:lower()] = num
    end
end

local function load_trust(callback)
    trust_list = {}

    local trust_filename = get_trust_filename()
    if not trust_filename then
        return
    end

    -- Create the trust file if it doesn't exist yet.
    local f
    local binmode = io.truncate and "" or "b"
    if not os.isfile(trust_filename) then
        f = io.sopen(trust_filename, "wx"..binmode, "rw")
        if not f then
            return
        end
        f:close()
    end

    -- Retry opening the trust file until there is no sharing violation.
    -- Try for up to 2 seconds, and then give up.
    local start_clock = os.clock()
    repeat
        f = io.sopen(trust_filename, "r+"..binmode, "rw")
    until f or os.clock() - start_clock > 2

    if not f then
        log.info("direnv unable to access '"..trust_filename.."'.")
        return
    end

    -- Get the file size.  Necessary until Clink has a way to truncate a file.
    local file_size = f:seek()

    -- Load trusted directories from file.
    for line in f:lines() do
        local name, timestamp = line:match("^(.*)=(.*)$")
        if name then
            table.insert(trust_list, {file=name, timestamp=tonumber(timestamp)})
        end
    end
    reindex_trust(trust_list)

    -- Strip trailing blank lines (compensates for the truncation workaround).
    for trim = #trust_list, 1, -1 do
        if trust_list[trim] ~= "" then
            break
        end
        trust_list[trim] = nil
    end

    -- Run callback function.
    local ret
    local callback_ret
    if not callback then
        ret = true
    else
        local save
        save, callback_ret = callback(trust_list)
        if save then
            if not f:seek("set") then
                log.info("direnv unable to update '"..trust_filename.."'.")
                f:close()
                return
            end
            -- Write the lines.
            for _, e in ipairs(trust_list) do
                f:write(string.format("%s=%s\n", e.file, tostring(e.timestamp)))
            end
            -- Truncate the file.
            if io.truncate then
                io.truncate(f)
            else
                local truncate = f:seek()
                local excess = file_size - truncate
                local fill = string.rep("\n", 512)
                while excess >= #fill do
                    f:write(fill)
                    excess = excess - #fill
                end
                if excess > 0 then
                    f:write(fill:sub(1, excess))
                end
            end
        end
        ret = save
    end

    f:close()
    return ret, callback_ret
end

local function add_file_if_exists(files, file)
    if os.isfile(file) then
        table.insert(files, file)
    end
end

local function get_env_files(files, target, isdir)
    if isdir then
        add_file_if_exists(files, path.join(target, ".env.cmd"))
        add_file_if_exists(files, path.join(target, ".env"))
    else
        table.insert(files, target)
    end
end

local function allow_trust(target)
    local orig_target = target
    target = (target == "") and "." or target
    target = (target and os.getfullpathname(target)) or ""
    if target ~= "" then
        target = strip_trailing_backslash(target)
        local isdir = os.isdir(target)
        local isfile = not isdir and os.isfile(target) and is_env_file(target)
        if isdir or isfile then
            local files = {}
            local ok, found = load_trust(function(list)
                get_env_files(files, target, isdir)
                local save = false
                local trusted = true
                for _, file in ipairs(files) do
                    if not is_trusted(file, list) then
                        local entry = make_trust_entry(file)
                        if not entry then
                            return false, false
                        end
                        table.insert(list, entry)
                        list[file:lower()] = #list
                        save = true -- Save the updated trust file.
                        trusted = false
                    end
                end
                return save, trusted
            end)
            if ok then
                for _, file in ipairs(files) do
                    print("Added '"..file.."' to the trust list.")
                end
            elseif not found then
                report_error("trying to allow '"..target.."'.")
            end
            return
        end
    end
    report_error("'"..(orig_target or "").."' not recognized.")
end

local function deny_trust(target)
    local orig_target = target
    target = (target == "") and "." or target
    target = (target and os.getfullpathname(target)) or ""
    if target ~= "" then
        target = strip_trailing_backslash(target)
        local isdir = os.isdir(target)
        local isfile = not isdir and os.isfile(target) and is_env_file(target)
        if isdir or isfile then
            local files = {}
            local ok, found = load_trust(function(list)
                get_env_files(files, target, isdir)
                local save = false
                local trusted = false
                for _, file in ipairs(files) do
                    local index = list[file:lower()]
                    if index then
                        list[index] = false
                        list[file:lower()] = nil
                        save = true -- Save the updated trust file.
                        trusted = true
                    end
                end
                if save then
                    reindex_trust(list)
                end
                return save, trusted
            end)
            if ok then
                for _, file in ipairs(files) do
                    print("Removed '"..file.."' from the trust list.")
                end
            elseif found then
                report_error("trying to deny '"..target.."'.")
            end
            return
        end
    end
    report_error("'"..(orig_target or "").."' not recognized.")
end

local function prune_trust()
    local removed, kept = 0, 0
    local ok = load_trust(function(list)
        for index = #list, 1, -1 do
            local entry = list[index]
            local current = make_trust_entry(entry.file)
            if not current or current.timestamp > entry.timestamp then
                table.remove(list, index)
                removed = removed + 1
            else
                kept = kept + 1
            end
        end
        if removed > 0 then
            reindex_trust(list)
        end
        return true, true
    end)
    if ok then
        if removed > 0 then
            print(string.format("Allowed files: removed %u outdated, kept %u up to date.", removed, kept))
        else
            print(string.format("Allowed files: verified %u up to date.", kept))
        end
    else
        report_error("trying to prune outdated allowed files.")
    end
end

local function find_dotenv(dir)
    dir = dir and os.getfullpathname(dir) or os.getcwd()
    dir = strip_trailing_backslash(dir)
    local target = dir
    repeat
        local name
        local exists
        name = path.join(target, ".env.cmd")
        exists = os.isfile(name)
        if not exists then
            name = path.join(target, ".env")
            exists = os.isfile(name)
        end
        if exists then
            if is_trusted(name) then
                return name, dir
            else
                return nil, dir, name--[[blocked]]
            end
        end
        local parent = path.toparent(target)
        if parent == target then
            parent = nil
        end
        target = parent
    until not target
    return nil, dir
end

local function apply_dotenv(dotenv)
    last_dotenv = dotenv
    envrestore = {}

    if not dotenv then
        return
    end

    local order = {}
    local envvars = {}

    local mode = path.getname(dotenv):lower()
    if mode == ".env" then
        -- Load variables from a .env file.
        local f = io.open(dotenv)
        if f then
            for line in f:lines() do
                local name, value = line:match("^%s*([^=]+)%s*=(.*)$")
                if name then
                    local lower = name:lower()
                    envvars[lower] = value
                    if not order[lower] then
                        table.insert(order, name)
                        order[lower] = true
                    end
                end
            end
            f:close()
        end
    elseif mode == ".env.cmd" then
        -- Run a .env.cmd file in a separate CMD shell.
        local tag_before = "----===##_DIRENV_BEFORE_##===----"
        local tag_after = "----===##_DIRENV_AFTER_##===----"
        local cmd = string.format('2>nul echo %s&set&echo %s&call "%s"&echo %s&set&echo %s',
                                  tag_before, tag_before, dotenv, tag_after, tag_after)
        local f = io.popen(cmd)
        if f then
            -- Parse the variables before and after.
            local before = {}
            local after = {}
            local which
            for line in f:lines() do
                if line == tag_before then
                    which = not which and before or nil
                elseif line == tag_after then
                    which = not which and after or nil
                elseif which then
                    local name, value = line:match("^([^=]+)=(.*)$")
                    if name then
                        which[name] = value
                    end
                end
            end
            f:close()
            -- Find variables added or changed.
            for name, value in pairs(after) do
                if not before[name] or value ~= before[name] then
                    local lower = name:lower()
                    envvars[lower] = value
                    if not order[lower] then
                        table.insert(order, name)
                        order[lower] = true
                    end
                end
            end
            -- Find variables removed.
            for name, _ in pairs(before) do
                if not after[name] then
                    local lower = name:lower()
                    envvars[lower] = ""
                    if not order[lower] then
                        table.insert(order, name)
                        order[lower] = true
                    end
                end
            end
        end
    else
        report_error(string.format("unsupported file '%s'.", dotenv))
        return
    end

    -- Apply the variables.
    local hide_env_diff = settings.get("direnv.hide_env_diff")
    local diff_added = ""
    local diff_removed = ""
    local diff_changed = ""
    for _, name in ipairs(order) do
        local lower = name:lower()
        local value = envvars[lower]
        envrestore[lower] = os.getenv(name) or ""
        if not hide_env_diff then
            if envrestore[lower] ~= "" then
                if value ~= "" then
                    diff_changed = diff_changed.." ~"..name
                else
                    diff_removed = diff_removed.." -"..name
                end
            else
                if value ~= "" then
                    diff_added = diff_added.." +"..name
                end
            end
        end
        value = (value ~= "") and value or nil
        os.setenv(name, value)
    end

    -- Save envrestore in a sessionstream, if available.
    save_envrestore()

    -- Optionally print a list of added/removed/changed variables.
    if diff_added ~= "" or diff_removed ~= "" or diff_changed ~= "" then
        banner(string.format("direnv: set%s", diff_added..diff_removed..diff_changed))
    end
end

local function unset_dotenv()
    -- Just keep the old values in memory in a Lua table.  Reloading scripts
    -- loses them, but a newer version of Clink provides per-session streams
    -- which survive across creating a new Lua VM.
    for name, value in pairs(envrestore) do
        value = (value ~= "") and value or nil
        os.setenv(name, value)
    end
    clear_envrestore()
    last_dotenv = nil
end

local function reload_env(dir, force)
    assert(trust_list)

    local any
    local orig_dir = dir
    local dotenv, blocked
    dotenv, dir, blocked = find_dotenv(dir)
    if force or (dotenv ~= last_dotenv or dir ~= last_dir) then
        if last_dotenv and not dotenv then
            --banner("direnv: unloading envvars from '"..last_dotenv.."'", force)
            banner("direnv: unloading", force)
            any = true
        end

        unset_dotenv()

        if dotenv then
            banner("direnv: loading envvars from '"..dotenv.."'", force)
            any = true
        end
        if force and not any then
            banner("direnv: no .env or .env.cmd file found", force)
        elseif blocked then
            report_error(string.format("%s is blocked; run 'direnv allow' to approve its content.", blocked))
        end

        apply_dotenv(dotenv)
        if not force then
            last_dir = dir or orig_dir
        end

        -- CMD doesn't refresh its awareness of environment variables unless SET
        -- is used to set a variable.
        if any then
            provide_line = ">nul set __dummy_direnv_lua_clink__=1&>nul set __dummy_direnv_lua_clink__="
        end
    end
end

--------------------------------------------------------------------------------
add_help("allow", {
"Allow loading .env or .env.cmd file from a specified directory.",
"",
"Usage:",
"  direnv allow <directory>",
"",
"For security reasons, direnv will not load a .env or .env.cmd file until the",
"file has been specifically allowed by using this command.",
})

add_help("deny", {
"Deny loading .env or .env.cmd file from a specified directory.",
"",
"Usage:",
"  direnv deny <directory>",
"",
"This revokes trust for a file that was allowed by the 'direnv allow' command.",
})

add_help("edit", {
"Open the corresponding .env or .env.cmd file into %EDITOR% (or Notepad).",
"",
"Usage:",
"  direnv edit [<directory>]",
"",
"If no directory is specified, then the current directory is assumed.",
})

add_help("exec", {
"Execute a command after loading a .env or .env.cmd file from the specified",
"directory.",
"",
"Usage:",
"  direnv exec <directory> <command> [args ...]",
"",
"This changes to the specified directory and loads its corresponding .env or",
".env.cmd file, then runs the specified command, then restores the original",
"directory and reloads its .env or .env.cmd file.",
})

add_help("help", {
"Show help text for direnv.",
"",
"Usage:",
"  direnv help",
"",
"To see help for a specific command, run 'direnv <command> --help'.",
})

add_help("list", {
"List allowed .env and .env.cmd files.",
"",
"Usage:",
"  direnv list",
"",
"Directories may be allowed with the 'direnv allow' command or denied with",
"the 'direnv deny' command.",
})

add_help("prune", {
"remove outdated allowed files.",
"",
"Usage:",
"  direnv prune",
"",
"Removes entries from the trust list for any files which no longer exist or are",
"no longer trusted because the file has been modified since it was added to the",
"trust list.",
})

add_help("reload", {
"Trigger an env reload.",
"",
"Usage:",
"  direnv reload [<directory>]",
"",
"If a directory is specified, a .env or .env.cmd file is loaded from that",
"directory, superseding any .env or .env.cmd file from the current directory.",
"",
"If no directory is specified, a .env or .env.cmd file is reloaded from the",
"current directory, refreshing the environment.",
})

local function print_help(help)
    for _, text in ipairs(help) do
        if type(text) == "table" then
            print_help(text)
        else
            print(text)
        end
    end
end

--------------------------------------------------------------------------------
local function onbeginedit()
    if settings.get("direnv.enable") then
        load_trust()
        reload_env()
    end
end

local function onprovideline()
    if provide_line then
        local line = provide_line
        provide_line = nil
        return line
    end
end

local function get_line_text(line_state, word_index)
    local info = line_state:getwordinfo(word_index)
    local offset = info.offset - (info.quoted and 1 or 0)
    local line = line_state:getline()
    return line:sub(offset)
end

local function command_allow(line_state)
    local dir = line_state:getword(3)
    allow_trust(dir)
end

local function command_deny(line_state)
    local dir = line_state:getword(3)
    deny_trust(dir)
end

local function command_edit(line_state)
    local editor = os.getenv("EDITOR")
    editor = editor and editor:gsub("^%s+", ""):gsub("%s+$", "")
    if not editor or editor == "" then
        editor = path.join(os.getenv("SystemRoot"), "System32\\notepad.exe")
        editor = editor and editor:gsub("^%s+", ""):gsub("%s+$", "")
        if editor == "" then
            editor = nil
        elseif editor then
            editor = '"'..editor..'"'
        end
        if not editor then
            report_error("%EDITOR% is not set.")
            return
        end
    end

    local dir = line_state:getword(3)
    local dotenv = find_dotenv(dir)
    if not dotenv then
        if dir and dir ~= "" and is_env_file(path.getname(dir)) then
            dotenv = os.getfullpathname(dir)
        else
            report_error(".env or .env.cmd file not found; run 'direnv edit .env.cmd' to create.")
            return
        end
    end

    -- Launch the editor.
    local before = make_trust_entry(dotenv)
    print(string.format("Edit '%s'...", dotenv))
    os.execute(string.format('"%s "%s""', editor, dotenv))
    local after = make_trust_entry(dotenv)

    -- Automatically add to trust list if timestamp changed.
    if after and (not before or after.timestamp > before.timestamp) then
        allow_trust(dotenv)
    end
end

local function command_exec(line_state)
    local dir = line_state:getword(3)
    local exec = get_line_text(line_state, 4)

    if not os.isdir(dir) then
        print('"'..dir..'" is not a directory.')
        return
    end

    -- Load the environment for the dir.  The next prompt will automatically
    -- reload the environment for the current dir again.
    reload_env(dir)

    -- When the script is run in a standalone Lua engine, the script owns
    -- responsibility for executing the commands itself.
    if standalone then
        local old = os.getcwd()
        os.chdir(dir)
        os.execute(exec)
        os.chdir(old)
        banner("direnv: reverting envvars")
        return
    end

    -- Return command lines to execute.
    local lines = {
        " pushd \""..dir.."\" >nul"..echo_up(),
        exec,
        " popd >nul"..echo_up(),
    }
    return lines, false
end

local function command_help(arg)
    local command = ""
    if type(arg) == "string" then
        command = arg
    end

    local help = help_text[command]
    if help then
        print_help(help)
    else
        print(string.format("No help for '%s'.", command))
    end
end

local function command_list()
    if not load_trust() then
        report_error("trying to list trusted files.")
    elseif trust_list[1] then
        for _, entry in ipairs(trust_list) do
            print(entry.file)
        end
    else
        print("No trusted .env or .env.cmd files.")
    end
end

local function command_prune()
    prune_trust()
end

local function command_reload(line_state)
    local dir = line_state:getword(3)
    if dir == "" then
        dir = nil
    end
    reload_env(dir, true)
end

local direnv_commands = {
    ["allow"]   = command_allow,
    ["deny"]    = command_deny,
    ["edit"]    = command_edit,
    ["exec"]    = command_exec,
    ["help"]    = command_help,
    ["list"]    = command_list,
    ["prune"]   = command_prune,
    ["reload"]  = command_reload,
}

local function handle_args(line_state)
    if line_state:getwordcount() >= 1 then
        local word = line_state:getword(2)
        local func = direnv_commands[word]
        if func then
            local arg = line_state:getword(3)
            if arg == "-?" or arg == "--help" then
                command_help(word)
            else
                local sret, bret = func(line_state)
                if sret then
                    return sret, bret
                end
            end
        else
            report_error(string.format("unrecognized command '%s'.", word))
            print()
            command_help()
        end
    else
        command_help()
    end
end

local function onfilterinput(line)
    if not line:find("direnv") then
        return
    end

    local commands = clink.parseline(line)
    if not commands or not commands[1] then
        return
    end

    local line_state = commands[1].line_state
    if line_state and line_state:getwordcount() >= 1 and line_state:getword(1) == "direnv" then
        if not settings.get("direnv.enable") then
            print("Direnv is not enabled.")
            print("It can be enabled by running 'clink set direnv.enable true'.")
            return "", false
        end

        local sret, bret = handle_args(line_state)
        if sret then
            return sret, bret
        end
        return "", false
    end
end

if standalone then

    local line = "direnv"
    for _, word in ipairs(arg) do
        if not word:find('^"') and word:find("[ \t|&<>]") then
            word = '"'..word..'"'
        end
        line = line.." "..word
    end

    local commands = clink.parseline(line)
    if not commands or not commands[1] then
        return
    end

    local line_state = commands[1].line_state
    if line_state then
        load_trust()
        local sret, _ = handle_args(line_state)
        assert(sret == nil)
    end

else

    clink.onbeginedit(onbeginedit)
    clink.onprovideline(onprovideline)
    clink.onfilterinput(onfilterinput)

end

--------------------------------------------------------------------------------
if not standalone then

    envrestore = {}
    if clink.opensessionstream then
        local e = clink.opensessionstream("direnv_restore", "r")
        if e then
            for line in e:lines() do
                local name, value = line:match("^([^=]+)=(.*)$")
                if name then
                    value = value or ""
                    envrestore[name] = value
                end
            end
            e:close()
        end
    end

    local help_flags = {
        { "-?", "Show help text" },
        { "--help", "Show help text" },
    }

    local noarg_parser = clink.argmatcher():_addexflags(help_flags):nofiles()
    local dirarg_parser = clink.argmatcher():_addexflags(help_flags):addarg(clink.dirmatches):nofiles()
    local exec_parser = clink.argmatcher():_addexflags(help_flags):addarg(clink.dirmatches):chaincommand()

    clink.argmatcher("direnv")
    :_addexflags(help_flags)
    :_addexarg({
        { "allow"..dirarg_parser, " dir", "Allow loading environment from dir" },
        { "deny"..dirarg_parser, " dir", "Deny loading environment from dir" },
        { "edit"..dirarg_parser, " [dir]", "Open the corresponding .env or .env.cmd file into %EDITOR% (or Notepad)" },
        { "exec"..exec_parser, " dir command [args]", "Execute a command after loading a .env or .env.cmd file from dir" }, -- luacheck: no max line length
        { "help"..noarg_parser, "Show help text" },
        { "list"..noarg_parser, "List allowed .env and .env.cmd files" },
        { "prune"..noarg_parser, "Prune the trust list to remove outdated allowed files." },
        { "reload"..dirarg_parser, " [dir]", "Trigger an env reload" },
    })

end

