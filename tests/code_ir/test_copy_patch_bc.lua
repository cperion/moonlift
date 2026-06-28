package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Schema = require("lalin.schema")
local pvm = require("lalin.pvm")

local T = pvm.context()
Schema(T)

local BC = require("lalin.copy_patch_bc")(T)

local source = [[
return function(x)
  return x + 2
end
]]

local entry, err = BC.compile_entry {
    id = "test:add_mode",
    symbol = "add_mode",
    chunk_name = "@test/copy_patch_bc/add_mode",
    source = source,
}
assert(entry, err)
assert(#entry.bytecode > 0, "expected dumped bytecode")

local bank = BC.build_bank({ entry }, { id = "test:bc-bank" })
assert(bank.target.luajit_version ~= "", "target records LuaJIT version")
assert(#bank.entries == 1, "expected one bank entry")

local loaded, load_err = BC.load_symbol(bank, "add_mode")
assert(loaded, load_err)
assert(loaded(5) == 7, "loaded bytecode should use exact compiled function")

io.write("copy_patch_bc ok\n")
