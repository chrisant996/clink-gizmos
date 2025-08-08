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
"the next, this script looks for a .env file with environment variables.  If",
"it finds one, then it applies environment variables from it to the current",
"environment.  When changing away to a different directory, then it unsets any",
"environment variables that were applied from the most recent .env file.",
"",
"By default, direnv starts out disabled and does nothing at all.  To enable",
"it, run 'clink set direnv.enable true'.  Once enabled, it only works in",
"directories it's been told to trust.",
"",
"By default, direnv starts out not trusting any directories.  It only looks",
"for .env files in directories that it has been told to trust.  Using 'direnv",
"allow directory_name' is how to tell direnv to trust a specific directory.",
"Trust is NOT recursive; trusting a parent directory does not establish trust",
"for any child directories beneath it.",
"",
"The format for a .env file is one variable definition per line, and each",
"variable definition is a name, an equal sign, and a value.  For example:",
"  VAR_NAME=VALUE",
"",
"Available commands:",
"  allow                 Allow loading .env file from dir.",
"  deny                  Deny loading .env file from dir.",
"  edit                  Open correponding .env file in an editor.",
"  exec                  Execute command after loading .env from dir.",
"  help                  Show this help text.",
"  list                  List allowed directories for .env files.",
"  prune                 Prune the trust list to remove outdated allowed files.",
"  reload                Trigger an env reload.",
"",
"For help on a specific command, run 'direnv <command> --help'.",
"For example 'direnv exec --help'.",
"",
"Clink settings for direnv:",
"  direnv.enable         True enables direnv, or false (the default) disables it.",
"  direnv.banner         True (the default) shows feedback when loading .env files.",
"  direnv.hide_env_diff  True hides env changes, or false (the default) shows",
"                        which environment variables are applied.",
"  color.direnv_banner   The color for direnv banner messages.",
"",
"Notes:",
"- The https://direnv.net project supports .envrc shell scripts, but those",
"  don't work with CMD on Windows.  Maybe someday direnv for Clink will add",
"  support for .env.cmd scripts.",
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

settings.add("direnv.enable", false, "Auto-apply env vars from .env files",
    "When this is enabled and the current directory (or any of its parents)\n"..
    "contains a .env file, then the environment variable assignments listed in\n"..
    "the .env file are automatically applied.  When the current directory changes\n"..
    "again to somewhere else, then the variables from the .env file are\n"..
    "automatically cleared.")
settings.add("direnv.banner", true, "Show feedback when loading .env files")
settings.add("direnv.hide_env_diff", false, "Hides feedback about env changes")
settings.add("color.direnv_banner", direnv_banner, "Color for direnv banner messages")

end

local last_dotenv
local last_dir
local envvars = {}
local envrestore = {}
local trusted = {}
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
local function get_trust_filename()
    local profile_dir = os.getenv("=clink.profile")
    if profile_dir and profile_dir ~= "" then
        local filename = path.join(profile_dir, "direnv_trust")
        return filename
    end
end

local function is_trusted(name, list)
    list = list or trusted
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
    for num, entry in ipairs(list) do
        trusted[entry.file:lower()] = num
    end
end

local function load_trust(callback)
    trusted = {}

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
            table.insert(trusted, {file=name, timestamp=tonumber(timestamp)})
        end
    end
    reindex_trust(trusted)

    -- Strip trailing blank lines (compensates for the truncation workaround).
    for trim = #trusted, 1, -1 do
        if trusted[trim] ~= "" then
            break
        end
        trusted[trim] = nil
    end

    -- Run callback function.
    local ret
    local callback_ret
    if not callback then
        ret = true
    else
        local save
        save, callback_ret = callback(trusted)
        if save then
            if not f:seek("set") then
                log.info("direnv unable to update '"..trust_filename.."'.")
                f:close()
                return
            end
            -- Write the lines.
            for _, e in ipairs(trusted) do
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

local function allow_trust(target)
    local orig_target = target
    target = (target == "") and "." or target
    target = (target and os.getfullpathname(target)) or ""
    if target ~= "" then
        target = strip_trailing_backslash(target)
        local isdir = os.isdir(target)
        local isfile = not isdir and os.isfile(target) and path.getname(target):lower() == ".env"
        if isdir or isfile then
            local file
            local ok, found = load_trust(function(list)
                file = isdir and path.join(target, ".env") or target
                if not is_trusted(file, list) then
                    local entry = make_trust_entry(file)
                    if not entry then
                        return false, false
                    end
                    table.insert(list, entry)
                    list[file:lower()] = #list
                    return true, false -- Save the updated trust file.
                else
                    return false, true -- Already trusted.
                end
            end)
            if ok then
                print("Added '"..file.."' to the trust list.")
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
        local isfile = not isdir and os.isfile(target) and path.getname(target):lower() == ".env"
        if isdir or isfile then
            local file
            local ok, found = load_trust(function(list)
                file = isdir and path.join(target, ".env") or target
                local index = list[file:lower()]
                if index then
                    table.remove(list, index)
                    list[file:lower()] = nil
                    reindex_trust(list)
                    return true, true -- Save the updated trust file.
                else
                    return false, false -- Not found.
                end
            end)
            if ok then
                print("Removed '"..file.."' from the trust list.")
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
        local name = path.join(target, ".env")
        if os.isfile(name) then
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
    envvars = {}
    envrestore = {}

    if dotenv then
        local f = io.open(dotenv)
        if f then
            local order = {}
            for line in f:lines() do
                local name, value = line:match("^%s*([^=]+)%s*=(.*)$")
                if name then
                    local lower = name:lower()
                    envvars[lower] = value
                    envrestore[lower] = os.getenv(name) or ""
                    if not order[lower] then
                        table.insert(order, name)
                        order[lower] = true
                    end
                end
            end
            local hide_env_diff = settings.get("direnv.hide_env_diff")
            local diff_added = ""
            local diff_removed = ""
            local diff_changed = ""
            for _, name in ipairs(order) do
                local lower = name:lower()
                local value = envvars[lower]
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
            if diff_added ~= "" or diff_removed ~= "" or diff_changed ~= "" then
                banner(string.format("direnv: set%s", diff_added..diff_removed..diff_changed))
            end
        end
    end
end

local function unset_dotenv()
    -- Any old values to restore are currently only saved in memory in a Lua
    -- table, so reloading scripts loses them.  Ideally the values could be
    -- saved such that reloading scripts doesn't lose them.  But the values also
    -- need to be stored separately for each CMD session, and that creates a bit
    -- of a challenge for discarding them appropriately and making sure they
    -- don't carry over to a new and different CMD session that happens to reuse
    -- the same process ID.
    for name, value in pairs(envrestore) do
        value = (value ~= "") and value or nil
        os.setenv(name, value)
    end
    envvars = {}
    envrestore = {}
    last_dotenv = nil
end

local function reload_env(dir, force)
    assert(trusted)

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
            banner("direnv: no .env file found", force)
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
"Allow loading .env file from a specified directory.",
"",
"Usage:",
"  direnv allow <directory>",
"",
"For security reasons, direnv will not load a .env file from a directory",
"until the directory has been specifically allowed by using this command.",
})

add_help("deny", {
"Deny loading .env file from a specified directory.",
"",
"Usage:",
"  direnv deny <directory>",
"",
"This revokes a directory that was allowed by the 'direnv allow' command.",
})

add_help("edit", {
"Open the corresponding .env file into %EDITOR% (or Notepad).",
"",
"Usage:",
"  direnv edit [<directory>]",
"",
"If no directory is specified, then the current directory is assumed.",
})

add_help("exec", {
"Execute a command after loading a .env file from the specified directory.",
"",
"Usage:",
"  direnv exec <directory> <command> [args ...]",
"",
"This changes to the specified directory and loads its corresponding .env",
"file, then runs the specified command, then restores the original directory",
"and reloads its .env file.",
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
"List allowed directories for loading a .env file.",
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
"If a directory is specified, a .env file is loaded from that directory,",
"superseding any .env file from the current directory.",
"",
"If no directory is specified, a .env file is reloaded from the current",
"directory, refreshing the environment.",
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
    end
    if editor then
        local dir = line_state:getword(3)
        local dotenv = find_dotenv(dir)
        dotenv = dotenv or path.join(os.getcwd(), ".env")
        local before = make_trust_entry(dotenv)

        -- Launch the editor.
        print(string.format("Edit '%s'...", dotenv))
        os.execute(string.format('"%s "%s""', editor, dotenv))

        -- Automatically add to trust list if timestamp changed.
        local after = make_trust_entry(dotenv)
        if after and (not before or after.timestamp > before.timestamp) then
            allow_trust(dotenv)
        end
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
        report_error("trying to list trusted directories.")
    elseif trusted[1] then
        for _, entry in ipairs(trusted) do
            print(entry.file)
        end
    else
        print("No trusted directories for loading .env files.")
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
        { "allow"..dirarg_parser, " dir", "Allow loading .env file from dir" },
        { "deny"..dirarg_parser, " dir", "Deny loading .env file from dir" },
        { "edit"..dirarg_parser, " [dir]", "Open the corresponding .env file into %EDITOR% (or Notepad)" },
        { "exec"..exec_parser, " dir command [args]", "Execute a command after loading a .env file from dir" },
        { "help"..noarg_parser, "Show help text" },
        { "list"..noarg_parser, "List allowed directories for loading a .env file" },
        { "prune"..noarg_parser, "Prune the trust list to remove outdated allowed files." },
        { "reload"..dirarg_parser, " [dir]", "Trigger an env reload" },
    })

end

