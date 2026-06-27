local pvm = require("lalin.pvm")

local function class_name(x)
    local cls = pvm.classof(x) or x
    return tostring(cls):match("Class%((.-)%)") or tostring(cls)
end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.code_flow_facts ~= nil then return T._lalin_api_cache.code_flow_facts end

    local Core = T.LalinCore
    local Code = T.LalinCode
    local Graph = T.LalinGraph
    local Flow = T.LalinFlow
    local Value = T.LalinValue
    local CodeGraph = require("lalin.code_graph")(T)

    local api = {}

    local function block_index(func)
        local by_id, order = {}, {}
        for i, block in ipairs(func.blocks or {}) do
            by_id[block.id.text] = block
            order[block.id.text] = i
        end
        return by_id, order
    end

    local function edge_args(dest_block, args)
        local out = {}
        local params = dest_block and dest_block.params or {}
        for i, arg in ipairs(args or {}) do
            local param = params[i]
            if param ~= nil then out[#out + 1] = Flow.FlowEdgeArg(arg, param.value) end
        end
        return out
    end

    local function term_edge_args(func, block_by_id, block)
        local out = {}
        local term = block.term and block.term.kind or nil
        local cls = pvm.classof(term)
        local function add(dest, args)
            if dest ~= nil then out[dest.text] = edge_args(block_by_id[dest.text], args or {}) end
        end
        if cls == Code.CodeTermJump then
            add(term.dest, term.args)
        elseif cls == Code.CodeTermBranch then
            add(term.then_dest, term.then_args)
            add(term.else_dest, term.else_args)
        elseif cls == Code.CodeTermSwitch then
            for _, case in ipairs(term.cases or {}) do add(case.dest, case.args) end
            add(term.default_dest, term.default_args)
        elseif cls == Code.CodeTermVariantSwitch then
            for _, case in ipairs(term.cases or {}) do add(case.dest, case.args) end
            add(term.default_dest, term.default_args)
        end
        return out
    end

    local function edge_arg_facts(func, graph_func, block_by_id)
        local by_from_to = {}
        for _, block in ipairs(func.blocks or {}) do
            local args_by_dest = term_edge_args(func, block_by_id, block)
            for dest, args in pairs(args_by_dest) do by_from_to[block.id.text .. "\0" .. dest] = args end
        end
        local out = {}
        for _, edge in ipairs(graph_func.edges or {}) do
            out[#out + 1] = Flow.FlowEdgeFact(edge, by_from_to[edge.from.block.text .. "\0" .. edge.to.block.text] or {})
        end
        return out
    end

    local function value_defs(func)
        local defs, types = {}, {}
        for _, param in ipairs(func.params or {}) do types[param.value.text] = param.ty end
        for _, block in ipairs(func.blocks or {}) do
            for _, param in ipairs(block.params or {}) do types[param.value.text] = param.ty end
            for _, inst in ipairs(block.insts or {}) do
                local k = inst.kind
                local cls = pvm.classof(k)
                if cls == Code.CodeInstConst then
                    defs[k.dst.text] = { cls = cls, inst = inst, const = k.const }
                    types[k.dst.text] = k.const.ty
                elseif cls == Code.CodeInstAlias then
                    defs[k.dst.text] = { cls = cls, inst = inst, src = k.src, ty = k.ty }
                    types[k.dst.text] = k.ty
                elseif cls == Code.CodeInstBinary then
                    defs[k.dst.text] = { cls = cls, inst = inst, op = k.op, ty = k.ty, semantics = k.semantics, lhs = k.lhs, rhs = k.rhs }
                    types[k.dst.text] = k.ty
                elseif cls == Code.CodeInstCompare then
                    defs[k.dst.text] = { cls = cls, inst = inst, op = k.op, operand_ty = k.operand_ty, lhs = k.lhs, rhs = k.rhs }
                    types[k.dst.text] = Code.CodeTyBool8
                elseif cls == Code.CodeInstCast then
                    defs[k.dst.text] = { cls = cls, inst = inst, value = k.value, from = k.from, to = k.to }
                    types[k.dst.text] = k.to
                elseif k.dst ~= nil then
                    local ty = k.ty or k.ptr_ty or k.tag_ty
                    if cls == Code.CodeInstViewMake then ty = Code.CodeTyView(k.elem_ty) end
                    if cls == Code.CodeInstViewData then
                        local vty = types[k.view.text]
                        if pvm.classof(vty) == Code.CodeTyLease then vty = vty.base end
                        ty = Code.CodeTyDataPtr(pvm.classof(vty) == Code.CodeTyView and vty.elem or nil)
                    end
                    if cls == Code.CodeInstViewLen or cls == Code.CodeInstViewStride then ty = Code.CodeTyIndex end
                    if cls == Code.CodeInstSliceMake then ty = Code.CodeTySlice(k.elem_ty) end
                    if cls == Code.CodeInstSliceData then
                        local sty = types[k.slice.text]
                        if pvm.classof(sty) == Code.CodeTyLease then sty = sty.base end
                        ty = Code.CodeTyDataPtr(pvm.classof(sty) == Code.CodeTySlice and sty.elem or nil)
                    end
                    if cls == Code.CodeInstSliceLen then ty = Code.CodeTyIndex end
                    if cls == Code.CodeInstByteSpanMake then ty = Code.CodeTyByteSpan end
                    if cls == Code.CodeInstByteSpanData then ty = Code.CodeTyDataPtr(Code.CodeTyInt(8, Code.CodeUnsigned)) end
                    if cls == Code.CodeInstByteSpanLen then ty = Code.CodeTyIndex end
                    if cls == Code.CodeInstLoad then ty = k.access.ty end
                    defs[k.dst.text] = { cls = cls, inst = inst }
                    types[k.dst.text] = ty
                end
            end
        end
        return defs, types
    end

    local function const_values(defs)
        local out = {}
        for key, def in pairs(defs or {}) do
            if def.cls == Code.CodeInstConst and pvm.classof(def.const) == Code.CodeConstLiteral then
                local lit = def.const.literal
                local n = lit and lit.raw and tonumber(lit.raw) or nil
                if n ~= nil then out[key] = n end
            end
        end
        return out
    end

    local function const_ranges(defs)
        local ranges = {}
        local keys = {}
        for key in pairs(defs or {}) do keys[#keys + 1] = key end
        table.sort(keys)
        for _, key in ipairs(keys) do
            local def = defs[key]
            if def.cls == Code.CodeInstConst and pvm.classof(def.const) == Code.CodeConstLiteral then
                local lit = def.const.literal
                if lit ~= nil and lit.raw ~= nil then ranges[#ranges + 1] = Flow.FlowRangeExact(Code.CodeValueId(key), Flow.FlowBoundConst(lit.raw)) end
            end
        end
        return ranges
    end

    local function edge_condition(block_by_id, edge)
        local block = edge and edge.from and edge.from.block and block_by_id[edge.from.block.text]
        local term = block and block.term and block.term.kind or nil
        if pvm.classof(term) == Code.CodeTermBranch then return term.cond end
        return nil
    end

    local function incoming_arg_for(edge_facts, header, param, skip_from)
        for _, fact in ipairs(edge_facts or {}) do
            local edge = fact.edge
            if edge.to.block == header and (skip_from == nil or edge.from.block ~= skip_from) then
                for _, arg in ipairs(fact.args or {}) do if arg.dst_param == param.value then return arg.src end end
            end
        end
        return nil
    end

    local function backedge_arg_for(edge_fact, param)
        for _, arg in ipairs(edge_fact and edge_fact.args or {}) do if arg.dst_param == param.value then return arg.src end end
        return nil
    end

    local function canonical_value(value, aliases)
        local seen = {}
        while value ~= nil and aliases ~= nil and aliases[value.text] ~= nil and not seen[value.text] do
            seen[value.text] = true
            value = aliases[value.text]
        end
        return value
    end

    local function same_canonical_value(a, b, aliases)
        a, b = canonical_value(a, aliases), canonical_value(b, aliases)
        return a ~= nil and b ~= nil and a == b
    end

    local function induction_step(param_value, back_value, defs, aliases)
        local def = back_value and defs[back_value.text] or nil
        if def == nil or def.cls ~= Code.CodeInstBinary then return nil, "backedge value is not a binary recurrence" end
        if def.op == Core.BinAdd then
            if same_canonical_value(def.lhs, param_value, aliases) then return def.rhs, nil end
            if same_canonical_value(def.rhs, param_value, aliases) then return def.lhs, nil end
        elseif def.op == Core.BinSub then
            if same_canonical_value(def.lhs, param_value, aliases) then return def.rhs, "subtraction induction records positive step magnitude; signed direction is not represented yet" end
        end
        return nil, "binary recurrence does not reference the header parameter"
    end

    local function compare_stop(cond, induction_value, defs)
        local def = cond and defs[cond.text] or nil
        if def == nil or def.cls ~= Code.CodeInstCompare then return nil, nil end
        if def.lhs == induction_value then
            local op = def.op
            return def.rhs, (op == Core.CmpLt or op == Core.CmpGe)
        elseif def.rhs == induction_value then
            local op = def.op
            return def.lhs, (op == Core.CmpGt or op == Core.CmpLe)
        end
        return nil, nil
    end

    local function range_for_induction(value, init, stop, exclusive, consts)
        local min = consts[init.text] and Flow.FlowBoundConst(tostring(consts[init.text])) or Flow.FlowBoundValue(init)
        local max = stop and (consts[stop.text] and Flow.FlowBoundConst(tostring(consts[stop.text])) or Flow.FlowBoundValue(stop)) or Flow.FlowBoundUnknown
        return Flow.FlowRangeDerived(value, min, max, "recognized counted loop induction range"), min, max, exclusive == true
    end

    local function analyze_loop(func, block_by_id, graph_loop, edge_facts, defs, types, consts)
        local rejects, inductions = {}, {}
        local latch = graph_loop.latches and graph_loop.latches[1] or nil
        if latch == nil then
            return Flow.FlowLoopFacts(graph_loop.id, Flow.FlowDomainLoop(graph_loop.id), nil, graph_loop.body or {}, {}, {}, { Flow.FlowRejectNotCounted(graph_loop.id, "loop has no latch edge") })
        end
        local header_block = block_by_id[graph_loop.header.block.text]
        local latch_fact = nil
        for _, fact in ipairs(edge_facts or {}) do if fact.edge == latch then latch_fact = fact; break end end
        if header_block == nil or latch_fact == nil then
            return Flow.FlowLoopFacts(graph_loop.id, Flow.FlowDomainLoop(graph_loop.id), nil, graph_loop.body or {}, {}, {}, { Flow.FlowRejectNotCounted(graph_loop.id, "loop header or latch edge is missing") })
        end

        local cond = edge_condition(block_by_id, latch)
        if cond == nil then
            for _, exit_edge in ipairs(graph_loop.exits or {}) do
                cond = cond or edge_condition(block_by_id, exit_edge)
            end
        end
        local loop_blocks = {}
        for _, block in ipairs(graph_loop.body or {}) do loop_blocks[block.block.text] = true end
        local aliases = {}
        local changed = true
        while changed do
            changed = false
            for _, fact in ipairs(edge_facts or {}) do
                local edge = fact.edge
                if edge ~= latch and loop_blocks[edge.from.block.text] and loop_blocks[edge.to.block.text] then
                    for _, arg in ipairs(fact.args or {}) do
                        local src = canonical_value(arg.src, aliases)
                        if src ~= nil and src ~= arg.dst_param and aliases[arg.dst_param.text] == nil then
                            aliases[arg.dst_param.text] = src
                            changed = true
                        end
                    end
                end
            end
        end

        local counted = nil
        for _, param in ipairs(header_block.params or {}) do
            local init = incoming_arg_for(edge_facts, graph_loop.header.block, param, latch.from.block)
            local back = backedge_arg_for(latch_fact, param)
            if init ~= nil and back ~= nil then
                local step, note = induction_step(param.value, back, defs, aliases)
                if step ~= nil then
                    local stop, exclusive = compare_stop(cond, param.value, defs)
                    local range = Flow.FlowRangeUnknown(param.value)
                    local kind = Flow.FlowDerivedInduction(param.value)
                    if stop ~= nil then
                        local _, min, max, max_exclusive = range_for_induction(param.value, init, stop, exclusive, consts)
                        range = Flow.FlowRangeDerived(param.value, min, max, "primary induction of counted loop")
                        counted = counted or Flow.FlowCountedDomain(init, stop, step, exclusive == true)
                        kind = Flow.FlowPrimaryInduction
                    end
                    inductions[#inductions + 1] = Flow.FlowInduction(param.value, types[param.value.text] or Code.CodeTyIndex, init, step, kind, range)
                    if note ~= nil then rejects[#rejects + 1] = Flow.FlowRejectUnsupportedInduction(graph_loop.id, param.value, note) end
                end
            end
        end
        if counted == nil then rejects[#rejects + 1] = Flow.FlowRejectNotCounted(graph_loop.id, "no header parameter matched a counted recurrence") end

        local exits = {}
        for _, edge in ipairs(graph_loop.exits or {}) do exits[#exits + 1] = Flow.FlowLoopExit(edge.from, edge.to, edge_condition(block_by_id, edge)) end
        return Flow.FlowLoopFacts(graph_loop.id, Flow.FlowDomainLoop(graph_loop.id), counted, graph_loop.body or {}, inductions, exits, rejects)
    end

    local function is_native_loop_header(block_by_id, graph_loop)
        local header = graph_loop and graph_loop.header and block_by_id[graph_loop.header.block.text]
        return type(header and header.name) == "string" and header.name:match("^ctl%.lln_loop_") ~= nil
    end

    local function primary_induction(loop_fact)
        for _, induction in ipairs(loop_fact and loop_fact.inductions or {}) do
            if induction.kind == Flow.FlowPrimaryInduction then return induction end
        end
        return nil
    end

    local function numeric_const(value, defs, consts, seen)
        if value == nil then return nil end
        if consts[value.text] ~= nil then return consts[value.text] end
        seen = seen or {}
        if seen[value.text] then return nil end
        seen[value.text] = true
        local def = defs[value.text]
        if def ~= nil and def.cls == Code.CodeInstCast then return numeric_const(def.value, defs, consts, seen) end
        if def ~= nil and def.cls == Code.CodeInstAlias then return numeric_const(def.src, defs, consts, seen) end
        return nil
    end

    local function native_window_boundary(name)
        if name == "clamp" then return Flow.FlowWindowBoundaryClamp end
        if name == "wrap" then return Flow.FlowWindowBoundaryWrap end
        if name == "zero" then return Flow.FlowWindowBoundaryZero end
        return Flow.FlowWindowBoundaryReject
    end

    local function native_nd_shape_from_header(header_name, axes)
        local stem = tostring(header_name or ""):gsub("_scan_axis_%d+$", "")
        local tiled = stem:match("_tiled_([%dx]+)$")
        if tiled ~= nil then
            local tile_sizes = {}
            for raw in tiled:gmatch("%d+") do tile_sizes[#tile_sizes + 1] = tonumber(raw) end
            if #tile_sizes == #axes then return Flow.FlowDomainShapeTiledND(axes, tile_sizes) end
        end
        local window = stem:match("_window_(.+)$")
        if window ~= nil then
            local windows = {}
            for boundary, before, after in window:gmatch("([a-z]+)_(%d+)_(%d+)") do
                windows[#windows + 1] = Flow.FlowWindowAxis(tonumber(before), tonumber(after), native_window_boundary(boundary))
            end
            if #windows == #axes then return Flow.FlowDomainShapeWindowND(axes, windows) end
        end
        return Flow.FlowDomainShapeRangeND(axes)
    end

    local function native_nd_axis_facts(header_block, edge_facts, graph_loop)
        if type(header_block and header_block.name) ~= "string" or header_block.name:match("^ctl%.lln_loop_nd_") == nil then return nil end
        local latch = graph_loop and graph_loop.latches and graph_loop.latches[1] or nil
        local skip_from = latch and latch.from and latch.from.block or nil
        local grouped = {}
        for _, param in ipairs(header_block.params or {}) do
            local axis_i, index_name, field, step, order = tostring(param.name or ""):match("^__lln_axis_[^_]+_(%d+)_idx_([_%a][_%w]*)_(%a+)_step_(%d+)_order_(%a+)$")
            if axis_i == nil then
                axis_i, field, step, order = tostring(param.name or ""):match("^__lln_axis_[^_]+_(%d+)_(%a+)_step_(%d+)_order_(%a+)$")
            end
            if axis_i ~= nil and (field == "start" or field == "stop" or field == "trip") then
                axis_i = tonumber(axis_i)
                grouped[axis_i] = grouped[axis_i] or { step = tonumber(step), order = order, ty = param.ty }
                grouped[axis_i][field] = incoming_arg_for(edge_facts, graph_loop.header.block, param, skip_from)
                grouped[axis_i].ty = grouped[axis_i].ty or param.ty
                grouped[axis_i].index_name = grouped[axis_i].index_name or index_name
            end
        end
        local axes = {}
        local i = 1
        while grouped[i] ~= nil do
            local axis = grouped[i]
            if axis.start == nil or axis.stop == nil or axis.step == nil then return nil end
            axes[#axes + 1] = Flow.FlowDomainAxis(
                axis.ty or Code.CodeTyIndex,
                Value.ValueExprValue(axis.start),
                Value.ValueExprValue(axis.stop),
                axis.step,
                axis.order == "backward" and Flow.FlowDomainBackward or Flow.FlowDomainForward,
                axis.index_name
            )
            i = i + 1
        end
        if #axes < 1 then return nil end
        return native_nd_shape_from_header(header_block.name, axes)
    end

    local function append_native_loop_domain_facts(domain_shapes, domain_intents, loop_fact, defs, consts, header_block, edge_facts, graph_loop)
        local domain = loop_fact and loop_fact.domain
        local nd_shape = native_nd_axis_facts(header_block, edge_facts, graph_loop)
        if nd_shape ~= nil then
            local proof = Flow.FlowProofDomain(domain, "lln.loop authored an explicit multi-axis producer")
            domain_shapes[#domain_shapes + 1] = Flow.FlowDomainShapeFact(
                domain,
                nd_shape,
                { proof },
                Flow.FlowFactFrontendFact("lln.nd_producer")
            )
            domain_intents[#domain_intents + 1] = Flow.FlowDomainIntentFact(
                domain,
                Flow.FlowDomainIntentNativeLoop("lln.loop"),
                { Flow.FlowProofFrontendFact("lln.loop authored this loop domain") },
                Flow.FlowFactFrontendFact("lln.loop")
            )
            return
        end

        local counted = loop_fact and loop_fact.counted
        local primary = primary_induction(loop_fact)
        if counted == nil or primary == nil then return end
        local step_num = numeric_const(counted.step, defs, consts)
        if step_num == nil or step_num == 0 then return end
        local order = step_num < 0 and Flow.FlowDomainBackward or Flow.FlowDomainForward
        local proof = Flow.FlowProofDomain(domain, "lln.loop authored a regular counted range")
        domain_shapes[#domain_shapes + 1] = Flow.FlowDomainShapeFact(
            domain,
            Flow.FlowDomainShapeRange1D(
                primary.ty or Code.CodeTyIndex,
                Value.ValueExprValue(counted.start),
                Value.ValueExprValue(counted.stop),
                math.abs(step_num),
                order
            ),
            { proof },
            Flow.FlowFactFrontendFact("lln.range")
        )
        domain_intents[#domain_intents + 1] = Flow.FlowDomainIntentFact(
            domain,
            Flow.FlowDomainIntentNativeLoop("lln.loop"),
            { Flow.FlowProofFrontendFact("lln.loop authored this loop domain") },
            Flow.FlowFactFrontendFact("lln.loop")
        )
    end

    local function facts(module, graph)
        graph = graph or CodeGraph.graph(module)
        local graph_by_func = {}
        for _, fg in ipairs(graph.funcs or {}) do graph_by_func[fg.func.text] = fg end

        local domains, edge_facts, loops, ranges, domain_shapes, domain_intents, rejects = {}, {}, {}, {}, {}, {}, {}
        for _, func in ipairs(module.funcs or {}) do
            local graph_func = graph_by_func[func.id.text]
            if graph_func ~= nil then
                local block_by_id = block_index(func)
                domains[#domains + 1] = Flow.FlowDomainFunction(func.id)
                local func_edge_facts = edge_arg_facts(func, graph_func, block_by_id)
                for _, fact in ipairs(func_edge_facts) do edge_facts[#edge_facts + 1] = fact end

                local defs, types = value_defs(func)
                local consts = const_values(defs)
                for _, range in ipairs(const_ranges(defs)) do ranges[#ranges + 1] = range end

                for _, graph_loop in ipairs(graph_func.loops or {}) do
                    domains[#domains + 1] = Flow.FlowDomainLoop(graph_loop.id)
                    local lf = analyze_loop(func, block_by_id, graph_loop, func_edge_facts, defs, types, consts)
                    loops[#loops + 1] = lf
                    if is_native_loop_header(block_by_id, graph_loop) then
                        append_native_loop_domain_facts(domain_shapes, domain_intents, lf, defs, consts, block_by_id[graph_loop.header.block.text], func_edge_facts, graph_loop)
                    end
                    for _, reject in ipairs(lf.rejects or {}) do rejects[#rejects + 1] = reject end
                end
            end
        end
        return Flow.FlowFactSet(module.id, domains, edge_facts, loops, ranges, domain_shapes, domain_intents, rejects)
    end

    local function is_primary_induction(induction)
        return pvm.classof(induction.kind) == nil and induction.kind == Flow.FlowPrimaryInduction
    end

    local function direction_for(primary, defs, consts)
        local step_num = primary and primary.step and consts[primary.step.text] or nil
        if step_num == nil then return Flow.FlowLoopDirectionUnknown end
        if step_num > 0 then return Flow.FlowLoopIncreasing end
        if step_num < 0 then return Flow.FlowLoopDecreasing end
        return Flow.FlowLoopDirectionUnknown
    end

    local function semantic_facts(module, graph_or_flow, maybe_flow)
        local flow_facts
        if maybe_flow ~= nil then
            flow_facts = maybe_flow
        elseif graph_or_flow ~= nil and pvm.classof(graph_or_flow) == Flow.FlowFactSet then
            flow_facts = graph_or_flow
        else
            flow_facts = facts(module, graph_or_flow)
        end

        local defs_by_func, consts_by_func = {}, {}
        for _, func in ipairs(module.funcs or {}) do
            local defs = value_defs(func)
            defs_by_func[func.id.text] = defs
            consts_by_func[func.id.text] = const_values(defs)
        end

        local graph_loop_func = {}
        local graph = (graph_or_flow ~= nil and pvm.classof(graph_or_flow) == Graph.CodeGraph) and graph_or_flow or nil
        if graph ~= nil then
            for _, fg in ipairs(graph.funcs or {}) do
                for _, loop in ipairs(fg.loops or {}) do graph_loop_func[loop.id.text] = fg.func end
            end
        end

        local out = {}
        for _, loop in ipairs(flow_facts.loops or {}) do
            if loop.counted ~= nil then
                local primary = nil
                for _, induction in ipairs(loop.inductions or {}) do if is_primary_induction(induction) then primary = primary or induction end end
                local func_id = graph_loop_func[loop.loop.text]
                local consts = func_id and consts_by_func[func_id.text] or {}
                local direction = direction_for(primary, defs_by_func[func_id and func_id.text or ""] or {}, consts)
                out[#out + 1] = Flow.FlowLoopNormalizedCounted(loop.loop, loop.counted, direction, Flow.FlowTripCountUnknown("no explicit trip-count CodeValueId is available"))
                if primary ~= nil and direction == Flow.FlowLoopIncreasing and loop.counted.stop_exclusive then
                    local _, min, max = range_for_induction(primary.value, loop.counted.start, loop.counted.stop, true, consts)
                    out[#out + 1] = Flow.FlowLoopInductionRange(Flow.FlowInductionRangeFact(loop.loop, primary.value, min, max, true, "primary induction of increasing exclusive counted loop stays within [start, stop) on executed iterations"))
                end
            end
        end
        return Flow.FlowSemanticFactSet(module.id, out)
    end

    api.facts = facts
    api.module = facts
    api.semantic_facts = semantic_facts
    api.semantics = semantic_facts

    T._lalin_api_cache.code_flow_facts = api
    return api
end

return bind_context
