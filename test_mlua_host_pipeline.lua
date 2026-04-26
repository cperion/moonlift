package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local MluaHostPipeline = require("moonlift.mlua_host_pipeline")
local Host = require("moonlift.host_quote")

local T = pvm.context()
A.Define(T)
local H = T.Moon2Host
local Pipeline = MluaHostPipeline.Define(T)

local src = [[
struct User {
    id: i32
    active: bool32
}

expose view(User) as Users {
    lua readonly checked
    terra
    c
}

expose ptr(User) as UserRef {
    lua readonly
    c
}
]]

local result = Pipeline.pipeline(H.MluaSource("demo", src), "demo")
assert(pvm.classof(result) == H.MluaHostPipelineResult)
assert(#result.parse.issues == 0, tostring(result.parse.issues[1]))
assert(#result.report.issues == 0, tostring(result.report.issues[1]))
assert(#result.layout_env.layouts == 1)
assert(result.layout_env.layouts[1].name == "User")
assert(#result.facts.facts > 0)
assert(#result.lua.cdefs >= 2)
assert(#result.lua.access_plans >= 2)
assert(result.terra.source:match("struct User"))
assert(result.c.source:match("typedef struct User"))

local saw_lua, saw_terra, saw_c, saw_view = false, false, false, false
for i = 1, #result.facts.facts do
    local cls = pvm.classof(result.facts.facts[i])
    if cls == H.HostFactLuaFfi then saw_lua = true end
    if cls == H.HostFactTerra then saw_terra = true end
    if cls == H.HostFactC then saw_c = true end
    if cls == H.HostFactViewDescriptor then saw_view = true end
end
assert(saw_lua and saw_terra and saw_c and saw_view)

local host_result = Host.host_pipeline(src, "demo2")
assert(#host_result.report.issues == 0)
assert(host_result.lua.module_name == "demo2")
assert(#host_result.layout_env.layouts == 1)

print("moonlift mlua host pipeline ok")
