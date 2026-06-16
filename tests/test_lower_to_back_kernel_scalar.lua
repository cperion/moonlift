package.path='./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;'..package.path

local ffi=require('ffi')
local pvm=require('moonlift.pvm'); local T=pvm.context(); require('moonlift.schema').Define(T)
local Parse=require('moonlift.parse').Define(T); local OpenFacts=require('moonlift.open_facts').Define(T); local OpenValidate=require('moonlift.open_validate').Define(T); local OpenExpand=require('moonlift.open_expand').Define(T); local ClosureConvert=require('moonlift.closure_convert').Define(T); local Typecheck=require('moonlift.tree_typecheck').Define(T); local Layout=require('moonlift.sem_layout_resolve').Define(T); local TreeToCode=require('moonlift.tree_to_code').Define(T); local CodeValidate=require('moonlift.code_validate').Define(T); local CodeGraph=require('moonlift.code_graph').Define(T); local CodeFlowFacts=require('moonlift.code_flow_facts').Define(T); local CodeValueFacts=require('moonlift.code_value_facts').Define(T); local CodeMemFacts=require('moonlift.code_mem_facts').Define(T); local CodeEffectFacts=require('moonlift.code_effect_facts').Define(T); local CodeKernelPlan=require('moonlift.code_kernel_plan').Define(T); local CodeSchedulePlan=require('moonlift.code_schedule_plan').Define(T); local CodeLowerPlan=require('moonlift.code_lower_plan').Define(T); local KernelValidate=require('moonlift.kernel_validate').Define(T); local LowerToBack=require('moonlift.lower_to_back').Define(T); local BackValidate=require('moonlift.back_validate').Define(T); local BackJit=require('moonlift.back_jit').Define(T)
local Kernel=T.MoonKernel; local Schedule=T.MoonSchedule; local Lower=T.MoonLower; local Back=T.MoonBack; local Mem=T.MoonMem
local function assert_no(l,issues) assert(#issues==0,l..' issues '..tostring(#issues)) end
local function lower(src)
 local parsed=Parse.parse_module(src); assert_no('parse',parsed.issues)
 local expanded=OpenExpand.module(parsed.module); assert_no('open',OpenValidate.validate(OpenFacts.facts_of_module(expanded)).issues)
 local checked=Typecheck.check_module(ClosureConvert.module(expanded)); assert_no('typecheck',checked.issues)
 local code,contracts=TreeToCode.module_with_contracts(Layout.module(checked.module)); assert_no('code',CodeValidate.validate(code).issues)
 local graph=CodeGraph.graph(code); local flow=CodeFlowFacts.facts(code,graph); local value=CodeValueFacts.facts(code,graph,flow); local mem=CodeMemFacts.semantic_facts(code,graph,flow,value,contracts); local effect=CodeEffectFacts.facts(code,graph,mem,contracts); local kernels=CodeKernelPlan.plan(code,graph,flow,value,mem,effect); local schedules=CodeSchedulePlan.plan(code,kernels,flow,value,mem,effect); local lower=CodeLowerPlan.plan(code,graph,kernels,schedules,Lower.LowerTargetBack)
 return code,graph,flow,value,mem,effect,kernels,schedules,lower
end
local code,graph,flow,value,mem,effect,kernels,schedules,lowered=lower([[
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
]])
local saw_store,saw_load=false,false
for _,p in ipairs(kernels.plans or {}) do if pvm.classof(p)==Kernel.KernelPlanned then for _,b in ipairs(p.body.bindings or {}) do if pvm.classof(b.expr)==Kernel.KernelExprLoad then saw_load=true end end; for _,e in ipairs(p.body.effects or {}) do if pvm.classof(e)==Kernel.KernelEffectStore then saw_store=true end end end end
assert(saw_load and saw_store,'KernelBody must contain load binding and store effect')
local saw_scalar=false; for _,s in ipairs(schedules.schedules or {}) do if pvm.classof(s)==Schedule.SchedulePlanned and (s.kind==Schedule.ScheduleScalarIndex or s.kind==Schedule.ScheduleScalarPointer) then saw_scalar=true end end; assert(saw_scalar,'default target should choose scalar schedule')
local saw_lower=false; for _,fp in ipairs(lowered.funcs or {}) do for _,fr in ipairs(fp.fragments or {}) do if pvm.classof(fr.strategy)==Lower.LowerStrategyKernel then saw_lower=true; assert(#fr.issues==0,'scalar kernel fragment must not have fallback') end end end; assert(saw_lower,'LowerStrategyKernel must be selected')
assert_no('semantic validate',KernelValidate.validate(code,graph,flow,value,mem,effect,kernels,schedules,lowered).issues)
local program=LowerToBack.module(code,graph,flow,value,mem,effect,kernels,schedules,lowered); assert_no('back',BackValidate.validate(program).issues)
local saw_meta=false; for _,cmd in ipairs(program.cmds or {}) do if (pvm.classof(cmd)==Back.CmdLoadInfo or pvm.classof(cmd)==Back.CmdStoreInfo) and pvm.classof(cmd.memory.trap)==Back.BackNonTrapping and pvm.classof(cmd.memory.motion)==Back.BackCanMove then saw_meta=true end end; assert(saw_meta,'scalar kernel memory ops must carry MemBackendAccessInfo metadata')
local jit=BackJit.jit(); local artifact=jit:compile(program); local fn=ffi.cast('int32_t (*)(int32_t*, const int32_t*, intptr_t)', artifact:getpointer(Back.BackFuncId('map_add1')))
local src=ffi.new('int32_t[6]',{1,2,3,4,5,6}); local dst=ffi.new('int32_t[6]',{0,0,0,0,0,0}); assert(fn(dst,src,6)==0); for i=0,5 do assert(dst[i]==src[i]+1,'bad dst '..i) end; artifact:free()

local unsafe_code,unsafe_graph,unsafe_flow,unsafe_value,unsafe_mem,unsafe_effect,unsafe_kernels,unsafe_schedules,unsafe_lower=lower([[
func unsafe_map(dst: ptr(i32), src: ptr(i32), n: i32): i32
 block loop(i: i32 = 0)
  if i >= n then return 0 end
  dst[i] = src[i]
  jump loop(i = i + 1)
 end
end
]])
local saw_no_plan=false; for _,p in ipairs(unsafe_kernels.plans or {}) do if pvm.classof(p)==Kernel.KernelNoPlan and pvm.classof(p.subject)==Kernel.KernelSubjectLoop then saw_no_plan=true end end; assert(saw_no_plan,'unsafe map must be KernelNoPlan')
local saw_fallback=false; for _,fp in ipairs(unsafe_lower.funcs or {}) do for _,fr in ipairs(fp.fragments or {}) do for _,issue in ipairs(fr.issues or {}) do if pvm.classof(issue)==Lower.LowerIssueFallback then saw_fallback=true end end end end; assert(saw_fallback,'unsafe map must retain explicit LowerIssueFallback')
for _,info in ipairs(unsafe_mem.backend_info or {}) do assert(info.trap==Mem.MemMayTrap,'unsafe mem remains may-trap') end

local alias_code,alias_graph,alias_flow,alias_value,alias_mem,alias_effect,alias_kernels=lower([[
func store_then_load(p: ptr(i32), n: i32): i32
 requires bounds(p,n)
 return block loop(i: i32 = 0, acc: i32 = 0): i32
  if i >= n then yield acc end
  p[i] = 1
  let x: i32 = p[i]
  jump loop(i = i + 1, acc = acc + x)
 end
end
]])
local alias_rejected=false
for _,p in ipairs(alias_kernels.plans or {}) do
 if pvm.classof(p)==Kernel.KernelNoPlan and pvm.classof(p.subject)==Kernel.KernelSubjectLoop then alias_rejected=true end
end
assert(alias_rejected,'same-object store-then-load must not be scalar-kernel planned because emitter reorders loads before stores')
io.write('moonlift lower_to_back_kernel_scalar ok\n')
