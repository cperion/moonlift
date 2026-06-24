package.path = table.concat({
    './?.lua',
    './?/init.lua',
    './lua/?.lua',
    './lua/?/init.lua',
    package.path,
}, ';')

local ffi = require('ffi')
local moon = require('moonlift')

local source = [=[
return unit. CopyPatchRegression {
  fn. sum_i32 { xs [ptr [i32]], n [i32] } [i32] {
    requires { bounds(xs, n), readonly(xs) },

    entry. start {} { jump. loop { i = 0, acc = 0 }, },

    block. loop { i [i32], acc [i32] } {
      when (i :lt (n)) {
        jump. body { i = i, acc = acc },
      },

      jump. done { acc = acc },
    },

    block. body { i [i32], acc [i32] } {
      jump. loop { i = i + 1, acc = acc + xs[i] },
    },

    block. done { acc [i32] } {
      ret (acc),
    },
  },

  fn. copy_i32 { dst [ptr [i32]], src [ptr [i32]], n [i32] } [void] {
    requires {
      bounds(dst, n), writeonly(dst),
      bounds(src, n), readonly(src),
      disjoint(dst, src),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      store (dst[i], src[i]),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. fill_i32 { dst [ptr [i32]], n [i32], value [i32] } [void] {
    requires { bounds(dst, n), writeonly(dst) },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      store (dst[i], value),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. map_neg_i32 { dst [ptr [i32]], src [ptr [i32]], n [i32] } [void] {
    requires {
      bounds(dst, n), writeonly(dst),
      bounds(src, n), readonly(src),
      disjoint(dst, src),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      store (dst[i], -src[i]),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. zip_add_i32 { dst [ptr [i32]], lhs [ptr [i32]], rhs [ptr [i32]], n [i32] } [void] {
    requires {
      bounds(dst, n), writeonly(dst),
      bounds(lhs, n), readonly(lhs),
      bounds(rhs, n), readonly(rhs),
      disjoint(dst, lhs), disjoint(dst, rhs), disjoint(lhs, rhs),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      store (dst[i], lhs[i] + rhs[i]),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },
}
]=]

local session = moon.use { scope = 'env' }
local decl = assert(session:loadstring(source, 'test_luajit_artifact_from_dsl.lua'))()
local artifact = moon.emit_luajit_artifact(decl, {
    path = 'target/test_artifacts/test_luajit_artifact_from_dsl.lua',
    name = 'CopyPatchRegression',
    stem = 'test_luajit_artifact_from_dsl',
})

assert(artifact.kind == 'LuaJITSourceArtifact')
assert(#artifact.artifacts == 5, 'expected selected stencil artifact for each DSL loop')
assert(artifact.source:match('__ml_check_stencil_target'), 'expected generated target guard')

local expected_vocab = {
    ['MoonStencil.StencilReduce'] = 'reduce',
    ['MoonStencil.StencilCopy'] = 'copy',
    ['MoonStencil.StencilFill'] = 'fill',
    ['MoonStencil.StencilMap'] = 'map',
    ['MoonStencil.StencilZipMap'] = 'zip_map',
}
local seen = {}
for _, selected in ipairs(artifact.artifacts) do
    local descriptor = selected.instance.descriptor
    local label = expected_vocab[tostring(descriptor.vocab)]
    assert(label ~= nil, 'unexpected selected stencil vocab ' .. tostring(descriptor.vocab))
    assert(seen[label] == nil, 'duplicate selected stencil artifact for ' .. label)
    assert(tostring(selected.instance.schedule):match('StencilScheduleAutoVector'), label .. ' should carry an auto-vector stencil schedule')
    seen[label] = true
end
for _, label in pairs(expected_vocab) do assert(seen[label], 'missing selected stencil artifact for ' .. label) end

local loaded = assert(loadfile(artifact.path))()
local arr = ffi.new('int32_t[6]', { 1, 2, 3, 4, 5, 6 })
assert(loaded.sum_i32(arr, 6) == 21)

local src = ffi.new('int32_t[6]', { 5, -3, 8, 0, 9, 2 })
local rhs = ffi.new('int32_t[6]', { 1, 10, -8, 7, 4, 11 })
local out = ffi.new('int32_t[6]')

loaded.copy_i32(out, src, 6)
for i = 0, 5 do assert(out[i] == src[i], 'copy mismatch at ' .. tostring(i)) end

loaded.fill_i32(out, 6, 77)
for i = 0, 5 do assert(out[i] == 77, 'fill mismatch at ' .. tostring(i)) end

loaded.map_neg_i32(out, src, 6)
for i = 0, 5 do assert(out[i] == -src[i], 'map mismatch at ' .. tostring(i)) end

loaded.zip_add_i32(out, src, rhs, 6)
for i = 0, 5 do assert(out[i] == src[i] + rhs[i], 'zip mismatch at ' .. tostring(i)) end

io.write('test_luajit_artifact_from_dsl: ok\n')
