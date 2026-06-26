package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")

local T = pvm.context()
Schema(T)

local Core = T.LalinCore
local Code = T.LalinCode
local Value = T.LalinValue
local Stencil = T.LalinStencil
local Matrix = require("lalin.stencil_support_matrix")(T)
local Plan = require("lalin.stencil_artifact_plan")(T)
local Rules = require("lalin.stencil_rules")(T)

local function read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local function sum_body(src, sum_name)
    local start_pat = "sum%.%s+" .. sum_name .. "%s*{"
    local s, e = src:find(start_pat)
    assert(s ~= nil, "missing sum " .. sum_name)
    local depth = 1
    local i = e + 1
    while i <= #src do
        local c = src:sub(i, i)
        if c == "{" then depth = depth + 1
        elseif c == "}" then
            depth = depth - 1
            if depth == 0 then return src:sub(e + 1, i - 1) end
        end
        i = i + 1
    end
    error("unterminated sum " .. sum_name)
end

local function variants(path, sum_name)
    local body = sum_body(read(path), sum_name)
    local out, seen = {}, {}
    for name in body:gmatch("([A-Z][A-Za-z0-9_]*)%s*[{,]") do
        if not seen[name] then
            seen[name] = true
            out[#out + 1] = name
        end
    end
    table.sort(out)
    return out
end

local function assert_matrix_covers(table_name, names)
    for _, name in ipairs(names) do
        local entry = Matrix.entry(table_name, name)
        assert(entry ~= nil, table_name .. " missing matrix row for " .. name)
        assert(Matrix.status[entry.status] ~= nil, table_name .. "." .. name .. " has invalid status " .. tostring(entry.status))
        assert(type(entry.scope) == "string" and entry.scope ~= "", table_name .. "." .. name .. " needs a scope/reason")
    end
end

local stencil_schema = "lua/lalin/schema/stencil.lua"
local code_schema = "lua/lalin/schema/code.lua"

assert_matrix_covers("vocabs", variants(stencil_schema, "StencilVocab"))
assert_matrix_covers("layouts", variants(stencil_schema, "StencilAccessLayout"))
assert_matrix_covers("producers", variants(stencil_schema, "StencilProducerShape"))
assert_matrix_covers("predicates", variants(stencil_schema, "StencilPredicate"))
assert_matrix_covers("type_families", variants(code_schema, "CodeType"))

assert(Matrix.materializers.copy_patch_bc.policy == Matrix.coverage_policy.semantic_probe, "copy_patch_bc must be the semantic coverage probe")
assert(Matrix.materializers.copy_patch_mc.policy == Matrix.coverage_policy.fast_subset, "copy_patch_mc must be the fast subset")
assert(Matrix.materializers.copy_patch_mc.fallback == "copy_patch_bc", "copy_patch_mc must name copy_patch_bc as semantic fallback")
assert(Matrix.materializers.emitted_bank.policy == Matrix.coverage_policy.deployment_bank, "emitted bank must be the deployment coverage probe")

local known_bc_producer_gaps = {
    StencilProduceRangeND = true,
    StencilProduceWindowND = true,
    StencilProduceTiledND = true,
}
local saw_bc_gap = false
for producer_name, entry in pairs(Matrix.producers) do
    assert(Matrix.materializer_status[entry.copy_patch_bc] ~= nil, "producer " .. producer_name .. " has invalid copy_patch_bc status " .. tostring(entry.copy_patch_bc))
    assert(Matrix.materializer_status[entry.copy_patch_mc] ~= nil, "producer " .. producer_name .. " has invalid copy_patch_mc status " .. tostring(entry.copy_patch_mc))
    assert(Matrix.materializer_status[entry.bank] ~= nil, "producer " .. producer_name .. " has invalid emitted-bank status " .. tostring(entry.bank))
    assert(Matrix.producer_materializer_status(producer_name, "copy_patch_bc") == entry.copy_patch_bc, "producer BC status query mismatch for " .. producer_name)
    assert(Matrix.producer_materializer_status(producer_name, "copy_patch_mc") == entry.copy_patch_mc, "producer MC status query mismatch for " .. producer_name)
    assert(Matrix.producer_materializer_status(producer_name, "emitted_bank") == entry.bank, "producer bank status query mismatch for " .. producer_name)
    local bc_gap = Matrix.copy_patch_bc_semantic_gap(producer_name)
    if bc_gap ~= nil then
        saw_bc_gap = true
        assert(known_bc_producer_gaps[producer_name], "unexpected copy_patch_bc semantic producer gap: " .. producer_name .. ": " .. bc_gap)
        assert(type(entry.copy_patch_bc_gap) == "string" and entry.copy_patch_bc_gap ~= "", "known BC producer gap needs explicit reason: " .. producer_name)
    end
end
assert(saw_bc_gap, "matrix should expose current BC semantic producer gaps until they are closed")

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local f64 = Code.CodeTyFloat(64)
local bool8 = Code.CodeTyBool8
local ptr_i32 = Code.CodeTyDataPtr(i32)
local vec_i32 = Code.CodeTyVector(i32, 4)
local int_semantics = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)

local function iconst(raw)
    return Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt(tostring(raw))))
end

local function pred(cmp, ty, value)
    return Stencil.StencilPredCompareConst(cmp, ty, value)
end

local function reduction(kind, init)
    return {
        kind = kind,
        init = iconst(init),
        int_semantics = int_semantics,
        float_mode = nil,
    }
end

local artifact_samples = {
    reduce = function()
        return Plan.reduce_array_artifact(reduction(Value.ReductionAdd, 0), nil, { elem_ty = i32, result_ty = i32, step_num = 1 })
    end,
    map = function()
        return Plan.map_array_artifact(Stencil.StencilUnaryNeg, { elem_ty = i32, result_ty = i32, step_num = 1 })
    end,
    zip_map = function()
        return Plan.zip_map_array_artifact(Stencil.StencilBinaryAdd, { lhs_ty = i32, rhs_ty = i32, result_ty = i32, step_num = 1 })
    end,
    scan = function()
        return Plan.scan_array_artifact(reduction(Value.ReductionAdd, 0), nil, { elem_ty = i32, result_ty = i32, step_num = 1 })
    end,
    copy = function()
        return Plan.copy_array_artifact({ elem_ty = i32, step_num = 1 })
    end,
    copy_memmove = function()
        return Plan.copy_array_artifact({ elem_ty = i32, semantics = Stencil.StencilCopyMemMove, step_num = 1 })
    end,
    fill = function()
        return Plan.fill_array_artifact({ elem_ty = i32, value = iconst(7), step_num = 1 })
    end,
    find = function()
        return Plan.find_array_artifact(pred(Core.CmpEq, i32, iconst(5)), { elem_ty = i32, step_num = 1 })
    end,
    partition = function()
        return Plan.partition_array_artifact(pred(Core.CmpGt, i32, iconst(0)), { elem_ty = i32, step_num = 1 })
    end,
    cast = function()
        return Plan.cast_array_artifact(Core.MachineCastSToF, { src_ty = i32, dst_ty = f64, step_num = 1 })
    end,
    compare = function()
        return Plan.compare_array_artifact(pred(Core.CmpGt, i32, iconst(0)), { elem_ty = i32, result_ty = bool8, step_num = 1 })
    end,
    zip_compare = function()
        return Plan.zip_compare_array_artifact(Core.CmpLt, { lhs_ty = i32, rhs_ty = i32, result_ty = bool8, step_num = 1 })
    end,
    select = function()
        return Plan.select_array_artifact(Stencil.StencilPredNonZero, { cond_ty = bool8, elem_ty = i32, result_ty = i32, step_num = 1 })
    end,
    apply_n = function()
        return Plan.apply_n_artifact({
            tag = "matrix",
            result_ty = i32,
            inputs = { { name = "x1", ty = i32 }, { name = "x2", ty = i32 }, { name = "x3", ty = i32 } },
            expr = Plan.apply_select_expr(Stencil.StencilPredNonZero, Plan.input_expr("x1"), Plan.input_expr("x2"), Plan.input_expr("x3"), i32),
            step_num = 1,
        })
    end,
    gather = function()
        return Plan.gather_array_artifact({ elem_ty = i32, index_ty = i32, step_num = 1 })
    end,
    scatter = function()
        return Plan.scatter_array_artifact({ elem_ty = i32, index_ty = i32, conflicts = Stencil.StencilScatterUniqueIndices, step_num = 1 })
    end,
    scatter_reduce = function()
        return Plan.scatter_reduce_n_artifact(reduction(Value.ReductionAdd, 0), nil, {
            tag = "matrix",
            result_ty = i32,
            item_ty = i32,
            index_ty = i32,
            inputs = { { name = "xs", ty = i32 } },
            expr = Plan.input_expr("xs"),
            step_num = 1,
        })
    end,
    in_place_map = function()
        return Plan.in_place_map_array_artifact(Stencil.StencilUnaryNeg, { elem_ty = i32, step_num = 1 })
    end,
    count = function()
        return Plan.count_array_artifact(pred(Core.CmpGt, i32, iconst(0)), { elem_ty = i32, step_num = 1 })
    end,
    reduce_n = function()
        return Plan.reduce_n_artifact(reduction(Value.ReductionAdd, 0), nil, {
            tag = "matrix",
            inputs = { { name = "lhs", ty = i32 }, { name = "rhs", ty = i32 } },
            expr = Plan.apply_binary_expr(Stencil.StencilBinaryAdd, Plan.input_expr("lhs"), Plan.input_expr("rhs"), i32, { int_semantics = int_semantics }),
            item_ty = i32,
            result_ty = i32,
            step_num = 1,
        })
    end,
    scan_n = function()
        return Plan.scan_n_artifact(reduction(Value.ReductionAdd, 0), nil, {
            tag = "matrix",
            inputs = { { name = "lhs", ty = i32 }, { name = "rhs", ty = i32 } },
            expr = Plan.apply_binary_expr(Stencil.StencilBinaryAdd, Plan.input_expr("lhs"), Plan.input_expr("rhs"), i32, { int_semantics = int_semantics }),
            item_ty = i32,
            result_ty = i32,
            step_num = 1,
        })
    end,
}

assert(Matrix.type_family_for(i32) == "CodeTyInt")
assert(Matrix.type_family_for(Code.CodeTyBool8) == "CodeTyBool8")
assert(Matrix.type_family_for(ptr_i32) == "CodeTyDataPtr")
assert(Matrix.type_family_for(vec_i32) == "CodeTyVector")

assert(Matrix.type_families.CodeTyInt.status == "supported")
assert(Matrix.type_families.CodeTyDataPtr.status == "supported")
assert(Matrix.type_families.CodeTyVector.status == "supported")

assert(Rules.classify_type(i32) ~= nil, "matrix says CodeTyInt is supported; rules must classify it")
assert(Rules.classify_type(ptr_i32) ~= nil, "matrix says CodeTyDataPtr is supported; rules must classify it")
assert(Rules.classify_type(vec_i32) ~= nil, "matrix says CodeTyVector is supported; rules must classify it")

for vocab, entry in pairs(Matrix.vocabs) do
    if entry.status == Matrix.status.supported then
        assert(Stencil[vocab] ~= nil, "supported basis vocab " .. vocab .. " must be exported by schema")
    end
end

for name, entry in pairs(Matrix.derived_plans) do
    if entry.status == Matrix.status.supported then
        local ctor = Matrix.artifact_constructors[name]
        assert(ctor ~= nil, "supported derived plan " .. name .. " needs an artifact constructor mapping")
        assert(type(Plan[ctor]) == "function", "artifact constructor " .. ctor .. " for " .. name .. " is not exported by stencil_artifact_plan")
        local sample = artifact_samples[name]
        assert(sample ~= nil, "supported derived plan " .. name .. " needs an artifact sample")
        local artifact = sample()
        assert(Plan.descriptor_vocab(artifact.instance.descriptor) == Stencil[entry.basis], "artifact sample for " .. name .. " emitted the wrong basis descriptor vocab")
    end
end

local gather = artifact_samples.gather()
assert(Plan.access_named(gather.instance.descriptor, "idx").role == Stencil.StencilAccessIndex, "gather index stream must use index access role")
local scatter = artifact_samples.scatter()
assert(Plan.access_named(scatter.instance.descriptor, "idx").role == Stencil.StencilAccessIndex, "scatter index stream must use index access role")
local scatter_reduce = artifact_samples.scatter_reduce()
assert(Plan.access_named(scatter_reduce.instance.descriptor, "idx").role == Stencil.StencilAccessIndex, "scatter-reduce index stream must use index access role")
assert(Plan.access_named(scatter_reduce.instance.descriptor, "dst").role == Stencil.StencilAccessReadWrite, "scatter-reduce destination must be readwrite")
local atomic_scatter_reduce_ok, atomic_scatter_reduce_err = pcall(function()
    return Plan.scatter_reduce_n_artifact(reduction(Value.ReductionAdd, 0), nil, {
        tag = "matrix_atomic",
        result_ty = i32,
        item_ty = i32,
        index_ty = i32,
        inputs = { { name = "xs", ty = i32 } },
        expr = Plan.input_expr("xs"),
        conflicts = Stencil.StencilScatterReduceAtomic(Core.AtomicSeqCst),
        step_num = 1,
    })
end)
assert(not atomic_scatter_reduce_ok and tostring(atomic_scatter_reduce_err):match("atomic scatter%-reduce"), "atomic scatter-reduce must be represented but rejected until materialized")

io.write("lalin stencil_support_matrix ok\n")
