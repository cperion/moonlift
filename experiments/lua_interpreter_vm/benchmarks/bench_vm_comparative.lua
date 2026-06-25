-- Comparative VM benchmark (Lalin VM vs LuaJIT -joff vs PUC Lua)

local ffi = require("ffi")
local bit = require("bit")

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")
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
void* lalin_scratch_raw(int slot, int elem_size, int count);
]]

local function load_lalin_lib()
    local tried = {}
    for _, name in ipairs({ "./target/release/liblalin.so", "./target/debug/liblalin.so", "liblalin" }) do
        tried[#tried + 1] = name
        local ok, lib = pcall(ffi.load, name)
        if ok then return lib end
    end
    error("could not load liblalin; tried: " .. table.concat(tried, ", ") .. "\nBuild first: cargo build --release")
end

local lib = load_lalin_lib()
local scratch_raw = lib.lalin_scratch_raw

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
    uint64_t tbc_head;
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
local BITS_7 = d2b(7.0)

local function set_nil(v) v.tag = const.Tag.NIL; v.aux = 0; v.bits = 0 end
local function set_num(v, bits) v.tag = const.Tag.NUM; v.aux = 0; v.bits = bits end
local function set_int(v, n) v.tag = const.Tag.INTEGER; v.aux = 0; v.bits = ffi.cast("uint64_t", n) end
local function set_bool(v, b) v.tag = b and const.Tag.TRUE or const.Tag.FALSE; v.aux = 0; v.bits = 0 end

local function build_thread(steps, fill_code, init_stack, code_slots, init_consts, maxstack)
    code_slots = code_slots or steps
    local slot = 40 + code_slots

    local consts = S(slot + 0, 16, 4, "Value*")
    set_num(consts[0], BITS_42)
    set_num(consts[1], BITS_99)
    set_num(consts[2], BITS_7)
    set_int(consts[3], 7)
    if init_consts then init_consts(consts) end

    local code = S(slot + 1, ffi.sizeof("Instr"), code_slots + 1, "Instr*")
    for i = 0, code_slots do
        set_ABC(code[i], 0, 0, 0, 0, 0)
    end
    fill_code(code, steps)
    set_ABC(code[code_slots], const.Op.RETURN, 0, 2, 0, 0)

    local proto = S(slot + 2, 1, 256, "Proto*")
    proto.code = ffi.cast("void*", code); proto.code_len = code_slots + 1
    proto.constants = ffi.cast("void*", consts); proto.constants_len = 4
    proto.maxstack = maxstack or 8

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
    set_num(stack[1], BITS_42)
    set_num(stack[2], BITS_99)
    set_num(stack[3], BITS_7)

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
    set_num(stack[1], BITS_42)
    set_num(stack[2], BITS_99)
    set_num(stack[3], BITS_7)
end

local runner_fn = lalin.func { vm_resume = vm.vm_loop.vm_resume } [[
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
]]:compile()

local STEPS = tonumber(os.getenv("LALIN_VM_STEPS")) or 10000
local RUNS = tonumber(os.getenv("LALIN_VM_RUNS")) or 1000

local function run_bench(name, fill_code, init_stack, steps_override, code_slots_override, init_consts, maxstack)
    local steps = steps_override or STEPS
    local code_slots = code_slots_override or steps
    local thread, stack, frames = build_thread(steps, fill_code, init_stack, code_slots, init_consts, maxstack)

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

local function init_int_stack(stack)
    set_int(stack[1], 42)
    set_int(stack[2], 99)
    set_int(stack[3], 7)
end

local function init_bool_stack(stack)
    set_bool(stack[1], true)
    set_bool(stack[2], false)
    set_bool(stack[3], true)
end

local function init_int_consts(consts)
    set_int(consts[0], 42)
    set_int(consts[1], 99)
    set_int(consts[2], 7)
    set_int(consts[3], 2)
end

local function fill_arith_pair(op, tm, a, b, c)
    return function(code, steps)
        for i = 0, steps - 1 do
            local pc = i * 2
            set_ABC(code[pc], op, a or 0, b or 1, c or 2, 0)
            set_ABC(code[pc + 1], const.Op.MMBIN, 0, tm, 0, 0)
        end
    end
end

local function fill_unary(op, a, b)
    return function(code, steps)
        for i = 0, steps - 1 do
            set_ABC(code[i], op, a or 0, b or 1, 0, 0)
        end
    end
end

local ops = {
    -- Loads / register movement.
    {
        name = "LOADI",
        group = "load",
        ref_src = "local a=0;for i=1,%d do a=42 end",
        fill = function(code, steps)
            for i = 0, steps - 1 do set_AsBx(code[i], const.Op.LOADI, 0, 42) end
        end,
    },
    {
        name = "LOADF",
        group = "load",
        ref_src = "local a=0;for i=1,%d do a=42.0 end",
        fill = function(code, steps)
            for i = 0, steps - 1 do set_AsBx(code[i], const.Op.LOADF, 0, 42) end
        end,
    },
    {
        name = "LOADK",
        group = "load",
        ref_src = "local a=0;for i=1,%d do a=42 end",
        fill = function(code, steps)
            for i = 0, steps - 1 do set_ABx(code[i], const.Op.LOADK, 0, i % 2) end
        end,
    },
    {
        name = "LOADKX",
        group = "load",
        code_slots = STEPS * 2,
        ref_src = "local a=0;for i=1,%d do a=42 end",
        fill = function(code, steps)
            for i = 0, steps - 1 do
                local pc = i * 2
                set_ABC(code[pc], const.Op.LOADKX, 0, 0, 0, 0)
                set_ABx(code[pc + 1], const.Op.EXTRAARG, 0, i % 2)
            end
        end,
    },
    {
        name = "LOADBOOL",
        group = "load",
        init_stack = init_bool_stack,
        ref_src = "local a=false;for i=1,%d do a=true end",
        fill = function(code, steps)
            for i = 0, steps - 1 do set_ABC(code[i], const.Op.LOADTRUE, 0, 0, 0, 0) end
        end,
    },
    {
        name = "LOADNIL3",
        group = "load",
        ref_src = "local a,b,c=1,2,3;for i=1,%d do a=nil;b=nil;c=nil end",
        fill = function(code, steps)
            for i = 0, steps - 1 do set_ABC(code[i], const.Op.LOADNIL, 0, 2, 0, 0) end
        end,
    },
    {
        name = "MOVE",
        group = "move",
        ref_src = "local a,b=42,99;for i=1,%d do a=b end",
        fill = function(code, steps)
            for i = 0, steps - 1 do set_ABC(code[i], const.Op.MOVE, 0, 1, 0, 0) end
        end,
    },

    -- Arithmetic fast paths. Lua 5.5 arithmetic skips over the following MMBIN
    -- on success, so each semantic operation occupies two bytecode slots.
    {
        name = "ADD_f64",
        group = "arith",
        code_slots = STEPS * 2,
        ref_src = "local a,b,c=42.0,99.0,0;for i=1,%d do c=a+b end",
        fill = fill_arith_pair(const.Op.ADD, const.TM.ADD, 3, 0, 1),
    },
    {
        name = "ADD_int",
        group = "arith",
        code_slots = STEPS * 2,
        init_stack = init_int_stack,
        init_consts = init_int_consts,
        ref_src = "local a,b,c=42,99,0;for i=1,%d do c=a+b end",
        fill = fill_arith_pair(const.Op.ADD, const.TM.ADD, 3, 0, 1),
    },
    {
        name = "ADDI_int",
        group = "arith",
        code_slots = STEPS * 2,
        init_stack = init_int_stack,
        init_consts = init_int_consts,
        ref_src = "local a,c=42,0;for i=1,%d do c=a+7 end",
        fill = function(code, steps)
            for i = 0, steps - 1 do
                local pc = i * 2
                set_ABC(code[pc], const.Op.ADDI, 3, 0, 7, 0)
                set_ABC(code[pc + 1], const.Op.MMBINI, 3, 7, const.TM.ADD, 0)
            end
        end,
    },
    {
        name = "ADDK_f64",
        group = "arith",
        code_slots = STEPS * 2,
        ref_src = "local a,k,c=42.0,7.0,0;for i=1,%d do c=a+k end",
        fill = function(code, steps)
            for i = 0, steps - 1 do
                local pc = i * 2
                set_ABC(code[pc], const.Op.ADDK, 3, 0, 2, 0)
                set_ABC(code[pc + 1], const.Op.MMBINK, 3, 2, const.TM.ADD, 0)
            end
        end,
    },
    {
        name = "SUB_f64",
        group = "arith",
        code_slots = STEPS * 2,
        ref_src = "local a,b,c=99.0,42.0,0;for i=1,%d do c=a-b end",
        fill = fill_arith_pair(const.Op.SUB, const.TM.SUB, 3, 1, 0),
    },
    {
        name = "MUL_f64",
        group = "arith",
        code_slots = STEPS * 2,
        ref_src = "local a,b,c=42.0,7.0,0;for i=1,%d do c=a*b end",
        fill = fill_arith_pair(const.Op.MUL, const.TM.MUL, 3, 0, 2),
    },
    {
        name = "DIV_f64",
        group = "arith",
        code_slots = STEPS * 2,
        ref_src = "local a,b,c=99.0,7.0,0;for i=1,%d do c=a/b end",
        fill = fill_arith_pair(const.Op.DIV, const.TM.DIV, 3, 1, 2),
    },
    {
        name = "UNM_f64",
        group = "arith",
        ref_src = "local a,c=42.0,0;for i=1,%d do c=-a end",
        fill = fill_unary(const.Op.UNM, 3, 0),
    },
    {
        name = "NOT_bool",
        group = "logic",
        init_stack = init_bool_stack,
        ref_src = "local a,b=false,true;for i=1,%d do a=not b end",
        fill = fill_unary(const.Op.NOT, 3, 0),
    },

    -- Control and comparison. These execute the tested opcode and skip a filler
    -- MOVE so the stream remains straight-line and comparable per semantic op.
    {
        name = "TEST_true",
        group = "control",
        code_slots = STEPS * 2,
        init_stack = init_bool_stack,
        ref_src = "local a=true;for i=1,%d do if a then end end",
        fill = function(code, steps)
            for i = 0, steps - 1 do
                local pc = i * 2
                set_ABC(code[pc], const.Op.TEST, 0, 0, 1, 0)
                set_ABC(code[pc + 1], const.Op.MOVE, 1, 1, 0, 0)
            end
        end,
    },
    {
        name = "EQ_num",
        group = "compare",
        code_slots = STEPS * 2,
        ref_src = "local a=42.0;for i=1,%d do if a==a then end end",
        fill = function(code, steps)
            for i = 0, steps - 1 do
                local pc = i * 2
                set_ABC(code[pc], const.Op.EQ, 1, 1, 1, 0)
                set_ABC(code[pc + 1], const.Op.MOVE, 1, 1, 0, 0)
            end
        end,
    },
    {
        name = "LT_num",
        group = "compare",
        code_slots = STEPS * 2,
        ref_src = "local a,b=42.0,99.0;for i=1,%d do if a<b then end end",
        fill = function(code, steps)
            for i = 0, steps - 1 do
                local pc = i * 2
                set_ABC(code[pc], const.Op.LT, 1, 0, 1, 0)
                set_ABC(code[pc + 1], const.Op.MOVE, 1, 1, 0, 0)
            end
        end,
    },
    {
        name = "JMP_next",
        group = "control",
        ref_src = "for i=1,%d do end",
        fill = function(code, steps)
            for i = 0, steps - 1 do set_AsBx(code[i], const.Op.JMP, 0, 1) end
        end,
    },

    -- Mixed straight-line slices approximate a tiny compiled trace better than
    -- single-op loops while still isolating VM dispatch/interpreter overhead.
    {
        name = "MIX_load_arith",
        group = "mixed",
        code_slots = STEPS * 4,
        divisor = 3,
        ref_src = "local a,b,c=0,0,0;for i=1,%d do a=42;b=7;c=a+b end",
        fill = function(code, steps)
            for i = 0, steps - 1 do
                local pc = i * 4
                set_AsBx(code[pc], const.Op.LOADI, 1, 42)
                set_AsBx(code[pc + 1], const.Op.LOADI, 2, 7)
                set_ABC(code[pc + 2], const.Op.ADD, 3, 1, 2, 0)
                set_ABC(code[pc + 3], const.Op.MMBIN, 3, const.TM.ADD, 0, 0)
            end
        end,
    },
    {
        name = "MIX_branch",
        group = "mixed",
        code_slots = STEPS * 2,
        divisor = 2,
        init_stack = init_bool_stack,
        ref_src = "local flag=true;local a,b=1,2;for i=1,%d do if flag then a=b end end",
        fill = function(code, steps)
            for i = 0, steps - 1 do
                local pc = i * 2
                set_ABC(code[pc], const.Op.TEST, 0, 0, 0, 0) -- true path executes MOVE
                set_ABC(code[pc + 1], const.Op.MOVE, 1, 2, 0, 0)
            end
        end,
    },
}

local results = {}
for _, op in ipairs(ops) do
    local elapsed = run_bench(op.name, op.fill, op.init_stack, nil, op.code_slots, op.init_consts, op.maxstack)
    local divisor = op.divisor or 1
    op.semantic_ops = STEPS * divisor
    results[op.name] = ((elapsed / RUNS) * 1e9 - ret_ns) / op.semantic_ops
end

-- Reference scripts (written to files: avoids shell quoting hazards).
for _, op in ipairs(ops) do
    local path = "/tmp/mlcmp_" .. op.name .. ".lua"
    local f = assert(io.open(path, "w"))
    local divisor = op.divisor or 1
    f:write(string.format(
        "local N=%d;local R=%d;local D=%d;local t0=os.clock();for r=1,R do " .. string.format(op.ref_src, STEPS) .. " end;local e=os.clock()-t0;print((e/(R*N*D))*1e9)",
        STEPS,
        RUNS,
        divisor
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
print(string.rep("-", 104))
print(string.format("%-16s  %-8s  %12s  %12s  %12s  %-8s  %-8s", "CASE", "GROUP", "Lalin VM", "LuaJIT -joff", "PUC Lua", "VM/LJ", "VM/PUC"))
print(string.rep("-", 104))
for _, op in ipairs(ops) do
    local ljit = read_num("luajit -joff /tmp/mlcmp_" .. op.name .. ".lua 2>/dev/null")
    local lua = read_num("lua /tmp/mlcmp_" .. op.name .. ".lua 2>/dev/null")
    local vm_ns = results[op.name]
    local vs_lj = (ljit and ljit > 0) and string.format("%.2fx", vm_ns / ljit) or "n/a"
    local vs_lua = (lua and lua > 0) and string.format("%.2fx", vm_ns / lua) or "n/a"
    print(string.format("%-16s  %-8s  %8.2f ns  %8.2f ns  %8.2f ns  %-8s  %-8s",
        op.name, op.group, vm_ns, ljit or -1, lua or -1, vs_lj, vs_lua))
end
print(string.rep("-", 104))
print("VM/LJ and VM/PUC are cost ratios; lower is better for Lalin VM.")
print("Negative VM ns/op means RETURN-overhead subtraction noise; increase LALIN_VM_STEPS/RUNS.")

runner_fn:free()
