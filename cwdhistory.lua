--------------------------------------------------------------------------------
-- CWD History
--
-- Maintains a list of recent current working directories.
--
-- The "cwdhistory.limit" setting specifies how many recently used current
-- working directories will be remembered.  The default limit is 100.
--
-- Shift-PgUp is the default key binding to show a popup list of recent
-- directories, unless it has already been bound to something else.
--
-- To bind a different key, add a key binding for "luafunc:cwdhistory_popup" to
-- your .inputrc file.
-- See https://chrisant996.github.io/clink/clink.html#customizing-key-bindings
-- for more information on key bindings.

--------------------------------------------------------------------------------
if not io.sopen then
    print("cwdhistory.lua requires a newer version of Clink; please upgrade.")
    return
end

--------------------------------------------------------------------------------
settings.add("cwdhistory.limit", 100, "Limit the cwd history", "At most this many recently used current working directories will be remembered.") -- luacheck: no max line length

--------------------------------------------------------------------------------
local cwd_history_list = {}
local deletion_list

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
        return filename
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
local function merge_nodups(file)
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
    local cwd_entry = { dir=os.getcwd(), time=os.time(), keep=true }
    add_and_update_index(reversed, cwd_entry, index, true--[[force]])
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
local function update_history()
    local f
    local history_filename = get_history_filename()
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
    cwd_history_list, loaded_list = merge_nodups(f)

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
function cwdhistory_popup(rl_buffer) -- luacheck: no global
    local items = {}
    for _, entry in ipairs(cwd_history_list) do
        local time_str
        if entry.time then
            time_str = os.date("%c", tonumber(entry.time))
        end
        table.insert(items, { value=entry.dir.."    ", description=time_str.."\t" })
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

    local value, shifted, index = clink.popuplist("Recently Used Directories", items, #cwd_history_list, del_callback) -- luacheck: no unused, no max line length
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
clink.onbeginedit(function ()
    update_history()
end)

--------------------------------------------------------------------------------
if rl.setbinding then
    if not rl.getbinding([["\e[5;2~"]]) then
        rl.setbinding([["\e[5;2~"]], [["luafunc:cwdhistory_popup"]])
    end
    if rl.describemacro then
        rl.describemacro([["luafunc:cwdhistory_popup"]], "Show popup list of recent directories")
    end
end
