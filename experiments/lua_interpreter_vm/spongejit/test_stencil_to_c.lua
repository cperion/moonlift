#!/usr/bin/env luajit
-- test_stencil_to_c.lua — Stencil IR lowering, canonicalization, and C emission.

local source = debug.getinfo(1, "S").source
local spongejit = source and source:sub(1, 1) == "@" and source:sub(2):match("^(.*/spongejit)") or "."
package.path = spongejit .. "/?.lua;" .. spongejit .. "/?/init.lua;" .. package.path

local SSA = require("src.ssa")
local StencilToC = require("src.stencil_to_c")

local function assert_true(x, msg) if not x then error(msg or "assert_true failed", 2) end end
local function assert_eq(a, b, msg) if a ~= b then error((msg or "assert_eq failed") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end
local function has_op(st, op) for _, n in ipairs(st.ops or {}) do if n.op == op then return true end end return false end

-- Patchable immediates are abstracted out of the canonical hash.
do
  local r1 = SSA.compile({{op="LOADI", a=0, sbx=1}}, {})
  local r2 = SSA.compile({{op="LOADI", a=0, sbx=42}}, {})
  assert_true(r1.ok and r2.ok, "LOADI compiles")
  assert_eq(r1.stencil_hash, r2.stencil_hash, "LOADI immediate must be a hole, not hash input")
end

-- Slot numbers are canonical slot classes; same equality pattern hashes together.
do
  local facts1 = {{kind="type", subject={kind="slot", id="R1"}, predicate="is_i64", value=true}}
  local facts2 = {{kind="type", subject={kind="slot", id="R5"}, predicate="is_i64", value=true}}
  local r1 = SSA.compile({{op="ADDI", a=1, b=1, c=1}}, facts1)
  local r2 = SSA.compile({{op="ADDI", a=5, b=5, c=1}}, facts2)
  assert_true(r1.ok and r2.ok, "ADDI compiles")
  assert_eq(r1.stencil_hash, r2.stencil_hash, "same slot equality pattern should hash together")
end

-- Different slot alias patterns remain distinct.
do
  local facts1 = {{kind="type", subject={kind="slot", id="R1"}, predicate="is_i64", value=true}}
  local facts2 = {{kind="type", subject={kind="slot", id="R2"}, predicate="is_i64", value=true}}
  local r1 = SSA.compile({{op="ADDI", a=1, b=1, c=1}}, facts1)
  local r2 = SSA.compile({{op="ADDI", a=1, b=2, c=1}}, facts2)
  assert_true(r1.ok and r2.ok, "ADDI variants compile")
  assert_true(r1.stencil_hash ~= r2.stencil_hash, "different slot alias patterns must not collide")
end

-- BoxI64 + FrameStore fusion belongs to lowering, not C emission.
do
  local facts = {{kind="type", subject={kind="slot", id="R1"}, predicate="is_i64", value=true}}
  local r = SSA.compile({{op="ADDI", a=1, b=1, c=1}}, facts)
  assert_true(r.ok, table.concat(r.errors or {}, "\n"))
  assert_true(has_op(r.stencil, "StoreI64Slot"), "lowering should fuse boxed integer store")
  local c = StencilToC.generate(r)
  assert_eq(c.hole_count, #(r.stencil.holes or {}), "C emitter must not allocate holes")
  assert_true(c.c_code:match("base%[f_slot_"), "direct i64 slot store expected")
end

-- Unsupported raw SSA ops lower to explicit unlowered exits.
do
  local IR = require("src.ssa_ir")
  local Lower = require("src.ssa_to_stencil")
  local stmod = require("src.stencil_ir")
  local g = IR.new({}, {})
  g:add("MadeUpSSAOp", {source = 1, effect = "residual", exit = g:exit_projection("madeup", 1)})
  local st = Lower.lower(g, {{op="MOVE", a=0, b=0}}, {})
  local ok, errs = stmod.validate(st)
  assert_true(ok, table.concat(errs or {}, "\n"))
  assert_true(has_op(st, "ExitUnlowered"), "unlowered op should be explicit")
end

print("ok - Stencil IR lowering/canonicalization/C emission")
