local M = {}

function M.Define(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.lower_to_c ~= nil then return T._moonlift_api_cache.lower_to_c end

    local CodeToC = require("moonlift.code_to_c").Define(T)

    local api = {}

    local function module(code_module, lower_module, opts)
        -- C lowering is intentionally a pure CodeToC projection for v1.
        -- The new LowerModule fragment plan is accepted but ignored here so C
        -- stays on ordinary Code fallback; this path must not install fake
        -- Kernel/Schedule lowering.  When C kernel lowering exists, it should
        -- consume generic KernelBody + Schedule semantics rather than
        -- special-casing individual reductions or benchmark shapes.
        return CodeToC.module(code_module, opts)
    end

    api.module = module
    api.unit = module

    T._moonlift_api_cache.lower_to_c = api
    return api
end

return M
