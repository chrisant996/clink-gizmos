--------------------------------------------------------------------------------
-- Usage:
--
-- This adds a new command that can be typed at the command line (the command
-- does not work in batch scripts):
--
--      i {dir} {command}
--
-- It runs {command} in {dir}, restoring the current directory afterwards.
--
-- Completion generators for {command} show matches as though {dir} were the
-- current directory.

if (clink.version_encoded or 0) < 10030013 then
    print("i.lua requires a newer version of Clink; please upgrade.")
    return
end

--------------------------------------------------------------------------------
-- Customization.
--
-- i_commands
--      You can set the `i_commands` global variable to a list of command names.
--      The `i` behavior will be assigned to each of the command names.
--
--      For example, you might want both `i` and `in` to work:
--          i_commands = "i in"
--
-- i_colors
--      You can set the `i_colors` global variable to a table of color
--      definitions.
--
--          i_colors[true] = Color definition for directory.
--          i_colors[false] = Color definition for not a directory.
--
--      Each color definition is a table with up to two optional fields:
--          i_colors[true] = { name="name of color setting", color="ANSI SGR code" }
--
--      If both name and color are present, then color is appended to the color
--      value fetched by the color setting name.

-- luacheck: globals i_commands
i_commands = i_commands or "i"

-- luacheck: globals i_colors
i_colors = i_colors or {
    [true] =    { name="color.executable", color=";4" },
    [false] =   { name="color.unrecognized", color=";4" },
}

--------------------------------------------------------------------------------
-- Functions.

local function echo_up()
    return (clink.getansihost and clink.getansihost() ~= "clink") and " & echo \x1b[2A" or ""
end

local function i_getcolor(isdir)
    local color = i_colors[isdir]
    if not color then
        return
    end

    local sgr
    if color.name then
        sgr = settings.get(color.name)
    end
    if color.color then
        sgr = (sgr or "")..color.color
    end
    return sgr
end

local function i_getdir(line)
    -- Check for "i" command.
    local candidate = line:match("^[ \t]*([^ \t]+)[ \t]+")
    if not candidate then
        return
    end
    local commands = string.explode(i_commands or "i")
    local command_name
    for _,name in ipairs(commands) do
        if candidate == name then
            command_name = name
        end
    end
    if not command_name then
        return
    end
    line = line:gsub("^[ \t]*[^ \t]+[ \t]+", "")

    -- Get dir argument.
    local dir
    if line:sub(1) == '"' then
        dir = line:match("^\"([^\"]+)\"[ \t]*")
        if dir then
            line = line:gsub("^\"[^\"]+\"[ \t]*", "")
        end
    else
        dir = line:match("^([^ \t]+)[ \t]*")
        line = line:gsub("^[^ \t]+[ \t]*", "")
    end

    return dir, line
end

local function i_filter(line)
    local dir
    dir, line = i_getdir(line)
    if not dir then
        return
    end

    -- Check for help flag.
    if dir == "-?" or dir == "--help" then
        print("Runs a command in a directory, restoring the current directory afterwards.")
        print()
        print(clink.upper(command_name).." dir command") -- luacheck: ignore 113
        print()
        print("  dir       Change to dir.")
        print("  command   Command to run in dir.")
        return "", false
    end

    -- Get dir argument.
    if not os.isdir(dir) then
        print('"'..dir..'" is not a directory.')
        return "", false
    end

    -- Return the adjusted command line.
    local lines = {
        " pushd \""..dir.."\" >nul"..echo_up(),
        line,
        " popd >nul"..echo_up(),
    }
    return lines, false
end

local function i_ondir(arg_index, word, word_index, line_state) -- luacheck: no unused
    local info = line_state:getwordinfo(word_index)
    if info and info.offset + info.length < line_state:getcursor() then
        os.chdir(word)
    end
end

local function i_classify(arg_index, word, word_index, line_state, classifications)
    if arg_index == 1 and word ~= "" then
        local color = i_getcolor(os.isdir(word))
        if color and color ~= "" then
            local info = line_state:getwordinfo(word_index)
            classifications:applycolor(info.offset, info.length, color)
        end
    end
end

clink.onfilterinput(i_filter)

clink.argmatcher(table.unpack(string.explode(i_commands or "i")))
:addarg({onarg=i_ondir, clink.dirmatches})
:addflags("-?", "--help")
:setclassifier(i_classify)
:chaincommand("doskey") -- `i` is able to expand doskey aliases.
