package.path='./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;'..package.path

local ffi=require('ffi')
local pvm=require('moonlift.pvm'); local T=pvm.context(); require('moonlift.schema').Define(T)
local Parse=require('moonlift.parse').Define(T); local OpenFacts=require('moonlift.open_facts').Define(T); local OpenValidate=require('moonlift.open_validate').Define(T); local OpenExpand=require('moonlift.open_expand').Define(T); local ClosureConvert=require('moonlift.closure_convert').Define(T); local Typecheck=require('moonlift.tree_typecheck').Define(T); local Layout=require('moonlift.sem_layout_resolve').Define(T); local TreeToCode=require('moonlift.tree_to_code').Define(T); local CodeValidate=require('moonlift.code_validate').Define(T); local CodeGraph=require('moonlift.code_graph').Define(T); local CodeFlowFacts=require('moonlift.code_flow_facts').Define(T); local CodeValueFacts=require('moonlift.code_value_facts').Define(T); local CodeMemFacts=require('moonlift.code_mem_facts').Define(T); local CodeEffectFacts=require('moonlift.code_effect_facts').Define(T); local CodeKernelPlan=require('moonlift.code_kernel_plan').Define(T); local CodeSchedulePlan=require('moonlift.code_schedule_plan').Define(T); local CodeLowerPlan=require('moonlift.code_lower_plan').Define(T); local KernelValidate=require('moonlift.kernel_validate').Define(T); local LowerToBack=require('moonlift.lower_to_back').Define(T); local BackValidate=require('moonlift.back_validate').Define(T); local BackJit=require('moonlift.back_jit').Define(T)
local Schedule=T.MoonSchedule; local Lower=T.MoonLower; local Back=T.MoonBack
local function assert_no(l,issues) assert(#issues==0,l..' issues '..tostring(#issues)) end
local function base(src)
 local parsed=Parse.parse_module(src); assert_no('parse',parsed.issues)
 local expanded=OpenExpand.module(parsed.module); assert_no('open',OpenValidate.validate(OpenFacts.facts_of_module(expanded)).issues)
 local checked=Typecheck.check_module(ClosureConvert.module(expanded)); assert_no('typecheck',checked.issues)
 local code,contracts=TreeToCode.module_with_contracts(Layout.module(checked.module)); assert_no('code',CodeValidate.validate(code).issues)
 local graph=CodeGraph.graph(code); local flow=CodeFlowFacts.facts(code,graph); local value=CodeValueFacts.facts(code,graph,flow); local mem=CodeMemFacts.semantic_facts(code,graph,flow,value,contracts); local effect=CodeEffectFacts.facts(code,graph,mem,contracts); local kernels=CodeKernelPlan.plan(code,graph,flow,value,mem,effect)
 return code,graph,flow,value,mem,effect,kernels
end
local src=[[
func map_add1(noalias dst: ptr(i32), readonly src: ptr(i32), n: i32): i32
 requires bounds(dst,n)
 requires bounds(src,n)
 requires disjoint(dst,src)
 block loop(i: i32 = 0)
  if i >= n then return 0 end
  let x: i32 = src[i]
  dst[i] = x + 1
  jump loop(i = i + 1)
 end
end
]]
local code,graph,flow,value,mem,effect,kernels=base(src)
local no_vec_schedules=CodeSchedulePlan.plan(code,kernels,flow,value,mem,effect)
for _,s in ipairs(no_vec_schedules.schedules or {}) do assert(pvm.classof(s.kind)~=Schedule.ScheduleVector,'no vector schedule without target vector shape facts') end
local target=Back.BackTargetModel(Back.BackTargetNative,{Back.BackTargetSupportsShape(Back.BackShapeVec(Back.BackVec(Back.BackI32,4)))})
local clamp_code,clamp_graph,clamp_flow,clamp_value,clamp_mem,clamp_effect,clamp_kernels=base([[
func clamp_nonnegative(noalias dst: ptr(i32), readonly src: ptr(i32), n: i32): i32
 requires bounds(dst,n)
 requires bounds(src,n)
 requires disjoint(dst,src)
 block loop(i: i32 = 0)
  if i >= n then return 0 end
  let x: i32 = src[i]
  dst[i] = select(x < 0, 0, x)
  jump loop(i = i + 1)
 end
end
]])
local clamp_schedules=CodeSchedulePlan.plan(clamp_code,clamp_kernels,clamp_flow,clamp_value,clamp_mem,clamp_effect,target)
local saw_clamp_vector=false
for _,s in ipairs(clamp_schedules.schedules or {}) do if pvm.classof(s)==Schedule.SchedulePlanned and pvm.classof(s.kind)==Schedule.ScheduleVector then saw_clamp_vector=true end end
assert(saw_clamp_vector,'vector compare/select emitter should allow clamp to select ScheduleVector')
local triad_code,triad_graph,triad_flow,triad_value,triad_mem,triad_effect,triad_kernels=base([[
func triad(noalias dst: ptr(i32), readonly a: ptr(i32), readonly b: ptr(i32), k: i32, n: i32): i32
 requires bounds(dst,n)
 requires bounds(a,n)
 requires bounds(b,n)
 requires disjoint(dst,a)
 requires disjoint(dst,b)
 block loop(i: i32 = 0)
  if i >= n then return 0 end
  dst[i] = a[i] + b[i] * k
  jump loop(i = i + 1)
 end
end
]])
local triad_schedules=CodeSchedulePlan.plan(triad_code,triad_kernels,triad_flow,triad_value,triad_mem,triad_effect,target)
local saw_triad_vector=false
for _,s in ipairs(triad_schedules.schedules or {}) do if pvm.classof(s)==Schedule.SchedulePlanned and pvm.classof(s.kind)==Schedule.ScheduleVector then saw_triad_vector=true end end
assert(saw_triad_vector,'loop-invariant scalar parameters should be splatted for vector store kernels')
local triad_lower=CodeLowerPlan.plan(triad_code,triad_graph,triad_kernels,triad_schedules,Lower.LowerTargetBack)
assert_no('triad semantic validate',KernelValidate.validate(triad_code,triad_graph,triad_flow,triad_value,triad_mem,triad_effect,triad_kernels,triad_schedules,triad_lower).issues)
assert_no('triad back',BackValidate.validate(LowerToBack.module(triad_code,triad_graph,triad_flow,triad_value,triad_mem,triad_effect,triad_kernels,triad_schedules,triad_lower)).issues)
local direct_triad_program=LowerToBack.module(triad_code,triad_graph,triad_flow,triad_value,triad_mem,triad_effect,triad_kernels,nil,nil,{target_model=target})
local direct_saw_vec=false
for _,cmd in ipairs(direct_triad_program.cmds or {}) do if pvm.classof(cmd)==Back.CmdStoreInfo and pvm.classof(cmd.ty)==Back.BackShapeVec then direct_saw_vec=true end end
assert(direct_saw_vec,'direct LowerToBack.module opts.target_model must reach scheduling')
local schedules=CodeSchedulePlan.plan(code,kernels,flow,value,mem,effect,target)
local saw_vector=false; for _,s in ipairs(schedules.schedules or {}) do if pvm.classof(s)==Schedule.SchedulePlanned and pvm.classof(s.kind)==Schedule.ScheduleVector then saw_vector=true end end; assert(saw_vector,'target vector facts should select ScheduleVector')
local lower=CodeLowerPlan.plan(code,graph,kernels,schedules,Lower.LowerTargetBack)
local saw_lower=false; for _,fp in ipairs(lower.funcs or {}) do for _,fr in ipairs(fp.fragments or {}) do if pvm.classof(fr.strategy)==Lower.LowerStrategyKernel then saw_lower=true; assert(#fr.issues==0) end end end; assert(saw_lower,'vector schedule should lower as LowerStrategyKernel')
assert_no('semantic validate',KernelValidate.validate(code,graph,flow,value,mem,effect,kernels,schedules,lower).issues)
local program=LowerToBack.module(code,graph,flow,value,mem,effect,kernels,schedules,lower); assert_no('back',BackValidate.validate(program).issues)
local saw_vload,saw_vstore,saw_vbin=false,false,false
for _,cmd in ipairs(program.cmds or {}) do
 local cls=pvm.classof(cmd)
 if cls==Back.CmdLoadInfo and pvm.classof(cmd.ty)==Back.BackShapeVec then saw_vload=true end
 if cls==Back.CmdStoreInfo and pvm.classof(cmd.ty)==Back.BackShapeVec then saw_vstore=true end
 if cls==Back.CmdVecBinary then saw_vbin=true end
end
assert(saw_vload and saw_vstore and saw_vbin,'vector lowering must emit vector-shaped load/store and CmdVecBinary')
local jit=BackJit.jit(); local artifact=jit:compile(program); local fn=ffi.cast('int32_t (*)(int32_t*, const int32_t*, intptr_t)', artifact:getpointer(Back.BackFuncId('map_add1')))
local src_arr=ffi.new('int32_t[9]',{1,2,3,4,5,6,7,8,9}); local dst=ffi.new('int32_t[9]',{0,0,0,0,0,0,0,0,0}); assert(fn(dst,src_arr,9)==0)
for i=0,8 do assert(dst[i]==src_arr[i]+1,'bad vector/tail result '..i..' got '..tonumber(dst[i])) end
artifact:free()
io.write('moonlift lower_to_back_kernel_vector ok\n')
