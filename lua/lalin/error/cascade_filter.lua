-- lalin/error/cascade_filter.lua
-- Cascade suppression: a single pure function that replaces both existing
-- cascade suppression systems (editor_diagnostic_facts.lua and error/registry.lua).
--
-- The algorithm runs AFTER all phases complete, so it has the full picture
-- of all issues across all phases. This eliminates the heuristic string
-- matching and incomplete void-type checks in the current dual systems.

local asdl = require("lalin.asdl")

local M = {}

-------------------------------------------------------------------------------
-- Phase ordering: earlier phases are potential root causes for later phases
-------------------------------------------------------------------------------

local PHASE_ORDER = {
    parse = 1,
    host = 2,
    open = 3,
    binding = 4,
    typecheck = 5,
    backend = 6,
    link = 7,
    vec = 8,
}

-------------------------------------------------------------------------------
-- Root cause classification
--
-- These issue kinds are ALWAYS root causes (not cascades):
-------------------------------------------------------------------------------

local ROOT_CAUSE_KINDS = {
    ParseIssue = true,

    TypeIssueUnresolvedValue = true,
    TypeIssueUnresolvedPath = true,
    TypeIssueDuplicateVariant = true,

    ControlRejectUnterminatedBlock = true,
    ControlRejectDuplicateLabel = true,

    HostIssueDuplicateField = true,
    HostIssueDuplicateType = true,
    HostIssueDuplicateDecl = true,
    HostIssueDuplicateFunc = true,
    HostIssueUnsealedType = true,
    HostIssueSealedMutation = true,
    HostIssueInvalidName = true,
    HostIssueInvalidPackedAlign = true,
    HostIssueBareBoolInBoundaryStruct = true,

    BindingUnresolved = true,

    -- Backend structural issues (missing definition, not cascade)
    BackIssueEmptyProgram = true,
    BackIssueMissingFinalize = true,
    BackIssueMissingSig = true,
    BackIssueMissingData = true,
    BackIssueMissingFunc = true,
    BackIssueMissingExtern = true,
    BackIssueMissingBlock = true,
    BackIssueMissingStackSlot = true,
    BackIssueMissingValue = true,
    BackIssueUnfinishedFunction = true,
}

-------------------------------------------------------------------------------
-- Cascade detection
-------------------------------------------------------------------------------

local void_kinds = {
    ScalarVoid = true,
}

local function is_void_type(ty)
    if not ty then return false end
    if asdl.class_basename(ty) == "TScalar" and ty.scalar then
        return void_kinds[asdl.class_basename(ty.scalar)] or false
    end
    return false
end

local function is_cascade(ri, unresolved_names)
    local kind = asdl.class_basename(ri.issue)
    if not kind then return false end

    -- If there are no unresolved names, no cascade detection based on void
    if not next(unresolved_names) then
        -- Still check for duplicate declarations after the first
        if kind == "HostIssueDuplicateDecl" or kind == "HostIssueDuplicateFunc"
           or kind == "HostIssueDuplicateField" or kind == "HostIssueDuplicateType" then
            return false  -- Each duplicate is independently useful
        end
        return false
    end

    -- Type mismatches involving void types are cascades from unresolved names
    if kind == "TypeIssueExpected" then
        return is_void_type(ri.issue.expected) or is_void_type(ri.issue.actual)
    end
    if kind == "TypeIssueNotCallable" then
        return is_void_type(ri.issue.ty)
    end
    if kind == "TypeIssueNotIndexable" then
        return is_void_type(ri.issue.ty)
    end
    if kind == "TypeIssueNotPointer" then
        return is_void_type(ri.issue.ty)
    end
    if kind == "TypeIssueInvalidUnary" then
        return is_void_type(ri.issue.ty)
    end
    if kind == "TypeIssueInvalidBinary" or kind == "TypeIssueInvalidCompare" or kind == "TypeIssueInvalidLogic" then
        return is_void_type(ri.issue.lhs) or is_void_type(ri.issue.rhs)
    end
    if kind == "TypeIssueArgCount" then
        -- Arg count mismatch cascades when the function type is void
        -- (from an unresolved name)
        return false  -- usually a genuine error in the call
    end

    -- Backend issues referencing missing definitions cascade from typecheck
    -- failures that caused the definition to not be emitted
    if kind:find("^BackIssueDuplicate") then
        return false  -- duplicates are always real
    end
    if kind:find("^BackIssueMissing") or kind:find("^BackIssueUnfinished") then
        -- These cascade from typecheck phase failures
        return true
    end
    if kind:find("^BackIssueCommand") or kind:find("^BackIssueFinish") then
        -- Order violations cascade from structural compiler issues
        return true
    end

    -- Control flow issues that reference a block/label from a failed region
    if kind == "TypeIssueMissingJumpTarget" or kind == "TypeIssueInvalidControl" then
        return false  -- usually independent issues
    end

    return false
end

-------------------------------------------------------------------------------
-- Key helper for dedup
-------------------------------------------------------------------------------

local function resolved_key(ri)
    if not ri.span then
        return ri.phase .. ":" .. tostring(ri.issue)
    end
    return ri.span.uri .. ":" .. ri.span.start_offset .. "-" .. ri.span.end_offset
        .. ":" .. (ri.code or tostring(ri.issue))
end

-------------------------------------------------------------------------------
-- Main filter
-------------------------------------------------------------------------------

--- Filter a list of ResolvedIssue, suppressing cascading issues.
-- @param resolved_issues  ResolvedIssue[] — all issues from all phases
-- @return ResolvedIssue[] — root causes only, in phase order, deduplicated
function M.filter(resolved_issues)
    if not resolved_issues or #resolved_issues == 0 then
        return {}
    end

    -- Sort by phase order
    table.sort(resolved_issues, function(a, b)
        local pa = PHASE_ORDER[a.phase] or 99
        local pb = PHASE_ORDER[b.phase] or 99
        if pa ~= pb then return pa < pb end
        -- Within the same phase, preserve original order
        return false
    end)

    -- First pass: identify root causes and collect unresolved names
    local unresolved_names = {}
    local root_keys = {}
    local seen_keys = {}

    for _, ri in ipairs(resolved_issues) do
        local kind = asdl.class_basename(ri.issue) or ""

        if ROOT_CAUSE_KINDS[kind] then
            root_keys[resolved_key(ri)] = true
        end

        if kind == "TypeIssueUnresolvedValue" and ri.issue.name then
            unresolved_names[ri.issue.name] = true
        end
        if kind == "TypeIssueUnresolvedPath" and ri.issue.first_name then
            unresolved_names[ri.issue.first_name] = true
        end
        if kind == "BindingUnresolved" then
            local name = ri.issue.use and ri.issue.use.anchor and ri.issue.use.anchor.label
            if name then unresolved_names[name] = true end
        end
        if kind == "HostIssueUnknownBinding" and ri.issue.name then
            unresolved_names[ri.issue.name] = true
        end
    end

    -- Second pass: filter cascades and deduplicate
    local out = {}
    for _, ri in ipairs(resolved_issues) do
        local kind = asdl.class_basename(ri.issue) or ""

        -- Root causes always pass
        if ROOT_CAUSE_KINDS[kind] then
            -- Dedup check
            local k = resolved_key(ri)
            if not seen_keys[k] then
                seen_keys[k] = true
                out[#out + 1] = ri
            end
            goto continue
        end

        -- Check if this is a cascade
        if is_cascade(ri, unresolved_names) then
            goto continue  -- suppressed
        end

        -- Dedup check
        local k = resolved_key(ri)
        if not seen_keys[k] then
            seen_keys[k] = true
            out[#out + 1] = ri
        end

        ::continue::
    end

    return out
end

return M
