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
    if T._moonlift_api_cache.lower_to_c ~= nil then return T._moonlift_api_cache.lower_to_c end

    local Core = T.MoonCore
    local Code = T.MoonCode
    local C = T.MoonC
    local Lower = T.MoonLower
    local Kernel = T.MoonKernel
    local Schedule = T.MoonSchedule
    local Value = T.MoonValue
    local Mem = T.MoonMem

    local CodeToC = require("moonlift.code_to_c").Define(T)
    local CodeType = require("moonlift.code_type").Define(T)
    local CodeGraph = require("moonlift.code_graph").Define(T)
    local CodeFlowFacts = require("moonlift.code_flow_facts").Define(T)
    local CodeValueFacts = require("moonlift.code_value_facts").Define(T)
    local CodeMemFacts = require("moonlift.code_mem_facts").Define(T)
    local CodeEffectFacts = require("moonlift.code_effect_facts").Define(T)
    local CodeKernelPlan = require("moonlift.code_kernel_plan").Define(T)
    local CodeSchedulePlan = require("moonlift.code_schedule_plan").Define(T)
    local CodeLowerPlan = require("moonlift.code_lower_plan").Define(T)

    local api = {}

    local function cname(text) return C.CBackendName(sanitize(text)) end
    local function clabel(id) return C.CBackendLabel(sanitize(id.text)) end
    local function cid(id) return C.CBackendLocalId(sanitize(id.text)) end
    local function atom(id) return C.CBackendAtomLocal(cid(id)) end

    local function class_name(x)
        local cls = pvm.classof(x) or x
        return tostring(cls):match("Class%((.-)%)") or tostring(cls)
    end

    local function make_type_ctx(code_module)
        local type_ctx = { code_sigs = {}, code_sig_order = {} }
        for _, sig in ipairs(code_module.sigs or {}) do type_ctx.code_sigs[sig.id.text] = sig end
        return type_ctx
    end

    local function c_ty(ctx, ty)
        return CodeType.code_type_to_c(ty, ctx.type_ctx)
    end

    local function helper_key(kind) return tostring(kind) end

    local function add_helper(ctx, kind)
        local key = helper_key(kind)
        local existing = ctx.helper_by_key[key]
        if existing ~= nil then return existing.id end
        ctx.next_helper = ctx.next_helper + 1
        local use = C.CBackendHelperUse(C.CBackendHelperId("ml_semantic_helper_" .. tostring(ctx.next_helper)), kind)
        ctx.helper_by_key[key] = use
        ctx.unit.helpers[#ctx.unit.helpers + 1] = use
        return use.id
    end

    local function add_local(ctx, id, ty)
        local text = id.text or id
        local lid = type(id) == "table" and id or C.CBackendLocalId(text)
        if ctx.local_seen[lid.text] then return lid end
        ctx.local_seen[lid.text] = true
        ctx.func.locals[#ctx.func.locals + 1] = C.CBackendLocal(lid, C.CBackendName(lid.text), c_ty(ctx, ty))
        return lid
    end

    local function note_value(ctx, id, ty)
        if id ~= nil and ty ~= nil then ctx.value_types[id.text] = ty end
    end

    local function value_ty(ctx, id) return id and ctx.value_types[id.text] or nil end
    local function view_type(ctx, id)
        local ty = value_ty(ctx, id)
        if pvm.classof(ty) == Code.CodeTyLease then ty = ty.base end
        return ty
    end
    local function view_elem_type(ctx, id)
        local ty = view_type(ctx, id)
        if pvm.classof(ty) == Code.CodeTyView then return ty.elem end
        return nil
    end
    local function view_data_type(ctx, id)
        return Code.CodeTyDataPtr(view_elem_type(ctx, id))
    end

    local function tmp(ctx, prefix, ty)
        ctx.next_tmp = ctx.next_tmp + 1
        local id = C.CBackendLocalId(sanitize("semantic." .. prefix .. "." .. tostring(ctx.next_tmp)))
        add_local(ctx, id, ty)
        return id
    end

    local function const_atom(ctx, const)
        local cls = pvm.classof(const)
        if cls == Code.CodeConstLiteral then return C.CBackendAtomLiteral(c_ty(ctx, const.ty), const.literal), const.ty end
        if cls == Code.CodeConstNull then return C.CBackendAtomNull(c_ty(ctx, const.ty)), const.ty end
        if cls == Code.CodeConstUndef then return C.CBackendAtomLiteral(c_ty(ctx, const.ty), Core.LitInt("0")), const.ty end
        error("lower_to_c: unsupported semantic const " .. class_name(const), 3)
    end

    local function assign(ctx, dst, rhs)
        ctx.stmts[#ctx.stmts + 1] = C.CBackendAssign(dst, rhs)
    end

    local function cast_to(ctx, src_atom, src_ty, dst_ty, name)
        if tostring(c_ty(ctx, src_ty)) == tostring(c_ty(ctx, dst_ty)) then return src_atom, dst_ty end
        local dst = tmp(ctx, name or "cast", dst_ty)
        assign(ctx, dst, C.CBackendRCast(Core.MachineCastIdentity, c_ty(ctx, dst_ty), src_atom))
        return C.CBackendAtomLocal(dst), dst_ty
    end

    local function overflow_mode(sem)
        if sem and sem.overflow == Code.CodeIntTrapOnOverflow then return C.CBackendIntTrapOnOverflow end
        if sem and pvm.classof(sem.overflow) == Code.CodeIntAssumeNoOverflow then return C.CBackendIntAssumeNoOverflow end
        return C.CBackendIntWrap
    end

    local function binary_helper(ctx, op, ty, sem)
        if op == Core.BinDiv or op == Core.BinRem then
            local mode = (sem and sem.div == Code.CodeDivTrapOnZeroOrOverflow) and C.CBackendDivTrapOnZeroOrOverflow or C.CBackendDivTrapOnZero
            return add_helper(ctx, C.CBackendHelperDivRem(op, c_ty(ctx, ty), mode))
        end
        return add_helper(ctx, C.CBackendHelperIntBinary(op, c_ty(ctx, ty), overflow_mode(sem)))
    end

    local simplify_value_expr
    local function literal_int_raw(expr)
        if pvm.classof(expr) ~= Value.ValueExprConst then return nil end
        if pvm.classof(expr.const) ~= Code.CodeConstLiteral then return nil end
        if pvm.classof(expr.const.literal) ~= Core.LitInt then return nil end
        return expr.const.literal.raw, expr.const.ty
    end
    local function literal_bool_value(expr)
        if pvm.classof(expr) ~= Value.ValueExprConst then return nil end
        if pvm.classof(expr.const) ~= Code.CodeConstLiteral then return nil end
        local lcls = pvm.classof(expr.const.literal)
        if lcls == Core.LitBool then return expr.const.literal.value end
        if lcls == Core.LitInt then return expr.const.literal.raw ~= "0" end
        return nil
    end
    local function int_const(ty, raw)
        return Value.ValueExprConst(Code.CodeConstLiteral(ty, Core.LitInt(tostring(raw))))
    end
    local function is_raw(raw, want) return raw ~= nil and tostring(raw) == tostring(want) end
    simplify_value_expr = function(expr)
        local cls = pvm.classof(expr)
        if cls == Value.ValueExprAdd or cls == Value.ValueExprSub or cls == Value.ValueExprMul or cls == Value.ValueExprDiv then
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
            elseif cls == Value.ValueExprDiv then
                if is_raw(br, "1") then return a end
            end
            if ar ~= nil and br ~= nil then
                local av, bv = tonumber(ar), tonumber(br)
                if av ~= nil and bv ~= nil and av == math.floor(av) and bv == math.floor(bv) then
                    if cls == Value.ValueExprAdd then return int_const(expr.ty, av + bv) end
                    if cls == Value.ValueExprSub then return int_const(expr.ty, av - bv) end
                    if cls == Value.ValueExprMul then return int_const(expr.ty, av * bv) end
                    if cls == Value.ValueExprDiv and bv ~= 0 then return int_const(expr.ty, math.floor(av / bv)) end
                end
            end
            if cls == Value.ValueExprAdd then return Value.ValueExprAdd(a, b, expr.ty, expr.sem) end
            if cls == Value.ValueExprSub then return Value.ValueExprSub(a, b, expr.ty, expr.sem) end
            if cls == Value.ValueExprMul then return Value.ValueExprMul(a, b, expr.ty, expr.sem) end
            return Value.ValueExprDiv(a, b, expr.ty, expr.sem)
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
    lower_value_expr = function(ctx, expr)
        expr = simplify_value_expr(expr)
        local cls = pvm.classof(expr)
        if cls == Value.ValueExprConst then
            return const_atom(ctx, expr.const)
        elseif cls == Value.ValueExprValue then
            local ty = value_ty(ctx, expr.value)
            if ty == nil then error("lower_to_c: semantic expression references unknown value " .. expr.value.text, 3) end
            return atom(expr.value), ty
        elseif cls == Value.ValueExprAdd or cls == Value.ValueExprSub or cls == Value.ValueExprMul or cls == Value.ValueExprDiv then
            local a, aty = lower_value_expr(ctx, expr.a)
            local b, bty = lower_value_expr(ctx, expr.b)
            a = cast_to(ctx, a, aty, expr.ty, "bin_lhs")
            b = cast_to(ctx, b, bty, expr.ty, "bin_rhs")
            local dst = tmp(ctx, "bin", expr.ty)
            local op = (cls == Value.ValueExprAdd and Core.BinAdd) or (cls == Value.ValueExprSub and Core.BinSub) or (cls == Value.ValueExprMul and Core.BinMul) or Core.BinDiv
            ctx.stmts[#ctx.stmts + 1] = C.CBackendHelperCall(dst, binary_helper(ctx, op, expr.ty, expr.sem), { a, b })
            return C.CBackendAtomLocal(dst), expr.ty
        elseif cls == Value.ValueExprCmp then
            local a, aty = lower_value_expr(ctx, expr.a)
            local b, bty = lower_value_expr(ctx, expr.b)
            a = cast_to(ctx, a, aty, expr.ty, "cmp_lhs")
            b = cast_to(ctx, b, bty, expr.ty, "cmp_rhs")
            local dst = tmp(ctx, "cmp", Code.CodeTyBool8)
            assign(ctx, dst, C.CBackendRCompare(expr.op, c_ty(ctx, expr.ty), a, b))
            return C.CBackendAtomLocal(dst), Code.CodeTyBool8
        elseif cls == Value.ValueExprSelect then
            local cnd = lower_value_expr(ctx, expr.cond)
            local t, tty = lower_value_expr(ctx, expr.t)
            local f, fty = lower_value_expr(ctx, expr.f)
            local ty = tty or fty
            f = cast_to(ctx, f, fty, ty, "sel_f")
            t = cast_to(ctx, t, tty, ty, "sel_t")
            local dst = tmp(ctx, "select", ty)
            assign(ctx, dst, C.CBackendRSelect(c_ty(ctx, ty), cnd, t, f))
            return C.CBackendAtomLocal(dst), ty
        elseif cls == Value.ValueExprAffine then
            local ty = expr.affine.ty
            local acc, acc_ty = nil, nil
            if expr.affine.constant ~= "0" then acc, acc_ty = lower_value_expr(ctx, Value.ValueExprConst(Code.CodeConstLiteral(ty, Core.LitInt(expr.affine.constant)))) end
            for _, term in ipairs(expr.affine.terms or {}) do
                local tv, tty = lower_value_expr(ctx, Value.ValueExprValue(term.value))
                tv = cast_to(ctx, tv, tty, ty, "affine_cast")
                if term.coeff ~= "1" then
                    local cv = C.CBackendAtomLiteral(c_ty(ctx, ty), Core.LitInt(term.coeff))
                    local mul = tmp(ctx, "affine_mul", ty)
                    ctx.stmts[#ctx.stmts + 1] = C.CBackendHelperCall(mul, binary_helper(ctx, Core.BinMul, ty, expr.affine.sem), { tv, cv })
                    tv = C.CBackendAtomLocal(mul)
                end
                if acc == nil then acc, acc_ty = tv, ty else
                    local sum = tmp(ctx, "affine_add", ty)
                    ctx.stmts[#ctx.stmts + 1] = C.CBackendHelperCall(sum, binary_helper(ctx, Core.BinAdd, ty, expr.affine.sem), { acc, tv })
                    acc, acc_ty = C.CBackendAtomLocal(sum), ty
                end
            end
            if acc == nil then return C.CBackendAtomLiteral(c_ty(ctx, ty), Core.LitInt("0")), ty end
            return acc, acc_ty
        end
        error("lower_to_c: unsupported semantic ValueExpr " .. class_name(expr), 3)
    end

    local function is_write_access(kind)
        return kind == Mem.MemStore or kind == Mem.MemAtomicStore or kind == Mem.MemAtomicRmw or kind == Mem.MemAtomicCas
    end
    local function is_read_access(kind)
        return kind == Mem.MemLoad or kind == Mem.MemAtomicLoad or kind == Mem.MemAtomicRmw or kind == Mem.MemAtomicCas
    end

    local function first_access(ctx, stream, want_write)
        for _, aid in ipairs(stream.accesses or {}) do
            local access = ctx.mem_access_by_id[aid.text]
            if access ~= nil and ((want_write and is_write_access(access.kind)) or ((not want_write) and is_read_access(access.kind))) then
                return access, ctx.mem_backend_by_access[aid.text]
            end
        end
        local aid = stream.accesses and stream.accesses[1]
        if aid ~= nil then return ctx.mem_access_by_id[aid.text], ctx.mem_backend_by_access[aid.text] end
        return nil, nil
    end

    local function base_atom(ctx, base)
        local cls = pvm.classof(base)
        if cls == Mem.MemBaseValue or cls == Mem.MemBaseArgument then return atom(base.value) end
        if cls == Mem.MemBaseGlobal then return C.CBackendAtomGlobal(C.CBackendGlobalId(base.global.text)) end
        if cls == Mem.MemBaseData then return C.CBackendAtomGlobal(C.CBackendGlobalId(base.data.text)) end
        if cls == Mem.MemBaseProjection then
            local b = base_atom(ctx, base.base)
            local zero = C.CBackendAtomLiteral(C.CBackendIndex, Core.LitInt("0"))
            local dst = tmp(ctx, "base_projection", Code.CodeTyDataPtr(nil))
            assign(ctx, dst, C.CBackendRPtrOffset(b, zero, 1, base.byte_offset or 0))
            return C.CBackendAtomLocal(dst)
        end
        error("lower_to_c: unsupported KernelStream base " .. class_name(base), 3)
    end

    local function address_index_atom(ctx, index_expr)
        local idx, ity = lower_value_expr(ctx, index_expr)
        idx = cast_to(ctx, idx, ity, Code.CodeTyIndex, "index_cast")
        return idx
    end

    local function place_for_stream(ctx, stream, want_write, index_expr)
        local access = first_access(ctx, stream, want_write)
        local elem_size = 1
        local const_offset = 0
        local icls = access and pvm.classof(access.index) or nil
        if icls == Mem.MemIndexValue or icls == Mem.MemIndexInduction then
            elem_size = access.index.elem_size or 1
            const_offset = access.index.const_offset or 0
        end
        local base = base_atom(ctx, stream.base)
        local idx = address_index_atom(ctx, index_expr)
        local base_place = C.CBackendPlaceDeref(base, c_ty(ctx, stream.elem_ty), nil)
        if const_offset ~= 0 then
            local ptr = tmp(ctx, "ptr_offset", Code.CodeTyDataPtr(stream.elem_ty))
            assign(ctx, ptr, C.CBackendRPtrOffset(base, idx, elem_size, const_offset))
            return C.CBackendPlaceDeref(C.CBackendAtomLocal(ptr), c_ty(ctx, stream.elem_ty), nil)
        end
        return C.CBackendPlaceIndex(base_place, idx, c_ty(ctx, stream.elem_ty), elem_size)
    end

    local function kernel_value_atom(ctx, kid)
        local mapped = ctx.kernel_value_local[kid.text]
        if mapped ~= nil then return C.CBackendAtomLocal(mapped), ctx.kernel_value_types[kid.text] end
        return C.CBackendAtomLocal(C.CBackendLocalId(sanitize(kid.text))), ctx.kernel_value_types[kid.text]
    end

    local lower_kernel_expr
    lower_kernel_expr = function(ctx, expr)
        local cls = pvm.classof(expr)
        if cls == Kernel.KernelExprValue then return atom(expr.value), value_ty(ctx, expr.value) end
        if cls == Kernel.KernelExprKernelValue then return kernel_value_atom(ctx, expr.value) end
        if cls == Kernel.KernelExprAlgebra then return lower_value_expr(ctx, expr.expr) end
        if cls == Kernel.KernelExprLoad then
            local dst = tmp(ctx, "load", expr.stream.elem_ty)
            local place = place_for_stream(ctx, expr.stream, false, expr.index)
            ctx.stmts[#ctx.stmts + 1] = C.CBackendPlaceLoad(dst, place)
            return C.CBackendAtomLocal(dst), expr.stream.elem_ty
        end
        error("lower_to_c: unsupported KernelExpr " .. class_name(expr), 3)
    end

    local function bind_kernel_value(ctx, binding)
        local dst = ctx.kernel_value_local[binding.id.text]
        if dst == nil then
            dst = C.CBackendLocalId(sanitize(binding.id.text))
            ctx.kernel_value_local[binding.id.text] = dst
            add_local(ctx, dst, binding.ty)
        end
        local src, sty = lower_kernel_expr(ctx, binding.expr)
        src = cast_to(ctx, src, sty, binding.ty, "kernel_bind_cast")
        assign(ctx, dst, C.CBackendRAtom(src))
        ctx.kernel_value_types[binding.id.text] = binding.ty
    end

    local function emit_kernel_effect(ctx, effect)
        local cls = pvm.classof(effect)
        if cls == Kernel.KernelEffectStore then
            local value, vty = lower_kernel_expr(ctx, effect.value)
            value = cast_to(ctx, value, vty, effect.dst.elem_ty, "store_cast")
            local place = place_for_stream(ctx, effect.dst, true, effect.index)
            ctx.stmts[#ctx.stmts + 1] = C.CBackendPlaceStore(place, value)
        elseif cls == Kernel.KernelEffectFold then
            return
        else
            error("lower_to_c: unsupported KernelEffect " .. class_name(effect), 3)
        end
    end

    local function term_to_c(ctx, term)
        local k = term.kind
        local cls = pvm.classof(k)
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
        error("lower_to_c: unsupported CodeTermKind " .. class_name(k), 2)
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

    local function schedule_by_id(schedules)
        local out = {}
        for _, s in ipairs(schedules and schedules.schedules or {}) do if pvm.classof(s) == Schedule.SchedulePlanned then out[s.id.text] = s end end
        return out
    end

    local function edge_args(ctx, edge_fact)
        local args = {}
        for _, arg in ipairs(edge_fact and edge_fact.args or {}) do args[#args + 1] = atom(arg.src) end
        return args
    end

    local function code_block_by_id(func)
        local out = {}; for _, b in ipairs(func.blocks or {}) do out[b.id.text] = b end; return out
    end

    local function c_block_params(ctx, code_block)
        local params = {}
        for i, p in ipairs(code_block.params or {}) do params[i] = C.CBackendBlockParam(cid(p.value), c_ty(ctx, p.ty)) end
        return params
    end

    local semantic_fragment_prelude

    local function emit_closed_form_fragment(ctx, graph, flow, kernels, fragment)
        local kplan = kernel_by_id(kernels)[fragment.strategy.kernel.text]
        if kplan == nil then error("lower_to_c: closed-form strategy references missing kernel " .. fragment.strategy.kernel.text, 2) end
        local loop = graph_loop_by_id(graph)[kplan.subject.loop.text]
        if loop == nil or #(loop.exits or {}) ~= 1 then error("lower_to_c: closed-form fragment requires one loop exit", 2) end
        local exit = loop.exits[1]
        local edge_facts = edge_fact_by_key(flow)
        local jump_dest = exit.to.block
        local jump_fact = edge_facts[exit.from.block.text .. "\0" .. exit.to.block.text]
        for _, block in ipairs(ctx.code_func.blocks or {}) do
            if block.id == exit.to.block and pvm.classof(block.term.kind) == Code.CodeTermJump then
                jump_dest = block.term.kind.dest
                jump_fact = edge_facts[block.id.text .. "\0" .. block.term.kind.dest.text] or jump_fact
            end
        end
        ctx.stmts = { C.CBackendComment("semantic closed-form " .. tostring(fragment.strategy.fact.id and fragment.strategy.fact.id.text or fragment.id.text)) }
        if semantic_fragment_prelude ~= nil then semantic_fragment_prelude(ctx, graph, fragment, loop.header.block) end
        local result = lower_value_expr(ctx, fragment.strategy.fact.expr)
        local args = {}
        for i, arg in ipairs(jump_fact and jump_fact.args or {}) do
            args[i] = (arg.src == fragment.strategy.fact.reduction.accumulator) and result or atom(arg.src)
        end
        local header = ctx.block_by_id[loop.header.block.text]
        ctx.blocks[#ctx.blocks + 1] = C.CBackendBlock(clabel(loop.header.block), c_block_params(ctx, header), ctx.stmts, C.CBackendGoto(clabel(jump_dest), args))
    end

    local function loop_partition(ctx, graph, flow, kplan)
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

    local function place_bindings_effects(ctx, kplan)
        local bindings_by_block, effects_by_block = {}, {}
        for _, binding in ipairs(kplan.body.bindings or {}) do
            local block = ctx.kernel_value_block[binding.id.text]
            if block ~= nil then bindings_by_block[block.text] = bindings_by_block[block.text] or {}; bindings_by_block[block.text][#bindings_by_block[block.text] + 1] = binding end
        end
        for _, effect in ipairs(kplan.body.effects or {}) do
            if pvm.classof(effect) == Kernel.KernelEffectStore then
                local access = first_access(ctx, effect.dst, true)
                local block = access and access.block and access.block.block
                if block ~= nil then effects_by_block[block.text] = effects_by_block[block.text] or {}; effects_by_block[block.text][#effects_by_block[block.text] + 1] = effect end
            elseif pvm.classof(effect) ~= Kernel.KernelEffectFold then
                error("lower_to_c: unsupported KernelEffect in planned kernel", 2)
            end
        end
        return bindings_by_block, effects_by_block
    end

    local function emit_scalar_kernel_fragment(ctx, graph, flow, kernels, fragment)
        local kplan = kernel_by_id(kernels)[fragment.strategy.kernel.text]
        if kplan == nil then error("lower_to_c: kernel strategy references missing kernel " .. fragment.strategy.kernel.text, 2) end
        local loop, body_set, edge_facts, exit_edge, latch_edge, body_successor, cond = loop_partition(ctx, graph, flow, kplan)
        local bindings_by_block, effects_by_block = place_bindings_effects(ctx, kplan)
        local header_block = ctx.block_by_id[loop.header.block.text]
        ctx.stmts = { C.CBackendComment("semantic scalar kernel " .. kplan.id.text) }
        if semantic_fragment_prelude ~= nil then semantic_fragment_prelude(ctx, graph, fragment, loop.header.block) end
        for _, b in ipairs(bindings_by_block[loop.header.block.text] or {}) do bind_kernel_value(ctx, b) end
        ctx.blocks[#ctx.blocks + 1] = C.CBackendBlock(clabel(loop.header.block), c_block_params(ctx, header_block), ctx.stmts,
            C.CBackendIfGoto(atom(cond), clabel(exit_edge.to.block), edge_args(ctx, edge_facts[exit_edge.from.block.text .. "\0" .. exit_edge.to.block.text]), clabel(body_successor), edge_args(ctx, edge_facts[exit_edge.from.block.text .. "\0" .. body_successor.text])))
        for _, block in ipairs(ctx.code_func.blocks or {}) do
            if body_set[block.id.text] and block.id ~= loop.header.block then
                ctx.stmts = { C.CBackendComment("semantic scalar kernel body " .. kplan.id.text) }
                if semantic_fragment_prelude ~= nil then semantic_fragment_prelude(ctx, graph, fragment, block.id) end
                for _, b in ipairs(bindings_by_block[block.id.text] or {}) do bind_kernel_value(ctx, b) end
                for _, e in ipairs(effects_by_block[block.id.text] or {}) do emit_kernel_effect(ctx, e) end
                local term
                if block.id == latch_edge.from.block then
                    term = C.CBackendGoto(clabel(loop.header.block), edge_args(ctx, edge_facts[latch_edge.from.block.text .. "\0" .. latch_edge.to.block.text]))
                else
                    local next_edge = nil
                    for _, fg in ipairs(graph.funcs or {}) do if fg.func == loop.func then for _, edge in ipairs(fg.edges or {}) do if edge.from.block == block.id and body_set[edge.to.block.text] then next_edge = edge end end end end
                    if next_edge == nil then error("lower_to_c: scalar kernel body block has no in-loop successor", 2) end
                    term = C.CBackendGoto(clabel(next_edge.to.block), edge_args(ctx, edge_facts[next_edge.from.block.text .. "\0" .. next_edge.to.block.text]))
                end
                ctx.blocks[#ctx.blocks + 1] = C.CBackendBlock(clabel(block.id), c_block_params(ctx, block), ctx.stmts, term)
            end
        end
    end

    local function value_expr_add_lane(ctx, expr, lane, ty)
        if lane == 0 then return expr end
        return Value.ValueExprAdd(expr, Value.ValueExprConst(Code.CodeConstLiteral(ty, Core.LitInt(tostring(lane)))), ty, Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZero, Code.CodeShiftMaskCount))
    end

    local function vector_lane_place(ctx, stream, want_write, lane, counter_ty)
        local idx = atom(ctx.vector_counter)
        if lane ~= 0 then
            local dst = tmp(ctx, "vec_lane_index", counter_ty)
            ctx.stmts[#ctx.stmts + 1] = C.CBackendHelperCall(dst, binary_helper(ctx, Core.BinAdd, counter_ty, nil), { atom(ctx.vector_counter), C.CBackendAtomLiteral(c_ty(ctx, counter_ty), Core.LitInt(tostring(lane))) })
            idx = C.CBackendAtomLocal(dst)
        end
        local access = first_access(ctx, stream, want_write)
        local elem_size = 1
        local const_offset = 0
        local icls = access and pvm.classof(access.index) or nil
        if icls == Mem.MemIndexValue or icls == Mem.MemIndexInduction then
            elem_size = access.index.elem_size or 1
            const_offset = access.index.const_offset or 0
        end
        local base = base_atom(ctx, stream.base)
        if const_offset ~= 0 then
            local ptr = tmp(ctx, "vec_lane_ptr", Code.CodeTyDataPtr(stream.elem_ty))
            assign(ctx, ptr, C.CBackendRPtrOffset(base, idx, elem_size, const_offset))
            return C.CBackendPlaceDeref(C.CBackendAtomLocal(ptr), c_ty(ctx, stream.elem_ty), nil)
        end
        return C.CBackendPlaceIndex(C.CBackendPlaceDeref(base, c_ty(ctx, stream.elem_ty), nil), idx, c_ty(ctx, stream.elem_ty), elem_size)
    end

    local lower_value_expr_lane, lower_kernel_expr_lane

    lower_value_expr_lane = function(ctx, expr, lane, index_ty)
        local cls = pvm.classof(expr)
        if cls == Value.ValueExprValue then
            local cached = ctx.lane_value_by_code and ctx.lane_value_by_code[expr.value.text]
            if cached ~= nil then return cached.atom, cached.ty end
            return lower_value_expr(ctx, expr)
        elseif cls == Value.ValueExprConst then
            return const_atom(ctx, expr.const)
        elseif cls == Value.ValueExprAdd or cls == Value.ValueExprSub or cls == Value.ValueExprMul or cls == Value.ValueExprDiv then
            local a, aty = lower_value_expr_lane(ctx, expr.a, lane, index_ty)
            local b, bty = lower_value_expr_lane(ctx, expr.b, lane, index_ty)
            a = cast_to(ctx, a, aty, expr.ty, "vec_bin_lhs")
            b = cast_to(ctx, b, bty, expr.ty, "vec_bin_rhs")
            local dst = tmp(ctx, "vec_bin", expr.ty)
            local op = (cls == Value.ValueExprAdd and Core.BinAdd) or (cls == Value.ValueExprSub and Core.BinSub) or (cls == Value.ValueExprMul and Core.BinMul) or Core.BinDiv
            ctx.stmts[#ctx.stmts + 1] = C.CBackendHelperCall(dst, binary_helper(ctx, op, expr.ty, expr.sem), { a, b })
            return C.CBackendAtomLocal(dst), expr.ty
        elseif cls == Value.ValueExprCmp then
            local a, aty = lower_value_expr_lane(ctx, expr.a, lane, index_ty)
            local b, bty = lower_value_expr_lane(ctx, expr.b, lane, index_ty)
            a = cast_to(ctx, a, aty, expr.ty, "vec_cmp_lhs")
            b = cast_to(ctx, b, bty, expr.ty, "vec_cmp_rhs")
            local dst = tmp(ctx, "vec_cmp", Code.CodeTyBool8)
            assign(ctx, dst, C.CBackendRCompare(expr.op, c_ty(ctx, expr.ty), a, b))
            return C.CBackendAtomLocal(dst), Code.CodeTyBool8
        elseif cls == Value.ValueExprSelect then
            local cnd = lower_value_expr_lane(ctx, expr.cond, lane, index_ty)
            local t, tty = lower_value_expr_lane(ctx, expr.t, lane, index_ty)
            local f, fty = lower_value_expr_lane(ctx, expr.f, lane, index_ty)
            local ty = tty or fty
            t = cast_to(ctx, t, tty, ty, "vec_sel_t")
            f = cast_to(ctx, f, fty, ty, "vec_sel_f")
            local dst = tmp(ctx, "vec_select", ty)
            assign(ctx, dst, C.CBackendRSelect(c_ty(ctx, ty), cnd, t, f))
            return C.CBackendAtomLocal(dst), ty
        elseif cls == Value.ValueExprAffine then
            local ty = expr.affine.ty
            local acc, acc_ty = nil, nil
            if expr.affine.constant ~= "0" then acc, acc_ty = const_atom(ctx, Code.CodeConstLiteral(ty, Core.LitInt(expr.affine.constant))) end
            for _, term in ipairs(expr.affine.terms or {}) do
                local tv, tty = lower_value_expr_lane(ctx, Value.ValueExprValue(term.value), lane, index_ty)
                tv = cast_to(ctx, tv, tty, ty, "vec_affine_cast")
                if term.coeff ~= "1" then
                    local cv = C.CBackendAtomLiteral(c_ty(ctx, ty), Core.LitInt(term.coeff))
                    local mul = tmp(ctx, "vec_affine_mul", ty)
                    ctx.stmts[#ctx.stmts + 1] = C.CBackendHelperCall(mul, binary_helper(ctx, Core.BinMul, ty, expr.affine.sem), { tv, cv })
                    tv = C.CBackendAtomLocal(mul)
                end
                if acc == nil then acc, acc_ty = tv, ty else
                    local sum = tmp(ctx, "vec_affine_add", ty)
                    ctx.stmts[#ctx.stmts + 1] = C.CBackendHelperCall(sum, binary_helper(ctx, Core.BinAdd, ty, expr.affine.sem), { acc, tv })
                    acc, acc_ty = C.CBackendAtomLocal(sum), ty
                end
            end
            if acc == nil then return C.CBackendAtomLiteral(c_ty(ctx, ty), Core.LitInt("0")), ty end
            return acc, acc_ty
        end
        return lower_value_expr(ctx, expr)
    end

    lower_kernel_expr_lane = function(ctx, expr, lane, index_ty)
        local cls = pvm.classof(expr)
        if cls == Kernel.KernelExprValue then
            local cached = ctx.lane_value_by_code and ctx.lane_value_by_code[expr.value.text]
            if cached ~= nil then return cached.atom, cached.ty end
            return atom(expr.value), value_ty(ctx, expr.value)
        elseif cls == Kernel.KernelExprKernelValue then
            local cached = ctx.lane_value_by_kernel and ctx.lane_value_by_kernel[expr.value.text]
            if cached ~= nil then return cached.atom, cached.ty end
            local binding = ctx.kernel_binding_by_id[expr.value.text]
            if binding == nil then return kernel_value_atom(ctx, expr.value) end
            local v, ty = lower_kernel_expr_lane(ctx, binding.expr, lane, index_ty)
            ctx.lane_value_by_kernel[expr.value.text] = { atom = v, ty = ty }
            local code_id = ctx.kernel_value_code_id and ctx.kernel_value_code_id[expr.value.text]
            if code_id ~= nil then ctx.lane_value_by_code[code_id.text] = { atom = v, ty = ty } end
            return v, ty
        elseif cls == Kernel.KernelExprAlgebra then
            return lower_value_expr_lane(ctx, expr.expr, lane, index_ty)
        elseif cls == Kernel.KernelExprLoad then
            local dst = tmp(ctx, "vec_lane_load", expr.stream.elem_ty)
            local place = vector_lane_place(ctx, expr.stream, false, lane, index_ty)
            ctx.stmts[#ctx.stmts + 1] = C.CBackendPlaceLoad(dst, place)
            return C.CBackendAtomLocal(dst), expr.stream.elem_ty
        end
        error("lower_to_c: unsupported vector KernelExpr " .. class_name(expr), 3)
    end

    local function emit_vector_lane_effect(ctx, effect, lane, index_ty)
        if pvm.classof(effect) ~= Kernel.KernelEffectStore then return end
        ctx.lane_value_by_code = {}
        ctx.lane_value_by_kernel = {}
        for _, binding in ipairs(ctx.current_kernel_bindings or {}) do
            lower_kernel_expr_lane(ctx, Kernel.KernelExprKernelValue(binding.id), lane, index_ty)
        end
        local value, vty = lower_kernel_expr_lane(ctx, effect.value, lane, index_ty)
        value = cast_to(ctx, value, vty, effect.dst.elem_ty, "vec_store_cast")
        local place = vector_lane_place(ctx, effect.dst, true, lane, index_ty)
        ctx.stmts[#ctx.stmts + 1] = C.CBackendPlaceStore(place, value)
    end

    local function emit_vector_kernel_fragment(ctx, graph, flow, kernels, schedules, fragment)
        local kplan = kernel_by_id(kernels)[fragment.strategy.kernel.text]
        local sched = schedule_by_id(schedules)[fragment.strategy.schedule.text]
        if kplan == nil or sched == nil or pvm.classof(sched.kind) ~= Schedule.ScheduleVector then error("lower_to_c: vector kernel strategy requires ScheduleVector", 2) end
        local lane_shape = sched.kind.lanes
        if pvm.classof(lane_shape) ~= Schedule.LaneVector then error("lower_to_c: vector schedule requires LaneVector", 2) end
        local lanes = lane_shape.lanes
        local loop, body_set, edge_facts, exit_edge, latch_edge, body_successor, scalar_cond, loop_fact = loop_partition(ctx, graph, flow, kplan)
        if loop_fact == nil or loop_fact.counted == nil or kplan.body.domain.counter == nil then error("lower_to_c: vector kernel requires counted loop", 2) end
        ctx.current_kernel_bindings = kplan.body.bindings or {}
        for _, binding in ipairs(kplan.body.bindings or {}) do ctx.kernel_binding_by_id[binding.id.text] = binding end
        local counter = kplan.body.domain.counter
        ctx.vector_counter = counter
        local counter_ty = value_ty(ctx, counter) or Code.CodeTyIndex
        local vector_label = C.CBackendLabel(clabel(loop.header.block).text .. "_semantic_vector")
        local tail_label = C.CBackendLabel(clabel(loop.header.block).text .. "_semantic_tail")
        local next_i = C.CBackendLocalId("semantic_vec_next_i_" .. sanitize(loop.id.text))
        add_local(ctx, next_i, counter_ty)
        local ok = C.CBackendLocalId("semantic_vec_ok_" .. sanitize(loop.id.text))
        add_local(ctx, ok, Code.CodeTyBool8)

        ctx.stmts = { C.CBackendComment("semantic vector kernel dispatch " .. kplan.id.text) }
        if semantic_fragment_prelude ~= nil then semantic_fragment_prelude(ctx, graph, fragment, loop.header.block) end
        for _, binding in ipairs(kplan.body.bindings or {}) do
            local block = ctx.kernel_value_block and ctx.kernel_value_block[binding.id.text]
            if block == loop.header.block then bind_kernel_value(ctx, binding) end
        end
        local lane_atom = C.CBackendAtomLiteral(c_ty(ctx, counter_ty), Core.LitInt(tostring(lanes)))
        ctx.stmts[#ctx.stmts + 1] = C.CBackendHelperCall(next_i, binary_helper(ctx, Core.BinAdd, counter_ty, nil), { atom(counter), lane_atom })
        local stop = atom(loop_fact.counted.stop)
        ctx.stmts[#ctx.stmts + 1] = C.CBackendAssign(ok, C.CBackendRCompare(Core.CmpLe, c_ty(ctx, counter_ty), C.CBackendAtomLocal(next_i), stop))
        ctx.blocks[#ctx.blocks + 1] = C.CBackendBlock(clabel(loop.header.block), c_block_params(ctx, ctx.block_by_id[loop.header.block.text]), ctx.stmts,
            C.CBackendIfGoto(C.CBackendAtomLocal(ok), vector_label, {}, tail_label, {}))

        ctx.stmts = { C.CBackendComment("semantic vector main loop lanes=" .. tostring(lanes)) }
        for _, effect in ipairs(kplan.body.effects or {}) do for lane = 0, lanes - 1 do emit_vector_lane_effect(ctx, effect, lane, counter_ty) end end
        local latch_fact = edge_facts[latch_edge.from.block.text .. "\0" .. latch_edge.to.block.text]
        local jump_args = {}
        for _, arg in ipairs(latch_fact and latch_fact.args or {}) do jump_args[#jump_args + 1] = (arg.dst_param == counter) and C.CBackendAtomLocal(next_i) or atom(arg.dst_param) end
        ctx.blocks[#ctx.blocks + 1] = C.CBackendBlock(vector_label, {}, ctx.stmts, C.CBackendGoto(clabel(loop.header.block), jump_args))

        ctx.stmts = { C.CBackendComment("semantic vector scalar tail") }
        ctx.blocks[#ctx.blocks + 1] = C.CBackendBlock(tail_label, {}, ctx.stmts,
            C.CBackendIfGoto(atom(scalar_cond), clabel(exit_edge.to.block), edge_args(ctx, edge_facts[exit_edge.from.block.text .. "\0" .. exit_edge.to.block.text]), clabel(body_successor), edge_args(ctx, edge_facts[exit_edge.from.block.text .. "\0" .. body_successor.text])))

        local bindings_by_block, effects_by_block = place_bindings_effects(ctx, kplan)
        for _, block in ipairs(ctx.code_func.blocks or {}) do
            if body_set[block.id.text] and block.id ~= loop.header.block then
                ctx.stmts = { C.CBackendComment("semantic vector scalar-tail body " .. kplan.id.text) }
                if semantic_fragment_prelude ~= nil then semantic_fragment_prelude(ctx, graph, fragment, block.id) end
                for _, b in ipairs(bindings_by_block[block.id.text] or {}) do bind_kernel_value(ctx, b) end
                for _, e in ipairs(effects_by_block[block.id.text] or {}) do emit_kernel_effect(ctx, e) end
                local term
                if block.id == latch_edge.from.block then
                    term = C.CBackendGoto(clabel(loop.header.block), edge_args(ctx, latch_fact))
                else
                    local next_edge = nil
                    for _, fg in ipairs(graph.funcs or {}) do if fg.func == loop.func then for _, edge in ipairs(fg.edges or {}) do if edge.from.block == block.id and body_set[edge.to.block.text] then next_edge = edge end end end end
                    if next_edge == nil then error("lower_to_c: vector tail body block has no in-loop successor", 2) end
                    term = C.CBackendGoto(clabel(next_edge.to.block), edge_args(ctx, edge_facts[next_edge.from.block.text .. "\0" .. next_edge.to.block.text]))
                end
                ctx.blocks[#ctx.blocks + 1] = C.CBackendBlock(clabel(block.id), c_block_params(ctx, block), ctx.stmts, term)
            end
        end
    end

    local function cover_blocks(fragment, func, graph_loops)
        local cover = fragment.cover
        local cls = pvm.classof(cover)
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

    semantic_fragment_prelude = function(ctx, graph, fragment, only_block)
        local _, covered = cover_blocks(fragment, ctx.code_func, graph_loop_by_id(graph))
        local aliases = {}
        local components = {}
        local emitted = {}

        local function ref(id, ty)
            return { atom = atom(id), ty = ty or value_ty(ctx, id) }
        end
        local function emit_assign_once(dst, src)
            if dst == nil or src == nil or emitted[dst.text] then return end
            emitted[dst.text] = true
            note_value(ctx, dst, src.ty)
            ctx.stmts[#ctx.stmts + 1] = C.CBackendAssign(cid(dst), C.CBackendRAtom(src.atom))
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
            note_value(ctx, dst, ty)
            local vty = view_type(ctx, view)
            if vty == nil then error("lower_to_c: semantic view projection references unknown view " .. tostring(view.text), 3) end
            ctx.stmts[#ctx.stmts + 1] = C.CBackendPlaceLoad(cid(dst), C.CBackendPlaceField(C.CBackendPlaceLocal(cid(view), c_ty(ctx, vty)), C.CBackendName(field), c_ty(ctx, ty), 0, nil, nil))
        end

        for _, block in ipairs(ctx.code_func.blocks or {}) do
            if covered[block.id.text] then
                for _, inst in ipairs(block.insts or {}) do
                    local k = inst.kind
                    local cls = pvm.classof(k)
                    if cls == Code.CodeInstViewMake then
                        local vty = Code.CodeTyView(k.elem_ty)
                        note_value(ctx, k.dst, vty)
                        components[k.dst.text] = {
                            data = ref(k.data, Code.CodeTyDataPtr(k.elem_ty)),
                            len = ref(k.len, Code.CodeTyIndex),
                            stride = ref(k.stride, Code.CodeTyIndex),
                        }
                    elseif cls == Code.CodeInstAlias and pvm.classof(value_ty(ctx, k.dst)) == Code.CodeTyView then
                        local src = resolve_view(k.src)
                        if src ~= nil then aliases[k.dst.text] = src end
                        if src ~= nil and components[src.text] ~= nil then components[k.dst.text] = components[src.text] end
                    end
                end
            end
        end

        for _, block in ipairs(ctx.code_func.blocks or {}) do
            if covered[block.id.text] and (only_block == nil or only_block == block.id) then
                for _, inst in ipairs(block.insts or {}) do
                    local k = inst.kind
                    local cls = pvm.classof(k)
                    if cls == Code.CodeInstViewData then
                        local src = component(k.view, "data")
                        if src ~= nil then emit_assign_once(k.dst, src)
                        else emit_field_load(k.dst, resolve_view(k.view), "data", view_data_type(ctx, k.view)) end
                    elseif cls == Code.CodeInstViewLen then
                        local src = component(k.view, "len")
                        if src ~= nil then emit_assign_once(k.dst, src)
                        else emit_field_load(k.dst, resolve_view(k.view), "len", Code.CodeTyIndex) end
                    elseif cls == Code.CodeInstViewStride then
                        local src = component(k.view, "stride")
                        if src ~= nil then emit_assign_once(k.dst, src)
                        else emit_field_load(k.dst, resolve_view(k.view), "stride", Code.CodeTyIndex) end
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
        local cls = pvm.classof(fragment.strategy)
        return cls == Lower.LowerStrategyKernel or cls == Lower.LowerStrategyClosedForm
    end

    local function prepare_func_ctx(ctx, code_func, c_func)
        ctx.code_func = code_func
        ctx.func = c_func
        ctx.blocks = {}
        ctx.block_by_id = code_block_by_id(code_func)
        ctx.value_types = {}
        ctx.kernel_value_local = {}
        ctx.kernel_value_types = {}
        ctx.kernel_value_block = {}
        ctx.kernel_value_code_id = {}
        ctx.kernel_binding_by_id = {}
        ctx.const_by_value = {}
        ctx.local_seen = {}
        for _, p in ipairs(c_func.params or {}) do ctx.local_seen[p.id.text] = true end
        for _, l in ipairs(c_func.locals or {}) do ctx.local_seen[l.id.text] = true end
        local function note_inst_dst(block, k)
            local cls = pvm.classof(k)
            local dst, ty = nil, nil
            if cls == Code.CodeInstConst then dst, ty = k.dst, k.const.ty; ctx.const_by_value[k.dst.text] = k.const
            elseif cls == Code.CodeInstAlias or cls == Code.CodeInstUnary or cls == Code.CodeInstBinary or cls == Code.CodeInstFloatBinary or cls == Code.CodeInstSelect then dst, ty = k.dst, k.ty
            elseif cls == Code.CodeInstCompare then dst, ty = k.dst, Code.CodeTyBool8
            elseif cls == Code.CodeInstCast then dst, ty = k.dst, k.to
            elseif cls == Code.CodeInstAddrOf or cls == Code.CodeInstGlobalRef or cls == Code.CodeInstPtrOffset then dst, ty = k.dst, k.ptr_ty
            elseif cls == Code.CodeInstLoad or cls == Code.CodeInstAtomicLoad or cls == Code.CodeInstAtomicRmw then dst, ty = k.dst, k.access.ty
            elseif cls == Code.CodeInstViewMake then dst, ty = k.dst, Code.CodeTyView(k.elem_ty)
            elseif cls == Code.CodeInstViewData then dst, ty = k.dst, Code.CodeTyDataPtr(nil)
            elseif cls == Code.CodeInstViewLen or cls == Code.CodeInstViewStride then dst, ty = k.dst, Code.CodeTyIndex
            elseif cls == Code.CodeInstCall then dst = k.dst end
            if dst ~= nil and ty ~= nil then
                note_value(ctx, dst, ty)
                local kid = Kernel.KernelValueId("kval:" .. dst.text)
                ctx.kernel_value_local[kid.text] = cid(dst)
                ctx.kernel_value_types[kid.text] = ty
                ctx.kernel_value_block[kid.text] = block.id
                ctx.kernel_value_code_id[kid.text] = dst
            end
        end
        for _, param in ipairs(code_func.params or {}) do note_value(ctx, param.value, param.ty) end
        for _, b in ipairs(code_func.blocks or {}) do
            for _, param in ipairs(b.params or {}) do note_value(ctx, param.value, param.ty) end
            for _, inst in ipairs(b.insts or {}) do note_inst_dst(b, inst.kind) end
        end
    end

    local function lower_semantic_func(ctx, graph, flow, kernels, schedules, code_func, c_func, func_plan, graph_loops, baseline_blocks)
        local mutable_func = {
            name = c_func.name,
            symbol = c_func.symbol,
            visibility = c_func.visibility,
            sig = c_func.sig,
            params = c_func.params,
            locals = {},
        }
        for i, l in ipairs(c_func.locals or {}) do mutable_func.locals[i] = l end
        prepare_func_ctx(ctx, code_func, mutable_func)
        local baseline_by_label = {}; for _, b in ipairs(baseline_blocks or {}) do baseline_by_label[b.label.text] = b end
        local schedules_by_id = schedule_by_id(schedules)
        for _, fragment in ipairs(ordered_fragments_for_func(code_func, func_plan, graph_loops)) do
            local cls = pvm.classof(fragment.strategy)
            if cls == Lower.LowerStrategyCode then
                for _, b in ipairs(cover_blocks(fragment, code_func, graph_loops)) do ctx.blocks[#ctx.blocks + 1] = baseline_by_label[clabel(b.id).text] end
            elseif cls == Lower.LowerStrategyClosedForm then
                emit_closed_form_fragment(ctx, graph, flow, kernels, fragment)
            elseif cls == Lower.LowerStrategyKernel then
                local sched = schedules_by_id[fragment.strategy.schedule.text]
                if sched == nil then error("lower_to_c: kernel strategy references missing schedule " .. fragment.strategy.schedule.text, 2) end
                if pvm.classof(sched.kind) == Schedule.ScheduleVector then emit_vector_kernel_fragment(ctx, graph, flow, kernels, schedules, fragment)
                else emit_scalar_kernel_fragment(ctx, graph, flow, kernels, fragment) end
            else
                error("lower_to_c: unsupported LowerStrategy for C emission " .. class_name(fragment.strategy), 2)
            end
        end
        return C.CBackendFunc(mutable_func.name, mutable_func.symbol, mutable_func.visibility, mutable_func.sig, mutable_func.params, mutable_func.locals, ctx.blocks)
    end

    local function func_by_id(code_module)
        local out = {}; for _, f in ipairs(code_module.funcs or {}) do out[f.id.text] = f end; return out
    end

    local function graph_indexes(graph)
        local loops = {}
        for _, fg in ipairs(graph and graph.funcs or {}) do for _, loop in ipairs(fg.loops or {}) do loops[loop.id.text] = loop end end
        return loops
    end

    local function normalize_args(code_module, lower_module, opts)
        opts = opts or {}
        if lower_module ~= nil and pvm.classof(lower_module) == Lower.LowerModule then
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
        local ctx = {
            unit = unit,
            type_ctx = make_type_ctx(code_module),
            helper_by_key = {},
            next_helper = 0,
            next_tmp = 0,
            mem = mem,
            mem_access_by_id = {},
            mem_backend_by_access = {},
        }
        for _, h in ipairs(unit.helpers or {}) do ctx.helper_by_key[helper_key(h.kind)] = h end
        for _, access in ipairs(mem and mem.accesses or {}) do ctx.mem_access_by_id[access.id.text] = access end
        for _, info in ipairs(mem and mem.backend_info or {}) do ctx.mem_backend_by_access[info.access.text] = info end

        for _, code_func in ipairs(code_module.funcs or {}) do
            local fp = plans[code_func.id.text]
            local base = base_func_by_name[code_func.name]
            if fp ~= nil then
                local semantic = false
                for _, frag in ipairs(fp.fragments or {}) do if semantic_strategy(frag) then semantic = true end end
                if semantic then cfuncs[#cfuncs + 1] = lower_semantic_func(ctx, graph, flow, kernels, schedules, code_func, base, fp, graph_loops, base.blocks)
                else cfuncs[#cfuncs + 1] = base end
            else
                cfuncs[#cfuncs + 1] = base
            end
        end
        return C.CBackendUnit(unit.module_name, unit.target, unit.sigs, unit.types, unit.globals, unit.externs, unit.helpers, cfuncs)
    end

    api.module = module
    api.unit = module

    T._moonlift_api_cache.lower_to_c = api
    return api
end

return M
