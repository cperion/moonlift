-- lalin/error/catalog.lua
-- Error Catalog: dispatcher for phase-local explainers.
--
-- Every compiler phase has an explain_XXX_issue() function that receives
-- (issue, analysis) and returns an ExplainEvent. This module routes
-- build_report calls to the appropriate explainer based on the phase.
--
-- The E9999 fallback is preserved for issues that reach the catalog
-- without a registered phase explainer.

local Report = require("lalin.error.report")
local Span = require("lalin.error.span")

local M = {}

local Entry = {}
Entry.__index = Entry

function M.entry(code, severity, build)
    return setmetatable({
        code = code,
        severity = severity,
        build = build,
    }, Entry)
end

-------------------------------------------------------------------------------
-- The Catalog
-------------------------------------------------------------------------------

M.entries = {}

local function register(code, severity, build)
    M.entries[code] = M.entry(code, severity, build)
end

local function lookup(code)
    return M.entries[code]
end

M.lookup = lookup

-------------------------------------------------------------------------------
-- Fallback span from analysis context
-------------------------------------------------------------------------------

local function issue_span(issue, analysis)
    if issue.span then return issue.span end
    if issue.offset and analysis and analysis.source_text then
        local src = analysis.source_text
        local line_starts = {}
        local n = #src
        for i = 1, n do
            if string.byte(src, i) == 10 then line_starts[#line_starts + 1] = i + 1 end
        end
        table.insert(line_starts, 1, 1)
        local line = 1
        for i = 1, #line_starts do
            if line_starts[i] <= (issue.offset + 1) then line = i end
        end
        local col = (issue.offset + 1) - line_starts[line] + 1
        return Span.from_offsets(
            analysis.uri or "?",
            issue.offset, issue.offset + 1,
            line, col, line, col + 1
        )
    end
    return nil
end

-------------------------------------------------------------------------------
-- E9999: Fallback (unknown issue)
-------------------------------------------------------------------------------

register("E9999", "error", function(issue, analysis)
    local span = issue_span(issue, analysis)
    local msg = issue.message or tostring(issue)

    return Report.new({
        code = "E9999",
        severity = "error",
        phase_context = issue.phase_context or "during compilation",
        primary = { span = span, message = msg },
        notes = {
            { message = "this is an unclassified error — please report it as a bug" },
        },
        suggestions = {},
    })
end)

-------------------------------------------------------------------------------
-- Issue-to-code mapping (kept for registry/collector severity detection)
-------------------------------------------------------------------------------

local issue_code_map = {
    -- Parse issues
    ParseIssue = "E0101",

    -- Name resolution
    TypeIssueUnresolvedValue = "E0201",
    TypeIssueUnresolvedPath = "E0202",
    BindingUnresolved = "E0201",

    -- Type mismatches
    TypeIssueExpected = "E0301",
    TypeIssueArgCount = "E0305",
    TypeIssueNotCallable = "E0302",
    TypeIssueNotIndexable = "E0303",
    TypeIssueNotPointer = "E0303",
    TypeIssueInvalidUnary = "E0304",
    TypeIssueInvalidBinary = "E0304",
    TypeIssueInvalidCompare = "E0304",
    TypeIssueInvalidLogic = "E0304",

    -- Control flow
    TypeIssueInvalidControl = "E0405",
    TypeIssueMissingJumpTarget = "E0402",
    TypeIssueMissingJumpArg = "E0404",
    TypeIssueExtraJumpArg = "E0404",
    TypeIssueDuplicateJumpArg = "E0404",
    TypeIssueUnexpectedYield = "E0407",

    -- Host issues
    HostIssueDuplicateField = "E0501",
    HostIssueDuplicateType = "E0502",
    HostIssueDuplicateDecl = "E0203",
    HostIssueDuplicateFunc = "E0203",
    HostIssueUnsealedType = "E0503",
    HostIssueSealedMutation = "E0503",
    HostIssueAlreadySealed = "E0503",
    HostIssueInvalidName = "E0504",
    HostIssueUnknownBinding = "E0201",
    HostIssueExpected = "E0301",
    HostIssueArgCount = "E0305",
    HostIssueInvalidPackedAlign = "E0506",
    HostIssueBareBoolInBoundaryStruct = "E0505",
    HostIssueInvalidEmitFill = "E0702",
    HostIssueMissingEmitFill = "E0702",

    -- HostIssue variants (previously unmapped)
    HostIssueSpliceExpected = "E0701",
    HostIssueSpliceEvalError = "E0703",
    HostIssueLuaStepError = "E0703",
    HostIssueTemplateParseError = "E0103",
    HostIssueRegionComposeMissingExit = "E0403",
    HostIssueRegionComposeIncompatibleCont = "E0404",
    HostIssueRegionComposeIncompleteRoute = "E0403",
    HostIssueRegionComposeContextMismatch = "E0405",

    -- Back issues
    BackIssueEmptyProgram = "E0603",
    BackIssueMissingFinalize = "E0603",
    BackIssueCommandAfterFinalize = "E0603",
    BackIssueCommandOutsideFunction = "E0603",
    BackIssueNestedFunction = "E0603",
    BackIssueFinishWithoutBegin = "E0603",
    BackIssueFinishWrongFunction = "E0603",
    BackIssueUnfinishedFunction = "E0603",
    BackIssueDuplicateSig = "E0602",
    BackIssueDuplicateData = "E0602",
    BackIssueDuplicateFunc = "E0602",
    BackIssueDuplicateExtern = "E0602",
    BackIssueDuplicateBlock = "E0406",
    BackIssueDuplicateStackSlot = "E0602",
    BackIssueDuplicateValue = "E0602",
    BackIssueMissingSig = "E0601",
    BackIssueMissingData = "E0601",
    BackIssueMissingFunc = "E0601",
    BackIssueMissingExtern = "E0601",
    BackIssueMissingBlock = "E0402",
    BackIssueMissingStackSlot = "E0601",
    BackIssueMissingValue = "E0601",

    -- BackIssue variants (previously unmapped)
    BackIssueDuplicateAccess = "E0602",
    BackIssueMissingAccess = "E0601",
    BackIssueInvalidAlignment = "E0506",
    BackIssueLoadAccessEffect = "E0301",
    BackIssueStoreAccessEffect = "E0301",
    BackIssueDereferenceTooSmall = "E0301",
    BackIssueIntScalarExpected = "E0304",
    BackIssueFloatScalarExpected = "E0304",
    BackIssueBitScalarExpected = "E0304",
    BackIssueShiftScalarExpected = "E0304",
    BackIssueNonTrappingWithoutDereference = "E0603",
    BackIssueCanMoveWithoutNonTrapping = "E0603",
    BackIssueShapeRequiresScalar = "E0301",
    BackIssueShapeRequiresVector = "E0301",

    -- Vectorization rejections
    VecRejectUnsupportedLoop = "E1001",
    VecRejectUnsupportedExpr = "E1001",
    VecRejectUnsupportedStmt = "E1001",
    VecRejectUnsupportedMemory = "E1002",
    VecRejectDependence = "E1003",
    VecRejectRange = "E1004",
    VecRejectTarget = "E1005",
    VecRejectCost = "E1005",

    -- Unknown/missing variant issues
    TypeIssueUnknownVariant = "E0301",
    TypeIssueVariantPayloadMismatch = "E0301",
    TypeIssueDuplicateVariant = "E0203",
    TypeIssueMissingJumpArg = "E0404",
    TypeIssueExtraJumpArg = "E0404",
    TypeIssueDuplicateJumpArg = "E0203",
}

function M.code_for_issue(issue)
    if not issue then return "E9999" end
    if type(issue) ~= "table" then return "E9999" end

    -- Check for explicit code
    local explicit_code = rawget(issue, "error_code")
    if type(explicit_code) == "string" then return explicit_code end

    -- Map by class kind
    local asdl = require("lalin.asdl")
    local cls = asdl.classof(issue)
    if cls then
        local code = issue_code_map[rawget(cls, "kind")]
        if code then return code end
    end

    -- Check for issue kind field
    local issue_kind = rawget(issue, "kind")
    if type(issue_kind) == "string" then
        local code = issue_code_map[issue_kind]
        if code then return code end
    end

    return "E9999"
end

-------------------------------------------------------------------------------
-- Phase-to-explainer dispatcher
-------------------------------------------------------------------------------

local explainers = {}
local REQUIRED_PHASES = {"parse","host","binding","typecheck","backend","link","vec","source"}

local function ensure_explainers()
    if explainers.parse then return end
    explainers.parse = function(issue, analysis) return { kind = "ParseIssue", primary = issue.message or "parse error" } end
    explainers.host = function(issue, analysis) return { kind = "HostIssue", primary = issue.message or "host error" } end
    explainers.binding = function(issue, analysis) return { kind = "BindingIssue", primary = issue.message or "binding error" } end
    explainers.typecheck = require("lalin.tree_typecheck").explain_type_issue
    explainers.backend = require("lalin.back_validate").explain_back_issue
    explainers.link = require("lalin.link_plan_validate").explain_link_issue
    explainers.vec = function(issue, analysis)
        local asdl = require("lalin.asdl")
        local kind = asdl.class_basename(issue) or issue.kind or "VecReject"
        local reason = issue.reason or issue.message or kind
        return {
            code = M.code_for_issue(issue),
            severity = "info",
            phase_context = "while planning vectorization",
            primary = { span = issue_span(issue, analysis), message = "vectorization rejected: " .. tostring(reason) },
            notes = {},
            suggestions = {},
        }
    end
    explainers.source = require("lalin.source_text_apply").explain_source_issue
    -- Validate all required phases have explainers
    for _, name in ipairs(REQUIRED_PHASES) do
        if not explainers[name] then
            error("missing explainer for phase: " .. name, 2)
        end
    end
end

-------------------------------------------------------------------------------
-- build_report: entry point for error construction
--
-- Signature: (code, issue, phase, analysis) → ErrorReport
-- The phase parameter determines which explainer to use.
-- The code parameter is used as fallback if the explainer returns E9999.
-------------------------------------------------------------------------------

function M.build_report(code, issue, phase, analysis)
    analysis = analysis or {}
    ensure_explainers()
    local explainer = explainers[phase]
    if not explainer then
        -- No explainer registered → use E9999 fallback
        local entry = M.entries["E9999"]
        local ok, report = pcall(entry.build, issue, analysis)
        if ok then return report end
        return Report.new({ code = "E9999", severity = "error",
            primary = { span = nil, message = tostring(report) } })
    end
    local ok, event = pcall(explainer, issue, analysis)
    if not ok then
        -- Explainer crashed → E9999 meta-error
        return Report.new({ code = "E9999", severity = "error",
            primary = { span = nil, message = "internal error: " .. tostring(event) },
            notes = { { message = "the error reporter crashed while explaining this error" } } })
    end
    -- Ensure the event has a code/span (fallback to the provided code or
    -- the collector-resolved span).  Explainers are still phase-local, but the
    -- collector is the authority for source resolution.
    if not event.code then
        event.code = code or "E9999"
    end
    event.primary = event.primary or { message = "unknown error" }
    if not event.primary.span and analysis.resolved_span then
        event.primary.span = analysis.resolved_span
    end
    return Report.new(event)
end

return M
