--------------------------------------------------------------------------------
-- Provides a command for showing a list of files matching a search pattern and opening the files your editor
--
-- SETTINGS:
--
--  The available settings are as follows.
--  The settings can be controlled via 'clink set'.
--
--      ripgrep.show_preview      If enabled it will also show a preview of the file using bat.
--                                Expects bat command to be available in PATH.
--
--      ripgrep.editor_executable Configures the editor to use to view the file when enter is pressed.
--                                Will only be taken into account if EDITOR environment variable is not set,
--                                otherwise EDITOR env variable will be used.
-- 
--      ripgrep.command           Configures the command to run when enter is pressed.
--                                Will use the editor path (ripgrep.editor_executable) as the executable, and can be used
--                                to invoke the editor so it opens the file at the selected line, if the editor supports it.
--                                You can use the following variables: {editor}, {line}, {file}.
--
--                                Usually editors support one of the following formats:
--                                   - vscode: "{editor}" --goto "{file}:{line}"
--                                   - sublime, emacs, hx, micro: "{editor}" "{file}:{line}"
--                                   - notepad++: "{editor}" -n {line} "{file}"
--                                   - ultraedit: "{editor}" "file/line"
--                                   - EditPlus: "{editor}" -cursor {line}:1 "{file}"
--                                   - pspad: "{editor}" /{line} "{file}"
--                                   - JetBrains (idea, storm, ..): "{editor}" --line {line} "{file}"
--                                   - vim, nano: "{editor}" +{line} "{file}"
--                                   - notepad (doesn't support opening at a specific line): "{editor}" "{file}"
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
        [[--bind "change:reload:rg --column --line-number --no-heading --color=always --smart-case {q}"]]
    }
    -- only add the preview part if it's enabled
    local val = settings.get("ripgrep.show_preview")
    if settings.get("ripgrep.show_preview") then
        table.insert(args, [[--preview-window "right:40%,border-left" --bind "ctrl-/:change-preview-window(right:70%|hidden|)" --preview "for /f \"tokens=1,2 delims=:\" %a in ({1}) do @bat --style numbers --force-colorization --highlight-line %b -r %b::16 %a"]])
    end
    table.insert(args, "--height 75% --reverse")

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
            local editor = os.getenv("EDITOR") or settings.get("ripgrep.editor_executable")
            local template = settings.get("ripgrep.command")
            editor = editor:gsub("%%", "%%%%") -- escape any % character
            local final_cmd = template
                :gsub("{editor}", editor)
                :gsub("{file}", file)
                :gsub("{line}", line)

            -- if executable/editor has spaces just running final_cmd doesn't seem to work, need to use cmd /s /c on it
            os.execute('cmd /s /c "' .. final_cmd .. '"')
            
            rl_buffer:beginundogroup()
            rl_buffer:setcursor(1)
            rl_buffer:remove(1, rl_buffer:getlength() + 1)  -- remove what the user might have started with
            rl_buffer:endundogroup()
        end
    end
end


------------

settings.add("ripgrep.show_preview", true, "Shows a preview window in fzf with file contents",
    "If enabled it will also show a preview of the file using bat.\n"..
    "Expects bat command to be available in PATH.")

settings.add("ripgrep.editor_executable", "%windir%\\notepad.exe", "Configures the editor to use to view the file when enter is pressed.",
    "Will only be taken into account if EDITOR environment variable is not set,\n"..
    "otherwise EDITOR env variable will be used.")

settings.add("ripgrep.command", '"{editor}" "{file}"', "Configures the command to run when enter is pressed.",
    "Will use the editor path (ripgrep.editor_executable) as the executable, and can be used\n"..
    "to invoke the editor so it opens the file at the selected line, if the editor supports it.\n"..
"You can use the following variables: {editor}, {line}, {file}.\n"..
"\n"..
"Usually editors support one of the following formats:\n"..
'   - vscode: "{editor}" --goto "{file}:{line}"\n'..
'   - sublime, emacs, hx, micro: "{editor}" "{file}:{line}"\n'..
'   - notepad++: "{editor}" -n {line} "{file}"\n'..
'   - ultraedit: "{editor}" "file/line"\n'..
'   - EditPlus: "{editor}" -cursor {line}:1 "{file}"\n'..
'   - pspad: "{editor}" /{line} "{file}"\n'..
'   - JetBrains (idea, storm, ..): "{editor}" --line {line} "{file}"\n'..
'   - vim, nano: "{editor}" +{line} "{file}"\n'..
'   - notepad (doesn\'t support opening at a specific line): "{editor}" "{file}"\n'..
'\n'..
'If setting from the command line you may need to escape the " character, so for example\n'..
'for Sublime the command may be clink set ripgrep.command "\\"{editor}\\" \\"{file}:{line}\\""\n'
)

if rl.getbinding then
    if not rl.getbinding([["\C-Xf"]]) then
        rl.setbinding([["\C-Xf"]], [["luafunc:ripgrep_popup"]])
    end
end