-- Lua Interpreter VM — Opcode factory compatibility shim
--
-- The old version generated Lalin source through Lua string concatenation.
-- That violates the VM's type-first implementation rule.  Opcode handlers now
-- live as typed hosted regions in op_handlers.lua, and dispatch metadata lives in
-- opcodes.lua.  Keep only the shared constant table for any external tooling that
-- used op_factory.ALL.

local lalin = require("lalin")
local const = require("experiments.lua_interpreter_vm.src.constants")

local values = {}
for k, v in pairs(const.Tag) do values["TAG_" .. k] = lalin.int(v) end
for k, v in pairs(const.Err) do values["ERR_" .. k] = lalin.int(v) end
for k, v in pairs(const.Resume) do values["RESUME_" .. k] = lalin.int(v) end
for k, v in pairs(const.TM) do values["TM_" .. k] = lalin.int(v) end
for k, v in pairs(const.Op) do values["OP_" .. k] = lalin.int(v) end
for k, v in pairs(const.ProtoFlag) do values["PF_" .. k] = lalin.int(v) end

return {
    ALL = values,
}
