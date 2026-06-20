-- VM vs reference benchmark
-- Run from repo root:
--   luajit experiments/lua_interpreter_vm/benchmarks/bench_vm_vs_ref.lua
-- or:
--   luajit -e 'package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path; dofile("experiments/lua_interpreter_vm/benchmarks/bench_vm_vs_ref.lua")'

local ffi = require("ffi")
local bit = require("bit")

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local moon = require("moonlift")
local vm = require("experiments.lua_interpreter_vm.src.init")
local const = vm.const

local function pack_ABC(op, a, b, c, k)
    return bit.bor(op, bit.lshift(a or 0, 7), bit.lshift(k or 0, 15), bit.lshift(b or 0, 16), bit.lshift(c or 0, 24))
end
local function pack_ABx(op, a, bx)
    return bit.bor(op, bit.lshift(a or 0, 7), bit.lshift(bx or 0, 15))
end
local function pack_AsBx(op, a, sbx)
    return bit.bor(op, bit.lshift(a or 0, 7), bit.lshift((sbx or 0) + 65535, 15))
end
local function set_ABC(i, op, a, b, c, k) i.word = pack_ABC(op, a, b, c, k) end
local function set_ABx(i, op, a, bx) i.word = pack_ABx(op, a, bx) end
local function set_AsBx(i, op, a, sbx) i.word = pack_AsBx(op, a, sbx) end
local function op_of(i) return bit.band(i.word, 127) end

ffi.cdef [[
    void* moonlift_scratch_raw(int slot, int elem_size, int count);
]]

local function load_moonlift_lib()
    local tried = {}
    for _, name in ipairs({ "libmoonlift", "./target/release/libmoonlift.so", "./target/debug/libmoonlift.so" }) do
        tried[#tried + 1] = name
        local ok, lib = pcall(ffi.load, name)
        if ok then return lib end
    end
    error("could not load libmoonlift; tried: " .. table.concat(tried, ", ") .. "\nBuild it first with: cargo build --release")
end

local libmoon = load_moonlift_lib()
local scratch_raw = libmoon.moonlift_scratch_raw

-- FFI layouts must match experiments/lua_interpreter_vm/src/products.lua exactly.
ffi.cdef [[
    typedef struct { void* next; uint8_t tt; uint8_t marked; } GCHeader;
    typedef struct { uint32_t tag; uint32_t aux; uint64_t bits; } Value;
    typedef struct { uint32_t word; } Instr;
    typedef struct {
        GCHeader gc;
        void* code; uint64_t code_len;
        void* constants; uint64_t constants_len;
        void** children; uint64_t children_len;
        int32_t* lineinfo; uint64_t lineinfo_len;
        void* locvars; uint64_t locvars_len;
        void* upvals; uint64_t upvals_len;
        void* source;
        int32_t linedefined; int32_t lastlinedefined;
        uint8_t numparams; uint8_t flag; uint16_t maxstack;
    } Proto;
    typedef struct {
        GCHeader gc;
        void* env; Proto* proto;
        void** upvals; uint8_t nupvals;
    } LClosure;
    typedef struct {
        Value closure; uint64_t base; uint64_t top; uint64_t pc;
        int32_t wanted; int32_t tailcalls;
        uint16_t resume_mode;
        uint16_t resume_a; uint16_t resume_b; uint16_t resume_c;
        uint64_t resume_pc; uint64_t resume_base; Value resume_value;
    } Frame;
    typedef struct {
        GCHeader gc; uint8_t status;
        Value* stack; uint64_t stack_size; uint64_t top;
        Frame* frames; uint64_t frame_count; uint64_t frame_cap;
        void* open_upvals; void* protected_top;
        void* global; Value err_value;
        uint8_t hookmask; uint8_t allowhook;
        int32_t hookcount; int32_t basehookcount; Value hook;
    } LuaThread;
    typedef struct { void* allocator; Value registry; void* mainthread; } GlobalState;
]]

local function scratch(slot, elem_size, count, ctype)
    return ffi.cast(ctype or "uint8_t*", scratch_raw(slot, elem_size, count))
end

local function double_bits(x)
    local u = ffi.new("union { double d; uint64_t u; }")
    u.d = x
    return u.u
end

local function bits_double(x)
    local u = ffi.new("union { double d; uint64_t u; }")
    u.u = x
    return u.d
end

local STACK_N = 64

local function build_thread()
    -- Constants: [42.0, 99.0]
    local consts = scratch(10, 16, 2, "Value*")
    consts[0].tag = const.Tag.NUM; consts[0].aux = 0; consts[0].bits = double_bits(42.0)
    consts[1].tag = const.Tag.NUM; consts[1].aux = 0; consts[1].bits = double_bits(99.0)

    -- Code: LOADK R0 K0, RETURN R0 2
    local code = scratch(11, ffi.sizeof("Instr"), 2, "Instr*")
    set_ABx(code[0], const.Op.LOADK, 0, 0)
    set_ABC(code[1], const.Op.RETURN, 0, 2, 0, 0)

    local proto = scratch(12, 1, 256, "Proto*")
    proto.code = ffi.cast("void*", code); proto.code_len = 2
    proto.constants = ffi.cast("void*", consts); proto.constants_len = 2
    proto.children = nil; proto.children_len = 0
    proto.lineinfo = nil; proto.lineinfo_len = 0
    proto.locvars = nil; proto.locvars_len = 0
    proto.upvals = nil; proto.upvals_len = 0
    proto.source = nil
    proto.linedefined = -1; proto.lastlinedefined = -1
    proto.numparams = 0; proto.flag = 0; proto.maxstack = 1

    local closure = scratch(13, 1, 64, "LClosure*")
    closure.env = nil; closure.proto = proto; closure.upvals = nil; closure.nupvals = 0

    local stack = scratch(14, 16, STACK_N, "Value*")
    for i = 0, STACK_N - 1 do
        stack[i].tag = const.Tag.NIL; stack[i].aux = 0; stack[i].bits = 0
    end
    stack[0].tag = const.Tag.LCLOSURE; stack[0].aux = 0; stack[0].bits = ffi.cast("uint64_t", closure)

    local frames = scratch(15, 1, 512, "Frame*")
    frames[0].closure.tag = const.Tag.LCLOSURE
    frames[0].closure.aux = 0
    frames[0].closure.bits = ffi.cast("uint64_t", closure)
    frames[0].base = 1; frames[0].top = 1; frames[0].pc = 0
    frames[0].wanted = 1; frames[0].tailcalls = 0
    frames[0].resume_mode = const.Resume.NORMAL
    frames[0].resume_a = 0; frames[0].resume_b = 0; frames[0].resume_c = 0
    frames[0].resume_pc = 0; frames[0].resume_base = 0
    frames[0].resume_value.tag = const.Tag.NIL; frames[0].resume_value.aux = 0; frames[0].resume_value.bits = 0

    local gstate = scratch(16, 1, 64, "GlobalState*")
    gstate.allocator = nil; gstate.registry.tag = const.Tag.NIL; gstate.registry.aux = 0; gstate.registry.bits = 0

    local thread = scratch(17, 1, 256, "LuaThread*")
    thread.status = const.Status.OK
    thread.stack = stack; thread.stack_size = STACK_N; thread.top = 1
    thread.frames = frames; thread.frame_count = 1; thread.frame_cap = 8
    thread.open_upvals = nil; thread.protected_top = nil; thread.global = gstate
    thread.err_value.tag = const.Tag.NIL; thread.err_value.aux = 0; thread.err_value.bits = 0
    thread.hookmask = 0; thread.allowhook = 0; thread.hookcount = 0; thread.basehookcount = 0
    thread.hook.tag = const.Tag.NIL; thread.hook.aux = 0; thread.hook.bits = 0
    gstate.mainthread = thread

    return thread, stack, frames
end

local function reset(thread, stack, frames)
    thread.status = const.Status.OK
    thread.top = 1
    thread.frame_count = 1
    frames[0].base = 1
    frames[0].top = 1
    frames[0].pc = 0
    frames[0].wanted = 1
    frames[0].resume_mode = const.Resume.NORMAL
    stack[1].tag = const.Tag.NIL
    stack[1].aux = 0
    stack[1].bits = 0
end

print("Compiling runner...")
local runner = moon.func { vm_resume = vm.vm_loop.vm_resume } [[
run(L: ptr(LuaThread), nargs: i32): i32
    return region: i32
    entry start()
        emit @{vm_resume}(L, nargs;
            ok = done,
            yielded = did_yield,
            runtime_error = did_error,
            oom = did_oom)
    end
    block done(nres: i32) return nres end
    block did_yield(nres: i32) return -100 - nres end
    block did_error(code: i32) return -200 - code end
    block did_oom() return -999 end
    end
end
]]
local run = runner:compile()

local thread, stack, frames = build_thread()

print("Warmup...")
local warm = run(thread, 0)
assert(warm == 1, "expected nres=1, got " .. tostring(warm))
assert(stack[1].tag == const.Tag.NUM, "expected numeric result tag, got " .. tostring(stack[1].tag))
local got = bits_double(stack[1].bits)
assert(math.abs(got - 42.0) < 0.001, "expected result 42, got " .. tostring(got))
print("OK: LOADK+RETURN =", got, "nres =", warm)
reset(thread, stack, frames)

local ITERS = tonumber(os.getenv("MOONLIFT_VM_BENCH_ITERS")) or 50000
local t0 = os.clock()
for _ = 1, ITERS do
    run(thread, 0)
    reset(thread, stack, frames)
end
local vm_elapsed = os.clock() - t0
local vm_rate = ITERS / vm_elapsed
print(string.format("\nMoonlift VM: %d iters in %.4fs = %.0f iter/s", ITERS, vm_elapsed, vm_rate))
print(string.format("             %.2f ns per LOADK+RETURN", (vm_elapsed / ITERS) * 1e9))

runner:free()

local function run_ref(title, cmd)
    print("\n--- " .. title .. " ---")
    local pipe = io.popen(cmd)
    if not pipe then
        print("unavailable")
        return
    end
    local out = pipe:read("*a")
    pipe:close()
    io.write(out)
end

local ref_code = string.format([[
local function f() return 42 end
local N = %d
local t0 = os.clock()
for _ = 1, N do f() end
local e = os.clock() - t0
print(string.format("%%.0f iter/s", N / e))
]], ITERS)

run_ref("Reference: LuaJIT -joff", "luajit -joff -e '" .. ref_code .. "'")
run_ref("Reference: PUC Lua", "lua -e '" .. ref_code .. "'")
