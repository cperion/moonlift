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
return unit. NativeWindowNeighborDSL {
  fn. prev_clamp { dst [ptr [i32]], xs [ptr [i32]], n [index] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (xs)(n), readonly(xs),
      disjoint (dst)(xs),
    },

    lln.loop { i } [lln.window_nd { axes = { { 0, n } }, windows = { { 1, 1, boundary = "clamp" } } }] {
      set (dst[i])(xs[i - 1]),
    },
  },
}
]=]

local session = lalin.use { scope = 'env' }
local decl = assert(session:loadstring(source, 'test_luajit_artifact_window_neighbor_dsl.lua'))()
local artifact = lalin.emit_luajit_artifact(decl, {
    path = 'target/test_artifacts/test_luajit_artifact_window_neighbor_dsl.lua',
    name = 'NativeWindowNeighborDSL',
    stem = 'test_luajit_artifact_window_neighbor_dsl',
})

assert(#artifact.artifacts == 1, 'window neighbor source should select one native stencil artifact')
local desc = artifact.artifacts[1].instance.descriptor
assert(tostring(pvm.classof(desc.producer.shape)):match('StencilProduceWindowND'), 'source window neighbor should preserve WindowND producer')
assert(tostring(pvm.classof(desc.body.expr)):match('StencilApplyWindowInput'), 'source neighbor access should lower to StencilApplyWindowInput')

local loaded = assert(loadfile(artifact.path))()
local src = ffi.new('int32_t[6]', { 1, 2, 3, 4, 5, 6 })
local dst = ffi.new('int32_t[6]')
loaded.prev_clamp(dst, src, 6)
assert(dst[0] == 1 and dst[1] == 1 and dst[2] == 2 and dst[3] == 3 and dst[4] == 4 and dst[5] == 5, 'native lln.window_nd neighbor output')

io.write('test_luajit_artifact_window_neighbor_dsl: ok\n')
