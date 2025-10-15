-- The line below extends package.path with modules
-- directory to allow to require them
package.path = debug.getinfo(1, "S").source:match[[^@?(.*[\/])[^\/]-$]] .."modules/?.lua;".. package.path

-- Load matchicons_module.lua early, if present, to ensure all clink-gizmos
-- scripts gain match icons when appropriate.
local function try_require(module)
    local r
    pcall(function() r = require(module) end)
    return r
end
try_require("matchicons_module")
