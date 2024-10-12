-- Highlights environment variables in a command line.
-- It does not (and cannot) handle delayed expansions.
--
-- By default it doesn't color environment variables.
--
-- Set a color via `clink set color.envvars YOUR COLOR HERE`.

settings.add("color.envvars", "", "Color for environment variables")

local ev = clink.classifier(1)
function ev:classify(commands) -- luacheck: no unused
    local color = settings.get("color.envvars") or ""
    if color ~= "" and commands and commands[1] then
        local line_state = commands[1].line_state
        local classifications = commands[1].classifications
        local line = line_state:getline()
        local in_out = false
        local index = 0

        while true do
            local next = line:find("%", index + 1, true--[[plain]])
            if not next then
                break
            end
            in_out = not in_out
            if in_out then
                index = next
            else
                local value = os.getenv(line:sub(index + 1, next - 1))
                if value then
                    classifications:applycolor(index, next + 1 - index, color)
                    index = next
                else
                    in_out = true
                    index = next
                end
            end
        end
    end
end

if clink.hinter then

    settings.add("highlight_envvars.show_preview", true, "Show preview of environment variable at cursor",
                 "When both the comment_row.show_hints and highlight_envvars.show_preview\n"..
                 "settings are enabled and the cursor is on a doskey alias, then a preview is\n"..
                 "shown in the comment row.")

    local enabled
    local function init_enabled()
        enabled = settings.get("highlight_envvars.show_preview")
    end
    clink.onbeginedit(init_enabled)

    local eh = clink.hinter(1)
    function eh:gethint(line_state) -- luacheck: no self
        if not enabled then
            return
        end

        local hint
        local pos

        local line = line_state:getline()
        local in_out = false
        local index = 0
        local cursorpos = line_state:getcursor() or 1

        while index <= cursorpos do
            local next = line:find("%", index + 1, true--[[plain]])
            if not next then
                break
            end
            in_out = not in_out
            if in_out then
                index = next
            else
                local name = line:sub(index + 1, next - 1)
                local value = os.getenv(name)
                if value then
                    if index <= cursorpos and cursorpos <= next + 1 then
                        hint = string.format("Envvar %s = %s", name, tostring(value))
                        pos = index
                    end
                    index = next
                else
                    in_out = true
                    index = next
                end
            end
        end

        return hint, pos
    end

end
