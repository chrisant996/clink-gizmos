-- luacheck: no max line length

if type(git) ~= "table" or type(git.getstatus) ~= "function" then
    log.info("scmapi_module.lua requires a newer version of Clink; please upgrade.")
    return
end

--------------------------------------------------------------------------------
-- Core structures

local api_git = {}
for k,v in pairs(git) do
    api_git[k] = v
end

local systems = {}
local systems_order = {}
local system_priorities = {}



--------------------------------------------------------------------------------
-- Helpers

local function nilwhenzero(x)
    if x and x > 0 then
        return x
    end
end

local function sum(list)
    local n = 0
    if list then
        if type(list) == "table" then
            for _,v in pairs(list) do
                n = n + tonumber(v)
            end
        else
            n = tonumber(list)
        end
    end
    return n
end

local function get_parent(dir)
    local parent = path.toparent(dir)
    if parent and parent ~= "" and parent ~= dir then
        return parent
    end
end

-- Function that takes (dir, subdir) and returns "dir\subdir" if the subdir
-- exists, otherwise it returns nil.
local function has_dir(dir, subdir) -- luacheck: no unused
    local test = path.join(dir, subdir)
    return os.isdir(test) and test or nil
end

-- Function that takes (dir, file) and returns "dir\file" if the file exists,
-- otherwise it returns nil.
local function has_file(dir, file)
    local test = path.join(dir, file)
    return os.isfile(test) and test or nil
end

-- Function that walks up from dir, looking for scan_for in each directory.
-- Starting with dir (or cwd if dir is nil), this invokes scan_func(dir), which
-- can check for a subdir or a file or whatever it wants to check.
-- NOTE:  scan_func(dir) must return nil to keep scanning upwards; any other
-- value (including false) is returned to the caller.
local function scan_upwards(dir, scan_func) -- luacheck: no unused
    -- Set default path to current directory.
    if not dir or dir == '.' then dir = os.getcwd() end

    repeat
        -- Call the supplied function.
        local result = table.pack(scan_func(dir))
        if result ~= nil and result[1] ~= nil then return table.unpack(result, 1, result.n) end

        -- Walk up to parent path.
        local parent = get_parent(dir)
        dir = parent
    until not dir
end

local function test_git(dir)
    return api_git.isgitdir(dir)
end



--------------------------------------------------------------------------------
-- Systems

local function notimpl()
    return
end

local api_names = {
    "getaction",
    "getaheadbehind",
    "getbranch",
    "getcommondir",
    "getconflictstatus",
    "getgitdir",
    "getremote",
    "getstashcount",
    "getstatus",
    "getsystemname",
    "hasstash",
    "isgitdir",
    "loadconfig",
}

local function copy_api_funcs(api)
    local copy = {}
    for _, n in ipairs(api_names) do
        if api[n] then
            copy[n] = api[n]
        else
            copy[n] = notimpl
        end
    end
    return copy
end

local function register_scm(name, scm, priority)
    if type(name) ~= "string" or name == "" then
        error("bad argument #1 to 'register' (non-empty string expected)")
    elseif type(scm) ~= "table" or type(scm.detect) ~= "function" or type(scm.api) ~= "table" then
        error("bad argument #2 to 'register' (scm table expected)")
    elseif priority and type(priority) ~= "number" then
        error("bad argument #3 to 'register' (nil or priority number expected)")
    end

    priority = priority or 25

    local copy = {}
    local info = debug.getinfo(2, "S")
    copy.detect = scm.detect
    copy.api = copy_api_funcs(scm.api)
    copy.source = info and info.source and info.source:gsub('^@', '') or nil

    local entry = systems[name]
    if entry then
        local msg = "scm system '"..name.."' already registered"
        if entry.source then
            msg = msg.." by "..entry.source
        end
        log.info(msg, 2)
        return nil, msg
    end

    systems[name] = copy
    system_priorities[name] = priority
    table.insert(systems_order, name)
    table.sort(systems_order, function (a,b) return system_priorities[a] < system_priorities[b] end)

    return true
end

register_scm("git", {
    detect = test_git,
    api = api_git,
}, 25)

local system_dir_cache = {}

if clink.onbeginedit then
    clink.onbeginedit(function()
        system_dir_cache = {}
    end)
end

local function detect_dir(dir)
    for _, k in ipairs(systems_order) do
        local s = systems[k]
        local tested_info = s.detect(dir)
        if tested_info then
            tested_info = type(tested_info) == "table" and tested_info or {}
            tested_info.type = k
            tested_info.api = s.api
            tested_info.root = dir
            system_dir_cache[dir:lower()] = { name=k, api=s.api }
            return tested_info
        end
    end
end

local function get_system(dir)
    local git_dir, _, root = git.getgitdir(dir)
    if not git_dir or not root then return end

    local system = system_dir_cache[root:lower()]
    if not system or not system.api then return end

    return system.api, system.name, git_dir
end



--------------------------------------------------------------------------------
-- API wrappers

function git.getsystemname(dir)
    if git._fake then return "git" end

    local api, name = get_system(dir)
    if not api or not name then return end

    return name
end

-- git.makecommand:  N/A

function git.isgitdir(dir)
    dir = dir or os.getcwd()

    if git._fake then
        local git_dir = path.join(dir, ".git")
        return git_dir, git_dir, dir
    end

    local info = detect_dir(dir)
    if info then
        return info.api.isgitdir(dir)
    end
end

-- git.getgitdir:  Comes for free because the built-in implementation simply
-- calls git.isgitdir.

-- git.getcommondir:  Comes for free because the built-in implementation calls
-- git.getgitdir.  However, it checks for "commondir" and it could technically
-- malfunction if such a directory exists within some other source control
-- manager.

function git.getbranch(git_dir)
    if git._fake then return git._fake.branch end

    -- Make sure git works the same as normally.
    if git_dir and git_dir:find("%.git[/\\]*$") then
        api_git.getbranch(git_dir)
    end

    -- Pass in git_dir to ensure system_dir_cache is updated.
    git_dir = git.getgitdir(git_dir)
    if not git_dir then return end

    local api, _
    api, _, git_dir = get_system(git_dir)
    if not api or not git_dir then return end

    return api.getbranch(git_dir)
end

function git.getremote(git_dir)
    if git._fake then return git._fake.remote end

    -- Make sure git works the same as normally.
    if git_dir and git_dir:find("%.git[/\\]*$") then
        api_git.getremote(git_dir)
    end

    local api, _
    api, _, git_dir = get_system(git_dir)
    if not api or not git_dir then return end

    return api.getremote(git_dir)
end

function git.getconflictstatus()
    if git._fake then return git._fake.status and git._fake.status.untracked end

    local api, _, git_dir = get_system()
    if not api or not git_dir then return false end

    return api.getconflictstatus()
end

function git.getaheadbehind()
    local ahead, behind

    if git._fake then
        ahead = git._fake.status and git._fake.status.ahead
        behind = git._fake.status and git._fake.status.behind
    else
        local api = get_system()
        if not api then return end
        ahead, behind = api.getaheadbehind()
    end

    return ahead and tostring(ahead) or "0", behind and tostring(behind) or "0"
end

--  {
--      branch = ...                -- branch name, or commit hash if detached
--      HEAD = ...                  -- HEAD commit hash, or "(initial)"
--      detached = ...              -- true if HEAD is detached, otherwise nil
--      upstream = ...              -- upstream name, other nil
--      dirty = ...                 -- true if working and/or staged changes, otherwise nil
--      ahead = ...                 -- number of commits ahead, otherwise nil
--      behind = ...                -- number of commits behind, otherwise nil
--      unpublished = ...           -- true if unpublished, otherwise nil
--      onlystaged = ...            -- number of changes only in staged files not in working files, otherwise nil
--      tracked = ...               -- number of changes in tracked working files, otherwise nil
--      untracked = ...             -- number of untracked files or directories, otherwise nil
--      conflict = ...              -- number of conflicted files, otherwise nil
--      working = {                 -- nil if no working changes
--          add = ...               -- number of added files
--          modify = ...            -- number of modified files
--          delete = ...            -- number of deleted files
--          conflict = ...          -- number of conflicted files
--          untracked = ...         -- number of untracked files or directories
--      }
--      staged = {                  -- nil if no working changes
--          add = ...               -- number of added files
--          modify = ...            -- number of modified files
--          delete = ...            -- number of deleted files
--          rename = ...            -- number of renamed files
--      }
--      total = {                   -- nil if neither working nor staged
--          -- This counts files uniquely; if a file "foo" is deleted in working and
--          -- also in staged, it counts as only 1 deleted file.  Etc.
--          add = ...               -- total added files
--          modify = ...            -- total modified files
--          delete = ...            -- total deleted files
--      }
--  }
function git.getstatus(no_untracked, include_submodules)
    if git._fake then return git._fake.status end

    local api, name = get_system()
    if not api then return end

    local status = api.getstatus(no_untracked, include_submodules)
    if not status then return end

    -- Some fields show up in two places.  If the registered scmapi handle
    -- provided only one of the fields, then for certain fields we can help
    -- remedy the mistake by synthesizing the other fields (it isn't possible
    -- for all fields).
    if status.working then
        if not status.tracked then
            local tracked = sum(status.working) - (status.working.untracked or 0)
            status.tracked = (tracked > 0) and tracked or nil
        end
        if not status.untracked and type(status.working.untracked) == "number" then
            status.untracked = (status.working.untracked > 0) and status.working.untracked or nil
        end
        if not status.conflict and type(status.working.conflict) == "number" then
            status.conflict = (status.working.conflict > 0) and status.working.conflict or nil
        end
    else
        local untracked = (type(status.untracked) == "number") and status.untracked or 0
        local tracked = (type(status.tracked) == "number") and status.tracked or 0
        local conflict = (type(status.conflict) == "number") and status.conflict or 0
        if untracked > 0 or tracked > 0 or conflict > 0 then
            status.working = {
                add=0,
                modify=tracked,
                delete=0,
                conflict=conflict,
                untracked=untracked,
            }
        end
    end

    status.systemname = name
    return status
end

function git.hasstash()
    if git._fake then return (git._fake.stashes or 0) > 0 end

    local api = get_system()
    if not api then return false end

    return api.hasstash()
end

function git.getstashcount()
    if git._fake then return git._fake.stashes or 0 end

    local api = get_system()
    if not api then return 0 end

    return api.getstashcount()
end



--------------------------------------------------------------------------------
-- Exports

local exports = {
    register = register_scm,

    nilwhenzero = nilwhenzero,
    sum = sum,
    has_file = has_file,
    has_dir = has_dir,
    scan_upwards = scan_upwards,
}

return exports
