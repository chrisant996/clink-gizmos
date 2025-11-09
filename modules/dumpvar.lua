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
-- Optionally, you can configure dumpvar:
--
--      local dv = require("dumpvar")
--
--      dv.show_type = true             -- Whether to show type names.
--      dv.sort_tables = true           -- Whether to sort named records in tables.
--      dv.type_colors = "..."          -- String of colors:  "typename1=sgr_code typename2=sgr_code ...etc"
--      dv.init = function()            -- Function to be run every time dumpvar() is called.
--          dv.show_type = true
--          dv.type_colors = "..."
--      end
--
--  Note:   If you configure dumpvar, consider using a wrapper function to
--          save/restore pre-existing configuration, to avoid interfering with
--          other scripts that may also be using dumpvar as well.
--
-- Or, you can provide options directly:
--
--      require("dumpvar")
--
--      local options = {
--          type_colors = "..."         -- Or set it to false (not nil) to disable colors.
--          write = function(text)      -- Function to write text (do not add newline).
--              clink.print(text, NONL)
--          end
--      }
--
--      dumpvarex(options, ...)         -- The ... represents the same arguments dumpvar() accepts.

local exports = {}

local default_colors = "string=38;5;172 table=38;5;40 boolean=38;5;39 number=38;5;141 function=38;5;27 thread=38;5;203 types=38;5;244 nil=38;5;196" -- luacheck: no max line length

local show_type
local sort_tables
local type_colors = {}
local write

local function sgr(code)
    return "\x1b["..(code or "").."m"
end

local function format_var_name(var_name, var_type)
    local c = type_colors[var_type] or type_colors.reset
    local out = c..tostring(var_name)

    if show_type then
        out = out..(type_colors["type"] or type_colors.reset).." ("..var_type..")"
    end

    out = out..type_colors.reset
    return out
end

local function comparator(a, b)
    return tostring(a) < tostring(b)
end

local function printtext(text)
    clink.print(text, NONL) -- luacheck: globals NONL
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
            write(string.format("%s%s = { %s\n", indent, format_var_name(name, t), tostring(value)))
        else
            write(string.format("%s{ %s\n", indent, tostring(value)))
        end
        local next_indent = indent.."  "
        depth = depth - 1
        if sort_tables then
            local keys = {}
            for n,v in pairs(value) do
                if v ~= _G then
                    if type(n) == "number" then
                        dumpvar_internal(v, depth, n, next_indent, ",")
                    else
                        table.insert(keys, n)
                    end
                end
            end
            table.sort(keys, comparator)
            for _,n in ipairs(keys) do
                local v = value[n]
                if v ~= _G then
                    dumpvar_internal(v, depth, n, next_indent, ",")
                end
            end
        else
            for n,v in pairs(value) do
                if v ~= _G then
                    dumpvar_internal(v, depth, n, next_indent, ",")
                end
            end
        end
        write(string.format("%s}%s\n", indent, comma))
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

    if name then write(string.format("%s%s = ", indent, format_var_name(name, t))) end -- luacheck: globals NONL
    write(string.format("%s%s\n", value, comma))
end

local function iif(expr, if_true, if_false)
    if expr then
        return if_true
    else
        return if_false
    end
end

-- luacheck: globals dumpvarex
function dumpvarex(options, value, depth, name, indent, comma)
    do
        show_type = iif(options.show_type == nil, true, options.show_type)
        sort_tables = iif(options.sort_tables == nil, true, options.sort_tables)

        local colors = iif(options.type_colors == false, nil, options.type_colors or default_colors)
        type_colors = {}
        if colors == nil then
            type_colors.reset = ""
        else
            local types = string.explode(colors, ", ")
            for _,v in ipairs(types) do
                local c = string.explode(v, "=")
                if c[1] then
                    if c[2] then
                    type_colors[c[1]] = sgr(";"..c[2])
                    else
                        type_colors[c[1]] = sgr()
                    end
                end
            end
            type_colors.reset = sgr()
        end

        write = options.write or printtext
    end

    dumpvar_internal(value, depth, name, indent, comma)
end

-- luacheck: globals dumpvar
function dumpvar(value, depth, name, indent, comma)
    if exports.init then
        exports.init()
    end

    dumpvarex(exports, value, depth, name, indent, comma)
end

exports.init = function() end
exports.show_type = true
exports.sort_tables = true
exports.type_colors = default_colors
exports.write = printtext

return exports
