package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local bit = require("bit")
local pvm = require("moonlift.pvm")
local A1 = require("moonlift_legacy.asdl")
local A2 = require("moonlift.asdl")
local Parse = require("moonlift.parse")
local Typecheck = require("moonlift.tree_typecheck")
local ContractFacts = require("moonlift.tree_contract_facts")
local KernelPlan = require("moonlift.vec_kernel_plan")
local Lower = require("moonlift.tree_to_back")
local Validate = require("moonlift.back_validate")
local Bridge = require("moonlift.back_to_moonlift")
local J = require("moonlift_legacy.jit")

local T = pvm.context()
A1.Define(T)
A2.Define(T)
local P = Parse.Define(T)
local TC = Typecheck.Define(T)
local CF = ContractFacts.Define(T)
local KP = KernelPlan.Define(T)
local Lowerer = Lower.Define(T)
local V = Validate.Define(T)
local bridge = Bridge.Define(T)
local jit_api = J.Define(T)
local B1 = T.MoonliftBack
local C = T.Moon2Core
local Vec = T.Moon2Vec

local src = [[
export func sum_construct_view_i32(xs: ptr(i32), n: index) -> i32
    requires bounds(xs, n)
    let v: view(i32) = view(xs, n)
    return block loop(i: index = 0, acc: i32 = 0) -> i32
        if i >= len(v) then yield acc end
        jump loop(i = i + 1, acc = acc + v[i])
    end
end

export func prod_construct_view_i32(xs: ptr(i32), n: index) -> i32
    requires bounds(xs, n)
    let v: view(i32) = view(xs, n)
    return block loop(i: index = 0, acc: i32 = 1) -> i32
        if i >= len(v) then yield acc end
        jump loop(i = i + 1, acc = acc * v[i])
    end
end

export func xor_reduce_construct_view_i32(xs: ptr(i32), n: index) -> i32
    requires bounds(xs, n)
    let v: view(i32) = view(xs, n)
    return block loop(i: index = 0, acc: i32 = 0) -> i32
        if i >= len(v) then yield acc end
        jump loop(i = i + 1, acc = acc ^ v[i])
    end
end

export func dot_construct_view_i32(a: ptr(i32), b: ptr(i32), n: index) -> i32
    requires bounds(a, n)
    requires bounds(b, n)
    let va: view(i32) = view(a, n)
    let vb: view(i32) = view(b, n)
    return block loop(i: index = 0, acc: i32 = 0) -> i32
        if i >= len(va) then yield acc end
        jump loop(i = i + 1, acc = acc + va[i] * vb[i])
    end
end

export func fill_construct_view_i32(dst: ptr(i32), n: index, value: i32) -> i32
    requires bounds(dst, n)
    let vd: view(i32) = view(dst, n)
    block loop(i: index = 0)
        if i >= len(vd) then return 0 end
        vd[i] = value
        jump loop(i = i + 1)
    end
end

export func copy_construct_view_i32(noalias dst: ptr(i32), readonly src: ptr(i32), n: index) -> i32
    requires bounds(dst, n)
    requires bounds(src, n)
    requires disjoint(dst, src)
    let vd: view(i32) = view(dst, n)
    let vs: view(i32) = view(src, n)
    block loop(i: index = 0)
        if i >= len(vd) then return 0 end
        vd[i] = vs[i]
        jump loop(i = i + 1)
    end
end

export func add_construct_view_i32(noalias dst: ptr(i32), readonly a: ptr(i32), readonly b: ptr(i32), n: index) -> i32
    requires bounds(dst, n)
    requires bounds(a, n)
    requires bounds(b, n)
    requires disjoint(dst, a)
    requires disjoint(dst, b)
    let vd: view(i32) = view(dst, n)
    let va: view(i32) = view(a, n)
    let vb: view(i32) = view(b, n)
    block loop(i: index = 0)
        if i >= len(vd) then return 0 end
        vd[i] = va[i] + vb[i]
        jump loop(i = i + 1)
    end
end

export func sub_construct_view_i32(noalias dst: ptr(i32), readonly a: ptr(i32), readonly b: ptr(i32), n: index) -> i32
    requires bounds(dst, n)
    requires bounds(a, n)
    requires bounds(b, n)
    requires disjoint(dst, a)
    requires disjoint(dst, b)
    let vd: view(i32) = view(dst, n)
    let va: view(i32) = view(a, n)
    let vb: view(i32) = view(b, n)
    block loop(i: index = 0)
        if i >= len(vd) then return 0 end
        vd[i] = va[i] - vb[i]
        jump loop(i = i + 1)
    end
end

export func scale_construct_view_i32(noalias dst: ptr(i32), readonly xs: ptr(i32), k: i32, n: index) -> i32
    requires bounds(dst, n)
    requires bounds(xs, n)
    requires disjoint(dst, xs)
    let vd: view(i32) = view(dst, n)
    let vx: view(i32) = view(xs, n)
    block loop(i: index = 0)
        if i >= len(vd) then return 0 end
        vd[i] = vx[i] * k
        jump loop(i = i + 1)
    end
end

export func and_construct_view_i32(noalias dst: ptr(i32), readonly a: ptr(i32), readonly b: ptr(i32), n: index) -> i32
    requires bounds(dst, n)
    requires bounds(a, n)
    requires bounds(b, n)
    requires disjoint(dst, a)
    requires disjoint(dst, b)
    let vd: view(i32) = view(dst, n)
    let va: view(i32) = view(a, n)
    let vb: view(i32) = view(b, n)
    block loop(i: index = 0)
        if i >= len(vd) then return 0 end
        vd[i] = va[i] & vb[i]
        jump loop(i = i + 1)
    end
end

export func or_construct_view_i32(noalias dst: ptr(i32), readonly a: ptr(i32), readonly b: ptr(i32), n: index) -> i32
    requires bounds(dst, n)
    requires bounds(a, n)
    requires bounds(b, n)
    requires disjoint(dst, a)
    requires disjoint(dst, b)
    let vd: view(i32) = view(dst, n)
    let va: view(i32) = view(a, n)
    let vb: view(i32) = view(b, n)
    block loop(i: index = 0)
        if i >= len(vd) then return 0 end
        vd[i] = va[i] | vb[i]
        jump loop(i = i + 1)
    end
end

export func xor_construct_view_i32(noalias dst: ptr(i32), readonly a: ptr(i32), readonly b: ptr(i32), n: index) -> i32
    requires bounds(dst, n)
    requires bounds(a, n)
    requires bounds(b, n)
    requires disjoint(dst, a)
    requires disjoint(dst, b)
    let vd: view(i32) = view(dst, n)
    let va: view(i32) = view(a, n)
    let vb: view(i32) = view(b, n)
    block loop(i: index = 0)
        if i >= len(vd) then return 0 end
        vd[i] = va[i] ^ vb[i]
        jump loop(i = i + 1)
    end
end

export func inc_construct_view_i32(xs: ptr(i32), n: index) -> i32
    requires bounds(xs, n)
    let vx: view(i32) = view(xs, n)
    block loop(i: index = 0)
        if i >= len(vx) then return 0 end
        vx[i] = vx[i] + 1
        jump loop(i = i + 1)
    end
end

export func axpy_construct_view_i32(noalias y: ptr(i32), readonly x: ptr(i32), a: i32, n: index) -> i32
    requires bounds(y, n)
    requires bounds(x, n)
    requires disjoint(y, x)
    let vy: view(i32) = view(y, n)
    let vx: view(i32) = view(x, n)
    block loop(i: index = 0)
        if i >= len(vy) then return 0 end
        vy[i] = vy[i] + a * vx[i]
        jump loop(i = i + 1)
    end
end

export func sum_construct_view_i64(xs: ptr(i64), n: index) -> i64
    requires bounds(xs, n)
    let v: view(i64) = view(xs, n)
    return block loop(i: index = 0, acc: i64 = 0) -> i64
        if i >= len(v) then yield acc end
        jump loop(i = i + 1, acc = acc + v[i])
    end
end

export func dot_construct_view_i64(a: ptr(i64), b: ptr(i64), n: index) -> i64
    requires bounds(a, n)
    requires bounds(b, n)
    let va: view(i64) = view(a, n)
    let vb: view(i64) = view(b, n)
    return block loop(i: index = 0, acc: i64 = 0) -> i64
        if i >= len(va) then yield acc end
        jump loop(i = i + 1, acc = acc + va[i] * vb[i])
    end
end

export func add_construct_view_i64(noalias dst: ptr(i64), readonly a: ptr(i64), readonly b: ptr(i64), n: index) -> i32
    requires bounds(dst, n)
    requires bounds(a, n)
    requires bounds(b, n)
    requires disjoint(dst, a)
    requires disjoint(dst, b)
    let vd: view(i64) = view(dst, n)
    let va: view(i64) = view(a, n)
    let vb: view(i64) = view(b, n)
    block loop(i: index = 0)
        if i >= len(vd) then return 0 end
        vd[i] = va[i] + vb[i]
        jump loop(i = i + 1)
    end
end

export func sub_construct_view_i64(noalias dst: ptr(i64), readonly a: ptr(i64), readonly b: ptr(i64), n: index) -> i32
    requires bounds(dst, n)
    requires bounds(a, n)
    requires bounds(b, n)
    requires disjoint(dst, a)
    requires disjoint(dst, b)
    let vd: view(i64) = view(dst, n)
    let va: view(i64) = view(a, n)
    let vb: view(i64) = view(b, n)
    block loop(i: index = 0)
        if i >= len(vd) then return 0 end
        vd[i] = va[i] - vb[i]
        jump loop(i = i + 1)
    end
end

export func scale_construct_view_i64(noalias dst: ptr(i64), readonly xs: ptr(i64), k: i64, n: index) -> i32
    requires bounds(dst, n)
    requires bounds(xs, n)
    requires disjoint(dst, xs)
    let vd: view(i64) = view(dst, n)
    let vx: view(i64) = view(xs, n)
    block loop(i: index = 0)
        if i >= len(vd) then return 0 end
        vd[i] = vx[i] * k
        jump loop(i = i + 1)
    end
end

export func or_construct_view_i64(noalias dst: ptr(i64), readonly a: ptr(i64), readonly b: ptr(i64), n: index) -> i32
    requires bounds(dst, n)
    requires bounds(a, n)
    requires bounds(b, n)
    requires disjoint(dst, a)
    requires disjoint(dst, b)
    let vd: view(i64) = view(dst, n)
    let va: view(i64) = view(a, n)
    let vb: view(i64) = view(b, n)
    block loop(i: index = 0)
        if i >= len(vd) then return 0 end
        vd[i] = va[i] | vb[i]
        jump loop(i = i + 1)
    end
end

export func sum_construct_view_u32(xs: ptr(u32), n: index) -> u32
    requires bounds(xs, n)
    let v: view(u32) = view(xs, n)
    return block loop(i: index = 0, acc: u32 = 0) -> u32
        if i >= len(v) then yield acc end
        jump loop(i = i + 1, acc = acc + v[i])
    end
end

export func add_construct_view_u32(noalias dst: ptr(u32), readonly a: ptr(u32), readonly b: ptr(u32), n: index) -> i32
    requires bounds(dst, n)
    requires bounds(a, n)
    requires bounds(b, n)
    requires disjoint(dst, a)
    requires disjoint(dst, b)
    let vd: view(u32) = view(dst, n)
    let va: view(u32) = view(a, n)
    let vb: view(u32) = view(b, n)
    block loop(i: index = 0)
        if i >= len(vd) then return 0 end
        vd[i] = va[i] + vb[i]
        jump loop(i = i + 1)
    end
end

export func sub_construct_view_u32(noalias dst: ptr(u32), readonly a: ptr(u32), readonly b: ptr(u32), n: index) -> i32
    requires bounds(dst, n)
    requires bounds(a, n)
    requires bounds(b, n)
    requires disjoint(dst, a)
    requires disjoint(dst, b)
    let vd: view(u32) = view(dst, n)
    let va: view(u32) = view(a, n)
    let vb: view(u32) = view(b, n)
    block loop(i: index = 0)
        if i >= len(vd) then return 0 end
        vd[i] = va[i] - vb[i]
        jump loop(i = i + 1)
    end
end

export func xor_construct_view_u32(noalias dst: ptr(u32), readonly a: ptr(u32), readonly b: ptr(u32), n: index) -> i32
    requires bounds(dst, n)
    requires bounds(a, n)
    requires bounds(b, n)
    requires disjoint(dst, a)
    requires disjoint(dst, b)
    let vd: view(u32) = view(dst, n)
    let va: view(u32) = view(a, n)
    let vb: view(u32) = view(b, n)
    block loop(i: index = 0)
        if i >= len(vd) then return 0 end
        vd[i] = va[i] ^ vb[i]
        jump loop(i = i + 1)
    end
end

export func sum_construct_view_u64(xs: ptr(u64), n: index) -> u64
    requires bounds(xs, n)
    let v: view(u64) = view(xs, n)
    return block loop(i: index = 0, acc: u64 = 0) -> u64
        if i >= len(v) then yield acc end
        jump loop(i = i + 1, acc = acc + v[i])
    end
end

export func add_construct_view_u64(noalias dst: ptr(u64), readonly a: ptr(u64), readonly b: ptr(u64), n: index) -> i32
    requires bounds(dst, n)
    requires bounds(a, n)
    requires bounds(b, n)
    requires disjoint(dst, a)
    requires disjoint(dst, b)
    let vd: view(u64) = view(dst, n)
    let va: view(u64) = view(a, n)
    let vb: view(u64) = view(b, n)
    block loop(i: index = 0)
        if i >= len(vd) then return 0 end
        vd[i] = va[i] + vb[i]
        jump loop(i = i + 1)
    end
end

export func xor_construct_view_u64(noalias dst: ptr(u64), readonly a: ptr(u64), readonly b: ptr(u64), n: index) -> i32
    requires bounds(dst, n)
    requires bounds(a, n)
    requires bounds(b, n)
    requires disjoint(dst, a)
    requires disjoint(dst, b)
    let vd: view(u64) = view(dst, n)
    let va: view(u64) = view(a, n)
    let vb: view(u64) = view(b, n)
    block loop(i: index = 0)
        if i >= len(vd) then return 0 end
        vd[i] = va[i] ^ vb[i]
        jump loop(i = i + 1)
    end
end
]]

local parsed = P.parse_module(src)
assert(#parsed.issues == 0)
local checked = TC.check_module(parsed.module)
assert(#checked.issues == 0)
for i = 1, #checked.module.items do
    local func = checked.module.items[i].func
    local plan = KP.plan(func.name, C.VisibilityExport, func.params, func.result, func.body, CF.facts(func).facts)
    local cls = pvm.classof(plan)
    assert(cls == Vec.VecKernelMap or cls == Vec.VecKernelReduce, func.name)
    assert(pvm.classof(plan.safety) == Vec.VecKernelSafetyProven, func.name)
end

local program = Lowerer.module(checked.module)
local report = V.validate(program)
assert(#report.issues == 0)
local saw = { add = false, sub = false, mul = false, band = false, bor = false, bxor = false, i64 = false, u64 = false }
for i = 1, #program.cmds do
    local cmd = program.cmds[i]
    if pvm.classof(cmd) == T.Moon2Back.CmdBinary then
        if cmd.op == T.Moon2Back.BackVecIadd then saw.add = true end
        if cmd.op == T.Moon2Back.BackVecIsub then saw.sub = true end
        if cmd.op == T.Moon2Back.BackVecImul then saw.mul = true end
        if cmd.op == T.Moon2Back.BackVecBand then saw.band = true end
        if cmd.op == T.Moon2Back.BackVecBor then saw.bor = true end
        if cmd.op == T.Moon2Back.BackVecBxor then saw.bxor = true end
    elseif pvm.classof(cmd) == T.Moon2Back.CmdLoad and pvm.classof(cmd.ty) == T.Moon2Back.BackShapeVec then
        if cmd.ty.vec.elem == T.Moon2Back.BackI64 and cmd.ty.vec.lanes == 2 then saw.i64 = true end
        if cmd.ty.vec.elem == T.Moon2Back.BackU64 and cmd.ty.vec.lanes == 2 then saw.u64 = true end
    end
end
assert(saw.add and saw.sub and saw.mul and saw.band and saw.bor and saw.bxor and saw.i64 and saw.u64)

local artifact = jit_api.jit():compile(bridge.lower_program(program))
local function fn(name, sig) return ffi.cast(sig, artifact:getpointer(B1.BackFuncId(name))) end
local sum_i32 = fn("sum_construct_view_i32", "int32_t (*)(const int32_t*, intptr_t)")
local prod_i32 = fn("prod_construct_view_i32", "int32_t (*)(const int32_t*, intptr_t)")
local xor_red_i32 = fn("xor_reduce_construct_view_i32", "int32_t (*)(const int32_t*, intptr_t)")
local dot_i32 = fn("dot_construct_view_i32", "int32_t (*)(const int32_t*, const int32_t*, intptr_t)")
local fill_i32 = fn("fill_construct_view_i32", "int32_t (*)(int32_t*, intptr_t, int32_t)")
local copy_i32 = fn("copy_construct_view_i32", "int32_t (*)(int32_t*, const int32_t*, intptr_t)")
local add_i32 = fn("add_construct_view_i32", "int32_t (*)(int32_t*, const int32_t*, const int32_t*, intptr_t)")
local sub_i32 = fn("sub_construct_view_i32", "int32_t (*)(int32_t*, const int32_t*, const int32_t*, intptr_t)")
local scale_i32 = fn("scale_construct_view_i32", "int32_t (*)(int32_t*, const int32_t*, int32_t, intptr_t)")
local and_i32 = fn("and_construct_view_i32", "int32_t (*)(int32_t*, const int32_t*, const int32_t*, intptr_t)")
local or_i32 = fn("or_construct_view_i32", "int32_t (*)(int32_t*, const int32_t*, const int32_t*, intptr_t)")
local xor_i32 = fn("xor_construct_view_i32", "int32_t (*)(int32_t*, const int32_t*, const int32_t*, intptr_t)")
local inc_i32 = fn("inc_construct_view_i32", "int32_t (*)(int32_t*, intptr_t)")
local axpy_i32 = fn("axpy_construct_view_i32", "int32_t (*)(int32_t*, const int32_t*, int32_t, intptr_t)")
local sum_i64 = fn("sum_construct_view_i64", "int64_t (*)(const int64_t*, intptr_t)")
local dot_i64 = fn("dot_construct_view_i64", "int64_t (*)(const int64_t*, const int64_t*, intptr_t)")
local add_i64 = fn("add_construct_view_i64", "int32_t (*)(int64_t*, const int64_t*, const int64_t*, intptr_t)")
local sub_i64 = fn("sub_construct_view_i64", "int32_t (*)(int64_t*, const int64_t*, const int64_t*, intptr_t)")
local scale_i64 = fn("scale_construct_view_i64", "int32_t (*)(int64_t*, const int64_t*, int64_t, intptr_t)")
local or_i64 = fn("or_construct_view_i64", "int32_t (*)(int64_t*, const int64_t*, const int64_t*, intptr_t)")
local sum_u32 = fn("sum_construct_view_u32", "uint32_t (*)(const uint32_t*, intptr_t)")
local add_u32 = fn("add_construct_view_u32", "int32_t (*)(uint32_t*, const uint32_t*, const uint32_t*, intptr_t)")
local sub_u32 = fn("sub_construct_view_u32", "int32_t (*)(uint32_t*, const uint32_t*, const uint32_t*, intptr_t)")
local xor_u32 = fn("xor_construct_view_u32", "int32_t (*)(uint32_t*, const uint32_t*, const uint32_t*, intptr_t)")
local sum_u64 = fn("sum_construct_view_u64", "uint64_t (*)(const uint64_t*, intptr_t)")
local add_u64 = fn("add_construct_view_u64", "int32_t (*)(uint64_t*, const uint64_t*, const uint64_t*, intptr_t)")
local xor_u64 = fn("xor_construct_view_u64", "int32_t (*)(uint64_t*, const uint64_t*, const uint64_t*, intptr_t)")

local a = ffi.new("int32_t[9]", { 1, 2, 3, 4, 5, 6, 7, 8, 9 })
local b = ffi.new("int32_t[9]", { 10, 20, 30, 40, 50, 60, 70, 80, 90 })
local out = ffi.new("int32_t[9]")
assert(sum_i32(a, 9) == 45)
assert(prod_i32(a, 9) == 362880)
assert(xor_red_i32(a, 9) == bit.bxor(bit.bxor(bit.bxor(bit.bxor(bit.bxor(bit.bxor(bit.bxor(bit.bxor(1, 2), 3), 4), 5), 6), 7), 8), 9))
assert(dot_i32(a, b, 9) == 2850)
assert(fill_i32(out, 9, 7) == 0); for i = 0, 8 do assert(out[i] == 7) end
assert(copy_i32(out, a, 9) == 0); for i = 0, 8 do assert(out[i] == a[i]) end
assert(add_i32(out, a, b, 9) == 0); for i = 0, 8 do assert(out[i] == a[i] + b[i]) end
assert(sub_i32(out, b, a, 9) == 0); for i = 0, 8 do assert(out[i] == b[i] - a[i]) end
assert(scale_i32(out, a, 3, 9) == 0); for i = 0, 8 do assert(out[i] == a[i] * 3) end
assert(and_i32(out, a, b, 9) == 0); for i = 0, 8 do assert(out[i] == bit.band(a[i], b[i])) end
assert(or_i32(out, a, b, 9) == 0); for i = 0, 8 do assert(out[i] == bit.bor(a[i], b[i])) end
assert(xor_i32(out, a, b, 9) == 0); for i = 0, 8 do assert(out[i] == bit.bxor(a[i], b[i])) end
local in_place = ffi.new("int32_t[9]", { 1, 2, 3, 4, 5, 6, 7, 8, 9 })
assert(inc_i32(in_place, 9) == 0); for i = 0, 8 do assert(in_place[i] == i + 2) end
local y = ffi.new("int32_t[9]", { 10, 20, 30, 40, 50, 60, 70, 80, 90 })
assert(axpy_i32(y, a, 2, 9) == 0); for i = 0, 8 do assert(y[i] == (i + 1) * 10 + a[i] * 2) end

local a64 = ffi.new("int64_t[9]", { 10, 20, 30, 40, 50, 60, 70, 80, 90 })
local b64 = ffi.new("int64_t[9]", { 1, 2, 3, 4, 5, 6, 7, 8, 9 })
local out64 = ffi.new("int64_t[9]")
assert(tonumber(sum_i64(a64, 9)) == 450)
assert(tonumber(dot_i64(a64, b64, 9)) == 2850)
assert(add_i64(out64, a64, b64, 9) == 0); for i = 0, 8 do assert(tonumber(out64[i]) == tonumber(a64[i] + b64[i])) end
assert(sub_i64(out64, a64, b64, 9) == 0); for i = 0, 8 do assert(tonumber(out64[i]) == tonumber(a64[i] - b64[i])) end
assert(scale_i64(out64, a64, 3LL, 9) == 0); for i = 0, 8 do assert(tonumber(out64[i]) == tonumber(a64[i] * 3)) end
assert(or_i64(out64, a64, b64, 9) == 0); for i = 0, 8 do assert(tonumber(out64[i]) == bit.bor(tonumber(a64[i]), tonumber(b64[i]))) end

local au32 = ffi.new("uint32_t[9]", { 1, 2, 3, 4, 5, 6, 7, 8, 9 })
local bu32 = ffi.new("uint32_t[9]", { 10, 20, 30, 40, 50, 60, 70, 80, 90 })
local outu32 = ffi.new("uint32_t[9]")
assert(tonumber(sum_u32(au32, 9)) == 45)
assert(add_u32(outu32, au32, bu32, 9) == 0); for i = 0, 8 do assert(tonumber(outu32[i]) == tonumber(au32[i] + bu32[i])) end
assert(sub_u32(outu32, bu32, au32, 9) == 0); for i = 0, 8 do assert(tonumber(outu32[i]) == tonumber(bu32[i] - au32[i])) end
assert(xor_u32(outu32, au32, bu32, 9) == 0); for i = 0, 8 do assert(tonumber(outu32[i]) == bit.bxor(tonumber(au32[i]), tonumber(bu32[i]))) end

local outu64 = ffi.new("uint64_t[9]")
assert(tonumber(sum_u64(ffi.cast("const uint64_t*", a64), 9)) == 450)
assert(add_u64(outu64, ffi.cast("const uint64_t*", a64), ffi.cast("const uint64_t*", b64), 9) == 0); for i = 0, 8 do assert(tonumber(outu64[i]) == tonumber(a64[i] + b64[i])) end
assert(xor_u64(outu64, ffi.cast("const uint64_t*", a64), ffi.cast("const uint64_t*", b64), 9) == 0); for i = 0, 8 do assert(tonumber(outu64[i]) == bit.bxor(tonumber(a64[i]), tonumber(b64[i]))) end

artifact:free()
print("moonlift parse_view_construct_family ok")
