-- Lua Interpreter VM — explicit compatibility frontiers.

local const = require("experiments.lua_interpreter_vm.src.constants")
local validate = require("experiments.lua_interpreter_vm.src.validate")
local compiler = require("experiments.lua_interpreter_vm.src.regions_compiler")
local native = require("experiments.lua_interpreter_vm.src.regions_native")
local chunk = require("experiments.lua_interpreter_vm.src.regions_chunk")

return {
    formats = const.CompatFormat,
    internal_proto_validator = validate.validate_proto,
    source_frontier = compiler.compile_lua_source_into,
    binary_chunk_frontier = chunk.load_lua55_binary_chunk,
    native_abi_frontier = native.decode_native_result,
    puc_oracle_only = true,
}
