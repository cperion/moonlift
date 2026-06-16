package.path='./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;'..package.path

local ffi=require('ffi')
local pvm=require('moonlift.pvm'); local T=pvm.context(); require('moonlift.schema').Define(T)
local Parse=require('moonlift.parse').Define(T); local OpenFacts=require('moonlift.open_facts').Define(T); local OpenValidate=require('moonlift.open_validate').Define(T); local OpenExpand=require('moonlift.open_expand').Define(T); local ClosureConvert=require('moonlift.closure_convert').Define(T); local Typecheck=require('moonlift.tree_typecheck').Define(T); local Layout=require('moonlift.sem_layout_resolve').Define(T); local TreeToCode=require('moonlift.tree_to_code').Define(T); local CodeValidate=require('moonlift.code_validate').Define(T); local CodeGraph=require('moonlift.code_graph').Define(T); local CodeFlowFacts=require('moonlift.code_flow_facts').Define(T); local CodeValueFacts=require('moonlift.code_value_facts').Define(T); local CodeMemFacts=require('moonlift.code_mem_facts').Define(T); local CodeEffectFacts=require('moonlift.code_effect_facts').Define(T); local CodeKernelPlan=require('moonlift.code_kernel_plan').Define(T); local CodeSchedulePlan=require('moonlift.code_schedule_plan').Define(T); local CodeLowerPlan=require('moonlift.code_lower_plan').Define(T); local KernelValidate=require('moonlift.kernel_validate').Define(T); local LowerToBack=require('moonlift.lower_to_back').Define(T); local BackValidate=require('moonlift.back_validate').Define(T); local BackJit=require('moonlift.back_jit').Define(T)
local Value=T.MoonValue; local Kernel=T.MoonKernel; local Schedule=T.MoonSchedule; local Lower=T.MoonLower; local Back=T.MoonBack
local function assert_no(l,issues) assert(#issues==0,l..' issues '..tostring(#issues)) end
local src=[[
func series(n: i32): i32
 return block loop(i: i32 = 0, acc: i32 = 0): i32
  if i >= n then yield acc end
  jump loop(i = i + 1, acc = acc + i)
 end
end
]]
local parsed=Parse.parse_module(src); assert_no('parse',parsed.issues)
local expanded=OpenExpand.module(parsed.module); assert_no('open',OpenValidate.validate(OpenFacts.facts_of_module(expanded)).issues)
local checked=Typecheck.check_module(ClosureConvert.module(expanded)); assert_no('typecheck',checked.issues)
local code,contracts=TreeToCode.module_with_contracts(Layout.module(checked.module)); assert_no('code',CodeValidate.validate(code).issues)
local graph=CodeGraph.graph(code); local flow=CodeFlowFacts.facts(code,graph); local value=CodeValueFacts.facts(code,graph,flow); local mem=CodeMemFacts.semantic_facts(code,graph,flow,value,contracts); local effect=CodeEffectFacts.facts(code,graph,mem,contracts); local kernels=CodeKernelPlan.plan(code,graph,flow,value,mem,effect); local schedules=CodeSchedulePlan.plan(code,kernels,flow,value,mem,effect); local lower=CodeLowerPlan.plan(code,graph,kernels,schedules,Lower.LowerTargetBack)
assert(#value.closed_forms>0 and pvm.classof(value.closed_forms[1])==Value.ClosedFormFact,'Value phase must produce ClosedFormFact')
local saw_sched=false for _,s in ipairs(schedules.schedules or {}) do if pvm.classof(s)==Schedule.SchedulePlanned and s.kind==Schedule.ScheduleClosedForm then saw_sched=true end end; assert(saw_sched,'ScheduleClosedForm must be planned')
local saw_lower=false; for _,fp in ipairs(lower.funcs or {}) do for _,fr in ipairs(fp.fragments or {}) do if pvm.classof(fr.strategy)==Lower.LowerStrategyClosedForm then saw_lower=true; assert(#fr.issues==0,'closed-form fragment must not carry fallback issue') end end end; assert(saw_lower,'LowerStrategyClosedForm must be selected')
assert_no('semantic validate',KernelValidate.validate(code,graph,flow,value,mem,effect,kernels,schedules,lower).issues)
local program=LowerToBack.module(code,graph,flow,value,mem,effect,kernels,schedules,lower); assert_no('back',BackValidate.validate(program).issues)
local loop=graph.funcs[1].loops[1]; local latch_from=loop.latches[1].from.block; local header=loop.header.block
local current=nil; for _,cmd in ipairs(program.cmds or {}) do local cls=pvm.classof(cmd); if cls==Back.CmdSwitchToBlock then current=cmd.block elseif cls==Back.CmdJump and current==Back.BackBlockId(latch_from.text) and cmd.dest==Back.BackBlockId(header.text) then error('closed-form lowering emitted original loop backedge') end end
local jit=BackJit.jit(); local artifact=jit:compile(program); local fn=ffi.cast('int32_t (*)(int32_t)', artifact:getpointer(Back.BackFuncId('series')))
assert(fn(-3)==0); assert(fn(0)==0); assert(fn(1)==0); assert(fn(5)==10); assert(fn(10)==45)
artifact:free()
io.write('moonlift lower_to_back_closed_form ok\n')
