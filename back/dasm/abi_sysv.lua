-- abi_sysv.lua — System V AMD64 ABI configuration
--
-- Defines parameter registers, return register, caller/callee-saved sets,
-- and stack-frame layout conventions.

local abi = {}

-- ── parameter passing ─────────────────────────────────────────────────

-- Integer/pointer parameter registers (in order)
abi.param_regs = {7, 6, 2, 1, 8, 9}  -- rdi, rsi, rdx, rcx, r8, r9

-- Float parameter registers (SSE)
abi.float_param_regs = {0, 1, 2, 3, 4, 5, 6, 7}  -- xmm0-xmm7

-- ── return values ─────────────────────────────────────────────────────

abi.return_reg  = 0   -- rax (integer/pointer)
abi.float_return_reg = 0  -- xmm0 (float)

-- ── register classification ───────────────────────────────────────────

-- Registers that the callee can freely clobber
abi.caller_saved = {0, 1, 2, 6, 7, 8, 9, 10, 11}
-- rax, rcx, rdx, rsi, rdi, r8, r9, r10, r11

-- Registers the callee must preserve (save/restore in prologue/epilogue)
abi.callee_saved = {3, 12, 13, 14, 15}
-- rbx, r12, r13, r14, r15  (rbp handled separately via frame pointer)

-- ── stack frame ───────────────────────────────────────────────────────

-- SysV does not require shadow space
abi.shadow_space = 0

-- Stack must be 16-byte aligned before call
abi.stack_alignment = 16

-- ── register names (for debugging/dumps) ──────────────────────────────

abi.reg_names = {
    [0]  = "rax",  [1]  = "rcx",  [2]  = "rdx",  [3]  = "rbx",
    [4]  = "rsp",  [5]  = "rbp",  [6]  = "rsi",  [7]  = "rdi",
    [8]  = "r8",   [9]  = "r9",   [10] = "r10",  [11] = "r11",
    [12] = "r12",  [13] = "r13",  [14] = "r14",  [15] = "r15",
}

-- ── helpers ───────────────────────────────────────────────────────────

function abi.reg_name(r)
    return abi.reg_names[r] or ("r" .. tostring(r))
end

-- Check if a register is callee-saved
function abi.is_callee_saved(r)
    for _, cs in ipairs(abi.callee_saved) do
        if cs == r then return true end
    end
    return false
end

-- Check if a register is caller-saved
function abi.is_caller_saved(r)
    for _, cs in ipairs(abi.caller_saved) do
        if cs == r then return true end
    end
    return false
end

-- Compute aligned offset (up to alignment boundary)
function abi.align_up(offset, align)
    align = align or abi.stack_alignment
    return math.floor((offset + align - 1) / align) * align
end

return abi
