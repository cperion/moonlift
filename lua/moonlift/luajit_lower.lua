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
        if cls == Code.CodeInstAlias or cls == Code.CodeInstBinary or cls == Code.CodeInstFloatBinary or cls == Code.CodeInstSelect or cls == Code.CodeInstAggregate or cls == Code.CodeInstArray then return k.ty end
        if cls == Code.CodeInstCompare then return Code.CodeTyBool8 end
        if cls == Code.CodeInstCast then return k.to end
        if cls == Code.CodeInstLoad then return k.access.ty end
        if cls == Code.CodeInstViewMake then return Code.CodeTyView(k.elem_ty) end
        if cls == Code.CodeInstViewLen or cls == Code.CodeInstViewStride then return Code.CodeTyIndex end
        if cls == Code.CodeInstViewData then return Code.CodeTyDataPtr(nil) end
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

    local function is_luajit_scalar_reduction(kind)
        return kind == Value.ReductionAdd
            or kind == Value.ReductionMul
            or kind == Value.ReductionAnd
            or kind == Value.ReductionOr
            or kind == Value.ReductionXor
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

    local function lower_kernel_vector_reduce(ctx, func, plan, graph_loop, loop_fact, kernel, opts)
        if pvm.classof(plan) ~= Kernel.KernelPlanned then return nil, "kernel is not planned" end
        local result = plan.body.result
        if pvm.classof(result) ~= Kernel.KernelResultReduction then return nil, "kernel result is not a reduction" end
        local reduction = result.reduction
        if not function_returns_reduction(func, graph_loop, reduction) then return nil, "function return is not the kernel reduction" end
        if not is_luajit_scalar_reduction(reduction.kind) then return nil, "LuaJIT vector reduce currently supports add/mul/min/max/bitwise reductions only" end
        local ty_cls = pvm.classof(reduction.ty)
        if ty_cls ~= Code.CodeTyInt or (reduction.ty.bits ~= 8 and reduction.ty.bits ~= 16 and reduction.ty.bits ~= 32) then return nil, "LuaJIT vector reduce scalar fallback currently supports 8/16/32-bit integer reductions only" end
        if (reduction.kind == Value.ReductionAdd or reduction.kind == Value.ReductionMul) and (reduction.int_semantics == nil or reduction.int_semantics.overflow ~= Code.CodeIntWrap) then
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
        local id = LJ.LJMachineId("machine:" .. sanitize(func.name) .. ":vreduce:" .. sanitize(loop_fact.loop.text))
        local artifact = nil
        if opts.stencil_artifact_for ~= nil then
            artifact = opts.stencil_artifact_for(func, reduction, plan, {
                array = base.addr,
                start = loop_fact.counted.start,
                stop = loop_fact.counted.stop,
                step = loop_fact.counted.step,
                step_num = step_num,
                elem_ty = load.access.ty,
                result_ty = reduction.ty,
                init = reduction.init,
            })
        end
        if artifact ~= nil then
            return LJ.LJMachine(
                id,
                LJ.LJMachineStencilCall(
                    artifact,
                    {
                        value_id_expr(ctx, base.addr),
                        value_id_expr(ctx, loop_fact.counted.start),
                        value_id_expr(ctx, loop_fact.counted.stop),
                        value_expr(ctx, reduction.init),
                    },
                    physical(ctx, reduction.ty)
                ),
                physical(ctx, reduction.ty),
                LJ.LJStateScalar,
                LJ.LJTraceHot
            ), nil
        end
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

    local function lower_blocks_func(ctx, func)
        local blocks = {}
        for i, block in ipairs(func.blocks or {}) do blocks[i] = lower_block(ctx, block) end
        return {}, LJ.LJBodyBlocks(bid(func.entry), blocks)
    end

    local function lower_func(module_ctx, func, kernel, graph_loops, flow_loops, loop_func, opts)
        local ctx = {
            code_sigs = module_ctx.code_sigs,
            value_types = {},
            defs = value_defs(func),
        }
        note_params(ctx, func.params)
        for _, block in ipairs(func.blocks or {}) do note_params(ctx, block.params) end
        local params = lower_params(ctx, func.params)
        local machines, body = nil, nil
        for _, plan in ipairs(kernel.plans or {}) do
            local subject = plan.subject
            if pvm.classof(subject) == Kernel.KernelSubjectLoop and loop_func[subject.loop.text] == func.id then
                local machine, reason = lower_kernel_vector_reduce(ctx, func, plan, graph_loops[subject.loop.text], flow_loops[subject.loop.text], kernel, opts)
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
        local module_ctx = { code_sigs = code_sigs(module) }
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
