local pvm = require("moonlift.pvm")

local function class_name(x)
    local cls = pvm.classof(x) or x
    return tostring(cls):match("Class%((.-)%)") or tostring(cls)
end

local function is_power_of_two(n)
    if type(n) ~= "number" or n < 1 or n % 1 ~= 0 then return false end
    while n > 1 do
        if n % 2 ~= 0 then return false end
        n = n / 2
    end
    return true
end

local function bind_context(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.code_validate ~= nil then return T._moonlift_api_cache.code_validate end

    local Code = T.MoonCode

    local api = {}

    local function add_issue(ctx, issue)
        ctx.issues[#ctx.issues + 1] = issue
        local collector = ctx.collector
        if collector and collector.emit then
            pcall(function() collector:emit(issue, "code") end)
        end
    end

    local function type_eq(a, b, seen)
        if a == b then return true end
        local ac, bc = pvm.classof(a), pvm.classof(b)
        if ac == Code.CodeTyLease then return type_eq(a.base, b, seen) end
        if bc == Code.CodeTyLease then return type_eq(a, b.base, seen) end
        if ac ~= bc then
            -- Opaque data pointers are intentionally compatible with typed data pointers.
            if ac == Code.CodeTyDataPtr and bc == Code.CodeTyDataPtr then return a.pointee == nil or b.pointee == nil end
            return false
        end
        if ac == Code.CodeTyDataPtr and (a.pointee == nil or b.pointee == nil) then return true end
        if ac == nil then return a == b end
        seen = seen or {}
        local key = tostring(a) .. "|" .. tostring(b)
        if seen[key] then return true end
        seen[key] = true
        local fields = ac.__fields or {}
        for i = 1, #fields do
            local name = fields[i].name
            local av, bv = a[name], b[name]
            if type(av) == "table" and pvm.classof(av) == nil then
                if type(bv) ~= "table" or #av ~= #bv then return false end
                for j = 1, #av do if not type_eq(av[j], bv[j], seen) then return false end end
            elseif type(av) == "table" and pvm.classof(av) ~= nil then
                if not type_eq(av, bv, seen) then return false end
            else
                if av ~= bv then return false end
            end
        end
        return true
    end

    local function is_bool(ty)
        return ty == Code.CodeTyBool8
    end

    local function is_integer_like(ty)
        local cls = pvm.classof(ty)
        return ty == Code.CodeTyIndex or cls == Code.CodeTyInt
    end

    local function type_uses_code_sig(ty, ctx)
        local cls = pvm.classof(ty)
        if cls == Code.CodeTyCodePtr or cls == Code.CodeTyClosure then
            if ctx.sigs[ty.sig.text] == nil then add_issue(ctx, Code.CodeIssueMissingSig(ty.sig)) end
        elseif cls == Code.CodeTyDataPtr and ty.pointee ~= nil then
            type_uses_code_sig(ty.pointee, ctx)
        elseif cls == Code.CodeTyArray or cls == Code.CodeTySlice or cls == Code.CodeTyView or cls == Code.CodeTyVector then
            type_uses_code_sig(ty.elem, ctx)
        elseif cls == Code.CodeTyLease then
            type_uses_code_sig(ty.base, ctx)
        end
    end

    local function expect_type(ctx, site, expected, actual)
        if expected ~= nil and actual ~= nil and not type_eq(expected, actual) then
            add_issue(ctx, Code.CodeIssueTypeMismatch(site, expected, actual))
            return false
        end
        return true
    end

    local function expect_bool(ctx, site, actual)
        if actual ~= nil and not is_bool(actual) then
            add_issue(ctx, Code.CodeIssueTypeMismatch(site, Code.CodeTyBool8, actual))
        end
    end

    local function index_by(ctx, items, key_fn, dup_issue_fn)
        local by = {}
        for i = 1, #(items or {}) do
            local item = items[i]
            local key, ref = key_fn(item)
            if by[key] ~= nil then add_issue(ctx, dup_issue_fn(ref)) else by[key] = item end
        end
        return by
    end

    local function check_align(ctx, site, align, access)
        if align ~= nil and not is_power_of_two(align) then
            if access ~= nil then
                add_issue(ctx, Code.CodeIssueInvalidMemoryAccess(site, access))
            else
                add_issue(ctx, Code.CodeIssueUnsupportedSource(site, "invalid alignment " .. tostring(align)))
            end
            return false
        end
        return true
    end

    local function global_ref_exists(ctx, ref)
        local cls = pvm.classof(ref)
        if cls == Code.CodeGlobalRefData then
            if ctx.data[ref.data.text] == nil then add_issue(ctx, Code.CodeIssueMissingData(ref.data)); return nil end
            return ctx.data[ref.data.text]
        elseif cls == Code.CodeGlobalRefGlobal then
            if ctx.globals[ref.global.text] == nil then add_issue(ctx, Code.CodeIssueMissingGlobal(ref.global)); return nil end
            return ctx.globals[ref.global.text]
        elseif cls == Code.CodeGlobalRefFunc then
            if ctx.funcs[ref.func.text] == nil then add_issue(ctx, Code.CodeIssueMissingFunc(ref.func)); return nil end
            return ctx.funcs[ref.func.text]
        elseif cls == Code.CodeGlobalRefExtern then
            if ctx.externs[ref["extern"].text] == nil then add_issue(ctx, Code.CodeIssueMissingExtern(ref["extern"])); return nil end
            return ctx.externs[ref["extern"].text]
        end
        return nil
    end

    local function check_sig_ref(ctx, sig_id)
        local sig = sig_id and ctx.sigs[sig_id.text] or nil
        if sig_id and sig == nil then add_issue(ctx, Code.CodeIssueMissingSig(sig_id)) end
        return sig
    end

    local function check_memory_access(ctx, site, access, expected_mode)
        if access == nil then return end
        check_align(ctx, site, access.align, access)
        if expected_mode == "read" and access.mode ~= Code.CodeMemoryRead and access.mode ~= Code.CodeMemoryReadWrite then
            add_issue(ctx, Code.CodeIssueInvalidMemoryAccess(site, access))
        elseif expected_mode == "write" and access.mode ~= Code.CodeMemoryWrite and access.mode ~= Code.CodeMemoryReadWrite then
            add_issue(ctx, Code.CodeIssueInvalidMemoryAccess(site, access))
        end
        type_uses_code_sig(access.ty, ctx)
    end

    local function data_init_extent(init)
        local cls = pvm.classof(init)
        if cls == Code.CodeDataZero then return init.offset, init.size end
        if cls == Code.CodeDataBytes then return init.offset, #init.bytes end
        if cls == Code.CodeDataScalar then return init.offset, 1 end
        if cls == Code.CodeDataReloc then return init.reloc.offset, 8 end
        return 0, 0
    end

    local function check_init_bounds(ctx, site, container_id, size, init)
        local off, n = data_init_extent(init)
        if type(off) ~= "number" or off < 0 or type(n) ~= "number" or n < 0 or (size ~= nil and off + n > size) then
            add_issue(ctx, Code.CodeIssueUnsupportedSource(site .. ":" .. container_id.text, "data initializer out of bounds"))
        end
    end

    local function check_reloc(ctx, reloc)
        if reloc == nil then return end
        if ctx.relocs[reloc.id.text] then add_issue(ctx, Code.CodeIssueInvalidReloc(reloc, "duplicate reloc id")) end
        ctx.relocs[reloc.id.text] = true
        if type(reloc.offset) ~= "number" or reloc.offset < 0 or reloc.offset % 1 ~= 0 then
            add_issue(ctx, Code.CodeIssueInvalidReloc(reloc, "invalid relocation offset"))
        end
        global_ref_exists(ctx, reloc.target)
    end

    local function value_type(fctx, ctx, value)
        local ty = value and fctx.values[value.text]
        if value ~= nil and ty == nil then add_issue(ctx, Code.CodeIssueMissingValue(value)) end
        return ty
    end

    local function view_elem_type(fctx, ctx, site, view)
        local vty = value_type(fctx, ctx, view)
        local cls = pvm.classof(vty)
        if cls == Code.CodeTyLease then
            vty = vty.base
            cls = pvm.classof(vty)
        end
        if vty ~= nil and cls ~= Code.CodeTyView then
            add_issue(ctx, Code.CodeIssueTypeMismatch(site, Code.CodeTyView(Code.CodeTyVoid), vty))
            return nil
        end
        return vty and vty.elem or nil
    end

    local function slice_elem_type(fctx, ctx, site, slice)
        local sty = value_type(fctx, ctx, slice)
        local cls = pvm.classof(sty)
        if cls == Code.CodeTyLease then
            sty = sty.base
            cls = pvm.classof(sty)
        end
        if sty ~= nil and cls ~= Code.CodeTySlice then
            add_issue(ctx, Code.CodeIssueTypeMismatch(site, Code.CodeTySlice(Code.CodeTyVoid), sty))
            return nil
        end
        return sty and sty.elem or nil
    end

    local function byte_span_type(fctx, ctx, site, span)
        local sty = value_type(fctx, ctx, span)
        local cls = pvm.classof(sty)
        if cls == Code.CodeTyLease then
            sty = sty.base
            cls = pvm.classof(sty)
        end
        if sty ~= nil and sty ~= Code.CodeTyByteSpan and cls ~= Code.CodeTyByteSpan then
            add_issue(ctx, Code.CodeIssueTypeMismatch(site, Code.CodeTyByteSpan, sty))
            return false
        end
        return true
    end

    local place_type
    place_type = function(ctx, fctx, place, site)
        local cls = pvm.classof(place)
        if cls == Code.CodePlaceLocal then
            local local_id = place.local_id
            local local_ = fctx.locals[local_id.text]
            if local_ == nil then
                add_issue(ctx, Code.CodeIssueUnsupportedSource(site, "missing local " .. local_id.text))
            else
                expect_type(ctx, site .. ":local", local_.ty, place.ty)
            end
            return place.ty
        elseif cls == Code.CodePlaceGlobal then
            local global = ctx.globals[place.global.text]
            if global == nil then add_issue(ctx, Code.CodeIssueMissingGlobal(place.global))
            else expect_type(ctx, site .. ":global", global.ty, place.ty) end
            return place.ty
        elseif cls == Code.CodePlaceData then
            if ctx.data[place.data.text] == nil then add_issue(ctx, Code.CodeIssueMissingData(place.data)) end
            return place.ty
        elseif cls == Code.CodePlaceDeref then
            local aty = value_type(fctx, ctx, place.addr)
            local ac = pvm.classof(aty)
            if aty ~= nil and ac ~= Code.CodeTyDataPtr then
                if ac == Code.CodeTyCodePtr then add_issue(ctx, Code.CodeIssueDataCodePointerConfusion(site .. ":deref", aty))
                else add_issue(ctx, Code.CodeIssueTypeMismatch(site .. ":deref", Code.CodeTyDataPtr(nil), aty)) end
            end
            check_align(ctx, site .. ":deref", place.align, nil)
            return place.ty
        elseif cls == Code.CodePlaceField then
            place_type(ctx, fctx, place.base, site .. ":field.base")
            check_align(ctx, site .. ":field", place.align, nil)
            if place.offset < 0 or (place.size ~= nil and place.size < 0) then add_issue(ctx, Code.CodeIssueUnsupportedSource(site, "invalid field byte range")) end
            return place.ty
        elseif cls == Code.CodePlaceIndex then
            place_type(ctx, fctx, place.base, site .. ":index.base")
            local ity = value_type(fctx, ctx, place.index)
            if ity ~= nil and not is_integer_like(ity) then add_issue(ctx, Code.CodeIssueTypeMismatch(site .. ":index", Code.CodeTyIndex, ity)) end
            if type(place.elem_size) ~= "number" or place.elem_size <= 0 then add_issue(ctx, Code.CodeIssueUnsupportedSource(site, "invalid element size")) end
            return place.ty
        elseif cls == Code.CodePlaceBytes then
            local bty = value_type(fctx, ctx, place.base)
            local bc = pvm.classof(bty)
            if bty ~= nil and bc ~= Code.CodeTyDataPtr then
                if bc == Code.CodeTyCodePtr then add_issue(ctx, Code.CodeIssueDataCodePointerConfusion(site .. ":bytes", bty))
                else add_issue(ctx, Code.CodeIssueTypeMismatch(site .. ":bytes", Code.CodeTyDataPtr(nil), bty)) end
            end
            check_align(ctx, site .. ":bytes", place.align, nil)
            if place.offset < 0 or place.size < 0 then add_issue(ctx, Code.CodeIssueUnsupportedSource(site, "invalid byte place range")) end
            return place.ty
        end
        add_issue(ctx, Code.CodeIssueUnsupportedSource(site, "unsupported place " .. class_name(place)))
        return nil
    end

    local function check_transfer(ctx, fctx, site, dest, args)
        local block = fctx.blocks[dest.text]
        if block == nil then add_issue(ctx, Code.CodeIssueMissingBlock(dest)); return end
        if #args ~= #block.params then add_issue(ctx, Code.CodeIssueJumpArity(dest, #block.params, #args)) end
        local n = math.min(#args, #block.params)
        for i = 1, n do
            local aty = value_type(fctx, ctx, args[i])
            if aty ~= nil and not type_eq(block.params[i].ty, aty) then
                add_issue(ctx, Code.CodeIssueBlockParamMismatch(dest, i, block.params[i].ty, aty))
            end
        end
    end

    local function check_call(ctx, fctx, site, sig_id, target, args, dst)
        local sig = check_sig_ref(ctx, sig_id)
        local tcls = pvm.classof(target)
        if tcls == Code.CodeCallDirect then
            local fn = ctx.funcs[target.func.text]
            if fn == nil then add_issue(ctx, Code.CodeIssueMissingFunc(target.func))
            elseif sig_id ~= nil and fn.sig ~= sig_id then add_issue(ctx, Code.CodeIssueTypeMismatch(site .. ":direct-sig", Code.CodeTyCodePtr(fn.sig), Code.CodeTyCodePtr(sig_id))) end
        elseif tcls == Code.CodeCallExtern then
            local ex = ctx.externs[target["extern"].text]
            if ex == nil then add_issue(ctx, Code.CodeIssueMissingExtern(target["extern"]))
            elseif sig_id ~= nil and ex.sig ~= sig_id then add_issue(ctx, Code.CodeIssueTypeMismatch(site .. ":extern-sig", Code.CodeTyCodePtr(ex.sig), Code.CodeTyCodePtr(sig_id))) end
        elseif tcls == Code.CodeCallIndirect then
            check_sig_ref(ctx, target.sig)
            if sig_id ~= nil and target.sig ~= sig_id then add_issue(ctx, Code.CodeIssueTypeMismatch(site .. ":indirect-sig", Code.CodeTyCodePtr(target.sig), Code.CodeTyCodePtr(sig_id))) end
            local callee_ty = value_type(fctx, ctx, target.callee)
            if callee_ty ~= nil then
                if pvm.classof(callee_ty) == Code.CodeTyCodePtr then
                    if target.sig ~= callee_ty.sig then add_issue(ctx, Code.CodeIssueTypeMismatch(site .. ":callee", Code.CodeTyCodePtr(target.sig), callee_ty)) end
                elseif pvm.classof(callee_ty) == Code.CodeTyDataPtr then
                    add_issue(ctx, Code.CodeIssueDataCodePointerConfusion(site .. ":callee", callee_ty))
                else
                    add_issue(ctx, Code.CodeIssueTypeMismatch(site .. ":callee", Code.CodeTyCodePtr(target.sig), callee_ty))
                end
            end
        elseif tcls == Code.CodeCallClosure then
            check_sig_ref(ctx, target.sig)
            if sig_id ~= nil and target.sig ~= sig_id then add_issue(ctx, Code.CodeIssueTypeMismatch(site .. ":closure-sig", Code.CodeTyClosure(target.sig), Code.CodeTyClosure(sig_id))) end
            local closure_ty = value_type(fctx, ctx, target.closure)
            if closure_ty ~= nil then
                if pvm.classof(closure_ty) == Code.CodeTyClosure then
                    if target.sig ~= closure_ty.sig then add_issue(ctx, Code.CodeIssueTypeMismatch(site .. ":closure", Code.CodeTyClosure(target.sig), closure_ty)) end
                else
                    add_issue(ctx, Code.CodeIssueTypeMismatch(site .. ":closure", Code.CodeTyClosure(target.sig), closure_ty))
                end
            end
        else
            add_issue(ctx, Code.CodeIssueUnsupportedSource(site, "unsupported call target " .. class_name(target)))
        end
        if sig == nil then return end
        if #args ~= #sig.params then add_issue(ctx, Code.CodeIssueCallArity(sig.id, #sig.params, #args)) end
        local n = math.min(#args, #sig.params)
        for i = 1, n do
            local aty = value_type(fctx, ctx, args[i])
            if aty ~= nil then expect_type(ctx, site .. ":arg" .. tostring(i), sig.params[i], aty) end
        end
        if #sig.results == 0 then
            if dst ~= nil then add_issue(ctx, Code.CodeIssueTypeMismatch(site .. ":result", Code.CodeTyVoid, value_type(fctx, ctx, dst) or Code.CodeTyVoid)) end
        elseif #sig.results == 1 then
            if dst == nil then
                add_issue(ctx, Code.CodeIssueTypeMismatch(site .. ":result", sig.results[1], Code.CodeTyVoid))
            else
                local dty = value_type(fctx, ctx, dst)
                if dty ~= nil then expect_type(ctx, site .. ":result", sig.results[1], dty) end
            end
        else
            add_issue(ctx, Code.CodeIssueUnsupportedSource(site, "multi-result call cannot be represented by one dst"))
        end
    end

    local function register_dst(ctx, fctx, id, ty)
        if id == nil then return end
        if fctx.values[id.text] ~= nil then add_issue(ctx, Code.CodeIssueDuplicateValue(id)) end
        fctx.values[id.text] = ty
        type_uses_code_sig(ty, ctx)
    end

    local function inst_dst_type(ctx, fctx, kind)
        local cls = pvm.classof(kind)
        if cls == Code.CodeInstConst then return kind.dst, kind.const.ty
        elseif cls == Code.CodeInstAlias then return kind.dst, kind.ty
        elseif cls == Code.CodeInstUnary then return kind.dst, kind.ty
        elseif cls == Code.CodeInstBinary then return kind.dst, kind.ty
        elseif cls == Code.CodeInstFloatBinary then return kind.dst, kind.ty
        elseif cls == Code.CodeInstCompare then return kind.dst, Code.CodeTyBool8
        elseif cls == Code.CodeInstCast then return kind.dst, kind.to
        elseif cls == Code.CodeInstSelect then return kind.dst, kind.ty
        elseif cls == Code.CodeInstIntrinsic then return kind.dst, kind.ty
        elseif cls == Code.CodeInstAddrOf then return kind.dst, kind.ptr_ty
        elseif cls == Code.CodeInstGlobalRef then return kind.dst, kind.ptr_ty
        elseif cls == Code.CodeInstPtrOffset then return kind.dst, kind.ptr_ty
        elseif cls == Code.CodeInstLoad then return kind.dst, kind.access.ty
        elseif cls == Code.CodeInstAggregate then return kind.dst, kind.ty
        elseif cls == Code.CodeInstArray then return kind.dst, kind.ty
        elseif cls == Code.CodeInstViewMake then return kind.dst, Code.CodeTyView(kind.elem_ty)
        elseif cls == Code.CodeInstViewData then
            local elem = view_elem_type(fctx, ctx, "view.data", kind.view)
            return kind.dst, Code.CodeTyDataPtr(elem)
        elseif cls == Code.CodeInstViewLen then return kind.dst, Code.CodeTyIndex
        elseif cls == Code.CodeInstViewStride then return kind.dst, Code.CodeTyIndex
        elseif cls == Code.CodeInstSliceMake then return kind.dst, Code.CodeTySlice(kind.elem_ty)
        elseif cls == Code.CodeInstSliceData then
            local elem = slice_elem_type(fctx, ctx, "slice.data", kind.slice)
            return kind.dst, Code.CodeTyDataPtr(elem)
        elseif cls == Code.CodeInstSliceLen then return kind.dst, Code.CodeTyIndex
        elseif cls == Code.CodeInstByteSpanMake then return kind.dst, Code.CodeTyByteSpan
        elseif cls == Code.CodeInstByteSpanData then return kind.dst, Code.CodeTyDataPtr(Code.CodeTyInt(8, Code.CodeUnsigned))
        elseif cls == Code.CodeInstByteSpanLen then return kind.dst, Code.CodeTyIndex
        elseif cls == Code.CodeInstClosure then return kind.dst, kind.ty
        elseif cls == Code.CodeInstVariantCtor then return kind.dst, kind.ty
        elseif cls == Code.CodeInstVariantTag then return kind.dst, kind.tag_ty
        elseif cls == Code.CodeInstVariantPayload then return kind.dst, kind.variant.payload_ty
        elseif cls == Code.CodeInstCall then
            return nil, nil -- checked after signature lookup
        elseif cls == Code.CodeInstAtomicLoad then return kind.dst, kind.access.ty
        elseif cls == Code.CodeInstAtomicRmw then return kind.dst, kind.access.ty
        elseif cls == Code.CodeInstAtomicCas then return kind.dst, kind.access.ty
        end
        return nil, nil
    end

    local function register_function_defs(ctx, fctx, func)
        for i = 1, #(func.params or {}) do register_dst(ctx, fctx, func.params[i].value, func.params[i].ty) end
        for i = 1, #(func.locals or {}) do
            local local_ = func.locals[i]
            if fctx.locals[local_.id.text] ~= nil then add_issue(ctx, Code.CodeIssueUnsupportedSource("func:" .. func.name, "duplicate local " .. local_.id.text)) end
            fctx.locals[local_.id.text] = local_
            type_uses_code_sig(local_.ty, ctx)
        end
        fctx.blocks = index_by(ctx, func.blocks, function(b) return b.id.text, b.id end, function(id) return Code.CodeIssueDuplicateBlock(id) end)
        for i = 1, #(func.blocks or {}) do
            local block = func.blocks[i]
            if block.term == nil then add_issue(ctx, Code.CodeIssueUnterminatedBlock(block.id)) end
            if block.term ~= nil then
                if fctx.terms[block.term.id.text] ~= nil then add_issue(ctx, Code.CodeIssueDuplicateTerm(block.term.id)) end
                fctx.terms[block.term.id.text] = true
            end
            for j = 1, #(block.params or {}) do register_dst(ctx, fctx, block.params[j].value, block.params[j].ty) end
            for j = 1, #(block.insts or {}) do
                local inst = block.insts[j]
                if fctx.insts[inst.id.text] ~= nil then add_issue(ctx, Code.CodeIssueDuplicateInst(inst.id)) end
                fctx.insts[inst.id.text] = true
                local dst, ty = inst_dst_type(ctx, fctx, inst.kind)
                if pvm.classof(inst.kind) == Code.CodeInstCall then
                    local sig = inst.kind.sig and ctx.sigs[inst.kind.sig.text] or nil
                    if sig ~= nil and #sig.results == 1 then dst, ty = inst.kind.dst, sig.results[1] end
                end
                if dst ~= nil then register_dst(ctx, fctx, dst, ty) end
            end
        end
    end

    local function check_inst(ctx, fctx, func, block, inst)
        local site = "func:" .. func.name .. ":block:" .. block.name .. ":inst:" .. inst.id.text
        local k = inst.kind
        local cls = pvm.classof(k)
        if cls == Code.CodeInstConst then
            type_uses_code_sig(k.const.ty, ctx)
        elseif cls == Code.CodeInstAlias then
            expect_type(ctx, site .. ":alias", k.ty, value_type(fctx, ctx, k.src))
        elseif cls == Code.CodeInstUnary then
            expect_type(ctx, site .. ":unary", k.ty, value_type(fctx, ctx, k.value))
        elseif cls == Code.CodeInstBinary or cls == Code.CodeInstFloatBinary then
            expect_type(ctx, site .. ":lhs", k.ty, value_type(fctx, ctx, k.lhs))
            expect_type(ctx, site .. ":rhs", k.ty, value_type(fctx, ctx, k.rhs))
        elseif cls == Code.CodeInstCompare then
            expect_type(ctx, site .. ":lhs", k.operand_ty, value_type(fctx, ctx, k.lhs))
            expect_type(ctx, site .. ":rhs", k.operand_ty, value_type(fctx, ctx, k.rhs))
        elseif cls == Code.CodeInstCast then
            expect_type(ctx, site .. ":cast", k.from, value_type(fctx, ctx, k.value))
        elseif cls == Code.CodeInstSelect then
            expect_bool(ctx, site .. ":cond", value_type(fctx, ctx, k.cond))
            expect_type(ctx, site .. ":then", k.ty, value_type(fctx, ctx, k.then_value))
            expect_type(ctx, site .. ":else", k.ty, value_type(fctx, ctx, k.else_value))
        elseif cls == Code.CodeInstIntrinsic then
            for i = 1, #k.args do value_type(fctx, ctx, k.args[i]) end
        elseif cls == Code.CodeInstAddrOf then
            local pty = place_type(ctx, fctx, k.place, site .. ":addr_of")
            if pvm.classof(k.ptr_ty) ~= Code.CodeTyDataPtr then add_issue(ctx, Code.CodeIssueDataCodePointerConfusion(site .. ":addr_of", k.ptr_ty))
            elseif pty ~= nil and k.ptr_ty.pointee ~= nil then expect_type(ctx, site .. ":addr_of", k.ptr_ty.pointee, pty) end
        elseif cls == Code.CodeInstGlobalRef then
            local target = global_ref_exists(ctx, k.ref)
            local rcls = pvm.classof(k.ref)
            if rcls == Code.CodeGlobalRefFunc or rcls == Code.CodeGlobalRefExtern then
                local sig = target and target.sig or nil
                local expected = sig and Code.CodeTyCodePtr(sig) or nil
                if pvm.classof(k.ptr_ty) ~= Code.CodeTyCodePtr then add_issue(ctx, Code.CodeIssueDataCodePointerConfusion(site .. ":global_ref", k.ptr_ty))
                elseif expected ~= nil then expect_type(ctx, site .. ":global_ref", expected, k.ptr_ty) end
            else
                if pvm.classof(k.ptr_ty) ~= Code.CodeTyDataPtr then add_issue(ctx, Code.CodeIssueDataCodePointerConfusion(site .. ":global_ref", k.ptr_ty)) end
            end
        elseif cls == Code.CodeInstPtrOffset then
            if pvm.classof(k.ptr_ty) ~= Code.CodeTyDataPtr then add_issue(ctx, Code.CodeIssueDataCodePointerConfusion(site .. ":ptr_offset", k.ptr_ty)) end
            local bty = value_type(fctx, ctx, k.base)
            if bty ~= nil and pvm.classof(bty) ~= Code.CodeTyDataPtr then add_issue(ctx, Code.CodeIssueTypeMismatch(site .. ":base", Code.CodeTyDataPtr(nil), bty)) end
            local ity = value_type(fctx, ctx, k.index)
            if ity ~= nil and not is_integer_like(ity) then add_issue(ctx, Code.CodeIssueTypeMismatch(site .. ":index", Code.CodeTyIndex, ity)) end
            if k.elem_size <= 0 then add_issue(ctx, Code.CodeIssueUnsupportedSource(site, "invalid element size")) end
        elseif cls == Code.CodeInstLoad then
            local pty = place_type(ctx, fctx, k.place, site .. ":load")
            check_memory_access(ctx, site .. ":load", k.access, "read")
            if pty ~= nil then expect_type(ctx, site .. ":load", k.access.ty, pty) end
        elseif cls == Code.CodeInstStore then
            local pty = place_type(ctx, fctx, k.place, site .. ":store")
            check_memory_access(ctx, site .. ":store", k.access, "write")
            if pty ~= nil then expect_type(ctx, site .. ":store.place", k.access.ty, pty) end
            expect_type(ctx, site .. ":store.value", k.access.ty, value_type(fctx, ctx, k.value))
        elseif cls == Code.CodeInstAggregate then
            for i = 1, #k.fields do value_type(fctx, ctx, k.fields[i].value) end
        elseif cls == Code.CodeInstArray then
            for i = 1, #k.elems do value_type(fctx, ctx, k.elems[i].value) end
        elseif cls == Code.CodeInstViewMake then
            type_uses_code_sig(k.elem_ty, ctx)
            local expected_data_ty = Code.CodeTyDataPtr(k.elem_ty)
            local dty = value_type(fctx, ctx, k.data)
            if dty ~= nil and pvm.classof(dty) ~= Code.CodeTyDataPtr then
                add_issue(ctx, Code.CodeIssueTypeMismatch(site .. ":view.data", Code.CodeTyDataPtr(nil), dty))
            elseif dty ~= nil and dty.pointee ~= nil then
                expect_type(ctx, site .. ":view.data", expected_data_ty, dty)
            end
            local lty = value_type(fctx, ctx, k.len)
            if lty ~= nil and not is_integer_like(lty) then add_issue(ctx, Code.CodeIssueTypeMismatch(site .. ":view.len", Code.CodeTyIndex, lty)) end
            local sty = value_type(fctx, ctx, k.stride)
            if sty ~= nil and not is_integer_like(sty) then add_issue(ctx, Code.CodeIssueTypeMismatch(site .. ":view.stride", Code.CodeTyIndex, sty)) end
        elseif cls == Code.CodeInstViewData then
            local elem = view_elem_type(fctx, ctx, site .. ":view.data", k.view)
            if elem ~= nil then type_uses_code_sig(Code.CodeTyDataPtr(elem), ctx) end
        elseif cls == Code.CodeInstViewLen or cls == Code.CodeInstViewStride then
            view_elem_type(fctx, ctx, site .. ":view", k.view)
        elseif cls == Code.CodeInstSliceMake then
            type_uses_code_sig(k.elem_ty, ctx)
            local expected_data_ty = Code.CodeTyDataPtr(k.elem_ty)
            local dty = value_type(fctx, ctx, k.data)
            if dty ~= nil and pvm.classof(dty) ~= Code.CodeTyDataPtr then
                add_issue(ctx, Code.CodeIssueTypeMismatch(site .. ":slice.data", Code.CodeTyDataPtr(nil), dty))
            elseif dty ~= nil and dty.pointee ~= nil then
                expect_type(ctx, site .. ":slice.data", expected_data_ty, dty)
            end
            local lty = value_type(fctx, ctx, k.len)
            if lty ~= nil and not is_integer_like(lty) then add_issue(ctx, Code.CodeIssueTypeMismatch(site .. ":slice.len", Code.CodeTyIndex, lty)) end
        elseif cls == Code.CodeInstSliceData then
            local elem = slice_elem_type(fctx, ctx, site .. ":slice.data", k.slice)
            if elem ~= nil then type_uses_code_sig(Code.CodeTyDataPtr(elem), ctx) end
        elseif cls == Code.CodeInstSliceLen then
            slice_elem_type(fctx, ctx, site .. ":slice", k.slice)
        elseif cls == Code.CodeInstByteSpanMake then
            local expected_data_ty = Code.CodeTyDataPtr(Code.CodeTyInt(8, Code.CodeUnsigned))
            local dty = value_type(fctx, ctx, k.data)
            if dty ~= nil and pvm.classof(dty) ~= Code.CodeTyDataPtr then
                add_issue(ctx, Code.CodeIssueTypeMismatch(site .. ":bytespan.data", Code.CodeTyDataPtr(nil), dty))
            elseif dty ~= nil and dty.pointee ~= nil then
                expect_type(ctx, site .. ":bytespan.data", expected_data_ty, dty)
            end
            local lty = value_type(fctx, ctx, k.len)
            if lty ~= nil and not is_integer_like(lty) then add_issue(ctx, Code.CodeIssueTypeMismatch(site .. ":bytespan.len", Code.CodeTyIndex, lty)) end
        elseif cls == Code.CodeInstByteSpanData then
            byte_span_type(fctx, ctx, site .. ":bytespan.data", k.span)
        elseif cls == Code.CodeInstByteSpanLen then
            byte_span_type(fctx, ctx, site .. ":bytespan", k.span)
        elseif cls == Code.CodeInstClosure then
            check_sig_ref(ctx, k.sig)
            if pvm.classof(k.ty) ~= Code.CodeTyClosure then add_issue(ctx, Code.CodeIssueTypeMismatch(site .. ":closure", Code.CodeTyClosure(k.sig), k.ty))
            elseif k.ty.sig ~= k.sig then add_issue(ctx, Code.CodeIssueTypeMismatch(site .. ":closure", Code.CodeTyClosure(k.sig), k.ty)) end
            expect_type(ctx, site .. ":closure.fn", Code.CodeTyCodePtr(k.sig), value_type(fctx, ctx, k.fn))
            local cty = value_type(fctx, ctx, k.ctx)
            if cty ~= nil and pvm.classof(cty) ~= Code.CodeTyDataPtr then add_issue(ctx, Code.CodeIssueTypeMismatch(site .. ":closure.ctx", Code.CodeTyDataPtr(nil), cty)) end
        elseif cls == Code.CodeInstVariantCtor then
            if k.payload ~= nil then
                if k.variant.payload_ty == nil then add_issue(ctx, Code.CodeIssueTypeMismatch(site .. ":variant.payload", Code.CodeTyVoid, value_type(fctx, ctx, k.payload) or Code.CodeTyVoid))
                else expect_type(ctx, site .. ":variant.payload", k.variant.payload_ty, value_type(fctx, ctx, k.payload)) end
            elseif k.variant.payload_ty ~= nil then
                add_issue(ctx, Code.CodeIssueTypeMismatch(site .. ":variant.payload", k.variant.payload_ty, Code.CodeTyVoid))
            end
        elseif cls == Code.CodeInstVariantTag then
            if not is_integer_like(k.tag_ty) then add_issue(ctx, Code.CodeIssueTypeMismatch(site .. ":variant.tag", Code.CodeTyIndex, k.tag_ty)) end
            value_type(fctx, ctx, k.value)
        elseif cls == Code.CodeInstVariantPayload then
            value_type(fctx, ctx, k.value)
        elseif cls == Code.CodeInstCall then
            check_call(ctx, fctx, site .. ":call", k.sig, k.target, k.args, k.dst)
        elseif cls == Code.CodeInstAtomicLoad then
            local pty = place_type(ctx, fctx, k.place, site .. ":atomic_load")
            check_memory_access(ctx, site .. ":atomic_load", k.access, "read")
            if pty ~= nil then expect_type(ctx, site .. ":atomic_load", k.access.ty, pty) end
        elseif cls == Code.CodeInstAtomicStore then
            local pty = place_type(ctx, fctx, k.place, site .. ":atomic_store")
            check_memory_access(ctx, site .. ":atomic_store", k.access, "write")
            if pty ~= nil then expect_type(ctx, site .. ":atomic_store.place", k.access.ty, pty) end
            expect_type(ctx, site .. ":atomic_store.value", k.access.ty, value_type(fctx, ctx, k.value))
        elseif cls == Code.CodeInstAtomicRmw then
            local pty = place_type(ctx, fctx, k.place, site .. ":atomic_rmw")
            check_memory_access(ctx, site .. ":atomic_rmw", k.access, "write")
            if pty ~= nil then expect_type(ctx, site .. ":atomic_rmw.place", k.access.ty, pty) end
            expect_type(ctx, site .. ":atomic_rmw.value", k.access.ty, value_type(fctx, ctx, k.value))
        elseif cls == Code.CodeInstAtomicCas then
            local pty = place_type(ctx, fctx, k.place, site .. ":atomic_cas")
            check_memory_access(ctx, site .. ":atomic_cas", k.access, "write")
            if pty ~= nil then expect_type(ctx, site .. ":atomic_cas.place", k.access.ty, pty) end
            expect_type(ctx, site .. ":atomic_cas.expected", k.access.ty, value_type(fctx, ctx, k.expected))
            expect_type(ctx, site .. ":atomic_cas.replacement", k.access.ty, value_type(fctx, ctx, k.replacement))
        elseif cls == Code.CodeInstAtomicFence then
            -- no value refs
        else
            add_issue(ctx, Code.CodeIssueUnsupportedSource(site, "unsupported instruction " .. class_name(k)))
        end
    end

    local function check_term(ctx, fctx, func, block)
        local term = block.term
        if term == nil then return end
        local site = "func:" .. func.name .. ":block:" .. block.name .. ":term:" .. term.id.text
        local k = term.kind
        local cls = pvm.classof(k)
        if cls == Code.CodeTermJump then
            check_transfer(ctx, fctx, site .. ":jump", k.dest, k.args)
        elseif cls == Code.CodeTermBranch then
            expect_bool(ctx, site .. ":branch.cond", value_type(fctx, ctx, k.cond))
            check_transfer(ctx, fctx, site .. ":branch.then", k.then_dest, k.then_args)
            check_transfer(ctx, fctx, site .. ":branch.else", k.else_dest, k.else_args)
        elseif cls == Code.CodeTermSwitch then
            value_type(fctx, ctx, k.value)
            for i = 1, #k.cases do check_transfer(ctx, fctx, site .. ":switch.case" .. tostring(i), k.cases[i].dest, k.cases[i].args) end
            check_transfer(ctx, fctx, site .. ":switch.default", k.default_dest, k.default_args)
        elseif cls == Code.CodeTermVariantSwitch then
            value_type(fctx, ctx, k.tag)
            for i = 1, #k.cases do check_transfer(ctx, fctx, site .. ":variant.case" .. tostring(i), k.cases[i].dest, k.cases[i].args) end
            check_transfer(ctx, fctx, site .. ":variant.default", k.default_dest, k.default_args)
        elseif cls == Code.CodeTermReturn then
            local sig = fctx.sig
            if sig ~= nil then
                if #k.values ~= #sig.results then add_issue(ctx, Code.CodeIssueCallArity(sig.id, #sig.results, #k.values)) end
                local n = math.min(#k.values, #sig.results)
                for i = 1, n do expect_type(ctx, site .. ":return" .. tostring(i), sig.results[i], value_type(fctx, ctx, k.values[i])) end
            else
                for i = 1, #k.values do value_type(fctx, ctx, k.values[i]) end
            end
        elseif cls == Code.CodeTermTrap or cls == Code.CodeTermUnreachable then
            -- valid terminal forms
        else
            add_issue(ctx, Code.CodeIssueInvalidTerminator(site, term.id))
        end
    end

    local function validate_func(ctx, func)
        local sig = check_sig_ref(ctx, func.sig)
        local fctx = { func = func, sig = sig, values = {}, locals = {}, blocks = {}, insts = {}, terms = {} }
        if sig ~= nil then
            if #func.params ~= #sig.params then add_issue(ctx, Code.CodeIssueCallArity(sig.id, #sig.params, #func.params)) end
            local n = math.min(#func.params, #sig.params)
            for i = 1, n do expect_type(ctx, "func:" .. func.name .. ":param" .. tostring(i), sig.params[i], func.params[i].ty) end
        end
        register_function_defs(ctx, fctx, func)
        if fctx.blocks[func.entry.text] == nil then add_issue(ctx, Code.CodeIssueMissingBlock(func.entry)) end
        for i = 1, #(func.blocks or {}) do
            local block = func.blocks[i]
            for j = 1, #(block.params or {}) do type_uses_code_sig(block.params[j].ty, ctx) end
            for j = 1, #(block.insts or {}) do check_inst(ctx, fctx, func, block, block.insts[j]) end
            check_term(ctx, fctx, func, block)
        end
    end

    local function validate(code_module, collector_or_opts)
        local collector = collector_or_opts
        if type(collector_or_opts) == "table" and collector_or_opts.collector ~= nil then collector = collector_or_opts.collector end
        local ctx = { issues = {}, collector = collector, relocs = {} }

        ctx.sigs = index_by(ctx, code_module.sigs, function(s) return s.id.text, s.id end, function(id) return Code.CodeIssueDuplicateSig(id) end)
        ctx.data = index_by(ctx, code_module.data, function(d) return d.id.text, d.id end, function(id) return Code.CodeIssueDuplicateData(id) end)
        ctx.globals = index_by(ctx, code_module.globals, function(g) return g.id.text, g.id end, function(id) return Code.CodeIssueDuplicateGlobal(id) end)
        ctx.externs = index_by(ctx, code_module.externs, function(e) return e.id.text, e.id end, function(id) return Code.CodeIssueDuplicateExtern(id) end)
        ctx.funcs = index_by(ctx, code_module.funcs, function(f) return f.id.text, f.id end, function(id) return Code.CodeIssueDuplicateFunc(id) end)

        for i = 1, #(code_module.sigs or {}) do
            local sig = code_module.sigs[i]
            for j = 1, #sig.params do type_uses_code_sig(sig.params[j], ctx) end
            for j = 1, #sig.results do type_uses_code_sig(sig.results[j], ctx) end
        end
        for i = 1, #(code_module.types or {}) do type_uses_code_sig(code_module.types[i].ty, ctx) end
        for i = 1, #(code_module.externs or {}) do check_sig_ref(ctx, code_module.externs[i].sig) end
        for i = 1, #(code_module.globals or {}) do
            local g = code_module.globals[i]
            type_uses_code_sig(g.ty, ctx)
            check_align(ctx, "global:" .. g.id.text, g.align, nil)
            for j = 1, #(g.inits or {}) do
                local init = g.inits[j]
                check_init_bounds(ctx, "global", g.id, g.size, init)
                if pvm.classof(init) == Code.CodeDataReloc then check_reloc(ctx, init.reloc) end
            end
        end
        for i = 1, #(code_module.data or {}) do
            local d = code_module.data[i]
            check_align(ctx, "data:" .. d.id.text, d.align, nil)
            for j = 1, #(d.inits or {}) do
                local init = d.inits[j]
                check_init_bounds(ctx, "data", d.id, d.size, init)
                if pvm.classof(init) == Code.CodeDataReloc then check_reloc(ctx, init.reloc) end
            end
        end
        for i = 1, #(code_module.funcs or {}) do validate_func(ctx, code_module.funcs[i]) end

        return Code.CodeValidationReport(ctx.issues)
    end

    api.validate = validate
    api.type_eq = type_eq

    T._moonlift_api_cache.code_validate = api
    return api
end

return bind_context
