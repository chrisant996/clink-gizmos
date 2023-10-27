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
-- A script can also replace the tip printer:
--
--      local external_tips = require("external_tips")
--
--      local use_custom_printer = true
--
--      local function print_tip(tip, print_with_wrap, off_message, default_print_tip)
--          local blue = "\x1b[34m"
--          local norm = "\x1b[m"
--          local divider = blue..string.rep("-", console.getwidth() - 1)..norm
--
--          print("")
--          print(divider)
--
--          if use_custom_printer then
--              print(tip.category.." tip:")
--              if tip.key then
--                  print_with_wrap(string.format("%s : %s -- %s", tip.key, tip.binding, tip.desc))
--              elseif tip.text then
--                  print_with_wrap(tip.text)
--              else
--                  error("Unexpected tip type for id '"..tip.id.."'.")
--              end
--              print("")
--              print(off_message)
--          else
--              default_print_tip(tip, print_with_wrap, off_message)
--          end
--
--          print(divider)
--          print("")
--      end
--
--      external_tips.print = print_tip

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
local function clear_callbacks()
    -- Allow garbage collection of anything that was registered.
    callbacks = nil
end

--------------------------------------------------------------------------------
if clink.onbeginedit then
    clink.onbeginedit(clear_callbacks)
end

--------------------------------------------------------------------------------
return {
    -- For public use.
    register = register_show_tips,
    print = nil,

    -- For internal use.
    collect = collect_external_tips,
    clear = clear_external_tips,
}
