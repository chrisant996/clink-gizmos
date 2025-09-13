--------------------------------------------------------------------------------
-- Adds Subversion support into Clink's "git" APIs.
--
-- This is disabled by default, to avoid performance cost for users who don't
-- need Subversion support.
--
-- To enable Subversion support, do either of these:
--  1. Run `clink set scmapi.svn true` to enable it for the Clink profile, and
--     then either start a new Clink session or press CTRL-X,CTRL-R to reload.
--  2. Run `set SCMAPI_SVN_ENABLE=1` to enable it for the current session, and
--     then press CTRL-X,CTRL-R to reload.

local scmapi = require("scmapi_module")
if not scmapi then
    return
end

settings.add("scmapi.svn", false, "Enable Subversion support in prompts",
             "Changing this takes effect for the next Clink session.\n"..
             "(Or set %SCMAPI_SVN_ENABLE% to any value.)")
settings.add("scmapi.svn_path", "", "Full path and filename to svn program",
             "Set this if svn is not found along the system PATH.\n"..
             "(Or set %SCMAPI_SVN_PATH% to the full path and filename.)")
settings.add("scmapi.svn_quiet", false, "Ignores untracked items")

if not settings.get("scmapi.svn") and not os.getenv("SCMAPI_SVN_ENABLE") then
    return
end

--------------------------------------------------------------------------------
-- Helpers

local api_svn = {}

local function get_svn_program()
    local pgm = os.getenv("SCMAPI_SVN_PATH") or settings.get("scmapi.svn_path")
    pgm = pgm and pgm:gsub('"', '')
    if not pgm or pgm == "" then
        pgm = "svn"
    end
    if rl.needquotes and rl.needquotes(pgm) then
        pgm = '"'..pgm..'"'
    end
    return pgm
end

local function get_flags()
    local flags = ""
    if settings.get("scmapi.svn_quiet") then
        flags = flags.." -q"
    end
    return flags
end

local function test_svn(dir)
    return scmapi.has_dir(dir, ".svn")
end

local function get_svn_branch()
    -- Return the branch information.
    local pipe = io.popenyield(string.format("2>nul %s info", get_svn_program()))
    if pipe then
        local branch
        for line in pipe:lines() do
            local m = line:match("^Relative URL:")
            if m then
                branch = line:sub(line:find("/")+1,line:len())
                break
            end
        end
        pipe:close()
        return branch
    end
end

local function add_working(status, field)
    local w = status.working or {}
    w[field] = (w[field] or 0) + 1
    status.working = w
end

local function get_svn_status()
    local status = {}

    local cmd = string.format("2>nul %s status%s", get_svn_program(), get_flags())
    local pipe, func = io.popenyield(cmd)
    if pipe then
        for line in pipe:lines() do
            local t = line:sub(1, 1)
            local t2 = line:sub(2, 2)
            if t == "M" then
                add_working(status, "modify")
            elseif t == "A" then
                add_working(status, "add")
            elseif t == "D" or t == "!" then
                add_working(status, "delete")
            elseif t == "R" then
                add_working(status, "delete")
                add_working(status, "add")
            elseif t == "?" then
                add_working(status, "untracked")
            elseif t == "C" then
                add_working(status, "conflict")
            else
                if t2 == "M" then
                    add_working(status, "modify")
                elseif t2 == "C" then
                    add_working(status, "conflict")
                end
            end
        end

        if type(func) == "function" then
            local ok, s, n = func()
            if not ok and s == "exit" and n ~= 0 then
                log.info("failure trying to run '"..cmd.."', exit code "..tostring(n))
                return nil
            end
        else
            pipe:close()
        end

        status.dirty = status.working and true or false

        if status.working then
            local t = {}
            local w = status.working
            t.modify = w.modify
            t.add = w.add
            t.delete = w.delete
            status.total = t
        end
    end

    return status
end

--------------------------------------------------------------------------------
-- APIs

function api_svn.isgitdir(dir)
    if test_svn(dir) then
        return dir, dir, dir
    end
end

function api_svn.getbranch(root)
    local _, ismain = coroutine.running()
    if ismain then
        return "svn"
    else
        return get_svn_branch(root)
    end
end

-- REVIEW: api_svn.getremote
-- REVIEW: api_svn.getconflictstatus
-- REVIEW: api_svn.getaheadbehind

function api_svn.getstatus(no_untracked, include_submodules) -- luacheck: no unused
    local status = get_svn_status()
    if status then
        status.branch = get_svn_branch()
        return status
    end
end

-- REVIEW: api_svn.hasstash
-- REVIEW: api_svn.getstashcount

scmapi.register("svn", {detect=test_svn, api=api_svn}, 31)
