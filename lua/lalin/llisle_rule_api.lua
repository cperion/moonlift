local M = {}

local Api = {}
Api.__index = Api

function Api:run(relation, input, output_name, missing)
    local result, err = self.engine:run(relation, input)
    if result == nil then return nil, err and err.message or missing or ("no Llisle result for " .. tostring(relation)) end
    if output_name == nil then return result.output, nil end
    return result.output[output_name], nil
end

function M.new(rules, engine, extra)
    local api = setmetatable({
        rules = rules,
        engine = engine,
    }, Api)
    if extra then
        for k, v in pairs(extra) do api[k] = v end
    end
    return api
end

return M
