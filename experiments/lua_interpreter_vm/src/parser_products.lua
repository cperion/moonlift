-- Lua Interpreter VM — Parser/compiler products

local host = require("moonlift.host")

local SourceView = host.struct [[struct SourceView bytes: ptr(u8); len: index; source_name: ptr(String) end]]
local SourcePos = host.struct [[struct SourcePos offset: index; line: i32; col: i32 end]]
local CompileError = host.struct [[struct CompileError code: i32; pos: SourcePos; token: u16 end]]

local Token = host.struct [[struct Token kind: u16; start: index; len: index; line: i32; aux: u32; bits: u64 end]]
local Lexer = host.struct [[struct Lexer src: SourceView; pos: index; line: i32; col: i32; current: Token; lookahead: Token; has_lookahead: u8 end]]

local CompileArena = host.struct [[struct CompileArena base: ptr(u8); pos: index; cap: index; overflowed: u8 end]]
local InstrVec = host.struct [[struct InstrVec data: ptr(Instr); len: index; cap: index end]]
local ValueVec = host.struct [[struct ValueVec data: ptr(Value); len: index; cap: index end]]
local ProtoPtrVec = host.struct [[struct ProtoPtrVec data: ptr(ptr(Proto)); len: index; cap: index end]]
local LocVarVec = host.struct [[struct LocVarVec data: ptr(LocVar); len: index; cap: index end]]
local UpValDescVec = host.struct [[struct UpValDescVec data: ptr(UpValDesc); len: index; cap: index end]]

local LabelPatch = host.struct [[struct LabelPatch pc: index; next: index end]]
local LabelDesc = host.struct [[struct LabelDesc name: ptr(String); pc: index; line: i32; nactvar: u16 end]]
local CompileLocal = host.struct [[struct CompileLocal name_start: index; name_len: index; hash: u32; reg: u16; kind: u8 end]]
local UpvalueRef = host.struct [[struct UpvalueRef name: ptr(String); instack: u8; index: u16 end]]

local FuncBuilder = host.struct [[struct FuncBuilder parent: ptr(FuncBuilder); out_proto: ptr(Proto); code: InstrVec; constants: ValueVec; children: ProtoPtrVec; locvars: LocVarVec; upvals: UpValDescVec; locals: ptr(CompileLocal); locals_len: index; locals_cap: index; labels: ptr(LabelDesc); labels_len: index; labels_cap: index; gotos: ptr(LabelDesc); gotos_len: index; gotos_cap: index; firstlocal: index; nactvar: u16; freereg: u16; maxstack: u16; pc: index; lasttarget: index; numparams: u8; flag: u8 end]]

local ExpDesc = host.struct [[struct ExpDesc kind: u16; info: u32; aux: u32; t: index; f: index; value: Value end]]

local CompileUnit = host.struct [[struct CompileUnit arena: ptr(CompileArena); lexer: Lexer; root: ptr(FuncBuilder); current: ptr(FuncBuilder); expr_tmp: ExpDesc; expr_tmp2: ExpDesc; token_tmp: Token end]]

return {
    SourceView = SourceView,
    SourcePos = SourcePos,
    CompileError = CompileError,
    Token = Token,
    Lexer = Lexer,
    CompileArena = CompileArena,
    InstrVec = InstrVec,
    ValueVec = ValueVec,
    ProtoPtrVec = ProtoPtrVec,
    LocVarVec = LocVarVec,
    UpValDescVec = UpValDescVec,
    LabelPatch = LabelPatch,
    LabelDesc = LabelDesc,
    CompileLocal = CompileLocal,
    UpvalueRef = UpvalueRef,
    FuncBuilder = FuncBuilder,
    CompileUnit = CompileUnit,
    ExpDesc = ExpDesc,
}
