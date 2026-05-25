-- Runtime checks for real Moonlift JIT structural functions/regions.
--
-- This executes compiled Moonlift code over the JIT product surface.  It is not
-- a Lua planner or native-byte probe.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local moon = require("moonlift")
local jit = require("experiments.lua_interpreter_vm.src.jit")
local C = jit.constants
local F = jit.funcs
local R = jit.regions

local pass, fail = 0, 0
local function check(name, cond, detail)
    if cond then
        pass = pass + 1
    else
        fail = fail + 1
        print("FAIL: " .. name .. (detail and (" -- " .. tostring(detail)) or ""))
    end
end

local probe = moon.func {
    has = F.jit_effect_has_flag,
    proj_flags = F.jit_effect_projection_flags,
    bound_flags = F.jit_effect_boundary_flags,
    status_boundary = F.jit_status_is_boundary,
    status_exit = F.jit_status_is_exit,
    classify = R.classify_effect,
    E_ALLOC = moon.int(C.Effect.MAY_ALLOC),
    E_GC = moon.int(C.Effect.MAY_GC),
    E_CALL_LUA = moon.int(C.Effect.MAY_CALL_LUA),
    E_THROW = moon.int(C.Effect.MAY_THROW),
    E_BRANCH = moon.int(C.Effect.MAY_BRANCH),
    P_ROOTS = moon.int(C.ProjectionReq.ROOTS),
    P_RESUME = moon.int(C.ProjectionReq.RESUME),
    P_ERROR = moon.int(C.ProjectionReq.ERROR),
    P_TARGET = moon.int(C.ProjectionReq.TARGET),
    B_ALLOC = moon.int(C.BoundaryReq.ALLOCATOR),
    B_GC = moon.int(C.BoundaryReq.GC_SAFEPOINT),
    B_LUA = moon.int(C.BoundaryReq.LUA_CALL),
    B_RET = moon.int(C.BoundaryReq.VM_RETURN),
    S_OK = moon.int(C.ExecutionStatus.OK),
    S_SIDE = moon.int(C.ExecutionStatus.SIDE_EXIT),
    S_CALL = moon.int(C.ExecutionStatus.CALL_BOUNDARY),
} [[
jit_structural_probe(which: i32) -> i32
    let e: Effect = { flags = as(u64, @{E_ALLOC}) | as(u64, @{E_GC}) | as(u64, @{E_CALL_LUA}) | as(u64, @{E_BRANCH}) }
    let p_flags: u64 = @{proj_flags}(e.flags)
    let b_flags: u64 = @{bound_flags}(e.flags)

    if which == 0 then
        if @{has}(e, as(u64, @{E_ALLOC})) then return 1 end
        return 0
    end
    if which == 1 then
        if (p_flags & as(u64, @{P_ROOTS})) ~= 0 and (p_flags & as(u64, @{P_RESUME})) ~= 0 and (p_flags & as(u64, @{P_TARGET})) ~= 0 then return 1 end
        return 0
    end
    if which == 2 then
        if (b_flags & as(u64, @{B_ALLOC})) ~= 0 and (b_flags & as(u64, @{B_GC})) ~= 0 and (b_flags & as(u64, @{B_LUA})) ~= 0 then return 1 end
        return 0
    end
    if which == 3 then
        return region -> i32
        entry start()
            emit @{classify}(e; pure = pure, needs_boundary = needs_b, needs_projection = needs_p)
        end
        block pure() yield 0 end
        block needs_b(flags: u64)
            if (flags & as(u64, @{B_LUA})) ~= 0 then yield 1 end
            yield 2
        end
        block needs_p(flags: u64) yield 3 end
        end
    end
    if which == 4 then
        if @{status_boundary}(as(u32, @{S_CALL})) then return 1 end
        return 0
    end
    if which == 5 then
        if @{status_exit}(as(u32, @{S_SIDE})) then return 1 end
        return 0
    end
    if which == 6 then
        let e2: Effect = { flags = as(u64, @{E_THROW}) }
        let p2: u64 = @{proj_flags}(e2.flags)
        let b2: u64 = @{bound_flags}(e2.flags)
        if (p2 & as(u64, @{P_ERROR})) ~= 0 and (b2 & as(u64, @{B_RET})) ~= 0 then return 1 end
        return 0
    end
    return -1
end
]]

local compiled = assert(probe:compile())
for i = 0, 6 do
    check("probe " .. i, compiled(i) == 1, compiled(i))
end
compiled:free()

print(string.format("JIT structural funcs: %d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
