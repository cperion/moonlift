-- lower_c.lua -- PVM scalar phase: CAst.TranslationUnit + CTypeFact[] + CLayoutFact[]
--                + CExternFunc[] -> MoonTree.Module
--
-- Converts a C AST into MoonTree IR, lowering all C constructs to their
-- MoonTree equivalents. All output uses proper MoonTree ASDL constructors
-- so the MoonTree passes cleanly through the typecheck/lower/validate pipeline.

local pvm = require("moonlift.pvm")
local M = {}

function M.Define(T)
    local CA = T.MoonCAst
    local MC = T.MoonC
    local Tr = T.MoonTree
    local Ty = T.MoonType
    local C = T.MoonCore
    local Bind = T.MoonBind
    local Sem = T.MoonSem
    local Host = T.MoonHost

    --------------------------------------------------------------------------
    -- Helpers: bindings, names
    --------------------------------------------------------------------------
    local function make_binding(name, class)
        return Bind.Binding(C.Id(name), name, Ty.TScalar(C.ScalarI32), class)
    end

    local function local_value_binding(name)
        return make_binding(name, Bind.BindingClassLocalValue)
    end

    local function local_cell_binding(name)
        return make_binding(name, Bind.BindingClassLocalCell)
    end

    local function arg_binding(name, index)
        return make_binding(name, Bind.BindingClassArg(index))
    end

    --------------------------------------------------------------------------
    -- Lowering context
    --------------------------------------------------------------------------
    local function new_context(module_name, ctype_facts, layout_facts, extern_funcs)
        local ctypes = {}
        for _, f in ipairs(ctype_facts or {}) do
            ctypes[f.id.module_name .. ":" .. f.id.spelling] = f
            ctypes[f.id.spelling] = f
        end
        local layouts = {}
        for _, l in ipairs(layout_facts or {}) do
            layouts[l.type.module_name .. ":" .. l.type.spelling] = l
            layouts[l.type.spelling] = l
        end
        local extern_table = {}
        for _, ef in ipairs(extern_funcs or {}) do
            extern_table[ef.moon_name] = ef
        end
        return {
            module_name = module_name or "c",
            ctypes = ctypes,
            layouts = layouts,
            func_table = {},
            extern_table = extern_table,
            data_items = {},
            data_counter = 0,
            string_cache = {},
            label_counter = 0,
            region_counter = 0,
            temp_counter = 0,
            func_name = nil,
            func_params = {},
            func_result_ty = nil,
            address_taken = nil,
            locals = {},
            loop_carried_vars = nil,
            break_target = nil,
            continue_target = nil,
            switch_cases = nil,
            switch_default = nil,
            internal_names = {},
        }
    end

    local function fresh_label(ctx, prefix)
        ctx.internal_names[prefix] = (ctx.internal_names[prefix] or 0) + 1
        return Tr.BlockLabel(prefix .. "_" .. ctx.internal_names[prefix])
    end

    local function fresh_region_id(ctx)
        ctx.region_counter = ctx.region_counter + 1
        return "region_" .. ctx.region_counter
    end

    local function fresh_temp_name(ctx, prefix)
        ctx.temp_counter = ctx.temp_counter + 1
        return prefix .. "_" .. ctx.temp_counter
    end

    --------------------------------------------------------------------------
    -- C type → MoonType.Type conversion
    --------------------------------------------------------------------------
    local function back_to_core_scalar(b)
        local tag = b._variant
        if tag == "BackVoid" then return C.ScalarVoid
        elseif tag == "BackBool" then return C.ScalarBool
        elseif tag == "BackI8" then return C.ScalarI8
        elseif tag == "BackI16" then return C.ScalarI16
        elseif tag == "BackI32" then return C.ScalarI32
        elseif tag == "BackI64" then return C.ScalarI64
        elseif tag == "BackU8" then return C.ScalarU8
        elseif tag == "BackU16" then return C.ScalarU16
        elseif tag == "BackU32" then return C.ScalarU32
        elseif tag == "BackU64" then return C.ScalarU64
        elseif tag == "BackF32" then return C.ScalarF32
        elseif tag == "BackF64" then return C.ScalarF64
        elseif tag == "BackPtr" then return C.ScalarRawPtr
        elseif tag == "BackIndex" then return C.ScalarIndex
        end
        return C.ScalarI32
    end

    local function c_kind_to_moon_type(kind, ctx)
        local tag = kind._variant
        if tag == "CVoid" then
            return Ty.TScalar(C.ScalarVoid)
        elseif tag == "CScalar" then
            return Ty.TScalar(back_to_core_scalar(kind.scalar))
        elseif tag == "CEnum" then
            return Ty.TScalar(back_to_core_scalar(kind.scalar))
        elseif tag == "CPointer" then
            local pointee_id = kind.pointee
            local pointee_fact = ctx.ctypes[pointee_id.module_name .. ":" .. pointee_id.spelling]
                or ctx.ctypes[pointee_id.spelling]
            local elem_ty
            if pointee_fact then
                if pointee_id.spelling == "void" or pointee_id.spelling == "char" then
                    elem_ty = Ty.TScalar(C.ScalarU8)
                else
                    elem_ty = c_kind_to_moon_type(pointee_fact.kind, ctx)
                end
            else
                elem_ty = Ty.TScalar(C.ScalarU8)
            end
            return Ty.TPtr(elem_ty)
        elseif tag == "CArray" then
            local elem_fact = ctx.ctypes[kind.elem.module_name .. ":" .. kind.elem.spelling]
                or ctx.ctypes[kind.elem.spelling]
            local elem_ty = elem_fact and c_kind_to_moon_type(elem_fact.kind, ctx)
                or Ty.TScalar(C.ScalarI32)
            return Ty.TPtr(elem_ty)
        elseif tag == "CStruct" or tag == "CUnion" then
            return Ty.TScalar(C.ScalarRawPtr)
        elseif tag == "COpaque" then
            return Ty.TScalar(C.ScalarRawPtr)
        elseif tag == "CFuncPtr" then
            return Ty.TCFuncPtr(kind.sig)
        end
        return Ty.TScalar(C.ScalarI32)
    end

    local function spec_to_name(spec)
        local tag = spec._variant
        if tag == "CTyVoid" then return "void"
        elseif tag == "CTyChar" then return "char"
        elseif tag == "CTyShort" then return "short"
        elseif tag == "CTyInt" then return "int"
        elseif tag == "CTyLong" then return "long"
        elseif tag == "CTyLongLong" then return "long long"
        elseif tag == "CTyFloat" then return "float"
        elseif tag == "CTyDouble" then return "double"
        elseif tag == "CTyBool" then return "_Bool"
        elseif tag == "CTyNamed" then return spec.name
        elseif tag == "CTyUnsigned" then return "unsigned int"
        elseif tag == "CTySigned" then return "int"
        elseif tag == "CTyStructOrUnion" then
            local kind = spec.kind and spec.kind._variant == "CStructKindUnion" and "union" or "struct"
            return spec.name and (kind .. " " .. spec.name) or kind
        elseif tag == "CTyEnum" then return spec.name or "enum"
        else return "int"
        end
    end

    local function c_type_spec_to_moon_type(spec, ctx)
        local name = spec_to_name(spec)
        local fact = ctx.ctypes[name]
        if fact then return c_kind_to_moon_type(fact.kind, ctx) end
        if spec._variant == "CTyStructOrUnion" and not spec.name and spec.members then
            return Ty.TScalar(C.ScalarRawPtr)
        end
        local tag = spec._variant
        if tag == "CTyVoid" then return Ty.TScalar(C.ScalarVoid)
        elseif tag == "CTyChar" then return Ty.TScalar(C.ScalarI8)
        elseif tag == "CTyInt" then return Ty.TScalar(C.ScalarI32)
        elseif tag == "CTyFloat" then return Ty.TScalar(C.ScalarF32)
        elseif tag == "CTyDouble" then return Ty.TScalar(C.ScalarF64)
        elseif tag == "CTyShort" then return Ty.TScalar(C.ScalarI16)
        elseif tag == "CTyLong" then return Ty.TScalar(C.ScalarI64)
        elseif tag == "CTyLongLong" then return Ty.TScalar(C.ScalarI64)
        elseif tag == "CTySigned" then return Ty.TScalar(C.ScalarI32)
        elseif tag == "CTyUnsigned" then return Ty.TScalar(C.ScalarU32)
        elseif tag == "CTyBool" then return Ty.TScalar(C.ScalarBool)
        elseif tag == "CTyNamed" then return Ty.TScalar(C.ScalarI32)
        end
        return Ty.TScalar(C.ScalarI32)
    end

    -- Apply declarator-derived types (pointer, array) to a base MoonType.
    -- Stops at CDerivedFunction (the function itself, not part of the return type).
    local function wrap_decl_type(base_ty, decltor, ctx)
        local ty = base_ty
        for _, d in ipairs(decltor.derived or {}) do
            if d._variant == "CDerivedFunction" then
                break
            elseif d._variant == "CDerivedPointer" then
                ty = Ty.TPtr(ty)
            elseif d._variant == "CDerivedArray" then
                ty = Ty.TPtr(ty)
            end
        end
        return ty
    end

    local function c_param_type(param, ctx)
        local base = c_type_spec_to_moon_type(param.type_spec, ctx)
        if param.declarator then
            return wrap_decl_type(base, param.declarator, ctx)
        end
        return base
    end

    local function c_type_id_for_spec(spec, ctx)
        local name = spec_to_name(spec)
        local fact = ctx.ctypes[name]
        if fact then return fact.id end
        return MC.CTypeId(ctx.module_name, name)
    end

    local function c_desc_from_spec_decl(spec, decltor, ctx)
        local id = c_type_id_for_spec(spec, ctx)
        local desc = { tag = "type", id = id }
        for _, d in ipairs((decltor and decltor.derived) or {}) do
            if d._variant == "CDerivedPointer" or d._variant == "CDerivedArray" then
                desc = { tag = "ptr", pointee = desc, id = nil }
            elseif d._variant == "CDerivedFunction" then
                break
            end
        end
        return desc
    end

    local function c_desc_to_moon_type(desc, ctx)
        if not desc then return Ty.TScalar(C.ScalarI32) end
        if desc.tag == "ptr" then return Ty.TPtr(c_desc_to_moon_type(desc.pointee, ctx)) end
        local id = desc.id
        local fact = id and (ctx.ctypes[id.module_name .. ":" .. id.spelling] or ctx.ctypes[id.spelling])
        if fact then return c_kind_to_moon_type(fact.kind, ctx) end
        return Ty.TScalar(C.ScalarI32)
    end

    local function field_layout_for(owner_desc, field_name, ctx)
        if not owner_desc or owner_desc.tag ~= "type" or not owner_desc.id then return nil end
        local id = owner_desc.id
        local layout = ctx.layouts[id.module_name .. ":" .. id.spelling] or ctx.layouts[id.spelling]
        if not layout then return nil end
        for _, f in ipairs(layout.fields or {}) do
            if f.name == field_name then return f end
        end
        return nil
    end

    local function host_rep_for_type(ty)
        if pvm.classof(ty) == Ty.TScalar then return Host.HostRepScalar(ty.scalar) end
        if pvm.classof(ty) == Ty.TPtr then return Host.HostRepPtr(ty.elem) end
        return Host.HostRepOpaque("c-field")
    end

    local function field_ref_for(owner_desc, field_name, ctx)
        local fl = field_layout_for(owner_desc, field_name, ctx)
        if not fl then return nil end
        local ffact = ctx.ctypes[fl.type.module_name .. ":" .. fl.type.spelling] or ctx.ctypes[fl.type.spelling]
        local fty = ffact and c_kind_to_moon_type(ffact.kind, ctx) or Ty.TScalar(C.ScalarI32)
        return Sem.FieldByOffset(field_name, fl.offset, fty, host_rep_for_type(fty)), { tag = "type", id = fl.type }
    end

    local lit_int  -- forward declaration (used by c_cond_to_bool)

    -- Wrap a C condition expression for Moonlift StmtIf (expects Bool).
    -- C comparisons (ExprCompare) already produce Bool, use as-is.
    -- Integer expressions need cond != 0 to produce Bool.
    local function c_cond_to_bool(moon_expr)
        local cls = pvm.classof(moon_expr)
        if cls == Tr.ExprCompare or cls == Tr.ExprNot then
            return moon_expr
        end
        return Tr.ExprCompare(Tr.ExprSurface, C.CmpNe, moon_expr, lit_int("0"))
    end

    local function c_func_param_types(c_func, ctx)
        local params = {}
        for _, d in ipairs(c_func.declarator.derived or {}) do
            if d._variant == "CDerivedFunction" then
                for i, p in ipairs(d.params) do
                    local pname = p.declarator and p.declarator.name or ("p" .. i)
                    params[#params + 1] = Ty.Param(pname, c_param_type(p, ctx))
                end
                if d.variadic then
                    params[#params + 1] = Ty.Param("__va", Ty.TScalar(C.ScalarRawPtr))
                end
            end
        end
        return params
    end

    --------------------------------------------------------------------------
    -- Usual arithmetic conversions
    --------------------------------------------------------------------------
    local function usual_arithmetic_conversion(ty_a, ty_b)
        if not ty_a or not ty_b then return nil end
        if ty_a == ty_b then return ty_a end
        return ty_b  -- simplified: prefer RHS type
    end

    local function needs_implicit_cast(src_ty, dst_ty, ctx)
        if not src_ty or not dst_ty then return false end
        return src_ty ~= dst_ty
    end

    --------------------------------------------------------------------------
    -- Data items (string literal deduplication)
    --------------------------------------------------------------------------
    local function make_data_item(bytes, ctx)
        local cached = ctx.string_cache[bytes]
        if cached then return cached end
        local id_text = "d" .. ctx.data_counter
        ctx.data_counter = ctx.data_counter + 1
        local data_id = C.DataId(id_text)
        local item_data = Tr.DataItem(data_id, #bytes, 1, bytes)
        ctx.data_items[id_text] = item_data
        local ref_expr = Tr.ExprLit(Tr.ExprSurface, C.LitString(bytes))
        ctx.string_cache[bytes] = ref_expr
        return ref_expr
    end

    --------------------------------------------------------------------------
    -- Expression helpers
    --------------------------------------------------------------------------
    function lit_int(raw)
        return Tr.ExprLit(Tr.ExprSurface, C.LitInt(raw))
    end

    local function lit_float(raw)
        return Tr.ExprLit(Tr.ExprSurface, C.LitFloat(raw))
    end

    local function lit_bool(val)
        return Tr.ExprLit(Tr.ExprSurface, C.LitBool(val))
    end

    local function lit_nil()
        return Tr.ExprLit(Tr.ExprSurface, C.LitNil)
    end

    local function c_expr_desc(c_expr, ctx)
        if type(c_expr) ~= "table" then return nil end
        local tag = c_expr._variant
        if tag == "CEIdent" then
            local l = ctx.locals[c_expr.name]
            return l and l.c_desc or nil
        elseif tag == "CEParen" then
            return c_expr_desc(c_expr.expr, ctx)
        elseif tag == "CEDeref" then
            local d = c_expr_desc(c_expr.operand, ctx)
            return d and d.tag == "ptr" and d.pointee or nil
        elseif tag == "CEAddrOf" then
            local d = c_expr_desc(c_expr.operand, ctx)
            return d and { tag = "ptr", pointee = d } or nil
        elseif tag == "CESubscript" then
            local d = c_expr_desc(c_expr.base, ctx)
            return d and d.tag == "ptr" and d.pointee or nil
        elseif tag == "CEArrow" then
            local d = c_expr_desc(c_expr.base, ctx)
            local owner = d and d.tag == "ptr" and d.pointee or nil
            local _, fd = field_ref_for(owner, c_expr.field, ctx)
            return fd
        elseif tag == "CEDot" then
            local owner = c_expr_desc(c_expr.base, ctx)
            local _, fd = field_ref_for(owner, c_expr.field, ctx)
            return fd
        end
        return nil
    end

    --------------------------------------------------------------------------
    -- Address-of analysis
    --------------------------------------------------------------------------
    local function collect_func_addresses(expr, out)
        local tag = expr._variant
        if tag == "CEAddrOf" and expr.operand then
            local op = expr.operand
            if op._variant == "CEIdent" then
                out[op.name] = true
            elseif op._variant == "CESubscript" then
                collect_func_addresses(op.base, out)
            elseif op._variant == "CEDot" then
                collect_func_addresses(op.base, out)
            elseif op._variant == "CEArrow" then
                collect_func_addresses(op.base, out)
            end
            return
        end
        -- Recurse into sub-expressions
        local kids = {
            CEIdent = {}, CEParen = {"expr"}, CEUnaryOp = {"operand"},
            CEBinary = {"left", "right"}, CEAssign = {"left", "right"},
            CETernary = {"cond", "then_expr", "else_expr"},
            CECall = {"callee"}, CEPreInc = {"operand"}, CEPreDec = {"operand"},
            CEPostInc = {"operand"}, CEPostDec = {"operand"},
            CECast = {"expr"}, CEComma = {"left", "right"},
            CESubscript = {"base", "index"}, CEDot = {"base"}, CEArrow = {"base"},
            CEDeref = {"operand"}, CEAddrOf = {"operand"},
            CEPlus = {"operand"}, CEMinus = {"operand"},
            CENot = {"operand"}, CEBitNot = {"operand"},
            CESizeofExpr = {"expr"}, CESizeofType = {},
            CECompoundLit = {}, CEStmtExpr = {},
        }
        local fields = kids[tag]
        if not fields then
            -- Recursively walk all fields
            for _, v in pairs(expr) do
                if type(v) == "table" and v._variant then
                    collect_func_addresses(v, out)
                elseif type(v) == "table" then
                    for _, item in ipairs(v) do
                        if type(item) == "table" and item._variant then
                            collect_func_addresses(item, out)
                        end
                    end
                end
            end
            return
        end
        for _, f in ipairs(fields) do
            local child = expr[f]
            if child and child._variant then
                collect_func_addresses(child, out)
            end
        end
    end

    local function collect_stmt_addresses(stmt, out)
        local tag = stmt._variant
        if tag == "CSLabeled" then
            collect_stmt_addresses(stmt.stmt, out)
        elseif tag == "CSCase" then
            collect_stmt_addresses(stmt.stmt, out)
        elseif tag == "CSDefault" then
            collect_stmt_addresses(stmt.stmt, out)
        elseif tag == "CSExpr" and stmt.expr then
            collect_func_addresses(stmt.expr, out)
        elseif tag == "CSCompound" then
            for _, bi in ipairs(stmt.items or {}) do
                if bi._variant == "CBlockDecl" then
                    for _, d in ipairs(bi.decl.declarators or {}) do
                        if d.initializer then
                            collect_func_addresses(d.initializer.expr or d.initializer, out)
                        end
                    end
                elseif bi._variant == "CBlockStmt" then
                    collect_stmt_addresses(bi.stmt, out)
                end
            end
        elseif tag == "CSIf" then
            collect_func_addresses(stmt.cond, out)
            collect_stmt_addresses(stmt.then_stmt, out)
            if stmt.else_stmt then collect_stmt_addresses(stmt.else_stmt, out) end
        elseif tag == "CSSwitch" then
            collect_func_addresses(stmt.cond, out)
            collect_stmt_addresses(stmt.body, out)
        elseif tag == "CSWhile" then
            collect_func_addresses(stmt.cond, out)
            collect_stmt_addresses(stmt.body, out)
        elseif tag == "CSDoWhile" then
            collect_stmt_addresses(stmt.body, out)
            collect_func_addresses(stmt.cond, out)
        elseif tag == "CSFor" then
            if stmt.init then collect_stmt_addresses(stmt.init, out) end
            if stmt.cond then collect_func_addresses(stmt.cond, out) end
            if stmt.incr then collect_func_addresses(stmt.incr, out) end
            collect_stmt_addresses(stmt.body, out)
        elseif tag == "CSReturn" and stmt.expr then
            collect_func_addresses(stmt.expr, out)
        end
    end

    --------------------------------------------------------------------------
    -- Loop analysis: write detection and variable classification
    --------------------------------------------------------------------------

    -- Collect written variable names from a C expression (LHS of =, ++, --, &)
    local function analyze_c_expr_writes(c_expr, out)
        if not c_expr or type(c_expr) ~= "table" then return end
        local tag = c_expr._variant
        -- Assignment LHS = written
        if tag == "CEAssign" then
            local lhs = c_expr.left
            if lhs and lhs._variant == "CEIdent" then
                out.written[lhs.name] = true
            end
            -- Recurse into RHS for nested assignments/comma
            if c_expr.right then analyze_c_expr_writes(c_expr.right, out) end
            return
        end
        -- Pre/post inc/dec = written
        if tag == "CEPreInc" or tag == "CEPreDec" or tag == "CEPostInc" or tag == "CEPostDec" then
            local op = c_expr.operand
            if op and op._variant == "CEIdent" then
                out.written[op.name] = true
            end
            return
        end
        -- Address-of = written (taking address implies potential mutation)
        if tag == "CEAddrOf" then
            local op = c_expr.operand
            if op and op._variant == "CEIdent" then
                out.written[op.name] = true
            end
            return
        end
        -- StmtExpr: walk items and result
        if tag == "CEStmtExpr" then
            for _, bi in ipairs(c_expr.items or {}) do
                if bi._variant == "CBlockStmt" then
                    analyze_c_stmt_writes(bi.stmt, out)
                end
            end
            if c_expr.result then analyze_c_expr_writes(c_expr.result, out) end
            return
        end
        -- Recurse into sub-expressions
        local kids = {
            CEParen = {"expr"},
            CEUnaryOp = {"operand"}, CENot = {"operand"}, CEBitNot = {"operand"},
            CEPlus = {"operand"}, CEMinus = {"operand"},
            CEBinary = {"left", "right"},
            CETernary = {"cond", "then_expr", "else_expr"},
            CECall = {"callee"},
            CEComma = {"left", "right"},
            CESubscript = {"base", "index"}, CEDot = {"base"}, CEArrow = {"base"},
            CEDeref = {"operand"}, CECast = {"expr"},
            CESizeofExpr = {"expr"},
        }
        local fields = kids[tag]
        if fields then
            for _, f in ipairs(fields) do
                local child = c_expr[f]
                if child and type(child) == "table" and child._variant then
                    analyze_c_expr_writes(child, out)
                end
            end
            if tag == "CECall" and c_expr.args then
                for _, a in ipairs(c_expr.args) do
                    analyze_c_expr_writes(a, out)
                end
            end
        end
    end

    -- Walk a C statement tree, recording variable writes and control flow
    local analyze_c_stmt_writes  -- forward declaration for recursion

    analyze_c_stmt_writes = function(c_stmt, out)
        if not c_stmt or type(c_stmt) ~= "table" then return end
        local tag = c_stmt._variant
        if tag == "CSWhile" then
            out.has_nested_loop = true
            if c_stmt.cond then analyze_c_expr_writes(c_stmt.cond, out) end
            analyze_c_stmt_writes(c_stmt.body, out)
        elseif tag == "CSDoWhile" then
            out.has_nested_loop = true
            if c_stmt.cond then analyze_c_expr_writes(c_stmt.cond, out) end
            analyze_c_stmt_writes(c_stmt.body, out)
        elseif tag == "CSFor" then
            out.has_nested_loop = true
            if c_stmt.init and c_stmt.init._variant == "CFInitExpr" then
                analyze_c_expr_writes(c_stmt.init.expr, out)
            end
            if c_stmt.cond then analyze_c_expr_writes(c_stmt.cond, out) end
            if c_stmt.incr then analyze_c_expr_writes(c_stmt.incr, out) end
            analyze_c_stmt_writes(c_stmt.body, out)
        elseif tag == "CSIf" then
            if c_stmt.cond then analyze_c_expr_writes(c_stmt.cond, out) end
            local then_writes = { written = {}, conditional_written = {}, has_break = false, has_continue = false, has_nested_loop = false }
            local else_writes = { written = {}, conditional_written = {}, has_break = false, has_continue = false, has_nested_loop = false }
            analyze_c_stmt_writes(c_stmt.then_stmt, then_writes)
            if c_stmt.else_stmt then
                analyze_c_stmt_writes(c_stmt.else_stmt, else_writes)
            end
            -- Merge: written in either branch
            for name in pairs(then_writes.written) do out.written[name] = true end
            for name in pairs(else_writes.written) do out.written[name] = true end
            -- Conditional: written in one branch but not the other
            for name in pairs(then_writes.written) do
                if not else_writes.written[name] then out.conditional_written[name] = true end
            end
            for name in pairs(else_writes.written) do
                if not then_writes.written[name] then out.conditional_written[name] = true end
            end
            -- Propagate control flow
            out.has_break = out.has_break or then_writes.has_break or else_writes.has_break
            out.has_continue = out.has_continue or then_writes.has_continue or else_writes.has_continue
            out.has_nested_loop = out.has_nested_loop or then_writes.has_nested_loop or else_writes.has_nested_loop
        elseif tag == "CSBreak" then
            out.has_break = true
        elseif tag == "CSContinue" then
            out.has_continue = true
        elseif tag == "CSExpr" then
            if c_stmt.expr then analyze_c_expr_writes(c_stmt.expr, out) end
        elseif tag == "CSCompound" then
            for _, bi in ipairs(c_stmt.items or {}) do
                if bi._variant == "CBlockStmt" then
                    analyze_c_stmt_writes(bi.stmt, out)
                end
            end
        elseif tag == "CSLabeled" then
            analyze_c_stmt_writes(c_stmt.stmt, out)
        elseif tag == "CSCase" then
            analyze_c_stmt_writes(c_stmt.stmt, out)
        elseif tag == "CSDefault" then
            analyze_c_stmt_writes(c_stmt.stmt, out)
        elseif tag == "CSSwitch" then
            -- Switch is not a loop; we don't consider it a fallback trigger
            if c_stmt.cond then analyze_c_expr_writes(c_stmt.cond, out) end
            analyze_c_stmt_writes(c_stmt.body, out)
        end
    end

    -- Collect variable names declared anywhere inside a C statement tree
    local function collect_names_declared_in_body(c_stmt, out)
        if not c_stmt or type(c_stmt) ~= "table" then return end
        local tag = c_stmt._variant
        if tag == "CSCompound" then
            for _, bi in ipairs(c_stmt.items or {}) do
                if bi._variant == "CBlockDecl" then
                    for _, decltor in ipairs(bi.decl.declarators or {}) do
                        if decltor.name then out[decltor.name] = true end
                    end
                elseif bi._variant == "CBlockStmt" then
                    collect_names_declared_in_body(bi.stmt, out)
                end
            end
        elseif tag == "CSWhile" or tag == "CSDoWhile" or tag == "CSFor" then
            collect_names_declared_in_body(c_stmt.body, out)
        elseif tag == "CSIf" then
            collect_names_declared_in_body(c_stmt.then_stmt, out)
            if c_stmt.else_stmt then
                collect_names_declared_in_body(c_stmt.else_stmt, out)
            end
        elseif tag == "CSLabeled" then
            collect_names_declared_in_body(c_stmt.stmt, out)
        elseif tag == "CSCase" then
            collect_names_declared_in_body(c_stmt.stmt, out)
        elseif tag == "CSDefault" then
            collect_names_declared_in_body(c_stmt.stmt, out)
        elseif tag == "CSSwitch" then
            collect_names_declared_in_body(c_stmt.body, out)
        end
    end

    -- Main loop analysis: classify variables and detect fallback triggers
    local function analyze_loop(c_stmt, ctx)
        local analysis = {
            carried_vars = {},
            invariant_vars = {},
            has_break = false,
            has_continue = false,
            has_nested_loop = false,
            conditional_writes = {},
            should_fallback = false,
            for_init_names = {},
        }

        -- For CSFor, extract names declared in the for-init
        if c_stmt._variant == "CSFor" then
            if c_stmt.init and c_stmt.init._variant == "CFInitDecl" then
                for _, decltor in ipairs(c_stmt.init.decl.declarators or {}) do
                    if decltor.name then
                        local init_expr = nil
                        if decltor.initializer and decltor.initializer._variant == "CInitExpr" then
                            init_expr = decltor.initializer.expr
                        end
                        analysis.for_init_names[decltor.name] = init_expr
                    end
                end
            end
        end

        -- Run write analysis on the entire loop
        local writes_out = {
            written = {},
            conditional_written = {},
            has_break = false,
            has_continue = false,
            has_nested_loop = false,
        }
        if c_stmt._variant == "CSDoWhile" then
            -- Do-while: body first, then condition
            analyze_c_stmt_writes(c_stmt.body, writes_out)
            if c_stmt.cond then analyze_c_expr_writes(c_stmt.cond, writes_out) end
        else
            -- CSWhile, CSFor: condition is part of the loop structure
            if c_stmt.cond then analyze_c_expr_writes(c_stmt.cond, writes_out) end
            analyze_c_stmt_writes(c_stmt.body, writes_out)
        end
        if c_stmt._variant == "CSFor" and c_stmt.incr then
            analyze_c_expr_writes(c_stmt.incr, writes_out)
        end

        analysis.has_break = writes_out.has_break
        analysis.has_continue = writes_out.has_continue
        analysis.has_nested_loop = writes_out.has_nested_loop
        analysis.conditional_writes = writes_out.conditional_written

        -- Collect names declared inside the loop body
        local body_decl_names = {}
        collect_names_declared_in_body(c_stmt.body, body_decl_names)

        -- Classify locals
        local should_fallback = false
        for name, local_info in pairs(ctx.locals or {}) do
            -- Skip names declared in for-init (handled separately)
            if analysis.for_init_names[name] then
                if writes_out.written[name] or writes_out.conditional_written[name] then
                    -- Carried: for-init var written in loop body/incr
                    local init_expr = analysis.for_init_names[name]
                    local init_moon = nil
                    if init_expr then
                        init_moon = lower_expr(init_expr, ctx)
                    else
                        init_moon = lit_int("0")
                    end
                    table.insert(analysis.carried_vars, {
                        name = name,
                        ty = Ty.TScalar(C.ScalarI32),
                        init = init_moon,
                        live_out = false,  -- for-init vars are scoped to the loop
                    })
                    if ctx.address_taken and ctx.address_taken[name] then
                        should_fallback = true
                    end
                end
                -- Non-written for-init vars: leave as regular decls before the loop
            elseif body_decl_names[name] then
                -- Declared inside the loop body, skip (loop-local)
            elseif writes_out.written[name] or writes_out.conditional_written[name] then
                -- Written in loop body → carried var
                local live_out = true  -- non-for-init vars read after the loop
                if writes_out.conditional_written[name] then
                    should_fallback = true
                end
                if ctx.address_taken and ctx.address_taken[name] then
                    should_fallback = true
                end
                local init = local_info.init or lit_int("0")
                table.insert(analysis.carried_vars, {
                    name = name,
                    ty = Ty.TScalar(C.ScalarI32),
                    init = init,
                    live_out = live_out,
                })
            else
                -- Not written, not declared in body → invariant
                table.insert(analysis.invariant_vars, { name = name })
            end
        end

        if analysis.has_break or analysis.has_continue then
            should_fallback = true
        end
        if analysis.has_nested_loop then
            should_fallback = true
        end
        if #analysis.carried_vars == 0 then
            should_fallback = true
        end
        -- Sort by name for deterministic live_out ordering
        table.sort(analysis.carried_vars, function(a, b) return a.name < b.name end)
        table.sort(analysis.invariant_vars, function(a, b) return a.name < b.name end)

        analysis.should_fallback = should_fallback
        return analysis
    end

    --------------------------------------------------------------------------
    -- Expression lowering: CAst.Expr → MoonTree.Expr
    --------------------------------------------------------------------------
    local lower_expr_to_place
    local function lower_expr(c_expr, ctx)

        -- Literals
        local tag = c_expr._variant
        if tag == "CEIntLit" then return lit_int(c_expr.raw) end
        if tag == "CEFloatLit" then return lit_float(c_expr.raw) end
        if tag == "CECharLit" then
            local raw = c_expr.raw
            local val = 0
            if raw:find("\\") then val = raw:byte(2) or 0 else val = raw:byte(1) or 0 end
            return lit_int(tostring(val))
        end
        if tag == "CEBoolLit" then return lit_bool(c_expr.value) end
        if tag == "CEStrLit" then
            local raw = c_expr.raw
            local bytes = ""
            local i = 1
            while i <= #raw do
                local c = raw:sub(i, i)
                if c == "\\" and i < #raw then
                    local n = raw:sub(i + 1, i + 1)
                    if n == "n" then bytes = bytes .. "\n"; i = i + 2
                    elseif n == "t" then bytes = bytes .. "\t"; i = i + 2
                    elseif n == "r" then bytes = bytes .. "\r"; i = i + 2
                    elseif n == "0" then bytes = bytes .. "\0"; i = i + 2
                    elseif n == "\\" then bytes = bytes .. "\\"; i = i + 2
                    elseif n == "\"" then bytes = bytes .. "\""; i = i + 2
                    elseif n == "'" then bytes = bytes .. "'"; i = i + 2
                    elseif n == "x" then
                        local hex = raw:sub(i + 2, i + 3)
                        bytes = bytes .. string.char(tonumber(hex, 16) or 0)
                        i = i + 4
                    else bytes = bytes .. c; i = i + 1 end
                else bytes = bytes .. c; i = i + 1 end
            end
            return make_data_item(bytes, ctx)
        end

        -- Identifiers
        if tag == "CEIdent" then
            local name = c_expr.name
            if ctx.locals[name] then
                return Tr.ExprRef(Tr.ExprSurface, Bind.ValueRefName(name))
            end
            if ctx.func_table[name] then
                return Tr.ExprRef(Tr.ExprSurface, Bind.ValueRefName(name))
            end
            if ctx.extern_table[name] then
                return Tr.ExprRef(Tr.ExprSurface, Bind.ValueRefName(name))
            end
            return Tr.ExprRef(Tr.ExprSurface, Bind.ValueRefName(name))
        end

        -- Paren
        if tag == "CEParen" then return lower_expr(c_expr.expr, ctx) end

        -- Unary operators
        if tag == "CEPlus" then return lower_expr(c_expr.operand, ctx) end
        if tag == "CEMinus" then return Tr.ExprUnary(Tr.ExprSurface, C.UnaryNeg, lower_expr(c_expr.operand, ctx)) end
        if tag == "CENot" then return Tr.ExprUnary(Tr.ExprSurface, C.UnaryNot, lower_expr(c_expr.operand, ctx)) end
        if tag == "CEBitNot" then return Tr.ExprUnary(Tr.ExprSurface, C.UnaryBitNot, lower_expr(c_expr.operand, ctx)) end
        if tag == "CEDeref" then return Tr.ExprDeref(Tr.ExprSurface, lower_expr(c_expr.operand, ctx)) end

        -- Address-of
        if tag == "CEAddrOf" then
            local op = lower_expr(c_expr.operand, ctx)
            return Tr.ExprAddrOf(Tr.ExprSurface, Tr.PlaceRef(Tr.PlaceSurface, Bind.ValueRefName("_addr")))
        end

        -- Pre/post increment/decrement
        if tag == "CEPreInc" or tag == "CEPreDec" or tag == "CEPostInc" or tag == "CEPostDec" then
            local opname = c_expr.operand._variant == "CEIdent" and c_expr.operand.name or "tmp"
            local old_val = Tr.ExprRef(Tr.ExprSurface, Bind.ValueRefName(opname))
            local is_inc = (tag == "CEPreInc" or tag == "CEPostInc")
            local one = lit_int("1")
            local new_val = Tr.ExprBinary(Tr.ExprSurface, is_inc and C.BinAdd or C.BinSub, old_val, one)
            local stmts = { Tr.StmtSet(Tr.StmtSurface, Tr.PlaceRef(Tr.PlaceSurface, Bind.ValueRefName(opname)), new_val) }
            if tag == "CEPostInc" or tag == "CEPostDec" then
                return Tr.ExprBlock(Tr.ExprSurface, stmts, old_val)
            else
                return Tr.ExprBlock(Tr.ExprSurface, stmts, new_val)
            end
        end

        -- Cast
        if tag == "CECast" then
            local value = lower_expr(c_expr.expr, ctx)
            local tn = c_expr.type_name
            local dst_ty = c_type_spec_to_moon_type(tn.type_spec, ctx)
            return Tr.ExprCast(Tr.ExprSurface, C.SurfaceCast, dst_ty, value)
        end

        -- sizeof
        if tag == "CESizeofExpr" or tag == "CESizeofType" then
            return lit_int("4")  -- placeholder
        end

        -- Binary operators
        if tag == "CEBinary" then
            local left = lower_expr(c_expr.left, ctx)
            local right = lower_expr(c_expr.right, ctx)
            local op_tag = c_expr.op._variant
            -- Arithmetic
            if op_tag == "CBinAdd" then return Tr.ExprBinary(Tr.ExprSurface, C.BinAdd, left, right) end
            if op_tag == "CBinSub" then return Tr.ExprBinary(Tr.ExprSurface, C.BinSub, left, right) end
            if op_tag == "CBinMul" then return Tr.ExprBinary(Tr.ExprSurface, C.BinMul, left, right) end
            if op_tag == "CBinDiv" then return Tr.ExprBinary(Tr.ExprSurface, C.BinDiv, left, right) end
            if op_tag == "CBinMod" then return Tr.ExprBinary(Tr.ExprSurface, C.BinRem, left, right) end
            -- Bitwise
            if op_tag == "CBinBitAnd" then return Tr.ExprBinary(Tr.ExprSurface, C.BinBitAnd, left, right) end
            if op_tag == "CBinBitOr" then return Tr.ExprBinary(Tr.ExprSurface, C.BinBitOr, left, right) end
            if op_tag == "CBinBitXor" then return Tr.ExprBinary(Tr.ExprSurface, C.BinBitXor, left, right) end
            -- Shift
            if op_tag == "CBinShl" then return Tr.ExprBinary(Tr.ExprSurface, C.BinShl, left, right) end
            if op_tag == "CBinShr" then return Tr.ExprBinary(Tr.ExprSurface, C.BinAShr, left, right) end
            -- Comparison
            if op_tag == "CBinLt" then return Tr.ExprCompare(Tr.ExprSurface, C.CmpLt, left, right) end
            if op_tag == "CBinLe" then return Tr.ExprCompare(Tr.ExprSurface, C.CmpLe, left, right) end
            if op_tag == "CBinGt" then return Tr.ExprCompare(Tr.ExprSurface, C.CmpGt, left, right) end
            if op_tag == "CBinGe" then return Tr.ExprCompare(Tr.ExprSurface, C.CmpGe, left, right) end
            if op_tag == "CBinEq" then return Tr.ExprCompare(Tr.ExprSurface, C.CmpEq, left, right) end
            if op_tag == "CBinNe" then return Tr.ExprCompare(Tr.ExprSurface, C.CmpNe, left, right) end
            -- Logical (short-circuit)
            if op_tag == "CBinLogAnd" then
                local zero = lit_int("0")
                return Tr.ExprIf(Tr.ExprSurface,
                    Tr.ExprCompare(Tr.ExprSurface, C.CmpNe, left, zero),
                    Tr.ExprCompare(Tr.ExprSurface, C.CmpNe, right, zero),
                    lit_int("0"))
            end
            if op_tag == "CBinLogOr" then
                local zero = lit_int("0")
                return Tr.ExprIf(Tr.ExprSurface,
                    Tr.ExprCompare(Tr.ExprSurface, C.CmpNe, left, zero),
                    lit_int("1"),
                    Tr.ExprCompare(Tr.ExprSurface, C.CmpNe, right, zero))
            end
            return lit_int("0")
        end

        -- Ternary
        if tag == "CETernary" then
            local cond = lower_expr(c_expr.cond, ctx)
            local then_expr = lower_expr(c_expr.then_expr, ctx)
            local else_expr = lower_expr(c_expr.else_expr, ctx)
            return Tr.ExprIf(Tr.ExprSurface, c_cond_to_bool(cond),
                then_expr, else_expr)
        end

        -- Assignment
        if tag == "CEAssign" then
            local assign_tag = c_expr.op._variant
            local rhs = lower_expr(c_expr.right, ctx)
            local rhs_val = rhs
            if assign_tag ~= "CAssign" then
                local old_val = lower_expr(c_expr.left, ctx)
                local bop = C.BinAdd
                if assign_tag == "CSubAssign" then bop = C.BinSub
                elseif assign_tag == "CMulAssign" then bop = C.BinMul
                elseif assign_tag == "CDivAssign" then bop = C.BinDiv
                elseif assign_tag == "CModAssign" then bop = C.BinRem
                elseif assign_tag == "CAndAssign" then bop = C.BinBitAnd
                elseif assign_tag == "COrAssign" then bop = C.BinBitOr
                elseif assign_tag == "CXorAssign" then bop = C.BinBitXor
                elseif assign_tag == "CShlAssign" then bop = C.BinShl
                elseif assign_tag == "CShrAssign" then bop = C.BinAShr
                end
                rhs_val = Tr.ExprBinary(Tr.ExprSurface, bop, old_val, rhs)
            end
            local stmts = { Tr.StmtSet(Tr.StmtSurface, lower_expr_to_place(c_expr.left, ctx), rhs_val) }
            return Tr.ExprBlock(Tr.ExprSurface, stmts, rhs_val)
        end

        -- Comma
        if tag == "CEComma" then
            local left = lower_expr(c_expr.left, ctx)
            local right = lower_expr(c_expr.right, ctx)
            return Tr.ExprBlock(Tr.ExprSurface, { Tr.StmtExpr(Tr.StmtSurface, left) }, right)
        end

        -- Call
        if tag == "CECall" then
            local callee = lower_expr(c_expr.callee, ctx)
            local args = {}
            for _, a in ipairs(c_expr.args or {}) do
                args[#args + 1] = lower_expr(a, ctx)
            end
            return Tr.ExprCall(Tr.ExprSurface, Sem.CallUnresolved(callee), args)
        end

        -- Member access.  Resolve C layout facts here, because Tree Dot is a
        -- high-level surface construct and tree_to_back only lowers resolved
        -- FieldByOffset accesses.
        if tag == "CEDot" then
            local owner = c_expr_desc(c_expr.base, ctx)
            local field = field_ref_for(owner, c_expr.field, ctx)
            if field then
                return Tr.ExprField(Tr.ExprSurface, lower_expr(c_expr.base, ctx), field)
            end
            return Tr.ExprDot(Tr.ExprSurface, lower_expr(c_expr.base, ctx), c_expr.field)
        end
        if tag == "CEArrow" then
            local d = c_expr_desc(c_expr.base, ctx)
            local owner = d and d.tag == "ptr" and d.pointee or nil
            local field = field_ref_for(owner, c_expr.field, ctx)
            if field then
                return Tr.ExprField(Tr.ExprSurface, lower_expr(c_expr.base, ctx), field)
            end
            return Tr.ExprDot(Tr.ExprSurface,
                Tr.ExprDeref(Tr.ExprSurface, lower_expr(c_expr.base, ctx)),
                c_expr.field)
        end

        -- Subscript
        if tag == "CESubscript" then
            local base = lower_expr(c_expr.base, ctx)
            local index = lower_expr(c_expr.index, ctx)
            return Tr.ExprIndex(Tr.ExprSurface,
                Tr.IndexBaseExpr(base), index)
        end

        -- Compound literal — simplified to nil for now
        if tag == "CECompoundLit" then return lit_int("0") end

        -- Statement expression
        if tag == "CEStmtExpr" then
            local stmts = {}
            for _, bi in ipairs(c_expr.items or {}) do
                if bi._variant == "CBlockDecl" then
                    local ds = lower_decl(bi.decl, ctx)
                    for _, s in ipairs(ds) do stmts[#stmts + 1] = s end
                elseif bi._variant == "CBlockStmt" then
                    local ss = lower_stmt(bi.stmt, ctx)
                    for _, s in ipairs(ss) do stmts[#stmts + 1] = s end
                end
            end
            local result = lower_expr(c_expr.result, ctx)
            return Tr.ExprBlock(Tr.ExprSurface, stmts, result)
        end

        return lit_int("0")
    end

    --------------------------------------------------------------------------
    -- Statement lowering: CAst.Stmt → MoonTree.Stmt[]
    -------------------------------------------------------------------------=
    lower_expr_to_place = function(c_expr, ctx)
        local tag = c_expr._variant
        if tag == "CEIdent" then
            return Tr.PlaceRef(Tr.PlaceSurface, Bind.ValueRefName(c_expr.name))
        end
        if tag == "CEDeref" then
            return Tr.PlaceDeref(Tr.PlaceSurface, lower_expr(c_expr.operand, ctx))
        end
        if tag == "CEDot" then
            local owner = c_expr_desc(c_expr.base, ctx)
            local field = field_ref_for(owner, c_expr.field, ctx)
            local base_place = lower_expr_to_place(c_expr.base, ctx)
            if field then return Tr.PlaceField(Tr.PlaceSurface, base_place, field) end
            return Tr.PlaceDot(Tr.PlaceSurface, base_place, c_expr.field)
        end
        if tag == "CEArrow" then
            local d = c_expr_desc(c_expr.base, ctx)
            local owner = d and d.tag == "ptr" and d.pointee or nil
            local field = field_ref_for(owner, c_expr.field, ctx)
            local base_place = Tr.PlaceDeref(Tr.PlaceSurface, lower_expr(c_expr.base, ctx))
            if field then return Tr.PlaceField(Tr.PlaceSurface, base_place, field) end
            return Tr.PlaceDot(Tr.PlaceSurface, base_place, c_expr.field)
        end
        if tag == "CESubscript" then
            local base = lower_expr(c_expr.base, ctx)
            local index = lower_expr(c_expr.index, ctx)
            return Tr.PlaceIndex(Tr.PlaceSurface,
                Tr.IndexBaseExpr(base), index)
        end
        return Tr.PlaceRef(Tr.PlaceSurface, Bind.ValueRefName("_"))
    end

    local lower_stmt, lower_decl, append_lists, collect_jump_args  -- forward declarations

    local function lower_block_items(items, ctx)
        local stmts = {}
        for _, bi in ipairs(items or {}) do
            if bi._variant == "CBlockDecl" then
                local ds = lower_decl(bi.decl, ctx)
                for _, s in ipairs(ds) do stmts[#stmts + 1] = s end
            elseif bi._variant == "CBlockStmt" then
                local ss = lower_stmt(bi.stmt, ctx)
                for _, s in ipairs(ss) do stmts[#stmts + 1] = s end
            end
        end
        return stmts
    end

    lower_decl = function(decl, ctx)
        local stmts = {}
        for _, decltor in ipairs(decl.declarators or {}) do
            if decltor.name then
                local name = decltor.name
                local is_var = ctx.address_taken and ctx.address_taken[name]
                local bind = is_var and local_cell_binding(name) or local_value_binding(name)
                local init = nil
                if decltor.initializer then
                    if decltor.initializer._variant == "CInitExpr" then
                        init = lower_expr(decltor.initializer.expr, ctx)
                    end
                end
                ctx.locals[name] = { binding = bind, is_var = is_var, init = init, c_desc = c_desc_from_spec_decl(decl.type_spec, decltor, ctx) }
                if init then
                    if is_var then
                        stmts[#stmts + 1] = Tr.StmtVar(Tr.StmtSurface, bind, init)
                    else
                        stmts[#stmts + 1] = Tr.StmtLet(Tr.StmtSurface, bind, init)
                    end
                else
                    if is_var then
                        stmts[#stmts + 1] = Tr.StmtVar(Tr.StmtSurface, bind, lit_int("0"))
                    else
                        stmts[#stmts + 1] = Tr.StmtLet(Tr.StmtSurface, bind, lit_int("0"))
                    end
                end
            end
        end
        return stmts
    end

    function lower_stmt(c_stmt, ctx)
        if type(c_stmt) ~= "table" then return {} end
        local tag = c_stmt._variant

        if tag == "CSExpr" then
            if c_stmt.expr then
                if c_stmt.expr._variant == "CEAssign" then
                    local rhs = lower_expr(c_stmt.expr.right, ctx)
                    local assign_tag = c_stmt.expr.op._variant
                    if assign_tag ~= "CAssign" then
                        local old_val = lower_expr(c_stmt.expr.left, ctx)
                        local bop = C.BinAdd
                        if assign_tag == "CSubAssign" then bop = C.BinSub
                        elseif assign_tag == "CMulAssign" then bop = C.BinMul
                        elseif assign_tag == "CDivAssign" then bop = C.BinDiv
                        elseif assign_tag == "CModAssign" then bop = C.BinRem
                        elseif assign_tag == "CAndAssign" then bop = C.BinBitAnd
                        elseif assign_tag == "COrAssign" then bop = C.BinBitOr
                        elseif assign_tag == "CXorAssign" then bop = C.BinBitXor
                        elseif assign_tag == "CShlAssign" then bop = C.BinShl
                        elseif assign_tag == "CShrAssign" then bop = C.BinAShr end
                        rhs = Tr.ExprBinary(Tr.ExprSurface, bop, old_val, rhs)
                    end
                    return { Tr.StmtSet(Tr.StmtSurface, lower_expr_to_place(c_stmt.expr.left, ctx), rhs) }
                end
                return { Tr.StmtExpr(Tr.StmtSurface, lower_expr(c_stmt.expr, ctx)) }
            end
            return {}
        end

        if tag == "CSCompound" then
            return lower_block_items(c_stmt.items, ctx)
        end

        if tag == "CSIf" then
            local cond = lower_expr(c_stmt.cond, ctx)
            local then_body = lower_stmt(c_stmt.then_stmt, ctx)
            local else_body = c_stmt.else_stmt and lower_stmt(c_stmt.else_stmt, ctx) or {}
            return { Tr.StmtIf(Tr.StmtSurface, c_cond_to_bool(cond),
                then_body, else_body) }
        end

        if tag == "CSReturn" then
            if c_stmt.expr then
                return { Tr.StmtReturnValue(Tr.StmtSurface, lower_expr(c_stmt.expr, ctx)) }
            else
                return { Tr.StmtReturnVoid(Tr.StmtSurface) }
            end
        end

        if tag == "CSBreak" then
            if ctx.break_target then
                local args = {}
                if ctx.loop_carried_vars then
                    for _, cv in ipairs(ctx.loop_carried_vars) do
                        if cv.live_out then
                            args[#args + 1] = Tr.JumpArg(cv.name, Tr.ExprRef(Tr.ExprSurface, Bind.ValueRefName(cv.name)))
                        end
                    end
                end
                return { Tr.StmtJump(Tr.StmtSurface, ctx.break_target, args) }
            end
            return { Tr.StmtReturnVoid(Tr.StmtSurface) }
        end

        if tag == "CSContinue" then
            if ctx.continue_target then
                local args = {}
                if ctx.loop_carried_vars then
                    for _, cv in ipairs(ctx.loop_carried_vars) do
                        args[#args + 1] = Tr.JumpArg(cv.name, Tr.ExprRef(Tr.ExprSurface, Bind.ValueRefName(cv.name)))
                    end
                end
                return { Tr.StmtJump(Tr.StmtSurface, ctx.continue_target, args) }
            end
            return { Tr.StmtReturnVoid(Tr.StmtSurface) }
        end

        if tag == "CSGoto" then
            return { Tr.StmtJump(Tr.StmtSurface, Tr.BlockLabel(c_stmt.label), {}) }
        end

        -- Loops
        if tag == "CSWhile" then
            local saved_break = ctx.break_target
            local saved_continue = ctx.continue_target
            local analysis = analyze_loop(c_stmt, ctx)

            if analysis.should_fallback then
                local loop_label = fresh_label(ctx, "while_loop")
                local body_label = fresh_label(ctx, "while_body")
                local end_label = fresh_label(ctx, "while_end")
                ctx.break_target = end_label
                ctx.continue_target = loop_label
                local cond = lower_expr(c_stmt.cond, ctx)
                local body_stmts = lower_stmt(c_stmt.body, ctx)
                local region_id = fresh_region_id(ctx)
                local entry = Tr.EntryControlBlock(loop_label,
                    {},
                    { Tr.StmtIf(Tr.StmtSurface, c_cond_to_bool(cond),
                        { Tr.StmtJump(Tr.StmtSurface, body_label, {}) },
                        { Tr.StmtJump(Tr.StmtSurface, end_label, {}) }
                    ) }
                )
                local body_block = Tr.ControlBlock(body_label, {},
                    append_lists(body_stmts, { Tr.StmtJump(Tr.StmtSurface, loop_label, {}) })
                )
                local end_block = Tr.ControlBlock(end_label, {}, { Tr.StmtYieldVoid(Tr.StmtSurface) })
                ctx.break_target = saved_break
                ctx.continue_target = saved_continue
                return { Tr.StmtControl(Tr.StmtSurface,
                    Tr.ControlStmtRegion(region_id, entry, { body_block, end_block })) }
            end

            -- Fact-based: single-block region with block params
            local carried = {}
            for _, cv in ipairs(analysis.carried_vars) do carried[cv.name] = cv end
            for name in pairs(carried) do ctx.locals[name] = nil end
            ctx.loop_carried_vars = analysis.carried_vars
            local cond = lower_expr(c_stmt.cond, ctx)
            local body_stmts = lower_stmt(c_stmt.body, ctx)
            local jump_args_pairs, cleaned_body = collect_jump_args(body_stmts, carried)
            ctx.loop_carried_vars = nil

            local entry_params = {}
            for _, cv in ipairs(analysis.carried_vars) do
                entry_params[#entry_params + 1] = Tr.EntryBlockParam(cv.name, cv.ty, cv.init)
            end
            local live_out = {}
            for _, cv in ipairs(analysis.carried_vars) do
                if cv.live_out then live_out[#live_out + 1] = cv end
            end

            local loop_label = fresh_label(ctx, "lp")
            local entry_body = {}
            if #live_out > 0 then
                entry_body[#entry_body + 1] = Tr.StmtIf(Tr.StmtSurface, c_cond_to_bool(cond),
                    {}, { Tr.StmtYieldValue(Tr.StmtSurface,
                        Tr.ExprRef(Tr.ExprSurface, Bind.ValueRefName(live_out[1].name))) })
            else
                entry_body[#entry_body + 1] = Tr.StmtIf(Tr.StmtSurface, c_cond_to_bool(cond),
                    {}, { Tr.StmtYieldVoid(Tr.StmtSurface) })
            end
            -- Inject cleaned body (non-carried-write statements) before the jump
            for _, s in ipairs(cleaned_body) do entry_body[#entry_body + 1] = s end
            local jump_args = {}
            local written_names = {}
            for _, pair in ipairs(jump_args_pairs) do
                jump_args[#jump_args + 1] = Tr.JumpArg(pair.name, pair.value)
                written_names[pair.name] = true
            end
            for name, _ in pairs(carried) do
                if not written_names[name] then
                    jump_args[#jump_args + 1] = Tr.JumpArg(name,
                        Tr.ExprRef(Tr.ExprSurface, Bind.ValueRefName(name)))
                end
            end
            entry_body[#entry_body + 1] = Tr.StmtJump(Tr.StmtSurface, loop_label, jump_args)

            local entry = Tr.EntryControlBlock(loop_label, entry_params, entry_body)
            local region_id = fresh_region_id(ctx)
            ctx.break_target = saved_break
            ctx.continue_target = saved_continue

            local result = {}
            if #live_out > 0 then
                local region = Tr.ControlExprRegion(region_id, live_out[1].ty, entry, {})
                local control_expr = Tr.ExprControl(Tr.ExprSurface, region)
                local bind = local_value_binding(live_out[1].name)
                result[#result + 1] = Tr.StmtLet(Tr.StmtSurface, bind, control_expr)
                for _, cv in ipairs(live_out) do
                    ctx.locals[cv.name] = { binding = bind, is_var = false, init = control_expr }
                end
            else
                local region = Tr.ControlStmtRegion(region_id, entry, {})
                result[#result + 1] = Tr.StmtControl(Tr.StmtSurface, region)
            end
            return result
        end

        if tag == "CSDoWhile" then
            local saved_break = ctx.break_target
            local saved_continue = ctx.continue_target
            local analysis = analyze_loop(c_stmt, ctx)

            if analysis.should_fallback then
                local body_label = fresh_label(ctx, "dowhile_body")
                local cond_label = fresh_label(ctx, "dowhile_cond")
                local end_label = fresh_label(ctx, "dowhile_end")
                ctx.break_target = end_label
                ctx.continue_target = cond_label
                local body_stmts = lower_stmt(c_stmt.body, ctx)
                local cond = lower_expr(c_stmt.cond, ctx)
                local region_id = fresh_region_id(ctx)
                local entry = Tr.EntryControlBlock(body_label, {},
                    append_lists(body_stmts, { Tr.StmtJump(Tr.StmtSurface, cond_label, {}) })
                )
                local cond_block = Tr.ControlBlock(cond_label, {},
                    { Tr.StmtIf(Tr.StmtSurface, c_cond_to_bool(cond),
                        { Tr.StmtJump(Tr.StmtSurface, body_label, {}) },
                        { Tr.StmtJump(Tr.StmtSurface, end_label, {}) }
                    ) }
                )
                local end_block = Tr.ControlBlock(end_label, {}, { Tr.StmtYieldVoid(Tr.StmtSurface) })
                ctx.break_target = saved_break
                ctx.continue_target = saved_continue
                return { Tr.StmtControl(Tr.StmtSurface,
                    Tr.ControlStmtRegion(region_id, entry, { cond_block, end_block })) }
            end

            -- Fact-based: body first, then condition check before back-jump
            local carried = {}
            for _, cv in ipairs(analysis.carried_vars) do carried[cv.name] = cv end
            for name in pairs(carried) do ctx.locals[name] = nil end
            ctx.loop_carried_vars = analysis.carried_vars
            local body_stmts = lower_stmt(c_stmt.body, ctx)
            local cond = lower_expr(c_stmt.cond, ctx)
            local jump_args_pairs, cleaned_body = collect_jump_args(body_stmts, carried)
            ctx.loop_carried_vars = nil

            local entry_params = {}
            for _, cv in ipairs(analysis.carried_vars) do
                entry_params[#entry_params + 1] = Tr.EntryBlockParam(cv.name, cv.ty, cv.init)
            end
            local live_out = {}
            for _, cv in ipairs(analysis.carried_vars) do
                if cv.live_out then live_out[#live_out + 1] = cv end
            end

            local loop_label = fresh_label(ctx, "dwl")
            local entry_body = {}
            if #live_out > 0 then
                entry_body[#entry_body + 1] = Tr.StmtIf(Tr.StmtSurface, c_cond_to_bool(cond),
                    {}, { Tr.StmtYieldValue(Tr.StmtSurface,
                        Tr.ExprRef(Tr.ExprSurface, Bind.ValueRefName(live_out[1].name))) })
            else
                entry_body[#entry_body + 1] = Tr.StmtIf(Tr.StmtSurface, c_cond_to_bool(cond),
                    {}, { Tr.StmtYieldVoid(Tr.StmtSurface) })
            end
            -- Inject cleaned body (non-carried-write statements) before the jump
            for _, s in ipairs(cleaned_body) do entry_body[#entry_body + 1] = s end
            local jump_args = {}
            local written_names = {}
            for _, pair in ipairs(jump_args_pairs) do
                jump_args[#jump_args + 1] = Tr.JumpArg(pair.name, pair.value)
                written_names[pair.name] = true
            end
            for name, _ in pairs(carried) do
                if not written_names[name] then
                    jump_args[#jump_args + 1] = Tr.JumpArg(name,
                        Tr.ExprRef(Tr.ExprSurface, Bind.ValueRefName(name)))
                end
            end
            entry_body[#entry_body + 1] = Tr.StmtJump(Tr.StmtSurface, loop_label, jump_args)

            local entry = Tr.EntryControlBlock(loop_label, entry_params, entry_body)
            local region_id = fresh_region_id(ctx)
            ctx.break_target = saved_break
            ctx.continue_target = saved_continue

            local result = {}
            if #live_out > 0 then
                local region = Tr.ControlExprRegion(region_id, live_out[1].ty, entry, {})
                local control_expr = Tr.ExprControl(Tr.ExprSurface, region)
                local bind = local_value_binding(live_out[1].name)
                result[#result + 1] = Tr.StmtLet(Tr.StmtSurface, bind, control_expr)
                for _, cv in ipairs(live_out) do
                    ctx.locals[cv.name] = { binding = bind, is_var = false, init = control_expr }
                end
            else
                local region = Tr.ControlStmtRegion(region_id, entry, {})
                result[#result + 1] = Tr.StmtControl(Tr.StmtSurface, region)
            end
            return result
        end

        if tag == "CSFor" then
            local saved_break = ctx.break_target
            local saved_continue = ctx.continue_target
            local analysis = analyze_loop(c_stmt, ctx)

            if analysis.should_fallback then
                local loop_label = fresh_label(ctx, "for_loop")
                local body_label = fresh_label(ctx, "for_body")
                local incr_label = fresh_label(ctx, "for_incr")
                local end_label = fresh_label(ctx, "for_end")
                ctx.break_target = end_label
                ctx.continue_target = incr_label
                local init_stmts = {}
                if c_stmt.init then
                    if c_stmt.init._variant == "CFInitDecl" then
                        local ds = lower_decl(c_stmt.init.decl, ctx)
                        for _, s in ipairs(ds) do init_stmts[#init_stmts + 1] = s end
                    elseif c_stmt.init._variant == "CFInitExpr" then
                        init_stmts[#init_stmts + 1] = Tr.StmtExpr(Tr.StmtSurface, lower_expr(c_stmt.init.expr, ctx))
                    end
                end
                local cond = c_stmt.cond and lower_expr(c_stmt.cond, ctx) or lit_int("1")
                local body_stmts = lower_stmt(c_stmt.body, ctx)
                local incr_stmts = c_stmt.incr and { Tr.StmtExpr(Tr.StmtSurface, lower_expr(c_stmt.incr, ctx)) } or {}
                local region_id = fresh_region_id(ctx)
                local entry = Tr.EntryControlBlock(loop_label, {},
                    { Tr.StmtIf(Tr.StmtSurface, c_cond_to_bool(cond),
                        { Tr.StmtJump(Tr.StmtSurface, body_label, {}) },
                        { Tr.StmtJump(Tr.StmtSurface, end_label, {}) }
                    ) }
                )
                local body_block = Tr.ControlBlock(body_label, {},
                    append_lists(body_stmts, { Tr.StmtJump(Tr.StmtSurface, incr_label, {}) })
                )
                local incr_block = Tr.ControlBlock(incr_label, {},
                    append_lists(incr_stmts, { Tr.StmtJump(Tr.StmtSurface, loop_label, {}) })
                )
                local end_block = Tr.ControlBlock(end_label, {}, { Tr.StmtYieldVoid(Tr.StmtSurface) })
                ctx.break_target = saved_break
                ctx.continue_target = saved_continue
                local stmts = {}
                for _, s in ipairs(init_stmts) do stmts[#stmts + 1] = s end
                stmts[#stmts + 1] = Tr.StmtControl(Tr.StmtSurface,
                    Tr.ControlStmtRegion(region_id, entry, { body_block, incr_block, end_block }))
                return stmts
            end

            -- Fact-based: condition → body → incr → jump, carried via block params
            local carried = {}
            for _, cv in ipairs(analysis.carried_vars) do carried[cv.name] = cv end
            for name in pairs(carried) do ctx.locals[name] = nil end

            -- Emit non-carried for-init declarations as separate stmts before the loop
            local init_stmts = {}
            if c_stmt.init and c_stmt.init._variant == "CFInitDecl" then
                for _, decltor in ipairs(c_stmt.init.decl.declarators or {}) do
                    if decltor.name and not carried[decltor.name] then
                        local is_var = ctx.address_taken and ctx.address_taken[decltor.name]
                        local bind = is_var and local_cell_binding(decltor.name) or local_value_binding(decltor.name)
                        local init = lit_int("0")
                        if decltor.initializer and decltor.initializer._variant == "CInitExpr" then
                            init = lower_expr(decltor.initializer.expr, ctx)
                        end
                        if is_var then
                            init_stmts[#init_stmts + 1] = Tr.StmtVar(Tr.StmtSurface, bind, init)
                        else
                            init_stmts[#init_stmts + 1] = Tr.StmtLet(Tr.StmtSurface, bind, init)
                        end
                        ctx.locals[decltor.name] = { binding = bind, is_var = is_var, init = init, c_desc = c_desc_from_spec_decl(c_stmt.init.decl.type_spec, decltor, ctx) }
                    end
                end
            elseif c_stmt.init and c_stmt.init._variant == "CFInitExpr" then
                -- Only emit the for-init if it has observable effects beyond carried-var writes
                local init_raw = { Tr.StmtExpr(Tr.StmtSurface, lower_expr(c_stmt.init.expr, ctx)) }
                local _, cleaned = collect_jump_args(init_raw, carried)
                for _, s in ipairs(cleaned) do
                    local sc = pvm.classof(s)
                    -- Skip trivially dead StmtExpr(literal)
                    if sc == Tr.StmtExpr and pvm.classof(s.expr) == Tr.ExprLit then
                        -- nothing: the for-init was purely a carried-var assignment
                    else
                        init_stmts[#init_stmts + 1] = s
                    end
                end
            end

            ctx.loop_carried_vars = analysis.carried_vars
            local cond = c_stmt.cond and lower_expr(c_stmt.cond, ctx) or lit_int("1")
            local body_stmts = lower_stmt(c_stmt.body, ctx)
            local incr_stmts = c_stmt.incr and { Tr.StmtExpr(Tr.StmtSurface, lower_expr(c_stmt.incr, ctx)) } or {}

            -- Extract jump args from body + incr (incr wins for same names — last write)
            local body_jp, cleaned_body = collect_jump_args(body_stmts, carried)
            local incr_jp, cleaned_incr = collect_jump_args(incr_stmts, carried)
            local jump_arg_map = {}
            for _, pair in ipairs(body_jp) do jump_arg_map[pair.name] = pair.value end
            for _, pair in ipairs(incr_jp) do jump_arg_map[pair.name] = pair.value end
            ctx.loop_carried_vars = nil

            local entry_params = {}
            for _, cv in ipairs(analysis.carried_vars) do
                entry_params[#entry_params + 1] = Tr.EntryBlockParam(cv.name, cv.ty, cv.init)
            end
            local live_out = {}
            for _, cv in ipairs(analysis.carried_vars) do
                if cv.live_out then live_out[#live_out + 1] = cv end
            end

            local loop_label = fresh_label(ctx, "fl")
            local entry_body = {}
            if #live_out > 0 then
                entry_body[#entry_body + 1] = Tr.StmtIf(Tr.StmtSurface, c_cond_to_bool(cond),
                    {}, { Tr.StmtYieldValue(Tr.StmtSurface,
                        Tr.ExprRef(Tr.ExprSurface, Bind.ValueRefName(live_out[1].name))) })
            else
                entry_body[#entry_body + 1] = Tr.StmtIf(Tr.StmtSurface, c_cond_to_bool(cond),
                    {}, { Tr.StmtYieldVoid(Tr.StmtSurface) })
            end
            -- Inject cleaned body + incr (non-carried-write statements) before the jump
            for _, s in ipairs(cleaned_body) do entry_body[#entry_body + 1] = s end
            for _, s in ipairs(cleaned_incr) do entry_body[#entry_body + 1] = s end
            local jump_args = {}
            for name, value in pairs(jump_arg_map) do
                jump_args[#jump_args + 1] = Tr.JumpArg(name, value)
            end
            for _, cv in ipairs(analysis.carried_vars) do
                if not jump_arg_map[cv.name] then
                    jump_args[#jump_args + 1] = Tr.JumpArg(cv.name,
                        Tr.ExprRef(Tr.ExprSurface, Bind.ValueRefName(cv.name)))
                end
            end
            entry_body[#entry_body + 1] = Tr.StmtJump(Tr.StmtSurface, loop_label, jump_args)

            local entry = Tr.EntryControlBlock(loop_label, entry_params, entry_body)
            local region_id = fresh_region_id(ctx)
            ctx.break_target = saved_break
            ctx.continue_target = saved_continue

            local result = {}
            for _, s in ipairs(init_stmts) do result[#result + 1] = s end
            if #live_out > 0 then
                local region = Tr.ControlExprRegion(region_id, live_out[1].ty, entry, {})
                local control_expr = Tr.ExprControl(Tr.ExprSurface, region)
                local bind = local_value_binding(live_out[1].name)
                result[#result + 1] = Tr.StmtLet(Tr.StmtSurface, bind, control_expr)
                for _, cv in ipairs(live_out) do
                    ctx.locals[cv.name] = { binding = bind, is_var = false, init = control_expr }
                end
            else
                local region = Tr.ControlStmtRegion(region_id, entry, {})
                result[#result + 1] = Tr.StmtControl(Tr.StmtSurface, region)
            end
            return result
        end

        -- Switch
        if tag == "CSSwitch" then
            local saved_break = ctx.break_target
            local saved_cases = ctx.switch_cases
            local saved_default = ctx.switch_default
            ctx.switch_cases = {}
            ctx.switch_default = nil
            -- First pass: collect case values and default
            local function collect_switch_cases(body_items)
                for _, bi in ipairs(body_items or {}) do
                    if bi._variant == "CBlockStmt" then
                        local s = bi.stmt
                        if s._variant == "CSCase" then
                            ctx.switch_cases[#ctx.switch_cases + 1] = { value = s.value, stmt = s.stmt }
                        elseif s._variant == "CSDefault" then
                            ctx.switch_default = s.stmt
                        end
                    end
                end
            end
            if c_stmt.body._variant == "CSCompound" then
                collect_switch_cases(c_stmt.body.items)
            end
            local switch_value = lower_expr(c_stmt.cond, ctx)
            local after_label = fresh_label(ctx, "switch_after")
            ctx.break_target = after_label
            -- Build case blocks with fallthrough
            local blocks = {}
            local arms = {}
            local default_block = nil
            for i, cs in ipairs(ctx.switch_cases) do
                local case_label = fresh_label(ctx, "case")
                local case_stmts = lower_stmt(cs.stmt, ctx)
                -- Handle fallthrough: unless last case, jump to next case
                if i < #ctx.switch_cases or ctx.switch_default then
                    local next_label = fresh_label(ctx, "case_next")
                    table.insert(case_stmts, Tr.StmtJump(Tr.StmtSurface, next_label, {}))
                    blocks[#blocks + 1] = Tr.ControlBlock(next_label, {}, {})
                else
                    table.insert(case_stmts, Tr.StmtJump(Tr.StmtSurface, after_label, {}))
                end
                blocks[#blocks + 1] = Tr.ControlBlock(case_label, {}, case_stmts)
                arms[#arms + 1] = Tr.SwitchStmtArm(Sem.SwitchKeyExpr(lower_expr(cs.value, ctx)), { Tr.StmtJump(Tr.StmtSurface, case_label, {}) })
            end
            if ctx.switch_default then
                local def_label = fresh_label(ctx, "default")
                local def_stmts = lower_stmt(ctx.switch_default, ctx)
                table.insert(def_stmts, Tr.StmtJump(Tr.StmtSurface, after_label, {}))
                blocks[#blocks + 1] = Tr.ControlBlock(def_label, {}, def_stmts)
                default_block = { Tr.StmtJump(Tr.StmtSurface, def_label, {}) }
            end
            blocks[#blocks + 1] = Tr.ControlBlock(after_label, {}, {})
            local switch_stmt = Tr.StmtSwitch(Tr.StmtSurface, switch_value, arms, {}, default_block or {})
            local region_id = fresh_region_id(ctx)
            local entry = Tr.EntryControlBlock(fresh_label(ctx, "switch_entry"), {},
                { switch_stmt }
            )
            ctx.break_target = saved_break
            ctx.switch_cases = saved_cases
            ctx.switch_default = saved_default
            return { Tr.StmtControl(Tr.StmtSurface, Tr.ControlStmtRegion(region_id, entry, blocks)) }
        end

        return {}
    end

    --------------------------------------------------------------------------
    -- Utility: append_lists
    --------------------------------------------------------------------------
    append_lists = function(a, b)
        local r = {}
        for _, x in ipairs(a or {}) do r[#r + 1] = x end
        for _, x in ipairs(b or {}) do r[#r + 1] = x end
        return r
    end

    --------------------------------------------------------------------------
    -- Utility: collect_jump_args — extract jump args from lowered MoonTree stmts
    --------------------------------------------------------------------------
    -- Walks a flat statement list (non-recursive into nested control regions).
    -- Finds StmtSet(PlaceRef(ValueRefName(name)), value) for carried names,
    -- extracts the value as a jump arg, and removes the StmtSet from the list.
    -- Also handles ExprBlock containing such StmtSet operations.
    -- For carried vars with no writes, adds identity jump arg (ValueRefName).
    collect_jump_args = function(body_stmts, carried)
        local jump_arg_map = {}  -- name → expr
        local cleaned_stmts = {}

        for _, stmt in ipairs(body_stmts or {}) do
            local cls = pvm.classof(stmt)

            if cls == Tr.StmtSet then
                local place = stmt.place
                if place and pvm.classof(place) == Tr.PlaceRef then
                    local ref = place.ref
                    if ref and pvm.classof(ref) == Bind.ValueRefName and carried[ref.name] then
                        -- Carried write → extract as jump arg, skip the StmtSet
                        jump_arg_map[ref.name] = stmt.value
                    else
                        cleaned_stmts[#cleaned_stmts + 1] = stmt
                    end
                else
                    cleaned_stmts[#cleaned_stmts + 1] = stmt
                end
            elseif cls == Tr.StmtExpr then
                -- Check if the expression is an ExprBlock containing carried writes
                local expr = stmt.expr
                if expr and pvm.classof(expr) == Tr.ExprBlock then
                    local inner_stmts = {}
                    local has_carried_write = false
                    for _, inner in ipairs(expr.stmts or {}) do
                        if pvm.classof(inner) == Tr.StmtSet then
                            local place = inner.place
                            if place and pvm.classof(place) == Tr.PlaceRef then
                                local ref = place.ref
                                if ref and pvm.classof(ref) == Bind.ValueRefName and carried[ref.name] then
                                    jump_arg_map[ref.name] = inner.value
                                    has_carried_write = true
                                else
                                    inner_stmts[#inner_stmts + 1] = inner
                                end
                            else
                                inner_stmts[#inner_stmts + 1] = inner
                            end
                        else
                            inner_stmts[#inner_stmts + 1] = inner
                        end
                    end
                    if has_carried_write then
                        if #inner_stmts == 0 then
                            -- No remaining stmts, just the result
                            cleaned_stmts[#cleaned_stmts + 1] = Tr.StmtExpr(Tr.StmtSurface, expr.result)
                        else
                            cleaned_stmts[#cleaned_stmts + 1] = Tr.StmtExpr(Tr.StmtSurface,
                                Tr.ExprBlock(Tr.ExprSurface, inner_stmts, expr.result))
                        end
                    else
                        cleaned_stmts[#cleaned_stmts + 1] = stmt
                    end
                else
                    cleaned_stmts[#cleaned_stmts + 1] = stmt
                end
            else
                -- Default: keep the stmt as-is
                cleaned_stmts[#cleaned_stmts + 1] = stmt
            end
        end

        -- Build jump args from the map (only real writes, no identity)
        local args_list = {}
        for name, value in pairs(jump_arg_map) do
            args_list[#args_list + 1] = { name = name, value = value }
        end

        return args_list, cleaned_stmts
    end

    --------------------------------------------------------------------------
    -- Function lowering
    --------------------------------------------------------------------------
    local function lower_func(c_func, ctx)
        local name = c_func.declarator.name or "anon"
        local is_export = true
        if c_func.storage and c_func.storage._variant == "CStorageStatic" then
            is_export = false
        end

        -- Collect parameters
        local params = {}
        for _, d in ipairs(c_func.declarator.derived or {}) do
            if d._variant == "CDerivedFunction" then
                for i, p in ipairs(d.params) do
                    local pname = p.declarator and p.declarator.name or ("p" .. i)
                    local pty = c_param_type(p, ctx)
                    params[#params + 1] = Ty.Param(pname, pty)
                end
                if d.variadic then
                    params[#params + 1] = Ty.Param("__va", Ty.TScalar(C.ScalarRawPtr))
                end
            end
        end

        -- Result type (apply any pointer/array derived types from the declarator)
        local result_ty = wrap_decl_type(
            c_type_spec_to_moon_type(c_func.type_spec, ctx),
            c_func.declarator, ctx)
        if result_ty == Ty.TScalar(C.ScalarVoid) then
            result_ty = Ty.TScalar(C.ScalarVoid)
        end

        -- Reset per-function state
        ctx.func_name = name
        ctx.func_params = params
        ctx.func_result_ty = result_ty
        ctx.locals = {}
        ctx.address_taken = {}
        ctx.break_target = nil
        ctx.continue_target = nil

        -- Register parameters as locals
        for _, d in ipairs(c_func.declarator.derived or {}) do
            if d._variant == "CDerivedFunction" then
                for i, p in ipairs(d.params) do
                    local pname = p.declarator and p.declarator.name or ("p" .. i)
                    ctx.locals[pname] = {
                        binding = arg_binding(pname, i),
                        is_var = false,
                        c_desc = c_desc_from_spec_decl(p.type_spec, p.declarator, ctx),
                    }
                end
            end
        end

        -- Address-of analysis
        if c_func.body._variant == "CSCompound" then
            for _, bi in ipairs(c_func.body.items or {}) do
                if bi._variant == "CBlockStmt" then
                    collect_stmt_addresses(bi.stmt, ctx.address_taken)
                end
            end
        end

        -- Lower body
        local body_stmts = {}
        if c_func.body._variant == "CSCompound" then
            body_stmts = lower_block_items(c_func.body.items, ctx)
        else
            body_stmts = lower_stmt(c_func.body, ctx)
        end

        -- Ensure body ends with return if non-void
        if result_ty ~= Ty.TScalar(C.ScalarVoid) and #body_stmts > 0 then
            local last = body_stmts[#body_stmts]
            local last_cls = pvm.classof(last)
            if last_cls ~= Tr.StmtReturnValue and last_cls ~= Tr.StmtReturnVoid then
                body_stmts[#body_stmts + 1] = Tr.StmtReturnVoid(Tr.StmtSurface)
            end
        end

        if is_export then
            return Tr.FuncExport(name, params, result_ty, body_stmts)
        else
            return Tr.FuncLocal(name, params, result_ty, body_stmts)
        end
    end

    --------------------------------------------------------------------------
    -- Main entry: M.lower
    --------------------------------------------------------------------------
    function M.lower(items, ctype_facts, layout_facts, extern_funcs, module_name)
        ctx = new_context(module_name, ctype_facts, layout_facts, extern_funcs)

        -- First pass: register function names for forward references
        for _, item in ipairs(items or {}) do
            if item._variant == "CATopFuncDef" then
                local name = item.func.declarator.name
                if name then ctx.func_table[name] = true end
            end
        end

        local out = {}
        for _, item in ipairs(items or {}) do
            if item._variant == "CATopFuncDef" then
                local func = lower_func(item.func, ctx)
                out[#out + 1] = Tr.ItemFunc(func)
            elseif item._variant == "CATopDecl" then
                local decl = item.decl
                local is_typedef = decl.storage and decl.storage._variant == "CStorageTypedef"
                local is_extern = decl.storage and decl.storage._variant == "CStorageExtern"
                local is_static = decl.storage and decl.storage._variant == "CStorageStatic"
                if is_typedef then
                    for _, decltor in ipairs(decl.declarators or {}) do
                        if decltor.name then
                            local spec = decl.type_spec
                            if spec._variant == "CTyStructOrUnion" and spec.members then
                                local fields = {}
                                for _, f in ipairs(spec.members) do
                                    for _, fd in ipairs(f.declarators or {}) do
                                        if fd.declarator and fd.declarator.name then
                                            local fty = c_type_spec_to_moon_type(f.type_spec, ctx)
                                            fields[#fields + 1] = Ty.FieldDecl(fd.declarator.name, fty)
                                        end
                                    end
                                end
                                out[#out + 1] = Tr.ItemType(Tr.TypeDeclStruct(decltor.name, fields))
                            elseif spec._variant == "CTyEnum" and spec.enumerators then
                                out[#out + 1] = Tr.ItemType(Tr.TypeDeclEnumSugar(decltor.name, {}))
                            end
                        end
                    end
                elseif is_extern then
                    for _, decltor in ipairs(decl.declarators or {}) do
                        if decltor.name then
                            local has_func = false
                            for _, d in ipairs(decltor.derived or {}) do
                                if d._variant == "CDerivedFunction" then has_func = true; break end
                            end
                            if has_func then
                                out[#out + 1] = Tr.ItemExtern(
                                    Tr.ExternFunc(decltor.name, decltor.name,
                                        c_func_param_types({ declarator = decltor, type_spec = decl.type_spec }, ctx),
                                        wrap_decl_type(c_type_spec_to_moon_type(decl.type_spec, ctx), decltor, ctx)))
                            end
                        end
                    end
                else
                    for _, decltor in ipairs(decl.declarators or {}) do
                        if decltor.name then
                            local has_func = false
                            for _, d in ipairs(decltor.derived or {}) do
                                if d._variant == "CDerivedFunction" then has_func = true; break end
                            end
                            if has_func then
                                if not ctx.func_table[decltor.name] then
                                    out[#out + 1] = Tr.ItemExtern(
                                        Tr.ExternFunc(decltor.name, decltor.name,
                                            c_func_param_types({ declarator = decltor, type_spec = decl.type_spec }, ctx),
                                            wrap_decl_type(c_type_spec_to_moon_type(decl.type_spec, ctx), decltor, ctx)))
                                end
                            else
                                local ty = wrap_decl_type(c_type_spec_to_moon_type(decl.type_spec, ctx), decltor, ctx)
                                local init = lit_int("0")
                                if decltor.initializer and decltor.initializer._variant == "CInitExpr" then
                                    init = lower_expr(decltor.initializer.expr, ctx)
                                end
                                if is_static then
                                    out[#out + 1] = Tr.ItemStatic(Tr.StaticItem(decltor.name, ty, init))
                                else
                                    out[#out + 1] = Tr.ItemStatic(Tr.StaticItem(decltor.name, ty, init))
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Emit data items (string literals)
        for _, data in pairs(ctx.data_items) do
            out[#out + 1] = Tr.ItemData(data)
        end

        return Tr.Module(Tr.ModuleSurface, out)
    end

    return { lower = M.lower }
end

return M
