-- facts.lua -- typed fact lattice for the SponJIT foundry.
--
-- Strings are accepted at the boundary for corpus/enumerator compatibility, but
-- inside the optimizer facts are records with subject/predicate/value/source/deps.

local Util = require("src.util")

local M = {}

local function copy_array(xs)
    local out = {}
    for i, x in ipairs(xs or {}) do out[i] = x end
    return out
end

local function sorted_keys(t)
    local out = {}
    for k in pairs(t or {}) do out[#out + 1] = k end
    table.sort(out)
    return out
end

local function value_key(v)
    if v == nil then return "" end
    if type(v) ~= "table" then return tostring(v) end
    local parts = {}
    for _, k in ipairs(sorted_keys(v)) do parts[#parts + 1] = tostring(k) .. "=" .. value_key(v[k]) end
    return "{" .. table.concat(parts, ",") .. "}"
end

function M.subject(kind, id, attrs)
    return { kind = kind, id = tostring(id or "?"), attrs = attrs or {} }
end

function M.value(id) return M.subject("value", id) end
function M.slot(id) return M.subject("slot", id) end
function M.table_ref(id) return M.subject("table", id) end
function M.callsite(id) return M.subject("callsite", id) end
function M.pc(id) return M.subject("pc", id) end
function M.memory(id) return M.subject("memory", id) end
function M.global_subject() return M.subject("global", "*") end

function M.subject_key(s)
    if type(s) == "string" then return s end
    if type(s) ~= "table" then return tostring(s) end
    return tostring(s.kind or "?") .. ":" .. tostring(s.id or "?")
end

local DEP_BY_PREDICATE = {
    shape_eq = { "shape_epoch" },
    shape_known = { "shape_epoch" },
    field_offset = { "shape_epoch" },
    metatable_absent = { "metatable_epoch" },
    no_metamethod = { "metatable_epoch" },
    target_eq = { "call_target_epoch" },
    known_call_target = { "call_target_epoch" },
    barrier_clean = { "gc_barrier_protocol" },
    array_hit = { "array_epoch" },
    bounds_ok = { "array_epoch" },
}

local TYPE_PREDICATES = {
    is_nil = true, is_bool = true, is_i64 = true, is_f64 = true,
    is_number = true, is_table = true, is_closure = true, is_string = true,
}

local IMPLIED_BY_PREDICATE = {
    shape_known = { { predicate = "is_table" } },
    shape_eq = { { predicate = "is_table" }, { predicate = "shape_known" } },
    field_offset = { { predicate = "is_table" }, { predicate = "key_const" } },
    metatable_absent = { { predicate = "no_metamethod", value = "__index" }, { predicate = "no_metamethod", value = "__newindex" } },
    array_hit = { { predicate = "is_table" } },
    bounds_ok = { { predicate = "array_hit" } },
    target_eq = { { predicate = "known_call_target" }, { predicate = "is_closure" } },
    key_i64 = { { predicate = "key_const" } },
}

local LEGACY = {
    lhs_i64 = function() return M.fact("type", M.value("lhs"), "is_i64", nil, "observed") end,
    rhs_i64 = function() return M.fact("type", M.value("rhs"), "is_i64", nil, "observed") end,
    last_i64 = function() return M.fact("type", M.value("last"), "is_i64", nil, "observed") end,
    key_i64 = function() return M.fact("type", M.value("key"), "key_i64", nil, "observed") end,
    table = function() return M.fact("type", M.value("table"), "is_table", nil, "observed") end,
    shape_known = function() return M.fact("shape", M.value("table"), "shape_known", true, "observed") end,
    metatable_absent = function() return M.fact("metatable", M.value("table"), "metatable_absent", true, "observed") end,
    key_const = function() return M.fact("constant", M.value("key"), "key_const", true, "observed") end,
    array_hit = function() return M.fact("array", M.value("table"), "array_hit", true, "observed") end,
    bounds = function() return M.fact("array", M.value("table"), "bounds_ok", true, "observed") end,
    array_bounds_known = function() return M.fact("array", M.value("table"), "bounds_ok", true, "observed") end,
    known_call_target = function() return M.fact("call", M.value("callee"), "known_call_target", true, "observed") end,
    result_known_call = function() return M.fact("call", M.value("last"), "known_call_target", true, "observed") end,
    callee_from_prev = function() return M.fact("call", M.value("callee"), "from_prev", true, "observed") end,
    barrier_clean = function() return M.fact("gc", M.global_subject(), "barrier_clean", true, "observed") end,
    returns_prev = function() return M.fact("liveness", M.value("last"), "returned", true, "observed") end,
    branch_consumes_prev = function() return M.fact("control", M.value("last"), "branch_consumed", true, "observed") end,
    loop_backedge = function() return M.fact("control", M.pc("backedge"), "loop_backedge", true, "observed") end,
    loop_i64 = function() return M.fact("type", M.value("loop_index"), "is_i64", nil, "observed") end,
    lhs_from_prev = function() return M.fact("flow", M.value("lhs"), "from_prev", true, "observed") end,
    result_dead = function() return M.fact("liveness", M.value("last"), "dead", true, "observed") end,
    slot_reuse = function() return M.fact("liveness", M.slot("cur"), "slot_reuse", true, "observed") end,
    value_in_rax = function() return M.fact("residency", M.value("last"), "in_reg", "rax", "observed") end,
    value_in_rcx = function() return M.fact("residency", M.value("last"), "in_reg", "rcx", "observed") end,
}

function M.fact(kind, subject, predicate, value, source, confidence, deps)
    local f = {
        kind = kind or "generic",
        subject = subject or M.global_subject(),
        predicate = predicate or "true",
        value = value,
        source = source or "assumed",
        confidence = confidence or "assumed",
        deps = copy_array(deps),
    }
    if #f.deps == 0 and DEP_BY_PREDICATE[f.predicate] then f.deps = copy_array(DEP_BY_PREDICATE[f.predicate]) end
    return f
end

function M.key(f)
    return table.concat({
        tostring(f.kind or "generic"),
        M.subject_key(f.subject),
        tostring(f.predicate or "true"),
        value_key(f.value),
    }, ":")
end

function M.guard_key(f)
    return M.subject_key(f.subject) .. ":" .. tostring(f.predicate) .. ":" .. value_key(f.value)
end

function M.parse(x)
    if type(x) == "table" and x.predicate then return x end
    if type(x) == "string" and LEGACY[x] then return LEGACY[x]() end
    if type(x) == "string" then return M.fact("legacy", M.global_subject(), x, true, "observed") end
    return M.fact("unknown", M.global_subject(), tostring(x), true, "observed")
end

local FactSet = {}
FactSet.__index = FactSet
M.FactSet = FactSet

function M.new(xs)
    local fs = setmetatable({ by_key = {}, order = {}, contradiction_list = {} }, FactSet)
    for _, x in ipairs(xs or {}) do fs:add(x) end
    fs:close()
    return fs
end

function FactSet:add(x)
    local f = M.parse(x)
    local k = M.key(f)
    if not self.by_key[k] then
        self.by_key[k] = f
        self.order[#self.order + 1] = k
    end
    return self.by_key[k]
end

function FactSet:each()
    local i = 0
    return function()
        i = i + 1
        local k = self.order[i]
        if k then return self.by_key[k] end
    end
end

function FactSet:has(predicate, subject, value)
    local sk = subject and M.subject_key(subject)
    for f in self:each() do
        if f.predicate == predicate and (not sk or M.subject_key(f.subject) == sk) and (value == nil or value_key(f.value) == value_key(value)) then
            return true, f
        end
    end
    return false
end

function FactSet:implies(x_or_predicate, subject, value)
    if type(x_or_predicate) == "table" and x_or_predicate.predicate then
        return self:has(x_or_predicate.predicate, x_or_predicate.subject, x_or_predicate.value)
    end
    return self:has(x_or_predicate, subject, value)
end

function FactSet:close()
    local changed = true
    while changed do
        changed = false
        local snapshot = {}
        for f in self:each() do snapshot[#snapshot + 1] = f end
        for _, f in ipairs(snapshot) do
            for _, imp in ipairs(IMPLIED_BY_PREDICATE[f.predicate] or {}) do
                local nf = M.fact(imp.kind or f.kind, f.subject, imp.predicate, imp.value, "implied", "proven", f.deps)
                local k = M.key(nf)
                if not self.by_key[k] then self:add(nf); changed = true end
            end
        end
    end
    self:check_contradictions()
    return self
end

function FactSet:check_contradictions()
    self.contradiction_list = {}
    local by_subject_type = {}
    local by_subject_shape = {}
    for f in self:each() do
        local sk = M.subject_key(f.subject)
        if TYPE_PREDICATES[f.predicate] then
            by_subject_type[sk] = by_subject_type[sk] or {}
            by_subject_type[sk][f.predicate] = true
        end
        if f.predicate == "shape_eq" then
            if by_subject_shape[sk] and value_key(by_subject_shape[sk]) ~= value_key(f.value) then
                self.contradiction_list[#self.contradiction_list + 1] = "conflicting shapes for " .. sk
            end
            by_subject_shape[sk] = f.value
        end
    end
    for sk, ts in pairs(by_subject_type) do
        local concrete = {}
        for t in pairs(ts) do if t ~= "is_number" then concrete[#concrete + 1] = t end end
        if #concrete > 1 then
            table.sort(concrete)
            self.contradiction_list[#self.contradiction_list + 1] = "conflicting types for " .. sk .. ": " .. table.concat(concrete, ",")
        end
    end
    return self.contradiction_list
end

function FactSet:contradictions() return copy_array(self.contradiction_list) end
function FactSet:ok() return #(self.contradiction_list or {}) == 0 end

function FactSet:guards_required()
    local out = {}
    for f in self:each() do
        if f.source ~= "static" and f.source ~= "implied" then out[#out + 1] = f end
    end
    table.sort(out, function(a, b) return M.key(a) < M.key(b) end)
    return out
end

function FactSet:deps()
    local seen, out = {}, {}
    for f in self:each() do
        for _, d in ipairs(f.deps or {}) do if not seen[d] then seen[d] = true; out[#out + 1] = d end end
    end
    table.sort(out)
    return out
end

function FactSet:list()
    local out = {}
    for f in self:each() do out[#out + 1] = f end
    table.sort(out, function(a, b) return M.key(a) < M.key(b) end)
    return out
end

function FactSet:canonical_key()
    local parts = {}
    for _, f in ipairs(self:list()) do parts[#parts + 1] = M.key(f) end
    return table.concat(parts, "|")
end

function FactSet:hash() return Util.stable_hash(self:canonical_key()) end

function FactSet:project(subjects)
    local want = {}
    for _, s in ipairs(subjects or {}) do want[M.subject_key(s)] = true end
    local out = M.new()
    for f in self:each() do if want[M.subject_key(f.subject)] then out:add(f) end end
    return out:close()
end

function FactSet:merge(other)
    local out = M.new(self:list())
    for f in (other or M.new()):each() do out:add(f) end
    return out:close()
end

function FactSet:legacy_checked()
    local out = {}
    for _, f in ipairs(self:guards_required()) do out[#out + 1] = f.predicate end
    table.sort(out)
    return out
end

return M
