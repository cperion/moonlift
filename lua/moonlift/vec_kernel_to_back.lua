local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local C = T.Moon2Core
    local Ty = T.Moon2Type
    local Bn = T.Moon2Bind
    local Tr = T.Moon2Tree
    local V = T.Moon2Vec
    local Back = T.Moon2Back

    local scalar_api = require("moonlift.type_to_back_scalar").Define(T)
    local abi_api = require("moonlift.type_func_abi_plan").Define(T)

    local function append_all(out, xs) for i = 1, #xs do out[#out + 1] = xs[i] end end
    local function shape_scalar(s) return Back.BackShapeScalar(s) end
    local function shape_vec(v) return Back.BackShapeVec(v) end

    local function elem_scalar(elem)
        if elem == V.VecElemI32 then return Back.BackI32 end
        if elem == V.VecElemU32 then return Back.BackU32 end
        if elem == V.VecElemI64 then return Back.BackI64 end
        if elem == V.VecElemU64 then return Back.BackU64 end
        return nil
    end

    local function elem_size(elem)
        if elem == V.VecElemI32 or elem == V.VecElemU32 then return 4 end
        if elem == V.VecElemI64 or elem == V.VecElemU64 then return 8 end
        return nil
    end

    local function same_binding_slot(a, b)
        if a == b then return true end
        if a == nil or b == nil or a.name ~= b.name then return false end
        local ca, cb = pvm.classof(a.class), pvm.classof(b.class)
        if ca == Bn.BindingClassArg and cb == Bn.BindingClassArg then return a.class.index == b.class.index end
        return false
    end

    local function back_scalar(ty)
        local result = scalar_api.result(ty)
        if pvm.classof(result) == Ty.TypeBackScalarKnown then return result.scalar end
        return nil
    end

    local function is_view_type(ty) return pvm.classof(ty) == Ty.TView end

    local function abi_param_scalars(plan)
        local ps = {}
        for i = 1, #plan.params do
            local param = plan.params[i]
            local cls = pvm.classof(param)
            if cls == Ty.AbiParamScalar then ps[#ps + 1] = param.scalar
            elseif cls == Ty.AbiParamView then ps[#ps + 1] = Back.BackPtr; ps[#ps + 1] = Back.BackIndex; ps[#ps + 1] = Back.BackIndex end
        end
        return ps
    end

    local function abi_result_scalars(plan)
        if pvm.classof(plan.result) == Ty.AbiResultScalar then return { plan.result.scalar } end
        return {}
    end

    local function abi_param_values(plan)
        local values = {}
        for i = 1, #plan.params do
            local param = plan.params[i]
            local cls = pvm.classof(param)
            if cls == Ty.AbiParamScalar then values[#values + 1] = param.value
            elseif cls == Ty.AbiParamView then values[#values + 1] = param.data; values[#values + 1] = param.len; values[#values + 1] = param.stride end
        end
        return values
    end

    local function arg_value_for_binding(name, params, binding)
        for i = 1, #params do
            local param = abi_api.param_plan(name, params[i], i)
            if pvm.classof(param) == Ty.AbiParamScalar and same_binding_slot(param.binding, binding) then return param.value end
            if pvm.classof(param) == Ty.AbiParamView and same_binding_slot(param.binding, binding) then return param.data end
        end
        return nil
    end

    local function arg_len_for_binding(name, params, binding)
        for i = 1, #params do
            local param = abi_api.param_plan(name, params[i], i)
            if pvm.classof(param) == Ty.AbiParamView and same_binding_slot(param.binding, binding) then return param.len end
        end
        return arg_value_for_binding(name, params, binding)
    end

    local function ref_binding(expr)
        if pvm.classof(expr) == Tr.ExprRef and pvm.classof(expr.ref) == Bn.ValueRefBinding then return expr.ref.binding end
        return nil
    end

    local function literal_int_raw(expr)
        if pvm.classof(expr) == Tr.ExprLit and pvm.classof(expr.value) == C.LitInt then return expr.value.raw end
        return nil
    end

    local function scalar_alias_for_binding(scalars, binding)
        for i = 1, #(scalars or {}) do if same_binding_slot(scalars[i].binding, binding) then return scalars[i] end end
        return nil
    end

    local function cast_int_value(ctx, value, from_ty, to_ty, cmds)
        if value == nil or from_ty == nil or to_ty == nil then return nil end
        if from_ty == to_ty then return value end
        local id = ctx.next("int.cast")
        local op = to_ty == Back.BackIndex and Back.BackSextend or Back.BackIreduce
        cmds[#cmds + 1] = Back.CmdCast(id, op, to_ty, value)
        return id
    end

    local int_sem_wrap
    local emit_scalar_binary

    local function lower_int_expr(ctx, expr, desired_ty, cmds)
        local binding = ref_binding(expr)
        if binding ~= nil then
            local alias = scalar_alias_for_binding(ctx.scalars, binding)
            if alias ~= nil then return lower_int_expr(ctx, alias.value, desired_ty, cmds) end
            local value = arg_value_for_binding(ctx.name, ctx.params, binding)
            if value ~= nil then return cast_int_value(ctx, value, back_scalar(binding.ty) or desired_ty, desired_ty, cmds) end
        end
        local raw = literal_int_raw(expr)
        if raw ~= nil then local id = ctx.next("int.const"); cmds[#cmds + 1] = Back.CmdConst(id, desired_ty, Back.BackLitInt(raw)); return id end
        if pvm.classof(expr) == Tr.ExprLen then
            local view_binding = ref_binding(expr.value)
            if view_binding ~= nil then return cast_int_value(ctx, arg_len_for_binding(ctx.name, ctx.params, view_binding), Back.BackIndex, desired_ty, cmds) end
            return nil
        end
        if pvm.classof(expr) == Tr.ExprBinary then
            local lhs = lower_int_expr(ctx, expr.lhs, desired_ty, cmds)
            local rhs = lower_int_expr(ctx, expr.rhs, desired_ty, cmds)
            if lhs == nil or rhs == nil then return nil end
            local id = ctx.next("int.bin")
            if expr.op == C.BinAdd then
                cmds[#cmds + 1] = Back.CmdIntBinary(id, Back.BackIntAdd, desired_ty, int_sem_wrap(), lhs, rhs)
            elseif expr.op == C.BinSub then
                cmds[#cmds + 1] = Back.CmdIntBinary(id, Back.BackIntSub, desired_ty, int_sem_wrap(), lhs, rhs)
            elseif expr.op == C.BinMul then
                cmds[#cmds + 1] = Back.CmdIntBinary(id, Back.BackIntMul, desired_ty, int_sem_wrap(), lhs, rhs)
            else
                return nil
            end
            return id
        end
        return nil
    end

    local function scalar_value_expr(ctx, elem, expr)
        local scalar_ty = elem_scalar(elem)
        if scalar_ty == nil then return nil end
        if scalar_ty == Back.BackI32 or scalar_ty == Back.BackU32 or scalar_ty == Back.BackI64 or scalar_ty == Back.BackU64 then return lower_int_expr(ctx, expr, scalar_ty, ctx.cmds) end
        return nil
    end

    local function len_value_for_binding(ctx, binding, cmds, desired_ty)
        desired_ty = desired_ty or Back.BackI32
        local value = arg_len_for_binding(ctx.name, ctx.params, binding)
        if value ~= nil then
            local source_ty = is_view_type(binding.ty) and Back.BackIndex or (back_scalar(binding.ty) or desired_ty)
            return cast_int_value(ctx, value, source_ty, desired_ty, cmds)
        end
        local alias = scalar_alias_for_binding(ctx.scalars, binding)
        if alias ~= nil then return lower_int_expr(ctx, alias.value, desired_ty, cmds) end
        return nil
    end

    local function back_vec_op(op)
        if op == V.VecAdd then return Back.BackVecIntAdd end
        if op == V.VecSub then return Back.BackVecIntSub end
        if op == V.VecMul then return Back.BackVecIntMul end
        if op == V.VecBitAnd then return Back.BackVecBitAnd end
        if op == V.VecBitOr then return Back.BackVecBitOr end
        if op == V.VecBitXor then return Back.BackVecBitXor end
        return nil
    end

    local function back_vec_cmp_op(op)
        if op == V.VecCmpEq then return Back.BackVecIcmpEq end
        if op == V.VecCmpNe then return Back.BackVecIcmpNe end
        if op == V.VecCmpSLt then return Back.BackVecSIcmpLt end
        if op == V.VecCmpSLe then return Back.BackVecSIcmpLe end
        if op == V.VecCmpSGt then return Back.BackVecSIcmpGt end
        if op == V.VecCmpSGe then return Back.BackVecSIcmpGe end
        if op == V.VecCmpULt then return Back.BackVecUIcmpLt end
        if op == V.VecCmpULe then return Back.BackVecUIcmpLe end
        if op == V.VecCmpUGt then return Back.BackVecUIcmpGt end
        if op == V.VecCmpUGe then return Back.BackVecUIcmpGe end
        return nil
    end

    local function back_scalar_cmp_op(op)
        if op == V.VecCmpEq then return Back.BackIcmpEq end
        if op == V.VecCmpNe then return Back.BackIcmpNe end
        if op == V.VecCmpSLt then return Back.BackSIcmpLt end
        if op == V.VecCmpSLe then return Back.BackSIcmpLe end
        if op == V.VecCmpSGt then return Back.BackSIcmpGt end
        if op == V.VecCmpSGe then return Back.BackSIcmpGe end
        if op == V.VecCmpULt then return Back.BackUIcmpLt end
        if op == V.VecCmpULe then return Back.BackUIcmpLe end
        if op == V.VecCmpUGt then return Back.BackUIcmpGt end
        if op == V.VecCmpUGe then return Back.BackUIcmpGe end
        return nil
    end

    local function back_vec_mask_op(op)
        if op == V.VecMaskNot then return Back.BackVecMaskNot end
        if op == V.VecMaskAnd then return Back.BackVecMaskAnd end
        if op == V.VecMaskOr then return Back.BackVecMaskOr end
        return nil
    end

    local function reduction_parts(reduction, default_elem)
        local cls = pvm.classof(reduction)
        if cls == V.VecKernelReductionBin then return reduction.op, reduction.elem, reduction.identity end
        if cls == V.VecKernelReductionAdd then return V.VecAdd, reduction.elem, "0" end
        return nil, nil, nil
    end

    local function decision_lanes(decision)
        if decision ~= nil and pvm.classof(decision.schedule) == V.VecScheduleVector and pvm.classof(decision.schedule.shape) == V.VecVectorShape then return decision.schedule.shape.lanes end
        if decision ~= nil and pvm.classof(decision.chosen) == V.VecLoopVector and pvm.classof(decision.chosen.shape) == V.VecVectorShape then return decision.chosen.shape.lanes end
        return 4
    end

    local function decision_unroll(decision)
        if decision ~= nil and pvm.classof(decision.schedule) == V.VecScheduleVector then return decision.schedule.unroll end
        if decision ~= nil and pvm.classof(decision.chosen) == V.VecLoopVector then return decision.chosen.unroll end
        return 1
    end

    local function decision_interleave(decision)
        if decision ~= nil and pvm.classof(decision.schedule) == V.VecScheduleVector then return decision.schedule.interleave end
        return 1
    end

    local function decision_accumulators(decision)
        if decision ~= nil and pvm.classof(decision.schedule) == V.VecScheduleVector then return decision.schedule.accumulators end
        return 1
    end

    local function counter_ty_for_counter(counter)
        local cls = pvm.classof(counter)
        if cls == V.VecKernelCounterIndex then return Back.BackIndex end
        if cls == V.VecKernelCounterI32 then return Back.BackI32 end
        return nil
    end

    local function make_ctx(name, params, elem, tag, scalars, cmds, counter_ty, safety, alias_state, alignments)
        local counter = 0
        local access_counter = 0
        local scope = tag or ""
        return {
            name = name,
            params = params,
            elem = elem,
            scalars = scalars or {},
            cmds = cmds,
            counter_ty = counter_ty or Back.BackI32,
            safety = safety,
            alias_state = alias_state,
            alignments = alignments or {},
            scope = scope,
            next = function(prefix)
                counter = counter + 1
                return Back.BackValId("vec:" .. name .. ":" .. scope .. prefix .. tostring(counter))
            end,
            access = function(prefix)
                access_counter = access_counter + 1
                return Back.BackAccessId("vec:" .. name .. ":" .. scope .. prefix .. tostring(access_counter))
            end,
        }
    end

    local function binding_name(binding)
        return binding and binding.name or "unknown"
    end

    local function alignment_for_base(ctx, base)
        for i = 1, #(ctx.alignments or {}) do
            local a = ctx.alignments[i]
            if same_binding_slot(a.base, base) then
                local cls = pvm.classof(a)
                if cls == V.VecKernelAlignProven then return Back.BackAlignKnown(a.bytes) end
                if cls == V.VecKernelAlignAssumed then return Back.BackAlignAssumed(a.bytes, a.assumption.reason) end
            end
        end
        return Back.BackAlignUnknown
    end

    local function memory_info(ctx, mode, tag, bytes, base)
        local deref, trap = Back.BackDerefUnknown, Back.BackMayTrap
        local safety_cls = ctx.safety and pvm.classof(ctx.safety) or nil
        if bytes ~= nil and safety_cls == V.VecKernelSafetyProven then
            deref = Back.BackDerefBytes(bytes, "vec kernel safety proof")
            trap = Back.BackNonTrapping("vec kernel safety proof")
        elseif bytes ~= nil and safety_cls == V.VecKernelSafetyAssumed then
            deref = Back.BackDerefAssumed(bytes, "vec kernel safety assumption")
            trap = Back.BackNonTrapping("vec kernel safety assumption")
        end
        local access = ctx.access(tag or "mem")
        if ctx.alias_state ~= nil and base ~= nil then
            ctx.alias_state[#ctx.alias_state + 1] = { access = access, base = base, mode = mode }
        end
        return Back.BackMemoryInfo(access, alignment_for_base(ctx, base), deref, trap, Back.BackMayNotMove, mode)
    end

    local function address_for_binding(base, byte_offset, binding)
        return Back.BackAddress(Back.BackAddrValue(base), byte_offset, Back.BackProvArg(binding_name(binding)), Back.BackPtrBoundsUnknown)
    end

    local function alias_flags(aliases)
        local flags = { same_index = false, independent = false, assumed = false }
        for i = 1, #(aliases or {}) do
            local cls = pvm.classof(aliases[i])
            if cls == V.VecKernelAliasSameIndexSafe then flags.same_index = true end
            if cls == V.VecKernelAliasProven then flags.independent = true end
            if cls == V.VecKernelAliasAssumed then flags.assumed = true end
        end
        return flags
    end

    local function emit_alias_facts(cmds, aliases, access_log)
        if #(access_log or {}) == 0 then return end
        local flags = alias_flags(aliases)
        for i = 1, #access_log do
            local base = access_log[i].base
            cmds[#cmds + 1] = Back.CmdAliasFact(Back.BackAliasScope(access_log[i].access, Back.BackAliasScopeId("vec.base:" .. base.id.text)))
        end
        for i = 1, #access_log do
            for j = i + 1, #access_log do
                local a, b = access_log[i], access_log[j]
                local touches_write = a.mode == Back.BackAccessWrite or a.mode == Back.BackAccessReadWrite or b.mode == Back.BackAccessWrite or b.mode == Back.BackAccessReadWrite
                if touches_write then
                    if same_binding_slot(a.base, b.base) then
                        if flags.same_index then
                            cmds[#cmds + 1] = Back.CmdAliasFact(Back.BackSameBaseSameIndexSafe(a.access, b.access, "vec kernel same-index safety proof"))
                        else
                            cmds[#cmds + 1] = Back.CmdAliasFact(Back.BackMayAlias(a.access, b.access, "same vector kernel base"))
                        end
                    elseif flags.independent or flags.assumed then
                        local reason = flags.independent and "vec kernel alias proof" or "vec kernel alias assumption"
                        cmds[#cmds + 1] = Back.CmdAliasFact(Back.BackNoAlias(a.access, b.access, reason))
                    else
                        cmds[#cmds + 1] = Back.CmdAliasFact(Back.BackMayAlias(a.access, b.access, "no vector kernel alias proof"))
                    end
                end
            end
        end
    end

    int_sem_wrap = function()
        return Back.BackIntSemantics(Back.BackIntWrap, Back.BackIntMayLose)
    end

    emit_scalar_binary = function(cmds, dst, op, scalar, lhs, rhs)
        if op == V.VecAdd then cmds[#cmds + 1] = Back.CmdIntBinary(dst, Back.BackIntAdd, scalar, int_sem_wrap(), lhs, rhs); return true end
        if op == V.VecSub then cmds[#cmds + 1] = Back.CmdIntBinary(dst, Back.BackIntSub, scalar, int_sem_wrap(), lhs, rhs); return true end
        if op == V.VecMul then cmds[#cmds + 1] = Back.CmdIntBinary(dst, Back.BackIntMul, scalar, int_sem_wrap(), lhs, rhs); return true end
        if op == V.VecBitAnd then cmds[#cmds + 1] = Back.CmdBitBinary(dst, Back.BackBitAnd, scalar, lhs, rhs); return true end
        if op == V.VecBitOr then cmds[#cmds + 1] = Back.CmdBitBinary(dst, Back.BackBitOr, scalar, lhs, rhs); return true end
        if op == V.VecBitXor then cmds[#cmds + 1] = Back.CmdBitBinary(dst, Back.BackBitXor, scalar, lhs, rhs); return true end
        return false
    end

    local function offset_to_bytes(offset, ctx, cmds, base_off, elem_size_v)
        if offset == nil or offset == V.VecKernelOffsetZero then return base_off end
        if pvm.classof(offset) == V.VecKernelOffsetExpr then
            local scalar = lower_int_expr(ctx, offset.expr, Back.BackIndex, cmds)
            if scalar == nil then return nil end
            local byte_off, total = ctx.next("offset.bytes"), ctx.next("offset.total")
            cmds[#cmds + 1] = Back.CmdIntBinary(byte_off, Back.BackIntMul, Back.BackIndex, int_sem_wrap(), scalar, elem_size_v)
            cmds[#cmds + 1] = Back.CmdIntBinary(total, Back.BackIntAdd, Back.BackIndex, int_sem_wrap(), base_off, byte_off)
            return total
        end
        if pvm.classof(offset) == V.VecKernelOffsetAdd then
            local first = offset_to_bytes(offset.lhs, ctx, cmds, base_off, elem_size_v)
            if first == nil then return nil end
            return offset_to_bytes(offset.rhs, ctx, cmds, first, elem_size_v)
        end
        return nil
    end

    local lower_vec_expr
    local function lower_vec_mask_expr(expr, ctx, cmds, vec_ty, off, elem_size_v)
        local cls = pvm.classof(expr)
        if cls == V.VecKernelMaskCompare then
            local lhs = lower_vec_expr(expr.lhs, ctx, cmds, vec_ty, off, elem_size_v)
            local rhs = lower_vec_expr(expr.rhs, ctx, cmds, vec_ty, off, elem_size_v)
            local op = back_vec_cmp_op(expr.op)
            if lhs == nil or rhs == nil or op == nil then return nil end
            local dst = ctx.next("mask.cmp")
            cmds[#cmds + 1] = Back.CmdVecCompare(dst, op, vec_ty, lhs, rhs)
            return dst
        elseif cls == V.VecKernelMaskNot then
            local value = lower_vec_mask_expr(expr.value, ctx, cmds, vec_ty, off, elem_size_v)
            local op = back_vec_mask_op(V.VecMaskNot)
            if value == nil or op == nil then return nil end
            local dst = ctx.next("mask.not")
            cmds[#cmds + 1] = Back.CmdVecMask(dst, op, vec_ty, { value })
            return dst
        elseif cls == V.VecKernelMaskBin then
            local lhs = lower_vec_mask_expr(expr.lhs, ctx, cmds, vec_ty, off, elem_size_v)
            local rhs = lower_vec_mask_expr(expr.rhs, ctx, cmds, vec_ty, off, elem_size_v)
            local op = back_vec_mask_op(expr.op)
            if lhs == nil or rhs == nil or op == nil then return nil end
            local dst = ctx.next("mask.bin")
            cmds[#cmds + 1] = Back.CmdVecMask(dst, op, vec_ty, { lhs, rhs })
            return dst
        end
        return nil
    end

    lower_vec_expr = function(expr, ctx, cmds, vec_ty, off, elem_size_v)
        local cls = pvm.classof(expr)
        if cls == V.VecKernelExprLoad then
            local base = arg_value_for_binding(ctx.name, ctx.params, expr.base)
            if base == nil then return nil end
            local actual_off = offset_to_bytes(expr.offset, ctx, cmds, off, elem_size_v)
            if actual_off == nil then return nil end
            local loaded = ctx.next("vload")
            cmds[#cmds + 1] = Back.CmdLoadInfo(loaded, shape_vec(vec_ty), address_for_binding(base, actual_off, expr.base), memory_info(ctx, Back.BackAccessRead, "vload", elem_size(ctx.elem) * vec_ty.lanes, expr.base))
            return loaded
        elseif cls == V.VecKernelExprInvariant then
            local scalar = scalar_value_expr(ctx, ctx.elem, expr.expr)
            if scalar == nil then return nil end
            local splat = ctx.next("inv.splat")
            cmds[#cmds + 1] = Back.CmdVecSplat(splat, vec_ty, scalar)
            return splat
        elseif cls == V.VecKernelExprBin then
            local lhs = lower_vec_expr(expr.lhs, ctx, cmds, vec_ty, off, elem_size_v)
            local rhs = lower_vec_expr(expr.rhs, ctx, cmds, vec_ty, off, elem_size_v)
            local op = back_vec_op(expr.op)
            if lhs == nil or rhs == nil or op == nil then return nil end
            local dst = ctx.next("bin")
            cmds[#cmds + 1] = Back.CmdVecBinary(dst, op, vec_ty, lhs, rhs)
            return dst
        elseif cls == V.VecKernelExprSelect then
            local mask = lower_vec_mask_expr(expr.cond, ctx, cmds, vec_ty, off, elem_size_v)
            local then_value = lower_vec_expr(expr.then_value, ctx, cmds, vec_ty, off, elem_size_v)
            local else_value = lower_vec_expr(expr.else_value, ctx, cmds, vec_ty, off, elem_size_v)
            if mask == nil or then_value == nil or else_value == nil then return nil end
            local dst = ctx.next("select")
            cmds[#cmds + 1] = Back.CmdVecSelect(dst, vec_ty, mask, then_value, else_value)
            return dst
        end
        return nil
    end

    local lower_scalar_expr
    local function lower_scalar_mask_expr(expr, ctx, cmds, index, elem_size_v)
        local scalar_ty = elem_scalar(ctx.elem)
        local cls = pvm.classof(expr)
        if cls == V.VecKernelMaskCompare then
            local lhs = lower_scalar_expr(expr.lhs, ctx, cmds, index, elem_size_v)
            local rhs = lower_scalar_expr(expr.rhs, ctx, cmds, index, elem_size_v)
            local op = back_scalar_cmp_op(expr.op)
            if lhs == nil or rhs == nil or op == nil then return nil end
            local dst = ctx.next("tail.cmp")
            cmds[#cmds + 1] = Back.CmdCompare(dst, op, shape_scalar(scalar_ty), lhs, rhs)
            return dst
        elseif cls == V.VecKernelMaskNot then
            local value = lower_scalar_mask_expr(expr.value, ctx, cmds, index, elem_size_v)
            if value == nil then return nil end
            local zero, dst = ctx.next("tail.false"), ctx.next("tail.not")
            cmds[#cmds + 1] = Back.CmdConst(zero, Back.BackBool, Back.BackLitBool(false))
            cmds[#cmds + 1] = Back.CmdCompare(dst, Back.BackIcmpEq, shape_scalar(Back.BackBool), value, zero)
            return dst
        elseif cls == V.VecKernelMaskBin then
            local lhs = lower_scalar_mask_expr(expr.lhs, ctx, cmds, index, elem_size_v)
            local rhs = lower_scalar_mask_expr(expr.rhs, ctx, cmds, index, elem_size_v)
            if lhs == nil or rhs == nil then return nil end
            local dst = ctx.next("tail.mask.bin")
            if expr.op == V.VecMaskAnd then
                cmds[#cmds + 1] = Back.CmdBitBinary(dst, Back.BackBitAnd, Back.BackBool, lhs, rhs)
            elseif expr.op == V.VecMaskOr then
                cmds[#cmds + 1] = Back.CmdBitBinary(dst, Back.BackBitOr, Back.BackBool, lhs, rhs)
            else
                return nil
            end
            return dst
        end
        return nil
    end

    lower_scalar_expr = function(expr, ctx, cmds, index, elem_size_v)
        local scalar_ty = elem_scalar(ctx.elem)
        local cls = pvm.classof(expr)
        if cls == V.VecKernelExprLoad then
            local base = arg_value_for_binding(ctx.name, ctx.params, expr.base)
            if base == nil then return nil end
            local idx64, off, addr, loaded = ctx.next("tail.idx"), ctx.next("tail.off"), ctx.next("tail.addr"), ctx.next("tail.load")
            if ctx.counter_ty == Back.BackIndex then
                idx64 = index
            else
                cmds[#cmds + 1] = Back.CmdCast(idx64, Back.BackSextend, Back.BackIndex, index)
            end
            cmds[#cmds + 1] = Back.CmdIntBinary(off, Back.BackIntMul, Back.BackIndex, int_sem_wrap(), idx64, elem_size_v)
            off = offset_to_bytes(expr.offset, ctx, cmds, off, elem_size_v)
            if off == nil then return nil end
            cmds[#cmds + 1] = Back.CmdLoadInfo(loaded, shape_scalar(scalar_ty), address_for_binding(base, off, expr.base), memory_info(ctx, Back.BackAccessRead, "tail.load", elem_size(ctx.elem), expr.base))
            return loaded
        elseif cls == V.VecKernelExprInvariant then
            local scalar = scalar_value_expr(ctx, ctx.elem, expr.expr)
            if scalar == nil then return nil end
            return scalar
        elseif cls == V.VecKernelExprBin then
            local lhs = lower_scalar_expr(expr.lhs, ctx, cmds, index, elem_size_v)
            local rhs = lower_scalar_expr(expr.rhs, ctx, cmds, index, elem_size_v)
            if lhs == nil or rhs == nil then return nil end
            local dst = ctx.next("tail.bin")
            if not emit_scalar_binary(cmds, dst, expr.op, scalar_ty, lhs, rhs) then return nil end
            return dst
        elseif cls == V.VecKernelExprSelect then
            local mask = lower_scalar_mask_expr(expr.cond, ctx, cmds, index, elem_size_v)
            local then_value = lower_scalar_expr(expr.then_value, ctx, cmds, index, elem_size_v)
            local else_value = lower_scalar_expr(expr.else_value, ctx, cmds, index, elem_size_v)
            if mask == nil or then_value == nil or else_value == nil then return nil end
            local dst = ctx.next("tail.select")
            cmds[#cmds + 1] = Back.CmdSelect(dst, shape_scalar(scalar_ty), mask, then_value, else_value)
            return dst
        end
        return nil
    end

    local function common_prefix(name, visibility, params, result_ty)
        local sig, func = Back.BackSigId("sig:" .. name), Back.BackFuncId(name)
        local abi_plan = abi_api.plan(name, params, result_ty)
        return sig, func, abi_param_scalars(abi_plan), abi_result_scalars(abi_plan), abi_param_values(abi_plan)
    end

    local function lower_reduce(name, visibility, params, result_ty, decision, elem, stop_binding, counter, scalars, reduction, safety, alignments, aliases)
        local red_op, red_elem, identity = reduction_parts(reduction, elem)
        elem = red_elem or elem
        local scalar_ty = elem_scalar(elem)
        local vec_op = back_vec_op(red_op)
        if scalar_ty == nil or vec_op == nil or identity == nil or back_scalar(result_ty) ~= scalar_ty then return nil end
        local sig, func, param_scalars, result_scalars, param_vals = common_prefix(name, visibility, params, result_ty)
        local counter_ty = counter_ty_for_counter(counter)
        if counter_ty == nil then return nil end
        local lanes = decision_lanes(decision)
        local unroll = decision_unroll(decision)
        local interleave = decision_interleave(decision)
        local schedule_accumulators = decision_accumulators(decision)
        if unroll < 1 or interleave < 1 or schedule_accumulators < 1 or math.floor(unroll) ~= unroll or math.floor(interleave) ~= interleave or math.floor(schedule_accumulators) ~= schedule_accumulators then return nil end
        local accumulators = unroll * interleave * schedule_accumulators
        local stride_elems = lanes * accumulators
        local vec_ty = Back.BackVec(scalar_ty, lanes)
        local function b(s) return Back.BackBlockId("vec:" .. name .. ":" .. s) end
        local function v(s) return Back.BackValId("vec:" .. name .. ":" .. s) end
        local entry, loop, body, exitv, tail, tail_body, ret = Back.BackBlockId("entry:" .. name), b("reduce.loop"), b("reduce.body"), b("reduce.exit"), b("reduce.tail"), b("reduce.tail.body"), b("reduce.ret")
        local li, bi, ei, ti, tacc, tbi, tbacc, result = v("li"), v("bi"), v("ei"), v("ti"), v("tacc"), v("tbi"), v("tbacc"), v("result")
        local lacc, bacc, eacc = {}, {}, {}
        for a = 1, accumulators do
            lacc[a], bacc[a], eacc[a] = v("lacc" .. tostring(a)), v("bacc" .. tostring(a)), v("eacc" .. tostring(a))
        end
        local cmds = { Back.CmdCreateSig(sig, param_scalars, result_scalars), Back.CmdDeclareFunc(visibility, func, sig), Back.CmdBeginFunc(func), Back.CmdCreateBlock(entry), Back.CmdCreateBlock(loop), Back.CmdCreateBlock(body), Back.CmdCreateBlock(exitv), Back.CmdCreateBlock(tail), Back.CmdCreateBlock(tail_body), Back.CmdCreateBlock(ret) }
        cmds[#cmds + 1] = Back.CmdAppendBlockParam(loop, li, shape_scalar(counter_ty))
        for a = 1, accumulators do cmds[#cmds + 1] = Back.CmdAppendBlockParam(loop, lacc[a], shape_vec(vec_ty)) end
        cmds[#cmds + 1] = Back.CmdAppendBlockParam(body, bi, shape_scalar(counter_ty))
        for a = 1, accumulators do cmds[#cmds + 1] = Back.CmdAppendBlockParam(body, bacc[a], shape_vec(vec_ty)) end
        cmds[#cmds + 1] = Back.CmdAppendBlockParam(exitv, ei, shape_scalar(counter_ty))
        for a = 1, accumulators do cmds[#cmds + 1] = Back.CmdAppendBlockParam(exitv, eacc[a], shape_vec(vec_ty)) end
        cmds[#cmds + 1] = Back.CmdAppendBlockParam(tail, ti, shape_scalar(counter_ty))
        cmds[#cmds + 1] = Back.CmdAppendBlockParam(tail, tacc, shape_scalar(scalar_ty))
        cmds[#cmds + 1] = Back.CmdAppendBlockParam(tail_body, tbi, shape_scalar(counter_ty))
        cmds[#cmds + 1] = Back.CmdAppendBlockParam(tail_body, tbacc, shape_scalar(scalar_ty))
        cmds[#cmds + 1] = Back.CmdAppendBlockParam(ret, result, shape_scalar(scalar_ty))
        cmds[#cmds + 1] = Back.CmdSwitchToBlock(entry)
        cmds[#cmds + 1] = Back.CmdBindEntryParams(entry, param_vals)
        local alias_state = {}
        local entry_ctx = make_ctx(name, params, elem, "reduce.entry.", scalars, cmds, counter_ty, safety, alias_state, alignments)
        local stop_val = len_value_for_binding(entry_ctx, stop_binding, cmds, counter_ty)
        if stop_val == nil then return nil end
        local zero_i, zero_acc, stride, rem, main_stop, zero_vec, elem_size_v = v("zero.i"), v("zero.acc"), v("stride"), v("rem"), v("main.stop"), v("zero.vec"), v("elem.size")
        cmds[#cmds + 1] = Back.CmdConst(zero_i, counter_ty, Back.BackLitInt("0"))
        cmds[#cmds + 1] = Back.CmdConst(zero_acc, scalar_ty, Back.BackLitInt(identity))
        cmds[#cmds + 1] = Back.CmdConst(stride, counter_ty, Back.BackLitInt(tostring(stride_elems)))
        cmds[#cmds + 1] = Back.CmdConst(elem_size_v, Back.BackIndex, Back.BackLitInt(tostring(elem_size(elem))))
        cmds[#cmds + 1] = Back.CmdIntBinary(rem, Back.BackIntSRem, counter_ty, int_sem_wrap(), stop_val, stride)
        cmds[#cmds + 1] = Back.CmdIntBinary(main_stop, Back.BackIntSub, counter_ty, int_sem_wrap(), stop_val, rem)
        cmds[#cmds + 1] = Back.CmdVecSplat(zero_vec, vec_ty, zero_acc)
        local loop_init = { zero_i }
        for a = 1, accumulators do loop_init[#loop_init + 1] = zero_vec end
        cmds[#cmds + 1] = Back.CmdJump(loop, loop_init)
        cmds[#cmds + 1] = Back.CmdSealBlock(entry)
        cmds[#cmds + 1] = Back.CmdSwitchToBlock(loop)
        local cond = v("cond")
        cmds[#cmds + 1] = Back.CmdCompare(cond, Back.BackSIcmpLt, shape_scalar(counter_ty), li, main_stop)
        local body_args, exit_args = { li }, { li }
        for a = 1, accumulators do body_args[#body_args + 1], exit_args[#exit_args + 1] = lacc[a], lacc[a] end
        cmds[#cmds + 1] = Back.CmdBrIf(cond, body, body_args, exitv, exit_args)
        cmds[#cmds + 1] = Back.CmdSealBlock(body); cmds[#cmds + 1] = Back.CmdSealBlock(exitv)
        cmds[#cmds + 1] = Back.CmdSwitchToBlock(body)
        local next_accs = {}
        for a = 1, accumulators do
            local index = bi
            if a > 1 then
                local delta, stepped = v("acc" .. tostring(a) .. ".delta"), v("acc" .. tostring(a) .. ".index")
                cmds[#cmds + 1] = Back.CmdConst(delta, counter_ty, Back.BackLitInt(tostring((a - 1) * lanes)))
                cmds[#cmds + 1] = Back.CmdIntBinary(stepped, Back.BackIntAdd, counter_ty, int_sem_wrap(), bi, delta)
                index = stepped
            end
            local idx64, off = v("idx64." .. tostring(a)), v("off." .. tostring(a))
            if counter_ty == Back.BackIndex then idx64 = index else cmds[#cmds + 1] = Back.CmdCast(idx64, Back.BackSextend, Back.BackIndex, index) end
            cmds[#cmds + 1] = Back.CmdIntBinary(off, Back.BackIntMul, Back.BackIndex, int_sem_wrap(), idx64, elem_size_v)
            local value = lower_vec_expr(reduction.value, make_ctx(name, params, elem, "reduce.vec" .. tostring(a) .. ".", scalars, cmds, counter_ty, safety, alias_state, alignments), cmds, vec_ty, off, elem_size_v)
            if value == nil then return nil end
            local next_acc = v("next.acc" .. tostring(a))
            cmds[#cmds + 1] = Back.CmdVecBinary(next_acc, vec_op, vec_ty, bacc[a], value)
            next_accs[a] = next_acc
        end
        local next_i = v("next.i")
        cmds[#cmds + 1] = Back.CmdIntBinary(next_i, Back.BackIntAdd, counter_ty, int_sem_wrap(), bi, stride)
        local next_args = { next_i }
        for a = 1, accumulators do next_args[#next_args + 1] = next_accs[a] end
        cmds[#cmds + 1] = Back.CmdJump(loop, next_args)
        cmds[#cmds + 1] = Back.CmdSealBlock(loop)
        cmds[#cmds + 1] = Back.CmdSwitchToBlock(exitv)
        local reduced = nil
        for a = 1, accumulators do
            for lane = 0, lanes - 1 do
                local lane_v = v("reduce.acc" .. tostring(a) .. ".lane" .. tostring(lane))
                cmds[#cmds + 1] = Back.CmdVecExtractLane(lane_v, scalar_ty, eacc[a], lane)
                if reduced == nil then reduced = lane_v else local sum = v("reduce.acc" .. tostring(a) .. ".sum" .. tostring(lane)); if not emit_scalar_binary(cmds, sum, red_op, scalar_ty, reduced, lane_v) then return nil end; reduced = sum end
            end
        end
        cmds[#cmds + 1] = Back.CmdJump(tail, { ei, reduced })
        cmds[#cmds + 1] = Back.CmdSwitchToBlock(tail)
        local tail_cond = v("tail.cond")
        cmds[#cmds + 1] = Back.CmdCompare(tail_cond, Back.BackSIcmpLt, shape_scalar(counter_ty), ti, stop_val)
        cmds[#cmds + 1] = Back.CmdBrIf(tail_cond, tail_body, { ti, tacc }, ret, { tacc })
        cmds[#cmds + 1] = Back.CmdSealBlock(tail_body); cmds[#cmds + 1] = Back.CmdSealBlock(ret)
        cmds[#cmds + 1] = Back.CmdSwitchToBlock(tail_body)
        local tail_value = lower_scalar_expr(reduction.value, make_ctx(name, params, elem, "reduce.tail.", scalars, cmds, counter_ty, safety, alias_state, alignments), cmds, tbi, elem_size_v)
        if tail_value == nil then return nil end
        local tail_next_acc, one, tail_next_i = v("tail.next.acc"), v("tail.one"), v("tail.next.i")
        if not emit_scalar_binary(cmds, tail_next_acc, red_op, scalar_ty, tbacc, tail_value) then return nil end
        cmds[#cmds + 1] = Back.CmdConst(one, counter_ty, Back.BackLitInt("1"))
        cmds[#cmds + 1] = Back.CmdIntBinary(tail_next_i, Back.BackIntAdd, counter_ty, int_sem_wrap(), tbi, one)
        cmds[#cmds + 1] = Back.CmdJump(tail, { tail_next_i, tail_next_acc })
        cmds[#cmds + 1] = Back.CmdSealBlock(tail)
        cmds[#cmds + 1] = Back.CmdSwitchToBlock(ret)
        emit_alias_facts(cmds, aliases or {}, alias_state)
        cmds[#cmds + 1] = Back.CmdReturnValue(result)
        cmds[#cmds + 1] = Back.CmdFinishFunc(func)
        return Tr.TreeBackFuncResult(cmds)
    end

    local function lower_map(name, visibility, params, result_ty, decision, elem, stop_binding, counter, scalars, stores, safety, alignments, aliases)
        local scalar_ty = elem_scalar(elem)
        if scalar_ty == nil or #stores ~= 1 then return nil end
        local sig, func, param_scalars, result_scalars, param_vals = common_prefix(name, visibility, params, result_ty)
        local counter_ty = counter_ty_for_counter(counter)
        if counter_ty == nil then return nil end
        local lanes = decision_lanes(decision)
        local unroll = decision_unroll(decision)
        local interleave = decision_interleave(decision)
        local accumulators = decision_accumulators(decision)
        if unroll < 1 or interleave < 1 or accumulators ~= 1 or math.floor(unroll) ~= unroll or math.floor(interleave) ~= interleave then return nil end
        local groups = unroll * interleave
        local vec_ty = Back.BackVec(scalar_ty, lanes)
        local result_scalar = result_scalars[1] or Back.BackI32
        local function b(s) return Back.BackBlockId("vec:" .. name .. ":" .. s) end
        local function v(s) return Back.BackValId("vec:" .. name .. ":" .. s) end
        local entry, loop, body, tail, tail_body, ret = Back.BackBlockId("entry:" .. name), b("map.loop"), b("map.body"), b("map.tail"), b("map.tail.body"), b("map.ret")
        local li, bi, ti, tbi, result = v("li"), v("bi"), v("ti"), v("tbi"), v("result")
        local cmds = { Back.CmdCreateSig(sig, param_scalars, result_scalars), Back.CmdDeclareFunc(visibility, func, sig), Back.CmdBeginFunc(func), Back.CmdCreateBlock(entry), Back.CmdCreateBlock(loop), Back.CmdCreateBlock(body), Back.CmdCreateBlock(tail), Back.CmdCreateBlock(tail_body), Back.CmdCreateBlock(ret), Back.CmdAppendBlockParam(loop, li, shape_scalar(counter_ty)), Back.CmdAppendBlockParam(body, bi, shape_scalar(counter_ty)), Back.CmdAppendBlockParam(tail, ti, shape_scalar(counter_ty)), Back.CmdAppendBlockParam(tail_body, tbi, shape_scalar(counter_ty)), Back.CmdAppendBlockParam(ret, result, shape_scalar(result_scalar)), Back.CmdSwitchToBlock(entry), Back.CmdBindEntryParams(entry, param_vals) }
        local alias_state = {}
        local entry_ctx = make_ctx(name, params, elem, "map.entry.", scalars, cmds, counter_ty, safety, alias_state, alignments)
        local stop_val = len_value_for_binding(entry_ctx, stop_binding, cmds, counter_ty)
        if stop_val == nil then return nil end
        local zero, stride, rem, main_stop, elem_size_v = v("zero"), v("stride"), v("rem"), v("main.stop"), v("elem.size")
        cmds[#cmds + 1] = Back.CmdConst(zero, counter_ty, Back.BackLitInt("0"))
        cmds[#cmds + 1] = Back.CmdConst(stride, counter_ty, Back.BackLitInt(tostring(lanes * groups)))
        cmds[#cmds + 1] = Back.CmdConst(elem_size_v, Back.BackIndex, Back.BackLitInt(tostring(elem_size(elem))))
        cmds[#cmds + 1] = Back.CmdIntBinary(rem, Back.BackIntSRem, counter_ty, int_sem_wrap(), stop_val, stride)
        cmds[#cmds + 1] = Back.CmdIntBinary(main_stop, Back.BackIntSub, counter_ty, int_sem_wrap(), stop_val, rem)
        cmds[#cmds + 1] = Back.CmdJump(loop, { zero })
        cmds[#cmds + 1] = Back.CmdSealBlock(entry)
        cmds[#cmds + 1] = Back.CmdSwitchToBlock(loop)
        local cond = v("cond")
        cmds[#cmds + 1] = Back.CmdCompare(cond, Back.BackSIcmpLt, shape_scalar(counter_ty), li, main_stop)
        cmds[#cmds + 1] = Back.CmdBrIf(cond, body, { li }, tail, { li })
        cmds[#cmds + 1] = Back.CmdSealBlock(body)
        cmds[#cmds + 1] = Back.CmdSwitchToBlock(body)
        local dst_base = arg_value_for_binding(name, params, stores[1].dst)
        if dst_base == nil then return nil end
        for g = 1, groups do
            local index = bi
            if g > 1 then
                local delta, stepped = v("group" .. tostring(g) .. ".delta"), v("group" .. tostring(g) .. ".index")
                cmds[#cmds + 1] = Back.CmdConst(delta, counter_ty, Back.BackLitInt(tostring((g - 1) * lanes)))
                cmds[#cmds + 1] = Back.CmdIntBinary(stepped, Back.BackIntAdd, counter_ty, int_sem_wrap(), bi, delta)
                index = stepped
            end
            local idx64, off = v("idx64." .. tostring(g)), v("off." .. tostring(g))
            if counter_ty == Back.BackIndex then idx64 = index else cmds[#cmds + 1] = Back.CmdCast(idx64, Back.BackSextend, Back.BackIndex, index) end
            cmds[#cmds + 1] = Back.CmdIntBinary(off, Back.BackIntMul, Back.BackIndex, int_sem_wrap(), idx64, elem_size_v)
            local vec_ctx = make_ctx(name, params, elem, "map.vec" .. tostring(g) .. ".", scalars, cmds, counter_ty, safety, alias_state, alignments)
            local vec_value = lower_vec_expr(stores[1].value, vec_ctx, cmds, vec_ty, off, elem_size_v)
            local dst_off = offset_to_bytes(stores[1].offset, vec_ctx, cmds, off, elem_size_v)
            if vec_value == nil or dst_off == nil then return nil end
            cmds[#cmds + 1] = Back.CmdStoreInfo(shape_vec(vec_ty), address_for_binding(dst_base, dst_off, stores[1].dst), vec_value, memory_info(vec_ctx, Back.BackAccessWrite, "vstore", elem_size(elem) * lanes, stores[1].dst))
        end
        local next_i = v("next.i")
        cmds[#cmds + 1] = Back.CmdIntBinary(next_i, Back.BackIntAdd, counter_ty, int_sem_wrap(), bi, stride)
        cmds[#cmds + 1] = Back.CmdJump(loop, { next_i })
        cmds[#cmds + 1] = Back.CmdSealBlock(loop)
        cmds[#cmds + 1] = Back.CmdSwitchToBlock(tail)
        local tail_cond, ret_zero = v("tail.cond"), zero
        if counter_ty ~= result_scalar then
            ret_zero = v("ret.zero")
            cmds[#cmds + 1] = Back.CmdConst(ret_zero, result_scalar, Back.BackLitInt("0"))
        end
        cmds[#cmds + 1] = Back.CmdCompare(tail_cond, Back.BackSIcmpLt, shape_scalar(counter_ty), ti, stop_val)
        cmds[#cmds + 1] = Back.CmdBrIf(tail_cond, tail_body, { ti }, ret, { ret_zero })
        cmds[#cmds + 1] = Back.CmdSealBlock(tail_body); cmds[#cmds + 1] = Back.CmdSealBlock(ret)
        cmds[#cmds + 1] = Back.CmdSwitchToBlock(tail_body)
        local tail_ctx = make_ctx(name, params, elem, "map.tail.", scalars, cmds, counter_ty, safety, alias_state, alignments)
        local scalar_value = lower_scalar_expr(stores[1].value, tail_ctx, cmds, tbi, elem_size_v)
        if scalar_value == nil then return nil end
        local tidx64, toff, taddr, one, tail_next_i = v("tail.idx64"), v("tail.off"), v("tail.addr"), v("tail.one"), v("tail.next.i")
        if counter_ty == Back.BackIndex then tidx64 = tbi else cmds[#cmds + 1] = Back.CmdCast(tidx64, Back.BackSextend, Back.BackIndex, tbi) end
        cmds[#cmds + 1] = Back.CmdIntBinary(toff, Back.BackIntMul, Back.BackIndex, int_sem_wrap(), tidx64, elem_size_v)
        toff = offset_to_bytes(stores[1].offset, tail_ctx, cmds, toff, elem_size_v)
        if toff == nil then return nil end
        cmds[#cmds + 1] = Back.CmdStoreInfo(shape_scalar(scalar_ty), address_for_binding(dst_base, toff, stores[1].dst), scalar_value, memory_info(tail_ctx, Back.BackAccessWrite, "tail.store", elem_size(elem), stores[1].dst))
        cmds[#cmds + 1] = Back.CmdConst(one, counter_ty, Back.BackLitInt("1"))
        cmds[#cmds + 1] = Back.CmdIntBinary(tail_next_i, Back.BackIntAdd, counter_ty, int_sem_wrap(), tbi, one)
        cmds[#cmds + 1] = Back.CmdJump(tail, { tail_next_i })
        cmds[#cmds + 1] = Back.CmdSealBlock(tail)
        cmds[#cmds + 1] = Back.CmdSwitchToBlock(ret)
        emit_alias_facts(cmds, aliases or {}, alias_state)
        cmds[#cmds + 1] = Back.CmdReturnValue(result)
        cmds[#cmds + 1] = Back.CmdFinishFunc(func)
        return Tr.TreeBackFuncResult(cmds)
    end

    local function safety_allows(safety)
        local cls = pvm.classof(safety)
        return cls == V.VecKernelSafetyProven or cls == V.VecKernelSafetyAssumed
    end

    local function lower_func(name, visibility, params, result_ty, plan)
        local cls = pvm.classof(plan)
        if cls == V.VecKernelReduce then if not safety_allows(plan.safety) then return nil end; return lower_reduce(name, visibility, params, result_ty, plan.decision, plan.elem, plan.stop, plan.counter, plan.scalars, plan.reduction, plan.safety, plan.alignments, plan.aliases) end
        if cls == V.VecKernelMap then if not safety_allows(plan.safety) then return nil end; return lower_map(name, visibility, params, result_ty, plan.decision, plan.elem, plan.stop, plan.counter, plan.scalars, plan.stores, plan.safety, plan.alignments, plan.aliases) end
        return nil
    end

    return { lower_func = lower_func }
end

return M
