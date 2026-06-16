package.path = './?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;' .. package.path
local pvm=require('moonlift.pvm'); local T=pvm.context(); require('moonlift.schema').Define(T)
local Parse=require('moonlift.parse').Define(T); local OpenFacts=require('moonlift.open_facts').Define(T); local OpenValidate=require('moonlift.open_validate').Define(T); local OpenExpand=require('moonlift.open_expand').Define(T); local ClosureConvert=require('moonlift.closure_convert').Define(T); local Typecheck=require('moonlift.tree_typecheck').Define(T); local Layout=require('moonlift.sem_layout_resolve').Define(T); local TreeToCode=require('moonlift.tree_to_code').Define(T); local CodeValidate=require('moonlift.code_validate').Define(T); local CodeGraph=require('moonlift.code_graph').Define(T); local CodeFlowFacts=require('moonlift.code_flow_facts').Define(T); local CodeValueFacts=require('moonlift.code_value_facts').Define(T); local CodeMemFacts=require('moonlift.code_mem_facts').Define(T); local CodeEffectFacts=require('moonlift.code_effect_facts').Define(T)
local Effect=T.MoonEffect
local function assert_no(l,issues) assert(#issues==0,l..' issues '..tostring(#issues)) end
local parsed=Parse.parse_module([[
extern touch(x: i32): i32 end
func effect_contracts(noalias readonly p: ptr(i32), writeonly invalidate q: ptr(i32), preserve r: ptr(i32), n: i32): i32
 let x: i32 = touch(n)
 return x
end
]])
assert_no('parse',parsed.issues)
local expanded=OpenExpand.module(parsed.module); assert_no('open',OpenValidate.validate(OpenFacts.facts_of_module(expanded)).issues)
local checked=Typecheck.check_module(ClosureConvert.module(expanded)); assert_no('typecheck',checked.issues)
local resolved=Layout.module(checked.module); local code,contracts=TreeToCode.module_with_contracts(resolved); assert_no('code',CodeValidate.validate(code).issues)
local graph=CodeGraph.graph(code); local flow=CodeFlowFacts.facts(code,graph); local value=CodeValueFacts.facts(code,graph,flow); local mem=CodeMemFacts.semantic_facts(code,graph,flow,value,contracts); local effect=CodeEffectFacts.facts(code,graph,mem,contracts)
local saw_read,saw_write,saw_noescape,saw_invalidate,saw_retain=false,false,false,false,false
for _,term in ipairs(effect.terms or {}) do
 for _,e in ipairs(term.effects or {}) do
  local cls=pvm.classof(e)
  if cls==Effect.EffectRead then saw_read=true end
  if cls==Effect.EffectWrite then saw_write=true end
  if cls==Effect.EffectNoEscape then saw_noescape=true end
  if cls==Effect.EffectInvalidate then saw_invalidate=true end
  if cls==Effect.EffectRetain then saw_retain=true end
 end
end
assert(saw_read and saw_write and saw_noescape and saw_invalidate and saw_retain,'contracts should normalize to explicit entry effects')
assert(#effect.calls==1 and pvm.classof(effect.calls[1])==Effect.CallSummary,'extern call should have CallSummary')
local saw_unknown_call=false
for _,inst in ipairs(effect.insts or {}) do for _,e in ipairs(inst.effects or {}) do if pvm.classof(e)==Effect.EffectUnknown then saw_unknown_call=true end end end
assert(saw_unknown_call,'extern call InstEffect should carry conservative EffectUnknown')
io.write('moonlift code_effect_facts ok\n')
