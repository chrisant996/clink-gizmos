--------------------------------------------------------------------------------
-- FZF and RipGrep integration for Clink.
--
--
-- This provides a command for showing a list of files matching a search pattern
-- and opening the files your editor.
--
--      CTRL-X,F        = Start fzf and search files using ripgrep.
--      CTRL-X,CTRL-F   = Start fzf and search files using ripgrep.
--
--
-- REQUIREMENTS:
--
-- This requires Clink, FZF, ripgrep, and optionally bat:
--
--  - Clink is available at https://chrisant996.github.io/clink
--  - FZF is available from https://github.com/junegunn/fzf
--    (version 0.67.0 or newer work; older versions may or may not work)
--  - RipGrep is available from https://github.com/BurntSushi/ripgrep
--    (version 15.1.0 or newer work; older versions may or may not work)
--  - Bat is available from https://github.com/sharkdp/bat
--    (version 0.26.1 or newer work; older versions may or may not work)
--
--
-- DEFAULT KEY BINDINGS:
--
-- Each default key binding here is only applied if the key isn't already bound
-- to something else.  You may also set key bindings manually in your .inputrc
-- file.
--[[

# Default key bindings for fzf_ripgrep.
"\C-xf":    "luafunc:fzf_ripgrep"   # CTRL-X,f Show a FZF filtered view with files matching search term
"\C-x\C-f": "luafunc:fzf_ripgrep"   # CTRL-X,CTRL-F Show a FZF filtered view with files matching search term

]]
-- KEYS IN FZF:
--
-- These keys perform special functions while searching with fzf and ripgrep.
-- See fzf documentation for info about other general keys available in fzf.
--
--      ESC             = Exit.
--      ENTER           = Open the selected file in an editor.
--      ALT-I           = Insert the selected file into the input line.
--
--      CTRL-/          = Toggles the preview pane on the right.
--      CTRL-\          = Toggles the preview pane on the bottom.
--
--      CTRL-R          = Use ripgrep mode; list matches in files.
--      CTRL-G          = Use fzf mode; filter matches further.
--
--      CTRL-U          = Clear the query text.
--
--
-- EDITOR:
--
--  TODO:  Document fzf_rg.editor.
--  TODO:  Document how the editor configuration works (and placeholder tokens).
--
--
-- ENVIRONMENT VARIABLES:
--
--  FZF_RG_EDITOR       = Command to launch editor (expands placeholder tokens).
--  FZF_RG_FZF_OPTIONS  = Options to add to the fzf commands.
--  FZF_RG_RG_OPTIONS   = Options to add to the rg commands.

--------------------------------------------------------------------------------
-- luacheck: no max line length

if not clink.argmatcher then
    -- This script invokes itself as a standalone Lua script for some things.
    if arg[1] == "--tqf" or arg[1] == "--tqr" then
        -- Transform query between ripgrep mode and fzf mode.
        local temp = os.getenv("TEMP")
        if temp then
            local opposite = { ["f"]="r", ["r"]="f" }
            local rletter = arg[1]:sub(-1)
            local wletter = opposite[rletter]
            -- Write the old mode's query argument to the old mode's file.
            local wfile = path.join(temp, "fzf_rg_"..wletter..".tmp")
            local w = io.open(wfile, "w")
            if w then
                w:write(arg[2] or "")
                w:close()
            end
            -- Read and print the new mode's query string from its file..
            local rfile = path.join(temp, "fzf_rg_"..rletter..".tmp")
            local r = io.open(rfile, "r")
            if r then
                print(r:read() or "")
                r:close()
            end
        end
    end
    return
end

-- luacheck: globals fzf_rg_loader_arbiter
fzf_rg_loader_arbiter = fzf_rg_loader_arbiter or {}
if fzf_rg_loader_arbiter.initialized then
    local msg = 'fzf_rg.lua was already fully initialized'
    if fzf_rg_loader_arbiter.loaded_source then
        msg = msg..' ('..fzf_rg_loader_arbiter.loaded_source..')'
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

maybe_add("fzf_rg.show_preview", {"right","bottom","off"}, "Show preview window by default in fzf",
[[The default is 'right', which shows a preview window on the right side.
Set to 'bottom' to show a preview window on the bottom side.
Set to 'off' to hide the preview window by default.
Regardless whether the preview window is initially shown, it can be toggled
on/off at any time while using fzf.

The preview automatically finds and uses batcat.exe or bat.exe if available in
the system PATH, otherwise it shows a plain text preview.

The bat tool is available here:  https://github.com/sharkdp/bat]]
)

maybe_add("fzf_rg.editor", "", "Configures how to invoke the editor",
[[This is a command line to execute for opening a file into an editor.  If this
is not set, then %FZF_RG_EDITOR% is used instead (and supports the same token
replacements).  If neither are found, then %EDITOR% or notepad are used and the
filename is appended (if the editor program is recognized then the line number
may be automatically added with an appropriate command line syntax as well).

The following token replacements can be used in fzf_rg.editor and FZF_RG_EDITOR:
    - {file} is replaced with the selected filename.  The filename is
      automatically quoted when needed, but if a quote is adjacent to {file}
      then quoting is disabled (e.g. an editor might require "{file}@{line}").
      If {file} is omitted, then the filename is automatically appended to the
      end of the command.
    - {line} is replaced with the selected line number.
    - {$envvar} is replaced with the value of %envvar% (with any newlines
      replaced with spaces).

Usually an editor supports one of the following formats:
    - vscode:                       {editor} --goto {file}:{line}
    - sublime, emacs, hx, micro:    {editor} {file}:{line}
    - notepad++:                    {editor} -n {line} {file}
    - ultraedit:                    {editor} file/line
    - EditPlus:                     {editor} -cursor {line}:1 {file}
    - pspad:                        {editor} /{line} {file}
    - JetBrains (idea, storm, ..):  {editor} --line {line} {file}
    - vim, nano:                    {editor} +{line} {file}
    - notepad:                      {editor} {file}

If setting from the command line you may need to escape the " character as \".]]
)

local describemacro_list = {}
local cached_preview_command
local cached_preview_has_bat

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

local function need_quote(word)
    return word and word:find("[ &()[%]{}^=;!%%'+,`~]") and true
end

local function maybe_quote(word)
    if need_quote(word) then
        word = '"'..word..'"'
    end
    return word
end

local function get_color_mode()
    return os.getenv("NO_COLOR") and "never" or "always"
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

local function get_reload_command()
    -- This is the ripgrep command to run.
    local rg_command = table.concat({
        "rg",
        "--column",
        "--line-number",
        "--no-heading",
        "--color="..get_color_mode(),
        "--smart-case",
        (os.getenv("FZF_RG_RG_OPTIONS") or ""):gsub('"', '\\"'),
        "{q}",
    }, " ")

    -- This takes care to only run ripgrep if the query string is not empty.
    -- This matters because otherwise ripgrep immediately starts loading all
    -- file content under the current directory (which can be over 100GB in
    -- in some repos).  And all that's visible is always only the first few
    -- lines of the first file; not very useful.

    -- How this technique works is nuanced; here is a detailed breakdown:
    return
        -- Echo an escaped form of the query string.  When empty, it is ^"^"
        -- which is printed as "", which is 2 characters long.  Note carefully
        -- that there is no space between this and the subsequent | operator.
        -- The presence of a space would change the regex pattern to match.
        [[echo {q}]]..
        -- Pipe into findstr and look for at least 3 characters, and redirect to
        -- nul so the matched string is not printed.
        [[| findstr ... >nul]]..
        -- If the pattern matched (not empty) then run ripgrep.
        [[&& ]]..rg_command..
        -- If the pattern did not match then clear errorlevel, otherwise fzf
        -- thinks the command failed and reports an error.
        [[|| ver >nul]]

    -- echo ^"^"| findstr ... >nul&& echo match|| echo mismatch
    -- mismatch
    --
    -- echo ^" ^"| findstr ... >nul&& echo match|| echo mismatch
    -- match
end

local function isnilorempty(s)
    return (s == nil or s == "")
end

local function apply_placeholders(command, file, line)
    local applied = ""
    local has_file

    local i = 1
    while true do
        local s, e = command:find("{$?[^ %p]+}", i)
        if not s then
            -- No more placeholders; append the rest of the command.
            applied = applied..command:sub(i)
            break
        end

        -- Append up to the placeholder.
        applied = applied..command:sub(i, s - 1)

        -- Expand the placeholder.
        local placeholder = command:sub(s, e):lower()
        if placeholder:find("^.%$") then
            applied = applied..(os.getenv(command:sub(s + 2, e - 1)):gsub("\n", " "))
        elseif placeholder == "{line}" then
            applied = applied..(line or "1")
        elseif placeholder == "{file}" then
            -- If a quote is adjacent to the {file} placeholder then do not
            -- add quotes, otherwise automatically add quotes if needed.
            if command:sub(s - 1) == '"' or command:sub(e + 1) == '"' then
                applied = applied..file
            else
                applied = applied..maybe_quote(file)
            end
            has_file = true
        else
            applied = applied..placeholder
        end

        -- Advance past the placeholder.
        i = e + 1
    end

    -- If there's no {file} placeholder then append the filename.
    if not has_file then
        applied = applied.." "..maybe_quote(file)
    end

    return applied
end

-- Returns command filename string, and a Boolean indicating whether the input
-- command string is quotable (i.e. is an exact filename).
local function extract_command_filename(command, found_placeholders)
    if found_placeholders then
        command = apply_placeholders(command, "||||||||", "||||||||")
    end

    if os.isfile(command) then
        return command, true
    end

    command = command:gsub("^%s+", "")

    local filename = command:match('^"([^"]+)"')
    if filename then
        return filename
    end

    local words = string.explode(command)
    if words and words[1] then
        return words[1]
    end
end

local function infer_placeholders(command, found_placeholders, line)
    local haystack = command:lower()
    local command_filename, quotable = extract_command_filename(command, found_placeholders)
    if command_filename then
        haystack = path.getname(command_filename)
    end

    local function test(...)
        for _, pattern in ipairs({...}) do
            for _, suffix in ipairs({'', '%.exe', '%.cmd', '%.bat', '%.pl', '%.py'}) do
                if haystack == pattern or
                        haystack == pattern..suffix:sub(2) or
                        haystack:find('^"?'..pattern..suffix..'[ "]') or
                        haystack:find('[ "/\\]'..pattern..suffix..'[ "]') then
                    return true
                end
            end
        end
    end

    local added_placeholders
    local function append_placeholder(text, delimiter)
        added_placeholders = true
        command = command..(delimiter or " ")..text
    end

    if quotable then
        command = maybe_quote(command)
    end

    -- 1. Modern IDEs & Cross-platform (VS Code, Zed, Sublime).
    if test("code") or
            test("zed") then
        append_placeholder("--goto {file}")
        if not isnilorempty(line) then
            append_placeholder(":{line}", "")
        end
    elseif test("subl") or
            test("emacs") or
            test("hx") or
            test("micro") then
        append_placeholder("{file}")
        if not isnilorempty(line) then
            append_placeholder(":{line}", "")
        end

    -- 2. Notepad++.
    elseif test("notepad++") or
            test("npp") then
        if not isnilorempty(line) then
            append_placeholder("-n{line}")
        end
        append_placeholder("{file}")

    -- 3. UltraEdit (uedit64 / uedit32).
    elseif test("uedit") then
        append_placeholder("{file}")
        if not isnilorempty(line) then
            append_placeholder("/{line}", "")
        end

    -- 4. EditPlus.
    elseif test("editplus") then
        if not isnilorempty(line) then
            append_placeholder("-cursor {line}:1")
        end
        append_placeholder("{file}")

    -- 5. PSPad.
    elseif test("pspad") then
        if not isnilorempty(line) then
            append_placeholder("/{line}")
        end
        append_placeholder("{file}")

    -- 6. JetBrains (IntelliJ, WebStorm, etc).
    elseif test("idea") or
            test("storm") or
            test("rider") then
        if not isnilorempty(line) then
            append_placeholder("--line {line}")
        end
        append_placeholder("{file}")

    -- 7. CLI Editors (Vim, Nano, Edit).
    elseif test("vim") or
            test("nano") or
            test("edit") then
        if not isnilorempty(line) then
            append_placeholder(" +{line}")
        end
        append_placeholder("{file}")
    else
        append_placeholder("{file}")
    end

    return command, added_placeholders
end

local function get_editor()
    local command = settings.get("fzf_rg.editor") or ""
    if command == "" then
        command = os.getenv("FZF_RG_EDITOR") or ""
    end

    local found_placeholders = (command:find("{.*}") and true or nil)
    if command == "" then
        command = os.getenv("EDITOR") or ""
        if command == "" then
            command = path.join(os.getenv("windir"), "System32\\notepad.exe")
        end
    end

    return command, found_placeholders
end

local function get_editor_nickname()
    local command, found_placeholders = get_editor()
    local command_filename = extract_command_filename(command, found_placeholders)
    command_filename = command_filename and path.getbasename(command_filename) or command
    if console.ellipsify then
        command_filename = console.ellipsify(command_filename, 16)
    end
    return command_filename
end

local function edit_file(rl_buffer, file, line)
    local command, found_placeholders = get_editor()

    if not found_placeholders then
        command, found_placeholders = infer_placeholders(command, found_placeholders, line)
    end

    if found_placeholders then
        command = apply_placeholders(command, file, line)
    else
        command = command.." "..maybe_quote(file)
    end

    -- Avoid garbling the prompt and input line display in case the editor is a
    -- terminal-based program.
    rl_buffer:beginoutput()

    -- If the command line to execute begins with a quote and contains
    -- more than one pair of quotes, then special quote handling is
    -- necessary.
    if command:find('^%s*"') then
        os.execute('cmd /s /c "'..command..'"')
    else
        os.execute(command)
    end
end

local function extract_file_and_line(item)
    -- fzf output format: file:line:column:text
    return item:match("([^:]+):([^:]+):")
end

local function tq_command(mode)
    local script
    do
        local info = debug.getinfo(1, "S")
        if info.source and info.source:sub(1, 1) == "@" then
            script = info.source:sub(2)
        elseif info.source then
            log.info(string.format("Unexpected source path '%s'.", info.source))
        else
            log.info(string.format("Unable to get source path for script."))
        end
    end
    if not script then
        return "rem"
    end
    -- Any quotes need to be escaped the same way {q} does, since the resulting
    -- string gets embedded inside a quoted string.
    local exe = string.format("%q", CLINK_EXE):gsub('"', '\\"')
    local lua = string.format("%q", script):gsub('"', '\\"')
    return string.format("2>nul %s lua %s --tq%s {q}", exe, lua, mode)
end

local function get_preview_config()
    local initial = settings.get("fzf_rg.show_preview")

    local function get_preview_start()
        local orientation = (initial == "off") and "right" or initial
        local border = orientation == "right" and ",border-left" or ",border-top"
        return (initial == "off") and
            orientation..":hidden" or
            orientation..":40%"..border
    end

    local function get_preview_cycle(orientation)
        local border = orientation == "right" and ",border-left" or ",border-top"
        local order = {
            orientation..":40%"..border,
            orientation..":70%"..border,
            "hidden",
        }
        if initial ~= "off" and orientation == initial then
            table.insert(order, order[1])
            table.remove(order, 1)
        end
        return table.concat(order, "|")
    end

    local function get_preview_command()
        if not cached_preview_command then
            local def_color = get_color_mode()
            local def_bat_opts = table.concat({
                os.getenv("BAT_STYLE") and "" or "--style=full",
                "--color="..def_color,
                "--decorations="..def_color,
                "--pager=never",
                "--highlight-line {2}",
            }, " ")

            -- Sometimes bat is installed as batcat
            local bat = search_in_paths("batcat.exe")
            if not bat then
                bat = search_in_paths("bat.exe")
            end
            if bat then
                cached_preview_command = bat:gsub("\\", "\\\\").." "..def_bat_opts.." {1}"
            else
                cached_preview_command = "type {1}"
            end
            cached_preview_has_bat = bat
        end
        return cached_preview_command, cached_preview_has_bat
    end

    local preview_command, bat = get_preview_command()
    local header_lines = bat and "4" or "0"
    local args = {
        [[--bind "ctrl-/:change-preview-window(]]..get_preview_cycle("right")..[[)"]],
        [[--bind "ctrl-\\:change-preview-window(]]..get_preview_cycle("bottom")..[[)"]],
        [[--bind "shift-down:preview-down+preview-down,shift-up:preview-up+preview-up,preview-scroll-up:preview-up+preview-up,preview-scroll-down:preview-down+preview-down"]],
        [[--preview-window "]]..get_preview_start()..[[,+{2}+]]..header_lines..[[/2,~]]..header_lines..[[" ]],
        [[--preview "]]..preview_command..[["]],
    }
    return table.unpack(args)
end

local function get_header_text()
    local header =
    "ENTER (edit via "..get_editor_nickname()..")  ALT-I (insert)  CTRL-/ or \\\\ (preview at right or bottom)\n"..
    "CTRL-R (ripgrep mode)  CTRL-F (fzf mode)  CTRL-U (clear query)"
    return header
end

add_help_desc("luafunc:fzf_ripgrep", "Show a FZF filtered view with files matching search term")

-- luacheck: globals fzf_ripgrep
-- Define the search and pick function.
function fzf_ripgrep(rl_buffer, line_state) -- luacheck: no unused
    -- Get the current text in the command line as the search query.
    local query = rl_buffer:getbuffer()

    -- {q} is the placeholder for the fzf input string.

    -- If the line is empty, let ripgrep prompt for input inside fzf.
    -- Otherwise, use the current line as the initial ripgrep query.
    local reload_command = get_reload_command()
    local expect = "alt-i"
    local args = {
        "--height 75%",
        "--reverse",
        -- Allow some customization.
        os.getenv("FZF_RG_FZF_OPTIONS") or "",
        -- Preserve and display ANSI color codes.
        "--ansi",
        -- Delimiter for fields in lines.
        [[--delimiter :]],
        -- Borders.
        [[--header "]]..get_header_text()..[["]],
        [[--header-border line]],
        -- %q adds safe quotes.
        string.format("--query %q", query),
        -- Initial mode (ripgrep).
        [[--disabled]],                         -- Disable fzf filtering (ripgrep will filter).
        [[--prompt "🔎 ripgrep> "]],
        -- Mode changes (ripgrep/fzf).
        [[--bind "ctrl-f:unbind(change,ctrl-f)+change-prompt(🔎 fzf> )+enable-search+rebind(ctrl-r)+transform-query(]]..tq_command("f")..[[)"]],
        [[--bind "ctrl-r:unbind(ctrl-r)+change-prompt(🔎 ripgrep> )+disable-search+rebind(change,ctrl-f)+transform-query(]]..tq_command("r")..[[)+reload(]]..reload_command..[[)"]],
        [[--color "hl:-1:underline:reverse,hl+:-1:underline:reverse"]],
        -- Query.
        [[--bind "start:reload(]]..reload_command..[[)+unbind(ctrl-r)"]],
        [[--bind "change:reload(]]..reload_command..[[)"]],
        -- Preview.
        get_preview_config(),
    }

    -- When expect is a comma separated list of key names, any of those keys
    -- is returned from fzf for post-processing.  When the --expect flag is
    -- present, the first line of output is always either one of the expected
    -- key names or a blank line (if some other key exited fzf).
    if expect then
        table.insert(args, '--expect='..expect)
        for _, key in ipairs(string.explode(expect, ',')) do
            table.insert(args, '--bind "'..key..':accept"')
        end
    end

    -- Delete any fzf mode query temporary file, so switching to fzf mode starts
    -- out with an empty query string.
    os.remove(path.join(os.getenv("TEMP"), "fzf_rg_f.tmp"))

    -- Open a pipe to capture the fzf output.
    local key
    local results = {}
    do
        local old_opts = os.getenv("FZF_DEFAULT_OPTS")
        local fzf_opts = table.concat(args, " ")
        os.setenv("FZF_DEFAULT_OPTS", (old_opts or "").." "..fzf_opts)
        local handle = io.popen("fzf")
        os.setenv("FZF_DEFAULT_OPTS", old_opts)
        if not handle then
            rl_buffer:ding()
            return
        end

        for line in handle:lines() do
            if expect and not key then
                key = line
            elseif line ~= "" then
                table.insert(results, line)
            end
        end
        handle:close()
    end

    -- Redraw the prompt and input line.
    rl_buffer:refreshline()

    -- If the user cancelled fzf, result will be empty.
    if not results or not results[1] then
        return
    end

    -- Get the file and line from the selected item.
    local file, line = extract_file_and_line(results[1])
    if not file or not line then
        rl_buffer:ding()
        return
    end

    -- Do what the user requested.
    local action = (key == "alt-i") and "insert-cursor" or "edit"
    if action == "edit" then
        -- Discard what the user might have started with.
        rl.invokecommand("clink-reset-line")
        -- Open the file in an editor.
        edit_file(rl_buffer, file, line)
    elseif action:find("^insert%-") then
        rl_buffer:beginundogroup()
        if action == "insert-cursor" then -- luacheck: ignore 542
        elseif action == "insert-word" then
            -- Eat non-spaces walking backwards from cursor.
            local cursor = rl_buffer:getcursor()
            local i = cursor
            local text = rl_buffer:getbuffer()
            while i > 1 do
                if string.byte(text, i - 1) == 32 then
                    break
                end
                i = i - 1
            end
            rl_buffer:remove(i, cursor)
        elseif action == "insert-line" then
            -- Replace the whole line.
            rl_buffer:remove(1, -1)
        end
        rl_buffer:insert(maybe_quote(file))
        rl_buffer:insert(" ")
        rl_buffer:endundogroup()
    else
        rl_buffer:ding()
        return
    end
end

local function apply_default_bindings()
    if rl.getbinding then
        for _, keymap in ipairs({"emacs", "vi-command", "vi-insert"}) do
            if not rl.getbinding([["\C-xf"]], keymap) then
                rl.setbinding([["\C-xf"]], [["luafunc:fzf_ripgrep"]], keymap)
            end
            if not rl.getbinding([["\C-x\C-f"]], keymap) then
                rl.setbinding([["\C-x\C-f"]], [["luafunc:fzf_ripgrep"]], keymap)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Delayed initialization shim.  Check for multiple copies of the script being
-- loaded in the same session.  This became necessary because Cmder wanted to
-- include fzf.lua, but users may have already installed a separate copy of the
-- script.

fzf_rg_loader_arbiter.ensure_initialized = function()
    assert(not fzf_rg_loader_arbiter.initialized)

    describe_commands()
    apply_default_bindings()

    local info = debug.getinfo(1, "S")
    local source = info and info.source or nil

    fzf_rg_loader_arbiter.initialized = true
    fzf_rg_loader_arbiter.loaded_source = source
end

clink.onbeginedit(function()
    -- Do delayed initialization if it hasn't happened yet.
    if fzf_rg_loader_arbiter.ensure_initialized then
        fzf_rg_loader_arbiter.ensure_initialized()
        fzf_rg_loader_arbiter.ensure_initialized = nil
    end

    -- Clear the cached preview command when starting a new input line, to
    -- search the system PATH again and construct an updated preview command.
    cached_preview_command = nil
end)
