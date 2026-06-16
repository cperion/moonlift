local pvm = require("moonlift.pvm")

local M = {}

local function class_name(x)
    local cls = pvm.classof(x) or x
    return tostring(cls):match("Class%((.-)%)") or tostring(cls)
end

function M.Define(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.code_to_back ~= nil then return T._moonlift_api_cache.code_to_back end

    local Core = T.MoonCore
    local Code = T.MoonCode
    local Back = T.MoonBack
    local Lower = T.MoonLower
    local CodeValidate = require("moonlift.code_validate").Define(T)
    local CodeGraph = require("moonlift.code_graph").Define(T)
    local CodeFlowFacts = require("moonlift.code_flow_facts").Define(T)
    local CodeValueFacts = require("moonlift.code_value_facts").Define(T)
    local CodeMemFacts = require("moonlift.code_mem_facts").Define(T)
    local CodeEffectFacts = require("moonlift.code_effect_facts").Define(T)

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

    local function scalar(ty)
        if ty == Code.CodeTyVoid then return Back.BackVoid end
        if ty == Code.CodeTyBool8 then return Back.BackBool end
        if ty == Code.CodeTyIndex then return Back.BackIndex end
        local cls = pvm.classof(ty)
        if cls == Code.CodeTyInt then
            if ty.bits == 8 then return ty.signedness == Code.CodeSigned and Back.BackI8 or Back.BackU8 end
            if ty.bits == 16 then return ty.signedness == Code.CodeSigned and Back.BackI16 or Back.BackU16 end
            if ty.bits == 32 then return ty.signedness == Code.CodeSigned and Back.BackI32 or Back.BackU32 end
            if ty.bits == 64 then return ty.signedness == Code.CodeSigned and Back.BackI64 or Back.BackU64 end
        elseif cls == Code.CodeTyFloat then
            if ty.bits == 32 then return Back.BackF32 end
            if ty.bits == 64 then return Back.BackF64 end
        elseif cls == Code.CodeTyDataPtr or cls == Code.CodeTyCodePtr or cls == Code.CodeTyImportedCFuncPtr then
            return Back.BackPtr
        elseif cls == Code.CodeTyHandle then
            return scalar(ty.repr)
        elseif cls == Code.CodeTyLease then
            return scalar(ty.base)
        end
        return nil
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
        if cls == Core.LitNil then return Back.BackLitNull end
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

    local function address_at_const_offset(ctx, addr, offset)
        if offset == 0 then return addr end
        local ptr = Back.BackValId("code_to_back.view_addr." .. tostring(ctx.next_tmp or 0) .. "." .. tostring(offset))
        ctx.next_tmp = (ctx.next_tmp or 0) + 1
        ctx.cmds[#ctx.cmds + 1] = Back.CmdPtrOffset(ptr, addr.base, const_index(ctx, 0), 1, offset, addr.provenance, addr.formation_bounds)
        return Back.BackAddress(Back.BackAddrValue(ptr), zero(ctx), addr.provenance, addr.formation_bounds)
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
        if cls == Code.CodeInstSelect then return k.dst, k.ty end
        if cls == Code.CodeInstAddrOf then return k.dst, k.ptr_ty end
        if cls == Code.CodeInstGlobalRef then return k.dst, k.ptr_ty end
        if cls == Code.CodeInstPtrOffset then return k.dst, k.ptr_ty end
        if cls == Code.CodeInstLoad then return k.dst, k.access.ty end
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

    local function is_view_ty(ty)
        return pvm.classof(ty) == Code.CodeTyView or (pvm.classof(ty) == Code.CodeTyLease and is_view_ty(ty.base))
    end

    local function view_elem(ty)
        if pvm.classof(ty) == Code.CodeTyLease then ty = ty.base end
        return pvm.classof(ty) == Code.CodeTyView and ty.elem or nil
    end

    local function component_scalars(ty)
        if is_view_ty(ty) then return { Back.BackPtr, Back.BackIndex, Back.BackIndex } end
        local s = scalar(ty); if s == nil then unsupported(ty) end
        return { s }
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
        elseif cls == Code.CodeInstSelect then
            ctx.cmds[#ctx.cmds + 1] = Back.CmdSelect(bid(k.dst), shape(k.ty), bid(k.cond), bid(k.then_value), bid(k.else_value))
        elseif cls == Code.CodeInstAddrOf then
            local pcls = pvm.classof(k.place)
            if pcls == Code.CodePlaceGlobal then ctx.cmds[#ctx.cmds + 1] = Back.CmdDataAddr(bid(k.dst), data_id(k.place.global))
            elseif pcls == Code.CodePlaceData then ctx.cmds[#ctx.cmds + 1] = Back.CmdDataAddr(bid(k.dst), data_id(k.place.data))
            else unsupported(k.place) end
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
            if is_view_ty(k.access.ty) then
                local elem = view_elem(k.access.ty)
                local data_ty = Code.CodeTyDataPtr(elem)
                local vals = component_values(k.dst, k.access.ty)
                ctx.cmds[#ctx.cmds + 1] = Back.CmdLoadInfo(vals[1], shape(data_ty), address_at_const_offset(ctx, addr, 0), component_memory_info(ctx, k.access, i.id, "view_data"))
                ctx.cmds[#ctx.cmds + 1] = Back.CmdLoadInfo(vals[2], shape(Code.CodeTyIndex), address_at_const_offset(ctx, addr, 8), component_memory_info(ctx, k.access, i.id, "view_len"))
                ctx.cmds[#ctx.cmds + 1] = Back.CmdLoadInfo(vals[3], shape(Code.CodeTyIndex), address_at_const_offset(ctx, addr, 16), component_memory_info(ctx, k.access, i.id, "view_stride"))
            else
                ctx.cmds[#ctx.cmds + 1] = Back.CmdLoadInfo(bid(k.dst), shape(k.access.ty), addr, memory_info(ctx, k.access, i.id))
            end
        elseif cls == Code.CodeInstStore then
            local addr = addr_from_place(ctx, k.place, ctx.mem_backend_by_inst[i.id.text])
            if is_view_ty(k.access.ty) then
                local elem = view_elem(k.access.ty)
                local data_ty = Code.CodeTyDataPtr(elem)
                local vals = component_values(k.value, k.access.ty)
                ctx.cmds[#ctx.cmds + 1] = Back.CmdStoreInfo(shape(data_ty), address_at_const_offset(ctx, addr, 0), vals[1], component_memory_info(ctx, k.access, i.id, "view_data"))
                ctx.cmds[#ctx.cmds + 1] = Back.CmdStoreInfo(shape(Code.CodeTyIndex), address_at_const_offset(ctx, addr, 8), vals[2], component_memory_info(ctx, k.access, i.id, "view_len"))
                ctx.cmds[#ctx.cmds + 1] = Back.CmdStoreInfo(shape(Code.CodeTyIndex), address_at_const_offset(ctx, addr, 16), vals[3], component_memory_info(ctx, k.access, i.id, "view_stride"))
            else
                ctx.cmds[#ctx.cmds + 1] = Back.CmdStoreInfo(shape(k.access.ty), addr, bid(k.value), memory_info(ctx, k.access, i.id))
            end
        elseif cls == Code.CodeInstCall then
            check_call_effects(ctx, i.id)
            local target_cls = pvm.classof(k.target)
            local target
            if target_cls == Code.CodeCallDirect then target = Back.BackCallDirect(func_id(k.target.func))
            elseif target_cls == Code.CodeCallExtern then target = Back.BackCallExtern(extern_id(k.target["extern"]))
            elseif target_cls == Code.CodeCallIndirect then target = Back.BackCallIndirect(bid(k.target.callee))
            else unsupported(k.target) end
            local sig = ctx.sigs[k.sig.text]
            local result = Back.BackCallStmt
            if k.dst ~= nil then
                local s = sig and sig.results[1] and scalar(sig.results[1]) or nil
                if s == nil then unsupported(k) end
                result = Back.BackCallValue(bid(k.dst), s)
            end
            local args = {}
            for n = 1, #k.args do append_components(args, k.args[n], sig.params[n]) end
            ctx.cmds[#ctx.cmds + 1] = Back.CmdCall(result, target, sig_id(k.sig), args)
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
            local cases = {}
            for i = 1, #k.cases do cases[i] = Back.BackSwitchCase(k.cases[i].literal.raw or tostring(k.cases[i].literal.value), block_id(k.cases[i].dest)) end
            ctx.cmds[#ctx.cmds + 1] = Back.CmdSwitchInt(bid(k.value), Back.BackI32, cases, block_id(k.default_dest))
        elseif cls == Code.CodeTermReturn then
            if #k.values == 0 then ctx.cmds[#ctx.cmds + 1] = Back.CmdReturnVoid
            elseif is_view_ty(ctx.value_types[k.values[1].text]) then error("code_to_back: view return ABI is not implemented below Code", 3)
            else ctx.cmds[#ctx.cmds + 1] = Back.CmdReturnValue(bid(k.values[1])) end
        elseif cls == Code.CodeTermTrap or cls == Code.CodeTermUnreachable then
            ctx.cmds[#ctx.cmds + 1] = Back.CmdTrap
        else
            unsupported(k)
        end
    end

    local function func(ctx, f)
        ctx.value_types = {}
        ctx.block_params = {}
        for i = 1, #(f.params or {}) do note_value(ctx, f.params[i].value, f.params[i].ty) end
        for i = 1, #(f.blocks or {}) do
            ctx.block_params[f.blocks[i].id.text] = f.blocks[i].params or {}
            for j = 1, #(f.blocks[i].params or {}) do note_value(ctx, f.blocks[i].params[j].value, f.blocks[i].params[j].ty) end
        end
        ctx.cmds[#ctx.cmds + 1] = Back.CmdBeginFunc(func_id(f.id))
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
                local params = {}; for j = 1, #f.params do append_components(params, f.params[j].value, f.params[j].ty) end
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
        local ctx = { cmds = {}, sigs = {}, next_tmp = 0, mem_backend_by_inst = {}, value_int_semantics_by_value = {}, value_float_mode_by_value = {}, value_expr_by_value = {}, effect_by_inst = {}, readonly_inst = {} }
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
            local params, results = {}, {}
            for j = 1, #s.params do for _, bs in ipairs(component_scalars(s.params[j])) do params[#params + 1] = bs end end
            for j = 1, #s.results do
                if is_view_ty(s.results[j]) then error("code_to_back: view return signature ABI is not implemented below Code", 3) end
                for _, bs in ipairs(component_scalars(s.results[j])) do results[#results + 1] = bs end
            end
            ctx.cmds[#ctx.cmds + 1] = Back.CmdCreateSig(sig_id(s.id), params, results)
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
        local f, blocks = blocks_for_cover(code_module, graph or opts.graph or CodeGraph.graph(code_module), cover)
        for _, param in ipairs(f.params or {}) do note_value(ctx, param.value, param.ty) end
        for _, b in ipairs(f.blocks or {}) do
            ctx.block_params[b.id.text] = b.params or {}
            for _, param in ipairs(b.params or {}) do note_value(ctx, param.value, param.ty) end
        end
        for _, b in ipairs(blocks or {}) do
            ctx.cmds[#ctx.cmds + 1] = Back.CmdSwitchToBlock(block_id(b.id))
            if b.id == f.entry then
                local params = {}; for j = 1, #f.params do append_components(params, f.params[j].value, f.params[j].ty) end
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
    api.function_declare = function_declare
    api.function_body_commands = function_body_commands
    api.fragment_commands = fragment_commands
    api.scalar = scalar

    T._moonlift_api_cache.code_to_back = api
    return api
end

return M
