local asdl = require("lalin.asdl")

local function class_name(value)
    local cls = asdl.classof(value) or value
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
    local SM = T.LalinStencilMachine
    local Stencil = T.LalinStencil

    local CType = require("lalin.luajit_ctype")(T)
    local Expr = require("lalin.luajit_expr")(T)
    local CodeGraph = require("lalin.code_graph")(T)
    local CodeFlowFacts = require("lalin.code_flow_facts")(T)
    local CodeValueFacts = require("lalin.code_value_facts")(T)
    local CodeMemFacts = require("lalin.code_mem_facts")(T)
    local CodeEffectFacts = require("lalin.code_effect_facts")(T)
    local CodeKernelPlan = require("lalin.code_kernel_plan")(T)
    local StencilMethods = require("lalin.stencil_methods")(T)
    local StencilArtifactPlan = require("lalin.stencil_artifact_plan")(T)

    local api = {}

    function Kernel.KernelPlan:luajit_kernel_body() return nil end
    function Kernel.KernelPlanned:luajit_kernel_body()
        local body = rawget(self, "body")
        return type(body) == "table" and body or nil
    end

    local function kernel_plan_body(plan)
        return plan and plan:luajit_kernel_body() or nil
    end

    function SM.StencilMachineKernelInput:select_stencil_machine_kernel()
        local ready = self.loop_plan and self.owns_loop and self.planned and self.counted_positive
        if ready and self.has_skeleton_provider and self.stencil_skeleton_ready then
            return SM.StencilMachineKernelSkeleton
        end
        if ready
            and self.has_store_provider
            and self.returns_void
            and self.single_store
            and self.store_dst_base
            and not self.stencil_skeleton_ready
            and self.stencil_store_ready
        then
            return SM.StencilMachineKernelStore
        end
        if ready
            and self.has_reduce_provider
            and self.result_reduction
            and self.returns_reduction
            and not self.stencil_skeleton_ready
            and self.stencil_reduce_ready
        then
            return SM.StencilMachineKernelReduce
        end
        return SM.StencilMachineKernelNoPlan(self.reject_reason)
    end

    function SM.StencilMachineSkeletonInput:select_stencil_machine_skeleton()
        for _, candidate in ipairs(self.candidates or {}) do
            return candidate:select_stencil_machine_skeleton_candidate()
        end
        return SM.StencilMachineSkeletonNoPlan(self.reject_reason)
    end

    function SM.StencilMachineSkeletonCandidate:select_stencil_machine_skeleton_candidate()
        return SM.StencilMachineSkeletonNoPlan("unsupported stencil skeleton candidate")
    end

    function SM.StencilMachineSkeletonScanCandidate:select_stencil_machine_skeleton_candidate()
        return SM.StencilMachineSkeletonScan(self.planned)
    end
    function SM.StencilMachineSkeletonFindCandidate:select_stencil_machine_skeleton_candidate()
        return SM.StencilMachineSkeletonFind(self.planned)
    end
    function SM.StencilMachineSkeletonPartitionCandidate:select_stencil_machine_skeleton_candidate()
        return SM.StencilMachineSkeletonPartition(self.planned)
    end
    function SM.StencilMachineSkeletonCopyCandidate:select_stencil_machine_skeleton_candidate()
        return SM.StencilMachineSkeletonCopy(self.planned)
    end
    function SM.StencilMachineSkeletonScatterReduceCandidate:select_stencil_machine_skeleton_candidate()
        return SM.StencilMachineSkeletonScatterReduce(self.planned)
    end

    function SM.StencilMachineSkeletonReductionFact:stencil_machine_artifact_reduction()
        return self.reduction
    end

    function SM.StencilMachineSkeletonReducer:stencil_machine_artifact_reduction()
        return {
            op = self.reducer.reduction,
            int_semantics = self.reducer.int_semantics,
            float_mode = self.reducer.float_mode,
        }
    end

    function SM.StencilMachineSelected:select_stencil_artifact(provider, func, reduction, plan)
        return nil
    end
    function SM.StencilMachineSelectStoreN:select_stencil_artifact(provider, func, reduction, plan)
        return provider(func, "store_n", self:stencil_artifact_op(), reduction, plan, self:stencil_artifact_descriptor())
    end
    function SM.StencilMachineSelectReduceN:select_stencil_artifact(provider, func, reduction, plan)
        return provider(func, "reduce_n", self:stencil_artifact_op(), reduction, plan, self:stencil_artifact_descriptor())
    end
    function SM.StencilMachineSelectScan:select_stencil_artifact(provider, func, reduction, plan)
        return provider(func, "scan", self:stencil_artifact_op(), reduction, plan, self:stencil_artifact_descriptor())
    end
    function SM.StencilMachineSelectFind:select_stencil_artifact(provider, func, reduction, plan)
        return provider(func, "find", self:stencil_artifact_op(), reduction, plan, self:stencil_artifact_descriptor())
    end
    function SM.StencilMachineSelectPartition:select_stencil_artifact(provider, func, reduction, plan)
        return provider(func, "partition", self:stencil_artifact_op(), reduction, plan, self:stencil_artifact_descriptor())
    end
    function SM.StencilMachineSelectCount:select_stencil_artifact(provider, func, reduction, plan)
        return provider(func, "count", self:stencil_artifact_op(), reduction, plan, self:stencil_artifact_descriptor())
    end
    function SM.StencilMachineSelectScatterReduce:select_stencil_artifact(provider, func, reduction, plan)
        return provider(func, "scatter_reduce", self:stencil_artifact_op(), reduction, plan, self:stencil_artifact_descriptor())
    end

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
        if asdl.classof(contracts) == Code.CodeContractFactSet then return contracts.facts or {} end
        return contracts
    end

    local function soa_contract_index(contracts)
        local out = {}
        for _, fact in ipairs(contract_facts(contracts)) do
            local k = fact.fact
            if asdl.classof(k) == Code.CodeContractSoAComponent then
                out[fact.func.text .. "\0" .. k.base.text] = k
            end
        end
        return out
    end

    local function flow_domain_key(domain)
        local cls = asdl.classof(domain)
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
        local cls = asdl.classof(shape)
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
        local cls = asdl.classof(origin)
        if origin == Flow.FlowFactCheckerDerived then return Stencil.StencilProducerCheckerDerived end
        if cls == Flow.FlowFactAuthorAsserted then return Stencil.StencilProducerAuthorAsserted(origin.reason) end
        if cls == Flow.FlowFactFrontendFact then return Stencil.StencilProducerFrontendFact(origin.reason) end
        return Stencil.StencilProducerCheckerDerived
    end

    local function kernel_proof_from_flow_proof(domain, proof)
        local cls = asdl.classof(proof)
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
                local k = inst.op
                local dst = rawget(k, "dst")
                if dst ~= nil then defs[dst.text] = { inst = inst, op = k } end
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
        local k = def.op
        local cls = asdl.classof(k)
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
        if def ~= nil and asdl.classof(def.op) == Code.CodeInstConst and asdl.classof(def.op.const) == Code.CodeConstLiteral then
            return LJ.LJExprLiteral(def.op.const.literal, physical(ctx, def.op.const.ty))
        end
        return LJ.LJExprValue(vid(id))
    end

    local function captured_closure_descriptor(ctx, id)
        local def = ctx.defs and id and ctx.defs[id.text] or nil
        local k = def and def.op or nil
        if asdl.classof(k) ~= Code.CodeInstAggregate then return false end
        if asdl.classof(k.ty) ~= Code.CodeTyClosure then return false end
        return #(k.fields or {}) > 1
    end

    local value_expr
    value_expr = function(ctx, expr)
        local cls = asdl.classof(expr)
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
        local k = def and def.op
        local cls = asdl.classof(k)
        if cls == Code.CodeInstConst and asdl.classof(k.const) == Code.CodeConstLiteral then
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
        if asdl.classof(expr) == Value.ValueExprValue then return producer_value_id_expr(ctx, expr.value) end
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
        local k = term.op
        local cls = asdl.classof(k)
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
        local k = def and def.op
        local cls = asdl.classof(k)
        if cls == Code.CodeInstConst and asdl.classof(k.const) == Code.CodeConstLiteral and asdl.classof(k.const.literal) == Core.LitInt then
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
        local k = term and term.op
        local cls = asdl.classof(k)
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
        local k = term and term.op
        local cls = asdl.classof(k)
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
        local term = block.term and block.term.op or nil
        if asdl.classof(term) == Code.CodeTermReturn then
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
        local term = block.term and block.term.op or nil
        if asdl.classof(term) == Code.CodeTermReturn then return #(term.values or {}) == 0 end
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
        local ret = exit.term and exit.term.op or nil
        if asdl.classof(ret) == Code.CodeTermReturn and #(ret.values or {}) == 1 then
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
        local ret = exit and exit.term and exit.term.op or nil
        return asdl.classof(ret) == Code.CodeTermReturn and #(ret.values or {}) == 0 or reaches_void_return(blocks, exit)
    end

    local function lane_base_value(lane)
        local base = lane and lane.base or nil
        if asdl.classof(base) == Mem.MemBaseValue then return base.value end
        if asdl.classof(base) == Mem.MemBaseProjection then
            local inner = lane_base_value({ base = base.base })
            if inner ~= nil then return inner end
        end
        return nil
    end

    local function mem_stride_const(stride)
        local cls = asdl.classof(stride)
        if stride == Mem.MemStrideUnit then return 1 end
        if cls == Mem.MemStrideConstElems then return stride.elems end
        return nil
    end

    local function extent_len(extent)
        if asdl.classof(extent) == Mem.MemExtentElements then return extent.len end
        return nil
    end

    local function pattern_layout(pattern)
        local cls = asdl.classof(pattern)
        if pattern == Mem.MemAccessContiguous then return Stencil.StencilLayoutContiguous(1) end
        if cls == Mem.MemAccessStrided then return Stencil.StencilLayoutContiguous(pattern.stride_elems) end
        return nil
    end

    local function field_name_from_lane(ctx, lane)
        for _, access_id in ipairs(lane and lane.accesses or {}) do
            local access = ctx.mem_accesses and ctx.mem_accesses[access_id.text] or nil
            local place = access and access.place or nil
            while place ~= nil do
                local cls = asdl.classof(place)
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
            local pcls = asdl.classof(provenance)
            if object.form == Mem.MemObjectDerived and pcls == Mem.MemProvProjection and provenance.projection == Mem.MemProjectField then
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
            if object.form == Mem.MemObjectView and pcls == Mem.MemProvView then
                if provenance.stride == nil then return nil end
                return wrap_soa(Stencil.StencilLayoutViewDescriptor(
                    provenance.view,
                    provenance.data,
                    extent_len(object.extent) or provenance.len,
                    provenance.stride,
                    mem_stride_const(object.stride)
                ))
            end
            if object.form == Mem.MemObjectSlice and pcls == Mem.MemProvSlice then
                return wrap_soa(Stencil.StencilLayoutSliceDescriptor(
                    provenance.slice,
                    provenance.data,
                    extent_len(object.extent) or provenance.len
                ))
            end
            if object.form == Mem.MemObjectByteSpan and pcls == Mem.MemProvByteSpan then
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
        local cls = asdl.classof(layout)
        if cls == Stencil.StencilLayoutAffine1D or cls == Stencil.StencilLayoutAffineND then return layout_data_value(layout.parent) end
        if cls == Stencil.StencilLayoutSoAComponent or cls == Stencil.StencilLayoutFieldProjection then return layout_data_value(layout.parent) end
        if cls == Stencil.StencilLayoutViewDescriptor or cls == Stencil.StencilLayoutSliceDescriptor or cls == Stencil.StencilLayoutByteSpanDescriptor then return layout.data end
        return nil
    end

    local function binding_index(body)
        local out = {}
        for i, binding in ipairs(body and body.bindings or {}) do
            out[i] = SM.StencilMachineExprBinding(binding.id, binding.expr)
        end
        return SM.StencilMachineExprBindings(out)
    end

    local function same_code_type(a, b)
        if a == b then return true end
        local ac, bc = asdl.classof(a), asdl.classof(b)
        if ac ~= bc then return false end
        if ac == Code.CodeTyInt then return a.bits == b.bits and a.signedness == b.signedness end
        if ac == Code.CodeTyFloat then return a.bits == b.bits end
        return false
    end

    local function primary_induction(loop_fact)
        for _, induction in ipairs(loop_fact and loop_fact.inductions or {}) do
            if induction.role == Flow.FlowPrimaryInduction then return induction.value end
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
        return asdl.classof(expr) == Value.ValueExprConst
            and asdl.classof(expr.const) == Code.CodeConstLiteral
            and asdl.classof(expr.const.literal) == Core.LitInt
            and tonumber(expr.const.literal.raw) == raw
    end

    local function expr_int_const(expr)
        if asdl.classof(expr) == Value.ValueExprConst
            and asdl.classof(expr.const) == Code.CodeConstLiteral
            and asdl.classof(expr.const.literal) == Core.LitInt then
            return tonumber(expr.const.literal.raw)
        end
        return nil
    end

    local function bound_algebra_expr(bindings, value)
        local id = value and Kernel.KernelValueId("kval:" .. value.text) or nil
        local binding = id and bindings and bindings:lookup(id) or nil
        if binding ~= nil and asdl.classof(binding.kernel_expr) == Kernel.KernelExprAlgebra then return binding.kernel_expr.expr end
        return nil
    end

    local function value_expr_from_code(ctx, value, seen)
        if value == nil then return nil end
        seen = seen or {}
        if seen[value.text] then return Value.ValueExprValue(value) end
        seen[value.text] = true
        local def = ctx.defs and ctx.defs[value.text] or nil
        local k = def and def.op or nil
        local cls = asdl.classof(k)
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
        local cls = asdl.classof(expr)
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
        local cls = asdl.classof(expr)
        if cls == Value.ValueExprConst and asdl.classof(expr.const) == Code.CodeConstLiteral then
            local lit = expr.const.literal
            return "const:" .. tostring(asdl.classof(lit)) .. ":" .. tostring(lit and (lit.raw or lit.value))
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
        local cls = asdl.classof(expr)
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
            while v ~= nil and asdl.classof(v) == Value.ValueExprCast do
                v = resolved_algebra_expr(ctx, v.value, bindings)
            end
            return v
        end
        expr = strip_casts(expr)
        if expr == nil then return nil end
        if asdl.classof(expr) == Value.ValueExprMul then
            if expr_is_int_const(expr.a, 1) then expr = strip_casts(expr.b) end
            if expr_is_int_const(expr.b, 1) then expr = strip_casts(expr.a) end
        end
        if expr == nil then return nil end
        if asdl.classof(expr) ~= Value.ValueExprSub then return nil end
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
        if asdl.classof(shape) ~= Stencil.StencilProduceRangeND then return nil end
        local axis_candidates = axis_expr_candidates(ctx, graph_loop, shape, bindings)
        local function strip(v)
            v = resolved_algebra_expr(ctx, v, bindings)
            while asdl.classof(v) == Value.ValueExprCast do v = resolved_algebra_expr(ctx, v.value, bindings) end
            if asdl.classof(v) == Value.ValueExprMul then
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
            local cls = asdl.classof(v)
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
        return asdl.classof(expr) == Value.ValueExprConst
            and asdl.classof(expr.const) == Code.CodeConstLiteral
            and asdl.classof(expr.const.literal) == Core.LitInt
            and tonumber(expr.const.literal.raw) == 0
    end

    local function is_minus_one_const(expr)
        return asdl.classof(expr) == Value.ValueExprConst
            and asdl.classof(expr.const) == Code.CodeConstLiteral
            and asdl.classof(expr.const.literal) == Core.LitInt
            and tonumber(expr.const.literal.raw) == -1
    end

    local function classify_store_expr(expr, bindings, seen)
        return StencilMethods.classify_expr(expr, bindings or SM.StencilMachineExprBindings({}), seen)
    end

    local function single_store_effect(body)
        local store = nil
        for _, effect in ipairs(body and body.effects or {}) do
            local cls = asdl.classof(effect)
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
        local point_facts, point_facts_err = StencilMethods.classify_expr(Kernel.KernelExprAlgebra(expr), bindings)
        if point_facts == nil then return nil, point_facts_err end
        return StencilMethods.select_index_lane(point_facts)
    end

    local function lane_selection_fact(ctx, lane)
        local layout = lane_layout(ctx, lane)
        if layout == nil then return nil end
        local base = lane_base_value(lane)
        local tcls = asdl.classof(layout)
        base = layout_data_value(layout) or base
        if base == nil then return nil end
        return {
            base = base,
            base_expr = value_id_expr(ctx, base),
            elem_ty = lane.elem_ty,
            layout = layout,
        }
    end

    local function enrich_point_facts(ctx, point_facts, graph_loop, loop_fact, bindings)
        local producer_fact = ctx and ctx.producer_facts and loop_fact and loop_fact.domain and ctx.producer_facts[flow_domain_key(loop_fact.domain)] or nil
        local producer_shape = producer_fact and producer_fact.producer and StencilArtifactPlan.producer_shape(producer_fact.producer) or nil
        local window_1d = producer_shape ~= nil and asdl.classof(producer_shape) == Stencil.StencilProduceWindowND and #(producer_shape.axes or {}) == 1
        local function strip_casts(expr)
            expr = resolved_algebra_expr(ctx, expr, bindings)
            if expr ~= nil and asdl.classof(expr) == Value.ValueExprValue then
                expr = value_expr_from_code(ctx, expr.value) or expr
            end
            while expr ~= nil and asdl.classof(expr) == Value.ValueExprCast do expr = resolved_algebra_expr(ctx, expr.value, bindings) end
            return expr
        end
        local function window_offset_for_index(index)
            if not window_1d then return nil end
            local expr = strip_casts(index)
            if expr == nil then return nil end
            if asdl.classof(expr) == Value.ValueExprMul then
                if expr_int_const(strip_casts(expr.a)) ~= nil then expr = strip_casts(expr.b)
                elseif expr_int_const(strip_casts(expr.b)) ~= nil then expr = strip_casts(expr.a) end
            end
            if expr == nil then return nil end
            if expr_is_primary(ctx, expr, graph_loop, loop_fact, bindings) then return 0 end
            local cls = asdl.classof(expr)
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
        local inputs = {}
        for i, input in ipairs(point_facts.inputs or {}) do
            if input.scalar_value ~= nil then
                inputs[i] = asdl.with(input, { index_primary = true })
            else
                local fact = lane_selection_fact(ctx, input.lane)
                if fact == nil then return nil, input.name .. " lane has no value base" end
                local enriched = asdl.with(input, {
                    base = fact.base,
                    base_expr = fact.base_expr,
                    ty = fact.elem_ty,
                    layout = fact.layout,
                    index_primary = expr_is_primary(ctx, input.index, graph_loop, loop_fact, bindings),
                })
                if not enriched.index_primary then
                    local affine_layout = affine_nd_layout_for_index(ctx, input.index, graph_loop, loop_fact, bindings, enriched.layout)
                    if affine_layout ~= nil then
                        enriched = asdl.with(enriched, { layout = affine_layout, index_primary = true })
                    end
                end
                if not enriched.index_primary then
                    local offset = window_offset_for_index(input.index)
                    if offset ~= nil then
                        local offsets = { Stencil.StencilWindowOffset(Stencil.StencilAxisRef(1), offset) }
                        enriched = asdl.with(enriched, { index_primary = true, window_offsets = offsets })
                        window_by_input[input.name] = offsets
                    end
                end
                if not enriched.index_primary then
                    local idx = index_lane_for(input.index, bindings)
                    if idx ~= nil then
                        local idx_fact = lane_selection_fact(ctx, idx.lane)
                        if idx_fact ~= nil then
                            enriched = asdl.with(enriched, {
                                index_lane = SM.StencilMachinePointInput(
                                    input.name .. "_idx",
                                    nil,
                                    nil,
                                    nil,
                                    idx_fact.base,
                                    idx_fact.base_expr,
                                    idx_fact.elem_ty,
                                    idx_fact.elem_ty,
                                    idx_fact.layout,
                                    Stencil.StencilAccessIndex,
                                    expr_is_primary(ctx, idx.index, graph_loop, loop_fact, bindings),
                                    nil,
                                    {}
                                ),
                            })
                        end
                    end
                end
                inputs[i] = enriched
            end
        end
        local rewrite_expr
        rewrite_expr = function(expr)
            local cls = asdl.classof(expr)
            if cls == Stencil.StencilPointInput then
                local offsets = window_by_input[expr.access.name]
                if offsets ~= nil then return Stencil.StencilPointWindowInput(expr.access, offsets) end
                return expr
            end
            if cls == Stencil.StencilPointUnary then return Stencil.StencilPointUnary(expr.op, rewrite_expr(expr.arg), expr.result_ty, expr.int_semantics, expr.float_mode) end
            if cls == Stencil.StencilPointBinary then return Stencil.StencilPointBinary(expr.op, rewrite_expr(expr.left), rewrite_expr(expr.right), expr.result_ty, expr.int_semantics, expr.float_mode) end
            if cls == Stencil.StencilPointCast then return Stencil.StencilPointCast(expr.op, rewrite_expr(expr.arg), expr.from, expr.to) end
            if cls == Stencil.StencilPointPredicate then return Stencil.StencilPointPredicate(expr.pred, rewrite_expr(expr.arg), expr.result_ty) end
            if cls == Stencil.StencilPointCompare then return Stencil.StencilPointCompare(expr.cmp, rewrite_expr(expr.left), rewrite_expr(expr.right), expr.result_ty) end
            if cls == Stencil.StencilPointSelect then return Stencil.StencilPointSelect(expr.pred, rewrite_expr(expr.cond), rewrite_expr(expr.then_expr), rewrite_expr(expr.else_expr), expr.result_ty) end
            return expr
        end
        local expr = point_facts.expr
        if next(window_by_input) ~= nil then expr = rewrite_expr(expr) end
        return SM.StencilMachinePointExprFacts(expr, inputs, point_facts.result_ty, point_facts.const_int)
    end

    local function enrich_stencil_point_facts(ctx, point_facts, graph_loop, loop_fact, bindings, dst_base, dst_ty)
        return enrich_point_facts(ctx, point_facts, graph_loop, loop_fact, bindings)
    end

    local function enriched_point_facts_for_expr(ctx, expr, graph_loop, loop_fact, bindings, dst_base, dst_ty)
        local raw_point_facts, reason = classify_store_expr(expr, bindings)
        if raw_point_facts == nil then return nil, reason end
        return enrich_stencil_point_facts(ctx, raw_point_facts, graph_loop, loop_fact, bindings, dst_base, dst_ty)
    end

    local function index_lane_selection_fact(ctx, expr, graph_loop, loop_fact, bindings)
        local idx = index_lane_for(expr, bindings)
        if idx == nil then return nil end
        local fact = lane_selection_fact(ctx, idx.lane)
        if fact == nil then return nil end
        return SM.StencilMachineIndexLane(
            fact.base,
            fact.base_expr,
            fact.elem_ty,
            fact.layout,
            expr_is_primary(ctx, idx.index, graph_loop, loop_fact, bindings)
        )
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
        return asdl.classof(expr) == Value.ValueExprValue and value ~= nil and expr.value.text == value.text
    end

    local function scan_axis_from_loop(ctx, loop_fact, producer)
        if producer == nil or loop_fact == nil or loop_fact.counted == nil then return nil end
        local shape = StencilArtifactPlan.producer_shape(producer)
        if asdl.classof(shape) ~= Stencil.StencilProduceRangeND then return nil end
        local counted = loop_fact.counted
        for axis_index, axis in ipairs(shape.axes or {}) do
            if same_value_expr_value(axis.start, counted.start) and same_value_expr_value(axis.stop, counted.stop) then
                return Stencil.StencilAxisRef(axis_index)
            end
        end
        return nil
    end

    local function stencil_store_plan(ctx, func, plan, graph_loop, loop_fact)
        if asdl.classof(plan) ~= Kernel.KernelPlanned then return nil, "kernel is not planned" end
        if not function_returns_void_from_loop(func, graph_loop) then return nil, "store stencil requires loop exit to return void" end
        if loop_fact == nil or loop_fact.counted == nil then return nil, "store stencil requires counted loop" end
        local step_num = const_int_value(ctx, loop_fact.counted.step)
        if step_num == nil or step_num == 0 then return nil, "store stencil requires a non-zero constant step" end
        local descriptor_step = math.abs(step_num)
        local store, store_reason = single_store_effect(kernel_plan_body(plan))
        if store == nil then return nil, store_reason end
        local dst_base = lane_base_value(store.dst)
        if dst_base == nil then return nil, "store destination lane has no value base" end
        local dst_fact = lane_selection_fact(ctx, store.dst)
        local bindings = binding_index(kernel_plan_body(plan))
        local raw_point_facts, reason = classify_store_expr(store.value, bindings)
        if raw_point_facts == nil then return nil, reason end
        local start_expr, stop_expr = producer_value_id_expr(ctx, loop_fact.counted.start), producer_value_id_expr(ctx, loop_fact.counted.stop)
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
        local point_facts, point_facts_reason = enrich_stencil_point_facts(ctx, raw_point_facts, graph_loop, loop_fact, bindings, dst_base, store.dst.elem_ty)
        if point_facts == nil then return nil, point_facts_reason end
        local selection_input = SM.StencilMachineStoreSelectionFacts(
            producer_from_loop(ctx, loop_fact, descriptor_step),
            descriptor_step,
            store.dst.elem_ty,
            dst_base,
            dst_expr,
            dst_layout,
            loop_fact.counted.start,
            loop_fact.counted.stop,
            start_expr,
            stop_expr,
            store_index_is_primary,
            store_index_is_primary and nil or index_lane_selection_fact(ctx, store.index, graph_loop, loop_fact, bindings),
            Stencil.StencilScatterUniqueIndices,
            nil,
            point_facts
        )
        local stencil_plan, select_reason = SM.StencilMachineStorePlanInput(
            asdl.classof(plan) == Kernel.KernelPlanned,
            function_returns_void_from_loop(func, graph_loop),
            step_num ~= nil and step_num ~= 0,
            store ~= nil,
            dst_base ~= nil,
            point_facts ~= nil,
            selection_input
        ):plan_store_stencil()
        if stencil_plan == nil then return nil, select_reason end
        return { selection = stencil_plan.selection }, nil
    end

    local function dynamic_stride_layout(layout)
        local cls = asdl.classof(layout)
        if cls == Stencil.StencilLayoutFieldProjection then return dynamic_stride_layout(layout.parent) end
        if cls == Stencil.StencilLayoutSoAComponent then return dynamic_stride_layout(layout.parent) end
        if cls == Stencil.StencilLayoutAffine1D or cls == Stencil.StencilLayoutAffineND then return dynamic_stride_layout(layout.parent) end
        if cls == Stencil.StencilLayoutViewDescriptor and layout.stride_const == nil then return layout end
        return nil
    end

    local function dynamic_affine_offset_layout(layout)
        local cls = asdl.classof(layout)
        if cls == Stencil.StencilLayoutFieldProjection then return dynamic_affine_offset_layout(layout.parent) end
        if cls == Stencil.StencilLayoutSoAComponent then return dynamic_affine_offset_layout(layout.parent) end
        if cls == Stencil.StencilLayoutIndexed then return dynamic_affine_offset_layout(layout.parent) end
        if cls == Stencil.StencilLayoutAffine1D and layout.offset ~= nil then return layout end
        if cls == Stencil.StencilLayoutAffineND and layout.offset ~= nil then return layout end
        return nil
    end

    local function access_arg_value(operation_descriptor, name)
        if operation_descriptor == nil or name == nil then return nil end
        if name == "dst" then return operation_descriptor.dst end
        if name == "xs" then return operation_descriptor.array or operation_descriptor.src or operation_descriptor.xs end
        if name == "src" then return operation_descriptor.src or operation_descriptor.array end
        if name == "lhs" then return operation_descriptor.lhs end
        if name == "rhs" then return operation_descriptor.rhs end
        if name == "idx" then return operation_descriptor.index or operation_descriptor.idx end
        if name == "cond" then return operation_descriptor.cond end
        if name == "then_xs" then return operation_descriptor.then_xs or operation_descriptor.then_base end
        if name == "else_xs" then return operation_descriptor.else_xs or operation_descriptor.else_base end
        for _, input in ipairs(operation_descriptor.inputs or {}) do
            if input.name == name then return input.base end
        end
        return operation_descriptor[name]
    end

    local function append_access_args(ctx, desc, operation_descriptor, out)
        for _, access in ipairs(StencilArtifactPlan.descriptor_accesses(desc)) do
            if asdl.classof(access.layout) ~= Stencil.StencilLayoutScalar then
                local role = access.role
                if role == Stencil.StencilAccessRead or role == Stencil.StencilAccessWrite or role == Stencil.StencilAccessReadWrite or role == Stencil.StencilAccessIndex then
                    local id = access_arg_value(operation_descriptor, access.name)
                    if id ~= nil then out[#out + 1] = value_id_expr(ctx, id) end
                end
            end
        end
    end

    local function append_producer_args(ctx, producer, out, fallback)
        local shape = StencilArtifactPlan.producer_shape(producer)
        local call_shape = fallback and fallback.producer and StencilArtifactPlan.producer_shape(fallback.producer) or shape
        local cls = asdl.classof(shape)
        if cls == Stencil.StencilProduceRange1D then
            out[#out + 1] = call_shape.start and producer_value_expr(ctx, call_shape.start) or assert(fallback and fallback.start_expr, "Range1D producer call is missing start")
            out[#out + 1] = call_shape.stop and producer_value_expr(ctx, call_shape.stop) or assert(fallback and fallback.stop_expr, "Range1D producer call is missing stop")
            return
        end
        if cls == Stencil.StencilProduceRangeND or cls == Stencil.StencilProduceWindowND or cls == Stencil.StencilProduceTiledND then
            for axis_index, axis in ipairs(shape.axes or {}) do
                local call_axis = call_shape.axes and call_shape.axes[axis_index] or axis
                out[#out + 1] = assert(call_axis.start and producer_value_expr(ctx, call_axis.start), "ND producer call is missing axis start")
                out[#out + 1] = assert(call_axis.stop and producer_value_expr(ctx, call_axis.stop), "ND producer call is missing axis stop")
            end
            return
        end
        error("luajit_lower: unsupported stencil producer call shape " .. class_name(shape), 3)
    end

    local function append_trailing_scalar_args(ctx, desc, operation_descriptor, out)
        for _, access in ipairs(StencilArtifactPlan.descriptor_accesses(desc)) do
            if asdl.classof(access.layout) == Stencil.StencilLayoutScalar and access.role == Stencil.StencilAccessRead then
                local init = access.layout.value or (operation_descriptor and operation_descriptor.value)
                if init ~= nil then out[#out + 1] = value_expr(ctx, init) end
            end
        end
        local sink = desc.sink
        local sink_cls = asdl.classof(sink)
        if sink_cls == Stencil.StencilSinkScan then
            out[#out + 1] = value_expr(ctx, assert(operation_descriptor and operation_descriptor.init, "scan stencil call is missing init"))
        elseif sink_cls == Stencil.StencilSinkReduce then
            local scope = sink.scope
            local scope_cls = asdl.classof(scope)
            local domain_scope = scope == Stencil.StencilReduceScopeDomain or scope_cls == Stencil.StencilReduceScopeDomain
            if domain_scope and asdl.classof(sink.semantics) == Stencil.StencilReduceFold then
                out[#out + 1] = value_expr(ctx, assert(operation_descriptor and operation_descriptor.init, "reduce stencil call is missing init"))
            end
        end
    end

    local function stencil_args(ctx, artifact, selection)
        local out = {}
        local desc = artifact and artifact.instance and artifact.instance.descriptor or nil
        local operation_descriptor = selection and selection:stencil_artifact_descriptor() or nil
        if desc ~= nil and operation_descriptor ~= nil then
            append_access_args(ctx, desc, operation_descriptor, out)
            append_producer_args(ctx, desc.producer, out, operation_descriptor)
            append_trailing_scalar_args(ctx, desc, operation_descriptor, out)
        else
            local args = selection and selection:stencil_artifact_args() or selection
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
        local artifact = selection:select_stencil_artifact(function(provider_func, vocab, op, _reduction, provider_plan, descriptor)
            return opts.stencil_store_artifact_for(provider_func, vocab, op, provider_plan, descriptor)
        end, func, nil, plan)
        if artifact == nil then return nil, "store stencil artifact provider did not select an artifact" end
        local id = LJ.LJMachineId("machine:" .. sanitize(func.name) .. ":stencil_store:" .. sanitize(loop_fact.loop.text))
        return LJ.LJMachine(id, LJ.LJMachineStencilEffect(artifact, stencil_args(ctx, artifact, selection)), nil, LJ.LJStateScalar, LJ.LJTraceHot), nil
    end

    local function plan_kernel_stencil_store(ctx, func, plan, graph_loop, loop_fact, opts)
        return lower_kernel_stencil_store(ctx, func, plan, graph_loop, loop_fact, opts)
    end

    local function stencil_reduce_plan(ctx, func, plan, graph_loop, loop_fact)
        if asdl.classof(plan) ~= Kernel.KernelPlanned then return nil, "kernel is not planned" end
        local result = kernel_plan_body(plan).result
        if asdl.classof(result) ~= Kernel.KernelResultReduction then return nil, "kernel result is not a reduction" end
        local reduction = result.reduction
        if not function_returns_reduction(func, graph_loop, reduction) then return nil, "function return is not the kernel reduction" end
        if loop_fact == nil or loop_fact.counted == nil then return nil, "reduction stencil requires counted loop" end
        local step_num = const_int_value(ctx, loop_fact.counted.step)
        if step_num == nil or step_num == 0 then return nil, "reduction stencil requires a non-zero constant step" end
        local descriptor_step = math.abs(step_num)
        local raw_point_facts, reason = classify_store_expr(Kernel.KernelExprAlgebra(reduction.contribution), binding_index(kernel_plan_body(plan)))
        if raw_point_facts == nil then return nil, reason end
        local start_expr, stop_expr = producer_value_id_expr(ctx, loop_fact.counted.start), producer_value_id_expr(ctx, loop_fact.counted.stop)
        local init_expr = value_expr(ctx, reduction.init)
        local point_facts, point_facts_reason = enrich_stencil_point_facts(ctx, raw_point_facts, graph_loop, loop_fact, binding_index(kernel_plan_body(plan)), nil, nil)
        if point_facts == nil then return nil, point_facts_reason end
        local i32 = Code.CodeTyInt(32, Code.CodeSigned)
        local selection_input = SM.StencilMachineReduceSelectionFacts(
            producer_from_loop(ctx, loop_fact, descriptor_step),
            descriptor_step,
            reduction.ty,
            reduction.init,
            init_expr,
            loop_fact.counted.start,
            loop_fact.counted.stop,
            start_expr,
            stop_expr,
            reduction.op,
            reduction.op == Value.ReductionAdd,
            is_zero_const(reduction.init),
            same_code_type(reduction.ty, i32),
            point_facts
        )
        local stencil_plan, select_reason = SM.StencilMachineReducePlanInput(
            asdl.classof(plan) == Kernel.KernelPlanned,
            asdl.classof(result) == Kernel.KernelResultReduction,
            function_returns_reduction(func, graph_loop, reduction),
            step_num ~= nil and step_num ~= 0,
            point_facts ~= nil,
            reduction,
            selection_input
        ):plan_reduce_stencil()
        if stencil_plan == nil then return nil, select_reason end
        return { reduction = stencil_plan.reduction, selection = stencil_plan.selection }, nil
    end

    local function lower_kernel_stencil_reduce(ctx, func, plan, graph_loop, loop_fact, opts)
        if opts.stencil_reduce_artifact_for == nil then return nil, "no reduction stencil artifact provider" end
        local planned, reason = stencil_reduce_plan(ctx, func, plan, graph_loop, loop_fact)
        if planned == nil then return nil, reason end
        local reduction, selection = planned.reduction, planned.selection
        local artifact = selection:select_stencil_artifact(opts.stencil_reduce_artifact_for, func, reduction, plan)
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
            local cls = asdl.classof(effect)
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
        if asdl.classof(plan) ~= Kernel.KernelPlanned then return false end
        local body = kernel_plan_body(plan)
        local result = body and body.result or nil
        if asdl.classof(result) == Kernel.KernelResultReduction
            or asdl.classof(result) == Kernel.KernelResultFind then
            return true
        end
        for _, effect in ipairs(body and body.effects or {}) do
            local cls = asdl.classof(effect)
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

    local function kernel_plan_requires_stencil_lowering(plan)
        if asdl.classof(plan) ~= Kernel.KernelPlanned then return false end
        local body = kernel_plan_body(plan)
        local result = body and body.result or nil
        if asdl.classof(result) == Kernel.KernelResultReduction
            or asdl.classof(result) == Kernel.KernelResultFind then
            return true
        end
        for _, effect in ipairs(body and body.effects or {}) do
            local cls = asdl.classof(effect)
            if cls == Kernel.KernelEffectScan
                or cls == Kernel.KernelEffectPartition
                or cls == Kernel.KernelEffectCopy
                or cls == Kernel.KernelEffectScatterReduce then
                return true
            end
        end
        return false
    end

    local function skeleton_scan_plan(ctx, func, plan, graph_loop, loop_fact)
        local effect, effect_reason = single_effect(kernel_plan_body(plan), Kernel.KernelEffectScan)
        if effect == nil then return nil, effect_reason end
        local result = kernel_plan_body(plan).result
        if asdl.classof(result) ~= Kernel.KernelResultReduction then return nil, "scan skeleton requires reduction result" end
        local reduction = effect.reduction
        if result.reduction ~= reduction then return nil, "scan result reduction does not match scan effect" end
        local returns_reduction = function_returns_reduction(func, graph_loop, reduction)
        if not returns_reduction and not function_returns_void_from_loop(func, graph_loop) then return nil, "scan loop exits as neither final value nor void effect" end
        local dst_base = lane_base_value(effect.dst)
        if dst_base == nil then return nil, "scan destination lane has no value base" end
        local dst_fact = lane_selection_fact(ctx, effect.dst)
        local bindings = binding_index(kernel_plan_body(plan))
        local point_facts, point_facts_reason = enriched_point_facts_for_expr(ctx, Kernel.KernelExprAlgebra(reduction.contribution), graph_loop, loop_fact, bindings, dst_base, effect.dst.elem_ty)
        if point_facts == nil then return nil, point_facts_reason end
        local start_expr, stop_expr = producer_value_id_expr(ctx, loop_fact.counted.start), producer_value_id_expr(ctx, loop_fact.counted.stop)
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
        local selection, select_reason = SM.StencilMachineScanSelectionFacts(
            producer,
            descriptor_step,
            effect.dst.elem_ty,
            reduction.ty,
            dst_base,
            value_id_expr(ctx, dst_base),
            dst_layout,
            loop_fact.counted.start,
            loop_fact.counted.stop,
            start_expr,
            stop_expr,
            store_index_is_primary,
            reduction,
            reduction.op,
            reduction.init,
            value_expr(ctx, reduction.init),
            effect.mode,
            effect.axis or scan_axis_from_loop(ctx, loop_fact, producer),
            point_facts
        ):select_scan_stencil()
        if selection == nil then return nil, select_reason end
        return SM.StencilMachineSkeletonPlan(selection, SM.StencilMachineSkeletonReductionFact(reduction), returns_reduction and reduction.ty or nil), nil
    end

    local function skeleton_find_plan(ctx, func, plan, graph_loop, loop_fact)
        local result = kernel_plan_body(plan).result
        if asdl.classof(result) ~= Kernel.KernelResultFind then return nil, "kernel result is not find" end
        if graph_loop == nil then return nil, "find skeleton requires a graph loop" end
        local bindings = binding_index(kernel_plan_body(plan))
        local point_facts, point_facts_reason = enriched_point_facts_for_expr(ctx, result.src, graph_loop, loop_fact, bindings, nil, nil)
        if point_facts == nil then return nil, point_facts_reason end
        local step_num = const_int_value(ctx, loop_fact.counted.step)
        local selection, select_reason = SM.StencilMachineFindSelectionFacts(
            producer_from_loop(ctx, loop_fact, step_num),
            step_num,
            loop_fact.counted.start,
            loop_fact.counted.stop,
            producer_value_id_expr(ctx, loop_fact.counted.start),
            producer_value_id_expr(ctx, loop_fact.counted.stop),
            result.pred,
            is_minus_one_const(result.not_found),
            point_facts
        ):select_find_stencil()
        if selection == nil then return nil, select_reason end
        return SM.StencilMachineSkeletonPlan(selection, nil, Code.CodeTyInt(32, Code.CodeSigned)), nil
    end

    local function skeleton_partition_plan(ctx, func, plan, graph_loop, loop_fact)
        local effect, effect_reason = single_effect(kernel_plan_body(plan), Kernel.KernelEffectPartition)
        if effect == nil then return nil, effect_reason end
        local dst_base = lane_base_value(effect.dst)
        if dst_base == nil then return nil, "partition destination lane has no value base" end
        local dst_fact = lane_selection_fact(ctx, effect.dst)
        local bindings = binding_index(kernel_plan_body(plan))
        local point_facts, point_facts_reason = enriched_point_facts_for_expr(ctx, effect.src, graph_loop, loop_fact, bindings, dst_base, effect.dst.elem_ty)
        if point_facts == nil then return nil, point_facts_reason end
        local step_num = const_int_value(ctx, loop_fact.counted.step)
        local selection, select_reason = SM.StencilMachinePartitionSelectionFacts(
            producer_from_loop(ctx, loop_fact, step_num),
            step_num,
            effect.dst.elem_ty,
            dst_base,
            value_id_expr(ctx, dst_base),
            dst_fact and dst_fact.layout or nil,
            loop_fact.counted.start,
            loop_fact.counted.stop,
            producer_value_id_expr(ctx, loop_fact.counted.start),
            producer_value_id_expr(ctx, loop_fact.counted.stop),
            true,
            effect.pred,
            effect.semantics,
            point_facts
        ):select_partition_stencil()
        if selection == nil then return nil, select_reason end
        return SM.StencilMachineSkeletonPlan(selection, nil, Code.CodeTyInt(32, Code.CodeSigned)), nil
    end

    local function skeleton_copy_plan(ctx, func, plan, graph_loop, loop_fact)
        local effect, effect_reason = single_effect(kernel_plan_body(plan), Kernel.KernelEffectCopy)
        if effect == nil then return nil, effect_reason end
        local dst_base = lane_base_value(effect.dst)
        if dst_base == nil then return nil, "copy destination lane has no value base" end
        local dst_fact = lane_selection_fact(ctx, effect.dst)
        local bindings = binding_index(kernel_plan_body(plan))
        local point_facts, point_facts_reason = enriched_point_facts_for_expr(ctx, effect.src, graph_loop, loop_fact, bindings, dst_base, effect.dst.elem_ty)
        if point_facts == nil then return nil, point_facts_reason end
        local step_num = const_int_value(ctx, loop_fact.counted.step)
        if step_num == nil or step_num == 0 then return nil, "copy skeleton requires a non-zero constant step" end
        local descriptor_step = math.abs(step_num)
        local selection, select_reason = SM.StencilMachineStoreSelectionFacts(
            producer_from_loop(ctx, loop_fact, descriptor_step),
            descriptor_step,
            effect.dst.elem_ty,
            dst_base,
            value_id_expr(ctx, dst_base),
            dst_fact and dst_fact.layout or nil,
            loop_fact.counted.start,
            loop_fact.counted.stop,
            producer_value_id_expr(ctx, loop_fact.counted.start),
            producer_value_id_expr(ctx, loop_fact.counted.stop),
            true,
            nil,
            Stencil.StencilScatterUniqueIndices,
            effect.semantics,
            point_facts
        ):select_store_stencil()
        if selection == nil then return nil, select_reason end
        return SM.StencilMachineSkeletonPlan(selection, nil, nil), nil
    end

    local function skeleton_scatter_reduce_plan(ctx, func, plan, graph_loop, loop_fact)
        local effect, effect_reason = single_effect(kernel_plan_body(plan), Kernel.KernelEffectScatterReduce)
        if effect == nil then return nil, effect_reason end
        if not function_returns_void_from_loop(func, graph_loop) then return nil, "scatter-reduce loop exits as neither final value nor void effect" end
        local dst_base = lane_base_value(effect.dst)
        if dst_base == nil then return nil, "scatter-reduce destination lane has no value base" end
        local dst_fact = lane_selection_fact(ctx, effect.dst)
        if dst_fact == nil then return nil, "scatter-reduce destination lane has no layout fact" end
        local bindings = binding_index(kernel_plan_body(plan))
        local point_facts, point_facts_reason = enriched_point_facts_for_expr(ctx, effect.value, graph_loop, loop_fact, bindings, dst_base, effect.dst.elem_ty)
        if point_facts == nil then return nil, point_facts_reason end
        for _, input in ipairs(point_facts.inputs or {}) do
            if input.index_primary ~= true then return nil, "scatter-reduce contribution inputs must be primary-indexed" end
        end
        local contribution = {
            ty = point_facts.result_ty,
            expr = point_facts.expr,
            inputs = point_facts.inputs,
        }
        local index_lane = index_lane_selection_fact(ctx, effect.index, graph_loop, loop_fact, bindings)
        if index_lane == nil then return nil, "scatter-reduce destination index must come from an index lane" end
        if not index_lane.index_primary then return nil, "scatter-reduce index lane must be primary-indexed" end
        local step_num = const_int_value(ctx, loop_fact.counted.step)
        if step_num == nil or step_num == 0 then return nil, "scatter-reduce stencil requires a non-zero constant step" end
        local descriptor_step = math.abs(step_num)
        return SM.StencilMachineSkeletonPlan(
            SM.StencilMachineSelectScatterReduce(
                SM.StencilMachineScatterReduceNDescriptor(
                    descriptor_step,
                    producer_from_loop(ctx, loop_fact, descriptor_step),
                    effect.reducer.result_ty,
                    contribution.ty,
                    index_lane.elem_ty,
                    dst_base,
                    index_lane.base,
                    "dst",
                    "idx",
                    Stencil.StencilLayoutIndexed(
                        dst_fact.layout,
                        Stencil.StencilAccessRef("idx"),
                        index_lane.elem_ty,
                        descriptor_step
                    ),
                    index_lane.layout,
                    contribution.inputs,
                    contribution.expr,
                    nil,
                    "arity" .. tostring(#(contribution.inputs or {})),
                    nil,
                    nil,
                    nil,
                    nil
                ),
                {
                    value_id_expr(ctx, dst_base),
                    index_lane.base_expr,
                    value_id_expr(ctx, loop_fact.counted.start),
                    value_id_expr(ctx, loop_fact.counted.stop),
                }
            ),
            SM.StencilMachineSkeletonReducer(effect.reducer),
            nil
        ), nil
    end

    local function stencil_skeleton_plan(ctx, func, plan, graph_loop, loop_fact)
        if asdl.classof(plan) ~= Kernel.KernelPlanned then return nil, "kernel is not planned" end
        if loop_fact == nil or loop_fact.counted == nil then return nil, "stencil skeleton requires counted loop" end
        local step_num = const_int_value(ctx, loop_fact.counted.step)
        if step_num == nil or step_num == 0 then return nil, "stencil skeleton requires a non-zero constant step" end
        local scan, scan_reason = skeleton_scan_plan(ctx, func, plan, graph_loop, loop_fact)
        local find, find_reason = skeleton_find_plan(ctx, func, plan, graph_loop, loop_fact)
        local partition, partition_reason = skeleton_partition_plan(ctx, func, plan, graph_loop, loop_fact)
        local copy, copy_reason = skeleton_copy_plan(ctx, func, plan, graph_loop, loop_fact)
        local scatter_reduce, scatter_reduce_reason = skeleton_scatter_reduce_plan(ctx, func, plan, graph_loop, loop_fact)
        local reject_reason = scan_reason or find_reason or partition_reason or copy_reason or scatter_reduce_reason or "no stencil skeleton selected"
        local candidates = {}
        if scan ~= nil then candidates[#candidates + 1] = SM.StencilMachineSkeletonScanCandidate(scan) end
        if find ~= nil then candidates[#candidates + 1] = SM.StencilMachineSkeletonFindCandidate(find) end
        if partition ~= nil then candidates[#candidates + 1] = SM.StencilMachineSkeletonPartitionCandidate(partition) end
        if copy ~= nil then candidates[#candidates + 1] = SM.StencilMachineSkeletonCopyCandidate(copy) end
        if scatter_reduce ~= nil then candidates[#candidates + 1] = SM.StencilMachineSkeletonScatterReduceCandidate(scatter_reduce) end
        local selection = SM.StencilMachineSkeletonInput(candidates, reject_reason):select_stencil_machine_skeleton()
        return selection:planned_stencil_machine_skeleton()
    end

    local function lower_kernel_stencil_skeleton(ctx, func, plan, graph_loop, loop_fact, opts)
        if opts.stencil_skeleton_artifact_for == nil then return nil, "no skeleton stencil artifact provider" end
        local planned, reason = stencil_skeleton_plan(ctx, func, plan, graph_loop, loop_fact)
        if planned == nil then return nil, reason end
        local selection = planned.selection
        local reduction = planned.reduction and planned.reduction:stencil_machine_artifact_reduction() or nil
        local artifact = selection:select_stencil_artifact(opts.stencil_skeleton_artifact_for, func, reduction, plan)
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

    function SM.StencilMachineSkeletonSelection:planned_stencil_machine_skeleton()
        return nil, "unsupported LuaJIT skeleton lowering selection"
    end

    function SM.StencilMachineSkeletonNoPlan:planned_stencil_machine_skeleton()
        return nil, self.reason
    end

    function SM.StencilMachineSkeletonScan:planned_stencil_machine_skeleton() return self.planned, nil end
    function SM.StencilMachineSkeletonFind:planned_stencil_machine_skeleton() return self.planned, nil end
    function SM.StencilMachineSkeletonPartition:planned_stencil_machine_skeleton() return self.planned, nil end
    function SM.StencilMachineSkeletonCopy:planned_stencil_machine_skeleton() return self.planned, nil end
    function SM.StencilMachineSkeletonScatterReduce:planned_stencil_machine_skeleton() return self.planned, nil end

    function SM.StencilMachineKernelSelection:plan_stencil_machine_kernel()
        return nil, "unsupported LuaJIT kernel lowering selection"
    end

    function SM.StencilMachineKernelNoPlan:plan_stencil_machine_kernel()
        return nil, self.reason
    end

    function SM.StencilMachineKernelReduce:plan_stencil_machine_kernel(ctx, func, plan, graph_loop, loop_fact, opts)
        return plan_kernel_stencil_reduce(ctx, func, plan, graph_loop, loop_fact, opts)
    end

    function SM.StencilMachineKernelStore:plan_stencil_machine_kernel(ctx, func, plan, graph_loop, loop_fact, opts)
        return plan_kernel_stencil_store(ctx, func, plan, graph_loop, loop_fact, opts)
    end

    function SM.StencilMachineKernelSkeleton:plan_stencil_machine_kernel(ctx, func, plan, graph_loop, loop_fact, opts)
        return plan_kernel_stencil_skeleton(ctx, func, plan, graph_loop, loop_fact, opts)
    end

    local function counted_positive(ctx, loop_fact)
        if loop_fact == nil or loop_fact.counted == nil then return false end
        local step_num = const_int_value(ctx, loop_fact.counted.step)
        return step_num ~= nil and step_num ~= 0
    end

    local function kernel_lowering_input(ctx, func, plan, graph_loop, loop_fact, loop_owner, kernel, opts)
        local subject = plan and plan.subject or nil
        local subject_cls = asdl.classof(subject)
        local loop_plan = subject_cls == Kernel.KernelSubjectLoop or subject_cls == Kernel.KernelSubjectFunction
        local owns_loop = (subject_cls == Kernel.KernelSubjectLoop and loop_owner == func.id)
            or (subject_cls == Kernel.KernelSubjectFunction and subject.func == func.id)
        local planned = asdl.classof(plan) == Kernel.KernelPlanned
        local result = planned and kernel_plan_body(plan) and kernel_plan_body(plan).result or nil
        local result_reduction = asdl.classof(result) == Kernel.KernelResultReduction
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
            store, store_reason = single_store_effect(kernel_plan_body(plan))
            single_store = store ~= nil
            store_dst_base = store ~= nil and lane_base_value(store.dst) ~= nil
        end
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
        return SM.StencilMachineKernelInput(
            loop_plan,
            loop_plan and owns_loop,
            planned,
            opts.stencil_reduce_artifact_for ~= nil,
            opts.stencil_store_artifact_for ~= nil,
            opts.stencil_skeleton_artifact_for ~= nil,
            counted_positive(ctx, loop_fact),
            result_reduction,
            reduction ~= nil and function_returns_reduction(func, graph_loop, reduction),
            function_returns_void_from_loop(func, graph_loop),
            stencil_reduce_ready,
            single_store,
            store_dst_base,
            stencil_store_ready,
            stencil_skeleton_ready,
            reject_reason
        )
    end

    local function lower_blocks_func(ctx, func)
        local blocks = {}
        for i, block in ipairs(func.blocks or {}) do blocks[i] = lower_block(ctx, block) end
        return {}, LJ.LJBodyBlocks(bid(func.entry), blocks)
    end

    local build_kernel

    local function module_ctx_for(module, flow, mem, contracts, opts)
        opts = opts or {}
        return {
            code_sigs = code_sigs(module),
            lj_sigs = {},
            lj_sig_order = {},
            lj_cdefs = {},
            lj_cdef_order = {},
            lj_named_decl_state = {},
            mem_objects = mem_object_index(mem),
            mem_accesses = mem_access_index(mem),
            soa_contracts = soa_contract_index(contracts),
            producer_facts = producer_fact_index(flow),
            flow = flow,
            layout_env = opts.layout_env,
            target = opts.target,
            module_name = module.id and module.id.text or "module",
        }
    end

    local function func_lower_ctx(module_ctx, func)
        local ctx = {
            code_sigs = module_ctx.code_sigs,
            lj_sigs = module_ctx.lj_sigs,
            lj_sig_order = module_ctx.lj_sig_order,
            lj_cdefs = module_ctx.lj_cdefs,
            lj_cdef_order = module_ctx.lj_cdef_order,
            lj_named_decl_state = module_ctx.lj_named_decl_state,
            mem_objects = module_ctx.mem_objects,
            mem_accesses = module_ctx.mem_accesses,
            soa_contracts = module_ctx.soa_contracts,
            producer_facts = module_ctx.producer_facts,
            func_id = func.id,
            flow = module_ctx.flow,
            layout_env = module_ctx.layout_env,
            target = module_ctx.target,
            module_name = module_ctx.module_name,
            value_types = {},
            defs = value_defs(func),
        }
        note_params(ctx, func.params)
        for _, block in ipairs(func.blocks or {}) do note_params(ctx, block.params) end
        return ctx
    end

    local function plan_domain_loop(plan)
        local body = plan and kernel_plan_body(plan) or nil
        local domain = body and body.domain and body.domain.domain or nil
        if asdl.classof(domain) == Flow.FlowDomainLoop then return domain.loop end
        return nil
    end

    local function select_kernel_machine(ctx, func, plan, graph_loop, loop_fact, owner, kernel, opts)
        local selection = kernel_lowering_input(ctx, func, plan, graph_loop, loop_fact, owner, kernel, opts):select_stencil_machine_kernel()
        return selection:plan_stencil_machine_kernel(ctx, func, plan, graph_loop, loop_fact, opts)
    end

    local function plan_func_stencil_machine(module_ctx, func, kernel, graph_loops, flow_loops, loop_func, opts)
        local ctx = func_lower_ctx(module_ctx, func)
        local pending_rejects = {}
        for _, plan in ipairs(kernel.plans or {}) do
            local subject = plan.subject
            local subject_cls = asdl.classof(subject)
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
                    local artifact = machine.op and machine.op.artifact or nil
                    return LJ.LJStencilMachinePlan(func.id, plan.id, machine, artifact), pending_rejects
                end
                if kernel_plan_requires_stencil_lowering(plan) then
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
        local module_ctx = module_ctx_for(module, flow, mem, opts.contracts, opts)
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
        local sig = CType.ensure_lj_sig(ctx, func.sig)
        local machines, body = nil, nil
        local planned_machine = opts.stencil_machines_by_func and opts.stencil_machines_by_func[func.id.text] or nil
        if planned_machine ~= nil then
            machines = { planned_machine }
            body = LJ.LJBodyMachine(planned_machine.id, LJ.LJTerminalFirst(nil))
            return LJ.LJFunc(fid(func.id), func.id, func.name, sig, params, {}, machines, body, LJ.LJTraceHot)
        end
        if body == nil then machines, body = lower_blocks_func(ctx, func) end
        return LJ.LJFunc(fid(func.id), func.id, func.name, sig, params, {}, machines, body, LJ.LJTraceHot)
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
        local module_ctx = module_ctx_for(module, flow, mem, opts.contracts, opts)
        local funcs = {}
        for i, func in ipairs(module.funcs or {}) do funcs[i] = lower_func(module_ctx, func, kernel, graph_loops, flow_loops, loop_func, opts) end
        return LJ.LJModule(module.id, funcs, module_ctx.lj_sig_order or {}, module_ctx.lj_cdef_order or {}, {}, module.data or {}), {
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
