-- ssa_to_stencil.lua -- lower optimized semantic SSA into hole-parametric Stencil IR.

local SIR = require("src.stencil_ir")
local IR = require("src.ssa_ir")
local Facts = require("src.facts")

local M = {}

local FIELD_KIND = { a = 1, b = 2, c = 3, dest = 4, aux = 5, cur = 0 }

local SLOT_FIELDS_BY_OP = {
  MOVE={"a","b"},
  LOADI={"a"}, LOADF={"a"}, LOADK={"a"}, LOADKX={"a"}, LOADFALSE={"a"}, LFALSESKIP={"a"}, LOADTRUE={"a"}, LOADNIL={"a"},
  GETUPVAL={"a"}, SETUPVAL={"a"},
  GETTABLE={"a","b","c"}, GETI={"a","b"}, GETFIELD={"a","b"}, GETTABUP={"a"}, SELF={"a","b"},
  SETTABLE={"a","b","c"}, SETI={"a","c"}, SETFIELD={"a","c"}, SETTABUP={"b","c"},
  NEWTABLE={"a"},
  ADD={"a","b","c"}, SUB={"a","b","c"}, MUL={"a","b","c"}, MOD={"a","b","c"}, POW={"a","b","c"}, DIV={"a","b","c"}, IDIV={"a","b","c"},
  BAND={"a","b","c"}, BOR={"a","b","c"}, BXOR={"a","b","c"}, SHL={"a","b","c"}, SHR={"a","b","c"},
  ADDI={"a","b"}, SHLI={"a","b"}, SHRI={"a","b"},
  ADDK={"a","b"}, SUBK={"a","b"}, MULK={"a","b"}, MODK={"a","b"}, POWK={"a","b"}, DIVK={"a","b"}, IDIVK={"a","b"},
  BANDK={"a","b"}, BORK={"a","b"}, BXORK={"a","b"},
  UNM={"a","b"}, BNOT={"a","b"}, NOT={"a","b"}, LEN={"a","b"}, CONCAT={"a","b","c"},
  EQ={"a","b","dest"}, LT={"a","b","dest"}, LE={"a","b","dest"}, EQK={"a"}, EQI={"a","dest"}, LTI={"a","dest"}, LEI={"a","dest"}, GTI={"a","dest"}, GEI={"a","dest"},
  TEST={"a","b"}, TESTSET={"a","b"},
  CALL={"a"}, TAILCALL={"a"}, RETURN={"a"}, RETURN1={"a"},
  FORPREP={"a"}, FORLOOP={"a"}, TFORPREP={"a"}, TFORCALL={"a"}, TFORLOOP={"a"},
  SETLIST={"a"}, CLOSURE={"a"}, VARARG={"a"}, GETVARG={"a"},
  MMBIN={"a","b"}, MMBINI={"a"}, MMBINK={"a","b"}, CLOSE={"a"}, TBC={"a"}, ERRNNIL={"a"},
}
M.FIELD_KIND = FIELD_KIND

local function copy_array(xs)
  local out = {}
  for i, x in ipairs(xs or {}) do out[i] = x end
  return out
end

local function slot_number(slot)
  if type(slot) == "number" then return slot end
  if type(slot) == "string" then return tonumber(slot:match("^R(%d+)$") or slot:match("^(%d+)$")) end
  return nil
end

local function source_op_name(op)
  return type(op) == "table" and tostring(op.op or "") or tostring(op or "")
end

local function build_slot_classes(source_ops)
  local concrete_to_class, class_to_concrete, occurrences = {}, {}, {}
  local function class_for(conc)
    conc = tonumber(conc)
    if not conc then return nil end
    if concrete_to_class[conc] == nil then
      local cls = #class_to_concrete
      concrete_to_class[conc] = cls
      class_to_concrete[#class_to_concrete + 1] = conc
    end
    return concrete_to_class[conc]
  end
  for pc, op in ipairs(source_ops or {}) do
    if type(op) == "table" then
      for _, field in ipairs(SLOT_FIELDS_BY_OP[source_op_name(op)] or {}) do
        local conc = tonumber(op[field])
        if conc then
          local cls = class_for(conc)
          occurrences[cls] = occurrences[cls] or {}
          occurrences[cls][#occurrences[cls] + 1] = {op_idx = pc - 1, field_kind = FIELD_KIND[field] or 0, concrete = conc}
        end
      end
    end
  end
  return concrete_to_class, class_to_concrete, occurrences
end

local function const_role_for_source(source_ops, pc, args)
  local src = source_ops and source_ops[pc]
  local on = source_op_name(src)
  if on == "LOADI" or on == "LOADF" then return "imm", "imm" end
  if on == "ADDI" or on == "SHLI" or on == "SHRI" then return "imm", "sC" end
  if on:match("K$") or on == "EQK" then return "const", "k_i64" end
  if on == "JMP" or on == "FORPREP" or on == "FORLOOP" then return "imm", "sBx" end
  return nil, nil
end

function M.lower(ssa_result_or_graph, source_ops, config)
  config = config or {}
  local g = ssa_result_or_graph.graph or ssa_result_or_graph
  source_ops = source_ops or ssa_result_or_graph.source_ops or {}
  local st = SIR.new(source_ops, config)
  local concrete_to_class, class_to_concrete, occurrences = build_slot_classes(source_ops)
  st.slot_class_by_concrete = concrete_to_class
  st.slot_concrete_by_class = class_to_concrete

  for cls, occs in pairs(occurrences) do
    for _, occ in ipairs(occs) do st:add_slotmap(occ.op_idx, cls, occ.field_kind) end
  end

  local function slot_class(slot, pc)
    local conc = slot_number(slot)
    local cls
    if conc then cls = concrete_to_class[conc] end
    if cls == nil then
      cls = #class_to_concrete
      class_to_concrete[#class_to_concrete + 1] = conc or cls
      if conc then concrete_to_class[conc] = cls end
    end
    if not occurrences[cls] then
      occurrences[cls] = {{op_idx = math.max(0, (pc or 1) - 1), field_kind = FIELD_KIND.cur, concrete = conc or cls}}
      st:add_slotmap(occurrences[cls][1].op_idx, cls, FIELD_KIND.cur)
    end
    return cls
  end

  local function canonical_guard(guard)
    if not guard or not guard.fact then return guard end
    local f = guard.fact
    local conc = slot_number(f.subject and f.subject.id)
    if conc == nil then return guard end
    local cls = slot_class(conc, 1)
    local nf = {}
    for k, v in pairs(f) do nf[k] = v end
    nf.subject = Facts.slot("R" .. tostring(cls))
    local ng = {}
    for k, v in pairs(guard) do ng[k] = v end
    ng.fact = nf
    ng.key = Facts.guard_key(nf)
    return ng
  end

  local function hole_for_slot(kind, slot, pc)
    local cls = slot_class(slot, pc)
    local occ = (occurrences[cls] and occurrences[cls][1]) or {op_idx = math.max(0, (pc or 1) - 1)}
    -- Prefer same-op occurrence when possible; runtime slot patching resolves by op_idx.
    for _, o in ipairs(occurrences[cls] or {}) do if o.op_idx == math.max(0, (pc or 1) - 1) then occ = o; break end end
    return st:hole({ role_kind = kind, role_arg = cls, op_idx = occ.op_idx, ty = "slot", key = kind .. ":" .. tostring(cls) .. ":" .. tostring(occ.op_idx) })
  end

  local vmap = {}
  local function map_value(vid)
    if not vid then return nil end
    if not vmap[vid] then
      local vv = g.values and g.values[vid]
      vmap[vid] = st:new_value(vv and vv.ty or "Unknown", vid, vv and vv.residency, vv and vv.facts)
    end
    return vmap[vid]
  end
  local function new_output(vid)
    local vv = g.values and g.values[vid]
    local out = st:new_value(vv and vv.ty or "Unknown", vid, vv and vv.residency, vv and vv.facts)
    vmap[vid] = out
    return out
  end

  local consumers = {}
  for _, n in ipairs(g.nodes or {}) do if not n.removed then
    for _, v in ipairs(n.inputs or {}) do consumers[v] = (consumers[v] or 0) + 1 end
  end end

  local skip = {}
  for idx, n in ipairs(g.nodes or {}) do
    if n.removed or skip[n.id] then goto continue end
    local pc = n.source or 1
    local op, args = n.op, n.args or {}
    local ins, outs = {}, {}
    for _, v in ipairs(n.inputs or {}) do ins[#ins + 1] = map_value(v) end
    for _, v in ipairs(n.outputs or {}) do outs[#outs + 1] = new_output(v) end

    if op == "FrameLoad" then
      local h = hole_for_slot("slot", args.slot or "cur", pc)
      st:add("LoadSlot", { outputs = outs, source = pc, hole = h, args = { slot = h.role_arg }, effect = "frame_read" })

    elseif op == "FrameStore" then
      local h = hole_for_slot("slot_store", args.slot or "cur", pc)
      st:add("StoreSlot", { inputs = ins, source = pc, hole = h, args = { slot = h.role_arg }, effect = "frame_write" })

    elseif op == "BoxI64" then
      local fused = nil
      for j = idx + 1, #g.nodes do
        local m = g.nodes[j]
        if not m.removed then
          if m.op == "FrameStore" and m.inputs and m.inputs[1] == (n.outputs and n.outputs[1]) then fused = m end
          break
        end
      end
      if fused then
        local h = hole_for_slot("slot_store", fused.args and fused.args.slot or "cur", fused.source or pc)
        local box_out = n.outputs and n.outputs[1]
        local keep_tvalue = (consumers[box_out] or 0) > 1
        local fused_outs = keep_tvalue and outs or {}
        st:add("StoreI64Slot", { inputs = ins, outputs = fused_outs, source = fused.source or pc, hole = h, args = { slot = h.role_arg }, effect = "frame_write" })
        skip[fused.id] = true
      else
        st:add("BoxI64Scratch", { inputs = ins, outputs = outs, source = pc })
      end

    elseif op == "GuardTypeI64" then
      st:add("GuardI64", { inputs = ins, source = pc, guard = canonical_guard(n.guard), deps = n.deps, exit = n.exit, effect = "guard" })
    elseif op == "GuardTable" then
      st:add("GuardTable", { inputs = ins, source = pc, guard = canonical_guard(n.guard), deps = n.deps, exit = n.exit, effect = "guard" })
    elseif op == "GuardShape" then
      local off = st:hole({ role_kind = "shape_offset", role = "shape_offset", op_idx = 0, ty = "offset", patchable = false, semantic = true })
      local sid = st:hole({ role_kind = "shape_id", role = "shape_id", op_idx = 0, ty = "u32", patchable = false, semantic = true })
      st:add("GuardShape", { inputs = ins, source = pc, guard = canonical_guard(n.guard), deps = n.deps, exit = n.exit, effect = "guard", args = { shape_offset = off.id, shape_id = sid.id } })
    elseif op == "GuardMetatableAbsent" then
      local off = st:hole({ role_kind = "metatable_offset", role = "metatable_offset", op_idx = 0, ty = "offset", patchable = false, semantic = true })
      st:add("GuardMetatableAbsent", { inputs = ins, source = pc, guard = canonical_guard(n.guard), deps = n.deps, exit = n.exit, effect = "guard", args = { metatable_offset = off.id } })
    elseif op == "GuardArrayHit" then
      st:add("GuardArrayHit", { inputs = ins, source = pc, guard = canonical_guard(n.guard), deps = n.deps, exit = n.exit, effect = "guard" })
    elseif op == "GuardBounds" then
      st:add("GuardBounds", { inputs = ins, source = pc, guard = canonical_guard(n.guard), deps = n.deps, exit = n.exit, effect = "guard" })
    elseif op == "GuardCallTarget" then
      local target = st:hole({ role_kind = "call_target", role = "call_target", op_idx = 0, ty = "ptr", patchable = false, semantic = true })
      st:add("GuardCallTarget", { inputs = ins, source = pc, guard = canonical_guard(n.guard), deps = n.deps, exit = n.exit, effect = "guard", args = { call_target = target.id } })

    elseif op == "ConstI64" then
      local rk, role = const_role_for_source(source_ops, pc, args)
      if rk then
        local h = st:hole({ role_kind = rk, role = role, op_idx = math.max(0, pc - 1), ty = "i64", semantic = false, key = role .. ":" .. tostring(math.max(0, pc - 1)) })
        st:add("ConstI64Hole", { outputs = outs, source = pc, hole = h, args = { role = role } })
      else
        st:add("ConstI64", { outputs = outs, source = pc, args = { value = tonumber(args.value) or 0 } })
      end
    elseif op == "LoadConst" then
      local h = st:hole({ role_kind = "const", role = "k_idx", op_idx = math.max(0, pc - 1), ty = "const", semantic = false, key = "k_idx:" .. tostring(math.max(0, pc - 1)) })
      st:add("LoadConst", { outputs = outs, source = pc, hole = h, args = { const = args.const } })
    elseif op == "ConstNil" then st:add("ConstNil", { outputs = outs, source = pc })
    elseif op == "ConstBool" then
      local h = st:hole({ role_kind = "bool", role = "bool_val", op_idx = math.max(0, pc - 1), ty = "bool", semantic = false, key = "bool:" .. tostring(pc) })
      st:add("ConstBool", { outputs = outs, source = pc, hole = h, args = { value = args.value and true or false } })
    elseif op == "Move" then st:add("Move", { inputs = ins, outputs = outs, source = pc })
    elseif op == "UnboxI64" then st:add("UnboxI64", { inputs = ins, outputs = outs, source = pc })
    elseif op == "AddI64" or op == "SubI64" or op == "MulI64" or op == "I64BinOp" or op == "I64UnaryOp" or op == "CmpI64" then
      st:add(op, { inputs = ins, outputs = outs, source = pc, args = args })
    elseif op == "FieldLoad" then
      local h = st:hole({ role_kind = "field_offset", role = "field_offset", op_idx = math.max(0, pc - 1), ty = "offset", patchable = false, semantic = true })
      st:add("FieldLoad", { inputs = ins, outputs = outs, source = pc, hole = h, args = { key = args.key }, effect = "heap_read" })
    elseif op == "FieldStore" then
      local h = st:hole({ role_kind = "field_offset", role = "field_offset", op_idx = math.max(0, pc - 1), ty = "offset", patchable = false, semantic = true })
      st:add("FieldStore", { inputs = ins, source = pc, hole = h, args = { key = args.key }, effect = "heap_write" })
    elseif op == "ArrayLoad" then
      local h = st:hole({ role_kind = "array_base_offset", role = "array_base_offset", op_idx = math.max(0, pc - 1), ty = "offset", patchable = false, semantic = true })
      st:add("ArrayLoad", { inputs = ins, outputs = outs, source = pc, hole = h, effect = "heap_read" })
    elseif op == "ArrayStore" then
      local h = st:hole({ role_kind = "array_base_offset", role = "array_base_offset", op_idx = math.max(0, pc - 1), ty = "offset", patchable = false, semantic = true })
      st:add("ArrayStore", { inputs = ins, source = pc, hole = h, effect = "heap_write" })
    elseif op == "BarrierCheck" then
      local h = st:hole({ role_kind = "barrier", role = "barrier", op_idx = math.max(0, pc - 1), ty = "bool", patchable = false, semantic = true })
      st:add("BarrierCheck", { inputs = ins, source = pc, hole = h, exit = n.exit, effect = "gc_barrier" })
    elseif op == "GenericExit" or op == "Residual" then
      st:add("ExitResidual", { inputs = ins, source = pc, args = args, exit = n.exit, effect = "residual" })
    elseif op == "Jump" or op == "Return1" or op == "Return0" or op == "Call" or op == "KnownCall" or op == "TailCall" then
      st:add("ExitBoundary", { inputs = ins, source = pc, args = { op = op }, exit = n.exit, effect = n.effect or "return" })
    else
      st:add("ExitUnlowered", { inputs = ins, source = pc, args = { op = op }, exit = n.exit, effect = "residual" })
    end
    ::continue::
  end

  table.sort(st.slotmaps, function(a, b)
    if a.op_idx ~= b.op_idx then return a.op_idx < b.op_idx end
    if a.logical_slot ~= b.logical_slot then return a.logical_slot < b.logical_slot end
    return a.field_kind < b.field_kind
  end)
  return st
end

return M
