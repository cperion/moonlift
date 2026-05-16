-- emit_mom_objects.lua — Pre-compile MOM .mlua modules to .o files.
--
-- Usage: luajit scripts/emit_mom_objects.lua [output_dir]
--
-- Requires a built moonlift binary (or libmoonlift.so) for the Cranelift backend.

package.path = "./lua/?.lua;" .. package.path

local mom_modules = {
    { path = "lua/moonlift/mom/parser/document_scan.mlua",  name = "mom_document_scan" },
    { path = "lua/moonlift/mom/parser/native_lexer.mlua",   name = "mom_native_lexer" },
    { path = "lua/moonlift/mom/parser/native_core.mlua",    name = "mom_native_core" },
    { path = "lua/moonlift/mom/parser/native_tree.mlua",    name = "mom_native_tree" },
    { path = "lua/moonlift/mom/driver/lower_wire.mlua",    name = "mom_lower_wire" },
    { path = "lua/moonlift/mom/driver/backend_ffi.mlua",   name = "mom_backend_ffi" },
    { path = "lua/moonlift/mom/driver/wire.mlua",          name = "mom_wire" },
    { path = "lua/moonlift/mom/runtime/builders.mlua",     name = "mom_builders" },
    { path = "lua/moonlift/mom/runtime/sets.mlua",         name = "mom_sets" },
    { path = "lua/moonlift/mom/back/ids.mlua",             name = "mom_back_ids" },
    { path = "lua/moonlift/mom/back/env.mlua",             name = "mom_back_env" },
    { path = "lua/moonlift/mom/back/ops.mlua",             name = "mom_back_ops" },
    { path = "lua/moonlift/mom/back/cmd.mlua",             name = "mom_back_cmd" },
    { path = "lua/moonlift/mom/back/expr_lower.mlua",      name = "mom_back_expr_lower" },
    { path = "lua/moonlift/mom/back/stmt_lower.mlua",      name = "mom_back_stmt_lower" },
    { path = "lua/moonlift/mom/back/control.mlua",         name = "mom_back_control" },
    { path = "lua/moonlift/mom/back/validate.mlua",        name = "mom_back_validate" },
    { path = "lua/moonlift/mom/vec/vec_facts.mlua",        name = "mom_vec_facts" },
    { path = "lua/moonlift/mom/vec/vec_decide.mlua",       name = "mom_vec_decide" },
    { path = "lua/moonlift/mom/vec/vec_plan.mlua",         name = "mom_vec_plan" },
    { path = "lua/moonlift/mom/vec/vec_lower.mlua",         name = "mom_vec_lower" },
}

local output_dir = arg[1] or "target/mom_objs"

local lfs_ok, lfs = pcall(require, "lfs")
if lfs_ok then
    lfs.mkdir(output_dir)
else
    os.execute("mkdir -p " .. output_dir)
end

local moon = require("moonlift")

local results = {}
local failed = {}

for _, mod_info in ipairs(mom_modules) do
    local path, name = mod_info.path, mod_info.name
    print("emitting: " .. name .. " (" .. path .. ")")
    local ok, mod = pcall(moon.loadfile, path)
    if not ok then
        print("  LOAD FAILED: " .. tostring(mod))
        failed[#failed + 1] = { name = name, path = path, error = "load: " .. tostring(mod) }
    else
        local mod_val = mod
        if type(mod_val) == "function" then mod_val = mod_val() end
        local obj_path = output_dir .. "/" .. name .. ".o"
        local emit_ok, result = pcall(function()
            local artifact = mod_val:emit_object({ module_name = name })
            artifact:write(obj_path)
            return artifact
        end)
        if not emit_ok then
            print("  EMIT FAILED: " .. tostring(result))
            failed[#failed + 1] = { name = name, path = path, error = "emit: " .. tostring(result) }
        else
            local exports = {}
            for k, v in pairs(mod_val.exports or {}) do
                exports[#exports + 1] = k
            end
            table.sort(exports)
            results[#results + 1] = { name = name, path = path, obj_path = obj_path, exports = exports }
            print("  OK: " .. obj_path .. " (" .. #exports .. " exports)")
        end
    end
end

if #failed > 0 then
    print("\n=== FAILURES ===")
    for _, f in ipairs(failed) do
        print(f.name .. ": " .. f.error)
    end
    os.exit(1)
end

print("\n=== EMIT COMPLETE: " .. #results .. " modules, " .. #failed .. " failures ===")