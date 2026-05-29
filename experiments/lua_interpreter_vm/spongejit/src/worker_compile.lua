-- worker_compile.lua — One parallel worker: SSA compile + native fragment metadata.
-- Usage: luajit src/worker_compile.lua <chunk_id>
--
-- C-function-shaped stencils are non-conforming. Workers emit the unified
-- native fragment metadata artifacts consumed by floor selection and hotter
-- online composition.

package.path = 'src/?.lua;src/?/init.lua;' .. package.path

local SSA = require("src.ssa")
local StencilToFragment = require("src.stencil_to_fragment")
local FragmentIR = require("src.fragment_ir")
local Util = require("src.util")
local FactAxes = require("src.ssa_fact_axes")

local ci = tonumber(arg[1])
assert(ci, "usage: luajit src/worker_compile.lua <chunk_id>")

local config = {
  max_fact_combos = tonumber(os.getenv("MAX_FACT_COMBOS") or "0") or 0,
  fact_axis_mode = tostring(os.getenv("FACT_AXIS_MODE") or "curated"),
}
local progress_every = tonumber(os.getenv("WORKER_PROGRESS_SEQS") or "1000") or 1000

local tmpdir = os.getenv("SPON_TMP") or "/tmp"
local function tmp(name) return tmpdir .. "/" .. name end
local seqs = Util.read_json(tmp("grammar_chunk_" .. ci .. ".json"))

io.stderr:write(string.format("[W%d] START seqs=%d fact_mode=%s max_fact_combos=%s\n",
  ci, #seqs, config.fact_axis_mode, tostring(config.max_fact_combos)))

local function op_signature(ops)
  local parts = {}
  for _, op in ipairs(ops or {}) do parts[#parts+1] = type(op)=="table" and tostring(op.op) or tostring(op) end
  return table.concat(parts, "|")
end

local function contract_key(contract)
  return table.concat({
    tostring(contract.selector_sig and contract.selector_sig.literal or ""),
    tostring(contract.required_sig and contract.required_sig.literal or ""),
    tostring(contract.checked_sig and contract.checked_sig.literal or ""),
    tostring(contract.produced_sig and contract.produced_sig.literal or ""),
    tostring(contract.killed_sig and contract.killed_sig.literal or ""),
  }, "|")
end

local forms_by_key = {}
local fragments_in_order = {}
local forms_in_order = {}
local lc, lok, lssa_ok, lrejected = 0, 0, 0, 0

for si, ops in ipairs(seqs) do
  local subsets = FactAxes.subsets(FactAxes.axes_for_ops(ops), config)
  for _, facts in ipairs(subsets) do
    local r = SSA.compile(ops, facts, config)
    lc = lc + 1
    if r.ok then
      lssa_ok = lssa_ok + 1
      local frag_result = StencilToFragment.generate(r, { facts = facts })
      if frag_result.ok then
        lok = lok + 1
        local fragment = frag_result.fragment
        local normal_key = r.stencil_hash
        local code_key = tostring(normal_key) .. "|" .. op_signature(ops)
        local dedupe_key = code_key .. "|" .. contract_key(fragment.fact_transfer)
        local form = forms_by_key[dedupe_key]
        if not form then
          fragment.fragment_id = #fragments_in_order + 1
          fragment.abi = FragmentIR.lower_to_abi(fragment)
          fragments_in_order[#fragments_in_order + 1] = fragment
          form = {
            key = normal_key,
            fragment_id = fragment.fragment_id,
            fragment_name = fragment.name,
            code_key = code_key,
            dedupe_key = dedupe_key,
            stencil_hash = r.stencil_hash,
            stencil_form = r.stencil_form,
            stencil_key = r.stencil_key,
            stencil_ops = r.stencil_ops,
            stencil_slotmaps = r.slotmaps,
            ops = ops,
            facts = facts,
            contract = fragment.fact_transfer,
            fragment_abi = fragment.abi.fragment,
            count = 0,
            changed = r.changed,
            source_ops = ops,
          }
          forms_by_key[dedupe_key] = form
          forms_in_order[#forms_in_order + 1] = form
        end
        form.count = form.count + 1
      else
        lrejected = lrejected + 1
      end
    end
  end
  if progress_every > 0 and (si % progress_every == 0 or si == #seqs) then
    io.stderr:write(string.format("[W%d] %d/%d compiles=%d ssa_ok=%d fragments=%d rejected=%d forms=%d\n", ci, si, #seqs, lc, lssa_ok, lok, lrejected, #forms_in_order))
  end
end

Util.write_json(tmp("grammar_fragments_" .. ci .. ".json"), { fragments = fragments_in_order })
Util.write_json(tmp("grammar_result_" .. ci .. ".json"), { forms = forms_in_order, compiles = lc, ok = lok, ssa_ok = lssa_ok, rejected = lrejected })

io.stderr:write(string.format("[W%d] DONE seqs=%d compiles=%d ssa_ok=%d fragments=%d rejected=%d forms=%d\n", ci, #seqs, lc, lssa_ok, lok, lrejected, #forms_in_order))
