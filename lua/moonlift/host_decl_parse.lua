local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local H = T.MoonHost

    local phase = pvm.phase("moonlift_host_decl_parse", {
        [H.HostDeclSourceSet] = function(self)
            return pvm.once(self.set)
        end,
        [H.HostDeclSourceDecls] = function(self)
            return pvm.once(H.HostDeclSet(self.decls))
        end,
        [H.HostDeclSet] = function(self)
            return pvm.once(self)
        end,
        [H.MluaParseResult] = function(self)
            return pvm.once(self.decls)
        end,
    })

    local function parse(source)
        return pvm.one(phase(source))
    end

    return {
        phase = phase,
        parse = parse,
    }
end

return M
