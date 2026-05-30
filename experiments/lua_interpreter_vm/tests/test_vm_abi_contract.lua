-- VM ABI contract module/API tests.

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local moon = require("moonlift")
local vm = require("experiments.lua_interpreter_vm.src.init")
local const = vm.const

assert(vm.contract.vm_abi_version == const.Abi.VM_VERSION, "VM ABI version mismatch")
assert(vm.contract.native_abi_version == const.Abi.NATIVE_VERSION, "native ABI version mismatch")
assert(vm.contract.validator_contract_version == const.Abi.VALIDATOR_VERSION, "validator ABI version mismatch")
assert(vm.contract.sponjit_allowed == false, "SponJIT must remain gated")

ffi.cdef [[
typedef struct { void* next; uint8_t tt; uint8_t marked; } GCHeader;
typedef struct { uint32_t tag; uint32_t aux; uint64_t bits; } Value;
typedef struct {
    GCHeader gc; uint8_t status;
    Value* stack; uint64_t stack_size; uint64_t top;
    void* frames; uint64_t frame_count; uint64_t frame_cap;
    void* open_upvals; void* protected_top;
    void* global; Value err_value;
    uint8_t hookmask; uint8_t allowhook;
    int32_t hookcount; int32_t basehookcount; Value hook;
    uint64_t tbc_head;
    int32_t yieldable; int32_t nonyieldable; int32_t last_error_code; uint32_t flags;
} LuaThread;
]]

local abi = moon.func {
    vm_abi = vm.api.lua_vm_abi_version_api,
    native_abi = vm.api.lua_native_abi_version_api,
    status_api = vm.api.lua_status_api,
    last_error_api = vm.api.lua_last_error_api,
    ABI_VM_VERSION = moon.int(const.Abi.VM_VERSION),
    ABI_NATIVE_VERSION = moon.int(const.Abi.NATIVE_VERSION),
} [[
abi_check(L: ptr(LuaThread)) -> i32
    let a: i32 = @{vm_abi}()
    let b: i32 = @{native_abi}()
    let s: i32 = @{status_api}(L)
    let e: i32 = @{last_error_api}(L)
    if a ~= @{ABI_VM_VERSION} then return -1 end
    if b ~= @{ABI_NATIVE_VERSION} then return -2 end
    if s ~= as(i32, L.status) then return -3 end
    if e ~= L.last_error_code then return -4 end
    return 0
end
]]:compile()

local L = ffi.new("LuaThread[1]")
L[0].status = const.Status.OK
L[0].last_error_code = 123
local r = abi(L)
abi:free()
assert(r == 0, "ABI API check failed: " .. tostring(r))
print("PASS VM ABI contract")
return true
