-- Fair benchmark: C monolithic stencil vs Moonlift VM dispatch
-- Both do the same work: iterate N times executing a bytecode program

local ffi = require("ffi")
local bit = require("bit")

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local moon = require("moonlift")
local vm = require("experiments.lua_interpreter_vm.src.init")
local const = vm.const

-- ── C stencil: compile to .so ──────────────────────────────────────────

-- The stencil matches the Moonlift VM's inlined ADD exactly:
-- 1. Read base, pc from context
-- 2. Decode instruction operands (A, B, C)
-- 3. Load lhs (base+B.tag, base+B.bits), rhs (base+C.tag, base+C.bits)
-- 4. Check both have TAG_INTEGER
-- 5. Add, store to base+A
-- 6. Advance pc by 2 (ADD is a 2-word instruction in this VM)
-- 7. Return

local c_src = [[
#include <stdint.h>
#include <stddef.h>
typedef struct { uint32_t tag; uint32_t aux; uint64_t bits; } Value;
typedef struct { uint32_t word; } Instr;
typedef struct {
    Value *stack;
    Instr *code;
    uint64_t pc;
    uint64_t base;
    uint64_t top;
    int32_t status;
} Ctx;

static inline uint32_t get_A(uint32_t w) { return (w >> 7) & 255; }
static inline uint32_t get_B(uint32_t w) { return (w >> 16) & 255; }
static inline uint32_t get_C(uint32_t w) { return (w >> 24) & 255; }

int stencil_run(Ctx *ctx) {
    for (;;) {
        Instr ins = ctx->code[ctx->pc];
        uint32_t w = ins.word;
        uint32_t op = w & 127;
        if (op == 0) {
            // RETURN
            return 0;
        }
        if (op == 1) {
            // LOADI
            uint32_t dst = ctx->base + get_A(w);
            int32_t sbx = (int32_t)((w >> 15) & 131071) - 65535;
            ctx->stack[dst].tag = 8; // TAG_INTEGER
            ctx->stack[dst].aux = 0;
            ctx->stack[dst].bits = (uint64_t)(int64_t)sbx;
            ctx->pc++;
            continue;
        }
        if (op == 34) {
            // ADD (inline)
            uint32_t dst = ctx->base + get_A(w);
            uint32_t lhs_idx = ctx->base + get_B(w);
            uint32_t rhs_idx = ctx->base + get_C(w);
            Value lhs = ctx->stack[lhs_idx];
            Value rhs = ctx->stack[rhs_idx];
            if (lhs.tag == 8 && rhs.tag == 8) {
                int64_t r = (int64_t)lhs.bits + (int64_t)rhs.bits;
                ctx->stack[dst].tag = 8;
                ctx->stack[dst].aux = 0;
                ctx->stack[dst].bits = (uint64_t)r;
                ctx->pc++;
                continue;
            }
            ctx->pc++;
            continue;
        }
        if (op == 36) {
            // MUL (inline)
            uint32_t dst = ctx->base + get_A(w);
            uint32_t lhs_idx = ctx->base + get_B(w);
            uint32_t rhs_idx = ctx->base + get_C(w);
            Value lhs = ctx->stack[lhs_idx];
            Value rhs = ctx->stack[rhs_idx];
            if (lhs.tag == 8 && rhs.tag == 8) {
                int64_t r = (int64_t)lhs.bits * (int64_t)rhs.bits;
                ctx->stack[dst].tag = 8;
                ctx->stack[dst].aux = 0;
                ctx->stack[dst].bits = (uint64_t)r;
                ctx->pc++;
                continue;
            }
            ctx->pc++;
            continue;
        }
        // MMBIN fallthrough for non-integer
        ctx->pc++;
    }
    return 0;
}
]]

local f = io.open("/tmp/stencil_mono_vm.c", "w"); f:write(c_src); f:close()
os.execute("gcc -O2 -fomit-frame-pointer -shared -fPIC /tmp/stencil_mono_vm.c -o /tmp/stencil_mono_vm.so 2>/dev/null")
assert(os.execute("test -f /tmp/stencil_mono_vm.so"), "compile failed")

ffi.cdef[[
typedef struct { uint32_t tag; uint32_t aux; uint64_t bits; } Value;
typedef struct { uint32_t word; } Instr;
typedef struct { Value *stack; Instr *code; uint64_t pc; uint64_t base; uint64_t top; int32_t status; } Ctx;
int stencil_run(Ctx *ctx);
]]
local lib = ffi.load("/tmp/stencil_mono_vm.so")

-- ── Moonlift VM infra ──────────────────────────────────────────────────

local function pack_ABC(op, a, b, c, k)
    return bit.bor(op, bit.lshift(a or 0, 7), bit.lshift(k or 0, 15), bit.lshift(b or 0, 16), bit.lshift(c or 0, 24))
end
local function pack_AsBx(op, a, sbx)
    return bit.bor(op, bit.lshift(a or 0, 7), bit.lshift((sbx or 0) + 65535, 15))
end
local function set_ABC(i, op, a, b, c, k) i.word = pack_ABC(op, a, b, c, k) end
local function set_AsBx(i, op, a, sbx) i.word = pack_AsBx(op, a, sbx) end

ffi.cdef [[ void* moonlift_scratch_raw(int slot, int elem_size, int count); ]]

local function load_mlib()
    for _, n in ipairs({"./target/release/libmoonlift.so","./target/debug/libmoonlift.so","libmoonlift"}) do
        local ok, l = pcall(ffi.load, n); if ok then return l end
    end
    error("build first: cargo build --release")
end
local ml = load_mlib()
local scratch_raw = ml.moonlift_scratch_raw
local function S(s, e, c, t) return ffi.cast(t or "uint8_t*", scratch_raw(s, e, c)) end

ffi.cdef [[
typedef struct { void* nxt; uint8_t tt; uint8_t mk; } GC;
typedef struct { uint32_t tag; uint32_t aux; uint64_t bits; } Value;
typedef struct { uint32_t word; } Instr;
typedef struct { GC gc; void* code; uint64_t code_len; void* constants; uint64_t constants_len; void** children; uint64_t children_len; int32_t* lineinfo; uint64_t lineinfo_len; void* locvars; uint64_t locvars_len; void* upvals; uint64_t upvals_len; void* source; int32_t linedefined; int32_t lastlinedefined; uint8_t numparams; uint8_t flag; uint16_t maxstack; } Proto;
typedef struct { GC gc; void* env; Proto* proto; void** upvals; uint8_t nupvals; } LCl;
typedef struct { Value closure; uint64_t base; uint64_t top; uint64_t pc; int32_t wanted; int32_t tailcalls; uint16_t resume_mode; uint16_t resume_a; uint16_t resume_b; uint16_t resume_c; uint64_t resume_pc; uint64_t resume_base; Value resume_value; } Frame;
typedef struct { GC gc; uint8_t status; Value* stack; uint64_t stack_size; uint64_t top; Frame* frames; uint64_t frame_count; uint64_t frame_cap; void* open_upvals; void* protected_top; void* global; Value err_value; uint8_t hookmask; uint8_t allowhook; int32_t hookcount; int32_t basehookcount; Value hook; uint64_t tbc_head; } LuaThread;
typedef struct { void* allocator; Value registry; void* mainthread; } GState;
]]

local function set_int(v, n) v.tag = const.Tag.INTEGER; v.aux = 0; v.bits = ffi.cast("uint64_t", n) end
local function set_nil(v) v.tag = const.Tag.NIL; v.aux = 0; v.bits = 0 end

-- ── Build a program ────────────────────────────────────────────────────

function build_program(fill, steps)
    steps = steps or 10000
    local code_slots = steps
    local slot = 40 + code_slots

    -- Constants
    local consts = S(slot, 16, 4, "Value*")
    set_int(consts[0], 42); set_int(consts[1], 99); set_int(consts[2], 7); set_int(consts[3], 2)

    -- Code
    local code = S(slot + 1, ffi.sizeof("Instr"), code_slots + 1, "Instr*")
    for i = 0, code_slots do set_ABC(code[i], 0, 0, 0, 0, 0) end
    fill(code, steps)
    set_ABC(code[code_slots], const.Op.RETURN, 0, 2, 0, 0)

    -- Proto
    local proto = S(slot + 2, 1, 256, "Proto*")
    proto.code = ffi.cast("void*", code); proto.code_len = code_slots + 1
    proto.constants = ffi.cast("void*", consts); proto.constants_len = 4; proto.maxstack = 8

    -- Closure
    local closure = S(slot + 3, 1, 64, "LCl*")
    closure.proto = proto; closure.nupvals = 0

    -- Stack
    local stack = S(slot + 4, 16, 64, "Value*")
    for i = 0, 63 do set_nil(stack[i]) end
    stack[0].tag = const.Tag.LCLOSURE; stack[0].aux = 0; stack[0].bits = ffi.cast("uint64_t", closure)
    set_int(stack[1], 42); set_int(stack[2], 99); set_int(stack[3], 7)

    -- Frame
    local frames = S(slot + 5, 1, 512, "Frame*")
    frames[0].closure.tag = const.Tag.LCLOSURE; frames[0].closure.aux = 0
    frames[0].closure.bits = ffi.cast("uint64_t", closure)
    frames[0].base = 1; frames[0].top = 3; frames[0].pc = 0; frames[0].wanted = 1
    frames[0].resume_mode = const.Resume.NORMAL

    -- Thread
    local gs = S(slot + 6, 1, 64, "GState*")
    local thread = S(slot + 7, 1, 256, "LuaThread*")
    thread.status = const.Status.OK; thread.stack = stack; thread.stack_size = 64
    thread.top = 3; thread.frames = frames; thread.frame_count = 1; thread.frame_cap = 8; thread.global = gs

    return thread, stack, frames, code
end

local function reset(thread, stack, frames)
    thread.status = const.Status.OK; thread.top = 3; thread.frame_count = 1
    frames[0].base = 1; frames[0].top = 3; frames[0].pc = 0; frames[0].wanted = 1
    frames[0].resume_mode = const.Resume.NORMAL
    set_int(stack[1], 42); set_int(stack[2], 99); set_int(stack[3], 7)
end

-- Moonlift runner
local runner_fn = moon.func { vm_resume = vm.vm_loop.vm_resume } [[
run(L: ptr(LuaThread), nargs: i32) -> i32
    return region -> i32
    entry start()
        emit @{vm_resume}(L, nargs;
            ok = done, yielded = did_yield,
            runtime_error = did_error, oom = did_oom)
    end
    block done(nres: i32) return nres end
    block did_yield(nres: i32) return -100 - nres end
    block did_error(code: i32) return -200 - code end
    block did_oom() return -999 end
    end
end
]]:compile()

-- ── Benchmarks ─────────────────────────────────────────────────────────

local STEPS = 50000
local RUNS = 1000

local function bench_vm(name, fill)
    local thread, stack, frames, code = build_program(fill, STEPS)
    local verify = runner_fn(thread, 0)
    assert(verify == 1, name .. " verify: " .. tostring(verify))
    runner_fn(thread, 0) -- warmup
    reset(thread, stack, frames)
    local t0 = os.clock()
    for _ = 1, RUNS do
        runner_fn(thread, 0)
        reset(thread, stack, frames)
    end
    return (os.clock() - t0) / (RUNS * STEPS) * 1e9
end

local function bench_c(name, fill)
    -- Build a Ctx, fill the code, run the stencil
    local _, stack, _, code = build_program(fill, STEPS)
    local ctx = ffi.new("Ctx")
    ctx.stack = stack
    ctx.code = ffi.cast("Instr*", code) -- reuse the same Instr*
    ctx.code = ffi.cast("Instr*", code)
    ctx.pc = 0; ctx.base = 1; ctx.top = 3; ctx.status = 0
    -- Reset stack
    set_int(stack[1], 42); set_int(stack[2], 99); set_int(stack[3], 7)
    -- Warmup
    lib.stencil_run(ctx)
    ctx.pc = 0; ctx.status = 0
    set_int(stack[1], 42); set_int(stack[2], 99); set_int(stack[3], 7)
    local t0 = os.clock()
    for _ = 1, RUNS do
        lib.stencil_run(ctx)
        ctx.pc = 0
        set_int(stack[1], 42); set_int(stack[2], 99); set_int(stack[3], 7)
    end
    return (os.clock() - t0) / (RUNS * STEPS) * 1e9
end

-- Empty baseline
local function empty_fill(c, s) end
local baseline = bench_vm("baseline", empty_fill)

print(string.format("\nSTEPS=%d  RUNS=%d  VM baseline=%.2f ns\n", STEPS, RUNS, baseline))
print(string.format("%-20s  %10s  %10s  %s", "BENCHMARK", "VM ns/op", "C ns/op", "speedup"))
print(string.rep("-", 60))

local benchmarks = {
    {"LOADI", function(c, s) for i=0,s-1 do set_AsBx(c[i], const.Op.LOADI, 0, 42) end end},
    {"ADD",   function(c, s) for i=0,s-1 do set_ABC(c[i], const.Op.ADD, 0, 1, 2, 0) end end},
    {"ADDI",  function(c, s) for i=0,s-1 do set_ABC(c[i], const.Op.ADDI, 0, 1, 7, 0) end end},
    {"MUL",   function(c, s) for i=0,s-1 do set_ABC(c[i], const.Op.MUL, 0, 1, 2, 0) end end},
}

for _, b in ipairs(benchmarks) do
    local vm_ns = bench_vm(b[1], b[2])
    local c_ns = bench_c(b[1], b[2])
    local speedup = c_ns > 0 and (vm_ns / c_ns) or 0
    print(string.format("%-20s  %7.2f ns  %7.2f ns  %5.2fx", b[1], vm_ns, c_ns, speedup))
end

print(string.rep("-", 60))

runner_fn:free()
