package.path = table.concat({
    './?.lua',
    './?/init.lua',
    './lua/?.lua',
    './lua/?/init.lua',
    package.path,
}, ';')

local ffi = require('ffi')
local pvm = require('lalin.pvm')
local lalin = require('lalin')

local source = [=[
local copy2d = fn(dst [ptr [i32]], src [ptr [i32]], h [index], w [index], n [index]) [void]
  requires bounds(dst)(n), writeonly(dst), bounds(src)(n), readonly(src), disjoint(dst)(src)
  loop i, j in grid(0 .. h, 0 .. w) do
    dst[i * w + j] = src[i * w + j]
  end
end

local tiled_scan_rows = fn(dst [ptr [i32]], xs [ptr [i32]], h [index], w [index], n [index]) [void]
  requires bounds(dst)(n), writeonly(dst), bounds(xs)(n), readonly(xs), disjoint(dst)(xs)
  loop i, j in tiled grid(0 .. h, 0 .. w) by 2, 2 do
    scan acc [i32] = 0 by add over j step xs[i * w + j] into dst[i * w + j]
  end
end

local prev_clamp = fn(dst [ptr [i32]], xs [ptr [i32]], n [index]) [void]
  requires bounds(dst)(n), writeonly(dst), bounds(xs)(n), readonly(xs), disjoint(dst)(xs)
  loop i in window(0 .. n, before = 1, after = 1, boundary = clamp) do
    dst[i] = xs[i - 1]
  end
end

return {
  copy2d,
  tiled_scan_rows,
  prev_clamp,
}
]=]

local parsed = assert(lalin.loadstring(source, '@test_luajit_artifact_nd_parsed.lln'))()
local plan = lalin.plan_luajit_artifact(parsed, {
    name = 'ParsedND',
    stem = 'test_luajit_artifact_nd_parsed',
})
local bank = assert(plan.backend.build_mc_bank(plan.artifacts, { stem = 'test_luajit_artifact_nd_parsed' }))
local artifact = lalin.emit_luajit_plan_artifact(plan, {
    path = 'target/test_artifacts/test_luajit_artifact_nd_parsed.lua',
    name = 'ParsedND',
    stem = 'test_luajit_artifact_nd_parsed',
    mc_bank = bank,
})

assert(#artifact.artifacts == 3, 'parsed ND source should select range, tiled scan, and window artifacts')
local seen = {}
for _, item in ipairs(artifact.artifacts) do
    local desc = item.instance.descriptor
    seen[tostring(pvm.classof(desc.producer.shape))] = true
end
assert(seen['Class(LalinStencil.StencilProduceRangeND)'], 'parsed range_nd should preserve RangeND producer')
assert(seen['Class(LalinStencil.StencilProduceTiledND)'], 'parsed tiled_nd should preserve TiledND producer')
assert(seen['Class(LalinStencil.StencilProduceWindowND)'], 'parsed window_nd should preserve WindowND producer')

local loaded = assert(loadfile(artifact.path))()

local src = ffi.new('int32_t[6]', { 1, 2, 3, 4, 5, 6 })
local dst = ffi.new('int32_t[6]')
loaded.copy2d(dst, src, 2, 3, 6)
assert(dst[0] == 1 and dst[1] == 2 and dst[2] == 3 and dst[3] == 4 and dst[4] == 5 and dst[5] == 6, 'parsed range_nd copy')

local scan_dst = ffi.new('int32_t[6]')
loaded.tiled_scan_rows(scan_dst, src, 2, 3, 6)
assert(scan_dst[0] == 1 and scan_dst[1] == 3 and scan_dst[2] == 6 and scan_dst[3] == 4 and scan_dst[4] == 9 and scan_dst[5] == 15, 'parsed tiled_nd axis scan')

local win_dst = ffi.new('int32_t[6]')
loaded.prev_clamp(win_dst, src, 6)
assert(win_dst[0] == 1 and win_dst[1] == 1 and win_dst[2] == 2 and win_dst[3] == 3 and win_dst[4] == 4 and win_dst[5] == 5, 'parsed window_nd neighbor')

io.write('test_luajit_artifact_nd_parsed: ok\n')
