package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function command_ok(cmd)
    local ok = os.execute(cmd)
    return ok == true or ok == 0
end

assert(command_ok("make lalin-bin"), "expected make lalin-bin to build the embedded Lalin executable")
assert(command_ok("test -f target/lalin_binary/lalin_embedded_bc_bank.c"), "expected binary build to generate embedded BC bank source")
assert(command_ok("test -f target/lalin_binary/lalin_embedded_bc_bank.h"), "expected binary build to generate embedded BC bank header")
assert(command_ok("test -f target/lalin_binary/lalin_embedded_mc_bank.c"), "expected binary build to generate embedded MC bank source")
assert(command_ok("test -f target/lalin_binary/lalin_embedded_mc_bank.h"), "expected binary build to generate embedded MC bank header")
assert(command_ok("target/lalin --version >/dev/null"), "expected embedded Lalin executable to start")
assert(command_ok("target/lalin -e " .. shell_quote("local lalin=require('lalin'); assert(type(lalin.compile)=='function'); assert(type(require('llbl'))=='table'); local pvm=require('lalin.pvm'); local Schema=require('lalin.schema'); local T=pvm.context(); Schema(T); local InternSet=require('lalin.copy_patch_mc_intern_set')(T); assert(debug.getregistry()['lalin.embedded_mc_bank.count'] == #InternSet.expected_symbols())")), "expected embedded banks to match the MC intern matrix")

os.execute("mkdir -p target/lalin_binary_smoke")
local path = "target/lalin_binary_smoke/smoke.lua"
local f = assert(io.open(path, "wb"))
f:write([=[
local lalin = require("lalin")
local add = lalin.loadstring([[return fn. add { a [i32], b [i32] } [i32] { ret (a + b), }]], "embedded_smoke.lua")
local m = lalin.compile("embedded_smoke", { add })
assert(m.add(20, 22) == 42)
]=])
f:close()

assert(command_ok("target/lalin " .. shell_quote(path)), "expected embedded Lalin executable to compile and run DSL input")

io.write("lalin binary ok\n")
