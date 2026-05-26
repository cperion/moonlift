-- verify.lua
-- Verifies mined candidates against semantic contracts
-- Per LUA_STENCIL_HARNESS_DESIGN.md §4.13

local M = {}

-- Verify a candidate against its contract
function M.verify_candidate(candidate, config)
    config = config or {}

    local result = {
        candidate_id = candidate.id or "unknown",
        valid = true,
        errors = {},
        warnings = {},
    }

    -- Check contract
    if candidate.contract then
        local contract_check = M.verify_contract(candidate, candidate.contract)
        if not contract_check.valid then
            result.valid = false
            table.insert(result.errors, "Contract verification failed")
            for _, err in ipairs(contract_check.errors) do
                table.insert(result.errors, err)
            end
        end
    end

    -- Check holes
    if candidate.holes then
        local holes_check = M.verify_holes(candidate)
        if not holes_check.valid then
            result.valid = false
            for _, err in ipairs(holes_check.errors) do
                table.insert(result.errors, err)
            end
        end
    end

    -- Check shape/legalization metadata. Native object compilation only proves
    -- syntax/codegen; the candidate must also declare its VM continuation shape.
    local shape_check = M.verify_shape(candidate)
    if not shape_check.valid then
        result.valid = false
        for _, err in ipairs(shape_check.errors) do
            table.insert(result.errors, err)
        end
    end

    -- Check relocations
    if candidate.relocs then
        local relocs_check = M.verify_relocs(candidate)
        if not relocs_check.valid then
            result.valid = false
            for _, err in ipairs(relocs_check.errors) do
                table.insert(result.errors, err)
            end
        end
    end

    return result
end

function M.verify_shape(candidate)
    local result = { valid = true, errors = {} }
    if not candidate.shape_kind then
        result.valid = false
        table.insert(result.errors, "Missing shape_kind")
    end
    if not candidate.lowering then
        result.valid = false
        table.insert(result.errors, "Missing lowering")
    end
    if not candidate.continuation then
        result.valid = false
        table.insert(result.errors, "Missing continuation")
    end
    if candidate.rewrite_kind then
        if candidate.kind ~= "REWRITE_STENCIL" then
            result.valid = false
            table.insert(result.errors, "rewrite_kind requires kind=REWRITE_STENCIL")
        end
        if not candidate.facts or #candidate.facts == 0 then
            result.valid = false
            table.insert(result.errors, "rewrite candidate missing required facts")
        end
        if not candidate.legalization_source then
            result.valid = false
            table.insert(result.errors, "rewrite candidate missing legalization_source")
        end
    end
    return result
end

-- Verify semantic contract
function M.verify_contract(candidate, contract)
    local result = {
        valid = true,
        errors = {},
    }

    -- Check input state shape
    if contract.input_shape then
        if not candidate.input_shape then
            table.insert(result.errors, "Missing input state shape")
            result.valid = false
        end
    end

    -- Check output state shape
    if contract.output_shape then
        if not candidate.output_shape then
            table.insert(result.errors, "Missing output state shape")
            result.valid = false
        end
    end

    -- Check effect declaration
    if contract.effect then
        if not candidate.effect then
            table.insert(result.errors, "Missing effect declaration")
            result.valid = false
        end
    end

    return result
end

-- Verify holes
function M.verify_holes(candidate)
    local result = {
        valid = true,
        errors = {},
        hole_count = candidate.holes and #candidate.holes or 0,
    }

    if not candidate.holes then
        return result
    end

    for i, hole in ipairs(candidate.holes) do
        -- Check hole has required fields
        if not hole.offset then
            table.insert(result.errors, string.format("Hole %d: missing offset", i))
            result.valid = false
        end

        if not hole.size then
            table.insert(result.errors, string.format("Hole %d: missing size", i))
            result.valid = false
        end

        -- Check offset is reasonable
        if hole.offset and type(hole.offset) ~= "number" then
            table.insert(result.errors, string.format("Hole %d: invalid offset type", i))
            result.valid = false
        end
    end

    return result
end

-- Verify relocations
function M.verify_relocs(candidate)
    local result = {
        valid = true,
        errors = {},
        reloc_count = candidate.relocs and #candidate.relocs or 0,
    }

    if not candidate.relocs then
        return result
    end

    for i, reloc in ipairs(candidate.relocs) do
        -- Check reloc has required fields
        if not reloc.offset then
            table.insert(result.errors, string.format("Reloc %d: missing offset", i))
            result.valid = false
        end

        if not reloc.kind then
            table.insert(result.errors, string.format("Reloc %d: missing kind", i))
            result.valid = false
        end

        -- Check reloc kind is valid
        local valid_kinds = {
            ["abs64"] = true,
            ["rel32"] = true,
            ["call"] = true,
            ["data"] = true,
        }
        if reloc.kind and not valid_kinds[reloc.kind] then
            table.insert(result.errors, string.format("Reloc %d: unknown kind '%s'", i, reloc.kind))
            result.valid = false
        end
    end

    return result
end

-- Verify projection requirements
function M.verify_projection(candidate)
    local result = {
        valid = true,
        errors = {},
    }

    if not candidate.projections then
        return result
    end

    for i, proj in ipairs(candidate.projections) do
        if not proj.kind then
            table.insert(result.errors, string.format("Projection %d: missing kind", i))
            result.valid = false
        end
    end

    return result
end

-- Verify equivalence against expansion
function M.verify_equivalence(candidate, expansion)
    local result = {
        valid = true,
        errors = {},
        candidate_size = candidate.size or 0,
        expansion_size = expansion and expansion.size or 0,
    }

    if not expansion then
        return result
    end

    -- Check that candidate is not larger than expansion
    if candidate.size and expansion.size and candidate.size > expansion.size then
        table.insert(result.errors, string.format(
            "Candidate size (%d) exceeds expansion size (%d)",
            candidate.size, expansion.size
        ))
        result.valid = false
    end

    return result
end

-- Report verification results
function M.report_verification(results)
    print("\n=== Verification Report ===")

    local valid_count = 0
    local error_count = 0

    for _, result in ipairs(results) do
        if result.valid then
            valid_count = valid_count + 1
        else
            error_count = error_count + 1
        end
    end

    print(string.format("Verified: %d", #results))
    print(string.format("Valid: %d", valid_count))
    print(string.format("Failed: %d", error_count))

    if error_count > 0 then
        print("\n  Failed candidates:")
        for _, result in ipairs(results) do
            if not result.valid then
                print(string.format("    %s:", result.candidate_id))
                for _, err in ipairs(result.errors) do
                    print(string.format("      - %s", err))
                end
            end
        end
    end
end

return M
