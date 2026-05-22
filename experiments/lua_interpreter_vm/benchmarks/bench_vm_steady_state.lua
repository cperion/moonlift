-- Steady-state VM benchmarks (Lua 5.5).
--
-- Builds long Proto bytecode arrays and reports:
--   * raw ns/resume for RETURN-only VM entry/teardown
--   * naive ns/dispatch including RETURN
--   * adjusted hot ns/op with RETURN-only cost subtracted
--   * hot ns/op after subtracting RETURN-only cost
--   * optional reference-loop comparisons against LuaJIT -joff and PUC Lua
--
-- Run:
--   luajit experiments/lua_interpreter_vm/benchmarks/bench_vm_steady_state.lua
--
-- Knobs:
--   MOONLIFT_VM_STEPS=10000
--   MOONLIFT_VM_RUNS=1000
--   MOONLIFT_VM_RETURN_RUNS=100000
--   MOONLIFT_VM_COMPARE_REFS=1     -- set 0 to skip Lua reference processes

local ffi = require("ffi")

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local moon = require("moonlift")
local vm = require("experiments.lua_interpreter_vm.src.init")
local const = vm.const

ffi.cdef [[
    void* moonlift_scratch_raw(int slot, int elem_size, int count);
]]

local function load_moonlift_lib()
    for _, name in ipairs({ "./target/release/libmoonlift.so", "./target/debug/libmoonlift.so", "libmoonlift" }) do
        local ok, lib = pcall(ffi.load, name)
        if ok then return lib end
    end
    error("could not load libmoonlift; build with: cargo build --release")
end
local libmoon = load_moonlift_lib()
local scratch_raw = libmoon.moonlift_scratch_raw

-- Struct layouts matching products.lua (Lua 5.5)
ffi.cdef [[
    typedef struct { void* next; uint8_t tt; uint8_t marked; } GCHeader;
    typedef struct { uint32_t tag; uint32_t aux; uint64_t bits; } Value;
    typedef struct {
        uint16_t op; uint16_t a; uint16_t b; uint16_t c;
        uint8_t  k;    uint32_t bx; int32_t sbx;
    } Instr;
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
        uint64_t tbc_head;
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

local BITS_42 = double_bits(42.0)
local BITS_99 = double_bits(99.0)
local BITS_42_INT = ffi.cast("uint64_t", 42)
local BITS_99_INT = ffi.cast("uint64_t", 99)
local STACK_N = 64
local NEXT_SLOT = 40

local function fresh_slots(n)
    local base = NEXT_SLOT
    NEXT_SLOT = NEXT_SLOT + n
    return base
end

local function clear_stack(stack)
    for i = 0, STACK_N - 1 do
        stack[i].tag = const.Tag.NIL
        stack[i].aux = 0
        stack[i].bits = 0
    end
end

local function set_num(v, bits)
    v.tag = const.Tag.NUM
    v.aux = 0
    v.bits = bits
end

local function set_nil(v)
    v.tag = const.Tag.NIL
    v.aux = 0
    v.bits = 0
end

local function make_thread(case)
    local slot = fresh_slots(8)
    local code_slots = case.code_slots or (case.hot_ops + 1)

    local consts = scratch(slot + 0, 16, 2, "Value*")
    set_num(consts[0], BITS_42)
    set_num(consts[1], BITS_99)

    local code = scratch(slot + 1, ffi.sizeof("Instr"), code_slots, "Instr*")
    for i = 0, code_slots - 1 do
        code[i].op = const.Op.MOVE
        code[i].a = 0
        code[i].b = 0
        code[i].c = 0
        code[i].k = 0
        code[i].bx = 0
        code[i].sbx = 0
    end
    case.fill(code, case.hot_ops, code_slots)

    local proto = scratch(slot + 2, 1, 256, "Proto*")
    proto.code = ffi.cast("void*", code)
    proto.code_len = code_slots
    proto.constants = ffi.cast("void*", consts)
    proto.constants_len = 2
    proto.children = nil; proto.children_len = 0
    proto.lineinfo = nil; proto.lineinfo_len = 0
    proto.locvars = nil; proto.locvars_len = 0
    proto.upvals = nil; proto.upvals_len = 0
    proto.source = nil
    proto.linedefined = -1; proto.lastlinedefined = -1
    proto.numparams = 0; proto.flag = 0; proto.maxstack = case.maxstack or 4

    local closure = scratch(slot + 3, 1, 64, "LClosure*")
    closure.env = nil
    closure.proto = proto
    closure.upvals = nil
    closure.nupvals = 0

    local stack = scratch(slot + 4, 16, STACK_N, "Value*")
    clear_stack(stack)
    stack[0].tag = const.Tag.LCLOSURE
    stack[0].aux = 0
    stack[0].bits = ffi.cast("uint64_t", closure)
    set_num(stack[1], BITS_42) -- R0
    set_num(stack[2], BITS_42) -- R1
    set_nil(stack[3])          -- R2 scratch destination

    if case.stack_init then
        case.stack_init(stack)
    end

    local frames = scratch(slot + 5, 1, 512, "Frame*")
    frames[0].closure.tag = const.Tag.LCLOSURE
    frames[0].closure.aux = 0
    frames[0].closure.bits = ffi.cast("uint64_t", closure)
    frames[0].base = 1
    frames[0].top = 1
    frames[0].pc = 0
    frames[0].wanted = 1
    frames[0].tailcalls = 0
    frames[0].resume_mode = const.Resume.NORMAL
    frames[0].resume_a = 0; frames[0].resume_b = 0; frames[0].resume_c = 0
    frames[0].resume_pc = 0; frames[0].resume_base = 0
    set_nil(frames[0].resume_value)

    local gstate = scratch(slot + 6, 1, 64, "GlobalState*")
    gstate.allocator = nil
    set_nil(gstate.registry)

    local thread = scratch(slot + 7, 1, 256, "LuaThread*")
    thread.status = const.Status.OK
    thread.stack = stack
    thread.stack_size = STACK_N
    thread.top = 1
    thread.frames = frames
    thread.frame_count = 1
    thread.frame_cap = 8
    thread.open_upvals = nil
    thread.protected_top = nil
    thread.global = gstate
    set_nil(thread.err_value)
    thread.hookmask = 0
    thread.allowhook = 0
    thread.hookcount = 0
    thread.basehookcount = 0
    set_nil(thread.hook)
    thread.tbc_head = 0
    gstate.mainthread = thread

    case.thread = thread
    case.stack = stack
    case.frames = frames
    case.code = code
    case.proto = proto
    case.code_slots = code_slots
    case.exec_dispatches = case.exec_dispatches or (case.hot_ops + 1)
    return case
end

local function reset(case)
    local thread, stack, frames = case.thread, case.stack, case.frames
    thread.status = const.Status.OK
    thread.top = 1
    thread.frame_count = 1
    frames[0].base = 1
    frames[0].top = 1
    frames[0].pc = 0
    frames[0].wanted = 1
    frames[0].resume_mode = const.Resume.NORMAL
    frames[0].resume_a = 0
    frames[0].resume_b = 0
    frames[0].resume_c = 0
    frames[0].resume_pc = 0
    frames[0].resume_base = 0
    set_num(stack[1], BITS_42)
    set_num(stack[2], BITS_42)
    set_nil(stack[3])
    if case.stack_init then
        case.stack_init(stack)
    end
end

local function put_return(code, pc)
    code[pc].op = const.Op.RETURN
    code[pc].a = 0
    code[pc].b = 2
    code[pc].c = 0
    code[pc].k = 0
    code[pc].bx = 0
    code[pc].sbx = 0
end

local function fill_return_only(code)
    put_return(code, 0)
end

local function fill_loadi(code, hot_ops)
    for i = 0, hot_ops - 1 do
        code[i].op = const.Op.LOADI
        code[i].a = 0
        code[i].sbx = 42
    end
    put_return(code, hot_ops)
end

local function fill_loadk(code, hot_ops)
    for i = 0, hot_ops - 1 do
        code[i].op = const.Op.LOADK
        code[i].a = 0
        code[i].bx = 0
    end
    put_return(code, hot_ops)
end

local function fill_move_self(code, hot_ops)
    for i = 0, hot_ops - 1 do
        code[i].op = const.Op.MOVE
        code[i].a = 0
        code[i].b = 0
    end
    put_return(code, hot_ops)
end

local function fill_add_int_mmbin(code, hot_ops)
    for i = 0, hot_ops - 1 do
        local pc = i * 2
        code[pc].op = const.Op.ADD
        code[pc].a = 2; code[pc].b = 0; code[pc].c = 1
        code[pc + 1].op = const.Op.MMBIN
        code[pc + 1].a = 0; code[pc + 1].b = const.TM.ADD; code[pc + 1].c = 0
    end
    put_return(code, hot_ops * 2)
end

local function stack_init_int(st)
    st[1].tag = const.Tag.INTEGER; st[1].aux = 0; st[1].bits = BITS_42_INT
    st[2].tag = const.Tag.INTEGER; st[2].aux = 0; st[2].bits = BITS_99_INT
end

local function fill_add_with_mmbin(code, hot_ops)
    for i = 0, hot_ops - 1 do
        local pc = i * 2
        code[pc].op = const.Op.ADD; code[pc].a = 2; code[pc].b = 0; code[pc].c = 1
        code[pc + 1].op = const.Op.MMBIN; code[pc + 1].a = 0; code[pc + 1].b = const.TM.ADD; code[pc + 1].c = 0
    end
    put_return(code, hot_ops * 2)
end

print("Compiling vm_resume runner...")
local runner = moon.func { vm_resume = vm.vm_loop.vm_resume } [[
run(L: ptr(LuaThread), nargs: i32) -> i32
    return region -> i32
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

local STEPS = tonumber(os.getenv("MOONLIFT_VM_STEPS")) or 10000
local RUNS = tonumber(os.getenv("MOONLIFT_VM_RUNS")) or 1000
local RETURN_RUNS = tonumber(os.getenv("MOONLIFT_VM_RETURN_RUNS")) or math.max(RUNS, 100000)
local COMPARE_REFS = os.getenv("MOONLIFT_VM_COMPARE_REFS") ~= "0"

local cases = {
    make_thread({ name = "RETURN", group = "overhead", hot_ops = 0, code_slots = 1, exec_dispatches = 1, fill = fill_return_only, maxstack = 2 }),
    make_thread({ name = "LOADI", group = "load", hot_ops = STEPS, fill = fill_loadi, maxstack = 2, ref = "LOADK" }),
    make_thread({ name = "LOADK", group = "load", hot_ops = STEPS, fill = fill_loadk, maxstack = 2, ref = "LOADK" }),
    make_thread({ name = "MOVE", group = "move", hot_ops = STEPS, fill = fill_move_self, maxstack = 2, ref = "MOVE" }),
    make_thread({ name = "ADD", group = "arith", hot_ops = STEPS, code_slots = STEPS * 2 + 1, exec_dispatches = STEPS + 1, fill = fill_add_with_mmbin, maxstack = 4, ref = "ADD" }),
    make_thread({ name = "ADD_int", group = "arith", hot_ops = STEPS, code_slots = STEPS * 2 + 1, exec_dispatches = STEPS + 1, fill = fill_add_int_mmbin, stack_init = stack_init_int, maxstack = 4, ref = "ADD" }),
}

local function verify(case)
    reset(case)
    local nres = run(case.thread, 0)
    assert(nres == 1, case.name .. ": expected nres=1, got " .. tostring(nres))
    local tag = case.stack[1].tag
    assert(tag == const.Tag.NUM or tag == const.Tag.INTEGER,
        case.name .. ": expected numeric result tag, got " .. tostring(tag))
    if tag == const.Tag.NUM then
        local v = bits_double(case.stack[1].bits)
        assert(math.abs(v - 42.0) < 0.001, case.name .. ": expected numeric 42, got " .. tostring(v))
    else
        local v = tonumber(ffi.cast("int64_t", case.stack[1].bits))
        assert(v == 42, case.name .. ": expected integer 42, got " .. tostring(v))
    end
    reset(case)
end

local function bench(case, runs)
    verify(case)
    for _ = 1, 5 do
        run(case.thread, 0)
        reset(case)
    end
    local t0 = os.clock()
    for _ = 1, runs do
        run(case.thread, 0)
        reset(case)
    end
    return os.clock() - t0
end

local function fmt_num(x, w, digits)
    if not x or x ~= x or x == math.huge then return string.format("%" .. w .. "s", "n/a") end
    return string.format("%" .. w .. "." .. (digits or 2) .. "f", x)
end

local function fmt_speed(x)
    if not x or x ~= x or x == math.huge then return "   n/a" end
    return string.format("%6.2fx", x)
end

local function line(char, n)
    print(string.rep(char or "-", n or 118))
end

local return_elapsed = bench(cases[1], RETURN_RUNS)
local return_ns_per_resume = (return_elapsed / RETURN_RUNS) * 1e9

local results = {}
local by_name = {}
results[#results + 1] = {
    case = cases[1], runs = RETURN_RUNS, elapsed = return_elapsed,
    ns_run = return_ns_per_resume, naive_ns = return_ns_per_resume,
    adjusted_ns = nil, mops = nil,
}
by_name.RETURN = results[1]

for i = 2, #cases do
    local case = cases[i]
    local elapsed = bench(case, RUNS)
    local ns_run = (elapsed / RUNS) * 1e9
    local naive_ns = (elapsed / (RUNS * case.exec_dispatches)) * 1e9
    local adjusted_ns = math.max(0, (ns_run - return_ns_per_resume) / case.hot_ops)
    local row = {
        case = case,
        runs = RUNS,
        elapsed = elapsed,
        ns_run = ns_run,
        naive_ns = naive_ns,
        adjusted_ns = adjusted_ns,
        mops = adjusted_ns > 0 and (1000 / adjusted_ns) or nil,
    }
    results[#results + 1] = row
    by_name[case.name] = row
end

print(string.format("\nMoonlift Lua VM steady-state benchmark"))
print(string.format("Config: STEPS=%d  RUNS=%d  RETURN_RUNS=%d  compare_refs=%s", STEPS, RUNS, RETURN_RUNS, tostring(COMPARE_REFS)))
print(string.format("RETURN-only overhead: %.2f ns/resume (%.4fs / %d runs)", return_ns_per_resume, return_elapsed, RETURN_RUNS))

line("-")
print(string.format("%-14s %8s %11s %12s %12s %12s %12s %10s",
    "case", "hot_ops", "dispatches", "elapsed(s)", "ns/run", "naive ns/d", "hot ns/op", "Mop/s"))
line("-")
for _, r in ipairs(results) do
    local c = r.case
    print(string.format("%-14s %8d %11d %12.4f %12.2f %12.2f %12s %10s",
        c.name,
        c.hot_ops,
        c.exec_dispatches,
        r.elapsed,
        r.ns_run,
        r.naive_ns,
        r.adjusted_ns and string.format("%.2f", r.adjusted_ns) or "overhead",
        r.mops and string.format("%.1f", r.mops) or "n/a"))
end
line("-")

local refs = {}
if COMPARE_REFS then
    local ref_specs = {
        LOADK = "local a=0; for i=1,N do a=42 end",
        MOVE = "local a,b=42,99; for i=1,N do a=b end",
        ADD = "local a,b,c=42,42,0; for i=1,N do c=a+b end",
    }
    local function write_ref(name, body)
        local path = "/tmp/moonlift_vm_ref_" .. name .. ".lua"
        local f = assert(io.open(path, "w"))
        f:write(string.format([[local N=%d
local R=%d
local t0=os.clock()
for r=1,R do
  %s
end
local e=os.clock()-t0
print((e/(R*N))*1e9)
]], STEPS, RUNS, body))
        f:close()
        return path
    end
    local function read_num(cmd)
        local p = io.popen(cmd)
        if not p then return nil end
        local out = p:read("*a")
        p:close()
        return tonumber(out)
    end
    for name, body in pairs(ref_specs) do
        local path = write_ref(name, body)
        refs[name] = {
            luajit = read_num("luajit -joff " .. path .. " 2>/dev/null"),
            lua = read_num("lua " .. path .. " 2>/dev/null"),
        }
    end

    print("\nReference-loop comparison (ref ns/op / VM hot ns/op; >1 means VM faster):")
    line("-", 118)
    print(string.format("%-14s %-8s %12s %12s %12s %12s %12s",
        "case", "ref", "VM ns/op", "LuaJIT ns", "VM/LJIT", "PUC ns", "VM/PUC"))
    line("-", 118)
    for _, r in ipairs(results) do
        local c = r.case
        if c.ref and r.adjusted_ns then
            local ref = refs[c.ref] or {}
            local lj_speed = ref.luajit and r.adjusted_ns > 0 and (ref.luajit / r.adjusted_ns) or nil
            local lua_speed = ref.lua and r.adjusted_ns > 0 and (ref.lua / r.adjusted_ns) or nil
            print(string.format("%-14s %-8s %12s %12s %12s %12s %12s",
                c.name,
                c.ref,
                fmt_num(r.adjusted_ns, 12, 2),
                fmt_num(ref.luajit, 12, 2),
                fmt_speed(lj_speed),
                fmt_num(ref.lua, 12, 2),
                fmt_speed(lua_speed)))
        end
    end
    line("-", 118)
end

runner:free()
