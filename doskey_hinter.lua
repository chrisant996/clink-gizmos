-- Shows a preview of a doskey alias entered in the input line.
--
-- This is enabled by default, when input hints are enabled.
-- Run `clink set comment_row.show_hints true` to enable input hints.
--
-- Run `clink set doskey.show_preview false` to disable the doskey preview.
-- Run `clink set comment_row.show_hints false` to disable all input hints.
--
-- Requires Clink v1.7.0 or higher.

if not clink.hinter then
    log.info("doskey_hinter requires a newer version of Clink; please upgrade.")
    return
end

settings.add("doskey.show_preview", true, "Show preview of doskey alias in the input line",
             "When both the comment_row.show_hints and doskey.show_preview settings are\n"..
             "enabled and the cursor is on a doskey alias, then a preview is shown in the\n"..
             "comment row.")

local enabled
local function init_enabled()
    enabled = settings.get("doskey.show_preview")
end
clink.onbeginedit(init_enabled)

local function expand_ctrl(text)
    local s = ""
    if text then
        local i = 1
        while i <= #text do
            local next = text:find("[\x01-\x1f]")
            if not next then
                s = s..text:sub(i)
                break
            end
            s = s.."^"..string.char(64 + text:byte(next))
            i = next + 1
        end
    end
    return s
end

local hinter = clink.hinter(1)
function hinter:gethint(line_state) -- luacheck: no self
    if not enabled then
        return
    end

    local cursorpos = line_state:getcursor() or 1
    local commandwordindex = line_state:getcommandwordindex()

    local info = line_state:getwordinfo(commandwordindex)
    if info and info.alias and info.offset <= cursorpos and cursorpos <= info.offset + info.length then
        local alias = line_state:getword(commandwordindex) or ""
        if alias ~= "" then
            local command = os.getalias(alias) or ""
            if command ~= "" then
                return "Alias "..expand_ctrl(alias).." = "..expand_ctrl(os.getalias(alias)), info.offset
            end
        end
    end
end
