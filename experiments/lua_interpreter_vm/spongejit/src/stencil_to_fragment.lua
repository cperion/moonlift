-- stencil_to_fragment.lua -- lower semantic Stencil IR to native fragment descriptors.

local FragmentIR = require("src.fragment_ir")
local Abi = require("src.fragment_abi_x64")
local Projection = require("src.fragment_projection")
local Contract = require("src.ssa_contract")

local M = {}

local SUPPORTED_OP = {
  LoadSlot = true,
  StoreI64Slot = true,
  GuardI64 = true,
  UnboxI64 = true,
  ConstI64 = true,
  ConstI64Hole = true,
  AddI64 = true,
  SubI64 = true,
  MulI64 = true,
  ExitBoundary = true,
  ExitResidual = true,
  ExitUnlowered = true,
}
M.SUPPORTED_OP = SUPPORTED_OP

local SUPPORTED_DATA_ROLE = { slot = true, slot_store = true, imm = true, const = true, bool = true }
M.SUPPORTED_DATA_ROLE = SUPPORTED_DATA_ROLE

local function copy_array(xs)
  local out = {}
  for i, x in ipairs(xs or {}) do out[i] = x end
  return out
end

local function copy_contract(c)
  return {
    selector_sig = c.selector_sig,
    required_sig = c.required_sig,
    checked_sig = c.checked_sig,
    produced_sig = c.produced_sig,
    killed_sig = c.killed_sig,
    deps = copy_array(c.deps),
    exits = copy_array(c.exits),
  }
end

local function standard_locations(kind)
  -- Current descriptors are abstract and non-executable, but endpoint contracts
  -- are not empty: entry/success/exit all agree on ctx in rdi and a synced frame
  -- in ctx.stack. Later executable fragments can refine this without changing
  -- the public ABI shape.
  return {
    FragmentIR.location({ kind = "reg", reg = "rdi", value_type = "Ptr", name = "ctx" }),
    FragmentIR.location({ kind = "ctx_field", index = 0, value_type = "Ptr", name = "ctx.stack.synced_frame" }),
    FragmentIR.location({ kind = "immediate", index = kind == "entry" and 1 or 0, value_type = "Bool", name = "abstract_endpoint_contract" }),
  }
end

local function endpoint(endpoints, projections, kind, n)
  local start = #projections + 1
  local p = nil
  if kind ~= "entry" and kind ~= "ok" then
    p = Projection.for_exit(nil, n)
    local ok, perr = Projection.validate_projection(p)
    if not ok then return nil, perr end
    projections[#projections + 1] = p
  end
  local ep = FragmentIR.endpoint({
    kind = kind,
    source = n and n.source,
    exit = n and n.exit,
    contract = "ctx_rdi_synced_frame_abstract_v1",
    locations = standard_locations(kind),
    projection_start = kind ~= "entry" and kind ~= "ok" and start or nil,
    n_projections = kind ~= "entry" and kind ~= "ok" and 1 or 0,
    projections = p and { p } or {},
  })
  endpoints[#endpoints + 1] = ep
  return #endpoints
end

local EXIT_KIND_BY_OP = {
  ExitResidual = "residual_exit",
  ExitBoundary = "boundary_exit",
  ExitUnlowered = "unlowered_exit",
}

local CONTROL_KIND_BY_OP = {
  ExitResidual = "residual",
  ExitBoundary = "boundary",
  ExitUnlowered = "boundary",
}

function M.lower_result(ssa_result, config)
  config = config or {}
  local errors = {}
  local st = ssa_result and ssa_result.stencil
  if not st then return nil, { "missing stencil" } end

  for _, n in ipairs(st.ops or {}) do
    if not SUPPORTED_OP[n.op] then errors[#errors + 1] = "unsupported native fragment op: " .. tostring(n.op) end
  end

  local contract = Contract.from_result(ssa_result, config.facts or ssa_result.facts or {})
  if #(contract.deps or {}) > 0 then errors[#errors + 1] = "unsupported dependencies in native fragment: " .. table.concat(contract.deps, ",") end

  local data_relocs = {}
  for _, h in ipairs(st.holes or {}) do
    if h.role_kind == "exit" or h.role_kind == "fail" then
      errors[#errors + 1] = "control endpoint encoded as data hole: " .. tostring(h.role_kind)
    elseif not SUPPORTED_DATA_ROLE[h.role_kind] then
      errors[#errors + 1] = "unsupported native fragment data hole role: " .. tostring(h.role_kind)
    else
      data_relocs[#data_relocs + 1] = FragmentIR.data_reloc({
        code_offset = 0,
        code_offset_kind = "abstract_zero",
        reloc_kind = h.role_kind,
        role_kind = h.role_kind,
        op_idx = h.op_idx,
        role_arg = h.role_arg,
        hole_id = h.id,
        value_type = h.ty,
      })
    end
  end

  if #errors > 0 then return nil, errors end

  local endpoints, projections, control_relocs = {}, {}, {}
  endpoint(endpoints, projections, "entry", nil)
  endpoint(endpoints, projections, "ok", nil)

  for _, n in ipairs(st.ops or {}) do
    if n.op == "GuardI64" then
      local idx = assert(endpoint(endpoints, projections, "guard_exit", n))
      control_relocs[#control_relocs + 1] = FragmentIR.control_reloc({
        code_offset = 0,
        code_offset_kind = "abstract_zero",
        reloc_kind = "guard_fail",
        edge_kind = "guard_fail",
        endpoint_index = idx,
        source = n.source,
      })
    elseif EXIT_KIND_BY_OP[n.op] then
      local idx = assert(endpoint(endpoints, projections, EXIT_KIND_BY_OP[n.op], n))
      control_relocs[#control_relocs + 1] = FragmentIR.control_reloc({
        code_offset = 0,
        code_offset_kind = "abstract_zero",
        reloc_kind = CONTROL_KIND_BY_OP[n.op],
        edge_kind = CONTROL_KIND_BY_OP[n.op],
        endpoint_index = idx,
        source = n.source,
      })
    end
  end

  local abi = Abi.desc()
  local f = FragmentIR.fragment({
    name = "frag_" .. tostring(ssa_result.stencil_hash or "unknown"),
    physical_abi = Abi.ID,
    pattern_key = ssa_result.stencil_hash,
    len = #(ssa_result.source_ops or st.source_ops or {}),
    executable = false,
    layout = {
      mode = "abstract_fragment",
      executable = false,
      code_offsets = "abstract_zero",
      reason = "metadata-only fragment descriptor; no native assembler offsets emitted",
    },
    clobbers = copy_array(abi.clobbers),
    endpoints = endpoints,
    data_relocs = data_relocs,
    control_relocs = control_relocs,
    slotmaps = copy_array(st.slotmaps),
    projections = projections,
    dependencies = copy_array(contract.deps),
    fact_transfer = copy_contract(contract),
    active_node_specs = copy_array(ssa_result.active_node_specs),
    stencil_ops = copy_array(ssa_result.stencil_ops),
    source_ops = copy_array(ssa_result.source_ops or st.source_ops),
  })

  local ok, verrs = FragmentIR.validate_fragment(f)
  if not ok then return nil, verrs end
  f.abi = FragmentIR.lower_to_abi(f)
  return f
end

function M.generate(ssa_result, config)
  local fragment, errors = M.lower_result(ssa_result, config)
  return { ok = fragment ~= nil, fragment = fragment, errors = errors or {} }
end

return M
