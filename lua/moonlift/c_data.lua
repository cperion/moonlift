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
    if T._moonlift_api_cache.c_data ~= nil then return T._moonlift_api_cache.c_data end

    local Core = T.MoonCore
    local Ty = T.MoonType
    local Tr = T.MoonTree
    local Bn = T.MoonBind
    local Sem = T.MoonSem
    local C = T.MoonC

    local TypeToC = require("moonlift.type_to_c").Define(T)
    local SizeAlign = require("moonlift.type_size_align").Define(T)

    local api = {}

    local function global_id(module_name, name)
        return C.CBackendGlobalId("g_" .. sanitize((module_name or "") .. "_" .. name))
    end

    local function func_name(name) return C.CBackendName(sanitize(name)) end

    local function layout_of(ty, env, target)
        local r = SizeAlign.result(ty, env, target)
        if pvm.classof(r) == Ty.TypeMemLayoutKnown then return r.layout end
        return nil
    end

    local function find_type_layout(ty, env)
        if pvm.classof(ty) ~= Ty.TNamed then return nil end
        local ref = ty.ref
        local rcls = pvm.classof(ref)
        env = env or Sem.LayoutEnv({})
        for i = 1, #env.layouts do
            local layout = env.layouts[i]
            local lcls = pvm.classof(layout)
            if rcls == Ty.TypeRefGlobal and lcls == Sem.LayoutNamed and layout.module_name == ref.module_name and layout.type_name == ref.type_name then return layout end
            if rcls == Ty.TypeRefLocal and lcls == Sem.LayoutLocal and layout.sym == ref.sym then return layout end
            if rcls == Ty.TypeRefPath and lcls == Sem.LayoutNamed and #ref.path.parts == 1 and layout.type_name == ref.path.parts[1].text then return layout end
        end
        return nil
    end

    local function binding_reloc_target(binding)
        local bcls = pvm.classof(binding.class)
        if bcls == Bn.BindingClassGlobalStatic or bcls == Bn.BindingClassGlobalConst then
            return C.CBackendRelocGlobal(global_id(binding.class.module_name, binding.class.item_name))
        elseif bcls == Bn.BindingClassGlobalFunc then
            return C.CBackendRelocFunc(func_name(binding.class.item_name))
        elseif bcls == Bn.BindingClassExtern then
            return C.CBackendRelocExtern(func_name(binding.name))
        end
        return nil
    end

    local function expr_reloc_target(expr)
        if pvm.classof(expr) ~= Tr.ExprRef then return nil end
        if pvm.classof(expr.ref) ~= Bn.ValueRefBinding then return nil end
        return binding_reloc_target(expr.ref.binding)
    end

    local lower_expr_init

    local function append_zero(out, offset, size)
        if size > 0 then out[#out + 1] = C.CBackendDataZero(offset, size) end
    end

    local function lower_array(expr, ty, offset, env, target, out, diagnostics)
        local elem_ty = expr.elem_ty or ty.elem
        local elem_layout = layout_of(elem_ty, env, target)
        if elem_layout == nil then diagnostics[#diagnostics + 1] = "array element layout unavailable"; return end
        for i = 1, #(expr.elems or {}) do lower_expr_init(expr.elems[i], elem_ty, offset + (i - 1) * elem_layout.size, env, target, out, diagnostics) end
    end

    local function lower_aggregate(expr, ty, offset, env, target, out, diagnostics)
        local layout = find_type_layout(ty or expr.ty, env)
        if layout == nil then diagnostics[#diagnostics + 1] = "aggregate layout unavailable"; return end
        local by_name = {}
        for i = 1, #layout.fields do by_name[layout.fields[i].field_name] = layout.fields[i] end
        for i = 1, #(expr.fields or {}) do
            local init = expr.fields[i]
            local field = by_name[init.name]
            if field == nil then diagnostics[#diagnostics + 1] = "aggregate field layout missing: " .. tostring(init.name)
            else lower_expr_init(init.value, field.ty, offset + field.offset, env, target, out, diagnostics) end
        end
    end

    lower_expr_init = function(expr, ty, offset, env, target, out, diagnostics)
        out = out or {}
        diagnostics = diagnostics or {}
        local cty = TypeToC.type_to_c(ty or (expr and expr.ty), {})
        local cls = pvm.classof(expr)
        if cls == Tr.ExprLit then
            if expr.value == Core.LitNil or pvm.classof(expr.value) == Core.LitNil then
                local layout = layout_of(ty, env, target)
                append_zero(out, offset, layout and layout.size or 0)
            else
                out[#out + 1] = C.CBackendDataScalar(offset, cty, expr.value)
            end
        elseif cls == Tr.ExprNull then
            out[#out + 1] = C.CBackendDataScalar(offset, cty, Core.LitNil)
        elseif cls == Tr.ExprAgg then
            lower_aggregate(expr, ty or expr.ty, offset, env, target, out, diagnostics)
        elseif cls == Tr.ExprArray then
            lower_array(expr, ty, offset, env, target, out, diagnostics)
        else
            local reloc = expr_reloc_target(expr)
            if reloc ~= nil then out[#out + 1] = C.CBackendDataReloc(offset, reloc, 0)
            else
                local layout = layout_of(ty, env, target)
                if layout ~= nil then append_zero(out, offset, layout.size) else diagnostics[#diagnostics + 1] = "unsupported data initializer expression" end
            end
        end
        return out, diagnostics
    end

    local function data_item(data, ctx)
        ctx = ctx or {}
        local id = C.CBackendGlobalId("data_" .. sanitize(data.id.text or data.id))
        local ty = C.CBackendArray(C.CBackendScalar(Core.ScalarU8), data.size)
        local inits = {}
        if data.bytes and #data.bytes > 0 then inits[#inits + 1] = C.CBackendDataBytes(0, data.bytes) end
        return C.CBackendGlobal(id, C.CBackendName(id.text), Core.VisibilityLocal, ty, data.size, data.align, inits)
    end

    local function static_item(item, module_name, env, ctx)
        ctx = ctx or {}
        local id = global_id(module_name, item.name)
        local layout = layout_of(item.ty, env, ctx.target) or Sem.MemLayout(0, 1)
        local inits, diagnostics = lower_expr_init(item.value, item.ty, 0, env, ctx.target, {}, {})
        if #inits == 0 then append_zero(inits, 0, layout.size) end
        local g = C.CBackendGlobal(id, C.CBackendName(sanitize(item.name)), Core.VisibilityLocal, TypeToC.type_to_c(item.ty, ctx), layout.size, layout.align, inits)
        return g, diagnostics
    end

    local function const_item(item, module_name, env, ctx)
        -- Constants with storage needs use the same exact initializer path as statics.
        return static_item(item, module_name, env, ctx)
    end

    local function scalar_bits(scalar, target)
        if scalar == Core.ScalarBool or scalar == Core.ScalarI8 or scalar == Core.ScalarU8 then return 8 end
        if scalar == Core.ScalarI16 or scalar == Core.ScalarU16 then return 16 end
        if scalar == Core.ScalarI32 or scalar == Core.ScalarU32 or scalar == Core.ScalarF32 then return 32 end
        if scalar == Core.ScalarI64 or scalar == Core.ScalarU64 or scalar == Core.ScalarF64 then return 64 end
        if scalar == Core.ScalarRawPtr then return (target and target.pointer_bits) or 64 end
        if scalar == Core.ScalarIndex then return (target and target.index_bits) or (target and target.pointer_bits) or 64 end
        return nil
    end

    local function decimal_to_bytes(raw, nbytes)
        raw = tostring(raw):match("^%s*(.-)%s*$")
        local neg = raw:sub(1, 1) == "-"
        if neg then raw = raw:sub(2) end
        raw = raw:gsub("^0+", "")
        if raw == "" then raw = "0" end
        local bytes = {}
        for i = 1, nbytes do
            local q, rem, seen = {}, 0, false
            for j = 1, #raw do
                local d = raw:byte(j) - 48
                if d < 0 or d > 9 then error("c_data: non-decimal integer literal cannot be byte-encoded exactly: " .. tostring(raw), 3) end
                local v = rem * 10 + d
                local qd = math.floor(v / 256)
                rem = v % 256
                if qd ~= 0 or seen then q[#q + 1] = string.char(48 + qd); seen = true end
            end
            bytes[i] = rem
            raw = (#q == 0) and "0" or table.concat(q)
        end
        if raw ~= "0" then error("c_data: integer literal does not fit fixed scalar width", 3) end
        if neg then
            local carry = 1
            for i = 1, nbytes do
                local v = (255 - bytes[i]) + carry
                if v >= 256 then bytes[i], carry = v - 256, 1 else bytes[i], carry = v, 0 end
            end
        end
        local chars = {}
        for i = 1, nbytes do chars[i] = string.char(bytes[i]) end
        return table.concat(chars)
    end

    local function encode_scalar_literal(literal, scalar, target)
        local bits = scalar_bits(scalar, target)
        if bits == nil then return nil end
        local nbytes = bits / 8
        local lcls = pvm.classof(literal)
        local bytes
        if lcls == Core.LitBool then
            bytes = string.char(literal.value and 1 or 0) .. string.rep("\0", nbytes - 1)
        elseif lcls == Core.LitInt then
            bytes = decimal_to_bytes(literal.raw, nbytes)
        else
            return nil
        end
        local endian = target and target.endian
        if endian == C.CBackendBigEndian or pvm.classof(endian) == C.CBackendBigEndian then
            bytes = bytes:reverse()
        end
        return bytes
    end

    local function scalar_literal_init(offset, ty, literal)
        return C.CBackendDataScalar(offset, TypeToC.type_to_c(ty, {}), literal)
    end

    api.global_id = global_id
    api.data_item = data_item
    api.static_item = static_item
    api.const_item = const_item
    api.lower_expr_init = lower_expr_init
    api.scalar_literal_init = scalar_literal_init
    api.encode_scalar_literal = encode_scalar_literal
    api.binding_reloc_target = binding_reloc_target

    T._moonlift_api_cache.c_data = api
    return api
end

return M
