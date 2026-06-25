-- lua_rt_closure_upvalue_model.lua -- closure/proto/upvalue identity validation.
-- Structural only; allocation, lifetime transitions, and close execution remain fail-closed.

local Schema = require("lua_compile.schema")
local pvm = require("lalin.pvm")
local T = Schema.get()
local RT, GC = T.LuaRT, T.LuaGC

local M = {}
local function cls(v) return pvm.classof(v) end
local function member(v, sum) return v ~= nil and sum and sum.members and sum.members[cls(v)] or false end
local function add(errors, msg) errors[#errors + 1] = msg end

function M.validate_upvalue_identity(identity)
  local errors = {}
  if cls(identity) ~= RT.UpvalueIdentity then add(errors, "expected LuaRT.UpvalueIdentity"); return false, errors end
  if cls(identity.upvalue) ~= RT.UpvalueRef then add(errors, "upvalue must be LuaRT.UpvalueRef") end
  if cls(identity.proto) ~= RT.ProtoRef then add(errors, "proto must be LuaRT.ProtoRef") end
  if cls(identity.owner) ~= RT.ClosureRef then add(errors, "owner must be LuaRT.ClosureRef") end
  if cls(identity.frame) ~= RT.FrameRef then add(errors, "frame must be LuaRT.FrameRef") end
  if cls(identity.captured_slot) ~= RT.Slot then add(errors, "captured_slot must be LuaRT.Slot") end
  if not member(identity.storage, RT.UpvalueStorageKind) then add(errors, "storage must be LuaRT.UpvalueStorageKind") end
  if type(identity.close_epoch) ~= "number" then add(errors, "close_epoch must be number") end
  if type(identity.alias_epoch) ~= "number" then add(errors, "alias_epoch must be number") end
  return #errors == 0, errors
end

function M.validate_closure_identity(identity)
  local errors = {}
  if cls(identity) ~= RT.ClosureIdentity then add(errors, "expected LuaRT.ClosureIdentity"); return false, errors end
  if cls(identity.closure) ~= RT.ClosureRef then add(errors, "closure must be LuaRT.ClosureRef") end
  if cls(identity.proto) ~= RT.ProtoRef then add(errors, "proto must be LuaRT.ProtoRef") end
  for i, upvalue in ipairs(identity.upvalues or {}) do
    local ok, errs = M.validate_upvalue_identity(upvalue)
    if not ok then for _, e in ipairs(errs) do add(errors, "upvalues[" .. i .. "] " .. e) end end
  end
  if type(identity.closure_epoch) ~= "number" then add(errors, "closure_epoch must be number") end
  return #errors == 0, errors
end

function M.validate_against_schema()
  local missing = {}
  for _, name in ipairs({
    "ProtoRef", "ClosureRef", "UpvalueRef", "ClosureValue", "LuaClosureValue", "CClosureValue", "UpvalueValue",
    "UpvalueStorageKind", "OpenStackUpvalue", "ClosedHeapUpvalue", "DeadUpvalue",
    "UpvalueIdentity", "ClosureIdentity",
  }) do
    if RT[name] == nil then missing[#missing + 1] = "LuaRT." .. name end
  end
  for _, name in ipairs({ "LClosure", "UpvalueKind", "UpvalueWriteBarrier", "ProtoObject", "ThreadObject", "UpvalueObject" }) do
    if GC[name] == nil then missing[#missing + 1] = "LuaGC." .. name end
  end
  table.sort(missing)
  return #missing == 0, missing
end

return M
