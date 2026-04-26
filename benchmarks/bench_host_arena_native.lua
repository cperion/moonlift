package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local HostAbi = require("moonlift.host_arena_abi")
local Native = require("moonlift.host_arena_native")

local mode = arg and arg[1] or "quick"
local iters = tonumber(os.getenv("MOONLIFT2_HOST_ARENA_NATIVE_ITERS") or (mode == "full" and "2000000" or "200000"))
local batch_size = tonumber(os.getenv("MOONLIFT2_HOST_ARENA_NATIVE_BATCH") or "100")

local User = HostAbi.define_record({
    name = "BenchNativeHostUser",
    ctype = "MoonliftBenchNativeHostUser",
    cdef = [[
        typedef struct MoonliftBenchNativeHostUser {
            int32_t id;
            int32_t age;
            uint8_t active;
            uint8_t _pad[3];
        } MoonliftBenchNativeHostUser;
    ]],
    fields = {
        { name = "id", kind = "i32" },
        { name = "age", kind = "i32" },
        { name = "active", kind = "bool" },
    },
})

local session = Native.session()
local proxy = session:alloc_record(User, { id = 42, age = 27, active = true })
local builder = session:record_builder(User, { capacity = batch_size })
local one_builder = session:record_builder(User, { capacity = 1 })
local tbl = { id = 42, age = 27, active = true }
local ptr = proxy:ptr()

local function bench(name, fn)
    collectgarbage("collect")
    local checksum = 0
    local t0 = os.clock()
    for _ = 1, iters do checksum = checksum + fn() end
    local dt = os.clock() - t0
    print(string.format("%-32s %.6f checksum=%d", name, dt, checksum))
    return dt
end

local batch_inits = {}
for i = 1, batch_size do
    batch_inits[i] = { id = i, age = i + 1, active = (i % 2) == 0 }
end

local function bench_batch(name, chunks, fn)
    collectgarbage("collect")
    local checksum = 0
    local t0 = os.clock()
    for _ = 1, chunks do checksum = checksum + fn() end
    local dt = os.clock() - t0
    print(string.format("%-32s %.6f checksum=%d", name, dt, checksum))
    return dt
end

print("host_arena_native", mode, "iters", iters, "batch", batch_size)
local t_table = bench("lua_table_fields", function()
    return tbl.id + tbl.age + (tbl.active and 1 or 0)
end)
local t_proxy = bench("rust_owned_proxy_fields", function()
    return proxy.id + proxy.age + (proxy.active and 1 or 0)
end)
local t_ptr = bench("rust_owned_raw_ptr_fields", function()
    return tonumber(ptr.id) + tonumber(ptr.age) + (ptr.active ~= 0 and 1 or 0)
end)
local t_alloc = bench("rust_alloc_record_one", function()
    local v = session:alloc_record(User, { id = 1, age = 2, active = true })
    return v.id + v.age + (v.active and 1 or 0)
end)
local t_alloc_cached = bench("rust_builder_one", function()
    local v = one_builder:build_one({ id = 1, age = 2, active = true })
    return v.id + v.age + (v.active and 1 or 0)
end)
local chunks = math.floor(iters / batch_size)
local t_batch = bench_batch("rust_alloc_records_batch", chunks, function()
    local values = session:alloc_records(User, batch_inits)
    local a = values[1]
    local b = values[#values]
    return a.id + b.age + (b.active and 1 or 0)
end)
local t_batch_cached = bench_batch("rust_builder_batch", chunks, function()
    local values = builder:build_many(batch_inits)
    local a = values[1]
    local b = values[#values]
    return a.id + b.age + (b.active and 1 or 0)
end)
print(string.format("ratio_proxy_vs_table %.3f", t_proxy / t_table))
print(string.format("ratio_ptr_vs_table %.3f", t_ptr / t_table))
print(string.format("alloc_one_records_per_sec %.0f", iters / t_alloc))
print(string.format("builder_one_records_per_sec %.0f", iters / t_alloc_cached))
print(string.format("alloc_batch_records_per_sec %.0f", (chunks * batch_size) / t_batch))
print(string.format("builder_batch_records_per_sec %.0f", (chunks * batch_size) / t_batch_cached))
session:free()
