--------------------------------------------------------------------------------
-- This script adds a new setting that skips adding lines to history unless they
-- meet a minimum specified length.  By default the minimum length is 0, meaning
-- all lines meet the minimum length.

if not clink.onhistory then
    log.info("filter_short_history.lua requires a newer version of Clink; please upgrade.")
    return
end

settings.add("history.minimum_length", 0,
    "Skip adding lines shorter than this",
    "The minimum length of a line that will be added to the history.  Any line\n"..
    "shorter than this value will not be added to the history.")

local function filter_short_history(line)
    local minlen = settings.get("history.minimum_length") or 0
    if #line < minlen then
        return false
    end
end

clink.onhistory(filter_short_history)
