-- NativeCallResult explicit routing contract.

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local moon = require("moonlift")
local vm = require("experiments.lua_interpreter_vm.src.init")
local const = vm.const

ffi.cdef [[
typedef struct { uint32_t tag; uint32_t aux; uint64_t bits; } Value;
typedef struct { uint8_t status; int32_t nresults; Value err; uint64_t stack_needed; uint8_t* continuation; } NativeCallResult;
]]

local route = moon.func { decode = vm.regions_native.decode_native_result } [[
route_native(result: ptr(NativeCallResult)): i32
    return region: i32
    entry start()
        emit @{decode}(result;
            returned = returned, yielded = yielded, error = err,
            oom = oom, stack_grow = grow, reenter_lua = reenter,
            invalid = invalid)
    end
    block returned(nres: i32) return nres end
    block yielded(nres: i32) return -100 - nres end
    block err(err: Value) return -200 - as(i32, err.aux) end
    block oom() return -300 end
    block grow(needed: index) return -400 - as(i32, needed) end
    block reenter() return -500 end
    block invalid() return -600 end
    end
end
]]:compile()

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1; print("  PASS " .. name)
    else fail = fail + 1; print("  FAIL " .. name) end
end

print("=== VM native ABI contract ===\n")
local r = ffi.new("NativeCallResult[1]")
r[0].status = const.NativeResult.OK; r[0].nresults = 2
check("OK returns nresults", route(r) == 2)
r[0].status = const.NativeResult.YIELD; r[0].nresults = 3
check("YIELD routes yielded", route(r) == -103)
r[0].status = const.NativeResult.ERROR; r[0].err.aux = 14
check("ERROR routes error object", route(r) == -214)
r[0].status = const.NativeResult.OOM
check("OOM routes oom", route(r) == -300)
r[0].status = const.NativeResult.STACK_GROW; r[0].stack_needed = 7
check("STACK_GROW routes needed size", route(r) == -407)
r[0].status = const.NativeResult.REENTER_LUA
check("REENTER_LUA routes explicitly", route(r) == -500)
r[0].status = const.NativeResult.INVALID
check("INVALID routes invalid", route(r) == -600)
route:free()

local invoke_route = moon.func {
    invoke = vm.regions_native.invoke_native,
    sys_realloc = vm.regions_allocator.sys_realloc,
} [[
invoke_nil(): i32
    let ctx: NativeCallContext = {
        func_slot = 0,
        nargs = 0,
        wanted = 0,
        result_base = 0,
        stack_top = 0,
        yieldable = 0,
        reserved = 0,
        resume = {
            kind = 0, a = 0, b = 0, c = 0,
            pc = 0, base = 0, result_base = 0, call_top = 0,
            wanted = 0,
            value = { tag = 0, aux = 0, bits = 0 },
            errfunc_slot = 0
        }
    }
    return region: i32
    entry start()
        emit @{invoke}(as(ptr(LuaThread), as(u64, 0)), as(ptr(CClosure), as(u64, 0)), ctx;
            returned = returned,
            yielded = yielded,
            error = err,
            oom = oom,
            stack_grow = grow,
            reenter_lua = reenter,
            invalid = invalid)
    end
    block returned(nres: i32) return 1 end
    block yielded(nres: i32) return 2 end
    block err(err: Value) return 3 end
    block oom() return 4 end
    block grow(needed: index) return 5 end
    block reenter() return 6 end
    block invalid() return 7 end
    end
end
]]:compile()
check("invoke_native rejects nil boundary explicitly", invoke_route() == 7)
invoke_route:free()

print(string.format("\n=== %d/%d passed ===", pass, pass + fail))
assert(fail == 0)
return true
