--------------------------------------------------------------------------------
-- Uses a ".redact_history" file to block command lines from being saved into
-- the history file, or to redact pieces of command lines before they're saved
-- into the history file.
--
-- FILE LOCATION:
--
--  Each of the following directories are checked, in the order listed.  Each
--  .redact_history file in any of these directories is loaded.
--
--      1.  The same directory where this redact_history.lua file is located.
--      2.  The Clink profile directory.
--      3.  The directory specified by the %HOME% environment variable.
--      4.  The directory specified by the %REDACT_HISTORY_PATH% environment
--          variable.
--
-- FILE FORMAT:
--
--  Each line in the ".redact_history" file can be one of the following:
--
--      - Blank lines or lines with only whitespace are ignored.
--      - Lines beginning with ; or # or // are ignored (treated as comments).
--      - Other lines are patterns using the Lua 5.2 pattern syntax, described
--        at https://www.lua.org/manual/5.2/manual.html#6.4.1.
--
--  If a pattern with no captures matches the input line, then the input line is
--  blocked from being saved into the history.  If a pattern with one or more
--  captures matches the input line, then each occurrence of the first capture in
--  the pattern is redacted with "******".
--------------------------------------------------------------------------------

local config_name = ".redact_history"   -- Config file name.

local redaction = "******"              -- Text to insert for redactions.

local block_patterns = {}               -- List of patterns to block.
local redact_patterns = {}              -- List of patterns to redact.

local loaded_timestamps = {}            -- Avoid reloading config unless timestamps have changed.
local logged_patterns = {}              -- Avoid reporting the same pattern errors more than once.

local norm = "\x1b[m"
local italic = "\x1b[3m"
local color = "\x1b[31m"

local function emoji_fallback(emoji, fallback)
    return (clink.getansihost and clink.getansihost() == "winterminal") and emoji or fallback
end

local function print_message(msg)
    local eyecatcher = emoji_fallback("🚫", "-->")
    clink.print(color..eyecatcher.." "..italic..msg..norm)
end

local function print_warning(msg)
    local eyecatcher = emoji_fallback("⚠️", "-->")
    clink.print(color..eyecatcher.." "..italic..msg..norm)
end

local function maybe_add(list, value)
    if value then
        table.insert(list, value)
    end
end

local function make_name(dir)
    if dir then
        dir = dir:gsub("^%s+", ""):gsub("%s+$", "")
        if dir ~= "" then
            local name = path.join(dir, config_name)
            if os.isfile(name) then
                return name
            end
        end
    end
end

local function get_script_file_dir()
    local info = debug.getinfo(1, 'S')
    if info then
        local src = info.source
        if src then
            src = src:gsub('^@', '')
            return path.getdirectory(src)
        end
    end
end

-- This function was mostly written by ChatGPT, plus some manual edits for table
-- management and returning failure messages.
local function process_pattern(pat)
    local pos_caps = 0
    local first_capture_start
    local first_capture_end

    local stack = {}
    local i = 1
    local n = #pat

    while i <= n do
        local c = pat:sub(i, i)

        if c == "%" then
            -- escaped character
            i = i + 2

        elseif c == "[" then
            -- character class
            i = i + 1
            while i <= n do
                local d = pat:sub(i, i)

                if d == "%" then
                    i = i + 2
                elseif d == "]" then
                    i = i + 1
                    break
                else
                    i = i + 1
                end
            end

        elseif c == "(" then
            if pat:sub(i + 1, i + 1) == ")" then
                -- position capture
                pos_caps = pos_caps + 1
                i = i + 2
            else
                -- ordinary capture
                table.insert(stack, i)

                if not first_capture_start then
                    first_capture_start = i
                end

                i = i + 1
            end

        elseif c == ")" then
            local start = table.remove(stack)
            if not start then
                return nil, "unmatched ')' at position "..tostring(i)
            end

            if start == first_capture_start and not first_capture_end then
                first_capture_end = i
            end

            i = i + 1

        else
            i = i + 1
        end
    end

    if #stack ~= 0 then
        return nil, "unmatched '(' at position "..tostring(i)
    end

    if not first_capture_start then
        table.insert(block_patterns, pat)
    else
        local p = {}
        p.orig = pat
        p.loop = not pat:find("^%^")

        if pos_caps == 2 then
            p.pattern = pat
        elseif pos_caps == 0 then
            p.pattern = table.concat({
                pat:sub(1, first_capture_start - 1),
                "()",
                pat:sub(first_capture_start, first_capture_end),
                "()",
                pat:sub(first_capture_end + 1),
            })
        else
            return nil, "unsupported number of position captures"
        end

        table.insert(redact_patterns, p)
    end

    return true
end

local function log_failure_once(name, linenum, msg, pattern)
    -- If a failure hasn't been logged yet for a pattern, then log it.
    if not logged_patterns[pattern] then
        logged_patterns[pattern] = true
        log.info(string.format("Malformed pattern in '%s' line %u; %s:  %s", name, linenum, msg, pattern))
    end
end

local function init()
    -- Make a list of config files that exist.
    local names = {}
    maybe_add(names, make_name(get_script_file_dir()))
    maybe_add(names, make_name(os.getenv("=clink.profile")))
    maybe_add(names, make_name(os.getenv("HOME")))
    maybe_add(names, make_name(os.getenv("REDACT_HISTORY_PATH")))

    -- Detect whether any of the files need to be loaded/reloaded.
    local reload
    local timestamps = {}
    for _, name in ipairs(names) do
        local t = os.globfiles(name, 2)
        if t and t[1] and t[1].mtime then
            if not loaded_timestamps[name] or t[1].mtime ~= loaded_timestamps[name] then
                timestamps[name] = t[1].mtime
                reload = true
            end
        end
    end

    if reload then
        -- Reset the lists of patterns.
        block_patterns = {}
        redact_patterns = {}
        loaded_timestamps = {}

        -- Read each file.
        local failures = 0
        for _, name in ipairs(names) do
            if not loaded_timestamps[name] then
                loaded_timestamps[name] = timestamps[name]

                local r = io.open(name)
                if r then
                    -- Remember how many patterns were loaded so far.
                    local old_b = #block_patterns
                    local old_r = #redact_patterns

                    -- Read lines from the file and process each line.
                    local linenum = 1
                    for line in r:lines() do
                        local is_comment = line:match("^[;#]") or line:match("^//") or line:match("^%s*$")
                        if not is_comment then
                            local ok, msg = process_pattern(line)
                            if not ok then
                                failures = failures + 1
                                log_failure_once(name, linenum, msg, line)
                            end
                        end
                        linenum = linenum + 1
                    end
                    r:close()

                    -- Log if any patterns were loaded from the file.
                    local new_b = #block_patterns
                    local new_r = #redact_patterns
                    if new_b > old_b then
                        log.info(string.format("Loaded %u block patterns from '%s'.", new_b - old_b, name))
                    end
                    if new_r > old_r then
                        log.info(string.format("Loaded %u redact patterns from '%s'.", new_r - old_r, name))
                    end
                end
            end
        end

        -- If there are any redaction patterns but the version of Clink is too
        -- old to support redaction, then discard the redaction patterns and log
        -- a message and print a warning.
        if redact_patterns[1] and (clink.version_encoded or 0) < 10090027 then
            redact_patterns = {}
            local msg = "History redaction patterns require Clink v1.9.27 or newer; please upgrade."
            log.info(msg)
            print_warning(msg)
        end

        -- If any pattern failures occurred, print a warning.
        if failures > 0 then
            print_warning("One or more errors while loading patterns; see clink.log for details.")
        end
    end
end

local function examine_input(line)
    -- Convert to lower case before trying to match any patterns.
    line = line:lower()

    -- Loop through block_patterns checking whether to block the input line from
    -- being added to the history.
    for _, pat in ipairs(block_patterns) do
        local ok, result = pcall(string.find, line, pat)
        if not ok then
            local msg = string.format("Error finding pattern '%s'; %s.", pat, result)
            log.info(msg)
            print_warning(msg)
        elseif result then
            -- Cancel adding the line to persisted history.
            print_message("Command line is blocked from history.")
            return false
        end
    end

    -- Loop through redact_patterns trying to apply redactions before the input
    -- line is added to the history.
    local orig = line
    for _, pat in ipairs(redact_patterns) do
        local i = 1
        local loop = pat.loop
        while true do
            -- Try to match the pattern.
            local results = { pcall(string.match, line, pat.pattern, i) }
            if not results[1] then
                local msg = string.format("Error matching pattern '%s'; %s.", pat.orig, results[2])
                log.info(msg)
                print_warning(msg)
                break
            end
            assert(type(results[1]) ~= "number")

            -- Find the (numeric) position captures.
            local positions = {}
            for _, value in ipairs(results) do
                if type(value) == "number" then
                    table.insert(positions, value)
                end
            end

            -- If not exactly 2 position captures, then stop.
            if #positions ~= 2 then
                break
            end

            -- Redact the text between the 2 position captures.
            line = table.concat({
                line:sub(1, positions[1] - 1),
                redaction,
                line:sub(positions[2]),
            })

            -- Stop if the pattern is anchored to the beginning.
            if not loop then
                break
            end

            -- Avoid a potential infinite loop:  stop if the pattern matched
            -- an empty substring at i.
            if positions[1] == i and positions[2] == i then
                break
            end

            -- Advance through the string.
            i = positions[1] + #redaction
        end
    end
    if orig ~= line then
        -- Modify the history line before saving it in the history.
        print_message("Command line is redacted in history.")
        return line
    end
end

clink.onbeginedit(init)
clink.onhistory(examine_input)
