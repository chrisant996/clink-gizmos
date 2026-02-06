-- Shows an optional display of Unicode codepoints at the cursor position.
-- Codepoints for emojis supersede most other hinters; codepoints for other
-- non-ASCII characters are superseded by most other hinters.
--
-- This is enabled by default, when input hints are enabled.
-- Run `clink set comment_row.show_hints true` to enable input hints.
--
-- Run `clink set codepoints.show_preview false` to disable this preview.
-- Run `clink set comment_row.show_hints false` to disable all input hints.
--
-- In Clink v1.7.5 or nigher, pressing Alt-F1 will immediately display the
-- codepoints, even for ASCII characters.  Unless Alt-F1 is already bound to
-- something else, in which can you can bind "luafunc:display_codepoints" to
-- another key.
--
-- Requires Clink v1.7.4 or higher.

if not clink.hinter or not console.cellcountiter then
    log.info("codepoints_hinter requires a newer version of Clink; please upgrade.")
    return
end

settings.add("codepoints.show_preview", true, "Show Unicode codepoints at the cursor",
             "When both the comment_row.show_hints and codepoints.show_preview settings are\n"..
             "enabled and the cursor is on a non-ASCII character, then a display is shown of\n"..
             "the Unicode codepoints at the cursor position.")

local enabled
local force

local function onbeginedit()
    enabled = settings.get("codepoints.show_preview")
    force = nil
end
clink.onbeginedit(onbeginedit)

local function codepoints_message(line, cursorpos, only_emoji)
    if not enabled and not force then
        return
    end

    cursorpos = cursorpos or 1
    if force and cursorpos > #line then
        return "Codepoints:  (end of line)", cursorpos
    end

    local iter = console.cellcountiter(line:sub(cursorpos))
    local str, _, emoji = iter()
    if str then
        if only_emoji and not emoji and not force then
            return
        elseif force or #str > 1 or string.byte(str) < 0x20 or string.byte(str) >= 0x80 then
            local msg = "Codepoints: "
            local utf8 = ""
            for s, value in unicode.iter(str) do
                msg = msg..string.format(" U+%X", value)
                for i = 1, #s do
                    utf8 = utf8..string.format("\\x%02x", string.byte(s, i))
                end
            end
            return msg..'  '..str..'  "'..utf8..'"', cursorpos
        end
    end
end

local hinter = clink.hinter(99)
function hinter:gethint(line_state) -- luacheck: no self
    return codepoints_message(line_state:getline(), line_state:getcursor(), false)
end

local hinter_emoji = clink.hinter(-1)
function hinter_emoji:gethint(line_state) -- luacheck: no self
    return codepoints_message(line_state:getline(), line_state:getcursor(), true)
end

if (clink.version_encoded or 0) >= 10070005 then
    rl.describemacro("luafunc:display_codepoints", "Toggle displaying the Unicode codepoints at the cursor position")

    local has_oninputlinechanged
    local function oninputlinechanged(line)
        if line == "" then
            force = nil
        end
    end

    function display_codepoints(rl_buffer) -- luacheck: no global
        local msg
        if force then
            force = nil
        else
            force = true
            msg = codepoints_message(rl_buffer:getbuffer(), rl_buffer:getcursor(), false)
        end
        rl_buffer:setcommentrow(msg or "\x1b[m")
        if not has_oninputlinechanged then
            clink.oninputlinechanged(oninputlinechanged)
            has_oninputlinechanged = true
        end
    end

    local key = [["\e\eOP"]]
    local binding = rl.getbinding(key)
    if not binding then
        rl.setbinding(key, [["luafunc:display_codepoints"]])
    end
end
