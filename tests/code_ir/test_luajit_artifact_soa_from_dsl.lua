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
return unit. SoARegression {
  struct. PairSoA {
    left [i32],
    right [i32],
    total [i32],
  },

  fn. soa_zip_add { dst [ptr [i32]], left [ptr [i32]], right [ptr [i32]], n [i32] } [void] {
    requires {
      bounds(dst, n), writeonly(dst), soa_component(dst, PairSoA, "total", 2),
      bounds(left, n), readonly(left), soa_component(left, PairSoA, "left", 0),
      bounds(right, n), readonly(right), soa_component(right, PairSoA, "right", 1),
      disjoint(dst, left), disjoint(dst, right), disjoint(left, right),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      store (dst[i], left[i] + right[i]),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. soa_zip_sum { left [ptr [i32]], right [ptr [i32]], n [i32] } [i32] {
    requires {
      bounds(left, n), readonly(left), soa_component(left, PairSoA, "left", 0),
      bounds(right, n), readonly(right), soa_component(right, PairSoA, "right", 1),
      disjoint(left, right),
    },

    entry. start {} { jump. loop { i = 0, acc = 0 }, },

    block. loop { i [i32], acc [i32] } {
      when (i :lt (n)) {
        jump. body { i = i, acc = acc },
      },

      jump. done { acc = acc },
    },

    block. body { i [i32], acc [i32] } {
      jump. loop { i = i + 1, acc = acc + (left[i] + right[i]) },
    },

    block. done { acc [i32] } {
      ret (acc),
    },
  },
}
]=]

local session = lalin.use { scope = 'env' }
local decl = assert(session:loadstring(source, 'test_luajit_artifact_soa_from_dsl.lua'))()
local artifact = lalin.emit_luajit_artifact(decl, {
    path = 'target/test_artifacts/test_luajit_artifact_soa_from_dsl.lua',
    name = 'SoARegression',
    stem = 'test_luajit_artifact_soa_from_dsl',
})

assert(artifact.kind == 'LuaJITSourceArtifact')
assert(#artifact.artifacts == 2, 'expected selected SoA zip_map and zip_reduce artifacts')
assert(not artifact.source:match('%.left'), 'SoA component buffers must not emit AoS field loads')

local function access_named(desc, name)
    for _, access in ipairs(desc.accesses or {}) do
        if access.name == name then return access end
    end
    error('missing descriptor access ' .. tostring(name))
end

local function assert_soa(access, field_name, component_index)
    local top = access.topology
    assert(tostring(pvm.classof(top)) == 'Class(LalinStencil.StencilTopologySoAComponent)', access.name .. ' should use SoA topology')
    assert(top.field_name == field_name, access.name .. ' should keep SoA field')
    assert(top.component_index == component_index, access.name .. ' should keep SoA component index')
    assert(tostring(top.record_ty):match('PairSoA'), access.name .. ' should keep logical record type')
end

for _, selected in ipairs(artifact.artifacts) do
    local desc = selected.instance.descriptor
    local descriptor_kind = tostring(pvm.classof(desc)):match('Class%((.-)%)')
    local expr_kind = tostring(pvm.classof(desc.expr)):match('Class%((.-)%)')
    if descriptor_kind == 'LalinStencil.StencilDescriptorApply' and expr_kind == 'LalinStencil.StencilApplyBinary' then
        assert_soa(access_named(desc, 'dst'), 'total', 2)
        assert_soa(access_named(desc, 'lhs'), 'left', 0)
        assert_soa(access_named(desc, 'rhs'), 'right', 1)
    elseif descriptor_kind == 'LalinStencil.StencilDescriptorReduce' and expr_kind == 'LalinStencil.StencilApplyBinary' then
        assert_soa(access_named(desc, 'lhs'), 'left', 0)
        assert_soa(access_named(desc, 'rhs'), 'right', 1)
    else
        error('unexpected SoA artifact descriptor ' .. tostring(pvm.classof(desc)))
    end
end

local loaded = assert(loadfile(artifact.path))()
local left = ffi.new('int32_t[5]', { 1, -2, 5, 0, 3 })
local right = ffi.new('int32_t[5]', { 10, 20, -5, 7, 4 })
local out = ffi.new('int32_t[5]')

loaded.soa_zip_add(out, left, right, 5)
assert(out[0] == 11 and out[1] == 18 and out[2] == 0 and out[3] == 7 and out[4] == 7, 'DSL SoA zip map')
assert(loaded.soa_zip_sum(left, right, 5) == 43, 'DSL SoA zip reduce')

io.write('test_luajit_artifact_soa_from_dsl: ok\n')
