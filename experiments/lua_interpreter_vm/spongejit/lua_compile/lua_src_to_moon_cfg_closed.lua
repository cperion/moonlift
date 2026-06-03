-- lua_src_to_moon_cfg_closed.lua -- bounded closed LuaSrc window -> MoonCFG.
--
-- This pass is the source-topology lowering path for closed bytecode windows:
-- every accepted control edge is resolved to another PC inside the provided
-- LuaSrc.Window and rendered as MoonCFG blocks/jumps/branches.  It deliberately
-- does not use LuaNF JumpExit/ConditionalJumpExit, because those are external
-- kernel exits in the older pipeline, not closed internal CFG edges.
--
-- Architecture in one place:
--   * scan_shape builds the PC -> op map, validates all control targets are in
--     the window, identifies block leaders, consumes PUC comparison/JMP pairs,
--     and partitions PCs into basic blocks.
--   * analyze_block_io records per-block use-before-def slots.  Those slots
--     become MoonCFG block params, so internal fallthrough/JMP/branch edges pass
--     live scalar values explicitly with named MoonCFG.Arg values.
--   * lower_instruction is the straight-line opcode table for currently honest
--     scalar values (i64/bool/nil-for-truthiness only).
--   * lower_condition is the control opcode table for PUC comparison+following
--     JMP and TEST.  BranchArgs is used when targets need live values.
--   * lower_block renders block-local operations plus a closed MoonCFG
--     terminator.  The emitter remains mechanical and never inspects LuaSrc.
--
-- Supported value/control semantics are still intentionally bounded: scalar
-- i64/bool constants and params, MOVE, LOADI/LOADK/LOADTRUE/LOADFALSE/LOADNIL,
-- ADDI/ADD/ADDK on proven i64 values, no-op MMBIN companions after lowered
-- primitive arithmetic, in-window JMP, TEST over supported truthiness, PUC
-- comparison+following-JMP branches (EQ/LT/LE/EQK/EQI/LTI/LEI/GTI/GEI),
-- TESTSET edge assignment for supported scalar values, and RETURN/RETURN1/
-- RETURN0. Numeric FORPREP/FORLOOP remains blocked below with a precise reason
-- rather than being faked as an external protocol.

local pvm = require("moonlift.pvm")
local B = require("lua_compile.builders")
local T = B.T
local Src, Fact, LC, CFG = T.LuaSrc, T.LuaFact, T.LuaContract, T.MoonCFG
local Abi = require("lua_compile.moon_cfg_abi")
local FactUse = require("lua_compile.lua_contract_fact_use")

local M = {}

local CONDITION_OP = {
  EQ = true, LT = true, LE = true, EQK = true,
  EQI = true, LTI = true, LEI = true, GTI = true, GEI = true,
  TEST = true, TESTSET = true,
}

local UNSUPPORTED_CLOSED_CONTROL = {
  FORPREP = "unsupported_numeric_for_puc_state_layout_and_loop_edge_values",
  FORLOOP = "unsupported_numeric_for_puc_state_layout_and_loop_edge_values",
}

local CONTROL_OP = { JMP = true }
for k in pairs(CONDITION_OP) do CONTROL_OP[k] = true end
for k in pairs(UNSUPPORTED_CLOSED_CONTROL) do CONTROL_OP[k] = true end

local TERMINAL_RETURN = { RETURN = true, RETURN0 = true, RETURN1 = true }

local ARITH_PREDECESSOR_FOR_MMBIN = {
  ADDI = true, ADDK = true, ADD = true,
}
local MMBIN_MARKER = { MMBIN = true, MMBINI = true, MMBINK = true }

local function cfg_name(s) return CFG.Name(tostring(s)) end
local function type_ref(s) return CFG.TypeRef(tostring(s)) end
local function block_id_for_pc(pc) return CFG.BlockId(cfg_name("pc_" .. tostring(pc))) end
local function block_ref_for_pc(pc) return CFG.BlockRef(block_id_for_pc(pc)) end
local function param_name_for_block_slot(pc, slot_id) return "pc_" .. tostring(pc) .. "_slot_" .. tostring(slot_id) end
local function const_i64(n) return CFG.ConstValue(CFG.I64Const(tonumber(n) or 0)) end
local function const_bool(b) return CFG.ConstValue(CFG.BoolConst(b == true)) end
local function param_value(s) return CFG.ParamValue(cfg_name(s)) end

local function sorted_keys(set)
  local out = {}
  for k in pairs(set or {}) do out[#out + 1] = k end
  table.sort(out)
  return out
end

local function pc_of(op) return op and op.pc and op.pc.id end
local function target_pc(op)
  return (op.pc.id or 0) + (op.offset.value or 0) + 1
end

local function has_fact(evidence, subject_kind, subject_id_field, subject_id, predicate)
  for _, f in ipairs((evidence and evidence.observed) or {}) do
    local subject = f.subject
    if subject and subject.kind == subject_kind and subject[subject_id_field]
        and subject[subject_id_field].id == subject_id
        and f.predicate and f.predicate.kind == predicate then
      return true, f
    end
  end
  return false, nil
end

local function has_i64_fact(evidence, slot)
  local sid = tonumber(slot and slot.id or slot) or 0
  return has_fact(evidence, "SrcSlot", "slot", sid, "IsI64")
end

local function has_bool_fact(evidence, slot)
  local sid = tonumber(slot and slot.id or slot) or 0
  return has_fact(evidence, "SrcSlot", "slot", sid, "IsBool")
end

local function const_i64_fact(evidence, k)
  local kid = tonumber(k and k.id or k) or 0
  local ok, f = has_fact(evidence, "Const", "k", kid, "ConstI64")
  if not ok then return nil end
  local v = tonumber(f.value_key or "")
  if v == nil then return nil end
  return v, f
end

local function add_error(errors, msg)
  errors[#errors + 1] = msg
  return nil
end

local function scan_shape(window)
  local ops = (window and window.ops) or {}
  if #ops == 0 then return nil, { "not_closed_control:no_ops" } end

  local by_pc, index_by_pc = {}, {}
  local has_control, has_return = false, false
  for i, op in ipairs(ops) do
    local pc = pc_of(op)
    if not pc then return nil, { "unsupported_op_without_pc:" .. tostring(op and op.kind) } end
    if by_pc[pc] then return nil, { "duplicate_pc:" .. tostring(pc) } end
    by_pc[pc], index_by_pc[pc] = op, i
    if CONTROL_OP[op.kind] then has_control = true end
    if TERMINAL_RETURN[op.kind] then has_return = true end
  end
  if not has_control then return nil, { "not_closed_control:no_control" } end
  if not has_return then return nil, { "not_closed_control:no_terminal_return" } end

  local leaders = { [pc_of(ops[1])] = true }
  local consumed_jmp = {}
  for i, op in ipairs(ops) do
    local kind = op.kind
    if UNSUPPORTED_CLOSED_CONTROL[kind] then
      return nil, { UNSUPPORTED_CLOSED_CONTROL[kind] .. ":" .. tostring(op.pc.id) }
    elseif kind == "JMP" then
      local target = target_pc(op)
      if not by_pc[target] then return nil, { "external_jump_target:" .. tostring(op.pc.id) .. "->" .. tostring(target) } end
      leaders[target] = true
      if ops[i + 1] then leaders[pc_of(ops[i + 1])] = true end
    elseif CONDITION_OP[kind] then
      local jmp = ops[i + 1]
      if not jmp or jmp.kind ~= "JMP" then return nil, { "conditional_without_following_jmp:" .. tostring(op.pc.id) } end
      local tpc = target_pc(jmp)
      local fop = ops[i + 2]
      if not by_pc[tpc] then return nil, { "external_conditional_target:" .. tostring(op.pc.id) .. "->" .. tostring(tpc) } end
      if not fop then return nil, { "external_conditional_fallthrough:" .. tostring(op.pc.id) } end
      leaders[tpc] = true
      leaders[pc_of(fop)] = true
      consumed_jmp[pc_of(jmp)] = true
    elseif TERMINAL_RETURN[kind] then
      if ops[i + 1] then leaders[pc_of(ops[i + 1])] = true end
    end
  end

  for pc in pairs(leaders) do
    if consumed_jmp[pc] then return nil, { "target_enters_conditional_jmp_companion:" .. tostring(pc) } end
  end

  local blocks = {}
  local assigned_pc = {}
  local i = 1
  while i <= #ops do
    local start = ops[i]
    local start_pc = pc_of(start)
    if consumed_jmp[start_pc] then return nil, { "block_starts_at_consumed_jmp:" .. tostring(start_pc) } end
    if not leaders[start_pc] then return nil, { "internal_partition_error:not_leader:" .. tostring(start_pc) } end
    local instrs = {}
    local term = nil
    while i <= #ops do
      local op = ops[i]
      local pc = pc_of(op)
      if consumed_jmp[pc] then return nil, { "consumed_jmp_reached_as_instruction:" .. tostring(pc) } end
      assigned_pc[pc] = true
      if op.kind == "JMP" then
        term = { kind = "jump", target = target_pc(op) }
        i = i + 1
        break
      elseif CONDITION_OP[op.kind] then
        local jmp = ops[i + 1]
        local false_op = ops[i + 2]
        term = { kind = "branch", op = op, true_target = target_pc(jmp), false_target = pc_of(false_op) }
        assigned_pc[pc_of(jmp)] = true
        i = i + 2
        break
      elseif TERMINAL_RETURN[op.kind] then
        term = { kind = "return", op = op }
        i = i + 1
        break
      else
        instrs[#instrs + 1] = op
        local next_op = ops[i + 1]
        i = i + 1
        if next_op and leaders[pc_of(next_op)] then
          term = { kind = "fallthrough", target = pc_of(next_op) }
          break
        end
      end
    end
    if not term then return nil, { "block_fell_out_of_window:" .. tostring(start_pc) } end
    blocks[#blocks + 1] = { pc = start_pc, instrs = instrs, term = term }
  end

  return { ops = ops, by_pc = by_pc, index_by_pc = index_by_pc, leaders = leaders, consumed_jmp = consumed_jmp, blocks = blocks }, nil
end

local function slot_reads_and_defs(block)
  local reads, defs = {}, {}
  local function read_slot(slot)
    local sid = slot and slot.id
    if sid ~= nil and not defs[sid] then reads[sid] = true end
  end
  local function def_slot(slot)
    local sid = slot and slot.id
    if sid ~= nil then defs[sid] = true end
  end
  local prev
  for _, op in ipairs(block.instrs or {}) do
    if op.kind == "MOVE" then read_slot(op.b); def_slot(op.a)
    elseif op.kind == "ADDI" then read_slot(op.lhs); def_slot(op.a)
    elseif op.kind == "ADD" then read_slot(op.lhs); read_slot(op.rhs); def_slot(op.a)
    elseif op.kind == "ADDK" then read_slot(op.lhs); def_slot(op.a)
    elseif op.kind == "LOADI" or op.kind == "LOADK" or op.kind == "LOADTRUE" or op.kind == "LOADFALSE" then def_slot(op.a)
    elseif op.kind == "LOADNIL" then
      local n = math.max(1, op.count and op.count.value or 1)
      for i = 0, n - 1 do defs[(op.a.id or 0) + i] = true end
    elseif MMBIN_MARKER[op.kind] then
      if not (prev and ARITH_PREDECESSOR_FOR_MMBIN[prev.kind]) then return nil, nil, "unsupported_mmbin_without_lowered_arithmetic:" .. tostring(op.pc.id) end
    else return nil, nil, "unsupported_instruction:" .. tostring(op.kind) end
    prev = op
  end
  local term = block.term
  if term.kind == "return" then
    local op = term.op
    if op.kind == "RETURN1" then read_slot(op.value)
    elseif op.kind == "RETURN" then
      if op.close_upvalues or ((op.c and op.c.value or 0) ~= 0) then return nil, nil, "unsupported_return_close_or_c:" .. tostring(op.pc.id) end
      local n = op.nresults and op.nresults.value or 0
      if n == 2 then read_slot(op.base) elseif n ~= 1 then return nil, nil, "unsupported_return_count:" .. tostring(n) end
    end
  elseif term.kind == "branch" then
    local op = term.op
    if op.kind == "TEST" then read_slot(op.a)
    elseif op.kind == "TESTSET" then read_slot(op.b)
    elseif op.kind == "EQK" then read_slot(op.lhs)
    elseif op.lhs then read_slot(op.lhs); if op.rhs and op.rhs.id ~= nil then read_slot(op.rhs) end end
  end
  return reads, defs, nil
end

local function analyze_block_io(shape)
  local by_pc = {}
  for _, block in ipairs(shape.blocks or {}) do by_pc[block.pc] = block end

  for _, block in ipairs(shape.blocks or {}) do
    local reads, defs, err = slot_reads_and_defs(block)
    if err then return nil, { err } end
    block.use_before_def = reads
    block.defs = defs
  end

  local edge_targets = {}
  for _, block in ipairs(shape.blocks or {}) do
    local term = block.term
    if term.kind == "jump" or term.kind == "fallthrough" then
      edge_targets[term.target] = true
    elseif term.kind == "branch" then
      edge_targets[term.true_target] = true
      edge_targets[term.false_target] = true
    end
  end

  local params_by_pc = {}
  for pc in pairs(edge_targets) do
    if not by_pc[pc] then return nil, { "unresolved_edge_target:" .. tostring(pc) } end
    params_by_pc[pc] = {}
    for sid in pairs(by_pc[pc].use_before_def or {}) do params_by_pc[pc][sid] = true end
  end
  return params_by_pc, nil
end

local function new_builder(evidence, params_by_pc)
  return {
    evidence = evidence,
    params_by_pc = params_by_pc or {},
    kernel_params = {},
    kernel_param_seen = {},
    required_i64 = {},
    required_bool = {},
    required_const_i64 = {},
    temp_id = 1,
    return_ty = nil,
    errors = {},
  }
end

local function param_ty_for_slot(builder, sid)
  local slot = B.slot(sid)
  local is_bool = has_bool_fact(builder.evidence, slot)
  local is_i64 = has_i64_fact(builder.evidence, slot)
  if is_bool and not is_i64 then return "bool" end
  return "i64"
end

local function require_kernel_i64(builder, slot)
  local sid = slot and slot.id or 0
  if not has_i64_fact(builder.evidence, slot) then return add_error(builder.errors, "missing_i64_fact_for_slot:" .. tostring(sid)) end
  local pname = Abi.slot_i64_name(slot)
  if not builder.kernel_param_seen[pname] then
    builder.kernel_param_seen[pname] = true
    builder.kernel_params[#builder.kernel_params + 1] = Abi.param(pname, "i64")
  end
  builder.required_i64[sid] = true
  return { value = param_value(pname), ty = "i64" }
end

local function require_kernel_bool(builder, slot)
  local sid = slot and slot.id or 0
  if not has_bool_fact(builder.evidence, slot) then return add_error(builder.errors, "missing_bool_fact_for_slot:" .. tostring(sid)) end
  local pname = "slot_" .. tostring(sid) .. "_bool"
  if not builder.kernel_param_seen[pname] then
    builder.kernel_param_seen[pname] = true
    builder.kernel_params[#builder.kernel_params + 1] = Abi.param(pname, "bool")
  end
  builder.required_bool[sid] = true
  return { value = param_value(pname), ty = "bool" }
end

local function const_i64_for_k(builder, k)
  local v = const_i64_fact(builder.evidence, k)
  if v == nil then return add_error(builder.errors, "missing_const_i64_fact_for_k:" .. tostring(k and k.id or k)) end
  builder.required_const_i64[k.id or 0] = true
  return { value = const_i64(v), ty = "i64" }
end

local function init_env_for_block(builder, block)
  local env = {}
  for _, sid in ipairs(sorted_keys(builder.params_by_pc[block.pc] or {})) do
    local pname = param_name_for_block_slot(block.pc, sid)
    local ty = param_ty_for_slot(builder, sid)
    env[sid] = { value = param_value(pname), ty = ty }
  end
  return env
end

local function read_i64(builder, env, slot)
  local sid = slot and slot.id or 0
  local cur = env[sid]
  if cur then
    if cur.ty ~= "i64" then return add_error(builder.errors, "slot_not_i64:" .. tostring(sid)) end
    return cur
  end
  return require_kernel_i64(builder, slot)
end

local function read_supported_value(builder, env, slot)
  local sid = slot and slot.id or 0
  local cur = env[sid]
  if cur then return cur end
  if has_bool_fact(builder.evidence, slot) and not has_i64_fact(builder.evidence, slot) then return require_kernel_bool(builder, slot) end
  if has_i64_fact(builder.evidence, slot) then return require_kernel_i64(builder, slot) end
  return add_error(builder.errors, "missing_supported_value_fact_for_slot:" .. tostring(sid))
end

local function read_truthy(builder, env, slot)
  local sid = slot and slot.id or 0
  local cur = env[sid]
  if cur then
    if cur.ty == "bool" then return cur end
    if cur.ty == "i64" then return { value = const_bool(true), ty = "bool" } end
    if cur.ty == "nil" then return { value = const_bool(false), ty = "bool" } end
    return add_error(builder.errors, "unsupported_truthy_type:" .. tostring(cur.ty) .. ":slot_" .. tostring(sid))
  end
  if has_bool_fact(builder.evidence, slot) then return require_kernel_bool(builder, slot) end
  if has_i64_fact(builder.evidence, slot) then
    builder.required_i64[sid] = true
    return { value = const_bool(true), ty = "bool" }
  end
  return add_error(builder.errors, "missing_truthy_fact_for_slot:" .. tostring(sid))
end

local function temp_place(builder, prefix)
  local id = builder.temp_id
  builder.temp_id = id + 1
  return CFG.Temp(cfg_name((prefix or "tmp") .. tostring(id)))
end

local function let_primitive(builder, ops, prefix, primop, args)
  local place = temp_place(builder, prefix)
  ops[#ops + 1] = CFG.Let(place, CFG.Primitive(primop, args or {}))
  return { value = CFG.PlaceValue(place), ty = (primop == CFG.Not or primop == CFG.Eq or primop == CFG.Lt or primop == CFG.Le) and "bool" or "i64" }
end

local function lower_instruction(builder, env, out_ops, op, prev_op)
  if op.kind == "LOADI" then
    env[op.a.id] = { value = const_i64(op.value and op.value.value or 0), ty = "i64" }
  elseif op.kind == "LOADK" then
    local v = const_i64_for_k(builder, op.k or op.rhs or op.b)
    if not v then return nil end
    env[op.a.id] = v
  elseif op.kind == "LOADTRUE" then
    env[op.a.id] = { value = const_bool(true), ty = "bool" }
  elseif op.kind == "LOADFALSE" then
    env[op.a.id] = { value = const_bool(false), ty = "bool" }
  elseif op.kind == "LOADNIL" then
    local n = math.max(1, op.count and op.count.value or 1)
    for i = 0, n - 1 do env[(op.a.id or 0) + i] = { value = const_bool(false), ty = "nil" } end
  elseif op.kind == "MOVE" then
    local v = env[op.b.id]
    if not v then
      if has_bool_fact(builder.evidence, op.b) and not has_i64_fact(builder.evidence, op.b) then v = require_kernel_bool(builder, op.b) else v = require_kernel_i64(builder, op.b) end
    end
    if not v then return nil end
    env[op.a.id] = v
  elseif op.kind == "ADDI" then
    local lhs = read_i64(builder, env, op.lhs)
    if not lhs then return nil end
    env[op.a.id] = let_primitive(builder, out_ops, "add", CFG.AddI64, { lhs.value, const_i64(op.rhs and op.rhs.value or 0) })
  elseif op.kind == "ADD" then
    local lhs, rhs = read_i64(builder, env, op.lhs), read_i64(builder, env, op.rhs)
    if not lhs or not rhs then return nil end
    env[op.a.id] = let_primitive(builder, out_ops, "add", CFG.AddI64, { lhs.value, rhs.value })
  elseif op.kind == "ADDK" then
    local lhs = read_i64(builder, env, op.lhs)
    local rhs = const_i64_for_k(builder, op.rhs)
    if not lhs or not rhs then return nil end
    env[op.a.id] = let_primitive(builder, out_ops, "add", CFG.AddI64, { lhs.value, rhs.value })
  elseif MMBIN_MARKER[op.kind] then
    if not (prev_op and ARITH_PREDECESSOR_FOR_MMBIN[prev_op.kind]) then return add_error(builder.errors, "unsupported_mmbin_without_lowered_arithmetic:" .. tostring(op.pc.id)) end
    -- Primitive-specialized arithmetic has already committed to the fast path;
    -- the PUC MMBIN companion is unreachable on that accepted path.
  else
    return add_error(builder.errors, "unsupported_instruction:" .. tostring(op.kind))
  end
  return true
end

local NUMERIC_CHOICE = {
  EQ = CFG.NumEq, LT = CFG.NumLt, LE = CFG.NumLe, EQK = CFG.NumEq,
  EQI = CFG.NumEq, LTI = CFG.NumLt, LEI = CFG.NumLe, GTI = CFG.NumGt, GEI = CFG.NumGe,
}

local function lower_condition(builder, env, out_ops, op)
  if op.kind == "TEST" or op.kind == "TESTSET" then
    local test_slot = op.kind == "TESTSET" and op.b or op.a
    local v = read_truthy(builder, env, test_slot)
    if not v then return nil end
    if op.polarity then return CFG.BoolChoice(v.value), false end
    local nv = let_primitive(builder, out_ops, "not", CFG.Not, { v.value })
    return CFG.BoolChoice(nv.value), false
  end

  local lhs = read_i64(builder, env, op.lhs)
  if not lhs then return nil end
  local rhs
  if op.kind == "EQ" or op.kind == "LT" or op.kind == "LE" then
    local rv = read_i64(builder, env, op.rhs)
    if not rv then return nil end
    rhs = rv.value
  elseif op.kind == "EQK" then
    local rv = const_i64_for_k(builder, op.rhs)
    if not rv then return nil end
    rhs = rv.value
  else
    if op.rhs_is_float then return add_error(builder.errors, "unsupported_immediate_float_origin_comparison:" .. tostring(op.pc.id)) end
    rhs = const_i64(op.rhs and op.rhs.value or 0)
  end
  local choice = CFG.NumericChoice(NUMERIC_CHOICE[op.kind], lhs.value, rhs)
  return choice, op.polarity ~= true
end

local function jump_args_for(builder, target_pc, env)
  local args = {}
  for _, sid in ipairs(sorted_keys(builder.params_by_pc[target_pc] or {})) do
    local cur = env[sid]
    if not cur then return add_error(builder.errors, "missing_jump_value_for_slot:" .. tostring(sid) .. "_to_pc_" .. tostring(target_pc)) end
    local want_ty = param_ty_for_slot(builder, sid)
    if cur.ty ~= want_ty then return add_error(builder.errors, "unsupported_jump_value_type:" .. tostring(cur.ty) .. "_to_" .. tostring(want_ty) .. ":slot_" .. tostring(sid)) end
    args[#args + 1] = CFG.Arg(cfg_name(param_name_for_block_slot(target_pc, sid)), cur.value)
  end
  return args
end

local function set_return_type(builder, ty)
  ty = ty or "void"
  if builder.return_ty and builder.return_ty ~= ty then return add_error(builder.errors, "inconsistent_return_type:" .. tostring(builder.return_ty) .. ":" .. tostring(ty)) end
  builder.return_ty = ty
  return true
end

local function lower_return(builder, env, op)
  if op.kind == "RETURN0" then
    if not set_return_type(builder, "void") then return nil end
    return CFG.Return({})
  elseif op.kind == "RETURN" then
    if op.close_upvalues or ((op.c and op.c.value or 0) ~= 0) then return add_error(builder.errors, "unsupported_return_close_or_c:" .. tostring(op.pc.id)) end
    local n = op.nresults and op.nresults.value or 0
    if n == 1 then
      if not set_return_type(builder, "void") then return nil end
      return CFG.Return({})
    elseif n ~= 2 then
      return add_error(builder.errors, "unsupported_return_count:" .. tostring(n))
    end
    local v = read_i64(builder, env, op.base)
    if not v then return nil end
    if not set_return_type(builder, v.ty) then return nil end
    return CFG.Return({ v.value })
  elseif op.kind == "RETURN1" then
    local v = env[op.value.id]
    if not v then
      if has_bool_fact(builder.evidence, op.value) and not has_i64_fact(builder.evidence, op.value) then v = require_kernel_bool(builder, op.value) else v = require_kernel_i64(builder, op.value) end
    end
    if not v then return nil end
    if v.ty ~= "i64" and v.ty ~= "bool" then return add_error(builder.errors, "unsupported_return_type:" .. tostring(v.ty)) end
    if not set_return_type(builder, v.ty) then return nil end
    return CFG.Return({ v.value })
  end
  return add_error(builder.errors, "unsupported_return:" .. tostring(op.kind))
end

local function block_params(builder, block)
  local params = {}
  for _, sid in ipairs(sorted_keys(builder.params_by_pc[block.pc] or {})) do
    local ty = param_ty_for_slot(builder, sid)
    params[#params + 1] = CFG.Param(cfg_name(param_name_for_block_slot(block.pc, sid)), type_ref(ty), CFG.ValueParam)
  end
  return params
end

local function lower_block(builder, block)
  local env = init_env_for_block(builder, block)
  local out_ops = {}
  local prev
  for _, op in ipairs(block.instrs or {}) do
    if not lower_instruction(builder, env, out_ops, op, prev) then return nil end
    prev = op
  end

  local term
  if block.term.kind == "jump" or block.term.kind == "fallthrough" then
    local args = jump_args_for(builder, block.term.target, env)
    if not args then return nil end
    term = CFG.Jump(block_ref_for_pc(block.term.target), args)
  elseif block.term.kind == "branch" then
    local branch_op = block.term.op
    local choice, swap = lower_condition(builder, env, out_ops, branch_op)
    if not choice then return nil end
    local t, f = block.term.true_target, block.term.false_target
    local true_env, false_env = env, env
    if branch_op.kind == "TESTSET" then
      local copied = read_supported_value(builder, env, branch_op.b)
      if not copied then return nil end
      true_env = {}; for k, v in pairs(env) do true_env[k] = v end
      true_env[branch_op.a.id] = copied
    end
    if swap then t, f, true_env, false_env = f, t, false_env, true_env end
    local targs = jump_args_for(builder, t, true_env)
    local fargs = jump_args_for(builder, f, false_env)
    if not targs or not fargs then return nil end
    if #targs == 0 and #fargs == 0 then
      term = CFG.Branch(choice, block_ref_for_pc(t), block_ref_for_pc(f))
    else
      term = CFG.BranchArgs(choice, block_ref_for_pc(t), targs, block_ref_for_pc(f), fargs)
    end
  elseif block.term.kind == "return" then
    term = lower_return(builder, env, block.term.op)
    if not term then return nil end
  else
    return add_error(builder.errors, "unsupported_block_terminator:" .. tostring(block.term.kind))
  end

  return CFG.Block(block_id_for_pc(block.pc), block_params(builder, block), out_ops, term)
end

local function add_fact_uses(facts, subject, predicate)
  facts[#facts + 1] = FactUse.required(subject, predicate, "", {})
  facts[#facts + 1] = FactUse.checked(subject, predicate, "", {})
end

local function contract_for(builder)
  local facts = {}
  for _, sid in ipairs(sorted_keys(builder.required_i64 or {})) do
    add_fact_uses(facts, Fact.SrcSlot(B.slot(sid)), Fact.IsI64)
  end
  for _, sid in ipairs(sorted_keys(builder.required_bool or {})) do
    add_fact_uses(facts, Fact.SrcSlot(B.slot(sid)), Fact.IsBool)
  end
  for _, kid in ipairs(sorted_keys(builder.required_const_i64 or {})) do
    add_fact_uses(facts, Fact.Const(B.k(kid)), Fact.ConstI64)
  end
  return LC.Contract(LC.Transfer(facts, {}), {}, {})
end

local function lower_value(window, evidence)
  local shape, errors = scan_shape(window)
  if not shape then return nil, errors end
  local params_by_pc, io_errors = analyze_block_io(shape)
  if not params_by_pc then return nil, io_errors end

  local builder = new_builder(evidence, params_by_pc)
  local cfg_blocks = {}
  for _, block in ipairs(shape.blocks or {}) do
    local b = lower_block(builder, block)
    if not b then return nil, builder.errors end
    cfg_blocks[#cfg_blocks + 1] = b
  end
  if #builder.errors > 0 then return nil, builder.errors end
  local return_ty = builder.return_ty or "void"
  local returns = return_ty == "void" and {} or { type_ref(return_ty) }
  local kid = CFG.KernelId(cfg_name("lua_compile_closed_kernel"))
  local rid = CFG.RegionId(cfg_name("lua_compile_closed_kernel_body"))
  local entry = block_id_for_pc(shape.blocks[1].pc)
  local region = CFG.Region(rid, builder.kernel_params, {}, entry, cfg_blocks)
  local kernel = CFG.Kernel(kid, CFG.InlineSpan, builder.kernel_params, returns, region, contract_for(builder))
  return kernel, nil
end

local phase = pvm.phase("spongejit_lua_src_to_moon_cfg_closed", function(window, evidence)
  local kernel, errors = lower_value(window, evidence)
  if not kernel then error("closed MoonCFG lower unsupported inside cached phase: " .. table.concat(errors or {}, "; ")) end
  return kernel
end)

function M.lower(window, evidence)
  local kernel, errors = lower_value(window, evidence)
  if not kernel then return nil, errors end
  return pvm.one(phase(window, evidence))
end

function M.is_candidate(window)
  local ops = (window and window.ops) or {}
  for _, op in ipairs(ops) do if CONTROL_OP[op.kind] then return true end end
  return false
end

M.phase = phase
M.lower_uncached = lower_value
M.UNSUPPORTED_CLOSED_CONTROL = UNSUPPORTED_CLOSED_CONTROL

return M
