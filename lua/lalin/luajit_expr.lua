local asdl = require("lalin.asdl")

local function class_name(value)
    local cls = asdl.classof(value) or value
    return tostring(cls):match("Class%((.-)%)") or tostring(cls)
end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.luajit_expr ~= nil then return T._lalin_api_cache.luajit_expr end

    local Core = T.LalinCore
    local Code = T.LalinCode
    local LJ = T.LalinLuaJIT
    local CType = require("lalin.luajit_ctype")(T)

    local api = {}

    local function vid(id)
        return LJ.LJValueId((id.text or ""):gsub("^v:", ""))
    end

    local function value_expr(id)
        return LJ.LJExprValue(vid(id))
    end

    local function local_id(id)
        return LJ.LJLocalId(id.text)
    end

    local function global_id(id)
        return LJ.LJGlobalId(id.text)
    end

    local function physical(ctx, ty)
        return CType.physical_type(ty, ctx)
    end

    local function note_value(ctx, id, ty)
        ctx.value_types = ctx.value_types or {}
        if id ~= nil and ty ~= nil then ctx.value_types[id.text] = ty end
    end

    local function value_type(ctx, id)
        return ctx.value_types and ctx.value_types[id.text] or nil
    end

    local function field_name(field)
        local cls = asdl.classof(field)
        if cls == T.LalinSem.FieldByName or cls == T.LalinSem.FieldByOffset then return field.field_name end
        return "field"
    end

    local place
    place = function(ctx, p)
        local cls = asdl.classof(p)
        if cls == Code.CodePlaceLocal then
            return LJ.LJPlaceLocal(local_id(p.local_id), physical(ctx, p.ty))
        elseif cls == Code.CodePlaceGlobal then
            return LJ.LJPlaceGlobal(global_id(p.global), physical(ctx, p.ty))
        elseif cls == Code.CodePlaceData then
            return LJ.LJPlaceData(global_id(p.data), physical(ctx, p.ty))
        elseif cls == Code.CodePlaceDeref then
            return LJ.LJPlaceDeref(value_expr(p.addr), physical(ctx, p.ty), p.align)
        elseif cls == Code.CodePlaceField then
            return LJ.LJPlaceField(place(ctx, p.base), field_name(p.field), physical(ctx, p.ty), p.offset, p.size, p.align)
        elseif cls == Code.CodePlaceIndex then
            return LJ.LJPlaceIndex(place(ctx, p.base), value_expr(p.index), physical(ctx, p.ty), p.elem_size)
        elseif cls == Code.CodePlaceBytes then
            return LJ.LJPlaceBytes(value_expr(p.base), p.offset, physical(ctx, p.ty), p.size, p.align)
        end
        error("luajit_expr: unsupported place " .. class_name(p), 2)
    end

    local function const_expr(ctx, const)
        local cls = asdl.classof(const)
        if cls == Code.CodeConstLiteral then
            return LJ.LJExprLiteral(const.literal, physical(ctx, const.ty))
        elseif cls == Code.CodeConstNull then
            return LJ.LJExprLiteral(Core.LitNil, physical(ctx, const.ty))
        elseif cls == Code.CodeConstUndef then
            return LJ.LJExprLiteral(Core.LitInt("0"), physical(ctx, const.ty))
        end
        error("luajit_expr: unsupported const " .. class_name(const), 2)
    end

    local function view_type(ctx, view)
        local ty = value_type(ctx, view)
        if asdl.classof(ty) == Code.CodeTyLease then ty = ty.base end
        if asdl.classof(ty) ~= Code.CodeTyView then
            error("luajit_expr: expected view type for " .. tostring(view.text), 3)
        end
        return ty
    end

    local function view_field_type(ctx, view, field)
        local vty = view_type(ctx, view)
        if field == "data" then return Code.CodeTyDataPtr(vty.elem) end
        if field == "len" or field == "stride" then return Code.CodeTyIndex end
        error("luajit_expr: unknown view field " .. tostring(field), 3)
    end

    local function project_view_field(ctx, view, field)
        local ty = view_field_type(ctx, view, field)
        return LJ.LJExprProjectField(value_expr(view), field, physical(ctx, ty), true), ty
    end

    local function slice_type(ctx, slice)
        local ty = value_type(ctx, slice)
        if asdl.classof(ty) == Code.CodeTyLease then ty = ty.base end
        if asdl.classof(ty) ~= Code.CodeTySlice then
            error("luajit_expr: expected slice type for " .. tostring(slice.text), 3)
        end
        return ty
    end

    local function slice_field_type(ctx, slice, field)
        local sty = slice_type(ctx, slice)
        if field == "data" then return Code.CodeTyDataPtr(sty.elem) end
        if field == "len" then return Code.CodeTyIndex end
        error("luajit_expr: unknown slice field " .. tostring(field), 3)
    end

    local function project_slice_field(ctx, slice, field)
        local ty = slice_field_type(ctx, slice, field)
        return LJ.LJExprProjectField(value_expr(slice), field, physical(ctx, ty), true), ty
    end

    local function byte_ty()
        return Code.CodeTyInt(8, Code.CodeUnsigned)
    end

    local function project_bytespan_field(ctx, span, field)
        local ty = field == "data" and Code.CodeTyDataPtr(byte_ty()) or Code.CodeTyIndex
        if field ~= "data" and field ~= "len" then error("luajit_expr: unknown byte span field " .. tostring(field), 3) end
        return LJ.LJExprProjectField(value_expr(span), field, physical(ctx, ty), true), ty
    end

    local function expr_list(ids)
        local out = {}
        for i = 1, #(ids or {}) do out[i] = value_expr(ids[i]) end
        return out
    end

    local function call_target(ctx, target)
        local cls = asdl.classof(target)
        if cls == Code.CodeCallDirect then return LJ.LJCallDirect(LJ.LJFuncId(target.func.text)) end
        if cls == Code.CodeCallExtern then return LJ.LJCallExtern(target["extern"].text) end
        if cls == Code.CodeCallIndirect then return LJ.LJCallIndirect(value_expr(target.callee), LJ.LJFuncSigId(target.sig.text)) end
        if cls == Code.CodeCallClosure then return LJ.LJCallClosure(value_expr(target.closure), LJ.LJFuncSigId(target.sig.text)) end
        error("luajit_expr: unsupported call target " .. class_name(target), 2)
    end

    local function inst_expr(ctx, k)
        local cls = asdl.classof(k)
        if cls == Code.CodeInstConst then
            return const_expr(ctx, k.const), k.const.ty
        elseif cls == Code.CodeInstAlias then
            return value_expr(k.src), k.ty
        elseif cls == Code.CodeInstUnary then
            return LJ.LJExprUnary(k.op, physical(ctx, k.ty), value_expr(k.value)), k.ty
        elseif cls == Code.CodeInstBinary then
            return LJ.LJExprIntBinary(k.op, physical(ctx, k.ty), k.semantics, value_expr(k.lhs), value_expr(k.rhs)), k.ty
        elseif cls == Code.CodeInstFloatBinary then
            return LJ.LJExprFloatBinary(k.op, physical(ctx, k.ty), k.mode, value_expr(k.lhs), value_expr(k.rhs)), k.ty
        elseif cls == Code.CodeInstCompare then
            return LJ.LJExprCompare(k.op, physical(ctx, k.operand_ty), value_expr(k.lhs), value_expr(k.rhs)), Code.CodeTyBool8
        elseif cls == Code.CodeInstCast then
            return LJ.LJExprCast(k.op, physical(ctx, k.from), physical(ctx, k.to), value_expr(k.value)), k.to
        elseif cls == Code.CodeInstSelect then
            return LJ.LJExprSelect(physical(ctx, k.ty), value_expr(k.cond), value_expr(k.then_value), value_expr(k.else_value)), k.ty
        elseif cls == Code.CodeInstIntrinsic then
            return LJ.LJExprIntrinsic(k.op, physical(ctx, k.ty), expr_list(k.args)), k.ty
        elseif cls == Code.CodeInstAddrOf then
            return LJ.LJExprAddrOfPlace(place(ctx, k.place), physical(ctx, k.ptr_ty)), k.ptr_ty
        elseif cls == Code.CodeInstGlobalRef then
            return LJ.LJExprGlobalRef(k.ref, physical(ctx, k.ptr_ty)), k.ptr_ty
        elseif cls == Code.CodeInstPtrOffset then
            return LJ.LJExprPtrOffset(physical(ctx, k.ptr_ty), value_expr(k.base), value_expr(k.index), k.elem_size, k.const_offset), k.ptr_ty
        elseif cls == Code.CodeInstLoad then
            return LJ.LJExprLoad(place(ctx, k.place), k.access), k.access.ty
        elseif cls == Code.CodeInstAggregate then
            local fields = {}
            for i = 1, #k.fields do fields[i] = LJ.LJFieldExpr(field_name(k.fields[i].field), value_expr(k.fields[i].value)) end
            return LJ.LJExprRecord(physical(ctx, k.ty), fields), k.ty
        elseif cls == Code.CodeInstArray then
            local elems = {}
            for i = 1, #k.elems do elems[i] = LJ.LJArrayExpr(k.elems[i].index, value_expr(k.elems[i].value)) end
            return LJ.LJExprArray(physical(ctx, k.ty), elems), k.ty
        elseif cls == Code.CodeInstViewMake then
            local ty = Code.CodeTyView(k.elem_ty)
            return LJ.LJExprRecord(physical(ctx, ty), {
                LJ.LJFieldExpr("data", value_expr(k.data)),
                LJ.LJFieldExpr("len", value_expr(k.len)),
                LJ.LJFieldExpr("stride", value_expr(k.stride)),
            }), ty
        elseif cls == Code.CodeInstViewData then
            return project_view_field(ctx, k.view, "data")
        elseif cls == Code.CodeInstViewLen then
            return project_view_field(ctx, k.view, "len")
        elseif cls == Code.CodeInstViewStride then
            return project_view_field(ctx, k.view, "stride")
        elseif cls == Code.CodeInstSliceMake then
            local ty = Code.CodeTySlice(k.elem_ty)
            return LJ.LJExprRecord(physical(ctx, ty), {
                LJ.LJFieldExpr("data", value_expr(k.data)),
                LJ.LJFieldExpr("len", value_expr(k.len)),
            }), ty
        elseif cls == Code.CodeInstSliceData then
            return project_slice_field(ctx, k.slice, "data")
        elseif cls == Code.CodeInstSliceLen then
            return project_slice_field(ctx, k.slice, "len")
        elseif cls == Code.CodeInstByteSpanMake then
            return LJ.LJExprRecord(physical(ctx, Code.CodeTyByteSpan), {
                LJ.LJFieldExpr("data", value_expr(k.data)),
                LJ.LJFieldExpr("len", value_expr(k.len)),
            }), Code.CodeTyByteSpan
        elseif cls == Code.CodeInstByteSpanData then
            return project_bytespan_field(ctx, k.span, "data")
        elseif cls == Code.CodeInstByteSpanLen then
            return project_bytespan_field(ctx, k.span, "len")
        elseif cls == Code.CodeInstClosure then
            return LJ.LJExprClosure(physical(ctx, k.ty), value_expr(k.fn), value_expr(k.ctx), LJ.LJFuncSigId(k.sig.text)), k.ty
        elseif cls == Code.CodeInstVariantCtor then
            return LJ.LJExprVariantCtor(physical(ctx, k.ty), k.variant, k.payload and value_expr(k.payload) or nil), k.ty
        elseif cls == Code.CodeInstVariantTag then
            return LJ.LJExprVariantTag(physical(ctx, k.tag_ty), value_expr(k.value)), k.tag_ty
        elseif cls == Code.CodeInstVariantPayload then
            local ty = k.variant.payload_ty or Code.CodeTyVoid
            return LJ.LJExprVariantPayload(physical(ctx, ty), k.variant, value_expr(k.value)), ty
        elseif cls == Code.CodeInstCall then
            local results = ctx.code_sigs and ctx.code_sigs[k.sig.text] and ctx.code_sigs[k.sig.text].results or nil
            local result_ty = results and #results == 1 and results[1] ~= Code.CodeTyVoid and results[1] or nil
            return LJ.LJExprCall(call_target(ctx, k.target), LJ.LJFuncSigId(k.sig.text), expr_list(k.args), result_ty and physical(ctx, result_ty) or nil), result_ty or Code.CodeTyVoid
        elseif cls == Code.CodeInstAtomicLoad then
            return LJ.LJExprAtomicLoad(place(ctx, k.place), k.access, k.ordering), k.access.ty
        elseif cls == Code.CodeInstAtomicRmw then
            return LJ.LJExprAtomicRmw(k.op, place(ctx, k.place), value_expr(k.value), k.access, k.ordering, physical(ctx, k.access.ty)), k.access.ty
        elseif cls == Code.CodeInstAtomicCas then
            return LJ.LJExprAtomicCas(place(ctx, k.place), value_expr(k.expected), value_expr(k.replacement), k.access, k.ordering, physical(ctx, k.access.ty)), k.access.ty
        end
        error("luajit_expr: unsupported expression instruction " .. class_name(k), 2)
    end

    local function inst_to_stmt(ctx, inst)
        local k = inst.op
        local cls = asdl.classof(k)
        if cls == Code.CodeInstStore then
            return LJ.LJStmtStore(place(ctx, k.place), value_expr(k.value), physical(ctx, k.access.ty), k.access)
        elseif cls == Code.CodeInstCall and rawget(k, "dst") == nil then
            return LJ.LJStmtCall(call_target(ctx, k.target), LJ.LJFuncSigId(k.sig.text), expr_list(k.args))
        elseif cls == Code.CodeInstIntrinsic and rawget(k, "dst") == nil then
            return LJ.LJStmtIntrinsic(k.op, physical(ctx, k.ty), expr_list(k.args))
        elseif cls == Code.CodeInstAtomicStore then
            return LJ.LJStmtAtomicStore(place(ctx, k.place), value_expr(k.value), k.access, k.ordering)
        elseif cls == Code.CodeInstAtomicFence then
            return LJ.LJStmtAtomicFence(k.ordering)
        end
        local expr, ty = inst_expr(ctx, k)
        local dst = rawget(k, "dst")
        if dst == nil then error("luajit_expr: instruction has no value destination " .. class_name(k), 2) end
        note_value(ctx, dst, ty)
        return LJ.LJStmtLet(vid(dst), physical(ctx, ty), expr)
    end

    api.value_id = vid
    api.value_expr = value_expr
    api.place = place
    api.const_expr = const_expr
    api.inst_expr = inst_expr
    api.inst_to_stmt = inst_to_stmt

    T._lalin_api_cache.luajit_expr = api
    return api
end

return bind_context
