-- lisle/codegen_lua.lua
--
-- Code generation from lisle semantic model to plain Lua.
--
-- Properties:
--   * deterministic output
--   * rule-priority preserving dispatch
--   * trace-friendly generated code (straight checks, low allocation)

local Decision = require("moonlift.lisle.decision")

local M = {}

local function q(s) return string.format("%q", s) end

local function emit(lines, s)
    lines[#lines + 1] = s
end

local function sorted_keys(map)
    local ks = {}
    for k in pairs(map or {}) do ks[#ks + 1] = k end
    table.sort(ks)
    return ks
end

local function copy_map(src)
    local out = {}
    for k, v in pairs(src or {}) do out[k] = v end
    return out
end

local function is_lua_ident(s)
    return type(s) == "string" and s:match("^[A-Za-z_][A-Za-z0-9_]*$") ~= nil
end

--------------------------------------------------------------------------
-- Pattern helpers
--------------------------------------------------------------------------

local function same_assumption_key(a, b)
    if not a or not b or a.kind ~= b.kind then return false end
    if a.kind == "ctor" then return a.name == b.name end
    if a.kind == "num" or a.kind == "str" or a.kind == "bool" then return a.value == b.value end
    if a.kind == "nil" then return true end
    return false
end

local function compile_pattern(pat, expr, spec, st, assume_key)
    if pat.tag == "wildcard" then return end

    if pat.tag == "var" then
        local n = pat.name
        local prev = st.bindings[n]
        if prev then st.checks[#st.checks + 1] = expr .. " == " .. prev
        else st.bindings[n] = expr end
        return
    end

    if pat.tag == "bind" then
        compile_pattern(pat.pat, expr, spec, st, assume_key)
        local prev = st.bindings[pat.name]
        if prev then st.checks[#st.checks + 1] = expr .. " == " .. prev
        else st.bindings[pat.name] = expr end
        return
    end

    if pat.tag == "ctor" then
        local expected = { kind = "ctor", name = pat.ctor }
        if assume_key and not same_assumption_key(assume_key, expected) then
            st.checks[#st.checks + 1] = "false"
            return
        end

        local c = spec.ctors[pat.ctor]
        if not assume_key then
            st.checks[#st.checks + 1] = "type(" .. expr .. ") == 'table'"
            st.checks[#st.checks + 1] = expr .. ".kind == " .. q(pat.ctor)
        end
        for i = 1, #pat.args do compile_pattern(pat.args[i], expr .. "." .. c.fields[i], spec, st, nil) end
        return
    end

    if pat.tag == "num" then
        local expected = { kind = "num", value = pat.value }
        if assume_key and same_assumption_key(assume_key, expected) then return end
        st.checks[#st.checks + 1] = expr .. " == " .. tostring(pat.value)
        return
    end

    if pat.tag == "str" then
        local expected = { kind = "str", value = pat.value }
        if assume_key and same_assumption_key(assume_key, expected) then return end
        st.checks[#st.checks + 1] = expr .. " == " .. q(pat.value)
        return
    end

    if pat.tag == "bool" then
        local expected = { kind = "bool", value = pat.value }
        if assume_key and same_assumption_key(assume_key, expected) then return end
        st.checks[#st.checks + 1] = expr .. " == " .. tostring(pat.value)
        return
    end

    if pat.tag == "nil" then
        local expected = { kind = "nil" }
        if assume_key and same_assumption_key(assume_key, expected) then return end
        st.checks[#st.checks + 1] = expr .. " == nil"
        return
    end

    error("lisle codegen: unsupported pattern tag '" .. tostring(pat.tag) .. "'", 0)
end

local function normalize_expr_pattern(node, spec)
    if node.tag == "sym" then
        if node.value == "_" then return { tag = "wildcard" } end
        local c = spec and spec.ctors and spec.ctors[node.value]
        if c and #c.fields == 0 then return { tag = "ctor", ctor = node.value, args = {} } end
        return { tag = "var", name = node.value }
    end
    if node.tag == "num" then return { tag = "num", value = node.value } end
    if node.tag == "str" then return { tag = "str", value = node.value } end
    if node.tag == "bool" then return { tag = "bool", value = node.value } end
    if node.tag == "nil" then return { tag = "nil" } end

    if node.tag == "list" then
        if #node == 0 then error("lisle codegen: empty pattern", 0) end
        if node[1].tag == "sym" and node[1].value == "@" then
            if #node ~= 3 then error("lisle codegen: (@ name pat) expects 2 args", 0) end
            return { tag = "bind", name = node[2].value, pat = normalize_expr_pattern(node[3], spec) }
        end
        if node[1].tag ~= "sym" then error("lisle codegen: ctor pattern head must be symbol", 0) end
        local args = {}
        for i = 2, #node do args[#args + 1] = normalize_expr_pattern(node[i], spec) end
        return { tag = "ctor", ctor = node[1].value, args = args }
    end

    error("lisle codegen: unsupported pattern node", 0)
end

--------------------------------------------------------------------------
-- Expression compiler
--------------------------------------------------------------------------

local INFIX_BINARY = {
    ["+"] = "+", ["-"] = "-", ["*"] = "*", ["/"] = "/", ["%"] = "%",
    ["="] = "==", ["~="] = "~=", ["<"] = "<", ["<="] = "<=", [">"] = ">", [">="] = ">=",
}

local function is_multi_term_call_ast(node, spec)
    if not node or node.tag ~= "list" or #node == 0 then return false end
    local h = node[1]
    if not h or h.tag ~= "sym" then return false end
    local t = spec.terms[h.value]
    return t and t.attrs and t.attrs.multi or false
end

local function compile_multi_call(node, spec, env, compile_expr)
    if not is_multi_term_call_ast(node, spec) then
        error("lisle codegen: expected multi term call", 0)
    end
    local term_name = node[1].value
    local args = {}
    for i = 2, #node do args[#args + 1] = compile_expr(node[i], spec, env, false) end
    return term_name, args
end

local function ctor_emit(name, args, spec)
    local ctor = spec.ctors[name]
    if #ctor.fields ~= #args then
        error("lisle codegen: ctor call '" .. name .. "' arity mismatch", 0)
    end

    local alias = (spec.extern_constructors and spec.extern_constructors[name]) or name
    local arg_list = table.concat(args, ", ")

    local fb = {"{ kind = " .. q(name)}
    for i = 1, #ctor.fields do
        fb[#fb + 1] = ", " .. ctor.fields[i] .. " = " .. args[i]
    end
    fb[#fb + 1] = " }"
    local fallback = table.concat(fb)

    return "((ctx and ctx.ctor and ctx.ctor[" .. q(alias) .. "] and ctx.ctor[" .. q(alias) .. "](" .. arg_list .. ")) or " .. fallback .. ")"
end

local function compile_expr(node, spec, env, allow_multi)
    allow_multi = allow_multi or false

    if node.tag == "num" then return tostring(node.value) end
    if node.tag == "str" then return q(node.value) end
    if node.tag == "bool" then return tostring(node.value) end
    if node.tag == "nil" then return "nil" end

    if node.tag == "sym" then
        local n = node.value
        if env.vars[n] then return n end
        if n == "true" or n == "false" or n == "nil" then return n end
        local c = spec.ctors[n]
        if c and #c.fields == 0 then return ctor_emit(n, {}, spec) end
        error("lisle codegen: unbound symbol '" .. tostring(n) .. "'", 0)
    end

    if node.tag ~= "list" then
        error("lisle codegen: invalid expression node '" .. tostring(node.tag) .. "'", 0)
    end
    if #node == 0 then error("lisle codegen: empty expression list", 0) end

    local head = node[1]
    if head.tag ~= "sym" then error("lisle codegen: expression head must be symbol", 0) end
    local h = head.value

    if h == "if" then
        local c = compile_expr(node[2], spec, env, false)
        local a = compile_expr(node[3], spec, env, false)
        local b = compile_expr(node[4], spec, env, false)
        return "(function() if " .. c .. " then return " .. a .. " else return " .. b .. " end end)()"
    end

    if h == "if-let" then
        local pair = node[2]
        local pat = normalize_expr_pattern(pair[1], spec)
        local st = { checks = {}, bindings = {} }
        compile_pattern(pat, "__v", spec, st)
        local cond = (#st.checks > 0) and table.concat(st.checks, " and ") or "true"

        local then_env = { vars = {} }
        for k, v in pairs(env.vars) do then_env.vars[k] = v end
        local bind_names = sorted_keys(st.bindings)
        local bind_code = {}
        for i = 1, #bind_names do
            local n = bind_names[i]
            if not is_lua_ident(n) then error("lisle codegen: invalid bound name in if-let: " .. tostring(n), 0) end
            then_env.vars[n] = true
            local e = st.bindings[n]
            if n ~= e then bind_code[#bind_code + 1] = " local " .. n .. " = " .. e .. ";" end
        end

        local t = compile_expr(node[3], spec, then_env, false)
        local f = compile_expr(node[4], spec, env, false)

        if is_multi_term_call_ast(pair[2], spec) then
            local term_name, args = compile_multi_call(pair[2], spec, env, compile_expr)
            local arg_list = table.concat(args, ", ")

            local checks_mv = {}
            for i = 1, #st.checks do checks_mv[i] = st.checks[i]:gsub("__v", "__mv") end
            local cond_mv = (#checks_mv > 0) and table.concat(checks_mv, " and ") or "true"

            local bind_code_mv = {}
            for i = 1, #bind_names do
                local n = bind_names[i]
                local e = st.bindings[n]:gsub("__v", "__mv")
                if n ~= e then bind_code_mv[#bind_code_mv + 1] = " local " .. n .. " = " .. e .. ";" end
            end

            return "(function()"
                .. " local __hit=false; local __out=nil;"
                .. " local function __emit_iflet(__mv)"
                .. " if " .. cond_mv .. " then"
                .. table.concat(bind_code_mv)
                .. " __hit=true; __out=" .. t .. "; return true;"
                .. " end; return false; end;"
                .. " M." .. term_name .. "(ctx" .. (#args > 0 and ", " .. arg_list or "") .. ", __emit_iflet);"
                .. " if __hit then return __out end;"
                .. " return " .. f .. " end)()"
        end

        local value_expr = compile_expr(pair[2], spec, env, false)
        return "(function() local __v = " .. value_expr .. "; if " .. cond .. " then"
            .. table.concat(bind_code)
            .. " return " .. t .. " else return " .. f .. " end end)()"
    end

    if h == "match" then
        local subject = compile_expr(node[2], spec, env, false)
        local parts = {"(function() local __m = " .. subject .. ";"}

        local if_started, has_terminal = false, false
        for i = 3, #node do
            local arm = node[i]
            if arm.tag ~= "list" or #arm ~= 2 then
                error("lisle codegen: match arm must be (pattern expr) or (default expr)", 0)
            end

            if arm[1].tag == "sym" and arm[1].value == "default" then
                local e = compile_expr(arm[2], spec, env, false)
                if if_started then parts[#parts + 1] = " else return " .. e .. ";"
                else parts[#parts + 1] = " return " .. e .. ";" end
                has_terminal = true
                break
            end

            local pat = normalize_expr_pattern(arm[1], spec)
            local st = { checks = {}, bindings = {} }
            compile_pattern(pat, "__m", spec, st)
            local cond = (#st.checks > 0) and table.concat(st.checks, " and ") or "true"

            local env_arm = { vars = {} }
            for k, v in pairs(env.vars) do env_arm.vars[k] = v end

            local bind_names = sorted_keys(st.bindings)
            local bind_code = {}
            for bi = 1, #bind_names do
                local n = bind_names[bi]
                if not is_lua_ident(n) then error("lisle codegen: invalid bound name in match: " .. tostring(n), 0) end
                env_arm.vars[n] = true
                local e = st.bindings[n]
                if n ~= e then bind_code[#bind_code + 1] = " local " .. n .. " = " .. e .. ";" end
            end

            local rhs = compile_expr(arm[2], spec, env_arm, false)
            if not if_started then
                parts[#parts + 1] = " if " .. cond .. " then" .. table.concat(bind_code) .. " return " .. rhs .. ";"
                if_started = true
            else
                parts[#parts + 1] = " elseif " .. cond .. " then" .. table.concat(bind_code) .. " return " .. rhs .. ";"
            end
        end

        if if_started then
            if not has_terminal then parts[#parts + 1] = " else return nil;" end
            parts[#parts + 1] = " end"
        elseif not has_terminal then
            parts[#parts + 1] = " return nil;"
        end

        parts[#parts + 1] = " end)()"
        return table.concat(parts)
    end

    if h == "do" then
        if #node == 1 then return "nil" end
        local parts = {"(function()"}
        for i = 2, #node - 1 do
            parts[#parts + 1] = " local __drop" .. tostring(i) .. " = " .. compile_expr(node[i], spec, env, false) .. ";"
        end
        parts[#parts + 1] = " return " .. compile_expr(node[#node], spec, env, false) .. " end)()"
        return table.concat(parts)
    end

    if h == "let" then
        local binds = node[2]
        local body = node[3]
        local env2 = { vars = {} }
        for k, v in pairs(env.vars) do env2.vars[k] = v end

        local parts = {"(function()"}
        for i = 1, #binds do
            local b = binds[i]
            local n = b[1].value
            local e = compile_expr(b[2], spec, env2, false)
            if not is_lua_ident(n) then error("lisle codegen: invalid let binding name: " .. tostring(n), 0) end
            parts[#parts + 1] = " local " .. n .. " = " .. e .. ";"
            env2.vars[n] = true
        end
        parts[#parts + 1] = " return " .. compile_expr(body, spec, env2, false) .. " end)()"
        return table.concat(parts)
    end

    if h == "collect" then
        local term_name, args = compile_multi_call(node[2], spec, env, compile_expr)
        local arg_list = table.concat(args, ", ")
        return "(function() local __acc={}; local function __emit_collect(v) __acc[#__acc+1]=v; return false end;"
            .. " M." .. term_name .. "(ctx" .. (#args > 0 and ", " .. arg_list or "") .. ", __emit_collect);"
            .. " return __acc end)()"
    end

    if h == "first" then
        local term_name, args = compile_multi_call(node[2], spec, env, compile_expr)
        local arg_list = table.concat(args, ", ")
        local fallback = (#node == 3) and compile_expr(node[3], spec, env, false) or "nil"
        return "(function() local __hit=false; local __out=nil;"
            .. " local function __emit_first(v) __hit=true; __out=v; return true end;"
            .. " M." .. term_name .. "(ctx" .. (#args > 0 and ", " .. arg_list or "") .. ", __emit_first);"
            .. " if __hit then return __out end; return " .. fallback .. " end)()"
    end

    if h == "any" then
        local term_name, args = compile_multi_call(node[2], spec, env, compile_expr)
        local arg_list = table.concat(args, ", ")
        return "(function() local __hit=false;"
            .. " local function __emit_any(_) __hit=true; return true end;"
            .. " M." .. term_name .. "(ctx" .. (#args > 0 and ", " .. arg_list or "") .. ", __emit_any);"
            .. " return __hit end)()"
    end

    if h == "not" then
        return "(not (" .. compile_expr(node[2], spec, env, false) .. "))"
    end

    if h == "and" or h == "or" then
        local op = " " .. h .. " "
        local xs = {}
        for i = 2, #node do xs[#xs + 1] = "(" .. compile_expr(node[i], spec, env, false) .. ")" end
        return "(" .. table.concat(xs, op) .. ")"
    end

    local bop = INFIX_BINARY[h]
    if bop then
        local a = compile_expr(node[2], spec, env, false)
        local b = compile_expr(node[3], spec, env, false)
        return "((" .. a .. ") " .. bop .. " (" .. b .. "))"
    end

    local args = {}
    for i = 2, #node do args[#args + 1] = compile_expr(node[i], spec, env, false) end
    local arg_list = table.concat(args, ", ")

    local term = spec.terms[h]
    if term then
        if term.attrs.multi then
            error("lisle codegen: cannot call multi term '" .. h .. "' in scalar expression context", 0)
        end
        return "M." .. h .. "(ctx" .. (#args > 0 and ", " .. arg_list or "") .. ")"
    end

    if spec.ctors[h] then
        return ctor_emit(h, args, spec)
    end

    local alias = (spec.extern_extractors and spec.extern_extractors[h]) or h
    return "ctx.extern[" .. q(alias) .. "](ctx" .. (#args > 0 and ", " .. arg_list or "") .. ")"
end

local function compile_guard(guard, spec, env)
    if not guard then return nil end
    if guard.kind == "lua" then return guard.code end
    if guard.kind == "expr" then return compile_expr(guard.expr, spec, env, false) end
    error("lisle codegen: unknown guard kind '" .. tostring(guard.kind) .. "'", 0)
end

local function emit_rhs(lines, rhs, spec, env, is_multi)
    if rhs.kind == "lua" then
        emit(lines, "          " .. rhs.code)
        return
    end

    if rhs.kind == "expr" then
        local e = compile_expr(rhs.expr, spec, env, false)
        if is_multi then
            emit(lines, "          local __stop = emit(" .. e .. ")")
            emit(lines, "          __matched = true")
            emit(lines, "          if __stop then return true end")
        else
            emit(lines, "          return " .. e)
        end
        return
    end

    error("lisle codegen: unknown rhs kind '" .. tostring(rhs.kind) .. "'", 0)
end

local function emit_guarded_rhs(lines, guard, rhs, spec, env, is_multi)
    local g = compile_guard(guard, spec, env)
    if g and #g > 0 then
        emit(lines, "        if " .. g .. " then")
        emit_rhs(lines, rhs, spec, env, is_multi)
        emit(lines, "        end")
    else
        emit_rhs(lines, rhs, spec, env, is_multi)
    end
end

local function compile_rule(lines, rule, term, spec, assume)
    local st = { checks = {}, bindings = {} }
    for i = 1, #rule.patterns do
        compile_pattern(rule.patterns[i], term.args[i], spec, st, assume and assume[i] or nil)
    end

    local cond = (#st.checks > 0) and table.concat(st.checks, " and ") or "true"
    local env = { vars = {} }
    for i = 1, #term.args do env.vars[term.args[i]] = true end

    local binds = sorted_keys(st.bindings)
    local bind_lines = {}
    for i = 1, #binds do
        local n = binds[i]
        if not is_lua_ident(n) then error("lisle codegen: invalid bound variable name: " .. tostring(n), 0) end
        local e = st.bindings[n]
        if n ~= e then bind_lines[#bind_lines + 1] = "        local " .. n .. " = " .. e end
        env.vars[n] = true
    end

    local g = compile_guard(rule.guard, spec, env)
    local has_guard = g and #g > 0

    if cond == "true" and #bind_lines == 0 and not has_guard then
        emit(lines, "    do")
        emit_rhs(lines, rule.rhs, spec, env, term.attrs.multi)
        emit(lines, "    end")
        return
    end

    emit(lines, "    do")
    emit(lines, "      if " .. cond .. " then")
    for i = 1, #bind_lines do emit(lines, bind_lines[i]) end

    if has_guard then
        emit(lines, "        if " .. g .. " then")
        emit_rhs(lines, rule.rhs, spec, env, term.attrs.multi)
        emit(lines, "        end")
    else
        emit_rhs(lines, rule.rhs, spec, env, term.attrs.multi)
    end

    emit(lines, "      end")
    emit(lines, "    end")
end

local function emit_split_key_cond(key, val_expr)
    if key.kind == "ctor" then return "type(" .. val_expr .. ") == 'table' and " .. val_expr .. ".kind == " .. q(key.name) end
    if key.kind == "num" then return val_expr .. " == " .. tostring(key.value) end
    if key.kind == "str" then return val_expr .. " == " .. q(key.value) end
    if key.kind == "bool" then return val_expr .. " == " .. tostring(key.value) end
    if key.kind == "nil" then return val_expr .. " == nil" end
    error("lisle codegen: unknown decision key kind '" .. tostring(key.kind) .. "'", 0)
end

local function emit_tree(lines, node, term, spec, st, assume)
    if node.kind == "leaf" then
        for i = 1, #node.rules do compile_rule(lines, node.rules[i], term, spec, assume) end
        return
    end

    if node.kind == "split" then
        st.tmp_i = st.tmp_i + 1
        local tmp = "__d" .. tostring(st.tmp_i)
        local arg_expr = term.args[node.arg_i]

        emit(lines, "    do")
        emit(lines, "      local " .. tmp .. " = " .. arg_expr)

        for i = 1, #node.buckets do
            local b = node.buckets[i]
            local cond = emit_split_key_cond(b.key, tmp)
            if i == 1 then emit(lines, "      if " .. cond .. " then")
            else emit(lines, "      elseif " .. cond .. " then") end
            local child_assume = copy_map(assume)
            child_assume[node.arg_i] = b.key
            emit_tree(lines, b.tree, term, spec, st, child_assume)
        end

        if node.fallback then
            emit(lines, "      else")
            local child_assume = copy_map(assume)
            child_assume[node.arg_i] = nil
            emit_tree(lines, node.fallback, term, spec, st, child_assume)
        end

        emit(lines, "      end")
        emit(lines, "    end")
        return
    end

    if node.kind == "equal" then
        local a = term.args[node.ai]
        local b = term.args[node.aj]
        emit(lines, "    if " .. a .. " == " .. b .. " then")
        emit_tree(lines, node.eq_tree, term, spec, st, assume)
        emit(lines, "    else")
        emit_tree(lines, node.neq_tree, term, spec, st, assume)
        emit(lines, "    end")
        return
    end

    error("lisle codegen: unknown decision node kind '" .. tostring(node.kind) .. "'", 0)
end

local function compile_default(lines, def, term, spec)
    local env = { vars = {} }
    for i = 1, #term.args do env.vars[term.args[i]] = true end
    emit_guarded_rhs(lines, def and def.guard, def and def.rhs, spec, env, term.attrs.multi)
end

function M.emit(spec, module_name)
    local lines = {}

    emit(lines, "-- GENERATED by moonlift.lisle (" .. tostring(module_name or "<anon>") .. ")")
    emit(lines, "return function()")
    emit(lines, "  local M = {}")
    emit(lines, "")

    local terms = sorted_keys(spec.terms)
    for ti = 1, #terms do
        local tname = terms[ti]
        local term = spec.terms[tname]

        for i = 1, #term.args do
            if not is_lua_ident(term.args[i]) then
                error("lisle codegen: term arg must be Lua identifier: " .. tostring(term.args[i]), 0)
            end
        end

        local sig = {}
        for i = 1, #term.args do sig[#sig + 1] = term.args[i] end
        if term.attrs.multi then sig[#sig + 1] = "emit" end

        emit(lines, "  function M." .. tname .. "(ctx" .. (#sig > 0 and ", " .. table.concat(sig, ", ") or "") .. ")")
        if term.attrs.multi then emit(lines, "    local __matched = false") end

        local rules = spec.rules[tname] or {}
        local tree = Decision.build(term, rules)
        emit_tree(lines, tree, term, spec, { tmp_i = 0 }, nil)

        local def = spec.defaults[tname]
        if def then
            compile_default(lines, def, term, spec)
        elseif term.attrs.extern then
            local alias = (spec.extern_extractors and spec.extern_extractors[tname]) or tname
            if term.attrs.multi then
                emit(lines, "    if ctx and ctx.extern and ctx.extern[" .. q(alias) .. "] then")
                emit(lines, "      local ok = ctx.extern[" .. q(alias) .. "](ctx"
                    .. (#term.args > 0 and ", " .. table.concat(term.args, ", ") or "") .. ", emit)")
                emit(lines, "      if ok then __matched = true; return true end")
                emit(lines, "    end")
            else
                emit(lines, "    if ctx and ctx.extern and ctx.extern[" .. q(alias) .. "] then")
                emit(lines, "      return ctx.extern[" .. q(alias) .. "](ctx"
                    .. (#term.args > 0 and ", " .. table.concat(term.args, ", ") or "") .. ")")
                emit(lines, "    end")
            end
        end

        if term.attrs.multi then
            emit(lines, "    return __matched")
        else
            local def_guaranteed_return = false
            if def and not def.guard then
                if def.rhs.kind == "expr" then
                    def_guaranteed_return = true
                elseif def.rhs.kind == "lua" and type(def.rhs.code) == "string" then
                    def_guaranteed_return = def.rhs.code:match("^%s*return[%s%(]") ~= nil
                end
            end

            if not def_guaranteed_return then
                if term.attrs.partial or def or term.attrs.extern then
                    emit(lines, "    return nil")
                else
                    emit(lines, "    error(" .. q("lisle: no matching rule for term " .. tname) .. ", 0)")
                end
            end
        end

        emit(lines, "  end")
        emit(lines, "")
    end

    emit(lines, "  return M")
    emit(lines, "end")
    return table.concat(lines, "\n")
end

return M
