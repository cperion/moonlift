local Host = require("moonlift.mlua_run")

local mlua_path
if package.searchpath then
    local mlua_package_path = package.path:gsub("%?%.lua", "?%.mlua")
    mlua_path = package.searchpath("moonlift.asdl_pvm_ll", mlua_package_path)
end
mlua_path = mlua_path or "lua/moonlift/asdl_pvm_ll.mlua"

local cache = setmetatable({}, { __mode = "k" })
local standalone

local function impl()
    local runtime = Host.current_runtime and Host.current_runtime() or nil
    if runtime ~= nil then
        local mod = cache[runtime]
        if mod == nil then
            mod = Host.dofile(mlua_path, { runtime = runtime })
            cache[runtime] = mod
        end
        return mod
    end
    if standalone == nil then standalone = Host.dofile(mlua_path) end
    return standalone
end

return setmetatable({}, {
    __index = function(_, key) return impl()[key] end,
})
