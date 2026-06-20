-- Compatibility-frontier contract tests. These verify that unsupported raw Lua 5.5
-- chunks are rejected at a typed boundary, not confused with internal Proto data.

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local moon = require("moonlift")
local vm = require("experiments.lua_interpreter_vm.src.init")

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1; print("  PASS " .. name)
    else fail = fail + 1; print("  FAIL " .. name) end
end

print("=== VM compatibility frontier checks ===\n")

check("compat exposes source frontier", vm.compat.source_frontier ~= nil)
check("compat exposes binary chunk frontier", vm.compat.binary_chunk_frontier ~= nil)
check("PUC remains oracle only", vm.compat.puc_oracle_only == true)

local route_chunk = moon.func { load_chunk = vm.regions_chunk.load_lua55_binary_chunk } [[
route_chunk(bytes: ptr(u8), len: index): i32
    return region: i32
    entry start()
        emit @{load_chunk}(as(ptr(LuaThread), as(u64, 0)), bytes, len;
            ok = ok,
            format_error = format_error,
            semantic_error = semantic_error,
            oom = oom)
    end
    block ok(proto: ptr(Proto)) return 1 end
    block format_error(err: CompileError) return 2 end
    block semantic_error(err: CompileError) return 3 end
    block oom() return 4 end
    end
end
]]:compile()

check("binary chunk frontier rejects unsupported chunks explicitly", route_chunk(nil, 0) == 2)
route_chunk:free()

print(string.format("\n=== %d/%d passed ===", pass, pass + fail))
assert(fail == 0)
return true
