package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local Parse = require("moonlift.parse")
local Typecheck = require("moonlift.tree_typecheck")
local TreeToBack = require("moonlift.tree_to_back")
local Validate = require("moonlift.back_validate")
local J = require("moonlift.back_jit")
local VecFacts = require("moonlift.vec_loop_facts")
local VecDecide = require("moonlift.vec_loop_decide")

local T = pvm.context()
A2.Define(T)
local P = Parse.Define(T)
local TC = Typecheck.Define(T)
local Lower = TreeToBack.Define(T)
local VBack = Validate.Define(T)
local jit_api = J.Define(T)
local VF = VecFacts.Define(T)
local VD = VecDecide.Define(T)
local B2 = T.Moon2Back
local Vec = T.Moon2Vec

local src = [[
export func tri(n: i32) -> i32
    block loop(i: i32 = 0, acc: i32 = 0)
        if i >= n then
            return acc
        end

        jump loop(
            i = i + 1,
            acc = acc + i,
        )
    end
end

export func fact(n: i32) -> i32
    return block loop(x: i32 = n, acc: i32 = 1) -> i32
        if x <= 1 then
            yield acc
        end

        jump loop(
            x = x - 1,
            acc = acc * x,
        )
    end
end

export func clamp_nonneg(x: i32) -> i32
    if x < 0 then
        return 0
    end
    return x
end

export func first_three_or_n(n: i32) -> i32
    return control -> i32
    block read(i: i32 = 0)
        if i >= n then
            yield n
        end

        if i == 3 then
            jump found(i = i)
        end

        jump read(i = i + 1)
    end

    block found(i: i32)
        yield i
    end
    end
end
]]

local parsed = P.parse_module(src)
assert(#parsed.issues == 0)
print("parsed items", #parsed.module.items)

local checked = TC.check_module(parsed.module)
assert(#checked.issues == 0)
print("typechecked module", checked.module.h.module_name)

local program = Lower.module(checked.module)
local report = VBack.validate(program)
assert(#report.issues == 0)
print("lowered backend commands", #program.cmds)

local target = Vec.VecTargetModel(Vec.VecTargetCraneliftJit, {
    Vec.VecTargetVectorBits(128),
    Vec.VecTargetSupportsShape(Vec.VecVectorShape(Vec.VecElemI32, 4)),
})

local tri_region = checked.module.items[1].func.body[1].region
local tri_facts = VF.facts(tri_region)
local tri_decision = VD.decide(tri_facts, target)
print("tri vec domain", pvm.classof(tri_facts.domain) == Vec.VecDomainCounted and "counted" or "rejected")
print("tri reductions", #tri_facts.reductions)
print("tri decision", pvm.classof(tri_decision.chosen) == Vec.VecLoopVector and "vector" or "scalar")

local fact_region = checked.module.items[2].func.body[1].value.region
local fact_facts = VF.facts(fact_region)
print("fact vec domain", pvm.classof(fact_facts.domain) == Vec.VecDomainCounted and "counted" or "rejected")
print("fact reductions", #fact_facts.reductions)

local first_region = checked.module.items[4].func.body[1].value.region
local first_facts = VF.facts(first_region)
print("multi-block source", pvm.classof(first_facts.source) == Vec.VecLoopSourceRejected and "not a vector loop yet" or "recognized")

local artifact = jit_api.jit():compile(program)
local tri = ffi.cast("int32_t (*)(int32_t)", artifact:getpointer(B2.BackFuncId("tri")))
local fact = ffi.cast("int32_t (*)(int32_t)", artifact:getpointer(B2.BackFuncId("fact")))
local clamp = ffi.cast("int32_t (*)(int32_t)", artifact:getpointer(B2.BackFuncId("clamp_nonneg")))
local first = ffi.cast("int32_t (*)(int32_t)", artifact:getpointer(B2.BackFuncId("first_three_or_n")))
assert(tri(10) == 45)
assert(fact(5) == 120)
assert(clamp(-7) == 0)
assert(first(8) == 3)
artifact:free()

print("moonlift parse playground ok")
print("tri(10)=45, fact(5)=120, clamp(-7)=0, first_three_or_n(8)=3")
