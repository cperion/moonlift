-- Lua Interpreter VM — Proto validation trust boundary (Lua 5.5)

local lalin = require("lalin")
local host = require("lalin.host")
local const = require("experiments.lua_interpreter_vm.src.constants")
local bytecode = require("experiments.lua_interpreter_vm.src.bytecode")

local I = {}
for k, v in pairs(const.Err) do I["ERR_" .. k] = lalin.int(v) end
for k, v in pairs(const.Op) do I["OP_" .. k] = lalin.int(v) end
for k, v in pairs(const.TM) do I["TM_" .. k] = lalin.int(v) end

-- validate_proto: verify Proto is safe to execute. This is the canonical
-- interpreter/JIT trust boundary; opcode handlers may assume these facts.
local validate_proto = host.region(I) [[
region validate_proto(L: ptr(LuaThread), p: ptr(Proto);
                      ok | invalid(code: i32) | oom)
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
    let vb: u16 = as(u16, (word >> 16) & 63)
    let vc: u16 = as(u16, (word >> 22) & 1023)
    let bx: u32 = (word >> 15) & 131071
    let sbx: i32 = as(i32, bx) - 65535
    let ax: u32 = (word >> 7) & 33554431
    let sj: i32 = as(i32, ax) - 16777215
    let sc: i32 = as(i32, c) - 127
    if op > @{OP_EXTRAARG} then
        jump invalid(code = @{ERR_BAD_OPCODE})
    end
    if op ~= @{OP_JMP} and op ~= @{OP_EXTRAARG} then
        if a >= p.maxstack then
            jump invalid(code = @{ERR_RUNTIME})
        end
    end

    -- Pair-only opcodes must be paired with their producers.
    if op == @{OP_EXTRAARG} then
        if pc == 0 then
            jump invalid(code = @{ERR_RUNTIME})
        end
        let prev_word: u32 = p.code[pc - 1].word
        let prev_k: u8 = as(u8, (prev_word >> 15) & 1)
        if prev_op ~= @{OP_LOADKX} and prev_op ~= @{OP_NEWTABLE} and prev_op ~= @{OP_SETLIST} then
            jump invalid(code = @{ERR_RUNTIME})
        end
        if prev_op == @{OP_NEWTABLE} and prev_k == 0 then
            jump invalid(code = @{ERR_RUNTIME})
        end
        if prev_op == @{OP_SETLIST} and prev_k == 0 then
            jump invalid(code = @{ERR_RUNTIME})
        end
    end
    if op == @{OP_MMBIN} then
        if prev_op ~= @{OP_ADD} and prev_op ~= @{OP_SUB} and prev_op ~= @{OP_MUL} and prev_op ~= @{OP_MOD} and prev_op ~= @{OP_POW} and prev_op ~= @{OP_DIV} and prev_op ~= @{OP_IDIV} and prev_op ~= @{OP_BAND} and prev_op ~= @{OP_BOR} and prev_op ~= @{OP_BXOR} and prev_op ~= @{OP_SHL} and prev_op ~= @{OP_SHR} and prev_op ~= @{OP_UNM} and prev_op ~= @{OP_BNOT} then
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
    if op == @{OP_SETTABUP} or op == @{OP_SETFIELD} then
        if k == 0 and c >= p.maxstack then
            jump invalid(code = @{ERR_RUNTIME})
        end
        if k ~= 0 and as(index, c) >= p.constants_len then
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
        let extra_ax: u32 = (extra_word >> 7) & 33554431
        if extra_op ~= @{OP_EXTRAARG} then
            jump invalid(code = @{ERR_RUNTIME})
        end
        if as(index, extra_ax) >= p.constants_len then
            jump invalid(code = @{ERR_RUNTIME})
        end
    end
    if op == @{OP_NEWTABLE} then
        if k ~= 0 then
            if pc + 1 >= p.code_len then
                jump invalid(code = @{ERR_RUNTIME})
            end
            let nt_extra_word: u32 = p.code[pc + 1].word
            let nt_extra_op: u16 = as(u16, nt_extra_word & 127)
            if nt_extra_op ~= @{OP_EXTRAARG} then
                jump invalid(code = @{ERR_RUNTIME})
            end
        end
    end
    if op == @{OP_SETLIST} then
        if k ~= 0 then
            if pc + 1 >= p.code_len then
                jump invalid(code = @{ERR_RUNTIME})
            end
            let sl_extra_word: u32 = p.code[pc + 1].word
            let sl_extra_op: u16 = as(u16, sl_extra_word & 127)
            if sl_extra_op ~= @{OP_EXTRAARG} then
                jump invalid(code = @{ERR_RUNTIME})
            end
        end
        if vb ~= 0 then
            let list_end: u32 = as(u32, a) + as(u32, vb)
            if list_end >= as(u32, p.maxstack) then
                jump invalid(code = @{ERR_RUNTIME})
            end
        end
    end
    if op == @{OP_ADDK} or op == @{OP_SUBK} or op == @{OP_MULK} or op == @{OP_MODK} or op == @{OP_POWK} or op == @{OP_DIVK} or op == @{OP_IDIVK} or op == @{OP_BANDK} or op == @{OP_BORK} or op == @{OP_BXORK} or op == @{OP_EQK} or op == @{OP_GETFIELD} then
        if as(index, c) >= p.constants_len then
            jump invalid(code = @{ERR_RUNTIME})
        end
    end
    if op == @{OP_GETTABUP} then
        if as(index, b) >= p.upvals_len then jump invalid(code = @{ERR_RUNTIME}) end
        if as(index, c) >= p.constants_len then jump invalid(code = @{ERR_RUNTIME}) end
    end
    if op == @{OP_SETTABUP} then
        if as(index, a) >= p.upvals_len then jump invalid(code = @{ERR_RUNTIME}) end
        if as(index, b) >= p.constants_len then jump invalid(code = @{ERR_RUNTIME}) end
    end
    if op == @{OP_SETFIELD} then
        if as(index, b) >= p.constants_len then
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
        let next_a: u16 = as(u16, (next_word >> 7) & 255)
        let next_k: u8 = as(u8, (next_word >> 15) & 1)
        let next_b: u16 = as(u16, (next_word >> 16) & 255)
        let next_c: u16 = as(u16, (next_word >> 24) & 255)
        if next_op ~= @{OP_MMBIN} then
            jump invalid(code = @{ERR_RUNTIME})
        end
        if next_a ~= b or next_b ~= c or next_k ~= 0 then
            jump invalid(code = @{ERR_RUNTIME})
        end
        if op == @{OP_ADD} and next_c ~= @{TM_ADD} then jump invalid(code = @{ERR_RUNTIME}) end
        if op == @{OP_SUB} and next_c ~= @{TM_SUB} then jump invalid(code = @{ERR_RUNTIME}) end
        if op == @{OP_MUL} and next_c ~= @{TM_MUL} then jump invalid(code = @{ERR_RUNTIME}) end
        if op == @{OP_MOD} and next_c ~= @{TM_MOD} then jump invalid(code = @{ERR_RUNTIME}) end
        if op == @{OP_POW} and next_c ~= @{TM_POW} then jump invalid(code = @{ERR_RUNTIME}) end
        if op == @{OP_DIV} and next_c ~= @{TM_DIV} then jump invalid(code = @{ERR_RUNTIME}) end
        if op == @{OP_IDIV} and next_c ~= @{TM_IDIV} then jump invalid(code = @{ERR_RUNTIME}) end
        if op == @{OP_BAND} and next_c ~= @{TM_BAND} then jump invalid(code = @{ERR_RUNTIME}) end
        if op == @{OP_BOR} and next_c ~= @{TM_BOR} then jump invalid(code = @{ERR_RUNTIME}) end
        if op == @{OP_BXOR} and next_c ~= @{TM_BXOR} then jump invalid(code = @{ERR_RUNTIME}) end
        if op == @{OP_SHL} and next_c ~= @{TM_SHL} then jump invalid(code = @{ERR_RUNTIME}) end
        if op == @{OP_SHR} and next_c ~= @{TM_SHR} then jump invalid(code = @{ERR_RUNTIME}) end
    end
    if op == @{OP_UNM} or op == @{OP_BNOT} then
        if pc + 1 >= p.code_len then
            jump invalid(code = @{ERR_RUNTIME})
        end
        let un_next_word: u32 = p.code[pc + 1].word
        let un_next_op: u16 = as(u16, un_next_word & 127)
        let un_next_a: u16 = as(u16, (un_next_word >> 7) & 255)
        let un_next_b: u16 = as(u16, (un_next_word >> 16) & 255)
        let un_next_c: u16 = as(u16, (un_next_word >> 24) & 255)
        if un_next_op ~= @{OP_MMBIN} then
            jump invalid(code = @{ERR_RUNTIME})
        end
        if un_next_a ~= a or un_next_b ~= b then
            jump invalid(code = @{ERR_RUNTIME})
        end
        if op == @{OP_UNM} and un_next_c ~= @{TM_UNM} then jump invalid(code = @{ERR_RUNTIME}) end
        if op == @{OP_BNOT} and un_next_c ~= @{TM_BNOT} then jump invalid(code = @{ERR_RUNTIME}) end
    end
    if op == @{OP_ADDI} or op == @{OP_SHLI} or op == @{OP_SHRI} then
        if pc + 1 >= p.code_len then
            jump invalid(code = @{ERR_RUNTIME})
        end
        let next_word_i: u32 = p.code[pc + 1].word
        let next_op_i: u16 = as(u16, next_word_i & 127)
        let next_a_i: u16 = as(u16, (next_word_i >> 7) & 255)
        let next_b_i: u16 = as(u16, (next_word_i >> 16) & 255)
        let next_c_i: u16 = as(u16, (next_word_i >> 24) & 255)
        if next_op_i ~= @{OP_MMBINI} then
            jump invalid(code = @{ERR_RUNTIME})
        end
        if next_a_i ~= b then
            jump invalid(code = @{ERR_RUNTIME})
        end
        if op == @{OP_ADDI} then
            if next_c_i ~= @{TM_ADD} and next_c_i ~= @{TM_SUB} then jump invalid(code = @{ERR_RUNTIME}) end
            if next_c_i == @{TM_ADD} and next_b_i ~= c then jump invalid(code = @{ERR_RUNTIME}) end
        end
        if op == @{OP_SHLI} then
            if next_b_i ~= c or next_c_i ~= @{TM_SHL} then jump invalid(code = @{ERR_RUNTIME}) end
        end
        if op == @{OP_SHRI} then
            if next_c_i ~= @{TM_SHR} and next_c_i ~= @{TM_SHL} then jump invalid(code = @{ERR_RUNTIME}) end
            if next_c_i == @{TM_SHR} and next_b_i ~= c then jump invalid(code = @{ERR_RUNTIME}) end
        end
    end
    if op == @{OP_ADDK} or op == @{OP_SUBK} or op == @{OP_MULK} or op == @{OP_MODK} or op == @{OP_POWK} or op == @{OP_DIVK} or op == @{OP_IDIVK} or op == @{OP_BANDK} or op == @{OP_BORK} or op == @{OP_BXORK} then
        if pc + 1 >= p.code_len then
            jump invalid(code = @{ERR_RUNTIME})
        end
        let next_word_k: u32 = p.code[pc + 1].word
        let next_op_k: u16 = as(u16, next_word_k & 127)
        let next_a_k: u16 = as(u16, (next_word_k >> 7) & 255)
        let next_b_k: u16 = as(u16, (next_word_k >> 16) & 255)
        let next_c_k: u16 = as(u16, (next_word_k >> 24) & 255)
        if next_op_k ~= @{OP_MMBINK} then
            jump invalid(code = @{ERR_RUNTIME})
        end
        if next_a_k ~= b or next_b_k ~= c then
            jump invalid(code = @{ERR_RUNTIME})
        end
        if op == @{OP_ADDK} and next_c_k ~= @{TM_ADD} then jump invalid(code = @{ERR_RUNTIME}) end
        if op == @{OP_SUBK} and next_c_k ~= @{TM_SUB} then jump invalid(code = @{ERR_RUNTIME}) end
        if op == @{OP_MULK} and next_c_k ~= @{TM_MUL} then jump invalid(code = @{ERR_RUNTIME}) end
        if op == @{OP_MODK} and next_c_k ~= @{TM_MOD} then jump invalid(code = @{ERR_RUNTIME}) end
        if op == @{OP_POWK} and next_c_k ~= @{TM_POW} then jump invalid(code = @{ERR_RUNTIME}) end
        if op == @{OP_DIVK} and next_c_k ~= @{TM_DIV} then jump invalid(code = @{ERR_RUNTIME}) end
        if op == @{OP_IDIVK} and next_c_k ~= @{TM_IDIV} then jump invalid(code = @{ERR_RUNTIME}) end
        if op == @{OP_BANDK} and next_c_k ~= @{TM_BAND} then jump invalid(code = @{ERR_RUNTIME}) end
        if op == @{OP_BORK} and next_c_k ~= @{TM_BOR} then jump invalid(code = @{ERR_RUNTIME}) end
        if op == @{OP_BXORK} and next_c_k ~= @{TM_BXOR} then jump invalid(code = @{ERR_RUNTIME}) end
    end

    -- Comparisons/tests are followed by the jump they conditionally skip.
    if op == @{OP_EQ} or op == @{OP_LT} or op == @{OP_LE} or op == @{OP_EQK} or op == @{OP_EQI} or op == @{OP_LTI} or op == @{OP_LEI} or op == @{OP_GTI} or op == @{OP_GEI} or op == @{OP_TEST} or op == @{OP_TESTSET} then
        if pc + 1 >= p.code_len then
            jump invalid(code = @{ERR_RUNTIME})
        end
        let cmp_next_word: u32 = p.code[pc + 1].word
        let cmp_next_op: u16 = as(u16, cmp_next_word & 127)
        if cmp_next_op ~= @{OP_JMP} then
            jump invalid(code = @{ERR_RUNTIME})
        end
    end

    -- Jump and loop targets/windows.
    if op == @{OP_JMP} then
        let target: i32 = as(i32, pc) + sj
        if target < 0 or as(index, target) >= p.code_len then
            jump invalid(code = @{ERR_RUNTIME})
        end
    end
    if op == @{OP_FORLOOP} then
        let target: i32 = as(i32, pc) - as(i32, bx)
        if target < 0 or as(index, target) >= p.code_len then
            jump invalid(code = @{ERR_RUNTIME})
        end
    end
    if op == @{OP_FORPREP} then
        let target: i32 = as(i32, pc) + as(i32, bx) + 1
        if target < 0 or as(index, target) >= p.code_len then
            jump invalid(code = @{ERR_RUNTIME})
        end
    end
    if op == @{OP_TFORPREP} then
        let target: i32 = as(i32, pc) + as(i32, bx)
        if target < 0 or as(index, target) >= p.code_len then
            jump invalid(code = @{ERR_RUNTIME})
        end
    end
    if op == @{OP_TFORLOOP} then
        let target: i32 = as(i32, pc) - as(i32, bx)
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
