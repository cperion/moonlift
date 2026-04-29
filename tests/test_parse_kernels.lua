package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local bit = require("bit")
local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local Parse = require("moonlift.parse")
local Typecheck = require("moonlift.tree_typecheck")
local TreeToBack = require("moonlift.tree_to_back")
local Validate = require("moonlift.back_validate")
local J = require("moonlift.back_jit")

local T = pvm.context()
A2.Define(T)
local P = Parse.Define(T)
local TC = Typecheck.Define(T)
local Lower = TreeToBack.Define(T)
local V = Validate.Define(T)
local jit_api = J.Define(T)
local B2 = T.Moon2Back

local src = [[
export func sum_i32(xs: ptr(i32), n: i32) -> i32
    return block loop(i: i32 = 0, acc: i32 = 0) -> i32
        if i >= n then
            yield acc
        end
        jump loop(i = i + 1, acc = acc + xs[i])
    end
end

export func fill_i32(xs: ptr(i32), n: i32, value: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then
            return 0
        end
        xs[i] = value
        jump loop(i = i + 1)
    end
end

export func dot_i32(a: ptr(i32), b: ptr(i32), n: i32) -> i32
    return block loop(i: i32 = 0, acc: i32 = 0) -> i32
        if i >= n then
            yield acc
        end
        jump loop(i = i + 1, acc = acc + a[i] * b[i])
    end
end

export func prod_i32(xs: ptr(i32), n: i32) -> i32
    return block loop(i: i32 = 0, acc: i32 = 1) -> i32
        if i >= n then
            yield acc
        end
        jump loop(i = i + 1, acc = acc * xs[i])
    end
end

export func xor_reduce_i32(xs: ptr(i32), n: i32) -> i32
    return block loop(i: i32 = 0, acc: i32 = 0) -> i32
        if i >= n then
            yield acc
        end
        jump loop(i = i + 1, acc = acc ^ xs[i])
    end
end

export func copy_i32(dst: ptr(i32), src: ptr(i32), n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then
            return 0
        end
        dst[i] = src[i]
        jump loop(i = i + 1)
    end
end

export func add_i32(dst: ptr(i32), a: ptr(i32), b: ptr(i32), n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then
            return 0
        end
        dst[i] = a[i] + b[i]
        jump loop(i = i + 1)
    end
end

export func scale_i32(dst: ptr(i32), xs: ptr(i32), k: i32, n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then
            return 0
        end
        dst[i] = xs[i] * k
        jump loop(i = i + 1)
    end
end

export func inc_i32(xs: ptr(i32), n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then
            return 0
        end
        xs[i] = xs[i] + 1
        jump loop(i = i + 1)
    end
end

export func axpy_i32(y: ptr(i32), x: ptr(i32), a: i32, n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then
            return 0
        end
        y[i] = y[i] + a * x[i]
        jump loop(i = i + 1)
    end
end

export func and_i32(dst: ptr(i32), a: ptr(i32), b: ptr(i32), n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then
            return 0
        end
        dst[i] = a[i] & b[i]
        jump loop(i = i + 1)
    end
end

export func sub_i32(dst: ptr(i32), a: ptr(i32), b: ptr(i32), n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then
            return 0
        end
        dst[i] = a[i] - b[i]
        jump loop(i = i + 1)
    end
end

export func or_i32(dst: ptr(i32), a: ptr(i32), b: ptr(i32), n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then
            return 0
        end
        dst[i] = a[i] | b[i]
        jump loop(i = i + 1)
    end
end

export func xor_i32(dst: ptr(i32), a: ptr(i32), b: ptr(i32), n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then
            return 0
        end
        dst[i] = a[i] ^ b[i]
        jump loop(i = i + 1)
    end
end

export func sum_i64(xs: ptr(i64), n: i32) -> i64
    return block loop(i: i32 = 0, acc: i64 = 0) -> i64
        if i >= n then
            yield acc
        end
        jump loop(i = i + 1, acc = acc + xs[i])
    end
end

export func add_i64(dst: ptr(i64), a: ptr(i64), b: ptr(i64), n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then
            return 0
        end
        dst[i] = a[i] + b[i]
        jump loop(i = i + 1)
    end
end

export func sub_i64(dst: ptr(i64), a: ptr(i64), b: ptr(i64), n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then
            return 0
        end
        dst[i] = a[i] - b[i]
        jump loop(i = i + 1)
    end
end

export func dot_i64(a: ptr(i64), b: ptr(i64), n: i32) -> i64
    return block loop(i: i32 = 0, acc: i64 = 0) -> i64
        if i >= n then
            yield acc
        end
        jump loop(i = i + 1, acc = acc + a[i] * b[i])
    end
end

export func scale_i64(dst: ptr(i64), xs: ptr(i64), k: i64, n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then
            return 0
        end
        dst[i] = xs[i] * k
        jump loop(i = i + 1)
    end
end

export func or_i64(dst: ptr(i64), a: ptr(i64), b: ptr(i64), n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then
            return 0
        end
        dst[i] = a[i] | b[i]
        jump loop(i = i + 1)
    end
end

export func sum_u32(xs: ptr(u32), n: i32) -> u32
    return block loop(i: i32 = 0, acc: u32 = 0) -> u32
        if i >= n then
            yield acc
        end
        jump loop(i = i + 1, acc = acc + xs[i])
    end
end

export func add_u32(dst: ptr(u32), a: ptr(u32), b: ptr(u32), n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then
            return 0
        end
        dst[i] = a[i] + b[i]
        jump loop(i = i + 1)
    end
end

export func xor_u64(dst: ptr(u64), a: ptr(u64), b: ptr(u64), n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then
            return 0
        end
        dst[i] = a[i] ^ b[i]
        jump loop(i = i + 1)
    end
end

export func sum_u64(xs: ptr(u64), n: i32) -> u64
    return block loop(i: i32 = 0, acc: u64 = 0) -> u64
        if i >= n then
            yield acc
        end
        jump loop(i = i + 1, acc = acc + xs[i])
    end
end

export func add_u64(dst: ptr(u64), a: ptr(u64), b: ptr(u64), n: i32) -> i32
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
local checked = TC.check_module(parsed.module)
assert(#checked.issues == 0)
local program = Lower.module(checked.module)
local report = V.validate(program)
assert(#report.issues == 0)
local saw_vec_load, saw_vec_add, saw_vec_sub, saw_vec_mul, saw_vec_band, saw_vec_bor, saw_vec_bxor, saw_vec_store = false, false, false, false, false, false, false, false
local saw_alias_fact = false
local saw_i64x2 = false
local saw_vec_memory_proof = false
local saw_vec_alignment = false
for i = 1, #program.cmds do
    local cmd = program.cmds[i]
    if pvm.classof(cmd) == T.Moon2Back.CmdLoadInfo and pvm.classof(cmd.ty) == T.Moon2Back.BackShapeVec then
        saw_vec_load = true
        if cmd.ty.vec.elem == T.Moon2Back.BackI64 and cmd.ty.vec.lanes == 2 then saw_i64x2 = true end
        if pvm.classof(cmd.memory.trap) == T.Moon2Back.BackNonTrapping and (pvm.classof(cmd.memory.dereference) == T.Moon2Back.BackDerefBytes or pvm.classof(cmd.memory.dereference) == T.Moon2Back.BackDerefAssumed) then saw_vec_memory_proof = true end
        if pvm.classof(cmd.memory.alignment) == T.Moon2Back.BackAlignAssumed or pvm.classof(cmd.memory.alignment) == T.Moon2Back.BackAlignKnown then saw_vec_alignment = true end
    elseif pvm.classof(cmd) == T.Moon2Back.CmdVecBinary and cmd.op == T.Moon2Back.BackVecIntAdd then
        saw_vec_add = true
    elseif pvm.classof(cmd) == T.Moon2Back.CmdVecBinary and cmd.op == T.Moon2Back.BackVecIntSub then
        saw_vec_sub = true
    elseif pvm.classof(cmd) == T.Moon2Back.CmdVecBinary and cmd.op == T.Moon2Back.BackVecIntMul then
        saw_vec_mul = true
    elseif pvm.classof(cmd) == T.Moon2Back.CmdVecBinary and cmd.op == T.Moon2Back.BackVecBitAnd then
        saw_vec_band = true
    elseif pvm.classof(cmd) == T.Moon2Back.CmdVecBinary and cmd.op == T.Moon2Back.BackVecBitOr then
        saw_vec_bor = true
    elseif pvm.classof(cmd) == T.Moon2Back.CmdVecBinary and cmd.op == T.Moon2Back.BackVecBitXor then
        saw_vec_bxor = true
    elseif pvm.classof(cmd) == T.Moon2Back.CmdStoreInfo and pvm.classof(cmd.ty) == T.Moon2Back.BackShapeVec then
        saw_vec_store = true
    elseif pvm.classof(cmd) == T.Moon2Back.CmdAliasFact then
        saw_alias_fact = true
    end
end
assert(saw_vec_load, "expected vector load in sum_i32")
assert(saw_vec_add, "expected vector add in sum_i32")
assert(saw_vec_store, "expected vector store in fill_i32")
assert(saw_vec_memory_proof, "expected vector memory proof to survive into BackMemoryInfo")
assert(saw_vec_alignment, "expected vector alignment evidence to survive into BackMemoryInfo")
assert(saw_alias_fact, "expected vector alias proof/assumption to lower into BackAliasFact")
assert(saw_i64x2, "expected i64x2 vector operation in i64 kernels")
assert(saw_vec_sub, "expected vector subtract in sub_i32")
assert(saw_vec_mul, "expected vector multiply in dot_i32")
assert(saw_vec_band, "expected vector bit-and in and_i32")
assert(saw_vec_bor, "expected vector bit-or in or_i32")
assert(saw_vec_bxor, "expected vector bit-xor in xor_i32")
local artifact = jit_api.jit():compile(program)
local sum_i32 = ffi.cast("int32_t (*)(const int32_t*, int32_t)", artifact:getpointer(B2.BackFuncId("sum_i32")))
local fill_i32 = ffi.cast("int32_t (*)(int32_t*, int32_t, int32_t)", artifact:getpointer(B2.BackFuncId("fill_i32")))
local dot_i32 = ffi.cast("int32_t (*)(const int32_t*, const int32_t*, int32_t)", artifact:getpointer(B2.BackFuncId("dot_i32")))
local prod_i32 = ffi.cast("int32_t (*)(const int32_t*, int32_t)", artifact:getpointer(B2.BackFuncId("prod_i32")))
local xor_reduce_i32 = ffi.cast("int32_t (*)(const int32_t*, int32_t)", artifact:getpointer(B2.BackFuncId("xor_reduce_i32")))
local copy_i32 = ffi.cast("int32_t (*)(int32_t*, const int32_t*, int32_t)", artifact:getpointer(B2.BackFuncId("copy_i32")))
local add_i32 = ffi.cast("int32_t (*)(int32_t*, const int32_t*, const int32_t*, int32_t)", artifact:getpointer(B2.BackFuncId("add_i32")))
local scale_i32 = ffi.cast("int32_t (*)(int32_t*, const int32_t*, int32_t, int32_t)", artifact:getpointer(B2.BackFuncId("scale_i32")))
local inc_i32 = ffi.cast("int32_t (*)(int32_t*, int32_t)", artifact:getpointer(B2.BackFuncId("inc_i32")))
local axpy_i32 = ffi.cast("int32_t (*)(int32_t*, const int32_t*, int32_t, int32_t)", artifact:getpointer(B2.BackFuncId("axpy_i32")))
local and_i32 = ffi.cast("int32_t (*)(int32_t*, const int32_t*, const int32_t*, int32_t)", artifact:getpointer(B2.BackFuncId("and_i32")))
local sub_i32 = ffi.cast("int32_t (*)(int32_t*, const int32_t*, const int32_t*, int32_t)", artifact:getpointer(B2.BackFuncId("sub_i32")))
local or_i32 = ffi.cast("int32_t (*)(int32_t*, const int32_t*, const int32_t*, int32_t)", artifact:getpointer(B2.BackFuncId("or_i32")))
local xor_i32 = ffi.cast("int32_t (*)(int32_t*, const int32_t*, const int32_t*, int32_t)", artifact:getpointer(B2.BackFuncId("xor_i32")))
local sum_i64 = ffi.cast("int64_t (*)(const int64_t*, int32_t)", artifact:getpointer(B2.BackFuncId("sum_i64")))
local add_i64 = ffi.cast("int32_t (*)(int64_t*, const int64_t*, const int64_t*, int32_t)", artifact:getpointer(B2.BackFuncId("add_i64")))
local sub_i64 = ffi.cast("int32_t (*)(int64_t*, const int64_t*, const int64_t*, int32_t)", artifact:getpointer(B2.BackFuncId("sub_i64")))
local dot_i64 = ffi.cast("int64_t (*)(const int64_t*, const int64_t*, int32_t)", artifact:getpointer(B2.BackFuncId("dot_i64")))
local scale_i64 = ffi.cast("int32_t (*)(int64_t*, const int64_t*, int64_t, int32_t)", artifact:getpointer(B2.BackFuncId("scale_i64")))
local or_i64 = ffi.cast("int32_t (*)(int64_t*, const int64_t*, const int64_t*, int32_t)", artifact:getpointer(B2.BackFuncId("or_i64")))
local sum_u32 = ffi.cast("uint32_t (*)(const uint32_t*, int32_t)", artifact:getpointer(B2.BackFuncId("sum_u32")))
local add_u32 = ffi.cast("int32_t (*)(uint32_t*, const uint32_t*, const uint32_t*, int32_t)", artifact:getpointer(B2.BackFuncId("add_u32")))
local xor_u64 = ffi.cast("int32_t (*)(uint64_t*, const uint64_t*, const uint64_t*, int32_t)", artifact:getpointer(B2.BackFuncId("xor_u64")))
local sum_u64 = ffi.cast("uint64_t (*)(const uint64_t*, int32_t)", artifact:getpointer(B2.BackFuncId("sum_u64")))
local add_u64 = ffi.cast("int32_t (*)(uint64_t*, const uint64_t*, const uint64_t*, int32_t)", artifact:getpointer(B2.BackFuncId("add_u64")))
local xs = ffi.new("int32_t[8]", { 1, 2, 3, 4, 5, 6, 7, 8 })
assert(sum_i32(xs, 0) == 0)
assert(sum_i32(xs, 4) == 10)
assert(sum_i32(xs, 8) == 36)
assert(fill_i32(xs, 8, 9) == 0)
for i = 0, 7 do assert(xs[i] == 9) end
assert(sum_i32(xs, 8) == 72)
local a = ffi.new("int32_t[8]", { 1, 2, 3, 4, 5, 6, 7, 8 })
local b = ffi.new("int32_t[8]", { 2, 3, 4, 5, 6, 7, 8, 9 })
assert(dot_i32(a, b, 0) == 0)
assert(dot_i32(a, b, 4) == 40)
assert(dot_i32(a, b, 8) == 240)
assert(prod_i32(a, 0) == 1)
assert(prod_i32(a, 4) == 24)
assert(prod_i32(a, 8) == 40320)
assert(xor_reduce_i32(a, 8) == bit.bxor(bit.bxor(bit.bxor(bit.bxor(bit.bxor(bit.bxor(bit.bxor(1, 2), 3), 4), 5), 6), 7), 8))
local out = ffi.new("int32_t[8]")
assert(copy_i32(out, a, 8) == 0)
for i = 0, 7 do assert(out[i] == a[i]) end
assert(add_i32(out, a, b, 8) == 0)
for i = 0, 7 do assert(out[i] == a[i] + b[i]) end
assert(scale_i32(out, a, 3, 8) == 0)
for i = 0, 7 do assert(out[i] == a[i] * 3) end
local inplace = ffi.new("int32_t[8]", { 1, 2, 3, 4, 5, 6, 7, 8 })
assert(inc_i32(inplace, 8) == 0)
for i = 0, 7 do assert(inplace[i] == i + 2) end
local y = ffi.new("int32_t[8]", { 10, 20, 30, 40, 50, 60, 70, 80 })
assert(axpy_i32(y, a, 2, 8) == 0)
for i = 0, 7 do assert(y[i] == (i + 1) * 10 + a[i] * 2) end
assert(and_i32(out, a, b, 8) == 0)
for i = 0, 7 do assert(out[i] == bit.band(a[i], b[i])) end
assert(sub_i32(out, b, a, 8) == 0)
for i = 0, 7 do assert(out[i] == b[i] - a[i]) end
assert(or_i32(out, a, b, 8) == 0)
for i = 0, 7 do assert(out[i] == bit.bor(a[i], b[i])) end
assert(xor_i32(out, a, b, 8) == 0)
for i = 0, 7 do assert(out[i] == bit.bxor(a[i], b[i])) end
local a64 = ffi.new("int64_t[8]", { 10, 20, 30, 40, 50, 60, 70, 80 })
local b64 = ffi.new("int64_t[8]", { 1, 2, 3, 4, 5, 6, 7, 8 })
local out64 = ffi.new("int64_t[8]")
assert(tonumber(sum_i64(a64, 8)) == 360)
assert(add_i64(out64, a64, b64, 8) == 0)
for i = 0, 7 do assert(tonumber(out64[i]) == tonumber(a64[i] + b64[i])) end
assert(sub_i64(out64, a64, b64, 8) == 0)
for i = 0, 7 do assert(tonumber(out64[i]) == tonumber(a64[i] - b64[i])) end
assert(tonumber(dot_i64(a64, b64, 8)) == 2040)
assert(scale_i64(out64, a64, 3LL, 8) == 0)
for i = 0, 7 do assert(tonumber(out64[i]) == tonumber(a64[i] * 3)) end
assert(or_i64(out64, a64, b64, 8) == 0)
for i = 0, 7 do assert(tonumber(out64[i]) == bit.bor(tonumber(a64[i]), tonumber(b64[i]))) end
local a32u = ffi.new("uint32_t[8]", { 1, 2, 3, 4, 5, 6, 7, 8 })
local b32u = ffi.new("uint32_t[8]", { 10, 20, 30, 40, 50, 60, 70, 80 })
local out32u = ffi.new("uint32_t[8]")
assert(tonumber(sum_u32(a32u, 8)) == 36)
assert(add_u32(out32u, a32u, b32u, 8) == 0)
for i = 0, 7 do assert(tonumber(out32u[i]) == tonumber(a32u[i] + b32u[i])) end
local out64u = ffi.new("uint64_t[8]")
assert(xor_u64(out64u, ffi.cast("const uint64_t*", a64), ffi.cast("const uint64_t*", b64), 8) == 0)
for i = 0, 7 do assert(tonumber(out64u[i]) == bit.bxor(tonumber(a64[i]), tonumber(b64[i]))) end
assert(tonumber(sum_u64(ffi.cast("const uint64_t*", a64), 8)) == 360)
assert(add_u64(out64u, ffi.cast("const uint64_t*", a64), ffi.cast("const uint64_t*", b64), 8) == 0)
for i = 0, 7 do assert(tonumber(out64u[i]) == tonumber(a64[i] + b64[i])) end
if os.getenv("MOONLIFT_KERNEL_DISASM") == "1" then
    io.stderr:write(artifact:disasm("sum_i32", { bytes = 220 }) .. "\n")
    io.stderr:write(artifact:disasm("fill_i32", { bytes = 220 }) .. "\n")
    io.stderr:write(artifact:disasm("dot_i32", { bytes = 260 }) .. "\n")
    io.stderr:write(artifact:disasm("add_i32", { bytes = 260 }) .. "\n")
    io.stderr:write(artifact:disasm("scale_i32", { bytes = 260 }) .. "\n")
    io.stderr:write(artifact:disasm("inc_i32", { bytes = 220 }) .. "\n")
    io.stderr:write(artifact:disasm("axpy_i32", { bytes = 300 }) .. "\n")
    io.stderr:write(artifact:disasm("and_i32", { bytes = 260 }) .. "\n")
    io.stderr:write(artifact:disasm("sub_i32", { bytes = 260 }) .. "\n")
    io.stderr:write(artifact:disasm("or_i32", { bytes = 260 }) .. "\n")
    io.stderr:write(artifact:disasm("xor_i32", { bytes = 260 }) .. "\n")
    io.stderr:write(artifact:disasm("sum_i64", { bytes = 260 }) .. "\n")
    io.stderr:write(artifact:disasm("add_i64", { bytes = 260 }) .. "\n")
end
artifact:free()
print("moonlift parse_kernels ok")
