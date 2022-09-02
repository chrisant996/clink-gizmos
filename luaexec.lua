--------------------------------------------------------------------------------
-- This lets you enter "rem lua: some_lua_code" and execute it as Lua code
-- within Clink by pressing Enter.
--
-- This also adds completion for Lua variables, and provides a `dumpvar()`
-- function to dump a variable.
--
--  dumpvar(var, depth) => Dumps var, recursing into tables to depth levels.
--
-- The following keys are automatically bound when using Clink v1.2.46 or
-- newer.  But for older versions of Clink the following key bindings must be
-- added to your .inputrc file:
--[[

# Use Ctrl+X,Ctrl+L to toggle Lua Execute mode.
"\C-x\C-l": "luafunc:clink_execute_lua"         # ctrl+x,ctrl+l

# Use Ctrl+X,Ctrl+K to expand the value of the Lua variable under the cursor.
"\C-x\C-k": "luafunc:clink_expand_lua_var"      # ctrl+x,ctrl+k

# In Lua Execute mode, Home (and also Shift+Home) jumps back and forth between
# the beginning of the Lua code or the beginning of the line.
"\e[H": "luafunc:luaexec_begin_line"            # Home
"\e[1;2H": "luafunc:luaexec_shift_begin_line"   # Shift+Home

# In Lua Execute mode, Ctrl+A selects only the Lua code, otherwise it selects
# the whole input line.
C-a: "luafunc:luaexec_select_all"               # Ctrl+A

# Use Alt+Ctrl+Shift+C to break into the Lua debugger.
"\e[27;8;67~": "luafunc:luaexec_pause"          # Alt+Ctrl+Shift+C

--]]

if not clink.onfilterinput then
    print("luaexec.lua requires a newer version of Clink; please upgrade.")
    return
end

--------------------------------------------------------------------------------
-- Settings configurable via `clink set`.

-- luacheck: push
-- luacheck: no max line length

settings.add("color.luaprefix", "bright cyan on blue", "Color for 'rem lua:' prefix")
settings.add("color.luacode", "", "Color for Lua code")
settings.add("lua.type_colors",
             "string=38;5;172 table=38;5;40 boolean=38;5;39 number=38;5;141 function=38;5;27 thread=38;5;203 types=38;5;244 nil=38;5;196",
             "Colors for Lua matches, by type",
             "The format is a series of type=color pairs, separated by spaces or commas.")
settings.add("lua.show_match_type", true, "Show Lua type in parens for matches")

-- luacheck: pop

--------------------------------------------------------------------------------
-- Internal data.

local lua_priority = 3          -- Arbitrary; should be fairly low, though.
local lua_prefix = "rem lua: "
local lua_prefix_match = "^ *rem +lua: *"

--------------------------------------------------------------------------------
-- Expand the Lua type colors setting into a table for internal use.

local function get_lua_type_colors()
    local out = {}
    local types = string.explode(settings.get("lua.type_colors"), ", ")
    for _,v in ipairs(types) do
        local c = string.explode(v, "=")
        out[c[1]] = "\x1b[;"..c[2].."m"
    end
    return out
end

--------------------------------------------------------------------------------
-- Get a variable's content as a string.

-- luacheck: globals getvar
function getvar(name)
    if name == nil or name == "" then return nil end

    local value = _G
    local names = name:explode(".")

    for _,n in ipairs(names) do
        if value[n] == nil then return nil end

        value = value[n]
    end

    if type(value) == "string" then
        return string.format("%q", value)
    elseif type(value) == "boolean" then
        return value and "true" or "false"
    elseif type(value) == "number" then
        return value
    end

    return nil
end

--------------------------------------------------------------------------------
-- Dump a variable's contents, recursing to depth levels.

local _type_colors
local _show_match_type
local _type_color
local function format_var_name(var_name, var_type)
    local c = _type_colors[var_type] or "\x1b[m"
    local out = c..tostring(var_name)

    if _show_match_type then
        out = out.._type_color.." ("..var_type..")"
    end

    out = out.."\x1b[m"
    return out
end

local _dumping = 0
-- luacheck: globals dumpvar
function dumpvar(value, depth, name, indent, comma)
    if _dumping == 0 then
        _type_colors = get_lua_type_colors()
        _show_match_type = settings.get("lua.show_match_type")
        _type_color = _type_colors["types"] or "\x1b[m"
    end

    _dumping = _dumping + 1

    if type(depth) == "string" and not name and not indent and not comma then
        name = depth
        depth = 1
    end

    if type(depth) ~= "number" then
        depth = 1
    elseif depth < 0 then
        depth = 0
    else
        depth = math.floor(depth)
    end

    indent = indent or ""
    comma = comma or ""

    local t = type(value)
    if t == "table" and depth > 0 then
        if name then
            clink.print(indent..format_var_name(name, t).." = { "..tostring(value))
        else
            clink.print(indent.."{ "..tostring(value))
        end
        local next_indent = indent.."  "
        depth = depth - 1
        for n,v in pairs(value) do
            if v ~= _G then
                dumpvar(v, depth, n, next_indent, ",")
            end
        end
        clink.print(indent.."}"..comma)
        _dumping = _dumping - 1
        return
    end

    if value == nil then
        value = "nil"
    else
        if t == "boolean" then
            value = value and "true" or "false"
        elseif t == "string" then
            value = string.format("%q", value)
        else
            value = tostring(value)
        end
    end

    if name then clink.print(indent..format_var_name(name, t).." = ", NONL) end -- luacheck: globals NONL
    clink.print(value..comma)

    _dumping = _dumping - 1
    return
end

--------------------------------------------------------------------------------
-- Determine whether the input line uses Lua Execute mode.

local function is_lua_code(line_state)
    if line_state:getline():match(lua_prefix_match) and
            line_state:getword(1) == "rem" and
            line_state:getword(2) == "lua:" then
        return true
    end
end

--------------------------------------------------------------------------------
-- Execute a string as Lua code.  Lifted from debugger.lua.

local function execute_lua(line)
    -- Map line starting with "=..." to "return ...".
    if string.sub(line, 1, 1) == "=" then
        line = string.gsub(line, "=" , "return ", 1)
    end

    local err = "\x1b[1;31m"
    local norm = "\x1b[m"

    local ok, func = pcall(load, line)
    if func == nil then
        local printable = line:gsub("\027", "\\027"):gsub("\008", "\\008")
        clink.print(err.."Compile error:"..norm.." "..printable)
    elseif not ok then
        clink.print(err.."Compile error:"..norm.." "..func)
    else
        -- If sandboxing is desired, then an implementation of setfenv will be
        -- needed.  I think my goal for this command is to NOT sandbox, though.
        --setfenv(func, eval_env)
        local res = { pcall(func) }
        if res[1] then
            if res[2] then
                table.remove(res, 1)
                for _,v in ipairs(res) do
                    clink.print(tostring(v).."\t", NONL) -- luacheck: globals NONL
                end
                clink.print()
            end
            --update in the context
            return 0
        else
            clink.print(err.."Run error:"..norm.." "..res[2])
        end
    end
end

--------------------------------------------------------------------------------
-- Get type of a Lua variable called 'name' (this is a name string, not the
-- variable itself).

local function get_lua_type(name)
    if name == "" or name:sub(-1) == "." then return end
    local fields = string.explode(name, ".")
    local o = _G
    for _,v in ipairs(fields) do
        o = o[v]
        if o == nil then break end
    end
    return type(o)
end

--------------------------------------------------------------------------------
-- Generate matches for Lua variables in Lua Execute mode.

local lua_generator = clink.generator(lua_priority)

local function xlate_matches(matches)
    local new_matches = {}
    local type_colors = get_lua_type_colors()
    local type_color = type_colors["types"] or "\x1b[m"
    local show_match_type = settings.get("lua.show_match_type")
    for _,m in ipairs(matches) do
        local match = m.match
        local t = get_lua_type(match)
        local c = type_colors[t] or "\x1b[m"
        local display = c..match:match("[^.]*$")
        if show_match_type then
            display = display..type_color.." ("..t..")"
        end
        table.insert(new_matches, { match=match, display=display })
    end
    return new_matches
end

local function parse_end_word(line_state)
    -- For now this handles:
    --  - aaa.bbb.etc
    -- This rejects:
    --  - aaa().bbb
    --  - aaa:bbb
    -- Eventually it can handle:            aaa["bbb"].ccc
    -- Eventually it can handle:            aaa[3]
    -- Eventually it can handle:            aaa[bbb].ccc
    -- Eventually it must NOT handle:       print("foo bar

    local word = line_state:getendword()

    if word:find("[)][.]") then return end
    if word:find(":") then return end

    -- Skip past any ".." since they're special.
    local pos = 1
    while true do
        local found, len = word:find("[.][.]+", pos)
        if not found then break end
        pos = pos + len
    end

    pos = word:find("[%w._]*$", pos)
    return pos
end

function lua_generator:getwordbreakinfo(line_state) -- luacheck: no unused
    if not is_lua_code(line_state) then return end

    local pos = parse_end_word(line_state)
    if not pos then return end

    return pos - 1
end

function lua_generator:generate(line_state, match_builder) -- luacheck: no unused
    if not is_lua_code(line_state) then return false end

    local info = line_state:getwordinfo(line_state:getwordcount())
    if not info then return true end

    local pos = info.offset
    local text = line_state:getline():sub(pos, line_state:getcursor() - 1)
    if text:sub(1, 1) == "." then return true end

    local parent
    local parentname
    local fields = string.explode(text, ".")
    local count = #fields
    if count == 0 then
        fields = { "" }
        count = 1
    elseif text:sub(-1) == "." then
        table.insert(fields, "")
        count = count + 1
    end

    -- Force regen every time, so we can generate different matches for "fle"
    -- and then for "flexprompt.set".
    clink.ondisplaymatches(xlate_matches)
    clink.onfiltermatches(xlate_matches)

    local index = 1
    while index <= count do
        if index == count then
            parent = parent or _G
            parentname = parentname and parentname.."." or ""
            local prefix = fields[index]:lower()
            for name,_ in pairs(parent or _G) do
                if #prefix == 0 or name:sub(1, #prefix):lower() == prefix then
                    match_builder:addmatch(parentname..name, "word")
                end
            end
            break
        else
            if parent and type(parent) ~= "table" then
                break
            end
            parent = (parent or _G)[fields[index]]
            parentname = (parentname and parentname.."." or "")..tostring(fields[index])
            if not parent then
                break
            end
        end
        index = index + 1
    end

    match_builder:setsuppressappend(true)
    return true
end

--------------------------------------------------------------------------------
-- Apply input line coloring in Lua Execute mode.

local lua_classifier = clink.classifier(lua_priority)
function lua_classifier:classify(commands) -- luacheck: no unused
    if commands and commands[1] then
        local line_state = commands[1].line_state
        local classifications = commands[1].classifications
        local line = line_state:getline()

        local start, length = line:find(lua_prefix_match)
        if start then
            local luaprefix_color = settings.get("color.luaprefix")
            local luacode_color = settings.get("color.luacode")
            if luacode_color == "" then luacode_color = settings.get("color.input") end

            local prefix = line:sub(start, length):gsub(" +$", "")
            local prefix_end = #prefix
            local _, prefix_start = line:find("^ +")
            prefix_start = (prefix_start or 0) + 1

            classifications:applycolor(prefix_start, prefix_end + 1 - prefix_start, luaprefix_color)
            classifications:applycolor(start + length, 999999, luacode_color)
            return true
        end
    end
end

--------------------------------------------------------------------------------
-- Helper function for CUA selection management.

local function invokecommand_until_cursor_pos(rl_buffer, command_left, command_right, target)
    if rl_buffer:getcursor() < target then
        if command_right then
            while rl_buffer:getcursor() < target do
                rl.invokecommand(command_right)
            end
        end
    elseif rl_buffer:getcursor() > target then
        if command_left then
            while rl_buffer:getcursor() > target do
                rl.invokecommand(command_left)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Filters command line input.  Any line that begins with "rem lua:" is executed
-- as Lua code.

local function onfilterinput(line)
    if line:match(lua_prefix_match) then
        line = line:gsub(lua_prefix_match, "")
    else
        return
    end

    execute_lua(line)
    return "", false
end

if clink.onfilterinput then
    clink.onfilterinput(onfilterinput)
else
    clink.onendedit(onfilterinput)
end

--------------------------------------------------------------------------------
local function add_desc(macro, desc)
    if rl.describemacro then
        rl.describemacro(macro, desc)
    end
end

--------------------------------------------------------------------------------
-- Luafunc command:  Toggles Lua Execute mode.

-- luacheck: globals clink_execute_lua
add_desc("luafunc:clink_execute_lua", "Toggle Lua execution mode")
function clink_execute_lua(rl_buffer)
    local line = rl_buffer:getbuffer()
    local prefix = line:match(lua_prefix_match)
    local cursor = rl_buffer:getcursor()
    if prefix then
        rl_buffer:remove(1, #prefix + 1)
        rl_buffer:setcursor(cursor - #prefix)
    else
        rl_buffer:setcursor(1)
        rl_buffer:insert(lua_prefix)
        rl_buffer:setcursor(cursor + #lua_prefix)
    end
end

--------------------------------------------------------------------------------
-- Luafunc command:  Expand the value of the Lua variable under the cursor.

-- luacheck: globals clink_expand_lua_var
add_desc("luafunc:clink_expand_lua_var", "Expand the value of the Lua variable under the cursor")
function clink_expand_lua_var(rl_buffer, line_state)
    local endwordoffset
    local cursor = rl_buffer:getcursor()
    local line = rl_buffer:getbuffer()

    if line_state then
        local idx = line_state:getwordcount()
        local info = line_state:getwordinfo(idx)
        endwordoffset = info.offset
    else
        endwordoffset = cursor
        while endwordoffset > 1 do
            if not line:match("^[%w._]", endwordoffset - 1) then
                break
            end
            endwordoffset = endwordoffset - 1
        end
    end

    if cursor <= endwordoffset then
        rl_buffer:ding()
        return
    end

    local word = line:sub(endwordoffset, cursor - 1)
    local replace = getvar(word)
    if not replace then return end

    rl_buffer:beginundogroup()
    rl_buffer:remove(endwordoffset, cursor)
    rl_buffer:setcursor(endwordoffset)
    rl_buffer:insert(replace)
    rl_buffer:endundogroup()
end

--------------------------------------------------------------------------------
-- Luafunc command:  Moves cursor to the beginning of Lua code, or to the
-- beginning of the line.

-- luacheck: globals luaexec_begin_line
add_desc("luafunc:luaexec_begin_line", "Moves cursor to the beginning of Lua code, or to the beginning of the line")
function luaexec_begin_line(rl_buffer)
    local line = rl_buffer:getbuffer()
    local prefix = line:match(lua_prefix_match)
    if prefix and #prefix + 1 ~= rl_buffer:getcursor() then
        invokecommand_until_cursor_pos(rl_buffer, "backward-char", "forward-char", #prefix + 1)
    else
        rl.invokecommand("beginning-of-line")
    end
end

--------------------------------------------------------------------------------
-- Luafunc command:  Extends the selection to the beginning of Lua code, or to
-- the beginning of the line.

-- luacheck: globals luaexec_shift_begin_line
add_desc("luafunc:luaexec_shift_begin_line", "Extends the selection to the beginning of Lua code, or to the beginning of the line") -- luacheck: no max line length
function luaexec_shift_begin_line(rl_buffer)
    local line = rl_buffer:getbuffer()
    local prefix = line:match(lua_prefix_match)
    if prefix and #prefix + 1 ~= rl_buffer:getcursor() then
        invokecommand_until_cursor_pos(rl_buffer, "cua-backward-char", "cua-forward-char", #prefix + 1)
    else
        rl.invokecommand("cua-beg-of-line")
    end
end

--------------------------------------------------------------------------------
-- Luafunc command:  Selects the Lua code in Lua Execute mode, otherwise it
-- selects the whole line.  Toggles between Lua code and the whole line, if the
-- Clink version supports it.

-- luacheck: globals luaexec_select_all
add_desc("luafunc:luaexec_select_all", "Selects the Lua code in Lua Execute mode, otherwise it selects the whole line")
function luaexec_select_all(rl_buffer)
    local line = rl_buffer:getbuffer()
    local prefix = line:match(lua_prefix_match)

    if not prefix then
        rl.invokecommand("cua-select-all")
        return
    end

    if rl_buffer.getanchor then
        local anchor = rl_buffer:getanchor()
        local cursor = rl_buffer:getcursor()
        local begin_test = #prefix + 1
        local end_test = rl_buffer:getlength() + 1
        if (anchor == begin_test and cursor == end_test) or
                (anchor == end_test and cursor == begin_test) then
            rl.invokecommand("cua-select-all")
            return
        end
    end

    rl.invokecommand("beginning-of-line")
    invokecommand_until_cursor_pos(rl_buffer, nil, "forward-char", #prefix + 1)
    rl.invokecommand("cua-end-of-line")
end

--------------------------------------------------------------------------------
-- luacheck: globals luaexec_pause
add_desc("luafunc:luaexec_pause", "Break into the Lua debugger")
function luaexec_pause()
	pause("Break into Lua debugger...")
end

--------------------------------------------------------------------------------
-- Key bindings.

if rl.setbinding then
    rl.setbinding([["\e[H"]],     [["luafunc:luaexec_begin_line"]],       "emacs")  -- Home
    rl.setbinding([["\e[1;2H"]],  [["luafunc:luaexec_shift_begin_line"]], "emacs")  -- Shift+Home
    rl.setbinding([["\C-a"]],     [["luafunc:luaexec_select_all"]],       "emacs")  -- Ctrl+A
    rl.setbinding([["\e[27;8;67~"]], [["luafunc:luaexec_pause"]],         "emacs")  -- Alt+Ctrl+Shift+C
    rl.setbinding([["\C-x\C-l"]], [["luafunc:clink_execute_lua"]],        "emacs")  -- Ctrl+X,Ctrl+L
    rl.setbinding([["\C-x\C-k"]], [["luafunc:clink_expand_lua_var"]],     "emacs")  -- Ctrl+X,Ctrl+K
end

