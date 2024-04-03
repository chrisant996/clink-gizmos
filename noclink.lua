-- This is a companion Lua script for the 'noclink.cmd' script.
-- Run 'noclink -?' for more information.

local envname = "NOCLINK_DISABLE_PROMPT_FILTERS"

-- Register a prompt filter that can disable prompt filtering.
local noclink = clink.promptfilter(-999999999)
function noclink:filter(prompt)
    if os.getenv(envname) then
        return prompt, false
    end
end

-- Helper function to get the path to this Lua script file.
local function get_script_dir()
    local dir
    local info = debug.getinfo(2, "S")
    if info and info.source then
        dir = path.getdirectory(info.source:sub(2))
    end
    return dir or ""
end

-- Set a doskey alias for 'noclink' to run noclink.cmd located in the same
-- directory as this Lua script file.
local alias = os.getalias("noclink")
local dir = get_script_dir()
local command = string.format('"%s" $*', path.join(dir, "noclink.cmd"))
if not alias or (alias:find("noclink.cmd") and alias ~= command) then
    if os.setalias then
        os.setalias("noclink", command)
    else
        os.execute("2>nul 1>nul doskey.exe noclink="..command)
    end
end

-- Register an argmatcher for 'noclink'.
local argmatcher = clink.argmatcher("noclink")
:addarg("prompt", "noprompt")
:addflags("/?", "-?", "/h", "-h", "/help", "-help", "--help")
if argmatcher.hideflags then
    argmatcher:hideflags("/?", "/h", "-h", "/help", "-help", "--help")
end
if argmatcher.adddescriptions then
    argmatcher:adddescriptions({
        ["prompt"] = "Re-enable Clink prompt filtering",
        ["noprompt"] = "Disable Clink prompt filtering",
        ["-?"] = "Show help",
    })
end
