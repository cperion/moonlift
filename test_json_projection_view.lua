package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local Json = require("moonlift.json_codegen")

local projector = Json.project({
    { name = "id", type = "i32" },
    { name = "age", type = "i32" },
    { name = "active", type = "bool" },
})
projector:compile()

local T = pvm.context()
A.Define(T)
local H = T.Moon2Host
local facts, layout = projector:view_layout_facts(T, { layout = { name = "JsonUserProjection" }, producer_name = "json_user_projection" })
assert(pvm.classof(facts) == H.HostFactSet)
assert(pvm.classof(layout) == H.HostTypeLayout)
assert(#layout.fields == 3)
assert(pvm.classof(layout.fields[3].rep) == H.HostRepBool)
assert(layout.fields[3].rep.encoding == H.HostBoolI32)

local decoder = projector:view_decoder({ layout = { name = "JsonUserProjection" } })
local view, err = decoder:decode([[{"meta":{"nested":[1,2,3]},"active":true,"id":42,"age":-7}]])
assert(view, tostring(err))
assert(view == decoder.view)
assert(view.id == 42)
assert(view.age == -7)
assert(view.active == true)
assert(view:owner())
assert(view:raw_ref()[0].session_id == 0)
assert(view:ptr().f1 == 42)
assert(view:ptr().f2 == -7)
assert(view:ptr().f3 ~= 0)

local t = view:to_table()
assert(t.id == 42)
assert(t.age == -7)
assert(t.active == true)

local view2, err2 = decoder:decode([[{"id":9,"age":11,"active":false,"ignored":[{"x":1}]}]])
assert(view2, tostring(err2))
assert(view2 == view)
assert(view.id == 9)
assert(view.age == 11)
assert(view.active == false)

local missing = assert(decoder:decode([[{"id":10}]]))
assert(missing == view)
assert(view.id == 10)
assert(view.age == 0)
assert(view.active == false)

local escaped_raw = assert(decoder:decode([[{"\u0069d":12,"a\u0067e":34,"active":true}]]))
assert(escaped_raw == view)
assert(view.id == 0)
assert(view.age == 0)
assert(view.active == true)

local borrowed = assert(decoder:decode([[{"id":12,"age":34,"active":true}]]))
assert(borrowed == decoder.view)
assert(borrowed.id == 12 and borrowed.age == 34 and borrowed.active == true)
local borrowed2 = assert(decoder:decode([[{"id":13,"age":35,"active":false}]]))
assert(borrowed2 == borrowed)
assert(borrowed.id == 13 and borrowed.age == 35 and borrowed.active == false)

local bad, bad_err = decoder:decode([[{"id":9,"age":11,"active":tru}]])
assert(bad == nil)
assert(bad_err ~= 0)

projector:free()
decoder:free()
print("moonlift json projection view ok")
