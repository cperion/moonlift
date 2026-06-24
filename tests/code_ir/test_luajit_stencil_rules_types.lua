package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")

local T = pvm.context()
Schema(T)

local Code = T.MoonCode
local Core = T.MoonCore
local Value = T.MoonValue
local Stencil = T.MoonStencil
local Rules = require("moonlift.luajit_stencil_rules")(T)

local function same_list(actual, expected)
    if #actual ~= #expected then return false end
    for i = 1, #expected do
        if actual[i] ~= expected[i] then return false end
    end
    return true
end

local function assert_constructor_contract(name, input, output)
    local contract = Rules.constructor_contract(name)
    assert(contract ~= nil, "missing constructor contract " .. name)
    assert(same_list(contract.input, input), "wrong input contract for " .. name)
    assert(same_list(contract.output, output), "wrong output contract for " .. name)
end

for _, name in ipairs({
    "store_fill",
    "store_copy",
    "store_gather",
    "store_scatter",
}) do
    assert_constructor_contract(name, { "info", "args" }, { "selection" })
end

for _, name in ipairs({
    "store_in_place_map",
    "store_map",
    "store_cast",
    "store_compare",
    "store_zip_map",
    "store_zip_compare",
    "reduce_map",
    "reduce_zip",
    "reduce_count",
}) do
    assert_constructor_contract(name, { "op", "info", "args" }, { "selection" })
end

assert_constructor_contract("reduce_array", { "info", "args" }, { "selection" })
assert_constructor_contract("scan_array", { "reduction", "info", "args" }, { "selection" })
assert_constructor_contract("find_array", { "op", "info", "args" }, { "selection" })
assert_constructor_contract("partition_array", { "op", "info", "args" }, { "selection" })
assert_constructor_contract("store_stencil_plan", { "selection" }, { "plan" })
assert_constructor_contract("reduce_stencil_plan", { "reduction", "selection" }, { "plan" })

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local fake_expr = { kind = "fake_expr" }
local fake_value = Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt("0")))

local scalar_types = {
    { ty = Code.CodeTyInt(8, Code.CodeSigned), kind = "int" },
    { ty = Code.CodeTyInt(8, Code.CodeUnsigned), kind = "int" },
    { ty = Code.CodeTyInt(16, Code.CodeSigned), kind = "int" },
    { ty = Code.CodeTyInt(16, Code.CodeUnsigned), kind = "int" },
    { ty = Code.CodeTyInt(32, Code.CodeSigned), kind = "int" },
    { ty = Code.CodeTyInt(32, Code.CodeUnsigned), kind = "int" },
    { ty = Code.CodeTyInt(64, Code.CodeSigned), kind = "int" },
    { ty = Code.CodeTyInt(64, Code.CodeUnsigned), kind = "int" },
    { ty = Code.CodeTyFloat(32), kind = "float" },
    { ty = Code.CodeTyFloat(64), kind = "float" },
    { ty = Code.CodeTyIndex, kind = "index" },
    { ty = Code.CodeTyBool8, kind = "bool8" },
}

for _, case in ipairs(scalar_types) do
    local class, err = Rules.classify_type(case.ty)
    assert(class ~= nil, "expected stencil type class: " .. tostring(err))
    assert(class.kind == case.kind, "wrong stencil type kind")
end

local ptr_i32 = Code.CodeTyDataPtr(i32)
local ptr_class = Rules.classify_type(ptr_i32)
assert(ptr_class == nil, "pointers are not stencil scalar element types")

local function clone(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

local scalar_tys = {}
for _, case in ipairs(scalar_types) do scalar_tys[#scalar_tys + 1] = case.ty end

local reductions = {
    Value.ReductionAdd,
    Value.ReductionMul,
    Value.ReductionAnd,
    Value.ReductionOr,
    Value.ReductionXor,
    Value.ReductionMin,
    Value.ReductionMax,
}

local function reduce_ctx(kind, ty)
    return {
        step_num = 1,
        result_ty = ty,
        init = fake_value,
        init_expr = fake_expr,
        start_expr = fake_expr,
        stop_expr = fake_expr,
        reduction_kind = kind,
        reduction_add = kind == Value.ReductionAdd,
        init_zero = true,
        result_i32 = ty == i32,
        class = {
            kind = "load",
            index_primary = true,
            src = "src",
            src_expr = fake_expr,
            elem_ty = ty,
        },
    }
end

local int_types = {
    Code.CodeTyInt(8, Code.CodeSigned),
    Code.CodeTyInt(8, Code.CodeUnsigned),
    Code.CodeTyInt(16, Code.CodeSigned),
    Code.CodeTyInt(16, Code.CodeUnsigned),
    Code.CodeTyInt(32, Code.CodeSigned),
    Code.CodeTyInt(32, Code.CodeUnsigned),
    Code.CodeTyInt(64, Code.CodeSigned),
    Code.CodeTyInt(64, Code.CodeUnsigned),
}

local float_types = { Code.CodeTyFloat(32), Code.CodeTyFloat(64) }

local supported = 0
for _, ty in ipairs(int_types) do
    for _, reduction in ipairs(reductions) do
        local selection, err = Rules.select_reduce(reduce_ctx(reduction, ty))
        assert(selection ~= nil, "expected integer reduction selection: " .. tostring(err))
        assert(selection.vocab == Stencil.StencilReduce, "expected reduce-array stencil")
        supported = supported + 1
    end
end

for _, ty in ipairs(float_types) do
    for _, reduction in ipairs({ Value.ReductionAdd, Value.ReductionMul, Value.ReductionMin, Value.ReductionMax }) do
        local selection, err = Rules.select_reduce(reduce_ctx(reduction, ty))
        assert(selection ~= nil, "expected float reduction selection: " .. tostring(err))
        assert(selection.vocab == Stencil.StencilReduce, "expected reduce-array stencil")
        supported = supported + 1
    end
    for _, reduction in ipairs({ Value.ReductionAnd, Value.ReductionOr, Value.ReductionXor }) do
        local selection = Rules.select_reduce(reduce_ctx(reduction, ty))
        assert(selection == nil, "float bitwise reduction must not be selected")
    end
end

assert(supported == 64, "expected 64 scalar reduction type cells")

local store_base_ctx = {
    step_num = 1,
    dst = "dst",
    dst_expr = fake_expr,
    start = "start",
    stop = "stop",
    start_expr = fake_expr,
    stop_expr = fake_expr,
    store_index_primary = true,
    scatter_conflicts = Stencil.StencilScatterUniqueIndices,
}

local store_shape_cells = 0
for _, ty in ipairs(scalar_tys) do
    local cases = {}

    local fill = clone(store_base_ctx)
    fill.dst_elem_ty = ty
    fill.class = { kind = "fill", value = fake_value, value_expr = fake_expr }
    cases[#cases + 1] = { ctx = fill, vocab = Stencil.StencilFill }

    local copy = clone(store_base_ctx)
    copy.dst_elem_ty = ty
    copy.class = { kind = "load", index_primary = true, src = "src", src_expr = fake_expr, elem_ty = ty }
    copy.copy_semantics = Stencil.StencilCopyMemMove
    cases[#cases + 1] = { ctx = copy, vocab = Stencil.StencilCopy }

    local gather = clone(store_base_ctx)
    gather.dst_elem_ty = ty
    gather.class = {
        kind = "load",
        index_primary = false,
        src = "src",
        src_expr = fake_expr,
        elem_ty = ty,
        index_stream = { base = "idx", base_expr = fake_expr, elem_ty = i32, index_primary = true },
    }
    cases[#cases + 1] = { ctx = gather, vocab = Stencil.StencilGather }

    local scatter = clone(store_base_ctx)
    scatter.dst_elem_ty = ty
    scatter.store_index_primary = false
    scatter.store_index_stream = { base = "idx", base_expr = fake_expr, elem_ty = i32, index_primary = true }
    scatter.class = { kind = "load", index_primary = true, src = "src", src_expr = fake_expr, elem_ty = ty }
    cases[#cases + 1] = { ctx = scatter, vocab = Stencil.StencilScatter }

    local in_place = clone(store_base_ctx)
    in_place.dst_elem_ty = ty
    in_place.class = {
        kind = "map",
        index_primary = true,
        src = "dst",
        src_expr = fake_expr,
        elem_ty = ty,
        result_ty = ty,
        same_src_dst_ty = true,
        op = Stencil.StencilUnaryIdentity,
    }
    cases[#cases + 1] = { ctx = in_place, vocab = Stencil.StencilInPlaceMap }

    local map = clone(store_base_ctx)
    map.dst_elem_ty = ty
    map.class = {
        kind = "map",
        index_primary = true,
        src = "src",
        src_expr = fake_expr,
        elem_ty = ty,
        result_ty = ty,
        op = Stencil.StencilUnaryIdentity,
    }
    cases[#cases + 1] = { ctx = map, vocab = Stencil.StencilMap }

    local cast = clone(store_base_ctx)
    cast.dst_elem_ty = ty
    cast.class = {
        kind = "cast",
        index_primary = true,
        src = "src",
        src_expr = fake_expr,
        src_ty = ty,
        result_ty = ty,
        op = Core.MachineCastIdentity,
    }
    cases[#cases + 1] = { ctx = cast, vocab = Stencil.StencilCast }

    local compare = clone(store_base_ctx)
    compare.dst_elem_ty = Code.CodeTyBool8
    compare.class = {
        kind = "compare",
        index_primary = true,
        src = "src",
        src_expr = fake_expr,
        elem_ty = ty,
        result_ty = Code.CodeTyBool8,
        pred = Stencil.StencilPredNonZero,
    }
    cases[#cases + 1] = { ctx = compare, vocab = Stencil.StencilCompare }

    local zip_map = clone(store_base_ctx)
    zip_map.dst_elem_ty = ty
    zip_map.class = {
        kind = "zip_map",
        lhs_index_primary = true,
        rhs_index_primary = true,
        lhs_base = "lhs",
        rhs_base = "rhs",
        lhs_expr = fake_expr,
        rhs_expr = fake_expr,
        lhs_ty = ty,
        rhs_ty = ty,
        result_ty = ty,
        op = Stencil.StencilBinaryAdd,
    }
    cases[#cases + 1] = { ctx = zip_map, vocab = Stencil.StencilZipMap }

    local zip_compare = clone(store_base_ctx)
    zip_compare.dst_elem_ty = Code.CodeTyBool8
    zip_compare.class = {
        kind = "zip_compare",
        lhs_index_primary = true,
        rhs_index_primary = true,
        lhs_base = "lhs",
        rhs_base = "rhs",
        lhs_expr = fake_expr,
        rhs_expr = fake_expr,
        lhs_ty = ty,
        rhs_ty = ty,
        cmp = Core.CmpEq,
    }
    cases[#cases + 1] = { ctx = zip_compare, vocab = Stencil.StencilZipCompare }

    for _, case in ipairs(cases) do
        local selection, err = Rules.select_store(case.ctx)
        assert(selection ~= nil, "expected store stencil selection: " .. tostring(err))
        assert(selection.vocab == case.vocab, "store selected wrong stencil vocab")
        store_shape_cells = store_shape_cells + 1
    end
end

assert(store_shape_cells == #scalar_tys * 10, "expected every store stencil shape across scalar types")

do
    local scan = clone(store_base_ctx)
    scan.dst_elem_ty = i32
    scan.result_ty = i32
    scan.reduction_kind = Value.ReductionAdd
    scan.reduction = { kind = Value.ReductionAdd, init = fake_value, int_semantics = nil, float_mode = nil }
    scan.init = fake_value
    scan.init_expr = fake_expr
    scan.mode = Stencil.StencilScanInclusive
    scan.class = { kind = "load", index_primary = true, src = "src", src_expr = fake_expr, elem_ty = i32 }
    local selection, err = Rules.select_scan(scan)
    assert(selection ~= nil, "expected scan stencil selection: " .. tostring(err))
    assert(selection.vocab == Stencil.StencilScan, "expected scan-array stencil")
end

do
    local find = clone(store_base_ctx)
    find.pred = Stencil.StencilPredNonZero
    find.not_found_minus_one = true
    find.class = { kind = "load", index_primary = true, src = "src", src_expr = fake_expr, elem_ty = i32 }
    local selection, err = Rules.select_find(find)
    assert(selection ~= nil, "expected find stencil selection: " .. tostring(err))
    assert(selection.vocab == Stencil.StencilFind, "expected find-array stencil")
end

do
    local partition = clone(store_base_ctx)
    partition.dst_elem_ty = i32
    partition.pred = Stencil.StencilPredNonZero
    partition.semantics = Stencil.StencilPartitionStable
    partition.class = { kind = "load", index_primary = true, src = "src", src_expr = fake_expr, elem_ty = i32 }
    local selection, err = Rules.select_partition(partition)
    assert(selection ~= nil, "expected partition stencil selection: " .. tostring(err))
    assert(selection.vocab == Stencil.StencilPartition, "expected partition-array stencil")
end

local pointer_copy = {}
for k, v in pairs(store_base_ctx) do pointer_copy[k] = v end
pointer_copy.dst_elem_ty = ptr_i32
pointer_copy.class = {
    kind = "load",
    index_primary = true,
    src = "src",
    src_expr = fake_expr,
    elem_ty = ptr_i32,
}
assert(Rules.select_store(pointer_copy) == nil, "pointer element copy must not select a stencil")

do
    local ready_store = {}
    for k, v in pairs(store_base_ctx) do ready_store[k] = v end
    ready_store.dst_elem_ty = i32
    ready_store.class = { kind = "load", index_primary = true, src = "src", src_expr = fake_expr, elem_ty = i32 }
    local plan, err = Rules.plan_store {
        planned = true,
        returns_void = true,
        counted_positive = true,
        single_store = true,
        dst_base_present = true,
        class_ready = true,
        selection_ctx = ready_store,
    }
    assert(plan ~= nil, "expected store stencil plan: " .. tostring(err))
    assert(plan.selection.vocab == Stencil.StencilCopy, "store plan should carry selected stencil")

    local rejected = Rules.plan_store {
        planned = true,
        returns_void = false,
        counted_positive = true,
        single_store = true,
        dst_base_present = true,
        class_ready = true,
        selection_ctx = ready_store,
    }
    assert(rejected == nil, "store plan must reject non-void loop exits")
end

local mismatch_zip = {}
for k, v in pairs(store_base_ctx) do mismatch_zip[k] = v end
mismatch_zip.dst_elem_ty = i32
mismatch_zip.class = {
    kind = "zip_map",
    lhs_index_primary = true,
    rhs_index_primary = true,
    lhs_base = "lhs",
    rhs_base = "rhs",
    lhs_expr = fake_expr,
    rhs_expr = fake_expr,
    lhs_ty = i32,
    rhs_ty = Code.CodeTyInt(32, Code.CodeUnsigned),
    result_ty = i32,
    op = Stencil.StencilBinaryAdd,
}
assert(Rules.select_store(mismatch_zip) == nil, "mismatched zip-map operand types must not select a stencil")

local higher_reduce_shape_cells = 0
for _, ty in ipairs(int_types) do
    for _, reduction in ipairs(reductions) do
        local map_ctx = reduce_ctx(reduction, ty)
        map_ctx.class = {
            kind = "map",
            index_primary = true,
            src = "src",
            src_expr = fake_expr,
            elem_ty = ty,
            result_ty = ty,
            op = Stencil.StencilUnaryIdentity,
        }
        local map_selection, map_err = Rules.select_reduce(map_ctx)
        assert(map_selection ~= nil, "expected integer map-reduce selection: " .. tostring(map_err))
        assert(map_selection.vocab == Stencil.StencilMapReduce, "expected map-reduce stencil")
        higher_reduce_shape_cells = higher_reduce_shape_cells + 1

        local zip_ctx = reduce_ctx(reduction, ty)
        zip_ctx.class = {
            kind = "zip_map",
            lhs_index_primary = true,
            rhs_index_primary = true,
            lhs_base = "lhs",
            rhs_base = "rhs",
            lhs_expr = fake_expr,
            rhs_expr = fake_expr,
            lhs_ty = ty,
            rhs_ty = ty,
            result_ty = ty,
            op = Stencil.StencilBinaryAdd,
        }
        local zip_selection, zip_err = Rules.select_reduce(zip_ctx)
        assert(zip_selection ~= nil, "expected integer zip-reduce selection: " .. tostring(zip_err))
        assert(zip_selection.vocab == Stencil.StencilZipReduce, "expected zip-reduce stencil")
        higher_reduce_shape_cells = higher_reduce_shape_cells + 1
    end
end

for _, ty in ipairs(float_types) do
    for _, reduction in ipairs({ Value.ReductionAdd, Value.ReductionMul, Value.ReductionMin, Value.ReductionMax }) do
        local map_ctx = reduce_ctx(reduction, ty)
        map_ctx.class = {
            kind = "map",
            index_primary = true,
            src = "src",
            src_expr = fake_expr,
            elem_ty = ty,
            result_ty = ty,
            op = Stencil.StencilUnaryIdentity,
        }
        local map_selection, map_err = Rules.select_reduce(map_ctx)
        assert(map_selection ~= nil, "expected float map-reduce selection: " .. tostring(map_err))
        assert(map_selection.vocab == Stencil.StencilMapReduce, "expected map-reduce stencil")
        higher_reduce_shape_cells = higher_reduce_shape_cells + 1

        local zip_ctx = reduce_ctx(reduction, ty)
        zip_ctx.class = {
            kind = "zip_map",
            lhs_index_primary = true,
            rhs_index_primary = true,
            lhs_base = "lhs",
            rhs_base = "rhs",
            lhs_expr = fake_expr,
            rhs_expr = fake_expr,
            lhs_ty = ty,
            rhs_ty = ty,
            result_ty = ty,
            op = Stencil.StencilBinaryAdd,
        }
        local zip_selection, zip_err = Rules.select_reduce(zip_ctx)
        assert(zip_selection ~= nil, "expected float zip-reduce selection: " .. tostring(zip_err))
        assert(zip_selection.vocab == Stencil.StencilZipReduce, "expected zip-reduce stencil")
        higher_reduce_shape_cells = higher_reduce_shape_cells + 1
    end
end

assert(higher_reduce_shape_cells == 128, "expected map-reduce and zip-reduce coverage for all scalar reduction cells")

for _, ty in ipairs(scalar_tys) do
    local count_ctx = reduce_ctx(Value.ReductionAdd, i32)
    count_ctx.class = {
        kind = "compare",
        index_primary = true,
        src = "src",
        src_expr = fake_expr,
        elem_ty = ty,
        result_ty = Code.CodeTyBool8,
        pred = Stencil.StencilPredNonZero,
    }
    local selection, err = Rules.select_reduce(count_ctx)
    assert(selection ~= nil, "expected count selection: " .. tostring(err))
    assert(selection.vocab == Stencil.StencilCount, "expected count stencil")
end

do
    local ready_reduce = reduce_ctx(Value.ReductionAdd, i32)
    local plan, err = Rules.plan_reduce {
        planned = true,
        result_reduction = true,
        returns_reduction = true,
        counted_positive = true,
        class_ready = true,
        reduction = "reduction",
        selection_ctx = ready_reduce,
    }
    assert(plan ~= nil, "expected reduction stencil plan: " .. tostring(err))
    assert(plan.reduction == "reduction", "reduce plan should preserve reduction payload")
    assert(plan.selection.vocab == Stencil.StencilReduce, "reduce plan should carry selected stencil")

    local rejected = Rules.plan_reduce {
        planned = true,
        result_reduction = true,
        returns_reduction = true,
        counted_positive = false,
        class_ready = true,
        reduction = "reduction",
        selection_ctx = ready_reduce,
    }
    assert(rejected == nil, "reduce plan must reject non-positive counted loops")
end

io.write("moonlift luajit_stencil_rules_types ok\n")
