-- fragment_abi_x64.lua -- x86-64 SysV SpongeJIT native fragment ABI v1.

local M = {}

M.ID = "x86_64_sysv_spon_v1"

function M.desc()
  return {
    id = M.ID,
    arch = "x86_64",
    calling_convention = "sysv",
    ctx = { kind = "reg", reg = "rdi", value_type = "Ptr" },
    scratch_gprs = { "rax", "rcx", "rdx", "r8", "r9", "r10", "r11" },
    value_gprs = { "rax", "r10", "r11" },
    clobbers = { "rax", "rcx", "rdx", "r8", "r9", "r10", "r11", "flags" },
    stack_alignment = 16,
  }
end

return M
