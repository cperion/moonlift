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
    local StencilRules = require("moonlift.stencil_rules")(T)
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

    local function pattern_topology(pattern)
        local cls = pvm.classof(pattern)
        if pattern == Mem.MemAccessContiguous then return Stencil.StencilTopologyContiguous(1) end
        if cls == Mem.MemAccessStrided then return Stencil.StencilTopologyContiguous(pattern.stride_elems) end
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

    local function lane_topology(ctx, lane)
        local object = ctx.mem_objects and lane and ctx.mem_objects[lane.object.text] or nil
        local base_value = lane_base_value(lane)
        local soa_contract = base_value and ctx.soa_contracts and ctx.func_id and ctx.soa_contracts[ctx.func_id.text .. "\0" .. base_value.text] or nil
        local function wrap_soa(topology)
            if soa_contract == nil or topology == nil then return topology end
            return Stencil.StencilTopologySoAComponent(topology, soa_contract.record_ty, soa_contract.field_name, soa_contract.component_index)
        end
        if object ~= nil then
            local provenance = object.provenance
            local pcls = pvm.classof(provenance)
            if object.kind == Mem.MemObjectDerived and pcls == Mem.MemProvProjection and provenance.projection == Mem.MemProjectField then
                local parent = ctx.mem_objects and ctx.mem_objects[provenance.parent.text] or nil
                local parent_topology = lane_topology(ctx, {
                    object = provenance.parent,
                    base = lane and lane.base,
                    pattern = lane and lane.pattern,
                    accesses = lane and lane.accesses,
                })
                local record_ty = parent and parent.elem_ty or nil
                local field_name = field_name_from_lane(ctx, lane)
                if parent_topology ~= nil and record_ty ~= nil and field_name ~= nil then
                    return wrap_soa(Stencil.StencilTopologyFieldProjection(parent_topology, record_ty, field_name, provenance.byte_offset or 0))
                end
            end
            if object.kind == Mem.MemObjectView and pcls == Mem.MemProvView then
                if provenance.stride == nil then return nil end
                return wrap_soa(Stencil.StencilTopologyViewDescriptor(
                    provenance.view,
                    provenance.data,
                    extent_len(object.extent) or provenance.len,
                    provenance.stride,
                    mem_stride_const(object.stride)
                ))
            end
            if object.kind == Mem.MemObjectSlice and pcls == Mem.MemProvSlice then
                return wrap_soa(Stencil.StencilTopologySliceDescriptor(
                    provenance.slice,
                    provenance.data,
                    extent_len(object.extent) or provenance.len
                ))
            end
            if object.kind == Mem.MemObjectByteSpan and pcls == Mem.MemProvByteSpan then
                return wrap_soa(Stencil.StencilTopologyByteSpanDescriptor(
                    provenance.span,
                    provenance.data,
                    extent_len(object.extent) or provenance.len
                ))
            end
        end
        return wrap_soa(pattern_topology(lane and lane.pattern))
    end

    local function topology_data_value(topology)
        local cls = pvm.classof(topology)
        if cls == Stencil.StencilTopologySoAComponent or cls == Stencil.StencilTopologyFieldProjection then return topology_data_value(topology.parent) end
        if cls == Stencil.StencilTopologyViewDescriptor or cls == Stencil.StencilTopologySliceDescriptor or cls == Stencil.StencilTopologyByteSpanDescriptor then return topology.data end
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

    local function bound_algebra_expr(bindings, value)
        local binding = value and bindings and bindings["kval:" .. value.text] or nil
        if binding ~= nil and pvm.classof(binding.expr) == Kernel.KernelExprAlgebra then return binding.expr.expr end
        return nil
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
        local topology = lane_topology(ctx, lane)
        if topology == nil then return nil end
        local base = lane_base_value(lane)
        local tcls = pvm.classof(topology)
        base = topology_data_value(topology) or base
        if base == nil then return nil end
        return {
            base = base,
            base_expr = value_id_expr(ctx, base),
            elem_ty = lane.elem_ty,
            topology = topology,
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
            class.src_topology = fact.topology
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
                            topology = idx_fact.topology,
                            index_primary = expr_is_primary(ctx, idx.index, graph_loop, loop_fact, bindings),
                        }
                    end
                end
            end
        else
            class[prefix .. "_base"] = fact.base
            class[prefix .. "_expr"] = fact.base_expr
            class[prefix .. "_ty"] = fact.elem_ty
            class[prefix .. "_topology"] = fact.topology
            class[prefix .. "_index_primary"] = expr_is_primary(ctx, index, graph_loop, loop_fact, bindings)
        end
        return class
    end

    local function enrich_stencil_class(ctx, class, graph_loop, loop_fact, bindings, dst_base, dst_ty)
        if class.kind == "load" or class.kind == "map" or class.kind == "cast" or class.kind == "compare" then
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

    local function stencil_store_plan(ctx, func, plan, graph_loop, loop_fact)
        if pvm.classof(plan) ~= Kernel.KernelPlanned then return nil, "kernel is not planned" end
        if not function_returns_void_from_loop(func, graph_loop) then return nil, "store stencil requires loop exit to return void" end
        if loop_fact == nil or loop_fact.counted == nil then return nil, "store stencil requires counted loop" end
        local step_num = const_int_value(ctx, loop_fact.counted.step)
        if step_num == nil or step_num <= 0 then return nil, "store stencil requires a positive constant step" end
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
        local class, class_reason = enrich_stencil_class(ctx, classified, graph_loop, loop_fact, bindings, dst_base, store.dst.elem_ty)
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
            store_index_lane = store_index_is_primary and nil or index_lane_selection_fact(ctx, store.index, graph_loop, loop_fact, bindings),
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

    local function dynamic_stride_topology(topology)
        local cls = pvm.classof(topology)
        if cls == Stencil.StencilTopologyFieldProjection then return dynamic_stride_topology(topology.parent) end
        if cls == Stencil.StencilTopologySoAComponent then return dynamic_stride_topology(topology.parent) end
        if cls == Stencil.StencilTopologyViewDescriptor and topology.stride_const == nil then return topology end
        return nil
    end

    local function stencil_args(ctx, artifact, args)
        local out = {}
        for i = 1, #(args or {}) do out[i] = args[i] end
        local desc = artifact and artifact.instance and artifact.instance.descriptor or nil
        for _, access in ipairs(desc and desc.accesses or {}) do
            local top = dynamic_stride_topology(access.topology)
            if top ~= nil then
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
        if step_num == nil or step_num <= 0 then return nil, "reduction stencil requires a positive constant step" end
        local classified, reason = classify_store_expr(Kernel.KernelExprAlgebra(reduction.contribution), binding_index(plan.body))
        if classified == nil then return nil, reason end
        local start_expr, stop_expr = value_id_expr(ctx, loop_fact.counted.start), value_id_expr(ctx, loop_fact.counted.stop)
        local init_expr = value_expr(ctx, reduction.init)
        local class, class_reason = enrich_stencil_class(ctx, classified, graph_loop, loop_fact, binding_index(plan.body), nil, nil)
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
        if not function_returns_reduction(func, graph_loop, reduction) then return nil, "function return is not the scan final value" end
        local dst_base = lane_base_value(effect.dst)
        if dst_base == nil then return nil, "scan destination lane has no value base" end
        local dst_fact = lane_selection_fact(ctx, effect.dst)
        local bindings = binding_index(plan.body)
        local class, class_reason = enriched_class_for_expr(ctx, Kernel.KernelExprAlgebra(reduction.contribution), graph_loop, loop_fact, bindings, dst_base, effect.dst.elem_ty)
        if class == nil then return nil, class_reason end
        local start_expr, stop_expr = value_id_expr(ctx, loop_fact.counted.start), value_id_expr(ctx, loop_fact.counted.stop)
        local step_num = const_int_value(ctx, loop_fact.counted.step)
        local selection, select_reason = run_stencil_selection("select_scan_stencil", {
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
            store_index_primary = expr_is_primary(ctx, effect.index, graph_loop, loop_fact, bindings),
            reduction = reduction,
            reduction_kind = reduction.kind,
            init = reduction.init,
            init_expr = value_expr(ctx, reduction.init),
            mode = effect.mode,
            class = class,
        }, "unsupported scan stencil shape")
        if selection == nil then return nil, select_reason end
        return { kind = "scan", selection = selection, reduction = reduction, result_ty = reduction.ty }, nil
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
        local selection, select_reason = run_stencil_selection("select_store_stencil", {
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
        }, "unsupported store stencil shape")
        if selection == nil then return nil, select_reason end
        return { kind = "copy", selection = selection, result_ty = nil }, nil
    end

    local function stencil_skeleton_plan(ctx, func, plan, graph_loop, loop_fact)
        if pvm.classof(plan) ~= Kernel.KernelPlanned then return nil, "kernel is not planned" end
        if loop_fact == nil or loop_fact.counted == nil then return nil, "stencil skeleton requires counted loop" end
        local step_num = const_int_value(ctx, loop_fact.counted.step)
        if step_num == nil or step_num <= 0 then return nil, "stencil skeleton requires a positive constant step" end
        local scan, scan_reason = skeleton_scan_plan(ctx, func, plan, graph_loop, loop_fact)
        local find, find_reason = skeleton_find_plan(ctx, func, plan, graph_loop, loop_fact)
        local partition, partition_reason = skeleton_partition_plan(ctx, func, plan, graph_loop, loop_fact)
        local copy, copy_reason = skeleton_copy_plan(ctx, func, plan, graph_loop, loop_fact)
        local reject_reason = scan_reason or find_reason or partition_reason or copy_reason or "no stencil skeleton selected"
        local selection, err = LowerRules:run("select_skeleton_lowering", { skeleton = {
            scan_ready = scan ~= nil,
            scan_plan = scan,
            find_ready = find ~= nil,
            find_plan = find,
            partition_ready = partition ~= nil,
            partition_plan = partition,
            copy_ready = copy ~= nil,
            copy_plan = copy,
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
        local artifact = select_skeleton_artifact(opts, func, selection.vocab, selection.op, planned.reduction, plan, selection.info)
        if artifact == nil then return nil, "skeleton stencil artifact provider did not select an artifact" end
        local id = LJ.LJMachineId("machine:" .. sanitize(func.name) .. ":stencil_skeleton:" .. sanitize(loop_fact.loop.text))
        if planned.result_ty ~= nil then
            local result_ty = physical(ctx, planned.result_ty)
            return LJ.LJMachine(id, LJ.LJMachineStencilCall(artifact, stencil_args(ctx, artifact, selection.args), result_ty), result_ty, LJ.LJStateScalar, LJ.LJTraceHot), nil
        end
        return LJ.LJMachine(id, LJ.LJMachineStencilEffect(artifact, stencil_args(ctx, artifact, selection.args)), nil, LJ.LJStateScalar, LJ.LJTraceHot), nil
    end

    local function plan_kernel_stencil_skeleton(ctx, func, plan, graph_loop, loop_fact, opts)
        return lower_kernel_stencil_skeleton(ctx, func, plan, graph_loop, loop_fact, opts)
    end

    local function counted_positive(ctx, loop_fact)
        if loop_fact == nil or loop_fact.counted == nil then return false end
        local step_num = const_int_value(ctx, loop_fact.counted.step)
        return step_num ~= nil and step_num > 0
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
        elseif result_reduction and not stencil_skeleton_ready then
            reject_reason = stencil_reduce_reason or reject_reason
        elseif stencil_skeleton_reason ~= nil then
            reject_reason = stencil_skeleton_reason
        elseif single_store then
            reject_reason = stencil_store_reason or store_reason or reject_reason
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
            flow = flow,
        }
    end

    local function func_lower_ctx(module_ctx, func)
        local ctx = {
            code_sigs = module_ctx.code_sigs,
            mem_objects = module_ctx.mem_objects,
            mem_accesses = module_ctx.mem_accesses,
            soa_contracts = module_ctx.soa_contracts,
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
                pending_rejects[#pending_rejects + 1] = { func = func.id, loop = loop_id, reason = reason }
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
            plan = LJ.LJStencilMachineModulePlan(module.id, opts.stencil_plan or T.MoonStencil.StencilModulePlan(module.id, kernel, {}), plans),
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
                if pvm.classof(plan) == Kernel.KernelPlanned then
                    local result = plan.body and plan.body.result or nil
                    local stencil_shaped = pvm.classof(result) == Kernel.KernelResultReduction
                        or pvm.classof(result) == Kernel.KernelResultFind
                    for _, eff in ipairs(plan.body and plan.body.effects or {}) do
                        local ecls = pvm.classof(eff)
                        if ecls == Kernel.KernelEffectStore
                            or ecls == Kernel.KernelEffectScan
                            or ecls == Kernel.KernelEffectPartition
                            or ecls == Kernel.KernelEffectCopy then
                            stencil_shaped = true
                            break
                        end
                    end
                    if stencil_shaped then
                        opts.collect_rejects[#opts.collect_rejects + 1] = {
                            func = nil,
                            loop = nil,
                            reason = "missing preplanned stencil machine; run stencil planning with an artifact provider before LuaJIT projection",
                        }
                    end
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

    T._moonlift_api_cache.luajit_lower = api
    return api
end

return bind_context
