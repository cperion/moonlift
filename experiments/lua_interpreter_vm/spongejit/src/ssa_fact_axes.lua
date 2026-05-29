-- ssa_fact_axes.lua -- curated fact-axis source for SponJIT foundry SSA.
--
-- This module is the contract between grammar enumeration, SSA lowering, bank
-- selection, and runtime patching. It deliberately does not enumerate a blind
-- powerset first. Instead it builds semantic bundles: facts that must travel
-- together for a lowering to be executable (type + guard lease + payload lease).
-- `subsets` then emits a bounded, ordered candidate ladder from those bundles.

local bit = require("bit")
local Facts = require("src.facts")

local M = {}

local BIN_RR = { ADD=true, SUB=true, MUL=true, DIV=true, MOD=true, IDIV=true,
  BAND=true, BOR=true, BXOR=true, SHL=true, SHR=true }
local BIN_RI = { ADDI=true, SHLI=true, SHRI=true }
local BIN_K = { ADDK=true, SUBK=true, MULK=true, MODK=true, POWK=true,
  DIVK=true, IDIVK=true, BANDK=true, BORK=true, BXORK=true }
local UNARY_I64 = { UNM=true, BNOT=true }
local CMP_RR = { EQ=true, LT=true, LE=true }
local CMP_RI = { EQI=true, LTI=true, LEI=true, GTI=true, GEI=true }
local CMP_K = { EQK=true }
local FIELD_GET = { GETFIELD=true, GETTABUP=true, SELF=true }
local FIELD_SET = { SETFIELD=true, SETTABUP=true }
local ARRAY_GET = { GETTABLE=true, GETI=true }
local ARRAY_SET = { SETTABLE=true, SETI=true }
local CALL = { CALL=true, TAILCALL=true }

local function opname(op) return type(op) == "table" and tostring(op.op) or tostring(op) end
local function reg(n) return n ~= nil and ("R" .. tostring(n)) or nil end
local function kval(k) return "K" .. tostring(k or 0) end
local function pc_id(pc) return "pc" .. tostring(pc or 0) end

local function axis_key(ax)
  local subj = ax.global and "*" or tostring(ax.slot or ax.subject or "?")
  local val = ax.value == nil and "" or tostring(ax.value)
  return subj .. ":" .. tostring(ax.predicate) .. ":" .. val
end

local function add_axis(out, seen, ax)
  if not ax or not ax.predicate then return nil end
  local k = axis_key(ax)
  if not seen[k] then
    seen[k] = ax
    out[#out + 1] = ax
  end
  return seen[k]
end

local function ax_slot(slot, predicate, attrs)
  attrs = attrs or {}
  attrs.slot = slot
  attrs.predicate = predicate
  return attrs
end
local function ax_k(k, predicate, attrs)
  attrs = attrs or {}
  attrs.slot = kval(k)
  attrs.predicate = predicate
  return attrs
end
local function ax_global(predicate, attrs)
  attrs = attrs or {}
  attrs.global = true
  attrs.predicate = predicate
  return attrs
end

local function make_bundle(bundles, name, axes, attrs)
  attrs = attrs or {}
  bundles[#bundles + 1] = {
    name = name,
    axes = axes,
    tier = attrs.tier or 1,
    pc = attrs.pc,
    op = attrs.op,
  }
end

local function bundle_numeric_rr(bundles, n, op, pc)
  local axes = { ax_slot(reg(op.b), "is_i64", {role="lhs"}), ax_slot(reg(op.c), "is_i64", {role="rhs"}) }
  if n == "DIV" or n == "MOD" or n == "IDIV" then axes[#axes + 1] = ax_slot(reg(op.c), "nonzero_i64", {role="rhs"}) end
  make_bundle(bundles, "num_rr:" .. n .. ":" .. pc, axes, {tier=2, pc=pc, op=n})
end

local function bundle_numeric_ri(bundles, n, op, pc)
  make_bundle(bundles, "num_ri:" .. n .. ":" .. pc, {
    ax_slot(reg(op.b), "is_i64", {role="lhs"}),
  }, {tier=2, pc=pc, op=n})
end

local function bundle_numeric_k(bundles, n, op, pc)
  local k = op.c or op.bx or 0
  local axes = {
    ax_slot(reg(op.b), "is_i64", {role="lhs"}),
    ax_k(k, "const_i64", {role="const", value="payload"}),
  }
  if n == "DIVK" or n == "MODK" or n == "IDIVK" then axes[#axes + 1] = ax_k(k, "nonzero_i64", {role="const"}) end
  make_bundle(bundles, "num_k:" .. n .. ":" .. pc, axes, {tier=2, pc=pc, op=n})
end

local function bundle_unary(bundles, n, op, pc)
  make_bundle(bundles, "unary:" .. n .. ":" .. pc, {
    ax_slot(reg(op.b), "is_i64", {role="arg"}),
  }, {tier=2, pc=pc, op=n})
end

local function bundle_cmp_rr(bundles, n, op, pc)
  make_bundle(bundles, "cmp_rr:" .. n .. ":" .. pc, {
    ax_slot(reg(op.a), "is_i64", {role="lhs"}),
    ax_slot(reg(op.b), "is_i64", {role="rhs"}),
  }, {tier=2, pc=pc, op=n})
end

local function bundle_cmp_ri(bundles, n, op, pc)
  make_bundle(bundles, "cmp_ri:" .. n .. ":" .. pc, {
    ax_slot(reg(op.a), "is_i64", {role="lhs"}),
  }, {tier=2, pc=pc, op=n})
end

local function bundle_cmp_k(bundles, n, op, pc)
  local k = op.bx or op.b or 0
  make_bundle(bundles, "cmp_k:" .. n .. ":" .. pc, {
    ax_slot(reg(op.a), "is_i64", {role="lhs"}),
    ax_k(k, "const_i64", {role="const", value="payload"}),
  }, {tier=2, pc=pc, op=n})
end

local function bundle_field_get(bundles, n, op, pc)
  local table_slot = reg(op.b)
  local k = op.c or 0
  -- Complete field lease: table identity, shape guard, metatable guard,
  -- key payload, field-offset payload. shape_eq/field_offset are payload facts;
  -- shape_known/key_const are cheap coarse facts used by selector/lifter.
  make_bundle(bundles, "field_get:" .. n .. ":" .. pc, {
    ax_slot(table_slot, "is_table", {role="table"}),
    ax_slot(table_slot, "shape_known", {role="shape"}),
    ax_slot(table_slot, "shape_eq", {role="shape", value=pc_id(pc)}),
    ax_slot(table_slot, "metatable_absent", {role="metatable"}),
    ax_k(k, "key_const", {role="key"}),
    ax_k(k, "field_offset", {role="field_offset", value=pc_id(pc)}),
  }, {tier=3, pc=pc, op=n})
end

local function bundle_field_set(bundles, n, op, pc)
  if n == "SETTABUP" then return end
  local table_slot = reg(op.a)
  local k = op.b or 0
  make_bundle(bundles, "field_set:" .. n .. ":" .. pc, {
    ax_slot(table_slot, "is_table", {role="table"}),
    ax_slot(table_slot, "shape_known", {role="shape"}),
    ax_slot(table_slot, "shape_eq", {role="shape", value=pc_id(pc)}),
    ax_slot(table_slot, "metatable_absent", {role="metatable"}),
    ax_k(k, "key_const", {role="key"}),
    ax_k(k, "field_offset", {role="field_offset", value=pc_id(pc)}),
    ax_global("barrier_clean", {role="barrier"}),
  }, {tier=3, pc=pc, op=n})
end

local function bundle_array_get(bundles, n, op, pc)
  local table_slot = reg(op.b)
  local axes = {
    ax_slot(table_slot, "is_table", {role="table"}),
    ax_slot(table_slot, "metatable_absent", {role="metatable"}),
    ax_slot(table_slot, "array_hit", {role="array"}),
    ax_slot(table_slot, "bounds_ok", {role="bounds"}),
    ax_slot(table_slot, "array_base_offset", {role="array_payload", value=pc_id(pc)}),
  }
  if n == "GETTABLE" then
    axes[#axes + 1] = ax_slot(reg(op.c), "is_i64", {role="key"})
    axes[#axes + 1] = ax_slot(reg(op.c), "key_i64", {role="key"})
  end
  make_bundle(bundles, "array_get:" .. n .. ":" .. pc, axes, {tier=3, pc=pc, op=n})
end

local function bundle_array_set(bundles, n, op, pc)
  local table_slot = reg(op.a)
  local axes = {
    ax_slot(table_slot, "is_table", {role="table"}),
    ax_slot(table_slot, "metatable_absent", {role="metatable"}),
    ax_slot(table_slot, "array_hit", {role="array"}),
    ax_slot(table_slot, "bounds_ok", {role="bounds"}),
    ax_slot(table_slot, "array_base_offset", {role="array_payload", value=pc_id(pc)}),
    ax_global("barrier_clean", {role="barrier"}),
  }
  if n == "SETTABLE" then
    axes[#axes + 1] = ax_slot(reg(op.b), "is_i64", {role="key"})
    axes[#axes + 1] = ax_slot(reg(op.b), "key_i64", {role="key"})
  end
  make_bundle(bundles, "array_set:" .. n .. ":" .. pc, axes, {tier=3, pc=pc, op=n})
end

local function bundle_call(bundles, n, op, pc)
  local callee = reg(op.a)
  make_bundle(bundles, "call:" .. n .. ":" .. pc, {
    ax_slot(callee, "is_closure", {role="callee"}),
    ax_slot(callee, "known_call_target", {role="callee"}),
    ax_slot(callee, "target_eq", {role="call_target", value=pc_id(pc)}),
  }, {tier=4, pc=pc, op=n})
end

local function bundle_for(bundles, n, op, pc)
  local a = op.a or 0
  make_bundle(bundles, "for:" .. n .. ":" .. pc, {
    ax_slot(reg(a), "is_i64", {role="index"}),
    ax_slot(reg(a + 1), "is_i64", {role="limit"}),
    ax_slot(reg(a + 2), "is_i64", {role="step"}),
  }, {tier=2, pc=pc, op=n})
end

function M.axes_for_ops(ops)
  local axes, seen = {}, {}
  local bundles = {}
  for pc, op in ipairs(ops or {}) do
    local n = opname(op)
    if BIN_RR[n] then bundle_numeric_rr(bundles, n, op, pc)
    elseif BIN_RI[n] then bundle_numeric_ri(bundles, n, op, pc)
    elseif BIN_K[n] then bundle_numeric_k(bundles, n, op, pc)
    elseif UNARY_I64[n] then bundle_unary(bundles, n, op, pc)
    elseif CMP_RR[n] then bundle_cmp_rr(bundles, n, op, pc)
    elseif CMP_RI[n] then bundle_cmp_ri(bundles, n, op, pc)
    elseif CMP_K[n] then bundle_cmp_k(bundles, n, op, pc)
    elseif FIELD_GET[n] then bundle_field_get(bundles, n, op, pc)
    elseif FIELD_SET[n] then bundle_field_set(bundles, n, op, pc)
    elseif ARRAY_GET[n] then bundle_array_get(bundles, n, op, pc)
    elseif ARRAY_SET[n] then bundle_array_set(bundles, n, op, pc)
    elseif CALL[n] then bundle_call(bundles, n, op, pc)
    elseif n == "FORPREP" or n == "FORLOOP" then bundle_for(bundles, n, op, pc)
    end
  end

  for _, b in ipairs(bundles) do
    b.axis_refs = {}
    for _, ax in ipairs(b.axes or {}) do
      local ref = add_axis(axes, seen, ax)
      if ref then b.axis_refs[#b.axis_refs + 1] = ref end
    end
  end
  axes.bundles = bundles
  return axes
end

local function fact_for_axis(ax)
  if ax.global then
    return Facts.fact("runtime", Facts.global_subject(), ax.predicate, ax.value or true, "assumed")
  end
  local s = tostring(ax.slot or "?")
  local subject
  if s:match("^R%d+$") then subject = Facts.slot(s)
  elseif s:match("^K") then subject = Facts.value(s)
  else subject = Facts.value(s) end
  return Facts.fact("assumed", subject, ax.predicate, ax.value or true, "assumed")
end

local function facts_for_axes(axis_list)
  local facts, seen = {}, {}
  for _, ax in ipairs(axis_list or {}) do
    local f = fact_for_axis(ax)
    local k = Facts.key(f)
    if not seen[k] then seen[k] = true; facts[#facts + 1] = f end
  end
  return facts
end

local function add_set(out, seen, axes)
  local facts = facts_for_axes(axes)
  local keys = {}
  for _, f in ipairs(facts) do keys[#keys + 1] = Facts.key(f) end
  table.sort(keys)
  local k = table.concat(keys, "|")
  if not seen[k] then seen[k] = true; out[#out + 1] = facts end
end

local function legacy_powerset(axes, max)
  local n = #axes
  if n == 0 then return {{}} end
  local total = 2 ^ n
  local limit = (max > 0 and max < total) and max or total
  local out = {}
  for i = 0, limit - 1 do
    local idx = (limit == total) and i or math.floor(i * total / limit)
    local xs = {}
    for j = 0, n - 1 do
      if bit.band(idx, bit.lshift(1, j)) ~= 0 then xs[#xs + 1] = axes[j + 1] end
    end
    out[#out + 1] = facts_for_axes(xs)
  end
  return out
end

function M.subsets(axes, config)
  config = config or {}
  local max = tonumber(config.max_fact_combos or os.getenv("MAX_FACT_COMBOS") or 0) or 0
  local mode = tostring(config.fact_axis_mode or os.getenv("FACT_AXIS_MODE") or "curated")
  if mode == "powerset" then return legacy_powerset(axes, max) end

  local bundles = axes.bundles or {}
  if #bundles == 0 then return {{}} end

  local out, seen = {}, {}
  add_set(out, seen, {}) -- floor/generic candidate is always explicit.

  -- Single-op executable bundles: critical for same-span fallback ladders.
  for _, b in ipairs(bundles) do add_set(out, seen, b.axis_refs) end

  -- Prefix cumulative bundles: models straight-line hot windows. This is the
  -- most important curated ladder for arity<=4.
  local prefix = {}
  for _, b in ipairs(bundles) do
    for _, ax in ipairs(b.axis_refs or {}) do prefix[#prefix + 1] = ax end
    add_set(out, seen, prefix)
  end

  -- Tiered cumulative bundles: numeric first, then table/array, then calls.
  for tier = 1, 4 do
    local xs = {}
    for _, b in ipairs(bundles) do
      if (b.tier or 1) <= tier then for _, ax in ipairs(b.axis_refs or {}) do xs[#xs + 1] = ax end end
    end
    add_set(out, seen, xs)
  end

  -- Full executable bundle.
  local full = {}
  for _, b in ipairs(bundles) do for _, ax in ipairs(b.axis_refs or {}) do full[#full + 1] = ax end end
  add_set(out, seen, full)

  -- If caller asks for more, add deterministic sparse powerset samples after
  -- curated forms, never before them.
  if max == 0 or #out < max then
    local extra_max = (max > 0) and (max - #out) or 0
    if extra_max ~= 0 then
      local extras = legacy_powerset(axes, extra_max)
      for _, fs in ipairs(extras) do
        local axs = {}
        -- extras are already facts; add directly by key.
        local keys = {}
        for _, f in ipairs(fs) do keys[#keys + 1] = Facts.key(f) end
        table.sort(keys)
        local k = table.concat(keys, "|")
        if not seen[k] then seen[k] = true; out[#out + 1] = fs end
      end
    end
  end

  if max > 0 and #out > max then
    local trimmed = {}
    for i = 1, max do trimmed[i] = out[i] end
    return trimmed
  end
  return out
end

return M
