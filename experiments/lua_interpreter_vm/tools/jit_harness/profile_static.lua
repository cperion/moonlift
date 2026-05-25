-- profile_static.lua
-- Profiles bytecode without executing it
-- Per LUA_STENCIL_HARNESS_DESIGN.md §4.5

local M = {}

-- Analyze opcode sequences in a function proto
function M.analyze_proto_bytecode(proto)
    if not proto or not proto.code then
        return {opcodes = {}, sequences = {}}
    end

    local opcodes = {}
    local opcode_names = {}

    -- Extract opcodes from proto.code
    -- proto.code is expected to be a list of instructions
    for i, instruction in ipairs(proto.code) do
        local op_name = instruction.op or instruction[1]
        table.insert(opcodes, {
            pc = i - 1,
            name = op_name,
            instruction = instruction,
        })
        table.insert(opcode_names, op_name)
    end

    return {
        opcodes = opcodes,
        opcode_names = opcode_names,
        total_count = #opcodes,
    }
end

-- Count opcode windows (pairs, triples, quads)
function M.count_opcode_windows(opcodes, max_arity)
    max_arity = max_arity or 4

    local windows = {}
    local window_counts = {}

    -- Generate all n-ary windows
    for arity = 2, math.min(max_arity, 4) do
        local arity_windows = {}

        for i = 1, #opcodes - (arity - 1) do
            local window_ops = {}
            for j = 0, arity - 1 do
                table.insert(window_ops, opcodes[i + j].name)
            end

            local window_key = table.concat(window_ops, "|")
            window_counts[window_key] = (window_counts[window_key] or 0) + 1

            table.insert(arity_windows, {
                pc = opcodes[i].pc,
                key = window_key,
                ops = window_ops,
                arity = arity,
            })
        end

        windows[arity] = arity_windows
    end

    return {
        windows = windows,
        window_counts = window_counts,
    }
end

-- Derive operand shape information
function M.derive_operand_shapes(proto)
    if not proto or not proto.code then
        return {}
    end

    local shapes = {}

    for i, instr in ipairs(proto.code) do
        local shape = {
            pc = i - 1,
            opcode = instr.op or instr[1],
            operands = {},
        }

        -- Analyze operand types
        -- This is proto-format dependent; adjust for actual structure
        for j = 2, #instr do
            local operand = instr[j]
            local operand_type = "unknown"

            if type(operand) == "number" then
                operand_type = "register"
            elseif type(operand) == "string" then
                operand_type = "constant"
            elseif type(operand) == "boolean" then
                operand_type = "immediate"
            end

            table.insert(shape.operands, {
                index = j - 1,
                type = operand_type,
                value = operand,
            })
        end

        shapes[i] = shape
    end

    return shapes
end

-- Derive control flow shapes (branches, fallthrough, etc.)
function M.derive_control_shapes(proto)
    if not proto or not proto.code then
        return {}
    end

    local control_shapes = {}

    for i, instr in ipairs(proto.code) do
        local shape = {
            pc = i - 1,
            opcode = instr.op or instr[1],
            control_kind = "fallthrough",
            targets = {},
        }

        local op = shape.opcode

        -- Classify based on opcode type
        if op == "JMP" or op == "TEST" or op == "TESTSET" then
            shape.control_kind = "conditional_branch"
            table.insert(shape.targets, {kind = "taken", offset = instr[2] or 0})
            table.insert(shape.targets, {kind = "fallthrough"})
        elseif op == "FORPREP" or op == "FORLOOP" then
            shape.control_kind = "loop_control"
            table.insert(shape.targets, {kind = "loop_back", offset = instr[3] or 0})
            table.insert(shape.targets, {kind = "fallthrough"})
        elseif op == "RETURN" or op == "RETURN0" or op == "RETURN1" then
            shape.control_kind = "return"
            shape.targets = {}
        elseif op == "CALL" or op == "TAILCALL" then
            shape.control_kind = "call"
            table.insert(shape.targets, {kind = "fallthrough"})
        else
            shape.control_kind = "fallthrough"
            table.insert(shape.targets, {kind = "fallthrough"})
        end

        control_shapes[i] = shape
    end

    return control_shapes
end

-- Derive static liveness (backward analysis)
function M.derive_static_liveness(proto, control_shapes)
    if not proto or not proto.code then
        return {}
    end

    local liveness = {}
    local n = #proto.code

    -- Simple forward pass: assume all registers live at each point
    for i = 1, n do
        liveness[i] = {
            pc = i - 1,
            live_in = {},
            live_out = {},
            uses = {},
            defs = {},
        }
    end

    -- Backward pass: refine liveness
    for i = n, 1, -1 do
        local instr = proto.code[i]
        local shape = liveness[i]

        -- Add targets' live_in to this instruction's live_out
        if control_shapes and control_shapes[i] then
            local ctrl = control_shapes[i]
            for _, target in ipairs(ctrl.targets) do
                if target.kind == "fallthrough" and i < n then
                    for j, v in ipairs(liveness[i + 1].live_in) do
                        shape.live_out[j] = v
                    end
                end
            end
        end

        -- For now, conservatively mark all registers as live
        for reg = 0, 255 do
            shape.live_in[reg] = true
            shape.live_out[reg] = true
        end
    end

    return liveness
end

-- Profile a proto bundle statically
function M.profile_proto_static(bundle, config)
    config = config or {}

    if not bundle or not bundle.protos then
        return {protos = {}, total_opcodes = 0}
    end

    local profile = {
        protos = {},
        total_opcodes = 0,
        total_windows = 0,
        window_counts = {},
    }

    -- Analyze each proto in the bundle
    for i, proto in ipairs(bundle.protos) do
        local bytecode = M.analyze_proto_bytecode(proto)
        local windows = M.count_opcode_windows(bytecode.opcodes, config.max_arity or 4)
        local operand_shapes = M.derive_operand_shapes(proto)
        local control_shapes = M.derive_control_shapes(proto)
        local liveness = M.derive_static_liveness(proto, control_shapes)

        profile.protos[i] = {
            id = i,
            bytecode = bytecode,
            windows = windows,
            operand_shapes = operand_shapes,
            control_shapes = control_shapes,
            liveness = liveness,
        }

        profile.total_opcodes = profile.total_opcodes + bytecode.total_count

        -- Aggregate window counts
        for window_key, count in pairs(windows.window_counts) do
            profile.window_counts[window_key] = (profile.window_counts[window_key] or 0) + count
            profile.total_windows = profile.total_windows + 1
        end
    end

    return profile
end

-- Report static profile statistics
function M.report_static_profile(profile)
    print("\n=== Static Bytecode Profile ===")
    print(string.format("Protos analyzed: %d", #profile.protos))
    print(string.format("Total opcodes: %d", profile.total_opcodes))
    print(string.format("Total opcode windows: %d", profile.total_windows))

    print("\n  Top opcode windows:")
    local sorted_windows = {}
    for window_key, count in pairs(profile.window_counts) do
        table.insert(sorted_windows, {key = window_key, count = count})
    end
    table.sort(sorted_windows, function(a, b) return a.count > b.count end)

    for i = 1, math.min(10, #sorted_windows) do
        local w = sorted_windows[i]
        print(string.format("    %s: %d occurrences", w.key, w.count))
    end
end

return M
