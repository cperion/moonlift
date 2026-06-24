local pvm = require("moonlift.pvm")

local function bind_context(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.luajit_emit ~= nil then return T._moonlift_api_cache.luajit_emit end

    local Core = T.MoonCore
    local Code = T.MoonCode
    local Value = T.MoonValue
    local LJ = T.MoonLuaJIT
    local Back = T.MoonBack

    local api = {}

    local function class_name(x)
        local cls = pvm.classof(x) or x
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

    local function indent(n)
        return string.rep("    ", n)
    end

    local function line(out, n, text)
        out[#out + 1] = indent(n) .. text
    end

    local is_cdata_reg

    local function literal(lit)
        local cls = pvm.classof(lit)
        if cls == Core.LitInt or cls == Core.LitFloat then return tostring(lit.raw) end
        if cls == Core.LitBool then return lit.value and "true" or "false" end
        if lit == Core.LitNil or cls == Core.LitNil then return "nil" end
        if cls == Core.LitString then return lua_string(lit.bytes) end
        unsupported(lit, "literal")
    end

    local function literal_expr(e)
        local cls = pvm.classof(e.literal)
        if cls == Core.LitInt and is_cdata_reg(e.ty) and pvm.classof(e.ty.storage) == LJ.LJCTypeScalar then
            local scalar = e.ty.storage.scalar
            if scalar == Back.BackI64 then return tostring(e.literal.raw) .. "LL" end
            if scalar == Back.BackU64 then return tostring(e.literal.raw) .. "ULL" end
        end
        return literal(e.literal)
    end

    local function ctype_spelling(ty)
        local cls = pvm.classof(ty)
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

    local function emit_cdecl(decl)
        local cls = pvm.classof(decl)
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
        return pvm.classof(phys and phys.register) == LJ.LJRegTraceInt32
    end

    function is_cdata_reg(phys)
        return pvm.classof(phys and phys.register) == LJ.LJRegCData
    end

    local expr
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
        if is_cdata_reg(e.to) then return "ffi.cast(" .. lua_string(ctype_spelling(e.to.storage)) .. ", " .. value .. ")" end
        return value
    end

    local function record_expr(e)
        local cls = pvm.classof(e.ty.storage)
        local parts = {}
        for i = 1, #e.fields do
            parts[i] = sanitize(e.fields[i].name) .. " = " .. expr(e.fields[i].expr)
        end
        if cls == LJ.LJCTypeNamed then
            return "ffi.new(" .. lua_string(e.ty.storage.spelling) .. ", { " .. table.concat(parts, ", ") .. " })"
        end
        return "{ " .. table.concat(parts, ", ") .. " }"
    end

    expr = function(e)
        local cls = pvm.classof(e)
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
        if cls == LJ.LJExprProjectField then return "(" .. expr(e.base) .. ")." .. sanitize(e.name) end
        if cls == LJ.LJExprRecord then return record_expr(e) end
        if cls == LJ.LJExprCDataCast then return "ffi.cast(" .. lua_string(ctype_spelling(e.ty)) .. ", " .. expr(e.value) .. ")" end
        unsupported(e, "expression")
    end

    local function emit_stmt(out, n, stmt)
        local cls = pvm.classof(stmt)
        if cls == LJ.LJStmtLet then
            line(out, n, "local " .. id_name(stmt.dst) .. " = " .. expr(stmt.expr))
        elseif cls == LJ.LJStmtStore then
            line(out, n, expr(stmt.addr) .. "[0] = " .. expr(stmt.value))
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

    local function emit_term(out, n, term, block_by_id)
        local cls = pvm.classof(term)
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
        if pvm.classof(reg) == LJ.LJRegTraceInt32 then return reg end
        return nil
    end

    local function reduction_binary_op(kind)
        if kind == Value.ReductionAdd then return Core.BinAdd end
        if kind == Value.ReductionMul then return Core.BinMul end
        if kind == Value.ReductionAnd then return Core.BinBitAnd end
        if kind == Value.ReductionOr then return Core.BinBitOr end
        if kind == Value.ReductionXor then return Core.BinBitXor end
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

    local function reduction_identity(kind, reg)
        if kind == Value.ReductionAdd or kind == Value.ReductionOr or kind == Value.ReductionXor then return normalize_trace(reg, "0") end
        if kind == Value.ReductionMul then return normalize_trace(reg, "1") end
        if kind == Value.ReductionAnd then return normalize_trace(reg, "-1") end
        if kind == Value.ReductionMin then
            if reg.signedness == Code.CodeSigned then return signed_max(reg) end
            return unsigned_max(reg)
        end
        if kind == Value.ReductionMax then
            if reg.signedness == Code.CodeSigned then return signed_min(reg) end
            return "0"
        end
        return nil
    end

    local function reduction_update(kind, reg, acc, value)
        if kind == Value.ReductionAdd then return normalize_trace(reg, "(" .. acc .. ") + (" .. value .. ")") end
        if kind == Value.ReductionMul then
            if reg.bits == 32 then return normalize_trace(reg, "__ml_mul32(" .. acc .. ", " .. value .. ")") end
            return normalize_trace(reg, "(" .. acc .. ") * (" .. value .. ")")
        end
        if kind == Value.ReductionAnd then return normalize_trace(reg, "__ml_band(" .. acc .. ", " .. value .. ")") end
        if kind == Value.ReductionOr then return normalize_trace(reg, "__ml_bor(" .. acc .. ", " .. value .. ")") end
        if kind == Value.ReductionXor then return normalize_trace(reg, "__ml_bxor(" .. acc .. ", " .. value .. ")") end
        if kind == Value.ReductionMin or kind == Value.ReductionMax then
            local cmp = kind == Value.ReductionMin and "<=" or ">="
            return "(((" .. acc .. ") " .. cmp .. " (" .. value .. ")) and (" .. acc .. ") or (" .. value .. "))"
        end
        return nil
    end

    local function fold_reduce_support(kind, sem, elem_ty, result_ty)
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
        if reduction_binary_op(kind) == nil and kind ~= Value.ReductionMin and kind ~= Value.ReductionMax then
            return false, "scalar LuaJIT fallback does not support this reduction kind"
        end
        if (kind == Value.ReductionAdd or kind == Value.ReductionMul) and (sem == nil or sem.overflow ~= Code.CodeIntWrap) then
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
        local k = m.kind
        local cls = pvm.classof(k)
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
            local source_kind = source and source.kind
            local source_cls = pvm.classof(source_kind)
            local step_cls = pvm.classof(k.step)
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
                return pvm.classof(e) == LJ.LJExprValue and e.value == id
            end
            local expr_ok = step_cls == LJ.LJExprIntBinary
                and ((is_value(k.step.lhs, k.acc) and is_value(k.step.rhs, k.item))
                    or (is_value(k.step.lhs, k.item) and is_value(k.step.rhs, k.acc)))
            if source_cls == LJ.LJMachineSourceArray and source_kind.length ~= nil and sem_ok and support_ok and expr_ok then
                local prefix = sanitize(m.id.text)
                local arr = id_name(source_kind.array)
                local acc = id_name(k.acc)
                emit_trace_fold_reduce_array(out, n, prefix, arr, "0", expr(source_kind.length), "1", k.init, 8, acc, k.item, reduction, k.step.ty)
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
            line(out, n, "if __moonlift_luajit_stencil_symbols[" .. lua_string(symbol) .. "] == nil then error(" .. lua_string("missing MoonStencil symbol " .. symbol) .. ", 0) end")
            local args = {}
            for i = 1, #k.args do args[i] = expr(k.args[i]) end
            body_cb(n, "__moonlift_luajit_stencil_symbols[" .. lua_string(symbol) .. "](" .. table.concat(args, ", ") .. ")")
        elseif cls == LJ.LJMachineStencilEffect then
            local symbol = k.artifact.symbol.text
            line(out, n, "if __moonlift_luajit_stencil_symbols[" .. lua_string(symbol) .. "] == nil then error(" .. lua_string("missing MoonStencil symbol " .. symbol) .. ", 0) end")
            local args = {}
            for i = 1, #k.args do args[i] = expr(k.args[i]) end
            line(out, n, "__moonlift_luajit_stencil_symbols[" .. lua_string(symbol) .. "](" .. table.concat(args, ", ") .. ")")
            body_cb(n, "nil")
        else
            unsupported(k, "machine")
        end
    end

    local function emit_machine_body(out, n, func, body)
        local machines = machine_map(func)
        local term = body.terminal
        local tcls = pvm.classof(term)
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
            local mcls = m ~= nil and pvm.classof(m.kind) or nil
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
        line(out, n, "local " .. func_name(func.name) .. " = function(" .. table.concat(params, ", ") .. ")")
        local body_cls = pvm.classof(func.body)
        if body_cls == LJ.LJBodySource then
            line(out, n + 1, func.body.source)
        elseif body_cls == LJ.LJBodyBlocks then
            emit_blocks_body(out, n + 1, func.body)
        elseif body_cls == LJ.LJBodyMachine then
            emit_machine_body(out, n + 1, func, func.body)
        else
            unsupported(func.body, "function body")
        end
        line(out, n, "end")
    end

    local function emit_module(module, opts)
        opts = opts or {}
        local out = {}
        line(out, 0, "local ffi = require('ffi')")
        line(out, 0, "local bit = require('bit')")
        line(out, 0, "local __moonlift_luajit_stencil_symbols = __moonlift_luajit_stencil_symbols or {}")
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
        for i = 1, #(module.funcs or {}) do emit_func(out, 0, module.funcs[i]) end
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
        local chunk, err = loader(source, opts.chunk_name or "moonlift_luajit_emit")
        if chunk == nil then return nil, err, source end
        if setfenv ~= nil then
            setfenv(chunk, setmetatable({
                __moonlift_luajit_stencil_symbols = opts.stencil_symbols or {},
            }, { __index = _G }))
        end
        local ok, result = pcall(chunk)
        if not ok then return nil, result, source end
        return result, nil, source
    end

    api.emit_module = emit_module
    api.compile_module = compile_module
    api.expr = expr

    T._moonlift_api_cache.luajit_emit = api
    return api
end

return bind_context
