package.path = './?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;' .. package.path
local pvm=require('moonlift.pvm'); local T=pvm.context(); require('moonlift.schema').Define(T)
local Parse=require('moonlift.parse').Define(T); local OpenFacts=require('moonlift.open_facts').Define(T); local OpenValidate=require('moonlift.open_validate').Define(T); local OpenExpand=require('moonlift.open_expand').Define(T); local ClosureConvert=require('moonlift.closure_convert').Define(T); local Typecheck=require('moonlift.tree_typecheck').Define(T); local Layout=require('moonlift.sem_layout_resolve').Define(T); local TreeToCode=require('moonlift.tree_to_code').Define(T); local CodeValidate=require('moonlift.code_validate').Define(T); local CodeGraph=require('moonlift.code_graph').Define(T)
local Graph=T.MoonGraph
local function assert_no(l,issues) assert(#issues==0,l..' issues '..tostring(#issues)) end
local function code_of(src)
 local parsed=Parse.parse_module(src); assert_no('parse',parsed.issues)
 local expanded=OpenExpand.module(parsed.module); assert_no('open',OpenValidate.validate(OpenFacts.facts_of_module(expanded)).issues)
 local checked=Typecheck.check_module(ClosureConvert.module(expanded)); assert_no('typecheck',checked.issues)
 local resolved=Layout.module(checked.module); local code=TreeToCode.module(resolved); assert_no('code',CodeValidate.validate(code).issues); return code
end
local code=code_of([[
func graph_sum(n: i32): i32
 return block loop(i: i32 = 0, acc: i32 = 0): i32
  if i >= n then yield acc end
  jump loop(i = i + 1, acc = acc + i)
 end
end
]])
local graph=CodeGraph.graph(code)
assert(graph.module==code.id and #graph.funcs==1,'graph is keyed by Code module/function')
local fg=graph.funcs[1]
assert(#fg.edges>=2,'graph should record CFG edges')
assert(#fg.defs>0,'graph should record defs')
assert(#fg.uses>0,'graph should record uses')
assert(#fg.loops>=1,'graph should detect natural loop')
local loop=fg.loops[1]
assert(pvm.classof(loop.id)==Graph.GraphLoopId,'loop id must be MoonGraph.GraphLoopId')
assert(loop.header~=nil and #loop.body>0 and #loop.latches>0,'loop should have header/body/latch')
io.write('moonlift code_graph ok\n')
