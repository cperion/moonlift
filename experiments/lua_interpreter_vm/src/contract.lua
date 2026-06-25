-- Machine-readable VM contract summary.
-- Plain Lua only: no Lalin fragments and no VM module imports.

return {
    vm_abi_version = 2,
    native_abi_version = 2,
    validator_contract_version = 2,
    sponjit_allowed = false,
    required_gates = {
        "lua55_tm_order",
        "bytecode_validator_complete",
        "binary_chunk_loader_complete",
        "source_compiler_complete",
        "frame_cache_reload_on_all_switches",
        "native_return_converges_with_lua_return",
        "unified_error_value_unwind",
        "explicit_coroutine_transfer",
        "gc_finalizer_weak_table_protocols",
    },
}
