local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local C = T.Moon2Core
    local Ty = T.Moon2Type
    local B = T.Moon2Bind
    local Tr = T.Moon2Tree
    local V = T.Moon2Vec
    local Back = T.Moon2Back

    local expr_type_api = require("moonlift.tree_expr_type").Define(T)
    local scalar_api = require("moonlift.type_to_back_scalar").Define(T)
    local layout_api = require("moonlift.type_size_align").Define(T)
    local facts_api = require("moonlift.vec_loop_facts").Define(T)
    local safety_api = require("moonlift.vec_kernel_safety").Define(T)
    local abi_api = require("moonlift.type_func_abi_plan").Define(T)

    local function loop_id(region_id) return V.VecLoopId(region_id) end
    local function reject(region_id, reason) return V.VecKernelNoPlan({ V.VecRejectUnsupportedLoop(loop_id(region_id or "unknown"), reason) }) end

    local function same_binding_slot(a, b)
        if a == b then return true end
        if a == nil or b == nil or a.name ~= b.name then return false end
        local ca, cb = pvm.classof(a.class), pvm.classof(b.class)
        if ca == B.BindingClassArg and cb == B.BindingClassArg then return a.class.index == b.class.index end
        if ca == B.BindingClassEntryBlockParam and cb == B.BindingClassEntryBlockParam then return a.class.region_id == b.class.region_id and a.class.block_name == b.class.block_name and a.class.index == b.class.index end
        if ca == B.BindingClassBlockParam and cb == B.BindingClassBlockParam then return a.class.region_id == b.class.region_id and a.class.block_name == b.class.block_name and a.class.index == b.class.index end
        return false
    end

    local function ref_binding(expr)
        if pvm.classof(expr) == Tr.ExprRef and pvm.classof(expr.ref) == B.ValueRefBinding then return expr.ref.binding end
        return nil
    end

    local function same_ref(expr, binding)
        local b = ref_binding(expr)
        return b ~= nil and same_binding_slot(b, binding)
    end

    local function expr_ty(expr) return expr_type_api.type(expr) or Ty.TScalar(C.ScalarVoid) end

    local function back_scalar(ty)
        local result = scalar_api.result(ty)
        if pvm.classof(result) == Ty.TypeBackScalarKnown then return result.scalar end
        return nil
    end

    local function elem_size(ty)
        local result = layout_api.result(ty)
        if pvm.classof(result) == Ty.TypeMemLayoutKnown then return result.layout.size end
        return nil
    end

    local function elem_from_type(ty)
        local scalar = back_scalar(ty)
        if scalar == Back.BackI32 and elem_size(ty) == 4 then return V.VecElemI32 end
        if scalar == Back.BackU32 and elem_size(ty) == 4 then return V.VecElemU32 end
        if scalar == Back.BackI64 and elem_size(ty) == 8 then return V.VecElemI64 end
        if scalar == Back.BackU64 and elem_size(ty) == 8 then return V.VecElemU64 end
        return nil
    end

    local function elem_lanes(elem)
        if elem == V.VecElemI32 or elem == V.VecElemU32 then return 4 end
        if elem == V.VecElemI64 or elem == V.VecElemU64 then return 2 end
        return nil
    end

    local function elem_bits(elem)
        if elem == V.VecElemI32 or elem == V.VecElemU32 then return 32 end
        if elem == V.VecElemI64 or elem == V.VecElemU64 then return 64 end
        return nil
    end

    local function elem_shape(elem)
        local lanes = elem_lanes(elem)
        if lanes == nil then return nil end
        return V.VecVectorShape(elem, lanes)
    end

    local function target_for_elem(elem)
        local shape = elem_shape(elem)
        if shape == nil then return nil end
        local facts = {
            V.VecTargetVectorBits(elem_bits(elem) * shape.lanes),
            V.VecTargetSupportsShape(shape),
            V.VecTargetSupportsBinOp(shape, V.VecAdd),
            V.VecTargetSupportsBinOp(shape, V.VecSub),
            V.VecTargetSupportsBinOp(shape, V.VecBitAnd),
            V.VecTargetSupportsBinOp(shape, V.VecBitOr),
            V.VecTargetSupportsBinOp(shape, V.VecBitXor),
            V.VecTargetSupportsCmpOp(shape, V.VecCmpEq),
            V.VecTargetSupportsCmpOp(shape, V.VecCmpNe),
            V.VecTargetSupportsSelect(shape),
            V.VecTargetSupportsMaskOp(shape, V.VecMaskNot),
            V.VecTargetSupportsMaskOp(shape, V.VecMaskAnd),
            V.VecTargetSupportsMaskOp(shape, V.VecMaskOr),
        }
        if elem == V.VecElemI32 or elem == V.VecElemI64 then
            facts[#facts + 1] = V.VecTargetSupportsCmpOp(shape, V.VecCmpSLt)
            facts[#facts + 1] = V.VecTargetSupportsCmpOp(shape, V.VecCmpSLe)
            facts[#facts + 1] = V.VecTargetSupportsCmpOp(shape, V.VecCmpSGt)
            facts[#facts + 1] = V.VecTargetSupportsCmpOp(shape, V.VecCmpSGe)
        elseif elem == V.VecElemU32 or elem == V.VecElemU64 then
            facts[#facts + 1] = V.VecTargetSupportsCmpOp(shape, V.VecCmpULt)
            facts[#facts + 1] = V.VecTargetSupportsCmpOp(shape, V.VecCmpULe)
            facts[#facts + 1] = V.VecTargetSupportsCmpOp(shape, V.VecCmpUGt)
            facts[#facts + 1] = V.VecTargetSupportsCmpOp(shape, V.VecCmpUGe)
        end
        facts[#facts + 1] = V.VecTargetSupportsBinOp(shape, V.VecMul)
        return V.VecTargetModel(V.VecTargetCraneliftJit, facts)
    end

    local function target_supports_bin_op(target, shape, op)
        for i = 1, #target.facts do
            local fact = target.facts[i]
            if pvm.classof(fact) == V.VecTargetSupportsBinOp and fact.shape == shape and fact.op == op then return true end
        end
        return false
    end

    local function target_supports_cmp_op(target, shape, op)
        for i = 1, #target.facts do
            local fact = target.facts[i]
            if pvm.classof(fact) == V.VecTargetSupportsCmpOp and fact.shape == shape and fact.op == op then return true end
        end
        return false
    end

    local function target_supports_select(target, shape)
        for i = 1, #target.facts do
            local fact = target.facts[i]
            if pvm.classof(fact) == V.VecTargetSupportsSelect and fact.shape == shape then return true end
        end
        return false
    end

    local function target_supports_mask_op(target, shape, op)
        for i = 1, #target.facts do
            local fact = target.facts[i]
            if pvm.classof(fact) == V.VecTargetSupportsMaskOp and fact.shape == shape and fact.op == op then return true end
        end
        return false
    end

    local function literal_int_raw(expr)
        if pvm.classof(expr) == Tr.ExprLit and pvm.classof(expr.value) == C.LitInt then return expr.value.raw end
        return nil
    end

    local function alias_for_view(aliases, binding)
        for i = 1, #(aliases or {}) do if same_binding_slot(aliases[i].view, binding) then return aliases[i] end end
        return nil
    end

    local function resolve_view_data(aliases, binding)
        local alias = alias_for_view(aliases, binding)
        if alias ~= nil then return alias.data end
        return binding
    end

    local function resolve_view_len(aliases, binding)
        local alias = alias_for_view(aliases, binding)
        if alias ~= nil then return alias.len end
        return binding
    end

    local function offset_is_zero(offset)
        return offset == nil or offset == V.VecKernelOffsetZero
    end

    local function offset_add(a, b_expr)
        local b = V.VecKernelOffsetExpr(b_expr)
        if offset_is_zero(a) then return b end
        if literal_int_raw(b_expr) == "0" then return a end
        return V.VecKernelOffsetAdd(a, b)
    end

    local function binding_expr(binding)
        return Tr.ExprRef(Tr.ExprTyped(binding.ty), B.ValueRefBinding(binding))
    end

    local function scalar_alias_for_binding(scalars, binding)
        for i = 1, #(scalars or {}) do if same_binding_slot(scalars[i].binding, binding) then return scalars[i] end end
        return nil
    end

    local function len_value_for_binding(scalars, binding)
        local alias = scalar_alias_for_binding(scalars, binding)
        if alias ~= nil then return alias.value end
        return binding_expr(binding)
    end

    local function len_source_expr(source)
        local cls = pvm.classof(source)
        if cls == V.VecKernelLenBinding then return binding_expr(source.binding) end
        if cls == V.VecKernelLenView then return Tr.ExprLen(Tr.ExprTyped(Ty.TScalar(C.ScalarIndex)), binding_expr(source.view)) end
        if cls == V.VecKernelLenExpr then return source.expr end
        return Tr.ExprLit(Tr.ExprTyped(Ty.TScalar(C.ScalarIndex)), C.LitInt("0"))
    end

    local function default_len_source(binding)
        if pvm.classof(binding.ty) == Ty.TView then return V.VecKernelLenView(binding) end
        return V.VecKernelLenBinding(binding)
    end

    local function view_access_for_binding(aliases, binding)
        local alias = alias_for_view(aliases, binding)
        if alias ~= nil then return alias.data, alias.offset, alias.base_len, alias.len_value end
        local source = default_len_source(binding)
        return binding, V.VecKernelOffsetZero, source, len_source_expr(source)
    end

    local function expr_len_binding(expr, aliases)
        if pvm.classof(expr) == Tr.ExprLen then
            local binding = ref_binding(expr.value)
            if binding ~= nil then return resolve_view_len(aliases, binding) end
        end
        return nil
    end

    local function binding_id(region_id, label, name) return C.Id("control:param:" .. region_id .. ":" .. label.name .. ":" .. name) end

    local function entry_param_binding(region, index)
        local param = region.entry.params[index]
        return B.Binding(binding_id(region.region_id, region.entry.label, param.name), param.name, param.ty, B.BindingClassEntryBlockParam(region.region_id, region.entry.label.name, index))
    end

    local function find_self_jump(region)
        if #region.entry.body == 0 then return nil end
        local last = region.entry.body[#region.entry.body]
        if pvm.classof(last) == Tr.StmtJump and last.target.name == region.entry.label.name then return last end
        return nil
    end

    local function find_jump_arg(args, name)
        for i = 1, #args do if args[i].name == name then return args[i] end end
        return nil
    end

    local function reduction_source_op(reduction)
        local cls = pvm.classof(reduction)
        if cls == V.VecReductionAdd then return V.VecAdd end
        if cls == V.VecReductionMul then return V.VecMul end
        if cls == V.VecReductionBitAnd then return V.VecBitAnd end
        if cls == V.VecReductionBitOr then return V.VecBitOr end
        if cls == V.VecReductionBitXor then return V.VecBitXor end
        return nil
    end

    local function source_bin_op(op)
        if op == C.BinAdd then return V.VecAdd end
        if op == C.BinMul then return V.VecMul end
        if op == C.BinBitAnd then return V.VecBitAnd end
        if op == C.BinBitOr then return V.VecBitOr end
        if op == C.BinBitXor then return V.VecBitXor end
        return nil
    end

    local function identity_raw(op, elem)
        if op == V.VecAdd or op == V.VecBitOr or op == V.VecBitXor then return "0" end
        if op == V.VecMul then return "1" end
        if op == V.VecBitAnd then
            if elem == V.VecElemU32 then return "4294967295" end
            if elem == V.VecElemU64 then return "18446744073709551615" end
            return "-1"
        end
        return nil
    end

    local function contribution_expr(update, acc_binding, vec_op)
        if pvm.classof(update) ~= Tr.ExprBinary or source_bin_op(update.op) ~= vec_op then return nil end
        if same_ref(update.lhs, acc_binding) then return update.rhs end
        if same_ref(update.rhs, acc_binding) then return update.lhs end
        return nil
    end

    local function view_base_expr(view)
        local cls = pvm.classof(view)
        if cls == Tr.ViewFromExpr then return view.base end
        if cls == Tr.ViewContiguous then return view.data end
        if cls == Tr.ViewStrided and literal_int_raw(view.stride) == "1" then return view.data end
        return nil
    end

    local function stride_value_for_view(view)
        local cls = pvm.classof(view)
        if cls == Tr.ViewFromExpr or cls == Tr.ViewContiguous then return V.VecKernelStrideUnit end
        if cls == Tr.ViewStrided then
            local raw = literal_int_raw(view.stride)
            if raw ~= nil then return V.VecKernelStrideConst(raw) end
            return V.VecKernelStrideDynamic(view.stride)
        end
        return nil
    end

    local function stride_is_unit(stride)
        if stride == nil or stride == V.VecKernelStrideUnit then return true end
        if pvm.classof(stride) == V.VecKernelStrideConst and stride.raw == "1" then return true end
        return false
    end

    local function vector_load_access(expr, index_binding, elem, aliases)
        if pvm.classof(expr) ~= Tr.ExprIndex then return nil end
        if not same_ref(expr.index, index_binding) then return nil end
        if pvm.classof(expr.base) ~= Tr.IndexBaseView then return nil end
        local base_expr = view_base_expr(expr.base.view)
        local binding = ref_binding(base_expr)
        if binding == nil then return nil end
        if elem_from_type(expr_ty(expr)) ~= elem then return nil end
        local data, offset, base_len, len_value = view_access_for_binding(aliases, binding)
        return { base = data, offset = offset, base_len = base_len, len_value = len_value }
    end

    local function bin_op(op)
        if op == C.BinAdd then return V.VecAdd end
        if op == C.BinSub then return V.VecSub end
        if op == C.BinMul then return V.VecMul end
        if op == C.BinBitAnd then return V.VecBitAnd end
        if op == C.BinBitOr then return V.VecBitOr end
        if op == C.BinBitXor then return V.VecBitXor end
        return nil
    end

    local function infer_kernel_expr_elem(expr, index_binding)
        local load_elem = elem_from_type(expr_ty(expr))
        if vector_load_access(expr, index_binding, load_elem, nil) ~= nil then return load_elem end
        local cls = pvm.classof(expr)
        if cls == Tr.ExprBinary or cls == Tr.ExprCompare then
            local lhs = infer_kernel_expr_elem(expr.lhs, index_binding)
            local rhs = infer_kernel_expr_elem(expr.rhs, index_binding)
            if lhs ~= nil and rhs ~= nil and lhs == rhs then return lhs end
        elseif cls == Tr.ExprSelect then
            local a = infer_kernel_expr_elem(expr.then_expr, index_binding)
            local b = infer_kernel_expr_elem(expr.else_expr, index_binding)
            if a ~= nil and b ~= nil and a == b then return a end
        end
        return elem_from_type(expr_ty(expr))
    end

    local function cmp_op(op, elem)
        if op == C.CmpEq then return V.VecCmpEq end
        if op == C.CmpNe then return V.VecCmpNe end
        local unsigned = elem == V.VecElemU32 or elem == V.VecElemU64
        if op == C.CmpLt then return unsigned and V.VecCmpULt or V.VecCmpSLt end
        if op == C.CmpLe then return unsigned and V.VecCmpULe or V.VecCmpSLe end
        if op == C.CmpGt then return unsigned and V.VecCmpUGt or V.VecCmpSGt end
        if op == C.CmpGe then return unsigned and V.VecCmpUGe or V.VecCmpSGe end
        return nil
    end

    local function mask_bin_op(op)
        if op == C.LogicAnd then return V.VecMaskAnd end
        if op == C.LogicOr then return V.VecMaskOr end
        return nil
    end

    local kernel_expr
    local function kernel_mask_expr(expr, index_binding, elem, target, shape, aliases)
        local cls = pvm.classof(expr)
        if cls == Tr.ExprCompare then
            local op = cmp_op(expr.op, elem)
            if op == nil or not target_supports_cmp_op(target, shape, op) then return nil end
            local lhs = kernel_expr(expr.lhs, index_binding, elem, target, shape, aliases)
            local rhs = kernel_expr(expr.rhs, index_binding, elem, target, shape, aliases)
            if lhs == nil or rhs == nil then return nil end
            return V.VecKernelMaskCompare(op, lhs, rhs)
        elseif cls == Tr.ExprUnary and expr.op == C.UnaryNot then
            if not target_supports_mask_op(target, shape, V.VecMaskNot) then return nil end
            local value = kernel_mask_expr(expr.value, index_binding, elem, target, shape, aliases)
            if value == nil then return nil end
            return V.VecKernelMaskNot(value)
        elseif cls == Tr.ExprLogic then
            local op = mask_bin_op(expr.op)
            if op == nil or not target_supports_mask_op(target, shape, op) then return nil end
            local lhs = kernel_mask_expr(expr.lhs, index_binding, elem, target, shape, aliases)
            local rhs = kernel_mask_expr(expr.rhs, index_binding, elem, target, shape, aliases)
            if lhs == nil or rhs == nil then return nil end
            return V.VecKernelMaskBin(op, lhs, rhs)
        end
        return nil
    end

    kernel_expr = function(expr, index_binding, elem, target, shape, aliases)
        local load = vector_load_access(expr, index_binding, elem, aliases)
        if load ~= nil then return V.VecKernelExprLoad(load.base, load.offset, load.base_len, load.len_value) end
        local cls = pvm.classof(expr)
        if cls == Tr.ExprBinary then
            local op = bin_op(expr.op)
            if op == nil or not target_supports_bin_op(target, shape, op) then return nil end
            if elem_from_type(expr_ty(expr)) ~= elem then return nil end
            local lhs = kernel_expr(expr.lhs, index_binding, elem, target, shape, aliases)
            local rhs = kernel_expr(expr.rhs, index_binding, elem, target, shape, aliases)
            if lhs == nil or rhs == nil then return nil end
            return V.VecKernelExprBin(op, lhs, rhs)
        elseif cls == Tr.ExprSelect then
            if elem_from_type(expr_ty(expr)) ~= elem or not target_supports_select(target, shape) then return nil end
            local cond = kernel_mask_expr(expr.cond, index_binding, elem, target, shape, aliases)
            local then_value = kernel_expr(expr.then_expr, index_binding, elem, target, shape, aliases)
            local else_value = kernel_expr(expr.else_expr, index_binding, elem, target, shape, aliases)
            if cond == nil or then_value == nil or else_value == nil then return nil end
            return V.VecKernelExprSelect(cond, then_value, else_value)
        end
        if elem_from_type(expr_ty(expr)) == elem then return V.VecKernelExprInvariant(expr) end
        return nil
    end

    local function vector_store_plan(stmt, index_binding, aliases)
        if pvm.classof(stmt) ~= Tr.StmtSet or pvm.classof(stmt.place) ~= Tr.PlaceIndex then return nil end
        if not same_ref(stmt.place.index, index_binding) then return nil end
        if pvm.classof(stmt.place.base) ~= Tr.IndexBaseView then return nil end
        local dst_binding = ref_binding(view_base_expr(stmt.place.base.view))
        if dst_binding == nil then return nil end
        local dst, dst_offset, dst_base_len, dst_len_value = view_access_for_binding(aliases, dst_binding)
        local elem = elem_from_type(stmt.place.h.ty)
        if elem == nil then return nil end
        local shape = elem_shape(elem)
        local target = target_for_elem(elem)
        if shape == nil or target == nil then return nil end
        local value = kernel_expr(stmt.value, index_binding, elem, target, shape, aliases)
        if value == nil then return nil end
        return V.VecKernelStorePlan(dst, dst_offset, dst_base_len, dst_len_value, value), elem
    end

    local function make_decision(facts, elem)
        local shape = elem_shape(elem)
        if shape == nil then return nil end
        local proof = V.VecProofDomain("kernel planner selected target-supported vector shape")
        local proofs = { proof }
        local tail = V.VecTailScalar
        local chosen = V.VecLoopVector(facts.loop, shape, 1, tail, proofs)
        local schedule = V.VecScheduleVector(shape, 1, 1, tail, 1, {}, proofs)
        return V.VecLoopDecision(facts, V.VecLegal(proofs), schedule, chosen, { V.VecShapeScore(chosen, shape.lanes, 50, "kernel planner structural match") })
    end

    local function view_alias_reject(binding, reason)
        return V.VecRejectUnsupportedMemory(V.VecAccessId("view.alias:" .. binding.id.text), reason)
    end

    local function scalar_alias_from_stmt(stmt)
        if pvm.classof(stmt) ~= Tr.StmtLet or pvm.classof(stmt.binding.ty) == Ty.TView then return nil end
        if back_scalar(stmt.binding.ty) == nil then return nil end
        return V.VecKernelScalarAlias(stmt.binding, stmt.init)
    end

    local function view_alias_from_stmt(stmt, aliases, scalars)
        if pvm.classof(stmt) ~= Tr.StmtLet or pvm.classof(stmt.binding.ty) ~= Ty.TView then return nil, nil, false end
        if pvm.classof(stmt.init) ~= Tr.ExprView then return nil, nil, false end
        local view = stmt.init.view
        local cls = pvm.classof(view)
        if cls == Tr.ViewContiguous or cls == Tr.ViewStrided then
            local data = ref_binding(view.data)
            local len = ref_binding(view.len)
            if data == nil or len == nil then return nil, view_alias_reject(stmt.binding, "constructed view data and length must be bindings for vector kernel planning"), true end
            local stride = stride_value_for_view(view)
            if not stride_is_unit(stride) then return nil, view_alias_reject(stmt.binding, "non-unit constructed view stride requires future gather/scatter vectorization"), true end
            return V.VecKernelViewAlias(stmt.binding, data, len, stride, V.VecKernelOffsetZero, V.VecKernelLenBinding(len), len_value_for_binding(scalars, len)), nil, true
        elseif cls == Tr.ViewWindow then
            if pvm.classof(view.base) ~= Tr.ViewFromExpr then return nil, view_alias_reject(stmt.binding, "window vectorization requires a named base view"), true end
            local base_binding = ref_binding(view.base.base)
            if base_binding == nil then return nil, view_alias_reject(stmt.binding, "window vectorization requires a named base view"), true end
            local base_alias = alias_for_view(aliases, base_binding)
            if base_alias == nil then return nil, view_alias_reject(stmt.binding, "window vectorization requires a prior constructed base-view alias"), true end
            if not stride_is_unit(base_alias.stride) then return nil, view_alias_reject(stmt.binding, "window over non-unit stride requires future gather/scatter vectorization"), true end
            local len = ref_binding(view.len)
            if len == nil then return nil, view_alias_reject(stmt.binding, "window length must be a binding for vector kernel planning"), true end
            return V.VecKernelViewAlias(stmt.binding, base_alias.data, len, base_alias.stride, offset_add(base_alias.offset, view.start), base_alias.base_len, len_value_for_binding(scalars, len)), nil, true
        end
        return nil, view_alias_reject(stmt.binding, "only constructed contiguous/strided views and windows are considered by vector kernel planning"), true
    end

    local function arg_binding_for_param(func_name, param, index)
        return abi_api.arg_binding_for_param(func_name, param, index)
    end

    local function seed_param_aliases(func_name, params)
        local aliases = {}
        for i = 1, #(params or {}) do
            if pvm.classof(params[i].ty) == Ty.TView then
                local binding = arg_binding_for_param(func_name, params[i], i)
                aliases[#aliases + 1] = V.VecKernelViewAlias(binding, binding, binding, V.VecKernelStrideUnit, V.VecKernelOffsetZero, V.VecKernelLenView(binding), Tr.ExprLen(Tr.ExprTyped(Ty.TScalar(C.ScalarIndex)), binding_expr(binding)))
            end
        end
        return aliases
    end

    local function split_prefix_aliases(body, initial_aliases)
        local aliases = {}
        for i = 1, #(initial_aliases or {}) do aliases[#aliases + 1] = initial_aliases[i] end
        local scalars = {}
        local rejects = {}
        local first = 1
        while first <= #body do
            local scalar = scalar_alias_from_stmt(body[first])
            if scalar ~= nil then
                scalars[#scalars + 1] = scalar
                first = first + 1
            else
                local alias, reject_value, consumed = view_alias_from_stmt(body[first], aliases, scalars)
                if not consumed then break end
                if reject_value ~= nil then rejects[#rejects + 1] = reject_value end
                if alias ~= nil then aliases[#aliases + 1] = alias end
                first = first + 1
            end
        end
        local rest = {}
        for i = first, #body do rest[#rest + 1] = body[i] end
        return aliases, scalars, rest, rejects
    end

    local function kernel_counter_for_stop(region_id, stop)
        if pvm.classof(stop.ty) == Ty.TView then return V.VecKernelCounterIndex({ V.VecProofDomain("view length ABI uses index counters") }) end
        if pvm.classof(stop.ty) == Ty.TScalar then
            if stop.ty.scalar == C.ScalarIndex then return V.VecKernelCounterIndex({ V.VecProofDomain("stop binding is index") }) end
            if stop.ty.scalar == C.ScalarI32 then return V.VecKernelCounterI32({ V.VecProofDomain("stop binding is i32") }) end
        end
        return V.VecKernelCounterRejected(V.VecRejectUnsupportedLoop(loop_id(region_id or "unknown"), "kernel stop type does not have an executable counter policy"))
    end

    local function common_region_base(region, aliases)
        if #region.blocks ~= 0 then return nil, reject(region.region_id, "multi-block vector kernel planning deferred") end
        local facts = facts_api.facts(region)
        if pvm.classof(facts.domain) ~= V.VecDomainCounted then return nil, reject(region.region_id, "kernel needs counted domain") end
        if #facts.inductions ~= 1 then return nil, reject(region.region_id, "kernel needs one primary induction") end
        if literal_int_raw(facts.domain.start) ~= "0" or literal_int_raw(facts.domain.step) ~= "1" then return nil, reject(region.region_id, "kernel needs i = 0, i = i + 1") end
        local stop = ref_binding(facts.domain.stop) or expr_len_binding(facts.domain.stop, aliases)
        if stop == nil then return nil, reject(region.region_id, "kernel stop must be a binding or len(view)") end
        local counter = kernel_counter_for_stop(region.region_id, stop)
        if pvm.classof(counter) == V.VecKernelCounterRejected then return nil, V.VecKernelNoPlan({ counter.reject }) end
        return { facts = facts, index = facts.inductions[1].binding, stop = stop, counter = counter }, nil
    end

    local function plan_reduce_region(region, contracts, aliases, scalars)
        local common, no = common_region_base(region, aliases)
        if common == nil then return no end
        if #common.facts.reductions ~= 1 or #common.facts.stores ~= 0 then return reject(region.region_id, "reduction kernel needs one reduction and no stores") end
        local reduction = common.facts.reductions[1]
        local red_op = reduction_source_op(reduction)
        if red_op == nil then return reject(region.region_id, "unsupported reduction operator") end
        local jump = find_self_jump(region)
        if jump == nil then return reject(region.region_id, "missing self jump") end
        local acc_index, acc_binding = nil, reduction.accumulator
        for i = 1, #region.entry.params do if same_binding_slot(entry_param_binding(region, i), acc_binding) then acc_index = i end end
        local acc_arg = find_jump_arg(jump.args, region.entry.params[acc_index].name)
        if acc_arg == nil then return reject(region.region_id, "missing accumulator jump arg") end
        local contribution = contribution_expr(acc_arg.value, acc_binding, red_op)
        if contribution == nil then return reject(region.region_id, "reduction contribution not recognized") end
        local elem = elem_from_type(acc_binding.ty) or infer_kernel_expr_elem(contribution, common.index)
        local target = elem and target_for_elem(elem) or nil
        local shape = elem and elem_shape(elem) or nil
        if elem == nil or target == nil or shape == nil then return reject(region.region_id, "reduction element type is not vectorizable") end
        if not target_supports_bin_op(target, shape, red_op) then return reject(region.region_id, "target does not support reduction op") end
        local identity = identity_raw(red_op, elem)
        if identity == nil or literal_int_raw(region.entry.params[acc_index].init) ~= identity then return reject(region.region_id, "reduction accumulator identity mismatch") end
        local value = kernel_expr(contribution, common.index, elem, target, shape, aliases)
        if value == nil then return reject(region.region_id, "reduction contribution is not vectorizable") end
        local decision = make_decision(common.facts, elem)
        local reduction_plan = V.VecKernelReductionBin(red_op, elem, acc_binding, value, identity)
        local core = V.VecKernelCoreReduce(decision, elem, common.stop, common.counter, scalars or {}, reduction_plan)
        local safety = safety_api.decide(common.facts, core, contracts or {})
        return V.VecKernelReduce(decision, elem, common.stop, common.counter, scalars or {}, reduction_plan, safety.safety, safety.alignments, safety.aliases)
    end

    local function plan_map_region(region, contracts, aliases, scalars)
        local common, no = common_region_base(region, aliases)
        if common == nil then return no end
        if #common.facts.reductions ~= 0 or #common.facts.stores == 0 then return reject(region.region_id, "map kernel needs stores and no reductions") end
        local stores = {}; local elem = nil
        for i = 1, #region.entry.body do
            local store, store_elem = vector_store_plan(region.entry.body[i], common.index, aliases)
            if store ~= nil then
                if elem == nil then elem = store_elem elseif elem ~= store_elem then return reject(region.region_id, "mixed element vector maps are deferred") end
                stores[#stores + 1] = store
            end
        end
        if #stores ~= #common.facts.stores then return reject(region.region_id, "not all stores are vectorizable") end
        local decision = make_decision(common.facts, elem)
        local core = V.VecKernelCoreMap(decision, elem, common.stop, common.counter, scalars or {}, stores)
        local safety = safety_api.decide(common.facts, core, contracts or {})
        return V.VecKernelMap(decision, elem, common.stop, common.counter, scalars or {}, stores, safety.safety, safety.alignments, safety.aliases)
    end

    local function plan_func(name, visibility, params, result_ty, body, contracts)
        local aliases, scalars, kernel_body, alias_rejects = split_prefix_aliases(body, seed_param_aliases(name, params))
        if #alias_rejects > 0 then return V.VecKernelNoPlan(alias_rejects) end
        if #kernel_body ~= 1 then return V.VecKernelNoPlan({}) end
        if pvm.classof(kernel_body[1]) == Tr.StmtReturnValue and pvm.classof(kernel_body[1].value) == Tr.ExprControl then
            local region = kernel_body[1].value.region
            if pvm.classof(region) == Tr.ControlExprRegion then return plan_reduce_region(region, contracts, aliases, scalars) end
        elseif pvm.classof(kernel_body[1]) == Tr.StmtControl then
            local region = kernel_body[1].region
            if pvm.classof(region) == Tr.ControlStmtRegion then return plan_map_region(region, contracts, aliases, scalars) end
        end
        return V.VecKernelNoPlan({})
    end

    return { plan_func = plan_func, plan = plan_func }
end

return M
