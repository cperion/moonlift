local pvm = require("lalin.pvm")

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s:match("^%d") then s = "_" .. s end
    if s == "" then s = "x" end
    return s
end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.code_mem_facts ~= nil then return T._lalin_api_cache.code_mem_facts end

    local Core = T.LalinCore
    local Code = T.LalinCode
    local Graph = T.LalinGraph
    local Flow = T.LalinFlow
    local Value = T.LalinValue
    local Mem = T.LalinMem
    local CodeGraph = require("lalin.code_graph")(T)
    local CodeFlowFacts = require("lalin.code_flow_facts")(T)
    local CodeValueFacts = require("lalin.code_value_facts")(T)

    local api = {}

    local function object_id(...)
        local parts = { ... }
        for i = 1, #parts do parts[i] = sanitize(parts[i]) end
        return Mem.MemObjectId(table.concat(parts, ":"))
    end

    local function access_id(func, block, inst)
        return Mem.MemAccessId("access:" .. sanitize(func.name) .. ":" .. sanitize(block.id.text) .. ":" .. sanitize(inst.id.text))
    end

    local function unwrap_lease(ty)
        while pvm.classof(ty) == Code.CodeTyLease do ty = ty.base end
        return ty
    end

    local function pointee_ty(ty)
        ty = unwrap_lease(ty)
        return pvm.classof(ty) == Code.CodeTyDataPtr and ty.pointee or nil
    end

    local function view_elem_ty(ty)
        ty = unwrap_lease(ty)
        return pvm.classof(ty) == Code.CodeTyView and ty.elem or nil
    end

    local function slice_elem_ty(ty)
        ty = unwrap_lease(ty)
        return pvm.classof(ty) == Code.CodeTySlice and ty.elem or nil
    end

    local function object_elem_ty(ty)
        ty = unwrap_lease(ty)
        if ty == Code.CodeTyByteSpan or pvm.classof(ty) == Code.CodeTyByteSpan then return Code.CodeTyInt(8, Code.CodeUnsigned) end
        return pointee_ty(ty) or view_elem_ty(ty) or slice_elem_ty(ty) or ty
    end

    local function storage_extent(ty, size, reason)
        if size ~= nil then return Mem.MemExtentBytes(size, reason or "declared storage size") end
        local cls = pvm.classof(unwrap_lease(ty))
        if cls == Code.CodeTyArray then return Mem.MemExtentBytes(0, "array byte size is target-dependent before backend layout") end
        return Mem.MemExtentUnknown(reason or "extent requires layout or contract fact")
    end

    local function scalar_bytes(ty)
        ty = unwrap_lease(ty)
        if ty == Code.CodeTyBool8 then return 1 end
        if ty == Code.CodeTyIndex then return 8 end
        local cls = pvm.classof(ty)
        if cls == Code.CodeTyInt or cls == Code.CodeTyFloat then return math.max(1, math.floor((ty.bits or 64) / 8)) end
        if cls == Code.CodeTyDataPtr or cls == Code.CodeTyCodePtr or cls == Code.CodeTyImportedCFuncPtr then return 8 end
        return nil
    end

    local function stride_from_value(value, consts)
        local n = value and consts[value.text] or nil
        if n == 1 then return Mem.MemStrideUnit end
        if n ~= nil then return Mem.MemStrideConstElems(n) end
        if value ~= nil then return Mem.MemStrideValue(value) end
        return Mem.MemStrideUnknown("stride value is unavailable")
    end

    local function add_unique(out, by_key, key, fact)
        if key ~= nil and by_key[key] ~= nil then return by_key[key] end
        if key ~= nil then by_key[key] = fact end
        out[#out + 1] = fact
        return fact
    end

    local function contract_facts(contracts)
        if contracts == nil then return {} end
        if pvm.classof(contracts) == Code.CodeContractFactSet then return contracts.facts or {} end
        return contracts
    end

    local function contract_index(contracts)
        local idx = { bounds = {}, window = {}, same_len = {}, disjoint = {}, soa = {}, noalias = {}, readonly = {}, writeonly = {}, by_func = {} }
        for _, f in ipairs(contract_facts(contracts)) do
            idx.by_func[f.func.text] = idx.by_func[f.func.text] or {}
            idx.by_func[f.func.text][#idx.by_func[f.func.text] + 1] = f
            local k = f.fact
            local cls = pvm.classof(k)
            if cls == Code.CodeContractBounds then idx.bounds[f.func.text .. "\0" .. k.base.text] = f
            elseif cls == Code.CodeContractWindowBounds then idx.window[f.func.text .. "\0" .. k.base.text] = f
            elseif cls == Code.CodeContractSameLen then idx.same_len[#idx.same_len + 1] = f
            elseif cls == Code.CodeContractDisjoint then idx.disjoint[#idx.disjoint + 1] = f
            elseif cls == Code.CodeContractSoAComponent then idx.soa[f.func.text .. "\0" .. k.base.text] = f
            elseif cls == Code.CodeContractNoAlias then idx.noalias[f.func.text .. "\0" .. k.base.text] = f
            elseif cls == Code.CodeContractReadonly then idx.readonly[f.func.text .. "\0" .. k.base.text] = f
            elseif cls == Code.CodeContractWriteonly then idx.writeonly[f.func.text .. "\0" .. k.base.text] = f end
        end
        return idx
    end

    local function const_values(func)
        local out = {}
        for _, block in ipairs(func.blocks or {}) do
            for _, inst in ipairs(block.insts or {}) do
                local k = inst.kind
                if pvm.classof(k) == Code.CodeInstConst and pvm.classof(k.const) == Code.CodeConstLiteral then
                    local lit = k.const.literal
                    local n = lit and lit.raw and tonumber(lit.raw) or nil
                    if n ~= nil then out[k.dst.text] = n end
                end
            end
        end
        return out
    end

    local function access_kind(k)
        local cls = pvm.classof(k)
        if cls == Code.CodeInstLoad then return Mem.MemLoad end
        if cls == Code.CodeInstStore then return Mem.MemStore end
        if cls == Code.CodeInstAtomicLoad then return Mem.MemAtomicLoad end
        if cls == Code.CodeInstAtomicStore then return Mem.MemAtomicStore end
        if cls == Code.CodeInstAtomicRmw then return Mem.MemAtomicRmw end
        if cls == Code.CodeInstAtomicCas then return Mem.MemAtomicCas end
        return nil
    end

    local function is_write_kind(kind)
        return kind == Mem.MemStore or kind == Mem.MemAtomicStore or kind == Mem.MemAtomicRmw or kind == Mem.MemAtomicCas
    end

    local function access_value(k)
        local cls = pvm.classof(k)
        if cls == Code.CodeInstStore or cls == Code.CodeInstAtomicStore or cls == Code.CodeInstAtomicRmw then return k.value end
        if cls == Code.CodeInstAtomicCas then return k.replacement end
        return nil
    end

    local function access_place(k)
        return k.place
    end

    local function backend_trap(access)
        if access.trap == Code.CodeMustNotTrap then return Mem.MemNonTrapping("CodeMemoryAccess is marked must-not-trap") end
        if access.trap == Code.CodeCheckedTrap then return Mem.MemCheckedTrap("CodeMemoryAccess is checked") end
        return Mem.MemMayTrap
    end

    local function backend_alignment(access)
        return access.align and Mem.MemAlignKnown(access.align) or Mem.MemAlignUnknown
    end

    local function object_for_value(value_object, id)
        return id and value_object[id.text] or nil
    end

    local function loop_membership(graph)
        local by_func = {}
        for _, fg in ipairs(graph and graph.funcs or {}) do
            by_func[fg.func.text] = by_func[fg.func.text] or {}
            for _, loop in ipairs(fg.loops or {}) do
                for _, gb in ipairs(loop.body or {}) do by_func[fg.func.text][gb.block.text] = loop.id end
            end
        end
        return by_func
    end

    local function index_key(index)
        local cls = pvm.classof(index)
        if index == Mem.MemIndexNone then return "none" end
        if cls == Mem.MemIndexValue then return "value:" .. index.value.text .. ":" .. tostring(index.elem_size) .. ":" .. tostring(index.const_offset or 0) end
        if cls == Mem.MemIndexInduction then return "induction:" .. index.induction.value.text .. ":" .. tostring(index.elem_size) .. ":" .. tostring(index.const_offset or 0) end
        return nil
    end

    local function value_expr_key(expr, seen)
        if expr == nil then return nil end
        seen = seen or {}
        if seen[expr] then return nil end
        seen[expr] = true
        local cls = pvm.classof(expr)
        if cls == Value.ValueExprValue then return "value:" .. expr.value.text end
        if cls == Value.ValueExprConst then return "const:" .. tostring(expr.const) end
        if cls == Value.ValueExprCast then return "cast:" .. tostring(expr.op) .. ":" .. tostring(expr.from) .. ":" .. tostring(expr.to) .. "(" .. tostring(value_expr_key(expr.value, seen)) .. ")" end
        if cls == Value.ValueExprUnary then return "unary:" .. tostring(expr.op) .. "(" .. tostring(value_expr_key(expr.value, seen)) .. ")" end
        if cls == Value.ValueExprAdd or cls == Value.ValueExprSub or cls == Value.ValueExprMul then
            return tostring(cls.__name) .. "(" .. tostring(value_expr_key(expr.a, seen)) .. "," .. tostring(value_expr_key(expr.b, seen)) .. ")"
        end
        return tostring(expr)
    end

    local function canonical_index_key(index, value_index)
        local cls = pvm.classof(index)
        if index == Mem.MemIndexNone then return "none" end
        if cls == Mem.MemIndexValue then
            local expr = value_index and value_index.expr_by_value and value_index.expr_by_value[index.value.text] or nil
            return "value_expr:" .. tostring(value_expr_key(expr) or index.value.text) .. ":" .. tostring(index.elem_size) .. ":" .. tostring(index.const_offset or 0)
        end
        return index_key(index)
    end

    local function semantic_facts(module, graph, flow, value, contracts)
        graph = graph or CodeGraph.graph(module)
        flow = flow or CodeFlowFacts.facts(module, graph)
        value = value or CodeValueFacts.facts(module, graph, flow)
        local cidx = contract_index(contracts)

        local objects, object_by_key = {}, {}
        local leases, accesses, intervals, safety, effects, dependences, relations, backend_info, proofs = {}, {}, {}, {}, {}, {}, {}, {}, {}
        local module_objects = { data = {}, global = {} }
        local loops_by_func_block = loop_membership(graph)

        local function add_object(fact)
            add_unique(objects, object_by_key, fact.id.text, fact)
            return fact.id
        end

        local function object_fact(id)
            return id and object_by_key[id.text] or nil
        end

            local function object_proves_access_safety(id)
                local fact = object_fact(id)
                if fact == nil then return false, "access object is unknown" end
                local extent_cls = pvm.classof(fact.extent)
            local kind = fact.kind
            if kind == Mem.MemObjectLocal or kind == Mem.MemObjectGlobal or kind == Mem.MemObjectData then
                return true, "direct local/global/data object access"
            end
            if kind == Mem.MemObjectContract then
                return true, "bounds contract proves object extent"
            end
            if kind == Mem.MemObjectLease then
                return true, "lease grant proves object access"
            end
            if kind == Mem.MemObjectView and extent_cls ~= Mem.MemExtentUnknown then
                return true, "view descriptor length proves object extent"
            end
            if kind == Mem.MemObjectSlice and extent_cls ~= Mem.MemExtentUnknown then
                return true, "slice descriptor length proves object extent"
            end
            if kind == Mem.MemObjectByteSpan and extent_cls ~= Mem.MemExtentUnknown then
                return true, "byte span descriptor length proves object extent"
            end
            if kind == Mem.MemObjectDerived and extent_cls ~= Mem.MemExtentUnknown then
                return true, "derived object has explicit bounded extent"
            end
            if extent_cls == Mem.MemExtentUnknown then
                return false, fact.extent.reason or "object extent is unknown"
            end
            return false, "object provenance alone is not a bounds proof"
        end

        for _, data in ipairs(module.data or {}) do
            local id = object_id("data", data.id.text)
            module_objects.data[data.id.text] = id
            add_object(Mem.MemObjectFact(id, nil, Mem.MemObjectData, Mem.MemProvData(data.id), nil, Mem.MemExtentBytes(data.size or 0, "CodeData.size"), Mem.MemStrideUnit))
        end
        for _, global in ipairs(module.globals or {}) do
            local id = object_id("global", global.id.text)
            module_objects.global[global.id.text] = id
            add_object(Mem.MemObjectFact(id, nil, Mem.MemObjectGlobal, Mem.MemProvGlobal(global.id), object_elem_ty(global.ty), storage_extent(global.ty, global.size, "CodeGlobal storage"), Mem.MemStrideUnit))
        end

        for _, func in ipairs(module.funcs or {}) do
            local value_object, local_object, local_value_object = {}, {}, {}
            local access_records = {}
            local readonly_objects, writeonly_objects = {}, {}
            local consts = const_values(func)
            local value_index = CodeValueFacts.expr_index(value)
            local scaled_index_stride = {}
            local same_store = {}

            local function mark_same_store(a, b)
                if a == nil or b == nil then return end
                same_store[a.text] = same_store[a.text] or {}
                same_store[b.text] = same_store[b.text] or {}
                same_store[a.text][b.text] = b
                same_store[b.text][a.text] = a
            end

            local function extent_for_value(value, ty)
                local bounds = value and cidx.bounds[func.id.text .. "\0" .. value.text]
                local window = value and cidx.window[func.id.text .. "\0" .. value.text]
                local contract = bounds or window
                if contract ~= nil then
                    local k = contract.fact
                    local len = bounds and k.len or k.base_len
                    return Mem.MemExtentElements(len, object_elem_ty(ty) or Code.CodeTyVoid, bounds and "CodeContractBounds extent" or "CodeContractWindowBounds base extent"), contract
                end
                if view_elem_ty(ty) ~= nil then return Mem.MemExtentUnknown("view extent requires descriptor length or contract"), nil end
                if slice_elem_ty(ty) ~= nil then return Mem.MemExtentUnknown("slice extent requires descriptor length or contract"), nil end
                if ty == Code.CodeTyByteSpan or pvm.classof(ty) == Code.CodeTyByteSpan then return Mem.MemExtentUnknown("byte span extent requires descriptor length or contract"), nil end
                return Mem.MemExtentUnknown("raw pointer parameter has no extent without contract or object provenance"), nil
            end

            for _, param in ipairs(func.params or {}) do
                local ty = unwrap_lease(param.ty)
                if pvm.classof(param.ty) == Code.CodeTyLease or pvm.classof(ty) == Code.CodeTyDataPtr or pvm.classof(ty) == Code.CodeTyView or pvm.classof(ty) == Code.CodeTySlice or ty == Code.CodeTyByteSpan or pvm.classof(ty) == Code.CodeTyByteSpan then
                    local extent, contract = extent_for_value(param.value, ty)
                    local id = object_id(func.name, pvm.classof(param.ty) == Code.CodeTyLease and "lease_param" or "param", param.value.text)
                    value_object[param.value.text] = id
                    local object_kind = pvm.classof(param.ty) == Code.CodeTyLease and Mem.MemObjectLease
                        or (contract and Mem.MemObjectContract
                            or (pvm.classof(ty) == Code.CodeTyView and Mem.MemObjectView
                                or (pvm.classof(ty) == Code.CodeTySlice and Mem.MemObjectSlice
                                    or ((ty == Code.CodeTyByteSpan or pvm.classof(ty) == Code.CodeTyByteSpan) and Mem.MemObjectByteSpan or Mem.MemObjectParam))))
                    add_object(Mem.MemObjectFact(id, func.id, object_kind, contract and Mem.MemProvContract(contract) or Mem.MemProvValue(param.value), object_elem_ty(ty), extent, pvm.classof(ty) == Code.CodeTyView and Mem.MemStrideUnknown("view parameter stride requires descriptor stride fact") or Mem.MemStrideUnit))
                    if pvm.classof(param.ty) == Code.CodeTyLease then
                        local proof = Mem.MemProofObject(id, "CodeTyLease parameter grants an explicit memory lease")
                        proofs[#proofs + 1] = proof
                        local lease_id = Mem.MemLeaseId("lease:" .. sanitize(func.name) .. ":" .. sanitize(param.value.text))
                        leases[#leases + 1] = Mem.MemLeaseGrant(lease_id, Flow.FlowDomainFunction(func.id), param.value, nil, id, Mem.MemBaseValue(param.value), extent, Mem.MemStrideUnit, proof)
                    end
                end
            end

            for _, local_decl in ipairs(func.locals or {}) do
                local id = object_id(func.name, "local", local_decl.id.text)
                local_object[local_decl.id.text] = id
                add_object(Mem.MemObjectFact(id, func.id, Mem.MemObjectLocal, Mem.MemProvLocal(local_decl.id), object_elem_ty(local_decl.ty), storage_extent(local_decl.ty, nil, "CodeLocal storage"), Mem.MemStrideUnit))
            end

            local function object_for_place(place)
                local cls = pvm.classof(place)
                if cls == Code.CodePlaceLocal then return local_object[place.local_id.text], Mem.MemBaseLocal(place.local_id), Mem.MemIndexNone end
                if cls == Code.CodePlaceGlobal then return module_objects.global[place.global.text], Mem.MemBaseGlobal(place.global), Mem.MemIndexNone end
                if cls == Code.CodePlaceData then return module_objects.data[place.data.text], Mem.MemBaseData(place.data), Mem.MemIndexNone end
                if cls == Code.CodePlaceDeref then return object_for_value(value_object, place.addr), Mem.MemBaseValue(place.addr), Mem.MemIndexNone end
                if cls == Code.CodePlaceIndex then
                    local parent, base = object_for_place(place.base)
                    return parent, base or Mem.MemBaseUnknown("index base object is unknown"), Mem.MemIndexValue(place.index, place.elem_size, 0)
                end
                if cls == Code.CodePlaceField then
                    local parent, base, index = object_for_place(place.base)
                    if parent ~= nil then
                        local id = object_id(func.name, "field", parent.text, tostring(place.offset or 0))
                        add_object(Mem.MemObjectFact(id, func.id, Mem.MemObjectDerived, Mem.MemProvProjection(parent, Mem.MemProjectField, place.offset or 0), place.ty, storage_extent(place.ty, place.size, "CodePlaceField projection"), Mem.MemStrideUnit))
                        local proof = Mem.MemProofObject(id, "CodePlaceField projection shares backing store with its parent object")
                        proofs[#proofs + 1] = proof
                        relations[#relations + 1] = Mem.MemObjectSameStore(id, parent, proof)
                        mark_same_store(id, parent)
                        return id, Mem.MemBaseProjection(base or Mem.MemBaseUnknown("field base unknown"), Mem.MemProjectField, place.offset or 0), index
                    end
                    return nil, Mem.MemBaseUnknown("field parent object is unknown"), Mem.MemIndexNone
                end
                if cls == Code.CodePlaceBytes then
                    local parent = object_for_value(value_object, place.base)
                    if parent ~= nil then
                        local id = object_id(func.name, "bytes", parent.text, tostring(place.offset or 0))
                        add_object(Mem.MemObjectFact(id, func.id, Mem.MemObjectDerived, Mem.MemProvProjection(parent, Mem.MemProjectBytes, place.offset or 0), place.ty, Mem.MemExtentBytes(place.size or 0, "CodePlaceBytes projection"), Mem.MemStrideUnit))
                        local proof = Mem.MemProofObject(id, "CodePlaceBytes projection shares backing store with its parent object")
                        proofs[#proofs + 1] = proof
                        relations[#relations + 1] = Mem.MemObjectSameStore(id, parent, proof)
                        mark_same_store(id, parent)
                        return id, Mem.MemBaseProjection(Mem.MemBaseValue(place.base), Mem.MemProjectBytes, place.offset or 0), Mem.MemIndexNone
                    end
                    return nil, Mem.MemBaseValue(place.base), Mem.MemIndexNone
                end
                return nil, Mem.MemBaseUnknown("unsupported CodePlace for memory facts"), Mem.MemIndexNone
            end

            local function merge_local_value(local_id, object)
                local key = local_id.text
                local old = local_value_object[key]
                if old == nil then local_value_object[key] = object or false elseif old ~= object then local_value_object[key] = false end
            end

            local function object_stride_const(object)
                local fact = object_fact(object)
                if fact == nil then return nil end
                local cls = pvm.classof(fact.stride)
                if fact.stride == Mem.MemStrideUnit then return 1 end
                if cls == Mem.MemStrideConstElems then return fact.stride.elems end
                return nil
            end

            local function pattern_for_index(index)
                if index == Mem.MemIndexNone then return Mem.MemAccessScalar end
                local cls = pvm.classof(index)
                if cls == Mem.MemIndexValue then
                    local stride = scaled_index_stride[index.value.text]
                    if stride == "dynamic" then return Mem.MemAccessUnknown end
                    if type(stride) == "number" and stride ~= 1 then return Mem.MemAccessStrided(stride) end
                end
                return Mem.MemAccessContiguous
            end

            for _, block in ipairs(func.blocks or {}) do
                for _, inst in ipairs(block.insts or {}) do
                    local k = inst.kind
                    local cls = pvm.classof(k)
                    if cls == Code.CodeInstGlobalRef then
                        local rcls = pvm.classof(k.ref)
                        if rcls == Code.CodeGlobalRefData then value_object[k.dst.text] = module_objects.data[k.ref.data.text] end
                        if rcls == Code.CodeGlobalRefGlobal then value_object[k.dst.text] = module_objects.global[k.ref.global.text] end
                    elseif cls == Code.CodeInstAddrOf then
                        local obj = object_for_place(k.place)
                        value_object[k.dst.text] = obj
                    elseif cls == Code.CodeInstPtrOffset then
                        local parent = object_for_value(value_object, k.base)
                        if parent ~= nil then
                            local id = object_id(func.name, "ptr_offset", k.dst.text)
                            value_object[k.dst.text] = id
                            add_object(Mem.MemObjectFact(id, func.id, Mem.MemObjectDerived, Mem.MemProvProjection(parent, Mem.MemProjectPtrOffset, k.const_offset or 0), pointee_ty(k.ptr_ty), Mem.MemExtentUnknown("ptr-offset projection requires a bounded slice/window fact before it has an extent"), Mem.MemStrideUnit))
                        end
                    elseif cls == Code.CodeInstViewMake then
                        local id = object_id(func.name, "view", k.dst.text)
                        value_object[k.dst.text] = id
                        add_object(Mem.MemObjectFact(id, func.id, Mem.MemObjectView, Mem.MemProvView(k.dst, k.data, k.len, k.stride), k.elem_ty, Mem.MemExtentElements(k.len, k.elem_ty, "CodeInstViewMake explicit length"), stride_from_value(k.stride, consts)))
                        local parent = object_for_value(value_object, k.data)
                        if parent ~= nil then
                            local proof = Mem.MemProofObject(id, "CodeInstViewMake descriptor shares backing store with its data object")
                            proofs[#proofs + 1] = proof
                            relations[#relations + 1] = Mem.MemObjectSameStore(id, parent, proof)
                            mark_same_store(id, parent)
                        end
                    elseif cls == Code.CodeInstViewData then
                        value_object[k.dst.text] = value_object[k.view.text]
                    elseif cls == Code.CodeInstViewStride then
                        local stride = object_stride_const(value_object[k.view.text])
                        if stride ~= nil then consts[k.dst.text] = stride end
                    elseif cls == Code.CodeInstSliceMake then
                        local id = object_id(func.name, "slice", k.dst.text)
                        value_object[k.dst.text] = id
                        add_object(Mem.MemObjectFact(id, func.id, Mem.MemObjectSlice, Mem.MemProvSlice(k.dst, k.data, k.len), k.elem_ty, Mem.MemExtentElements(k.len, k.elem_ty, "CodeInstSliceMake explicit length"), Mem.MemStrideUnit))
                        local parent = object_for_value(value_object, k.data)
                        if parent ~= nil then
                            local proof = Mem.MemProofObject(id, "CodeInstSliceMake descriptor shares backing store with its data object")
                            proofs[#proofs + 1] = proof
                            relations[#relations + 1] = Mem.MemObjectSameStore(id, parent, proof)
                            mark_same_store(id, parent)
                        end
                    elseif cls == Code.CodeInstSliceData then
                        value_object[k.dst.text] = value_object[k.slice.text]
                    elseif cls == Code.CodeInstByteSpanMake then
                        local id = object_id(func.name, "bytespan", k.dst.text)
                        value_object[k.dst.text] = id
                        add_object(Mem.MemObjectFact(id, func.id, Mem.MemObjectByteSpan, Mem.MemProvByteSpan(k.dst, k.data, k.len), Code.CodeTyInt(8, Code.CodeUnsigned), Mem.MemExtentElements(k.len, Code.CodeTyInt(8, Code.CodeUnsigned), "CodeInstByteSpanMake explicit byte length"), Mem.MemStrideUnit))
                        local parent = object_for_value(value_object, k.data)
                        if parent ~= nil then
                            local proof = Mem.MemProofObject(id, "CodeInstByteSpanMake descriptor shares backing store with its data object")
                            proofs[#proofs + 1] = proof
                            relations[#relations + 1] = Mem.MemObjectSameStore(id, parent, proof)
                            mark_same_store(id, parent)
                        end
                    elseif cls == Code.CodeInstByteSpanData then
                        value_object[k.dst.text] = value_object[k.span.text]
                    elseif cls == Code.CodeInstLoad then
                        if pvm.classof(k.place) == Code.CodePlaceLocal and local_value_object[k.place.local_id.text] then value_object[k.dst.text] = local_value_object[k.place.local_id.text] end
                    elseif cls == Code.CodeInstStore then
                        if pvm.classof(k.place) == Code.CodePlaceLocal then merge_local_value(k.place.local_id, value_object[k.value.text]) end
                    elseif cls == Code.CodeInstAlias then
                        value_object[k.dst.text] = value_object[k.src.text]
                        if consts[k.src.text] ~= nil then consts[k.dst.text] = consts[k.src.text] end
                    elseif cls == Code.CodeInstCast then
                        value_object[k.dst.text] = value_object[k.value.text]
                        if consts[k.value.text] ~= nil then consts[k.dst.text] = consts[k.value.text] end
                    elseif cls == Code.CodeInstBinary then
                        local lhs, rhs = consts[k.lhs.text], consts[k.rhs.text]
                        if k.op == Core.BinMul then
                            if lhs ~= nil and rhs ~= nil then
                                consts[k.dst.text] = lhs * rhs
                                scaled_index_stride[k.dst.text] = lhs * rhs
                            elseif lhs ~= nil then
                                scaled_index_stride[k.dst.text] = lhs
                            elseif rhs ~= nil then
                                scaled_index_stride[k.dst.text] = rhs
                            else
                                scaled_index_stride[k.dst.text] = "dynamic"
                            end
                        elseif k.op == Core.BinAdd or k.op == Core.BinSub then
                            if lhs ~= nil and rhs ~= nil then consts[k.dst.text] = (k.op == Core.BinAdd) and (lhs + rhs) or (lhs - rhs) end
                        end
                    end

                    local kind = access_kind(k)
                    if kind ~= nil then
                        local place = access_place(k)
                        local object, base, index = object_for_place(place)
                        local id = access_id(func, block, inst)
                        local in_bounds, bounds_reason = object_proves_access_safety(object)
                        local bounds = in_bounds and Mem.MemBoundsInObject(bounds_reason) or Mem.MemBoundsUnknown(bounds_reason)
                        local trap
                        if k.access.trap == Code.CodeMustNotTrap or k.access.trap == Code.CodeCheckedTrap then
                            trap = backend_trap(k.access)
                        elseif in_bounds then
                            trap = Mem.MemNonTrapping(bounds_reason)
                        else
                            trap = Mem.MemMayTrap
                        end
                        local align = backend_alignment(k.access)
                        local pattern = pattern_for_index(index)
                        local loop_id = loops_by_func_block[func.id.text] and loops_by_func_block[func.id.text][block.id.text] or nil
                        local access_fact = Mem.MemAccessFact(id, func.id, Graph.GraphBlockId(func.id, block.id), inst.id, kind, place, k.access, base, index, pattern, align, bounds, trap)
                        accesses[#accesses + 1] = access_fact
                        access_records[#access_records + 1] = { id = id, object = object, kind = kind, index = index, index_key = canonical_index_key(index, value_index), loop = loop_id, in_bounds = in_bounds, trap = trap, order = #access_records + 1 }

                        local proof = Mem.MemProofBackend(id, "backend access info derived from structured MemAccessFact")
                        proofs[#proofs + 1] = proof
                        local deref = scalar_bytes(k.access.ty)
                        local is_atomic = kind == Mem.MemAtomicLoad or kind == Mem.MemAtomicStore or kind == Mem.MemAtomicRmw or kind == Mem.MemAtomicCas or k.access.ordering ~= nil
                        local explicit_nontrap = k.access.trap == Code.CodeMustNotTrap
                        local movable = (pvm.classof(trap) == Mem.MemNonTrapping) and (in_bounds or explicit_nontrap) and not k.access.volatile and not is_atomic
                        backend_info[#backend_info + 1] = Mem.MemBackendAccessInfo(id, trap, align, bounds, deref, movable, { proof })
                        if object ~= nil and in_bounds then
                            local interval = Mem.MemAccessInterval(id, object, loop_id, index, Flow.FlowBoundDerived("access-length:" .. id.text, {}), deref or 0, 0, "access projected into proven bounded memory object")
                            intervals[#intervals + 1] = interval
                            local iproof = Mem.MemProofInterval(interval, "access interval is contained in proven memory object extent")
                            proofs[#proofs + 1] = iproof
                            safety[#safety + 1] = Mem.MemAccessInBounds(interval, iproof)
                        end
                        if deref ~= nil then safety[#safety + 1] = Mem.MemAccessDerefBytes(id, deref, proof) end
                        if k.access.align ~= nil then safety[#safety + 1] = Mem.MemAccessAlignKnown(id, k.access.align, proof) end
                        if pvm.classof(trap) == Mem.MemNonTrapping then safety[#safety + 1] = Mem.MemAccessNonTrap(id, proof) end
                        if movable then safety[#safety + 1] = Mem.MemAccessMovable(id, proof) end
                    end
                end
            end

            for _, fact in ipairs(cidx.by_func[func.id.text] or {}) do
                local k = fact.fact
                local cls = pvm.classof(k)
                local proof = Mem.MemProofContract(fact, "memory contract normalized into semantic memory facts")
                proofs[#proofs + 1] = proof
                if cls == Code.CodeContractReadonly or cls == Code.CodeContractWriteonly then
                    local obj = value_object[k.base.text]
                    if obj ~= nil then
                        if cls == Code.CodeContractReadonly then readonly_objects[obj.text] = true else writeonly_objects[obj.text] = true end
                        effects[#effects + 1] = (cls == Code.CodeContractReadonly and Mem.MemObjectReadonly(obj, proof) or Mem.MemObjectWriteonly(obj, proof))
                    end
                elseif cls == Code.CodeContractSameLen then
                    local a, b = value_object[k.a.text], value_object[k.b.text]
                    if a ~= nil and b ~= nil then relations[#relations + 1] = Mem.MemObjectsSameLen(a, b, proof) end
                elseif cls == Code.CodeContractWindowBounds then
                    local window, parent = value_object[k.base.text], value_object[k.base.text]
                    if window ~= nil and parent ~= nil then relations[#relations + 1] = Mem.MemObjectWindowOf(window, parent, k.start, k.len, proof) end
                end
            end

            local disjoint = {}
            local function mark_disjoint(a, b)
                if a == nil or b == nil then return end
                disjoint[a.text .. "\0" .. b.text] = true
                disjoint[b.text .. "\0" .. a.text] = true
            end
            for _, fact in ipairs(cidx.disjoint or {}) do
                if fact.func == func.id then mark_disjoint(value_object[fact.fact.a.text], value_object[fact.fact.b.text]) end
            end
            local noalias_objects = {}
            for key, fact in pairs(cidx.noalias or {}) do
                if fact.func == func.id then
                    local obj = value_object[fact.fact.base.text]
                    if obj ~= nil then noalias_objects[obj.text] = true end
                end
            end

            local function object_pair_safe(a, b)
                if a.object == nil or b.object == nil then return false, nil end
                if a.object == b.object and a.index_key ~= nil and a.index_key == b.index_key then return true, "same object and same per-iteration index do not carry dependence across iterations" end
                local function disjoint_through_same_store(x, y)
                    if disjoint[x.text .. "\0" .. y.text] then return true end
                    for _, sx in pairs(same_store[x.text] or {}) do
                        if disjoint[sx.text .. "\0" .. y.text] then return true end
                        for _, sy in pairs(same_store[y.text] or {}) do
                            if disjoint[sx.text .. "\0" .. sy.text] then return true end
                        end
                    end
                    for _, sy in pairs(same_store[y.text] or {}) do
                        if disjoint[x.text .. "\0" .. sy.text] then return true end
                    end
                    return false
                end
                if a.object ~= b.object and disjoint_through_same_store(a.object, b.object) then return true, "objects are disjoint by contract through same-store relation" end
                if a.object ~= b.object and (noalias_objects[a.object.text] or noalias_objects[b.object.text]) then return true, "noalias contract separates one object from the other" end
                if a.object ~= b.object and readonly_objects[a.object.text] and readonly_objects[b.object.text] then return true, "read-only objects do not create loop-carried dependence" end
                if a.object ~= b.object and ((readonly_objects[a.object.text] and writeonly_objects[b.object.text]) or (writeonly_objects[a.object.text] and readonly_objects[b.object.text])) then
                    if disjoint[a.object.text .. "\0" .. b.object.text] or noalias_objects[a.object.text] or noalias_objects[b.object.text] then return true, "readonly/writeonly noalias objects are independent" end
                end
                return false, nil
            end

            for i = 1, #access_records do
                for j = i + 1, #access_records do
                    local a, b = access_records[i], access_records[j]
                    if a.loop ~= nil and b.loop ~= nil and a.loop == b.loop then
                        if not is_write_kind(a.kind) and not is_write_kind(b.kind) then
                            dependences[#dependences + 1] = Mem.MemReadReadIndependent(a.id, b.id, "two reads in the same loop do not carry dependence")
                        elseif a.in_bounds and b.in_bounds and pvm.classof(a.trap) == Mem.MemNonTrapping and pvm.classof(b.trap) == Mem.MemNonTrapping then
                            local safe, reason = object_pair_safe(a, b)
                            if safe then
                                local proof = Mem.MemProofNoDependence({ a.id, b.id }, reason)
                                proofs[#proofs + 1] = proof
                                dependences[#dependences + 1] = Mem.MemNoLoopCarriedDependence(a.id, b.id, a.loop, proof)
                            else
                                dependences[#dependences + 1] = Mem.MemDependenceUnknown(a.id, b.id, "no alias/dependence proof for loop-local memory pair")
                            end
                        end
                    end
                end
            end
        end

        return Mem.MemSemanticFactSet(module.id, objects, leases, accesses, intervals, safety, effects, dependences, relations, backend_info, proofs)
    end

    local function facts(module, graph, flow, value, contracts)
        local sem = semantic_facts(module, graph, flow, value, contracts)
        return Mem.MemFactSet(module.id, sem.accesses, {}, sem.dependences, sem.proofs)
    end

    api.semantic_facts = semantic_facts
    api.semantics = semantic_facts
    api.facts = facts
    api.module = semantic_facts

    T._lalin_api_cache.code_mem_facts = api
    return api
end

return bind_context
