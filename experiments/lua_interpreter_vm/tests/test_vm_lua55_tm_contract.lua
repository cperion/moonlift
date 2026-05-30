-- Lua 5.5 tag-method order contract for the Moonlift VM.
-- PUC Lua is used as semantic/oracle documentation only; these constants are
-- Moonlift VM ABI discriminants consumed by bytecode and metamethod lookup.

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local vm = require("experiments.lua_interpreter_vm.src.init")
local TM = vm.const.TM

local order = {
    "INDEX", "NEWINDEX", "GC", "MODE", "LEN", "EQ",
    "ADD", "SUB", "MUL", "MOD", "POW", "DIV", "IDIV",
    "BAND", "BOR", "BXOR", "SHL", "SHR", "UNM", "BNOT",
    "LT", "LE", "CONCAT", "CALL", "CLOSE",
}

for i, name in ipairs(order) do
    assert(TM[name] == i - 1, string.format("TM.%s = %s, expected %d", name, tostring(TM[name]), i - 1))
end
assert(TM.N == #order, string.format("TM.N = %s, expected %d", tostring(TM.N), #order))

assert(vm.const.TypeMeta.STRING == 4, "primitive type-metatable discriminants are exported")
assert(vm.const.Abi.VALIDATOR_VERSION == 2, "validator ABI bumped for paired-op/event contract")

print("PASS Lua 5.5 TM contract")
return true
