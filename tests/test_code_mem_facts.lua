package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path
local pvm=require('moonlift.pvm'); local T=pvm.context(); require('moonlift.schema').Define(T)
local Parse=require('moonlift.parse').Define(T); local OpenFacts=require('moonlift.open_facts').Define(T); local OpenValidate=require('moonlift.open_validate').Define(T); local OpenExpand=require('moonlift.open_expand').Define(T); local ClosureConvert=require('moonlift.closure_convert').Define(T); local Typecheck=require('moonlift.tree_typecheck').Define(T); local Layout=require('moonlift.sem_layout_resolve').Define(T); local TreeToCode=require('moonlift.tree_to_code').Define(T); local CodeValidate=require('moonlift.code_validate').Define(T); local CodeGraph=require('moonlift.code_graph').Define(T); local CodeFlowFacts=require('moonlift.code_flow_facts').Define(T); local CodeValueFacts=require('moonlift.code_value_facts').Define(T); local CodeMemFacts=require('moonlift.code_mem_facts').Define(T); local LowerToBack=require('moonlift.lower_to_back').Define(T); local BackValidate=require('moonlift.back_validate').Define(T)
local Mem=T.MoonMem; local Back=T.MoonBack
local function assert_no(label, issues) assert(#issues==0,label..' issues '..tostring(#issues)) end
local function lower(src)
 local parsed=Parse.parse_module(src); assert_no('parse',parsed.issues); local expanded=OpenExpand.module(parsed.module); assert_no('open',OpenValidate.validate(OpenFacts.facts_of_module(expanded)).issues); local closed=ClosureConvert.module(expanded); local checked=Typecheck.check_module(closed); assert_no('typecheck',checked.issues); local resolved=Layout.module(checked.module); local code,contracts=TreeToCode.module_with_contracts(resolved); assert_no('code',CodeValidate.validate(code).issues); local graph=CodeGraph.graph(code); local flow=CodeFlowFacts.facts(code,graph); local value=CodeValueFacts.facts(code,graph,flow); local mem=CodeMemFacts.semantic_facts(code,graph,flow,value,contracts); return code,contracts,graph,flow,value,mem end

local code,contracts,graph,flow,value,mem=lower([[
func contracted_copy(noalias dst: ptr(i32), readonly src: ptr(i32), n: i32): i32
 requires bounds(dst,n)
 requires bounds(src,n)
 block loop(i: i32 = 0)
  if i >= n then return 0 end
  dst[i] = src[i]
  jump loop(i = i + 1)
 end
end
]])
assert(mem.module==code.id)
assert(#mem.accesses==2,'expected load/store access facts')
assert(#mem.backend_info==2,'expected backend info for every access')
local saw_load,saw_store,saw_nontrap,saw_move,saw_readonly=false,false,false,false,false
for _,a in ipairs(mem.accesses) do if a.kind==Mem.MemLoad then saw_load=true end; if a.kind==Mem.MemStore then saw_store=true end; assert(a.inst~=nil,'access retains inst provenance') end
for _,info in ipairs(mem.backend_info) do if pvm.classof(info.trap)==Mem.MemNonTrapping then saw_nontrap=true end; if info.movable then saw_move=true end end
for _,e in ipairs(mem.effects) do if pvm.classof(e)==Mem.MemObjectReadonly then saw_readonly=true end end
assert(saw_load and saw_store and saw_nontrap and saw_move,'access/backend metadata should be structured')
assert(saw_readonly,'readonly contracts become object effects')
local program=LowerToBack.module(code,nil,nil,nil,mem,nil,nil,nil,nil); assert_no('back',BackValidate.validate(program).issues)
local saw_back_meta=false
for _,cmd in ipairs(program.cmds or {}) do if pvm.classof(cmd)==Back.CmdLoadInfo and pvm.classof(cmd.memory.trap)==Back.BackNonTrapping and pvm.classof(cmd.memory.motion)==Back.BackCanMove then saw_back_meta=true end end
assert(saw_back_meta,'Back loads consume MemBackendAccessInfo')

local raw_code,_,_,_,_,raw_mem=lower([[
func raw_sum(p: ptr(i32), n: i32): i32
 return block loop(i: i32 = 0, acc: i32 = 0): i32
  if i >= n then yield acc end
  jump loop(i = i + 1, acc = acc + p[i])
 end
end
]])
local saw_unknown=false
for _,object in ipairs(raw_mem.objects) do if pvm.classof(object.extent)==Mem.MemExtentUnknown then saw_unknown=true end end
assert(saw_unknown,'raw pointer params remain unknown extent without contracts')
local saw_raw_maytrap=false
for _,info in ipairs(raw_mem.backend_info or {}) do
 if info.trap==Mem.MemMayTrap then saw_raw_maytrap=true end
 assert(not info.movable,'raw pointer access without bounds/lease/view proof must not be movable')
 assert(pvm.classof(info.bounds)==Mem.MemBoundsUnknown,'raw pointer access without bounds/lease/view proof must keep unknown bounds')
end
assert(saw_raw_maytrap,'raw pointer access without bounds/lease/view proof must remain may-trap')
for _,sf in ipairs(raw_mem.safety or {}) do
 assert(pvm.classof(sf) ~= Mem.MemAccessInBounds,'raw pointer access without bounds/lease/view proof must not emit MemAccessInBounds')
end

local view_code,_,_,_,_,view_mem=lower([[
func view_sum(p: ptr(i32), n: i32): i32
 let v: view(i32) = view(p,n)
 return block loop(i: i32 = 0, acc: i32 = 0): i32
  if i >= n then yield acc end
  jump loop(i = i + 1, acc = acc + v[i])
 end
end
]])
for _,access in ipairs(view_mem.accesses) do assert(pvm.classof(access.base) ~= Mem.MemBaseUnknown, 'view provenance should remain structured, not hidden as an unknown string') end
io.write('moonlift code_mem_facts ok\n')
