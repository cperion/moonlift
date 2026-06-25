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
return unit. VectorRelocRegression {
  struct. PairSoA {
    left [i32],
    right [i32],
    total [i32],
  },

  fn. soa_zip_add { total [ptr [i32]], left [ptr [i32]], right [ptr [i32]], n [i32] } [void] {
    requires {
      bounds(total, n), writeonly(total), soa_component(total, PairSoA, "total", 2),
      bounds(left, n), readonly(left), soa_component(left, PairSoA, "left", 0),
      bounds(right, n), readonly(right), soa_component(right, PairSoA, "right", 1),
      disjoint(total, left), disjoint(total, right), disjoint(left, right),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      store (total[i], left[i] + right[i]),
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
local decl = assert(session:loadstring(source, 'test_stencil_bank_vector_local_reloc.lua'))()
local artifact = lalin.emit_luajit_artifact(decl, {
    path = 'target/test_artifacts/test_stencil_bank_vector_local_reloc.lua',
    name = 'VectorRelocRegression',
    stem = 'test_stencil_bank_vector_local_reloc',
    cflags = '-std=c99 -O3 -march=native -ffunction-sections -fno-pic -fno-stack-protector -fno-asynchronous-unwind-tables -fno-unwind-tables -c',
})

assert(artifact.bank ~= nil, 'expected emitted artifact to keep binary stencil bank')
assert(#artifact.bank.entries == 2, 'expected zip_map and zip_reduce bank entries')

local local_const_pool = string.char(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15)
local saw_materialized_local = false
for _, entry in ipairs(artifact.bank.entries or {}) do
    if entry.binary:find(local_const_pool, 1, true) then saw_materialized_local = true end
    for _, patch in ipairs(entry.patches or {}) do
        assert(not tostring(patch.symbol or ''):match('^%.LC'), 'local constant-pool relocation should be materialized into the binary blob, not left as runtime patch')
    end
end

local loaded = assert(loadfile(artifact.path))()
local n = 257
local left = ffi.new('int32_t[?]', n)
local right = ffi.new('int32_t[?]', n)
local total = ffi.new('int32_t[?]', n)
local expected = 0
for i = 0, n - 1 do
    left[i] = (i % 97) - 48
    right[i] = (i % 53) + 3
    total[i] = 0
    expected = expected + left[i] + right[i]
end

loaded.soa_zip_add(total, left, right, n)
for i = 0, n - 1 do
    assert(total[i] == left[i] + right[i], 'vectorized local-reloc zip_map mismatch at ' .. tostring(i))
end
assert(loaded.soa_zip_sum(left, right, n) == expected, 'vectorized local-reloc zip_reduce mismatch')

-- Host compilers without a masked-tail vector path may not emit .LC constants,
-- but when they do the bank must fold them into the installed blob.
if saw_materialized_local then
    assert(artifact.source:match('string%.char'), 'emitted Lua artifact should contain embedded local section bytes')
end

io.write('lalin stencil_bank vector local reloc ok\n')
