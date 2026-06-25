-- Lua Interpreter VM — shared LuaJIT FFI schema for tests/tools.
-- Canonical product definitions live in:
--   experiments/lua_interpreter_vm/src/products.lua
--   experiments/lua_interpreter_vm/src/parser_products.lua
-- Keep this file synchronized with those Lalin product structs; do not add
-- private test-only struct copies elsewhere.

local M = {}

M.cdef = [[
typedef struct Value Value;
typedef struct GCHeader GCHeader;
typedef struct Node Node;
typedef struct String String;
typedef struct Table Table;
typedef struct Instr Instr;
typedef struct LocVar LocVar;
typedef struct UpValDesc UpValDesc;
typedef struct Proto Proto;
typedef struct UpVal UpVal;
typedef struct LClosure LClosure;
typedef struct NativeFunc NativeFunc;
typedef struct NativeCallResult NativeCallResult;
typedef struct NativeCallContext NativeCallContext;
typedef struct CClosure CClosure;
typedef struct UserData UserData;
typedef struct InlineCache InlineCache;
typedef struct QuickInstr QuickInstr;
typedef struct DebugInfo DebugInfo;
typedef struct ApiIndex ApiIndex;
typedef struct Allocator Allocator;
typedef struct ResumeState ResumeState;
typedef struct ProtectedFrame ProtectedFrame;
typedef struct CoroutineState CoroutineState;
typedef struct FinalizerQueue FinalizerQueue;
typedef struct Frame Frame;
typedef struct StringTable StringTable;
typedef struct GlobalState GlobalState;
typedef struct LuaThread LuaThread;

typedef struct SourceSpan SourceSpan;
typedef struct FuncBuilder FuncBuilder;
typedef struct CompileArena CompileArena;
typedef struct IndexVec IndexVec;
typedef struct ParseNode ParseNode;
typedef struct ParseFunction ParseFunction;
typedef struct ParseFrame ParseFrame;
typedef struct ExprOpEntry ExprOpEntry;
typedef struct ExprValEntry ExprValEntry;
typedef struct ParseNodeVec ParseNodeVec;
typedef struct ParseFunctionVec ParseFunctionVec;
typedef struct ParseFrameVec ParseFrameVec;
typedef struct ExprOpVec ExprOpVec;
typedef struct ExprValVec ExprValVec;
typedef struct ScopeRec ScopeRec;
typedef struct SymbolRec SymbolRec;
typedef struct CaptureRec CaptureRec;
typedef struct NameUse NameUse;
typedef struct HirFunction HirFunction;
typedef struct HirBlock HirBlock;
typedef struct HirStmt HirStmt;
typedef struct HirExpr HirExpr;
typedef struct HirFunctionVec HirFunctionVec;
typedef struct HirBlockVec HirBlockVec;
typedef struct HirStmtVec HirStmtVec;
typedef struct HirExprVec HirExprVec;
typedef struct ScopeVec ScopeVec;
typedef struct SymbolVec SymbolVec;
typedef struct CaptureVec CaptureVec;
typedef struct NameUseVec NameUseVec;
typedef struct SemanticFrame SemanticFrame;
typedef struct SemanticFrameVec SemanticFrameVec;
typedef struct LowerFrame LowerFrame;
typedef struct LowerScope LowerScope;
typedef struct PatchRec PatchRec;
typedef struct ExprSlot ExprSlot;
typedef struct LowerFrameVec LowerFrameVec;
typedef struct LowerScopeVec LowerScopeVec;
typedef struct PatchVec PatchVec;
typedef struct ExprSlotVec ExprSlotVec;
typedef struct LabelDesc LabelDesc;
typedef struct LabelPatch LabelPatch;
typedef struct CompileLocal CompileLocal;
typedef struct UpvalueRef UpvalueRef;

typedef struct Value { uint32_t tag; uint32_t aux; uint64_t bits; } Value;
typedef struct GCHeader { GCHeader* next; uint8_t tt; uint8_t marked; } GCHeader;
typedef struct Node { Value key; Value value; Node* next; } Node;
typedef struct String { GCHeader gc; uint8_t reserved; uint32_t hash; uint64_t len; uint8_t* bytes; } String;
typedef struct Table {
    GCHeader gc;
    uint32_t flags;
    uint64_t array_len; uint64_t array_cap; Value* array;
    uint32_t node_mask; uint64_t node_count; Node* nodes; Node* lastfree;
    Table* metatable;
    uint32_t shape_epoch;
    GCHeader* weak_next;
    uint8_t finalizer_state; uint8_t reserved;
} Table;
typedef struct Instr { uint32_t word; } Instr;
typedef struct LocVar { String* name; uint64_t startpc; uint64_t endpc; } LocVar;
typedef struct UpValDesc { String* name; uint8_t instack; uint16_t index; } UpValDesc;
typedef struct Proto {
    GCHeader gc;
    Instr* code; uint64_t code_len;
    Value* constants; uint64_t constants_len;
    Proto** children; uint64_t children_len;
    int32_t* lineinfo; uint64_t lineinfo_len;
    LocVar* locvars; uint64_t locvars_len;
    UpValDesc* upvals; uint64_t upvals_len;
    String* source;
    int32_t linedefined; int32_t lastlinedefined;
    uint8_t numparams; uint8_t flag; uint16_t maxstack;
} Proto;
typedef struct UpVal { GCHeader gc; Value* v; Value closed; uint64_t stack_index; UpVal* next_open; } UpVal;
typedef struct LClosure { GCHeader gc; Table* env; Proto* proto; UpVal** upvals; uint8_t nupvals; } LClosure;
typedef struct NativeFunc { uint32_t abi_version; uint32_t flags; uint8_t* addr; String* name; } NativeFunc;
typedef struct NativeCallResult { uint8_t status; int32_t nresults; Value err; uint64_t stack_needed; uint8_t* continuation; } NativeCallResult;
typedef struct CClosure { GCHeader gc; Table* env; NativeFunc* fn; Value* upvals; uint8_t nupvals; } CClosure;
typedef struct UserData { GCHeader gc; Table* metatable; Table* env; uint64_t len; uint8_t* data; uint32_t align; uint8_t flags; uint8_t finalizer_state; Value* user_values; uint64_t user_values_len; } UserData;
typedef struct InlineCache { uint32_t epoch; uint32_t aux0; uint32_t aux1; Value key; Value value; } InlineCache;
typedef struct QuickInstr { Instr instr; InlineCache cache; } QuickInstr;
typedef struct DebugInfo { int32_t event; String* name; String* namewhat; String* what; String* source; int32_t currentline; int32_t nups; uint64_t frame_index; } DebugInfo;
typedef struct ApiIndex { uint64_t absolute; } ApiIndex;
typedef struct Allocator { uint32_t abi_version; uint32_t flags; uint8_t* userdata; uint8_t* alloc; uint8_t* realloc; uint8_t* free; } Allocator;
typedef struct ResumeState {
    uint16_t kind;
    uint16_t a; uint16_t b; uint16_t c;
    uint64_t pc; uint64_t base; uint64_t result_base; uint64_t call_top;
    int32_t wanted;
    Value value;
    uint64_t errfunc_slot;
} ResumeState;
typedef struct NativeCallContext { uint64_t func_slot; int32_t nargs; int32_t wanted; uint64_t result_base; uint64_t stack_top; uint8_t yieldable; uint8_t reserved; ResumeState resume; } NativeCallContext;
typedef struct ProtectedFrame { uint8_t status; uint8_t flags; uint64_t saved_frame_count; uint64_t frame_index; uint64_t stack_top; uint64_t handler_slot; uint64_t errfunc_slot; ResumeState resume; ProtectedFrame* previous; } ProtectedFrame;
typedef struct CoroutineState { LuaThread* caller; int32_t nresults; ResumeState resume; } CoroutineState;
typedef struct FinalizerQueue { GCHeader* eligible; GCHeader* pending; GCHeader* running; } FinalizerQueue;
typedef struct Frame {
    Value closure; uint64_t base; uint64_t top; uint64_t pc;
    int32_t wanted; int32_t tailcalls;
    uint64_t result_base; uint64_t call_top;
    ResumeState resume;
    uint8_t yieldable; uint8_t flags; uint16_t reserved;
} Frame;
typedef struct StringTable { String** buckets; uint64_t bucket_count; uint64_t nuse; } StringTable;
typedef struct GlobalState {
    Allocator* allocator;
    Value registry;
    LuaThread* mainthread;
    GCHeader* allgc; GCHeader* gray; GCHeader* grayagain;
    GCHeader* weak_values; GCHeader* weak_keys; GCHeader* ephemeron; GCHeader* all_weak;
    FinalizerQueue finalizers;
    GCHeader** sweep_cursor;
    StringTable* string_table;
    String** tmname;
    uint8_t currentwhite; uint8_t gcstate;
    uint64_t totalbytes; uint64_t estimate; uint64_t threshold; uint64_t gcdebt;
    int32_t gcpause; int32_t gcstepmul;
    Value panic;
    uint32_t vm_abi_version; uint32_t native_abi_version;
} GlobalState;
typedef struct LuaThread {
    GCHeader gc; uint8_t status;
    Value* stack; uint64_t stack_size; uint64_t top;
    Frame* frames; uint64_t frame_count; uint64_t frame_cap;
    UpVal* open_upvals; ProtectedFrame* protected_top;
    GlobalState* global; Value err_value;
    uint8_t hookmask; uint8_t allowhook;
    int32_t hookcount; int32_t basehookcount; Value hook;
    uint64_t tbc_head;
    int32_t yieldable; int32_t nonyieldable; int32_t last_error_code; uint32_t flags;
    CoroutineState coroutine;
} LuaThread;

typedef struct SourceView { uint8_t* bytes; uint64_t len; String* source_name; } SourceView;
typedef struct SourcePos { uint64_t offset; int32_t line; int32_t col; } SourcePos;
typedef struct SourceSpan { uint64_t start; uint64_t len; int32_t line; int32_t col; } SourceSpan;
typedef struct CompileError { int32_t code; SourcePos pos; uint16_t token; } CompileError;
typedef struct Token { uint16_t kind; uint64_t start; uint64_t len; int32_t line; uint32_t aux; uint64_t bits; } Token;
typedef struct Lexer { SourceView src; uint64_t pos; int32_t line; int32_t col; Token current; Token lookahead; uint8_t has_lookahead; } Lexer;
typedef struct CompileArena { uint8_t* base; uint64_t pos; uint64_t cap; uint8_t overflowed; } CompileArena;
typedef struct IndexVec { uint64_t* data; uint64_t len; uint64_t cap; } IndexVec;
typedef struct InstrVec { Instr* data; uint64_t len; uint64_t cap; } InstrVec;
typedef struct ValueVec { Value* data; uint64_t len; uint64_t cap; } ValueVec;
typedef struct ProtoPtrVec { Proto** data; uint64_t len; uint64_t cap; } ProtoPtrVec;
typedef struct LocVarVec { LocVar* data; uint64_t len; uint64_t cap; } LocVarVec;
typedef struct UpValDescVec { UpValDesc* data; uint64_t len; uint64_t cap; } UpValDescVec;

typedef struct ParseNode { uint16_t kind; uint16_t flags; uint16_t token; uint16_t reserved; uint64_t first_child; uint64_t child_len; uint64_t a; uint64_t b; uint64_t c; SourceSpan span; } ParseNode;
typedef struct ParseFunction { uint64_t parent; uint64_t root_node; uint64_t param_first; uint64_t param_len; uint64_t child_func_first; uint64_t child_func_len; uint16_t flags; uint16_t reserved; SourceSpan span; } ParseFunction;
typedef struct ParseFrame { uint16_t kind; uint16_t pc; uint16_t flags; uint8_t return_seen; uint8_t reserved; uint64_t parent; uint64_t node; uint64_t function_ref; uint64_t block_ref; uint64_t first_child; uint64_t child_count; uint32_t terminator_mask; uint64_t a; uint64_t b; uint64_t c; SourceSpan span; } ParseFrame;
typedef struct ExprOpEntry { uint16_t op; uint8_t precedence; uint8_t right_assoc; SourceSpan span; } ExprOpEntry;
typedef struct ExprValEntry { uint64_t node; SourceSpan span; } ExprValEntry;
typedef struct ParseNodeVec { ParseNode* data; uint64_t len; uint64_t cap; } ParseNodeVec;
typedef struct ParseFunctionVec { ParseFunction* data; uint64_t len; uint64_t cap; } ParseFunctionVec;
typedef struct ParseFrameVec { ParseFrame* data; uint64_t len; uint64_t cap; } ParseFrameVec;
typedef struct ExprOpVec { ExprOpEntry* data; uint64_t len; uint64_t cap; } ExprOpVec;
typedef struct ExprValVec { ExprValEntry* data; uint64_t len; uint64_t cap; } ExprValVec;

typedef struct ScopeRec { uint64_t parent; uint64_t owner_function; uint64_t symbol_first; uint64_t symbol_len; uint16_t flags; uint16_t reserved; SourceSpan span; } ScopeRec;
typedef struct SymbolRec { uint16_t kind; uint16_t flags; uint64_t owner_function; uint64_t scope; uint64_t name_start; uint64_t name_len; uint16_t local_index; uint16_t upvalue_index; SourceSpan span; } SymbolRec;
typedef struct CaptureRec { uint64_t symbol; uint64_t source_function; uint8_t through_parent; uint8_t reserved; uint16_t upvalue_index; SourceSpan span; } CaptureRec;
typedef struct NameUse { uint64_t name_start; uint64_t name_len; uint16_t resolved_kind; uint16_t reserved; uint64_t resolved_ref; SourceSpan span; } NameUse;
typedef struct HirFunction { uint64_t parent; uint64_t body; uint64_t params_first; uint64_t params_len; uint64_t symbols_first; uint64_t symbols_len; uint64_t captures_first; uint64_t captures_len; uint64_t nested_first; uint64_t nested_len; uint16_t flags; uint8_t numparams; uint8_t is_vararg; SourceSpan span; } HirFunction;
typedef struct HirBlock { uint64_t scope; uint64_t stmt_first; uint64_t stmt_last; uint64_t stmt_len; uint16_t flags; uint16_t terminator; SourceSpan span; } HirBlock;
typedef struct HirStmt { uint16_t kind; uint16_t flags; uint64_t a; uint64_t b; uint64_t c; uint64_t d; uint64_t e; uint64_t pc; uint64_t next_stmt; SourceSpan span; } HirStmt;
typedef struct HirExpr { uint16_t kind; uint16_t op; uint16_t flags; uint16_t reserved; uint64_t a; uint64_t b; uint64_t c; uint64_t next; Value value; SourceSpan span; } HirExpr;
typedef struct HirFunctionVec { HirFunction* data; uint64_t len; uint64_t cap; } HirFunctionVec;
typedef struct HirBlockVec { HirBlock* data; uint64_t len; uint64_t cap; } HirBlockVec;
typedef struct HirStmtVec { HirStmt* data; uint64_t len; uint64_t cap; } HirStmtVec;
typedef struct HirExprVec { HirExpr* data; uint64_t len; uint64_t cap; } HirExprVec;
typedef struct ScopeVec { ScopeRec* data; uint64_t len; uint64_t cap; } ScopeVec;
typedef struct SymbolVec { SymbolRec* data; uint64_t len; uint64_t cap; } SymbolVec;
typedef struct CaptureVec { CaptureRec* data; uint64_t len; uint64_t cap; } CaptureVec;
typedef struct NameUseVec { NameUse* data; uint64_t len; uint64_t cap; } NameUseVec;

typedef struct SemanticFrame { uint16_t kind; uint16_t pc; uint16_t flags; uint16_t reserved; uint64_t parse_ref; uint64_t hir_parent; uint64_t scope; uint64_t function_ref; uint64_t a; uint64_t b; uint64_t c; SourceSpan span; } SemanticFrame;
typedef struct SemanticFrameVec { SemanticFrame* data; uint64_t len; uint64_t cap; } SemanticFrameVec;
typedef struct LowerFrame { uint16_t kind; uint16_t pc; uint16_t flags; uint16_t reserved; uint64_t hir_ref; uint64_t function_ref; uint16_t target_reg; uint16_t result_count; uint64_t patch_base; uint64_t a; uint64_t b; uint64_t c; SourceSpan span; } LowerFrame;
typedef struct LowerScope { uint64_t scope; uint16_t first_reg; uint64_t first_local; uint64_t patch_base; SourceSpan span; } LowerScope;
typedef struct PatchRec { uint16_t kind; uint16_t flags; uint64_t pc; uint64_t target; uint64_t next; SourceSpan span; } PatchRec;
typedef struct ExprSlot { uint16_t kind; uint16_t reg; uint64_t ref; uint16_t flags; SourceSpan span; } ExprSlot;
typedef struct LowerFrameVec { LowerFrame* data; uint64_t len; uint64_t cap; } LowerFrameVec;
typedef struct LowerScopeVec { LowerScope* data; uint64_t len; uint64_t cap; } LowerScopeVec;
typedef struct PatchVec { PatchRec* data; uint64_t len; uint64_t cap; } PatchVec;
typedef struct ExprSlotVec { ExprSlot* data; uint64_t len; uint64_t cap; } ExprSlotVec;

typedef struct LabelPatch { uint64_t pc; uint64_t next; } LabelPatch;
typedef struct LabelDesc { String* name; uint64_t pc; int32_t line; uint16_t nactvar; } LabelDesc;
typedef struct CompileLocal { uint64_t name_start; uint64_t name_len; uint32_t hash; uint16_t reg; uint8_t kind; } CompileLocal;
typedef struct UpvalueRef { String* name; uint8_t instack; uint16_t index; } UpvalueRef;
typedef struct FuncBuilder {
    FuncBuilder* parent; Proto* out_proto;
    InstrVec code; ValueVec constants; ProtoPtrVec children; LocVarVec locvars; UpValDescVec upvals;
    CompileLocal* locals; uint64_t locals_len; uint64_t locals_cap;
    LabelDesc* labels; uint64_t labels_len; uint64_t labels_cap;
    LabelDesc* gotos; uint64_t gotos_len; uint64_t gotos_cap;
    uint64_t firstlocal; uint16_t nactvar; uint16_t freereg; uint16_t maxstack;
    uint64_t pc; uint64_t lasttarget; uint8_t numparams; uint8_t flag;
} FuncBuilder;
typedef struct ExpDesc { uint16_t kind; uint32_t info; uint32_t aux; uint64_t t; uint64_t f; Value value; } ExpDesc;
typedef struct CompileUnit {
    CompileArena arena;
    Lexer lexer;
    FuncBuilder* root;
    FuncBuilder* current;
    uint16_t phase;
    uint16_t status;
    uint32_t reserved;
    CompileError error;
    uint64_t root_parse_function;
    uint64_t root_hir_function;
    ParseNodeVec parse_nodes;
    ParseFunctionVec parse_functions;
    IndexVec parse_children;
    ParseFrameVec parse_frames;
    ExprOpVec expr_ops;
    ExprValVec expr_vals;
    HirFunctionVec hir_functions;
    HirBlockVec hir_blocks;
    HirStmtVec hir_stmts;
    HirExprVec hir_exprs;
    ScopeVec scopes;
    SymbolVec symbols;
    CaptureVec captures;
    NameUseVec name_uses;
    SemanticFrameVec semantic_frames;
    LowerFrameVec lower_frames;
    LowerScopeVec lower_scopes;
    PatchVec patches;
    ExprSlotVec expr_slots;
    uint64_t parse_mark;
    uint64_t semantic_mark;
    uint64_t lower_mark;
    uint64_t durable_mark;
} CompileUnit;
]]

function M.apply(ffi)
    ffi.cdef(M.cdef)
end

return M
