package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")
local session = lalin.use { scope = "env" }
local pvm = require("lalin.pvm")

local src = [[
return {
    fn. add
        { a [i32], b [i32] }
        [i32]
        {
            ret (a + b),
        },
}
]]

local decls = session:loadstring(src, "compiler_driver_test.lua")()
local decl = lalin.unit("DriverSmoke", decls)

local lowered = decl:lower()
assert(pvm.classof(lowered))
assert(tostring(pvm.classof(lowered)):match("LalinC%.CBackendUnit"))

local artifact = decl:emit_c_artifact()
assert(artifact.unit)
assert(tostring(pvm.classof(artifact.unit)):match("LalinC%.CBackendUnit"))
assert(type(artifact.source) == "string")

local native = lalin.compile("DriverSmoke", decls)
assert(native.add(3, 4) == 7)

io.write("lalin compiler_driver ok\n")
