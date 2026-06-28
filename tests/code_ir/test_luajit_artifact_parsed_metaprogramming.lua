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
local elem_ty = i32
local ptr_elem_ty = ptr [elem_ty]
local factor = 3
local bias = 5

local scaled_expr = expr x * [factor] + [bias] end

local scale_stmt = stmt
  dst[i] = src[i] * [factor]
end

local scale_one = fn(x [elem_ty]) [elem_ty]
  return [scaled_expr]
end

local scale_array = fn(dst [ptr_elem_ty], src [ptr_elem_ty], n [index]) [void]
  requires bounds(dst)(n), writeonly(dst), bounds(src)(n), readonly(src), disjoint(dst)(src)
  loop i in 0 .. n do
    [scale_stmt]
  end
end

return {
  scale_one,
  scale_array,
}
]=]

local parsed = assert(lalin.loadstring(source, '@test_luajit_artifact_parsed_metaprogramming.lln'))()
local loaded = lalin.compile('ParsedMetaprogramming', parsed, { residual = 'bc' })

assert(loaded.scale_one(4) == 17, 'parsed expr fragment splice with host literals')

local src = ffi.new('int32_t[4]', { 2, -3, 4, 5 })
local dst = ffi.new('int32_t[4]')
loaded.scale_array(dst, src, 4)
assert(dst[0] == 6 and dst[1] == -9 and dst[2] == 12 and dst[3] == 15, 'parsed stmt fragment splice with type host escapes')

io.write('test_luajit_artifact_parsed_metaprogramming: ok\n')
