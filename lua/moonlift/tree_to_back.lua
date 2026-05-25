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
    local O = T.MoonOpen

    local scalar_api = require("moonlift.type_to_back_scalar").Define(T)
    local layout_api = require("moonlift.type_size_align").Define(T)
    local vec_kernel_plan_api = require("moonlift.vec_kernel_plan").Define(T)
    local vec_kernel_to_back_api = require("moonlift.vec_kernel_to_back").Define(T)
    local contract_api = require("moonlift.tree_contract_facts").Define(T)
    local abi_api = require("moonlift.type_func_abi_plan").Define(T)
    local module_type_api = require("moonlift.tree_module_type").Define(T)
    local const_eval_api = require("moonlift.sem_const_eval").Define(T)
    local BackProvenance = require("moonlift.back_provenance")

    local lower_context = { const_env = Bn.ConstEnv({}), globals = {}, provenance = nil }

    local expr_type
    local scalar_literal
    local unary_op
    local binary_cmd
    local compare_op
    local intrinsic_op
    local machine_cast_op
    local surface_cast_op
    local call_target
    local expr_to_back
    local field_addr_from_base_ptr
    local load_from_field_addr
    local view_to_back
    local index_addr_to_back
    local place_addr_to_back
    local expr_base_addr_to_back
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
    local append_zero_offset
    local memory_info
    local address_from_ptr
    local address_from_data
    local atomic_ordering
    local atomic_rmw_op
    local global_data_addr
    local load_global_data
    local store_global_data
    local append_memcpy
    local descriptor_field_load
    local lower_closure_call

    local function env_empty(ret)
        return Tr.TreeBackEnv({}, 0, 0, ret or Tr.TreeBackReturnScalar)
    end

    local function global_key(module_name, item_name)
        return tostring(module_name or "") .. "\0" .. tostring(item_name or "")
    end

    local function data_id_for_global(module_name, item_name)
        return Back.BackDataId("data:" .. tostring(module_name or "") .. ":" .. tostring(item_name or ""))
    end

    local function env_add(env, binding, value, ty)
        local locals = {}
        for i = 1, #env.locals do locals[#locals + 1] = env.locals[i] end
        locals[#locals + 1] = Tr.TreeBackScalarLocal(binding, value, ty)
        return Tr.TreeBackEnv(locals, env.next_value, env.next_block, env.ret)
    end

    local function env_add_stack(env, binding, slot, ty)
        local locals = {}
        for i = 1, #env.locals do locals[#locals + 1] = env.locals[i] end
        locals[#locals + 1] = Tr.TreeBackStackLocal(binding, slot, ty)
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

    local function binding_key(binding)
        return tostring(binding.id and binding.id.text or binding.name)
    end

    local collect_address_taken_stmts
    local collect_address_taken_expr
    local collect_address_taken_place

    local function mark_addressed_place(place, out)
        if place == nil then return end
        local cls = pvm.classof(place)
        if cls == Tr.PlaceRef and pvm.classof(place.ref) == Bn.ValueRefBinding then
            local binding = place.ref.binding
            if binding.class == Bn.BindingClassLocalCell or binding.class == Bn.BindingClassLocalValue then out[binding_key(binding)] = true end
        elseif cls == Tr.PlaceField or cls == Tr.PlaceDot then
            mark_addressed_place(place.base, out)
        elseif cls == Tr.PlaceIndex then
            if pvm.classof(place.base) == Tr.IndexBasePlace then mark_addressed_place(place.base.place, out) end
        end
    end

    collect_address_taken_place = function(place, out)
        if place == nil then return end
        local cls = pvm.classof(place)
        if cls == Tr.PlaceDeref then collect_address_taken_expr(place.base, out)
        elseif cls == Tr.PlaceField or cls == Tr.PlaceDot then collect_address_taken_place(place.base, out)
        elseif cls == Tr.PlaceIndex then
            local bcls = pvm.classof(place.base)
            if bcls == Tr.IndexBaseExpr then collect_address_taken_expr(place.base.expr, out)
            elseif bcls == Tr.IndexBaseView then collect_address_taken_expr(place.base.view.base, out)
            elseif bcls == Tr.IndexBasePlace then collect_address_taken_place(place.base.place, out) end
            collect_address_taken_expr(place.index, out)
        end
    end

    collect_address_taken_expr = function(expr, out)
        if expr == nil then return end
        local cls = pvm.classof(expr)
        if cls == Tr.ExprAddrOf then mark_addressed_place(expr.place, out); collect_address_taken_place(expr.place, out)
        elseif cls == Tr.ExprUnary or cls == Tr.ExprDeref or cls == Tr.ExprLen then collect_address_taken_expr(expr.value or expr.base, out)
        elseif cls == Tr.ExprBinary or cls == Tr.ExprCompare or cls == Tr.ExprLogic then collect_address_taken_expr(expr.lhs, out); collect_address_taken_expr(expr.rhs, out)
        elseif cls == Tr.ExprCast or cls == Tr.ExprMachineCast or cls == Tr.ExprLoad or cls == Tr.ExprAtomicLoad then collect_address_taken_expr(expr.value or expr.addr, out)
        elseif cls == Tr.ExprAtomicRmw then collect_address_taken_expr(expr.addr, out); collect_address_taken_expr(expr.value, out)
        elseif cls == Tr.ExprAtomicCas then collect_address_taken_expr(expr.addr, out); collect_address_taken_expr(expr.expected, out); collect_address_taken_expr(expr.replacement, out)
        elseif cls == Tr.ExprCall then
            collect_address_taken_expr(expr.callee, out)
            for i = 1, #expr.args do collect_address_taken_expr(expr.args[i], out) end
        elseif cls == Tr.ExprField or cls == Tr.ExprDot then collect_address_taken_expr(expr.base, out)
        elseif cls == Tr.ExprIndex then
            local bcls = pvm.classof(expr.base)
            if bcls == Tr.IndexBaseExpr then collect_address_taken_expr(expr.base.expr, out)
            elseif bcls == Tr.IndexBaseView then collect_address_taken_expr(expr.base.view.base, out)
            elseif bcls == Tr.IndexBasePlace then collect_address_taken_place(expr.base.place, out) end
            collect_address_taken_expr(expr.index, out)
        elseif cls == Tr.ExprIntrinsic or cls == Tr.ExprAgg or cls == Tr.ExprArray then
            if expr.args ~= nil then for i = 1, #expr.args do collect_address_taken_expr(expr.args[i], out) end
            elseif expr.items ~= nil then for i = 1, #expr.items do collect_address_taken_expr(expr.items[i], out) end
            elseif expr.fields ~= nil then for i = 1, #expr.fields do collect_address_taken_expr(expr.fields[i].value, out) end end
        elseif cls == Tr.ExprIf then collect_address_taken_expr(expr.cond, out); collect_address_taken_stmts(expr.then_body, out); collect_address_taken_expr(expr.then_value, out); collect_address_taken_stmts(expr.else_body, out); collect_address_taken_expr(expr.else_value, out)
        elseif cls == Tr.ExprSelect then collect_address_taken_expr(expr.cond, out); collect_address_taken_expr(expr.then_value, out); collect_address_taken_expr(expr.else_value, out)
        elseif cls == Tr.ExprSwitch then
            collect_address_taken_expr(expr.value, out)
            for i = 1, #expr.arms do collect_address_taken_stmts(expr.arms[i].body, out); collect_address_taken_expr(expr.arms[i].result, out) end
            collect_address_taken_stmts(expr.default_body or {}, out); if expr.default_result then collect_address_taken_expr(expr.default_result, out) end
        elseif cls == Tr.ExprControl then collect_address_taken_stmts(expr.region.entry.body, out); for i = 1, #expr.region.blocks do collect_address_taken_stmts(expr.region.blocks[i].body, out) end
        elseif cls == Tr.ExprBlock then collect_address_taken_stmts(expr.body, out); if expr.result then collect_address_taken_expr(expr.result, out) end
        elseif cls == Tr.ExprView then if expr.view and expr.view.base then collect_address_taken_expr(expr.view.base, out) end
        elseif cls == Tr.ExprCtor then for i = 1, #(expr.args or {}) do collect_address_taken_expr(expr.args[i], out) end
        end
    end

    collect_address_taken_stmts = function(stmts, out)
        for i = 1, #(stmts or {}) do
            local stmt = stmts[i]
            local cls = pvm.classof(stmt)
            if cls == Tr.StmtLet or cls == Tr.StmtVar then collect_address_taken_expr(stmt.init, out)
            elseif cls == Tr.StmtSet then collect_address_taken_place(stmt.place, out); collect_address_taken_expr(stmt.value, out)
            elseif cls == Tr.StmtAtomicStore then collect_address_taken_expr(stmt.addr, out); collect_address_taken_expr(stmt.value, out)
            elseif cls == Tr.StmtExpr or cls == Tr.StmtAssert or cls == Tr.StmtYieldValue or cls == Tr.StmtReturnValue then collect_address_taken_expr(stmt.expr or stmt.cond or stmt.value, out)
            elseif cls == Tr.StmtIf then collect_address_taken_expr(stmt.cond, out); collect_address_taken_stmts(stmt.then_body, out); collect_address_taken_stmts(stmt.else_body, out)
            elseif cls == Tr.StmtSwitch then collect_address_taken_expr(stmt.value, out); for j = 1, #stmt.arms do collect_address_taken_stmts(stmt.arms[j].body, out) end; collect_address_taken_stmts(stmt.default_body or {}, out)
            elseif cls == Tr.StmtJump or cls == Tr.StmtJumpCont then for j = 1, #stmt.args do collect_address_taken_expr(stmt.args[j].value, out) end
            elseif cls == Tr.StmtControl then collect_address_taken_stmts(stmt.region.entry.body, out); for j = 1, #stmt.region.blocks do collect_address_taken_stmts(stmt.region.blocks[j].body, out) end
            elseif cls == Tr.StmtUseRegionFrag then for j = 1, #stmt.args do collect_address_taken_expr(stmt.args[j], out) end
            end
        end
        return out
    end

    local hex = {}
    for i = 0, 255 do hex[i] = string.format("%02x", i) end

    local function string_data_id(bytes)
        local parts = { "str", tostring(#bytes) }
        for i = 1, #bytes do parts[#parts + 1] = hex[bytes:byte(i)] end
        return Back.BackDataId(table.concat(parts, ":"))
    end

    local function string_data_cmds(bytes)
        local data = string_data_id(bytes)
        local cmds = { Back.CmdDeclareData(data, #bytes + 1, 1) }
        for i = 1, #bytes do
            cmds[#cmds + 1] = Back.CmdDataInit(data, i - 1, Back.BackU8, Back.BackLitInt(tostring(bytes:byte(i))))
        end
        cmds[#cmds + 1] = Back.CmdDataInitZero(data, #bytes, 1)
        return data, cmds
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
            return C.MachineCastIdentity
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
        local values = scalar_api.scalar_to_back:drain_uncached(scalar)
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

    local function is_aggregate_type(ty)
        local cls = pvm.classof(ty)
        return cls == Ty.TArray or cls == Ty.TNamed
    end

    local function shape_scalar(s)
        return Back.BackShapeScalar(s)
    end

    local function elem_size(ty)
        local result = layout_api.result(ty, lower_context.layout_env or Sem.LayoutEnv({}))
        if pvm.classof(result) == Ty.TypeMemLayoutKnown then return result.layout.size end
        return nil
    end

    local function elem_align(ty)
        local result = layout_api.result(ty, lower_context.layout_env or Sem.LayoutEnv({}))
        if pvm.classof(result) == Ty.TypeMemLayoutKnown then return result.layout.align end
        return nil
    end

    local function stack_slot_for_binding(binding)
        local func = tostring(lower_context.current_func or "func")
        return Back.BackStackSlotId("slot:" .. func .. ":" .. binding_key(binding))
    end

    local function new_stack_slot_for_binding(binding)
        lower_context.stack_slot_seq = (lower_context.stack_slot_seq or 0) + 1
        local func = tostring(lower_context.current_func or "func")
        return Back.BackStackSlotId("slot:" .. func .. ":" .. binding_key(binding) .. ":" .. tostring(lower_context.stack_slot_seq))
    end

    local function binding_is_stack_local(binding)
        return lower_context.stack_locals ~= nil and lower_context.stack_locals[binding_key(binding)] == true
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

    expr_type = pvm.phase("moonlift_tree_expr_type_from_header", {
        [Tr.ExprTyped] = function(self) return pvm.once(self.ty) end,
        [Tr.ExprOpen] = function(self) return pvm.once(self.ty) end,

        [Tr.ExprSurface] = function() return pvm.empty() end,
    })

    scalar_literal = pvm.phase("moonlift_tree_literal_to_back_literal", {
        [C.LitInt] = function(self) return pvm.once(Back.BackLitInt(self.raw)) end,
        [C.LitFloat] = function(self) return pvm.once(Back.BackLitFloat(self.raw)) end,
        [C.LitBool] = function(self) return pvm.once(Back.BackLitBool(self.value)) end,
        [C.LitNil] = function() return pvm.once(Back.BackLitNull) end,
    })

    local function sem_const_literal(value)
        local cls = pvm.classof(value)
        if cls == Sem.ConstInt then return Back.BackLitInt(value.raw) end
        if cls == Sem.ConstFloat then return Back.BackLitFloat(value.raw) end
        if cls == Sem.ConstBool then return Back.BackLitBool(value.value) end
        if cls == Sem.ConstNil then return Back.BackLitNull end
        return nil
    end

    local function switch_key_raw_value(key_raw)
        if type(key_raw) == "string" then return key_raw end
        if type(key_raw) == "number" then return tostring(key_raw) end
        return nil
    end

    local function scalar_size_align(scalar)
        local ii = int_scalar_info[scalar]
        if ii ~= nil then
            local n = math.max(1, math.floor((ii.bits + 7) / 8))
            return n, n
        end
        local fb = float_scalar_bits[scalar]
        if fb ~= nil then
            local n = math.floor((fb + 7) / 8)
            return n, n
        end
        if scalar == Back.BackPtr then return 8, 8 end
        if scalar == Back.BackBool then return 1, 1 end
        return nil, nil
    end

    local function const_value_for(module_name, item_name)
        for i = 1, #lower_context.const_env.entries do
            local entry = lower_context.const_env.entries[i]
            if entry.module_name == module_name and entry.item_name == item_name then
                return const_eval_api.value(entry.value, lower_context.const_env, const_eval_api.empty_local_env())
            end
        end
        return nil
    end

    local function data_init_cmds(module_name, item_name, ty, value_expr)
        local scalar = back_scalar(ty)
        if scalar == nil then return nil, "global data requires scalar backend type" end
        local value = const_eval_api.value(value_expr, lower_context.const_env, const_eval_api.empty_local_env())
        local lit = value and sem_const_literal(value) or nil
        if lit == nil then return nil, "global data initializer is not a scalar constant" end
        local size, align = scalar_size_align(scalar)
        if size == nil then return nil, "global data has unsupported scalar layout" end
        local data = data_id_for_global(module_name, item_name)
        return {
            Back.CmdDeclareData(data, size, align),
            Back.CmdDataInit(data, 0, scalar, lit),
        }
    end

    unary_op = pvm.phase("moonlift_tree_unary_to_back_op", {
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

    binary_cmd = pvm.phase("moonlift_tree_binary_to_back_cmd", {
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

    compare_op = pvm.phase("moonlift_tree_compare_to_back_op", {
        [C.CmpEq] = function(_, scalar) if scalar == Back.BackF32 or scalar == Back.BackF64 then return pvm.once(Back.BackFCmpEq) end return pvm.once(Back.BackIcmpEq) end,
        [C.CmpNe] = function(_, scalar) if scalar == Back.BackF32 or scalar == Back.BackF64 then return pvm.once(Back.BackFCmpNe) end return pvm.once(Back.BackIcmpNe) end,
        [C.CmpLt] = function(_, scalar) if scalar == Back.BackF32 or scalar == Back.BackF64 then return pvm.once(Back.BackFCmpLt) end return pvm.once(Back.BackSIcmpLt) end,
        [C.CmpLe] = function(_, scalar) if scalar == Back.BackF32 or scalar == Back.BackF64 then return pvm.once(Back.BackFCmpLe) end return pvm.once(Back.BackSIcmpLe) end,
        [C.CmpGt] = function(_, scalar) if scalar == Back.BackF32 or scalar == Back.BackF64 then return pvm.once(Back.BackFCmpGt) end return pvm.once(Back.BackSIcmpGt) end,
        [C.CmpGe] = function(_, scalar) if scalar == Back.BackF32 or scalar == Back.BackF64 then return pvm.once(Back.BackFCmpGe) end return pvm.once(Back.BackSIcmpGe) end,
    }, { args_cache = "last" })

    intrinsic_op = pvm.phase("moonlift_tree_intrinsic_to_back_op", {
        [C.IntrinsicPopcount] = function() return pvm.once(Back.BackIntrinsicPopcount) end,
        [C.IntrinsicClz] = function() return pvm.once(Back.BackIntrinsicClz) end,
        [C.IntrinsicCtz] = function() return pvm.once(Back.BackIntrinsicCtz) end,
        [C.IntrinsicBswap] = function() return pvm.once(Back.BackIntrinsicBswap) end,
        [C.IntrinsicSqrt] = function() return pvm.once(Back.BackIntrinsicSqrt) end,
        [C.IntrinsicAbs] = function() return pvm.once(Back.BackIntrinsicAbs) end,
        [C.IntrinsicFloor] = function() return pvm.once(Back.BackIntrinsicFloor) end,
        [C.IntrinsicCeil] = function() return pvm.once(Back.BackIntrinsicCeil) end,
        [C.IntrinsicTruncFloat] = function() return pvm.once(Back.BackIntrinsicTruncFloat) end,
        [C.IntrinsicRound] = function() return pvm.once(Back.BackIntrinsicRound) end,
        [C.IntrinsicRotl] = function() return pvm.empty() end,
        [C.IntrinsicRotr] = function() return pvm.empty() end,
        [C.IntrinsicFma] = function() return pvm.empty() end,
        [C.IntrinsicTrap] = function() return pvm.empty() end,
        [C.IntrinsicAssume] = function() return pvm.empty() end,
    })

    machine_cast_op = pvm.phase("moonlift_tree_machine_cast_to_back_op", {
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

    surface_cast_op = pvm.phase("moonlift_tree_surface_cast_to_machine_cast", {
        [C.SurfaceCast] = function() return pvm.once(C.MachineCastBitcast) end,
        [C.SurfaceTrunc] = function() return pvm.once(C.MachineCastIreduce) end,
        [C.SurfaceZExt] = function() return pvm.once(C.MachineCastUextend) end,
        [C.SurfaceSExt] = function() return pvm.once(C.MachineCastSextend) end,
        [C.SurfaceBitcast] = function() return pvm.once(C.MachineCastBitcast) end,
        [C.SurfaceSatCast] = function() return pvm.once(C.MachineCastBitcast) end,
    })

    call_target = function(callee_expr, env)
        local cls = pvm.classof(callee_expr)
        if cls == Tr.ExprRef then
            local ref_cls = pvm.classof(callee_expr.ref)
            if ref_cls == Bn.ValueRefName or ref_cls == Bn.ValueRefPath then
                -- Try to resolve from environment
                local resolved = expr_value(expr_to_back:one_uncached(callee_expr, env))
                if resolved ~= nil then return Back.BackCallIndirect(resolved.value) end
                return nil
            end
            if ref_cls == Bn.ValueRefBinding then
                local class_cls = pvm.classof(callee_expr.ref.binding.class)
                if class_cls == Bn.BindingClassGlobalFunc then
                    return Back.BackCallDirect(Back.BackFuncId(callee_expr.ref.binding.class.item_name))
                end
                if class_cls == Bn.BindingClassExtern then
                    return Back.BackCallExtern(Back.BackExternId(callee_expr.ref.binding.class.symbol))
                end
                if class_cls == Bn.BindingClassOpenSym then
                    if callee_expr.ref.binding.class.sym.kind == C.SymKindExtern then
                        return Back.BackCallExtern(Back.BackExternId(callee_expr.ref.binding.class.sym.symbol))
                    end
                    if callee_expr.ref.binding.class.sym.kind == C.SymKindFunc then
                        return Back.BackCallDirect(Back.BackFuncId(callee_expr.ref.binding.class.sym.name))
                    end
                end
            end
        end
        -- Indirect call via expression
        local callee = expr_value(expr_to_back:one_uncached(callee_expr, env))
        if callee == nil then return nil end
        return Back.BackCallIndirect(callee.value)
    end

    lower_closure_call = function(call_expr, env, want_value)
        local closure = expr_value(expr_to_back:one_uncached(call_expr.callee, env))
        if closure == nil then return Tr.TreeBackExprUnsupported(env, {}, "unsupported closure callee") end
        local cmds = {}; append_all(cmds, closure.cmds)
        local current = closure.env
        local fn, ctx
        current, fn = descriptor_field_load(cmds, current, closure.value, "fn", 0, Back.BackPtr)
        current, ctx = descriptor_field_load(cmds, current, closure.value, "ctx", 8, Back.BackPtr)
        local args, params = { ctx }, { Back.BackPtr }
        for i = 1, #call_expr.args do
            local arg = expr_value(expr_to_back:one_uncached(call_expr.args[i], current))
            if arg == nil then return Tr.TreeBackExprUnsupported(current, cmds, "unsupported closure call arg") end
            append_all(cmds, arg.cmds)
            args[#args + 1] = arg.value
            params[#params + 1] = arg.ty
            current = arg.env
        end
        local result_ty = expr_ty(call_expr)
        local result_scalar = back_scalar(result_ty)
        local sig_results = {}
        if want_value then
            if result_scalar == nil then return Tr.TreeBackExprUnsupported(current, cmds, "closure call result has non-scalar type") end
            sig_results[1] = result_scalar
        end
        local sig_prefix = "sig:closure:" .. tostring(lower_context.module_name or "") .. ":" .. tostring(lower_context.current_func or "") .. ":"
        lower_context.closure_call_seq = (lower_context.closure_call_seq or 0) + 1
        local sig = Back.BackSigId(sig_prefix .. tostring(lower_context.closure_call_seq))
        cmds[#cmds + 1] = Back.CmdCreateSig(sig, params, sig_results)
        if want_value then
            local env2, dst = env_next_value(current, "v")
            cmds[#cmds + 1] = Back.CmdCall(Back.BackCallValue(dst, result_scalar), Back.BackCallIndirect(fn), sig, args)
            return Tr.TreeBackExprValue(env2, cmds, dst, result_scalar)
        end
        cmds[#cmds + 1] = Back.CmdCall(Back.BackCallStmt, Back.BackCallIndirect(fn), sig, args)
        return Tr.TreeBackStmtResult(current, cmds, Back.BackFallsThrough)
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

    append_zero_offset = function(cmds, current)
        local env1, zero = env_next_value(current, "v")
        cmds[#cmds + 1] = Back.CmdConst(zero, Back.BackIndex, Back.BackLitInt("0"))
        return env1, zero
    end

    address_from_data = function(data, offset)
        return Back.BackAddress(Back.BackAddrData(data), offset, Back.BackProvData(data), Back.BackPtrInBounds("global data"))
    end

    expr_to_back = pvm.phase("moonlift_tree_expr_to_back", {
        [Tr.ExprLit] = function(self, env)
            if pvm.classof(self.value) == C.LitString then
                local data, cmds = string_data_cmds(self.value.bytes)
                local env2, dst = env_next_value(env, "v")
                cmds[#cmds + 1] = Back.CmdDataAddr(dst, data)
                return pvm.once(Tr.TreeBackExprValue(env2, cmds, dst, Back.BackPtr))
            end
            local ty = expr_ty(self)
            local scalar = back_scalar(ty)
            if scalar == nil then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "literal has non-scalar type")) end
            local env2, dst = env_next_value(env, "v")
            return pvm.once(Tr.TreeBackExprValue(env2, { Back.CmdConst(dst, scalar, scalar_literal:one_uncached(self.value)) }, dst, scalar))
        end,
        [Tr.ExprRef] = function(self, env)
            local ref_cls = pvm.classof(self.ref)
            if ref_cls == Bn.ValueRefBinding then
                local local_entry = env_lookup(env, self.ref.binding)
                if local_entry ~= nil then
                    local local_cls = pvm.classof(local_entry)
                    if local_cls == Tr.TreeBackScalarLocal then
                        return pvm.once(Tr.TreeBackExprValue(env, {}, local_entry.value, local_entry.ty))
                    elseif local_cls == Tr.TreeBackStackLocal then
                        local env1, addr = env_next_value(env, "addr")
                        local env2, dst = env_next_value(env1, "v")
                        local cmds = { Back.CmdStackAddr(addr, local_entry.slot) }
                        local env3 = append_load_info(cmds, env2, dst, shape_scalar(local_entry.ty), addr, "stack:" .. tostring(self.ref.binding.name))
                        return pvm.once(Tr.TreeBackExprValue(env3, cmds, dst, local_entry.ty))
                    end
                end

                if is_aggregate_type(self.ref.binding.ty) then
                    local slot = lower_context.agg_binding_slots and lower_context.agg_binding_slots[binding_key(self.ref.binding)] or nil
                    local class_cls = pvm.classof(self.ref.binding.class)
                    if slot == nil and (class_cls == Bn.BindingClassLocalValue or class_cls == Bn.BindingClassLocalCell) then
                        slot = stack_slot_for_binding(self.ref.binding)
                    end
                    if slot ~= nil then
                        local env1, addr = env_next_value(env, "addr")
                        return pvm.once(Tr.TreeBackExprValue(env1, { Back.CmdStackAddr(addr, slot) }, addr, Back.BackPtr))
                    end
                end

                local class = self.ref.binding.class
                local class_cls = pvm.classof(class)
                if class_cls == Bn.BindingClassGlobalConst then
                    local value = const_value_for(class.module_name, class.item_name)
                    local lit = value and sem_const_literal(value) or nil
                    local scalar = back_scalar(self.ref.binding.ty)
                    if lit ~= nil and scalar ~= nil then
                        local env2, dst = env_next_value(env, "v")
                        return pvm.once(Tr.TreeBackExprValue(env2, { Back.CmdConst(dst, scalar, lit) }, dst, scalar))
                    end
                    return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "global const is not a scalar compile-time value"))
                end
                if class_cls == Bn.BindingClassGlobalStatic then
                    return pvm.once(load_global_data(env, data_id_for_global(class.module_name, class.item_name), self.ref.binding.ty, class.item_name))
                end
                if class_cls == Bn.BindingClassGlobalFunc then
                    local env2, dst = env_next_value(env, "v")
                    return pvm.once(Tr.TreeBackExprValue(env2, { Back.CmdFuncAddr(dst, Back.BackFuncId(class.item_name)) }, dst, Back.BackPtr))
                end
                if class_cls == Bn.BindingClassExtern then
                    local env2, dst = env_next_value(env, "v")
                    return pvm.once(Tr.TreeBackExprValue(env2, { Back.CmdExternAddr(dst, Back.BackExternId(class.symbol)) }, dst, Back.BackPtr))
                end
            elseif ref_cls == Bn.ValueRefHole then
                local slot_cls = pvm.classof(self.ref.slot)
                if slot_cls == O.SlotConst then
                    local slot = self.ref.slot.slot
                    local value = lower_context.slot_consts and lower_context.slot_consts[slot.key] or nil
                    local lit = value and sem_const_literal(value) or nil
                    local scalar = back_scalar(slot.ty)
                    if lit ~= nil and scalar ~= nil then
                        local env2, dst = env_next_value(env, "v")
                        return pvm.once(Tr.TreeBackExprValue(env2, { Back.CmdConst(dst, scalar, lit) }, dst, scalar))
                    end
                elseif slot_cls == O.SlotStatic then
                    local slot = self.ref.slot.slot
                    local data = lower_context.slot_statics and lower_context.slot_statics[slot.key] or nil
                    if data ~= nil then return pvm.once(load_global_data(env, data, slot.ty, slot.pretty_name)) end
                elseif slot_cls == O.SlotFunc then
                    local slot = self.ref.slot.slot
                    local env2, dst = env_next_value(env, "v")
                    return pvm.once(Tr.TreeBackExprValue(env2, { Back.CmdFuncAddr(dst, Back.BackFuncId(slot.pretty_name)) }, dst, Back.BackPtr))
                end
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
            local cmds = {}; append_all(cmds, lhs.cmds); append_all(cmds, rhs.cmds)

            -- Pointer arithmetic: pointer +/- integer element offset
            if (self.op == C.BinAdd or self.op == C.BinSub) and scalar == Back.BackPtr then
                local ptr, off = lhs, rhs
                if self.op == C.BinAdd and ptr.ty ~= Back.BackPtr then ptr, off = rhs, lhs end
                -- stride = sizeof(elem) so that p+n advances by n elements
                local stride = 1
                if pvm.classof(ty) == Ty.TPtr then
                    local sz = elem_size(ty.elem); if sz ~= nil and sz > 0 then stride = sz end
                end
                local env_e1 = rhs.env
                local off_ext = off.value
                if off.ty ~= Back.BackIndex then
                    local cast_env, cast_val = env_next_value(env_e1, "v")
                    cmds[#cmds + 1] = Back.CmdCast(cast_val, Back.BackSextend, Back.BackIndex, off.value)
                    env_e1 = cast_env
                    off_ext = cast_val
                end
                if self.op == C.BinSub then
                    local env_neg, neg_off = env_next_value(env_e1, "v")
                    cmds[#cmds + 1] = Back.CmdUnary(neg_off, Back.BackUnaryIneg, Back.BackShapeScalar(Back.BackIndex), off_ext)
                    env_e1 = env_neg; off_ext = neg_off
                end
                local env_e2, addr = env_next_value(env_e1, "v")
                cmds[#cmds + 1] = Back.CmdPtrOffset(addr, Back.BackAddrValue(ptr.value), off_ext, stride, 0, Back.BackProvDerived("ptr arith"), Back.BackPtrBoundsUnknown)
                return pvm.once(Tr.TreeBackExprValue(env_e2, cmds, addr, Back.BackPtr))
            end

            local env2, dst = env_next_value(rhs.env, "v")
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
            local ops = machine_cast_op:drain_uncached(self.op)
            if #ops == 0 then return pvm.once(Tr.TreeBackExprValue(value.env, value.cmds, value.value, scalar)) end
            if ops[1] == Back.BackIreduce then
                local src_info, dst_info = int_scalar_info[value.ty], int_scalar_info[scalar]
                if src_info ~= nil and dst_info ~= nil and dst_info.bits >= src_info.bits then
                    return pvm.once(Tr.TreeBackExprValue(value.env, value.cmds, value.value, scalar))
                end
            end
            if ops[1] == Back.BackBitcast and value.ty == scalar then
                return pvm.once(Tr.TreeBackExprValue(value.env, value.cmds, value.value, scalar))
            end
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
            if pvm.classof(self.callee) == Tr.ExprClosure then return pvm.once(lower_closure_call(self, env, true)) end
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
            local target = call_target(self.callee, env2)
            if target == nil then return pvm.once(Tr.TreeBackExprUnsupported(current, cmds, "unsupported call target")) end
            local sig_prefix = "sig:call:" .. tostring(lower_context.module_name or "") .. ":" .. tostring(lower_context.current_func or "") .. ":"
            local sig, declare_call_sig = Back.BackSigId(sig_prefix .. tostring(dst.text)), true
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
        [Tr.ExprCast] = function(self, env) return pvm.once(expr_to_back:one_uncached(Tr.ExprMachineCast(self.h, surface_cast_to_machine_op(self.op, expr_ty(self.value), self.ty), self.ty, self.value), env)) end,
        [Tr.ExprLen] = function(self, env)
            local value_ty = expr_ty(self.value)
            if pvm.classof(value_ty) == Ty.TArray and pvm.classof(value_ty.count) == Ty.ArrayLenConst then
                local env2, dst = env_next_value(env, "v")
                return pvm.once(Tr.TreeBackExprValue(env2, { Back.CmdConst(dst, Back.BackIndex, Back.BackLitInt(tostring(value_ty.count.count))) }, dst, Back.BackIndex))
            end
            local lowered = expr_to_back:one_uncached(self.value, env)
            local view = expr_view_value(lowered)
            if view ~= nil then return pvm.once(Tr.TreeBackExprValue(view.env, view.cmds, view.len, Back.BackIndex)) end
            if pvm.classof(self.value) == Tr.ExprRef and pvm.classof(self.value.ref) == Bn.ValueRefBinding then
                local local_entry = env_lookup(env, self.value.ref.binding)
                if local_entry ~= nil and (pvm.classof(local_entry) == Tr.TreeBackViewLocal or pvm.classof(local_entry) == Tr.TreeBackStridedViewLocal) then return pvm.once(Tr.TreeBackExprValue(env, {}, local_entry.len, Back.BackIndex)) end
            end
            return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "len lowering requires view or array binding"))
        end,
        [Tr.ExprLogic] = function(self, env)
            local lhs = expr_value(expr_to_back:one_uncached(self.lhs, env))
            if lhs == nil then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "unsupported logic lhs")) end
            local rhs = expr_value(expr_to_back:one_uncached(self.rhs, lhs.env))
            if rhs == nil then return pvm.once(Tr.TreeBackExprUnsupported(lhs.env, lhs.cmds, "unsupported logic rhs")) end
            local cmds = {}; append_all(cmds, lhs.cmds); append_all(cmds, rhs.cmds)

            if self.op == C.LogicAnd then
                local env1, false_val = env_next_value(rhs.env, "v")
                cmds[#cmds + 1] = Back.CmdConst(false_val, Back.BackBool, Back.BackLitBool(false))
                local env2, dst = env_next_value(env1, "v")
                cmds[#cmds + 1] = Back.CmdSelect(dst, Back.BackShapeScalar(Back.BackBool), lhs.value, rhs.value, false_val)
                return pvm.once(Tr.TreeBackExprValue(env2, cmds, dst, Back.BackBool))
            end
            if self.op == C.LogicOr then
                local env1, true_val = env_next_value(rhs.env, "v")
                cmds[#cmds + 1] = Back.CmdConst(true_val, Back.BackBool, Back.BackLitBool(true))
                local env2, dst = env_next_value(env1, "v")
                cmds[#cmds + 1] = Back.CmdSelect(dst, Back.BackShapeScalar(Back.BackBool), lhs.value, true_val, rhs.value)
                return pvm.once(Tr.TreeBackExprValue(env2, cmds, dst, Back.BackBool))
            end
            return pvm.once(Tr.TreeBackExprUnsupported(rhs.env, cmds, "unsupported logic op"))
        end,
        [Tr.ExprIf] = function(self, env)
            local cond = expr_value(expr_to_back:one_uncached(self.cond, env))
            if cond == nil then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "unsupported if expression cond")) end
            local result_scalar = back_scalar(expr_ty(self))
            if result_scalar == nil then return pvm.once(Tr.TreeBackExprUnsupported(cond.env, cond.cmds, "if expression result has non-scalar type")) end

            local current = cond.env
            local then_block; current, then_block = env_next_block(current, "if.expr.then")
            local else_block; current, else_block = env_next_block(current, "if.expr.else")
            local join_block; current, join_block = env_next_block(current, "if.expr.join")
            local result_value; current, result_value = env_next_value(current, "ifexpr")

            local cmds = {}
            append_all(cmds, cond.cmds)
            cmds[#cmds + 1] = Back.CmdCreateBlock(then_block)
            cmds[#cmds + 1] = Back.CmdCreateBlock(else_block)
            cmds[#cmds + 1] = Back.CmdCreateBlock(join_block)
            cmds[#cmds + 1] = Back.CmdAppendBlockParam(join_block, result_value, shape_scalar(result_scalar))
            cmds[#cmds + 1] = Back.CmdBrIf(cond.value, then_block, {}, else_block, {})
            cmds[#cmds + 1] = Back.CmdSealBlock(then_block)
            cmds[#cmds + 1] = Back.CmdSealBlock(else_block)

            cmds[#cmds + 1] = Back.CmdSwitchToBlock(then_block)
            local then_start = env_with_counters(cond.env, current)
            local then_result = expr_value(expr_to_back:one_uncached(self.then_expr, then_start))
            if then_result == nil then return pvm.once(Tr.TreeBackExprUnsupported(then_start, cmds, "unsupported if expression then")) end
            append_all(cmds, then_result.cmds)
            cmds[#cmds + 1] = Back.CmdJump(join_block, { then_result.value })
            current = env_with_counters(current, then_result.env)

            cmds[#cmds + 1] = Back.CmdSwitchToBlock(else_block)
            local else_start = env_with_counters(cond.env, current)
            local else_result = expr_value(expr_to_back:one_uncached(self.else_expr, else_start))
            if else_result == nil then return pvm.once(Tr.TreeBackExprUnsupported(else_start, cmds, "unsupported if expression else")) end
            append_all(cmds, else_result.cmds)
            cmds[#cmds + 1] = Back.CmdJump(join_block, { else_result.value })
            current = env_with_counters(current, else_result.env)

            cmds[#cmds + 1] = Back.CmdSealBlock(join_block)
            cmds[#cmds + 1] = Back.CmdSwitchToBlock(join_block)
            return pvm.once(Tr.TreeBackExprValue(Tr.TreeBackEnv(cond.env.locals, current.next_value, current.next_block, cond.env.ret), cmds, result_value, result_scalar))
        end,
        [Tr.ExprSwitch] = function(self, env)
            local value = expr_value(expr_to_back:one_uncached(self.value, env))
            if value == nil then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "unsupported switch expression value")) end
            local result_scalar = back_scalar(expr_ty(self))
            if result_scalar == nil then return pvm.once(Tr.TreeBackExprUnsupported(value.env, value.cmds, "switch expression result has non-scalar type")) end
            local case_raws = {}
            for i = 1, #self.arms do
                local raw = switch_key_raw_value(self.arms[i].raw_key)
                if raw == nil then return pvm.once(Tr.TreeBackExprUnsupported(value.env, value.cmds, "switch expression case is not an integer/bool constant")) end
                case_raws[#case_raws + 1] = raw
            end

            local current = value.env
            local arm_blocks = {}
            for i = 1, #self.arms do current, arm_blocks[i] = env_next_block(current, "switch.expr.arm") end
            local default_block; current, default_block = env_next_block(current, "switch.expr.default")
            local join_block; current, join_block = env_next_block(current, "switch.expr.join")
            local result_value; current, result_value = env_next_value(current, "switch")

            local cmds = {}
            append_all(cmds, value.cmds)
            for i = 1, #arm_blocks do cmds[#cmds + 1] = Back.CmdCreateBlock(arm_blocks[i]) end
            cmds[#cmds + 1] = Back.CmdCreateBlock(default_block)
            cmds[#cmds + 1] = Back.CmdCreateBlock(join_block)
            cmds[#cmds + 1] = Back.CmdAppendBlockParam(join_block, result_value, shape_scalar(result_scalar))
            local cases = {}
            for i = 1, #case_raws do cases[i] = Back.BackSwitchCase(case_raws[i], arm_blocks[i]) end
            cmds[#cmds + 1] = Back.CmdSwitchInt(value.value, value.ty, cases, default_block)
            for i = 1, #arm_blocks do cmds[#cmds + 1] = Back.CmdSealBlock(arm_blocks[i]) end
            cmds[#cmds + 1] = Back.CmdSealBlock(default_block)

            for i = 1, #self.arms do
                cmds[#cmds + 1] = Back.CmdSwitchToBlock(arm_blocks[i])
                local start = env_with_counters(value.env, current)
                local arm_env, arm_cmds, arm_flow = lower_body(self.arms[i].body, start)
                append_all(cmds, arm_cmds)
                if arm_flow ~= Back.BackTerminates then
                    local result = expr_value(expr_to_back:one_uncached(self.arms[i].result, arm_env))
                    if result == nil then return pvm.once(Tr.TreeBackExprUnsupported(arm_env, cmds, "unsupported switch arm result")) end
                    append_all(cmds, result.cmds)
                    cmds[#cmds + 1] = Back.CmdJump(join_block, { result.value })
                    current = env_with_counters(current, result.env)
                else
                    current = env_with_counters(current, arm_env)
                end
            end

            cmds[#cmds + 1] = Back.CmdSwitchToBlock(default_block)
            local default_start = env_with_counters(value.env, current)
            local default_env, default_cmds, default_flow = lower_body(self.default_body or {}, default_start)
            append_all(cmds, default_cmds)
            if default_flow ~= Back.BackTerminates then
                local default_result = expr_value(expr_to_back:one_uncached(self.default_expr, default_env))
                if default_result == nil then return pvm.once(Tr.TreeBackExprUnsupported(default_env, cmds, "unsupported switch default result")) end
                append_all(cmds, default_result.cmds)
                cmds[#cmds + 1] = Back.CmdJump(join_block, { default_result.value })
                current = env_with_counters(current, default_result.env)
            else
                current = env_with_counters(current, default_env)
            end

            cmds[#cmds + 1] = Back.CmdSealBlock(join_block)
            cmds[#cmds + 1] = Back.CmdSwitchToBlock(join_block)
            return pvm.once(Tr.TreeBackExprValue(Tr.TreeBackEnv(value.env.locals, current.next_value, current.next_block, value.env.ret), cmds, result_value, result_scalar))
        end,
        [Tr.ExprControl] = function(self, env) return pvm.once(control_api.expr_region_to_back:one_uncached(self.region, env)) end,
        [Tr.ExprBlock] = function(self, env)
            local body_env, body_cmds, flow = lower_body(self.stmts, env)
            if flow == Back.BackTerminates then return pvm.once(Tr.TreeBackExprUnsupported(body_env, body_cmds, "block expression body terminates before result")) end
            local result = expr_to_back:one_uncached(self.result, body_env)
            local value = expr_value(result)
            if value ~= nil then
                local cmds = {}; append_all(cmds, body_cmds); append_all(cmds, value.cmds)
                return pvm.once(Tr.TreeBackExprValue(value.env, cmds, value.value, value.ty))
            end
            local view = expr_view_value(result)
            if view ~= nil then
                local cmds = {}; append_all(cmds, body_cmds); append_all(cmds, view.cmds)
                if pvm.classof(view) == Tr.TreeBackExprStridedView then return pvm.once(Tr.TreeBackExprStridedView(view.env, cmds, view.data, view.len, view.stride)) end
                return pvm.once(Tr.TreeBackExprView(view.env, cmds, view.data, view.len))
            end
            return pvm.once(Tr.TreeBackExprUnsupported(body_env, body_cmds, "unsupported block expression result"))
        end,
        [Tr.ExprDot] = function(_, env) return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "dot lowering requires layout resolution")) end,
        [Tr.ExprIntrinsic] = function(self, env)
            local result_scalar = back_scalar(expr_ty(self))
            if result_scalar == nil then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "intrinsic result has non-scalar type")) end
            local args = {}; local cmds = {}; local current = env
            for i = 1, #self.args do
                local arg = expr_value(expr_to_back:one_uncached(self.args[i], current))
                if arg == nil then return pvm.once(Tr.TreeBackExprUnsupported(current, cmds, "unsupported intrinsic arg")) end
                append_all(cmds, arg.cmds); args[#args + 1] = arg.value; current = arg.env
            end
            if self.op == C.IntrinsicFma and #args == 3 then
                local env2, dst = env_next_value(current, "v")
                cmds[#cmds + 1] = Back.CmdFma(dst, result_scalar, Back.BackFloatStrict, args[1], args[2], args[3])
                return pvm.once(Tr.TreeBackExprValue(env2, cmds, dst, result_scalar))
            end
            local ops = intrinsic_op:drain_uncached(self.op)
            if #ops ~= 1 then return pvm.once(Tr.TreeBackExprUnsupported(current, cmds, "unsupported intrinsic op")) end
            local env2, dst = env_next_value(current, "v")
            cmds[#cmds + 1] = Back.CmdIntrinsic(dst, ops[1], shape_scalar(result_scalar), args)
            return pvm.once(Tr.TreeBackExprValue(env2, cmds, dst, result_scalar))
        end,
        [Tr.ExprAddrOf] = function(self, env) return pvm.once(place_addr_to_back:one_uncached(self.place, env)) end,
        [Tr.ExprDeref] = function(self, env)
            local addr = expr_value(expr_to_back:one_uncached(self.value, env))
            if addr == nil then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "unsupported deref address")) end
            local scalar = back_scalar(expr_ty(self))
            if scalar == nil then
                if is_aggregate_type(expr_ty(self)) then return pvm.once(addr) end
                return pvm.once(Tr.TreeBackExprUnsupported(addr.env, addr.cmds, "deref result has non-scalar type"))
            end
            local env2, dst = env_next_value(addr.env, "v")
            local cmds = {}; append_all(cmds, addr.cmds)
            local env3 = append_load_info(cmds, env2, dst, shape_scalar(scalar), addr.value, dst.text)
            return pvm.once(Tr.TreeBackExprValue(env3, cmds, dst, scalar))
        end,
        [Tr.ExprField] = function(self, env)
            if pvm.classof(self.field) ~= Sem.FieldByOffset then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "field expression requires resolved offset")) end
            local base = expr_base_addr_to_back(self.base, env)
            if base == nil then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "unsupported field expression base")) end
            local addr = field_addr_from_base_ptr(base, self.field)
            if is_aggregate_type(expr_ty(self)) then return pvm.once(addr) end
            return pvm.once(load_from_field_addr(addr, self.field))
        end,
        [Tr.ExprIndex] = function(self, env)
            local lowered = index_addr_to_back:one_uncached(self.base, self.index, expr_ty(self), env)
            if pvm.classof(lowered) ~= Tr.TreeBackExprValue then return pvm.once(lowered) end
            local scalar = back_scalar(expr_ty(self))
            if scalar == nil then
                if is_aggregate_type(expr_ty(self)) then return pvm.once(lowered) end
                return pvm.once(Tr.TreeBackExprUnsupported(lowered.env, lowered.cmds, "index result has non-scalar type"))
            end
            local env2, dst = env_next_value(lowered.env, "v")
            local cmds = {}; append_all(cmds, lowered.cmds)
            local env3 = append_load_info(cmds, env2, dst, shape_scalar(scalar), lowered.value, dst.text)
            return pvm.once(Tr.TreeBackExprValue(env3, cmds, dst, scalar))
        end,
        [Tr.ExprAgg] = function(self, env)
            if pvm.classof(self.ty) == Ty.TClosure then
                local env_size = 0
                for i = 1, #self.fields do
                    local fi = self.fields[i]
                    if fi.name ~= "__moon_fn" then
                        local sz = elem_size(expr_ty(fi.value))
                        if sz == nil then
                            local s = back_scalar(expr_ty(fi.value))
                            sz = s and scalar_size_align(s) or nil
                        end
                        if sz == nil then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "closure capture has unsupported layout")) end
                        if fi.offset + sz > env_size then env_size = fi.offset + sz end
                    end
                end
                local total_size = 16 + env_size
                local func = tostring(lower_context.current_func or "anon")
                local slot = Back.BackStackSlotId("slot:" .. func .. ":closure:" .. tostring(env.next_value))
                local cmds = { Back.CmdCreateStackSlot(slot, total_size, 8) }
                local env1, desc = env_next_value(env, "v")
                cmds[#cmds + 1] = Back.CmdStackAddr(desc, slot)
                local current = env1
                local fn_field = nil
                for i = 1, #self.fields do if self.fields[i].name == "__moon_fn" then fn_field = self.fields[i]; break end end
                if fn_field == nil then return pvm.once(Tr.TreeBackExprUnsupported(current, cmds, "closure descriptor missing function pointer")) end
                local fn_val = expr_value(expr_to_back:one_uncached(fn_field.value, current))
                if fn_val == nil then return pvm.once(Tr.TreeBackExprUnsupported(current, cmds, "closure function pointer unsupported")) end
                append_all(cmds, fn_val.cmds); current = fn_val.env
                current = append_store_info(cmds, current, shape_scalar(Back.BackPtr), desc, fn_val.value, "closure:fn")
                local ctx_value
                if env_size == 0 then
                    current, ctx_value = env_next_value(current, "v")
                    cmds[#cmds + 1] = Back.CmdConst(ctx_value, Back.BackPtr, Back.BackLitNull)
                else
                    local ctx_ptr = add_ptr_offset(Tr.TreeBackExprValue(current, {}, desc, Back.BackPtr), 16)
                    append_all(cmds, ctx_ptr.cmds); current = ctx_ptr.env; ctx_value = ctx_ptr.value
                end
                local ctx_addr = add_ptr_offset(Tr.TreeBackExprValue(current, {}, desc, Back.BackPtr), 8)
                append_all(cmds, ctx_addr.cmds); current = ctx_addr.env
                current = append_store_info(cmds, current, shape_scalar(Back.BackPtr), ctx_addr.value, ctx_value, "closure:ctx")
                for i = 1, #self.fields do
                    local fi = self.fields[i]
                    if fi.name ~= "__moon_fn" then
                        local cap_val = expr_value(expr_to_back:one_uncached(fi.value, current))
                        if cap_val == nil then return pvm.once(Tr.TreeBackExprUnsupported(current, cmds, "closure capture unsupported")) end
                        append_all(cmds, cap_val.cmds); current = cap_val.env
                        local cap_addr = add_ptr_offset(Tr.TreeBackExprValue(current, {}, desc, Back.BackPtr), 16 + fi.offset)
                        append_all(cmds, cap_addr.cmds); current = cap_addr.env
                        current = append_store_info(cmds, current, shape_scalar(cap_val.ty), cap_addr.value, cap_val.value, "closure:cap:" .. fi.name)
                    end
                end
                return pvm.once(Tr.TreeBackExprValue(current, cmds, desc, Back.BackPtr))
            end
            local size = elem_size(self.ty)
            local align = elem_align(self.ty)
            if size == nil or align == nil then
                return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "aggregate type has unknown layout"))
            end
            local func = tostring(lower_context.current_func or "anon")
            local slot
            local cmds
            local env1, addr
            -- Use target slot if set by StmtLet for aggregate-typed bindings
            if lower_context.target_agg_slot then
                slot = lower_context.target_agg_slot
                cmds = {}
                env1, addr = env_next_value(env, "v")
                cmds[#cmds + 1] = Back.CmdStackAddr(addr, slot)
            else
                slot = Back.BackStackSlotId("slot:" .. func .. ":agg:" .. tostring(env.next_value))
                cmds = { Back.CmdCreateStackSlot(slot, size, align) }
                env1, addr = env_next_value(env, "v")
                cmds[#cmds + 1] = Back.CmdStackAddr(addr, slot)
            end
            local current = env1
            for i = 1, #self.fields do
                local fi = self.fields[i]
                local prev_target_slot = lower_context.target_agg_slot
                lower_context.target_agg_slot = nil
                local field_val = expr_value(expr_to_back:one_uncached(fi.value, current))
                lower_context.target_agg_slot = prev_target_slot
                if field_val == nil then
                    return pvm.once(Tr.TreeBackExprUnsupported(current, cmds, "struct field value unsupported"))
                end
                append_all(cmds, field_val.cmds)
                current = field_val.env
                local dst_addr_val = addr
                if fi.offset ~= 0 then
                    local off = add_ptr_offset(Tr.TreeBackExprValue(current, {}, addr, Back.BackPtr), fi.offset)
                    append_all(cmds, off.cmds); current = off.env; dst_addr_val = off.value
                end
                if is_aggregate_type(expr_ty(fi.value)) then
                    local sz = elem_size(expr_ty(fi.value))
                    if sz == nil then return pvm.once(Tr.TreeBackExprUnsupported(current, cmds, "struct aggregate field has unknown size")) end
                    current = append_memcpy(cmds, current, dst_addr_val, field_val.value, sz, "agg:" .. tostring(dst_addr_val.text) .. ":" .. fi.name)
                elseif fi.offset == 0 then
                    current = append_store_info(cmds, current, shape_scalar(field_val.ty), addr, field_val.value, "agg:" .. tostring(addr.text) .. ":" .. fi.name)
                else
                    local env_s, zero = append_zero_offset(cmds, current)
                    cmds[#cmds + 1] = Back.CmdStoreInfo(shape_scalar(field_val.ty), address_from_ptr(dst_addr_val, zero), field_val.value, memory_info("tree:agg:" .. tostring(dst_addr_val.text) .. ":" .. fi.name, Back.BackAccessWrite))
                    current = env_s
                end
            end
            return pvm.once(Tr.TreeBackExprValue(current, cmds, addr, Back.BackPtr))
        end,
        [Tr.ExprArray] = function(self, env)
            local elem_sz = elem_size(self.elem_ty)
            local elem_al = elem_align(self.elem_ty)
            if elem_sz == nil or elem_al == nil then
                return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "array element type has unknown layout"))
            end
            local total_size = elem_sz * #self.elems
            local func = tostring(lower_context.current_func or "anon")
            local slot
            local cmds
            local env1, addr
            if lower_context.target_agg_slot then
                slot = lower_context.target_agg_slot
                cmds = {}
                env1, addr = env_next_value(env, "v")
                cmds[#cmds + 1] = Back.CmdStackAddr(addr, slot)
            else
                slot = Back.BackStackSlotId("slot:" .. func .. ":arr:" .. tostring(env.next_value))
                cmds = { Back.CmdCreateStackSlot(slot, total_size, elem_al) }
                env1, addr = env_next_value(env, "v")
                cmds[#cmds + 1] = Back.CmdStackAddr(addr, slot)
            end
            local current = env1
            for i = 1, #self.elems do
                local prev_target_slot = lower_context.target_agg_slot
                lower_context.target_agg_slot = nil
                local elem_val = expr_value(expr_to_back:one_uncached(self.elems[i], current))
                lower_context.target_agg_slot = prev_target_slot
                if elem_val == nil then
                    return pvm.once(Tr.TreeBackExprUnsupported(current, cmds, "array element unsupported"))
                end
                append_all(cmds, elem_val.cmds)
                current = elem_val.env
                local off = (i - 1) * elem_sz
                local dst_addr_val = addr
                if off ~= 0 then
                    local off_ptr = add_ptr_offset(Tr.TreeBackExprValue(current, {}, addr, Back.BackPtr), off)
                    append_all(cmds, off_ptr.cmds); current = off_ptr.env; dst_addr_val = off_ptr.value
                end
                if is_aggregate_type(expr_ty(self.elems[i])) then
                    current = append_memcpy(cmds, current, dst_addr_val, elem_val.value, elem_sz, "arr:" .. tostring(i))
                elseif off == 0 then
                    current = append_store_info(cmds, current, shape_scalar(elem_val.ty), addr, elem_val.value, "arr:" .. tostring(i))
                else
                    local env_s, zero = append_zero_offset(cmds, current)
                    cmds[#cmds + 1] = Back.CmdStoreInfo(shape_scalar(elem_val.ty), address_from_ptr(dst_addr_val, zero), elem_val.value, memory_info("tree:arr:" .. tostring(i), Back.BackAccessWrite))
                    current = env_s
                end
            end
            return pvm.once(Tr.TreeBackExprValue(current, cmds, addr, Back.BackPtr))
        end,
        [Tr.ExprClosure] = function(_, env) return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "closure literals require closure-conversion before backend lowering")) end,
        [Tr.ExprView] = function(self, env) return pvm.once(view_to_back:one_uncached(self.view, env)) end,
        [Tr.ExprLoad] = function(self, env)
            local addr = expr_value(expr_to_back:one_uncached(self.addr, env))
            if addr == nil then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "unsupported load address")) end
            local scalar = back_scalar(self.ty)
            if scalar == nil then
                if is_aggregate_type(self.ty) then return pvm.once(addr) end
                return pvm.once(Tr.TreeBackExprUnsupported(addr.env, addr.cmds, "load result has non-scalar type"))
            end
            local env2, dst = env_next_value(addr.env, "v")
            local cmds = {}; append_all(cmds, addr.cmds)
            local env3 = append_load_info(cmds, env2, dst, shape_scalar(scalar), addr.value, dst.text)
            return pvm.once(Tr.TreeBackExprValue(env3, cmds, dst, scalar))
        end,
        [Tr.ExprAtomicLoad] = function(self, env)
            local addr = expr_value(expr_to_back:one_uncached(self.addr, env))
            if addr == nil then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "unsupported atomic_load address")) end
            local scalar = back_scalar(self.ty)
            if scalar == nil then return pvm.once(Tr.TreeBackExprUnsupported(addr.env, addr.cmds, "atomic_load result has non-scalar type")) end
            local cmds = {}; append_all(cmds, addr.cmds)
            local env1, zero = env_next_value(addr.env, "v")
            local env2, dst = env_next_value(env1, "v")
            cmds[#cmds + 1] = Back.CmdConst(zero, Back.BackIndex, Back.BackLitInt("0"))
            cmds[#cmds + 1] = Back.CmdAtomicLoad(dst, scalar, address_from_ptr(addr.value, zero), memory_info("tree:atomic:load:" .. tostring(dst.text), Back.BackAccessRead), atomic_ordering(self.ordering))
            return pvm.once(Tr.TreeBackExprValue(env2, cmds, dst, scalar))
        end,
        [Tr.ExprAtomicRmw] = function(self, env)
            local addr = expr_value(expr_to_back:one_uncached(self.addr, env))
            if addr == nil then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "unsupported atomic_rmw address")) end
            local value = expr_value(expr_to_back:one_uncached(self.value, addr.env))
            if value == nil then return pvm.once(Tr.TreeBackExprUnsupported(addr.env, addr.cmds, "unsupported atomic_rmw value")) end
            local scalar = back_scalar(self.ty)
            if scalar == nil then return pvm.once(Tr.TreeBackExprUnsupported(value.env, value.cmds, "atomic_rmw result has non-scalar type")) end
            local cmds = {}; append_all(cmds, addr.cmds); append_all(cmds, value.cmds)
            local env1, zero = env_next_value(value.env, "v")
            local env2, dst = env_next_value(env1, "v")
            cmds[#cmds + 1] = Back.CmdConst(zero, Back.BackIndex, Back.BackLitInt("0"))
            cmds[#cmds + 1] = Back.CmdAtomicRmw(dst, atomic_rmw_op(self.op), scalar, address_from_ptr(addr.value, zero), value.value, memory_info("tree:atomic:rmw:" .. tostring(dst.text), Back.BackAccessReadWrite), atomic_ordering(self.ordering))
            return pvm.once(Tr.TreeBackExprValue(env2, cmds, dst, scalar))
        end,
        [Tr.ExprAtomicCas] = function(self, env)
            local addr = expr_value(expr_to_back:one_uncached(self.addr, env))
            if addr == nil then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "unsupported atomic_cas address")) end
            local expected = expr_value(expr_to_back:one_uncached(self.expected, addr.env))
            if expected == nil then return pvm.once(Tr.TreeBackExprUnsupported(addr.env, addr.cmds, "unsupported atomic_cas expected")) end
            local replacement = expr_value(expr_to_back:one_uncached(self.replacement, expected.env))
            if replacement == nil then return pvm.once(Tr.TreeBackExprUnsupported(expected.env, expected.cmds, "unsupported atomic_cas replacement")) end
            local scalar = back_scalar(self.ty)
            if scalar == nil then return pvm.once(Tr.TreeBackExprUnsupported(replacement.env, replacement.cmds, "atomic_cas result has non-scalar type")) end
            local cmds = {}; append_all(cmds, addr.cmds); append_all(cmds, expected.cmds); append_all(cmds, replacement.cmds)
            local env1, zero = env_next_value(replacement.env, "v")
            local env2, dst = env_next_value(env1, "v")
            cmds[#cmds + 1] = Back.CmdConst(zero, Back.BackIndex, Back.BackLitInt("0"))
            cmds[#cmds + 1] = Back.CmdAtomicCas(dst, scalar, address_from_ptr(addr.value, zero), expected.value, replacement.value, memory_info("tree:atomic:cas:" .. tostring(dst.text), Back.BackAccessReadWrite), atomic_ordering(self.ordering))
            return pvm.once(Tr.TreeBackExprValue(env2, cmds, dst, scalar))
        end,
        [Tr.ExprNull] = function(self, env)
            local ty = expr_ty(self)
            local scalar = back_scalar(ty)
            local env2, dst = env_next_value(env, "v")
            return pvm.once(Tr.TreeBackExprValue(env2, { Back.CmdConst(dst, scalar, Back.BackLitNull) }, dst, scalar))
        end,
        [Tr.ExprIsNull] = function(self, env)
            local value_env = pvm.one(expr_to_back(self.value, env))
            local env2, dst = env_next_value(value_env.env, "b")
            local _, zero_dst = env_next_value(env2, "z")
            local zero_cmds = { Back.CmdConst(zero_dst, Back.BackIndex, Back.BackLitInt("0")) }
            local cmds = pvm.cmds(value_env.cmds, zero_cmds, {
                Back.CmdCompare(dst, Back.BackIcmpEq, Back.BackBool, value_env.dst, zero_dst)
            })
            return pvm.once(Tr.TreeBackExprValue(value_env.env, cmds, dst, Back.BackBool))
        end,
        [Tr.ExprSlotValue] = function(_, env) return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "open expr slot reached backend; run open_expand/open_validate before lowering")) end,
        [Tr.ExprUseExprFrag] = function(_, env) return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "expr fragment use reached backend; run open_expand before lowering")) end,
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

    memory_info = function(access_text, mode)
        return Back.BackMemoryInfo(Back.BackAccessId(access_text), Back.BackAlignUnknown, Back.BackDerefUnknown, Back.BackMayTrap, Back.BackMayNotMove, mode)
    end

    atomic_ordering = function(ordering)
        if ordering == C.AtomicSeqCst then return Back.BackAtomicSeqCst end
        return Back.BackAtomicSeqCst
    end

    atomic_rmw_op = function(op)
        if op == C.AtomicRmwAdd then return Back.BackAtomicRmwAdd end
        if op == C.AtomicRmwSub then return Back.BackAtomicRmwSub end
        if op == C.AtomicRmwAnd then return Back.BackAtomicRmwAnd end
        if op == C.AtomicRmwOr then return Back.BackAtomicRmwOr end
        if op == C.AtomicRmwXor then return Back.BackAtomicRmwXor end
        if op == C.AtomicRmwXchg then return Back.BackAtomicRmwXchg end
        return Back.BackAtomicRmwXchg
    end

    address_from_ptr = function(ptr, offset)
        return Back.BackAddress(Back.BackAddrValue(ptr), offset, Back.BackProvUnknown, Back.BackPtrBoundsUnknown)
    end

    global_data_addr = function(env, data)
        local env2, dst = env_next_value(env, "v")
        return Tr.TreeBackExprValue(env2, { Back.CmdDataAddr(dst, data) }, dst, Back.BackPtr)
    end

    load_global_data = function(env, data, ty, access_tag)
        local scalar = back_scalar(ty)
        if scalar == nil then return Tr.TreeBackExprUnsupported(env, {}, "global load requires scalar backend type") end
        local env1, zero = env_next_value(env, "v")
        local env2, dst = env_next_value(env1, "v")
        local cmds = {
            Back.CmdConst(zero, Back.BackIndex, Back.BackLitInt("0")),
            Back.CmdLoadInfo(dst, shape_scalar(scalar), address_from_data(data, zero), memory_info("tree:global:" .. tostring(access_tag or data.text), Back.BackAccessRead)),
        }
        return Tr.TreeBackExprValue(env2, cmds, dst, scalar)
    end

    store_global_data = function(env, data, ty, value, access_tag)
        local rhs = expr_value(expr_to_back:one_uncached(value, env))
        if rhs == nil then return Tr.TreeBackStmtResult(env, {}, Back.BackTerminates) end
        local scalar = back_scalar(ty)
        if scalar == nil then return Tr.TreeBackStmtResult(rhs.env, rhs.cmds, Back.BackTerminates) end
        local cmds = {}; append_all(cmds, rhs.cmds)
        local env1, zero = env_next_value(rhs.env, "v")
        cmds[#cmds + 1] = Back.CmdConst(zero, Back.BackIndex, Back.BackLitInt("0"))
        cmds[#cmds + 1] = Back.CmdStoreInfo(shape_scalar(scalar), address_from_data(data, zero), rhs.value, memory_info("tree:global:" .. tostring(access_tag or data.text), Back.BackAccessWrite))
        return Tr.TreeBackStmtResult(env1, cmds, Back.BackFallsThrough)
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

    local function offset_view_data(base_view, offset_expr, elem_ty, scale_by_base_stride, reason)
        local cmds = {}; append_all(cmds, base_view.cmds); append_all(cmds, offset_expr.cmds)
        local current, elem_index = cast_to_index(offset_expr, offset_expr.env, cmds)
        if scale_by_base_stride then
            local env_mul, scaled = env_next_value(current, "v")
            cmds[#cmds + 1] = Back.CmdIntBinary(scaled, Back.BackIntMul, Back.BackIndex, int_sem_wrap(), elem_index, base_view.stride)
            current = env_mul; elem_index = scaled
        end
        local size = elem_size(elem_ty)
        if size == nil then return nil, current, cmds, "unknown view element size" end
        local env1, size_val = env_next_value(current, "v")
        local env2, off_val = env_next_value(env1, "v")
        local env3, data_val = env_next_value(env2, "v")
        cmds[#cmds + 1] = Back.CmdConst(size_val, Back.BackIndex, Back.BackLitInt(tostring(size)))
        cmds[#cmds + 1] = Back.CmdIntBinary(off_val, Back.BackIntMul, Back.BackIndex, int_sem_wrap(), elem_index, size_val)
        cmds[#cmds + 1] = Back.CmdPtrOffset(data_val, Back.BackAddrValue(base_view.data), off_val, 1, 0, Back.BackProvDerived(reason or "view data offset"), Back.BackPtrBoundsUnknown)
        return data_val, env3, cmds, nil
    end

    view_to_back = pvm.phase("moonlift_tree_view_to_back", {
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
        [Tr.ViewRestrided] = function(self, env)
            local base_view = expr_view_value(view_to_back:one_uncached(self.base, env))
            if base_view == nil then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "unsupported restrided base view")) end
            local stride = expr_value(expr_to_back:one_uncached(self.stride, base_view.env))
            if stride == nil then return pvm.once(Tr.TreeBackExprUnsupported(base_view.env, base_view.cmds, "unsupported restrided stride")) end
            local cmds = {}; append_all(cmds, base_view.cmds); append_all(cmds, stride.cmds)
            local current, stride_value = cast_to_index(stride, stride.env, cmds)
            return pvm.once(Tr.TreeBackExprStridedView(current, cmds, base_view.data, base_view.len, stride_value))
        end,
        [Tr.ViewRowBase] = function(self, env)
            local base_view = expr_view_value(view_to_back:one_uncached(self.base, env))
            if base_view == nil then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "unsupported row-base base view")) end
            local row = expr_value(expr_to_back:one_uncached(self.row_offset, base_view.env))
            if row == nil then return pvm.once(Tr.TreeBackExprUnsupported(base_view.env, base_view.cmds, "unsupported row-base offset")) end
            local data, current, cmds, err = offset_view_data(base_view, row, view_elem(self), true, "view row base")
            if data == nil then return pvm.once(Tr.TreeBackExprUnsupported(current, cmds, err)) end
            return pvm.once(Tr.TreeBackExprStridedView(current, cmds, data, base_view.len, base_view.stride))
        end,
        [Tr.ViewInterleaved] = function(self, env)
            local data = expr_value(expr_to_back:one_uncached(self.data, env))
            if data == nil then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "unsupported interleaved data")) end
            local len = expr_value(expr_to_back:one_uncached(self.len, data.env))
            if len == nil then return pvm.once(Tr.TreeBackExprUnsupported(data.env, data.cmds, "unsupported interleaved len")) end
            local stride = expr_value(expr_to_back:one_uncached(self.stride, len.env))
            if stride == nil then return pvm.once(Tr.TreeBackExprUnsupported(len.env, len.cmds, "unsupported interleaved stride")) end
            local cmds = {}; append_all(cmds, data.cmds); append_all(cmds, len.cmds); append_all(cmds, stride.cmds)
            local current, len_value = cast_to_index(len, stride.env, cmds)
            local current2, stride_value = cast_to_index(stride, current, cmds)
            local lane = expr_value(expr_to_back:one_uncached(self.lane, current2))
            if lane == nil then return pvm.once(Tr.TreeBackExprUnsupported(current2, cmds, "unsupported interleaved lane")) end
            local base_view = Tr.TreeBackExprStridedView(current2, cmds, data.value, len_value, stride_value)
            local lane_expr = Tr.TreeBackExprValue(lane.env, lane.cmds, lane.value, lane.ty)
            local data_value, current3, out_cmds, err = offset_view_data(base_view, lane_expr, self.elem, false, "view interleaved lane")
            if data_value == nil then return pvm.once(Tr.TreeBackExprUnsupported(current3, out_cmds, err)) end
            return pvm.once(Tr.TreeBackExprStridedView(current3, out_cmds, data_value, len_value, stride_value))
        end,
        [Tr.ViewInterleavedView] = function(self, env)
            local base_view = expr_view_value(view_to_back:one_uncached(self.base, env))
            if base_view == nil then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "unsupported interleaved-view base")) end
            local stride = expr_value(expr_to_back:one_uncached(self.stride, base_view.env))
            if stride == nil then return pvm.once(Tr.TreeBackExprUnsupported(base_view.env, base_view.cmds, "unsupported interleaved-view stride")) end
            local base_cmds = {}; append_all(base_cmds, base_view.cmds); append_all(base_cmds, stride.cmds)
            local current2, stride_value = cast_to_index(stride, stride.env, base_cmds)
            local lane = expr_value(expr_to_back:one_uncached(self.lane, current2))
            if lane == nil then return pvm.once(Tr.TreeBackExprUnsupported(current2, base_cmds, "unsupported interleaved-view lane")) end
            local base_for_offset = Tr.TreeBackExprStridedView(current2, base_cmds, base_view.data, base_view.len, base_view.stride)
            local lane_expr = Tr.TreeBackExprValue(lane.env, lane.cmds, lane.value, lane.ty)
            local data_value, current, cmds, err = offset_view_data(base_for_offset, lane_expr, self.elem, true, "view interleaved-view lane")
            if data_value == nil then return pvm.once(Tr.TreeBackExprUnsupported(current, cmds, err)) end
            local env_mul, composed_stride = env_next_value(current, "v")
            cmds[#cmds + 1] = Back.CmdIntBinary(composed_stride, Back.BackIntMul, Back.BackIndex, int_sem_wrap(), base_view.stride, stride_value)
            return pvm.once(Tr.TreeBackExprStridedView(env_mul, cmds, data_value, base_view.len, composed_stride))
        end,
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

    index_addr_to_back = pvm.phase("moonlift_tree_index_addr_to_back", {
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
        [Tr.IndexBasePlace] = function(self, index, elem_ty, env)
            local base = expr_value(place_addr_to_back:one_uncached(self.base, env))
            if base == nil then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "unsupported place index base")) end
            local idx = expr_value(expr_to_back:one_uncached(index, base.env))
            if idx == nil then return pvm.once(Tr.TreeBackExprUnsupported(base.env, base.cmds, "unsupported place index value")) end
            local size = elem_size(elem_ty)
            if size == nil then return pvm.once(Tr.TreeBackExprUnsupported(idx.env, idx.cmds, "unknown place-indexed element size")) end
            local current = idx.env
            local index_value = idx.value
            local cmds = {}; append_all(cmds, base.cmds); append_all(cmds, idx.cmds)
            if idx.ty ~= Back.BackIndex then
                local cast_env, cast_val = env_next_value(current, "v")
                cmds[#cmds + 1] = Back.CmdCast(cast_val, Back.BackSextend, Back.BackIndex, idx.value)
                current = cast_env
                index_value = cast_val
            end
            local env1, size_val = env_next_value(current, "v")
            local env2, off_val = env_next_value(env1, "v")
            local env3, addr_val = env_next_value(env2, "v")
            cmds[#cmds + 1] = Back.CmdConst(size_val, Back.BackIndex, Back.BackLitInt(tostring(size)))
            cmds[#cmds + 1] = Back.CmdIntBinary(off_val, Back.BackIntMul, Back.BackIndex, int_sem_wrap(), index_value, size_val)
            cmds[#cmds + 1] = Back.CmdPtrOffset(addr_val, Back.BackAddrValue(base.value), off_val, 1, 0, Back.BackProvDerived("place index address"), Back.BackPtrBoundsUnknown)
            return pvm.once(Tr.TreeBackExprValue(env3, cmds, addr_val, Back.BackPtr))
        end,
        [Tr.IndexBaseExpr] = function(_, _, _, env) return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "untyped index base reached backend")) end,
    }, { args_cache = "last" })

    place_addr_to_back = pvm.phase("moonlift_tree_place_addr_to_back", {
        [Tr.PlaceIndex] = function(self, env)
            return pvm.once(index_addr_to_back:one_uncached(self.base, self.index, self.h.ty, env))
        end,
        [Tr.PlaceDeref] = function(self, env)
            local addr = expr_value(expr_to_back:one_uncached(self.base, env))
            if addr == nil then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "unsupported deref place address")) end
            return pvm.once(addr)
        end,
        [Tr.PlaceField] = function(self, env)
            local field = self.field
            if pvm.classof(field) ~= Sem.FieldByOffset then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "field address requires resolved offset")) end
            local base = nil
            if pvm.classof(self.base) == Tr.PlaceRef then
                local h = self.base.h
                if pvm.classof(h) == Tr.PlaceTyped and pvm.classof(h.ty) == Ty.TPtr then
                    base = expr_value(expr_to_back:one_uncached(Tr.ExprRef(Tr.ExprTyped(h.ty), self.base.ref), env))
                end
            end
            if base == nil then base = expr_value(place_addr_to_back:one_uncached(self.base, env)) end
            if base == nil then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "unsupported field base address")) end
            return pvm.once(field_addr_from_base_ptr(base, field))
        end,
        [Tr.PlaceRef] = function(self, env)
            local ref_cls = pvm.classof(self.ref)
            if ref_cls == Bn.ValueRefBinding then
                -- Check for aggregate binding stored in lower_context (only if binding has aggregate type)
                if is_aggregate_type(self.ref.binding.ty) then
                    local slot = lower_context.agg_binding_slots and lower_context.agg_binding_slots[binding_key(self.ref.binding)] or nil
                    local class = self.ref.binding.class
                    local class_cls = pvm.classof(class)
                    if slot == nil and (class_cls == Bn.BindingClassLocalValue or class_cls == Bn.BindingClassLocalCell) then
                        slot = stack_slot_for_binding(self.ref.binding)
                    end
                    if slot then
                        local env1, addr = env_next_value(env, "addr")
                        local cmds = { Back.CmdStackAddr(addr, slot) }
                        return pvm.once(Tr.TreeBackExprValue(env1, cmds, addr, Back.BackPtr))
                    end
                end
                local local_entry = env_lookup(env, self.ref.binding)
                if local_entry ~= nil and pvm.classof(local_entry) == Tr.TreeBackStackLocal then
                    local env1, addr = env_next_value(env, "addr")
                    return pvm.once(Tr.TreeBackExprValue(env1, { Back.CmdStackAddr(addr, local_entry.slot) }, addr, Back.BackPtr))
                end
                if local_entry ~= nil and pvm.classof(local_entry) == Tr.TreeBackScalarLocal then
                    if is_aggregate_type(self.ref.binding.ty) and local_entry.ty == Back.BackPtr then
                        return pvm.once(Tr.TreeBackExprValue(env, {}, local_entry.value, Back.BackPtr))
                    end
                    local scalar = back_scalar(self.ref.binding.ty) or local_entry.ty
                    local size, align = elem_size(self.ref.binding.ty), elem_align(self.ref.binding.ty)
                    if size == nil or align == nil then size, align = scalar_size_align(scalar) end
                    if size ~= nil and align ~= nil then
                        local slot = stack_slot_for_binding(self.ref.binding)
                        local env1, addr = env_next_value(env, "addr")
                        local cmds = { Back.CmdCreateStackSlot(slot, size, align), Back.CmdStackAddr(addr, slot) }
                        local env2 = append_store_info(cmds, env1, shape_scalar(scalar), addr, local_entry.value, "stack:addr:" .. tostring(self.ref.binding.name))
                        local env3 = env_add_stack(env2, self.ref.binding, slot, scalar)
                        return pvm.once(Tr.TreeBackExprValue(env3, cmds, addr, Back.BackPtr))
                    end
                end
                local class = self.ref.binding.class
                local class_cls = pvm.classof(class)
                if class_cls == Bn.BindingClassGlobalStatic or class_cls == Bn.BindingClassGlobalConst then
                    return pvm.once(global_data_addr(env, data_id_for_global(class.module_name, class.item_name)))
                end
            elseif ref_cls == Bn.ValueRefHole then
                local slot_cls = pvm.classof(self.ref.slot)
                if slot_cls == O.SlotStatic then
                    local slot = self.ref.slot.slot
                    local data = lower_context.slot_statics and lower_context.slot_statics[slot.key] or nil
                    if data ~= nil then return pvm.once(global_data_addr(env, data)) end
                elseif slot_cls == O.SlotConst then
                    local slot = self.ref.slot.slot
                    local data = lower_context.slot_consts_data and lower_context.slot_consts_data[slot.key] or nil
                    if data ~= nil then return pvm.once(global_data_addr(env, data)) end
                end
            end
            return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "address of binding requires a stack/global storage location"))
        end,
        [Tr.PlaceDot] = function(_, env) return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "dot place reached backend; run semantic layout resolution before lowering")) end,
        [Tr.PlaceSlotValue] = function(_, env) return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "open place slot reached backend; run open_expand/open_validate before lowering")) end,
    }, { args_cache = "last" })

    expr_base_addr_to_back = function(expr, env)
        local ty = expr_ty(expr)
        if pvm.classof(ty) == Ty.TPtr then return expr_value(expr_to_back:one_uncached(expr, env)) end
        local cls = pvm.classof(expr)
        if cls == Tr.ExprRef then
            if pvm.classof(expr.ref) == Bn.ValueRefBinding and is_aggregate_type(expr.ref.binding.ty) then
                local local_entry = env_lookup(env, expr.ref.binding)
                if local_entry ~= nil and pvm.classof(local_entry) == Tr.TreeBackScalarLocal and local_entry.ty == Back.BackPtr then
                    return Tr.TreeBackExprValue(env, {}, local_entry.value, Back.BackPtr)
                end
                local slot = lower_context.agg_binding_slots and lower_context.agg_binding_slots[binding_key(expr.ref.binding)] or stack_slot_for_binding(expr.ref.binding)
                local env1, addr = env_next_value(env, "addr")
                return Tr.TreeBackExprValue(env1, { Back.CmdStackAddr(addr, slot) }, addr, Back.BackPtr)
            end
            return expr_value(place_addr_to_back:one_uncached(Tr.PlaceRef(Tr.PlaceTyped(ty), expr.ref), env))
        end
        if cls == Tr.ExprDeref then
            return expr_value(expr_to_back:one_uncached(expr.value, env))
        end
        if cls == Tr.ExprField and pvm.classof(expr.field) == Sem.FieldByOffset then
            local base = expr_base_addr_to_back(expr.base, env)
            if base == nil then return nil end
            return field_addr_from_base_ptr(base, expr.field)
        end
        if cls == Tr.ExprIndex then
            return expr_value(index_addr_to_back:one_uncached(expr.base, expr.index, expr_ty(expr), env))
        end
        return expr_value(expr_to_back:one_uncached(expr, env))
    end

    local function lowering_unsupported(reason)
        error("moonlift tree_to_back unsupported lowering: " .. tostring(reason), 2)
    end

    append_memcpy = function(cmds, current, dst, src, size, tag)
        local env1, len = env_next_value(current, "v")
        cmds[#cmds + 1] = Back.CmdConst(len, Back.BackIndex, Back.BackLitInt(tostring(size)))
        cmds[#cmds + 1] = Back.CmdMemcpy(dst, src, len)
        return env1
    end

    local function store_at_addr(place, value, env)
        local addr = expr_value(place_addr_to_back:one_uncached(place, env))
        if addr == nil then
            local reason = "store address could not be lowered"
            local lowered_addr = place_addr_to_back:one_uncached(place, env)
            if pvm.classof(lowered_addr) == Tr.TreeBackExprUnsupported then reason = reason .. ": " .. tostring(lowered_addr.reason) .. " at " .. tostring(place) end
            lowering_unsupported(reason)
        end
        local rhs = expr_value(expr_to_back:one_uncached(value, addr.env))
        if rhs == nil then return pvm.once(Tr.TreeBackStmtResult(addr.env, addr.cmds, Back.BackTerminates)) end
        local field = pvm.classof(place) == Tr.PlaceField and place.field or nil
        local scalar = field and field_storage_scalar(field) or back_scalar(place.h.ty)
        local cmds = {}; append_all(cmds, addr.cmds); append_all(cmds, rhs.cmds)
        local current = rhs.env
        if scalar == nil and is_aggregate_type(place.h.ty) then
            local sz = elem_size(place.h.ty)
            if sz == nil then return pvm.once(Tr.TreeBackStmtResult(rhs.env, rhs.cmds, Back.BackTerminates)) end
            current = append_memcpy(cmds, current, addr.value, rhs.value, sz, tostring(addr.value.text) .. ":copy")
            return pvm.once(Tr.TreeBackStmtResult(current, cmds, Back.BackFallsThrough))
        end
        if scalar == nil then return pvm.once(Tr.TreeBackStmtResult(rhs.env, rhs.cmds, Back.BackTerminates)) end
        local store_value = rhs.value
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

    place_store_to_back = pvm.phase("moonlift_tree_place_store_to_back", {
        [Tr.PlaceIndex] = function(self, value, env) return store_at_addr(self, value, env) end,
        [Tr.PlaceDeref] = function(self, value, env) return store_at_addr(self, value, env) end,
        [Tr.PlaceField] = function(self, value, env) return store_at_addr(self, value, env) end,
        [Tr.PlaceRef] = function(self, value, env)
            if pvm.classof(self.ref) == Bn.ValueRefBinding and pvm.classof(self.ref.binding.class) == Bn.BindingClassGlobalStatic then
                local class = self.ref.binding.class
                return pvm.once(store_global_data(env, data_id_for_global(class.module_name, class.item_name), self.ref.binding.ty, value, class.item_name))
            end
            if pvm.classof(self.ref) == Bn.ValueRefHole and pvm.classof(self.ref.slot) == O.SlotStatic then
                local slot = self.ref.slot.slot
                local data = lower_context.slot_statics and lower_context.slot_statics[slot.key] or nil
                if data ~= nil then return pvm.once(store_global_data(env, data, slot.ty, value, slot.pretty_name)) end
            end
            -- Local cell mutation. Stack-backed cells update their slot;
            -- value-backed cells (legacy/non-addressed) rebind through SSA.
            if pvm.classof(self.ref) == Bn.ValueRefBinding and self.ref.binding.class == Bn.BindingClassLocalCell then
                local local_entry = env_lookup(env, self.ref.binding)
                if local_entry ~= nil and pvm.classof(local_entry) == Tr.TreeBackStackLocal then
                    return store_at_addr(self, value, env)
                end
                local rhs = expr_value(expr_to_back:one_uncached(value, env))
                if rhs == nil then return pvm.once(Tr.TreeBackStmtResult(env, {}, Back.BackFallsThrough)) end
                local scalar = back_scalar(self.ref.binding.ty) or rhs.ty
                local env2, alias = env_next_value(rhs.env, "var")
                local cmds = {}
                append_all(cmds, rhs.cmds)
                cmds[#cmds + 1] = Back.CmdAlias(alias, rhs.value)
                local env3 = env_add(env2, self.ref.binding, alias, scalar)
                return pvm.once(Tr.TreeBackStmtResult(env3, cmds, Back.BackFallsThrough))
            end
            return pvm.once(Tr.TreeBackStmtResult(env, {}, Back.BackFallsThrough))
        end,
        [Tr.PlaceDot] = function() lowering_unsupported("dot place reached backend; run semantic layout resolution before lowering") end,
        [Tr.PlaceSlotValue] = function() lowering_unsupported("open place slot reached backend; run open_expand/open_validate before lowering") end,
    }, { args_cache = "last" })

    local function lower_if_stmt(self, env)
        local cond = expr_value(expr_to_back:one_uncached(self.cond, env))
        if cond == nil then lowering_unsupported("if statement condition could not be lowered") end

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
        local then_jump_pos = nil
        if then_flow ~= Back.BackTerminates then
            then_cmds[#then_cmds + 1] = Back.CmdJump(join_block, {})
            then_jump_pos = #cmds + #then_cmds  -- absolute index in cmds after append
        end
        local then_cmds_start = #cmds + 1
        append_all(cmds, then_cmds)
        -- Adjust: then_jump_pos is relative to then_cmds, absolute in cmds
        if then_flow ~= Back.BackTerminates then then_jump_pos = then_cmds_start + #then_cmds - 1 end

        cmds[#cmds + 1] = Back.CmdSwitchToBlock(else_block)
        local else_start = env_with_locals(env_with_counters(env, then_env), env.locals)
        local else_env, else_cmds, else_flow = lower_body(self.else_body, else_start)
        if else_flow ~= Back.BackTerminates then else_cmds[#else_cmds + 1] = Back.CmdJump(join_block, {}) end
        local else_jump_pos = else_flow ~= Back.BackTerminates and (#cmds + #else_cmds + 1) or nil  -- +1 for SwitchToBlock
        local else_cmds_start = #cmds + 1
        append_all(cmds, else_cmds)
        if else_flow ~= Back.BackTerminates then else_jump_pos = else_cmds_start + #else_cmds - 1 end

        -- Phi analysis: find LocalCell bindings mutated in either branch.
        -- For each, emit a CmdAppendBlockParam on the join block and thread
        -- the correct value from each branch through the jump args.
        local out_locals = {}
        for i = 1, #env.locals do out_locals[#out_locals + 1] = env.locals[i] end

        local phi_then_args = {}
        local phi_else_args = {}
        local pre_counters = env_with_counters(env, else_env)

        for i = 1, #env.locals do
            local local_entry = env.locals[i]
            if pvm.classof(local_entry) == Tr.TreeBackScalarLocal
                and local_entry.binding.class == Bn.BindingClassLocalCell then
                local then_val = env_lookup(then_env, local_entry.binding)
                local else_val = env_lookup(else_env, local_entry.binding)
                local then_v = then_val and then_val.value or local_entry.value
                local else_v = else_val and else_val.value or local_entry.value
                -- Only emit phi if at least one branch changed the value
                local changed = (then_v ~= local_entry.value) or (else_v ~= local_entry.value)
                if changed then
                    local phi_env, phi_val = env_next_value(pre_counters, "phi")
                    pre_counters = phi_env
                    cmds[#cmds + 1] = Back.CmdAppendBlockParam(join_block, phi_val, shape_scalar(local_entry.ty))
                    phi_then_args[#phi_then_args + 1] = then_v
                    phi_else_args[#phi_else_args + 1] = else_v
                    -- Rebind the local to the phi value in out_locals
                    out_locals[#out_locals + 1] = Tr.TreeBackScalarLocal(local_entry.binding, phi_val, local_entry.ty)
                end
            end
        end

        -- Patch the branch jumps to include phi args
        if #phi_then_args > 0 then
            if then_flow ~= Back.BackTerminates and then_jump_pos ~= nil then
                cmds[then_jump_pos] = Back.CmdJump(join_block, phi_then_args)
            end
            if else_flow ~= Back.BackTerminates and else_jump_pos ~= nil then
                cmds[else_jump_pos] = Back.CmdJump(join_block, phi_else_args)
            end
        end

        local out_env = Tr.TreeBackEnv(out_locals, pre_counters.next_value, pre_counters.next_block, env.ret)
        cmds[#cmds + 1] = Back.CmdSealBlock(join_block)
        if then_flow ~= Back.BackTerminates or else_flow ~= Back.BackTerminates then
            cmds[#cmds + 1] = Back.CmdSwitchToBlock(join_block)
            return pvm.once(Tr.TreeBackStmtResult(out_env, cmds, Back.BackFallsThrough))
        end
        return pvm.once(Tr.TreeBackStmtResult(out_env, cmds, Back.BackTerminates))
    end

    local function lower_switch_stmt(self, env)
        if #self.variant_arms > 0 then lowering_unsupported("variant switch statement lowering is not implemented") end

        local value = expr_value(expr_to_back:one_uncached(self.value, env))
        if value == nil then lowering_unsupported("switch statement value could not be lowered") end

        local case_raws = {}
        for i = 1, #self.arms do
            local raw = switch_key_raw_value(self.arms[i].raw_key)
            if raw == nil then return pvm.once(Tr.TreeBackStmtResult(value.env, value.cmds, Back.BackTerminates)) end
            case_raws[#case_raws + 1] = raw
        end

        local current = value.env
        local arm_blocks = {}
        for i = 1, #self.arms do current, arm_blocks[i] = env_next_block(current, "switch.stmt.arm") end
        local default_block; current, default_block = env_next_block(current, "switch.stmt.default")
        local join_block; current, join_block = env_next_block(current, "switch.stmt.join")

        local cmds = {}
        append_all(cmds, value.cmds)
        for i = 1, #arm_blocks do cmds[#cmds + 1] = Back.CmdCreateBlock(arm_blocks[i]) end
        cmds[#cmds + 1] = Back.CmdCreateBlock(default_block)
        cmds[#cmds + 1] = Back.CmdCreateBlock(join_block)
        local cases = {}
        for i = 1, #case_raws do cases[i] = Back.BackSwitchCase(case_raws[i], arm_blocks[i]) end
        cmds[#cmds + 1] = Back.CmdSwitchInt(value.value, value.ty, cases, default_block)
        for i = 1, #arm_blocks do cmds[#cmds + 1] = Back.CmdSealBlock(arm_blocks[i]) end
        cmds[#cmds + 1] = Back.CmdSealBlock(default_block)

        local fallers = {}
        for i = 1, #self.arms do
            cmds[#cmds + 1] = Back.CmdSwitchToBlock(arm_blocks[i])
            local start = env_with_locals(env_with_counters(value.env, current), value.env.locals)
            local arm_env, arm_cmds, arm_flow = lower_body(self.arms[i].body, start)
            append_all(cmds, arm_cmds)
            if arm_flow ~= Back.BackTerminates then
                local jump_pos = #cmds + 1
                cmds[jump_pos] = Back.CmdJump(join_block, {})
                fallers[#fallers + 1] = { env = arm_env, jump_pos = jump_pos, args = {} }
            end
            current = env_with_counters(current, arm_env)
        end

        cmds[#cmds + 1] = Back.CmdSwitchToBlock(default_block)
        local default_start = env_with_locals(env_with_counters(value.env, current), value.env.locals)
        local default_env, default_cmds, default_flow = lower_body(self.default_body or {}, default_start)
        append_all(cmds, default_cmds)
        if default_flow ~= Back.BackTerminates then
            local jump_pos = #cmds + 1
            cmds[jump_pos] = Back.CmdJump(join_block, {})
            fallers[#fallers + 1] = { env = default_env, jump_pos = jump_pos, args = {} }
        end
        current = env_with_counters(current, default_env)

        local out_locals = {}
        for i = 1, #value.env.locals do out_locals[#out_locals + 1] = value.env.locals[i] end
        local pre_counters = current
        if #fallers > 0 then
            for i = 1, #value.env.locals do
                local local_entry = value.env.locals[i]
                if pvm.classof(local_entry) == Tr.TreeBackScalarLocal
                    and local_entry.binding.class == Bn.BindingClassLocalCell then
                    local changed = false
                    local vals = {}
                    for j = 1, #fallers do
                        local found = env_lookup(fallers[j].env, local_entry.binding)
                        local v = found and found.value or local_entry.value
                        vals[j] = v
                        if v ~= local_entry.value then changed = true end
                    end
                    if changed then
                        local phi_env, phi_val = env_next_value(pre_counters, "phi")
                        pre_counters = phi_env
                        cmds[#cmds + 1] = Back.CmdAppendBlockParam(join_block, phi_val, shape_scalar(local_entry.ty))
                        for j = 1, #fallers do fallers[j].args[#fallers[j].args + 1] = vals[j] end
                        out_locals[#out_locals + 1] = Tr.TreeBackScalarLocal(local_entry.binding, phi_val, local_entry.ty)
                    end
                end
            end
            for i = 1, #fallers do cmds[fallers[i].jump_pos] = Back.CmdJump(join_block, fallers[i].args) end
        end

        local out_env = Tr.TreeBackEnv(out_locals, pre_counters.next_value, pre_counters.next_block, value.env.ret)
        cmds[#cmds + 1] = Back.CmdSealBlock(join_block)
        if #fallers > 0 then
            cmds[#cmds + 1] = Back.CmdSwitchToBlock(join_block)
            return pvm.once(Tr.TreeBackStmtResult(out_env, cmds, Back.BackFallsThrough))
        end
        return pvm.once(Tr.TreeBackStmtResult(out_env, cmds, Back.BackTerminates))
    end

    stmt_to_back = pvm.phase("moonlift_tree_stmt_to_back", {
        [Tr.StmtLet] = function(self, env)
            -- For aggregate-typed bindings, create a stack slot for the binding itself
            if is_aggregate_type(self.binding.ty) then
                local binding_size = elem_size(self.binding.ty)
                local binding_align = elem_align(self.binding.ty)
                if binding_size == nil or binding_align == nil then
                    return pvm.once(Tr.TreeBackStmtResult(env, {}, Back.BackFallsThrough))
                end
                local slot = new_stack_slot_for_binding(self.binding)
                local cmds = { Back.CmdCreateStackSlot(slot, binding_size, binding_align) }
                local lowered = expr_to_back:one_uncached(self.init, env)
                local init = expr_value(lowered)
                if init == nil then lowering_unsupported("aggregate let initializer could not be lowered") end
                append_all(cmds, init.cmds)
                local env1, addr = env_next_value(init.env, "addr")
                cmds[#cmds + 1] = Back.CmdStackAddr(addr, slot)
                local current = append_memcpy(cmds, env1, addr, init.value, binding_size, "agg-let:" .. tostring(self.binding.name))
                -- Don't add to environment - aggregate bindings are accessed via field/index/address, not direct reference
                -- Store slot in lower_context for later PlaceRef lookup
                if not lower_context.agg_binding_slots then lower_context.agg_binding_slots = {} end
                lower_context.agg_binding_slots[binding_key(self.binding)] = slot
                return pvm.once(Tr.TreeBackStmtResult(current, cmds, Back.BackFallsThrough))
            end

            if binding_is_stack_local(self.binding) then
                local init = expr_value(expr_to_back:one_uncached(self.init, env))
                if init == nil then lowering_unsupported("stack local initializer could not be lowered") end
                local scalar = back_scalar(self.binding.ty) or init.ty
                local size, align = elem_size(self.binding.ty), elem_align(self.binding.ty)
                if size == nil or align == nil then size, align = scalar_size_align(scalar) end
                if size == nil or align == nil then return pvm.once(Tr.TreeBackStmtResult(init.env, init.cmds, Back.BackTerminates)) end
                local slot = stack_slot_for_binding(self.binding)
                local env1, addr = env_next_value(init.env, "addr")
                local cmds = { Back.CmdCreateStackSlot(slot, size, align) }
                append_all(cmds, init.cmds)
                cmds[#cmds + 1] = Back.CmdStackAddr(addr, slot)
                local env2 = append_store_info(cmds, env1, shape_scalar(scalar), addr, init.value, "stack:init:" .. tostring(self.binding.name))
                local env3 = env_add_stack(env2, self.binding, slot, scalar)
                return pvm.once(Tr.TreeBackStmtResult(env3, cmds, Back.BackFallsThrough))
            end

            local lowered = expr_to_back:one_uncached(self.init, env)
            local view_init = expr_view_value(lowered)
            if view_init ~= nil then
                if not is_view_type(self.binding.ty) then lowering_unsupported("view initializer assigned to non-view binding") end
                local env2
                if pvm.classof(view_init) == Tr.TreeBackExprStridedView then env2 = env_add_strided_view(view_init.env, self.binding, view_init.data, view_init.len, view_init.stride)
                else env2 = env_add_view(view_init.env, self.binding, view_init.data, view_init.len) end
                return pvm.once(Tr.TreeBackStmtResult(env2, view_init.cmds, Back.BackFallsThrough))
            end
            local init = expr_value(lowered)
            if init == nil then
                local reason = pvm.classof(lowered) == Tr.TreeBackExprUnsupported and lowered.reason or "let initializer could not be lowered"
                lowering_unsupported("let initializer could not be lowered: " .. tostring(reason) .. " at " .. tostring(self.init))
            end
            local scalar = back_scalar(self.binding.ty) or init.ty
            local env2 = env_add(init.env, self.binding, init.value, scalar)
            return pvm.once(Tr.TreeBackStmtResult(env2, init.cmds, Back.BackFallsThrough))
        end,
        [Tr.StmtExpr] = function(self, env)
            if pvm.classof(self.expr) == Tr.ExprCall then
                local ty = expr_ty(self.expr)
                if pvm.classof(ty) == Ty.TScalar and ty.scalar == C.ScalarVoid and pvm.classof(self.expr.callee) == Tr.ExprClosure then
                    return pvm.once(lower_closure_call(self.expr, env, false))
                end
                if pvm.classof(ty) == Ty.TScalar and ty.scalar == C.ScalarVoid then
                    local args, params, cmds, current = {}, {}, {}, env
                    for i = 1, #self.expr.args do
                        local arg = expr_value(expr_to_back:one_uncached(self.expr.args[i], current))
                        if arg == nil then return pvm.once(Tr.TreeBackStmtResult(current, cmds, Back.BackFallsThrough)) end
                        append_all(cmds, arg.cmds); args[#args + 1] = arg.value; params[#params + 1] = arg.ty; current = arg.env
                    end
                    local target = call_target(self.expr.callee, current)
                    if target == nil then return pvm.once(Tr.TreeBackStmtResult(current, cmds, Back.BackFallsThrough)) end
                    lower_context.callstmt_seq = (lower_context.callstmt_seq or 0) + 1
                    local sig_prefix = "sig:callstmt:" .. tostring(lower_context.module_name or "") .. ":" .. tostring(lower_context.current_func or "") .. ":"
                    local sig, declare_call_sig = Back.BackSigId(sig_prefix .. tostring(lower_context.callstmt_seq)), true
                    if pvm.classof(target) == Back.BackCallExtern then
                        sig = Back.BackSigId("sig:extern:" .. tostring(target.func.text))
                        declare_call_sig = false
                    elseif pvm.classof(target) == Back.BackCallDirect then
                        sig = Back.BackSigId("sig:" .. tostring(target.func.text))
                        declare_call_sig = false
                    end
                    if declare_call_sig then cmds[#cmds + 1] = Back.CmdCreateSig(sig, params, {}) end
                    cmds[#cmds + 1] = Back.CmdCall(Back.BackCallStmt, target, sig, args)
                    return pvm.once(Tr.TreeBackStmtResult(current, cmds, Back.BackFallsThrough))
                end
            end
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
            if value == nil then
                local reason = pvm.classof(lowered) == Tr.TreeBackExprUnsupported and lowered.reason or "return value could not be lowered"
                lowering_unsupported("return value could not be lowered: " .. tostring(reason))
            end
            local cmds = {}; append_all(cmds, value.cmds); cmds[#cmds + 1] = Back.CmdReturnValue(value.value)
            return pvm.once(Tr.TreeBackStmtResult(value.env, cmds, Back.BackTerminates))
        end,
        [Tr.StmtReturnVoid] = function(_, env) return pvm.once(Tr.TreeBackStmtResult(env, { Back.CmdReturnVoid }, Back.BackTerminates)) end,
        [Tr.StmtVar] = function(self, env)
            if not binding_is_stack_local(self.binding) then
                return pvm.once(stmt_to_back:one_uncached(Tr.StmtLet(self.h, self.binding, self.init), env))
            end
            -- For aggregate-typed var bindings, create a stack slot for the binding itself
            if is_aggregate_type(self.binding.ty) then
                local binding_size = elem_size(self.binding.ty)
                local binding_align = elem_align(self.binding.ty)
                if binding_size == nil or binding_align == nil then
                    return pvm.once(Tr.TreeBackStmtResult(env, {}, Back.BackFallsThrough))
                end
                local slot = new_stack_slot_for_binding(self.binding)
                local cmds = { Back.CmdCreateStackSlot(slot, binding_size, binding_align) }
                local lowered = expr_to_back:one_uncached(self.init, env)
                local init = expr_value(lowered)
                if init == nil then lowering_unsupported("aggregate var initializer could not be lowered") end
                append_all(cmds, init.cmds)
                local env1, addr = env_next_value(init.env, "addr")
                cmds[#cmds + 1] = Back.CmdStackAddr(addr, slot)
                local current = append_memcpy(cmds, env1, addr, init.value, binding_size, "agg-var:" .. tostring(self.binding.name))
                -- Don't add to environment - aggregate bindings are accessed via field/index/address, not direct reference
                -- Store slot in lower_context for later PlaceRef lookup
                if not lower_context.agg_binding_slots then lower_context.agg_binding_slots = {} end
                lower_context.agg_binding_slots[binding_key(self.binding)] = slot
                return pvm.once(Tr.TreeBackStmtResult(current, cmds, Back.BackFallsThrough))
            end
            local init = expr_value(expr_to_back:one_uncached(self.init, env))
            if init == nil then lowering_unsupported("var initializer could not be lowered") end
            local scalar = back_scalar(self.binding.ty) or init.ty
            local size, align = elem_size(self.binding.ty), elem_align(self.binding.ty)
            if size == nil or align == nil then
                size, align = scalar_size_align(scalar)
            end
            if size == nil or align == nil then return pvm.once(Tr.TreeBackStmtResult(init.env, init.cmds, Back.BackTerminates)) end
            local slot = stack_slot_for_binding(self.binding)
            local env1, addr = env_next_value(init.env, "addr")
            local cmds = { Back.CmdCreateStackSlot(slot, size, align) }
            append_all(cmds, init.cmds)
            cmds[#cmds + 1] = Back.CmdStackAddr(addr, slot)
            local env2 = append_store_info(cmds, env1, shape_scalar(scalar), addr, init.value, "stack:init:" .. tostring(self.binding.name))
            local env3 = env_add_stack(env2, self.binding, slot, scalar)
            return pvm.once(Tr.TreeBackStmtResult(env3, cmds, Back.BackFallsThrough))
        end,
        [Tr.StmtSet] = function(self, env) return pvm.once(place_store_to_back:one_uncached(self.place, self.value, env)) end,
        [Tr.StmtAtomicStore] = function(self, env)
            local addr = expr_value(expr_to_back:one_uncached(self.addr, env))
            if addr == nil then lowering_unsupported("atomic_store address could not be lowered") end
            local value = expr_value(expr_to_back:one_uncached(self.value, addr.env))
            if value == nil then return pvm.once(Tr.TreeBackStmtResult(addr.env, addr.cmds, Back.BackTerminates)) end
            local scalar = back_scalar(self.ty)
            if scalar == nil then return pvm.once(Tr.TreeBackStmtResult(value.env, value.cmds, Back.BackTerminates)) end
            local cmds = {}; append_all(cmds, addr.cmds); append_all(cmds, value.cmds)
            local env1, zero = env_next_value(value.env, "v")
            cmds[#cmds + 1] = Back.CmdConst(zero, Back.BackIndex, Back.BackLitInt("0"))
            cmds[#cmds + 1] = Back.CmdAtomicStore(scalar, address_from_ptr(addr.value, zero), value.value, memory_info("tree:atomic:store:" .. tostring(addr.value.text), Back.BackAccessWrite), atomic_ordering(self.ordering))
            return pvm.once(Tr.TreeBackStmtResult(env1, cmds, Back.BackFallsThrough))
        end,
        [Tr.StmtAtomicFence] = function(self, env) return pvm.once(Tr.TreeBackStmtResult(env, { Back.CmdAtomicFence(atomic_ordering(self.ordering)) }, Back.BackFallsThrough)) end,
        [Tr.StmtAssert] = function(_, env) return pvm.once(Tr.TreeBackStmtResult(env, {}, Back.BackFallsThrough)) end,
        [Tr.StmtIf] = lower_if_stmt,
        [Tr.StmtSwitch] = lower_switch_stmt,
        [Tr.StmtJump] = function() lowering_unsupported("jump statement reached function-body lowerer; control regions must lower jumps") end,
        [Tr.StmtJumpCont] = function() lowering_unsupported("continuation jump reached function-body lowerer; control regions must lower jumps") end,
        [Tr.StmtYieldVoid] = function() lowering_unsupported("yield statement reached function-body lowerer; control expressions must lower yields") end,
        [Tr.StmtYieldValue] = function() lowering_unsupported("yield value reached function-body lowerer; control expressions must lower yields") end,
        [Tr.StmtControl] = function(self, env) return pvm.once(control_api.stmt_region_to_back:one_uncached(self.region, env)) end,
        [Tr.StmtTrap] = function(_, env)
            return pvm.once(Tr.TreeBackStmtResult(env, { Back.CmdTrap }, Back.BackTerminates))
        end,
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
        env_lookup = env_lookup,
        env_with_locals = env_with_locals,
        env_with_counters = env_with_counters,
        env_next_value = env_next_value,
        env_next_block = env_next_block,
        expr_to_back = expr_to_back,
        stmt_to_back = stmt_to_back,
        back_scalar = back_scalar,
        elem_size = elem_size,
        elem_align = elem_align,
        const_eval = const_eval_api,
        get_const_env = function() return lower_context.const_env end,
        get_provenance = function() return lower_context.provenance end,
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

    local function abi_plan_error(plan)
        for i = 1, #plan.params do
            local param = plan.params[i]
            if pvm.classof(param) == Ty.AbiParamRejected then
                return "function parameter `" .. tostring(param.name) .. "` has no executable ABI: " .. tostring(param.reason)
            end
        end
        if pvm.classof(plan.result) == Ty.AbiResultRejected then
            return "function result has no executable ABI: " .. tostring(plan.result.reason)
        end
        return nil
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

    descriptor_field_load = function(cmds, current, desc, field_name, offset, scalar)
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
        local abi_err = abi_plan_error(abi_plan)
        if abi_err ~= nil then lowering_unsupported(abi_err .. " in `" .. tostring(name) .. "`") end
        local param_scalars, result_scalars = abi_param_scalars(abi_plan), abi_result_scalars(abi_plan)
        local env = env_from_abi_params(abi_plan)
        local param_vals = abi_param_values(abi_plan)
        local previous_func = lower_context.current_func
        local previous_stack_locals = lower_context.stack_locals
        local previous_agg_slots = lower_context.agg_binding_slots
        lower_context.current_func = name
        lower_context.stack_locals = collect_address_taken_stmts(body, {})
        lower_context.agg_binding_slots = {}
        local _, body_cmds, flow = lower_body(body, env)
        lower_context.current_func = previous_func
        lower_context.stack_locals = previous_stack_locals
        lower_context.agg_binding_slots = previous_agg_slots
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
            if #result_scalars == 0 then cmds[#cmds + 1] = Back.CmdReturnVoid else lowering_unsupported("non-void function can fall through without return: " .. tostring(name)) end
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
            local sig = Back.BackSigId("sig:extern:" .. func_node.symbol)
            local ps, rs = func_sig(func_node.params, func_node.result)
            return Tr.TreeBackItemResult({ Back.CmdCreateSig(sig, ps, rs), Back.CmdDeclareExtern(Back.BackExternId(func_node.symbol), func_node.symbol, sig) })
        end
        if cls == Tr.ExternFuncOpen then
            local sig = Back.BackSigId("sig:extern:" .. func_node.sym.symbol)
            local result_scalar = back_scalar(func_node.result)
            local rs = {}
            if result_scalar ~= nil and result_scalar ~= Back.BackVoid then rs[#rs + 1] = result_scalar end
            return Tr.TreeBackItemResult({ Back.CmdCreateSig(sig, {}, rs), Back.CmdDeclareExtern(Back.BackExternId(func_node.sym.symbol), func_node.sym.symbol, sig) })
        end
        return Tr.TreeBackItemResult({})
    end

    local lower_item_direct
    local lower_module_direct
    local with_module_context

    local function data_cmd_key(cmd)
        local k = cmd.kind
        if k == "CmdDeclareData" then return table.concat({ k, cmd.data.text, tostring(cmd.size), tostring(cmd.align) }, "\t") end
        if k == "CmdDataInitZero" then return table.concat({ k, cmd.data.text, tostring(cmd.offset), tostring(cmd.size) }, "\t") end
        if k == "CmdDataInit" then
            local v = cmd.value
            local value_key = v.kind
            if v.kind == "BackLitInt" or v.kind == "BackLitFloat" then value_key = value_key .. ":" .. v.raw
            elseif v.kind == "BackLitBool" then value_key = value_key .. ":" .. tostring(v.value)
            end
            return table.concat({ k, cmd.data.text, tostring(cmd.offset), cmd.ty.kind, value_key }, "\t")
        end
        return nil
    end

    local function decl_cmd_key(cmd)
        local k = cmd.kind
        if k == "CmdCreateSig" then return table.concat({ k, cmd.sig.text }, "\t"), "sig" end
        if k == "CmdDeclareFunc" then return table.concat({ k, cmd.func.text }, "\t"), "func" end
        if k == "CmdDeclareExtern" then return table.concat({ k, cmd.func.text }, "\t"), "extern" end
        return nil, nil
    end

    local function hoist_module_cmds(cmds)
        local sig_cmds, func_cmds, extern_cmds, data_cmds, other_cmds = {}, {}, {}, {}, {}
        local seen = {}
        for i = 1, #cmds do
            local dkey, dkind = decl_cmd_key(cmds[i])
            if dkey ~= nil then
                if not seen[dkey] then
                    if dkind == "sig" then sig_cmds[#sig_cmds + 1] = cmds[i]
                    elseif dkind == "func" then func_cmds[#func_cmds + 1] = cmds[i]
                    else extern_cmds[#extern_cmds + 1] = cmds[i] end
                    seen[dkey] = true
                end
            else
                local key = data_cmd_key(cmds[i])
                if key ~= nil then
                    if not seen[key] then data_cmds[#data_cmds + 1] = cmds[i]; seen[key] = true end
                else
                    other_cmds[#other_cmds + 1] = cmds[i]
                end
            end
        end
        local out = {}
        append_all(out, sig_cmds)
        append_all(out, func_cmds)
        append_all(out, extern_cmds)
        append_all(out, data_cmds)
        append_all(out, other_cmds)
        return out
    end

    lower_item_direct = function(item)
        local cls = pvm.classof(item)
        if cls == Tr.ItemFunc then return Tr.TreeBackItemResult(lower_func_direct(item.func).cmds) end
        if cls == Tr.ItemExtern then return lower_extern_direct(item.func) end
        if cls == Tr.ItemConst then
            local c = item.c
            local name = nil
            if pvm.classof(c) == Tr.ConstItem then name = c.name elseif pvm.classof(c) == Tr.ConstItemOpen then name = c.sym.name end
            if name == nil then return Tr.TreeBackItemResult({}) end
            local cmds = data_init_cmds(lower_context.module_name, name, c.ty, c.value)
            return Tr.TreeBackItemResult(cmds or {})
        end
        if cls == Tr.ItemStatic then
            local s = item.s
            local name = nil
            if pvm.classof(s) == Tr.StaticItem then name = s.name elseif pvm.classof(s) == Tr.StaticItemOpen then name = s.sym.name end
            if name == nil then return Tr.TreeBackItemResult({}) end
            local cmds = data_init_cmds(lower_context.module_name, name, s.ty, s.value)
            return Tr.TreeBackItemResult(cmds or {})
        end
        if cls == Tr.ItemUseModule then
            return with_module_context(item.module, function()
                local cmds = {}
                for i = 1, #item.module.items do append_all(cmds, lower_item_direct(item.module.items[i]).cmds) end
                return Tr.TreeBackItemResult(cmds)
            end)
        end
        return Tr.TreeBackItemResult({})
    end

    local function module_name_of(module)
        return pvm.one(module_type_api.module_name(module.h)) or ""
    end

    local function collect_global_context(module, const_entries, globals, slot_consts, slot_statics, slot_consts_data)
        local mod_name = module_name_of(module)
        for i = 1, #module.items do
            local item = module.items[i]
            local cls = pvm.classof(item)
            if cls == Tr.ItemConst then
                local c = item.c
                local name = nil
                if pvm.classof(c) == Tr.ConstItem then name = c.name elseif pvm.classof(c) == Tr.ConstItemOpen then name = c.sym.name end
                if name ~= nil then
                    const_entries[#const_entries + 1] = Bn.ConstEntry(mod_name, name, c.ty, c.value)
                    local data = data_id_for_global(mod_name, name)
                    globals[global_key(mod_name, name)] = { data = data, ty = c.ty, mutable = false }
                    if pvm.classof(c) == Tr.ConstItemOpen then
                        slot_consts[c.sym.key] = const_eval_api.value(c.value, Bn.ConstEnv(const_entries), const_eval_api.empty_local_env())
                        slot_consts_data[c.sym.key] = data
                    end
                end
            elseif cls == Tr.ItemStatic then
                local s = item.s
                local name = nil
                if pvm.classof(s) == Tr.StaticItem then name = s.name elseif pvm.classof(s) == Tr.StaticItemOpen then name = s.sym.name end
                if name ~= nil then
                    local data = data_id_for_global(mod_name, name)
                    globals[global_key(mod_name, name)] = { data = data, ty = s.ty, mutable = true }
                    if pvm.classof(s) == Tr.StaticItemOpen then slot_statics[s.sym.key] = data end
                end
            elseif cls == Tr.ItemUseModule then
                collect_global_context(item.module, const_entries, globals, slot_consts, slot_statics, slot_consts_data)
            end
        end
    end

    function with_module_context(module, fn, opts)
        opts = opts or {}
        local previous = lower_context
        local const_entries, globals, slot_consts, slot_statics, slot_consts_data = {}, {}, {}, {}, {}
        collect_global_context(module, const_entries, globals, slot_consts, slot_statics, slot_consts_data)
        local layouts = {}
        if opts.layout_env and opts.layout_env.layouts then
            for i = 1, #opts.layout_env.layouts do layouts[#layouts + 1] = opts.layout_env.layouts[i] end
        end
        local module_layouts = module_type_api.env(module).layouts
        for i = 1, #module_layouts do layouts[#layouts + 1] = module_layouts[i] end
        lower_context = {
            module_name = module_name_of(module),
            layout_env = Sem.LayoutEnv(layouts),
            const_env = Bn.ConstEnv(const_entries),
            globals = globals,
            slot_consts = slot_consts,
            slot_statics = slot_statics,
            slot_consts_data = slot_consts_data,
            provenance = BackProvenance.new(),
        }
        local ok, result = pcall(fn)
        lower_context = previous
        if not ok then error(result, 0) end
        return result
    end

    local function item_name(item)
        local cls = pvm.classof(item)
        if cls == Tr.ItemFunc then
            local f = item.func
            local fc = pvm.classof(f)
            if fc == Tr.FuncLocal or fc == Tr.FuncExport
               or fc == Tr.FuncLocalContract or fc == Tr.FuncExportContract then
                return f.name
            elseif fc == Tr.FuncOpen then
                return f.sym and f.sym.name or nil
            end
        elseif cls == Tr.ItemExtern then
            local f = item.func
            local fc = pvm.classof(f)
            if fc == Tr.ExternFunc then
                return f.name or f.symbol
            elseif fc == Tr.ExternFuncOpen then
                return f.sym and f.sym.name or nil
            end
        elseif cls == Tr.ItemConst then
            local c = item.c
            if pvm.classof(c) == Tr.ConstItem then return c.name end
            if pvm.classof(c) == Tr.ConstItemOpen then return c.sym and c.sym.name end
        elseif cls == Tr.ItemStatic then
            local s = item.s
            if pvm.classof(s) == Tr.StaticItem then return s.name end
            if pvm.classof(s) == Tr.StaticItemOpen then return s.sym and s.sym.name end
        elseif cls == Tr.ItemType then
            local t = item.t
            local tc = pvm.classof(t)
            if tc == Tr.TypeDeclStruct or tc == Tr.TypeDeclUnion
               or tc == Tr.TypeDeclEnumSugar or tc == Tr.TypeDeclTaggedUnionSugar then
                return t.name
            elseif tc == Tr.TypeDeclOpenStruct or tc == Tr.TypeDeclOpenUnion then
                return t.sym and t.sym.name end
        elseif cls == Tr.ItemUseModule then
            return item.use_id
        elseif cls == Tr.ItemImport then
            local p = item.imp and item.imp.path
            return p and p.text or nil
        end
        return nil
    end

    lower_module_direct = function(module, opts)
        local provenance  -- captured inside fn, survives pcall
        local prog = with_module_context(module, function()
            local cmds = {}
            for i = 1, #module.items do
                local start_idx = #cmds + 1
                append_all(cmds, lower_item_direct(module.items[i]).cmds)
                local end_idx = #cmds
                if start_idx <= end_idx and lower_context.provenance then
                    local name = item_name(module.items[i])
                    if name then
                        lower_context.provenance:record(start_idx, end_idx, nil, nil, name)
                    end
                end
            end
            cmds = hoist_module_cmds(cmds)
            cmds[#cmds + 1] = Back.CmdFinalizeModule
            provenance = lower_context.provenance
            return Back.BackProgram(cmds)
        end, opts)
        return prog, provenance
    end

    func_to_back = pvm.phase("moonlift_tree_func_to_back", function(self) return lower_func_direct(self) end)
    extern_to_back = pvm.phase("moonlift_tree_extern_to_back", function(self) return lower_extern_direct(self) end)
    item_to_back = pvm.phase("moonlift_tree_item_to_back", function(self) return lower_item_direct(self) end)
    module_to_back = pvm.phase("moonlift_tree_module_to_back", function(module) return lower_module_direct(module) end)

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
