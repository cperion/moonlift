package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local HostAbi = require("moonlift.host_arena_abi")

local mode = arg and arg[1] or "quick"
local iters = tonumber(os.getenv("MOONLIFT2_HOST_ABI_ITERS") or (mode == "full" and "20000000" or "2000000"))

local User = HostAbi.define_record({
    name = "BenchHostAbiUser",
    ctype = "MoonliftBenchHostAbiUser",
    cdef = [[
        typedef struct MoonliftBenchHostAbiUser {
            int32_t id;
            int32_t age;
            uint8_t active;
            uint8_t _pad[3];
        } MoonliftBenchHostAbiUser;
    ]],
    fields = {
        { name = "id", kind = "i32" },
        { name = "age", kind = "i32" },
        { name = "active", kind = "bool" },
    },
})

local proxy = User:new({ id = 42, age = 27, active = true })
local tbl = { id = 42, age = 27, active = true }
local ptr = proxy:ptr()

local function bench(name, fn)
    collectgarbage("collect")
    local checksum = 0
    local t0 = os.clock()
    for _ = 1, iters do checksum = checksum + fn() end
    local dt = os.clock() - t0
    print(string.format("%-28s %.6f checksum=%d", name, dt, checksum))
    return dt
end

print("host_arena_abi", mode, "iters", iters)
local t_table = bench("lua_table_fields", function()
    return tbl.id + tbl.age + (tbl.active and 1 or 0)
end)
local t_proxy = bench("proxy_typed_fields", function()
    return proxy.id + proxy.age + (proxy.active and 1 or 0)
end)
local t_ptr = bench("raw_ptr_fields", function()
    return tonumber(ptr.id) + tonumber(ptr.age) + (ptr.active ~= 0 and 1 or 0)
end)
print(string.format("ratio_proxy_vs_table %.3f", t_proxy / t_table))
print(string.format("ratio_ptr_vs_table %.3f", t_ptr / t_table))
