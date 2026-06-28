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
return unit. NativeTiledScanDSL {
  fn. tiled_scan_rows { dst [ptr [i32]], xs [ptr [i32]], h [index], w [index], n [index] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (xs)(n), readonly(xs),
      disjoint (dst)(xs),
    },

    lln.loop { i, j } [lln.tiled_nd { axes = { { 0, h }, { 0, w } }, tiles = { 2, 2 } }] {
      lln.scan. acc [lln.i32] {
        init = 0,
        by = lln.add,
        axis = 2,
        step = xs[i * w + j],
        into = dst[i * w + j],
      },
    },
  },
}
]=]

local session = lalin.use { scope = 'env' }
local decl = assert(session:loadstring(source, 'test_luajit_artifact_tiled_scan_dsl.lua'))()
local plan = lalin.plan_luajit_artifact(decl, {
    name = 'NativeTiledScanDSL',
    stem = 'test_luajit_artifact_tiled_scan_dsl',
})
local bank = assert(plan.backend.build_mc_bank(plan.artifacts, { stem = 'test_luajit_artifact_tiled_scan_dsl' }))
local artifact = lalin.emit_luajit_plan_artifact(plan, {
    path = 'target/test_artifacts/test_luajit_artifact_tiled_scan_dsl.lua',
    name = 'NativeTiledScanDSL',
    stem = 'test_luajit_artifact_tiled_scan_dsl',
    mc_bank = bank,
})

assert(#artifact.artifacts == 1, 'tiled_nd scan source should select one native stencil artifact')
local desc = artifact.artifacts[1].instance.descriptor
assert(tostring(require('lalin.pvm').classof(desc.producer.shape)):match('StencilProduceTiledND'), 'source tiled scan should preserve TiledND producer')
assert(tostring(require('lalin.pvm').classof(desc.sink)):match('StencilSinkScan'), 'source tiled scan should preserve Scan sink')

local loaded = assert(loadfile(artifact.path))()
local src = ffi.new('int32_t[6]', { 1, 2, 3, 4, 5, 6 })
local dst = ffi.new('int32_t[6]')
loaded.tiled_scan_rows(dst, src, 2, 3, 6)
assert(dst[0] == 1 and dst[1] == 3 and dst[2] == 6 and dst[3] == 4 and dst[4] == 9 and dst[5] == 15, 'native lln.tiled_nd axis scan output')

io.write('test_luajit_artifact_tiled_scan_dsl: ok\n')
