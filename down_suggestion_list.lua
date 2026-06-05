-- This script can replace the DOWN key binding to also show the suggestion list
-- if a suggestion is available, otherwise navigate forward through history.
--
-- When the down_suggestion_list.autobind setting is 'always', or is 'auto' (the
-- default) and the suggestionlist.autooff setting is true, then the script
-- checks the current DOWN key binding:  If it's bound to either next-history or
-- history-search-forward then the DOWN arrow binding is updated:
--
--  - next-history --> suggestion_list_or_next_history
--  - history-search-forward --> suggestion_list_or_history_search_forward
--
-- If a suggestion is available then DOWN shows the suggestion list, otherwise
-- it invokes the next-history or history-search-forward (which was
-- originally bound to DOWN).

if (clink.version_encoded or 0) < 10080000 then
    log.info("down_suggestion_list.lua requires a newer version of Clink; please upgrade.")
    return
end

settings.add("down_suggestion_list.autobind", { "auto", "off", "always" },
"Augment DOWN key per suggetionlist.autooff",
[[When this is 'always', or when this is 'auto' and the suggestionlist.autooff
setting is also true, then the default DOWN key binding may be overridden:
If DOWN is bound to 'next-history' or 'history-search-forward', then it will be
augmented to first show the suggestion list if any suggestion is available.
Changing this setting doesn't take effect until the next Clink session.]])

-- luacheck: push
-- luacheck: no max line length
rl.describemacro([["luafunc:suggestion_list_or_next_history"]], "Show suggestion list or invoke 'next-history'")
rl.describemacro([["luafunc:suggestion_list_or_history_search_forward"]], "Show suggestion list or invoke 'history-search-forward'")
-- luacheck: pop

local function suggestion_list_else(fallback, rl_buffer)
    if rl_buffer:hassuggestion() then
        rl.invokecommand("clink-toggle-suggestion-list")
    else
        rl.invokecommand(fallback)
    end
end

-- luacheck: globals suggestion_list_or_next_history
function suggestion_list_or_next_history(rl_buffer, line_state) -- luacheck: no unused
    suggestion_list_else("next-history", rl_buffer)
end

-- luacheck: globals suggestion_list_or_history_search_forward
function suggestion_list_or_history_search_forward(rl_buffer, line_state) -- luacheck: no unused
    suggestion_list_else("history-search-forward", rl_buffer)
end

local autobind = settings.get("down_suggestion_list.autobind")
if autobind == "always" or (autobind == "auto" and settings.get("suggestionlist.autooff")) then
    -- Get binding for DOWN.
    local bfunc, btype = rl.getbinding([["\e[B"]])
    if btype == "function" then
        -- Override certain commands with augmented versions.
        if bfunc == "next-history" then
            rl.setbinding([["\e[B"]], [["luafunc:suggestion_list_or_next_history"]])
        elseif bfunc == "history-search-forward" then
            rl.setbinding([["\e[B"]], [["luafunc:suggestion_list_or_history_search_forward"]])
        end
    end
end
