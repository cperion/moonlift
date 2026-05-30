-- Regression coverage for VM allocator/native hook indirect calls.
-- The allocator boundary stores callbacks as ptr(u8) fields and casts them to
-- typed function pointers at the Moonlift boundary. This must compile and run
-- with the exact indirect-call signature, not accidentally reuse the enclosing
-- function signature.

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local moon = require("moonlift")

ffi.cdef [[
void* malloc(size_t size);
void free(void* ptr);
]]

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1; print("  PASS " .. name)
    else fail = fail + 1; print("  FAIL " .. name) end
end

print("=== VM allocator indirect-call contract ===\n")

local callback = ffi.cast("uint64_t (*)(uint8_t*, uint64_t, uint64_t, uint64_t)",
    function(old, old_size, new_size, align)
        if new_size == 0 then
            if old ~= nil then ffi.C.free(old) end
            return ffi.cast("uint64_t", 0)
        end
        local p = ffi.C.malloc(tonumber(new_size))
        if p == nil then return ffi.cast("uint64_t", 0) end
        return ffi.cast("uint64_t", ffi.cast("uintptr_t", p))
    end)

local probe = moon.func [[
probe_allocator_hook(fp: ptr(u8)) -> i32
    let realloc_fn: func(ptr(u8), index, index, index) -> u64 = as(func(ptr(u8), index, index, index) -> u64, fp)
    let bits: u64 = realloc_fn(as(ptr(u8), as(u64, 0)), as(index, 0), as(index, 16), as(index, 8))
    if bits == as(u64, 0) then return 0 end
    let ignored: u64 = realloc_fn(as(ptr(u8), bits), as(index, 16), as(index, 0), as(index, 8))
    return 1
end
]]:compile()

check("typed allocator callback pointer compiles and runs", probe(ffi.cast("uint8_t*", callback)) == 1)

probe:free()
callback:free()

print(string.format("\n=== %d/%d passed ===", pass, pass + fail))
assert(fail == 0)
return true
