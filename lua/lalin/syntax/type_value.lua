-- lalin.syntax.type_value
-- Projects evaluated Lua type values into the active parsed-module context.

local pvm = require("lalin.pvm")

local function bind_context(T)
  if not T.LalinCore then require("lalin.schema_projection")(T) end
  local C, Ty, CT = T.LalinCore, T.LalinType, T.LalinC
  local M = {}

  local function class_name(value)
    local cls = pvm.classof(value)
    if not cls then return nil end
    return tostring(cls):match("^Class%((.-)%)$")
  end

  local scalar = {
    ["LalinCore.ScalarVoid"] = C.ScalarVoid,
    ["LalinCore.ScalarBool"] = C.ScalarBool,
    ["LalinCore.ScalarI8"] = C.ScalarI8,
    ["LalinCore.ScalarI16"] = C.ScalarI16,
    ["LalinCore.ScalarI32"] = C.ScalarI32,
    ["LalinCore.ScalarI64"] = C.ScalarI64,
    ["LalinCore.ScalarU8"] = C.ScalarU8,
    ["LalinCore.ScalarU16"] = C.ScalarU16,
    ["LalinCore.ScalarU32"] = C.ScalarU32,
    ["LalinCore.ScalarU64"] = C.ScalarU64,
    ["LalinCore.ScalarF32"] = C.ScalarF32,
    ["LalinCore.ScalarF64"] = C.ScalarF64,
    ["LalinCore.ScalarIndex"] = C.ScalarIndex,
    ["LalinCore.ScalarRawPtr"] = C.ScalarRawPtr,
  }

  local access = {
    ["LalinType.TypeAccessNoAlias"] = Ty.TypeAccessNoAlias,
    ["LalinType.TypeAccessReadonly"] = Ty.TypeAccessReadonly,
    ["LalinType.TypeAccessWriteonly"] = Ty.TypeAccessWriteonly,
    ["LalinType.TypeAccessNoEscape"] = Ty.TypeAccessNoEscape,
    ["LalinType.TypeAccessInvalidate"] = Ty.TypeAccessInvalidate,
    ["LalinType.TypeAccessPreserve"] = Ty.TypeAccessPreserve,
  }

  local lease_origin = {
    ["LalinType.LeaseOriginUnknown"] = Ty.LeaseOriginUnknown,
  }

  local function scalar_value(value)
    local out = scalar[class_name(value)]
    if out == nil then error("evaluated type uses unsupported scalar value " .. tostring(value), 3) end
    return out
  end

  local function access_value(value)
    local out = access[class_name(value)]
    if out == nil then error("evaluated type uses unsupported access value " .. tostring(value), 3) end
    return out
  end

  local function name_value(value)
    local name = class_name(value)
    if name ~= "LalinCore.Name" then error("evaluated type ref uses unsupported name " .. tostring(value), 3) end
    return C.Name(value.text)
  end

  local function path_value(value)
    local name = class_name(value)
    if name ~= "LalinCore.Path" then error("evaluated type ref uses unsupported path " .. tostring(value), 3) end
    local parts = {}
    for i, part in ipairs(value.parts or {}) do parts[i] = name_value(part) end
    return C.Path(parts)
  end

  local function type_sym_value(value)
    local name = class_name(value)
    if name ~= "LalinCore.TypeSym" then error("evaluated local type ref uses unsupported symbol " .. tostring(value), 3) end
    return C.TypeSym(value.key, value.name)
  end

  local function type_ref(value)
    local name = class_name(value)
    if name == "LalinType.TypeRefPath" then
      return Ty.TypeRefPath(path_value(value.path))
    elseif name == "LalinType.TypeRefGlobal" then
      return Ty.TypeRefGlobal(value.module_name, value.type_name)
    elseif name == "LalinType.TypeRefLocal" then
      return Ty.TypeRefLocal(type_sym_value(value.sym))
    end
    error("evaluated type uses unsupported type ref " .. tostring(value), 3)
  end

  local function array_len(value)
    local name = class_name(value)
    if name == "LalinType.ArrayLenConst" then return Ty.ArrayLenConst(value.count) end
    error("evaluated array type uses unsupported length " .. tostring(value), 3)
  end

  local function lease_origin_value(value)
    local name = class_name(value)
    local out = lease_origin[name]
    if out ~= nil then return out end
    if name == "LalinType.LeaseOriginParam" then return Ty.LeaseOriginParam(value.name) end
    error("evaluated lease type uses unsupported origin " .. tostring(value), 3)
  end

  local function handle_repr_value(value)
    local name = class_name(value)
    if name == "LalinType.HandleReprScalar" then return Ty.HandleReprScalar(scalar_value(value.scalar)) end
    error("evaluated handle type uses unsupported representation " .. tostring(value), 3)
  end

  local function c_type_id(value)
    local name = class_name(value)
    if name == "LalinC.CTypeId" then return CT.CTypeId(value.module_name, value.spelling) end
    error("evaluated imported C type uses unsupported id " .. tostring(value), 3)
  end

  local function c_func_sig_id(value)
    local name = class_name(value)
    if name == "LalinC.CFuncSigId" then return CT.CFuncSigId(value.text) end
    error("evaluated imported C function pointer uses unsupported signature id " .. tostring(value), 3)
  end

  function M.type(value)
    local name = class_name(value)
    if name == "LalinType.TScalar" then
      return Ty.TScalar(scalar_value(value.scalar))
    elseif name == "LalinType.TPtr" then
      return Ty.TPtr(M.type(value.elem))
    elseif name == "LalinType.TArray" then
      return Ty.TArray(array_len(value.count), M.type(value.elem))
    elseif name == "LalinType.TSlice" then
      return Ty.TSlice(M.type(value.elem))
    elseif name == "LalinType.TView" then
      return Ty.TView(M.type(value.elem))
    elseif name == "LalinType.TLease" then
      return Ty.TLease(M.type(value.base), lease_origin_value(value.origin))
    elseif name == "LalinType.TOwned" then
      return Ty.TOwned(M.type(value.base))
    elseif name == "LalinType.TAccess" then
      return Ty.TAccess(access_value(value.access), M.type(value.base))
    elseif name == "LalinType.THandle" then
      return Ty.THandle(type_ref(value.ref), handle_repr_value(value.repr))
    elseif name == "LalinType.TFunc" then
      local params = {}
      for i, param in ipairs(value.params or {}) do params[i] = M.type(param) end
      return Ty.TFunc(params, M.type(value.result))
    elseif name == "LalinType.TClosure" then
      local params = {}
      for i, param in ipairs(value.params or {}) do params[i] = M.type(param) end
      return Ty.TClosure(params, M.type(value.result))
    elseif name == "LalinType.TNamed" then
      return Ty.TNamed(type_ref(value.ref))
    elseif name == "LalinType.TCType" then
      return Ty.TCType(c_type_id(value.id))
    elseif name == "LalinType.TCFuncPtr" then
      return Ty.TCFuncPtr(c_func_sig_id(value.sig))
    end
    return nil
  end

  return M
end

return bind_context
