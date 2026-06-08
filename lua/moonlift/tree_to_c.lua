local pvm = require("moonlift.pvm")

local M = {}

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s:match("^%d") then s = "_" .. s end
    if s == "" then s = "x" end
    return s
end

function M.Define(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.tree_to_c ~= nil then return T._moonlift_api_cache.tree_to_c end

    local Core = T.MoonCore
    local Ty = T.MoonType
    local Bn = T.MoonBind
    local Sem = T.MoonSem
    local Tr = T.MoonTree
    local C = T.MoonC

    local TypeToC = require("moonlift.type_to_c").Define(T)
    local Helpers = require("moonlift.c_helpers").Define(T)
    local Coverage = require("moonlift.c_coverage")
    local CAbi = require("moonlift.c_abi").Define(T)
    local CLayout = require("moonlift.c_layout").Define(T)
    local CPlaces = require("moonlift.c_places").Define(T)
    local CResidence = require("moonlift.c_residence").Define(T)
    local CData = require("moonlift.c_data").Define(T)
    local CCfg = require("moonlift.c_cfg").Define(T)
    local SizeAlign = require("moonlift.type_size_align").Define(T)

    local api = {}

    local function append_all(out, xs) for i = 1, #(xs or {}) do out[#out + 1] = xs[i] end end

    local function module_name_of(module)
        local hcls = pvm.classof(module.h)
        if hcls == Tr.ModuleSem or hcls == Tr.ModuleCode or hcls == Tr.ModuleTyped then return module.h.module_name end
        return "moonlift_module"
    end

    local function expr_ty(expr)
        local hcls = pvm.classof(expr.h)
        if hcls == Tr.ExprTyped or hcls == Tr.ExprOpen then return expr.h.ty end
        error("tree_to_c: expression is not typed: " .. tostring(expr.kind), 3)
    end

    local function binding_key(binding)
        return binding.id and binding.id.text or binding.name
    end

    local function local_id_for(ctx, name)
        ctx.next_local = (ctx.next_local or 0) + 1
        return C.CBackendLocalId("ml_" .. sanitize(name) .. "_" .. tostring(ctx.next_local))
    end

    local function local_name(name)
        return C.CBackendName(sanitize(name))
    end

    local function c_func_name(name)
        return C.CBackendName(sanitize(name))
    end

    local function is_void(ty)
        return ty == C.CBackendVoid or pvm.classof(ty) == C.CBackendVoid
    end

    local function add_local(ctx, id, name, ty, opts)
        opts = opts or {}
        local loc = C.CBackendLocal(id, local_name(name), ty)
        ctx.locals[#ctx.locals + 1] = loc
        ctx.local_types = ctx.local_types or {}
        ctx.local_types[id.text] = ty
        if ctx.local_storage ~= nil then
            local residence = opts.residence or C.CBackendResidenceValue
            local init_state = opts.init_state or C.CBackendLocalUninitialized
            ctx.local_storage[#ctx.local_storage + 1] = C.CBackendLocalStorage(id, local_name(name), ty, residence, init_state, opts.address_taken == true)
        end
        return loc
    end

    local function bind_local(ctx, binding, id, ty)
        local entry = { id = id, ty = ty, binding = binding }
        ctx.env[binding_key(binding)] = entry
        ctx.env[binding.name] = entry
        local bcls = pvm.classof(binding.class)
        if bcls == Bn.BindingClassArg then ctx.env["arg#" .. tostring(binding.class.index)] = entry end
    end

    local expr_to_c
    local stmt_to_c
    local lower_body
    local emit_nonterminal_body

    local function atom_type(atom, ctx)
        local cls = pvm.classof(atom)
        if cls == C.CBackendAtomLiteral or cls == C.CBackendAtomNull then return atom.ty end
        if cls == C.CBackendAtomLocal then return ctx.local_types[atom["local"].text] end
        if cls == C.CBackendAtomGlobal then return ctx.global_types[atom.global.text] end
        return nil
    end

    local function temp_for(ctx, prefix, ty)
        local id = local_id_for(ctx, prefix)
        add_local(ctx, id, prefix, ty, { init_state = C.CBackendLocalInitialized })
        return id
    end

    local function direct_call_target(expr, ctx)
        if pvm.classof(expr) == Tr.ExprRef and pvm.classof(expr.ref) == Bn.ValueRefBinding then
            local b = expr.ref.binding
            local bcls = pvm.classof(b.class)
            if bcls == Bn.BindingClassGlobalFunc then return C.CBackendCallDirect(c_func_name(b.class.item_name)) end
            if bcls == Bn.BindingClassExtern then return C.CBackendCallExtern(c_func_name(b.name)) end
        end
        return nil
    end

    local function binary_helper_kind(op, ty)
        if op == Core.BinDiv or op == Core.BinRem then return C.CBackendHelperDivRem(op, ty, C.CBackendDivTrapOnZeroOrOverflow) end
        if op == Core.BinShl or op == Core.BinLShr or op == Core.BinAShr then return C.CBackendHelperShift(op, ty, C.CBackendShiftMaskCount) end
        return C.CBackendHelperIntBinary(op, ty, C.CBackendIntWrap)
    end

    local function expr_kind(expr)
        local cls = pvm.classof(expr)
        return (cls and cls.kind) or tostring(expr and expr.kind)
    end

    local function hard_expr_error(expr, fallback)
        local kind = expr_kind(expr)
        local c = Coverage.classification("MoonTree.Expr", kind)
        local reason = (c and c.reason) or fallback or "unsupported C backend expression"
        error("tree_to_c: " .. kind .. " is " .. ((c and c.status) or "unsupported") .. " for C backend: " .. reason, 3)
    end

    local function literal_index(value)
        return C.CBackendAtomLiteral(C.CBackendIndex, Core.LitInt(tostring(value)))
    end

    local function in_cfg(ctx)
        return ctx ~= nil and ctx.cfg ~= nil and ctx.cfg.current ~= nil
    end

    local function emit_stmts(ctx, out, xs)
        if in_cfg(ctx) then
            for i = 1, #(xs or {}) do ctx.cfg:emit(xs[i]) end
        else
            append_all(out, xs)
        end
    end

    local function normalize_bool(atom, atom_ty, ctx, out)
        if atom_ty == nil then return atom end
        if atom_ty == C.CBackendBool8 or pvm.classof(atom_ty) == C.CBackendBool8 then return atom end
        local tmp = temp_for(ctx, "bool_norm", C.CBackendBool8)
        local hid = Helpers.register(ctx, C.CBackendHelperBoolNormalize(atom_ty))
        emit_stmts(ctx, out, { C.CBackendHelperCall(tmp, hid, { atom }) })
        return C.CBackendAtomLocal(tmp)
    end

    local function emit_expr_result(expr, ctx, out)
        local atom, stmts = expr_to_c(expr, ctx)
        emit_stmts(ctx, out, stmts)
        return atom
    end

    local function expr_atom_for_place(expr, ctx)
        return emit_expr_result(expr, ctx, {})
    end

    local function layout_size_align(ty, ctx)
        local r = SizeAlign.result(ty, ctx.layout_env, ctx.target)
        if pvm.classof(r) == Ty.TypeMemLayoutKnown then return r.layout.size, r.layout.align end
        return 0, 1
    end

    local function field_place(base_place, field, ctx)
        if pvm.classof(field) ~= Sem.FieldByOffset then error("tree_to_c: unresolved field must be resolved before C lowering", 3) end
        local cty = TypeToC.type_to_c(field.ty, ctx)
        local size, align = layout_size_align(field.ty, ctx)
        return C.CBackendPlaceField(base_place, C.CBackendName(sanitize(field.field_name)), cty, field.offset, size, align)
    end

    local function place_from_expr(expr, ctx)
        local cls = pvm.classof(expr)
        if cls == Tr.ExprRef then
            local atom, stmts = expr_to_c(expr, ctx)
            emit_stmts(ctx, {}, stmts)
            local aty = atom_type(atom, ctx) or TypeToC.type_to_c(expr_ty(expr), ctx)
            local acls = pvm.classof(atom)
            if acls == C.CBackendAtomLocal then return C.CBackendPlaceLocal(atom["local"], aty) end
            if acls == C.CBackendAtomGlobal then return C.CBackendPlaceGlobal(atom.global, aty) end
        elseif cls == Tr.ExprDeref then
            local addr = emit_expr_result(expr.value, ctx, {})
            return C.CBackendPlaceDeref(addr, TypeToC.type_to_c(expr_ty(expr), ctx), nil)
        elseif cls == Tr.ExprField then
            return field_place(place_from_expr(expr.base, ctx), expr.field, ctx)
        elseif cls == Tr.ExprIndex then
            local old = ctx.expr_to_atom
            ctx.expr_to_atom = expr_atom_for_place
            local ok, p = pcall(CPlaces.index_base_to_place, expr.base, expr.index, expr_ty(expr), ctx)
            ctx.expr_to_atom = old
            if not ok then error(p, 3) end
            return p
        end
        error("tree_to_c: expression is not addressable as a C place: " .. tostring(expr_kind(expr)), 3)
    end

    local function place_from_tree_place(place, ctx)
        local old = ctx.expr_to_atom
        ctx.expr_to_atom = expr_atom_for_place
        local ok, lowered = pcall(CPlaces.place_to_c, place, ctx)
        ctx.expr_to_atom = old
        if not ok then error(lowered, 3) end
        return lowered.place
    end

    local function assign_addr_of_place(ctx, place, prefix)
        local pty = C.CBackendDataPtr(place.ty)
        local tmp = temp_for(ctx, prefix or "addr", pty)
        return C.CBackendAtomLocal(tmp), { C.CBackendAssign(tmp, C.CBackendRAddrOfPlace(place)) }
    end

    local function switch_arm_literal(raw)
        raw = tostring(raw or "0")
        if raw == "true" then return Core.LitBool(true) end
        if raw == "false" then return Core.LitBool(false) end
        return Core.LitInt(raw)
    end

    local hex = {}
    for i = 0, 255 do hex[i] = string.format("%02x", i) end

    local function string_global(ctx, bytes)
        ctx.globals = ctx.globals or {}
        ctx.global_types = ctx.global_types or {}
        local parts = { "str", tostring(#bytes) }
        for i = 1, #bytes do parts[#parts + 1] = hex[bytes:byte(i)] end
        local id = C.CBackendGlobalId(table.concat(parts, "_"))
        if ctx.global_types[id.text] == nil then
            local ty = C.CBackendArray(C.CBackendScalar(Core.ScalarU8), #bytes + 1)
            local inits = {}
            if #bytes > 0 then inits[#inits + 1] = C.CBackendDataBytes(0, bytes) end
            ctx.globals[#ctx.globals + 1] = C.CBackendGlobal(id, C.CBackendName(id.text), Core.VisibilityLocal, ty, #bytes + 1, 1, inits)
            ctx.global_types[id.text] = ty
        end
        return id
    end

    local function named_type_name(ty)
        if ty ~= nil and pvm.classof(ty) == Ty.TNamed then
            local ref = ty.ref
            local cls = pvm.classof(ref)
            if cls == Ty.TypeRefGlobal then return ref.type_name or ref.name end
            if cls == Ty.TypeRefPath and ref.path and #ref.path.parts > 0 then return ref.path.parts[#ref.path.parts].text or ref.path.parts[#ref.path.parts].name end
        end
        return nil
    end

    local function variant_layout_offsets(fields, ctx)
        local out, offset, max_align = {}, 0, 1
        for i = 1, #fields do
            local sz, al = layout_size_align(fields[i].ty, ctx)
            offset = math.floor((offset + al - 1) / al) * al
            out[fields[i].field_name] = { offset = offset, ty = fields[i].ty, size = sz, align = al }
            offset = offset + sz
            if al > max_align then max_align = al end
        end
        return out
    end

    local function build_variant_defs(module, ctx)
        local defs = {}
        local function add_decl(t)
            local cls = pvm.classof(t)
            if cls == Tr.TypeDeclEnumSugar then
                local variants = {}
                for i = 1, #t.variants do local n = t.variants[i].text or tostring(t.variants[i]); variants[n] = { name = n, tag = i - 1, payload = Ty.TScalar(Core.ScalarVoid), fields = {}, field_offsets = {} } end
                defs[t.name] = { type_name = t.name, variants = variants }
            elseif cls == Tr.TypeDeclTaggedUnionSugar then
                local variants = {}
                for i = 1, #t.variants do
                    local v = t.variants[i]
                    variants[v.name] = { name = v.name, tag = i - 1, payload = v.payload, fields = v.fields or {}, field_offsets = variant_layout_offsets(v.fields or {}, ctx) }
                end
                defs[t.name] = { type_name = t.name, variants = variants }
            end
        end
        for i = 1, #module.items do
            local item = module.items[i]
            local cls = pvm.classof(item)
            if cls == Tr.ItemType then add_decl(item.t)
            elseif cls == Tr.ItemUseModule then
                local nested = build_variant_defs(item.module, ctx)
                for k, v in pairs(nested) do defs[k] = v end
            end
        end
        return defs
    end

    local function layout_field_for_type(ctx, type_name, field_name)
        local env = ctx.layout_env or Sem.LayoutEnv({})
        for i = 1, #env.layouts do
            local layout = env.layouts[i]
            local lcls = pvm.classof(layout)
            if lcls == Sem.LayoutNamed and layout.type_name == type_name then
                for j = 1, #layout.fields do if layout.fields[j].field_name == field_name then return layout.fields[j] end end
            end
        end
        return nil
    end

    local function aggregate_place_for_atom(atom, ty, ctx)
        local cls = pvm.classof(atom)
        if cls == C.CBackendAtomLocal then return C.CBackendPlaceLocal(atom["local"], ty) end
        if cls == C.CBackendAtomGlobal then return C.CBackendPlaceGlobal(atom.global, ty) end
        error("tree_to_c: tagged-union value is not addressable", 3)
    end

    local function addr_of_atom_place(atom, ty, ctx, prefix, out)
        local place = aggregate_place_for_atom(atom, ty, ctx)
        local tmp = temp_for(ctx, prefix or "addr", C.CBackendDataPtr(ty))
        emit_stmts(ctx, out or {}, { C.CBackendAssign(tmp, C.CBackendRAddrOfPlace(place)) })
        return C.CBackendAtomLocal(tmp), place
    end

    local function payload_offset_for_type(ctx, type_name)
        local f = layout_field_for_type(ctx, type_name, "__payload")
        return f and f.offset or nil
    end

    local function tag_place(atom, ty, ctx, type_name)
        local f = layout_field_for_type(ctx, type_name, "__tag")
        local tag_ty = TypeToC.type_to_c(Ty.TScalar(Core.ScalarU32), ctx)
        return C.CBackendPlaceField(aggregate_place_for_atom(atom, ty, ctx), C.CBackendName("__tag"), tag_ty, f and f.offset or 0, 4, 4)
    end

    local function payload_place(addr, offset, ty, ctx)
        local size, align = layout_size_align(ty, ctx)
        return C.CBackendPlaceBytes(addr, offset, TypeToC.type_to_c(ty, ctx), size, align)
    end

    local function view_parts(view, ctx)
        local cls = pvm.classof(view)
        local function one() return C.CBackendAtomLiteral(C.CBackendIndex, Core.LitInt("1")) end
        if cls == Tr.ViewContiguous then
            return { data = emit_expr_result(view.data, ctx, {}), len = emit_expr_result(view.len, ctx, {}), stride = one(), elem = view.elem }
        elseif cls == Tr.ViewStrided then
            return { data = emit_expr_result(view.data, ctx, {}), len = emit_expr_result(view.len, ctx, {}), stride = emit_expr_result(view.stride, ctx, {}), elem = view.elem }
        elseif cls == Tr.ViewFromExpr then
            local bty = expr_ty(view.base)
            if pvm.classof(bty) == Ty.TView then
                local atom = emit_expr_result(view.base, ctx, {})
                local vty = TypeToC.type_to_c(bty, ctx)
                local place = aggregate_place_for_atom(atom, vty, ctx)
                local data_ty = C.CBackendDataPtr(TypeToC.type_to_c(bty.elem, ctx))
                local data_id = temp_for(ctx, "view_data", data_ty)
                local len_id = temp_for(ctx, "view_len", C.CBackendIndex)
                local stride_id = temp_for(ctx, "view_stride", C.CBackendIndex)
                emit_stmts(ctx, {}, {
                    C.CBackendPlaceLoad(data_id, C.CBackendPlaceField(place, C.CBackendName("data"), data_ty, 0, nil, nil)),
                    C.CBackendPlaceLoad(len_id, C.CBackendPlaceField(place, C.CBackendName("len"), C.CBackendIndex, 8, nil, nil)),
                    C.CBackendPlaceLoad(stride_id, C.CBackendPlaceField(place, C.CBackendName("stride"), C.CBackendIndex, 16, nil, nil)),
                })
                return { data = C.CBackendAtomLocal(data_id), len = C.CBackendAtomLocal(len_id), stride = C.CBackendAtomLocal(stride_id), elem = bty.elem }
            end
            if pvm.classof(bty) == Ty.TPtr then
                return { data = emit_expr_result(view.base, ctx, {}), len = C.CBackendAtomLiteral(C.CBackendIndex, Core.LitInt("1")), stride = one(), elem = bty.elem }
            end
            local base = place_from_expr(view.base, ctx)
            local data, stmts = assign_addr_of_place(ctx, base, "view_data")
            emit_stmts(ctx, {}, stmts)
            local len = C.CBackendAtomLiteral(C.CBackendIndex, Core.LitInt("1"))
            return { data = data, len = len, stride = one(), elem = view.elem }
        elseif cls == Tr.ViewRestrided then
            local p = view_parts(view.base, ctx); p.stride = emit_expr_result(view.stride, ctx, {}); p.elem = view.elem; return p
        elseif cls == Tr.ViewWindow then
            local p = view_parts(view.base, ctx)
            local start = emit_expr_result(view.start, ctx, {})
            local elem_cty = TypeToC.type_to_c(p.elem, ctx)
            local tmp = temp_for(ctx, "view_window", C.CBackendDataPtr(elem_cty))
            local size = layout_size_align(p.elem, ctx)
            emit_stmts(ctx, {}, { C.CBackendAssign(tmp, C.CBackendRPtrOffset(p.data, start, size, 0)) })
            p.data = C.CBackendAtomLocal(tmp); p.len = emit_expr_result(view.len, ctx, {}); return p
        elseif cls == Tr.ViewRowBase then
            local p = view_parts(view.base, ctx)
            local off = emit_expr_result(view.row_offset, ctx, {})
            local elem_cty = TypeToC.type_to_c(view.elem, ctx)
            local tmp = temp_for(ctx, "view_row", C.CBackendDataPtr(elem_cty))
            local size = layout_size_align(view.elem, ctx)
            emit_stmts(ctx, {}, { C.CBackendAssign(tmp, C.CBackendRPtrOffset(p.data, off, size, 0)) })
            p.data = C.CBackendAtomLocal(tmp); p.elem = view.elem; return p
        elseif cls == Tr.ViewInterleaved then
            local base = emit_expr_result(view.data, ctx, {})
            local lane = emit_expr_result(view.lane, ctx, {})
            local elem_cty = TypeToC.type_to_c(view.elem, ctx)
            local tmp = temp_for(ctx, "view_lane", C.CBackendDataPtr(elem_cty))
            local size = layout_size_align(view.elem, ctx)
            emit_stmts(ctx, {}, { C.CBackendAssign(tmp, C.CBackendRPtrOffset(base, lane, size, 0)) })
            return { data = C.CBackendAtomLocal(tmp), len = emit_expr_result(view.len, ctx, {}), stride = emit_expr_result(view.stride, ctx, {}), elem = view.elem }
        elseif cls == Tr.ViewInterleavedView then
            local p = view_parts(view.base, ctx)
            local lane = emit_expr_result(view.lane, ctx, {})
            local elem_cty = TypeToC.type_to_c(view.elem, ctx)
            local tmp = temp_for(ctx, "view_lane", C.CBackendDataPtr(elem_cty))
            local size = layout_size_align(view.elem, ctx)
            emit_stmts(ctx, {}, { C.CBackendAssign(tmp, C.CBackendRPtrOffset(p.data, lane, size, 0)) })
            p.data = C.CBackendAtomLocal(tmp); p.stride = emit_expr_result(view.stride, ctx, {}); p.elem = view.elem; return p
        end
        error("tree_to_c: unsupported view form", 3)
    end

    local function view_to_place(view, index_atom, result_ty, ctx)
        local parts = view_parts(view, ctx)
        local elem_cty = TypeToC.type_to_c(result_ty, ctx)
        local size = layout_size_align(result_ty, ctx)
        local scaled = index_atom
        local scls = pvm.classof(parts.stride)
        if not (scls == C.CBackendAtomLiteral and parts.stride.literal.raw == "1") then
            local idx_tmp = temp_for(ctx, "view_index", C.CBackendIndex)
            local hid = Helpers.register(ctx, C.CBackendHelperIntBinary(Core.BinMul, C.CBackendIndex, C.CBackendIntWrap))
            emit_stmts(ctx, {}, { C.CBackendHelperCall(idx_tmp, hid, { index_atom, parts.stride }) })
            scaled = C.CBackendAtomLocal(idx_tmp)
        end
        local ptr_tmp = temp_for(ctx, "view_elem", C.CBackendDataPtr(nil))
        emit_stmts(ctx, {}, { C.CBackendAssign(ptr_tmp, C.CBackendRPtrOffset(parts.data, scaled, size, 0)) })
        return C.CBackendPlaceDeref(C.CBackendAtomLocal(ptr_tmp), elem_cty, nil)
    end

    expr_to_c = function(expr, ctx)
        local cls = pvm.classof(expr)
        if cls == Tr.ExprLit then
            if pvm.classof(expr.value) == Core.LitString then
                return C.CBackendAtomGlobal(string_global(ctx, expr.value.bytes)), {}
            end
            return C.CBackendAtomLiteral(TypeToC.type_to_c(expr_ty(expr), ctx), expr.value), {}
        elseif cls == Tr.ExprNull then
            return C.CBackendAtomNull(TypeToC.type_to_c(expr_ty(expr), ctx)), {}
        elseif cls == Tr.ExprSizeOf or cls == Tr.ExprAlignOf then
            local SizeAlign = require("moonlift.type_size_align").Define(T)
            local r = SizeAlign.result(expr.ty, ctx.layout_env, ctx.target)
            if pvm.classof(r) == Ty.TypeMemLayoutKnown then
                return literal_index((cls == Tr.ExprSizeOf) and r.layout.size or r.layout.align), {}
            end
            return literal_index((cls == Tr.ExprSizeOf) and 0 or 1), {}
        elseif cls == Tr.ExprRef then
            if pvm.classof(expr.ref) == Bn.ValueRefBinding then
                local b = expr.ref.binding
                local bcls = pvm.classof(b.class)
                if bcls == Bn.BindingClassGlobalStatic or bcls == Bn.BindingClassGlobalConst then
                    local id = (ctx.global_ids and (ctx.global_ids[binding_key(b)] or ctx.global_ids[b.name])) or CData.global_id(b.class.module_name, b.class.item_name)
                    return C.CBackendAtomGlobal(id), {}
                elseif bcls == Bn.BindingClassGlobalFunc then
                    local ty = TypeToC.type_to_c(expr_ty(expr), ctx)
                    if pvm.classof(ty) ~= C.CBackendCodePtr then hard_expr_error(expr, "global function ref did not project to an exact C code pointer") end
                    local tmp = temp_for(ctx, "fnaddr_" .. b.class.item_name, ty)
                    return C.CBackendAtomLocal(tmp), { C.CBackendAssign(tmp, C.CBackendRFuncAddr(c_func_name(b.class.item_name), ty.sig)) }
                elseif bcls == Bn.BindingClassExtern then
                    local ty = TypeToC.type_to_c(expr_ty(expr), ctx)
                    if pvm.classof(ty) ~= C.CBackendCodePtr then hard_expr_error(expr, "extern ref did not project to an exact C code pointer") end
                    local tmp = temp_for(ctx, "externaddr_" .. b.name, ty)
                    return C.CBackendAtomLocal(tmp), { C.CBackendAssign(tmp, C.CBackendRExternAddr(c_func_name(b.name), ty.sig)) }
                end
                local found = ctx.env[binding_key(b)] or ctx.env[b.name]
                if not found and pvm.classof(b.class) == Bn.BindingClassArg then found = ctx.env["arg#" .. tostring(b.class.index)] end
                if not found then error("tree_to_c: unbound value " .. b.name, 3) end
                return C.CBackendAtomLocal(found.id), {}
            elseif pvm.classof(expr.ref) == Bn.ValueRefName then
                local found = ctx.env[expr.ref.name]
                if not found then error("tree_to_c: unbound name " .. expr.ref.name, 3) end
                return C.CBackendAtomLocal(found.id), {}
            end
            error("tree_to_c: unsupported value ref", 3)
        elseif cls == Tr.ExprIsNull then
            local value, stmts = expr_to_c(expr.value, ctx)
            local vty = atom_type(value, ctx) or TypeToC.type_to_c(expr_ty(expr.value), ctx)
            local tmp = temp_for(ctx, "isnull", C.CBackendBool8)
            stmts[#stmts + 1] = C.CBackendAssign(tmp, C.CBackendRCompare(Core.CmpEq, vty, value, C.CBackendAtomNull(vty)))
            return C.CBackendAtomLocal(tmp), stmts
        elseif cls == Tr.ExprDot or cls == Tr.ExprCast or cls == Tr.ExprClosure or cls == Tr.ExprSlotValue or cls == Tr.ExprUseExprFrag then
            hard_expr_error(expr)
        elseif cls == Tr.ExprCtor then
            local ty = TypeToC.type_to_c(expr_ty(expr), ctx)
            local def = ctx.variant_defs and ctx.variant_defs[expr.type_name]
            local variant = def and def.variants[expr.variant_name]
            if variant == nil then error("tree_to_c: unknown variant constructor " .. tostring(expr.type_name) .. "." .. tostring(expr.variant_name), 3) end
            local tmp = temp_for(ctx, "ctor_" .. expr.variant_name, ty)
            local atom = C.CBackendAtomLocal(tmp)
            local place = C.CBackendPlaceLocal(tmp, ty)
            local stmts = {}
            local size = layout_size_align(expr_ty(expr), ctx)
            stmts[#stmts + 1] = C.CBackendZeroInit(place, ty, size)
            stmts[#stmts + 1] = C.CBackendPlaceStore(tag_place(atom, ty, ctx, expr.type_name), C.CBackendAtomLiteral(TypeToC.type_to_c(Ty.TScalar(Core.ScalarU32), ctx), Core.LitInt(tostring(variant.tag))))
            local payload_offset = payload_offset_for_type(ctx, expr.type_name)
            if payload_offset ~= nil then
                local addr = addr_of_atom_place(atom, ty, ctx, "ctor_addr", stmts)
                for i = 1, #expr.args do
                    local arg, arg_stmts = expr_to_c(expr.args[i], ctx); append_all(stmts, arg_stmts)
                    local pty = (variant.fields and variant.fields[i] and variant.fields[i].ty) or variant.payload
                    local off = payload_offset
                    if variant.fields and variant.fields[i] then
                        local rec = variant.field_offsets[variant.fields[i].field_name]
                        if rec then off = off + rec.offset end
                    end
                    stmts[#stmts + 1] = C.CBackendPlaceStore(payload_place(addr, off, pty, ctx), arg)
                end
            end
            return atom, stmts
        elseif cls == Tr.ExprUnary then
            local value, value_stmts = expr_to_c(expr.value, ctx)
            local ty = TypeToC.type_to_c(expr_ty(expr), ctx)
            local tmp = temp_for(ctx, "unary", ty)
            local hid = Helpers.register(ctx, C.CBackendHelperUnary(expr.op, ty))
            local stmts = {}; append_all(stmts, value_stmts)
            stmts[#stmts + 1] = C.CBackendHelperCall(tmp, hid, { value })
            return C.CBackendAtomLocal(tmp), stmts
        elseif cls == Tr.ExprBinary then
            local lhs, lhs_stmts = expr_to_c(expr.lhs, ctx)
            local rhs, rhs_stmts = expr_to_c(expr.rhs, ctx)
            local ty = TypeToC.type_to_c(expr_ty(expr), ctx)
            local tmp = temp_for(ctx, "bin", ty)
            local stmts = {}; append_all(stmts, lhs_stmts); append_all(stmts, rhs_stmts)
            local hid = Helpers.register(ctx, binary_helper_kind(expr.op, ty))
            stmts[#stmts + 1] = C.CBackendHelperCall(tmp, hid, { lhs, rhs })
            return C.CBackendAtomLocal(tmp), stmts
        elseif cls == Tr.ExprCompare then
            local lhs, lhs_stmts = expr_to_c(expr.lhs, ctx)
            local rhs, rhs_stmts = expr_to_c(expr.rhs, ctx)
            local ty = TypeToC.type_to_c(expr_ty(expr.lhs), ctx)
            local rty = TypeToC.type_to_c(expr_ty(expr), ctx)
            local tmp = temp_for(ctx, "cmp", rty)
            local stmts = {}; append_all(stmts, lhs_stmts); append_all(stmts, rhs_stmts)
            stmts[#stmts + 1] = C.CBackendAssign(tmp, C.CBackendRCompare(expr.op, ty, lhs, rhs))
            return C.CBackendAtomLocal(tmp), stmts
        elseif cls == Tr.ExprLogic then
            local cfg = ctx.cfg
            local lhs_ty = TypeToC.type_to_c(expr_ty(expr.lhs), ctx)
            local lhs, lhs_stmts = expr_to_c(expr.lhs, ctx)
            local lhs_atom = lhs
            local out = {}
            emit_stmts(ctx, out, lhs_stmts)
            if in_cfg(ctx) then
                lhs_atom = normalize_bool(lhs_atom, lhs_ty, ctx, out)
                local tmp = temp_for(ctx, "logic", C.CBackendBool8)
                local false_atom = C.CBackendAtomLiteral(C.CBackendBool8, Core.LitBool(false))
                local true_atom = C.CBackendAtomLiteral(C.CBackendBool8, Core.LitBool(true))
                local true_label = cfg:label("logic_true")
                local false_label = cfg:label("logic_false")
                local join_label = cfg:join_label("logic_join")
                cfg:if_goto(lhs_atom, true_label, false_label, {}, {})
                cfg:start_block(true_label, {})
                if expr.op == Core.LogicAnd then
                    local rhs, rhs_stmts = expr_to_c(expr.rhs, ctx)
                    emit_stmts(ctx, out, rhs_stmts)
                    rhs = normalize_bool(rhs, TypeToC.type_to_c(expr_ty(expr.rhs), ctx), ctx, out)
                    cfg:emit(C.CBackendAssign(tmp, C.CBackendRAtom(rhs)))
                else
                    cfg:emit(C.CBackendAssign(tmp, C.CBackendRAtom(true_atom)))
                end
                cfg:goto_block(join_label, {})
                cfg:start_block(false_label, {})
                if expr.op == Core.LogicAnd then
                    cfg:emit(C.CBackendAssign(tmp, C.CBackendRAtom(false_atom)))
                else
                    local rhs, rhs_stmts = expr_to_c(expr.rhs, ctx)
                    emit_stmts(ctx, out, rhs_stmts)
                    rhs = normalize_bool(rhs, TypeToC.type_to_c(expr_ty(expr.rhs), ctx), ctx, out)
                    cfg:emit(C.CBackendAssign(tmp, C.CBackendRAtom(rhs)))
                end
                cfg:goto_block(join_label, {})
                cfg:start_block(join_label, {})
                return C.CBackendAtomLocal(tmp), {}
            end

            local rhs, rhs_stmts = expr_to_c(expr.rhs, ctx)
            local tmp = temp_for(ctx, "logic", C.CBackendBool8)
            local stmts = {}; append_all(stmts, lhs_stmts); append_all(stmts, rhs_stmts)
            local false_atom = C.CBackendAtomLiteral(C.CBackendBool8, Core.LitBool(false))
            local true_atom = C.CBackendAtomLiteral(C.CBackendBool8, Core.LitBool(true))
            if expr.op == Core.LogicAnd then
                stmts[#stmts + 1] = C.CBackendAssign(tmp, C.CBackendRSelect(C.CBackendBool8, lhs, rhs, false_atom))
            else
                stmts[#stmts + 1] = C.CBackendAssign(tmp, C.CBackendRSelect(C.CBackendBool8, lhs, true_atom, rhs))
            end
            return C.CBackendAtomLocal(tmp), stmts
        elseif cls == Tr.ExprMachineCast then
            local value, value_stmts = expr_to_c(expr.value, ctx)
            local from_ty = atom_type(value, ctx) or TypeToC.type_to_c(expr_ty(expr.value), ctx)
            local ty = TypeToC.type_to_c(expr.ty, ctx)
            local tmp = temp_for(ctx, "cast", ty)
            local stmts = {}; append_all(stmts, value_stmts)
            local hid = Helpers.register(ctx, C.CBackendHelperCast(expr.op, from_ty, ty))
            stmts[#stmts + 1] = C.CBackendHelperCall(tmp, hid, { value })
            return C.CBackendAtomLocal(tmp), stmts
        elseif cls == Tr.ExprIntrinsic then
            local args = {}; local stmts = {}
            for i = 1, #expr.args do local a, s = expr_to_c(expr.args[i], ctx); append_all(stmts, s); args[i] = a end
            local ty = TypeToC.type_to_c(expr_ty(expr), ctx)
            local tmp = is_void(ty) and nil or temp_for(ctx, "intrin", ty)
            local hid = Helpers.register(ctx, C.CBackendHelperIntrinsic(expr.op, ty))
            stmts[#stmts + 1] = C.CBackendHelperCall(tmp, hid, args)
            return tmp and C.CBackendAtomLocal(tmp) or C.CBackendAtomNull(C.CBackendVoid), stmts
        elseif cls == Tr.ExprSelect then
            local cond, cond_stmts = expr_to_c(expr.cond, ctx)
            local ty = TypeToC.type_to_c(expr_ty(expr), ctx)
            local tmp = temp_for(ctx, "select", ty)
            local out = {}
            emit_stmts(ctx, out, cond_stmts)
            if in_cfg(ctx) then
                local cfg = ctx.cfg
                local cond_ty = TypeToC.type_to_c(expr_ty(expr.cond), ctx)
                local cond_atom = normalize_bool(cond, cond_ty, ctx, out)
                local then_label = cfg:label("select_true")
                local else_label = cfg:label("select_false")
                local join_label = cfg:join_label("select_join")
                cfg:if_goto(cond_atom, then_label, else_label, {}, {})
                cfg:start_block(then_label, {})
                local tv = emit_expr_result(expr.then_expr, ctx, out)
                cfg:emit(C.CBackendAssign(tmp, C.CBackendRAtom(tv)))
                cfg:goto_block(join_label, {})
                cfg:start_block(else_label, {})
                local ev = emit_expr_result(expr.else_expr, ctx, out)
                cfg:emit(C.CBackendAssign(tmp, C.CBackendRAtom(ev)))
                cfg:goto_block(join_label, {})
                cfg:start_block(join_label, {})
                return C.CBackendAtomLocal(tmp), {}
            else
                local tv, ts = expr_to_c(expr.then_expr, ctx)
                local ev, es = expr_to_c(expr.else_expr, ctx)
                if #ts > 0 or #es > 0 then
                    error("tree_to_c: ExprSelect with side-effecting arms requires CFG expression lowering", 3)
                end
                local stmts = {}; append_all(stmts, out); append_all(stmts, { C.CBackendAssign(tmp, C.CBackendRSelect(ty, cond, tv, ev)) })
                return C.CBackendAtomLocal(tmp), stmts
            end
        elseif cls == Tr.ExprAddrOf then
            local place = place_from_tree_place(expr.place, ctx)
            return assign_addr_of_place(ctx, place, "addr")
        elseif cls == Tr.ExprDeref then
            local place = place_from_expr(expr, ctx)
            local ty = TypeToC.type_to_c(expr_ty(expr), ctx)
            local tmp = temp_for(ctx, "deref", ty)
            return C.CBackendAtomLocal(tmp), { C.CBackendPlaceLoad(tmp, place) }
        elseif cls == Tr.ExprField then
            local place = place_from_expr(expr, ctx)
            local ty = TypeToC.type_to_c(expr_ty(expr), ctx)
            local tmp = temp_for(ctx, "field", ty)
            return C.CBackendAtomLocal(tmp), { C.CBackendPlaceLoad(tmp, place) }
        elseif cls == Tr.ExprIndex then
            local place = place_from_expr(expr, ctx)
            local ty = TypeToC.type_to_c(expr_ty(expr), ctx)
            local tmp = temp_for(ctx, "index", ty)
            return C.CBackendAtomLocal(tmp), { C.CBackendPlaceLoad(tmp, place) }
        elseif cls == Tr.ExprLen then
            local vty = expr_ty(expr.value)
            local vcls = pvm.classof(vty)
            if vcls == Ty.TArray and pvm.classof(vty.count) == Ty.ArrayLenConst then return literal_index(vty.count.count), {} end
            local base_place = place_from_expr(expr.value, ctx)
            local len_place = C.CBackendPlaceField(base_place, C.CBackendName("len"), C.CBackendIndex, 0, nil, nil)
            local tmp = temp_for(ctx, "len", C.CBackendIndex)
            return C.CBackendAtomLocal(tmp), { C.CBackendPlaceLoad(tmp, len_place) }
        elseif cls == Tr.ExprAgg then
            local ty = TypeToC.type_to_c(expr.ty, ctx)
            local tmp = temp_for(ctx, "agg", ty)
            local ty_cls = pvm.classof(ty)
            if ty_cls == C.CBackendClosureDescriptor then
                local stmts = {}
                local fn_atom, ctx_size = nil, 0
                local cap_fields = {}
                for i = 1, #expr.fields do
                    local fi = expr.fields[i]
                    if fi.name == "__moon_fn" then
                        local a, s = expr_to_c(fi.value, ctx); append_all(stmts, s); fn_atom = a
                    else
                        local vty = expr_ty(fi.value)
                        local sz = layout_size_align(vty, ctx)
                        ctx_size = math.max(ctx_size, (fi.offset or 0) + sz)
                        cap_fields[#cap_fields + 1] = fi
                    end
                end
                if fn_atom == nil then error("tree_to_c: closure descriptor missing __moon_fn", 3) end
                local desc = C.CBackendPlaceLocal(tmp, ty)
                stmts[#stmts + 1] = C.CBackendPlaceStore(C.CBackendPlaceField(desc, C.CBackendName("fn"), C.CBackendCodePtr(ty.sig), 0, nil, nil), fn_atom)
                if ctx_size > 0 then
                    local ctx_ty = C.CBackendArray(C.CBackendScalar(Core.ScalarU8), ctx_size)
                    local ctx_id = local_id_for(ctx, "closure_ctx")
                    add_local(ctx, ctx_id, "closure_ctx", ctx_ty, { init_state = C.CBackendLocalInitialized })
                    stmts[#stmts + 1] = C.CBackendZeroInit(C.CBackendPlaceLocal(ctx_id, ctx_ty), ctx_ty, ctx_size)
                    for i = 1, #cap_fields do
                        local a, s = expr_to_c(cap_fields[i].value, ctx); append_all(stmts, s)
                        local vty = expr_ty(cap_fields[i].value)
                        local cty = TypeToC.type_to_c(vty, ctx)
                        local sz, al = layout_size_align(vty, ctx)
                        stmts[#stmts + 1] = C.CBackendPlaceStore(C.CBackendPlaceBytes(C.CBackendAtomLocal(ctx_id), cap_fields[i].offset or 0, cty, sz, al), a)
                    end
                    stmts[#stmts + 1] = C.CBackendPlaceStore(C.CBackendPlaceField(desc, C.CBackendName("ctx"), C.CBackendDataPtr(nil), 8, nil, nil), C.CBackendAtomLocal(ctx_id))
                else
                    stmts[#stmts + 1] = C.CBackendPlaceStore(C.CBackendPlaceField(desc, C.CBackendName("ctx"), C.CBackendDataPtr(nil), 8, nil, nil), C.CBackendAtomNull(C.CBackendDataPtr(nil)))
                end
                return C.CBackendAtomLocal(tmp), stmts
            end
            local fields = {}; local stmts = {}
            for i = 1, #expr.fields do
                local a, s = expr_to_c(expr.fields[i].value, ctx); append_all(stmts, s)
                fields[i] = C.CBackendAggregateFieldInit(C.CBackendName(sanitize(expr.fields[i].name)), a, expr.fields[i].offset)
            end
            stmts[#stmts + 1] = C.CBackendAggregateInit(C.CBackendPlaceLocal(tmp, ty), ty, fields)
            return C.CBackendAtomLocal(tmp), stmts
        elseif cls == Tr.ExprArray then
            local ty = TypeToC.type_to_c(expr_ty(expr), ctx)
            local tmp = temp_for(ctx, "array", ty)
            local elems = {}; local stmts = {}
            for i = 1, #expr.elems do
                local a, s = expr_to_c(expr.elems[i], ctx); append_all(stmts, s)
                elems[i] = C.CBackendArrayElemInit(i - 1, a)
            end
            stmts[#stmts + 1] = C.CBackendArrayInit(C.CBackendPlaceLocal(tmp, ty), ty, elems)
            return C.CBackendAtomLocal(tmp), stmts
        elseif cls == Tr.ExprView then
            local ty = TypeToC.type_to_c(expr_ty(expr), ctx)
            local tmp = temp_for(ctx, "view", ty)
            local stmts = {}
            local p = view_parts(expr.view, ctx)
            local fields = {
                C.CBackendAggregateFieldInit(C.CBackendName("data"), p.data, nil),
                C.CBackendAggregateFieldInit(C.CBackendName("len"), p.len, nil),
                C.CBackendAggregateFieldInit(C.CBackendName("stride"), p.stride, nil),
            }
            stmts[#stmts + 1] = C.CBackendAggregateInit(C.CBackendPlaceLocal(tmp, ty), ty, fields)
            return C.CBackendAtomLocal(tmp), stmts
        elseif cls == Tr.ExprBlock then
            local stmts = {}
            for i = 1, #expr.stmts do local s, t = stmt_to_c(expr.stmts[i], ctx); append_all(stmts, s); if t then error("tree_to_c: terminal statement inside ExprBlock is not supported before result", 3) end end
            local a, s = expr_to_c(expr.result, ctx); append_all(stmts, s); return a, stmts
        elseif cls == Tr.ExprIf then
            local cond, cond_stmts = expr_to_c(expr.cond, ctx)
            local ty = TypeToC.type_to_c(expr_ty(expr), ctx)
            local tmp = temp_for(ctx, "ifexpr", ty)
            local out = {}; emit_stmts(ctx, out, cond_stmts)
            if not in_cfg(ctx) then error("tree_to_c: ExprIf requires CFG expression lowering", 3) end
            local cfg = ctx.cfg
            local cond_atom = normalize_bool(cond, TypeToC.type_to_c(expr_ty(expr.cond), ctx), ctx, out)
            local then_label, else_label, join_label = cfg:label("if_true"), cfg:label("if_false"), cfg:join_label("if_join")
            cfg:if_goto(cond_atom, then_label, else_label, {}, {})
            cfg:start_block(then_label, {})
            cfg:emit(C.CBackendAssign(tmp, C.CBackendRAtom(emit_expr_result(expr.then_expr, ctx, out))))
            cfg:goto_block(join_label, {})
            cfg:start_block(else_label, {})
            cfg:emit(C.CBackendAssign(tmp, C.CBackendRAtom(emit_expr_result(expr.else_expr, ctx, out))))
            cfg:goto_block(join_label, {})
            cfg:start_block(join_label, {})
            return C.CBackendAtomLocal(tmp), {}
        elseif cls == Tr.ExprSwitch then
            if #(expr.variant_arms or {}) > 0 then
                if #expr.arms > 0 then error("tree_to_c: mixed scalar and variant switch expression arms are not supported", 3) end
                if not in_cfg(ctx) then error("tree_to_c: ExprSwitch requires CFG expression lowering", 3) end
                local value, value_stmts = expr_to_c(expr.value, ctx)
                emit_stmts(ctx, {}, value_stmts)
                local value_ty = TypeToC.type_to_c(expr_ty(expr.value), ctx)
                local type_name = named_type_name(expr_ty(expr.value))
                local def = type_name and ctx.variant_defs and ctx.variant_defs[type_name] or nil
                if def == nil then error("tree_to_c: variant switch expression requires tagged-union facts", 3) end
                local ty = TypeToC.type_to_c(expr_ty(expr), ctx)
                local tmp = temp_for(ctx, "vswexpr", ty)
                local cfg = ctx.cfg
                local join_label = cfg:join_label("variant_switch_join")
                local tag_tmp = temp_for(ctx, "variant_tag", TypeToC.type_to_c(Ty.TScalar(Core.ScalarU32), ctx))
                cfg:emit(C.CBackendPlaceLoad(tag_tmp, tag_place(value, value_ty, ctx, type_name)))
                local cases = {}
                for i = 1, #expr.variant_arms do
                    local variant = def.variants[expr.variant_arms[i].variant_name]
                    if variant == nil then error("tree_to_c: unknown variant arm " .. tostring(expr.variant_arms[i].variant_name), 3) end
                    cases[i] = C.CBackendSwitchCase(Core.LitInt(tostring(variant.tag)), cfg:label("variant_switch_case"), {})
                end
                local default_label = cfg:label("variant_switch_default")
                cfg:switch_goto(C.CBackendAtomLocal(tag_tmp), cases, default_label, {})
                local payload_offset = payload_offset_for_type(ctx, type_name)
                for i = 1, #expr.variant_arms do
                    cfg:start_block(cases[i].dest, {})
                    local arm = expr.variant_arms[i]
                    local variant = def.variants[arm.variant_name]
                    local bind_stmts = {}
                    if payload_offset ~= nil and #(arm.binds or {}) > 0 then
                        local addr = addr_of_atom_place(value, value_ty, ctx, "variant_addr", bind_stmts)
                        for j = 1, #arm.binds do
                            local bind = arm.binds[j]
                            local bty = TypeToC.type_to_c(bind.ty, ctx)
                            local id = local_id_for(ctx, bind.name)
                            add_local(ctx, id, bind.name, bty, { init_state = C.CBackendLocalInitialized })
                            local off = payload_offset
                            local rec = variant.field_offsets and variant.field_offsets[bind.name]
                            if rec then off = off + rec.offset end
                            bind_stmts[#bind_stmts + 1] = C.CBackendPlaceLoad(id, payload_place(addr, off, bind.ty, ctx))
                            local b = Bn.Binding(Core.Id("variant:expr_switch:" .. variant.name .. ":" .. bind.name), bind.name, bind.ty, Bn.BindingClassLocalValue)
                            bind_local(ctx, b, id, bty)
                        end
                    end
                    emit_stmts(ctx, {}, bind_stmts)
                    if emit_nonterminal_body(arm.body, ctx) then error("tree_to_c: terminal statement before variant ExprSwitch arm result", 3) end
                    cfg:emit(C.CBackendAssign(tmp, C.CBackendRAtom(emit_expr_result(arm.result, ctx, {}))))
                    cfg:goto_block(join_label, {})
                end
                cfg:start_block(default_label, {})
                if emit_nonterminal_body(expr.default_body, ctx) then error("tree_to_c: terminal statement before variant ExprSwitch default result", 3) end
                cfg:emit(C.CBackendAssign(tmp, C.CBackendRAtom(emit_expr_result(expr.default_expr, ctx, {}))))
                cfg:goto_block(join_label, {})
                cfg:start_block(join_label, {})
                return C.CBackendAtomLocal(tmp), {}
            end
            if not in_cfg(ctx) then error("tree_to_c: ExprSwitch requires CFG expression lowering", 3) end
            local value, value_stmts = expr_to_c(expr.value, ctx)
            emit_stmts(ctx, {}, value_stmts)
            local ty = TypeToC.type_to_c(expr_ty(expr), ctx)
            local tmp = temp_for(ctx, "swexpr", ty)
            local cfg = ctx.cfg
            local join_label = cfg:join_label("switch_join")
            local cases = {}
            for i = 1, #expr.arms do cases[i] = C.CBackendSwitchCase(switch_arm_literal(expr.arms[i].raw_key), cfg:label("switch_case"), {}) end
            local default_label = cfg:label("switch_default")
            cfg:switch_goto(value, cases, default_label, {})
            for i = 1, #expr.arms do
                cfg:start_block(cases[i].dest, {})
                if emit_nonterminal_body(expr.arms[i].body, ctx) then error("tree_to_c: terminal statement before ExprSwitch arm result", 3) end
                cfg:emit(C.CBackendAssign(tmp, C.CBackendRAtom(emit_expr_result(expr.arms[i].result, ctx, {}))))
                cfg:goto_block(join_label, {})
            end
            cfg:start_block(default_label, {})
            if emit_nonterminal_body(expr.default_body, ctx) then error("tree_to_c: terminal statement before ExprSwitch default result", 3) end
            cfg:emit(C.CBackendAssign(tmp, C.CBackendRAtom(emit_expr_result(expr.default_expr, ctx, {}))))
            cfg:goto_block(join_label, {})
            cfg:start_block(join_label, {})
            return C.CBackendAtomLocal(tmp), {}
        elseif cls == Tr.ExprCall then
            local args = {}; local stmts = {}
            for i = 1, #expr.args do local a, s = expr_to_c(expr.args[i], ctx); append_all(stmts, s); args[i] = a end
            local result_ty = TypeToC.type_to_c(expr_ty(expr), ctx)
            local dst = is_void(result_ty) and nil or temp_for(ctx, "call", result_ty)
            local target = direct_call_target(expr.callee, ctx)
            if target == nil then
                local callee, cs = expr_to_c(expr.callee, ctx); append_all(stmts, cs)
                local callee_ty = atom_type(callee, ctx)
                local ccls = pvm.classof(callee_ty)
                if ccls == C.CBackendClosureDescriptor then
                    local base = C.CBackendPlaceLocal(callee["local"], callee_ty)
                    local fn_id = temp_for(ctx, "closure_fn", C.CBackendCodePtr(callee_ty.sig))
                    local ctx_id = temp_for(ctx, "closure_ctx", C.CBackendDataPtr(nil))
                    stmts[#stmts + 1] = C.CBackendPlaceLoad(fn_id, C.CBackendPlaceField(base, C.CBackendName("fn"), C.CBackendCodePtr(callee_ty.sig), 0, nil, nil))
                    stmts[#stmts + 1] = C.CBackendPlaceLoad(ctx_id, C.CBackendPlaceField(base, C.CBackendName("ctx"), C.CBackendDataPtr(nil), 8, nil, nil))
                    local closure_args = { C.CBackendAtomLocal(ctx_id) }
                    for i = 1, #args do closure_args[#closure_args + 1] = args[i] end
                    args = closure_args
                    target = C.CBackendCallIndirect(C.CBackendAtomLocal(fn_id), callee_ty.sig)
                else
                    local sig = callee_ty and (callee_ty.sig or callee_ty.imported_sig)
                    if sig == nil then error("tree_to_c: indirect call callee is not a code pointer", 3) end
                    target = C.CBackendCallIndirect(callee, sig)
                end
            end
            stmts[#stmts + 1] = C.CBackendCall(dst, target, args)
            return dst and C.CBackendAtomLocal(dst) or C.CBackendAtomNull(C.CBackendVoid), stmts
        elseif cls == Tr.ExprLoad then
            local addr, as = expr_to_c(expr.addr, ctx)
            local ty = TypeToC.type_to_c(expr.ty, ctx)
            local tmp = temp_for(ctx, "load", ty)
            local stmts = {}; append_all(stmts, as); stmts[#stmts + 1] = C.CBackendPlaceLoad(tmp, C.CBackendPlaceDeref(addr, ty, nil))
            return C.CBackendAtomLocal(tmp), stmts
        elseif cls == Tr.ExprAtomicLoad then
            local addr, as = expr_to_c(expr.addr, ctx)
            local ty = TypeToC.type_to_c(expr.ty, ctx)
            local tmp = temp_for(ctx, "atomic_load", ty)
            local access = C.CBackendMemoryAccess(ty, 1, C.CBackendMayTrap, true, expr.ordering)
            local hid = Helpers.register(ctx, C.CBackendHelperAtomicLoad(access))
            local stmts = {}; append_all(stmts, as); stmts[#stmts + 1] = C.CBackendHelperCall(tmp, hid, { addr })
            return C.CBackendAtomLocal(tmp), stmts
        elseif cls == Tr.ExprAtomicRmw then
            local addr, as = expr_to_c(expr.addr, ctx)
            local val, vs = expr_to_c(expr.value, ctx)
            local ty = TypeToC.type_to_c(expr.ty, ctx)
            local tmp = temp_for(ctx, "atomic_rmw", ty)
            local access = C.CBackendMemoryAccess(ty, 1, C.CBackendMayTrap, true, expr.ordering)
            local hid = Helpers.register(ctx, C.CBackendHelperAtomicRmw(expr.op, access))
            local stmts = {}; append_all(stmts, as); append_all(stmts, vs); stmts[#stmts + 1] = C.CBackendHelperCall(tmp, hid, { addr, val })
            return C.CBackendAtomLocal(tmp), stmts
        elseif cls == Tr.ExprAtomicCas then
            local addr, as = expr_to_c(expr.addr, ctx)
            local expected, es = expr_to_c(expr.expected, ctx)
            local repl, rs = expr_to_c(expr.replacement, ctx)
            local ty = TypeToC.type_to_c(expr.ty, ctx)
            local expected_tmp = temp_for(ctx, "cas_expected", ty)
            local expected_place = C.CBackendPlaceLocal(expected_tmp, ty)
            local expected_addr, addr_stmts = assign_addr_of_place(ctx, expected_place, "cas_expected_addr")
            local access = C.CBackendMemoryAccess(ty, 1, C.CBackendMayTrap, true, expr.ordering)
            local hid = Helpers.register(ctx, C.CBackendHelperAtomicCas(access, expr.ordering, expr.ordering))
            local dst = temp_for(ctx, "atomic_cas", ty)
            local stmts = {}; append_all(stmts, as); append_all(stmts, es); append_all(stmts, rs)
            stmts[#stmts + 1] = C.CBackendAssign(expected_tmp, C.CBackendRAtom(expected))
            append_all(stmts, addr_stmts)
            stmts[#stmts + 1] = C.CBackendHelperCall(dst, hid, { addr, expected_addr, repl })
            return C.CBackendAtomLocal(dst), stmts
        elseif cls == Tr.ExprControl then
            if not in_cfg(ctx) then error("tree_to_c: expression control regions require CFG expression lowering", 3) end
            local Control = require("moonlift.tree_control_to_c").Define(T, { expr_to_c = expr_to_c, stmt_to_c = stmt_to_c, named_type_name = named_type_name, tag_place = tag_place, payload_place = payload_place, addr_of_atom_place = addr_of_atom_place, payload_offset_for_type = payload_offset_for_type, bind_local = bind_local, add_local = add_local, local_id_for = local_id_for })
            local ty = TypeToC.type_to_c(expr_ty(expr), ctx)
            local tmp = temp_for(ctx, "control", ty)
            local join_label = ctx.cfg:join_label("control_join")
            local old_yield_label, old_yield_value = ctx.yield_label, ctx.yield_value_local
            ctx.yield_label, ctx.yield_value_local = join_label, tmp
            local lowered = Control.expr_region_to_c(expr.region, ctx)
            ctx.yield_label, ctx.yield_value_local = old_yield_label, old_yield_value
            emit_stmts(ctx, {}, lowered.init_stmts)
            ctx.cfg:terminate(lowered.entry_term)
            append_all(ctx.extra_blocks, lowered.blocks)
            ctx.cfg:start_block(join_label, {})
            return C.CBackendAtomLocal(tmp), {}
        end
        error("tree_to_c: unsupported expr " .. tostring(expr.kind), 3)
    end

    emit_nonterminal_body = function(body, ctx)
        for i = 1, #body do
            local s, t = stmt_to_c(body[i], ctx)
            if in_cfg(ctx) then for j = 1, #s do ctx.cfg:emit(s[j]) end else emit_stmts(ctx, {}, s) end
            if t ~= nil then
                if in_cfg(ctx) then ctx.cfg:terminate(t) end
                return true
            end
        end
        return false
    end

    stmt_to_c = function(stmt, ctx)
        local cls = pvm.classof(stmt)
        local out = {}
        if cls == Tr.StmtLet or cls == Tr.StmtVar then
            local init_cls = pvm.classof(stmt.init)
            local ty = TypeToC.type_to_c(stmt.binding.ty, ctx)
            local id = local_id_for(ctx, stmt.binding.name)
            add_local(ctx, id, stmt.binding.name, ty, { init_state = C.CBackendLocalInitialized }); ctx.local_types[id.text] = ty; bind_local(ctx, stmt.binding, id, ty)
            if init_cls == Tr.ExprArray then
                local elems = {}
                for i = 1, #stmt.init.elems do local a, s = expr_to_c(stmt.init.elems[i], ctx); append_all(out, s); elems[i] = C.CBackendArrayElemInit(i - 1, a) end
                out[#out + 1] = C.CBackendArrayInit(C.CBackendPlaceLocal(id, ty), ty, elems)
            elseif init_cls == Tr.ExprAgg then
                local fields = {}
                for i = 1, #stmt.init.fields do local a, s = expr_to_c(stmt.init.fields[i].value, ctx); append_all(out, s); fields[i] = C.CBackendAggregateFieldInit(C.CBackendName(sanitize(stmt.init.fields[i].name)), a, stmt.init.fields[i].offset) end
                out[#out + 1] = C.CBackendAggregateInit(C.CBackendPlaceLocal(id, ty), ty, fields)
            else
                local atom, stmts = expr_to_c(stmt.init, ctx); append_all(out, stmts)
                out[#out + 1] = C.CBackendAssign(id, C.CBackendRAtom(atom))
            end
        elseif cls == Tr.StmtSet then
            local atom, stmts = expr_to_c(stmt.value, ctx); append_all(out, stmts)
            out[#out + 1] = C.CBackendPlaceStore(place_from_tree_place(stmt.place, ctx), atom)
        elseif cls == Tr.StmtAtomicStore then
            local addr, as = expr_to_c(stmt.addr, ctx); append_all(out, as)
            local value, vs = expr_to_c(stmt.value, ctx); append_all(out, vs)
            local ty = TypeToC.type_to_c(stmt.ty, ctx)
            local hid = Helpers.register(ctx, C.CBackendHelperAtomicStore(C.CBackendMemoryAccess(ty, 1, C.CBackendMayTrap, true, stmt.ordering)))
            out[#out + 1] = C.CBackendHelperCall(nil, hid, { addr, value })
        elseif cls == Tr.StmtAtomicFence then
            local hid = Helpers.register(ctx, C.CBackendHelperAtomicFence(stmt.ordering))
            out[#out + 1] = C.CBackendHelperCall(nil, hid, {})
        elseif cls == Tr.StmtExpr then
            local _, stmts = expr_to_c(stmt.expr, ctx); append_all(out, stmts)
        elseif cls == Tr.StmtAssert then
            if not in_cfg(ctx) then error("tree_to_c: StmtAssert requires CFG lowering", 3) end
            local cond, stmts = expr_to_c(stmt.cond, ctx); emit_stmts(ctx, out, stmts)
            local ok_label, trap_label = ctx.cfg:label("assert_ok"), ctx.cfg:label("assert_trap")
            ctx.cfg:if_goto(normalize_bool(cond, TypeToC.type_to_c(expr_ty(stmt.cond), ctx), ctx, out), ok_label, trap_label, {}, {})
            ctx.cfg:start_block(trap_label, {}); ctx.cfg:trap(); ctx.cfg:start_block(ok_label, {})
        elseif cls == Tr.StmtIf then
            if not in_cfg(ctx) then error("tree_to_c: StmtIf requires CFG lowering", 3) end
            local cond, stmts = expr_to_c(stmt.cond, ctx); emit_stmts(ctx, out, stmts)
            local then_label, else_label, join_label = ctx.cfg:label("if_then"), ctx.cfg:label("if_else"), ctx.cfg:join_label("if_join")
            ctx.cfg:if_goto(normalize_bool(cond, TypeToC.type_to_c(expr_ty(stmt.cond), ctx), ctx, out), then_label, else_label, {}, {})
            ctx.cfg:start_block(then_label, {}); emit_nonterminal_body(stmt.then_body, ctx); if ctx.cfg.current and ctx.cfg.current.term == nil then ctx.cfg:goto_block(join_label, {}) end
            ctx.cfg:start_block(else_label, {}); emit_nonterminal_body(stmt.else_body, ctx); if ctx.cfg.current and ctx.cfg.current.term == nil then ctx.cfg:goto_block(join_label, {}) end
            ctx.cfg:start_block(join_label, {})
        elseif cls == Tr.StmtSwitch then
            if #(stmt.variant_arms or {}) > 0 then
                if #stmt.arms > 0 then error("tree_to_c: mixed scalar and variant switch statement arms are not supported", 3) end
                if not in_cfg(ctx) then error("tree_to_c: StmtSwitch requires CFG lowering", 3) end
                local value, stmts = expr_to_c(stmt.value, ctx); emit_stmts(ctx, out, stmts)
                local value_ty = TypeToC.type_to_c(expr_ty(stmt.value), ctx)
                local type_name = named_type_name(expr_ty(stmt.value))
                local def = type_name and ctx.variant_defs and ctx.variant_defs[type_name] or nil
                if def == nil then error("tree_to_c: variant switch statement requires tagged-union facts", 3) end
                local tag_tmp = temp_for(ctx, "variant_tag", TypeToC.type_to_c(Ty.TScalar(Core.ScalarU32), ctx))
                ctx.cfg:emit(C.CBackendPlaceLoad(tag_tmp, tag_place(value, value_ty, ctx, type_name)))
                local join_label = ctx.cfg:join_label("variant_switch_join")
                local cases = {}
                for i = 1, #stmt.variant_arms do
                    local variant = def.variants[stmt.variant_arms[i].variant_name]
                    if variant == nil then error("tree_to_c: unknown variant arm " .. tostring(stmt.variant_arms[i].variant_name), 3) end
                    cases[i] = C.CBackendSwitchCase(Core.LitInt(tostring(variant.tag)), ctx.cfg:label("variant_switch_case"), {})
                end
                local default_label = ctx.cfg:label("variant_switch_default")
                ctx.cfg:switch_goto(C.CBackendAtomLocal(tag_tmp), cases, default_label, {})
                local payload_offset = payload_offset_for_type(ctx, type_name)
                for i = 1, #stmt.variant_arms do
                    ctx.cfg:start_block(cases[i].dest, {})
                    local arm = stmt.variant_arms[i]
                    local variant = def.variants[arm.variant_name]
                    local bind_stmts = {}
                    if payload_offset ~= nil and #(arm.binds or {}) > 0 then
                        local addr = addr_of_atom_place(value, value_ty, ctx, "variant_addr", bind_stmts)
                        for j = 1, #arm.binds do
                            local bind = arm.binds[j]
                            local bty = TypeToC.type_to_c(bind.ty, ctx)
                            local id = local_id_for(ctx, bind.name)
                            add_local(ctx, id, bind.name, bty, { init_state = C.CBackendLocalInitialized })
                            local off = payload_offset
                            local rec = variant.field_offsets and variant.field_offsets[bind.name]
                            if rec then off = off + rec.offset end
                            bind_stmts[#bind_stmts + 1] = C.CBackendPlaceLoad(id, payload_place(addr, off, bind.ty, ctx))
                            local b = Bn.Binding(Core.Id("variant:stmt_switch:" .. variant.name .. ":" .. bind.name), bind.name, bind.ty, Bn.BindingClassLocalValue)
                            bind_local(ctx, b, id, bty)
                        end
                    end
                    emit_stmts(ctx, {}, bind_stmts)
                    emit_nonterminal_body(arm.body, ctx)
                    if ctx.cfg.current and ctx.cfg.current.term == nil then ctx.cfg:goto_block(join_label, {}) end
                end
                ctx.cfg:start_block(default_label, {})
                emit_nonterminal_body(stmt.default_body, ctx)
                if ctx.cfg.current and ctx.cfg.current.term == nil then ctx.cfg:goto_block(join_label, {}) end
                ctx.cfg:start_block(join_label, {})
                return out, nil
            end
            if not in_cfg(ctx) then error("tree_to_c: StmtSwitch requires CFG lowering", 3) end
            local value, stmts = expr_to_c(stmt.value, ctx); emit_stmts(ctx, out, stmts)
            local join_label = ctx.cfg:join_label("switch_join")
            local cases = {}
            for i = 1, #stmt.arms do cases[i] = C.CBackendSwitchCase(switch_arm_literal(stmt.arms[i].raw_key), ctx.cfg:label("switch_case"), {}) end
            local default_label = ctx.cfg:label("switch_default")
            ctx.cfg:switch_goto(value, cases, default_label, {})
            for i = 1, #stmt.arms do ctx.cfg:start_block(cases[i].dest, {}); emit_nonterminal_body(stmt.arms[i].body, ctx); if ctx.cfg.current and ctx.cfg.current.term == nil then ctx.cfg:goto_block(join_label, {}) end end
            ctx.cfg:start_block(default_label, {}); emit_nonterminal_body(stmt.default_body, ctx); if ctx.cfg.current and ctx.cfg.current.term == nil then ctx.cfg:goto_block(join_label, {}) end
            ctx.cfg:start_block(join_label, {})
        elseif cls == Tr.StmtReturnVoid then
            return out, C.CBackendReturnVoid
        elseif cls == Tr.StmtReturnValue then
            if pvm.classof(stmt.value) == Tr.ExprControl then
                local Control = require("moonlift.tree_control_to_c").Define(T, { expr_to_c = expr_to_c, stmt_to_c = stmt_to_c, named_type_name = named_type_name, tag_place = tag_place, payload_place = payload_place, addr_of_atom_place = addr_of_atom_place, payload_offset_for_type = payload_offset_for_type, bind_local = bind_local, add_local = add_local, local_id_for = local_id_for })
                local lowered = Control.expr_region_to_c(stmt.value.region, ctx)
                append_all(ctx.extra_blocks, lowered.blocks)
                append_all(out, lowered.init_stmts)
                return out, lowered.entry_term
            end
            local atom, stmts = expr_to_c(stmt.value, ctx); append_all(out, stmts)
            return out, C.CBackendReturn(atom)
        elseif cls == Tr.StmtTrap then
            return out, C.CBackendTrap
        elseif cls == Tr.StmtJumpCont or cls == Tr.StmtUseRegionSlot or cls == Tr.StmtUseRegionFrag then
            error("tree_to_c: open/control-fragment statement cannot reach C lowering: " .. tostring(stmt.kind), 3)
        elseif cls == Tr.StmtControl then
            local Control = require("moonlift.tree_control_to_c").Define(T, { expr_to_c = expr_to_c, stmt_to_c = stmt_to_c, named_type_name = named_type_name, tag_place = tag_place, payload_place = payload_place, addr_of_atom_place = addr_of_atom_place, payload_offset_for_type = payload_offset_for_type, bind_local = bind_local, add_local = add_local, local_id_for = local_id_for })
            local lowered = Control.stmt_region_to_c(stmt.region, ctx)
            append_all(ctx.extra_blocks, lowered.blocks)
            append_all(out, lowered.init_stmts)
            return out, lowered.entry_term
        else
            error("tree_to_c: unsupported stmt " .. tostring(stmt.kind), 3)
        end
        return out, nil
    end

    lower_body = function(body, ctx)
        local stmts = {}
        local term = nil
        for i = 1, #body do
            local s, t = stmt_to_c(body[i], ctx)
            if in_cfg(ctx) then
                for j = 1, #s do ctx.cfg:emit(s[j]) end
            else
                append_all(stmts, s)
            end
            if t ~= nil then
                if in_cfg(ctx) then ctx.cfg:terminate(t)
                else term = t end
                break
            end
        end
        if in_cfg(ctx) then
            if ctx.cfg.current and ctx.cfg.current.term == nil then ctx.cfg:terminate(C.CBackendReturnVoid) end
            return nil, nil
        end
        if term == nil then term = C.CBackendReturnVoid end
        return stmts, term
    end

    local function func_visibility(func)
        local cls = pvm.classof(func)
        if cls == Tr.FuncExport or cls == Tr.FuncExportContract then return Core.VisibilityExport end
        return Core.VisibilityLocal
    end

    local function func_parts(func)
        local cls = pvm.classof(func)
        if cls == Tr.FuncLocal or cls == Tr.FuncExport or cls == Tr.FuncLocalContract or cls == Tr.FuncExportContract then
            return func.name, func.params, func.result, func.body
        elseif cls == Tr.FuncDecl then
            return func.name, func.params, func.result, nil
        elseif cls == Tr.FuncOpen then
            error("tree_to_c: FuncOpen cannot reach C backend lowering", 3)
        end
        error("tree_to_c: unsupported function variant", 3)
    end

    local function func_to_c(func, ctx)
        local name, params, result, body = func_parts(func)
        if body == nil then error("tree_to_c: FuncDecl has no body and must be lowered as a declaration", 3) end
        local fctx = {
            next_local = 0,
            next_label = 0,
            env = {},
            locals = {},
            local_storage = {},
            local_types = {},
            globals = ctx.globals,
            global_types = ctx.global_types,
            global_ids = ctx.global_ids,
            exact_symbols = ctx.exact_symbols,
            layout_env = ctx.layout_env,
            target = ctx.target,
            coverage = ctx.coverage,
            abi = ctx.abi,
            c_layout = ctx.c_layout,
            c_places = ctx.c_places,
            c_residence = ctx.c_residence,
            c_data = ctx.c_data,
            diagnostics = ctx.diagnostics,
            residence = CResidence.analyze_func(func),
            extra_blocks = {},
            helpers_by_id = ctx.helpers_by_id,
            helper_order = ctx.helper_order,
            helpers = ctx.helpers,
            sigs = ctx.sigs,
            sig_order = ctx.sig_order,
            types = ctx.types,
            type_order = ctx.type_order,
            type_decls_by_id = ctx.type_decls_by_id,
            variant_defs = ctx.variant_defs,
        }
        fctx.expr_to_c = expr_to_c
        fctx.expr_to_atom = expr_atom_for_place
        fctx.view_to_parts = view_parts
        fctx.view_to_place = view_to_place
        fctx.cfg = CCfg.new(fctx, { entry = false })
        local param_tys = {}
        local c_params = {}
        for i = 1, #params do
            local ty = TypeToC.type_to_c(params[i].ty, ctx)
            param_tys[i] = ty
            local id = C.CBackendLocalId("arg_" .. sanitize(params[i].name))
            c_params[i] = C.CBackendLocal(id, local_name(params[i].name), ty)
            fctx.local_types[id.text] = ty
            local binding = Bn.Binding(Core.Id("arg:" .. name .. ":" .. params[i].name), params[i].name, params[i].ty, Bn.BindingClassArg(i))
            fctx.local_storage[#fctx.local_storage + 1] = CResidence.storage_for_binding(binding, id, params[i].name, fctx.residence, fctx)
            bind_local(fctx, binding, id, ty)
        end
        local result_ty = TypeToC.type_to_c(result, ctx)
        local sig_id = TypeToC.ensure_sig(ctx, param_tys, result_ty)
        fctx.cfg:start_block(C.CBackendLabel("entry"), {})
        lower_body(body, fctx)
        local blocks = fctx.cfg:sealed_blocks()
        append_all(blocks, fctx.extra_blocks)
        return C.CBackendFunc(c_func_name(name), sanitize(name), func_visibility(func), sig_id, c_params, fctx.locals, blocks)
    end

    local function extern_to_c(func, ctx)
        local cls = pvm.classof(func)
        if cls == Tr.ExternFuncOpen then error("tree_to_c: ExternFuncOpen cannot reach C backend lowering", 3) end
        local params = {}
        for i = 1, #func.params do params[i] = TypeToC.type_to_c(func.params[i].ty, ctx) end
        local result = TypeToC.type_to_c(func.result, ctx)
        local sig = TypeToC.ensure_sig(ctx, params, result)
        return C.CBackendExtern(c_func_name(func.name), func.symbol, sig, nil)
    end

    local function data_to_c(data, ctx)
        local g = CData.data_item(data, ctx)
        ctx.global_types[g.id.text] = g.ty
        return g
    end

    local function declare_func(func, ctx)
        local name, params, result = func_parts(func)
        local cparams = {}; for i = 1, #params do cparams[i] = TypeToC.type_to_c(params[i].ty, ctx) end
        local sig = TypeToC.ensure_sig(ctx, cparams, TypeToC.type_to_c(result, ctx))
        return C.CBackendExtern(c_func_name(name), name, sig, nil)
    end

    local function item_to_c(item, ctx)
        local cls = pvm.classof(item)
        if cls == Tr.ItemFunc then
            if pvm.classof(item.func) == Tr.FuncDecl then ctx.externs[#ctx.externs + 1] = declare_func(item.func, ctx)
            else ctx.funcs[#ctx.funcs + 1] = func_to_c(item.func, ctx) end
        elseif cls == Tr.ItemExtern then ctx.externs[#ctx.externs + 1] = extern_to_c(item.func, ctx)
        elseif cls == Tr.ItemType then CLayout.decl_for_type_decl(item.t, ctx.module_name, ctx.layout_env, ctx, { target = ctx.target })
        elseif cls == Tr.ItemConst then
            if pvm.classof(item.c) ~= Tr.ConstItem then error("tree_to_c: open const item cannot reach C backend lowering", 3) end
            local g, diags = CData.const_item(item.c, ctx.module_name, ctx.layout_env, ctx); ctx.globals[#ctx.globals + 1] = g; ctx.global_types[g.id.text] = g.ty; ctx.global_ids[item.c.name] = g.id
            for i = 1, #(diags or {}) do ctx.diagnostics[#ctx.diagnostics + 1] = diags[i] end
        elseif cls == Tr.ItemStatic then
            if pvm.classof(item.s) ~= Tr.StaticItem then error("tree_to_c: open static item cannot reach C backend lowering", 3) end
            local g, diags = CData.static_item(item.s, ctx.module_name, ctx.layout_env, ctx); ctx.globals[#ctx.globals + 1] = g; ctx.global_types[g.id.text] = g.ty; ctx.global_ids[item.s.name] = g.id
            for i = 1, #(diags or {}) do ctx.diagnostics[#ctx.diagnostics + 1] = diags[i] end
        elseif cls == Tr.ItemData then local g = data_to_c(item.data, ctx); ctx.globals[#ctx.globals + 1] = g; ctx.global_types[g.id.text] = g.ty
        elseif cls == Tr.ItemUseModule then
            for i = 1, #item.module.items do item_to_c(item.module.items[i], ctx) end
        elseif cls == Tr.ItemImport or cls == Tr.ItemUseTypeDeclSlot or cls == Tr.ItemUseItemsSlot or cls == Tr.ItemUseModuleSlot then
            error("tree_to_c: unresolved import/open item cannot reach C backend lowering: " .. tostring(item.kind), 3)
        else
            error("tree_to_c: unsupported item " .. tostring(item.kind), 3)
        end
    end

    local function module_to_c(module, opts)
        opts = opts or {}
        local target = opts.target or TypeToC.default_target(opts.c_target or opts)
        local layout_env = opts.layout_env or (opts.env and opts.env.layouts and Bn.Env and opts.env) or nil
        local ctx = {
            module_name = opts.module_name or module_name_of(module),
            target = target,
            layout_env = layout_env,
            coverage = Coverage,
            abi = CAbi,
            c_layout = CLayout,
            c_places = CPlaces,
            c_residence = CResidence,
            c_data = CData,
            diagnostics = {},
            exact_symbols = {},
            sigs = {}, sig_order = {},
            abis = {}, abi_order = {},
            types = {}, type_order = nil, type_decls_by_id = {},
            globals = {}, global_types = {}, global_ids = {}, externs = {},
            helpers = {}, helpers_by_id = {}, helper_order = {}, funcs = {},
        }
        ctx.type_order = ctx.types
        ctx.variant_defs = build_variant_defs(module, ctx)
        for i = 1, #module.items do item_to_c(module.items[i], ctx) end
        return C.CBackendUnit(ctx.module_name, ctx.target, ctx.sig_order, ctx.types, ctx.globals, ctx.externs, ctx.helper_order, ctx.funcs)
    end

    api.module = module_to_c
    api.item_to_c = item_to_c
    api.func_to_c = func_to_c
    api.extern_to_c = extern_to_c
    api.data_to_c = data_to_c
    api.expr_to_c = expr_to_c
    api.stmt_to_c = stmt_to_c

    T._moonlift_api_cache.tree_to_c = api
    return api
end

return M
