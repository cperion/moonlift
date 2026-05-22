-- Comparative VM benchmark (Moonlift VM vs LuaJIT -joff vs PUC Lua)

local ffi = require("ffi")

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local moon = require("moonlift")
local vm = require("experiments.lua_interpreter_vm.src.init")
local const = vm.const

ffi.cdef [[
void* moonlift_scratch_raw(int slot, int elem_size, int count);
]]

local function load_moonlift_lib()
    local tried = {}
    for _, name in ipairs({ "./target/release/libmoonlift.so", "./target/debug/libmoonlift.so", "libmoonlift" }) do
        tried[#tried + 1] = name
        local ok, lib = pcall(ffi.load, name)
        if ok then return lib end
    end
    error("could not load libmoonlift; tried: " .. table.concat(tried, ", ") .. "\nBuild first: cargo build --release")
end

local lib = load_moonlift_lib()
local scratch_raw = lib.moonlift_scratch_raw

ffi.cdef [[
typedef struct { void* next; uint8_t tt; uint8_t marked; } GCHeader;
typedef struct { uint32_t tag; uint32_t aux; uint64_t bits; } Value;
typedef struct {
    uint16_t op; uint16_t a; uint16_t b; uint16_t c;
    uint8_t k; uint32_t bx; int32_t sbx;
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
typedef struct { GCHeader gc; void* env; Proto* proto; void** upvals; uint8_t nupvals; } LClosure;
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

local function S(slot, elem_size, count, ctype)
    return ffi.cast(ctype or "uint8_t*", scratch_raw(slot, elem_size, count))
end

local u = ffi.new("union { double d; uint64_t u; }")
local function d2b(x)
    u.d = x
    return u.u
end

local BITS_42 = d2b(42.0)
local BITS_99 = d2b(99.0)

local function build_thread(steps, fill_code, init_stack, code_slots)
    code_slots = code_slots or steps
    local slot = 40 + code_slots

    local consts = S(slot + 0, 16, 2, "Value*")
    consts[0].tag = const.Tag.NUM; consts[0].aux = 0; consts[0].bits = BITS_42
    consts[1].tag = const.Tag.NUM; consts[1].aux = 0; consts[1].bits = BITS_99

    local code = S(slot + 1, ffi.sizeof("Instr"), code_slots + 1, "Instr*")
    for i = 0, code_slots do
        code[i].op = 0; code[i].a = 0; code[i].b = 0; code[i].c = 0; code[i].bx = 0; code[i].sbx = 0
    end
    fill_code(code, steps)
    code[code_slots].op = const.Op.RETURN
    code[code_slots].a = 0
    code[code_slots].b = 2

    local proto = S(slot + 2, 1, 256, "Proto*")
    proto.code = ffi.cast("void*", code); proto.code_len = code_slots + 1
    proto.constants = ffi.cast("void*", consts); proto.constants_len = 2
    proto.maxstack = 4

    local closure = S(slot + 3, 1, 64, "LClosure*")
    closure.proto = proto
    closure.nupvals = 0

    local stack = S(slot + 4, 16, 64, "Value*")
    for i = 0, 63 do
        stack[i].tag = const.Tag.NIL
        stack[i].aux = 0
        stack[i].bits = 0
    end
    stack[0].tag = const.Tag.LCLOSURE
    stack[0].aux = 0
    stack[0].bits = ffi.cast("uint64_t", closure)

    -- Pre-seed register values so arithmetic cases stay on the fast numeric path.
    stack[1].tag = const.Tag.NUM; stack[1].aux = 0; stack[1].bits = BITS_42
    stack[2].tag = const.Tag.NUM; stack[2].aux = 0; stack[2].bits = BITS_99

    if init_stack then
        init_stack(stack)
    end

    local frames = S(slot + 5, 1, 512, "Frame*")
    frames[0].closure.tag = const.Tag.LCLOSURE
    frames[0].closure.aux = 0
    frames[0].closure.bits = ffi.cast("uint64_t", closure)
    frames[0].base = 1
    frames[0].top = 3
    frames[0].pc = 0
    frames[0].wanted = 1
    frames[0].resume_mode = const.Resume.NORMAL

    local gstate = S(slot + 6, 1, 64, "GlobalState*")

    local thread = S(slot + 7, 1, 256, "LuaThread*")
    thread.status = const.Status.OK
    thread.stack = stack
    thread.stack_size = 64
    thread.top = 3
    thread.frames = frames
    thread.frame_count = 1
    thread.frame_cap = 8
    thread.global = gstate

    return thread, stack, frames
end

local function reset(thread, stack, frames)
    thread.status = const.Status.OK
    thread.top = 3
    thread.frame_count = 1

    frames[0].base = 1
    frames[0].top = 3
    frames[0].pc = 0
    frames[0].wanted = 1
    frames[0].resume_mode = const.Resume.NORMAL

    -- restore numeric sources used by arithmetic/move loops
    stack[1].tag = const.Tag.NUM; stack[1].aux = 0; stack[1].bits = BITS_42
    stack[2].tag = const.Tag.NUM; stack[2].aux = 0; stack[2].bits = BITS_99
end

local runner_fn = moon.func { vm_resume = vm.vm_loop.vm_resume } [[
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
]]:compile()

local STEPS = tonumber(os.getenv("MOONLIFT_VM_STEPS")) or 10000
local RUNS = tonumber(os.getenv("MOONLIFT_VM_RUNS")) or 1000

local function run_bench(name, fill_code, init_stack, steps_override, code_slots_override)
    local steps = steps_override or STEPS
    local code_slots = code_slots_override or steps
    local thread, stack, frames = build_thread(steps, fill_code, init_stack, code_slots)

    reset(thread, stack, frames)
    local verify = runner_fn(thread, 0)
    if verify ~= 1 then
        error("verify fail " .. name .. ": expected nres=1, got " .. tostring(verify))
    end

    runner_fn(thread, 0) -- warmup
    reset(thread, stack, frames)

    local t0 = os.clock()
    for _ = 1, RUNS do
        runner_fn(thread, 0)
        reset(thread, stack, frames)
    end
    return os.clock() - t0
end

-- Baseline is pure RETURN (0 hot opcodes), not STEPS copies of opcode 0.
local ret_elapsed = run_bench("RETURN", function() end, nil, 0)
local ret_ns = (ret_elapsed / RUNS) * 1e9

local ops = {
    {
        name = "LOADK",
        ref = "LOADK",
        fill = function(code, steps)
            for i = 0, steps - 1 do
                code[i].op = const.Op.LOADK
                code[i].a = i % 2
                code[i].bx = i % 2
            end
        end,
    },
    {
        name = "MOVE",
        ref = "MOVE",
        fill = function(code, steps)
            for i = 0, steps - 1 do
                code[i].op = const.Op.MOVE
                code[i].a = (i + 1) % 2
                code[i].b = i % 2
            end
        end,
    },
    {
        name = "ADD",
        ref = "ADD",
        code_slots = STEPS * 2,
        fill = function(code, steps)
            for i = 0, steps - 1 do
                local pc = i * 2
                code[pc].op = const.Op.ADD
                -- Lua 5.5 arithmetic instructions skip over the following MMBIN
                -- on the fast path, so lay the stream out as ADD/MMBIN pairs.
                code[pc].a = 2
                code[pc].b = 0
                code[pc].c = 1
                code[pc + 1].op = const.Op.MMBIN
                code[pc + 1].a = 0
                code[pc + 1].b = const.TM.ADD
                code[pc + 1].c = 0
            end
        end,
    },
}

local results = {}
for _, op in ipairs(ops) do
    local elapsed = run_bench(op.name, op.fill, op.init_stack, nil, op.code_slots)
    results[op.name] = math.max(0, ((elapsed / RUNS) * 1e9 - ret_ns) / STEPS)
end

-- Reference scripts (written to files: avoids shell quoting hazards).
local refs = {
    { "LOADK", "local a=0;for i=1,%d do a=42 end" },
    { "MOVE",  "local a,b=42,99;for i=1,%d do a=b end" },
    { "ADD",   "local a,b,c=1,2,0;for i=1,%d do c=a+b end" },
}

for _, spec in ipairs(refs) do
    local path = "/tmp/mlcmp_" .. spec[1] .. ".lua"
    local f = assert(io.open(path, "w"))
    f:write(string.format(
        "local N=%d;local R=%d;local t0=os.clock();for r=1,R do %s end;local e=os.clock()-t0;print((e/(R*N))*1e9)",
        STEPS,
        RUNS,
        string.format(spec[2], STEPS)
    ))
    f:close()
end

local function read_num(cmd)
    local p = io.popen(cmd)
    if not p then return nil end
    local out = p:read("*a")
    p:close()
    return tonumber(out)
end

print(string.format("\nSTEPS=%-8d  RUNS=%-8d\n", STEPS, RUNS))
print(string.rep("-", 80))
print(string.format("%-12s  %12s  %12s  %12s  %-6s", "OP", "Moonlift VM", "LuaJIT -joff", "PUC Lua", "vs LJIT"))
print(string.rep("-", 80))
for _, op in ipairs(ops) do
    local ref = op.ref or op.name
    local ljit = read_num("luajit -joff /tmp/mlcmp_" .. ref .. ".lua 2>/dev/null")
    local lua = read_num("lua /tmp/mlcmp_" .. ref .. ".lua 2>/dev/null")
    local vs = ""
    if ljit and ljit > 0 then
        vs = string.format("%.1fx", results[op.name] / ljit)
    end
    print(string.format("%-12s  %8.2f ns  %8.2f ns  %8.2f ns  %s", op.name, results[op.name], ljit or -1, lua or -1, vs))
end
print(string.rep("-", 80))

runner_fn:free()
