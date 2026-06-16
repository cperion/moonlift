local pvm = require("moonlift.pvm")
local bit = require("bit")

local M = {}

local function append_all(dst, src)
    for i = 1, #(src or {}) do dst[#dst + 1] = src[i] end
    return dst
end

local function safe_name(s)
    s = tostring(s or "anon"):gsub("[^%w_]", "_")
    if s == "" then s = "anon" end
    if not s:match("^[_%a]") then s = "_" .. s end
    return s
end

local function stable_hash(s)
    local h = 2166136261
    for i = 1, #s do
        h = bit.bxor(h, s:byte(i))
        h = bit.tobit(h * 16777619)
    end
    return bit.tohex(h, 8)
end

local function class_name(x)
    local cls = pvm.classof(x)
    return cls and (cls.__name or tostring(cls)) or type(x)
end

local function scalar_name(s)
    if type(s) == "table" then return class_name(s) end
    return tostring(s)
end

function M.safe_name(s) return safe_name(s) end

function M.Define(T, cb)
    cb = cb or {}
    local C = T.MoonCore
    local Ty = T.MoonType
    local B = T.MoonBind
    local O = T.MoonOpen
    local Tr = T.MoonTree

    local wrappers = {}
    local order = {}
    local site_seq = 0

    local void_ty = Ty.TScalar(C.ScalarVoid)

    local function name_ref_text(name)
        local cls = pvm.classof(name)
        if cls == O.NameRefText then return name.text end
        if cls == O.NameRefSlot then return "slot_" .. safe_name(name.slot.key) end
        return tostring(name)
    end

    local function type_key(ty)
        local cls = pvm.classof(ty)
        if cls == Ty.TScalar then return "scalar(" .. scalar_name(ty.scalar) .. ")" end
        if cls == Ty.TPtr then return "ptr(" .. type_key(ty.elem) .. ")" end
        if cls == Ty.TArray then return "array(" .. class_name(ty.count) .. "," .. type_key(ty.elem) .. ")" end
        if cls == Ty.TSlice then return "slice(" .. type_key(ty.elem) .. ")" end
        if cls == Ty.TView then return "view(" .. type_key(ty.elem) .. ")" end
        if cls == Ty.TLease then return "lease(" .. type_key(ty.base) .. ")" end
        if cls == Ty.THandle then return "handle(" .. class_name(ty.ref) .. ")" end
        if cls == Ty.TFunc or cls == Ty.TClosure then
            local parts = {}
            for i = 1, #(ty.params or {}) do parts[#parts + 1] = type_key(ty.params[i]) end
            return class_name(ty) .. "(" .. table.concat(parts, ",") .. ")->" .. type_key(ty.result)
        end
        if cls == Ty.TNamed then
            local r = ty.ref
            local rcls = pvm.classof(r)
            if rcls == Ty.TypeRefGlobal then return "named(" .. r.module_name .. "." .. r.type_name .. ")" end
            if rcls == Ty.TypeRefPath then
                local parts = {}
                for i = 1, #r.path.parts do parts[#parts + 1] = r.path.parts[i].text or r.path.parts[i].name or tostring(r.path.parts[i]) end
                return "named(" .. table.concat(parts, ".") .. ")"
            end
            if rcls == Ty.TypeRefLocal then return "named(local:" .. r.sym.key .. ")" end
            if rcls == Ty.TypeRefSlot then return "named(slot:" .. r.slot.key .. ")" end
        end
        if cls == Ty.TSlot then return "slot(" .. ty.slot.key .. ")" end
        return tostring(ty)
    end

    local function type_contains_lease(ty)
        local cls = pvm.classof(ty)
        if cls == Ty.TLease then return true end
        if cls == Ty.TPtr then return type_contains_lease(ty.elem) end
        if cls == Ty.TArray then return type_contains_lease(ty.elem) end
        if cls == Ty.TSlice then return type_contains_lease(ty.elem) end
        if cls == Ty.TView then return type_contains_lease(ty.elem) end
        if cls == Ty.TFunc or cls == Ty.TClosure then
            for i = 1, #(ty.params or {}) do if type_contains_lease(ty.params[i]) then return true end end
            return type_contains_lease(ty.result)
        end
        return false
    end

    local function frag_key(frag)
        local parts = { "region", name_ref_text(frag.name), "params" }
        for i = 1, #(frag.params or {}) do
            parts[#parts + 1] = frag.params[i].name .. ":" .. type_key(frag.params[i].ty)
        end
        parts[#parts + 1] = "conts"
        for i = 1, #(frag.conts or {}) do
            local cont = frag.conts[i]
            parts[#parts + 1] = cont.pretty_name
            for j = 1, #(cont.params or {}) do
                parts[#parts + 1] = cont.params[j].name .. ":" .. type_key(cont.params[j].ty)
            end
        end
        return table.concat(parts, "|")
    end

    local function names_for_frag(frag)
        local key = frag_key(frag)
        local base = safe_name(name_ref_text(frag.name))
        local hash = stable_hash(key)
        return {
            key = key,
            hash = hash,
            base = base,
            result = "__moon_region_call_" .. base .. "_" .. hash .. "_result",
            fn = "__moon_region_call_" .. base .. "_" .. hash .. "_fn",
            region = "__moon_region_call_" .. base .. "_" .. hash .. "_region",
        }
    end

    local function result_named_type(result_name)
        -- Use a path reference so normal module type canonicalization resolves
        -- the generated result to the current module identity.  Hard-coding an
        -- empty TypeRefGlobal works only for surface/anonymous modules and
        -- splits identity in hosted ModuleTyped bundles.
        return Ty.TNamed(Ty.TypeRefPath(C.Path({ C.Name(result_name) })))
    end

    local function result_type_for_frag(frag, result_name)
        local variants = {}
        for i = 1, #(frag.conts or {}) do
            local cont = frag.conts[i]
            local fields = {}
            for j = 1, #(cont.params or {}) do
                fields[#fields + 1] = Ty.FieldDecl(cont.params[j].name, cont.params[j].ty)
            end
            variants[#variants + 1] = Ty.VariantDecl(cont.pretty_name, void_ty, fields)
        end
        return Tr.TypeDeclTaggedUnionSugar(result_name, variants)
    end

    local function runtime_arg_exprs(frag)
        local args = {}
        for i = 1, #(frag.params or {}) do
            args[#args + 1] = Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(frag.params[i].name))
        end
        return args
    end

    local function wrapper_func_for_frag(frag, names)
        local params = {}
        for i = 1, #(frag.params or {}) do
            params[#params + 1] = Ty.Param(frag.params[i].name, frag.params[i].ty)
        end

        local cont_fills = {}
        local ret_blocks = {}
        for i = 1, #(frag.conts or {}) do
            local cont = frag.conts[i]
            local label = Tr.BlockLabel("__ret_" .. safe_name(cont.pretty_name))
            cont_fills[#cont_fills + 1] = O.ContBinding(cont.pretty_name, O.ContTargetLabel(label))

            local block_params = {}
            local ctor_args = {}
            for j = 1, #(cont.params or {}) do
                local p = cont.params[j]
                block_params[#block_params + 1] = Tr.BlockParam(p.name, p.ty)
                ctor_args[#ctor_args + 1] = Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(p.name))
            end
            ret_blocks[#ret_blocks + 1] = Tr.ControlBlock(label, block_params, {
                Tr.StmtYieldValue(Tr.StmtSurface, Tr.ExprCtor(Tr.ExprSurface, names.result, cont.pretty_name, ctor_args)),
            })
        end

        local frag_name = name_ref_text(frag.name)
        local emit_stmt = Tr.StmtUseRegionFrag(
            Tr.StmtSurface,
            Tr.RegionUseEmit,
            "emit." .. safe_name(frag_name) .. "." .. names.hash .. ".wrapper",
            O.RegionFragRefName(frag_name),
            runtime_arg_exprs(frag),
            {},
            cont_fills
        )
        local region = Tr.ControlExprRegion(
            names.region,
            result_named_type(names.result),
            Tr.EntryControlBlock(Tr.BlockLabel("start"), {}, { emit_stmt }),
            ret_blocks
        )
        return Tr.FuncLocal(names.fn, params, result_named_type(names.result), {
            Tr.StmtReturnValue(Tr.StmtSurface, Tr.ExprControl(Tr.ExprSurface, region)),
        })
    end

    local function ensure_wrapper(frag)
        local names = names_for_frag(frag)
        local rec = wrappers[names.key]
        if rec ~= nil then return rec end
        local result_decl = result_type_for_frag(frag, names.result)
        local wrapper_func = wrapper_func_for_frag(frag, names)
        rec = {
            key = names.key,
            names = names,
            result_type = result_decl,
            wrapper_func = wrapper_func,
            items = { Tr.ItemType(result_decl), Tr.ItemFunc(wrapper_func) },
            emitted = false,
        }
        wrappers[names.key] = rec
        order[#order + 1] = names.key
        table.sort(order)
        return rec
    end

    local function pending_wrappers()
        local out = {}
        for i = 1, #order do
            local rec = wrappers[order[i]]
            if rec then out[#out + 1] = rec end
        end
        return out
    end

    local function mark_emitted(key)
        if wrappers[key] then wrappers[key].emitted = true end
    end

    local function expanded_expr(expr, env)
        if cb.expand_expr then return cb.expand_expr(expr, env) end
        return expr
    end

    local function expanded_stmt_header(h, env)
        if cb.expand_stmt_header then return cb.expand_stmt_header(h, env) end
        return h
    end

    local function call_site_result_name(stmt)
        site_seq = site_seq + 1
        return "__moon_region_call_result_" .. tostring(site_seq) .. "_" .. stable_hash(tostring(stmt.use_id or site_seq)):sub(1, 8)
    end

    local function rebase_label(label, map)
        return (map and map[label.name]) or label
    end

    local function jump_to_target(target, args, label_map)
        local cls = pvm.classof(target)
        if cls == O.ContTargetLabel then
            return Tr.StmtJump(Tr.StmtSurface, rebase_label(target.label, label_map), args)
        elseif cls == O.ContTargetSlot then
            return Tr.StmtJumpCont(Tr.StmtSurface, target.slot, args)
        end
        return Tr.StmtTrap(Tr.StmtSurface)
    end

    local function cont_target_for_name(stmt, name)
        for i = 1, #(stmt.cont_fills or {}) do
            if stmt.cont_fills[i].name == name then return stmt.cont_fills[i].target end
        end
        return nil
    end

    local function lower_call_use(stmt, env, label_map)
        local frag = cb.lookup_region_frag_ref and cb.lookup_region_frag_ref(stmt.frag, env) or nil
        if frag == nil or frag == pvm.NIL then
            return { pvm.with(stmt, { h = expanded_stmt_header(stmt.h, env), args = (cb.expand_exprs and cb.expand_exprs(stmt.args, env)) or stmt.args }) }
        end

        local rec = ensure_wrapper(frag)
        local result_name = call_site_result_name(stmt)
        local result_ty = result_named_type(rec.names.result)
        local binding = B.Binding(C.Id("local:" .. result_name), result_name, result_ty, B.BindingClassLocalValue)
        local args = {}
        local param_tys = {}
        for i = 1, #(stmt.args or {}) do args[#args + 1] = expanded_expr(stmt.args[i], env) end
        for i = 1, #(frag.params or {}) do param_tys[#param_tys + 1] = frag.params[i].ty end
        local fn_binding = B.Binding(
            C.Id("func::" .. rec.names.fn),
            rec.names.fn,
            Ty.TFunc(param_tys, result_ty),
            B.BindingClassGlobalFunc("", rec.names.fn)
        )

        local let_stmt = Tr.StmtLet(
            expanded_stmt_header(stmt.h, env),
            binding,
            Tr.ExprCall(Tr.ExprSurface, Tr.ExprRef(Tr.ExprSurface, B.ValueRefBinding(fn_binding)), args)
        )

        local variant_arms = {}
        for i = 1, #(frag.conts or {}) do
            local cont = frag.conts[i]
            local binds = {}
            local jump_args = {}
            for j = 1, #(cont.params or {}) do
                local p = cont.params[j]
                binds[#binds + 1] = Tr.VariantBind(p.name, p.ty)
                jump_args[#jump_args + 1] = Tr.JumpArg(p.name, Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(p.name)))
            end
            local target = cont_target_for_name(stmt, cont.pretty_name)
            local body = { target and jump_to_target(target, jump_args, label_map) or Tr.StmtTrap(Tr.StmtSurface) }
            variant_arms[#variant_arms + 1] = Tr.SwitchVariantStmtArm(cont.pretty_name, binds, body)
        end

        local switch_stmt = Tr.StmtSwitch(
            Tr.StmtSurface,
            Tr.ExprRef(Tr.ExprSurface, B.ValueRefBinding(binding)),
            {},
            variant_arms,
            { Tr.StmtTrap(Tr.StmtSurface) }
        )
        return { let_stmt, switch_stmt }
    end

    return {
        safe_name = safe_name,
        names_for_frag = names_for_frag,
        result_type_for_frag = result_type_for_frag,
        wrapper_func_for_frag = wrapper_func_for_frag,
        ensure_wrapper = ensure_wrapper,
        pending_wrappers = pending_wrappers,
        mark_emitted = mark_emitted,
        lower_call_use = lower_call_use,
        lower_region_call_use = lower_call_use,
        type_contains_lease = type_contains_lease,
    }
end

return M
