-- lua_compile/lua_ffi_validate.lua -- structural checks for first-class LuaFFI ASDL.
--
-- These validators make FFI metadata explicit and fail closed on malformed
-- declarations/layouts. They do not parse C, call LuaJIT FFI, dlopen/dlsym,
-- lower C ABIs, or implement C calls.

local pvm = require("moonlift.pvm")
local B = require("lua_compile.builders")
local T = B.T
local FFI = T.LuaFFI

local M = {}

local function add(errors, msg) errors[#errors + 1] = msg end
local function cls(v) return pvm.classof(v) end
local function is(v, c) return cls(v) == c or v == c end
local function is_member(sum, v)
  return v ~= nil and sum and sum.members and sum.members[cls(v)] or false
end
local function nonneg(n) return type(n) == "number" and n >= 0 end
local function positive(n) return type(n) == "number" and n > 0 end
local function text(n) return n and n.text or "" end

local function is_function_type(t, seen)
  if not t or type(t) ~= "table" then return false end
  seen = seen or {}
  if seen[t] then return false end
  seen[t] = true
  if is(t, FFI.FunctionType) then return true end
  if is(t, FFI.TypedefType) then return is_function_type(t.aliased, seen) end
  return false
end

local function is_complete_type(t, seen)
  if not t or type(t) ~= "table" then return false end
  seen = seen or {}
  if seen[t] then return false end
  seen[t] = true
  if is(t, FFI.ScalarType) or is(t, FFI.PointerType) or is(t, FFI.FunctionType) or is(t, FFI.EnumType) then
    if is(t, FFI.EnumType) then return positive(t.layout and t.layout.align_bytes) and nonneg(t.layout and t.layout.size_bytes) end
    return true
  elseif is(t, FFI.ArrayType) then
    return nonneg(t.count) and positive(t.align_bytes) and nonneg(t.size_bytes) and is_complete_type(t.element, seen)
  elseif is(t, FFI.IncompleteArrayType) or is(t, FFI.OpaqueTagType) then
    return false
  elseif is(t, FFI.StructType) or is(t, FFI.UnionType) then
    return t.layout and t.layout.is_complete == true
  elseif is(t, FFI.TypedefType) then
    return is_complete_type(t.aliased, seen)
  end
  return false
end

local function validate_ctype_into(t, errors, where, seen)
  where = where or "ctype"
  if not is_member(FFI.CType, t) then add(errors, where .. " must be LuaFFI.CType"); return end
  seen = seen or {}
  if seen[t] then return end
  seen[t] = true

  if is(t, FFI.ScalarType) then
    if not is(t.id, FFI.CTypeId) then add(errors, where .. " scalar id must be CTypeId") end
    if not is_member(FFI.CScalarKind, t.kind) then add(errors, where .. " scalar kind invalid") end
    if not is_member(FFI.CSignedness, t.signedness) then add(errors, where .. " signedness invalid") end
    if not nonneg(t.size_bytes) then add(errors, where .. " scalar size_bytes must be >= 0") end
    if not nonneg(t.align_bytes) then add(errors, where .. " scalar align_bytes must be >= 0") end
    if t.size_bytes > 0 and t.align_bytes <= 0 then add(errors, where .. " non-void scalar align_bytes must be > 0") end
  elseif is(t, FFI.PointerType) then
    validate_ctype_into(t.pointee, errors, where .. ".pointee", seen)
  elseif is(t, FFI.ArrayType) then
    if not nonneg(t.count) then add(errors, where .. " array count must be >= 0") end
    if not nonneg(t.size_bytes) then add(errors, where .. " array size_bytes must be >= 0") end
    if not positive(t.align_bytes) then add(errors, where .. " array align_bytes must be > 0") end
    validate_ctype_into(t.element, errors, where .. ".element", seen)
    if not is_complete_type(t.element) then add(errors, where .. " array element type must be complete") end
  elseif is(t, FFI.IncompleteArrayType) then
    validate_ctype_into(t.element, errors, where .. ".element", seen)
  elseif is(t, FFI.FunctionType) then
    validate_ctype_into(t.return_type, errors, where .. ".return_type", seen)
    if not is(t.params, FFI.CParamList) then add(errors, where .. " params must be CParamList")
    else
      for i, p in ipairs(t.params.params or {}) do
        if not is(p, FFI.CParam) then add(errors, where .. " param " .. i .. " must be CParam")
        else
          validate_ctype_into(p.type, errors, where .. ".param" .. i, seen)
          if not is_member(FFI.CParamMode, p.mode) then add(errors, where .. " param " .. i .. " mode invalid") end
        end
      end
    end
  elseif is(t, FFI.StructType) or is(t, FFI.UnionType) then
    if not is(t.layout, FFI.CRecordLayout) then add(errors, where .. " layout must be CRecordLayout")
    else M.record_layout(t.layout, errors, where .. ".layout") end
  elseif is(t, FFI.EnumType) then
    if not is(t.layout, FFI.CEnumLayout) then add(errors, where .. " layout must be CEnumLayout")
    else M.enum_layout(t.layout, errors, where .. ".layout") end
  elseif is(t, FFI.TypedefType) then
    validate_ctype_into(t.aliased, errors, where .. ".aliased", seen)
  elseif is(t, FFI.OpaqueTagType) then
    -- Opaque tags are intentionally incomplete until a later declaration resolves them.
  end
end

function M.ctype(t)
  local errors = {}
  validate_ctype_into(t, errors, "ctype")
  return #errors == 0, errors
end

function M.record_layout(layout, errors, where)
  local own = errors == nil
  errors = errors or {}
  where = where or "record_layout"
  if not is(layout, FFI.CRecordLayout) then add(errors, where .. " must be LuaFFI.CRecordLayout"); return false, errors end
  if layout.is_complete then
    if not nonneg(layout.size_bytes) then add(errors, where .. " complete size_bytes must be >= 0") end
    if not positive(layout.align_bytes) then add(errors, where .. " complete align_bytes must be > 0") end
    if tostring(layout.layout_hash or "") == "" then add(errors, where .. " complete layout_hash must be non-empty") end
  else
    if (layout.size_bytes or 0) ~= 0 or (layout.align_bytes or 0) ~= 0 or #(layout.fields or {}) ~= 0 then
      add(errors, where .. " incomplete layout cannot carry complete size/align/fields")
    end
  end
  local saw_flexible = false
  for i, field in ipairs(layout.fields or {}) do
    if not is(field, FFI.CField) then add(errors, where .. " field " .. i .. " must be CField")
    else
      if saw_flexible then add(errors, where .. " flexible array member must be last") end
      if not is_member(FFI.CFieldKind, field.kind) then add(errors, where .. " field " .. i .. " kind invalid") end
      if not nonneg(field.offset_bits) then add(errors, where .. " field " .. i .. " offset_bits must be >= 0") end
      if is(field.kind, FFI.BitField) and not positive(field.width_bits) then add(errors, where .. " bitfield " .. i .. " width_bits must be > 0") end
      if is(field.kind, FFI.FlexibleArrayMember) then
        saw_flexible = true
        if field.width_bits ~= 0 then add(errors, where .. " flexible array member width_bits must be 0") end
      elseif not nonneg(field.width_bits) then
        add(errors, where .. " field " .. i .. " width_bits must be >= 0")
      end
      validate_ctype_into(field.type, errors, where .. ".field" .. i)
      if not is(field.kind, FFI.FlexibleArrayMember) and not is_complete_type(field.type) then add(errors, where .. " field " .. i .. " type must be complete") end
    end
  end
  if own then return #errors == 0, errors end
end

function M.enum_layout(layout, errors, where)
  local own = errors == nil
  errors = errors or {}
  where = where or "enum_layout"
  if not is(layout, FFI.CEnumLayout) then add(errors, where .. " must be LuaFFI.CEnumLayout"); return false, errors end
  if not is_member(FFI.CScalarKind, layout.repr) then add(errors, where .. " repr invalid") end
  if not nonneg(layout.size_bytes) then add(errors, where .. " size_bytes must be >= 0") end
  if not positive(layout.align_bytes) then add(errors, where .. " align_bytes must be > 0") end
  for i, item in ipairs(layout.items or {}) do
    if not is(item, FFI.CEnumItem) then add(errors, where .. " item " .. i .. " must be CEnumItem") end
  end
  if own then return #errors == 0, errors end
end

function M.symbol(symbol)
  local errors = {}
  if not is(symbol, FFI.CSymbol) then add(errors, "expected LuaFFI.CSymbol"); return false, errors end
  if not is_member(FFI.CSymbolKind, symbol.kind) then add(errors, "symbol kind invalid") end
  validate_ctype_into(symbol.type, errors, "symbol.type")
  if is(symbol.kind, FFI.FunctionSymbol) or is(symbol.kind, FFI.CallbackSymbol) then
    if not is_function_type(symbol.type) then add(errors, "function/callback symbol must have FunctionType signature") end
  elseif is(symbol.kind, FFI.DataSymbol) and is_function_type(symbol.type) then
    add(errors, "data symbol must not have FunctionType")
  end
  if symbol.resolved and tostring(symbol.address_key or "") == "" then add(errors, "resolved symbol requires address_key") end
  return #errors == 0, errors
end

function M.cdata(cdata)
  local errors = {}
  if not is(cdata, FFI.CData) then add(errors, "expected LuaFFI.CData"); return false, errors end
  validate_ctype_into(cdata.type, errors, "cdata.type")
  if not is_member(FFI.CStorage, cdata.storage) then add(errors, "cdata.storage must be CStorage")
  else
    local storage = cdata.storage
    local complete_required = is(storage, FFI.InlineStorage) or is(storage, FFI.OwnedHeapStorage) or is(storage, FFI.StaticSymbolStorage)
    if complete_required and not is_complete_type(cdata.type) then add(errors, "complete ctype required for inline/owned/static cdata storage") end
    if storage.byte_size and storage.byte_size < 0 then add(errors, "cdata storage byte_size must be >= 0") end
    if is(storage, FFI.StaticSymbolStorage) then
      local ok, serr = M.symbol(storage.symbol)
      for _, e in ipairs(serr) do add(errors, "static storage symbol: " .. e) end
    end
  end
  if not is_member(FFI.CFinalizer, cdata.finalizer) then add(errors, "cdata.finalizer must be CFinalizer") end
  if not is_member(FFI.OwnershipState, cdata.ownership) then add(errors, "cdata.ownership must be OwnershipState") end
  return #errors == 0, errors
end

function M.callback(callback)
  local errors = {}
  if not is(callback, FFI.CCallback) then add(errors, "expected LuaFFI.CCallback"); return false, errors end
  validate_ctype_into(callback.function_type, errors, "callback.function_type")
  if not is_function_type(callback.function_type) then add(errors, "callback.function_type must be FunctionType") end
  if callback.live and tostring(callback.thunk_key or "") == "" then add(errors, "live callback requires thunk_key") end
  return #errors == 0, errors
end

function M.ffi_call_shape(call)
  local errors = {}
  if not is(call, FFI.FFICallShape) then add(errors, "expected LuaFFI.FFICallShape"); return false, errors end
  if not is(call.symbol, FFI.CSymbolId) then add(errors, "symbol must be CSymbolId") end
  if not is_member(FFI.CAbi, call.abi) then add(errors, "abi must be CAbi") end
  if not is(call.params, FFI.CParamList) then add(errors, "params must be CParamList") end
  validate_ctype_into(call.return_type, errors, "return_type")
  for i, conv in ipairs(call.conversions or {}) do
    if not is_member(FFI.CValueConversion, conv) then add(errors, "conversions[" .. i .. "] must be CValueConversion") end
  end
  return #errors == 0, errors
end

function M.cdata_ownership_transition(transition)
  local errors = {}
  if not is(transition, FFI.CDataOwnershipTransition) then add(errors, "expected LuaFFI.CDataOwnershipTransition"); return false, errors end
  local ok, cdata_errors = M.cdata(transition.cdata)
  if not ok then for _, e in ipairs(cdata_errors) do add(errors, "cdata " .. e) end end
  if not is_member(FFI.OwnershipState, transition.from_state) then add(errors, "from_state must be OwnershipState") end
  if not is_member(FFI.OwnershipState, transition.to_state) then add(errors, "to_state must be OwnershipState") end
  return #errors == 0, errors
end

function M.ffi_callback_entry(entry)
  local errors = {}
  if not is(entry, FFI.FFICallbackEntry) then add(errors, "expected LuaFFI.FFICallbackEntry"); return false, errors end
  if not is(entry.callback, FFI.CCallbackId) then add(errors, "callback must be CCallbackId") end
  if not is_member(FFI.CAbi, entry.abi) then add(errors, "abi must be CAbi") end
  return #errors == 0, errors
end

function M.registry(registry)
  local errors = {}
  if not is(registry, FFI.FFIRegistry) then add(errors, "expected LuaFFI.FFIRegistry"); return false, errors end
  for i, t in ipairs(registry.types or {}) do local ok, es = M.ctype(t); for _, e in ipairs(es) do add(errors, "type " .. i .. ": " .. e) end end
  for i, r in ipairs(registry.records or {}) do local ok, es = M.record_layout(r); for _, e in ipairs(es) do add(errors, "record " .. i .. ": " .. e) end end
  for i, e in ipairs(registry.enums or {}) do local ok, es = M.enum_layout(e); for _, msg in ipairs(es) do add(errors, "enum " .. i .. ": " .. msg) end end
  for i, sym in ipairs(registry.symbols or {}) do local ok, es = M.symbol(sym); for _, e in ipairs(es) do add(errors, "symbol " .. i .. ": " .. e) end end
  for i, data in ipairs(registry.cdata or {}) do local ok, es = M.cdata(data); for _, e in ipairs(es) do add(errors, "cdata " .. i .. ": " .. e) end end
  for i, cb in ipairs(registry.callbacks or {}) do local ok, es = M.callback(cb); for _, e in ipairs(es) do add(errors, "callback " .. i .. ": " .. e) end end
  return #errors == 0, errors
end

return M
