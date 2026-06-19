package.path = './?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;' .. package.path

local ffi = require('ffi')
local bit = require('bit')
local pvm = require('moonlift.pvm')
local T = pvm.context()
require('moonlift.schema').Define(T)

local Parse = require('moonlift.parse').Define(T)
local Pipeline = require('moonlift.frontend_pipeline').Define(T)
local BackJit = require('moonlift.back_jit').Define(T)
local Back = T.MoonBack
local Schedule = T.MoonSchedule

local src = [[
func sum_i32(readonly xs: ptr(i32), n: i32, init: i32): i32
 requires bounds(xs,n)
 return block loop(i: i32 = 0, acc: i32 = init): i32
  if i >= n then yield acc end
  jump loop(i = i + 1, acc = acc + xs[i])
 end
end

func prod_i32(readonly xs: ptr(i32), n: i32, init: i32): i32
 requires bounds(xs,n)
 return block loop(i: i32 = 0, acc: i32 = init): i32
  if i >= n then yield acc end
  jump loop(i = i + 1, acc = acc * xs[i])
 end
end

func xor_i32(readonly xs: ptr(i32), n: i32, init: i32): i32
 requires bounds(xs,n)
 return block loop(i: i32 = 0, acc: i32 = init): i32
  if i >= n then yield acc end
  jump loop(i = i + 1, acc = acc ^ xs[i])
 end
end

func and_i32(readonly xs: ptr(i32), n: i32, init: i32): i32
 requires bounds(xs,n)
 return block loop(i: i32 = 0, acc: i32 = init): i32
  if i >= n then yield acc end
  jump loop(i = i + 1, acc = acc & xs[i])
 end
end

func or_i32(readonly xs: ptr(i32), n: i32, init: i32): i32
 requires bounds(xs,n)
 return block loop(i: i32 = 0, acc: i32 = init): i32
  if i >= n then yield acc end
  jump loop(i = i + 1, acc = acc | xs[i])
 end
end

func min_i32(readonly xs: ptr(i32), n: i32, init: i32): i32
 requires bounds(xs,n)
 return block loop(i: i32 = 0, acc: i32 = init): i32
  if i >= n then yield acc end
  let x: i32 = xs[i]
  let next: i32 = select(acc < x, acc, x)
  jump loop(i = i + 1, acc = next)
 end
end

func max_i32(readonly xs: ptr(i32), n: i32, init: i32): i32
 requires bounds(xs,n)
 return block loop(i: i32 = 0, acc: i32 = init): i32
  if i >= n then yield acc end
  let x: i32 = xs[i]
  let next: i32 = select(acc > x, acc, x)
  jump loop(i = i + 1, acc = next)
 end
end
]]

local target = Back.BackTargetModel(Back.BackTargetNative, {
    Back.BackTargetSupportsShape(Back.BackShapeVec(Back.BackVec(Back.BackI32, 4))),
})
local module = Parse.parse_module(src).module
local result = Pipeline.lower_module(module, {
    site = 'test_lower_to_back_vector_reductions',
    target_model = target,
})
assert(#result.back_report.issues == 0)

local saw_vector_schedule = false
for _, sched in ipairs(result.schedule_plan.schedules or {}) do
    if pvm.classof(sched) == Schedule.SchedulePlanned and pvm.classof(sched.kind) == Schedule.ScheduleVector then
        saw_vector_schedule = true
    end
end
assert(saw_vector_schedule, 'supported reductions should select ScheduleVector')

local saw_extract, saw_vbin, saw_vcmp, saw_vselect = false, false, false, false
for _, cmd in ipairs(result.program.cmds or {}) do
    local cls = pvm.classof(cmd)
    if cls == Back.CmdVecExtractLane then saw_extract = true end
    if cls == Back.CmdVecBinary then saw_vbin = true end
    if cls == Back.CmdVecCompare then saw_vcmp = true end
    if cls == Back.CmdVecSelect then saw_vselect = true end
end
assert(saw_extract and saw_vbin, 'vector reduction lowering should emit vector combines and horizontal folds')
assert(saw_vcmp and saw_vselect, 'min/max reductions should emit vector compare/select')

local artifact = BackJit.jit():compile(result.program)
local fty = 'int32_t (*)(const int32_t*, int32_t, int32_t)'
local f_sum = ffi.cast(fty, artifact:getpointer(Back.BackFuncId('sum_i32')))
local f_prod = ffi.cast(fty, artifact:getpointer(Back.BackFuncId('prod_i32')))
local f_xor = ffi.cast(fty, artifact:getpointer(Back.BackFuncId('xor_i32')))
local f_and = ffi.cast(fty, artifact:getpointer(Back.BackFuncId('and_i32')))
local f_or = ffi.cast(fty, artifact:getpointer(Back.BackFuncId('or_i32')))
local f_min = ffi.cast(fty, artifact:getpointer(Back.BackFuncId('min_i32')))
local f_max = ffi.cast(fty, artifact:getpointer(Back.BackFuncId('max_i32')))

local xs = ffi.new('int32_t[9]', { 5, -2, 7, 3, 4, -6, 8, 1, 9 })
local ns = { 0, 2, 4, 5, 8, 9 }

local function fold(n, init, fn)
    local acc = init
    for i = 0, n - 1 do acc = fn(acc, tonumber(xs[i])) end
    return acc
end

for _, n in ipairs(ns) do
    local exp = fold(n, 10, function(a, b) return a + b end); local got = f_sum(xs, n, 10); assert(got == exp, 'bad sum n=' .. n .. ' got=' .. got .. ' expected=' .. exp)
    exp = fold(n, 2, function(a, b) return a * b end); got = f_prod(xs, n, 2); assert(got == exp, 'bad prod n=' .. n .. ' got=' .. got .. ' expected=' .. exp)
    exp = fold(n, 3, function(a, b) return bit.bxor(a, b) end); got = f_xor(xs, n, 3); assert(got == exp, 'bad xor n=' .. n .. ' got=' .. got .. ' expected=' .. exp)
    exp = fold(n, -1, function(a, b) return bit.band(a, b) end); got = f_and(xs, n, -1); assert(got == exp, 'bad and n=' .. n .. ' got=' .. got .. ' expected=' .. exp)
    exp = fold(n, 16, function(a, b) return bit.bor(a, b) end); got = f_or(xs, n, 16); assert(got == exp, 'bad or n=' .. n .. ' got=' .. got .. ' expected=' .. exp)
    exp = fold(n, 100, function(a, b) return a < b and a or b end); got = f_min(xs, n, 100); assert(got == exp, 'bad min n=' .. n .. ' got=' .. got .. ' expected=' .. exp)
    exp = fold(n, -100, function(a, b) return a > b and a or b end); got = f_max(xs, n, -100); assert(got == exp, 'bad max n=' .. n .. ' got=' .. got .. ' expected=' .. exp)
end

artifact:free()
io.write('moonlift lower_to_back_vector_reductions ok\n')
