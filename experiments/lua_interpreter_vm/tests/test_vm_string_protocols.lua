-- Focused protocol tests for string hashing and interning boundary.

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local moon = require("moonlift")
local vm = require("experiments.lua_interpreter_vm.src.init")

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1; print("  PASS " .. name)
    else fail = fail + 1; print("  FAIL " .. name) end
end

print("=== VM string protocol checks ===\n")

local hash_fn = moon.func { string_hash = vm.regions_string.string_hash } [[
hash_bytes(bytes: ptr(u8), len: index): u32
    return region: u32
    entry start()
        emit @{string_hash}(bytes, len, as(u32, 0); done = done)
    end
    block done(hash: u32) return hash end
    end
end
]]:compile()

local bytes = ffi.new("uint8_t[3]", string.byte("a"), string.byte("b"), string.byte("c"))
local expected = ((0 * 5 + string.byte("a")) * 5 + string.byte("b")) * 5 + string.byte("c")
check("string_hash computes VM hash", hash_fn(bytes, 3) == expected)
hash_fn:free()

local intern_probe = moon.func {
    string_intern = vm.regions_string.string_intern,
    sys_realloc = vm.regions_allocator.sys_realloc,
} [[
intern_probe(L: ptr(LuaThread), bytes: ptr(u8), len: index): i32
    return region: i32
    entry start()
        emit @{string_intern}(L, bytes, len; found = found, created = created, oom = oom)
    end
    block found(s: ptr(String)) return 1 end
    block created(s: ptr(String)) return 2 end
    block oom() return 3 end
    end
end
]]:compile()
check("string_intern boundary compiles and rejects missing runtime storage", intern_probe(nil, bytes, 3) == 3)
intern_probe:free()

print(string.format("\n=== %d/%d passed ===", pass, pass + fail))
assert(fail == 0)
return true
