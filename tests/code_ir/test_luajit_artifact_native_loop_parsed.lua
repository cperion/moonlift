package.path = table.concat({
    './?.lua',
    './?/init.lua',
    './lua/?.lua',
    './lua/?/init.lua',
    package.path,
}, ';')

local ffi = require('ffi')
local lalin = require('lalin')

local source = [=[
local zip_add = fn(dst [ptr [i32]], lhs [ptr [i32]], rhs [ptr [i32]], n [index]) [void]
  requires bounds(dst)(n), writeonly(dst), bounds(lhs)(n), readonly(lhs), bounds(rhs)(n), readonly(rhs)
  requires disjoint(dst)(lhs), disjoint(dst)(rhs), disjoint(lhs)(rhs)
  loop i in 0 .. n do
    dst[i] = lhs[i] + rhs[i]
  end
end

local dot = fn(lhs [ptr [i32]], rhs [ptr [i32]], n [index]) [i32]
  requires bounds(lhs)(n), readonly(lhs), bounds(rhs)(n), readonly(rhs)
  loop i in 0 .. n do
    fold acc [i32] = 0 by add step lhs[i] * rhs[i]
  end
end

local product = fn(xs [ptr [i32]], n [index]) [i32]
  requires bounds(xs)(n), readonly(xs)
  loop i in 0 .. n do
    fold acc [i32] = 1 by mul step xs[i]
  end
end

local min_i32 = fn(xs [ptr [i32]], n [index]) [i32]
  requires bounds(xs)(n), readonly(xs)
  loop i in 0 .. n do
    fold acc [i32] = 2147483647 by min step xs[i]
  end
end

local scan_sum = fn(dst [ptr [i32]], xs [ptr [i32]], n [index]) [void]
  requires bounds(dst)(n), writeonly(dst), bounds(xs)(n), readonly(xs), disjoint(dst)(xs)
  loop i in 0 .. n do
    scan acc [i32] = 0 by add step xs[i] into dst[i]
  end
end

return {
  zip_add,
  dot,
  product,
  min_i32,
  scan_sum,
}
]=]

local parsed = assert(lalin.loadstring(source, '@test_luajit_artifact_native_loop_parsed.lln'))()
local loaded = lalin.compile('ParsedNativeLoop', parsed, { residual = 'bc' })

local lhs = ffi.new('int32_t[5]', { 1, -2, 5, 0, 3 })
local rhs = ffi.new('int32_t[5]', { 10, 20, -5, 7, 4 })
local out = ffi.new('int32_t[5]')

loaded.zip_add(out, lhs, rhs, 5)
assert(out[0] == 11 and out[1] == 18 and out[2] == 0 and out[3] == 7 and out[4] == 7, 'parsed range store loop')

assert(loaded.dot(lhs, rhs, 5) == -43, 'parsed fold add dot')

local product_xs = ffi.new('int32_t[4]', { 2, -3, 4, 5 })
assert(loaded.product(product_xs, 4) == -120, 'parsed fold mul product')
assert(loaded.min_i32(product_xs, 4) == -3, 'parsed fold min')

local scan_xs = ffi.new('int32_t[5]', { 1, -2, 5, 0, 3 })
local scan_out = ffi.new('int32_t[5]')
loaded.scan_sum(scan_out, scan_xs, 5)
assert(scan_out[0] == 1 and scan_out[1] == -1 and scan_out[2] == 4 and scan_out[3] == 4 and scan_out[4] == 7, 'parsed scan add')

io.write('test_luajit_artifact_native_loop_parsed: ok\n')
