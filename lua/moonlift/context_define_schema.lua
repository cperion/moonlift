-- Define ASDL context modules directly from MoonAsdl.Schema data.
-- No text round-trip — converts MoonAsdl values straight to the definition
-- format that asdl_context expects.

local pvm = require("moonlift.pvm")
local asdl_context = require("moonlift.asdl_context")

local M = {}

local function basename(name)
    return name:match("([^.]*)$")
end

local function type_name(A, ty)
    local cls = pvm.classof(ty)
    if cls == A.TypeBuiltin then return ty.name end
    if cls == A.TypeName then return ty.module_name .. "." .. ty.name end
    if cls == A.TypeRelativeName then return ty.name end
    if cls == A.TypeList then return type_name(A, ty.elem) end
    if cls == A.TypeOptional then return type_name(A, ty.elem) end
    error("context_define_schema: unsupported TypeExpr " .. tostring(cls and cls.kind or tostring(ty)), 2)
end

local function convert_field(A, field)
    local d = { name = field.name }
    local ty = field.ty
    local cls = pvm.classof(ty)
    -- Unwrap TypeList/TypeOptional: set field flags, use inner type name
    if cls == A.TypeList then
        d.list = true
        ty = ty.elem
        cls = pvm.classof(ty)
    elseif cls == A.TypeOptional then
        d.optional = true
        ty = ty.elem
        cls = pvm.classof(ty)
    end
    d.type = type_name(A, ty)
    return d
end

local function convert_fields(A, fields)
    if #(fields or {}) == 0 then return nil end
    local out = {}
    for i = 1, #fields do
        out[#out + 1] = convert_field(A, fields[i])
    end
    return out
end

local function has_attr(attrs, class_or_singleton)
    for i = 1, #(attrs or {}) do
        if attrs[i] == class_or_singleton or pvm.classof(attrs[i]) == class_or_singleton then
            return true
        end
    end
    return false
end

local function convert_module(A, module)
    local defs = {}
    local mod_ns = module.name .. "."
    for _, decl in ipairs(module.decls or {}) do
        local cls = pvm.classof(decl)
        local fq_name = mod_ns .. decl.name
        if cls == A.ProductDecl then
            defs[#defs + 1] = {
                name = fq_name,
                type = {
                    kind = "product",
                    unique = has_attr(decl.attrs, A.DeclUnique),
                    fields = convert_fields(A, decl.fields),
                },
            }
        elseif cls == A.SumDecl then
            local ctors = {}
            for _, variant in ipairs(decl.variants or {}) do
                ctors[#ctors + 1] = {
                    name = mod_ns .. variant.name,
                    unique = has_attr(variant.attrs, A.VariantUnique),
                    fields = convert_fields(A, variant.fields),
                }
            end
            defs[#defs + 1] = {
                name = fq_name,
                type = {
                    kind = "sum",
                    constructors = ctors,
                },
            }
        elseif cls == A.AliasDecl then
            defs[#defs + 1] = {
                name = fq_name,
                type = {
                    kind = "product",
                    unique = true,
                    fields = {
                        { name = "value", type = type_name(A, decl.target) },
                    },
                },
            }
        end
    end
    return defs
end

function M.define(T, schema)
    local A = assert(T.MoonAsdl, "context_define_schema.define expects MoonAsdl to be defined in the context")
    if pvm.classof(schema) ~= A.Schema then
        error("context_define_schema.define expects MoonAsdl.Schema", 2)
    end

    -- Convert each module into definition lists.
    local defs = {}
    for _, module in ipairs(schema.modules or {}) do
        local module_defs = convert_module(A, module)
        for _, d in ipairs(module_defs) do
            defs[#defs + 1] = d
        end
    end

    asdl_context.define(T, defs)
    return T
end

return M
