--------------------------------------------------------------------------------
-- Provides a command for showing a list of files matching a search pattern and
-- opening the files your editor.
--
-- KEY BINDING:
--
--  Each default key binding here is only applied if the key isn't already bound
--  to something else.
--
--  You may also set key bindings manually in your .inputrc file.
--
--[[

# Default key bindings for fzf_ripgrep.
"\C-Xf":    "luafunc:fzf_ripgrep"   # CTRL-X,f Show a FZF filtered view with files matching search term

]]
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
                w:write(arg[2])
                w:close()
            end
            -- Read and print the new mode's query string from its file..
            local rfile = path.join(temp, "fzf_rg_"..rletter..".tmp")
            local r = io.open(rfile, "r")
            if r then
                print(r:read())
                r:close()
            end
        end
    end
    return
end

if os.getenv("WHICH_RIPGREP_SCRIPT") ~= "chrisant996" then
    return
else
    print("\x1b[3mUsing fzf_rg.lua script.\x1b[m")
end

local cached_preview_command

local function add_desc(macro, desc)
    if rl.describemacro then
        rl.describemacro(macro, desc)
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

local function get_preview_command()
    if not cached_preview_command then
        local def_style = os.getenv("BAT_STYLE") or "full"
        local def_color = get_color_mode()
        local def_bat_opts = "--style=\""..def_style.."\" "..
                             "--color="..def_color.." "..
                             "--decorations="..def_color.." "..
                             "--pager=never "..
                             "--highlight-line {2}"

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
    end
    return cached_preview_command
end

local function edit_file(rl_buffer, file, line)
    -- Prepare the command to open the editor.
    -- Uses EDITOR environment variable, defaults to notepad.
    local editor = os.getenv("EDITOR") or path.join(os.getenv("windir"), "System32\\notepad.exe")
    local haystack = editor:lower()
    local quotable
    if os.isfile(haystack) then
        quotable = true
        haystack = path.getname(haystack)
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

    local final_cmd = quotable and maybe_quote(editor) or editor
    local function append_cmd(fmt, ...)
        final_cmd = final_cmd..' '..string.format(fmt, ...)
    end

    -- 1. Modern IDEs & Cross-platform (VS Code, Zed, Sublime).
    if test("code") or
            test("zed") then
        append_cmd('--goto "%s:%s"', file, line)

    elseif test("subl") or
            test("emacs") or
            test("hx") or
            test("micro") then
        append_cmd('"%s:%s"', file, line)

    -- 2. Notepad++.
    elseif test("notepad++") or
            test("npp") then
        append_cmd('-n%s "%s"', line, file)

    -- 3. UltraEdit (uedit64 / uedit32).
    elseif test("uedit") then
        -- UltraEdit uses file.txt/line syntax.
        append_cmd('"%s/%s"', file, line)

    -- 4. EditPlus.
    elseif test("editplus") then
        append_cmd('-cursor %s:1 "%s"', line, file)

    -- 5. PSPad.
    elseif test("pspad") then
        append_cmd('/%s "%s"', line, file)

    -- 6. JetBrains (IntelliJ, WebStorm, etc).
    elseif test("idea") or
            test("storm") or
            test("rider") then
        append_cmd('--line %s "%s"', line, file)

    -- 7. CLI Editors (Vim, Nano, Edit).
    elseif test("vim") or
            test("nano") or
            test("edit") then
        append_cmd('+"%s" "%s"', line, file)

    else
        append_cmd('"%s"', file)
    end

    -- Avoid garbling the prompt and input line display in case the editor is a
    -- terminal-based program.
    rl_buffer:beginoutput()

    -- If the command line to execute begins with a quote and contains
    -- more than one pair of quotes, then special quote handling is
    -- necessary.
    if final_cmd:find('^%s*"') then
        os.execute('cmd /s /c "'..final_cmd..'"')
    else
        os.execute(final_cmd)
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

add_desc("luafunc:fzf_ripgrep", "Show a FZF filtered view with files matching search term")

-- luacheck: globals fzf_ripgrep
-- Define the search and pick function.
function fzf_ripgrep(rl_buffer, line_state) -- luacheck: no unused
    -- Get the current text in the command line as the search query.
    local query = rl_buffer:getbuffer()

    -- {q} is the placeholder for the fzf input string.

    -- If the line is empty, let ripgrep prompt for input inside fzf.
    -- Otherwise, use the current line as the initial ripgrep query.
    local _rg_command = [[rg --column --line-number --no-heading --color=]]..get_color_mode()..[[ --smart-case {q}]]
    local reload_command = [[echo {q} | findstr /r /c:"..*" >nul && ]].._rg_command -- Don't search if empty query string.
    local preview_command = get_preview_command()
    local args = {
        "--height 75%",
        "--reverse",
        -- Preserve and display ANSI color codes.
        "--ansi",
        -- Delimiter for fields in lines.
        [[--delimiter :]],
        -- Borders.
        [[--header "CTRL-/ (toggle preview)  CTRL-R (ripgrep mode)  CTRL-F (fzf mode)"]],
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
        [[--bind "ctrl-/:change-preview-window(right:40%|70%|hidden)"]],
        [[--bind "shift-down:preview-down+preview-down,shift-up:preview-up+preview-up,preview-scroll-up:preview-up+preview-up,preview-scroll-down:preview-down+preview-down"]],
        [[--preview-window "right:hidden,border-left,+{2}+4/2,~4" ]],
        [[--preview "]]..preview_command..[["]],
    }
    local fzf_opts = table.concat(args, " ")

    -- Delete any fzf mode query temporary file, so switching to fzf mode starts
    -- out with an empty query string.
    os.remove(path.join(os.getenv("TEMP"), "fzf_rg_f.tmp"))

    -- Open a pipe to capture the fzf output.
    local old_opts = os.getenv("FZF_DEFAULT_OPTS")
    os.setenv("FZF_DEFAULT_OPTS", old_opts.." "..fzf_opts)
    local handle = io.popen("fzf")
    os.setenv("FZF_DEFAULT_OPTS", old_opts)
    if not handle then
        rl_buffer:ding()
        return
    end

    local result = handle:read("*a")
    handle:close()

    -- Redraw the prompt and input line.
    rl_buffer:refreshline()

    -- If the user cancelled fzf, result will be empty.
    if not result or result == "" then
        return
    end

    -- Get the file and line from the selected item.
    local file, line = extract_file_and_line(result)
    if not file or not line then
        rl_buffer:ding()
        return
    end

    -- Discard what the user might have started with.
    rl.invokecommand("clink-reset-line")

    -- Open the file in an editor.
    edit_file(rl_buffer, file, line)
end

if rl.getbinding then
    if not rl.getbinding([["\C-Xf"]]) then
        rl.setbinding([["\C-Xf"]], [["luafunc:fzf_ripgrep"]])
    end
    if not rl.getbinding([["\C-X\C-f"]]) then
        rl.setbinding([["\C-X\C-f"]], [["luafunc:fzf_ripgrep"]])
    end
end

clink.onbeginedit(function()
    -- Clear the cached preview command when starting a new input line, to
    -- search the system PATH again and construct an updated preview command.
    cached_preview_command = nil
end)
