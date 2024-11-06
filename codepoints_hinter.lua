-- Shows an optional display of Unicode codepoints at the cursor position.
-- Codepoints for emojis supersede most other hinters; codepoints for other
-- non-ASCII characters are superseded by most other hinters.
--
-- By default this display is disabled.
--
-- Run `clink set codepoints.show_preview true` to enable the display.
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
local function init_enabled()
    enabled = settings.get("codepoints.show_preview")
end
clink.onbeginedit(init_enabled)

local function codepoints_message(line_state, only_emoji)
    if not enabled then
        return
    end

    local cursorpos = line_state:getcursor() or 1
    local line = line_state:getline()

    for str, _, emoji in console.cellcountiter(line:sub(cursorpos)) do
        if only_emoji and not emoji then
            return
        elseif #str > 1 or string.byte(str) < 0x20 or string.byte(str) >= 0x80 then
            local msg = "Codepoints: "
            local utf8 = ""
            for s, value in unicode.iter(str) do
                msg = msg..string.format(" U+%X", value)
                for i = 1, #s do
                    utf8 = utf8..string.format("\\x%02x", string.byte(s, i))
                end
            end
            return msg..'  "'..utf8..'"', cursorpos
        else
            break
        end
    end
end

local hinter = clink.hinter(99)
function hinter:gethint(line_state) -- luacheck: no self
    return codepoints_message(line_state, false)
end

local hinter_emoji = clink.hinter(-1)
function hinter_emoji:gethint(line_state) -- luacheck: no self
    return codepoints_message(line_state, true)
end
