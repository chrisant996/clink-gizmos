--------------------------------------------------------------------------------
-- Usage:
--
-- For use with z.lua (https://github.com/skywind3000/z.lua).
--
-- This script provides a function `z_dir_popup` for use as a "luafunc:" key
-- binding (see https://chrisant996.github.io/clink/clink.html#luakeybindings).
--
-- The command shows a popup to pick from a directory known to z, and then
-- changes to that directory.
--
-- Sample key binding, in .inputrc format:
--[[

"\e[5;5~":    "luafunc:z_dir_popup"    # Ctrl-PgUp

--]]

if not clink.popuplist then
    print("z_dir_popup.lua requires a newer version of Clink; please upgrade.")
    return
end

if rl.describemacro then
    rl.describemacro("luafunc:z_dir_popup", "Show a popup to pick from a directory known to z, and then change to the directory") -- luacheck: no max line length
end

function z_dir_popup(rl_buffer) -- luacheck: no global
    local z = os.getalias("z")
    if z then
        z = z:match('^"([^"]+)"') or z:match('^([^ ]+)')
    end
    if not z then
        z = "z.cmd"
    end

    local r = io.popen('"' .. z .. '" -l')
    if not r then
        rl_buffer:ding()
        return
    end

    local list = {}
    for line in r:lines() do
        if line ~= "" then
            table.insert(list, line)
        end
    end
    r:close()

    local dirs = {}
    for i = #list, 1, -1 do
        table.insert(dirs, list[i])
    end

    local selected = clink.popuplist("Z Directories", dirs)
    if not selected then
        return
    end

    local dir, shifted = selected:match("^ *[0-9.]+ +(.+)$")
    if not dir or dir == "" then
        rl_buffer:ding()
        return
    end

    if shifted and (clink.version_encoded or 0) >= 10030024 then
        rl_buffer:insert(dir)
    else
        rl_buffer:remove(1, -1)
        rl_buffer:setcursor(1)
        rl_buffer:insert("  cd /d " .. dir)
        rl.invokecommand("accept-line")
    end
end
