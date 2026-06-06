-- lua_exec_region_model.lua -- static semantic region taxonomy metadata.
--
-- Representation metadata only: no interpreter dispatch, protocol handoff, or
-- helper execution lives here. Region semantic identity is independent of
-- current lowerer support; unsupported region kinds remain structurally valid
-- ASDL products and reject only at executable lowering gates.

local Schema = require("lua_compile.schema")
local T = Schema.get()
local Exec, RT = T.LuaExec, T.LuaRT
local CallModel = require("lua_compile.lua_rt_call_model")

local M = {}

M.SUPPORTED_REGION_KIND_NOW = {
  CoreWindowRegion = true,
  LoadMoveRegion = true,
  BranchRegion = true,
  ReturnRegion = true,
  VarargRegion = true,
  ArithmeticRegion = true,
  TableAccessRegion = true,
  TableGetRegion = true,
  TableSetRegion = true,
  LenRegion = true,
  ConcatRegion = true,
  ErrorRegion = true,
  YieldRegion = true,
  GuardRegion = true,
}

M.UNSUPPORTED_REGION_KIND_NOW = {
  CallRegion = true,
  TailCallRegion = true,
  MetatableRegion = true,
  ClosureRegion = true,
  UpvalueRegion = true,
  GCAllocRegion = true,
  FFIRegion = true,
  NumericForRegion = true,
  GenericForRegion = true,
  CloseRegion = true,
  SetListRegion = true,
  OpcodeFamilyRegion = true,
}

local LOAD_MOVE = {
  MOVE = true,
  LOADNIL = true,
  LOADFALSE = true,
  LFALSESKIP = true,
  LOADTRUE = true,
  LOADI = true,
  LOADF = true,
  LOADK = true,
  LOADKX = true,
  EXTRAARG = true,
}

local ARITH = {
  ADD = true, ADDI = true, ADDK = true, SUB = true, SUBK = true, MUL = true,
  MULK = true, MOD = true, MODK = true, POW = true, POWK = true, DIV = true,
  DIVK = true, IDIV = true, IDIVK = true, BAND = true, BANDK = true, BOR = true,
  BORK = true, BXOR = true, BXORK = true, SHL = true, SHLI = true, SHR = true,
  SHRI = true, UNM = true, BNOT = true, MMBIN = true, MMBINI = true,
  MMBINK = true,
}

local COMPARE_BRANCH = {
  JMP = true, EQ = true, LT = true, LE = true, EQK = true, EQI = true,
  LTI = true, LEI = true, GTI = true, GEI = true, TEST = true, TESTSET = true,
}

local TABLE_ACCESS = {
  GETTABLE = true, GETI = true, GETFIELD = true, GETTABUP = true, SELF = true,
}

local TABLE_SET = {
  SETTABLE = true, SETI = true, SETFIELD = true, SETTABUP = true,
}

local function kind_name(kind)
  if type(kind) == "string" then return kind end
  return kind and kind.kind or nil
end
M.kind_name = kind_name

function M.is_supported_region_kind_now(kind)
  return M.SUPPORTED_REGION_KIND_NOW[kind_name(kind)] == true
end

function M.is_executable_region_kind(kind)
  return M.is_supported_region_kind_now(kind)
end

function M.is_unsupported_region_kind_now(kind)
  return M.UNSUPPORTED_REGION_KIND_NOW[kind_name(kind)] == true
end

function M.is_potentially_executable_region_kind(kind)
  local k = kind_name(kind)
  return M.SUPPORTED_REGION_KIND_NOW[k] == true or k == "CallRegion"
end

function M.is_executable_region(region, contract)
  if not region then return false, "missing_region" end
  if M.is_supported_region_kind_now(region.kind) then return true end
  local k = kind_name(region.kind)
  if k == "CallRegion" then
    local ok, reason = CallModel.contract_allows_executable_call_region(contract)
    if ok then return true end
    return false, "call_region_contract:" .. tostring(reason)
  end
  return false, "unsupported_semantic_region:" .. tostring(k)
end

function M.opcode_family_for_src_kind(kind)
  local k = kind_name(kind)
  local family
  if LOAD_MOVE[k] then family = "LoadMoveFamily"
  elseif ARITH[k] then family = "ArithmeticFamily"
  elseif COMPARE_BRANCH[k] then family = "CompareBranchFamily"
  elseif k == "RETURN" or k == "RETURN0" or k == "RETURN1" then family = "ReturnFamily"
  elseif k == "CALL" then family = "CallFamily"
  elseif k == "TAILCALL" then family = "TailCallFamily"
  elseif TABLE_ACCESS[k] then family = "TableAccessFamily"
  elseif TABLE_SET[k] then family = "TableSetFamily"
  elseif k == "NEWTABLE" or k == "SETLIST" then family = "ConstructorFamily"
  elseif k == "VARARG" or k == "GETVARG" or k == "VARARGPREP" then family = "VarargFamily"
  elseif k == "CLOSURE" then family = "ClosureFamily"
  elseif k == "GETUPVAL" or k == "SETUPVAL" then family = "UpvalueFamily"
  elseif k == "FORPREP" or k == "FORLOOP" then family = "NumericForFamily"
  elseif k == "TFORPREP" or k == "TFORCALL" or k == "TFORLOOP" then family = "GenericForFamily"
  elseif k == "CLOSE" or k == "TBC" then family = "CloseTBCFamily"
  elseif k == "LEN" or k == "CONCAT" then family = "MetatableFamily"
  elseif k == "ERRNNIL" then family = "ErrorYieldFamily"
  else family = "UnsupportedFamily" end
  return Exec[family]
end

function M.region_kind_for_existing_block_term(term_kind)
  local k = kind_name(term_kind)
  local name
  if k == "return" or k == "return0" then name = "ReturnRegion"
  elseif k == "fallthrough" then name = "CoreWindowRegion"
  elseif k == "jump" or k == "branch" then name = "BranchRegion"
  elseif k == "arithmetic" or k == "arithmetic_error" then name = "ArithmeticRegion"
  elseif k == "gettable" or k == "gettable_error" then name = "TableGetRegion"
  elseif k == "settable" then name = "TableSetRegion"
  elseif k == "len" or k == "len_error" then name = "LenRegion"
  elseif k == "concat" or k == "concat_error" then name = "ConcatRegion"
  elseif k == "errnnil" or k == "error" then name = "ErrorRegion"
  else name = "CoreWindowRegion" end
  return Exec[name]
end

function M.region_kind_for_existing_shape(shape)
  local blocks = (shape and shape.blocks) or {}
  if #blocks ~= 1 then return Exec.CoreWindowRegion end
  return M.region_kind_for_existing_block_term(blocks[1].term and blocks[1].term.kind)
end

function M.family_for_existing_shape(shape)
  local blocks = (shape and shape.blocks) or {}
  local first = blocks[1]
  if first and first.instrs and first.instrs[1] then
    return M.opcode_family_for_src_kind(first.instrs[1].kind)
  end
  if first and first.term and first.term.op then
    return M.opcode_family_for_src_kind(first.term.op.kind)
  end
  return Exec.UnsupportedFamily
end

local function as_region_id(id)
  if id and id.name then return id end
  if id and id.text then return Exec.RegionId(id) end
  return Exec.RegionId(Exec.Name(tostring(id or "region")))
end

local function as_pc(pc)
  if type(pc) == "table" and pc.value ~= nil then return pc end
  return RT.Pc(tonumber(pc) or 0)
end

function M.descriptor(id, kind, family, start_pc, end_pc, _supported_now)
  local rkind = kind or Exec.CoreWindowRegion
  return Exec.RegionDescriptor(
    as_region_id(id),
    rkind,
    family or Exec.UnsupportedFamily,
    as_pc(start_pc),
    as_pc(end_pc)
  )
end

function M.descriptor_for_shape(id, shape)
  local blocks = (shape and shape.blocks) or {}
  local first_pc, last_pc = 0, 0
  if blocks[1] then first_pc = blocks[1].pc or 0 end
  for _, block in ipairs(blocks) do
    if type(block.pc) == "number" then last_pc = math.max(last_pc, block.pc) end
  end
  local kind = M.region_kind_for_existing_shape(shape)
  return M.descriptor(id, kind, M.family_for_existing_shape(shape), first_pc, last_pc, M.is_executable_region_kind(kind))
end

local UNSUPPORTED_KIND_FOR_FAMILY = {
  CallFamily = "CallRegion",
  TailCallFamily = "TailCallRegion",
  ConstructorFamily = "GCAllocRegion",
  ClosureFamily = "ClosureRegion",
  UpvalueFamily = "UpvalueRegion",
  NumericForFamily = "NumericForRegion",
  GenericForFamily = "GenericForRegion",
  CloseTBCFamily = "CloseRegion",
  MetatableFamily = "MetatableRegion",
  GCFamily = "GCAllocRegion",
  FFIFamily = "FFIRegion",
}

function M.unsupported_region_kind_for_family(family)
  local family_name = kind_name(family)
  local region_name = UNSUPPORTED_KIND_FOR_FAMILY[family_name] or "OpcodeFamilyRegion"
  return Exec[region_name]
end

function M.unsupported_descriptor_for_src_kind(kind, pc, id)
  local family = M.opcode_family_for_src_kind(kind)
  local region_kind = M.unsupported_region_kind_for_family(family)
  return M.descriptor(id or ("unsupported_" .. tostring(kind_name(kind) or "unknown") .. "_" .. tostring(pc or 0)), region_kind, family, pc, pc, false)
end

function M.call_descriptor(pc) return M.unsupported_descriptor_for_src_kind("CALL", pc, "call_unsupported_" .. tostring(pc or 0)) end
function M.tailcall_descriptor(pc) return M.unsupported_descriptor_for_src_kind("TAILCALL", pc, "tailcall_unsupported_" .. tostring(pc or 0)) end
function M.close_descriptor(pc) return M.unsupported_descriptor_for_src_kind("CLOSE", pc, "close_unsupported_" .. tostring(pc or 0)) end
function M.gc_alloc_descriptor(kind, pc) return M.unsupported_descriptor_for_src_kind(kind or "NEWTABLE", pc, "gc_alloc_unsupported_" .. tostring(pc or 0)) end
function M.metatable_descriptor(kind, pc) return M.unsupported_descriptor_for_src_kind(kind or "GETTABLE", pc, "metatable_unsupported_" .. tostring(pc or 0)) end

function M.validate_against_schema()
  local missing = {}
  for _, name in ipairs({
    "RegionId", "RegionRef", "RegionDescriptor", "OpcodeFamily",
    "CoreWindowRegion", "LoadMoveRegion", "BranchRegion", "TableAccessRegion",
    "MetatableRegion", "ClosureRegion", "UpvalueRegion", "GCAllocRegion",
    "FFIRegion", "OpcodeFamilyRegion", "CallStateExpr", "MetamethodDispatchExpr",
    "ClosePlanExpr", "GCEffectExpr", "RegionDescriptorExpr", "StaticRegionBindingExpr",
    "StaticRegionInvocationExpr", "RequiresRegionDescriptor", "DescribesRegion",
    "CallContinuationRegion", "StaticRegionBinding", "StaticRegionInvocation", "ModuleDescriptor",
  }) do
    if Exec[name] == nil then missing[#missing + 1] = "LuaExec." .. name end
  end
  for name in pairs(M.SUPPORTED_REGION_KIND_NOW) do
    if Exec[name] == nil then missing[#missing + 1] = "LuaExec.RegionKind." .. name end
  end
  for name in pairs(M.UNSUPPORTED_REGION_KIND_NOW) do
    if Exec[name] == nil then missing[#missing + 1] = "LuaExec.RegionKind." .. name end
  end
  table.sort(missing)
  return #missing == 0, missing
end

return M
