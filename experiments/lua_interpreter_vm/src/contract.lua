-- Machine-readable VM contract summary.
-- Plain Lua only: no Moonlift fragments and no VM module imports.

return {
    vm_abi_version = 1,
    native_abi_version = 1,
    validator_contract_version = 1,
    sponjit_allowed = false,
    required_gates = {
        "bytecode_validator_complete",
        "frame_cache_reload_on_switch",
        "explicit_call_result_base",
        "unified_error_unwind",
        "explicit_native_abi",
        "explicit_allocator_boundary",
    },
}
