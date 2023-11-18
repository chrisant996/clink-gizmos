--------------------------------------------------------------------------------
-- Usage:
--
--      require("dumpvar")
--
--      local variable = {
--          abc = true,
--          def = "hello world",
--          ghi = 3.14,
--          jkl = 42,
--          mno = {
--              nested = true,
--          },
--      }
--
--      dumpvar(variable)               -- Prints content of variable.
--      dumpvar(variable, 3)            -- Prints content of variable, recursing to 3 levels of tables.
--
-- Optionally, you can configuration dumpvar:
--
--      local dv = require("dumpvar")
--
--      dv.show_type = true             -- Whether to show type names.
--      dv.type_colors = "..."          -- String of colors:  "typename1=sgr_code typename2=sgr_code ...etc"
--      dv.init = function()            -- Function to be run every time dumpvar() is called.
--          dv.show_type = true
--          dv.type_colors = "..."
--      end

local exports = {}

local default_colors = "string=38;5;172 table=38;5;40 boolean=38;5;39 number=38;5;141 function=38;5;27 thread=38;5;203 types=38;5;244 nil=38;5;196" -- luacheck: no max line length

local norm = "\x1b[m"
local type_colors = {}

local function sgr(code)
    return "\x1b["..(code or "").."m"
end

local function format_var_name(var_name, var_type)
    local c = type_colors[var_type] or norm
    local out = c..tostring(var_name)

    if exports.show_type then
        out = out..(type_colors["type"] or norm).." ("..var_type..")"
    end

    out = out..sgr()
    return out
end

local function dumpvar_internal(value, depth, name, indent, comma)
    if type(depth) == "string" and not name and not indent and not comma then
        name = depth
        depth = 1
    end

    if type(depth) ~= "number" then
        depth = 1
    elseif depth < 0 then
        depth = 0
    else
        depth = math.floor(depth)
    end

    indent = indent or ""
    comma = comma or ""

    local t = type(value)
    if t == "table" and depth > 0 then
        if name then
            clink.print(indent..format_var_name(name, t).." = { "..tostring(value))
        else
            clink.print(indent.."{ "..tostring(value))
        end
        local next_indent = indent.."  "
        depth = depth - 1
        for n,v in pairs(value) do
            if v ~= _G then
                dumpvar_internal(v, depth, n, next_indent, ",")
            end
        end
        clink.print(indent.."}"..comma)
        return
    end

    if value == nil then
        value = "nil"
    else
        if t == "boolean" then
            value = value and "true" or "false"
        elseif t == "string" then
            value = string.format("%q", value)
        else
            value = tostring(value)
        end
    end

    if name then clink.print(indent..format_var_name(name, t).." = ", NONL) end -- luacheck: globals NONL
    clink.print(value..comma)
end

-- luacheck: globals dumpvar
function dumpvar(value, depth, name, indent, comma)
    do
        if exports.init then
            exports.init()
        end

        local colors = exports.type_colors or default_colors
        local types = string.explode(colors, ", ")
        for _,v in ipairs(types) do
            local c = string.explode(v, "=")
            type_colors[c[1]] = sgr(";"..c[2])
        end
    end

    dumpvar_internal(value, depth, name, indent, comma)
end

exports.init = function() end
exports.show_type = true
exports.type_colors = default_colors

return exports
