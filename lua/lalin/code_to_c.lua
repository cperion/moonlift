local pvm = require("lalin.pvm")

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s:match("^%d") then s = "_" .. s end
    if s == "" then s = "x" end
    return s
end

local function class_name(x)
    local cls = pvm.classof(x) or x
    return tostring(cls):match("Class%((.-)%)") or tostring(cls)
end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.code_to_c ~= nil then return T._lalin_api_cache.code_to_c end

    local Core = T.LalinCore
    local Sem = T.LalinSem
    local Code = T.LalinCode
    local C = T.LalinC

    local CodeType = require("lalin.code_type")(T)
    local CodeValidate = require("lalin.code_validate")(T)

    local api = {}

    local function c_name(text) return C.CBackendName(sanitize(text)) end
    local function c_label(id) return C.CBackendLabel(sanitize(id.text)) end
    local function c_local_id(id) return C.CBackendLocalId(sanitize(id.text)) end
    local function c_global_id(id) return C.CBackendGlobalId(sanitize(id.text)) end
    local function c_sig_id(id) return C.CBackendFuncSigId(sanitize(id.text)) end
    local function c_synth_local_id(prefix, id) return C.CBackendLocalId(sanitize(prefix .. ":" .. id.text)) end
    local function c_synth_local_id2(prefix, id, suffix) return C.CBackendLocalId(sanitize(prefix .. ":" .. id.text .. ":" .. suffix)) end

    local function add_helper(ctx, kind)
        local key = tostring(kind)
        ctx.helpers_by_key = ctx.helpers_by_key or {}
        local use = ctx.helpers_by_key[key]
        if use ~= nil then return use.id end
        local id = C.CBackendHelperId("ml_code_helper_" .. tostring(#ctx.helper_order + 1))
        use = C.CBackendHelperUse(id, kind)
        ctx.helpers_by_key[key] = use
        ctx.helpers_by_id[id.text] = use
        ctx.helper_order[#ctx.helper_order + 1] = use
        return id
    end

    local function c_ty(ctx, ty)
        return CodeType.code_type_to_c(ty, ctx.type_ctx)
    end

    local function c_type_id_key(id)
        return id.module_name .. "\0" .. id.spelling
    end

    local function variant_payload_union_id(owner_ty)
        if pvm.classof(owner_ty) ~= Code.CodeTyNamed then return nil end
        return C.CTypeId(owner_ty.module_name, owner_ty.type_name .. "_payload")
    end

    local function variant_payload_member_place(ctx, base_place, variant)
        local union_id = variant_payload_union_id(variant.owner_ty)
        local payload_union_ty = C.CBackendNamed(union_id)
        local payload_place = C.CBackendPlaceField(
            base_place,
            C.CBackendName("__payload"),
            payload_union_ty,
            0,
            nil,
            nil
        )
        return C.CBackendPlaceField(
            payload_place,
            C.CBackendName(variant.variant_name),
            c_ty(ctx, variant.payload_ty),
            0,
            nil,
            nil
        )
    end

    local function c_sig(ctx, sig_id)
        return c_sig_id(sig_id)
    end

    local function c_trap_mode(mode)
        if mode == Code.CodeMustNotTrap then return C.CBackendMustNotTrap end
        if mode == Code.CodeCheckedTrap then return C.CBackendCheckedTrap end
        return C.CBackendMayTrap
    end

    local function c_access(ctx, access)
        return C.CBackendMemoryAccess(c_ty(ctx, access.ty), access.align, c_trap_mode(access.trap), access.volatile, access.ordering)
    end

    local function is_pointer_c_ty(ty)
        local cls = pvm.classof(ty)
        return cls == C.CBackendDataPtr
            or cls == C.CBackendCodePtr
            or cls == C.CBackendImportedCodePtr
            or cls == C.CBackendAbiHiddenOutPtr
            or cls == C.CBackendSliceDescriptor
            or cls == C.CBackendViewDescriptor
            or cls == C.CBackendClosureDescriptor
    end

    local function is_zero_literal(lit)
        local cls = pvm.classof(lit)
        return cls == Core.LitInt and tostring(lit.raw) == "0"
    end

    local function is_nullish_const_atom(a)
        local cls = pvm.classof(a)
        if cls == C.CBackendAtomNull then return true end
        if cls == C.CBackendAtomLiteral then return is_zero_literal(a.literal) end
        return false
    end

    local function field_name(field)
        local cls = pvm.classof(field)
        if cls == Sem.FieldByName or cls == Sem.FieldByOffset then return field.field_name end
        return "field"
    end

    local function atom(id)
        return C.CBackendAtomLocal(c_local_id(id))
    end

    local function view_type(ctx, id)
        local ty = ctx.value_types and id and ctx.value_types[id.text] or nil
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

    local function slice_type(ctx, id)
        local ty = ctx.value_types and id and ctx.value_types[id.text] or nil
        if pvm.classof(ty) == Code.CodeTyLease then ty = ty.base end
        return ty
    end

    local function slice_elem_type(ctx, id)
        local ty = slice_type(ctx, id)
        if pvm.classof(ty) == Code.CodeTySlice then return ty.elem end
        return nil
    end

    local function slice_data_type(ctx, id)
        return Code.CodeTyDataPtr(slice_elem_type(ctx, id))
    end

    local function byte_ty()
        return Code.CodeTyInt(8, Code.CodeUnsigned)
    end

    local function const_atom(ctx, const)
        local cls = pvm.classof(const)
        if cls == Code.CodeConstLiteral then return C.CBackendAtomLiteral(c_ty(ctx, const.ty), const.literal) end
        if cls == Code.CodeConstNull then return C.CBackendAtomNull(c_ty(ctx, const.ty)) end
        if cls == Code.CodeConstUndef then return C.CBackendAtomLiteral(c_ty(ctx, const.ty), Core.LitInt("0")) end
        error("code_to_c: unsupported const " .. class_name(const), 2)
    end

    local place_to_c
    place_to_c = function(ctx, place)
        local cls = pvm.classof(place)
        if cls == Code.CodePlaceLocal then
            return C.CBackendPlaceLocal(c_local_id(place.local_id), c_ty(ctx, place.ty))
        elseif cls == Code.CodePlaceGlobal then
            return C.CBackendPlaceGlobal(c_global_id(place.global), c_ty(ctx, place.ty))
        elseif cls == Code.CodePlaceData then
            return C.CBackendPlaceGlobal(c_global_id(place.data), c_ty(ctx, place.ty))
        elseif cls == Code.CodePlaceDeref then
            return C.CBackendPlaceDeref(atom(place.addr), c_ty(ctx, place.ty), place.align)
        elseif cls == Code.CodePlaceField then
            return C.CBackendPlaceField(place_to_c(ctx, place.base), C.CBackendName(field_name(place.field)), c_ty(ctx, place.ty), place.offset, place.size, place.align)
        elseif cls == Code.CodePlaceIndex then
            return C.CBackendPlaceIndex(place_to_c(ctx, place.base), atom(place.index), c_ty(ctx, place.ty), place.elem_size)
        elseif cls == Code.CodePlaceBytes then
            return C.CBackendPlaceBytes(atom(place.base), place.offset, c_ty(ctx, place.ty), place.size, place.align)
        end
        error("code_to_c: unsupported place " .. class_name(place), 2)
    end

    local function atomic_place_addr_stmts(ctx, inst_id, place, suffix)
        if pvm.classof(place) == Code.CodePlaceDeref then return {}, atom(place.addr) end
        local addr = c_synth_local_id2("atomic_addr", inst_id, suffix or "place")
        return { C.CBackendAssign(addr, C.CBackendRAddrOfPlace(place_to_c(ctx, place))) }, C.CBackendAtomLocal(addr)
    end

    local function code_func_name(ctx, id)
        local f = ctx.funcs[id.text]
        if f == nil then error("code_to_c: missing function " .. tostring(id.text), 2) end
        return c_name(f.name)
    end

    local function code_extern_name(ctx, id)
        local e = ctx.externs[id.text]
        if e == nil then error("code_to_c: missing extern " .. tostring(id.text), 2) end
        return c_name(e.name)
    end

    local function global_ref_name(ctx, ref)
        local cls = pvm.classof(ref)
        if cls == Code.CodeGlobalRefFunc then return code_func_name(ctx, ref.func) end
        if cls == Code.CodeGlobalRefExtern then return code_extern_name(ctx, ref["extern"]) end
        if cls == Code.CodeGlobalRefGlobal then return c_name(ref.global.text) end
        if cls == Code.CodeGlobalRefData then return c_name(ref.data.text) end
        return c_name("global")
    end

    local function global_ref_sig(ctx, ref)
        local cls = pvm.classof(ref)
        if cls == Code.CodeGlobalRefFunc then
            local f = ctx.funcs[ref.func.text]
            if f == nil then error("code_to_c: missing function ref " .. tostring(ref.func.text), 2) end
            return c_sig(ctx, f.sig)
        elseif cls == Code.CodeGlobalRefExtern then
            local e = ctx.externs[ref["extern"].text]
            if e == nil then error("code_to_c: missing extern ref " .. tostring(ref["extern"].text), 2) end
            return c_sig(ctx, e.sig)
        end
        error("code_to_c: non-code global ref has no function signature " .. class_name(ref), 2)
    end

    local function binary_helper_kind(ctx, k)
        local ty = c_ty(ctx, k.ty)
        if k.op == Core.BinDiv or k.op == Core.BinRem then
            local mode = (k.semantics and k.semantics.div == Code.CodeDivTrapOnZeroOrOverflow) and C.CBackendDivTrapOnZeroOrOverflow or C.CBackendDivTrapOnZero
            return C.CBackendHelperDivRem(k.op, ty, mode)
        elseif k.op == Core.BinShl or k.op == Core.BinLShr or k.op == Core.BinAShr then
            local mode = (k.semantics and k.semantics.shift == Code.CodeShiftTrapOutOfRange) and C.CBackendShiftTrapOutOfRange or C.CBackendShiftMaskCount
            return C.CBackendHelperShift(k.op, ty, mode)
        else
            local overflow = C.CBackendIntWrap
            if k.semantics and k.semantics.overflow == Code.CodeIntTrapOnOverflow then overflow = C.CBackendIntTrapOnOverflow end
            if k.semantics and pvm.classof(k.semantics.overflow) == Code.CodeIntAssumeNoOverflow then overflow = C.CBackendIntAssumeNoOverflow end
            return C.CBackendHelperIntBinary(k.op, ty, overflow)
        end
    end

    local function inst_to_stmts(ctx, inst)
        local k = inst.kind
        local cls = pvm.classof(k)
        if cls == Code.CodeInstConst then
            local a = const_atom(ctx, k.const)
            ctx.const_atoms[k.dst.text] = a
            return { C.CBackendAssign(c_local_id(k.dst), C.CBackendRAtom(a)) }
        elseif cls == Code.CodeInstAlias then
            ctx.const_atoms[k.dst.text] = ctx.const_atoms[k.src.text]
            return { C.CBackendAssign(c_local_id(k.dst), C.CBackendRAtom(atom(k.src))) }
        elseif cls == Code.CodeInstUnary then
            local helper = add_helper(ctx, C.CBackendHelperUnary(k.op, c_ty(ctx, k.ty)))
            return { C.CBackendHelperCall(c_local_id(k.dst), helper, { atom(k.value) }) }
        elseif cls == Code.CodeInstBinary then
            local helper = add_helper(ctx, binary_helper_kind(ctx, k))
            return { C.CBackendHelperCall(c_local_id(k.dst), helper, { atom(k.lhs), atom(k.rhs) }) }
        elseif cls == Code.CodeInstFloatBinary then
            local helper = add_helper(ctx, C.CBackendHelperIntBinary(k.op, c_ty(ctx, k.ty), C.CBackendIntWrap))
            return { C.CBackendHelperCall(c_local_id(k.dst), helper, { atom(k.lhs), atom(k.rhs) }) }
        elseif cls == Code.CodeInstCompare then
            return { C.CBackendAssign(c_local_id(k.dst), C.CBackendRCompare(k.op, c_ty(ctx, k.operand_ty), atom(k.lhs), atom(k.rhs))) }
        elseif cls == Code.CodeInstCast then
            local to_ty = c_ty(ctx, k.to)
            local source_const = ctx.const_atoms[k.value.text]
            if is_pointer_c_ty(to_ty) and source_const ~= nil and is_nullish_const_atom(source_const) then
                ctx.const_atoms[k.dst.text] = C.CBackendAtomNull(to_ty)
                return { C.CBackendAssign(c_local_id(k.dst), C.CBackendRAtom(C.CBackendAtomNull(to_ty))) }
            end
            ctx.const_atoms[k.dst.text] = nil
            return { C.CBackendAssign(c_local_id(k.dst), C.CBackendRCast(k.op, to_ty, atom(k.value))) }
        elseif cls == Code.CodeInstSelect then
            return { C.CBackendAssign(c_local_id(k.dst), C.CBackendRSelect(c_ty(ctx, k.ty), atom(k.cond), atom(k.then_value), atom(k.else_value))) }
        elseif cls == Code.CodeInstIntrinsic then
            local helper = add_helper(ctx, C.CBackendHelperIntrinsic(k.op, c_ty(ctx, k.ty)))
            local args = {}; for i = 1, #k.args do args[i] = atom(k.args[i]) end
            return { C.CBackendHelperCall(k.dst and c_local_id(k.dst) or nil, helper, args) }
        elseif cls == Code.CodeInstAddrOf then
            return { C.CBackendAssign(c_local_id(k.dst), C.CBackendRAddrOfPlace(place_to_c(ctx, k.place))) }
        elseif cls == Code.CodeInstGlobalRef then
            local rcls = pvm.classof(k.ref)
            if rcls == Code.CodeGlobalRefFunc then
                return { C.CBackendAssign(c_local_id(k.dst), C.CBackendRFuncAddr(global_ref_name(ctx, k.ref), global_ref_sig(ctx, k.ref))) }
            elseif rcls == Code.CodeGlobalRefExtern then
                return { C.CBackendAssign(c_local_id(k.dst), C.CBackendRExternAddr(global_ref_name(ctx, k.ref), global_ref_sig(ctx, k.ref))) }
            else
                return { C.CBackendAssign(c_local_id(k.dst), C.CBackendRAtom(C.CBackendAtomGlobal(c_global_id(k.ref.global or k.ref.data)))) }
            end
        elseif cls == Code.CodeInstPtrOffset then
            return { C.CBackendAssign(c_local_id(k.dst), C.CBackendRPtrOffset(atom(k.base), atom(k.index), k.elem_size, k.const_offset)) }
        elseif cls == Code.CodeInstLoad then
            return { C.CBackendPlaceLoad(c_local_id(k.dst), place_to_c(ctx, k.place)) }
        elseif cls == Code.CodeInstStore then
            return { C.CBackendPlaceStore(place_to_c(ctx, k.place), atom(k.value)) }
        elseif cls == Code.CodeInstAggregate then
            local fields = {}
            for i = 1, #k.fields do fields[i] = C.CBackendAggregateFieldInit(C.CBackendName(field_name(k.fields[i].field)), atom(k.fields[i].value), nil) end
            return { C.CBackendAggregateInit(C.CBackendPlaceLocal(c_local_id(k.dst), c_ty(ctx, k.ty)), c_ty(ctx, k.ty), fields) }
        elseif cls == Code.CodeInstArray then
            local elems = {}; for i = 1, #k.elems do elems[i] = C.CBackendArrayElemInit(k.elems[i].index, atom(k.elems[i].value)) end
            return { C.CBackendArrayInit(C.CBackendPlaceLocal(c_local_id(k.dst), c_ty(ctx, k.ty)), c_ty(ctx, k.ty), elems) }
        elseif cls == Code.CodeInstViewMake then
            return { C.CBackendAggregateInit(C.CBackendPlaceLocal(c_local_id(k.dst), c_ty(ctx, Code.CodeTyView(k.elem_ty))), c_ty(ctx, Code.CodeTyView(k.elem_ty)), {
                C.CBackendAggregateFieldInit(C.CBackendName("data"), atom(k.data), 0),
                C.CBackendAggregateFieldInit(C.CBackendName("len"), atom(k.len), nil),
                C.CBackendAggregateFieldInit(C.CBackendName("stride"), atom(k.stride), nil),
            }) }
        elseif cls == Code.CodeInstViewData then
            return { C.CBackendPlaceLoad(c_local_id(k.dst), C.CBackendPlaceField(C.CBackendPlaceLocal(c_local_id(k.view), c_ty(ctx, view_type(ctx, k.view))), C.CBackendName("data"), c_ty(ctx, view_data_type(ctx, k.view)), 0, nil, nil)) }
        elseif cls == Code.CodeInstViewLen then
            return { C.CBackendPlaceLoad(c_local_id(k.dst), C.CBackendPlaceField(C.CBackendPlaceLocal(c_local_id(k.view), c_ty(ctx, view_type(ctx, k.view))), C.CBackendName("len"), C.CBackendIndex, 0, nil, nil)) }
        elseif cls == Code.CodeInstViewStride then
            return { C.CBackendPlaceLoad(c_local_id(k.dst), C.CBackendPlaceField(C.CBackendPlaceLocal(c_local_id(k.view), c_ty(ctx, view_type(ctx, k.view))), C.CBackendName("stride"), C.CBackendIndex, 0, nil, nil)) }
        elseif cls == Code.CodeInstSliceMake then
            return { C.CBackendAggregateInit(C.CBackendPlaceLocal(c_local_id(k.dst), c_ty(ctx, Code.CodeTySlice(k.elem_ty))), c_ty(ctx, Code.CodeTySlice(k.elem_ty)), {
                C.CBackendAggregateFieldInit(C.CBackendName("data"), atom(k.data), 0),
                C.CBackendAggregateFieldInit(C.CBackendName("len"), atom(k.len), nil),
            }) }
        elseif cls == Code.CodeInstSliceData then
            return { C.CBackendPlaceLoad(c_local_id(k.dst), C.CBackendPlaceField(C.CBackendPlaceLocal(c_local_id(k.slice), c_ty(ctx, slice_type(ctx, k.slice))), C.CBackendName("data"), c_ty(ctx, slice_data_type(ctx, k.slice)), 0, nil, nil)) }
        elseif cls == Code.CodeInstSliceLen then
            return { C.CBackendPlaceLoad(c_local_id(k.dst), C.CBackendPlaceField(C.CBackendPlaceLocal(c_local_id(k.slice), c_ty(ctx, slice_type(ctx, k.slice))), C.CBackendName("len"), C.CBackendIndex, 0, nil, nil)) }
        elseif cls == Code.CodeInstByteSpanMake then
            return { C.CBackendAggregateInit(C.CBackendPlaceLocal(c_local_id(k.dst), c_ty(ctx, Code.CodeTyByteSpan)), c_ty(ctx, Code.CodeTyByteSpan), {
                C.CBackendAggregateFieldInit(C.CBackendName("data"), atom(k.data), 0),
                C.CBackendAggregateFieldInit(C.CBackendName("len"), atom(k.len), nil),
            }) }
        elseif cls == Code.CodeInstByteSpanData then
            return { C.CBackendPlaceLoad(c_local_id(k.dst), C.CBackendPlaceField(C.CBackendPlaceLocal(c_local_id(k.span), c_ty(ctx, Code.CodeTyByteSpan)), C.CBackendName("data"), c_ty(ctx, Code.CodeTyDataPtr(byte_ty())), 0, nil, nil)) }
        elseif cls == Code.CodeInstByteSpanLen then
            return { C.CBackendPlaceLoad(c_local_id(k.dst), C.CBackendPlaceField(C.CBackendPlaceLocal(c_local_id(k.span), c_ty(ctx, Code.CodeTyByteSpan)), C.CBackendName("len"), C.CBackendIndex, 0, nil, nil)) }
        elseif cls == Code.CodeInstClosure then
            return { C.CBackendAggregateInit(C.CBackendPlaceLocal(c_local_id(k.dst), c_ty(ctx, k.ty)), c_ty(ctx, k.ty), {
                C.CBackendAggregateFieldInit(C.CBackendName("fn"), atom(k.fn), 0),
                C.CBackendAggregateFieldInit(C.CBackendName("ctx"), atom(k.ctx), nil),
            }) }
        elseif cls == Code.CodeInstVariantCtor then
            local dst_place = C.CBackendPlaceLocal(c_local_id(k.dst), c_ty(ctx, k.ty))
            local out = {
                C.CBackendAggregateInit(dst_place, c_ty(ctx, k.ty), {
                    C.CBackendAggregateFieldInit(C.CBackendName("__tag"), C.CBackendAtomLiteral(C.CBackendScalar(Core.ScalarU32), Core.LitInt(tostring(k.variant.tag_value))), 0),
                })
            }
            if k.payload ~= nil then
                out[#out + 1] = C.CBackendPlaceStore(variant_payload_member_place(ctx, dst_place, k.variant), atom(k.payload))
            end
            return out
        elseif cls == Code.CodeInstVariantTag then
            return { C.CBackendPlaceLoad(c_local_id(k.dst), C.CBackendPlaceField(C.CBackendPlaceLocal(c_local_id(k.value), c_ty(ctx, k.variant and k.variant.owner_ty or Code.CodeTyVoid)), C.CBackendName("__tag"), c_ty(ctx, k.tag_ty), 0, nil, nil)) }
        elseif cls == Code.CodeInstVariantPayload then
            return { C.CBackendPlaceLoad(c_local_id(k.dst), variant_payload_member_place(ctx, C.CBackendPlaceLocal(c_local_id(k.value), c_ty(ctx, k.variant.owner_ty)), k.variant)) }
        elseif cls == Code.CodeInstCall then
            local args = {}; for i = 1, #k.args do args[i] = atom(k.args[i]) end
            local tcls = pvm.classof(k.target)
            local target
            if tcls == Code.CodeCallDirect then target = C.CBackendCallDirect(code_func_name(ctx, k.target.func))
            elseif tcls == Code.CodeCallExtern then target = C.CBackendCallExtern(code_extern_name(ctx, k.target["extern"]))
            elseif tcls == Code.CodeCallIndirect then target = C.CBackendCallIndirect(atom(k.target.callee), c_sig(ctx, k.target.sig))
            elseif tcls == Code.CodeCallClosure then target = C.CBackendCallClosure(atom(k.target.closure), c_sig(ctx, k.target.sig))
            else error("code_to_c: unsupported call target " .. class_name(k.target), 2) end
            return { C.CBackendCall(k.dst and c_local_id(k.dst) or nil, target, args) }
        elseif cls == Code.CodeInstAtomicLoad then
            local helper = add_helper(ctx, C.CBackendHelperAtomicLoad(c_access(ctx, k.access)))
            local stmts, addr = atomic_place_addr_stmts(ctx, inst.id, k.place, "load")
            stmts[#stmts + 1] = C.CBackendHelperCall(c_local_id(k.dst), helper, { addr })
            return stmts
        elseif cls == Code.CodeInstAtomicStore then
            local helper = add_helper(ctx, C.CBackendHelperAtomicStore(c_access(ctx, k.access)))
            local stmts, addr = atomic_place_addr_stmts(ctx, inst.id, k.place, "store")
            stmts[#stmts + 1] = C.CBackendHelperCall(nil, helper, { addr, atom(k.value) })
            return stmts
        elseif cls == Code.CodeInstAtomicRmw then
            local helper = add_helper(ctx, C.CBackendHelperAtomicRmw(k.op, c_access(ctx, k.access)))
            local stmts, addr = atomic_place_addr_stmts(ctx, inst.id, k.place, "rmw")
            stmts[#stmts + 1] = C.CBackendHelperCall(c_local_id(k.dst), helper, { addr, atom(k.value) })
            return stmts
        elseif cls == Code.CodeInstAtomicCas then
            local expected_addr = c_synth_local_id("atomic_cas_expected_addr", inst.id)
            local helper = add_helper(ctx, C.CBackendHelperAtomicCas(c_access(ctx, k.access), k.ordering, k.ordering))
            local stmts, addr = atomic_place_addr_stmts(ctx, inst.id, k.place, "cas")
            stmts[#stmts + 1] =
                C.CBackendAssign(expected_addr, C.CBackendRAddrOfPlace(C.CBackendPlaceLocal(c_local_id(k.expected), c_ty(ctx, k.access.ty))))
            stmts[#stmts + 1] = C.CBackendHelperCall(c_local_id(k.dst), helper, { addr, C.CBackendAtomLocal(expected_addr), atom(k.replacement) })
            return stmts
        elseif cls == Code.CodeInstAtomicFence then
            local helper = add_helper(ctx, C.CBackendHelperAtomicFence(k.ordering))
            return { C.CBackendHelperCall(nil, helper, {}) }
        end
        error("code_to_c: unsupported CodeInstKind " .. class_name(k), 2)
    end

    local function term_to_c(ctx, term)
        local k = term.kind
        local cls = pvm.classof(k)
        if cls == Code.CodeTermJump then
            local args = {}; for i = 1, #k.args do args[i] = atom(k.args[i]) end
            return C.CBackendGoto(c_label(k.dest), args)
        elseif cls == Code.CodeTermBranch then
            local then_args = {}; for i = 1, #k.then_args do then_args[i] = atom(k.then_args[i]) end
            local else_args = {}; for i = 1, #k.else_args do else_args[i] = atom(k.else_args[i]) end
            return C.CBackendIfGoto(atom(k.cond), c_label(k.then_dest), then_args, c_label(k.else_dest), else_args)
        elseif cls == Code.CodeTermSwitch then
            local cases = {}; for i = 1, #k.cases do local c = k.cases[i]; local args = {}; for j = 1, #c.args do args[j] = atom(c.args[j]) end; cases[i] = C.CBackendSwitchCase(c.literal, c_label(c.dest), args) end
            local default_args = {}; for i = 1, #k.default_args do default_args[i] = atom(k.default_args[i]) end
            return C.CBackendSwitchGoto(atom(k.value), cases, c_label(k.default_dest), default_args)
        elseif cls == Code.CodeTermVariantSwitch then
            local cases = {}; for i = 1, #k.cases do local c = k.cases[i]; local args = {}; for j = 1, #c.args do args[j] = atom(c.args[j]) end; cases[i] = C.CBackendSwitchCase(Core.LitInt(tostring(c.variant.tag_value)), c_label(c.dest), args) end
            local default_args = {}; for i = 1, #k.default_args do default_args[i] = atom(k.default_args[i]) end
            return C.CBackendSwitchGoto(atom(k.tag), cases, c_label(k.default_dest), default_args)
        elseif cls == Code.CodeTermReturn then
            if #k.values == 0 then return C.CBackendReturnVoid end
            return C.CBackendReturn(atom(k.values[1]))
        elseif cls == Code.CodeTermTrap or cls == Code.CodeTermUnreachable then
            return C.CBackendTrap
        end
        error("code_to_c: unsupported CodeTermKind " .. class_name(k), 2)
    end

    local function collect_value_locals(ctx, func)
        local out, seen = {}, {}
        local function add(id, ty)
            if id ~= nil and ty ~= nil then ctx.value_types[id.text] = ty end
            if id == nil or seen[id.text] or ctx.param_values[id.text] then return end
            seen[id.text] = true
            out[#out + 1] = C.CBackendLocal(c_local_id(id), c_name(id.text), c_ty(ctx, ty))
        end
        for i = 1, #(func.locals or {}) do add(func.locals[i].id, func.locals[i].ty) end
        for i = 1, #(func.blocks or {}) do
            local b = func.blocks[i]
            for j = 1, #(b.insts or {}) do
                local k = b.insts[j].kind
                local cls = pvm.classof(k)
                if cls == Code.CodeInstConst then add(k.dst, k.const.ty)
                elseif cls == Code.CodeInstAlias then add(k.dst, k.ty)
                elseif cls == Code.CodeInstUnary or cls == Code.CodeInstBinary or cls == Code.CodeInstFloatBinary or cls == Code.CodeInstSelect or cls == Code.CodeInstIntrinsic then add(k.dst, k.ty)
                elseif cls == Code.CodeInstCompare then add(k.dst, Code.CodeTyBool8)
                elseif cls == Code.CodeInstCast then add(k.dst, k.to)
                elseif cls == Code.CodeInstAddrOf or cls == Code.CodeInstGlobalRef or cls == Code.CodeInstPtrOffset then add(k.dst, k.ptr_ty)
                elseif cls == Code.CodeInstLoad then add(k.dst, k.access.ty)
                elseif cls == Code.CodeInstAggregate or cls == Code.CodeInstArray or cls == Code.CodeInstClosure or cls == Code.CodeInstVariantCtor then add(k.dst, k.ty)
                elseif cls == Code.CodeInstViewMake then add(k.dst, Code.CodeTyView(k.elem_ty))
                elseif cls == Code.CodeInstViewData then add(k.dst, view_data_type(ctx, k.view))
                elseif cls == Code.CodeInstViewLen or cls == Code.CodeInstViewStride then add(k.dst, Code.CodeTyIndex)
                elseif cls == Code.CodeInstSliceMake then add(k.dst, Code.CodeTySlice(k.elem_ty))
                elseif cls == Code.CodeInstSliceData then add(k.dst, slice_data_type(ctx, k.slice))
                elseif cls == Code.CodeInstSliceLen then add(k.dst, Code.CodeTyIndex)
                elseif cls == Code.CodeInstByteSpanMake then add(k.dst, Code.CodeTyByteSpan)
                elseif cls == Code.CodeInstByteSpanData then add(k.dst, Code.CodeTyDataPtr(byte_ty()))
                elseif cls == Code.CodeInstByteSpanLen then add(k.dst, Code.CodeTyIndex)
                elseif cls == Code.CodeInstVariantTag then add(k.dst, k.tag_ty)
                elseif cls == Code.CodeInstVariantPayload then if k.variant.payload_ty ~= nil then add(k.dst, k.variant.payload_ty) end
                elseif cls == Code.CodeInstAtomicCas then
                    add(k.dst, k.access.ty)
                    local sid = Code.CodeValueId("atomic_cas_expected_addr:" .. b.insts[j].id.text)
                    add(sid, Code.CodeTyDataPtr(k.access.ty))
                    if pvm.classof(k.place) ~= Code.CodePlaceDeref then
                        local aid = Code.CodeValueId("atomic_addr:" .. b.insts[j].id.text .. ":cas")
                        add(aid, Code.CodeTyDataPtr(k.access.ty))
                    end
                elseif cls == Code.CodeInstAtomicLoad or cls == Code.CodeInstAtomicStore or cls == Code.CodeInstAtomicRmw then
                    if cls == Code.CodeInstAtomicLoad or cls == Code.CodeInstAtomicRmw then add(k.dst, k.access.ty) end
                    if pvm.classof(k.place) ~= Code.CodePlaceDeref then
                        local suffix = (cls == Code.CodeInstAtomicLoad and "load") or (cls == Code.CodeInstAtomicStore and "store") or "rmw"
                        local aid = Code.CodeValueId("atomic_addr:" .. b.insts[j].id.text .. ":" .. suffix)
                        add(aid, Code.CodeTyDataPtr(k.access.ty))
                    end
                elseif cls == Code.CodeInstCall then
                    local sig = ctx.sigs[k.sig.text]
                    if k.dst ~= nil and sig and #sig.results == 1 then add(k.dst, sig.results[1]) end
                end
            end
        end
        return out
    end

    local function lower_func(ctx, func)
        ctx.param_values = {}
        ctx.value_types = {}
        ctx.const_atoms = {}
        local params = {}
        for i = 1, #(func.params or {}) do
            ctx.param_values[func.params[i].value.text] = true
            ctx.value_types[func.params[i].value.text] = func.params[i].ty
            params[i] = C.CBackendLocal(c_local_id(func.params[i].value), c_name(func.params[i].name), c_ty(ctx, func.params[i].ty))
        end
        for i = 1, #(func.blocks or {}) do
            for j = 1, #(func.blocks[i].params or {}) do ctx.value_types[func.blocks[i].params[j].value.text] = func.blocks[i].params[j].ty end
        end
        local locals = collect_value_locals(ctx, func)
        local blocks = {}
        for i = 1, #(func.blocks or {}) do
            local b = func.blocks[i]
            local stmts = {}
            for j = 1, #(b.insts or {}) do
                local ss = inst_to_stmts(ctx, b.insts[j])
                for k = 1, #ss do if ss[k] ~= nil then stmts[#stmts + 1] = ss[k] end end
            end
            local params_ = {}
            for j = 1, #(b.params or {}) do params_[j] = C.CBackendBlockParam(c_local_id(b.params[j].value), c_ty(ctx, b.params[j].ty)) end
            blocks[i] = C.CBackendBlock(c_label(b.id), params_, stmts, term_to_c(ctx, b.term))
        end
        local visibility = (func.linkage == Code.CodeLinkageExport) and Core.VisibilityExport or Core.VisibilityLocal
        return C.CBackendFunc(
            c_name(func.name),
            func.name,
            visibility,
            c_sig(ctx, func.sig),
            params,
            locals,
            C.CBackendBodyBlocks(blocks[1].label, blocks)
        )
    end

    local function c_reloc_target(ref)
        local cls = pvm.classof(ref)
        if cls == Code.CodeGlobalRefGlobal then return C.CBackendRelocGlobal(c_global_id(ref.global)) end
        if cls == Code.CodeGlobalRefData then return C.CBackendRelocGlobal(c_global_id(ref.data)) end
        if cls == Code.CodeGlobalRefFunc then return C.CBackendRelocFunc(c_name(ref.func.text)) end
        if cls == Code.CodeGlobalRefExtern then return C.CBackendRelocExtern(c_name(ref["extern"].text)) end
        error("code_to_c: unsupported reloc target " .. class_name(ref), 2)
    end

    local function c_init(ctx, init)
        local cls = pvm.classof(init)
        if cls == Code.CodeDataZero then return C.CBackendDataZero(init.offset, init.size) end
        if cls == Code.CodeDataBytes then return C.CBackendDataBytes(init.offset, init.bytes) end
        if cls == Code.CodeDataScalar then return C.CBackendDataScalar(init.offset, c_ty(ctx, init.ty), init.literal) end
        if cls == Code.CodeDataReloc then return C.CBackendDataReloc(init.reloc.offset, c_reloc_target(init.reloc.target), init.reloc.addend) end
        return nil
    end

    local function lower_global(ctx, g)
        local inits = {}; for i = 1, #(g.inits or {}) do inits[i] = c_init(ctx, g.inits[i]) end
        local id = c_global_id(g.id)
        return C.CBackendGlobal(id, C.CBackendName(id.text), Core.VisibilityLocal, c_ty(ctx, g.ty), g.size or 8, g.align or 1, inits)
    end

    local function lower_data(ctx, d)
        local inits = {}; for i = 1, #(d.inits or {}) do inits[i] = c_init(ctx, d.inits[i]) end
        local id = c_global_id(d.id)
        return C.CBackendGlobal(id, C.CBackendName(id.text), Core.VisibilityLocal, C.CBackendDataPtr(nil), d.size, d.align, inits)
    end

    local function lower_extern(ctx, e)
        return C.CBackendExtern(c_name(e.name), e.symbol, c_sig(ctx, e.sig), nil)
    end

    local function lower_type_decl(ctx, td)
        local ty = c_ty(ctx, td.ty)
        return C.CBackendTypedef(C.CTypeId(ctx.module_name, td.name), ty)
    end

    local function c_type_size_align(ctx, ty)
        if ty == C.CBackendVoid or pvm.classof(ty) == C.CBackendVoid then return 0, 1 end
        if ty == C.CBackendBool8 or pvm.classof(ty) == C.CBackendBool8 then return 1, 1 end
        if ty == C.CBackendIndex or pvm.classof(ty) == C.CBackendIndex then local n = (ctx.target.index_bits or 64) / 8; return n, n end
        local cls = pvm.classof(ty)
        if cls == C.CBackendScalar then
            local s = ty.scalar
            if s == Core.ScalarI8 or s == Core.ScalarU8 or s == Core.ScalarBool then return 1, 1 end
            if s == Core.ScalarI16 or s == Core.ScalarU16 then return 2, 2 end
            if s == Core.ScalarI32 or s == Core.ScalarU32 or s == Core.ScalarF32 then return 4, 4 end
            if s == Core.ScalarI64 or s == Core.ScalarU64 or s == Core.ScalarF64 then return 8, 8 end
            if s == Core.ScalarIndex then local n = (ctx.target.index_bits or 64) / 8; return n, n end
            if s == Core.ScalarRawPtr then local n = (ctx.target.pointer_bits or 64) / 8; return n, n end
        elseif cls == C.CBackendDataPtr or cls == C.CBackendCodePtr or cls == C.CBackendImportedCodePtr then
            local n = (ctx.target.pointer_bits or 64) / 8; return n, n
        elseif cls == C.CBackendArray then
            local sz, al = c_type_size_align(ctx, ty.elem); return sz * ty.count, al
        elseif cls == C.CBackendNamed then
            local layout = ctx.c_type_layouts and ctx.c_type_layouts[c_type_id_key(ty.id)]
            if layout ~= nil then return layout.size, layout.align end
        end
        return 8, 8
    end

    local function variant_type_id(owner_ty)
        if pvm.classof(owner_ty) ~= Code.CodeTyNamed then return nil end
        return C.CTypeId(owner_ty.module_name, owner_ty.type_name)
    end

    local function collect_layout_type_decls(ctx, existing)
        local out = {}
        local env = ctx.layout_env
        for _, layout in ipairs((env and env.layouts) or {}) do
            local cls = pvm.classof(layout)
            local id
            if cls == Sem.LayoutNamed then id = C.CTypeId(layout.module_name, layout.type_name)
            elseif cls == Sem.LayoutLocal then id = C.CTypeId("local", layout.sym.name) end
            if id ~= nil then
                local key = id.module_name .. "\0" .. id.spelling
                if not existing[key] then
                    local fields = {}
                    for i = 1, #(layout.fields or {}) do
                        local lf = layout.fields[i]
                        local fty = CodeType.type_to_c(lf.ty, ctx.type_ctx)
                        local sz, al = c_type_size_align(ctx, fty)
                        fields[#fields + 1] = C.CBackendField(C.CBackendName(lf.field_name), fty, lf.offset, sz, al)
                    end
                    out[#out + 1] = C.CBackendStructDecl(id, fields, layout.size, layout.align)
                    existing[key] = true
                end
            end
        end
        return out
    end

    local function collect_variant_type_decls(ctx, code_module, existing)
        local by_key, order = {}, {}
        local function record(ref)
            if ref == nil then return end
            local id = variant_type_id(ref.owner_ty)
            if id == nil then return end
            local key = id.module_name .. "\0" .. id.spelling
            if existing[key] then return end
            local rec = by_key[key]
            if rec == nil then rec = { id = id, owner_ty = ref.owner_ty, variants = {}, by_variant = {} }; by_key[key] = rec; order[#order + 1] = rec end
            if ref.payload_ty ~= nil and rec.by_variant[ref.variant_name] == nil then
                rec.by_variant[ref.variant_name] = ref.payload_ty
                rec.variants[#rec.variants + 1] = { name = ref.variant_name, payload_ty = ref.payload_ty }
            end
        end
        for _, func in ipairs(code_module.funcs or {}) do
            for _, block in ipairs(func.blocks or {}) do
                for _, inst in ipairs(block.insts or {}) do
                    local k = inst.kind
                    local cls = pvm.classof(k)
                    if cls == Code.CodeInstVariantCtor or cls == Code.CodeInstVariantPayload then record(k.variant) end
                end
                if block.term ~= nil and pvm.classof(block.term.kind) == Code.CodeTermVariantSwitch then
                    for _, case in ipairs(block.term.kind.cases or {}) do record(case.variant) end
                end
            end
        end
        local out = {}
        for _, rec in ipairs(order) do
            local tag_ty = C.CBackendScalar(Core.ScalarU32)
            local fields = { C.CBackendField(C.CBackendName("__tag"), tag_ty, 0, 4, 4) }
            local size, align = 4, 4
            if #rec.variants > 0 then
                local union_id = variant_payload_union_id(rec.owner_ty)
                local union_fields = {}
                local psz, pal = 0, 1
                for i = 1, #rec.variants do
                    local payload_ty = c_ty(ctx, rec.variants[i].payload_ty)
                    local vsz, val = c_type_size_align(ctx, payload_ty)
                    union_fields[#union_fields + 1] = C.CBackendField(C.CBackendName(rec.variants[i].name), payload_ty, 0, vsz, val)
                    if vsz > psz then psz = vsz end
                    if val > pal then pal = val end
                end
                psz = math.floor((psz + pal - 1) / pal) * pal
                out[#out + 1] = C.CBackendUnionDecl(union_id, union_fields, psz, pal)
                ctx.c_type_layouts[c_type_id_key(union_id)] = { size = psz, align = pal }
                local off = math.floor((size + pal - 1) / pal) * pal
                fields[#fields + 1] = C.CBackendField(C.CBackendName("__payload"), C.CBackendNamed(union_id), off, psz, pal)
                size = off + psz
                align = math.max(align, pal)
            end
            size = math.floor((size + align - 1) / align) * align
            out[#out + 1] = C.CBackendStructDecl(rec.id, fields, size, align)
            existing[rec.id.module_name .. "\0" .. rec.id.spelling] = true
        end
        return out
    end

    local function c_type_layout_index(layout_env)
        local out = {}
        for _, layout in ipairs((layout_env and layout_env.layouts) or {}) do
            local cls = pvm.classof(layout)
            if cls == Sem.LayoutNamed then
                out[layout.module_name .. "\0" .. layout.type_name] = { size = layout.size, align = layout.align }
            elseif cls == Sem.LayoutLocal then
                out["local\0" .. layout.sym.name] = { size = layout.size, align = layout.align }
            end
        end
        return out
    end

    local function module(code_module, opts)
        opts = opts or {}
        local report = CodeValidate.validate(code_module, opts.collector)
        if opts.validate ~= false and #report.issues > 0 then
            error("code_to_c: CodeModule failed validation with " .. tostring(#report.issues) .. " issue(s)", 2)
        end
        local module_name = tostring(code_module.id.text):gsub("^module:", "")
        local type_ctx = { code_sigs = {}, code_sig_order = {}, module_name = module_name }
        local sigs = {}
        for i = 1, #(code_module.sigs or {}) do type_ctx.code_sigs[code_module.sigs[i].id.text] = code_module.sigs[i] end
        for i = 1, #(code_module.sigs or {}) do
            local s = code_module.sigs[i]
            local params = {}; for j = 1, #s.params do params[j] = CodeType.code_type_to_c(s.params[j], type_ctx) end
            local result = (#s.results == 0) and C.CBackendVoid or CodeType.code_type_to_c(s.results[1], type_ctx)
            sigs[#sigs + 1] = C.CBackendFuncSig(c_sig_id(s.id), params, result)
        end
        local ctx = {
            module_name = module_name,
            target = CodeType.normalize_target(opts.target or opts.c_target or opts),
            type_ctx = type_ctx,
            sigs = {}, funcs = {}, externs = {},
            helpers_by_id = {}, helper_order = {}, helpers = {},
            layout_env = opts.layout_env,
            c_type_layouts = c_type_layout_index(opts.layout_env),
        }
        for i = 1, #(code_module.sigs or {}) do ctx.sigs[code_module.sigs[i].id.text] = code_module.sigs[i] end
        for i = 1, #(code_module.funcs or {}) do ctx.funcs[code_module.funcs[i].id.text] = code_module.funcs[i] end
        for i = 1, #(code_module.externs or {}) do ctx.externs[code_module.externs[i].id.text] = code_module.externs[i] end

        local types = {}
        local existing_type_ids = {}
        for i = 1, #(code_module.types or {}) do
            types[i] = lower_type_decl(ctx, code_module.types[i])
            local id = types[i].id
            if id ~= nil then existing_type_ids[id.module_name .. "\0" .. id.spelling] = true end
        end
        local variant_types = collect_variant_type_decls(ctx, code_module, existing_type_ids)
        for i = 1, #variant_types do types[#types + 1] = variant_types[i] end
        local layout_types = collect_layout_type_decls(ctx, existing_type_ids)
        for i = 1, #layout_types do types[#types + 1] = layout_types[i] end
        local globals = {}
        for i = 1, #(code_module.data or {}) do globals[#globals + 1] = lower_data(ctx, code_module.data[i]) end
        for i = 1, #(code_module.globals or {}) do globals[#globals + 1] = lower_global(ctx, code_module.globals[i]) end
        local externs = {}; for i = 1, #(code_module.externs or {}) do externs[i] = lower_extern(ctx, code_module.externs[i]) end
        local funcs = {}; for i = 1, #(code_module.funcs or {}) do funcs[i] = lower_func(ctx, code_module.funcs[i]) end
        local seen_sigs = {}
        for i = 1, #sigs do seen_sigs[sigs[i].id.text] = true end
        for i = 1, #((type_ctx and type_ctx.sig_order) or {}) do
            local sig = type_ctx.sig_order[i]
            if not seen_sigs[sig.id.text] then
                sigs[#sigs + 1] = sig
                seen_sigs[sig.id.text] = true
            end
        end

        return C.CBackendUnit(code_module.id.text, ctx.target, sigs, types, globals, externs, ctx.helper_order, funcs)
    end

    api.module = module

    T._lalin_api_cache.code_to_c = api
    return api
end

return bind_context
