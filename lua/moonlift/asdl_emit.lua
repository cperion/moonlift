-- Emit compatibility ASDL parser text from canonical MoonAsdl.Schema values.
--
-- This is a bridge.  The source of truth is MoonAsdl data; direct context
-- construction can replace this emitter later.

local pvm = require("moonlift.pvm")

local M = {}

local function push(out, line)
    out[#out + 1] = line
end

local function indent(n)
    return string.rep("    ", n)
end

local function has_attr(attrs, class_or_singleton)
    for i = 1, #(attrs or {}) do
        if attrs[i] == class_or_singleton or pvm.classof(attrs[i]) == class_or_singleton then return true end
    end
    return false
end

local function type_text(A, ty)
    local cls = pvm.classof(ty)
    if cls == A.TypeBuiltin then return ty.name end
    if cls == A.TypeName then return ty.module_name .. "." .. ty.name end
    if cls == A.TypeRelativeName then return ty.name end
    if cls == A.TypeList then return type_text(A, ty.elem) .. "*" end
    if cls == A.TypeOptional then return type_text(A, ty.elem) .. "?" end
    error("asdl_emit: unsupported TypeExpr " .. tostring(cls and cls.kind or ty), 2)
end

local function field_text(A, field)
    local ty = field.ty
    if field.cardinality == A.FieldMany then ty = A.TypeList(ty)
    elseif field.cardinality == A.FieldOptional then ty = A.TypeOptional(ty) end
    return type_text(A, ty) .. " " .. field.name
end

local function fields_text(A, fields)
    local parts = {}
    for i = 1, #(fields or {}) do parts[#parts + 1] = field_text(A, fields[i]) end
    return "(" .. table.concat(parts, ", ") .. ")"
end

local function variant_text(A, variant)
    local text = variant.name
    if #(variant.fields or {}) > 0 then text = text .. fields_text(A, variant.fields) end
    if has_attr(variant.attrs, A.VariantUnique) then text = text .. " unique" end
    return text
end

local function emit_decl(A, out, decl)
    local cls = pvm.classof(decl)
    if cls == A.ProductDecl then
        local text = indent(1) .. decl.name .. " = " .. fields_text(A, decl.fields)
        if has_attr(decl.attrs, A.DeclUnique) then text = text .. " unique" end
        push(out, text)
    elseif cls == A.SumDecl then
        local variants = decl.variants or {}
        if #variants == 0 then error("asdl_emit: sum " .. decl.name .. " has no variants", 2) end
        push(out, indent(1) .. decl.name .. " = " .. variant_text(A, variants[1]))
        for i = 2, #variants do
            push(out, indent(2) .. "| " .. variant_text(A, variants[i]))
        end
    elseif cls == A.AliasDecl then
        error("asdl_emit: AliasDecl cannot be bridged through the legacy ASDL text parser yet: " .. decl.name, 2)
    else
        error("asdl_emit: unsupported Decl " .. tostring(cls and cls.kind or decl), 2)
    end
end

local function emit_module(A, out, module)
    push(out, "module " .. module.name .. " {")
    for i = 1, #(module.decls or {}) do
        emit_decl(A, out, module.decls[i])
        if i < #module.decls then push(out, "") end
    end
    push(out, "}")
end

function M.emit(schema, A)
    if A == nil then error("asdl_emit.emit expects emit(schema, T.MoonAsdl) or emit_with(T.MoonAsdl, schema)", 2) end
    return M.emit_with(A, schema)
end

function M.emit_with(A, schema)
    if pvm.classof(schema) ~= A.Schema then error("asdl_emit.emit_with expects MoonAsdl.Schema", 2) end
    local out = {}
    for i = 1, #(schema.modules or {}) do
        emit_module(A, out, schema.modules[i])
        if i < #schema.modules then push(out, "") end
    end
    return table.concat(out, "\n") .. "\n"
end

return M
