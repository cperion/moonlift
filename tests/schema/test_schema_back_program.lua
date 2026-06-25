package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")
local BackProgram = require("lalin.back_program")

local T = pvm.context()
Schema(T)
local B = T.LalinBack
local P = BackProgram(T)

local a = B.CmdFinalizeModule
local empty = P.empty()
assert(pvm.classof(empty) == B.BackProgram)
assert(#empty.cmds == 0)

local one = P.singleton(a)
assert(#one.cmds == 1)
assert(one.cmds[1] == a)

local two = P.append(one, a)
assert(#two.cmds == 2)
assert(#one.cmds == 1, "append must be structural, not mutating")

local three = P.extend(one, { a, a })
assert(#three.cmds == 3)

local cat = P.concat({ one, two })
assert(#cat.cmds == 3)

local cmds = P.cmds(cat)
cmds[1] = nil
assert(#cat.cmds == 3, "cmds returns a copy")

io.write("lalin schema_back_program ok\n")
