--------------------------------------------------------------------------------
-- Provides a command for showing a list of doskey aliases and their expansions.
--
-- KEY BINDING:
--
--  Each default key binding here is only applied if the key isn't already bound
--  to something else.
--
--  You may also set key bindings manually in your .inputrc file.
--
--[[

# Default key bindings for abbr.
"\C-xd":    "luafunc:doskey_popup"  # CTRL-X,D show doskey aliases and their expansions in a popup list.

]]
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Helper functions.

local function sort_by_name(a, b)
    return string.comparematches(a.value, b.value)
end

--------------------------------------------------------------------------------
-- Commands available for key bindings.

local function add_desc(macro, desc)
    if rl.describemacro then
        rl.describemacro(macro, desc)
    end
end

add_desc("luafunc:doskey_popup", "Show doskey aliases and their expansions in a popup list")

-- luacheck: globals doskey_popup
function doskey_popup(rl_buffer, line_state) -- luacheck: no unused
    local items = {}
    for _,name in pairs(os.getaliases()) do
        local command = os.getalias(name)
        table.insert(items, { value=name, description=command.."\t" })
    end
    table.sort(items, sort_by_name)

    local value = clink.popuplist("Doskey Aliases and Expansions", items)
    if value then
        rl_buffer:beginundogroup()
        rl_buffer:setcursor(1)
        rl_buffer:insert(value.." ")
        rl_buffer:endundogroup()
    end
end

--------------------------------------------------------------------------------
-- Default key bindings.

if rl.getbinding then
    if not rl.getbinding([["\C-Xd"]]) then
        rl.setbinding([["\C-Xd"]], [["luafunc:doskey_popup"]])
    end
end
