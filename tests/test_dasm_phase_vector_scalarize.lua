package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local V = require("back.dasm.phases.vector_scalarize")

local body = {
    { kind = "CmdVecSplat" },
    { kind = "CmdVecBinary" },
}

local out = V.run(body)
assert(out == body)

print("dasm phase vector_scalarize: ok")
