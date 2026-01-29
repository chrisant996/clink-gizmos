--------------------------------------------------------------------------------
-- This script optionally sets the terminal title.
--
-- This is disabled by default.  Run `clink set tabtitle.enable true` to enable
-- it.  Once enabled, it updates the terminal title at the beginning and end of
-- inputting a new command line.
--
-- The terminal title is updated according to the `tabtitle.template` setting.
-- The default template for the title sets it to the current working directory.
-- Certain strings in the template are expanded as follows:
--      $cwd      = the current working directory
--      $folder   = the folder name of the current working directory
--      $command  = the most recent command
--      %envvar%  = the value of the named environment variable
-- Other text in the template string is used as-is.
--
-- IMPORTANT:  many terminals block setting the title, for security reasons.
-- Check your terminal's documentation for how to configure it to allow setting
-- the title.
--
-- If you use ConEmu:  By default, ConEmu blocks setting tab titles via escape
-- codes, but it has an alternative way which is slower.  If you configure
-- ConEmu to allow escape codes to set the title, then you can also run
-- `clink set tabtitle.ansi_codes_in_conemu true` to tell this script to use
-- escape codes instead of using ConEmu's slower alternative.

-- luacheck: no max line length

if not unicode or not unicode.iter then
    print('tabtitle.lua requires a newer version of Clink; please upgrade.')
    return
end

settings.add('tabtitle.enable', false, 'Set console title after each command prompt',
'When enabled, the console title is updated after each command prompt.\
Note that this may have no effect if the terminal isn\'t configured to allow\
escape codes to change the console title.  Check the terminal documentation\
for how to configure that.')

settings.add('tabtitle.ansi_codes_in_conemu', false, 'Controls ConEmu workaround',
'By default, ConEmu blocks setting tab titles via escape codes.  If you\
configure ConEmu to allow them, you can set this to true which will\
remove the delay before the input command line gets run.')

settings.add('tabtitle.template', '$cwd', 'Template string for setting console title',
'The default template for the title sets it to the current working directory.\
Certain strings in the template are expanded as follows:\
  $cwd = the current working directory\
  $folder = the folder name of the current working directory\
  $command = the most recent command\
  %envvar% = the value of the named environment variable\
Other text in the template string is used as-is.')

local state_text = 1
local state_keyword = 2
local state_envvar = 3

local last_command = ''
local ignoring_line

local function ignore_line(line)
    -- The direnv.lua script can issue a placeholder command to force CMD to
    -- refresh its cache of the environment variables.  Ignore the placeholder
    -- command so it doesn't pollute the title.
    if line:lower():find("__dummy_direnv_lua_clink__") then
        ignoring_line = true
    end
    return ignoring_line
end

local function process_run(state, instr, out, index, length)
    if length > 0 then
        local text
        if state == state_text then
            text = instr:sub(index, index + length - 1)
        elseif state == state_keyword then
            text = instr:sub(index, index + length - 1)
            if text == '$$' then
                text = '$'
            elseif text == '$cwd' then
                text = os.getcwd()
            elseif text == '$folder' then
                local parent, child = path.toparent(path.join(os.getcwd(), ""))
                if child and child ~= "" then
                    text = child
                else
                    text = parent
                end
            elseif text == '$command' then
                text = last_command
            end
        elseif state == state_envvar then
            text = instr:sub(index, index + length - 1)
            text = os.getenv(text:gsub('%%', '')) or text
        end
        out = out..text
    end
    return out, index + length, 0
end

local function expand_template(instr)
    local out = ''

    local index = 1
    local length = 0
    local state = state_text
    for str, value, combining in unicode.iter(instr) do -- luacheck: no unused
        if str == '$' then
            if state == state_keyword then
                if length == 1 then
                    index = index + length
                    state = state_text
                end
                out, index, length = process_run(state, instr, out, index, length)
                length = length + #str
            else
                out, index, length = process_run(state, instr, out, index, length)
                state = state_keyword
                length = length + #str
            end
        elseif str == '%' then
            if state == state_envvar then
                length = length + #str
                out, index, length = process_run(state, instr, out, index, length)
            else
                out, index, length = process_run(state, instr, out, index, length)
                state = state_envvar
                length = length + #str
            end
        elseif state == state_envvar or state == state_keyword then
            if str:find('^[A-Za-z_0-9]$') then
                length = length + #str
            else
                out, index, length = process_run(state, instr, out, index, length)
                state = state_text
                length = length + #str
            end
        else
            length = length + #str
        end
    end

    out, index, length = process_run(state, instr, out, index, length) -- luacheck: no unused

    return out
end

local function update_title()
    if not settings.get('tabtitle.enable') then
        return
    end

    local template = settings.get('tabtitle.template')
    if template == nil or template == '' then
        return
    end

    local run_conemu = false
    local host, detected = clink.getansihost()
    if detected == 'conemu' or host == 'conemu' then
        run_conemu = not settings.get('tabtitle.use_ansi_codes_in_conemu')
    end

    local title = expand_template(template)

    if run_conemu then
        -- Attempt to sanitize the input so it isn't susceptible to injection
        -- attack, i.e. accidentally running part of the title text as though it
        -- is a command to be executed.
        title = title:gsub('"', '\\"')

        -- By default, ConEmu blocks setting the tab title via escape code.
        -- So, in ConEmu, invoke the ConEmuC program to do it.
        os.execute('2>nul 1>nul conemuc -GuiMacro Rename 0 "'..title..'"')
    else
        -- Sanitize the input so it doesn't break the escape code sequence.
        title = title:gsub('\x1b', '{ESC}')
        title = title:gsub('\x07', '{BEL}')

        -- 0; sets icon name and window title.
        -- 1; sets only icon name.
        -- 2; sets only window title.
        local mode = 2
        local begincode = '\x1b]'..tostring(mode)..';'
        local endcode = '\x07'

        -- Note:  the NONL suppresses the line ending, so that only the escape
        -- is printed, so that the cursor doesn't move.
        clink.print(begincode..title..endcode, NONL) -- luacheck: globals NONL
    end
end

local function on_end_edit(line)
    if not ignore_line(line) then
        last_command = line
        update_title()
    end
end

local function on_begin_edit()
    if not ignoring_line then
        update_title()
    end
    ignoring_line = nil
end

clink.onendedit(on_end_edit)
clink.onbeginedit(on_begin_edit)
