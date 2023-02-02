--------------------------------------------------------------------------------
-- This script can automatically switch to different history files based on the
-- current directory.  For example, you can configure it to use one history file
-- when in one git repo, another history file in another git repo, and yet
-- another history file in some other directory.

-- Set this in a Lua script to contain a list of pairs of directories and
-- history label qualifiers.  When the current directory is within a listed
-- directory, then the script sets CLINK_HISTORY_LABEL to the associated history
-- label string.  When the current directory is not within any listed directory,
-- then the script clears the CLINK_HISTORY_LABEL environment variable (but only
-- if the script has previously set it).

history_label_dirs = history_label_dirs or {}

-- Example:
--      history_label_dirs = {
--          { "c:/repos/clink", "Clink Repo" },
--          { "c:/repos/workcode", "Work Repo" },
--      }

if not unicode.normalize then
    log.info("history_labels.lua requires a newer version of Clink; please upgrade.")
    return
end

local using_label

local function select_label()
    -- Get the current directory.
    local cwd = unicode.normalize(3, string.lower(path.join(os.getcwd(), "")))

    -- Find a label associated with the current directory.
    local label
    for _,x in ipairs(history_label_dirs) do
        local candidate = unicode.normalize(3, string.lower(path.join(path.normalise(x[1]), "")))
        if cwd:find(candidate, 1, true--[[plain]]) == 1 then
            label = x[2]
            break
        end
    end

    -- If no label and we haven't set a label, then there's nothing to do.
    if not label and not using_label then
        return
    end

    -- Apply the label.  If there's no label, this reverts to the profile's
    -- history file.
    using_label = label
    os.setenv("CLINK_HISTORY_LABEL", label)
end

clink.onbeginedit(select_label)
