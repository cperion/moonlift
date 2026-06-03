-- lua_rt_object_model.lua -- executable string/table object substrate.
--
-- This is a deliberately explicit Moonlift layout for the LuaRT string/table
-- handle model used by LuaExec/MoonCFG. LuaRTValue ref payloads carry integer
-- handles into the string/table banks supplied as kernel parameters.
--
-- Strings:
--   * non-negative payload_i64 indexes LuaRTString[];
--   * negative payload_i64 is a deterministic synthetic concat handle whose
--     byte length is -payload_i64. This avoids pretending allocation exists
--     while keeping concat results observable and typed.
--   * numeric_kind/numeric_i64/numeric_f64 are explicit parse metadata for the
--     bounded arithmetic coercion slice. They model a pre-parsed string bank,
--     not a hidden parser helper. Supported executable subset: decimal integer
--     strings and decimal float strings supplied with matching metadata.
-- Tables:
--   * payload_i64 indexes LuaRTTable[];
--   * this executable substrate supports raw array-part get/set by integer key
--     and raw hash-part get/set over explicit LuaRTTableHashEntry storage for
--     integer keys outside the array range and string keys;
--   * metatable_kind is explicit data. 0 means no metatable. Non-zero
--     metatable/callable paths must be represented by LuaExec regions before
--     accepted full semantic kernels may use them.
--   * GC barrier metadata is executable substrate data, not a helper call:
--       gc_color/gc_generation decide whether a collectable child write needs
--       a barrier; barrier_count/last_* record the explicit barrier effect.

local M = {}

M.STRING_TYPE_NAME = "LuaRTString"
M.TABLE_TYPE_NAME = "LuaRTTable"
M.RAW_GET_TYPE_NAME = "LuaRTRawGetResult"
M.HASH_ENTRY_TYPE_NAME = "LuaRTTableHashEntry"

M.HASH_ENTRY_STATE = {
  Empty = 0,
  Occupied = 1,
  Tombstone = 2,
}

-- The current MoonCFG emitter emits a bounded, explicit, unrolled probe over
-- this many hash entries. Tables with larger hash_capacity are treated as
-- malformed for raw SETTABLE (typed RuntimeError) until dynamic block-loop
-- table regions are introduced.
M.HASH_PROBE_LIMIT = 8

M.GC_COLOR = {
  White0 = 0,
  White1 = 1,
  Gray = 2,
  Black = 3,
  Fixed = 4,
  Dead = 5,
}

M.GC_GENERATION = {
  Young = 0,
  Old = 1,
}

M.METATABLE_KIND = {
  NoMetatable = 0,
  IndexTable = 1,
  IndexFunction = 2,
  NewIndexTable = 3,
  NewIndexFunction = 4,
  LenFunction = 5,
  ConcatFunction = 6,
}

M.STRING_NUMERIC_KIND = {
  NotNumeric = 0,
  DecimalInteger = 1,
  DecimalFloat = 2,
}

M.TYPE_DECL = table.concat({
  "struct " .. M.STRING_TYPE_NAME .. " byte_len: i64; hash: i64; numeric_kind: i64; numeric_i64: i64; numeric_f64: f64 end",
  "struct " .. M.HASH_ENTRY_TYPE_NAME .. " state: i64; key: LuaRTValue; value: LuaRTValue end",
  "struct " .. M.TABLE_TYPE_NAME .. " array: ptr(LuaRTValue); array_len: i64; hash: ptr(" .. M.HASH_ENTRY_TYPE_NAME .. "); hash_capacity: i64; hash_count: i64; metatable_kind: i64; index_table: i64; newindex_table: i64; gc_color: i64; gc_generation: i64; gc_epoch: i64; barrier_epoch: i64; barrier_count: i64; barrier_last_child_tag: i64; barrier_last_child_payload: i64 end",
  "struct " .. M.RAW_GET_TYPE_NAME .. " hit: bool; value: LuaRTValue end",
}, "\n")

function M.hash_entry_state_value(name)
  local v = M.HASH_ENTRY_STATE[name]
  assert(v ~= nil, "unknown LuaRT hash entry state: " .. tostring(name))
  return v
end

function M.metatable_kind_value(name)
  local v = M.METATABLE_KIND[name]
  assert(v ~= nil, "unknown LuaRT metatable kind: " .. tostring(name))
  return v
end

function M.string_numeric_kind_value(name)
  local v = M.STRING_NUMERIC_KIND[name]
  assert(v ~= nil, "unknown LuaRT string numeric kind: " .. tostring(name))
  return v
end

function M.gc_color_value(name)
  local v = M.GC_COLOR[name]
  assert(v ~= nil, "unknown LuaRT GC color: " .. tostring(name))
  return v
end

function M.gc_generation_value(name)
  local v = M.GC_GENERATION[name]
  assert(v ~= nil, "unknown LuaRT GC generation: " .. tostring(name))
  return v
end

return M
