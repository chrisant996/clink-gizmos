--------------------------------------------------------------------------------
-- Usage:
--
-- Adds a command to fully qualify the path name under the cursor.  By default
-- it's bound to Ctrl-Alt-Q, unless something else is already bound to that.
--
-- Customize key bindings:
--
--      To bind different keys, add a key bindings for the appropriate commands
--      to your .inputrc file.  For information on customizing key bindings see
--      https://chrisant996.github.io/clink/clink.html#customizing-key-bindings
--
--      "luafunc:fully_qualify_path"
--              Fully qualify the path name under the cursor.

if not clink.parseline then
    log.info("fully_qualify.lua requires a newer version of Clink; please upgrade.")
    return
end

if rl.describemacro then
    rl.describemacro([["luafunc:fully_qualify_path"]],
                     "Fully qualify the path name under the cursor")
end

if rl.getbinding then
    local key = [["\e\C-Q"]]
    local command = rl.getbinding(key)
    if not command then
        rl.setbinding(key, [["luafunc:fully_qualify_path"]])
    end
end

local function get_word_at_cursor(rl_buffer)
    local word = ""
    local start, len
    local cursor = rl_buffer:getcursor()
    local line = rl_buffer:getbuffer()

    local commands = clink.parseline(line)
    for _, command in ipairs(commands) do
        local line_state = command.line_state
        for i = 1, line_state:getwordcount() do
            local info = line_state:getwordinfo(i)
            if info.offset < cursor then
                word = line_state:getword(i)
                start = info.offset
                len = info.length
                if info.quoted then
                    start = start - 1
                    len = len + 1
                    if line:sub(start + len, start + len) == '"' then
                        len = len + 1
                    end
                end
            else
                break
            end
        end
    end

    return word, start, len
end

local function maybe_quote(text)
    local need
    if rl.needquotes then
        need = rl.needquotes(text)
    else
        need = text:find("[ &()[%]{}^=;!%%'+,`~") and true or false
    end
    if need then
        text = '"'..text..'"'
    end
    return text
end

-- luacheck: globals fully_qualify_path
function fully_qualify_path(rl_buffer)
    local word, start, len = get_word_at_cursor(rl_buffer)
    if not word then
        rl_buffer:ding()
        return
    end

    local new = os.getfullpathname(word)

    if not new or new == word then
        rl_buffer:ding()
        return
    end

    local cursor_delta = math.max(0, rl_buffer:getcursor() - (start + len))
    rl_buffer:beginundogroup()
    rl_buffer:setcursor(start)
    rl_buffer:remove(start, start + len)
    rl_buffer:insert(new)
    rl_buffer:setcursor(rl_buffer:getcursor() + cursor_delta)
    rl_buffer:endundogroup()
end
