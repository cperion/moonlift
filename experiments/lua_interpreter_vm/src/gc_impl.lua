-- Lua Interpreter VM — GC implementation (incremental mark-sweep)

local regions_gc = require("experiments.lua_interpreter_vm.src.regions_gc")

-- Export the GC regions directly — the full GC algorithm
-- builds on top of these primitives.
return regions_gc
