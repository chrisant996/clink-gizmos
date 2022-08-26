--------------------------------------------------------------------------------
-- When the tilde.autoexpand setting is enabled, any tilde (~) by itself or any
-- tilde and path separator (~\) at the beginning of a word is expanded to the
-- user's home directory.
--
-- The tilde.escape setting specifies a string that is always expanded to a
-- single tilde after tilde expansion has been applied.
--
-- The color.autoexpandtilde setting is the color for tildes that will be
-- automatically expanded into the user's home directory.
--
-- The color.escapetilde setting is the color for the tilde escape string that
-- is always expanded to a single tilde after tilde expansion has been applied.
--
-- Unlink Readline's tilde expansion, this properly respects quotes:
--  - This works inside quoted words such as "~\foo".
--  - This properly only expands tilde at the beginning of a quoted word such
--    as "foo ~\bar" or "~\foo ~\bar".

--------------------------------------------------------------------------------
-- Version check.

if not clink.onfilterinput then
    print("tilde_autoexpand.lua requires a newer version of Clink; please upgrade.")
    return
end

--------------------------------------------------------------------------------
-- Settings.

settings.add("tilde.autoexpand", false, "Automatically expand ~ to home directory",
    "When enabled, a tilde (~) by itself or a tilde and path separator (~\\) at\n"..
    "the beginning of a word is expanded to the user's home directory.")

settings.add("tilde.escape", "~~", "Replace this with ~ after autoexpand",
    "This string is replaced by ~ after expanding tildes in the input line.")

settings.add("color.autoexpandtilde", "bri cya", "Color for home dir tilde")

settings.add("color.escapetilde", "bri cya on blu", "Color for escape for plain tilde")

--------------------------------------------------------------------------------
-- Helper functions.

local tilde_escape = {}

local function ensure_escape()
    local s = settings.get("tilde.escape")
    if s == "" then
        s = nil
    end
    if s ~= tilde_escape.setting then
        if s then
            tilde_escape.setting = s
            local pat = ""
            for i = 1, #s do
                local b = s:byte(i)
                if not (b >= 65 and b <= 90) and not (b >= 97 and b <= 122) then
                    pat = pat .. "%"
                end
                pat = pat .. s:sub(i, i)
            end
            tilde_escape.pattern = pat
        else
            tilde_escape.setting = nil
            tilde_escape.pattern = nil
        end
    end
    return tilde_escape.pattern
end

local function apply_escape(line)
    local pat = ensure_escape()
    if pat then
        line = line:gsub(pat, "~")
    end
    return line
end

--------------------------------------------------------------------------------
-- Input filter function, to expand tildes.

local tilde_autoexpand

if clink.parseline then

    local function need_quote(word)
        return word and word:find("[ &()[%]{}^=;!%'+,`~]") and true
    end

    local function maybe_quote(word)
        if need_quote(word) then
            word = '"' .. word .. '"'
        end
        return word
    end

    tilde_autoexpand = function (line)
        if settings.get("tilde.autoexpand") then
            local out = ""
            local commands = clink.parseline(line)
            local next = 1
            for _, c in ipairs(commands) do
                local ls = c.line_state
                for i = 1, ls:getwordcount() do
                    local info = ls:getwordinfo(i)
                    local word, expanded = rl.expandtilde(ls:getword(i))
                    if expanded and not info.quoted then
                        word = maybe_quote(word)
                    end
                    out = out .. line:sub(next, info.offset - 1) .. word
                    next = info.offset + info.length
                end
            end
            out = out .. line:sub(next, #line)
            return apply_escape(out)
        end
    end

else

    tilde_autoexpand = function (line)
        if settings.get("tilde.autoexpand") then
            local expanded = rl.expandtilde(line)
            return apply_escape(expanded)
        end
    end

end

clink.onfilterinput(tilde_autoexpand)

--------------------------------------------------------------------------------
-- Input line coloring for tilde expansion.

if clink.classifier then

    local clf = clink.classifier(999)

    function clf:classify(commands) -- luacheck: no unused
        if not settings.get("tilde.autoexpand") then
            return
        end

        -- Color tildes that will expand.
        local color = settings.get("color.autoexpandtilde")
        if color and color ~= "" then
            for _, c in ipairs(commands) do
                local ls = c.line_state
                local first_word = true
                for i = 1, ls:getwordcount() do
                    local word = ls:getword(i)
                    local info = ls:getwordinfo(i)
                    if word:sub(1, 1) == "~" then
                        local expanded
                        word, expanded = rl.expandtilde(word)
                        if expanded then
                            if first_word and not info.redir and clink.recognizecommand then
                                word = apply_escape(word)
                                local cl = clink.recognizecommand(ls:getline(), word, info.quoted)
                                if cl then
                                    local m = clink.getargmatcher(word) and "m" or ""
                                    c.classifications:classifyword(i, m..cl, true)
                                end
                                first_word = false
                            end
                            c.classifications:applycolor(info.offset, 1, color)
                        end
                    end
                end
            end
        end

        -- Color escapes that will turn into tildes.
        local pat = ensure_escape()
        if pat then
            local i = 1
            local line = commands[1] and commands[1].line_state:getline() or ""
            local classifications = commands[1] and commands[1].classifications
            color = settings.get("color.escapetilde")
            if color and color ~= "" then
                while true do
                    local s, e = line:find(pat, i)
                    if not s then
                        break
                    end
                    classifications:applycolor(s, e + 1 - s, color)
                    i = e + 1
                end
            end
        end
    end

end
