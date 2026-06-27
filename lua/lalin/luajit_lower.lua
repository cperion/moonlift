local pvm = require("lalin.pvm")

local function class_name(value)
    local cls = pvm.classof(value) or value
    return tostring(cls):match("Class%((.-)%)") or tostring(cls)
end

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s == "" then s = "x" end
    if s:match("^%d") then s = "_" .. s end
    return s
end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.luajit_lower ~= nil then return T._lalin_api_cache.luajit_lower end

    local Core = T.LalinCore
    local Code = T.LalinCode
    local Flow = T.LalinFlow
    local Value = T.LalinValue
    local Mem = T.LalinMem
    local Kernel = T.LalinKernel
    local LJ = T.LalinLuaJIT
    local Stencil = T.LalinStencil

    local CType = require("lalin.luajit_ctype")(T)
    local Expr = require("lalin.luajit_expr")(T)
    local CodeGraph = require("lalin.code_graph")(T)
    local CodeFlowFacts = require("lalin.code_flow_facts")(T)
    local CodeValueFacts = require("lalin.code_value_facts")(T)
    local CodeMemFacts = require("lalin.code_mem_facts")(T)
    local CodeEffectFacts = require("lalin.code_effect_facts")(T)
    local CodeKernelPlan = require("lalin.code_kernel_plan")(T)
    local StencilRules = require("lalin.stencil_rules")(T)
    local StencilArtifactPlan = require("lalin.stencil_artifact_plan")(T)
    local LowerRules = require("lalin.luajit_lower_rules")(T)

    local api = {}

    local function vid(id) return LJ.LJValueId((id.text or ""):gsub("^v:", "")) end
    local function bid(id) return LJ.LJBlockId(id.text) end
    local function fid(id) return LJ.LJFuncId(id.text) end
    local function sigid(id) return LJ.LJFuncSigId(id.text) end

    local function physical(ctx, ty)
        return CType.physical_type(ty, ctx)
    end

    local function literal_expr(ctx, ty, raw)
        return LJ.LJExprLiteral(Core.LitInt(tostring(raw)), physical(ctx, ty))
    end

    local function code_sigs(module)
        local out = {}
        for _, sig in ipairs(module.sigs or {}) do out[sig.id.text] = sig end
        return out
    end

    local function contract_facts(contracts)
        if contracts == nil then return {} end
        if pvm.classof(contracts) == Code.CodeContractFactSet then return contracts.facts or {} end
        return contracts
    end

    local function soa_contract_index(contracts)
        local out = {}
        for _, fact in ipairs(contract_facts(contracts)) do
            local k = fact.fact
            if pvm.classof(k) == Code.CodeContractSoAComponent then
                out[fact.func.text .. "\0" .. k.base.text] = k
            end
        end
        return out
    end

    local function flow_domain_key(domain)
        local cls = pvm.classof(domain)
        if cls == Flow.FlowDomainLoop then return "loop:" .. domain.loop.text end
        if cls == Flow.FlowDomainFunction then return "func:" .. domain.func.text end
        return tostring(domain)
    end

    local function stencil_order(order)
        if order == Flow.FlowDomainBackward then return Stencil.StencilProducerBackward end
        return Stencil.StencilProducerForward
    end

    local function stencil_axis(axis)
        return Stencil.StencilProducerAxis(axis.index_ty, axis.start, axis.stop, axis.step, stencil_order(axis.order), axis.index_name)
    end

    local function stencil_boundary(boundary)
        if boundary == Flow.FlowWindowBoundaryClamp then return Stencil.StencilWindowBoundaryClamp end
        if boundary == Flow.FlowWindowBoundaryWrap then return Stencil.StencilWindowBoundaryWrap end
        if boundary == Flow.FlowWindowBoundaryZero then return Stencil.StencilWindowBoundaryZero end
        return Stencil.StencilWindowBoundaryReject
    end

    local function stencil_window_axis(axis)
        return Stencil.StencilWindowAxis(axis.before, axis.after, stencil_boundary(axis.boundary))
    end

    local function map_list(xs, f)
        local out = {}
        for i, x in ipairs(xs or {}) do out[i] = f(x) end
        return out
    end

    local function stencil_producer_shape(shape)
        local cls = pvm.classof(shape)
        if cls == Flow.FlowDomainShapeRange1D then
            return Stencil.StencilProduceRange1D(shape.index_ty, shape.start, shape.stop, shape.step, stencil_order(shape.order))
        elseif cls == Flow.FlowDomainShapeRangeND then
            return Stencil.StencilProduceRangeND(map_list(shape.axes, stencil_axis))
        elseif cls == Flow.FlowDomainShapeWindowND then
            return Stencil.StencilProduceWindowND(map_list(shape.axes, stencil_axis), map_list(shape.windows, stencil_window_axis))
        elseif cls == Flow.FlowDomainShapeTiledND then
            return Stencil.StencilProduceTiledND(map_list(shape.axes, stencil_axis), shape.tile_sizes or {})
        end
        error("luajit_lower: unsupported FlowDomainShape " .. class_name(shape), 3)
    end

    local function stencil_producer_origin(origin)
        local cls = pvm.classof(origin)
        if origin == Flow.FlowFactCheckerDerived then return Stencil.StencilProducerCheckerDerived end
        if cls == Flow.FlowFactAuthorAsserted then return Stencil.StencilProducerAuthorAsserted(origin.reason) end
        if cls == Flow.FlowFactFrontendFact then return Stencil.StencilProducerFrontendFact(origin.reason) end
        return Stencil.StencilProducerCheckerDerived
    end

    local function kernel_proof_from_flow_proof(domain, proof)
        local cls = pvm.classof(proof)
        if cls == Flow.FlowProofDomain then return Kernel.KernelProofFlow(proof.domain, proof.reason) end
        if cls == Flow.FlowProofMemory then return Kernel.KernelProofMemory(proof.proof, proof.reason) end
        if cls == Flow.FlowProofAuthorAsserted then return Kernel.KernelProofFlow(domain, proof.reason) end
        if cls == Flow.FlowProofFrontendFact then return Kernel.KernelProofFlow(domain, proof.reason) end
        return Kernel.KernelProofFlow(domain, "unknown FlowProof")
    end

    local function producer_fact_from_domain_shape(fact)
        local producer = Stencil.StencilProducer(fact.domain, stencil_producer_shape(fact.shape))
        local proofs = {}
        for i, proof in ipairs(fact.proofs or {}) do proofs[i] = kernel_proof_from_flow_proof(fact.domain, proof) end
        return Stencil.StencilProducerFact(fact.domain, producer, proofs, stencil_producer_origin(fact.origin))
    end

    local function producer_fact_index(flow)
        local out = {}
        for _, shape_fact in ipairs(flow and flow.domain_shapes or {}) do
            local fact = producer_fact_from_domain_shape(shape_fact)
            out[flow_domain_key(fact.domain)] = fact
        end
        return out
    end

    local function block_index(func)
        local out = {}
        for _, block in ipairs(func.blocks or {}) do out[block.id.text] = block end
        return out
    end

    local function func_index(module)
        local out = {}
        for _, func in ipairs(module.funcs or {}) do out[func.id.text] = func end
        return out
    end

    local function value_defs(func)
        local defs = {}
        for _, param in ipairs(func.params or {}) do defs[param.value.text] = { param = param, ty = param.ty } end
        for _, block in ipairs(func.blocks or {}) do
            for _, param in ipairs(block.params or {}) do defs[param.value.text] = { param = param, ty = param.ty } end
            for _, inst in ipairs(block.insts or {}) do
                local k = inst.kind
                if k.dst ~= nil then defs[k.dst.text] = { inst = inst, kind = k } end
            end
        end
        return defs
    end

    local function value_type(ctx, id)
        local ty = ctx.value_types and id and ctx.value_types[id.text] or nil
        if ty ~= nil then return ty end
        local def = ctx.defs and id and ctx.defs[id.text] or nil
        if def == nil then return Code.CodeTyIndex end
        if def.ty ~= nil then return def.ty end
        local k = def.kind
        local cls = pvm.classof(k)
        if cls == Code.CodeInstConst then return k.const.ty end
        if cls == Code.CodeInstAlias or cls == Code.CodeInstUnary or cls == Code.CodeInstBinary or cls == Code.CodeInstFloatBinary or cls == Code.CodeInstSelect or cls == Code.CodeInstAggregate or cls == Code.CodeInstArray then return k.ty end
        if cls == Code.CodeInstCompare then return Code.CodeTyBool8 end
        if cls == Code.CodeInstCast then return k.to end
        if cls == Code.CodeInstLoad then return k.access.ty end
        if cls == Code.CodeInstViewMake then return Code.CodeTyView(k.elem_ty) end
        if cls == Code.CodeInstViewLen or cls == Code.CodeInstViewStride then return Code.CodeTyIndex end
        if cls == Code.CodeInstViewData then return Code.CodeTyDataPtr(nil) end
        if cls == Code.CodeInstSliceMake then return Code.CodeTySlice(k.elem_ty) end
        if cls == Code.CodeInstSliceLen then return Code.CodeTyIndex end
        if cls == Code.CodeInstSliceData then return Code.CodeTyDataPtr(nil) end
        if cls == Code.CodeInstByteSpanMake then return Code.CodeTyByteSpan end
        if cls == Code.CodeInstByteSpanLen then return Code.CodeTyIndex end
        if cls == Code.CodeInstByteSpanData then return Code.CodeTyDataPtr(Code.CodeTyInt(8, Code.CodeUnsigned)) end
        if cls == Code.CodeInstAddrOf or cls == Code.CodeInstGlobalRef or cls == Code.CodeInstPtrOffset then return k.ptr_ty end
        if cls == Code.CodeInstVariantTag then return k.tag_ty end
        if cls == Code.CodeInstVariantPayload then return k.variant.payload_ty or Code.CodeTyVoid end
        return Code.CodeTyIndex
    end

    local function value_id_expr(ctx, id)
        local def = ctx.defs and id and ctx.defs[id.text] or nil
        if def ~= nil and pvm.classof(def.kind) == Code.CodeInstConst and pvm.classof(def.kind.const) == Code.CodeConstLiteral then
            return LJ.LJExprLiteral(def.kind.const.literal, physical(ctx, def.kind.const.ty))
        end
        return LJ.LJExprValue(vid(id))
    end

    local function captured_closure_descriptor(ctx, id)
        local def = ctx.defs and id and ctx.defs[id.text] or nil
        local k = def and def.kind or nil
        if pvm.classof(k) ~= Code.CodeInstAggregate then return false end
        if pvm.classof(k.ty) ~= Code.CodeTyClosure then return false end
        return #(k.fields or {}) > 1
    end

    local value_expr
    value_expr = function(ctx, expr)
        local cls = pvm.classof(expr)
        if cls == Value.ValueExprConst then
            return Expr.const_expr(ctx, expr.const)
        elseif cls == Value.ValueExprValue then
            return value_id_expr(ctx, expr.value)
        elseif cls == Value.ValueExprUnary then
            return LJ.LJExprUnary(expr.op, physical(ctx, expr.ty), value_expr(ctx, expr.value))
        elseif cls == Value.ValueExprCast then
            return LJ.LJExprCast(expr.op, physical(ctx, expr.from), physical(ctx, expr.to), value_expr(ctx, expr.value))
        elseif cls == Value.ValueExprAdd or cls == Value.ValueExprSub or cls == Value.ValueExprMul or cls == Value.ValueExprDiv or cls == Value.ValueExprRem then
            local op = (cls == Value.ValueExprAdd and Core.BinAdd)
                or (cls == Value.ValueExprSub and Core.BinSub)
                or (cls == Value.ValueExprMul and Core.BinMul)
                or (cls == Value.ValueExprRem and Core.BinRem)
                or Core.BinDiv
            return LJ.LJExprIntBinary(op, physical(ctx, expr.ty), expr.sem, value_expr(ctx, expr.a), value_expr(ctx, expr.b))
        elseif cls == Value.ValueExprBinary then
            return LJ.LJExprIntBinary(expr.op, physical(ctx, expr.ty), expr.sem, value_expr(ctx, expr.a), value_expr(ctx, expr.b))
        end
        error("luajit_lower: unsupported ValueExpr " .. class_name(expr), 3)
    end

    local producer_value_expr
    local function producer_value_id_expr(ctx, id, seen)
        local def = ctx.defs and id and ctx.defs[id.text] or nil
        local k = def and def.kind
        local cls = pvm.classof(k)
        if cls == Code.CodeInstConst and pvm.classof(k.const) == Code.CodeConstLiteral then
            return Expr.const_expr(ctx, k.const)
        end
        seen = seen or {}
        if id ~= nil and seen[id.text] then return value_id_expr(ctx, id) end
        if id ~= nil then seen[id.text] = true end
        if cls == Code.CodeInstAlias then return producer_value_id_expr(ctx, k.src, seen) end
        if cls == Code.CodeInstCast then
            return LJ.LJExprCast(k.op, physical(ctx, k.from), physical(ctx, k.to), producer_value_id_expr(ctx, k.value, seen))
        end
        if cls == Code.CodeInstBinary then
            return LJ.LJExprIntBinary(k.op, physical(ctx, k.ty), k.semantics, producer_value_id_expr(ctx, k.lhs, seen), producer_value_id_expr(ctx, k.rhs, seen))
        end
        return value_id_expr(ctx, id)
    end

    producer_value_expr = function(ctx, expr)
        if pvm.classof(expr) == Value.ValueExprValue then return producer_value_id_expr(ctx, expr.value) end
        return value_expr(ctx, expr)
    end

    local function note_params(ctx, params)
        for _, param in ipairs(params or {}) do
            ctx.value_types[param.value.text] = param.ty
        end
    end

    local function lower_param(ctx, param)
        return LJ.LJParam(vid(param.value), param.name, physical(ctx, param.ty))
    end

    local function lower_params(ctx, params)
        local out = {}
        for i, param in ipairs(params or {}) do out[i] = lower_param(ctx, param) end
        return out
    end

    local function lower_term(ctx, term)
        local k = term.kind
        local cls = pvm.classof(k)
        local function exprs(ids)
            local out = {}
            for i, id in ipairs(ids or {}) do out[i] = value_id_expr(ctx, id) end
            return out
        end
        if cls == Code.CodeTermJump then
            return LJ.LJTermJump(bid(k.dest), exprs(k.args))
        elseif cls == Code.CodeTermBranch then
            return LJ.LJTermBranch(value_id_expr(ctx, k.cond), bid(k.then_dest), exprs(k.then_args), bid(k.else_dest), exprs(k.else_args))
        elseif cls == Code.CodeTermSwitch then
            local cases = {}
            for i, case in ipairs(k.cases or {}) do cases[i] = LJ.LJCase(case.literal, bid(case.dest), exprs(case.args)) end
            return LJ.LJTermSwitch(value_id_expr(ctx, k.value), cases, bid(k.default_dest), exprs(k.default_args))
        elseif cls == Code.CodeTermVariantSwitch then
            local cases = {}
            for i, case in ipairs(k.cases or {}) do
                cases[i] = LJ.LJCase(Core.LitInt(tostring(case.variant.tag_value)), bid(case.dest), exprs(case.args))
            end
            return LJ.LJTermSwitch(value_id_expr(ctx, k.tag), cases, bid(k.default_dest), exprs(k.default_args))
        elseif cls == Code.CodeTermReturn then
            for _, value in ipairs(k.values or {}) do
                if captured_closure_descriptor(ctx, value) then
                    error("luajit_lower: returning captured closure descriptors requires a closure environment ownership model", 3)
                end
            end
            return LJ.LJTermReturn(exprs(k.values))
        elseif cls == Code.CodeTermTrap then
            return LJ.LJTermTrap(k.reason)
        elseif cls == Code.CodeTermUnreachable then
            return LJ.LJTermTrap(k.reason or "unreachable")
        end
        error("luajit_lower: unsupported CodeTerm " .. class_name(k), 3)
    end

    local function lower_block(ctx, block)
        note_params(ctx, block.params)
        local stmts = {}
        for i, inst in ipairs(block.insts or {}) do stmts[i] = Expr.inst_to_stmt(ctx, inst) end
        return LJ.LJBlock(bid(block.id), lower_params(ctx, block.params), stmts, lower_term(ctx, block.term))
    end

    local function graph_loop_index(graph)
        local by_loop, by_func = {}, {}
        for _, fg in ipairs(graph and graph.funcs or {}) do
            for _, loop in ipairs(fg.loops or {}) do
                by_loop[loop.id.text] = loop
                by_func[loop.id.text] = fg.func
            end
        end
        return by_loop, by_func
    end

    local function flow_loop_index(flow)
        local out = {}
        for _, loop in ipairs(flow and flow.loops or {}) do out[loop.loop.text] = loop end
        return out
    end

    local function mem_access_index(mem)
        local out = {}
        for _, access in ipairs(mem and mem.accesses or {}) do out[access.id.text] = access end
        return out
    end

    local function mem_object_index(mem)
        local out = {}
        for _, object in ipairs(mem and mem.objects or {}) do out[object.id.text] = object end
        return out
    end

    local function const_int_value(ctx, id, seen)
        local def = ctx.defs and id and ctx.defs[id.text] or nil
        local k = def and def.kind
        local cls = pvm.classof(k)
        if cls == Code.CodeInstConst and pvm.classof(k.const) == Code.CodeConstLiteral and pvm.classof(k.const.literal) == Core.LitInt then
            return tonumber(k.const.literal.raw)
        end
        if cls == Code.CodeInstCast then
            seen = seen or {}
            if id ~= nil and seen[id.text] then return nil end
            if id ~= nil then seen[id.text] = true end
            return const_int_value(ctx, k.value, seen)
        end
        if cls == Code.CodeInstAlias then
            seen = seen or {}
            if id ~= nil and seen[id.text] then return nil end
            if id ~= nil then seen[id.text] = true end
            return const_int_value(ctx, k.src, seen)
        end
        return nil
    end

    local function term_args_to_dest(term, dest)
        local k = term and term.kind
        local cls = pvm.classof(k)
        if cls == Code.CodeTermJump and k.dest == dest then return k.args or {} end
        if cls == Code.CodeTermBranch then
            if k.then_dest == dest then return k.then_args or {} end
            if k.else_dest == dest then return k.else_args or {} end
        elseif cls == Code.CodeTermSwitch then
            for _, case in ipairs(k.cases or {}) do if case.dest == dest then return case.args or {} end end
            if k.default_dest == dest then return k.default_args or {} end
        elseif cls == Code.CodeTermVariantSwitch then
            for _, case in ipairs(k.cases or {}) do if case.dest == dest then return case.args or {} end end
            if k.default_dest == dest then return k.default_args or {} end
        end
        return nil
    end

    local function same_value_id(a, b)
        return a ~= nil and b ~= nil and a.text == b.text
    end

    local function term_successors(term)
        local k = term and term.kind
        local cls = pvm.classof(k)
        local out = {}
        if cls == Code.CodeTermJump then
            out[#out + 1] = { dest = k.dest, args = k.args or {} }
        elseif cls == Code.CodeTermBranch then
            out[#out + 1] = { dest = k.then_dest, args = k.then_args or {} }
            out[#out + 1] = { dest = k.else_dest, args = k.else_args or {} }
        elseif cls == Code.CodeTermSwitch then
            for _, case in ipairs(k.cases or {}) do out[#out + 1] = { dest = case.dest, args = case.args or {} } end
            out[#out + 1] = { dest = k.default_dest, args = k.default_args or {} }
        elseif cls == Code.CodeTermVariantSwitch then
            for _, case in ipairs(k.cases or {}) do out[#out + 1] = { dest = case.dest, args = case.args or {} } end
            out[#out + 1] = { dest = k.default_dest, args = k.default_args or {} }
        end
        return out
    end

    local function forwarded_value_to_block(block, args, value)
        for i, param in ipairs(block.params or {}) do
            if same_value_id(args[i], value) then return param.value end
        end
        return value
    end

    local function reaches_return_with_value(blocks, block, value, seen)
        if block == nil then return false end
        local key = block.id.text .. "\0" .. (value and value.text or "")
        seen = seen or {}
        if seen[key] then return false end
        seen[key] = true
        local term = block.term and block.term.kind or nil
        if pvm.classof(term) == Code.CodeTermReturn then
            return #(term.values or {}) == 1 and same_value_id(term.values[1], value)
        end
        for _, succ in ipairs(term_successors(block.term)) do
            local dest = blocks[succ.dest.text]
            if reaches_return_with_value(blocks, dest, forwarded_value_to_block(dest or {}, succ.args, value), seen) then return true end
        end
        return false
    end

    local function reaches_void_return(blocks, block, seen)
        if block == nil then return false end
        seen = seen or {}
        if seen[block.id.text] then return false end
        seen[block.id.text] = true
        local term = block.term and block.term.kind or nil
        if pvm.classof(term) == Code.CodeTermReturn then return #(term.values or {}) == 0 end
        for _, succ in ipairs(term_successors(block.term)) do
            if reaches_void_return(blocks, blocks[succ.dest.text], seen) then return true end
        end
        return false
    end

    local function function_returns_reduction(func, graph_loop, reduction)
        if graph_loop == nil or #(graph_loop.exits or {}) ~= 1 then return false end
        local blocks = block_index(func)
        local edge = graph_loop.exits[1]
        local from = blocks[edge.from.block.text]
        local exit = blocks[edge.to.block.text]
        if from == nil or exit == nil then return false end
        local ret = exit.term and exit.term.kind or nil
        if pvm.classof(ret) == Code.CodeTermReturn and #(ret.values or {}) == 1 then
            if same_value_id(ret.values[1], reduction.accumulator) then return true end
            for i, param in ipairs(exit.params or {}) do
                if same_value_id(ret.values[1], param.value) then
                    local args = term_args_to_dest(from.term, exit.id)
                    return args ~= nil and same_value_id(args[i], reduction.accumulator)
                end
            end
        end
        return reaches_return_with_value(blocks, exit, reduction.accumulator)
    end

    local function function_returns_void_from_loop(func, graph_loop)
        if graph_loop == nil or #(graph_loop.exits or {}) ~= 1 then return false end
        local blocks = block_index(func)
        local exit = blocks[graph_loop.exits[1].to.block.text]
        local ret = exit and exit.term and exit.term.kind or nil
        return pvm.classof(ret) == Code.CodeTermReturn and #(ret.values or {}) == 0 or reaches_void_return(blocks, exit)
    end

    local function lane_base_value(lane)
        local base = lane and lane.base or nil
        if pvm.classof(base) == Mem.MemBaseValue then return base.value end
        if pvm.classof(base) == Mem.MemBaseProjection then
            local inner = lane_base_value({ base = base.base })
            if inner ~= nil then return inner end
        end
        return nil
    end

    local function mem_stride_const(stride)
        local cls = pvm.classof(stride)
        if stride == Mem.MemStrideUnit then return 1 end
        if cls == Mem.MemStrideConstElems then return stride.elems end
        return nil
    end

    local function extent_len(extent)
        if pvm.classof(extent) == Mem.MemExtentElements then return extent.len end
        return nil
    end

    local function pattern_layout(pattern)
        local cls = pvm.classof(pattern)
        if pattern == Mem.MemAccessContiguous then return Stencil.StencilLayoutContiguous(1) end
        if cls == Mem.MemAccessStrided then return Stencil.StencilLayoutContiguous(pattern.stride_elems) end
        return nil
    end

    local function field_name_from_lane(ctx, lane)
        for _, access_id in ipairs(lane and lane.accesses or {}) do
            local access = ctx.mem_accesses and ctx.mem_accesses[access_id.text] or nil
            local place = access and access.place or nil
            while place ~= nil do
                local cls = pvm.classof(place)
                if cls == Code.CodePlaceField then
                    local field = place.field
                    return field and field.field_name or ("field_" .. tostring(place.offset or 0))
                elseif cls == Code.CodePlaceIndex then
                    place = place.base
                else
                    place = nil
                end
            end
        end
        return nil
    end

    local function lane_layout(ctx, lane)
        local object = ctx.mem_objects and lane and ctx.mem_objects[lane.object.text] or nil
        local base_value = lane_base_value(lane)
        local soa_contract = base_value and ctx.soa_contracts and ctx.func_id and ctx.soa_contracts[ctx.func_id.text .. "\0" .. base_value.text] or nil
        local function wrap_soa(layout)
            if soa_contract == nil or layout == nil then return layout end
            return Stencil.StencilLayoutSoAComponent(layout, soa_contract.record_ty, soa_contract.field_name, soa_contract.component_index)
        end
        if object ~= nil then
            local provenance = object.provenance
            local pcls = pvm.classof(provenance)
            if object.kind == Mem.MemObjectDerived and pcls == Mem.MemProvProjection and provenance.projection == Mem.MemProjectField then
                local parent = ctx.mem_objects and ctx.mem_objects[provenance.parent.text] or nil
                local parent_layout = lane_layout(ctx, {
                    object = provenance.parent,
                    base = lane and lane.base,
                    pattern = lane and lane.pattern,
                    accesses = lane and lane.accesses,
                })
                local record_ty = parent and parent.elem_ty or nil
                local field_name = field_name_from_lane(ctx, lane)
                if parent_layout ~= nil and record_ty ~= nil and field_name ~= nil then
                    return wrap_soa(Stencil.StencilLayoutFieldProjection(parent_layout, record_ty, field_name, provenance.byte_offset or 0))
                end
            end
            if object.kind == Mem.MemObjectView and pcls == Mem.MemProvView then
                if provenance.stride == nil then return nil end
                return wrap_soa(Stencil.StencilLayoutViewDescriptor(
                    provenance.view,
                    provenance.data,
                    extent_len(object.extent) or provenance.len,
                    provenance.stride,
                    mem_stride_const(object.stride)
                ))
            end
            if object.kind == Mem.MemObjectSlice and pcls == Mem.MemProvSlice then
                return wrap_soa(Stencil.StencilLayoutSliceDescriptor(
                    provenance.slice,
                    provenance.data,
                    extent_len(object.extent) or provenance.len
                ))
            end
            if object.kind == Mem.MemObjectByteSpan and pcls == Mem.MemProvByteSpan then
                return wrap_soa(Stencil.StencilLayoutByteSpanDescriptor(
                    provenance.span,
                    provenance.data,
                    extent_len(object.extent) or provenance.len
                ))
            end
        end
        return wrap_soa(pattern_layout(lane and lane.pattern))
    end

    local function layout_data_value(layout)
        local cls = pvm.classof(layout)
        if cls == Stencil.StencilLayoutAffine1D or cls == Stencil.StencilLayoutAffineND then return layout_data_value(layout.parent) end
        if cls == Stencil.StencilLayoutSoAComponent or cls == Stencil.StencilLayoutFieldProjection then return layout_data_value(layout.parent) end
        if cls == Stencil.StencilLayoutViewDescriptor or cls == Stencil.StencilLayoutSliceDescriptor or cls == Stencil.StencilLayoutByteSpanDescriptor then return layout.data end
        return nil
    end

    local function binding_index(body)
        local out = {}
        for _, binding in ipairs(body and body.bindings or {}) do out[binding.id.text] = binding end
        return out
    end

    local function same_code_type(a, b)
        if a == b then return true end
        local ac, bc = pvm.classof(a), pvm.classof(b)
        if ac ~= bc then return false end
        if ac == Code.CodeTyInt then return a.bits == b.bits and a.signedness == b.signedness end
        if ac == Code.CodeTyFloat then return a.bits == b.bits end
        return false
    end

    local function primary_induction(loop_fact)
        for _, induction in ipairs(loop_fact and loop_fact.inductions or {}) do
            if induction.kind == Flow.FlowPrimaryInduction then return induction.value end
        end
        return nil
    end

    local function loop_aliases(ctx, graph_loop)
        if graph_loop == nil then return nil end
        ctx.loop_alias_cache = ctx.loop_alias_cache or {}
        if ctx.loop_alias_cache[graph_loop.id.text] ~= nil then return ctx.loop_alias_cache[graph_loop.id.text] end
        local loop_blocks = {}
        for _, block in ipairs(graph_loop.body or {}) do loop_blocks[block.block.text] = true end
        local latch = graph_loop.latches and graph_loop.latches[1] or nil
        local aliases = {}
        local function canonical(value)
            local seen = {}
            while value ~= nil and aliases[value.text] ~= nil and not seen[value.text] do
                seen[value.text] = true
                value = aliases[value.text]
            end
            return value
        end
        local changed = true
        while changed do
            changed = false
            for _, fact in ipairs(ctx.flow and ctx.flow.edges or {}) do
                local edge = fact.edge
                if edge ~= latch and loop_blocks[edge.from.block.text] and loop_blocks[edge.to.block.text] then
                    for _, arg in ipairs(fact.args or {}) do
                        local src = canonical(arg.src)
                        if src ~= nil and aliases[arg.dst_param.text] ~= src then
                            aliases[arg.dst_param.text] = src
                            changed = true
                        end
                    end
                end
            end
        end
        ctx.loop_alias_cache[graph_loop.id.text] = aliases
        return aliases
    end

    local function canonical_loop_value(ctx, graph_loop, value)
        local aliases = loop_aliases(ctx, graph_loop)
        local seen = {}
        while value ~= nil and aliases ~= nil and aliases[value.text] ~= nil and not seen[value.text] do
            seen[value.text] = true
            value = aliases[value.text]
        end
        return value
    end

    local function same_loop_value(ctx, graph_loop, a, b)
        a = canonical_loop_value(ctx, graph_loop, a)
        b = canonical_loop_value(ctx, graph_loop, b)
        return a ~= nil and b ~= nil and a.text == b.text
    end

    local function expr_is_int_const(expr, raw)
        return pvm.classof(expr) == Value.ValueExprConst
            and pvm.classof(expr.const) == Code.CodeConstLiteral
            and pvm.classof(expr.const.literal) == Core.LitInt
            and tonumber(expr.const.literal.raw) == raw
    end

    local function expr_int_const(expr)
        if pvm.classof(expr) == Value.ValueExprConst
            and pvm.classof(expr.const) == Code.CodeConstLiteral
            and pvm.classof(expr.const.literal) == Core.LitInt then
            return tonumber(expr.const.literal.raw)
        end
        return nil
    end

    local function bound_algebra_expr(bindings, value)
        local binding = value and bindings and bindings["kval:" .. value.text] or nil
        if binding ~= nil and pvm.classof(binding.expr) == Kernel.KernelExprAlgebra then return binding.expr.expr end
        return nil
    end

    local function value_expr_from_code(ctx, value, seen)
        if value == nil then return nil end
        seen = seen or {}
        if seen[value.text] then return Value.ValueExprValue(value) end
        seen[value.text] = true
        local def = ctx.defs and ctx.defs[value.text] or nil
        local k = def and def.kind or nil
        local cls = pvm.classof(k)
        if cls == Code.CodeInstConst then return Value.ValueExprConst(k.const) end
        if cls == Code.CodeInstAlias then return value_expr_from_code(ctx, k.src, seen) end
        if cls == Code.CodeInstUnary then return Value.ValueExprUnary(k.op, value_expr_from_code(ctx, k.value, seen), k.ty) end
        if cls == Code.CodeInstCast then return Value.ValueExprCast(k.op, k.from, k.to, value_expr_from_code(ctx, k.value, seen)) end
        if cls == Code.CodeInstBinary then
            local a, b = value_expr_from_code(ctx, k.lhs, seen), value_expr_from_code(ctx, k.rhs, seen)
            if k.op == Core.BinAdd then return Value.ValueExprAdd(a, b, k.ty, k.semantics) end
            if k.op == Core.BinSub then return Value.ValueExprSub(a, b, k.ty, k.semantics) end
            if k.op == Core.BinMul then return Value.ValueExprMul(a, b, k.ty, k.semantics) end
            if k.op == Core.BinDiv then return Value.ValueExprDiv(a, b, k.ty, k.semantics) end
            if k.op == Core.BinRem then return Value.ValueExprRem(a, b, k.ty, k.semantics) end
            if k.op == Core.BinBitAnd or k.op == Core.BinBitOr or k.op == Core.BinBitXor
                or k.op == Core.BinShl or k.op == Core.BinLShr or k.op == Core.BinAShr then
                return Value.ValueExprBinary(k.op, a, b, k.ty, k.semantics)
            end
        end
        if cls == Code.CodeInstCompare then
            return Value.ValueExprCmp(k.op, k.operand_ty, value_expr_from_code(ctx, k.lhs, seen), value_expr_from_code(ctx, k.rhs, seen))
        end
        if cls == Code.CodeInstSelect then
            return Value.ValueExprSelect(value_expr_from_code(ctx, k.cond, seen), value_expr_from_code(ctx, k.then_value, seen), value_expr_from_code(ctx, k.else_value, seen))
        end
        return Value.ValueExprValue(value)
    end

    local function resolved_algebra_expr(ctx, expr, bindings, seen)
        if expr == nil then return nil end
        local cls = pvm.classof(expr)
        if cls == Value.ValueExprValue then
            seen = seen or {}
            if seen[expr.value.text] then return expr end
            seen[expr.value.text] = true
            return resolved_algebra_expr(ctx, bound_algebra_expr(bindings, expr.value) or value_expr_from_code(ctx, expr.value), bindings, seen)
        end
        return expr
    end

    local function value_expr_key(ctx, graph_loop, expr, bindings, seen)
        expr = resolved_algebra_expr(ctx, expr, bindings)
        if expr == nil then return "nil" end
        local cls = pvm.classof(expr)
        if cls == Value.ValueExprConst and pvm.classof(expr.const) == Code.CodeConstLiteral then
            local lit = expr.const.literal
            return "const:" .. tostring(pvm.classof(lit)) .. ":" .. tostring(lit and (lit.raw or lit.value))
        end
        if cls == Value.ValueExprValue then
            local v = canonical_loop_value(ctx, graph_loop, expr.value)
            return "value:" .. tostring(v and v.text)
        end
        if cls == Value.ValueExprCast then return value_expr_key(ctx, graph_loop, expr.value, bindings, seen) end
        if cls == Value.ValueExprUnary then return "unary:" .. tostring(expr.op) .. "(" .. value_expr_key(ctx, graph_loop, expr.value, bindings, seen) .. ")" end
        if cls == Value.ValueExprAdd or cls == Value.ValueExprSub or cls == Value.ValueExprMul or cls == Value.ValueExprDiv or cls == Value.ValueExprRem then
            return tostring(cls) .. "(" .. value_expr_key(ctx, graph_loop, expr.a, bindings, seen) .. "," .. value_expr_key(ctx, graph_loop, expr.b, bindings, seen) .. ")"
        end
        if cls == Value.ValueExprBinary then
            return "binary:" .. tostring(expr.op) .. "(" .. value_expr_key(ctx, graph_loop, expr.a, bindings, seen) .. "," .. value_expr_key(ctx, graph_loop, expr.b, bindings, seen) .. ")"
        end
        if cls == Value.ValueExprCmp then
            return "cmp:" .. tostring(expr.op) .. ":" .. value_expr_key(ctx, graph_loop, expr.a, bindings, seen) .. "," .. value_expr_key(ctx, graph_loop, expr.b, bindings, seen)
        end
        if cls == Value.ValueExprSelect then
            return "select:" .. value_expr_key(ctx, graph_loop, expr.cond, bindings, seen) .. "?"
                .. value_expr_key(ctx, graph_loop, expr.t, bindings, seen) .. ":"
                .. value_expr_key(ctx, graph_loop, expr.f, bindings, seen)
        end
        return tostring(expr)
    end

    local expr_is_primary
    expr_is_primary = function(ctx, expr, graph_loop, loop_fact, bindings, seen)
        local primary = primary_induction(loop_fact)
        if primary == nil or expr == nil then return false end
        seen = seen or {}
        if seen[expr] then return false end
        seen[expr] = true
        local cls = pvm.classof(expr)
        if cls == Value.ValueExprValue then
            if same_loop_value(ctx, graph_loop, expr.value, primary) then return true end
            return expr_is_primary(ctx, bound_algebra_expr(bindings, expr.value), graph_loop, loop_fact, bindings, seen)
        end
        if cls == Value.ValueExprCast or cls == Value.ValueExprUnary then
            return expr_is_primary(ctx, expr.value, graph_loop, loop_fact, bindings, seen)
        end
        if cls == Value.ValueExprMul then
            return (expr_is_int_const(expr.a, 1) and expr_is_primary(ctx, expr.b, graph_loop, loop_fact, bindings, seen))
                or (expr_is_int_const(expr.b, 1) and expr_is_primary(ctx, expr.a, graph_loop, loop_fact, bindings, seen))
        end
        if cls == Value.ValueExprAdd then
            return (expr_is_int_const(expr.a, 0) and expr_is_primary(ctx, expr.b, graph_loop, loop_fact, bindings, seen))
                or (expr_is_int_const(expr.b, 0) and expr_is_primary(ctx, expr.a, graph_loop, loop_fact, bindings, seen))
        end
        return false
    end

    local function reverse_affine_offset(ctx, expr, graph_loop, loop_fact, bindings)
        local counted = loop_fact and loop_fact.counted or nil
        if counted == nil then return nil end
        local function strip_casts(v)
            v = resolved_algebra_expr(ctx, v, bindings)
            while v ~= nil and pvm.classof(v) == Value.ValueExprCast do
                v = resolved_algebra_expr(ctx, v.value, bindings)
            end
            return v
        end
        expr = strip_casts(expr)
        if expr == nil then return nil end
        if pvm.classof(expr) == Value.ValueExprMul then
            if expr_is_int_const(expr.a, 1) then expr = strip_casts(expr.b) end
            if expr_is_int_const(expr.b, 1) then expr = strip_casts(expr.a) end
        end
        if expr == nil then return nil end
        if pvm.classof(expr) ~= Value.ValueExprSub then return nil end
        if not expr_is_primary(ctx, expr.b, graph_loop, loop_fact, bindings) then return nil end
        local start_expr = value_expr_from_code(ctx, counted.start)
        if value_expr_key(ctx, graph_loop, expr.a, bindings) ~= value_expr_key(ctx, graph_loop, start_expr, bindings) then return nil end
        return expr.a
    end

    local function index_const_expr(n)
        return Value.ValueExprConst(Code.CodeConstLiteral(Code.CodeTyIndex, Core.LitInt(tostring(n))))
    end

    local function producer_shape_for_loop(ctx, loop_fact)
        local producer_fact = ctx and ctx.producer_facts and loop_fact and loop_fact.domain and ctx.producer_facts[flow_domain_key(loop_fact.domain)] or nil
        return producer_fact and producer_fact.producer and StencilArtifactPlan.producer_shape(producer_fact.producer) or nil
    end

    local function axis_expr_candidates(ctx, graph_loop, shape, bindings)
        local out = {}
        for axis_i, axis in ipairs(shape and shape.axes or {}) do
            local name = axis.index_name
            if name ~= nil then
                local candidates = {}
                local pat = "dsl_" .. tostring(name) .. "_"
                for text in pairs(ctx.defs or {}) do
                    if tostring(text):find(pat, 1, true) then
                        local expr = value_expr_from_code(ctx, Code.CodeValueId(text))
                        if expr ~= nil then candidates[#candidates + 1] = expr end
                    end
                end
                out[axis_i] = candidates
            end
        end
        return out
    end

    local function affine_nd_layout_for_index(ctx, expr, graph_loop, loop_fact, bindings, parent_layout)
        local shape = producer_shape_for_loop(ctx, loop_fact)
        if pvm.classof(shape) ~= Stencil.StencilProduceRangeND then return nil end
        local axis_candidates = axis_expr_candidates(ctx, graph_loop, shape, bindings)
        local function strip(v)
            v = resolved_algebra_expr(ctx, v, bindings)
            while pvm.classof(v) == Value.ValueExprCast do v = resolved_algebra_expr(ctx, v.value, bindings) end
            if pvm.classof(v) == Value.ValueExprMul then
                if expr_is_int_const(v.a, 1) then return strip(v.b) end
                if expr_is_int_const(v.b, 1) then return strip(v.a) end
            end
            return v
        end
        local function axis_index(v)
            v = strip(v)
            for i, candidates in pairs(axis_candidates) do
                for _, candidate in ipairs(candidates) do
                    if value_expr_key(ctx, graph_loop, v, bindings) == value_expr_key(ctx, graph_loop, candidate, bindings) then return i end
                end
            end
            return nil
        end
        local terms = {}
        local function add_term(axis_i, coeff)
            terms[axis_i] = (terms[axis_i] or 0) + coeff
        end
        local function walk(v, sign)
            v = strip(v)
            local c = expr_int_const(v)
            if c ~= nil then return c * sign end
            local ai = axis_index(v)
            if ai ~= nil then add_term(ai, sign); return 0 end
            local cls = pvm.classof(v)
            if cls == Value.ValueExprAdd then return walk(v.a, sign) + walk(v.b, sign) end
            if cls == Value.ValueExprSub then return walk(v.a, sign) + walk(v.b, -sign) end
            if cls == Value.ValueExprMul then
                local ca, cb = expr_int_const(strip(v.a)), expr_int_const(strip(v.b))
                if ca ~= nil then
                    local bi = axis_index(v.b)
                    if bi ~= nil then add_term(bi, sign * ca); return 0 end
                end
                if cb ~= nil then
                    local ai2 = axis_index(v.a)
                    if ai2 ~= nil then add_term(ai2, sign * cb); return 0 end
                end
            end
            return nil
        end
        local offset = walk(expr, 1)
        if offset == nil then return nil end
        local list = {}
        for axis_i = 1, #(shape.axes or {}) do
            local coeff = terms[axis_i]
            if coeff ~= nil and coeff ~= 0 then
                list[#list + 1] = Stencil.StencilAffineAxisTerm(Stencil.StencilAxisRef(axis_i), index_const_expr(coeff))
            end
        end
        if #list == 0 then return nil end
        return Stencil.StencilLayoutAffineND(parent_layout, list, offset ~= 0 and index_const_expr(offset) or nil)
    end

    local function is_zero_const(expr)
        return pvm.classof(expr) == Value.ValueExprConst
            and pvm.classof(expr.const) == Code.CodeConstLiteral
            and pvm.classof(expr.const.literal) == Core.LitInt
            and tonumber(expr.const.literal.raw) == 0
    end

    local function is_minus_one_const(expr)
        return pvm.classof(expr) == Value.ValueExprConst
            and pvm.classof(expr.const) == Code.CodeConstLiteral
            and pvm.classof(expr.const.literal) == Core.LitInt
            and tonumber(expr.const.literal.raw) == -1
    end

    local function classify_store_expr(expr, bindings, seen)
        return StencilRules.classify_expr(expr, bindings or {}, seen)
    end

    local function single_store_effect(body)
        local store = nil
        for _, effect in ipairs(body and body.effects or {}) do
            local cls = pvm.classof(effect)
            if cls == Kernel.KernelEffectStore then
                if store ~= nil then return nil, "multiple stores in kernel" end
                store = effect
            elseif cls ~= Kernel.KernelEffectFold then
                return nil, "non-store effect in kernel"
            end
        end
        if store == nil then return nil, "kernel has no store effect" end
        return store, nil
    end

    local function index_lane_for(expr, bindings)
        local class, class_err = StencilRules.classify_expr(Kernel.KernelExprAlgebra(expr), bindings)
        if class == nil then return nil, class_err end
        return StencilRules:run("select_index_lane", { class = class }, "lane", "expression is not an index lane")
    end

    local function lane_selection_fact(ctx, lane)
        local layout = lane_layout(ctx, lane)
        if layout == nil then return nil end
        local base = lane_base_value(lane)
        local tcls = pvm.classof(layout)
        base = layout_data_value(layout) or base
        if base == nil then return nil end
        return {
            base = base,
            base_expr = value_id_expr(ctx, base),
            elem_ty = lane.elem_ty,
            layout = layout,
        }
    end

    local function enrich_lane_class(ctx, class, graph_loop, loop_fact, bindings, prefix)
        local lane = class[prefix]
        local index = class[prefix .. "_index"] or class.index
        local fact = lane_selection_fact(ctx, lane)
        if fact == nil then return nil, prefix .. " lane has no value base" end
        if prefix == "lane" then
            class.src = fact.base
            class.src_expr = fact.base_expr
            class.elem_ty = fact.elem_ty
            class.src_layout = fact.layout
            class.index_primary = expr_is_primary(ctx, index, graph_loop, loop_fact, bindings)
            if not class.index_primary then
                local idx = index_lane_for(index, bindings)
                if idx ~= nil then
                    local idx_fact = lane_selection_fact(ctx, idx.lane)
                    if idx_fact ~= nil then
                        class.index_lane = {
                            base = idx_fact.base,
                            base_expr = idx_fact.base_expr,
                            elem_ty = idx_fact.elem_ty,
                            layout = idx_fact.layout,
                            index_primary = expr_is_primary(ctx, idx.index, graph_loop, loop_fact, bindings),
                        }
                    end
                end
            end
        else
            class[prefix .. "_base"] = fact.base
            class[prefix .. "_expr"] = fact.base_expr
            class[prefix .. "_ty"] = fact.elem_ty
            class[prefix .. "_layout"] = fact.layout
            class[prefix .. "_index_primary"] = expr_is_primary(ctx, index, graph_loop, loop_fact, bindings)
        end
        return class
    end

    local function enrich_apply_n_class(ctx, class, graph_loop, loop_fact, bindings)
        local producer_fact = ctx and ctx.producer_facts and loop_fact and loop_fact.domain and ctx.producer_facts[flow_domain_key(loop_fact.domain)] or nil
        local producer_shape = producer_fact and producer_fact.producer and StencilArtifactPlan.producer_shape(producer_fact.producer) or nil
        local window_1d = producer_shape ~= nil and pvm.classof(producer_shape) == Stencil.StencilProduceWindowND and #(producer_shape.axes or {}) == 1
        local function strip_casts(expr)
            expr = resolved_algebra_expr(ctx, expr, bindings)
            if expr ~= nil and pvm.classof(expr) == Value.ValueExprValue then
                expr = value_expr_from_code(ctx, expr.value) or expr
            end
            while expr ~= nil and pvm.classof(expr) == Value.ValueExprCast do expr = resolved_algebra_expr(ctx, expr.value, bindings) end
            return expr
        end
        local function window_offset_for_index(index)
            if not window_1d then return nil end
            local expr = strip_casts(index)
            if expr == nil then return nil end
            if pvm.classof(expr) == Value.ValueExprMul then
                if expr_int_const(strip_casts(expr.a)) ~= nil then expr = strip_casts(expr.b)
                elseif expr_int_const(strip_casts(expr.b)) ~= nil then expr = strip_casts(expr.a) end
            end
            if expr == nil then return nil end
            if expr_is_primary(ctx, expr, graph_loop, loop_fact, bindings) then return 0 end
            local cls = pvm.classof(expr)
            if cls == Value.ValueExprAdd then
                local c = expr_int_const(strip_casts(expr.a))
                if c ~= nil and expr_is_primary(ctx, expr.b, graph_loop, loop_fact, bindings) then return c end
                c = expr_int_const(strip_casts(expr.b))
                if c ~= nil and expr_is_primary(ctx, expr.a, graph_loop, loop_fact, bindings) then return c end
            elseif cls == Value.ValueExprSub then
                local c = expr_int_const(strip_casts(expr.b))
                if c ~= nil and expr_is_primary(ctx, expr.a, graph_loop, loop_fact, bindings) then return -c end
                c = expr_int_const(strip_casts(expr.a))
                if c ~= nil and expr_is_primary(ctx, expr.b, graph_loop, loop_fact, bindings) then return nil end
            end
            return nil
        end
        local window_by_input = {}
        for _, input in ipairs(class.inputs or {}) do
            if input.scalar_value ~= nil then
                input.index_primary = true
            else
                local fact = lane_selection_fact(ctx, input.lane)
                if fact == nil then return nil, input.name .. " lane has no value base" end
                input.base = fact.base
                input.base_expr = fact.base_expr
                input.ty = fact.elem_ty
                input.layout = fact.layout
                input.index_primary = expr_is_primary(ctx, input.index, graph_loop, loop_fact, bindings)
                if not input.index_primary then
                    local affine_layout = affine_nd_layout_for_index(ctx, input.index, graph_loop, loop_fact, bindings, input.layout)
                    if affine_layout ~= nil then
                        input.layout = affine_layout
                        input.index_primary = true
                    end
                end
                if not input.index_primary then
                    local offset = window_offset_for_index(input.index)
                    if offset ~= nil then
                        input.index_primary = true
                        input.window_offsets = { Stencil.StencilWindowOffset(Stencil.StencilAxisRef(1), offset) }
                        window_by_input[input.name] = input.window_offsets
                    end
                end
                if not input.index_primary then
                    local idx = index_lane_for(input.index, bindings)
                    if idx ~= nil then
                        local idx_fact = lane_selection_fact(ctx, idx.lane)
                        if idx_fact ~= nil then
                            input.index_lane = {
                                name = input.name .. "_idx",
                                base = idx_fact.base,
                                base_expr = idx_fact.base_expr,
                                elem_ty = idx_fact.elem_ty,
                                ty = idx_fact.elem_ty,
                                layout = idx_fact.layout,
                                role = Stencil.StencilAccessIndex,
                                index_primary = expr_is_primary(ctx, idx.index, graph_loop, loop_fact, bindings),
                            }
                        end
                    end
                end
            end
        end
        local rewrite_expr
        rewrite_expr = function(expr)
            local cls = pvm.classof(expr)
            if cls == Stencil.StencilApplyInput then
                local offsets = window_by_input[expr.access.name]
                if offsets ~= nil then return Stencil.StencilApplyWindowInput(expr.access, offsets) end
                return expr
            end
            if cls == Stencil.StencilApplyUnary then return Stencil.StencilApplyUnary(expr.op, rewrite_expr(expr.arg), expr.result_ty, expr.int_semantics, expr.float_mode) end
            if cls == Stencil.StencilApplyBinary then return Stencil.StencilApplyBinary(expr.op, rewrite_expr(expr.left), rewrite_expr(expr.right), expr.result_ty, expr.int_semantics, expr.float_mode) end
            if cls == Stencil.StencilApplyCast then return Stencil.StencilApplyCast(expr.op, rewrite_expr(expr.arg), expr.from, expr.to) end
            if cls == Stencil.StencilApplyPredicate then return Stencil.StencilApplyPredicate(expr.pred, rewrite_expr(expr.arg), expr.result_ty) end
            if cls == Stencil.StencilApplyCompare then return Stencil.StencilApplyCompare(expr.cmp, rewrite_expr(expr.left), rewrite_expr(expr.right), expr.result_ty) end
            if cls == Stencil.StencilApplySelect then return Stencil.StencilApplySelect(expr.pred, rewrite_expr(expr.cond), rewrite_expr(expr.then_expr), rewrite_expr(expr.else_expr), expr.result_ty) end
            return expr
        end
        if next(window_by_input) ~= nil then class.expr = rewrite_expr(class.expr) end
        return class
    end

    local function enrich_stencil_class(ctx, class, graph_loop, loop_fact, bindings, dst_base, dst_ty)
        if class.kind == "apply_n" then
            local ok, err = enrich_apply_n_class(ctx, class, graph_loop, loop_fact, bindings)
            if not ok then return nil, err end
        elseif class.kind == "load" or class.kind == "map" or class.kind == "cast" or class.kind == "compare" then
            local ok, err = enrich_lane_class(ctx, class, graph_loop, loop_fact, bindings, "lane")
            if not ok then return nil, err end
            if class.kind == "map" then
                class.same_src_dst_ty = class.src == dst_base and same_code_type(class.elem_ty, dst_ty)
            end
        elseif class.kind == "zip_map" or class.kind == "zip_compare" then
            local ok, err = enrich_lane_class(ctx, class, graph_loop, loop_fact, bindings, "lhs")
            if not ok then return nil, err end
            ok, err = enrich_lane_class(ctx, class, graph_loop, loop_fact, bindings, "rhs")
            if not ok then return nil, err end
        elseif class.kind == "fill" then
            class.value_expr = value_expr(ctx, class.value)
        end
        return class
    end

    local function enriched_class_for_expr(ctx, expr, graph_loop, loop_fact, bindings, dst_base, dst_ty)
        local classified, reason = classify_store_expr(expr, bindings)
        if classified == nil then return nil, reason end
        return enrich_stencil_class(ctx, classified, graph_loop, loop_fact, bindings, dst_base, dst_ty)
    end

    local function index_lane_selection_fact(ctx, expr, graph_loop, loop_fact, bindings)
        local idx = index_lane_for(expr, bindings)
        if idx == nil then return nil end
        local fact = lane_selection_fact(ctx, idx.lane)
        if fact == nil then return nil end
        return {
            base = fact.base,
            base_expr = fact.base_expr,
            elem_ty = fact.elem_ty,
            index_primary = expr_is_primary(ctx, idx.index, graph_loop, loop_fact, bindings),
        }
    end

    local function producer_from_loop(ctx, loop_fact, step_num)
        local counted = loop_fact and loop_fact.counted or nil
        if counted == nil then return nil end
        local producer_fact = ctx and ctx.producer_facts and ctx.producer_facts[flow_domain_key(loop_fact.domain)] or nil
        if producer_fact ~= nil then return producer_fact.producer end
        return Stencil.StencilProducer(
            loop_fact.domain,
            Stencil.StencilProduceRange1D(
                Code.CodeTyIndex,
                Value.ValueExprValue(counted.start),
                Value.ValueExprValue(counted.stop),
                step_num,
                Stencil.StencilProducerForward
            )
        )
    end

    local function same_value_expr_value(expr, value)
        return pvm.classof(expr) == Value.ValueExprValue and value ~= nil and expr.value.text == value.text
    end

    local function scan_axis_from_loop(ctx, loop_fact, producer)
        if producer == nil or loop_fact == nil or loop_fact.counted == nil then return nil end
        local shape = StencilArtifactPlan.producer_shape(producer)
        if pvm.classof(shape) ~= Stencil.StencilProduceRangeND then return nil end
        local counted = loop_fact.counted
        for axis_index, axis in ipairs(shape.axes or {}) do
            if same_value_expr_value(axis.start, counted.start) and same_value_expr_value(axis.stop, counted.stop) then
                return Stencil.StencilAxisRef(axis_index)
            end
        end
        return nil
    end

    local function stencil_store_plan(ctx, func, plan, graph_loop, loop_fact)
        if pvm.classof(plan) ~= Kernel.KernelPlanned then return nil, "kernel is not planned" end
        if not function_returns_void_from_loop(func, graph_loop) then return nil, "store stencil requires loop exit to return void" end
        if loop_fact == nil or loop_fact.counted == nil then return nil, "store stencil requires counted loop" end
        local step_num = const_int_value(ctx, loop_fact.counted.step)
        if step_num == nil or step_num == 0 then return nil, "store stencil requires a non-zero constant step" end
        local descriptor_step = math.abs(step_num)
        local store, store_reason = single_store_effect(plan.body)
        if store == nil then return nil, store_reason end
        local dst_base = lane_base_value(store.dst)
        if dst_base == nil then return nil, "store destination lane has no value base" end
        local dst_fact = lane_selection_fact(ctx, store.dst)
        local bindings = binding_index(plan.body)
        local classified, reason = classify_store_expr(store.value, bindings)
        if classified == nil then return nil, reason end
        local start_expr, stop_expr = value_id_expr(ctx, loop_fact.counted.start), value_id_expr(ctx, loop_fact.counted.stop)
        local dst_expr = value_id_expr(ctx, dst_base)
        local store_index_is_primary = expr_is_primary(ctx, store.index, graph_loop, loop_fact, bindings)
        local dst_layout = dst_fact and dst_fact.layout or nil
        if not store_index_is_primary and dst_layout ~= nil then
            local offset = reverse_affine_offset(ctx, store.index, graph_loop, loop_fact, bindings)
            if offset ~= nil then
                dst_layout = Stencil.StencilLayoutAffine1D(dst_layout, -1, offset)
                store_index_is_primary = true
            end
        end
        if not store_index_is_primary and dst_layout ~= nil then
            local affine_layout = affine_nd_layout_for_index(ctx, store.index, graph_loop, loop_fact, bindings, dst_layout)
            if affine_layout ~= nil then
                dst_layout = affine_layout
                store_index_is_primary = true
            end
        end
        local class, class_reason = enrich_stencil_class(ctx, classified, graph_loop, loop_fact, bindings, dst_base, store.dst.elem_ty)
        if class == nil then return nil, class_reason end
        local selection_ctx = {
            producer = producer_from_loop(ctx, loop_fact, descriptor_step),
            step_num = descriptor_step,
            dst_elem_ty = store.dst.elem_ty,
            dst = dst_base,
            dst_expr = dst_expr,
            dst_layout = dst_layout,
            start = loop_fact.counted.start,
            stop = loop_fact.counted.stop,
            start_expr = start_expr,
            stop_expr = stop_expr,
            store_index_primary = store_index_is_primary,
            store_index_lane = store_index_is_primary and nil or index_lane_selection_fact(ctx, store.index, graph_loop, loop_fact, bindings),
            scatter_conflicts = Stencil.StencilScatterUniqueIndices,
            class = class,
        }
        local stencil_plan, select_reason = StencilRules.plan_store {
            planned = pvm.classof(plan) == Kernel.KernelPlanned,
            returns_void = function_returns_void_from_loop(func, graph_loop),
            counted_positive = step_num ~= nil and step_num ~= 0,
            single_store = store ~= nil,
            dst_base_present = dst_base ~= nil,
            class_ready = class ~= nil,
            selection_ctx = selection_ctx,
        }
        if stencil_plan == nil then return nil, select_reason end
        return { selection = stencil_plan.selection }, nil
    end

    local function dynamic_stride_layout(layout)
        local cls = pvm.classof(layout)
        if cls == Stencil.StencilLayoutFieldProjection then return dynamic_stride_layout(layout.parent) end
        if cls == Stencil.StencilLayoutSoAComponent then return dynamic_stride_layout(layout.parent) end
        if cls == Stencil.StencilLayoutAffine1D or cls == Stencil.StencilLayoutAffineND then return dynamic_stride_layout(layout.parent) end
        if cls == Stencil.StencilLayoutViewDescriptor and layout.stride_const == nil then return layout end
        return nil
    end

    local function dynamic_affine_offset_layout(layout)
        local cls = pvm.classof(layout)
        if cls == Stencil.StencilLayoutFieldProjection then return dynamic_affine_offset_layout(layout.parent) end
        if cls == Stencil.StencilLayoutSoAComponent then return dynamic_affine_offset_layout(layout.parent) end
        if cls == Stencil.StencilLayoutIndexed then return dynamic_affine_offset_layout(layout.parent) end
        if cls == Stencil.StencilLayoutAffine1D and layout.offset ~= nil then return layout end
        if cls == Stencil.StencilLayoutAffineND and layout.offset ~= nil then return layout end
        return nil
    end

    local function access_arg_value(info, name)
        if info == nil or name == nil then return nil end
        if name == "dst" then return info.dst end
        if name == "xs" then return info.array or info.src or info.xs end
        if name == "src" then return info.src or info.array end
        if name == "lhs" then return info.lhs end
        if name == "rhs" then return info.rhs end
        if name == "idx" then return info.index or info.idx end
        if name == "cond" then return info.cond end
        if name == "then_xs" then return info.then_xs or info.then_base end
        if name == "else_xs" then return info.else_xs or info.else_base end
        for _, input in ipairs(info.inputs or {}) do
            if input.name == name then return input.base end
        end
        return info[name]
    end

    local function append_access_args(ctx, desc, info, out)
        for _, access in ipairs(StencilArtifactPlan.descriptor_accesses(desc)) do
            if pvm.classof(access.layout) ~= Stencil.StencilLayoutScalar then
                local role = access.role
                if role == Stencil.StencilAccessRead or role == Stencil.StencilAccessWrite or role == Stencil.StencilAccessReadWrite or role == Stencil.StencilAccessIndex then
                    local id = access_arg_value(info, access.name)
                    if id ~= nil then out[#out + 1] = value_id_expr(ctx, id) end
                end
            end
        end
    end

    local function append_producer_args(ctx, producer, out, fallback)
        local shape = StencilArtifactPlan.producer_shape(producer)
        local cls = pvm.classof(shape)
        if cls == Stencil.StencilProduceRange1D then
            out[#out + 1] = shape.start and producer_value_expr(ctx, shape.start) or assert(fallback and fallback.start_expr, "Range1D producer call is missing start")
            out[#out + 1] = shape.stop and producer_value_expr(ctx, shape.stop) or assert(fallback and fallback.stop_expr, "Range1D producer call is missing stop")
            return
        end
        if cls == Stencil.StencilProduceRangeND or cls == Stencil.StencilProduceWindowND or cls == Stencil.StencilProduceTiledND then
            for _, axis in ipairs(shape.axes or {}) do
                out[#out + 1] = assert(axis.start and producer_value_expr(ctx, axis.start), "ND producer call is missing axis start")
                out[#out + 1] = assert(axis.stop and producer_value_expr(ctx, axis.stop), "ND producer call is missing axis stop")
            end
            return
        end
        error("luajit_lower: unsupported stencil producer call shape " .. class_name(shape), 3)
    end

    local function append_trailing_scalar_args(ctx, desc, info, out)
        for _, access in ipairs(StencilArtifactPlan.descriptor_accesses(desc)) do
            if pvm.classof(access.layout) == Stencil.StencilLayoutScalar and access.role == Stencil.StencilAccessRead then
                local init = access.layout.value or (info and info.value)
                if init ~= nil then out[#out + 1] = value_expr(ctx, init) end
            end
        end
        local sink = desc.sink
        local sink_cls = pvm.classof(sink)
        if sink_cls == Stencil.StencilSinkScan then
            out[#out + 1] = value_expr(ctx, assert(info and info.init, "scan stencil call is missing init"))
        elseif sink_cls == Stencil.StencilSinkReduce then
            local scope = sink.scope
            local scope_cls = pvm.classof(scope)
            local domain_scope = scope == Stencil.StencilReduceScopeDomain or scope_cls == Stencil.StencilReduceScopeDomain
            if domain_scope and pvm.classof(sink.mode) == Stencil.StencilReduceFold then
                out[#out + 1] = value_expr(ctx, assert(info and info.init, "reduce stencil call is missing init"))
            end
        end
    end

    local function stencil_args(ctx, artifact, selection)
        local out = {}
        local desc = artifact and artifact.instance and artifact.instance.descriptor or nil
        local info = selection and selection.info or nil
        if desc ~= nil and info ~= nil then
            append_access_args(ctx, desc, info, out)
            append_producer_args(ctx, desc.producer, out, info)
            append_trailing_scalar_args(ctx, desc, info, out)
        else
            local args = selection and selection.args or selection
            for i = 1, #(args or {}) do out[i] = args[i] end
        end
        for _, access in ipairs(StencilArtifactPlan.descriptor_accesses(desc)) do
            local top = dynamic_stride_layout(access.layout)
            if top ~= nil then
                out[#out + 1] = value_id_expr(ctx, top.stride)
            end
        end
        for _, access in ipairs(StencilArtifactPlan.descriptor_accesses(desc)) do
            local top = dynamic_affine_offset_layout(access.layout)
            if top ~= nil then
                out[#out + 1] = producer_value_expr(ctx, top.offset)
            end
        end
        return out
    end

    local function lower_kernel_stencil_store(ctx, func, plan, graph_loop, loop_fact, opts)
        if opts.stencil_store_artifact_for == nil then return nil, "no store stencil artifact provider" end
        local planned, reason = stencil_store_plan(ctx, func, plan, graph_loop, loop_fact)
        if planned == nil then return nil, reason end
        local selection = planned.selection
        local artifact = opts.stencil_store_artifact_for(func, selection.kind or selection.vocab, selection.op, plan, selection.info)
        if artifact == nil then return nil, "store stencil artifact provider did not select an artifact" end
        local id = LJ.LJMachineId("machine:" .. sanitize(func.name) .. ":stencil_store:" .. sanitize(loop_fact.loop.text))
        return LJ.LJMachine(id, LJ.LJMachineStencilEffect(artifact, stencil_args(ctx, artifact, selection)), nil, LJ.LJStateScalar, LJ.LJTraceHot), nil
    end

    local function plan_kernel_stencil_store(ctx, func, plan, graph_loop, loop_fact, opts)
        return lower_kernel_stencil_store(ctx, func, plan, graph_loop, loop_fact, opts)
    end

    local function select_reduction_artifact(opts, func, vocab, op, reduction, plan, info)
        if opts.stencil_reduce_artifact_for ~= nil then return opts.stencil_reduce_artifact_for(func, vocab, op, reduction, plan, info) end
        return nil
    end

    local function stencil_reduce_plan(ctx, func, plan, graph_loop, loop_fact)
        if pvm.classof(plan) ~= Kernel.KernelPlanned then return nil, "kernel is not planned" end
        local result = plan.body.result
        if pvm.classof(result) ~= Kernel.KernelResultReduction then return nil, "kernel result is not a reduction" end
        local reduction = result.reduction
        if not function_returns_reduction(func, graph_loop, reduction) then return nil, "function return is not the kernel reduction" end
        if loop_fact == nil or loop_fact.counted == nil then return nil, "reduction stencil requires counted loop" end
        local step_num = const_int_value(ctx, loop_fact.counted.step)
        if step_num == nil or step_num == 0 then return nil, "reduction stencil requires a non-zero constant step" end
        local descriptor_step = math.abs(step_num)
        local classified, reason = classify_store_expr(Kernel.KernelExprAlgebra(reduction.contribution), binding_index(plan.body))
        if classified == nil then return nil, reason end
        local start_expr, stop_expr = value_id_expr(ctx, loop_fact.counted.start), value_id_expr(ctx, loop_fact.counted.stop)
        local init_expr = value_expr(ctx, reduction.init)
        local class, class_reason = enrich_stencil_class(ctx, classified, graph_loop, loop_fact, binding_index(plan.body), nil, nil)
        if class == nil then return nil, class_reason end
        local i32 = Code.CodeTyInt(32, Code.CodeSigned)
        local selection_ctx = {
            step_num = descriptor_step,
            producer = producer_from_loop(ctx, loop_fact, descriptor_step),
            result_ty = reduction.ty,
            init = reduction.init,
            init_expr = init_expr,
            start = loop_fact.counted.start,
            stop = loop_fact.counted.stop,
            start_expr = start_expr,
            stop_expr = stop_expr,
            reduction_kind = reduction.kind,
            reduction_add = reduction.kind == Value.ReductionAdd,
            init_zero = is_zero_const(reduction.init),
            result_i32 = same_code_type(reduction.ty, i32),
            class = class,
        }
        local stencil_plan, select_reason = StencilRules.plan_reduce {
            planned = pvm.classof(plan) == Kernel.KernelPlanned,
            result_reduction = pvm.classof(result) == Kernel.KernelResultReduction,
            returns_reduction = function_returns_reduction(func, graph_loop, reduction),
            counted_positive = step_num ~= nil and step_num ~= 0,
            class_ready = class ~= nil,
            reduction = reduction,
            selection_ctx = selection_ctx,
        }
        if stencil_plan == nil then return nil, select_reason end
        return { reduction = stencil_plan.reduction, selection = stencil_plan.selection }, nil
    end

    local function lower_kernel_stencil_reduce(ctx, func, plan, graph_loop, loop_fact, opts)
        if opts.stencil_reduce_artifact_for == nil then return nil, "no reduction stencil artifact provider" end
        local planned, reason = stencil_reduce_plan(ctx, func, plan, graph_loop, loop_fact)
        if planned == nil then return nil, reason end
        local reduction, selection = planned.reduction, planned.selection
        local artifact = select_reduction_artifact(opts, func, selection.kind or selection.vocab, selection.op, reduction, plan, selection.info)
        if artifact == nil then return nil, "reduction stencil artifact provider did not select an artifact" end
        local id = LJ.LJMachineId("machine:" .. sanitize(func.name) .. ":stencil_reduce:" .. sanitize(loop_fact.loop.text))
        return LJ.LJMachine(id, LJ.LJMachineStencilCall(artifact, stencil_args(ctx, artifact, selection), physical(ctx, reduction.ty)), physical(ctx, reduction.ty), LJ.LJStateScalar, LJ.LJTraceHot), nil
    end

    local function plan_kernel_stencil_reduce(ctx, func, plan, graph_loop, loop_fact, opts)
        return lower_kernel_stencil_reduce(ctx, func, plan, graph_loop, loop_fact, opts)
    end

    local function single_effect(body, wanted)
        local found = nil
        for _, effect in ipairs(body and body.effects or {}) do
            local cls = pvm.classof(effect)
            if cls == wanted then
                if found ~= nil then return nil, "multiple matching skeleton effects" end
                found = effect
            elseif cls ~= Kernel.KernelEffectFold then
                return nil, "non-skeleton effect in kernel"
            end
        end
        if found == nil then return nil, "missing skeleton effect" end
        return found, nil
    end

    local function kernel_plan_stencil_shaped(plan)
        if pvm.classof(plan) ~= Kernel.KernelPlanned then return false end
        local body = plan.body
        local result = body and body.result or nil
        if pvm.classof(result) == Kernel.KernelResultReduction
            or pvm.classof(result) == Kernel.KernelResultFind then
            return true
        end
        for _, effect in ipairs(body and body.effects or {}) do
            local cls = pvm.classof(effect)
            if cls == Kernel.KernelEffectStore
                or cls == Kernel.KernelEffectScan
                or cls == Kernel.KernelEffectPartition
                or cls == Kernel.KernelEffectCopy
                or cls == Kernel.KernelEffectScatterReduce then
                return true
            end
        end
        return false
    end

    local function select_skeleton_artifact(opts, func, vocab, op, reduction, plan, info)
        if opts.stencil_skeleton_artifact_for ~= nil then return opts.stencil_skeleton_artifact_for(func, vocab, op, reduction, plan, info) end
        return nil
    end

    local function run_stencil_selection(relation, fields, missing)
        return StencilRules:run(relation, { ctx = fields }, "selection", missing)
    end

    local function skeleton_scan_plan(ctx, func, plan, graph_loop, loop_fact)
        local effect, effect_reason = single_effect(plan.body, Kernel.KernelEffectScan)
        if effect == nil then return nil, effect_reason end
        local result = plan.body.result
        if pvm.classof(result) ~= Kernel.KernelResultReduction then return nil, "scan skeleton requires reduction result" end
        local reduction = effect.reduction
        if result.reduction ~= reduction then return nil, "scan result reduction does not match scan effect" end
        local returns_reduction = function_returns_reduction(func, graph_loop, reduction)
        if not returns_reduction and not function_returns_void_from_loop(func, graph_loop) then return nil, "scan loop exits as neither final value nor void effect" end
        local dst_base = lane_base_value(effect.dst)
        if dst_base == nil then return nil, "scan destination lane has no value base" end
        local dst_fact = lane_selection_fact(ctx, effect.dst)
        local bindings = binding_index(plan.body)
        local class, class_reason = enriched_class_for_expr(ctx, Kernel.KernelExprAlgebra(reduction.contribution), graph_loop, loop_fact, bindings, dst_base, effect.dst.elem_ty)
        if class == nil then return nil, class_reason end
        local start_expr, stop_expr = value_id_expr(ctx, loop_fact.counted.start), value_id_expr(ctx, loop_fact.counted.stop)
        local step_num = const_int_value(ctx, loop_fact.counted.step)
        if step_num == nil or step_num == 0 then return nil, "scan stencil requires a non-zero constant step" end
        local descriptor_step = math.abs(step_num)
        local dst_layout = dst_fact and dst_fact.layout or nil
        local store_index_is_primary = expr_is_primary(ctx, effect.index, graph_loop, loop_fact, bindings)
        if not store_index_is_primary and dst_layout ~= nil then
            local offset = reverse_affine_offset(ctx, effect.index, graph_loop, loop_fact, bindings)
            if offset ~= nil then
                dst_layout = Stencil.StencilLayoutAffine1D(dst_layout, -1, offset)
                store_index_is_primary = true
            end
        end
        if not store_index_is_primary and dst_layout ~= nil then
            local affine_layout = affine_nd_layout_for_index(ctx, effect.index, graph_loop, loop_fact, bindings, dst_layout)
            if affine_layout ~= nil then
                dst_layout = affine_layout
                store_index_is_primary = true
            end
        end
        local producer = producer_from_loop(ctx, loop_fact, descriptor_step)
        local selection, select_reason = run_stencil_selection("select_scan_stencil", {
            step_num = descriptor_step,
            producer = producer,
            dst_elem_ty = effect.dst.elem_ty,
            result_ty = reduction.ty,
            dst = dst_base,
            dst_expr = value_id_expr(ctx, dst_base),
            dst_layout = dst_layout,
            start = loop_fact.counted.start,
            stop = loop_fact.counted.stop,
            start_expr = start_expr,
            stop_expr = stop_expr,
            store_index_primary = store_index_is_primary,
            reduction = reduction,
            reduction_kind = reduction.kind,
            init = reduction.init,
            init_expr = value_expr(ctx, reduction.init),
            mode = effect.mode,
            axis = effect.axis or scan_axis_from_loop(ctx, loop_fact, producer),
            class = class,
        }, "unsupported scan stencil shape")
        if selection == nil then return nil, select_reason end
        return { kind = "scan", selection = selection, reduction = reduction, result_ty = returns_reduction and reduction.ty or nil }, nil
    end

    local function skeleton_find_plan(ctx, func, plan, graph_loop, loop_fact)
        local result = plan.body.result
        if pvm.classof(result) ~= Kernel.KernelResultFind then return nil, "kernel result is not find" end
        if graph_loop == nil then return nil, "find skeleton requires a graph loop" end
        local bindings = binding_index(plan.body)
        local class, class_reason = enriched_class_for_expr(ctx, result.src, graph_loop, loop_fact, bindings, nil, nil)
        if class == nil then return nil, class_reason end
        local step_num = const_int_value(ctx, loop_fact.counted.step)
        local selection, select_reason = run_stencil_selection("select_find_stencil", {
            step_num = step_num,
            producer = producer_from_loop(ctx, loop_fact, step_num),
            start = loop_fact.counted.start,
            stop = loop_fact.counted.stop,
            start_expr = value_id_expr(ctx, loop_fact.counted.start),
            stop_expr = value_id_expr(ctx, loop_fact.counted.stop),
            pred = result.pred,
            not_found_minus_one = is_minus_one_const(result.not_found),
            class = class,
        }, "unsupported find stencil shape")
        if selection == nil then return nil, select_reason end
        return { kind = "find", selection = selection, result_ty = Code.CodeTyInt(32, Code.CodeSigned) }, nil
    end

    local function skeleton_partition_plan(ctx, func, plan, graph_loop, loop_fact)
        local effect, effect_reason = single_effect(plan.body, Kernel.KernelEffectPartition)
        if effect == nil then return nil, effect_reason end
        local dst_base = lane_base_value(effect.dst)
        if dst_base == nil then return nil, "partition destination lane has no value base" end
        local dst_fact = lane_selection_fact(ctx, effect.dst)
        local bindings = binding_index(plan.body)
        local class, class_reason = enriched_class_for_expr(ctx, effect.src, graph_loop, loop_fact, bindings, dst_base, effect.dst.elem_ty)
        if class == nil then return nil, class_reason end
        local step_num = const_int_value(ctx, loop_fact.counted.step)
        local selection, select_reason = run_stencil_selection("select_partition_stencil", {
            step_num = step_num,
            producer = producer_from_loop(ctx, loop_fact, step_num),
            dst_elem_ty = effect.dst.elem_ty,
            dst = dst_base,
            dst_expr = value_id_expr(ctx, dst_base),
            dst_layout = dst_fact and dst_fact.layout or nil,
            start = loop_fact.counted.start,
            stop = loop_fact.counted.stop,
            start_expr = value_id_expr(ctx, loop_fact.counted.start),
            stop_expr = value_id_expr(ctx, loop_fact.counted.stop),
            store_index_primary = true,
            pred = effect.pred,
            semantics = effect.semantics,
            class = class,
        }, "unsupported partition stencil shape")
        if selection == nil then return nil, select_reason end
        return { kind = "partition", selection = selection, result_ty = Code.CodeTyInt(32, Code.CodeSigned) }, nil
    end

    local function skeleton_copy_plan(ctx, func, plan, graph_loop, loop_fact)
        local effect, effect_reason = single_effect(plan.body, Kernel.KernelEffectCopy)
        if effect == nil then return nil, effect_reason end
        local dst_base = lane_base_value(effect.dst)
        if dst_base == nil then return nil, "copy destination lane has no value base" end
        local dst_fact = lane_selection_fact(ctx, effect.dst)
        local bindings = binding_index(plan.body)
        local class, class_reason = enriched_class_for_expr(ctx, effect.src, graph_loop, loop_fact, bindings, dst_base, effect.dst.elem_ty)
        if class == nil then return nil, class_reason end
        local step_num = const_int_value(ctx, loop_fact.counted.step)
        if step_num == nil or step_num == 0 then return nil, "copy skeleton requires a non-zero constant step" end
        local descriptor_step = math.abs(step_num)
        local selection, select_reason = run_stencil_selection("select_store_stencil", {
            step_num = descriptor_step,
            producer = producer_from_loop(ctx, loop_fact, descriptor_step),
            dst_elem_ty = effect.dst.elem_ty,
            dst = dst_base,
            dst_expr = value_id_expr(ctx, dst_base),
            dst_layout = dst_fact and dst_fact.layout or nil,
            start = loop_fact.counted.start,
            stop = loop_fact.counted.stop,
            start_expr = value_id_expr(ctx, loop_fact.counted.start),
            stop_expr = value_id_expr(ctx, loop_fact.counted.stop),
            store_index_primary = true,
            copy_semantics = effect.semantics,
            class = class,
        }, "unsupported store stencil shape")
        if selection == nil then return nil, select_reason end
        return { kind = "copy", selection = selection, result_ty = nil }, nil
    end

    local function skeleton_scatter_reduce_plan(ctx, func, plan, graph_loop, loop_fact)
        local effect, effect_reason = single_effect(plan.body, Kernel.KernelEffectScatterReduce)
        if effect == nil then return nil, effect_reason end
        if not function_returns_void_from_loop(func, graph_loop) then return nil, "scatter-reduce loop exits as neither final value nor void effect" end
        local dst_base = lane_base_value(effect.dst)
        if dst_base == nil then return nil, "scatter-reduce destination lane has no value base" end
        local dst_fact = lane_selection_fact(ctx, effect.dst)
        if dst_fact == nil then return nil, "scatter-reduce destination lane has no layout fact" end
        local bindings = binding_index(plan.body)
        local class, class_reason = enriched_class_for_expr(ctx, effect.value, graph_loop, loop_fact, bindings, dst_base, effect.dst.elem_ty)
        if class == nil then return nil, class_reason end
        local contribution = nil
        if class.kind == "apply_n" then
            for _, input in ipairs(class.inputs or {}) do
                if input.index_primary ~= true then return nil, "scatter-reduce contribution inputs must be primary-indexed" end
            end
            contribution = {
                ty = class.result_ty,
                expr = class.expr,
                inputs = class.inputs,
            }
        elseif class.kind == "load" then
            contribution = {
                ty = class.elem_ty,
                expr = Stencil.StencilApplyInput(Stencil.StencilAccessRef("xs")),
                inputs = {
                    {
                        name = "xs",
                        base = class.src,
                        base_expr = class.src_expr,
                        ty = class.elem_ty,
                        layout = class.src_layout,
                        index_primary = class.index_primary,
                    },
                },
            }
            if not class.index_primary then return nil, "scatter-reduce contribution must be primary-indexed" end
        end
        if contribution == nil then return nil, "scatter-reduce requires an ApplyN contribution" end
        local index_lane = index_lane_selection_fact(ctx, effect.index, graph_loop, loop_fact, bindings)
        if index_lane == nil then return nil, "scatter-reduce destination index must come from an index lane" end
        if not index_lane.index_primary then return nil, "scatter-reduce index lane must be primary-indexed" end
        local step_num = const_int_value(ctx, loop_fact.counted.step)
        if step_num == nil or step_num == 0 then return nil, "scatter-reduce stencil requires a non-zero constant step" end
        local descriptor_step = math.abs(step_num)
        return {
            kind = "scatter_reduce",
            selection = {
                kind = "scatter_reduce",
                info = {
                    step_num = descriptor_step,
                    producer = producer_from_loop(ctx, loop_fact, descriptor_step),
                    result_ty = effect.reducer.result_ty,
                    item_ty = contribution.ty,
                    index_ty = index_lane.elem_ty,
                    dst = dst_base,
                    dst_name = "dst",
                    dst_layout = Stencil.StencilLayoutIndexed(
                        dst_fact.layout,
                        Stencil.StencilAccessRef("idx"),
                        index_lane.elem_ty,
                        descriptor_step
                    ),
                    index = index_lane.base,
                    index_name = "idx",
                    index_layout = index_lane.layout,
                    inputs = contribution.inputs,
                    expr = contribution.expr,
                },
                args = {
                    value_id_expr(ctx, dst_base),
                    index_lane.base_expr,
                    value_id_expr(ctx, loop_fact.counted.start),
                    value_id_expr(ctx, loop_fact.counted.stop),
                },
            },
            reduction = {
                kind = effect.reducer.reduction,
                int_semantics = effect.reducer.int_semantics,
                float_mode = effect.reducer.float_mode,
            },
            result_ty = nil,
        }, nil
    end

    local function stencil_skeleton_plan(ctx, func, plan, graph_loop, loop_fact)
        if pvm.classof(plan) ~= Kernel.KernelPlanned then return nil, "kernel is not planned" end
        if loop_fact == nil or loop_fact.counted == nil then return nil, "stencil skeleton requires counted loop" end
        local step_num = const_int_value(ctx, loop_fact.counted.step)
        if step_num == nil or step_num == 0 then return nil, "stencil skeleton requires a non-zero constant step" end
        local scan, scan_reason = skeleton_scan_plan(ctx, func, plan, graph_loop, loop_fact)
        local find, find_reason = skeleton_find_plan(ctx, func, plan, graph_loop, loop_fact)
        local partition, partition_reason = skeleton_partition_plan(ctx, func, plan, graph_loop, loop_fact)
        local copy, copy_reason = skeleton_copy_plan(ctx, func, plan, graph_loop, loop_fact)
        local scatter_reduce, scatter_reduce_reason = skeleton_scatter_reduce_plan(ctx, func, plan, graph_loop, loop_fact)
        local reject_reason = scan_reason or find_reason or partition_reason or copy_reason or scatter_reduce_reason or "no stencil skeleton selected"
        local selection, err = LowerRules:run("select_skeleton_lowering", { skeleton = {
            scan_ready = scan ~= nil,
            scan_plan = scan,
            find_ready = find ~= nil,
            find_plan = find,
            partition_ready = partition ~= nil,
            partition_plan = partition,
            copy_ready = copy ~= nil,
            copy_plan = copy,
            scatter_reduce_ready = scatter_reduce ~= nil,
            scatter_reduce_plan = scatter_reduce,
            reject_reason = reject_reason,
        } }, "selection", "no LuaJIT skeleton lowering selected")
        if selection == nil then return nil, err end
        if selection.kind == LowerRules.kind.no_plan then return nil, selection.reason end
        return selection.planned, nil
    end

    local function lower_kernel_stencil_skeleton(ctx, func, plan, graph_loop, loop_fact, opts)
        if opts.stencil_skeleton_artifact_for == nil then return nil, "no skeleton stencil artifact provider" end
        local planned, reason = stencil_skeleton_plan(ctx, func, plan, graph_loop, loop_fact)
        if planned == nil then return nil, reason end
        local selection = planned.selection
        local artifact = select_skeleton_artifact(opts, func, selection.kind or selection.vocab, selection.op, planned.reduction, plan, selection.info)
        if artifact == nil then return nil, "skeleton stencil artifact provider did not select an artifact" end
        local id = LJ.LJMachineId("machine:" .. sanitize(func.name) .. ":stencil_skeleton:" .. sanitize(loop_fact.loop.text))
        if planned.result_ty ~= nil then
            local result_ty = physical(ctx, planned.result_ty)
            return LJ.LJMachine(id, LJ.LJMachineStencilCall(artifact, stencil_args(ctx, artifact, selection), result_ty), result_ty, LJ.LJStateScalar, LJ.LJTraceHot), nil
        end
        return LJ.LJMachine(id, LJ.LJMachineStencilEffect(artifact, stencil_args(ctx, artifact, selection)), nil, LJ.LJStateScalar, LJ.LJTraceHot), nil
    end

    local function plan_kernel_stencil_skeleton(ctx, func, plan, graph_loop, loop_fact, opts)
        return lower_kernel_stencil_skeleton(ctx, func, plan, graph_loop, loop_fact, opts)
    end

    local function counted_positive(ctx, loop_fact)
        if loop_fact == nil or loop_fact.counted == nil then return false end
        local step_num = const_int_value(ctx, loop_fact.counted.step)
        return step_num ~= nil and step_num ~= 0
    end

    local function kernel_lowering_input(ctx, func, plan, graph_loop, loop_fact, loop_owner, kernel, opts)
        local subject = plan and plan.subject or nil
        local subject_cls = pvm.classof(subject)
        local loop_plan = subject_cls == Kernel.KernelSubjectLoop or subject_cls == Kernel.KernelSubjectFunction
        local owns_loop = (subject_cls == Kernel.KernelSubjectLoop and loop_owner == func.id)
            or (subject_cls == Kernel.KernelSubjectFunction and subject.func == func.id)
        local planned = pvm.classof(plan) == Kernel.KernelPlanned
        local result = planned and plan.body and plan.body.result or nil
        local result_reduction = pvm.classof(result) == Kernel.KernelResultReduction
        local reduction = result_reduction and result.reduction or nil
        local stencil_reduce_ready = false
        local stencil_reduce_reason = nil
        if planned then
            local ready
            ready, stencil_reduce_reason = stencil_reduce_plan(ctx, func, plan, graph_loop, loop_fact)
            stencil_reduce_ready = ready ~= nil
        end
        local stencil_store_ready = false
        local stencil_store_reason = nil
        if planned then
            local ready
            ready, stencil_store_reason = stencil_store_plan(ctx, func, plan, graph_loop, loop_fact)
            stencil_store_ready = ready ~= nil
        end
        local stencil_skeleton_ready = false
        local stencil_skeleton_reason = nil
        if planned then
            local ready
            ready, stencil_skeleton_reason = stencil_skeleton_plan(ctx, func, plan, graph_loop, loop_fact)
            stencil_skeleton_ready = ready ~= nil
        end
        local single_store = false
        local store_dst_base = false
        local store_reason = nil
        if planned then
            local store
            store, store_reason = single_store_effect(plan.body)
            single_store = store ~= nil
            store_dst_base = store ~= nil and lane_base_value(store.dst) ~= nil
        end
        local any_ready_lowering = (opts.stencil_skeleton_artifact_for ~= nil and stencil_skeleton_ready)
            or (opts.stencil_reduce_artifact_for ~= nil and result_reduction and stencil_reduce_ready and not stencil_skeleton_ready)
            or (opts.stencil_store_artifact_for ~= nil and stencil_store_ready and not stencil_skeleton_ready)
        local reject_reason = "no LuaJIT stencil lowering matched"
        if not loop_plan then
            reject_reason = "kernel subject is not a loop lowering input"
        elseif not owns_loop then
            reject_reason = "kernel subject is not owned by the current function"
        elseif not planned then
            reject_reason = "kernel is not planned"
        elseif single_store then
            reject_reason = stencil_store_reason or store_reason or reject_reason
        elseif result_reduction and not stencil_skeleton_ready then
            reject_reason = stencil_reduce_reason or reject_reason
        elseif stencil_skeleton_reason ~= nil then
            reject_reason = stencil_skeleton_reason
        elseif store_reason ~= nil then
            reject_reason = store_reason
        end
        return {
            loop_plan = loop_plan,
            owns_loop = loop_plan and owns_loop,
            planned = planned,
            has_reduce_provider = opts.stencil_reduce_artifact_for ~= nil,
            has_store_provider = opts.stencil_store_artifact_for ~= nil,
            has_skeleton_provider = opts.stencil_skeleton_artifact_for ~= nil,
            counted_positive = counted_positive(ctx, loop_fact),
            result_reduction = result_reduction,
            returns_reduction = reduction ~= nil and function_returns_reduction(func, graph_loop, reduction),
            returns_void = function_returns_void_from_loop(func, graph_loop),
            stencil_reduce_ready = stencil_reduce_ready,
            stencil_reduce_reject = stencil_reduce_reason,
            single_store = single_store,
            store_dst_base = store_dst_base,
            stencil_store_ready = stencil_store_ready,
            stencil_store_reject = stencil_store_reason,
            stencil_skeleton_ready = stencil_skeleton_ready,
            stencil_skeleton_reject = stencil_skeleton_reason,
            store_reject = store_reason,
            any_ready_lowering = any_ready_lowering,
            reject_reason = reject_reason,
        }
    end

    local function lower_blocks_func(ctx, func)
        local blocks = {}
        for i, block in ipairs(func.blocks or {}) do blocks[i] = lower_block(ctx, block) end
        return {}, LJ.LJBodyBlocks(bid(func.entry), blocks)
    end

    local build_kernel

    local function module_ctx_for(module, flow, mem, contracts)
        return {
            code_sigs = code_sigs(module),
            mem_objects = mem_object_index(mem),
            mem_accesses = mem_access_index(mem),
            soa_contracts = soa_contract_index(contracts),
            producer_facts = producer_fact_index(flow),
            flow = flow,
        }
    end

    local function func_lower_ctx(module_ctx, func)
        local ctx = {
            code_sigs = module_ctx.code_sigs,
            mem_objects = module_ctx.mem_objects,
            mem_accesses = module_ctx.mem_accesses,
            soa_contracts = module_ctx.soa_contracts,
            producer_facts = module_ctx.producer_facts,
            func_id = func.id,
            flow = module_ctx.flow,
            value_types = {},
            defs = value_defs(func),
        }
        note_params(ctx, func.params)
        for _, block in ipairs(func.blocks or {}) do note_params(ctx, block.params) end
        return ctx
    end

    local function plan_domain_loop(plan)
        local body = plan and plan.body or nil
        local domain = body and body.domain and body.domain.domain or nil
        if pvm.classof(domain) == Flow.FlowDomainLoop then return domain.loop end
        return nil
    end

    local function select_kernel_machine(ctx, func, plan, graph_loop, loop_fact, owner, kernel, opts)
        local input = kernel_lowering_input(ctx, func, plan, graph_loop, loop_fact, owner, kernel, opts)
        local selection, reason = LowerRules:run("select_kernel_lowering", { kernel = input }, "selection", "no LuaJIT kernel lowering selected")
        if selection == nil then return nil, reason end
        if selection.kind == LowerRules.kind.no_plan then return nil, selection.reason end
        local planners = {
            [LowerRules.kind.stencil_reduce] = plan_kernel_stencil_reduce,
            [LowerRules.kind.stencil_store] = plan_kernel_stencil_store,
            [LowerRules.kind.stencil_skeleton] = plan_kernel_stencil_skeleton,
        }
        local planner = planners[selection.kind]
        if planner ~= nil then
            return planner(ctx, func, plan, graph_loop, loop_fact, opts)
        end
        return nil, "unknown LuaJIT lowering strategy " .. tostring(selection.kind)
    end

    local function plan_func_stencil_machine(module_ctx, func, kernel, graph_loops, flow_loops, loop_func, opts)
        local ctx = func_lower_ctx(module_ctx, func)
        local pending_rejects = {}
        for _, plan in ipairs(kernel.plans or {}) do
            local subject = plan.subject
            local subject_cls = pvm.classof(subject)
            local loop_id = nil
            local owner = nil
            if subject_cls == Kernel.KernelSubjectLoop and loop_func[subject.loop.text] == func.id then
                loop_id = subject.loop
                owner = loop_func[subject.loop.text]
            elseif subject_cls == Kernel.KernelSubjectFunction and subject.func == func.id then
                loop_id = plan_domain_loop(plan)
                owner = func.id
            end
            if loop_id ~= nil then
                local graph_loop = graph_loops[loop_id.text]
                local loop_fact = flow_loops[loop_id.text]
                local machine, reason = select_kernel_machine(ctx, func, plan, graph_loop, loop_fact, owner, kernel, opts)
                if machine ~= nil then
                    local artifact = machine.kind and machine.kind.artifact or nil
                    return LJ.LJStencilMachinePlan(func.id, plan.id, machine, artifact), pending_rejects
                end
                if kernel_plan_stencil_shaped(plan) then
                    pending_rejects[#pending_rejects + 1] = { func = func.id, loop = loop_id, reason = reason }
                end
            end
        end
        return nil, pending_rejects
    end

    local function plan_stencil_machines(module, opts)
        opts = opts or {}
        local graph, flow, value, mem, effect, kernel = build_kernel(module, opts)
        local graph_loops, loop_func = graph_loop_index(graph)
        local flow_loops = flow_loop_index(flow)
        local module_ctx = module_ctx_for(module, flow, mem, opts.contracts)
        local by_func, plans, rejects = {}, {}, {}
        for _, func in ipairs(module.funcs or {}) do
            local plan, pending = plan_func_stencil_machine(module_ctx, func, kernel, graph_loops, flow_loops, loop_func, opts)
            if plan ~= nil then
                plans[#plans + 1] = plan
                by_func[func.id.text] = plan.machine
            else
                for _, reject in ipairs(pending or {}) do rejects[#rejects + 1] = reject end
            end
        end
        return {
            graph = graph,
            flow = flow,
            value = value,
            mem = mem,
            effect = effect,
            kernel = kernel,
            plan = LJ.LJStencilMachineModulePlan(module.id, opts.stencil_plan or T.LalinStencil.StencilModulePlan(module.id, kernel, {}), plans),
            machine_plans = plans,
            machines_by_func = by_func,
            rejects = rejects,
        }
    end

    local function lower_func(module_ctx, func, kernel, graph_loops, flow_loops, loop_func, opts)
        local ctx = func_lower_ctx(module_ctx, func)
        local params = lower_params(ctx, func.params)
        local machines, body = nil, nil
        local planned_machine = opts.stencil_machines_by_func and opts.stencil_machines_by_func[func.id.text] or nil
        if planned_machine ~= nil then
            machines = { planned_machine }
            body = LJ.LJBodyMachine(planned_machine.id, LJ.LJTerminalFirst(nil))
            return LJ.LJFunc(fid(func.id), func.id, func.name, sigid(func.sig), params, {}, machines, body, LJ.LJTraceHot)
        end
        if body == nil then machines, body = lower_blocks_func(ctx, func) end
        return LJ.LJFunc(fid(func.id), func.id, func.name, sigid(func.sig), params, {}, machines, body, LJ.LJTraceHot)
    end

    build_kernel = function(module, opts)
        local graph = opts.graph or CodeGraph.graph(module)
        local flow = opts.flow or CodeFlowFacts.facts(module, graph)
        local value = opts.value or CodeValueFacts.facts(module, graph, flow)
        local mem = opts.mem or CodeMemFacts.semantic_facts(module, graph, flow, value, opts.contracts)
        local effect = opts.effect or CodeEffectFacts.facts(module, graph, mem, opts.contracts)
        local kernel = opts.kernel or CodeKernelPlan.plan(module, graph, flow, value, mem, effect)
        return graph, flow, value, mem, effect, kernel
    end

    local function lower_module(module, opts)
        opts = opts or {}
        local graph, flow, value, mem, effect, kernel = build_kernel(module, opts)
        local has_stencil_provider = opts.stencil_store_artifact_for ~= nil
            or opts.stencil_reduce_artifact_for ~= nil
            or opts.stencil_skeleton_artifact_for ~= nil
        if opts.stencil_machines_by_func == nil and has_stencil_provider then
            local planned = plan_stencil_machines(module, opts)
            opts.stencil_machines_by_func = planned.machines_by_func
            opts.luajit_stencil_machine_plan = planned.plan
            if opts.collect_rejects ~= nil then
                for _, reject in ipairs(planned.rejects or {}) do opts.collect_rejects[#opts.collect_rejects + 1] = reject end
            end
        elseif opts.collect_rejects ~= nil and opts.stencil_machines_by_func == nil then
            for _, plan in ipairs(kernel.plans or {}) do
                if kernel_plan_stencil_shaped(plan) then
                    opts.collect_rejects[#opts.collect_rejects + 1] = {
                        func = nil,
                        loop = nil,
                        reason = "missing preplanned stencil machine; run stencil planning with an artifact provider before LuaJIT projection",
                    }
                end
            end
        end
        local graph_loops, loop_func = graph_loop_index(graph)
        local flow_loops = flow_loop_index(flow)
        local module_ctx = module_ctx_for(module, flow, mem, opts.contracts)
        local funcs = {}
        for i, func in ipairs(module.funcs or {}) do funcs[i] = lower_func(module_ctx, func, kernel, graph_loops, flow_loops, loop_func, opts) end
        return LJ.LJModule(module.id, funcs, {}, {}, {}), {
            graph = graph,
            flow = flow,
            value = value,
            mem = mem,
            effect = effect,
            kernel = kernel,
        }
    end

    api.lower_module = lower_module
    api.module = lower_module
    api.build_kernel = build_kernel
    api.plan_stencil_machines = plan_stencil_machines

    T._lalin_api_cache.luajit_lower = api
    return api
end

return bind_context
