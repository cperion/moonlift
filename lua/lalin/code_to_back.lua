local asdl = require("lalin.asdl")

local function class_name(x)
    return tostring(x):match("Class%((.-)%)") or tostring(x)
end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.code_to_back ~= nil then return T._lalin_api_cache.code_to_back end

    local Core = T.LalinCore
    local Code = T.LalinCode
    local Back = T.LalinBack
    local Lower = T.LalinLower
    local CodeValidate = require("lalin.code_validate")(T)
    local CodeGraph = require("lalin.code_graph")(T)
    local CodeFlowFacts = require("lalin.code_flow_facts")(T)
    local CodeValueFacts = require("lalin.code_value_facts")(T)
    local CodeMemFacts = require("lalin.code_mem_facts")(T)
    local CodeEffectFacts = require("lalin.code_effect_facts")(T)
    local CodeAggregateAbi = require("lalin.code_aggregate_abi")(T)

    local api = {}

    local function unsupported(x)
        error("code_to_back: unsupported " .. class_name(x), 3)
    end

    local function code_back_result(input, state)
        return Code.CodeBackStateResult(state or input.state)
    end

    local function code_back_module_facts_from_lowering(lowering)
        return Code.CodeBackModuleFacts(
            lowering.sigs,
            lowering.sig_abi_by_sig,
            lowering.mem_backend_by_inst,
            lowering.value_int_semantics_by_value,
            lowering.value_float_mode_by_value,
            lowering.effect_by_inst,
            lowering.readonly_inst,
            lowering.layout_env,
            lowering.target
        )
    end

    local function code_back_function_facts_from_lowering(lowering)
        return Code.CodeBackFunctionFacts(
            lowering.current_func_id,
            lowering.current_return_sret,
            lowering.value_types,
            lowering.block_params
        )
    end

    local function code_back_state_from_lowering(lowering)
        return Code.CodeBackFunctionState(
            lowering.cmds,
            lowering.aggregate_local_addr,
            lowering.aggregate_value_addr,
            lowering.aggregate_value_size,
            lowering.closure_value_has_captures,
            lowering.local_stack_slots,
            lowering.tmp_index or 0,
            lowering.next_tmp or 0
        )
    end

    local function copy_list(xs)
        local out = {}
        for i = 1, #(xs or {}) do out[i] = xs[i] end
        return out
    end

    local function copy_map(xs)
        local out = {}
        for k, v in pairs(xs or {}) do out[k] = v end
        return out
    end

    local function code_back_state(cmds, aggregate_local_addr, aggregate_value_addr, aggregate_value_size, closure_value_has_captures, local_stack_slots, tmp_index, next_tmp)
        return Code.CodeBackFunctionState(
            cmds,
            aggregate_local_addr,
            aggregate_value_addr,
            aggregate_value_size,
            closure_value_has_captures,
            local_stack_slots,
            tmp_index or 0,
            next_tmp or 0
        )
    end

    function Code.CodeBackFunctionState:code_back_append_cmd(cmd)
        local cmds = copy_list(self.cmds)
        cmds[#cmds + 1] = cmd
        return code_back_state(cmds, self.aggregate_local_addr, self.aggregate_value_addr, self.aggregate_value_size, self.closure_value_has_captures, self.local_stack_slots, self.tmp_index, self.next_tmp)
    end

    function Code.CodeBackFunctionState:code_back_tmp_value(tag)
        local next_tmp = (self.next_tmp or 0) + 1
        return Code.CodeBackValueResult(
            Back.BackValId((tag or "code_to_back.tmp") .. "." .. tostring(next_tmp)),
            code_back_state(self.cmds, self.aggregate_local_addr, self.aggregate_value_addr, self.aggregate_value_size, self.closure_value_has_captures, self.local_stack_slots, self.tmp_index, next_tmp)
        )
    end

    function Code.CodeBackFunctionState:code_back_note_aggregate_value(id, addr, size)
        local aggregate_value_addr = copy_map(self.aggregate_value_addr)
        local aggregate_value_size = self.aggregate_value_size
        aggregate_value_addr[id.text] = addr
        if size ~= nil then
            aggregate_value_size = copy_map(self.aggregate_value_size)
            aggregate_value_size[id.text] = size
        end
        return code_back_state(self.cmds, self.aggregate_local_addr, aggregate_value_addr, aggregate_value_size, self.closure_value_has_captures, self.local_stack_slots, self.tmp_index, self.next_tmp)
    end

    function Code.CodeBackFunctionState:code_back_note_aggregate_local(id, addr)
        local aggregate_local_addr = copy_map(self.aggregate_local_addr)
        aggregate_local_addr[id.text] = addr
        return code_back_state(self.cmds, aggregate_local_addr, self.aggregate_value_addr, self.aggregate_value_size, self.closure_value_has_captures, self.local_stack_slots, self.tmp_index, self.next_tmp)
    end

    function Code.CodeBackFunctionState:code_back_note_closure_captures(id, has_captures)
        local closure_value_has_captures = copy_map(self.closure_value_has_captures)
        closure_value_has_captures[id.text] = has_captures
        return code_back_state(self.cmds, self.aggregate_local_addr, self.aggregate_value_addr, self.aggregate_value_size, closure_value_has_captures, self.local_stack_slots, self.tmp_index, self.next_tmp)
    end

    function Code.CodeBackFunctionState:code_back_note_local_stack_slot(local_, slot, size, align)
        local local_stack_slots = copy_map(self.local_stack_slots)
        local_stack_slots[local_.id.text] = Code.CodeBackLocalSlot(slot, local_.ty, size, align)
        return code_back_state(self.cmds, self.aggregate_local_addr, self.aggregate_value_addr, self.aggregate_value_size, self.closure_value_has_captures, local_stack_slots, self.tmp_index, self.next_tmp)
    end

    local function code_back_sync_lowering(lowering, state)
        lowering.cmds = state.cmds
        lowering.aggregate_local_addr = state.aggregate_local_addr
        lowering.aggregate_value_addr = state.aggregate_value_addr
        lowering.aggregate_value_size = state.aggregate_value_size
        lowering.closure_value_has_captures = state.closure_value_has_captures
        lowering.local_stack_slots = state.local_stack_slots
        lowering.tmp_index = state.tmp_index
        lowering.next_tmp = state.next_tmp
    end

    local function code_back_inst_input(lowering, inst_id)
        return Code.CodeBackInstInput(
            code_back_module_facts_from_lowering(lowering),
            code_back_function_facts_from_lowering(lowering),
            code_back_state_from_lowering(lowering),
            inst_id
        )
    end

    local function code_back_term_input(lowering, term_id)
        return Code.CodeBackTermInput(
            code_back_module_facts_from_lowering(lowering),
            code_back_function_facts_from_lowering(lowering),
            code_back_state_from_lowering(lowering),
            term_id
        )
    end

    local function bid(id) return Back.BackValId(id.text) end
    local function block_id(id) return Back.BackBlockId(id.text) end
    local function func_id(id)
        local text = tostring(id.text)
        return Back.BackFuncId(text:gsub("^fn:", "", 1))
    end
    local function extern_id(id) return Back.BackExternId(id.text) end
    local function data_id(id) return Back.BackDataId(id.text) end
    local function sig_id(id) return Back.BackSigId(id.text) end
    local function closure_sig_id(id) return Back.BackSigId("closure:" .. id.text) end

    local function scalar(ty)
        if CodeAggregateAbi.is_aggregate(ty) then return Back.BackPtr end
        return CodeAggregateAbi.scalar(ty)
    end

    local function shape(ty)
        local s = scalar(ty)
        if s == nil then unsupported(ty) end
        return Back.BackShapeScalar(s)
    end

    function Core.Literal:lower_core_literal_to_back()
        unsupported(self)
    end
    function Core.LitInt:lower_core_literal_to_back()
        return Back.BackLitInt(self.raw)
    end
    function Core.LitFloat:lower_core_literal_to_back()
        return Back.BackLitFloat(self.raw)
    end
    function Core.LitBool:lower_core_literal_to_back()
        return Back.BackLitBool(self.value)
    end
    function Core.LitNil:lower_core_literal_to_back()
        return Back.BackLitNull
    end

    function Code.CodeConst:lower_code_const_to_back_literal()
        unsupported(self)
    end
    function Code.CodeConstLiteral:lower_code_const_to_back_literal()
        return self.literal:lower_core_literal_to_back()
    end
    function Code.CodeConstNull:lower_code_const_to_back_literal()
        return Back.BackLitNull
    end
    function Code.CodeConstUndef:lower_code_const_to_back_literal()
        return Back.BackLitInt("0")
    end

    function Core.BinaryOp:lower_code_binary_to_back_int_op() return nil end
    function Core.BinAdd:lower_code_binary_to_back_int_op() return Back.BackIntAdd end
    function Core.BinSub:lower_code_binary_to_back_int_op() return Back.BackIntSub end
    function Core.BinMul:lower_code_binary_to_back_int_op() return Back.BackIntMul end
    function Core.BinDiv:lower_code_binary_to_back_int_op() return Back.BackIntSDiv end
    function Core.BinRem:lower_code_binary_to_back_int_op() return Back.BackIntSRem end

    function Core.BinaryOp:lower_code_binary_to_back_bit_op() return nil end
    function Core.BinBitAnd:lower_code_binary_to_back_bit_op() return Back.BackBitAnd end
    function Core.BinBitOr:lower_code_binary_to_back_bit_op() return Back.BackBitOr end
    function Core.BinBitXor:lower_code_binary_to_back_bit_op() return Back.BackBitXor end

    function Core.BinaryOp:lower_code_binary_to_back_shift_op() return nil end
    function Core.BinShl:lower_code_binary_to_back_shift_op() return Back.BackShiftLeft end
    function Core.BinLShr:lower_code_binary_to_back_shift_op() return Back.BackShiftLogicalRight end
    function Core.BinAShr:lower_code_binary_to_back_shift_op() return Back.BackShiftArithmeticRight end

    function Core.AtomicOrdering:lower_code_atomic_ordering_to_back()
        unsupported(self)
    end
    function Core.AtomicSeqCst:lower_code_atomic_ordering_to_back()
        return Back.BackAtomicSeqCst
    end

    function Core.AtomicRmwOp:lower_code_atomic_rmw_op_to_back()
        unsupported(self)
    end
    function Core.AtomicRmwAdd:lower_code_atomic_rmw_op_to_back() return Back.BackAtomicRmwAdd end
    function Core.AtomicRmwSub:lower_code_atomic_rmw_op_to_back() return Back.BackAtomicRmwSub end
    function Core.AtomicRmwAnd:lower_code_atomic_rmw_op_to_back() return Back.BackAtomicRmwAnd end
    function Core.AtomicRmwOr:lower_code_atomic_rmw_op_to_back() return Back.BackAtomicRmwOr end
    function Core.AtomicRmwXor:lower_code_atomic_rmw_op_to_back() return Back.BackAtomicRmwXor end
    function Core.AtomicRmwXchg:lower_code_atomic_rmw_op_to_back() return Back.BackAtomicRmwXchg end

    function Core.BinaryOp:lower_code_binary_to_back_float_op() return nil end
    function Core.BinAdd:lower_code_binary_to_back_float_op() return Back.BackFloatAdd end
    function Core.BinSub:lower_code_binary_to_back_float_op() return Back.BackFloatSub end
    function Core.BinMul:lower_code_binary_to_back_float_op() return Back.BackFloatMul end
    function Core.BinDiv:lower_code_binary_to_back_float_op() return Back.BackFloatDiv end

    function Core.UnaryOp:lower_code_unary_to_back_op() return nil end
    function Core.UnaryNeg:lower_code_unary_to_back_op() return Back.BackUnaryIneg end
    function Core.UnaryBitNot:lower_code_unary_to_back_op() return Back.BackUnaryBnot end
    function Core.UnaryNot:lower_code_unary_to_back_op() return Back.BackUnaryBoolNot end

    function Code.CodeType:lower_code_type_to_back_cmp_op(cmp)
        return cmp:lower_code_compare_to_back_int_op()
    end
    function Code.CodeTyInt:lower_code_type_to_back_cmp_op(cmp)
        return self.signedness == Code.CodeUnsigned and cmp:lower_code_compare_to_back_unsigned_op() or cmp:lower_code_compare_to_back_int_op()
    end
    function Code.CodeTyIndex:lower_code_type_to_back_cmp_op(cmp)
        return cmp:lower_code_compare_to_back_unsigned_op()
    end
    function Code.CodeTyFloat:lower_code_type_to_back_cmp_op(cmp)
        return cmp:lower_code_compare_to_back_float_op()
    end

    function Core.CmpOp:lower_code_compare_to_back_int_op() unsupported(self) end
    function Core.CmpOp:lower_code_compare_to_back_unsigned_op() return self:lower_code_compare_to_back_int_op() end
    function Core.CmpOp:lower_code_compare_to_back_float_op() unsupported(self) end
    function Core.CmpEq:lower_code_compare_to_back_int_op() return Back.BackIcmpEq end
    function Core.CmpNe:lower_code_compare_to_back_int_op() return Back.BackIcmpNe end
    function Core.CmpLt:lower_code_compare_to_back_int_op() return Back.BackSIcmpLt end
    function Core.CmpLe:lower_code_compare_to_back_int_op() return Back.BackSIcmpLe end
    function Core.CmpGt:lower_code_compare_to_back_int_op() return Back.BackSIcmpGt end
    function Core.CmpGe:lower_code_compare_to_back_int_op() return Back.BackSIcmpGe end
    function Core.CmpLt:lower_code_compare_to_back_unsigned_op() return Back.BackUIcmpLt end
    function Core.CmpLe:lower_code_compare_to_back_unsigned_op() return Back.BackUIcmpLe end
    function Core.CmpGt:lower_code_compare_to_back_unsigned_op() return Back.BackUIcmpGt end
    function Core.CmpGe:lower_code_compare_to_back_unsigned_op() return Back.BackUIcmpGe end
    function Core.CmpEq:lower_code_compare_to_back_float_op() return Back.BackFCmpEq end
    function Core.CmpNe:lower_code_compare_to_back_float_op() return Back.BackFCmpNe end
    function Core.CmpLt:lower_code_compare_to_back_float_op() return Back.BackFCmpLt end
    function Core.CmpLe:lower_code_compare_to_back_float_op() return Back.BackFCmpLe end
    function Core.CmpGt:lower_code_compare_to_back_float_op() return Back.BackFCmpGt end
    function Core.CmpGe:lower_code_compare_to_back_float_op() return Back.BackFCmpGe end

    function Core.MachineCastOp:lower_code_cast_to_back_op() unsupported(self) end
    function Core.MachineCastBitcast:lower_code_cast_to_back_op() return Back.BackBitcast end
    function Core.MachineCastIdentity:lower_code_cast_to_back_op() return Back.BackBitcast end
    function Core.MachineCastIreduce:lower_code_cast_to_back_op() return Back.BackIreduce end
    function Core.MachineCastSextend:lower_code_cast_to_back_op() return Back.BackSextend end
    function Core.MachineCastUextend:lower_code_cast_to_back_op() return Back.BackUextend end
    function Core.MachineCastFpromote:lower_code_cast_to_back_op() return Back.BackFpromote end
    function Core.MachineCastFdemote:lower_code_cast_to_back_op() return Back.BackFdemote end
    function Core.MachineCastSToF:lower_code_cast_to_back_op() return Back.BackSToF end
    function Core.MachineCastUToF:lower_code_cast_to_back_op() return Back.BackUToF end
    function Core.MachineCastFToS:lower_code_cast_to_back_op() return Back.BackFToS end
    function Core.MachineCastFToU:lower_code_cast_to_back_op() return Back.BackFToU end

    local zero
    local aggregate_addr_for_value
    local is_byref_aggregate_ty

    function Core.Intrinsic:lower_code_intrinsic_to_back_op() return nil end
    function Core.IntrinsicPopcount:lower_code_intrinsic_to_back_op() return Back.BackIntrinsicPopcount end
    function Core.IntrinsicClz:lower_code_intrinsic_to_back_op() return Back.BackIntrinsicClz end
    function Core.IntrinsicCtz:lower_code_intrinsic_to_back_op() return Back.BackIntrinsicCtz end
    function Core.IntrinsicBswap:lower_code_intrinsic_to_back_op() return Back.BackIntrinsicBswap end
    function Core.IntrinsicSqrt:lower_code_intrinsic_to_back_op() return Back.BackIntrinsicSqrt end
    function Core.IntrinsicAbs:lower_code_intrinsic_to_back_op() return Back.BackIntrinsicAbs end
    function Core.IntrinsicFloor:lower_code_intrinsic_to_back_op() return Back.BackIntrinsicFloor end
    function Core.IntrinsicCeil:lower_code_intrinsic_to_back_op() return Back.BackIntrinsicCeil end
    function Core.IntrinsicTruncFloat:lower_code_intrinsic_to_back_op() return Back.BackIntrinsicTruncFloat end
    function Core.IntrinsicRound:lower_code_intrinsic_to_back_op() return Back.BackIntrinsicRound end

    function Core.Intrinsic:lower_code_intrinsic_to_back_rotate_op() return nil end
    function Core.IntrinsicRotl:lower_code_intrinsic_to_back_rotate_op() return Back.BackRotateLeft end
    function Core.IntrinsicRotr:lower_code_intrinsic_to_back_rotate_op() return Back.BackRotateRight end

    function Code.CodeIntOverflow:lower_code_int_overflow_to_back()
        return Back.BackIntWrap
    end
    function Code.CodeIntAssumeNoOverflow:lower_code_int_overflow_to_back()
        return Back.BackIntNoWrap(self.reason)
    end
    function Code.CodeIntTrapOnOverflow:lower_code_int_overflow_to_back()
        return Back.BackIntNoWrap("trap-on-overflow Code semantics")
    end

    function Code.CodeFloatMode:lower_code_float_mode_to_back()
        return Back.BackFloatStrict
    end
    function Code.CodeFloatStrict:lower_code_float_mode_to_back()
        return Back.BackFloatStrict
    end
    function Code.CodeFloatReassoc:lower_code_float_mode_to_back()
        return Back.BackFloatReassoc(self.reason)
    end
    function Code.CodeFloatFastMath:lower_code_float_mode_to_back()
        return Back.BackFloatFastMath(self.reason)
    end

    function T.LalinMem.MemAlignment:lower_code_mem_alignment_to_back()
        return Back.BackAlignUnknown
    end
    function T.LalinMem.MemAlignUnknown:lower_code_mem_alignment_to_back()
        return Back.BackAlignUnknown
    end
    function T.LalinMem.MemAlignKnown:lower_code_mem_alignment_to_back()
        return Back.BackAlignKnown(self.bytes)
    end
    function T.LalinMem.MemAlignAtLeast:lower_code_mem_alignment_to_back()
        return Back.BackAlignAtLeast(self.bytes)
    end
    function T.LalinMem.MemAlignAssumed:lower_code_mem_alignment_to_back()
        return Back.BackAlignAssumed(self.bytes, "MemBackendAccessInfo assumption")
    end

    function T.LalinMem.MemTrap:lower_code_mem_trap_to_back()
        return Back.BackMayTrap
    end
    function T.LalinMem.MemMayTrap:lower_code_mem_trap_to_back()
        return Back.BackMayTrap
    end
    function T.LalinMem.MemNonTrapping:lower_code_mem_trap_to_back()
        return Back.BackNonTrapping(self.reason)
    end
    function T.LalinMem.MemCheckedTrap:lower_code_mem_trap_to_back()
        return Back.BackChecked(self.reason)
    end

    function T.LalinMem.MemBounds:lower_code_mem_bounds_to_back()
        return Back.BackPtrInBounds("MemBackendAccessInfo bounds")
    end
    function T.LalinMem.MemBoundsUnknown:lower_code_mem_bounds_to_back()
        return Back.BackPtrBoundsUnknown
    end

    function T.LalinMem.MemObjectEffectFact:code_back_readonly_object()
        return nil
    end
    function T.LalinMem.MemObjectReadonly:code_back_readonly_object()
        return self.object
    end

    function T.LalinEffect.OpEffect:code_back_allows_call()
        return true
    end
    function T.LalinEffect.EffectUnknown:code_back_allows_call()
        return true
    end

    function Code.CodeType:code_back_index_cast_op()
        return nil
    end
    function Code.CodeTyIndex:code_back_index_cast_op()
        return false
    end
    function Code.CodeTyInt:code_back_index_cast_op()
        if self.bits < 64 then return self.signedness == Code.CodeSigned and Back.BackSextend or Back.BackUextend end
        return nil
    end
    function Code.CodeTyBool8:code_back_index_cast_op()
        return Back.BackUextend
    end

    function Code.CodeType:code_back_lease_base()
        return self
    end
    function Code.CodeTyLease:code_back_lease_base()
        return self.base
    end
    function Code.CodeType:code_back_optional_lease_base()
        return self
    end
    function Code.CodeType:code_back_view_elem()
        return nil
    end
    function Code.CodeTyView:code_back_view_elem()
        return self.elem
    end
    function Code.CodeType:code_back_slice_elem()
        return nil
    end
    function Code.CodeTySlice:code_back_slice_elem()
        return self.elem
    end
    function Code.CodeType:code_back_view_data_ty()
        return Code.CodeTyDataPtr(nil)
    end
    function Code.CodeTyView:code_back_view_data_ty()
        return Code.CodeTyDataPtr(self.elem)
    end
    function Code.CodeType:code_back_slice_data_ty()
        return Code.CodeTyDataPtr(nil)
    end
    function Code.CodeTySlice:code_back_slice_data_ty()
        return Code.CodeTyDataPtr(self.elem)
    end
    function Code.CodeType:code_back_is_local_byref_aggregate()
        return false
    end
    function Code.CodeTyNamed:code_back_is_local_byref_aggregate()
        return true
    end
    function Code.CodeTyArray:code_back_is_local_byref_aggregate()
        return true
    end
    function Code.CodeTyClosure:code_back_is_local_byref_aggregate()
        return true
    end
    function Code.CodeType:code_back_is_closure()
        return false
    end
    function Code.CodeTyClosure:code_back_is_closure()
        return true
    end
    function Code.CodeType:code_back_array_elem()
        return nil
    end
    function Code.CodeTyArray:code_back_array_elem()
        return self.elem
    end

    function Code.CodePlace:code_back_store_aggregate_local(state, value, access)
        return nil
    end
    function Code.CodePlaceLocal:code_back_store_aggregate_local(state, value, access)
        if is_byref_aggregate_ty(access.ty) then
            return state:code_back_note_aggregate_local(self.local_id, aggregate_addr_for_value(state, value, access.ty) or bid(value))
        end
        return nil
    end

    function T.LalinSem.FieldRef:code_back_field_offset()
        unsupported(self)
    end
    function T.LalinSem.FieldByOffset:code_back_field_offset()
        return self.offset or 0
    end

    function Back.BackAddressBase:code_back_materialize_addr_base(state, tag)
        return Code.CodeBackValueResult(nil, state)
    end
    function Back.BackAddrValue:code_back_materialize_addr_base(state, tag)
        return Code.CodeBackValueResult(self.value, state)
    end
    function Back.BackAddrStack:code_back_materialize_addr_base(state, tag)
        local tmp = state:code_back_tmp_value((tag or "code_to_back.stack_base") .. ".base")
        state = tmp.state:code_back_append_cmd(Back.CmdStackAddr(tmp.value, self.slot))
        return Code.CodeBackValueResult(tmp.value, state)
    end
    function Back.BackAddrData:code_back_materialize_addr_base(state, tag)
        local tmp = state:code_back_tmp_value((tag or "code_to_back.data_base") .. ".base")
        state = tmp.state:code_back_append_cmd(Back.CmdDataAddr(tmp.value, self.data))
        return Code.CodeBackValueResult(tmp.value, state)
    end

    function Back.BackAddress:code_back_with_const_offset(state, offset)
        local base = self.base
        local materialized = base:code_back_materialize_addr_base(state, "code_to_back.addr_base")
        state = materialized.state
        if materialized.value ~= nil then base = Back.BackAddrValue(materialized.value) end
        if offset == 0 then return Code.CodeBackAddressResult(Back.BackAddress(base, self.byte_offset, self.provenance, self.formation_bounds), state) end
        local tmp = state:code_back_tmp_value("code_to_back.view_addr." .. tostring(offset))
        state = tmp.state:code_back_append_cmd(Back.CmdPtrOffset(tmp.value, base, self.byte_offset, 1, offset, self.provenance, self.formation_bounds))
        local z = zero(state)
        return Code.CodeBackAddressResult(Back.BackAddress(Back.BackAddrValue(tmp.value), z.value, self.provenance, self.formation_bounds), z.state)
    end

    function Back.BackAddress:code_back_to_ptr_value(state, tag)
        local materialized = self.base:code_back_materialize_addr_base(state, tag)
        state = materialized.state
        local base = materialized.value ~= nil and Back.BackAddrValue(materialized.value) or self.base
        local tmp = state:code_back_tmp_value(tag or "code_to_back.addr_value")
        state = tmp.state:code_back_append_cmd(Back.CmdPtrOffset(tmp.value, base, self.byte_offset, 1, 0, self.provenance, self.formation_bounds))
        return Code.CodeBackValueResult(tmp.value, state)
    end

    function Back.BackAddress:code_back_stack_base_slot()
        return self.base:code_back_stack_base_slot(self.byte_offset)
    end
    function Back.BackAddressBase:code_back_stack_base_slot(byte_offset)
        return nil
    end
    function Back.BackAddrStack:code_back_stack_base_slot(byte_offset)
        return self.slot
    end

    local function int_semantics(module_facts, k)
        local fact = module_facts.value_int_semantics_by_value and module_facts.value_int_semantics_by_value[k.dst.text]
        local sem = fact or k.semantics
        local overflow = Back.BackIntWrap
        if sem ~= nil then
            overflow = sem.overflow:lower_code_int_overflow_to_back()
        end
        return Back.BackIntSemantics(overflow, Back.BackIntMayLose)
    end

    local function float_semantics(module_facts, k)
        local mode = (module_facts.value_float_mode_by_value and module_facts.value_float_mode_by_value[k.dst.text]) or k.mode
        return mode ~= nil and mode:lower_code_float_mode_to_back() or Back.BackFloatStrict
    end

    zero = function(state)
        local tmp = state:code_back_tmp_value("code_to_back.zero")
        return Code.CodeBackValueResult(tmp.value, tmp.state:code_back_append_cmd(Back.CmdConst(tmp.value, Back.BackIndex, Back.BackLitInt("0"))))
    end

    local function lowering_note_value(state, id, ty)
        if id ~= nil and ty ~= nil then state.value_types[id.text] = ty end
    end

    local function index_value(state, func_facts, id)
        local ty = func_facts.value_types[id.text]
        local op = ty and ty:code_back_index_cast_op() or nil
        if op == false then return Code.CodeBackValueResult(bid(id), state) end
        if op ~= nil then
            local tmp = state:code_back_tmp_value("code_to_back.index")
            state = tmp.state
            local v = tmp.value
            state = state:code_back_append_cmd(Back.CmdCast(v, op, Back.BackIndex, bid(id)))
            return Code.CodeBackValueResult(v, state)
        end
        return Code.CodeBackValueResult(bid(id), state)
    end

    local function value_as(state, func_facts, id, ty)
        if ty == Code.CodeTyIndex then return index_value(state, func_facts, id) end
        return Code.CodeBackValueResult(bid(id), state)
    end

    local function access_mode(mode, readonly)
        if readonly and mode == Code.CodeMemoryRead then return Back.BackAccessReadonly end
        if mode == Code.CodeMemoryWrite then return Back.BackAccessWrite end
        if mode == Code.CodeMemoryReadWrite then return Back.BackAccessReadWrite end
        return Back.BackAccessRead
    end

    local function back_alignment(alignment)
        return alignment ~= nil and alignment:lower_code_mem_alignment_to_back() or Back.BackAlignUnknown
    end

    local function back_trap(trap)
        return trap ~= nil and trap:lower_code_mem_trap_to_back() or Back.BackMayTrap
    end

    local function memory_info(module_facts, access, inst_id)
        local info = module_facts.mem_backend_by_inst and module_facts.mem_backend_by_inst[inst_id.text] or nil
        if info == nil then error("code_to_back: missing MemBackendAccessInfo for Code inst " .. inst_id.text, 3) end
        local deref = info.deref_bytes and Back.BackDerefBytes(info.deref_bytes, "MemBackendAccessInfo") or Back.BackDerefUnknown
        local motion = info.movable and Back.BackCanMove("MemBackendAccessInfo movable") or Back.BackMayNotMove
        local readonly = module_facts.readonly_inst and module_facts.readonly_inst[inst_id.text]
        return Back.BackMemoryInfo(Back.BackAccessId(info.access.text), back_alignment(info.alignment), deref, back_trap(info.trap), motion, access_mode(access.mode, readonly))
    end

    local function component_memory_info(module_facts, access, inst_id, field)
        local info = module_facts.mem_backend_by_inst and module_facts.mem_backend_by_inst[inst_id.text] or nil
        if info == nil then error("code_to_back: missing MemBackendAccessInfo for Code inst " .. inst_id.text, 3) end
        local motion = info.movable and Back.BackCanMove("MemBackendAccessInfo movable view component") or Back.BackMayNotMove
        local readonly = module_facts.readonly_inst and module_facts.readonly_inst[inst_id.text]
        return Back.BackMemoryInfo(Back.BackAccessId(info.access.text .. ":" .. field), back_alignment(info.alignment), Back.BackDerefBytes(8, "view descriptor component"), back_trap(info.trap), motion, access_mode(access.mode, readonly))
    end

    local function const_index(state, raw)
        local tmp = state:code_back_tmp_value("code_to_back.const_index")
        return Code.CodeBackValueResult(tmp.value, tmp.state:code_back_append_cmd(Back.CmdConst(tmp.value, Back.BackIndex, Back.BackLitInt(tostring(raw)))))
    end

    local function null_ptr(state, tag)
        local tmp = state:code_back_tmp_value(tag or "code_to_back.null")
        return Code.CodeBackValueResult(tmp.value, tmp.state:code_back_append_cmd(Back.CmdConst(tmp.value, Back.BackPtr, Back.BackLitNull)))
    end

    local function address_at_const_offset(state, addr, offset)
        return addr:code_back_with_const_offset(state, offset)
    end

    local function address_to_ptr_value(state, addr, tag)
        return addr:code_back_to_ptr_value(state, tag)
    end

    local function back_bounds(info)
        return info ~= nil and info.bounds:lower_code_mem_bounds_to_back() or Back.BackPtrBoundsUnknown
    end

    function Code.CodePlace:lower_code_place_to_back_addr(input)
        unsupported(self)
    end
    function Code.CodePlaceDeref:lower_code_place_to_back_addr(input)
        local state = input.state
        local z = zero(state); state = z.state
        return Code.CodeBackPlaceResult(Back.BackAddress(Back.BackAddrValue(bid(self.addr)), z.value, Back.BackProvUnknown, back_bounds(input.access)), state)
    end
    function Code.CodePlaceGlobal:lower_code_place_to_back_addr(input)
        local state = input.state
        local z = zero(state); state = z.state
        return Code.CodeBackPlaceResult(Back.BackAddress(Back.BackAddrData(data_id(self.global)), z.value, Back.BackProvData(data_id(self.global)), Back.BackPtrInBounds("global")), state)
    end
    function Code.CodePlaceData:lower_code_place_to_back_addr(input)
        local state = input.state
        local z = zero(state); state = z.state
        return Code.CodeBackPlaceResult(Back.BackAddress(Back.BackAddrData(data_id(self.data)), z.value, Back.BackProvData(data_id(self.data)), Back.BackPtrInBounds("data")), state)
    end
    function Code.CodePlaceLocal:lower_code_place_to_back_addr(input)
        local state = input.state
        if CodeAggregateAbi.is_view(self.ty) or CodeAggregateAbi.is_slice(self.ty) or CodeAggregateAbi.is_byte_span(self.ty) then
            local stack = state.local_stack_slots and state.local_stack_slots[self.local_id.text]
            if stack == nil then error("code_to_back: descriptor local has no materialized storage " .. self.local_id.text, 3) end
            local z = zero(state); state = z.state
            return Code.CodeBackPlaceResult(Back.BackAddress(Back.BackAddrStack(stack.slot), z.value, Back.BackProvStack(stack.slot), back_bounds(input.access)), state)
        end
        if self.ty:code_back_is_local_byref_aggregate() then
            local addr = state.aggregate_local_addr and state.aggregate_local_addr[self.local_id.text]
            if addr == nil then error("code_to_back: aggregate local has no materialized address " .. self.local_id.text, 3) end
            local z = zero(state); state = z.state
            return Code.CodeBackPlaceResult(Back.BackAddress(Back.BackAddrValue(addr), z.value, Back.BackProvUnknown, back_bounds(input.access)), state)
        end
        local stack = state.local_stack_slots and state.local_stack_slots[self.local_id.text]
        if stack ~= nil then
            local z = zero(state); state = z.state
            return Code.CodeBackPlaceResult(Back.BackAddress(Back.BackAddrStack(stack.slot), z.value, Back.BackProvStack(stack.slot), back_bounds(input.access)), state)
        end
        unsupported(self)
    end
    function Code.CodePlaceField:lower_code_place_to_back_addr(input)
        local state = input.state
        local base_result = self.base:lower_code_place_to_back_addr(input)
        state = base_result.state
        local base = base_result.address
        local ptr_result = state:code_back_tmp_value("code_to_back.field." .. tostring(self.offset or 0))
        state = ptr_result.state
        local ptr = ptr_result.value
        local bounds = back_bounds(input.access)
        local idx0 = const_index(state, 0); state = idx0.state
        state = state:code_back_append_cmd(Back.CmdPtrOffset(ptr, base.base, idx0.value, 1, self.offset or 0, Back.BackProvDerived("field"), bounds))
        local z = zero(state); state = z.state
        return Code.CodeBackPlaceResult(Back.BackAddress(Back.BackAddrValue(ptr), z.value, Back.BackProvDerived("field"), bounds), state)
    end
    function Code.CodePlaceIndex:lower_code_place_to_back_addr(input)
        local state = input.state
        local base_result = self.base:lower_code_place_to_back_addr(input)
        state = base_result.state
        local base = base_result.address
        local ptr = Back.BackValId("code_to_back.addr." .. self.index.text)
        local index = index_value(state, input.func, self.index); state = index.state
        local bounds = back_bounds(input.access)
        state = state:code_back_append_cmd(Back.CmdPtrOffset(ptr, base.base, index.value, self.elem_size, 0, Back.BackProvDerived("index"), bounds))
        local z = zero(state); state = z.state
        return Code.CodeBackPlaceResult(Back.BackAddress(Back.BackAddrValue(ptr), z.value, Back.BackProvDerived("index"), bounds), state)
    end

    function Code.CodePlace:lower_code_place_addr_of_to_back(input, dst)
        local state = input.state
        local result = self:lower_code_place_to_back_addr(input)
        state = result.state
        local ptr = address_to_ptr_value(state, result.address, "code_to_back.addr_of"); state = ptr.state
        state = state:code_back_append_cmd(Back.CmdAlias(bid(dst), ptr.value))
        return Code.CodeBackStateResult(state)
    end
    function Code.CodePlaceGlobal:lower_code_place_addr_of_to_back(input, dst)
        local state = input.state
        state = state:code_back_append_cmd(Back.CmdDataAddr(bid(dst), data_id(self.global)))
        return Code.CodeBackStateResult(state)
    end
    function Code.CodePlaceData:lower_code_place_addr_of_to_back(input, dst)
        local state = input.state
        state = state:code_back_append_cmd(Back.CmdDataAddr(bid(dst), data_id(self.data)))
        return Code.CodeBackStateResult(state)
    end
    function Code.CodePlaceLocal:lower_code_place_addr_of_to_back(input, dst)
        local state = input.state
        local result = self:lower_code_place_to_back_addr(input)
        state = result.state
        local addr = result.address
        local stack_offset = addr:code_back_stack_base_slot()
        if stack_offset ~= nil then
            state = state:code_back_append_cmd(Back.CmdStackAddr(bid(dst), stack_offset))
        else
            local ptr = address_to_ptr_value(state, addr, "code_to_back.addr_of"); state = ptr.state
            state = state:code_back_append_cmd(Back.CmdAlias(bid(dst), ptr.value))
        end
        return Code.CodeBackStateResult(state)
    end

    local function code_back_place_input(input)
        return Code.CodeBackPlaceInput(input.module, input.func, input.state, input.inst, input.module.mem_backend_by_inst[input.inst.text])
    end

    local function addr_from_place(input, place)
        return place:lower_code_place_to_back_addr(code_back_place_input(input))
    end

    function Code.CodeDataInit:lower_code_data_init_to_back(state, data)
        unsupported(self)
    end
    function Code.CodeDataZero:lower_code_data_init_to_back(state, data)
        state = state:code_back_append_cmd(Back.CmdDataInitZero(data, self.offset, self.size))
    end
    function Code.CodeDataScalar:lower_code_data_init_to_back(state, data)
        local s = scalar(self.ty); if s == nil then unsupported(self.ty) end
        state = state:code_back_append_cmd(Back.CmdDataInit(data, self.offset, s, self.literal:lower_core_literal_to_back()))
    end
    function Code.CodeDataBytes:lower_code_data_init_to_back(state, data)
        for i = 1, #self.bytes do
            state = state:code_back_append_cmd(Back.CmdDataInit(data, self.offset + i - 1, Back.BackU8, Back.BackLitInt(tostring(self.bytes:byte(i)))))
        end
    end

    local function data_init(state, init, data)
        return init:lower_code_data_init_to_back(state, data)
    end

    function Code.CodeInstKind:lower_code_inst_dst_type(func_facts, module_facts)
        return nil, nil
    end
    function Code.CodeInstConst:lower_code_inst_dst_type(func_facts, module_facts) return self.dst, self.const.ty end
    function Code.CodeInstAlias:lower_code_inst_dst_type(func_facts, module_facts) return self.dst, self.ty end
    function Code.CodeInstUnary:lower_code_inst_dst_type(func_facts, module_facts) return self.dst, self.ty end
    function Code.CodeInstBinary:lower_code_inst_dst_type(func_facts, module_facts) return self.dst, self.ty end
    function Code.CodeInstFloatBinary:lower_code_inst_dst_type(func_facts, module_facts) return self.dst, self.ty end
    function Code.CodeInstCompare:lower_code_inst_dst_type(func_facts, module_facts) return self.dst, Code.CodeTyBool8 end
    function Code.CodeInstCast:lower_code_inst_dst_type(func_facts, module_facts) return self.dst, self.to end
    function Code.CodeInstIntrinsic:lower_code_inst_dst_type(func_facts, module_facts) return self.dst, self.ty end
    function Code.CodeInstSelect:lower_code_inst_dst_type(func_facts, module_facts) return self.dst, self.ty end
    function Code.CodeInstAddrOf:lower_code_inst_dst_type(func_facts, module_facts) return self.dst, self.ptr_ty end
    function Code.CodeInstGlobalRef:lower_code_inst_dst_type(func_facts, module_facts) return self.dst, self.ptr_ty end
    function Code.CodeInstPtrOffset:lower_code_inst_dst_type(func_facts, module_facts) return self.dst, self.ptr_ty end
    function Code.CodeInstLoad:lower_code_inst_dst_type(func_facts, module_facts) return self.dst, self.access.ty end
    function Code.CodeInstAtomicLoad:lower_code_inst_dst_type(func_facts, module_facts) return self.dst, self.access.ty end
    function Code.CodeInstAtomicRmw:lower_code_inst_dst_type(func_facts, module_facts) return self.dst, self.access.ty end
    function Code.CodeInstAtomicCas:lower_code_inst_dst_type(func_facts, module_facts) return self.dst, self.access.ty end
    function Code.CodeInstAggregate:lower_code_inst_dst_type(func_facts, module_facts) return self.dst, self.ty end
    function Code.CodeInstArray:lower_code_inst_dst_type(func_facts, module_facts) return self.dst, self.ty end
    function Code.CodeInstClosure:lower_code_inst_dst_type(func_facts, module_facts) return self.dst, self.ty end
    function Code.CodeInstVariantCtor:lower_code_inst_dst_type(func_facts, module_facts) return self.dst, self.ty end
    function Code.CodeInstVariantTag:lower_code_inst_dst_type(func_facts, module_facts) return self.dst, self.tag_ty end
    function Code.CodeInstVariantPayload:lower_code_inst_dst_type(func_facts, module_facts) return self.dst, self.variant.payload_ty end
    function Code.CodeInstViewMake:lower_code_inst_dst_type(func_facts, module_facts) return self.dst, Code.CodeTyView(self.elem_ty) end
    function Code.CodeInstViewData:lower_code_inst_dst_type(func_facts, module_facts)
        local vty = func_facts.value_types and func_facts.value_types[self.view.text] or nil
        return self.dst, vty ~= nil and vty:code_back_lease_base():code_back_view_data_ty() or Code.CodeTyDataPtr(nil)
    end
    function Code.CodeInstViewLen:lower_code_inst_dst_type(func_facts, module_facts) return self.dst, Code.CodeTyIndex end
    function Code.CodeInstViewStride:lower_code_inst_dst_type(func_facts, module_facts) return self.dst, Code.CodeTyIndex end
    function Code.CodeInstSliceMake:lower_code_inst_dst_type(func_facts, module_facts) return self.dst, Code.CodeTySlice(self.elem_ty) end
    function Code.CodeInstSliceData:lower_code_inst_dst_type(func_facts, module_facts)
        local sty = func_facts.value_types and func_facts.value_types[self.slice.text] or nil
        return self.dst, sty ~= nil and sty:code_back_lease_base():code_back_slice_data_ty() or Code.CodeTyDataPtr(nil)
    end
    function Code.CodeInstSliceLen:lower_code_inst_dst_type(func_facts, module_facts) return self.dst, Code.CodeTyIndex end
    function Code.CodeInstByteSpanMake:lower_code_inst_dst_type(func_facts, module_facts) return self.dst, Code.CodeTyByteSpan end
    function Code.CodeInstByteSpanData:lower_code_inst_dst_type(func_facts, module_facts) return self.dst, Code.CodeTyDataPtr(Code.CodeTyInt(8, Code.CodeUnsigned)) end
    function Code.CodeInstByteSpanLen:lower_code_inst_dst_type(func_facts, module_facts) return self.dst, Code.CodeTyIndex end
    function Code.CodeInstCall:lower_code_inst_dst_type(func_facts, module_facts)
        local sig = self.sig and module_facts.sigs[self.sig.text] or nil
        if sig and sig.results[1] then return self.dst, sig.results[1] end
        return nil, nil
    end

    local function inst_dst_type(func_facts, module_facts, k)
        return k:lower_code_inst_dst_type(func_facts, module_facts)
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

    local function is_view_ty(ty) return CodeAggregateAbi.is_view(ty) end

    local function view_elem(ty) return CodeAggregateAbi.view_elem(ty) end

    local function is_slice_ty(ty) return CodeAggregateAbi.is_slice(ty) end

    local function slice_elem(ty) return CodeAggregateAbi.slice_elem(ty) end

    is_byref_aggregate_ty = function(ty) return CodeAggregateAbi.is_aggregate(ty) end

    local function component_scalars(ty) return CodeAggregateAbi.component_scalars(ty) end

    local function sig_abi(state, sig) return CodeAggregateAbi.lowered_sig(sig) end

    local function closure_abi(state, sig)
        local abi = sig_abi(state, sig)
        local params = {}
        if abi.sret then params[#params + 1] = Back.BackPtr end
        params[#params + 1] = Back.BackPtr
        local start = abi.sret and 2 or 1
        for i = start, #abi.params do params[#params + 1] = abi.params[i] end
        return { sret = abi.sret, result_ty = abi.result_ty, params = params, results = abi.results }
    end

    local function component_shapes(ty)
        local scalars = component_scalars(ty)
        local out = {}
        for i = 1, #scalars do out[i] = Back.BackShapeScalar(scalars[i]) end
        return out
    end

    local function component_values(id, ty)
        if is_view_ty(ty) then return { view_component_id(id, "data"), view_component_id(id, "len"), view_component_id(id, "stride") } end
        if is_slice_ty(ty) then return { slice_component_id(id, "data"), slice_component_id(id, "len") } end
        if CodeAggregateAbi.is_byte_span(ty) then return { bytespan_component_id(id, "data"), bytespan_component_id(id, "len") } end
        return { bid(id) }
    end

    local function append_components(out, id, ty)
        local vals = component_values(id, ty)
        for i = 1, #vals do out[#out + 1] = vals[i] end
    end

    local function scalar_size_align(s)
        if s == Back.BackI8 or s == Back.BackU8 or s == Back.BackBool then return 1, 1 end
        if s == Back.BackI16 or s == Back.BackU16 then return 2, 2 end
        if s == Back.BackI32 or s == Back.BackU32 or s == Back.BackF32 then return 4, 4 end
        if s == Back.BackI64 or s == Back.BackU64 or s == Back.BackF64 or s == Back.BackPtr or s == Back.BackIndex then return 8, 8 end
        return 0, 1
    end

    local function aggregate_layout(state, ty) return CodeAggregateAbi.layout(state, ty) end

    local function aggregate_size_align(state, ty) return CodeAggregateAbi.size_align(state, ty) end

    local function code_size_align(state, ty)
        if is_view_ty(ty) then return aggregate_size_align(state, ty) end
        if is_slice_ty(ty) then return aggregate_size_align(state, ty) end
        if CodeAggregateAbi.is_byte_span(ty) then return aggregate_size_align(state, ty) end
        if CodeAggregateAbi.is_aggregate(ty) then return aggregate_size_align(state, ty) end
        local s = scalar(ty); if s == nil then unsupported(ty) end
        return scalar_size_align(s)
    end

    local function layout_field_offset(state, ty, name) return CodeAggregateAbi.field_offset(state, ty, name) end

    local function synthetic_memory(state, tag, bytes, mode)
        local tmp = state:code_back_tmp_value("code_to_back." .. tag)
        local memory = Back.BackMemoryInfo(Back.BackAccessId(tmp.value.text), Back.BackAlignUnknown, Back.BackDerefBytes(bytes or 1, "Code aggregate ABI"), Back.BackNonTrapping("Code aggregate ABI stack/local access"), Back.BackCanMove("Code aggregate ABI local access"), mode)
        return Code.CodeBackMemoryInfoResult(memory, tmp.state)
    end

    aggregate_addr_for_value = function(state, id, ty)
        local mapped = state.aggregate_value_addr and state.aggregate_value_addr[id.text]
        if mapped ~= nil then return mapped end
        if is_byref_aggregate_ty(ty) then return bid(id) end
        return nil
    end

    local function create_aggregate_storage(state, id, ty, prefix, size_override, align_override)
        local size, align = aggregate_size_align(state, ty)
        size = size_override or size
        align = align_override or align
        local slot = Back.BackStackSlotId((prefix or "code_to_back.aggregate") .. ":" .. id.text)
        local addr = Back.BackValId(id.text .. ":addr")
        state = state:code_back_append_cmd(Back.CmdCreateStackSlot(slot, size, align))
        state = state:code_back_append_cmd(Back.CmdStackAddr(addr, slot))
        state = state:code_back_append_cmd(Back.CmdAlias(bid(id), addr))
        state = state:code_back_note_aggregate_value(id, addr, size)
        return state, addr, size, align
    end

    local function create_local_stack_slot(state, local_, prefix, emit)
        local size, align = code_size_align(state, local_.ty)
        local slot = Back.BackStackSlotId((prefix or "code_to_back.local") .. ":" .. local_.id.text)
        if emit ~= false then state = state:code_back_append_cmd(Back.CmdCreateStackSlot(slot, size, align)) end
        state = state:code_back_note_local_stack_slot(local_, slot, size, align)
        return state, slot
    end

    local function materialize_addressed_locals(state, locals, emit)
        for _, local_ in ipairs(locals or {}) do
            if is_view_ty(local_.ty) or is_slice_ty(local_.ty) or CodeAggregateAbi.is_byte_span(local_.ty) then
                state = create_local_stack_slot(state, local_, nil, emit)
            elseif local_.residence == Code.CodeResidenceAddressed and not CodeAggregateAbi.is_aggregate(local_.ty) then
                state = create_local_stack_slot(state, local_, nil, emit)
            end
        end
        return state
    end

    local function closure_descriptor_size(func_facts, fields)
        local size, align = 16, 8
        for _, field in ipairs(fields or {}) do
            local name = field.field and field.field.field_name
            if name ~= "__lalin_fn" then
                local fty = func_facts.value_types[field.value.text]
                if fty == nil then error("code_to_back: closure capture value has unknown type " .. field.value.text, 3) end
                local s = scalar(fty); if s == nil then unsupported(fty) end
                local sz, a = scalar_size_align(s)
                local end_offset = 16 + (field.field.offset or 0) + sz
                if end_offset > size then size = end_offset end
                if a > align then align = a end
            end
        end
        local rem = size % align
        if rem ~= 0 then size = size + (align - rem) end
        return size, align
    end

    local function store_scalar_at_offset(state, base_addr, offset, value, ty, tag)
        local s = scalar(ty); if s == nil then unsupported(ty) end
        local sz = scalar_size_align(s)
        local ptr_result = state:code_back_tmp_value((tag or "code_to_back.store_field") .. ".ptr." .. tostring(offset or 0))
        state = ptr_result.state
        local ptr = ptr_result.value
        local idx0 = const_index(state, 0); state = idx0.state
        state = state:code_back_append_cmd(Back.CmdPtrOffset(ptr, Back.BackAddrValue(base_addr), idx0.value, 1, offset or 0, Back.BackProvDerived(tag or "aggregate field"), Back.BackPtrInBounds("aggregate field")))
        local z = zero(state); state = z.state
        local memory = synthetic_memory(state, tag or "aggregate_store", sz, Back.BackAccessWrite); state = memory.state
        state = state:code_back_append_cmd(Back.CmdStoreInfo(Back.BackShapeScalar(s), Back.BackAddress(Back.BackAddrValue(ptr), z.value, Back.BackProvDerived(tag or "aggregate field"), Back.BackPtrInBounds("aggregate field")), value, memory.memory))
        return state
    end

    local function load_scalar_at_offset(state, dst, base_addr, offset, ty, tag)
        local s = scalar(ty); if s == nil then unsupported(ty) end
        local sz = scalar_size_align(s)
        local ptr_result = state:code_back_tmp_value((tag or "code_to_back.load_field") .. ".ptr." .. tostring(offset or 0))
        state = ptr_result.state
        local ptr = ptr_result.value
        local idx0 = const_index(state, 0); state = idx0.state
        state = state:code_back_append_cmd(Back.CmdPtrOffset(ptr, Back.BackAddrValue(base_addr), idx0.value, 1, offset or 0, Back.BackProvDerived(tag or "aggregate field"), Back.BackPtrInBounds("aggregate field")))
        local z = zero(state); state = z.state
        local memory = synthetic_memory(state, tag or "aggregate_load", sz, Back.BackAccessRead); state = memory.state
        state = state:code_back_append_cmd(Back.CmdLoadInfo(dst, Back.BackShapeScalar(s), Back.BackAddress(Back.BackAddrValue(ptr), z.value, Back.BackProvDerived(tag or "aggregate field"), Back.BackPtrInBounds("aggregate field")), memory.memory))
        return state
    end

    local function source_aggregate_ptr(state, value)
        return state.aggregate_value_addr[value.text] or bid(value)
    end

    local function ptr_at_offset(state, base_addr, offset, tag)
        local ptr_result = state:code_back_tmp_value((tag or "code_to_back.aggregate_ptr") .. "." .. tostring(offset or 0))
        state = ptr_result.state
        local idx0 = const_index(state, 0); state = idx0.state
        state = state:code_back_append_cmd(Back.CmdPtrOffset(ptr_result.value, Back.BackAddrValue(base_addr), idx0.value, 1, offset or 0, Back.BackProvDerived(tag or "aggregate copy"), Back.BackPtrInBounds("aggregate copy")))
        return Code.CodeBackValueResult(ptr_result.value, state)
    end

    local function copy_aggregate_from_ptr(state, dst_base, dst_offset, src_base, ty, tag, src_offset)
        local size = aggregate_size_align(state, ty)
        local dst_ptr = ptr_at_offset(state, dst_base, dst_offset or 0, (tag or "aggregate_copy") .. ".dst"); state = dst_ptr.state
        local src_ptr = ptr_at_offset(state, src_base, src_offset or 0, (tag or "aggregate_copy") .. ".src"); state = src_ptr.state
        local len = const_index(state, size); state = len.state
        state = state:code_back_append_cmd(Back.CmdMemcpy(dst_ptr.value, src_ptr.value, len.value))
        return state
    end

    local function copy_value_to_offset(state, dst_base, dst_offset, value, ty, tag, src_base, src_offset, tmp)
        if is_view_ty(ty) then
            local vals
            if value ~= nil then
                vals = component_values(value, ty)
            else
                local data = tmp and Code.CodeBackValueResult(tmp, state) or state:code_back_tmp_value((tag or "view_copy") .. ".data")
                state = data.state
                local len = state:code_back_tmp_value((tag or "view_copy") .. ".len"); state = len.state
                local stride = state:code_back_tmp_value((tag or "view_copy") .. ".stride"); state = stride.state
                vals = { data.value, len.value, stride.value }
                state = load_scalar_at_offset(state, vals[1], src_base, (src_offset or 0), Code.CodeTyDataPtr(view_elem(ty)), tag or "view_copy_data")
                state = load_scalar_at_offset(state, vals[2], src_base, (src_offset or 0) + 8, Code.CodeTyIndex, tag or "view_copy_len")
                state = load_scalar_at_offset(state, vals[3], src_base, (src_offset or 0) + 16, Code.CodeTyIndex, tag or "view_copy_stride")
            end
            state = store_scalar_at_offset(state, dst_base, (dst_offset or 0), vals[1], Code.CodeTyDataPtr(view_elem(ty)), tag or "view_store_data")
            state = store_scalar_at_offset(state, dst_base, (dst_offset or 0) + 8, vals[2], Code.CodeTyIndex, tag or "view_store_len")
            state = store_scalar_at_offset(state, dst_base, (dst_offset or 0) + 16, vals[3], Code.CodeTyIndex, tag or "view_store_stride")
        elseif is_slice_ty(ty) then
            local vals
            if value ~= nil then
                vals = component_values(value, ty)
            else
                local data = tmp and Code.CodeBackValueResult(tmp, state) or state:code_back_tmp_value((tag or "slice_copy") .. ".data")
                state = data.state
                local len = state:code_back_tmp_value((tag or "slice_copy") .. ".len"); state = len.state
                vals = { data.value, len.value }
                state = load_scalar_at_offset(state, vals[1], src_base, src_offset or 0, Code.CodeTyDataPtr(slice_elem(ty)), tag or "slice_copy_data")
                state = load_scalar_at_offset(state, vals[2], src_base, (src_offset or 0) + 8, Code.CodeTyIndex, tag or "slice_copy_len")
            end
            state = store_scalar_at_offset(state, dst_base, dst_offset or 0, vals[1], Code.CodeTyDataPtr(slice_elem(ty)), tag or "slice_store_data")
            state = store_scalar_at_offset(state, dst_base, (dst_offset or 0) + 8, vals[2], Code.CodeTyIndex, tag or "slice_store_len")
        elseif CodeAggregateAbi.is_byte_span(ty) then
            local vals
            if value ~= nil then
                vals = component_values(value, ty)
            else
                local data = tmp and Code.CodeBackValueResult(tmp, state) or state:code_back_tmp_value((tag or "bytespan_copy") .. ".data")
                state = data.state
                local len = state:code_back_tmp_value((tag or "bytespan_copy") .. ".len"); state = len.state
                vals = { data.value, len.value }
                state = load_scalar_at_offset(state, vals[1], src_base, src_offset or 0, Code.CodeTyDataPtr(Code.CodeTyInt(8, Code.CodeUnsigned)), tag or "bytespan_copy_data")
                state = load_scalar_at_offset(state, vals[2], src_base, (src_offset or 0) + 8, Code.CodeTyIndex, tag or "bytespan_copy_len")
            end
            state = store_scalar_at_offset(state, dst_base, dst_offset or 0, vals[1], Code.CodeTyDataPtr(Code.CodeTyInt(8, Code.CodeUnsigned)), tag or "bytespan_store_data")
            state = store_scalar_at_offset(state, dst_base, (dst_offset or 0) + 8, vals[2], Code.CodeTyIndex, tag or "bytespan_store_len")
        elseif is_byref_aggregate_ty(ty) then
            local source = src_base
            if source == nil then
                if value == nil then error("code_to_back: aggregate copy has no source", 3) end
                source = source_aggregate_ptr(state, value)
            end
            state = copy_aggregate_from_ptr(state, dst_base, dst_offset or 0, source, ty, tag, src_offset or 0)
        else
            local v = value and Code.CodeBackValueResult(bid(value), state) or (tmp and Code.CodeBackValueResult(tmp, state) or state:code_back_tmp_value((tag or "scalar_copy") .. ".tmp"))
            state = v.state
            if value == nil then state = load_scalar_at_offset(state, v.value, src_base, src_offset or 0, ty, tag or "scalar_copy") end
            state = store_scalar_at_offset(state, dst_base, dst_offset or 0, v.value, ty, tag)
        end
        return state
    end

    local function store_closure_descriptor(state, dst, ty, fn, ctx_ptr)
        local addr
        state, addr = create_aggregate_storage(state, dst, ty, "code_to_back.closure")
        local fn_ty = Code.CodeTyCodePtr(ty.sig)
        state = store_scalar_at_offset(state, addr, 0, fn, fn_ty, "closure_fn")
        state = store_scalar_at_offset(state, addr, 8, ctx_ptr, Code.CodeTyDataPtr(nil), "closure_ctx")
        return Code.CodeBackValueResult(addr, state)
    end

    local function closure_env_ptr(state, base_addr, has_captures)
        if not has_captures then return null_ptr(state, "code_to_back.closure_ctx_null") end
        local ptr = state:code_back_tmp_value("code_to_back.closure_ctx"); state = ptr.state
        local idx0 = const_index(state, 0); state = idx0.state
        state = state:code_back_append_cmd(Back.CmdPtrOffset(ptr.value, Back.BackAddrValue(base_addr), idx0.value, 1, 16, Back.BackProvDerived("closure env"), Back.BackPtrInBounds("closure env")))
        return Code.CodeBackValueResult(ptr.value, state)
    end

    local function store_view_components_to_addr(state, base_addr, view, ty, tag)
        local elem = view_elem(ty)
        local data_ty = Code.CodeTyDataPtr(elem)
        local vals = component_values(view, ty)
        state = store_scalar_at_offset(state, base_addr, 0, vals[1], data_ty, (tag or "view") .. ":data")
        state = store_scalar_at_offset(state, base_addr, 8, vals[2], Code.CodeTyIndex, (tag or "view") .. ":len")
        state = store_scalar_at_offset(state, base_addr, 16, vals[3], Code.CodeTyIndex, (tag or "view") .. ":stride")
        return state
    end

    local function load_view_components_from_addr(state, view, base_addr, ty, tag)
        local elem = view_elem(ty)
        local data_ty = Code.CodeTyDataPtr(elem)
        local vals = component_values(view, ty)
        state = load_scalar_at_offset(state, vals[1], base_addr, 0, data_ty, (tag or "view") .. ":data")
        state = load_scalar_at_offset(state, vals[2], base_addr, 8, Code.CodeTyIndex, (tag or "view") .. ":len")
        state = load_scalar_at_offset(state, vals[3], base_addr, 16, Code.CodeTyIndex, (tag or "view") .. ":stride")
        return state
    end

    local function check_call_effects(module_facts, inst_id)
        local effects = module_facts.effect_by_inst and module_facts.effect_by_inst[inst_id.text] or nil
        if effects == nil then return end
        for _, effect in ipairs(effects.effects or {}) do
            if effect:code_back_allows_call() then
                -- Ordinary Code fallback may still emit conservative calls; the
                -- fact is consulted here so optimized fragment emitters can
                -- reject motion/vectorization before reaching Back.
                return
            end
        end
    end

    function Code.CodeGlobalRef:lower_code_global_ref_to_back_addr(state, dst)
        unsupported(self)
    end
    function Code.CodeGlobalRefFunc:lower_code_global_ref_to_back_addr(state, dst)
        state = state:code_back_append_cmd(Back.CmdFuncAddr(bid(dst), func_id(self.func)))
        return Code.CodeBackStateResult(state)
    end
    function Code.CodeGlobalRefExtern:lower_code_global_ref_to_back_addr(state, dst)
        state = state:code_back_append_cmd(Back.CmdExternAddr(bid(dst), extern_id(self["extern"])))
        return Code.CodeBackStateResult(state)
    end
    function Code.CodeGlobalRefData:lower_code_global_ref_to_back_addr(state, dst)
        state = state:code_back_append_cmd(Back.CmdDataAddr(bid(dst), data_id(self.data)))
        return Code.CodeBackStateResult(state)
    end
    function Code.CodeGlobalRefGlobal:lower_code_global_ref_to_back_addr(state, dst)
        state = state:code_back_append_cmd(Back.CmdDataAddr(bid(dst), data_id(self.global)))
        return Code.CodeBackStateResult(state)
    end

    function Code.CodeCallTarget:lower_code_call_target_to_back(input, call)
        unsupported(self)
    end
    function Code.CodeCallDirect:lower_code_call_target_to_back(input, call)
        return Back.BackCallDirect(func_id(self.func)), sig_id(call.sig), nil
    end
    function Code.CodeCallExtern:lower_code_call_target_to_back(input, call)
        return Back.BackCallExtern(extern_id(self["extern"])), sig_id(call.sig), nil
    end
    function Code.CodeCallIndirect:lower_code_call_target_to_back(input, call)
        return Back.BackCallIndirect(bid(self.callee)), sig_id(call.sig), nil
    end
    function Code.CodeCallClosure:lower_code_call_target_to_back(input, call)
        local state = input.state
        local closure_ty = input.func.value_types[self.closure.text]
        local closure_addr = aggregate_addr_for_value(state, self.closure, closure_ty)
        if closure_addr == nil then error("code_to_back: closure call has no descriptor address " .. self.closure.text, 3) end
        local fn = Back.BackValId(self.closure.text .. ":closure_call_fn")
        local closure_ctx = Back.BackValId(self.closure.text .. ":closure_call_ctx")
        state = load_scalar_at_offset(state, fn, closure_addr, 0, Code.CodeTyCodePtr(self.sig), "closure_call_fn")
        state = load_scalar_at_offset(state, closure_ctx, closure_addr, 8, Code.CodeTyDataPtr(nil), "closure_call_ctx")
        return Back.BackCallIndirect(fn), closure_sig_id(call.sig), closure_ctx, state
    end

    function Code.CodeInst:lower_code_inst_to_back(input)
        return self.kind:lower_code_inst_to_back(Code.CodeBackInstInput(input.module, input.func, input.state, self.id))
    end

    function Code.CodeInstKind:lower_code_inst_to_back(input)
        unsupported(self)
    end

    function Code.CodeInstConst:lower_code_inst_to_back(input)
        local state = input.state
            local s = scalar(self.const.ty); if s == nil then unsupported(self.const.ty) end
            state = state:code_back_append_cmd(Back.CmdConst(bid(self.dst), s, self.const:lower_code_const_to_back_literal()))
        return code_back_result(input, state)
    end

    function Code.CodeInstAlias:lower_code_inst_to_back(input)
        local state = input.state
            if is_view_ty(self.ty) then
                local dsts, srcs = component_values(self.dst, self.ty), component_values(self.src, self.ty)
                for n = 1, #dsts do state = state:code_back_append_cmd(Back.CmdAlias(dsts[n], srcs[n])) end
            elseif is_byref_aggregate_ty(self.ty) then
                state = state:code_back_note_aggregate_value(self.dst, aggregate_addr_for_value(state, self.src, self.ty) or bid(self.src))
            else
                state = state:code_back_append_cmd(Back.CmdAlias(bid(self.dst), bid(self.src)))
            end
        return code_back_result(input, state)
    end

    function Code.CodeInstUnary:lower_code_inst_to_back(input)
        local state = input.state
            local op = self.op:lower_code_unary_to_back_op(); if op == nil then unsupported(self.op) end
            state = state:code_back_append_cmd(Back.CmdUnary(bid(self.dst), op, shape(self.ty), bid(self.value)))
        return code_back_result(input, state)
    end

    function Code.CodeInstBinary:lower_code_inst_to_back(input)
        local state = input.state
            local s = scalar(self.ty); if s == nil then unsupported(self.ty) end
            local iop, bop, sop = self.op:lower_code_binary_to_back_int_op(), self.op:lower_code_binary_to_back_bit_op(), self.op:lower_code_binary_to_back_shift_op()
            local lhs = value_as(state, input.func, self.lhs, self.ty); state = lhs.state
            local rhs = value_as(state, input.func, self.rhs, self.ty); state = rhs.state
            if iop then state = state:code_back_append_cmd(Back.CmdIntBinary(bid(self.dst), iop, s, int_semantics(input.module, self), lhs.value, rhs.value))
            elseif bop then state = state:code_back_append_cmd(Back.CmdBitBinary(bid(self.dst), bop, s, lhs.value, rhs.value))
            elseif sop then state = state:code_back_append_cmd(Back.CmdShift(bid(self.dst), sop, s, lhs.value, rhs.value))
            else unsupported(self.op) end
        return code_back_result(input, state)
    end

    function Code.CodeInstFloatBinary:lower_code_inst_to_back(input)
        local state = input.state
            local s = scalar(self.ty); local op = self.op:lower_code_binary_to_back_float_op(); if not s or not op then unsupported(self) end
            state = state:code_back_append_cmd(Back.CmdFloatBinary(bid(self.dst), op, s, float_semantics(input.module, self), bid(self.lhs), bid(self.rhs)))
        return code_back_result(input, state)
    end

    function Code.CodeInstCompare:lower_code_inst_to_back(input)
        local state = input.state
            local lhs = value_as(state, input.func, self.lhs, self.operand_ty); state = lhs.state
            local rhs = value_as(state, input.func, self.rhs, self.operand_ty); state = rhs.state
            state = state:code_back_append_cmd(Back.CmdCompare(bid(self.dst), self.operand_ty:lower_code_type_to_back_cmp_op(self.op), shape(self.operand_ty), lhs.value, rhs.value))
        return code_back_result(input, state)
    end

    function Code.CodeInstCast:lower_code_inst_to_back(input)
        local state = input.state
            local s = scalar(self.to); if s == nil then unsupported(self.to) end
            state = state:code_back_append_cmd(Back.CmdCast(bid(self.dst), self.op:lower_code_cast_to_back_op(), s, bid(self.value)))
        return code_back_result(input, state)
    end

    function Code.CodeInstIntrinsic:lower_code_inst_to_back(input)
        local state = input.state
            if self.op == Core.IntrinsicTrap then
                state = state:code_back_append_cmd(Back.CmdTrap)
            elseif self.op == Core.IntrinsicFma then
                local s = scalar(self.ty); if s == nil then unsupported(self.ty) end
                if self.dst == nil or #self.args ~= 3 then unsupported(self) end
                state = state:code_back_append_cmd(Back.CmdFma(bid(self.dst), s, Back.BackFloatStrict, bid(self.args[1]), bid(self.args[2]), bid(self.args[3])))
            elseif self.op:lower_code_intrinsic_to_back_rotate_op() ~= nil then
                local s = scalar(self.ty); if s == nil then unsupported(self.ty) end
                if self.dst == nil or #self.args ~= 2 then unsupported(self) end
                state = state:code_back_append_cmd(Back.CmdRotate(bid(self.dst), self.op:lower_code_intrinsic_to_back_rotate_op(), s, bid(self.args[1]), bid(self.args[2])))
            else
                local op = self.op:lower_code_intrinsic_to_back_op(); if op == nil then unsupported(self.op) end
                local s = scalar(self.ty); if s == nil then unsupported(self.ty) end
                if self.dst == nil or #self.args < 1 then unsupported(self) end
                state = state:code_back_append_cmd(Back.CmdIntrinsic(bid(self.dst), op, Back.BackShapeScalar(s), { bid(self.args[1]) }))
            end
        return code_back_result(input, state)
    end

    function Code.CodeInstSelect:lower_code_inst_to_back(input)
        local state = input.state
            state = state:code_back_append_cmd(Back.CmdSelect(bid(self.dst), shape(self.ty), bid(self.cond), bid(self.then_value), bid(self.else_value)))
        return code_back_result(input, state)
    end

    function Code.CodeInstAddrOf:lower_code_inst_to_back(input)
        local state = input.state
            self.place:lower_code_place_addr_of_to_back(code_back_place_input(input), self.dst)
        return code_back_result(input, state)
    end

    function Code.CodeInstGlobalRef:lower_code_inst_to_back(input)
        local state = input.state
            local result = self.ref:lower_code_global_ref_to_back_addr(state, self.dst)
            state = result.state
        return code_back_result(input, state)
    end

    function Code.CodeInstPtrOffset:lower_code_inst_to_back(input)
        local state = input.state
            local index = index_value(state, input.func, self.index); state = index.state
            state = state:code_back_append_cmd(Back.CmdPtrOffset(bid(self.dst), Back.BackAddrValue(bid(self.base)), index.value, self.elem_size, self.const_offset, Back.BackProvDerived("CodePtrOffset"), Back.BackPtrBoundsUnknown))
        return code_back_result(input, state)
    end

    function Code.CodeInstViewMake:lower_code_inst_to_back(input)
        local state = input.state
            -- Materialize executable descriptor components as deterministic SSA aliases.
            -- Projections alias from these component ids; if a view was not made in Code,
            -- Back validation fails loudly on the missing deterministic source value.
            state = state:code_back_append_cmd(Back.CmdAlias(view_component_id(self.dst, "data"), bid(self.data)))
            state = state:code_back_append_cmd(Back.CmdAlias(view_component_id(self.dst, "len"), bid(self.len)))
            state = state:code_back_append_cmd(Back.CmdAlias(view_component_id(self.dst, "stride"), bid(self.stride)))
        return code_back_result(input, state)
    end

    function Code.CodeInstViewData:lower_code_inst_to_back(input)
        local state = input.state
            state = state:code_back_append_cmd(Back.CmdAlias(bid(self.dst), view_component_id(self.view, "data")))
        return code_back_result(input, state)
    end

    function Code.CodeInstViewLen:lower_code_inst_to_back(input)
        local state = input.state
            state = state:code_back_append_cmd(Back.CmdAlias(bid(self.dst), view_component_id(self.view, "len")))
        return code_back_result(input, state)
    end

    function Code.CodeInstViewStride:lower_code_inst_to_back(input)
        local state = input.state
            state = state:code_back_append_cmd(Back.CmdAlias(bid(self.dst), view_component_id(self.view, "stride")))
        return code_back_result(input, state)
    end

    function Code.CodeInstSliceMake:lower_code_inst_to_back(input)
        local state = input.state
            state = state:code_back_append_cmd(Back.CmdAlias(slice_component_id(self.dst, "data"), bid(self.data)))
            state = state:code_back_append_cmd(Back.CmdAlias(slice_component_id(self.dst, "len"), bid(self.len)))
        return code_back_result(input, state)
    end

    function Code.CodeInstSliceData:lower_code_inst_to_back(input)
        local state = input.state
            state = state:code_back_append_cmd(Back.CmdAlias(bid(self.dst), slice_component_id(self.slice, "data")))
        return code_back_result(input, state)
    end

    function Code.CodeInstSliceLen:lower_code_inst_to_back(input)
        local state = input.state
            state = state:code_back_append_cmd(Back.CmdAlias(bid(self.dst), slice_component_id(self.slice, "len")))
        return code_back_result(input, state)
    end

    function Code.CodeInstByteSpanMake:lower_code_inst_to_back(input)
        local state = input.state
            state = state:code_back_append_cmd(Back.CmdAlias(Back.BackValId(self.dst.text .. ":bytespan_data"), bid(self.data)))
            state = state:code_back_append_cmd(Back.CmdAlias(Back.BackValId(self.dst.text .. ":bytespan_len"), bid(self.len)))
        return code_back_result(input, state)
    end

    function Code.CodeInstByteSpanData:lower_code_inst_to_back(input)
        local state = input.state
            state = state:code_back_append_cmd(Back.CmdAlias(bid(self.dst), Back.BackValId(self.span.text .. ":bytespan_data")))
        return code_back_result(input, state)
    end

    function Code.CodeInstByteSpanLen:lower_code_inst_to_back(input)
        local state = input.state
            state = state:code_back_append_cmd(Back.CmdAlias(bid(self.dst), Back.BackValId(self.span.text .. ":bytespan_len")))
        return code_back_result(input, state)
    end

    function Code.CodeInstLoad:lower_code_inst_to_back(input)
        local state = input.state
            local place_result = addr_from_place(input, self.place)
            local addr = place_result.address
            state = place_result.state
            if is_byref_aggregate_ty(self.access.ty) then
                local p = address_to_ptr_value(state, addr, "code_to_back.aggregate_load_addr"); state = p.state
                state = state:code_back_append_cmd(Back.CmdAlias(bid(self.dst), p.value))
                state = state:code_back_note_aggregate_value(self.dst, p.value)
            elseif is_view_ty(self.access.ty) then
                local elem = view_elem(self.access.ty)
                local data_ty = Code.CodeTyDataPtr(elem)
                local vals = component_values(self.dst, self.access.ty)
                local data_addr = address_at_const_offset(state, addr, 0); state = data_addr.state
                local len_addr = address_at_const_offset(state, addr, 8); state = len_addr.state
                local stride_addr = address_at_const_offset(state, addr, 16); state = stride_addr.state
                local data_mem = component_memory_info(input.module, self.access, input.inst, "view_data")
                local len_mem = component_memory_info(input.module, self.access, input.inst, "view_len")
                local stride_mem = component_memory_info(input.module, self.access, input.inst, "view_stride")
                state = state:code_back_append_cmd(Back.CmdLoadInfo(vals[1], shape(data_ty), data_addr.address, data_mem))
                state = state:code_back_append_cmd(Back.CmdLoadInfo(vals[2], shape(Code.CodeTyIndex), len_addr.address, len_mem))
                state = state:code_back_append_cmd(Back.CmdLoadInfo(vals[3], shape(Code.CodeTyIndex), stride_addr.address, stride_mem))
            elseif is_slice_ty(self.access.ty) then
                local elem = slice_elem(self.access.ty)
                local data_ty = Code.CodeTyDataPtr(elem)
                local vals = component_values(self.dst, self.access.ty)
                local data_addr = address_at_const_offset(state, addr, 0); state = data_addr.state
                local len_addr = address_at_const_offset(state, addr, 8); state = len_addr.state
                local data_mem = component_memory_info(input.module, self.access, input.inst, "slice_data")
                local len_mem = component_memory_info(input.module, self.access, input.inst, "slice_len")
                state = state:code_back_append_cmd(Back.CmdLoadInfo(vals[1], shape(data_ty), data_addr.address, data_mem))
                state = state:code_back_append_cmd(Back.CmdLoadInfo(vals[2], shape(Code.CodeTyIndex), len_addr.address, len_mem))
            elseif CodeAggregateAbi.is_byte_span(self.access.ty) then
                local data_ty = Code.CodeTyDataPtr(Code.CodeTyInt(8, Code.CodeUnsigned))
                local vals = component_values(self.dst, self.access.ty)
                local data_addr = address_at_const_offset(state, addr, 0); state = data_addr.state
                local len_addr = address_at_const_offset(state, addr, 8); state = len_addr.state
                local data_mem = component_memory_info(input.module, self.access, input.inst, "bytespan_data")
                local len_mem = component_memory_info(input.module, self.access, input.inst, "bytespan_len")
                state = state:code_back_append_cmd(Back.CmdLoadInfo(vals[1], shape(data_ty), data_addr.address, data_mem))
                state = state:code_back_append_cmd(Back.CmdLoadInfo(vals[2], shape(Code.CodeTyIndex), len_addr.address, len_mem))
            else
                state = state:code_back_append_cmd(Back.CmdLoadInfo(bid(self.dst), shape(self.access.ty), addr, memory_info(input.module, self.access, input.inst)))
            end
        return code_back_result(input, state)
    end

    function Code.CodeInstAggregate:lower_code_inst_to_back(input)
        local state = input.state
            if self.ty:code_back_is_closure() then
                local size, align = closure_descriptor_size(input.func, self.fields)
                local addr
                state, addr = create_aggregate_storage(state, self.dst, self.ty, "code_to_back.closure", size, align)
                local fn = nil
                local captures = {}
                for _, field in ipairs(self.fields or {}) do
                    if field.field.field_name == "__lalin_fn" then
                        fn = field.value
                    else
                        captures[#captures + 1] = field
                    end
                end
                state = state:code_back_note_closure_captures(self.dst, #captures > 0)
                if fn == nil then error("code_to_back: closure aggregate missing __lalin_fn", 3) end
                state = store_scalar_at_offset(state, addr, 0, bid(fn), Code.CodeTyCodePtr(self.ty.sig), "closure_fn")
                local closure_ctx = closure_env_ptr(state, addr, #captures > 0); state = closure_ctx.state
                state = store_scalar_at_offset(state, addr, 8, closure_ctx.value, Code.CodeTyDataPtr(nil), "closure_ctx")
                for _, field in ipairs(captures) do
                    local fty = input.func.value_types[field.value.text]
                    if fty == nil then error("code_to_back: closure capture value has unknown type " .. field.value.text, 3) end
                    state = copy_value_to_offset(state, addr, 16 + field.field:code_back_field_offset(), field.value, fty, "closure_capture")
                end
            else
                local addr
                state, addr = create_aggregate_storage(state, self.dst, self.ty, "code_to_back.aggregate")
                for _, field in ipairs(self.fields or {}) do
                    local fty = input.func.value_types[field.value.text]
                    if fty == nil then error("code_to_back: aggregate field value has unknown type " .. field.value.text, 3) end
                    state = copy_value_to_offset(state, addr, field.field:code_back_field_offset(), field.value, fty, "aggregate_field")
                end
            end
        return code_back_result(input, state)
    end

    function Code.CodeInstClosure:lower_code_inst_to_back(input)
        local state = input.state
            local descriptor = store_closure_descriptor(state, self.dst, self.ty, bid(self.fn), bid(self.state))
            state = descriptor.state
        return code_back_result(input, state)
    end

    function Code.CodeInstArray:lower_code_inst_to_back(input)
        local state = input.state
            local addr
            state, addr = create_aggregate_storage(state, self.dst, self.ty, "code_to_back.array")
            local elem_ty = self.ty:code_back_array_elem()
            if elem_ty == nil then unsupported(self.ty) end
            local elem_s = scalar(elem_ty)
            local elem_size
            if elem_s ~= nil then
                elem_size = scalar_size_align(elem_s)
            else
                elem_size = aggregate_size_align(state, elem_ty)
            end
            for _, elem in ipairs(self.elems or {}) do
                local ety = input.func.value_types[elem.value.text] or elem_ty
                state = copy_value_to_offset(state, addr, (elem.index or 0) * elem_size, elem.value, ety, "array_elem")
            end
        return code_back_result(input, state)
    end

    function Code.CodeInstVariantCtor:lower_code_inst_to_back(input)
        local state = input.state
            local addr
            state, addr = create_aggregate_storage(state, self.dst, self.ty, "code_to_back.variant")
            local tag_ty = Code.CodeTyInt(32, Code.CodeUnsigned)
            local tag_val = Back.BackValId(self.dst.text .. ":tag")
            state = state:code_back_append_cmd(Back.CmdConst(tag_val, Back.BackU32, Back.BackLitInt(tostring(self.variant.tag_value))))
            state = store_scalar_at_offset(state, addr, 0, tag_val, tag_ty, "variant_tag")
            if self.payload ~= nil and self.variant.payload_ty ~= nil then
                local off = layout_field_offset(state, self.ty, "__payload") or 4
                local pty = input.func.value_types[self.payload.text] or self.variant.payload_ty
                state = store_scalar_at_offset(state, addr, off, bid(self.payload), pty, "variant_payload")
            end
        return code_back_result(input, state)
    end

    function Code.CodeInstVariantTag:lower_code_inst_to_back(input)
        local state = input.state
            local addr = aggregate_addr_for_value(state, self.value, input.func.value_types[self.value.text])
            if addr == nil then error("code_to_back: variant tag source has no aggregate address " .. self.value.text, 3) end
            state = load_scalar_at_offset(state, self.dst and bid(self.dst) or Back.BackValId(self.value.text .. ":tag"), addr, 0, self.tag_ty, "variant_tag")
        return code_back_result(input, state)
    end

    function Code.CodeInstVariantPayload:lower_code_inst_to_back(input)
        local state = input.state
            local owner_ty = input.func.value_types[self.value.text]
            local addr = aggregate_addr_for_value(state, self.value, owner_ty)
            if addr == nil then error("code_to_back: variant payload source has no aggregate address " .. self.value.text, 3) end
            local off = layout_field_offset(state, owner_ty, "__payload") or 4
            local pty = self.variant.payload_ty
            if pty == nil then error("code_to_back: variant payload has no payload type", 3) end
            state = load_scalar_at_offset(state, bid(self.dst), addr, off, pty, "variant_payload")
        return code_back_result(input, state)
    end

    function Code.CodeInstStore:lower_code_inst_to_back(input)
        local state = input.state
            local aggregate_local_state = self.place:code_back_store_aggregate_local(state, self.value, self.access)
            if aggregate_local_state ~= nil then
                state = aggregate_local_state
                return Code.CodeBackStateResult(state)
            end
            local place_result = addr_from_place(input, self.place)
            local addr = place_result.address
            state = place_result.state
            if is_view_ty(self.access.ty) then
                local elem = view_elem(self.access.ty)
                local data_ty = Code.CodeTyDataPtr(elem)
                local vals = component_values(self.value, self.access.ty)
                local data_addr = address_at_const_offset(state, addr, 0); state = data_addr.state
                local len_addr = address_at_const_offset(state, addr, 8); state = len_addr.state
                local stride_addr = address_at_const_offset(state, addr, 16); state = stride_addr.state
                local data_mem = component_memory_info(input.module, self.access, input.inst, "view_data")
                local len_mem = component_memory_info(input.module, self.access, input.inst, "view_len")
                local stride_mem = component_memory_info(input.module, self.access, input.inst, "view_stride")
                state = state:code_back_append_cmd(Back.CmdStoreInfo(shape(data_ty), data_addr.address, vals[1], data_mem))
                state = state:code_back_append_cmd(Back.CmdStoreInfo(shape(Code.CodeTyIndex), len_addr.address, vals[2], len_mem))
                state = state:code_back_append_cmd(Back.CmdStoreInfo(shape(Code.CodeTyIndex), stride_addr.address, vals[3], stride_mem))
            elseif is_slice_ty(self.access.ty) then
                local elem = slice_elem(self.access.ty)
                local data_ty = Code.CodeTyDataPtr(elem)
                local vals = component_values(self.value, self.access.ty)
                local data_addr = address_at_const_offset(state, addr, 0); state = data_addr.state
                local len_addr = address_at_const_offset(state, addr, 8); state = len_addr.state
                local data_mem = component_memory_info(input.module, self.access, input.inst, "slice_data")
                local len_mem = component_memory_info(input.module, self.access, input.inst, "slice_len")
                state = state:code_back_append_cmd(Back.CmdStoreInfo(shape(data_ty), data_addr.address, vals[1], data_mem))
                state = state:code_back_append_cmd(Back.CmdStoreInfo(shape(Code.CodeTyIndex), len_addr.address, vals[2], len_mem))
            elseif CodeAggregateAbi.is_byte_span(self.access.ty) then
                local data_ty = Code.CodeTyDataPtr(Code.CodeTyInt(8, Code.CodeUnsigned))
                local vals = component_values(self.value, self.access.ty)
                local data_addr = address_at_const_offset(state, addr, 0); state = data_addr.state
                local len_addr = address_at_const_offset(state, addr, 8); state = len_addr.state
                local data_mem = component_memory_info(input.module, self.access, input.inst, "bytespan_data")
                local len_mem = component_memory_info(input.module, self.access, input.inst, "bytespan_len")
                state = state:code_back_append_cmd(Back.CmdStoreInfo(shape(data_ty), data_addr.address, vals[1], data_mem))
                state = state:code_back_append_cmd(Back.CmdStoreInfo(shape(Code.CodeTyIndex), len_addr.address, vals[2], len_mem))
            else
                state = state:code_back_append_cmd(Back.CmdStoreInfo(shape(self.access.ty), addr, bid(self.value), memory_info(input.module, self.access, input.inst)))
            end
        return code_back_result(input, state)
    end

    function Code.CodeInstAtomicLoad:lower_code_inst_to_back(input)
        local state = input.state
            local s = scalar(self.access.ty); if s == nil then unsupported(self.access.ty) end
            local place_result = addr_from_place(input, self.place)
            local addr = place_result.address
            state = place_result.state
            state = state:code_back_append_cmd(Back.CmdAtomicLoad(bid(self.dst), s, addr, memory_info(input.module, self.access, input.inst), self.ordering:lower_code_atomic_ordering_to_back()))
        return code_back_result(input, state)
    end

    function Code.CodeInstAtomicStore:lower_code_inst_to_back(input)
        local state = input.state
            local s = scalar(self.access.ty); if s == nil then unsupported(self.access.ty) end
            local place_result = addr_from_place(input, self.place)
            local addr = place_result.address
            state = place_result.state
            state = state:code_back_append_cmd(Back.CmdAtomicStore(s, addr, bid(self.value), memory_info(input.module, self.access, input.inst), self.ordering:lower_code_atomic_ordering_to_back()))
        return code_back_result(input, state)
    end

    function Code.CodeInstAtomicRmw:lower_code_inst_to_back(input)
        local state = input.state
            local s = scalar(self.access.ty); if s == nil then unsupported(self.access.ty) end
            local place_result = addr_from_place(input, self.place)
            local addr = place_result.address
            state = place_result.state
            state = state:code_back_append_cmd(Back.CmdAtomicRmw(bid(self.dst), self.op:lower_code_atomic_rmw_op_to_back(), s, addr, bid(self.value), memory_info(input.module, self.access, input.inst), self.ordering:lower_code_atomic_ordering_to_back()))
        return code_back_result(input, state)
    end

    function Code.CodeInstAtomicCas:lower_code_inst_to_back(input)
        local state = input.state
            local s = scalar(self.access.ty); if s == nil then unsupported(self.access.ty) end
            local place_result = addr_from_place(input, self.place)
            local addr = place_result.address
            state = place_result.state
            state = state:code_back_append_cmd(Back.CmdAtomicCas(bid(self.dst), s, addr, bid(self.expected), bid(self.replacement), memory_info(input.module, self.access, input.inst), self.ordering:lower_code_atomic_ordering_to_back()))
        return code_back_result(input, state)
    end

    function Code.CodeInstAtomicFence:lower_code_inst_to_back(input)
        local state = input.state
            state = state:code_back_append_cmd(Back.CmdAtomicFence(self.ordering:lower_code_atomic_ordering_to_back()))
        return code_back_result(input, state)
    end

    function Code.CodeInstCall:lower_code_inst_to_back(input)
        local state = input.state
            check_call_effects(input.module, input.inst)
            local target, call_sig, closure_ctx, target_state = self.target:lower_code_call_target_to_back(input, self)
            if target_state ~= nil then state = target_state end
            local sig = input.module.sigs[self.sig.text]
            local abi = input.module.sig_abi_by_sig and input.module.sig_abi_by_sig[self.sig.text] or sig_abi(state, sig)
            local result = Back.BackCallStmt
            local args = {}
            local sret_addr = nil
            if abi.sret then
                if self.dst == nil then error("code_to_back: aggregate-return call requires destination", 3) end
                state, sret_addr = create_aggregate_storage(state, self.dst, abi.result_ty, "code_to_back.call_result")
                args[#args + 1] = sret_addr
            elseif self.dst ~= nil then
                local s = sig and sig.results[1] and scalar(sig.results[1]) or nil
                if s == nil then unsupported(self) end
                result = Back.BackCallValue(bid(self.dst), s)
            end
            if closure_ctx ~= nil then args[#args + 1] = closure_ctx end
            for n = 1, #self.args do append_components(args, self.args[n], sig.params[n]) end
            state = state:code_back_append_cmd(Back.CmdCall(result, target, call_sig, args))
            if sret_addr ~= nil and is_view_ty(abi.result_ty) then state = load_view_components_from_addr(state, self.dst, sret_addr, abi.result_ty, "code_to_back.call_view_result") end
        return code_back_result(input, state)
    end
    function Code.CodeTerm:lower_code_term_to_back(input)
        return self.kind:lower_code_term_to_back(Code.CodeBackTermInput(input.module, input.func, input.state, self.id))
    end

    function Code.CodeTermKind:lower_code_term_to_back(input)
        unsupported(self)
    end

    function Code.CodeTermJump:lower_code_term_to_back(input)
        local state = input.state
            local args = {}
            local dest_params = input.func.block_params[self.dest.text] or {}
            for i = 1, #self.args do append_components(args, self.args[i], dest_params[i] and dest_params[i].ty or input.func.value_types[self.args[i].text]) end
            state = state:code_back_append_cmd(Back.CmdJump(block_id(self.dest), args))
        return code_back_result(input, state)
    end

    function Code.CodeTermBranch:lower_code_term_to_back(input)
        local state = input.state
            local ta, ea = {}, {}
            local then_params, else_params = input.func.block_params[self.then_dest.text] or {}, input.func.block_params[self.else_dest.text] or {}
            for i = 1, #self.then_args do append_components(ta, self.then_args[i], then_params[i] and then_params[i].ty or input.func.value_types[self.then_args[i].text]) end
            for i = 1, #self.else_args do append_components(ea, self.else_args[i], else_params[i] and else_params[i].ty or input.func.value_types[self.else_args[i].text]) end
            state = state:code_back_append_cmd(Back.CmdBrIf(bid(self.cond), block_id(self.then_dest), ta, block_id(self.else_dest), ea))
        return code_back_result(input, state)
    end

    function Code.CodeTermSwitch:lower_code_term_to_back(input)
        local state = input.state
            if #(self.default_args or {}) ~= 0 then error("code_to_back: switch default args are not representable in Back CmdSwitchInt", 3) end
            local cases = {}
            for i = 1, #self.cases do
                if #(self.cases[i].args or {}) ~= 0 then error("code_to_back: switch case args are not representable in Back CmdSwitchInt", 3) end
                cases[i] = Back.BackSwitchCase(self.cases[i].literal.raw or tostring(self.cases[i].literal.value), block_id(self.cases[i].dest))
            end
            state = state:code_back_append_cmd(Back.CmdSwitchInt(bid(self.value), Back.BackI32, cases, block_id(self.default_dest)))
        return code_back_result(input, state)
    end

    function Code.CodeTermVariantSwitch:lower_code_term_to_back(input)
        local state = input.state
            if #(self.default_args or {}) ~= 0 then error("code_to_back: variant switch default args are not representable in Back CmdSwitchInt", 3) end
            local cases = {}
            for i = 1, #self.cases do
                if #(self.cases[i].args or {}) ~= 0 then error("code_to_back: variant switch case args are not representable in Back CmdSwitchInt", 3) end
                cases[i] = Back.BackSwitchCase(tostring(self.cases[i].variant.tag_value), block_id(self.cases[i].dest))
            end
            state = state:code_back_append_cmd(Back.CmdSwitchInt(bid(self.tag), Back.BackI32, cases, block_id(self.default_dest)))
        return code_back_result(input, state)
    end

    function Code.CodeTermReturn:lower_code_term_to_back(input)
        local state = input.state
            if #self.values == 0 then state = state:code_back_append_cmd(Back.CmdReturnVoid)
            else
                local rty = input.func.value_types[self.values[1].text]
                if rty:code_back_is_closure() and state.closure_value_has_captures[self.values[1].text] then
                    error("code_to_back: returning captured closure descriptors requires a closure environment ownership model", 3)
                end
                if input.func.current_return_sret ~= nil and is_view_ty(rty) then
                    state = store_view_components_to_addr(state, input.func.current_return_sret, self.values[1], rty, "code_to_back.view_return")
                    state = state:code_back_append_cmd(Back.CmdReturnVoid)
                elseif is_view_ty(rty) then
                    error("code_to_back: view return ABI requires sret lowering", 3)
                elseif input.func.current_return_sret ~= nil and is_byref_aggregate_ty(rty) then
                    local src = aggregate_addr_for_value(state, self.values[1], rty)
                    if src == nil then error("code_to_back: aggregate return value has no address " .. self.values[1].text, 3) end
                    local size = aggregate_size_align(state, rty)
                    local len = const_index(state, size); state = len.state
                    state = state:code_back_append_cmd(Back.CmdMemcpy(input.func.current_return_sret, src, len.value))
                    state = state:code_back_append_cmd(Back.CmdReturnVoid)
                else
                    state = state:code_back_append_cmd(Back.CmdReturnValue(bid(self.values[1])))
                end
            end
        return code_back_result(input, state)
    end

    function Code.CodeTermTrap:lower_code_term_to_back(input)
        local state = input.state
        state = state:code_back_append_cmd(Back.CmdTrap)
        return code_back_result(input, state)
    end

    function Code.CodeTermUnreachable:lower_code_term_to_back(input)
        local state = input.state
        state = state:code_back_append_cmd(Back.CmdTrap)
        return code_back_result(input, state)
    end
    local function func(lowering, f)
        lowering.current_func_id = f.id
        lowering.value_types = {}
        lowering.block_params = {}
        lowering.aggregate_local_addr = {}
        lowering.aggregate_value_addr = {}
        lowering.aggregate_value_size = {}
        lowering.closure_value_has_captures = {}
        lowering.local_stack_slots = {}
        local fsig = lowering.sigs[f.sig.text]
        local fabi = lowering.sig_abi_by_sig and lowering.sig_abi_by_sig[f.sig.text] or (fsig and sig_abi(lowering, fsig))
        lowering.current_return_sret = fabi and fabi.sret and Back.BackValId("sret:" .. f.id.text) or nil
        for i = 1, #(f.params or {}) do lowering_note_value(lowering, f.params[i].value, f.params[i].ty) end
        for i = 1, #(f.blocks or {}) do
            lowering.block_params[f.blocks[i].id.text] = f.blocks[i].params or {}
            for j = 1, #(f.blocks[i].params or {}) do lowering_note_value(lowering, f.blocks[i].params[j].value, f.blocks[i].params[j].ty) end
            for j = 1, #(f.blocks[i].insts or {}) do
                local dst, ty = inst_dst_type(code_back_function_facts_from_lowering(lowering), code_back_module_facts_from_lowering(lowering), f.blocks[i].insts[j].kind)
                lowering_note_value(lowering, dst, ty)
            end
        end
        lowering.cmds[#lowering.cmds + 1] = Back.CmdBeginFunc(func_id(f.id))
        local function_state = code_back_state_from_lowering(lowering)
        function_state = materialize_addressed_locals(function_state, f.locals, true)
        code_back_sync_lowering(lowering, function_state)
        for i = 1, #f.blocks do lowering.cmds[#lowering.cmds + 1] = Back.CmdCreateBlock(block_id(f.blocks[i].id)) end
        for i = 1, #f.blocks do
            local b = f.blocks[i]
            for j = 1, #b.params do
                local vals, shapes = component_values(b.params[j].value, b.params[j].ty), component_shapes(b.params[j].ty)
                for n = 1, #vals do lowering.cmds[#lowering.cmds + 1] = Back.CmdAppendBlockParam(block_id(b.id), vals[n], shapes[n]) end
            end
        end
        for i = 1, #f.blocks do
            local b = f.blocks[i]
            lowering.cmds[#lowering.cmds + 1] = Back.CmdSwitchToBlock(block_id(b.id))
            if b.id == f.entry then
                local params = {}
                if lowering.current_return_sret ~= nil then params[#params + 1] = lowering.current_return_sret end
                for j = 1, #f.params do append_components(params, f.params[j].value, f.params[j].ty) end
                lowering.cmds[#lowering.cmds + 1] = Back.CmdBindEntryParams(block_id(b.id), params)
            end
            for j = 1, #b.insts do
                local result = b.insts[j]:lower_code_inst_to_back(code_back_inst_input(lowering, b.insts[j].id))
                code_back_sync_lowering(lowering, result.state)
            end
            local term_result = b.term:lower_code_term_to_back(code_back_term_input(lowering, b.term.id))
            code_back_sync_lowering(lowering, term_result.state)
        end
        lowering.cmds[#lowering.cmds + 1] = Back.CmdFinishFunc(func_id(f.id))
    end

    local function validate_module(code_module, opts)
        opts = opts or {}
        local report = CodeValidate.validate(code_module, opts.collector)
        if opts.validate ~= false and #report.issues > 0 then
            error("code_to_back: CodeModule failed validation with " .. tostring(#report.issues) .. " issue(s)", 2)
        end
    end

    local function build_fact_context(code_module, opts)
        opts = opts or {}
        if opts.mem ~= nil and opts.value ~= nil and opts.effect ~= nil then return opts.graph, opts.flow, opts.value, opts.mem, opts.effect end
        local graph = opts.graph or CodeGraph.graph(code_module)
        local flow = opts.flow or CodeFlowFacts.facts(code_module, graph)
        local value = opts.value or CodeValueFacts.facts(code_module, graph, flow)
        local mem = opts.mem or CodeMemFacts.semantic_facts(code_module, graph, flow, value, opts.contracts)
        local effect = opts.effect or CodeEffectFacts.facts(code_module, graph, mem, opts.contracts)
        return graph, flow, value, mem, effect
    end

    local function make_lowering(code_module, opts)
        opts = opts or {}
        local _, _, value, mem, effect = build_fact_context(code_module, opts)
        local lowering = { cmds = {}, sigs = {}, sig_abi_by_sig = {}, next_tmp = 0, mem_backend_by_inst = {}, value_int_semantics_by_value = {}, value_float_mode_by_value = {}, value_expr_by_value = {}, effect_by_inst = {}, readonly_inst = {}, aggregate_local_addr = {}, aggregate_value_addr = {}, aggregate_value_size = {}, closure_value_has_captures = {}, local_stack_slots = {}, layout_env = opts.layout_env, target = opts.target }
        for i = 1, #(code_module.sigs or {}) do lowering.sigs[code_module.sigs[i].id.text] = code_module.sigs[i] end
        local backend_by_access, object_by_access, readonly_objects = {}, {}, {}
        for _, info in ipairs(mem and mem.backend_info or {}) do backend_by_access[info.access.text] = info end
        for _, interval in ipairs(mem and mem.intervals or {}) do object_by_access[interval.access.text] = interval.object end
        for _, eff in ipairs(mem and mem.effects or {}) do
            local readonly = eff:code_back_readonly_object()
            if readonly ~= nil then readonly_objects[readonly.text] = true end
        end
        for _, access in ipairs(mem and mem.accesses or {}) do
            local info = backend_by_access[access.id.text]
            if info ~= nil and access.inst ~= nil then
                lowering.mem_backend_by_inst[access.inst.text] = info
                local obj = object_by_access[access.id.text]
                if obj ~= nil and readonly_objects[obj.text] and access.access.mode == Code.CodeMemoryRead then lowering.readonly_inst[access.inst.text] = true end
            end
        end
        local vindex = CodeValueFacts.expr_index(value)
        lowering.value_expr_by_value = vindex.expr_by_value
        lowering.value_int_semantics_by_value = vindex.no_wrap_by_value
        lowering.value_float_mode_by_value = vindex.float_mode_by_value
        for _, inst_effect in ipairs(effect and effect.insts or {}) do lowering.effect_by_inst[inst_effect.inst.text] = inst_effect end
        return lowering
    end

    local function emit_module_prelude(lowering, code_module)
        for i = 1, #(code_module.sigs or {}) do
            local s = code_module.sigs[i]
            local abi = sig_abi(lowering, s)
            lowering.sig_abi_by_sig[s.id.text] = abi
            lowering.cmds[#lowering.cmds + 1] = Back.CmdCreateSig(sig_id(s.id), abi.params, abi.results)
            local cabi = closure_abi(lowering, s)
            lowering.cmds[#lowering.cmds + 1] = Back.CmdCreateSig(closure_sig_id(s.id), cabi.params, cabi.results)
        end
        for i = 1, #(code_module.data or {}) do
            local d = code_module.data[i]
            lowering.cmds[#lowering.cmds + 1] = Back.CmdDeclareData(data_id(d.id), d.size, d.align)
            for j = 1, #d.inits do data_init(lowering, d.inits[j], data_id(d.id)) end
        end
        for i = 1, #(code_module.globals or {}) do
            local g = code_module.globals[i]
            lowering.cmds[#lowering.cmds + 1] = Back.CmdDeclareData(data_id(g.id), g.size or 8, g.align or 1)
            for j = 1, #g.inits do data_init(lowering, g.inits[j], data_id(g.id)) end
        end
        for i = 1, #(code_module.externs or {}) do lowering.cmds[#lowering.cmds + 1] = Back.CmdDeclareExtern(extern_id(code_module.externs[i].id), code_module.externs[i].symbol, sig_id(code_module.externs[i].sig)) end
    end

    local function function_declare(f)
        local vis = (f.linkage == Code.CodeLinkageExport) and Core.VisibilityExport or Core.VisibilityLocal
        return Back.CmdDeclareFunc(vis, func_id(f.id), sig_id(f.sig))
    end

    local function function_body_commands(code_module, f)
        local lowering = make_lowering(code_module)
        func(lowering, f)
        return lowering.cmds
    end

    local function code_back_find_func(code_module, func_id_)
        for _, f in ipairs(code_module.funcs or {}) do
            if f.id == func_id_ then return f end
        end
        return nil
    end

    function Lower.LowerCover:code_back_blocks_for_cover(code_module, graph)
        error("code_to_back: unable to resolve LowerCover for fragment", 2)
    end

    function Lower.LowerCoverFunction:code_back_blocks_for_cover(code_module, graph)
        local f = code_back_find_func(code_module, self.func)
        if f ~= nil then return f, f.blocks or {} end
        return Lower.LowerCover.code_back_blocks_for_cover(self, code_module, graph)
    end

    function Lower.LowerCoverBlock:code_back_blocks_for_cover(code_module, graph)
        local f = code_back_find_func(code_module, self.func)
        if f ~= nil then
            for _, b in ipairs(f.blocks or {}) do
                if b.id == self.block then return f, { b } end
            end
        end
        return Lower.LowerCover.code_back_blocks_for_cover(self, code_module, graph)
    end

    function Lower.LowerCoverBlockRange:code_back_blocks_for_cover(code_module, graph)
        local f = code_back_find_func(code_module, self.func)
        if f ~= nil then
            local out, active = {}, false
            for _, b in ipairs(f.blocks or {}) do
                if b.id == self.entry then active = true end
                if active then out[#out + 1] = b end
                if b.id == self.exit then break end
            end
            return f, out
        end
        return Lower.LowerCover.code_back_blocks_for_cover(self, code_module, graph)
    end

    function Lower.LowerCoverLoop:code_back_blocks_for_cover(code_module, graph)
        local block_set, func_id_ = {}, nil
        for _, fg in ipairs(graph and graph.funcs or {}) do
            for _, loop in ipairs(fg.loops or {}) do
                if loop.id == self.loop then
                    func_id_ = fg.func
                    for _, bid in ipairs(loop.body or {}) do block_set[bid.block.text] = true end
                end
            end
        end
        if func_id_ ~= nil then
            local f = code_back_find_func(code_module, func_id_)
            if f ~= nil then
                local out = {}
                for _, b in ipairs(f.blocks or {}) do if block_set[b.id.text] then out[#out + 1] = b end end
                return f, out
            end
        end
        return Lower.LowerCover.code_back_blocks_for_cover(self, code_module, graph)
    end

    local function blocks_for_cover(code_module, graph, cover)
        return cover:code_back_blocks_for_cover(code_module, graph)
    end

    local function fragment_commands(code_module, graph, flow, value, mem, effect, cover, opts)
        opts = opts or {}
        opts.graph, opts.flow, opts.value, opts.mem, opts.effect = graph, flow, value, mem, effect
        validate_module(code_module, opts)
        local lowering = make_lowering(code_module, opts)
        lowering.value_types = {}
        lowering.block_params = {}
        lowering.aggregate_local_addr = {}
        lowering.aggregate_value_addr = {}
        lowering.aggregate_value_size = {}
        lowering.closure_value_has_captures = {}
        lowering.local_stack_slots = {}
        local f, blocks = blocks_for_cover(code_module, graph or opts.graph or CodeGraph.graph(code_module), cover)
        lowering.current_func_id = f.id
        local fsig = lowering.sigs[f.sig.text]
        local fabi = lowering.sig_abi_by_sig and lowering.sig_abi_by_sig[f.sig.text] or (fsig and sig_abi(lowering, fsig))
        lowering.current_return_sret = fabi and fabi.sret and Back.BackValId("sret:" .. f.id.text) or nil
        local function_state = code_back_state_from_lowering(lowering)
        function_state = materialize_addressed_locals(function_state, f.locals, opts.emit_local_slots ~= false)
        code_back_sync_lowering(lowering, function_state)
        local block_ord = {}
        for i, b in ipairs(f.blocks or {}) do block_ord[b.id.text] = i end
        local first_ord = 1
        if blocks and blocks[1] and block_ord[blocks[1].id.text] then first_ord = block_ord[blocks[1].id.text] end
        lowering.next_tmp = first_ord * 1000000
        for _, param in ipairs(f.params or {}) do lowering_note_value(lowering, param.value, param.ty) end
        for _, b in ipairs(f.blocks or {}) do
            lowering.block_params[b.id.text] = b.params or {}
            for _, param in ipairs(b.params or {}) do lowering_note_value(lowering, param.value, param.ty) end
            for _, i in ipairs(b.insts or {}) do
                local dst, ty = inst_dst_type(code_back_function_facts_from_lowering(lowering), code_back_module_facts_from_lowering(lowering), i.kind)
                lowering_note_value(lowering, dst, ty)
            end
        end
        for _, b in ipairs(blocks or {}) do
            lowering.cmds[#lowering.cmds + 1] = Back.CmdSwitchToBlock(block_id(b.id))
            if b.id == f.entry then
                local params = {}
                if lowering.current_return_sret ~= nil then params[#params + 1] = lowering.current_return_sret end
                for j = 1, #f.params do append_components(params, f.params[j].value, f.params[j].ty) end
                lowering.cmds[#lowering.cmds + 1] = Back.CmdBindEntryParams(block_id(b.id), params)
            end
            for _, i in ipairs(b.insts or {}) do
                local result = i:lower_code_inst_to_back(code_back_inst_input(lowering, i.id))
                code_back_sync_lowering(lowering, result.state)
            end
            local term_result = b.term:lower_code_term_to_back(code_back_term_input(lowering, b.term.id))
            code_back_sync_lowering(lowering, term_result.state)
        end
        return lowering.cmds
    end

    local function module_prelude_commands(code_module, opts)
        opts = opts or {}
        validate_module(code_module, opts)
        local lowering = make_lowering(code_module, opts)
        emit_module_prelude(lowering, code_module)
        return lowering.cmds
    end

    local function function_local_stack_slot_commands(code_module, f, opts)
        opts = opts or {}
        local lowering = make_lowering(code_module, opts)
        lowering.local_stack_slots = {}
        local state = code_back_state_from_lowering(lowering)
        state = materialize_addressed_locals(state, f.locals, true)
        code_back_sync_lowering(lowering, state)
        return lowering.cmds
    end

    local function module(code_module, opts)
        opts = opts or {}
        validate_module(code_module, opts)
        local lowering = make_lowering(code_module, opts)
        emit_module_prelude(lowering, code_module)
        for i = 1, #(code_module.funcs or {}) do
            lowering.cmds[#lowering.cmds + 1] = function_declare(code_module.funcs[i])
        end
        for i = 1, #(code_module.funcs or {}) do
            func(lowering, code_module.funcs[i])
        end
        lowering.cmds[#lowering.cmds + 1] = Back.CmdFinalizeModule
        return Back.BackProgram(lowering.cmds)
    end

    api.module = module
    api.module_prelude_commands = module_prelude_commands
    api.function_local_stack_slot_commands = function_local_stack_slot_commands
    api.function_declare = function_declare
    api.function_body_commands = function_body_commands
    api.fragment_commands = fragment_commands
    api.scalar = scalar

    T._lalin_api_cache.code_to_back = api
    return api
end

return bind_context
