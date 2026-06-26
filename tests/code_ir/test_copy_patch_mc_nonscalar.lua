package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local LLBL = require("llbl")
local LC = require("llbl.c")
local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")

local T = pvm.context()
Schema(T)

local Code = T.LalinCode
local C = T.LalinC
local Stencil = T.LalinStencil
local Ty = T.LalinType
local Plan = require("lalin.stencil_artifact_plan")(T)
local StencilBinary = require("tests.code_ir.copy_patch_mc_helper")

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local ptr_i32 = Code.CodeTyDataPtr(i32)
local named_pair = Code.CodeTyNamed("Demo", "Pair", Ty.TNamed(Ty.TypeRefGlobal("Demo", "Pair")))
local imported_pair = Code.CodeTyImportedC(C.CTypeId("Host", "HostPair"))
local arr2_i32 = Code.CodeTyArray(i32, 2)
local slice_i32 = Code.CodeTySlice(i32)
local view_i32 = Code.CodeTyView(i32)
local byte_span = Code.CodeTyByteSpan
local closure_sig = Code.CodeSigId("codesig_i32_to_i32")
local closure_i32 = Code.CodeTyClosure(closure_sig)
local cfunc_i32 = Code.CodeTyImportedCFuncPtr(C.CFuncSigId("host_callback"))
local vec4_i32 = Code.CodeTyVector(i32, 4)

local artifacts = {
    ptr_copy = Plan.copy_array_artifact({ elem_ty = ptr_i32, step_num = 1 }),
    ptr_move = Plan.copy_array_artifact({ elem_ty = ptr_i32, semantics = Stencil.StencilCopyMemMove, step_num = 1 }),
    ptr_gather = Plan.gather_array_artifact({ elem_ty = ptr_i32, index_ty = i32, step_num = 1 }),
    ptr_scatter = Plan.scatter_array_artifact({ elem_ty = ptr_i32, index_ty = i32, conflicts = Stencil.StencilScatterUniqueIndices, step_num = 1 }),
    ptr_identity = Plan.map_array_artifact(Stencil.StencilUnaryIdentity, { elem_ty = ptr_i32, result_ty = ptr_i32, step_num = 1 }),
    named_copy = Plan.copy_array_artifact({ elem_ty = named_pair, semantics = Stencil.StencilCopyMemMove, step_num = 1 }),
    named_identity = Plan.map_array_artifact(Stencil.StencilUnaryIdentity, { elem_ty = named_pair, result_ty = named_pair, step_num = 1 }),
    imported_copy = Plan.copy_array_artifact({ elem_ty = imported_pair, semantics = Stencil.StencilCopyMemMove, step_num = 1 }),
    array_copy = Plan.copy_array_artifact({ elem_ty = arr2_i32, semantics = Stencil.StencilCopyMemMove, step_num = 1 }),
    array_gather = Plan.gather_array_artifact({ elem_ty = arr2_i32, index_ty = i32, step_num = 1 }),
    array_scatter = Plan.scatter_array_artifact({ elem_ty = arr2_i32, index_ty = i32, conflicts = Stencil.StencilScatterUniqueIndices, step_num = 1 }),
    array_identity = Plan.map_array_artifact(Stencil.StencilUnaryIdentity, { elem_ty = arr2_i32, result_ty = arr2_i32, step_num = 1 }),
    slice_copy = Plan.copy_array_artifact({ elem_ty = slice_i32, semantics = Stencil.StencilCopyMemMove, step_num = 1 }),
    slice_identity = Plan.map_array_artifact(Stencil.StencilUnaryIdentity, { elem_ty = slice_i32, result_ty = slice_i32, step_num = 1 }),
    view_copy = Plan.copy_array_artifact({ elem_ty = view_i32, semantics = Stencil.StencilCopyMemMove, step_num = 1 }),
    bytespan_copy = Plan.copy_array_artifact({ elem_ty = byte_span, semantics = Stencil.StencilCopyMemMove, step_num = 1 }),
    closure_copy = Plan.copy_array_artifact({ elem_ty = closure_i32, semantics = Stencil.StencilCopyMemMove, step_num = 1 }),
    closure_gather = Plan.gather_array_artifact({ elem_ty = closure_i32, index_ty = i32, step_num = 1 }),
    closure_scatter = Plan.scatter_array_artifact({ elem_ty = closure_i32, index_ty = i32, conflicts = Stencil.StencilScatterUniqueIndices, step_num = 1 }),
    closure_identity = Plan.map_array_artifact(Stencil.StencilUnaryIdentity, { elem_ty = closure_i32, result_ty = closure_i32, step_num = 1 }),
    cfunc_copy = Plan.copy_array_artifact({ elem_ty = cfunc_i32, semantics = Stencil.StencilCopyMemMove, step_num = 1 }),
    cfunc_gather = Plan.gather_array_artifact({ elem_ty = cfunc_i32, index_ty = i32, step_num = 1 }),
    cfunc_scatter = Plan.scatter_array_artifact({ elem_ty = cfunc_i32, index_ty = i32, conflicts = Stencil.StencilScatterUniqueIndices, step_num = 1 }),
    cfunc_identity = Plan.map_array_artifact(Stencil.StencilUnaryIdentity, { elem_ty = cfunc_i32, result_ty = cfunc_i32, step_num = 1 }),
    vector_copy = Plan.copy_array_artifact({ elem_ty = vec4_i32, semantics = Stencil.StencilCopyMemMove, step_num = 1 }),
    vector_gather = Plan.gather_array_artifact({ elem_ty = vec4_i32, index_ty = i32, step_num = 1 }),
    vector_scatter = Plan.scatter_array_artifact({ elem_ty = vec4_i32, index_ty = i32, conflicts = Stencil.StencilScatterUniqueIndices, step_num = 1 }),
    vector_identity = Plan.map_array_artifact(Stencil.StencilUnaryIdentity, { elem_ty = vec4_i32, result_ty = vec4_i32, step_num = 1 }),
}

local ordered = {
    artifacts.ptr_copy,
    artifacts.ptr_move,
    artifacts.ptr_gather,
    artifacts.ptr_scatter,
    artifacts.ptr_identity,
    artifacts.named_copy,
    artifacts.named_identity,
    artifacts.imported_copy,
    artifacts.array_copy,
    artifacts.array_gather,
    artifacts.array_scatter,
    artifacts.array_identity,
    artifacts.slice_copy,
    artifacts.slice_identity,
    artifacts.view_copy,
    artifacts.bytespan_copy,
    artifacts.closure_copy,
    artifacts.closure_gather,
    artifacts.closure_scatter,
    artifacts.closure_identity,
    artifacts.cfunc_copy,
    artifacts.cfunc_gather,
    artifacts.cfunc_scatter,
    artifacts.cfunc_identity,
    artifacts.vector_copy,
    artifacts.vector_gather,
    artifacts.vector_scatter,
    artifacts.vector_identity,
}

local ffi_preamble = [[
typedef struct { int32_t left; int32_t right; } Demo_Pair;
typedef struct { int32_t left; int32_t right; } HostPair;
typedef HostPair Host_HostPair;
typedef struct { int32_t data[2]; } ml_array_2_i32;
typedef struct { int32_t* data; intptr_t len; } ml_slice_CBackendScalar_ScalarI32;
typedef struct { int32_t* data; intptr_t len; intptr_t stride; } ml_view_CBackendScalar_ScalarI32;
typedef struct { uint8_t* data; intptr_t len; } ml_bytespan;
typedef struct { void (*fn)(void); void* ctx; } ml_closure_codesig_i32_to_i32;
typedef void (*ml_cfuncptr_host_callback)(void);
typedef struct { int32_t lane[4]; } ml_vector_4_i32;
]]

local c_decls = {
    LC.typedef_struct [LLBL.N.Demo_Pair] {
        LLBL.N.left [LC.i32],
        LLBL.N.right [LC.i32],
    },
    LC.typedef_struct [LLBL.N.HostPair] {
        LLBL.N.left [LC.i32],
        LLBL.N.right [LC.i32],
    },
    LC.typedef. Host_HostPair [LC.type.HostPair],
    LC.typedef_struct [LLBL.N.ml_array_2_i32] {
        LLBL.N.data [LC.array [LC.i32] [2]],
    },
    LC.typedef_struct [LLBL.N.ml_slice_CBackendScalar_ScalarI32] {
        LLBL.N.data [LC.ptr [LC.i32]],
        LLBL.N.len [LC.intptr_t],
    },
    LC.typedef_struct [LLBL.N.ml_view_CBackendScalar_ScalarI32] {
        LLBL.N.data [LC.ptr [LC.i32]],
        LLBL.N.len [LC.intptr_t],
        LLBL.N.stride [LC.intptr_t],
    },
    LC.typedef_struct [LLBL.N.ml_bytespan] {
        LLBL.N.data [LC.ptr [LC.u8]],
        LLBL.N.len [LC.intptr_t],
    },
    LC.typedef_struct [LLBL.N.ml_closure_codesig_i32_to_i32] {
        LLBL.N.fn [LC.fnptr [{}] [LC.void]],
        LLBL.N.ctx [LC.void_ptr],
    },
    LC.typedef. ml_cfuncptr_host_callback [LC.fnptr [{}] [LC.void]],
    LC.typedef_struct [LLBL.N.ml_vector_4_i32] {
        LLBL.N.lane [LC.array [LC.i32] [4]],
    },
}

ffi.cdef([[
typedef struct { int32_t left; int32_t right; } Demo_Pair;
typedef struct { int32_t left; int32_t right; } HostPair;
typedef HostPair Host_HostPair;
typedef struct { int32_t data[2]; } ml_array_2_i32;
typedef struct { int32_t* data; intptr_t len; } ml_slice_CBackendScalar_ScalarI32;
typedef struct { int32_t* data; intptr_t len; intptr_t stride; } ml_view_CBackendScalar_ScalarI32;
typedef struct { uint8_t* data; intptr_t len; } ml_bytespan;
typedef struct { void (*fn)(void); void* ctx; } ml_closure_codesig_i32_to_i32;
typedef void (*ml_cfuncptr_host_callback)(void);
typedef struct { int32_t lane[4]; } ml_vector_4_i32;
]])

local build, err, src = StencilBinary.compile(T, ordered, {
    stem = "test_copy_patch_mc_nonscalar",
    c_decls = c_decls,
    ffi_preamble = ffi_preamble,
})
assert(build ~= nil, tostring(err) .. "\n" .. tostring(src))
assert(artifacts.ptr_copy.symbol.text ~= artifacts.named_copy.symbol.text, "non-scalar artifact symbols must include structural type identity")

local function sym(artifact)
    return assert(build.symbols[artifact.symbol.text], artifact.symbol.text)
end

local values = ffi.new("int32_t[6]", { 10, 20, 30, 40, 50, 60 })
local xs = ffi.new("int32_t *[6]")
for i = 0, 5 do xs[i] = values + i end
local cxs = ffi.cast("int32_t * const *", xs)

local out = ffi.new("int32_t *[6]")
sym(artifacts.ptr_copy)(out, cxs, 0, 6)
for i = 0, 5 do assert(out[i] == xs[i] and out[i][0] == values[i], "pointer copy") end

local overlap = ffi.new("int32_t *[7]")
for i = 0, 6 do overlap[i] = values + math.min(i, 5) end
sym(artifacts.ptr_move)(overlap + 1, ffi.cast("int32_t * const *", overlap), 0, 6)
assert(overlap[0] == values and overlap[1] == values and overlap[2] == values + 1 and overlap[3] == values + 2, "pointer memmove")

local idx = ffi.new("int32_t[6]", { 2, 0, 5, 1, 4, 3 })
sym(artifacts.ptr_gather)(out, cxs, idx, 0, 6)
assert(out[0] == xs[2] and out[1] == xs[0] and out[2] == xs[5] and out[3] == xs[1] and out[4] == xs[4] and out[5] == xs[3], "pointer gather")

for i = 0, 5 do out[i] = nil end
sym(artifacts.ptr_scatter)(out, cxs, idx, 0, 6)
assert(out[0] == xs[1] and out[1] == xs[3] and out[2] == xs[0] and out[3] == xs[5] and out[4] == xs[4] and out[5] == xs[2], "pointer scatter")

sym(artifacts.ptr_identity)(out, cxs, 0, 6)
for i = 0, 5 do assert(out[i] == xs[i], "pointer identity map") end

do
    local src_pairs = ffi.new("Demo_Pair[3]", { { 1, 10 }, { 2, 20 }, { 3, 30 } })
    local out_pairs = ffi.new("Demo_Pair[3]")
    sym(artifacts.named_copy)(out_pairs, src_pairs, 0, 3)
    for i = 0, 2 do assert(out_pairs[i].left == src_pairs[i].left and out_pairs[i].right == src_pairs[i].right, "named struct copy") end
    local out_pairs2 = ffi.new("Demo_Pair[3]")
    sym(artifacts.named_identity)(out_pairs2, src_pairs, 0, 3)
    for i = 0, 2 do assert(out_pairs2[i].left == src_pairs[i].left and out_pairs2[i].right == src_pairs[i].right, "named struct identity") end
end

do
    local src_pairs = ffi.new("HostPair[2]", { { 7, 70 }, { 8, 80 } })
    local out_pairs = ffi.new("HostPair[2]")
    sym(artifacts.imported_copy)(out_pairs, src_pairs, 0, 2)
    assert(out_pairs[0].left == 7 and out_pairs[0].right == 70 and out_pairs[1].left == 8 and out_pairs[1].right == 80, "imported C struct copy")
end

do
    local src = ffi.new("ml_array_2_i32[3]")
    for i = 0, 2 do src[i].data[0], src[i].data[1] = i + 1, (i + 1) * 10 end
    local out_arr = ffi.new("ml_array_2_i32[3]")
    sym(artifacts.array_copy)(out_arr, src, 0, 3)
    for i = 0, 2 do assert(out_arr[i].data[0] == src[i].data[0] and out_arr[i].data[1] == src[i].data[1], "fixed-array copy") end
    local idx = ffi.new("int32_t[3]", { 2, 0, 1 })
    sym(artifacts.array_gather)(out_arr, src, idx, 0, 3)
    assert(out_arr[0].data[0] == 3 and out_arr[1].data[0] == 1 and out_arr[2].data[0] == 2, "fixed-array gather")
    for i = 0, 2 do out_arr[i].data[0], out_arr[i].data[1] = 0, 0 end
    sym(artifacts.array_scatter)(out_arr, src, idx, 0, 3)
    assert(out_arr[0].data[0] == 2 and out_arr[1].data[0] == 3 and out_arr[2].data[0] == 1, "fixed-array scatter")
    sym(artifacts.array_identity)(out_arr, src, 0, 3)
    assert(out_arr[0].data[1] == 10 and out_arr[2].data[1] == 30, "fixed-array identity")
end

do
    local data_a = ffi.new("int32_t[3]", { 1, 2, 3 })
    local data_b = ffi.new("int32_t[3]", { 4, 5, 6 })
    local slices = ffi.new("ml_slice_CBackendScalar_ScalarI32[2]")
    slices[0].data, slices[0].len = data_a, 3
    slices[1].data, slices[1].len = data_b, 3
    local out_slices = ffi.new("ml_slice_CBackendScalar_ScalarI32[2]")
    sym(artifacts.slice_copy)(out_slices, slices, 0, 2)
    assert(out_slices[0].data == data_a and out_slices[0].len == 3 and out_slices[1].data == data_b, "slice descriptor copy")
    local out_slices2 = ffi.new("ml_slice_CBackendScalar_ScalarI32[2]")
    sym(artifacts.slice_identity)(out_slices2, slices, 0, 2)
    assert(out_slices2[0].data == data_a and out_slices2[1].data == data_b, "slice descriptor identity")

    local views = ffi.new("ml_view_CBackendScalar_ScalarI32[1]")
    views[0].data, views[0].len, views[0].stride = data_a, 3, 1
    local out_views = ffi.new("ml_view_CBackendScalar_ScalarI32[1]")
    sym(artifacts.view_copy)(out_views, views, 0, 1)
    assert(out_views[0].data == data_a and out_views[0].len == 3 and out_views[0].stride == 1, "view descriptor copy")

    local bytes = ffi.new("uint8_t[4]", { 9, 8, 7, 6 })
    local spans = ffi.new("ml_bytespan[1]")
    spans[0].data, spans[0].len = bytes, 4
    local out_spans = ffi.new("ml_bytespan[1]")
    sym(artifacts.bytespan_copy)(out_spans, spans, 0, 1)
    assert(out_spans[0].data == bytes and out_spans[0].len == 4, "byte-span descriptor copy")
end

do
    local cb = ffi.cast("void (*)(void)", function() end)
    local closures = ffi.new("ml_closure_codesig_i32_to_i32[3]")
    for i = 0, 2 do closures[i].fn, closures[i].ctx = cb, ffi.cast("void *", ffi.cast("uintptr_t", i + 11)) end
    local out_closures = ffi.new("ml_closure_codesig_i32_to_i32[3]")
    sym(artifacts.closure_copy)(out_closures, closures, 0, 3)
    assert(out_closures[0].fn == cb and tonumber(ffi.cast("uintptr_t", out_closures[2].ctx)) == 13, "closure copy")
    local idx = ffi.new("int32_t[3]", { 1, 2, 0 })
    sym(artifacts.closure_gather)(out_closures, closures, idx, 0, 3)
    assert(tonumber(ffi.cast("uintptr_t", out_closures[0].ctx)) == 12 and tonumber(ffi.cast("uintptr_t", out_closures[2].ctx)) == 11, "closure gather")
    for i = 0, 2 do out_closures[i].fn, out_closures[i].ctx = nil, nil end
    sym(artifacts.closure_scatter)(out_closures, closures, idx, 0, 3)
    assert(tonumber(ffi.cast("uintptr_t", out_closures[0].ctx)) == 13 and tonumber(ffi.cast("uintptr_t", out_closures[1].ctx)) == 11, "closure scatter")
    sym(artifacts.closure_identity)(out_closures, closures, 0, 3)
    assert(tonumber(ffi.cast("uintptr_t", out_closures[1].ctx)) == 12, "closure identity")
end

do
    local cb1 = ffi.cast("ml_cfuncptr_host_callback", function() end)
    local cb2 = ffi.cast("ml_cfuncptr_host_callback", function() end)
    local cb3 = ffi.cast("ml_cfuncptr_host_callback", function() end)
    local funcs = ffi.new("ml_cfuncptr_host_callback[3]", { cb1, cb2, cb3 })
    local out_funcs = ffi.new("ml_cfuncptr_host_callback[3]")
    sym(artifacts.cfunc_copy)(out_funcs, funcs, 0, 3)
    assert(out_funcs[0] == cb1 and out_funcs[2] == cb3, "imported C function-pointer copy")
    local idx = ffi.new("int32_t[3]", { 2, 0, 1 })
    sym(artifacts.cfunc_gather)(out_funcs, funcs, idx, 0, 3)
    assert(out_funcs[0] == cb3 and out_funcs[1] == cb1 and out_funcs[2] == cb2, "imported C function-pointer gather")
    for i = 0, 2 do out_funcs[i] = nil end
    sym(artifacts.cfunc_scatter)(out_funcs, funcs, idx, 0, 3)
    assert(out_funcs[0] == cb2 and out_funcs[1] == cb3 and out_funcs[2] == cb1, "imported C function-pointer scatter")
    sym(artifacts.cfunc_identity)(out_funcs, funcs, 0, 3)
    assert(out_funcs[0] == cb1 and out_funcs[1] == cb2 and out_funcs[2] == cb3, "imported C function-pointer identity")
end

do
    local vecs = ffi.new("ml_vector_4_i32[3]")
    for i = 0, 2 do
        for lane = 0, 3 do vecs[i].lane[lane] = (i + 1) * 10 + lane end
    end
    local out_vecs = ffi.new("ml_vector_4_i32[3]")
    sym(artifacts.vector_copy)(out_vecs, vecs, 0, 3)
    assert(out_vecs[0].lane[0] == 10 and out_vecs[2].lane[3] == 33, "vector element copy")
    local idx = ffi.new("int32_t[3]", { 1, 2, 0 })
    sym(artifacts.vector_gather)(out_vecs, vecs, idx, 0, 3)
    assert(out_vecs[0].lane[0] == 20 and out_vecs[2].lane[0] == 10, "vector element gather")
    for i = 0, 2 do for lane = 0, 3 do out_vecs[i].lane[lane] = 0 end end
    sym(artifacts.vector_scatter)(out_vecs, vecs, idx, 0, 3)
    assert(out_vecs[0].lane[0] == 30 and out_vecs[1].lane[0] == 10 and out_vecs[2].lane[0] == 20, "vector element scatter")
    sym(artifacts.vector_identity)(out_vecs, vecs, 0, 3)
    assert(out_vecs[1].lane[2] == 22, "vector element identity")
end

io.write("lalin copy_patch_mc nonscalar ok\n")
