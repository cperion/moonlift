local llb = require("llb")

local M = {}

local function class(name)
    local mt = { __lisle_class = name }
    mt.__index = mt
    return mt
end

local Binder = class("Binder")
local Field = class("Field")
local RelationSpec = class("RelationSpec")
local ProductSpec = class("ProductSpec")
local StrategySpec = class("StrategySpec")
local Directive = class("Directive")
local RelationCall = class("RelationCall")
local RuleSpec = class("RuleSpec")
local PredicateDecl = class("PredicateDecl")
local ConstructorDecl = class("ConstructorDecl")
local GuardSpec = class("GuardSpec")
local RunSpec = class("RunSpec")
local ChooseSpec = class("ChooseSpec")
local AltSpec = class("AltSpec")
local BindSpec = class("BindSpec")
local EmitSpec = class("EmitSpec")
local RetSpec = class("RetSpec")
local FailSpec = class("FailSpec")
local PredicateSpec = class("PredicateSpec")

local function cls(v)
    local mt = type(v) == "table" and getmetatable(v) or nil
    return mt and mt.__lisle_class or nil
end

local function is(v, mt) return type(v) == "table" and getmetatable(v) == mt end

function M.is_llisle_value(v)
    if cls(v) ~= nil then return true end
    return llb.is(v, "Fragment") and tostring(v.role) == "llisle_rule"
end

local function die(msg, origin)
    llb.fail("llisle.dsl: " .. msg, { primary = origin })
end

local function ident_text(v, what)
    what = what or "name"
    if is(v, Binder) then return table.concat(v.path, ".") end
    if llb.is(v, "Name") or llb.is(v, "Symbol") then return tostring(v.text) end
    if type(v) == "table" and rawget(v, "name") ~= nil then return tostring(rawget(v, "name")) end
    if type(v) == "string" or type(v) == "number" then return tostring(v) end
    die(what .. " expected, got " .. llb.repr(v), llb.origin_of(v))
end

local function array_items(t)
    local out = {}
    for i = 1, #(t or {}) do
        local v = t[i]
        if llb.is(v, "Spread") then
            local frag = v.value
            if llb.is(frag, "Fragment") then
                for j = 1, #(frag.items or {}) do out[#out + 1] = frag.items[j] end
            elseif type(frag) == "table" then
                for j = 1, #frag do out[#out + 1] = frag[j] end
            else
                die("spread expects a fragment or array", v.origin)
            end
        elseif llb.is(v, "Fragment") then
            for j = 1, #(v.items or {}) do out[#out + 1] = v.items[j] end
        else
            out[#out + 1] = v
        end
    end
    return out
end

local function has_record_fields(t)
    if type(t) ~= "table" then return false end
    for k in pairs(t) do if type(k) ~= "number" then return true end end
    return false
end

local function process_payload(t)
    if has_record_fields(t) then return t or {} end
    return array_items(t or {})
end

local function fields_from_table(t)
    local out = {}
    for _, v in ipairs(array_items(t or {})) do
        if is(v, Field) then
            out[#out + 1] = v
        elseif llb.is(v, "Capture") then
            out[#out + 1] = setmetatable({ name = ident_text(v.subject, "field name"), type = v.value, origin = v.origin }, Field)
        elseif llb.is(v, "Expr") and v.kind == "index" then
            out[#out + 1] = setmetatable({ name = ident_text(v.base, "field name"), type = v.index, origin = v.origin }, Field)
        elseif type(v) == "table" and rawget(v, "name") ~= nil and rawget(v, "type") ~= nil then
            out[#out + 1] = setmetatable(v, Field)
        else
            die("field product expects entries like name [Type]", llb.origin_of(v))
        end
    end
    return out
end

local binder_predicates = {
    has_type = true, is_const = true, fits_imm32 = true, fits_imm64 = true,
    has_const_pred = true,
    is_int_type = true, is_float_type = true, is_index_type = true, is_bool8_type = true,
    is_index_data_type = true, same_type = true,
    unary_supported = true, binary_supported = true, reduction_supported = true, cast_supported = true,
    is = true, eq = true, ne = true, lt = true, le = true, gt = true, ge = true,
    matches = true, present = true, absent = true,
}

local function binder(space, path, origin)
    return setmetatable({ space = space, path = path, origin = origin or llb.here("llisle-binder", { skip = 2 }) }, Binder)
end

Binder.__index = function(self, key)
    if Binder[key] then return Binder[key] end
    if binder_predicates[key] then
        return function(receiver, ...)
            return setmetatable({ predicate = tostring(key), subject = receiver, args = { ... }, origin = llb.here("llisle-predicate", { skip = 1 }) }, PredicateSpec)
        end
    end
    local path = {}
    for i = 1, #self.path do path[i] = self.path[i] end
    path[#path + 1] = tostring(key)
    return binder(self.space, path, self.origin)
end

Binder.__call = function(self, ...)
    return setmetatable({ predicate = "call", subject = self, args = { ... }, origin = llb.here("llisle-predicate", { skip = 1 }) }, PredicateSpec)
end
Binder.__tostring = function(self) return self.space .. ". " .. table.concat(self.path, ".") end
llb.enable_algebra(Binder)
llb.enable_algebra(PredicateSpec)

local function binder_space(name)
    return setmetatable({ __lisle_binder_space = name }, {
        __index = function(_, key) return binder(name, { tostring(key) }, llb.here("llisle-binder", { hint = key, skip = 1 })) end,
        __call = function(_, key) return binder(name, { tostring(key) }, llb.here("llisle-binder", { hint = key, skip = 1 })) end,
    })
end

M.P = binder_space("P")
M.V = binder_space("V")
M.T = binder_space("T")

local g = llb.grammar
local ch = llb.channel
local function slot_name(slot) return slot[g.name] { channel = ch.index_name } end
local function slot_body(slot, role) return slot[role] { channel = ch.call_table } end
local function slot_index_impl(slot) return slot[g.value] { channel = ch.index_value } end
local function slot_call_value(slot) return slot[g.value] { channels = { ch.call_none, ch.call_value, ch.call_table, ch.call_many } } end

local function role_list(label, allowed)
    return {
        kind = "array",
        algebra = "list",
        normalize = function(_, ctx, v)
            local out = {}
            for _, item in ipairs(array_items(v)) do
                local c = cls(item)
                if allowed and not allowed[c] and not (llb.is(item, "Fragment") and allowed.Fragment) then
                    die(label .. " received invalid item " .. tostring(c or llb.tagof(item) or type(item)), llb.origin_of(item) or (ctx and ctx.origin))
                end
                out[#out + 1] = item
            end
            return out
        end,
    }
end

local function product(kind, fields, origin)
    return setmetatable({ kind = kind, fields = fields or {}, origin = origin }, ProductSpec)
end

local function directive(kind, value, origin)
    return setmetatable({ kind = kind, value = value, origin = origin }, Directive)
end

local function constructor_body_items(v)
    local out = {}
    for _, item in ipairs(array_items(v or {})) do
        local c = cls(item)
        if c ~= "ProductSpec" and c ~= "Directive" then
            die("constructor received invalid item " .. tostring(c or llb.tagof(item) or type(item)), llb.origin_of(item))
        end
        out[#out + 1] = item
    end
    return out
end

function ConstructorDecl:__call(body)
    return setmetatable({
        name = self.name,
        impl = self.impl,
        body = constructor_body_items(body or {}),
        origin = llb.origin_of(body) or self.origin,
    }, ConstructorDecl)
end

local function relation_call(name, fields, origin)
    return setmetatable({ name = tostring(name), fields = fields or {}, origin = origin or llb.here("llisle-relation-call", { hint = name, skip = 2 }) }, RelationCall)
end

local function record_fields(t)
    local out = {}
    for k, v in pairs(t or {}) do
        if type(k) ~= "number" then out[#out + 1] = { name = tostring(k), value = v } end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

local RelationCallFactory = {}
RelationCallFactory.__index = function(_, key)
    return setmetatable({ name = tostring(key), origin = llb.here("llisle-relation-call", { hint = key, skip = 1 }) }, {
        __call = function(self, fields) return relation_call(self.name, fields or {}, self.origin) end,
    })
end
M.relation_call = setmetatable({}, RelationCallFactory)

local L = llb.define "LlisleDsl" {
    g.role .decls (role_list("llisle", { RelationSpec = true, RuleSpec = true, PredicateDecl = true, ConstructorDecl = true, Fragment = true })),
    g.role .relation_body (role_list("relation", { ProductSpec = true, StrategySpec = true, Directive = true })),
    g.role .predicate_body (role_list("predicate", { ProductSpec = true, Directive = true })),
    g.role .constructor_body (role_list("constructor", { ProductSpec = true, Directive = true })),
    g.role .fields { kind = "array", algebra = "product", normalize = function(_, _, v) return fields_from_table(v) end },
    g.role .strategy_body (role_list("strategy", { Directive = true })),
    g.role .rule_body (role_list("rule", { RelationCall = true, GuardSpec = true, BindSpec = true, RunSpec = true, ChooseSpec = true, Directive = true })),
    g.role .guard_body { kind = "array", algebra = "product", normalize = function(_, _, v) return array_items(v or {}) end },
    g.role .payload_body { kind = "array", algebra = "product", normalize = function(_, _, v) return process_payload(v or {}) end },
    g.role .run_body (role_list("run", { BindSpec = true, EmitSpec = true, RetSpec = true, FailSpec = true, ChooseSpec = true, RelationCall = true })),
    g.role .choose_body (role_list("choose", { AltSpec = true })),
    g.role .alt_body (role_list("alt", { GuardSpec = true, BindSpec = true, RunSpec = true, Directive = true })),
    g.role .rules_body (role_list("rules", { RuleSpec = true })),

    g.trait .named { apply = function(_, head) head.lsp = head.lsp or { symbol = function(n) return { name = tostring(n.name), kind = head.name, origin = n.origin, node = n } end } end },

    -- Declares a typed product-to-product relation. Rules satisfy relations.
    g.head .relation { g.trait .named, slot_name(g.slot .name), slot_body(g.slot .body, g.relation_body), emit = function(n) return setmetatable({ kind = "relation", name = ident_text(n.name, "relation name"), body = n.body or {}, origin = n.origin }, RelationSpec) end },
    -- Declares a projection relation. Projection turns family values into MoonSchema-backed facts.
    g.head .project { g.trait .named, slot_name(g.slot .name), slot_body(g.slot .body, g.relation_body), emit = function(n) return setmetatable({ kind = "project", name = ident_text(n.name, "project name"), body = n.body or {}, origin = n.origin }, RelationSpec) end },
    -- Declares a semantic predicate used by guards. The optional [] slot carries the Lua implementation value.
    g.head .predicate { g.trait .named, slot_name(g.slot .name), slot_index_impl(g.slot .impl), slot_body(g.slot .body, g.predicate_body), emit = function(n) return setmetatable({ name = ident_text(n.name, "predicate name"), impl = n.impl, body = n.body or {}, origin = n.origin }, PredicateDecl) end },
    -- Declares a semantic constructor used by ret/emit payload construction. The optional [] slot carries the Lua implementation value.
    g.head .constructor { g.trait .named, slot_name(g.slot .name), slot_index_impl(g.slot .impl), slot_body(g.slot .body, g.constructor_body) { optional = true, default = {} }, emit = function(n) return setmetatable({ name = ident_text(n.name, "constructor name"), impl = n.impl, body = n.body or {}, origin = n.origin }, ConstructorDecl) end },
    -- Declares the input product of a relation.
    g.head .input { slot_body(g.slot .fields, g.fields), emit = function(n) return product("input", n.fields or {}, n.origin) end },
    -- Declares the output product of a relation.
    g.head .output { slot_body(g.slot .fields, g.fields), emit = function(n) return product("output", n.fields or {}, n.origin) end },
    -- Declares process effects yielded by a relation.
    g.head .effects { slot_body(g.slot .fields, g.fields), emit = function(n) return product("effects", n.fields or {}, n.origin) end },
    -- Declares sum-elimination policy for relation or choice alternatives.
    g.head .strategy { slot_body(g.slot .body, g.strategy_body), emit = function(n) return setmetatable({ body = n.body or {}, origin = n.origin }, StrategySpec) end },
    -- Selects the rule/alternative selection policy.
    g.head .select { slot_name(g.slot .value), emit = function(n) return directive("select", ident_text(n.value, "selection policy"), n.origin) end },
    -- Selects ambiguity behavior.
    g.head .ambiguity { slot_name(g.slot .value), emit = function(n) return directive("ambiguity", ident_text(n.value, "ambiguity policy"), n.origin) end },
    -- Selects coverage behavior.
    g.head .coverage { slot_name(g.slot .value), emit = function(n) return directive("coverage", ident_text(n.value, "coverage policy"), n.origin) end },
    -- Marks a predicate as pure.
    g.head .pure { emit = function(n) return directive("pure", true, n.origin) end },
    -- Groups rule alternatives as a reusable fragment.
    g.head .rules { slot_body(g.slot .body, g.rules_body), emit = function(n) return llb.fragment("llisle_rule", n.body or {}, n.origin, { algebra = "list" }) end },
    -- Declares one rule: a relation pattern, guards, and a process body.
    g.head .rule { g.trait .named, slot_name(g.slot .name), slot_body(g.slot .body, g.rule_body), emit = function(n) return setmetatable({ name = ident_text(n.name, "rule name"), body = n.body or {}, origin = n.origin }, RuleSpec) end },
    -- Declares guard predicates for a rule or alternative.
    g.head .when { slot_body(g.slot .body, g.guard_body), emit = function(n) return setmetatable({ body = n.body or {}, origin = n.origin }, GuardSpec) end },
    -- Declares the selected process-shaped body of a rule or alternative.
    g.head .run { slot_body(g.slot .body, g.run_body), emit = function(n) return setmetatable({ body = n.body or {}, origin = n.origin }, RunSpec) end },
    -- Declares a local sum elimination inside a rule body.
    g.head .choose { slot_body(g.slot .body, g.choose_body), emit = function(n) return setmetatable({ body = n.body or {}, origin = n.origin }, ChooseSpec) end },
    -- Declares one alternative inside choose.
    g.head .alt { g.trait .named, slot_name(g.slot .name), slot_body(g.slot .body, g.alt_body), emit = function(n) return setmetatable({ name = ident_text(n.name, "alternative name"), body = n.body or {}, origin = n.origin }, AltSpec) end },
    -- Assigns cost metadata used by best-cost selection.
    g.head .cost { slot_call_value(g.slot .value), emit = function(n) return directive("cost", n.value, n.origin) end },
    -- Binds a produced local value from a relation call or expression.
    g.head .bind { g.trait .named, slot_name(g.slot .name), slot_body(g.slot .body, g.payload_body), emit = function(n) return setmetatable({ name = ident_text(n.name, "binding name"), body = n.body or {}, origin = n.origin }, BindSpec) end },
    -- Emits one process event/effect.
    g.head .emit { slot_name(g.slot .channel), slot_body(g.slot .body, g.payload_body), emit = function(n) return setmetatable({ channel = ident_text(n.channel, "emit channel"), body = n.body or {}, origin = n.origin }, EmitSpec) end },
    -- Returns the output product of a relation.
    g.head .ret { slot_body(g.slot .body, g.payload_body), emit = function(n) return setmetatable({ body = n.body or {}, origin = n.origin }, RetSpec) end },
    -- Fails the current rule or alternative with a diagnostic reason.
    g.head .fail { slot_name(g.slot .reason), slot_body(g.slot .body, g.payload_body), emit = function(n) return setmetatable({ reason = ident_text(n.reason, "failure reason"), body = n.body or {}, origin = n.origin }, FailSpec) end },
}

M.language = L
M._ = llb.spread
M.spread = llb.spread
M.llisle = llb.zone_head { family = "moonlift", member = "llisle.dsl", name = "llisle", role = "rules" }

local function is_llisle_zone(v)
    return llb.is(v, "Zone") and (v.member == "llisle.dsl" or v.name == "llisle")
end

function M.collect(out, value, seen)
    out = out or {}
    if value == nil then return out end
    if type(value) ~= "table" then return out end
    seen = seen or {}
    if seen[value] then return out end
    seen[value] = true
    if M.is_llisle_value(value) then
        out[#out + 1] = value
        if llb.is(value, "Fragment") then
            for _, item in ipairs(value.items or {}) do M.collect(out, item, seen) end
        else
            for _, item in ipairs(rawget(value, "body") or {}) do M.collect(out, item, seen) end
            for _, item in ipairs(rawget(value, "items") or {}) do M.collect(out, item, seen) end
        end
        return out
    end
    if is_llisle_zone(value) then
        for _, item in ipairs(value.items or {}) do M.collect(out, item, seen) end
        return out
    end
    if llb.is(value, "FamilyBundle") then
        for _, z in ipairs(value.zones or {}) do M.collect(out, z, seen) end
        return out
    end
    if not llb.is(value, "Zone") then
        for i = 1, #value do M.collect(out, value[i], seen) end
        for k, v in pairs(value) do if type(k) ~= "number" then M.collect(out, v, seen) end end
    end
    return out
end

local doc = llb.doc
local function block(items, f, fmt)
    if #(items or {}) == 0 then return doc.text("{}") end
    local parts = {}
    for i = 1, #items do
        parts[#parts + 1] = fmt(items[i], f)
        parts[#parts + 1] = ","
        if i < #items then parts[#parts + 1] = doc.line() end
    end
    return doc.concat { "{", doc.indent({ doc.line(), parts }, f.indent_width), doc.line(), "}" }
end

local fmt_spec, fmt_any
local function algebra_symbol(op)
    if op == "sum" then return "+" end
    if op == "product" then return "*" end
    if op == "sequence" then return ".." end
    return tostring(op)
end

local function fmt_llb_value(v, f)
    if llb.is(v, "Name") or llb.is(v, "Symbol") then return doc.text(v.text) end
    if llb.is(v, "Type") then return doc.text(v.name) end
    if llb.is(v, "Capture") then return doc.group { fmt_any(v.subject, f), " [", fmt_any(v.value, f), "]" } end
    if llb.is(v, "CaptureInit") then return doc.group { fmt_any(v.capture, f), " (", fmt_any(v.init, f), ")" } end
    if llb.is(v, "Expr") then
        if v.kind == "binop" then return doc.group { fmt_any(v.a, f), " ", tostring(v.op), " ", fmt_any(v.b, f) } end
        if v.kind == "unop" then return doc.group { tostring(v.op), fmt_any(v.a, f) } end
        if v.kind == "field" then return doc.group { fmt_any(v.base, f), ".", tostring(v.field) } end
        if v.kind == "index" then return doc.group { fmt_any(v.base, f), " [", fmt_any(v.index, f), "]" } end
        if v.kind == "call" then
            local args = {}
            local raw_args, n = v.args or {}, (v.args and (v.args.n or #v.args)) or 0
            for i = 1, n do args[i] = fmt_any(raw_args[i], f) end
            return doc.group { fmt_any(v.callee, f), " ", block(args, f, function(x) return x end) }
        end
    end
    if llb.is_algebra(v) then
        local parts = {}
        local sep = doc.concat { doc.line(), algebra_symbol(v.op), " " }
        for i, item in ipairs(v.items or {}) do parts[i] = fmt_any(item, f) end
        return doc.group { "(", f:join(sep, parts), ")" }
    end
    return nil
end

fmt_any = function(v, f)
    if is(v, Binder) then return doc.text(tostring(v)) end
    if is(v, PredicateSpec) then
        local args = {}
        for i = 1, #(v.args or {}) do args[i] = fmt_any(v.args[i], f) end
        return doc.group { fmt_any(v.subject, f), " :", v.predicate, " (", f:join(doc.concat { ",", doc.line() }, args), ")" }
    end
    if M.is_llisle_value(v) then return fmt_spec(v, f) end
    local llb_doc = fmt_llb_value(v, f)
    if llb_doc then return llb_doc end
    if type(v) == "table" and not llb.is(v, "Expr") and not llb.is(v, "Symbol") and not llb.is(v, "Name") and not llb.is(v, "Capture") then
        local fields = record_fields(v)
        if #fields > 0 then
            local items = {}
            for i = 1, #fields do items[i] = doc.group { fields[i].name, " = ", fmt_any(fields[i].value, f) } end
            return block(items, f, function(x) return x end)
        end
    end
    return f:format(v)
end

local function fmt_fields(fields, f)
    return block(fields or {}, f, function(field)
        return doc.group { field.name, " [", fmt_any(field.type, f), "]" }
    end)
end

local function fmt_body(body, f) return block(body or {}, f, fmt_spec) end
local function fmt_payload(body, f)
    body = body or {}
    if has_record_fields(body) then
        local items = {}
        for _, field in ipairs(record_fields(body)) do
            items[#items + 1] = doc.group { field.name, " = ", fmt_any(field.value, f) }
        end
        return block(items, f, function(x) return x end)
    end
    return block(body, f, fmt_any)
end

fmt_spec = function(v, f)
    if is(v, Field) then return doc.group { v.name, " [", fmt_any(v.type, f), "]" } end
    if is(v, ProductSpec) then return doc.concat { v.kind, " ", fmt_fields(v.fields, f) } end
    if is(v, Directive) then
        if v.kind == "cost" then return doc.group { "cost (", fmt_any(v.value, f), ")" } end
        return doc.group { v.kind, ". ", tostring(v.value) }
    end
    if is(v, StrategySpec) then return doc.concat { "strategy ", fmt_body(v.body, f) } end
    if is(v, RelationSpec) then return doc.concat { (v.kind == "project" and "project. " or "relation. "), v.name, " ", fmt_body(v.body, f) } end
    if is(v, PredicateDecl) then return doc.concat { "predicate. ", v.name, v.impl ~= nil and " [<lua>]" or "", " ", fmt_body(v.body, f) } end
    if is(v, ConstructorDecl) then
        if #(v.body or {}) == 0 then return doc.concat { "constructor. ", v.name, v.impl ~= nil and " [<lua>]" or "" } end
        return doc.concat { "constructor. ", v.name, v.impl ~= nil and " [<lua>]" or "", " ", fmt_body(v.body, f) }
    end
    if is(v, RelationCall) then
        local items = {}
        for _, field in ipairs(record_fields(v.fields or {})) do items[#items + 1] = doc.group { field.name, " = ", fmt_any(field.value, f) } end
        return doc.concat { v.name, " ", block(items, f, function(x) return x end) }
    end
    if is(v, RuleSpec) then return doc.concat { "rule. ", v.name, " ", fmt_body(v.body, f) } end
    if is(v, GuardSpec) then return doc.concat { "when ", block(v.body or {}, f, fmt_any) } end
    if is(v, RunSpec) then return doc.concat { "run ", fmt_body(v.body, f) } end
    if is(v, ChooseSpec) then return doc.concat { "choose ", fmt_body(v.body, f) } end
    if is(v, AltSpec) then return doc.concat { "alt. ", v.name, " ", fmt_body(v.body, f) } end
    if is(v, BindSpec) then return doc.concat { "bind. ", v.name, " ", fmt_payload(v.body, f) } end
    if is(v, EmitSpec) then return doc.concat { "emit. ", v.channel, " ", fmt_payload(v.body, f) } end
    if is(v, RetSpec) then return doc.concat { "ret ", fmt_payload(v.body, f) } end
    if is(v, FailSpec) then return doc.concat { "fail. ", v.reason, " ", fmt_payload(v.body, f) } end
    if llb.is(v, "Fragment") and tostring(v.role) == "llisle_rule" then return doc.concat { "rules ", fmt_body(v.items or {}, f) } end
    return f:format(v)
end

function M.doc(value, opts)
    return fmt_spec(value, setmetatable({ opts = opts or {}, width = opts and opts.width or 100, indent_width = opts and opts.indent or 2, seen = {} }, llb.FormatContext))
end

function M.format(value, opts) return llb.render(M.doc(value, opts or {}), opts or {}) end

local function product_kind(spec, kind)
    for _, item in ipairs(spec.body or {}) do if cls(item) == "ProductSpec" and item.kind == kind then return item end end
    return nil
end

local function relation_call_of(rule)
    local found
    for _, item in ipairs(rule.body or {}) do
        if cls(item) == "RelationCall" then
            if found then return nil, "multiple relation patterns" end
            found = item
        end
    end
    return found
end

local function has_run(items)
    for _, item in ipairs(items or {}) do if cls(item) == "RunSpec" then return true end end
    return false
end

function M.diagnostics(value, bag)
    bag = bag or llb.diagnostics()
    local rels, rules, predicates, constructors = {}, {}, {}, {}
    for _, item in ipairs(M.collect({}, value)) do
        if cls(item) == "RelationSpec" then
            if rels[item.name] then bag:error { code = "E_LLISLE_DUP_RELATION", message = "duplicate Llisle relation " .. item.name, primary = item.origin } end
            rels[item.name] = item
            if not product_kind(item, "input") then bag:error { code = "E_LLISLE_RELATION_INPUT", message = "relation " .. item.name .. " has no input product", primary = item.origin } end
            if not product_kind(item, "output") then bag:error { code = "E_LLISLE_RELATION_OUTPUT", message = "relation " .. item.name .. " has no output product", primary = item.origin } end
        elseif cls(item) == "PredicateDecl" then
            if predicates[item.name] then bag:error { code = "E_LLISLE_DUP_PREDICATE", message = "duplicate Llisle predicate " .. item.name, primary = item.origin } end
            predicates[item.name] = item
            if not product_kind(item, "input") then bag:error { code = "E_LLISLE_PREDICATE_INPUT", message = "predicate " .. item.name .. " has no input product", primary = item.origin } end
        elseif cls(item) == "ConstructorDecl" then
            if constructors[item.name] then bag:error { code = "E_LLISLE_DUP_CONSTRUCTOR", message = "duplicate Llisle constructor " .. item.name, primary = item.origin } end
            constructors[item.name] = item
        elseif cls(item) == "RuleSpec" then
            if rules[item.name] then bag:error { code = "E_LLISLE_DUP_RULE", message = "duplicate Llisle rule " .. item.name, primary = item.origin } end
            rules[item.name] = item
        end
    end
    for _, rule in pairs(rules) do
        local call, err = relation_call_of(rule)
        if not call then bag:error { code = "E_LLISLE_RULE_RELATION", message = "rule " .. rule.name .. " must contain exactly one relation pattern" .. (err and (": " .. err) or ""), primary = rule.origin }
        elseif not rels[call.name] then bag:error { code = "E_LLISLE_UNKNOWN_RELATION", message = "rule " .. rule.name .. " targets unknown relation " .. call.name, primary = call.origin } end
        if not has_run(rule.body) then
            local has_choice = false
            for _, item in ipairs(rule.body or {}) do if cls(item) == "ChooseSpec" then has_choice = true end end
            if not has_choice then bag:error { code = "E_LLISLE_RULE_RUN", message = "rule " .. rule.name .. " has no run body or choose body", primary = rule.origin } end
        end
    end
    return bag
end

function M.index(value)
    local out = { symbols = {}, hovers = {}, diagnostics = {} }
    for _, item in ipairs(M.collect({}, value)) do
        if cls(item) == "RelationSpec" then
            out.symbols[#out.symbols + 1] = { name = item.name, kind = item.kind == "project" and "llisle.project" or "llisle.relation", member = "llisle.dsl", origin = item.origin }
        elseif cls(item) == "PredicateDecl" then
            out.symbols[#out.symbols + 1] = { name = item.name, kind = "llisle.predicate", member = "llisle.dsl", origin = item.origin }
        elseif cls(item) == "ConstructorDecl" then
            out.symbols[#out.symbols + 1] = { name = item.name, kind = "llisle.constructor", member = "llisle.dsl", origin = item.origin }
        elseif cls(item) == "RuleSpec" then
            out.symbols[#out.symbols + 1] = { name = item.name, kind = "llisle.rule", member = "llisle.dsl", origin = item.origin }
        elseif cls(item) == "AltSpec" then
            out.symbols[#out.symbols + 1] = { name = item.name, kind = "llisle.alt", member = "llisle.dsl", origin = item.origin }
        end
    end
    return out
end

local NAMESPACE_KEYS = {
    "P", "V", "T", "relation", "input", "output", "effects", "strategy", "select", "ambiguity", "coverage",
    "project", "predicate", "constructor", "pure",
    "rules", "rule", "when", "run", "choose", "alt", "cost", "bind", "emit", "ret", "fail", "_", "spread",
}

function M.make_env(opts)
    opts = opts or {}
    local env = {}
    for k, v in pairs(opts.base or opts.target or _G) do env[k] = v end
    env.llisle = M.namespace(opts)
    env.P, env.V, env.T = M.P, M.V, M.T
    for _, name in ipairs(NAMESPACE_KEYS) do env[name] = M.namespace(opts)[name] end
    return env
end

function M.namespace(opts)
    local exports = { P = M.P, V = M.V, T = M.T, _ = llb.spread, spread = llb.spread }
    for name, value in pairs(L.exports or {}) do exports[name] = value end
    exports.pure = directive("pure", true, llb.here("llisle-pure"))
    if M.compile ~= nil then exports.compile = M.compile end
    if M.engine ~= nil then exports.engine = M.engine end
    return llb.namespace {
        family = "moonlift",
        member = "llisle.dsl",
        name = "llisle",
        exports = exports,
        zone = M.llisle,
        default_head = M.relation_call,
    }
end

function M.make_family_env(opts) return { llisle = M.namespace(opts) } end

function M.use(opts)
    opts = opts or {}
    local exports = M.make_env(opts)
    return llb.use(L, {
        scope = opts.scope or (opts.global == false and "env" or "permanent"),
        target = opts.target or _G,
        base = exports,
        exports = exports,
        lang_exports = false,
        helpers = false,
        strict = opts.strict,
        strict_message = "unknown Llisle DSL global ",
        override = opts.override ~= false,
        auto_names = opts.auto_names ~= false,
        mode = opts.mode,
        requires = opts.requires or { "llb.core" },
        provides = opts.provides or { "llisle.dsl" },
    })
end

function M.loadstring(src, name, opts)
    opts = opts or {}
    local target = opts.env or {}
    local session = M.use {
        scope = "env",
        target = target,
        global = false,
        strict = opts.strict,
        auto_names = opts.auto_names,
        base = opts.base,
        mode = opts.mode,
        requires = opts.requires,
        provides = opts.provides,
    }
    local fn, err = (loadstring or load)(src, name or "=(llisle.dsl)")
    if not fn then error(err, 2) end
    if setfenv then setfenv(fn, session.env) end
    return fn
end

function M.load(src, name, opts) return M.loadstring(src, name, opts)() end
function M.loadfile(path, opts) local f = assert(io.open(path, "rb")); local src = f:read("*a") or ""; f:close(); return M.loadstring(src, "@" .. path, opts) end

M.Binder, M.Field, M.RelationSpec, M.RuleSpec, M.RelationCall = Binder, Field, RelationSpec, RuleSpec, RelationCall
M.ProductSpec, M.StrategySpec, M.ChooseSpec, M.AltSpec = ProductSpec, StrategySpec, ChooseSpec, AltSpec
M.BindSpec, M.EmitSpec, M.RetSpec, M.FailSpec = BindSpec, EmitSpec, RetSpec, FailSpec
M.PredicateDecl, M.ConstructorDecl = PredicateDecl, ConstructorDecl
M.cls = cls

return M
