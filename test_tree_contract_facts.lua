package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local Parse = require("moonlift.parse")
local Typecheck = require("moonlift.tree_typecheck")
local ContractFacts = require("moonlift.tree_contract_facts")

local T = pvm.context()
A.Define(T)
local P = Parse.Define(T)
local TC = Typecheck.Define(T)
local CF = ContractFacts.Define(T)
local Tr = T.Moon2Tree

local src = [[
export func add_noalias_i32(noalias dst: ptr(i32), readonly a: ptr(i32), readonly b: ptr(i32), n: i32) -> i32
    requires bounds(dst, n)
    requires bounds(a, n)
    requires bounds(b, n)
    requires disjoint(dst, a)
    requires disjoint(dst, b)
    block loop(i: i32 = 0)
        if i >= n then
            return 0
        end
        dst[i] = a[i] + b[i]
        jump loop(i = i + 1)
    end
end
]]

local parsed = P.parse_module(src)
assert(#parsed.issues == 0)
assert(pvm.classof(parsed.module.items[1].func) == Tr.FuncExportContract)
assert(#parsed.module.items[1].func.contracts == 8)

local checked = TC.check_module(parsed.module)
assert(#checked.issues == 0)
local func = checked.module.items[1].func
local facts = CF.facts(func)
local counts = { bounds = 0, disjoint = 0, noalias = 0, readonly = 0 }
for i = 1, #facts.facts do
    local cls = pvm.classof(facts.facts[i])
    if cls == Tr.ContractFactBounds then counts.bounds = counts.bounds + 1 end
    if cls == Tr.ContractFactDisjoint then counts.disjoint = counts.disjoint + 1 end
    if cls == Tr.ContractFactNoAlias then counts.noalias = counts.noalias + 1 end
    if cls == Tr.ContractFactReadonly then counts.readonly = counts.readonly + 1 end
end
assert(counts.bounds == 3)
assert(counts.disjoint == 2)
assert(counts.noalias == 1)
assert(counts.readonly == 2)

print("moonlift tree_contract_facts ok")
