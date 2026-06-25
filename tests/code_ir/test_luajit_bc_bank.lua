package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Schema = require("lalin.schema")
local pvm = require("lalin.pvm")

local T = pvm.context()
Schema(T)

local LJ = T.LalinLuaJIT
local BC = require("lalin.luajit_bc_bank")(T)

local source = [[
return function(x)
  local mode = "MLBC_PATCH_A"
  if mode == "MLBC_PATCH_B" then
    return x + 40
  end
  return x + 2
end
]]

local entry, err = BC.compile_entry {
    id = "test:add_mode",
    symbol = "add_mode",
    chunk_name = "@test/luajit_bc_bank/add_mode",
    source = source,
    holes = {
        {
            name = "mode",
            expected = "MLBC_PATCH_A",
            kind = LJ.LJBCPatchStringConstantExact,
            reason = "select bytecode stencil branch mode",
        },
    },
}
assert(entry, err)
assert(#entry.bytecode > 0, "expected dumped bytecode")
assert(#entry.patches == 1, "expected one patch")
assert(entry.patches[1].offset >= 0, "patch offsets are zero based")

local bank = BC.build_bank({ entry }, { id = "test:bc-bank" })
assert(bank.target.luajit_version ~= "", "target records LuaJIT version")
assert(#bank.entries == 1, "expected one bank entry")

local unpatched, unpatched_err = BC.load_symbol(bank, "add_mode")
assert(unpatched, unpatched_err)
assert(unpatched(5) == 7, "unpatched bytecode should use original constant")

local patched, patched_err = BC.load_symbol(bank, "add_mode", {
    LJ.LJBCPatchBinding("mode", LJ.LJBCPatchString("MLBC_PATCH_B")),
})
assert(patched, patched_err)
assert(patched(5) == 45, "patched bytecode should use replacement constant")

local bad, bad_err = BC.load_symbol(bank, "add_mode", {
    LJ.LJBCPatchBinding("mode", LJ.LJBCPatchString("too short")),
})
assert(bad == nil, "width-mismatched patch must fail")
assert(tostring(bad_err):match("replacement width mismatch"), bad_err)

io.write("luajit_bc_bank ok\n")
