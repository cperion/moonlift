package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local Parse = require("moonlift.parse")
local Typecheck = require("moonlift.tree_typecheck")
local Plan = require("moonlift.vec_kernel_plan")

local T = pvm.context()
A.Define(T)
local P = Parse.Define(T)
local TC = Typecheck.Define(T)
local KP = Plan.Define(T)
local V = T.Moon2Vec
local C = T.Moon2Core
local Tr = T.Moon2Tree

local src = [[
export func sum_i32(xs: ptr(i32), n: i32) -> i32
    return block loop(i: i32 = 0, acc: i32 = 0) -> i32
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + xs[i])
    end
end

export func dot_i32(a: ptr(i32), b: ptr(i32), n: i32) -> i32
    return block loop(i: i32 = 0, acc: i32 = 0) -> i32
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + a[i] * b[i])
    end
end

export func fill_i32(xs: ptr(i32), n: i32, value: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        xs[i] = value
        jump loop(i = i + 1)
    end
end

export func copy_i32(dst: ptr(i32), src: ptr(i32), n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i] = src[i]
        jump loop(i = i + 1)
    end
end

export func add_i32(dst: ptr(i32), a: ptr(i32), b: ptr(i32), n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i] = a[i] + b[i]
        jump loop(i = i + 1)
    end
end

export func scale_i32(dst: ptr(i32), xs: ptr(i32), k: i32, n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i] = xs[i] * k
        jump loop(i = i + 1)
    end
end

export func inc_i32(xs: ptr(i32), n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        xs[i] = xs[i] + 1
        jump loop(i = i + 1)
    end
end

export func axpy_i32(y: ptr(i32), x: ptr(i32), a: i32, n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        y[i] = y[i] + a * x[i]
        jump loop(i = i + 1)
    end
end

export func and_i32(dst: ptr(i32), a: ptr(i32), b: ptr(i32), n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i] = a[i] & b[i]
        jump loop(i = i + 1)
    end
end

export func sub_i32(dst: ptr(i32), a: ptr(i32), b: ptr(i32), n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i] = a[i] - b[i]
        jump loop(i = i + 1)
    end
end

export func or_i32(dst: ptr(i32), a: ptr(i32), b: ptr(i32), n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i] = a[i] | b[i]
        jump loop(i = i + 1)
    end
end

export func xor_i32(dst: ptr(i32), a: ptr(i32), b: ptr(i32), n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i] = a[i] ^ b[i]
        jump loop(i = i + 1)
    end
end
]]

local parsed = P.parse_module(src)
assert(#parsed.issues == 0)
local checked = TC.check_module(parsed.module)
assert(#checked.issues == 0)
local items = checked.module.items
local sum = KP.plan(items[1].func.name, C.VisibilityExport, items[1].func.params, items[1].func.result, items[1].func.body)
local dot = KP.plan(items[2].func.name, C.VisibilityExport, items[2].func.params, items[2].func.result, items[2].func.body)
local fill = KP.plan(items[3].func.name, C.VisibilityExport, items[3].func.params, items[3].func.result, items[3].func.body)
local copy = KP.plan(items[4].func.name, C.VisibilityExport, items[4].func.params, items[4].func.result, items[4].func.body)
local add = KP.plan(items[5].func.name, C.VisibilityExport, items[5].func.params, items[5].func.result, items[5].func.body)
local scale = KP.plan(items[6].func.name, C.VisibilityExport, items[6].func.params, items[6].func.result, items[6].func.body)
local inc = KP.plan(items[7].func.name, C.VisibilityExport, items[7].func.params, items[7].func.result, items[7].func.body)
local axpy = KP.plan(items[8].func.name, C.VisibilityExport, items[8].func.params, items[8].func.result, items[8].func.body)
local band = KP.plan(items[9].func.name, C.VisibilityExport, items[9].func.params, items[9].func.result, items[9].func.body)
local sub = KP.plan(items[10].func.name, C.VisibilityExport, items[10].func.params, items[10].func.result, items[10].func.body)
local bor = KP.plan(items[11].func.name, C.VisibilityExport, items[11].func.params, items[11].func.result, items[11].func.body)
local bxor = KP.plan(items[12].func.name, C.VisibilityExport, items[12].func.params, items[12].func.result, items[12].func.body)
assert(pvm.classof(sum) == V.VecKernelReduce)
assert(pvm.classof(sum.counter) == V.VecKernelCounterI32)
assert(pvm.classof(dot) == V.VecKernelReduce)
assert(pvm.classof(dot.counter) == V.VecKernelCounterI32)
assert(pvm.classof(fill) == V.VecKernelMap)
assert(pvm.classof(copy) == V.VecKernelMap)
assert(pvm.classof(add) == V.VecKernelMap)
assert(pvm.classof(add.counter) == V.VecKernelCounterI32)
assert(pvm.classof(scale) == V.VecKernelMap)
assert(pvm.classof(inc) == V.VecKernelMap)
assert(pvm.classof(axpy) == V.VecKernelMap)
assert(pvm.classof(band) == V.VecKernelMap)
assert(pvm.classof(sub) == V.VecKernelMap)
assert(pvm.classof(bor) == V.VecKernelMap)
assert(pvm.classof(bxor) == V.VecKernelMap)
assert(pvm.classof(sum.reduction) == V.VecKernelReductionBin)
assert(sum.reduction.op == V.VecAdd)
assert(sum.reduction.identity == "0")
assert(pvm.classof(sum.reduction.value) == V.VecKernelExprLoad)
assert(sum.reduction.value.base.name == "xs")
assert(pvm.classof(dot.reduction) == V.VecKernelReductionBin)
assert(dot.reduction.op == V.VecAdd)
assert(pvm.classof(dot.reduction.value) == V.VecKernelExprBin)
assert(dot.reduction.value.op == V.VecMul)
assert(dot.reduction.value.lhs.base.name == "a")
assert(dot.reduction.value.rhs.base.name == "b")
assert(#fill.stores == 1)
assert(fill.stores[1].dst.name == "xs")
assert(pvm.classof(fill.stores[1].value) == V.VecKernelExprInvariant)
assert(pvm.classof(copy.stores[1].value) == V.VecKernelExprLoad)
assert(pvm.classof(add.stores[1].value) == V.VecKernelExprBin)
assert(add.stores[1].value.op == V.VecAdd)
assert(pvm.classof(scale.stores[1].value) == V.VecKernelExprBin)
assert(scale.stores[1].value.op == V.VecMul)
assert(pvm.classof(inc.stores[1].value) == V.VecKernelExprBin)
assert(inc.stores[1].value.op == V.VecAdd)
assert(pvm.classof(axpy.stores[1].value) == V.VecKernelExprBin)
assert(axpy.stores[1].value.op == V.VecAdd)
assert(pvm.classof(band.stores[1].value) == V.VecKernelExprBin)
assert(band.stores[1].value.op == V.VecBitAnd)
assert(pvm.classof(sub.stores[1].value) == V.VecKernelExprBin)
assert(sub.stores[1].value.op == V.VecSub)
assert(bor.stores[1].value.op == V.VecBitOr)
assert(bxor.stores[1].value.op == V.VecBitXor)
assert(sum.decision.chosen.shape.lanes == 4)
assert(add.decision.chosen.shape.lanes == 4)
assert(pvm.classof(sum.decision.chosen) == V.VecLoopVector)
assert(pvm.classof(dot.decision.chosen) == V.VecLoopVector)
assert(pvm.classof(fill.decision.chosen) == V.VecLoopVector)
assert(pvm.classof(sum.safety) == V.VecKernelSafetyAssumed)
assert(pvm.classof(dot.safety) == V.VecKernelSafetyAssumed)
assert(pvm.classof(fill.safety) == V.VecKernelSafetyAssumed)
assert(pvm.classof(inc.safety) == V.VecKernelSafetyAssumed)
assert(#inc.safety.proofs >= 2)

print("moonlift vec_kernel_plan ok")
