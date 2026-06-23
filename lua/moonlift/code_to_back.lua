local pvm = require("moonlift.pvm")

local function class_name(x)
    local cls = pvm.classof(x) or x
    return tostring(cls):match("Class%((.-)%)") or tostring(cls)
end

local function bind_context(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.code_to_back ~= nil then return T._moonlift_api_cache.code_to_back end

    local Core = T.MoonCore
    local Code = T.MoonCode
    local Back = T.MoonBack
    local Lower = T.MoonLower
    local CodeValidate = require("moonlift.code_validate")(T)
    local CodeGraph = require("moonlift.code_graph")(T)
    local CodeFlowFacts = require("moonlift.code_flow_facts")(T)
    local CodeValueFacts = require("moonlift.code_value_facts")(T)
    local CodeMemFacts = require("moonlift.code_mem_facts")(T)
    local CodeEffectFacts = require("moonlift.code_effect_facts")(T)
    local CodeAggregateAbi = require("moonlift.code_aggregate_abi")(T)

    local api = {}

    local function unsupported(x)
        error("code_to_back: unsupported " .. class_name(x), 3)
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

    local function literal(lit)
        local cls = pvm.classof(lit)
        if cls == Core.LitInt then return Back.BackLitInt(lit.raw) end
        if cls == Core.LitFloat then return Back.BackLitFloat(lit.raw) end
        if cls == Core.LitBool then return Back.BackLitBool(lit.value) end
        if lit == Core.LitNil or cls == Core.LitNil then return Back.BackLitNull end
        unsupported(lit)
    end

    local function const_literal(k)
        local cls = pvm.classof(k)
        if cls == Code.CodeConstLiteral then return literal(k.literal) end
        if cls == Code.CodeConstNull then return Back.BackLitNull end
        if cls == Code.CodeConstUndef then return Back.BackLitInt("0") end
        unsupported(k)
    end

    local function int_op(op)
        if op == Core.BinAdd then return Back.BackIntAdd end
        if op == Core.BinSub then return Back.BackIntSub end
        if op == Core.BinMul then return Back.BackIntMul end
        if op == Core.BinDiv then return Back.BackIntSDiv end
        if op == Core.BinRem then return Back.BackIntSRem end
        return nil
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

    local function atomic_ordering(ordering)
        if ordering == Core.AtomicSeqCst then return Back.BackAtomicSeqCst end
        unsupported(ordering)
    end

    local function atomic_rmw_op(op)
        if op == Core.AtomicRmwAdd then return Back.BackAtomicRmwAdd end
        if op == Core.AtomicRmwSub then return Back.BackAtomicRmwSub end
        if op == Core.AtomicRmwAnd then return Back.BackAtomicRmwAnd end
        if op == Core.AtomicRmwOr then return Back.BackAtomicRmwOr end
        if op == Core.AtomicRmwXor then return Back.BackAtomicRmwXor end
        if op == Core.AtomicRmwXchg then return Back.BackAtomicRmwXchg end
        unsupported(op)
    end

    local function float_op(op)
        if op == Core.BinAdd then return Back.BackFloatAdd end
        if op == Core.BinSub then return Back.BackFloatSub end
        if op == Core.BinMul then return Back.BackFloatMul end
        if op == Core.BinDiv then return Back.BackFloatDiv end
        return nil
    end

    local function unary_op(op)
        if op == Core.UnaryNeg then return Back.BackUnaryIneg end
        if op == Core.UnaryFNeg then return Back.BackUnaryFneg end
        if op == Core.UnaryBitNot then return Back.BackUnaryBnot end
        if op == Core.UnaryNot then return Back.BackUnaryBoolNot end
        return nil
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
        unsupported(op)
    end

    local function cast_op(op)
        if op == Core.CastBitcast or op == Core.MachineCastBitcast or op == Core.MachineCastIdentity then return Back.BackBitcast end
        if op == Core.CastTrunc or op == Core.MachineCastIreduce then return Back.BackIreduce end
        if op == Core.CastSExt or op == Core.MachineCastSextend then return Back.BackSextend end
        if op == Core.CastZExt or op == Core.MachineCastUextend then return Back.BackUextend end
        if op == Core.CastFPExt or op == Core.MachineCastFpromote then return Back.BackFpromote end
        if op == Core.CastFPTrunc or op == Core.MachineCastFdemote then return Back.BackFdemote end
        if op == Core.CastSIToFP or op == Core.MachineCastSToF then return Back.BackSToF end
        if op == Core.CastUIToFP or op == Core.MachineCastUToF then return Back.BackUToF end
        if op == Core.CastFPToSI or op == Core.MachineCastFToS then return Back.BackFToS end
        if op == Core.CastFPToUI or op == Core.MachineCastFToU then return Back.BackFToU end
        unsupported(op)
    end

    local function intrinsic_op(op)
        if op == Core.IntrinsicPopcount then return Back.BackIntrinsicPopcount end
        if op == Core.IntrinsicClz then return Back.BackIntrinsicClz end
        if op == Core.IntrinsicCtz then return Back.BackIntrinsicCtz end
        if op == Core.IntrinsicBswap then return Back.BackIntrinsicBswap end
        if op == Core.IntrinsicSqrt then return Back.BackIntrinsicSqrt end
        if op == Core.IntrinsicAbs then return Back.BackIntrinsicAbs end
        if op == Core.IntrinsicFloor then return Back.BackIntrinsicFloor end
        if op == Core.IntrinsicCeil then return Back.BackIntrinsicCeil end
        if op == Core.IntrinsicTruncFloat then return Back.BackIntrinsicTruncFloat end
        if op == Core.IntrinsicRound then return Back.BackIntrinsicRound end
        return nil
    end

    local function rotate_op(op)
        if op == Core.IntrinsicRotl then return Back.BackRotateLeft end
        if op == Core.IntrinsicRotr then return Back.BackRotateRight end
        return nil
    end

    local function int_semantics(ctx, k)
        local fact = ctx.value_int_semantics_by_value and ctx.value_int_semantics_by_value[k.dst.text]
        local sem = fact or k.semantics
        local overflow = Back.BackIntWrap
        if sem ~= nil then
            local ocls = pvm.classof(sem.overflow)
            if ocls == Code.CodeIntAssumeNoOverflow then overflow = Back.BackIntNoWrap(sem.overflow.reason)
            elseif sem.overflow == Code.CodeIntTrapOnOverflow then overflow = Back.BackIntNoWrap("trap-on-overflow Code semantics") end
        end
        return Back.BackIntSemantics(overflow, Back.BackIntMayLose)
    end

    local function float_semantics(ctx, k)
        local mode = (ctx.value_float_mode_by_value and ctx.value_float_mode_by_value[k.dst.text]) or k.mode
        if mode == nil or mode == Code.CodeFloatStrict then return Back.BackFloatStrict end
        local cls = pvm.classof(mode)
        if cls == Code.CodeFloatReassoc then return Back.BackFloatReassoc(mode.reason) end
        if cls == Code.CodeFloatFastMath then return Back.BackFloatFastMath(mode.reason) end
        return Back.BackFloatStrict
    end

    local function zero(ctx)
        ctx.next_tmp = (ctx.next_tmp or 0) + 1
        local v = Back.BackValId("code_to_back.zero." .. tostring(ctx.next_tmp))
        ctx.cmds[#ctx.cmds + 1] = Back.CmdConst(v, Back.BackIndex, Back.BackLitInt("0"))
        return v
    end

    local function note_value(ctx, id, ty)
        if id ~= nil and ty ~= nil then ctx.value_types[id.text] = ty end
    end

    local function index_value(ctx, id)
        local ty = ctx.value_types[id.text]
        if ty == Code.CodeTyIndex then return bid(id) end
        local cls = pvm.classof(ty)
        if cls == Code.CodeTyInt and ty.bits < 64 then
            ctx.next_tmp = (ctx.next_tmp or 0) + 1
            local v = Back.BackValId("code_to_back.index." .. tostring(ctx.next_tmp))
            local op = ty.signedness == Code.CodeSigned and Back.BackSextend or Back.BackUextend
            ctx.cmds[#ctx.cmds + 1] = Back.CmdCast(v, op, Back.BackIndex, bid(id))
            return v
        elseif ty == Code.CodeTyBool8 then
            ctx.next_tmp = (ctx.next_tmp or 0) + 1
            local v = Back.BackValId("code_to_back.index." .. tostring(ctx.next_tmp))
            ctx.cmds[#ctx.cmds + 1] = Back.CmdCast(v, Back.BackUextend, Back.BackIndex, bid(id))
            return v
        end
        return bid(id)
    end

    local function value_as(ctx, id, ty)
        if ty == Code.CodeTyIndex then return index_value(ctx, id) end
        return bid(id)
    end

    local function access_mode(mode, readonly)
        if readonly and mode == Code.CodeMemoryRead then return Back.BackAccessReadonly end
        if mode == Code.CodeMemoryWrite then return Back.BackAccessWrite end
        if mode == Code.CodeMemoryReadWrite then return Back.BackAccessReadWrite end
        return Back.BackAccessRead
    end

    local function back_alignment(alignment)
        local cls = pvm.classof(alignment)
        if alignment == nil or alignment == T.MoonMem.MemAlignUnknown then return Back.BackAlignUnknown end
        if cls == T.MoonMem.MemAlignKnown then return Back.BackAlignKnown(alignment.bytes) end
        if cls == T.MoonMem.MemAlignAtLeast then return Back.BackAlignAtLeast(alignment.bytes) end
        if cls == T.MoonMem.MemAlignAssumed then return Back.BackAlignAssumed(alignment.bytes, "MemBackendAccessInfo assumption") end
        return Back.BackAlignUnknown
    end

    local function back_trap(trap)
        local cls = pvm.classof(trap)
        if trap == T.MoonMem.MemMayTrap then return Back.BackMayTrap end
        if cls == T.MoonMem.MemNonTrapping then return Back.BackNonTrapping(trap.reason) end
        if cls == T.MoonMem.MemCheckedTrap then return Back.BackChecked(trap.reason) end
        return Back.BackMayTrap
    end

    local function memory_info(ctx, access, inst_id)
        local info = ctx.mem_backend_by_inst and ctx.mem_backend_by_inst[inst_id.text] or nil
        if info == nil then error("code_to_back: missing MemBackendAccessInfo for Code inst " .. inst_id.text, 3) end
        local deref = info.deref_bytes and Back.BackDerefBytes(info.deref_bytes, "MemBackendAccessInfo") or Back.BackDerefUnknown
        local motion = info.movable and Back.BackCanMove("MemBackendAccessInfo movable") or Back.BackMayNotMove
        local readonly = ctx.readonly_inst and ctx.readonly_inst[inst_id.text]
        return Back.BackMemoryInfo(Back.BackAccessId(info.access.text), back_alignment(info.alignment), deref, back_trap(info.trap), motion, access_mode(access.mode, readonly))
    end

    local function component_memory_info(ctx, access, inst_id, field)
        local info = ctx.mem_backend_by_inst and ctx.mem_backend_by_inst[inst_id.text] or nil
        if info == nil then error("code_to_back: missing MemBackendAccessInfo for Code inst " .. inst_id.text, 3) end
        local motion = info.movable and Back.BackCanMove("MemBackendAccessInfo movable view component") or Back.BackMayNotMove
        local readonly = ctx.readonly_inst and ctx.readonly_inst[inst_id.text]
        return Back.BackMemoryInfo(Back.BackAccessId(info.access.text .. ":" .. field), back_alignment(info.alignment), Back.BackDerefBytes(8, "view descriptor component"), back_trap(info.trap), motion, access_mode(access.mode, readonly))
    end

    local function const_index(ctx, raw)
        ctx.next_tmp = (ctx.next_tmp or 0) + 1
        local v = Back.BackValId("code_to_back.const_index." .. tostring(ctx.next_tmp))
        ctx.cmds[#ctx.cmds + 1] = Back.CmdConst(v, Back.BackIndex, Back.BackLitInt(tostring(raw)))
        return v
    end

    local function null_ptr(ctx, tag)
        ctx.next_tmp = (ctx.next_tmp or 0) + 1
        local v = Back.BackValId((tag or "code_to_back.null") .. "." .. tostring(ctx.next_tmp))
        ctx.cmds[#ctx.cmds + 1] = Back.CmdConst(v, Back.BackPtr, Back.BackLitNull)
        return v
    end

    local function address_at_const_offset(ctx, addr, offset)
        local base = addr.base
        local base_cls = pvm.classof(base)
        if base_cls == Back.BackAddrStack then
            local base_ptr = Back.BackValId("code_to_back.addr_stack_base." .. tostring(ctx.next_tmp or 0))
            ctx.next_tmp = (ctx.next_tmp or 0) + 1
            ctx.cmds[#ctx.cmds + 1] = Back.CmdStackAddr(base_ptr, base.slot)
            base = Back.BackAddrValue(base_ptr)
        elseif base_cls == Back.BackAddrData then
            local base_ptr = Back.BackValId("code_to_back.addr_data_base." .. tostring(ctx.next_tmp or 0))
            ctx.next_tmp = (ctx.next_tmp or 0) + 1
            ctx.cmds[#ctx.cmds + 1] = Back.CmdDataAddr(base_ptr, base.data)
            base = Back.BackAddrValue(base_ptr)
        end
        if offset == 0 then return Back.BackAddress(base, addr.byte_offset, addr.provenance, addr.formation_bounds) end
        local ptr = Back.BackValId("code_to_back.view_addr." .. tostring(ctx.next_tmp or 0) .. "." .. tostring(offset))
        ctx.next_tmp = (ctx.next_tmp or 0) + 1
        ctx.cmds[#ctx.cmds + 1] = Back.CmdPtrOffset(ptr, base, addr.byte_offset, 1, offset, addr.provenance, addr.formation_bounds)
        return Back.BackAddress(Back.BackAddrValue(ptr), zero(ctx), addr.provenance, addr.formation_bounds)
    end

    local function address_to_ptr_value(ctx, addr, tag)
        local base = addr.base
        local base_cls = pvm.classof(base)
        if base_cls == Back.BackAddrStack then
            local base_ptr = Back.BackValId((tag or "code_to_back.stack_base") .. ".base." .. tostring(ctx.next_tmp or 0))
            ctx.next_tmp = (ctx.next_tmp or 0) + 1
            ctx.cmds[#ctx.cmds + 1] = Back.CmdStackAddr(base_ptr, base.slot)
            base = Back.BackAddrValue(base_ptr)
        elseif base_cls == Back.BackAddrData then
            local base_ptr = Back.BackValId((tag or "code_to_back.data_base") .. ".base." .. tostring(ctx.next_tmp or 0))
            ctx.next_tmp = (ctx.next_tmp or 0) + 1
            ctx.cmds[#ctx.cmds + 1] = Back.CmdDataAddr(base_ptr, base.data)
            base = Back.BackAddrValue(base_ptr)
        end
        local ptr = Back.BackValId((tag or "code_to_back.addr_value") .. "." .. tostring(ctx.next_tmp or 0))
        ctx.next_tmp = (ctx.next_tmp or 0) + 1
        ctx.cmds[#ctx.cmds + 1] = Back.CmdPtrOffset(ptr, base, addr.byte_offset, 1, 0, addr.provenance, addr.formation_bounds)
        return ptr
    end

    local function back_bounds(info)
        if info ~= nil and pvm.classof(info.bounds) ~= T.MoonMem.MemBoundsUnknown then return Back.BackPtrInBounds("MemBackendAccessInfo bounds") end
        return Back.BackPtrBoundsUnknown
    end

    local function addr_from_place(ctx, place, info)
        local cls = pvm.classof(place)
        if cls == Code.CodePlaceDeref then
            return Back.BackAddress(Back.BackAddrValue(bid(place.addr)), zero(ctx), Back.BackProvUnknown, back_bounds(info))
        elseif cls == Code.CodePlaceGlobal then
            return Back.BackAddress(Back.BackAddrData(data_id(place.global)), zero(ctx), Back.BackProvData(data_id(place.global)), Back.BackPtrInBounds("global"))
        elseif cls == Code.CodePlaceData then
            return Back.BackAddress(Back.BackAddrData(data_id(place.data)), zero(ctx), Back.BackProvData(data_id(place.data)), Back.BackPtrInBounds("data"))
        elseif cls == Code.CodePlaceLocal then
            local ty_cls = pvm.classof(place.ty)
            if CodeAggregateAbi.is_view(place.ty) then
                local stack = ctx.local_stack_slots and ctx.local_stack_slots[place.local_id.text]
                if stack == nil then error("code_to_back: view local has no materialized descriptor " .. place.local_id.text, 3) end
                return Back.BackAddress(Back.BackAddrStack(stack.slot), zero(ctx), Back.BackProvStack(stack.slot), back_bounds(info))
            end
            if ty_cls == Code.CodeTyNamed or ty_cls == Code.CodeTyArray or ty_cls == Code.CodeTySlice or ty_cls == Code.CodeTyClosure then
                local addr = ctx.aggregate_local_addr and ctx.aggregate_local_addr[place.local_id.text]
                if addr == nil then error("code_to_back: aggregate local has no materialized address " .. place.local_id.text, 3) end
                return Back.BackAddress(Back.BackAddrValue(addr), zero(ctx), Back.BackProvUnknown, back_bounds(info))
            end
            local stack = ctx.local_stack_slots and ctx.local_stack_slots[place.local_id.text]
            if stack ~= nil then
                return Back.BackAddress(Back.BackAddrStack(stack.slot), zero(ctx), Back.BackProvStack(stack.slot), back_bounds(info))
            end
        elseif cls == Code.CodePlaceField then
            local base = addr_from_place(ctx, place.base, info)
            local ptr = Back.BackValId("code_to_back.field." .. tostring(ctx.next_tmp or 0) .. "." .. tostring(place.offset or 0))
            ctx.next_tmp = (ctx.next_tmp or 0) + 1
            local bounds = back_bounds(info)
            local idx0 = const_index(ctx, 0)
            ctx.cmds[#ctx.cmds + 1] = Back.CmdPtrOffset(ptr, base.base, idx0, 1, place.offset or 0, Back.BackProvDerived("field"), bounds)
            return Back.BackAddress(Back.BackAddrValue(ptr), zero(ctx), Back.BackProvDerived("field"), bounds)
        elseif cls == Code.CodePlaceIndex then
            local base = addr_from_place(ctx, place.base, info)
            local ptr = Back.BackValId("code_to_back.addr." .. place.index.text)
            local index = index_value(ctx, place.index)
            local bounds = back_bounds(info)
            ctx.cmds[#ctx.cmds + 1] = Back.CmdPtrOffset(ptr, base.base, index, place.elem_size, 0, Back.BackProvDerived("index"), bounds)
            return Back.BackAddress(Back.BackAddrValue(ptr), zero(ctx), Back.BackProvDerived("index"), bounds)
        end
        unsupported(place)
    end

    local function data_init(ctx, init, data)
        local cls = pvm.classof(init)
        if cls == Code.CodeDataZero then
            ctx.cmds[#ctx.cmds + 1] = Back.CmdDataInitZero(data, init.offset, init.size)
        elseif cls == Code.CodeDataScalar then
            local s = scalar(init.ty); if s == nil then unsupported(init.ty) end
            ctx.cmds[#ctx.cmds + 1] = Back.CmdDataInit(data, init.offset, s, literal(init.literal))
        elseif cls == Code.CodeDataBytes then
            for i = 1, #init.bytes do
                ctx.cmds[#ctx.cmds + 1] = Back.CmdDataInit(data, init.offset + i - 1, Back.BackU8, Back.BackLitInt(tostring(init.bytes:byte(i))))
            end
        else
            unsupported(init)
        end
    end

    local function inst_dst_type(ctx, k)
        local cls = pvm.classof(k)
        if cls == Code.CodeInstConst then return k.dst, k.const.ty end
        if cls == Code.CodeInstAlias then return k.dst, k.ty end
        if cls == Code.CodeInstUnary then return k.dst, k.ty end
        if cls == Code.CodeInstBinary then return k.dst, k.ty end
        if cls == Code.CodeInstFloatBinary then return k.dst, k.ty end
        if cls == Code.CodeInstCompare then return k.dst, Code.CodeTyBool8 end
        if cls == Code.CodeInstCast then return k.dst, k.to end
        if cls == Code.CodeInstIntrinsic then return k.dst, k.ty end
        if cls == Code.CodeInstSelect then return k.dst, k.ty end
        if cls == Code.CodeInstAddrOf then return k.dst, k.ptr_ty end
        if cls == Code.CodeInstGlobalRef then return k.dst, k.ptr_ty end
        if cls == Code.CodeInstPtrOffset then return k.dst, k.ptr_ty end
        if cls == Code.CodeInstLoad or cls == Code.CodeInstAtomicLoad or cls == Code.CodeInstAtomicRmw or cls == Code.CodeInstAtomicCas then return k.dst, k.access.ty end
        if cls == Code.CodeInstAggregate or cls == Code.CodeInstArray or cls == Code.CodeInstClosure or cls == Code.CodeInstVariantCtor then return k.dst, k.ty end
        if cls == Code.CodeInstVariantTag then return k.dst, k.tag_ty end
        if cls == Code.CodeInstVariantPayload then return k.dst, k.variant.payload_ty end
        if cls == Code.CodeInstViewMake then return k.dst, Code.CodeTyView(k.elem_ty) end
        if cls == Code.CodeInstViewData then
            local vty = ctx.value_types and ctx.value_types[k.view.text] or nil
            if pvm.classof(vty) == Code.CodeTyLease then vty = vty.base end
            return k.dst, Code.CodeTyDataPtr(pvm.classof(vty) == Code.CodeTyView and vty.elem or nil)
        end
        if cls == Code.CodeInstViewLen or cls == Code.CodeInstViewStride then return k.dst, Code.CodeTyIndex end
        if cls == Code.CodeInstCall then
            local sig = k.sig and ctx.sigs[k.sig.text] or nil
            if sig and sig.results[1] then return k.dst, sig.results[1] end
        end
        return nil, nil
    end

    local function view_component_id(view, field)
        return Back.BackValId(view.text .. ":view_" .. field)
    end

    local function is_view_ty(ty) return CodeAggregateAbi.is_view(ty) end

    local function view_elem(ty) return CodeAggregateAbi.view_elem(ty) end

    local function is_byref_aggregate_ty(ty) return CodeAggregateAbi.is_aggregate(ty) end

    local function component_scalars(ty) return CodeAggregateAbi.component_scalars(ty) end

    local function sig_abi(ctx, sig) return CodeAggregateAbi.lowered_sig(sig) end

    local function closure_abi(ctx, sig)
        local abi = sig_abi(ctx, sig)
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

    local function aggregate_layout(ctx, ty) return CodeAggregateAbi.layout(ctx, ty) end

    local function aggregate_size_align(ctx, ty) return CodeAggregateAbi.size_align(ctx, ty) end

    local function code_size_align(ctx, ty)
        if is_view_ty(ty) then return aggregate_size_align(ctx, ty) end
        if CodeAggregateAbi.is_aggregate(ty) then return aggregate_size_align(ctx, ty) end
        local s = scalar(ty); if s == nil then unsupported(ty) end
        return scalar_size_align(s)
    end

    local function layout_field_offset(ctx, ty, name) return CodeAggregateAbi.field_offset(ctx, ty, name) end

    local function synthetic_memory(ctx, tag, bytes, mode)
        ctx.next_tmp = (ctx.next_tmp or 0) + 1
        return Back.BackMemoryInfo(Back.BackAccessId("code_to_back." .. tag .. "." .. tostring(ctx.next_tmp)), Back.BackAlignUnknown, Back.BackDerefBytes(bytes or 1, "Code aggregate ABI"), Back.BackNonTrapping("Code aggregate ABI stack/local access"), Back.BackCanMove("Code aggregate ABI local access"), mode)
    end

    local function aggregate_addr_for_value(ctx, id, ty)
        local mapped = ctx.aggregate_value_addr and ctx.aggregate_value_addr[id.text]
        if mapped ~= nil then return mapped end
        if is_byref_aggregate_ty(ty) then return bid(id) end
        return nil
    end

    local function create_aggregate_storage(ctx, id, ty, prefix, size_override, align_override)
        local size, align = aggregate_size_align(ctx, ty)
        size = size_override or size
        align = align_override or align
        local slot = Back.BackStackSlotId((prefix or "code_to_back.aggregate") .. ":" .. id.text)
        local addr = Back.BackValId(id.text .. ":addr")
        ctx.cmds[#ctx.cmds + 1] = Back.CmdCreateStackSlot(slot, size, align)
        ctx.cmds[#ctx.cmds + 1] = Back.CmdStackAddr(addr, slot)
        ctx.cmds[#ctx.cmds + 1] = Back.CmdAlias(bid(id), addr)
        ctx.aggregate_value_addr[id.text] = addr
        ctx.aggregate_value_size[id.text] = size
        return addr, size, align
    end

    local function create_local_stack_slot(ctx, local_, prefix, emit)
        local size, align = code_size_align(ctx, local_.ty)
        local slot = Back.BackStackSlotId((prefix or "code_to_back.local") .. ":" .. local_.id.text)
        if emit ~= false then ctx.cmds[#ctx.cmds + 1] = Back.CmdCreateStackSlot(slot, size, align) end
        ctx.local_stack_slots = ctx.local_stack_slots or {}
        ctx.local_stack_slots[local_.id.text] = { slot = slot, ty = local_.ty, size = size, align = align }
        return slot
    end

    local function materialize_addressed_locals(ctx, locals, emit)
        ctx.local_stack_slots = ctx.local_stack_slots or {}
        for _, local_ in ipairs(locals or {}) do
            if is_view_ty(local_.ty) then
                create_local_stack_slot(ctx, local_, nil, emit)
            elseif local_.residence == Code.CodeResidenceAddressed and not CodeAggregateAbi.is_aggregate(local_.ty) then
                create_local_stack_slot(ctx, local_, nil, emit)
            end
        end
    end

    local function closure_descriptor_size(ctx, fields)
        local size, align = 16, 8
        for _, field in ipairs(fields or {}) do
            local name = field.field and field.field.field_name
            if name ~= "__moon_fn" then
                local fty = ctx.value_types[field.value.text]
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

    local function store_scalar_at_offset(ctx, base_addr, offset, value, ty, tag)
        local s = scalar(ty); if s == nil then unsupported(ty) end
        local sz = scalar_size_align(s)
        local ptr = Back.BackValId((tag or "code_to_back.store_field") .. ".ptr." .. tostring(ctx.next_tmp or 0) .. "." .. tostring(offset or 0))
        local idx0 = const_index(ctx, 0)
        ctx.cmds[#ctx.cmds + 1] = Back.CmdPtrOffset(ptr, Back.BackAddrValue(base_addr), idx0, 1, offset or 0, Back.BackProvDerived(tag or "aggregate field"), Back.BackPtrInBounds("aggregate field"))
        local z = zero(ctx)
        ctx.cmds[#ctx.cmds + 1] = Back.CmdStoreInfo(Back.BackShapeScalar(s), Back.BackAddress(Back.BackAddrValue(ptr), z, Back.BackProvDerived(tag or "aggregate field"), Back.BackPtrInBounds("aggregate field")), value, synthetic_memory(ctx, tag or "aggregate_store", sz, Back.BackAccessWrite))
    end

    local function load_scalar_at_offset(ctx, dst, base_addr, offset, ty, tag)
        local s = scalar(ty); if s == nil then unsupported(ty) end
        local sz = scalar_size_align(s)
        local ptr = Back.BackValId((tag or "code_to_back.load_field") .. ".ptr." .. tostring(ctx.next_tmp or 0) .. "." .. tostring(offset or 0))
        local idx0 = const_index(ctx, 0)
        ctx.cmds[#ctx.cmds + 1] = Back.CmdPtrOffset(ptr, Back.BackAddrValue(base_addr), idx0, 1, offset or 0, Back.BackProvDerived(tag or "aggregate field"), Back.BackPtrInBounds("aggregate field"))
        local z = zero(ctx)
        ctx.cmds[#ctx.cmds + 1] = Back.CmdLoadInfo(dst, Back.BackShapeScalar(s), Back.BackAddress(Back.BackAddrValue(ptr), z, Back.BackProvDerived(tag or "aggregate field"), Back.BackPtrInBounds("aggregate field")), synthetic_memory(ctx, tag or "aggregate_load", sz, Back.BackAccessRead))
    end

    local function source_aggregate_ptr(ctx, value)
        return ctx.aggregate_value_addr[value.text] or bid(value)
    end

    local function ptr_at_offset(ctx, base_addr, offset, tag)
        local ptr = Back.BackValId((tag or "code_to_back.aggregate_ptr") .. "." .. tostring(ctx.next_tmp or 0) .. "." .. tostring(offset or 0))
        ctx.next_tmp = (ctx.next_tmp or 0) + 1
        local idx0 = const_index(ctx, 0)
        ctx.cmds[#ctx.cmds + 1] = Back.CmdPtrOffset(ptr, Back.BackAddrValue(base_addr), idx0, 1, offset or 0, Back.BackProvDerived(tag or "aggregate copy"), Back.BackPtrInBounds("aggregate copy"))
        return ptr
    end

    local function copy_aggregate_from_ptr(ctx, dst_base, dst_offset, src_base, ty, tag, src_offset)
        local size = aggregate_size_align(ctx, ty)
        local dst_ptr = ptr_at_offset(ctx, dst_base, dst_offset or 0, (tag or "aggregate_copy") .. ".dst")
        local src_ptr = ptr_at_offset(ctx, src_base, src_offset or 0, (tag or "aggregate_copy") .. ".src")
        local len = const_index(ctx, size)
        ctx.cmds[#ctx.cmds + 1] = Back.CmdMemcpy(dst_ptr, src_ptr, len)
    end

    local function copy_value_to_offset(ctx, dst_base, dst_offset, value, ty, tag, src_base, src_offset, tmp)
        if is_view_ty(ty) then
            local vals
            if value ~= nil then
                vals = component_values(value, ty)
            else
                vals = {
                    tmp or Back.BackValId((tag or "view_copy") .. ".data." .. tostring(ctx.next_tmp or 0)),
                    Back.BackValId((tag or "view_copy") .. ".len." .. tostring(ctx.next_tmp or 0)),
                    Back.BackValId((tag or "view_copy") .. ".stride." .. tostring(ctx.next_tmp or 0)),
                }
                load_scalar_at_offset(ctx, vals[1], src_base, (src_offset or 0), Code.CodeTyDataPtr(view_elem(ty)), tag or "view_copy_data")
                load_scalar_at_offset(ctx, vals[2], src_base, (src_offset or 0) + 8, Code.CodeTyIndex, tag or "view_copy_len")
                load_scalar_at_offset(ctx, vals[3], src_base, (src_offset or 0) + 16, Code.CodeTyIndex, tag or "view_copy_stride")
            end
            store_scalar_at_offset(ctx, dst_base, (dst_offset or 0), vals[1], Code.CodeTyDataPtr(view_elem(ty)), tag or "view_store_data")
            store_scalar_at_offset(ctx, dst_base, (dst_offset or 0) + 8, vals[2], Code.CodeTyIndex, tag or "view_store_len")
            store_scalar_at_offset(ctx, dst_base, (dst_offset or 0) + 16, vals[3], Code.CodeTyIndex, tag or "view_store_stride")
        elseif is_byref_aggregate_ty(ty) then
            local source = src_base
            if source == nil then
                if value == nil then error("code_to_back: aggregate copy has no source", 3) end
                source = source_aggregate_ptr(ctx, value)
            end
            copy_aggregate_from_ptr(ctx, dst_base, dst_offset or 0, source, ty, tag, src_offset or 0)
        else
            local v = value and bid(value) or (tmp or Back.BackValId((tag or "scalar_copy") .. ".tmp." .. tostring(ctx.next_tmp or 0)))
            if value == nil then load_scalar_at_offset(ctx, v, src_base, src_offset or 0, ty, tag or "scalar_copy") end
            store_scalar_at_offset(ctx, dst_base, dst_offset or 0, v, ty, tag)
        end
    end

    local function store_closure_descriptor(ctx, dst, ty, fn, ctx_ptr)
        local addr = create_aggregate_storage(ctx, dst, ty, "code_to_back.closure")
        local fn_ty = Code.CodeTyCodePtr(ty.sig)
        store_scalar_at_offset(ctx, addr, 0, fn, fn_ty, "closure_fn")
        store_scalar_at_offset(ctx, addr, 8, ctx_ptr, Code.CodeTyDataPtr(nil), "closure_ctx")
        return addr
    end

    local function closure_env_ptr(ctx, base_addr, has_captures)
        if not has_captures then return null_ptr(ctx, "code_to_back.closure_ctx_null") end
        local ptr = Back.BackValId("code_to_back.closure_ctx." .. tostring(ctx.next_tmp or 0))
        local idx0 = const_index(ctx, 0)
        ctx.cmds[#ctx.cmds + 1] = Back.CmdPtrOffset(ptr, Back.BackAddrValue(base_addr), idx0, 1, 16, Back.BackProvDerived("closure env"), Back.BackPtrInBounds("closure env"))
        return ptr
    end

    local function store_view_components_to_addr(ctx, base_addr, view, ty, tag)
        local elem = view_elem(ty)
        local data_ty = Code.CodeTyDataPtr(elem)
        local vals = component_values(view, ty)
        store_scalar_at_offset(ctx, base_addr, 0, vals[1], data_ty, (tag or "view") .. ":data")
        store_scalar_at_offset(ctx, base_addr, 8, vals[2], Code.CodeTyIndex, (tag or "view") .. ":len")
        store_scalar_at_offset(ctx, base_addr, 16, vals[3], Code.CodeTyIndex, (tag or "view") .. ":stride")
    end

    local function load_view_components_from_addr(ctx, view, base_addr, ty, tag)
        local elem = view_elem(ty)
        local data_ty = Code.CodeTyDataPtr(elem)
        local vals = component_values(view, ty)
        load_scalar_at_offset(ctx, vals[1], base_addr, 0, data_ty, (tag or "view") .. ":data")
        load_scalar_at_offset(ctx, vals[2], base_addr, 8, Code.CodeTyIndex, (tag or "view") .. ":len")
        load_scalar_at_offset(ctx, vals[3], base_addr, 16, Code.CodeTyIndex, (tag or "view") .. ":stride")
    end

    local function check_call_effects(ctx, inst_id)
        local effects = ctx.effect_by_inst and ctx.effect_by_inst[inst_id.text] or nil
        if effects == nil then return end
        for _, effect in ipairs(effects.effects or {}) do
            if pvm.classof(effect) == T.MoonEffect.EffectUnknown then
                -- Ordinary Code fallback may still emit conservative calls; the
                -- fact is consulted here so optimized fragment emitters can
                -- reject motion/vectorization before reaching Back.
                return
            end
        end
    end

    local function inst(ctx, i)
        local k = i.kind
        local cls = pvm.classof(k)
        if cls == Code.CodeInstConst then
            local s = scalar(k.const.ty); if s == nil then unsupported(k.const.ty) end
            ctx.cmds[#ctx.cmds + 1] = Back.CmdConst(bid(k.dst), s, const_literal(k.const))
        elseif cls == Code.CodeInstAlias then
            if is_view_ty(k.ty) then
                local dsts, srcs = component_values(k.dst, k.ty), component_values(k.src, k.ty)
                for n = 1, #dsts do ctx.cmds[#ctx.cmds + 1] = Back.CmdAlias(dsts[n], srcs[n]) end
            elseif is_byref_aggregate_ty(k.ty) then
                ctx.aggregate_value_addr[k.dst.text] = aggregate_addr_for_value(ctx, k.src, k.ty) or bid(k.src)
            else
                ctx.cmds[#ctx.cmds + 1] = Back.CmdAlias(bid(k.dst), bid(k.src))
            end
        elseif cls == Code.CodeInstUnary then
            local op = unary_op(k.op); if op == nil then unsupported(k.op) end
            ctx.cmds[#ctx.cmds + 1] = Back.CmdUnary(bid(k.dst), op, shape(k.ty), bid(k.value))
        elseif cls == Code.CodeInstBinary then
            local s = scalar(k.ty); if s == nil then unsupported(k.ty) end
            local iop, bop, sop = int_op(k.op), bit_op(k.op), shift_op(k.op)
            local lhs, rhs = value_as(ctx, k.lhs, k.ty), value_as(ctx, k.rhs, k.ty)
            if iop then ctx.cmds[#ctx.cmds + 1] = Back.CmdIntBinary(bid(k.dst), iop, s, int_semantics(ctx, k), lhs, rhs)
            elseif bop then ctx.cmds[#ctx.cmds + 1] = Back.CmdBitBinary(bid(k.dst), bop, s, lhs, rhs)
            elseif sop then ctx.cmds[#ctx.cmds + 1] = Back.CmdShift(bid(k.dst), sop, s, lhs, rhs)
            else unsupported(k.op) end
        elseif cls == Code.CodeInstFloatBinary then
            local s = scalar(k.ty); local op = float_op(k.op); if not s or not op then unsupported(k) end
            ctx.cmds[#ctx.cmds + 1] = Back.CmdFloatBinary(bid(k.dst), op, s, float_semantics(ctx, k), bid(k.lhs), bid(k.rhs))
        elseif cls == Code.CodeInstCompare then
            local lhs, rhs = value_as(ctx, k.lhs, k.operand_ty), value_as(ctx, k.rhs, k.operand_ty)
            ctx.cmds[#ctx.cmds + 1] = Back.CmdCompare(bid(k.dst), cmp_op(k.op, k.operand_ty), shape(k.operand_ty), lhs, rhs)
        elseif cls == Code.CodeInstCast then
            local s = scalar(k.to); if s == nil then unsupported(k.to) end
            ctx.cmds[#ctx.cmds + 1] = Back.CmdCast(bid(k.dst), cast_op(k.op), s, bid(k.value))
        elseif cls == Code.CodeInstIntrinsic then
            if k.op == Core.IntrinsicTrap then
                ctx.cmds[#ctx.cmds + 1] = Back.CmdTrap
            elseif k.op == Core.IntrinsicFma then
                local s = scalar(k.ty); if s == nil then unsupported(k.ty) end
                if k.dst == nil or #k.args ~= 3 then unsupported(k) end
                ctx.cmds[#ctx.cmds + 1] = Back.CmdFma(bid(k.dst), s, Back.BackFloatStrict, bid(k.args[1]), bid(k.args[2]), bid(k.args[3]))
            elseif rotate_op(k.op) ~= nil then
                local s = scalar(k.ty); if s == nil then unsupported(k.ty) end
                if k.dst == nil or #k.args ~= 2 then unsupported(k) end
                ctx.cmds[#ctx.cmds + 1] = Back.CmdRotate(bid(k.dst), rotate_op(k.op), s, bid(k.args[1]), bid(k.args[2]))
            else
                local op = intrinsic_op(k.op); if op == nil then unsupported(k.op) end
                local s = scalar(k.ty); if s == nil then unsupported(k.ty) end
                if k.dst == nil or #k.args < 1 then unsupported(k) end
                ctx.cmds[#ctx.cmds + 1] = Back.CmdIntrinsic(bid(k.dst), op, Back.BackShapeScalar(s), { bid(k.args[1]) })
            end
        elseif cls == Code.CodeInstSelect then
            ctx.cmds[#ctx.cmds + 1] = Back.CmdSelect(bid(k.dst), shape(k.ty), bid(k.cond), bid(k.then_value), bid(k.else_value))
        elseif cls == Code.CodeInstAddrOf then
            local pcls = pvm.classof(k.place)
            if pcls == Code.CodePlaceGlobal then ctx.cmds[#ctx.cmds + 1] = Back.CmdDataAddr(bid(k.dst), data_id(k.place.global))
            elseif pcls == Code.CodePlaceData then ctx.cmds[#ctx.cmds + 1] = Back.CmdDataAddr(bid(k.dst), data_id(k.place.data))
            else
                local addr = addr_from_place(ctx, k.place, ctx.mem_backend_by_inst[i.id.text])
                if pcls == Code.CodePlaceLocal and pvm.classof(addr.base) == Back.BackAddrStack and pvm.classof(addr.byte_offset) == Back.BackValId then
                    ctx.cmds[#ctx.cmds + 1] = Back.CmdStackAddr(bid(k.dst), addr.base.slot)
                else
                    local ptr = address_to_ptr_value(ctx, addr, "code_to_back.addr_of")
                    ctx.cmds[#ctx.cmds + 1] = Back.CmdAlias(bid(k.dst), ptr)
                end
            end
        elseif cls == Code.CodeInstGlobalRef then
            local rcls = pvm.classof(k.ref)
            if rcls == Code.CodeGlobalRefFunc then ctx.cmds[#ctx.cmds + 1] = Back.CmdFuncAddr(bid(k.dst), func_id(k.ref.func))
            elseif rcls == Code.CodeGlobalRefExtern then ctx.cmds[#ctx.cmds + 1] = Back.CmdExternAddr(bid(k.dst), extern_id(k.ref["extern"]))
            elseif rcls == Code.CodeGlobalRefData then ctx.cmds[#ctx.cmds + 1] = Back.CmdDataAddr(bid(k.dst), data_id(k.ref.data))
            elseif rcls == Code.CodeGlobalRefGlobal then ctx.cmds[#ctx.cmds + 1] = Back.CmdDataAddr(bid(k.dst), data_id(k.ref.global))
            else unsupported(k.ref) end
        elseif cls == Code.CodeInstPtrOffset then
            local index = index_value(ctx, k.index)
            ctx.cmds[#ctx.cmds + 1] = Back.CmdPtrOffset(bid(k.dst), Back.BackAddrValue(bid(k.base)), index, k.elem_size, k.const_offset, Back.BackProvDerived("CodePtrOffset"), Back.BackPtrBoundsUnknown)
        elseif cls == Code.CodeInstViewMake then
            -- Materialize executable descriptor components as deterministic SSA aliases.
            -- Projections alias from these component ids; if a view was not made in Code,
            -- Back validation fails loudly on the missing deterministic source value.
            ctx.cmds[#ctx.cmds + 1] = Back.CmdAlias(view_component_id(k.dst, "data"), bid(k.data))
            ctx.cmds[#ctx.cmds + 1] = Back.CmdAlias(view_component_id(k.dst, "len"), bid(k.len))
            ctx.cmds[#ctx.cmds + 1] = Back.CmdAlias(view_component_id(k.dst, "stride"), bid(k.stride))
        elseif cls == Code.CodeInstViewData then
            ctx.cmds[#ctx.cmds + 1] = Back.CmdAlias(bid(k.dst), view_component_id(k.view, "data"))
        elseif cls == Code.CodeInstViewLen then
            ctx.cmds[#ctx.cmds + 1] = Back.CmdAlias(bid(k.dst), view_component_id(k.view, "len"))
        elseif cls == Code.CodeInstViewStride then
            ctx.cmds[#ctx.cmds + 1] = Back.CmdAlias(bid(k.dst), view_component_id(k.view, "stride"))
        elseif cls == Code.CodeInstLoad then
            local addr = addr_from_place(ctx, k.place, ctx.mem_backend_by_inst[i.id.text])
            if is_byref_aggregate_ty(k.access.ty) then
                local p = address_to_ptr_value(ctx, addr, "code_to_back.aggregate_load_addr")
                ctx.cmds[#ctx.cmds + 1] = Back.CmdAlias(bid(k.dst), p)
                ctx.aggregate_value_addr[k.dst.text] = p
            elseif is_view_ty(k.access.ty) then
                local elem = view_elem(k.access.ty)
                local data_ty = Code.CodeTyDataPtr(elem)
                local vals = component_values(k.dst, k.access.ty)
                local data_addr = address_at_const_offset(ctx, addr, 0)
                local len_addr = address_at_const_offset(ctx, addr, 8)
                local stride_addr = address_at_const_offset(ctx, addr, 16)
                local data_mem = component_memory_info(ctx, k.access, i.id, "view_data")
                local len_mem = component_memory_info(ctx, k.access, i.id, "view_len")
                local stride_mem = component_memory_info(ctx, k.access, i.id, "view_stride")
                ctx.cmds[#ctx.cmds + 1] = Back.CmdLoadInfo(vals[1], shape(data_ty), data_addr, data_mem)
                ctx.cmds[#ctx.cmds + 1] = Back.CmdLoadInfo(vals[2], shape(Code.CodeTyIndex), len_addr, len_mem)
                ctx.cmds[#ctx.cmds + 1] = Back.CmdLoadInfo(vals[3], shape(Code.CodeTyIndex), stride_addr, stride_mem)
            else
                ctx.cmds[#ctx.cmds + 1] = Back.CmdLoadInfo(bid(k.dst), shape(k.access.ty), addr, memory_info(ctx, k.access, i.id))
            end
        elseif cls == Code.CodeInstAggregate then
            if pvm.classof(k.ty) == Code.CodeTyClosure then
                local size, align = closure_descriptor_size(ctx, k.fields)
                local addr = create_aggregate_storage(ctx, k.dst, k.ty, "code_to_back.closure", size, align)
                local fn = nil
                local captures = {}
                for _, field in ipairs(k.fields or {}) do
                    if pvm.classof(field.field) ~= T.MoonSem.FieldByOffset then unsupported(field.field) end
                    if field.field.field_name == "__moon_fn" then
                        fn = field.value
                    else
                        captures[#captures + 1] = field
                    end
                end
                if fn == nil then error("code_to_back: closure aggregate missing __moon_fn", 3) end
                store_scalar_at_offset(ctx, addr, 0, bid(fn), Code.CodeTyCodePtr(k.ty.sig), "closure_fn")
                store_scalar_at_offset(ctx, addr, 8, closure_env_ptr(ctx, addr, #captures > 0), Code.CodeTyDataPtr(nil), "closure_ctx")
                for _, field in ipairs(captures) do
                    local fty = ctx.value_types[field.value.text]
                    if fty == nil then error("code_to_back: closure capture value has unknown type " .. field.value.text, 3) end
                    copy_value_to_offset(ctx, addr, 16 + (field.field.offset or 0), field.value, fty, "closure_capture")
                end
            else
                local addr = create_aggregate_storage(ctx, k.dst, k.ty, "code_to_back.aggregate")
                for _, field in ipairs(k.fields or {}) do
                    if pvm.classof(field.field) ~= T.MoonSem.FieldByOffset then unsupported(field.field) end
                    local fty = ctx.value_types[field.value.text]
                    if fty == nil then error("code_to_back: aggregate field value has unknown type " .. field.value.text, 3) end
                    copy_value_to_offset(ctx, addr, field.field.offset or 0, field.value, fty, "aggregate_field")
                end
            end
        elseif cls == Code.CodeInstClosure then
            store_closure_descriptor(ctx, k.dst, k.ty, bid(k.fn), bid(k.ctx))
        elseif cls == Code.CodeInstArray then
            local addr = create_aggregate_storage(ctx, k.dst, k.ty, "code_to_back.array")
            local ty_cls = pvm.classof(k.ty)
            if ty_cls ~= Code.CodeTyArray then unsupported(k.ty) end
            local elem_s = scalar(k.ty.elem)
            local elem_size
            if elem_s ~= nil then
                elem_size = scalar_size_align(elem_s)
            else
                elem_size = aggregate_size_align(ctx, k.ty.elem)
            end
            for _, elem in ipairs(k.elems or {}) do
                local ety = ctx.value_types[elem.value.text] or k.ty.elem
                copy_value_to_offset(ctx, addr, (elem.index or 0) * elem_size, elem.value, ety, "array_elem")
            end
        elseif cls == Code.CodeInstVariantCtor then
            local addr = create_aggregate_storage(ctx, k.dst, k.ty, "code_to_back.variant")
            local tag_ty = Code.CodeTyInt(32, Code.CodeUnsigned)
            local tag_val = Back.BackValId(k.dst.text .. ":tag")
            ctx.cmds[#ctx.cmds + 1] = Back.CmdConst(tag_val, Back.BackU32, Back.BackLitInt(tostring(k.variant.tag_value)))
            store_scalar_at_offset(ctx, addr, 0, tag_val, tag_ty, "variant_tag")
            if k.payload ~= nil and k.variant.payload_ty ~= nil then
                local off = layout_field_offset(ctx, k.ty, "__payload") or 4
                local pty = ctx.value_types[k.payload.text] or k.variant.payload_ty
                store_scalar_at_offset(ctx, addr, off, bid(k.payload), pty, "variant_payload")
            end
        elseif cls == Code.CodeInstVariantTag then
            local addr = aggregate_addr_for_value(ctx, k.value, ctx.value_types[k.value.text])
            if addr == nil then error("code_to_back: variant tag source has no aggregate address " .. k.value.text, 3) end
            load_scalar_at_offset(ctx, k.dst and bid(k.dst) or Back.BackValId(k.value.text .. ":tag"), addr, 0, k.tag_ty, "variant_tag")
        elseif cls == Code.CodeInstVariantPayload then
            local owner_ty = ctx.value_types[k.value.text]
            local addr = aggregate_addr_for_value(ctx, k.value, owner_ty)
            if addr == nil then error("code_to_back: variant payload source has no aggregate address " .. k.value.text, 3) end
            local off = layout_field_offset(ctx, owner_ty, "__payload") or 4
            local pty = k.variant.payload_ty
            if pty == nil then error("code_to_back: variant payload has no payload type", 3) end
            load_scalar_at_offset(ctx, bid(k.dst), addr, off, pty, "variant_payload")
        elseif cls == Code.CodeInstStore then
            if pvm.classof(k.place) == Code.CodePlaceLocal and is_byref_aggregate_ty(k.access.ty) then
                ctx.aggregate_local_addr = ctx.aggregate_local_addr or {}
                ctx.aggregate_local_addr[k.place.local_id.text] = aggregate_addr_for_value(ctx, k.value, k.access.ty) or bid(k.value)
                note_value(ctx, inst_dst_type(ctx, k))
                return
            end
            local addr = addr_from_place(ctx, k.place, ctx.mem_backend_by_inst[i.id.text])
            if is_view_ty(k.access.ty) then
                local elem = view_elem(k.access.ty)
                local data_ty = Code.CodeTyDataPtr(elem)
                local vals = component_values(k.value, k.access.ty)
                local data_addr = address_at_const_offset(ctx, addr, 0)
                local len_addr = address_at_const_offset(ctx, addr, 8)
                local stride_addr = address_at_const_offset(ctx, addr, 16)
                local data_mem = component_memory_info(ctx, k.access, i.id, "view_data")
                local len_mem = component_memory_info(ctx, k.access, i.id, "view_len")
                local stride_mem = component_memory_info(ctx, k.access, i.id, "view_stride")
                ctx.cmds[#ctx.cmds + 1] = Back.CmdStoreInfo(shape(data_ty), data_addr, vals[1], data_mem)
                ctx.cmds[#ctx.cmds + 1] = Back.CmdStoreInfo(shape(Code.CodeTyIndex), len_addr, vals[2], len_mem)
                ctx.cmds[#ctx.cmds + 1] = Back.CmdStoreInfo(shape(Code.CodeTyIndex), stride_addr, vals[3], stride_mem)
            else
                ctx.cmds[#ctx.cmds + 1] = Back.CmdStoreInfo(shape(k.access.ty), addr, bid(k.value), memory_info(ctx, k.access, i.id))
            end
        elseif cls == Code.CodeInstAtomicLoad then
            local s = scalar(k.access.ty); if s == nil then unsupported(k.access.ty) end
            local addr = addr_from_place(ctx, k.place, ctx.mem_backend_by_inst[i.id.text])
            ctx.cmds[#ctx.cmds + 1] = Back.CmdAtomicLoad(bid(k.dst), s, addr, memory_info(ctx, k.access, i.id), atomic_ordering(k.ordering))
        elseif cls == Code.CodeInstAtomicStore then
            local s = scalar(k.access.ty); if s == nil then unsupported(k.access.ty) end
            local addr = addr_from_place(ctx, k.place, ctx.mem_backend_by_inst[i.id.text])
            ctx.cmds[#ctx.cmds + 1] = Back.CmdAtomicStore(s, addr, bid(k.value), memory_info(ctx, k.access, i.id), atomic_ordering(k.ordering))
        elseif cls == Code.CodeInstAtomicRmw then
            local s = scalar(k.access.ty); if s == nil then unsupported(k.access.ty) end
            local addr = addr_from_place(ctx, k.place, ctx.mem_backend_by_inst[i.id.text])
            ctx.cmds[#ctx.cmds + 1] = Back.CmdAtomicRmw(bid(k.dst), atomic_rmw_op(k.op), s, addr, bid(k.value), memory_info(ctx, k.access, i.id), atomic_ordering(k.ordering))
        elseif cls == Code.CodeInstAtomicCas then
            local s = scalar(k.access.ty); if s == nil then unsupported(k.access.ty) end
            local addr = addr_from_place(ctx, k.place, ctx.mem_backend_by_inst[i.id.text])
            ctx.cmds[#ctx.cmds + 1] = Back.CmdAtomicCas(bid(k.dst), s, addr, bid(k.expected), bid(k.replacement), memory_info(ctx, k.access, i.id), atomic_ordering(k.ordering))
        elseif cls == Code.CodeInstAtomicFence then
            ctx.cmds[#ctx.cmds + 1] = Back.CmdAtomicFence(atomic_ordering(k.ordering))
        elseif cls == Code.CodeInstCall then
            check_call_effects(ctx, i.id)
            local target_cls = pvm.classof(k.target)
            local target
            local call_sig = sig_id(k.sig)
            local closure_ctx = nil
            if target_cls == Code.CodeCallDirect then target = Back.BackCallDirect(func_id(k.target.func))
            elseif target_cls == Code.CodeCallExtern then target = Back.BackCallExtern(extern_id(k.target["extern"]))
            elseif target_cls == Code.CodeCallIndirect then target = Back.BackCallIndirect(bid(k.target.callee))
            elseif target_cls == Code.CodeCallClosure then
                local closure_ty = ctx.value_types[k.target.closure.text]
                local closure_addr = aggregate_addr_for_value(ctx, k.target.closure, closure_ty)
                if closure_addr == nil then error("code_to_back: closure call has no descriptor address " .. k.target.closure.text, 3) end
                local fn = Back.BackValId(k.target.closure.text .. ":closure_call_fn")
                closure_ctx = Back.BackValId(k.target.closure.text .. ":closure_call_ctx")
                load_scalar_at_offset(ctx, fn, closure_addr, 0, Code.CodeTyCodePtr(k.target.sig), "closure_call_fn")
                load_scalar_at_offset(ctx, closure_ctx, closure_addr, 8, Code.CodeTyDataPtr(nil), "closure_call_ctx")
                target = Back.BackCallIndirect(fn)
                call_sig = closure_sig_id(k.sig)
            else unsupported(k.target) end
            local sig = ctx.sigs[k.sig.text]
            local abi = ctx.sig_abi_by_sig and ctx.sig_abi_by_sig[k.sig.text] or sig_abi(ctx, sig)
            local result = Back.BackCallStmt
            local args = {}
            local sret_addr = nil
            if abi.sret then
                if k.dst == nil then error("code_to_back: aggregate-return call requires destination", 3) end
                sret_addr = create_aggregate_storage(ctx, k.dst, abi.result_ty, "code_to_back.call_result")
                args[#args + 1] = sret_addr
            elseif k.dst ~= nil then
                local s = sig and sig.results[1] and scalar(sig.results[1]) or nil
                if s == nil then unsupported(k) end
                result = Back.BackCallValue(bid(k.dst), s)
            end
            if closure_ctx ~= nil then args[#args + 1] = closure_ctx end
            for n = 1, #k.args do append_components(args, k.args[n], sig.params[n]) end
            ctx.cmds[#ctx.cmds + 1] = Back.CmdCall(result, target, call_sig, args)
            if sret_addr ~= nil and is_view_ty(abi.result_ty) then load_view_components_from_addr(ctx, k.dst, sret_addr, abi.result_ty, "code_to_back.call_view_result") end
        else
            unsupported(k)
        end
        note_value(ctx, inst_dst_type(ctx, k))
    end

    local function term(ctx, t)
        local k = t.kind
        local cls = pvm.classof(k)
        if cls == Code.CodeTermJump then
            local args = {}
            local dest_params = ctx.block_params[k.dest.text] or {}
            for i = 1, #k.args do append_components(args, k.args[i], dest_params[i] and dest_params[i].ty or ctx.value_types[k.args[i].text]) end
            ctx.cmds[#ctx.cmds + 1] = Back.CmdJump(block_id(k.dest), args)
        elseif cls == Code.CodeTermBranch then
            local ta, ea = {}, {}
            local then_params, else_params = ctx.block_params[k.then_dest.text] or {}, ctx.block_params[k.else_dest.text] or {}
            for i = 1, #k.then_args do append_components(ta, k.then_args[i], then_params[i] and then_params[i].ty or ctx.value_types[k.then_args[i].text]) end
            for i = 1, #k.else_args do append_components(ea, k.else_args[i], else_params[i] and else_params[i].ty or ctx.value_types[k.else_args[i].text]) end
            ctx.cmds[#ctx.cmds + 1] = Back.CmdBrIf(bid(k.cond), block_id(k.then_dest), ta, block_id(k.else_dest), ea)
        elseif cls == Code.CodeTermSwitch then
            if #(k.default_args or {}) ~= 0 then error("code_to_back: switch default args are not representable in Back CmdSwitchInt", 3) end
            local cases = {}
            for i = 1, #k.cases do
                if #(k.cases[i].args or {}) ~= 0 then error("code_to_back: switch case args are not representable in Back CmdSwitchInt", 3) end
                cases[i] = Back.BackSwitchCase(k.cases[i].literal.raw or tostring(k.cases[i].literal.value), block_id(k.cases[i].dest))
            end
            ctx.cmds[#ctx.cmds + 1] = Back.CmdSwitchInt(bid(k.value), Back.BackI32, cases, block_id(k.default_dest))
        elseif cls == Code.CodeTermVariantSwitch then
            if #(k.default_args or {}) ~= 0 then error("code_to_back: variant switch default args are not representable in Back CmdSwitchInt", 3) end
            local cases = {}
            for i = 1, #k.cases do
                if #(k.cases[i].args or {}) ~= 0 then error("code_to_back: variant switch case args are not representable in Back CmdSwitchInt", 3) end
                cases[i] = Back.BackSwitchCase(tostring(k.cases[i].variant.tag_value), block_id(k.cases[i].dest))
            end
            ctx.cmds[#ctx.cmds + 1] = Back.CmdSwitchInt(bid(k.tag), Back.BackI32, cases, block_id(k.default_dest))
        elseif cls == Code.CodeTermReturn then
            if #k.values == 0 then ctx.cmds[#ctx.cmds + 1] = Back.CmdReturnVoid
            else
                local rty = ctx.value_types[k.values[1].text]
                if ctx.current_return_sret ~= nil and is_view_ty(rty) then
                    store_view_components_to_addr(ctx, ctx.current_return_sret, k.values[1], rty, "code_to_back.view_return")
                    ctx.cmds[#ctx.cmds + 1] = Back.CmdReturnVoid
                elseif is_view_ty(rty) then
                    error("code_to_back: view return ABI requires sret lowering", 3)
                elseif ctx.current_return_sret ~= nil and is_byref_aggregate_ty(rty) then
                    local src = aggregate_addr_for_value(ctx, k.values[1], rty)
                    if src == nil then error("code_to_back: aggregate return value has no address " .. k.values[1].text, 3) end
                    if pvm.classof(rty) == Code.CodeTyClosure and (ctx.aggregate_value_size[k.values[1].text] or 16) > 16 then
                        error("code_to_back: returning captured closure descriptors requires a closure environment ownership model", 3)
                    end
                    local size = aggregate_size_align(ctx, rty)
                    local len = const_index(ctx, size)
                    ctx.cmds[#ctx.cmds + 1] = Back.CmdMemcpy(ctx.current_return_sret, src, len)
                    ctx.cmds[#ctx.cmds + 1] = Back.CmdReturnVoid
                else
                    ctx.cmds[#ctx.cmds + 1] = Back.CmdReturnValue(bid(k.values[1]))
                end
            end
        elseif cls == Code.CodeTermTrap or cls == Code.CodeTermUnreachable then
            ctx.cmds[#ctx.cmds + 1] = Back.CmdTrap
        else
            unsupported(k)
        end
    end

    local function func(ctx, f)
        ctx.value_types = {}
        ctx.block_params = {}
        ctx.aggregate_local_addr = {}
        ctx.aggregate_value_addr = {}
        ctx.aggregate_value_size = {}
        ctx.local_stack_slots = {}
        local fsig = ctx.sigs[f.sig.text]
        local fabi = ctx.sig_abi_by_sig and ctx.sig_abi_by_sig[f.sig.text] or (fsig and sig_abi(ctx, fsig))
        ctx.current_return_sret = fabi and fabi.sret and Back.BackValId("sret:" .. f.id.text) or nil
        for i = 1, #(f.params or {}) do note_value(ctx, f.params[i].value, f.params[i].ty) end
        for i = 1, #(f.blocks or {}) do
            ctx.block_params[f.blocks[i].id.text] = f.blocks[i].params or {}
            for j = 1, #(f.blocks[i].params or {}) do note_value(ctx, f.blocks[i].params[j].value, f.blocks[i].params[j].ty) end
        end
        ctx.cmds[#ctx.cmds + 1] = Back.CmdBeginFunc(func_id(f.id))
        materialize_addressed_locals(ctx, f.locals, true)
        for i = 1, #f.blocks do ctx.cmds[#ctx.cmds + 1] = Back.CmdCreateBlock(block_id(f.blocks[i].id)) end
        for i = 1, #f.blocks do
            local b = f.blocks[i]
            for j = 1, #b.params do
                local vals, shapes = component_values(b.params[j].value, b.params[j].ty), component_shapes(b.params[j].ty)
                for n = 1, #vals do ctx.cmds[#ctx.cmds + 1] = Back.CmdAppendBlockParam(block_id(b.id), vals[n], shapes[n]) end
            end
        end
        for i = 1, #f.blocks do
            local b = f.blocks[i]
            ctx.cmds[#ctx.cmds + 1] = Back.CmdSwitchToBlock(block_id(b.id))
            if b.id == f.entry then
                local params = {}
                if ctx.current_return_sret ~= nil then params[#params + 1] = ctx.current_return_sret end
                for j = 1, #f.params do append_components(params, f.params[j].value, f.params[j].ty) end
                ctx.cmds[#ctx.cmds + 1] = Back.CmdBindEntryParams(block_id(b.id), params)
            end
            for j = 1, #b.insts do inst(ctx, b.insts[j]) end
            term(ctx, b.term)
        end
        ctx.cmds[#ctx.cmds + 1] = Back.CmdFinishFunc(func_id(f.id))
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

    local function make_ctx(code_module, opts)
        opts = opts or {}
        local _, _, value, mem, effect = build_fact_context(code_module, opts)
        local ctx = { cmds = {}, sigs = {}, sig_abi_by_sig = {}, next_tmp = 0, mem_backend_by_inst = {}, value_int_semantics_by_value = {}, value_float_mode_by_value = {}, value_expr_by_value = {}, effect_by_inst = {}, readonly_inst = {}, aggregate_local_addr = {}, aggregate_value_addr = {}, aggregate_value_size = {}, local_stack_slots = {}, layout_env = opts.layout_env, target = opts.target }
        for i = 1, #(code_module.sigs or {}) do ctx.sigs[code_module.sigs[i].id.text] = code_module.sigs[i] end
        local backend_by_access, object_by_access, readonly_objects = {}, {}, {}
        for _, info in ipairs(mem and mem.backend_info or {}) do backend_by_access[info.access.text] = info end
        for _, interval in ipairs(mem and mem.intervals or {}) do object_by_access[interval.access.text] = interval.object end
        for _, eff in ipairs(mem and mem.effects or {}) do if pvm.classof(eff) == T.MoonMem.MemObjectReadonly then readonly_objects[eff.object.text] = true end end
        for _, access in ipairs(mem and mem.accesses or {}) do
            local info = backend_by_access[access.id.text]
            if info ~= nil and access.inst ~= nil then
                ctx.mem_backend_by_inst[access.inst.text] = info
                local obj = object_by_access[access.id.text]
                if obj ~= nil and readonly_objects[obj.text] and access.access.mode == Code.CodeMemoryRead then ctx.readonly_inst[access.inst.text] = true end
            end
        end
        local vindex = CodeValueFacts.expr_index(value)
        ctx.value_expr_by_value = vindex.expr_by_value
        ctx.value_int_semantics_by_value = vindex.no_wrap_by_value
        ctx.value_float_mode_by_value = vindex.float_mode_by_value
        for _, inst_effect in ipairs(effect and effect.insts or {}) do ctx.effect_by_inst[inst_effect.inst.text] = inst_effect end
        return ctx
    end

    local function emit_module_prelude(ctx, code_module)
        for i = 1, #(code_module.sigs or {}) do
            local s = code_module.sigs[i]
            local abi = sig_abi(ctx, s)
            ctx.sig_abi_by_sig[s.id.text] = abi
            ctx.cmds[#ctx.cmds + 1] = Back.CmdCreateSig(sig_id(s.id), abi.params, abi.results)
            local cabi = closure_abi(ctx, s)
            ctx.cmds[#ctx.cmds + 1] = Back.CmdCreateSig(closure_sig_id(s.id), cabi.params, cabi.results)
        end
        for i = 1, #(code_module.data or {}) do
            local d = code_module.data[i]
            ctx.cmds[#ctx.cmds + 1] = Back.CmdDeclareData(data_id(d.id), d.size, d.align)
            for j = 1, #d.inits do data_init(ctx, d.inits[j], data_id(d.id)) end
        end
        for i = 1, #(code_module.globals or {}) do
            local g = code_module.globals[i]
            ctx.cmds[#ctx.cmds + 1] = Back.CmdDeclareData(data_id(g.id), g.size or 8, g.align or 1)
            for j = 1, #g.inits do data_init(ctx, g.inits[j], data_id(g.id)) end
        end
        for i = 1, #(code_module.externs or {}) do ctx.cmds[#ctx.cmds + 1] = Back.CmdDeclareExtern(extern_id(code_module.externs[i].id), code_module.externs[i].symbol, sig_id(code_module.externs[i].sig)) end
    end

    local function function_declare(f)
        local vis = (f.linkage == Code.CodeLinkageExport) and Core.VisibilityExport or Core.VisibilityLocal
        return Back.CmdDeclareFunc(vis, func_id(f.id), sig_id(f.sig))
    end

    local function function_body_commands(code_module, f)
        local ctx = make_ctx(code_module)
        func(ctx, f)
        return ctx.cmds
    end

    local function blocks_for_cover(code_module, graph, cover)
        local cls = pvm.classof(cover)
        if cls == Lower.LowerCoverFunction then
            for _, f in ipairs(code_module.funcs or {}) do if f.id == cover.func then return f, f.blocks or {} end end
        elseif cls == Lower.LowerCoverBlock then
            for _, f in ipairs(code_module.funcs or {}) do
                if f.id == cover.func then
                    for _, b in ipairs(f.blocks or {}) do if b.id == cover.block then return f, { b } end end
                end
            end
        elseif cls == Lower.LowerCoverBlockRange then
            for _, f in ipairs(code_module.funcs or {}) do
                if f.id == cover.func then
                    local out, active = {}, false
                    for _, b in ipairs(f.blocks or {}) do
                        if b.id == cover.entry then active = true end
                        if active then out[#out + 1] = b end
                        if b.id == cover.exit then break end
                    end
                    return f, out
                end
            end
        elseif cls == Lower.LowerCoverLoop then
            local block_set, func_id = {}, nil
            for _, fg in ipairs(graph and graph.funcs or {}) do
                for _, loop in ipairs(fg.loops or {}) do
                    if loop.id == cover.loop then
                        func_id = fg.func
                        for _, bid in ipairs(loop.body or {}) do block_set[bid.block.text] = true end
                    end
                end
            end
            if func_id ~= nil then
                for _, f in ipairs(code_module.funcs or {}) do
                    if f.id == func_id then
                        local out = {}
                        for _, b in ipairs(f.blocks or {}) do if block_set[b.id.text] then out[#out + 1] = b end end
                        return f, out
                    end
                end
            end
        end
        error("code_to_back: unable to resolve LowerCover for fragment", 2)
    end

    local function fragment_commands(code_module, graph, flow, value, mem, effect, cover, opts)
        opts = opts or {}
        opts.graph, opts.flow, opts.value, opts.mem, opts.effect = graph, flow, value, mem, effect
        validate_module(code_module, opts)
        local ctx = make_ctx(code_module, opts)
        ctx.value_types = {}
        ctx.block_params = {}
        ctx.aggregate_local_addr = {}
        ctx.aggregate_value_addr = {}
        ctx.aggregate_value_size = {}
        ctx.local_stack_slots = {}
        local f, blocks = blocks_for_cover(code_module, graph or opts.graph or CodeGraph.graph(code_module), cover)
        local fsig = ctx.sigs[f.sig.text]
        local fabi = ctx.sig_abi_by_sig and ctx.sig_abi_by_sig[f.sig.text] or (fsig and sig_abi(ctx, fsig))
        ctx.current_return_sret = fabi and fabi.sret and Back.BackValId("sret:" .. f.id.text) or nil
        materialize_addressed_locals(ctx, f.locals, opts.emit_local_slots ~= false)
        local block_ord = {}
        for i, b in ipairs(f.blocks or {}) do block_ord[b.id.text] = i end
        local first_ord = 1
        if blocks and blocks[1] and block_ord[blocks[1].id.text] then first_ord = block_ord[blocks[1].id.text] end
        ctx.next_tmp = first_ord * 1000000
        for _, param in ipairs(f.params or {}) do note_value(ctx, param.value, param.ty) end
        for _, b in ipairs(f.blocks or {}) do
            ctx.block_params[b.id.text] = b.params or {}
            for _, param in ipairs(b.params or {}) do note_value(ctx, param.value, param.ty) end
            for _, i in ipairs(b.insts or {}) do
                local dst, ty = inst_dst_type(ctx, i.kind)
                note_value(ctx, dst, ty)
            end
        end
        for _, b in ipairs(blocks or {}) do
            ctx.cmds[#ctx.cmds + 1] = Back.CmdSwitchToBlock(block_id(b.id))
            if b.id == f.entry then
                local params = {}
                if ctx.current_return_sret ~= nil then params[#params + 1] = ctx.current_return_sret end
                for j = 1, #f.params do append_components(params, f.params[j].value, f.params[j].ty) end
                ctx.cmds[#ctx.cmds + 1] = Back.CmdBindEntryParams(block_id(b.id), params)
            end
            for _, i in ipairs(b.insts or {}) do inst(ctx, i) end
            term(ctx, b.term)
        end
        return ctx.cmds
    end

    local function module_prelude_commands(code_module, opts)
        opts = opts or {}
        validate_module(code_module, opts)
        local ctx = make_ctx(code_module, opts)
        emit_module_prelude(ctx, code_module)
        return ctx.cmds
    end

    local function function_local_stack_slot_commands(code_module, f, opts)
        opts = opts or {}
        local ctx = make_ctx(code_module, opts)
        ctx.local_stack_slots = {}
        materialize_addressed_locals(ctx, f.locals, true)
        return ctx.cmds
    end

    local function module(code_module, opts)
        opts = opts or {}
        validate_module(code_module, opts)
        local ctx = make_ctx(code_module, opts)
        emit_module_prelude(ctx, code_module)
        for i = 1, #(code_module.funcs or {}) do
            ctx.cmds[#ctx.cmds + 1] = function_declare(code_module.funcs[i])
        end
        for i = 1, #(code_module.funcs or {}) do
            func(ctx, code_module.funcs[i])
        end
        ctx.cmds[#ctx.cmds + 1] = Back.CmdFinalizeModule
        return Back.BackProgram(ctx.cmds)
    end

    api.module = module
    api.module_prelude_commands = module_prelude_commands
    api.function_local_stack_slot_commands = function_local_stack_slot_commands
    api.function_declare = function_declare
    api.function_body_commands = function_body_commands
    api.fragment_commands = fragment_commands
    api.scalar = scalar

    T._moonlift_api_cache.code_to_back = api
    return api
end

return bind_context