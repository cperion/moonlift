-- Lua Interpreter VM — Data type tree (products)
-- Moonlift-native runtime products. PUC Lua is an oracle only; no PUC layouts
-- are imported here.

local moon = require("moonlift")
local host = require("moonlift.host")

-- 1. Core value type. This is ABI storage; consumers decode through value
-- protocol regions rather than switching on unvalidated tags ad hoc.
local Value = host.struct [[struct Value tag: u32; aux: u32; bits: u64 end]]

-- 2. GC header for all collectable objects.
local GCHeader = host.struct [[struct GCHeader next: ptr(GCHeader); tt: u8; marked: u8 end]]

-- 3. Table hash chain node.
local Node = host.struct [[struct Node key: Value; value: Value; next: ptr(Node) end]]

-- 4. String (interned).
local String = host.struct [[struct String gc: GCHeader; reserved: u8; hash: u32; len: index; bytes: ptr(u8) end]]

-- 5. Table. Weak/finalizer/cache states are represented in this Moonlift
-- product instead of hidden GC-side PUC lists.
local Table = host.struct [[struct Table gc: GCHeader; flags: u32; array_len: index; array_cap: index; array: ptr(Value); node_mask: u32; node_count: index; nodes: ptr(Node); lastfree: ptr(Node); metatable: ptr(Table); shape_epoch: u32; weak_next: ptr(GCHeader); finalizer_state: u8; reserved: u8 end]]

-- 6. Instruction (Lua 5.5 compact 32-bit word).
local Instr = host.struct [[struct Instr word: u32 end]]

-- 7. Local variable descriptor.
local LocVar = host.struct [[struct LocVar name: ptr(String); startpc: index; endpc: index end]]

-- 8. Upvalue descriptor.
local UpValDesc = host.struct [[struct UpValDesc name: ptr(String); instack: u8; index: u16 end]]

-- 9. Prototype (compiled function).
local Proto = host.struct [[struct Proto gc: GCHeader; code: ptr(Instr); code_len: index; constants: ptr(Value); constants_len: index; children: ptr(ptr(Proto)); children_len: index; lineinfo: ptr(i32); lineinfo_len: index; locvars: ptr(LocVar); locvars_len: index; upvals: ptr(UpValDesc); upvals_len: index; source: ptr(String); linedefined: i32; lastlinedefined: i32; numparams: u8; flag: u8; maxstack: u16 end]]

-- 10. Upvalue (open or closed).
local UpVal = host.struct [[struct UpVal gc: GCHeader; v: ptr(Value); closed: Value; stack_index: index; next_open: ptr(UpVal) end]]

-- 11. Lua closure.
local LClosure = host.struct [[struct LClosure gc: GCHeader; env: ptr(Table); proto: ptr(Proto); upvals: ptr(ptr(UpVal)); nupvals: u8 end]]

-- 12. Native function descriptor and explicit native ABI result.
local NativeFunc = host.struct [[struct NativeFunc abi_version: u32; flags: u32; addr: ptr(u8); name: ptr(String) end]]
local NativeCallResult = host.struct [[struct NativeCallResult status: u8; nresults: i32; err: Value; stack_needed: index; continuation: ptr(u8) end]]

-- 13. C closure (native function with upvalues).
local CClosure = host.struct [[struct CClosure gc: GCHeader; env: ptr(Table); fn: ptr(NativeFunc); upvals: ptr(Value); nupvals: u8 end]]

-- 14. Userdata. Payload ownership/alignment/user-values are explicit VM
-- semantics, not inherited C layout facts.
local UserData = host.struct [[struct UserData gc: GCHeader; metatable: ptr(Table); env: ptr(Table); len: index; data: ptr(u8); align: u32; flags: u8; finalizer_state: u8; user_values: ptr(Value); user_values_len: index end]]

-- 15. Inline cache (reserved, unused until interpreter contract gates pass).
local InlineCache = host.struct [[struct InlineCache epoch: u32; aux0: u32; aux1: u32; key: Value; value: Value end]]

-- 16. Quickened instruction (reserved, unused).
local QuickInstr = host.struct [[struct QuickInstr instr: Instr; cache: InlineCache end]]

-- 17. Debug info record.
local DebugInfo = host.struct [[struct DebugInfo event: i32; name: ptr(String); namewhat: ptr(String); what: ptr(String); source: ptr(String); currentline: i32; nups: i32; frame_index: index end]]

-- 18. ApiIndex (decoded stack index).
local ApiIndex = host.struct [[struct ApiIndex absolute: index end]]

-- 19. Allocator hook table.
local Allocator = host.struct [[struct Allocator abi_version: u32; flags: u32; userdata: ptr(u8); alloc: ptr(u8); realloc: ptr(u8); free: ptr(u8) end]]

-- 20. Persisted suspended-control state. Frame.resume is the single storage
-- location for control that must be resumed later.
local ResumeState = host.struct [[struct ResumeState kind: u16; a: u16; b: u16; c: u16; pc: index; base: index; result_base: index; call_top: index; wanted: i32; value: Value; errfunc_slot: index end]]

-- 21. Native call context. This is the only value that crosses the VM loop
-- native-call continuation; raw resume modes are not part of that protocol.
local NativeCallContext = host.struct [[struct NativeCallContext func_slot: index; nargs: i32; wanted: i32; result_base: index; stack_top: index; yieldable: u8; reserved: u8; resume: ResumeState end]]

-- 22. Protected frame (replaces setjmp/longjmp with explicit state).
local ProtectedFrame = host.struct [[struct ProtectedFrame status: u8; flags: u8; saved_frame_count: index; frame_index: index; stack_top: index; handler_slot: index; errfunc_slot: index; resume: ResumeState; previous: ptr(ProtectedFrame) end]]

-- 23. Coroutine suspended state.
local CoroutineState = host.struct [[struct CoroutineState caller: ptr(LuaThread); nresults: i32; resume: ResumeState end]]

-- 24. Finalizer queues, expressed with Moonlift objects rather than PUC list names.
local FinalizerQueue = host.struct [[struct FinalizerQueue eligible: ptr(GCHeader); pending: ptr(GCHeader); running: ptr(GCHeader) end]]

-- 25. Call frame.
local Frame = host.struct [[struct Frame closure: Value; base: index; top: index; pc: index; wanted: i32; tailcalls: i32; result_base: index; call_top: index; resume: ResumeState; yieldable: u8; flags: u8; reserved: u16 end]]

-- 26. String table (hash buckets).
local StringTable = host.struct [[struct StringTable buckets: ptr(ptr(String)); bucket_count: index; nuse: index end]]

-- 26. Global VM state.
local GlobalState = host.struct [[struct GlobalState allocator: ptr(Allocator); registry: Value; mainthread: ptr(LuaThread); allgc: ptr(GCHeader); gray: ptr(GCHeader); grayagain: ptr(GCHeader); weak_values: ptr(GCHeader); weak_keys: ptr(GCHeader); ephemeron: ptr(GCHeader); all_weak: ptr(GCHeader); finalizers: FinalizerQueue; sweep_cursor: ptr(ptr(GCHeader)); string_table: ptr(StringTable); tmname: ptr(ptr(String)); currentwhite: u8; gcstate: u8; totalbytes: index; estimate: index; threshold: index; gcdebt: index; gcpause: i32; gcstepmul: i32; panic: Value; vm_abi_version: u32; native_abi_version: u32 end]]

-- 27. Lua thread (coroutine).
local LuaThread = host.struct [[struct LuaThread gc: GCHeader; status: u8; stack: ptr(Value); stack_size: index; top: index; frames: ptr(Frame); frame_count: index; frame_cap: index; open_upvals: ptr(UpVal); protected_top: ptr(ProtectedFrame); global: ptr(GlobalState); err_value: Value; hookmask: u8; allowhook: u8; hookcount: i32; basehookcount: i32; hook: Value; tbc_head: index; yieldable: i32; nonyieldable: i32; last_error_code: i32; flags: u32; coroutine: CoroutineState end]]

-- NOTE: LuaThread references GlobalState (ptr) and GlobalState references LuaThread (ptr).
-- This circularity works because both are pointer types.

return {
    Value = Value,
    GCHeader = GCHeader,
    Node = Node,
    String = String,
    Table = Table,
    Instr = Instr,
    LocVar = LocVar,
    UpValDesc = UpValDesc,
    Proto = Proto,
    UpVal = UpVal,
    LClosure = LClosure,
    NativeFunc = NativeFunc,
    NativeCallContext = NativeCallContext,
    NativeCallResult = NativeCallResult,
    CClosure = CClosure,
    UserData = UserData,
    InlineCache = InlineCache,
    QuickInstr = QuickInstr,
    DebugInfo = DebugInfo,
    ApiIndex = ApiIndex,
    Allocator = Allocator,
    ResumeState = ResumeState,
    ProtectedFrame = ProtectedFrame,
    CoroutineState = CoroutineState,
    FinalizerQueue = FinalizerQueue,
    Frame = Frame,
    StringTable = StringTable,
    GlobalState = GlobalState,
    LuaThread = LuaThread,
}
