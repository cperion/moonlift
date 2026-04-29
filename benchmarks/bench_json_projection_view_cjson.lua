package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path
package.cpath = "./.luarocks/lib64/lua/5.1/?.so;" .. package.cpath

local ffi = require("ffi")
local cjson = require("cjson")
local Json = require("moonlift.json_codegen")

local mode = arg and arg[1] or "quick"
local iters = tonumber(os.getenv("MOONLIFT2_JSON_PROJECTION_VIEW_ITERS") or (mode == "full" and "200000" or "20000"))

local src = [[ { "meta": {"nested": [1,2,3,4], "skip": true}, "name": "cedric", "id": 42, "active": true, "age": -7, "ignored": [false, null, {"x": 1}] } ]]
local function u8buf(s)
    local buf = ffi.new("uint8_t[?]", #s)
    ffi.copy(buf, s, #s)
    return { ptr = buf, n = #s }
end
local src_buf = u8buf(src)
local out = ffi.new("int32_t[3]")

local projector = Json.project({
    { name = "id", type = "i32" },
    { name = "age", type = "i32" },
    { name = "active", type = "bool" },
}, { byte_cap = #src, tape_cap = #src, stack_cap = 256 })
projector:compile()
projector:view_layout({ name = "BenchJsonProjectionView" })
local reusable = assert(projector:new_view())
local decoder = projector:view_decoder()
local view = assert(decoder:decode(src_buf))
assert(view.id == 42 and view.age == -7 and view.active == true)

local function bench(name, fn)
    collectgarbage("collect")
    local checksum = 0
    local t0 = os.clock()
    for _ = 1, iters do checksum = checksum + fn() end
    local dt = os.clock() - t0
    print(string.format("%-38s %.6f checksum=%d", name, dt, checksum))
    return dt
end

print("json_projection_view_indexed", mode, "iters", iters, "bytes", #src)
local t_buffer = bench("moonlift_project_indexed_buffer", function()
    local got, err = projector:decode_i32(src_buf, out)
    if not got then error(err) end
    return tonumber(out[0]) + tonumber(out[1]) + tonumber(out[2])
end)
local t_view_reuse = bench("moonlift_project_reused_view", function()
    local v, err = projector:decode_into_view(src_buf, reusable)
    if not v then error(err) end
    return v.id + v.age + (v.active and 1 or 0)
end)
local t_view_reuse_ptr = bench("moonlift_project_reused_view_ptr", function()
    local v, err = projector:decode_into_view(src_buf, reusable)
    if not v then error(err) end
    local p = v:ptr()
    return tonumber(p.f1) + tonumber(p.f2) + (p.f3 ~= 0 and 1 or 0)
end)
local t_view_decoder = bench("moonlift_view_decoder", function()
    local v, err = decoder:decode(src_buf)
    if not v then error(err) end
    return v.id + v.age + (v.active and 1 or 0)
end)
local t_table = bench("moonlift_project_indexed_table", function()
    local v, err = projector:decode_table(src_buf)
    if not v then error(err) end
    return v.id + v.age + (v.active and 1 or 0)
end)
local t_cjson = bench("cjson_decode_project", function()
    local v = cjson.decode(src)
    return v.id + v.age + (v.active and 1 or 0)
end)
print(string.format("ratio_buffer_vs_cjson %.3f", t_buffer / t_cjson))
print(string.format("ratio_reused_view_vs_cjson %.3f", t_view_reuse / t_cjson))
print(string.format("ratio_reused_view_ptr_vs_cjson %.3f", t_view_reuse_ptr / t_cjson))
print(string.format("ratio_view_decoder_vs_cjson %.3f", t_view_decoder / t_cjson))
print(string.format("ratio_table_vs_cjson %.3f", t_table / t_cjson))

projector:free()
decoder:free()
