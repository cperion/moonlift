package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local AnalysisMod = require("moonlift.mlua_document_analysis")
local SigMod = require("moonlift.editor_signature_help")
local PositionIndex = require("moonlift.source_position_index")

local T = pvm.context()
A.Define(T)
local S = T.MoonSource
local E = T.MoonEditor
local Mlua = T.MoonMlua
local H = T.MoonHost
local Ty = T.MoonType
local C = T.MoonCore
local Tr = T.MoonTree
local Analysis = AnalysisMod.Define(T)
local Sig = SigMod.Define(T)
local P = PositionIndex.Define(T)

local uri = S.DocUri("file:///signature.mlua")
local src = [[
func add(a: i32, b: i32) -> i32
    return a
end
expr Twice(x: i32) -> i32
    x
end
expr Use() -> i32
    add(1, 2)
end
expr UseFrag() -> i32
    Twice(1)
end

local decoded = moonlift.json.decode(bytes, opts)
local lua_side = add(1, 2)
]]
local doc = S.DocumentSnapshot(uri, S.DocVersion(1), S.LangMlua, src)
local analysis = Analysis.analyze_document(doc)
local idx = P.build_index(doc)
local function q_after(needle)
    local s, e = assert(src:find(needle, 1, true))
    return E.PositionQuery(uri, S.DocVersion(1), P.offset_to_pos(idx, e).pos)
end

local ctx = Sig.context(q_after("add(1,"), analysis)
assert(pvm.classof(ctx) == E.SignatureCall)
assert(ctx.callee == "add")
assert(ctx.active_parameter == 1)

local help = Sig.help(q_after("add(1,"), analysis)
assert(pvm.classof(help) == E.SignatureHelp)
assert(#help.signatures == 1)
assert(help.active_parameter == 1)
assert(help.signatures[1].label == "add(a: i32, b: i32) -> i32")
assert(#help.signatures[1].params == 2)
assert(help.signatures[1].params[2].label == "b: i32")

local builtin = Sig.help(q_after("moonlift.json.decode(bytes"), analysis)
assert(pvm.classof(builtin) == E.SignatureHelp)
assert(builtin.active_parameter == 0)
assert(builtin.signatures[1].label == "moonlift.json.decode(src)")

local extern_src = [[
expr UseExtern() -> i32
    puts(0)
end
]]
local extern_doc = S.DocumentSnapshot(uri, S.DocVersion(1), S.LangMlua, extern_src)
local extern_base = Analysis.analyze_document(extern_doc)
local extern_item = Tr.ItemExtern(Tr.ExternFunc("puts", "puts", { Ty.Param("x", Ty.TPtr(Ty.TScalar(C.ScalarU8))) }, Ty.TScalar(C.ScalarI32)))
local extern_parse = Mlua.DocumentParse(
    extern_base.parse.parts,
    H.MluaParseResult(extern_base.parse.combined.decls, Tr.Module(Tr.ModuleSurface, { extern_item }), {}, {}, {}),
    extern_base.parse.islands,
    extern_base.parse.anchors
)
local extern_analysis = Mlua.DocumentAnalysis(extern_parse, extern_base.host, extern_base.open_report, {}, {}, {}, {}, extern_base.back_report, extern_base.anchors)
local extern_idx = P.build_index(extern_doc)
local _, extern_e = assert(extern_src:find("puts(", 1, true))
local extern_help = Sig.help(E.PositionQuery(uri, S.DocVersion(1), P.offset_to_pos(extern_idx, extern_e).pos), extern_analysis)
assert(pvm.classof(extern_help) == E.SignatureHelp)
assert(extern_help.signatures[1].label == "puts(x: ptr(u8)) -> i32")

local frag = Sig.help(q_after("Twice("), analysis)
assert(pvm.classof(frag) == E.SignatureHelp)
assert(frag.signatures[1].label == "Twice(x: i32) -> i32")

local lua_opaque_add = Sig.help(q_after("local lua_side = add(1,"), analysis)
assert(pvm.classof(lua_opaque_add) == E.SignatureHelpMissing)

local missing = Sig.help(q_after("expr Use"), analysis)
assert(pvm.classof(missing) == E.SignatureHelpMissing)

print("moonlift editor signature help ok")
