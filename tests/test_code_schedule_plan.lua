package.path = './?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;' .. package.path

local pvm=require('moonlift.pvm'); local T=pvm.context(); require('moonlift.schema').Define(T)
local Parse=require('moonlift.parse').Define(T); local OpenFacts=require('moonlift.open_facts').Define(T); local OpenValidate=require('moonlift.open_validate').Define(T); local OpenExpand=require('moonlift.open_expand').Define(T); local ClosureConvert=require('moonlift.closure_convert').Define(T); local Typecheck=require('moonlift.tree_typecheck').Define(T); local Layout=require('moonlift.sem_layout_resolve').Define(T); local TreeToCode=require('moonlift.tree_to_code').Define(T); local CodeValidate=require('moonlift.code_validate').Define(T); local CodeGraph=require('moonlift.code_graph').Define(T); local CodeFlowFacts=require('moonlift.code_flow_facts').Define(T); local CodeValueFacts=require('moonlift.code_value_facts').Define(T); local CodeMemFacts=require('moonlift.code_mem_facts').Define(T); local CodeEffectFacts=require('moonlift.code_effect_facts').Define(T); local CodeKernelPlan=require('moonlift.code_kernel_plan').Define(T); local CodeSchedulePlan=require('moonlift.code_schedule_plan').Define(T)
local Kernel=T.MoonKernel; local Schedule=T.MoonSchedule; local Back=T.MoonBack
local function assert_no(l,issues) assert(#issues==0,l..' issues '..tostring(#issues)) end
local function lower(src)
 local parsed=Parse.parse_module(src); assert_no('parse',parsed.issues)
 local expanded=OpenExpand.module(parsed.module); assert_no('open',OpenValidate.validate(OpenFacts.facts_of_module(expanded)).issues)
 local checked=Typecheck.check_module(ClosureConvert.module(expanded)); assert_no('typecheck',checked.issues)
 local resolved=Layout.module(checked.module); local code,contracts=TreeToCode.module_with_contracts(resolved); assert_no('code',CodeValidate.validate(code).issues)
 local graph=CodeGraph.graph(code); local flow=CodeFlowFacts.facts(code,graph); local value=CodeValueFacts.facts(code,graph,flow); local mem=CodeMemFacts.semantic_facts(code,graph,flow,value,contracts); local effect=CodeEffectFacts.facts(code,graph,mem,contracts); local kernels=CodeKernelPlan.plan(code,graph,flow,value,mem,effect); return code,flow,value,mem,effect,kernels
end
local function planned_for(kernels,schedules)
 local out={}
 for _,s in ipairs(schedules.schedules or {}) do if pvm.classof(s)==Schedule.SchedulePlanned then out[#out+1]=s end end
 return out
end

local code,flow,value,mem,effect,kernels=lower([[
func series(n: i32): i32
 return block loop(i: i32 = 0, acc: i32 = 0): i32
  if i >= n then yield acc end
  jump loop(i = i + 1, acc = acc + i)
 end
end
]])
local schedules=CodeSchedulePlan.plan(code,kernels,flow,value,mem,effect)
local saw_closed=false
for _,s in ipairs(planned_for(kernels,schedules)) do if s.kind==Schedule.ScheduleClosedForm then saw_closed=true; assert(#s.proofs>0,'closed-form schedule carries proofs') end end
assert(saw_closed,'proven arithmetic series should schedule as executable ScheduleClosedForm')

local copy_code,copy_flow,copy_value,copy_mem,copy_effect,copy_kernels=lower([[
func copy(noalias dst: ptr(i32), readonly src: ptr(i32), n: i32): i32
 requires bounds(dst,n)
 requires bounds(src,n)
 requires disjoint(dst,src)
 block loop(i: i32 = 0)
  if i >= n then return 0 end
  dst[i] = src[i]
  jump loop(i = i + 1)
 end
end
]])
local scalar_schedules=CodeSchedulePlan.plan(copy_code,copy_kernels,copy_flow,copy_value,copy_mem,copy_effect)
local saw_scalar=false
for _,s in ipairs(planned_for(copy_kernels,scalar_schedules)) do if s.kind==Schedule.ScheduleScalarIndex or s.kind==Schedule.ScheduleScalarPointer then saw_scalar=true end end
assert(saw_scalar,'bounded disjoint copy should have executable scalar schedule by default')
local vector_target=Back.BackTargetModel(Back.BackTargetNative,{Back.BackTargetSupportsShape(Back.BackShapeVec(Back.BackVec(Back.BackI32,4)))})
local vector_schedules=CodeSchedulePlan.plan(copy_code,copy_kernels,copy_flow,copy_value,copy_mem,copy_effect,vector_target)
local saw_vector=false
for _,s in ipairs(planned_for(copy_kernels,vector_schedules)) do if pvm.classof(s.kind)==Schedule.ScheduleVector then saw_vector=true; assert(pvm.classof(s.kind.lanes)==Schedule.LaneVector) end end
assert(saw_vector,'vector target facts should select ScheduleVector for contiguous copy')

local unsafe_code,unsafe_flow,unsafe_value,unsafe_mem,unsafe_effect,unsafe_kernels=lower([[
func raw_sum(p: ptr(i32), n: i32): i32
 return block loop(i: i32 = 0, acc: i32 = 0): i32
  if i >= n then yield acc end
  jump loop(i = i + 1, acc = acc + p[i])
 end
end
]])
local saw_kernel_reject=false
for _,p in ipairs(unsafe_kernels.plans or {}) do if pvm.classof(p)==Kernel.KernelNoPlan and #(p.rejects or {})>0 then saw_kernel_reject=true end end
assert(saw_kernel_reject,'unsafe raw-pointer loop should be rejected before scheduling')
local unsafe_schedules=CodeSchedulePlan.plan(unsafe_code,unsafe_kernels,unsafe_flow,unsafe_value,unsafe_mem,unsafe_effect)
assert(#unsafe_schedules.schedules==0,'KernelNoPlan loops should not get decorative schedules')

local call_code,call_flow,call_value,call_mem,call_effect,call_kernels=lower([[
extern touch(x: i32): i32 end
func call_loop(n: i32): i32
 return block loop(i: i32 = 0, acc: i32 = 0): i32
  if i >= n then yield acc end
  let x: i32 = touch(i)
  jump loop(i = i + 1, acc = acc + x)
 end
end
]])
local saw_effect_reject=false
for _,p in ipairs(call_kernels.plans or {}) do for _,r in ipairs(p.rejects or {}) do if pvm.classof(r)==Kernel.KernelRejectEffect then saw_effect_reject=true end end end
assert(saw_effect_reject,'unknown extern effect should reject Kernel before scheduling')

io.write('moonlift code_schedule_plan ok\n')
