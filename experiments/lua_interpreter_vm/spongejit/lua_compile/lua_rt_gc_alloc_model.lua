-- lua_rt_gc_alloc_model.lua -- LuaGC allocation/root/barrier/finalizer products.
-- Structural validation only; no allocator or collector lowering is introduced here.

local Schema = require("lua_compile.schema")
local pvm = require("lalin.pvm")
local T = Schema.get()
local GC = T.LuaGC
local RT = T.LuaRT

local M = {}
local function cls(v) return pvm.classof(v) end
local function member(v, sum) return v ~= nil and sum and sum.members and sum.members[cls(v)] or false end
local function kind(v) return v and v.kind or nil end
local function add(errors, msg) errors[#errors + 1] = msg end

function M.validate_collectable_object(obj)
  local errors = {}
  if not member(obj, GC.CollectableObject) then add(errors, "expected LuaGC.CollectableObject"); return false, errors end
  return true, errors
end

function M.validate_gc_effect(effect)
  local errors = {}
  if not member(effect, GC.GCEffect) then add(errors, "expected LuaGC.GCEffect"); return false, errors end
  local k = kind(effect)
  if k == "GCAllocationEffect" then
    if cls(effect.request) ~= GC.AllocRequest then add(errors, "request must be LuaGC.AllocRequest") end
    if not member(effect.result, GC.AllocResult) then add(errors, "result must be LuaGC.AllocResult") end
  elseif k == "GCRootEffect" then
    if cls(effect.roots) ~= GC.RootSet then add(errors, "roots must be LuaGC.RootSet") end
  elseif k == "GCBarrierEffect" then
    if not member(effect.barrier, GC.BarrierKind) then add(errors, "barrier must be LuaGC.BarrierKind") end
    if not member(effect.action, GC.BarrierAction) then add(errors, "action must be LuaGC.BarrierAction") end
    if not member(effect.result, GC.BarrierResult) then add(errors, "result must be LuaGC.BarrierResult") end
  elseif k == "GCFinalizerEffect" then
    if cls(effect.request) ~= GC.FinalizerRequest then add(errors, "request must be LuaGC.FinalizerRequest") end
    if not member(effect.result, GC.FinalizerProcessingResult) then add(errors, "result must be LuaGC.FinalizerProcessingResult") end
  elseif k == "GCEpochEffect" then
    if not member(effect.fact, GC.GCFact) then add(errors, "fact must be LuaGC.GCFact") end
  end
  return #errors == 0, errors
end

function M.validate_proto_object(obj)
  local errors = {}
  if cls(obj) ~= GC.ProtoObject then add(errors, "expected LuaGC.ProtoObject"); return false, errors end
  if cls(obj.header) ~= GC.GCHeader then add(errors, "header must be LuaGC.GCHeader") end
  if cls(obj.proto) ~= RT.ProtoRef then add(errors, "proto must be LuaRT.ProtoRef") end
  if type(obj.proto_hash) ~= "string" then add(errors, "proto_hash must be string") end
  return #errors == 0, errors
end

function M.validate_thread_object(obj)
  local errors = {}
  if cls(obj) ~= GC.ThreadObject then add(errors, "expected LuaGC.ThreadObject"); return false, errors end
  if cls(obj.header) ~= GC.GCHeader then add(errors, "header must be LuaGC.GCHeader") end
  if cls(obj.thread) ~= RT.ThreadRef then add(errors, "thread must be LuaRT.ThreadRef") end
  for i, frame in ipairs(obj.frames or {}) do if cls(frame) ~= RT.FrameRef then add(errors, "frames[" .. i .. "] must be LuaRT.FrameRef") end end
  return #errors == 0, errors
end

function M.validate_upvalue_object(obj)
  local errors = {}
  if cls(obj) ~= GC.UpvalueObject then add(errors, "expected LuaGC.UpvalueObject"); return false, errors end
  if cls(obj.header) ~= GC.GCHeader then add(errors, "header must be LuaGC.GCHeader") end
  if cls(obj.identity) ~= RT.UpvalueIdentity then add(errors, "identity must be LuaRT.UpvalueIdentity") end
  if not member(obj.value, RT.ValueRef) then add(errors, "value must be LuaRT.ValueRef") end
  return #errors == 0, errors
end

function M.validate_against_schema()
  local missing = {}
  for _, name in ipairs({
    "GCEffect", "GCAllocationEffect", "GCRootEffect", "GCBarrierEffect", "GCFinalizerEffect", "GCEpochEffect",
    "ProtoObject", "ThreadObject", "UpvalueObject", "GCProtoObject", "GCThreadObject", "GCUpvalueObject",
  }) do
    if GC[name] == nil then missing[#missing + 1] = "LuaGC." .. name end
  end
  table.sort(missing)
  return #missing == 0, missing
end

return M
