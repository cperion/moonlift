-- Lua Interpreter VM — Parser/compiler products

local host = require("lalin.host")

local SourceView = host.struct [[struct SourceView bytes: ptr(u8), len: index, source_name: ptr(String) end]]
local SourcePos = host.struct [[struct SourcePos offset: index, line: i32, col: i32 end]]
local SourceSpan = host.struct [[struct SourceSpan start: index, len: index, line: i32, col: i32 end]]
local CompileError = host.struct [[struct CompileError code: i32, pos: SourcePos, token: u16 end]]

local Token = host.struct [[struct Token kind: u16, start: index, len: index, line: i32, aux: u32, bits: u64 end]]
local Lexer = host.struct [[struct Lexer src: SourceView, pos: index, line: i32, col: i32, current: Token, lookahead: Token, has_lookahead: u8 end]]

local CompileArena = host.struct [[struct CompileArena base: ptr(u8), pos: index, cap: index, overflowed: u8 end]]
local IndexVec = host.struct [[struct IndexVec data: ptr(index), len: index, cap: index end]]

local InstrVec = host.struct [[struct InstrVec data: ptr(Instr), len: index, cap: index end]]
local ValueVec = host.struct [[struct ValueVec data: ptr(Value), len: index, cap: index end]]
local ProtoPtrVec = host.struct [[struct ProtoPtrVec data: ptr(ptr(Proto)), len: index, cap: index end]]
local LocVarVec = host.struct [[struct LocVarVec data: ptr(LocVar), len: index, cap: index end]]
local UpValDescVec = host.struct [[struct UpValDescVec data: ptr(UpValDesc), len: index, cap: index end]]

local ParseNode = host.struct [[struct ParseNode kind: u16, flags: u16, token: u16, reserved: u16, first_child: index, child_len: index, a: index, b: index, c: index, span: SourceSpan end]]
local ParseFunction = host.struct [[struct ParseFunction parent: index, root_node: index, param_first: index, param_len: index, child_func_first: index, child_func_len: index, flags: u16, reserved: u16, span: SourceSpan end]]
local ParseFrame = host.struct [[struct ParseFrame kind: u16, pc: u16, flags: u16, return_seen: u8, reserved: u8, parent: index, node: index, function_ref: index, block_ref: index, first_child: index, child_count: index, terminator_mask: u32, a: index, b: index, c: index, span: SourceSpan end]]
local ExprOpEntry = host.struct [[struct ExprOpEntry op: u16, precedence: u8, right_assoc: u8, span: SourceSpan end]]
local ExprValEntry = host.struct [[struct ExprValEntry node: index, span: SourceSpan end]]

local ParseNodeVec = host.struct [[struct ParseNodeVec data: ptr(ParseNode), len: index, cap: index end]]
local ParseFunctionVec = host.struct [[struct ParseFunctionVec data: ptr(ParseFunction), len: index, cap: index end]]
local ParseFrameVec = host.struct [[struct ParseFrameVec data: ptr(ParseFrame), len: index, cap: index end]]
local ExprOpVec = host.struct [[struct ExprOpVec data: ptr(ExprOpEntry), len: index, cap: index end]]
local ExprValVec = host.struct [[struct ExprValVec data: ptr(ExprValEntry), len: index, cap: index end]]

local ScopeRec = host.struct [[struct ScopeRec parent: index, owner_function: index, symbol_first: index, symbol_len: index, flags: u16, reserved: u16, span: SourceSpan end]]
local SymbolRec = host.struct [[struct SymbolRec kind: u16, flags: u16, owner_function: index, scope: index, name_start: index, name_len: index, local_index: u16, upvalue_index: u16, span: SourceSpan end]]
local CaptureRec = host.struct [[struct CaptureRec symbol: index, source_function: index, through_parent: u8, reserved: u8, upvalue_index: u16, span: SourceSpan end]]
local NameUse = host.struct [[struct NameUse name_start: index, name_len: index, resolved_kind: u16, reserved: u16, resolved_ref: index, span: SourceSpan end]]

local HirFunction = host.struct [[struct HirFunction parent: index, body: index, params_first: index, params_len: index, symbols_first: index, symbols_len: index, captures_first: index, captures_len: index, nested_first: index, nested_len: index, flags: u16, numparams: u8, is_vararg: u8, span: SourceSpan end]]
local HirBlock = host.struct [[struct HirBlock scope: index, stmt_first: index, stmt_last: index, stmt_len: index, flags: u16, terminator: u16, span: SourceSpan end]]
local HirStmt = host.struct [[struct HirStmt kind: u16, flags: u16, a: index, b: index, c: index, d: index, e: index, pc: index, next_stmt: index, span: SourceSpan end]]
local HirExpr = host.struct [[struct HirExpr kind: u16, op: u16, flags: u16, reserved: u16, a: index, b: index, c: index, next: index, value: Value, span: SourceSpan end]]

local HirFunctionVec = host.struct [[struct HirFunctionVec data: ptr(HirFunction), len: index, cap: index end]]
local HirBlockVec = host.struct [[struct HirBlockVec data: ptr(HirBlock), len: index, cap: index end]]
local HirStmtVec = host.struct [[struct HirStmtVec data: ptr(HirStmt), len: index, cap: index end]]
local HirExprVec = host.struct [[struct HirExprVec data: ptr(HirExpr), len: index, cap: index end]]
local ScopeVec = host.struct [[struct ScopeVec data: ptr(ScopeRec), len: index, cap: index end]]
local SymbolVec = host.struct [[struct SymbolVec data: ptr(SymbolRec), len: index, cap: index end]]
local CaptureVec = host.struct [[struct CaptureVec data: ptr(CaptureRec), len: index, cap: index end]]
local NameUseVec = host.struct [[struct NameUseVec data: ptr(NameUse), len: index, cap: index end]]

local SemanticFrame = host.struct [[struct SemanticFrame kind: u16, pc: u16, flags: u16, reserved: u16, parse_ref: index, hir_parent: index, scope: index, function_ref: index, a: index, b: index, c: index, span: SourceSpan end]]
local SemanticFrameVec = host.struct [[struct SemanticFrameVec data: ptr(SemanticFrame), len: index, cap: index end]]

local LowerFrame = host.struct [[struct LowerFrame kind: u16, pc: u16, flags: u16, reserved: u16, hir_ref: index, function_ref: index, target_reg: u16, result_count: u16, patch_base: index, a: index, b: index, c: index, span: SourceSpan end]]
local LowerScope = host.struct [[struct LowerScope scope: index, first_reg: u16, first_local: index, patch_base: index, span: SourceSpan end]]
local PatchRec = host.struct [[struct PatchRec kind: u16, flags: u16, pc: index, target: index, next: index, span: SourceSpan end]]
local ExprSlot = host.struct [[struct ExprSlot kind: u16, reg: u16, ref: index, flags: u16, span: SourceSpan end]]

local LowerFrameVec = host.struct [[struct LowerFrameVec data: ptr(LowerFrame), len: index, cap: index end]]
local LowerScopeVec = host.struct [[struct LowerScopeVec data: ptr(LowerScope), len: index, cap: index end]]
local PatchVec = host.struct [[struct PatchVec data: ptr(PatchRec), len: index, cap: index end]]
local ExprSlotVec = host.struct [[struct ExprSlotVec data: ptr(ExprSlot), len: index, cap: index end]]

local LabelPatch = host.struct [[struct LabelPatch pc: index, next: index end]]
local LabelDesc = host.struct [[struct LabelDesc name: ptr(String), pc: index, line: i32, nactvar: u16 end]]
local CompileLocal = host.struct [[struct CompileLocal name_start: index, name_len: index, hash: u32, reg: u16, kind: u8 end]]
local UpvalueRef = host.struct [[struct UpvalueRef name: ptr(String), instack: u8, index: u16 end]]

local FuncBuilder = host.struct [[struct FuncBuilder parent: ptr(FuncBuilder), out_proto: ptr(Proto), code: InstrVec, constants: ValueVec, children: ProtoPtrVec, locvars: LocVarVec, upvals: UpValDescVec, locals: ptr(CompileLocal), locals_len: index, locals_cap: index, labels: ptr(LabelDesc), labels_len: index, labels_cap: index, gotos: ptr(LabelDesc), gotos_len: index, gotos_cap: index, firstlocal: index, nactvar: u16, freereg: u16, maxstack: u16, pc: index, lasttarget: index, numparams: u8, flag: u8 end]]

-- Legacy direct-to-bytecode expression descriptor. Retained only because some
-- low-level codegen helpers still expose it while lowering is being migrated.
local ExpDesc = host.struct [[struct ExpDesc kind: u16, info: u32, aux: u32, t: index, f: index, value: Value end]]

local CompileUnit = host.struct [[struct CompileUnit
    arena: CompileArena,
    lexer: Lexer,
    root: ptr(FuncBuilder),
    current: ptr(FuncBuilder),

    phase: u16,
    status: u16,
    reserved: u32,
    error: CompileError,

    root_parse_function: index,
    root_hir_function: index,

    parse_nodes: ParseNodeVec,
    parse_functions: ParseFunctionVec,
    parse_children: IndexVec,
    parse_frames: ParseFrameVec,
    expr_ops: ExprOpVec,
    expr_vals: ExprValVec,

    hir_functions: HirFunctionVec,
    hir_blocks: HirBlockVec,
    hir_stmts: HirStmtVec,
    hir_exprs: HirExprVec,
    scopes: ScopeVec,
    symbols: SymbolVec,
    captures: CaptureVec,
    name_uses: NameUseVec,
    semantic_frames: SemanticFrameVec,

    lower_frames: LowerFrameVec,
    lower_scopes: LowerScopeVec,
    patches: PatchVec,
    expr_slots: ExprSlotVec,

    parse_mark: index,
    semantic_mark: index,
    lower_mark: index,
    durable_mark: index
end]]

return {
    SourceView = SourceView,
    SourcePos = SourcePos,
    SourceSpan = SourceSpan,
    CompileError = CompileError,
    Token = Token,
    Lexer = Lexer,
    CompileArena = CompileArena,
    IndexVec = IndexVec,
    InstrVec = InstrVec,
    ValueVec = ValueVec,
    ProtoPtrVec = ProtoPtrVec,
    LocVarVec = LocVarVec,
    UpValDescVec = UpValDescVec,
    ParseNode = ParseNode,
    ParseFunction = ParseFunction,
    ParseFrame = ParseFrame,
    ExprOpEntry = ExprOpEntry,
    ExprValEntry = ExprValEntry,
    ParseNodeVec = ParseNodeVec,
    ParseFunctionVec = ParseFunctionVec,
    ParseFrameVec = ParseFrameVec,
    ExprOpVec = ExprOpVec,
    ExprValVec = ExprValVec,
    ScopeRec = ScopeRec,
    SymbolRec = SymbolRec,
    CaptureRec = CaptureRec,
    NameUse = NameUse,
    HirFunction = HirFunction,
    HirBlock = HirBlock,
    HirStmt = HirStmt,
    HirExpr = HirExpr,
    HirFunctionVec = HirFunctionVec,
    HirBlockVec = HirBlockVec,
    HirStmtVec = HirStmtVec,
    HirExprVec = HirExprVec,
    ScopeVec = ScopeVec,
    SymbolVec = SymbolVec,
    CaptureVec = CaptureVec,
    NameUseVec = NameUseVec,
    SemanticFrame = SemanticFrame,
    SemanticFrameVec = SemanticFrameVec,
    LowerFrame = LowerFrame,
    LowerScope = LowerScope,
    PatchRec = PatchRec,
    ExprSlot = ExprSlot,
    LowerFrameVec = LowerFrameVec,
    LowerScopeVec = LowerScopeVec,
    PatchVec = PatchVec,
    ExprSlotVec = ExprSlotVec,
    LabelPatch = LabelPatch,
    LabelDesc = LabelDesc,
    CompileLocal = CompileLocal,
    UpvalueRef = UpvalueRef,
    FuncBuilder = FuncBuilder,
    CompileUnit = CompileUnit,
    ExpDesc = ExpDesc,
}
