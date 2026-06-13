-- Compatibility shim for libraries that were authored against a top-level
-- `pvm` module before Moonlift namespaced its Lua modules.
return require("moonlift.pvm")
