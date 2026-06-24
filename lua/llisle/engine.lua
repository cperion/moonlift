local llb = require("llb")
local dsl = require("llisle.dsl")

local M = {}

local Engine = {}
Engine.__index = Engine

local function is_cls(v, name) return dsl.cls(v) == name end
local function is_binder(v) return is_cls(v, "Binder") end
local function path_name(path, i) return tostring((path or {})[i] or "") end
local function root_key(b) return path_name(b.path, 1) end

local SKIP_FIELDS = {
    __llb = true,
    __llb_tag = true,
    origin = true,
    n = true,
}

local function table_keys(t)
    local out = {}
    for k in pairs(t or {}) do
        if not SKIP_FIELDS[k] then out[#out + 1] = k end
    end
    table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
    return out
end

local function has_record_fields(t)
    if type(t) ~= "table" then return false end
    for k in pairs(t) do if type(k) ~= "number" and not SKIP_FIELDS[k] then return true end end
    return false
end

local function shallow_copy(t)
    local out = {}
    for k, v in pairs(t or {}) do out[k] = v end
    return out
end

local function copy_bindings(src)
    local out = { P = {}, V = {}, T = {} }
    for space, map in pairs(src or {}) do
        out[space] = out[space] or {}
        for k, v in pairs(map) do out[space][k] = v end
    end
    return out
end

local function copy_state(state)
    local out = {
        engine = state.engine,
        bindings = copy_bindings(state.bindings),
        effects = {},
        cost = state.cost or 0,
        fresh_id = state.fresh_id or 0,
        rule = state.rule,
        alt = state.alt,
    }
    for i, effect in ipairs(state.effects or {}) do out.effects[i] = effect end
    return out
end

local function default_equal(a, b, seen)
    if a == b then return true end
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return false end
    seen = seen or {}
    seen[a] = seen[a] or {}
    if seen[a][b] then return true end
    seen[a][b] = true
    if llb.tagof(a) ~= llb.tagof(b) then return false end
    local ak, bk = table_keys(a), table_keys(b)
    if #ak ~= #bk then return false end
    for i = 1, #ak do
        if ak[i] ~= bk[i] then return false end
        if not default_equal(a[ak[i]], b[bk[i]], seen) then return false end
    end
    return true
end

local function symbol_name(v)
    if llb.is(v, "Symbol") or llb.is(v, "Name") then return tostring(v.text) end
    if type(v) == "string" then return v end
    return nil
end

local function semantic_key_text(k)
    if llb.is(k, "Symbol") or llb.is(k, "Name") then return tostring(k.text) end
    if type(k) == "table" then
        local text = rawget(k, "text") or rawget(k, "name") or rawget(k, "field")
        if text ~= nil then return tostring(text) end
    end
    if type(k) == "string" or type(k) == "number" then return tostring(k) end
    return nil
end

local function field_get(engine, base, key)
    if type(base) ~= "table" then return nil end
    if rawget(base, key) ~= nil then return rawget(base, key) end
    local text = semantic_key_text(key)
    if text == nil then return nil end
    if rawget(base, text) ~= nil then return rawget(base, text) end
    local shared = engine and engine.symbols and engine.symbols[text] or nil
    if shared ~= nil and rawget(base, shared) ~= nil then return rawget(base, shared) end
    for k, v in pairs(base) do
        if semantic_key_text(k) == text then return v end
    end
    return nil
end

local function node_name(v)
    if type(v) ~= "table" then return nil end
    return rawget(v, "kind") or rawget(v, "tag") or rawget(v, "name") or rawget(v, "op") or symbol_name(v)
end

local function relation_call_of(rule)
    local found
    for _, item in ipairs(rule.body or {}) do
        if is_cls(item, "RelationCall") then
            if found then return nil end
            found = item
        end
    end
    return found
end

local function product_kind(spec, kind)
    for _, item in ipairs(spec.body or {}) do
        if is_cls(item, "ProductSpec") and item.kind == kind then return item end
    end
    return nil
end

local function directive_value(items, kind)
    for _, item in ipairs(items or {}) do
        if is_cls(item, "Directive") and item.kind == kind then return item.value end
    end
    return nil
end

local function strategy_for(rel)
    local out = { select = "first", ambiguity = "first", coverage = "partial" }
    for _, item in ipairs(rel.body or {}) do
        if is_cls(item, "StrategySpec") then
            out.select = directive_value(item.body, "select") or out.select
            out.ambiguity = directive_value(item.body, "ambiguity") or out.ambiguity
            out.coverage = directive_value(item.body, "coverage") or out.coverage
        end
    end
    return out
end

local function payload_items(payload)
    if has_record_fields(payload) then
        local out = {}
        for _, k in ipairs(table_keys(payload)) do out[#out + 1] = { name = k, value = payload[k] } end
        return out, true
    end
    local out = {}
    for i = 1, #(payload or {}) do out[i] = payload[i] end
    return out, false
end

local match_pattern
local resolve_binder

local function bind_pattern(state, binder, actual)
    local space, key = binder.space, root_key(binder)
    state.bindings[space] = state.bindings[space] or {}
    local existing = state.bindings[space][key]
    if #(binder.path or {}) > 1 then
        local projected = resolve_binder and resolve_binder(state, binder) or nil
        return projected ~= nil and (state.engine.equal or default_equal)(projected, actual)
    end
    if existing == nil then
        state.bindings[space][key] = actual
        return true
    end
    return (state.engine.equal or default_equal)(existing, actual)
end

local function match_record_fields(state, pattern, actual)
    if type(actual) ~= "table" then return false end
    for _, k in ipairs(table_keys(pattern)) do
        if not match_pattern(state, pattern[k], field_get(state.engine, actual, k)) then return false end
    end
    return true
end

local function first_arg_record(expr)
    local args = expr.args or {}
    local n = args.n or #args
    if n == 1 and type(args[1]) == "table" then return args[1] end
    return nil
end

local function match_expr_pattern(state, pattern, actual)
    if pattern.kind == "index" then
        if llb.is(actual, "Expr") and actual.kind == "index" then
            return match_pattern(state, pattern.base, actual.base) and match_pattern(state, pattern.index, actual.index)
        end
        if type(actual) == "table" and (rawget(actual, "ty") ~= nil or rawget(actual, "type") ~= nil) then
            return match_pattern(state, pattern.base, actual) and match_pattern(state, pattern.index, rawget(actual, "ty") or rawget(actual, "type"))
        end
        return false
    end

    if pattern.kind == "call" then
        local callee = symbol_name(pattern.callee)
        if callee ~= nil and not llb.is(actual, "Expr") then
            if semantic_key_text(node_name(actual)) ~= callee then return false end
            local record = first_arg_record(pattern)
            if record then return match_record_fields(state, record, actual) end
        end
    end

    if pattern.kind == "ctor" then
        local name = tostring(pattern.name)
        if not llb.is(actual, "Expr") then
            if semantic_key_text(node_name(actual)) ~= name then return false end
            local args = pattern.args or {}
            local n = args.n or #args
            if n == 1 and type(args[1]) == "table" then return match_record_fields(state, args[1], actual) end
        end
    end

    if not llb.is(actual, "Expr") or pattern.kind ~= actual.kind then return false end
    return match_record_fields(state, pattern, actual)
end

match_pattern = function(state, pattern, actual)
    if is_binder(pattern) then return bind_pattern(state, pattern, actual) end
    if llb.is(pattern, "Expr") then return match_expr_pattern(state, pattern, actual) end
    if llb.is(pattern, "Symbol") or llb.is(pattern, "Name") then
        local name = symbol_name(pattern)
        return semantic_key_text(actual) == name or semantic_key_text(node_name(actual)) == name
    end
    if type(pattern) == "table" then
        if (state.engine.equal or default_equal)(pattern, actual) then return true end
        return match_record_fields(state, pattern, actual)
    end
    return pattern == actual
end

local eval_value

resolve_binder = function(state, binder)
    local space, key = binder.space, root_key(binder)
    state.bindings[space] = state.bindings[space] or {}
    local value = state.bindings[space][key]
    if value == nil and space == "V" then
        state.fresh_id = (state.fresh_id or 0) + 1
        local fresh = state.engine.fresh or function(name) return { kind = "llisle_value", name = name } end
        value = fresh(key, state.fresh_id, state)
        state.bindings[space][key] = value
    elseif value == nil then
        return nil
    end
    for i = 2, #(binder.path or {}) do
        value = field_get(state.engine, value, path_name(binder.path, i))
        if value == nil then return nil end
    end
    return value
end

local function eval_record(state, record)
    local out = {}
    for _, k in ipairs(table_keys(record)) do out[k] = eval_value(state, record[k]) end
    return out
end

local function eval_args(state, args)
    local out = {}
    local n = args and (args.n or #args) or 0
    for i = 1, n do out[i] = eval_value(state, args[i]) end
    return out, n
end

local function build_call(state, name, args, n)
    local decl = state.engine.constructors and state.engine.constructors[name]
    local builder = decl and decl.impl or nil
    if builder then return builder(args[1], args, state) end
    if n == 1 and type(args[1]) == "table" then
        local out = shallow_copy(args[1])
        out.kind = out.kind or name
        return out
    end
    return { kind = name, args = args }
end

local function eval_binop(op, a, b)
    if op == "+" then return a + b end
    if op == "-" then return a - b end
    if op == "*" then return a * b end
    if op == "/" then return a / b end
    if op == "%" then return a % b end
    if op == "==" then return a == b end
    if op == "~=" then return a ~= b end
    if op == "<" then return a < b end
    if op == "<=" then return a <= b end
    if op == ">" then return a > b end
    if op == ">=" then return a >= b end
    error("llisle.engine: unsupported binary operator " .. tostring(op), 2)
end

local function eval_expr(state, expr)
    if expr.kind == "binop" then return eval_binop(expr.op, eval_value(state, expr.a), eval_value(state, expr.b)) end
    if expr.kind == "unop" then
        local v = eval_value(state, expr.a)
        if expr.op == "-" then return -v end
        error("llisle.engine: unsupported unary operator " .. tostring(expr.op), 2)
    end
    if expr.kind == "field" then
        local base = eval_value(state, expr.base)
        return field_get(state.engine, base, expr.field)
    end
    if expr.kind == "index" then
        local base = eval_value(state, expr.base)
        local index = eval_value(state, expr.index)
        return field_get(state.engine, base, index)
    end
    if expr.kind == "call" then
        local callee = symbol_name(expr.callee) or eval_value(state, expr.callee)
        local args, n = eval_args(state, expr.args)
        if type(callee) == "function" then return callee(unpack(args, 1, n)) end
        return build_call(state, tostring(callee), args, n)
    end
    if expr.kind == "ctor" then
        local args, n = eval_args(state, expr.args)
        return build_call(state, tostring(expr.name), args, n)
    end
    error("llisle.engine: unsupported expression kind " .. tostring(expr.kind), 2)
end

eval_value = function(state, value)
    if is_binder(value) then return resolve_binder(state, value) end
    if llb.is(value, "Symbol") or llb.is(value, "Name") then
        local name = symbol_name(value)
        return (state.engine.symbols and state.engine.symbols[name]) or name
    end
    if llb.is(value, "Expr") then return eval_expr(state, value) end
    if is_cls(value, "RelationCall") then
        local fields = eval_record(state, value.fields or {})
        local result, err = state.engine:run(value.name, fields)
        if not result then
            state.last_error = err
            return nil
        end
        for _, effect in ipairs(result.effects or {}) do state.effects[#state.effects + 1] = effect end
        return result.output
    end
    if type(value) == "table" and getmetatable(value) == nil then
        if has_record_fields(value) then return eval_record(state, value) end
        local out = {}
        for i = 1, #value do out[i] = eval_value(state, value[i]) end
        return out
    end
    return value
end

local function eval_payload(state, payload)
    if has_record_fields(payload) then return eval_record(state, payload) end
    local n = #(payload or {})
    if n == 0 then return {} end
    if n == 1 then return eval_value(state, payload[1]) end
    local out = {}
    for i = 1, n do out[i] = eval_value(state, payload[i]) end
    return out
end

local function eval_predicate(state, pred)
    local subject = eval_value(state, pred.subject)
    local args = {}
    for i = 1, #(pred.args or {}) do args[i] = eval_value(state, pred.args[i]) end
    local decl = state.engine.predicate_decls and state.engine.predicate_decls[pred.predicate]
    local host = decl and decl.impl or nil
    if host then return host(subject, unpack(args, 1, #args)) and true or false end
    local eq = state.engine.equal or default_equal
    if pred.predicate == "is" or pred.predicate == "eq" then return eq(subject, args[1]) end
    if pred.predicate == "ne" then return not eq(subject, args[1]) end
    if pred.predicate == "lt" then return subject < args[1] end
    if pred.predicate == "le" then return subject <= args[1] end
    if pred.predicate == "gt" then return subject > args[1] end
    if pred.predicate == "ge" then return subject >= args[1] end
    if pred.predicate == "present" then return subject ~= nil end
    if pred.predicate == "absent" then return subject == nil end
    if pred.predicate == "is_const" then return type(subject) == "table" and subject.kind == "const" end
    if pred.predicate == "call" and type(subject) == "function" then return subject(unpack(args, 1, #args)) and true or false end
    error("llisle.engine: unknown predicate " .. tostring(pred.predicate), 2)
end

local function eval_guard_item(state, item)
    if is_cls(item, "PredicateSpec") then return eval_predicate(state, item) end
    if llb.is_algebra(item) then
        if item.op == "sum" then
            for _, child in ipairs(item.items or {}) do
                if eval_guard_item(state, child) then return true end
            end
            return false
        end
        for _, child in ipairs(item.items or {}) do
            if not eval_guard_item(state, child) then return false end
        end
        return true
    end
    return eval_value(state, item) and true or false
end

local function eval_guards(state, body)
    for _, item in ipairs(body or {}) do
        if not eval_guard_item(state, item) then return false end
    end
    return true
end

local exec_items

local function exec_bind(state, item)
    local value = eval_payload(state, item.body)
    if value == nil then return false end
    state.bindings.V[item.name] = value
    return true
end

local function run_alternative(state, alt)
    local s = copy_state(state)
    s.alt = alt.name
    for _, item in ipairs(alt.body or {}) do
        if is_cls(item, "BindSpec") then
            if not exec_bind(s, item) then return nil end
        elseif is_cls(item, "GuardSpec") and not eval_guards(s, item.body) then
            return nil
        elseif is_cls(item, "Directive") and item.kind == "cost" then
            s.cost = s.cost + tonumber(item.value or 0)
        end
    end
    for _, item in ipairs(alt.body or {}) do
        if is_cls(item, "RunSpec") then
            local ok = exec_items(s, item.body)
            if not ok then return nil end
        end
    end
    return s
end

local function select_candidate(candidates, select)
    if #candidates == 0 then return nil end
    if select == "best_cost" then
        table.sort(candidates, function(a, b)
            if a.cost == b.cost then return tostring(a.rule or "") < tostring(b.rule or "") end
            return (a.cost or 0) < (b.cost or 0)
        end)
    end
    return candidates[1]
end

local function exec_choose(state, choose)
    local candidates = {}
    for _, alt in ipairs(choose.body or {}) do
        if is_cls(alt, "AltSpec") then
            local s = run_alternative(state, alt)
            if s then candidates[#candidates + 1] = s end
        end
    end
    local selected = select_candidate(candidates, "best_cost")
    if not selected then return false end
    state.bindings, state.effects, state.output, state.cost, state.alt =
        selected.bindings, selected.effects, selected.output, selected.cost, selected.alt
    return true
end

exec_items = function(state, items)
    for _, item in ipairs(items or {}) do
        if is_cls(item, "BindSpec") then
            if not exec_bind(state, item) then return false end
        elseif is_cls(item, "EmitSpec") then
            state.effects[#state.effects + 1] = { channel = item.channel, value = eval_payload(state, item.body), origin = item.origin }
        elseif is_cls(item, "RetSpec") then
            state.output = eval_payload(state, item.body)
            return true
        elseif is_cls(item, "FailSpec") then
            return false
        elseif is_cls(item, "ChooseSpec") then
            if not exec_choose(state, item) then return false end
            if state.output ~= nil then return true end
        elseif is_cls(item, "RelationCall") then
            eval_value(state, item)
        end
    end
    return true
end

local function rule_candidate(engine, rule, input)
    local call = relation_call_of(rule)
    if not call then return nil end
    local state = {
        engine = engine,
        bindings = { P = {}, V = {}, T = {} },
        effects = {},
        cost = 0,
        fresh_id = 0,
        rule = rule.name,
    }
    if not match_record_fields(state, call.fields or {}, input or {}) then return nil end
    for _, item in ipairs(rule.body or {}) do
        if is_cls(item, "BindSpec") then
            if not exec_bind(state, item) then return nil end
        elseif is_cls(item, "GuardSpec") and not eval_guards(state, item.body) then
            return nil
        end
    end
    for _, item in ipairs(rule.body or {}) do
        if is_cls(item, "RunSpec") then
            if not exec_items(state, item.body) then return nil end
        elseif is_cls(item, "ChooseSpec") then
            if not exec_choose(state, item) then return nil end
        end
        if state.output ~= nil then break end
    end
    return state
end

function Engine:run(name, input)
    local rel = self.relations[name]
    if not rel then
        return nil, { code = "E_LLISLE_UNKNOWN_RELATION", message = "unknown Llisle relation " .. tostring(name) }
    end
    local candidates = {}
    for _, rule in ipairs(self.rules_by_relation[name] or {}) do
        local state = rule_candidate(self, rule, input or {})
        if state then candidates[#candidates + 1] = state end
    end
    local selected = select_candidate(candidates, strategy_for(rel).select)
    if not selected then
        return nil, { code = "E_LLISLE_NO_MATCH", message = "no Llisle rule matched relation " .. tostring(name) }
    end
    return {
        relation = name,
        rule = selected.rule,
        alt = selected.alt,
        output = selected.output or {},
        effects = selected.effects or {},
        cost = selected.cost or 0,
        bindings = selected.bindings,
    }
end

function M.compile(value, opts)
    opts = opts or {}
    local bag = dsl.diagnostics(value)
    if bag:has_errors() then error(bag:render(), 2) end
    local engine = setmetatable({
        relations = {},
        rules_by_relation = {},
        predicate_decls = {},
        constructors = {},
        symbols = opts.symbols or {},
        fresh = opts.fresh,
        equal = opts.equal or default_equal,
    }, Engine)
    for _, item in ipairs(dsl.collect({}, value)) do
        if is_cls(item, "RelationSpec") then
            engine.relations[item.name] = item
            product_kind(item, "input")
            product_kind(item, "output")
        elseif is_cls(item, "PredicateDecl") then
            engine.predicate_decls[item.name] = item
        elseif is_cls(item, "ConstructorDecl") then
            engine.constructors[item.name] = item
        elseif is_cls(item, "RuleSpec") then
            local call = relation_call_of(item)
            if call then
                engine.rules_by_relation[call.name] = engine.rules_by_relation[call.name] or {}
                engine.rules_by_relation[call.name][#engine.rules_by_relation[call.name] + 1] = item
            end
        end
    end
    return engine
end

function M.run(value, relation, input, opts)
    return M.compile(value, opts):run(relation, input)
end

M.Engine = Engine
M.default_equal = default_equal

return M
