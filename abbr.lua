--------------------------------------------------------------------------------
-- Reads abbreviations and expansions from a ".abbr" file.  An abbreviation may
-- be replaced anywhere in the input line with its corresponding expansion (for
-- a command-only abbreviation, use a doskey alias instead).
--
-- USAGE:
--
--  Upon pressing SPACE a space character is inserted and the preceding word is
--  expanded if it's defined in the .abbr file (only if the cursor is at the end
--  of the word).
--
--  Upon pressing CTRL-X,SPACE the preceding word is expanded if it's defined in
--  the .abbr file (only if the cursor is at the end of the word).  Note that
--  this does not insert a space character.
--
--  Upon pressing CTRL-X,A a popup list of available abbreviation expansions is
--  shown as defined by the .abbr file.  Pressing ENTER inserts the selected
--  expansion, or ESC cancels.
--
-- FILE LOCATION:
--
--  Each of the following directories are checked, in the order list.  Each
--  .abbr file in any of these directories is loaded.  In the case of duplicate
--  abbreviations in different files, the last one loaded wins.
--
--      1.  The same directory where this abbr.lua file is located.
--      2.  The Clink profile directory.
--      3.  The directory specified by the %HOME% environment variable.
--      4.  The directory specified by the %ABBR_PATH% environment variable.
--
-- FILE FORMAT:
--
--  Each line in the ".abbr" file follows this syntax:
--
--      word=expansion
--
--  Any line beginning with ; or # or // is ignored (treated as a comment).
--  Any line that has any whitespace characters before the equal sign is ignored.
--
-- SETTINGS:
--
--  The available settings are as follows.
--  The settings can be controlled via 'clink set'.
--
--      abbr.show_preview       When both the comment_row.show_hints and
--                              abbr.show_preview settings are enabled and the
--                              word before the cursor is an abbreviation with a
--                              defined expansion, then a preview is shown in
--                              the comment row.
--
--      color.abbr              Set this to a color value to highlight
--                              abbreviations in the input line, to indicate an
--                              expansion is available.
--
-- KEY BINDINGS:
--
--  Each default key binding mentioned in the USAGE: section is only applied if
--  the key isn't already bound to something else.
--
--  You may also set key bindings manually in your .inputrc file.
--
--[[

# Default key bindings for abbr.
" ":        "luafunc:abbr_space"    # SPACE inserts a space and expands the preceding abbreviation if possible.
"\C-x ":    "luafunc:abbr_expand"   # CTRL-X,SPACE expands the preceding abbreviation if possible.
"\C-xa":    "luafunc:abbr_popup"    # CTRL-X,A show abbreviations and their expansions in a popup list.

]]
--------------------------------------------------------------------------------

local abbr_list
local abbr_timestamps = {}
local show_preview

--------------------------------------------------------------------------------
-- Helper functions.

local function make_name(dir)
    if dir then
        dir = dir:gsub("^%s+", ""):gsub("%s+$", "")
        if dir ~= "" then
            local name = path.join(dir, ".abbr")
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

local function get_abbr_expansion(line_state)
    if abbr_list then
        local pos = line_state:getcursor()
        if pos > 1 then
            local line = line_state:getline()
            local next = line:sub(pos, pos)
            if next == "" or next == " " then
                local before = line:sub(1, pos - 1)
                if before ~= "" then
                    local word = before:match("([^%s]+)$")
                    if word then
                        return abbr_list[word], word, pos - #word
                    end
                end
            end
        end
    end
end

local function spairs(t, order)
    local keys = {}
    local num = 0
    for k in pairs(t) do
        num = num + 1
        keys[num] = k
    end

    if order then
        table.sort(keys, function(a,b) return order(t, a, b) end)
    else
        table.sort(keys)
    end

    local i = 0
    return function()
        i = i + 1
        if keys[i] then
            return keys[i], t[keys[i]]
        end
    end
end

--------------------------------------------------------------------------------
-- Initialization at the beginning of each new input line.

local function maybe_add(list, value)
    if value then
        table.insert(list, value)
    end
end

local function init()
    if clink.hinter then
        show_preview = settings.get("abbr.show_preview")
    end

    local names = {}
    maybe_add(names, make_name(get_script_file_dir()))
    maybe_add(names, make_name(os.getenv("=clink.profile")))
    maybe_add(names, make_name(os.getenv("HOME")))
    maybe_add(names, make_name(os.getenv("ABBR_PATH")))

    local reload
    local timestamps = {}
    for _, name in ipairs(names) do
        local t = os.globfiles(name, 2)
        if t and t[1] and t[1].mtime then
            if not abbr_timestamps[name] or t[1].mtime ~= abbr_timestamps[name] then
                timestamps[name] = t[1].mtime
                reload = true
            end
        end
    end

    if reload then
        abbr_list = {}
        abbr_timestamps = {}

        for _, name in ipairs(names) do
            if not abbr_timestamps[name] then
                abbr_timestamps[name] = timestamps[name]

                local r = io.open(name)
                if r then
                    local num = 0
                    for line in r:lines() do
                        line = line:gsub("^%s+", ""):gsub("%s+$", "")
                        if not line:match("^[;#]") and not line:match("^//") then
                            local a,x = line:match("^([^%s]+)=(.*)$")
                            if a then
                                abbr_list[a] = x
                                num = num + 1
                            end
                        end
                    end
                    r:close()

                    if num > 0 then
                        log.info(string.format("loaded %u abbreviations from '%s'.", num, name))
                    end
                end
            end
        end
    end
end

clink.onbeginedit(init)

--------------------------------------------------------------------------------
-- Commands available for key bindings.

local function add_desc(macro, desc)
    if rl.describemacro then
        rl.describemacro(macro, desc)
    end
end

add_desc("luafunc:abbr_space", "Insert a space, and expand the preceding abbreviation if possible")
add_desc("luafunc:abbr_expand", "Expand the preceding abbreviation if possible")
add_desc("luafunc:abbr_popup", "Show abbreviations and their expansions in a popup list")

-- luacheck: globals abbr_space
function abbr_space(rl_buffer, line_state)
    -- First, add an undo group with just a space inserted, so that undo can
    -- undo the expansion without undoing the space.
    rl_buffer:beginundogroup()
    rl_buffer:insert(" ")
    rl_buffer:endundogroup()

    -- Second, if an expansion is available, add another undo group with the
    -- expansion and a space.
    local x, word, ofs = get_abbr_expansion(line_state)
    if x then
        rl_buffer:beginundogroup()
        rl_buffer:remove(ofs, ofs + #word + 1)
        rl_buffer:setcursor(ofs)
        rl_buffer:insert(x)
        rl_buffer:insert(" ")
        rl_buffer:endundogroup()
    end
end

-- luacheck: globals abbr_expand
function abbr_expand(rl_buffer, line_state)
    local x, word, ofs = get_abbr_expansion(line_state)
    if x then
        rl_buffer:beginundogroup()
        rl_buffer:remove(ofs, ofs + #word + 1)
        rl_buffer:setcursor(ofs)
        rl_buffer:insert(x)
        rl_buffer:endundogroup()
    end
end

-- luacheck: globals abbr_popup
function abbr_popup(rl_buffer, line_state) -- luacheck: no unused
    local items = {}
    local max_len = 0
    for a, x in pairs(abbr_list) do -- luacheck: no unused
        max_len = math.max(max_len, console.cellcount(a))
    end
    for a, x in spairs(abbr_list) do
        table.insert(items, { value=x, display=a..string.rep(" ", max_len + 2 - console.cellcount(a)), description=x })
    end
    if clink.getpopuplistcolors then
        local tmp
        items.colors = clink.getpopuplistcolors()
        tmp = items.colors.items
        items.colors.items = items.colors.desc
        items.colors.desc = tmp
        tmp = items.colors.select
        items.colors.select = items.colors.selectdesc
        items.colors.selectdesc = tmp
        if items.colors.border then
            -- Workaround for border color issue in Clink v1.7.4 and earlier.
            items.colors.border = "0;"..items.colors.border
        end
    end

    local value = clink.popuplist("Abbreviations and Expansions", items)
    if value then
        rl_buffer:insert(value)
    end
end

--------------------------------------------------------------------------------
-- Default key bindings.

if rl.getbinding then
    if rl.getbinding([[" "]]) == "self-insert" then
        rl.setbinding([[" "]], [["luafunc:abbr_space"]])
    end
    if not rl.getbinding([["\C-X "]]) then
        rl.setbinding([["\C-X "]], [["luafunc:abbr_expand"]])
    end
    if not rl.getbinding([["\C-Xa"]]) then
        rl.setbinding([["\C-Xa"]], [["luafunc:abbr_popup"]])
    end
end

--------------------------------------------------------------------------------
-- Apply coloring to any command word that matches an abbreviation.

settings.add("color.abbr", "", "Color for abbreviations")

local classifier = clink.classifier(5)
function classifier:classify(commands) -- luacheck: no unused
    if abbr_list and commands and commands[1] then
        local color = settings.get("color.abbr") or ""
        if color ~= "" then
            local line_state = commands[1].line_state
            local classifications = commands[1].classifications
            local line = line_state:getline()

            local end_offset = #line + 1
            --[[
            local cwi = line_state:getcommandwordindex()
            local cwinfo = line_state:getwordinfo(cwi)
            if cwinfo then
                end_offset = cwinfo.offset + cwinfo.length
            end
            ]]

            local cur_offset = 1
            while cur_offset < end_offset do
                local so, eo = line:find("([^%s]+)", cur_offset)
                if not so then
                    break
                end
                local word = line:sub(so, eo)
                if abbr_list[word] then
                    classifications:applycolor(so, #word, color)
                end
                cur_offset = eo + 1
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Show input line hints.

if clink.hinter then
    settings.add("abbr.show_preview", true, "Show preview of abbr expansion in the input line",
                 "When both the comment_row.show_hints and abbr.show_preview settings are\n"..
                 "enabled and the word before the cursor is an abbreviation with a defined\n"..
                 "expansion, then a preview is shown in the comment row.")

    local hinter = clink.hinter(0)
    function hinter:gethint(line_state) -- luacheck: no self
        if show_preview then
            local x, word, ofs = get_abbr_expansion(line_state)
            if x then
                return "Abbr "..word.." = "..x, ofs
            end
        end
    end
end
