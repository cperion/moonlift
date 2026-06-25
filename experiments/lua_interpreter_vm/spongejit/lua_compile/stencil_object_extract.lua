-- stencil_object_extract.lua -- explicit object-metadata adapter for Stencil ASDL.
--
-- Future object extraction can feed this adapter with real code/symbol/reloc/hole
-- metadata. This module intentionally does not invoke Cranelift/Lalin and
-- does not fabricate code blobs.

local pvm = require("lalin.pvm")
local B = require("lua_compile.builders")
local T = B.T
local S = T.Stencil
local GC = T.LuaGC
local Plan = require("lua_compile.stencil_materialization_plan")
local Validate = require("lua_compile.stencil_validate")

local M = {}

local function name(s) return type(s) == "table" and s or S.Name(tostring(s or "")) end

local function enum(map, v, label)
  if type(v) == "table" then return v end
  local e = map[tostring(v or "")]
  assert(e, "unknown " .. label .. ": " .. tostring(v))
  return e
end

local SymbolKind = {
  EntrySymbol = S.EntrySymbol, LocalLabel = S.LocalLabel, ExternalTarget = S.ExternalTarget,
  ContinuationTarget = S.ContinuationTarget, PatchAnchor = S.PatchAnchor,
}
local SymbolVisibility = { Local = S.Local, BankExported = S.BankExported, ExternalImported = S.ExternalImported }
local PatchKind = {
  ImmediatePatch = S.ImmediatePatch, StackOffsetPatch = S.StackOffsetPatch, ConstAddressPatch = S.ConstAddressPatch,
  BranchTargetPatch = S.BranchTargetPatch, CallTargetPatch = S.CallTargetPatch, SymbolAddressPatch = S.SymbolAddressPatch,
  FrameLayoutPatch = S.FrameLayoutPatch, RegisterPatch = S.RegisterPatch, VTablePatch = S.VTablePatch,
  FFISymbolAddr64Patch = S.FFISymbolAddr64Patch, FFIFieldOffsetPatch = S.FFIFieldOffsetPatch,
  FFISizeOfPatch = S.FFISizeOfPatch, FFIAlignOfPatch = S.FFIAlignOfPatch, FFICallbackThunkPatch = S.FFICallbackThunkPatch,
  GCStatePtrPatch = S.GCStatePtrPatch, GCAllocatorFnPatch = S.GCAllocatorFnPatch,
  GCObjectLayoutOffsetPatch = S.GCObjectLayoutOffsetPatch, GCBarrierEntryAddrPatch = S.GCBarrierEntryAddrPatch,
  GCFinalizerQueuePtrPatch = S.GCFinalizerQueuePtrPatch, GCEpochAddressPatch = S.GCEpochAddressPatch,
  GCEpochExpectedPatch = S.GCEpochExpectedPatch,
}
local PatchEncoding = { U8=S.U8, U16=S.U16, U32=S.U32, U64=S.U64, I32=S.I32, I64=S.I64, PcRel32=S.PcRel32, PcRel64=S.PcRel64, Abs64=S.Abs64 }
local RelocKind = { AbsAddr=S.AbsAddr, PcRel=S.PcRel, GotRelative=S.GotRelative, PltRelative=S.PltRelative, SectionRelative=S.SectionRelative }
local GCObjectKind = {
  StringKind = GC.StringKind, TableKind = GC.TableKind, ClosureKind = GC.ClosureKind, ProtoKind = GC.ProtoKind,
  ThreadKind = GC.ThreadKind, UserdataKind = GC.UserdataKind, CDataKind = GC.CDataKind, UpvalueKind = GC.UpvalueKind,
}

local function symbol_from(m)
  if T.Stencil.Symbol == pvm.classof(m) then return m end
  return S.Symbol(name(m.name or m.symbol), enum(SymbolKind, m.kind or "LocalLabel", "SymbolKind"), enum(SymbolVisibility, m.visibility or "Local", "SymbolVisibility"), tonumber(m.offset or 0) or 0)
end

local function code_from(m)
  if pvm.classof(m) == S.CodeBlobRef then return m end
  assert(m and m.symbol and m.byte_size and m.content_hash, "object metadata requires explicit code symbol, byte_size, and content_hash")
  return S.CodeBlobRef(name(m.symbol), tonumber(m.byte_size), tostring(m.content_hash))
end

local function immediate_from(m)
  if type(m) == "table" and T.Stencil.ImmediateOperand.members[pvm.classof(m)] then return m end
  local kind = tostring(m.kind or m.type or "ImmI64")
  if kind == "ImmI64" then return S.ImmI64(tonumber(m.value or 0) or 0) end
  if kind == "ImmF64" then return S.ImmF64(tonumber(m.value or 0) or 0) end
  if kind == "ImmBool" then return S.ImmBool(not not m.value) end
  if kind == "ImmBytes" then return S.ImmBytes(tostring(m.hash), tonumber(m.byte_size or 0) or 0) end
  if kind == "ImmSymbol" then return S.ImmSymbol(symbol_from(m.symbol)) end
  error("unknown ImmediateOperand: " .. kind)
end

local function source_from(m, symbols)
  if type(m) == "table" and T.Stencil.PatchSource.members[pvm.classof(m)] then return m end
  local kind = tostring((m and (m.kind or m.type)) or "FromMaterializationValue")
  if kind == "FromImmediate" then return S.FromImmediate(immediate_from(m.imm or m.immediate or { kind = m.imm_kind or "ImmI64", value = m.value or 0 })) end
  if kind == "FromSymbol" then
    local sym = type(m.symbol) == "string" and symbols[m.symbol] or symbol_from(m.symbol)
    return S.FromSymbol(sym)
  end
  if kind == "FromGCState" then return S.FromGCState(GC.Name(tostring(m.state or m.name or "gc_state"))) end
  if kind == "FromGCAllocator" then return S.FromGCAllocator(GC.Name(tostring(m.allocator or "allocator")), GC.Name(tostring(m.function_name or m.fn or "alloc_fn"))) end
  if kind == "FromGCObjectLayout" then return S.FromGCObjectLayout(enum(GCObjectKind, m.object_kind or m.kind_name or "TableKind", "GCObjectKind"), GC.Name(tostring(m.field or "layout_field"))) end
  if kind == "FromGCFinalizerQueue" then return S.FromGCFinalizerQueue(GC.Name(tostring(m.state or m.name or "gc_state"))) end
  if kind == "FromGCBarrierEntry" and T.Stencil.PatchSource.members[pvm.classof(m.source)] then return m.source end
  if kind == "FromGCEpoch" and T.Stencil.PatchSource.members[pvm.classof(m.source)] then return m.source end
  if kind == "FromMaterializationValue" then return S.FromMaterializationValue(name(m.name or m.value or "patch_value")) end
  error("unsupported PatchSource in explicit metadata: " .. kind)
end

local function hole_from(m, symbols)
  if pvm.classof(m) == S.PatchHole then return m end
  local enc = PatchEncoding[tostring(m.encoding or "")]
  if not enc then enc = S.TargetSpecific(tostring(m.encoding or "target")) end
  return S.PatchHole(name(m.id or m.name), enum(PatchKind, m.kind, "PatchKind"), tonumber(m.offset or 0) or 0, tonumber(m.width_bytes or m.width or 0) or 0, enc, source_from(m.source or { kind = "FromMaterializationValue", name = m.id or m.name }, symbols))
end

local function reloc_from(m, symbols)
  if pvm.classof(m) == S.Reloc then return m end
  local rk = RelocKind[tostring(m.kind or "")]
  if not rk then rk = S.TargetReloc(tostring(m.kind or "target")) end
  local target = type(m.target) == "string" and symbols[m.target] or symbol_from(m.target)
  assert(target, "reloc target does not resolve in explicit metadata: " .. tostring(m.target))
  return S.Reloc(name(m.id or m.name or ("reloc_" .. tostring(m.offset or 0))), rk, tonumber(m.offset or 0) or 0, target, tonumber(m.addend or 0) or 0)
end

function M.template_from_metadata(metadata, variant, opts)
  opts = opts or {}
  assert(metadata, "metadata required")
  assert(variant, "variant required")
  local symbols = {}
  local local_symbols = {}
  for _, s in ipairs(metadata.symbols or {}) do
    local sym = symbol_from(s)
    symbols[sym.name and sym.name.text or tostring(#local_symbols + 1)] = sym
    local_symbols[#local_symbols + 1] = sym
  end
  local entry_name = metadata.entry or metadata.entry_symbol or (metadata.code and metadata.code.symbol)
  local entry_symbol = symbols[tostring(entry_name)]
  if not entry_symbol then
    entry_symbol = S.Symbol(name(entry_name), S.EntrySymbol, S.Local, 0)
    symbols[entry_symbol.name.text] = entry_symbol
    local_symbols[#local_symbols + 1] = entry_symbol
  end
  local holes = {}
  for _, h in ipairs(metadata.holes or {}) do holes[#holes + 1] = hole_from(h, symbols) end
  local relocs = {}
  for _, r in ipairs(metadata.relocs or {}) do relocs[#relocs + 1] = reloc_from(r, symbols) end
  local code = code_from(metadata.code or {})
  local template = Plan.template{
    name = metadata.name or (code.symbol and code.symbol.text) or "stencil_template",
    kind = metadata.kind or S.KernelStencil,
    variant = variant,
    code = code,
    holes = holes,
    relocs = relocs,
    local_symbols = local_symbols,
    entry_symbol = entry_symbol,
    target_abi = variant.target_abi,
    patch_values = metadata.patch_values or {},
    link_steps = metadata.link_steps or {},
    validate_opts = opts,
  }
  local ok, errors = Validate.validate_template(template, opts)
  if not ok then error(table.concat(errors, "\n"), 2) end
  return template
end

return M
