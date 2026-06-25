-- Lua Interpreter VM — explicit GC/weak/finalizer classification protocols.

local lalin = require("lalin")
local host = require("lalin.host")
local const = require("experiments.lua_interpreter_vm.src.constants")

local I = {}
for k, v in pairs(const.TableFlag) do I["TABLE_" .. k] = lalin.int(v) end
for k, v in pairs(const.FinalizerState) do I["FINALIZER_" .. k] = lalin.int(v) end

local decode_weak_mode = host.region(I) [[
region decode_weak_mode(mode_flags: u8;
                        none | weak_values | weak_keys |
                        ephemeron | all_weak | invalid)
entry start()
    if mode_flags == 0 then jump none() end
    if as(bool, mode_flags & @{TABLE_ALL_WEAK}) then jump all_weak() end
    if as(bool, mode_flags & @{TABLE_EPHEMERON}) then jump ephemeron() end
    if as(bool, mode_flags & @{TABLE_WEAK_KEYS}) then jump weak_keys() end
    if as(bool, mode_flags & @{TABLE_WEAK_VALUES}) then jump weak_values() end
    jump invalid()
end
end
]]

local classify_finalizer_state = host.region(I) [[
region classify_finalizer_state(state: u8;
                                none | eligible | pending |
                                running | done | invalid)
entry start()
    switch state do
    case 0 then jump none()
    case 1 then jump eligible()
    case 2 then jump pending()
    case 3 then jump running()
    case 4 then jump done()
    default then jump invalid()
    end
end
end
]]

return {
    decode_weak_mode = decode_weak_mode,
    classify_finalizer_state = classify_finalizer_state,
}
