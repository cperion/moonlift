-- Verify the ASDL host model exposes explicit HostProgram/HostTemplate steps.

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")

local T = pvm.context(); A.Define(T)
local S = T.MoonSource
local doc = S.DocumentSnapshot(S.DocUri("pipeline.mlua"), S.DocVersion(0), S.LangMlua, [[
local x = 7
local r = region R()
entry start()
    let y: i32 = @{x}
end
end
return r
]])

local parts = require("moonlift.mlua_document").Define(T).document_parts(doc)
local program = pvm.one(require("moonlift.mlua_host_model").Define(T).host_program(parts))
assert(#program.steps >= 2)
local saw_region = false
for i = 1, #program.steps do
    if program.steps[i].template and program.steps[i].template.kind_word == "region" then
        saw_region = true
        assert(#program.steps[i].template.parts == 3)
    end
end
assert(saw_region)

print("moonlift ASDL host pipeline ok")
return "moonlift ASDL host pipeline ok"
