-- StateOp → Moonlift code generation with correct Moonlift syntax.
-- Uses proper pointer indexing, type inference, and memory operations.

local M = {}

-- Hole markers for scan-and-replace at runtime
local HOLE_SLOT_DISP = 0x5a5a5a5a      -- 4-byte stack slot offset
local HOLE_IMM32 = 0x3d3d3d3d            -- 4-byte immediate
local HOLE_TAG_CONST = 0x44332211        -- 4-byte tag constant

-- Generate a Moonlift function from a StateOp sequence
function M.generate_function(candidate)
    local name = candidate.name or ("compound_" .. candidate.id)
    local sanitized_name = string.gsub(name, "[^a-z0-9_]", "_")
    local ops = candidate.ops or {}

    if not ops or #ops == 0 then
        return nil, "no operations in candidate"
    end

    local lines = {}
    local holes_list = {}
    local var_scope = {}  -- Track which variables are defined

    -- Function signature - stencil ABI
    lines[#lines + 1] = string.format("func %s(state: ptr(u8), exits: ptr(ptr(u8)), return_addr: ptr(u8)) -> ptr(u8)", sanitized_name)

    -- Process each StateOp
    for i, op in ipairs(ops) do
        local op_name = op.op
        local args = op.args or {}

        if op_name == "ConstInt" then
            -- ConstInt: create a constant value
            -- Use a distinctive marker for the immediate
            local imm_name = args.value or "imm"
            local var = "v_" .. string.gsub(imm_name, "_", "")
            lines[#lines + 1] = string.format("    let %s = %d", var, HOLE_IMM32)
            holes_list[#holes_list + 1] = {kind="imm32", name=imm_name}
            var_scope[imm_name] = var

        elseif op_name == "ReadSlot" then
            -- ReadSlot: read from state buffer at offset
            local slot = args.slot or "slot"
            local var = "v_" .. slot
            -- Use marker for offset, then read from that offset
            lines[#lines + 1] = string.format("    let %s = *(state + %d)", var, HOLE_SLOT_DISP)
            holes_list[#holes_list + 1] = {kind="slot_disp", name=slot}
            var_scope[slot] = var

        elseif op_name == "WriteSlot" then
            -- WriteSlot: write to state buffer at offset
            local slot = args.slot or "slot"
            local value = args.value or "value"
            local val_var = var_scope[value] or ("v_" .. value)
            -- Write through pointer arithmetic
            lines[#lines + 1] = string.format("    *(state + %d) = %s", HOLE_SLOT_DISP, val_var)
            holes_list[#holes_list + 1] = {kind="slot_disp", name=slot}

        elseif op_name == "GuardTag" then
            -- GuardTag: test if value has expected tag, exit if not
            local exit = args.exit or "exit"
            local tag = args.tag or "ANY"
            local value = args.value or "value"
            local val_var = var_scope[value] or ("v_" .. value)
            -- Check tag: if not equal to marker, jump to exit
            lines[#lines + 1] = string.format("    if %s ~= %d then", val_var, HOLE_TAG_CONST)
            lines[#lines + 1] = string.format("        return exits[%d]", HOLE_SLOT_DISP)
            lines[#lines + 1] = "    end"
            holes_list[#holes_list + 1] = {kind="tag_const", name=tag}
            holes_list[#holes_list + 1] = {kind="exit_idx", name=exit}

        elseif op_name == "AddIntWrap" then
            -- AddIntWrap: add two values
            local lhs = args.lhs or "lhs"
            local rhs = args.rhs or "rhs"
            local lhs_var = var_scope[lhs] or ("v_" .. lhs)
            local rhs_var = var_scope[rhs] or ("v_" .. rhs)
            local sum_var = "v_sum"
            lines[#lines + 1] = string.format("    let %s = %s + %s", sum_var, lhs_var, rhs_var)
            var_scope["sum"] = sum_var

        elseif op_name == "LtInt" then
            -- LtInt: less-than comparison
            local lhs = args.lhs or "lhs"
            local rhs = args.rhs or "rhs"
            local lhs_var = var_scope[lhs] or ("v_" .. lhs)
            local rhs_var = var_scope[rhs] or ("v_" .. rhs)
            lines[#lines + 1] = string.format("    let v_lt = %s < %s", lhs_var, rhs_var)
            var_scope["lt"] = "v_lt"

        elseif op_name == "Branch" then
            -- Branch: conditional jump based on comparison
            local cond = args.cond or "cond"
            local true_target = args.true_target or "true_edge"
            local false_target = args.false_target or "false_edge"
            local cond_var = var_scope[cond] or ("v_" .. cond)
            lines[#lines + 1] = string.format("    if %s then", cond_var)
            lines[#lines + 1] = string.format("        return exits[%d]", HOLE_SLOT_DISP)
            lines[#lines + 1] = "    else"
            lines[#lines + 1] = string.format("        return exits[%d]", HOLE_SLOT_DISP)
            lines[#lines + 1] = "    end"
            holes_list[#holes_list + 1] = {kind="exit_idx", name=true_target}
            holes_list[#holes_list + 1] = {kind="exit_idx", name=false_target}

        elseif op_name == "Jump" then
            -- Jump: unconditional jump to exit or fallthrough
            local target = args.target or "next"
            if target == "next" then
                lines[#lines + 1] = "    return return_addr"
            else
                lines[#lines + 1] = string.format("    return exits[%d]", HOLE_SLOT_DISP)
                holes_list[#holes_list + 1] = {kind="exit_idx", name=target}
            end

        elseif op_name == "ProjectSlot" then
            -- ProjectSlot: write value to state for snapshotting
            local slot = args.slot or "slot"
            local value = args.value or "value"
            local val_var = var_scope[value] or ("v_" .. value)
            lines[#lines + 1] = string.format("    *(state + %d) = %s", HOLE_SLOT_DISP, val_var)
            holes_list[#holes_list + 1] = {kind="slot_disp", name=slot}

        else
            lines[#lines + 1] = string.format("    -- TODO: %s", op_name)
        end
    end

    lines[#lines + 1] = "end"
    lines[#lines + 1] = ""

    local source = table.concat(lines, "\n")

    return {
        source = source,
        holes = holes_list,
        name = sanitized_name,
        original_name = name
    }
end

-- Generate a module with all stencil functions
function M.generate_module(candidates)
    if not candidates or #candidates == 0 then
        return nil, "no candidates"
    end

    local lines = {}
    lines[#lines + 1] = "-- Generated stencil functions"
    lines[#lines + 1] = "-- Auto-generated by stencil_codegen_correct.lua"
    lines[#lines + 1] = ""

    local generated = {}
    for i, candidate in ipairs(candidates) do
        if candidate.replacement and candidate.replacement.kind == "code_stencil_needed" then
            local func, err = M.generate_function(candidate)
            if func then
                for line in string.gmatch(func.source, "[^\n]+") do
                    lines[#lines + 1] = line
                end
                generated[#generated + 1] = {
                    name = func.name,
                    original_name = candidate.name,
                    id = candidate.id,
                    holes = func.holes
                }
            else
                io.stderr:write(string.format("warning: skipped %s: %s\n", candidate.name, err))
            end
        end
    end

    return {
        source = table.concat(lines, "\n"),
        generated = generated
    }
end

return M
