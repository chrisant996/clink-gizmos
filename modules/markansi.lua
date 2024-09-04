--------------------------------------------------------------------------------
-- Formatting is as follows:
--
--      "@@_*hello*_@@"         -->  Literal "_*hello*_" without applying markup.
--      "[display](hyperlink)"  -->  "display" plus escape codes for hyperlink.
--      "**text**"              -->  Boldface "text".
--      "*text*"                -->  Italic "text".
--      "_text_"                -->  Italic "text".
--      "`text`"                -->  Reverse video "text".
--      "~text~"                -->  Strikethrough "text".
--      "|text|"                -->  Underline "text".
--      "^text^"                -->  Overline "text".
--      "# " or "## " etc       -->  Heading.
--      "#hex"                  -->  Foreground color code for hex RRGGBB (or "@" for default).
--      "#|hex"                 -->  Background color code for hex RRGGBB (or "@" for default).
--      "#hex|hex"              -->  Foreground and background color codes (or "@" for default).
--
-- Exported functions are:
--
--  mark:
--
--      local markansi = require("markansi")
--
--      local s = markansi.mark("**Hello!**  _Isn't this cool?_")
--      clink.print(s)
--
--  getcodes:
--
--      local markansi = require("markansi")
--
--      local codes = markansi.getcodes()
--      codes["*"] = { "93", "39" }     -- Change "*" to apply yellow/default.
--      codes[":"] = { "104", "49" }    -- Add ":" to apply blue background.
--                                      -- Override the code for Headings.
--      codes["#"] = { "93;7", "\x1b[27m░▒▓\x1b[7m ", " \x1b[27m▓▒░" }
--
--      local s = markansi.mark(":Attention!:  Keep **calm** and carry **on**.", codes)
--      clink.print(s)
--

--------------------------------------------------------------------------------
-- TODO:
--  - Numbered lists.
--  - More sophisticated begin/end parsing rules.

--------------------------------------------------------------------------------
local default_codes = {
    ["#"] = { "7", " " },           -- # Heading (begin SGR, padding)
    ["*"] = { "1", "22" },          -- **bold**
    ["_"] = { "3", "23" },          -- _italic_ or *italic*
    ["`"] = { "7", "27" },          -- `reverse`
    ["~"] = { "9", "29" },          -- ~strikethrough~
    ["|"] = { "4", "24" },          -- |underline|
    ["^"] = { "53", "55" },         -- ^overline^
    default_color = { "39", "49" }, -- #@|@ default colors.
}

local double_star_bold = true       -- "**" for bold, and convert "*" to "_".

--------------------------------------------------------------------------------
local iter
if unicode and unicode.iter then
    iter = unicode.iter
else
    iter = function(text)
        local i = 1
        return (function()
            local s = text:sub(i, i)
            i = i + 1
            return (s ~= "" and s)
        end)
    end
end

local function sgr(code)
    return "\x1b["..(code or "").."m"
end

local function getcodes()
    local t = {}
    for a,b in pairs(default_codes) do
        if type(b) == "table" then
            local u = {}
            for x,y in ipairs(b) do
                u[x] = y
            end
            t[a] = u
        else
            t[a] = b
        end
    end
    return t
end

local function match_hyperlink(text, offset)
    local display, hyperlink
    display, hyperlink = text:match("^%[([^%[%]]+)%]%(([^)]+)%)", offset)
    if not display or not hyperlink then
        return
    end
    return display, hyperlink, (1 + #display + 2 + #hyperlink + 1)
end

local function mark(text, codes)
    local s = ""

    local need_norm
    local need_reapply_colors = true
    local mode = {}
    codes = codes or default_codes

    local function do_reapply_colors()
        if need_reapply_colors then
            local colors = sgr()
            if codes.default_color then
                if codes.default_color[1] then
                    colors = colors..sgr(codes.default_color[1])
                end
                if codes.default_color[2] then
                    colors = colors..sgr(codes.default_color[2])
                end
            end
            for i = 1, #mode do
                colors = colors..mode[i].sgr
            end
            s = s..colors
            need_reapply_colors = nil
        end
    end

    local function concat(append_text)
        if append_text ~= "" then
            if need_reapply_colors then
                do_reapply_colors()
            end
            s = s..append_text
        end
    end

    local _curr_offset
    local _next_offset = 1
    local _iter_func = iter(text)

    local function next()
        _curr_offset = _next_offset
        local c = _iter_func()
        if c then
            _next_offset = _next_offset + #c
        end
        return c
    end

    local peek = next()
    local startable = true
    local space = true -- luacheck: no unused

    local function set_mode(c, v)
        assert((c or "") ~= "")
        if need_reapply_colors then
            do_reapply_colors()
        end
        if not mode[c] then
            table.insert(mode, { c=c, sgr=sgr(v) })
            mode[c] = #mode
        end
        s = s..sgr(v)
        need_norm = true
    end

    local function clear_mode(c, tc)
        assert((c or "") ~= "")
        local index = mode[c]
        if index then
            for i = index + 1, #mode do
                local k = mode[i].c
                mode[k] = mode[k] - 1
            end
            mode[c] = nil
            table.remove(mode, index)
        end
        if tc then
            concat(sgr(tc))
        else
            need_reapply_colors = true
        end
    end

    while true do
        local offset = _curr_offset
        local cc
        local c = peek
        if not c then
            break
        end
        peek = next()

        if offset == 1 and c == "#" and text:find("^#+ ") then
            local t = codes["#"]
            local tc, prolog
            if type(t) == "string" then
                tc = t
                prolog = ""
            else
                tc = t[1]
                prolog = t[2] or ""
            end
            set_mode(c, tc)
            while c == "#" do
                c = peek
                peek = next()
            end
            concat(sgr(tc)..prolog)
            c = peek
            peek = next()
        end

        if c == "@" and peek == "@" then
            local tmp = ""
            while true do
                c = next()
                if not c then
                    break
                elseif c == "@" then
                    local n = next()
                    if n == "@" then
                        break
                    else
                        tmp = tmp..c..n
                    end
                else
                    tmp = tmp..c
                end
            end
            concat(tmp)
            c = ""
            peek = next()
        elseif c == "[" then
            local display, hyperlink, parsed_len = match_hyperlink(text, offset)
            local defer_reapply_colors
            if display then
                c = "\x1b]8;;"..hyperlink.."\a"..display.."\x1b]8;;\a"
                local t = codes["["]
                if type(t) == "string" then
                    c = sgr(t)..c
                    defer_reapply_colors = true
                    need_norm = true
                elseif type(t) == "table" then
                    c = sgr(t[1])..c
                    if t[2] then
                        c = c..sgr(t[2])
                    else
                        defer_reapply_colors = true
                    end
                    need_norm = true
                end
                parsed_len = parsed_len - 1
                while peek and parsed_len > 0 do
                    local x = peek
                    peek = next()
                    parsed_len = parsed_len - #x
                end
            end
            concat(c)
            c = ""
            need_reapply_colors = defer_reapply_colors or need_reapply_colors
        elseif c == "#" and (peek or ""):find("[A-Fa-f0-9|@]") then
            local fg = ""
            local bg = ""
            local color = ""
            local nope = "#"
            local alt
            while true do
                c = peek
                if not c then
                    break
                end
                nope = nope..c
                peek = next()
                if c == "|" then
                    if alt then
                        break
                    else
                        alt = true
                    end
                elseif c == "@" then
                    if color ~= "" then
                        break
                    end
                    if alt then
                        bg = c
                        break
                    else
                        fg = c
                        if peek ~= "|" then
                            break
                        end
                    end
                elseif c:find("[A-Fa-f0-9]") then
                    if color == "@" then
                        break
                    end
                    color = color..c
                    if #color == 6 then
                        if alt then
                            bg = color
                        else
                            fg = color
                        end
                        color = ""
                        if alt or peek ~= "|" then
                            break
                        end
                    end
                else
                    break
                end
            end
            if color ~= "" or
                    (fg ~= "" and fg ~= "@" and #fg ~= 6) or
                    (bg ~= "" and bg ~= "@" and #bg ~= 6) then
                c = nope
            else
                c = ""
                if fg == "@" then
                    local v = (codes.default_color and codes.default_color[1]) or "39"
                    clear_mode("#fg")
                    c = c..sgr(v)
                    need_norm = true
                elseif #fg == 6 then
                    local v = "38;2;"..tonumber(fg:sub(1, 2), 16)..
                              ";"..tonumber(fg:sub(3, 4), 16)..
                              ";"..tonumber(fg:sub(5, 6), 16)
                    set_mode("#fg", v)
                    c = c..sgr(v)
                end
                if bg == "@" then
                    local v = (codes.default_color and codes.default_color[2]) or "49"
                    clear_mode("#bg")
                    c = c..sgr(v)
                    need_norm = true
                elseif #bg == 6 then
                    local v = "48;2;"..tonumber(bg:sub(1, 2), 16)..
                              ";"..tonumber(bg:sub(3, 4), 16)..
                              ";"..tonumber(bg:sub(5, 6), 16)
                    set_mode("#bg", v)
                    c = c..sgr(v)
                end
            end
        elseif double_star_bold and c == "*" then
            if peek ~= "*" then
                cc = "_"    -- Redirect * to _ for code lookup.
            else
                cc = "*"
                c = "**"
                peek = next()
            end
        end

        if c ~= "" then
            if mode[c] and not (peek or ""):find("[A-Za-z0-9]") then
                local t = codes[cc or c]
                local tc = (type(t) == "table" and t[2])
                clear_mode(c, tc)
                c = ""
            elseif startable and peek ~= " " then
                local t = codes[cc or c]
                local tc
                if type(t) == "string" then
                    tc = t
                elseif type(t) == "table" then
                    tc = t[1]
                end
                if tc and not mode[c] then
                    set_mode(c, tc)
                    c = ""
                end
            end

            concat(c)
        end

        startable = not c:find("^[A-Za-z0-9.]$")
        space = (c == " ")
    end

    if mode["#"] then
        -- Final padding for Heading.
        s = s..(codes["#"][3] or codes["#"][2] or "")
    end

    if need_norm then
        s = s..sgr()
    end

    return s
end

return {
    mark=mark,
    getcodes=getcodes,
}
