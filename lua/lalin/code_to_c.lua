local asdl = require("lalin.asdl")

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s:match("^%d") then s = "_" .. s end
    if s == "" then s = "x" end
    return s
end

local function class_name(x)
    local cls = asdl.classof(x) or x
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

    local function add_helper(c_emission, spec)
        local key = tostring(spec)
        c_emission.helpers_by_key = c_emission.helpers_by_key or {}
        local use = c_emission.helpers_by_key[key]
        if use ~= nil then return use.id end
        local id = C.CBackendHelperId("ml_code_helper_" .. tostring(#c_emission.helper_order + 1))
        use = C.CBackendHelperUse(id, spec)
        c_emission.helpers_by_key[key] = use
        c_emission.helpers_by_id[id.text] = use
        c_emission.helper_order[#c_emission.helper_order + 1] = use
        return id
    end

    local function c_ty(c_emission, ty)
        return CodeType.code_type_to_c(ty, c_emission.c_type_projection)
    end

    local function c_type_id_key(id)
        return id.module_name .. "\0" .. id.spelling
    end

    function Code.CodeType:code_to_c_variant_payload_union_id()
        return nil
    end
    function Code.CodeTyNamed:code_to_c_variant_payload_union_id()
        return C.CTypeId(self.module_name, self.type_name .. "_payload")
    end

    local function variant_payload_union_id(owner_ty)
        return owner_ty:code_to_c_variant_payload_union_id()
    end

    local function variant_payload_member_place(c_emission, base_place, variant)
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
            c_ty(c_emission, variant.payload_ty),
            0,
            nil,
            nil
        )
    end

    local function c_sig(c_emission, sig_id)
        return c_sig_id(sig_id)
    end

    local function c_trap_mode(mode)
        if mode == Code.CodeMustNotTrap then return C.CBackendMustNotTrap end
        if mode == Code.CodeCheckedTrap then return C.CBackendCheckedTrap end
        return C.CBackendMayTrap
    end

    local function c_access(c_emission, access)
        return C.CBackendMemoryAccess(c_ty(c_emission, access.ty), access.align, c_trap_mode(access.trap), access.volatile, access.ordering)
    end

    function C.CBackendType:code_to_c_is_pointer_type()
        return false
    end
    function C.CBackendDataPtr:code_to_c_is_pointer_type()
        return true
    end
    function C.CBackendCodePtr:code_to_c_is_pointer_type()
        return true
    end
    function C.CBackendImportedCodePtr:code_to_c_is_pointer_type()
        return true
    end
    function C.CBackendAbiHiddenOutPtr:code_to_c_is_pointer_type()
        return true
    end
    function C.CBackendSliceDescriptor:code_to_c_is_pointer_type()
        return true
    end
    function C.CBackendViewDescriptor:code_to_c_is_pointer_type()
        return true
    end
    function C.CBackendClosureDescriptor:code_to_c_is_pointer_type()
        return true
    end

    local function is_pointer_c_ty(ty)
        return ty:code_to_c_is_pointer_type()
    end

    function Core.Literal:code_to_c_is_zero_literal()
        return false
    end
    function Core.LitInt:code_to_c_is_zero_literal()
        return tostring(self.raw) == "0"
    end

    function C.CBackendAtom:code_to_c_is_nullish_const()
        return false
    end
    function C.CBackendAtomNull:code_to_c_is_nullish_const()
        return true
    end
    function C.CBackendAtomLiteral:code_to_c_is_nullish_const()
        return self.literal:code_to_c_is_zero_literal()
    end

    local function is_nullish_const_atom(a)
        return a:code_to_c_is_nullish_const()
    end

    function Sem.FieldRef:code_to_c_field_name()
        return "field"
    end
    function Sem.FieldByName:code_to_c_field_name()
        return self.field_name
    end
    function Sem.FieldByOffset:code_to_c_field_name()
        return self.field_name
    end

    local function field_name(field)
        return field:code_to_c_field_name()
    end

    local function atom(id)
        return C.CBackendAtomLocal(c_local_id(id))
    end

    function Code.CodeType:code_to_c_without_lease()
        return self
    end
    function Code.CodeTyLease:code_to_c_without_lease()
        return self.base
    end
    function Code.CodeType:code_to_c_view_elem_type()
        return nil
    end
    function Code.CodeTyView:code_to_c_view_elem_type()
        return self.elem
    end
    function Code.CodeType:code_to_c_slice_elem_type()
        return nil
    end
    function Code.CodeTySlice:code_to_c_slice_elem_type()
        return self.elem
    end

    local function view_type(c_emission, id)
        local ty = c_emission.value_types and id and c_emission.value_types[id.text] or nil
        if ty ~= nil then ty = ty:code_to_c_without_lease() end
        return ty
    end

    local function view_elem_type(c_emission, id)
        local ty = view_type(c_emission, id)
        return ty and ty:code_to_c_view_elem_type() or nil
    end

    local function view_data_type(c_emission, id)
        return Code.CodeTyDataPtr(view_elem_type(c_emission, id))
    end

    local function slice_type(c_emission, id)
        local ty = c_emission.value_types and id and c_emission.value_types[id.text] or nil
        if ty ~= nil then ty = ty:code_to_c_without_lease() end
        return ty
    end

    local function slice_elem_type(c_emission, id)
        local ty = slice_type(c_emission, id)
        return ty and ty:code_to_c_slice_elem_type() or nil
    end

    local function slice_data_type(c_emission, id)
        return Code.CodeTyDataPtr(slice_elem_type(c_emission, id))
    end

    local function byte_ty()
        return Code.CodeTyInt(8, Code.CodeUnsigned)
    end

    function Code.CodeConst:lower_code_const_to_c_atom(c_emission)
        error("code_to_c: unsupported const " .. class_name(self), 2)
    end
    function Code.CodeConstLiteral:lower_code_const_to_c_atom(c_emission)
        return C.CBackendAtomLiteral(c_ty(c_emission, self.ty), self.literal)
    end
    function Code.CodeConstNull:lower_code_const_to_c_atom(c_emission)
        return C.CBackendAtomNull(c_ty(c_emission, self.ty))
    end
    function Code.CodeConstUndef:lower_code_const_to_c_atom(c_emission)
        return C.CBackendAtomLiteral(c_ty(c_emission, self.ty), Core.LitInt("0"))
    end

    local function const_atom(c_emission, const)
        return const:lower_code_const_to_c_atom(c_emission)
    end

    local place_to_c
    function Code.CodePlace:lower_code_place_to_c(c_emission)
        error("code_to_c: unsupported place " .. class_name(self), 2)
    end
    function Code.CodePlace:code_to_c_is_deref()
        return false
    end
    function Code.CodePlaceLocal:lower_code_place_to_c(c_emission)
        return C.CBackendPlaceLocal(c_local_id(self.local_id), c_ty(c_emission, self.ty))
    end
    function Code.CodePlaceGlobal:lower_code_place_to_c(c_emission)
        return C.CBackendPlaceGlobal(c_global_id(self.global), c_ty(c_emission, self.ty))
    end
    function Code.CodePlaceData:lower_code_place_to_c(c_emission)
        return C.CBackendPlaceGlobal(c_global_id(self.data), c_ty(c_emission, self.ty))
    end
    function Code.CodePlaceDeref:lower_code_place_to_c(c_emission)
        return C.CBackendPlaceDeref(atom(self.addr), c_ty(c_emission, self.ty), self.align)
    end
    function Code.CodePlaceDeref:code_to_c_is_deref()
        return true
    end
    function Code.CodePlaceField:lower_code_place_to_c(c_emission)
        return C.CBackendPlaceField(place_to_c(c_emission, self.base), C.CBackendName(field_name(self.field)), c_ty(c_emission, self.ty), self.offset, self.size, self.align)
    end
    function Code.CodePlaceIndex:lower_code_place_to_c(c_emission)
        return C.CBackendPlaceIndex(place_to_c(c_emission, self.base), atom(self.index), c_ty(c_emission, self.ty), self.elem_size)
    end
    function Code.CodePlaceBytes:lower_code_place_to_c(c_emission)
        return C.CBackendPlaceBytes(atom(self.base), self.offset, c_ty(c_emission, self.ty), self.size, self.align)
    end
    place_to_c = function(c_emission, place)
        return place:lower_code_place_to_c(c_emission)
    end

    local function atomic_place_addr_stmts(c_emission, inst_id, place, suffix)
        if place:code_to_c_is_deref() then return {}, atom(place.addr) end
        local addr = c_synth_local_id2("atomic_addr", inst_id, suffix or "place")
        return { C.CBackendAssign(addr, C.CBackendRAddrOfPlace(place_to_c(c_emission, place))) }, C.CBackendAtomLocal(addr)
    end

    local function code_func_name(c_emission, id)
        local f = c_emission.funcs[id.text]
        if f == nil then error("code_to_c: missing function " .. tostring(id.text), 2) end
        return c_name(f.name)
    end

    local function code_extern_name(c_emission, id)
        local e = c_emission.externs[id.text]
        if e == nil then error("code_to_c: missing extern " .. tostring(id.text), 2) end
        return c_name(e.name)
    end

    function Code.CodeGlobalRef:lower_code_global_ref_to_c_name(c_emission)
        error("code_to_c: unsupported global ref " .. class_name(self), 2)
    end
    function Code.CodeGlobalRefFunc:lower_code_global_ref_to_c_name(c_emission)
        return code_func_name(c_emission, self.func)
    end
    function Code.CodeGlobalRefExtern:lower_code_global_ref_to_c_name(c_emission)
        return code_extern_name(c_emission, self["extern"])
    end
    function Code.CodeGlobalRefGlobal:lower_code_global_ref_to_c_name(c_emission)
        return c_name(self.global.text)
    end
    function Code.CodeGlobalRefData:lower_code_global_ref_to_c_name(c_emission)
        return c_name(self.data.text)
    end

    function Code.CodeGlobalRef:lower_code_global_ref_to_c_sig(c_emission)
        error("code_to_c: non-code global ref has no function signature " .. class_name(self), 2)
    end
    function Code.CodeGlobalRefFunc:lower_code_global_ref_to_c_sig(c_emission)
            local f = c_emission.funcs[self.func.text]
            if f == nil then error("code_to_c: missing function ref " .. tostring(self.func.text), 2) end
            return c_sig(c_emission, f.sig)
    end
    function Code.CodeGlobalRefExtern:lower_code_global_ref_to_c_sig(c_emission)
            local e = c_emission.externs[self["extern"].text]
            if e == nil then error("code_to_c: missing extern ref " .. tostring(self["extern"].text), 2) end
            return c_sig(c_emission, e.sig)
    end

    function Code.CodeGlobalRef:lower_code_global_ref_to_c_assign(c_emission, dst)
        return C.CBackendAssign(c_local_id(dst), C.CBackendRAtom(C.CBackendAtomGlobal(c_global_id(self.global or self.data))))
    end
    function Code.CodeGlobalRefFunc:lower_code_global_ref_to_c_assign(c_emission, dst)
        return C.CBackendAssign(c_local_id(dst), C.CBackendRFuncAddr(self:lower_code_global_ref_to_c_name(c_emission), self:lower_code_global_ref_to_c_sig(c_emission)))
    end
    function Code.CodeGlobalRefExtern:lower_code_global_ref_to_c_assign(c_emission, dst)
        return C.CBackendAssign(c_local_id(dst), C.CBackendRExternAddr(self:lower_code_global_ref_to_c_name(c_emission), self:lower_code_global_ref_to_c_sig(c_emission)))
    end

    function Code.CodeIntOverflow:lower_code_int_overflow_to_c()
        return C.CBackendIntWrap
    end
    function Code.CodeIntWrap:lower_code_int_overflow_to_c()
        return C.CBackendIntWrap
    end
    function Code.CodeIntTrapOnOverflow:lower_code_int_overflow_to_c()
        return C.CBackendIntTrapOnOverflow
    end
    function Code.CodeIntAssumeNoOverflow:lower_code_int_overflow_to_c()
        return C.CBackendIntAssumeNoOverflow
    end

    local function binary_helper_spec(c_emission, k)
        local ty = c_ty(c_emission, k.ty)
        if k.op == Core.BinDiv or k.op == Core.BinRem then
            local mode = (k.semantics and k.semantics.div == Code.CodeDivTrapOnZeroOrOverflow) and C.CBackendDivTrapOnZeroOrOverflow or C.CBackendDivTrapOnZero
            return C.CBackendHelperDivRem(k.op, ty, mode)
        elseif k.op == Core.BinShl or k.op == Core.BinLShr or k.op == Core.BinAShr then
            local mode = (k.semantics and k.semantics.shift == Code.CodeShiftTrapOutOfRange) and C.CBackendShiftTrapOutOfRange or C.CBackendShiftMaskCount
            return C.CBackendHelperShift(k.op, ty, mode)
        else
            local overflow = C.CBackendIntWrap
            if k.semantics then overflow = k.semantics.overflow:lower_code_int_overflow_to_c() end
            return C.CBackendHelperIntBinary(k.op, ty, overflow)
        end
    end

    local function atoms(values)
        local out = {}
        for i = 1, #(values or {}) do out[i] = atom(values[i]) end
        return out
    end

    function Code.CodeCallTarget:lower_code_call_target_to_c(c_emission)
        error("code_to_c: unsupported call target " .. class_name(self), 2)
    end
    function Code.CodeCallDirect:lower_code_call_target_to_c(c_emission)
        return C.CBackendCallDirect(code_func_name(c_emission, self.func))
    end
    function Code.CodeCallExtern:lower_code_call_target_to_c(c_emission)
        return C.CBackendCallExtern(code_extern_name(c_emission, self["extern"]))
    end
    function Code.CodeCallIndirect:lower_code_call_target_to_c(c_emission)
        return C.CBackendCallIndirect(atom(self.callee), c_sig(c_emission, self.sig))
    end
    function Code.CodeCallClosure:lower_code_call_target_to_c(c_emission)
        return C.CBackendCallClosure(atom(self.closure), c_sig(c_emission, self.sig))
    end

    function Code.CodeInst:lower_code_inst_to_c_stmts(c_emission)
        return self.op:lower_code_inst_to_c_stmts(c_emission, self)
    end
    function Code.CodeInstOp:lower_code_inst_to_c_stmts(c_emission, inst)
        error("code_to_c: unsupported CodeInstOp " .. class_name(self), 2)
    end
    function Code.CodeInstConst:lower_code_inst_to_c_stmts(c_emission)
        local a = const_atom(c_emission, self.const)
        c_emission.const_atoms[self.dst.text] = a
        return { C.CBackendAssign(c_local_id(self.dst), C.CBackendRAtom(a)) }
    end
    function Code.CodeInstAlias:lower_code_inst_to_c_stmts(c_emission)
        c_emission.const_atoms[self.dst.text] = c_emission.const_atoms[self.src.text]
        return { C.CBackendAssign(c_local_id(self.dst), C.CBackendRAtom(atom(self.src))) }
    end
    function Code.CodeInstUnary:lower_code_inst_to_c_stmts(c_emission)
        local helper = add_helper(c_emission, C.CBackendHelperUnary(self.op, c_ty(c_emission, self.ty)))
        return { C.CBackendHelperCall(c_local_id(self.dst), helper, { atom(self.value) }) }
    end
    function Code.CodeInstBinary:lower_code_inst_to_c_stmts(c_emission)
        local helper = add_helper(c_emission, binary_helper_spec(c_emission, self))
        return { C.CBackendHelperCall(c_local_id(self.dst), helper, { atom(self.lhs), atom(self.rhs) }) }
    end
    function Code.CodeInstFloatBinary:lower_code_inst_to_c_stmts(c_emission)
        local helper = add_helper(c_emission, C.CBackendHelperFloatBinary(self.op, c_ty(c_emission, self.ty)))
        return { C.CBackendHelperCall(c_local_id(self.dst), helper, { atom(self.lhs), atom(self.rhs) }) }
    end
    function Code.CodeInstCompare:lower_code_inst_to_c_stmts(c_emission)
        return { C.CBackendAssign(c_local_id(self.dst), C.CBackendRCompare(self.op, c_ty(c_emission, self.operand_ty), atom(self.lhs), atom(self.rhs))) }
    end
    function Code.CodeInstCast:lower_code_inst_to_c_stmts(c_emission)
        local to_ty = c_ty(c_emission, self.to)
        local source_const = c_emission.const_atoms[self.value.text]
        if is_pointer_c_ty(to_ty) and source_const ~= nil and is_nullish_const_atom(source_const) then
            local null_atom = C.CBackendAtomNull(to_ty)
            c_emission.const_atoms[self.dst.text] = null_atom
            return { C.CBackendAssign(c_local_id(self.dst), C.CBackendRAtom(null_atom)) }
        end
        c_emission.const_atoms[self.dst.text] = nil
        return { C.CBackendAssign(c_local_id(self.dst), C.CBackendRCast(self.op, to_ty, atom(self.value))) }
    end
    function Code.CodeInstSelect:lower_code_inst_to_c_stmts(c_emission)
        return { C.CBackendAssign(c_local_id(self.dst), C.CBackendRSelect(c_ty(c_emission, self.ty), atom(self.cond), atom(self.then_value), atom(self.else_value))) }
    end
    function Code.CodeInstIntrinsic:lower_code_inst_to_c_stmts(c_emission)
        local helper = add_helper(c_emission, C.CBackendHelperIntrinsic(self.op, c_ty(c_emission, self.ty)))
        return { C.CBackendHelperCall(self.dst and c_local_id(self.dst) or nil, helper, atoms(self.args)) }
    end
    function Code.CodeInstAddrOf:lower_code_inst_to_c_stmts(c_emission)
        return { C.CBackendAssign(c_local_id(self.dst), C.CBackendRAddrOfPlace(place_to_c(c_emission, self.place))) }
    end
    function Code.CodeInstGlobalRef:lower_code_inst_to_c_stmts(c_emission)
        return { self.ref:lower_code_global_ref_to_c_assign(c_emission, self.dst) }
    end
    function Code.CodeInstPtrOffset:lower_code_inst_to_c_stmts(c_emission)
        return { C.CBackendAssign(c_local_id(self.dst), C.CBackendRPtrOffset(atom(self.base), atom(self.index), self.elem_size, self.const_offset)) }
    end
    function Code.CodeInstLoad:lower_code_inst_to_c_stmts(c_emission)
        return { C.CBackendPlaceLoad(c_local_id(self.dst), place_to_c(c_emission, self.place)) }
    end
    function Code.CodeInstStore:lower_code_inst_to_c_stmts(c_emission)
        return { C.CBackendPlaceStore(place_to_c(c_emission, self.place), atom(self.value)) }
    end
    function Code.CodeInstAggregate:lower_code_inst_to_c_stmts(c_emission)
        local fields = {}
        for i = 1, #self.fields do fields[i] = C.CBackendAggregateFieldInit(C.CBackendName(field_name(self.fields[i].field)), atom(self.fields[i].value), nil) end
        return { C.CBackendAggregateInit(C.CBackendPlaceLocal(c_local_id(self.dst), c_ty(c_emission, self.ty)), c_ty(c_emission, self.ty), fields) }
    end
    function Code.CodeInstArray:lower_code_inst_to_c_stmts(c_emission)
        local elems = {}; for i = 1, #self.elems do elems[i] = C.CBackendArrayElemInit(self.elems[i].index, atom(self.elems[i].value)) end
        return { C.CBackendArrayInit(C.CBackendPlaceLocal(c_local_id(self.dst), c_ty(c_emission, self.ty)), c_ty(c_emission, self.ty), elems) }
    end
    function Code.CodeInstViewMake:lower_code_inst_to_c_stmts(c_emission)
        return { C.CBackendAggregateInit(C.CBackendPlaceLocal(c_local_id(self.dst), c_ty(c_emission, Code.CodeTyView(self.elem_ty))), c_ty(c_emission, Code.CodeTyView(self.elem_ty)), {
            C.CBackendAggregateFieldInit(C.CBackendName("data"), atom(self.data), 0),
            C.CBackendAggregateFieldInit(C.CBackendName("len"), atom(self.len), nil),
            C.CBackendAggregateFieldInit(C.CBackendName("stride"), atom(self.stride), nil),
        }) }
    end
    function Code.CodeInstViewData:lower_code_inst_to_c_stmts(c_emission)
        return { C.CBackendPlaceLoad(c_local_id(self.dst), C.CBackendPlaceField(C.CBackendPlaceLocal(c_local_id(self.view), c_ty(c_emission, view_type(c_emission, self.view))), C.CBackendName("data"), c_ty(c_emission, view_data_type(c_emission, self.view)), 0, nil, nil)) }
    end
    function Code.CodeInstViewLen:lower_code_inst_to_c_stmts(c_emission)
        return { C.CBackendPlaceLoad(c_local_id(self.dst), C.CBackendPlaceField(C.CBackendPlaceLocal(c_local_id(self.view), c_ty(c_emission, view_type(c_emission, self.view))), C.CBackendName("len"), C.CBackendIndex, 0, nil, nil)) }
    end
    function Code.CodeInstViewStride:lower_code_inst_to_c_stmts(c_emission)
        return { C.CBackendPlaceLoad(c_local_id(self.dst), C.CBackendPlaceField(C.CBackendPlaceLocal(c_local_id(self.view), c_ty(c_emission, view_type(c_emission, self.view))), C.CBackendName("stride"), C.CBackendIndex, 0, nil, nil)) }
    end
    function Code.CodeInstSliceMake:lower_code_inst_to_c_stmts(c_emission)
        return { C.CBackendAggregateInit(C.CBackendPlaceLocal(c_local_id(self.dst), c_ty(c_emission, Code.CodeTySlice(self.elem_ty))), c_ty(c_emission, Code.CodeTySlice(self.elem_ty)), {
            C.CBackendAggregateFieldInit(C.CBackendName("data"), atom(self.data), 0),
            C.CBackendAggregateFieldInit(C.CBackendName("len"), atom(self.len), nil),
        }) }
    end
    function Code.CodeInstSliceData:lower_code_inst_to_c_stmts(c_emission)
        return { C.CBackendPlaceLoad(c_local_id(self.dst), C.CBackendPlaceField(C.CBackendPlaceLocal(c_local_id(self.slice), c_ty(c_emission, slice_type(c_emission, self.slice))), C.CBackendName("data"), c_ty(c_emission, slice_data_type(c_emission, self.slice)), 0, nil, nil)) }
    end
    function Code.CodeInstSliceLen:lower_code_inst_to_c_stmts(c_emission)
        return { C.CBackendPlaceLoad(c_local_id(self.dst), C.CBackendPlaceField(C.CBackendPlaceLocal(c_local_id(self.slice), c_ty(c_emission, slice_type(c_emission, self.slice))), C.CBackendName("len"), C.CBackendIndex, 0, nil, nil)) }
    end
    function Code.CodeInstByteSpanMake:lower_code_inst_to_c_stmts(c_emission)
        return { C.CBackendAggregateInit(C.CBackendPlaceLocal(c_local_id(self.dst), c_ty(c_emission, Code.CodeTyByteSpan)), c_ty(c_emission, Code.CodeTyByteSpan), {
            C.CBackendAggregateFieldInit(C.CBackendName("data"), atom(self.data), 0),
            C.CBackendAggregateFieldInit(C.CBackendName("len"), atom(self.len), nil),
        }) }
    end
    function Code.CodeInstByteSpanData:lower_code_inst_to_c_stmts(c_emission)
        return { C.CBackendPlaceLoad(c_local_id(self.dst), C.CBackendPlaceField(C.CBackendPlaceLocal(c_local_id(self.span), c_ty(c_emission, Code.CodeTyByteSpan)), C.CBackendName("data"), c_ty(c_emission, Code.CodeTyDataPtr(byte_ty())), 0, nil, nil)) }
    end
    function Code.CodeInstByteSpanLen:lower_code_inst_to_c_stmts(c_emission)
        return { C.CBackendPlaceLoad(c_local_id(self.dst), C.CBackendPlaceField(C.CBackendPlaceLocal(c_local_id(self.span), c_ty(c_emission, Code.CodeTyByteSpan)), C.CBackendName("len"), C.CBackendIndex, 0, nil, nil)) }
    end
    function Code.CodeInstClosure:lower_code_inst_to_c_stmts(c_emission)
        return { C.CBackendAggregateInit(C.CBackendPlaceLocal(c_local_id(self.dst), c_ty(c_emission, self.ty)), c_ty(c_emission, self.ty), {
            C.CBackendAggregateFieldInit(C.CBackendName("fn"), atom(self.fn), 0),
            C.CBackendAggregateFieldInit(C.CBackendName("c_emission"), atom(self.c_emission), nil),
        }) }
    end
    function Code.CodeInstVariantCtor:lower_code_inst_to_c_stmts(c_emission)
        local dst_place = C.CBackendPlaceLocal(c_local_id(self.dst), c_ty(c_emission, self.ty))
        local out = {
            C.CBackendAggregateInit(dst_place, c_ty(c_emission, self.ty), {
                C.CBackendAggregateFieldInit(C.CBackendName("__tag"), C.CBackendAtomLiteral(C.CBackendScalar(Core.ScalarU32), Core.LitInt(tostring(self.variant.tag_value))), 0),
            })
        }
        if self.payload ~= nil then
            out[#out + 1] = C.CBackendPlaceStore(variant_payload_member_place(c_emission, dst_place, self.variant), atom(self.payload))
        end
        return out
    end
    function Code.CodeInstVariantTag:lower_code_inst_to_c_stmts(c_emission)
        return { C.CBackendPlaceLoad(c_local_id(self.dst), C.CBackendPlaceField(C.CBackendPlaceLocal(c_local_id(self.value), c_ty(c_emission, self.variant and self.variant.owner_ty or Code.CodeTyVoid)), C.CBackendName("__tag"), c_ty(c_emission, self.tag_ty), 0, nil, nil)) }
    end
    function Code.CodeInstVariantPayload:lower_code_inst_to_c_stmts(c_emission)
        return { C.CBackendPlaceLoad(c_local_id(self.dst), variant_payload_member_place(c_emission, C.CBackendPlaceLocal(c_local_id(self.value), c_ty(c_emission, self.variant.owner_ty)), self.variant)) }
    end
    function Code.CodeInstCall:lower_code_inst_to_c_stmts(c_emission)
        return { C.CBackendCall(self.dst and c_local_id(self.dst) or nil, self.target:lower_code_call_target_to_c(c_emission), atoms(self.args)) }
    end
    function Code.CodeInstAtomicLoad:lower_code_inst_to_c_stmts(c_emission, inst)
        local helper = add_helper(c_emission, C.CBackendHelperAtomicLoad(c_access(c_emission, self.access)))
        local stmts, addr = atomic_place_addr_stmts(c_emission, inst.id, self.place, "load")
        stmts[#stmts + 1] = C.CBackendHelperCall(c_local_id(self.dst), helper, { addr })
        return stmts
    end
    function Code.CodeInstAtomicStore:lower_code_inst_to_c_stmts(c_emission, inst)
        local helper = add_helper(c_emission, C.CBackendHelperAtomicStore(c_access(c_emission, self.access)))
        local stmts, addr = atomic_place_addr_stmts(c_emission, inst.id, self.place, "store")
        stmts[#stmts + 1] = C.CBackendHelperCall(nil, helper, { addr, atom(self.value) })
        return stmts
    end
    function Code.CodeInstAtomicRmw:lower_code_inst_to_c_stmts(c_emission, inst)
        local helper = add_helper(c_emission, C.CBackendHelperAtomicRmw(self.op, c_access(c_emission, self.access)))
        local stmts, addr = atomic_place_addr_stmts(c_emission, inst.id, self.place, "rmw")
        stmts[#stmts + 1] = C.CBackendHelperCall(c_local_id(self.dst), helper, { addr, atom(self.value) })
        return stmts
    end
    function Code.CodeInstAtomicCas:lower_code_inst_to_c_stmts(c_emission, inst)
        local expected_addr = c_synth_local_id("atomic_cas_expected_addr", inst.id)
        local helper = add_helper(c_emission, C.CBackendHelperAtomicCas(c_access(c_emission, self.access), self.ordering, self.ordering))
        local stmts, addr = atomic_place_addr_stmts(c_emission, inst.id, self.place, "cas")
        stmts[#stmts + 1] =
            C.CBackendAssign(expected_addr, C.CBackendRAddrOfPlace(C.CBackendPlaceLocal(c_local_id(self.expected), c_ty(c_emission, self.access.ty))))
        stmts[#stmts + 1] = C.CBackendHelperCall(c_local_id(self.dst), helper, { addr, C.CBackendAtomLocal(expected_addr), atom(self.replacement) })
        return stmts
    end
    function Code.CodeInstAtomicFence:lower_code_inst_to_c_stmts(c_emission)
        local helper = add_helper(c_emission, C.CBackendHelperAtomicFence(self.ordering))
        return { C.CBackendHelperCall(nil, helper, {}) }
    end

    local function inst_to_stmts(c_emission, inst)
        return inst:lower_code_inst_to_c_stmts(c_emission)
    end

    function Code.CodeTerm:lower_code_term_to_c(c_emission)
        return self.op:lower_code_term_to_c(c_emission, self)
    end
    function Code.CodeTermOp:lower_code_term_to_c(c_emission, term)
        error("code_to_c: unsupported CodeTermOp " .. class_name(self), 2)
    end
    function Code.CodeTermJump:lower_code_term_to_c(c_emission)
        return C.CBackendGoto(c_label(self.dest), atoms(self.args))
    end
    function Code.CodeTermBranch:lower_code_term_to_c(c_emission)
        return C.CBackendIfGoto(atom(self.cond), c_label(self.then_dest), atoms(self.then_args), c_label(self.else_dest), atoms(self.else_args))
    end
    function Code.CodeTermSwitch:lower_code_term_to_c(c_emission)
        local cases = {}
        for i = 1, #self.cases do
            local case = self.cases[i]
            cases[i] = C.CBackendSwitchCase(case.literal, c_label(case.dest), atoms(case.args))
        end
        return C.CBackendSwitchGoto(atom(self.value), cases, c_label(self.default_dest), atoms(self.default_args))
    end
    function Code.CodeTermVariantSwitch:lower_code_term_to_c(c_emission)
        local cases = {}
        for i = 1, #self.cases do
            local case = self.cases[i]
            cases[i] = C.CBackendSwitchCase(Core.LitInt(tostring(case.variant.tag_value)), c_label(case.dest), atoms(case.args))
        end
        return C.CBackendSwitchGoto(atom(self.tag), cases, c_label(self.default_dest), atoms(self.default_args))
    end
    function Code.CodeTermReturn:lower_code_term_to_c(c_emission)
        if #self.values == 0 then return C.CBackendReturnVoid end
        return C.CBackendReturn(atom(self.values[1]))
    end
    function Code.CodeTermTrap:lower_code_term_to_c(c_emission)
        return C.CBackendTrap
    end
    function Code.CodeTermUnreachable:lower_code_term_to_c(c_emission)
        return C.CBackendTrap
    end

    local function term_to_c(c_emission, term)
        return term:lower_code_term_to_c(c_emission)
    end

    function Code.CodeInst:append_code_to_c_locals(c_emission, add)
        self.op:append_code_to_c_locals(c_emission, self, add)
    end
    function Code.CodeInstOp:append_code_to_c_locals(c_emission, inst, add)
    end
    function Code.CodeInstConst:append_code_to_c_locals(c_emission, inst, add)
        add(self.dst, self.const.ty)
    end
    function Code.CodeInstAlias:append_code_to_c_locals(c_emission, inst, add)
        add(self.dst, self.ty)
    end
    function Code.CodeInstUnary:append_code_to_c_locals(c_emission, inst, add)
        add(self.dst, self.ty)
    end
    function Code.CodeInstBinary:append_code_to_c_locals(c_emission, inst, add)
        add(self.dst, self.ty)
    end
    function Code.CodeInstFloatBinary:append_code_to_c_locals(c_emission, inst, add)
        add(self.dst, self.ty)
    end
    function Code.CodeInstSelect:append_code_to_c_locals(c_emission, inst, add)
        add(self.dst, self.ty)
    end
    function Code.CodeInstIntrinsic:append_code_to_c_locals(c_emission, inst, add)
        add(self.dst, self.ty)
    end
    function Code.CodeInstCompare:append_code_to_c_locals(c_emission, inst, add)
        add(self.dst, Code.CodeTyBool8)
    end
    function Code.CodeInstCast:append_code_to_c_locals(c_emission, inst, add)
        add(self.dst, self.to)
    end
    function Code.CodeInstAddrOf:append_code_to_c_locals(c_emission, inst, add)
        add(self.dst, self.ptr_ty)
    end
    function Code.CodeInstGlobalRef:append_code_to_c_locals(c_emission, inst, add)
        add(self.dst, self.ptr_ty)
    end
    function Code.CodeInstPtrOffset:append_code_to_c_locals(c_emission, inst, add)
        add(self.dst, self.ptr_ty)
    end
    function Code.CodeInstLoad:append_code_to_c_locals(c_emission, inst, add)
        add(self.dst, self.access.ty)
    end
    function Code.CodeInstAggregate:append_code_to_c_locals(c_emission, inst, add)
        add(self.dst, self.ty)
    end
    function Code.CodeInstArray:append_code_to_c_locals(c_emission, inst, add)
        add(self.dst, self.ty)
    end
    function Code.CodeInstClosure:append_code_to_c_locals(c_emission, inst, add)
        add(self.dst, self.ty)
    end
    function Code.CodeInstVariantCtor:append_code_to_c_locals(c_emission, inst, add)
        add(self.dst, self.ty)
    end
    function Code.CodeInstViewMake:append_code_to_c_locals(c_emission, inst, add)
        add(self.dst, Code.CodeTyView(self.elem_ty))
    end
    function Code.CodeInstViewData:append_code_to_c_locals(c_emission, inst, add)
        add(self.dst, view_data_type(c_emission, self.view))
    end
    function Code.CodeInstViewLen:append_code_to_c_locals(c_emission, inst, add)
        add(self.dst, Code.CodeTyIndex)
    end
    function Code.CodeInstViewStride:append_code_to_c_locals(c_emission, inst, add)
        add(self.dst, Code.CodeTyIndex)
    end
    function Code.CodeInstSliceMake:append_code_to_c_locals(c_emission, inst, add)
        add(self.dst, Code.CodeTySlice(self.elem_ty))
    end
    function Code.CodeInstSliceData:append_code_to_c_locals(c_emission, inst, add)
        add(self.dst, slice_data_type(c_emission, self.slice))
    end
    function Code.CodeInstSliceLen:append_code_to_c_locals(c_emission, inst, add)
        add(self.dst, Code.CodeTyIndex)
    end
    function Code.CodeInstByteSpanMake:append_code_to_c_locals(c_emission, inst, add)
        add(self.dst, Code.CodeTyByteSpan)
    end
    function Code.CodeInstByteSpanData:append_code_to_c_locals(c_emission, inst, add)
        add(self.dst, Code.CodeTyDataPtr(byte_ty()))
    end
    function Code.CodeInstByteSpanLen:append_code_to_c_locals(c_emission, inst, add)
        add(self.dst, Code.CodeTyIndex)
    end
    function Code.CodeInstVariantTag:append_code_to_c_locals(c_emission, inst, add)
        add(self.dst, self.tag_ty)
    end
    function Code.CodeInstVariantPayload:append_code_to_c_locals(c_emission, inst, add)
        if self.variant.payload_ty ~= nil then add(self.dst, self.variant.payload_ty) end
    end
    function Code.CodeInstAtomicLoad:append_code_to_c_locals(c_emission, inst, add)
        add(self.dst, self.access.ty)
        if not self.place:code_to_c_is_deref() then
            add(Code.CodeValueId("atomic_addr:" .. inst.id.text .. ":load"), Code.CodeTyDataPtr(self.access.ty))
        end
    end
    function Code.CodeInstAtomicStore:append_code_to_c_locals(c_emission, inst, add)
        if not self.place:code_to_c_is_deref() then
            add(Code.CodeValueId("atomic_addr:" .. inst.id.text .. ":store"), Code.CodeTyDataPtr(self.access.ty))
        end
    end
    function Code.CodeInstAtomicRmw:append_code_to_c_locals(c_emission, inst, add)
        add(self.dst, self.access.ty)
        if not self.place:code_to_c_is_deref() then
            add(Code.CodeValueId("atomic_addr:" .. inst.id.text .. ":rmw"), Code.CodeTyDataPtr(self.access.ty))
        end
    end
    function Code.CodeInstAtomicCas:append_code_to_c_locals(c_emission, inst, add)
        add(self.dst, self.access.ty)
        add(Code.CodeValueId("atomic_cas_expected_addr:" .. inst.id.text), Code.CodeTyDataPtr(self.access.ty))
        if not self.place:code_to_c_is_deref() then
            add(Code.CodeValueId("atomic_addr:" .. inst.id.text .. ":cas"), Code.CodeTyDataPtr(self.access.ty))
        end
    end
    function Code.CodeInstCall:append_code_to_c_locals(c_emission, inst, add)
        local sig = c_emission.sigs[self.sig.text]
        if self.dst ~= nil and sig and #sig.results == 1 then add(self.dst, sig.results[1]) end
    end

    local function collect_value_locals(c_emission, func)
        local out, seen = {}, {}
        local function add(id, ty)
            if id ~= nil and ty ~= nil then c_emission.value_types[id.text] = ty end
            if id == nil or seen[id.text] or c_emission.param_values[id.text] then return end
            seen[id.text] = true
            out[#out + 1] = C.CBackendLocal(c_local_id(id), c_name(id.text), c_ty(c_emission, ty))
        end
        for i = 1, #(func.locals or {}) do add(func.locals[i].id, func.locals[i].ty) end
        for i = 1, #(func.blocks or {}) do
            local b = func.blocks[i]
            for j = 1, #(b.insts or {}) do
                b.insts[j]:append_code_to_c_locals(c_emission, add)
            end
        end
        return out
    end

    local function lower_func(c_emission, func)
        c_emission.param_values = {}
        c_emission.value_types = {}
        c_emission.const_atoms = {}
        local params = {}
        for i = 1, #(func.params or {}) do
            c_emission.param_values[func.params[i].value.text] = true
            c_emission.value_types[func.params[i].value.text] = func.params[i].ty
            params[i] = C.CBackendLocal(c_local_id(func.params[i].value), c_name(func.params[i].name), c_ty(c_emission, func.params[i].ty))
        end
        for i = 1, #(func.blocks or {}) do
            for j = 1, #(func.blocks[i].params or {}) do c_emission.value_types[func.blocks[i].params[j].value.text] = func.blocks[i].params[j].ty end
        end
        local locals = collect_value_locals(c_emission, func)
        local blocks = {}
        for i = 1, #(func.blocks or {}) do
            local b = func.blocks[i]
            local stmts = {}
            for j = 1, #(b.insts or {}) do
                local ss = inst_to_stmts(c_emission, b.insts[j])
                for k = 1, #ss do if ss[k] ~= nil then stmts[#stmts + 1] = ss[k] end end
            end
            local params_ = {}
            for j = 1, #(b.params or {}) do params_[j] = C.CBackendBlockParam(c_local_id(b.params[j].value), c_ty(c_emission, b.params[j].ty)) end
            blocks[i] = C.CBackendBlock(c_label(b.id), params_, stmts, term_to_c(c_emission, b.term))
        end
        local visibility = (func.linkage == Code.CodeLinkageExport) and Core.VisibilityExport or Core.VisibilityLocal
        return C.CBackendFunc(
            c_name(func.name),
            func.name,
            visibility,
            c_sig(c_emission, func.sig),
            params,
            locals,
            C.CBackendBodyBlocks(blocks[1].label, blocks)
        )
    end

    function Code.CodeGlobalRef:lower_code_global_ref_to_c_reloc()
        error("code_to_c: unsupported reloc target " .. class_name(self), 2)
    end
    function Code.CodeGlobalRefGlobal:lower_code_global_ref_to_c_reloc()
        return C.CBackendRelocGlobal(c_global_id(self.global))
    end
    function Code.CodeGlobalRefData:lower_code_global_ref_to_c_reloc()
        return C.CBackendRelocGlobal(c_global_id(self.data))
    end
    function Code.CodeGlobalRefFunc:lower_code_global_ref_to_c_reloc()
        return C.CBackendRelocFunc(c_name(self.func.text))
    end
    function Code.CodeGlobalRefExtern:lower_code_global_ref_to_c_reloc()
        return C.CBackendRelocExtern(c_name(self["extern"].text))
    end

    function Code.CodeDataInit:lower_code_data_init_to_c(c_emission)
        error("code_to_c: unsupported data init " .. class_name(self), 2)
    end
    function Code.CodeDataZero:lower_code_data_init_to_c(c_emission)
        return C.CBackendDataZero(self.offset, self.size)
    end
    function Code.CodeDataBytes:lower_code_data_init_to_c(c_emission)
        return C.CBackendDataBytes(self.offset, self.bytes)
    end
    function Code.CodeDataScalar:lower_code_data_init_to_c(c_emission)
        return C.CBackendDataScalar(self.offset, c_ty(c_emission, self.ty), self.literal)
    end
    function Code.CodeDataReloc:lower_code_data_init_to_c(c_emission)
        return C.CBackendDataReloc(self.reloc.offset, self.reloc.target:lower_code_global_ref_to_c_reloc(), self.reloc.addend)
    end

    local function c_init(c_emission, init)
        return init:lower_code_data_init_to_c(c_emission)
    end

    local function lower_global(c_emission, g)
        local inits = {}; for i = 1, #(g.inits or {}) do inits[i] = c_init(c_emission, g.inits[i]) end
        local id = c_global_id(g.id)
        return C.CBackendGlobal(id, C.CBackendName(id.text), Core.VisibilityLocal, c_ty(c_emission, g.ty), g.size or 8, g.align or 1, inits)
    end

    local function lower_data(c_emission, d)
        local inits = {}; for i = 1, #(d.inits or {}) do inits[i] = c_init(c_emission, d.inits[i]) end
        local id = c_global_id(d.id)
        return C.CBackendGlobal(id, C.CBackendName(id.text), Core.VisibilityLocal, C.CBackendDataPtr(nil), d.size, d.align, inits)
    end

    local function lower_extern(c_emission, e)
        return C.CBackendExtern(c_name(e.name), e.symbol, c_sig(c_emission, e.sig), nil)
    end

    local function lower_type_decl(c_emission, td)
        local ty = c_ty(c_emission, td.ty)
        return C.CBackendTypedef(C.CTypeId(c_emission.module_name, td.name), ty)
    end

    local c_type_size_align
    function C.CBackendType:code_to_c_size_align(c_emission)
        return 8, 8
    end
    function C.CBackendVoid:code_to_c_size_align(c_emission)
        return 0, 1
    end
    function C.CBackendBool8:code_to_c_size_align(c_emission)
        return 1, 1
    end
    function C.CBackendIndex:code_to_c_size_align(c_emission)
        local n = (c_emission.target.index_bits or 64) / 8
        return n, n
    end
    function C.CBackendScalar:code_to_c_size_align(c_emission)
        local s = self.scalar
        if s == Core.ScalarI8 or s == Core.ScalarU8 or s == Core.ScalarBool then return 1, 1 end
        if s == Core.ScalarI16 or s == Core.ScalarU16 then return 2, 2 end
        if s == Core.ScalarI32 or s == Core.ScalarU32 or s == Core.ScalarF32 then return 4, 4 end
        if s == Core.ScalarI64 or s == Core.ScalarU64 or s == Core.ScalarF64 then return 8, 8 end
        if s == Core.ScalarIndex then local n = (c_emission.target.index_bits or 64) / 8; return n, n end
        if s == Core.ScalarRawPtr then local n = (c_emission.target.pointer_bits or 64) / 8; return n, n end
        return 8, 8
    end
    function C.CBackendDataPtr:code_to_c_size_align(c_emission)
        local n = (c_emission.target.pointer_bits or 64) / 8
        return n, n
    end
    function C.CBackendCodePtr:code_to_c_size_align(c_emission)
        local n = (c_emission.target.pointer_bits or 64) / 8
        return n, n
    end
    function C.CBackendImportedCodePtr:code_to_c_size_align(c_emission)
        local n = (c_emission.target.pointer_bits or 64) / 8
        return n, n
    end
    function C.CBackendArray:code_to_c_size_align(c_emission)
        local sz, al = c_type_size_align(c_emission, self.elem)
        return sz * self.count, al
    end
    function C.CBackendNamed:code_to_c_size_align(c_emission)
        local layout = c_emission.c_type_layouts and c_emission.c_type_layouts[c_type_id_key(self.id)]
        if layout ~= nil then return layout.size, layout.align end
        return 8, 8
    end

    c_type_size_align = function(c_emission, ty)
        return ty:code_to_c_size_align(c_emission)
    end

    function Code.CodeType:code_to_c_variant_type_id()
        return nil
    end
    function Code.CodeTyNamed:code_to_c_variant_type_id()
        return C.CTypeId(self.module_name, self.type_name)
    end

    local function variant_type_id(owner_ty)
        return owner_ty:code_to_c_variant_type_id()
    end

    function Sem.TypeLayout:code_to_c_type_id()
        return nil
    end
    function Sem.LayoutNamed:code_to_c_type_id()
        return C.CTypeId(self.module_name, self.type_name)
    end
    function Sem.LayoutLocal:code_to_c_type_id()
        return C.CTypeId("local", self.sym.name)
    end
    function Sem.TypeLayout:append_code_to_c_type_decl(c_emission, existing, out)
        local id = self:code_to_c_type_id()
        if id == nil then return end
        local key = id.module_name .. "\0" .. id.spelling
        if existing[key] then return end
        local fields = {}
        for i = 1, #(self.fields or {}) do
            local lf = self.fields[i]
            local fty = CodeType.type_to_c(lf.ty, c_emission.c_type_projection)
            local sz, al = c_type_size_align(c_emission, fty)
            fields[#fields + 1] = C.CBackendField(C.CBackendName(lf.field_name), fty, lf.offset, sz, al)
        end
        out[#out + 1] = C.CBackendStructDecl(id, fields, self.size, self.align)
        existing[key] = true
    end
    function Sem.TypeLayout:code_to_c_layout_index_entry(out)
        local id = self:code_to_c_type_id()
        if id ~= nil then out[id.module_name .. "\0" .. id.spelling] = { size = self.size, align = self.align } end
    end

    local function collect_layout_type_decls(c_emission, existing)
        local out = {}
        local layout_facts = c_emission.layout_env
        for _, layout in ipairs((layout_facts and layout_facts.layouts) or {}) do
            layout:append_code_to_c_type_decl(c_emission, existing, out)
        end
        return out
    end

    function Code.CodeInstOp:append_code_to_c_variant_refs(record_variant_ref)
    end
    function Code.CodeInstVariantCtor:append_code_to_c_variant_refs(record_variant_ref)
        record_variant_ref(self.variant)
    end
    function Code.CodeInstVariantPayload:append_code_to_c_variant_refs(record_variant_ref)
        record_variant_ref(self.variant)
    end
    function Code.CodeTermOp:append_code_to_c_variant_refs(record_variant_ref)
    end
    function Code.CodeTermVariantSwitch:append_code_to_c_variant_refs(record_variant_ref)
        for _, case in ipairs(self.cases or {}) do record_variant_ref(case.variant) end
    end

    local function collect_variant_type_decls(c_emission, code_module, existing)
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
                    inst.op:append_code_to_c_variant_refs(record)
                end
                if block.term ~= nil then block.term.op:append_code_to_c_variant_refs(record) end
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
                    local payload_ty = c_ty(c_emission, rec.variants[i].payload_ty)
                    local vsz, val = c_type_size_align(c_emission, payload_ty)
                    union_fields[#union_fields + 1] = C.CBackendField(C.CBackendName(rec.variants[i].name), payload_ty, 0, vsz, val)
                    if vsz > psz then psz = vsz end
                    if val > pal then pal = val end
                end
                psz = math.floor((psz + pal - 1) / pal) * pal
                out[#out + 1] = C.CBackendUnionDecl(union_id, union_fields, psz, pal)
                c_emission.c_type_layouts[c_type_id_key(union_id)] = { size = psz, align = pal }
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
            layout:code_to_c_layout_index_entry(out)
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
        local c_type_projection = { code_sigs = {}, code_sig_order = {}, module_name = module_name }
        local sigs = {}
        for i = 1, #(code_module.sigs or {}) do c_type_projection.code_sigs[code_module.sigs[i].id.text] = code_module.sigs[i] end
        for i = 1, #(code_module.sigs or {}) do
            local s = code_module.sigs[i]
            local params = {}; for j = 1, #s.params do params[j] = CodeType.code_type_to_c(s.params[j], c_type_projection) end
            local result = (#s.results == 0) and C.CBackendVoid or CodeType.code_type_to_c(s.results[1], c_type_projection)
            sigs[#sigs + 1] = C.CBackendFuncSig(c_sig_id(s.id), params, result)
        end
        local c_emission = {
            module_name = module_name,
            target = CodeType.normalize_target(opts.target or opts.c_target or opts),
            c_type_projection = c_type_projection,
            sigs = {}, funcs = {}, externs = {},
            helpers_by_id = {}, helper_order = {}, helpers = {},
            layout_env = opts.layout_env,
            c_type_layouts = c_type_layout_index(opts.layout_env),
        }
        for i = 1, #(code_module.sigs or {}) do c_emission.sigs[code_module.sigs[i].id.text] = code_module.sigs[i] end
        for i = 1, #(code_module.funcs or {}) do c_emission.funcs[code_module.funcs[i].id.text] = code_module.funcs[i] end
        for i = 1, #(code_module.externs or {}) do c_emission.externs[code_module.externs[i].id.text] = code_module.externs[i] end

        local types = {}
        local existing_type_ids = {}
        for i = 1, #(code_module.types or {}) do
            types[i] = lower_type_decl(c_emission, code_module.types[i])
            local id = types[i].id
            if id ~= nil then existing_type_ids[id.module_name .. "\0" .. id.spelling] = true end
        end
        local variant_types = collect_variant_type_decls(c_emission, code_module, existing_type_ids)
        for i = 1, #variant_types do types[#types + 1] = variant_types[i] end
        local layout_types = collect_layout_type_decls(c_emission, existing_type_ids)
        for i = 1, #layout_types do types[#types + 1] = layout_types[i] end
        local globals = {}
        for i = 1, #(code_module.data or {}) do globals[#globals + 1] = lower_data(c_emission, code_module.data[i]) end
        for i = 1, #(code_module.globals or {}) do globals[#globals + 1] = lower_global(c_emission, code_module.globals[i]) end
        local externs = {}; for i = 1, #(code_module.externs or {}) do externs[i] = lower_extern(c_emission, code_module.externs[i]) end
        local funcs = {}; for i = 1, #(code_module.funcs or {}) do funcs[i] = lower_func(c_emission, code_module.funcs[i]) end
        local seen_sigs = {}
        for i = 1, #sigs do seen_sigs[sigs[i].id.text] = true end
        for i = 1, #((c_emission.c_type_projection and c_emission.c_type_projection.code_sig_order) or {}) do
            local sig = c_emission.c_type_projection.code_sig_order[i]
            if not seen_sigs[sig.id.text] then
                sigs[#sigs + 1] = sig
                seen_sigs[sig.id.text] = true
            end
        end

        return C.CBackendUnit(code_module.id.text, c_emission.target, sigs, types, globals, externs, c_emission.helper_order, funcs)
    end

    api.module = module

    T._lalin_api_cache.code_to_c = api
    return api
end

return bind_context
