-- Lua 5.5 bytecode decoder oracle checks.

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local vm = require("experiments.lua_interpreter_vm.src.init")
local const = vm.const
local bc = vm.bytecode

local pass, fail = 0, 0
local function check(name, cond, msg)
    if cond then pass = pass + 1; print("  PASS " .. name)
    else fail = fail + 1; print("  FAIL " .. name .. (msg and (": " .. msg) or "")) end
end

print("=== VM bytecode decoder contract ===\n")

local j = bc.decode_word(bc.encode_sJ(const.Op.JMP, -42))
check("sJ decodes 25-bit signed jump", j.op == const.Op.JMP and j.sJ == -42, tostring(j.sJ))

local imm = bc.decode_word(bc.encode_ABC(const.Op.ADDI, 1, 2, bc.OFFSET_SC - 9, 0))
check("sC decodes as C - 127", imm.sC == -9, tostring(imm.sC))

local ax = bc.decode_word(bc.encode_Ax(const.Op.EXTRAARG, 100000))
check("EXTRAARG uses Ax", ax.Ax == 100000 and ax.Bx ~= 100000, tostring(ax.Ax) .. "/" .. tostring(ax.Bx))

local nt = bc.decode_word(bc.encode_AvBCk(const.Op.NEWTABLE, 4, 17, 513, 1))
check("NEWTABLE decodes vB/vC/k", nt.A == 4 and nt.vB == 17 and nt.vC == 513 and nt.K == 1)

local fl = bc.decode_word(bc.encode_ABx(const.Op.FORLOOP, 2, 12345))
check("FORLOOP uses Bx", fl.A == 2 and fl.Bx == 12345)

print(string.format("\n=== %d/%d passed ===", pass, pass + fail))
assert(fail == 0)
return true
