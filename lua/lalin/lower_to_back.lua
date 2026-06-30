local asdl = require("lalin.asdl")

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s:match("^%d") then s = "_" .. s end
    if s == "" then s = "x" end
    return s
end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.lower_to_back ~= nil then return T._lalin_api_cache.lower_to_back end

    local Code = T.LalinCode
    local Back = T.LalinBack
    local Lower = T.LalinLower
    local Kernel = T.LalinKernel
    local Schedule = T.LalinSchedule
    local Value = T.LalinValue
    local Mem = T.LalinMem
    local Core = T.LalinCore

    local CodeToBack = require("lalin.code_to_back")(T)
    local CodeGraph = require("lalin.code_graph")(T)
    local CodeFlowFacts = require("lalin.code_flow_facts")(T)
    local CodeValueFacts = require("lalin.code_value_facts")(T)
    local CodeMemFacts = require("lalin.code_mem_facts")(T)
    local CodeEffectFacts = require("lalin.code_effect_facts")(T)
    local CodeKernelPlan = require("lalin.code_kernel_plan")(T)
    local CodeSchedulePlan = require("lalin.code_schedule_plan")(T)
    local CodeLowerPlan = require("lalin.code_lower_plan")(T)
    local CodeAggregateAbi = require("lalin.code_aggregate_abi")(T)
    local ReductionAlgebra = require("lalin.reduction_algebra")(T)

    local api = {}

    function Schedule.ScheduleForm:lower_emit_kernel_selection()
        return Lower.LowerEmitScalarKernel
    end
    function Schedule.ScheduleVector:lower_emit_kernel_selection()
        return Lower.LowerEmitVectorKernel
    end
    function Schedule.KernelSchedule:lower_emit_kernel_selection()
        return Lower.LowerEmitScalarKernel
    end
    function Schedule.SchedulePlanned:lower_emit_kernel_selection()
        return self.form:lower_emit_kernel_selection()
    end

    function Lower.LowerStrategy:lower_emit_candidate(schedule)
        return Lower.LowerEmitUnsupportedCandidate("unsupported LowerStrategy for Back emission " .. tostring(asdl.class_basename(self) or self))
    end
    function Lower.LowerStrategyCode:lower_emit_candidate(schedule)
        return Lower.LowerEmitCodeCandidate
    end
    function Lower.LowerStrategyClosedForm:lower_emit_candidate(schedule)
        return Lower.LowerEmitClosedFormCandidate
    end
    function Lower.LowerStrategyKernel:lower_emit_candidate(schedule)
        if schedule == nil then return Lower.LowerEmitMissingScheduleCandidate(self:lower_emit_missing_schedule_reason()) end
        return Lower.LowerEmitKernelCandidate(schedule)
    end

    function Lower.LowerEmitCandidate:select_lower_emit()
        return Lower.LowerEmitUnsupported("unsupported lower emit candidate " .. tostring(asdl.class_basename(self) or self))
    end
    function Lower.LowerEmitCodeCandidate:select_lower_emit()
        return Lower.LowerEmitCode
    end
    function Lower.LowerEmitClosedFormCandidate:select_lower_emit()
        return Lower.LowerEmitClosedForm
    end
    function Lower.LowerEmitKernelCandidate:select_lower_emit()
        return self.schedule:lower_emit_kernel_selection()
    end
    function Lower.LowerEmitMissingScheduleCandidate:select_lower_emit()
        return Lower.LowerEmitMissingSchedule(self.reason)
    end
    function Lower.LowerEmitUnsupportedCandidate:select_lower_emit()
        return Lower.LowerEmitUnsupported(self.reason)
    end

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

    local function view_component_id(view, field)
        return Back.BackValId(view.text .. ":view_" .. field)
    end

    local function slice_component_id(slice, field)
        return Back.BackValId(slice.text .. ":slice_" .. field)
    end

    local function bytespan_component_id(span, field)
        return Back.BackValId(span.text .. ":bytespan_" .. field)
    end

    local function component_values(id, ty)
        if CodeAggregateAbi.is_view(ty) then return { view_component_id(id, "data"), view_component_id(id, "len"), view_component_id(id, "stride") } end
        if CodeAggregateAbi.is_slice(ty) then return { slice_component_id(id, "data"), slice_component_id(id, "len") } end
        if CodeAggregateAbi.is_byte_span(ty) then return { bytespan_component_id(id, "data"), bytespan_component_id(id, "len") } end
        return { bid(id) }
    end

    local function component_shapes(ty)
        local scalars = CodeAggregateAbi.component_scalars(ty)
        local out = {}
        for i = 1, #scalars do out[i] = Back.BackShapeScalar(scalars[i]) end
        return out
    end

    local function scalar(ty)
        local s = CodeToBack.scalar(ty)
        if s == nil then error("lower_to_back: unsupported scalar type for semantic emission", 3) end
        return s
    end

    local function note_value(back_emission, id, ty)
        if id ~= nil and ty ~= nil then back_emission.value_types[id.text] = ty end
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
        local cls = asdl.classof(cover)
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
        for _, kp in ipairs(kernels and kernels.plans or {}) do if asdl.classof(kp) == Kernel.KernelPlanned then out[kp.id.text] = kp end end
        return out
    end

    local function value_ty(back_emission, id)
        return id and back_emission.value_types[id.text] or nil
    end

    local function code_value(back_emission, id)
        local ov = id and back_emission.value_overrides and back_emission.value_overrides[id.text] or nil
        if ov ~= nil then return ov.value, ov.ty end
        return bid(id), value_ty(back_emission, id)
    end

    local function with_value_overrides(back_emission, overrides, fn)
        local old = back_emission.value_overrides
        back_emission.value_overrides = setmetatable(overrides or {}, { __index = old })
        local results = { pcall(fn) }
        back_emission.value_overrides = old
        if not results[1] then error(results[2], 0) end
        return unpack(results, 2)
    end

    local function int_op(op, ty)
        if op == "add" then return Back.BackIntAdd end
        if op == "sub" then return Back.BackIntSub end
        if op == "mul" then return Back.BackIntMul end
        if op == "div" then
            local cls = asdl.classof(ty)
            if ty == Code.CodeTyIndex or (cls == Code.CodeTyInt and ty.signedness == Code.CodeUnsigned) then return Back.BackIntUDiv end
            return Back.BackIntSDiv
        end
        if op == "rem" then
            local cls = asdl.classof(ty)
            if ty == Code.CodeTyIndex or (cls == Code.CodeTyInt and ty.signedness == Code.CodeUnsigned) then return Back.BackIntURem end
            return Back.BackIntSRem
        end
        error("lower_to_back: unsupported closed-form integer op " .. tostring(op), 3)
    end
    local function bit_op(op)
        if op == Core.BinBitAnd then return Back.BackBitAnd end
        if op == Core.BinBitOr then return Back.BackBitOr end
        if op == Core.BinBitXor then return Back.BackBitXor end
        return nil
    end
    local function shift_op(op)
        if op == Core.BinShl then return Back.BackShiftLeft end
        if op == Core.BinLShr then return Back.BackShiftLogicalRight end
        if op == Core.BinAShr then return Back.BackShiftArithmeticRight end
        return nil
    end

    local function int_sem(expr)
        local overflow = Back.BackIntWrap
        if expr and expr.sem and asdl.classof(expr.sem.overflow) == Code.CodeIntAssumeNoOverflow then overflow = Back.BackIntNoWrap(expr.sem.overflow.reason) end
        return Back.BackIntSemantics(overflow, Back.BackIntMayLose)
    end

    local function cmp_op(op, ty)
        local cls = asdl.classof(ty)
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

    local function fresh(back_emission, prefix)
        back_emission.next_tmp = (back_emission.next_tmp or 0) + 1
        return Back.BackValId((prefix or "semantic.tmp") .. "." .. tostring(back_emission.next_tmp))
    end

    local function reduction_entry(reduction, ty)
        local entry, why = ReductionAlgebra.entry(reduction.op, ty or reduction.ty)
        if entry == nil then error("lower_to_back: unsupported vector reduction " .. tostring(why), 3) end
        return entry
    end

    local function emit_reduction_scalar_identity(back_emission, entry)
        local dst = fresh(back_emission, "semantic.reduce.identity")
        back_emission.cmds[#back_emission.cmds + 1] = Back.CmdConst(dst, entry.scalar, Back.BackLitInt(entry.identity_raw))
        return dst
    end

    local function emit_reduction_vector_identity(back_emission, entry, vec)
        local scalar_id = emit_reduction_scalar_identity(back_emission, entry)
        local dst = fresh(back_emission, "semantic.reduce.vec_identity")
        back_emission.cmds[#back_emission.cmds + 1] = Back.CmdVecSplat(dst, vec, scalar_id)
        return dst
    end

    local function emit_reduction_scalar_combine(back_emission, entry, ty, lhs, rhs)
        local dst = fresh(back_emission, "semantic.reduce.scalar")
        if entry.scalar_int_op ~= nil then
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdIntBinary(dst, entry.scalar_int_op, scalar(ty), Back.BackIntSemantics(Back.BackIntWrap, Back.BackIntMayLose), lhs, rhs)
        elseif entry.scalar_bit_op ~= nil then
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdBitBinary(dst, entry.scalar_bit_op, scalar(ty), lhs, rhs)
        elseif entry.scalar_compare ~= nil then
            local cond = fresh(back_emission, "semantic.reduce.cmp")
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdCompare(cond, entry.scalar_compare, shape(ty), lhs, rhs)
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdSelect(dst, shape(ty), cond, lhs, rhs)
        else
            error("lower_to_back: reduction has no scalar combiner " .. tostring(entry.name), 3)
        end
        return dst
    end

    local function emit_reduction_vector_combine(back_emission, entry, vec, lhs, rhs)
        local dst = fresh(back_emission, "semantic.reduce.vector")
        if entry.vector_op ~= nil then
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdVecBinary(dst, entry.vector_op, vec, lhs, rhs)
        elseif entry.vector_compare ~= nil then
            local mask = fresh(back_emission, "semantic.reduce.vec_cmp")
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdVecCompare(mask, entry.vector_compare, vec, lhs, rhs)
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdVecSelect(dst, vec, mask, lhs, rhs)
        else
            error("lower_to_back: reduction has no vector combiner " .. tostring(entry.name), 3)
        end
        return dst
    end

    local function emit_reduction_horizontal_fold(back_emission, entry, ty, base_scalar, vector_acc, lanes)
        local acc = base_scalar
        for lane = 0, lanes - 1 do
            local lane_v = fresh(back_emission, "semantic.reduce.lane")
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdVecExtractLane(lane_v, scalar(ty), vector_acc, lane)
            acc = emit_reduction_scalar_combine(back_emission, entry, ty, acc, lane_v)
        end
        return acc
    end

    local function cast_op_for(from_ty, to_ty)
        local fcls, tcls = asdl.classof(from_ty), asdl.classof(to_ty)
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

    local function ensure_value_ty(back_emission, dst, to_ty, src, from_ty)
        if scalar(to_ty) == scalar(from_ty) then
            if dst.text ~= src.text then back_emission.cmds[#back_emission.cmds + 1] = Back.CmdAlias(dst, src) end
            return dst
        end
        back_emission.cmds[#back_emission.cmds + 1] = Back.CmdCast(dst, cast_op_for(from_ty, to_ty), scalar(to_ty), src)
        return dst
    end

    local function lower_value_expr(back_emission, expr)
        local cls = asdl.classof(expr)
        if cls == Value.ValueExprConst then
            back_emission.next_tmp = (back_emission.next_tmp or 0) + 1
            local v = Back.BackValId("semantic.const." .. tostring(back_emission.next_tmp))
            local ccls = asdl.classof(expr.const)
            if ccls ~= Code.CodeConstLiteral then error("lower_to_back: semantic const must be literal", 3) end
            local lit = expr.const.literal
            local lcls = asdl.classof(lit)
            local back_lit
            if lcls == Core.LitInt then back_lit = Back.BackLitInt(lit.raw)
            elseif lcls == Core.LitBool then back_lit = Back.BackLitBool(lit.value)
            elseif lcls == Core.LitFloat then back_lit = Back.BackLitFloat(lit.raw)
            else error("lower_to_back: unsupported semantic literal", 3) end
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdConst(v, scalar(expr.const.ty), back_lit)
            return v, expr.const.ty
        elseif cls == Value.ValueExprValue then
            local v, ty = code_value(back_emission, expr.value)
            if ty == nil then error("lower_to_back: semantic expression references unknown value " .. expr.value.text, 3) end
            return v, ty
        elseif cls == Value.ValueExprAdd or cls == Value.ValueExprSub or cls == Value.ValueExprMul or cls == Value.ValueExprDiv or cls == Value.ValueExprRem then
            local av, aty = lower_value_expr(back_emission, expr.a)
            local bv, bty = lower_value_expr(back_emission, expr.b)
            back_emission.next_tmp = (back_emission.next_tmp or 0) + 1
            local lhs = av
            if scalar(aty) ~= scalar(expr.ty) then lhs = ensure_value_ty(back_emission, Back.BackValId("semantic.cast." .. tostring(back_emission.next_tmp) .. ".lhs"), expr.ty, av, aty) end
            local rhs = bv
            if scalar(bty) ~= scalar(expr.ty) then rhs = ensure_value_ty(back_emission, Back.BackValId("semantic.cast." .. tostring(back_emission.next_tmp) .. ".rhs"), expr.ty, bv, bty) end
            local dst = Back.BackValId("semantic.tmp." .. tostring(back_emission.next_tmp))
            local op = (cls == Value.ValueExprAdd and "add") or (cls == Value.ValueExprSub and "sub") or (cls == Value.ValueExprMul and "mul") or (cls == Value.ValueExprRem and "rem") or "div"
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdIntBinary(dst, int_op(op, expr.ty), scalar(expr.ty), int_sem(expr), lhs, rhs)
            return dst, expr.ty
        elseif cls == Value.ValueExprBinary then
            local av, aty = lower_value_expr(back_emission, expr.a)
            local bv, bty = lower_value_expr(back_emission, expr.b)
            back_emission.next_tmp = (back_emission.next_tmp or 0) + 1
            local lhs = av
            if scalar(aty) ~= scalar(expr.ty) then lhs = ensure_value_ty(back_emission, Back.BackValId("semantic.cast." .. tostring(back_emission.next_tmp) .. ".bin_lhs"), expr.ty, av, aty) end
            local dst = Back.BackValId("semantic.tmp." .. tostring(back_emission.next_tmp))
            local bop = bit_op(expr.op)
            if bop ~= nil then
                local rhs = bv
                if scalar(bty) ~= scalar(expr.ty) then rhs = ensure_value_ty(back_emission, Back.BackValId("semantic.cast." .. tostring(back_emission.next_tmp) .. ".bin_rhs"), expr.ty, bv, bty) end
                back_emission.cmds[#back_emission.cmds + 1] = Back.CmdBitBinary(dst, bop, scalar(expr.ty), lhs, rhs)
                return dst, expr.ty
            end
            local sop = shift_op(expr.op)
            if sop ~= nil then
                back_emission.cmds[#back_emission.cmds + 1] = Back.CmdShift(dst, sop, scalar(expr.ty), lhs, bv)
                return dst, expr.ty
            end
            error("lower_to_back: unsupported binary ValueExpr op " .. tostring(expr.op), 3)
        elseif cls == Value.ValueExprCmp then
            local av, aty = lower_value_expr(back_emission, expr.a)
            local bv, bty = lower_value_expr(back_emission, expr.b)
            back_emission.next_tmp = (back_emission.next_tmp or 0) + 1
            local lhs = av
            if scalar(aty) ~= scalar(expr.ty) then lhs = ensure_value_ty(back_emission, Back.BackValId("semantic.cast." .. tostring(back_emission.next_tmp) .. ".cmp_lhs"), expr.ty, av, aty) end
            local rhs = bv
            if scalar(bty) ~= scalar(expr.ty) then rhs = ensure_value_ty(back_emission, Back.BackValId("semantic.cast." .. tostring(back_emission.next_tmp) .. ".cmp_rhs"), expr.ty, bv, bty) end
            local dst = Back.BackValId("semantic.cmp." .. tostring(back_emission.next_tmp))
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdCompare(dst, cmp_op(expr.op, expr.ty), shape(expr.ty), lhs, rhs)
            return dst, Code.CodeTyBool8
        elseif cls == Value.ValueExprSelect then
            local cv = lower_value_expr(back_emission, expr.cond)
            local tv, tty = lower_value_expr(back_emission, expr.t)
            local fv, fty = lower_value_expr(back_emission, expr.f)
            local ty = tty or fty
            back_emission.next_tmp = (back_emission.next_tmp or 0) + 1
            local tval = tv
            if scalar(tty) ~= scalar(ty) then tval = ensure_value_ty(back_emission, Back.BackValId("semantic.cast." .. tostring(back_emission.next_tmp) .. ".sel_t"), ty, tv, tty) end
            local fval = fv
            if scalar(fty) ~= scalar(ty) then fval = ensure_value_ty(back_emission, Back.BackValId("semantic.cast." .. tostring(back_emission.next_tmp) .. ".sel_f"), ty, fv, fty) end
            local dst = Back.BackValId("semantic.select." .. tostring(back_emission.next_tmp))
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdSelect(dst, shape(ty), cv, tval, fval)
            return dst, ty
        elseif cls == Value.ValueExprAffine then
            local acc = nil
            local ty = expr.affine.ty
            if expr.affine.constant ~= "0" then
                acc = lower_value_expr(back_emission, Value.ValueExprConst(Code.CodeConstLiteral(ty, Core.LitInt(expr.affine.constant))))
            end
            for _, term in ipairs(expr.affine.terms or {}) do
                local tv, tty = lower_value_expr(back_emission, Value.ValueExprValue(term.value))
                if scalar(tty) ~= scalar(ty) then
                    back_emission.next_tmp = (back_emission.next_tmp or 0) + 1
                    tv = ensure_value_ty(back_emission, Back.BackValId("semantic.affine.cast." .. tostring(back_emission.next_tmp)), ty, tv, tty)
                end
                if term.coeff ~= "1" then
                    back_emission.next_tmp = (back_emission.next_tmp or 0) + 1
                    local c = Back.BackValId("semantic.affine.coeff." .. tostring(back_emission.next_tmp))
                    back_emission.cmds[#back_emission.cmds + 1] = Back.CmdConst(c, scalar(ty), Back.BackLitInt(term.coeff))
                    local mul = Back.BackValId("semantic.affine.mul." .. tostring(back_emission.next_tmp))
                    back_emission.cmds[#back_emission.cmds + 1] = Back.CmdIntBinary(mul, Back.BackIntMul, scalar(ty), Back.BackIntSemantics(Back.BackIntWrap, Back.BackIntMayLose), tv, c)
                    tv = mul
                end
                if acc == nil then acc = tv else
                    back_emission.next_tmp = (back_emission.next_tmp or 0) + 1
                    local sum = Back.BackValId("semantic.affine.add." .. tostring(back_emission.next_tmp))
                    back_emission.cmds[#back_emission.cmds + 1] = Back.CmdIntBinary(sum, Back.BackIntAdd, scalar(ty), Back.BackIntSemantics(Back.BackIntWrap, Back.BackIntMayLose), acc, tv)
                    acc = sum
                end
            end
            if acc == nil then return lower_value_expr(back_emission, Value.ValueExprConst(Code.CodeConstLiteral(ty, Core.LitInt("0")))) end
            return acc, ty
        end
        error("lower_to_back: unsupported semantic ValueExpr", 3)
    end

    function Mem.MemAccessOp:lower_back_read_access(access, backend_access) return nil end
    function Mem.MemLoad:lower_back_read_access(access, backend_access) return access, backend_access end
    function Mem.MemAtomicLoad:lower_back_read_access(access, backend_access) return access, backend_access end
    function Mem.MemAtomicRmw:lower_back_read_access(access, backend_access) return access, backend_access end
    function Mem.MemAtomicCas:lower_back_read_access(access, backend_access) return access, backend_access end

    function Mem.MemAccessOp:lower_back_write_access(access, backend_access) return nil end
    function Mem.MemStore:lower_back_write_access(access, backend_access) return access, backend_access end
    function Mem.MemAtomicStore:lower_back_write_access(access, backend_access) return access, backend_access end
    function Mem.MemAtomicRmw:lower_back_write_access(access, backend_access) return access, backend_access end
    function Mem.MemAtomicCas:lower_back_write_access(access, backend_access) return access, backend_access end

    local function access_mode(access)
        if access.effect == Code.CodeMemoryWrite then return Back.BackAccessWrite end
        if access.effect == Code.CodeMemoryReadWrite then return Back.BackAccessReadWrite end
        return Back.BackAccessRead
    end

    local function back_alignment(alignment)
        local cls = asdl.classof(alignment)
        if alignment == nil or alignment == Mem.MemAlignUnknown then return Back.BackAlignUnknown end
        if cls == Mem.MemAlignKnown then return Back.BackAlignKnown(alignment.bytes) end
        if cls == Mem.MemAlignAtLeast then return Back.BackAlignAtLeast(alignment.bytes) end
        if cls == Mem.MemAlignAssumed then return Back.BackAlignAssumed(alignment.bytes, "MemBackendAccessInfo assumption") end
        return Back.BackAlignUnknown
    end

    local function back_trap(trap)
        local cls = asdl.classof(trap)
        if trap == Mem.MemMayTrap then return Back.BackMayTrap end
        if cls == Mem.MemNonTrapping then return Back.BackNonTrapping(trap.reason) end
        if cls == Mem.MemCheckedTrap then return Back.BackChecked(trap.reason) end
        return Back.BackMayTrap
    end

    local function back_bounds(backend_access)
        if backend_access ~= nil and asdl.classof(backend_access.bounds) ~= Mem.MemBoundsUnknown then return Back.BackPtrInBounds("MemBackendAccessInfo bounds") end
        return Back.BackPtrBoundsUnknown
    end

    local function memory_info_for(back_emission, access, backend_access, suffix, deref_override)
        if access == nil or backend_access == nil then error("lower_to_back: scalar kernel missing MemBackendAccessInfo", 3) end
        local deref_bytes = deref_override or backend_access.deref_bytes
        local deref = deref_bytes and Back.BackDerefBytes(deref_bytes, "MemBackendAccessInfo") or Back.BackDerefUnknown
        local motion = backend_access.movable and Back.BackCanMove("MemBackendAccessInfo movable") or Back.BackMayNotMove
        return Back.BackMemoryInfo(Back.BackAccessId(backend_access.access.text .. (suffix or "")), back_alignment(backend_access.alignment), deref, back_trap(backend_access.trap), motion, access_mode(access.access))
    end

    local function const_zero(back_emission)
        back_emission.next_tmp = (back_emission.next_tmp or 0) + 1
        local v = Back.BackValId("semantic.zero." .. tostring(back_emission.next_tmp))
        back_emission.cmds[#back_emission.cmds + 1] = Back.CmdConst(v, Back.BackIndex, Back.BackLitInt("0"))
        return v
    end

    local function base_addr(back_emission, base, backend_access)
        local cls = asdl.classof(base)
        if cls == Mem.MemBaseValue or cls == Mem.MemBaseArgument then
            local v = code_value(back_emission, base.value)
            return Back.BackAddrValue(v)
        end
        if cls == Mem.MemBaseGlobal then return Back.BackAddrData(Back.BackDataId(base.global.text)) end
        if cls == Mem.MemBaseData then return Back.BackAddrData(Back.BackDataId(base.data.text)) end
        if cls == Mem.MemBaseProjection then
            local root = base_addr(back_emission, base.base, backend_access)
            back_emission.next_tmp = (back_emission.next_tmp or 0) + 1
            local ptr = Back.BackValId("semantic.base_projection." .. tostring(back_emission.next_tmp))
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdPtrOffset(ptr, root, const_zero(back_emission), 1, base.byte_offset or 0, Back.BackProvDerived("MemBaseProjection"), back_bounds(backend_access))
            return Back.BackAddrValue(ptr)
        end
        error("lower_to_back: unsupported KernelLane base " .. tostring(cls), 3)
    end

    local function first_lane_access(back_emission, lane, selector)
        for _, aid in ipairs(lane.accesses or {}) do
            local access = back_emission.mem_projection and back_emission.mem_projection:mem_access(aid)
            local backend_access = back_emission.mem_projection and back_emission.mem_projection:backend_for_access(aid)
            if access ~= nil then
                local selected_access, selected_backend_access = access.op[selector](access.op, access, backend_access)
                if selected_access ~= nil then return selected_access, selected_backend_access end
            end
        end
        local aid = lane.accesses and lane.accesses[1]
        if aid ~= nil then return back_emission.mem_projection:mem_access(aid), back_emission.mem_projection:backend_for_access(aid) end
        return nil, nil
    end

    local function first_read_access(back_emission, lane)
        return first_lane_access(back_emission, lane, "lower_back_read_access")
    end

    local function first_write_access(back_emission, lane)
        return first_lane_access(back_emission, lane, "lower_back_write_access")
    end

    local function address_for_access(back_emission, lane, access, backend_access, index_expr)
        local index, index_ty = lower_value_expr(back_emission, index_expr)
        if scalar(index_ty) ~= scalar(Code.CodeTyIndex) then
            back_emission.next_tmp = (back_emission.next_tmp or 0) + 1
            index = ensure_value_ty(back_emission, Back.BackValId("semantic.index.cast." .. tostring(back_emission.next_tmp)), Code.CodeTyIndex, index, index_ty)
        end
        back_emission.next_tmp = (back_emission.next_tmp or 0) + 1
        local ptr = Back.BackValId("semantic.ptr." .. tostring(back_emission.next_tmp))
        local elem_size = 1
        local const_offset = 0
        local icls = access and asdl.classof(access.index) or nil
        if icls == Mem.MemIndexValue or icls == Mem.MemIndexInduction then
            elem_size = access.index.elem_size or 1
            const_offset = access.index.const_offset or 0
        end
        back_emission.cmds[#back_emission.cmds + 1] = Back.CmdPtrOffset(ptr, base_addr(back_emission, lane.base, backend_access), index, elem_size, const_offset, Back.BackProvDerived("KernelLane"), back_bounds(backend_access))
        return Back.BackAddress(Back.BackAddrValue(ptr), const_zero(back_emission), Back.BackProvDerived("KernelLane"), back_bounds(backend_access))
    end

    local function kernel_value_back(back_emission, kid)
        return (back_emission.kernel_value_back and back_emission.kernel_value_back[kid.text]) or Back.BackValId(kid.text)
    end

    local function lower_kernel_expr(back_emission, expr)
        local cls = asdl.classof(expr)
        if cls == Kernel.KernelExprValue then return code_value(back_emission, expr.value) end
        if cls == Kernel.KernelExprKernelValue then
            local v = kernel_value_back(back_emission, expr.value)
            return v, back_emission.kernel_value_types and back_emission.kernel_value_types[expr.value.text] or nil
        end
        if cls == Kernel.KernelExprAlgebra then return lower_value_expr(back_emission, expr.expr) end
        if cls == Kernel.KernelExprLaneLoad then
            local access, backend_access = first_read_access(back_emission, expr.lane)
            local addr = address_for_access(back_emission, expr.lane, access, backend_access, expr.index)
            back_emission.next_tmp = (back_emission.next_tmp or 0) + 1
            local dst = Back.BackValId("semantic.load." .. tostring(back_emission.next_tmp))
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdLoadInfo(dst, shape(expr.lane.elem_ty), addr, memory_info_for(back_emission, access, backend_access, ":kernel_load"))
            return dst, expr.lane.elem_ty
        end
        error("lower_to_back: unsupported KernelExpr in scalar emitter", 3)
    end

    local function bind_kernel_value(back_emission, binding)
        local dst = kernel_value_back(back_emission, binding.id)
        local src, src_ty = lower_kernel_expr(back_emission, binding.expr)
        if src_ty == nil then error("lower_to_back: KernelBinding source type is unknown for " .. binding.id.text, 3) end
        ensure_value_ty(back_emission, dst, binding.ty, src, src_ty)
        back_emission.kernel_value_types[binding.id.text] = binding.ty
        note_value(back_emission, back_emission.kernel_value_code_id and back_emission.kernel_value_code_id[binding.id.text], binding.ty)
    end

    local function value_expr_block(back_emission, expr)
        local cls = asdl.classof(expr)
        if cls == Value.ValueExprValue then return back_emission.value_block and back_emission.value_block[expr.value.text] end
        if cls == Value.ValueExprAdd or cls == Value.ValueExprSub or cls == Value.ValueExprMul or cls == Value.ValueExprDiv or cls == Value.ValueExprRem or cls == Value.ValueExprBinary or cls == Value.ValueExprCmp then
            return value_expr_block(back_emission, expr.a) or value_expr_block(back_emission, expr.b)
        end
        if cls == Value.ValueExprSelect then return value_expr_block(back_emission, expr.cond) or value_expr_block(back_emission, expr.t) or value_expr_block(back_emission, expr.f) end
        if cls == Value.ValueExprAffine then
            for _, term in ipairs(expr.affine.terms or {}) do
                local block = back_emission.value_block and back_emission.value_block[term.value.text]
                if block ~= nil then return block end
            end
        end
        return nil
    end

    local function kernel_binding_block(back_emission, binding)
        local block = back_emission.kernel_value_block and back_emission.kernel_value_block[binding.id.text]
        if block ~= nil then return block end
        local ecls = asdl.classof(binding.expr)
        if ecls == Kernel.KernelExprLaneLoad then
            local access = first_read_access(back_emission, binding.expr.lane)
            return access and access.block and access.block.block
        elseif ecls == Kernel.KernelExprValue then
            return back_emission.value_block and back_emission.value_block[binding.expr.value.text]
        elseif ecls == Kernel.KernelExprKernelValue then
            return back_emission.kernel_value_block and back_emission.kernel_value_block[binding.expr.value.text]
        elseif ecls == Kernel.KernelExprAlgebra then
            return value_expr_block(back_emission, binding.expr.expr)
        end
        return nil
    end

    local function emit_kernel_effect(back_emission, effect)
        local cls = asdl.classof(effect)
        if cls == Kernel.KernelEffectStore then
            local access, backend_access = first_write_access(back_emission, effect.dst)
            local value, value_ty0 = lower_kernel_expr(back_emission, effect.value)
            if scalar(value_ty0) ~= scalar(effect.dst.elem_ty) then
                back_emission.next_tmp = (back_emission.next_tmp or 0) + 1
                value = ensure_value_ty(back_emission, Back.BackValId("semantic.store.cast." .. tostring(back_emission.next_tmp)), effect.dst.elem_ty, value, value_ty0)
            end
            local addr = address_for_access(back_emission, effect.dst, access, backend_access, effect.index)
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdStoreInfo(shape(effect.dst.elem_ty), addr, value, memory_info_for(back_emission, access, backend_access, ":kernel_store"))
        elseif cls == Kernel.KernelEffectFold then
            -- Scalar loop emission preserves reductions through the latch edge args
            -- produced by KernelBinding values; no separate Back command is needed.
            return
        else
            error("lower_to_back: unsupported KernelEffect reached scalar emitter", 3)
        end
    end

    local function edge_args(back_emission, edge_fact, overrides)
        return with_value_overrides(back_emission, overrides, function()
            local args = {}
            for _, arg in ipairs(edge_fact and edge_fact.args or {}) do
                local v = code_value(back_emission, arg.src)
                args[#args + 1] = v
            end
            return args
        end)
    end

    local function reduction_effects(kplan)
        local out = {}
        for _, effect in ipairs(kplan.body.effects or {}) do
            if asdl.classof(effect) == Kernel.KernelEffectFold then out[#out + 1] = effect.reduction end
        end
        return out
    end

    local function reduction_overrides(reductions, values)
        local overrides = {}
        for i, reduction in ipairs(reductions or {}) do
            overrides[reduction.accumulator.text] = { value = values[i], ty = reduction.ty }
        end
        return overrides
    end

    local function merge_overrides(a, b)
        local out = {}
        for k, v in pairs(a or {}) do out[k] = v end
        for k, v in pairs(b or {}) do out[k] = v end
        return out
    end

    local function emit_scalar_kernel_fragment(back_emission, code_module, graph, flow, schedules, kernels, fragment)
        local strategy = fragment.strategy
        local kplan = kernel_by_id(kernels)[strategy.kernel.text]
        if kplan == nil then error("lower_to_back: scalar kernel strategy references missing kernel " .. strategy.kernel.text, 2) end
        local schedule = back_emission.schedule_by_id and back_emission.schedule_by_id[strategy.schedule.text]
        if schedule == nil then error("lower_to_back: scalar kernel strategy references missing schedule " .. strategy.schedule.text, 2) end
        if not (schedule.form == Schedule.ScheduleScalarIndex or schedule.form == Schedule.ScheduleScalarPointer) then
            error("lower_to_back: scalar kernel emitter received non-scalar schedule", 2)
        end
        if asdl.classof(kplan.subject) ~= Kernel.KernelSubjectLoop then error("lower_to_back: scalar kernel emitter supports loop subjects only", 2) end
        local loop = graph_loop_by_id(graph)[kplan.subject.loop.text]
        if loop == nil then error("lower_to_back: missing graph loop for scalar kernel", 2) end
        local latch_count = #(loop.latches or {})
        local exit_count = #(loop.exits or {})
        local loop_id = loop.id and loop.id.text or "<unknown>"
        if latch_count ~= 1 or exit_count ~= 1 then
            error(("lower_to_back: scalar kernel supports exactly one latch and one exit "
                .. "(loop %s has %d latch(es), %d exit(s))"):format(loop_id, latch_count, exit_count), 2)
        end
        local edge_facts = edge_fact_by_key(flow)
        local body_set = {}
        for _, gb in ipairs(loop.body or {}) do body_set[gb.block.text] = true end
        local bindings_by_block, effects_by_block = {}, {}
        for _, binding in ipairs(kplan.body.bindings or {}) do
            local block = kernel_binding_block(back_emission, binding)
            if block == nil then error("lower_to_back: cannot place KernelBinding " .. binding.id.text .. " in a Code block", 2) end
            bindings_by_block[block.text] = bindings_by_block[block.text] or {}
            bindings_by_block[block.text][#bindings_by_block[block.text] + 1] = binding
        end
        for _, effect in ipairs(kplan.body.effects or {}) do
            local ecls = asdl.classof(effect)
            if ecls == Kernel.KernelEffectStore then
                local access = first_write_access(back_emission, effect.dst)
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
        back_emission.cmds[#back_emission.cmds + 1] = Back.CmdSwitchToBlock(block_id(header))
        for _, binding in ipairs(bindings_by_block[header.text] or {}) do bind_kernel_value(back_emission, binding) end
        back_emission.cmds[#back_emission.cmds + 1] = Back.CmdBrIf(bid(cond), block_id(exit_edge.to.block), edge_args(back_emission, header_exit_fact), block_id(body_successor), edge_args(back_emission, edge_facts[exit_edge.from.block.text .. "\0" .. body_successor.text]))

        local func = back_emission.current_func
        for _, block in ipairs(func.blocks or {}) do
            if body_set[block.id.text] and block.id ~= header then
                back_emission.cmds[#back_emission.cmds + 1] = Back.CmdSwitchToBlock(block_id(block.id))
                for _, binding in ipairs(bindings_by_block[block.id.text] or {}) do bind_kernel_value(back_emission, binding) end
                for _, effect in ipairs(effects_by_block[block.id.text] or {}) do emit_kernel_effect(back_emission, effect) end
                if block.id == latch_edge.from.block then
                    back_emission.cmds[#back_emission.cmds + 1] = Back.CmdJump(block_id(header), edge_args(back_emission, latch_fact))
                else
                    local next_edge = nil
                    for _, fg in ipairs(graph.funcs or {}) do
                        if fg.func == loop.func then
                            for _, edge in ipairs(fg.edges or {}) do if edge.from.block == block.id and body_set[edge.to.block.text] then next_edge = edge end end
                        end
                    end
                    if next_edge == nil then error("lower_to_back: scalar kernel body block has no in-loop successor", 2) end
                    back_emission.cmds[#back_emission.cmds + 1] = Back.CmdJump(block_id(next_edge.to.block), edge_args(back_emission, edge_facts[next_edge.from.block.text .. "\0" .. next_edge.to.block.text]))
                end
            end
        end
    end

    local function vector_for_lane_shape(lanes)
        if asdl.classof(lanes) ~= Schedule.LaneVector then error("lower_to_back: vector schedule requires LaneVector", 3) end
        return Back.BackVec(scalar(lanes.elem_ty), lanes.lanes), lanes.elem_ty, lanes.lanes
    end

    local function vec_int_op_for_value_expr(cls)
        if cls == Value.ValueExprAdd then return Back.BackVecIntAdd end
        if cls == Value.ValueExprSub then return Back.BackVecIntSub end
        if cls == Value.ValueExprMul then return Back.BackVecIntMul end
        return nil
    end

    local function vec_cmp_op(op, ty)
        local cls = asdl.classof(ty)
        if cls == Code.CodeTyFloat then error("lower_to_back: Back has no vector float compare", 3) end
        local unsigned = ty == Code.CodeTyIndex or (cls == Code.CodeTyInt and ty.signedness == Code.CodeUnsigned) or ty == Code.CodeTyBool8
        if op == Core.CmpEq then return Back.BackVecIcmpEq end
        if op == Core.CmpNe then return Back.BackVecIcmpNe end
        if op == Core.CmpLt then return unsigned and Back.BackVecUIcmpLt or Back.BackVecSIcmpLt end
        if op == Core.CmpLe then return unsigned and Back.BackVecUIcmpLe or Back.BackVecSIcmpLe end
        if op == Core.CmpGt then return unsigned and Back.BackVecUIcmpGt or Back.BackVecSIcmpGt end
        if op == Core.CmpGe then return unsigned and Back.BackVecUIcmpGe or Back.BackVecSIcmpGe end
        error("lower_to_back: unsupported vector compare op", 3)
    end

    local lower_vector_kernel_expr
    local function lower_vector_value_expr(back_emission, expr, vec, elem_ty)
        local cls = asdl.classof(expr)
        if cls == Value.ValueExprValue then
            local cached = back_emission.vector_value_by_code and back_emission.vector_value_by_code[expr.value.text]
            if cached ~= nil then return cached end
            local kid = back_emission.kernel_value_by_code and back_emission.kernel_value_by_code[expr.value.text]
            if kid ~= nil then return lower_vector_kernel_expr(back_emission, Kernel.KernelExprKernelValue(kid), vec, elem_ty) end
            local sv, sty = lower_value_expr(back_emission, expr)
            if scalar(sty) ~= scalar(elem_ty) then
                back_emission.next_tmp = (back_emission.next_tmp or 0) + 1
                sv = ensure_value_ty(back_emission, Back.BackValId("semantic.vec.scast." .. tostring(back_emission.next_tmp)), elem_ty, sv, sty)
            end
            back_emission.next_tmp = (back_emission.next_tmp or 0) + 1
            local splat = Back.BackValId("semantic.vec.splat." .. tostring(back_emission.next_tmp))
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdVecSplat(splat, vec, sv)
            return splat
        elseif cls == Value.ValueExprConst then
            local sv, sty = lower_value_expr(back_emission, expr)
            if scalar(sty) ~= scalar(elem_ty) then
                back_emission.next_tmp = (back_emission.next_tmp or 0) + 1
                sv = ensure_value_ty(back_emission, Back.BackValId("semantic.vec.const_cast." .. tostring(back_emission.next_tmp)), elem_ty, sv, sty)
            end
            back_emission.next_tmp = (back_emission.next_tmp or 0) + 1
            local splat = Back.BackValId("semantic.vec.const_splat." .. tostring(back_emission.next_tmp))
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdVecSplat(splat, vec, sv)
            return splat
        elseif cls == Value.ValueExprAdd or cls == Value.ValueExprSub or cls == Value.ValueExprMul then
            local a = lower_vector_value_expr(back_emission, expr.a, vec, elem_ty)
            local b = lower_vector_value_expr(back_emission, expr.b, vec, elem_ty)
            back_emission.next_tmp = (back_emission.next_tmp or 0) + 1
            local dst = Back.BackValId("semantic.vec.bin." .. tostring(back_emission.next_tmp))
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdVecBinary(dst, vec_int_op_for_value_expr(cls), vec, a, b)
            return dst
        elseif cls == Value.ValueExprCmp then
            local a = lower_vector_value_expr(back_emission, expr.a, vec, elem_ty)
            local b = lower_vector_value_expr(back_emission, expr.b, vec, elem_ty)
            back_emission.next_tmp = (back_emission.next_tmp or 0) + 1
            local dst = Back.BackValId("semantic.vec.cmp." .. tostring(back_emission.next_tmp))
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdVecCompare(dst, vec_cmp_op(expr.op, expr.ty), vec, a, b)
            return dst
        elseif cls == Value.ValueExprSelect then
            local cond = lower_vector_value_expr(back_emission, expr.cond, vec, elem_ty)
            local tv = lower_vector_value_expr(back_emission, expr.t, vec, elem_ty)
            local fv = lower_vector_value_expr(back_emission, expr.f, vec, elem_ty)
            back_emission.next_tmp = (back_emission.next_tmp or 0) + 1
            local dst = Back.BackValId("semantic.vec.select." .. tostring(back_emission.next_tmp))
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdVecSelect(dst, vec, cond, tv, fv)
            return dst
        end
        -- Non-vector algebra values become scalar splats only when they do not depend
        -- on vector loads; unsupported mixed forms fail before scheduling once T042
        -- uses this emitter's capability classifier.
        local sv, sty = lower_value_expr(back_emission, expr)
        if scalar(sty) ~= scalar(elem_ty) then
            back_emission.next_tmp = (back_emission.next_tmp or 0) + 1
            sv = ensure_value_ty(back_emission, Back.BackValId("semantic.vec.fallback_cast." .. tostring(back_emission.next_tmp)), elem_ty, sv, sty)
        end
        back_emission.next_tmp = (back_emission.next_tmp or 0) + 1
        local splat = Back.BackValId("semantic.vec.fallback_splat." .. tostring(back_emission.next_tmp))
        back_emission.cmds[#back_emission.cmds + 1] = Back.CmdVecSplat(splat, vec, sv)
        return splat
    end

    lower_vector_kernel_expr = function(back_emission, expr, vec, elem_ty)
        local cls = asdl.classof(expr)
        if cls == Kernel.KernelExprKernelValue then
            local cached = back_emission.vector_value_by_kernel and back_emission.vector_value_by_kernel[expr.value.text]
            if cached ~= nil then return cached end
            local binding = back_emission.kernel_binding_by_id and back_emission.kernel_binding_by_id[expr.value.text]
            if binding == nil then error("lower_to_back: vector KernelExprKernelValue has no binding " .. expr.value.text, 3) end
            local value = lower_vector_kernel_expr(back_emission, binding.expr, vec, elem_ty)
            back_emission.vector_value_by_kernel[expr.value.text] = value
            local code_id = back_emission.kernel_value_code_id and back_emission.kernel_value_code_id[expr.value.text]
            if code_id ~= nil then back_emission.vector_value_by_code[code_id.text] = value end
            return value
        elseif cls == Kernel.KernelExprLaneLoad then
            local access, backend_access = first_read_access(back_emission, expr.lane)
            local index_expr = back_emission.vector_counter and Value.ValueExprValue(back_emission.vector_counter) or expr.index
            local addr = address_for_access(back_emission, expr.lane, access, backend_access, index_expr)
            back_emission.next_tmp = (back_emission.next_tmp or 0) + 1
            local dst = Back.BackValId("semantic.vec.load." .. tostring(back_emission.next_tmp))
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdLoadInfo(dst, Back.BackShapeVec(vec), addr, memory_info_for(back_emission, access, backend_access, ":kernel_vec_load", (backend_access.deref_bytes or 0) * vec.lanes))
            return dst
        elseif cls == Kernel.KernelExprAlgebra then
            return lower_vector_value_expr(back_emission, expr.expr, vec, elem_ty)
        elseif cls == Kernel.KernelExprValue then
            return lower_vector_value_expr(back_emission, Value.ValueExprValue(expr.value), vec, elem_ty)
        end
        error("lower_to_back: unsupported KernelExpr in vector emitter", 3)
    end

    local function emit_vector_kernel_fragment(back_emission, code_module, graph, flow, schedules, kernels, fragment)
        local strategy = fragment.strategy
        local kplan = kernel_by_id(kernels)[strategy.kernel.text]
        if kplan == nil then error("lower_to_back: vector kernel strategy references missing kernel", 2) end
        local schedule = back_emission.schedule_by_id and back_emission.schedule_by_id[strategy.schedule.text]
        if schedule == nil or asdl.classof(schedule.form) ~= Schedule.ScheduleVector then error("lower_to_back: vector kernel strategy requires ScheduleVector", 2) end
        local vec, elem_ty, lanes = vector_for_lane_shape(schedule.form.lanes)
        if schedule.form.tail ~= Schedule.TailScalar and schedule.form.tail ~= Schedule.TailNone then error("lower_to_back: vector kernel only implements TailScalar/TailNone", 2) end
        if asdl.classof(kplan.body.result) == Kernel.KernelResultClosedForm then error("lower_to_back: invalid vector schedule for closed-form result", 2) end
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
        local reductions = reduction_effects(kplan)
        local has_reductions = #reductions > 0
        if has_reductions and schedule.form.tail ~= Schedule.TailScalar then error("lower_to_back: vector reductions require TailScalar", 2) end
        local counter = kplan.body.domain.counter
        local counter_ty = value_ty(back_emission, counter)
        local vector_block = Back.BackBlockId(header.text .. ":kernel_vector")
        local tail_check = Back.BackBlockId(header.text .. ":kernel_tail")
        local vector_check = has_reductions and Back.BackBlockId(header.text .. ":kernel_vector_check") or nil
        local vector_done = has_reductions and Back.BackBlockId(header.text .. ":kernel_vector_done") or nil
        local tail_exit = has_reductions and Back.BackBlockId(header.text .. ":kernel_tail_exit") or nil
        if has_reductions then
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdCreateBlock(vector_check)
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdCreateBlock(vector_done)
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdCreateBlock(tail_exit)
        end
        back_emission.cmds[#back_emission.cmds + 1] = Back.CmdCreateBlock(vector_block)
        back_emission.cmds[#back_emission.cmds + 1] = Back.CmdCreateBlock(tail_check)

        local vector_counter_param, vector_body_counter_param, vector_done_counter_param, tail_counter_param
        local vector_acc_params, vector_body_acc_params, vector_done_acc_params, tail_acc_params = {}, {}, {}, {}
        if has_reductions then
            vector_counter_param = fresh(back_emission, "semantic.vec.i")
            vector_body_counter_param = fresh(back_emission, "semantic.vec.body_i")
            vector_done_counter_param = fresh(back_emission, "semantic.vec.done_i")
            tail_counter_param = fresh(back_emission, "semantic.vec.tail_i")
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdAppendBlockParam(vector_check, vector_counter_param, shape(counter_ty))
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdAppendBlockParam(vector_block, vector_body_counter_param, shape(counter_ty))
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdAppendBlockParam(vector_done, vector_done_counter_param, shape(counter_ty))
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdAppendBlockParam(tail_check, tail_counter_param, shape(counter_ty))
            for _, reduction in ipairs(reductions) do
                local vcp = fresh(back_emission, "semantic.vec.acc")
                local vbp = fresh(back_emission, "semantic.vec.body_acc")
                local vdp = fresh(back_emission, "semantic.vec.done_acc")
                local tap = fresh(back_emission, "semantic.vec.tail_acc")
                vector_acc_params[#vector_acc_params + 1] = vcp
                vector_body_acc_params[#vector_body_acc_params + 1] = vbp
                vector_done_acc_params[#vector_done_acc_params + 1] = vdp
                tail_acc_params[#tail_acc_params + 1] = tap
                back_emission.cmds[#back_emission.cmds + 1] = Back.CmdAppendBlockParam(vector_check, vcp, Back.BackShapeVec(vec))
                back_emission.cmds[#back_emission.cmds + 1] = Back.CmdAppendBlockParam(vector_block, vbp, Back.BackShapeVec(vec))
                back_emission.cmds[#back_emission.cmds + 1] = Back.CmdAppendBlockParam(vector_done, vdp, Back.BackShapeVec(vec))
                back_emission.cmds[#back_emission.cmds + 1] = Back.CmdAppendBlockParam(tail_check, tap, shape(reduction.ty))
            end
        end

        back_emission.kernel_value_by_code = {}
        for _, binding in ipairs(kplan.body.bindings or {}) do
            back_emission.kernel_binding_by_id[binding.id.text] = binding
            local code_id = back_emission.kernel_value_code_id and back_emission.kernel_value_code_id[binding.id.text]
            if code_id ~= nil then back_emission.kernel_value_by_code[code_id.text] = binding.id end
        end
        local bindings_by_block, effects_by_block = {}, {}
        for _, binding in ipairs(kplan.body.bindings or {}) do
            local block = back_emission.kernel_value_block and back_emission.kernel_value_block[binding.id.text]
            if block ~= nil then
                bindings_by_block[block.text] = bindings_by_block[block.text] or {}
                bindings_by_block[block.text][#bindings_by_block[block.text] + 1] = binding
            end
        end
        for _, effect in ipairs(kplan.body.effects or {}) do
            if asdl.classof(effect) == Kernel.KernelEffectStore then
                local access = first_write_access(back_emission, effect.dst)
                local block = access and access.block and access.block.block
                if block ~= nil then
                    effects_by_block[block.text] = effects_by_block[block.text] or {}
                    effects_by_block[block.text][#effects_by_block[block.text] + 1] = effect
                end
            end
        end

        back_emission.cmds[#back_emission.cmds + 1] = Back.CmdSwitchToBlock(block_id(header))
        local header_bindings = {}
        for _, binding in ipairs(kplan.body.bindings or {}) do if back_emission.kernel_value_block[binding.id.text] == header then header_bindings[#header_bindings + 1] = binding end end
        for _, binding in ipairs(header_bindings) do bind_kernel_value(back_emission, binding) end
        back_emission.next_tmp = (back_emission.next_tmp or 0) + 1
        local lane_const = Back.BackValId("semantic.vec.lanes." .. tostring(back_emission.next_tmp))
        back_emission.cmds[#back_emission.cmds + 1] = Back.CmdConst(lane_const, scalar(counter_ty), Back.BackLitInt(tostring(lanes)))
        local next_i = Back.BackValId("semantic.vec.next_i." .. tostring(back_emission.next_tmp))
        back_emission.cmds[#back_emission.cmds + 1] = Back.CmdIntBinary(next_i, Back.BackIntAdd, scalar(counter_ty), Back.BackIntSemantics(Back.BackIntWrap, Back.BackIntMayLose), bid(counter), lane_const)
        local stop_v, stop_ty = lower_value_expr(back_emission, Value.ValueExprValue(loop_fact.counted.stop))
        if scalar(stop_ty) ~= scalar(counter_ty) then stop_v = ensure_value_ty(back_emission, Back.BackValId("semantic.vec.stop_cast." .. tostring(back_emission.next_tmp)), counter_ty, stop_v, stop_ty) end
        local vec_ok = Back.BackValId("semantic.vec.ok." .. tostring(back_emission.next_tmp))
        back_emission.cmds[#back_emission.cmds + 1] = Back.CmdCompare(vec_ok, cmp_op(Core.CmpLe, counter_ty), shape(counter_ty), next_i, stop_v)
        if has_reductions then
            local init_args = { bid(counter) }
            for _, reduction in ipairs(reductions) do init_args[#init_args + 1] = emit_reduction_vector_identity(back_emission, reduction_entry(reduction, elem_ty), vec) end
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdJump(vector_check, init_args)
        else
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdBrIf(vec_ok, vector_block, {}, tail_check, {})
        end

        back_emission.vector_counter = kplan.body.domain.counter
        if has_reductions then
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdSwitchToBlock(vector_check)
            with_value_overrides(back_emission, { [counter.text] = { value = vector_counter_param, ty = counter_ty } }, function()
                local step = fresh(back_emission, "semantic.vec.lanes")
                back_emission.cmds[#back_emission.cmds + 1] = Back.CmdConst(step, scalar(counter_ty), Back.BackLitInt(tostring(lanes)))
                local check_next_i = fresh(back_emission, "semantic.vec.next_i")
                back_emission.cmds[#back_emission.cmds + 1] = Back.CmdIntBinary(check_next_i, Back.BackIntAdd, scalar(counter_ty), Back.BackIntSemantics(Back.BackIntWrap, Back.BackIntMayLose), vector_counter_param, step)
                local check_stop, check_stop_ty = lower_value_expr(back_emission, Value.ValueExprValue(loop_fact.counted.stop))
                if scalar(check_stop_ty) ~= scalar(counter_ty) then check_stop = ensure_value_ty(back_emission, fresh(back_emission, "semantic.vec.stop_cast"), counter_ty, check_stop, check_stop_ty) end
                local check_ok = fresh(back_emission, "semantic.vec.ok")
                back_emission.cmds[#back_emission.cmds + 1] = Back.CmdCompare(check_ok, cmp_op(Core.CmpLe, counter_ty), shape(counter_ty), check_next_i, check_stop)
                local body_args, done_args = { vector_counter_param }, { vector_counter_param }
                for _, acc in ipairs(vector_acc_params) do body_args[#body_args + 1] = acc; done_args[#done_args + 1] = acc end
                back_emission.cmds[#back_emission.cmds + 1] = Back.CmdBrIf(check_ok, vector_block, body_args, vector_done, done_args)
            end)
        end

        back_emission.vector_value_by_kernel, back_emission.vector_value_by_code = {}, {}
        back_emission.cmds[#back_emission.cmds + 1] = Back.CmdSwitchToBlock(vector_block)
        local body_overrides = merge_overrides(back_emission.semantic_fragment_overrides, has_reductions and { [counter.text] = { value = vector_body_counter_param, ty = counter_ty } } or nil)
        with_value_overrides(back_emission, body_overrides, function()
            for _, effect in ipairs(kplan.body.effects or {}) do
                if asdl.classof(effect) == Kernel.KernelEffectStore then
                    local access, backend_access = first_write_access(back_emission, effect.dst)
                    local addr = address_for_access(back_emission, effect.dst, access, backend_access, Value.ValueExprValue(kplan.body.domain.counter))
                    local value = lower_vector_kernel_expr(back_emission, effect.value, vec, elem_ty)
                    back_emission.cmds[#back_emission.cmds + 1] = Back.CmdStoreInfo(Back.BackShapeVec(vec), addr, value, memory_info_for(back_emission, access, backend_access, ":kernel_vec_store", (backend_access.deref_bytes or 0) * vec.lanes))
                elseif asdl.classof(effect) ~= Kernel.KernelEffectFold then
                    error("lower_to_back: unsupported vector KernelEffect", 2)
                end
            end
        end)

        local latch_fact = edge_facts[latch_edge.from.block.text .. "\0" .. latch_edge.to.block.text]
        if has_reductions then
            local updated_vector_accs = {}
            with_value_overrides(back_emission, body_overrides, function()
                for i, reduction in ipairs(reductions) do
                    back_emission.vector_value_by_kernel, back_emission.vector_value_by_code = {}, {}
                    local contribution = lower_vector_value_expr(back_emission, reduction.contribution, vec, elem_ty)
                    updated_vector_accs[i] = emit_reduction_vector_combine(back_emission, reduction_entry(reduction, elem_ty), vec, vector_body_acc_params[i], contribution)
                end
            end)
            local step = fresh(back_emission, "semantic.vec.lanes")
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdConst(step, scalar(counter_ty), Back.BackLitInt(tostring(lanes)))
            local body_next_i = fresh(back_emission, "semantic.vec.next_i")
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdIntBinary(body_next_i, Back.BackIntAdd, scalar(counter_ty), Back.BackIntSemantics(Back.BackIntWrap, Back.BackIntMayLose), vector_body_counter_param, step)
            local jump_args = { body_next_i }
            for _, acc in ipairs(updated_vector_accs) do jump_args[#jump_args + 1] = acc end
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdJump(vector_check, jump_args)

            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdSwitchToBlock(vector_done)
            local folded = {}
            for i, reduction in ipairs(reductions) do
                folded[i] = emit_reduction_horizontal_fold(back_emission, reduction_entry(reduction, elem_ty), reduction.ty, bid(reduction.accumulator), vector_done_acc_params[i], lanes)
            end
            local tail_args = { vector_done_counter_param }
            for _, acc in ipairs(folded) do tail_args[#tail_args + 1] = acc end
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdJump(tail_check, tail_args)
        else
            local jump_args = {}
            for _, arg in ipairs(latch_fact and latch_fact.args or {}) do
                if arg.dst_param == counter then jump_args[#jump_args + 1] = next_i else jump_args[#jump_args + 1] = bid(arg.dst_param) end
            end
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdJump(block_id(header), jump_args)
        end

        back_emission.cmds[#back_emission.cmds + 1] = Back.CmdSwitchToBlock(tail_check)
        local tail_overrides = merge_overrides(back_emission.semantic_fragment_overrides, {})
        if has_reductions then
            tail_overrides[counter.text] = { value = tail_counter_param, ty = counter_ty }
            for key, value in pairs(reduction_overrides(reductions, tail_acc_params)) do tail_overrides[key] = value end
            local stop_cur, stop_cur_ty = lower_value_expr(back_emission, Value.ValueExprValue(loop_fact.counted.stop))
            if scalar(stop_cur_ty) ~= scalar(counter_ty) then stop_cur = ensure_value_ty(back_emission, fresh(back_emission, "semantic.tail.stop_cast"), counter_ty, stop_cur, stop_cur_ty) end
            scalar_cond = fresh(back_emission, "semantic.tail.done")
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdCompare(scalar_cond, cmp_op(Core.CmpGe, counter_ty), shape(counter_ty), tail_counter_param, stop_cur)
        end
        local true_block = has_reductions and tail_exit or block_id(exit_edge.to.block)
        local true_args = has_reductions and {} or edge_args(back_emission, edge_facts[exit_edge.from.block.text .. "\0" .. exit_edge.to.block.text], tail_overrides)
        back_emission.cmds[#back_emission.cmds + 1] = Back.CmdBrIf(bid(scalar_cond), true_block, true_args, block_id(body_successor), edge_args(back_emission, edge_facts[exit_edge.from.block.text .. "\0" .. body_successor.text], tail_overrides))
        if has_reductions then
            local exit_block = nil
            for _, block in ipairs(back_emission.current_func.blocks or {}) do if block.id == exit_edge.to.block then exit_block = block end end
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdSwitchToBlock(tail_exit)
            local term = exit_block and exit_block.term and exit_block.term.op or nil
            if asdl.classof(term) == Code.CodeTermJump then
                local jump_fact = edge_facts[exit_block.id.text .. "\0" .. term.dest.text]
                back_emission.cmds[#back_emission.cmds + 1] = Back.CmdJump(block_id(term.dest), edge_args(back_emission, jump_fact, tail_overrides))
            elseif asdl.classof(term) == Code.CodeTermReturn and #(term.values or {}) == 1 then
                local v = with_value_overrides(back_emission, tail_overrides, function() return code_value(back_emission, term.values[1]) end)
                back_emission.cmds[#back_emission.cmds + 1] = Back.CmdReturnValue(v)
            else
                error("lower_to_back: vector reduction tail exit cannot lower exit block " .. tostring(exit_edge.to.block.text), 2)
            end
        end
        for _, block in ipairs(back_emission.current_func.blocks or {}) do
            if body_set[block.id.text] and block.id ~= header then
                back_emission.cmds[#back_emission.cmds + 1] = Back.CmdSwitchToBlock(block_id(block.id))
                for _, binding in ipairs(bindings_by_block[block.id.text] or {}) do bind_kernel_value(back_emission, binding) end
                for _, effect in ipairs(effects_by_block[block.id.text] or {}) do emit_kernel_effect(back_emission, effect) end
                if block.id == latch_edge.from.block then
                    back_emission.cmds[#back_emission.cmds + 1] = Back.CmdJump(block_id(header), edge_args(back_emission, latch_fact))
                else
                    local next_edge = nil
                    for _, fg in ipairs(graph.funcs or {}) do
                        if fg.func == loop.func then
                            for _, edge in ipairs(fg.edges or {}) do if edge.from.block == block.id and body_set[edge.to.block.text] then next_edge = edge end end
                        end
                    end
                    if next_edge == nil then error("lower_to_back: vector scalar-tail body block has no in-loop successor", 2) end
                    back_emission.cmds[#back_emission.cmds + 1] = Back.CmdJump(block_id(next_edge.to.block), edge_args(back_emission, edge_facts[next_edge.from.block.text .. "\0" .. next_edge.to.block.text]))
                end
            end
        end
    end

    local function emit_closed_form_fragment(back_emission, code_module, graph, flow, kernels, fragment)
        local strategy = fragment.strategy
        local kplan = kernel_by_id(kernels)[strategy.kernel.text]
        if kplan == nil then error("lower_to_back: closed-form strategy references missing kernel " .. strategy.kernel.text, 2) end
        if asdl.classof(kplan.subject) ~= Kernel.KernelSubjectLoop then error("lower_to_back: closed-form strategy only supports loop subjects", 2) end
        local loop = graph_loop_by_id(graph)[kplan.subject.loop.text]
        if loop == nil then error("lower_to_back: missing graph loop for closed-form fragment", 2) end
        if #(loop.exits or {}) ~= 1 then error("lower_to_back: closed-form emitter supports exactly one loop exit", 2) end
        local exit = loop.exits[1]
        local edge_facts = edge_fact_by_key(flow)
        local edge_fact = edge_facts[exit.from.block.text .. "\0" .. exit.to.block.text]
        if edge_fact == nil then error("lower_to_back: missing FlowEdgeFact for closed-form loop exit", 2) end
        local jump_dest, jump_args_fact = exit.to.block, edge_fact
        local jump_block = nil
        for _, func in ipairs(code_module.funcs or {}) do
            if func.id == loop.func then
                for _, block in ipairs(func.blocks or {}) do
                    if block.id == exit.to.block and asdl.classof(block.term.op) == Code.CodeTermJump then
                        local next_key = block.id.text .. "\0" .. block.term.op.dest.text
                        jump_dest = block.term.op.dest
                        jump_args_fact = edge_facts[next_key] or edge_fact
                    end
                    if block.id == jump_dest then jump_block = block end
                end
            end
        end
        back_emission.cmds[#back_emission.cmds + 1] = Back.CmdSwitchToBlock(block_id(loop.header.block))
        local result, _ = lower_value_expr(back_emission, strategy.fact.expr)
        if jump_block ~= nil and asdl.classof(jump_block.term.op) == Code.CodeTermReturn
            and #(jump_block.term.op.values or {}) == 1
            and jump_block.term.op.values[1] == strategy.fact.reduction.accumulator then
            back_emission.cmds[#back_emission.cmds + 1] = Back.CmdReturnValue(result)
            return
        end
        local args = {}
        for i, arg in ipairs(jump_args_fact.args or {}) do
            if arg.src == strategy.fact.reduction.accumulator then args[i] = result else args[i] = bid(arg.src) end
        end
        back_emission.cmds[#back_emission.cmds + 1] = Back.CmdJump(block_id(jump_dest), args)
    end

    local function semantic_fragment_overrides(back_emission, graph, fragment)
        local blocks = cover_blocks(fragment, back_emission.current_func, graph_loop_by_id(graph))
        local covered = {}
        for _, block in ipairs(blocks or {}) do covered[block.id.text] = true end
        local components_by_value = {}
        local overrides = {}

        local function descriptor_ty(id)
            local ty = value_ty(back_emission, id)
            if asdl.classof(ty) == Code.CodeTyLease then ty = ty.base end
            local cls = asdl.classof(ty)
            return (cls == Code.CodeTyView or cls == Code.CodeTySlice or ty == Code.CodeTyByteSpan or cls == Code.CodeTyByteSpan) and ty or nil
        end

        local function component_ty(ty, field)
            if field == "data" then return Code.CodeTyDataPtr((ty == Code.CodeTyByteSpan or asdl.classof(ty) == Code.CodeTyByteSpan) and Code.CodeTyInt(8, Code.CodeUnsigned) or ty.elem) end
            return Code.CodeTyIndex
        end

        local function value_ref(id, ty)
            local ov = overrides[id.text]
            if ov ~= nil then return ov end
            return { value = bid(id), ty = ty or value_ty(back_emission, id) }
        end

        local function default_components(id)
            local ty = descriptor_ty(id)
            if ty == nil then return nil end
            local vals = component_values(id, ty)
            local comps = {
                data = { value = vals[1], ty = Code.CodeTyDataPtr((ty == Code.CodeTyByteSpan or asdl.classof(ty) == Code.CodeTyByteSpan) and Code.CodeTyInt(8, Code.CodeUnsigned) or ty.elem) },
                len = { value = vals[2], ty = Code.CodeTyIndex },
            }
            if asdl.classof(ty) == Code.CodeTyView then comps.stride = { value = vals[3], ty = Code.CodeTyIndex } end
            return comps
        end

        local function components(id)
            return components_by_value[id.text] or default_components(id)
        end

        local function set_projection(dst, view, field)
            local comps = components(view)
            if comps == nil or comps[field] == nil then return end
            overrides[dst.text] = comps[field]
        end

        for _, block in ipairs(back_emission.current_func.blocks or {}) do
            for _, inst in ipairs(block.insts or {}) do
                local k = inst.op
                local cls = asdl.classof(k)
                if cls == Code.CodeInstViewMake then
                    components_by_value[k.dst.text] = {
                        data = value_ref(k.data, Code.CodeTyDataPtr(k.elem_ty)),
                        len = value_ref(k.len, Code.CodeTyIndex),
                        stride = value_ref(k.stride, Code.CodeTyIndex),
                    }
                elseif cls == Code.CodeInstSliceMake then
                    components_by_value[k.dst.text] = {
                        data = value_ref(k.data, Code.CodeTyDataPtr(k.elem_ty)),
                        len = value_ref(k.len, Code.CodeTyIndex),
                    }
                elseif cls == Code.CodeInstByteSpanMake then
                    components_by_value[k.dst.text] = {
                        data = value_ref(k.data, Code.CodeTyDataPtr(Code.CodeTyInt(8, Code.CodeUnsigned))),
                        len = value_ref(k.len, Code.CodeTyIndex),
                    }
                elseif cls == Code.CodeInstAlias and descriptor_ty(k.dst) ~= nil then
                    local comps = components(k.src)
                    if comps ~= nil then components_by_value[k.dst.text] = comps end
                elseif cls == Code.CodeInstLoad and (asdl.classof(k.access.ty) == Code.CodeTyView or asdl.classof(k.access.ty) == Code.CodeTySlice or k.access.ty == Code.CodeTyByteSpan or asdl.classof(k.access.ty) == Code.CodeTyByteSpan) then
                    -- A descriptor load defines fresh components through real memory loads in
                    -- generic Code emission.  Semantic fragments cannot assume those loads
                    -- exist once the block is replaced.
                    components_by_value[k.dst.text] = nil
                elseif covered[block.id.text] then
                    if cls == Code.CodeInstViewData then set_projection(k.dst, k.view, "data")
                    elseif cls == Code.CodeInstViewLen then set_projection(k.dst, k.view, "len")
                    elseif cls == Code.CodeInstViewStride then set_projection(k.dst, k.view, "stride")
                    elseif cls == Code.CodeInstSliceData then set_projection(k.dst, k.slice, "data")
                    elseif cls == Code.CodeInstSliceLen then set_projection(k.dst, k.slice, "len")
                    elseif cls == Code.CodeInstByteSpanData then set_projection(k.dst, k.span, "data")
                    elseif cls == Code.CodeInstByteSpanLen then set_projection(k.dst, k.span, "len") end
                end
            end
        end

        return overrides
    end

    local function lower_emit_candidate(back_emission, fragment)
        return fragment.strategy:lower_emit_candidate(fragment.strategy:lower_emit_schedule(back_emission.schedule_by_id))
    end

    function Lower.LowerStrategy:lower_emit_schedule(schedule_by_id) return nil end
    function Lower.LowerStrategyKernel:lower_emit_schedule(schedule_by_id)
        return schedule_by_id and schedule_by_id[self.schedule.text] or nil
    end
    function Lower.LowerStrategy:lower_emit_missing_schedule_reason() return "" end
    function Lower.LowerStrategyKernel:lower_emit_missing_schedule_reason()
        return "kernel strategy references missing schedule " .. self.schedule.text
    end

    function Lower.LowerEmitSelection:emit_to_back(back_emission, fragment_emit)
        error("lower_to_back: unsupported lower emission selection", 2)
    end

    function Lower.LowerEmitCode:emit_to_back(back_emission, fragment_emit)
        local cmds = CodeToBack.fragment_commands(
            fragment_emit.code_module,
            fragment_emit.graph,
            fragment_emit.flow,
            fragment_emit.value_facts,
            fragment_emit.mem,
            fragment_emit.effect,
            fragment_emit.fragment.cover,
            { validate = false, emit_local_slots = false, layout_env = back_emission.layout_env, target = back_emission.target }
        )
        for _, cmd in ipairs(cmds or {}) do back_emission.cmds[#back_emission.cmds + 1] = cmd end
    end

    function Lower.LowerEmitScalarKernel:emit_to_back(back_emission, fragment_emit)
        local fragment = fragment_emit.fragment
        local old_overrides = back_emission.semantic_fragment_overrides
        back_emission.semantic_fragment_overrides = semantic_fragment_overrides(back_emission, fragment_emit.graph, fragment)
        with_value_overrides(back_emission, back_emission.semantic_fragment_overrides, function()
            emit_scalar_kernel_fragment(back_emission, fragment_emit.code_module, fragment_emit.graph, fragment_emit.flow, fragment_emit.schedules, fragment_emit.kernels, fragment)
        end)
        back_emission.semantic_fragment_overrides = old_overrides
    end

    function Lower.LowerEmitVectorKernel:emit_to_back(back_emission, fragment_emit)
        local fragment = fragment_emit.fragment
        local old_overrides = back_emission.semantic_fragment_overrides
        back_emission.semantic_fragment_overrides = semantic_fragment_overrides(back_emission, fragment_emit.graph, fragment)
        with_value_overrides(back_emission, back_emission.semantic_fragment_overrides, function()
            emit_vector_kernel_fragment(back_emission, fragment_emit.code_module, fragment_emit.graph, fragment_emit.flow, fragment_emit.schedules, fragment_emit.kernels, fragment)
        end)
        back_emission.semantic_fragment_overrides = old_overrides
    end

    function Lower.LowerEmitClosedForm:emit_to_back(back_emission, fragment_emit)
        local fragment = fragment_emit.fragment
        with_value_overrides(back_emission, semantic_fragment_overrides(back_emission, fragment_emit.graph, fragment), function()
            emit_closed_form_fragment(back_emission, fragment_emit.code_module, fragment_emit.graph, fragment_emit.flow, fragment_emit.kernels, fragment)
        end)
    end

    function Lower.LowerEmitMissingSchedule:emit_to_back(back_emission, fragment_emit)
        error("lower_to_back: " .. tostring(self.reason), 2)
    end

    function Lower.LowerEmitUnsupported:emit_to_back(back_emission, fragment_emit)
        error("lower_to_back: " .. tostring(self.reason), 2)
    end

    local function emit_fragment(back_emission, fragment_emit)
        local selection = lower_emit_candidate(back_emission, fragment_emit.fragment):select_lower_emit()
        selection:emit_to_back(back_emission, fragment_emit)
    end

    local function emit_func(back_emission, code_module, graph, flow, value, mem, effect, func, func_plan, graph_loops)
        back_emission.value_types = {}
        back_emission.current_func = func
        back_emission.kernel_value_back = {}
        back_emission.kernel_value_types = {}
        back_emission.kernel_value_block = {}
        back_emission.kernel_value_code_id = {}
        back_emission.kernel_binding_by_id = {}
        back_emission.value_block = {}
        local function note_inst_dst(block, k)
            local cls = asdl.classof(k)
            local dst, ty = nil, nil
            if cls == Code.CodeInstConst then dst, ty = k.dst, k.const.ty
            elseif cls == Code.CodeInstAlias or cls == Code.CodeInstUnary or cls == Code.CodeInstBinary or cls == Code.CodeInstFloatBinary or cls == Code.CodeInstSelect then dst, ty = k.dst, k.ty
            elseif cls == Code.CodeInstCompare then dst, ty = k.dst, Code.CodeTyBool8
            elseif cls == Code.CodeInstCast then dst, ty = k.dst, k.ty
            elseif cls == Code.CodeInstIntrinsic then dst, ty = rawget(k, "dst"), k.ty
            elseif cls == Code.CodeInstAddrOf or cls == Code.CodeInstGlobalRef or cls == Code.CodeInstPtrOffset then dst, ty = k.dst, k.ptr_ty
            elseif cls == Code.CodeInstLoad or cls == Code.CodeInstAtomicLoad or cls == Code.CodeInstAtomicRmw or cls == Code.CodeInstAtomicCas then dst, ty = k.dst, k.access.ty
            elseif cls == Code.CodeInstViewMake then dst, ty = k.dst, Code.CodeTyView(k.elem_ty)
            elseif cls == Code.CodeInstViewData then
                local vty = value_ty(back_emission, k.view)
                if asdl.classof(vty) == Code.CodeTyLease then vty = vty.base end
                dst, ty = k.dst, Code.CodeTyDataPtr(asdl.classof(vty) == Code.CodeTyView and vty.elem or nil)
            elseif cls == Code.CodeInstViewLen or cls == Code.CodeInstViewStride then dst, ty = k.dst, Code.CodeTyIndex
            elseif cls == Code.CodeInstSliceMake then dst, ty = k.dst, Code.CodeTySlice(k.elem_ty)
            elseif cls == Code.CodeInstSliceData then
                local sty = value_ty(back_emission, k.slice)
                if asdl.classof(sty) == Code.CodeTyLease then sty = sty.base end
                dst, ty = k.dst, Code.CodeTyDataPtr(asdl.classof(sty) == Code.CodeTySlice and sty.elem or nil)
            elseif cls == Code.CodeInstSliceLen then dst, ty = k.dst, Code.CodeTyIndex
            elseif cls == Code.CodeInstByteSpanMake then dst, ty = k.dst, Code.CodeTyByteSpan
            elseif cls == Code.CodeInstByteSpanData then dst, ty = k.dst, Code.CodeTyDataPtr(Code.CodeTyInt(8, Code.CodeUnsigned))
            elseif cls == Code.CodeInstByteSpanLen then dst, ty = k.dst, Code.CodeTyIndex end
            if dst ~= nil and ty ~= nil then
                note_value(back_emission, dst, ty)
                back_emission.value_block[dst.text] = block.id
                local kid = Kernel.KernelValueId("kval:" .. dst.text)
                back_emission.kernel_value_back[kid.text] = bid(dst)
                back_emission.kernel_value_types[kid.text] = ty
                back_emission.kernel_value_block[kid.text] = block.id
                back_emission.kernel_value_code_id[kid.text] = dst
            end
        end
        for _, param in ipairs(func.params or {}) do note_value(back_emission, param.value, param.ty) end
        for _, b in ipairs(func.blocks or {}) do
            for _, param in ipairs(b.params or {}) do
                note_value(back_emission, param.value, param.ty)
                back_emission.value_block[param.value.text] = b.id
            end
            for _, inst in ipairs(b.insts or {}) do note_inst_dst(b, inst.op) end
        end
        back_emission.cmds[#back_emission.cmds + 1] = Back.CmdBeginFunc(func_id(func.id))
        for _, cmd in ipairs(CodeToBack.function_local_stack_slot_commands(code_module, func, { graph = graph, flow = flow, value = value, mem = mem, effect = effect, validate = false, layout_env = back_emission.layout_env, target = back_emission.target })) do back_emission.cmds[#back_emission.cmds + 1] = cmd end
        for _, b in ipairs(func.blocks or {}) do back_emission.cmds[#back_emission.cmds + 1] = Back.CmdCreateBlock(block_id(b.id)) end
        for _, b in ipairs(func.blocks or {}) do
            for _, param in ipairs(b.params or {}) do
                local vals, shapes = component_values(param.value, param.ty), component_shapes(param.ty)
                for i = 1, #vals do back_emission.cmds[#back_emission.cmds + 1] = Back.CmdAppendBlockParam(block_id(b.id), vals[i], shapes[i]) end
            end
        end
        for _, fragment in ipairs(ordered_fragments_for_func(func, func_plan, graph_loops)) do
            emit_fragment(back_emission, Lower.LowerBackEmitInput(code_module, graph, flow, value, mem, effect, back_emission.kernels, back_emission.schedules, fragment))
        end
        back_emission.cmds[#back_emission.cmds + 1] = Back.CmdFinishFunc(func_id(func.id))
    end

    local function normalize_args(code_module, a, b, c, d, e, f, g, h)
        if a ~= nil and asdl.classof(a) == Lower.LowerModule then
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

    local function module(code_module, graph, flow, value, mem, effect, kernels, schedules, lower, opts)
        if graph ~= nil and asdl.classof(graph) == Lower.LowerModule then
            opts = flow or opts
        end
        opts = opts or {}
        graph, flow, value, mem, effect, kernels, schedules, lower = normalize_args(code_module, graph, flow, value, mem, effect, kernels, schedules, lower)
        graph = graph or CodeGraph.graph(code_module)
        flow = flow or CodeFlowFacts.facts(code_module, graph)
        value = value or CodeValueFacts.facts(code_module, graph, flow)
        mem = mem or CodeMemFacts.semantic_facts(code_module, graph, flow, value, nil)
        effect = effect or CodeEffectFacts.facts(code_module, graph, mem, nil)
        kernels = kernels or CodeKernelPlan.plan(code_module, graph, flow, value, mem, effect)
        schedules = schedules or CodeSchedulePlan.plan(code_module, kernels, flow, value, mem, effect, opts.target_model or opts.back_target_model)
        lower = lower or CodeLowerPlan.plan(code_module, graph, kernels, schedules, Lower.LowerTargetBack)

        local back_emission = { cmds = {}, kernels = kernels, schedules = schedules, value_types = {}, next_tmp = 0, mem_projection = CodeMemFacts.access_projection(mem), schedule_by_id = {}, layout_env = opts.layout_env, target = opts.target }
        for _, sched in ipairs(schedules and schedules.schedules or {}) do if asdl.classof(sched) == Schedule.SchedulePlanned then back_emission.schedule_by_id[sched.id.text] = sched end end
        for _, cmd in ipairs(CodeToBack.module_prelude_commands(code_module, { graph = graph, flow = flow, value = value, mem = mem, effect = effect, validate = false, layout_env = opts.layout_env, target = opts.target })) do back_emission.cmds[#back_emission.cmds + 1] = cmd end
        for _, func in ipairs(code_module.funcs or {}) do back_emission.cmds[#back_emission.cmds + 1] = CodeToBack.function_declare(func) end

        local funcs = func_by_id(code_module)
        local graph_loops = graph_indexes(graph)
        for _, func_plan in ipairs(lower.funcs or {}) do
            local func = funcs[func_plan.func.text]
            if func == nil then error("lower_to_back: LowerFuncPlan references missing function " .. func_plan.func.text, 2) end
            emit_func(back_emission, code_module, graph, flow, value, mem, effect, func, func_plan, graph_loops)
        end
        back_emission.cmds[#back_emission.cmds + 1] = Back.CmdFinalizeModule
        return Back.BackProgram(back_emission.cmds)
    end

    api.module = module

    T._lalin_api_cache.lower_to_back = api
    return api
end

return bind_context
