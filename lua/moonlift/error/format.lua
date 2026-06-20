-- moonlift/error/format.lua
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
    local pvm = require("moonlift.pvm")
    local cls = pvm.classof(ty)

    -- Check for ASDL types
    if cls then
        if scalar_labels[cls.kind] then return scalar_labels[cls.kind] end

        if cls.kind == "TScalar" then
            local scls = ty.scalar and pvm.classof(ty.scalar)
            return (scls and scalar_labels[scls.kind]) or cls.kind
        end
        if cls.kind == "TPtr" then return "ptr(" .. M.type_name(ty.elem) .. ")" end
        if cls.kind == "TView" then return "view(" .. M.type_name(ty.elem) .. ")" end
        if cls.kind == "TLease" then
            local origin = ""
            local ocls = ty.origin and pvm.classof(ty.origin)
            if ocls and ocls.kind == "LeaseOriginParam" then origin = "(" .. tostring(ty.origin.name) .. ")" end
            return "lease" .. origin .. " " .. M.type_name(ty.base)
        end
        if cls.kind == "TOwned" then return "owned " .. M.type_name(ty.base) end
        if cls.kind == "TAccess" then
            local acls = ty.access and pvm.classof(ty.access)
            local label = ({
                TypeAccessNoAlias = "noalias",
                TypeAccessReadonly = "readonly",
                TypeAccessWriteonly = "writeonly",
                TypeAccessNoEscape = "noescape",
                TypeAccessInvalidate = "invalidate",
                TypeAccessPreserve = "preserve",
            })[acls and acls.kind] or tostring(ty.access)
            return label .. " " .. M.type_name(ty.base)
        end
        if cls.kind == "THandle" then
            local ref = ty.ref
            local rcls = ref and pvm.classof(ref)
            if rcls and rcls.kind == "TypeRefGlobal" then return ref.type_name end
            if rcls and rcls.kind == "TypeRefPath" and ref.path then
                local parts = {}
                for i = 1, #(ref.path.parts or {}) do parts[i] = ref.path.parts[i].text end
                if #parts > 0 then return table.concat(parts, ".") end
            end
            return "handle"
        end
        if cls.kind == "TSlice" then return "slice(" .. M.type_name(ty.elem) .. ")" end
        if cls.kind == "TArray" then return "array(" .. M.type_name(ty.elem) .. ")" end
        if cls.kind == "TFunc" then return "func(...): " .. M.type_name(ty.result) end
        if cls.kind == "TClosure" then return "closure(...): " .. M.type_name(ty.result) end
        if cls.kind == "TNamed" then
            local ref = ty.ref
            if ref then
                local rcls = pvm.classof(ref)
                if rcls and rcls.kind == "TypeRefGlobal" then return ref.type_name end
                if rcls and rcls.kind == "TypeRefLocal" then return ref.sym and ref.sym.name or ref.sym end
                if rcls and rcls.kind == "TypeRefPath" and ref.path then
                    local parts = {}
                    for i = 1, #(ref.path.parts or {}) do parts[i] = ref.path.parts[i].text end
                    return table.concat(parts, ".")
                end
            end
        end
        return cls.kind
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
    ["MoonCore.BinAdd"] = "+", ["MoonCore.BinSub"] = "-", ["MoonCore.BinMul"] = "*",
    ["MoonCore.BinDiv"] = "/", ["MoonCore.BinRem"] = "%",
    ["MoonCore.BinBitAnd"] = "&", ["MoonCore.BinBitOr"] = "|", ["MoonCore.BinBitXor"] = "~",
    ["MoonCore.BinShl"] = "<<", ["MoonCore.BinLShr"] = ">>>", ["MoonCore.BinAShr"] = ">>",
    ["MoonCore.CmpEq"] = "==", ["MoonCore.CmpNe"] = "~=", ["MoonCore.CmpLt"] = "<",
    ["MoonCore.CmpLe"] = "<=", ["MoonCore.CmpGt"] = ">", ["MoonCore.CmpGe"] = ">=",
    ["MoonCore.LogicAnd"] = "and", ["MoonCore.LogicOr"] = "or",
    ["MoonCore.UnaryNot"] = "not", ["MoonCore.UnaryNeg"] = "-", ["MoonCore.UnaryBitNot"] = "~",
}

function M.op_symbol(op)
    if not op then return "?" end
    local s = tostring(op)
    if op_symbols[s] then return op_symbols[s] end
    -- Strip "MoonCore." prefix if present and retry
    local short = s:match("^MoonCore%.(.+)$")
    if short and op_symbols[short] then return op_symbols[short] end
    return s
end

-------------------------------------------------------------------------------
-- Scalar name formatting (for BackScalar values)
-------------------------------------------------------------------------------

function M.scalar_name(scalar)
    if not scalar then return "?" end
    local pvm = require("moonlift.pvm")
    local cls = pvm.classof(scalar)
    if cls and scalar_labels[cls.kind] then return scalar_labels[cls.kind] end
    return tostring(scalar)
end

-------------------------------------------------------------------------------
-- Access mode name formatting (for BackAccessMode values)
-------------------------------------------------------------------------------

function M.access_mode_name(mode)
    if not mode then return "?" end
    local pvm = require("moonlift.pvm")
    local cls = pvm.classof(mode)
    if not cls then return tostring(mode) end
    if cls.kind == "AccessModeLoad" then return "load" end
    if cls.kind == "AccessModeStore" then return "store" end
    if cls.kind == "AccessModeLoadStore" then return "load-store" end
    return cls.kind
end

-------------------------------------------------------------------------------
-- Re-exports
-------------------------------------------------------------------------------

M.Suggest = require("moonlift.error.suggest")
M.SpanResolvers = require("moonlift.error.span_resolvers")

-----------------------------------------------------------------------------
-- Resolve class from issue, with fallback to issue.kind
--
-- All explainers use this instead of raw pvm.classof() so they work with
-- both real ASDL nodes and mock issues (which have a .kind field).
-----------------------------------------------------------------------------

function M.resolve_class(issue)
    local pvm = require("moonlift.pvm")
    local cls = pvm.classof(issue)
    if cls then return cls end
    if issue and issue.kind then
        return { kind = issue.kind }
    end
    return nil
end

return M
