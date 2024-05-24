--------------------------------------------------------------------------------
-- Usage:
--
-- Adds a command to toggle the word under the cursor between long and short
-- path names.  By default it's bound to Ctrl-Alt-A, unless something else is
-- already bound to Ctrl-Alt-A.
--
-- Press Ctrl-Alt-A to change a long path name into a short path name (8.3 names
-- with tildes) or vice versa.
--
-- Customize key bindings:
--
--      To bind different keys, add a key bindings for the appropriate commands
--      to your .inputrc file.  For information on customizing key bindings see
--      https://chrisant996.github.io/clink/clink.html#customizing-key-bindings
--
--      "luafunc:toggle_short_path"
--              Toggle the word under the cursor between long and short path
--              names.

if not clink.parseline then
    log.info("toggle_short.lua requires a newer version of Clink; please upgrade.")
    return
end

if rl.describemacro then
    rl.describemacro([["luafunc:toggle_short_path"]], "Toggle the word under the cursor between long and short path names")
end

if rl.getbinding then
    local key = [["\e\C-A"]]
    local command = rl.getbinding(key)
    if not command then
        rl.setbinding(key, [["luafunc:toggle_short_path"]])
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

-- luacheck: globals toggle_short_path
function toggle_short_path(rl_buffer)
    local word, start, len = get_word_at_cursor(rl_buffer)
    if not word then
        rl_buffer:ding()
        return
    end

    local new
    if not word:find("~") then
        new = os.getshortpathname(word)
    else
        local long = os.getlongpathname(word)
        if long and long ~= word then
            new = maybe_quote(long)
        end
    end

    if not new then
        rl_buffer:ding()
        return
    end

    rl_buffer:beginundogroup()
    rl_buffer:setcursor(start)
    rl_buffer:remove(start, start + len)
    rl_buffer:insert(new)
    rl_buffer:endundogroup()
end
