package.path = table.concat({
    './?.lua',
    './?/init.lua',
    './lua/?.lua',
    './lua/?/init.lua',
    package.path,
}, ';')

local lalin = require('lalin')

local source = [=[
return unit. NativeNDScanMissingAxisDSL {
  fn. nd_scan { dst [ptr [i32]], xs [ptr [i32]], h [index], w [index], n [index] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (xs)(n), readonly(xs),
      disjoint (dst)(xs),
    },

    lln.loop { i, j } [lln.range_nd { { 0, h }, { 0, w } }] {
      lln.scan. acc [lln.i32] {
        init = 0,
        by = lln.add,
        step = xs[i * w + j],
        into = dst[i * w + j],
      },
    },
  },
}
]=]

local session = lalin.use { scope = 'env' }
local ok, err = pcall(function()
    local decl = assert(session:loadstring(source, 'test_luajit_artifact_nd_scan_axis_reject.lua'))()
    return lalin.emit_luajit_artifact(decl, {
        path = 'target/test_artifacts/test_luajit_artifact_nd_scan_axis_reject.lua',
        name = 'NativeNDScanMissingAxisDSL',
        stem = 'test_luajit_artifact_nd_scan_axis_reject',
    })
end)

assert(not ok and tostring(err):match('requires axis'), 'lln.range_nd scan should reject without explicit axis')

io.write('test_luajit_artifact_nd_scan_axis_reject: ok\n')
