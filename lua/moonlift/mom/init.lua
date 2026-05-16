-- MOM compilation driver.
--
-- Loads all .mlua module tables, concatenates their func/type values,
-- registers everything on a ModuleValue, and compiles.

local Host = require("moonlift.mlua_run")

local M = {}

-- All source files in dependency order.
M.sources = {
    -- Phase 0: runtime and data structures
    "lua/moonlift/mom/runtime/builders.mlua",
    "lua/moonlift/mom/runtime/sets.mlua",
    -- Phase 1: backend infrastructure
    "lua/moonlift/mom/back/ids.mlua",
    "lua/moonlift/mom/back/ops.mlua",
    "lua/moonlift/mom/back/env.mlua",
    "lua/moonlift/mom/back/cmd.mlua",
    "lua/moonlift/mom/back/control.mlua",
    "lua/moonlift/mom/back/validate.mlua",
    "lua/moonlift/mom/back/expr_lower.mlua",
    "lua/moonlift/mom/back/stmt_lower.mlua",
    "lua/moonlift/mom/back/back_abi.mlua",
    -- Phase 2: type system
    "lua/moonlift/mom/typecheck/type_scalar.mlua",
    "lua/moonlift/mom/typecheck/type_env.mlua",
    "lua/moonlift/mom/typecheck/type_check.mlua",
    "lua/moonlift/mom/typecheck/type_expr.mlua",
    "lua/moonlift/mom/typecheck/type_stmt.mlua",
    "lua/moonlift/mom/typecheck/type_control.mlua",
    "lua/moonlift/mom/typecheck/type_module.mlua",
    -- Phase 3: layout resolution
    "lua/moonlift/mom/layout/layout_env.mlua",
    "lua/moonlift/mom/layout/layout_field.mlua",
    "lua/moonlift/mom/layout/layout_resolve.mlua",
    -- Phase 4: driver / wire / backend
    "lua/moonlift/mom/driver/wire.mlua",
    "lua/moonlift/mom/driver/lower_wire.mlua",
    "lua/moonlift/mom/driver/backend_ffi.mlua",
    "lua/moonlift/mom/driver/compile_module.mlua",
    "lua/moonlift/mom/driver/native_entry.mlua",
    -- Phase 5: vectorization (skeletons)
    "lua/moonlift/mom/vec/vec_facts.mlua",
    "lua/moonlift/mom/vec/vec_decide.mlua",
    "lua/moonlift/mom/vec/vec_lower.mlua",
    "lua/moonlift/mom/vec/vec_plan.mlua",
    -- Phase 6: parser (native compiler frontend)
    "lua/moonlift/mom/parser/document_scan.mlua",
    "lua/moonlift/mom/parser/native_lexer.mlua",
    "lua/moonlift/mom/parser/native_core.mlua",
    "lua/moonlift/mom/parser/native_tree.mlua",
}

-- Load all .mlua source tables and concatenate into a flat scope.
-- Returns the scope table and the runtime (for module creation).
function M.load(sources)
    sources = sources or M.sources
    local scope = {}
    local rt
    for i, path in ipairs(sources) do
        local carrier
        if i == 1 then
            carrier, rt = Host.loadfile(path)
        else
            carrier = Host.loadfile(path, {runtime = rt})
        end
        local result = carrier()
        if type(result) == "function" then
            result(scope)
        elseif type(result) == "table" then
            for k, v in pairs(result) do
                scope[k] = v
            end
        end
    end
    return scope, rt
end

-- Compile a scope table into a module.
-- scope: flat table of func/type values (from M.load or manually assembled).
-- opts.runtime: mlua runtime (from M.load).
-- opts.name: module name (default "mom").
function M.compile(scope, opts)
    opts = opts or {}
    local rt = opts.runtime
    local name = opts.name or "mom"
    local Mod = rt.session:api().module(name)

    -- Register types first, then funcs.
    for _, v in pairs(scope) do
        if type(v) == "table" and (v.kind == "struct" or v.kind == "union" or v.kind == "struct_draft") then
            Mod:add_type(v)
        end
    end
    for _, v in pairs(scope) do
        if type(v) == "table" and v.visibility ~= nil and v.name ~= nil
           and not (v.kind == "struct" or v.kind == "union" or v.kind == "struct_draft") then
            Mod:add_func(v)
        end
    end

    return Mod:compile()
end

-- Emit a scope table as a single relocatable object file.
-- scope: flat table of func/type values (from M.load or manually assembled).
-- opts.runtime: mlua runtime (from M.load).
-- opts.name: module name (default "mom").
-- opts.module_name: Cranelift object module name (defaults to opts.name).
-- Returns ObjectArtifact with :bytes() and :write(path).
function M.emit_object(scope, opts)
    opts = opts or {}
    local rt = opts.runtime
    local name = opts.name or "mom"
    local Mod = rt.session:api().module(name)

    for _, v in pairs(scope) do
        if type(v) == "table" and (v.kind == "struct" or v.kind == "union" or v.kind == "struct_draft") then
            Mod:add_type(v)
        end
    end
    for _, v in pairs(scope) do
        if type(v) == "table" and v.visibility ~= nil and v.name ~= nil
           and not (v.kind == "struct" or v.kind == "union" or v.kind == "struct_draft") then
            Mod:add_func(v)
        end
    end

    return Mod:emit_object({ module_name = opts.module_name or name })
end

-- Convenience: load + emit_object in one call.
function M.build_object(sources, opts)
    local scope, rt = M.load(sources)
    opts = opts or {}
    opts.runtime = rt
    return M.emit_object(scope, opts)
end

-- Convenience: load + compile in one call.
function M.build(sources, opts)
    local scope, rt = M.load(sources)
    opts = opts or {}
    opts.runtime = rt
    return M.compile(scope, opts)
end

-- Get or create a cached compiled instance of all MOM modules.
-- Returns a CompiledModule with :get(name) for each pipeline function.
function M.get_compiled()
    if M._compiled then return M._compiled end
    M._compiled = M.build()
    return M._compiled
end

-- Compile a flat command tape through validate → wire → backend JIT.
-- ct..cf: parallel arrays of size ncmds (one per command, 7 arrays for tag+a+b+c+d+e+f)
-- Returns artifact pointer (ptr(u8)) or nil + issue_count on failure.
-- The artifact is freed with mom_backend_free_artifact.
function M.compile_cmd_tape(ct, ca, cb, cc, cd, ce, cf, ncmds)
    local ffi = require("ffi")
    local compiled = M.get_compiled()

    local mc_validate_tape = compiled:get("mc_validate_tape")
    local mc_wire_tape = compiled:get("mc_wire_tape")
    local mom_backend_compile_binary = compiled:get("mom_backend_compile_binary")
    local mw_init = compiled:get("mw_init")
    local mw_finish = compiled:get("mw_finish")
    local mw_ok = compiled:get("mw_ok")

    local cv = ncmds + 16
    local it = ffi.new("int32_t[?]", cv); local ia = ffi.new("int32_t[?]", cv)
    local ib = ffi.new("int32_t[?]", cv); local ic = ffi.new("int32_t[?]", cv)
    local icnt = ffi.new("int32_t[1]", 0)
    local ms = ffi.new("int32_t[?]", 64); local mk = ffi.new("int32_t[?]", 64)

    local issues = mc_validate_tape(ct, ca, cb, cc, cd, ce, cf, ncmds,
                                     it, ia, ib, ic, icnt, cv * 2, ms, mk, 64)
    if icnt[0] > 0 then return nil, icnt[0] end

    local wire_cap = ncmds * 18 * 4 + 256
    local wire_data = ffi.new("uint8_t[?]", wire_cap)
    local w = ffi.new("MomWireBuilder")
    w.data = wire_data; w.len = 0; w.cap = wire_cap; w.string_count = 0; w.aux_count = 0; w.error = 0
    mw_init(w, wire_data, wire_cap)
    local written = mc_wire_tape(ct, ca, ncmds, w)
    if not mw_ok(w) then return nil, "wire" end
    mw_finish(w)

    local artifact = mom_backend_compile_binary(wire_data, written)
    return artifact
end

return M
