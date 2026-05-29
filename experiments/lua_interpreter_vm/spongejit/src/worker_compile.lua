-- worker_compile.lua — One parallel worker: SSA compile + C codegen in one pass
-- Usage: luajit src/worker_compile.lua <chunk_id>
--
-- This is intentionally a repo file, not a /tmp heredoc/script: downstream
-- bank generation relies on the exact identity between a grammar form and the
-- generated C function name. Every unique form written to grammar_result_N.json
-- carries its func name, and grammar_holes_N.json carries the same func name.

package.path = 'src/?.lua;src/?/init.lua;' .. package.path

local SSA = require("src.ssa")
local StencilToC = require("src.stencil_to_c")
local Util = require("src.util")
local FactAxes = require("src.ssa_fact_axes")
local Contract = require("src.ssa_contract")

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

local forms_by_key = {}
local code_by_key = {}
local forms_in_order = {}
local lc, lok = 0, 0
local c_blocks, all_holes = {}, {}

for si, ops in ipairs(seqs) do
  local subsets = FactAxes.subsets(FactAxes.axes_for_ops(ops), config)
  for _, facts in ipairs(subsets) do
    local r = SSA.compile(ops, facts, config)
    lc = lc + 1
    if r.ok then
      lok = lok + 1
      local normal_key = r.stencil_hash
      local code_key = tostring(normal_key) .. "|" .. op_signature(ops)
      local contract = Contract.from_result(r, facts)
      local contract_key = table.concat({
        tostring(contract.selector_sig and contract.selector_sig.literal or ""),
        tostring(contract.required_sig and contract.required_sig.literal or ""),
        tostring(contract.checked_sig and contract.checked_sig.literal or ""),
        tostring(contract.produced_sig and contract.produced_sig.literal or ""),
        tostring(contract.killed_sig and contract.killed_sig.literal or ""),
      }, "|")
      local dedupe_key = code_key .. "|" .. contract_key
      local form = forms_by_key[dedupe_key]
      if not form then
        local c = code_by_key[code_key]
        if not c then
          c = StencilToC.generate(r, ops, {facts=facts, func_salt="c" .. tostring(ci)})
          code_by_key[code_key] = c
          c_blocks[#c_blocks+1] = c.c_code
          all_holes[#all_holes+1] = {func=c.func_name, key=normal_key, code_key=code_key, holes=c.hole_catalog}
        end
        form = {
          key=normal_key,
          code_key=code_key,
          dedupe_key=dedupe_key,
          func=c.func_name,
          stencil_hash=r.stencil_hash,
          stencil_form=r.stencil_form,
          stencil_key=r.stencil_key,
          stencil_ops=r.stencil_ops,
          stencil_slotmaps=r.slotmaps,
          ops=ops,
          facts=facts,
          contract=contract,
          count=0,
          changed=r.changed,
          source_ops=ops,
        }
        forms_by_key[dedupe_key] = form
        forms_in_order[#forms_in_order+1] = form
      end
      form.count = form.count + 1
    end
  end
  if progress_every > 0 and (si % progress_every == 0 or si == #seqs) then
    io.stderr:write(string.format("[W%d] %d/%d compiles=%d ok=%d forms=%d\n", ci, si, #seqs, lc, lok, #forms_in_order))
  end
end

-- Write C code chunk. Keep exactly one preamble, then every generated function.
local combined = {}
local first = c_blocks[1] or ""
local pe = first:find("void z_")
if pe then combined[#combined+1] = first:sub(1, pe-1) end
for _, block in ipairs(c_blocks) do
  local fs = block:find("void z_")
  if fs then combined[#combined+1] = "\n" .. block:sub(fs) end
end
Util.write_file(tmp("grammar_c_code_" .. ci .. ".c"), table.concat(combined))
Util.write_json(tmp("grammar_holes_" .. ci .. ".json"), all_holes)
Util.write_json(tmp("grammar_result_" .. ci .. ".json"), {forms=forms_in_order, compiles=lc, ok=lok})

io.stderr:write(string.format("[W%d] DONE seqs=%d compiles=%d ok=%d forms=%d\n", ci, #seqs, lc, lok, #forms_in_order))
