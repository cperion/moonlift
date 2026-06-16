local pvm = require("moonlift.pvm")

local M = {}

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s:match("^%d") then s = "_" .. s end
    if s == "" then s = "x" end
    return s
end

function M.Define(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.lower_to_back ~= nil then return T._moonlift_api_cache.lower_to_back end

    local Code = T.MoonCode
    local Back = T.MoonBack
    local Lower = T.MoonLower
    local Kernel = T.MoonKernel
    local Schedule = T.MoonSchedule
    local Value = T.MoonValue
    local Mem = T.MoonMem
    local Core = T.MoonCore

    local CodeToBack = require("moonlift.code_to_back").Define(T)
    local CodeGraph = require("moonlift.code_graph").Define(T)
    local CodeFlowFacts = require("moonlift.code_flow_facts").Define(T)
    local CodeValueFacts = require("moonlift.code_value_facts").Define(T)
    local CodeMemFacts = require("moonlift.code_mem_facts").Define(T)
    local CodeEffectFacts = require("moonlift.code_effect_facts").Define(T)
    local CodeKernelPlan = require("moonlift.code_kernel_plan").Define(T)
    local CodeSchedulePlan = require("moonlift.code_schedule_plan").Define(T)
    local CodeLowerPlan = require("moonlift.code_lower_plan").Define(T)

    local api = {}

    local function bid(id) return Back.BackValId(id.text) end
    local function block_id(id) return Back.BackBlockId(id.text) end
    local function func_id(id)
        local text = tostring(id.text)
        return Back.BackFuncId(text:gsub("^fn:", "", 1))
    end
    local function shape(ty)
        local s = CodeToBack.scalar(ty)
        if s == nil then error("lower_to_back: unsupported block param type", 3) end
        return Back.BackShapeScalar(s)
    end

    local function scalar(ty)
        local s = CodeToBack.scalar(ty)
        if s == nil then error("lower_to_back: unsupported scalar type for semantic emission", 3) end
        return s
    end

    local function note_value(ctx, id, ty)
        if id ~= nil and ty ~= nil then ctx.value_types[id.text] = ty end
    end

    local function func_by_id(code_module)
        local out = {}
        for _, func in ipairs(code_module.funcs or {}) do out[func.id.text] = func end
        return out
    end

    local function graph_indexes(graph)
        local loops = {}
        for _, fg in ipairs(graph and graph.funcs or {}) do
            for _, loop in ipairs(fg.loops or {}) do loops[loop.id.text] = loop end
        end
        return loops
    end

    local function cover_blocks(fragment, func, graph_loops)
        local cover = fragment.cover
        local cls = pvm.classof(cover)
        local out, set = {}, {}
        local function add(block)
            if block ~= nil and not set[block.id.text] then set[block.id.text] = true; out[#out + 1] = block end
        end
        if cls == Lower.LowerCoverFunction then
            for _, b in ipairs(func.blocks or {}) do add(b) end
        elseif cls == Lower.LowerCoverBlock then
            for _, b in ipairs(func.blocks or {}) do if b.id == cover.block then add(b) end end
        elseif cls == Lower.LowerCoverBlockRange then
            local active = false
            for _, b in ipairs(func.blocks or {}) do
                if b.id == cover.entry then active = true end
                if active then add(b) end
                if b.id == cover.exit then break end
            end
        elseif cls == Lower.LowerCoverLoop then
            local loop = graph_loops[cover.loop.text]
            local body = {}
            for _, gb in ipairs(loop and loop.body or {}) do body[gb.block.text] = true end
            for _, b in ipairs(func.blocks or {}) do if body[b.id.text] then add(b) end end
        end
        return out, set
    end

    local function fragment_covers_block(fragment, func, graph_loops, block)
        local _, set = cover_blocks(fragment, func, graph_loops)
        return set[block.id.text]
    end

    local function ordered_fragments_for_func(func, func_plan, graph_loops)
        local ordered, emitted = {}, {}
        for _, block in ipairs(func.blocks or {}) do
            if not emitted[block.id.text] then
                local chosen = nil
                for _, fragment in ipairs(func_plan.fragments or {}) do
                    if fragment_covers_block(fragment, func, graph_loops, block) then chosen = fragment; break end
                end
                if chosen ~= nil then
                    ordered[#ordered + 1] = chosen
                    local _, set = cover_blocks(chosen, func, graph_loops)
                    for key in pairs(set) do emitted[key] = true end
                end
            end
        end
        return ordered
    end

    local function graph_loop_by_id(graph)
        local out = {}
        for _, fg in ipairs(graph and graph.funcs or {}) do for _, loop in ipairs(fg.loops or {}) do out[loop.id.text] = loop end end
        return out
    end

    local function edge_fact_by_key(flow)
        local out = {}
        for _, ef in ipairs(flow and flow.edges or {}) do out[ef.edge.from.block.text .. "\0" .. ef.edge.to.block.text] = ef end
        return out
    end

    local function kernel_by_id(kernels)
        local out = {}
        for _, kp in ipairs(kernels and kernels.plans or {}) do if pvm.classof(kp) == Kernel.KernelPlanned then out[kp.id.text] = kp end end
        return out
    end

    local function value_ty(ctx, id)
        return id and ctx.value_types[id.text] or nil
    end

    local function int_op(op, ty)
        if op == "add" then return Back.BackIntAdd end
        if op == "sub" then return Back.BackIntSub end
        if op == "mul" then return Back.BackIntMul end
        if op == "div" then
            local cls = pvm.classof(ty)
            if ty == Code.CodeTyIndex or (cls == Code.CodeTyInt and ty.signedness == Code.CodeUnsigned) then return Back.BackIntUDiv end
            return Back.BackIntSDiv
        end
        error("lower_to_back: unsupported closed-form integer op " .. tostring(op), 3)
    end

    local function int_sem(expr)
        local overflow = Back.BackIntWrap
        if expr and expr.sem and pvm.classof(expr.sem.overflow) == Code.CodeIntAssumeNoOverflow then overflow = Back.BackIntNoWrap(expr.sem.overflow.reason) end
        return Back.BackIntSemantics(overflow, Back.BackIntMayLose)
    end

    local function cmp_op(op, ty)
        local cls = pvm.classof(ty)
        local unsigned = ty == Code.CodeTyIndex or (cls == Code.CodeTyInt and ty.signedness == Code.CodeUnsigned)
        local float = cls == Code.CodeTyFloat
        if op == Core.CmpEq then return float and Back.BackFCmpEq or Back.BackIcmpEq end
        if op == Core.CmpNe then return float and Back.BackFCmpNe or Back.BackIcmpNe end
        if op == Core.CmpLt then return float and Back.BackFCmpLt or (unsigned and Back.BackUIcmpLt or Back.BackSIcmpLt) end
        if op == Core.CmpLe then return float and Back.BackFCmpLe or (unsigned and Back.BackUIcmpLe or Back.BackSIcmpLe) end
        if op == Core.CmpGt then return float and Back.BackFCmpGt or (unsigned and Back.BackUIcmpGt or Back.BackSIcmpGt) end
        if op == Core.CmpGe then return float and Back.BackFCmpGe or (unsigned and Back.BackUIcmpGe or Back.BackSIcmpGe) end
        error("lower_to_back: unsupported compare op", 3)
    end

    local function cast_op_for(from_ty, to_ty)
        local fcls, tcls = pvm.classof(from_ty), pvm.classof(to_ty)
        if from_ty == to_ty then return nil end
        if to_ty == Code.CodeTyIndex then
            if fcls == Code.CodeTyInt then return from_ty.signedness == Code.CodeSigned and Back.BackSextend or Back.BackUextend end
            if from_ty == Code.CodeTyBool8 then return Back.BackUextend end
        end
        if tcls == Code.CodeTyInt then
            if from_ty == Code.CodeTyIndex then return Back.BackIreduce end
            if fcls == Code.CodeTyInt then
                if from_ty.bits < to_ty.bits then return from_ty.signedness == Code.CodeSigned and Back.BackSextend or Back.BackUextend end
                if from_ty.bits > to_ty.bits then return Back.BackIreduce end
                return Back.BackBitcast
            end
            if from_ty == Code.CodeTyBool8 then return Back.BackUextend end
        end
        if tcls == Code.CodeTyFloat and fcls == Code.CodeTyFloat then
            if from_ty.bits < to_ty.bits then return Back.BackFpromote end
            if from_ty.bits > to_ty.bits then return Back.BackFdemote end
        end
        if scalar(from_ty) == scalar(to_ty) then return Back.BackBitcast end
        error("lower_to_back: unsupported semantic cast from " .. tostring(from_ty) .. " to " .. tostring(to_ty), 3)
    end

    local function ensure_value_ty(ctx, dst, to_ty, src, from_ty)
        if scalar(to_ty) == scalar(from_ty) then
            if dst.text ~= src.text then ctx.cmds[#ctx.cmds + 1] = Back.CmdAlias(dst, src) end
            return dst
        end
        ctx.cmds[#ctx.cmds + 1] = Back.CmdCast(dst, cast_op_for(from_ty, to_ty), scalar(to_ty), src)
        return dst
    end

    local function lower_value_expr(ctx, expr)
        local cls = pvm.classof(expr)
        if cls == Value.ValueExprConst then
            ctx.next_tmp = (ctx.next_tmp or 0) + 1
            local v = Back.BackValId("semantic.const." .. tostring(ctx.next_tmp))
            local ccls = pvm.classof(expr.const)
            if ccls ~= Code.CodeConstLiteral then error("lower_to_back: semantic const must be literal", 3) end
            local lit = expr.const.literal
            local lcls = pvm.classof(lit)
            local back_lit
            if lcls == Core.LitInt then back_lit = Back.BackLitInt(lit.raw)
            elseif lcls == Core.LitBool then back_lit = Back.BackLitBool(lit.value)
            elseif lcls == Core.LitFloat then back_lit = Back.BackLitFloat(lit.raw)
            else error("lower_to_back: unsupported semantic literal", 3) end
            ctx.cmds[#ctx.cmds + 1] = Back.CmdConst(v, scalar(expr.const.ty), back_lit)
            return v, expr.const.ty
        elseif cls == Value.ValueExprValue then
            local ty = value_ty(ctx, expr.value)
            if ty == nil then error("lower_to_back: semantic expression references unknown value " .. expr.value.text, 3) end
            return bid(expr.value), ty
        elseif cls == Value.ValueExprAdd or cls == Value.ValueExprSub or cls == Value.ValueExprMul or cls == Value.ValueExprDiv then
            local av, aty = lower_value_expr(ctx, expr.a)
            local bv, bty = lower_value_expr(ctx, expr.b)
            ctx.next_tmp = (ctx.next_tmp or 0) + 1
            local lhs = av
            if scalar(aty) ~= scalar(expr.ty) then lhs = ensure_value_ty(ctx, Back.BackValId("semantic.cast." .. tostring(ctx.next_tmp) .. ".lhs"), expr.ty, av, aty) end
            local rhs = bv
            if scalar(bty) ~= scalar(expr.ty) then rhs = ensure_value_ty(ctx, Back.BackValId("semantic.cast." .. tostring(ctx.next_tmp) .. ".rhs"), expr.ty, bv, bty) end
            local dst = Back.BackValId("semantic.tmp." .. tostring(ctx.next_tmp))
            local op = (cls == Value.ValueExprAdd and "add") or (cls == Value.ValueExprSub and "sub") or (cls == Value.ValueExprMul and "mul") or "div"
            ctx.cmds[#ctx.cmds + 1] = Back.CmdIntBinary(dst, int_op(op, expr.ty), scalar(expr.ty), int_sem(expr), lhs, rhs)
            return dst, expr.ty
        elseif cls == Value.ValueExprCmp then
            local av, aty = lower_value_expr(ctx, expr.a)
            local bv, bty = lower_value_expr(ctx, expr.b)
            ctx.next_tmp = (ctx.next_tmp or 0) + 1
            local lhs = av
            if scalar(aty) ~= scalar(expr.ty) then lhs = ensure_value_ty(ctx, Back.BackValId("semantic.cast." .. tostring(ctx.next_tmp) .. ".cmp_lhs"), expr.ty, av, aty) end
            local rhs = bv
            if scalar(bty) ~= scalar(expr.ty) then rhs = ensure_value_ty(ctx, Back.BackValId("semantic.cast." .. tostring(ctx.next_tmp) .. ".cmp_rhs"), expr.ty, bv, bty) end
            local dst = Back.BackValId("semantic.cmp." .. tostring(ctx.next_tmp))
            ctx.cmds[#ctx.cmds + 1] = Back.CmdCompare(dst, cmp_op(expr.op, expr.ty), shape(expr.ty), lhs, rhs)
            return dst, Code.CodeTyBool8
        elseif cls == Value.ValueExprSelect then
            local cv = lower_value_expr(ctx, expr.cond)
            local tv, tty = lower_value_expr(ctx, expr.t)
            local fv, fty = lower_value_expr(ctx, expr.f)
            local ty = tty or fty
            ctx.next_tmp = (ctx.next_tmp or 0) + 1
            local tval = tv
            if scalar(tty) ~= scalar(ty) then tval = ensure_value_ty(ctx, Back.BackValId("semantic.cast." .. tostring(ctx.next_tmp) .. ".sel_t"), ty, tv, tty) end
            local fval = fv
            if scalar(fty) ~= scalar(ty) then fval = ensure_value_ty(ctx, Back.BackValId("semantic.cast." .. tostring(ctx.next_tmp) .. ".sel_f"), ty, fv, fty) end
            local dst = Back.BackValId("semantic.select." .. tostring(ctx.next_tmp))
            ctx.cmds[#ctx.cmds + 1] = Back.CmdSelect(dst, shape(ty), cv, tval, fval)
            return dst, ty
        elseif cls == Value.ValueExprAffine then
            local acc = nil
            local ty = expr.affine.ty
            if expr.affine.constant ~= "0" then
                acc = lower_value_expr(ctx, Value.ValueExprConst(Code.CodeConstLiteral(ty, Core.LitInt(expr.affine.constant))))
            end
            for _, term in ipairs(expr.affine.terms or {}) do
                local tv, tty = lower_value_expr(ctx, Value.ValueExprValue(term.value))
                if scalar(tty) ~= scalar(ty) then
                    ctx.next_tmp = (ctx.next_tmp or 0) + 1
                    tv = ensure_value_ty(ctx, Back.BackValId("semantic.affine.cast." .. tostring(ctx.next_tmp)), ty, tv, tty)
                end
                if term.coeff ~= "1" then
                    ctx.next_tmp = (ctx.next_tmp or 0) + 1
                    local c = Back.BackValId("semantic.affine.coeff." .. tostring(ctx.next_tmp))
                    ctx.cmds[#ctx.cmds + 1] = Back.CmdConst(c, scalar(ty), Back.BackLitInt(term.coeff))
                    local mul = Back.BackValId("semantic.affine.mul." .. tostring(ctx.next_tmp))
                    ctx.cmds[#ctx.cmds + 1] = Back.CmdIntBinary(mul, Back.BackIntMul, scalar(ty), Back.BackIntSemantics(Back.BackIntWrap, Back.BackIntMayLose), tv, c)
                    tv = mul
                end
                if acc == nil then acc = tv else
                    ctx.next_tmp = (ctx.next_tmp or 0) + 1
                    local sum = Back.BackValId("semantic.affine.add." .. tostring(ctx.next_tmp))
                    ctx.cmds[#ctx.cmds + 1] = Back.CmdIntBinary(sum, Back.BackIntAdd, scalar(ty), Back.BackIntSemantics(Back.BackIntWrap, Back.BackIntMayLose), acc, tv)
                    acc = sum
                end
            end
            if acc == nil then return lower_value_expr(ctx, Value.ValueExprConst(Code.CodeConstLiteral(ty, Core.LitInt("0")))) end
            return acc, ty
        end
        error("lower_to_back: unsupported semantic ValueExpr", 3)
    end

    local function is_write_access(kind)
        return kind == Mem.MemStore or kind == Mem.MemAtomicStore or kind == Mem.MemAtomicRmw or kind == Mem.MemAtomicCas
    end

    local function is_read_access(kind)
        return kind == Mem.MemLoad or kind == Mem.MemAtomicLoad or kind == Mem.MemAtomicRmw or kind == Mem.MemAtomicCas
    end

    local function access_mode(access)
        if access.mode == Code.CodeMemoryWrite then return Back.BackAccessWrite end
        if access.mode == Code.CodeMemoryReadWrite then return Back.BackAccessReadWrite end
        return Back.BackAccessRead
    end

    local function back_alignment(alignment)
        local cls = pvm.classof(alignment)
        if alignment == nil or alignment == Mem.MemAlignUnknown then return Back.BackAlignUnknown end
        if cls == Mem.MemAlignKnown then return Back.BackAlignKnown(alignment.bytes) end
        if cls == Mem.MemAlignAtLeast then return Back.BackAlignAtLeast(alignment.bytes) end
        if cls == Mem.MemAlignAssumed then return Back.BackAlignAssumed(alignment.bytes, "MemBackendAccessInfo assumption") end
        return Back.BackAlignUnknown
    end

    local function back_trap(trap)
        local cls = pvm.classof(trap)
        if trap == Mem.MemMayTrap then return Back.BackMayTrap end
        if cls == Mem.MemNonTrapping then return Back.BackNonTrapping(trap.reason) end
        if cls == Mem.MemCheckedTrap then return Back.BackChecked(trap.reason) end
        return Back.BackMayTrap
    end

    local function back_bounds(info)
        if info ~= nil and pvm.classof(info.bounds) ~= Mem.MemBoundsUnknown then return Back.BackPtrInBounds("MemBackendAccessInfo bounds") end
        return Back.BackPtrBoundsUnknown
    end

    local function memory_info_for(ctx, access, info, suffix, deref_override)
        if access == nil or info == nil then error("lower_to_back: scalar kernel missing MemBackendAccessInfo", 3) end
        local deref_bytes = deref_override or info.deref_bytes
        local deref = deref_bytes and Back.BackDerefBytes(deref_bytes, "MemBackendAccessInfo") or Back.BackDerefUnknown
        local motion = info.movable and Back.BackCanMove("MemBackendAccessInfo movable") or Back.BackMayNotMove
        return Back.BackMemoryInfo(Back.BackAccessId(info.access.text .. (suffix or "")), back_alignment(info.alignment), deref, back_trap(info.trap), motion, access_mode(access.access))
    end

    local function const_zero(ctx)
        ctx.next_tmp = (ctx.next_tmp or 0) + 1
        local v = Back.BackValId("semantic.zero." .. tostring(ctx.next_tmp))
        ctx.cmds[#ctx.cmds + 1] = Back.CmdConst(v, Back.BackIndex, Back.BackLitInt("0"))
        return v
    end

    local function base_addr(ctx, base, info)
        local cls = pvm.classof(base)
        if cls == Mem.MemBaseValue or cls == Mem.MemBaseArgument then return Back.BackAddrValue(bid(base.value)) end
        if cls == Mem.MemBaseGlobal then return Back.BackAddrData(Back.BackDataId(base.global.text)) end
        if cls == Mem.MemBaseData then return Back.BackAddrData(Back.BackDataId(base.data.text)) end
        if cls == Mem.MemBaseProjection then
            local root = base_addr(ctx, base.base, info)
            ctx.next_tmp = (ctx.next_tmp or 0) + 1
            local ptr = Back.BackValId("semantic.base_projection." .. tostring(ctx.next_tmp))
            ctx.cmds[#ctx.cmds + 1] = Back.CmdPtrOffset(ptr, root, const_zero(ctx), 1, base.byte_offset or 0, Back.BackProvDerived("MemBaseProjection"), back_bounds(info))
            return Back.BackAddrValue(ptr)
        end
        error("lower_to_back: unsupported KernelStream base " .. tostring(cls), 3)
    end

    local function first_access(ctx, stream, want_write)
        for _, aid in ipairs(stream.accesses or {}) do
            local access = ctx.mem_access_by_id and ctx.mem_access_by_id[aid.text]
            if access ~= nil and ((want_write and is_write_access(access.kind)) or ((not want_write) and is_read_access(access.kind))) then
                return access, ctx.mem_backend_by_access and ctx.mem_backend_by_access[aid.text]
            end
        end
        local aid = stream.accesses and stream.accesses[1]
        if aid ~= nil then return ctx.mem_access_by_id[aid.text], ctx.mem_backend_by_access[aid.text] end
        return nil, nil
    end

    local function address_for_access(ctx, stream, access, info, index_expr)
        local index, index_ty = lower_value_expr(ctx, index_expr)
        if scalar(index_ty) ~= scalar(Code.CodeTyIndex) then
            ctx.next_tmp = (ctx.next_tmp or 0) + 1
            index = ensure_value_ty(ctx, Back.BackValId("semantic.index.cast." .. tostring(ctx.next_tmp)), Code.CodeTyIndex, index, index_ty)
        end
        ctx.next_tmp = (ctx.next_tmp or 0) + 1
        local ptr = Back.BackValId("semantic.ptr." .. tostring(ctx.next_tmp))
        local elem_size = 1
        local const_offset = 0
        local icls = access and pvm.classof(access.index) or nil
        if icls == Mem.MemIndexValue or icls == Mem.MemIndexInduction then
            elem_size = access.index.elem_size or 1
            const_offset = access.index.const_offset or 0
        end
        ctx.cmds[#ctx.cmds + 1] = Back.CmdPtrOffset(ptr, base_addr(ctx, stream.base, info), index, elem_size, const_offset, Back.BackProvDerived("KernelStream"), back_bounds(info))
        return Back.BackAddress(Back.BackAddrValue(ptr), const_zero(ctx), Back.BackProvDerived("KernelStream"), back_bounds(info))
    end

    local function kernel_value_back(ctx, kid)
        return (ctx.kernel_value_back and ctx.kernel_value_back[kid.text]) or Back.BackValId(kid.text)
    end

    local function lower_kernel_expr(ctx, expr)
        local cls = pvm.classof(expr)
        if cls == Kernel.KernelExprValue then return bid(expr.value), value_ty(ctx, expr.value) end
        if cls == Kernel.KernelExprKernelValue then
            local v = kernel_value_back(ctx, expr.value)
            return v, ctx.kernel_value_types and ctx.kernel_value_types[expr.value.text] or nil
        end
        if cls == Kernel.KernelExprAlgebra then return lower_value_expr(ctx, expr.expr) end
        if cls == Kernel.KernelExprLoad then
            local access, info = first_access(ctx, expr.stream, false)
            local addr = address_for_access(ctx, expr.stream, access, info, expr.index)
            ctx.next_tmp = (ctx.next_tmp or 0) + 1
            local dst = Back.BackValId("semantic.load." .. tostring(ctx.next_tmp))
            ctx.cmds[#ctx.cmds + 1] = Back.CmdLoadInfo(dst, shape(expr.stream.elem_ty), addr, memory_info_for(ctx, access, info, ":kernel_load"))
            return dst, expr.stream.elem_ty
        end
        error("lower_to_back: unsupported KernelExpr in scalar emitter", 3)
    end

    local function bind_kernel_value(ctx, binding)
        local dst = kernel_value_back(ctx, binding.id)
        local src, src_ty = lower_kernel_expr(ctx, binding.expr)
        if src_ty == nil then error("lower_to_back: KernelBinding source type is unknown for " .. binding.id.text, 3) end
        ensure_value_ty(ctx, dst, binding.ty, src, src_ty)
        ctx.kernel_value_types[binding.id.text] = binding.ty
        note_value(ctx, ctx.kernel_value_code_id and ctx.kernel_value_code_id[binding.id.text], binding.ty)
    end

    local function emit_kernel_effect(ctx, effect)
        local cls = pvm.classof(effect)
        if cls == Kernel.KernelEffectStore then
            local access, info = first_access(ctx, effect.dst, true)
            local value, value_ty0 = lower_kernel_expr(ctx, effect.value)
            if scalar(value_ty0) ~= scalar(effect.dst.elem_ty) then
                ctx.next_tmp = (ctx.next_tmp or 0) + 1
                value = ensure_value_ty(ctx, Back.BackValId("semantic.store.cast." .. tostring(ctx.next_tmp)), effect.dst.elem_ty, value, value_ty0)
            end
            local addr = address_for_access(ctx, effect.dst, access, info, effect.index)
            ctx.cmds[#ctx.cmds + 1] = Back.CmdStoreInfo(shape(effect.dst.elem_ty), addr, value, memory_info_for(ctx, access, info, ":kernel_store"))
        elseif cls == Kernel.KernelEffectFold then
            -- Scalar loop emission preserves reductions through the latch edge args
            -- produced by KernelBinding values; no separate Back command is needed.
            return
        else
            error("lower_to_back: unsupported KernelEffect reached scalar emitter", 3)
        end
    end

    local function edge_args(ctx, edge_fact)
        local args = {}
        for _, arg in ipairs(edge_fact and edge_fact.args or {}) do args[#args + 1] = bid(arg.src) end
        return args
    end

    local function emit_scalar_kernel_fragment(ctx, code_module, graph, flow, schedules, kernels, fragment)
        local strategy = fragment.strategy
        local kplan = kernel_by_id(kernels)[strategy.kernel.text]
        if kplan == nil then error("lower_to_back: scalar kernel strategy references missing kernel " .. strategy.kernel.text, 2) end
        local schedule = ctx.schedule_by_id and ctx.schedule_by_id[strategy.schedule.text]
        if schedule == nil then error("lower_to_back: scalar kernel strategy references missing schedule " .. strategy.schedule.text, 2) end
        if not (schedule.kind == Schedule.ScheduleScalarIndex or schedule.kind == Schedule.ScheduleScalarPointer) then
            error("lower_to_back: scalar kernel emitter received non-scalar schedule", 2)
        end
        if pvm.classof(kplan.subject) ~= Kernel.KernelSubjectLoop then error("lower_to_back: scalar kernel emitter supports loop subjects only", 2) end
        local loop = graph_loop_by_id(graph)[kplan.subject.loop.text]
        if loop == nil then error("lower_to_back: missing graph loop for scalar kernel", 2) end
        if #(loop.latches or {}) ~= 1 or #(loop.exits or {}) ~= 1 then error("lower_to_back: scalar kernel supports exactly one latch and one exit", 2) end
        local edge_facts = edge_fact_by_key(flow)
        local body_set = {}
        for _, gb in ipairs(loop.body or {}) do body_set[gb.block.text] = true end
        local bindings_by_block, effects_by_block = {}, {}
        for _, binding in ipairs(kplan.body.bindings or {}) do
            local block = ctx.kernel_value_block and ctx.kernel_value_block[binding.id.text]
            if block == nil then error("lower_to_back: cannot place KernelBinding " .. binding.id.text .. " in a Code block", 2) end
            bindings_by_block[block.text] = bindings_by_block[block.text] or {}
            bindings_by_block[block.text][#bindings_by_block[block.text] + 1] = binding
        end
        for _, effect in ipairs(kplan.body.effects or {}) do
            local ecls = pvm.classof(effect)
            if ecls == Kernel.KernelEffectStore then
                local access = first_access(ctx, effect.dst, true)
                local block = access and access.block and access.block.block
                if block == nil then error("lower_to_back: cannot place KernelEffectStore in a Code block", 2) end
                effects_by_block[block.text] = effects_by_block[block.text] or {}
                effects_by_block[block.text][#effects_by_block[block.text] + 1] = effect
            elseif ecls == Kernel.KernelEffectFold then
                -- Fold is represented by already-planned recurrence bindings and latch args.
            else
                error("lower_to_back: unsupported scalar KernelEffect", 2)
            end
        end
        local exit_edge = loop.exits[1]
        local latch_edge = loop.latches[1]
        local header = loop.header.block
        local header_exit_fact = edge_facts[exit_edge.from.block.text .. "\0" .. exit_edge.to.block.text]
        local latch_fact = edge_facts[latch_edge.from.block.text .. "\0" .. latch_edge.to.block.text]
        local body_successor = nil
        for _, fg in ipairs(graph.funcs or {}) do
            if fg.func == loop.func then
                for _, edge in ipairs(fg.edges or {}) do
                    if edge.from.block == header and body_set[edge.to.block.text] and edge.to.block ~= header then body_successor = edge.to.block end
                end
            end
        end
        if body_successor == nil then error("lower_to_back: scalar kernel cannot find header body successor", 2) end
        local loop_fact = nil
        for _, lf in ipairs(flow.loops or {}) do if lf.loop == loop.id then loop_fact = lf end end
        local cond = loop_fact and loop_fact.exits and loop_fact.exits[1] and loop_fact.exits[1].condition
        if cond == nil then error("lower_to_back: scalar kernel loop exit has no condition", 2) end
        ctx.cmds[#ctx.cmds + 1] = Back.CmdSwitchToBlock(block_id(header))
        for _, binding in ipairs(bindings_by_block[header.text] or {}) do bind_kernel_value(ctx, binding) end
        ctx.cmds[#ctx.cmds + 1] = Back.CmdBrIf(bid(cond), block_id(exit_edge.to.block), edge_args(ctx, header_exit_fact), block_id(body_successor), edge_args(ctx, edge_facts[exit_edge.from.block.text .. "\0" .. body_successor.text]))

        local func = ctx.current_func
        for _, block in ipairs(func.blocks or {}) do
            if body_set[block.id.text] and block.id ~= header then
                ctx.cmds[#ctx.cmds + 1] = Back.CmdSwitchToBlock(block_id(block.id))
                for _, binding in ipairs(bindings_by_block[block.id.text] or {}) do bind_kernel_value(ctx, binding) end
                for _, effect in ipairs(effects_by_block[block.id.text] or {}) do emit_kernel_effect(ctx, effect) end
                if block.id == latch_edge.from.block then
                    ctx.cmds[#ctx.cmds + 1] = Back.CmdJump(block_id(header), edge_args(ctx, latch_fact))
                else
                    local next_edge = nil
                    for _, fg in ipairs(graph.funcs or {}) do
                        if fg.func == loop.func then
                            for _, edge in ipairs(fg.edges or {}) do if edge.from.block == block.id and body_set[edge.to.block.text] then next_edge = edge end end
                        end
                    end
                    if next_edge == nil then error("lower_to_back: scalar kernel body block has no in-loop successor", 2) end
                    ctx.cmds[#ctx.cmds + 1] = Back.CmdJump(block_id(next_edge.to.block), edge_args(ctx, edge_facts[next_edge.from.block.text .. "\0" .. next_edge.to.block.text]))
                end
            end
        end
    end

    local function vector_for_lane_shape(lanes)
        if pvm.classof(lanes) ~= Schedule.LaneVector then error("lower_to_back: vector schedule requires LaneVector", 3) end
        return Back.BackVec(scalar(lanes.elem_ty), lanes.lanes), lanes.elem_ty, lanes.lanes
    end

    local function vec_int_op_for_value_expr(cls)
        if cls == Value.ValueExprAdd then return Back.BackVecIntAdd end
        if cls == Value.ValueExprSub then return Back.BackVecIntSub end
        if cls == Value.ValueExprMul then return Back.BackVecIntMul end
        return nil
    end

    local lower_vector_kernel_expr
    local function lower_vector_value_expr(ctx, expr, vec, elem_ty)
        local cls = pvm.classof(expr)
        if cls == Value.ValueExprValue then
            local cached = ctx.vector_value_by_code and ctx.vector_value_by_code[expr.value.text]
            if cached ~= nil then return cached end
            local kid = ctx.kernel_value_by_code and ctx.kernel_value_by_code[expr.value.text]
            if kid ~= nil then return lower_vector_kernel_expr(ctx, Kernel.KernelExprKernelValue(kid), vec, elem_ty) end
            local sv, sty = lower_value_expr(ctx, expr)
            if scalar(sty) ~= scalar(elem_ty) then
                ctx.next_tmp = (ctx.next_tmp or 0) + 1
                sv = ensure_value_ty(ctx, Back.BackValId("semantic.vec.scast." .. tostring(ctx.next_tmp)), elem_ty, sv, sty)
            end
            ctx.next_tmp = (ctx.next_tmp or 0) + 1
            local splat = Back.BackValId("semantic.vec.splat." .. tostring(ctx.next_tmp))
            ctx.cmds[#ctx.cmds + 1] = Back.CmdVecSplat(splat, vec, sv)
            return splat
        elseif cls == Value.ValueExprConst then
            local sv, sty = lower_value_expr(ctx, expr)
            if scalar(sty) ~= scalar(elem_ty) then
                ctx.next_tmp = (ctx.next_tmp or 0) + 1
                sv = ensure_value_ty(ctx, Back.BackValId("semantic.vec.const_cast." .. tostring(ctx.next_tmp)), elem_ty, sv, sty)
            end
            ctx.next_tmp = (ctx.next_tmp or 0) + 1
            local splat = Back.BackValId("semantic.vec.const_splat." .. tostring(ctx.next_tmp))
            ctx.cmds[#ctx.cmds + 1] = Back.CmdVecSplat(splat, vec, sv)
            return splat
        elseif cls == Value.ValueExprAdd or cls == Value.ValueExprSub or cls == Value.ValueExprMul then
            local a = lower_vector_value_expr(ctx, expr.a, vec, elem_ty)
            local b = lower_vector_value_expr(ctx, expr.b, vec, elem_ty)
            ctx.next_tmp = (ctx.next_tmp or 0) + 1
            local dst = Back.BackValId("semantic.vec.bin." .. tostring(ctx.next_tmp))
            ctx.cmds[#ctx.cmds + 1] = Back.CmdVecBinary(dst, vec_int_op_for_value_expr(cls), vec, a, b)
            return dst
        end
        -- Non-vector algebra values become scalar splats only when they do not depend
        -- on vector loads; unsupported mixed forms fail before scheduling once T042
        -- uses this emitter's capability classifier.
        local sv, sty = lower_value_expr(ctx, expr)
        if scalar(sty) ~= scalar(elem_ty) then
            ctx.next_tmp = (ctx.next_tmp or 0) + 1
            sv = ensure_value_ty(ctx, Back.BackValId("semantic.vec.fallback_cast." .. tostring(ctx.next_tmp)), elem_ty, sv, sty)
        end
        ctx.next_tmp = (ctx.next_tmp or 0) + 1
        local splat = Back.BackValId("semantic.vec.fallback_splat." .. tostring(ctx.next_tmp))
        ctx.cmds[#ctx.cmds + 1] = Back.CmdVecSplat(splat, vec, sv)
        return splat
    end

    lower_vector_kernel_expr = function(ctx, expr, vec, elem_ty)
        local cls = pvm.classof(expr)
        if cls == Kernel.KernelExprKernelValue then
            local cached = ctx.vector_value_by_kernel and ctx.vector_value_by_kernel[expr.value.text]
            if cached ~= nil then return cached end
            local binding = ctx.kernel_binding_by_id and ctx.kernel_binding_by_id[expr.value.text]
            if binding == nil then error("lower_to_back: vector KernelExprKernelValue has no binding " .. expr.value.text, 3) end
            local value = lower_vector_kernel_expr(ctx, binding.expr, vec, elem_ty)
            ctx.vector_value_by_kernel[expr.value.text] = value
            local code_id = ctx.kernel_value_code_id and ctx.kernel_value_code_id[expr.value.text]
            if code_id ~= nil then ctx.vector_value_by_code[code_id.text] = value end
            return value
        elseif cls == Kernel.KernelExprLoad then
            local access, info = first_access(ctx, expr.stream, false)
            local index_expr = ctx.vector_counter and Value.ValueExprValue(ctx.vector_counter) or expr.index
            local addr = address_for_access(ctx, expr.stream, access, info, index_expr)
            ctx.next_tmp = (ctx.next_tmp or 0) + 1
            local dst = Back.BackValId("semantic.vec.load." .. tostring(ctx.next_tmp))
            ctx.cmds[#ctx.cmds + 1] = Back.CmdLoadInfo(dst, Back.BackShapeVec(vec), addr, memory_info_for(ctx, access, info, ":kernel_vec_load", (info.deref_bytes or 0) * vec.lanes))
            return dst
        elseif cls == Kernel.KernelExprAlgebra then
            return lower_vector_value_expr(ctx, expr.expr, vec, elem_ty)
        elseif cls == Kernel.KernelExprValue then
            return lower_vector_value_expr(ctx, Value.ValueExprValue(expr.value), vec, elem_ty)
        end
        error("lower_to_back: unsupported KernelExpr in vector emitter", 3)
    end

    local function emit_vector_kernel_fragment(ctx, code_module, graph, flow, schedules, kernels, fragment)
        local strategy = fragment.strategy
        local kplan = kernel_by_id(kernels)[strategy.kernel.text]
        if kplan == nil then error("lower_to_back: vector kernel strategy references missing kernel", 2) end
        local schedule = ctx.schedule_by_id and ctx.schedule_by_id[strategy.schedule.text]
        if schedule == nil or pvm.classof(schedule.kind) ~= Schedule.ScheduleVector then error("lower_to_back: vector kernel strategy requires ScheduleVector", 2) end
        local vec, elem_ty, lanes = vector_for_lane_shape(schedule.kind.lanes)
        if schedule.kind.tail ~= Schedule.TailScalar and schedule.kind.tail ~= Schedule.TailNone then error("lower_to_back: vector kernel only implements TailScalar/TailNone", 2) end
        if pvm.classof(kplan.body.result) == Kernel.KernelResultReduction or pvm.classof(kplan.body.result) == Kernel.KernelResultClosedForm then error("lower_to_back: vector reductions are not implemented", 2) end
        local loop = graph_loop_by_id(graph)[kplan.subject.loop.text]
        if loop == nil or #(loop.latches or {}) ~= 1 or #(loop.exits or {}) ~= 1 then error("lower_to_back: vector kernel supports one loop/latch/exit", 2) end
        local loop_fact = nil
        for _, lf in ipairs(flow.loops or {}) do if lf.loop == loop.id then loop_fact = lf end end
        if loop_fact == nil or loop_fact.counted == nil or kplan.body.domain.counter == nil then error("lower_to_back: vector kernel requires counted loop and counter", 2) end
        local edge_facts = edge_fact_by_key(flow)
        local body_set = {}; for _, gb in ipairs(loop.body or {}) do body_set[gb.block.text] = true end
        local exit_edge, latch_edge = loop.exits[1], loop.latches[1]
        local header = loop.header.block
        local body_successor = nil
        for _, fg in ipairs(graph.funcs or {}) do if fg.func == loop.func then for _, edge in ipairs(fg.edges or {}) do if edge.from.block == header and body_set[edge.to.block.text] and edge.to.block ~= header then body_successor = edge.to.block end end end end
        if body_successor == nil then error("lower_to_back: vector kernel cannot find scalar tail body successor", 2) end
        local scalar_cond = loop_fact.exits and loop_fact.exits[1] and loop_fact.exits[1].condition
        if scalar_cond == nil then error("lower_to_back: vector kernel requires scalar exit condition", 2) end
        local vector_block = Back.BackBlockId(header.text .. ":kernel_vector")
        local tail_check = Back.BackBlockId(header.text .. ":kernel_tail")
        ctx.cmds[#ctx.cmds + 1] = Back.CmdCreateBlock(vector_block)
        ctx.cmds[#ctx.cmds + 1] = Back.CmdCreateBlock(tail_check)
        ctx.kernel_value_by_code = {}
        for _, binding in ipairs(kplan.body.bindings or {}) do
            ctx.kernel_binding_by_id[binding.id.text] = binding
            local code_id = ctx.kernel_value_code_id and ctx.kernel_value_code_id[binding.id.text]
            if code_id ~= nil then ctx.kernel_value_by_code[code_id.text] = binding.id end
        end
        local bindings_by_block, effects_by_block = {}, {}
        for _, binding in ipairs(kplan.body.bindings or {}) do
            local block = ctx.kernel_value_block and ctx.kernel_value_block[binding.id.text]
            if block ~= nil then
                bindings_by_block[block.text] = bindings_by_block[block.text] or {}
                bindings_by_block[block.text][#bindings_by_block[block.text] + 1] = binding
            end
        end
        for _, effect in ipairs(kplan.body.effects or {}) do
            if pvm.classof(effect) == Kernel.KernelEffectStore then
                local access = first_access(ctx, effect.dst, true)
                local block = access and access.block and access.block.block
                if block ~= nil then
                    effects_by_block[block.text] = effects_by_block[block.text] or {}
                    effects_by_block[block.text][#effects_by_block[block.text] + 1] = effect
                end
            end
        end

        ctx.cmds[#ctx.cmds + 1] = Back.CmdSwitchToBlock(block_id(header))
        -- Preserve original scalar exit condition for the tail path.
        local header_bindings = {}
        for _, binding in ipairs(kplan.body.bindings or {}) do if ctx.kernel_value_block[binding.id.text] == header then header_bindings[#header_bindings + 1] = binding end end
        for _, binding in ipairs(header_bindings) do bind_kernel_value(ctx, binding) end
        local counter = kplan.body.domain.counter
        local counter_ty = value_ty(ctx, counter)
        ctx.next_tmp = (ctx.next_tmp or 0) + 1
        local lane_const = Back.BackValId("semantic.vec.lanes." .. tostring(ctx.next_tmp))
        ctx.cmds[#ctx.cmds + 1] = Back.CmdConst(lane_const, scalar(counter_ty), Back.BackLitInt(tostring(lanes)))
        local next_i = Back.BackValId("semantic.vec.next_i." .. tostring(ctx.next_tmp))
        ctx.cmds[#ctx.cmds + 1] = Back.CmdIntBinary(next_i, Back.BackIntAdd, scalar(counter_ty), Back.BackIntSemantics(Back.BackIntWrap, Back.BackIntMayLose), bid(counter), lane_const)
        local stop_v, stop_ty = lower_value_expr(ctx, Value.ValueExprValue(loop_fact.counted.stop))
        if scalar(stop_ty) ~= scalar(counter_ty) then stop_v = ensure_value_ty(ctx, Back.BackValId("semantic.vec.stop_cast." .. tostring(ctx.next_tmp)), counter_ty, stop_v, stop_ty) end
        local vec_ok = Back.BackValId("semantic.vec.ok." .. tostring(ctx.next_tmp))
        ctx.cmds[#ctx.cmds + 1] = Back.CmdCompare(vec_ok, cmp_op(Core.CmpLe, counter_ty), shape(counter_ty), next_i, stop_v)
        ctx.cmds[#ctx.cmds + 1] = Back.CmdBrIf(vec_ok, vector_block, {}, tail_check, {})

        ctx.vector_value_by_kernel, ctx.vector_value_by_code = {}, {}
        ctx.vector_counter = kplan.body.domain.counter
        ctx.cmds[#ctx.cmds + 1] = Back.CmdSwitchToBlock(vector_block)
        for _, effect in ipairs(kplan.body.effects or {}) do
            if pvm.classof(effect) == Kernel.KernelEffectStore then
                local access, info = first_access(ctx, effect.dst, true)
                local addr = address_for_access(ctx, effect.dst, access, info, Value.ValueExprValue(kplan.body.domain.counter))
                local value = lower_vector_kernel_expr(ctx, effect.value, vec, elem_ty)
                ctx.cmds[#ctx.cmds + 1] = Back.CmdStoreInfo(Back.BackShapeVec(vec), addr, value, memory_info_for(ctx, access, info, ":kernel_vec_store", (info.deref_bytes or 0) * vec.lanes))
            elseif pvm.classof(effect) ~= Kernel.KernelEffectFold then
                error("lower_to_back: unsupported vector KernelEffect", 2)
            end
        end
        local jump_args = {}
        local latch_fact = edge_facts[latch_edge.from.block.text .. "\0" .. latch_edge.to.block.text]
        for _, arg in ipairs(latch_fact and latch_fact.args or {}) do
            if arg.dst_param == counter then jump_args[#jump_args + 1] = next_i else jump_args[#jump_args + 1] = bid(arg.dst_param) end
        end
        ctx.cmds[#ctx.cmds + 1] = Back.CmdJump(block_id(header), jump_args)

        ctx.cmds[#ctx.cmds + 1] = Back.CmdSwitchToBlock(tail_check)
        ctx.cmds[#ctx.cmds + 1] = Back.CmdBrIf(bid(scalar_cond), block_id(exit_edge.to.block), edge_args(ctx, edge_facts[exit_edge.from.block.text .. "\0" .. exit_edge.to.block.text]), block_id(body_successor), edge_args(ctx, edge_facts[exit_edge.from.block.text .. "\0" .. body_successor.text]))
        for _, block in ipairs(ctx.current_func.blocks or {}) do
            if body_set[block.id.text] and block.id ~= header then
                ctx.cmds[#ctx.cmds + 1] = Back.CmdSwitchToBlock(block_id(block.id))
                for _, binding in ipairs(bindings_by_block[block.id.text] or {}) do bind_kernel_value(ctx, binding) end
                for _, effect in ipairs(effects_by_block[block.id.text] or {}) do emit_kernel_effect(ctx, effect) end
                if block.id == latch_edge.from.block then
                    ctx.cmds[#ctx.cmds + 1] = Back.CmdJump(block_id(header), edge_args(ctx, latch_fact))
                else
                    local next_edge = nil
                    for _, fg in ipairs(graph.funcs or {}) do
                        if fg.func == loop.func then
                            for _, edge in ipairs(fg.edges or {}) do if edge.from.block == block.id and body_set[edge.to.block.text] then next_edge = edge end end
                        end
                    end
                    if next_edge == nil then error("lower_to_back: vector scalar-tail body block has no in-loop successor", 2) end
                    ctx.cmds[#ctx.cmds + 1] = Back.CmdJump(block_id(next_edge.to.block), edge_args(ctx, edge_facts[next_edge.from.block.text .. "\0" .. next_edge.to.block.text]))
                end
            end
        end
    end

    local function emit_closed_form_fragment(ctx, code_module, graph, flow, kernels, fragment)
        local strategy = fragment.strategy
        local kplan = kernel_by_id(kernels)[strategy.kernel.text]
        if kplan == nil then error("lower_to_back: closed-form strategy references missing kernel " .. strategy.kernel.text, 2) end
        if pvm.classof(kplan.subject) ~= Kernel.KernelSubjectLoop then error("lower_to_back: closed-form strategy only supports loop subjects", 2) end
        local loop = graph_loop_by_id(graph)[kplan.subject.loop.text]
        if loop == nil then error("lower_to_back: missing graph loop for closed-form fragment", 2) end
        if #(loop.exits or {}) ~= 1 then error("lower_to_back: closed-form emitter supports exactly one loop exit", 2) end
        local exit = loop.exits[1]
        local edge_facts = edge_fact_by_key(flow)
        local edge_fact = edge_facts[exit.from.block.text .. "\0" .. exit.to.block.text]
        if edge_fact == nil then error("lower_to_back: missing FlowEdgeFact for closed-form loop exit", 2) end
        local jump_dest, jump_args_fact = exit.to.block, edge_fact
        for _, func in ipairs(code_module.funcs or {}) do
            if func.id == loop.func then
                for _, block in ipairs(func.blocks or {}) do
                    if block.id == exit.to.block and pvm.classof(block.term.kind) == Code.CodeTermJump then
                        local next_key = block.id.text .. "\0" .. block.term.kind.dest.text
                        jump_dest = block.term.kind.dest
                        jump_args_fact = edge_facts[next_key] or edge_fact
                    end
                end
            end
        end
        ctx.cmds[#ctx.cmds + 1] = Back.CmdSwitchToBlock(block_id(loop.header.block))
        local result, _ = lower_value_expr(ctx, strategy.fact.expr)
        local args = {}
        for i, arg in ipairs(jump_args_fact.args or {}) do
            if arg.src == strategy.fact.reduction.accumulator then args[i] = result else args[i] = bid(arg.src) end
        end
        ctx.cmds[#ctx.cmds + 1] = Back.CmdJump(block_id(jump_dest), args)
    end

    local function emit_fragment(ctx, code_module, graph, flow, value, mem, effect, kernels, fragment)
        local cls = pvm.classof(fragment.strategy)
        if cls == Lower.LowerStrategyCode then
            local cmds = CodeToBack.fragment_commands(code_module, graph, flow, value, mem, effect, fragment.cover, { validate = false })
            for _, cmd in ipairs(cmds or {}) do ctx.cmds[#ctx.cmds + 1] = cmd end
            return
        end
        if cls == Lower.LowerStrategyKernel then
            local sched = ctx.schedule_by_id and ctx.schedule_by_id[fragment.strategy.schedule.text]
            if sched ~= nil and pvm.classof(sched.kind) == Schedule.ScheduleVector then
                emit_vector_kernel_fragment(ctx, code_module, graph, flow, ctx.schedules, kernels, fragment)
            else
                emit_scalar_kernel_fragment(ctx, code_module, graph, flow, ctx.schedules, kernels, fragment)
            end
            return
        elseif cls == Lower.LowerStrategyClosedForm then
            emit_closed_form_fragment(ctx, code_module, graph, flow, kernels, fragment)
            return
        elseif cls == Lower.LowerStrategyIntrinsic then
            error("lower_to_back: LowerStrategyIntrinsic has no Back emitter; planner must emit LowerStrategyCode/Call with explicit fallback or implement the intrinsic emitter", 2)
        elseif cls == Lower.LowerStrategyCall then
            error("lower_to_back: LowerStrategyCall has no Back emitter; planner must emit LowerStrategyCode with LowerIssueFallback or implement the call emitter", 2)
        end
        error("lower_to_back: unsupported LowerStrategy for Back emission", 2)
    end

    local function emit_func(ctx, code_module, graph, flow, value, mem, effect, func, func_plan, graph_loops)
        ctx.value_types = {}
        ctx.current_func = func
        ctx.kernel_value_back = {}
        ctx.kernel_value_types = {}
        ctx.kernel_value_block = {}
        ctx.kernel_value_code_id = {}
        ctx.kernel_binding_by_id = {}
        local function note_inst_dst(block, k)
            local cls = pvm.classof(k)
            local dst, ty = nil, nil
            if cls == Code.CodeInstConst then dst, ty = k.dst, k.const.ty
            elseif cls == Code.CodeInstAlias or cls == Code.CodeInstUnary or cls == Code.CodeInstBinary or cls == Code.CodeInstFloatBinary or cls == Code.CodeInstSelect then dst, ty = k.dst, k.ty
            elseif cls == Code.CodeInstCompare then dst, ty = k.dst, Code.CodeTyBool8
            elseif cls == Code.CodeInstCast then dst, ty = k.dst, k.to
            elseif cls == Code.CodeInstAddrOf or cls == Code.CodeInstGlobalRef or cls == Code.CodeInstPtrOffset then dst, ty = k.dst, k.ptr_ty
            elseif cls == Code.CodeInstLoad then dst, ty = k.dst, k.access.ty
            elseif cls == Code.CodeInstViewMake then dst, ty = k.dst, Code.CodeTyView(k.elem_ty)
            elseif cls == Code.CodeInstViewData then
                local vty = value_ty(ctx, k.view)
                if pvm.classof(vty) == Code.CodeTyLease then vty = vty.base end
                dst, ty = k.dst, Code.CodeTyDataPtr(pvm.classof(vty) == Code.CodeTyView and vty.elem or nil)
            elseif cls == Code.CodeInstViewLen or cls == Code.CodeInstViewStride then dst, ty = k.dst, Code.CodeTyIndex end
            if dst ~= nil and ty ~= nil then
                note_value(ctx, dst, ty)
                local kid = Kernel.KernelValueId("kval:" .. dst.text)
                ctx.kernel_value_back[kid.text] = bid(dst)
                ctx.kernel_value_types[kid.text] = ty
                ctx.kernel_value_block[kid.text] = block.id
                ctx.kernel_value_code_id[kid.text] = dst
            end
        end
        for _, param in ipairs(func.params or {}) do note_value(ctx, param.value, param.ty) end
        for _, b in ipairs(func.blocks or {}) do
            for _, param in ipairs(b.params or {}) do note_value(ctx, param.value, param.ty) end
            for _, inst in ipairs(b.insts or {}) do note_inst_dst(b, inst.kind) end
        end
        ctx.cmds[#ctx.cmds + 1] = Back.CmdBeginFunc(func_id(func.id))
        for _, b in ipairs(func.blocks or {}) do ctx.cmds[#ctx.cmds + 1] = Back.CmdCreateBlock(block_id(b.id)) end
        for _, b in ipairs(func.blocks or {}) do
            for _, param in ipairs(b.params or {}) do ctx.cmds[#ctx.cmds + 1] = Back.CmdAppendBlockParam(block_id(b.id), bid(param.value), shape(param.ty)) end
        end
        for _, fragment in ipairs(ordered_fragments_for_func(func, func_plan, graph_loops)) do emit_fragment(ctx, code_module, graph, flow, value, mem, effect, ctx.kernels, fragment) end
        ctx.cmds[#ctx.cmds + 1] = Back.CmdFinishFunc(func_id(func.id))
    end

    local function normalize_args(code_module, a, b, c, d, e, f, g, h)
        if a ~= nil and pvm.classof(a) == Lower.LowerModule then
            local lower = a
            local graph = CodeGraph.graph(code_module)
            local flow = lower.kernels and lower.kernels.flow or CodeFlowFacts.facts(code_module, graph)
            local value = lower.kernels and lower.kernels.value or CodeValueFacts.facts(code_module, graph, flow)
            local mem = lower.kernels and lower.kernels.mem or CodeMemFacts.semantic_facts(code_module, graph, flow, value, nil)
            local effect = lower.kernels and lower.kernels.effect or CodeEffectFacts.facts(code_module, graph, mem, nil)
            return graph, flow, value, mem, effect, lower.kernels, lower.schedules, lower
        end
        return a, b, c, d, e, f, g, h
    end

    local function module(code_module, graph, flow, value, mem, effect, kernels, schedules, lower)
        graph, flow, value, mem, effect, kernels, schedules, lower = normalize_args(code_module, graph, flow, value, mem, effect, kernels, schedules, lower)
        graph = graph or CodeGraph.graph(code_module)
        flow = flow or CodeFlowFacts.facts(code_module, graph)
        value = value or CodeValueFacts.facts(code_module, graph, flow)
        mem = mem or CodeMemFacts.semantic_facts(code_module, graph, flow, value, nil)
        effect = effect or CodeEffectFacts.facts(code_module, graph, mem, nil)
        kernels = kernels or CodeKernelPlan.plan(code_module, graph, flow, value, mem, effect)
        schedules = schedules or CodeSchedulePlan.plan(code_module, kernels, flow, value, mem, effect, nil)
        lower = lower or CodeLowerPlan.plan(code_module, graph, kernels, schedules, Lower.LowerTargetBack)

        local ctx = { cmds = {}, kernels = kernels, schedules = schedules, value_types = {}, next_tmp = 0, mem_access_by_id = {}, mem_backend_by_access = {}, schedule_by_id = {} }
        for _, access in ipairs(mem and mem.accesses or {}) do ctx.mem_access_by_id[access.id.text] = access end
        for _, info in ipairs(mem and mem.backend_info or {}) do ctx.mem_backend_by_access[info.access.text] = info end
        for _, sched in ipairs(schedules and schedules.schedules or {}) do if pvm.classof(sched) == Schedule.SchedulePlanned then ctx.schedule_by_id[sched.id.text] = sched end end
        for _, cmd in ipairs(CodeToBack.module_prelude_commands(code_module, { graph = graph, flow = flow, value = value, mem = mem, effect = effect, validate = false })) do ctx.cmds[#ctx.cmds + 1] = cmd end
        for _, func in ipairs(code_module.funcs or {}) do ctx.cmds[#ctx.cmds + 1] = CodeToBack.function_declare(func) end

        local funcs = func_by_id(code_module)
        local graph_loops = graph_indexes(graph)
        for _, func_plan in ipairs(lower.funcs or {}) do
            local func = funcs[func_plan.func.text]
            if func == nil then error("lower_to_back: LowerFuncPlan references missing function " .. func_plan.func.text, 2) end
            emit_func(ctx, code_module, graph, flow, value, mem, effect, func, func_plan, graph_loops)
        end
        ctx.cmds[#ctx.cmds + 1] = Back.CmdFinalizeModule
        return Back.BackProgram(ctx.cmds)
    end

    api.module = module

    T._moonlift_api_cache.lower_to_back = api
    return api
end

return M
