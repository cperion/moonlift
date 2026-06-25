-- lua_compile/lua_exec_validate.lua -- structural checks for LuaExec semantic CFG.
--
-- LuaExec regions are semantic ASDL CFG fragments. Validation here stays
-- structural and fail-closed; it does not interpret Lua opcodes or call helpers.

local Schema = require("lua_compile.schema")
local pvm = require("lalin.pvm")
local T = Schema.get()
local RT, Exec = T.LuaRT, T.LuaExec
local LuaRTValidate = require("lua_compile.lua_rt_validate")
local ValueModel = require("lua_compile.lua_rt_value_model")
local RegionModel = require("lua_compile.lua_exec_region_model")
local StaticRegionModel = require("lua_compile.lua_exec_static_region_model")

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

local function validate_region_descriptor(descriptor, errors, label)
  if cls(descriptor) ~= Exec.RegionDescriptor then
    add(errors, label .. " must be LuaExec.RegionDescriptor")
    return
  end
  if cls(descriptor.id) ~= Exec.RegionId then add(errors, label .. ".id must be LuaExec.RegionId") end
  if not is_member(Exec.RegionKind, descriptor.kind) then add(errors, label .. ".kind must be LuaExec.RegionKind") end
  if not is_member(Exec.OpcodeFamily, descriptor.family) then add(errors, label .. ".family must be LuaExec.OpcodeFamily") end
  if cls(descriptor.start_pc) ~= RT.Pc then add(errors, label .. ".start_pc must be LuaRT.Pc") end
  if cls(descriptor.end_pc) ~= RT.Pc then add(errors, label .. ".end_pc must be LuaRT.Pc") end
end

function M.static_region_binding(binding)
  return StaticRegionModel.validate_static_region_binding(binding)
end

function M.call_continuation_region(region)
  return StaticRegionModel.validate_call_continuation_region(region)
end

function M.static_region_invocation(invocation)
  return StaticRegionModel.validate_static_region_invocation(invocation)
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
      or c == Exec.TableRawGetExpr or c == Exec.TableRawGetHitExpr or c == Exec.TableRawGetValueOrNilExpr or c == Exec.TableRawSetCanWriteExpr or c == Exec.TableWriteBarrierNeededExpr or c == Exec.TableLenExpr or c == Exec.StringLenExpr or c == Exec.LenNoMetaExpr or c == Exec.LenNoMetaOkExpr or c == Exec.StringConcat2Expr
      or c == Exec.ArithmeticNumericOkExpr or c == Exec.ArithmeticNoMetaExpr or c == Exec.ArithmeticErrorValueExpr
      or c == Exec.MetamethodLookupPathExpr or c == Exec.AdjustResultsExpr or c == Exec.NumberOpExpr or c == Exec.StringConcatExpr then
    -- Structurally recognized; unsupported execution is rejected by lowering.
  elseif c == Exec.NormalizeResultsExpr then
    local ok, seq_errors = LuaRTValidate.value_seq(expr.seq)
    if not ok then for _, e in ipairs(seq_errors) do add(errors, label .. " NormalizeResultsExpr seq " .. e) end end
    local shape_ok, shape_errors = LuaRTValidate.arity_shape(expr.shape)
    if not shape_ok then for _, e in ipairs(shape_errors) do add(errors, label .. " NormalizeResultsExpr shape " .. e) end end
  elseif c == Exec.ResultChannelExpr then
    local ok, errs = LuaRTValidate.result_channel(expr.channel)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. " ResultChannelExpr " .. e) end end
  elseif c == Exec.CallStateExpr then
    local ok, errs = LuaRTValidate.call_state(expr.call)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. " CallStateExpr " .. e) end end
  elseif c == Exec.ResolvedCallTargetExpr then
    local ok, errs = LuaRTValidate.resolved_call_target(expr.target)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. " ResolvedCallTargetExpr " .. e) end end
  elseif c == Exec.CallArgChannelExpr then
    local ok, errs = LuaRTValidate.call_arg_channel(expr.channel)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. " CallArgChannelExpr " .. e) end end
  elseif c == Exec.CallFrameStateExpr then
    local ok, errs = LuaRTValidate.call_frame_state(expr.frame)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. " CallFrameStateExpr " .. e) end end
  elseif c == Exec.CallResultChannelExpr then
    local ok, errs = LuaRTValidate.call_result_channel(expr.channel)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. " CallResultChannelExpr " .. e) end end
  elseif c == Exec.MetamethodDispatchExpr then
    local ok, errs = LuaRTValidate.metamethod_dispatch(expr.dispatch)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. " MetamethodDispatchExpr " .. e) end end
  elseif c == Exec.ClosePlanExpr then
    local ok, errs = LuaRTValidate.close_plan(expr.plan)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. " ClosePlanExpr " .. e) end end
  elseif c == Exec.GCEffectExpr then
    local ok, errs = LuaRTValidate.gc_effect(expr.effect)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. " GCEffectExpr " .. e) end end
  elseif c == Exec.RegionDescriptorExpr then
    validate_region_descriptor(expr.descriptor, errors, label .. " RegionDescriptorExpr")
  elseif c == Exec.StaticRegionBindingExpr then
    local ok, errs = M.static_region_binding(expr.binding)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. " StaticRegionBindingExpr " .. e) end end
  elseif c == Exec.StaticRegionInvocationExpr then
    local ok, errs = M.static_region_invocation(expr.invocation)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. " StaticRegionInvocationExpr " .. e) end end
  elseif c == Exec.LuaOperationExpr then
    local ok, errs = LuaRTValidate.lua_operation(expr.operation)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. " LuaOperationExpr " .. e) end end
  else
    add(errors, label .. " unsupported LuaExec.Expr class")
  end
end

local function validate_terminator(term, blocks_by_id, continuations_by_id, errors, label)
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
    local cont_name = term.continuation and term.continuation.id and term.continuation.id.text
    if continuations_by_id and cont_name and not continuations_by_id[cont_name] then add(errors, label .. " continue target does not resolve: " .. tostring(cont_name)) end
    validate_args(term.args, errors, label .. " continue")
  elseif c == Exec.Return then
    local ok, seq_errors = LuaRTValidate.value_seq(term.values)
    if not ok then for _, e in ipairs(seq_errors) do add(errors, label .. " return " .. e) end end
  elseif c == Exec.Error then
    if cls(term.error) ~= RT.ErrorState then add(errors, label .. " error terminator must carry LuaRT.ErrorState") end
  elseif c == Exec.Yield then
    if cls(term.yield) ~= RT.YieldState then add(errors, label .. " yield terminator must carry LuaRT.YieldState") end
  elseif c == Exec.Unreachable or (term and term.kind == "Unreachable") then
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
  local continuations_by_id = {}
  for i, cont in ipairs(region.continuations or {}) do
    if cls(cont) ~= Exec.Continuation then
      add(errors, "continuation " .. i .. " must be LuaExec.Continuation")
    else
      if cls(cont.id) ~= Exec.Name then add(errors, "continuation " .. i .. ".id must be LuaExec.Name") else
        local ck = cont.id.text
        if continuations_by_id[ck] then add(errors, "duplicate continuation id: " .. ck) else continuations_by_id[ck] = cont end
      end
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
        if not is_member(RT.ResultAdjustment, op.adjustment) then add(errors, label .. " op " .. i .. " AssignSeq adjustment must be LuaRT.ResultAdjustment") end
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
      elseif cls(op) == Exec.PrepareCallFrame then
        local ok, errs = LuaRTValidate.call_frame_state(op.frame)
        if not ok then for _, e in ipairs(errs) do add(errors, label .. " op " .. i .. " PrepareCallFrame " .. e) end end
      elseif cls(op) == Exec.ReceiveCallResults then
        local ok, errs = LuaRTValidate.call_frame_state(op.frame)
        if not ok then for _, e in ipairs(errs) do add(errors, label .. " op " .. i .. " ReceiveCallResults " .. e) end end
      elseif cls(op) == Exec.EmitRegion then
        if cls(op.region) ~= Exec.Name then add(errors, label .. " op " .. i .. " EmitRegion region must be LuaExec.Name") end
        validate_args(op.args, errors, label .. " op " .. i .. " EmitRegion")
        for j, binding in ipairs(op.continuations or {}) do
          if cls(binding) ~= Exec.ContBinding then add(errors, label .. " op " .. i .. " EmitRegion continuation " .. j .. " must be LuaExec.ContBinding") end
        end
      elseif cls(op) == Exec.Project then
        local pk = op.projection and op.projection.kind
        if pk ~= "ProjectTag" and pk ~= "ProjectPayloadBits" and pk ~= "ProjectInteger" and pk ~= "ProjectBool" and pk ~= "ProjectFloat" then
          add(errors, label .. " op " .. i .. " unsupported LuaRT.ValueProjection: " .. tostring(pk))
        end
      end
    end
    validate_terminator(block.terminator, blocks_by_id, continuations_by_id, errors, label)
  end

  return #errors == 0, errors
end

local function validate_exec_obligation(obligation, errors, label)
  if not is_member(Exec.Obligation, obligation) then add(errors, label .. " must be LuaExec.Obligation"); return end
  local c = cls(obligation)
  if c == Exec.RequiresGuard then
    if not is_member(RT.Guard, obligation.guard) then add(errors, label .. ".guard must be LuaRT.Guard") end
  elseif c == Exec.RequiresResolvedRegion then
    if cls(obligation.region) ~= Exec.Name then add(errors, label .. ".region must be LuaExec.Name") end
  elseif c == Exec.RequiresContinuation then
    if cls(obligation.continuation) ~= Exec.ContRef then add(errors, label .. ".continuation must be LuaExec.ContRef") end
  elseif c == Exec.RequiresCompanion then
    if cls(obligation.pc) ~= RT.Pc then add(errors, label .. ".pc must be LuaRT.Pc") end
    if not is_member(RT.CompanionKind, obligation.kind) then add(errors, label .. ".kind must be LuaRT.CompanionKind") end
  elseif c == Exec.RequiresRegionDescriptor then
    validate_region_descriptor(obligation.descriptor, errors, label .. ".descriptor")
  elseif c == Exec.RequiresArityShape then
    local ok, errs = LuaRTValidate.arity_shape(obligation.shape)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. ".shape " .. e) end end
  elseif c == Exec.RequiresResultChannel then
    local ok, errs = LuaRTValidate.result_channel(obligation.channel)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. ".channel " .. e) end end
  elseif c == Exec.RequiresResolvedCallTarget then
    local ok, errs = LuaRTValidate.resolved_call_target(obligation.target)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. ".target " .. e) end end
  elseif c == Exec.RequiresCallFrameLayout then
    local ok, errs = LuaRTValidate.call_frame_layout(obligation.layout)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. ".layout " .. e) end end
  elseif c == Exec.RequiresCallArgChannel then
    local ok, errs = LuaRTValidate.call_arg_channel(obligation.channel)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. ".channel " .. e) end end
  elseif c == Exec.RequiresCallResultChannel then
    local ok, errs = LuaRTValidate.call_result_channel(obligation.channel)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. ".channel " .. e) end end
  elseif c == Exec.RequiresResultRoute then
    local ok, errs = LuaRTValidate.result_channel(obligation.channel)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. ".channel " .. e) end end
  elseif c == Exec.RequiresFrameEffect then
    local ok, errs = LuaRTValidate.frame_effect(obligation.effect)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. ".effect " .. e) end end
  elseif c == Exec.RequiresStaticRegion then
    local ok, errs = M.static_region_binding(obligation.binding)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. ".binding " .. e) end end
  elseif c == Exec.RequiresStaticRegionInvocation then
    local ok, errs = M.static_region_invocation(obligation.invocation)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. ".invocation " .. e) end end
  elseif c == Exec.RequiresCallContinuationRegion then
    local ok, errs = M.call_continuation_region(obligation.region)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. ".region " .. e) end end
  elseif c == Exec.RequiresMetamethodLookupPath then
    local ok, errs = LuaRTValidate.metamethod_lookup_path(obligation.path)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. ".path " .. e) end end
  elseif c == Exec.RequiresClosureIdentity then
    local ok, errs = LuaRTValidate.closure_identity(obligation.identity)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. ".identity " .. e) end end
  elseif c == Exec.RequiresUpvalueIdentity then
    local ok, errs = LuaRTValidate.upvalue_identity(obligation.identity)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. ".identity " .. e) end end
  elseif c == Exec.RequiresGCEffect then
    local ok, errs = LuaRTValidate.gc_effect(obligation.effect)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. ".effect " .. e) end end
  elseif c == Exec.RequiresFFICallShape then
    local ok, errs = LuaRTValidate.ffi_call_shape(obligation.call)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. ".call " .. e) end end
  elseif c == Exec.RequiresLuaOperation then
    local ok, errs = LuaRTValidate.lua_operation(obligation.operation)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. ".operation " .. e) end end
  elseif c == Exec.RequiresLoopTopology then
    local ok, errs = LuaRTValidate.loop_topology(obligation.topology)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. ".topology " .. e) end end
  elseif c == Exec.RequiresClosePlan then
    local ok, errs = LuaRTValidate.close_plan(obligation.plan)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. ".plan " .. e) end end
  end
end

local function validate_exec_guarantee(guarantee, errors, label)
  if not is_member(Exec.Guarantee, guarantee) then add(errors, label .. " must be LuaExec.Guarantee"); return end
  local c = cls(guarantee)
  if c == Exec.ProducesValue then
    if not is_member(RT.ValueRef, guarantee.value) then add(errors, label .. ".value must be LuaRT.ValueRef") end
  elseif c == Exec.PreservesFrame then
    if cls(guarantee.frame) ~= RT.FrameRef then add(errors, label .. ".frame must be LuaRT.FrameRef") end
  elseif c == Exec.UpdatesTop then
    if cls(guarantee.top) ~= RT.TopRef then add(errors, label .. ".top must be LuaRT.TopRef") end
  elseif c == Exec.ClosesChain then
    if cls(guarantee.chain) ~= RT.CloseChain then add(errors, label .. ".chain must be LuaRT.CloseChain") end
  elseif c == Exec.DescribesRegion then
    validate_region_descriptor(guarantee.descriptor, errors, label .. ".descriptor")
  elseif c == Exec.NormalizesArity then
    local ok, errs = LuaRTValidate.arity_normalization(guarantee.normalization)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. ".normalization " .. e) end end
  elseif c == Exec.ProducesResultChannel then
    local ok, errs = LuaRTValidate.result_channel(guarantee.channel)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. ".channel " .. e) end end
  elseif c == Exec.ResolvesCallTarget then
    local ok, errs = LuaRTValidate.resolved_call_target(guarantee.target)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. ".target " .. e) end end
  elseif c == Exec.PreparesCallFrame then
    local ok, errs = LuaRTValidate.call_frame_state(guarantee.frame)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. ".frame " .. e) end end
  elseif c == Exec.ProducesCallResults then
    local ok, errs = LuaRTValidate.call_result_channel(guarantee.channel)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. ".channel " .. e) end end
  elseif c == Exec.ProducesResultRoute then
    local ok, errs = LuaRTValidate.result_channel(guarantee.channel)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. ".channel " .. e) end end
  elseif c == Exec.AppliesFrameEffect then
    local ok, errs = LuaRTValidate.frame_effect(guarantee.effect)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. ".effect " .. e) end end
  elseif c == Exec.ProvidesStaticRegion then
    local ok, errs = M.static_region_binding(guarantee.binding)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. ".binding " .. e) end end
  elseif c == Exec.InvokesStaticRegion then
    local ok, errs = M.static_region_invocation(guarantee.invocation)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. ".invocation " .. e) end end
  elseif c == Exec.BindsCallContinuationRegion then
    local ok, errs = M.call_continuation_region(guarantee.region)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. ".region " .. e) end end
  elseif c == Exec.ResolvesMetamethodLookupPath then
    local ok, errs = LuaRTValidate.metamethod_lookup_path(guarantee.path)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. ".path " .. e) end end
  elseif c == Exec.UsesClosureIdentity then
    local ok, errs = LuaRTValidate.closure_identity(guarantee.identity)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. ".identity " .. e) end end
  elseif c == Exec.UsesUpvalueIdentity then
    local ok, errs = LuaRTValidate.upvalue_identity(guarantee.identity)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. ".identity " .. e) end end
  elseif c == Exec.AppliesGCEffect then
    local ok, errs = LuaRTValidate.gc_effect(guarantee.effect)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. ".effect " .. e) end end
  elseif c == Exec.UsesFFICallShape then
    local ok, errs = LuaRTValidate.ffi_call_shape(guarantee.call)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. ".call " .. e) end end
  elseif c == Exec.DescribesLuaOperation then
    local ok, errs = LuaRTValidate.lua_operation(guarantee.operation)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. ".operation " .. e) end end
  elseif c == Exec.DescribesLoopTopology then
    local ok, errs = LuaRTValidate.loop_topology(guarantee.topology)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. ".topology " .. e) end end
  elseif c == Exec.AppliesClosePlan then
    local ok, errs = LuaRTValidate.close_plan(guarantee.plan)
    if not ok then for _, e in ipairs(errs) do add(errors, label .. ".plan " .. e) end end
  end
end

function M.contract(contract)
  local errors = {}
  if cls(contract) ~= Exec.Contract then return false, { "expected LuaExec.Contract" } end
  for i, obligation in ipairs(contract.obligations or {}) do validate_exec_obligation(obligation, errors, "contract.obligations[" .. i .. "]") end
  for i, guarantee in ipairs(contract.guarantees or {}) do validate_exec_guarantee(guarantee, errors, "contract.guarantees[" .. i .. "]") end
  return #errors == 0, errors
end

function M.region_descriptor(descriptor)
  local errors = {}
  validate_region_descriptor(descriptor, errors, "region_descriptor")
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
  local contract_ok, contract_errors = M.contract(kernel.contract)
  if not contract_ok then for _, e in ipairs(contract_errors) do add(errors, "kernel.contract " .. e) end end
  return #errors == 0, errors
end

function M.module(module)
  local errors = {}
  if cls(module) ~= Exec.Module then
    add(errors, "expected LuaExec.Module")
    return false, errors
  end
  local index, index_errors = StaticRegionModel.index_module(module)
  if not index then
    for _, e in ipairs(index_errors or {}) do add(errors, e) end
  end
  for i, region in ipairs(module.regions or {}) do
    local ok, errs = M.region(region)
    if not ok then for _, e in ipairs(errs) do add(errors, "module region " .. i .. " " .. e) end end
  end
  for i, kernel in ipairs(module.kernels or {}) do
    local ok, errs = M.kernel(kernel)
    if not ok then for _, e in ipairs(errs) do add(errors, "module kernel " .. i .. " " .. e) end end
    if index and cls(kernel) == Exec.Kernel then
      local call_ok, call_reason = StaticRegionModel.validate_call_contract_for_static_invocation(kernel.contract)
      if not call_ok then add(errors, "module kernel " .. i .. " unsupported static call contract: " .. tostring(call_reason)) end
      for _, invocation in ipairs(StaticRegionModel.contract_static_invocations(kernel.contract)) do
        local inv_ok, inv_errors = StaticRegionModel.validate_invocation_against_module(index, invocation)
        if not inv_ok then for _, e in ipairs(inv_errors) do add(errors, "module kernel " .. i .. " static invocation " .. e) end end
      end
      for _, block in ipairs((kernel.body and kernel.body.blocks) or {}) do
        for op_i, op in ipairs(block.ops or {}) do
          if cls(op) == Exec.EmitRegion then
            local shape_ok, shape_errors = StaticRegionModel.validate_emit_op_inline_shape(block, op_i)
            if not shape_ok then for _, e in ipairs(shape_errors) do add(errors, "module kernel " .. i .. " EmitRegion " .. e) end end
            local invocation, find_errors = StaticRegionModel.find_invocation_for_emit(kernel.contract, op)
            if not invocation then
              for _, e in ipairs(find_errors or {}) do add(errors, "module kernel " .. i .. " EmitRegion " .. e) end
            else
              local inv_ok, inv_errors = StaticRegionModel.validate_invocation_against_module(index, invocation)
              if not inv_ok then for _, e in ipairs(inv_errors) do add(errors, "module kernel " .. i .. " EmitRegion " .. e) end end
              local target_name = StaticRegionModel.region_ref_key(invocation.target.region)
              local target = target_name and index.regions[target_name]
              if target then
                local target_ok, target_errors = StaticRegionModel.validate_target_region_for_inline(target, invocation, kernel.contract)
                if not target_ok then for _, e in ipairs(target_errors) do add(errors, "module kernel " .. i .. " EmitRegion target " .. e) end end
              end
            end
          end
        end
      end
    end
  end
  return #errors == 0, errors
end

return M
