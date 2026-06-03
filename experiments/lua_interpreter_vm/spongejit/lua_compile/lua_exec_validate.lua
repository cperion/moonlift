-- lua_compile/lua_exec_validate.lua -- structural checks for LuaExec semantic CFG.
--
-- LuaExec regions are semantic ASDL CFG fragments. Validation here stays
-- structural and fail-closed; it does not interpret Lua opcodes or call helpers.

local Schema = require("lua_compile.schema")
local pvm = require("moonlift.pvm")
local T = Schema.get()
local RT, Exec = T.LuaRT, T.LuaExec
local LuaRTValidate = require("lua_compile.lua_rt_validate")
local ValueModel = require("lua_compile.lua_rt_value_model")

local M = {}

local function add(errors, msg) errors[#errors + 1] = msg end
local function cls(v) return pvm.classof(v) end
local function is_member(sum, v)
  return v ~= nil and sum and sum.members and sum.members[cls(v)] or false
end
local function name_text(name)
  return name and name.text or "<nil>"
end
local function block_key(block_id)
  return block_id and block_id.name and block_id.name.text or nil
end
local function block_ref_key(ref)
  return ref and ref.id and ref.id.name and ref.id.name.text or nil
end

local function validate_param(param, errors, label)
  if cls(param) ~= Exec.Param then
    add(errors, label .. " must be LuaExec.Param")
    return
  end
  if cls(param.name) ~= Exec.Name then add(errors, label .. ".name must be LuaExec.Name") end
  if not is_member(Exec.Type, param.type) then add(errors, label .. ".type must be LuaExec.Type") end
end

local function validate_args(args, errors, label)
  for i, arg in ipairs(args or {}) do
    if cls(arg) ~= Exec.Arg then
      add(errors, label .. " arg " .. i .. " must be LuaExec.Arg")
    else
      if cls(arg.name) ~= Exec.Name then add(errors, label .. " arg " .. i .. ".name must be LuaExec.Name") end
      if not is_member(Exec.Value, arg.value) then add(errors, label .. " arg " .. i .. ".value must be LuaExec.Value") end
    end
  end
end

local function validate_expr(expr, errors, label)
  if not is_member(Exec.Expr, expr) then add(errors, label .. " expr must be LuaExec.Expr"); return end
  local c = cls(expr)
  if c == Exec.TypeTestExpr then
    if not ValueModel.tags_for_type_test(expr.test) then add(errors, label .. " unsupported LuaRT.TypeTest: " .. tostring(expr.test and expr.test.kind)) end
  elseif c == Exec.ProjectExpr then
    local pk = expr.projection and expr.projection.kind
    if pk ~= "ProjectTag" and pk ~= "ProjectPayloadBits" and pk ~= "ProjectInteger" and pk ~= "ProjectBool" and pk ~= "ProjectFloat" then
      add(errors, label .. " unsupported LuaRT.ValueProjection: " .. tostring(pk))
    end
  elseif c == Exec.ValueExpr or c == Exec.TruthinessExpr or c == Exec.NotTruthinessExpr or c == Exec.StackLoadExpr or c == Exec.TopValueExpr or c == Exec.CountExpr or c == Exec.ValueSeqExpr or c == Exec.VarargAccessExpr or c == Exec.RawGetExpr or c == Exec.RawSetExpr
      or c == Exec.TableRawGetExpr or c == Exec.TableRawGetHitExpr or c == Exec.TableRawGetValueOrNilExpr or c == Exec.TableRawSetCanWriteExpr or c == Exec.TableWriteBarrierNeededExpr or c == Exec.TableLenExpr or c == Exec.StringLenExpr or c == Exec.LenNoMetaExpr or c == Exec.StringConcat2Expr
      or c == Exec.ArithmeticNumericOkExpr or c == Exec.ArithmeticNoMetaExpr or c == Exec.ArithmeticErrorValueExpr
      or c == Exec.MetamethodLookupExpr or c == Exec.AdjustResultsExpr or c == Exec.NumberOpExpr or c == Exec.StringConcatExpr then
    -- Structurally recognized; unsupported execution is rejected by lowering.
  else
    add(errors, label .. " unsupported LuaExec.Expr class")
  end
end

local function validate_terminator(term, blocks_by_id, errors, label)
  if not is_member(Exec.Terminator, term) then
    add(errors, label .. " terminator must be LuaExec.Terminator")
    return
  end
  local c = cls(term)
  if c == Exec.Jump then
    local target = block_ref_key(term.target)
    if not target or not blocks_by_id[target] then add(errors, label .. " jump target does not resolve: " .. tostring(target)) end
    validate_args(term.args, errors, label .. " jump")
  elseif c == Exec.Branch then
    local t = block_ref_key(term.if_true)
    local f = block_ref_key(term.if_false)
    if not t or not blocks_by_id[t] then add(errors, label .. " true branch target does not resolve: " .. tostring(t)) end
    if not f or not blocks_by_id[f] then add(errors, label .. " false branch target does not resolve: " .. tostring(f)) end
    if not is_member(Exec.Choice, term.choice) then add(errors, label .. " branch choice must be LuaExec.Choice") end
  elseif c == Exec.BranchArgs then
    local t = block_ref_key(term.if_true)
    local f = block_ref_key(term.if_false)
    if not t or not blocks_by_id[t] then add(errors, label .. " true branch target does not resolve: " .. tostring(t)) end
    if not f or not blocks_by_id[f] then add(errors, label .. " false branch target does not resolve: " .. tostring(f)) end
    if not is_member(Exec.Choice, term.choice) then add(errors, label .. " branch choice must be LuaExec.Choice") end
    validate_args(term.true_args, errors, label .. " true branch")
    validate_args(term.false_args, errors, label .. " false branch")
  elseif c == Exec.Continue then
    if cls(term.continuation) ~= Exec.ContRef then add(errors, label .. " continue target must be LuaExec.ContRef") end
    validate_args(term.args, errors, label .. " continue")
  elseif c == Exec.Return then
    local ok, seq_errors = LuaRTValidate.value_seq(term.values)
    if not ok then for _, e in ipairs(seq_errors) do add(errors, label .. " return " .. e) end end
  elseif c == Exec.Error then
    if cls(term.error) ~= RT.ErrorState then add(errors, label .. " error terminator must carry LuaRT.ErrorState") end
  elseif c == Exec.Yield then
    if cls(term.yield) ~= RT.YieldState then add(errors, label .. " yield terminator must carry LuaRT.YieldState") end
  elseif c == Exec.Unreachable then
    -- accepted structural terminator
  else
    add(errors, label .. " unsupported LuaExec terminator class")
  end
end

function M.region(region)
  local errors = {}
  if cls(region) ~= Exec.Region then
    add(errors, "expected LuaExec.Region")
    return false, errors
  end
  if cls(region.id) ~= Exec.Name then add(errors, "region.id must be LuaExec.Name") end
  if not is_member(Exec.RegionKind, region.kind) then add(errors, "region.kind must be LuaExec.RegionKind") end
  for i, param in ipairs(region.params or {}) do validate_param(param, errors, "region param " .. i) end
  for i, cont in ipairs(region.continuations or {}) do
    if cls(cont) ~= Exec.Continuation then
      add(errors, "continuation " .. i .. " must be LuaExec.Continuation")
    else
      if cls(cont.id) ~= Exec.Name then add(errors, "continuation " .. i .. ".id must be LuaExec.Name") end
      if not is_member(Exec.ContinuationKind, cont.kind) then add(errors, "continuation " .. i .. ".kind must be LuaExec.ContinuationKind") end
      for j, param in ipairs(cont.params or {}) do validate_param(param, errors, "continuation " .. i .. " param " .. j) end
    end
  end

  local blocks_by_id = {}
  for i, block in ipairs(region.blocks or {}) do
    if cls(block) ~= Exec.Block then
      add(errors, "block " .. i .. " must be LuaExec.Block")
    else
      local key = block_key(block.id)
      if not key then
        add(errors, "block " .. i .. " has invalid id")
      elseif blocks_by_id[key] then
        add(errors, "duplicate block id: " .. key)
      else
        blocks_by_id[key] = block
      end
    end
  end

  local entry = region.entry and region.entry.name and region.entry.name.text or nil
  if not entry or not blocks_by_id[entry] then add(errors, "region entry block does not exist: " .. tostring(entry)) end

  for _, block in pairs(blocks_by_id) do
    local label = "block " .. name_text(block.id.name)
    for i, param in ipairs(block.params or {}) do validate_param(param, errors, label .. " param " .. i) end
    for i, op in ipairs(block.ops or {}) do
      if not is_member(Exec.Op, op) then add(errors, label .. " op " .. i .. " must be LuaExec.Op")
      elseif cls(op) == Exec.Let then validate_expr(op.expr, errors, label .. " op " .. i)
      elseif cls(op) == Exec.AssignValue then
        if not is_member(RT.ValueRef, op.dst) then add(errors, label .. " op " .. i .. " AssignValue dst must be LuaRT.ValueRef") end
        if not is_member(Exec.Value, op.src) then add(errors, label .. " op " .. i .. " AssignValue src must be LuaExec.Value") end
      elseif cls(op) == Exec.AssignSeq then
        if cls(op.dst) ~= RT.StackWindow then add(errors, label .. " op " .. i .. " AssignSeq dst must be LuaRT.StackWindow") end
        local ok, seq_errors = LuaRTValidate.value_seq(op.src)
        if not ok then for _, e in ipairs(seq_errors) do add(errors, label .. " op " .. i .. " AssignSeq " .. e) end end
      elseif cls(op) == Exec.SetTop then
        if cls(op.top) ~= RT.TopRef then add(errors, label .. " op " .. i .. " SetTop top must be LuaRT.TopRef") end
        if not is_member(RT.CountSpec, op.count) then add(errors, label .. " op " .. i .. " SetTop count must be LuaRT.CountSpec") end
      elseif cls(op) == Exec.TableRawSet then
        if not is_member(RT.ValueRef, op.table_value) then add(errors, label .. " op " .. i .. " TableRawSet table must be LuaRT.ValueRef") end
        if not is_member(RT.ValueRef, op.key) then add(errors, label .. " op " .. i .. " TableRawSet key must be LuaRT.ValueRef") end
        if not is_member(RT.ValueRef, op.value) then add(errors, label .. " op " .. i .. " TableRawSet value must be LuaRT.ValueRef") end
      elseif cls(op) == Exec.TableWriteBarrier then
        if not is_member(RT.ValueRef, op.table_value) then add(errors, label .. " op " .. i .. " TableWriteBarrier table must be LuaRT.ValueRef") end
        if not is_member(RT.ValueRef, op.value) then add(errors, label .. " op " .. i .. " TableWriteBarrier value must be LuaRT.ValueRef") end
      elseif cls(op) == Exec.Project then
        local pk = op.projection and op.projection.kind
        if pk ~= "ProjectTag" and pk ~= "ProjectPayloadBits" and pk ~= "ProjectInteger" and pk ~= "ProjectBool" and pk ~= "ProjectFloat" then
          add(errors, label .. " op " .. i .. " unsupported LuaRT.ValueProjection: " .. tostring(pk))
        end
      end
    end
    validate_terminator(block.terminator, blocks_by_id, errors, label)
  end

  return #errors == 0, errors
end

function M.kernel(kernel)
  local errors = {}
  if cls(kernel) ~= Exec.Kernel then
    add(errors, "expected LuaExec.Kernel")
    return false, errors
  end
  if cls(kernel.id) ~= Exec.Name then add(errors, "kernel.id must be LuaExec.Name") end
  local frame_ok, frame_errors = LuaRTValidate.frame(kernel.frame)
  if not frame_ok then for _, e in ipairs(frame_errors) do add(errors, "kernel.frame " .. e) end end
  local region_ok, region_errors = M.region(kernel.body)
  if not region_ok then for _, e in ipairs(region_errors) do add(errors, "kernel.body " .. e) end end
  if cls(kernel.contract) ~= Exec.Contract then add(errors, "kernel.contract must be LuaExec.Contract") end
  return #errors == 0, errors
end

function M.module(module)
  local errors = {}
  if cls(module) ~= Exec.Module then
    add(errors, "expected LuaExec.Module")
    return false, errors
  end
  for i, region in ipairs(module.regions or {}) do
    local ok, errs = M.region(region)
    if not ok then for _, e in ipairs(errs) do add(errors, "module region " .. i .. " " .. e) end end
  end
  for i, kernel in ipairs(module.kernels or {}) do
    local ok, errs = M.kernel(kernel)
    if not ok then for _, e in ipairs(errs) do add(errors, "module kernel " .. i .. " " .. e) end end
  end
  return #errors == 0, errors
end

return M
