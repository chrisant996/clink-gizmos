--------------------------------------------------------------------------------
-- Usage:
--
-- For use with zoxide (https://github.com/ajeetdsouza/zoxide).
--
-- This script provides a function `zoxide_dir_popup` for use as a "luafunc:"
-- key binding (see https://chrisant996.github.io/clink/clink.html#luakeybindings).
--
-- The command shows a popup to pick from a directory known to zoxide, and then
-- changes to that directory.
--
-- Sample key binding, in .inputrc format:
--[[

"\e[5;5~":    "luafunc:zoxide_dir_popup"    # Ctrl-PgUp

--]]

if not clink.popuplist then
    print("zoxide_dir_popup.lua requires a newer version of Clink; please upgrade.")
    return
end

if rl.describemacro then
    rl.describemacro("luafunc:zoxide_dir_popup", "Show a popup to pick from a directory known to zoxide, and then change to the directory") -- luacheck: no max line length
end

local function need_cd_drive(dir)
    local drive = path.getdrive(dir)
    if drive then
        local cwd = os.getcwd()
        if cwd then
            local cwd_drive = path.getdrive(cwd)
            if cwd_drive and cwd_drive:lower() == drive:lower() then
                return
            end
        end
    end
    return drive
end

function zoxide_dir_popup(rl_buffer) -- luacheck: no global
    local z = os.getalias("z")
    if z then
        z = z:match('^"([^"]+)"') or z:match('^([^ ]+)')
    end
    if not z then
        z = "zoxide.exe"
    end

    local r = io.popen('2>nul "' .. z .. '" query --list')
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

    local selected = clink.popuplist("Zoxide Directories", dirs)
    if not selected then
        return
    end

    local dir = selected
    if not dir or dir == "" then
        rl_buffer:ding()
        return
    end

    if shifted and (clink.version_encoded or 0) >= 10030024 then
        rl_buffer:insert(dir)
    else
        rl_buffer:remove(1, -1)
        rl_buffer:setcursor(1)
        local drive = need_cd_drive(dir)
        if drive then
            rl_buffer:insert("  " .. drive .. " & cd " .. dir)
        else
            rl_buffer:insert("  cd " .. dir)
        end
        rl.invokecommand("accept-line")
    end
end
