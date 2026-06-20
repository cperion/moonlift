-- Typed LuaJIT/Moonlift bridge boundary model.
--
-- This module declares the handles, records, and protocol signatures that make
-- Lua stack effects, registry references, protected calls, and Lua errors
-- explicit Moonlift facts.

local M = {}

M.source = [[
struct LuaStateRecord
    raw: ptr(u8),
    generation: u64,
    owns_state: bool,
end

struct LuaRefRecord
    state: LuaStateRef,
    registry_ref: i32,
    kind_hint: u8,
    generation: u64,
end

struct LuaErrorRecord
    state: LuaStateRef,
    message: LuaRef,
    traceback: LuaRef,
    code: i32,
    generation: u64,
end

struct LuaBridgeStore
    states: ptr(LuaStateRecord),
    refs: ptr(LuaRefRecord),
    errors: ptr(LuaErrorRecord),
    generation: u64,
end

struct Core
    lua_bridge: ptr(LuaBridgeStore),
end

handle LuaStateRef : u32 invalid 0
    target LuaStateRecord
end

handle LuaRef : u32 invalid 0
    target LuaRefRecord
end

handle LuaErrorRef : u32 invalid 0
    target LuaErrorRecord
end

handle OwnedBytesRef : u32 invalid 0 end
handle TypeRef : u32 invalid 0 end
handle ValueRef : u32 invalid 0 end
handle ArgsRef : u32 invalid 0 end
handle FieldOverrideSetRef : u32 invalid 0 end
handle FieldRef : u32 invalid 0 end
handle SymbolRef : u32 invalid 0 end
handle DiagnosticRef : u32 invalid 0 end

union LuaValueKind
    nil_value
  | boolean
  | number
  | string
  | table
  | function
  | userdata
  | thread
  | lightuserdata
  | unknown(code: i32)
end

struct LuaStackMark
    top: i32,
end

struct LuaStackRange
    first: i32,
    count: i32,
end

struct LuaStringBorrow
    data: ptr(u8),
    len: index,
    stack_index: i32,
    mark: LuaStackMark,
end

struct LuaCallFrame
    mark: LuaStackMark,
    fn_index: i32,
    first_arg: i32,
    nargs: i32,
    nresults: i32,
end

region lua_state_adopt(core: ptr(Core), L: ptr(u8);
    adopted(state: LuaStateRef)
  | null_state
  | already_registered(state: LuaStateRef)
  | memory_exhausted(needed: index))
end

region lua_state_validate(core: ptr(Core), state: LuaStateRef;
    valid(record: lease ptr(LuaStateRecord))
  | stale(state: LuaStateRef)
  | missing(state: LuaStateRef))
end

region lua_state_raw(core: ptr(Core), state: LuaStateRef;
    raw(L: ptr(u8))
  | stale(state: LuaStateRef)
  | missing(state: LuaStateRef))
end

region lua_retain_value(core: ptr(Core), state: LuaStateRef, idx: i32;
    retained(ref: owned LuaRef)
  | invalid_index(idx: i32)
  | unsupported_type(actual: LuaValueKind)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef)
  | lua_error(code: i32)
  | memory_exhausted(needed: index))
end

region lua_push_ref(core: ptr(Core), state: LuaStateRef, ref: LuaRef;
    pushed(stack_index: i32)
  | stale(ref: LuaRef)
  | missing(ref: LuaRef)
  | wrong_state(ref: LuaRef, state: LuaStateRef)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef)
  | lua_error(code: i32))
end

region lua_release_ref(core: ptr(Core), state: LuaStateRef, ref: owned LuaRef;
    released
  | stale(ref: owned LuaRef)
  | missing(ref: owned LuaRef)
  | wrong_state(ref: owned LuaRef, state: LuaStateRef)
  | stale_state(ref: owned LuaRef, state: LuaStateRef)
  | missing_state(ref: owned LuaRef, state: LuaStateRef)
  | lua_error(ref: owned LuaRef, code: i32))
end

region lua_stack_mark(core: ptr(Core), state: LuaStateRef;
    mark(mark: LuaStackMark)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef))
end

region lua_stack_restore(core: ptr(Core), state: LuaStateRef, mark: LuaStackMark;
    restored
  | stack_underflow(expected: i32, got: i32)
  | stack_overflow(expected: i32, got: i32)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef))
end

region lua_stack_check(core: ptr(Core), state: LuaStateRef, mark: LuaStackMark;
    balanced
  | changed(expected: i32, got: i32)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef))
end

region lua_read_type(core: ptr(Core), state: LuaStateRef, idx: i32;
    kind(kind: LuaValueKind)
  | invalid_index(idx: i32)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef))
end

region lua_borrow_string(core: ptr(Core), state: LuaStateRef, idx: i32;
    string(s: LuaStringBorrow)
  | wrong_type(actual: LuaValueKind)
  | invalid_index(idx: i32)
  | null_string
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef))
end

region lua_copy_string(core: ptr(Core), state: LuaStateRef, idx: i32;
    bytes(bytes: owned OwnedBytesRef)
  | wrong_type(actual: LuaValueKind)
  | invalid_index(idx: i32)
  | null_string
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef)
  | memory_exhausted(needed: index))
end

region lua_read_bool(core: ptr(Core), state: LuaStateRef, idx: i32;
    value(value: bool)
  | wrong_type(actual: LuaValueKind)
  | invalid_index(idx: i32)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef))
end

region lua_read_number(core: ptr(Core), state: LuaStateRef, idx: i32;
    value(value: f64)
  | wrong_type(actual: LuaValueKind)
  | invalid_index(idx: i32)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef))
end

region lua_value_to_core_value(core: ptr(Core), state: LuaStateRef, idx: i32, expected: TypeRef;
    value(value: ValueRef)
  | wrong_type(expected: TypeRef, actual: LuaValueKind)
  | unsupported_conversion(actual: LuaValueKind)
  | foreign_userdata
  | invalid_index(idx: i32)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef)
  | lua_error(code: i32)
  | memory_exhausted(needed: index))
end

region lua_push_nil(core: ptr(Core), state: LuaStateRef;
    pushed(stack_index: i32)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef)
  | lua_error(code: i32))
end

region lua_push_bool(core: ptr(Core), state: LuaStateRef, value: bool;
    pushed(stack_index: i32)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef)
  | lua_error(code: i32))
end

region lua_push_number(core: ptr(Core), state: LuaStateRef, value: f64;
    pushed(stack_index: i32)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef)
  | lua_error(code: i32))
end

region lua_push_string(core: ptr(Core), state: LuaStateRef, bytes: readonly view(u8);
    pushed(stack_index: i32)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef)
  | lua_error(code: i32)
  | memory_exhausted(needed: index))
end

region core_value_to_lua(core: ptr(Core), state: LuaStateRef, value: ValueRef;
    pushed(stack_index: i32)
  | unsupported_value(kind: u8)
  | invalid_ref
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef)
  | lua_error(code: i32)
  | memory_exhausted(needed: index))
end

region lua_begin_call(core: ptr(Core), state: LuaStateRef, fn: LuaRef;
    frame(frame: LuaCallFrame)
  | stale(ref: LuaRef)
  | missing(ref: LuaRef)
  | wrong_state(ref: LuaRef, state: LuaStateRef)
  | invalid_function(ref: LuaRef)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef)
  | lua_error(code: i32))
end

region lua_push_call_arg(core: ptr(Core), state: LuaStateRef, frame: LuaCallFrame, value: ValueRef;
    pushed(frame: LuaCallFrame)
  | unsupported_value(kind: u8)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef)
  | lua_error(code: i32)
  | memory_exhausted(needed: index))
end

region lua_finish_call(core: ptr(Core), state: LuaStateRef, frame: LuaCallFrame;
    returned(results: LuaStackRange)
  | lua_error(message: owned LuaErrorRef)
  | stack_unbalanced(expected: i32, got: i32)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef)
  | memory_exhausted(needed: index))
end

region lua_call_protected(core: ptr(Core), state: LuaStateRef, fn: LuaRef, args: LuaStackRange, nresults: i32;
    returned(results: LuaStackRange)
  | lua_error(message: owned LuaErrorRef)
  | invalid_function(ref: LuaRef)
  | stack_unbalanced(expected: i32, got: i32)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef)
  | memory_exhausted(needed: index))
end

region capture_lua_error(core: ptr(Core), state: LuaStateRef, err_index: i32;
    error(err: owned LuaErrorRef)
  | invalid_error_object
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef)
  | memory_exhausted(needed: index))
end

region lua_error_to_diagnostic(core: ptr(Core), err: LuaErrorRef;
    diagnostic(diag: DiagnosticRef)
  | stale(err: LuaErrorRef)
  | missing(err: LuaErrorRef))
end

region lua_release_error(core: ptr(Core), err: owned LuaErrorRef;
    released
  | stale(err: owned LuaErrorRef)
  | missing(err: owned LuaErrorRef))
end

region lua_import_args_table(core: ptr(Core), state: LuaStateRef, idx: i32;
    args(args: ArgsRef)
  | wrong_type(actual: LuaValueKind)
  | unsupported_key_type(actual: LuaValueKind)
  | unsupported_value_type(actual: LuaValueKind)
  | too_many_args(n: index)
  | invalid_index(idx: i32)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef)
  | lua_error(code: i32)
  | memory_exhausted(needed: index))
end

region lua_import_field_overrides(core: ptr(Core), state: LuaStateRef, idx: i32, subject: ValueRef;
    overrides(overrides: FieldOverrideSetRef)
  | wrong_type(actual: LuaValueKind)
  | no_such_field(name: SymbolRef)
  | field_type_mismatch(field: FieldRef, expected: TypeRef, got: TypeRef)
  | invalid_index(idx: i32)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef)
  | lua_error(code: i32)
  | memory_exhausted(needed: index))
end

region lua_decode_proxy(core: ptr(Core), state: LuaStateRef, idx: i32, expected_kind: u8;
    proxy(value: ValueRef)
  | wrong_type(actual: LuaValueKind)
  | wrong_proxy_kind(expected: u8, actual: u8)
  | foreign_userdata
  | stale_proxy
  | invalid_index(idx: i32)
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef)
  | lua_error(code: i32))
end

region lua_push_core_proxy(core: ptr(Core), state: LuaStateRef, value: ValueRef;
    pushed(stack_index: i32)
  | unsupported_value(kind: u8)
  | invalid_ref
  | stale_state(state: LuaStateRef)
  | missing_state(state: LuaStateRef)
  | lua_error(code: i32)
  | memory_exhausted(needed: index))
end
]]

local function parse(T)
    local parsed = require("moonlift.parse").Define(T).parse_module(M.source)
    if #parsed.issues ~= 0 then
        error(parsed.issues[1].message or tostring(parsed.issues[1]), 2)
    end
    return parsed.module
end

function M.module(T)
    return parse(T)
end

function M.items(T)
    return parse(T).items
end

function M.protocols(T)
    local P = require("moonlift.parse").Define(T)
    local out = {}
    local source = "\n" .. M.source .. "\n"
    for region_src in source:gmatch("\n(region%s+.-\nend)\n") do
        local parsed = P.parse_region(region_src)
        if #parsed.issues ~= 0 then
            error(parsed.issues[1].message or tostring(parsed.issues[1]), 2)
        end
        out[#out + 1] = parsed.value
    end
    return out
end

function M.install(bundle)
    local items = M.items(bundle.session.T)
    for i = 1, #items do
        bundle.items[#bundle.items + 1] = items[i]
    end
    return bundle
end

return M
