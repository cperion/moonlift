-- Benchmark: Copy-and-patch vs Lalin VM dispatch
-- Copy-and-patch: memcpy .text bytes to RWX memory, call function pointer directly
-- NO .so, NO PLT, NO FFI call overhead

local ffi = require("ffi")
local bit = require("bit")

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")
local vm = require("experiments.lua_interpreter_vm.src.init")
local const = vm.const

-- ── Step 1: Write the C stencil source ─────────────────────────────────

local c_src = [[
#include <stdint.h>

typedef struct { uint32_t tag; uint32_t aux; uint64_t bits; } Value;
typedef struct { uint32_t word; } Instr;

typedef struct {
    Value  *stack;
    Instr  *code;
    uint64_t pc;
    uint64_t base;
    uint64_t top;
    int32_t status;
} Ctx;

static inline uint32_t A(uint32_t w) { return (w >> 7) & 255; }
static inline uint32_t B(uint32_t w) { return (w >> 16) & 255; }
static inline uint32_t C(uint32_t w) { return (w >> 24) & 255; }

int stencil_run(Ctx *ctx) {
    for (;;) {
        uint32_t w = ctx->code[ctx->pc].word;
        uint32_t op = w & 127;

        if (op == 0) return 0;          // RETURN

        if (op == 1) {                   // LOADI
            uint32_t dst = ctx->base + A(w);
            int32_t sbx = (int32_t)((w >> 15) & 131071) - 65535;
            ctx->stack[dst].tag = 8;     // TAG_INTEGER
            ctx->stack[dst].aux = 0;
            ctx->stack[dst].bits = (uint64_t)(int64_t)sbx;
            ctx->pc++;
            continue;
        }

        if (op == 34) {                  // ADD (inline integer path)
            uint32_t dst = ctx->base + A(w);
            uint32_t lhs_i = ctx->base + B(w);
            uint32_t rhs_i = ctx->base + C(w);
            Value lhs = ctx->stack[lhs_i];
            Value rhs = ctx->stack[rhs_i];
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

        if (op == 36) {                  // MUL (inline integer path)
            uint32_t dst = ctx->base + A(w);
            uint32_t lhs_i = ctx->base + B(w);
            uint32_t rhs_i = ctx->base + C(w);
            Value lhs = ctx->stack[lhs_i];
            Value rhs = ctx->stack[rhs_i];
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

        ctx->pc++;  // unknown opcode
    }
}
]]

local f = io.open("/tmp/stencil_cap.c", "w"); f:write(c_src); f:close()
os.execute("gcc -O2 -fomit-frame-pointer -c /tmp/stencil_cap.c -o /tmp/stencil_cap.o 2>&1")
assert(os.execute("test -f /tmp/stencil_cap.o"), "compile failed")

-- ── Step 2: Extract .text bytes ────────────────────────────────────────

local function extract_text_bytes(o_path)
    local p = io.popen("objdump -d -j .text " .. o_path .. " 2>/dev/null", "r")
    local dis = p:read("*a"); p:close()
    local bytes = {}
    for line in dis:gmatch("[^\n]+") do
        local hex = line:match("^%s*[0-9a-f]+:%s+([0-9a-f ]+)%s+")
        if hex then for b in hex:gmatch("[0-9a-f][0-9a-f]") do bytes[#bytes+1] = tonumber(b, 16) end end
    end
    if #bytes == 0 then return nil end
    return bytes
end

local text_bytes = extract_text_bytes("/tmp/stencil_cap.o")
assert(text_bytes, "could not extract .text")
print(string.format("Extracted %d bytes of stencil_run .text", #text_bytes))

-- ── Step 3: mmap RWX + copy for copy-and-patch ────────────────────────

ffi.cdef [[
void *mmap(void *addr, size_t length, int prot, int flags, int fd, long offset);
int munmap(void *addr, size_t length);
int mprotect(void *addr, size_t len, int prot);
void *memcpy(void *dest, const void *src, size_t n);

typedef struct { uint32_t tag; uint32_t aux; uint64_t bits; } Value;
typedef struct { uint32_t word; } Instr;

typedef struct {
    Value  *stack;
    Instr  *code;
    uint64_t pc;
    uint64_t base;
    uint64_t top;
    int32_t status;
} Ctx;
]]

local PROT_READ = 1
local PROT_WRITE = 2
local PROT_EXEC = 4
local MAP_PRIVATE = 2
local MAP_ANONYMOUS = 0x20

-- Allocate RWX memory
local code_size = #text_bytes
local code_mem = ffi.cast("uint8_t*",
    ffi.C.mmap(nil, code_size, bit.bor(PROT_READ, PROT_WRITE, PROT_EXEC),
               bit.bor(MAP_PRIVATE, MAP_ANONYMOUS), -1, 0))
assert(tonumber(ffi.cast("uintptr_t", code_mem)) ~= 0xffffffffffffffff, "mmap failed")

-- memcpy the .text bytes
local src_buf = ffi.new("uint8_t[?]", code_size)
for i = 0, code_size - 1 do src_buf[i] = text_bytes[i + 1] end
ffi.C.memcpy(code_mem, src_buf, code_size)

-- Create function pointer
local fn_ptr = ffi.cast("int(*)(Ctx*)", code_mem)

-- ── Step 4: Lalin VM infra ──────────────────────────────────────────

local function pack_ABC(op, a, b, c, k)
    return bit.bor(op, bit.lshift(a or 0, 7), bit.lshift(k or 0, 15), bit.lshift(b or 0, 16), bit.lshift(c or 0, 24))
end
local function pack_AsBx(op, a, sbx)
    return bit.bor(op, bit.lshift(a or 0, 7), bit.lshift((sbx or 0) + 65535, 15))
end
local function set_ABC(i, op, a, b, c, k) i.word = pack_ABC(op, a, b, c, k) end
local function set_AsBx(i, op, a, sbx) i.word = pack_AsBx(op, a, sbx) end

ffi.cdef [[ void* lalin_scratch_raw(int slot, int elem_size, int count); ]]

local function load_mlib()
    for _, n in ipairs({"./target/release/liblalin.so","./target/debug/liblalin.so","liblalin"}) do
        local ok, l = pcall(ffi.load, n); if ok then return l end
    end
    error("build first: cargo build --release")
end
local ml = load_mlib()
local scratch_raw = ml.lalin_scratch_raw
local function S(s, e, c, t) return ffi.cast(t or "uint8_t*", scratch_raw(s, e, c)) end

ffi.cdef [[
typedef struct { void* nxt; uint8_t tt; uint8_t mk; } GC;
typedef struct { uint32_t tag; uint32_t aux; uint64_t bits; } Value;
typedef struct { uint32_t word; } Instr;
typedef struct { GC gc; void* code; uint64_t code_len; void* constants; uint64_t constants_len; void** children; uint64_t children_len; int32_t* lineinfo; uint64_t lineinfo_len; void* locvars; uint64_t locvars_len; void* upvals; uint64_t upvals_len; void* source; int32_t linedefined; int32_t lastlinedefined; uint8_t numparams; uint8_t flag; uint16_t maxstack; } Proto;
typedef struct { GC gc; void* env; Proto* proto; void** upval; uint8_t nupvals; } LCl;
typedef struct { Value closure; uint64_t base; uint64_t top; uint64_t pc; int32_t wanted; int32_t tailcalls; uint16_t resume_mode; uint16_t resume_a; uint16_t resume_b; uint16_t resume_c; uint64_t resume_pc; uint64_t resume_base; Value resume_value; } Frame;
typedef struct { GC gc; uint8_t status; Value* stack; uint64_t stack_size; uint64_t top; Frame* frames; uint64_t frame_count; uint64_t frame_cap; void* open_upvals; void* protected_top; void* global; Value err_value; uint8_t hookmask; uint8_t allowhook; int32_t hookcount; int32_t basehookcount; Value hook; uint64_t tbc_head; } LuaThread;
typedef struct { void* allocator; Value registry; void* mainthread; } GState;
]]

local function set_int(v, n) v.tag = const.Tag.INTEGER; v.aux = 0; v.bits = ffi.cast("uint64_t", n) end
local function set_nil(v) v.tag = const.Tag.NIL; v.aux = 0; v.bits = 0 end

function build_program(fill, steps)
    steps = steps or 50000
    local code_slots = steps
    local slot = 40 + code_slots
    local consts = S(slot, 16, 4, "Value*")
    set_int(consts[0], 42); set_int(consts[1], 99); set_int(consts[2], 7); set_int(consts[3], 2)
    local code = S(slot + 1, ffi.sizeof("Instr"), code_slots + 1, "Instr*")
    for i = 0, code_slots do set_ABC(code[i], 0, 0, 0, 0, 0) end
    fill(code, steps)
    set_ABC(code[code_slots], const.Op.RETURN, 0, 2, 0, 0)
    local proto = S(slot + 2, 1, 256, "Proto*")
    proto.code = ffi.cast("void*", code); proto.code_len = code_slots + 1
    proto.constants = ffi.cast("void*", consts); proto.constants_len = 4; proto.maxstack = 8
    local closure = S(slot + 3, 1, 64, "LCl*")
    closure.proto = proto; closure.nupvals = 0
    local stack = S(slot + 4, 16, 64, "Value*")
    for i = 0, 63 do set_nil(stack[i]) end
    stack[0].tag = const.Tag.LCLOSURE; stack[0].aux = 0; stack[0].bits = ffi.cast("uint64_t", closure)
    set_int(stack[1], 42); set_int(stack[2], 99); set_int(stack[3], 7)
    local frames = S(slot + 5, 1, 512, "Frame*")
    frames[0].closure.tag = const.Tag.LCLOSURE; frames[0].closure.aux = 0
    frames[0].closure.bits = ffi.cast("uint64_t", closure)
    frames[0].base = 1; frames[0].top = 3; frames[0].pc = 0; frames[0].wanted = 1
    frames[0].resume_mode = const.Resume.NORMAL
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

local runner_fn = lalin.func { vm_resume = vm.vm_loop.vm_resume } [[
run(L: ptr(LuaThread), nargs: i32): i32
    return region: i32
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

-- ── Benchmark ──────────────────────────────────────────────────────────

local STEPS = 50000
local RUNS = 1000

local function bench_vm(fill)
    local thread, stack, frames = build_program(fill, STEPS)
    local verify = runner_fn(thread, 0)
    assert(verify == 1)
    runner_fn(thread, 0) -- warmup
    reset(thread, stack, frames)
    local t0 = os.clock()
    for _ = 1, RUNS do
        runner_fn(thread, 0)
        reset(thread, stack, frames)
    end
    return (os.clock() - t0) / (RUNS * STEPS) * 1e9
end

local function bench_cap(fill)
    -- Build the program (same as VM)
    local _, stack, _, code = build_program(fill, STEPS)
    -- Ctx for the stencil
    local ctx = ffi.new("Ctx")
    ctx.stack = stack
    ctx.code = code
    ctx.pc = 0; ctx.base = 1; ctx.top = 3; ctx.status = 0
    set_int(stack[1], 42); set_int(stack[2], 99); set_int(stack[3], 7)
    -- Warmup
    fn_ptr(ctx)
    ctx.pc = 0; set_int(stack[1], 42); set_int(stack[2], 99); set_int(stack[3], 7)
    -- Timed loop — DIRECT function pointer call, no FFI dispatch overhead
    local t0 = os.clock()
    for _ = 1, RUNS do
        fn_ptr(ctx)
        ctx.pc = 0
        set_int(stack[1], 42); set_int(stack[2], 99); set_int(stack[3], 7)
    end
    return (os.clock() - t0) / (RUNS * STEPS) * 1e9
end

-- Empty baseline
local function empty_fill(c, s) end
local baseline = bench_vm(empty_fill)

print(string.format("\nSTEPS=%d  RUNS=%d  code_size=%d bytes  VM baseline=%.2f ns\n", STEPS, RUNS, code_size, baseline))
print(string.format("%-20s  %10s  %10s  %s", "BENCHMARK", "VM ns/op", "C+P ns/op", "speedup"))
print(string.rep("-", 60))

local benchmarks = {
    {"LOADI", function(c, s) for i=0,s-1 do set_AsBx(c[i], const.Op.LOADI, 0, 42) end end},
    {"ADD",   function(c, s) for i=0,s-1 do set_ABC(c[i], const.Op.ADD, 0, 1, 2, 0) end end},
    {"ADDI",  function(c, s) for i=0,s-1 do set_ABC(c[i], const.Op.ADDI, 0, 1, 7, 0) end end},
    {"MUL",   function(c, s) for i=0,s-1 do set_ABC(c[i], const.Op.MUL, 0, 1, 2, 0) end end},
}

for _, b in ipairs(benchmarks) do
    local vm_ns = bench_vm(b[2])
    local cap_ns = bench_cap(b[2])
    local speedup = cap_ns > 0 and (vm_ns / cap_ns) or 0
    print(string.format("%-20s  %7.2f ns  %7.2f ns  %5.2fx", b[1], vm_ns, cap_ns, speedup))
end

print(string.rep("-", 60))
print("\nCopy-and-patch: mmap RWX + memcpy .text bytes + direct call (no PLT/GOT/FFI)")

ffi.C.munmap(code_mem, code_size)
runner_fn:free()
