local asdl = require("lalin.asdl")

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.luajit_emit ~= nil then return T._lalin_api_cache.luajit_emit end

    local Core = T.LalinCore
    local Code = T.LalinCode
    local Value = T.LalinValue
    local LJ = T.LalinLuaJIT
    local Back = T.LalinBack

    local api = {}

    local function class_name(x)
        local cls = asdl.classof(x) or x
        return tostring(cls):match("Class%((.-)%)") or tostring(cls)
    end

    local function unsupported(x, where)
        error("luajit_emit: unsupported " .. (where or "node") .. " " .. class_name(x), 3)
    end

    local function sanitize(s)
        s = tostring(s or "x"):gsub("[^%w_]", "_")
        if s == "" then s = "x" end
        if s:match("^%d") then s = "_" .. s end
        return s
    end

    local function lua_string(s)
        return string.format("%q", tostring(s))
    end

    local function id_name(id)
        return "v_" .. sanitize(id.text)
    end

    local function func_name(name)
        return "fn_" .. sanitize(name)
    end

    local function func_ref_name(id)
        local text = tostring(id.text or id)
        text = text:gsub("^fn:", "")
        return func_name(text)
    end

    local function data_name(id)
        return "__lalin_data_" .. sanitize(id and (id.text or id) or "data")
    end

    local function indent(n)
        return string.rep("    ", n)
    end

    local function line(out, n, text)
        out[#out + 1] = indent(n) .. text
    end

    local is_cdata_reg

    local function literal(lit)
        local cls = asdl.classof(lit)
        if cls == Core.LitInt or cls == Core.LitFloat then return tostring(lit.raw) end
        if cls == Core.LitBool then return lit.value and "true" or "false" end
        if lit == Core.LitNil or cls == Core.LitNil then return "nil" end
        if cls == Core.LitString then return lua_string(lit.bytes) end
        unsupported(lit, "literal")
    end

    local function literal_expr(e)
        local cls = asdl.classof(e.literal)
        if cls == Core.LitInt and is_cdata_reg(e.ty) and asdl.classof(e.ty.storage) == LJ.LJCTypeScalar then
            local scalar = e.ty.storage.scalar
            if scalar == Back.BackI64 then return tostring(e.literal.raw) .. "LL" end
            if scalar == Back.BackU64 then return tostring(e.literal.raw) .. "ULL" end
        end
        return literal(e.literal)
    end

    local function ctype_spelling(ty)
        local cls = asdl.classof(ty)
        if ty == LJ.LJCTypeVoid then return "void" end
        if ty == LJ.LJCTypeBool then return "bool" end
        if cls == LJ.LJCTypeScalar then return ty.spelling end
        if cls == LJ.LJCTypePointer then
            return (ty.pointee and ctype_spelling(ty.pointee) or "void") .. "*"
        end
        if cls == LJ.LJCTypeArray then return ctype_spelling(ty.elem) .. "[" .. tostring(ty.count) .. "]" end
        if cls == LJ.LJCTypeNamed then return ty.spelling end
        if cls == LJ.LJCTypeFuncPtr then return "void (*)(void)" end
        unsupported(ty, "C type")
    end

    local function global_ref_expr(ref)
        local cls = asdl.classof(ref)
        if cls == Code.CodeGlobalRefFunc then return func_ref_name(ref.func) end
        if cls == Code.CodeGlobalRefData then return data_name(ref.data) end
        unsupported(ref, "global reference")
    end

    local function overlay_bytes(base, offset, bytes)
        offset = tonumber(offset) or 0
        bytes = tostring(bytes or "")
        return base:sub(1, offset) .. bytes .. base:sub(offset + #bytes + 1)
    end

    local function data_bytes(data)
        local bytes = string.rep("\0", tonumber(data.size or 0) or 0)
        for _, init in ipairs(data.inits or {}) do
            local cls = asdl.classof(init)
            if cls == Code.CodeDataZero then
                bytes = overlay_bytes(bytes, init.offset, string.rep("\0", tonumber(init.size or 0) or 0))
            elseif cls == Code.CodeDataBytes then
                bytes = overlay_bytes(bytes, init.offset, init.bytes)
            else
                unsupported(init, "LuaJIT data initializer")
            end
        end
        return bytes
    end

    local function emit_cdecl(decl)
        local cls = asdl.classof(decl)
        if cls == LJ.LJCDeclRaw then return decl.source end
        if cls == LJ.LJCDeclTypedef then
            return "typedef " .. ctype_spelling(decl.ty) .. " " .. decl.spelling .. ";"
        end
        if cls == LJ.LJCDeclStruct then
            local out = { decl.spelling .. " {" }
            for i = 1, #decl.fields do
                local f = decl.fields[i]
                out[#out + 1] = "  " .. ctype_spelling(f.ty) .. " " .. sanitize(f.name) .. ";"
            end
            out[#out + 1] = "};"
            return table.concat(out, "\n")
        end
        unsupported(decl, "C declaration")
    end

    local function sig_index(module)
        local out = {}
        for _, sig in ipairs(module.sigs or {}) do
            if sig.id ~= nil then out[sig.id.text] = sig end
        end
        return out
    end

    local binop = {
        [Core.BinAdd] = "+",
        [Core.BinSub] = "-",
        [Core.BinMul] = "*",
        [Core.BinDiv] = "/",
        [Core.BinRem] = "%",
    }

    local cmpop = {
        [Core.CmpEq] = "==",
        [Core.CmpNe] = "~=",
        [Core.CmpLt] = "<",
        [Core.CmpLe] = "<=",
        [Core.CmpGt] = ">",
        [Core.CmpGe] = ">=",
    }

    local function is_trace_int(phys)
        return asdl.classof(phys and phys.register) == LJ.LJRegTraceInt32
    end

    function is_cdata_reg(phys)
        return asdl.classof(phys and phys.register) == LJ.LJRegCData
    end

    local expr
    local place_expr
    local function call_bit(name, args)
        local alias = {
            tobit = "__ml_tobit",
            band = "__ml_band",
            bor = "__ml_bor",
            bxor = "__ml_bxor",
            lshift = "__ml_lshift",
            rshift = "__ml_rshift",
            arshift = "__ml_arshift",
            bnot = "__ml_bnot",
        }
        return (alias[name] or ("bit." .. name)) .. "(" .. table.concat(args, ", ") .. ")"
    end

    local function int_binary(e)
        local op = e.op
        local lhs, rhs = expr(e.lhs), expr(e.rhs)
        if is_trace_int(e.ty) then
            if op == Core.BinAdd or op == Core.BinSub or op == Core.BinMul then
                return call_bit("tobit", { "(" .. lhs .. ") " .. binop[op] .. " (" .. rhs .. ")" })
            elseif op == Core.BinBitAnd then
                return call_bit("band", { lhs, rhs })
            elseif op == Core.BinBitOr then
                return call_bit("bor", { lhs, rhs })
            elseif op == Core.BinBitXor then
                return call_bit("bxor", { lhs, rhs })
            elseif op == Core.BinShl then
                return call_bit("lshift", { lhs, rhs })
            elseif op == Core.BinLShr then
                return call_bit("rshift", { lhs, rhs })
            elseif op == Core.BinAShr then
                return call_bit("arshift", { lhs, rhs })
            elseif op == Core.BinDiv then
                return call_bit("tobit", { "(" .. lhs .. ") / (" .. rhs .. ")" })
            elseif op == Core.BinRem then
                return call_bit("tobit", { "(" .. lhs .. ") % (" .. rhs .. ")" })
            end
        elseif is_cdata_reg(e.ty) then
            if binop[op] then return "((" .. lhs .. ") " .. binop[op] .. " (" .. rhs .. "))" end
        else
            if binop[op] then return "((" .. lhs .. ") " .. binop[op] .. " (" .. rhs .. "))" end
        end
        unsupported(op, "integer binary op")
    end

    local function float_binary(e)
        local op = binop[e.op]
        if op == nil then unsupported(e.op, "float binary op") end
        return "((" .. expr(e.lhs) .. ") " .. op .. " (" .. expr(e.rhs) .. "))"
    end

    local function cast_expr(e)
        local value = expr(e.value)
        if is_trace_int(e.to) then return "bit.tobit(" .. value .. ")" end
        if e.to.register == LJ.LJRegLuaNumber then return "tonumber(" .. value .. ")" end
        if is_cdata_reg(e.to) then
            if asdl.classof(e.to.storage) == LJ.LJCTypePointer then
                return "((type(" .. value .. ") == 'table') and " .. value .. " or ffi.cast(" .. lua_string(ctype_spelling(e.to.storage)) .. ", " .. value .. "))"
            end
            return "ffi.cast(" .. lua_string(ctype_spelling(e.to.storage)) .. ", " .. value .. ")"
        end
        return value
    end

    local function record_expr(e)
        local cls = asdl.classof(e.ty.storage)
        local spelling = tostring(e.ty.storage and e.ty.storage.spelling or "")
        local closure_record = spelling:match("lj_closure_") ~= nil
        local parts = {}
        local capture_index = 0
        for i = 1, #e.fields do
            local name = e.fields[i].name
            local value = expr(e.fields[i].expr)
            parts[#parts + 1] = sanitize(name) .. " = " .. value
            if closure_record and name ~= "__lalin_fn" then
                parts[#parts + 1] = "[" .. tostring(capture_index) .. "] = " .. value
                capture_index = capture_index + 1
            end
        end
        if cls == LJ.LJCTypeNamed and not closure_record then
            return "ffi.new(" .. lua_string(e.ty.storage.spelling) .. ", { " .. table.concat(parts, ", ") .. " })"
        end
        return "{ " .. table.concat(parts, ", ") .. " }"
    end

    place_expr = function(p)
        local cls = asdl.classof(p)
        if cls == LJ.LJPlaceLocal then return id_name(p.local_id) end
        if cls == LJ.LJPlaceDeref then return "(" .. expr(p.addr) .. ")[0]" end
        if cls == LJ.LJPlaceField then return "(" .. place_expr(p.base) .. ")." .. sanitize(p.name) end
        if cls == LJ.LJPlaceIndex then
            if asdl.classof(p.base) == LJ.LJPlaceDeref then
                return "(" .. expr(p.base.addr) .. ")[" .. expr(p.index) .. "]"
            end
            local base = place_expr(p.base)
            -- If the base is already parenthesized (Deref, Field, or nested
            -- Index all produce parenthesized output), adding outer parens
            -- creates ambiguous syntax in LuaJIT.  Only wrap bare locals.
            if base:sub(1,1) == "(" then
                return base .. "[" .. expr(p.index) .. "]"
            end
            return "(" .. base .. ")[" .. expr(p.index) .. "]"
        end
        unsupported(p, "place")
    end

    local function ptr_offset_expr(e)
        local offset = tonumber(e.const_offset or 0) or 0
        local elem = tonumber(e.elem_size or 1) or 1
        local terms = { expr(e.base), "(" .. expr(e.index) .. ")" }
        if offset ~= 0 then
            if elem ~= 0 and offset % elem == 0 then
                terms[#terms + 1] = tostring(offset / elem)
            else
                unsupported(e, "byte-granular pointer offset")
            end
        end
        return "(" .. table.concat(terms, " + ") .. ")"
    end

    local function call_target_expr(target, args)
        local cls = asdl.classof(target)
        if cls == LJ.LJCallDirect then return func_ref_name(target.func) .. "(" .. table.concat(args, ", ") .. ")" end
        if cls == LJ.LJCallExtern then return "ffi.C." .. sanitize(target.extern_name) .. "(" .. table.concat(args, ", ") .. ")" end
        if cls == LJ.LJCallIndirect then return expr(target.callee) .. "(" .. table.concat(args, ", ") .. ")" end
        if cls == LJ.LJCallClosure then
            local closure = expr(target.closure)
            local call_args = { closure }
            for i = 1, #args do call_args[#call_args + 1] = args[i] end
            return "(" .. closure .. ").__lalin_fn(" .. table.concat(call_args, ", ") .. ")"
        end
        unsupported(target, "call target")
    end

    local function call_expr(e)
        local args = {}
        for i = 1, #e.args do args[i] = expr(e.args[i]) end
        return call_target_expr(e.target, args)
    end

    expr = function(e)
        local cls = asdl.classof(e)
        if cls == LJ.LJExprValue then return id_name(e.value) end
        if cls == LJ.LJExprLiteral then return literal_expr(e) end
        if cls == LJ.LJExprUnary then
            if e.op == Core.UnaryNeg then return "(-(" .. expr(e.value) .. "))" end
            if e.op == Core.UnaryNot then return "(not (" .. expr(e.value) .. "))" end
            if e.op == Core.UnaryBitNot then return call_bit("bnot", { expr(e.value) }) end
            unsupported(e.op, "unary op")
        end
        if cls == LJ.LJExprIntBinary then return int_binary(e) end
        if cls == LJ.LJExprFloatBinary then return float_binary(e) end
        if cls == LJ.LJExprCompare then
            local op = cmpop[e.op]
            if op == nil then unsupported(e.op, "compare op") end
            return "((" .. expr(e.lhs) .. ") " .. op .. " (" .. expr(e.rhs) .. "))"
        end
        if cls == LJ.LJExprSelect then
            return "(((" .. expr(e.cond) .. ") and (" .. expr(e.then_value) .. ")) or (" .. expr(e.else_value) .. "))"
        end
        if cls == LJ.LJExprCast then return cast_expr(e) end
        if cls == LJ.LJExprAddrOfPlace then return place_expr(e.place) end
        if cls == LJ.LJExprPtrOffset then return ptr_offset_expr(e) end
        if cls == LJ.LJExprLoad then return place_expr(e.place) end
        if cls == LJ.LJExprProjectField then return "(" .. expr(e.base) .. ")." .. sanitize(e.name) end
        if cls == LJ.LJExprRecord then return record_expr(e) end
        if cls == LJ.LJExprArray then
            local elems = {}
            for i = 1, #e.elems do elems[i] = "[" .. tostring(e.elems[i].index) .. "] = " .. expr(e.elems[i].expr) end
            return "{ " .. table.concat(elems, ", ") .. " }"
        end
        if cls == LJ.LJExprClosure then return "{ __lalin_fn = " .. expr(e.fn) .. ", __lalin_ctx = " .. expr(e.ctx) .. " }" end
        if cls == LJ.LJExprCall then return call_expr(e) end
        if cls == LJ.LJExprCDataCast then return "ffi.cast(" .. lua_string(ctype_spelling(e.ty)) .. ", " .. expr(e.value) .. ")" end
        if cls == LJ.LJExprGlobalRef then return global_ref_expr(e.ref) end
        unsupported(e, "expression")
    end

    local function emit_stmt(out, n, stmt)
        local cls = asdl.classof(stmt)
        if cls == LJ.LJStmtLet then
            line(out, n, "local " .. id_name(stmt.dst) .. " = " .. expr(stmt.expr))
        elseif cls == LJ.LJStmtStore then
            line(out, n, place_expr(stmt.place) .. " = " .. expr(stmt.value))
        elseif cls == LJ.LJStmtCall then
            local args = {}
            for i = 1, #stmt.args do args[i] = expr(stmt.args[i]) end
            line(out, n, call_target_expr(stmt.target, args))
        elseif cls == LJ.LJStmtEmitMachine then
            line(out, n, "__emit_machine_" .. sanitize(stmt.machine.text) .. "()")
        else
            unsupported(stmt, "statement")
        end
    end

    local function build_block_map(blocks)
        local by_id, order = {}, {}
        for i = 1, #blocks do
            by_id[blocks[i].id.text] = blocks[i]
            order[#order + 1] = blocks[i].id.text
        end
        return by_id, order
    end

    local function assign_block_args(out, n, params, args)
        for i = 1, #params do
            line(out, n, id_name(params[i].value) .. " = " .. expr(args[i]))
        end
    end

    local function collect_store_locals(body)
        local out = {}
        local seen = {}
        for _, b in ipairs(body.blocks or {}) do
            for _, stmt in ipairs(b.stmts or {}) do
                if asdl.classof(stmt) == LJ.LJStmtStore and asdl.classof(stmt.place) == LJ.LJPlaceLocal then
                    local name = id_name(stmt.place.local_id)
                    if not seen[name] then
                        seen[name] = true
                        out[#out + 1] = name
                    end
                end
            end
        end
        return out
    end

    local function emit_term(out, n, term, block_by_id)
        local cls = asdl.classof(term)
        if cls == LJ.LJTermReturn then
            local values = {}
            for i = 1, #term.values do values[i] = expr(term.values[i]) end
            line(out, n, "return " .. table.concat(values, ", "))
        elseif cls == LJ.LJTermTrap then
            line(out, n, "error(" .. lua_string(term.reason) .. ", 0)")
        elseif cls == LJ.LJTermJump then
            local dest = block_by_id[term.dest.text]
            if dest == nil then error("luajit_emit: missing jump dest " .. tostring(term.dest.text), 3) end
            assign_block_args(out, n, dest.params, term.args)
            line(out, n, "__block = " .. lua_string(term.dest.text))
        elseif cls == LJ.LJTermBranch then
            local td, ed = block_by_id[term.then_dest.text], block_by_id[term.else_dest.text]
            if td == nil or ed == nil then error("luajit_emit: missing branch dest", 3) end
            line(out, n, "if " .. expr(term.cond) .. " then")
            assign_block_args(out, n + 1, td.params, term.then_args)
            line(out, n + 1, "__block = " .. lua_string(term.then_dest.text))
            line(out, n, "else")
            assign_block_args(out, n + 1, ed.params, term.else_args)
            line(out, n + 1, "__block = " .. lua_string(term.else_dest.text))
            line(out, n, "end")
        elseif cls == LJ.LJTermSwitch then
            line(out, n, "do")
            line(out, n + 1, "local __switch = " .. expr(term.value))
            for i = 1, #term.cases do
                local case = term.cases[i]
                local prefix = i == 1 and "if" or "elseif"
                local dest = block_by_id[case.dest.text]
                if dest == nil then error("luajit_emit: missing switch dest " .. tostring(case.dest.text), 3) end
                line(out, n + 1, prefix .. " __switch == " .. literal(case.literal) .. " then")
                assign_block_args(out, n + 2, dest.params, case.args)
                line(out, n + 2, "__block = " .. lua_string(case.dest.text))
            end
            local dd = block_by_id[term.default_dest.text]
            if dd == nil then error("luajit_emit: missing switch default dest " .. tostring(term.default_dest.text), 3) end
            line(out, n + 1, "else")
            assign_block_args(out, n + 2, dd.params, term.default_args)
            line(out, n + 2, "__block = " .. lua_string(term.default_dest.text))
            line(out, n + 1, "end")
            line(out, n, "end")
        else
            unsupported(term, "term")
        end
    end

    local function emit_blocks_body(out, n, body)
        local block_by_id, order = build_block_map(body.blocks)
        line(out, n, "local __block = " .. lua_string(body.entry.text))
        for _, local_name in ipairs(collect_store_locals(body)) do line(out, n, "local " .. local_name) end
        for _, key in ipairs(order) do
            local b = block_by_id[key]
            for i = 1, #b.params do line(out, n, "local " .. id_name(b.params[i].value)) end
        end
        line(out, n, "while true do")
        for i, key in ipairs(order) do
            local b = block_by_id[key]
            line(out, n + 1, (i == 1 and "if" or "elseif") .. " __block == " .. lua_string(key) .. " then")
            for j = 1, #b.stmts do emit_stmt(out, n + 2, b.stmts[j]) end
            emit_term(out, n + 2, b.term, block_by_id)
        end
        line(out, n + 1, "else")
        line(out, n + 2, "error('unknown LuaJIT block '..tostring(__block), 0)")
        line(out, n + 1, "end")
        line(out, n, "end")
    end

    local function machine_map(func)
        local out = {}
        for i = 1, #(func.machines or {}) do out[func.machines[i].id.text] = func.machines[i] end
        return out
    end

    local function trace_int_reg(phys)
        local reg = phys and phys.register
        if asdl.classof(reg) == LJ.LJRegTraceInt32 then return reg end
        return nil
    end

    local function reduction_binary_op(op)
        if op == Value.ReductionAdd then return Core.BinAdd end
        if op == Value.ReductionMul then return Core.BinMul end
        if op == Value.ReductionAnd then return Core.BinBitAnd end
        if op == Value.ReductionOr then return Core.BinBitOr end
        if op == Value.ReductionXor then return Core.BinBitXor end
        return nil
    end

    local function trace_norm_func(reg)
        if reg.bits == 8 then return reg.signedness == Code.CodeSigned and "__ml_i8" or "__ml_u8" end
        if reg.bits == 16 then return reg.signedness == Code.CodeSigned and "__ml_i16" or "__ml_u16" end
        if reg.bits == 32 then return reg.signedness == Code.CodeSigned and "__ml_tobit" or "__ml_u32" end
        return nil
    end

    local function normalize_trace(reg, raw)
        local fn = trace_norm_func(reg)
        if fn == nil then error("luajit_emit: unsupported trace-int width " .. tostring(reg and reg.bits), 3) end
        return fn .. "(" .. raw .. ")"
    end

    local function signed_min(reg)
        if reg.bits == 8 then return "-128" end
        if reg.bits == 16 then return "-32768" end
        if reg.bits == 32 then return "-2147483648" end
        return nil
    end

    local function signed_max(reg)
        if reg.bits == 8 then return "127" end
        if reg.bits == 16 then return "32767" end
        if reg.bits == 32 then return "2147483647" end
        return nil
    end

    local function unsigned_max(reg)
        if reg.bits == 8 then return "255" end
        if reg.bits == 16 then return "65535" end
        if reg.bits == 32 then return "4294967295" end
        return nil
    end

    local function reduction_identity(op, reg)
        if op == Value.ReductionAdd or op == Value.ReductionOr or op == Value.ReductionXor then return normalize_trace(reg, "0") end
        if op == Value.ReductionMul then return normalize_trace(reg, "1") end
        if op == Value.ReductionAnd then return normalize_trace(reg, "-1") end
        if op == Value.ReductionMin then
            if reg.signedness == Code.CodeSigned then return signed_max(reg) end
            return unsigned_max(reg)
        end
        if op == Value.ReductionMax then
            if reg.signedness == Code.CodeSigned then return signed_min(reg) end
            return "0"
        end
        return nil
    end

    local function reduction_update(op, reg, acc, value)
        if op == Value.ReductionAdd then return normalize_trace(reg, "(" .. acc .. ") + (" .. value .. ")") end
        if op == Value.ReductionMul then
            if reg.bits == 32 then return normalize_trace(reg, "__ml_mul32(" .. acc .. ", " .. value .. ")") end
            return normalize_trace(reg, "(" .. acc .. ") * (" .. value .. ")")
        end
        if op == Value.ReductionAnd then return normalize_trace(reg, "__ml_band(" .. acc .. ", " .. value .. ")") end
        if op == Value.ReductionOr then return normalize_trace(reg, "__ml_bor(" .. acc .. ", " .. value .. ")") end
        if op == Value.ReductionXor then return normalize_trace(reg, "__ml_bxor(" .. acc .. ", " .. value .. ")") end
        if op == Value.ReductionMin or op == Value.ReductionMax then
            local cmp = op == Value.ReductionMin and "<=" or ">="
            return "(((" .. acc .. ") " .. cmp .. " (" .. value .. ")) and (" .. acc .. ") or (" .. value .. "))"
        end
        return nil
    end

    local function fold_reduce_support(op, sem, elem_ty, result_ty)
        local elem_reg = trace_int_reg(elem_ty)
        local result_reg = trace_int_reg(result_ty)
        if elem_reg == nil or result_reg == nil then
            return false, "scalar LuaJIT fallback currently supports trace-int reductions only"
        end
        if elem_reg.bits ~= result_reg.bits or elem_reg.signedness ~= result_reg.signedness then
            return false, "scalar LuaJIT fallback requires matching element/result trace-int types"
        end
        if result_reg.bits ~= 8 and result_reg.bits ~= 16 and result_reg.bits ~= 32 then
            return false, "scalar LuaJIT fallback supports only 8/16/32-bit trace-int reductions"
        end
        if reduction_binary_op(op) == nil and op ~= Value.ReductionMin and op ~= Value.ReductionMax then
            return false, "scalar LuaJIT fallback does not support this reduction op"
        end
        if (op == Value.ReductionAdd or op == Value.ReductionMul) and (sem == nil or sem.overflow ~= Code.CodeIntWrap) then
            return false, "add/mul scalar LuaJIT fallback requires wrapping integer semantics"
        end
        return true, nil
    end

    local function emit_trace_fold_reduce_array(out, n, prefix, arr, start_expr, stop_expr, step_expr, init, lanes, result_name, item_id, reduction, result_ty)
        local reg = trace_int_reg(result_ty)
        lanes = tonumber(lanes) or 8
        if lanes < 1 then error("luajit_emit: vector reduce lanes must be >= 1", 3) end
        local step_num = tonumber(step_expr)
        if step_num == nil or step_num <= 0 then error("luajit_emit: vector reduce scalar fallback currently requires a positive constant step", 3) end
        local identity = reduction_identity(reduction, reg)
        if identity == nil then error("luajit_emit: vector reduce has no scalar identity for reduction", 3) end
        local len = "__len_" .. prefix
        local idx = "__i_" .. prefix
        local limit = "__limit_" .. prefix
        local acc_names = {}
        for i = 0, lanes - 1 do acc_names[i + 1] = result_name .. tostring(i) end
        line(out, n, "local " .. idx .. " = " .. start_expr)
        line(out, n, "local " .. len .. " = " .. stop_expr)
        line(out, n, "local " .. limit .. " = " .. len .. " - " .. tostring(lanes * step_num))
        line(out, n, "local " .. acc_names[1] .. " = " .. normalize_trace(reg, expr(init)))
        for i = 2, lanes do line(out, n, "local " .. acc_names[i] .. " = " .. identity) end
        line(out, n, "while " .. idx .. " <= " .. limit .. " do")
        for i = 0, lanes - 1 do
            local item = arr .. "[" .. idx .. (i == 0 and "" or (" + " .. tostring(i * step_num))) .. "]"
            line(out, n + 1, acc_names[i + 1] .. " = " .. reduction_update(reduction, reg, acc_names[i + 1], item))
        end
        line(out, n + 1, idx .. " = " .. idx .. " + " .. tostring(lanes * step_num))
        line(out, n, "end")
        line(out, n, "local " .. result_name .. " = " .. acc_names[1])
        for i = 2, lanes do line(out, n, result_name .. " = " .. reduction_update(reduction, reg, result_name, acc_names[i])) end
        line(out, n, "while " .. idx .. " < " .. len .. " do")
        local item_name = id_name(item_id)
        line(out, n + 1, "local " .. item_name .. " = " .. arr .. "[" .. idx .. "]")
        line(out, n + 1, result_name .. " = " .. reduction_update(reduction, reg, result_name, item_name))
        line(out, n + 1, idx .. " = " .. idx .. " + " .. tostring(step_num))
        line(out, n, "end")
    end

    local function emit_machine_loop(out, n, machines, machine_id, item_name, body_cb)
        local m = machines[machine_id.text]
        if m == nil then error("luajit_emit: missing machine " .. tostring(machine_id.text), 3) end
        local k = m.op
        local cls = asdl.classof(k)
        if cls == LJ.LJMachineSourceArray then
            local arr = id_name(k.array)
            local len = k.length and expr(k.length) or ("#" .. arr)
            local idx = "__i_" .. sanitize(m.id.text)
            line(out, n, "for " .. idx .. " = 0, (" .. len .. ") - 1 do")
            line(out, n + 1, "local " .. item_name .. " = " .. arr .. "[" .. idx .. "]")
            body_cb(n + 1, item_name)
            line(out, n, "end")
        elseif cls == LJ.LJMachineSourceRange then
            local idx = item_name
            line(out, n, "for " .. idx .. " = " .. expr(k.start) .. ", " .. expr(k.stop) .. ", " .. expr(k.step) .. " do")
            body_cb(n + 1, idx)
            line(out, n, "end")
        elseif cls == LJ.LJMachineMap then
            emit_machine_loop(out, n, machines, k.input, id_name(k.binding), function(inner_n, source_value)
                local mapped = "__mapped_" .. sanitize(m.id.text)
                line(out, inner_n, "local " .. mapped .. " = " .. expr(k.expr))
                body_cb(inner_n, mapped)
            end)
        elseif cls == LJ.LJMachineFilter then
            emit_machine_loop(out, n, machines, k.input, id_name(k.binding), function(inner_n, source_value)
                line(out, inner_n, "if " .. expr(k.pred) .. " then")
                body_cb(inner_n + 1, source_value)
                line(out, inner_n, "end")
            end)
        elseif cls == LJ.LJMachineConcat then
            for i = 1, #k.inputs do emit_machine_loop(out, n, machines, k.inputs[i], item_name, body_cb) end
        elseif cls == LJ.LJMachineFold then
            local source = machines[k.input.text]
            local source_op = source and source.op
            local source_cls = asdl.classof(source_op)
            local step_cls = asdl.classof(k.step)
            local sem_ok = step_cls == LJ.LJExprIntBinary
            local reduction = step_cls == LJ.LJExprIntBinary and (
                k.step.op == Core.BinAdd and Value.ReductionAdd
                or k.step.op == Core.BinMul and Value.ReductionMul
                or k.step.op == Core.BinBitAnd and Value.ReductionAnd
                or k.step.op == Core.BinBitOr and Value.ReductionOr
                or k.step.op == Core.BinBitXor and Value.ReductionXor
            ) or nil
            local support_ok = false
            if sem_ok and reduction ~= nil then support_ok = fold_reduce_support(reduction, k.step.semantics, k.step.ty, k.step.ty) end
            local function is_value(e, id)
                return asdl.classof(e) == LJ.LJExprValue and e.value == id
            end
            local expr_ok = step_cls == LJ.LJExprIntBinary
                and ((is_value(k.step.lhs, k.acc) and is_value(k.step.rhs, k.item))
                    or (is_value(k.step.lhs, k.item) and is_value(k.step.rhs, k.acc)))
            if source_cls == LJ.LJMachineSourceArray and source_op.length ~= nil and sem_ok and support_ok and expr_ok then
                local prefix = sanitize(m.id.text)
                local arr = id_name(source_op.array)
                local acc = id_name(k.acc)
                emit_trace_fold_reduce_array(out, n, prefix, arr, "0", expr(source_op.length), "1", k.init, 8, acc, k.item, reduction, k.step.ty)
                body_cb(n, acc)
                return
            end
            local acc = id_name(k.acc)
            line(out, n, "local " .. acc .. " = " .. expr(k.init))
            emit_machine_loop(out, n, machines, k.input, id_name(k.item), function(inner_n, source_value)
                line(out, inner_n, acc .. " = " .. expr(k.step))
            end)
            body_cb(n, acc)
        elseif cls == LJ.LJMachineOne then
            local one = "__one_" .. sanitize(m.id.text)
            line(out, n, "local " .. one .. " = " .. expr(k.value))
            body_cb(n, one)
        elseif cls == LJ.LJMachineEmpty then
            return
        elseif cls == LJ.LJMachineStencilCall then
            local symbol = k.artifact.symbol.text
            line(out, n, "if __lalin_luajit_stencil_symbols[" .. lua_string(symbol) .. "] == nil then error(" .. lua_string("missing LalinStencil symbol " .. symbol) .. ", 0) end")
            local args = {}
            for i = 1, #k.args do args[i] = expr(k.args[i]) end
            body_cb(n, "__lalin_luajit_stencil_symbols[" .. lua_string(symbol) .. "](" .. table.concat(args, ", ") .. ")")
        elseif cls == LJ.LJMachineStencilEffect then
            local symbol = k.artifact.symbol.text
            line(out, n, "if __lalin_luajit_stencil_symbols[" .. lua_string(symbol) .. "] == nil then error(" .. lua_string("missing LalinStencil symbol " .. symbol) .. ", 0) end")
            local args = {}
            for i = 1, #k.args do args[i] = expr(k.args[i]) end
            line(out, n, "__lalin_luajit_stencil_symbols[" .. lua_string(symbol) .. "](" .. table.concat(args, ", ") .. ")")
            body_cb(n, "nil")
        else
            unsupported(k, "machine")
        end
    end

    local function emit_machine_body(out, n, func, body)
        local machines = machine_map(func)
        local term = body.terminal
        local tcls = asdl.classof(term)
        if tcls == LJ.LJTerminalFold then
            local acc = "__terminal_acc"
            line(out, n, "local " .. acc .. " = " .. expr(term.init))
            emit_machine_loop(out, n, machines, body.machine, "__terminal_item", function(inner_n, item)
                line(out, inner_n, "local v_item = " .. item)
                line(out, inner_n, acc .. " = " .. expr(term.step))
            end)
            line(out, n, "return " .. acc)
        elseif tcls == LJ.LJTerminalCollect then
            line(out, n, "local __out = {}")
            emit_machine_loop(out, n, machines, body.machine, "__terminal_item", function(inner_n, item)
                line(out, inner_n, "__out[#__out + 1] = " .. item)
            end)
            line(out, n, "return __out")
        elseif tcls == LJ.LJTerminalFirst then
            local m = machines[body.machine.text]
            local mcls = m ~= nil and asdl.classof(m.op) or nil
            if m ~= nil and mcls == LJ.LJMachineStencilEffect and term.default == nil then
                emit_machine_loop(out, n, machines, body.machine, "__terminal_item", function() end)
                line(out, n, "return")
                return
            end
            if m ~= nil and mcls == LJ.LJMachineStencilCall and term.default == nil then
                emit_machine_loop(out, n, machines, body.machine, "__terminal_item", function(inner_n, item)
                    line(out, inner_n, "return " .. item)
                end)
                return
            end
            if m ~= nil and mcls == LJ.LJMachineFold and term.default == nil then
                emit_machine_loop(out, n, machines, body.machine, "__terminal_item", function(inner_n, item)
                    line(out, inner_n, "return " .. item)
                end)
                return
            end
            line(out, n, "local __first_set = false")
            line(out, n, "local __first_value = nil")
            emit_machine_loop(out, n, machines, body.machine, "__terminal_item", function(inner_n, item)
                line(out, inner_n, "if not __first_set then")
                line(out, inner_n + 1, "__first_value = " .. item)
                line(out, inner_n + 1, "__first_set = true")
                line(out, inner_n, "end")
            end)
            if term.default ~= nil then
                line(out, n, "if __first_set then return __first_value else return " .. expr(term.default) .. " end")
            else
                line(out, n, "return __first_value")
            end
        else
            unsupported(term, "machine terminal")
        end
    end

    local function emit_func(out, n, func)
        local params = {}
        for i = 1, #func.params do params[i] = id_name(func.params[i].value) end
        line(out, n, func_name(func.name) .. " = function(" .. table.concat(params, ", ") .. ")")
        local body_cls = asdl.classof(func.body)
        if body_cls == LJ.LJBodyBlocks then
            emit_blocks_body(out, n + 1, func.body)
        elseif body_cls == LJ.LJBodyMachine then
            emit_machine_body(out, n + 1, func, func.body)
        else
            unsupported(func.body, "function body")
        end
        line(out, n, "end")
    end

    local function native_c_string(s)
        return string.format("%q", tostring(s))
    end

    local function native_c_name(prefix, name)
        return "__lalin_native_" .. prefix .. "_" .. sanitize(name)
    end

    local function native_param_decl(param)
        return ctype_spelling(param.ty.abi) .. " " .. id_name(param.value)
    end

    local native_expr
    local native_place_expr

    local native_binop = {
        [Core.BinAdd] = "+",
        [Core.BinSub] = "-",
        [Core.BinMul] = "*",
        [Core.BinDiv] = "/",
        [Core.BinRem] = "%",
        [Core.BinBitAnd] = "&",
        [Core.BinBitOr] = "|",
        [Core.BinBitXor] = "^",
        [Core.BinShl] = "<<",
        [Core.BinLShr] = ">>",
        [Core.BinAShr] = ">>",
    }

    local native_cmpop = {
        [Core.CmpEq] = "==",
        [Core.CmpNe] = "!=",
        [Core.CmpLt] = "<",
        [Core.CmpLe] = "<=",
        [Core.CmpGt] = ">",
        [Core.CmpGe] = ">=",
    }

    local function native_ptr_offset_expr(e)
        local offset = tonumber(e.const_offset or 0) or 0
        local elem = tonumber(e.elem_size or 1) or 1
        local terms = { native_expr(e.base), "(" .. native_expr(e.index) .. ")" }
        if offset ~= 0 then
            if elem ~= 0 and offset % elem == 0 then
                terms[#terms + 1] = tostring(offset / elem)
            else
                unsupported(e, "native residual byte-granular pointer offset")
            end
        end
        return "(" .. table.concat(terms, " + ") .. ")"
    end

    native_place_expr = function(p)
        local cls = asdl.classof(p)
        if cls == LJ.LJPlaceValue then return id_name(p.value) end
        if cls == LJ.LJPlaceDeref then return "(*(" .. native_expr(p.addr) .. "))" end
        if cls == LJ.LJPlaceField then return "(" .. native_place_expr(p.base) .. ")." .. sanitize(p.name) end
        if cls == LJ.LJPlaceIndex then return "(" .. native_place_expr(p.base) .. ")[" .. native_expr(p.index) .. "]" end
        unsupported(p, "native residual place")
    end

    native_expr = function(e)
        local cls = asdl.classof(e)
        if cls == LJ.LJExprValue then return id_name(e.value) end
        if cls == LJ.LJExprLiteral then return literal_expr(e) end
        if cls == LJ.LJExprUnary then
            if e.op == Core.UnaryNeg then return "(-(" .. native_expr(e.value) .. "))" end
            if e.op == Core.UnaryNot then return "(!(" .. native_expr(e.value) .. "))" end
            if e.op == Core.UnaryBitNot then return "(~(" .. native_expr(e.value) .. "))" end
            unsupported(e.op, "native residual unary op")
        end
        if cls == LJ.LJExprIntBinary or cls == LJ.LJExprFloatBinary then
            local op = native_binop[e.op]
            if op == nil then unsupported(e.op, "native residual binary op") end
            return "((" .. native_expr(e.lhs) .. ") " .. op .. " (" .. native_expr(e.rhs) .. "))"
        end
        if cls == LJ.LJExprCompare then
            local op = native_cmpop[e.op]
            if op == nil then unsupported(e.op, "native residual compare op") end
            return "((" .. native_expr(e.lhs) .. ") " .. op .. " (" .. native_expr(e.rhs) .. "))"
        end
        if cls == LJ.LJExprSelect then
            return "((" .. native_expr(e.cond) .. ") ? (" .. native_expr(e.then_value) .. ") : (" .. native_expr(e.else_value) .. "))"
        end
        if cls == LJ.LJExprCast then
            return "((" .. ctype_spelling(e.to.abi) .. ")(" .. native_expr(e.value) .. "))"
        end
        if cls == LJ.LJExprCDataCast then
            return "((" .. ctype_spelling(e.ty) .. ")(" .. native_expr(e.value) .. "))"
        end
        if cls == LJ.LJExprAddrOfPlace then return "(&(" .. native_place_expr(e.place) .. "))" end
        if cls == LJ.LJExprPtrOffset then return native_ptr_offset_expr(e) end
        if cls == LJ.LJExprLoad then return native_place_expr(e.place) end
        unsupported(e, "native residual expression")
    end

    local function c_signature_parts(symbol, c_signature)
        local sig = tostring(c_signature or "")
        local ret, params = sig:match("^%s*(.-)%s*%(%s*%*%s*%)%s*%((.*)%)%s*$")
        if ret == nil then
            local direct_ret, direct_name, direct_params = sig:match("^%s*(.-)%s+([_%a][_%w]*)%s*%((.*)%)%s*;?%s*$")
            if direct_ret ~= nil and direct_name == symbol then
                ret, params = direct_ret, direct_params
            end
        end
        if ret == nil then error("luajit_emit: cannot derive C prototype from stencil signature " .. sig, 3) end
        return ret, params
    end

    local function pattern_escape(s)
        return (tostring(s):gsub("([^%w])", "%%%1"))
    end

    local function machine_by_id(func)
        local out = {}
        for _, machine in ipairs(func.machines or {}) do out[machine.id.text] = machine end
        return out
    end

    local function native_residual_candidate(func)
        if asdl.classof(func.body) ~= LJ.LJBodyMachine then return nil end
        local term = func.body.terminal
        if asdl.classof(term) ~= LJ.LJTerminalFirst or term.default ~= nil then return nil end
        local machine = machine_by_id(func)[func.body.machine.text]
        local op = machine and machine.op or nil
        local cls = asdl.classof(op)
        if cls == LJ.LJMachineStencilCall or cls == LJ.LJMachineStencilEffect then return op, cls end
        return nil
    end

    local function native_wrapper_result_type(func, sig, op, op_cls)
        if op_cls == LJ.LJMachineStencilEffect then return "void" end
        local result = op.result_ty or (sig and sig.result)
        if result == nil then return "void" end
        return ctype_spelling(result.abi)
    end

    local function native_wrapper_source(func, sig, op, op_cls)
        local wrapper = native_c_name("fn", func.name)
        local ret = native_wrapper_result_type(func, sig, op, op_cls)
        local params = {}
        for i = 1, #func.params do params[i] = native_param_decl(func.params[i]) end
        local args = {}
        for i = 1, #op.args do args[i] = native_expr(op.args[i]) end
        local symbol = op.artifact.symbol.text
        local stencil_ret, stencil_params = c_signature_parts(symbol, op.artifact.c_signature)
        local out = {
            stencil_ret .. " " .. symbol .. "(" .. stencil_params .. ");",
            "",
            ret .. " " .. wrapper .. "(" .. (#params > 0 and table.concat(params, ", ") or "void") .. ") {",
        }
        if op_cls == LJ.LJMachineStencilEffect then
            out[#out + 1] = "  " .. symbol .. "(" .. table.concat(args, ", ") .. ");"
            out[#out + 1] = "}"
        elseif ret == "void" then
            out[#out + 1] = "  " .. symbol .. "(" .. table.concat(args, ", ") .. ");"
            out[#out + 1] = "}"
        else
            out[#out + 1] = "  return " .. symbol .. "(" .. table.concat(args, ", ") .. ");"
            out[#out + 1] = "}"
        end
        return table.concat(out, "\n"), wrapper, symbol
    end

    local function native_func_pointer_ctype(func, sig, op, op_cls)
        local ret = native_wrapper_result_type(func, sig, op, op_cls)
        local params = {}
        for i = 1, #func.params do params[i] = ctype_spelling(func.params[i].ty.abi) end
        return ret .. " (*)(" .. (#params > 0 and table.concat(params, ", ") or "void") .. ")"
    end

    local function c_func_name(name)
        return sanitize(name)
    end

    local function c_func_ref_name(ctx, id)
        local text = tostring(id and (id.text or id) or "")
        local mapped = ctx and ctx.func_symbol_by_id and ctx.func_symbol_by_id[text]
        if mapped ~= nil then return mapped end
        text = text:gsub("^fn:", ""):gsub("^func:", ""):gsub("^function:", "")
        return c_func_name(text)
    end

    local function c_label(id)
        return "bb_" .. sanitize(id.text or id)
    end

    local function c_xfer_name(block, index)
        return "__xfer_" .. sanitize(block.id.text) .. "_" .. tostring(index)
    end

    local function c_literal(lit, phys)
        local cls = asdl.classof(lit)
        if cls == Core.LitInt then
            local suffix = ""
            local storage = phys and phys.storage
            if asdl.classof(storage) == LJ.LJCTypeScalar then
                local scalar = storage.scalar
                if scalar == Back.BackI64 then suffix = "LL"
                elseif scalar == Back.BackU64 then suffix = "ULL" end
            end
            return tostring(lit.raw) .. suffix
        end
        if cls == Core.LitFloat then return tostring(lit.raw) end
        if cls == Core.LitBool then return lit.value and "1" or "0" end
        if lit == Core.LitNil or cls == Core.LitNil then return "0" end
        if cls == Core.LitString then
            local out = { '"' }
            for i = 1, #lit.bytes do
                local b = lit.bytes:byte(i)
                if b == 34 then out[#out + 1] = '\\"'
                elseif b == 92 then out[#out + 1] = "\\\\"
                elseif b == 10 then out[#out + 1] = "\\n"
                elseif b == 13 then out[#out + 1] = "\\r"
                elseif b == 9 then out[#out + 1] = "\\t"
                elseif b >= 32 and b <= 126 then out[#out + 1] = string.char(b)
                else out[#out + 1] = string.format("\\x%02x", b) end
            end
            out[#out + 1] = '"'
            return table.concat(out)
        end
        unsupported(lit, "C literal")
    end

    local function c_decl(ty, name)
        if asdl.classof(ty) == LJ.LJCTypeArray then
            return ctype_spelling(ty.elem) .. " " .. name .. "[" .. tostring(ty.count) .. "]"
        end
        return ctype_spelling(ty) .. " " .. name
    end

    local function c_param_decl(param)
        return c_decl(param.ty.abi, id_name(param.value))
    end

    local function c_result_type(sig)
        return sig and sig.result and ctype_spelling(sig.result.abi) or "void"
    end

    local c_expr
    local c_place_expr

    local function c_unsigned_type(bits)
        bits = tonumber(bits)
        if bits == 8 then return "uint8_t" end
        if bits == 16 then return "uint16_t" end
        if bits == 32 then return "uint32_t" end
        if bits == 64 then return "uint64_t" end
        return nil
    end

    local function c_wrapping_binary(e, lhs, rhs, op)
        local sem_ty = e.ty and e.ty.semantic
        if asdl.classof(sem_ty) ~= Code.CodeTyInt then return nil end
        if sem_ty.signedness ~= Code.CodeSigned then return nil end
        if e.semantics == nil or e.semantics.overflow ~= Code.CodeIntWrap then return nil end
        if op ~= "+" and op ~= "-" and op ~= "*" then return nil end
        local uty = c_unsigned_type(sem_ty.bits)
        if uty == nil then return nil end
        local cty = ctype_spelling(e.ty.abi)
        return "((" .. cty .. ")((" .. uty .. ")(" .. lhs .. ") " .. op .. " (" .. uty .. ")(" .. rhs .. ")))"
    end

    local function c_int_binary(ctx, e)
        local op = native_binop[e.op]
        if op == nil then unsupported(e.op, "C integer binary op") end
        local lhs, rhs = c_expr(ctx, e.lhs), c_expr(ctx, e.rhs)
        return c_wrapping_binary(e, lhs, rhs, op) or "((" .. lhs .. ") " .. op .. " (" .. rhs .. "))"
    end

    local function c_call_target_expr(ctx, target, args)
        local cls = asdl.classof(target)
        if cls == LJ.LJCallDirect then return c_func_ref_name(ctx, target.func) .. "(" .. table.concat(args, ", ") .. ")" end
        if cls == LJ.LJCallExtern then return sanitize(target.extern_name) .. "(" .. table.concat(args, ", ") .. ")" end
        if cls == LJ.LJCallIndirect then return c_expr(ctx, target.callee) .. "(" .. table.concat(args, ", ") .. ")" end
        unsupported(target, "C call target")
    end

    local function c_call_expr(ctx, e)
        local args = {}
        for i = 1, #e.args do args[i] = c_expr(ctx, e.args[i]) end
        return c_call_target_expr(ctx, e.target, args)
    end

    local function c_record_expr(ctx, e)
        local fields = {}
        for i = 1, #e.fields do
            fields[#fields + 1] = "." .. sanitize(e.fields[i].name) .. " = " .. c_expr(ctx, e.fields[i].expr)
        end
        return "((" .. ctype_spelling(e.ty.abi) .. "){ " .. table.concat(fields, ", ") .. " })"
    end

    c_place_expr = function(ctx, p)
        local cls = asdl.classof(p)
        if cls == LJ.LJPlaceLocal then return id_name(p.local_id) end
        if cls == LJ.LJPlaceGlobal then return sanitize(p.global.text) end
        if cls == LJ.LJPlaceData then return data_name(p.data) end
        if cls == LJ.LJPlaceDeref then return "(*(" .. c_expr(ctx, p.addr) .. "))" end
        if cls == LJ.LJPlaceField then return "(" .. c_place_expr(ctx, p.base) .. ")." .. sanitize(p.name) end
        if cls == LJ.LJPlaceIndex then
            if asdl.classof(p.base) == LJ.LJPlaceDeref then
                return "(" .. c_expr(ctx, p.base.addr) .. ")[" .. c_expr(ctx, p.index) .. "]"
            end
            return "(" .. c_place_expr(ctx, p.base) .. ")[" .. c_expr(ctx, p.index) .. "]"
        end
        if cls == LJ.LJPlaceBytes then
            return "(*(" .. ctype_spelling(p.ty.abi) .. "*)((char*)(" .. c_expr(ctx, p.base) .. ") + " .. tostring(p.offset or 0) .. "))"
        end
        unsupported(p, "C place")
    end

    local function c_ptr_offset_expr(ctx, e)
        local base = c_expr(ctx, e.base)
        local index = c_expr(ctx, e.index)
        local elem = tonumber(e.elem_size or 1) or 1
        local offset = tonumber(e.const_offset or 0) or 0
        return "((" .. ctype_spelling(e.ptr_ty.abi) .. ")((char*)(" .. base .. ") + (" .. index .. ") * " .. tostring(elem) .. " + " .. tostring(offset) .. "))"
    end

    c_expr = function(ctx, e)
        local cls = asdl.classof(e)
        if cls == LJ.LJExprValue then return id_name(e.value) end
        if cls == LJ.LJExprLiteral then return c_literal(e.literal, e.ty) end
        if cls == LJ.LJExprUnary then
            if e.op == Core.UnaryNeg then return "(-(" .. c_expr(ctx, e.value) .. "))" end
            if e.op == Core.UnaryNot then return "(!(" .. c_expr(ctx, e.value) .. "))" end
            if e.op == Core.UnaryBitNot then return "(~(" .. c_expr(ctx, e.value) .. "))" end
            unsupported(e.op, "C unary op")
        end
        if cls == LJ.LJExprIntBinary then return c_int_binary(ctx, e) end
        if cls == LJ.LJExprFloatBinary then
            local op = native_binop[e.op]
            if op == nil then unsupported(e.op, "C float binary op") end
            return "((" .. c_expr(ctx, e.lhs) .. ") " .. op .. " (" .. c_expr(ctx, e.rhs) .. "))"
        end
        if cls == LJ.LJExprCompare then
            local op = native_cmpop[e.op]
            if op == nil then unsupported(e.op, "C compare op") end
            return "((" .. c_expr(ctx, e.lhs) .. ") " .. op .. " (" .. c_expr(ctx, e.rhs) .. "))"
        end
        if cls == LJ.LJExprSelect then return "((" .. c_expr(ctx, e.cond) .. ") ? (" .. c_expr(ctx, e.then_value) .. ") : (" .. c_expr(ctx, e.else_value) .. "))" end
        if cls == LJ.LJExprCast then return "((" .. ctype_spelling(e.to.abi) .. ")(" .. c_expr(ctx, e.value) .. "))" end
        if cls == LJ.LJExprCDataCast then return "((" .. ctype_spelling(e.ty) .. ")(" .. c_expr(ctx, e.value) .. "))" end
        if cls == LJ.LJExprAddrOfPlace then return "(&(" .. c_place_expr(ctx, e.place) .. "))" end
        if cls == LJ.LJExprPtrOffset then return c_ptr_offset_expr(ctx, e) end
        if cls == LJ.LJExprLoad then return c_place_expr(ctx, e.place) end
        if cls == LJ.LJExprProjectField then return "(" .. c_expr(ctx, e.base) .. ")." .. sanitize(e.name) end
        if cls == LJ.LJExprRecord then return c_record_expr(ctx, e) end
        if cls == LJ.LJExprArray then
            local elems = {}
            for i = 1, #e.elems do elems[#elems + 1] = "[" .. tostring(e.elems[i].index) .. "] = " .. c_expr(ctx, e.elems[i].expr) end
            return "((" .. ctype_spelling(e.ty.abi) .. "){ " .. table.concat(elems, ", ") .. " })"
        end
        if cls == LJ.LJExprCall then return c_call_expr(ctx, e) end
        if cls == LJ.LJExprGlobalRef then
            local rcls = asdl.classof(e.ref)
            if rcls == Code.CodeGlobalRefFunc then return c_func_ref_name(ctx, e.ref.func) end
            if rcls == Code.CodeGlobalRefData then return data_name(e.ref.data) end
        end
        unsupported(e, "C expression")
    end

    local function c_stencil_call_expr(ctx, op)
        local args = {}
        for i = 1, #op.args do args[i] = c_expr(ctx, op.args[i]) end
        return op.artifact.symbol.text .. "(" .. table.concat(args, ", ") .. ")"
    end

    local function c_stencil_wrapper_source(ctx, func, sig, op, op_cls)
        local ret = native_wrapper_result_type(func, sig, op, op_cls)
        local params = {}
        for i = 1, #func.params do params[i] = c_param_decl(func.params[i]) end
        local call = c_stencil_call_expr(ctx, op)
        local out = { ret .. " " .. c_func_name(func.name) .. "(" .. (#params > 0 and table.concat(params, ", ") or "void") .. ") {" }
        if op_cls == LJ.LJMachineStencilEffect or ret == "void" then
            out[#out + 1] = "    " .. call .. ";"
            out[#out + 1] = "}"
        else
            out[#out + 1] = "    return " .. call .. ";"
            out[#out + 1] = "}"
        end
        return table.concat(out, "\n")
    end

    local function c_emit_transfer(out, n, ctx, block, args)
        if #block.params ~= #(args or {}) then error("luajit_emit: C block transfer arity mismatch for " .. tostring(block.id.text), 3) end
        for i = 1, #block.params do
            line(out, n, c_xfer_name(block, i) .. " = " .. c_expr(ctx, args[i]) .. ";")
        end
        line(out, n, "goto " .. c_label(block.id) .. ";")
    end

    local function c_emit_machine_stmt(out, n, ctx, machine_id)
        local machine = ctx.machine_by_id[machine_id.text]
        if machine == nil then error("luajit_emit: missing C machine " .. tostring(machine_id.text), 3) end
        local op = machine.op
        local cls = asdl.classof(op)
        if cls == LJ.LJMachineStencilEffect or cls == LJ.LJMachineStencilCall then
            line(out, n, c_stencil_call_expr(ctx, op) .. ";")
            return
        end
        unsupported(op, "C emitted machine")
    end

    local function c_emit_stmt(out, n, ctx, stmt)
        local cls = asdl.classof(stmt)
        if cls == LJ.LJStmtLet then
            line(out, n, id_name(stmt.dst) .. " = " .. c_expr(ctx, stmt.expr) .. ";")
        elseif cls == LJ.LJStmtStore then
            line(out, n, c_place_expr(ctx, stmt.place) .. " = " .. c_expr(ctx, stmt.value) .. ";")
        elseif cls == LJ.LJStmtCall then
            local args = {}
            for i = 1, #stmt.args do args[i] = c_expr(ctx, stmt.args[i]) end
            line(out, n, c_call_target_expr(ctx, stmt.target, args) .. ";")
        elseif cls == LJ.LJStmtEmitMachine then
            c_emit_machine_stmt(out, n, ctx, stmt.machine)
        else
            unsupported(stmt, "C statement")
        end
    end

    local function c_emit_term(out, n, ctx, term, block_by_id)
        local cls = asdl.classof(term)
        if cls == LJ.LJTermReturn then
            if #term.values == 0 then
                line(out, n, "return;")
            elseif #term.values == 1 then
                line(out, n, "return " .. c_expr(ctx, term.values[1]) .. ";")
            else
                unsupported(term, "C multi-value return")
            end
        elseif cls == LJ.LJTermTrap then
            line(out, n, "abort();")
        elseif cls == LJ.LJTermJump then
            local dest = block_by_id[term.dest.text]
            if dest == nil then error("luajit_emit: missing C jump dest " .. tostring(term.dest.text), 3) end
            c_emit_transfer(out, n, ctx, dest, term.args)
        elseif cls == LJ.LJTermBranch then
            local td, ed = block_by_id[term.then_dest.text], block_by_id[term.else_dest.text]
            if td == nil or ed == nil then error("luajit_emit: missing C branch dest", 3) end
            line(out, n, "if (" .. c_expr(ctx, term.cond) .. ") {")
            c_emit_transfer(out, n + 1, ctx, td, term.then_args)
            line(out, n, "} else {")
            c_emit_transfer(out, n + 1, ctx, ed, term.else_args)
            line(out, n, "}")
        elseif cls == LJ.LJTermSwitch then
            line(out, n, "switch (" .. c_expr(ctx, term.value) .. ") {")
            for i = 1, #term.cases do
                local case = term.cases[i]
                local dest = block_by_id[case.dest.text]
                if dest == nil then error("luajit_emit: missing C switch dest " .. tostring(case.dest.text), 3) end
                line(out, n, "case " .. c_literal(case.literal) .. ":")
                c_emit_transfer(out, n + 1, ctx, dest, case.args)
            end
            local dd = block_by_id[term.default_dest.text]
            if dd == nil then error("luajit_emit: missing C switch default dest " .. tostring(term.default_dest.text), 3) end
            line(out, n, "default:")
            c_emit_transfer(out, n + 1, ctx, dd, term.default_args)
            line(out, n, "}")
        else
            unsupported(term, "C term")
        end
    end

    local function c_collect_func_locals(func)
        local locals, seen = {}, {}
        local function mark(id)
            if id ~= nil then seen[id.text] = true end
        end
        local function add(id, phys)
            if id == nil or phys == nil or seen[id.text] then return end
            seen[id.text] = true
            locals[#locals + 1] = { name = id_name(id), ty = phys.abi }
        end
        for _, param in ipairs(func.params or {}) do mark(param.value) end
        if asdl.classof(func.body) == LJ.LJBodyBlocks then
            for _, block in ipairs(func.body.blocks or {}) do
                for i, param in ipairs(block.params or {}) do
                    add(param.value, param.ty)
                    locals[#locals + 1] = { name = c_xfer_name(block, i), ty = param.ty.abi }
                end
                for _, stmt in ipairs(block.stmts or {}) do
                    local cls = asdl.classof(stmt)
                    if cls == LJ.LJStmtLet then
                        add(stmt.dst, stmt.ty)
                    elseif cls == LJ.LJStmtStore and asdl.classof(stmt.place) == LJ.LJPlaceLocal then
                        add(stmt.place.local_id, stmt.place.ty)
                    end
                end
            end
        end
        return locals
    end

    local function c_emit_blocks_func(ctx, func, sig)
        local block_by_id, order = build_block_map(func.body.blocks)
        local entry = block_by_id[func.body.entry.text]
        if entry == nil then error("luajit_emit: C function missing entry block " .. tostring(func.body.entry.text), 3) end
        if #(entry.params or {}) ~= 0 then error("luajit_emit: C function entry block parameters are not supported", 3) end
        local params = {}
        for i = 1, #func.params do params[i] = c_param_decl(func.params[i]) end
        local out = { c_result_type(sig) .. " " .. c_func_name(func.name) .. "(" .. (#params > 0 and table.concat(params, ", ") or "void") .. ") {" }
        for _, local_ in ipairs(c_collect_func_locals(func)) do
            line(out, 1, c_decl(local_.ty, local_.name) .. ";")
        end
        line(out, 1, "goto " .. c_label(func.body.entry) .. ";")
        for _, key in ipairs(order) do
            local block = block_by_id[key]
            out[#out + 1] = c_label(block.id) .. ":"
            for i = 1, #block.params do
                line(out, 1, id_name(block.params[i].value) .. " = " .. c_xfer_name(block, i) .. ";")
            end
            for i = 1, #block.stmts do c_emit_stmt(out, 1, ctx, block.stmts[i]) end
            c_emit_term(out, 1, ctx, block.term, block_by_id)
        end
        out[#out + 1] = "}"
        return table.concat(out, "\n")
    end

    local function c_func_prototype(func, sig)
        local params = {}
        for i = 1, #func.params do params[i] = c_param_decl(func.params[i]) end
        return c_result_type(sig) .. " " .. c_func_name(func.name) .. "(" .. (#params > 0 and table.concat(params, ", ") or "void") .. ");"
    end

    local function c_func_symbol_index(module)
        local out = {}
        for _, func in ipairs(module.funcs or {}) do
            out[func.id.text] = c_func_name(func.name)
            if func.source ~= nil then out[func.source.text] = c_func_name(func.name) end
        end
        return out
    end

    local function c_module_context(module)
        return {
            sigs = sig_index(module),
            func_symbol_by_id = c_func_symbol_index(module),
        }
    end

    local function c_emit_func(ctx, func)
        local sig = ctx.sigs[func.sig.text]
        if sig == nil then error("luajit_emit: C function references missing signature " .. tostring(func.sig.text), 3) end
        local body_cls = asdl.classof(func.body)
        if body_cls == LJ.LJBodyBlocks then
            ctx.machine_by_id = machine_map(func)
            return c_emit_blocks_func(ctx, func, sig)
        end
        if body_cls == LJ.LJBodyMachine then
            local op, op_cls = native_residual_candidate(func)
            if op ~= nil then return c_stencil_wrapper_source(ctx, func, sig, op, op_cls) end
        end
        unsupported(func.body, "C function body")
    end

    local function c_byte_init_list(bytes)
        bytes = tostring(bytes or "")
        if #bytes == 0 then return "{0}" end
        local out = {}
        for i = 1, #bytes do out[#out + 1] = "[" .. tostring(i - 1) .. "] = " .. tostring(bytes:byte(i)) end
        return "{ " .. table.concat(out, ", ") .. " }"
    end

    local function c_emit_data(module, out)
        for i = 1, #(module.data or {}) do
            local data = module.data[i]
            local bytes = data_bytes(data)
            local size = tonumber(data.size or #bytes) or #bytes
            if size < 1 then size = 1 end
            out[#out + 1] = "static unsigned char " .. data_name(data.id) .. "[" .. tostring(size) .. "] = " .. c_byte_init_list(bytes) .. ";"
        end
    end

    local function c_emit_cdefs(module, out)
        local seen = {}
        local function add(decl)
            local source = emit_cdecl(decl)
            if source ~= nil and source ~= "" and not seen[source] then
                seen[source] = true
                out[#out + 1] = source
            end
        end
        for i = 1, #(module.types or {}) do add(module.types[i]) end
        for i = 1, #(module.funcs or {}) do
            for j = 1, #(module.funcs[i].cdefs or {}) do add(module.funcs[i].cdefs[j]) end
        end
    end

    local function c_common_preamble()
        return {
            "#include <stdint.h>",
            "#include <stddef.h>",
            "#include <stdbool.h>",
            "#include <string.h>",
            "#include <stdlib.h>",
            "#include <math.h>",
            "typedef intptr_t ml_index;",
        }
    end

    local function emit_c_module(module, artifacts, opts)
        opts = opts or {}
        local StencilC = require("lalin.stencil_c")(T)
        local ctx = c_module_context(module)
        local out = { "/* generated by lalin LuaJIT whole-program C emitter */" }
        for _, item in ipairs(c_common_preamble()) do out[#out + 1] = item end
        out[#out + 1] = ""
        c_emit_cdefs(module, out)
        out[#out + 1] = ""
        c_emit_data(module, out)
        out[#out + 1] = ""
        for _, func in ipairs(module.funcs or {}) do out[#out + 1] = c_func_prototype(func, ctx.sigs[func.sig.text]) end
        out[#out + 1] = ""
        if #(artifacts or {}) > 0 then
            local stencil_source = StencilC.source(artifacts, {
                omit_preamble = true,
                c_decls = opts.c_decls or opts.decls,
            })
            if opts.static_stencils ~= false then
                local seen = {}
                for _, artifact in ipairs(artifacts or {}) do
                    local symbol = artifact.symbol.text
                    if not seen[symbol] then
                        local ret = c_signature_parts(symbol, artifact.c_signature)
                        stencil_source = stencil_source:gsub(
                            "([^\n]*)" .. pattern_escape(ret) .. "%s+" .. pattern_escape(symbol) .. "%s*%(",
                            function(prefix)
                                if prefix ~= "" then return prefix .. ret .. " " .. symbol .. "(" end
                                return "static inline " .. ret .. " " .. symbol .. "("
                            end,
                            1
                        )
                        seen[symbol] = true
                    end
                end
            end
            out[#out + 1] = stencil_source
        end
        for _, func in ipairs(module.funcs or {}) do
            out[#out + 1] = c_emit_func(ctx, func)
            out[#out + 1] = ""
        end
        return table.concat(out, "\n")
    end

    local function emit_c_header(module, opts)
        opts = opts or {}
        local ctx = c_module_context(module)
        local guard = sanitize((opts.guard or opts.name or "lalin_jit") .. "_h"):upper()
        local out = {
            "/* generated by lalin LuaJIT whole-program C emitter */",
            "#ifndef " .. guard,
            "#define " .. guard,
            "",
        }
        for _, item in ipairs(c_common_preamble()) do out[#out + 1] = item end
        out[#out + 1] = ""
        out[#out + 1] = "#ifdef __cplusplus"
        out[#out + 1] = "extern \"C\" {"
        out[#out + 1] = "#endif"
        out[#out + 1] = ""
        c_emit_cdefs(module, out)
        out[#out + 1] = ""
        for _, func in ipairs(module.funcs or {}) do out[#out + 1] = c_func_prototype(func, ctx.sigs[func.sig.text]) end
        out[#out + 1] = ""
        out[#out + 1] = "#ifdef __cplusplus"
        out[#out + 1] = "}"
        out[#out + 1] = "#endif"
        out[#out + 1] = ""
        out[#out + 1] = "#endif"
        return table.concat(out, "\n") .. "\n"
    end

    local function emit_c_artifact(module, artifacts, opts)
        local source = emit_c_module(module, artifacts, opts)
        local header = emit_c_header(module, opts)
        return {
            kind = "LuaJITCSourceArtifact",
            source = source,
            header = header,
            support = "",
            combined = source,
            lj_module = module,
            artifacts = artifacts or {},
        }
    end

    local function emit_native_residuals(out, module, opts)
        if not (opts.native_residual == true or opts.native_residual == "tcc" or opts.tcc_residual == true) then return end
        local sigs = sig_index(module)
        local c_units, replacements, host_symbols = {}, {}, {}
        local seen_symbols = {}
        for _, func in ipairs(module.funcs or {}) do
            local op, op_cls = native_residual_candidate(func)
            if op ~= nil then
                local sig = sigs[func.sig.text]
                local source, wrapper, stencil_symbol = native_wrapper_source(func, sig, op, op_cls)
                c_units[#c_units + 1] = source
                replacements[#replacements + 1] = {
                    func_name = func_name(func.name),
                    wrapper = wrapper,
                    ctype = native_func_pointer_ctype(func, sig, op, op_cls),
                }
                seen_symbols[stencil_symbol] = true
            end
        end
        if #replacements == 0 then return end
        for symbol in pairs(seen_symbols) do host_symbols[#host_symbols + 1] = symbol end
        table.sort(host_symbols)
        c_units[#c_units + 1] = ""
        table.insert(c_units, 1, "#include <stdint.h>")
        table.insert(c_units, 2, "#include <stdbool.h>")
        line(out, 0, "local __lalin_native_residual_sessions = debug.getregistry().__lalin_native_residual_sessions")
        line(out, 0, "if __lalin_native_residual_sessions == nil then __lalin_native_residual_sessions = {}; debug.getregistry().__lalin_native_residual_sessions = __lalin_native_residual_sessions end")
        line(out, 0, "do")
        line(out, 1, "local __c_tcc = require('lalin.c_tcc')")
        line(out, 1, "local __native_source = " .. native_c_string(table.concat(c_units, "\n\n") .. "\n"))
        line(out, 1, "local __native_host_symbols = {}")
        for _, symbol in ipairs(host_symbols) do
            line(out, 1, "if __lalin_luajit_stencil_symbols[" .. lua_string(symbol) .. "] == nil then error(" .. lua_string("missing LalinStencil symbol " .. symbol) .. ", 0) end")
            line(out, 1, "__native_host_symbols[" .. lua_string(symbol) .. "] = ffi.cast('void *', ffi.cast('uintptr_t', __lalin_luajit_stencil_symbols[" .. lua_string(symbol) .. "]))")
        end
        line(out, 1, "local __session, __err = __c_tcc.compile(__native_source, { libraries = { 'm' }, host_symbols = __native_host_symbols })")
        line(out, 1, "if not __session then error((__err and __err.message) or 'native residual TCC compile failed', 0) end")
        line(out, 1, "__lalin_native_residual_sessions[#__lalin_native_residual_sessions + 1] = __session")
        for _, replacement in ipairs(replacements) do
            line(out, 1, replacement.func_name .. " = assert(__session:symbol(" .. lua_string(replacement.wrapper) .. ", " .. lua_string(replacement.ctype) .. "))")
        end
        line(out, 0, "end")
    end

    local function emit_module(module, opts)
        opts = opts or {}
        local out = {}
        line(out, 0, "local ffi = require('ffi')")
        line(out, 0, "local bit = require('bit')")
        line(out, 0, "local __lalin_luajit_stencil_symbols = __lalin_luajit_stencil_symbols or {}")
        line(out, 0, "local __ml_tobit = bit.tobit")
        line(out, 0, "local __ml_band = bit.band")
        line(out, 0, "local __ml_bor = bit.bor")
        line(out, 0, "local __ml_bxor = bit.bxor")
        line(out, 0, "local __ml_lshift = bit.lshift")
        line(out, 0, "local __ml_rshift = bit.rshift")
        line(out, 0, "local __ml_arshift = bit.arshift")
        line(out, 0, "local __ml_bnot = bit.bnot")
        line(out, 0, "local function __ml_u8(x) return __ml_band(__ml_tobit(x), 255) end")
        line(out, 0, "local function __ml_i8(x) x = __ml_band(__ml_tobit(x), 255); return x - __ml_lshift(__ml_band(x, 128), 1) end")
        line(out, 0, "local function __ml_u16(x) return __ml_band(__ml_tobit(x), 65535) end")
        line(out, 0, "local function __ml_i16(x) x = __ml_band(__ml_tobit(x), 65535); return x - __ml_lshift(__ml_band(x, 32768), 1) end")
        line(out, 0, "local function __ml_u32(x) x = __ml_tobit(x); if x < 0 then return x + 4294967296 end; return x end")
        line(out, 0, "local function __ml_mul32(a, b) local al = __ml_band(a, 65535); local ah = __ml_rshift(a, 16); local bl = __ml_band(b, 65535); local bh = __ml_rshift(b, 16); return __ml_tobit(al * bl + __ml_lshift(__ml_band(ah * bl + al * bh, 65535), 16)) end")
        line(out, 0, "local math = math")
        local cdefs = {}
        for i = 1, #(module.types or {}) do cdefs[#cdefs + 1] = emit_cdecl(module.types[i]) end
        for i = 1, #(module.funcs or {}) do
            for j = 1, #(module.funcs[i].cdefs or {}) do cdefs[#cdefs + 1] = emit_cdecl(module.funcs[i].cdefs[j]) end
        end
        if #cdefs > 0 then
            line(out, 0, "pcall(ffi.cdef, " .. lua_string(table.concat(cdefs, "\n")) .. ")")
        end
        for i = 1, #(module.data or {}) do
            local data = module.data[i]
            local bytes = data_bytes(data)
            line(out, 0, "local " .. data_name(data.id) .. " = ffi.new('unsigned char[?]', " .. tostring(#bytes) .. ")")
            if #bytes > 0 then
                line(out, 0, "ffi.copy(" .. data_name(data.id) .. ", " .. lua_string(bytes) .. ", " .. tostring(#bytes) .. ")")
            end
        end
        for i = 1, #(module.funcs or {}) do
            line(out, 0, "local " .. func_name(module.funcs[i].name))
        end
        for i = 1, #(module.funcs or {}) do emit_func(out, 0, module.funcs[i]) end
        emit_native_residuals(out, module, opts)
        line(out, 0, "return {")
        for i = 1, #(module.funcs or {}) do
            local f = module.funcs[i]
            line(out, 1, "[" .. lua_string(f.name) .. "] = " .. func_name(f.name) .. ",")
        end
        line(out, 0, "}")
        return table.concat(out, "\n") .. "\n"
    end

    local function compile_module(module, opts)
        opts = opts or {}
        local source = emit_module(module, opts)
        local loader = loadstring or load
        local chunk, err = loader(source, opts.chunk_name or "lalin_luajit_emit")
        if chunk == nil then return nil, err, source end
        if setfenv ~= nil then
            setfenv(chunk, setmetatable({
                __lalin_luajit_stencil_symbols = opts.stencil_symbols or {},
            }, { __index = _G }))
        end
        local ok, result = pcall(chunk)
        if not ok then return nil, result, source end
        return result, nil, source
    end

    api.emit_module = emit_module
    api.emit_c_module = emit_c_module
    api.emit_c_header = emit_c_header
    api.emit_c_artifact = emit_c_artifact
    api.compile_module = compile_module
    api.expr = expr

    T._lalin_api_cache.luajit_emit = api
    return api
end

return bind_context
