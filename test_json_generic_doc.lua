package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Json = require("moonlift.json_library")

local compiled, err = Json.compile()
if not compiled then
    io.stderr:write("json library compile failed at " .. tostring(err.stage) .. "\n")
    for i = 1, #err.issues do io.stderr:write(tostring(err.issues[i]) .. "\n") end
    error("json library compile failed")
end

local doc, parse_err = Json.parse(compiled, [[{"id":42,"active":true,"items":[1,2],"obj":{"x":7},"bad":"12"}]], { stack_cap = 256, tape_cap = 128 })
assert(doc, tostring(parse_err))
assert(doc.root == 0)
assert(doc.tags[doc.root] == Json.TAG.OBJECT_BEGIN)
assert(doc:child_count_of() == 5)

local id, id_err = doc:get_i32("id")
assert(id == 42 and id_err == nil)
local active, active_err = doc:get_bool("active")
assert(active == true and active_err == nil)
local missing, missing_err = doc:get_i32("missing")
assert(missing == nil and missing_err == "missing")
local bad, bad_err = doc:get_i32("bad")
assert(bad == nil and bad_err == "type")

local obj_idx = doc:find_field_raw("obj")
assert(obj_idx ~= nil)
assert(doc.tags[obj_idx] == Json.TAG.OBJECT_BEGIN)
assert(doc:child_count_of(obj_idx) == 1)
local x, x_err = doc:get_i32("x", obj_idx)
assert(x == 7 and x_err == nil)

local items_idx = doc:find_field_raw("items")
assert(items_idx ~= nil)
assert(doc.tags[items_idx] == Json.TAG.ARRAY_BEGIN)
assert(doc:child_count_of(items_idx) == 2)
local first_item = doc.first_child[items_idx]
local out = compiled and doc._out
assert(compiled.read_i32(doc.buf, doc.tags, doc.a, doc.b, first_item, out) == 0)
assert(out[0] == 1)
local second_item = doc.next_sibling[first_item]
assert(compiled.read_i32(doc.buf, doc.tags, doc.a, doc.b, second_item, out) == 0)
assert(out[0] == 2)

local escaped_doc = assert(Json.parse(compiled, [[{"\u0069d":5}]], { stack_cap = 256, tape_cap = 32 }))
local escaped = escaped_doc:find_field_raw("id")
assert(escaped == nil, "raw generic lookup should not claim escaped-key semantic equality")

local decoder = Json.doc_decoder(compiled, { byte_cap = 128, tape_cap = 128, stack_cap = 256 })
local reused = assert(decoder:decode([[{"id":1,"active":false}]]))
assert(reused:get_i32("id") == 1)
assert(reused:get_bool("active") == false)
local reused2 = assert(decoder:decode([[{"id":2,"active":true,"obj":{"x":9}}]]))
assert(reused2 == reused)
assert(reused:get_i32("id") == 2)
assert(reused:get_bool("active") == true)
local reused_obj = reused:find_field_raw("obj")
assert(reused:get_i32("x", reused_obj) == 9)

compiled.artifact:free()
print("moonlift json generic doc ok")
