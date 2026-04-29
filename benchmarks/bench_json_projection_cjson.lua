package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path
package.cpath = "./.luarocks/lib64/lua/5.1/?.so;" .. package.cpath

local ffi = require("ffi")
local cjson = require("cjson")
local Json = require("moonlift.json_codegen")

local mode = arg and arg[1] or "quick"
local iters = mode == "full" and 200000 or 20000

local src = [[ { "meta": {"nested": [1,2,3,4], "skip": true}, "name": "cedric", "id": 42, "active": true, "age": -7, "ignored": [false, null, {"x": 1}] } ]]

local function u8buf(s)
    local buf = ffi.new("uint8_t[?]", #s)
    ffi.copy(buf, s, #s)
    return buf, #s
end

local ptr, n = u8buf(src)
local ptr_src = { ptr = ptr, n = n }
local out = ffi.new("int32_t[3]")

local projector = Json.project({
    { name = "id", type = "i32" },
    { name = "age", type = "i32" },
    { name = "active", type = "bool" },
}, { byte_cap = #src, tape_cap = #src, stack_cap = 256 })
projector:compile()

local function bench(name, fn)
    collectgarbage("collect")
    local t0 = os.clock()
    local checksum = 0
    for _ = 1, iters do checksum = checksum + fn() end
    local dt = os.clock() - t0
    print(string.format("%-36s %.6f checksum=%d", name, dt, checksum))
    return dt
end

print("json_projection_indexed", mode, "iters", iters, "bytes", #src)
local t_buf = bench("moonlift_project_indexed_buffer", function()
    local got, err = projector:decode_i32(ptr_src, out)
    if not got then error(err) end
    return tonumber(out[0]) + tonumber(out[1]) + tonumber(out[2])
end)
local t_str = bench("moonlift_project_indexed_string", function()
    local got, err = projector:decode_i32(src, out)
    if not got then error(err) end
    return tonumber(out[0]) + tonumber(out[1]) + tonumber(out[2])
end)
local t_table = bench("moonlift_project_indexed_table", function()
    local obj, err = projector:decode_table(src)
    if not obj then error(err) end
    return obj.id + obj.age + (obj.active and 1 or 0)
end)
local t_cjson = bench("cjson_decode_project", function()
    local obj = cjson.decode(src)
    return obj.id + obj.age + (obj.active and 1 or 0)
end)

print(string.format("ratio_buffer_vs_cjson %.3f", t_buf / t_cjson))
print(string.format("ratio_string_vs_cjson %.3f", t_str / t_cjson))
print(string.format("ratio_table_vs_cjson %.3f", t_table / t_cjson))

projector:free()
