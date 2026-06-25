-- lua_src_call_static_model.lua -- strict evidence-backed source CALL slice.
--
-- This module is the only source-CALL evidence lookup boundary.  It accepts
-- fixed-shape direct Lua-closure calls only when typed payload leases carry the
-- closure/proto identity and static callee LuaExec.Region binding.  It does not
-- dispatch to the VM, synthesize helper calls, or accept dynamic/metamethod/C/FFI
-- targets.

local Schema = require("lua_compile.schema")
local pvm = require("lalin.pvm")
local T = Schema.get()
local Src, Fact, RT, Exec = T.LuaSrc, T.LuaFact, T.LuaRT, T.LuaExec
local Arity = require("lua_compile.lua_rt_arity_model")
local StaticRegion = require("lua_compile.lua_exec_static_region_model")

local M = {}

local function cls(v) return pvm.classof(v) end
local function kind(v) return v and v.kind or nil end
local function add(errors, msg) errors[#errors + 1] = msg end
local function pc_id(pc) return tonumber(pc and pc.id or pc) or 0 end
local function slot_id(slot) return tonumber(slot and slot.id or slot) or 0 end
local function src_count(count) return tonumber(count and count.value or count) or 0 end
local function rtname(s) return RT.Name(tostring(s)) end
local function ename(s) return Exec.Name(tostring(s)) end
local function same_name(a, b) return a and b and a.name and b.name and a.name.text == b.name.text end
local function same_proto(a, b) return a and b and a.proto and b and (a.proto.id == b.id or (b.proto and a.proto.id == b.proto.id)) end
local function region_ref_key(ref) return StaticRegion.region_ref_key(ref) end
local function region_id_key(id) return StaticRegion.region_id_key(id) end

local function is_src_slot_subject(subject, sid)
  return subject and subject.kind == "SrcSlot" and subject.slot and subject.slot.id == sid
end

local function payload_matches(payload, call_op)
  return payload and payload.pc and payload.pc.id == call_op.pc.id
    and is_src_slot_subject(payload.subject, call_op.base.id)
end

function M.find_static_call_payloads(evidence, call_op)
  local target_payload, region_payload
  for _, payload in ipairs((evidence and evidence.payloads) or {}) do
    if payload_matches(payload, call_op) then
      if kind(payload) == "StaticClosureTargetPayload" then target_payload = payload
      elseif kind(payload) == "StaticCalleeRegionPayload" then region_payload = payload end
    end
  end
  if target_payload and region_payload then return { target = target_payload, region = region_payload } end
  local missing = {}
  if not target_payload then missing[#missing + 1] = "StaticClosureTargetPayload" end
  if not region_payload then missing[#missing + 1] = "StaticCalleeRegionPayload" end
  return nil, { "lua_exec:source_call_missing_static_evidence:" .. tostring(call_op and call_op.pc and call_op.pc.id) .. ":" .. table.concat(missing, ",") }
end

local function validate_target_region(region, errors)
  if cls(region) ~= Exec.Region then add(errors, "static callee payload region must be LuaExec.Region"); return end
  if #(region.params or {}) > 0 then add(errors, "source CALL static callee region params are not supported") end
  for _, block in ipairs(region.blocks or {}) do
    for _, op in ipairs(block.ops or {}) do
      if cls(op) == Exec.EmitRegion then add(errors, "source CALL static callee region must not contain nested EmitRegion") end
    end
    local tc = cls(block.terminator)
    if tc == Exec.Return or tc == Exec.Error or tc == Exec.Yield then
      add(errors, "source CALL static callee region must terminate via Continue/Jump/Branch, not " .. tostring(kind(block.terminator)))
    end
  end
end

function M.validate_static_call_slice(call_op, target_payload, region_payload)
  local errors = {}
  if cls(call_op) ~= Src.CALL then add(errors, "expected LuaSrc.CALL") end
  local nargs = src_count(call_op and call_op.nargs)
  local nresults = src_count(call_op and call_op.nresults)
  if nargs <= 0 then add(errors, "lua_exec:source_call_dynamic_or_open_arg_count:" .. tostring(pc_id(call_op and call_op.pc))) end
  if nresults <= 0 then add(errors, "lua_exec:source_call_dynamic_or_open_result_count:" .. tostring(pc_id(call_op and call_op.pc))) end
  if cls(target_payload) ~= Fact.StaticClosureTargetPayload then add(errors, "missing StaticClosureTargetPayload") end
  if cls(region_payload) ~= Fact.StaticCalleeRegionPayload then add(errors, "missing StaticCalleeRegionPayload") end
  if #errors > 0 then return false, errors end

  if not payload_matches(target_payload, call_op) then add(errors, "StaticClosureTargetPayload pc/subject does not match CALL") end
  if not payload_matches(region_payload, call_op) then add(errors, "StaticCalleeRegionPayload pc/subject does not match CALL") end
  if cls(target_payload.closure) ~= RT.ClosureIdentity then add(errors, "target payload closure must be LuaRT.ClosureIdentity") end
  if cls(region_payload.closure) ~= RT.ClosureIdentity then add(errors, "region payload closure must be LuaRT.ClosureIdentity") end
  if cls(target_payload.target) ~= RT.ResolvedCallTarget then add(errors, "target payload target must be LuaRT.ResolvedCallTarget") end
  if cls(region_payload.binding) ~= Exec.StaticRegionBinding then add(errors, "region payload binding must be LuaExec.StaticRegionBinding") end
  if cls(region_payload.region) ~= Exec.Region then add(errors, "region payload region must be LuaExec.Region") end
  if #errors > 0 then return false, errors end

  local closure = target_payload.closure
  local resolved = target_payload.target
  if region_payload.closure.closure ~= closure.closure or region_payload.closure.proto.proto.id ~= closure.proto.proto.id then
    add(errors, "static CALL closure identity mismatch between payloads")
  end
  if #((closure and closure.upvalues) or {}) > 0 then
    for i, up in ipairs(closure.upvalues or {}) do
      if cls(up) ~= RT.UpvalueIdentity then add(errors, "static CALL upvalue " .. i .. " is not represented by UpvalueIdentity") end
    end
  end
  if cls(resolved.target) ~= RT.DirectLuaClosureTarget then add(errors, "source CALL target must be DirectLuaClosureTarget, got " .. tostring(kind(resolved.target))) end
  if kind(resolved.identity) ~= "LuaClosureTargetIdentity" then add(errors, "source CALL identity must be LuaClosureTargetIdentity, got " .. tostring(kind(resolved.identity))) end
  if kind(resolved.callable) ~= "CallableLuaClosure" then add(errors, "source CALL callable must be CallableLuaClosure, got " .. tostring(kind(resolved.callable))) end
  if cls(resolved.target) == RT.DirectLuaClosureTarget and resolved.target.closure ~= closure.closure then add(errors, "source CALL resolved closure does not match ClosureIdentity") end
  if kind(resolved.identity) == "LuaClosureTargetIdentity" then
    if resolved.identity.closure ~= closure.closure then add(errors, "source CALL identity closure does not match ClosureIdentity") end
    if resolved.identity.proto.id ~= closure.proto.proto.id then add(errors, "source CALL identity proto does not match ClosureIdentity proto") end
    if type(resolved.identity.closure_handle) ~= "number" or resolved.identity.closure_handle < 0 then add(errors, "source CALL invalid closure handle") end
  end

  local binding_ok, binding_errors = StaticRegion.validate_static_region_binding(region_payload.binding)
  if not binding_ok then for _, e in ipairs(binding_errors) do add(errors, "static binding " .. e) end end
  local region = region_payload.region
  local binding = region_payload.binding
  if region and binding then
    if region.id.text ~= region_ref_key(binding.region) then add(errors, "static binding region id does not match supplied region") end
    if region.id.text ~= region_id_key(binding.descriptor.id) then add(errors, "static binding descriptor id does not match supplied region") end
    if region.kind ~= binding.descriptor.kind then add(errors, "static binding descriptor kind does not match supplied region") end
  end
  validate_target_region(region, errors)
  return #errors == 0, errors
end

local function frame_ref(name) return RT.FrameRef(rtname(name)) end
local function stack_value(frame, sid) return RT.StackValue(frame, RT.Slot(sid)) end
local function fixed_count(n) return RT.FixedCount(n) end
local function exact_shape(n)
  return RT.ArityShape(fixed_count(n), fixed_count(n), RT.ExactCount(RT.Count(n)), RT.FixedArity)
end

local function build_products_uncached(call_op, payloads, opts)
  opts = opts or {}
  local target_payload, region_payload = payloads and payloads.target, payloads and payloads.region
  local ok, errors = M.validate_static_call_slice(call_op, target_payload, region_payload)
  if not ok then return nil, errors end

  local pc = pc_id(call_op.pc)
  local base = slot_id(call_op.base)
  local arg_count = src_count(call_op.nargs) - 1
  local result_count = src_count(call_op.nresults) - 1
  local caller = opts.caller_frame or frame_ref("frame0")
  local callee = opts.callee_frame or frame_ref("call_" .. tostring(pc) .. "_callee")
  local call = target_payload.target.call
  local callee_ref = stack_value(caller, base)

  local arg_window = RT.StackWindow(RT.CallWindow, caller, RT.Slot(base + 1), fixed_count(arg_count))
  local arg_seq = RT.ValueSeq(RT.FixedSeq, {}, fixed_count(arg_count), RT.FromStackWindow(arg_window))
  local arg_shape = exact_shape(arg_count)
  local arg_channel = RT.CallArgChannel(call, arg_seq, arg_shape)

  local result_window = RT.StackWindow(RT.ReturnWindow, callee, RT.Slot(base), fixed_count(result_count))
  local result_seq = RT.ValueSeq(RT.CallResultSeq, {}, fixed_count(result_count), RT.FromCallResult(call))
  local result_destination = RT.StackWindowDestination(RT.StackWindow(RT.ReturnWindow, caller, RT.Slot(base), fixed_count(result_count)))
  local result_channel = Arity.result_channel(RT.StackWindowRoute, rtname("call_" .. tostring(pc) .. "_results"), result_destination, fixed_count(result_count))
  local result_shape = exact_shape(result_count)
  local result_norm = RT.ArityNormalization(result_seq, result_shape, RT.ResultBundle(result_seq, result_channel), {
    RT.FrameEffect(RT.StoreSeqEffect, caller, result_destination.window, fixed_count(result_count)),
  })
  local call_result = RT.CallResultChannel(call, result_channel, result_norm)

  local layout = RT.CallFrameLayout(
    RT.CallFrameRef(rtname("call_" .. tostring(pc) .. "_frame")),
    caller,
    callee,
    RT.Slot(base),
    RT.Slot(0),
    fixed_count(arg_count),
    RT.Slot(base),
    fixed_count(result_count),
    RT.Count(math.max(base + result_count + 1, arg_count + result_count + 4))
  )
  local frame_state = RT.CallFrameState(call, layout, arg_channel, call_result, target_payload.target, RT.CallFrameUnprepared)
  local shape = RT.CallShape(call, callee_ref, arg_window, fixed_count(result_count), RT.NotTailCall, RT.NonYieldingCall)

  local return_cont = Exec.ContRef(ename(opts.return_cont or "ret_" .. tostring(pc)))
  local error_cont = Exec.ContRef(ename(opts.error_cont or "err_" .. tostring(pc)))
  local yield_cont = Exec.ContRef(ename(opts.yield_cont or "yield_" .. tostring(pc)))
  local call_cont = Exec.CallContinuationRegion(call, region_payload.binding.region, return_cont, error_cont, yield_cont)
  local cont_binding = Exec.ContBinding(return_cont, opts.return_block_ref, opts.return_args or {})
  local invocation = Exec.StaticRegionInvocation(ename(opts.invocation_name or "invoke_call_" .. tostring(pc)), region_payload.binding, {}, { cont_binding }, call_cont)

  return Exec.StaticCallProducts(
    call,
    shape,
    target_payload.closure,
    target_payload.target,
    arg_channel,
    call_result,
    result_channel,
    result_norm,
    layout,
    frame_state,
    call_cont,
    invocation,
    region_payload.binding,
    region_payload.region,
    callee,
    caller,
    base,
    result_count,
    arg_count
  ), nil
end

local product_phase = pvm.phase("spongejit_lua_src_call_static_products", function(call_op, evidence, return_block_ref, return_args)
  local payloads, payload_errors = M.find_static_call_payloads(evidence, call_op)
  if not payloads then return Exec.StaticCallProductsReject(payload_errors or { "source_call_missing_static_evidence" }) end
  local products, errors = build_products_uncached(call_op, payloads, { return_block_ref = return_block_ref, return_args = return_args or {} })
  if not products then return Exec.StaticCallProductsReject(errors or { "source_call_products_failed" }) end
  return Exec.StaticCallProductsOk(products)
end, { args_cache = "last" })

function M.products(call_op, evidence, return_block_ref, return_args)
  local result = pvm.one(product_phase(call_op, evidence, return_block_ref, return_args or {}))
  if pvm.classof(result) == Exec.StaticCallProductsReject then return nil, result.errors end
  return result.products, nil
end

function M.build_call_products(call_op, payloads, opts)
  -- Compatibility wrapper for tests/helpers that already performed payload lookup;
  -- meaningful source-lowering callers should use M.products so construction is
  -- recorded at the PVM boundary.
  return build_products_uncached(call_op, payloads, opts)
end

M.phase = product_phase
M.build_call_products_uncached = build_products_uncached

return M
