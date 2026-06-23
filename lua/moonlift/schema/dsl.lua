-- MoonSchema authoring DSL.
--
-- Schema source is Lua data authored through LLB.  Runtime ASDL classes are a
-- projection of these values, not the source of truth.

local llb = require("llb")
local Model = require("moonlift.schema_projection_model")
local DefineSchema = require("moonlift.context_define_schema")
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

local BUILTIN_ALIASES = {
    str = "string",
    bool = "boolean",
}

local function tag(v)
    return type(v) == "table" and rawget(v, "__moonschema_tag") or nil
end

local function llb_path(v)
    if llb.is(v, "Symbol") or llb.is(v, "Name") then return { v.text } end
    if llb.is(v, "Expr") and v.kind == "field" and type(v.field) == "string" then
        local path = llb_path(v.base)
        if path then
            path[#path + 1] = v.field
            return path
        end
    end
    return nil
end

local function copy_array(xs)
    local out = {}
    for i = 1, #(xs or {}) do out[i] = xs[i] end
    return out
end

local function schema_format(value, f)
    return M.format_doc(value, f)
end

local VALUE_MT = { __llb_format = schema_format }

local function node(kind, spec)
    spec = spec or {}
    spec.__moonschema_tag = kind
    if getmetatable(spec) == nil then setmetatable(spec, VALUE_MT) end
    return spec
end

function M.is_schema_value(v, kind)
    local t = tag(v)
    return kind and t == kind or t ~= nil
end

function M.name(text)
    if type(text) ~= "string" or text == "" then error("moonschema: expected non-empty name", 2) end
    return text
end

function M.type(name)
    if tag(name) == "Type" then return name end
    local path = llb_path(name)
    if path then name = table.concat(path, ".") end
    if llb.is(name, "Symbol") then name = name.text end
    if llb.is(name, "Name") then name = name.text end
    if llb.is(name, "Type") then name = name.name end
    if type(name) ~= "string" or name == "" then error("moonschema: expected type name", 2) end
    name = BUILTIN_ALIASES[name] or name
    return node("Type", { kind = BUILTINS[name] and "builtin" or "name", name = name })
end

function M.many(ty)
    return node("Type", { kind = "many", elem = M.type(ty) })
end

function M.optional(ty)
    return node("Type", { kind = "optional", elem = M.type(ty) })
end

function M.ref(ty)
    return node("Type", { kind = "ref", elem = M.type(ty) })
end

function M.id(ty)
    return node("Type", { kind = "id", elem = M.type(ty) })
end

function M.map(key, value)
    return node("Type", { kind = "map", key = M.type(key), value = M.type(value) })
end

function M.field(name, ty, attrs)
    return node("Field", { name = M.name(name), ty = M.type(ty), attrs = copy_array(attrs) })
end

function M.product(name, fields, attrs)
    return node("Decl", { kind = "product", name = M.name(name), fields = copy_array(fields), attrs = copy_array(attrs) })
end

function M.variant(name, fields, attrs)
    return node("Variant", { name = M.name(name), fields = copy_array(fields), attrs = copy_array(attrs) })
end

function M.sum(name, variants, attrs)
    return node("Decl", { kind = "sum", name = M.name(name), variants = copy_array(variants), attrs = copy_array(attrs) })
end

function M.alias(name, ty, attrs)
    return node("Decl", { kind = "alias", name = M.name(name), target = M.type(ty), attrs = copy_array(attrs) })
end

function M.schema(name, decls, attrs)
    return node("Module", { name = M.name(name), decls = copy_array(decls), attrs = copy_array(attrs) })
end

M.module = M.schema
M.unique = node("Attr", { kind = "unique" })
M.interned = M.unique
M.variant_unique = node("Attr", { kind = "variant_unique" })

function M.doc(text)
    if type(text) ~= "string" then error("moonschema: doc expects string", 2) end
    return node("Attr", { kind = "doc", text = text })
end

local function has_attr(attrs, kind)
    for i = 1, #(attrs or {}) do
        local a = attrs[i]
        if tag(a) == "Attr" and a.kind == kind then return true end
    end
    return false
end

local function split_type_name(name)
    local module_name, type_name = name:match("^(.+)%.([%a_][%w_]*)$")
    return module_name, type_name
end

local function to_asdl_type(A, ty)
    ty = M.type(ty)
    if ty.kind == "builtin" then return A.TypeBuiltin(ty.name) end
    if ty.kind == "name" then
        local module_name, type_name = split_type_name(ty.name)
        if module_name then return A.TypeName(module_name, type_name) end
        return A.TypeRelativeName(ty.name)
    end
    if ty.kind == "many" then return A.TypeList(to_asdl_type(A, ty.elem)) end
    if ty.kind == "optional" then return A.TypeOptional(to_asdl_type(A, ty.elem)) end
    if ty.kind == "ref" or ty.kind == "id" then return to_asdl_type(A, ty.elem) end
    if ty.kind == "map" then return A.TypeList(to_asdl_type(A, ty.value)) end
    error("moonschema: unsupported type kind " .. tostring(ty.kind), 2)
end

local function to_asdl_attrs(A, attrs, scope)
    local out = {}
    if has_attr(attrs, "unique") or has_attr(attrs, "interned") then
        if scope == "decl" then out[#out + 1] = A.DeclUnique end
    end
    if has_attr(attrs, "variant_unique") or has_attr(attrs, "unique") or has_attr(attrs, "interned") then
        if scope == "variant" then out[#out + 1] = A.VariantUnique end
    end
    for i = 1, #(attrs or {}) do
        local a = attrs[i]
        if tag(a) == "Attr" and a.kind == "doc" then
            if scope == "decl" then out[#out + 1] = A.DeclDoc(a.text)
            elseif scope == "variant" then out[#out + 1] = A.VariantDoc(a.text)
            elseif scope == "module" then out[#out + 1] = A.ModuleDoc(a.text) end
        end
    end
    return out
end

local function to_asdl_field(A, field)
    if tag(field) ~= "Field" then error("moonschema: expected field", 2) end
    return A.Field(field.name, to_asdl_type(A, field.ty), A.FieldOne)
end

local function to_asdl_fields(A, fields)
    local out = {}
    for i = 1, #(fields or {}) do out[#out + 1] = to_asdl_field(A, fields[i]) end
    return out
end

local function to_asdl_variant(A, variant)
    if tag(variant) ~= "Variant" then error("moonschema: expected variant", 2) end
    return A.Variant(variant.name, to_asdl_fields(A, variant.fields), to_asdl_attrs(A, variant.attrs, "variant"))
end

local function to_asdl_decl(A, decl)
    if tag(decl) ~= "Decl" then error("moonschema: expected declaration", 2) end
    if decl.kind == "product" then
        return A.ProductDecl(decl.name, to_asdl_fields(A, decl.fields), to_asdl_attrs(A, decl.attrs, "decl"))
    elseif decl.kind == "sum" then
        local variants = {}
        for i = 1, #(decl.variants or {}) do variants[#variants + 1] = to_asdl_variant(A, decl.variants[i]) end
        return A.SumDecl(decl.name, variants, to_asdl_attrs(A, decl.attrs, "decl"))
    elseif decl.kind == "alias" then
        return A.AliasDecl(decl.name, to_asdl_type(A, decl.target), to_asdl_attrs(A, decl.attrs, "decl"))
    end
    error("moonschema: unsupported declaration kind " .. tostring(decl.kind), 2)
end

local function to_asdl_module(A, module)
    if tag(module) ~= "Module" then error("moonschema: expected module", 2) end
    local decls = {}
    for i = 1, #(module.decls or {}) do decls[#decls + 1] = to_asdl_decl(A, module.decls[i]) end
    return A.Module(module.name, decls, to_asdl_attrs(A, module.attrs, "module"))
end

function M.to_asdl_schema(T, modules)
    Model.Define(T)
    local A = T.MoonAsdl
    local out = {}
    for i = 1, #(modules or {}) do out[#out + 1] = to_asdl_module(A, modules[i]) end
    return A.Schema(out)
end

function M.define(T, modules)
    return DefineSchema.define(T, M.to_asdl_schema(T, modules))
end

function M.describe(value)
    if tag(value) == "Module" then
        return { tag = "MoonSchema.Module", name = value.name, decl_count = #(value.decls or {}) }
    elseif tag(value) == "Decl" then
        return { tag = "MoonSchema.Decl", kind = value.kind, name = value.name }
    elseif tag(value) == "Variant" then
        return { tag = "MoonSchema.Variant", name = value.name, field_count = #(value.fields or {}) }
    elseif tag(value) == "Field" then
        return { tag = "MoonSchema.Field", name = value.name, ty = value.ty }
    elseif tag(value) == "Type" then
        return { tag = "MoonSchema.Type", kind = value.kind, name = value.name }
    end
    return llb.describe and llb.describe(value) or { tag = type(value) }
end

-- LLB authoring surface ------------------------------------------------------

llb.register_type_like(function(v)
    return tag(v) == "Type"
end)

local TypeCtor = {}
TypeCtor.__index = function(self, key)
    local args = copy_array(rawget(self, "args"))
    args[#args + 1] = key
    local arity = rawget(self, "arity")
    if #args < arity then
        return setmetatable({ name = self.name, arity = arity, args = args, emit = self.emit }, TypeCtor)
    end
    return self.emit(unpack(args, 1, #args))
end
TypeCtor.__call = function(self, ...)
    local cur = self
    for i = 1, select("#", ...) do cur = TypeCtor.__index(cur, select(i, ...)) end
    return cur
end

local function type_ctor(name, arity, emit)
    return setmetatable({ name = name, arity = arity or 1, args = {}, emit = emit }, TypeCtor)
end

local function type_value(v)
    return M.type(v)
end

local function field_from_capture(item)
    if llb.is(item, "Capture") then
        if not llb.is(item.subject, "Symbol") then error("moonschema: field subject must be a symbol", 2) end
        return M.field(item.subject.text, type_value(item.value))
    end
    error("moonschema: expected field capture", 2)
end

local function field_from_index_expr(item)
    if llb.is(item, "Expr") and item.kind == "index" and llb.is(item.base, "Symbol") and llb_path(item.index) then
        return M.field(item.base.text, type_value(item.index))
    end
    return nil
end

local function normalize_body(tbl, allow_variants)
    local attrs, fields, variants, decls = {}, {}, {}, {}
    for i = 1, #(tbl or {}) do
        local item = tbl[i]
        local indexed_field = field_from_index_expr(item)
        if tag(item) == "Attr" then
            attrs[#attrs + 1] = item
        elseif tag(item) == "Field" then
            fields[#fields + 1] = item
        elseif tag(item) == "Variant" then
            variants[#variants + 1] = item
        elseif tag(item) == "Decl" then
            decls[#decls + 1] = item
        elseif llb.is(item, "Capture") then
            fields[#fields + 1] = field_from_capture(item)
        elseif indexed_field then
            fields[#fields + 1] = indexed_field
        elseif allow_variants and llb.is(item, "Symbol") then
            variants[#variants + 1] = M.variant(item.text, {})
        elseif allow_variants and llb.is(item, "Expr") and item.kind == "call" and llb.is(item.callee, "Symbol") then
            local args = item.args or {}
            if (args.n or #args) ~= 1 or type(args[1]) ~= "table" then error("moonschema: variant payload must be one table", 2) end
            local body = normalize_body(args[1], false)
            variants[#variants + 1] = M.variant(item.callee.text, body.fields, body.attrs)
        else
            error("moonschema: unexpected body item " .. tostring(llb.repr and llb.repr(item) or item), 2)
        end
    end
    return { attrs = attrs, fields = fields, variants = variants, decls = decls }
end

local g = llb.grammar

local Lang = llb.define "MoonSchema" {
    g.role .decls {
        kind = "array",
        normalize = function(_, _, v)
            local body = normalize_body(v, false)
            return body.decls
        end,
    },

    g.role .product_body {
        kind = "array",
        normalize = function(_, _, v)
            return normalize_body(v, false)
        end,
    },

    g.role .sum_body {
        kind = "array",
        normalize = function(_, _, v)
            return normalize_body(v, true)
        end,
    },

    g.role .schema_type {
        kind = "value",
        normalize = function(_, _, v)
            return type_value(v)
        end,
    },

    -- Declares a MoonSchema module: the root namespace for ASDL products, sums,
    -- and aliases.
    g.head .schema {
        g.slot .name [g.name],
        g.slot .decls [g.decls],
        emit = function(n)
            return M.schema(n.name.text, n.decls)
        end,
    },

    -- Declares a product type with named fields.
    g.head .product {
        g.slot .name [g.name],
        g.slot .body [g.product_body],
        emit = function(n)
            return M.product(n.name.text, n.body.fields, n.body.attrs)
        end,
    },

    -- Declares a sum type with named variants.
    g.head .sum {
        g.slot .name [g.name],
        g.slot .body [g.sum_body],
        emit = function(n)
            return M.sum(n.name.text, n.body.variants, n.body.attrs)
        end,
    },

    -- Declares a type alias to another schema type path.
    g.head .alias {
        g.slot .name [g.name],
        g.slot .target [g.schema_type] { channels = { "index:type", "index:value" } },
        emit = function(n)
            return M.alias(n.name.text, n.target)
        end,
    },

    -- Declares a field when the field name collides with a schema helper or Lua
    -- reserved word.
    g.head .field {
        g.slot .name [g.name],
        g.slot .target [g.schema_type] { channels = { "index:type", "index:value" } },
        emit = function(n)
            return M.field(n.name.text, n.target)
        end,
    },

    g.helper .str { value = M.type("string") },
    g.helper .bool { value = M.type("boolean") },
    g.helper .number { value = M.type("number") },
    g.helper .any { value = M.type("any") },
    g.helper .table_ty { value = M.type("table") },
    g.helper .function_ty { value = M.type("function") },
    g.helper .nil_ty { value = M.type("nil") },
    g.helper .interned { value = M.interned },
    g.helper .unique { value = M.unique },
    g.helper .variant_unique { value = M.variant_unique },
    g.helper .many { value = type_ctor("many", 1, M.many) },
    g.helper .optional { value = type_ctor("optional", 1, M.optional) },
    g.helper .ref { value = type_ctor("ref", 1, M.ref) },
    g.helper .id { value = type_ctor("id", 1, M.id) },
    g.helper .map { value = type_ctor("map", 2, M.map) },
}

function M.make_env(opts)
    return Lang:env(opts)
end

function M.use(opts)
    opts = opts or {}
    opts.provides = opts.provides or { "moonschema" }
    return Lang:use(opts)
end

function M.loadstring(src, chunkname, opts)
    return Lang:loadstring(src, chunkname, opts)
end

function M.loadfile(path, opts)
    return Lang:loadfile(path, opts)
end

M.Language = Lang
M.tag = tag
M.moonschema = llb.zone_head { family = "moonlift", member = "moonschema.dsl", name = "schema", role = "decls" }

function M.namespace(opts)
    local env = Lang:env { base = opts and opts.base or nil }
    return llb.namespace {
        family = "moonlift",
        member = "moonschema.dsl",
        name = "schema",
        zone = M.moonschema,
        default_head = env.schema,
        exports = {
        module = env.schema,
        product = env.product,
        sum = env.sum,
        alias = env.alias,
        field = env.field,
        str = env.str,
        bool = env.bool,
        number = env.number,
        any = env.any,
        table_ty = env.table_ty,
        function_ty = env.function_ty,
        nil_ty = env.nil_ty,
        interned = env.interned,
        unique = env.unique,
        variant_unique = env.variant_unique,
        many = env.many,
        optional = env.optional,
        ref = env.ref,
        id = env.id,
        map = env.map,
        },
    }
end

function M.make_family_env(opts)
    return {
        schema = M.namespace(opts),
    }
end

-- Formatting ----------------------------------------------------------------

local function ident(s)
    return type(s) == "string" and s:match("^[_%a][_%w]*$") ~= nil and not ({ ["function"] = true, ["nil"] = true, ["true"] = true, ["false"] = true, ["local"] = true, ["return"] = true, ["end"] = true })[s]
end

local FIELD_CAPTURE_RESERVED = {
    schema = true, product = true, sum = true, alias = true, field = true,
    str = true, bool = true, number = true, any = true,
    table_ty = true, function_ty = true, nil_ty = true,
    interned = true, unique = true, variant_unique = true,
    many = true, optional = true, ref = true, id = true, map = true,
    llb = true, N = true, spread = true, _ = true, process = true, process_opts = true,
    here = true, at_origin = true, with_origin = true,
    decls = true, product_body = true, sum_body = true, schema_type = true,
    name = true, expr = true, boolean = true, identity = true, module = true,
    value = true, type = true, string = true, table = true, math = true,
    require = true, pairs = true, ipairs = true, error = true, assert = true,
    print = true, select = true, tostring = true, tonumber = true, pcall = true,
    xpcall = true, coroutine = true, unpack = true, next = true,
}

local function quote(s)
    return string.format("%q", tostring(s))
end

local function attr_doc(a, f)
    if a.kind == "unique" then return f:text("interned") end
    if a.kind == "variant_unique" then return f:text("variant_unique") end
    if a.kind == "doc" then return f:concat { "doc ", quote(a.text) } end
    return f:text(tostring(a.kind))
end

local function type_doc(ty, f)
    ty = M.type(ty)
    if ty.kind == "builtin" then
        if ty.name == "string" then return f:text("str") end
        if ty.name == "boolean" then return f:text("bool") end
        if ty.name == "table" then return f:text("table_ty") end
        if ty.name == "function" then return f:text("function_ty") end
        if ty.name == "nil" then return f:text("nil_ty") end
        return f:text(ty.name)
    elseif ty.kind == "name" then
        return f:text(ty.name)
    elseif ty.kind == "many" or ty.kind == "optional" or ty.kind == "ref" or ty.kind == "id" then
        return f:group { ty.kind, " [", type_doc(ty.elem, f), "]" }
    elseif ty.kind == "map" then
        return f:group { "map [", type_doc(ty.key, f), "] [", type_doc(ty.value, f), "]" }
    end
    return f:text("<type>")
end

local function field_doc(field, f)
    if not ident(field.name) then
        error("moonschema: cannot format non-identifier field name " .. quote(field.name), 2)
    end
    if FIELD_CAPTURE_RESERVED[field.name] then
        return f:group { "field. ", field.name, " [", type_doc(field.ty, f), "]" }
    end
    return f:group { field.name, " [", type_doc(field.ty, f), "]" }
end

local function entries_block(entries, f)
    return f:block(entries, {
        format = function(item, ff)
            if tag(item) == "Attr" then return attr_doc(item, ff) end
            if tag(item) == "Field" then return field_doc(item, ff) end
            if tag(item) == "Variant" then return variant_doc(item, ff) end
            if tag(item) == "Decl" then return decl_doc(item, ff) end
            return ff:format(item)
        end,
    })
end

function variant_doc(variant, f)
    local entries = {}
    for i = 1, #(variant.attrs or {}) do entries[#entries + 1] = variant.attrs[i] end
    for i = 1, #(variant.fields or {}) do entries[#entries + 1] = variant.fields[i] end
    if #entries == 0 then return f:text(variant.name) end
    return f:group { variant.name, " ", entries_block(entries, f) }
end

function decl_doc(decl, f)
    if decl.kind == "product" then
        local entries = {}
        for i = 1, #(decl.attrs or {}) do entries[#entries + 1] = decl.attrs[i] end
        for i = 1, #(decl.fields or {}) do entries[#entries + 1] = decl.fields[i] end
        return f:group { "product. ", decl.name, " ", entries_block(entries, f) }
    elseif decl.kind == "sum" then
        local entries = {}
        for i = 1, #(decl.attrs or {}) do entries[#entries + 1] = decl.attrs[i] end
        for i = 1, #(decl.variants or {}) do entries[#entries + 1] = decl.variants[i] end
        return f:group { "sum. ", decl.name, " ", entries_block(entries, f) }
    elseif decl.kind == "alias" then
        return f:group { "alias. ", decl.name, " [", type_doc(decl.target, f), "]" }
    end
    return f:text("<decl>")
end

function M.format_doc(value, f)
    f = getmetatable(f) == llb.FormatContext and f or llb.FormatContext and f or nil
    if not f or not f.text then
        return llb.format_doc(value)
    end
    local t = tag(value)
    if t == "Module" then
        local entries = {}
        for i = 1, #(value.attrs or {}) do entries[#entries + 1] = value.attrs[i] end
        for i = 1, #(value.decls or {}) do entries[#entries + 1] = value.decls[i] end
        return f:group { "schema. ", value.name, " ", entries_block(entries, f) }
    elseif t == "Decl" then return decl_doc(value, f)
    elseif t == "Variant" then return variant_doc(value, f)
    elseif t == "Field" then return field_doc(value, f)
    elseif t == "Type" then return type_doc(value, f)
    elseif t == "Attr" then return attr_doc(value, f) end
    return f:text(tostring(value))
end

function M.format(value, opts)
    opts = opts or {}
    return llb.format(value, opts)
end

function M.file_text(module_value, opts)
    local body = M.format(module_value, opts)
    return table.concat({
        "local S = require(\"moonlift.schema.dsl\")",
        "S.use()",
        "",
        "return " .. body,
        "",
    }, "\n")
end

return M
