-- Shows a preview of the fully qualified pathname of the current command (like
-- the 'where' command, but as a preview, i.e. as an input hint).
--
-- This is enabled by default, when input hints are enabled.
-- Run `clink set comment_row.show_hints false` to disable all input hints.
--
-- Run `clink set where.show_preview false` to disable the where preview.
-- Run `clink set comment_row.show_hints false` to disable all input hints.
--
-- Requires Clink v1.7.0 or higher.

if not clink.hinter then
    log.info("where_hinter requires a newer version of Clink; please upgrade.")
    return
end

settings.add("where.show_preview", true, "Show preview of 'where' for the current command",
             "When both the comment_row.show_hints and doskey.show_preview settings are\n"..
             "enabled and the cursor is on a doskey alias, then a preview is shown in the\n"..
             "comment row.")

settings.add("color.where_hinter", "", "Color for where hints")

local enabled
local function init_enabled()
    enabled = settings.get("where.show_preview")
end
clink.onbeginedit(init_enabled)

local hinter = clink.hinter(1)
function hinter:gethint(line_state) -- luacheck: no self
    if not enabled then
        return
    end

    local cursorpos = line_state:getcursor() or 1
    local commandwordindex = line_state:getcommandwordindex()

    local info = line_state:getwordinfo(commandwordindex)
    if not info or info.cmd or info.alias or info.offset > cursorpos then
        return
    end

    local endpos = info.offset + info.length
    local text = line_state:getline()
    if info.quoted and text:byte(endpos) == 34 then
        endpos = endpos + 1
    end
    if cursorpos > endpos then
        return
    end

    local command_word = line_state:getword(commandwordindex)
    if not command_word then
        return
    end

    local word_class, ready, file = clink.recognizecommand(command_word, info.quoted)
    if not (word_class == "x" and ready and file) then
        return
    end

    local color = settings.get("color.where_hinter")
    if color and color ~= "" then
        color = "\x1b[0;"..color.."m"
    end
    return color.."Where "..command_word.." = "..file, info.offset
end
