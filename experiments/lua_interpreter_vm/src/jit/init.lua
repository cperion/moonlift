-- Moonlift Lua VM JIT product surface.
--
-- This init intentionally exposes only explicit products/constants and the
-- empirical miner contracts.  It does not expose a Lua planner, Lua native
-- runner, or benchmark harness as JIT implementation.

return {
    products = require("experiments.lua_interpreter_vm.src.jit.products"),
    constants = require("experiments.lua_interpreter_vm.src.jit.constants"),
    funcs = require("experiments.lua_interpreter_vm.src.jit.funcs"),
    regions = require("experiments.lua_interpreter_vm.src.jit.regions"),
    machines = require("experiments.lua_interpreter_vm.src.jit.machines"),
    library_builder = require("experiments.lua_interpreter_vm.src.jit.library_builder"),
    miner_contracts = require("experiments.lua_interpreter_vm.src.jit.miner_contracts"),
}
