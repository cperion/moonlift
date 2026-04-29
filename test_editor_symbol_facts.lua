package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local AnalysisMod = require("moonlift.mlua_document_analysis")
local SymbolsMod = require("moonlift.editor_symbol_facts")

local T = pvm.context()
A.Define(T)
local S = T.Moon2Source
local E = T.Moon2Editor
local Analysis = AnalysisMod.Define(T)
local Symbols = SymbolsMod.Define(T)

local uri = S.DocUri("file:///symbols.mlua")
local src = [[
struct User
    id: i32
    active: bool32
end
expose Users: view(User)
func User:is_active(self: ptr(User)) -> bool
    return true
end
region Done(n: i32; done: cont(total: i32))
entry start(total: i32 = 0)
    jump done(total = total)
end
end
expr FortyTwo() -> i32
    42
end
module Math
    export func two() -> i32
        return 2
    end
end
export func first(xs: ptr(i32), n: index) -> i32
    return block loop(i: index = 0) -> i32
        if i >= n then yield i end
        jump loop(i = i + 1)
    end
end
]]
local analysis = Analysis.analyze_document(S.DocumentSnapshot(uri, S.DocVersion(1), S.LangMlua, src))
local symbols = Symbols.symbols(analysis)
local tree = Symbols.symbol_tree(analysis)
assert(pvm.classof(tree) == E.SymbolTree)
assert(#tree.symbols == #symbols)

local function find(name, kind)
    for i = 1, #symbols do
        local s = symbols[i]
        if s.name == name and (not kind or s.kind == kind) then return s end
    end
    return nil
end

local user = assert(find("User", E.SymStruct))
assert(pvm.classof(user.subject) == E.SubjectHostStruct)
local id = assert(find("id", E.SymField))
assert(id.parent == E.SymbolId("host.struct.User"))
assert(pvm.classof(id.subject) == E.SubjectHostField)
local expose = assert(find("Users", E.SymInterface))
assert(pvm.classof(expose.subject) == E.SubjectHostExpose)
local accessor = assert(find("User:is_active", E.SymMethod))
assert(pvm.classof(accessor.subject) == E.SubjectHostAccessor or pvm.classof(accessor.subject) == E.SubjectTreeFunc)
local func = assert(find("first", E.SymFunction))
assert(pvm.classof(func.subject) == E.SubjectTreeFunc)
assert(func.range.uri == uri)
local module_sym = assert(find("Math", E.SymModule))
assert(pvm.classof(module_sym.subject) == E.SubjectTreeModule)
local loop_sym = assert(find("loop", E.SymEvent))
assert(pvm.classof(loop_sym.subject) == E.SubjectContinuation)

local saw_region, saw_expr = false, false
for i = 1, #symbols do
    if pvm.classof(symbols[i].subject) == E.SubjectRegionFrag then saw_region = true end
    if pvm.classof(symbols[i].subject) == E.SubjectExprFrag then saw_expr = true end
end
assert(saw_region and saw_expr)

Symbols.symbol_facts_phase:reset()
pvm.drain(Symbols.symbol_facts_phase(analysis))
pvm.drain(Symbols.symbol_facts_phase(analysis))
local report = pvm.report({ Symbols.symbol_facts_phase })[1]
assert(report.calls == 2 and report.hits == 1)

print("moonlift editor symbol facts ok")
