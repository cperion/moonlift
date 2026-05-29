#!/usr/bin/env luajit

package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;" .. package.path

local Facts = require("src.facts")
local SSA = require("src.ssa")
local Projection = require("src.fragment_projection")
local StencilToFragment = require("src.stencil_to_fragment")

local function assert_eq(a, b, msg) if a ~= b then error((msg or "assert_eq failed") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end
local function assert_true(x, msg) if not x then error(msg or "assert_true failed", 2) end end

-- Synced-frame projections are explicit recipes.
do
  local p = Projection.synced_frame({ reason = "guard:is_i64", pc = 7 }, 0)
  assert_eq(p.kind, "SYNCED_FRAME", "projection kind")
  assert_eq(p.pc, 7, "projection pc")
end

-- I64 guard lowering gives every guard exit a projection, preserving source pc and flattened range.
do
  local facts = { Facts.fact("type", Facts.slot("R1"), "is_i64", true) }
  local r = SSA.compile({ { op = "ADDI", a = 1, b = 1, c = 1 } }, facts)
  assert_true(r.ok, table.concat(r.errors or {}, "\n"))
  local fr = StencilToFragment.generate(r, { facts = facts })
  assert_true(fr.ok, table.concat(fr.errors or {}, "\n"))
  local saw_guard = false
  for _, ep in ipairs(fr.fragment.endpoints or {}) do
    if ep.kind == "guard_exit" then
      saw_guard = true
      assert_true((ep.n_projections or 0) > 0, "guard exit must have projection")
      assert_true(ep.projection_start and fr.fragment.projections[ep.projection_start], "guard projection range missing")
      assert_true(ep.projections and ep.projections[1], "guard projection object missing")
      assert_eq(ep.projections[1].pc, 1, "guard projection must use SSA/stencil source pc")
      assert_eq(fr.fragment.projections[ep.projection_start].pc, 1, "flattened projection must use source pc")
    end
  end
  assert_true(saw_guard, "expected guard_exit endpoint")
end

print("ok - SpongeJIT fragment projection")
