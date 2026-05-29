#!/usr/bin/env luajit

package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;" .. package.path

local Facts = require("src.facts")
local SSA = require("src.ssa")
local StencilToFragment = require("src.stencil_to_fragment")

local function assert_eq(a, b, msg) if a ~= b then error((msg or "assert_eq failed") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end
local function assert_true(x, msg) if not x then error(msg or "assert_true failed", 2) end end
local function assert_false(x, msg) if x then error(msg or "assert_false failed", 2) end end

local function has_endpoint(f, kind)
  for _, ep in ipairs(f.endpoints or {}) do if ep.kind == kind then return true, ep end end
  return false
end

local function has_data_role(f, role)
  for _, r in ipairs(f.data_relocs or {}) do if r.role_kind == role then return true end end
  return false
end

local function has_control(f, kind)
  for _, r in ipairs(f.control_relocs or {}) do if r.edge_kind == kind then return true, r end end
  return false
end

local function has_error(errors, needle)
  for _, e in ipairs(errors or {}) do if tostring(e):find(needle, 1, true) then return true end end
  return false
end

local function assert_exit_projection(f, endpoint_kind, control_kind)
  local ok_ep, ep = has_endpoint(f, endpoint_kind)
  assert_true(ok_ep, endpoint_kind .. " endpoint missing")
  assert_true(ep.projection_start and f.projections[ep.projection_start], endpoint_kind .. " projection range missing")
  assert_true((ep.n_projections or 0) > 0, endpoint_kind .. " projection count missing")
  assert_true(has_control(f, control_kind), control_kind .. " control reloc missing")
end

-- End-to-end conforming i64 slot arithmetic fragment descriptor.
do
  local facts = { Facts.fact("type", Facts.slot("R1"), "is_i64", true) }
  local r = SSA.compile({ { op = "ADDI", a = 1, b = 1, c = 1 } }, facts)
  assert_true(r.ok, table.concat(r.errors or {}, "\n"))
  local fr = StencilToFragment.generate(r, { facts = facts })
  assert_true(fr.ok, table.concat(fr.errors or {}, "\n"))
  local f = fr.fragment
  assert_eq(f.physical_abi, "x86_64_sysv_spon_v1", "physical ABI")
  assert_eq(f.abi.fragment.physical_abi, 1, "ABI-lowered physical ABI")
  assert_eq(f.abi.fragment.flags, 1, "abstract fragment flag")
  assert_true(f.executable == false and f.layout.mode == "abstract_fragment", "fragment must be explicitly abstract/non-executable")
  assert_true(has_endpoint(f, "entry"), "entry endpoint missing")
  assert_true(has_endpoint(f, "ok"), "ok endpoint missing")
  assert_true(has_endpoint(f, "guard_exit"), "guard exit endpoint missing")
  for _, ep in ipairs(f.endpoints or {}) do assert_true(#(ep.locations or {}) > 0, "endpoint locations must be explicit") end
  assert_true(#(f.clobbers or {}) > 0, "fragment clobbers must be explicit")
  assert_true(has_data_role(f, "slot"), "slot data reloc missing")
  assert_true(has_data_role(f, "slot_store"), "slot_store data reloc missing")
  assert_true(has_data_role(f, "imm"), "imm data reloc missing")
  assert_true(has_control(f, "guard_fail"), "guard_fail control reloc missing")
  for _, dr in ipairs(f.data_relocs or {}) do
    assert_true(dr.role_kind ~= "fail" and dr.role_kind ~= "exit", "exit/fail must not be data relocs")
    assert_eq(dr.code_offset_kind, "abstract_zero", "abstract data reloc offset marker")
  end
  for _, cr in ipairs(f.control_relocs or {}) do assert_eq(cr.code_offset_kind, "abstract_zero", "abstract control reloc offset marker") end
  assert_true(f.fact_transfer.checked_sig, "checked signature missing")
  assert_true(f.fact_transfer.produced_sig, "produced signature missing")
  assert_true(f.fact_transfer.killed_sig, "killed signature missing")
end

-- Boundary exit lowering is covered and projected.
do
  local r = SSA.compile({ { op = "RETURN1", a = 1 } }, {})
  assert_true(r.ok, table.concat(r.errors or {}, "\n"))
  local fr = StencilToFragment.generate(r, {})
  assert_true(fr.ok, table.concat(fr.errors or {}, "\n"))
  assert_exit_projection(fr.fragment, "boundary_exit", "boundary")
end

-- Residual exit lowering is covered and projected.
do
  local r = SSA.compile({ { op = "POW", a = 1, b = 1, c = 1 } }, {})
  assert_true(r.ok, table.concat(r.errors or {}, "\n"))
  local fr = StencilToFragment.generate(r, {})
  assert_true(fr.ok, table.concat(fr.errors or {}, "\n"))
  assert_exit_projection(fr.fragment, "residual_exit", "residual")
end

-- Unlowered semantic node reopening is covered and projected.
do
  local r = SSA.compile_nodes({ { op = "MysteryNativeOp", source = 3, inputs = {}, outputs = {}, effect = "none" } }, {})
  assert_true(r.ok, table.concat(r.errors or {}, "\n"))
  local fr = StencilToFragment.generate(r, {})
  assert_true(fr.ok, table.concat(fr.errors or {}, "\n"))
  assert_exit_projection(fr.fragment, "unlowered_exit", "boundary")
end

-- Payload/dependency-heavy table/shape fragments reject loudly.
do
  local r = SSA.compile({ "GETFIELD" }, { "table", "shape_known", "metatable_absent", "key_const" })
  assert_true(r.ok, table.concat(r.errors or {}, "\n"))
  local fr = StencilToFragment.generate(r, { facts = { "table", "shape_known", "metatable_absent", "key_const" } })
  assert_false(fr.ok, "shape/table fragment must reject unsupported payload/dependency surface")
  assert_true(has_error(fr.errors, "unsupported"), table.concat(fr.errors or {}, "\n"))
end

print("ok - SpongeJIT stencil to native fragment")
