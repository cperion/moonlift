-- Batch compilation harness for generating stencil fixture bytes.
--
-- This module orchestrates:
-- 1. StateOp -> Moonlift code generation (stencil_codegen)
-- 2. Batch compilation via moon.emit_object()
-- 3. ELF parsing to extract bytes + holes
-- 4. Population of promotion plan with physical data

local path = (...) or debug.getinfo(1, "S").source:match("@(.*/)")
package.path = path .. "/../?.lua;" .. path .. "/../../?.lua;" .. package.path

local codegen = require("experiments.lua_interpreter_vm.src.jit.stencil_codegen_production")
local elf_parser = require("experiments.lua_interpreter_vm.src.jit.elf_parser")
local moon = require("moonlift")

local M = {}

-- Compile a list of candidates to a Moonlift module, emit object file,
-- and extract function bytes/holes.
function M.compile_and_extract(candidates)
    if not candidates or #candidates == 0 then
        return nil, "no candidates to compile"
    end

    -- Generate Moonlift source
    local result, err = codegen.generate_module(candidates)
    if not result then
        return nil, "codegen failed: " .. err
    end

    local moonlift_src = result.source
    local generated = result.generated

    if #generated == 0 then
        return nil, "no functions generated"
    end

    io.stderr:write(string.format("Generated %d Moonlift functions\n", #generated))

    -- Emit to object file
    io.stderr:write("Compiling to object file...\n")
    local ok, result = pcall(function() return moon.emit_object(moonlift_src, "stencil_library") end)
    if not ok then
        -- Compilation error - save source for debugging
        local f = io.open("/tmp/failed_compile.mlua", "w")
        if f then
            f:write(moonlift_src)
            f:close()
            io.stderr:write("Failed source saved to /tmp/failed_compile.mlua\n")
        end
        return nil, "emit_object error: " .. tostring(result)
    end
    local obj_bytes, err = result
    if not obj_bytes or #obj_bytes == 0 then
        return nil, "emit_object failed: " .. (err or "unknown error")
    end

    io.stderr:write(string.format("Emitted object file: %d bytes\n", #obj_bytes))

    -- Parse ELF and extract functions
    io.stderr:write("Parsing ELF and extracting functions...\n")
    local elf, err = elf_parser.parse(obj_bytes)
    if not elf then
        return nil, "ELF parse failed: " .. err
    end

    io.stderr:write(string.format("Found %d functions in ELF\n", #elf.functions))

    -- Map functions by name
    local by_name = {}
    for _, fn in ipairs(elf.functions) do
        by_name[fn.name] = {
            bytes_hex = elf_parser.bytes_to_hex(fn.bytes),
            bytes = fn.bytes,
            size = fn.size,
            relocations = fn.relocations,
        }
    end

    -- Match extracted functions back to candidates
    -- Note: sanitized names (no dots) are in ELF, but we need to map them back to original names
    local extracted = {}
    for _, gen in ipairs(generated) do
        -- gen.name is the sanitized name in ELF, gen.original_name is from the promotion plan
        local fn_data = by_name[gen.name]
        if fn_data then
            -- Store by original name for population
            extracted[gen.original_name] = {
                bytes_hex = fn_data.bytes_hex,
                bytes = fn_data.bytes,
                size = fn_data.size,
                holes = M.extract_holes(fn_data.bytes, gen.holes),
                relocations = fn_data.relocations,
            }
        else
            io.stderr:write(string.format("warning: function %s (sanitized from %s) not found in ELF\n", gen.name, gen.original_name))
        end
    end

    return {
        source = moonlift_src,
        obj_bytes = obj_bytes,
        elf = elf,
        extracted = extracted,
        candidate_map = by_name,
    }
end

-- Extract hole positions by scanning the binary for marker patterns
function M.extract_holes(bytes, hole_specs)
    if not bytes or #bytes == 0 then
        return {}
    end

    -- Build a map of marker patterns to hole specs
    local marker_specs = {}

    -- Common markers (may be multiple specs per marker)
    local markers = {
        [0x5a5a5a5a] = "slot_disp",
        [0x3d3d3d3d] = "imm32",
        [0x3d3d3d3d3d3d3d3d] = "imm64",
        [0x44332211] = "tag_const",
    }

    -- Scan for 32-bit markers
    local holes = {}
    for i = 1, #bytes - 3 do
        local b1, b2, b3, b4 = string.byte(bytes, i, i + 3)
        local word = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
        if markers[word] then
            holes[#holes + 1] = {
                kind = markers[word],
                offset = i - 1,
                marker = elf_parser.bytes_to_hex(string.sub(bytes, i, i + 3)),
                width = 4,
            }
        end
    end

    -- Scan for 64-bit markers (8 bytes of 0x3d)
    for i = 1, #bytes - 7 do
        local pattern = string.sub(bytes, i, i + 7)
        if pattern == "\x3d\x3d\x3d\x3d\x3d\x3d\x3d\x3d" then
            holes[#holes + 1] = {
                kind = "imm64",
                offset = i - 1,
                marker = elf_parser.bytes_to_hex(pattern),
                width = 8,
            }
        end
    end

    return holes
end

-- Populate promotion plan with physical data from extracted bytes
function M.populate_physical(promotion_plan, extracted_data)
    if not promotion_plan or not promotion_plan.library then
        return nil, "invalid promotion plan"
    end

    if not extracted_data or not extracted_data.extracted then
        return nil, "invalid extracted data"
    end

    local updated = promotion_plan
    local updated_count = 0

    for i, candidate in ipairs(updated.library) do
        local ext = extracted_data.extracted[candidate.name]
        if ext then
            candidate.physical = {
                bytes_hex = ext.bytes_hex,
                size = ext.size,
                holes = ext.holes,
                relocs = ext.relocations or {},
            }
            candidate.status = "promoted_with_physical"
            updated_count = updated_count + 1
        end
    end

    io.stderr:write(string.format("Populated physical data for %d candidates\n", updated_count))

    return updated
end

-- Full pipeline: promotion plan -> code gen -> compile -> extract -> populate
function M.build_full_library(promotion_plan)
    if not promotion_plan or not promotion_plan.library then
        return nil, "invalid promotion plan"
    end

    -- Extract candidates that need physical data
    local to_compile = {}
    for _, candidate in ipairs(promotion_plan.library) do
        -- Only compile compound candidates, skip primitives that already have physical data
        if candidate.kind == "compound_candidate" and
           candidate.replacement and candidate.replacement.kind == "code_stencil_needed" then
            to_compile[#to_compile + 1] = candidate
        end
    end

    if #to_compile == 0 then
        io.stderr:write("No candidates need compilation\n")
        return promotion_plan
    end

    io.stderr:write(string.format("Compiling %d compound candidates...\n", #to_compile))

    local compiled, err = M.compile_and_extract(to_compile)
    if not compiled then
        return nil, "compilation failed: " .. err
    end

    local updated, err = M.populate_physical(promotion_plan, compiled)
    if not updated then
        return nil, "population failed: " .. err
    end

    return updated
end

return M
