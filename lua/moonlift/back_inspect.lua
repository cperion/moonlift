local M = {}

function M.Define(T)
    local Back = (T.MoonBack or T.Moon2Back)
    assert(Back, "moonlift.back_inspect.Define expects moonlift.asdl in the context")

    local function sorted_counts(counts)
        local keys = {}
        for k in pairs(counts) do keys[#keys + 1] = k end
        table.sort(keys)
        local out = {}
        for i = 1, #keys do out[#out + 1] = Back.BackCommandCount(keys[i], counts[keys[i]]) end
        return out
    end

    local function inspect(program)
        local counts = {}
        local targets = {}
        local memory = {}
        local addresses = {}
        local pointer_offsets = {}
        local aliases = {}
        local int_semantics = {}
        local float_semantics = {}

        for index = 1, #program.cmds do
            local cmd = program.cmds[index]
            counts[cmd.kind] = (counts[cmd.kind] or 0) + 1
            if cmd.kind == "CmdTargetModel" then
                targets[#targets + 1] = cmd.target
            elseif cmd.kind == "CmdPtrOffset" then
                pointer_offsets[#pointer_offsets + 1] = Back.BackPointerOffsetInspection(index, cmd.dst, cmd.base, cmd.index, cmd.elem_size, cmd.const_offset, cmd.provenance, cmd.bounds)
            elseif cmd.kind == "CmdLoadInfo" or cmd.kind == "CmdStoreInfo" then
                local m = cmd.memory
                memory[#memory + 1] = Back.BackMemoryInspection(index, m.access, m.alignment, m.dereference, m.trap, m.motion, m.mode)
                addresses[#addresses + 1] = Back.BackAddressInspection(index, cmd.addr)
            elseif cmd.kind == "CmdAliasFact" then
                aliases[#aliases + 1] = Back.BackAliasInspection(index, cmd.fact)
            elseif cmd.kind == "CmdIntBinary" then
                int_semantics[#int_semantics + 1] = Back.BackIntSemanticsInspection(index, cmd.dst, cmd.op, cmd.scalar, cmd.semantics)
            elseif cmd.kind == "CmdFloatBinary" then
                float_semantics[#float_semantics + 1] = Back.BackFloatSemanticsInspection(index, cmd.dst, Back.BackFloatSemanticBinary(cmd.op), cmd.scalar, cmd.semantics)
            elseif cmd.kind == "CmdFma" then
                float_semantics[#float_semantics + 1] = Back.BackFloatSemanticsInspection(index, cmd.dst, Back.BackFloatSemanticFma, cmd.ty, cmd.semantics)
            end
        end

        return Back.BackInspectionReport(sorted_counts(counts), targets, memory, addresses, pointer_offsets, aliases, int_semantics, float_semantics)
    end

    return { inspect = inspect }
end

return M
