--------------------------------------------------------------------------------
-- This script can automatically run "git pull" in certain directories when
-- Clink starts, if it's been more than a certain number of days since the last
-- time this script ran "git pull" in the directory.
--
-- Errors encountered during the "git pull" are written to the Clink log file.
--
-- To reset the interval and trigger "git pull", delete the ".autopull_state"
-- file located in the Clink profile directory.

if not io.truncate then
    log.info("autopull.lua requires a newer version of Clink; please upgrade.")
    return
end

settings.add("autopull.enable", true,
    "Auto 'git pull' in certain directories",
    "When enabled, periodically performs automatic 'git pull' in directories\n"..
    "listed in the 'autopull.directories' setting, no more frequently than the\n"..
    "'autopull.interval' setting.")

settings.add("autopull.directories", "",
    "Directories for automatic 'git pull'",
    "This is a semicolon delimited list of directories in which to perform\n"..
    "automatic 'git pull' when starting Clink.")

settings.add("autopull.interval", 3,
    "Days between automatic 'git pull'",
    "Automatic 'git pull' in directories will wait this many days before doing\n"..
    "another automatic 'git pull' in the directories.")

local function log_info(message)
    message = "Autopull: " .. message
    log.info(message, 2)
end

--------------------------------------------------------------------------------
-- Internal functions.

local messages = {}

local function log_debug(message)
    if tonumber(os.getenv("AUTOPULL_DEBUG") or "0") > 0 then
        log.info(message, 2--[[level]])
    end
end

local function get_state_filename()
    return path.join(os.getenv("=clink.profile"), ".autopull_state")
end

local function get_dirs()
    local seen = {}
    local dirs = {}
    for _,dir in ipairs(string.explode(settings.get("autopull.directories", ";"))) do
        local key = dir:lower()
        if not seen[key] then
            table.insert(dirs, dir)
            seen[key] = true
        end
    end
    return dirs
end

local function do_autopull(dirs)
    local red = "\x1b[1;31m"
    local yellow = "\x1b[1;33m"
    local norm = "\x1b[m"

    -- Iterate through the directories.
    for _,dir in ipairs(dirs) do
        -- Change to the directory.
        log_debug("AUTOPULL: "..dir)
        if os.chdir(dir) then
            -- Run git pull.
            local command = "2>&1 git pull --no-progress"
            log_debug("AUTOPULL: "..command)
            local file, pclose = io.popenyield(command)
            if file then
                -- Read the output.
                local output = file:read("*a") or ""

                -- Get the exit code, if available.
                local ok = true
                local code
                if type(pclose) == "function" then
                    ok, _, code = pclose()
                else
                    file:close()
                end
                code = code or 0

                -- If something unexpected happened, log it and queue a message.
                if not ok or code ~= 0 or not output:find("Already up to date") then
                    local message
                    if not ok then
                        message = "failure"
                    elseif code ~= 0 then
                        message = "exit code "..tostring(code)
                    else
                        message = "unexpected output"
                    end

                    -- Queue a message.
                    local color = (ok and code == 0) and yellow or red
                    table.insert(messages, color.."Autopull: "..message.." from 'git pull' in "..dir..norm)

                    -- Log what happened.
                    message = message.." in "..dir.." from command: "..command
                    if #output > 0 then
                        message = message.."\n"..output
                    end
                    log_info(message)
                end
            end
        end
    end
end

local function onbeginedit()
    -- Display any pending messages.
    if #messages > 0 then
        for _,m in ipairs(messages) do
            clink.print(m)
        end
        if log.getfile then
            clink.print("\x1b[1mSee Clink log file for details ("..log.getfile()..").\x1b[m")
        else
            print("See Clink log file for details.")
        end
        messages = {}
    end

    -- Short circuit if there's nothing to do.
    if not settings.get("autopull.enable") then
        log_debug("AUTOPULL: disabled")
        return
    end
    local dirs = get_dirs()
    if #dirs == 0 then
        log_debug("AUTOPULL: no dirs")
        return
    end

    -- Open the state file; using io.sopen() begins an atomicity guard.
    local name = get_state_filename()
    local f = io.sopen(name, "a+", "rw"--[[deny]])
    if not f then
        log_debug("AUTOPULL: unable to open "..name)
        return
    end

    -- Rewind to start of file for reading.
    f:seek("set")

    -- Get the interval.
    local now = os.time()
    local timestamp = tonumber(f:read()) or 0
    local interval = settings.get("autopull.interval")
    if not interval or interval < 0 then
        interval = 1
    end

    -- Check whether overdue.
    local overdue = now - (timestamp + 60*60*24*interval)
    log_debug("AUTOPULL: delta "..tostring(overdue))
    if overdue > 0 then
        -- Reset the file to be empty.
        f:seek("set")
        io.truncate(f)

        -- Update the timestamp in the state file.
        f:write(tostring(now))

        -- Start a coroutine to run the git pull operations in the background.
        log_debug("AUTOPULL: start coroutine")
        local c = coroutine.create(function ()
            do_autopull(dirs)
        end)
        clink.runcoroutineuntilcomplete(c)
    end

    -- Close the state file; this ends the atomicity guard.
    f:close()
end

clink.onbeginedit(onbeginedit)
