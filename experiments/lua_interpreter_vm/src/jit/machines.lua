-- Moonlift Lua VM JIT — first product-level machines.
--
-- These are real compiled Moonlift routines that construct and inspect JIT
-- products.  They are deliberately structural: no Lua planning script, no fake
-- native execution, no bytecode mutation.

local moon = require("moonlift")
local C = require("experiments.lua_interpreter_vm.src.jit.constants")
require("experiments.lua_interpreter_vm.src.jit.products")

local V = {}
for k, v in pairs(C.TraceStatus) do V["TRACE_STATUS_" .. k] = moon.int(v) end
for k, v in pairs(C.TraceSelectStatus) do V["TRACE_SELECT_" .. k] = moon.int(v) end
for k, v in pairs(C.ReplacementKind) do V["REPL_" .. k] = moon.int(v) end

local function extend_values(extra)
    local out = {}
    for k, v in pairs(V) do out[k] = v end
    for k, v in pairs(extra or {}) do out[k] = v end
    return out
end

local jit_init_virtual_state = moon.func [[
jit_init_virtual_state(out: ptr(VirtualState), addr: SemanticAddr,
                       frame: u32, base: index, top: index,
                       slot_values: ptr(u32), slot_count: index,
                       values: ptr(TypedValue), value_count: index,
                       facts: ptr(Fact), fact_count: index,
                       deps: ptr(DependencyKey), dep_count: index) -> bool
    if out == nil then return false end
    out.addr.proto = addr.proto
    out.addr.pc = addr.pc
    out.addr.frame = addr.frame
    out.frame = frame
    out.base = base
    out.top = top
    out.slot_values = slot_values
    out.slot_count = slot_count
    out.values = values
    out.value_count = value_count
    out.facts = facts
    out.fact_count = fact_count
    out.deps = deps
    out.dep_count = dep_count
    return true
end
]]

local jit_build_projection_header = moon.func [[
jit_build_projection_header(out: ptr(Projection), id: u32, kind: u8,
                            addr: SemanticAddr, frame: u32,
                            base: index, top: index, flags: u64) -> bool
    if out == nil then return false end
    out.id = id
    out.kind = kind
    out.addr.proto = addr.proto
    out.addr.pc = addr.pc
    out.addr.frame = addr.frame
    out.frame = frame
    out.base = base
    out.top = top
    out.slots = nil
    out.slot_count = 0
    out.roots = nil
    out.root_count = 0
    out.flags = flags
    return true
end
]]

local jit_clear_stencil_plan = moon.func [[
jit_clear_stencil_plan(plan: ptr(StencilPlan)) -> bool
    if plan == nil then return false end
    plan.nodes = nil
    plan.node_count = 0
    plan.fixups = nil
    plan.fixup_count = 0
    plan.projections = nil
    plan.projection_count = 0
    plan.estimated_size = 0
    return true
end
]]

local jit_trace_anchor_tick = moon.func(V) [[
jit_trace_anchor_tick(anchor: ptr(TraceAnchor), hot_threshold: u32) -> bool
    if anchor == nil then return false end
    if anchor.status == as(u8, @{TRACE_STATUS_BLACKLISTED}) then return false end
    anchor.counter = anchor.counter + 1
    if anchor.counter >= hot_threshold then
        anchor.status = as(u8, @{TRACE_STATUS_RECORDING})
        return true
    end
    return false
end
]]

local jit_init_trace_record = moon.func [[
jit_init_trace_record(out: ptr(TraceRecord), anchor: TraceAnchor,
                      ops: ptr(StateOp), op_count: index,
                      guards: ptr(Guard), guard_count: index,
                      snapshots: ptr(Projection), snapshot_count: index,
                      deps: ptr(DependencyKey), dep_count: index,
                      flags: u32) -> bool
    if out == nil then return false end
    out.anchor.addr.proto = anchor.addr.proto
    out.anchor.addr.pc = anchor.addr.pc
    out.anchor.addr.frame = anchor.addr.frame
    out.anchor.kind = anchor.kind
    out.anchor.status = anchor.status
    out.anchor.counter = anchor.counter
    out.anchor.blacklist = anchor.blacklist
    out.anchor.generation = anchor.generation
    out.ops = ops
    out.op_count = op_count
    out.guards = guards
    out.guard_count = guard_count
    out.snapshots = snapshots
    out.snapshot_count = snapshot_count
    out.deps = deps
    out.dep_count = dep_count
    out.flags = flags
    return true
end
]]

local jit_trace_record_has_path = moon.func [[
jit_trace_record_has_path(record: ptr(TraceRecord)) -> bool
    if record == nil then return false end
    return record.op_count > 0
end
]]

local jit_trace_record_is_guarded = moon.func [[
jit_trace_record_is_guarded(record: ptr(TraceRecord)) -> bool
    if record == nil then return false end
    return record.guard_count > 0 and record.snapshot_count > 0
end
]]

local jit_trace_pattern_matches = moon.func [[
jit_trace_pattern_matches(record: ptr(TraceRecord), pattern: ptr(StencilPattern), start: index) -> bool
    if record == nil or pattern == nil then return false end
    if record.ops == nil or pattern.ops == nil or pattern.stencil == nil then return false end
    if pattern.op_count == 0 then return false end
    if start > record.op_count then return false end
    if pattern.op_count > record.op_count - start then return false end

    return region -> bool
    entry start_block()
        jump loop(i = as(index, 0), effect_flags = as(u64, 0))
    end
    block loop(i: index, effect_flags: u64)
        if i >= pattern.op_count then
            if (effect_flags & pattern.required_effects) ~= pattern.required_effects then yield false end
            yield true
        end
        let op: ptr(StateOp) = record.ops + (start + i)
        let wanted: u16 = pattern.ops[i]
        if op.op ~= wanted then yield false end
        if (op.effect.flags & pattern.forbidden_effects) ~= 0 then yield false end
        jump loop(i = i + 1, effect_flags = effect_flags | op.effect.flags)
    end
    end
end
]]

local jit_trace_match_at = moon.func { matches = jit_trace_pattern_matches } [[
jit_trace_match_at(record: ptr(TraceRecord), lib: ptr(StencilPatternLibrary), start: index,
                   out: ptr(TraceStencilMatch)) -> bool
    if out == nil then return false end
    if record == nil or lib == nil or lib.patterns == nil then return false end

    return region -> bool
    entry start_block()
        jump scan(i = as(index, 0), found = false,
                  best_index = as(index, 0), best_len = as(index, 0), best_score = as(u32, 0))
    end
    block scan(i: index, found: bool, best_index: index, best_len: index, best_score: u32)
        if i >= lib.pattern_count then
            if not found then yield false end
            let best: ptr(StencilPattern) = lib.patterns + best_index
            out.start = start
            out.covered_ops = best.op_count
            out.stencil = best.stencil
            out.config.kind = as(u16, best.flags & 65535)
            out.config.op = best.stencil.op
            out.config.value_type = 0
            out.config.lhs_loc = 0
            out.config.rhs_loc = 0
            out.config.out_loc = 0
            out.config.passthrough_mask = 0
            out.config.pattern_id = best.id
            out.score = best.score
            out.flags = best.flags
            yield true
        end
        let pattern: ptr(StencilPattern) = lib.patterns + i
        if @{matches}(record, pattern, start) then
            let better_len: bool = pattern.op_count > best_len
            let better_score: bool = pattern.op_count == best_len and pattern.score > best_score
            if (not found) or better_len or better_score then
                jump scan(i = i + 1, found = true,
                          best_index = i, best_len = pattern.op_count, best_score = pattern.score)
            end
        end
        jump scan(i = i + 1, found = found,
                  best_index = best_index, best_len = best_len, best_score = best_score)
    end
    end
end
]]

local jit_trace_select_pattern_plan = moon.func(extend_values { match_at = jit_trace_match_at, matches = jit_trace_pattern_matches }) [[
jit_trace_select_pattern_plan(record: ptr(TraceRecord), lib: ptr(StencilPatternLibrary),
                              nodes_out: ptr(StencilNode), node_capacity: index,
                              scratch: ptr(TraceStencilMatch), plan: ptr(StencilPlan)) -> u32
    if record == nil or lib == nil or nodes_out == nil or scratch == nil or plan == nil then
        return as(u32, @{TRACE_SELECT_INVALID})
    end
    plan.nodes = nodes_out
    plan.node_count = 0
    plan.fixups = nil
    plan.fixup_count = 0
    plan.projections = record.snapshots
    plan.projection_count = record.snapshot_count
    plan.estimated_size = 0
    if record.op_count == 0 then return as(u32, @{TRACE_SELECT_EMPTY}) end

    return region -> u32
    entry start_block()
        jump loop(i = as(index, 0), out_count = as(index, 0), estimated = as(index, 0))
    end
    block loop(i: index, out_count: index, estimated: index)
        if i >= record.op_count then
            plan.node_count = out_count
            plan.estimated_size = estimated
            yield as(u32, @{TRACE_SELECT_OK})
        end
        if out_count >= node_capacity then yield as(u32, @{TRACE_SELECT_INVALID}) end
        if not @{match_at}(record, lib, i, scratch) then yield as(u32, @{TRACE_SELECT_NO_STENCIL}) end
        let node: ptr(StencilNode) = nodes_out + out_count
        node.stencil = scratch.stencil
        node.config.kind = scratch.config.kind
        node.config.op = scratch.config.op
        node.config.value_type = scratch.config.value_type
        node.config.lhs_loc = scratch.config.lhs_loc
        node.config.rhs_loc = scratch.config.rhs_loc
        node.config.out_loc = scratch.config.out_loc
        node.config.passthrough_mask = scratch.config.passthrough_mask
        node.config.pattern_id = scratch.config.pattern_id
        node.next = as(u32, out_count + 1)
        node.alt = 0
        node.label = as(u32, out_count)
        node.boundary_id = 0
        node.projection_id = 0
        jump loop(i = i + scratch.covered_ops, out_count = out_count + 1,
                  estimated = estimated + scratch.stencil.size)
    end
    end
end
]]

local jit_promotion_is_candidate = moon.func [[
jit_promotion_is_candidate(e: PromotionEvidence, min_hits: u64, min_ns_savings: i64) -> bool
    if e.hits < min_hits then return false end
    if e.ns_savings < min_ns_savings then return false end
    return true
end
]]

local jit_rewrite_has_equivalence = moon.func [[
jit_rewrite_has_equivalence(r: ptr(RewriteStencil)) -> bool
    if r == nil then return false end
    return r.equivalence.contract_id ~= 0
end
]]

local jit_rewrite_replacement_is_physical = moon.func(V) [[
jit_rewrite_replacement_is_physical(r: ptr(RewriteStencil)) -> bool
    if r == nil then return false end
    if r.replacement.kind == as(u8, @{REPL_EMPTY}) then return true end
    if r.replacement.kind == as(u8, @{REPL_CODE_STENCIL}) then return r.replacement.stencil ~= nil end
    if r.replacement.kind == as(u8, @{REPL_NODE_SEQUENCE}) then return r.replacement.nodes ~= nil and r.replacement.node_count > 0 end
    return false
end
]]

local jit_stencil_summary_within_policy = moon.func [[
jit_stencil_summary_within_policy(s: StencilSummary, p: StencilClosurePolicy) -> bool
    if s.max_arity > p.max_arity then return false end
    if s.closure_depth > p.max_depth then return false end
    if s.covered_ops > p.max_covered_ops then return false end
    if s.code_size > p.max_code_size then return false end
    if s.hole_count > p.max_holes then return false end
    if s.exit_count > p.max_exits then return false end
    return true
end
]]

local jit_plan_metrics_from_plan = moon.func [[
jit_plan_metrics_from_plan(plan: ptr(StencilPlan), out: ptr(StencilPlanMetrics), covered_ops: index,
                           max_depth: u8, granularity_score: u32) -> bool
    if plan == nil or out == nil then return false end
    out.node_count = plan.node_count
    out.covered_ops = covered_ops
    out.max_depth = max_depth
    out.granularity_score = granularity_score
    out.estimated_size = plan.estimated_size
    return true
end
]]

local jit_trace_select_plan_skeleton = moon.func(V) [[
jit_trace_select_plan_skeleton(record: ptr(TraceRecord), plan: ptr(StencilPlan)) -> u32
    if record == nil or plan == nil then return as(u32, @{TRACE_SELECT_INVALID}) end
    plan.nodes = nil
    plan.node_count = 0
    plan.fixups = nil
    plan.fixup_count = 0
    plan.projections = record.snapshots
    plan.projection_count = record.snapshot_count
    plan.estimated_size = 0
    if record.op_count == 0 then return as(u32, @{TRACE_SELECT_EMPTY}) end
    -- Real maximal stencil matching starts here.  Until a promoted trace
    -- stencil library is present, a non-empty trace must decline compilation
    -- loudly as NO_STENCIL rather than inventing fake code.
    return as(u32, @{TRACE_SELECT_NO_STENCIL})
end
]]

local jit_layout_stencil_plan = moon.func [[
jit_layout_stencil_plan(plan: ptr(StencilPlan)) -> index
    if plan == nil then return 0 end
    var total: index = 0
    return region -> index
    entry start()
        jump loop(i = as(index, 0), acc = total)
    end
    block loop(i: index, acc: index)
        if i >= plan.node_count then
            plan.estimated_size = acc
            yield acc
        end
        let node: ptr(StencilNode) = plan.nodes + i
        if node.stencil == nil then
            jump loop(i = i + 1, acc = acc)
        end
        jump loop(i = i + 1, acc = acc + node.stencil.size)
    end
    end
end
]]

return {
    jit_init_virtual_state = jit_init_virtual_state,
    jit_build_projection_header = jit_build_projection_header,
    jit_clear_stencil_plan = jit_clear_stencil_plan,
    jit_trace_anchor_tick = jit_trace_anchor_tick,
    jit_init_trace_record = jit_init_trace_record,
    jit_trace_record_has_path = jit_trace_record_has_path,
    jit_trace_record_is_guarded = jit_trace_record_is_guarded,
    jit_trace_pattern_matches = jit_trace_pattern_matches,
    jit_trace_match_at = jit_trace_match_at,
    jit_trace_select_pattern_plan = jit_trace_select_pattern_plan,
    jit_trace_select_plan_skeleton = jit_trace_select_plan_skeleton,
    jit_promotion_is_candidate = jit_promotion_is_candidate,
    jit_rewrite_has_equivalence = jit_rewrite_has_equivalence,
    jit_rewrite_replacement_is_physical = jit_rewrite_replacement_is_physical,
    jit_stencil_summary_within_policy = jit_stencil_summary_within_policy,
    jit_plan_metrics_from_plan = jit_plan_metrics_from_plan,
    jit_layout_stencil_plan = jit_layout_stencil_plan,
}
