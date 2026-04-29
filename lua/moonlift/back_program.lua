local M = {}

function M.Define(T)
    local Back = T.MoonBack or T.MoonBack
    assert(Back, "moonlift.back_program.Define expects MoonBack/MoonBack in the context")

    local api = {}

    local function copy_cmds(cmds)
        local out = {}
        for i = 1, #(cmds or {}) do out[#out + 1] = cmds[i] end
        return out
    end

    function api.empty()
        return Back.BackProgram({})
    end

    function api.program(cmds)
        return Back.BackProgram(copy_cmds(cmds))
    end

    function api.singleton(cmd)
        return Back.BackProgram({ cmd })
    end

    function api.concat(programs)
        local out = {}
        for i = 1, #(programs or {}) do
            local program = programs[i]
            for j = 1, #program.cmds do out[#out + 1] = program.cmds[j] end
        end
        return Back.BackProgram(out)
    end

    function api.append(program, cmd)
        local out = copy_cmds(program.cmds)
        out[#out + 1] = cmd
        return Back.BackProgram(out)
    end

    function api.extend(program, cmds)
        local out = copy_cmds(program.cmds)
        for i = 1, #(cmds or {}) do out[#out + 1] = cmds[i] end
        return Back.BackProgram(out)
    end

    function api.cmds(program)
        return copy_cmds(program.cmds)
    end

    return api
end

return M
