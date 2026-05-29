-- Lua Interpreter VM — Proto validation trust boundary (Lua 5.5)

local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")

local I = {}
for k, v in pairs(const.Err) do I["ERR_" .. k] = moon.int(v) end
for k, v in pairs(const.Op) do I["OP_" .. k] = moon.int(v) end

-- validate_proto: verify Proto is safe to execute. This is the canonical
-- interpreter/JIT trust boundary; opcode handlers may assume these facts.
local validate_proto = host.region(I) [[
region validate_proto(L: ptr(LuaThread), p: ptr(Proto);
                      ok: cont(), invalid: cont(code: i32), oom: cont())
entry start()
    if p == nil then
        jump invalid(code = @{ERR_RUNTIME})
    end
    if p.maxstack == 0 then
        jump invalid(code = @{ERR_RUNTIME})
    end
    if p.code_len > 0 and p.code == nil then
        jump invalid(code = @{ERR_RUNTIME})
    end
    if p.constants_len > 0 and p.constants == nil then
        jump invalid(code = @{ERR_RUNTIME})
    end
    if p.children_len > 0 and p.children == nil then
        jump invalid(code = @{ERR_RUNTIME})
    end
    if p.code_len == 0 then
        jump ok()
    end
    jump loop(pc = as(index, 0), prev_op = as(u16, 65535))
end
block loop(pc: index, prev_op: u16)
    if pc >= p.code_len then
        jump ok()
    end
    let word: u32 = p.code[pc].word
    let op: u16 = as(u16, word & 127)
    let a: u16 = as(u16, (word >> 7) & 255)
    let k: u8 = as(u8, (word >> 15) & 1)
    let b: u16 = as(u16, (word >> 16) & 255)
    let c: u16 = as(u16, (word >> 24) & 255)
    let bx: u32 = (word >> 15) & 131071
    let sbx: i32 = as(i32, bx) - 65535
    if op > @{OP_EXTRAARG} then
        jump invalid(code = @{ERR_BAD_OPCODE})
    end
    if a >= p.maxstack then
        jump invalid(code = @{ERR_RUNTIME})
    end

    -- Pair-only opcodes must be paired with their producers.
    if op == @{OP_EXTRAARG} then
        if prev_op ~= @{OP_LOADKX} then
            jump invalid(code = @{ERR_RUNTIME})
        end
    end
    if op == @{OP_MMBIN} then
        if prev_op ~= @{OP_ADD} and prev_op ~= @{OP_SUB} and prev_op ~= @{OP_MUL} and prev_op ~= @{OP_MOD} and prev_op ~= @{OP_POW} and prev_op ~= @{OP_DIV} and prev_op ~= @{OP_IDIV} and prev_op ~= @{OP_BAND} and prev_op ~= @{OP_BOR} and prev_op ~= @{OP_BXOR} and prev_op ~= @{OP_SHL} and prev_op ~= @{OP_SHR} then
            jump invalid(code = @{ERR_RUNTIME})
        end
    end
    if op == @{OP_MMBINI} then
        if prev_op ~= @{OP_ADDI} and prev_op ~= @{OP_SHLI} and prev_op ~= @{OP_SHRI} then
            jump invalid(code = @{ERR_RUNTIME})
        end
    end
    if op == @{OP_MMBINK} then
        if prev_op ~= @{OP_ADDK} and prev_op ~= @{OP_SUBK} and prev_op ~= @{OP_MULK} and prev_op ~= @{OP_MODK} and prev_op ~= @{OP_POWK} and prev_op ~= @{OP_DIVK} and prev_op ~= @{OP_IDIVK} and prev_op ~= @{OP_BANDK} and prev_op ~= @{OP_BORK} and prev_op ~= @{OP_BXORK} then
            jump invalid(code = @{ERR_RUNTIME})
        end
    end

    -- A-register is universal above; check B/C for common register families.
    if op == @{OP_MOVE} or op == @{OP_GETTABLE} or op == @{OP_GETI} or op == @{OP_GETFIELD} or op == @{OP_SELF} or op == @{OP_ADDI} or op == @{OP_SHLI} or op == @{OP_SHRI} or op == @{OP_UNM} or op == @{OP_BNOT} or op == @{OP_NOT} or op == @{OP_LEN} or op == @{OP_TESTSET} then
        if b >= p.maxstack then
            jump invalid(code = @{ERR_RUNTIME})
        end
    end
    if op == @{OP_ADD} or op == @{OP_SUB} or op == @{OP_MUL} or op == @{OP_MOD} or op == @{OP_POW} or op == @{OP_DIV} or op == @{OP_IDIV} or op == @{OP_BAND} or op == @{OP_BOR} or op == @{OP_BXOR} or op == @{OP_SHL} or op == @{OP_SHR} or op == @{OP_EQ} or op == @{OP_LT} or op == @{OP_LE} or op == @{OP_SETTABLE} then
        if b >= p.maxstack then
            jump invalid(code = @{ERR_RUNTIME})
        end
        if c >= p.maxstack then
            jump invalid(code = @{ERR_RUNTIME})
        end
    end

    -- Constants and child-prototype bounds.
    if op == @{OP_LOADK} then
        if as(index, bx) >= p.constants_len then
            jump invalid(code = @{ERR_RUNTIME})
        end
    end
    if op == @{OP_LOADKX} then
        if pc + 1 >= p.code_len then
            jump invalid(code = @{ERR_RUNTIME})
        end
        let extra_word: u32 = p.code[pc + 1].word
        let extra_op: u16 = as(u16, extra_word & 127)
        let extra_bx: u32 = (extra_word >> 15) & 131071
        if extra_op ~= @{OP_EXTRAARG} then
            jump invalid(code = @{ERR_RUNTIME})
        end
        if as(index, extra_bx) >= p.constants_len then
            jump invalid(code = @{ERR_RUNTIME})
        end
    end
    if op == @{OP_ADDK} or op == @{OP_SUBK} or op == @{OP_MULK} or op == @{OP_MODK} or op == @{OP_POWK} or op == @{OP_DIVK} or op == @{OP_IDIVK} or op == @{OP_BANDK} or op == @{OP_BORK} or op == @{OP_BXORK} or op == @{OP_EQK} or op == @{OP_GETFIELD} or op == @{OP_SETFIELD} then
        if as(index, c) >= p.constants_len then
            jump invalid(code = @{ERR_RUNTIME})
        end
    end
    if op == @{OP_CLOSURE} then
        if as(index, bx) >= p.children_len then
            jump invalid(code = @{ERR_RUNTIME})
        end
    end

    -- Arithmetic fast paths rely on adjacent metamethod fallback opcodes.
    if op == @{OP_ADD} or op == @{OP_SUB} or op == @{OP_MUL} or op == @{OP_MOD} or op == @{OP_POW} or op == @{OP_DIV} or op == @{OP_IDIV} or op == @{OP_BAND} or op == @{OP_BOR} or op == @{OP_BXOR} or op == @{OP_SHL} or op == @{OP_SHR} then
        if pc + 1 >= p.code_len then
            jump invalid(code = @{ERR_RUNTIME})
        end
        let next_word: u32 = p.code[pc + 1].word
        let next_op: u16 = as(u16, next_word & 127)
        if next_op ~= @{OP_MMBIN} then
            jump invalid(code = @{ERR_RUNTIME})
        end
    end
    if op == @{OP_ADDI} or op == @{OP_SHLI} or op == @{OP_SHRI} then
        if pc + 1 >= p.code_len then
            jump invalid(code = @{ERR_RUNTIME})
        end
        let next_word_i: u32 = p.code[pc + 1].word
        let next_op_i: u16 = as(u16, next_word_i & 127)
        if next_op_i ~= @{OP_MMBINI} then
            jump invalid(code = @{ERR_RUNTIME})
        end
    end
    if op == @{OP_ADDK} or op == @{OP_SUBK} or op == @{OP_MULK} or op == @{OP_MODK} or op == @{OP_POWK} or op == @{OP_DIVK} or op == @{OP_IDIVK} or op == @{OP_BANDK} or op == @{OP_BORK} or op == @{OP_BXORK} then
        if pc + 1 >= p.code_len then
            jump invalid(code = @{ERR_RUNTIME})
        end
        let next_word_k: u32 = p.code[pc + 1].word
        let next_op_k: u16 = as(u16, next_word_k & 127)
        if next_op_k ~= @{OP_MMBINK} then
            jump invalid(code = @{ERR_RUNTIME})
        end
    end

    -- Jump and loop targets/windows.
    if op == @{OP_JMP} or op == @{OP_FORLOOP} or op == @{OP_FORPREP} or op == @{OP_TFORPREP} then
        let target: i32 = as(i32, pc) + sbx
        if target < 0 or as(index, target) >= p.code_len then
            jump invalid(code = @{ERR_RUNTIME})
        end
    end
    if op == @{OP_FORLOOP} or op == @{OP_FORPREP} then
        let end_reg: u32 = as(u32, a) + 3
        if end_reg >= as(u32, p.maxstack) then
            jump invalid(code = @{ERR_RUNTIME})
        end
    end
    if op == @{OP_TFORCALL} or op == @{OP_TFORLOOP} then
        let end_tfor: u32 = as(u32, a) + 3
        if end_tfor >= as(u32, p.maxstack) then
            jump invalid(code = @{ERR_RUNTIME})
        end
    end

    -- Call/return register windows.
    if op == @{OP_CALL} or op == @{OP_TAILCALL} then
        if b ~= 0 then
            let arg_end: u32 = as(u32, a) + as(u32, b) - 1
            if arg_end >= as(u32, p.maxstack) then
                jump invalid(code = @{ERR_RUNTIME})
            end
        end
        if c > 1 then
            let res_end: u32 = as(u32, a) + as(u32, c) - 2
            if res_end >= as(u32, p.maxstack) then
                jump invalid(code = @{ERR_RUNTIME})
            end
        end
    end
    if op == @{OP_RETURN} then
        if b > 1 then
            let ret_end: u32 = as(u32, a) + as(u32, b) - 2
            if ret_end >= as(u32, p.maxstack) then
                jump invalid(code = @{ERR_RUNTIME})
            end
        end
    end

    jump loop(pc = pc + 1, prev_op = op)
end
end
]]

return {
    validate_proto = validate_proto,
}
