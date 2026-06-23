package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local moon = require("moonlift")
local session = moon.use { scope = "env" }
local pvm = require("moonlift.pvm")

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
local decl = moon.unit("DriverSmoke", decls)

local lowered = decl:lower()
assert(pvm.classof(lowered))
assert(tostring(pvm.classof(lowered)):match("MoonCompiler%.FlatlineImage"))

local artifact = decl:emit_c_artifact()
assert(artifact.unit)
assert(tostring(pvm.classof(artifact.unit)):match("MoonC%.CBackendUnit"))
assert(type(artifact.source) == "string")

local object_bytes = require("moonlift").emit_object(decl, nil, "driver_smoke_object")
assert(type(object_bytes) == "string")
assert(#object_bytes > 0)

local native = moon.compile("DriverSmoke", decls)
assert(native.descriptor)
assert(tostring(pvm.classof(native.descriptor)):match("MoonCompiler%.NativeArtifact"))
native:free()

io.write("moonlift compiler_driver ok\n")
