--------------------------------------------------------------------------------
-- Formatting is as follows:
--
--      "@@_*hello*_@@"         -->  Literal "_*hello*_" without applying markup.
--      "{93;7}"                -->  Specifies SGR code "CSI [ SGR m".
--      "[display](hyperlink)"  -->  "display" plus escape codes for hyperlink.
--      "*text*"                -->  Boldface "text".
--      "_text_"                -->  Italic "text".
--      "`text`"                -->  Reverse video "text".
--      "~text~"                -->  Strikethrough "text".
--      "|text|"                -->  Underline "text".
--      "^text^"                -->  Overline "text".
--      "##"                    -->  Literal "#" (two # become one #).
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
--      local s = markansi.mark("*Hello!*  _Isn't this cool?_")
--      clink.print(s)
--
--  getcodes:
--
--      local markansi = require("markansi")
--
--      local codes = markansi.getcodes()
--      codes["*"] = { "93", "39" }     -- Change "*" to apply yellow/default.
--      codes[":"] = { "104", "49" }    -- Add ":" to apply blue background.
--
--      local s = markansi.mark(":Attention!:  Keep *calm* and carry *on*.")
--      clink.print(s)
--

--------------------------------------------------------------------------------
local default_codes = {
    ["*"] = { "1", "22" },          -- *bold*
    ["_"] = { "3", "23" },          -- _italic_
    ["`"] = { "7", "27" },          -- `reverse`
    ["~"] = { "9", "29" },          -- ~strikethrough~
    ["|"] = { "4", "24" },          -- |underline|
    ["^"] = { "53", "55" },         -- ^overline^
    default_color = { "39", "49" }, -- #@|@ default colors.
}

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
        local u = {}
        for x,y in ipairs(b) do
            u[x] = y
        end
        t[a] = u
    end
    return t
end

local function mark(text, codes)
    local s = ""

    local need_norm
    local mode = {}
    codes = codes or default_codes

    local next = iter(text)
    local peek = next()
    local startable = true
    local space = true

    while true do
        local c = peek
        if not c then
            break
        end
        peek = next()

        if c == "@" and peek == "@" then
            local tmp = ""
            while true do
                c = next()
                if not c then
                    s = s..tmp
                    break
                elseif c == "@" then
                    local cc = next()
                    if cc == "@" then
                        s = s..tmp
                        break
                    else
                        tmp = tmp..c..cc
                    end
                else
                    tmp = tmp..c
                end
            end
            c = ""
            peek = next()
        elseif c == "{" and startable and peek ~= " " then
            local tmp = ""
            while true do
                c = peek
                if not c then
                    s = s..tmp
                    break
                end
                peek = next()
                if c == "}" then
                    break
                else
                    tmp = tmp..c
                end
            end
            need_norm = true
            c = sgr(tmp)
        elseif c == "[" then
            local display = ""
            local hyperlink
            while true do
                c = peek
                if not c then
                    break
                end
                peek = next()
                if hyperlink then
                    if c == ")" then
                        break
                    else
                        hyperlink = hyperlink..c
                    end
                else
                    if c == "]" then
                        if peek == "(" then
                            peek = next()
                            hyperlink = ""
                        else
                            break
                        end
                    else
                        display = display..c
                    end
                end
            end
            if hyperlink then
                c = "\x1b]8;;"..hyperlink.."\a"..display.."\x1b]8;;\a"
                local t = codes["["]
                if t then
                    c = sgr(t[1])..c..sgr(t[2])
                end
            else
                c = "["..display.."]"
            end
        elseif c == "#" and peek == "#" then
            c = peek
            peek = next()
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
                elseif c:find("[A-Za-z0-9]") then
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
                    c = c..sgr((codes.default_color and codes.default_color[1]) or "39")
                    need_norm = true
                elseif #fg == 6 then
                    c = c..sgr("38;2;"..tonumber(fg:sub(1, 2), 16)..
                               ";"..tonumber(fg:sub(3, 4), 16)..
                               ";"..tonumber(fg:sub(5, 6), 16))
                    need_norm = true
                end
                if bg == "@" then
                    c = c..sgr((codes.default_color and codes.default_color[2]) or "49")
                    need_norm = true
                elseif #bg == 6 then
                    c = c..sgr("48;2;"..tonumber(bg:sub(1, 2), 16)..
                               ";"..tonumber(bg:sub(3, 4), 16)..
                               ";"..tonumber(bg:sub(5, 6), 16))
                    need_norm = true
                end
            end
        end

        if not space and not (peek or ""):find("[A-Za-z0-9]") then
            local t = codes[c]
            if t and mode[c] then
                mode[c] = false
                c = sgr(t[2])
            end
        end
        if startable and peek ~= " " then
            local t = codes[c]
            if t and not mode[c] then
                mode[c] = true
                c = sgr(t[1])
            end
        end

        s = s..c

        startable = not c:find("^[A-Za-z0-9]$")
        space = (c == " ")
    end

    for c,v in pairs(mode) do
        if v then
            s = s..sgr(codes[c][2])
        end
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
