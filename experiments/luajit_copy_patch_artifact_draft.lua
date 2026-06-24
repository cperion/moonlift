-- EXPERIMENTAL ARCHITECTURE PROBE ONLY.
--
-- This file is intentionally not production backend code. It exists to test the
-- LuaJIT copy-patch artifact model before the real ASDL/runtime implementation
-- is wired:
--
--   descriptor fixture
--     -> runtime facts
--     -> self-contained Lua source artifact
--     -> load(...)
--     -> lazy native blob install
--     -> hot reused-param wrapper
--
-- The native bytes below are a tiny x86_64 SysV fixture, not a real stencil-bank
-- output. The real backend must consume MoonStencil/MoonExec/MoonLuaJIT ASDL
-- facts and copy bytes from a C-backend-produced stencil bank.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")

if ffi.os ~= "Linux" or ffi.arch ~= "x64" then
  error("this draft fixture only runs on Linux x64 LuaJIT")
end

local function bytes_literal(bytes)
  local parts = {}
  for i = 1, #bytes do
    parts[#parts + 1] = string.format("0x%02x", bytes:byte(i))
  end
  return "string.char(" .. table.concat(parts, ", ") .. ")"
end

local function quote(s)
  return string.format("%q", s)
end

local descriptor_fixture = {
  tag = "StencilDescriptorFixture",
  vocab = "map_reduce",
  domain = "range1d",
  skeleton = "reduce",
  operator = "add_param_i32",
  result_ty = "i32",
  note = "fixture only: models one native island called by a generated Lua residual wrapper",
}

local runtime_facts = {
  blob = {
    id = "blob.add_param_i32.x64_sysv",
    symbol = "ml_draft_add_param_i32",
    sig = "int32_t (*)(DraftParam*)",
    install = "lazy",
  },
  param = {
    id = "DraftParam",
    ctype = "typedef struct { int32_t a; int32_t b; } DraftParam;",
    lifetime = "call_only",
    reuse = "single",
  },
  wrapper = {
    name = "add",
    shape = "param_call",
    fixed_arity = true,
    hot_runtime_lookup_allowed = false,
    hot_allocation_allowed = false,
    reentrant = false,
    native_retains_param = false,
  },
}

-- x86_64 SysV:
--   int32_t f(DraftParam *p) { return p->a + p->b; }
-- bytes:
--   mov eax, dword ptr [rdi]
--   add eax, dword ptr [rdi + 4]
--   ret
local native_blob = string.char(0x8b, 0x07, 0x03, 0x47, 0x04, 0xc3)

local function emit_artifact_source(descriptor, facts, blob)
  return table.concat({
    "-- GENERATED DRAFT ARTIFACT. Experimental copy-patch architecture probe only.\n",
    "local ffi = require('ffi')\n",
    "if ffi.os ~= 'Linux' or ffi.arch ~= 'x64' then error('draft artifact only supports Linux x64') end\n",
    "ffi.cdef[[\n",
    "typedef int int32_t;\n",
    "typedef unsigned long size_t;\n",
    "typedef long intptr_t;\n",
    "typedef struct { int32_t a; int32_t b; } DraftParam;\n",
    "void *mmap(void *addr, size_t length, int prot, int flags, int fd, intptr_t offset);\n",
    "]]\n",
    "local PROT_READ, PROT_WRITE, PROT_EXEC = 1, 2, 4\n",
    "local MAP_PRIVATE, MAP_ANON = 2, 32\n",
    "local MAP_FAILED = ffi.cast('void *', -1)\n",
    "local descriptor = { tag = ", quote(descriptor.tag), ", vocab = ", quote(descriptor.vocab), ", skeleton = ", quote(descriptor.skeleton), " }\n",
    "local runtime = { blob_id = ", quote(facts.blob.id), ", wrapper = ", quote(facts.wrapper.name), ", reuse = ", quote(facts.param.reuse), " }\n",
    "local blob = ", bytes_literal(blob), "\n",
    "local Param = ffi.typeof('DraftParam')\n",
    "local param = Param()\n",
    "local fn\n",
    "local function install_blob()\n",
    "  local mem = ffi.C.mmap(nil, #blob, bit.bor(PROT_READ, PROT_WRITE, PROT_EXEC), bit.bor(MAP_PRIVATE, MAP_ANON), -1, 0)\n",
    "  if mem == MAP_FAILED then error('mmap failed while installing draft blob') end\n",
    "  ffi.copy(mem, blob, #blob)\n",
    "  fn = ffi.cast('int32_t (*)(DraftParam*)', mem)\n",
    "  return fn\n",
    "end\n",
    "local hot\n",
    "local function hot_impl(a, b)\n",
    "  param.a = a\n",
    "  param.b = b\n",
    "  return tonumber(fn(param))\n",
    "end\n",
    "local function cold(a, b)\n",
    "  install_blob()\n",
    "  hot = hot_impl\n",
    "  return hot_impl(a, b)\n",
    "end\n",
    "hot = cold\n",
    "local M = { descriptor = descriptor, runtime = runtime }\n",
    "function M.add(a, b) return hot(a, b) end\n",
    "function M.selftest() return M.add(20, 22) end\n",
    "return M\n",
  })
end

local source = emit_artifact_source(descriptor_fixture, runtime_facts, native_blob)
local chunk = assert(load(source, "draft_copy_patch_artifact"))
local module = chunk()
local got = module.selftest()
assert(got == 42, "selftest expected 42, got " .. tostring(got))

local N = tonumber(arg[1]) or 2000000
local sum = 0
local t0 = os.clock()
for i = 1, N do
  sum = sum + module.add(i, 1)
end
local dt = os.clock() - t0

print("draft artifact selftest", got)
print("descriptor", module.descriptor.vocab, module.descriptor.skeleton)
print("runtime", module.runtime.wrapper, module.runtime.reuse)
print(string.format("hot wrapper %.6f result=%d", dt, sum % 1000000))
