package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local Parse = require("moonlift.parse")
local Pipeline = require("moonlift.frontend_pipeline")
local Jit = require("moonlift.back_jit")

local T = pvm.context()
A2.Define(T)
local C, Ty, B, Tr, Back = T.MoonCore, T.MoonType, T.MoonBind, T.MoonTree, T.MoonBack
local i32 = Ty.TScalar(C.ScalarI32)
local index = Ty.TScalar(C.ScalarIndex)
local view_i32 = Ty.TView(i32)

local function ref(name) return Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(name)) end
local function int(n) return Tr.ExprLit(Tr.ExprSurface, C.LitInt(tostring(n))) end

local src = [[
func restrided_sum(xs: ptr(i32)): i32
    let v: view(i32) = view(xs, 3)
    return block loop(i: index = 0, acc: i32 = 0): i32
        if i >= len(v) then yield acc end
        jump loop(i = i + 1, acc = acc + v[i])
    end
end

func row_base_sum(xs: ptr(i32)): i32
    let v: view(i32) = view(xs, 3)
    return block loop(i: index = 0, acc: i32 = 0): i32
        if i >= len(v) then yield acc end
        jump loop(i = i + 1, acc = acc + v[i])
    end
end

func interleaved_raw_sum(xs: ptr(i32)): i32
    let v: view(i32) = view(xs, 3)
    return block loop(i: index = 0, acc: i32 = 0): i32
        if i >= len(v) then yield acc end
        jump loop(i = i + 1, acc = acc + v[i])
    end
end

func interleaved_view_sum(xs: ptr(i32)): i32
    let v: view(i32) = view(xs, 3)
    return block loop(i: index = 0, acc: i32 = 0): i32
        if i >= len(v) then yield acc end
        jump loop(i = i + 1, acc = acc + v[i])
    end
end
]]

local parsed = Parse.Define(T).parse_module(src)
assert(#parsed.issues == 0, tostring(parsed.issues[1]))

local replacements = {
    restrided_sum = Tr.ExprView(Tr.ExprSurface,
        Tr.ViewRestrided(Tr.ViewContiguous(ref("xs"), i32, int(3)), i32, int(2))),
    row_base_sum = Tr.ExprView(Tr.ExprSurface,
        Tr.ViewRowBase(Tr.ViewContiguous(ref("xs"), i32, int(3)), int(4), i32)),
    interleaved_raw_sum = Tr.ExprView(Tr.ExprSurface,
        Tr.ViewInterleaved(ref("xs"), i32, int(3), int(3), int(1))),
    interleaved_view_sum = Tr.ExprView(Tr.ExprSurface,
        Tr.ViewInterleavedView(Tr.ViewStrided(ref("xs"), i32, int(3), int(2)), i32, int(3), int(1))),
}

local items = {}
for i = 1, #parsed.module.items do
    local item = parsed.module.items[i]
    if pvm.classof(item) == Tr.ItemFunc and replacements[item.func.name] then
        local body = {}
        for j = 1, #item.func.body do body[j] = item.func.body[j] end
        body[1] = pvm.with(body[1], { init = replacements[item.func.name] })
        items[i] = pvm.with(item, { func = pvm.with(item.func, { body = body }) })
    else
        items[i] = item
    end
end

local module = pvm.with(parsed.module, { items = items })
local program = Pipeline.Define(T).lower_module(module, { site = "advanced views test" }).program
local artifact = Jit.Define(T).jit():compile(program)
local restrided = ffi.cast("int32_t (*)(const int32_t*)", artifact:getpointer(Back.BackFuncId("restrided_sum")))
local row = ffi.cast("int32_t (*)(const int32_t*)", artifact:getpointer(Back.BackFuncId("row_base_sum")))
local raw = ffi.cast("int32_t (*)(const int32_t*)", artifact:getpointer(Back.BackFuncId("interleaved_raw_sum")))
local composed = ffi.cast("int32_t (*)(const int32_t*)", artifact:getpointer(Back.BackFuncId("interleaved_view_sum")))

local xs = ffi.new("int32_t[16]")
for i = 0, 15 do xs[i] = i + 1 end

assert(restrided(xs) == 1 + 3 + 5)
assert(row(xs) == 5 + 6 + 7)
assert(raw(xs) == 2 + 5 + 8)
assert(composed(xs) == 3 + 9 + 15)
artifact:free()

print("moonlift advanced view lowering ok")
