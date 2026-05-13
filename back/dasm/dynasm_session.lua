local encode = require("back.dasm.encode_x64")

local Session = {}
Session.__index = Session

function Session:new()
    encode.init()
    return setmetatable({}, self)
end

function Session:flush_fragments()
    encode.flush()
    return encode.take_fragments()
end

function Session:globals()
    return encode.global_bindings()
end

return {
    new = function()
        return Session:new()
    end,
}
