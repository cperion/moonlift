-- Helpers for converting between MoonAsdl schema values and compact ASDL text.
--
-- The runtime schema source of truth is .asdl text.  This module keeps the
-- existing MoonAsdl-as-data API available for tools/tests that want to inspect
-- the schema, and provides the one-shot converter used to migrate old Lua
-- builder modules.

local parser = require("moonlift.asdl_parser")
local Model = require("moonlift.asdl_model")
local pvm = require("moonlift.pvm")

local M = {}

local BUILTINS = {
    string = true,
    number = true,
    boolean = true,
    ["nil"] = true,
    table = true,
    ["function"] = true,
    any = true,
}

local function basename(name)
    return name:match("([^.]*)$")
end

local function dirname(name)
    return name:match("^(.*%.)[^.]*$") or ""
end

local function strip_prefix(s, prefix)
    if prefix ~= "" and s:sub(1, #prefix) == prefix then
        return s:sub(#prefix + 1)
    end
    return s
end

local function type_expr(A, name)
    if BUILTINS[name] then return A.TypeBuiltin(name) end
    local module_name, type_name = name:match("^(.+)%.([%a_][%w_]*)$")
    if module_name then return A.TypeName(module_name, type_name) end
    return A.TypeRelativeName(name)
end

local function field_from_parsed(A, f)
    local ty = type_expr(A, f.type)
    if f.list then ty = A.TypeList(ty)
    elseif f.optional then ty = A.TypeOptional(ty) end
    return A.Field(f.name, ty, A.FieldOne)
end

local function fields_from_parsed(A, fields)
    local out = {}
    for i = 1, #(fields or {}) do
        out[#out + 1] = field_from_parsed(A, fields[i])
    end
    return out
end

local function schema_from_defs(T, defs)
    Model.Define(T)
    local A = T.MoonAsdl
    local module_order, module_decls = {}, {}

    local function ensure_module(module_name)
        if not module_decls[module_name] then
            module_decls[module_name] = {}
            module_order[#module_order + 1] = module_name
        end
        return module_decls[module_name]
    end

    for _, d in ipairs(defs or {}) do
        local ns = d.namespace or dirname(d.name)
        if ns:sub(-1) == "." then ns = ns:sub(1, -2) end
        if ns == "" then error("asdl_text: top-level definitions are not supported in schema text", 2) end
        local decl_name = basename(d.name)
        local decls = ensure_module(ns)
        if d.type.kind == "product" then
            local attrs = {}
            if d.type.unique then attrs[#attrs + 1] = A.DeclUnique end
            decls[#decls + 1] = A.ProductDecl(decl_name, fields_from_parsed(A, d.type.fields), attrs)
        elseif d.type.kind == "sum" then
            local variants = {}
            for _, c in ipairs(d.type.constructors or {}) do
                local vattrs = {}
                if c.unique then vattrs[#vattrs + 1] = A.VariantUnique end
                variants[#variants + 1] = A.Variant(
                    strip_prefix(c.name, ns .. "."),
                    fields_from_parsed(A, c.fields),
                    vattrs
                )
            end
            decls[#decls + 1] = A.SumDecl(decl_name, variants, {})
        else
            error("asdl_text: unsupported parsed declaration kind " .. tostring(d.type.kind), 2)
        end
    end

    local modules = {}
    for _, module_name in ipairs(module_order) do
        modules[#modules + 1] = A.Module(module_name, module_decls[module_name], {})
    end
    return A.Schema(modules)
end

function M.parse_schema(T, text)
    return schema_from_defs(T, parser.parse(text))
end

function M.concat_modules(modules)
    return table.concat(modules, "\n\n")
end

local function emit_type(A, ty, current_module)
    local cls = pvm.classof(ty)
    if cls == A.TypeBuiltin then return ty.name end
    if cls == A.TypeName then return ty.module_name .. "." .. ty.name end
    if cls == A.TypeRelativeName then
        if BUILTINS[ty.name] then return ty.name end
        -- Fully qualify relative names so the existing text parser, whose
        -- parsed field records are flat strings, can round-trip without hidden
        -- namespace resolution.
        if current_module and current_module ~= "" then
            return current_module .. "." .. ty.name
        end
        return ty.name
    end
    if cls == A.TypeList then return emit_type(A, ty.elem, current_module) .. "*" end
    if cls == A.TypeOptional then return emit_type(A, ty.elem, current_module) .. "?" end
    error("asdl_text: unsupported TypeExpr " .. tostring(cls and cls.kind or cls), 2)
end

local function emit_field(A, field, current_module)
    return emit_type(A, field.ty, current_module) .. " " .. field.name
end

local function emit_fields(A, fields, current_module)
    local parts = {}
    for i = 1, #(fields or {}) do
        parts[#parts + 1] = emit_field(A, fields[i], current_module)
    end
    return "(" .. table.concat(parts, ", ") .. ")"
end

local function has_attr(attrs, attr)
    for i = 1, #(attrs or {}) do
        if attrs[i] == attr or pvm.classof(attrs[i]) == attr then return true end
    end
    return false
end

local function emit_variant(A, variant, current_module)
    local s = variant.name
    if #(variant.fields or {}) > 0 then
        s = s .. emit_fields(A, variant.fields, current_module)
    end
    if has_attr(variant.attrs, A.VariantUnique) then s = s .. " unique" end
    return s
end

local function emit_decl(A, decl, current_module)
    local cls = pvm.classof(decl)
    if cls == A.ProductDecl then
        local s = "    " .. decl.name .. " = " .. emit_fields(A, decl.fields, current_module)
        if has_attr(decl.attrs, A.DeclUnique) then s = s .. " unique" end
        return s
    elseif cls == A.SumDecl then
        local variants = {}
        for i = 1, #(decl.variants or {}) do
            local prefix = (i == 1) and ("    " .. decl.name .. " = ") or "         | "
            variants[#variants + 1] = prefix .. emit_variant(A, decl.variants[i], current_module)
        end
        return table.concat(variants, "\n")
    elseif cls == A.AliasDecl then
        -- The legacy text parser has no alias production.  Preserve the old
        -- context_define_schema behavior: aliases lower as unique value products.
        return "    " .. decl.name .. " = (" .. emit_type(A, decl.target, current_module) .. " value) unique"
    end
    error("asdl_text: unsupported Decl " .. tostring(cls and cls.kind or cls), 2)
end

function M.emit_module(T, module)
    local A = assert(T.MoonAsdl, "emit_module expects MoonAsdl in context")
    local lines = { "module " .. module.name .. " {" }
    for i = 1, #(module.decls or {}) do
        if i > 1 then lines[#lines + 1] = "" end
        lines[#lines + 1] = emit_decl(A, module.decls[i], module.name)
    end
    lines[#lines + 1] = "}"
    lines[#lines + 1] = ""
    return table.concat(lines, "\n")
end

function M.emit_schema(T, schema)
    local A = assert(T.MoonAsdl, "emit_schema expects MoonAsdl in context")
    assert(pvm.classof(schema) == A.Schema, "emit_schema expects MoonAsdl.Schema")
    local chunks = {}
    for i = 1, #(schema.modules or {}) do
        chunks[#chunks + 1] = M.emit_module(T, schema.modules[i])
    end
    return table.concat(chunks, "\n")
end

function M.read_file(path)
    local f, err = io.open(path, "rb")
    if not f then return nil, err end
    local s = f:read("*a")
    f:close()
    return s
end

function M.write_file(path, text)
    local f, err = io.open(path, "wb")
    if not f then error(err, 2) end
    f:write(text)
    f:close()
end

function M.load_text(module_name, path)
    local preload_name = module_name .. "_asdl"
    local ok, embedded = pcall(require, preload_name)
    if ok then return embedded end
    local text, err = M.read_file(path)
    if not text then error("asdl_text: cannot read " .. path .. ": " .. tostring(err), 2) end
    return text
end

return M
