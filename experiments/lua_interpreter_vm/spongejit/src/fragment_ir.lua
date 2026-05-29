-- fragment_ir.lua -- native SpongeJIT fragment ABI metadata and validation.
--
-- Lua-side fragments are explicit abstract native-fragment descriptors until an
-- assembler/linker provides byte offsets. Every descriptor also carries a
-- deterministic ABI-lowered view with numeric enum values matching sponbank.h,
-- so JSON artifacts never mix public C ABI numeric fields with ambiguous string
-- names.

local bit = require("bit")

local M = {}

local function copy_array(xs)
  local out = {}
  for i, x in ipairs(xs or {}) do out[i] = x end
  return out
end

local function has_kind(set, k) return set[k] == true end
local function err(errors, msg) errors[#errors + 1] = msg end

M.PHYSICAL_ABI = { x86_64_sysv_spon_v1 = true }
M.PHYSICAL_ABI_ID = { x86_64_sysv_spon_v1 = 1 }
M.VALUE_TYPE = { TValue = true, I64 = true, Bool = true, Ptr = true, Unknown = true }
M.VALUE_TYPE_ID = { Unknown = 0, TValue = 1, I64 = 2, Bool = 3, Ptr = 4 }
M.LOCATION_KIND = { none = true, reg = true, ctx_field = true, frame_slot = true, immediate = true }
M.LOCATION_KIND_ID = { none = 0, reg = 1, ctx_field = 2, frame_slot = 3, immediate = 4 }
M.ENDPOINT_KIND = {
  entry = true,
  ok = true,
  guard_exit = true,
  residual_exit = true,
  boundary_exit = true,
  unlowered_exit = true,
}
M.ENDPOINT_KIND_ID = { entry = 1, ok = 2, guard_exit = 3, residual_exit = 4, boundary_exit = 5, unlowered_exit = 6 }
M.DATA_RELOC_KIND = {
  slot = true,
  slot_store = true,
  imm = true,
  const = true,
  bool = true,
  shape_offset = true,
  shape_id = true,
  metatable_offset = true,
  field_offset = true,
  array_base_offset = true,
  call_target = true,
  barrier = true,
}
M.DATA_RELOC_KIND_ID = { slot = 1, slot_store = 2, imm = 3, const = 4, bool = 5, shape_offset = 6, shape_id = 7, metatable_offset = 8, field_offset = 9, array_base_offset = 10, call_target = 11, barrier = 12 }
M.CONTROL_RELOC_KIND = {
  fallthrough = true,
  guard_fail = true,
  residual = true,
  boundary = true,
  projection_stub = true,
}
M.CONTROL_RELOC_KIND_ID = { fallthrough = 1, guard_fail = 2, residual = 3, boundary = 4, projection_stub = 5 }
M.PROJECTION_KIND = { SYNCED_FRAME = true, BOX_I64 = true }
M.PROJECTION_KIND_ID = { SYNCED_FRAME = 1, BOX_I64 = 2 }

M.FRAGMENT_FLAG = { ABSTRACT = 1, NATIVE = 2, PUC_PATCHABLE = 4 }

local REG_ID = {
  none = 0,
  rax = 1, rcx = 2, rdx = 3, rbx = 4, rsp = 5, rbp = 6, rsi = 7, rdi = 8,
  r8 = 9, r9 = 10, r10 = 11, r11 = 12, r12 = 13, r13 = 14, r14 = 15, r15 = 16,
  flags = 255,
}
M.REG_ID = REG_ID

local DATA_ROLE = {
  unknown = true,
  slot = true,
  slot_store = true,
  imm = true,
  const = true,
  bool = true,
  shape_offset = true,
  shape_id = true,
  metatable_offset = true,
  field_offset = true,
  array_base_offset = true,
  call_target = true,
  barrier = true,
}
M.DATA_ROLE = DATA_ROLE

local FIRST_NATIVE_DATA_ROLE = { slot = true, slot_store = true, imm = true, const = true, bool = true }
M.FIRST_NATIVE_DATA_ROLE = FIRST_NATIVE_DATA_ROLE

local PAYLOAD_ROLE = {
  shape_offset = true,
  shape_id = true,
  metatable_offset = true,
  field_offset = true,
  array_base_offset = true,
  call_target = true,
  barrier = true,
}
M.PAYLOAD_ROLE = PAYLOAD_ROLE

local DATA_WORDS_AS_CONTROL = { fail = true, exit = true, guard_fail = true, fallthrough = true, residual = true, boundary = true, projection_stub = true }
local CONTROL_WORDS_AS_DATA = { slot = true, slot_store = true, imm = true, const = true, bool = true, shape_offset = true, shape_id = true, metatable_offset = true, field_offset = true, array_base_offset = true, call_target = true, barrier = true, exit = true, fail = true }

local function u32(x)
  local n = tonumber(bit.band(x, 0xffffffff)) or 0
  if n < 0 then n = n + 4294967296 end
  return n
end

local function stable_u64_literal(s)
  s = tostring(s or "")
  local hi, lo = 0x811c9dc5, 0x01000193
  for i = 1, #s do
    local b = string.byte(s, i)
    hi = bit.tobit(bit.bxor(hi, b) * 16777619)
    lo = bit.tobit(bit.bxor(lo, b) * 2166136261)
  end
  return string.format("0x%08x%08xULL", u32(hi), u32(lo))
end
M.stable_u64_literal = stable_u64_literal

local function sig_literal(x)
  if type(x) == "table" and x.literal then return tostring(x.literal) end
  if type(x) == "number" then return string.format("0x%016xULL", x) end
  if x == nil then return "0x0000000000000000ULL" end
  return tostring(x)
end

local function u64_parts_from_literal(lit)
  local hex = tostring(lit or ""):match("^0x([%x]+)ULL$") or tostring(lit or ""):match("^0x([%x]+)$") or "0"
  hex = hex:lower()
  if #hex > 16 then hex = hex:sub(#hex - 15) end
  hex = string.rep("0", 16 - #hex) .. hex
  local hi = tonumber(hex:sub(1, 8), 16) or 0
  local lo = tonumber(hex:sub(9, 16), 16) or 0
  return hi, lo
end

function M.location(t)
  t = t or {}
  return {
    kind = t.kind or "none",
    value_type = t.value_type or t.ty or "Unknown",
    reg = t.reg,
    index = t.index,
    name = t.name,
  }
end

function M.projection(t)
  t = t or {}
  return {
    kind = t.kind or "SYNCED_FRAME",
    value_type = t.value_type or t.ty or "Unknown",
    logical_slot = t.logical_slot,
    value_index = t.value_index,
    reason = t.reason,
    pc = t.pc or 0,
    entries = copy_array(t.entries),
  }
end

function M.endpoint(t)
  t = t or {}
  return {
    kind = t.kind,
    flags = t.flags or {},
    locations = copy_array(t.locations),
    clobbers = copy_array(t.clobbers),
    contract = t.contract,
    projection_start = t.projection_start,
    n_projections = t.n_projections or (t.projections and #t.projections or 0),
    projections = copy_array(t.projections),
    source = t.source,
    exit = t.exit,
  }
end

function M.data_reloc(t)
  t = t or {}
  return {
    code_offset = t.code_offset or 0,
    code_offset_kind = t.code_offset_kind,
    reloc_kind = t.reloc_kind or t.kind or t.role_kind,
    role_kind = t.role_kind or t.kind or t.reloc_kind,
    op_idx = t.op_idx or 0,
    role_arg = t.role_arg,
    hole_id = t.hole_id,
    value_type = t.value_type or t.ty,
  }
end

function M.control_reloc(t)
  t = t or {}
  return {
    code_offset = t.code_offset or 0,
    code_offset_kind = t.code_offset_kind,
    reloc_kind = t.reloc_kind or t.edge_kind,
    edge_kind = t.edge_kind or t.reloc_kind,
    endpoint_index = t.endpoint_index,
    target_delta = t.target_delta or 0,
    source = t.source,
  }
end

function M.dependency(t)
  if type(t) == "string" then return { name = t } end
  t = t or {}
  return { name = t.name or tostring(t[1] or "") }
end

local function default_layout(t)
  if t.layout then return t.layout end
  return {
    mode = "abstract_fragment",
    executable = false,
    code_offsets = "abstract_zero",
    reason = "native assembler/linker offsets are not emitted by metadata lowering",
  }
end

function M.fragment(t)
  t = t or {}
  local f = {
    schema = t.schema or "spon.fragment.abstract.v1",
    fragment_id = t.fragment_id,
    name = t.name,
    physical_abi = t.physical_abi,
    pattern_key = t.pattern_key,
    len = t.len or 0,
    executable = t.executable == true,
    layout = default_layout(t),
    endpoints = copy_array(t.endpoints),
    data_relocs = copy_array(t.data_relocs),
    control_relocs = copy_array(t.control_relocs),
    slotmaps = copy_array(t.slotmaps),
    projections = copy_array(t.projections),
    dependencies = copy_array(t.dependencies),
    clobbers = copy_array(t.clobbers),
    fact_transfer = t.fact_transfer,
    active_node_specs = copy_array(t.active_node_specs),
    stencil_ops = copy_array(t.stencil_ops),
    source_ops = copy_array(t.source_ops),
    allow_payload_roles = t.allow_payload_roles and true or false,
    allow_dependencies = t.allow_dependencies and true or false,
  }
  f.abi = M.lower_to_abi(f)
  return f
end

local function validate_projection_object(p, errors, label)
  if type(p) ~= "table" then err(errors, label .. " missing projection object"); return false end
  if not has_kind(M.PROJECTION_KIND, p.kind) then err(errors, label .. " unknown projection kind: " .. tostring(p.kind)); return false end
  if p.pc == nil then err(errors, label .. " missing pc") end
  if p.kind == "BOX_I64" then
    if p.logical_slot == nil then err(errors, label .. " BOX_I64 missing logical_slot") end
    if p.value_index == nil then err(errors, label .. " BOX_I64 missing value_index") end
  end
  return true
end

local function validate_location(loc, errors, label)
  if type(loc) ~= "table" then err(errors, label .. " missing location object"); return end
  if not has_kind(M.LOCATION_KIND, loc.kind) then err(errors, label .. " unknown location kind: " .. tostring(loc.kind)) end
  if not has_kind(M.VALUE_TYPE, loc.value_type or "Unknown") then err(errors, label .. " unknown value type: " .. tostring(loc.value_type)) end
  if loc.kind == "reg" and not REG_ID[loc.reg or ""] then err(errors, label .. " unknown register: " .. tostring(loc.reg)) end
end

local function validate_abstract_offset(f, r, errors, label)
  if f.executable then
    if r.code_offset_kind == "abstract_zero" then err(errors, label .. " executable reloc cannot use abstract code offset") end
    if type(r.code_offset) ~= "number" then err(errors, label .. " executable reloc missing numeric code_offset") end
  else
    if not (f.layout and f.layout.mode == "abstract_fragment") then err(errors, label .. " non-executable fragment missing abstract layout") end
    if r.code_offset == 0 and r.code_offset_kind ~= "abstract_zero" then err(errors, label .. " zero placeholder code_offset must be marked abstract_zero") end
  end
end

function M.validate_fragment(f)
  local errors = {}
  if type(f) ~= "table" then return false, { "missing fragment" } end

  if f.schema ~= "spon.fragment.abstract.v1" then err(errors, "unknown fragment schema: " .. tostring(f.schema)) end
  if not has_kind(M.PHYSICAL_ABI, f.physical_abi) then err(errors, "unknown physical ABI: " .. tostring(f.physical_abi)) end
  if not f.executable then
    if not (f.layout and f.layout.mode == "abstract_fragment" and f.layout.executable == false) then
      err(errors, "abstract fragment must declare non-executable abstract layout")
    end
  end
  if #(f.clobbers or {}) == 0 then err(errors, "fragment must declare clobbers") end

  local entry_count, ok_count = 0, 0
  for i, ep in ipairs(f.endpoints or {}) do
    if not has_kind(M.ENDPOINT_KIND, ep.kind) then err(errors, "unknown endpoint kind at " .. i .. ": " .. tostring(ep.kind)) end
    if #(ep.locations or {}) == 0 then err(errors, "endpoint without location contract at " .. i .. ": " .. tostring(ep.kind)) end
    for j, loc in ipairs(ep.locations or {}) do validate_location(loc, errors, "endpoint " .. i .. " location " .. j) end
    if ep.kind == "entry" then entry_count = entry_count + 1 end
    if ep.kind == "ok" then ok_count = ok_count + 1 end
    local nproj = tonumber(ep.n_projections or 0) or 0
    if ep.kind ~= "entry" and ep.kind ~= "ok" then
      if nproj <= 0 then
        err(errors, "non-success endpoint without projection: " .. tostring(ep.kind))
      else
        local start = tonumber(ep.projection_start)
        if not start or start < 1 then
          err(errors, "endpoint projection range missing start at " .. i)
        elseif start + nproj - 1 > #(f.projections or {}) then
          err(errors, "endpoint projection range out of bounds at " .. i)
        else
          for k = start, start + nproj - 1 do validate_projection_object(f.projections[k], errors, "projection " .. k) end
        end
        if #(ep.projections or {}) > 0 then
          if #ep.projections ~= nproj then err(errors, "endpoint embedded projection count mismatch at " .. i) end
          for j, p in ipairs(ep.projections or {}) do validate_projection_object(p, errors, "endpoint " .. i .. " projection " .. j) end
        end
      end
    elseif nproj ~= 0 then
      err(errors, "success/entry endpoint must not carry projections at " .. i)
    end
  end
  if entry_count ~= 1 then err(errors, "fragment requires exactly one entry endpoint") end
  if ok_count < 1 then err(errors, "fragment requires at least one ok endpoint") end

  local ft = f.fact_transfer
  if type(ft) ~= "table" then
    err(errors, "missing fact_transfer")
  else
    for _, k in ipairs({"selector_sig", "required_sig", "checked_sig", "produced_sig", "killed_sig"}) do
      if ft[k] == nil then err(errors, "missing fact_transfer." .. k) end
    end
  end

  for i, h in ipairs(f.data_relocs or {}) do
    validate_abstract_offset(f, h, errors, "data reloc " .. i)
    local role = h.role_kind or h.reloc_kind
    if DATA_WORDS_AS_CONTROL[role] then err(errors, "control role used as data reloc at " .. i .. ": " .. tostring(role)) end
    if not has_kind(DATA_ROLE, role) then err(errors, "unknown data reloc role at " .. i .. ": " .. tostring(role)) end
    if PAYLOAD_ROLE[role] and not f.allow_payload_roles then err(errors, "unsupported payload data reloc role: " .. tostring(role)) end
  end

  for i, cr in ipairs(f.control_relocs or {}) do
    validate_abstract_offset(f, cr, errors, "control reloc " .. i)
    local edge = cr.edge_kind or cr.reloc_kind
    if CONTROL_WORDS_AS_DATA[edge] then err(errors, "data role used as control reloc at " .. i .. ": " .. tostring(edge)) end
    if not has_kind(M.CONTROL_RELOC_KIND, edge) then err(errors, "unknown control reloc kind at " .. i .. ": " .. tostring(edge)) end
    if cr.endpoint_index == nil then err(errors, "control reloc without endpoint index at " .. i) end
    if cr.endpoint_index ~= nil and not (f.endpoints or {})[cr.endpoint_index] then err(errors, "control reloc endpoint out of range at " .. i) end
  end

  for i, p in ipairs(f.projections or {}) do validate_projection_object(p, errors, "projection " .. i) end

  if #(f.dependencies or {}) > 0 and not f.allow_dependencies then err(errors, "unsupported dependencies in native fragment descriptor") end

  return #errors == 0, errors
end

local function loc_to_abi(loc)
  return {
    kind = M.LOCATION_KIND_ID[loc.kind or "none"] or 0,
    value_type = M.VALUE_TYPE_ID[loc.value_type or "Unknown"] or 0,
    reg = REG_ID[loc.reg or "none"] or 0,
    index = loc.index or 0,
    name = loc.name,
  }
end

local function proj_to_abi(p)
  return {
    kind = M.PROJECTION_KIND_ID[p.kind] or 0,
    value_type = M.VALUE_TYPE_ID[p.value_type or "Unknown"] or 0,
    logical_slot = p.logical_slot or 0,
    value_index = p.value_index or 0,
    pc = p.pc or 0,
    reason = p.reason,
  }
end

function M.lower_to_abi(f)
  local locations, endpoints = {}, {}
  for _, ep in ipairs(f.endpoints or {}) do
    local loc_start = #locations + 1
    for _, loc in ipairs(ep.locations or {}) do locations[#locations + 1] = loc_to_abi(loc) end
    endpoints[#endpoints + 1] = {
      kind = M.ENDPOINT_KIND_ID[ep.kind] or 0,
      flags = 0,
      location_start = loc_start,
      n_locations = #(ep.locations or {}),
      projection_start = ep.projection_start or 0,
      n_projections = ep.n_projections or 0,
    }
  end

  local data_relocs = {}
  for _, r in ipairs(f.data_relocs or {}) do
    data_relocs[#data_relocs + 1] = {
      code_offset = r.code_offset or 0,
      code_offset_kind = r.code_offset_kind,
      reloc_kind = 0,
      role_kind = M.DATA_RELOC_KIND_ID[r.role_kind or r.reloc_kind] or 0,
      op_idx = r.op_idx or 0,
      role_arg = r.role_arg or 0,
    }
  end

  local control_relocs = {}
  for _, r in ipairs(f.control_relocs or {}) do
    control_relocs[#control_relocs + 1] = {
      code_offset = r.code_offset or 0,
      code_offset_kind = r.code_offset_kind,
      reloc_kind = 0,
      edge_kind = M.CONTROL_RELOC_KIND_ID[r.edge_kind or r.reloc_kind] or 0,
      endpoint_index = r.endpoint_index or 0,
      target_delta = r.target_delta or 0,
    }
  end

  local projections = {}
  for _, p in ipairs(f.projections or {}) do projections[#projections + 1] = proj_to_abi(p) end

  local flags = f.executable and M.FRAGMENT_FLAG.NATIVE or M.FRAGMENT_FLAG.ABSTRACT
  local pattern_lit = stable_u64_literal(f.pattern_key)
  local pattern_hi, pattern_lo = u64_parts_from_literal(pattern_lit)
  local selector_lit = sig_literal(f.fact_transfer and f.fact_transfer.selector_sig)
  local required_lit = sig_literal(f.fact_transfer and f.fact_transfer.required_sig)
  local checked_lit = sig_literal(f.fact_transfer and f.fact_transfer.checked_sig)
  local produced_lit = sig_literal(f.fact_transfer and f.fact_transfer.produced_sig)
  local killed_lit = sig_literal(f.fact_transfer and f.fact_transfer.killed_sig)
  local selector_hi, selector_lo = u64_parts_from_literal(selector_lit)
  local required_hi, required_lo = u64_parts_from_literal(required_lit)
  local checked_hi, checked_lo = u64_parts_from_literal(checked_lit)
  local produced_hi, produced_lo = u64_parts_from_literal(produced_lit)
  local killed_hi, killed_lo = u64_parts_from_literal(killed_lit)
  return {
    schema = "spon.fragment.abi.v1",
    executable = f.executable == true,
    layout = f.layout,
    fragment = {
      fragment_id = f.fragment_id or 0,
      offset = 0,
      size = 0,
      endpoint_start = 1,
      data_reloc_start = 1,
      control_reloc_start = 1,
      slotmap_start = 1,
      projection_start = 1,
      dependency_start = 1,
      len = f.len or 0,
      n_endpoints = #(f.endpoints or {}),
      n_data_relocs = #(f.data_relocs or {}),
      n_control_relocs = #(f.control_relocs or {}),
      n_slotmaps = #(f.slotmaps or {}),
      n_projections = #(f.projections or {}),
      n_dependencies = #(f.dependencies or {}),
      flags = flags,
      physical_abi = M.PHYSICAL_ABI_ID[f.physical_abi] or 0,
      pattern_key = pattern_lit,
      pattern_key_hi = pattern_hi,
      pattern_key_lo = pattern_lo,
      selector_sig = selector_lit,
      selector_sig_hi = selector_hi,
      selector_sig_lo = selector_lo,
      required_sig = required_lit,
      required_sig_hi = required_hi,
      required_sig_lo = required_lo,
      checked_sig = checked_lit,
      checked_sig_hi = checked_hi,
      checked_sig_lo = checked_lo,
      produced_sig = produced_lit,
      produced_sig_hi = produced_hi,
      produced_sig_lo = produced_lo,
      killed_sig = killed_lit,
      killed_sig_hi = killed_hi,
      killed_sig_lo = killed_lo,
    },
    endpoints = endpoints,
    locations = locations,
    data_relocs = data_relocs,
    control_relocs = control_relocs,
    slotmaps = copy_array(f.slotmaps),
    projections = projections,
    dependencies = copy_array(f.dependencies),
    clobbers = copy_array(f.clobbers),
  }
end

return M
