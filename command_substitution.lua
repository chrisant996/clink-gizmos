--------------------------------------------------------------------------------
-- Usage:
--
-- This simulates performing simple command substitutions similar to bash.
--
-- This:
--      echo $(echo hello)
--
-- Emits:
--      hello
--
-- Global configuration variables in Lua:
--
--      clink_gizmos_command_substitution
--              [true|false]  Set this global variable to true to enable this
--              script.  This script is disabled by default.
--
--
-- IMPORTANT WARNINGS:
--
--      This is a very simple and stupid implementation, and it does not (and
--      cannot) work the same as bash.
--
--          1.  WHETHER a command substitution runs is different!
--          2.  The ORDER in which command substitutions run is different!
--
--      In bash, command substitution happens only IF and WHEN the corresponding
--      clause is evaluated by the shell script parser engine.
--
--      In command_substitution.lua, command subsitution happens ALWAYS and
--      BEFORE passing the rest of the command line to CMD for processing.
--
--      Bash intelligently skips command substitutions that don't need to be
--      performed, for example in an 'else' clause that is not reached.  But
--      this script stupidly ALWAYS performs command substitutions no matter
--      whether CMD will reach processing that part of the command line.
--
--      Bash intelligently performs command substitutions in the correct order
--      with respect to other parts of the command line that precede or follow
--      the command substitutions.  But this script stupidly performs ALL
--      command substitutions before any other processing happens.  That means
--      command substitutions can't successfully refer to or use outputs from
--      earlier parts of the command line -- because this script does not
--      understand the rest of the command line and doesn't evaluate things in
--      the right order.
--
-- CAVEATS:
--
--      This is a simple and stupid implementation, and will not work quite as
--      expected in many cases.
--
--      This does not support nested substitutions; neither nested via typing
--      nor nested via substitution.
--
--      Spawns new cmd shells to invoke commands.  This means commands cannot
--      affect the current shell's state:  changing env vars or cwd or etc do
--      not affect the current shell.
--
--      Newlines and tab characters in the output are replaced with spaces
--      before substitution into the command line.
--
--      CMD does not support command lines longer than a total length of about
--      8,000 characters.

if not clink_gizmos_command_substitution then
    return
end

if not clink.onfilterinput then
    print('command_substitution.lua requires a newer version of Clink; please upgrade.')
    return
end

local function find_command_end(line, s)
    local quote
    local level = 1
    local i = s + 2
    while i <= #line do
        local c = line:sub(i, i)
        if c == '"' then
            quote = not quote
        elseif quote then
            -- Accept characters between quotes verbatim.
        elseif c == '^' then
            i = i + 1
        elseif c == '(' then
            level = level + 1
        elseif c == ')' then
            level = level - 1
            if level == 0 then
                return i
            end
        end
        i = i + 1
    end
end

local function substitution(line)
    local i = 1
    local result = ''
    local continue
    while true do
        -- Find a $(command).
        local s = line:find('%$%(', i)
        local e = s and find_command_end(line, s)
        if not s or not e then
            -- Concat the rest of the input line.
            result = result..line:sub(i)
            break
        end

        -- Concat what precedes the $(command).
        result = result..line:sub(i, s - 1)
        i = e + 1

        -- Substitution was found, so halt further onfilterinput processing.
        continue = false

        -- Spawn a new shell to invoke the $(command).
        local c = line:sub(s + 2, e - 1)
        local f = io.popen(c)
        if f then
            -- Read the command's output.
            local o = f:read('*a') or ''

            -- Trim trailing line endings.
            while true do
                local t = o:sub(#o)
                if t ~= '\r' or t ~= '\n' then
                    break
                end
                o = o:sub(1, #o - 1)
            end
            f:close()

            -- Replace problem characters with spaces.
            o = o:gsub('[\r\n\t]', ' ')

            -- Append the output to the input line.
            result = result..o
        end
    end
    return result, continue
end

clink.onfilterinput(substitution)
