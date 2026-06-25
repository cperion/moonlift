-- ASDL → Lalin type emitter.
--
-- Walks LalinAsdl.Schema and emits Lalin struct/enum/union declarations
-- with flat namespaced names (LalinTree_ExprHeader instead of LalinTree.ExprHeader)
-- so all type references resolve locally without @{...} splices.
--
-- Usage:
--   local Emit = require("lalin.schema_emit_types")
--   local blob = Emit.emit_all(T)   -- string of Lalin declarations
--   -- then in a .mlua island:  @{blob}

local pvm = require("lalin.pvm")

local M = {}

-- ── Flat naming ────────────────────────────────────────────────────────────────

local function flat_name(mod_name, decl_name)
    return mod_name .. "_" .. decl_name
end

-- ── Field type ─────────────────────────────────────────────────────────────────

local function field_type_str(A, ty)
    local cls = pvm.classof(ty)

    if cls == A.TypeBuiltin then
        if ty.name == "string" then return "ptr(u8)" end
        if ty.name == "number" then return "i32" end
        if ty.name == "boolean" then return "i32" end
        return "i32"
    elseif cls == A.TypeName then
        return "ptr(" .. flat_name(ty.module_name, ty.name) .. ")"
    elseif cls == A.TypeRelativeName then
        return "ptr(" .. ty.name .. ")"
    elseif cls == A.TypeList then
        -- Array of ASDL nodes: just use the element pointer type.
        -- Length is tracked separately (not in the type system).
        return field_type_str(A, ty.elem)
    elseif cls == A.TypeOptional then
        return field_type_str(A, ty.elem)
    end
    return "i32"
end

-- ── Variant helpers ────────────────────────────────────────────────────────────

local function variant_has_no_fields(A, variant)
    for _, f in ipairs(variant.fields or {}) do
        if not (pvm.classof(f.ty) == A.TypeBuiltin and f.ty.name == "boolean" and f.name == "__marker") then
            return false
        end
    end
    return true
end

local function variant_single_field_name(A, variant)
    local name = nil
    for _, f in ipairs(variant.fields or {}) do
        if not (pvm.classof(f.ty) == A.TypeBuiltin and f.ty.name == "boolean" and f.name == "__marker") then
            if name then return nil end
            name = f
        end
    end
    return name
end

-- ── Product → struct ───────────────────────────────────────────────────────────

local function emit_product(A, out, decl, mod_name)
    local fname = flat_name(mod_name, decl.name)
    out[#out + 1] = ""
    out[#out + 1] = "type " .. fname .. " = struct"
    for _, f in ipairs(decl.fields or {}) do
        local fty = field_type_str(A, f.ty)
        out[#out + 1] = "    " .. f.name .. ": " .. fty .. ","
    end
    out[#out + 1] = "end"
end

-- ── Sum → enum or tagged union ─────────────────────────────────────────────────

local function emit_sum(A, out, decl, mod_name)
    local fname = flat_name(mod_name, decl.name)
    out[#out + 1] = ""

    local all_no_fields = true
    for _, v in ipairs(decl.variants or {}) do
        if not variant_has_no_fields(A, v) then
            all_no_fields = false
            break
        end
    end

    if all_no_fields then
        out[#out + 1] = "type " .. fname .. " = enum"
        for _, v in ipairs(decl.variants or {}) do
            out[#out + 1] = "    " .. flat_name(mod_name, v.name) .. ","
        end
        out[#out + 1] = "end"
    else
        -- Tagged union via type Name = Variant1 | Variant2 | ... end
        out[#out + 1] = "type " .. fname .. " ="
        for vi, v in ipairs(decl.variants or {}) do
            local prefix = (vi == 1) and "    " or "    | "
            local f = variant_single_field_name(A, v)
            if f then
                local fty = field_type_str(A, f.ty)
                out[#out + 1] = prefix .. flat_name(mod_name, v.name) .. "(" .. fty .. ")"
            else
                out[#out + 1] = prefix .. flat_name(mod_name, v.name)
            end
        end
        out[#out + 1] = "end"
    end
end

-- ── Top-level emitter ──────────────────────────────────────────────────────────

function M.emit_all(T)
    local A = assert(T.LalinAsdl, "emit_all expects LalinAsdl defined in context")
    local schema = require("lalin.schema").schema(T)

    local out = { "-- === ASDL → Lalin type declarations (auto-generated) ===\n" }

    for _, mod in ipairs(schema.modules or {}) do
        out[#out + 1] = "-- " .. mod.name
        for _, decl in ipairs(mod.decls or {}) do
            local cls = pvm.classof(decl)
            if cls == A.ProductDecl then
                emit_product(A, out, decl, mod.name)
            elseif cls == A.SumDecl then
                emit_sum(A, out, decl, mod.name)
            end
        end
    end

    return table.concat(out, "\n")
end

return M
