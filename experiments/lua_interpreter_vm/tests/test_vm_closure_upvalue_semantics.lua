-- Closure/upvalue execution semantics for the Moonlift Lua VM.
-- Covers OP_CLOSURE allocation, open upvalue capture, GETUPVAL, RETURN with
-- close-upvalues, and a closure surviving its defining frame.

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local moon = require("moonlift")
local vm = require("experiments.lua_interpreter_vm.src.init")
local const = vm.const
local bytecode = vm.bytecode

local libmoon
for _, p in ipairs({ "libmoonlift", "./target/release/libmoonlift.so", "./target/debug/libmoonlift.so" }) do
    local ok, lib = pcall(ffi.load, p)
    if ok then libmoon = lib; break end
end
if not libmoon then error("could not load libmoonlift; build with cargo build --release") end

ffi.cdef [[
void* malloc(size_t size);
void free(void* ptr);
void* moonlift_scratch_raw(int slot, int elem_size, int count);
typedef struct GCHeader { struct GCHeader* next; uint8_t tt; uint8_t marked; } GCHeader;
typedef struct Value { uint32_t tag; uint32_t aux; uint64_t bits; } Value;
typedef struct Instr { uint32_t word; } Instr;
typedef struct String { GCHeader gc; uint8_t reserved; uint32_t hash; uint64_t len; uint8_t* bytes; } String;
typedef struct Node { Value key; Value value; struct Node* next; } Node;
typedef struct Table { GCHeader gc; uint32_t flags; uint64_t array_len; uint64_t array_cap; Value* array; uint32_t node_mask; uint64_t node_count; Node* nodes; Node* lastfree; struct Table* metatable; uint32_t shape_epoch; GCHeader* weak_next; uint8_t finalizer_state; uint8_t reserved; } Table;
typedef struct UpValDesc { String* name; uint8_t instack; uint16_t index; } UpValDesc;
typedef struct Proto {
    GCHeader gc;
    Instr* code; uint64_t code_len;
    Value* constants; uint64_t constants_len;
    struct Proto** children; uint64_t children_len;
    int32_t* lineinfo; uint64_t lineinfo_len;
    void* locvars; uint64_t locvars_len;
    UpValDesc* upvals; uint64_t upvals_len;
    String* source;
    int32_t linedefined; int32_t lastlinedefined;
    uint8_t numparams; uint8_t flag; uint16_t maxstack;
} Proto;
typedef struct UpVal { GCHeader gc; Value* v; Value closed; uint64_t stack_index; struct UpVal* next_open; } UpVal;
typedef struct LClosure { GCHeader gc; void* env; Proto* proto; UpVal** upvals; uint8_t nupvals; } LClosure;
typedef struct {
    uint16_t kind;
    uint16_t a; uint16_t b; uint16_t c;
    uint64_t pc; uint64_t base; uint64_t result_base; uint64_t call_top;
    int32_t wanted;
    Value value;
    uint64_t errfunc_slot;
} ResumeState;
typedef struct Frame {
    Value closure; uint64_t base; uint64_t top; uint64_t pc;
    int32_t wanted; int32_t tailcalls;
    uint64_t result_base; uint64_t call_top;
    ResumeState resume;
    uint8_t yieldable; uint8_t flags; uint16_t reserved;
} Frame;
typedef struct Allocator { uint32_t abi_version; uint32_t flags; uint8_t* userdata; uint8_t* alloc; uint8_t* realloc; uint8_t* free; } Allocator;
typedef struct LuaThread LuaThread;
typedef struct FinalizerQueue { GCHeader* eligible; GCHeader* pending; GCHeader* running; } FinalizerQueue;
typedef struct StringTable { void* buckets; uint64_t bucket_count; uint64_t nuse; } StringTable;
typedef struct GlobalState {
    Allocator* allocator; Value registry; LuaThread* mainthread;
    GCHeader* allgc; GCHeader* gray; GCHeader* grayagain;
    GCHeader* weak_values; GCHeader* weak_keys; GCHeader* ephemeron; GCHeader* all_weak;
    FinalizerQueue finalizers; GCHeader** sweep_cursor; StringTable* string_table; void* tmname;
    uint8_t currentwhite; uint8_t gcstate;
    uint64_t totalbytes; uint64_t estimate; uint64_t threshold; uint64_t gcdebt;
    int32_t gcpause; int32_t gcstepmul; Value panic;
    uint32_t vm_abi_version; uint32_t native_abi_version;
} GlobalState;
struct LuaThread {
    GCHeader gc; uint8_t status;
    Value* stack; uint64_t stack_size; uint64_t top;
    Frame* frames; uint64_t frame_count; uint64_t frame_cap;
    UpVal* open_upvals; void* protected_top;
    GlobalState* global; Value err_value;
    uint8_t hookmask; uint8_t allowhook;
    int32_t hookcount; int32_t basehookcount; Value hook;
    uint64_t tbc_head;
    int32_t yieldable; int32_t nonyieldable; int32_t last_error_code; uint32_t flags;
};
]]

local scratch_raw = libmoon.moonlift_scratch_raw
local NEXT_SLOT = 700
local function scratch(elem_size, count, ctype)
    local slot = NEXT_SLOT
    NEXT_SLOT = NEXT_SLOT + 1
    return ffi.cast(ctype, scratch_raw(slot, elem_size, count))
end

local function setnil(v) v.tag = const.Tag.NIL; v.aux = 0; v.bits = 0 end
local function setint(v, x) v.tag = const.Tag.INTEGER; v.aux = 0; v.bits = ffi.cast("uint64_t", x) end
local function setclosure(v, cl) v.tag = const.Tag.LCLOSURE; v.aux = 0; v.bits = ffi.cast("uint64_t", cl) end
local function settable(v, t) v.tag = const.Tag.TABLE; v.aux = 0; v.bits = ffi.cast("uint64_t", t) end
local function setstr(v, s) v.tag = const.Tag.STR; v.aux = 0; v.bits = ffi.cast("uint64_t", s) end
local function bits_i64(x) return tonumber(ffi.cast("int64_t", x)) end
local function set_ABC(i, op, a, b, c, k) i.word = bytecode.encode_ABC(op, a, b, c, k) end
local function set_AsBx(i, op, a, sbx) i.word = bytecode.encode_AsBx(op, a, sbx) end
local function set_ABx(i, op, a, bx) i.word = bytecode.encode_ABx(op, a, bx) end

local realloc_cb = ffi.cast("uint64_t (*)(uint8_t*, uint64_t, uint64_t, uint64_t)",
    function(old, old_size, new_size, align)
        if new_size == 0 then
            if old ~= nil then ffi.C.free(old) end
            return ffi.cast("uint64_t", 0)
        end
        local p = ffi.C.malloc(tonumber(new_size))
        if p == nil then return ffi.cast("uint64_t", 0) end
        return ffi.cast("uint64_t", ffi.cast("uintptr_t", p))
    end)

local runner = moon.func {
    vm_resume = vm.vm_loop.vm_resume,
    sys_realloc = vm.regions_allocator.sys_realloc,
} [[
run(L: ptr(LuaThread)): i32
    return region: i32
    entry start()
        emit @{vm_resume}(L, 0;
            ok = done,
            yielded = yielded,
            runtime_error = err,
            oom = oom)
    end
    block done(nres: i32) return nres end
    block yielded(nres: i32) return -100 - nres end
    block err(code: i32) return -200 - code end
    block oom() return -999 end
    end
end
]]:compile()

local function make_proto(ncode, maxstack, nchildren, nup, nconst)
    local p = scratch(ffi.sizeof("Proto"), 1, "Proto*")
    local code = scratch(ffi.sizeof("Instr"), ncode, "Instr*")
    local children = nchildren and nchildren > 0 and scratch(ffi.sizeof("Proto*"), nchildren, "Proto**") or nil
    local upvals = nup and nup > 0 and scratch(ffi.sizeof("UpValDesc"), nup, "UpValDesc*") or nil
    local consts = nconst and nconst > 0 and scratch(ffi.sizeof("Value"), nconst, "Value*") or nil
    if consts ~= nil then for i = 0, nconst - 1 do setnil(consts[i]) end end
    p.code = code; p.code_len = ncode
    p.constants = consts; p.constants_len = nconst or 0
    p.children = children; p.children_len = nchildren or 0
    p.lineinfo = nil; p.lineinfo_len = 0; p.locvars = nil; p.locvars_len = 0
    p.upvals = upvals; p.upvals_len = nup or 0
    p.source = nil; p.linedefined = -1; p.lastlinedefined = -1
    p.numparams = 0; p.flag = 0; p.maxstack = maxstack
    return p, code, children, upvals, consts
end

local function make_thread(root_proto)
    local root_cl = scratch(ffi.sizeof("LClosure"), 1, "LClosure*")
    root_cl.env = nil; root_cl.proto = root_proto; root_cl.upvals = nil; root_cl.nupvals = 0
    local stack = scratch(ffi.sizeof("Value"), 64, "Value*")
    for i = 0, 63 do setnil(stack[i]) end
    setclosure(stack[0], root_cl)
    local frames = scratch(ffi.sizeof("Frame"), 8, "Frame*")
    frames[0].closure = stack[0]
    frames[0].base = 1; frames[0].top = 1; frames[0].pc = 0; frames[0].wanted = 1; frames[0].tailcalls = 0
    frames[0].result_base = 1; frames[0].call_top = 1
    frames[0].resume.kind = const.Resume.NORMAL; frames[0].resume.result_base = 1; frames[0].resume.call_top = 1; frames[0].resume.wanted = 1
    setnil(frames[0].resume.value)
    frames[0].yieldable = 1; frames[0].flags = 0; frames[0].reserved = 0
    local alloc = scratch(ffi.sizeof("Allocator"), 1, "Allocator*")
    alloc.realloc = ffi.cast("uint8_t*", realloc_cb)
    local G = scratch(ffi.sizeof("GlobalState"), 1, "GlobalState*")
    G.allocator = alloc; G.threshold = 1024 * 1024; G.totalbytes = 0; G.currentwhite = 0; G.vm_abi_version = const.Abi.VM_VERSION; G.native_abi_version = const.Abi.NATIVE_VERSION
    G.allgc = nil; G.gray = nil; G.grayagain = nil; G.weak_values = nil; G.weak_keys = nil; G.ephemeron = nil; G.all_weak = nil
    setnil(G.registry)
    local L = scratch(ffi.sizeof("LuaThread"), 1, "LuaThread*")
    L.status = const.Status.OK; L.stack = stack; L.stack_size = 64; L.top = 1
    L.frames = frames; L.frame_count = 1; L.frame_cap = 8; L.open_upvals = nil; L.protected_top = nil; L.global = G
    setnil(L.err_value); L.yieldable = 1; L.nonyieldable = 0; L.last_error_code = 0; L.flags = 0
    G.mainthread = L
    return L, stack
end

local pass, fail = 0, 0
local function check(name, cond, msg)
    if cond then pass = pass + 1; print("  PASS " .. name)
    else fail = fail + 1; print("  FAIL " .. name .. (msg and (": " .. msg) or "")) end
end

print("=== VM closure/upvalue semantics ===\n")

-- Direct open-upvalue capture: parent creates child closure and calls it before returning.
do
    local child, child_code, _, child_uv = make_proto(2, 2, 0, 1)
    child_uv[0].instack = 1; child_uv[0].index = 0
    set_ABC(child_code[0], const.Op.GETUPVAL, 0, 0, 0, 0)
    set_ABC(child_code[1], const.Op.RETURN1, 0, 0, 0, 0)

    local root, root_code, root_children = make_proto(5, 4, 1, 0)
    root_children[0] = child
    set_AsBx(root_code[0], const.Op.LOADI, 0, 41)
    set_ABx(root_code[1], const.Op.CLOSURE, 1, 0)
    set_ABC(root_code[2], const.Op.CALL, 1, 1, 2, 0)
    set_ABC(root_code[3], const.Op.MOVE, 0, 1, 0, 0)
    set_ABC(root_code[4], const.Op.RETURN1, 0, 0, 0, 0)

    local L, stack = make_thread(root)
    local n = runner(L)
    check("OP_CLOSURE captures open stack upvalue", n == 1 and stack[1].tag == const.Tag.INTEGER and bits_i64(stack[1].bits) == 41,
          "n=" .. tostring(n) .. " tag=" .. tostring(stack[1].tag) .. " err=" .. tostring(L.last_error_code))
end

-- Closed-upvalue survival: root calls a factory, factory returns child closure
-- with RETURN k=1, then root calls that returned closure after factory frame is gone.
do
    local child, child_code, _, child_uv = make_proto(2, 2, 0, 1)
    child_uv[0].instack = 1; child_uv[0].index = 0
    set_ABC(child_code[0], const.Op.GETUPVAL, 0, 0, 0, 0)
    set_ABC(child_code[1], const.Op.RETURN1, 0, 0, 0, 0)

    local factory, factory_code, factory_children = make_proto(3, 3, 1, 0)
    factory_children[0] = child
    set_AsBx(factory_code[0], const.Op.LOADI, 0, 41)
    set_ABx(factory_code[1], const.Op.CLOSURE, 1, 0)
    set_ABC(factory_code[2], const.Op.RETURN, 1, 2, 0, 1) -- k closes TBC too; returns also close upvalues

    local root, root_code, root_children = make_proto(4, 4, 1, 0)
    root_children[0] = factory
    set_ABx(root_code[0], const.Op.CLOSURE, 0, 0)
    set_ABC(root_code[1], const.Op.CALL, 0, 1, 2, 0)
    set_ABC(root_code[2], const.Op.CALL, 0, 1, 2, 0)
    set_ABC(root_code[3], const.Op.RETURN1, 0, 0, 0, 0)

    local L, stack = make_thread(root)
    local n = runner(L)
    check("closed upvalue survives defining frame", n == 1 and stack[1].tag == const.Tag.INTEGER and bits_i64(stack[1].bits) == 41,
          "n=" .. tostring(n) .. " tag=" .. tostring(stack[1].tag) .. " value=" .. tostring(bits_i64(stack[1].bits)) .. " err=" .. tostring(L.last_error_code))
end

-- Vararg functions keep extra arguments in the incoming frame and OP_VARARG
-- copies from after fixed parameters.
do
    local varp, var_code = make_proto(2, 4, 0, 0)
    varp.flag = const.ProtoFlag.PF_VAHID
    varp.numparams = 1
    set_ABC(var_code[0], const.Op.VARARG, 0, 0, 2, 0) -- first vararg into R0
    set_ABC(var_code[1], const.Op.RETURN1, 0, 0, 0, 0)

    local root, root_code, root_children = make_proto(6, 6, 1, 0)
    root_children[0] = varp
    set_ABx(root_code[0], const.Op.CLOSURE, 0, 0)
    set_AsBx(root_code[1], const.Op.LOADI, 1, 10) -- fixed param
    set_AsBx(root_code[2], const.Op.LOADI, 2, 20) -- vararg #1
    set_AsBx(root_code[3], const.Op.LOADI, 3, 30) -- vararg #2
    set_ABC(root_code[4], const.Op.CALL, 0, 4, 2, 0)
    set_ABC(root_code[5], const.Op.RETURN1, 0, 0, 0, 0)

    local L, stack = make_thread(root)
    local n = runner(L)
    check("OP_VARARG copies after fixed params", n == 1 and stack[1].tag == const.Tag.INTEGER and bits_i64(stack[1].bits) == 20,
          "n=" .. tostring(n) .. " tag=" .. tostring(stack[1].tag) .. " value=" .. tostring(bits_i64(stack[1].bits)) .. " err=" .. tostring(L.last_error_code))
end

-- __call metamethod makes table values callable through the same call/return path.
do
    local callee, callee_code = make_proto(2, 2, 0, 0)
    set_AsBx(callee_code[0], const.Op.LOADI, 0, 77)
    set_ABC(callee_code[1], const.Op.RETURN1, 0, 0, 0, 0)
    local call_cl = scratch(ffi.sizeof("LClosure"), 1, "LClosure*")
    call_cl.env = nil; call_cl.proto = callee; call_cl.upvals = nil; call_cl.nupvals = 0

    local name_bytes = scratch(1, 6, "uint8_t*")
    ffi.copy(name_bytes, "__call", 6)
    local name = scratch(ffi.sizeof("String"), 1, "String*")
    name.len = 6; name.bytes = name_bytes; name.hash = 0
    local tmnames = scratch(ffi.sizeof("String*"), const.TM.N, "String**")
    for i = 0, const.TM.N - 1 do tmnames[i] = nil end
    tmnames[const.TM.CALL] = name

    local mt_nodes = scratch(ffi.sizeof("Node"), 1, "Node*")
    setstr(mt_nodes[0].key, name); setclosure(mt_nodes[0].value, call_cl); mt_nodes[0].next = nil
    local mt = scratch(ffi.sizeof("Table"), 1, "Table*")
    mt.array_len = 0; mt.array_cap = 0; mt.array = nil; mt.node_mask = 0; mt.node_count = 1; mt.nodes = mt_nodes; mt.metatable = nil
    local obj = scratch(ffi.sizeof("Table"), 1, "Table*")
    obj.array_len = 0; obj.array_cap = 0; obj.array = nil; obj.node_mask = 0; obj.node_count = 0; obj.nodes = nil; obj.metatable = mt

    local root, root_code, _, _, consts = make_proto(3, 4, 0, 0, 1)
    settable(consts[0], obj)
    set_ABx(root_code[0], const.Op.LOADK, 0, 0)
    set_ABC(root_code[1], const.Op.CALL, 0, 1, 2, 0)
    set_ABC(root_code[2], const.Op.RETURN1, 0, 0, 0, 0)

    local L, stack = make_thread(root)
    L.global.tmname = ffi.cast("void*", tmnames)
    local n = runner(L)
    check("table __call metamethod dispatches through prepare_call", n == 1 and stack[1].tag == const.Tag.INTEGER and bits_i64(stack[1].bits) == 77,
          "n=" .. tostring(n) .. " tag=" .. tostring(stack[1].tag) .. " value=" .. tostring(bits_i64(stack[1].bits)) .. " err=" .. tostring(L.last_error_code))
end

runner:free()
realloc_cb:free()

print(string.format("\n=== %d/%d passed ===", pass, pass + fail))
assert(fail == 0)
return true
