-- Lua Interpreter VM — Proto validation trust boundary

local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")

local I = {}
for k, v in pairs(const.Err) do I["ERR_" .. k] = moon.int(v) end
for k, v in pairs(const.Op) do I["OP_" .. k] = moon.int(v) end

-- validate_proto: verify Proto is safe to execute
local validate_proto = host.region {
    ERR_RUNTIME = I.ERR_RUNTIME, ERR_BAD_OPCODE = I.ERR_BAD_OPCODE,
    OP_VARARG = I.OP_VARARG, OP_LOADK = I.OP_LOADK, OP_GETGLOBAL = I.OP_GETGLOBAL,
    OP_CLOSURE = I.OP_CLOSURE, OP_JMP = I.OP_JMP, OP_FORLOOP = I.OP_FORLOOP,
    OP_FORPREP = I.OP_FORPREP,
} [[
region validate_proto(L: ptr(LuaThread), p: ptr(Proto);
                      ok: cont(), invalid: cont(code: i32), oom: cont())
entry start()
    if p == nil then
        jump invalid(code = @{ERR_RUNTIME})
    end
    if p.code_len == 0 then
        jump ok()
    end
    jump loop(pc = 0)
end
block loop(pc: index)
    if pc >= p.code_len then
        jump ok()
    end
    let instr: Instr = p.code[pc]
    if instr.op > @{OP_VARARG} then
        jump invalid(code = @{ERR_BAD_OPCODE})
    end
    if instr.a >= p.maxstack then
        jump invalid(code = @{ERR_RUNTIME})
    end
    if instr.op == @{OP_LOADK} or instr.op == @{OP_GETGLOBAL} then
        if as(index, instr.bx) >= p.constants_len then
            jump invalid(code = @{ERR_RUNTIME})
        end
    end
    if instr.op == @{OP_CLOSURE} then
        if as(index, instr.bx) >= p.children_len then
            jump invalid(code = @{ERR_RUNTIME})
        end
    end
    if instr.op == @{OP_JMP} or instr.op == @{OP_FORLOOP} or instr.op == @{OP_FORPREP} then
        let target: i32 = as(i32, pc) + instr.sbx
        if target < 0 or as(index, target) >= p.code_len then
            jump invalid(code = @{ERR_RUNTIME})
        end
    end
    jump loop(pc = pc + 1)
end
end
]]

return {
    validate_proto = validate_proto,
}
