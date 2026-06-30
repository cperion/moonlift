-- schema_context.lua — GC-backed ASDL context builder
--
-- Builds live ASDL classes from parser output:
--   - callable classes
--   - structural interning for `unique`
--   - sum membership and reflection through private side metadata
--   - structural update and raw getters through generated side-table plans
--
-- Memory model:
--   ASDL values are ordinary GC-managed Lua objects. Old worlds die by
--   reachability. There is no user-visible lifecycle step.
--
-- Performance model:
--   The backend stays simple (plain GC-managed objects) but still uses codegen
--   for the hot constructor / updater / raw-getter paths. Arity-specialized
--   kernels up to MAX_SPECIAL_ARITY keep the common cases monomorphic without
--   reintroducing slot/gen lifetime machinery.

local M = {}
local Quote = require("lalin.quote")

local type = type
local error = error
local pairs = pairs
local ipairs = ipairs
local select = select
local tostring = tostring
local rawset = rawset
local rawget = rawget
local setmetatable = setmetatable
local getmetatable = getmetatable
local tconcat = table.concat
local sfmt = string.format
local unpack = table.unpack or unpack

local NIL = {}
local LEAF = {}
local WEAK_VALUE_MT = { __mode = "v" }
local CLASS_META = setmetatable({}, { __mode = "k" })
local MAX_SPECIAL_ARITY = 16
local normalize_field
local classof_fast

local function class_meta(class)
    return type(class) == "table" and CLASS_META[class] or nil
end

local function is_class(class)
    return class_meta(class) ~= nil
end

local function class_from(value)
    if type(value) ~= "table" then return false end
    if is_class(value) then return value end
    return classof_fast(value)
end

-- ── Builtin type checks ─────────────────────────────────────

local builtin_checks = {}
for _, name in ipairs({ "nil", "number", "string", "boolean", "function" }) do
    builtin_checks[name] = function(v) return type(v) == name end
end

-- ── Context ──────────────────────────────────────────────────

local Context = {}
function Context:__index(key)
    return self.definitions[key] or self.namespaces[key] or Context[key]
end

local function basename(name)
    return name:match("([^.]*)$")
end

function Context:_SetDefinition(name, value)
    local ns = self.namespaces
    for part in name:gmatch("([^.]*)%.") do
        ns[part] = ns[part] or {}
        ns = ns[part]
    end
    ns[basename(name)] = value
    self.definitions[name] = value
    self._builders = nil
    self._fast_builders = nil
end

function Context:Extern(name, check_fn)
    self.checks[name] = check_fn
end

local function make_named_builder(class, trusted)
    local meta = class_meta(class)
    local fields = meta and meta.fields
    local plan = meta and meta.plan
    local name = meta and meta.name or tostring(class)
    local allowed = {}
    for i = 1, #fields do
        allowed[fields[i].name] = true
    end

    local q = Quote()
    local _ctor = q:val(class, "ctor")

    q("return function(spec)")
    if not trusted then
        local _type = q:val(type, "type")
        local _getmetatable = q:val(getmetatable, "getmetatable")
        local _classof_fast = q:val(classof_fast, "classof_fast")
        local _pairs = q:val(pairs, "pairs")
        local _tostring = q:val(tostring, "tostring")
        local _allowed = q:val(allowed, "allowed")

        q("  if %s(spec) ~= 'table' or %s(spec) ~= nil or %s(spec) then", _type, _getmetatable, _classof_fast)
        q("    error(%q, 2)", "builder for '" .. name .. "' expects one plain Lua table")
        q("  end")
        q("  for k in %s(spec) do", _pairs)
        q("    if %s[k] == nil then", _allowed)
        q("      error(\"unknown field '\" .. %s(k) .. \"' for '%s'\", 2)", _tostring, name)
        q("    end")
        q("  end")
    end

    local args = {}
    for i = 1, #fields do
        local f = fields[i]
        q("  local v%d = spec[%q]", i, f.name)
        if not trusted and not f.optional then
            q("  if v%d == nil then error(%q, 2) end", i, "missing required field '" .. f.name .. "' for '" .. name .. "'")
        end
        args[i] = "v" .. i
    end

    q("  return %s(%s)", _ctor, tconcat(args, ", "))
    q("end")
    return q:compile("=(asdl.builder." .. tostring(name) .. "." .. tostring(trusted) .. ")")
end

local function build_builder_tree(src, trusted)
    local out = {}
    for k, v in pairs(src) do
        if is_class(v) then
            local meta = class_meta(v)
            if meta.fields then
                local slot = trusted and "__fast_builder" or "__builder"
                out[k] = meta[slot] or make_named_builder(v, trusted)
                meta[slot] = out[k]
            else
                out[k] = v
            end
        elseif type(v) == "table" and not classof_fast(v) and getmetatable(v) == nil then
            out[k] = build_builder_tree(v, trusted)
        else
            out[k] = v
        end
    end
    return out
end

function Context:Builders(opts)
    opts = opts or false
    local trusted = opts == true or (type(opts) == "table" and opts.trusted) or false
    local cache_key = trusted and "_fast_builders" or "_builders"
    local cached = rawget(self, cache_key)
    if cached ~= nil then return cached end
    local built = build_builder_tree(self.namespaces, trusted)
    rawset(self, cache_key, built)
    return built
end

function Context:FastBuilders()
    return self:Builders(true)
end

function Context:Singleton(class)
    if type(class) ~= "table" then
        error("ASDL singleton: expected class or singleton", 2)
    end
    local node_class = classof_fast(class)
    if node_class ~= false then
        class = node_class
    elseif not is_class(class) then
        error("ASDL singleton: expected class or singleton", 2)
    end
    local singleton = class_meta(class).singleton
    if singleton == nil then
        error("ASDL singleton: class is not a nullary singleton variant", 2)
    end
    return singleton
end

function Context:singleton(class)
    return self:Singleton(class)
end

classof_fast = function(v)
    if type(v) ~= "table" then
        return false
    end
    local mt = getmetatable(v)
    return (mt and mt.__class) or false
end

function M.ClassOf(v)
    return classof_fast(v)
end

function M.Class(value)
    return class_from(value)
end

function M.ClassName(value)
    local cls = class_from(value)
    local meta = cls and class_meta(cls)
    return meta and meta.name or nil
end

function M.ClassBasename(value)
    local cls = class_from(value)
    local meta = cls and class_meta(cls)
    return meta and meta.basename or nil
end

function M.ContextOf(value)
    local cls = class_from(value)
    local meta = cls and class_meta(cls)
    return meta and meta.context or nil
end

function M.Fields(value)
    local cls = class_from(value)
    local meta = cls and class_meta(cls)
    return meta and meta.fields or nil
end

function M.Members(value)
    local cls = class_from(value)
    local meta = cls and class_meta(cls)
    return meta and meta.members or nil
end

function M.IsSumParent(value)
    local cls = class_from(value)
    local meta = cls and class_meta(cls)
    return meta and meta.is_sum_parent or false
end

function M.With(node, overrides, nil_sentinel)
    local cls = classof_fast(node)
    local meta = cls and class_meta(cls)
    if not meta or not meta.fields then
        error("asdl.with: not an ASDL node", 3)
    end
    return meta.with(node, overrides, nil_sentinel)
end

function M.Raw(class)
    local meta = class_meta(class)
    return meta and meta.raw or nil
end

function M.RawField(class, name)
    local meta = class_meta(class)
    return meta and meta.raw_fields and meta.raw_fields[name] or nil
end

-- ── Interning helpers ───────────────────────────────────────

local function alloc_leaf_box(value)
    local box = setmetatable({}, WEAK_VALUE_MT)
    box[1] = value
    return box
end

local function intern_value(cache, keys, build)
    if cache == nil then
        return build()
    end

    local node = cache
    for i = 1, #keys do
        local next = node[keys[i]]
        if next == nil then
            next = {}
            node[keys[i]] = next
        end
        node = next
    end

    local leaf = node[LEAF]
    if leaf ~= nil then
        local hit = leaf[1]
        if hit ~= nil then
            return hit
        end
        node[LEAF] = nil
    end

    local value = build()
    node[LEAF] = alloc_leaf_box(value)
    return value
end

-- ── Normalization / checking ────────────────────────────────

local function make_list_check(check, type_name, unique_parent)
    if unique_parent then
        local intern_trie = {}
        local seen = setmetatable({}, { __mode = "kv" })
        return function(vs)
            if type(vs) ~= "table" then
                return false
            end

            local fast = seen[vs]
            if fast ~= nil then
                return true, fast
            end

            local len = #vs
            local elems = nil
            for i = 1, len do
                local elem = vs[i]
                local ok, aux = check(elem)
                if not ok then
                    return false, i
                end
                local value = (aux ~= nil) and aux or elem
                if elems ~= nil then
                    elems[i] = value
                elseif value ~= elem then
                    elems = {}
                    for j = 1, i - 1 do elems[j] = vs[j] end
                    elems[i] = value
                end
            end

            local src = elems or vs
            local keys = { len }
            for i = 1, len do
                keys[i + 1] = (src[i] == nil) and NIL or src[i]
            end

            local canonical = intern_value(intern_trie, keys, function()
                local out = {}
                for i = 1, len do out[i] = src[i] end
                return out
            end)
            seen[vs] = canonical
            return true, canonical
        end, type_name .. "*"
    end

    return function(vs)
        if type(vs) ~= "table" then
            return false
        end
        local len = #vs
        local elems = nil
        for i = 1, len do
            local elem = vs[i]
            local ok, aux = check(elem)
            if not ok then
                return false, i
            end
            local value = (aux ~= nil) and aux or elem
            if elems ~= nil then
                elems[i] = value
            elseif value ~= elem then
                elems = {}
                for j = 1, i - 1 do elems[j] = vs[j] end
                elems[i] = value
            end
        end
        return true, elems
    end, type_name .. "*"
end

local function make_check(ctx, field, unique_parent)
    local type_name = field.type
    local check = ctx.checks[type_name]
    if not check then
        error("ASDL: unknown type '" .. type_name .. "' in field '" .. (field.name or "?") .. "'")
    end

    if field.list then
        return make_list_check(check, type_name, unique_parent)
    elseif field.optional then
        return function(v)
            if v == nil then
                return true
            end
            return check(v)
        end, type_name .. "?"
    else
        return check, type_name
    end
end

normalize_field = function(fp, arg, argi, ctor_name)
    local ok, aux = fp.normalize(arg)
    if not ok then
        error(sfmt(
            "bad arg #%d to '%s': expected '%s' got '%s'%s",
            argi, ctor_name, fp.type_name, type(arg),
            aux and (" at index " .. aux) or ""), 2)
    end
    local value = (aux ~= nil) and aux or arg
    local key = (value == nil) and NIL or value
    return value, key
end

-- ── Constructors / with / raw ───────────────────────────────

local function make_instance_mt(class, instance_tostring, field_lookup)
    return {
        __class = class,
        __index = function(self, k)
            local v = rawget(self, k)
            if v ~= nil then
                return v
            end
            if field_lookup[k] then
                return nil
            end
            local method = class[k]
            if type(method) == "function" then
                return method
            end
            return nil
        end,
        __newindex = function()
            error("ASDL nodes are immutable; use asdl.with(...)", 2)
        end,
        __tostring = instance_tostring,
    }
end

-- Generate arity-specialized constructors for GC-backed objects.
--
-- This keeps the old good part of the backend — straight-line constructor
-- code with unrolled normalization and intern-trie walks — while the objects
-- themselves remain ordinary GC-managed Lua tables.
local function gen_ctor_factory(n, trusted)
    local q = Quote()
    local _normalize_field = q:val(normalize_field, "normalize_field")
    local _setmetatable = q:val(setmetatable, "setmetatable")
    local _alloc_leaf_box = q:val(alloc_leaf_box, "alloc_leaf_box")
    local _NIL = q:val(NIL, "NIL")
    local _LEAF = q:val(LEAF, "LEAF")
    local args = {}
    for i = 1, n do args[i] = "a" .. i end
    local arglist = tconcat(args, ", ")

    q("return function(plan)")
    q("  local cache = plan.cache")
    q("  local ctor_name = plan.name")
    q("  local mt = plan.instance_mt")
    q("  local alloc_instance = plan.alloc_instance")
    if not trusted then
        q("  local fields = plan.fields")
    end
    for i = 1, n do
        q("  local k%d = plan.names[%d]", i, i)
    end
    q("  return function(self, %s)", arglist)
    for i = 1, n do
        if trusted then
            q("    local v%d = a%d", i, i)
            q("    local key%d = (v%d == nil) and %s or v%d", i, i, _NIL, i)
        else
            q("    local v%d, key%d = %s(fields[%d], a%d, %d, ctor_name)", i, i, _normalize_field, i, i, i)
        end
    end
    q("    local node = cache")
    q("    if node ~= nil then")
    for i = 1, n do
        q("      local next%d = node[key%d]", i, i)
        q("      if next%d == nil then", i)
        q("        next%d = {}", i)
        q("        node[key%d] = next%d", i, i)
        q("      end")
        q("      node = next%d", i)
    end
    q("      local leaf = node[%s]", _LEAF)
    q("      if leaf ~= nil then")
    q("        local hit = leaf[1]")
    q("        if hit ~= nil then return hit end")
    q("        node[%s] = nil", _LEAF)
    q("      end")
    q("    end")
    q("    local obj = alloc_instance({")
    for i = 1, n do
        q("      [%s] = v%d,", "k" .. i, i)
    end
    q("    }, mt)")
    q("    if node ~= nil then node[%s] = %s(obj) end", _LEAF, _alloc_leaf_box)
    q("    return obj")
    q("  end")
    q("end")
    return q:compile("=(asdl.gc_ctor." .. tostring(n) .. "." .. tostring(trusted) .. ")")
end

local CTOR_KERNELS = {}
local TRUSTED_CTOR_KERNELS = {}
for n = 1, MAX_SPECIAL_ARITY do
    CTOR_KERNELS[n] = gen_ctor_factory(n, false)
    TRUSTED_CTOR_KERNELS[n] = gen_ctor_factory(n, true)
end

local function make_ctor(plan)
    local n = plan.arity
    if n >= 1 and n <= MAX_SPECIAL_ARITY then
        return CTOR_KERNELS[n](plan)
    end
    return function(self, ...)
        local values = {}
        local keys = {}
        for i = 1, n do
            local value, key = normalize_field(plan.fields[i], select(i, ...), i, plan.name)
            values[plan.names[i]] = value
            keys[i] = key
        end
        return intern_value(plan.cache, keys, function()
            return plan.alloc_instance(values, plan.instance_mt)
        end)
    end
end

local function make_with_updater(class, plan, fields)
    local n = #fields
    if n >= 1 and n <= MAX_SPECIAL_ARITY then
        local q = Quote()
        local _class = q:val(class, "class")
        q("return function(self, overrides, NIL_SENTINEL)")
        for i = 1, n do
            local name = fields[i].name
            q("  local v%d = overrides[%q]", i, name)
            q("  if v%d == NIL_SENTINEL then", i)
            q("    v%d = nil", i)
            q("  elseif v%d == nil then", i)
            q("    v%d = rawget(self, %q)", i, name)
            q("  end")
        end
        local args = {}
        for i = 1, n do args[i] = "v" .. i end
        q("  return %s(%s)", _class, tconcat(args, ", "))
        q("end")
        return q:compile("=(asdl.with_gc." .. plan.name .. ")")
    end
    return function(self, overrides, NIL_SENTINEL)
        local args = {}
        for i = 1, n do
            local name = fields[i].name
            local v = overrides[name]
            if v == NIL_SENTINEL then
                v = nil
            elseif v == nil then
                v = rawget(self, name)
            end
            args[i] = v
        end
        return class(unpack(args, 1, n))
    end
end

local function make_raw_getter(fields)
    local n = #fields
    if n >= 1 and n <= MAX_SPECIAL_ARITY then
        local q = Quote()
        q("return function(self)")
        local outs = {}
        for i = 1, n do
            local name = fields[i].name
            q("  local v%d = rawget(self, %q)", i, name)
            outs[i] = "v" .. i
        end
        q("  return %s", tconcat(outs, ", "))
        q("end")
        return q:compile("=(asdl.raw_gc." .. tostring(n) .. ")")
    end
    return function(self)
        local out = {}
        for i = 1, n do
            out[i] = rawget(self, fields[i].name)
        end
        return unpack(out, 1, n)
    end
end

local function build_ctor_plan(ctx, name, class, unique, fields, instance_tostring)
    local meta = class_meta(class)
    for _, f in ipairs(fields) do
        if f.namespace then
            local fq = f.namespace .. f.type
            if ctx.definitions[fq] then
                f.type = fq
            end
            f.namespace = nil
        end
    end

    local names = {}
    local field_plans = {}
    local field_lookup = {}
    for i, f in ipairs(fields) do
        local normalize, type_name = make_check(ctx, f, unique)
        names[i] = f.name
        field_lookup[f.name] = true
        field_plans[i] = {
            name = f.name,
            type_name = type_name,
            normalize = normalize,
        }
    end

    local instance_mt = make_instance_mt(class, instance_tostring, field_lookup)
    local alloc_instance
    if meta ~= nil and meta.ref_class_id ~= nil then
        alloc_instance = function(values, mt)
            local slot = meta.next_ref_slot or 1
            meta.next_ref_slot = slot + 1
            values.__slot = slot
            return setmetatable(values, mt)
        end
    else
        alloc_instance = function(values, mt)
            return setmetatable(values, mt)
        end
    end

    return {
        name = name,
        class = class,
        arity = #fields,
        unique = unique,
        names = names,
        fields = field_plans,
        cache = unique and {} or nil,
        backend = "gc_object",
        field_lookup = field_lookup,
        instance_mt = instance_mt,
        alloc_instance = alloc_instance,
    }
end

-- ── Class building ───────────────────────────────────────────

local function build_class(ctx, name, unique, fields, is_sum_parent)
    local class = ctx.definitions[name]
    local meta = CLASS_META[class]
    if meta == nil then
        meta = {
            name = name,
            basename = basename(name),
            context = ctx,
            members = {},
            fields = fields,
            is_sum_parent = is_sum_parent or false,
        }
        CLASS_META[class] = meta
    end
    meta.name = name
    meta.basename = basename(name)
    meta.context = ctx
    meta.fields = fields
    meta.is_sum_parent = is_sum_parent or false
    meta.members = meta.members or {}
    meta.members[class] = true

    if unique and meta.ref_class_id == nil then
        meta.ref_class_id = ctx._next_ref_class_id
        meta.next_ref_slot = 1
        ctx._next_ref_class_id = ctx._next_ref_class_id + 1
    end

    local mt = {}

    if fields then
        local function instance_tostring(self)
            local parts = {}
            for i, f in ipairs(fields) do
                local v = self[f.name]
                if v ~= nil or not f.optional then
                    if f.list then
                        local elems = {}
                        for j = 1, #v do elems[j] = tostring(v[j]) end
                        parts[#parts + 1] = f.name .. " = {" .. tconcat(elems, ",") .. "}"
                    else
                        parts[#parts + 1] = f.name .. " = " .. tostring(v)
                    end
                end
            end
            return name .. "(" .. tconcat(parts, ", ") .. ")"
        end

        local plan = build_ctor_plan(ctx, name, class, unique, fields, instance_tostring)
        mt.__call = make_ctor(plan)
        meta.storage = plan.backend
        meta.ctype = nil
        meta.plan = plan
        meta.instance_mt = plan.instance_mt
        meta.with = make_with_updater(class, plan, fields)
        meta.raw = make_raw_getter(fields)
        meta.tostring = instance_tostring
        meta.raw_fields = {}
        for i = 1, #fields do
            if fields[i].list then
                meta.raw_fields[fields[i].name] = function(self)
                    local v = rawget(self, fields[i].name)
                    if v == nil then
                        return nil, nil, 0, false
                    end
                    return v, 1, #v, true
                end
            end
        end
    else
        local function instance_tostring()
            return name
        end

        local instance_mt = {
            __class = class,
            __index = function(self, k)
                local method = class[k]
                if type(method) == "function" then
                    return method
                end
                return nil
            end,
            __newindex = function(_, k, v)
                if type(k) == "string" and type(v) == "function" then
                    rawset(class, k, v)
                    return
                end
                error("ASDL nodes are immutable; use asdl.with(...)", 2)
            end,
            __tostring = instance_tostring,
        }

        local singleton = {}
        if meta.ref_class_id ~= nil then
            singleton.__slot = 1
            meta.next_ref_slot = 2
        end
        singleton = setmetatable(singleton, instance_mt)

        function mt:__call()
            return singleton
        end

        meta.storage = "gc_singleton"
        meta.ctype = nil
        meta.plan = {
            name = name,
            class = class,
            arity = 0,
            unique = true,
            names = {},
            fields = {},
            cache = nil,
            backend = "gc_singleton",
            instance_mt = instance_mt,
        }
        meta.instance_mt = instance_mt
        meta.singleton = singleton
        meta.tostring = instance_tostring
    end

    function mt:__newindex(k, v)
        rawset(self, k, v)
    end

    function mt:__index(k)
        local parent = class_meta(self).parent
        if parent ~= nil then
            return parent[k]
        end
        return nil
    end

    function mt:__tostring()
        return sfmt("Class(%s)", name)
    end

    function class:isclassof(obj)
        local self_meta = class_meta(self)
        return self_meta and self_meta.members[classof_fast(obj)] or false
    end

    setmetatable(class, mt)
    return class
end

-- ── Define: process parsed definitions ───────────────────────

function M.define(ctx, definitions)
    for _, d in ipairs(definitions) do
        ctx.definitions[d.name] = ctx.definitions[d.name] or {}
        do
            local definition = ctx.definitions[d.name]
            ctx.checks[d.name] = function(v)
                local meta = class_meta(definition)
                local members = meta and meta.members
                return members and members[classof_fast(v)] or false
            end
        end
        ctx:_SetDefinition(d.name, ctx.definitions[d.name])

        if d.type.kind == "sum" then
            for _, c in ipairs(d.type.constructors) do
                ctx.definitions[c.name] = ctx.definitions[c.name] or {}
                do
                    local definition = ctx.definitions[c.name]
                    ctx.checks[c.name] = function(v)
                        local meta = class_meta(definition)
                        local members = meta and meta.members
                        return members and members[classof_fast(v)] or false
                    end
                end
                ctx:_SetDefinition(c.name, ctx.definitions[c.name])
            end
        end
    end

    for _, d in ipairs(definitions) do
        if d.type.kind == "sum" then
            local parent = build_class(ctx, d.name, false, nil, true)
            for _, c in ipairs(d.type.constructors) do
                local child = build_class(ctx, c.name, c.unique, c.fields, false)
                local parent_meta = class_meta(parent)
                local child_meta = class_meta(child)
                parent_meta.members[child] = true
                child_meta.parent = parent
                if not c.fields then
                    ctx:_SetDefinition(c.name, child())
                end
            end
        else
            build_class(ctx, d.name, d.type.unique, d.type.fields, false)
        end
    end
end

-- ── NewContext ───────────────────────────────────────────────

function M.NewContext(opts)
    opts = opts or {}
    local ctx = setmetatable({
        definitions = {},
        namespaces = {},
        checks = setmetatable({}, { __index = builtin_checks }),
        _next_ref_class_id = 1,
        opts = opts,
    }, Context)

    function ctx:bind_context()
        error("ASDL text definitions have been removed; use LalinSchema values and context_define_schema.define", 2)
    end

    return ctx
end

return M
