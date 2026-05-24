-- JIT contract surface smoke test.
-- Verifies that the canonical contracts module exposes all product types,
-- region headers, and function headers from JIT_DESIGN.md.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local jit = require("experiments.lua_interpreter_vm.src.jit")

local pass, fail = 0, 0
local function check(name, cond)
    if cond then
        pass = pass + 1
    else
        fail = fail + 1
        print("FAIL: " .. name)
    end
end

local function kind_is(v, prefix)
    return tostring(v):match("^" .. prefix) ~= nil or (type(v) == "table" and v.kind)
end

local product_names = {
    "SemanticAddr", "SemanticRange", "Effect", "BoundaryRequirement", "Fact", "FactSet",
    "DependencyKey", "DependencySet", "TypedValue", "VirtualState", "Guard",
    "ProjectedSlot", "ResumeProjection", "ErrorProjection", "DebugProjection", "Projection",
    "MachineLoc", "LoweringAction", "ProjectionLowering", "StateOp", "StencilHole",
    "StencilReloc", "StencilPayload", "CodeStencil", "StencilLibrary", "StencilConfig",
    "StencilNode", "CodeFixup", "StencilPlan", "CodeSlab", "CodeArena",
    "X64Mem", "X64Operand", "X64Inst", "CompiledCode", "BlockInfo", "LiveSet", "LivenessInfo", "UnitABI",
    "StateShape", "UnitProfile", "ExitProfile", "EdgeCell", "EntryCell", "Boundary",
    "UnitExit", "JitOutcome", "JitRootArea", "JitRuntime", "ExecutableUnit", "DependencyEntry", "DependencyIndex", "ExecImage",
}

local region_names = {
    "discover_blocks", "analyze_liveness", "record_state_program", "build_projection",
    "verify_unit", "allocate_and_lower", "allocate_code_buffer", "materialize_stencil",
    "finalize_code_buffer", "publish_unit", "enter_addr", "execute_boundary",
    "resolve_addr", "patch_edge_cell", "revert_edge_cell", "invalidate_dependency", "reclaim_code",
    "try_enter_jit", "execute_jit_outcome", "project_to_vm_state", "project_roots",
    "record_hot_entry", "mark_jit_roots",
}

local func_names = {
    "effect_to_requirement", "effect_has_flag", "requirement_has_flag", "liveset_contains",
    "typed_value_is_gc_ref", "typed_value_is_numeric", "unit_covers_addr", "edge_current_target",
    "projection_slot_count", "stencil_size", "code_offset_to_rx", "code_offset_to_rw",
}

for _, name in ipairs(product_names) do
    check("product " .. name, jit.products[name] ~= nil and tostring(jit.products[name]):match("^MoonStructValue") ~= nil)
end

for _, name in ipairs(region_names) do
    local r = jit.regions[name]
    check("region " .. name, type(r) == "table" and r.kind == "region_header")
end

for _, name in ipairs(func_names) do
    local f = jit.funcs[name]
    check("func " .. name, type(f) == "table" and f.kind == "func_header")
end

check("constants present", type(jit.constants) == "table" and type(jit.constants.Effect.MAY_GC) == "number")

print(string.format("JIT contracts: %d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
