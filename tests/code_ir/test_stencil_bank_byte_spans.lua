package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")

local T = pvm.context()
Schema(T)

local Core = T.LalinCore
local Code = T.LalinCode
local Value = T.LalinValue
local Stencil = T.LalinStencil
local StencilArtifactPlan = require("lalin.stencil_artifact_plan")(T)
local StencilBinary = require("tests.code_ir.stencil_binary_helper")

local u8 = Code.CodeTyInt(8, Code.CodeUnsigned)
local bool8 = Code.CodeTyBool8

local function u8const(raw)
    return Value.ValueExprConst(Code.CodeConstLiteral(u8, Core.LitInt(tostring(raw))))
end

local function bytespan_topology(name)
    return Stencil.StencilTopologyByteSpanDescriptor(
        Code.CodeValueId("v:bytespan:" .. name),
        Code.CodeValueId("v:data:" .. name),
        Code.CodeValueId("v:len:" .. name)
    )
end

local artifacts = {
    StencilArtifactPlan.copy_array_artifact({ elem_ty = u8, step_num = 1, dst_topology = bytespan_topology("copy_dst"), src_topology = bytespan_topology("copy_src") }),
    StencilArtifactPlan.copy_array_artifact({ elem_ty = u8, semantics = Stencil.StencilCopyMemMove, step_num = 1, dst_topology = bytespan_topology("move_dst"), src_topology = bytespan_topology("move_src") }),
    StencilArtifactPlan.fill_array_artifact({ elem_ty = u8, value = u8const(127), step_num = 1, dst_topology = bytespan_topology("fill_dst") }),
    StencilArtifactPlan.find_array_artifact(Stencil.StencilPredEqConst(u8const(13)), { elem_ty = u8, step_num = 1, array_topology = bytespan_topology("find_xs") }),
    StencilArtifactPlan.compare_array_artifact(Stencil.StencilPredGtConst(u8const(9)), { elem_ty = u8, result_ty = bool8, step_num = 1, dst_topology = bytespan_topology("compare_dst"), src_topology = bytespan_topology("compare_xs") }),
    StencilArtifactPlan.count_array_artifact(Stencil.StencilPredGtConst(u8const(9)), { elem_ty = u8, step_num = 1, array_topology = bytespan_topology("count_xs") }),
}

local build, err, src = StencilBinary.compile(T, artifacts, { stem = "test_stencil_bank_byte_spans" })
assert(build ~= nil, tostring(err) .. "\n" .. tostring(src))

local xs = ffi.new("uint8_t[6]", { 3, 5, 255, 8, 13, 21 })
local out = ffi.new("uint8_t[6]")
local mask = ffi.new("uint8_t[6]")

local function sym(artifact)
    return assert(build.symbols[artifact.symbol.text], artifact.symbol.text)
end

sym(artifacts[1])(out, xs, 0, 6)
for i = 0, 5 do assert(out[i] == xs[i], "byte copy mismatch") end

local overlap = ffi.new("uint8_t[7]", { 1, 2, 3, 4, 5, 6, 7 })
sym(artifacts[2])(overlap + 1, overlap, 0, 6)
assert(overlap[0] == 1 and overlap[1] == 1 and overlap[2] == 2 and overlap[3] == 3 and overlap[4] == 4 and overlap[5] == 5 and overlap[6] == 6, "byte memmove")

sym(artifacts[3])(out, 0, 6, 127)
for i = 0, 5 do assert(out[i] == 127, "byte fill mismatch") end

assert(sym(artifacts[4])(xs, 0, 6) == 4, "byte find")

sym(artifacts[5])(mask, xs, 0, 6)
assert(mask[0] == 0 and mask[1] == 0 and mask[2] == 1 and mask[3] == 0 and mask[4] == 1 and mask[5] == 1, "byte compare")

assert(sym(artifacts[6])(xs, 0, 6) == 3, "byte count")

io.write("lalin stencil_bank byte spans ok\n")
