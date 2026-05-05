-- cimport.lua -- PVM scalar phase: CAst.TranslationUnit -> CTypeFact[], CLayoutFact[], CExternFunc[]
--
-- This phase takes a parsed C translation unit (plain Lua table with _variant fields)
-- and a module name, then produces C type facts, layout facts, and extern function
-- descriptors by querying the host platform through LuaJIT FFI.

local pvm = require("moonlift.pvm")
local ffi = require("ffi")
local M = {}

function M.Define(T)
    local CA = T.MoonCAst
    local MC = T.MoonC
    local Back = T.MoonBack

    --------------------------------------------------------------------------
    -- Platform-sensitive scalar resolution via ffi.sizeof
    --------------------------------------------------------------------------
    -- Maps C type names to MoonBack.BackScalar variants.
    -- "long" and "long long" have platform-dependent sizes.

    local cdef_name_to_scalar = {
        ["char"]              = Back.BackI8,
        ["signed char"]       = Back.BackI8,
        ["unsigned char"]     = Back.BackU8,
        ["short"]             = Back.BackI16,
        ["short int"]         = Back.BackI16,
        ["signed short"]      = Back.BackI16,
        ["signed short int"]  = Back.BackI16,
        ["unsigned short"]    = Back.BackU16,
        ["unsigned short int"] = Back.BackU16,
        ["int"]               = Back.BackI32,
        ["signed"]            = Back.BackI32,
        ["signed int"]        = Back.BackI32,
        ["unsigned"]          = Back.BackU32,
        ["unsigned int"]      = Back.BackU32,
        ["long"]              = nil,  -- resolved dynamically
        ["long int"]          = nil,
        ["signed long"]       = nil,
        ["signed long int"]   = nil,
        ["unsigned long"]     = nil,
        ["unsigned long int"] = nil,
        ["long long"]         = nil,  -- resolved dynamically
        ["long long int"]     = nil,
        ["signed long long"]  = nil,
        ["signed long long int"] = nil,
        ["unsigned long long"]   = nil,
        ["unsigned long long int"] = nil,
        ["float"]             = Back.BackF32,
        ["double"]            = Back.BackF64,
        ["long double"]       = Back.BackF64,
        ["_Bool"]             = Back.BackU8,
        ["bool"]              = Back.BackU8,
        ["void"]              = Back.BackVoid,
    }

    -- Resolve platform-dependent sizes for long and long long
    local long_scalar = nil
    local ulong_scalar = nil
    local longlong_scalar = nil
    local ulonglong_scalar = nil

    local function ensure_platform_scalars()
        if long_scalar ~= nil then
            return
        end
        local ok, sizeof_long = pcall(ffi.sizeof, "long")
        if ok then
            if sizeof_long == 8 then
                long_scalar = Back.BackI64
                ulong_scalar = Back.BackU64
            else
                long_scalar = Back.BackI32
                ulong_scalar = Back.BackU32
            end
        else
            long_scalar = Back.BackI64
            ulong_scalar = Back.BackU64
        end
        local ok2, sizeof_ll = pcall(ffi.sizeof, "long long")
        if ok2 then
            if sizeof_ll == 8 then
                longlong_scalar = Back.BackI64
                ulonglong_scalar = Back.BackU64
            else
                longlong_scalar = Back.BackI64
                ulonglong_scalar = Back.BackU64
            end
        else
            longlong_scalar = Back.BackI64
            ulonglong_scalar = Back.BackU64
        end
        -- Fill in dynamic entries
        cdef_name_to_scalar["long"] = long_scalar
        cdef_name_to_scalar["long int"] = long_scalar
        cdef_name_to_scalar["signed long"] = long_scalar
        cdef_name_to_scalar["signed long int"] = long_scalar
        cdef_name_to_scalar["unsigned long"] = ulong_scalar
        cdef_name_to_scalar["unsigned long int"] = ulong_scalar
        cdef_name_to_scalar["long long"] = longlong_scalar
        cdef_name_to_scalar["long long int"] = longlong_scalar
        cdef_name_to_scalar["signed long long"] = longlong_scalar
        cdef_name_to_scalar["signed long long int"] = longlong_scalar
        cdef_name_to_scalar["unsigned long long"] = ulonglong_scalar
        cdef_name_to_scalar["unsigned long long int"] = ulonglong_scalar
    end

    --------------------------------------------------------------------------
    -- BackScalar resolution
    --------------------------------------------------------------------------

    local function back_scalar_by_size(bytes, signed)
        if signed then
            if bytes <= 1 then return Back.BackI8
            elseif bytes <= 2 then return Back.BackI16
            elseif bytes <= 4 then return Back.BackI32
            else return Back.BackI64 end
        else
            if bytes <= 1 then return Back.BackU8
            elseif bytes <= 2 then return Back.BackU16
            elseif bytes <= 4 then return Back.BackU32
            else return Back.BackU64 end
        end
    end

    local function resolve_scalar(cdef_name)
        ensure_platform_scalars()
        local cached = cdef_name_to_scalar[cdef_name]
        if cached ~= nil then
            return cached, true
        end
        -- Try querying ffi.sizeof for the type name directly
        local ok, sz = pcall(ffi.sizeof, cdef_name)
        if ok then
            -- Determine signedness from the name
            local signed = true
            if cdef_name:find("^unsigned") then
                signed = false
            end
            return back_scalar_by_size(sz, signed), true
        end
        return nil, false
    end

    --------------------------------------------------------------------------
    -- C def string builder
    --------------------------------------------------------------------------

    local function is_simple_type_spec(spec)
        local tag = spec._variant or "unknown"
        if tag == "CTyVoid" or tag == "CTyChar" or tag == "CTyShort"
            or tag == "CTyInt" or tag == "CTyLong" or tag == "CTyLongLong"
            or tag == "CTyFloat" or tag == "CTyDouble" or tag == "CTyLongDouble"
            or tag == "CTySigned" or tag == "CTyUnsigned" or tag == "CTyBool" then
            return true
        end
        return false
    end

    local type_spec_to_cdef
    local declarator_to_cdef
    local field_decl_to_cdef
    local param_decl_to_cdef
    local expr_to_cdef
    local initializer_expr_to_cdef

    type_spec_to_cdef = function(spec, qualifiers)
        local qstr = ""
        for _, q in ipairs(qualifiers or {}) do
            local qt = q._variant
            if qt == "CQualConst" then qstr = qstr .. "const "
            elseif qt == "CQualVolatile" then qstr = qstr .. "volatile "
            elseif qt == "CQualRestrict" then qstr = qstr .. "__restrict "
            end
        end

        local tag = spec._variant
        if tag == "CTyVoid" then
            return qstr .. "void"
        elseif tag == "CTyChar" then
            return qstr .. "char"
        elseif tag == "CTyShort" then
            return qstr .. "short"
        elseif tag == "CTyInt" then
            return qstr .. "int"
        elseif tag == "CTyLong" then
            return qstr .. "long"
        elseif tag == "CTyLongLong" then
            return qstr .. "long long"
        elseif tag == "CTyFloat" then
            return qstr .. "float"
        elseif tag == "CTyDouble" then
            return qstr .. "double"
        elseif tag == "CTyLongDouble" then
            return qstr .. "long double"
        elseif tag == "CTySigned" then
            return qstr .. "signed"
        elseif tag == "CTyUnsigned" then
            return qstr .. "unsigned"
        elseif tag == "CTyBool" then
            return qstr .. "_Bool"
        elseif tag == "CTyNamed" then
            return qstr .. spec.name
        elseif tag == "CTyStructOrUnion" then
            local sk = spec.kind._variant
            local kind = (sk == "CStructKindStruct") and "struct" or "union"
            local name_part = spec.name or ""
            if spec.members then
                local fields_str = ""
                for i, field in ipairs(spec.members) do
                    local fdecl = field_decl_to_cdef(field)
                    if i > 1 then fields_str = fields_str .. "; " end
                    fields_str = fields_str .. fdecl
                end
                return qstr .. kind .. " " .. name_part .. " { " .. fields_str .. "; }"
            else
                return qstr .. kind .. " " .. name_part
            end
        elseif tag == "CTyEnum" then
            local name_part = spec.name or ""
            if spec.enumerators then
                local enum_body = ""
                for i, e in ipairs(spec.enumerators) do
                    if i > 1 then enum_body = enum_body .. ", " end
                    enum_body = enum_body .. e.name
                    if e.value then
                        enum_body = enum_body .. " = " .. initializer_expr_to_cdef(e.value)
                    end
                end
                return qstr .. "enum " .. name_part .. " { " .. enum_body .. " }"
            else
                return qstr .. "enum " .. name_part
            end
        elseif tag == "CTyComplex" then
            return qstr .. "_Complex"
        elseif tag == "CTyTypeof" then
            return qstr .. "typeof(" .. expr_to_cdef(spec.expr) .. ")"
        end
        return qstr .. "int"
    end

    local function pointer_quals_to_cdef(quals)
        local qs = ""
        for _, q in ipairs(quals or {}) do
            local qt = q._variant
            if qt == "CQualConst" then qs = qs .. "const "
            elseif qt == "CQualVolatile" then qs = qs .. "volatile "
            elseif qt == "CQualRestrict" then qs = qs .. "__restrict "
            end
        end
        return qs
    end

    local function params_to_cdef(params, variadic)
        local params_str = ""
        for i, p in ipairs(params or {}) do
            if i > 1 then params_str = params_str .. ", " end
            params_str = params_str .. param_decl_to_cdef(p)
        end
        if variadic then
            if #(params or {}) > 0 then params_str = params_str .. ", " end
            params_str = params_str .. "..."
        end
        if params_str == "" then params_str = "void" end
        return params_str
    end

    declarator_to_cdef = function(decl, spec_str)
        local inner = decl.name or ""
        local derived = decl.derived or {}
        for i, d in ipairs(derived) do
            local tag = d._variant
            local next_d = derived[i + 1]
            if tag == "CDerivedPointer" then
                local qs = pointer_quals_to_cdef(d.qualifiers)
                if next_d and (next_d._variant == "CDerivedFunction" or next_d._variant == "CDerivedArray") then
                    inner = "(" .. qs .. "*" .. inner .. ")"
                else
                    inner = qs .. "*" .. inner
                end
            elseif tag == "CDerivedArray" then
                inner = inner .. "[" .. (d.size and expr_to_cdef(d.size) or "") .. "]"
            elseif tag == "CDerivedFunction" then
                inner = inner .. "(" .. params_to_cdef(d.params, d.variadic) .. ")"
            end
        end
        if inner == "" then return spec_str end
        return spec_str .. " " .. inner
    end

    field_decl_to_cdef = function(field)
        local spec_str = type_spec_to_cdef(field.type_spec)
        local parts = {}
        for _, fd in ipairs(field.declarators) do
            if fd.declarator then
                local dstr = declarator_to_cdef(fd.declarator, spec_str)
                if fd.bit_width then
                    dstr = dstr .. " : " .. expr_to_cdef(fd.bit_width)
                end
                parts[#parts + 1] = dstr
            else
                local dstr = spec_str
                if fd.bit_width then
                    dstr = dstr .. " : " .. expr_to_cdef(fd.bit_width)
                end
                parts[#parts + 1] = dstr
            end
        end
        return table.concat(parts, ", ")
    end

    param_decl_to_cdef = function(param)
        local spec_str = type_spec_to_cdef(param.type_spec, param.qualifiers)
        if param.declarator then
            return declarator_to_cdef(param.declarator, spec_str)
        end
        return spec_str
    end

    expr_to_cdef = function(expr)
        if type(expr) ~= "table" then
            return tostring(expr)
        end
        local tag = expr._variant
        if tag == "CEIntLit" then
            return expr.raw
        elseif tag == "CEFloatLit" then
            return expr.raw
        elseif tag == "CECharLit" then
            return "'" .. expr.raw:gsub("'", "\\'") .. "'"
        elseif tag == "CEStrLit" then
            return '"' .. expr.raw:gsub('"', '\\"') .. '"'
        elseif tag == "CEBoolLit" then
            return expr.value and "1" or "0"
        elseif tag == "CEIdent" then
            return expr.name
        elseif tag == "CEParen" then
            return "(" .. expr_to_cdef(expr.expr) .. ")"
        elseif tag == "CEBinary" then
            local op_map = {
                CBinAdd = "+", CBinSub = "-", CBinMul = "*", CBinDiv = "/", CBinMod = "%",
                CBinShl = "<<", CBinShr = ">>",
                CBinLt = "<", CBinLe = "<=", CBinGt = ">", CBinGe = ">=",
                CBinEq = "==", CBinNe = "!=",
                CBinBitAnd = "&", CBinBitXor = "^", CBinBitOr = "|",
                CBinLogAnd = "&&", CBinLogOr = "||",
            }
            local op = op_map[expr.op._variant] or "?"
            return "(" .. expr_to_cdef(expr.left) .. " " .. op .. " " .. expr_to_cdef(expr.right) .. ")"
        elseif tag == "CEUnary" or tag == "CEPlus" then
            return "(+" .. expr_to_cdef(expr.operand) .. ")"
        elseif tag == "CEMinus" then
            return "(-" .. expr_to_cdef(expr.operand) .. ")"
        elseif tag == "CENot" then
            return "(!" .. expr_to_cdef(expr.operand) .. ")"
        elseif tag == "CEBitNot" then
            return "(~" .. expr_to_cdef(expr.operand) .. ")"
        elseif tag == "CESizeofExpr" then
            return "sizeof(" .. expr_to_cdef(expr.expr) .. ")"
        elseif tag == "CESizeofType" then
            local tn = expr.type_name
            local spec_str = type_spec_to_cdef(tn.type_spec)
            local ty = spec_str
            for _, d in ipairs(tn.derived or {}) do
                ty = derived_to_cdef(d, ty)
            end
            return "sizeof(" .. ty .. ")"
        elseif tag == "CECast" then
            local tn = expr.type_name
            local spec_str = type_spec_to_cdef(tn.type_spec)
            local ty = spec_str
            for _, d in ipairs(tn.derived or {}) do
                ty = derived_to_cdef(d, ty)
            end
            return "((" .. ty .. ")" .. expr_to_cdef(expr.expr) .. ")"
        end
        return "0"
    end

    initializer_expr_to_cdef = function(init)
        if init._variant == "CInitExpr" then
            return expr_to_cdef(init.expr)
        end
        return "0"
    end

    -- Build the cdef string to feed to ffi.cdef
    local function build_cdef_string(items)
        local cdef_parts = {}
        for _, item in ipairs(items) do
            local tag = item._variant
            if tag == "CATopDecl" then
                local decl = item.decl
                local spec_str = type_spec_to_cdef(decl.type_spec, decl.qualifiers)
                -- Check if typedef
                local is_typedef = false
                if decl.storage and decl.storage._variant == "CStorageTypedef" then
                    is_typedef = true
                end
                for _, decltor in ipairs(decl.declarators) do
                    local dstr = declarator_to_cdef(decltor, spec_str)
                    if is_typedef then
                        cdef_parts[#cdef_parts + 1] = "typedef " .. dstr .. ";"
                    elseif decl.storage and decl.storage._variant == "CStorageExtern" then
                        -- extern declaration (function or variable)
                        local has_func = false
                        for _, d in ipairs(decltor.derived or {}) do
                            if d._variant == "CDerivedFunction" then
                                has_func = true
                                break
                            end
                        end
                        if has_func then
                            cdef_parts[#cdef_parts + 1] = dstr .. ";"
                        else
                            cdef_parts[#cdef_parts + 1] = "extern " .. dstr .. ";"
                        end
                    else
                        cdef_parts[#cdef_parts + 1] = dstr .. ";"
                    end
                end
            elseif tag == "CATopFuncDef" then
                local func = item.func
                local spec_str = type_spec_to_cdef(func.type_spec, func.qualifiers)
                local decltor = func.declarator
                cdef_parts[#cdef_parts + 1] = declarator_to_cdef(decltor, spec_str) .. ";"
            end
        end
        return table.concat(cdef_parts, "\n")
    end

    --------------------------------------------------------------------------
    -- Type fact construction
    --------------------------------------------------------------------------

    -- Produce a CTypeId from module_name and spelling
    local function make_c_type_id(module_name, spelling)
        return {
            _variant = "CTypeId",
            module_name = module_name,
            spelling = spelling,
        }
    end

    -- Build a CTypeFact from a resolved type description
    local function make_c_type_fact(module_name, spelling, kind, complete, size, align)
        return {
            _variant = "CTypeFact",
            id = make_c_type_id(module_name, spelling),
            kind = kind,
            complete = complete,
            size = size,
            align = align,
        }
    end

    --------------------------------------------------------------------------
    -- Resolving type specifiers to CTypeFact
    --------------------------------------------------------------------------

    local function collect_spec_cdef_name(spec, qualifiers)
        -- Build a single cdef-style name from the type spec
        local parts = {}
        for _, q in ipairs(qualifiers or {}) do
            if q._variant == "CQualConst" then parts[#parts + 1] = "const" end
        end
        local tag = spec._variant
        if tag == "CTyVoid" then parts[#parts + 1] = "void"
        elseif tag == "CTyChar" then parts[#parts + 1] = "char"
        elseif tag == "CTyShort" then parts[#parts + 1] = "short"
        elseif tag == "CTyInt" then parts[#parts + 1] = "int"
        elseif tag == "CTyLong" then parts[#parts + 1] = "long"
        elseif tag == "CTyLongLong" then parts[#parts + 1] = "long long"
        elseif tag == "CTyFloat" then parts[#parts + 1] = "float"
        elseif tag == "CTyDouble" then parts[#parts + 1] = "double"
        elseif tag == "CTyLongDouble" then parts[#parts + 1] = "long double"
        elseif tag == "CTySigned" then parts[#parts + 1] = "signed"
        elseif tag == "CTyUnsigned" then parts[#parts + 1] = "unsigned"
        elseif tag == "CTyBool" then parts[#parts + 1] = "_Bool"
        elseif tag == "CTyNamed" then parts[#parts + 1] = spec.name
        elseif tag == "CTyStructOrUnion" then
            local sk = spec.kind._variant
            local kind = (sk == "CStructKindStruct") and "struct" or "union"
            parts[#parts + 1] = kind .. " " .. (spec.name or "")
        elseif tag == "CTyEnum" then
            parts[#parts + 1] = "enum " .. (spec.name or "")
        end
        return table.concat(parts, " ")
    end

    local function resolve_type_spec(spec, module_name, typedef_table)
        local tag = spec._variant

        -- Handle typedef references (CTyNamed)
        if tag == "CTyNamed" then
            local name = spec.name
            local lookup = typedef_table[name]
            if lookup then
                return lookup
            end
            -- Try resolving via ffi
            local cdef_name = name
            local back_scalar, ok = resolve_scalar(cdef_name)
            if ok then
                local kind = { _variant = "CScalar", scalar = back_scalar }
                return make_c_type_fact(module_name, name, kind, true, ffi.sizeof(cdef_name), ffi.alignof(cdef_name))
            end
            -- Unknown named type - treat as opaque
            return make_c_type_fact(module_name, name, { _variant = "COpaque" }, false, nil, nil)
        end

        -- Handle struct/union types
        if tag == "CTyStructOrUnion" then
            local sk = spec.kind._variant
            local kind_tag = (sk == "CStructKindStruct") and "CStruct" or "CUnion"
            local lookup_name = (sk == "CStructKindStruct") and ("struct " .. (spec.name or "")) or ("union " .. (spec.name or ""))
            local kind = { _variant = kind_tag }

            if spec.members then
                -- Complete definition
                local cdef_name = lookup_name
                local ok, sz = pcall(ffi.sizeof, cdef_name)
                local ok2, al = pcall(ffi.alignof, cdef_name)
                if ok then
                    return make_c_type_fact(module_name, lookup_name, kind, true, sz, ok2 and al or 1)
                end
                -- Fallback: estimate from known types
                return make_c_type_fact(module_name, lookup_name, kind, true, nil, nil)
            else
                -- Forward declaration - opaque
                return make_c_type_fact(module_name, lookup_name, kind, false, nil, nil)
            end
        end

        -- Handle enum types
        if tag == "CTyEnum" then
            local lookup_name = "enum " .. (spec.name or "")
            if spec.enumerators then
                local back_scalar, ok = resolve_scalar("int")
                if not ok then back_scalar = Back.BackI32 end
                local kind = { _variant = "CEnum", scalar = back_scalar }
                local sz = 4
                local ok_sz, ffi_sz = pcall(ffi.sizeof, "int")
                if ok_sz then sz = ffi_sz end
                local al = sz
                return make_c_type_fact(module_name, lookup_name, kind, true, sz, al)
            else
                return make_c_type_fact(module_name, lookup_name, { _variant = "CEnum", scalar = Back.BackI32 }, false, nil, nil)
            end
        end

        -- Handle void
        if tag == "CTyVoid" then
            return make_c_type_fact(module_name, "void", { _variant = "CVoid" }, true, 1, 1)
        end

        -- Handle scalar types: char, short, int, long, float, double, etc.
        local cdef_name = collect_spec_cdef_name(spec)
        local back_scalar, ok = resolve_scalar(cdef_name)
        if ok and back_scalar._variant ~= "BackVoid" then
            local kind = { _variant = "CScalar", scalar = back_scalar }
            local sz = 1
            local al = 1
            local ok_sz, ffi_sz = pcall(ffi.sizeof, cdef_name)
            if ok_sz then sz = ffi_sz end
            local ok_al, ffi_al = pcall(ffi.alignof, cdef_name)
            if ok_al then al = ffi_al end
            return make_c_type_fact(module_name, cdef_name, kind, true, sz, al)
        end

        -- Fallback: try int
        local kind = { _variant = "CScalar", scalar = Back.BackI32 }
        return make_c_type_fact(module_name, cdef_name, kind, true, 4, 4)
    end

    --------------------------------------------------------------------------
    -- Layout fact construction via FFI
    --------------------------------------------------------------------------

    local function build_layout_for_type(module_name, type_spelling, ffi_lookup_name, members, type_facts, typedef_table)
        local fields = {}
        local ok, ffi_fields = pcall(function()
            local ct = ffi.typeof(ffi_lookup_name)
            local results = {}
            for _, member in ipairs(members) do
                for _, fd in ipairs(member.declarators) do
                    local fd_name = fd.declarator and fd.declarator.name
                    if fd_name then
                        local offset = ffi.offsetof(ct, fd_name)
                        local field_type_fact = resolve_type_spec(member.type_spec, module_name, typedef_table)
                        local fsz = field_type_fact.size or 4
                        local fal = field_type_fact.align or 1
                        results[#results + 1] = {
                            _variant = "CFieldLayout",
                            owner = make_c_type_id(module_name, type_spelling),
                            name = fd_name,
                            type = field_type_fact.id,
                            offset = tonumber(offset),
                            size = fsz,
                            align = fal,
                            bit_offset = nil,
                            bit_width = fd.bit_width and nil or nil,
                        }
                    end
                end
            end
            return results
        end)
        if ok then fields = ffi_fields end
        local sz = nil
        local al = nil
        local ok_sz, ffi_sz = pcall(ffi.sizeof, ffi_lookup_name)
        if ok_sz then sz = tonumber(ffi_sz) end
        local ok_al, ffi_al = pcall(ffi.alignof, ffi_lookup_name)
        if ok_al then al = tonumber(ffi_al) end

        return {
            _variant = "CLayoutFact",
            type = make_c_type_id(module_name, type_spelling),
            size = sz or 0,
            align = al or 1,
            fields = fields,
        }
    end

    --------------------------------------------------------------------------
    -- Function signature building
    --------------------------------------------------------------------------

    local function build_func_sig_id(func_proto_text)
        return {
            _variant = "CFuncSigId",
            text = func_proto_text,
        }
    end

    local function param_types_from_proto(params, module_name, typedef_table)
        local types = {}
        for _, p in ipairs(params) do
            local fact = resolve_type_spec(p.type_spec, module_name, typedef_table)
            types[#types + 1] = fact.id
        end
        return types
    end

    --------------------------------------------------------------------------
    -- Main entry point
    --------------------------------------------------------------------------

    function M.cimport(tu_items, module_name)
        ensure_platform_scalars()

        local type_facts = {}
        local layout_facts = {}
        local extern_funcs = {}
        local typedef_table = {}   -- name -> CTypeFact for typedefs
        local type_fact_cache = {} -- spelling -> CTypeFact (dedup)

        -- Phase 1: collect struct/union members for layout queries
        local struct_defs = {}  -- {name, kind, members}[]

        -- Phase 2: build cdef string from all declarations
        local cdef_str = build_cdef_string(tu_items)

        -- Phase 3: call ffi.cdef to register types
        if #cdef_str > 0 then
            local ok, err = pcall(ffi.cdef, cdef_str)
            if not ok then
                -- Emit diagnostic, continue with partial types
                io.stderr:write(string.format("ffi.cdef warning (%s): %s\n", module_name, tostring(err)))
            end
        end

        -- Phase 4: process each top-level item for type facts and layouts
        local function get_or_create_type_fact(spec)
            local cdef_name = collect_spec_cdef_name(spec)
            if type_fact_cache[cdef_name] then
                return type_fact_cache[cdef_name]
            end
            local fact = resolve_type_spec(spec, module_name, typedef_table)
            type_fact_cache[cdef_name] = fact
            return fact
        end

        for _, item in ipairs(tu_items) do
            local tag = item._variant

            if tag == "CATopDecl" then
                local decl = item.decl
                local spec_fact = get_or_create_type_fact(decl.type_spec)

                -- Check for typedef
                if decl.storage and decl.storage._variant == "CStorageTypedef" then
                    for _, decltor in ipairs(decl.declarators) do
                        local name = decltor.name
                        if name then
                            -- Build the type fact for the typedef
                            local base_fact = spec_fact
                            local typing = base_fact.kind
                            -- Apply pointer/array derived types
                            for _, d in ipairs(decltor.derived or {}) do
                                local dt = d._variant
                                if dt == "CDerivedPointer" then
                                    typing = { _variant = "CPointer", pointee = base_fact.id }
                                elseif dt == "CDerivedFunction" then
                                    local sig_text = "typedef_" .. name
                                    local sig_id = build_func_sig_id(sig_text)
                                    typing = { _variant = "CFuncPtr", sig = sig_id }
                                end
                            end
                            local complete = base_fact.complete
                            local size = base_fact.size
                            local align = base_fact.align
                            if decl.type_spec._variant == "CTyStructOrUnion" and decl.type_spec.members and #(decltor.derived or {}) == 0 then
                                local ok_sz, ffi_sz = pcall(ffi.sizeof, name)
                                local ok_al, ffi_al = pcall(ffi.alignof, name)
                                if ok_sz then size = tonumber(ffi_sz); complete = true end
                                if ok_al then align = tonumber(ffi_al) end
                            end
                            local fact = make_c_type_fact(module_name, name, typing, complete, size, align)
                            type_facts[#type_facts + 1] = fact
                            typedef_table[name] = fact
                            type_fact_cache[name] = fact

                            -- Check for extern function declarations
                            -- (extern storage + function derived type)
                        end
                    end
                else
                    -- Non-typedef declarations
                    for _, decltor in ipairs(decl.declarators) do
                        local name = decltor.name
                        if not name then break end
                        local is_extern_func = false
                        local params = {}
                        local variadic = false
                        local result_fact = spec_fact

                        for _, d in ipairs(decltor.derived or {}) do
                            if d._variant == "CDerivedFunction" then
                                is_extern_func = true
                                params = d.params
                                variadic = d.variadic
                            end
                        end

                        if is_extern_func then
                            -- Build function signature
                            local param_ids = param_types_from_proto(params, module_name, typedef_table)
                            local sig_text = name .. "(" .. table.concat(
                                (function()
                                    local strs = {}
                                    for _, pid in ipairs(param_ids) do
                                        strs[#strs + 1] = pid.spelling
                                    end
                                    return strs
                                end)(), ","
                            ) .. ")->" .. result_fact.id.spelling

                            local sig_id = build_func_sig_id(sig_text)

                            -- Add result type fact
                            local result_type_fact = result_fact

                            -- Create extern func entry
                            local moon_name = name
                            local symbol = name
                            library = decl.storage and (decl.storage._variant == "CStorageExtern") and nil -- could be extended with library info

                            extern_funcs[#extern_funcs + 1] = {
                                _variant = "CExternFunc",
                                moon_name = moon_name,
                                symbol = symbol,
                                sig = sig_id,
                                library = nil,
                            }
                        else
                            -- Regular variable declaration
                            local cdef_lookup = name
                            local kind = { _variant = "CScalar", scalar = Back.BackI32 }
                            -- Build through derived types
                            local base_kind = spec_fact.kind
                            local current_kind = base_kind
                            for _, d in ipairs(decltor.derived or {}) do
                                if d._variant == "CDerivedPointer" then
                                    current_kind = { _variant = "CPointer", pointee = spec_fact.id }
                                elseif d._variant == "CDerivedArray" then
                                    local count = 0
                                    if d.size then
                                        -- Try to evaluate constant expression
                                        count = 0
                                    end
                                    current_kind = { _variant = "CArray", elem = spec_fact.id, count = count }
                                end
                            end
                            local fact = make_c_type_fact(module_name, cdef_lookup, current_kind, true, nil, nil)
                            type_facts[#type_facts + 1] = fact
                        end
                    end
                end

                -- Emit the spec type fact itself if it is useful
                local already_have = false
                for _, tf in ipairs(type_facts) do
                    if tf.id.spelling == spec_fact.id.spelling then
                        already_have = true
                        break
                    end
                end
                if not already_have then
                    type_facts[#type_facts + 1] = spec_fact
                end

            elseif tag == "CATopFuncDef" then
                local func = item.func
                local name = func.declarator.name or "anon"
                local result_fact = get_or_create_type_fact(func.type_spec)

                -- Collect params
                local params = {}
                local variadic = false
                for _, d in ipairs(func.declarator.derived or {}) do
                    if d._variant == "CDerivedFunction" then
                        params = d.params
                        variadic = d.variadic
                    end
                end

                -- Build function name
                local param_ids = param_types_from_proto(params, module_name, typedef_table)
                local sig_text = name .. "(" .. table.concat(
                    (function()
                        local strs = {}
                        for _, pid in ipairs(param_ids) do
                            strs[#strs + 1] = pid.spelling
                        end
                        return strs
                    end)(), ","
                ) .. ")->" .. result_fact.id.spelling
                local sig_id = build_func_sig_id(sig_text)

                if func.storage and func.storage._variant == "CStorageExtern" then
                    extern_funcs[#extern_funcs + 1] = {
                        _variant = "CExternFunc",
                        moon_name = name,
                        symbol = name,
                        sig = sig_id,
                        library = nil,
                    }
                end
            end
        end

        -- Phase 5: build layout facts from struct/union definitions
        for _, item in ipairs(tu_items) do
            if item._variant == "CATopDecl" then
                local spec = item.decl.type_spec
                if spec._variant == "CTyStructOrUnion" and spec.members then
                    local sname = spec.name
                    if sname then
                        layout_facts[#layout_facts + 1] = build_layout_for_type(module_name, "struct " .. sname, "struct " .. sname, spec.members, type_facts, typedef_table)
                    end
                    if item.decl.storage and item.decl.storage._variant == "CStorageTypedef" then
                        for _, decltor in ipairs(item.decl.declarators or {}) do
                            if decltor.name and #(decltor.derived or {}) == 0 then
                                layout_facts[#layout_facts + 1] = build_layout_for_type(module_name, decltor.name, decltor.name, spec.members, type_facts, typedef_table)
                            end
                        end
                    end
                end
            end
        end

        return type_facts, layout_facts, extern_funcs
    end

    return { cimport = M.cimport }
end

return M
