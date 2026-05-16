-- emit_mom_precompiled.lua — Precompile all 34 MOM modules into ONE unified .o file.
--
-- This must be run through the moonlift binary:
--   ./target/release/moonlift scripts/emit_mom_precompiled.lua
--
-- Loads all MOM .mlua modules via moonlift.mom.init, combines them into a single
-- unified module, and emits to a single relocatable object file.

local output_path = os.getenv("MOM_OBJ_PATH") or "target/libmom_precompiled.o"

-- Ensure output directory exists
local output_dir = output_path:gsub("/[^/]+$", "")
if output_dir ~= "" then
    os.execute("mkdir -p " .. output_dir)
end

print("Loading Mom.init module compiler...")
local Mom = require("moonlift.mom.init")

print("Loading all 34 MOM modules into unified scope...")
local scope, rt = Mom.load()

print("Emitting unified object file...")
local artifact = Mom.emit_object(scope, {
    runtime = rt,
    name = "mom",
    module_name = "libmom_precompiled"
})

print("Writing: " .. output_path)
artifact:write(output_path)

print("\n✓ Success: 34 MOM modules compiled to single unified object")
print("  " .. output_path)
