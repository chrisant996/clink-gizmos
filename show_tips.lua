--------------------------------------------------------------------------------
settings.add('tips.enable', true, 'Show a tip when Clink starts',
    'When true, a random tip is printed when Clink starts.')

if not settings.get('tips.enable') then
    return
end

--------------------------------------------------------------------------------
-- A script can register to add its own tips.
-- See modules/external_tips.lua for details.
local external_tips = require("external_tips")

--------------------------------------------------------------------------------
local function rl_testvar(name, test)
    if rl.getvariable then
        local value = rl.getvariable(name)
        if value then
            return (test == value)
        end
    end
end

--------------------------------------------------------------------------------
local function open_seen_tips_file(mode, deny)
    if not io.sopen then
        return
    end

    local profile_dir = os.getenv("=clink.profile")
    if not profile_dir or profile_dir == "" then
        return
    end

    local name = path.join(profile_dir, ".seen_tips")
    if not name then
        return
    end

    -- Retry opening the file until there is no sharing violation.
    -- Try for up to 2 seconds, and then give up.
    local f
    local start_clock = os.clock()
    repeat
        f = io.sopen(name, mode, deny)
    until f or os.clock() - start_clock > 2

    return f
end

local function clear_seen_file()
    local f = open_seen_tips_file("w+", "rw")
    if f then
        f:close()
    end
    return {}
end

local function load_seen_tips()
    local seen = {}
    -- Opening for "w" then "r" ensures the file exists before trying to read
    -- it, otherwise it will retry for 2 seconds when the file doesn't exist.
    local f = open_seen_tips_file("w", "w")
    if f then
        f:close()
        f = open_seen_tips_file("r", "w")
        for line in f:lines() do
            seen[line] = true
        end
        f:close()
    end
    return seen
end

local function add_seen_tip(id)
    local f = open_seen_tips_file("a", "rw")
    if f then
        f:write(id.."\n")
        f:close()
    end
end

--------------------------------------------------------------------------------
-- luacheck: no max line length
local function collect_tips(external, seen)
    local tips = {early={}}
    local any_seen

    local function insert_tip(id, condition, tip)
        if seen[id] then
            any_seen = true
        else
            if condition then
                tip.id = id
                tips[id] = tip
                table.insert(tips, id)
                if tip.early then
                    table.insert(tips.early, id)
                end
            else
                add_seen_tip(id)
            end
        end
    end

    -- REVIEW: Tips about concepts?
    -- TODO: Killing and Yanking.
    -- TODO: Numeric Arguments.
    -- TODO: Readline Init File (config variables and key bindings).

    -- Collect key bindings.
    local bindings = rl.getkeybindings()
    if bindings and #bindings > 0 then
        local early_commands = {
        ["reverse-search-history"] = true,
        ["history-search-backward"] = true,
        ["yank-last-arg"] = true,
        ["operate-and-get-next"] = true,
        ["clink-select-complete"] = true,
        ["undo"] = true,
        ["add-history"] = true,
        ["remove-history"] = true,
        ["clink-expand-line"] = true,
        ["clink-popup-history"] = true,
        ["clink-show-help"] = true,
        ["clink-what-is"] = true,
        ["clink-up-directory"] = true,
        ["cua-backward-char"] = true,
        ["cua-forward-char"] = true,
        ["cua-beg-of-line"] = true,
        ["cua-end-of-line"] = true,
        }
        for _, b in ipairs(bindings) do
            if b.key and b.binding and b.desc and b.desc ~= "" then
                local k = b.key:gsub(" +$", "")
                local id = "key:"..k..":"..b.binding
                if seen[id] then
                    any_seen = true
                else
                    if early_commands[b.binding] then
                        b.early = true
                    end
                    tips[id] = b
                    table.insert(tips, id)
                end
            end
        end
    end

    -- Collect other kinds of tips.
    insert_tip("set:colored-stats", rl_testvar("colored-stats", "off") and rl_testvar("colored-completion-prefix", "off"),
               {early=true, text="Completions can be displayed with color by setting 'colored-stats' in the .inputrc init file.\nSee https://chrisant996.github.io/clink/clink.html#init-file for more info."})
    insert_tip("set:clink.colorize_input", not settings.get("clink.colorize_input"),
               {early=true, text="The input line can be colorized by running 'clink set clink.colorize_input true'.\nSee https://chrisant996.github.io/clink/clink.html#classifywords for more info."})
    insert_tip("set:customized_prompt", true,
               {early=true, text="You can customize the prompt by downloading or writing your own Lua scripts.\nSee https://chrisant996.github.io/clink/clink.html#gettingstarted_customprompt for more info."})
    insert_tip("set:history.time_stamp", not settings.get("history.time_stamp"),
               {text="The saved command history can include time stamps by running 'clink set history.time_stamp true'.\nSee https://chrisant996.github.io/clink/clink.html#history-timestamps for more info."})
    insert_tip("set:history.dupe_mode", true,
               {text="The 'history.dupe_mode' setting controls how duplicate entries are saved in the command history.\nSee https://chrisant996.github.io/clink/clink.html#history_dupe_mode for more info."})
    -- TODO: history expansion.
    -- TODO: history.shared setting.
    -- TODO: match.wild setting.

    -- REVIEW: Not sure how/when/whether to present these tips:
    -- TODO: autosuggest feature.
    -- TODO: startup cmd script.
    -- TODO: clink.auto_answer setting.
    -- TODO: match.sort_dirs setting.
    -- TODO: terminal.differentiate_keys setting.
    -- TODO: clink.logo setting.
    -- TODO: exec.enabled and related settings.
    -- TODO: doskey.enhanced setting.
    -- TODO: autoupdate settings and etc?

    -- Some tips have prerequisites.
    if rl_testvar("colored-stats", "on") then
        insert_tip("set:LS_COLORS", not os.getenv("LS_COLORS"),
                   {early=true, text="Completion colors can be customized by setting the LS_COLORS environment variable.\nSee https://chrisant996.github.io/clink/clink.html#completioncolors for more info."})
    end

    -- Allow external tips.
    if external then
        for _, t in ipairs(external) do
            if t.id and t.text then
                insert_tip(t.id, (t.condition == nil or t.condition), {
                    early = t.early,
                    text = t.text,
                    category = t.category,
                })
            end
        end
    end

    return tips, any_seen
end

--------------------------------------------------------------------------------
local function print_with_wrap(text)
    if unicode.iter then
        local width = console.getwidth() - 1
        local columns = 0
        local line = ""
        local word = ""
        local non_spaces = false

        local function flush_line()
            if columns > 0 then
                clink.print(line)
                columns = 0
                line = ""
            end
        end

        local function print_word()
            local len = console.cellcount(word)
            if len > 0 then
                if columns > 0 and columns + len >= width then
                    flush_line()
                    word = word:gsub("^ +", "")
                    len = console.cellcount(word)
                end
                columns = columns + len
                line = line..word
                word = ""
                non_spaces = false
            end
        end

        for s in unicode.iter(text) do
            if s == "\n" then
                print_word()
                flush_line()
            elseif s == " " then
                if non_spaces then
                    print_word()
                end
                word = word..s
            else
                word = word..s
                non_spaces = true
            end
        end
        print_word()
        flush_line()
    else
        clink.print(text)
    end
end

local function default_print_tip(tip, wrap, off)
    local bold = "\x1b[1m"
    local cyan = "\x1b[36m"
    local gray = "\x1b[30;1m"
    local norm = "\x1b[m"

    local function embolden(text)
        return bold..text..norm
    end

    local heading = cyan..tip.category.." tip:"..norm
    local message
    if tip.key then
        message = string.format("%s : %s -- %s", embolden(tip.key), embolden(tip.binding), tip.desc)
    elseif tip.text then
        message = tip.text
    else
        error("Unexpected tip type for id '"..(tip.id or "<unknown>").."'.")
    end
    off = gray..off..norm

    -- Show the selected tip.
    clink.print(heading)
    wrap(message)
    clink.print("")
    clink.print(off)
end

local function print_tip(tip, wrap_func, off_message, default_func)
    clink.print("")
    default_func(tip, wrap_func, off_message)
    clink.print("")
end

local function show_tip()
    -- Collect available tips that haven't been seen yet.
    local seen = load_seen_tips()
    local external = external_tips.collect()
    local tips, any_seen = collect_tips(external, seen)
    if not tips[1] and any_seen then
        -- Reset the seen file if all tips have been seen.
        clear_seen_file()
        tips = collect_tips(external, {})
    end
    if not tips[1] then
        return
    end

    -- Select at random whether to use an "early" tip.
    math.randomseed(os.time())
    local source = tips
    local chance_for_early = 1/4
    if #tips.early > 0 and math.random() >= (1 - chance_for_early) then
        source = tips.early
    end

    -- Select a tip at random.
    local index = math.random(#source)
    local id = source[index]
    local tip = tips[id]
    if not tip then
        return
    end

    -- Prepare the selected tip.
    local out = {}
    for k, v in pairs(tip) do
        out[k] = v
    end
    if tip.key then
        out.key = tip.key:gsub(" +$", "")
        out.desc = tip.desc:gsub("([^.])$", "%1.")
        out.category = "Key binding"
    elseif tip.text then
        local cat = tip.category or "configuration"
        out.category = cat:sub(1, 1):upper()..cat:sub(2)
    else
        error("Unexpected tip type for id '"..id.."'.")
    end

    -- Show the selected tip.
    local print_func = external_tips.print or print_tip
    local off = "You can turn off these tips by running 'clink set tips.enable false'."
    print_func(out, print_with_wrap, off, default_print_tip)

    -- Mark that the tip has been seen.
    add_seen_tip(id)
end

--------------------------------------------------------------------------------
if rl and rl.getkeybindings and clink.oninject then
    clink.oninject(show_tip)
end
