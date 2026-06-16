package.path='./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;'..package.path
local pvm=require'moonlift.pvm'; local T=pvm.context(); require('moonlift.schema').Define(T)
local Parse=require('moonlift.parse').Define(T); local OpenFacts=require('moonlift.open_facts').Define(T); local OpenValidate=require('moonlift.open_validate').Define(T); local OpenExpand=require('moonlift.open_expand').Define(T); local ClosureConvert=require('moonlift.closure_convert').Define(T); local Typecheck=require('moonlift.tree_typecheck').Define(T); local Layout=require('moonlift.sem_layout_resolve').Define(T); local TreeToCode=require('moonlift.tree_to_code').Define(T); local CodeValidate=require('moonlift.code_validate').Define(T); local CodeGraph=require('moonlift.code_graph').Define(T); local CodeFlowFacts=require('moonlift.code_flow_facts').Define(T); local CodeValueFacts=require('moonlift.code_value_facts').Define(T); local CodeMemFacts=require('moonlift.code_mem_facts').Define(T); local CodeEffectFacts=require('moonlift.code_effect_facts').Define(T); local CodeKernelPlan=require('moonlift.code_kernel_plan').Define(T); local CodeSchedulePlan=require('moonlift.code_schedule_plan').Define(T)
local Kernel=T.MoonKernel; local Value=T.MoonValue; local Schedule=T.MoonSchedule
local function assert_no(l,i) assert(#i==0,l..' issues '..#i) end
local function lower(src) local parsed=Parse.parse_module(src); assert_no('parse',parsed.issues); local expanded=OpenExpand.module(parsed.module); assert_no('open',OpenValidate.validate(OpenFacts.facts_of_module(expanded)).issues); local closed=ClosureConvert.module(expanded); local checked=Typecheck.check_module(closed); assert_no('typecheck',checked.issues); local resolved=Layout.module(checked.module); local code,contracts=TreeToCode.module_with_contracts(resolved); assert_no('code',CodeValidate.validate(code).issues); local graph=CodeGraph.graph(code); local flow=CodeFlowFacts.facts(code,graph); local value=CodeValueFacts.facts(code,graph,flow); local mem=CodeMemFacts.semantic_facts(code,graph,flow,value,contracts); local effect=CodeEffectFacts.facts(code,graph,mem,contracts); return code,graph,flow,value,mem,effect end
local code,graph,flow,value,mem,effect=lower([[
func sum_loop(n: i32): i32
 return block loop(i: i32 = 0, acc: i32 = 0): i32
  if i >= n then yield acc end
  jump loop(i = i + 1, acc = acc + i)
 end
end
]])
local plan=CodeKernelPlan.plan(code,graph,flow,value,mem,effect)
assert(plan.module==code.id and plan.flow==flow and plan.value==value and plan.mem==mem and plan.effect==effect)
assert(#plan.plans>=1,'expected plans')
local saw_planned,saw_closed=false,false
for _,p in ipairs(plan.plans) do if pvm.classof(p)==Kernel.KernelPlanned then saw_planned=true; assert(p.schedule==nil,'Kernel must not contain schedule'); if pvm.classof(p.body.result)==Kernel.KernelResultClosedForm then saw_closed=true; assert(pvm.classof(p.body.result.closed_form)==Value.ClosedFormFact) end end end
assert(saw_planned,'expected semantic loop plan'); assert(saw_closed,'expected closed-form result citing MoonValue')
local sched=CodeSchedulePlan.plan(code,plan,flow,value,mem,effect)
assert(pvm.classof(sched)==Schedule.ScheduleModulePlan and #sched.schedules>0,'schedule phase owns target choices')
local code2,graph2,flow2,value2,mem2,effect2=lower([[
func plain(n: i32): i32
 return n + 1
end
]])
local plan2=CodeKernelPlan.plan(code2,graph2,flow2,value2,mem2,effect2)
local saw_func_no_plan=false
for _,p in ipairs(plan2.plans) do if pvm.classof(p)==Kernel.KernelNoPlan and pvm.classof(p.subject)==Kernel.KernelSubjectFunction then saw_func_no_plan=true end end
assert(saw_func_no_plan,'function replacement should be explicit no-plan in semantic Kernel v1')

local raw_code,raw_graph,raw_flow,raw_value,raw_mem,raw_effect=lower([[
func raw_sum(p: ptr(i32), n: i32): i32
 return block loop(i: i32 = 0, acc: i32 = 0): i32
  if i >= n then yield acc end
  jump loop(i = i + 1, acc = acc + p[i])
 end
end
]])
local raw_plan=CodeKernelPlan.plan(raw_code,raw_graph,raw_flow,raw_value,raw_mem,raw_effect)
local saw_raw_reject=false
for _,p in ipairs(raw_plan.plans or {}) do if pvm.classof(p)==Kernel.KernelNoPlan and pvm.classof(p.subject)==Kernel.KernelSubjectLoop and #(p.rejects or {})>0 then saw_raw_reject=true end end
assert(saw_raw_reject,'raw pointer loop without bounds must be KernelNoPlan')

local call_code,call_graph,call_flow,call_value,call_mem,call_effect=lower([[
extern touch(x: i32): i32 end
func call_loop(n: i32): i32
 return block loop(i: i32 = 0, acc: i32 = 0): i32
  if i >= n then yield acc end
  let x: i32 = touch(i)
  jump loop(i = i + 1, acc = acc + x)
 end
end
]])
local call_plan=CodeKernelPlan.plan(call_code,call_graph,call_flow,call_value,call_mem,call_effect)
local saw_effect_reject=false
for _,p in ipairs(call_plan.plans or {}) do
 if pvm.classof(p)==Kernel.KernelNoPlan then
  for _,r in ipairs(p.rejects or {}) do if pvm.classof(r)==Kernel.KernelRejectEffect then saw_effect_reject=true end end
 end
end
assert(saw_effect_reject,'unknown extern call effect in loop must reject Kernel planning')
io.write('moonlift code_kernel_plan ok\n')
