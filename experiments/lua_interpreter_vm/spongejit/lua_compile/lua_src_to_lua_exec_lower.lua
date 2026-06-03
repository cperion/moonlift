-- lua_src_to_lua_exec_lower.lua -- LuaSrc closed core-value window -> LuaExec.
--
-- This stage makes LuaExec an executable semantic IR for the bounded core Lua
-- value slice.  It lowers source windows into LuaRT stack/value operations and
-- LuaExec CFG control first; MoonCFG is produced by lua_exec_to_moon_cfg_lower.
-- No table/metamethod/call/FFI semantics or protocol handoff are introduced.

local pvm = require("moonlift.pvm")
local B = require("lua_compile.builders")
local T = B.T
local Src, Fact, RT, Exec = T.LuaSrc, T.LuaFact, T.LuaRT, T.LuaExec

local M = {}

local CONDITION_OP = {
  EQ = true, LT = true, LE = true, EQK = true,
  EQI = true, LTI = true, LEI = true, GTI = true, GEI = true,
  TEST = true, TESTSET = true,
}
local CONTROL_OP = { JMP = true, ERRNNIL = true }
for k in pairs(CONDITION_OP) do CONTROL_OP[k] = true end
local TERMINAL_RETURN = { RETURN = true, RETURN0 = true, RETURN1 = true }
local TERMINAL_EFFECT = { SETTABLE = true }
local ARITHMETIC_OP = { ADD = RT.ArithAdd }
local MMBIN_OP = { Add = true }
local SUPPORTED_INSTR = { LOADNIL = true, LOADFALSE = true, LOADTRUE = true, LOADI = true, LOADK = true, MOVE = true, NOT = true, VARARG = true, GETVARG = true, SETLIST = true, GETTABLE = true, LEN = true, CONCAT = true, MMBIN = true }

local function ename(s) return Exec.Name(tostring(s)) end
local function rtname(s) return RT.Name(tostring(s)) end
local function pc_of(op) return op and op.pc and op.pc.id end
local function target_pc(op) return (op.pc.id or 0) + (op.offset.value or 0) + 1 end
local function frame_ref() return RT.FrameRef(rtname("frame0")) end
local function stack_ref() return RT.StackRef(frame_ref()) end
local function top_ref() return RT.TopRef(frame_ref()) end
local function slot_ref(sid) return RT.StackValue(frame_ref(), RT.Slot(tonumber(sid) or 0)) end
local function vararg_source() return RT.HiddenFrameVarargs(frame_ref(), RT.Count(0)) end
local function temp_ref(s) return RT.TempValue(rtname(s)) end
local function value_key(v)
  local cls = pvm.classof(v)
  if cls == RT.StackValue then return "stack:" .. tostring(v.frame.name.text) .. ":" .. tostring(v.slot.index) end
  if cls == RT.TempValue then return "temp:" .. tostring(v.name.text) end
  return tostring(cls) .. ":" .. tostring(v)
end
local function exec_value_name_for_slot(sid) return "slot_" .. tostring(sid) end
local function param_name_for_slot(sid, ty) return "slot_" .. tostring(sid) .. "_" .. tostring(ty) end
local function param_name_for_block_slot(pc, sid) return "pc_" .. tostring(pc) .. "_slot_" .. tostring(sid) end
local function block_id_for_pc(pc) return Exec.BlockId(ename("pc_" .. tostring(pc))) end
local function block_ref_for_pc(pc) return Exec.BlockRef(block_id_for_pc(pc)) end

local function sorted_keys(set)
  local out = {}
  for k in pairs(set or {}) do out[#out + 1] = k end
  table.sort(out)
  return out
end

local function add_error(errors, msg) errors[#errors + 1] = msg; return nil end

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
  return tonumber(f.value_key or "")
end

local function scan_shape(window)
  local ops = (window and window.ops) or {}
  if #ops == 0 then return nil, { "lua_exec:no_ops" } end
  local by_pc, has_return = {}, false
  for i, op in ipairs(ops) do
    local pc = pc_of(op)
    if not pc then return nil, { "lua_exec:op_without_pc:" .. tostring(op and op.kind) } end
    if by_pc[pc] then return nil, { "lua_exec:duplicate_pc:" .. tostring(pc) } end
    by_pc[pc] = op
    if TERMINAL_RETURN[op.kind] or TERMINAL_EFFECT[op.kind] or op.kind == "ERRNNIL" then has_return = true end
  end
  if not has_return then return nil, { "lua_exec:no_terminal_return" } end

  local leaders, consumed_jmp = { [pc_of(ops[1])] = true }, {}
  for i, op in ipairs(ops) do
    if op.kind == "JMP" then
      local target = target_pc(op)
      if not by_pc[target] then return nil, { "lua_exec:external_jump_target:" .. tostring(op.pc.id) .. "->" .. tostring(target) } end
      leaders[target] = true
      if ops[i + 1] then leaders[pc_of(ops[i + 1])] = true end
    elseif CONDITION_OP[op.kind] then
      local jmp, fall = ops[i + 1], ops[i + 2]
      if not jmp or jmp.kind ~= "JMP" then return nil, { "lua_exec:conditional_without_following_jmp:" .. tostring(op.pc.id) } end
      local target = target_pc(jmp)
      if not by_pc[target] then return nil, { "lua_exec:external_conditional_target:" .. tostring(op.pc.id) .. "->" .. tostring(target) } end
      if not fall then return nil, { "lua_exec:external_conditional_fallthrough:" .. tostring(op.pc.id) } end
      leaders[target], leaders[pc_of(fall)] = true, true
      consumed_jmp[pc_of(jmp)] = true
    elseif op.kind == "ERRNNIL" then
      local fall = ops[i + 1]
      -- PUC ERRNNIL is a runtime check: nil continues, non-nil raises.
      -- A standalone window has no in-window continuation, so synthesize an
      -- explicit normal zero-result outcome for the nil path instead of
      -- falling back to evidence/rejection.
      if fall then leaders[pc_of(fall)] = true end
    elseif ARITHMETIC_OP[op.kind] then
      local next_i = i + 1
      local companion = ops[next_i]
      if companion and companion.kind == "MMBIN" then
        if companion.op ~= Src.Add and not (companion.op and companion.op.kind == "Add") then return nil, { "lua_exec:mismatched_mmbin_companion:" .. tostring(op.pc.id) } end
        next_i = i + 2
      end
      local fall = ops[next_i]
      if not fall then return nil, { "lua_exec:arithmetic_without_following_continuation:" .. tostring(op.pc.id) } end
      leaders[pc_of(fall)] = true
    elseif TERMINAL_RETURN[op.kind] or TERMINAL_EFFECT[op.kind] then
      if ops[i + 1] then leaders[pc_of(ops[i + 1])] = true end
    elseif not SUPPORTED_INSTR[op.kind] then
      return nil, { "lua_exec:unsupported_instruction:" .. tostring(op.kind) }
    end
  end
  for pc in pairs(leaders) do if consumed_jmp[pc] then return nil, { "lua_exec:target_enters_conditional_jmp_companion:" .. tostring(pc) } end end

  local blocks, i = {}, 1
  while i <= #ops do
    local start_pc = pc_of(ops[i])
    if consumed_jmp[start_pc] then return nil, { "lua_exec:block_starts_at_consumed_jmp:" .. tostring(start_pc) } end
    if not leaders[start_pc] then return nil, { "lua_exec:internal_partition_error:" .. tostring(start_pc) } end
    local instrs, term = {}, nil
    while i <= #ops do
      local op, pc = ops[i], pc_of(ops[i])
      if consumed_jmp[pc] then return nil, { "lua_exec:consumed_jmp_reached:" .. tostring(pc) } end
      if op.kind == "JMP" then
        term = { kind = "jump", target = target_pc(op) }; i = i + 1; break
      elseif CONDITION_OP[op.kind] then
        term = { kind = "branch", op = op, true_target = target_pc(ops[i + 1]), false_target = pc_of(ops[i + 2]) }
        i = i + 2; break
      elseif op.kind == "ERRNNIL" then
        local fall = ops[i + 1]
        term = { kind = "errnnil", op = op, nil_target = fall and pc_of(fall) or "errnnil_ok_" .. tostring(op.pc.id), error_target = "errnnil_error_" .. tostring(op.pc.id) }
        i = i + 1; break
      elseif ARITHMETIC_OP[op.kind] then
        local next_i = i + 1
        local companion = ops[next_i]
        local companion_pc = nil
        if companion and companion.kind == "MMBIN" then
          if companion.op ~= Src.Add and not (companion.op and companion.op.kind == "Add") then return nil, { "lua_exec:mismatched_mmbin_companion:" .. tostring(op.pc.id) } end
          companion_pc = companion.pc and companion.pc.id
          next_i = i + 2
        end
        local fall = ops[next_i]
        term = { kind = "arithmetic", op = op, ok_target = fall and pc_of(fall), error_target = "arithmetic_error_" .. tostring(op.pc.id), companion_pc = companion_pc }
        i = next_i; break
      elseif TERMINAL_RETURN[op.kind] then
        term = { kind = "return", op = op }; i = i + 1; break
      elseif TERMINAL_EFFECT[op.kind] then
        term = { kind = "settable", op = op, ok_target = "settable_ok_" .. tostring(op.pc.id), error_target = "settable_nil_error_" .. tostring(op.pc.id) }; i = i + 1; break
      else
        instrs[#instrs + 1] = op
        local next_op = ops[i + 1]
        i = i + 1
        if next_op and leaders[pc_of(next_op)] then term = { kind = "fallthrough", target = pc_of(next_op) }; break end
      end
    end
    if not term then return nil, { "lua_exec:block_fell_out_of_window:" .. tostring(start_pc) } end
    blocks[#blocks + 1] = { pc = start_pc, instrs = instrs, term = term }
    if term.kind == "errnnil" then
      if not (ops[i] and term.nil_target == pc_of(ops[i])) then
        blocks[#blocks + 1] = { pc = term.nil_target, instrs = {}, term = { kind = "return0" } }
      end
      blocks[#blocks + 1] = { pc = term.error_target, instrs = {}, term = { kind = "error", op = term.op } }
    elseif term.kind == "arithmetic" then
      blocks[#blocks + 1] = { pc = term.error_target, instrs = {}, term = { kind = "arithmetic_error", op = term.op } }
    elseif term.kind == "settable" then
      local write_target = "settable_write_" .. tostring(term.op.pc.id)
      local raw_error_target = "settable_raw_error_" .. tostring(term.op.pc.id)
      blocks[#blocks + 1] = { pc = term.ok_target, instrs = {}, term = { kind = "settable_ok_check", op = term.op, write_target = write_target, error_target = raw_error_target } }
      blocks[#blocks + 1] = { pc = write_target, instrs = {}, term = { kind = "settable_write", op = term.op } }
      blocks[#blocks + 1] = { pc = raw_error_target, instrs = {}, term = { kind = "table_raw_set_error", op = term.op } }
      blocks[#blocks + 1] = { pc = term.error_target, instrs = {}, term = { kind = "table_key_nil_error", op = term.op } }
    end
  end
  return { ops = ops, by_pc = by_pc, leaders = leaders, blocks = blocks }, nil
end

local function slot_reads_and_defs(block)
  local reads, defs = {}, {}
  local function read_slot(slot) local sid = slot and slot.id; if sid ~= nil and not defs[sid] then reads[sid] = true end end
  local function def_slot(slot) local sid = slot and slot.id; if sid ~= nil then defs[sid] = true end end
  for _, op in ipairs(block.instrs or {}) do
    if op.kind == "MOVE" or op.kind == "NOT" then read_slot(op.b); def_slot(op.a)
    elseif ARITHMETIC_OP[op.kind] then read_slot(op.lhs); read_slot(op.rhs); def_slot(op.a)
    elseif op.kind == "GETTABLE" then read_slot(op.table); read_slot(op.key); def_slot(op.a)
    elseif op.kind == "LEN" then read_slot(op.b); def_slot(op.a)
    elseif op.kind == "CONCAT" then read_slot(op.first); read_slot(op.last); def_slot(op.a)
    elseif op.kind == "LOADI" or op.kind == "LOADK" or op.kind == "LOADTRUE" or op.kind == "LOADFALSE" then def_slot(op.a)
    elseif op.kind == "LOADNIL" then
      local n = math.max(1, op.count and op.count.value or 1)
      for i = 0, n - 1 do defs[(op.a.id or 0) + i] = true end
    elseif op.kind == "VARARG" then
      local wanted = op.wanted and op.wanted.value or 0
      if op.uses_vararg_table then return nil, nil, "lua_exec:unsupported_vararg_table_mode_until_table_model" end
      if wanted == 0 then def_slot(op.a) else for i = 0, math.max(0, wanted - 2) do defs[(op.a.id or 0) + i] = true end end
    elseif op.kind == "GETVARG" then read_slot(op.index); def_slot(op.a)
    elseif op.kind == "SETLIST" then
      if (op.narray and op.narray.value or 0) == 0 then defs[-100000 - (op.table and op.table.id or 0)] = true end
    else return nil, nil, "lua_exec:unsupported_instruction:" .. tostring(op.kind) end
  end
  local term = block.term
  if term.kind == "return" then
    local op = term.op
    if op.kind == "RETURN1" then read_slot(op.value)
    elseif op.kind == "RETURN" then
      if op.close_upvalues or ((op.c and op.c.value or 0) ~= 0) then return nil, nil, "lua_exec:unsupported_return_close_or_c:" .. tostring(op.pc.id) end
      local n = op.nresults and op.nresults.value or 0
      if n == 0 then defs[-200000] = true elseif n == 2 then read_slot(op.base) elseif n == 1 then -- RETURN with B=1 returns zero values.
      elseif n > 2 then for i = 0, n - 2 do read_slot(B.slot((op.base.id or 0) + i)) end else return nil, nil, "lua_exec:unsupported_return_count:" .. tostring(n) end
    end
  elseif term.kind == "settable" then
    local op = term.op
    if op.kind == "SETTABLE" then read_slot(op.table); read_slot(op.key); if op.value and op.value.kind == "R" then read_slot(op.value.slot) end end
  elseif term.kind == "settable_ok_check" then
    local op = term.op
    read_slot(op.table); read_slot(op.key); if op.value and op.value.kind == "R" then read_slot(op.value.slot) end
  elseif term.kind == "table_key_nil_error" then
    read_slot(term.op.key)
  elseif term.kind == "settable_write" then
    local op = term.op
    read_slot(op.table); read_slot(op.key); if op.value and op.value.kind == "R" then read_slot(op.value.slot) end
  elseif term.kind == "table_raw_set_error" then
    read_slot(term.op.table)
  elseif term.kind == "return0" then
    -- no values
  elseif term.kind == "branch" then
    local op = term.op
    if op.kind == "TEST" then read_slot(op.a)
    elseif op.kind == "TESTSET" then read_slot(op.b)
    elseif op.kind == "EQK" then read_slot(op.lhs)
    elseif op.lhs then read_slot(op.lhs); if op.rhs and op.rhs.id ~= nil then read_slot(op.rhs) end end
  elseif term.kind == "arithmetic" then
    read_slot(term.op.lhs); read_slot(term.op.rhs)
  elseif term.kind == "arithmetic_error" then
    read_slot(term.op.lhs); read_slot(term.op.rhs)
  elseif term.kind == "errnnil" or term.kind == "error" then
    read_slot(term.op.a)
  end
  return reads, defs, nil
end

local function analyze_block_io(shape)
  local by_pc, edge_targets = {}, {}
  for _, block in ipairs(shape.blocks or {}) do by_pc[block.pc] = block end
  for _, block in ipairs(shape.blocks or {}) do
    local reads, defs, err = slot_reads_and_defs(block)
    if err then return nil, { err } end
    block.use_before_def, block.defs = reads, defs
    local term = block.term
    if term.kind == "jump" or term.kind == "fallthrough" then edge_targets[term.target] = true
    elseif term.kind == "branch" then edge_targets[term.true_target] = true; edge_targets[term.false_target] = true
    elseif term.kind == "errnnil" then edge_targets[term.nil_target] = true; edge_targets[term.error_target] = true
    elseif term.kind == "arithmetic" then edge_targets[term.ok_target] = true; edge_targets[term.error_target] = true
    elseif term.kind == "settable" then edge_targets[term.ok_target] = true; edge_targets[term.error_target] = true
    elseif term.kind == "settable_ok_check" then edge_targets[term.write_target] = true; edge_targets[term.error_target] = true end
  end
  local params_by_pc = {}
  for pc in pairs(edge_targets) do
    if not by_pc[pc] then return nil, { "lua_exec:unresolved_edge_target:" .. tostring(pc) } end
    params_by_pc[pc] = {}
    for sid in pairs(by_pc[pc].use_before_def or {}) do params_by_pc[pc][sid] = true end
  end
  return params_by_pc, nil
end

local function new_builder(evidence, params_by_pc)
  return { evidence = evidence, params_by_pc = params_by_pc or {}, forced_slot_ty = {}, kernel_params = {}, kernel_param_seen = {}, errors = {}, temp_id = 1 }
end
local function slot_ty(builder, sid)
  local s = B.slot(sid)
  if has_bool_fact(builder.evidence, s) and not has_i64_fact(builder.evidence, s) then return "bool" end
  if has_i64_fact(builder.evidence, s) then return "i64" end
  return "i64"
end
local function slot_ty_for_pc(builder, pc, sid)
  local pcs = tostring(pc)
  local forced = builder.forced_slot_ty and builder.forced_slot_ty[pc] and builder.forced_slot_ty[pc][sid]
  if forced then return forced end
  if pcs:match("^errnnil_error_") or pcs:match("^arithmetic_error_") or pcs:match("^settable_") then return "lua_value" end
  return slot_ty(builder, sid)
end
local function exec_type_for_external_scalar(ty)
  if ty == "i64" then return Exec.MoonType("i64") end
  if ty == "bool" then return Exec.MoonType("bool") end
  if ty == "f64" then return Exec.MoonType("f64") end
  if ty == "lua_i64_value" then return Exec.LuaValueWithTagType(RT.IntegerTag) end
  if ty == "lua_value" then return Exec.LuaValueType end
  if ty == "ptr_lua_value" then return Exec.MoonType("ptr(LuaRTValue)") end
  if ty == "ptr_i64" then return Exec.MoonType("ptr(i64)") end
  if ty == "ptr_lua_table" then return Exec.MoonType("ptr(LuaRTTable)") end
  if ty == "ptr_lua_string" then return Exec.MoonType("ptr(LuaRTString)") end
  return Exec.LuaValueType
end
local function exec_value_type_for_slot_ty(ty)
  if ty == "i64" then return Exec.LuaValueWithTagType(RT.IntegerTag) end
  if ty == "bool" then return Exec.LuaValueWithTypeTestType(RT.IsBoolean) end
  if ty == "nil" then return Exec.LuaValueWithTagType(RT.NilTag) end
  if ty == "f64" then return Exec.LuaValueWithTagType(RT.FloatTag) end
  if ty == "lua_i64_value" then return Exec.LuaValueWithTagType(RT.IntegerTag) end
  if ty == "lua_value" then return Exec.LuaValueType end
  return Exec.LuaValueType
end
local function require_param(builder, sid, ty)
  local pname = param_name_for_slot(sid, ty)
  if not builder.kernel_param_seen[pname] then
    builder.kernel_param_seen[pname] = true
    builder.kernel_params[#builder.kernel_params + 1] = Exec.Param(ename(pname), exec_type_for_external_scalar(ty))
  end
  return Exec.TempValue(ename(pname)), ty
end
local function require_external(builder, sid)
  local s = B.slot(sid)
  if has_bool_fact(builder.evidence, s) and not has_i64_fact(builder.evidence, s) then return require_param(builder, sid, "bool") end
  if has_i64_fact(builder.evidence, s) then return require_param(builder, sid, "i64") end
  return require_param(builder, sid, "lua_value")
end
local function require_named_param(builder, name, ty)
  if not builder.kernel_param_seen[name] then
    builder.kernel_param_seen[name] = true
    builder.kernel_params[#builder.kernel_params + 1] = Exec.Param(ename(name), exec_type_for_external_scalar(ty))
  end
  return Exec.TempValue(ename(name)), ty
end
local function require_stack_params(builder)
  require_named_param(builder, "frame0_stack", "ptr_lua_value")
  require_named_param(builder, "frame0_top_ptr", "ptr_i64")
end
local function require_vararg_params(builder)
  require_named_param(builder, "frame0_varargs", "ptr_lua_value")
  require_named_param(builder, "frame0_vararg_count", "i64")
end
local function require_strings_params(builder)
  require_named_param(builder, "frame0_strings", "ptr_lua_string")
end
local function require_object_params(builder)
  require_named_param(builder, "frame0_tables", "ptr_lua_table")
  require_strings_params(builder)
end
local function const_i64_for_k(builder, k)
  local v = const_i64_fact(builder.evidence, k)
  if v == nil then return add_error(builder.errors, "lua_exec:missing_const_i64_fact_for_k:" .. tostring(k and k.id or k)) end
  return Exec.ConstTValue(RT.IntValue(v)), "i64"
end
local function bind_slot(builder, ops, env, sid)
  if env[sid] then return true end
  local v, ty = require_external(builder, sid)
  if not v then return nil end
  ops[#ops + 1] = Exec.AssignValue(slot_ref(sid), v)
  env[sid] = ty
  return true
end
local function temp_name(builder, prefix)
  local id = builder.temp_id; builder.temp_id = id + 1
  return (prefix or "tmp") .. tostring(id)
end
local function tvalue_for(ty, value)
  if ty == "i64" then return RT.IntValue(value or 0) end
  if ty == "bool" then return RT.BoolValue(value and RT.LuaTrue or RT.LuaFalse) end
  if ty == "nil" then return RT.NilValue(RT.OrdinaryNil) end
  error("unsupported core tvalue type: " .. tostring(ty))
end

local function lower_instruction(builder, env, ops, op)
  local sid = op.a and op.a.id
  if op.kind == "LOADI" then
    ops[#ops + 1] = Exec.AssignValue(slot_ref(sid), Exec.ConstTValue(RT.IntValue(op.value and op.value.value or 0)))
    env[sid] = "i64"
  elseif op.kind == "LOADK" then
    local v, ty = const_i64_for_k(builder, op.k)
    if not v then return nil end
    ops[#ops + 1] = Exec.AssignValue(slot_ref(sid), v); env[sid] = ty
  elseif op.kind == "LOADTRUE" then
    ops[#ops + 1] = Exec.AssignValue(slot_ref(sid), Exec.ConstTValue(RT.BoolValue(RT.LuaTrue))); env[sid] = "bool"
  elseif op.kind == "LOADFALSE" then
    ops[#ops + 1] = Exec.AssignValue(slot_ref(sid), Exec.ConstTValue(RT.BoolValue(RT.LuaFalse))); env[sid] = "bool"
  elseif op.kind == "LOADNIL" then
    local n = math.max(1, op.count and op.count.value or 1)
    for i = 0, n - 1 do
      local dsid = (op.a.id or 0) + i
      ops[#ops + 1] = Exec.AssignValue(slot_ref(dsid), Exec.ConstTValue(RT.NilValue(RT.OrdinaryNil)))
      env[dsid] = "nil"
    end
  elseif op.kind == "MOVE" then
    if not bind_slot(builder, ops, env, op.b.id) then return nil end
    ops[#ops + 1] = Exec.AssignValue(slot_ref(sid), Exec.RuntimeValue(slot_ref(op.b.id)))
    env[sid] = env[op.b.id]
  elseif op.kind == "NOT" then
    if not bind_slot(builder, ops, env, op.b.id) then return nil end
    local tmp = temp_name(builder, "not")
    ops[#ops + 1] = Exec.Let(ename(tmp), Exec.NotTruthinessExpr(slot_ref(op.b.id)))
    ops[#ops + 1] = Exec.AssignValue(slot_ref(sid), Exec.TempValue(ename(tmp)))
    env[sid] = "bool"
  elseif op.kind == "VARARG" then
    if op.uses_vararg_table then return add_error(builder.errors, "lua_exec:unsupported_vararg_table_mode_until_table_model") end
    require_stack_params(builder); require_vararg_params(builder)
    local wanted = op.wanted and op.wanted.value or 0
    local count_spec = wanted == 0 and RT.OpenFromVarargs(vararg_source()) or RT.FixedCount(math.max(0, wanted - 1))
    local seq = RT.ValueSeq(RT.VarargSeq, {}, count_spec, RT.FromVarargs(vararg_source()))
    local dst_window = RT.StackWindow(RT.VarargWindow, frame_ref(), RT.Slot(op.a.id or 0), count_spec)
    ops[#ops + 1] = Exec.AssignSeq(dst_window, seq, wanted == 0 and RT.PropagateOpenTail or RT.ExactCount(RT.Count(math.max(0, wanted - 1))))
    if wanted == 0 then
      ops[#ops + 1] = Exec.SetTop(top_ref(), RT.OpenFromVarargsAtBase(RT.Slot(op.a.id or 0), vararg_source()))
      env.__open_top_base = op.a.id or 0
    else
      for i = 0, math.max(0, wanted - 2) do env[(op.a.id or 0) + i] = "lua_value" end
    end
  elseif op.kind == "GETVARG" then
    require_vararg_params(builder)
    if not bind_slot(builder, ops, env, op.index.id) then return nil end
    local tmp = temp_name(builder, "getvarg")
    ops[#ops + 1] = Exec.Let(ename(tmp), Exec.VarargAccessExpr(RT.VarargIndex(vararg_source(), slot_ref(op.index.id))))
    ops[#ops + 1] = Exec.AssignValue(slot_ref(op.a.id), Exec.TempValue(ename(tmp)))
    env[op.a.id] = "lua_value"
  elseif op.kind == "GETTABLE" then
    require_object_params(builder)
    if not bind_slot(builder, ops, env, op.table.id) then return nil end
    if not bind_slot(builder, ops, env, op.key.id) then return nil end
    local raw = temp_name(builder, "rawget")
    ops[#ops + 1] = Exec.Let(ename(raw), Exec.TableRawGetExpr(slot_ref(op.table.id), slot_ref(op.key.id)))
    local val = temp_name(builder, "gettable")
    ops[#ops + 1] = Exec.Let(ename(val), Exec.TableRawGetValueOrNilExpr(Exec.TempValue(ename(raw))))
    ops[#ops + 1] = Exec.AssignValue(slot_ref(op.a.id), Exec.TempValue(ename(val)))
    env[op.a.id] = "lua_value"
  elseif op.kind == "LEN" then
    require_object_params(builder)
    if not bind_slot(builder, ops, env, op.b.id) then return nil end
    local tmp = temp_name(builder, "len")
    ops[#ops + 1] = Exec.Let(ename(tmp), Exec.LenNoMetaExpr(slot_ref(op.b.id)))
    ops[#ops + 1] = Exec.AssignValue(slot_ref(op.a.id), Exec.TempValue(ename(tmp)))
    env[op.a.id] = "i64"
  elseif op.kind == "CONCAT" then
    require_object_params(builder)
    if (op.last.id or 0) ~= (op.first.id or 0) + 1 then return add_error(builder.errors, "lua_exec:concat_currently_requires_two_operands_for_explicit_string_handle_model") end
    if not bind_slot(builder, ops, env, op.first.id) then return nil end
    if not bind_slot(builder, ops, env, op.last.id) then return nil end
    local tmp = temp_name(builder, "concat")
    ops[#ops + 1] = Exec.Let(ename(tmp), Exec.StringConcat2Expr(slot_ref(op.first.id), slot_ref(op.last.id)))
    ops[#ops + 1] = Exec.AssignValue(slot_ref(op.a.id), Exec.TempValue(ename(tmp)))
    env[op.a.id] = "lua_value"
  elseif op.kind == "SETLIST" then
    if (op.narray and op.narray.value or 0) == 0 then
      require_stack_params(builder)
      local count_spec = RT.OpenFromTop(top_ref())
      local window = RT.StackWindow(RT.ConstructorWindow, frame_ref(), RT.Slot((op.table.id or 0) + 1), count_spec)
      local seq = RT.ValueSeq(RT.OpenSeq, {}, count_spec, RT.FromStackWindow(window))
      ops[#ops + 1] = Exec.Let(ename(temp_name(builder, "setlist_values")), Exec.ValueSeqExpr(seq))
      -- Table writes remain future; this consumes/builds the open sequence model
      -- without pretending table mutation semantics are implemented.
    else
      return add_error(builder.errors, "lua_exec:setlist_table_write_semantics_future")
    end
  else
    return add_error(builder.errors, "lua_exec:unsupported_instruction:" .. tostring(op.kind))
  end
  return true
end

local NUMERIC_TEST = { EQ = Exec.Eq, LT = Exec.Lt, LE = Exec.Le, EQK = Exec.Eq, EQI = Exec.Eq, LTI = Exec.Lt, LEI = Exec.Le, GTI = Exec.Gt, GEI = Exec.Ge }
local function rk_value_ref(builder, env, ops, rk)
  local cls = pvm.classof(rk)
  if cls == Src.R then
    if not bind_slot(builder, ops, env, rk.slot.id) then return nil end
    return slot_ref(rk.slot.id), env[rk.slot.id]
  elseif cls == Src.K then
    local v, ty = const_i64_for_k(builder, rk.k)
    if not v then return nil end
    local tmp = temp_ref("const_set_k_" .. tostring(rk.k.id))
    ops[#ops + 1] = Exec.AssignValue(tmp, v)
    return tmp, ty
  end
  return add_error(builder.errors, "lua_exec:unsupported_rk_value:" .. tostring(rk and rk.kind))
end

local function lower_condition(builder, env, ops, op)
  if op.kind == "TEST" or op.kind == "TESTSET" then
    local test_slot = op.kind == "TESTSET" and op.b or op.a
    if not bind_slot(builder, ops, env, test_slot.id) then return nil end
    return Exec.TruthinessChoice(slot_ref(test_slot.id)), op.polarity ~= true
  end
  if not bind_slot(builder, ops, env, op.lhs.id) then return nil end
  local rhs_ref
  if op.kind == "EQ" or op.kind == "LT" or op.kind == "LE" then
    if not bind_slot(builder, ops, env, op.rhs.id) then return nil end
    rhs_ref = slot_ref(op.rhs.id)
  elseif op.kind == "EQK" then
    local v, ty = const_i64_for_k(builder, op.rhs)
    if not v then return nil end
    local tmp = temp_ref("const_k_" .. tostring(op.rhs.id))
    ops[#ops + 1] = Exec.AssignValue(tmp, v)
    rhs_ref = tmp
  else
    if op.rhs_is_float then return add_error(builder.errors, "lua_exec:unsupported_immediate_float_origin_comparison:" .. tostring(op.pc.id)) end
    local tmp = temp_ref("imm_" .. tostring(op.pc.id))
    ops[#ops + 1] = Exec.AssignValue(tmp, Exec.ConstTValue(RT.IntValue(op.rhs and op.rhs.value or 0)))
    rhs_ref = tmp
  end
  return Exec.NumericChoice(NUMERIC_TEST[op.kind], slot_ref(op.lhs.id), rhs_ref), op.polarity ~= true
end

local function init_env_for_block(builder, block, ops)
  local env = {}
  for _, sid in ipairs(sorted_keys(builder.params_by_pc[block.pc] or {})) do
    local ty = slot_ty_for_pc(builder, block.pc, sid)
    local pname = param_name_for_block_slot(block.pc, sid)
    ops[#ops + 1] = Exec.AssignValue(slot_ref(sid), Exec.TempValue(ename(pname)))
    env[sid] = ty
  end
  return env
end
local function block_params(builder, block)
  local params = {}
  for _, sid in ipairs(sorted_keys(builder.params_by_pc[block.pc] or {})) do
    params[#params + 1] = Exec.Param(ename(param_name_for_block_slot(block.pc, sid)), exec_value_type_for_slot_ty(slot_ty_for_pc(builder, block.pc, sid)))
  end
  return params
end
local function jump_args_for(builder, target_pc, env, overrides)
  local args = {}
  overrides = overrides or {}
  for _, sid in ipairs(sorted_keys(builder.params_by_pc[target_pc] or {})) do
    local ty = env[sid]
    if not ty then return add_error(builder.errors, "lua_exec:missing_jump_value_for_slot:" .. tostring(sid) .. "_to_pc_" .. tostring(target_pc)) end
    local want = slot_ty_for_pc(builder, target_pc, sid)
    if want ~= "lua_value" and ty ~= want then return add_error(builder.errors, "lua_exec:unsupported_jump_value_type:" .. tostring(ty) .. "_to_" .. tostring(want) .. ":slot_" .. tostring(sid)) end
    args[#args + 1] = Exec.Arg(ename(param_name_for_block_slot(target_pc, sid)), overrides[sid] or Exec.RuntimeValue(slot_ref(sid)))
  end
  return args
end
local function copy_env(env) local out = {}; for k, v in pairs(env) do out[k] = v end; return out end

local function return_seq_for(builder, env, ops, op)
  if op.kind == "RETURN0" then
    return RT.ValueSeq(RT.FixedSeq, {}, RT.FixedCount(0), RT.FromLiteralValues)
  elseif op.kind == "RETURN" then
    if op.close_upvalues or ((op.c and op.c.value or 0) ~= 0) then return add_error(builder.errors, "lua_exec:unsupported_return_close_or_c:" .. tostring(op.pc.id)) end
    local n = op.nresults and op.nresults.value or 0
    if n == 0 then
      require_stack_params(builder)
      local count = RT.OpenFromTop(top_ref())
      local window = RT.StackWindow(RT.ReturnWindow, frame_ref(), RT.Slot(op.base.id), count)
      return RT.ValueSeq(RT.OpenSeq, {}, count, RT.FromStackWindow(window))
    end
    if n == 1 then return RT.ValueSeq(RT.FixedSeq, {}, RT.FixedCount(0), RT.FromLiteralValues) end
    if n > 2 then
      for i = 0, n - 2 do if not bind_slot(builder, ops, env, (op.base.id or 0) + i) then return nil end end
      local refs = {}
      for i = 0, n - 2 do refs[#refs + 1] = slot_ref((op.base.id or 0) + i) end
      local window = RT.StackWindow(RT.ReturnWindow, frame_ref(), RT.Slot(op.base.id), RT.FixedCount(n - 1))
      return RT.ValueSeq(RT.FixedSeq, refs, RT.FixedCount(n - 1), RT.FromStackWindow(window))
    end
    if not bind_slot(builder, ops, env, op.base.id) then return nil end
    local window = RT.StackWindow(RT.ReturnWindow, frame_ref(), RT.Slot(op.base.id), RT.FixedCount(1))
    return RT.ValueSeq(RT.FixedSeq, { slot_ref(op.base.id) }, RT.FixedCount(1), RT.FromStackWindow(window))
  elseif op.kind == "RETURN1" then
    if not bind_slot(builder, ops, env, op.value.id) then return nil end
    local window = RT.StackWindow(RT.ReturnWindow, frame_ref(), RT.Slot(op.value.id), RT.FixedCount(1))
    return RT.ValueSeq(RT.FixedSeq, { slot_ref(op.value.id) }, RT.FixedCount(1), RT.FromStackWindow(window))
  end
  return add_error(builder.errors, "lua_exec:unsupported_return:" .. tostring(op.kind))
end

local function lower_block(builder, block)
  local ops = {}
  local env = init_env_for_block(builder, block, ops)
  for _, op in ipairs(block.instrs or {}) do if not lower_instruction(builder, env, ops, op) then return nil end end
  local term
  if block.term.kind == "jump" or block.term.kind == "fallthrough" then
    local args = jump_args_for(builder, block.term.target, env); if not args then return nil end
    term = Exec.Jump(block_ref_for_pc(block.term.target), args)
  elseif block.term.kind == "branch" then
    local choice, swap = lower_condition(builder, env, ops, block.term.op); if not choice then return nil end
    local t, f = block.term.true_target, block.term.false_target
    local true_env, false_env = env, env
    local true_overrides, false_overrides = {}, {}
    if block.term.op.kind == "TESTSET" then
      if not bind_slot(builder, ops, env, block.term.op.b.id) then return nil end
      true_env = copy_env(env)
      true_env[block.term.op.a.id] = env[block.term.op.b.id]
      true_overrides[block.term.op.a.id] = Exec.RuntimeValue(slot_ref(block.term.op.b.id))
    end
    if swap then t, f, true_env, false_env, true_overrides, false_overrides = f, t, false_env, true_env, false_overrides, true_overrides end
    local targs = jump_args_for(builder, t, true_env, true_overrides); local fargs = jump_args_for(builder, f, false_env, false_overrides)
    if not targs or not fargs then return nil end
    if #targs == 0 and #fargs == 0 then term = Exec.Branch(choice, block_ref_for_pc(t), block_ref_for_pc(f))
    else term = Exec.BranchArgs(choice, block_ref_for_pc(t), targs, block_ref_for_pc(f), fargs) end
  elseif block.term.kind == "errnnil" then
    local op = block.term.op
    if not bind_slot(builder, ops, env, op.a.id) then return nil end
    local choice = Exec.TypeChoice(slot_ref(op.a.id), RT.IsNil)
    local nil_args = jump_args_for(builder, block.term.nil_target, env)
    local err_args = jump_args_for(builder, block.term.error_target, env)
    if not nil_args or not err_args then return nil end
    if #nil_args == 0 and #err_args == 0 then term = Exec.Branch(choice, block_ref_for_pc(block.term.nil_target), block_ref_for_pc(block.term.error_target))
    else term = Exec.BranchArgs(choice, block_ref_for_pc(block.term.nil_target), nil_args, block_ref_for_pc(block.term.error_target), err_args) end
  elseif block.term.kind == "arithmetic" then
    local op = block.term.op
    require_strings_params(builder)
    if not bind_slot(builder, ops, env, op.lhs.id) then return nil end
    if not bind_slot(builder, ops, env, op.rhs.id) then return nil end
    local tmp = temp_name(builder, "arith_add")
    ops[#ops + 1] = Exec.Let(ename(tmp), Exec.ArithmeticNoMetaExpr(RT.ArithAdd, slot_ref(op.lhs.id), slot_ref(op.rhs.id)))
    local choice = Exec.ArithmeticNumericChoice(RT.ArithAdd, slot_ref(op.lhs.id), slot_ref(op.rhs.id))
    local result_ty = (env[op.lhs.id] == "i64" and env[op.rhs.id] == "i64") and "lua_i64_value" or "lua_value"
    builder.forced_slot_ty[block.term.ok_target] = builder.forced_slot_ty[block.term.ok_target] or {}
    builder.forced_slot_ty[block.term.ok_target][op.a.id] = result_ty
    local ok_env = copy_env(env)
    ok_env[op.a.id] = result_ty
    local ok_overrides = { [op.a.id] = Exec.TempValue(ename(tmp)) }
    local ok_args = jump_args_for(builder, block.term.ok_target, ok_env, ok_overrides)
    local err_args = jump_args_for(builder, block.term.error_target, env)
    if not ok_args or not err_args then return nil end
    term = Exec.BranchArgs(choice, block_ref_for_pc(block.term.ok_target), ok_args, block_ref_for_pc(block.term.error_target), err_args)
  elseif block.term.kind == "arithmetic_error" then
    local op = block.term.op
    require_strings_params(builder)
    if not bind_slot(builder, ops, env, op.lhs.id) then return nil end
    if not bind_slot(builder, ops, env, op.rhs.id) then return nil end
    local tmp = temp_name(builder, "arith_error_value")
    local err_ref = temp_ref(tmp .. "_ref")
    ops[#ops + 1] = Exec.Let(ename(tmp), Exec.ArithmeticErrorValueExpr(RT.ArithAdd, slot_ref(op.lhs.id), slot_ref(op.rhs.id)))
    ops[#ops + 1] = Exec.AssignValue(err_ref, Exec.TempValue(ename(tmp)))
    term = Exec.Error(RT.ErrorState(RT.ArithmeticError, err_ref, RT.Pc(op.pc.id or 0), top_ref()))
  elseif block.term.kind == "error" then
    local op = block.term.op
    if not bind_slot(builder, ops, env, op.a.id) then return nil end
    term = Exec.Error(RT.ErrorState(RT.ErrNnilError, slot_ref(op.a.id), RT.Pc(op.pc.id or 0), top_ref()))
  elseif block.term.kind == "settable" then
    local op = block.term.op
    require_object_params(builder)
    if not bind_slot(builder, ops, env, op.table.id) then return nil end
    if not bind_slot(builder, ops, env, op.key.id) then return nil end
    if not rk_value_ref(builder, env, ops, op.value) then return nil end
    local choice = Exec.TypeChoice(slot_ref(op.key.id), RT.IsNil)
    local err_args = jump_args_for(builder, block.term.error_target, env)
    local ok_args = jump_args_for(builder, block.term.ok_target, env)
    if not err_args or not ok_args then return nil end
    term = Exec.BranchArgs(choice, block_ref_for_pc(block.term.error_target), err_args, block_ref_for_pc(block.term.ok_target), ok_args)
  elseif block.term.kind == "table_key_nil_error" then
    local op = block.term.op
    if not bind_slot(builder, ops, env, op.key.id) then return nil end
    term = Exec.Error(RT.ErrorState(RT.TableIndexNilError, slot_ref(op.key.id), RT.Pc(op.pc.id or 0), top_ref()))
  elseif block.term.kind == "settable_ok_check" then
    local op = block.term.op
    require_object_params(builder)
    if not bind_slot(builder, ops, env, op.table.id) then return nil end
    if not bind_slot(builder, ops, env, op.key.id) then return nil end
    if not rk_value_ref(builder, env, ops, op.value) then return nil end
    local tmp = temp_name(builder, "rawset_can_write")
    ops[#ops + 1] = Exec.Let(ename(tmp), Exec.TableRawSetCanWriteExpr(slot_ref(op.table.id), slot_ref(op.key.id)))
    local choice = Exec.BoolChoice(Exec.TempValue(ename(tmp)))
    local wargs = jump_args_for(builder, block.term.write_target, env)
    local eargs = jump_args_for(builder, block.term.error_target, env)
    if not wargs or not eargs then return nil end
    term = Exec.BranchArgs(choice, block_ref_for_pc(block.term.write_target), wargs, block_ref_for_pc(block.term.error_target), eargs)
  elseif block.term.kind == "settable_write" then
    local op = block.term.op
    require_object_params(builder)
    if not bind_slot(builder, ops, env, op.table.id) then return nil end
    if not bind_slot(builder, ops, env, op.key.id) then return nil end
    local value_ref = rk_value_ref(builder, env, ops, op.value); if not value_ref then return nil end
    ops[#ops + 1] = Exec.TableRawSet(slot_ref(op.table.id), slot_ref(op.key.id), value_ref)
    ops[#ops + 1] = Exec.TableWriteBarrier(slot_ref(op.table.id), value_ref)
    term = Exec.Return(RT.ValueSeq(RT.FixedSeq, {}, RT.FixedCount(0), RT.FromLiteralValues))
  elseif block.term.kind == "table_raw_set_error" then
    local op = block.term.op
    if not bind_slot(builder, ops, env, op.table.id) then return nil end
    term = Exec.Error(RT.ErrorState(RT.RuntimeError, slot_ref(op.table.id), RT.Pc(op.pc.id or 0), top_ref()))
  elseif block.term.kind == "return0" then
    term = Exec.Return(RT.ValueSeq(RT.FixedSeq, {}, RT.FixedCount(0), RT.FromLiteralValues))
  elseif block.term.kind == "return" then
    local seq = return_seq_for(builder, env, ops, block.term.op); if not seq then return nil end
    term = Exec.Return(seq)
  else return add_error(builder.errors, "lua_exec:unsupported_block_terminator:" .. tostring(block.term.kind)) end
  return Exec.Block(block_id_for_pc(block.pc), block_params(builder, block), ops, term)
end

local function make_frame(entry_pc)
  local fr = frame_ref()
  return RT.Frame(fr, stack_ref(), top_ref(), vararg_source(), RT.CloseChain(fr, {}), RT.Pc(entry_pc or 0))
end
local function empty_contract() return Exec.Contract({}, {}) end

local function lower_value(window, evidence)
  local raw_ops = (window and window.ops) or {}
  for i, op in ipairs(raw_ops) do
    if ARITHMETIC_OP[op.kind] and has_i64_fact(evidence, op.lhs) and has_i64_fact(evidence, op.rhs)
        and not (raw_ops[i + 1] and raw_ops[i + 1].kind == "MMBIN") then
      return nil, { "lua_exec:proven_i64_arithmetic_owned_by_closed_moon_cfg:" .. tostring(op.pc and op.pc.id) }
    end
  end
  local shape, errors = scan_shape(window); if not shape then return nil, errors end
  local params_by_pc, io_errors = analyze_block_io(shape); if not params_by_pc then return nil, io_errors end
  local builder = new_builder(evidence, params_by_pc)
  local blocks = {}
  for _, block in ipairs(shape.blocks or {}) do
    local b = lower_block(builder, block)
    if not b then return nil, builder.errors end
    blocks[#blocks + 1] = b
  end
  if #builder.errors > 0 then return nil, builder.errors end
  local entry = block_id_for_pc(shape.blocks[1].pc)
  local region = Exec.Region(ename("lua_exec_core_body"), Exec.ReturnRegion, builder.kernel_params, {}, entry, blocks)
  return Exec.Kernel(ename("lua_exec_core_kernel"), make_frame(shape.blocks[1].pc), region, empty_contract()), nil
end

local phase = pvm.phase("spongejit_lua_src_to_lua_exec_lower", function(window, evidence)
  local kernel, errors = lower_value(window, evidence)
  if not kernel then error("LuaExec lower unsupported inside cached phase: " .. table.concat(errors or {}, "; ")) end
  return kernel
end)

function M.lower(window, evidence)
  local kernel, errors = lower_value(window, evidence)
  if not kernel then return nil, errors end
  return pvm.one(phase(window, evidence))
end

function M.is_candidate(window, evidence)
  return lower_value(window, evidence or B.empty_evidence()) ~= nil
end

M.phase = phase
M.lower_uncached = lower_value

return M
