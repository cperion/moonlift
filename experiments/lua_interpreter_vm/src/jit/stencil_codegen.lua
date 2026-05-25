-- StateOp → Moonlift code generation for stencil fixture compilation.
--
-- This module translates semantic StateOp sequences (from the stencil promotion
-- plan) into Moonlift function source code. The generated functions can be
-- compiled via moon.emit_object() to produce physical stencil bytes.

local M = {}

-- Hole markers: distinctive byte patterns that appear in compiled code
-- and get replaced by runtime fixups.
local HOLE_MARKERS = {
    slot_disp = 0x5a5a5a5a,      -- 4-byte stack slot offset
    imm32 = 0x3d3d3d3d,           -- 4-byte immediate
    tag_const = 0x44332211,       -- 4-byte tag constant
}

-- Convert a number to hex literal for Moonlift source
-- We use simple integer literals and let Moonlift's type inference handle them
local function hex_u32(val)
    val = val % 2^32
    return string.format("%d", val)  -- Just decimal, type will be inferred
end

local function hex_i64(val)
    val = val % 2^64
    -- For large 64-bit values, Moonlift might need explicit typing
    -- For now use decimal which is simpler
    return string.format("%d", val)
end

-- Generate a unique variable name for a value
local function value_var(value_name, suffix)
    suffix = suffix or ""
    return "v_" .. string.gsub(value_name, "[^a-z0-9]", "_") .. suffix
end

-- Sanitize a name for use as a function identifier in Moonlift
local function sanitize_name(name)
    return string.gsub(name, "[^a-z0-9_]", "_")
end

-- Flexible value lookup: try exact match, then base name
local function lookup_var(vars_in_scope, name)
    -- Try exact match first
    if vars_in_scope[name] then
        return vars_in_scope[name]
    end

    -- Try base name (strip type suffix like _i32, _i64)
    if string.find(name, "_") then
        return vars_in_scope[name]  -- Already tried
    end

    -- If looking for "imm", try "imm_i32", "imm_i64", etc.
    for key, val in pairs(vars_in_scope) do
        if string.match(key, "^" .. name .. "_") then
            return val
        end
    end

    return nil
end

-- Generate a Moonlift function from a StateOp sequence
-- Returns: {source=string, holes=table, name=sanitized_name}
function M.generate_function(candidate)
    local name = candidate.name or ("compound_" .. candidate.id)
    local sanitized_name = sanitize_name(name)
    local ops = candidate.ops or {}

    if not ops or #ops == 0 then
        return nil, "no operations in candidate"
    end

    local lines = {}
    local holes_list = {}
    local vars_in_scope = {}  -- Track which variables are defined

    -- Function signature
    lines[#lines + 1] = string.format(
        "func %s(state: ptr(u8), exits: ptr(u8), return_addr: ptr(u8)) -> ptr(u8)",
        sanitized_name
    )

    -- Process each StateOp
    for op_idx, op in ipairs(ops) do
        local op_name = op.op
        local args = op.args or {}

        if op_name == "ConstInt" then
            local imm = args.value or "imm"
            local var = value_var(imm)
            lines[#lines + 1] = string.format("    let %s = %s", var, hex_i64(HOLE_MARKERS.imm32))
            holes_list[#holes_list + 1] = {kind="imm64", name=imm}
            -- Store by both the full name and base name (in case of type qualifiers like imm_i32 vs imm)
            vars_in_scope[imm] = var
            local base_name = string.match(imm, "^([a-z_]+)") or imm
            if base_name ~= imm then
                vars_in_scope[base_name] = var
            end

        elseif op_name == "ReadSlot" then
            local slot = args.slot or "slot"
            local var = value_var(slot)
            local marker = hex_u32(HOLE_MARKERS.slot_disp)
            -- Read u64 from state + offset
            lines[#lines + 1] = string.format("    let %s_ptr = as(ptr(u64), state + as(index, as(u32, %s)))", var, marker)
            lines[#lines + 1] = string.format("    let %s = %s_ptr[0]", var, var)
            holes_list[#holes_list + 1] = {kind="slot_disp", name=slot}
            vars_in_scope[slot] = var

        elseif op_name == "WriteSlot" then
            local slot = args.slot or "slot"
            local value = args.value or "value"
            local val_var = lookup_var(vars_in_scope, value) or value_var(value)
            local marker = hex_u32(HOLE_MARKERS.slot_disp)
            lines[#lines + 1] = string.format("    let %s_ptr = as(ptr(u64), state + as(index, as(u32, %s)))", value_var(slot), marker)
            lines[#lines + 1] = string.format("    %s_ptr[0] = as(u64, %s)", value_var(slot), val_var)
            holes_list[#holes_list + 1] = {kind="slot_disp", name=slot}

        elseif op_name == "GuardTag" then
            local exit = args.exit or "exit"
            local tag = args.tag or "ANY"
            local value = args.value or "value"
            local var = value_var(value)
            local val_var = lookup_var(vars_in_scope, value) or var
            lines[#lines + 1] = string.format("    let %s_tag = as(u32, %s)", var, val_var)
            local tag_marker = hex_u32(HOLE_MARKERS.tag_const)
            local exit_marker = hex_u32(HOLE_MARKERS.slot_disp)
            lines[#lines + 1] = string.format("    if %s_tag ~= as(u32, %s) then", var, tag_marker)
            lines[#lines + 1] = string.format("        let exit_idx = as(u32, %s)", exit_marker)
            lines[#lines + 1] = string.format("        let exit_ptr = as(ptr(ptr(u8)), exits + as(index, exit_idx))")
            lines[#lines + 1] = "        return exit_ptr[0]"
            lines[#lines + 1] = "    end"
            holes_list[#holes_list + 1] = {kind="tag_const", name=tag}
            holes_list[#holes_list + 1] = {kind="exit_idx", name=exit}

        elseif op_name == "AddIntWrap" then
            local lhs = args.lhs or "lhs"
            local rhs = args.rhs or "rhs"
            local result = "sum"
            local lhs_var = lookup_var(vars_in_scope, lhs) or value_var(lhs)
            local rhs_var = lookup_var(vars_in_scope, rhs) or value_var(rhs)
            local sum_var = value_var(result)
            -- Cast both to i64 for safety (handle u64 from ReadSlot and i64 from ConstInt)
            lines[#lines + 1] = string.format("    let %s = as(i64, %s) + as(i64, %s)", sum_var, lhs_var, rhs_var)
            vars_in_scope[result] = sum_var

        elseif op_name == "LtInt" then
            local lhs = args.lhs or "lhs"
            local rhs = args.rhs or "rhs"
            local lhs_var = lookup_var(vars_in_scope, lhs) or value_var(lhs)
            local rhs_var = lookup_var(vars_in_scope, rhs) or value_var(rhs)
            local cmp_var = value_var("lt")
            lines[#lines + 1] = string.format("    let %s = %s < %s", cmp_var, lhs_var, rhs_var)
            vars_in_scope["lt"] = cmp_var

        elseif op_name == "Branch" then
            local cond = args.cond or "cond"
            local true_target = args.true_target or "true_edge"
            local false_target = args.false_target or "false_edge"
            local cond_var = lookup_var(vars_in_scope, cond) or value_var(cond)
            local true_marker = hex_u32(HOLE_MARKERS.slot_disp)
            local false_marker = hex_u32(HOLE_MARKERS.slot_disp)
            lines[#lines + 1] = string.format("    if as(bool, %s) then", cond_var)
            lines[#lines + 1] = string.format("        return as(ptr(u8), exits[as(index, as(u32, %s))])", true_marker)
            lines[#lines + 1] = "    else"
            lines[#lines + 1] = string.format("        return as(ptr(u8), exits[as(index, as(u32, %s))])", false_marker)
            lines[#lines + 1] = "    end"
            holes_list[#holes_list + 1] = {kind="exit_idx", name=true_target}
            holes_list[#holes_list + 1] = {kind="exit_idx", name=false_target}

        elseif op_name == "Jump" then
            local target = args.target or "next"
            if target == "next" then
                lines[#lines + 1] = "    return return_addr"
            else
                local exit_marker = hex_u32(HOLE_MARKERS.slot_disp)
                lines[#lines + 1] = string.format("    return as(ptr(u8), exits[as(index, as(u32, %s))])", exit_marker)
                holes_list[#holes_list + 1] = {kind="exit_idx", name=target}
            end

        elseif op_name == "ProjectSlot" then
            local slot = args.slot or "slot"
            local value = args.value or "value"
            local val_var = lookup_var(vars_in_scope, value) or value_var(value)
            local marker = hex_u32(HOLE_MARKERS.slot_disp)
            lines[#lines + 1] = string.format("    as(ptr(u64), state + as(index, as(u32, %s)))[0] = as(u64, %s)", marker, val_var)
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

-- Generate a complete Moonlift module with all stencil functions
function M.generate_module(candidates)
    if not candidates or #candidates == 0 then
        return nil, "no candidates"
    end

    local lines = {}

    lines[#lines + 1] = "-- Generated stencil functions for batch compilation"
    lines[#lines + 1] = "-- Auto-generated by stencil_codegen.lua"
    lines[#lines + 1] = ""

    -- Generate each function
    local generated = {}
    for i, candidate in ipairs(candidates) do
        -- Only generate code stencils, skip rewrites
        if candidate.replacement and candidate.replacement.kind == "code_stencil_needed" then
            local func, err = M.generate_function(candidate)
            if func then
                for line in string.gmatch(func.source, "[^\n]+") do
                    lines[#lines + 1] = line
                end
                generated[#generated + 1] = {
                    name = candidate.name,
                    id = candidate.id,
                    holes = func.holes
                }
            else
                io.stderr:write(string.format("warning: skipped candidate %s: %s\n", candidate.name, err))
            end
        end
    end

    local source = table.concat(lines, "\n")

    return {
        source = source,
        generated = generated
    }
end

return M
