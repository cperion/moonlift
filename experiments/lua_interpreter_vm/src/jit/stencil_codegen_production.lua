-- StateOp → Moonlift code generation (production version).
--
-- This generator uses the actual Lua VM patterns as reference and builds
-- proper Moonlift code through source quoting with value binding.

local moon = require("moonlift")
local host = require("moonlift.host")

local M = {}

-- Validate that operations have all their dependencies available before them
-- Only validates the first path (up to first Jump(next) or Branch)
local function validate_ops_ordering(ops)
    local outputs = {}

    for i, op in ipairs(ops) do
        local op_name = op.op
        local args = op.args or {}

        -- Stop at first return/branch - only validate this path
        if (op_name == "Jump" and args.target == "next") or op_name == "Branch" then
            break
        end

        -- Check dependencies based on operation type
        if op_name == "WriteSlot" or op_name == "ProjectSlot" then
            local value = args.value or "value"
            if not outputs[value] and not outputs[string.gsub(value, "_[ui]%d+$", "")] then
                return false, string.format("op %d (%s) references undefined value '%s'", i, op_name, value)
            end
        elseif op_name == "AddIntWrap" or op_name == "LtInt" then
            local lhs = args.lhs or "lhs"
            local rhs = args.rhs or "rhs"
            if not outputs[lhs] and not outputs[string.gsub(lhs, "_[ui]%d+$", "")] then
                return false, string.format("op %d (%s) references undefined lhs '%s'", i, op_name, lhs)
            end
            if not outputs[rhs] and not outputs[string.gsub(rhs, "_[ui]%d+$", "")] then
                return false, string.format("op %d (%s) references undefined rhs '%s'", i, op_name, rhs)
            end
        elseif op_name == "GuardTag" then
            local value = args.value or "value"
            if not outputs[value] and not outputs[string.gsub(value, "_[ui]%d+$", "")] then
                return false, string.format("op %d (GuardTag) references undefined value '%s'", i, value)
            end
        end

        -- Record this operation as producing output
        if op_name == "ReadSlot" then
            outputs[args.slot or "slot"] = true
        elseif op_name == "ConstInt" then
            local value_name = args.value or "imm"
            local base_name = string.gsub(value_name, "_[ui]%d+$", "")
            outputs[base_name] = true
            outputs[value_name] = true
        elseif op_name == "AddIntWrap" then
            outputs["sum"] = true
        elseif op_name == "LtInt" then
            outputs["lt"] = true
        end
    end

    return true
end

-- Build a map of which operation produces which named value
-- Only includes operations before the first Jump(next) or Branch
-- (without modifying the ops array)
local function build_outputs_map(ops)
    local outputs = {}  -- Track which op index produces which named value

    for i, op in ipairs(ops) do
        local op_name = op.op
        local args = op.args or {}

        -- Stop at first return/branch - only map this path
        if (op_name == "Jump" and args.target == "next") or op_name == "Branch" then
            break
        end

        -- Operations that produce values
        if op_name == "ReadSlot" then
            local slot = args.slot or "slot"
            outputs[slot] = i  -- Operation i produced value "slot"

        elseif op_name == "ConstInt" then
            -- Store the canonical output name for this constant
            local value_name = args.value or "imm"
            -- Normalize: extract base name (remove type suffixes like "_i32")
            local base_name = string.gsub(value_name, "_[ui]%d+$", "")
            outputs[base_name] = i  -- This op produces value "base_name"
            outputs[value_name] = i  -- Also track the full name

        elseif op_name == "AddIntWrap" or op_name == "LtInt" then
            -- These produce values (sum/lt)
            -- The output is typically named after the operation (sum, lt)
            local output_name = (op_name == "AddIntWrap" and "sum") or "lt"
            outputs[output_name] = i
        end
    end

    return outputs
end

-- Resolve a value reference to the operation that produced it
-- Only resolves if the operation comes before or at the given current operation index
local function resolve_value(outputs,name, current_op_index)
    local op_index = outputs[name]
    if not op_index then
        -- Try base name (strip type suffixes)
        local base_name = string.gsub(name, "_[ui]%d+$", "")
        op_index = outputs[base_name]
    end

    -- Check if this operation comes before or at the current operation
    if op_index and op_index <= current_op_index then
        return op_index
    end

    return nil
end

-- Build a Moonlift function from StateOp sequence
-- Returns proper Moonlift source that can be compiled
function M.generate_function(candidate)
    local name = candidate.name or ("compound_" .. candidate.id)
    local sanitized_name = string.gsub(name, "[^a-z0-9_]", "_")
    local ops = candidate.ops or {}

    if not ops or #ops == 0 then
        return nil, "no operations in candidate"
    end

    -- Validate that operations have dependencies available before use
    local valid, err = validate_ops_ordering(ops)
    if not valid then
        return nil, "invalid op ordering: " .. err
    end

    -- Build map of which operation produces which named value
    local outputs = build_outputs_map(ops)

    -- Build statements from StateOps
    local stmts = {}
    local var_map = {}  -- Maps operation index to variable name

    for i, op in ipairs(ops) do
        local op_name = op.op
        local args = op.args or {}

        -- Stop at first return - these candidates have multiple paths encoded,
        -- we generate only the first path
        if op_name == "Jump" and args.target == "next" then
            table.insert(stmts, "return return_addr")
            break
        end
        if op_name == "Branch" then
            -- Generate branch code, then stop
            local cond = args.cond or "cond"
            local cond_op = resolve_value(outputs,cond)
            local cond_var = cond_op and var_map[cond_op] or ("v_" .. cond)
            table.insert(stmts, string.format("if %s then", cond_var))
            table.insert(stmts, string.format("    return exits[as(index, %d)]", 0x5a5a5a5a))
            table.insert(stmts, "else")
            table.insert(stmts, string.format("    return exits[as(index, %d)]", 0x5a5a5a5a))
            table.insert(stmts, "end")
            break
        end

        if op_name == "ReadSlot" then
            -- ReadSlot: load from stack at offset
            -- Cast to i64 to avoid type mismatches with other operations
            local slot = args.slot or "slot"
            local var = "v_" .. slot
            table.insert(stmts, string.format("let %s: i64 = as(i64, state[as(index, %d)])", var, 0x5a5a5a5a))
            var_map[i] = var

        elseif op_name == "WriteSlot" then
            -- WriteSlot: store to stack at offset
            -- Cast back to u8 for storage
            local slot = args.slot or "slot"
            local value = args.value or "value"
            -- Find which operation produced this value
            local src_op = resolve_value(outputs, value, i)
            local src_var = src_op and var_map[src_op] or ("v_" .. value)
            table.insert(stmts, string.format("state[as(index, %d)] = as(u8, %s)", 0x5a5a5a5a, src_var))

        elseif op_name == "ConstInt" then
            -- ConstInt: create constant
            local value_name = args.value or "imm"
            local var = "v_const"
            table.insert(stmts, string.format("let %s: i64 = %d", var, 0x3d3d3d3d))
            var_map[i] = var

        elseif op_name == "GuardTag" then
            -- GuardTag: test tag matches, exit if not
            local value = args.value or "value"
            local src_op = resolve_value(outputs, value, i)
            local src_var = src_op and var_map[src_op] or ("v_" .. value)
            table.insert(stmts, string.format("if %s ~= %d then", src_var, 0x44332211))
            table.insert(stmts, string.format("    return exits[as(index, %d)]", 0x5a5a5a5a))
            table.insert(stmts, "end")

        elseif op_name == "AddIntWrap" then
            -- AddIntWrap: integer addition
            -- Cast both operands to i64 to handle type mismatches (u8 from load + i32 from const)
            local lhs = args.lhs or "lhs"
            local rhs = args.rhs or "rhs"
            local lhs_op = resolve_value(outputs, lhs, i)
            local rhs_op = resolve_value(outputs, rhs, i)
            local lhs_var = lhs_op and var_map[lhs_op] or ("v_" .. lhs)
            local rhs_var = rhs_op and var_map[rhs_op] or ("v_" .. rhs)
            local sum_var = "v_sum"
            table.insert(stmts, string.format("let %s: i64 = as(i64, %s) + as(i64, %s)", sum_var, lhs_var, rhs_var))
            var_map[i] = sum_var

        elseif op_name == "LtInt" then
            -- LtInt: less-than comparison
            -- Cast both operands to i64 to handle type mismatches
            local lhs = args.lhs or "lhs"
            local rhs = args.rhs or "rhs"
            local lhs_op = resolve_value(outputs, lhs, i)
            local rhs_op = resolve_value(outputs, rhs, i)
            local lhs_var = lhs_op and var_map[lhs_op] or ("v_" .. lhs)
            local rhs_var = rhs_op and var_map[rhs_op] or ("v_" .. rhs)
            local lt_var = "v_lt"
            table.insert(stmts, string.format("let %s: bool = as(i64, %s) < as(i64, %s)", lt_var, lhs_var, rhs_var))
            var_map[i] = lt_var


        elseif op_name == "ProjectSlot" then
            -- ProjectSlot: write to snapshot location
            -- Cast back to u8 for storage
            local slot = args.slot or "slot"
            local value = args.value or "value"
            local src_op = resolve_value(outputs, value, i)
            local src_var = src_op and var_map[src_op] or ("v_" .. value)
            table.insert(stmts, string.format("state[as(index, %d)] = as(u8, %s)", 0x5a5a5a5a, src_var))

        else
            table.insert(stmts, string.format("-- TODO: %s", op_name))
        end
    end

    -- Ensure we always have a return
    if #stmts == 0 or not string.match(stmts[#stmts], "return") then
        table.insert(stmts, "return return_addr")
    end

    -- Build the function source
    local body = "    " .. table.concat(stmts, "\n    ")

    local func_src = string.format([[func %s(state: ptr(u8), exits: ptr(ptr(u8)), return_addr: ptr(u8)) -> ptr(u8)
%s
end
]], sanitized_name, body)

    return {
        source = func_src,
        holes = {},  -- Will be populated by ELF scanning
        name = sanitized_name,
        original_name = name
    }
end

-- Generate a complete module
function M.generate_module(candidates)
    if not candidates or #candidates == 0 then
        return nil, "no candidates"
    end

    local lines = {}
    lines[#lines + 1] = "-- Generated stencil functions (production)"
    lines[#lines + 1] = "-- Auto-generated by stencil_codegen_production.lua"
    lines[#lines + 1] = ""

    local generated = {}
    for i, candidate in ipairs(candidates) do
        if candidate.replacement and candidate.replacement.kind == "code_stencil_needed" then
            local func, err = M.generate_function(candidate)
            if func then
                for line in string.gmatch(func.source, "[^\n]+") do
                    lines[#lines + 1] = line
                end
                lines[#lines + 1] = ""
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
