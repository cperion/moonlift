package.path='./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;'..package.path

local pvm=require('moonlift.pvm'); local T=pvm.context(); require('moonlift.schema').Define(T)
local Parse=require('moonlift.parse').Define(T)
local Pipeline=require('moonlift.frontend_pipeline').Define(T)
local CEmit=require('moonlift.c_emit').Define(T)
local LowerToC=require('moonlift.lower_to_c').Define(T)
local Back=T.MoonBack
local Lower=T.MoonLower
local Schedule=T.MoonSchedule

local function assert_no(label, issues)
    assert(#issues==0, label..' issues '..tostring(#issues))
end

local function lower_c(src, target_model)
    local parsed=Parse.parse_module(src); assert_no('parse', parsed.issues)
    local r=Pipeline.lower_module_to_c(parsed.module, { target_model=target_model, c_opts={dialect='c11'} })
    assert_no('code', r.code_report.issues)
    assert_no('kernel validate', r.kernel_report.issues)
    assert_no('c validate', r.c_report.issues)
    local c_src=CEmit.emit_artifact(r.c_unit, {dialect='c11'}).source
    assert(not c_src:find('semantic kernel structured C', 1, true), 'semantic C lowering must not use raw structured-kernel blocks')
    assert(not c_src:find('semantic closed-form structured C', 1, true), 'semantic C lowering must not use raw structured closed-form blocks')
    return c_src, r
end

local function has_strategy(r, klass)
    for _,fp in ipairs(r.lower_plan.funcs or {}) do
        for _,fr in ipairs(fp.fragments or {}) do if pvm.classof(fr.strategy)==klass then return true end end
    end
    return false
end

local function has_vector_schedule(r)
    for _,s in ipairs(r.schedule_plan.schedules or {}) do
        if pvm.classof(s)==Schedule.SchedulePlanned and pvm.classof(s.kind)==Schedule.ScheduleVector then return true end
    end
    return false
end

local function cc_run(c_src, main_src)
    local cc=os.getenv('CC') or 'cc'
    local c_path=os.tmpname()..'.c'
    local main_path=os.tmpname()..'.c'
    local exe=os.tmpname()
    local f=assert(io.open(c_path,'wb')); f:write(c_src); f:close()
    f=assert(io.open(main_path,'wb')); f:write(main_src); f:close()
    local ok=os.execute(cc..' -std=c11 '..c_path..' '..main_path..' -o '..exe..' >/tmp/moonlift_c_test.log 2>&1')
    assert(ok==true or ok==0, 'cc failed; see /tmp/moonlift_c_test.log')
    ok=os.execute(exe..' >/tmp/moonlift_c_test.log 2>&1')
    os.remove(c_path); os.remove(main_path); os.remove(exe)
    assert(ok==true or ok==0, 'compiled C program failed; see /tmp/moonlift_c_test.log')
end

local series_src=[[
func series(n: i32): i32
 return block loop(i: i32 = 0, acc: i32 = 0): i32
  if i >= n then yield acc end
  jump loop(i = i + 1, acc = acc + i)
 end
end
]]
local series_c, series_r=lower_c(series_src)
assert(series_c:find('semantic closed%-form'), 'closed-form fragment must be emitted semantically')
assert(has_strategy(series_r, Lower.LowerStrategyClosedForm), 'LowerTargetC must select LowerStrategyClosedForm')
cc_run(series_c, [[
#include <stdint.h>
int32_t series(int32_t n);
int main(){ return (series(-3)==0 && series(0)==0 && series(5)==10 && series(9)==36) ? 0 : 1; }
]])

local copy_src=[[
func copy(noalias dst: ptr(i32), readonly src: ptr(i32), n: i32): i32
 requires bounds(dst,n)
 requires bounds(src,n)
 requires disjoint(dst,src)
 block loop(i: i32 = 0)
  if i >= n then return 0 end
  let x: i32 = src[i]
  dst[i] = x
  jump loop(i = i + 1)
 end
end
]]
local copy_c, copy_r=lower_c(copy_src)
assert(copy_c:find('semantic scalar kernel'), 'copy must use semantic scalar kernel lowering')
assert(has_strategy(copy_r, Lower.LowerStrategyKernel), 'copy must select LowerStrategyKernel')
cc_run(copy_c, [[
#include <stdint.h>
int32_t copy(void* dst, void* src, int32_t n);
int main(){ int32_t src[6]={9,8,7,6,5,4}, dst[6]={0}; if(copy(dst,src,6)!=0) return 1; for(int i=0;i<6;i++) if(dst[i]!=src[i]) return 2+i; return 0; }
]])

local add2_src=[[
func add2(noalias dst: ptr(i32), readonly a: ptr(i32), readonly b: ptr(i32), n: i32): i32
 requires bounds(dst,n)
 requires bounds(a,n)
 requires bounds(b,n)
 requires disjoint(dst,a)
 requires disjoint(dst,b)
 block loop(i: i32 = 0)
  if i >= n then return 0 end
  let x: i32 = a[i]
  let y: i32 = b[i]
  dst[i] = x + y
  jump loop(i = i + 1)
 end
end
]]
local add2_c, add2_r=lower_c(add2_src)
assert(add2_c:find('semantic scalar kernel'), 'two-input map must use semantic scalar kernel lowering')
assert(has_strategy(add2_r, Lower.LowerStrategyKernel), 'two-input map must select LowerStrategyKernel')
cc_run(add2_c, [[
#include <stdint.h>
int32_t add2(void* dst, void* a, void* b, int32_t n);
int main(){ int32_t a[7]={1,2,3,4,5,6,7}, b[7]={10,20,30,40,50,60,70}, dst[7]={0}; if(add2(dst,a,b,7)!=0) return 1; for(int i=0;i<7;i++) if(dst[i]!=a[i]+b[i]) return 2+i; return 0; }
]])
do
    local planned
    for _, p in ipairs(add2_r.kernel_plan.plans or {}) do
        if pvm.classof(p) == T.MoonKernel.KernelPlanned then planned = planned or p end
    end
    assert(planned ~= nil, 'add2 test needs planned kernel')
    local first = add2_r.lower_plan.funcs[1].fragments[1]
    local bad = Lower.LowerFragment(first.id, first.cover, Lower.LowerStrategyKernel(planned.id, Schedule.ScheduleId('schedule:missing')), first.proofs, first.issues)
    local bad_lower = Lower.LowerModule(add2_r.lower_plan.module, add2_r.lower_plan.target, add2_r.lower_plan.kernels, add2_r.lower_plan.schedules, { Lower.LowerFuncPlan(add2_r.lower_plan.funcs[1].func, { bad }) }, add2_r.lower_plan.issues)
    local ok, err = pcall(function() LowerToC.module(add2_r.code_module, bad_lower, { dialect = 'c11' }) end)
    assert(not ok and tostring(err):find('missing schedule', 1, true), 'LowerToC must fail loud for dangling semantic schedules')
end

local view_sum_src=[[
func view_sum(p: ptr(i32), n: index): i32
 let v: view(i32) = view(p, n)
 block loop(i: index = 0, acc: i32 = 0)
  if i >= n then return acc end
  jump loop(i = i + 1, acc = acc + v[i])
 end
end
]]
local view_sum_c, view_sum_r=lower_c(view_sum_src)
assert(view_sum_c:find('semantic scalar kernel'), 'view sum must use semantic scalar kernel lowering')
assert(has_strategy(view_sum_r, Lower.LowerStrategyKernel), 'view sum must select LowerStrategyKernel')
cc_run(view_sum_c, [[
#include <stdint.h>
#include <stddef.h>
int32_t view_sum(void* p, intptr_t n);
int main(){ int32_t xs[8]={4,-2,7,1,3,-5,9,6}; int32_t want=0; for(int i=0;i<8;i++) want+=xs[i]; return view_sum(xs,8)==want ? 0 : 1; }
]])

local view_sum_strided_src=[[
func view_sum_strided(p: ptr(i32), n: index): i32
 let v: view(i32) = view(p, n, 2)
 block loop(i: index = 0, acc: i32 = 0)
  if i >= n then return acc end
  jump loop(i = i + 1, acc = acc + v[i])
 end
end
]]
local view_sum_strided_c, view_sum_strided_r=lower_c(view_sum_strided_src)
assert(view_sum_strided_c:find('semantic scalar kernel'), 'strided view sum must use semantic scalar kernel lowering')
assert(has_strategy(view_sum_strided_r, Lower.LowerStrategyKernel), 'strided view sum must select LowerStrategyKernel')
cc_run(view_sum_strided_c, [[
#include <stdint.h>
#include <stddef.h>
int32_t view_sum_strided(void* p, intptr_t n);
int main(){ int32_t xs[12]={3,100,-1,100,4,100,8,100,-6,100,2,100}; int32_t want=3-1+4+8-6+2; return view_sum_strided(xs,6)==want ? 0 : 1; }
]])

local submul_src=[[
func submul(noalias dst_sub: ptr(i32), noalias dst_mul: ptr(i32), readonly a: ptr(i32), readonly b: ptr(i32), n: i32): i32
 requires bounds(dst_sub,n)
 requires bounds(dst_mul,n)
 requires bounds(a,n)
 requires bounds(b,n)
 requires disjoint(dst_sub,a)
 requires disjoint(dst_sub,b)
 requires disjoint(dst_mul,a)
 requires disjoint(dst_mul,b)
 requires disjoint(dst_sub,dst_mul)
 block loop(i: i32 = 0)
  if i >= n then return 0 end
  let x: i32 = a[i]
  let y: i32 = b[i]
  dst_sub[i] = x - y
  dst_mul[i] = x * y
  jump loop(i = i + 1)
 end
end
]]
local submul_c, submul_r=lower_c(submul_src)
assert(submul_c:find('semantic scalar kernel'), 'sub/mul multi-output map must use semantic scalar kernel lowering')
assert(has_strategy(submul_r, Lower.LowerStrategyKernel), 'sub/mul multi-output map must select LowerStrategyKernel')
cc_run(submul_c, [[
#include <stdint.h>
int32_t submul(void* dst_sub, void* dst_mul, void* a, void* b, int32_t n);
int main(){ int32_t a[6]={2,4,6,8,10,12}, b[6]={1,3,5,7,9,11}, s[6]={0}, m[6]={0}; if(submul(s,m,a,b,6)!=0) return 1; for(int i=0;i<6;i++){ if(s[i]!=a[i]-b[i]) return 2+i; if(m[i]!=a[i]*b[i]) return 20+i; } return 0; }
]])

local twoout_src=[[
func twoout(noalias dst1: ptr(i32), noalias dst2: ptr(i32), readonly src: ptr(i32), n: i32): i32
 requires bounds(dst1,n)
 requires bounds(dst2,n)
 requires bounds(src,n)
 requires disjoint(dst1,src)
 requires disjoint(dst2,src)
 requires disjoint(dst1,dst2)
 block loop(i: i32 = 0)
  if i >= n then return 0 end
  let x: i32 = src[i]
  dst1[i] = x + 1
  dst2[i] = x * 2
  jump loop(i = i + 1)
 end
end
]]
local twoout_c, twoout_r=lower_c(twoout_src)
assert(twoout_c:find('semantic scalar kernel'), 'multi-output map must use semantic scalar kernel lowering')
assert(has_strategy(twoout_r, Lower.LowerStrategyKernel), 'multi-output map must select LowerStrategyKernel')
cc_run(twoout_c, [[
#include <stdint.h>
int32_t twoout(void* dst1, void* dst2, void* src, int32_t n);
int main(){ int32_t src[5]={3,4,5,6,7}, dst1[5]={0}, dst2[5]={0}; if(twoout(dst1,dst2,src,5)!=0) return 1; for(int i=0;i<5;i++){ if(dst1[i]!=src[i]+1) return 2+i; if(dst2[i]!=src[i]*2) return 20+i; } return 0; }
]])

local step2_src=[[
func step2(noalias dst: ptr(i32), readonly src: ptr(i32), n: i32): i32
 requires bounds(dst,n)
 requires bounds(src,n)
 requires disjoint(dst,src)
 block loop(i: i32 = 1)
  if i >= n then return 0 end
  let x: i32 = src[i]
  dst[i] = x + 3
  jump loop(i = i + 2)
 end
end
]]
local step2_c, step2_r=lower_c(step2_src)
assert(step2_c:find('semantic scalar kernel'), 'nonzero/nonunit counted loop must use semantic scalar kernel lowering')
assert(has_strategy(step2_r, Lower.LowerStrategyKernel), 'nonzero/nonunit counted loop must select LowerStrategyKernel')
cc_run(step2_c, [[
#include <stdint.h>
int32_t step2(void* dst, void* src, int32_t n);
int main(){ int32_t src[8]={0,10,20,30,40,50,60,70}, dst[8]={0}; if(step2(dst,src,8)!=0) return 1; for(int i=0;i<8;i++){ int32_t want=(i%2==1)?src[i]+3:0; if(dst[i]!=want) return 2+i; } return 0; }
]])

local target=Back.BackTargetModel(Back.BackTargetNative,{Back.BackTargetSupportsShape(Back.BackShapeVec(Back.BackVec(Back.BackI32,4)))})
local vector_c, vector_r=lower_c(add2_src, target)
assert(vector_c:find('semantic vector main loop lanes=4'), 'vector target must emit semantic vector kernel lowering')
assert(vector_c:find('semantic vector scalar tail'), 'vector target must emit scalar tail')
assert(has_vector_schedule(vector_r), 'vector target must select ScheduleVector for C')
cc_run(vector_c, [[
#include <stdint.h>
int32_t add2(void* dst, void* a, void* b, int32_t n);
int main(){ int32_t a[9]={1,2,3,4,5,6,7,8,9}, b[9]={9,8,7,6,5,4,3,2,1}, dst[9]={0}; if(add2(dst,a,b,9)!=0) return 1; for(int i=0;i<9;i++) if(dst[i]!=a[i]+b[i]) return 2+i; return 0; }
]])

local unsupported_call_src=[[
extern host_id(x: i32): i32 end
func call_loop(noalias dst: ptr(i32), n: i32): i32
 requires bounds(dst,n)
 block loop(i: i32 = 0)
  if i >= n then return 0 end
  let x: i32 = host_id(i)
  dst[i] = x
  jump loop(i = i + 1)
 end
end
]]
local call_c, call_r=lower_c(unsupported_call_src)
assert(not has_strategy(call_r, Lower.LowerStrategyKernel), 'loop with call effect must not be misrepresented as an executable semantic kernel')
assert(not call_c:find('semantic scalar kernel'), 'unsupported call-effect loop must stay on Code lowering')
cc_run(call_c, [[
#include <stdint.h>
int32_t host_id(int32_t x){ return x + 5; }
int32_t call_loop(void* dst, int32_t n);
int main(){ int32_t dst[4]={0}; if(call_loop(dst,4)!=0) return 1; for(int i=0;i<4;i++) if(dst[i]!=i+5) return 2+i; return 0; }
]])

io.write('moonlift lower_to_c_semantic ok\n')
