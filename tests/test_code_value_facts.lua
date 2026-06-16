package.path = './?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;' .. package.path
local pvm=require('moonlift.pvm'); local T=pvm.context(); require('moonlift.schema').Define(T)
local Parse=require('moonlift.parse').Define(T); local OpenFacts=require('moonlift.open_facts').Define(T); local OpenValidate=require('moonlift.open_validate').Define(T); local OpenExpand=require('moonlift.open_expand').Define(T); local ClosureConvert=require('moonlift.closure_convert').Define(T); local Typecheck=require('moonlift.tree_typecheck').Define(T); local Layout=require('moonlift.sem_layout_resolve').Define(T); local TreeToCode=require('moonlift.tree_to_code').Define(T); local CodeValidate=require('moonlift.code_validate').Define(T); local CodeGraph=require('moonlift.code_graph').Define(T); local CodeFlowFacts=require('moonlift.code_flow_facts').Define(T); local CodeValueFacts=require('moonlift.code_value_facts').Define(T)
local Value=T.MoonValue
local function assert_no(l,issues) assert(#issues==0,l..' issues '..tostring(#issues)) end
local function facts(src)
 local parsed=Parse.parse_module(src); assert_no('parse',parsed.issues)
 local expanded=OpenExpand.module(parsed.module); assert_no('open',OpenValidate.validate(OpenFacts.facts_of_module(expanded)).issues)
 local checked=Typecheck.check_module(ClosureConvert.module(expanded)); assert_no('typecheck',checked.issues)
 local resolved=Layout.module(checked.module); local code=TreeToCode.module(resolved); assert_no('code',CodeValidate.validate(code).issues)
 local graph=CodeGraph.graph(code); local flow=CodeFlowFacts.facts(code,graph); return CodeValueFacts.facts(code,graph,flow)
end
local value=facts([[
func series(n: i32): i32
 return block loop(i: i32 = 0, acc: i32 = 0): i32
  if i >= n then yield acc end
  jump loop(i = i + 1, acc = acc + i)
 end
end
]])
assert(#value.reductions>0,'additive recurrence should emit ReductionFact')
assert(#value.closed_forms>0,'arithmetic series should emit ClosedFormFact before Kernel')
assert(pvm.classof(value.closed_forms[1].expr)~=Value.ValueExprValue,'ClosedFormFact expr must be a computed expression tree, not the accumulator placeholder')
local no_cf=facts([[
func plus_one(n: i32): i32
 return block loop(i: i32 = 0, acc: i32 = 0): i32
  if i >= n then yield acc end
  jump loop(i = i + 1, acc = acc + 1)
 end
end
]])
assert(#no_cf.reductions>0,'non-series add recurrence still emits ReductionFact')
assert(#no_cf.closed_forms==0,'insufficient facts for exact series must not emit fake ClosedFormFact')
io.write('moonlift code_value_facts ok\n')
