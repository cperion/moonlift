#!/usr/bin/env luajit
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;./experiments/lua_interpreter_vm/spongejit/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Schema = require("lua_compile.schema")
local pvm = require("moonlift.pvm")
local T = Schema.get()
local Validate = require("lua_compile.validate")
local LuaRTValidate = require("lua_compile.lua_rt_validate")
local LuaExecValidate = require("lua_compile.lua_exec_validate")
local RT, Exec = T.LuaRT, T.LuaExec

local function assert_ok(ok, errs)
  assert(ok, table.concat(errs or {}, "\n"))
end
local function name(s) return RT.Name(s) end
local function ename(s) return Exec.Name(s) end

-- Ordinary nil is distinct from table/lookup sentinels.
local ordinary_nil = RT.NilValue(RT.OrdinaryNil)
local empty_slot_nil = RT.NilValue(RT.EmptySlotSentinel)
local absent_key_nil = RT.NilValue(RT.AbsentKeySentinel)
local no_table_nil = RT.NilValue(RT.NoTableSentinel)
assert_ok(LuaRTValidate.tvalue(ordinary_nil))
assert_ok(Validate.lua_rt_tvalue(absent_key_nil))
assert(ordinary_nil.kind.kind == "OrdinaryNil")
assert(empty_slot_nil.kind.kind == "EmptySlotSentinel")
assert(absent_key_nil.kind.kind == "AbsentKeySentinel")
assert(no_table_nil.kind.kind == "NoTableSentinel")
assert(ordinary_nil ~= absent_key_nil, "ordinary nil must not collapse with absent-key sentinel")

local false_value = RT.BoolValue(RT.LuaFalse)
local true_value = RT.BoolValue(RT.LuaTrue)
assert_ok(LuaRTValidate.tvalue(false_value))
assert_ok(LuaRTValidate.tvalue(true_value))
assert(RT.IsFalsey.kind == "IsFalsey")
assert(RT.IsTruthy.kind == "IsTruthy")
assert(RT.FalseyNil.kind == "FalseyNil")
assert(RT.FalseyFalse.kind == "FalseyFalse")
assert(RT.TruthyValue.kind == "TruthyValue")

-- Stack/top/window/multivalue semantics are first-class ASDL values.
local frame_ref = RT.FrameRef(name("frame0"))
local stack_ref = RT.StackRef(frame_ref)
local top_ref = RT.TopRef(frame_ref)
local slot1 = RT.Slot(1)
local slot2 = RT.Slot(2)
local value1 = RT.StackValue(frame_ref, slot1)
local value2 = RT.StackValue(frame_ref, slot2)
local open_count = RT.OpenFromTop(top_ref)
local return_window = RT.StackWindow(RT.ReturnWindow, frame_ref, slot1, open_count)
local seq = RT.ValueSeq(RT.OpenSeq, { value1, value2 }, open_count, RT.FromStackWindow(return_window))
local fill_adjust = RT.FillNilTo(RT.Count(3))
assert(pvm.classof(return_window) == RT.StackWindow)
assert(pvm.classof(seq) == RT.ValueSeq)
assert(fill_adjust.kind == "FillNilTo")
assert_ok(LuaRTValidate.value_seq(seq))

-- Varargs preserve hidden-frame vs access behavior.
local hidden_varargs = RT.HiddenFrameVarargs(frame_ref, RT.Count(2))
local key_value = RT.TempValue(name("vararg_key"))
local vararg_index = RT.VarargIndex(hidden_varargs, key_value)
local vararg_copy = RT.VarargOpenCopy(hidden_varargs)
local vararg_n = RT.VarargNField(hidden_varargs)
assert(hidden_varargs.kind == "HiddenFrameVarargs")
assert(vararg_index.kind == "VarargIndex")
assert(vararg_copy.kind == "VarargOpenCopy")
assert(vararg_n.kind == "VarargNField")

-- Raw table lookup distinguishes hit vs miss/sentinel.
local table_ref = RT.TableRef(name("table0"))
local table_value = RT.TableValue(table_ref)
local raw_hit = RT.RawHit(value1)
local raw_miss = RT.RawMiss(RT.AbsentKeySentinel)
local table_state = RT.TableRefState(table_ref, RT.MixedArrayHash, RT.TableMetatable(table_ref))
assert(raw_hit.kind == "RawHit")
assert(raw_miss.kind == "RawMiss")
assert(raw_miss.absent_sentinel.kind == "AbsentKeySentinel")
assert(table_state.shape.kind == "MixedArrayHash")
assert(table_state.metatable.kind == "TableMetatable")

-- Metamethod enum constructors are present in PUC ltm.h order and lookups are explicit.
local metamethod_order = {
  "TM_INDEX", "TM_NEWINDEX", "TM_GC", "TM_MODE", "TM_LEN", "TM_EQ",
  "TM_ADD", "TM_SUB", "TM_MUL", "TM_MOD", "TM_POW", "TM_DIV", "TM_IDIV",
  "TM_BAND", "TM_BOR", "TM_BXOR", "TM_SHL", "TM_SHR", "TM_UNM", "TM_BNOT",
  "TM_LT", "TM_LE", "TM_CONCAT", "TM_CALL", "TM_CLOSE",
}
for _, k in ipairs(metamethod_order) do assert(RT[k] and RT[k].kind == k, "missing metamethod " .. k) end
local mt_epoch = RT.MetatableEpoch(RT.TableMetatable(table_ref), 1)
local mm_slot = RT.MetamethodSlot(RT.TableMetatable(table_ref), RT.TM_INDEX, RT.TempValue(name("index_mm")), 2)
local mm_lookup = RT.MetamethodLookupPath(table_value, RT.TM_INDEX, { RT.CheckReceiverMetatable(table_value, mt_epoch), RT.CheckMetamethodSlot(mm_slot) }, RT.MetamethodFoundResult(RT.TempValue(name("index_mm"))), { T.LuaFact.MetatableEpoch })
assert(pvm.classof(mm_lookup) == RT.MetamethodLookupPath)
assert(mm_lookup.result.kind == "MetamethodFoundResult")

-- Calls have explicit CallRef-spined shape and result-continuation categories.
local call_args = RT.StackWindow(RT.CallWindow, frame_ref, slot1, RT.FixedCount(2))
local call_ref = RT.CallRef(name("call0"))
local call_shape = RT.CallShape(call_ref, RT.ClosureValue(RT.ClosureRef(name("callee"))), call_args, RT.FixedCount(1), RT.NotTailCall, RT.YieldingCall)
local call_result = RT.CallResult(call_ref, seq, RT.CallYield)
assert(call_shape.yield_policy.kind == "YieldingCall")
assert(call_result.continuation.kind == "CallYield")

-- Error/yield and close-chain states are ASDL-visible, not protocol tags.
local error_state = RT.ErrorState(RT.TypeError, RT.TempValue(name("error_object")), RT.Pc(12), top_ref)
local yield_state = RT.YieldState(RT.Pc(13), top_ref, seq, RT.ResumeMetamethod)
local close_pending = RT.CloseItem(slot1, value1, RT.ClosePending)
local close_found = RT.CloseItem(slot2, value2, RT.CloseMethodFound(RT.TempValue(name("close_mm"))))
local close_error = RT.CloseItem(RT.Slot(3), value1, RT.CloseErrorState(error_state))
local close_yield = RT.CloseItem(RT.Slot(4), value2, RT.CloseYieldState(yield_state))
local close_chain = RT.CloseChain(frame_ref, { close_pending, close_found, close_error, close_yield })
assert(close_chain.items[1].state.kind == "ClosePending")
assert(close_chain.items[2].state.kind == "CloseMethodFound")
assert(close_chain.items[3].state.kind == "CloseErrorState")
assert(close_chain.items[4].state.kind == "CloseYieldState")

local frame = RT.Frame(frame_ref, stack_ref, top_ref, hidden_varargs, close_chain, RT.Pc(1))
assert_ok(LuaRTValidate.frame(frame))
assert_ok(Validate.lua_rt_frame(frame))

-- Numeric and generic for state variants preserve PUC-distinct layouts.
local int_for = RT.IntegerForState(RT.Slot(5), RT.TempValue(name("count")), RT.TempValue(name("step")), RT.TempValue(name("control")))
local float_for = RT.FloatForState(RT.Slot(5), RT.TempValue(name("limit")), RT.TempValue(name("fstep")), RT.TempValue(name("fcontrol")))
local generic_for = RT.GenericForState(RT.Slot(8), RT.TempValue(name("iter")), RT.TempValue(name("state")), RT.TempValue(name("control")), RT.TempValue(name("closing")), RT.Count(2))
assert(int_for.kind == "IntegerForState")
assert(float_for.kind == "FloatForState")
assert(pvm.classof(generic_for) == RT.GenericForState)

-- SETLIST state preserves open count and EXTRAARG extension facts.
local setlist_state = RT.SetListState(table_ref, RT.StackWindow(RT.ConstructorWindow, frame_ref, RT.Slot(10), open_count), open_count, RT.Count(50), true, RT.Ax(7))
assert(setlist_state.uses_extraarg == true)
assert(setlist_state.extraarg.value == 7)

-- LuaExec semantic CFG region with typed continuations and explicit terminator.
local ok_cont = Exec.Continuation(ename("ok"), Exec.OkCont, { Exec.Param(ename("result"), Exec.LuaValueSeqType) })
local err_cont = Exec.Continuation(ename("err"), Exec.ErrorCont, { Exec.Param(ename("error"), Exec.LuaErrorType) })
local yield_cont = Exec.Continuation(ename("yield"), Exec.YieldCont, { Exec.Param(ename("yield_state"), Exec.LuaYieldType) })
local entry_id = Exec.BlockId(ename("entry"))
local done_id = Exec.BlockId(ename("done"))
local entry_ref = Exec.BlockRef(entry_id)
local done_ref = Exec.BlockRef(done_id)
local truthy_choice = Exec.TruthinessChoice(value1)
local let_truthy = Exec.Let(ename("truthy"), Exec.TruthinessExpr(value1))
local entry_block = Exec.Block(entry_id, {}, { let_truthy }, Exec.Branch(truthy_choice, done_ref, done_ref))
local done_block = Exec.Block(done_id, { Exec.Param(ename("ignored"), Exec.LuaValueType) }, {}, Exec.Return(seq))
-- Branch targets with params would need edge args in a future richer terminator; keep structural region valid.
done_block = Exec.Block(done_id, {}, {}, Exec.Return(seq))
local region = Exec.Region(ename("truthiness_region"), Exec.GuardRegion, { Exec.Param(ename("frame"), Exec.LuaFrameType) }, { ok_cont, err_cont, yield_cont }, entry_id, { entry_block, done_block })
assert_ok(LuaExecValidate.region(region))
assert_ok(Validate.lua_exec_region(region))

local contract = Exec.Contract({ Exec.RequiresGuard(RT.TypeGuard(value1, RT.IsTruthy)) }, { Exec.PreservesFrame(frame_ref), Exec.UpdatesTop(top_ref), Exec.ProducesValue(value1), Exec.ClosesChain(close_chain) })
local kernel = Exec.Kernel(ename("kernel0"), frame, region, contract)
local module = Exec.Module({ region }, { kernel })
assert_ok(LuaExecValidate.kernel(kernel))
assert_ok(Validate.lua_exec_kernel(kernel))
assert_ok(LuaExecValidate.module(module))
assert_ok(Validate.lua_exec_module(module))

print("ok - SpongeJIT LuaRT/LuaExec structural ASDL")
