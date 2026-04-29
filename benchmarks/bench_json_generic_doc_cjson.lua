package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path
package.cpath = "./.luarocks/lib64/lua/5.1/?.so;" .. package.cpath

local cjson = require("cjson")
local Json = require("moonlift.json_library")

local mode = arg and arg[1] or "quick"
local iters = tonumber(os.getenv("MOONLIFT2_JSON_GENERIC_ITERS") or (mode == "full" and "200000" or "20000"))

local src = [[{"id":42,"active":true,"items":[1,2,3,4],"obj":{"x":7},"name":"cedric","bad":"12"}]]

local compiled = assert(Json.compile())
local decoder = Json.doc_decoder(compiled, { byte_cap = #src, tape_cap = #src, stack_cap = 128 })
local doc = assert(decoder:decode(src))
assert(doc:get_i32("id") == 42)
assert(doc:get_bool("active") == true)
local obj = assert(doc:find_field_raw("obj"))
assert(doc:get_i32("x", obj) == 7)
assert(cjson.decode(src).obj.x == 7)

local function bench(name, fn)
    collectgarbage("collect")
    local checksum = 0
    local t0 = os.clock()
    for _ = 1, iters do checksum = checksum + fn() end
    local dt = os.clock() - t0
    print(string.format("%-34s %.6f checksum=%d", name, dt, checksum))
    return dt
end

print("json_generic_doc", mode, "iters", iters, "bytes", #src)
local t_doc = bench("moonlift_doc_decoder_get", function()
    local d = assert(decoder:decode(src))
    local id = assert(d:get_i32("id"))
    local active = assert(d:get_bool("active"))
    local o = assert(d:find_field_raw("obj"))
    local x = assert(d:get_i32("x", o))
    return id + x + (active and 1 or 0)
end)
local t_cjson = bench("cjson_decode_get", function()
    local d = cjson.decode(src)
    return d.id + d.obj.x + (d.active and 1 or 0)
end)
print(string.format("ratio_doc_vs_cjson %.3f", t_doc / t_cjson))

compiled.artifact:free()
