-- stencil_ir.lua -- semantic stencil shape IR for native fragment lowering.
--
-- Semantic SSA remains the Lua semantics authority. This module defines
-- hole-parametric operation shape consumed by normalization, contracts,
-- fragment metadata validation, and native emission.

local M = {}

local KNOWN_OP = {
  LoadSlot = true, StoreSlot = true, StoreI64Slot = true,
  LoadConst = true, ConstI64 = true, ConstI64Hole = true, ConstNil = true, ConstBool = true,
  Move = true, GuardI64 = true, GuardTable = true, GuardShape = true,
  GuardMetatableAbsent = true, GuardCallTarget = true, GuardArrayHit = true, GuardBounds = true,
  UnboxI64 = true, BoxI64Scratch = true,
  AddI64 = true, SubI64 = true, MulI64 = true, I64BinOp = true, I64UnaryOp = true, CmpI64 = true,
  FieldLoad = true, FieldStore = true, ArrayLoad = true, ArrayStore = true, BarrierCheck = true,
  ExitResidual = true, ExitBoundary = true, ExitUnlowered = true,
}
M.KNOWN_OP = KNOWN_OP

local DATA_HOLE_ROLE = {
  unknown = true,
  slot = true,
  slot_store = true,
  imm = true,
  const = true,
  bool = true,
  shape_offset = true,
  shape_id = true,
  metatable_offset = true,
  field_offset = true,
  array_base_offset = true,
  call_target = true,
  barrier = true,
}
M.DATA_HOLE_ROLE = DATA_HOLE_ROLE

local function copy_array(xs)
  local out = {}
  for i, x in ipairs(xs or {}) do out[i] = x end
  return out
end

local function role_name(kind, arg)
  if kind == "slot" then return "R" .. tostring(arg or 0) end
  if kind == "slot_store" then return "slot_R" .. tostring(arg or 0) end
  return tostring(kind or "unknown")
end

local Stencil = {}
Stencil.__index = Stencil
M.Stencil = Stencil

function M.new(source_ops, config)
  return setmetatable({
    ops = {},
    values = {},
    value_order = {},
    holes = {},
    hole_by_key = {},
    slotmaps = {},
    exits = {},
    facts = {},
    source_ops = copy_array(source_ops or {}),
    config = config or {},
    next_value = 1,
    next_hole = 0,
  }, Stencil)
end

function Stencil:new_value(ty, source, residency, facts)
  local id = "sv" .. tostring(self.next_value)
  self.next_value = self.next_value + 1
  local v = { id = id, ty = ty or "Unknown", source = source, residency = residency, facts = copy_array(facts) }
  self.values[id] = v
  self.value_order[#self.value_order + 1] = id
  return id
end

function Stencil:add_slotmap(op_idx, logical_slot, field_kind)
  if logical_slot == nil or field_kind == nil then return end
  logical_slot = tonumber(logical_slot)
  if not logical_slot or logical_slot < 0 or logical_slot >= 256 then return end
  local k = tostring(op_idx or 0) .. ":" .. tostring(logical_slot) .. ":" .. tostring(field_kind)
  self._slotmap_seen = self._slotmap_seen or {}
  if self._slotmap_seen[k] then return end
  self._slotmap_seen[k] = true
  self.slotmaps[#self.slotmaps + 1] = {
    op_idx = tonumber(op_idx or 0) or 0,
    logical_slot = logical_slot,
    field_kind = tonumber(field_kind or 0) or 0,
  }
end

function Stencil:hole(t)
  t = t or {}
  assert(t.role_kind ~= "exit" and t.role_kind ~= "fail", "exit/fail are control endpoints, not data holes")
  local key = t.key or table.concat({t.role_kind or "unknown", tostring(t.role_arg or ""), tostring(t.op_idx or 0), t.ty or "Unknown", tostring(t.semantic and 1 or 0)}, ":")
  local existing = self.hole_by_key[key]
  if existing then return existing end
  local id = self.next_hole
  self.next_hole = self.next_hole + 1
  local h = {
    id = id,
    role_kind = t.role_kind or "unknown",
    role = t.role or role_name(t.role_kind, t.role_arg),
    role_arg = t.role_arg,
    op_idx = tonumber(t.op_idx or 0) or 0,
    ty = t.ty or "uintptr",
    patchable = t.patchable ~= false and (t.patchable or DATA_HOLE_ROLE[t.role_kind or "unknown"] or false),
    semantic = t.semantic and true or false,
    key = key,
  }
  self.holes[#self.holes + 1] = h
  self.hole_by_key[key] = h
  return h
end

function Stencil:add(op, t)
  assert(KNOWN_OP[op], "unknown Stencil IR op: " .. tostring(op))
  t = t or {}
  local n = {
    id = #self.ops + 1,
    op = op,
    inputs = copy_array(t.inputs),
    outputs = copy_array(t.outputs),
    args = t.args or {},
    effect = t.effect or "none",
    source = t.source,
    hole = t.hole,
    guard = t.guard,
    exit = t.exit,
    deps = copy_array(t.deps),
  }
  self.ops[#self.ops + 1] = n
  if n.exit then self.exits[#self.exits + 1] = { op = op, source = n.source or 0, exit = n.exit } end
  return n
end

local function defined_values(st)
  local def = {}
  for _, id in ipairs(st.value_order or {}) do def[id] = true end
  return def
end

function M.validate(st)
  local errors = {}
  if not st then return false, {"missing stencil"} end
  local def = defined_values(st)
  for i, h in ipairs(st.holes or {}) do
    if h.id ~= i - 1 then errors[#errors + 1] = "non-contiguous hole id at index " .. i end
    if h.role_kind == "exit" or h.role_kind == "fail" then
      errors[#errors + 1] = "control endpoint encoded as data hole: " .. tostring(h.role_kind)
    end
    if (h.role_kind == "slot" or h.role_kind == "slot_store") then
      if h.role_arg == nil or tonumber(h.role_arg) == nil or tonumber(h.role_arg) < 0 or tonumber(h.role_arg) >= 8 then
        errors[#errors + 1] = "slot hole outside 0..7 canonical fact ABI: " .. tostring(h.role_arg)
      end
    end
  end
  for _, op in ipairs(st.ops or {}) do
    if not KNOWN_OP[op.op] then errors[#errors + 1] = "unknown op " .. tostring(op.op) end
    for _, v in ipairs(op.inputs or {}) do if not def[v] then errors[#errors + 1] = "unknown input " .. tostring(v) .. " at op " .. tostring(op.id) end end
    for _, v in ipairs(op.outputs or {}) do if not def[v] then errors[#errors + 1] = "unknown output " .. tostring(v) .. " at op " .. tostring(op.id) end end
  end
  local has_slotmap = {}
  for _, sm in ipairs(st.slotmaps or {}) do
    if sm.logical_slot == nil then errors[#errors + 1] = "slotmap without logical slot" end
    has_slotmap[tonumber(sm.logical_slot)] = true
  end
  for _, h in ipairs(st.holes or {}) do
    if (h.role_kind == "slot" or h.role_kind == "slot_store") and not has_slotmap[tonumber(h.role_arg)] then
      errors[#errors + 1] = "slot hole without matching slotmap: " .. tostring(h.role_arg)
    end
  end
  return #errors == 0, errors
end

return M
