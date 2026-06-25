-- EXPERIMENTAL PATCH PROBE ONLY.
--
-- This tests lalin.stencil_bank.install_binary_stencil, not production stencil
-- extraction. The bytes are a tiny x86_64 SysV binary stencil with one immediate
-- hole:
--
--   int32_t f(DraftParam *p) { return p->a + p->b + PATCHED_IMM32; }
--
-- Real bank entries must be produced from object-code relocation records by the
-- stencil-library builder. This probe only validates copy + patch + install + call.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")

if ffi.os ~= "Linux" or ffi.arch ~= "x64" then
  error("this patch probe only runs on Linux x64 LuaJIT")
end

ffi.cdef[[
typedef int int32_t;
typedef struct { int32_t a; int32_t b; } DraftParam;
]]

local T = pvm.context()
Schema(T)
local Bank = require("lalin.stencil_bank")(T)

local entry = {
  key = "draft.add_param_i32_plus_imm32",
  c_signature = "int32_t (*)(DraftParam *)",
  -- mov eax, [rdi]
  -- add eax, [rdi + 4]
  -- add eax, imm32
  -- ret
  binary = string.char(0x8b, 0x07, 0x03, 0x47, 0x04, 0x05, 0x00, 0x00, 0x00, 0x00, 0xc3),
  patches = {
    { kind = "abs32", offset = 6, ordinal = 1 },
  },
}

local installed = Bank.install_binary_stencil(entry, { [1] = 10 })
local p = ffi.new("DraftParam", { a = 20, b = 12 })
local got = tonumber(installed.fn(p))
assert(got == 42, "expected patched result 42, got " .. tostring(got))

local installed2 = Bank.install_binary_stencil(entry, { [1] = -7 })
p.a = 20
p.b = 12
local got2 = tonumber(installed2.fn(p))
assert(got2 == 25, "expected patched result 25, got " .. tostring(got2))

print("stencil_bank patch probe ok", got, got2)
