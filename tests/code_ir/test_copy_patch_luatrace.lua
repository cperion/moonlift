package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")

local T = pvm.context()
Schema(T)

local Core = T.LalinCore
local Code = T.LalinCode
local Value = T.LalinValue
local Schedule = T.LalinSchedule
local Stencil = T.LalinStencil
local StencilArtifactPlan = require("lalin.stencil_artifact_plan")(T)
local CopyPatchLuaTrace = require("lalin.copy_patch_luatrace")(T)

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local u8 = Code.CodeTyInt(8, Code.CodeUnsigned)
local f64 = Code.CodeTyFloat(64)
local bool8 = Code.CodeTyBool8
local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)

local function iconst(raw)
    return Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt(tostring(raw))))
end

local function u8const(raw)
    return Value.ValueExprConst(Code.CodeConstLiteral(u8, Core.LitInt(tostring(raw))))
end

local function fconst(raw)
    return Value.ValueExprConst(Code.CodeConstLiteral(f64, Core.LitFloat(tostring(raw))))
end

local function pred(cmp, ty, value)
    return Stencil.StencilPredCompareConst(cmp, ty, value)
end

local function reduction(kind, init)
    return {
        kind = kind,
        init = iconst(init),
        int_semantics = sem,
        float_mode = nil,
    }
end

local function view_topology(name, stride_const)
    return Stencil.StencilTopologyViewDescriptor(
        Code.CodeValueId("v:view:" .. name),
        Code.CodeValueId("v:data:" .. name),
        Code.CodeValueId("v:len:" .. name),
        Code.CodeValueId("v:stride:" .. name),
        stride_const
    )
end

local artifacts = {
    StencilArtifactPlan.reduce_array_artifact(reduction(Value.ReductionAdd, 0), nil, { elem_ty = i32, result_ty = i32, step_num = 1 }),
    StencilArtifactPlan.map_array_artifact(Stencil.StencilUnaryNeg, { elem_ty = i32, result_ty = i32, step_num = 1 }),
    StencilArtifactPlan.zip_map_array_artifact(Stencil.StencilBinaryAdd, { lhs_ty = i32, rhs_ty = i32, result_ty = i32, step_num = 1 }),
    StencilArtifactPlan.scan_array_artifact(reduction(Value.ReductionAdd, 0), nil, { elem_ty = i32, result_ty = i32, step_num = 1 }),
    StencilArtifactPlan.copy_array_artifact({ elem_ty = i32, step_num = 1 }),
    StencilArtifactPlan.copy_array_artifact({ elem_ty = i32, semantics = Stencil.StencilCopyMemMove, step_num = 1 }),
    StencilArtifactPlan.fill_array_artifact({ elem_ty = i32, value = iconst(7), step_num = 1 }),
    StencilArtifactPlan.find_array_artifact(pred(Core.CmpEq, i32, iconst(5)), { elem_ty = i32, step_num = 1 }),
    StencilArtifactPlan.partition_array_artifact(pred(Core.CmpGt, i32, iconst(0)), { elem_ty = i32, step_num = 1 }),
    StencilArtifactPlan.cast_array_artifact(Core.MachineCastSToF, { src_ty = i32, dst_ty = f64, step_num = 1 }),
    StencilArtifactPlan.compare_array_artifact(pred(Core.CmpGt, i32, iconst(0)), { elem_ty = i32, result_ty = bool8, step_num = 1 }),
    StencilArtifactPlan.zip_compare_array_artifact(Core.CmpLt, { lhs_ty = i32, rhs_ty = i32, result_ty = bool8, step_num = 1 }),
    StencilArtifactPlan.gather_array_artifact({ elem_ty = i32, index_ty = i32, step_num = 1 }),
    StencilArtifactPlan.scatter_array_artifact({ elem_ty = i32, index_ty = i32, conflicts = Stencil.StencilScatterUniqueIndices, step_num = 1 }),
    StencilArtifactPlan.in_place_map_array_artifact(Stencil.StencilUnaryNeg, { elem_ty = i32, step_num = 1 }),
    StencilArtifactPlan.count_array_artifact(pred(Core.CmpGt, i32, iconst(0)), { elem_ty = i32, step_num = 1 }),
    StencilArtifactPlan.map_reduce_array_artifact(Stencil.StencilUnaryNeg, reduction(Value.ReductionAdd, 0), nil, { elem_ty = i32, mapped_ty = i32, result_ty = i32, step_num = 1 }),
    StencilArtifactPlan.zip_reduce_array_artifact(Stencil.StencilBinaryAdd, reduction(Value.ReductionAdd, 0), nil, { lhs_ty = i32, rhs_ty = i32, mapped_ty = i32, result_ty = i32, step_num = 1 }),
    StencilArtifactPlan.select_array_artifact(Stencil.StencilPredNonZero, { cond_ty = bool8, elem_ty = i32, result_ty = i32, step_num = 1 }),
}

local realization = CopyPatchLuaTrace.realize_artifacts(artifacts)
assert(realization.kind == "BCStencilBankRealization", "expected BC copy-patch realization")
assert(#realization.installed == #artifacts, "all artifacts installed")
assert(pvm.classof(realization.installed[1].artifact.realized) == Stencil.StencilRealizedUnrolled, "BC autovector trace grouping should record unrolled realization")
assert(pvm.classof(realization.installed[1].artifact.schedule_rejects[1]) == Stencil.StencilScheduleRejectRequestedRealizedMismatch, "BC autovector trace grouping should record requested/realized mismatch")
assert(artifacts[1].fingerprint.text:match("^stencil%-artifact%-v1:"), "C artifact should carry a build fingerprint")
assert(realization.installed[1].artifact.fingerprint.text:match("^stencil%-artifact%-v1:"), "BC artifact should carry a build fingerprint")
assert(realization.installed[1].artifact.fingerprint.text ~= artifacts[1].fingerprint.text, "provider change must change artifact fingerprint")
assert(#realization.installed[1].artifact.diagnostics >= 1, "BC realized artifact should carry diagnostics")
assert(realization.installed[1].artifact.diagnostics[1].source == "realized-schedule", "BC diagnostic should record realized schedule source")

local reduce_template = CopyPatchLuaTrace.emit_mc_stencil_source(artifacts[1])
assert(reduce_template:match("local function ml_stencil_reduce_array_i32_add_to_i32_s1"), "expected reduce bytecode template")
local partition_template = CopyPatchLuaTrace.emit_mc_stencil_source(artifacts[9])
assert(partition_template:match("local function ml_stencil_partition_array_i32_gt_stable_s1"), "expected partition bytecode template")

local function access_ref(name)
    return Stencil.StencilAccessRef(name)
end

local function noalias_pair(left, right)
    return Stencil.StencilAccessAliasFact(access_ref(left), access_ref(right), Stencil.StencilAliasNoAlias)
end

local function noalias_obligation(pair)
    return Stencil.StencilProofObligation(
        Stencil.StencilProofNoAlias(pair.left, pair.right),
        Stencil.StencilProofAuthorAsserted,
        nil
    )
end

local function artifact_with_facts(artifact, rewrite_fact, alias_facts)
    local schedule = artifact.instance.schedule
    local facts = schedule.facts
    local access_facts = {}
    for i, fact in ipairs(facts.access_facts or {}) do
        access_facts[i] = rewrite_fact(fact)
    end
    local proof_obligations = facts.proof_obligations or {}
    if alias_facts ~= nil then
        proof_obligations = {}
        for _, pair in ipairs(alias_facts) do
            if pair.relation == Stencil.StencilAliasNoAlias then
                proof_obligations[#proof_obligations + 1] = noalias_obligation(pair)
            end
        end
    end
    local next_facts = Stencil.StencilVectorizationFacts(access_facts, alias_facts or facts.alias_facts or {}, facts.trip_count, facts.arithmetic, proof_obligations)
    local next_schedule
    local schedule_cls = pvm.classof(schedule)
    if schedule_cls == Stencil.StencilScheduleAutoVector then
        next_schedule = Stencil.StencilScheduleAutoVector(schedule.compiler, next_facts)
    elseif schedule_cls == Stencil.StencilScheduleUnrolled then
        next_schedule = Stencil.StencilScheduleUnrolled(schedule.factor, schedule.compiler, next_facts)
    elseif schedule_cls == Stencil.StencilScheduleVector then
        next_schedule = Stencil.StencilScheduleVector(
            schedule.feature,
            schedule.lane_policy,
            schedule.required_alignment,
            schedule.tail,
            schedule.reduction,
            schedule.vector_compiler,
            schedule.vector_unroll,
            schedule.interleave,
            schedule.compiler,
            next_facts
        )
    else
        error("expected vectorized schedule with facts")
    end
    local next_instance = Stencil.StencilInstance(
        artifact.instance.id,
        artifact.instance.descriptor,
        next_schedule,
        artifact.instance.abi,
        artifact.instance.proofs
    )
    return Stencil.StencilArtifact(next_instance, artifact.provider, artifact.symbol, artifact.c_signature, artifact.fingerprint, artifact.realized, artifact.diagnostics or {}, artifact.schedule_rejects or {})
end

local stale_bc_bank = assert(CopyPatchLuaTrace.build_bc_bank({ artifacts[1] }, { stem = "test_copy_patch_luatrace_stale" }))
local stale_bc_request = artifact_with_facts(artifacts[1], function(fact)
    return Stencil.StencilAccessVectorFact(fact.access, Stencil.StencilAlignmentKnown(64), fact.readonly, fact.unit_stride)
end)
local stale_bc_realization, stale_bc_err = CopyPatchLuaTrace.realize_bc_artifacts({ stale_bc_request }, { bank = stale_bc_bank })
assert(stale_bc_realization == nil, "stale BC bank entry must not realize")
assert(tostring(stale_bc_err):match("fingerprint mismatch"), "stale BC bank rejection should name fingerprint mismatch")

local first_plan = CopyPatchLuaTrace.plan_artifact(artifacts[1])
assert(first_plan.kind == "LuaTraceArtifactPlan", "expected inspectable LuaTrace artifact plan")
assert(first_plan.access_by_name.xs.kind == "contiguous", "expected contiguous access plan")
assert(first_plan.loop_plan.loop_shape == "grouped_while", "AutoVector reduce should use grouped loop plan")
assert(first_plan.kernel_plan.kind == "reduce_array", "expected reduce kernel plan")
assert(first_plan.kernel_plan.reduction_plan.kind == "ordered_single_accumulator", "LuaTrace reductions should expose ordered accumulator policy")
assert(first_plan.kernel_plan.reduction_plan.reassociation_required == false, "ordered LuaTrace reduction must not require reassociation")
assert(CopyPatchLuaTrace.plan_artifact(artifacts[5]).kernel_plan.primitive_plan.kind == "ffi_copy", "no-overlap copy should use ffi.copy primitive")
assert(CopyPatchLuaTrace.plan_artifact(artifacts[6]).kernel_plan.primitive_plan == nil, "memmove copy must not use ffi.copy primitive")
assert(CopyPatchLuaTrace.plan_artifact(artifacts[7]).kernel_plan.primitive_plan == nil, "i32 fill should stay loop-shaped")
local noalias_memmove = artifact_with_facts(artifacts[6], function(fact)
    return Stencil.StencilAccessVectorFact(fact.access, fact.alignment, fact.readonly, fact.unit_stride)
end, { noalias_pair("dst", "src") })
local noalias_memmove_primitive = CopyPatchLuaTrace.plan_artifact(noalias_memmove).kernel_plan.primitive_plan
assert(noalias_memmove_primitive.kind == "ffi_copy", "noalias facts should allow memmove-shaped copy to use ffi.copy")
assert(noalias_memmove_primitive.no_overlap_source == "noalias_facts", "copy primitive should record noalias legality source")
local readonly_dst_copy = artifact_with_facts(artifacts[5], function(fact)
    local readonly = fact.access.name == "dst" and true or fact.readonly
    return Stencil.StencilAccessVectorFact(fact.access, fact.alignment, readonly, fact.unit_stride)
end)
assert(CopyPatchLuaTrace.plan_artifact(readonly_dst_copy).kernel_plan.primitive_plan == nil, "readonly destination must block ffi.copy primitive")
assert(CopyPatchLuaTrace.plan_artifact(artifacts[11]).kernel_plan.predicate_plan.kind == "numeric_store", "compare should use measured inline numeric predicate policy")
assert(CopyPatchLuaTrace.plan_artifact(artifacts[12]).kernel_plan.predicate_plan.kind == "numeric_store", "zip compare should use measured inline numeric compare policy")
assert(CopyPatchLuaTrace.plan_artifact(artifacts[16]).kernel_plan.predicate_plan.kind == "multi_counter_branch", "count should use measured multi-counter branch policy")
assert(CopyPatchLuaTrace.plan_artifact(artifacts[16]).kernel_plan.predicate_plan.counters == 4, "count multi-counter policy should follow grouped loop width")
assert(CopyPatchLuaTrace.plan_artifact(artifacts[11]).kernel_plan.predicate_plan.rejected == "helper_branchless_measured_slower", "predicate plan should record rejected helper branchless candidate")
local unique_scatter_plan = CopyPatchLuaTrace.plan_artifact(artifacts[14])
assert(unique_scatter_plan.kernel_plan.scatter_plan.kind == "unique_indices", "unique scatter should expose conflict policy")
assert(unique_scatter_plan.loop_plan.group == 4, "unique scatter should be eligible for grouped LuaTrace lowering")

local last_write_scatter_artifact = StencilArtifactPlan.scatter_array_artifact({
    elem_ty = i32,
    index_ty = i32,
    conflicts = Stencil.StencilScatterLastWriteWins,
    step_num = 1,
})
local last_write_scatter_plan = CopyPatchLuaTrace.plan_artifact(last_write_scatter_artifact)
assert(last_write_scatter_plan.kernel_plan.scatter_plan.kind == "ordered_last_write", "last-write scatter should expose ordered conflict policy")
assert(last_write_scatter_plan.loop_plan.group == 1, "last-write scatter should remain scalar/conservative")

local u8_fill_artifact = StencilArtifactPlan.fill_array_artifact({ elem_ty = u8, value = u8const(127), step_num = 1 })
local u8_fill_plan = CopyPatchLuaTrace.plan_artifact(u8_fill_artifact)
assert(u8_fill_plan.kernel_plan.primitive_plan.kind == "ffi_fill", "u8 fill should use ffi.fill primitive")

local vector_artifact = StencilArtifactPlan.reduce_array_artifact(reduction(Value.ReductionAdd, 0), nil, {
    elem_ty = i32,
    result_ty = i32,
    step_num = 1,
    schedule = Schedule.ScheduleVector(Schedule.LaneVector(i32, 4), 2, 2, Schedule.TailScalar),
})
assert(pvm.classof(vector_artifact.instance.schedule) == Stencil.StencilScheduleVector, "expected vector stencil schedule")
assert(vector_artifact.instance.schedule.interleave == 2, "vector schedule should preserve interleave")
local vector_plan = CopyPatchLuaTrace.plan_artifact(vector_artifact)
assert(vector_plan.loop_plan.group == 16, "explicit vector plan should preserve lanes * unroll * interleave")
local vector_template = CopyPatchLuaTrace.emit_mc_stencil_source(vector_artifact)
assert(vector_template:match("luatrace schedule: vector_as_trace_group factor=16"), "LuaTrace should consume vector schedule as trace group")
assert(vector_template:match("while __ml_i < __ml_stop_group do"), "expected grouped LuaTrace loop")
assert(reduce_template:match("luatrace plan: autovector_trace_group"), "LuaTrace should consume AutoVector facts")

local vector_schedule = vector_artifact.instance.schedule
local vector_facts = vector_schedule.facts
local multiple_obligations = {}
for i, obligation in ipairs(vector_facts.proof_obligations or {}) do multiple_obligations[i] = obligation end
multiple_obligations[#multiple_obligations + 1] = Stencil.StencilProofObligation(
    Stencil.StencilProofTripCount(Stencil.StencilTripCountMultipleOf(16)),
    Stencil.StencilProofAuthorAsserted,
    nil
)
local multiple_facts = Stencil.StencilVectorizationFacts(
    vector_facts.access_facts,
    vector_facts.alias_facts,
    Stencil.StencilTripCountMultipleOf(16),
    vector_facts.arithmetic,
    multiple_obligations
)
local multiple_schedule = Stencil.StencilScheduleVector(
    vector_schedule.feature,
    vector_schedule.lane_policy,
    vector_schedule.required_alignment,
    vector_schedule.tail,
    vector_schedule.reduction,
    vector_schedule.vector_compiler,
    vector_schedule.vector_unroll,
    vector_schedule.interleave,
    vector_schedule.compiler,
    multiple_facts
)
local multiple_instance = Stencil.StencilInstance(
    vector_artifact.instance.id,
    vector_artifact.instance.descriptor,
    multiple_schedule,
    vector_artifact.instance.abi,
    vector_artifact.instance.proofs
)
local multiple_artifact = Stencil.StencilArtifact(
    multiple_instance,
    vector_artifact.provider,
    vector_artifact.symbol,
    vector_artifact.c_signature,
    vector_artifact.fingerprint,
    vector_artifact.realized,
    vector_artifact.diagnostics or {},
    vector_artifact.schedule_rejects or {}
)
local multiple_plan = CopyPatchLuaTrace.plan_artifact(multiple_artifact)
assert(multiple_plan.loop_plan.tail_strategy == "no_tail_trip_count_multiple", "trip-count multiple should remove generic tail")
local multiple_template = CopyPatchLuaTrace.emit_mc_stencil_source(multiple_artifact)
assert(multiple_template:match("tail=no_tail_trip_count_multiple"), "template should expose no-tail trip-count policy")
assert(not multiple_template:match("for i = __ml_i, stop %- 1, 1 do"), "no-tail trip-count policy must not emit generic tail loop")

local strict_f64_reduce_artifact = StencilArtifactPlan.reduce_array_artifact({
    kind = Value.ReductionAdd,
    init = fconst(0),
    int_semantics = nil,
    float_mode = Code.CodeFloatStrict,
}, nil, {
    elem_ty = f64,
    result_ty = f64,
    step_num = 1,
})
local strict_f64_reduce_plan = CopyPatchLuaTrace.plan_artifact(strict_f64_reduce_artifact).kernel_plan.reduction_plan
assert(strict_f64_reduce_plan.kind == "ordered_single_accumulator", "strict float should use ordered reduction policy")
assert(strict_f64_reduce_plan.reassociable == false, "strict float reduction must record non-reassociable arithmetic")
assert(strict_f64_reduce_plan.multi_accumulator == false, "strict float reduction must reject multi-accumulator lowering")
assert(strict_f64_reduce_plan.multi_accumulator_rejected == "reassociation_not_legal", "strict float rejection should be explicit")

local view_vector_artifact = StencilArtifactPlan.reduce_array_artifact(reduction(Value.ReductionAdd, 0), nil, {
    elem_ty = i32,
    result_ty = i32,
    step_num = 1,
    schedule = Schedule.ScheduleVector(Schedule.LaneVector(i32, 4), 2, 1, Schedule.TailScalar),
    array_topology = view_topology("strided_xs"),
})
local view_vector_plan = CopyPatchLuaTrace.plan_artifact(view_vector_artifact)
assert(view_vector_plan.access_by_name.xs.kind == "view_dynamic_stride", "expected dynamic view access plan")
assert(view_vector_plan.access_by_name.xs.dynamic_stride_arg == "xs_stride", "expected named dynamic stride arg")
local view_vector_template = CopyPatchLuaTrace.emit_mc_stencil_source(view_vector_artifact)
assert(view_vector_template:match("xs%[%(%(__ml_i %+ 1%) %* xs_stride%)%]"), "grouped dynamic view access must parenthesize the lane index")

local function exercise(symbols)
    local function sym(artifact)
        return assert(symbols[artifact.symbol.text], artifact.symbol.text)
    end

    local xs = ffi.new("int32_t[5]", { 1, -2, 5, 0, 3 })
    local ys = ffi.new("int32_t[5]", { 10, 20, 30, 40, 50 })
    local out = ffi.new("int32_t[5]")
    local mask = ffi.new("uint8_t[5]")
    local dout = ffi.new("double[5]")
    local idx = ffi.new("int32_t[5]", { 2, 0, 4, 1, 3 })

    assert(sym(artifacts[1])(xs, 0, 5, 0) == 7, "reduce add")

    sym(artifacts[2])(out, xs, 0, 5)
    assert(out[0] == -1 and out[1] == 2 and out[2] == -5 and out[3] == 0 and out[4] == -3, "map neg")

    sym(artifacts[3])(out, xs, ys, 0, 5)
    assert(out[0] == 11 and out[1] == 18 and out[2] == 35 and out[3] == 40 and out[4] == 53, "zip add")

    local final = sym(artifacts[4])(out, xs, 0, 5, 0)
    assert(final == 7, "scan final")
    assert(out[0] == 1 and out[1] == -1 and out[2] == 4 and out[3] == 4 and out[4] == 7, "scan prefix")

    sym(artifacts[5])(out, xs, 0, 5)
    assert(out[0] == 1 and out[1] == -2 and out[2] == 5 and out[3] == 0 and out[4] == 3, "copy")

    local overlap = ffi.new("int32_t[6]", { 1, 2, 3, 4, 5, 6 })
    sym(artifacts[6])(overlap + 1, overlap, 0, 5)
    assert(overlap[0] == 1 and overlap[1] == 1 and overlap[2] == 2 and overlap[3] == 3 and overlap[4] == 4 and overlap[5] == 5, "copy memmove")

    sym(artifacts[7])(out, 0, 5, 7)
    assert(out[0] == 7 and out[1] == 7 and out[2] == 7 and out[3] == 7 and out[4] == 7, "fill")

    assert(sym(artifacts[8])(xs, 0, 5) == 2, "find eq")

    local split = sym(artifacts[9])(out, xs, 0, 5)
    assert(split == 3, "partition split")
    assert(out[0] == 1 and out[1] == 5 and out[2] == 3 and out[3] == -2 and out[4] == 0, "partition order")

    sym(artifacts[10])(dout, xs, 0, 5)
    assert(dout[0] == 1 and dout[1] == -2 and dout[2] == 5 and dout[3] == 0 and dout[4] == 3, "cast")

    sym(artifacts[11])(mask, xs, 0, 5)
    assert(mask[0] == 1 and mask[1] == 0 and mask[2] == 1 and mask[3] == 0 and mask[4] == 1, "compare")

    sym(artifacts[12])(mask, xs, ys, 0, 5)
    assert(mask[0] == 1 and mask[1] == 1 and mask[2] == 1 and mask[3] == 1 and mask[4] == 1, "zip compare")

    sym(artifacts[13])(out, xs, idx, 0, 5)
    assert(out[0] == 5 and out[1] == 1 and out[2] == 3 and out[3] == -2 and out[4] == 0, "gather")

    for i = 0, 4 do out[i] = 0 end
    sym(artifacts[14])(out, xs, idx, 0, 5)
    assert(out[0] == -2 and out[1] == 0 and out[2] == 1 and out[3] == 3 and out[4] == 5, "scatter")

    sym(artifacts[15])(out, 0, 5)
    assert(out[0] == 2 and out[1] == 0 and out[2] == -1 and out[3] == -3 and out[4] == -5, "in-place map")

    assert(sym(artifacts[16])(xs, 0, 5) == 3, "count")
    assert(sym(artifacts[17])(xs, 0, 5, 0) == -7, "map reduce")
    assert(sym(artifacts[18])(xs, ys, 0, 5, 0) == 157, "zip reduce")
    local select_mask = ffi.new("uint8_t[5]", { 1, 0, 1, 0, 1 })
    sym(artifacts[19])(out, select_mask, xs, ys, 0, 5)
    assert(out[0] == 1 and out[1] == 20 and out[2] == 5 and out[3] == 40 and out[4] == 3, "select")
end

exercise(realization.symbols)

do
    local xs = ffi.new("int32_t[17]", { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 })
    local vf = CopyPatchLuaTrace.compile_artifact(vector_artifact)
    assert(vf(xs, 0, 17, 0) == 153, "vector-as-trace-group reduce")
end

do
    local xs = ffi.new("int32_t[34]")
    for i = 0, 16 do
        xs[i * 2] = i + 1
        xs[i * 2 + 1] = -1000
    end
    local vf = CopyPatchLuaTrace.compile_artifact(view_vector_artifact)
    assert(vf(xs, 0, 17, 0, 2) == 153, "grouped dynamic view reduce")
end

io.write("lalin copy_patch_luatrace ok\n")
