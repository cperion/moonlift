local asdl = require("lalin.asdl")

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s:match("^%d") then s = "_" .. s end
    if s == "" then s = "x" end
    return s
end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.lower_to_c ~= nil then return T._lalin_api_cache.lower_to_c end

    local Core = T.LalinCore
    local Code = T.LalinCode
    local C = T.LalinC
    local Lower = T.LalinLower
    local Kernel = T.LalinKernel
    local Schedule = T.LalinSchedule
    local Value = T.LalinValue
    local Mem = T.LalinMem

    local CodeToC = require("lalin.code_to_c")(T)
    local CodeType = require("lalin.code_type")(T)
    local CodeGraph = require("lalin.code_graph")(T)
    local CodeFlowFacts = require("lalin.code_flow_facts")(T)
    local CodeValueFacts = require("lalin.code_value_facts")(T)
    local CodeMemFacts = require("lalin.code_mem_facts")(T)
    local CodeEffectFacts = require("lalin.code_effect_facts")(T)
    local CodeKernelPlan = require("lalin.code_kernel_plan")(T)
    local CodeSchedulePlan = require("lalin.code_schedule_plan")(T)
    local CodeLowerPlan = require("lalin.code_lower_plan")(T)
    local ExecPlan = require("lalin.exec_plan")(T)

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
        return Lower.LowerEmitUnsupportedCandidate("unsupported LowerStrategy for C emission " .. tostring(asdl.class_basename(self) or self))
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

    local function cname(text) return C.CBackendName(sanitize(text)) end
    local function clabel(id) return C.CBackendLabel(sanitize(id.text)) end
    local function cid(id) return C.CBackendLocalId(sanitize(id.text)) end
    local function atom(id) return C.CBackendAtomLocal(cid(id)) end

    local function class_name(x)
        local cls = asdl.classof(x) or x
        return tostring(cls):match("Class%((.-)%)") or tostring(cls)
    end

    local function make_c_type_projection(code_module)
        local c_type_projection = { code_sigs = {}, code_sig_order = {} }
        for _, sig in ipairs(code_module.sigs or {}) do c_type_projection.code_sigs[sig.id.text] = sig end
        return c_type_projection
    end

    local function c_ty(c_emission, ty)
        return CodeType.code_type_to_c(ty, c_emission.c_type_projection)
    end

    local function helper_key(spec) return tostring(spec) end

    local function add_helper(c_emission, spec)
        local key = helper_key(spec)
        local existing = c_emission.helper_by_key[key]
        if existing ~= nil then return existing.id end
        c_emission.next_helper = c_emission.next_helper + 1
        local use = C.CBackendHelperUse(C.CBackendHelperId("ml_semantic_helper_" .. tostring(c_emission.next_helper)), spec)
        c_emission.helper_by_key[key] = use
        c_emission.unit.helpers[#c_emission.unit.helpers + 1] = use
        return use.id
    end

    local function add_local(c_emission, id, ty)
        local text = id.text or id
        local lid = type(id) == "table" and id or C.CBackendLocalId(text)
        if c_emission.local_seen[lid.text] then return lid end
        c_emission.local_seen[lid.text] = true
        c_emission.func.locals[#c_emission.func.locals + 1] = C.CBackendLocal(lid, C.CBackendName(lid.text), c_ty(c_emission, ty))
        return lid
    end

    local function note_value(c_emission, id, ty)
        if id ~= nil and ty ~= nil then c_emission.value_types[id.text] = ty end
    end

    local function value_ty(c_emission, id) return id and c_emission.value_types[id.text] or nil end
    local function view_type(c_emission, id)
        local ty = value_ty(c_emission, id)
        if asdl.classof(ty) == Code.CodeTyLease then ty = ty.base end
        return ty
    end
    local function view_elem_type(c_emission, id)
        local ty = view_type(c_emission, id)
        if asdl.classof(ty) == Code.CodeTyView then return ty.elem end
        return nil
    end
    local function view_data_type(c_emission, id)
        return Code.CodeTyDataPtr(view_elem_type(c_emission, id))
    end
    local function slice_elem_type(c_emission, id)
        local ty = view_type(c_emission, id)
        if asdl.classof(ty) == Code.CodeTySlice then return ty.elem end
        return nil
    end
    local function slice_data_type(c_emission, id)
        return Code.CodeTyDataPtr(slice_elem_type(c_emission, id))
    end
    local function byte_ty()
        return Code.CodeTyInt(8, Code.CodeUnsigned)
    end

    local function tmp(c_emission, prefix, ty)
        c_emission.next_tmp = c_emission.next_tmp + 1
        local id = C.CBackendLocalId(sanitize("semantic." .. prefix .. "." .. tostring(c_emission.next_tmp)))
        add_local(c_emission, id, ty)
        return id
    end

    local function const_atom(c_emission, const)
        local cls = asdl.classof(const)
        if cls == Code.CodeConstLiteral then return C.CBackendAtomLiteral(c_ty(c_emission, const.ty), const.literal), const.ty end
        if cls == Code.CodeConstNull then return C.CBackendAtomNull(c_ty(c_emission, const.ty)), const.ty end
        if cls == Code.CodeConstUndef then return C.CBackendAtomLiteral(c_ty(c_emission, const.ty), Core.LitInt("0")), const.ty end
        error("lower_to_c: unsupported semantic const " .. class_name(const), 3)
    end

    local function assign(c_emission, dst, rhs)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendAssign(dst, rhs)
    end

    local function cast_to(c_emission, src_atom, src_ty, dst_ty, name)
        if tostring(c_ty(c_emission, src_ty)) == tostring(c_ty(c_emission, dst_ty)) then return src_atom, dst_ty end
        local dst = tmp(c_emission, name or "cast", dst_ty)
        assign(c_emission, dst, C.CBackendRCast(Core.MachineCastIdentity, c_ty(c_emission, dst_ty), src_atom))
        return C.CBackendAtomLocal(dst), dst_ty
    end

    local function overflow_mode(sem)
        if sem and sem.overflow == Code.CodeIntTrapOnOverflow then return C.CBackendIntTrapOnOverflow end
        if sem and asdl.classof(sem.overflow) == Code.CodeIntAssumeNoOverflow then return C.CBackendIntAssumeNoOverflow end
        return C.CBackendIntWrap
    end

    local function binary_helper(c_emission, op, ty, sem)
        if op == Core.BinDiv or op == Core.BinRem then
            local mode = (sem and sem.div == Code.CodeDivTrapOnZeroOrOverflow) and C.CBackendDivTrapOnZeroOrOverflow or C.CBackendDivTrapOnZero
            return add_helper(c_emission, C.CBackendHelperDivRem(op, c_ty(c_emission, ty), mode))
        end
        return add_helper(c_emission, C.CBackendHelperIntBinary(op, c_ty(c_emission, ty), overflow_mode(sem)))
    end

    local simplify_value_expr
    local function literal_int_raw(expr)
        if asdl.classof(expr) ~= Value.ValueExprConst then return nil end
        if asdl.classof(expr.const) ~= Code.CodeConstLiteral then return nil end
        if asdl.classof(expr.const.literal) ~= Core.LitInt then return nil end
        return expr.const.literal.raw, expr.const.ty
    end
    local function literal_bool_value(expr)
        if asdl.classof(expr) ~= Value.ValueExprConst then return nil end
        if asdl.classof(expr.const) ~= Code.CodeConstLiteral then return nil end
        local lcls = asdl.classof(expr.const.literal)
        if lcls == Core.LitBool then return expr.const.literal.value end
        if lcls == Core.LitInt then return expr.const.literal.raw ~= "0" end
        return nil
    end
    local function int_const(ty, raw)
        return Value.ValueExprConst(Code.CodeConstLiteral(ty, Core.LitInt(tostring(raw))))
    end
    local function is_raw(raw, want) return raw ~= nil and tostring(raw) == tostring(want) end
    simplify_value_expr = function(expr)
        local cls = asdl.classof(expr)
        if cls == Value.ValueExprAdd or cls == Value.ValueExprSub or cls == Value.ValueExprMul or cls == Value.ValueExprDiv or cls == Value.ValueExprRem then
            local a = simplify_value_expr(expr.a)
            local b = simplify_value_expr(expr.b)
            local ar = literal_int_raw(a)
            local br = literal_int_raw(b)
            if cls == Value.ValueExprAdd then
                if is_raw(ar, "0") then return b end
                if is_raw(br, "0") then return a end
            elseif cls == Value.ValueExprSub then
                if is_raw(br, "0") then return a end
            elseif cls == Value.ValueExprMul then
                if is_raw(ar, "0") or is_raw(br, "0") then return int_const(expr.ty, "0") end
                if is_raw(ar, "1") then return b end
                if is_raw(br, "1") then return a end
            elseif cls == Value.ValueExprDiv or cls == Value.ValueExprRem then
                if is_raw(br, "1") then return a end
            end
            if ar ~= nil and br ~= nil then
                local av, bv = tonumber(ar), tonumber(br)
                if av ~= nil and bv ~= nil and av == math.floor(av) and bv == math.floor(bv) then
                    if cls == Value.ValueExprAdd then return int_const(expr.ty, av + bv) end
                    if cls == Value.ValueExprSub then return int_const(expr.ty, av - bv) end
                    if cls == Value.ValueExprMul then return int_const(expr.ty, av * bv) end
                    if cls == Value.ValueExprDiv and bv ~= 0 then return int_const(expr.ty, math.floor(av / bv)) end
                    if cls == Value.ValueExprRem and bv ~= 0 then return int_const(expr.ty, av % bv) end
                end
            end
            if cls == Value.ValueExprAdd then return Value.ValueExprAdd(a, b, expr.ty, expr.sem) end
            if cls == Value.ValueExprSub then return Value.ValueExprSub(a, b, expr.ty, expr.sem) end
            if cls == Value.ValueExprMul then return Value.ValueExprMul(a, b, expr.ty, expr.sem) end
            if cls == Value.ValueExprDiv then return Value.ValueExprDiv(a, b, expr.ty, expr.sem) end
            return Value.ValueExprRem(a, b, expr.ty, expr.sem)
        elseif cls == Value.ValueExprBinary then
            return Value.ValueExprBinary(expr.op, simplify_value_expr(expr.a), simplify_value_expr(expr.b), expr.ty, expr.sem)
        elseif cls == Value.ValueExprCmp then
            local a = simplify_value_expr(expr.a)
            local b = simplify_value_expr(expr.b)
            local ar = literal_int_raw(a)
            local br = literal_int_raw(b)
            if ar ~= nil and br ~= nil then
                local av, bv = tonumber(ar), tonumber(br)
                if av ~= nil and bv ~= nil then
                    local r = (expr.op == Core.CmpEq and av == bv) or (expr.op == Core.CmpNe and av ~= bv)
                        or (expr.op == Core.CmpLt and av < bv) or (expr.op == Core.CmpLe and av <= bv)
                        or (expr.op == Core.CmpGt and av > bv) or (expr.op == Core.CmpGe and av >= bv) or false
                    return Value.ValueExprConst(Code.CodeConstLiteral(Code.CodeTyBool8, Core.LitBool(r)))
                end
            end
            return Value.ValueExprCmp(expr.op, expr.ty, a, b)
        elseif cls == Value.ValueExprSelect then
            local cnd = simplify_value_expr(expr.cond)
            local bv = literal_bool_value(cnd)
            if bv == true then return simplify_value_expr(expr.t) end
            if bv == false then return simplify_value_expr(expr.f) end
            return Value.ValueExprSelect(cnd, simplify_value_expr(expr.t), simplify_value_expr(expr.f))
        elseif cls == Value.ValueExprAffine then
            if expr.affine.constant == "0" and #(expr.affine.terms or {}) == 1 and expr.affine.terms[1].coeff == "1" then
                return Value.ValueExprValue(expr.affine.terms[1].value)
            end
        end
        return expr
    end

    local lower_value_expr
    lower_value_expr = function(c_emission, expr)
        expr = simplify_value_expr(expr)
        local cls = asdl.classof(expr)
        if cls == Value.ValueExprConst then
            return const_atom(c_emission, expr.const)
        elseif cls == Value.ValueExprValue then
            local ty = value_ty(c_emission, expr.value)
            if ty == nil then error("lower_to_c: semantic expression references unknown value " .. expr.value.text, 3) end
            return atom(expr.value), ty
        elseif cls == Value.ValueExprAdd or cls == Value.ValueExprSub or cls == Value.ValueExprMul or cls == Value.ValueExprDiv or cls == Value.ValueExprRem then
            local a, aty = lower_value_expr(c_emission, expr.a)
            local b, bty = lower_value_expr(c_emission, expr.b)
            a = cast_to(c_emission, a, aty, expr.ty, "bin_lhs")
            b = cast_to(c_emission, b, bty, expr.ty, "bin_rhs")
            local dst = tmp(c_emission, "bin", expr.ty)
            local op = (cls == Value.ValueExprAdd and Core.BinAdd) or (cls == Value.ValueExprSub and Core.BinSub) or (cls == Value.ValueExprMul and Core.BinMul) or (cls == Value.ValueExprRem and Core.BinRem) or Core.BinDiv
            c_emission.stmts[#c_emission.stmts + 1] = C.CBackendHelperCall(dst, binary_helper(c_emission, op, expr.ty, expr.sem), { a, b })
            return C.CBackendAtomLocal(dst), expr.ty
        elseif cls == Value.ValueExprBinary then
            local a, aty = lower_value_expr(c_emission, expr.a)
            local b, bty = lower_value_expr(c_emission, expr.b)
            a = cast_to(c_emission, a, aty, expr.ty, "bin_lhs")
            b = cast_to(c_emission, b, bty, expr.ty, "bin_rhs")
            local dst = tmp(c_emission, "bin", expr.ty)
            c_emission.stmts[#c_emission.stmts + 1] = C.CBackendHelperCall(dst, binary_helper(c_emission, expr.op, expr.ty, expr.sem), { a, b })
            return C.CBackendAtomLocal(dst), expr.ty
        elseif cls == Value.ValueExprCmp then
            local a, aty = lower_value_expr(c_emission, expr.a)
            local b, bty = lower_value_expr(c_emission, expr.b)
            a = cast_to(c_emission, a, aty, expr.ty, "cmp_lhs")
            b = cast_to(c_emission, b, bty, expr.ty, "cmp_rhs")
            local dst = tmp(c_emission, "cmp", Code.CodeTyBool8)
            assign(c_emission, dst, C.CBackendRCompare(expr.op, c_ty(c_emission, expr.ty), a, b))
            return C.CBackendAtomLocal(dst), Code.CodeTyBool8
        elseif cls == Value.ValueExprSelect then
            local cnd = lower_value_expr(c_emission, expr.cond)
            local t, tty = lower_value_expr(c_emission, expr.t)
            local f, fty = lower_value_expr(c_emission, expr.f)
            local ty = tty or fty
            f = cast_to(c_emission, f, fty, ty, "sel_f")
            t = cast_to(c_emission, t, tty, ty, "sel_t")
            local dst = tmp(c_emission, "select", ty)
            assign(c_emission, dst, C.CBackendRSelect(c_ty(c_emission, ty), cnd, t, f))
            return C.CBackendAtomLocal(dst), ty
        elseif cls == Value.ValueExprAffine then
            local ty = expr.affine.ty
            local acc, acc_ty = nil, nil
            if expr.affine.constant ~= "0" then acc, acc_ty = lower_value_expr(c_emission, Value.ValueExprConst(Code.CodeConstLiteral(ty, Core.LitInt(expr.affine.constant)))) end
            for _, term in ipairs(expr.affine.terms or {}) do
                local tv, tty = lower_value_expr(c_emission, Value.ValueExprValue(term.value))
                tv = cast_to(c_emission, tv, tty, ty, "affine_cast")
                if term.coeff ~= "1" then
                    local cv = C.CBackendAtomLiteral(c_ty(c_emission, ty), Core.LitInt(term.coeff))
                    local mul = tmp(c_emission, "affine_mul", ty)
                    c_emission.stmts[#c_emission.stmts + 1] = C.CBackendHelperCall(mul, binary_helper(c_emission, Core.BinMul, ty, expr.affine.sem), { tv, cv })
                    tv = C.CBackendAtomLocal(mul)
                end
                if acc == nil then acc, acc_ty = tv, ty else
                    local sum = tmp(c_emission, "affine_add", ty)
                    c_emission.stmts[#c_emission.stmts + 1] = C.CBackendHelperCall(sum, binary_helper(c_emission, Core.BinAdd, ty, expr.affine.sem), { acc, tv })
                    acc, acc_ty = C.CBackendAtomLocal(sum), ty
                end
            end
            if acc == nil then return C.CBackendAtomLiteral(c_ty(c_emission, ty), Core.LitInt("0")), ty end
            return acc, acc_ty
        end
        error("lower_to_c: unsupported semantic ValueExpr " .. class_name(expr), 3)
    end

    function Mem.MemAccessOp:lower_c_read_access(access) return nil end
    function Mem.MemLoad:lower_c_read_access(access) return access end
    function Mem.MemAtomicLoad:lower_c_read_access(access) return access end
    function Mem.MemAtomicRmw:lower_c_read_access(access) return access end
    function Mem.MemAtomicCas:lower_c_read_access(access) return access end

    function Mem.MemAccessOp:lower_c_write_access(access) return nil end
    function Mem.MemStore:lower_c_write_access(access) return access end
    function Mem.MemAtomicStore:lower_c_write_access(access) return access end
    function Mem.MemAtomicRmw:lower_c_write_access(access) return access end
    function Mem.MemAtomicCas:lower_c_write_access(access) return access end

    local function first_lane_access(c_emission, lane, selector)
        for _, aid in ipairs(lane.accesses or {}) do
            local access = c_emission.mem_projection:mem_access(aid)
            if access ~= nil then
                local selected_access = access.op[selector](access.op, access)
                if selected_access ~= nil then return selected_access, c_emission.mem_projection:backend_for_access(aid) end
            end
        end
        local aid = lane.accesses and lane.accesses[1]
        if aid ~= nil then return c_emission.mem_projection:mem_access(aid), c_emission.mem_projection:backend_for_access(aid) end
        return nil, nil
    end

    local function first_read_access(c_emission, lane)
        return first_lane_access(c_emission, lane, "lower_c_read_access")
    end

    local function first_write_access(c_emission, lane)
        return first_lane_access(c_emission, lane, "lower_c_write_access")
    end

    local function base_atom(c_emission, base)
        local cls = asdl.classof(base)
        if cls == Mem.MemBaseValue or cls == Mem.MemBaseArgument then return atom(base.value) end
        if cls == Mem.MemBaseGlobal then return C.CBackendAtomGlobal(C.CBackendGlobalId(base.global.text)) end
        if cls == Mem.MemBaseData then return C.CBackendAtomGlobal(C.CBackendGlobalId(base.data.text)) end
        if cls == Mem.MemBaseProjection then
            local b = base_atom(c_emission, base.base)
            local zero = C.CBackendAtomLiteral(C.CBackendIndex, Core.LitInt("0"))
            local dst = tmp(c_emission, "base_projection", Code.CodeTyDataPtr(nil))
            assign(c_emission, dst, C.CBackendRPtrOffset(b, zero, 1, base.byte_offset or 0))
            return C.CBackendAtomLocal(dst)
        end
        error("lower_to_c: unsupported KernelLane base " .. class_name(base), 3)
    end

    local function address_index_atom(c_emission, index_expr)
        local idx, ity = lower_value_expr(c_emission, index_expr)
        idx = cast_to(c_emission, idx, ity, Code.CodeTyIndex, "index_cast")
        return idx
    end

    local function place_for_access(c_emission, lane, access, index_expr)
        local elem_size = 1
        local const_offset = 0
        local icls = access and asdl.classof(access.index) or nil
        if icls == Mem.MemIndexValue or icls == Mem.MemIndexInduction then
            elem_size = access.index.elem_size or 1
            const_offset = access.index.const_offset or 0
        end
        local base = base_atom(c_emission, lane.base)
        local idx = address_index_atom(c_emission, index_expr)
        local base_place = C.CBackendPlaceDeref(base, c_ty(c_emission, lane.elem_ty), nil)
        if const_offset ~= 0 then
            local ptr = tmp(c_emission, "ptr_offset", Code.CodeTyDataPtr(lane.elem_ty))
            assign(c_emission, ptr, C.CBackendRPtrOffset(base, idx, elem_size, const_offset))
            return C.CBackendPlaceDeref(C.CBackendAtomLocal(ptr), c_ty(c_emission, lane.elem_ty), nil)
        end
        return C.CBackendPlaceIndex(base_place, idx, c_ty(c_emission, lane.elem_ty), elem_size)
    end

    local function place_for_read_lane(c_emission, lane, index_expr)
        return place_for_access(c_emission, lane, first_read_access(c_emission, lane), index_expr)
    end

    local function place_for_write_lane(c_emission, lane, index_expr)
        return place_for_access(c_emission, lane, first_write_access(c_emission, lane), index_expr)
    end

    local function kernel_value_atom(c_emission, kid)
        local mapped = c_emission.kernel_value_local[kid.text]
        if mapped ~= nil then return C.CBackendAtomLocal(mapped), c_emission.kernel_value_types[kid.text] end
        return C.CBackendAtomLocal(C.CBackendLocalId(sanitize(kid.text))), c_emission.kernel_value_types[kid.text]
    end

    local lower_kernel_expr
    lower_kernel_expr = function(c_emission, expr)
        local cls = asdl.classof(expr)
        if cls == Kernel.KernelExprValue then return atom(expr.value), value_ty(c_emission, expr.value) end
        if cls == Kernel.KernelExprKernelValue then return kernel_value_atom(c_emission, expr.value) end
        if cls == Kernel.KernelExprAlgebra then return lower_value_expr(c_emission, expr.expr) end
        if cls == Kernel.KernelExprLaneLoad then
            local dst = tmp(c_emission, "load", expr.lane.elem_ty)
            local place = place_for_read_lane(c_emission, expr.lane, expr.index)
            c_emission.stmts[#c_emission.stmts + 1] = C.CBackendPlaceLoad(dst, place)
            return C.CBackendAtomLocal(dst), expr.lane.elem_ty
        end
        error("lower_to_c: unsupported KernelExpr " .. class_name(expr), 3)
    end

    local function bind_kernel_value(c_emission, binding)
        local dst = c_emission.kernel_value_local[binding.id.text]
        if dst == nil then
            dst = C.CBackendLocalId(sanitize(binding.id.text))
            c_emission.kernel_value_local[binding.id.text] = dst
            add_local(c_emission, dst, binding.ty)
        end
        local src, sty = lower_kernel_expr(c_emission, binding.expr)
        src = cast_to(c_emission, src, sty, binding.ty, "kernel_bind_cast")
        assign(c_emission, dst, C.CBackendRAtom(src))
        c_emission.kernel_value_types[binding.id.text] = binding.ty
    end

    local function emit_kernel_effect(c_emission, effect)
        local cls = asdl.classof(effect)
        if cls == Kernel.KernelEffectStore then
            local value, vty = lower_kernel_expr(c_emission, effect.value)
            value = cast_to(c_emission, value, vty, effect.dst.elem_ty, "store_cast")
            local place = place_for_write_lane(c_emission, effect.dst, effect.index)
            c_emission.stmts[#c_emission.stmts + 1] = C.CBackendPlaceStore(place, value)
        elseif cls == Kernel.KernelEffectFold then
            return
        else
            error("lower_to_c: unsupported KernelEffect " .. class_name(effect), 3)
        end
    end

    local function term_to_c(c_emission, term)
        local k = term.op
        local cls = asdl.classof(k)
        local function args(xs)
            local out = {}
            for i = 1, #(xs or {}) do out[i] = atom(xs[i]) end
            return out
        end
        if cls == Code.CodeTermJump then return C.CBackendGoto(clabel(k.dest), args(k.args)) end
        if cls == Code.CodeTermBranch then return C.CBackendIfGoto(atom(k.cond), clabel(k.then_dest), args(k.then_args), clabel(k.else_dest), args(k.else_args)) end
        if cls == Code.CodeTermSwitch then
            local cases = {}; for i = 1, #k.cases do cases[i] = C.CBackendSwitchCase(k.cases[i].literal, clabel(k.cases[i].dest), args(k.cases[i].args)) end
            return C.CBackendSwitchGoto(atom(k.value), cases, clabel(k.default_dest), args(k.default_args))
        end
        if cls == Code.CodeTermVariantSwitch then
            local cases = {}; for i = 1, #k.cases do cases[i] = C.CBackendSwitchCase(Core.LitInt(tostring(k.cases[i].variant.tag_value)), clabel(k.cases[i].dest), args(k.cases[i].args)) end
            return C.CBackendSwitchGoto(atom(k.tag), cases, clabel(k.default_dest), args(k.default_args))
        end
        if cls == Code.CodeTermReturn then return (#k.values == 0) and C.CBackendReturnVoid or C.CBackendReturn(atom(k.values[1])) end
        if cls == Code.CodeTermTrap or cls == Code.CodeTermUnreachable then return C.CBackendTrap end
        error("lower_to_c: unsupported CodeTermOp " .. class_name(k), 2)
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

    local function schedule_by_id(schedules)
        local out = {}
        for _, s in ipairs(schedules and schedules.schedules or {}) do if asdl.classof(s) == Schedule.SchedulePlanned then out[s.id.text] = s end end
        return out
    end

    local function edge_args(c_emission, edge_fact)
        local args = {}
        for _, arg in ipairs(edge_fact and edge_fact.args or {}) do args[#args + 1] = atom(arg.src) end
        return args
    end

    local function code_block_by_id(func)
        local out = {}; for _, b in ipairs(func.blocks or {}) do out[b.id.text] = b end; return out
    end

    local function c_block_params(c_emission, code_block)
        local params = {}
        for i, p in ipairs(code_block.params or {}) do params[i] = C.CBackendBlockParam(cid(p.value), c_ty(c_emission, p.ty)) end
        return params
    end

    local semantic_fragment_prelude

    local function emit_closed_form_fragment(c_emission, graph, flow, kernels, fragment)
        local kplan = kernel_by_id(kernels)[fragment.strategy.kernel.text]
        if kplan == nil then error("lower_to_c: closed-form strategy references missing kernel " .. fragment.strategy.kernel.text, 2) end
        local loop = graph_loop_by_id(graph)[kplan.subject.loop.text]
        if loop == nil or #(loop.exits or {}) ~= 1 then error("lower_to_c: closed-form fragment requires one loop exit", 2) end
        local exit = loop.exits[1]
        local edge_facts = edge_fact_by_key(flow)
        local jump_dest = exit.to.block
        local jump_fact = edge_facts[exit.from.block.text .. "\0" .. exit.to.block.text]
        for _, block in ipairs(c_emission.code_func.blocks or {}) do
            if block.id == exit.to.block and asdl.classof(block.term.op) == Code.CodeTermJump then
                jump_dest = block.term.op.dest
                jump_fact = edge_facts[block.id.text .. "\0" .. block.term.op.dest.text] or jump_fact
            end
        end
        c_emission.stmts = { C.CBackendComment("semantic closed-form " .. tostring(fragment.strategy.fact.id and fragment.strategy.fact.id.text or fragment.id.text)) }
        if semantic_fragment_prelude ~= nil then semantic_fragment_prelude(c_emission, graph, fragment, loop.header.block) end
        local result = lower_value_expr(c_emission, fragment.strategy.fact.expr)
        local args = {}
        for i, arg in ipairs(jump_fact and jump_fact.args or {}) do
            args[i] = (arg.src == fragment.strategy.fact.reduction.accumulator) and result or atom(arg.src)
        end
        local header = c_emission.block_by_id[loop.header.block.text]
        c_emission.blocks[#c_emission.blocks + 1] = C.CBackendBlock(clabel(loop.header.block), c_block_params(c_emission, header), c_emission.stmts, C.CBackendGoto(clabel(jump_dest), args))
    end

    local function loop_partition(c_emission, graph, flow, kplan)
        local loop = graph_loop_by_id(graph)[kplan.subject.loop.text]
        if loop == nil or #(loop.latches or {}) ~= 1 or #(loop.exits or {}) ~= 1 then error("lower_to_c: kernel fragment requires one loop/latch/exit", 2) end
        local body_set = {}; for _, gb in ipairs(loop.body or {}) do body_set[gb.block.text] = true end
        local edge_facts = edge_fact_by_key(flow)
        local exit_edge, latch_edge = loop.exits[1], loop.latches[1]
        local body_successor = nil
        for _, fg in ipairs(graph.funcs or {}) do
            if fg.func == loop.func then
                for _, edge in ipairs(fg.edges or {}) do
                    if edge.from.block == loop.header.block and body_set[edge.to.block.text] and edge.to.block ~= loop.header.block then body_successor = edge.to.block end
                end
            end
        end
        if body_successor == nil then error("lower_to_c: kernel cannot find header body successor", 2) end
        local loop_fact = nil
        for _, lf in ipairs(flow.loops or {}) do if lf.loop == loop.id then loop_fact = lf end end
        local cond = loop_fact and loop_fact.exits and loop_fact.exits[1] and loop_fact.exits[1].condition
        if cond == nil then error("lower_to_c: kernel loop exit has no condition", 2) end
        return loop, body_set, edge_facts, exit_edge, latch_edge, body_successor, cond, loop_fact
    end

    local function place_bindings_effects(c_emission, kplan)
        local bindings_by_block, effects_by_block = {}, {}
        for _, binding in ipairs(kplan.body.bindings or {}) do
            local block = c_emission.kernel_value_block[binding.id.text]
            if block ~= nil then bindings_by_block[block.text] = bindings_by_block[block.text] or {}; bindings_by_block[block.text][#bindings_by_block[block.text] + 1] = binding end
        end
        for _, effect in ipairs(kplan.body.effects or {}) do
            if asdl.classof(effect) == Kernel.KernelEffectStore then
                local access = first_write_access(c_emission, effect.dst)
                local block = access and access.block and access.block.block
                if block ~= nil then effects_by_block[block.text] = effects_by_block[block.text] or {}; effects_by_block[block.text][#effects_by_block[block.text] + 1] = effect end
            elseif asdl.classof(effect) ~= Kernel.KernelEffectFold then
                error("lower_to_c: unsupported KernelEffect in planned kernel", 2)
            end
        end
        return bindings_by_block, effects_by_block
    end

    local function emit_scalar_kernel_fragment(c_emission, graph, flow, kernels, fragment)
        local kplan = kernel_by_id(kernels)[fragment.strategy.kernel.text]
        if kplan == nil then error("lower_to_c: kernel strategy references missing kernel " .. fragment.strategy.kernel.text, 2) end
        local loop, body_set, edge_facts, exit_edge, latch_edge, body_successor, cond = loop_partition(c_emission, graph, flow, kplan)
        local bindings_by_block, effects_by_block = place_bindings_effects(c_emission, kplan)
        local header_block = c_emission.block_by_id[loop.header.block.text]
        c_emission.stmts = { C.CBackendComment("semantic scalar kernel " .. kplan.id.text) }
        if semantic_fragment_prelude ~= nil then semantic_fragment_prelude(c_emission, graph, fragment, loop.header.block) end
        for _, b in ipairs(bindings_by_block[loop.header.block.text] or {}) do bind_kernel_value(c_emission, b) end
        c_emission.blocks[#c_emission.blocks + 1] = C.CBackendBlock(clabel(loop.header.block), c_block_params(c_emission, header_block), c_emission.stmts,
            C.CBackendIfGoto(atom(cond), clabel(exit_edge.to.block), edge_args(c_emission, edge_facts[exit_edge.from.block.text .. "\0" .. exit_edge.to.block.text]), clabel(body_successor), edge_args(c_emission, edge_facts[exit_edge.from.block.text .. "\0" .. body_successor.text])))
        for _, block in ipairs(c_emission.code_func.blocks or {}) do
            if body_set[block.id.text] and block.id ~= loop.header.block then
                c_emission.stmts = { C.CBackendComment("semantic scalar kernel body " .. kplan.id.text) }
                if semantic_fragment_prelude ~= nil then semantic_fragment_prelude(c_emission, graph, fragment, block.id) end
                for _, b in ipairs(bindings_by_block[block.id.text] or {}) do bind_kernel_value(c_emission, b) end
                for _, e in ipairs(effects_by_block[block.id.text] or {}) do emit_kernel_effect(c_emission, e) end
                local term
                if block.id == latch_edge.from.block then
                    term = C.CBackendGoto(clabel(loop.header.block), edge_args(c_emission, edge_facts[latch_edge.from.block.text .. "\0" .. latch_edge.to.block.text]))
                else
                    local next_edge = nil
                    for _, fg in ipairs(graph.funcs or {}) do if fg.func == loop.func then for _, edge in ipairs(fg.edges or {}) do if edge.from.block == block.id and body_set[edge.to.block.text] then next_edge = edge end end end end
                    if next_edge == nil then error("lower_to_c: scalar kernel body block has no in-loop successor", 2) end
                    term = C.CBackendGoto(clabel(next_edge.to.block), edge_args(c_emission, edge_facts[next_edge.from.block.text .. "\0" .. next_edge.to.block.text]))
                end
                c_emission.blocks[#c_emission.blocks + 1] = C.CBackendBlock(clabel(block.id), c_block_params(c_emission, block), c_emission.stmts, term)
            end
        end
    end

    local function value_expr_add_lane(c_emission, expr, lane, ty)
        if lane == 0 then return expr end
        return Value.ValueExprAdd(expr, Value.ValueExprConst(Code.CodeConstLiteral(ty, Core.LitInt(tostring(lane)))), ty, Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZero, Code.CodeShiftMaskCount))
    end

    local function vector_lane_place_for_access(c_emission, lane_desc, access, lane, counter_ty)
        local idx = atom(c_emission.vector_counter)
        if lane ~= 0 then
            local dst = tmp(c_emission, "vec_lane_index", counter_ty)
            c_emission.stmts[#c_emission.stmts + 1] = C.CBackendHelperCall(dst, binary_helper(c_emission, Core.BinAdd, counter_ty, nil), { atom(c_emission.vector_counter), C.CBackendAtomLiteral(c_ty(c_emission, counter_ty), Core.LitInt(tostring(lane))) })
            idx = C.CBackendAtomLocal(dst)
        end
        local elem_size = 1
        local const_offset = 0
        local icls = access and asdl.classof(access.index) or nil
        if icls == Mem.MemIndexValue or icls == Mem.MemIndexInduction then
            elem_size = access.index.elem_size or 1
            const_offset = access.index.const_offset or 0
        end
        local base = base_atom(c_emission, lane_desc.base)
        if const_offset ~= 0 then
            local ptr = tmp(c_emission, "vec_lane_ptr", Code.CodeTyDataPtr(lane_desc.elem_ty))
            assign(c_emission, ptr, C.CBackendRPtrOffset(base, idx, elem_size, const_offset))
            return C.CBackendPlaceDeref(C.CBackendAtomLocal(ptr), c_ty(c_emission, lane_desc.elem_ty), nil)
        end
        return C.CBackendPlaceIndex(C.CBackendPlaceDeref(base, c_ty(c_emission, lane_desc.elem_ty), nil), idx, c_ty(c_emission, lane_desc.elem_ty), elem_size)
    end

    local function vector_read_lane_place(c_emission, lane_desc, lane, counter_ty)
        return vector_lane_place_for_access(c_emission, lane_desc, first_read_access(c_emission, lane_desc), lane, counter_ty)
    end

    local function vector_write_lane_place(c_emission, lane_desc, lane, counter_ty)
        return vector_lane_place_for_access(c_emission, lane_desc, first_write_access(c_emission, lane_desc), lane, counter_ty)
    end

    local lower_value_expr_lane, lower_kernel_expr_lane

    lower_value_expr_lane = function(c_emission, expr, lane, index_ty)
        local cls = asdl.classof(expr)
        if cls == Value.ValueExprValue then
            local cached = c_emission.lane_value_by_code and c_emission.lane_value_by_code[expr.value.text]
            if cached ~= nil then return cached.atom, cached.ty end
            return lower_value_expr(c_emission, expr)
        elseif cls == Value.ValueExprConst then
            return const_atom(c_emission, expr.const)
        elseif cls == Value.ValueExprAdd or cls == Value.ValueExprSub or cls == Value.ValueExprMul or cls == Value.ValueExprDiv or cls == Value.ValueExprRem then
            local a, aty = lower_value_expr_lane(c_emission, expr.a, lane, index_ty)
            local b, bty = lower_value_expr_lane(c_emission, expr.b, lane, index_ty)
            a = cast_to(c_emission, a, aty, expr.ty, "vec_bin_lhs")
            b = cast_to(c_emission, b, bty, expr.ty, "vec_bin_rhs")
            local dst = tmp(c_emission, "vec_bin", expr.ty)
            local op = (cls == Value.ValueExprAdd and Core.BinAdd) or (cls == Value.ValueExprSub and Core.BinSub) or (cls == Value.ValueExprMul and Core.BinMul) or (cls == Value.ValueExprRem and Core.BinRem) or Core.BinDiv
            c_emission.stmts[#c_emission.stmts + 1] = C.CBackendHelperCall(dst, binary_helper(c_emission, op, expr.ty, expr.sem), { a, b })
            return C.CBackendAtomLocal(dst), expr.ty
        elseif cls == Value.ValueExprBinary then
            local a, aty = lower_value_expr_lane(c_emission, expr.a, lane, index_ty)
            local b, bty = lower_value_expr_lane(c_emission, expr.b, lane, index_ty)
            a = cast_to(c_emission, a, aty, expr.ty, "vec_bin_lhs")
            b = cast_to(c_emission, b, bty, expr.ty, "vec_bin_rhs")
            local dst = tmp(c_emission, "vec_bin", expr.ty)
            c_emission.stmts[#c_emission.stmts + 1] = C.CBackendHelperCall(dst, binary_helper(c_emission, expr.op, expr.ty, expr.sem), { a, b })
            return C.CBackendAtomLocal(dst), expr.ty
        elseif cls == Value.ValueExprCmp then
            local a, aty = lower_value_expr_lane(c_emission, expr.a, lane, index_ty)
            local b, bty = lower_value_expr_lane(c_emission, expr.b, lane, index_ty)
            a = cast_to(c_emission, a, aty, expr.ty, "vec_cmp_lhs")
            b = cast_to(c_emission, b, bty, expr.ty, "vec_cmp_rhs")
            local dst = tmp(c_emission, "vec_cmp", Code.CodeTyBool8)
            assign(c_emission, dst, C.CBackendRCompare(expr.op, c_ty(c_emission, expr.ty), a, b))
            return C.CBackendAtomLocal(dst), Code.CodeTyBool8
        elseif cls == Value.ValueExprSelect then
            local cnd = lower_value_expr_lane(c_emission, expr.cond, lane, index_ty)
            local t, tty = lower_value_expr_lane(c_emission, expr.t, lane, index_ty)
            local f, fty = lower_value_expr_lane(c_emission, expr.f, lane, index_ty)
            local ty = tty or fty
            t = cast_to(c_emission, t, tty, ty, "vec_sel_t")
            f = cast_to(c_emission, f, fty, ty, "vec_sel_f")
            local dst = tmp(c_emission, "vec_select", ty)
            assign(c_emission, dst, C.CBackendRSelect(c_ty(c_emission, ty), cnd, t, f))
            return C.CBackendAtomLocal(dst), ty
        elseif cls == Value.ValueExprAffine then
            local ty = expr.affine.ty
            local acc, acc_ty = nil, nil
            if expr.affine.constant ~= "0" then acc, acc_ty = const_atom(c_emission, Code.CodeConstLiteral(ty, Core.LitInt(expr.affine.constant))) end
            for _, term in ipairs(expr.affine.terms or {}) do
                local tv, tty = lower_value_expr_lane(c_emission, Value.ValueExprValue(term.value), lane, index_ty)
                tv = cast_to(c_emission, tv, tty, ty, "vec_affine_cast")
                if term.coeff ~= "1" then
                    local cv = C.CBackendAtomLiteral(c_ty(c_emission, ty), Core.LitInt(term.coeff))
                    local mul = tmp(c_emission, "vec_affine_mul", ty)
                    c_emission.stmts[#c_emission.stmts + 1] = C.CBackendHelperCall(mul, binary_helper(c_emission, Core.BinMul, ty, expr.affine.sem), { tv, cv })
                    tv = C.CBackendAtomLocal(mul)
                end
                if acc == nil then acc, acc_ty = tv, ty else
                    local sum = tmp(c_emission, "vec_affine_add", ty)
                    c_emission.stmts[#c_emission.stmts + 1] = C.CBackendHelperCall(sum, binary_helper(c_emission, Core.BinAdd, ty, expr.affine.sem), { acc, tv })
                    acc, acc_ty = C.CBackendAtomLocal(sum), ty
                end
            end
            if acc == nil then return C.CBackendAtomLiteral(c_ty(c_emission, ty), Core.LitInt("0")), ty end
            return acc, acc_ty
        end
        return lower_value_expr(c_emission, expr)
    end

    lower_kernel_expr_lane = function(c_emission, expr, lane, index_ty)
        local cls = asdl.classof(expr)
        if cls == Kernel.KernelExprValue then
            local cached = c_emission.lane_value_by_code and c_emission.lane_value_by_code[expr.value.text]
            if cached ~= nil then return cached.atom, cached.ty end
            return atom(expr.value), value_ty(c_emission, expr.value)
        elseif cls == Kernel.KernelExprKernelValue then
            local cached = c_emission.lane_value_by_kernel and c_emission.lane_value_by_kernel[expr.value.text]
            if cached ~= nil then return cached.atom, cached.ty end
            local binding = c_emission.kernel_binding_by_id[expr.value.text]
            if binding == nil then return kernel_value_atom(c_emission, expr.value) end
            local v, ty = lower_kernel_expr_lane(c_emission, binding.expr, lane, index_ty)
            c_emission.lane_value_by_kernel[expr.value.text] = { atom = v, ty = ty }
            local code_id = c_emission.kernel_value_code_id and c_emission.kernel_value_code_id[expr.value.text]
            if code_id ~= nil then c_emission.lane_value_by_code[code_id.text] = { atom = v, ty = ty } end
            return v, ty
        elseif cls == Kernel.KernelExprAlgebra then
            return lower_value_expr_lane(c_emission, expr.expr, lane, index_ty)
        elseif cls == Kernel.KernelExprLaneLoad then
            local dst = tmp(c_emission, "vec_lane_load", expr.lane.elem_ty)
            local place = vector_read_lane_place(c_emission, expr.lane, lane, index_ty)
            c_emission.stmts[#c_emission.stmts + 1] = C.CBackendPlaceLoad(dst, place)
            return C.CBackendAtomLocal(dst), expr.lane.elem_ty
        end
        error("lower_to_c: unsupported vector KernelExpr " .. class_name(expr), 3)
    end

    local function emit_vector_lane_effect(c_emission, effect, lane, index_ty)
        if asdl.classof(effect) ~= Kernel.KernelEffectStore then return end
        c_emission.lane_value_by_code = {}
        c_emission.lane_value_by_kernel = {}
        for _, binding in ipairs(c_emission.current_kernel_bindings or {}) do
            lower_kernel_expr_lane(c_emission, Kernel.KernelExprKernelValue(binding.id), lane, index_ty)
        end
        local value, vty = lower_kernel_expr_lane(c_emission, effect.value, lane, index_ty)
        value = cast_to(c_emission, value, vty, effect.dst.elem_ty, "vec_store_cast")
        local place = vector_write_lane_place(c_emission, effect.dst, lane, index_ty)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendPlaceStore(place, value)
    end

    local function emit_vector_kernel_fragment(c_emission, graph, flow, kernels, schedules, fragment)
        local kplan = kernel_by_id(kernels)[fragment.strategy.kernel.text]
        local sched = schedule_by_id(schedules)[fragment.strategy.schedule.text]
        if kplan == nil or sched == nil or asdl.classof(sched.form) ~= Schedule.ScheduleVector then error("lower_to_c: vector kernel strategy requires ScheduleVector", 2) end
        local lane_shape = sched.form.lanes
        if asdl.classof(lane_shape) ~= Schedule.LaneVector then error("lower_to_c: vector schedule requires LaneVector", 2) end
        local lanes = lane_shape.lanes
        local loop, body_set, edge_facts, exit_edge, latch_edge, body_successor, scalar_cond, loop_fact = loop_partition(c_emission, graph, flow, kplan)
        if loop_fact == nil or loop_fact.counted == nil or kplan.body.domain.counter == nil then error("lower_to_c: vector kernel requires counted loop", 2) end
        c_emission.current_kernel_bindings = kplan.body.bindings or {}
        for _, binding in ipairs(kplan.body.bindings or {}) do c_emission.kernel_binding_by_id[binding.id.text] = binding end
        local counter = kplan.body.domain.counter
        c_emission.vector_counter = counter
        local counter_ty = value_ty(c_emission, counter) or Code.CodeTyIndex
        local vector_label = C.CBackendLabel(clabel(loop.header.block).text .. "_semantic_vector")
        local tail_label = C.CBackendLabel(clabel(loop.header.block).text .. "_semantic_tail")
        local next_i = C.CBackendLocalId("semantic_vec_next_i_" .. sanitize(loop.id.text))
        add_local(c_emission, next_i, counter_ty)
        local ok = C.CBackendLocalId("semantic_vec_ok_" .. sanitize(loop.id.text))
        add_local(c_emission, ok, Code.CodeTyBool8)

        c_emission.stmts = { C.CBackendComment("semantic vector kernel dispatch " .. kplan.id.text) }
        if semantic_fragment_prelude ~= nil then semantic_fragment_prelude(c_emission, graph, fragment, loop.header.block) end
        for _, binding in ipairs(kplan.body.bindings or {}) do
            local block = c_emission.kernel_value_block and c_emission.kernel_value_block[binding.id.text]
            if block == loop.header.block then bind_kernel_value(c_emission, binding) end
        end
        local lane_atom = C.CBackendAtomLiteral(c_ty(c_emission, counter_ty), Core.LitInt(tostring(lanes)))
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendHelperCall(next_i, binary_helper(c_emission, Core.BinAdd, counter_ty, nil), { atom(counter), lane_atom })
        local stop = atom(loop_fact.counted.stop)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendAssign(ok, C.CBackendRCompare(Core.CmpLe, c_ty(c_emission, counter_ty), C.CBackendAtomLocal(next_i), stop))
        c_emission.blocks[#c_emission.blocks + 1] = C.CBackendBlock(clabel(loop.header.block), c_block_params(c_emission, c_emission.block_by_id[loop.header.block.text]), c_emission.stmts,
            C.CBackendIfGoto(C.CBackendAtomLocal(ok), vector_label, {}, tail_label, {}))

        c_emission.stmts = { C.CBackendComment("semantic vector main loop lanes=" .. tostring(lanes)) }
        for _, effect in ipairs(kplan.body.effects or {}) do for lane = 0, lanes - 1 do emit_vector_lane_effect(c_emission, effect, lane, counter_ty) end end
        local latch_fact = edge_facts[latch_edge.from.block.text .. "\0" .. latch_edge.to.block.text]
        local jump_args = {}
        for _, arg in ipairs(latch_fact and latch_fact.args or {}) do jump_args[#jump_args + 1] = (arg.dst_param == counter) and C.CBackendAtomLocal(next_i) or atom(arg.dst_param) end
        c_emission.blocks[#c_emission.blocks + 1] = C.CBackendBlock(vector_label, {}, c_emission.stmts, C.CBackendGoto(clabel(loop.header.block), jump_args))

        c_emission.stmts = { C.CBackendComment("semantic vector scalar tail") }
        c_emission.blocks[#c_emission.blocks + 1] = C.CBackendBlock(tail_label, {}, c_emission.stmts,
            C.CBackendIfGoto(atom(scalar_cond), clabel(exit_edge.to.block), edge_args(c_emission, edge_facts[exit_edge.from.block.text .. "\0" .. exit_edge.to.block.text]), clabel(body_successor), edge_args(c_emission, edge_facts[exit_edge.from.block.text .. "\0" .. body_successor.text])))

        local bindings_by_block, effects_by_block = place_bindings_effects(c_emission, kplan)
        for _, block in ipairs(c_emission.code_func.blocks or {}) do
            if body_set[block.id.text] and block.id ~= loop.header.block then
                c_emission.stmts = { C.CBackendComment("semantic vector scalar-tail body " .. kplan.id.text) }
                if semantic_fragment_prelude ~= nil then semantic_fragment_prelude(c_emission, graph, fragment, block.id) end
                for _, b in ipairs(bindings_by_block[block.id.text] or {}) do bind_kernel_value(c_emission, b) end
                for _, e in ipairs(effects_by_block[block.id.text] or {}) do emit_kernel_effect(c_emission, e) end
                local term
                if block.id == latch_edge.from.block then
                    term = C.CBackendGoto(clabel(loop.header.block), edge_args(c_emission, latch_fact))
                else
                    local next_edge = nil
                    for _, fg in ipairs(graph.funcs or {}) do if fg.func == loop.func then for _, edge in ipairs(fg.edges or {}) do if edge.from.block == block.id and body_set[edge.to.block.text] then next_edge = edge end end end end
                    if next_edge == nil then error("lower_to_c: vector tail body block has no in-loop successor", 2) end
                    term = C.CBackendGoto(clabel(next_edge.to.block), edge_args(c_emission, edge_facts[next_edge.from.block.text .. "\0" .. next_edge.to.block.text]))
                end
                c_emission.blocks[#c_emission.blocks + 1] = C.CBackendBlock(clabel(block.id), c_block_params(c_emission, block), c_emission.stmts, term)
            end
        end
    end

    local function cover_blocks(fragment, func, graph_loops)
        local cover = fragment.cover
        local cls = asdl.classof(cover)
        local out, set = {}, {}
        local function add(block) if block and not set[block.id.text] then set[block.id.text] = true; out[#out + 1] = block end end
        if cls == Lower.LowerCoverFunction then for _, b in ipairs(func.blocks or {}) do add(b) end
        elseif cls == Lower.LowerCoverBlock then for _, b in ipairs(func.blocks or {}) do if b.id == cover.block then add(b) end end
        elseif cls == Lower.LowerCoverLoop then
            local loop = graph_loops[cover.loop.text]
            local body = {}; for _, gb in ipairs(loop and loop.body or {}) do body[gb.block.text] = true end
            for _, b in ipairs(func.blocks or {}) do if body[b.id.text] then add(b) end end
        elseif cls == Lower.LowerCoverBlockRange then
            local active = false
            for _, b in ipairs(func.blocks or {}) do if b.id == cover.entry then active = true end; if active then add(b) end; if b.id == cover.exit then break end end
        end
        return out, set
    end

    semantic_fragment_prelude = function(c_emission, graph, fragment, only_block)
        local _, covered = cover_blocks(fragment, c_emission.code_func, graph_loop_by_id(graph))
        local aliases = {}
        local components = {}
        local emitted = {}

        local function ref(id, ty)
            return { atom = atom(id), ty = ty or value_ty(c_emission, id) }
        end
        local function emit_assign_once(dst, src)
            if dst == nil or src == nil or emitted[dst.text] then return end
            emitted[dst.text] = true
            note_value(c_emission, dst, src.ty)
            c_emission.stmts[#c_emission.stmts + 1] = C.CBackendAssign(cid(dst), C.CBackendRAtom(src.atom))
        end
        local function resolve_view(id)
            local seen = {}
            while id ~= nil and aliases[id.text] ~= nil and not seen[id.text] do
                seen[id.text] = true
                id = aliases[id.text]
            end
            return id
        end
        local function component(id, field)
            id = resolve_view(id)
            local comp = id and components[id.text] or nil
            return comp and comp[field] or nil
        end
        local function emit_field_load(dst, view, field, ty)
            if dst == nil or view == nil or emitted[dst.text] then return end
            emitted[dst.text] = true
            note_value(c_emission, dst, ty)
            local vty = view_type(c_emission, view)
            if vty == nil then error("lower_to_c: semantic descriptor projection references unknown value " .. tostring(view.text), 3) end
            c_emission.stmts[#c_emission.stmts + 1] = C.CBackendPlaceLoad(cid(dst), C.CBackendPlaceField(C.CBackendPlaceLocal(cid(view), c_ty(c_emission, vty)), C.CBackendName(field), c_ty(c_emission, ty), 0, nil, nil))
        end

        for _, block in ipairs(c_emission.code_func.blocks or {}) do
            if covered[block.id.text] then
                for _, inst in ipairs(block.insts or {}) do
                    local k = inst.op
                    local cls = asdl.classof(k)
                    if cls == Code.CodeInstViewMake then
                        local vty = Code.CodeTyView(k.elem_ty)
                        note_value(c_emission, k.dst, vty)
                        components[k.dst.text] = {
                            data = ref(k.data, Code.CodeTyDataPtr(k.elem_ty)),
                            len = ref(k.len, Code.CodeTyIndex),
                            stride = ref(k.stride, Code.CodeTyIndex),
                        }
                    elseif cls == Code.CodeInstSliceMake then
                        local sty = Code.CodeTySlice(k.elem_ty)
                        note_value(c_emission, k.dst, sty)
                        components[k.dst.text] = {
                            data = ref(k.data, Code.CodeTyDataPtr(k.elem_ty)),
                            len = ref(k.len, Code.CodeTyIndex),
                        }
                    elseif cls == Code.CodeInstByteSpanMake then
                        note_value(c_emission, k.dst, Code.CodeTyByteSpan)
                        components[k.dst.text] = {
                            data = ref(k.data, Code.CodeTyDataPtr(byte_ty())),
                            len = ref(k.len, Code.CodeTyIndex),
                        }
                    elseif cls == Code.CodeInstAlias and (asdl.classof(value_ty(c_emission, k.dst)) == Code.CodeTyView or asdl.classof(value_ty(c_emission, k.dst)) == Code.CodeTySlice or value_ty(c_emission, k.dst) == Code.CodeTyByteSpan or asdl.classof(value_ty(c_emission, k.dst)) == Code.CodeTyByteSpan) then
                        local src = resolve_view(k.src)
                        if src ~= nil then aliases[k.dst.text] = src end
                        if src ~= nil and components[src.text] ~= nil then components[k.dst.text] = components[src.text] end
                    end
                end
            end
        end

        for _, block in ipairs(c_emission.code_func.blocks or {}) do
            if covered[block.id.text] and (only_block == nil or only_block == block.id) then
                for _, inst in ipairs(block.insts or {}) do
                    local k = inst.op
                    local cls = asdl.classof(k)
                    if cls == Code.CodeInstViewData then
                        local src = component(k.view, "data")
                        if src ~= nil then emit_assign_once(k.dst, src)
                        else emit_field_load(k.dst, resolve_view(k.view), "data", view_data_type(c_emission, k.view)) end
                    elseif cls == Code.CodeInstViewLen then
                        local src = component(k.view, "len")
                        if src ~= nil then emit_assign_once(k.dst, src)
                        else emit_field_load(k.dst, resolve_view(k.view), "len", Code.CodeTyIndex) end
                    elseif cls == Code.CodeInstViewStride then
                        local src = component(k.view, "stride")
                        if src ~= nil then emit_assign_once(k.dst, src)
                        else emit_field_load(k.dst, resolve_view(k.view), "stride", Code.CodeTyIndex) end
                    elseif cls == Code.CodeInstSliceData then
                        local src = component(k.slice, "data")
                        if src ~= nil then emit_assign_once(k.dst, src)
                        else emit_field_load(k.dst, resolve_view(k.slice), "data", slice_data_type(c_emission, k.slice)) end
                    elseif cls == Code.CodeInstSliceLen then
                        local src = component(k.slice, "len")
                        if src ~= nil then emit_assign_once(k.dst, src)
                        else emit_field_load(k.dst, resolve_view(k.slice), "len", Code.CodeTyIndex) end
                    elseif cls == Code.CodeInstByteSpanData then
                        local src = component(k.span, "data")
                        if src ~= nil then emit_assign_once(k.dst, src)
                        else emit_field_load(k.dst, resolve_view(k.span), "data", Code.CodeTyDataPtr(byte_ty())) end
                    elseif cls == Code.CodeInstByteSpanLen then
                        local src = component(k.span, "len")
                        if src ~= nil then emit_assign_once(k.dst, src)
                        else emit_field_load(k.dst, resolve_view(k.span), "len", Code.CodeTyIndex) end
                    end
                end
            end
        end
    end

    local function ordered_fragments_for_func(func, func_plan, graph_loops)
        local ordered, emitted = {}, {}
        for _, block in ipairs(func.blocks or {}) do
            if not emitted[block.id.text] then
                local chosen = nil
                for _, fragment in ipairs(func_plan.fragments or {}) do
                    local _, set = cover_blocks(fragment, func, graph_loops)
                    if set[block.id.text] then chosen = fragment; break end
                end
                if chosen then
                    ordered[#ordered + 1] = chosen
                    local _, set = cover_blocks(chosen, func, graph_loops)
                    for key in pairs(set) do emitted[key] = true end
                end
            end
        end
        return ordered
    end

    local function semantic_strategy(fragment)
        local cls = asdl.classof(fragment.strategy)
        return cls == Lower.LowerStrategyKernel or cls == Lower.LowerStrategyClosedForm
    end

    local function lower_emit_candidate(fragment, schedules_by_id)
        return fragment.strategy:lower_emit_candidate(fragment.strategy:lower_emit_schedule(schedules_by_id))
    end

    function Lower.LowerStrategy:lower_emit_schedule(schedules_by_id) return nil end
    function Lower.LowerStrategyKernel:lower_emit_schedule(schedules_by_id)
        return schedules_by_id and schedules_by_id[self.schedule.text] or nil
    end
    function Lower.LowerStrategy:lower_emit_missing_schedule_reason() return "" end
    function Lower.LowerStrategyKernel:lower_emit_missing_schedule_reason()
        return "kernel strategy references missing schedule " .. self.schedule.text
    end

    local function baseline_block_by_label(blocks)
        local out = {}
        for _, block in ipairs(blocks or {}) do out[block.label.text] = block end
        return out
    end

    function Lower.LowerEmitSelection:emit_to_c(c_emission, fragment_emit)
        error("lower_to_c: unsupported lower emission selection", 2)
    end

    function Lower.LowerEmitCode:emit_to_c(c_emission, fragment_emit)
        local baseline_blocks = baseline_block_by_label(fragment_emit.baseline_blocks)
        local graph_loops = graph_loop_by_id(fragment_emit.graph)
        for _, b in ipairs(cover_blocks(fragment_emit.fragment, fragment_emit.code_func, graph_loops)) do
            c_emission.blocks[#c_emission.blocks + 1] = baseline_blocks[clabel(b.id).text]
        end
    end

    function Lower.LowerEmitClosedForm:emit_to_c(c_emission, fragment_emit)
        emit_closed_form_fragment(c_emission, fragment_emit.graph, fragment_emit.flow, fragment_emit.kernels, fragment_emit.fragment)
    end

    function Lower.LowerEmitScalarKernel:emit_to_c(c_emission, fragment_emit)
        emit_scalar_kernel_fragment(c_emission, fragment_emit.graph, fragment_emit.flow, fragment_emit.kernels, fragment_emit.fragment)
    end

    function Lower.LowerEmitVectorKernel:emit_to_c(c_emission, fragment_emit)
        emit_vector_kernel_fragment(c_emission, fragment_emit.graph, fragment_emit.flow, fragment_emit.kernels, fragment_emit.schedules, fragment_emit.fragment)
    end

    function Lower.LowerEmitMissingSchedule:emit_to_c(c_emission, fragment_emit)
        error("lower_to_c: " .. tostring(self.reason), 2)
    end

    function Lower.LowerEmitUnsupported:emit_to_c(c_emission, fragment_emit)
        error("lower_to_c: " .. tostring(self.reason), 2)
    end

    local function prepare_func_emission(c_emission, code_func, c_func)
        c_emission.code_func = code_func
        c_emission.func = c_func
        c_emission.blocks = {}
        c_emission.block_by_id = code_block_by_id(code_func)
        c_emission.value_types = {}
        c_emission.kernel_value_local = {}
        c_emission.kernel_value_types = {}
        c_emission.kernel_value_block = {}
        c_emission.kernel_value_code_id = {}
        c_emission.kernel_binding_by_id = {}
        c_emission.const_by_value = {}
        c_emission.local_seen = {}
        for _, p in ipairs(c_func.params or {}) do c_emission.local_seen[p.id.text] = true end
        for _, l in ipairs(c_func.locals or {}) do c_emission.local_seen[l.id.text] = true end
        local function note_inst_dst(block, k)
            local cls = asdl.classof(k)
            local dst, ty = nil, nil
            if cls == Code.CodeInstConst then dst, ty = k.dst, k.const.ty; c_emission.const_by_value[k.dst.text] = k.const
            elseif cls == Code.CodeInstAlias or cls == Code.CodeInstUnary or cls == Code.CodeInstBinary or cls == Code.CodeInstFloatBinary or cls == Code.CodeInstSelect then dst, ty = k.dst, k.ty
            elseif cls == Code.CodeInstCompare then dst, ty = k.dst, Code.CodeTyBool8
            elseif cls == Code.CodeInstCast then dst, ty = k.dst, k.to
            elseif cls == Code.CodeInstAddrOf or cls == Code.CodeInstGlobalRef or cls == Code.CodeInstPtrOffset then dst, ty = k.dst, k.ptr_ty
            elseif cls == Code.CodeInstLoad or cls == Code.CodeInstAtomicLoad or cls == Code.CodeInstAtomicRmw then dst, ty = k.dst, k.access.ty
            elseif cls == Code.CodeInstViewMake then dst, ty = k.dst, Code.CodeTyView(k.elem_ty)
            elseif cls == Code.CodeInstViewData then dst, ty = k.dst, Code.CodeTyDataPtr(nil)
            elseif cls == Code.CodeInstViewLen or cls == Code.CodeInstViewStride then dst, ty = k.dst, Code.CodeTyIndex
            elseif cls == Code.CodeInstSliceMake then dst, ty = k.dst, Code.CodeTySlice(k.elem_ty)
            elseif cls == Code.CodeInstSliceData then dst, ty = k.dst, Code.CodeTyDataPtr(nil)
            elseif cls == Code.CodeInstSliceLen then dst, ty = k.dst, Code.CodeTyIndex
            elseif cls == Code.CodeInstByteSpanMake then dst, ty = k.dst, Code.CodeTyByteSpan
            elseif cls == Code.CodeInstByteSpanData then dst, ty = k.dst, Code.CodeTyDataPtr(byte_ty())
            elseif cls == Code.CodeInstByteSpanLen then dst, ty = k.dst, Code.CodeTyIndex
            elseif cls == Code.CodeInstCall then dst = rawget(k, "dst") end
            if dst ~= nil and ty ~= nil then
                note_value(c_emission, dst, ty)
                local kid = Kernel.KernelValueId("kval:" .. dst.text)
                c_emission.kernel_value_local[kid.text] = cid(dst)
                c_emission.kernel_value_types[kid.text] = ty
                c_emission.kernel_value_block[kid.text] = block.id
                c_emission.kernel_value_code_id[kid.text] = dst
            end
        end
        for _, param in ipairs(code_func.params or {}) do note_value(c_emission, param.value, param.ty) end
        for _, b in ipairs(code_func.blocks or {}) do
            for _, param in ipairs(b.params or {}) do note_value(c_emission, param.value, param.ty) end
            for _, inst in ipairs(b.insts or {}) do note_inst_dst(b, inst.op) end
        end
    end

    local function lower_semantic_func(c_emission, graph, flow, kernels, schedules, code_func, c_func, func_plan, graph_loops, baseline_blocks)
        local mutable_func = {
            name = c_func.name,
            symbol = c_func.symbol,
            visibility = c_func.visibility,
            sig = c_func.sig,
            params = c_func.params,
            locals = {},
        }
        for i, l in ipairs(c_func.locals or {}) do mutable_func.locals[i] = l end
        prepare_func_emission(c_emission, code_func, mutable_func)
        local schedules_by_id = schedule_by_id(schedules)
        for _, fragment in ipairs(ordered_fragments_for_func(code_func, func_plan, graph_loops)) do
            local selection = lower_emit_candidate(fragment, schedules_by_id):select_lower_emit()
            selection:emit_to_c(c_emission, Lower.LowerCEmitInput(graph, flow, kernels, schedules, code_func, fragment, baseline_blocks))
        end
        return C.CBackendFunc(
            mutable_func.name,
            mutable_func.symbol,
            mutable_func.visibility,
            mutable_func.sig,
            mutable_func.params,
            mutable_func.locals,
            C.CBackendBodyBlocks(clabel(code_func.blocks[1].id), c_emission.blocks)
        )
    end

    local function func_by_id(code_module)
        local out = {}; for _, f in ipairs(code_module.funcs or {}) do out[f.id.text] = f end; return out
    end

    local function c_block_body(func)
        local body = assert(func and func.body, "lower_to_c: expected C function with body")
        if asdl.classof(body) ~= C.CBackendBodyBlocks then error("lower_to_c: semantic lowering requires canonical C block body", 3) end
        return body.blocks
    end

    local function graph_indexes(graph)
        local loops = {}
        for _, fg in ipairs(graph and graph.funcs or {}) do for _, loop in ipairs(fg.loops or {}) do loops[loop.id.text] = loop end end
        return loops
    end

    local function normalize_args(code_module, lower_module, opts)
        opts = opts or {}
        if lower_module ~= nil and asdl.classof(lower_module) == Lower.LowerModule then
            local graph = CodeGraph.graph(code_module)
            local flow = lower_module.kernels and lower_module.kernels.flow or CodeFlowFacts.facts(code_module, graph)
            local value = lower_module.kernels and lower_module.kernels.value or CodeValueFacts.facts(code_module, graph, flow)
            local mem = lower_module.kernels and lower_module.kernels.mem or CodeMemFacts.semantic_facts(code_module, graph, flow, value, nil)
            local effect = lower_module.kernels and lower_module.kernels.effect or CodeEffectFacts.facts(code_module, graph, mem, nil)
            return graph, flow, value, mem, effect, lower_module.kernels, lower_module.schedules, lower_module, opts
        end
        local graph = CodeGraph.graph(code_module)
        local flow = CodeFlowFacts.facts(code_module, graph)
        local value = CodeValueFacts.facts(code_module, graph, flow)
        local mem = CodeMemFacts.semantic_facts(code_module, graph, flow, value, nil)
        local effect = CodeEffectFacts.facts(code_module, graph, mem, nil)
        local kernels = CodeKernelPlan.plan(code_module, graph, flow, value, mem, effect)
        local schedules = CodeSchedulePlan.plan(code_module, kernels, flow, value, mem, effect, opts and (opts.target_model or opts.back_target_model))
        local lower = CodeLowerPlan.plan(code_module, graph, kernels, schedules, Lower.LowerTargetC)
        return graph, flow, value, mem, effect, kernels, schedules, lower, opts
    end

    local function module(code_module, lower_module, opts)
        local graph, flow, value, mem, effect, kernels, schedules, lower
        graph, flow, value, mem, effect, kernels, schedules, lower, opts = normalize_args(code_module, lower_module, opts)
        opts = opts or {}
        local unit = CodeToC.module(code_module, opts)
        local has_semantic = false
        for _, fp in ipairs(lower.funcs or {}) do for _, frag in ipairs(fp.fragments or {}) do if semantic_strategy(frag) then has_semantic = true end end end
        if not has_semantic then return unit end

        local base_func_by_name = {}; for _, f in ipairs(unit.funcs or {}) do base_func_by_name[f.symbol] = f end
        local plans = {}; for _, fp in ipairs(lower.funcs or {}) do plans[fp.func.text] = fp end
        local funcs = func_by_id(code_module)
        local graph_loops = graph_indexes(graph)
        local cfuncs = {}
        local c_emission = {
            unit = unit,
            c_type_projection = make_c_type_projection(code_module),
            helper_by_key = {},
            next_helper = 0,
            next_tmp = 0,
            mem = mem,
            mem_projection = CodeMemFacts.access_projection(mem),
        }
        for _, h in ipairs(unit.helpers or {}) do c_emission.helper_by_key[helper_key(h.spec)] = h end

        for _, code_func in ipairs(code_module.funcs or {}) do
            local fp = plans[code_func.id.text]
            local base = base_func_by_name[code_func.name]
            if fp ~= nil then
                local semantic = false
                for _, frag in ipairs(fp.fragments or {}) do if semantic_strategy(frag) then semantic = true end end
                if semantic then cfuncs[#cfuncs + 1] = lower_semantic_func(c_emission, graph, flow, kernels, schedules, code_func, base, fp, graph_loops, c_block_body(base))
                else cfuncs[#cfuncs + 1] = base end
            else
                cfuncs[#cfuncs + 1] = base
            end
        end
        return C.CBackendUnit(unit.module_name, unit.target, unit.sigs, unit.types, unit.globals, unit.externs, unit.helpers, cfuncs)
    end

    local function exec_plan(code_module, lower_module, opts)
        local graph, flow, value, mem, effect, kernels
        graph, flow, value, mem, effect, kernels, _, _, opts = normalize_args(code_module, lower_module, opts)
        opts = opts or {}
        return ExecPlan.plan(code_module, {
            graph = graph,
            flow = flow,
            value = value,
            mem = mem,
            effect = effect,
            kernels = kernels,
            stencil = opts.stencil,
            artifacts = opts.artifacts,
            contracts = opts.contracts,
        })
    end

    api.module = module
    api.unit = module
    api.exec_plan = exec_plan
    api.exec = exec_plan

    T._lalin_api_cache.lower_to_c = api
    return api
end

return bind_context
