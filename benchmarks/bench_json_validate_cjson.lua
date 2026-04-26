-- Moonlift full structural JSON validator vs lua-cjson decode.

package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path
package.cpath = "./.luarocks/lib64/lua/5.1/?.so;" .. package.cpath

local ffi = require("ffi")
local cjson = require("cjson")
local Json = require("moonlift.json_library")

local mode = arg and arg[1] or "quick"
local quick = mode == "quick"
local COUNT = tonumber(os.getenv("MOONLIFT2_JSON_COUNT") or (quick and "10000" or "200000"))
local WARMUP = tonumber(os.getenv("MOONLIFT2_JSON_WARMUP") or (quick and "1" or "2"))
local ITERS = tonumber(os.getenv("MOONLIFT2_JSON_ITERS") or (quick and "5" or "7"))

local function best_of(f, ...)
    for _ = 1, WARMUP do f(...) end
    local best, result = math.huge, nil
    for _ = 1, ITERS do
        collectgarbage("collect")
        local t0 = os.clock()
        result = f(...)
        local dt = os.clock() - t0
        if dt < best then best = dt end
    end
    return best, result
end

local function build_json(count)
    local parts = { "{\"items\":[" }
    for i = 1, count do
        if i > 1 then parts[#parts + 1] = "," end
        local v = (i * 17 + 3) % 1009
        parts[#parts + 1] = "{\"id\":" .. tostring(v) .. ",\"ok\":true,\"name\":\"item\\u0041\"}"
    end
    parts[#parts + 1] = "],\"tail\":null}"
    return table.concat(parts)
end

local compiled, err = Json.compile()
if not compiled then
    io.stderr:write("json library compile failed at " .. tostring(err.stage) .. "\n")
    for i = 1, #err.issues do io.stderr:write(tostring(err.issues[i]) .. "\n") end
    error("json library compile failed")
end
local artifact = compiled.artifact
local B1 = compiled.B1
local valid = ffi.cast("int32_t (*)(const uint8_t*, int32_t, int32_t*, int32_t)", artifact:getpointer(B1.BackFuncId("json_valid_scalar")))

local src = build_json(COUNT)
local buf = ffi.new("uint8_t[?]", #src)
local stack = ffi.new("int32_t[?]", 4096)
ffi.copy(buf, src, #src)
assert(valid(buf, #src, stack, 4096) == 0)
assert(cjson.decode(src).items[1].ok == true)

local function moon_valid()
    return tonumber(valid(buf, #src, stack, 4096))
end
local function cjson_decode_only(s)
    local v = cjson.decode(s)
    return #v.items
end

local moon_t, moon_result = best_of(moon_valid)
local cjson_t, cjson_result = best_of(cjson_decode_only, src)

io.write(string.format("json_objects %d bytes %d\n", COUNT, #src))
io.write(string.format("moonlift_json_valid %.9f %d\n", moon_t, moon_result))
io.write(string.format("cjson_decode_object %.9f %d\n", cjson_t, cjson_result))
io.write(string.format("ratio_moonlift_vs_cjson_decode %.3f\n", moon_t / cjson_t))

artifact:free()
