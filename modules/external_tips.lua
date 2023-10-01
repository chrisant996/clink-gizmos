--------------------------------------------------------------------------------
-- A script can add its own custom tips to be shown by show_tips.lua:
--
--      local external_tips = require("external_tips")
--
--      local function my_tips()
--          return {
--              { id="fun", text="Have fun." },
--              { id="gold", text="Dig at the end of the rainbow.", category="secret" },
--          }
--      end
--
--      external_tips.register(my_tips)
--
-- A tip must contain:
--
--      id          = A unique string, to tell whether the tip has been shown.
--      text        = The tip text.  This can contain ANSI escape codes.
--
-- A tip may also contain:
--
--      category    = A category name.  If none is given, "Custom" is assumed.
--      early       = When true, the tip is prioritized to be shown earlier than
--                    most other tips.

--------------------------------------------------------------------------------
local callbacks = {}

--------------------------------------------------------------------------------
local function register_show_tips(func)
    if callbacks and not callbacks[func] then
        table.insert(callbacks, func)
        callbacks[func] = true
    end
end

--------------------------------------------------------------------------------
local function collect_external_tips()
    local external = {}
    if callbacks then
        for _, func in ipairs(callbacks) do
            local tips = func()
            if type(tips) == "table" then
                for _, t in ipairs(tips) do
                    if type(t) == "table" and t.id and t.text then
                        local cat = t.category
                        if type(cat) ~= "string" or cat:gsub(" +$", "") == "" then
                            cat = "custom"
                        end
                        table.insert(external, {
                            id = "ext:"..t.id,
                            text = t.text,
                            early = t.early,
                            category = cat,
                        })
                    end
                end
            end
        end
    end
    return external
end

--------------------------------------------------------------------------------
local function clear_external_tips()
    callbacks = nil -- Allow garbage collection of anything that was registered.
end

--------------------------------------------------------------------------------
return {
    register = register_show_tips,
    collect = collect_external_tips,
    clear = clear_external_tips,
}
