-- lalin/error/format.lua
-- Shared formatting utilities for error messages.
--
-- Extracted from catalog.lua so all phase explainers can use the same
-- type_name(), op_symbol(), scalar_name(), and access_mode_name() functions
-- without duplication.

local M = {}

-------------------------------------------------------------------------------
-- Type name formatting
-------------------------------------------------------------------------------

local scalar_labels = {
    ScalarVoid = "void", ScalarBool = "bool",
    ScalarI8 = "i8", ScalarI16 = "i16", ScalarI32 = "i32", ScalarI64 = "i64",
    ScalarU8 = "u8", ScalarU16 = "u16", ScalarU32 = "u32", ScalarU64 = "u64",
    ScalarF32 = "f32", ScalarF64 = "f64", ScalarRawPtr = "rawptr", ScalarIndex = "index",
}

M.scalar_labels = scalar_labels

function M.type_name(ty)
    if not ty then return "<unknown>" end
    if type(ty) ~= "table" then return tostring(ty) end
    local asdl = require("lalin.asdl")
    local class = asdl.class_basename(ty)

    -- Check for ASDL types
    if class then
        if scalar_labels[class] then return scalar_labels[class] end

        if class == "TScalar" then
            local scalar_class = ty.scalar and asdl.class_basename(ty.scalar)
            return (scalar_class and scalar_labels[scalar_class]) or class
        end
        if class == "TPtr" then return "ptr(" .. M.type_name(ty.elem) .. ")" end
        if class == "TView" then return "view(" .. M.type_name(ty.elem) .. ")" end
        if class == "TLease" then
            local origin = ""
            if ty.origin and asdl.class_basename(ty.origin) == "LeaseOriginParam" then origin = "(" .. tostring(ty.origin.name) .. ")" end
            return "lease" .. origin .. " " .. M.type_name(ty.base)
        end
        if class == "TOwned" then return "owned " .. M.type_name(ty.base) end
        if class == "TAccess" then
            local access_class = ty.access and asdl.class_basename(ty.access)
            local label = ({
                TypeAccessNoAlias = "noalias",
                TypeAccessReadonly = "readonly",
                TypeAccessWriteonly = "writeonly",
                TypeAccessNoEscape = "noescape",
                TypeAccessInvalidate = "invalidate",
                TypeAccessPreserve = "preserve",
            })[access_class] or tostring(ty.access)
            return label .. " " .. M.type_name(ty.base)
        end
        if class == "THandle" then
            local ref = ty.ref
            local ref_class = ref and asdl.class_basename(ref)
            if ref_class == "TypeRefGlobal" then return ref.type_name end
            if ref_class == "TypeRefPath" and ref.path then
                local parts = {}
                for i = 1, #(ref.path.parts or {}) do parts[i] = ref.path.parts[i].text end
                if #parts > 0 then return table.concat(parts, ".") end
            end
            return "handle"
        end
        if class == "TSlice" then return "slice(" .. M.type_name(ty.elem) .. ")" end
        if class == "TArray" then return "array(" .. M.type_name(ty.elem) .. ")" end
        if class == "TFunc" then return "func(...): " .. M.type_name(ty.result) end
        if class == "TClosure" then return "closure(...): " .. M.type_name(ty.result) end
        if class == "TNamed" then
            local ref = ty.ref
            if ref then
                local ref_class = asdl.class_basename(ref)
                if ref_class == "TypeRefGlobal" then return ref.type_name end
                if ref_class == "TypeRefLocal" then return ref.sym and ref.sym.name or ref.sym end
                if ref_class == "TypeRefPath" and ref.path then
                    local parts = {}
                    for i = 1, #(ref.path.parts or {}) do parts[i] = ref.path.parts[i].text end
                    return table.concat(parts, ".")
                end
            end
        end
        return class
    end

    -- Fallback for simple tables
    if ty.scalar then return M.type_name(ty.scalar) end
    if ty.elem then return "ptr(" .. M.type_name(ty.elem) .. ")" end
    return tostring(ty)
end

-------------------------------------------------------------------------------
-- Operator symbol formatting
-------------------------------------------------------------------------------

local op_symbols = {
    BinAdd = "+", BinSub = "-", BinMul = "*", BinDiv = "/", BinRem = "%",
    BinBitAnd = "&", BinBitOr = "|", BinBitXor = "~", BinShl = "<<", BinLShr = ">>>", BinAShr = ">>",
    CmpEq = "==", CmpNe = "~=", CmpLt = "<", CmpLe = "<=", CmpGt = ">", CmpGe = ">=",
    LogicAnd = "&&", LogicOr = "||", UnaryNot = "not", UnaryNeg = "-", UnaryBitNot = "~",
    ["LalinCore.BinAdd"] = "+", ["LalinCore.BinSub"] = "-", ["LalinCore.BinMul"] = "*",
    ["LalinCore.BinDiv"] = "/", ["LalinCore.BinRem"] = "%",
    ["LalinCore.BinBitAnd"] = "&", ["LalinCore.BinBitOr"] = "|", ["LalinCore.BinBitXor"] = "~",
    ["LalinCore.BinShl"] = "<<", ["LalinCore.BinLShr"] = ">>>", ["LalinCore.BinAShr"] = ">>",
    ["LalinCore.CmpEq"] = "==", ["LalinCore.CmpNe"] = "~=", ["LalinCore.CmpLt"] = "<",
    ["LalinCore.CmpLe"] = "<=", ["LalinCore.CmpGt"] = ">", ["LalinCore.CmpGe"] = ">=",
    ["LalinCore.LogicAnd"] = "and", ["LalinCore.LogicOr"] = "or",
    ["LalinCore.UnaryNot"] = "not", ["LalinCore.UnaryNeg"] = "-", ["LalinCore.UnaryBitNot"] = "~",
}

function M.op_symbol(op)
    if not op then return "?" end
    local s = tostring(op)
    if op_symbols[s] then return op_symbols[s] end
    -- Strip "LalinCore." prefix if present and retry
    local short = s:match("^LalinCore%.(.+)$")
    if short and op_symbols[short] then return op_symbols[short] end
    return s
end

-------------------------------------------------------------------------------
-- Scalar name formatting (for BackScalar values)
-------------------------------------------------------------------------------

function M.scalar_name(scalar)
    if not scalar then return "?" end
    local asdl = require("lalin.asdl")
    local class = asdl.class_basename(scalar)
    if class and scalar_labels[class] then return scalar_labels[class] end
    return tostring(scalar)
end

-------------------------------------------------------------------------------
-- Access mode name formatting (for BackAccessEffect values)
-------------------------------------------------------------------------------

function M.access_mode_name(mode)
    if not mode then return "?" end
    local asdl = require("lalin.asdl")
    local class = asdl.class_basename(mode)
    if not class then return tostring(mode) end
    if class == "AccessModeLoad" then return "load" end
    if class == "AccessModeStore" then return "store" end
    if class == "AccessModeLoadStore" then return "load-store" end
    return class
end

-------------------------------------------------------------------------------
-- Re-exports
-------------------------------------------------------------------------------

M.Suggest = require("lalin.error.suggest")
M.SpanResolvers = require("lalin.error.span_resolvers")

-----------------------------------------------------------------------------
-- Resolve class from issue, with fallback to issue.kind
--
-- All explainers use this instead of raw asdl.classof() so they work with
-- both real ASDL nodes and mock issues (which have a .kind field).
-----------------------------------------------------------------------------

function M.resolve_class(issue)
    local asdl = require("lalin.asdl")
    local cls = asdl.classof(issue)
    if cls then return cls end
    if issue and issue.kind then
        return { kind = issue.kind }
    end
    return nil
end

return M
