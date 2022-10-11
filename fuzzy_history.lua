--------------------------------------------------------------------------------
-- Fuzzy history suggestion strategy.
--
-- This is like the "history" strategy, but it does fuzzy matching on the
-- command word, instead of being requiring a literal prefix match.
--
-- To use this, include "fuzzy_history" in the autosuggest.strategy setting.
-- Use "clink set autosuggest.strategy <list of strategies>" to set it.
-- See "clink set autosuggest.strategy" or the Clink documentation for more
-- information about suggestions and the autosuggest.strategy setting.
--
-- Settings:
--
--      fuzzy_history.max_items
--              This limits how many history entries are searched.
--
--      fuzzy_history.max_time
--              This limits how many milliseconds can be spent searching
--              history entries.  On my laptop, 5000 entries take under 5
--              milliseconds to search.
--
--      fuzzy_history.ignore_path
--              The fuzzy match can ignore the path component of the command
--              word ("hello.exe" matches "\foo\hello.exe").
--
--      fuzzy_history.ignore_ext
--              The fuzzy match can ignore the file extension of the command
--              word ("hello" matches "hello.exe").

settings.add('fuzzy_history.max_items', 5000, 'Limit fuzzy_history searches',
    'The fuzzy_history suggestion strategy can search up to this many history\n'..
    'entries.  If not set or set to 0, it is unlimited.')

settings.add('fuzzy_history.max_time', 25, 'Limit fuzzy_history searches',
    'The fuzzy_history suggestion strategy can spend up to this many milliseconds\n'..
    'to search history entries.  If not set or set to 0, it is unlimited.')

settings.add('fuzzy_history.ignore_path', true, 'Ignores command path',
    'When true, the fuzzy_history suggestion strategy ignores command paths when\n'..
    'searching history.  E.g. "\\foo\\bar\\hello" matches "hello".')

settings.add('fuzzy_history.ignore_ext', true, 'Ignores command extension',
    'When true, the fuzzy_history suggestion strategy ignores command file\n'..
    'extensions when searching history.  E.g. "hello.exe" matches "hello".')

--------------------------------------------------------------------------------
local function log_if_expensive(tick, found, count)
    -- Anything over about 100 ms is noticable.
    -- Typical search time for 5000 items on my laptop is under 5 ms.
    local elapsed = os.clock() - tick
    if elapsed > 0.200 then
        local msg = 'PERFORMANCE: fuzzy_history took '..elapsed..' sec; '..count..' history entries searched; '
        if found then
            msg = msg..'match found'
        else
            msg = msg..'no matches found'
        end
        log.info(msg)
    end
end

--------------------------------------------------------------------------------
local function transform_command(command, ignore_path, ignore_ext)
    if ignore_path then
        if ignore_ext then
            return path.getbasename(command), path.getextension(command)
        else
            return path.getname(command), ''
        end
    else
        local p = path.getdirectory(command)
        if ignore_ext then
            return path.join(p, path.getbasename(command)), path.getextension(command)
        else
            return path.join(p, path.getname(command)), ''
        end
    end
end

--------------------------------------------------------------------------------
local sug = clink.suggester('fuzzy_history')

--------------------------------------------------------------------------------
function sug:suggest(line_state, matches)
    -- If empty or only spaces there's nothing to match.
    local line = line_state:getline()
    if not line:match('[^ ]') then
        return
    end

    -- If more than 2 words it's definitely not a match.
    if line_state:getwordcount() > 2 then
        return
    end

    -- First word must not be redirection.
    local info = line_state:getwordinfo(1)
    if not info or info.redir then
        return
    end

    -- Get command word.
    local command, gap
    local endquote
    if line_state:getwordcount() == 1 then
        command = line:sub(info.offset, line_state:getcursor() - 1)
        if info.quoted and command:sub(-1) == '"' then
            command = command:sub(1, #command - 1)
            endquote = true
        end
        gap = ''
    else
        command = line_state:getword(1)
        gap = line:sub(info.offset + info.length, line_state:getcursor() - 1)
        -- Must be one word followed by optional whitespace; no second word.
        if info.quoted and gap:find('^"') then
            gap = gap:sub(2)
            endquote = true
        end
        if gap:gsub(' ', '') ~= '' then
            return
        end
    end

    if #command == 0 then
        return
    end

    local ignore_path = settings.get('fuzzy_history.ignore_path')
    local ignore_ext = settings.get('fuzzy_history.ignore_ext')

    local name, ext = transform_command(command, ignore_path, ignore_ext)

    local max_items = settings.get('fuzzy_history.max_items')
    local upperbound = rl.gethistorycount()
    local lowerbound = 1
    if max_items and max_items > 0 then
        lowerbound = upperbound + 1 - max_items
        if lowerbound < 1 then
            lowerbound = 1
        end
    end

    local max_time = settings.get('fuzzy_history.max_time')
    if max_time and max_time <= 0 then
        max_time = nil
    else
        max_time = max_time / 1000
    end

    local tick = os.clock()
    local batch = 0
    for i = upperbound, lowerbound, -1 do
        local h = rl.gethistoryitems(i, i)[1]
        local q = 0
        local s, e = h.line:find('^ *"([^"]+)"')
        if s then
            q = 1
        else
            s, e = h.line:find('^ *([^" ][^ ]*)')
        end
        if s then
            local hc = h.line:sub(s, e)
            local hn, he = transform_command(hc, ignore_path, ignore_ext)
            local both, hb

            -- Try for an exact match of the base name, plus either an exact
            -- match of the extension or an omitted extension.
            local partial = 0
            local found = (string.matchlen(name, hn) < 0 and
                           (he == '' or ext == '' or string.matchlen(ext, he) < 0))

            -- If no match and there isn't a space yet after the command word,
            -- then try for a prefix match.
            if not found and gap == '' then
                both = name..ext
                hb = hn..he
                local len = string.matchlen(both, hb)
                if not endquote and len == #both then
                    found = true
                    partial = #hb - string.matchlen(hb, both)
                end
            end

            -- If the command word matches, then use the rest of the history
            -- line as the suggestion.
            if found then
                -- Take the rest of the history line, but strip leading spaces.
                -- If that's not empty, then we have a winner.
                local suggestion = h.line:sub(e + 1 + q):gsub('^( +)', '')
                if suggestion ~= '' then
                    if gap == '' then
                        suggestion = ' '..suggestion
                        if info.quoted and not endquote then
                            suggestion = '"'..suggestion
                        end
                        if partial > 0 then
                            suggestion = hb:sub(0 - partial)..suggestion
                        end
                    end
                    suggestion = line:sub(1, line_state:getcursor() - 1)..suggestion
                    log_if_expensive(tick, true, upperbound + 1 - i)
                    return suggestion, 1
                end
            end
        end

        batch = batch + 1
        if batch >= 5 then
            if os.clock() - tick > max_time then
                break
            end
            batch = 0
        end
    end

    log_if_expensive(tick, false, upperbound + 1 - lowerbound)
end
