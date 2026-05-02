-- Loader shim only.  The PVM-LL implementation lives in pvm_ll.mlua.
local Host = require("moonlift.host_quote")

local mlua_path
if package.searchpath then
    local mlua_package_path = package.path:gsub("%?%.lua", "?%.mlua")
    mlua_path = package.searchpath("moonlift.pvm_ll", mlua_package_path)
end
mlua_path = mlua_path or "lua/moonlift/pvm_ll.mlua"

return Host.dofile(mlua_path)
