--------------------------------------------------------------------------------
-- FZF integration for Clink.
--
-- Clink is available at https://chrisant996.github.io/clink
-- FZF is available from https://nicedoc.io/junegunn/fzf
--
-- Either put fzf.exe in a directory listed in the system PATH environment
-- variable, or run 'clink set fzf.exe_location <directoryname>' to tell Clink
-- where to find fzf.exe.
--
-- To use FZF integration, you may set key bindings manually in your .inputrc
-- file, or you may use the default key bindings.  To use the default key
-- bindings, run 'clink set fzf.default_bindings true'.
--
-- The key bindings when 'fzf.default_bindings' is true are as follows.  They
-- are presented in .inputrc file format for convenience, if you want to add
-- them to your .inputrc manually (perhaps with modifications).
--[[

# Default key bindings for fzf with Clink.
"\C-t":        "luafunc:fzf_file"           # Ctrl+T lists files recursively; choose one or multiple to insert them.
"\C-r":        "luafunc:fzf_history"        # Ctrl+R lists history entries; choose one to insert it.
"\M-c":        "luafunc:fzf_directory"      # Alt+C lists subdirectories; choose one to 'cd /d' to it.
"\M-b":        "luafunc:fzf_bindings"       # Alt+B lists key bindings; choose one to invoke it.
"\t":          "luafunc:fzf_complete"       # Tab uses fzf to filter match completions, but only when preceded by '**' (recursive).
"\e[27;5;32~": "luafunc:fzf_complete_force" # Ctrl+Space uses fzf to filter match completions (and supports '**' for recursive).

]]
-- Optional:  You can set the following environment variables to customize the
-- behavior:
--
--          FZF_CTRL_T_OPTS     = fzf options for fzf_file() function.
--          FZF_CTRL_R_OPTS     = fzf options for fzf_history() function.
--          FZF_ALT_C_OPTS      = fzf options for fzf_directory() function.
--          FZF_BINDINGS_OPTS   = fzf options for fzf_bindings() function.
--          FZF_COMPLETE_OPTS   = fzf options for fzf_complete() and fzf_complete_force() functions.
--
--          FZF_CTRL_T_COMMAND  = command to run for collecting files for fzf_file() function.
--          FZF_ALT_C_COMMAND   = command to run for collecting directories for fzf_directory() function.
--
--          FZF_COMPLETION_DIR_COMMANDS = commands that should complete only directories, separated by spaces.

--------------------------------------------------------------------------------
-- Compatibility check.
if not io.popenrw then
    print('fzf.lua requires a newer version of Clink; please upgrade.')
    return
end

package.path = debug.getinfo(1, "S").source:match[[^@?(.*[\/])[^\/]-$]] .."modules/?.lua;".. package.path
require('arghelper')

--------------------------------------------------------------------------------
-- Settings available via 'clink set'.

settings.add('fzf.height', '40%', 'Height to use for the --height flag')
settings.add('fzf.exe_location', '', 'Location of fzf.exe if not on the PATH')

if rl.setbinding then

    settings.add(
        'fzf.default_bindings',
        false,
        'Use default key bindings',
        'To avoid interference with your existing key bindings, key bindings for\n'..
        'fzf are initially not enabled.  Set this to true to enable the default\n'..
        'key bindings for fzf, or add bindings manually to your .inputrc file.\n\n'..
        'Changing this takes effect for the next Clink session.')

    if settings.get('fzf.default_bindings') then
        rl.setbinding([["\C-t"]], [["luafunc:fzf_file"]])
        rl.setbinding([["\C-r"]], [["luafunc:fzf_history"]])
        rl.setbinding([["\M-c"]], [["luafunc:fzf_directory"]])
        rl.setbinding([["\M-b"]], [["luafunc:fzf_bindings"]])
        rl.setbinding([["\t"]], [["luafunc:fzf_complete"]])
        rl.setbinding([["\e[27;5;32~"]], [["luafunc:fzf_complete_force"]])
    end

end

--------------------------------------------------------------------------------
-- Helpers.

local diag = false
local fzf_complete_intercept = false

local function get_fzf(env)
    local height = settings.get('fzf.height')
    local command = settings.get('fzf.exe_location')
    if os.expandenv and command then
        -- Expand so that os.getshortpathname() can work even when envvars are
        -- present.
        command = os.expandenv(command)
    end
    if not command or command == '' then
        command = 'fzf.exe'
    else
        -- CMD.exe cannot use pipe redirection with a quoted program name, so
        -- try to use a short name.
        local short = os.getshortpathname(command)
        if short then
            command = short
        end
    end
    if command and command ~= '' and height and height ~= '' then
        command = command..' --height '..height
    end
    if env then
        local options = os.getenv(env)
        if options then
            command = command..' '..options
        end
    end
    return command
end

local function get_clink()
    local clink_alias = os.getalias('clink')
    if not clink_alias or clink_alias == '' then
        return ''
    end
    return clink_alias:gsub(' $[*]', '')
end

local function need_quote(word)
    return word and word:find("[ &()[%]{}^=;!%'+,`~]") and true
end

local function maybe_quote(word)
    if need_quote(word) then
        word = '"' .. word .. '"'
    end
    return word
end

local function replace_dir(str, word)
    if word then
        word = maybe_quote(rl.expandtilde(word))
    end
    return str:gsub('$dir', word or '.')
end

local function get_word_at_cursor(line_state)
    if line_state:getwordcount() > 0 then
        local info = line_state:getwordinfo(line_state:getwordcount())
        if info then
            local line = line_state:getline()
            local word = line:sub(info.offset, line_state:getcursor() - 1)
            if word and #word > 0 then
                word = word:gsub('"', '')
                word = word:gsub("'", '')
                return word
            end
        end
    end
end

local function get_word_insert_bounds(line_state)
    if line_state:getwordcount() > 0 then
        local info = line_state:getwordinfo(line_state:getwordcount())
        if info then
            local first = info.offset
            local last = line_state:getcursor() - 1
            local quote
            local delimit
            if info.quoted then
                local line = line_state:getline()
                first = first - 1
                quote = line:sub(first, first)
                local eq = line:sub(last + 1, last + 1)
                if eq == '' or eq == ' ' or eq == '\t' then
                    delimit = true
                end
            end
            return first, last, quote, delimit
        end
    end
end

local function get_ctrl_t_command(dir)
    local command = os.getenv('FZF_CTRL_T_COMMAND')
    if not command then
        command = 'dir /b /s /a:-s $dir'
    end
    command = replace_dir(command, dir)
    return command
end

local function get_alt_c_command(dir)
    local command = os.getenv('FZF_ALT_C_COMMAND')
    if not command then
        command = 'dir /b /s /a:d-s $dir'
    end
    command = replace_dir(command, dir)
    return command
end

local function is_trigger(line_state)
    local word = get_word_at_cursor(line_state)
    if word and word:sub(#word - 1) == '**' then
        return word:sub(1, #word - 2)
    end
end

local function is_dir_command(line_state)
    local command = line_state:getword(1)
    local dir_commands = os.getenv('FZF_COMPLETION_DIR_COMMANDS') or 'cd chdir rd rmdir pushd'
    for _,c in ipairs(string.explode(dir_commands)) do
        if string.equalsi(c, command) then
            return true
        end
    end
end

local function fzf_recursive(rl_buffer, line_state, search, quote, dirs_only)
    local dir, word
    dir = path.getdirectory(search)
    word = path.getname(search)

    local command
    if dirs_only then
        command = get_alt_c_command(dir)
    else
        command = get_ctrl_t_command(dir)
    end

    local first, last, has_quote, delimit = get_word_insert_bounds(line_state)
    local quote = has_quote or '"'

    local r = io.popen(command..' 2>nul | '..get_fzf('FZF_COMPLETE_OPTS')..' -q "'..word..'"')
    if not r then
        rl_buffer:ding()
        return
    end

    -- Read filtered matches.
    local match
    while (true) do
        local line = r:read('*line')
        if not line then
            break
        end
        if not match then
            match = line
        end
    end
    r:close()

    if not match then
        return
    end

    -- Insert match.
    local use_quote = ((has_quote or need_quote(match)) and quote) or ''
    rl_buffer:beginundogroup()
    rl_buffer:remove(first, last + 1)
    rl_buffer:setcursor(first)
    rl_buffer:insert(use_quote)
    rl_buffer:insert(match)
    rl_buffer:insert(use_quote)
    rl_buffer:insert(' ')
    rl_buffer:endundogroup()
end

local function fzf_complete_internal(rl_buffer, line_state, force)
    local search = is_trigger(line_state)
    if search then
        -- Gather files and/or dirs recursively, and show them in fzf.
        local dirs_only = is_dir_command(line_state)
        fzf_recursive(rl_buffer, line_state, search, dirs_only)
        rl_buffer:refreshline()
    elseif not force then
        -- Invoke the normal complete command.
        rl.invokecommand('complete')
    else
        -- Intercept matches Use match filtering to let
        fzf_complete_intercept = true
        rl.invokecommand('complete')
        if fzf_complete_intercept then
            rl_buffer:ding()
        end
        fzf_complete_intercept = false
        rl_buffer:refreshline()
    end
end

--------------------------------------------------------------------------------
-- Functions for use with 'luafunc:' key bindings.

function fzf_complete(rl_buffer, line_state)
    fzf_complete_internal(rl_buffer, line_state, false)
end

function fzf_complete_force(rl_buffer, line_state)
    fzf_complete_internal(rl_buffer, line_state, true)
end

function fzf_history(rl_buffer)
    local clink_command = get_clink()
    if #clink_command == 0 then
        rl_buffer:ding()
        return
    end

    -- Build command to get history for the current Clink session.
    local history = clink_command..' --session '..clink.getsession()..' history --bare'
    if diag then
        history = history..' --diag'
    end

    -- This intentionally does not use '--query' because that isn't safe:
    -- Depending on what the user has typed so far, passing it as an argument
    -- may cause the command to interpreted differently than expected.
    -- E.g. suppose the user typed:     "pgm.exe & rd /s
    -- Then fzf would be invoked as:    fzf.exe --query""pgm.exe & rd /s"
    -- And since the & is not inside quotes, the 'rd /s' command gets actually
    -- run by mistake!
    local r = io.popen(history..' 2>nul | '..get_fzf('FZF_CTRL_R_OPTS')..' -i --tac')
    if not r then
        rl_buffer:ding()
        return
    end

    local str = r:read('*all')
    str = str and str:gsub('[\r\n]', '') or ''
    r:close()

    -- If something was selected, insert it.
    if #str > 0 then
        rl_buffer:beginundogroup()
        rl_buffer:remove(0, -1)
        rl_buffer:insert(str)
        rl_buffer:endundogroup()
    end

    rl_buffer:refreshline()
end

function fzf_file(rl_buffer, line_state)
    local dir = get_word_at_cursor(line_state)
    local command = get_ctrl_t_command(dir)

    local r = io.popen(command..' 2>nul | '..get_fzf('FZF_CTRL_T_OPTS')..' -i -m')
    if not r then
        rl_buffer:ding()
        return
    end

    local str = r:read('*line')
    str = str and str:gsub('[\r\n]+', ' ') or ''
    str = str:gsub(' +$', '')
    r:close()

    if #str > 0 then
        if str:find("[ &()[%]{}^=;!%%'+,`~]") then
            str = '"'..str..'"'
        end
        rl_buffer:insert(str)
    end

    rl_buffer:refreshline()
end

function fzf_directory(rl_buffer, line_state)
    local dir = get_word_at_cursor(line_state)
    local command = get_alt_c_command(dir)

    local temp_contents = rl_buffer:getbuffer()
    local r = io.popen(command..' 2>nul | '..get_fzf('FZF_ALT_C_OPTS')..' -i')
    if not r then
        rl_buffer:ding()
        return
    end

    local str = r:read('*all')
    str = str and str:gsub('[\r\n]', '') or ''
    r:close()

    if #str > 0 then
        rl_buffer:beginundogroup()
        rl_buffer:remove(0, -1)
        rl_buffer:insert('cd /d '..str)
        rl_buffer:endundogroup()
        rl_buffer:refreshline()
        rl.invokecommand('accept-line')
        return
    end

    rl_buffer:refreshline()
end

function fzf_bindings(rl_buffer)
    if not rl.getkeybindings then
        rl_buffer:beginoutput()
        print('fzf_bindings() in fzf.lua requires a newer version of Clink; please upgrade.')
        return
    end

    local bindings = rl.getkeybindings()
    if #bindings <= 0 then
        rl_buffer:refreshline()
        return
    end

    local line
    local r,w = io.popenrw(get_fzf('FZF_BINDINGS_OPTS')..' -i')
    if r and w then
        -- Write key bindings to the write pipe.
        for _,kb in ipairs(bindings) do
            w:write(kb.key..' : '..kb.binding..'\n')
        end
        w:close()

        -- Read filtered matches.
        local ret = {}
        line = r:read('*line')
        r:close()
    end

    rl_buffer:refreshline()

    if line and #line > 0 then
        local binding = line:sub(#bindings[1].key + 3 + 1)
        rl.invokecommand(binding)
    end
end

--------------------------------------------------------------------------------
-- Match generator.

local function filter_matches(matches, completion_type, filename_completion_desired)
    if not fzf_complete_intercept then
        return
    end
    if #matches <= 1 then
        return
    end

    -- Start fzf.
    local r,w = io.popenrw(get_fzf('FZF_COMPLETE_OPTS'))
    if not r or not w then
        return
    end

    -- Write matches to the write pipe.
    for _,m in ipairs(matches) do
        w:write(m.match..'\n')
    end
    w:close()

    -- Read filtered matches.
    local ret = {}
    while (true) do
        local line = r:read('*line')
        if not line then
            break
        end
        for _,m in ipairs(matches) do
            if m.match == line then
                table.insert(ret, m)
            end
        end
    end
    r:close()

    -- Yay, successful; clear it to not ding.
    fzf_complete_intercept = false
    fzf_trigger_search = nil
    return ret
end

local interceptor = clink.generator(0)
function interceptor:generate(line_state, match_builder)
    if fzf_complete_intercept then
        clink.onfiltermatches(filter_matches)
    end
    return false
end

clink.onbeginedit(function ()
    fzf_complete_intercept = false
    fzf_trigger_search = nil
end)

--------------------------------------------------------------------------------
-- Argmatcher.

local algos = clink.argmatcher():_addexarg({
    { 'v1',             'Optimal scoring algorithm (quality)' },
    { 'v2',             'Faster but not guaranteed to find the optimal result (performance)' },
})
local nth = clink.argmatcher():addarg({fromhistory=true, loopchars=','})
local delim = clink.argmatcher():addarg({fromhistory=true})
local criteria = clink.argmatcher():addarg({
    loopchars=',',
    { 'length',         'Prefers line with shorter length' },
    { 'begin',          'Prefers line with matched substring closer to the beginning' },
    { 'end',            'Prefers line with matched substring closer to the end' },
    { 'index',          'Prefers line that appeared earlier in the input stream' },
})
local multimax = clink.argmatcher():addarg({fromhistory=true})
local keybinds = clink.argmatcher():addarg({fromhistory=true, loopchars=','})
local scrolloff = clink.argmatcher():addarg({fromhistory=true, '0'})
local hscrolloff = clink.argmatcher():addarg({fromhistory=true, '10'})
local jumplabels = clink.argmatcher():addarg({fromhistory=true})
local heights = clink.argmatcher():addarg({fromhistory=true, '10', '15', '20', '25%', '30%', '40%', '50%'})
local minheight = clink.argmatcher():addarg({fromhistory=true, '10'})
local layout = clink.argmatcher():_addexarg({
    nosort=true,
    { 'default',        'Display from the bottom of the screen' },
    { 'reverse',        'Display from the top of the screen' },
    { 'reverse-list',   'Display from the top of the screen, prompt at the bottom' },
})
local borderstyle = clink.argmatcher():addarg({
    nosort=true,
    'rounded',
    'sharp',
    'horizontal',
    'vertical',
    'top',
    'bottom',
    'left',
    'right',
    'none',
})
local margin = clink.argmatcher():addarg({fromhistory=true, loopchars=',', '0', '1', '2'})
local padding = clink.argmatcher():addarg({fromhistory=true, loopchars=',', '0', '1', '2'})
local infostyle = clink.argmatcher():_addexarg({
    nosort=true,
    { 'default',        'Display on the next line to the prompt' },
    { 'inline',         'Display on the same line as the prompt' },
    { 'hidden',         'Do not display finder info' },
})
local prompt = clink.argmatcher():addarg({fromhistory=true, '"> "'})
local pointer = clink.argmatcher():addarg({fromhistory=true, '">"', '"*"'})
local marker = clink.argmatcher():addarg({fromhistory=true, '">"', '"*"'})
local header = clink.argmatcher():addarg({fromhistory=true})
local headerlines = clink.argmatcher():addarg({fromhistory=true})
local ellipsis = clink.argmatcher():addarg({fromhistory=true, '..', '...', '…'})
local tabstop = clink.argmatcher():addarg({fromhistory=true, '8'})
local colspec = clink.argmatcher():addarg({fromhistory=true, loopchars=','})
local historysize = clink.argmatcher():addarg({fromhistory=true, '1000'})
local previewcommand = clink.argmatcher():addarg({fromhistory=true})
local previewopt = clink.argmatcher():addarg({
    fromhistory=true,
    loopchars=',:',
    'up', 'down', 'left', 'right',
    '10%', '20%', '25%', '30%', '40%', '50%', '60%', '70%', '75%', '80%', '90%',
    'wrap', 'nowrap',
    'cycle', 'nocycle',
    'follow', 'nofollow',
    'hidden', 'nohidden',
    'border',
    'border-rounded', 'border-sharp',
    'border-horizontal', 'border-vertical',
    'border-top', 'border-bottom', 'border-left', 'border-right',
    'border-none',
    '+SCROLL[OFFSETS][/DENOM]',
    '~HEADER_LINES',
    'default',
})
local query = clink.argmatcher():addarg({fromhistory=true})
local filter = clink.argmatcher():addarg({fromhistory=true})
local expect = clink.argmatcher():addarg({fromhistory=true, loopchars=','})

clink.argmatcher('fzf')
:_addexflags({
    opteq=true,
    -- Search options
    { '-x',                             'Extended-search mode (enabled by default; +x or --no-extended to disable)' },
    { '+x',                             'Disable extended-search mode' },
    { '--extended',                     'Extended-search mode (enabled by default; +x or --no-extended to disable)' },
    { '--no-extended',                  'Disable extended-search mode' },
    { '-e',                             'Enable Exact-match' },
    { '--exact',                        'Enable Exact-match' },
    { '--algo='..algos, 'TYPE',         'Fuzzy matching algorithm' },
    { '-i',                             'Case-insensitive match (default: smart-case match; +i for case-sensitive match)' },
    { '+i',                             'Case-sensitive match' },
    { '--literal',                      'Do not normalize latin script letters before matching' },
    { '-n'..nth, ' N[,..]',             'Comma-separated list of field index expressions for limiting search scope (non-zero integer or range expression "1..4")' },
    { '--nth='..nth, 'N[,..]',          'Comma-separated list of field index expressions for limiting search scope (non-zero integer or range expression "1..4")' },
    { '--with-nth='..nth, 'N[,..]',     'Transform the presentation of each line using field index expressions' },
    { '-d'..delim, ' STR',              'Field delimiter regex (default: AWK-style)' },
    { '--delimiter='..delim, 'STR',     'Field delimiter regex (default: AWK-style)' },
    { '+s',                             'Do not sort the result' },
    { '--no-sort',                      'Do not sort the result' },
    { '--tac',                          'Reverse the order of the input' },
    { '--disabled',                     'Do not perform search' },
    { '--tiebreak='..criteria, 'CRI[,..]', 'Comma-separated list of sort criteria to apply when the scores are tied (default: length)' },

    -- Interface options
    { '-m',                             'Enable multi-select with tab/shift-tab' },
    { '--multi',                        'Enable multi-select with tab/shift-tab' },
    { '--multi='..multimax, 'MAX',      'Enable multi-select with tab/shift-tab', opteq=false },
    { '--no-mouse',                     'Disable mouse' },
    { '--bind='..keybinds, 'KEYBINDS',  'Custom key bindings. Refer to the man page' },
    { '--cycle',                        'Enable cyclic scroll' },
    { '--keep-right',                   'Keep the right end of the line visible on overflow' },
    { '--scroll-off='..scrolloff, 'LINES', 'Number of screen lines to keep above or below when scrolling to the top or to the bottom (default: 0)' },
    { '--no-hscroll',                   'Disable horizontal scroll' },
    { '--hscroll-off='..hscrolloff, 'COLS', 'Number of screen columns to keep to the right of the highlighted substring (default: 10)' },
    { '--filepath-word',                'Make word-wise movements respect path separators' },
    { '--jump-labels='..jumplabels, 'CHARS', 'Label characters for jump and jump-accept' },

    -- Layout options
    { '--height='..heights, 'HEIGHT[%]', 'Display fzf window below the cursor with the given height instead of using fullscreen' },
    { '--min-height='..minheight, 'HEIGHT', 'Minimum height when --height is given in percent (default: 10)' },
    { '--layout='..layout, 'LAYOUT',    'Choose layout' },
    { '--reverse',                      'A synonym for --layout=reverse' },
    { '--border',                       'Draw border around the finder (default: rounded)' },
    { '--border='..borderstyle, 'STYLE', 'Draw border around the finder (default: rounded)', opteq=false },
    { '--margin='..margin, 'MARGIN',    'Screen margin (TRBL | TB,RL | T,RL,B | T,R,B,L)' },
    { '--padding='..padding, 'PADDING', 'Padding inside border (TRBL | TB,RL | T,RL,B | T,R,B,L)' },
    { '--info='..infostyle, 'STYLE',    'Finder info style' },
    { '--no-info',                      'Hide the finder info (synonym for --info=hidden)' },
    { '--prompt='..prompt, 'STR',       "Input prompt (default: '> ')" },
    { '--pointer='..pointer, 'STR',     "Pointer to the current line (default: '>')" },
    { '--marker='..marker, 'STR',       "Multi-select marker (default: '>')" },
    { '--header='..header, 'STR',       "String to print as header" },
    { '--header-lines='..headerlines, 'N', 'The first N lines of the input are treated as header' },
    { '--header-first',                 'Print header before the prompt line' },
    { '--ellipsis='..ellipsis, 'STR',   "Ellipsis to show when line is truncated (default: '..')" },

    -- Display options
    { '--ansi',                         'Enable processing of ANSI color codes' },
    { '--tabstop='..tabstop, 'SPACES',  'Number of spaces for a tab character (default: 8)' },
    { '--color='..colspec, 'COLSPEC',   'Base scheme (dark|light|16|bw) and/or custom colors' },
    { '--no-bold',                      'Do not use bold text' },
    { '--no-unicode',                   'Use ASCII characters instead of Unicode box drawing characters to draw border' },
    { '--black',                        'Use black background' },

    -- History options
    { '--history=', 'FILE',             'History file' },
    { '--history-size='..historysize, 'N', 'Maximum number of history entries (default: 1000)' },

    -- Preview options
    { '--preview='..previewcommand, 'COMMAND', 'Command to preview highlighted line ({})' },
    { '--preview-window='..previewopt, 'OPTS', 'Preview window layout (default: right,50%)' },

    -- Scripting options
    { '-q'..query, ' STR',              'Start the finder with the given query' },
    { '--query='..query, 'STR',         'Start the finder with the given query' },
    { '-1',                             'Automatically select the only match' },
    { '--select-1',                     'Automatically select the only match' },
    { '-0',                             'Exit immediately when there\'s no match' },
    { '--exit-0',                       'Exit immediately when there\'s no match' },
    { '-f'..filter, ' STR',             'Filter mode. Do not start interactive finder' },
    { '--filter='..filter, 'STR',       'Filter mode. Do not start interactive finder' },
    { '--print-query',                  'Print query as the first line' },
    { '--expect='..expect, 'KEYS',      'Comma-separated list of keys to complete fzf' },
    { '--no-expect',                    'Clear list of keys to complete fzf' },
    { '--read0',                        'Read input delimited by ASCII NUL characters' },
    { '--print0',                       'Print output delimited by ASCII NUL characters' },
    { '--sync',                         'Synchronous search for multi-staged filtering' },
    { '--version',                      'Display version information and exit' },
})

