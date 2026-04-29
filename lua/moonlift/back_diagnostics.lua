local M = {}

function M.Define(T)
    local Back = (T.MoonBack or T.Moon2Back)
    local Vec = (T.MoonVec or T.Moon2Vec)
    assert(Back and Vec, "moonlift.back_diagnostics.Define expects moonlift.asdl in the context")

    local Inspect = require("moonlift.back_inspect").Define(T)
    local VecInspect = require("moonlift.vec_inspect").Define(T)
    local Jit = require("moonlift.back_jit").Define(T)

    local function diagnostics(program, vector_decisions, funcs, opts)
        opts = opts or {}
        local inspection = Inspect.inspect(program)
        local vector = VecInspect.decisions(vector_decisions or {})
        local disassembly = {}
        if funcs ~= nil and #funcs > 0 then
            local jit = Jit.jit()
            local artifact = jit:compile(program)
            for i = 1, #funcs do
                local func = funcs[i]
                local bytes = opts.bytes or 256
                local text = artifact:disasm(func, { bytes = bytes, objdump = opts.objdump, machine = opts.machine, flags = opts.flags })
                disassembly[#disassembly + 1] = Back.BackDisasmInspection(func, text)
            end
            artifact:free()
            jit:free()
        end
        return Back.BackDiagnosticsReport(inspection, vector, disassembly)
    end

    return { diagnostics = diagnostics }
end

return M
