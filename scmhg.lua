--------------------------------------------------------------------------------
-- Adds Mercurial support into Clink's "git" APIs.
--
-- This is disabled by default, to avoid performance cost for users who don't
-- need Mercurial support.
--
-- To enable Mercurial support, do either of these:
--  1. Run `clink set scmapi.hg true` to enable it for the Clink profile, and
--     then either start a new Clink session or press CTRL-X,CTRL-R to reload.
--  2. Run `set SCMAPI_HG_ENABLE=1` to enable it for the current session, and
--     then press CTRL-X,CTRL-R to reload.

local scmapi = require("scmapi_module")
if not scmapi then
    return
end

settings.add("scmapi.hg", false, "Enable Mercurial support in prompts",
             "Changing this takes effect for the next Clink session.\n"..
             "(Or set %SCMAPI_HG_ENABLE% to any value.)")
settings.add("scmapi.hg_path", "", "Full path and filename to hg program",
             "Set this if hg is not found along the system PATH.\n"..
             "(Or set %SCMAPI_HG_PATH% to the full path and filename.)")
settings.add("scmapi.hg_quiet", false, "Ignores untracked items")

if not settings.get("scmapi.hg") and not os.getenv("SCMAPI_HG_ENABLE") then
    return
end

--------------------------------------------------------------------------------
-- Helpers

local api_hg = {}

local function get_hg_program()
    local pgm = os.getenv("SCMAPI_HG_PATH") or settings.get("scmapi.hg_path")
    pgm = pgm and pgm:gsub('"', '')
    if not pgm or pgm == "" then
        pgm = "hg"
    end
    if rl.needquotes and rl.needquotes(pgm) then
        pgm = '"'..pgm..'"'
    end
    return pgm
end

local function get_flags()
    local flags = ""
    if settings.get("scmapi.hg_quiet") then
        flags = flags.." -amrd"
    end
    return flags
end

local function test_hg(dir)
    return scmapi.has_dir(dir, ".hg")
end

local function get_hg_branch()
    -- Return the branch information.
    local pipe = io.popenyield(string.format("2>nul %s branch", get_hg_program()))
    if pipe then
        local m
        for line in pipe:lines() do
            m = line:match("(.+)$")
            if m then
                break
            end
        end
        pipe:close()
        return m
    end
end

local function add_working(status, field)
    local w = status.working or {}
    w[field] = (w[field] or 0) + 1
    status.working = w
end

local function get_hg_status()
    local status = {}

    -- The default is to just use the branch name, but you could e.g. use the
    -- "hg-prompt" extension to get more information, such as any applied mq
    -- patches.  Here's an example of that:
    -- "hg prompt \"{branch}{status}{|{patch}}{update}\""
    local cmd = string.format("2>&1 %s status%s", get_hg_program(), get_flags())
    local pipe, func = io.popenyield(cmd)
    if pipe then
        for line in pipe:lines() do
            local t = line:sub(1, 1)
            if t == "M" then
                add_working(status, "modify")
            elseif t == "A" then
                add_working(status, "add")
            elseif t == "R" or t == "!" then
                add_working(status, "delete")
            elseif t == "?" then
                add_working(status, "untracked")
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

function api_hg.isgitdir(dir)
    if test_hg(dir) then
        return dir, dir, dir
    end
end

function api_hg.getbranch(root)
    local _, ismain = coroutine.running()
    if ismain then
        return "hg"
    else
        return get_hg_branch(root)
    end
end

-- REVIEW: api_hg.getremote
-- REVIEW: api_hg.getconflictstatus
-- REVIEW: api_hg.getaheadbehind

function api_hg.getstatus(no_untracked, include_submodules) -- luacheck: no unused
    local status = get_hg_status()
    if status then
        status.branch = get_hg_branch()
        return status
    end
end

-- REVIEW: api_hg.hasstash
-- REVIEW: api_hg.getstashcount

scmapi.register("hg", {detect=test_hg, api=api_hg}, 30)
