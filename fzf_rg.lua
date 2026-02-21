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

# Default key bindings for ripgrep_popup.
"\C-Xf":    "luafunc:ripgrep_popup"  # CTRL-X,f Show a FZF filtered view with files matching search term

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

add_desc("luafunc:ripgrep_popup", "Show a FZF filtered view with files matching search term")

-- luacheck: globals ripgrep_popup
-- Define the search and pick function
function ripgrep_popup(rl_buffer, line_state) -- luacheck: no unused
    -- Get the current text in the command line as the search query
    local query = rl_buffer:getbuffer()

    -- --disabled: Tells fzf not to filter results itself
    -- --bind "change:reload...": Runs rg every time the input changes
    -- {q}: Is the placeholder for the fzf input string

    -- If the line is empty, we'll let ripgrep prompt for input inside fzf
    -- Otherwise, we use the current line as the initial ripgrep query
    local args = {
        "fzf",
        "--ansi",
        "--disabled",
        string.format("--query %q", query), -- %q adds safe quotes
        -- We use single quotes inside the bind to protect the rg command
        [[--bind "start:reload:rg --column --line-number --no-heading --color=always --smart-case {q}"]],
        [[--bind "change:reload:rg --column --line-number --no-heading --color=always --smart-case {q}"]],
        "--height 75% --reverse"
    }
    local fzf_cmd = table.concat(args, " ")

    -- Open a pipe to capture the fzf output
    local handle = io.popen(fzf_cmd)
    local result = handle:read("*a")
    handle:close()

    -- Redraw the prompt and input line
    rl_buffer:refreshline()

    -- If the user cancelled fzf, result will be empty
    if not result or result == "" then
        return
    end

    -- fzf output format: file:line:column:text
    local file, line = result:match("([^:]+):([^:]+):")
    if not file or not line then
        return
    end

    -- Prepare the command to open the editor
    -- Uses EDITOR environment variable, defaults to 'vim'
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

    -- 1. Modern IDEs & Cross-platform (VS Code, Zed, Sublime)
    if test("code") or
            test("zed") then
        append_cmd('--goto "%s:%s"', file, line)

    elseif test("subl") or
            test("emacs") or
            test("hx") or
            test("micro") then
        append_cmd('"%s:%s"', file, line)

    -- 2. Notepad++
    elseif test("notepad++") or
            test("npp") then
        append_cmd('-n%s "%s"', line, file)

    -- 3. UltraEdit (uedit64 / uedit32)
    elseif test("uedit") then
        -- UltraEdit uses file.txt/line syntax
        append_cmd('"%s/%s"', file, line)

    -- 4. EditPlus
    elseif test("editplus") then
        append_cmd('-cursor %s:1 "%s"', line, file)

    -- 5. PSPad
    elseif test("pspad") then
        append_cmd('/%s "%s"', line, file)

    -- 6. JetBrains (IntelliJ, WebStorm, etc.)
    elseif test("idea") or
            test("storm") or
            test("rider") then
        append_cmd('--line %s "%s"', line, file)

    -- 7. CLI Editors (Vim, Nano, Edit)
    elseif test("vim") or
            test("nano") or
            test("edit") then
        append_cmd('+"%s" "%s"', line, file)

    else
        append_cmd('"%s"', file)
    end

    -- If the command line to execute begins with a quote and contains
    -- more than one pair of quotes, then special quote handling is
    -- necessary.
    if final_cmd:find('^%s*"') then
        os.execute('cmd /s /c "'..final_cmd..'"')
    else
        os.execute(final_cmd)
    end

    -- Discard what the user might have started with
    rl.invokecommand("clink-reset-line")
end

if rl.getbinding then
    if not rl.getbinding([["\C-Xf"]]) then
        rl.setbinding([["\C-Xf"]], [["luafunc:ripgrep_popup"]])
    end
end
