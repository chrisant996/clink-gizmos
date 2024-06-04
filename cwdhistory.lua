--------------------------------------------------------------------------------
-- CWD History
--
-- Maintains a list of recent current working directories.  Also provides some
-- directory completion commands.
--
-- The "cwdhistory.limit" setting specifies how many recently used current
-- working directories will be remembered.  The default limit is 100.
--
-- The CLINK_HISTORY_LABEL environment variable affects directory history the
-- same way it affects command history.
--
-- History:
--
--      Shift-PgUp is the default key binding to show a popup list of recent
--      directories, unless it has already been bound to something else.
--
-- Completion:
--
--      Ctrl-\ is the default key binding to cycle through directory matches for
--      the word at the cursor.  Ctrl-Shift-\ cycles in reverse order.
--
--      Alt-Ctrl-\ is the default key binding to perform interactive completion
--      for the word at the cursor, showing possible directory completions.
--
-- Customize key bindings:
--
--      To bind different keys, add a key bindings for the appropriate commands
--      to your .inputrc file.  For information on customizing key bindings see
--      https://chrisant996.github.io/clink/clink.html#customizing-key-bindings
--
--      "luafunc:cwdhistory_popup"
--              Show popup list of recent current working directories.  Press
--              Enter to `cd` to the selected directory, or press Shift-Enter
--              or Ctrl-Enter to `pushd` to the selected directory.
--
--      "luafunc:cwdhistory_menucomplete"
--      "luafunc:cwdhistory_menucomplete_backward"
--              Cycle through directory matches for the word at the cursor.
--              These behave like the "old-menu-complete" and
--              "old-menu-complete-backward" commands.
--
--      "luafunc:cwdhistory_complete"
--              Perform completion for directory matches for the word at the
--              cursor.  Behaves like the "complete" command.
--
--      "luafunc:cwdhistory_selectcomplete"
--              Perform completion by selecting from an interactive list of
--              directory matches.  Behaves like the "clink-select-complete"
--              command.

--------------------------------------------------------------------------------
if not io.sopen then
    print("cwdhistory.lua requires a newer version of Clink; please upgrade.")
    return
end

--------------------------------------------------------------------------------
settings.add("cwdhistory.limit", 100, "Limit the cwd history",
             "At most this many recently used current working directories will be remembered.")
settings.add("cwdhistory.restore", false, "Restore the most recent cwd on startup",
             "When this is 'true', when Clink is injected it automatically changes to the\n"..
             "most recent cwd in the history.")

--------------------------------------------------------------------------------
local cwd_history_list = {}
local deletion_list
local using_history_file

--------------------------------------------------------------------------------
local function reset_cache()
    cwd_history_list = {}
    deletion_list = nil
    using_history_file = nil
end

--------------------------------------------------------------------------------
local function add_and_update_index(list, entry, index, force)
    local key = clink.lower(entry.dir)
    local present = index[key]
    if force or present then
        table.insert(list, entry)
    end
    if present then
        index[key] = nil
    end
end

--------------------------------------------------------------------------------
local function need_quote(word)
    return word and word:find("[ &()[%]{}^=;!%'+,`~]") and true
end

--------------------------------------------------------------------------------
local function maybe_quote(word)
    if need_quote(word) then
        word = '"' .. word .. '"'
    end
    return word
end

--------------------------------------------------------------------------------
local function get_history_filename()
    local profile_dir = os.getenv("=clink.profile")
    if profile_dir and profile_dir ~= "" then
        local filename = path.join(profile_dir, "cwd_history")
        local label = os.getenv("CLINK_HISTORY_LABEL") or ""
        label = label:gsub("%p", "")
        if #label > 0 then
            label = "-" .. label
        end
        return filename .. label
    end
end

--------------------------------------------------------------------------------
local function read_history(file)
    local list = {}
    if file then
        for line in file:lines() do
            local dir, time = line:match("^([^|]*)%|(.*)$")
            if dir and #dir > 0 then
                table.insert(list, { dir=dir, time=time })
            elseif #line > 0 then
                table.insert(list, { dir=line })
            end
        end
    end
    return list
end

--------------------------------------------------------------------------------
local function merge_nodups(file, nocwd)
    local persisted_list = read_history(file)
    local limit = settings.get("cwdhistory.limit")

    -- Build index of dirs, for removing duplicates.
    local index = {}
    for _, entry in ipairs(persisted_list) do
        index[clink.lower(entry.dir)] = true
    end

    -- Build list of dirs added in session history.
    local new_dirs = {}
    for _, entry in ipairs(cwd_history_list) do
        if entry.keep and not index[clink.lower(entry.dir)] then
            table.insert(new_dirs, entry)
        end
    end

    -- Build reversed list with duplicates removed.
    local reversed = {}
    if not nocwd then
        local cwd_entry = { dir=os.getcwd(), time=os.time(), keep=true }
        add_and_update_index(reversed, cwd_entry, index, true--[[force]])
    end
    for i = #new_dirs, 1, -1 do
        table.insert(reversed, new_dirs[i])
    end
    for i = #persisted_list, 1, -1 do
        add_and_update_index(reversed, persisted_list[i], index)
    end

    -- Apply deletions.
    if deletion_list then
        for i = #reversed, 1, -1 do
            if deletion_list[clink.lower(reversed[i].dir)] then
                table.remove(reversed, i)
            end
        end
        deletion_list = nil
    end

    -- Prune to the limit, if any.
    if limit and limit > 0 then
        for i = #reversed, limit + 1, -1 do
            table.remove(reversed, i)
        end
    end

    -- Reverse the list again.
    local output = {}
    for i = #reversed, 1, -1 do
        table.insert(output, reversed[i])
    end

    return output, persisted_list
end

--------------------------------------------------------------------------------
local function update_history_internal(history_filename, nocwd)
    local f
    local binmode = io.truncate and "" or "b"

    -- Create the history file if it doesn't exist yet.
    if not os.isfile(history_filename) then
        f = io.sopen(history_filename, "wx"..binmode, "rw")
        if not f then
            return
        end
        f:close()
    end

    -- Retry opening the history file until there is no sharing violation.
    -- Try for up to 2 seconds, and then give up.
    local start_clock = os.clock()
    repeat
        f = io.sopen(history_filename, "r+"..binmode, "rw")
    until f or os.clock() - start_clock > 2

    if not f then
        log.info("cwdhistory unable to access '"..history_filename.."'.")
        return
    end

    -- Get the file size.  Necessary until Clink has a way to truncate a file.
    local file_size = f:seek()

    -- Merge the in-memory list with the persisted list.
    local loaded_list
    cwd_history_list, loaded_list = merge_nodups(f, nocwd)

    -- Be nice to SSD lifetime, and to performance!  Do not rewrite the file
    -- unless it has changed.  But do not rewrite the file if the only change is
    -- to the timestamp of the last entry.
    local rewrite = #cwd_history_list ~= #loaded_list
    if not rewrite then
        for i = 1, #loaded_list, 1 do
            if cwd_history_list[i].dir ~= loaded_list[i].dir then
                rewrite = true
                break
            elseif cwd_history_list[i].time ~= loaded_list[i].time then
                if i < #loaded_list then
                    rewrite = true
                    break
                end
            end
        end
    end

    if rewrite and f:seek("set") ~= nil then
        for _, entry in ipairs(cwd_history_list) do
            if entry.time then
                f:write(entry.dir.."|"..tostring(entry.time).."\n")
            else
                f:write(entry.dir.."\n")
            end
        end

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

    f:close()
end

--------------------------------------------------------------------------------
local function update_history(nocwd)
    local file = get_history_filename()

    if using_history_file then
        update_history_internal(using_history_file, nocwd)
    end

    if using_history_file ~= file then
        reset_cache()
        using_history_file = file
        update_history_internal(using_history_file, nocwd)
    end
end



--------------------------------------------------------------------------------
function cwdhistory_popup(rl_buffer) -- luacheck: no global
    local items = {}
    local time_format = "%Y-%m-%d  %H:%M:%S"
    for _, entry in ipairs(cwd_history_list) do
        local time_str
        if entry.time then
            time_str = os.date(time_format, tonumber(entry.time))
        end
        table.insert(items, { value=entry.dir.."  ", description=time_str.."\t" })
    end

    -- If the most recent is the same as the current directory, then remove it;
    -- there's little point in switching to the same directory.
    if #items > 0 then
        local top = items[#items].value:gsub(" +$", "")
        if string.equalsi(os.getcwd(), top) then
            table.remove(items, #items)
        end
    end

    local update
    local function del_callback(index)
        if cwd_history_list[index] then
            deletion_list = deletion_list or {}
            deletion_list[clink.lower(cwd_history_list[index].dir)] = true
            table.remove(cwd_history_list, index)
            update = true
            return true
        end
    end

    items.reverse = true

    local value, shifted, index = clink.popuplist("Recently Used Directories", items, #items, del_callback) -- luacheck: no unused, no max line length
    if update then
        update_history()
    end
    if not value then
        rl_buffer:ding()
        return
    end

    value = value:gsub(" *$", "").."\\"

    rl_buffer:beginundogroup()
    rl_buffer:remove(1, -1)
    if shifted then
        rl_buffer:insert("pushd ")
    end
    rl_buffer:insert(maybe_quote(value))
    rl_buffer:endundogroup()

    rl.invokecommand("accept-line")
end



--------------------------------------------------------------------------------
local use_dir_generator
local dir_generator = clink.generator(-999999)

--------------------------------------------------------------------------------
local function get_cursor_word(line_state)
    local info = line_state:getwordinfo(line_state:getwordcount())
    if not info then
        return ""
    end

    local start = info.offset
    local cursor = line_state:getcursor()
    if cursor < start then
        return ""
    end

    return line_state:getline():sub(start, cursor - 1)
end

--------------------------------------------------------------------------------
function dir_generator:generate(line_state, builder) -- luacheck: no unused
    if not use_dir_generator then
        return
    end

    local word = get_cursor_word(line_state)
    local drive = path.getdrive(word)

    if line_state:getwordcount() <= 1 then
        local restrict_drive
        if not drive then
            local dir = path.getdirectory(word)
            if dir and dir:sub(1, 1) == "\\" then
                local fullword = os.getfullpathname(word)
                if fullword and fullword ~= "" then
                    word = fullword
                    drive = path.getdrive(fullword)
                    restrict_drive = true
                end
            end
        end

        if word == "" or drive then
            local color = settings.get("color.doskey")
            if not color or color == "" then
                color = rl.getmatchcolor("", "dir") or ""
            else
                color = "\x1b[0;"..color.."m"
            end
            for i = #cwd_history_list, 1, -1 do
                local dir = path.join(cwd_history_list[i].dir, "")
                if restrict_drive then
                    if path.getdrive(dir) ~= drive then
                        dir = nil
                    else
                        dir = dir:sub(#drive + 1)
                    end
                end
                if dir then
                    builder:addmatch({ match=dir, display=color..dir, type="word", suppressappend=true })
                end
            end
            builder:setnosort()
        end
    end

    for _, m in ipairs(clink.dirmatches(line_state:getendword())) do
        builder:addmatch(m)
    end

    return true
end

--------------------------------------------------------------------------------
-- luacheck: globals cwdhistory_menucomplete
function cwdhistory_menucomplete(rl_buffer) -- luacheck: no unused
    use_dir_generator = true
    rl.invokecommand("old-menu-complete")
    use_dir_generator = nil
end

--------------------------------------------------------------------------------
-- luacheck: globals cwdhistory_menucomplete_backward
function cwdhistory_menucomplete_backward(rl_buffer) -- luacheck: no unused
    use_dir_generator = true
    rl.invokecommand("old-menu-complete-backward")
    use_dir_generator = nil
end

--------------------------------------------------------------------------------
-- luacheck: globals cwdhistory_complete
function cwdhistory_complete(rl_buffer) -- luacheck: no unused
    use_dir_generator = true
    rl.invokecommand("complete")
    use_dir_generator = nil
end

--------------------------------------------------------------------------------
-- luacheck: globals cwdhistory_selectcomplete
function cwdhistory_selectcomplete(rl_buffer) -- luacheck: no unused
    use_dir_generator = true
    rl.invokecommand("clink-select-complete")
    use_dir_generator = nil
end



--------------------------------------------------------------------------------
function cwdhistory_remove_dir(dir) -- luacheck: no global
    deletion_list = deletion_list or {}
    deletion_list[clink.lower(dir)] = true
end



--------------------------------------------------------------------------------
local function do_restore()
    if not settings.get("cwdhistory.restore") then
        return
    end
    local norestore = os.getenv("CWDHISTORY_NORESTORE")
    if norestore and tonumber(norestore) ~= 0 then
        return
    end
    return true
end

--------------------------------------------------------------------------------
local function is_in_history_labels_dir(dir, history_labels_dir)
    dir = clink.lower(path.normalise(path.join(dir, "")))
    history_labels_dir = clink.lower(path.normalise(path.join(history_labels_dir, "")))
    if dir:find(history_labels_dir, 1, true) == 1 then
        return true
    end
end

--------------------------------------------------------------------------------
local restore_dir
clink.oninject(function ()
    os.setenv("=cwdhistory_injected", "1")
    if do_restore() then
        local nocwd = true
        update_history(nocwd)
        if cwd_history_list then
            local last = #cwd_history_list
            local dir = cwd_history_list[last].dir
            local history_labels_dir = os.getenv("=history_labels_dir")
            if not history_labels_dir or is_in_history_labels_dir(dir, history_labels_dir) then
                restore_dir = dir
            end
        end
    end
end)

--------------------------------------------------------------------------------
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

--------------------------------------------------------------------------------
clink.onprovideline(function ()
    if restore_dir then
        local dir = restore_dir
        local drive = need_cd_drive(dir)
        restore_dir = nil
        -- Ideally this could use CD /D, but that only works if command
        -- extensions are enabled.
        if drive then
            return "  " .. drive .. " & cd " .. dir
        else
            return "  cd " .. dir
        end
    end
end)

--------------------------------------------------------------------------------
local initialized
clink.onbeginedit(function ()
    if initialized then
        return
    end
    -- This tries to ensure update_history() runs as the last onbeginedit event
    -- handler, in case any set CLINK_HISTORY_LABEL (like history_labels.lua
    -- does).  Adding an event handler from inside an existing event handler
    -- adds the new handler at the end of the list, so the new handler gets run
    -- last (it isn't skipped).
    initialized = true
    clink.onbeginedit(function ()
        update_history(restore_dir)
    end)
end)

--------------------------------------------------------------------------------
if rl.setbinding then
    if not rl.getbinding([["\e[5;2~"]]) then
        rl.setbinding([["\e[5;2~"]], [["luafunc:cwdhistory_popup"]])
    end
    if not rl.getbinding([["\e\C-\"]]) then
        rl.setbinding([["\e\C-\"]], [["luafunc:cwdhistory_selectcomplete"]])
    end
    if not rl.getbinding([["\C-\"]]) then
        rl.setbinding([["\C-\"]], [["luafunc:cwdhistory_menucomplete"]])
    end
    if not rl.getbinding([["\e[27;6;220~"]]) then
        rl.setbinding([["\e[27;6;220~"]], [["luafunc:cwdhistory_menucomplete_backward"]])
    end
    if rl.describemacro then
        rl.describemacro([["luafunc:cwdhistory_popup"]], "Show popup list of recent directories")
        rl.describemacro([["luafunc:cwdhistory_menucomplete"]], "Replace word with next directory match")
        rl.describemacro([["luafunc:cwdhistory_menucomplete_backward"]], "Replace word with previous directory match")
        rl.describemacro([["luafunc:cwdhistory_complete"]], "Complete word as a directory")
        rl.describemacro([["luafunc:cwdhistory_selectcomplete"]], "Complete word as a directory from an interactive list") -- luacheck: no max line length
    end
end
