-- lisle/sema.lua
--
-- Pure-Lua semantic analysis for lisle.
--
-- Supported top-level forms:
--   (type T ...)
--   (term name (args...) [attrs...])
--   (decl [mods...] name (args...) [ret] [attrs...])
--   (extern name ...)
--   (extern constructor C lua_name)
--   (extern extractor term lua_name)
--   (rule term prio (patterns...) clauses...)
--   (default term clauses...)
--
-- This pass enforces deterministic rule ordering, ambiguity checks for
-- equal-priority rules, recursion checks, and expression validity.

local M = {}

--------------------------------------------------------------------------
-- AST helpers
--------------------------------------------------------------------------

local function expect(node, tag, msg)
    if not node or node.tag ~= tag then error(msg, 0) end
    return node
end

local function as_sym(node, msg)
    return expect(node, "sym", msg).value
end

local function as_list(node, msg)
    return expect(node, "list", msg)
end

local function atom_text(node, msg)
    if not node then error(msg, 0) end
    if node.tag == "sym" or node.tag == "str" then return node.value end
    if node.tag == "num" then return tostring(node.value) end
    if node.tag == "bool" then return tostring(node.value) end
    if node.tag == "nil" then return "nil" end
    error(msg, 0)
end

local function is_sym(node, s)
    return node and node.tag == "sym" and node.value == s
end

local function copy_set(src)
    local out = {}
    for k, v in pairs(src or {}) do out[k] = v end
    return out
end

--------------------------------------------------------------------------
-- Pattern normalization
--------------------------------------------------------------------------

local function parse_pattern(node)
    if node.tag == "sym" then
        if node.value == "_" then return { tag = "wildcard" } end
        return { tag = "var", name = node.value }
    end
    if node.tag == "num" then return { tag = "num", value = node.value } end
    if node.tag == "str" then return { tag = "str", value = node.value } end
    if node.tag == "bool" then return { tag = "bool", value = node.value } end
    if node.tag == "nil" then return { tag = "nil" } end

    if node.tag == "list" then
        if #node == 0 then error("lisle sema: empty pattern list", 0) end

        if is_sym(node[1], "@") then
            if #node ~= 3 then error("lisle sema: (@ name pat) expects 2 args", 0) end
            return {
                tag = "bind",
                name = as_sym(node[2], "lisle sema: bind name must be symbol"),
                pat = parse_pattern(node[3]),
            }
        end

        local ctor = as_sym(node[1], "lisle sema: ctor pattern head must be symbol")
        local args = {}
        for i = 2, #node do args[#args + 1] = parse_pattern(node[i]) end
        return { tag = "ctor", ctor = ctor, args = args }
    end

    error("lisle sema: unsupported pattern node", 0)
end

local function validate_pattern(pat, env)
    if pat.tag == "wildcard" or pat.tag == "var"
        or pat.tag == "num" or pat.tag == "str"
        or pat.tag == "bool" or pat.tag == "nil" then
        return
    end

    if pat.tag == "bind" then
        validate_pattern(pat.pat, env)
        return
    end

    if pat.tag == "ctor" then
        local c = env.ctors[pat.ctor]
        if not c then error("lisle sema: unknown constructor '" .. tostring(pat.ctor) .. "'", 0) end
        if #pat.args ~= #c.fields then
            error("lisle sema: constructor '" .. tostring(pat.ctor) .. "' arity mismatch: expected "
                .. tostring(#c.fields) .. ", got " .. tostring(#pat.args), 0)
        end
        for i = 1, #pat.args do validate_pattern(pat.args[i], env) end
        return
    end

    error("lisle sema: unknown pattern tag '" .. tostring(pat.tag) .. "'", 0)
end

local function rewrite_zeroary_ctor_pattern(pat, env)
    if pat.tag == "var" then
        local c = env.ctors[pat.name]
        if c and #c.fields == 0 then
            return { tag = "ctor", ctor = pat.name, args = {} }
        end
        return pat
    end

    if pat.tag == "bind" then
        return { tag = "bind", name = pat.name, pat = rewrite_zeroary_ctor_pattern(pat.pat, env) }
    end

    if pat.tag == "ctor" then
        local out = {}
        for i = 1, #pat.args do out[#out + 1] = rewrite_zeroary_ctor_pattern(pat.args[i], env) end
        return { tag = "ctor", ctor = pat.ctor, args = out }
    end

    return pat
end

local function collect_pattern_bindings(pat, out)
    if pat.tag == "var" then
        if pat.name ~= "_" then out[pat.name] = true end
        return
    end

    if pat.tag == "bind" then
        out[pat.name] = true
        collect_pattern_bindings(pat.pat, out)
        return
    end

    if pat.tag == "ctor" then
        for i = 1, #pat.args do collect_pattern_bindings(pat.args[i], out) end
    end
end

--------------------------------------------------------------------------
-- Clause parsing
--------------------------------------------------------------------------

local function parse_when_clause(cl)
    local v = cl[2]
    if not v then error("lisle sema: (when ...) requires one argument", 0) end
    if v.tag == "str" then return { kind = "lua", code = v.value } end
    return { kind = "expr", expr = v }
end

local function parse_rhs_clause(cl)
    local head = as_sym(cl[1], "lisle sema: rhs clause head must be symbol")
    local v = cl[2]
    if not v then error("lisle sema: rhs clause requires one argument", 0) end

    if head == "lua" then
        if v.tag ~= "str" then error("lisle sema: (lua ...) expects string", 0) end
        return { kind = "lua", code = v.value }
    end
    if head == "expr" then
        return { kind = "expr", expr = v }
    end

    error("lisle sema: unsupported rhs clause '" .. tostring(head) .. "'", 0)
end

local function parse_rule_clauses(form, start_i)
    local guard, rhs = nil, nil
    for i = start_i, #form do
        local cl = as_list(form[i], "lisle sema: clause must be list")
        local h = as_sym(cl[1], "lisle sema: clause head must be symbol")
        if h == "when" then
            if guard then error("lisle sema: duplicate (when ...)", 0) end
            guard = parse_when_clause(cl)
        elseif h == "lua" or h == "expr" then
            if rhs then error("lisle sema: duplicate rhs clause", 0) end
            rhs = parse_rhs_clause(cl)
        else
            error("lisle sema: unknown clause '" .. tostring(h) .. "'", 0)
        end
    end
    if not rhs then error("lisle sema: missing rhs clause (lua|expr)", 0) end
    return guard, rhs
end

--------------------------------------------------------------------------
-- Type/term declarations
--------------------------------------------------------------------------

local function parse_arg_decl(node, what)
    if node.tag == "sym" then
        return node.value, nil
    end

    local xs = as_list(node, "lisle sema: " .. what .. " must be symbol or (name type)")
    if #xs ~= 2 then
        error("lisle sema: " .. what .. " typed form must be (name type)", 0)
    end

    local name = as_sym(xs[1], "lisle sema: " .. what .. " name must be symbol")
    local ty = atom_text(xs[2], "lisle sema: " .. what .. " type must be atom")
    return name, ty
end

local function parse_variant(node)
    if node.tag == "sym" then return { name = node.value, fields = {}, field_types = {} } end

    local xs = as_list(node, "lisle sema: variant must be symbol or list")
    if #xs < 1 then error("lisle sema: empty variant", 0) end

    local name = as_sym(xs[1], "lisle sema: variant head must be symbol")
    local fields, field_types = {}, {}
    for i = 2, #xs do
        local fn, ft = parse_arg_decl(xs[i], "variant field")
        fields[#fields + 1] = fn
        field_types[#field_types + 1] = ft
    end
    return { name = name, fields = fields, field_types = field_types }
end

local function parse_attrs(nodes, start_i)
    local attrs = {
        partial = false,
        multi = false,
        extern = false,
        rec = false,
    }

    for i = start_i, #nodes do
        local n = nodes[i]
        if n.tag == "sym" then
            local k = n.value
            if attrs[k] == nil then error("lisle sema: unknown term attr '" .. tostring(k) .. "'", 0) end
            attrs[k] = true
        elseif n.tag == "list" and is_sym(n[1], "attrs") then
            for j = 2, #n do
                local k = as_sym(n[j], "lisle sema: attr name must be symbol")
                if attrs[k] == nil then error("lisle sema: unknown term attr '" .. tostring(k) .. "'", 0) end
                attrs[k] = true
            end
        else
            error("lisle sema: expected attr symbol or (attrs ...)", 0)
        end
    end

    return attrs
end

local function parse_decl_signature(form)
    -- (decl [mods...] name (args...) [ret] [attrs...])
    local i = 2
    local attrs = { partial = false, multi = false, extern = false, rec = false }

    while form[i] and form[i].tag == "sym" do
        local s = form[i].value
        if s == "partial" or s == "multi" or s == "extern" or s == "rec" then
            attrs[s] = true
            i = i + 1
        else
            break
        end
    end

    local name = as_sym(form[i], "lisle sema: decl name must be symbol")
    i = i + 1

    local args_list = as_list(form[i], "lisle sema: decl args must be list")
    i = i + 1

    local args, arg_types = {}, {}
    for ai = 1, #args_list do
        local n = args_list[ai]
        if n.tag == "list" then
            local an, at = parse_arg_decl(n, "decl arg")
            args[#args + 1] = an
            arg_types[#arg_types + 1] = at
        else
            -- ISLE-like decls often provide only arg types; synthesize arg names.
            local ty = atom_text(n, "lisle sema: decl arg type must be atom")
            args[#args + 1] = "a" .. tostring(ai)
            arg_types[#arg_types + 1] = ty
        end
    end

    local ret_type = nil
    if form[i] and (form[i].tag == "sym" or form[i].tag == "str" or form[i].tag == "num" or form[i].tag == "bool" or form[i].tag == "nil") then
        ret_type = atom_text(form[i], "lisle sema: decl return type must be atom")
        i = i + 1
    end

    local trailing = parse_attrs(form, i)
    for k, v in pairs(trailing) do attrs[k] = attrs[k] or v end

    return name, args, arg_types, ret_type, attrs
end

--------------------------------------------------------------------------
-- Overlap / ambiguity checks
--------------------------------------------------------------------------

local function guard_const_bool(g)
    if not g or g.kind ~= "expr" then return nil end
    local e = g.expr
    if not e then return nil end
    if e.tag == "bool" then return e.value and true or false end
    if e.tag == "sym" then
        if e.value == "true" then return true end
        if e.value == "false" then return false end
    end
    return nil
end

local function pattern_overlap(a, b)
    local ta, tb = a.tag, b.tag

    if ta == "bind" then return pattern_overlap(a.pat, b) end
    if tb == "bind" then return pattern_overlap(a, b.pat) end

    if ta == "wildcard" or ta == "var" then return true end
    if tb == "wildcard" or tb == "var" then return true end

    if ta == "ctor" and tb == "ctor" then
        if a.ctor ~= b.ctor then return false end
        for i = 1, #a.args do
            if not pattern_overlap(a.args[i], b.args[i]) then return false end
        end
        return true
    end

    if ta == "num" and tb == "num" then return a.value == b.value end
    if ta == "str" and tb == "str" then return a.value == b.value end
    if ta == "bool" and tb == "bool" then return a.value == b.value end
    if ta == "nil" and tb == "nil" then return true end

    if ta == "num" or ta == "str" or ta == "bool" or ta == "nil" then return false end
    if tb == "num" or tb == "str" or tb == "bool" or tb == "nil" then return false end

    return true
end

local function rules_quick_disjoint(r1, r2)
    for i = 1, #r1.patterns do
        if not pattern_overlap(r1.patterns[i], r2.patterns[i]) then return true end
    end
    local g1, g2 = guard_const_bool(r1.guard), guard_const_bool(r2.guard)
    if g1 == false or g2 == false then return true end
    return false
end

local function ov_var(id) return { tag = "var", id = id } end
local function ov_lit(kind, value) return { tag = "lit", kind = kind, value = value } end
local function ov_ctor(name, args) return { tag = "ctor", name = name, args = args } end

local function lower_pattern_for_overlap(pat, st)
    if pat.tag == "wildcard" then
        st.next_id = st.next_id + 1
        return ov_var(st.next_id)
    end

    if pat.tag == "var" then
        local id = st.vars[pat.name]
        if not id then
            st.next_id = st.next_id + 1
            id = st.next_id
            st.vars[pat.name] = id
        end
        return ov_var(id)
    end

    if pat.tag == "bind" then
        local id = st.vars[pat.name]
        if not id then
            st.next_id = st.next_id + 1
            id = st.next_id
            st.vars[pat.name] = id
        end
        local inner = lower_pattern_for_overlap(pat.pat, st)
        st.eqs[#st.eqs + 1] = { ov_var(id), inner }
        return inner
    end

    if pat.tag == "ctor" then
        local args = {}
        for i = 1, #pat.args do args[#args + 1] = lower_pattern_for_overlap(pat.args[i], st) end
        return ov_ctor(pat.ctor, args)
    end

    if pat.tag == "num" then return ov_lit("num", pat.value) end
    if pat.tag == "str" then return ov_lit("str", pat.value) end
    if pat.tag == "bool" then return ov_lit("bool", pat.value) end
    if pat.tag == "nil" then return ov_lit("nil", nil) end

    error("lisle sema: overlap lowering unsupported pattern tag '" .. tostring(pat.tag) .. "'", 0)
end

local function term_clone(t)
    if t.tag == "var" then return ov_var(t.id) end
    if t.tag == "lit" then return ov_lit(t.kind, t.value) end
    if t.tag == "ctor" then
        local args = {}
        for i = 1, #t.args do args[i] = term_clone(t.args[i]) end
        return ov_ctor(t.name, args)
    end
    error("lisle sema: overlap clone unknown term tag", 0)
end

local function term_shift(t, delta)
    if delta == 0 then return term_clone(t) end
    if t.tag == "var" then return ov_var(t.id + delta) end
    if t.tag == "lit" then return ov_lit(t.kind, t.value) end
    if t.tag == "ctor" then
        local args = {}
        for i = 1, #t.args do args[i] = term_shift(t.args[i], delta) end
        return ov_ctor(t.name, args)
    end
    error("lisle sema: overlap shift unknown term tag", 0)
end

local function unify_maybe(a0, b0, subst)
    local function deref(t)
        while t.tag == "var" do
            local v = subst[t.id]
            if not v then break end
            t = v
        end
        return t
    end

    local function occurs(id, t)
        t = deref(t)
        if t.tag == "var" then return t.id == id end
        if t.tag == "ctor" then
            for i = 1, #t.args do if occurs(id, t.args[i]) then return true end end
        end
        return false
    end

    local function go(a, b)
        a = deref(a)
        b = deref(b)

        if a.tag == "var" then
            if b.tag == "var" and a.id == b.id then return true end
            if occurs(a.id, b) then return false end
            subst[a.id] = b
            return true
        end

        if b.tag == "var" then
            if occurs(b.id, a) then return false end
            subst[b.id] = a
            return true
        end

        if a.tag ~= b.tag then return false end

        if a.tag == "lit" then return a.kind == b.kind and a.value == b.value end
        if a.tag == "ctor" then
            if a.name ~= b.name or #a.args ~= #b.args then return false end
            for i = 1, #a.args do if not go(a.args[i], b.args[i]) then return false end end
            return true
        end

        return false
    end

    return go(a0, b0)
end

local function guard_term(node, ov, env)
    if not node then return nil end

    if node.tag == "num" then return ov_lit("num", node.value) end
    if node.tag == "str" then return ov_lit("str", node.value) end
    if node.tag == "bool" then return ov_lit("bool", node.value) end
    if node.tag == "nil" then return ov_lit("nil", nil) end

    if node.tag == "sym" then
        if node.value == "true" then return ov_lit("bool", true) end
        if node.value == "false" then return ov_lit("bool", false) end
        if node.value == "nil" then return ov_lit("nil", nil) end

        local vid = ov.var_ids and ov.var_ids[node.value]
        if vid then return ov_var(vid) end

        local c = env and env.ctors and env.ctors[node.value]
        if c and #c.fields == 0 then return ov_ctor(node.value, {}) end
    end

    return nil
end

local function guard_info_empty()
    return { unknown = false, unsat = false, eqs = {}, nes = {} }
end

local function merge_guard_info(into, child)
    if child.unsat then
        into.unsat = true
        return
    end
    if child.unknown then into.unknown = true end
    for i = 1, #child.eqs do into.eqs[#into.eqs + 1] = child.eqs[i] end
    for i = 1, #child.nes do into.nes[#into.nes + 1] = child.nes[i] end
end

local function extract_guard_constraints_expr(node, ov, env)
    if not node then return guard_info_empty() end

    if node.tag == "bool" then
        if node.value then return guard_info_empty() end
        return { unknown = false, unsat = true, eqs = {}, nes = {} }
    end

    if node.tag == "sym" then
        if node.value == "true" then return guard_info_empty() end
        if node.value == "false" then return { unknown = false, unsat = true, eqs = {}, nes = {} } end
        return { unknown = true, unsat = false, eqs = {}, nes = {} }
    end

    if node.tag ~= "list" or #node == 0 then
        return { unknown = true, unsat = false, eqs = {}, nes = {} }
    end

    local head = node[1]
    if head.tag ~= "sym" then
        return { unknown = true, unsat = false, eqs = {}, nes = {} }
    end

    local h = head.value

    if h == "and" then
        local out = guard_info_empty()
        for i = 2, #node do
            local ci = extract_guard_constraints_expr(node[i], ov, env)
            merge_guard_info(out, ci)
            if out.unsat then return out end
        end
        return out
    end

    if h == "or" then
        local sat_infos = {}
        for i = 2, #node do
            local ci = extract_guard_constraints_expr(node[i], ov, env)
            if ci.unknown then
                return { unknown = true, unsat = false, eqs = {}, nes = {} }
            end
            if not ci.unsat then sat_infos[#sat_infos + 1] = ci end
        end

        if #sat_infos == 0 then
            return { unknown = false, unsat = true, eqs = {}, nes = {} }
        end
        if #sat_infos == 1 then return sat_infos[1] end
        return { unknown = true, unsat = false, eqs = {}, nes = {} }
    end

    if h == "not" and #node == 2 then
        local ci = extract_guard_constraints_expr(node[2], ov, env)
        if ci.unsat then return guard_info_empty() end
        if ci.unknown then return { unknown = true, unsat = false, eqs = {}, nes = {} } end
        if #ci.eqs == 1 and #ci.nes == 0 then
            return { unknown = false, unsat = false, eqs = {}, nes = { ci.eqs[1] } }
        end
        if #ci.eqs == 0 and #ci.nes == 1 then
            return { unknown = false, unsat = false, eqs = { ci.nes[1] }, nes = {} }
        end
        return { unknown = true, unsat = false, eqs = {}, nes = {} }
    end

    if (h == "=" or h == "~=") and #node == 3 then
        local a = guard_term(node[2], ov, env)
        local b = guard_term(node[3], ov, env)
        if not a or not b then return { unknown = true, unsat = false, eqs = {}, nes = {} } end
        if h == "=" then
            return { unknown = false, unsat = false, eqs = { { a, b } }, nes = {} }
        else
            return { unknown = false, unsat = false, eqs = {}, nes = { { a, b } } }
        end
    end

    return { unknown = true, unsat = false, eqs = {}, nes = {} }
end

local function prepare_rule_overlap(rule, env)
    local st = { vars = {}, next_id = 0, eqs = {} }
    local terms = {}
    for i = 1, #rule.patterns do terms[i] = lower_pattern_for_overlap(rule.patterns[i], st) end

    local ov = {
        terms = terms,
        eqs = st.eqs,
        nes = {},
        max_id = st.next_id,
        var_ids = st.vars,
        guard_unsat = false,
    }

    if rule.guard and rule.guard.kind == "expr" then
        local gi = extract_guard_constraints_expr(rule.guard.expr, ov, env)
        if gi.unsat then
            ov.guard_unsat = true
        else
            for i = 1, #gi.eqs do ov.eqs[#ov.eqs + 1] = gi.eqs[i] end
            for i = 1, #gi.nes do ov.nes[#ov.nes + 1] = gi.nes[i] end
        end
    end

    return ov
end

local function deref_term(subst, t)
    while t.tag == "var" do
        local v = subst[t.id]
        if not v then break end
        t = v
    end
    return t
end

local function definitely_equal(subst, a, b)
    a = deref_term(subst, a)
    b = deref_term(subst, b)

    if a.tag == "var" and b.tag == "var" then return a.id == b.id end
    if a.tag ~= b.tag then return false end

    if a.tag == "lit" then return a.kind == b.kind and a.value == b.value end
    if a.tag == "ctor" then
        if a.name ~= b.name or #a.args ~= #b.args then return false end
        for i = 1, #a.args do
            if not definitely_equal(subst, a.args[i], b.args[i]) then return false end
        end
        return true
    end

    return false
end

local function rules_maybe_overlap(r1, r2)
    if rules_quick_disjoint(r1, r2) then return false end

    local o1 = r1._ov or prepare_rule_overlap(r1)
    local o2 = r2._ov or prepare_rule_overlap(r2)
    if o1.guard_unsat or o2.guard_unsat then return false end

    local subst = {}

    for i = 1, #o1.terms do
        if not unify_maybe(term_clone(o1.terms[i]), term_shift(o2.terms[i], o1.max_id), subst) then
            return false
        end
    end

    for i = 1, #o1.eqs do
        if not unify_maybe(term_clone(o1.eqs[i][1]), term_clone(o1.eqs[i][2]), subst) then return false end
    end
    for i = 1, #o2.eqs do
        if not unify_maybe(term_shift(o2.eqs[i][1], o1.max_id), term_shift(o2.eqs[i][2], o1.max_id), subst) then
            return false
        end
    end

    for i = 1, #o1.nes do
        if definitely_equal(subst, o1.nes[i][1], o1.nes[i][2]) then return false end
    end
    for i = 1, #o2.nes do
        if definitely_equal(subst, term_shift(o2.nes[i][1], o1.max_id), term_shift(o2.nes[i][2], o1.max_id)) then
            return false
        end
    end

    return true
end

--------------------------------------------------------------------------
-- Expression validation
--------------------------------------------------------------------------

local function is_multi_term_call_expr(node, terms)
    if not node or node.tag ~= "list" or #node == 0 then return false end
    local h = node[1]
    if not h or h.tag ~= "sym" then return false end
    local t = terms[h.value]
    return t and t.attrs and t.attrs.multi or false
end

local INFIX_BINARY = {
    ["+"] = true, ["-"] = true, ["*"] = true, ["/"] = true, ["%"] = true,
    ["="] = true, ["~="] = true, ["<"] = true, ["<="] = true, [">"] = true, [">="] = true,
}

local function validate_expr(node, out, vars, allow_multi)
    local terms, ctors = out.terms, out.ctors

    if not node then return end

    if node.tag == "num" or node.tag == "str" or node.tag == "bool" or node.tag == "nil" then return end

    if node.tag == "sym" then
        local n = node.value
        if n == "true" or n == "false" or n == "nil" then return end
        if vars[n] then return end
        local c = ctors[n]
        if c and #c.fields == 0 then return end
        error("lisle sema: unbound symbol in expression '" .. tostring(n) .. "'", 0)
    end

    if node.tag ~= "list" then error("lisle sema: invalid expression node '" .. tostring(node.tag) .. "'", 0) end
    if #node == 0 then error("lisle sema: empty expression list", 0) end

    local h = node[1]
    if h.tag ~= "sym" then error("lisle sema: expression head must be symbol", 0) end
    local name = h.value

    if name == "if" then
        if #node ~= 4 then error("lisle sema: (if cond then else) expects 3 args", 0) end
        validate_expr(node[2], out, vars, false)
        validate_expr(node[3], out, vars, false)
        validate_expr(node[4], out, vars, false)
        return
    end

    if name == "if-let" then
        if #node ~= 4 then error("lisle sema: (if-let (pat expr) then else) expects 3 args", 0) end
        local pair = node[2]
        if pair.tag ~= "list" or #pair ~= 2 then error("lisle sema: if-let binding must be (pattern expr)", 0) end

        local p = rewrite_zeroary_ctor_pattern(parse_pattern(pair[1]), out)
        validate_pattern(p, out)
        validate_expr(pair[2], out, vars, true)

        local vars_then = copy_set(vars)
        collect_pattern_bindings(p, vars_then)
        validate_expr(node[3], out, vars_then, false)
        validate_expr(node[4], out, vars, false)
        return
    end

    if name == "match" then
        if #node < 3 then error("lisle sema: (match value arm...) requires at least one arm", 0) end
        validate_expr(node[2], out, vars, false)

        local seen_default = false
        for i = 3, #node do
            local arm = node[i]
            if arm.tag ~= "list" or #arm ~= 2 then
                error("lisle sema: match arm must be (pattern expr) or (default expr)", 0)
            end

            if arm[1].tag == "sym" and arm[1].value == "default" then
                if seen_default then error("lisle sema: duplicate match default arm", 0) end
                seen_default = true
                validate_expr(arm[2], out, vars, false)
            else
                if seen_default then
                    error("lisle sema: match default arm must be last", 0)
                end
                local p = rewrite_zeroary_ctor_pattern(parse_pattern(arm[1]), out)
                validate_pattern(p, out)
                local vars_arm = copy_set(vars)
                collect_pattern_bindings(p, vars_arm)
                validate_expr(arm[2], out, vars_arm, false)
            end
        end
        return
    end

    if name == "do" then
        for i = 2, #node do validate_expr(node[i], out, vars, false) end
        return
    end

    if name == "let" then
        if #node ~= 3 then error("lisle sema: (let ((name expr)...) body) expects 2 args", 0) end
        local binds = as_list(node[2], "lisle sema: let bindings must be list")
        local vars_let = copy_set(vars)
        for i = 1, #binds do
            local b = as_list(binds[i], "lisle sema: let binding must be (name expr)")
            if #b ~= 2 then error("lisle sema: let binding must be (name expr)", 0) end
            local bn = as_sym(b[1], "lisle sema: let binding name must be symbol")
            validate_expr(b[2], out, vars_let, false)
            vars_let[bn] = true
        end
        validate_expr(node[3], out, vars_let, false)
        return
    end

    if name == "collect" then
        if #node ~= 2 then error("lisle sema: (collect expr) expects 1 arg", 0) end
        if not is_multi_term_call_expr(node[2], terms) then
            error("lisle sema: (collect ...) expects multi term call", 0)
        end
        validate_expr(node[2], out, vars, true)
        return
    end

    if name == "first" then
        if #node ~= 2 and #node ~= 3 then error("lisle sema: (first multi-call [default]) arity mismatch", 0) end
        if not is_multi_term_call_expr(node[2], terms) then
            error("lisle sema: (first ...) expects multi term call", 0)
        end
        validate_expr(node[2], out, vars, true)
        if #node == 3 then validate_expr(node[3], out, vars, false) end
        return
    end

    if name == "any" then
        if #node ~= 2 then error("lisle sema: (any multi-call) expects 1 arg", 0) end
        if not is_multi_term_call_expr(node[2], terms) then
            error("lisle sema: (any ...) expects multi term call", 0)
        end
        validate_expr(node[2], out, vars, true)
        return
    end

    if name == "not" then
        if #node ~= 2 then error("lisle sema: (not x) expects 1 arg", 0) end
        validate_expr(node[2], out, vars, false)
        return
    end

    if name == "and" or name == "or" then
        if #node < 3 then error("lisle sema: (" .. name .. " ...) expects at least 2 args", 0) end
        for i = 2, #node do validate_expr(node[i], out, vars, false) end
        return
    end

    if INFIX_BINARY[name] then
        if #node ~= 3 then error("lisle sema: binary op '" .. name .. "' expects 2 args", 0) end
        validate_expr(node[2], out, vars, false)
        validate_expr(node[3], out, vars, false)
        return
    end

    local term = terms[name]
    if term then
        if term.attrs.multi and not allow_multi then
            error("lisle sema: multi term '" .. name .. "' used in scalar expression context", 0)
        end
        if #node - 1 ~= #term.args then
            error("lisle sema: term call '" .. name .. "' arity mismatch: expected "
                .. tostring(#term.args) .. ", got " .. tostring(#node - 1), 0)
        end
        for i = 2, #node do validate_expr(node[i], out, vars, false) end
        return
    end

    local ctor = ctors[name]
    if ctor then
        if #node - 1 ~= #ctor.fields then
            error("lisle sema: ctor call '" .. name .. "' arity mismatch: expected "
                .. tostring(#ctor.fields) .. ", got " .. tostring(#node - 1), 0)
        end
        for i = 2, #node do validate_expr(node[i], out, vars, false) end
        return
    end

    -- External helper/extractor call.
    for i = 2, #node do validate_expr(node[i], out, vars, false) end
end

--------------------------------------------------------------------------
-- Recursion checks
--------------------------------------------------------------------------

local function collect_term_refs_expr(node, terms, out_refs)
    if not node or node.tag ~= "list" or #node == 0 then return end
    local head = node[1]
    if head.tag == "sym" and terms[head.value] then
        out_refs[head.value] = true
    end
    for i = 1, #node do collect_term_refs_expr(node[i], terms, out_refs) end
end

local function collect_rule_edges(term_name, rules, def, terms)
    local refs = {}
    local function from_clause(cl)
        if cl and cl.kind == "expr" then collect_term_refs_expr(cl.expr, terms, refs) end
    end

    for i = 1, #rules do
        from_clause(rules[i].guard)
        from_clause(rules[i].rhs)
    end
    if def then
        from_clause(def.guard)
        from_clause(def.rhs)
    end
    return refs
end

local function scc(graph, nodes)
    local idx, low = {}, {}
    local st, on = {}, {}
    local n = 0
    local comps = {}

    local function push(v) st[#st + 1] = v; on[v] = true end
    local function pop_to(v)
        local comp = {}
        while #st > 0 do
            local w = st[#st]
            st[#st] = nil
            on[w] = nil
            comp[#comp + 1] = w
            if w == v then break end
        end
        comps[#comps + 1] = comp
    end

    local function visit(v)
        n = n + 1
        idx[v], low[v] = n, n
        push(v)

        for w in pairs(graph[v] or {}) do
            if not idx[w] then
                visit(w)
                if low[w] < low[v] then low[v] = low[w] end
            elseif on[w] and idx[w] < low[v] then
                low[v] = idx[w]
            end
        end

        if low[v] == idx[v] then pop_to(v) end
    end

    for i = 1, #nodes do
        local v = nodes[i]
        if not idx[v] then visit(v) end
    end

    return comps
end

local function run_recursion_checks(out)
    local terms = {}
    for t in pairs(out.terms) do terms[#terms + 1] = t end
    table.sort(terms)

    local graph = {}
    for i = 1, #terms do
        local t = terms[i]
        graph[t] = collect_rule_edges(t, out.rules[t] or {}, out.defaults[t], out.terms)
    end

    local comps = scc(graph, terms)
    for i = 1, #comps do
        local comp = comps[i]
        if #comp > 1 then
            for j = 1, #comp do
                local t = comp[j]
                if not out.terms[t].attrs.rec then
                    error("lisle sema: recursive cycle requires 'rec' attr on term '" .. t .. "'", 0)
                end
            end
        else
            local t = comp[1]
            if graph[t] and graph[t][t] and not out.terms[t].attrs.rec then
                error("lisle sema: self recursion requires 'rec' attr on term '" .. t .. "'", 0)
            end
        end
    end
end

--------------------------------------------------------------------------
-- Main analysis
--------------------------------------------------------------------------

function M.analyze(forms)
    local out = {
        types = {},
        ctors = {},
        terms = {},
        rules = {},
        defaults = {},
        extern_constructors = {},
        extern_extractors = {},
    }

    local function define_term(name, args, arg_types, ret_type, attrs)
        local prev = out.terms[name]
        local a = attrs or { partial = false, multi = false, extern = false, rec = false }
        local at = arg_types or {}

        if prev then
            if #prev.args ~= #args then
                error("lisle sema: term '" .. name .. "' redeclared with different arity", 0)
            end
            for i = 1, #args do
                if prev.args[i] ~= args[i] then
                    error("lisle sema: term '" .. name .. "' arg name mismatch at position " .. tostring(i), 0)
                end
                local old_ty, new_ty = prev.arg_types[i], at[i]
                if old_ty and new_ty and old_ty ~= new_ty then
                    error("lisle sema: term '" .. name .. "' arg type mismatch at position " .. tostring(i)
                        .. " ('" .. tostring(old_ty) .. "' vs '" .. tostring(new_ty) .. "')", 0)
                elseif (not old_ty) and new_ty then
                    prev.arg_types[i] = new_ty
                end
            end
            if prev.ret_type and ret_type and prev.ret_type ~= ret_type then
                error("lisle sema: term '" .. name .. "' return type mismatch ('"
                    .. tostring(prev.ret_type) .. "' vs '" .. tostring(ret_type) .. "')", 0)
            elseif (not prev.ret_type) and ret_type then
                prev.ret_type = ret_type
            end

            prev.attrs.partial = prev.attrs.partial or a.partial
            prev.attrs.multi = prev.attrs.multi or a.multi
            prev.attrs.extern = prev.attrs.extern or a.extern
            prev.attrs.rec = prev.attrs.rec or a.rec
            return
        end

        out.terms[name] = {
            name = name,
            args = args,
            arg_types = at,
            ret_type = ret_type,
            attrs = {
                partial = a.partial and true or false,
                multi = a.multi and true or false,
                extern = a.extern and true or false,
                rec = a.rec and true or false,
            },
        }
        out.rules[name] = out.rules[name] or {}
    end

    -- Pass 1: collect declarations/forms.
    for i = 1, #forms do
        local f = as_list(forms[i], "lisle sema: top-level form must be list")
        local head = as_sym(f[1], "lisle sema: form head must be symbol")

        if head == "type" then
            local tname = as_sym(f[2], "lisle sema: type name must be symbol")
            if out.types[tname] then error("lisle sema: duplicate type '" .. tname .. "'", 0) end

            local vars = {}
            local start = 3
            if f[3] and f[3].tag == "list" and is_sym(f[3][1], "enum") then
                local enum = f[3]
                for j = 2, #enum do
                    local v = parse_variant(enum[j])
                    if out.ctors[v.name] then error("lisle sema: duplicate constructor '" .. v.name .. "'", 0) end
                    out.ctors[v.name] = { type_name = tname, fields = v.fields, field_types = v.field_types }
                    vars[#vars + 1] = v
                end
                start = #f + 1
            elseif f[3] and f[3].tag == "list" and is_sym(f[3][1], "primitive") then
                -- primitive type marker; no constructors
                start = #f + 1
            end

            for j = start, #f do
                local v = parse_variant(f[j])
                if out.ctors[v.name] then error("lisle sema: duplicate constructor '" .. v.name .. "'", 0) end
                out.ctors[v.name] = { type_name = tname, fields = v.fields, field_types = v.field_types }
                vars[#vars + 1] = v
            end

            out.types[tname] = { name = tname, variants = vars }

        elseif head == "term" then
            local tname = as_sym(f[2], "lisle sema: term name must be symbol")
            local args_ast = as_list(f[3], "lisle sema: term args must be list")
            local args, arg_types = {}, {}
            for j = 1, #args_ast do
                local an, at = parse_arg_decl(args_ast[j], "term arg")
                args[#args + 1] = an
                arg_types[#arg_types + 1] = at
            end
            define_term(tname, args, arg_types, nil, parse_attrs(f, 4))

        elseif head == "decl" then
            local tname, args, arg_types, ret_type, attrs = parse_decl_signature(f)
            define_term(tname, args, arg_types, ret_type, attrs)

        elseif head == "extern" then
            if is_sym(f[2], "constructor") then
                local ctor_name = as_sym(f[3], "lisle sema: extern constructor name must be symbol")
                local lua_name = as_sym(f[4], "lisle sema: extern constructor lua name must be symbol")
                out.extern_constructors[ctor_name] = lua_name

            elseif is_sym(f[2], "extractor") then
                local term_name = as_sym(f[3], "lisle sema: extern extractor term must be symbol")
                local lua_name = as_sym(f[4], "lisle sema: extern extractor lua name must be symbol")
                out.extern_extractors[term_name] = lua_name
                if out.terms[term_name] then
                    out.terms[term_name].attrs.extern = true
                end

            else
                local tname = as_sym(f[2], "lisle sema: extern term name must be symbol")
                local args, arg_types, attrs, ret_type
                if f[3] and f[3].tag == "list" then
                    local arg_list = as_list(f[3], "lisle sema: extern args must be list")
                    args, arg_types = {}, {}
                    for j = 1, #arg_list do
                        local an, at = parse_arg_decl(arg_list[j], "extern arg")
                        args[#args + 1] = an
                        arg_types[#arg_types + 1] = at
                    end
                    local pos = 4
                    ret_type = nil
                    if f[pos] and (f[pos].tag == "sym" or f[pos].tag == "str" or f[pos].tag == "num" or f[pos].tag == "bool" or f[pos].tag == "nil") then
                        ret_type = atom_text(f[pos], "lisle sema: extern return type must be atom")
                        pos = pos + 1
                    end
                    attrs = parse_attrs(f, pos)
                else
                    args, arg_types = {}, {}
                    attrs = { partial = false, multi = false, extern = false, rec = false }
                    ret_type = nil
                end
                attrs.extern = true
                if not attrs.partial then attrs.partial = true end
                define_term(tname, args, arg_types, ret_type, attrs)
            end

        elseif head == "rule" then
            local tname = as_sym(f[2], "lisle sema: rule term must be symbol")
            local prio = tonumber(atom_text(f[3], "lisle sema: rule priority must be numeric atom"))
            if not prio then error("lisle sema: invalid rule priority", 0) end

            local pats = as_list(f[4], "lisle sema: rule pattern list required")
            local guard, rhs = parse_rule_clauses(f, 5)

            local norm = {}
            for j = 1, #pats do norm[#norm + 1] = parse_pattern(pats[j]) end

            out.rules[tname] = out.rules[tname] or {}
            out.rules[tname][#out.rules[tname] + 1] = {
                term = tname,
                prio = prio,
                patterns = norm,
                guard = guard,
                rhs = rhs,
            }

        elseif head == "default" then
            local tname = as_sym(f[2], "lisle sema: default term must be symbol")
            if out.defaults[tname] then error("lisle sema: duplicate default for term '" .. tname .. "'", 0) end
            local guard, rhs = parse_rule_clauses(f, 3)
            out.defaults[tname] = { guard = guard, rhs = rhs }

        else
            error("lisle sema: unknown top-level form '" .. tostring(head) .. "'", 0)
        end
    end

    -- Validate extern constructor targets now that all types are known.
    for ctor_name in pairs(out.extern_constructors) do
        if not out.ctors[ctor_name] then
            error("lisle sema: extern constructor references unknown ctor '" .. tostring(ctor_name) .. "'", 0)
        end
    end

    -- Validate extern extractor targets now that all terms are known.
    for term_name in pairs(out.extern_extractors) do
        local t = out.terms[term_name]
        if not t then
            error("lisle sema: extern extractor references unknown term '" .. tostring(term_name) .. "'", 0)
        end
        t.attrs.extern = true
    end

    -- Pass 2: validate rules and expressions.
    for tname, rs in pairs(out.rules) do
        local term = out.terms[tname]
        if not term then error("lisle sema: rules reference unknown term '" .. tostring(tname) .. "'", 0) end

        for i = 1, #rs do
            local r = rs[i]
            if #r.patterns ~= #term.args then
                error("lisle sema: rule for term '" .. tname .. "' has " .. tostring(#r.patterns)
                    .. " patterns, expected " .. tostring(#term.args), 0)
            end

            for j = 1, #r.patterns do
                validate_pattern(r.patterns[j], out)
                r.patterns[j] = rewrite_zeroary_ctor_pattern(r.patterns[j], out)
            end

            local vars = {}
            for j = 1, #term.args do vars[term.args[j]] = true end
            for j = 1, #r.patterns do collect_pattern_bindings(r.patterns[j], vars) end

            if r.guard and r.guard.kind == "expr" then validate_expr(r.guard.expr, out, vars, false) end
            if r.rhs and r.rhs.kind == "expr" then validate_expr(r.rhs.expr, out, vars, false) end

            r._ov = prepare_rule_overlap(r, out)
        end

        table.sort(rs, function(a, b)
            if a.prio ~= b.prio then return a.prio > b.prio end
            return tostring(a.rhs.kind) < tostring(b.rhs.kind)
        end)

        for i = 1, #rs do
            for j = i + 1, #rs do
                if rs[i].prio ~= rs[j].prio then break end
                if rules_maybe_overlap(rs[i], rs[j]) then
                    error("lisle sema: ambiguous equal-priority overlap in term '" .. tname
                        .. "' at priority " .. tostring(rs[i].prio), 0)
                end
            end
        end
    end

    for tname, d in pairs(out.defaults) do
        local term = out.terms[tname]
        if not term then error("lisle sema: default references unknown term '" .. tostring(tname) .. "'", 0) end

        local vars = {}
        for i = 1, #term.args do vars[term.args[i]] = true end
        if d.guard and d.guard.kind == "expr" then validate_expr(d.guard.expr, out, vars, false) end
        if d.rhs and d.rhs.kind == "expr" then validate_expr(d.rhs.expr, out, vars, false) end
    end

    -- Contract checks for term/extractor completeness.
    for tname, term in pairs(out.terms) do
        local has_rules = #((out.rules[tname]) or {}) > 0
        local has_default = out.defaults[tname] ~= nil
        if (not term.attrs.partial) and (not term.attrs.extern) and (not has_rules) and (not has_default) then
            error("lisle sema: non-partial term '" .. tname .. "' has no rules/default", 0)
        end
    end

    run_recursion_checks(out)
    return out
end

return M
