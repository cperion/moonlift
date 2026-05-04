-- Retired compatibility module name.
--
-- The old host_quote string-concatenation bridge is gone.  The module name now
-- points at the ASDL-hosted .mlua runner so existing require paths fail less
-- mysteriously during the tree-wide migration.  `source` and `translate` are not
-- provided: source quotes are no longer a primary representation.

local Run = require("moonlift.mlua_run")

local M = {}

M.loadstring = Run.loadstring
M.loadfile = Run.loadfile
M.dofile = Run.dofile

function M.source()
    error("Host.source was removed: construct ASDL values or typed host templates instead", 2)
end

function M.translate()
    error("host_quote.translate was removed: use moonlift.mlua_host_model / moonlift.mlua_run", 2)
end

return M
