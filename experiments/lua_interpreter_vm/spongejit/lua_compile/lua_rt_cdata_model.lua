-- lua_rt_cdata_model.lua -- executable cdata scalar buffer substrate.
--
-- LuaRTValue with CDataTag carries a non-negative handle into a LuaRTCData
-- bank supplied explicitly as a kernel parameter.  LuaRTCData is materialized
-- runtime data only: typed scalar data pointers plus semantic metadata already
-- represented by LuaFFI ASDL (type id, ownership, finalizer, metatype).  There
-- is no C parser, dynamic lookup, callback execution, or FFI helper dispatch
-- here.

local Schema = require("lua_compile.schema")
local pvm = require("lalin.pvm")
local T = Schema.get()
local FFI = T.LuaFFI

local M = {}
local function cls(v) return pvm.classof(v) end
local function member(v, sum) return v ~= nil and sum and sum.members and sum.members[cls(v)] or false end

M.TYPE_NAME = "LuaRTCData"

M.OWNERSHIP = {
  BorrowedOwnership = 0,
  OwnedOwnership = 1,
  ReleasedOwnership = 2,
  FinalizerAttachedOwnership = 3,
  FinalizerRunningOwnership = 4,
  FinalizedOwnership = 5,
}

M.FINALIZER = {
  NoFinalizer = 0,
  CFunctionFinalizer = 1,
  LuaCallableFinalizer = 2,
}

M.SCALAR = {
  CInt32 = { width = 4, align = 4, lalin_type = "i32", lua_tag = "IntegerTag" },
  CInt64 = { width = 8, align = 8, lalin_type = "i64", lua_tag = "IntegerTag" },
  CDouble = { width = 8, align = 8, lalin_type = "f64", lua_tag = "FloatTag" },
}

-- The bank uses typed scalar pointers instead of an opaque ptr(u8) helper.
-- Offsets are still byte offsets and must pass explicit type/size guards;
-- the typed pointer selected here is the direct executable scalar view.
M.TYPE_DECL = table.concat({
  "struct " .. M.TYPE_NAME,
  "  data_i32: ptr(i32); data_i64: ptr(i64); data_f64: ptr(f64);",
  "  size_bytes: i64; type_id: i64; ownership_kind: i64; finalizer_kind: i64; metatype: i64",
  "end",
}, "\n")

local function scalar_name(scalar)
  return scalar and scalar.kind or tostring(scalar)
end

function M.scalar_info(scalar)
  local name = scalar_name(scalar)
  return M.SCALAR[name]
end

function M.ownership_value(name)
  local v = M.OWNERSHIP[name]
  assert(v ~= nil, "unknown cdata ownership kind: " .. tostring(name))
  return v
end

function M.finalizer_value(name)
  local v = M.FINALIZER[name]
  assert(v ~= nil, "unknown cdata finalizer kind: " .. tostring(name))
  return v
end

function M.validate_ownership_transition(transition)
  local errors = {}
  if cls(transition) ~= FFI.CDataOwnershipTransition then errors[#errors + 1] = "expected LuaFFI.CDataOwnershipTransition"; return false, errors end
  if cls(transition.cdata) ~= FFI.CData then errors[#errors + 1] = "cdata must be LuaFFI.CData" end
  if not member(transition.from_state, FFI.OwnershipState) then errors[#errors + 1] = "from_state must be LuaFFI.OwnershipState" end
  if not member(transition.to_state, FFI.OwnershipState) then errors[#errors + 1] = "to_state must be LuaFFI.OwnershipState" end
  return #errors == 0, errors
end

function M.validate_against_schema()
  local missing = {}
  for _, name in ipairs({ "FFICallShape", "FFICallbackEntry", "CDataOwnershipTransition", "CValueConversion" }) do
    if FFI[name] == nil then missing[#missing + 1] = "LuaFFI." .. name end
  end
  table.sort(missing)
  return #missing == 0, missing
end

return M
