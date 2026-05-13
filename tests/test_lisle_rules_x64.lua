package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local LisleCompile = require("moonlift.lisle.compile")

local f = assert(io.open("back/dasm/rules_x64.lisle", "rb"))
local src = f:read("*a")
f:close()

local calls = {}
local env = {
  isel = {
    const_ = function() calls[#calls + 1] = "const" end,
    emit_epilogue = function() calls[#calls + 1] = "epilogue" end,
  },
  encode = {
    emit = function(op) calls[#calls + 1] = op end,
  },
}
setmetatable(env, { __index = _G })

local mod = select(1, LisleCompile.load_source(src, "rules_x64_lisle_test", env))

mod.lower_cmd({}, { kind = "CmdConst" }, {}, 1)
mod.lower_cmd({}, { kind = "CmdReturnVoid" }, {}, 2)
mod.lower_cmd({}, { kind = "CmdTrap" }, {}, 3)
mod.lower_cmd({}, { kind = "CmdCreateBlock" }, {}, 4)

assert(calls[1] == "const")
assert(calls[2] == "epilogue")
assert(calls[3] == "int3_0")

local ok = pcall(function()
  mod.lower_cmd({}, { kind = "CmdUnknown" }, {}, 9)
end)
assert(ok == false)

print("lisle rules_x64: ok")
