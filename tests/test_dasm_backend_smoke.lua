-- tests/test_dasm_backend_smoke.lua — end-to-end smoke test

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lib/?.lua;" ..
               "./.vendor/LuaJIT/dynasm/?.lua;" .. package.path

local ffi       = require("ffi")
local dasm_init = require("back.dasm")

local BackScalar = {
    I32 = {kind = "BackI32"},
    I64 = {kind = "BackI64"},
}
local function id(s) return {text = s} end

local program = {
    cmds = {
        {kind = "CmdCreateSig", sig = id("sig:add1"),
         params = {BackScalar.I32}, results = {BackScalar.I32}},
        {kind = "CmdDeclareFunc", visibility = {kind = "Public"},
         func = id("add1"), sig = id("sig:add1")},
        {kind = "CmdBeginFunc", func = id("add1")},
        {kind = "CmdCreateBlock", block = id("entry")},
        {kind = "CmdSwitchToBlock", block = id("entry")},
        {kind = "CmdBindEntryParams", block = id("entry"), values = {id("arg")}},
        {kind = "CmdConst", dst = id("one"), ty = BackScalar.I32,
         value = {kind = "BackLitInt", raw = "1"}},
        {kind = "CmdIntBinary", dst = id("sum"), op = {kind = "BackIntAdd"},
         scalar = BackScalar.I32,
         semantics = {overflow = {kind = "BackIntWrap"}, exact = {kind = "BackIntMayLose"}},
         lhs = id("arg"), rhs = id("one")},
        {kind = "CmdReturnValue", value = id("sum")},
        {kind = "CmdSealBlock", block = id("entry")},
        {kind = "CmdFinishFunc", func = id("add1")},
        {kind = "CmdFinalizeModule"},
    },
}

print("compiling add1...")
local api = dasm_init.Define({})
local jit = api.jit()
local artifact = jit:compile(program)

local ptr = artifact:getpointer("add1")
print("  ptr = " .. tostring(ptr))

local add1 = ffi.cast("int32_t (*)(int32_t)", ptr)
local result = add1(41)
print("add1(41) = " .. tostring(result))
assert(result == 42, "expected 42, got " .. tostring(result))

result = add1(-5)
print("add1(-5) = " .. tostring(result))
assert(result == -4, "expected -4, got " .. tostring(result))

print("OK — DynASM backend smoke test passed")
artifact:free()
