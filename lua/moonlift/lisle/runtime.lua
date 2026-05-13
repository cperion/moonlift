local Compile = require("moonlift.lisle.compile")

local M = {}

function M.load(spec_text, module_name, env, opts)
    return Compile.load_source(spec_text, module_name, env, opts)
end

function M.load_file(path, module_name, env, opts)
    return Compile.load_file(path, module_name, env, opts)
end

return M
