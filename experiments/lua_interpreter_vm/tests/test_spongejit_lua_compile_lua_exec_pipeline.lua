#!/usr/bin/env luajit
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;./experiments/lua_interpreter_vm/spongejit/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local lalin = require("lalin")
local C = require("lua_compile")
local Schema = require("lua_compile.schema")
local pvm = require("lalin.pvm")
local T = Schema.get()
local ExecLower = require("lua_compile.lua_src_to_lua_exec_lower")
local ExecToLalin = require("lua_compile.lua_exec_to_lalin_cfg_lower")
local ExecValidate = require("lua_compile.lua_exec_validate")
local CFGValidate = require("lua_compile.lalin_cfg_validate")
local Emit = require("lua_compile.lalin_cfg_emit")
local OutcomeModel = require("lua_compile.lua_rt_outcome_model")
local ValueModel = require("lua_compile.lua_rt_value_model")
local RT, Exec, CFG, Src = T.LuaRT, T.LuaExec, T.LalinCFG, T.LuaSrc

ffi.cdef[[
typedef struct { int64_t tag; int64_t payload_i64; double payload_f64; } LuaRTValue;
]]

local function runtime_value(tag_name, payload_i64, payload_f64)
  local x = ffi.new("LuaRTValue")
  x.tag = ValueModel.TAG[tag_name]
  x.payload_i64 = payload_i64 or 0
  x.payload_f64 = payload_f64 or 0
  return x
end

local function contains_class(v, pred, seen)
  if type(v) ~= "table" then return false end
  seen = seen or {}; if seen[v] then return false end; seen[v] = true
  local cls = pvm.classof(v)
  if pred(cls) then return true end
  if cls and cls.__fields then
    for _, f in ipairs(cls.__fields) do if contains_class(v[f.name], pred, seen) then return true end end
  elseif not cls then
    for _, x in pairs(v) do if contains_class(x, pred, seen) then return true end end
  end
  return false
end

local function assert_no_luasrc_or_protocol(kernel)
  assert(not contains_class(kernel, function(cls) return Src.Op.members[cls] end), "LalinCFG output must not contain LuaSrc opcode nodes")
  assert(not contains_class(kernel, function(cls)
    local plan = cls and rawget(cls, "__plan")
    local cname = tostring((plan and plan.name) or "")
    return cname:match("ProtocolExit")
  end), "LalinCFG output must not contain protocol-exit concepts")
end

local function lower_exec(events, evidence)
  local unit = C.unit_from_events(events, evidence or {})
  local exec_kernel, exec_errors = ExecLower.lower(unit.source, unit.evidence)
  assert(exec_kernel, "LuaExec lowering rejected fixture: " .. table.concat(exec_errors or {}, "; "))
  local ok, errs = ExecValidate.kernel(exec_kernel)
  assert(ok, table.concat(errs or {}, "\n"))
  local cfg_kernel, cfg_errors = ExecToLalin.lower(exec_kernel)
  assert(cfg_kernel, "LuaExec->LalinCFG rejected fixture: " .. table.concat(cfg_errors or {}, "; "))
  ok, errs = CFGValidate.validate(cfg_kernel)
  assert(ok, table.concat(errs or {}, "\n"))
  assert_no_luasrc_or_protocol(cfg_kernel)
  return exec_kernel, cfg_kernel
end

local run_kernel

local function lower_outcome(events, evidence, projection)
  local unit = C.unit_from_events(events, evidence or {})
  local exec_kernel, exec_errors = ExecLower.lower(unit.source, unit.evidence)
  assert(exec_kernel, "LuaExec lowering rejected outcome fixture: " .. table.concat(exec_errors or {}, "; "))
  local cfg_kernel, cfg_errors = ExecToLalin.lower_outcome(exec_kernel, projection)
  assert(cfg_kernel, "LuaExec->LalinCFG outcome rejected fixture: " .. table.concat(cfg_errors or {}, "; "))
  local ok, errs = CFGValidate.validate(cfg_kernel)
  assert(ok, table.concat(errs or {}, "\n"))
  assert_no_luasrc_or_protocol(cfg_kernel)
  return exec_kernel, cfg_kernel
end

local function run_outcome(events, evidence, projection, name, ...)
  local _exec, cfg = lower_outcome(events, evidence, projection)
  return run_kernel(cfg, name, ...)
end

local function compile_kernel(events, evidence)
  local r = C.compile_to_lalin_kernel(C.unit_from_events(events, evidence or {}))
  assert(r.kind == "Ok", "compile rejected fixture")
  local k = r.product.kernel
  assert(k.id.name.text == "lua_exec_core_kernel", "compile_to_lalin_kernel should use LuaExec core path for this fixture")
  return k
end

local dyn_return_public = C.compile_to_lalin_kernel(C.unit_from_events({ {op="RETURN1", pc=1, a=1} }, {}))
assert(dyn_return_public.kind == "Ok", "dynamic RETURN1 should not hard-error after outcome retry")
assert(dyn_return_public.product.kernel.id.name.text == "lua_exec_core_kernel")
local dyn_return_src = Emit.emit(dyn_return_public.product.kernel, { name = "test_public_dynamic_return1_outcome" })
assert(dyn_return_src:match("LuaRTOutcome"), "dynamic RETURN1 public compile should lower through typed outcome projection")
local arity_exec = assert(ExecLower.lower(C.unit_from_events({ {op="LOADI", pc=1, a=1, b=5}, {op="RETURN1", pc=2, a=1} }, {}).source, C.unit_from_events({ {op="LOADI", pc=1, a=1, b=5}, {op="RETURN1", pc=2, a=1} }, {}).evidence))
assert(contains_class(arity_exec.contract, function(cls) return cls == Exec.RequiresArityShape end), "RETURN must carry RequiresArityShape")
assert(contains_class(arity_exec.contract, function(cls) return cls == Exec.RequiresResultChannel end), "RETURN must carry RequiresResultChannel")
assert(contains_class(arity_exec.contract, function(cls) return cls == Exec.NormalizesArity end), "RETURN must carry NormalizesArity")
assert(contains_class(arity_exec.contract, function(cls) return cls == Exec.ProducesResultChannel end), "RETURN must carry ProducesResultChannel")

function run_kernel(kernel, name, ...)
  local src = Emit.emit(kernel, { name = name })
  assert(not src:match("out_tag") and not src:match("out_event_kind"), "LuaExec path must not emit protocol ABI")
  local fn = assert(lalin.loadstring(src, "=(" .. name .. ")"))()
  local native = assert(fn:compile())
  local out = native(...)
  if type(out) == "cdata" then out = tonumber(out) or tonumber(tostring(out):match("^-?%d+")) or out end
  native:free()
  return out, src
end

-- LuaRT/LuaExec structural truthiness: nil and false are falsey, true and i64
-- are truthy. NOT is represented as NotTruthinessExpr before LalinCFG lowering.
local exec_nil, cfg_nil = lower_exec({
  {op="LOADNIL", pc=1, a=1, b=1},
  {op="NOT", pc=2, a=2, b=1},
  {op="RETURN1", pc=3, a=2},
}, {})
assert(contains_class(exec_nil, function(cls) return cls == Exec.NotTruthinessExpr end), "NOT must lower through LuaExec.NotTruthinessExpr")
local r_nil = run_kernel(cfg_nil, "test_lua_exec_not_nil")
assert(r_nil == true, tostring(r_nil))

local _, cfg_false = lower_exec({ {op="LOADFALSE", pc=1, a=1}, {op="NOT", pc=2, a=2, b=1}, {op="RETURN1", pc=3, a=2} }, {})
local r_false = run_kernel(cfg_false, "test_lua_exec_not_false")
assert(r_false == true, tostring(r_false))
local _, cfg_true = lower_exec({ {op="LOADTRUE", pc=1, a=1}, {op="NOT", pc=2, a=2, b=1}, {op="RETURN1", pc=3, a=2} }, {})
local r_true = run_kernel(cfg_true, "test_lua_exec_not_true")
assert(r_true == false, tostring(r_true))
local _, cfg_i64 = lower_exec({ {op="LOADI", pc=1, a=1, b=0}, {op="NOT", pc=2, a=2, b=1}, {op="RETURN1", pc=3, a=2} }, {})
local r_i64 = run_kernel(cfg_i64, "test_lua_exec_not_i64_zero_truthy")
assert(r_i64 == false, tostring(r_i64))

-- TEST uses LuaExec.TruthinessChoice, not a Lalin bool-only source shortcut.
local exec_test_nil, cfg_test_nil = lower_exec({
  {op="LOADNIL", pc=1, a=1, b=1},
  {op="TEST", pc=2, a=1, k=true},
  {op="JMP", pc=3, offset=2},
  {op="LOADI", pc=4, a=2, b=22},
  {op="RETURN1", pc=5, a=2},
  {op="LOADI", pc=6, a=2, b=11},
  {op="RETURN1", pc=7, a=2},
}, {})
assert(contains_class(exec_test_nil, function(cls) return cls == Exec.TruthinessChoice end), "TEST must lower through LuaExec.TruthinessChoice")
assert(run_kernel(cfg_test_nil, "test_lua_exec_test_nil") == 22)

local _, cfg_test_false = lower_exec({
  {op="LOADFALSE", pc=1, a=1}, {op="TEST", pc=2, a=1, k=true}, {op="JMP", pc=3, offset=2},
  {op="LOADI", pc=4, a=2, b=22}, {op="RETURN1", pc=5, a=2}, {op="LOADI", pc=6, a=2, b=11}, {op="RETURN1", pc=7, a=2},
}, {})
assert(run_kernel(cfg_test_false, "test_lua_exec_test_false") == 22)
local _, cfg_test_true = lower_exec({
  {op="LOADTRUE", pc=1, a=1}, {op="TEST", pc=2, a=1, k=true}, {op="JMP", pc=3, offset=2},
  {op="LOADI", pc=4, a=2, b=22}, {op="RETURN1", pc=5, a=2}, {op="LOADI", pc=6, a=2, b=11}, {op="RETURN1", pc=7, a=2},
}, {})
assert(run_kernel(cfg_test_true, "test_lua_exec_test_true") == 11)
local _, cfg_test_i64 = lower_exec({
  {op="LOADI", pc=1, a=1, b=0}, {op="TEST", pc=2, a=1, k=true}, {op="JMP", pc=3, offset=2},
  {op="LOADI", pc=4, a=2, b=22}, {op="RETURN1", pc=5, a=2}, {op="LOADI", pc=6, a=2, b=11}, {op="RETURN1", pc=7, a=2},
}, {})
assert(run_kernel(cfg_test_i64, "test_lua_exec_test_i64_truthy") == 11)

-- TESTSET copies the represented Lua value on the taken edge. The semantic copy
-- appears in LuaExec BranchArgs, then mechanically becomes LalinCFG BranchArgs.
local exec_testset_i64, cfg_testset_i64 = lower_exec({
  {op="TESTSET", pc=1, a=2, b=1, k=true},
  {op="JMP", pc=2, offset=2},
  {op="LOADI", pc=3, a=2, b=0},
  {op="RETURN1", pc=4, a=2},
  {op="RETURN1", pc=5, a=2},
}, { {slot=1,predicate="is_i64"}, {slot=2,predicate="is_i64"} })
assert(contains_class(exec_testset_i64, function(cls) return cls == Exec.BranchArgs end), "TESTSET live copy must use LuaExec.BranchArgs")
assert(run_kernel(cfg_testset_i64, "test_lua_exec_testset_i64", 123) == 123)

local exec_testset_bool, cfg_testset_bool = lower_exec({
  {op="TESTSET", pc=1, a=2, b=1, k=true}, {op="JMP", pc=2, offset=2},
  {op="LOADFALSE", pc=3, a=2}, {op="RETURN1", pc=4, a=2}, {op="RETURN1", pc=5, a=2},
}, { {slot=1,predicate="is_bool"}, {slot=2,predicate="is_bool"} })
assert(contains_class(exec_testset_bool, function(cls) return cls == Exec.BranchArgs end), "dynamic bool TESTSET must use LuaExec.BranchArgs")
assert(contains_class(cfg_testset_bool, function(cls) return cls == CFG.BranchArgs end), "dynamic bool TESTSET must lower to LalinCFG BranchArgs")
assert(run_kernel(cfg_testset_bool, "test_lua_exec_testset_bool_true", true) == true)
assert(run_kernel(cfg_testset_bool, "test_lua_exec_testset_bool_false", false) == false)

-- Fixed RETURN uses LuaRT.ValueSeq / LuaExec.Return, and outcome mode turns
-- it into an explicit LuaRTOutcome with kind/count/value fields.
local exec_return, cfg_return = lower_exec({ {op="LOADI", pc=1, a=1, b=77}, {op="RETURN", pc=2, a=1, b=2, c=0, k=false} }, {})
assert(contains_class(exec_return, function(cls) return cls == RT.ValueSeq end), "fixed RETURN must carry LuaRT.ValueSeq")
assert(run_kernel(cfg_return, "test_lua_exec_fixed_return") == 77)
assert(run_outcome({ {op="LOADNIL", pc=1, a=1, b=1}, {op="RETURN1", pc=2, a=1} }, {}, "kind", "test_outcome_nil_kind") == OutcomeModel.OUTCOME_KIND.NormalReturnOutcome)
assert(run_outcome({ {op="LOADNIL", pc=1, a=1, b=1}, {op="RETURN1", pc=2, a=1} }, {}, "count", "test_outcome_nil_count") == 1)
assert(run_outcome({ {op="LOADNIL", pc=1, a=1, b=1}, {op="RETURN1", pc=2, a=1} }, {}, "value0_tag", "test_outcome_nil_tag") == ValueModel.TAG.NilTag)
assert(run_outcome({ {op="LOADFALSE", pc=1, a=1}, {op="RETURN1", pc=2, a=1} }, {}, "value0_tag", "test_outcome_false_tag") == ValueModel.TAG.FalseTag)
assert(run_outcome({ {op="LOADTRUE", pc=1, a=1}, {op="RETURN1", pc=2, a=1} }, {}, "value0_tag", "test_outcome_true_tag") == ValueModel.TAG.TrueTag)
assert(run_outcome({ {op="LOADI", pc=1, a=1, b=77}, {op="RETURN1", pc=2, a=1} }, {}, "value0_payload_i64", "test_outcome_i64_payload") == 77)

-- ERRNNIL follows PUC: it errors when R[A] is non-nil; nil falls through to
-- the closed in-window continuation. The error is a typed outcome, not a host
-- protocol tag.
assert(run_outcome({ {op="LOADNIL", pc=1, a=1, b=1}, {op="ERRNNIL", pc=2, a=1, bx=99}, {op="RETURN0", pc=3} }, {}, "kind", "test_errnnil_nil_ok_kind") == OutcomeModel.OUTCOME_KIND.NormalReturnOutcome)
assert(run_outcome({ {op="LOADNIL", pc=1, a=1, b=1}, {op="ERRNNIL", pc=2, a=1, bx=99}, {op="RETURN0", pc=3} }, {}, "count", "test_errnnil_nil_ok_count") == 0)
assert(run_outcome({ {op="LOADI", pc=1, a=1, b=5}, {op="ERRNNIL", pc=2, a=1, bx=99}, {op="RETURN0", pc=3} }, {}, "kind", "test_errnnil_i64_error_kind") == OutcomeModel.OUTCOME_KIND.LuaErrorOutcome)
assert(run_outcome({ {op="LOADI", pc=1, a=1, b=5}, {op="ERRNNIL", pc=2, a=1, bx=99}, {op="RETURN0", pc=3} }, {}, "error_kind", "test_errnnil_i64_error_code") == OutcomeModel.ERROR_KIND.ErrNnilError)
assert(run_outcome({ {op="LOADI", pc=1, a=1, b=5}, {op="ERRNNIL", pc=2, a=1, bx=99}, {op="RETURN0", pc=3} }, {}, "error_value_tag", "test_errnnil_i64_error_value_tag") == ValueModel.TAG.IntegerTag)
assert(run_outcome({ {op="LOADI", pc=1, a=1, b=5}, {op="ERRNNIL", pc=2, a=1, bx=99}, {op="RETURN0", pc=3} }, {}, "error_value_payload_i64", "test_errnnil_i64_error_payload") == 5)

-- Standalone ERRNNIL still compiles as an executable runtime check. With no
-- following in-window continuation, nil produces a normal zero-result outcome;
-- any non-nil LuaRTValue produces ErrNnilError. This uses tag checks, not
-- evidence/fact proof.
local standalone_errnnil = { {op="ERRNNIL", pc=1, a=1, bx=123} }
assert(run_outcome(standalone_errnnil, {}, "kind", "test_errnnil_standalone_nil_kind", runtime_value("NilTag")) == OutcomeModel.OUTCOME_KIND.NormalReturnOutcome)
assert(run_outcome(standalone_errnnil, {}, "count", "test_errnnil_standalone_nil_count", runtime_value("NilTag")) == 0)
assert(run_outcome(standalone_errnnil, {}, "kind", "test_errnnil_standalone_i64_kind", runtime_value("IntegerTag", 5)) == OutcomeModel.OUTCOME_KIND.LuaErrorOutcome)
assert(run_outcome(standalone_errnnil, {}, "error_kind", "test_errnnil_standalone_i64_error", runtime_value("IntegerTag", 5)) == OutcomeModel.ERROR_KIND.ErrNnilError)
assert(run_outcome(standalone_errnnil, {}, "error_value_payload_i64", "test_errnnil_standalone_i64_payload", runtime_value("IntegerTag", 5)) == 5)
assert(run_outcome(standalone_errnnil, {}, "error_kind", "test_errnnil_standalone_false_error", runtime_value("FalseTag")) == OutcomeModel.ERROR_KIND.ErrNnilError)
assert(run_outcome(standalone_errnnil, {}, "error_kind", "test_errnnil_standalone_string_error", runtime_value("ShortStringTag", 44)) == OutcomeModel.ERROR_KIND.ErrNnilError)
local standalone_unit = C.unit_from_events(standalone_errnnil, {})
assert(standalone_unit.source.ops[1].name_index.value == 123, "ERRNNIL Bx/name_index must remain preserved in LuaSrc")

-- Nil can continue through an in-window continuation after ERRNNIL; non-nil
-- exits through the typed error outcome.
assert(run_outcome({ {op="LOADNIL", pc=1, a=1, b=1}, {op="ERRNNIL", pc=2, a=1, bx=77}, {op="LOADI", pc=3, a=2, b=42}, {op="RETURN1", pc=4, a=2} }, {}, "value0_payload_i64", "test_errnnil_nil_continues_to_return") == 42)
assert(run_outcome({ {op="LOADI", pc=1, a=1, b=9}, {op="ERRNNIL", pc=2, a=1, bx=77}, {op="LOADI", pc=3, a=2, b=42}, {op="RETURN1", pc=4, a=2} }, {}, "error_kind", "test_errnnil_non_nil_skips_continuation") == OutcomeModel.ERROR_KIND.ErrNnilError)
local compiled_standalone = compile_kernel(standalone_errnnil, {})
local standalone_src = Emit.emit(compiled_standalone, { name = "test_errnnil_compile_kernel_src" })
assert(not standalone_src:match("out_tag") and not standalone_src:match("out_event_kind"), "standalone ERRNNIL must not emit protocol ABI")
assert(standalone_src:match("%.tag%s*==") and standalone_src:match("LuaRTOutcome"), "standalone ERRNNIL must emit explicit LuaRTValue tag check and typed outcome construction")

-- Manual LuaExec error region also lowers mechanically to a typed Lua error outcome.
local function rt_name(s) return RT.Name(s) end
local function ex_name(s) return Exec.Name(s) end
local fr = RT.FrameRef(rt_name("manual_frame"))
local top = RT.TopRef(fr)
local slot1 = RT.StackValue(fr, RT.Slot(1))
local manual_ops = { Exec.AssignValue(slot1, Exec.ConstTValue(RT.IntValue(123))) }
local manual_error = RT.ErrorState(RT.RuntimeError, slot1, RT.Pc(44), top)
local manual_block = Exec.Block(Exec.BlockId(ex_name("entry")), {}, manual_ops, Exec.Error(manual_error))
local manual_region = Exec.Region(ex_name("manual_error_body"), Exec.ErrorRegion, {}, {}, Exec.BlockId(ex_name("entry")), { manual_block })
local manual_frame = RT.Frame(fr, RT.StackRef(fr), top, RT.NoVarargs, RT.CloseChain(fr, {}), RT.Pc(44))
local manual_kernel = Exec.Kernel(ex_name("manual_error_kernel"), manual_frame, manual_region, Exec.Contract({}, {}))
local manual_cfg = assert(ExecToLalin.lower_outcome(manual_kernel, "error_kind"))
assert(run_kernel(manual_cfg, "test_manual_lua_exec_error_outcome") == OutcomeModel.ERROR_KIND.RuntimeError)
local manual_payload_cfg = assert(ExecToLalin.lower_outcome(manual_kernel, "error_value_payload_i64"))
assert(run_kernel(manual_payload_cfg, "test_manual_lua_exec_error_payload") == 123)

local empty_yield_seq = RT.ValueSeq(RT.FixedSeq, {}, RT.FixedCount(0), RT.FromLiteralValues)
local manual_yield = RT.YieldState(RT.Pc(55), top, empty_yield_seq, RT.ResumeCall)
local yield_block = Exec.Block(Exec.BlockId(ex_name("entry")), {}, {}, Exec.Yield(manual_yield))
local yield_region = Exec.Region(ex_name("manual_yield_body"), Exec.YieldRegion, {}, {}, Exec.BlockId(ex_name("entry")), { yield_block })
local yield_kernel = Exec.Kernel(ex_name("manual_yield_kernel"), manual_frame, yield_region, Exec.Contract({}, {}))
local yield_cfg = assert(ExecToLalin.lower_outcome(yield_kernel, "yield_kind"))
assert(run_kernel(yield_cfg, "test_manual_lua_exec_yield_outcome") == OutcomeModel.YIELD_KIND.ResumeCall)

-- Closed JMP and comparison+JMP control run through LuaExec path for supported core values.
local cfg_jmp = compile_kernel({
  {op="LOADI", pc=1, a=1, b=1}, {op="JMP", pc=2, offset=1},
  {op="LOADI", pc=3, a=1, b=2}, {op="RETURN1", pc=4, a=1},
}, {})
assert(run_kernel(cfg_jmp, "test_lua_exec_compile_closed_jmp") == 1)
local cfg_branch = compile_kernel({
  {op="EQI", pc=1, a=1, sb=0, k=true}, {op="JMP", pc=2, offset=2},
  {op="LOADI", pc=3, a=2, b=22}, {op="RETURN1", pc=4, a=2},
  {op="LOADI", pc=5, a=2, b=11}, {op="RETURN1", pc=6, a=2},
}, { {slot=1,predicate="is_i64"} })
assert(run_kernel(cfg_branch, "test_lua_exec_compile_closed_branch", 0) == 11)
assert(run_kernel(cfg_branch, "test_lua_exec_compile_closed_branch2", 7) == 22)

-- Manual LalinCFG value-substrate fixtures prove every LuaRTValue tag is
-- constructible and mechanically projectable without opaque helpers.
local ValueModel = require("lua_compile.lua_rt_value_model")
local function cfg_name(s) return CFG.Name(s) end
local function cfg_temp(s) return CFG.Temp(cfg_name(s)) end
local function cfg_place(s) return CFG.PlaceValue(cfg_temp(s)) end
local function cfg_ty(s) return CFG.TypeRef(s) end
local function one_block_kernel(expr, projection_expr, ret_ty)
  local ops = {
    CFG.Let(cfg_temp("v"), expr),
    CFG.Let(cfg_temp("out"), projection_expr(cfg_place("v"))),
  }
  local block = CFG.Block(CFG.BlockId(cfg_name("entry")), {}, ops, CFG.Return({ cfg_place("out") }))
  local region = CFG.Region(CFG.RegionId(cfg_name("rt_value_test_body")), {}, {}, CFG.BlockId(cfg_name("entry")), { block })
  return CFG.Kernel(CFG.KernelId(cfg_name("rt_value_test_kernel")), CFG.InlineSpan, {}, { cfg_ty(ret_ty or "i64") }, region, cfg_branch.contract)
end
local function assert_manual_kernel(expr, projection, ret_ty, name, expected)
  local k = one_block_kernel(expr, projection, ret_ty)
  local out, src = run_kernel(k, name)
  assert(not src:match("make_tvalue") and not src:match("truthy_tvalue") and not src:match("tvalue_helper"), "TValue operations must be emitted inline")
  if ret_ty == "f64" then assert(math.abs(out - expected) < 0.00001, tostring(out)) else assert(out == expected, tostring(out) .. " ~= " .. tostring(expected)) end
  return src
end
local function project_tag(v) return CFG.RuntimeTag(v) end
local function project_payload_i64(v) return CFG.RuntimePayloadI64(v) end
local function project_payload_f64(v) return CFG.RuntimePayloadF64(v) end
local function truthy(v) return CFG.RuntimeTruthiness(v) end

local tag_fixtures = {
  { "NilTag", CFG.RuntimeBoxNil(RT.OrdinaryNil) },
  { "EmptySlotTag", CFG.RuntimeBoxNil(RT.EmptySlotSentinel) },
  { "AbsentKeyTag", CFG.RuntimeBoxNil(RT.AbsentKeySentinel) },
  { "NoTableTag", CFG.RuntimeBoxNil(RT.NoTableSentinel) },
  { "FalseTag", CFG.RuntimeBoxBool(CFG.ConstValue(CFG.BoolConst(false))) },
  { "TrueTag", CFG.RuntimeBoxBool(CFG.ConstValue(CFG.BoolConst(true))) },
  { "IntegerTag", CFG.RuntimeBoxI64(CFG.ConstValue(CFG.I64Const(1234))) },
  { "FloatTag", CFG.RuntimeBoxF64(CFG.ConstValue(CFG.F64Const(12.5))) },
  { "ShortStringTag", CFG.RuntimeBoxRef(RT.ShortStringTag, CFG.ConstValue(CFG.I64Const(901))) },
  { "LongStringTag", CFG.RuntimeBoxRef(RT.LongStringTag, CFG.ConstValue(CFG.I64Const(902))) },
  { "TableTag", CFG.RuntimeBoxRef(RT.TableTag, CFG.ConstValue(CFG.I64Const(903))) },
  { "LuaClosureTag", CFG.RuntimeBoxRef(RT.LuaClosureTag, CFG.ConstValue(CFG.I64Const(904))) },
  { "CClosureTag", CFG.RuntimeBoxRef(RT.CClosureTag, CFG.ConstValue(CFG.I64Const(905))) },
  { "LightCFunctionTag", CFG.RuntimeBoxRef(RT.LightCFunctionTag, CFG.ConstValue(CFG.I64Const(906))) },
  { "UserdataTag", CFG.RuntimeBoxRef(RT.UserdataTag, CFG.ConstValue(CFG.I64Const(907))) },
  { "LightUserdataTag", CFG.RuntimeBoxRef(RT.LightUserdataTag, CFG.ConstValue(CFG.I64Const(908))) },
  { "ThreadTag", CFG.RuntimeBoxRef(RT.ThreadTag, CFG.ConstValue(CFG.I64Const(909))) },
  { "CDataTag", CFG.RuntimeBoxRef(RT.CDataTag, CFG.ConstValue(CFG.I64Const(910))) },
}
for _, f in ipairs(tag_fixtures) do
  assert_manual_kernel(f[2], project_tag, "i64", "test_rt_tag_" .. f[1], ValueModel.TAG[f[1]])
end
assert_manual_kernel(CFG.RuntimeBoxI64(CFG.ConstValue(CFG.I64Const(777))), project_payload_i64, "i64", "test_rt_i64_payload", 777)
assert_manual_kernel(CFG.RuntimeBoxRef(RT.TableTag, CFG.ConstValue(CFG.I64Const(0x1234))), project_payload_i64, "i64", "test_rt_ref_payload", 0x1234)
assert_manual_kernel(CFG.RuntimeBoxF64(CFG.ConstValue(CFG.F64Const(99.25))), project_payload_f64, "f64", "test_rt_f64_payload", 99.25)

assert_manual_kernel(CFG.RuntimeBoxNil(RT.OrdinaryNil), truthy, "bool", "test_rt_truth_nil", false)
assert_manual_kernel(CFG.RuntimeBoxBool(CFG.ConstValue(CFG.BoolConst(false))), truthy, "bool", "test_rt_truth_false", false)
assert_manual_kernel(CFG.RuntimeBoxBool(CFG.ConstValue(CFG.BoolConst(true))), truthy, "bool", "test_rt_truth_true", true)
assert_manual_kernel(CFG.RuntimeBoxI64(CFG.ConstValue(CFG.I64Const(0))), truthy, "bool", "test_rt_truth_i64_zero", true)
assert_manual_kernel(CFG.RuntimeBoxF64(CFG.ConstValue(CFG.F64Const(0.0))), truthy, "bool", "test_rt_truth_f64_zero", true)
assert_manual_kernel(CFG.RuntimeBoxRef(RT.TableTag, CFG.ConstValue(CFG.I64Const(1))), truthy, "bool", "test_rt_truth_ref", true)

local _, cfg_move = lower_exec({ {op="LOADI", pc=1, a=1, b=55}, {op="MOVE", pc=2, a=2, b=1}, {op="RETURN1", pc=3, a=2} }, {})
local move_out, move_src = run_kernel(cfg_move, "test_lua_exec_move_runtime_value")
assert(move_out == 55)
assert(move_src:match("LuaRTValue") and move_src:match("payload_i64"), "MOVE path must preserve/project LuaRTValue")

local _, cfg_ret_nil = lower_exec({ {op="LOADNIL", pc=1, a=1, b=1}, {op="RETURN1", pc=2, a=1} }, {})
assert(run_kernel(cfg_ret_nil, "test_lua_exec_return_nil_tag") == ValueModel.TAG.NilTag)
local _, cfg_ret_false = lower_exec({ {op="LOADFALSE", pc=1, a=1}, {op="RETURN1", pc=2, a=1} }, {})
assert(run_kernel(cfg_ret_false, "test_lua_exec_return_false_bool") == false)
local _, cfg_ret_true = lower_exec({ {op="LOADTRUE", pc=1, a=1}, {op="RETURN1", pc=2, a=1} }, {})
assert(run_kernel(cfg_ret_true, "test_lua_exec_return_true_bool") == true)
local _, cfg_ret_i64 = lower_exec({ {op="LOADI", pc=1, a=1, b=88}, {op="RETURN1", pc=2, a=1} }, {})
assert(run_kernel(cfg_ret_i64, "test_lua_exec_return_i64_payload") == 88)
local _, not_src = run_kernel(cfg_nil, "test_lua_exec_not_nil_source_shape")
assert(not_src:match("%.tag") and not_src:match("LuaRTValue"), "NOT must use runtime-value tag truthiness")

print("ok - SpongeJIT LuaExec core-value pipeline")
