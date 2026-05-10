-- tests/test_luajitvm_skeleton.lua
package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path
-- Verifies that the luajitvm skeleton compiles without errors.
-- Covers tasks 6 (M0 protocols), 7 (skeleton), 8 (protocol stubs).

local Run = require("moonlift.mlua_run")

local files = {
    -- Task 6: M0 protocol type declarations
    "mlua/luajitvm/protocols.mlua",
    -- Task 7: skeleton modules
    "mlua/luajitvm/core/value.mlua",
    "mlua/luajitvm/core/state.mlua",
    "mlua/luajitvm/core/bytecode.mlua",
    "mlua/luajitvm/core/object.mlua",
    "mlua/luajitvm/core/api.mlua",
    -- Task 7-B: GC object and runtime-state layout modules (P3.CORE.005-009)
    "mlua/luajitvm/core/string.mlua",
    "mlua/luajitvm/core/table.mlua",
    "mlua/luajitvm/core/proto.mlua",
    "mlua/luajitvm/core/func.mlua",
    "mlua/luajitvm/core/upval.mlua",
    "mlua/luajitvm/core/global.mlua",
    "mlua/luajitvm/gc/gc.mlua",
    "mlua/luajitvm/gc/mark.mlua",
    "mlua/luajitvm/gc/sweep.mlua",
    "mlua/luajitvm/runtime/error.mlua",
    "mlua/luajitvm/runtime/upvalue.mlua",
    "mlua/luajitvm/jit/emit.mlua",
    "mlua/luajitvm/jit/opt_split.mlua",
    "mlua/luajitvm/asm/x64_emit.mlua",
    "mlua/luajitvm/asm/x64_exit.mlua",
    "mlua/luajitvm/ffi/ctype.mlua",
    "mlua/luajitvm/generated/ir_meta.mlua",
    "mlua/luajitvm/generated/fold_rules.mlua",
    "mlua/luajitvm/generated/asm_tiles_x64.mlua",
    -- Task 8: P4.PROTO.002 interpreter stubs
    "mlua/luajitvm/runtime/dispatch.mlua",  -- P5.INT: real interpreter now
    "mlua/luajitvm/runtime/arith.mlua",
    "mlua/luajitvm/runtime/compare.mlua",
    "mlua/luajitvm/runtime/stackop.mlua",
    "mlua/luajitvm/runtime/call.mlua",
    "mlua/luajitvm/runtime/base.mlua",
    "mlua/luajitvm/runtime/closure.mlua",
    -- Task 8: P4.PROTO.003 table/meta stubs
    "mlua/luajitvm/runtime/table.mlua",
    "mlua/luajitvm/runtime/string.mlua",
    "mlua/luajitvm/runtime/meta.mlua",
    "mlua/luajitvm/runtime/global.mlua",
    "mlua/luajitvm/runtime/loop.mlua",
    -- Task 8: P4.PROTO.004 GC stubs
    "mlua/luajitvm/gc/alloc.mlua",
    "mlua/luajitvm/gc/barrier.mlua",
    -- Task 8: P4.PROTO.005 trace stubs
    "mlua/luajitvm/jit/trace.mlua",
    -- Function pointer trace-call smoke module is covered by tests/test_trace_function_pointer.lua.
    -- Task 8: P4.PROTO.006 IR stubs
    "mlua/luajitvm/jit/ir.mlua",
    "mlua/luajitvm/jit/snap.mlua",
    "mlua/luajitvm/jit/fold.mlua",
    "mlua/luajitvm/jit/record.mlua",
    -- Task 8: P4.PROTO.007 optimizer stubs
    "mlua/luajitvm/jit/opt_dce.mlua",
    "mlua/luajitvm/jit/opt_loop.mlua",
    "mlua/luajitvm/jit/opt_sink.mlua",
    "mlua/luajitvm/jit/opt_narrow.mlua",
    -- Task 8: P4.PROTO.008 assembler stubs
    "mlua/luajitvm/asm/asm_state.mlua",
    "mlua/luajitvm/asm/regalloc.mlua",
    "mlua/luajitvm/asm/mcode.mlua",
    "mlua/luajitvm/asm/x64_tiles.mlua",
    -- FFI stubs
    "mlua/luajitvm/ffi/cdata.mlua",
    "mlua/luajitvm/ffi/ccall.mlua",
    -- Generated stubs
    "mlua/luajitvm/generated/opcodes.mlua",
}

local passed, failed = 0, 0
for _, path in ipairs(files) do
    local ok, err = pcall(function()
        Run.dofile(path)
    end)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        io.stderr:write("FAIL " .. path .. ": " .. tostring(err) .. "\n")
    end
end

assert(failed == 0,
    string.format("luajitvm skeleton: %d passed, %d FAILED", passed, failed))
print(string.format("luajitvm skeleton ok: %d files compiled", passed))
