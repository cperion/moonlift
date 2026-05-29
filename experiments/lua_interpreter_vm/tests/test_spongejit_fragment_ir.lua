#!/usr/bin/env luajit

package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;" .. package.path

local FragmentIR = require("src.fragment_ir")
local Abi = require("src.fragment_abi_x64")

local function assert_eq(a, b, msg) if a ~= b then error((msg or "assert_eq failed") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end
local function assert_true(x, msg) if not x then error(msg or "assert_true failed", 2) end end
local function assert_false(x, msg) if x then error(msg or "assert_false failed", 2) end end
local function has_error(errors, needle)
  for _, e in ipairs(errors or {}) do if tostring(e):find(needle, 1, true) then return true end end
  return false
end

local function fact_transfer()
  return {
    selector_sig = { literal = "0x0ULL" },
    required_sig = { literal = "0x0ULL" },
    checked_sig = { literal = "0x0ULL" },
    produced_sig = { literal = "0x0ULL" },
    killed_sig = { literal = "0x0ULL" },
  }
end

local function locs()
  return {
    FragmentIR.location({ kind = "reg", reg = "rdi", value_type = "Ptr", name = "ctx" }),
    FragmentIR.location({ kind = "ctx_field", index = 0, value_type = "Ptr", name = "ctx.stack.synced_frame" }),
  }
end

local function ep(kind, overrides)
  local e = FragmentIR.endpoint({ kind = kind, locations = locs() })
  for k, v in pairs(overrides or {}) do e[k] = v end
  return e
end

local function minimal(overrides)
  local f = FragmentIR.fragment({
    physical_abi = "x86_64_sysv_spon_v1",
    clobbers = Abi.desc().clobbers,
    endpoints = { ep("entry"), ep("ok") },
    fact_transfer = fact_transfer(),
  })
  for k, v in pairs(overrides or {}) do f[k] = v end
  f.abi = FragmentIR.lower_to_abi(f)
  return f
end

-- Valid minimal abstract fragment with entry + ok + fact transfer passes and has ABI-lowered numeric metadata.
do
  local f = minimal()
  local ok, errors = FragmentIR.validate_fragment(f)
  assert_true(ok, table.concat(errors or {}, "\n"))
  assert_eq(f.abi.fragment.physical_abi, 1, "ABI physical_abi must be numeric")
  assert_eq(f.abi.endpoints[1].kind, 1, "ABI endpoint kind must be numeric")
  assert_true(tostring(f.abi.fragment.pattern_key):match("^0x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%xULL$"), "ABI pattern_key must be a deterministic uint64 literal")
  assert_eq(type(f.abi.fragment.pattern_key_hi), "number", "ABI pattern_key_hi must be numeric")
  assert_eq(type(f.abi.fragment.pattern_key_lo), "number", "ABI pattern_key_lo must be numeric")
  assert_eq(type(f.abi.fragment.selector_sig_hi), "number", "ABI selector_sig_hi must be numeric")
  assert_eq(type(f.abi.fragment.selector_sig_lo), "number", "ABI selector_sig_lo must be numeric")
  assert_true(f.abi.executable == false, "minimal metadata fragment must be abstract/non-executable")
end

-- Missing entry fails.
do
  local ok, errors = FragmentIR.validate_fragment(minimal({ endpoints = { ep("ok") } }))
  assert_false(ok, "missing entry must fail")
  assert_true(has_error(errors, "entry"), table.concat(errors or {}, "\n"))
end

-- Missing endpoint locations fails.
do
  local ok, errors = FragmentIR.validate_fragment(minimal({ endpoints = { FragmentIR.endpoint({ kind = "entry" }), ep("ok") } }))
  assert_false(ok, "empty endpoint locations must fail")
  assert_true(has_error(errors, "location contract"), table.concat(errors or {}, "\n"))
end

-- Missing fact transfer fails.
do
  local f = minimal()
  f.fact_transfer = nil
  local ok, errors = FragmentIR.validate_fragment(f)
  assert_false(ok, "missing fact_transfer must fail")
  assert_true(has_error(errors, "fact_transfer"), table.concat(errors or {}, "\n"))
end

-- Data reloc with role fail or exit fails.
do
  local ok, errors = FragmentIR.validate_fragment(minimal({ data_relocs = { FragmentIR.data_reloc({ role_kind = "fail", code_offset_kind = "abstract_zero" }) } }))
  assert_false(ok, "fail data reloc must fail")
  assert_true(has_error(errors, "control role"), table.concat(errors or {}, "\n"))
  ok, errors = FragmentIR.validate_fragment(minimal({ data_relocs = { FragmentIR.data_reloc({ role_kind = "exit", code_offset_kind = "abstract_zero" }) } }))
  assert_false(ok, "exit data reloc must fail")
end

-- Non-success endpoint without projection fails.
do
  local f = minimal({ endpoints = { ep("entry"), ep("ok"), ep("guard_exit") } })
  local ok, errors = FragmentIR.validate_fragment(f)
  assert_false(ok, "guard_exit without projection must fail")
  assert_true(has_error(errors, "without projection"), table.concat(errors or {}, "\n"))
end

-- Projection ranges must correspond to actual projection objects.
do
  local f = minimal({ endpoints = { ep("entry"), ep("ok"), ep("guard_exit", { projection_start = 1, n_projections = 1 }) }, projections = {} })
  local ok, errors = FragmentIR.validate_fragment(f)
  assert_false(ok, "n_projections alone must not validate")
  assert_true(has_error(errors, "out of bounds"), table.concat(errors or {}, "\n"))

  f = minimal({ endpoints = { ep("entry"), ep("ok"), ep("guard_exit", { projection_start = 1, n_projections = 1 }) }, projections = { { kind = "BAD", pc = 1 } } })
  ok, errors = FragmentIR.validate_fragment(f)
  assert_false(ok, "bad projection kind must fail")
  assert_true(has_error(errors, "unknown projection kind"), table.concat(errors or {}, "\n"))
end

-- Control reloc using data role fails.
do
  local ok, errors = FragmentIR.validate_fragment(minimal({ control_relocs = { FragmentIR.control_reloc({ edge_kind = "slot", endpoint_index = 2, code_offset_kind = "abstract_zero" }) } }))
  assert_false(ok, "data role control reloc must fail")
  assert_true(has_error(errors, "data role"), table.concat(errors or {}, "\n"))
end

-- Abstract zero code offsets must be marked, so placeholders are explicit.
do
  local ok, errors = FragmentIR.validate_fragment(minimal({ data_relocs = { FragmentIR.data_reloc({ role_kind = "slot", code_offset = 0 }) } }))
  assert_false(ok, "unmarked zero code offset must fail in abstract descriptors")
  assert_true(has_error(errors, "abstract_zero"), table.concat(errors or {}, "\n"))
end

print("ok - SpongeJIT fragment IR validation")
