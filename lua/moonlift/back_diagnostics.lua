local function bind_context(T)
    local Back = T.MoonBack
    assert(Back, "moonlift.back_diagnostics(T) expects MoonBack in the context")

    local Inspect = require("moonlift.back_inspect")(T)
    local Jit = require("moonlift.back_jit")(T)

    local function diagnostics(program, _unused, funcs, opts)
        opts = opts or {}
        local inspection = Inspect.inspect(program)
        local disassembly = {}
        if funcs ~= nil and #funcs > 0 then
            local jit = Jit.jit()
            local artifact = jit:compile(Jit.flatline.encode_back_program(program))
            for i = 1, #funcs do
                local func = funcs[i]
                local bytes = opts.bytes or 256
                local text = artifact:disasm(func, { bytes = bytes, objdump = opts.objdump, machine = opts.machine, flags = opts.flags })
                disassembly[#disassembly + 1] = Back.BackDisasmInspection(func, text)
            end
            artifact:free()
            jit:free()
        end
        return Back.BackDiagnosticsReport(inspection, disassembly)
    end

    return { diagnostics = diagnostics }
end

return bind_context