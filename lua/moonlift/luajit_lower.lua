local pvm = require("moonlift.pvm")

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
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.luajit_lower ~= nil then return T._moonlift_api_cache.luajit_lower end

    local Core = T.MoonCore
    local Code = T.MoonCode
    local Flow = T.MoonFlow
    local Value = T.MoonValue
    local Mem = T.MoonMem
    local Kernel = T.MoonKernel
    local LJ = T.MoonLuaJIT
    local Stencil = T.MoonStencil

    local CType = require("moonlift.luajit_ctype")(T)
    local Expr = require("moonlift.luajit_expr")(T)
    local CodeGraph = require("moonlift.code_graph")(T)
    local CodeFlowFacts = require("moonlift.code_flow_facts")(T)
    local CodeValueFacts = require("moonlift.code_value_facts")(T)
    local CodeMemFacts = require("moonlift.code_mem_facts")(T)
    local CodeEffectFacts = require("moonlift.code_effect_facts")(T)
    local CodeKernelPlan = require("moonlift.code_kernel_plan")(T)
    local StencilRules = require("moonlift.luajit_stencil_rules")(T)
    local LowerRules = require("moonlift.luajit_lower_rules")(T)

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
        elseif cls == Value.ValueExprAdd or cls == Value.ValueExprSub or cls == Value.ValueExprMul or cls == Value.ValueExprDiv then
            local op = (cls == Value.ValueExprAdd and Core.BinAdd)
                or (cls == Value.ValueExprSub and Core.BinSub)
                or (cls == Value.ValueExprMul and Core.BinMul)
                or Core.BinDiv
            return LJ.LJExprIntBinary(op, physical(ctx, expr.ty), expr.sem, value_expr(ctx, expr.a), value_expr(ctx, expr.b))
        end
        error("luajit_lower: unsupported ValueExpr " .. class_name(expr), 3)
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

    local function is_luajit_scalar_reduction(kind)
        return kind == Value.ReductionAdd
            or kind == Value.ReductionMul
            or kind == Value.ReductionAnd
            or kind == Value.ReductionOr
            or kind == Value.ReductionXor
            or kind == Value.ReductionMin
            or kind == Value.ReductionMax
    end

    local function is_float_stencil_reduction(kind)
        return kind == Value.ReductionAdd
            or kind == Value.ReductionMul
            or kind == Value.ReductionMin
            or kind == Value.ReductionMax
    end

    local function const_int_value(ctx, id)
        local def = ctx.defs and id and ctx.defs[id.text] or nil
        local k = def and def.kind
        if pvm.classof(k) ~= Code.CodeInstConst or pvm.classof(k.const) ~= Code.CodeConstLiteral or pvm.classof(k.const.literal) ~= Core.LitInt then return nil end
        return tonumber(k.const.literal.raw)
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

    local function function_returns_reduction(func, graph_loop, reduction)
        if graph_loop == nil or #(graph_loop.exits or {}) ~= 1 then return false end
        local blocks = block_index(func)
        local edge = graph_loop.exits[1]
        local from = blocks[edge.from.block.text]
        local exit = blocks[edge.to.block.text]
        if from == nil or exit == nil then return false end
        local ret = exit.term and exit.term.kind or nil
        if pvm.classof(ret) ~= Code.CodeTermReturn or #(ret.values or {}) ~= 1 then return false end
        if ret.values[1] == reduction.accumulator then return true end
        for i, param in ipairs(exit.params or {}) do
            if ret.values[1] == param.value then
                local args = term_args_to_dest(from.term, exit.id)
                return args ~= nil and args[i] == reduction.accumulator
            end
        end
        return false
    end

    local function find_load_inst(func, loop_fact, value)
        local loop_blocks = {}
        for _, gb in ipairs(loop_fact and loop_fact.body_blocks or {}) do loop_blocks[gb.block.text] = true end
        for _, block in ipairs(func.blocks or {}) do
            if loop_blocks[block.id.text] then
                for _, inst in ipairs(block.insts or {}) do
                    local k = inst.kind
                    if pvm.classof(k) == Code.CodeInstLoad and k.dst == value then return block, inst, k end
                end
            end
        end
        return nil, nil, nil
    end

    local function stream_has_load_access(kernel, load_inst)
        local accesses = mem_access_index(kernel.mem)
        for _, plan in ipairs(kernel.plans or {}) do
            if pvm.classof(plan) == Kernel.KernelPlanned then
                for _, stream in ipairs(plan.body.streams or {}) do
                    for _, aid in ipairs(stream.accesses or {}) do
                        local access = accesses[aid.text]
                        if access ~= nil and access.inst == load_inst.id then return true end
                    end
                end
            end
        end
        return false
    end

    local function vector_reduce_plan(ctx, func, plan, graph_loop, loop_fact, kernel)
        if pvm.classof(plan) ~= Kernel.KernelPlanned then return nil, "kernel is not planned" end
        local result = plan.body.result
        if pvm.classof(result) ~= Kernel.KernelResultReduction then return nil, "kernel result is not a reduction" end
        local reduction = result.reduction
        if not function_returns_reduction(func, graph_loop, reduction) then return nil, "function return is not the kernel reduction" end
        if not is_luajit_scalar_reduction(reduction.kind) then return nil, "LuaJIT vector reduce currently supports add/mul/min/max/bitwise reductions only" end
        local ty_cls = pvm.classof(reduction.ty)
        local fallback_supported = ty_cls == Code.CodeTyInt and (reduction.ty.bits == 8 or reduction.ty.bits == 16 or reduction.ty.bits == 32)
        if ty_cls ~= Code.CodeTyInt and ty_cls ~= Code.CodeTyFloat then return nil, "LuaJIT vector reduce supports scalar integer/float reductions only" end
        if ty_cls == Code.CodeTyFloat and not is_float_stencil_reduction(reduction.kind) then return nil, "LuaJIT float vector reduce supports add/mul/min/max only" end
        if not fallback_supported then return nil, "LuaJIT vector reduce scalar fallback currently supports 8/16/32-bit integer reductions only" end
        if ty_cls == Code.CodeTyInt and (reduction.kind == Value.ReductionAdd or reduction.kind == Value.ReductionMul) and (reduction.int_semantics == nil or reduction.int_semantics.overflow ~= Code.CodeIntWrap) then
            return nil, "LuaJIT vector reduce add/mul requires wrapping integer semantics"
        end
        local contrib = reduction.contribution
        if pvm.classof(contrib) ~= Value.ValueExprValue then return nil, "reduction contribution is not a single Code value" end
        local _, load_inst, load = find_load_inst(func, loop_fact, contrib.value)
        if load == nil then return nil, "reduction contribution is not a loop-local load" end
        if not stream_has_load_access(kernel, load_inst) then return nil, "load is not part of a planned kernel stream" end
        local place = load.place
        if pvm.classof(place) ~= Code.CodePlaceIndex then return nil, "load is not indexed array access" end
        local base = place.base
        if pvm.classof(base) ~= Code.CodePlaceDeref then return nil, "indexed load base is not a data pointer dereference" end
        local found_induction = false
        for _, induction in ipairs(loop_fact.inductions or {}) do
            if place.index == induction.value and induction.kind == Flow.FlowPrimaryInduction then found_induction = true end
        end
        if not found_induction then return nil, "indexed load is not driven by the primary induction" end
        if loop_fact.counted == nil then return nil, "loop is not counted" end
        local step_num = const_int_value(ctx, loop_fact.counted.step)
        if step_num == nil or step_num <= 0 then return nil, "LuaJIT vector reduce scalar fallback requires a positive constant step" end
        return {
            reduction = reduction,
            load_inst = load_inst,
            load = load,
            base = base,
            step_num = step_num,
        }, nil
    end

    local function lower_kernel_vector_reduce(ctx, func, plan, graph_loop, loop_fact, kernel, opts)
        local ready, reason = vector_reduce_plan(ctx, func, plan, graph_loop, loop_fact, kernel)
        if ready == nil then return nil, reason end
        local reduction, load, base = ready.reduction, ready.load, ready.base
        local id = LJ.LJMachineId("machine:" .. sanitize(func.name) .. ":vreduce:" .. sanitize(loop_fact.loop.text))
        return LJ.LJMachine(
            id,
            LJ.LJMachineVectorReduceArray(
                vid(base.addr),
                value_id_expr(ctx, loop_fact.counted.start),
                value_id_expr(ctx, loop_fact.counted.stop),
                value_id_expr(ctx, loop_fact.counted.step),
                physical(ctx, load.access.ty),
                physical(ctx, reduction.ty),
                reduction.kind,
                reduction.int_semantics,
                value_expr(ctx, reduction.init),
                opts.vector_lanes or 8,
                opts.vector_unroll or 1
            ),
            physical(ctx, reduction.ty),
            LJ.LJStateScalar,
            LJ.LJTraceHot
        ), nil
    end

    local function function_returns_void_from_loop(func, graph_loop)
        if graph_loop == nil or #(graph_loop.exits or {}) ~= 1 then return false end
        local blocks = block_index(func)
        local exit = blocks[graph_loop.exits[1].to.block.text]
        local ret = exit and exit.term and exit.term.kind or nil
        return pvm.classof(ret) == Code.CodeTermReturn and #(ret.values or {}) == 0
    end

    local function stream_base_value(stream)
        local base = stream and stream.base or nil
        if pvm.classof(base) == Mem.MemBaseValue then return base.value end
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

    local function pattern_topology(pattern)
        local cls = pvm.classof(pattern)
        if pattern == Mem.MemAccessContiguous then return Stencil.StencilTopologyContiguous(1) end
        if cls == Mem.MemAccessStrided then return Stencil.StencilTopologyContiguous(pattern.stride_elems) end
        return nil
    end

    local function stream_topology(ctx, stream)
        local object = ctx.mem_objects and stream and ctx.mem_objects[stream.object.text] or nil
        if object ~= nil then
            local provenance = object.provenance
            local pcls = pvm.classof(provenance)
            if object.kind == Mem.MemObjectView and pcls == Mem.MemProvView then
                if provenance.stride == nil then return nil end
                return Stencil.StencilTopologyViewDescriptor(
                    provenance.view,
                    provenance.data,
                    extent_len(object.extent) or provenance.len,
                    provenance.stride,
                    mem_stride_const(object.stride)
                )
            end
            if object.kind == Mem.MemObjectSlice and pcls == Mem.MemProvSlice then
                return Stencil.StencilTopologySliceDescriptor(
                    provenance.slice,
                    provenance.data,
                    extent_len(object.extent) or provenance.len
                )
            end
            if object.kind == Mem.MemObjectByteSpan and pcls == Mem.MemProvByteSpan then
                return Stencil.StencilTopologyByteSpanDescriptor(
                    provenance.span,
                    provenance.data,
                    extent_len(object.extent) or provenance.len
                )
            end
        end
        return pattern_topology(stream and stream.pattern)
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

    local function expr_is_value(expr, id)
        return id ~= nil and pvm.classof(expr) == Value.ValueExprValue and expr.value == id
    end

    local function expr_is_primary(expr, loop_fact)
        return expr_is_value(expr, primary_induction(loop_fact))
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

    local function index_stream_for(expr, bindings)
        return StencilRules.select_index_stream(Kernel.KernelExprAlgebra(expr), bindings)
    end

    local function stream_selection_fact(ctx, stream)
        local topology = stream_topology(ctx, stream)
        if topology == nil then return nil end
        local base = stream_base_value(stream)
        local tcls = pvm.classof(topology)
        if tcls == Stencil.StencilTopologyViewDescriptor or tcls == Stencil.StencilTopologySliceDescriptor or tcls == Stencil.StencilTopologyByteSpanDescriptor then
            base = topology.data
        end
        if base == nil then return nil end
        return {
            base = base,
            base_expr = value_id_expr(ctx, base),
            elem_ty = stream.elem_ty,
            topology = topology,
        }
    end

    local function enrich_stream_class(ctx, class, loop_fact, bindings, prefix)
        local stream = class[prefix]
        local index = class[prefix .. "_index"] or class.index
        local fact = stream_selection_fact(ctx, stream)
        if fact == nil then return nil, prefix .. " stream has no value base" end
        if prefix == "stream" then
            class.src = fact.base
            class.src_expr = fact.base_expr
            class.elem_ty = fact.elem_ty
            class.src_topology = fact.topology
            class.index_primary = expr_is_primary(index, loop_fact)
            if not class.index_primary then
                local idx = index_stream_for(index, bindings)
                if idx ~= nil then
                    local idx_fact = stream_selection_fact(ctx, idx.stream)
                    if idx_fact ~= nil then
                        class.index_stream = {
                            base = idx_fact.base,
                            base_expr = idx_fact.base_expr,
                            elem_ty = idx_fact.elem_ty,
                            topology = idx_fact.topology,
                            index_primary = expr_is_primary(idx.index, loop_fact),
                        }
                    end
                end
            end
        else
            class[prefix .. "_base"] = fact.base
            class[prefix .. "_expr"] = fact.base_expr
            class[prefix .. "_ty"] = fact.elem_ty
            class[prefix .. "_topology"] = fact.topology
            class[prefix .. "_index_primary"] = expr_is_primary(index, loop_fact)
        end
        return class
    end

    local function enrich_stencil_class(ctx, class, loop_fact, bindings, dst_base, dst_ty)
        if class.kind == "load" or class.kind == "map" or class.kind == "cast" or class.kind == "compare" then
            local ok, err = enrich_stream_class(ctx, class, loop_fact, bindings, "stream")
            if not ok then return nil, err end
            if class.kind == "map" then
                class.same_src_dst_ty = class.src == dst_base and same_code_type(class.elem_ty, dst_ty)
            end
        elseif class.kind == "zip_map" or class.kind == "zip_compare" then
            local ok, err = enrich_stream_class(ctx, class, loop_fact, bindings, "lhs")
            if not ok then return nil, err end
            ok, err = enrich_stream_class(ctx, class, loop_fact, bindings, "rhs")
            if not ok then return nil, err end
        elseif class.kind == "fill" then
            class.value_expr = value_expr(ctx, class.value)
        end
        return class
    end

    local function enriched_class_for_expr(ctx, expr, loop_fact, bindings, dst_base, dst_ty)
        local classified, reason = classify_store_expr(expr, bindings)
        if classified == nil then return nil, reason end
        return enrich_stencil_class(ctx, classified, loop_fact, bindings, dst_base, dst_ty)
    end

    local function index_stream_selection_fact(ctx, expr, loop_fact, bindings)
        local idx = index_stream_for(expr, bindings)
        if idx == nil then return nil end
        local fact = stream_selection_fact(ctx, idx.stream)
        if fact == nil then return nil end
        return {
            base = fact.base,
            base_expr = fact.base_expr,
            elem_ty = fact.elem_ty,
            index_primary = expr_is_primary(idx.index, loop_fact),
        }
    end

    local function stencil_store_plan(ctx, func, plan, graph_loop, loop_fact)
        if pvm.classof(plan) ~= Kernel.KernelPlanned then return nil, "kernel is not planned" end
        if not function_returns_void_from_loop(func, graph_loop) then return nil, "store stencil requires loop exit to return void" end
        if loop_fact == nil or loop_fact.counted == nil then return nil, "store stencil requires counted loop" end
        local step_num = const_int_value(ctx, loop_fact.counted.step)
        if step_num == nil or step_num <= 0 then return nil, "store stencil requires a positive constant step" end
        local store, store_reason = single_store_effect(plan.body)
        if store == nil then return nil, store_reason end
        local dst_base = stream_base_value(store.dst)
        if dst_base == nil then return nil, "store destination stream has no value base" end
        local dst_fact = stream_selection_fact(ctx, store.dst)
        local bindings = binding_index(plan.body)
        local classified, reason = classify_store_expr(store.value, bindings)
        if classified == nil then return nil, reason end
        local start_expr, stop_expr = value_id_expr(ctx, loop_fact.counted.start), value_id_expr(ctx, loop_fact.counted.stop)
        local dst_expr = value_id_expr(ctx, dst_base)
        local store_index_is_primary = expr_is_primary(store.index, loop_fact)
        local class, class_reason = enrich_stencil_class(ctx, classified, loop_fact, bindings, dst_base, store.dst.elem_ty)
        if class == nil then return nil, class_reason end
        local selection_ctx = {
            step_num = step_num,
            dst_elem_ty = store.dst.elem_ty,
            dst = dst_base,
            dst_expr = dst_expr,
            dst_topology = dst_fact and dst_fact.topology or nil,
            start = loop_fact.counted.start,
            stop = loop_fact.counted.stop,
            start_expr = start_expr,
            stop_expr = stop_expr,
            store_index_primary = store_index_is_primary,
            store_index_stream = store_index_is_primary and nil or index_stream_selection_fact(ctx, store.index, loop_fact, bindings),
            scatter_conflicts = Stencil.StencilScatterUniqueIndices,
            class = class,
        }
        local stencil_plan, select_reason = StencilRules.plan_store {
            planned = pvm.classof(plan) == Kernel.KernelPlanned,
            returns_void = function_returns_void_from_loop(func, graph_loop),
            counted_positive = step_num ~= nil and step_num > 0,
            single_store = store ~= nil,
            dst_base_present = dst_base ~= nil,
            class_ready = class ~= nil,
            selection_ctx = selection_ctx,
        }
        if stencil_plan == nil then return nil, select_reason end
        return { selection = stencil_plan.selection }, nil
    end

    local function stencil_args(ctx, artifact, args)
        local out = {}
        for i = 1, #(args or {}) do out[i] = args[i] end
        local desc = artifact and artifact.instance and artifact.instance.descriptor or nil
        for _, access in ipairs(desc and desc.accesses or {}) do
            local top = access.topology
            if pvm.classof(top) == Stencil.StencilTopologyViewDescriptor and top.stride_const == nil then
                out[#out + 1] = value_id_expr(ctx, top.stride)
            end
        end
        return out
    end

    local function lower_kernel_stencil_store(ctx, func, plan, graph_loop, loop_fact, opts)
        if opts.stencil_store_artifact_for == nil then return nil, "no store stencil artifact provider" end
        local planned, reason = stencil_store_plan(ctx, func, plan, graph_loop, loop_fact)
        if planned == nil then return nil, reason end
        local selection = planned.selection
        local artifact = opts.stencil_store_artifact_for(func, selection.vocab, selection.op, plan, selection.info)
        if artifact == nil then return nil, "store stencil artifact provider did not select an artifact" end
        local id = LJ.LJMachineId("machine:" .. sanitize(func.name) .. ":stencil_store:" .. sanitize(loop_fact.loop.text))
        return LJ.LJMachine(id, LJ.LJMachineStencilEffect(artifact, stencil_args(ctx, artifact, selection.args)), nil, LJ.LJStateScalar, LJ.LJTraceHot), nil
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
        if step_num == nil or step_num <= 0 then return nil, "reduction stencil requires a positive constant step" end
        local classified, reason = classify_store_expr(Kernel.KernelExprAlgebra(reduction.contribution), binding_index(plan.body))
        if classified == nil then return nil, reason end
        local start_expr, stop_expr = value_id_expr(ctx, loop_fact.counted.start), value_id_expr(ctx, loop_fact.counted.stop)
        local init_expr = value_expr(ctx, reduction.init)
        local class, class_reason = enrich_stencil_class(ctx, classified, loop_fact, binding_index(plan.body), nil, nil)
        if class == nil then return nil, class_reason end
        local i32 = Code.CodeTyInt(32, Code.CodeSigned)
        local selection_ctx = {
            step_num = step_num,
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
            counted_positive = step_num ~= nil and step_num > 0,
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
        local artifact = select_reduction_artifact(opts, func, selection.vocab, selection.op, reduction, plan, selection.info)
        if artifact == nil then return nil, "reduction stencil artifact provider did not select an artifact" end
        local id = LJ.LJMachineId("machine:" .. sanitize(func.name) .. ":stencil_reduce:" .. sanitize(loop_fact.loop.text))
        return LJ.LJMachine(id, LJ.LJMachineStencilCall(artifact, stencil_args(ctx, artifact, selection.args), physical(ctx, reduction.ty)), physical(ctx, reduction.ty), LJ.LJStateScalar, LJ.LJTraceHot), nil
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

    local function select_skeleton_artifact(opts, func, vocab, op, reduction, plan, info)
        if opts.stencil_skeleton_artifact_for ~= nil then return opts.stencil_skeleton_artifact_for(func, vocab, op, reduction, plan, info) end
        return nil
    end

    local function skeleton_scan_plan(ctx, func, plan, graph_loop, loop_fact)
        local effect, effect_reason = single_effect(plan.body, Kernel.KernelEffectScan)
        if effect == nil then return nil, effect_reason end
        local result = plan.body.result
        if pvm.classof(result) ~= Kernel.KernelResultReduction then return nil, "scan skeleton requires reduction result" end
        local reduction = effect.reduction
        if result.reduction ~= reduction then return nil, "scan result reduction does not match scan effect" end
        if not function_returns_reduction(func, graph_loop, reduction) then return nil, "function return is not the scan final value" end
        local dst_base = stream_base_value(effect.dst)
        if dst_base == nil then return nil, "scan destination stream has no value base" end
        local dst_fact = stream_selection_fact(ctx, effect.dst)
        local bindings = binding_index(plan.body)
        local class, class_reason = enriched_class_for_expr(ctx, Kernel.KernelExprAlgebra(reduction.contribution), loop_fact, bindings, dst_base, effect.dst.elem_ty)
        if class == nil then return nil, class_reason end
        local start_expr, stop_expr = value_id_expr(ctx, loop_fact.counted.start), value_id_expr(ctx, loop_fact.counted.stop)
        local step_num = const_int_value(ctx, loop_fact.counted.step)
        local selection, select_reason = StencilRules.select_scan {
            step_num = step_num,
            dst_elem_ty = effect.dst.elem_ty,
            result_ty = reduction.ty,
            dst = dst_base,
            dst_expr = value_id_expr(ctx, dst_base),
            dst_topology = dst_fact and dst_fact.topology or nil,
            start = loop_fact.counted.start,
            stop = loop_fact.counted.stop,
            start_expr = start_expr,
            stop_expr = stop_expr,
            store_index_primary = expr_is_primary(effect.index, loop_fact),
            reduction = reduction,
            reduction_kind = reduction.kind,
            init = reduction.init,
            init_expr = value_expr(ctx, reduction.init),
            mode = effect.mode,
            class = class,
        }
        if selection == nil then return nil, select_reason end
        return { kind = "scan", selection = selection, reduction = reduction, result_ty = reduction.ty }, nil
    end

    local function skeleton_find_plan(ctx, func, plan, graph_loop, loop_fact)
        local result = plan.body.result
        if pvm.classof(result) ~= Kernel.KernelResultFind then return nil, "kernel result is not find" end
        if graph_loop == nil then return nil, "find skeleton requires a graph loop" end
        local bindings = binding_index(plan.body)
        local class, class_reason = enriched_class_for_expr(ctx, result.src, loop_fact, bindings, nil, nil)
        if class == nil then return nil, class_reason end
        local step_num = const_int_value(ctx, loop_fact.counted.step)
        local selection, select_reason = StencilRules.select_find {
            step_num = step_num,
            start = loop_fact.counted.start,
            stop = loop_fact.counted.stop,
            start_expr = value_id_expr(ctx, loop_fact.counted.start),
            stop_expr = value_id_expr(ctx, loop_fact.counted.stop),
            pred = result.pred,
            not_found_minus_one = is_minus_one_const(result.not_found),
            class = class,
        }
        if selection == nil then return nil, select_reason end
        return { kind = "find", selection = selection, result_ty = Code.CodeTyInt(32, Code.CodeSigned) }, nil
    end

    local function skeleton_partition_plan(ctx, func, plan, graph_loop, loop_fact)
        local effect, effect_reason = single_effect(plan.body, Kernel.KernelEffectPartition)
        if effect == nil then return nil, effect_reason end
        local dst_base = stream_base_value(effect.dst)
        if dst_base == nil then return nil, "partition destination stream has no value base" end
        local dst_fact = stream_selection_fact(ctx, effect.dst)
        local bindings = binding_index(plan.body)
        local class, class_reason = enriched_class_for_expr(ctx, effect.src, loop_fact, bindings, dst_base, effect.dst.elem_ty)
        if class == nil then return nil, class_reason end
        local step_num = const_int_value(ctx, loop_fact.counted.step)
        local selection, select_reason = StencilRules.select_partition {
            step_num = step_num,
            dst_elem_ty = effect.dst.elem_ty,
            dst = dst_base,
            dst_expr = value_id_expr(ctx, dst_base),
            dst_topology = dst_fact and dst_fact.topology or nil,
            start = loop_fact.counted.start,
            stop = loop_fact.counted.stop,
            start_expr = value_id_expr(ctx, loop_fact.counted.start),
            stop_expr = value_id_expr(ctx, loop_fact.counted.stop),
            store_index_primary = true,
            pred = effect.pred,
            semantics = effect.semantics,
            class = class,
        }
        if selection == nil then return nil, select_reason end
        return { kind = "partition", selection = selection, result_ty = Code.CodeTyInt(32, Code.CodeSigned) }, nil
    end

    local function skeleton_copy_plan(ctx, func, plan, graph_loop, loop_fact)
        local effect, effect_reason = single_effect(plan.body, Kernel.KernelEffectCopy)
        if effect == nil then return nil, effect_reason end
        local dst_base = stream_base_value(effect.dst)
        if dst_base == nil then return nil, "copy destination stream has no value base" end
        local dst_fact = stream_selection_fact(ctx, effect.dst)
        local bindings = binding_index(plan.body)
        local class, class_reason = enriched_class_for_expr(ctx, effect.src, loop_fact, bindings, dst_base, effect.dst.elem_ty)
        if class == nil then return nil, class_reason end
        local step_num = const_int_value(ctx, loop_fact.counted.step)
        local selection, select_reason = StencilRules.select_store {
            step_num = step_num,
            dst_elem_ty = effect.dst.elem_ty,
            dst = dst_base,
            dst_expr = value_id_expr(ctx, dst_base),
            dst_topology = dst_fact and dst_fact.topology or nil,
            start = loop_fact.counted.start,
            stop = loop_fact.counted.stop,
            start_expr = value_id_expr(ctx, loop_fact.counted.start),
            stop_expr = value_id_expr(ctx, loop_fact.counted.stop),
            store_index_primary = true,
            copy_semantics = effect.semantics,
            class = class,
        }
        if selection == nil then return nil, select_reason end
        return { kind = "copy", selection = selection, result_ty = nil }, nil
    end

    local function stencil_skeleton_plan(ctx, func, plan, graph_loop, loop_fact)
        if pvm.classof(plan) ~= Kernel.KernelPlanned then return nil, "kernel is not planned" end
        if loop_fact == nil or loop_fact.counted == nil then return nil, "stencil skeleton requires counted loop" end
        local step_num = const_int_value(ctx, loop_fact.counted.step)
        if step_num == nil or step_num <= 0 then return nil, "stencil skeleton requires a positive constant step" end
        local planned, reason = skeleton_scan_plan(ctx, func, plan, graph_loop, loop_fact)
        if planned ~= nil then return planned, nil end
        planned, reason = skeleton_find_plan(ctx, func, plan, graph_loop, loop_fact)
        if planned ~= nil then return planned, nil end
        planned, reason = skeleton_partition_plan(ctx, func, plan, graph_loop, loop_fact)
        if planned ~= nil then return planned, nil end
        planned, reason = skeleton_copy_plan(ctx, func, plan, graph_loop, loop_fact)
        if planned ~= nil then return planned, nil end
        return nil, reason or "no stencil skeleton selected"
    end

    local function lower_kernel_stencil_skeleton(ctx, func, plan, graph_loop, loop_fact, opts)
        if opts.stencil_skeleton_artifact_for == nil then return nil, "no skeleton stencil artifact provider" end
        local planned, reason = stencil_skeleton_plan(ctx, func, plan, graph_loop, loop_fact)
        if planned == nil then return nil, reason end
        local selection = planned.selection
        local artifact = select_skeleton_artifact(opts, func, selection.vocab, selection.op, planned.reduction, plan, selection.info)
        if artifact == nil then return nil, "skeleton stencil artifact provider did not select an artifact" end
        local id = LJ.LJMachineId("machine:" .. sanitize(func.name) .. ":stencil_skeleton:" .. sanitize(loop_fact.loop.text))
        if planned.result_ty ~= nil then
            local result_ty = physical(ctx, planned.result_ty)
            return LJ.LJMachine(id, LJ.LJMachineStencilCall(artifact, stencil_args(ctx, artifact, selection.args), result_ty), result_ty, LJ.LJStateScalar, LJ.LJTraceHot), nil
        end
        return LJ.LJMachine(id, LJ.LJMachineStencilEffect(artifact, stencil_args(ctx, artifact, selection.args)), nil, LJ.LJStateScalar, LJ.LJTraceHot), nil
    end

    local function counted_positive(ctx, loop_fact)
        if loop_fact == nil or loop_fact.counted == nil then return false end
        local step_num = const_int_value(ctx, loop_fact.counted.step)
        return step_num ~= nil and step_num > 0
    end

    local function kernel_lowering_candidate(ctx, func, plan, graph_loop, loop_fact, loop_owner, kernel, opts)
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
        local vector_ready = false
        local vector_reason = nil
        if planned then
            local ready
            ready, vector_reason = vector_reduce_plan(ctx, func, plan, graph_loop, loop_fact, kernel)
            vector_ready = ready ~= nil
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
            store_dst_base = store ~= nil and stream_base_value(store.dst) ~= nil
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
            vector_reduce_ready = vector_ready,
            vector_reject = vector_reason,
            store_reject = store_reason,
        }
    end

    local function lower_blocks_func(ctx, func)
        local blocks = {}
        for i, block in ipairs(func.blocks or {}) do blocks[i] = lower_block(ctx, block) end
        return {}, LJ.LJBodyBlocks(bid(func.entry), blocks)
    end

    local function lower_func(module_ctx, func, kernel, graph_loops, flow_loops, loop_func, opts)
        local ctx = {
            code_sigs = module_ctx.code_sigs,
            mem_objects = module_ctx.mem_objects,
            value_types = {},
            defs = value_defs(func),
        }
        note_params(ctx, func.params)
        for _, block in ipairs(func.blocks or {}) do note_params(ctx, block.params) end
        local params = lower_params(ctx, func.params)
        local machines, body = nil, nil
        local function plan_domain_loop(plan)
            local body = plan and plan.body or nil
            local domain = body and body.domain and body.domain.domain or nil
            if pvm.classof(domain) == Flow.FlowDomainLoop then return domain.loop end
            return nil
        end
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
                local candidate = kernel_lowering_candidate(ctx, func, plan, graph_loop, loop_fact, owner, kernel, opts)
                local selection, reason = LowerRules.select(candidate)
                if selection == nil then
                    if candidate.result_reduction then
                        reason = candidate.vector_reject or candidate.stencil_reduce_reject or reason
                    elseif candidate.stencil_skeleton_reject then
                        reason = candidate.stencil_skeleton_reject
                    elseif candidate.single_store then
                        reason = candidate.stencil_store_reject or candidate.store_reject or reason
                    end
                end
                local machine = nil
                if selection ~= nil then
                    if selection.kind == "stencil_reduce" then
                        machine, reason = lower_kernel_stencil_reduce(ctx, func, plan, graph_loop, loop_fact, opts)
                    elseif selection.kind == "vector_reduce" then
                        machine, reason = lower_kernel_vector_reduce(ctx, func, plan, graph_loop, loop_fact, kernel, opts)
                    elseif selection.kind == "stencil_store" then
                        machine, reason = lower_kernel_stencil_store(ctx, func, plan, graph_loop, loop_fact, opts)
                    elseif selection.kind == "stencil_skeleton" then
                        machine, reason = lower_kernel_stencil_skeleton(ctx, func, plan, graph_loop, loop_fact, opts)
                    else
                        reason = "unknown LuaJIT lowering strategy " .. tostring(selection.kind)
                    end
                end
                if machine ~= nil then
                    machines = { machine }
                    body = LJ.LJBodyMachine(machine.id, LJ.LJTerminalFirst(nil))
                    break
                elseif opts.collect_rejects ~= nil then
                    opts.collect_rejects[#opts.collect_rejects + 1] = { func = func.id, loop = subject.loop, reason = reason }
                end
            end
        end
        if body == nil then machines, body = lower_blocks_func(ctx, func) end
        return LJ.LJFunc(fid(func.id), func.id, func.name, sigid(func.sig), params, {}, machines, body, LJ.LJTraceHot)
    end

    local function build_kernel(module, opts)
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
        local graph_loops, loop_func = graph_loop_index(graph)
        local flow_loops = flow_loop_index(flow)
        local module_ctx = { code_sigs = code_sigs(module), mem_objects = mem_object_index(mem) }
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

    T._moonlift_api_cache.luajit_lower = api
    return api
end

return bind_context
