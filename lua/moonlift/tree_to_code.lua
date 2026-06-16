local pvm = require("moonlift.pvm")

local M = {}

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

function M.Define(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.tree_to_code ~= nil then return T._moonlift_api_cache.tree_to_code end

    local Core = T.MoonCore
    local Ty = T.MoonType
    local Bind = T.MoonBind
    local Sem = T.MoonSem
    local Host = T.MoonHost
    local Tr = T.MoonTree
    local Code = T.MoonCode

    local CodeType = require("moonlift.code_type").Define(T)
    local TypeSizeAlign = require("moonlift.type_size_align").Define(T)
    local ModuleType = require("moonlift.tree_module_type").Define(T)
    local ConstEval = require("moonlift.sem_const_eval").Define(T)
    local TreeContractFacts = require("moonlift.tree_contract_facts").Define(T)

    local api = {}

    local function unsupported(ctx, node, what)
        local site = ctx and ctx.func_name or "module"
        error("tree_to_code scalar/place slice does not support " .. tostring(what or class_name(node)) .. " in " .. site, 3)
    end

    local function module_name(module)
        local h = module and module.h
        local cls = pvm.classof(h)
        if cls == Tr.ModuleTyped or cls == Tr.ModuleSem or cls == Tr.ModuleCode then return h.module_name end
        if cls == Tr.ModuleOpen then
            local nh = pvm.classof(h.name)
            if nh and h.name.name then return h.name.name end
        end
        return "module"
    end

    local function binding_key(binding)
        if binding == nil then return "<nil>" end
        if binding.id and binding.id.text then return binding.id.text end
        return tostring(binding.name)
    end

    local function is_void_type(ty)
        return pvm.classof(ty) == Ty.TScalar and ty.scalar == Core.ScalarVoid
    end

    local function source_access_base(ty)
        if pvm.classof(ty) == Ty.TLease then return ty.base end
        return ty
    end

    local function variant_name_text(v)
        if type(v) == "string" then return v end
        return v and (v.text or v.name) or tostring(v)
    end

    local function named_type_name(ty)
        if pvm.classof(ty) ~= Ty.TNamed then return nil end
        local ref = ty.ref
        local rcls = pvm.classof(ref)
        if rcls == Ty.TypeRefGlobal then return ref.type_name end
        if rcls == Ty.TypeRefLocal then return ref.sym.name end
        if rcls == Ty.TypeRefPath and #ref.path.parts > 0 then return ref.path.parts[#ref.path.parts].text end
        return nil
    end

    local function build_variant_defs(module, module_name)
        local defs = {}
        local function add_type_decl(t, mod_name)
            local cls = pvm.classof(t)
            if cls == Tr.TypeDeclEnumSugar then
                local variants = {}
                for i = 1, #t.variants do
                    local name = variant_name_text(t.variants[i])
                    variants[name] = { name = name, tag = i - 1, payload = Ty.TScalar(Core.ScalarVoid), fields = {} }
                end
                defs[t.name] = { type_name = t.name, ty = Ty.TNamed(Ty.TypeRefGlobal(mod_name, t.name)), variants = variants }
            elseif cls == Tr.TypeDeclTaggedUnionSugar then
                local variants = {}
                for i = 1, #t.variants do
                    local v = t.variants[i]
                    variants[v.name] = { name = v.name, tag = i - 1, payload = v.payload, fields = v.fields or {} }
                end
                defs[t.name] = { type_name = t.name, ty = Ty.TNamed(Ty.TypeRefGlobal(mod_name, t.name)), variants = variants }
            end
        end
        for i = 1, #(module.items or {}) do
            local item = module.items[i]
            local cls = pvm.classof(item)
            if cls == Tr.ItemType then add_type_decl(item.t, module_name)
            elseif cls == Tr.ItemUseModule then
                local nested = build_variant_defs(item.module, module_name)
                for k, v in pairs(nested) do defs[k] = v end
            end
        end
        return defs
    end

    local function func_key(module_name, item_name)
        return tostring(module_name or "") .. "\0" .. tostring(item_name or "")
    end

    local function code_func_id(item_name)
        return Code.CodeFuncId("fn:" .. tostring(item_name))
    end

    local function code_extern_id(name)
        return Code.CodeExternId("extern:" .. tostring(name))
    end

    local function code_global_id(module_name, item_name)
        return Code.CodeGlobalId("global:" .. tostring(module_name or "") .. ":" .. tostring(item_name or ""))
    end

    local function code_data_id(id)
        return Code.CodeDataId("data:" .. tostring(id and id.text or id))
    end

    local function decoded_string_bytes(bytes)
        bytes = tostring(bytes or "")
        local first = bytes:sub(1, 1)
        if (first == '"' or first == "'") and bytes:sub(-1) == first then
            local loader = loadstring or load
            local fn = loader("return " .. bytes)
            if fn then
                local ok, value = pcall(fn)
                if ok and type(value) == "string" then return value end
            end
        end
        return bytes
    end

    local function fresh_string_data(ctx, bytes)
        local module_ctx = ctx.module_ctx
        module_ctx.next_string_data = (module_ctx.next_string_data or 0) + 1
        local stem = "str_" .. sanitize(ctx.func_name) .. "_" .. tostring(module_ctx.next_string_data)
        local id = Code.CodeDataId("data:" .. tostring(module_ctx.module_name or "module") .. ":" .. stem)
        local nul_terminated = decoded_string_bytes(bytes) .. "\0"
        module_ctx.generated_data[#module_ctx.generated_data + 1] = Code.CodeData(
            id,
            stem,
            Code.CodeLinkageLocal,
            #nul_terminated,
            1,
            { Code.CodeDataBytes(0, nul_terminated) },
            Code.CodeOriginGenerated("string literal " .. stem)
        )
        return id
    end

    local function value_id_for_binding(ctx, binding)
        return Code.CodeValueId("v:" .. sanitize(ctx.func_name) .. ":" .. sanitize(binding_key(binding)))
    end

    local function local_id_for_binding(ctx, binding)
        return Code.CodeLocalId("local:" .. sanitize(ctx.func_name) .. ":" .. sanitize(binding_key(binding)))
    end

    local function origin_binding(binding)
        if binding ~= nil then return Code.CodeOriginBinding(binding) end
        return Code.CodeOriginUnknown
    end

    local function origin_generated(reason)
        return Code.CodeOriginGenerated(reason)
    end

    local function expr_type(expr)
        local h = expr and expr.h
        local cls = pvm.classof(h)
        if cls == Tr.ExprTyped or cls == Tr.ExprOpen then return h.ty end
        unsupported(nil, expr, "untyped expression " .. class_name(expr))
    end

    local function place_type(place)
        local h = place and place.h
        local cls = pvm.classof(h)
        if cls == Tr.PlaceTyped or cls == Tr.PlaceOpen then return h.ty end
        unsupported(nil, place, "untyped place " .. class_name(place))
    end

    local function index_base_elem_ty(base)
        local cls = pvm.classof(base)
        if cls == Tr.IndexBaseExpr then
            local ty = expr_type(base.base)
            local tcls = pvm.classof(ty)
            if tcls == Ty.TPtr or tcls == Ty.TArray or tcls == Ty.TSlice or tcls == Ty.TView then return ty.elem end
        elseif cls == Tr.IndexBasePlace then
            return base.elem
        elseif cls == Tr.IndexBaseView then
            return base.view.elem
        end
        unsupported(nil, base, "index base without element type " .. class_name(base))
    end

    local function code_ty(ctx, ty)
        return CodeType.type_to_code(ty, ctx.module_ctx)
    end

    local function variant_def(ctx, type_name)
        return ctx.module_ctx.variant_defs and ctx.module_ctx.variant_defs[type_name] or nil
    end

    local function variant_payload_ty(ctx, variant)
        if #(variant.fields or {}) > 1 then unsupported(ctx, variant, "multi-field variant payload `" .. tostring(variant.name) .. "`") end
        local ty = (#(variant.fields or {}) == 1) and variant.fields[1].ty or variant.payload
        if ty == nil or is_void_type(ty) then return nil end
        return ty
    end

    local function variant_ref(ctx, owner_ty, variant)
        local payload_ty = variant_payload_ty(ctx, variant)
        return Code.CodeVariantRef(code_ty(ctx, owner_ty), variant.name, variant.tag, payload_ty and code_ty(ctx, payload_ty) or nil)
    end

    local function variant_binding(kind, variant, bind)
        return Bind.Binding(Core.Id("variant:" .. kind .. ":" .. variant.name .. ":" .. bind.name), bind.name, bind.ty, Bind.BindingClassLocalValue)
    end

    local function is_float_code_ty(ty)
        return pvm.classof(ty) == Code.CodeTyFloat
    end

    local function is_aggregate_code_ty(ty)
        local cls = pvm.classof(ty)
        return cls == Code.CodeTyNamed or cls == Code.CodeTyArray or cls == Code.CodeTySlice or cls == Code.CodeTyView or cls == Code.CodeTyClosure
    end

    local function layout_of(ctx, ty)
        local result = TypeSizeAlign.result(ty, ctx.layout_env, ctx.target)
        if pvm.classof(result) == Ty.TypeMemLayoutKnown then return result.layout end
        return nil
    end

    local function align_of(ctx, ty)
        local layout = layout_of(ctx, ty)
        return layout and layout.align or 1
    end

    local function size_of(ctx, ty)
        local layout = layout_of(ctx, ty)
        return layout and layout.size or nil
    end

    local function new_temp(ctx, prefix)
        ctx.next_value = ctx.next_value + 1
        return Code.CodeValueId("v:" .. sanitize(ctx.func_name) .. ":" .. sanitize(prefix or "tmp") .. tostring(ctx.next_value))
    end

    local function new_inst_id(ctx, prefix)
        ctx.next_inst = ctx.next_inst + 1
        return Code.CodeInstId("inst:" .. sanitize(ctx.func_name) .. ":" .. sanitize(prefix or "i") .. tostring(ctx.next_inst))
    end

    local function new_term_id(ctx, prefix)
        ctx.next_term = ctx.next_term + 1
        return Code.CodeTermId("term:" .. sanitize(ctx.func_name) .. ":" .. sanitize(prefix or "t") .. tostring(ctx.next_term))
    end

    local function new_block_id(ctx, prefix)
        ctx.next_block = ctx.next_block + 1
        return Code.CodeBlockId("block:" .. sanitize(ctx.func_name) .. ":" .. sanitize(prefix or "b") .. tostring(ctx.next_block))
    end

    local function append_inst(ctx, kind, origin)
        if ctx.current_block == nil then unsupported(ctx, kind, "instruction after terminator") end
        ctx.current_block.insts[#ctx.current_block.insts + 1] = Code.CodeInst(new_inst_id(ctx), kind, origin or origin_generated("tree_to_code"))
    end

    local function start_block(ctx, id, name, params, origin)
        if ctx.current_block ~= nil then unsupported(ctx, id, "starting block before terminating current block") end
        ctx.current_block = { id = id, name = name, params = params or {}, insts = {}, origin = origin or origin_generated("block " .. tostring(name or "block")) }
    end

    local function terminate(ctx, kind, origin)
        if ctx.current_block == nil then unsupported(ctx, kind, "terminator without current block") end
        local term = Code.CodeTerm(new_term_id(ctx, "term"), kind, origin or origin_generated("terminator"))
        local block = ctx.current_block
        ctx.blocks[#ctx.blocks + 1] = Code.CodeBlock(block.id, block.name, block.params, block.insts, term, block.origin)
        ctx.current_block = nil
        return term
    end

    local function clone_map(t)
        local out = {}
        for k, v in pairs(t or {}) do out[k] = v end
        return out
    end

    local function save_bindings(ctx)
        return { bindings = clone_map(ctx.bindings), locals_by_key = clone_map(ctx.locals_by_key) }
    end

    local function restore_bindings(ctx, saved)
        ctx.bindings = clone_map(saved.bindings)
        ctx.locals_by_key = clone_map(saved.locals_by_key)
    end

    local function default_int_semantics()
        return Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftTrapOutOfRange)
    end

    local function default_float_mode()
        return Code.CodeFloatStrict
    end

    local function memory_access(ctx, mode, source_ty, code_type)
        return Code.CodeMemoryAccess(mode, code_type or code_ty(ctx, source_ty), align_of(ctx, source_ty), Code.CodeMayTrap, false, nil)
    end

    local function residence_for(ctx, binding, ty)
        local key = binding_key(binding)
        if ctx.addressed[key] then return Code.CodeResidenceAddressed end
        if is_aggregate_code_ty(code_ty(ctx, ty or binding.ty)) then return Code.CodeResidenceAggregate end
        return Code.CodeResidenceValue
    end

    local function ensure_local(ctx, binding, ty, residence)
        local key = binding_key(binding)
        local existing = ctx.locals_by_key[key]
        if existing ~= nil then return existing.id, existing.ty end
        local cty = code_ty(ctx, ty or binding.ty)
        local id = local_id_for_binding(ctx, binding)
        local local_ = Code.CodeLocal(id, binding.name, cty, residence or residence_for(ctx, binding, ty or binding.ty), origin_binding(binding))
        ctx.locals[#ctx.locals + 1] = local_
        ctx.locals_by_key[key] = { id = id, ty = cty, source_ty = ty or binding.ty }
        return id, cty
    end

    local collect_address_taken_expr, collect_address_taken_place, collect_address_taken_stmts

    local function mark_addressed_place(place, out)
        local cls = pvm.classof(place)
        if cls == Tr.PlaceRef and pvm.classof(place.ref) == Bind.ValueRefBinding then
            out.addressed[binding_key(place.ref.binding)] = true
        elseif cls == Tr.PlaceField or cls == Tr.PlaceDot then
            mark_addressed_place(place.base, out)
        elseif cls == Tr.PlaceIndex then
            -- Taking the address of an indexed place takes the address of the base storage.
            local bcls = pvm.classof(place.base)
            if bcls == Tr.IndexBasePlace then mark_addressed_place(place.base.base, out) end
        end
    end

    collect_address_taken_place = function(place, out)
        local cls = pvm.classof(place)
        if cls == Tr.PlaceRef then
            -- Plain stores/loads through a place do not make immutable values address-taken.
        elseif cls == Tr.PlaceDeref then
            collect_address_taken_expr(place.base, out)
        elseif cls == Tr.PlaceField or cls == Tr.PlaceDot then
            collect_address_taken_place(place.base, out)
        elseif cls == Tr.PlaceIndex then
            local bcls = pvm.classof(place.base)
            if bcls == Tr.IndexBaseExpr then collect_address_taken_expr(place.base.base, out)
            elseif bcls == Tr.IndexBasePlace then collect_address_taken_place(place.base.base, out)
            elseif bcls == Tr.IndexBaseView then collect_address_taken_expr(place.base.view.base, out) end
            collect_address_taken_expr(place.index, out)
        end
    end

    collect_address_taken_expr = function(expr, out)
        if expr == nil then return end
        local cls = pvm.classof(expr)
        if cls == Tr.ExprAddrOf then
            mark_addressed_place(expr.place, out)
            collect_address_taken_place(expr.place, out)
        elseif cls == Tr.ExprUnary or cls == Tr.ExprDeref or cls == Tr.ExprLen or cls == Tr.ExprIsNull then
            collect_address_taken_expr(expr.value, out)
        elseif cls == Tr.ExprBinary or cls == Tr.ExprCompare or cls == Tr.ExprLogic then
            collect_address_taken_expr(expr.lhs, out); collect_address_taken_expr(expr.rhs, out)
        elseif cls == Tr.ExprCast or cls == Tr.ExprMachineCast or cls == Tr.ExprLoad or cls == Tr.ExprAtomicLoad then
            collect_address_taken_expr(expr.value or expr.addr, out)
        elseif cls == Tr.ExprAtomicRmw then
            collect_address_taken_expr(expr.addr, out); collect_address_taken_expr(expr.value, out)
        elseif cls == Tr.ExprAtomicCas then
            collect_address_taken_expr(expr.addr, out); collect_address_taken_expr(expr.expected, out); collect_address_taken_expr(expr.replacement, out)
        elseif cls == Tr.ExprCall then
            collect_address_taken_expr(expr.callee, out)
            for i = 1, #(expr.args or {}) do collect_address_taken_expr(expr.args[i], out) end
        elseif cls == Tr.ExprField or cls == Tr.ExprDot then
            collect_address_taken_expr(expr.base, out)
        elseif cls == Tr.ExprIndex then
            local bcls = pvm.classof(expr.base)
            if bcls == Tr.IndexBaseExpr then collect_address_taken_expr(expr.base.base, out)
            elseif bcls == Tr.IndexBasePlace then collect_address_taken_place(expr.base.base, out)
            elseif bcls == Tr.IndexBaseView then collect_address_taken_expr(expr.base.view.base, out) end
            collect_address_taken_expr(expr.index, out)
        elseif cls == Tr.ExprIntrinsic or cls == Tr.ExprArray or cls == Tr.ExprCtor then
            for i = 1, #(expr.args or expr.elems or {}) do collect_address_taken_expr((expr.args or expr.elems)[i], out) end
        elseif cls == Tr.ExprAgg then
            for i = 1, #(expr.fields or {}) do collect_address_taken_expr(expr.fields[i].value, out) end
        elseif cls == Tr.ExprIf then
            collect_address_taken_expr(expr.cond, out); collect_address_taken_expr(expr.then_expr, out); collect_address_taken_expr(expr.else_expr, out)
        elseif cls == Tr.ExprSelect then
            collect_address_taken_expr(expr.cond, out); collect_address_taken_expr(expr.then_expr, out); collect_address_taken_expr(expr.else_expr, out)
        elseif cls == Tr.ExprSwitch then
            collect_address_taken_expr(expr.value, out)
            for i = 1, #(expr.arms or {}) do collect_address_taken_stmts(expr.arms[i].body, out); collect_address_taken_expr(expr.arms[i].result, out) end
            for i = 1, #(expr.variant_arms or {}) do collect_address_taken_stmts(expr.variant_arms[i].body, out); collect_address_taken_expr(expr.variant_arms[i].result, out) end
            collect_address_taken_stmts(expr.default_body or {}, out); collect_address_taken_expr(expr.default_expr, out)
        elseif cls == Tr.ExprControl then
            collect_address_taken_stmts(expr.region.entry.body, out)
            for i = 1, #(expr.region.blocks or {}) do collect_address_taken_stmts(expr.region.blocks[i].body, out) end
        elseif cls == Tr.ExprView then
            local vcls = pvm.classof(expr.view)
            if vcls == Tr.ViewFromExpr then collect_address_taken_expr(expr.view.base, out)
            elseif vcls == Tr.ViewContiguous then collect_address_taken_expr(expr.view.data, out); collect_address_taken_expr(expr.view.len, out)
            elseif vcls == Tr.ViewStrided then collect_address_taken_expr(expr.view.data, out); collect_address_taken_expr(expr.view.len, out); collect_address_taken_expr(expr.view.stride, out)
            elseif vcls == Tr.ViewRestrided then collect_address_taken_expr(expr.view.stride, out)
            elseif vcls == Tr.ViewWindow then collect_address_taken_expr(expr.view.start, out); collect_address_taken_expr(expr.view.len, out)
            elseif vcls == Tr.ViewRowBase then collect_address_taken_expr(expr.view.row_offset, out)
            elseif vcls == Tr.ViewInterleaved then collect_address_taken_expr(expr.view.data, out); collect_address_taken_expr(expr.view.len, out); collect_address_taken_expr(expr.view.stride, out); collect_address_taken_expr(expr.view.lane, out)
            elseif vcls == Tr.ViewInterleavedView then collect_address_taken_expr(expr.view.stride, out); collect_address_taken_expr(expr.view.lane, out) end
        elseif cls == Tr.ExprBlock then
            collect_address_taken_stmts(expr.stmts or {}, out); collect_address_taken_expr(expr.result, out)
        end
    end

    collect_address_taken_stmts = function(stmts, out)
        for i = 1, #(stmts or {}) do
            local stmt = stmts[i]
            local cls = pvm.classof(stmt)
            if cls == Tr.StmtLet then
                collect_address_taken_expr(stmt.init, out)
            elseif cls == Tr.StmtVar then
                out.mutable[binding_key(stmt.binding)] = true
                collect_address_taken_expr(stmt.init, out)
            elseif cls == Tr.StmtSet then
                collect_address_taken_place(stmt.place, out); collect_address_taken_expr(stmt.value, out)
            elseif cls == Tr.StmtAtomicStore then
                collect_address_taken_expr(stmt.addr, out); collect_address_taken_expr(stmt.value, out)
            elseif cls == Tr.StmtExpr or cls == Tr.StmtAssert or cls == Tr.StmtYieldValue or cls == Tr.StmtReturnValue then
                collect_address_taken_expr(stmt.expr or stmt.cond or stmt.value, out)
            elseif cls == Tr.StmtIf then
                collect_address_taken_expr(stmt.cond, out); collect_address_taken_stmts(stmt.then_body, out); collect_address_taken_stmts(stmt.else_body, out)
            elseif cls == Tr.StmtSwitch then
                collect_address_taken_expr(stmt.value, out)
                for j = 1, #(stmt.arms or {}) do collect_address_taken_stmts(stmt.arms[j].body, out) end
                for j = 1, #(stmt.variant_arms or {}) do collect_address_taken_stmts(stmt.variant_arms[j].body, out) end
                collect_address_taken_stmts(stmt.default_body or {}, out)
            elseif cls == Tr.StmtJump or cls == Tr.StmtJumpCont then
                for j = 1, #(stmt.args or {}) do collect_address_taken_expr(stmt.args[j].value, out) end
            elseif cls == Tr.StmtControl then
                collect_address_taken_stmts(stmt.region.entry.body, out)
                for j = 1, #(stmt.region.blocks or {}) do collect_address_taken_stmts(stmt.region.blocks[j].body, out) end
            end
        end
        return out
    end

    local lower_expr
    local lower_place
    local expr_as_place
    local lower_stmt
    local lower_stmt_body
    local lower_expr_if
    local lower_expr_switch
    local lower_expr_logic
    local lower_call
    local lower_control_region
    local lower_stmt_if
    local lower_stmt_switch

    local function lookup_binding(ctx, ref)
        if pvm.classof(ref) ~= Bind.ValueRefBinding then unsupported(ctx, ref, "non-binding value reference " .. class_name(ref)) end
        return ref.binding, binding_key(ref.binding)
    end

    local function load_place(ctx, place, source_ty, reason)
        local dst = new_temp(ctx, reason or "load")
        append_inst(ctx, Code.CodeInstLoad(dst, place, memory_access(ctx, Code.CodeMemoryRead, source_ty, code_ty(ctx, source_ty))), origin_generated(reason or "load"))
        return dst, code_ty(ctx, source_ty)
    end

    local function store_place(ctx, place, source_ty, value, origin)
        append_inst(ctx, Code.CodeInstStore(place, value, memory_access(ctx, Code.CodeMemoryWrite, source_ty, code_ty(ctx, source_ty))), origin or origin_generated("store"))
    end

    local function atomic_access(ctx, mode, source_ty, ordering)
        return Code.CodeMemoryAccess(mode, code_ty(ctx, source_ty), align_of(ctx, source_ty), Code.CodeMayTrap, true, ordering)
    end

    local function const_index(ctx, n, reason)
        local dst = new_temp(ctx, reason or "index_const")
        append_inst(ctx, Code.CodeInstConst(dst, Code.CodeConstLiteral(Code.CodeTyIndex, Core.LitInt(tostring(n)))), origin_generated(reason or "index const"))
        return dst, Code.CodeTyIndex
    end

    local function as_index_value(ctx, value, value_ty, reason)
        if value_ty == Code.CodeTyIndex then return value end
        local cls = pvm.classof(value_ty)
        local op = nil
        if cls == Code.CodeTyInt then
            if value_ty.bits < 64 then
                op = value_ty.signedness == Code.CodeSigned and Core.MachineCastSextend or Core.MachineCastUextend
            else
                op = Core.MachineCastBitcast
            end
        elseif value_ty == Code.CodeTyBool8 then
            op = Core.MachineCastUextend
        end
        if op == nil then unsupported(ctx, value_ty, "non-integer index value " .. class_name(value_ty)) end
        local dst = new_temp(ctx, reason or "to_index")
        append_inst(ctx, Code.CodeInstCast(dst, op, value_ty, Code.CodeTyIndex, value), origin_generated(reason or "index cast"))
        return dst
    end

    local function lower_view_parts(ctx, view)
        local vcls = pvm.classof(view)
        if vcls == Tr.ViewContiguous or vcls == Tr.ViewStrided then
            local data = lower_expr(ctx, view.data)
            local len = lower_expr(ctx, view.len)
            local stride
            if vcls == Tr.ViewStrided then stride = lower_expr(ctx, view.stride)
            else stride = const_index(ctx, 1, "view_stride") end
            return data, len, stride
        elseif vcls == Tr.ViewFromExpr then
            local base_ty = source_access_base(expr_type(view.base))
            if pvm.classof(base_ty) == Ty.TPtr then
                local data = lower_expr(ctx, view.base)
                local len = const_index(ctx, 1, "view_len")
                local stride = const_index(ctx, 1, "view_stride")
                return data, len, stride
            elseif pvm.classof(base_ty) == Ty.TView then
                local base = lower_expr(ctx, view.base)
                local data = new_temp(ctx, "view_data")
                local len = new_temp(ctx, "view_len")
                local stride = new_temp(ctx, "view_stride")
                append_inst(ctx, Code.CodeInstViewData(data, base), origin_generated("view data"))
                append_inst(ctx, Code.CodeInstViewLen(len, base), origin_generated("view len"))
                append_inst(ctx, Code.CodeInstViewStride(stride, base), origin_generated("view stride"))
                return data, len, stride
            end
        elseif vcls == Tr.ViewRestrided then
            local data, len = lower_view_parts(ctx, view.base)
            local stride = lower_expr(ctx, view.stride)
            return data, len, stride
        elseif vcls == Tr.ViewWindow then
            local data, _, stride = lower_view_parts(ctx, view.base)
            local start = lower_expr(ctx, view.start)
            local scaled = new_temp(ctx, "view_window_start")
            append_inst(ctx, Code.CodeInstBinary(scaled, Core.BinMul, Code.CodeTyIndex, default_int_semantics(), start, stride), origin_generated("view window start stride"))
            local ptr_ty = Code.CodeTyDataPtr(code_ty(ctx, view.elem))
            local window_data = new_temp(ctx, "view_window_data")
            local elem_size = size_of(ctx, view.elem)
            if elem_size == nil then unsupported(ctx, view, "view element without known size") end
            append_inst(ctx, Code.CodeInstPtrOffset(window_data, ptr_ty, data, scaled, elem_size, 0), origin_generated("view window data"))
            local len = lower_expr(ctx, view.len)
            return window_data, len, stride
        end
        unsupported(ctx, view, "view form " .. class_name(view))
    end

    local function lookup_value(ctx, ref)
        local binding, key = lookup_binding(ctx, ref)
        local local_info = ctx.locals_by_key[key]
        if local_info ~= nil then
            return load_place(ctx, Code.CodePlaceLocal(local_info.id, local_info.ty), binding.ty, "load_" .. binding.name)
        end
        local id = ctx.bindings[key]
        if id ~= nil then return id, code_ty(ctx, binding.ty) end
        local bcls = pvm.classof(binding.class)
        if bcls == Bind.BindingClassGlobalFunc then
            local fn = code_func_id(binding.class.item_name)
            local ptr_ty = code_ty(ctx, binding.ty)
            local dst = new_temp(ctx, "fnref")
            append_inst(ctx, Code.CodeInstGlobalRef(dst, Code.CodeGlobalRefFunc(fn), ptr_ty), origin_binding(binding))
            return dst, ptr_ty
        elseif bcls == Bind.BindingClassExtern then
            local ex = code_extern_id(binding.name)
            local ptr_ty = code_ty(ctx, binding.ty)
            local dst = new_temp(ctx, "externref")
            append_inst(ctx, Code.CodeInstGlobalRef(dst, Code.CodeGlobalRefExtern(ex), ptr_ty), origin_binding(binding))
            return dst, ptr_ty
        elseif bcls == Bind.BindingClassGlobalConst or bcls == Bind.BindingClassGlobalStatic then
            local gid = code_global_id(binding.class.module_name, binding.class.item_name)
            return load_place(ctx, Code.CodePlaceGlobal(gid, code_ty(ctx, binding.ty)), binding.ty, "load_global_" .. binding.name)
        end
        unsupported(ctx, ref, "unbound scalar reference `" .. tostring(binding.name) .. "`")
    end

    local function call_sig_id(ctx, fn_ty)
        local cls = pvm.classof(fn_ty)
        if cls == Ty.TFunc or cls == Ty.TClosure then
            return CodeType.ensure_type_sig(ctx.module_ctx, fn_ty.params, fn_ty.result)
        end
        unsupported(ctx, fn_ty, "non-callable type " .. class_name(fn_ty))
    end

    lower_call = function(ctx, expr)
        local fn_ty = expr_type(expr.callee)
        local sig = call_sig_id(ctx, fn_ty)
        local args = {}
        for i = 1, #(expr.args or {}) do args[i] = lower_expr(ctx, expr.args[i]) end
        local target
        if pvm.classof(expr.callee) == Tr.ExprRef and pvm.classof(expr.callee.ref) == Bind.ValueRefBinding then
            local binding = expr.callee.ref.binding
            local bcls = pvm.classof(binding.class)
            if bcls == Bind.BindingClassGlobalFunc then
                target = Code.CodeCallDirect(code_func_id(binding.class.item_name))
            elseif bcls == Bind.BindingClassExtern then
                target = Code.CodeCallExtern(code_extern_id(binding.name))
            end
        end
        if target == nil then
            local callee = lower_expr(ctx, expr.callee)
            if pvm.classof(fn_ty) == Ty.TClosure then
                target = Code.CodeCallClosure(callee, sig)
            else
                target = Code.CodeCallIndirect(callee, sig)
            end
        end
        local result_ty = code_ty(ctx, expr_type(expr))
        local dst = nil
        if result_ty ~= Code.CodeTyVoid then dst = new_temp(ctx, "call") end
        append_inst(ctx, Code.CodeInstCall(dst, target, sig, args), origin_generated("call"))
        return dst, result_ty
    end

    local function lower_field_base_place(ctx, base, base_ty)
        base_ty = source_access_base(base_ty)
        if pvm.classof(base_ty) == Ty.TPtr then
            local addr = lower_expr(ctx, base)
            local elem_ty = base_ty.elem
            return Code.CodePlaceDeref(addr, code_ty(ctx, elem_ty), align_of(ctx, elem_ty)), elem_ty
        end
        return expr_as_place(ctx, base), base_ty
    end

    local function lower_field_place(ctx, base, field)
        if pvm.classof(field) ~= Sem.FieldByOffset then unsupported(ctx, field, "field access before sem_layout_resolve") end
        local base_ty = expr_type(base)
        local base_place = lower_field_base_place(ctx, base, base_ty)
        local field_layout = layout_of(ctx, field.ty)
        return Code.CodePlaceField(base_place, field, code_ty(ctx, field.ty), field.offset, field_layout and field_layout.size or nil, field_layout and field_layout.align or nil)
    end

    local function lower_index_place(ctx, base, index, elem_ty)
        local idx, idx_ty = lower_expr(ctx, index)
        idx = as_index_value(ctx, idx, idx_ty, "index")
        local elem_size = size_of(ctx, elem_ty)
        if elem_size == nil then unsupported(ctx, base, "index element without known size") end
        local bcls = pvm.classof(base)
        local base_place
        if bcls == Tr.IndexBaseExpr then
            local base_ty = source_access_base(expr_type(base.base))
            local btcls = pvm.classof(base_ty)
            if btcls == Ty.TPtr then
                local addr = lower_expr(ctx, base.base)
                base_place = Code.CodePlaceDeref(addr, code_ty(ctx, elem_ty), align_of(ctx, elem_ty))
            elseif btcls == Ty.TView then
                local view = lower_expr(ctx, base.base)
                local data = new_temp(ctx, "view_index_data")
                local stride = new_temp(ctx, "view_index_stride")
                local scaled = new_temp(ctx, "view_index_scaled")
                append_inst(ctx, Code.CodeInstViewData(data, view), origin_generated("view index data"))
                append_inst(ctx, Code.CodeInstViewStride(stride, view), origin_generated("view index stride"))
                append_inst(ctx, Code.CodeInstBinary(scaled, Core.BinMul, Code.CodeTyIndex, default_int_semantics(), idx, stride), origin_generated("view index scale"))
                idx = scaled
                base_place = Code.CodePlaceDeref(data, code_ty(ctx, elem_ty), align_of(ctx, elem_ty))
            elseif btcls == Ty.TArray or btcls == Ty.TSlice or is_aggregate_code_ty(code_ty(ctx, base_ty)) then
                base_place = expr_as_place(ctx, base.base)
            else
                unsupported(ctx, base, "index expression base type " .. class_name(base_ty))
            end
        elseif bcls == Tr.IndexBasePlace then
            local base_ty = source_access_base(place_type(base.base))
            if pvm.classof(base_ty) == Ty.TView then
                local view = load_place(ctx, lower_place(ctx, base.base), base_ty, "view_index")
                local data = new_temp(ctx, "view_index_data")
                local stride = new_temp(ctx, "view_index_stride")
                local scaled = new_temp(ctx, "view_index_scaled")
                append_inst(ctx, Code.CodeInstViewData(data, view), origin_generated("view index data"))
                append_inst(ctx, Code.CodeInstViewStride(stride, view), origin_generated("view index stride"))
                append_inst(ctx, Code.CodeInstBinary(scaled, Core.BinMul, Code.CodeTyIndex, default_int_semantics(), idx, stride), origin_generated("view index scale"))
                idx = scaled
                base_place = Code.CodePlaceDeref(data, code_ty(ctx, elem_ty), align_of(ctx, elem_ty))
            else
                base_place = lower_place(ctx, base.base)
            end
        elseif bcls == Tr.IndexBaseView then
            local data, _, stride = lower_view_parts(ctx, base.view)
            local scaled = new_temp(ctx, "view_index_scaled")
            append_inst(ctx, Code.CodeInstBinary(scaled, Core.BinMul, Code.CodeTyIndex, default_int_semantics(), idx, stride), origin_generated("view index scale"))
            idx = scaled
            base_place = Code.CodePlaceDeref(data, code_ty(ctx, elem_ty), align_of(ctx, elem_ty))
        else
            unsupported(ctx, base, "index base " .. class_name(base))
        end
        return Code.CodePlaceIndex(base_place, idx, code_ty(ctx, elem_ty), elem_size)
    end

    lower_place = function(ctx, place)
        local cls = pvm.classof(place)
        if cls == Tr.PlaceRef then
            local binding, key = lookup_binding(ctx, place.ref)
            local bcls = pvm.classof(binding.class)
            if bcls == Bind.BindingClassGlobalConst or bcls == Bind.BindingClassGlobalStatic then
                return Code.CodePlaceGlobal(code_global_id(binding.class.module_name, binding.class.item_name), code_ty(ctx, binding.ty))
            end
            local local_info = ctx.locals_by_key[key]
            if local_info == nil then
                if ctx.addressed[key] or ctx.mutable[key] or is_aggregate_code_ty(code_ty(ctx, binding.ty)) then
                    ensure_local(ctx, binding, binding.ty)
                    local_info = ctx.locals_by_key[key]
                else
                    unsupported(ctx, place, "address/store of value-resident binding `" .. tostring(binding.name) .. "`")
                end
            end
            return Code.CodePlaceLocal(local_info.id, local_info.ty)
        elseif cls == Tr.PlaceDeref then
            local addr = lower_expr(ctx, place.base)
            local ty = place_type(place)
            return Code.CodePlaceDeref(addr, code_ty(ctx, ty), align_of(ctx, ty))
        elseif cls == Tr.PlaceField then
            if pvm.classof(place.field) ~= Sem.FieldByOffset then unsupported(ctx, place, "field place before sem_layout_resolve") end
            local base_ty = source_access_base(place_type(place.base))
            local base_place
            if pvm.classof(base_ty) == Ty.TPtr and pvm.classof(place.base) == Tr.PlaceRef then
                local addr = lower_expr(ctx, Tr.ExprRef(Tr.ExprTyped(base_ty), place.base.ref))
                base_place = Code.CodePlaceDeref(addr, code_ty(ctx, base_ty.elem), align_of(ctx, base_ty.elem))
            else
                base_place = lower_place(ctx, place.base)
            end
            local field_layout = layout_of(ctx, place.field.ty)
            return Code.CodePlaceField(base_place, place.field, code_ty(ctx, place.field.ty), place.field.offset, field_layout and field_layout.size or nil, field_layout and field_layout.align or nil)
        elseif cls == Tr.PlaceIndex then
            return lower_index_place(ctx, place.base, place.index, place_type(place))
        elseif cls == Tr.PlaceDot then
            unsupported(ctx, place, "dot place before sem_layout_resolve")
        end
        unsupported(ctx, place, "place " .. class_name(place))
    end

    expr_as_place = function(ctx, expr)
        local cls = pvm.classof(expr)
        if cls == Tr.ExprRef then return lower_place(ctx, Tr.PlaceRef(Tr.PlaceTyped(expr_type(expr)), expr.ref)) end
        if cls == Tr.ExprDeref then return Code.CodePlaceDeref(lower_expr(ctx, expr.value), code_ty(ctx, expr_type(expr)), align_of(ctx, expr_type(expr))) end
        if cls == Tr.ExprField then return lower_field_place(ctx, expr.base, expr.field) end
        if cls == Tr.ExprIndex then return lower_index_place(ctx, expr.base, expr.index, expr_type(expr)) end
        unsupported(ctx, expr, "expression is not addressable " .. class_name(expr))
    end

    lower_expr = function(ctx, expr)
        local cls = pvm.classof(expr)
        if cls == Tr.ExprLit then
            local ty = code_ty(ctx, expr_type(expr))
            if pvm.classof(expr.value) == Core.LitString then
                local dst = new_temp(ctx, "str")
                local data_id = fresh_string_data(ctx, expr.value.bytes)
                append_inst(ctx, Code.CodeInstGlobalRef(dst, Code.CodeGlobalRefData(data_id), ty), origin_generated("string literal data ref"))
                return dst, ty
            end
            local dst = new_temp(ctx, "lit")
            append_inst(ctx, Code.CodeInstConst(dst, Code.CodeConstLiteral(ty, expr.value)), origin_generated("literal"))
            return dst, ty
        elseif cls == Tr.ExprRef then
            return lookup_value(ctx, expr.ref)
        elseif cls == Tr.ExprUnary then
            local value = lower_expr(ctx, expr.value)
            local ty = code_ty(ctx, expr_type(expr))
            local dst = new_temp(ctx, "unary")
            append_inst(ctx, Code.CodeInstUnary(dst, expr.op, ty, value), origin_generated("unary"))
            return dst, ty
        elseif cls == Tr.ExprBinary then
            local lhs = lower_expr(ctx, expr.lhs)
            local rhs = lower_expr(ctx, expr.rhs)
            local ty = code_ty(ctx, expr_type(expr))
            local dst = new_temp(ctx, "bin")
            if is_float_code_ty(ty) then
                append_inst(ctx, Code.CodeInstFloatBinary(dst, expr.op, ty, default_float_mode(), lhs, rhs), origin_generated("float binary"))
            else
                append_inst(ctx, Code.CodeInstBinary(dst, expr.op, ty, default_int_semantics(), lhs, rhs), origin_generated("binary"))
            end
            return dst, ty
        elseif cls == Tr.ExprCompare then
            local lhs = lower_expr(ctx, expr.lhs)
            local rhs = lower_expr(ctx, expr.rhs)
            local operand_ty = code_ty(ctx, expr_type(expr.lhs))
            local dst = new_temp(ctx, "cmp")
            append_inst(ctx, Code.CodeInstCompare(dst, expr.op, operand_ty, lhs, rhs), origin_generated("compare"))
            return dst, Code.CodeTyBool8
        elseif cls == Tr.ExprLogic then
            return lower_expr_logic(ctx, expr)
        elseif cls == Tr.ExprIf then
            return lower_expr_if(ctx, expr)
        elseif cls == Tr.ExprSwitch then
            return lower_expr_switch(ctx, expr)
        elseif cls == Tr.ExprControl then
            return lower_control_region(ctx, expr.region, true)
        elseif cls == Tr.ExprBlock then
            local saved = save_bindings(ctx)
            lower_stmt_body(ctx, expr.stmts or {})
            if ctx.current_block == nil then unsupported(ctx, expr, "expression block body terminated before result") end
            local value, ty = lower_expr(ctx, expr.result)
            restore_bindings(ctx, saved)
            return value, ty
        elseif cls == Tr.ExprMachineCast then
            local value, from = lower_expr(ctx, expr.value)
            local to = code_ty(ctx, expr.ty or expr_type(expr))
            local dst = new_temp(ctx, "cast")
            append_inst(ctx, Code.CodeInstCast(dst, expr.op, from, to, value), origin_generated("cast"))
            return dst, to
        elseif cls == Tr.ExprCast then
            unsupported(ctx, expr, "surface cast after typechecking")
        elseif cls == Tr.ExprSelect then
            local cond = lower_expr(ctx, expr.cond)
            local then_value = lower_expr(ctx, expr.then_expr)
            local else_value = lower_expr(ctx, expr.else_expr)
            local ty = code_ty(ctx, expr_type(expr))
            local dst = new_temp(ctx, "select")
            append_inst(ctx, Code.CodeInstSelect(dst, ty, cond, then_value, else_value), origin_generated("select"))
            return dst, ty
        elseif cls == Tr.ExprAddrOf then
            local place = lower_place(ctx, expr.place)
            local ptr_ty = code_ty(ctx, expr_type(expr))
            local dst = new_temp(ctx, "addr")
            append_inst(ctx, Code.CodeInstAddrOf(dst, ptr_ty, place), origin_generated("address of"))
            return dst, ptr_ty
        elseif cls == Tr.ExprIntrinsic then
            local args = {}
            for i = 1, #(expr.args or {}) do args[i] = lower_expr(ctx, expr.args[i]) end
            local ty = code_ty(ctx, expr_type(expr))
            local dst = ty ~= Code.CodeTyVoid and new_temp(ctx, "intrin") or nil
            append_inst(ctx, Code.CodeInstIntrinsic(dst, expr.op, ty, args), origin_generated("intrinsic"))
            return dst, ty
        elseif cls == Tr.ExprAgg then
            local ty = code_ty(ctx, expr.ty or expr_type(expr))
            local fields = {}
            for i = 1, #(expr.fields or {}) do
                local fi = expr.fields[i]
                local value = lower_expr(ctx, fi.value)
                fields[#fields + 1] = Code.CodeFieldValue(Sem.FieldByOffset(fi.name, fi.offset or 0, expr_type(fi.value), Host.HostRepOpaque("tree_to_code.aggregate")), value)
            end
            local dst = new_temp(ctx, "agg")
            append_inst(ctx, Code.CodeInstAggregate(dst, ty, fields), origin_generated("aggregate"))
            return dst, ty
        elseif cls == Tr.ExprArray then
            local ty = code_ty(ctx, expr_type(expr))
            local elems = {}
            for i = 1, #(expr.elems or {}) do elems[#elems + 1] = Code.CodeArrayValue(i - 1, lower_expr(ctx, expr.elems[i])) end
            local dst = new_temp(ctx, "array")
            append_inst(ctx, Code.CodeInstArray(dst, ty, elems), origin_generated("array"))
            return dst, ty
        elseif cls == Tr.ExprView then
            local data, len, stride = lower_view_parts(ctx, expr.view)
            local ty = code_ty(ctx, expr_type(expr))
            local dst = new_temp(ctx, "view")
            append_inst(ctx, Code.CodeInstViewMake(dst, ty.elem, data, len, stride), origin_generated("view"))
            return dst, ty
        elseif cls == Tr.ExprLen then
            local vty = source_access_base(expr_type(expr.value))
            if pvm.classof(vty) == Ty.TArray and pvm.classof(vty.count) == Ty.ArrayLenConst then
                return const_index(ctx, vty.count.count, "array_len")
            elseif pvm.classof(vty) == Ty.TView then
                local view = lower_expr(ctx, expr.value)
                local dst = new_temp(ctx, "view_len")
                append_inst(ctx, Code.CodeInstViewLen(dst, view), origin_generated("view len"))
                return dst, Code.CodeTyIndex
            end
            unsupported(ctx, expr, "len of non-array/view")
        elseif cls == Tr.ExprSizeOf then
            local n = size_of(ctx, expr.ty)
            if n == nil then unsupported(ctx, expr, "sizeof type without known layout") end
            return const_index(ctx, n, "sizeof")
        elseif cls == Tr.ExprAlignOf then
            return const_index(ctx, align_of(ctx, expr.ty), "alignof")
        elseif cls == Tr.ExprIsNull then
            local value, ty = lower_expr(ctx, expr.value)
            local null_value = new_temp(ctx, "null_cmp")
            append_inst(ctx, Code.CodeInstConst(null_value, Code.CodeConstNull(ty)), origin_generated("null compare literal"))
            local dst = new_temp(ctx, "is_null")
            append_inst(ctx, Code.CodeInstCompare(dst, Core.CmpEq, ty, value, null_value), origin_generated("is null"))
            return dst, Code.CodeTyBool8
        elseif cls == Tr.ExprCall then
            return lower_call(ctx, expr)
        elseif cls == Tr.ExprDeref then
            local place = Code.CodePlaceDeref(lower_expr(ctx, expr.value), code_ty(ctx, expr_type(expr)), align_of(ctx, expr_type(expr)))
            return load_place(ctx, place, expr_type(expr), "deref")
        elseif cls == Tr.ExprField then
            return load_place(ctx, lower_field_place(ctx, expr.base, expr.field), expr_type(expr), "field")
        elseif cls == Tr.ExprIndex then
            return load_place(ctx, lower_index_place(ctx, expr.base, expr.index, expr_type(expr)), expr_type(expr), "index")
        elseif cls == Tr.ExprLoad then
            local place = Code.CodePlaceDeref(lower_expr(ctx, expr.addr), code_ty(ctx, expr.ty or expr_type(expr)), align_of(ctx, expr.ty or expr_type(expr)))
            return load_place(ctx, place, expr.ty or expr_type(expr), "load")
        elseif cls == Tr.ExprAtomicLoad then
            local ty = expr.ty or expr_type(expr)
            local place = Code.CodePlaceDeref(lower_expr(ctx, expr.addr), code_ty(ctx, ty), align_of(ctx, ty))
            local dst = new_temp(ctx, "atomic_load")
            append_inst(ctx, Code.CodeInstAtomicLoad(dst, place, atomic_access(ctx, Code.CodeMemoryRead, ty, expr.ordering), expr.ordering), origin_generated("atomic load"))
            return dst, code_ty(ctx, ty)
        elseif cls == Tr.ExprAtomicRmw then
            local ty = expr.ty or expr_type(expr)
            local place = Code.CodePlaceDeref(lower_expr(ctx, expr.addr), code_ty(ctx, ty), align_of(ctx, ty))
            local value = lower_expr(ctx, expr.value)
            local dst = new_temp(ctx, "atomic_rmw")
            append_inst(ctx, Code.CodeInstAtomicRmw(dst, expr.op, place, value, atomic_access(ctx, Code.CodeMemoryReadWrite, ty, expr.ordering), expr.ordering), origin_generated("atomic rmw"))
            return dst, code_ty(ctx, ty)
        elseif cls == Tr.ExprAtomicCas then
            local ty = expr.ty or expr_type(expr)
            local place = Code.CodePlaceDeref(lower_expr(ctx, expr.addr), code_ty(ctx, ty), align_of(ctx, ty))
            local expected = lower_expr(ctx, expr.expected)
            local replacement = lower_expr(ctx, expr.replacement)
            local dst = new_temp(ctx, "atomic_cas")
            append_inst(ctx, Code.CodeInstAtomicCas(dst, place, expected, replacement, atomic_access(ctx, Code.CodeMemoryReadWrite, ty, expr.ordering), expr.ordering), origin_generated("atomic cas"))
            return dst, code_ty(ctx, ty)
        elseif cls == Tr.ExprCtor then
            if #(expr.args or {}) > 1 then unsupported(ctx, expr, "multi-argument variant constructor `" .. tostring(expr.type_name) .. "." .. tostring(expr.variant_name) .. "`") end
            local def = variant_def(ctx, expr.type_name)
            local variant = def and def.variants[expr.variant_name] or nil
            if variant == nil then unsupported(ctx, expr, "unknown variant constructor `" .. tostring(expr.type_name) .. "." .. tostring(expr.variant_name) .. "`") end
            local owner_ty = expr_type(expr)
            local payload = nil
            if #(expr.args or {}) == 1 then payload = lower_expr(ctx, expr.args[1]) end
            local dst = new_temp(ctx, "variant_ctor")
            append_inst(ctx, Code.CodeInstVariantCtor(dst, code_ty(ctx, owner_ty), variant_ref(ctx, owner_ty, variant), payload), origin_generated("variant constructor"))
            return dst, code_ty(ctx, owner_ty)
        elseif cls == Tr.ExprNull then
            local ty = code_ty(ctx, expr_type(expr))
            local dst = new_temp(ctx, "null")
            append_inst(ctx, Code.CodeInstConst(dst, Code.CodeConstNull(ty)), origin_generated("null"))
            return dst, ty
        end
        unsupported(ctx, expr, "expression " .. class_name(expr))
    end

    local function bind_alias(ctx, binding, src, ty)
        local dst = value_id_for_binding(ctx, binding)
        ctx.bindings[binding_key(binding)] = dst
        append_inst(ctx, Code.CodeInstAlias(dst, ty, src), origin_binding(binding))
        return dst
    end

    local function bind_local_init(ctx, binding, init_value, source_ty, is_mutable)
        local residence = is_mutable and Code.CodeResidenceAddressed or residence_for(ctx, binding, source_ty)
        local local_id, local_ty = ensure_local(ctx, binding, source_ty, residence)
        store_place(ctx, Code.CodePlaceLocal(local_id, local_ty), source_ty, init_value, origin_binding(binding))
        return local_id
    end

    local function lower_variant_binds(ctx, kind, owner_value, owner_ty, variant, arm)
        if #(arm.binds or {}) == 0 then return end
        if #(arm.binds or {}) > 1 then unsupported(ctx, arm, "multi-bind variant arm `" .. tostring(variant.name) .. "`") end
        local payload_ty = variant_payload_ty(ctx, variant)
        if payload_ty == nil then unsupported(ctx, arm, "payload bind for void variant `" .. tostring(variant.name) .. "`") end
        local ref = variant_ref(ctx, owner_ty, variant)
        local payload = new_temp(ctx, "variant_payload")
        append_inst(ctx, Code.CodeInstVariantPayload(payload, ref, owner_value), origin_generated("variant payload"))
        local binding = variant_binding(kind, variant, arm.binds[1])
        local ty = code_ty(ctx, binding.ty)
        if ctx.addressed[binding_key(binding)] or is_aggregate_code_ty(ty) then
            bind_local_init(ctx, binding, payload, binding.ty, false)
        else
            bind_alias(ctx, binding, payload, ty)
        end
    end

    local function label_key(label)
        return label and label.name or tostring(label)
    end

    local function find_jump_arg(args, name)
        local found = nil
        for i = 1, #(args or {}) do
            if args[i].name == name then
                if found ~= nil then unsupported(nil, args[i], "duplicate jump arg `" .. tostring(name) .. "`") end
                found = args[i]
            end
        end
        if found == nil then unsupported(nil, name, "missing jump arg `" .. tostring(name) .. "`") end
        return found
    end

    local function control_binding(region_id, label, param, index, is_entry)
        local class = is_entry and Bind.BindingClassEntryBlockParam(region_id, label.name, index) or Bind.BindingClassBlockParam(region_id, label.name, index)
        return Bind.Binding(Core.Id("control:param:" .. region_id .. ":" .. label.name .. ":" .. param.name), param.name, param.ty, class)
    end

    local function switch_literal(raw)
        if raw == "true" then return Core.LitBool(true) end
        if raw == "false" then return Core.LitBool(false) end
        if type(raw) == "string" and raw:match("^[+-]?%d+$") then return Core.LitInt(raw) end
        unsupported(nil, raw, "non-literal switch case `" .. tostring(raw) .. "`")
    end

    local function lower_stmt_fallthrough_to(ctx, body, block_id, name, join_id)
        start_block(ctx, block_id, name, {}, origin_generated(name))
        local saved = save_bindings(ctx)
        lower_stmt_body(ctx, body or {})
        local falls = ctx.current_block ~= nil
        if falls then terminate(ctx, Code.CodeTermJump(join_id, {}), origin_generated(name .. " fallthrough")) end
        restore_bindings(ctx, saved)
        return falls
    end

    lower_stmt_if = function(ctx, stmt)
        local cond = lower_expr(ctx, stmt.cond)
        local then_id = new_block_id(ctx, "if_then")
        local else_id = new_block_id(ctx, "if_else")
        local join_id = new_block_id(ctx, "if_join")
        local saved = save_bindings(ctx)
        terminate(ctx, Code.CodeTermBranch(cond, then_id, {}, else_id, {}), origin_generated("if branch"))
        restore_bindings(ctx, saved)
        local then_falls = lower_stmt_fallthrough_to(ctx, stmt.then_body, then_id, "if.then", join_id)
        restore_bindings(ctx, saved)
        local else_falls = lower_stmt_fallthrough_to(ctx, stmt.else_body, else_id, "if.else", join_id)
        restore_bindings(ctx, saved)
        if then_falls or else_falls then
            start_block(ctx, join_id, "if.join", {}, origin_generated("if join"))
        end
    end

    lower_stmt_switch = function(ctx, stmt)
        if #(stmt.variant_arms or {}) > 0 then
            if #(stmt.arms or {}) > 0 then unsupported(ctx, stmt, "mixed scalar and variant switch arms") end
            local owner_ty = expr_type(stmt.value)
            local type_name = named_type_name(owner_ty)
            local def = type_name and variant_def(ctx, type_name) or nil
            if def == nil then unsupported(ctx, stmt, "variant switch without tagged-union facts") end
            local value = lower_expr(ctx, stmt.value)
            local tag = new_temp(ctx, "variant_tag")
            append_inst(ctx, Code.CodeInstVariantTag(tag, Code.CodeTyInt(32, Code.CodeUnsigned), value), origin_generated("variant tag"))
            local case_ids = {}
            local cases = {}
            for i = 1, #(stmt.variant_arms or {}) do
                local arm = stmt.variant_arms[i]
                local variant = def.variants[arm.variant_name]
                if variant == nil then unsupported(ctx, stmt, "unknown variant arm `" .. tostring(arm.variant_name) .. "`") end
                local bid = new_block_id(ctx, "switch_variant_case")
                case_ids[i] = bid
                cases[i] = Code.CodeVariantCase(variant_ref(ctx, owner_ty, variant), bid, {})
            end
            local default_id = new_block_id(ctx, "switch_variant_default")
            local join_id = new_block_id(ctx, "switch_variant_join")
            local saved = save_bindings(ctx)
            terminate(ctx, Code.CodeTermVariantSwitch(tag, cases, default_id, {}), origin_generated("variant switch"))
            local any_falls = false
            for i = 1, #(stmt.variant_arms or {}) do
                restore_bindings(ctx, saved)
                local arm = stmt.variant_arms[i]
                local variant = def.variants[arm.variant_name]
                start_block(ctx, case_ids[i], "switch.variant.case", {}, origin_generated("variant switch case"))
                lower_variant_binds(ctx, "stmt_switch", value, owner_ty, variant, arm)
                lower_stmt_body(ctx, arm.body or {})
                if ctx.current_block ~= nil then terminate(ctx, Code.CodeTermJump(join_id, {}), origin_generated("variant switch case fallthrough")); any_falls = true end
            end
            restore_bindings(ctx, saved)
            if lower_stmt_fallthrough_to(ctx, stmt.default_body or {}, default_id, "switch.variant.default", join_id) then any_falls = true end
            restore_bindings(ctx, saved)
            if any_falls then start_block(ctx, join_id, "switch.variant.join", {}, origin_generated("variant switch join")) end
            return
        end
        local value = lower_expr(ctx, stmt.value)
        local case_ids = {}
        local cases = {}
        for i = 1, #(stmt.arms or {}) do
            local bid = new_block_id(ctx, "switch_case")
            case_ids[i] = bid
            cases[i] = Code.CodeSwitchCase(switch_literal(stmt.arms[i].raw_key), bid, {})
        end
        local default_id = new_block_id(ctx, "switch_default")
        local join_id = new_block_id(ctx, "switch_join")
        local saved = save_bindings(ctx)
        terminate(ctx, Code.CodeTermSwitch(value, cases, default_id, {}), origin_generated("switch"))
        local any_falls = false
        for i = 1, #(stmt.arms or {}) do
            restore_bindings(ctx, saved)
            if lower_stmt_fallthrough_to(ctx, stmt.arms[i].body, case_ids[i], "switch.case", join_id) then any_falls = true end
        end
        restore_bindings(ctx, saved)
        if lower_stmt_fallthrough_to(ctx, stmt.default_body or {}, default_id, "switch.default", join_id) then any_falls = true end
        restore_bindings(ctx, saved)
        if any_falls then start_block(ctx, join_id, "switch.join", {}, origin_generated("switch join")) end
    end

    lower_expr_if = function(ctx, expr)
        local cond = lower_expr(ctx, expr.cond)
        local then_id = new_block_id(ctx, "expr_if_then")
        local else_id = new_block_id(ctx, "expr_if_else")
        local join_id = new_block_id(ctx, "expr_if_join")
        local result_ty = code_ty(ctx, expr_type(expr))
        local result_value = new_temp(ctx, "if_result")
        local result_param = Code.CodeParam(result_value, "result", result_ty, origin_generated("if expression result"))
        local saved = save_bindings(ctx)
        terminate(ctx, Code.CodeTermBranch(cond, then_id, {}, else_id, {}), origin_generated("if expression branch"))
        restore_bindings(ctx, saved)
        start_block(ctx, then_id, "expr.if.then", {}, origin_generated("if expression then"))
        local then_value = lower_expr(ctx, expr.then_expr)
        terminate(ctx, Code.CodeTermJump(join_id, { then_value }), origin_generated("if expression then yield"))
        restore_bindings(ctx, saved)
        start_block(ctx, else_id, "expr.if.else", {}, origin_generated("if expression else"))
        local else_value = lower_expr(ctx, expr.else_expr)
        terminate(ctx, Code.CodeTermJump(join_id, { else_value }), origin_generated("if expression else yield"))
        restore_bindings(ctx, saved)
        start_block(ctx, join_id, "expr.if.join", { result_param }, origin_generated("if expression join"))
        return result_value, result_ty
    end

    lower_expr_logic = function(ctx, expr)
        local lhs = lower_expr(ctx, expr.lhs)
        local rhs_id = new_block_id(ctx, "logic_rhs")
        local short_id = new_block_id(ctx, "logic_short")
        local join_id = new_block_id(ctx, "logic_join")
        local result_value = new_temp(ctx, "logic_result")
        local result_param = Code.CodeParam(result_value, "result", Code.CodeTyBool8, origin_generated("logic result"))
        if expr.op == Core.LogicAnd then
            terminate(ctx, Code.CodeTermBranch(lhs, rhs_id, {}, short_id, {}), origin_generated("logic and branch"))
        elseif expr.op == Core.LogicOr then
            terminate(ctx, Code.CodeTermBranch(lhs, short_id, {}, rhs_id, {}), origin_generated("logic or branch"))
        else
            unsupported(ctx, expr, "logic op " .. class_name(expr.op))
        end
        local saved = save_bindings(ctx)
        start_block(ctx, rhs_id, "logic.rhs", {}, origin_generated("logic rhs"))
        local rhs = lower_expr(ctx, expr.rhs)
        terminate(ctx, Code.CodeTermJump(join_id, { rhs }), origin_generated("logic rhs yield"))
        restore_bindings(ctx, saved)
        start_block(ctx, short_id, "logic.short", {}, origin_generated("logic short"))
        local lit = expr.op == Core.LogicAnd and Core.LitBool(false) or Core.LitBool(true)
        local short_value = new_temp(ctx, "logic_short")
        append_inst(ctx, Code.CodeInstConst(short_value, Code.CodeConstLiteral(Code.CodeTyBool8, lit)), origin_generated("logic short-circuit literal"))
        terminate(ctx, Code.CodeTermJump(join_id, { short_value }), origin_generated("logic short yield"))
        restore_bindings(ctx, saved)
        start_block(ctx, join_id, "logic.join", { result_param }, origin_generated("logic join"))
        return result_value, Code.CodeTyBool8
    end

    lower_expr_switch = function(ctx, expr)
        if #(expr.variant_arms or {}) > 0 then
            if #(expr.arms or {}) > 0 then unsupported(ctx, expr, "mixed scalar and variant switch expression arms") end
            local owner_ty = expr_type(expr.value)
            local type_name = named_type_name(owner_ty)
            local def = type_name and variant_def(ctx, type_name) or nil
            if def == nil then unsupported(ctx, expr, "variant switch expression without tagged-union facts") end
            local value = lower_expr(ctx, expr.value)
            local tag = new_temp(ctx, "variant_tag")
            append_inst(ctx, Code.CodeInstVariantTag(tag, Code.CodeTyInt(32, Code.CodeUnsigned), value), origin_generated("variant tag"))
            local result_ty = code_ty(ctx, expr_type(expr))
            local result_value = new_temp(ctx, "switch_result")
            local result_param = Code.CodeParam(result_value, "result", result_ty, origin_generated("variant switch expression result"))
            local case_ids = {}
            local cases = {}
            for i = 1, #(expr.variant_arms or {}) do
                local arm = expr.variant_arms[i]
                local variant = def.variants[arm.variant_name]
                if variant == nil then unsupported(ctx, expr, "unknown variant arm `" .. tostring(arm.variant_name) .. "`") end
                local bid = new_block_id(ctx, "expr_switch_variant_case")
                case_ids[i] = bid
                cases[i] = Code.CodeVariantCase(variant_ref(ctx, owner_ty, variant), bid, {})
            end
            local default_id = new_block_id(ctx, "expr_switch_variant_default")
            local join_id = new_block_id(ctx, "expr_switch_variant_join")
            local saved = save_bindings(ctx)
            terminate(ctx, Code.CodeTermVariantSwitch(tag, cases, default_id, {}), origin_generated("variant switch expression"))
            local any_falls = false
            for i = 1, #(expr.variant_arms or {}) do
                restore_bindings(ctx, saved)
                local arm = expr.variant_arms[i]
                local variant = def.variants[arm.variant_name]
                start_block(ctx, case_ids[i], "expr.switch.variant.case", {}, origin_generated("variant switch expression case"))
                lower_variant_binds(ctx, "expr_switch", value, owner_ty, variant, arm)
                lower_stmt_body(ctx, arm.body or {})
                if ctx.current_block ~= nil then
                    local arm_value = lower_expr(ctx, arm.result)
                    terminate(ctx, Code.CodeTermJump(join_id, { arm_value }), origin_generated("variant switch expression case yield"))
                    any_falls = true
                end
            end
            restore_bindings(ctx, saved)
            start_block(ctx, default_id, "expr.switch.variant.default", {}, origin_generated("variant switch expression default"))
            lower_stmt_body(ctx, expr.default_body or {})
            if ctx.current_block ~= nil then
                local default_value = lower_expr(ctx, expr.default_expr)
                terminate(ctx, Code.CodeTermJump(join_id, { default_value }), origin_generated("variant switch expression default yield"))
                any_falls = true
            end
            restore_bindings(ctx, saved)
            if not any_falls then unsupported(ctx, expr, "variant switch expression has no value-producing arm") end
            start_block(ctx, join_id, "expr.switch.variant.join", { result_param }, origin_generated("variant switch expression join"))
            return result_value, result_ty
        end
        local value = lower_expr(ctx, expr.value)
        local result_ty = code_ty(ctx, expr_type(expr))
        local result_value = new_temp(ctx, "switch_result")
        local result_param = Code.CodeParam(result_value, "result", result_ty, origin_generated("switch expression result"))
        local case_ids = {}
        local cases = {}
        for i = 1, #(expr.arms or {}) do
            local bid = new_block_id(ctx, "expr_switch_case")
            case_ids[i] = bid
            cases[i] = Code.CodeSwitchCase(switch_literal(expr.arms[i].raw_key), bid, {})
        end
        local default_id = new_block_id(ctx, "expr_switch_default")
        local join_id = new_block_id(ctx, "expr_switch_join")
        local saved = save_bindings(ctx)
        terminate(ctx, Code.CodeTermSwitch(value, cases, default_id, {}), origin_generated("switch expression"))
        local any_falls = false
        for i = 1, #(expr.arms or {}) do
            restore_bindings(ctx, saved)
            start_block(ctx, case_ids[i], "expr.switch.case", {}, origin_generated("switch expression case"))
            lower_stmt_body(ctx, expr.arms[i].body or {})
            if ctx.current_block ~= nil then
                local arm_value = lower_expr(ctx, expr.arms[i].result)
                terminate(ctx, Code.CodeTermJump(join_id, { arm_value }), origin_generated("switch expression case yield"))
                any_falls = true
            end
        end
        restore_bindings(ctx, saved)
        start_block(ctx, default_id, "expr.switch.default", {}, origin_generated("switch expression default"))
        lower_stmt_body(ctx, expr.default_body or {})
        if ctx.current_block ~= nil then
            local default_value = lower_expr(ctx, expr.default_expr)
            terminate(ctx, Code.CodeTermJump(join_id, { default_value }), origin_generated("switch expression default yield"))
            any_falls = true
        end
        restore_bindings(ctx, saved)
        if not any_falls then unsupported(ctx, expr, "switch expression has no value-producing arm") end
        start_block(ctx, join_id, "expr.switch.join", { result_param }, origin_generated("switch expression join"))
        return result_value, result_ty
    end

    lower_control_region = function(ctx, region, is_expr)
        local result_ty = is_expr and code_ty(ctx, region.result_ty) or nil
        local result_value = is_expr and new_temp(ctx, "control_result") or nil
        local exit_params = {}
        if is_expr then exit_params[1] = Code.CodeParam(result_value, "result", result_ty, origin_generated("control result")) end
        local records = {}
        local labels = {}
        local function add_record(block, is_entry)
            local bid = new_block_id(ctx, "ctl_" .. block.label.name)
            local params = {}
            local bindings = {}
            for i = 1, #(block.params or {}) do
                local b = control_binding(region.region_id, block.label, block.params[i], i, is_entry)
                local v = value_id_for_binding(ctx, b)
                local ty = code_ty(ctx, block.params[i].ty)
                params[#params + 1] = Code.CodeParam(v, block.params[i].name, ty, origin_binding(b))
                bindings[#bindings + 1] = { binding = b, value = v, ty = block.params[i].ty, code_ty = ty }
            end
            local rec = { id = bid, label = block.label, name = "ctl." .. block.label.name, params = params, bindings = bindings, body = block.body or {}, entry = is_entry, entry_params = block.params or {} }
            records[#records + 1] = rec
            labels[label_key(block.label)] = rec
            return rec
        end
        local entry = add_record(region.entry, true)
        for i = 1, #(region.blocks or {}) do add_record(region.blocks[i], false) end
        local exit_id = new_block_id(ctx, is_expr and "ctl_expr_exit" or "ctl_stmt_exit")
        local saved_outer = save_bindings(ctx)
        local entry_args = {}
        for i = 1, #(region.entry.params or {}) do
            entry_args[#entry_args + 1] = lower_expr(ctx, region.entry.params[i].init)
        end
        terminate(ctx, Code.CodeTermJump(entry.id, entry_args), origin_generated("enter control region"))
        local outer_control = ctx.control_region
        local control_region = { labels = labels, exit_id = exit_id, is_expr = is_expr, has_exit = false }
        ctx.control_region = control_region
        local saved_region_outer = saved_outer
        for i = 1, #records do
            local rec = records[i]
            restore_bindings(ctx, saved_region_outer)
            start_block(ctx, rec.id, rec.name, rec.params, origin_generated("control block " .. rec.label.name))
            for j = 1, #rec.bindings do
                local b = rec.bindings[j]
                ctx.bindings[binding_key(b.binding)] = b.value
                if ctx.addressed[binding_key(b.binding)] or is_aggregate_code_ty(b.code_ty) then
                    bind_local_init(ctx, b.binding, b.value, b.ty, false)
                end
            end
            lower_stmt_body(ctx, rec.body)
            if ctx.current_block ~= nil then unsupported(ctx, rec.label, "control block `" .. tostring(rec.label.name) .. "` can fall through") end
        end
        ctx.control_region = outer_control
        restore_bindings(ctx, saved_outer)
        if control_region.has_exit or is_expr then
            start_block(ctx, exit_id, is_expr and "ctl.expr.exit" or "ctl.stmt.exit", exit_params, origin_generated("control exit"))
        end
        if is_expr then return result_value, result_ty end
    end

    lower_stmt = function(ctx, stmt)
        if ctx.current_block == nil then return end
        local cls = pvm.classof(stmt)
        if cls == Tr.StmtLet then
            local src, ty = lower_expr(ctx, stmt.init)
            local key = binding_key(stmt.binding)
            if ctx.addressed[key] or is_aggregate_code_ty(ty) then bind_local_init(ctx, stmt.binding, src, stmt.binding.ty, false)
            else bind_alias(ctx, stmt.binding, src, ty) end
        elseif cls == Tr.StmtVar then
            local src = lower_expr(ctx, stmt.init)
            ctx.mutable[binding_key(stmt.binding)] = true
            bind_local_init(ctx, stmt.binding, src, stmt.binding.ty, true)
        elseif cls == Tr.StmtSet then
            local value = lower_expr(ctx, stmt.value)
            store_place(ctx, lower_place(ctx, stmt.place), place_type(stmt.place), value, origin_generated("set"))
        elseif cls == Tr.StmtAtomicStore then
            local value = lower_expr(ctx, stmt.value)
            local place = Code.CodePlaceDeref(lower_expr(ctx, stmt.addr), code_ty(ctx, stmt.ty), align_of(ctx, stmt.ty))
            append_inst(ctx, Code.CodeInstAtomicStore(place, value, atomic_access(ctx, Code.CodeMemoryWrite, stmt.ty, stmt.ordering), stmt.ordering), origin_generated("atomic store"))
        elseif cls == Tr.StmtAtomicFence then
            append_inst(ctx, Code.CodeInstAtomicFence(stmt.ordering), origin_generated("atomic fence"))
        elseif cls == Tr.StmtExpr then
            lower_expr(ctx, stmt.expr)
        elseif cls == Tr.StmtIf then
            lower_stmt_if(ctx, stmt)
        elseif cls == Tr.StmtSwitch then
            lower_stmt_switch(ctx, stmt)
        elseif cls == Tr.StmtControl then
            lower_control_region(ctx, stmt.region, false)
        elseif cls == Tr.StmtJump then
            local region = ctx.control_region
            if region == nil then unsupported(ctx, stmt, "jump outside control region") end
            local target = region.labels[label_key(stmt.target)]
            if target == nil then unsupported(ctx, stmt, "missing control target `" .. tostring(stmt.target.name) .. "`") end
            local args = {}
            for i = 1, #target.params do
                local arg = find_jump_arg(stmt.args, target.params[i].name)
                args[#args + 1] = lower_expr(ctx, arg.value)
            end
            terminate(ctx, Code.CodeTermJump(target.id, args), origin_generated("control jump"))
        elseif cls == Tr.StmtJumpCont then
            unsupported(ctx, stmt, "continuation slot jump after open expansion")
        elseif cls == Tr.StmtYieldValue then
            local region = ctx.control_region
            if region == nil or not region.is_expr then unsupported(ctx, stmt, "value yield outside expression control region") end
            local value = lower_expr(ctx, stmt.value)
            region.has_exit = true
            terminate(ctx, Code.CodeTermJump(region.exit_id, { value }), origin_generated("control yield value"))
        elseif cls == Tr.StmtYieldVoid then
            local region = ctx.control_region
            if region == nil or region.is_expr then unsupported(ctx, stmt, "void yield outside statement control region") end
            region.has_exit = true
            terminate(ctx, Code.CodeTermJump(region.exit_id, {}), origin_generated("control yield"))
        elseif cls == Tr.StmtReturnValue then
            local value = lower_expr(ctx, stmt.value)
            terminate(ctx, Code.CodeTermReturn({ value }), origin_generated("return"))
        elseif cls == Tr.StmtReturnVoid then
            terminate(ctx, Code.CodeTermReturn({}), origin_generated("return"))
        elseif cls == Tr.StmtTrap then
            terminate(ctx, Code.CodeTermTrap("source trap"), origin_generated("trap"))
        elseif cls == Tr.StmtAssert then
            local cond = lower_expr(ctx, stmt.cond)
            local ok_id = new_block_id(ctx, "assert_ok")
            local trap_id = new_block_id(ctx, "assert_trap")
            terminate(ctx, Code.CodeTermBranch(cond, ok_id, {}, trap_id, {}), origin_generated("assert branch"))
            start_block(ctx, trap_id, "assert.trap", {}, origin_generated("assert trap"))
            terminate(ctx, Code.CodeTermTrap("assertion failed"), origin_generated("assert trap"))
            start_block(ctx, ok_id, "assert.ok", {}, origin_generated("assert ok"))
        else
            unsupported(ctx, stmt, "statement " .. class_name(stmt))
        end
    end

    lower_stmt_body = function(ctx, body)
        for i = 1, #(body or {}) do
            if ctx.current_block == nil then return end
            lower_stmt(ctx, body[i])
        end
    end

    local function func_parts(func)
        local cls = pvm.classof(func)
        if cls == Tr.FuncLocal then return func.name, Code.CodeLinkageLocal, func.params, func.result, func.body end
        if cls == Tr.FuncExport then return func.name, Code.CodeLinkageExport, func.params, func.result, func.body end
        if cls == Tr.FuncLocalContract then return func.name, Code.CodeLinkageLocal, func.params, func.result, func.body end
        if cls == Tr.FuncExportContract then return func.name, Code.CodeLinkageExport, func.params, func.result, func.body end
        unsupported(nil, func, "function " .. class_name(func))
    end

    local function param_binding(Core, Bind, func_name, param, index)
        return Bind.Binding(Core.Id("arg:" .. func_name .. ":" .. param.name), param.name, param.ty, Bind.BindingClassArg(index - 1))
    end

    local function param_types(params)
        local out = {}
        for i = 1, #(params or {}) do out[i] = params[i].ty end
        return out
    end

    local function global_init_for_const(ctx, source_ty, value_expr, site)
        local value = ConstEval.value(value_expr, ctx.module_ctx.const_env, ConstEval.empty_local_env())
        local cls = pvm.classof(value)
        local ty = code_ty(ctx, source_ty)
        if cls == Sem.ConstInt then return { Code.CodeDataScalar(0, ty, Core.LitInt(value.raw)) } end
        if cls == Sem.ConstFloat then return { Code.CodeDataScalar(0, ty, Core.LitFloat(value.raw)) } end
        if cls == Sem.ConstBool then return { Code.CodeDataScalar(0, ty, Core.LitBool(value.value)) } end
        unsupported(ctx, value_expr, "non-scalar constant initializer for global `" .. tostring(site) .. "`")
    end

    local function lower_global(module_ctx, name, source_ty, value_expr)
        local ctx = { module_ctx = module_ctx, layout_env = module_ctx.layout_env, target = module_ctx.target, func_name = module_ctx.module_name }
        local inits = global_init_for_const(ctx, source_ty, value_expr, name)
        return Code.CodeGlobal(code_global_id(module_ctx.module_name, name), name, code_ty(ctx, source_ty), Code.CodeLinkageLocal, size_of(ctx, source_ty), align_of(ctx, source_ty), inits, origin_generated("global " .. tostring(name)))
    end

    local function contract_value_for_binding(func_name, binding)
        return value_id_for_binding({ func_name = func_name }, binding)
    end

    local function contract_value_for_expr(func_name, expr)
        if pvm.classof(expr) == Tr.ExprRef and pvm.classof(expr.ref) == Bind.ValueRefBinding then
            return contract_value_for_binding(func_name, expr.ref.binding)
        end
        return nil, "contract expression is not a lowered binding reference: " .. class_name(expr)
    end

    local function code_contract_reject(func_id, reason)
        return Code.CodeFuncContractFact(
            func_id,
            Code.CodeContractRejected(tostring(reason or "unsupported contract fact")),
            origin_generated("contract rejection")
        )
    end

    local function join_reasons(...)
        local out = {}
        for i = 1, select("#", ...) do
            local reason = select(i, ...)
            if reason ~= nil then out[#out + 1] = tostring(reason) end
        end
        return table.concat(out, "; ")
    end

    local function code_contract_fact(func_name, func_id, fact)
        local cls = pvm.classof(fact)
        if cls == Tr.ContractFactBounds then
            return Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(
                contract_value_for_binding(func_name, fact.base),
                contract_value_for_binding(func_name, fact.len)
            ), origin_binding(fact.base))
        elseif cls == Tr.ContractFactWindowBounds then
            local base = contract_value_for_binding(func_name, fact.base)
            local base_len, base_len_err = contract_value_for_expr(func_name, fact.base_len)
            local start, start_err = contract_value_for_expr(func_name, fact.start)
            local len, len_err = contract_value_for_expr(func_name, fact.len)
            if base_len == nil or start == nil or len == nil then
                return code_contract_reject(func_id, join_reasons(base_len_err, start_err, len_err))
            end
            return Code.CodeFuncContractFact(func_id, Code.CodeContractWindowBounds(base, base_len, start, len), origin_binding(fact.base))
        elseif cls == Tr.ContractFactDisjoint then
            return Code.CodeFuncContractFact(func_id, Code.CodeContractDisjoint(
                contract_value_for_binding(func_name, fact.a),
                contract_value_for_binding(func_name, fact.b)
            ), origin_binding(fact.a))
        elseif cls == Tr.ContractFactSameLen then
            return Code.CodeFuncContractFact(func_id, Code.CodeContractSameLen(
                contract_value_for_binding(func_name, fact.a),
                contract_value_for_binding(func_name, fact.b)
            ), origin_binding(fact.a))
        elseif cls == Tr.ContractFactNoAlias then
            return Code.CodeFuncContractFact(func_id, Code.CodeContractNoAlias(
                contract_value_for_binding(func_name, fact.base)
            ), origin_binding(fact.base))
        elseif cls == Tr.ContractFactReadonly then
            return Code.CodeFuncContractFact(func_id, Code.CodeContractReadonly(
                contract_value_for_binding(func_name, fact.base)
            ), origin_binding(fact.base))
        elseif cls == Tr.ContractFactWriteonly then
            return Code.CodeFuncContractFact(func_id, Code.CodeContractWriteonly(
                contract_value_for_binding(func_name, fact.base)
            ), origin_binding(fact.base))
        elseif cls == Tr.ContractFactInvalidate then
            return Code.CodeFuncContractFact(func_id, Code.CodeContractInvalidate(
                contract_value_for_binding(func_name, fact.base)
            ), origin_binding(fact.base))
        elseif cls == Tr.ContractFactPreserve then
            return Code.CodeFuncContractFact(func_id, Code.CodeContractPreserve(
                contract_value_for_binding(func_name, fact.base)
            ), origin_binding(fact.base))
        elseif cls == Tr.ContractFactRejected then
            return code_contract_reject(func_id, "tree contract rejected: " .. class_name(fact.issue))
        end
        return code_contract_reject(func_id, "unsupported tree contract fact: " .. class_name(fact))
    end

    local function lower_contracts(module, opts)
        opts = opts or {}
        local mod_id = Code.CodeModuleId("module:" .. sanitize(opts.module_id or module_name(module)))
        local facts = {}
        for i = 1, #(module.items or {}) do
            local item = module.items[i]
            if pvm.classof(item) == Tr.ItemFunc then
                local name = func_parts(item.func)
                local func_id = code_func_id(name)
                local tree_facts = TreeContractFacts.facts(item.func)
                for j = 1, #(tree_facts.facts or {}) do
                    facts[#facts + 1] = code_contract_fact(name, func_id, tree_facts.facts[j])
                end
            end
        end
        return Code.CodeContractFactSet(mod_id, facts)
    end

    local function lower_func(module_ctx, func)
        local name, linkage, params, result_ty, body = func_parts(func)
        local residence = collect_address_taken_stmts(body or {}, { addressed = {}, mutable = {} })
        local ctx = {
            module_ctx = module_ctx,
            layout_env = module_ctx.layout_env,
            target = module_ctx.target,
            func_name = name,
            bindings = {},
            locals_by_key = {},
            addressed = residence.addressed,
            mutable = residence.mutable,
            locals = {},
            blocks = {},
            current_block = nil,
            next_value = 0,
            next_inst = 0,
            next_term = 0,
            next_block = 0,
        }

        local entry = Code.CodeBlockId("block:" .. sanitize(name) .. ":entry")
        start_block(ctx, entry, "entry", {}, origin_generated("entry block"))

        local code_params = {}
        local sig_params = {}
        for i = 1, #(params or {}) do
            local p = params[i]
            local binding = param_binding(Core, Bind, name, p, i)
            local ty = code_ty(ctx, p.ty)
            local value = value_id_for_binding(ctx, binding)
            ctx.bindings[binding_key(binding)] = value
            code_params[#code_params + 1] = Code.CodeParam(value, p.name, ty, origin_binding(binding))
            sig_params[#sig_params + 1] = ty
            if ctx.addressed[binding_key(binding)] or is_aggregate_code_ty(ty) then
                bind_local_init(ctx, binding, value, p.ty, false)
            end
        end

        local result = code_ty(ctx, result_ty)
        local sig_results = {}
        if result ~= Code.CodeTyVoid then sig_results[#sig_results + 1] = result end
        local sig = CodeType.ensure_code_sig(module_ctx, sig_params, sig_results)

        lower_stmt_body(ctx, body or {})
        if ctx.current_block ~= nil then
            if result == Code.CodeTyVoid then
                terminate(ctx, Code.CodeTermReturn({}), origin_generated("void fallthrough"))
            else
                unsupported(ctx, func, "non-void function without return")
            end
        end

        return Code.CodeFunc(Code.CodeFuncId("fn:" .. name), name, linkage, sig, code_params, ctx.locals, entry, ctx.blocks, origin_generated("function " .. name))
    end

    local function lower_module(module, opts)
        opts = opts or {}
        local layout_env = opts.layout_env
        if layout_env == nil then layout_env = T.MoonSem.LayoutEnv(ModuleType.env(module, opts.target).layouts) end
        local mod_name = module_name(module)
        local const_entries = {}
        for i = 1, #(module.items or {}) do
            local item = module.items[i]
            if pvm.classof(item) == Tr.ItemConst then
                local c = item.c
                if pvm.classof(c) == Tr.ConstItem then const_entries[#const_entries + 1] = Bind.ConstEntry(mod_name, c.name, c.ty, c.value) end
            end
        end
        local module_ctx = { code_sigs = {}, code_sig_order = {}, layout_env = layout_env, target = opts.target, module_name = mod_name, funcs = {}, externs = {}, variant_defs = build_variant_defs(module, mod_name), const_env = Bind.ConstEnv(const_entries), generated_data = {}, next_string_data = 0 }
        local externs = {}
        for i = 1, #(module.items or {}) do
            local item = module.items[i]
            local cls = pvm.classof(item)
            if cls == Tr.ItemFunc then
                local name, _, params, result_ty = func_parts(item.func)
                local sig = CodeType.ensure_type_sig(module_ctx, param_types(params), result_ty)
                module_ctx.funcs[func_key(module_ctx.module_name, name)] = { id = code_func_id(name), sig = sig }
            elseif cls == Tr.ItemExtern then
                local f = item.func
                if pvm.classof(f) ~= Tr.ExternFunc then unsupported({ func_name = module_ctx.module_name }, f, "open extern after expansion") end
                local param_tys = {}
                for j = 1, #(f.params or {}) do param_tys[j] = f.params[j].ty end
                local sig = CodeType.ensure_type_sig(module_ctx, param_tys, f.result)
                local ex = Code.CodeExtern(code_extern_id(f.name), f.name, f.symbol, sig, origin_generated("extern " .. f.name))
                module_ctx.externs[f.name] = ex
                externs[#externs + 1] = ex
            end
        end
        local funcs = {}
        local data = {}
        local globals = {}
        for i = 1, #(module.items or {}) do
            local item = module.items[i]
            local cls = pvm.classof(item)
            if cls == Tr.ItemFunc then
                funcs[#funcs + 1] = lower_func(module_ctx, item.func)
            elseif cls == Tr.ItemData then
                data[#data + 1] = Code.CodeData(code_data_id(item.data.id), item.data.id.text, Code.CodeLinkageLocal, item.data.size, item.data.align, { Code.CodeDataBytes(0, item.data.bytes) }, origin_generated("data " .. tostring(item.data.id.text)))
            elseif cls == Tr.ItemConst then
                if pvm.classof(item.c) ~= Tr.ConstItem then unsupported({ func_name = mod_name }, item, "open const item after expansion") end
                globals[#globals + 1] = lower_global(module_ctx, item.c.name, item.c.ty, item.c.value)
            elseif cls == Tr.ItemStatic then
                if pvm.classof(item.s) ~= Tr.StaticItem then unsupported({ func_name = mod_name }, item, "open static item after expansion") end
                globals[#globals + 1] = lower_global(module_ctx, item.s.name, item.s.ty, item.s.value)
            elseif cls == Tr.ItemExtern or cls == Tr.ItemType or cls == Tr.ItemImport then
                -- Declarations do not produce executable MoonCode blocks.
            else
                unsupported({ func_name = module_name(module) }, item, "module item " .. class_name(item))
            end
        end
        for i = 1, #module_ctx.generated_data do data[#data + 1] = module_ctx.generated_data[i] end
        return Code.CodeModule(
            Code.CodeModuleId("module:" .. sanitize(opts.module_id or module_name(module))),
            module_ctx.code_sig_order,
            {}, data, globals, externs, funcs,
            origin_generated("tree_to_code module")
        )
    end

    local function lower_module_with_contracts(module, opts)
        return lower_module(module, opts), lower_contracts(module, opts)
    end

    api.module = lower_module
    api.contracts = lower_contracts
    api.module_with_contracts = lower_module_with_contracts

    T._moonlift_api_cache.tree_to_code = api
    return api
end

return M
