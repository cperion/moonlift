-- Moonlift Lua VM JIT — product-level functions.
--
-- These are real Moonlift functions over the JIT product tree.  They encode
-- structural obligations such as effect -> projection/boundary requirements.
-- They do not select stencils or execute code.

local moon = require("moonlift")
local C = require("experiments.lua_interpreter_vm.src.jit.constants")
require("experiments.lua_interpreter_vm.src.jit.products")

local V = {}
for k, v in pairs(C.Effect) do V["EFF_" .. k] = moon.int(v) end
for k, v in pairs(C.ProjectionReq) do V["PROJ_" .. k] = moon.int(v) end
for k, v in pairs(C.BoundaryReq) do V["BOUND_" .. k] = moon.int(v) end
for k, v in pairs(C.ExecutionStatus) do V["STATUS_" .. k] = moon.int(v) end

local jit_flags_has_flag = moon.func(V) [[
jit_flags_has_flag(flags: u64, flag: u64) -> bool
    return (flags & flag) ~= 0
end
]]

local jit_effect_has_flag = moon.func(V) [[
jit_effect_has_flag(e: Effect, flag: u64) -> bool
    return (e.flags & flag) ~= 0
end
]]

local jit_effect_projection_flags = moon.func(V) [[
jit_effect_projection_flags(flags_in: u64) -> u64
    var flags: u64 = 0

    if (flags_in & @{EFF_MAY_ALLOC}) ~= 0 or (flags_in & @{EFF_MAY_GC}) ~= 0 then
        flags = flags | @{PROJ_ROOTS}
    end
    if (flags_in & @{EFF_MAY_CALL_LUA}) ~= 0 or (flags_in & @{EFF_MAY_YIELD}) ~= 0 then
        flags = flags | @{PROJ_ROOTS} | @{PROJ_RESUME}
    end
    if (flags_in & @{EFF_MAY_RUN_HOOK}) ~= 0 then
        flags = flags | @{PROJ_ROOTS} | @{PROJ_RESUME} | @{PROJ_DEBUG}
    end
    if (flags_in & @{EFF_MAY_OBSERVE_STACK}) ~= 0 then
        flags = flags | @{PROJ_INTERPRETER}
    end
    if (flags_in & @{EFF_MAY_THROW}) ~= 0 then
        flags = flags | @{PROJ_ERROR}
    end
    if (flags_in & @{EFF_MAY_NEED_BARRIER}) ~= 0 then
        flags = flags | @{PROJ_BARRIER}
    end
    if (flags_in & @{EFF_MAY_BRANCH}) ~= 0 then
        flags = flags | @{PROJ_TARGET}
    end

    return flags
end
]]

local jit_effect_boundary_flags = moon.func(V) [[
jit_effect_boundary_flags(flags_in: u64) -> u64
    var flags: u64 = 0

    if (flags_in & @{EFF_MAY_ALLOC}) ~= 0 then
        flags = flags | @{BOUND_ALLOCATOR}
    end
    if (flags_in & @{EFF_MAY_GC}) ~= 0 then
        flags = flags | @{BOUND_GC_SAFEPOINT}
    end
    if (flags_in & @{EFF_MAY_CALL_LUA}) ~= 0 then
        flags = flags | @{BOUND_LUA_CALL}
    end
    if (flags_in & @{EFF_MAY_CALL_METAMETHOD}) ~= 0 then
        flags = flags | @{BOUND_METAMETHOD}
    end
    if (flags_in & @{EFF_MAY_THROW}) ~= 0 or (flags_in & @{EFF_MAY_OBSERVE_STACK}) ~= 0 then
        flags = flags | @{BOUND_VM_RETURN}
    end

    return flags
end
]]

local jit_effect_to_projection_requirement = moon.func(V) [[
jit_effect_to_projection_requirement(e: Effect) -> ProjectionRequirement
    return { flags = jit_effect_projection_flags(e.flags) }
end
]]

local jit_effect_to_boundary_requirement = moon.func(V) [[
jit_effect_to_boundary_requirement(e: Effect) -> BoundaryRequirement
    return { flags = jit_effect_boundary_flags(e.flags) }
end
]]

local jit_projection_requires = moon.func(V) [[
jit_projection_requires(req: ProjectionRequirement, flag: u64) -> bool
    return (req.flags & flag) ~= 0
end
]]

local jit_boundary_requires = moon.func(V) [[
jit_boundary_requires(req: BoundaryRequirement, flag: u64) -> bool
    return (req.flags & flag) ~= 0
end
]]

local jit_range_contains_pc = moon.func(V) [[
jit_range_contains_pc(r: SemanticRange, pc: index) -> bool
    return pc >= r.start_pc and pc < r.end_pc
end
]]

local jit_semantic_addr_eq = moon.func(V) [[
jit_semantic_addr_eq(a: SemanticAddr, b: SemanticAddr) -> bool
    return a.proto == b.proto and a.pc == b.pc and a.frame == b.frame
end
]]

local jit_plan_node_count = moon.func(V) [[
jit_plan_node_count(plan: ptr(StencilPlan)) -> index
    if plan == nil then return 0 end
    return plan.node_count
end
]]

local jit_plan_has_work = moon.func(V) [[
jit_plan_has_work(plan: ptr(StencilPlan)) -> bool
    if plan == nil then return false end
    return plan.node_count > 0
end
]]

local jit_status_is_boundary = moon.func(V) [[
jit_status_is_boundary(status: u32) -> bool
    return status == as(u32, @{STATUS_CALL_BOUNDARY}) or status == as(u32, @{STATUS_RUNTIME_BOUNDARY})
end
]]

local jit_status_is_exit = moon.func(V) [[
jit_status_is_exit(status: u32) -> bool
    return status == as(u32, @{STATUS_SIDE_EXIT}) or status == as(u32, @{STATUS_ERROR})
end
]]

local jit_outcome_is_boundary = moon.func(V) [[
jit_outcome_is_boundary(out: NativeJitOutcome) -> bool
    return jit_status_is_boundary(out.status)
end
]]

local jit_outcome_is_exit = moon.func(V) [[
jit_outcome_is_exit(out: NativeJitOutcome) -> bool
    return jit_status_is_exit(out.status)
end
]]

return {
    jit_flags_has_flag = jit_flags_has_flag,
    jit_effect_has_flag = jit_effect_has_flag,
    jit_effect_projection_flags = jit_effect_projection_flags,
    jit_effect_boundary_flags = jit_effect_boundary_flags,
    jit_effect_to_projection_requirement = jit_effect_to_projection_requirement,
    jit_effect_to_boundary_requirement = jit_effect_to_boundary_requirement,
    jit_projection_requires = jit_projection_requires,
    jit_boundary_requires = jit_boundary_requires,
    jit_range_contains_pc = jit_range_contains_pc,
    jit_semantic_addr_eq = jit_semantic_addr_eq,
    jit_plan_node_count = jit_plan_node_count,
    jit_plan_has_work = jit_plan_has_work,
    jit_status_is_boundary = jit_status_is_boundary,
    jit_status_is_exit = jit_status_is_exit,
    jit_outcome_is_boundary = jit_outcome_is_boundary,
    jit_outcome_is_exit = jit_outcome_is_exit,
}
