package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local BackProgram = require("moonlift.back_program")

local T = pvm.context()
A2.Define(T)
local B = T.MoonBack
local P = BackProgram.Define(T)

local a = B.CmdConst(B.BackValId("a"), B.BackI32, B.BackLitInt("1"))
local b = B.CmdConst(B.BackValId("b"), B.BackI32, B.BackLitInt("2"))
local c = B.CmdReturnValue(B.BackValId("b"))

local empty = P.empty()
assert(pvm.classof(empty) == B.BackProgram)
assert(#empty.cmds == 0)

local one = P.singleton(a)
assert(#one.cmds == 1 and one.cmds[1] == a)

local two = P.append(one, b)
assert(#one.cmds == 1, "append must not mutate the original program")
assert(#two.cmds == 2 and two.cmds[1] == a and two.cmds[2] == b)

local three = P.extend(two, { c })
assert(#two.cmds == 2, "extend must not mutate the original program")
assert(#three.cmds == 3 and three.cmds[3] == c)

local joined = P.concat({ P.singleton(a), P.program({ b, c }) })
assert(#joined.cmds == 3 and joined.cmds[1] == a and joined.cmds[2] == b and joined.cmds[3] == c)

local copied = P.cmds(joined)
copied[1] = c
assert(joined.cmds[1] == a, "cmds() must return a copy")

print("moonlift back_program ok")
