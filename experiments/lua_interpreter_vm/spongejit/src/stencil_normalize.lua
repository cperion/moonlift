-- stencil_normalize.lua -- canonical form/key/hash for hole-parametric Stencil IR.

local Util = require("src.util")
local Facts = require("src.facts")

local M = {}

local function sorted_keys(t)
  local out = {}
  for k in pairs(t or {}) do out[#out + 1] = k end
  table.sort(out, function(a,b) return tostring(a) < tostring(b) end)
  return out
end

local function args_key(args, n)
  if n and n.hole and not n.hole.semantic then return "" end
  local out = {}
  for _, k in ipairs(sorted_keys(args or {})) do
    local v = args[k]
    if type(v) ~= "table" then out[#out + 1] = tostring(k) .. "=" .. tostring(v) end
  end
  return table.concat(out, ",")
end

local IMPORTANT = {
  LoadSlot = "FRAME_LOAD", StoreSlot = "FRAME_STORE", StoreI64Slot = "STORE_I64_SLOT",
  LoadConst = "LOAD_CONST", ConstI64 = "CONST_I64", ConstI64Hole = "CONST_I64_HOLE", ConstNil = "CONST_NIL", ConstBool = "CONST_BOOL",
  Move = "MOVE", GuardI64 = "I64", GuardTable = "TABLE", GuardShape = "SHAPE", GuardMetatableAbsent = "NO_META",
  GuardCallTarget = "CALL_TARGET", GuardArrayHit = "ARRAY_HIT", GuardBounds = "BOUNDS",
  UnboxI64 = "UNBOX_I64", BoxI64Scratch = "BOX_I64",
  AddI64 = "ADD_I64", SubI64 = "SUB_I64", MulI64 = "MUL_I64", I64BinOp = "I64_BINOP", I64UnaryOp = "I64_UNOP", CmpI64 = "CMP_I64",
  FieldLoad = "FIELD_LOAD", FieldStore = "FIELD_STORE", ArrayLoad = "ARRAY_LOAD", ArrayStore = "ARRAY_STORE", BarrierCheck = "BARRIER",
  ExitResidual = "RESIDUAL", ExitBoundary = "BOUNDARY", ExitUnlowered = "UNLOWERED",
}

local CODEGEN_OP = {
  LoadSlot = "load_slot", StoreSlot = "store_slot", StoreI64Slot = "store_i64_slot",
  LoadConst = "load_const", ConstI64 = "const_i64", ConstI64Hole = "const_i64_hole", ConstNil = "const_nil", ConstBool = "const_bool",
  Move = "move_value", GuardI64 = "guard_i64", GuardTable = "guard_table", GuardShape = "guard_shape", GuardMetatableAbsent = "guard_metatable_absent",
  GuardCallTarget = "guard_call_target", GuardArrayHit = "guard_array_hit", GuardBounds = "guard_bounds",
  UnboxI64 = "unbox_i64", BoxI64Scratch = "box_i64_scratch",
  AddI64 = "add_i64", SubI64 = "sub_i64", MulI64 = "mul_i64", I64BinOp = "i64_binop", I64UnaryOp = "i64_unop", CmpI64 = "cmp_i64",
  FieldLoad = "table_field_load", FieldStore = "table_field_store", ArrayLoad = "table_array_load", ArrayStore = "table_array_store", BarrierCheck = "barrier_check",
  ExitResidual = "residual_boundary", ExitBoundary = "boundary", ExitUnlowered = "unlowered_boundary",
}
M.CODEGEN_OP = CODEGEN_OP

local COMPOSITE_PATTERNS = {
  { name = "FIELD_ADDI_UPDATE", seq = {"LoadSlot","GuardTable","GuardShape","GuardMetatableAbsent","FieldLoad","StoreSlot","GuardI64","UnboxI64","ConstI64Hole","AddI64","StoreI64Slot","LoadSlot","FieldStore"} },
  { name = "FIELD_ADDI_UPDATE", seq = {"LoadSlot","GuardTable","GuardShape","GuardMetatableAbsent","FieldLoad","StoreSlot","GuardI64","UnboxI64","ConstI64","AddI64","StoreI64Slot","LoadSlot","FieldStore"} },
  { name = "FIELD_LOAD_RETURN", seq = {"LoadSlot","GuardTable","GuardShape","GuardMetatableAbsent","FieldLoad","StoreSlot","ExitBoundary"} },
  { name = "SELF_CALL", seq = {"LoadSlot","GuardTable","GuardShape","GuardMetatableAbsent","FieldLoad","StoreSlot","LoadSlot","GuardCallTarget","ExitBoundary"} },
}

local function op_list(st)
  local out = {}
  for _, n in ipairs(st.ops or {}) do out[#out + 1] = n.op end
  return out
end

local function compress_patterns(ops)
  local out, i = {}, 1
  while i <= #ops do
    local matched = false
    for _, p in ipairs(COMPOSITE_PATTERNS) do
      local ok = true
      if i + #p.seq - 1 > #ops then ok = false end
      if ok then for j, op in ipairs(p.seq) do if ops[i + j - 1] ~= op then ok = false; break end end end
      if ok then out[#out + 1] = p.name; i = i + #p.seq; matched = true; break end
    end
    if not matched then out[#out + 1] = IMPORTANT[ops[i]] or ops[i]; i = i + 1 end
  end
  return out
end

function M.form(st) return compress_patterns(op_list(st)) end

function M.active_codegen_ops(st)
  local out = {}
  for _, n in ipairs(st.ops or {}) do out[#out + 1] = CODEGEN_OP[n.op] or n.op end
  return out
end

function M.checked_facts(st)
  local seen, out = {}, {}
  for _, n in ipairs(st.ops or {}) do
    if n.guard and n.guard.fact then
      local f = n.guard.fact
      local k = Facts.guard_key(f)
      if not seen[k] then seen[k] = true; out[#out + 1] = f end
    end
  end
  table.sort(out, function(a,b) return Facts.guard_key(a) < Facts.guard_key(b) end)
  return out
end

function M.checked_fact_names(st)
  local out = {}
  for _, f in ipairs(M.checked_facts(st)) do out[#out + 1] = f.predicate end
  table.sort(out)
  return out
end

function M.deps(st)
  local seen, out = {}, {}
  for _, n in ipairs(st.ops or {}) do
    for _, d in ipairs(n.deps or {}) do if not seen[d] then seen[d] = true; out[#out + 1] = d end end
    if n.guard and n.guard.fact then
      for _, d in ipairs(n.guard.fact.deps or {}) do if not seen[d] then seen[d] = true; out[#out + 1] = d end end
    end
  end
  table.sort(out)
  return out
end

function M.projection(st)
  local exits, virtuals, reasons = 0, 0, {}
  for _, n in ipairs(st.ops or {}) do
    if n.exit then
      exits = exits + 1
      reasons[#reasons + 1] = n.exit.reason or n.op or "exit"
      if n.exit.virtual_values then virtuals = virtuals + #n.exit.virtual_values end
    end
  end
  table.sort(reasons)
  return { ok = true, exit_obligations = exits, virtual_values = virtuals, reasons = reasons }
end

local function hole_ref(h)
  if not h then return "" end
  return table.concat({"h", tostring(h.id), h.role_kind or "unknown", tostring(h.role_arg or ""), h.ty or "", h.patchable and "P" or "NP", h.semantic and "S" or "V"}, ":")
end

function M.key(st)
  local vmap, vnext, lines = {}, 0, {}
  local function val(v)
    if not v then return "" end
    if not vmap[v] then vnext = vnext + 1; vmap[v] = "v" .. tostring(vnext) end
    return vmap[v]
  end
  for _, h in ipairs(st.holes or {}) do
    lines[#lines + 1] = table.concat({"HOLE", tostring(h.id), h.role_kind or "unknown", tostring(h.role_arg or ""), h.ty or "", h.patchable and "P" or "NP", h.semantic and "S" or "V"}, ";")
  end
  for _, sm in ipairs(st.slotmaps or {}) do
    lines[#lines + 1] = table.concat({"SLOTMAP", tostring(sm.op_idx), tostring(sm.logical_slot), tostring(sm.field_kind)}, ";")
  end
  for _, n in ipairs(st.ops or {}) do
    local ins, outs = {}, {}
    for _, x in ipairs(n.inputs or {}) do ins[#ins + 1] = val(x) end
    for _, x in ipairs(n.outputs or {}) do outs[#outs + 1] = val(x) end
    local guard = n.guard and n.guard.key or ""
    local exit = n.exit and (n.exit.reason or "exit") or ""
    lines[#lines + 1] = table.concat({"OP", n.op, table.concat(ins, ","), table.concat(outs, ","), n.effect or "none", hole_ref(n.hole), guard, exit, args_key(n.args, n)}, ";")
  end
  return table.concat(lines, "|")
end

function M.hash(st)
  local facts = {}
  for _, f in ipairs(M.checked_facts(st)) do facts[#facts + 1] = Facts.guard_key(f) end
  return Util.stable_hash(M.key(st) .. " :: " .. table.concat(facts, ",") .. " :: " .. table.concat(M.deps(st), ","))
end

return M
