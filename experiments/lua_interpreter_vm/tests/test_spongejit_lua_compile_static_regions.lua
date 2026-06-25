#!/usr/bin/env luajit
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;./experiments/lua_interpreter_vm/spongejit/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local C = require("lua_compile")
local Schema = require("lua_compile.schema")
local pvm = require("lalin.pvm")
local T = Schema.get()
local ExecLower = require("lua_compile.lua_src_to_lua_exec_lower")
local ExecToLalin = require("lua_compile.lua_exec_to_lalin_cfg_lower")
local ExecValidate = require("lua_compile.lua_exec_validate")
local CFGValidate = require("lua_compile.lalin_cfg_validate")
local RegionModel = require("lua_compile.lua_exec_region_model")
local ArityModel = require("lua_compile.lua_rt_arity_model")
local RT, Exec = T.LuaRT, T.LuaExec

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

local function lower_exec(events)
  local unit = C.unit_from_events(events, {})
  local exec_kernel, exec_errors = ExecLower.lower(unit.source, unit.evidence)
  assert(exec_kernel, table.concat(exec_errors or {}, "; "))
  local ok, errors = ExecValidate.kernel(exec_kernel)
  assert(ok, table.concat(errors or {}, "\n"))
  assert(RegionModel.is_executable_region_kind(exec_kernel.body.kind), "current slice region must be executable")
  assert(contains_class(exec_kernel.contract, function(cls) return cls == Exec.RequiresRegionDescriptor end), "Exec contract must carry RegionDescriptor obligation")
  assert(contains_class(exec_kernel.contract, function(cls) return cls == Exec.DescribesRegion end), "Exec contract must carry RegionDescriptor guarantee")
  return exec_kernel
end

local function lower_lalin(events)
  local exec_kernel = lower_exec(events)
  local cfg, cfg_errors = ExecToLalin.lower_outcome(exec_kernel, "kind")
  if not cfg then cfg, cfg_errors = ExecToLalin.lower(exec_kernel) end
  assert(cfg, table.concat(cfg_errors or {}, "; "))
  local ok, errors = CFGValidate.validate(cfg)
  assert(ok, table.concat(errors or {}, "\n"))
  return exec_kernel, cfg
end

local exec_load_return = select(1, lower_lalin({ {op="LOADI", pc=1, a=1, sbx=7}, {op="RETURN1", pc=2, a=1} }))
assert(contains_class(exec_load_return.contract, function(cls) return cls == Exec.RequiresArityShape end), "Exec contract must carry arity-shape obligation")
assert(contains_class(exec_load_return.contract, function(cls) return cls == Exec.RequiresResultChannel end), "Exec contract must carry result-channel obligation")
assert(contains_class(exec_load_return.contract, function(cls) return cls == Exec.NormalizesArity end), "Exec contract must carry arity-normalization guarantee")
assert(contains_class(exec_load_return.contract, function(cls) return cls == Exec.ProducesResultChannel end), "Exec contract must carry result-channel guarantee")
lower_lalin({ {op="VARARG", pc=1, a=1, b=0, c=3, k=false}, {op="RETURN", pc=2, a=1, b=3, c=0, k=false} })
lower_lalin({ {op="ADDI", pc=1, a=1, b=1, c=128, sc=1}, {op="MMBINI", pc=2, a=1, b=128, sb=1, c="ADD"}, {op="RETURN1", pc=3, a=1} })
lower_lalin({ {op="GETTABLE", pc=1, a=1, b=2, c=3}, {op="RETURN1", pc=2, a=1} })
lower_lalin({ {op="SETTABLE", pc=1, a=2, b=3, c=1, k=false} })

local function frame0()
  local fr = RT.FrameRef(RT.Name("frame0"))
  return RT.Frame(fr, RT.StackRef(fr), RT.TopRef(fr), RT.NoVarargs, RT.CloseChain(fr, {}), RT.Pc(1))
end

local function empty_return_block()
  local bid = Exec.BlockId(Exec.Name("entry"))
  local seq = RT.ValueSeq(RT.FixedSeq, {}, RT.FixedCount(0), RT.FromLiteralValues)
  return bid, Exec.Block(bid, {}, {}, Exec.Return(seq))
end

local function manual_unsupported_region(kind)
  local bid, block = empty_return_block()
  local region = Exec.Region(Exec.Name("manual_unsupported"), kind, {}, {}, bid, { block })
  local kernel = Exec.Kernel(Exec.Name("manual_unsupported_kernel"), frame0(), region, Exec.Contract({}, {}))
  local ok, errors = ExecValidate.kernel(kernel)
  assert(ok, table.concat(errors or {}, "\n"))
  local cfg, cfg_errors = ExecToLalin.lower(kernel)
  assert(not cfg, "unsupported semantic region must not lower to LalinCFG")
  assert(table.concat(cfg_errors or {}, "; "):match("unsupported_semantic_region"), "expected unsupported semantic region diagnostic")
end

manual_unsupported_region(Exec.CallRegion)
manual_unsupported_region(Exec.TailCallRegion)

local function contracted_call_region()
  local caller = RT.FrameRef(RT.Name("caller"))
  local callee = RT.FrameRef(RT.Name("callee"))
  local call_ref = RT.CallRef(RT.Name("call0"))
  local arg_seq = RT.ValueSeq(RT.FixedSeq, {}, RT.FixedCount(1), RT.FromStackWindow(RT.StackWindow(RT.CallWindow, caller, RT.Slot(1), RT.FixedCount(1))))
  local arg_shape = RT.ArityShape(RT.FixedCount(1), RT.FixedCount(1), RT.ExactCount(RT.Count(1)), RT.FixedArity)
  local arg_channel = RT.CallArgChannel(call_ref, arg_seq, arg_shape)
  local result_seq = RT.ValueSeq(RT.CallResultSeq, {}, RT.FixedCount(1), RT.FromCallResult(call_ref))
  local result_shape = RT.ArityShape(RT.FixedCount(1), RT.FixedCount(1), RT.ExactCount(RT.Count(1)), RT.FixedArity)
  local result_channel = ArityModel.result_channel("CallFrameResultChannel", result_seq, RT.FixedCount(1))
  local results = RT.CallResultChannel(call_ref, result_channel, ArityModel.normalization(result_seq, result_shape, result_channel))
  local layout = RT.CallFrameLayout(RT.CallFrameRef(RT.Name("layout0")), caller, callee, RT.Slot(0), RT.Slot(0), RT.FixedCount(1), RT.Slot(2), RT.FixedCount(1), RT.Count(4))
  local closure = RT.ClosureRef(RT.Name("closure0"))
  local target = RT.DirectLuaClosureTarget(RT.StackValue(caller, RT.Slot(0)), closure)
  local resolved = RT.ResolvedCallTarget(call_ref, target, RT.LuaClosureTargetIdentity(closure, T.LuaSrc.KRef(0), 1, {}), RT.CallableLuaClosure)
  local frame_state = RT.CallFrameState(call_ref, layout, arg_channel, results, resolved, RT.CallFrameUnprepared)
  local ret_seq = RT.ValueSeq(RT.FixedSeq, {}, RT.FixedCount(1), RT.FromStackWindow(RT.StackWindow(RT.ReturnWindow, caller, RT.Slot(2), RT.FixedCount(1))))
  local bid = Exec.BlockId(Exec.Name("entry"))
  local params = {
    Exec.Param(Exec.Name("caller_stack"), Exec.LalinType("ptr(LuaRTValue)")),
    Exec.Param(Exec.Name("callee_stack"), Exec.LalinType("ptr(LuaRTValue)")),
  }
  local block = Exec.Block(bid, {}, { Exec.PrepareCallFrame(frame_state), Exec.ReceiveCallResults(frame_state) }, Exec.Return(ret_seq))
  local region = Exec.Region(Exec.Name("manual_call"), Exec.CallRegion, params, {}, bid, { block })
  local contract = Exec.Contract({ Exec.RequiresResolvedCallTarget(resolved), Exec.RequiresCallFrameLayout(layout), Exec.RequiresCallArgChannel(arg_channel), Exec.RequiresCallResultChannel(results) }, { Exec.ResolvesCallTarget(resolved), Exec.PreparesCallFrame(frame_state), Exec.ProducesCallResults(results) })
  return Exec.Kernel(Exec.Name("manual_call_kernel"), RT.Frame(caller, RT.StackRef(caller), RT.TopRef(caller), RT.NoVarargs, RT.CloseChain(caller, {}), RT.Pc(1)), region, contract)
end

local call_kernel = contracted_call_region()
local call_ok, call_errors = ExecValidate.kernel(call_kernel)
assert(call_ok, table.concat(call_errors or {}, "\n"))
local call_cfg, call_cfg_errors = ExecToLalin.lower_outcome(call_kernel, "value0_tag")
assert(call_cfg, "properly contracted manual CallRegion must lower: " .. table.concat(call_cfg_errors or {}, ";"))
local call_cfg_ok, call_cfg_validate_errors = CFGValidate.validate(call_cfg)
assert(call_cfg_ok, table.concat(call_cfg_validate_errors or {}, "\n"))

local function assert_source_reject(events, needle)
  local result = C.compile_to_lalin_kernel(C.unit_from_events(events, {}))
  assert(result.kind == "Reject", "unsupported source must reject, not compile")
  local msg = result.diagnostic and result.diagnostic.message or ""
  assert(msg:match(needle), "expected reject diagnostic containing " .. needle .. ", got: " .. msg)
end

assert_source_reject({ {op="CALL", pc=1, a=1, b=1, c=1}, {op="RETURN0", pc=2} }, "source_call_missing_static_evidence")
assert_source_reject({ {op="TAILCALL", pc=1, a=1, b=1, c=0, k=false}, {op="RETURN0", pc=2} }, "unsupported_source_semantics:TailCallRegion")
assert_source_reject({ {op="SETLIST", pc=1, a=1, b=2, c=3, k=false}, {op="RETURN0", pc=2} }, "setlist_table_write_semantics_future")
assert_source_reject({ {op="TFORPREP", pc=1, a=1, b=1, c=1}, {op="RETURN0", pc=2} }, "unsupported_instruction:TFORPREP")
assert_source_reject({ {op="TFORCALL", pc=1, a=1, b=1, c=1}, {op="RETURN0", pc=2} }, "unsupported_instruction:TFORCALL")
assert_source_reject({ {op="TFORLOOP", pc=1, a=1, b=1, c=1}, {op="RETURN0", pc=2} }, "unsupported_instruction:TFORLOOP")
assert_source_reject({ {op="MMBIN", pc=1, a=1, b=2, c="ADD"}, {op="RETURN0", pc=2} }, "unsupported_instruction:MMBIN")

print("ok - SpongeJIT LuaCompile static semantic regions")
