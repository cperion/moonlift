-- Emit MoonAsdl.Schema declarations as ordinary Moonlift surface type skeletons.
--
-- Products become structs. Sums become tagged unions. Every declared ASDL type
-- also receives an Id and Arena skeleton so phase subjects/cache keys can use
-- stable identities without fake manual tag structs.

local pvm = require("moonlift.pvm")
local AsdlModel = require("moonlift.asdl_model")

local M = {}

local function push(out, line)
    out[#out + 1] = line
end

local function sanitize(name)
    return tostring(name):gsub("[^%w_]", "_")
end

local function qname(module_name, name)
    return sanitize(module_name) .. "_" .. sanitize(name)
end

local function scalar_builtin(name)
    if name == "boolean" then return "bool" end
    if name == "number" then return "i64" end
    if name == "string" then return "StringId" end
    return name
end

local function type_base(A, current_module, ty, opts)
    local cls = pvm.classof(ty)
    if cls == A.TypeBuiltin then return scalar_builtin(ty.name) end
    if cls == A.TypeRelativeName then return qname(current_module, ty.name) end
    if cls == A.TypeName then return qname(ty.module_name, ty.name) end
    if cls == A.TypeList then return type_base(A, current_module, ty.elem, opts) .. "Range" end
    if cls == A.TypeOptional then return "Optional" .. type_base(A, current_module, ty.elem, opts) end
    error("pvm_surface_schema_emit: unsupported TypeExpr", 2)
end

local function type_ref(A, current_module, ty, opts)
    opts = opts or {}
    local cls = pvm.classof(ty)
    if cls == A.TypeBuiltin then return scalar_builtin(ty.name) end
    if cls == A.TypeList or cls == A.TypeOptional then return type_base(A, current_module, ty, opts) end
    local base = type_base(A, current_module, ty, opts)
    local key
    if cls == A.TypeRelativeName then key = current_module .. "." .. ty.name
    elseif cls == A.TypeName then key = ty.module_name .. "." .. ty.name end
    if opts.by_value and key and opts.by_value[key] then return base end
    return base .. "Id"
end

local function emit_id_and_arena(out, name)
    push(out, "type " .. name .. "Id = struct")
    push(out, "    index: index")
    push(out, "end")
    push(out, "")
    push(out, "type " .. name .. "Arena = struct")
    push(out, "    values: ptr(" .. name .. ")")
    push(out, "    len: index")
    push(out, "end")
    push(out, "")
end

local function emit_product(A, out, module_name, decl, opts)
    local name = qname(module_name, decl.name)
    emit_id_and_arena(out, name)
    push(out, "type " .. name .. " = struct")
    for i = 1, #decl.fields do
        local f = decl.fields[i]
        push(out, "    " .. f.name .. ": " .. type_ref(A, module_name, f.ty, opts))
    end
    push(out, "end")
    push(out, "")
end

local function emit_payload_struct(A, out, module_name, sum_name, variant, opts)
    local payload = qname(module_name, sum_name .. "_" .. variant.name .. "Payload")
    push(out, "type " .. payload .. " = struct")
    for i = 1, #variant.fields do
        local f = variant.fields[i]
        push(out, "    " .. f.name .. ": " .. type_ref(A, module_name, f.ty, opts))
    end
    push(out, "end")
    push(out, "")
    return payload
end

local function emit_sum(A, out, module_name, decl, opts)
    local name = qname(module_name, decl.name)
    local payloads = {}
    for i = 1, #decl.variants do
        local v = decl.variants[i]
        if #v.fields > 1 then payloads[v.name] = emit_payload_struct(A, out, module_name, decl.name, v, opts) end
    end
    emit_id_and_arena(out, name)
    push(out, "type " .. name .. " =")
    for i = 1, #decl.variants do
        local v = decl.variants[i]
        local line = "    " .. (i == 1 and "" or "| ") .. v.name
        if #v.fields == 1 then
            line = line .. "(" .. type_ref(A, module_name, v.fields[1].ty, opts) .. ")"
        elseif #v.fields > 1 then
            line = line .. "(" .. payloads[v.name] .. ")"
        end
        push(out, line)
    end
    push(out, "")
end

local function emit_module(A, out, module, opts)
    push(out, "-- MoonAsdl module " .. module.name .. " lowered to Moonlift surface")
    for i = 1, #module.decls do
        local decl = module.decls[i]
        local cls = pvm.classof(decl)
        if cls == A.ProductDecl then emit_product(A, out, module.name, decl, opts)
        elseif cls == A.SumDecl then emit_sum(A, out, module.name, decl, opts)
        end
    end
end

function M.emit(T, schema, opts)
    AsdlModel.Define(T)
    local A = T.MoonAsdl
    if pvm.classof(schema) ~= A.Schema then error("pvm_surface_schema_emit.emit expects MoonAsdl.Schema", 2) end
    local out = {}
    push(out, "-- generated Moonlift surface schema skeleton")
    push(out, "type StringId = struct")
    push(out, "    index: index")
    push(out, "end")
    push(out, "")
    for i = 1, #schema.modules do emit_module(A, out, schema.modules[i], opts or {}) end
    return table.concat(out, "\n") .. "\n"
end

function M.Define(T)
    AsdlModel.Define(T)
    return {
        emit = function(schema, opts) return M.emit(T, schema, opts) end,
    }
end

return M
