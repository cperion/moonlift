local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local C = T.MoonCore
    local Ty = T.MoonType
    local Bn = T.MoonBind
    local Sem = T.MoonSem
    local Tr = T.MoonTree
    local Back = T.MoonBack
    local Host = T.MoonHost

    local scalar_api = require("moonlift.type_to_back_scalar").Define(T)
    local layout_api = require("moonlift.type_size_align").Define(T)
    local vec_kernel_plan_api = require("moonlift.vec_kernel_plan").Define(T)
    local vec_kernel_to_back_api = require("moonlift.vec_kernel_to_back").Define(T)
    local contract_api = require("moonlift.tree_contract_facts").Define(T)
    local abi_api = require("moonlift.type_func_abi_plan").Define(T)

    local expr_type
    local scalar_literal
    local unary_op
    local binary_cmd
    local compare_op
    local machine_cast_op
    local surface_cast_op
    local call_target
    local expr_to_back
    local field_addr_from_base_ptr
    local load_from_field_addr
    local view_to_back
    local index_addr_to_back
    local place_addr_to_back
    local place_store_to_back
    local stmt_to_back
    local lower_body
    local func_to_back
    local try_vector_func
    local extern_to_back
    local item_to_back
    local module_to_back
    local control_api
    local append_load_info
    local append_store_info

    local function env_empty(ret)
        return Tr.TreeBackEnv({}, 0, 0, ret or Tr.TreeBackReturnScalar)
    end

    local function env_add(env, binding, value, ty)
        local locals = {}
        for i = 1, #env.locals do locals[#locals + 1] = env.locals[i] end
        locals[#locals + 1] = Tr.TreeBackScalarLocal(binding, value, ty)
        return Tr.TreeBackEnv(locals, env.next_value, env.next_block, env.ret)
    end

    local function env_add_view(env, binding, data, len)
        local locals = {}
        for i = 1, #env.locals do locals[#locals + 1] = env.locals[i] end
        locals[#locals + 1] = Tr.TreeBackViewLocal(binding, data, len)
        return Tr.TreeBackEnv(locals, env.next_value, env.next_block, env.ret)
    end

    local function env_add_strided_view(env, binding, data, len, stride)
        local locals = {}
        for i = 1, #env.locals do locals[#locals + 1] = env.locals[i] end
        locals[#locals + 1] = Tr.TreeBackStridedViewLocal(binding, data, len, stride)
        return Tr.TreeBackEnv(locals, env.next_value, env.next_block, env.ret)
    end

    local function env_with_locals(env, locals)
        local out = {}
        for i = 1, #locals do out[#out + 1] = locals[i] end
        return Tr.TreeBackEnv(out, env.next_value, env.next_block, env.ret)
    end

    local function env_with_counters(env, counters)
        return Tr.TreeBackEnv(env.locals, counters.next_value, counters.next_block, env.ret)
    end

    local function same_binding_slot(a, b)
        if a == b then return true end
        if a.name ~= b.name then return false end
        local ca, cb = pvm.classof(a.class), pvm.classof(b.class)
        if ca == Bn.BindingClassArg and cb == Bn.BindingClassArg then return a.class.index == b.class.index end
        if ca == Bn.BindingClassEntryBlockParam and cb == Bn.BindingClassEntryBlockParam then
            return a.class.region_id == b.class.region_id and a.class.block_name == b.class.block_name and a.class.index == b.class.index
        end
        if ca == Bn.BindingClassBlockParam and cb == Bn.BindingClassBlockParam then
            return a.class.region_id == b.class.region_id and a.class.block_name == b.class.block_name and a.class.index == b.class.index
        end
        return false
    end

    local function env_lookup(env, binding)
        for i = #env.locals, 1, -1 do
            local local_entry = env.locals[i]
            if same_binding_slot(local_entry.binding, binding) then return local_entry end
        end
        return nil
    end

    local function env_next_value(env, prefix)
        local n = env.next_value + 1
        return Tr.TreeBackEnv(env.locals, n, env.next_block, env.ret), Back.BackValId(prefix .. tostring(n))
    end

    local function env_next_block(env, prefix)
        local n = env.next_block + 1
        return Tr.TreeBackEnv(env.locals, env.next_value, n, env.ret), Back.BackBlockId(prefix .. tostring(n))
    end

    local function append_all(out, xs)
        for i = 1, #xs do out[#out + 1] = xs[i] end
    end

    local function expr_ty(expr)
        return expr_type:one_uncached(expr.h)
    end

    local function back_scalar(ty)
        local result = scalar_api.result(ty)
        if pvm.classof(result) == Ty.TypeBackScalarKnown then return result.scalar end
        return nil
    end

    local int_scalar_info = {
        [Back.BackBool] = { bits = 1, signed = false },
        [Back.BackI8] = { bits = 8, signed = true },
        [Back.BackI16] = { bits = 16, signed = true },
        [Back.BackI32] = { bits = 32, signed = true },
        [Back.BackI64] = { bits = 64, signed = true },
        [Back.BackU8] = { bits = 8, signed = false },
        [Back.BackU16] = { bits = 16, signed = false },
        [Back.BackU32] = { bits = 32, signed = false },
        [Back.BackU64] = { bits = 64, signed = false },
        [Back.BackIndex] = { bits = 64, signed = true },
    }

    local float_scalar_bits = {
        [Back.BackF32] = 32,
        [Back.BackF64] = 64,
    }

    local function semantic_cast_op(src_scalar, dst_scalar)
        if src_scalar == nil or dst_scalar == nil then return C.MachineCastBitcast end
        if src_scalar == dst_scalar then return C.MachineCastIdentity end
        local si, di = int_scalar_info[src_scalar], int_scalar_info[dst_scalar]
        if si ~= nil and di ~= nil then
            if di.bits < si.bits then return C.MachineCastIreduce end
            if di.bits > si.bits then return si.signed and C.MachineCastSextend or C.MachineCastUextend end
            return C.MachineCastBitcast
        end
        local sf, df = float_scalar_bits[src_scalar], float_scalar_bits[dst_scalar]
        if sf ~= nil and df ~= nil then
            if df > sf then return C.MachineCastFpromote end
            if df < sf then return C.MachineCastFdemote end
            return C.MachineCastIdentity
        end
        if si ~= nil and df ~= nil then return si.signed and C.MachineCastSToF or C.MachineCastUToF end
        if sf ~= nil and di ~= nil then return di.signed and C.MachineCastFToS or C.MachineCastFToU end
        return C.MachineCastBitcast
    end

    local function surface_cast_to_machine_op(surface_op, src_ty, dst_ty)
        if surface_op == C.SurfaceCast then return semantic_cast_op(back_scalar(src_ty), back_scalar(dst_ty)) end
        return surface_cast_op:one_uncached(surface_op)
    end

    local function core_scalar_to_back(scalar)
        local values = pvm.drain(scalar_api.scalar_to_back(scalar))
        return values[1]
    end

    local function field_storage_scalar(field)
        if pvm.classof(field) ~= Sem.FieldByOffset then return back_scalar(field.ty) end
        local storage = field.storage
        local cls = pvm.classof(storage)
        if cls == Host.HostRepScalar then return core_scalar_to_back(storage.scalar) end
        if cls == Host.HostRepBool then return core_scalar_to_back(storage.storage) end
        return back_scalar(field.ty)
    end

    local function field_is_stored_bool(field)
        return pvm.classof(field) == Sem.FieldByOffset and pvm.classof(field.storage) == Host.HostRepBool
    end

    local function is_view_type(ty)
        return pvm.classof(ty) == Ty.TView
    end

    local function shape_scalar(s)
        return Back.BackShapeScalar(s)
    end

    local function elem_size(ty)
        local result = layout_api.result(ty)
        if pvm.classof(result) == Ty.TypeMemLayoutKnown then return result.layout.size end
        return nil
    end

    local function shape_vec(vec)
        return Back.BackShapeVec(vec)
    end

    local function view_elem(view)
        local cls = pvm.classof(view)
        if cls == Tr.ViewFromExpr or cls == Tr.ViewContiguous or cls == Tr.ViewStrided or cls == Tr.ViewRestrided or cls == Tr.ViewRowBase or cls == Tr.ViewInterleaved or cls == Tr.ViewInterleavedView then return view.elem end
        if cls == Tr.ViewWindow then return view_elem(view.base) end
        return Ty.TScalar(C.ScalarVoid)
    end

    local function expr_value(result)
        if pvm.classof(result) == Tr.TreeBackExprValue then return result end
        return nil
    end

    local function expr_view_value(result)
        local cls = pvm.classof(result)
        if cls == Tr.TreeBackExprView or cls == Tr.TreeBackExprStridedView then return result end
        return nil
    end

    expr_type = pvm.phase("moon2_tree_expr_type_from_header", {
        [Tr.ExprTyped] = function(self) return pvm.once(self.ty) end,
        [Tr.ExprOpen] = function(self) return pvm.once(self.ty) end,
        [Tr.ExprSem] = function(self) return pvm.once(self.ty) end,
        [Tr.ExprCode] = function(self) return pvm.once(self.ty) end,
        [Tr.ExprSurface] = function() return pvm.empty() end,
    })

    scalar_literal = pvm.phase("moon2_tree_literal_to_back_literal", {
        [C.LitInt] = function(self) return pvm.once(Back.BackLitInt(self.raw)) end,
        [C.LitFloat] = function(self) return pvm.once(Back.BackLitFloat(self.raw)) end,
        [C.LitBool] = function(self) return pvm.once(Back.BackLitBool(self.value)) end,
        [C.LitNil] = function() return pvm.once(Back.BackLitNull) end,
    })

    unary_op = pvm.phase("moon2_tree_unary_to_back_op", {
        [C.UnaryNeg] = function(_, scalar)
            if scalar == Back.BackF32 or scalar == Back.BackF64 then return pvm.once(Back.BackUnaryFneg) end
            return pvm.once(Back.BackUnaryIneg)
        end,
        [C.UnaryNot] = function() return pvm.once(Back.BackUnaryBoolNot) end,
        [C.UnaryBitNot] = function() return pvm.once(Back.BackUnaryBnot) end,
    }, { args_cache = "last" })

    local function int_sem_wrap()
        return Back.BackIntSemantics(Back.BackIntWrap, Back.BackIntMayLose)
    end

    binary_cmd = pvm.phase("moon2_tree_binary_to_back_cmd", {
        [C.BinAdd] = function(_, dst, scalar, lhs, rhs)
            if scalar == Back.BackF32 or scalar == Back.BackF64 then return pvm.once(Back.CmdFloatBinary(dst, Back.BackFloatAdd, scalar, Back.BackFloatStrict, lhs, rhs)) end
            return pvm.once(Back.CmdIntBinary(dst, Back.BackIntAdd, scalar, int_sem_wrap(), lhs, rhs))
        end,
        [C.BinSub] = function(_, dst, scalar, lhs, rhs)
            if scalar == Back.BackF32 or scalar == Back.BackF64 then return pvm.once(Back.CmdFloatBinary(dst, Back.BackFloatSub, scalar, Back.BackFloatStrict, lhs, rhs)) end
            return pvm.once(Back.CmdIntBinary(dst, Back.BackIntSub, scalar, int_sem_wrap(), lhs, rhs))
        end,
        [C.BinMul] = function(_, dst, scalar, lhs, rhs)
            if scalar == Back.BackF32 or scalar == Back.BackF64 then return pvm.once(Back.CmdFloatBinary(dst, Back.BackFloatMul, scalar, Back.BackFloatStrict, lhs, rhs)) end
            return pvm.once(Back.CmdIntBinary(dst, Back.BackIntMul, scalar, int_sem_wrap(), lhs, rhs))
        end,
        [C.BinDiv] = function(_, dst, scalar, lhs, rhs)
            if scalar == Back.BackF32 or scalar == Back.BackF64 then return pvm.once(Back.CmdFloatBinary(dst, Back.BackFloatDiv, scalar, Back.BackFloatStrict, lhs, rhs)) end
            return pvm.once(Back.CmdIntBinary(dst, Back.BackIntSDiv, scalar, int_sem_wrap(), lhs, rhs))
        end,
        [C.BinRem] = function(_, dst, scalar, lhs, rhs) return pvm.once(Back.CmdIntBinary(dst, Back.BackIntSRem, scalar, int_sem_wrap(), lhs, rhs)) end,
        [C.BinBitAnd] = function(_, dst, scalar, lhs, rhs) return pvm.once(Back.CmdBitBinary(dst, Back.BackBitAnd, scalar, lhs, rhs)) end,
        [C.BinBitOr] = function(_, dst, scalar, lhs, rhs) return pvm.once(Back.CmdBitBinary(dst, Back.BackBitOr, scalar, lhs, rhs)) end,
        [C.BinBitXor] = function(_, dst, scalar, lhs, rhs) return pvm.once(Back.CmdBitBinary(dst, Back.BackBitXor, scalar, lhs, rhs)) end,
        [C.BinShl] = function(_, dst, scalar, lhs, rhs) return pvm.once(Back.CmdShift(dst, Back.BackShiftLeft, scalar, lhs, rhs)) end,
        [C.BinLShr] = function(_, dst, scalar, lhs, rhs) return pvm.once(Back.CmdShift(dst, Back.BackShiftLogicalRight, scalar, lhs, rhs)) end,
        [C.BinAShr] = function(_, dst, scalar, lhs, rhs) return pvm.once(Back.CmdShift(dst, Back.BackShiftArithmeticRight, scalar, lhs, rhs)) end,
    }, { args_cache = "last" })

    compare_op = pvm.phase("moon2_tree_compare_to_back_op", {
        [C.CmpEq] = function(_, scalar) if scalar == Back.BackF32 or scalar == Back.BackF64 then return pvm.once(Back.BackFCmpEq) end return pvm.once(Back.BackIcmpEq) end,
        [C.CmpNe] = function(_, scalar) if scalar == Back.BackF32 or scalar == Back.BackF64 then return pvm.once(Back.BackFCmpNe) end return pvm.once(Back.BackIcmpNe) end,
        [C.CmpLt] = function(_, scalar) if scalar == Back.BackF32 or scalar == Back.BackF64 then return pvm.once(Back.BackFCmpLt) end return pvm.once(Back.BackSIcmpLt) end,
        [C.CmpLe] = function(_, scalar) if scalar == Back.BackF32 or scalar == Back.BackF64 then return pvm.once(Back.BackFCmpLe) end return pvm.once(Back.BackSIcmpLe) end,
        [C.CmpGt] = function(_, scalar) if scalar == Back.BackF32 or scalar == Back.BackF64 then return pvm.once(Back.BackFCmpGt) end return pvm.once(Back.BackSIcmpGt) end,
        [C.CmpGe] = function(_, scalar) if scalar == Back.BackF32 or scalar == Back.BackF64 then return pvm.once(Back.BackFCmpGe) end return pvm.once(Back.BackSIcmpGe) end,
    }, { args_cache = "last" })

    machine_cast_op = pvm.phase("moon2_tree_machine_cast_to_back_op", {
        [C.MachineCastBitcast] = function() return pvm.once(Back.BackBitcast) end,
        [C.MachineCastIreduce] = function() return pvm.once(Back.BackIreduce) end,
        [C.MachineCastSextend] = function() return pvm.once(Back.BackSextend) end,
        [C.MachineCastUextend] = function() return pvm.once(Back.BackUextend) end,
        [C.MachineCastFpromote] = function() return pvm.once(Back.BackFpromote) end,
        [C.MachineCastFdemote] = function() return pvm.once(Back.BackFdemote) end,
        [C.MachineCastSToF] = function() return pvm.once(Back.BackSToF) end,
        [C.MachineCastUToF] = function() return pvm.once(Back.BackUToF) end,
        [C.MachineCastFToS] = function() return pvm.once(Back.BackFToS) end,
        [C.MachineCastFToU] = function() return pvm.once(Back.BackFToU) end,
        [C.MachineCastIdentity] = function() return pvm.empty() end,
    })

    surface_cast_op = pvm.phase("moon2_tree_surface_cast_to_machine_cast", {
        [C.SurfaceCast] = function() return pvm.once(C.MachineCastBitcast) end,
        [C.SurfaceTrunc] = function() return pvm.once(C.MachineCastIreduce) end,
        [C.SurfaceZExt] = function() return pvm.once(C.MachineCastUextend) end,
        [C.SurfaceSExt] = function() return pvm.once(C.MachineCastSextend) end,
        [C.SurfaceBitcast] = function() return pvm.once(C.MachineCastBitcast) end,
        [C.SurfaceSatCast] = function() return pvm.once(C.MachineCastBitcast) end,
    })

    call_target = pvm.phase("moon2_tree_call_target_to_back", {
        [Sem.CallDirect] = function(self) return pvm.once(Back.BackCallDirect(Back.BackFuncId(self.func_name))) end,
        [Sem.CallExtern] = function(self) return pvm.once(Back.BackCallExtern(Back.BackExternId(self.symbol))) end,
        [Sem.CallIndirect] = function(self, env)
            local callee = expr_value(expr_to_back:one_uncached(self.callee, env))
            if callee == nil then return pvm.empty() end
            return pvm.once(Back.BackCallIndirect(callee.value))
        end,
        [Sem.CallClosure] = function() return pvm.empty() end,
        [Sem.CallUnresolved] = function() return pvm.empty() end,
    }, { args_cache = "last" })

    expr_to_back = pvm.phase("moon2_tree_expr_to_back", {
        [Tr.ExprLit] = function(self, env)
            local ty = expr_ty(self)
            local scalar = back_scalar(ty)
            if scalar == nil then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "literal has non-scalar type")) end
            local env2, dst = env_next_value(env, "v")
            return pvm.once(Tr.TreeBackExprValue(env2, { Back.CmdConst(dst, scalar, scalar_literal:one_uncached(self.value)) }, dst, scalar))
        end,
        [Tr.ExprRef] = function(self, env)
            if pvm.classof(self.ref) == Bn.ValueRefBinding then
                local local_entry = env_lookup(env, self.ref.binding)
                if local_entry ~= nil and pvm.classof(local_entry) == Tr.TreeBackScalarLocal then return pvm.once(Tr.TreeBackExprValue(env, {}, local_entry.value, local_entry.ty)) end
            end
            return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "unsupported ref"))
        end,
        [Tr.ExprUnary] = function(self, env)
            local value = expr_value(expr_to_back:one_uncached(self.value, env))
            if value == nil then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "unsupported unary operand")) end
            local env2, dst = env_next_value(value.env, "v")
            local cmds = {}; append_all(cmds, value.cmds)
            cmds[#cmds + 1] = Back.CmdUnary(dst, unary_op:one_uncached(self.op, value.ty), shape_scalar(value.ty), value.value)
            return pvm.once(Tr.TreeBackExprValue(env2, cmds, dst, value.ty))
        end,
        [Tr.ExprBinary] = function(self, env)
            local lhs = expr_value(expr_to_back:one_uncached(self.lhs, env))
            if lhs == nil then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "unsupported binary lhs")) end
            local rhs = expr_value(expr_to_back:one_uncached(self.rhs, lhs.env))
            if rhs == nil then return pvm.once(Tr.TreeBackExprUnsupported(lhs.env, lhs.cmds, "unsupported binary rhs")) end
            local ty = expr_ty(self)
            local scalar = back_scalar(ty) or lhs.ty
            local env2, dst = env_next_value(rhs.env, "v")
            local cmds = {}; append_all(cmds, lhs.cmds); append_all(cmds, rhs.cmds)
            local cmd = binary_cmd:drain_uncached(self.op, dst, scalar, lhs.value, rhs.value)[1]
            if cmd == nil then return pvm.once(Tr.TreeBackExprUnsupported(rhs.env, cmds, "unsupported binary op")) end
            cmds[#cmds + 1] = cmd
            return pvm.once(Tr.TreeBackExprValue(env2, cmds, dst, scalar))
        end,
        [Tr.ExprCompare] = function(self, env)
            local lhs = expr_value(expr_to_back:one_uncached(self.lhs, env))
            if lhs == nil then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "unsupported compare lhs")) end
            local rhs = expr_value(expr_to_back:one_uncached(self.rhs, lhs.env))
            if rhs == nil then return pvm.once(Tr.TreeBackExprUnsupported(lhs.env, lhs.cmds, "unsupported compare rhs")) end
            local env2, dst = env_next_value(rhs.env, "v")
            local cmds = {}; append_all(cmds, lhs.cmds); append_all(cmds, rhs.cmds)
            cmds[#cmds + 1] = Back.CmdCompare(dst, compare_op:one_uncached(self.op, lhs.ty), shape_scalar(lhs.ty), lhs.value, rhs.value)
            return pvm.once(Tr.TreeBackExprValue(env2, cmds, dst, Back.BackBool))
        end,
        [Tr.ExprMachineCast] = function(self, env)
            local value = expr_value(expr_to_back:one_uncached(self.value, env))
            if value == nil then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "unsupported cast operand")) end
            local scalar = back_scalar(self.ty)
            if scalar == nil then return pvm.once(Tr.TreeBackExprUnsupported(value.env, value.cmds, "cast result has non-scalar type")) end
            local ops = pvm.drain(machine_cast_op(self.op))
            if #ops == 0 then return pvm.once(Tr.TreeBackExprValue(value.env, value.cmds, value.value, scalar)) end
            local env2, dst = env_next_value(value.env, "v")
            local cmds = {}; append_all(cmds, value.cmds)
            cmds[#cmds + 1] = Back.CmdCast(dst, ops[1], scalar, value.value)
            return pvm.once(Tr.TreeBackExprValue(env2, cmds, dst, scalar))
        end,
        [Tr.ExprSelect] = function(self, env)
            local cond = expr_value(expr_to_back:one_uncached(self.cond, env))
            if cond == nil then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "unsupported select cond")) end
            local a = expr_value(expr_to_back:one_uncached(self.then_expr, cond.env))
            if a == nil then return pvm.once(Tr.TreeBackExprUnsupported(cond.env, cond.cmds, "unsupported select then")) end
            local b = expr_value(expr_to_back:one_uncached(self.else_expr, a.env))
            if b == nil then return pvm.once(Tr.TreeBackExprUnsupported(a.env, a.cmds, "unsupported select else")) end
            local scalar = back_scalar(expr_ty(self)) or a.ty
            local env2, dst = env_next_value(b.env, "v")
            local cmds = {}; append_all(cmds, cond.cmds); append_all(cmds, a.cmds); append_all(cmds, b.cmds)
            cmds[#cmds + 1] = Back.CmdSelect(dst, shape_scalar(scalar), cond.value, a.value, b.value)
            return pvm.once(Tr.TreeBackExprValue(env2, cmds, dst, scalar))
        end,
        [Tr.ExprCall] = function(self, env)
            local args = {}; local params = {}; local cmds = {}; local current = env
            for i = 1, #self.args do
                local arg = expr_value(expr_to_back:one_uncached(self.args[i], current))
                if arg == nil then return pvm.once(Tr.TreeBackExprUnsupported(current, cmds, "unsupported call arg")) end
                append_all(cmds, arg.cmds); args[#args + 1] = arg.value; params[#params + 1] = arg.ty; current = arg.env
            end
            local ty = expr_ty(self)
            local scalar = back_scalar(ty)
            if scalar == nil then return pvm.once(Tr.TreeBackExprUnsupported(current, cmds, "call result has non-scalar type")) end
            local env2, dst = env_next_value(current, "v")
            local target = call_target:one_uncached(self.target, env2)
            local sig, declare_call_sig = Back.BackSigId("sig:call:" .. tostring(dst.text)), true
            if pvm.classof(target) == Back.BackCallExtern then
                sig = Back.BackSigId("sig:extern:" .. tostring(target.func.text))
                declare_call_sig = false
            elseif pvm.classof(target) == Back.BackCallDirect then
                sig = Back.BackSigId("sig:" .. tostring(target.func.text))
                declare_call_sig = false
            end
            if declare_call_sig then cmds[#cmds + 1] = Back.CmdCreateSig(sig, params, { scalar }) end
            cmds[#cmds + 1] = Back.CmdCall(Back.BackCallValue(dst, scalar), target, sig, args)
            return pvm.once(Tr.TreeBackExprValue(env2, cmds, dst, scalar))
        end,
        [Tr.ExprCast] = function(self, env) return expr_to_back(Tr.ExprMachineCast(self.h, surface_cast_to_machine_op(self.op, expr_ty(self.value), self.ty), self.ty, self.value), env) end,
        [Tr.ExprLen] = function(self, env)
            local lowered = expr_to_back:one_uncached(self.value, env)
            local view = expr_view_value(lowered)
            if view ~= nil then return pvm.once(Tr.TreeBackExprValue(view.env, view.cmds, view.len, Back.BackIndex)) end
            if pvm.classof(self.value) == Tr.ExprRef and pvm.classof(self.value.ref) == Bn.ValueRefBinding then
                local local_entry = env_lookup(env, self.value.ref.binding)
                if local_entry ~= nil and (pvm.classof(local_entry) == Tr.TreeBackViewLocal or pvm.classof(local_entry) == Tr.TreeBackStridedViewLocal) then return pvm.once(Tr.TreeBackExprValue(env, {}, local_entry.len, Back.BackIndex)) end
            end
            return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "len lowering requires view binding"))
        end,
        [Tr.ExprLogic] = function(_, env) return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "logic lowering needs control flow")) end,
        [Tr.ExprIf] = function(_, env) return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "if expression lowering deferred")) end,
        [Tr.ExprSwitch] = function(_, env) return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "switch expression lowering deferred")) end,
        [Tr.ExprControl] = function(self, env) return control_api.expr_region_to_back(self.region, env) end,
        [Tr.ExprBlock] = function(_, env) return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "block expression lowering deferred")) end,
        [Tr.ExprDot] = function(_, env) return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "dot lowering deferred")) end,
        [Tr.ExprIntrinsic] = function(_, env) return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "intrinsic lowering deferred")) end,
        [Tr.ExprAddrOf] = function(self, env) return place_addr_to_back(self.place, env) end,
        [Tr.ExprDeref] = function(self, env)
            local addr = expr_value(expr_to_back:one_uncached(self.value, env))
            if addr == nil then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "unsupported deref address")) end
            local scalar = back_scalar(expr_ty(self))
            if scalar == nil then return pvm.once(Tr.TreeBackExprUnsupported(addr.env, addr.cmds, "deref result has non-scalar type")) end
            local env2, dst = env_next_value(addr.env, "v")
            local cmds = {}; append_all(cmds, addr.cmds)
            local env3 = append_load_info(cmds, env2, dst, shape_scalar(scalar), addr.value, dst.text)
            return pvm.once(Tr.TreeBackExprValue(env3, cmds, dst, scalar))
        end,
        [Tr.ExprField] = function(self, env)
            if pvm.classof(self.field) ~= Sem.FieldByOffset then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "field expression requires resolved offset")) end
            local base = expr_value(expr_to_back:one_uncached(self.base, env))
            if base == nil then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "unsupported field expression base")) end
            local addr = field_addr_from_base_ptr(base, self.field)
            return pvm.once(load_from_field_addr(addr, self.field))
        end,
        [Tr.ExprIndex] = function(self, env)
            local lowered = index_addr_to_back:one_uncached(self.base, self.index, expr_ty(self), env)
            if pvm.classof(lowered) ~= Tr.TreeBackExprValue then return lowered end
            local scalar = back_scalar(expr_ty(self))
            if scalar == nil then return pvm.once(Tr.TreeBackExprUnsupported(lowered.env, lowered.cmds, "index result has non-scalar type")) end
            local env2, dst = env_next_value(lowered.env, "v")
            local cmds = {}; append_all(cmds, lowered.cmds)
            local env3 = append_load_info(cmds, env2, dst, shape_scalar(scalar), lowered.value, dst.text)
            return pvm.once(Tr.TreeBackExprValue(env3, cmds, dst, scalar))
        end,
        [Tr.ExprAgg] = function(_, env) return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "aggregate lowering deferred")) end,
        [Tr.ExprArray] = function(_, env) return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "array lowering deferred")) end,
        [Tr.ExprClosure] = function(_, env) return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "closure lowering deferred")) end,
        [Tr.ExprView] = function(self, env) return view_to_back(self.view, env) end,
        [Tr.ExprLoad] = function(self, env)
            local addr = expr_value(expr_to_back:one_uncached(self.addr, env))
            if addr == nil then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "unsupported load address")) end
            local scalar = back_scalar(self.ty)
            if scalar == nil then return pvm.once(Tr.TreeBackExprUnsupported(addr.env, addr.cmds, "load result has non-scalar type")) end
            local env2, dst = env_next_value(addr.env, "v")
            local cmds = {}; append_all(cmds, addr.cmds)
            local env3 = append_load_info(cmds, env2, dst, shape_scalar(scalar), addr.value, dst.text)
            return pvm.once(Tr.TreeBackExprValue(env3, cmds, dst, scalar))
        end,
        [Tr.ExprSlotValue] = function(_, env) return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "slot expr lowering deferred")) end,
        [Tr.ExprUseExprFrag] = function(_, env) return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "frag expr lowering deferred")) end,
    }, { args_cache = "last" })

    local function cast_to_index(value, current, cmds)
        if value.ty == Back.BackIndex then return current, value.value end
        local env2, dst = env_next_value(current, "v")
        cmds[#cmds + 1] = Back.CmdCast(dst, Back.BackSextend, Back.BackIndex, value.value)
        return env2, dst
    end

    local function const_index(current, cmds, raw)
        local env2, dst = env_next_value(current, "v")
        cmds[#cmds + 1] = Back.CmdConst(dst, Back.BackIndex, Back.BackLitInt(tostring(raw)))
        return env2, dst
    end

    local function const_for_scalar(scalar, raw)
        if scalar == Back.BackBool then return Back.BackLitBool(raw ~= "0" and raw ~= 0 and raw ~= false) end
        return Back.BackLitInt(tostring(raw))
    end

    local function memory_info(access_text, mode)
        return Back.BackMemoryInfo(Back.BackAccessId(access_text), Back.BackAlignUnknown, Back.BackDerefUnknown, Back.BackMayTrap, Back.BackMayNotMove, mode)
    end

    local function append_zero_offset(cmds, current)
        local env1, zero = env_next_value(current, "v")
        cmds[#cmds + 1] = Back.CmdConst(zero, Back.BackIndex, Back.BackLitInt("0"))
        return env1, zero
    end

    local function address_from_ptr(ptr, offset)
        return Back.BackAddress(Back.BackAddrValue(ptr), offset, Back.BackProvUnknown, Back.BackPtrBoundsUnknown)
    end

    append_load_info = function(cmds, current, dst, shape, ptr, access_tag)
        local env1, zero = append_zero_offset(cmds, current)
        cmds[#cmds + 1] = Back.CmdLoadInfo(dst, shape, address_from_ptr(ptr, zero), memory_info("tree:" .. tostring(access_tag or dst.text), Back.BackAccessRead))
        return env1
    end

    append_store_info = function(cmds, current, shape, ptr, value, access_tag)
        local env1, zero = append_zero_offset(cmds, current)
        cmds[#cmds + 1] = Back.CmdStoreInfo(shape, address_from_ptr(ptr, zero), value, memory_info("tree:" .. tostring(access_tag or ptr.text), Back.BackAccessWrite))
        return env1
    end

    local function add_ptr_offset(value, offset)
        if offset == 0 then return value end
        local cmds = {}; append_all(cmds, value.cmds)
        local env1, off_val = env_next_value(value.env, "v")
        local env2, addr_val = env_next_value(env1, "v")
        cmds[#cmds + 1] = Back.CmdConst(off_val, Back.BackIndex, Back.BackLitInt(tostring(offset)))
        cmds[#cmds + 1] = Back.CmdPtrOffset(addr_val, Back.BackAddrValue(value.value), off_val, 1, 0, Back.BackProvDerived("tree byte offset"), Back.BackPtrBoundsUnknown)
        return Tr.TreeBackExprValue(env2, cmds, addr_val, Back.BackPtr)
    end

    field_addr_from_base_ptr = function(base, field)
        return add_ptr_offset(base, field.offset)
    end

    load_from_field_addr = function(addr, field)
        local storage_scalar = field_storage_scalar(field)
        if storage_scalar == nil then return Tr.TreeBackExprUnsupported(addr.env, addr.cmds, "field storage has no scalar backend") end
        local cmds = {}; append_all(cmds, addr.cmds)
        local env1, raw = env_next_value(addr.env, "v")
        local env_load = append_load_info(cmds, env1, raw, shape_scalar(storage_scalar), addr.value, raw.text)
        if not field_is_stored_bool(field) then
            return Tr.TreeBackExprValue(env_load, cmds, raw, storage_scalar)
        end
        local env2, zero = env_next_value(env_load, "v")
        local env3, dst = env_next_value(env2, "v")
        cmds[#cmds + 1] = Back.CmdConst(zero, storage_scalar, const_for_scalar(storage_scalar, "0"))
        cmds[#cmds + 1] = Back.CmdCompare(dst, Back.BackIcmpNe, shape_scalar(storage_scalar), raw, zero)
        return Tr.TreeBackExprValue(env3, cmds, dst, Back.BackBool)
    end

    local function add_scaled_offset(base_view, start, len, elem_ty)
        local cmds = {}; append_all(cmds, base_view.cmds); append_all(cmds, start.cmds); append_all(cmds, len.cmds)
        local current, elem_index = cast_to_index(start, len.env, cmds)
        local stride_value = base_view.stride
        local stride_expr = Tr.TreeBackExprValue(current, {}, stride_value, Back.BackIndex)
        current, stride_value = cast_to_index(stride_expr, current, cmds)
        local mul_env, mul_val = env_next_value(current, "v")
        cmds[#cmds + 1] = Back.CmdIntBinary(mul_val, Back.BackIntMul, Back.BackIndex, int_sem_wrap(), elem_index, stride_value)
        current = mul_env
        elem_index = mul_val
        local size = elem_size(elem_ty)
        if size == nil then return Tr.TreeBackExprUnsupported(len.env, cmds, "unknown window element size") end
        local env1, size_val = env_next_value(current, "v")
        local env2, off_val = env_next_value(env1, "v")
        local env3, data_val = env_next_value(env2, "v")
        cmds[#cmds + 1] = Back.CmdConst(size_val, Back.BackIndex, Back.BackLitInt(tostring(size)))
        cmds[#cmds + 1] = Back.CmdIntBinary(off_val, Back.BackIntMul, Back.BackIndex, int_sem_wrap(), elem_index, size_val)
        cmds[#cmds + 1] = Back.CmdPtrOffset(data_val, Back.BackAddrValue(base_view.data), off_val, 1, 0, Back.BackProvDerived("view window data"), Back.BackPtrBoundsUnknown)
        return Tr.TreeBackExprStridedView(env3, cmds, data_val, len.value, base_view.stride)
    end

    view_to_back = pvm.phase("moon2_tree_view_to_back", {
        [Tr.ViewFromExpr] = function(self, env)
            if pvm.classof(self.base) == Tr.ExprRef and pvm.classof(self.base.ref) == Bn.ValueRefBinding then
                local local_entry = env_lookup(env, self.base.ref.binding)
                if local_entry ~= nil and pvm.classof(local_entry) == Tr.TreeBackViewLocal then
                    local cmds = {}
                    local env1, stride = const_index(env, cmds, 1)
                    return pvm.once(Tr.TreeBackExprStridedView(env1, cmds, local_entry.data, local_entry.len, stride))
                end
                if local_entry ~= nil and pvm.classof(local_entry) == Tr.TreeBackStridedViewLocal then return pvm.once(Tr.TreeBackExprStridedView(env, {}, local_entry.data, local_entry.len, local_entry.stride)) end
            end
            local base = expr_value(expr_to_back:one_uncached(self.base, env))
            if base ~= nil and base.ty == Back.BackPtr then
                local cmds = {}; append_all(cmds, base.cmds)
                local current, len = const_index(base.env, cmds, 0)
                local current2, stride = const_index(current, cmds, 1)
                return pvm.once(Tr.TreeBackExprStridedView(current2, cmds, base.value, len, stride))
            end
            return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "view-from-expression lowering requires a local view binding or pointer"))
        end,
        [Tr.ViewContiguous] = function(self, env)
            local data = expr_value(expr_to_back:one_uncached(self.data, env))
            if data == nil then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "unsupported view data")) end
            local len = expr_value(expr_to_back:one_uncached(self.len, data.env))
            if len == nil then return pvm.once(Tr.TreeBackExprUnsupported(data.env, data.cmds, "unsupported view len")) end
            local cmds = {}; append_all(cmds, data.cmds); append_all(cmds, len.cmds)
            local current, len_value = cast_to_index(len, len.env, cmds)
            local current2, stride_value = const_index(current, cmds, 1)
            return pvm.once(Tr.TreeBackExprStridedView(current2, cmds, data.value, len_value, stride_value))
        end,
        [Tr.ViewStrided] = function(self, env)
            local data = expr_value(expr_to_back:one_uncached(self.data, env))
            if data == nil then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "unsupported view data")) end
            local len = expr_value(expr_to_back:one_uncached(self.len, data.env))
            if len == nil then return pvm.once(Tr.TreeBackExprUnsupported(data.env, data.cmds, "unsupported view len")) end
            local stride = expr_value(expr_to_back:one_uncached(self.stride, len.env))
            if stride == nil then local cmds = {}; append_all(cmds, data.cmds); append_all(cmds, len.cmds); return pvm.once(Tr.TreeBackExprUnsupported(len.env, cmds, "unsupported view stride")) end
            local cmds = {}; append_all(cmds, data.cmds); append_all(cmds, len.cmds); append_all(cmds, stride.cmds)
            local current, len_value = cast_to_index(len, stride.env, cmds)
            local current2, stride_value = cast_to_index(stride, current, cmds)
            return pvm.once(Tr.TreeBackExprStridedView(current2, cmds, data.value, len_value, stride_value))
        end,
        [Tr.ViewWindow] = function(self, env)
            local base_view = expr_view_value(view_to_back:one_uncached(self.base, env))
            if base_view == nil then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "unsupported window base view")) end
            local start = expr_value(expr_to_back:one_uncached(self.start, base_view.env))
            if start == nil then return pvm.once(Tr.TreeBackExprUnsupported(base_view.env, base_view.cmds, "unsupported window start")) end
            local len = expr_value(expr_to_back:one_uncached(self.len, start.env))
            if len == nil then local cmds = {}; append_all(cmds, base_view.cmds); append_all(cmds, start.cmds); return pvm.once(Tr.TreeBackExprUnsupported(start.env, cmds, "unsupported window len")) end
            return pvm.once(add_scaled_offset(base_view, start, len, view_elem(self)))
        end,
        [Tr.ViewRestrided] = function(_, env) return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "restrided view lowering deferred")) end,
        [Tr.ViewRowBase] = function(_, env) return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "row-base view lowering deferred")) end,
        [Tr.ViewInterleaved] = function(_, env) return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "interleaved view lowering deferred")) end,
        [Tr.ViewInterleavedView] = function(_, env) return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "interleaved-view lowering deferred")) end,
    }, { args_cache = "last" })

    local function view_base_expr(view)
        local cls = pvm.classof(view)
        if cls == Tr.ViewFromExpr then return view.base end
        if cls == Tr.ViewContiguous then return view.data end
        return nil
    end

    local function view_base_to_back(view, env)
        local base_expr = view_base_expr(view)
        if base_expr == nil then return nil end
        if pvm.classof(base_expr) == Tr.ExprRef and pvm.classof(base_expr.ref) == Bn.ValueRefBinding then
            local local_entry = env_lookup(env, base_expr.ref.binding)
            if local_entry ~= nil and (pvm.classof(local_entry) == Tr.TreeBackViewLocal or pvm.classof(local_entry) == Tr.TreeBackStridedViewLocal) then return Tr.TreeBackExprValue(env, {}, local_entry.data, Back.BackPtr) end
        end
        return expr_value(expr_to_back:one_uncached(base_expr, env))
    end

    local function view_stride_to_back(view, env)
        local cls = pvm.classof(view)
        if cls == Tr.ViewStrided then return expr_value(expr_to_back:one_uncached(view.stride, env)) end
        local base_expr = view_base_expr(view)
        if base_expr ~= nil and pvm.classof(base_expr) == Tr.ExprRef and pvm.classof(base_expr.ref) == Bn.ValueRefBinding then
            local local_entry = env_lookup(env, base_expr.ref.binding)
            if local_entry ~= nil and pvm.classof(local_entry) == Tr.TreeBackStridedViewLocal then return Tr.TreeBackExprValue(env, {}, local_entry.stride, Back.BackIndex) end
        end
        return nil
    end

    index_addr_to_back = pvm.phase("moon2_tree_index_addr_to_back", {
        [Tr.IndexBaseView] = function(self, index, elem_ty, env)
            local view = expr_view_value(view_to_back:one_uncached(self.view, env))
            if view == nil then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "unsupported index base")) end
            local idx = expr_value(expr_to_back:one_uncached(index, view.env))
            if idx == nil then return pvm.once(Tr.TreeBackExprUnsupported(view.env, view.cmds, "unsupported index value")) end
            local size = elem_size(elem_ty)
            if size == nil then return pvm.once(Tr.TreeBackExprUnsupported(idx.env, idx.cmds, "unknown indexed element size")) end
            local current = idx.env
            local index_value = idx.value
            local cmds = {}; append_all(cmds, view.cmds); append_all(cmds, idx.cmds)
            if idx.ty ~= Back.BackIndex then
                local cast_env, cast_val = env_next_value(current, "v")
                cmds[#cmds + 1] = Back.CmdCast(cast_val, Back.BackSextend, Back.BackIndex, idx.value)
                current = cast_env
                index_value = cast_val
            end
            local stride_value = view.stride
            local mul_env, mul_val = env_next_value(current, "v")
            cmds[#cmds + 1] = Back.CmdIntBinary(mul_val, Back.BackIntMul, Back.BackIndex, int_sem_wrap(), index_value, stride_value)
            current = mul_env
            index_value = mul_val
            local env1, size_val = env_next_value(current, "v")
            local env2, off_val = env_next_value(env1, "v")
            local env3, addr_val = env_next_value(env2, "v")
            cmds[#cmds + 1] = Back.CmdConst(size_val, Back.BackIndex, Back.BackLitInt(tostring(size)))
            cmds[#cmds + 1] = Back.CmdIntBinary(off_val, Back.BackIntMul, Back.BackIndex, int_sem_wrap(), index_value, size_val)
            cmds[#cmds + 1] = Back.CmdPtrOffset(addr_val, Back.BackAddrValue(view.data), off_val, 1, 0, Back.BackProvDerived("view index address"), Back.BackPtrBoundsUnknown)
            return pvm.once(Tr.TreeBackExprValue(env3, cmds, addr_val, Back.BackPtr))
        end,
        [Tr.IndexBasePlace] = function(_, _, _, env) return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "place index address lowering deferred")) end,
        [Tr.IndexBaseExpr] = function(_, _, _, env) return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "untyped index base reached backend")) end,
    }, { args_cache = "last" })

    place_addr_to_back = pvm.phase("moon2_tree_place_addr_to_back", {
        [Tr.PlaceIndex] = function(self, env)
            return index_addr_to_back(self.base, self.index, self.h.ty, env)
        end,
        [Tr.PlaceDeref] = function(self, env)
            local addr = expr_value(expr_to_back:one_uncached(self.base, env))
            if addr == nil then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "unsupported deref place address")) end
            return pvm.once(addr)
        end,
        [Tr.PlaceField] = function(self, env)
            local field = self.field
            if pvm.classof(field) ~= Sem.FieldByOffset then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "field address requires resolved offset")) end
            local base = expr_value(place_addr_to_back:one_uncached(self.base, env))
            if base == nil then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "unsupported field base address")) end
            return pvm.once(field_addr_from_base_ptr(base, field))
        end,
        [Tr.PlaceRef] = function(_, env) return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "address of scalar binding lowering deferred")) end,
        [Tr.PlaceDot] = function(_, env) return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "dot place address lowering deferred")) end,
        [Tr.PlaceSlotValue] = function(_, env) return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "slot place address lowering deferred")) end,
    }, { args_cache = "last" })

    local function store_at_addr(place, value, env)
        local addr = expr_value(place_addr_to_back:one_uncached(place, env))
        if addr == nil then return pvm.once(Tr.TreeBackStmtResult(env, { Back.CmdTrap }, Back.BackTerminates)) end
        local rhs = expr_value(expr_to_back:one_uncached(value, addr.env))
        if rhs == nil then return pvm.once(Tr.TreeBackStmtResult(addr.env, addr.cmds, Back.BackTerminates)) end
        local field = pvm.classof(place) == Tr.PlaceField and place.field or nil
        local scalar = field and field_storage_scalar(field) or back_scalar(place.h.ty)
        if scalar == nil then return pvm.once(Tr.TreeBackStmtResult(rhs.env, rhs.cmds, Back.BackTerminates)) end
        local cmds = {}; append_all(cmds, addr.cmds); append_all(cmds, rhs.cmds)
        local store_value = rhs.value
        local current = rhs.env
        if field ~= nil and field_is_stored_bool(field) and scalar ~= Back.BackBool then
            local env1, one_val = env_next_value(current, "v")
            local env2, zero_val = env_next_value(env1, "v")
            local env3, encoded = env_next_value(env2, "v")
            cmds[#cmds + 1] = Back.CmdConst(one_val, scalar, const_for_scalar(scalar, "1"))
            cmds[#cmds + 1] = Back.CmdConst(zero_val, scalar, const_for_scalar(scalar, "0"))
            cmds[#cmds + 1] = Back.CmdSelect(encoded, shape_scalar(scalar), rhs.value, one_val, zero_val)
            store_value = encoded
            current = env3
        end
        current = append_store_info(cmds, current, shape_scalar(scalar), addr.value, store_value, tostring(addr.value.text) .. ":store")
        return pvm.once(Tr.TreeBackStmtResult(current, cmds, Back.BackFallsThrough))
    end

    place_store_to_back = pvm.phase("moon2_tree_place_store_to_back", {
        [Tr.PlaceIndex] = function(self, value, env) return store_at_addr(self, value, env) end,
        [Tr.PlaceDeref] = function(self, value, env) return store_at_addr(self, value, env) end,
        [Tr.PlaceField] = function(self, value, env) return store_at_addr(self, value, env) end,
        [Tr.PlaceRef] = function(_, _, env) return pvm.once(Tr.TreeBackStmtResult(env, {}, Back.BackFallsThrough)) end,
        [Tr.PlaceDot] = function(_, _, env) return pvm.once(Tr.TreeBackStmtResult(env, { Back.CmdTrap }, Back.BackTerminates)) end,
        [Tr.PlaceSlotValue] = function(_, _, env) return pvm.once(Tr.TreeBackStmtResult(env, { Back.CmdTrap }, Back.BackTerminates)) end,
    }, { args_cache = "last" })

    local function lower_if_stmt(self, env)
        local cond = expr_value(expr_to_back:one_uncached(self.cond, env))
        if cond == nil then return pvm.once(Tr.TreeBackStmtResult(env, { Back.CmdTrap }, Back.BackTerminates)) end

        local env1, then_block = env_next_block(cond.env, "if.then")
        local env2, else_block = env_next_block(env1, "if.else")
        local env3, join_block = env_next_block(env2, "if.join")
        local cmds = {}
        append_all(cmds, cond.cmds)
        cmds[#cmds + 1] = Back.CmdCreateBlock(then_block)
        cmds[#cmds + 1] = Back.CmdCreateBlock(else_block)
        cmds[#cmds + 1] = Back.CmdCreateBlock(join_block)
        cmds[#cmds + 1] = Back.CmdBrIf(cond.value, then_block, {}, else_block, {})
        cmds[#cmds + 1] = Back.CmdSealBlock(then_block)
        cmds[#cmds + 1] = Back.CmdSealBlock(else_block)

        cmds[#cmds + 1] = Back.CmdSwitchToBlock(then_block)
        local then_start = env_with_locals(env3, env.locals)
        local then_env, then_cmds, then_flow = lower_body(self.then_body, then_start)
        append_all(cmds, then_cmds)
        if then_flow ~= Back.BackTerminates then cmds[#cmds + 1] = Back.CmdJump(join_block, {}) end

        cmds[#cmds + 1] = Back.CmdSwitchToBlock(else_block)
        local else_start = env_with_locals(env_with_counters(env, then_env), env.locals)
        local else_env, else_cmds, else_flow = lower_body(self.else_body, else_start)
        append_all(cmds, else_cmds)
        if else_flow ~= Back.BackTerminates then cmds[#cmds + 1] = Back.CmdJump(join_block, {}) end

        local out_env = env_with_locals(env_with_counters(env, else_env), env.locals)
        cmds[#cmds + 1] = Back.CmdSealBlock(join_block)
        if then_flow ~= Back.BackTerminates or else_flow ~= Back.BackTerminates then
            cmds[#cmds + 1] = Back.CmdSwitchToBlock(join_block)
            return pvm.once(Tr.TreeBackStmtResult(out_env, cmds, Back.BackFallsThrough))
        end
        return pvm.once(Tr.TreeBackStmtResult(out_env, cmds, Back.BackTerminates))
    end

    stmt_to_back = pvm.phase("moon2_tree_stmt_to_back", {
        [Tr.StmtLet] = function(self, env)
            local lowered = expr_to_back:one_uncached(self.init, env)
            local view_init = expr_view_value(lowered)
            if view_init ~= nil then
                if not is_view_type(self.binding.ty) then return pvm.once(Tr.TreeBackStmtResult(view_init.env, { Back.CmdTrap }, Back.BackTerminates)) end
                local env2
                if pvm.classof(view_init) == Tr.TreeBackExprStridedView then env2 = env_add_strided_view(view_init.env, self.binding, view_init.data, view_init.len, view_init.stride)
                else env2 = env_add_view(view_init.env, self.binding, view_init.data, view_init.len) end
                return pvm.once(Tr.TreeBackStmtResult(env2, view_init.cmds, Back.BackFallsThrough))
            end
            local init = expr_value(lowered)
            if init == nil then return pvm.once(Tr.TreeBackStmtResult(env, { Back.CmdTrap }, Back.BackTerminates)) end
            local scalar = back_scalar(self.binding.ty) or init.ty
            local env2 = env_add(init.env, self.binding, init.value, scalar)
            return pvm.once(Tr.TreeBackStmtResult(env2, init.cmds, Back.BackFallsThrough))
        end,
        [Tr.StmtExpr] = function(self, env)
            local result = expr_value(expr_to_back:one_uncached(self.expr, env))
            if result == nil then return pvm.once(Tr.TreeBackStmtResult(env, {}, Back.BackFallsThrough)) end
            return pvm.once(Tr.TreeBackStmtResult(result.env, result.cmds, Back.BackFallsThrough))
        end,
        [Tr.StmtReturnValue] = function(self, env)
            local lowered = expr_to_back:one_uncached(self.value, env)
            local view = expr_view_value(lowered)
            if view ~= nil and pvm.classof(env.ret) == Tr.TreeBackReturnView then
                local cmds = {}; append_all(cmds, view.cmds)
                local out = env.ret.out
                local out_value = Tr.TreeBackExprValue(view.env, cmds, out, Back.BackPtr)
                local len_addr = add_ptr_offset(out_value, 8)
                cmds = len_addr.cmds
                local stride_addr = add_ptr_offset(Tr.TreeBackExprValue(len_addr.env, cmds, out, Back.BackPtr), 16)
                cmds = stride_addr.cmds
                local current = append_store_info(cmds, stride_addr.env, shape_scalar(Back.BackPtr), out, view.data, tostring(out.text) .. ":data")
                current = append_store_info(cmds, current, shape_scalar(Back.BackIndex), len_addr.value, view.len, tostring(out.text) .. ":len")
                current = append_store_info(cmds, current, shape_scalar(Back.BackIndex), stride_addr.value, view.stride, tostring(out.text) .. ":stride")
                cmds[#cmds + 1] = Back.CmdReturnVoid
                return pvm.once(Tr.TreeBackStmtResult(current, cmds, Back.BackTerminates))
            end
            local value = expr_value(lowered)
            if value == nil then return pvm.once(Tr.TreeBackStmtResult(env, { Back.CmdTrap }, Back.BackTerminates)) end
            local cmds = {}; append_all(cmds, value.cmds); cmds[#cmds + 1] = Back.CmdReturnValue(value.value)
            return pvm.once(Tr.TreeBackStmtResult(value.env, cmds, Back.BackTerminates))
        end,
        [Tr.StmtReturnVoid] = function(_, env) return pvm.once(Tr.TreeBackStmtResult(env, { Back.CmdReturnVoid }, Back.BackTerminates)) end,
        [Tr.StmtVar] = function(self, env) return stmt_to_back(Tr.StmtLet(self.h, self.binding, self.init), env) end,
        [Tr.StmtSet] = function(self, env) return place_store_to_back(self.place, self.value, env) end,
        [Tr.StmtAssert] = function(_, env) return pvm.once(Tr.TreeBackStmtResult(env, {}, Back.BackFallsThrough)) end,
        [Tr.StmtIf] = lower_if_stmt,
        [Tr.StmtSwitch] = function(_, env) return pvm.once(Tr.TreeBackStmtResult(env, { Back.CmdTrap }, Back.BackTerminates)) end,
        [Tr.StmtJump] = function(_, env) return pvm.once(Tr.TreeBackStmtResult(env, { Back.CmdTrap }, Back.BackTerminates)) end,
        [Tr.StmtJumpCont] = function(_, env) return pvm.once(Tr.TreeBackStmtResult(env, { Back.CmdTrap }, Back.BackTerminates)) end,
        [Tr.StmtYieldVoid] = function(_, env) return pvm.once(Tr.TreeBackStmtResult(env, { Back.CmdTrap }, Back.BackTerminates)) end,
        [Tr.StmtYieldValue] = function(_, env) return pvm.once(Tr.TreeBackStmtResult(env, { Back.CmdTrap }, Back.BackTerminates)) end,
        [Tr.StmtControl] = function(self, env) return control_api.stmt_region_to_back(self.region, env) end,
        [Tr.StmtUseRegionSlot] = function(_, env) return pvm.once(Tr.TreeBackStmtResult(env, {}, Back.BackFallsThrough)) end,
        [Tr.StmtUseRegionFrag] = function(_, env) return pvm.once(Tr.TreeBackStmtResult(env, {}, Back.BackFallsThrough)) end,
    }, { args_cache = "last" })

    lower_body = function(stmts, env)
        local current = env
        local cmds = {}
        local flow = Back.BackFallsThrough
        for i = 1, #stmts do
            if flow == Back.BackTerminates then break end
            local result = stmt_to_back:one_uncached(stmts[i], current)
            append_all(cmds, result.cmds)
            current = result.env
            flow = result.flow
        end
        return current, cmds, flow
    end

    control_api = require("moonlift.tree_control_to_back").Define(T, {
        env_add = env_add,
        env_with_locals = env_with_locals,
        env_with_counters = env_with_counters,
        env_next_block = env_next_block,
        expr_to_back = expr_to_back,
        stmt_to_back = stmt_to_back,
        back_scalar = back_scalar,
    })

    local function abi_param_scalars(plan)
        local ps = {}
        if pvm.classof(plan.result) == Ty.AbiResultView then ps[#ps + 1] = Back.BackPtr end
        for i = 1, #plan.params do
            local param = plan.params[i]
            local cls = pvm.classof(param)
            if cls == Ty.AbiParamScalar then
                ps[#ps + 1] = param.scalar
            elseif cls == Ty.AbiParamView then
                ps[#ps + 1] = Back.BackPtr
                ps[#ps + 1] = Back.BackIndex
                ps[#ps + 1] = Back.BackIndex
            end
        end
        return ps
    end

    local function abi_result_scalars(plan)
        if pvm.classof(plan.result) == Ty.AbiResultScalar then return { plan.result.scalar } end
        return {}
    end

    local function abi_param_values(plan)
        local values = {}
        if pvm.classof(plan.result) == Ty.AbiResultView then values[#values + 1] = plan.result.out end
        for i = 1, #plan.params do
            local param = plan.params[i]
            local cls = pvm.classof(param)
            if cls == Ty.AbiParamScalar then
                values[#values + 1] = param.value
            elseif cls == Ty.AbiParamView then
                values[#values + 1] = param.data
                values[#values + 1] = param.len
                values[#values + 1] = param.stride
            end
        end
        return values
    end

    local function env_from_abi_params(plan)
        local ret = Tr.TreeBackReturnScalar
        if pvm.classof(plan.result) == Ty.AbiResultView then ret = Tr.TreeBackReturnView(plan.result.out) end
        local env = env_empty(ret)
        for i = 1, #plan.params do
            local param = plan.params[i]
            local cls = pvm.classof(param)
            if cls == Ty.AbiParamScalar then
                env = env_add(env, param.binding, param.value, param.scalar)
            elseif cls == Ty.AbiParamView then
                env = env_add_strided_view(env, param.binding, param.data, param.len, param.stride)
            end
        end
        return env
    end

    local function func_sig(params, result)
        local plan = abi_api.plan("extern", params, result)
        return abi_param_scalars(plan), abi_result_scalars(plan)
    end

    local function has_view_param(params)
        for i = 1, #(params or {}) do if pvm.classof(params[i].ty) == Ty.TView then return true end end
        return false
    end

    local function public_host_param_scalars(params, result_ty)
        local ps = {}
        if pvm.classof(result_ty) == Ty.TView then ps[#ps + 1] = Back.BackPtr end
        for i = 1, #(params or {}) do
            if pvm.classof(params[i].ty) == Ty.TView then
                ps[#ps + 1] = Back.BackPtr
            else
                local scalar = back_scalar(params[i].ty)
                if scalar ~= nil and scalar ~= Back.BackVoid then ps[#ps + 1] = scalar end
            end
        end
        return ps
    end

    local function descriptor_field_load(cmds, current, desc, field_name, offset, scalar)
        local addr = desc
        if offset ~= 0 then
            local env1, off_val = env_next_value(current, "v")
            local env2, addr_val = env_next_value(env1, "v")
            cmds[#cmds + 1] = Back.CmdConst(off_val, Back.BackIndex, Back.BackLitInt(tostring(offset)))
            cmds[#cmds + 1] = Back.CmdPtrOffset(addr_val, Back.BackAddrValue(desc), off_val, 1, 0, Back.BackProvDerived("descriptor " .. field_name), Back.BackPtrBoundsUnknown)
            current, addr = env2, addr_val
        end
        local env3, value = env_next_value(current, "v")
        local env4 = append_load_info(cmds, env3, value, shape_scalar(scalar), addr, "descriptor:" .. tostring(desc.text) .. ":" .. field_name)
        return env4, value
    end

    local function lower_host_export_wrapper(public_name, inner_name, params, result_ty)
        local public_sig = Back.BackSigId("sig:" .. public_name)
        local inner_sig = Back.BackSigId("sig:" .. inner_name)
        local public_func = Back.BackFuncId(public_name)
        local inner_func = Back.BackFuncId(inner_name)
        local entry = Back.BackBlockId("entry:" .. public_name)
        local public_params = public_host_param_scalars(params, result_ty)
        local result_scalars = {}
        if pvm.classof(result_ty) ~= Ty.TView then
            local scalar = back_scalar(result_ty)
            if scalar ~= nil and scalar ~= Back.BackVoid then result_scalars[#result_scalars + 1] = scalar end
        end
        local arg_values, inner_args = {}, {}
        if pvm.classof(result_ty) == Ty.TView then
            local out = Back.BackValId("arg:" .. public_name .. ":return:out")
            arg_values[#arg_values + 1] = out
            inner_args[#inner_args + 1] = out
        end
        local cmds = {
            Back.CmdCreateSig(public_sig, public_params, result_scalars),
            Back.CmdDeclareFunc(C.VisibilityExport, public_func, public_sig),
            Back.CmdBeginFunc(public_func),
            Back.CmdCreateBlock(entry),
            Back.CmdSwitchToBlock(entry),
        }
        local load_cmds = {}
        local current = env_empty()
        for i = 1, #(params or {}) do
            local param = params[i]
            if pvm.classof(param.ty) == Ty.TView then
                local desc = Back.BackValId("arg:" .. public_name .. ":" .. param.name .. ":descriptor")
                arg_values[#arg_values + 1] = desc
                local data, len, stride
                current, data = descriptor_field_load(load_cmds, current, desc, "data", 0, Back.BackPtr)
                current, len = descriptor_field_load(load_cmds, current, desc, "len", 8, Back.BackIndex)
                current, stride = descriptor_field_load(load_cmds, current, desc, "stride", 16, Back.BackIndex)
                inner_args[#inner_args + 1] = data
                inner_args[#inner_args + 1] = len
                inner_args[#inner_args + 1] = stride
            else
                local value = Back.BackValId("arg:" .. public_name .. ":" .. param.name)
                arg_values[#arg_values + 1] = value
                inner_args[#inner_args + 1] = value
            end
        end
        cmds[#cmds + 1] = Back.CmdBindEntryParams(entry, arg_values)
        append_all(cmds, load_cmds)
        if #result_scalars == 1 then
            local env2, dst = env_next_value(current, "v")
            cmds[#cmds + 1] = Back.CmdCall(Back.BackCallValue(dst, result_scalars[1]), Back.BackCallDirect(inner_func), inner_sig, inner_args)
            cmds[#cmds + 1] = Back.CmdReturnValue(dst)
            current = env2
        else
            cmds[#cmds + 1] = Back.CmdCall(Back.BackCallStmt, Back.BackCallDirect(inner_func), inner_sig, inner_args)
            cmds[#cmds + 1] = Back.CmdReturnVoid
        end
        cmds[#cmds + 1] = Back.CmdSealBlock(entry)
        cmds[#cmds + 1] = Back.CmdFinishFunc(public_func)
        return Tr.TreeBackFuncResult(cmds)
    end

    -- Vector kernel recognition/lowering lives in vec_kernel_plan.lua and vec_kernel_to_back.lua.

    try_vector_func = function(name, visibility, params, result_ty, body, contracts)
        local plan = vec_kernel_plan_api.plan(name, visibility, params, result_ty, body, contracts or {})
        return vec_kernel_to_back_api.lower_func(name, visibility, params, result_ty, plan)
    end

    local function lower_func_common(name, visibility, params, result_ty, body, contracts)
        if visibility == C.VisibilityExport and has_view_param(params) then
            local inner_name = name .. "__moon_inner"
            local inner = lower_func_common(inner_name, C.VisibilityLocal, params, result_ty, body, contracts or {})
            local wrapper = lower_host_export_wrapper(name, inner_name, params, result_ty)
            local cmds = {}
            append_all(cmds, inner.cmds)
            append_all(cmds, wrapper.cmds)
            return Tr.TreeBackFuncResult(cmds)
        end
        local vectorized = try_vector_func(name, visibility, params, result_ty, body, contracts or {})
        if vectorized ~= nil then return vectorized end
        local sig = Back.BackSigId("sig:" .. name)
        local func = Back.BackFuncId(name)
        local entry = Back.BackBlockId("entry:" .. name)
        local abi_plan = abi_api.plan(name, params, result_ty)
        local param_scalars, result_scalars = abi_param_scalars(abi_plan), abi_result_scalars(abi_plan)
        local env = env_from_abi_params(abi_plan)
        local param_vals = abi_param_values(abi_plan)
        local _, body_cmds, flow = lower_body(body, env)
        local cmds = {
            Back.CmdCreateSig(sig, param_scalars, result_scalars),
            Back.CmdDeclareFunc(visibility, func, sig),
            Back.CmdBeginFunc(func),
            Back.CmdCreateBlock(entry),
            Back.CmdSwitchToBlock(entry),
            Back.CmdBindEntryParams(entry, param_vals),
        }
        append_all(cmds, body_cmds)
        if flow ~= Back.BackTerminates then
            if #result_scalars == 0 then cmds[#cmds + 1] = Back.CmdReturnVoid else cmds[#cmds + 1] = Back.CmdTrap end
        end
        cmds[#cmds + 1] = Back.CmdSealBlock(entry)
        cmds[#cmds + 1] = Back.CmdFinishFunc(func)
        return Tr.TreeBackFuncResult(cmds)
    end

    local function lower_func_direct(func_node)
        local cls = pvm.classof(func_node)
        if cls == Tr.FuncLocal then return lower_func_common(func_node.name, C.VisibilityLocal, func_node.params, func_node.result, func_node.body) end
        if cls == Tr.FuncExport then return lower_func_common(func_node.name, C.VisibilityExport, func_node.params, func_node.result, func_node.body) end
        if cls == Tr.FuncLocalContract then return lower_func_common(func_node.name, C.VisibilityLocal, func_node.params, func_node.result, func_node.body, contract_api.facts(func_node).facts) end
        if cls == Tr.FuncExportContract then return lower_func_common(func_node.name, C.VisibilityExport, func_node.params, func_node.result, func_node.body, contract_api.facts(func_node).facts) end
        if cls == Tr.FuncOpen then return lower_func_common(func_node.sym.name, func_node.visibility, {}, func_node.result, func_node.body) end
        return Tr.TreeBackFuncResult({})
    end

    local function lower_extern_direct(func_node)
        local cls = pvm.classof(func_node)
        if cls == Tr.ExternFunc then
            local sig = Back.BackSigId("sig:extern:" .. func_node.name)
            local ps, rs = func_sig(func_node.params, func_node.result)
            return Tr.TreeBackItemResult({ Back.CmdCreateSig(sig, ps, rs), Back.CmdDeclareExtern(Back.BackExternId(func_node.name), func_node.symbol, sig) })
        end
        if cls == Tr.ExternFuncOpen then
            local sig = Back.BackSigId("sig:extern:" .. func_node.sym.name)
            local result_scalar = back_scalar(func_node.result)
            local rs = {}
            if result_scalar ~= nil and result_scalar ~= Back.BackVoid then rs[#rs + 1] = result_scalar end
            return Tr.TreeBackItemResult({ Back.CmdCreateSig(sig, {}, rs), Back.CmdDeclareExtern(Back.BackExternId(func_node.sym.name), func_node.sym.symbol, sig) })
        end
        return Tr.TreeBackItemResult({})
    end

    local lower_item_direct
    local lower_module_direct

    lower_item_direct = function(item)
        local cls = pvm.classof(item)
        if cls == Tr.ItemFunc then return Tr.TreeBackItemResult(lower_func_direct(item.func).cmds) end
        if cls == Tr.ItemExtern then return lower_extern_direct(item.func) end
        if cls == Tr.ItemUseModule then return Tr.TreeBackItemResult(lower_module_direct(item.module).cmds) end
        return Tr.TreeBackItemResult({})
    end

    lower_module_direct = function(module)
        local cmds = {}
        for i = 1, #module.items do append_all(cmds, lower_item_direct(module.items[i]).cmds) end
        cmds[#cmds + 1] = Back.CmdFinalizeModule
        return Back.BackProgram(cmds)
    end

    func_to_back = pvm.phase("moon2_tree_func_to_back", function(self) return lower_func_direct(self) end)
    extern_to_back = pvm.phase("moon2_tree_extern_to_back", function(self) return lower_extern_direct(self) end)
    item_to_back = pvm.phase("moon2_tree_item_to_back", function(self) return lower_item_direct(self) end)
    module_to_back = pvm.phase("moon2_tree_module_to_back", function(module) return lower_module_direct(module) end)

    return {
        env_empty = env_empty,
        expr_to_back = expr_to_back,
        stmt_to_back = stmt_to_back,
        func_to_back = func_to_back,
        item_to_back = item_to_back,
        module_to_back = module_to_back,
        func_direct = lower_func_direct,
        item_direct = lower_item_direct,
        module_direct = lower_module_direct,
        module = lower_module_direct,
    }
end

return M
