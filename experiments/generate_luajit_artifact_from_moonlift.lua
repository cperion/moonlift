package.path = table.concat({
    './?.lua',
    './?/init.lua',
    './lua/?.lua',
    './lua/?/init.lua',
    package.path,
}, ';')

local ffi = require('ffi')
local moon = require('moonlift')

local source_path = arg[1] or 'target/artifacts/sum_i32_from_moonlift_dsl.source.lua'
local artifact_path = arg[2] or 'target/artifacts/sum_i32_from_moonlift_dsl.lua'

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function mkdir_parent(path)
    local dir = tostring(path):match('^(.*)/[^/]+$')
    if dir ~= nil and dir ~= '' then os.execute('mkdir -p ' .. shell_quote(dir)) end
end

local function write_file(path, source)
    mkdir_parent(path)
    local f = assert(io.open(path, 'wb'))
    f:write(source)
    f:close()
end

local source = [=[
return unit. CopyPatchDemo {
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
}
]=]

write_file(source_path, source)

local session = moon.use { scope = 'env' }
local decl = assert(session:loadstring(source, source_path))()
local artifact = moon.emit_luajit_artifact(decl, {
    path = artifact_path,
    name = 'CopyPatchDemo',
    stem = 'sum_i32_from_moonlift_dsl',
})

assert(#artifact.artifacts > 0, 'expected at least one selected stencil artifact')
assert(artifact.source:match('__ml_check_stencil_target'), 'generated artifact is missing target guard')

local loaded = assert(loadfile(artifact_path))()
local arr = ffi.new('int32_t[5]', { 1, 2, 3, 4, 5 })
local got = loaded.sum_i32(arr, 5)
assert(got == 15, 'expected generated artifact sum_i32 to return 15, got ' .. tostring(got))

io.write('generated ', artifact_path, ' from ', source_path, '\n')
io.write('sum_i32(1..5) = ', tostring(got), '\n')
