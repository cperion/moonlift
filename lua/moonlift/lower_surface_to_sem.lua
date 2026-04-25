package.path = "./?.lua;./?/init.lua;" .. package.path

local M = {}

function M.Define()
    error("moonlift.lower_surface_to_sem is retired; use moonlift.lower_surface_to_elab_top + moonlift.lower_elab_to_sem, or the canonical moonlift.source pipeline helpers", 2)
end

return M
