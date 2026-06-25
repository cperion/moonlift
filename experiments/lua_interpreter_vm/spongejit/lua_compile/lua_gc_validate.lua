-- lua_compile/lua_gc_validate.lua -- structural checks for first-class LuaGC ASDL.
--
-- These validators make GC metadata explicit and fail closed on malformed
-- state/facts. They do not implement allocation, tracing, barriers,
-- finalization, weak processing, or a collector algorithm.

local pvm = require("lalin.pvm")
local B = require("lua_compile.builders")
local T = B.T
local GC = T.LuaGC

local M = {}

local function add(errors, msg) errors[#errors + 1] = msg end
local function cls(v) return pvm.classof(v) end
local function is(v, c) return cls(v) == c or v == c end
local function is_member(sum, v)
  return v ~= nil and sum and sum.members and sum.members[cls(v)] or false
end
local function nonneg(n) return type(n) == "number" and n >= 0 end
local function positive(n) return type(n) == "number" and n > 0 end
local function is_no_ref(ref) return is(ref, GC.NoGCRef) end

local function validate_ref(ref, errors, where)
  where = where or "gc_ref"
  if not is_member(GC.GCRef, ref) then
    add(errors, where .. " must be LuaGC.GCRef")
  elseif is(ref, GC.SomeGCRef) and not is(ref.object, GC.GCObjectRef) then
    add(errors, where .. " object must be GCObjectRef")
  end
end

function M.header(header)
  local errors = {}
  if not is(header, GC.GCHeader) then add(errors, "expected LuaGC.GCHeader"); return false, errors end
  if not is(header.object, GC.GCObjectRef) then add(errors, "header.object must be GCObjectRef") end
  validate_ref(header.next, errors, "header.next")
  if not is_member(GC.GCObjectKind, header.kind) then add(errors, "header.kind must be GCObjectKind") end
  if not is_member(GC.GCColor, header.color) then add(errors, "header.color must be GCColor") end
  if not nonneg(header.flags) then add(errors, "header.flags must be >= 0") end
  if not nonneg(header.epoch) then add(errors, "header.epoch must be >= 0") end
  return #errors == 0, errors
end

local function validate_limits(limits, errors)
  if not is(limits, GC.GCLimits) then add(errors, "state.limits must be GCLimits"); return end
  if not nonneg(limits.pause_debt) then add(errors, "limits.pause_debt must be >= 0") end
  if not nonneg(limits.step_multiplier) then add(errors, "limits.step_multiplier must be >= 0") end
  if not nonneg(limits.emergency_threshold) then add(errors, "limits.emergency_threshold must be >= 0") end
end

local function validate_lists(lists, errors)
  if not is(lists, GC.GCLists) then add(errors, "state.lists must be GCLists"); return end
  for _, field in ipairs({ "all", "gray", "gray_again", "weak_tables", "ephemeron_tables", "finalizable", "to_finalize" }) do
    validate_ref(lists[field], errors, "lists." .. field)
  end
end

local function validate_allocator(allocator, errors)
  if not is(allocator, GC.Allocator) then add(errors, "state.allocator must be Allocator"); return end
  for _, field in ipairs({ "ctx", "alloc_fn", "realloc_fn", "free_fn" }) do
    if not is(allocator[field], GC.Name) or tostring(allocator[field].text or "") == "" then
      add(errors, "allocator." .. field .. " must be non-empty LuaGC.Name")
    end
  end
end

function M.gc_state(state)
  local errors = {}
  if not is(state, GC.GCState) then add(errors, "expected LuaGC.GCState"); return false, errors end
  if not is_member(GC.GCPhase, state.phase) then add(errors, "state.phase must be GCPhase") end
  if not is_member(GC.GCColor, state.current_white) then add(errors, "state.current_white must be GCColor") end
  validate_lists(state.lists, errors)
  if not nonneg(state.total_bytes) then add(errors, "state.total_bytes must be >= 0") end
  if type(state.debt) ~= "number" then add(errors, "state.debt must be numeric") end
  validate_limits(state.limits, errors)
  if not nonneg(state.global_epoch) then add(errors, "state.global_epoch must be >= 0") end
  if not nonneg(state.barrier_epoch) then add(errors, "state.barrier_epoch must be >= 0") end
  validate_allocator(state.allocator, errors)
  return #errors == 0, errors
end

function M.finalizer_ref(finalizer)
  local errors = {}
  if not is(finalizer, GC.FinalizerRef) then add(errors, "expected LuaGC.FinalizerRef"); return false, errors end
  if not is(finalizer.id, GC.Name) or tostring(finalizer.id.text or "") == "" then add(errors, "finalizer.id must be non-empty LuaGC.Name") end
  if not is_member(GC.FinalizerKind, finalizer.kind) then add(errors, "finalizer.kind must be FinalizerKind") end
  if finalizer.attached and is(finalizer.kind, GC.NoFinalizerKind) then add(errors, "attached finalizer cannot use NoFinalizerKind") end
  return #errors == 0, errors
end

function M.barrier_kind(barrier)
  local errors = {}
  if not is_member(GC.BarrierKind, barrier) then add(errors, "expected LuaGC.BarrierKind"); return false, errors end
  if is(barrier, GC.ObjectToObjectBarrier) then
    validate_ref(barrier.parent, errors, "barrier.parent")
    validate_ref(barrier.child, errors, "barrier.child")
    if is_no_ref(barrier.parent) then add(errors, "object-to-object barrier parent must not be NoGCRef") end
    if is_no_ref(barrier.child) then add(errors, "object-to-object barrier child must not be NoGCRef") end
  elseif is(barrier, GC.TableSlotBarrier) or is(barrier, GC.UpvalueWriteBarrier) or is(barrier, GC.CDataRefBarrier) then
    validate_ref(barrier.child, errors, "barrier.child")
    if is_no_ref(barrier.child) then add(errors, "barrier child must not be NoGCRef") end
  end
  return #errors == 0, errors
end

function M.root_set(root_set)
  local errors = {}
  if not is(root_set, GC.RootSet) then add(errors, "expected LuaGC.RootSet"); return false, errors end
  for i, root in ipairs(root_set.roots or {}) do
    if not is(root, GC.GCRoot) then
      add(errors, "root " .. i .. " must be GCRoot")
    else
      if not is_member(GC.RootKind, root.kind) then add(errors, "root " .. i .. " kind must be RootKind") end
      validate_ref(root.value, errors, "root " .. i .. ".value")
      if is_no_ref(root.value) then add(errors, "root " .. i .. " value must not be NoGCRef") end
    end
  end
  return #errors == 0, errors
end

function M.gc_fact(fact)
  local errors = {}
  if not is_member(GC.GCFact, fact) then add(errors, "expected LuaGC.GCFact"); return false, errors end
  if is(fact, GC.BarrierClean) then
    local ok, es = M.barrier_kind(fact.barrier); for _, e in ipairs(es) do add(errors, "barrier_clean: " .. e) end
  elseif is(fact, GC.ObjectEpoch) then
    validate_ref(fact.object, errors, "object_epoch.object")
    if is_no_ref(fact.object) then add(errors, "object_epoch object must not be NoGCRef") end
    if not nonneg(fact.epoch) then add(errors, "object_epoch epoch must be >= 0") end
  elseif is(fact, GC.TableEpoch) then
    if not nonneg(fact.epoch) then add(errors, "table_epoch epoch must be >= 0") end
  elseif is(fact, GC.ShapeEpoch) then
    if tostring(fact.shape_key or "") == "" then add(errors, "shape_epoch shape_key must be non-empty") end
    if not nonneg(fact.epoch) then add(errors, "shape_epoch epoch must be >= 0") end
  elseif is(fact, GC.GCPhaseFact) then
    if not is_member(GC.GCPhase, fact.phase) then add(errors, "gc_phase fact phase invalid") end
  elseif is(fact, GC.NoFinalizerFact) then
    validate_ref(fact.object, errors, "no_finalizer.object")
    if is_no_ref(fact.object) then add(errors, "no_finalizer object must not be NoGCRef") end
  elseif is(fact, GC.FinalizerAttachedFact) then
    validate_ref(fact.object, errors, "finalizer_attached.object")
    local ok, es = M.finalizer_ref(fact.finalizer); for _, e in ipairs(es) do add(errors, "finalizer_attached: " .. e) end
    if fact.finalizer and fact.finalizer.attached ~= true then add(errors, "finalizer_attached fact requires attached FinalizerRef") end
  end
  return #errors == 0, errors
end

return M
