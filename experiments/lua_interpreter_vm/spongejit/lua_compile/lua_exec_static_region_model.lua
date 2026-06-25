-- lua_exec_static_region_model.lua -- typed LuaExec.Module static-region invocation gates.
--
-- Static invocation is semantic CFG composition over existing LuaExec ASDL
-- products.  This module validates relationships and current inlining support;
-- it does not dispatch to the VM, call helpers, or make source CALL executable.

local Schema = require("lua_compile.schema")
local pvm = require("lalin.pvm")
local T = Schema.get()
local RT, Exec = T.LuaRT, T.LuaExec
local RegionModel = require("lua_compile.lua_exec_region_model")
local CallModel = require("lua_compile.lua_rt_call_model")

local M = {}

local function cls(v) return pvm.classof(v) end
local function member(v, sum) return v ~= nil and sum and sum.members and sum.members[cls(v)] or false end
local function add(errors, msg) errors[#errors + 1] = msg end
local function kind(v) return v and v.kind or nil end

local function name_key(name) return name and name.text or nil end
local function region_id_key(id) return id and id.name and id.name.text or nil end
local function region_ref_key(ref) return ref and ref.id and region_id_key(ref.id) or nil end
local function block_id_key(id) return id and id.name and id.name.text or nil end
local function block_ref_key(ref) return ref and ref.id and block_id_key(ref.id) or nil end
local function cont_ref_key(ref) return ref and ref.id and ref.id.text or nil end
local function op_region_key(op) return op and op.region and op.region.text or nil end

M.name_key = name_key
M.region_id_key = region_id_key
M.region_ref_key = region_ref_key
M.block_id_key = block_id_key
M.block_ref_key = block_ref_key
M.cont_ref_key = cont_ref_key
M.op_region_key = op_region_key

local function validate_args(args, errors, label)
  for i, arg in ipairs(args or {}) do
    if cls(arg) ~= Exec.Arg then
      add(errors, label .. ".args[" .. i .. "] must be LuaExec.Arg")
    else
      if cls(arg.name) ~= Exec.Name then add(errors, label .. ".args[" .. i .. "].name must be LuaExec.Name") end
      if not member(arg.value, Exec.Value) then add(errors, label .. ".args[" .. i .. "].value must be LuaExec.Value") end
    end
  end
end

local function validate_cont_bindings(bindings, errors, label)
  local seen = {}
  for i, binding in ipairs(bindings or {}) do
    if cls(binding) ~= Exec.ContBinding then
      add(errors, label .. ".continuations[" .. i .. "] must be LuaExec.ContBinding")
    else
      if cls(binding.continuation) ~= Exec.ContRef then add(errors, label .. ".continuations[" .. i .. "].continuation must be LuaExec.ContRef") end
      if cls(binding.target) ~= Exec.BlockRef then add(errors, label .. ".continuations[" .. i .. "].target must be LuaExec.BlockRef") end
      validate_args(binding.args, errors, label .. ".continuations[" .. i .. "]")
      local ck = cont_ref_key(binding.continuation)
      if ck then
        if seen[ck] then add(errors, label .. ".duplicate continuation binding: " .. ck) end
        seen[ck] = true
      end
    end
  end
end

local function validate_region_descriptor(descriptor, errors, label)
  if cls(descriptor) ~= Exec.RegionDescriptor then
    add(errors, label .. " must be LuaExec.RegionDescriptor")
    return
  end
  if cls(descriptor.id) ~= Exec.RegionId then add(errors, label .. ".id must be LuaExec.RegionId") end
  if not member(descriptor.kind, Exec.RegionKind) then add(errors, label .. ".kind must be LuaExec.RegionKind") end
  if not member(descriptor.family, Exec.OpcodeFamily) then add(errors, label .. ".family must be LuaExec.OpcodeFamily") end
  if cls(descriptor.start_pc) ~= RT.Pc then add(errors, label .. ".start_pc must be LuaRT.Pc") end
  if cls(descriptor.end_pc) ~= RT.Pc then add(errors, label .. ".end_pc must be LuaRT.Pc") end
end

function M.validate_static_region_binding(binding)
  local errors = {}
  if cls(binding) ~= Exec.StaticRegionBinding then add(errors, "expected LuaExec.StaticRegionBinding"); return false, errors end
  if cls(binding.region) ~= Exec.RegionRef then add(errors, "region must be LuaExec.RegionRef") end
  validate_region_descriptor(binding.descriptor, errors, "descriptor")
  if not member(binding.role, Exec.StaticRegionRole) then add(errors, "role must be LuaExec.StaticRegionRole") end
  local ref_id = region_ref_key(binding.region)
  local desc_id = region_id_key(binding.descriptor and binding.descriptor.id)
  if ref_id and desc_id and ref_id ~= desc_id then add(errors, "binding region id must match descriptor id: " .. tostring(ref_id) .. " != " .. tostring(desc_id)) end
  return #errors == 0, errors
end

function M.validate_call_continuation_region(region)
  local errors = {}
  if cls(region) ~= Exec.CallContinuationRegion then add(errors, "expected LuaExec.CallContinuationRegion"); return false, errors end
  if cls(region.call) ~= RT.CallRef then add(errors, "call must be LuaRT.CallRef") end
  if cls(region.callee_region) ~= Exec.RegionRef then add(errors, "callee_region must be LuaExec.RegionRef") end
  for _, field in ipairs({ "return_cont", "error_cont", "yield_cont" }) do
    if cls(region[field]) ~= Exec.ContRef then add(errors, field .. " must be LuaExec.ContRef") end
  end
  return #errors == 0, errors
end

function M.validate_static_region_invocation(invocation)
  local errors = {}
  if cls(invocation) ~= Exec.StaticRegionInvocation then add(errors, "expected LuaExec.StaticRegionInvocation"); return false, errors end
  if cls(invocation.id) ~= Exec.Name then add(errors, "id must be LuaExec.Name") end
  local ok_binding, binding_errors = M.validate_static_region_binding(invocation.target)
  if not ok_binding then for _, e in ipairs(binding_errors) do add(errors, "target " .. e) end end
  validate_args(invocation.args, errors, "invocation")
  validate_cont_bindings(invocation.continuations, errors, "invocation")
  local ok_cont, cont_errors = M.validate_call_continuation_region(invocation.call_continuation)
  if not ok_cont then for _, e in ipairs(cont_errors) do add(errors, "call_continuation " .. e) end end
  local target_region = region_ref_key(invocation.target and invocation.target.region)
  local cont_region = region_ref_key(invocation.call_continuation and invocation.call_continuation.callee_region)
  if target_region and cont_region and target_region ~= cont_region then
    add(errors, "call_continuation callee_region must match invocation target: " .. tostring(cont_region) .. " != " .. tostring(target_region))
  end
  return #errors == 0, errors
end

function M.index_module(module)
  local errors = {}
  if cls(module) ~= Exec.Module then return nil, { "expected LuaExec.Module" } end
  local index = { regions = {}, kernels = {}, all = {} }
  local function insert(kind_label, map, item, i)
    local key = item and item.id and item.id.text
    if not key then add(errors, kind_label .. "[" .. i .. "] has invalid id"); return end
    if index.all[key] then add(errors, "duplicate module region/kernel id: " .. key) end
    map[key] = item
    index.all[key] = item
  end
  for i, region in ipairs(module.regions or {}) do
    if cls(region) ~= Exec.Region then add(errors, "regions[" .. i .. "] must be LuaExec.Region") else insert("regions", index.regions, region, i) end
  end
  for i, kernel in ipairs(module.kernels or {}) do
    if cls(kernel) ~= Exec.Kernel then add(errors, "kernels[" .. i .. "] must be LuaExec.Kernel") else insert("kernels", index.kernels, kernel, i) end
  end
  if #errors > 0 then return nil, errors end
  return index, nil
end

local function collect_invocation(invocations, invocation)
  invocations[#invocations + 1] = invocation
end

function M.contract_static_invocations(contract)
  local invocations, seen = {}, {}
  local function add_inv(invocation)
    if invocation and not seen[invocation] then
      seen[invocation] = true
      collect_invocation(invocations, invocation)
    end
  end
  for _, o in ipairs((contract and contract.obligations) or {}) do
    if cls(o) == Exec.RequiresStaticRegionInvocation then add_inv(o.invocation) end
  end
  for _, g in ipairs((contract and contract.guarantees) or {}) do
    if cls(g) == Exec.InvokesStaticRegion then add_inv(g.invocation) end
  end
  return invocations
end

local function cont_bindings_match(a, b)
  local ax, bx = {}, {}
  for _, binding in ipairs(a or {}) do ax[cont_ref_key(binding.continuation)] = block_ref_key(binding.target) end
  for _, binding in ipairs(b or {}) do bx[cont_ref_key(binding.continuation)] = block_ref_key(binding.target) end
  for k, v in pairs(ax) do if bx[k] ~= v then return false end end
  for k, v in pairs(bx) do if ax[k] ~= v then return false end end
  return true
end

function M.find_invocation_for_emit(contract, emit_op)
  if cls(emit_op) ~= Exec.EmitRegion then return nil, { "op must be LuaExec.EmitRegion" } end
  local target_name = op_region_key(emit_op)
  local matches = {}
  for _, invocation in ipairs(M.contract_static_invocations(contract)) do
    if region_ref_key(invocation.target and invocation.target.region) == target_name
        and cont_bindings_match(invocation.continuations, emit_op.continuations) then
      matches[#matches + 1] = invocation
    end
  end
  if #matches == 1 then return matches[1] end
  if #matches == 0 then return nil, { "missing_static_region_invocation_contract:" .. tostring(target_name) } end
  return nil, { "ambiguous_static_region_invocation_contract:" .. tostring(target_name) }
end

local function target_region_for_invocation(module_index, invocation)
  local target_name = region_ref_key(invocation and invocation.target and invocation.target.region)
  return target_name and module_index and module_index.regions[target_name] or nil, target_name
end

function M.validate_invocation_against_module(module_index, invocation)
  local errors = {}
  local ok, errs = M.validate_static_region_invocation(invocation)
  if not ok then for _, e in ipairs(errs) do add(errors, e) end; return false, errors end
  local region, target_name = target_region_for_invocation(module_index, invocation)
  if not region then add(errors, "static invocation target not in module: " .. tostring(target_name)); return false, errors end
  local desc = invocation.target.descriptor
  if region.id.text ~= region_id_key(desc.id) then add(errors, "target descriptor id mismatch: " .. tostring(region.id.text) .. " != " .. tostring(region_id_key(desc.id))) end
  if region.kind ~= desc.kind then add(errors, "target descriptor kind mismatch: " .. tostring(kind(region.kind)) .. " != " .. tostring(kind(desc.kind))) end
  return #errors == 0, errors
end

function M.validate_emit_op_inline_shape(block, op_index)
  local errors = {}
  if cls(block) ~= Exec.Block then return false, { "block must be LuaExec.Block" } end
  local op = block.ops and block.ops[op_index]
  if cls(op) ~= Exec.EmitRegion then return false, { "op must be LuaExec.EmitRegion" } end
  if op_index ~= #(block.ops or {}) then add(errors, "EmitRegion must be final op in block") end
  if cls(block.terminator) ~= Exec.Unreachable and (block.terminator and block.terminator.kind) ~= "Unreachable" then add(errors, "EmitRegion block terminator must be LuaExec.Unreachable") end
  return #errors == 0, errors
end

local function binding_by_cont(bindings)
  local out = {}
  for _, binding in ipairs(bindings or {}) do out[cont_ref_key(binding.continuation)] = binding end
  return out
end

function M.validate_target_region_for_inline(region, invocation, contract)
  local errors = {}
  if cls(region) ~= Exec.Region then return false, { "target must be LuaExec.Region" } end
  local executable, reason = RegionModel.is_executable_region(region, contract or Exec.Contract({}, {}))
  if not executable then add(errors, "unsupported_static_target_region:" .. tostring(reason)) end
  if kind(region.kind) == "CallRegion" or kind(region.kind) == "TailCallRegion" then
    add(errors, "static target region must be non-call executable region")
  end
  local ret_cont = cont_ref_key(invocation.call_continuation and invocation.call_continuation.return_cont)
  local bound = binding_by_cont(invocation.continuations)
  if ret_cont and not bound[ret_cont] then add(errors, "return continuation is not bound: " .. tostring(ret_cont)) end
  for _, field in ipairs({ "error_cont", "yield_cont" }) do
    local ck = cont_ref_key(invocation.call_continuation and invocation.call_continuation[field])
    if ck and bound[ck] == nil then
      -- Structurally they may be absent from the emit site for this milestone;
      -- executable target regions below must not continue to them.
    end
  end
  for _, block in ipairs(region.blocks or {}) do
    for i, op in ipairs(block.ops or {}) do
      if cls(op) == Exec.EmitRegion then add(errors, "nested EmitRegion is not supported in static target: " .. tostring(region.id.text) .. " block " .. tostring(block_id_key(block.id)) .. " op " .. i) end
    end
    local tc = cls(block.terminator)
    if tc == Exec.Return or tc == Exec.Error or tc == Exec.Yield then
      add(errors, "static target region must terminate via Continue/Jump/Branch, not " .. tostring(kind(block.terminator)))
    elseif tc == Exec.Continue then
      local ck = cont_ref_key(block.terminator.continuation)
      if ck ~= ret_cont then add(errors, "static target Continue must use bound return continuation: " .. tostring(ck)) end
    end
  end
  return #errors == 0, errors
end

function M.validate_call_contract_for_static_invocation(contract)
  local has_call_contract = false
  for _, o in ipairs((contract and contract.obligations) or {}) do
    local k = kind(o)
    if k == "RequiresResolvedCallTarget" or k == "RequiresCallFrameLayout" or k == "RequiresCallArgChannel" or k == "RequiresCallResultChannel" then has_call_contract = true end
  end
  for _, g in ipairs((contract and contract.guarantees) or {}) do
    local k = kind(g)
    if k == "ResolvesCallTarget" or k == "PreparesCallFrame" or k == "ProducesCallResults" then has_call_contract = true end
  end
  if not has_call_contract then return true end
  return CallModel.contract_allows_executable_call_region(contract)
end

function M.validate_against_schema()
  local missing = {}
  for _, name in ipairs({
    "StaticRegionRole", "StaticRegionBinding", "StaticRegionInvocation",
    "CallContinuationRegion", "RequiresStaticRegion", "RequiresStaticRegionInvocation",
    "RequiresCallContinuationRegion", "ProvidesStaticRegion", "InvokesStaticRegion",
    "BindsCallContinuationRegion", "StaticRegionBindingExpr", "StaticRegionInvocationExpr",
  }) do
    if Exec[name] == nil then missing[#missing + 1] = "LuaExec." .. name end
  end
  return #missing == 0, missing
end

return M
