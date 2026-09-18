--------------------------------------------------------------------------------
-- Lua profiler for Clink.
--
-- There are two profiling modes:
--
--  1.  Manual start/stop of profiling session.
--  2.  Automatic start/stop of one profiling session per input prompt (from
--      the onbeginedit event through the onendedit event).
--
-- Profile reports are written to profiler.log in the current Clink profile
-- directory.  Refer to the modules\profiler.lua script for details about what
-- is in a profile report (it's the "lua-profiler" written by Charles Mallah)..
--
-- There are 6 bindable commands; for details, refer to the script source code
-- further below.
--
-- There is 1 default key binding:
--
--      Ctrl-X Ctrl-P           Toggles Lua profiling

--------------------------------------------------------------------------------
if rl.describemacro then
    -- luacheck: no max line length
    rl.describemacro("luafunc:clink_enable_profile_editline", "Enable Lua profiling (from onbeginedit through onendedit)")
    rl.describemacro("luafunc:clink_disable_profile_editline", "Disable Lua profiling (from onbeginedit through onendedit)")
    rl.describemacro("luafunc:clink_toggle_profile_editline", "Toggle Lua profiling (from onbeginedit through onendedit)")
    rl.describemacro("luafunc:clink_start_profiling", "Start Lua profiling")
    rl.describemacro("luafunc:clink_stop_profiling", "Stop Lua profiling")
    rl.describemacro("luafunc:clink_toggle_profiling", "Toggle Lua profiling")
end

--------------------------------------------------------------------------------
if rl.setbinding then
    rl.setbinding([["\C-x\C-p"]], [["luafunc:clink_toggle_profiling"]])
end

--------------------------------------------------------------------------------
local profiler = require('profiler')
local active
local mode

--------------------------------------------------------------------------------
local function start()
    active = mode
    log.info("START PROFILER")
    profiler.start()
end

--------------------------------------------------------------------------------
local function stop(report)
    if report and active then
        local filename = path.join(os.getenv("=clink.profile"), "profiler.log")
        profiler.report(filename)
        log.info("STOP PROFILER; report written to "..filename)
    else
        profiler.stop()
        log.info("STOP PROFILER")
    end
    active = nil
end

--------------------------------------------------------------------------------
local function onbeginedit()
    if mode == "editline" then
        start()
    end
end

--------------------------------------------------------------------------------
local hooked_end_edit
local function onendedit()
    if not hooked_end_edit then
        local function real_onendedit()
            if active and (not mode or mode == "editline") then
                stop(true)
            end
        end

        -- This defers hooking, to try to be the last onendedit handler.
        hooked_end_edit = true
        clink.onendedit(real_onendedit)
    end
end

--------------------------------------------------------------------------------
function clink_enable_profile_editline() -- luacheck: no global
    mode = "editline"
end

--------------------------------------------------------------------------------
function clink_disable_profile_editline() -- luacheck: no global
    mode = nil
end

--------------------------------------------------------------------------------
function clink_toggle_profile_editline() -- luacheck: no global
    if mode == "editline" then
        mode = nil
    else
        mode = "editline"
    end
end

--------------------------------------------------------------------------------
-- luacheck: globals clink_start_profiling
function clink_start_profiling()
    stop(true)
    mode = "continuous"
    start()
end

--------------------------------------------------------------------------------
-- luacheck: globals clink_stop_profiling
function clink_stop_profiling()
    mode = nil
    if active then
        stop(true)
    end
end

--------------------------------------------------------------------------------
function clink_toggle_profiling() -- luacheck: no global
    if mode == "continuous" then
        clink_stop_profiling()
    else
        clink_start_profiling()
    end
end

--------------------------------------------------------------------------------
if profiler then
    profiler.configuration({
        fW = 40,    -- file column width
        fnW = 32,   -- function column width
    })
end

--------------------------------------------------------------------------------
clink.onbeginedit(onbeginedit)
clink.onendedit(onendedit)
