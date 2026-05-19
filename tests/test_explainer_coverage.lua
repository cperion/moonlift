-- tests/test_explainer_coverage.lua
-- Verifies that every ASDL issue variant has a handler in the phase-local explainers.
--
-- For each variant, creates a mock issue with the expected class kind, calls
-- build_report through the catalog dispatcher, and asserts the result.code
-- is NOT "E9999" (which would indicate an unmapped variant).

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Catalog = require("moonlift.error.catalog")
local pvm = require("moonlift.pvm")

-------------------------------------------------------------------------------
-- Static list of ALL issue variants by phase
-------------------------------------------------------------------------------

local expected = {
    parse = {
        ParseIssue = true,
    },

    typecheck = {
        TypeIssueExpected = true,
        TypeIssueArgCount = true,
        TypeIssueNotCallable = true,
        TypeIssueNotIndexable = true,
        TypeIssueNotPointer = true,
        TypeIssueInvalidUnary = true,
        TypeIssueInvalidBinary = true,
        TypeIssueInvalidCompare = true,
        TypeIssueInvalidLogic = true,
        TypeIssueUnresolvedValue = true,
        TypeIssueUnresolvedPath = true,
        TypeIssueInvalidControl = true,
        TypeIssueMissingJumpTarget = true,
        TypeIssueMissingJumpArg = true,
        TypeIssueExtraJumpArg = true,
        TypeIssueDuplicateJumpArg = true,
        TypeIssueUnexpectedYield = true,
        TypeIssueUnknownVariant = true,
        TypeIssueVariantPayloadMismatch = true,
        TypeIssueDuplicateVariant = true,
    },

    host = {
        HostIssueInvalidName = true,
        HostIssueExpected = true,
        HostIssueArgCount = true,
        HostIssueDuplicateField = true,
        HostIssueDuplicateType = true,
        HostIssueDuplicateDecl = true,
        HostIssueDuplicateFunc = true,
        HostIssueUnsealedType = true,
        HostIssueSealedMutation = true,
        HostIssueAlreadySealed = true,
        HostIssueUnknownBinding = true,
        HostIssueInvalidEmitFill = true,
        HostIssueMissingEmitFill = true,
        HostIssueInvalidPackedAlign = true,
        HostIssueBareBoolInBoundaryStruct = true,
        HostIssueSpliceExpected = true,
        HostIssueSpliceEvalError = true,
        HostIssueLuaStepError = true,
        HostIssueTemplateParseError = true,
        HostIssueRegionComposeMissingExit = true,
        HostIssueRegionComposeIncompatibleCont = true,
        HostIssueRegionComposeIncompleteRoute = true,
        HostIssueRegionComposeContextMismatch = true,
    },

    open = {
        IssueUnfilledTypeSlot = true,
        IssueUnfilledValueSlot = true,
        IssueOpenSlot = true,
        IssueUnfilledExprSlot = true,
        IssueUnfilledPlaceSlot = true,
        IssueUnfilledDomainSlot = true,
        IssueUnfilledRegionSlot = true,
        IssueUnfilledContSlot = true,
        IssueUnfilledFuncSlot = true,
        IssueUnfilledConstSlot = true,
        IssueUnfilledStaticSlot = true,
        IssueUnfilledTypeDeclSlot = true,
        IssueUnfilledItemsSlot = true,
        IssueUnfilledModuleSlot = true,
        IssueUnfilledRegionFragSlot = true,
        IssueUnfilledExprFragSlot = true,
        IssueUnfilledNameSlot = true,
        IssueUnexpandedExprFragUse = true,
        IssueUnexpandedRegionFragUse = true,
        IssueUnexpandedModuleUse = true,
        IssueGenericValueImport = true,
        IssueOpenModuleName = true,
    },

    binding = {
        BindingUnresolved = true,
    },

    backend = {
        BackIssueEmptyProgram = true,
        BackIssueMissingFinalize = true,
        BackIssueCommandAfterFinalize = true,
        BackIssueCommandOutsideFunction = true,
        BackIssueNestedFunction = true,
        BackIssueFinishWithoutBegin = true,
        BackIssueFinishWrongFunction = true,
        BackIssueUnfinishedFunction = true,
        BackIssueDuplicateSig = true,
        BackIssueDuplicateData = true,
        BackIssueDuplicateFunc = true,
        BackIssueDuplicateExtern = true,
        BackIssueDuplicateBlock = true,
        BackIssueDuplicateStackSlot = true,
        BackIssueDuplicateValue = true,
        BackIssueDuplicateAccess = true,
        BackIssueMissingSig = true,
        BackIssueMissingData = true,
        BackIssueMissingFunc = true,
        BackIssueMissingExtern = true,
        BackIssueMissingBlock = true,
        BackIssueMissingStackSlot = true,
        BackIssueMissingValue = true,
        BackIssueMissingAccess = true,
        BackIssueInvalidAlignment = true,
        BackIssueLoadAccessMode = true,
        BackIssueStoreAccessMode = true,
        BackIssueDereferenceTooSmall = true,
        BackIssueTargetUnsupportedShape = true,
        BackIssueIntScalarExpected = true,
        BackIssueFloatScalarExpected = true,
        BackIssueBitScalarExpected = true,
        BackIssueShiftScalarExpected = true,
        BackIssueNonTrappingWithoutDereference = true,
        BackIssueCanMoveWithoutNonTrapping = true,
        BackIssueShapeRequiresScalar = true,
        BackIssueShapeRequiresVector = true,
    },

    link = {
        LinkIssueMissingOutput = true,
        LinkIssueNoInputs = true,
        LinkIssueMissingInput = true,
        LinkIssueUnsupportedPlatform = true,
        LinkIssueUnsupportedInput = true,
        LinkIssueUnsupportedOption = true,
        LinkIssueUnresolvedSymbol = true,
        LinkIssueDuplicateSymbol = true,
        LinkIssueToolUnavailable = true,
        LinkIssueCommandFailed = true,
    },

    vec = {
        VecRejectUnsupportedLoop = true,
        VecRejectUnsupportedExpr = true,
        VecRejectUnsupportedStmt = true,
        VecRejectUnsupportedMemory = true,
        VecRejectDependence = true,
        VecRejectRange = true,
        VecRejectTarget = true,
        VecRejectCost = true,
    },

    source = {
        SourceIssueWrongDocument = true,
        SourceIssueStaleVersion = true,
        SourceIssueInvalidRange = true,
        SourceIssueOverlappingRanges = true,
        SourceIssueMixedReplaceAll = true,
    },
}

-------------------------------------------------------------------------------
-- Mock issue factory
-------------------------------------------------------------------------------

local function make_mock_issue(kind)
    -- Create a mock with __class metatable so pvm.classof works
    local obj = {}
    setmetatable(obj, { __class = { kind = kind } })
    
    -- Common fields
    obj.kind = kind
    obj.message = kind
    obj.offset = nil
    obj.name = "mock"
    obj.site = "call"
    obj.expected = "i32"
    obj.actual = "f64"
    obj.ty = "i32"
    obj.lhs = "i32"
    obj.rhs = "i32"
    obj.op = "BinAdd"
    obj.op_kind = "binary"
    obj.span = nil
    obj.error_code = nil

    -- Host-specific fields
    obj.field_name = "mock_field"
    obj.type_name = "MockType"
    obj.module_name = "mock_module"
    obj.func_name = "mock_func"
    obj.fill_name = "mock_fill"
    obj.fragment_name = "mock_frag"
    obj.exit_name = "mock_exit"
    obj.left = "left"
    obj.right = "right"
    obj.splice_id = "mock_splice"
    obj.step_id = "mock_step"
    obj.align = 4

    -- Back-specific fields
    obj.sig = { text = "mock_sig" }
    obj.func = { text = "mock_func" }
    obj.block = { text = "mock_block" }
    obj.value = { text = "mock_value" }
    obj.data = { text = "mock_data" }
    obj.extern_val = { text = "mock_extern" }
    obj.slot = { text = "mock_slot", key = "mock_slot", pretty_name = "" }
    obj.access = { text = "mock_access" }
    obj.mode = { text = "mock_mode" }
    obj.scalar = { text = "mock_scalar" }
    obj.bytes = 4
    obj.index = 1
    obj.violation = "mock violation"

    -- Open-specific fields
    obj.use_id = "mock_use"
    obj.import_val = { text = "mock_import" }
    obj.param_name = "mock_param"
    obj.island_name = "mock_island"

    -- Link-specific fields
    obj.path = { text = "mock_path.mlua" }
    obj.symbol = { name = "mock_symbol" }
    obj.tool = "mock_tool"
    obj.code = 1
    obj.stderr = "mock stderr"
    obj.reason = "mock reason"
    obj.platform = "mock_platform"
    obj.option = "mock_option"

    -- Vec-specific fields
    obj.loop = { text = "mock_loop" }
    obj.expr = { text = "mock_expr" }
    obj.stmt_id = "mock_stmt"
    obj.shape = { text = "mock_shape" }
    obj.a = { text = "mock_access_a" }
    obj.b = { text = "mock_access_b" }

    -- Source-specific fields
    obj.uri = { text = "mock_uri" }
    obj.expected_after = { value = 5 }
    obj.actual_version = { value = 3 }
    obj.previous = { text = "prev" }
    obj.current = { text = "cur" }

    -- Variant-specific
    obj.variant_name = "mock_variant"
    obj.decl_name = "mock_decl"
    obj.label = { name = "mock_label" }
    obj.label_name = "mock_label"
    obj.block_names = { "mock_label_1", "mock_label_2" }
    obj.candidates = { "mock_candidate" }
    obj.first_span = nil
    obj.path_text = "mock.path"
    obj.first_name = "mock"
    obj.def_kind = "mock_def"
    obj.cont_name = "mock_cont"
    obj.region_name = "mock_region"
    obj.declared_conts = { "cont_a", "cont_b" }
    obj.expected_params = {}
    obj.actual_params = {}
    obj.context = "mock_context"
    obj.construct = "mock_construct"
    obj.keyword = "mock_keyword"
    obj.in_scope_names = {}
    
    return obj
end

-------------------------------------------------------------------------------
-- PVM classof mock
-- We need to override pvm.classof to return the expected class kind.
-- The explainers use pvm.classof(issue) to detect variant types.
-------------------------------------------------------------------------------

-- Note: mock issues use __class metatable, so pvm.classof works normally.
-- No override needed.

-------------------------------------------------------------------------------
-- Run coverage test
-------------------------------------------------------------------------------

local function run_tests()
    local passed, failed = 0, 0
    local total = 0

    for phase, variants in pairs(expected) do
        for variant_name in pairs(variants) do
            total = total + 1
            local mock_issue = make_mock_issue(variant_name)
            -- Try to call the explainer via Catalog.build_report
            local ok, result = pcall(Catalog.build_report, nil, mock_issue, phase, {})
            if ok then
                local code = result and result.code or "nil"
                if code == "E9999" then
                    print("FAIL [" .. phase .. "] " .. variant_name .. " → E9999 (unmapped)")
                    failed = failed + 1
                else
                    print("PASS [" .. phase .. "] " .. variant_name .. " → " .. tostring(code))
                    passed = passed + 1
                end
            else
                print("FAIL [" .. phase .. "] " .. variant_name .. " → crashed: " .. tostring(result))
                failed = failed + 1
            end
        end
    end

    print("\n=== Results ===")
    print("Total: " .. total)
    print("Passed: " .. passed)
    print("Failed: " .. failed)

    if failed > 0 then
        os.exit(1)
    end
end

local ok, err = pcall(run_tests)
if not ok then
    print("Test runner crashed: " .. tostring(err))
    os.exit(1)
end
