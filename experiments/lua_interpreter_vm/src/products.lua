-- Lua Interpreter VM — Data type tree (products)
-- All struct definitions via moon.struct[[]].
-- Topological order: leaf types first, no forward references.

local moon = require("moonlift")
local host = require("moonlift.host")

-- 1. Core value type
local Value = host.struct [[struct Value tag: u32; aux: u32; bits: u64 end]]

-- 2. GC header for all collectable objects
local GCHeader = host.struct [[struct GCHeader next: ptr(GCHeader); tt: u8; marked: u8 end]]

-- 3. Table hash chain node
local Node = host.struct [[struct Node key: Value; value: Value; next: ptr(Node) end]]

-- 4. String (interned)
local String = host.struct [[struct String gc: GCHeader; reserved: u8; hash: u32; len: index; bytes: ptr(u8) end]]

-- 5. Table
local Table = host.struct [[struct Table gc: GCHeader; flags: u32; array_len: index; array: ptr(Value); node_mask: u32; nodes: ptr(Node); lastfree: ptr(Node); metatable: ptr(Table); shape_epoch: u32 end]]

-- 6. Instruction (decoded, k-bit extracted by loader)
local Instr = host.struct [[struct Instr op: u16; a: u16; b: u16; c: u16; k: u8; bx: u32; sbx: i32 end]]

-- 7. Local variable descriptor
local LocVar = host.struct [[struct LocVar name: ptr(String); startpc: index; endpc: index end]]

-- 8. Upvalue descriptor
local UpValDesc = host.struct [[struct UpValDesc name: ptr(String); instack: u8; index: u16 end]]

-- 9. Prototype (compiled function)
local Proto = host.struct [[struct Proto gc: GCHeader; code: ptr(Instr); code_len: index; constants: ptr(Value); constants_len: index; children: ptr(ptr(Proto)); children_len: index; lineinfo: ptr(i32); lineinfo_len: index; locvars: ptr(LocVar); locvars_len: index; upvals: ptr(UpValDesc); upvals_len: index; source: ptr(String); linedefined: i32; lastlinedefined: i32; numparams: u8; flag: u8; maxstack: u16 end]]

-- 10. Upvalue (open or closed)
local UpVal = host.struct [[struct UpVal gc: GCHeader; v: ptr(Value); closed: Value; stack_index: index; next_open: ptr(UpVal) end]]

-- 11. Lua closure
local LClosure = host.struct [[struct LClosure gc: GCHeader; env: ptr(Table); proto: ptr(Proto); upvals: ptr(ptr(UpVal)); nupvals: u8 end]]

-- 12. Native function descriptor
local NativeFunc = host.struct [[struct NativeFunc addr: ptr(u8); flags: u32 end]]

-- 13. C closure (native function with upvalues)
local CClosure = host.struct [[struct CClosure gc: GCHeader; env: ptr(Table); fn: ptr(NativeFunc); upvals: ptr(Value); nupvals: u8 end]]

-- 14. Userdata
local UserData = host.struct [[struct UserData gc: GCHeader; metatable: ptr(Table); env: ptr(Table); len: index; data: ptr(u8) end]]

-- 15. Inline cache for quickening
local InlineCache = host.struct [[struct InlineCache epoch: u32; aux0: u32; aux1: u32; key: Value; value: Value end]]

-- 16. Quickened instruction
local QuickInstr = host.struct [[struct QuickInstr instr: Instr; cache: InlineCache end]]

-- 17. Debug info record
local DebugInfo = host.struct [[struct DebugInfo event: i32; name: ptr(String); namewhat: ptr(String); what: ptr(String); source: ptr(String); currentline: i32; nups: i32; frame_index: index end]]

-- 18. ApiIndex (decoded stack index)
local ApiIndex = host.struct [[struct ApiIndex absolute: index end]]

-- 19. Allocator (opaque C type)
local Allocator = host.struct [[struct Allocator _opaque: ptr(u8) end]]

-- 19. Protected frame (replaces setjmp)
local ProtectedFrame = host.struct [[struct ProtectedFrame frame_index: index; stack_top: index; handler_slot: index; errfunc_slot: index; previous: ptr(ProtectedFrame) end]]

-- 20. Call frame
local Frame = host.struct [[struct Frame closure: Value; base: index; top: index; pc: index; wanted: i32; tailcalls: i32; resume_mode: u16; resume_a: u16; resume_b: u16; resume_c: u16; resume_pc: index; resume_base: index; resume_value: Value end]]

-- 21. String table (hash buckets)
local StringTable = host.struct [[struct StringTable buckets: ptr(ptr(String)); bucket_count: index; nuse: index end]]

-- 22. Global VM state
local GlobalState = host.struct [[struct GlobalState allocator: ptr(Allocator); registry: Value; mainthread: ptr(LuaThread); allgc: ptr(GCHeader); gray: ptr(GCHeader); grayagain: ptr(GCHeader); weak: ptr(GCHeader); tmudata: ptr(GCHeader); string_table: ptr(StringTable); tmname: ptr(ptr(String)); currentwhite: u8; gcstate: u8; sweep_cursor: ptr(ptr(GCHeader)); totalbytes: index; estimate: index; threshold: index; gcdebt: index; gcpause: i32; gcstepmul: i32; panic: Value end]]

-- 23. Lua thread (coroutine)
local LuaThread = host.struct [[struct LuaThread gc: GCHeader; status: u8; stack: ptr(Value); stack_size: index; top: index; frames: ptr(Frame); frame_count: index; frame_cap: index; open_upvals: ptr(UpVal); protected_top: ptr(ProtectedFrame); global: ptr(GlobalState); err_value: Value; hookmask: u8; allowhook: u8; hookcount: i32; basehookcount: i32; hook: Value; tbc_head: index end]]

-- NOTE: LuaThread references GlobalState (ptr) and GlobalState references LuaThread (ptr).
-- This circularity works because both are pointer types — no forward declaration needed
-- for pointer fields in Moonlift structs.

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
    CClosure = CClosure,
    UserData = UserData,
    InlineCache = InlineCache,
    QuickInstr = QuickInstr,
    DebugInfo = DebugInfo,
    ApiIndex = ApiIndex,
    Allocator = Allocator,
    ProtectedFrame = ProtectedFrame,
    Frame = Frame,
    StringTable = StringTable,
    GlobalState = GlobalState,
    LuaThread = LuaThread,
}
