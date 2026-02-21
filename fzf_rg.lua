--------------------------------------------------------------------------------
-- Provides a command for showing a list of files matching a search pattern and opening the files your editor
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
    
    -- If the user cancelled fzf, result will be empty
    if result ~= "" then
        -- fzf output format: file:line:column:text
        local file, line = result:match("([^:]+):([^:]+):")
        
        if file and line then
            -- Prepare the command to open the editor
            -- Uses EDITOR environment variable, defaults to 'vim'
            local editor = os.getenv("EDITOR") or "C:\\Program Files\\Sublime Text\\subl.exe"
            local final_cmd = string.format('"%s" "%s:%s"', editor, file, line)

            -- 1. Modern IDEs & Cross-platform (VS Code, Zed, Sublime)
            if editor:find("code") or editor:find("zed") then
                final_cmd = string.format('"%s" --goto "%s:%s"', editor, file, line)

            elseif editor:find("subl") or editor:find("emacs") or editor:find("hx") or editor:find("micro") then
                final_cmd = string.format('"%s" "%s:%s"', editor, file, line)

            -- 2. Notepad++ (The Windows favorite)
            elseif editor:find("notepad++") or editor:find("npp") then
                final_cmd = string.format('"%s" -n%s "%s"', editor, line, file)

            -- 3. UltraEdit (uedit64 / uedit32)
            elseif editor:find("uedit") then
                -- UltraEdit uses file.txt/line syntax
                final_cmd = string.format('"%s" "%s/%s"', editor, file, line)

            -- 4. EditPlus
            elseif editor:find("editplus") then
                final_cmd = string.format('"%s" -cursor %s:1 "%s"', editor, line, file)

            -- 5. PSPad
            elseif editor:find("pspad") then
                final_cmd = string.format('"%s" /%s "%s"', editor, line, file)

            -- 6. JetBrains (IntelliJ, WebStorm, etc.)
            elseif editor:find("idea") or editor:find("storm") or editor:find("rider") then
                final_cmd = string.format('"%s" --line %s "%s"', editor, line, file)

            -- 7. Standard Windows Notepad (Fallback)
            elseif editor == "notepad" or editor == "notepad.exe" then
                -- Notepad doesn't support line flags via CLI.
                -- We open it, then Clink can't automate the jump easily, 
                -- so we just open the file.
                final_cmd = string.format('notepad "%s"', file)
            
            -- 8. CLI Editors (Vim, Nano)
            else
                final_cmd = string.format('"%s" +"%s" "%s"', editor, line, file)
            end
            final_cmd = final_cmd

            -- if executable has spaces just running final_cmd doesn't seem to work
            os.execute('cmd /s /c "' .. final_cmd .. '"')
            
            rl_buffer:beginundogroup()
            rl_buffer:setcursor(1)
            rl_buffer:remove(1, rl_buffer:getlength() + 1)  -- remove what the user might have started with
            rl_buffer:endundogroup()
        end
    end
end

if rl.getbinding then
    if not rl.getbinding([["\C-Xf"]]) then
        rl.setbinding([["\C-Xf"]], [["luafunc:ripgrep_popup"]])
    end
end
