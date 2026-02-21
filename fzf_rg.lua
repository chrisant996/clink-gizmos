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

add_desc("luafunc:fzf_ripgrep", "Show a FZF filtered view with files matching search term")

-- luacheck: globals fzf_ripgrep
-- Define the search and pick function.
function fzf_ripgrep(rl_buffer, line_state) -- luacheck: no unused
    -- Get the current text in the command line as the search query.
    local query = rl_buffer:getbuffer()

    -- {q} is the placeholder for the fzf input string.

    -- If the line is empty, let ripgrep prompt for input inside fzf.
    -- Otherwise, use the current line as the initial ripgrep query.
    local args = {
        "--height 75%",
        "--reverse",
        -- Preserve and display ANSI color codes.
        "--ansi",
        -- %q adds safe quotes.
        string.format("--query %q", query),
        [[--disabled]],                         -- Disable fzf filtering (ripgrep will filter).
        -- Query.
        [[--bind "start:reload:rg --column --line-number --no-heading --color=always --smart-case {q}"]],
        [[--bind "change:reload:rg --column --line-number --no-heading --color=always --smart-case {q}"]],
    }
    local fzf_opts = table.concat(args, " ")

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
end
