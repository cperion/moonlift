package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Compile = require("moonlift.lisle.compile")
local Lisle = require("moonlift.lisle.runtime")

local src = [[
(term inc (x))
(rule inc 10
  (x)
  (expr (+ x 1)))
]]

local path = "/tmp/test_lisle_file_api.lisle"
local wf = assert(io.open(path, "wb"))
wf:write(src)
wf:close()

local code, spec = Compile.compile_file(path, "test_lisle_file_api")
assert(type(code) == "string" and spec and spec.terms and spec.terms.inc)

local mod = Lisle.load_file(path, "test_lisle_file_api_run")
assert(mod.inc({}, 41) == 42)

print("lisle file api: ok")
