-- Canonical C backend coverage classification matrix.
--
-- This table is the contract for the MoonTree -> MoonCode -> CBackend pipeline.
-- Every relevant source-schema variant is classified explicitly at the phase
-- boundary where it is accepted, rejected, or required to have disappeared;
-- callers must not infer a default for unknown variants.

local M = {}

local VALID_STATUS = {
    supported = true,
    phase_unreachable = true,
    language_rejected = true,
}

local function entry(status, section, reason)
    assert(VALID_STATUS[status], "invalid C backend coverage status")
    assert(type(section) == "string" and section ~= "", "missing C backend coverage section")
    assert(type(reason) == "string" and reason ~= "", "missing C backend coverage reason")
    return { status = status, section = section, reason = reason }
end

local function supported(section, reason) return entry("supported", section, reason) end
local function phase_unreachable(section, reason) return entry("phase_unreachable", section, reason) end
local function language_rejected(section, reason) return entry("language_rejected", section, reason) end
local tables = {
    ["MoonType.TypeRef"] = {
        TypeRefPath = supported("C_BACKEND_DESIGN.md §6", "Named type paths are accepted only when the semantic layout environment resolves them exactly."),
        TypeRefGlobal = supported("C_BACKEND_DESIGN.md §6", "Global named types project to layout-backed CBackendNamed declarations."),
        TypeRefLocal = supported("C_BACKEND_DESIGN.md §6", "Local/open-expanded named types project through their resolved layout entries."),
        TypeRefSlot = phase_unreachable("C_BACKEND_DESIGN.md §6", "Open type slots must be expanded before tree_to_code lowering."),
    },

    ["MoonType.ArrayLen"] = {
        ArrayLenExpr = language_rejected("C_BACKEND_DESIGN.md §6", "Dynamic array lengths are rejected during typechecking; C storage arrays require ArrayLenConst before tree_to_code/code_to_c lowering."),
        ArrayLenConst = supported("C_BACKEND_DESIGN.md §6", "Constant array lengths lower to fixed CBackendArray storage types."),
        ArrayLenSlot = phase_unreachable("C_BACKEND_DESIGN.md §6", "Open expression slots in type positions must be expanded before tree_to_code lowering."),
    },

    ["MoonType.Type"] = {
        TScalar = supported("C_BACKEND_DESIGN.md §6", "All MoonCore scalar types project to fixed-width, bool, raw pointer, or target index CBackend types."),
        TPtr = supported("C_BACKEND_DESIGN.md §6", "Typed data pointers remain distinct from code pointers."),
        TArray = supported("C_BACKEND_DESIGN.md §6", "Fixed arrays lower to explicit storage/declaration types and ABI by-address where required."),
        TSlice = supported("C_BACKEND_DESIGN.md §6", "Slices lower to explicit descriptor storage when present in typed input."),
        TView = supported("C_BACKEND_DESIGN.md §6", "Views lower to data/len/stride descriptors and view ABI forms."),
        TFunc = supported("C_BACKEND_DESIGN.md §6", "Function types lower to exact code-pointer signatures, never void pointers."),
        TClosure = supported("C_BACKEND_DESIGN.md §6", "Closure types lower to fn/context descriptors after closure conversion."),
        TNamed = supported("C_BACKEND_DESIGN.md §6", "Named aggregates/imported types lower through Sem.LayoutEnv-backed declarations."),
        THandle = supported("C_BACKEND_DESIGN.md §6", "Handles lower through their explicit representation type and layout-backed handle declarations."),
        TLease = supported("C_BACKEND_DESIGN.md §6", "Leases lower through their base type after ownership/borrow discipline is enforced before backend projection."),
        TAccess = supported("C_BACKEND_DESIGN.md §6", "Access-qualified types lower through their base type after frontend access facts are preserved in ASDL."),
        TSlot = phase_unreachable("C_BACKEND_DESIGN.md §6", "Open type slots are invalid after open expansion and typechecking."),
        TCType = supported("C_BACKEND_DESIGN.md §6", "Imported C type ids are preserved as exact CBackend named/imported types."),
        TCFuncPtr = supported("C_BACKEND_DESIGN.md §6", "Imported C function pointer signatures are preserved exactly as code pointers."),
    },

    ["MoonTree.View"] = {
        ViewFromExpr = supported("C_BACKEND_DESIGN.md §10", "A view value expression can be reused as an existing data/len/stride descriptor."),
        ViewContiguous = supported("C_BACKEND_DESIGN.md §10", "Contiguous views construct data/len descriptors with stride equal to element size."),
        ViewStrided = supported("C_BACKEND_DESIGN.md §10", "Strided views construct data/len/stride descriptors directly."),
        ViewRestrided = supported("C_BACKEND_DESIGN.md §10", "Restriding rewrites the stride component of an existing descriptor."),
        ViewWindow = supported("C_BACKEND_DESIGN.md §10", "Windowing adjusts descriptor data and length while preserving stride."),
        ViewRowBase = supported("C_BACKEND_DESIGN.md §10", "Row-base views offset descriptor data by row offset and element layout."),
        ViewInterleaved = supported("C_BACKEND_DESIGN.md §10", "Interleaved views compute lane-offset data with explicit stride."),
        ViewInterleavedView = supported("C_BACKEND_DESIGN.md §10", "Interleaved subviews compute lane-offset data from an existing descriptor."),
    },

    ["MoonTree.Domain"] = {
        DomainRange = supported("C_BACKEND_DESIGN.md §10", "Range domains are lowerable when view/domain lowering is requested by a supported construct."),
        DomainRange2 = supported("C_BACKEND_DESIGN.md §10", "Start/stop range domains preserve explicit bounds."),
        DomainZipEqValues = supported("C_BACKEND_DESIGN.md §10", "Zip-equal value domains are represented by explicit value lists before backend loops/regions."),
        DomainValue = supported("C_BACKEND_DESIGN.md §10", "Single-value domains are represented explicitly."),
        DomainView = supported("C_BACKEND_DESIGN.md §10", "View domains lower through the complete View table."),
        DomainZipEqViews = supported("C_BACKEND_DESIGN.md §10", "Zip-equal view domains lower through descriptor facts."),
        DomainSlotValue = phase_unreachable("C_BACKEND_DESIGN.md §10", "Open domain slots must be expanded before tree_to_code lowering."),
    },

    ["MoonTree.IndexBase"] = {
        IndexBaseExpr = supported("C_BACKEND_DESIGN.md §9", "Expression bases lower through pointer/array descriptor address calculation."),
        IndexBasePlace = supported("C_BACKEND_DESIGN.md §9", "Place bases lower through place-aware address calculation."),
        IndexBaseView = supported("C_BACKEND_DESIGN.md §9", "View bases lower through descriptor data/stride extraction."),
    },

    ["MoonTree.Place"] = {
        PlaceRef = supported("C_BACKEND_DESIGN.md §9", "Value references lower to residence-aware local/global places."),
        PlaceDeref = supported("C_BACKEND_DESIGN.md §9", "Pointer dereferences lower to typed or byte-addressed places."),
        PlaceDot = phase_unreachable("C_BACKEND_DESIGN.md §9", "Raw field names must be resolved to PlaceField before tree_to_code lowering."),
        PlaceField = supported("C_BACKEND_DESIGN.md §9", "Resolved semantic field refs lower by layout offset and field type."),
        PlaceIndex = supported("C_BACKEND_DESIGN.md §9", "Array/pointer/view indexing lowers with target-aware element-size calculation."),
        PlaceSlotValue = phase_unreachable("C_BACKEND_DESIGN.md §9", "Open place slots must be expanded before tree_to_code lowering."),
    },

    ["MoonTree.Expr"] = {
        ExprLit = supported("C_BACKEND_DESIGN.md §8", "Integer/float/bool/string/nil literals lower with exact literal preservation or diagnostics."),
        ExprRef = supported("C_BACKEND_DESIGN.md §8", "Resolved value references lower through exact symbol and residence tables."),
        ExprDot = phase_unreachable("C_BACKEND_DESIGN.md §9", "Raw dot access must be resolved to ExprField before tree_to_code lowering."),
        ExprUnary = supported("C_BACKEND_DESIGN.md §8", "Unary operators lower through UB-free helper or direct safe operations."),
        ExprBinary = supported("C_BACKEND_DESIGN.md §8", "Binary operators lower through UB-free arithmetic/bitwise/shift helpers."),
        ExprCompare = supported("C_BACKEND_DESIGN.md §8", "Comparisons lower to explicit bool8 compare rvalues."),
        ExprLogic = supported("C_BACKEND_DESIGN.md §8", "Logical operators lower with CFG-based short-circuit semantics."),
        ExprCast = phase_unreachable("C_BACKEND_DESIGN.md §8", "Surface casts must be resolved to ExprMachineCast by typechecking."),
        ExprMachineCast = supported("C_BACKEND_DESIGN.md §8", "Machine casts lower through exact helper/direct conversion rules."),
        ExprIntrinsic = supported("C_BACKEND_DESIGN.md §8", "All MoonCore intrinsics lower through explicit helper semantics or target diagnostics."),
        ExprAddrOf = supported("C_BACKEND_DESIGN.md §9", "Address-of places lower through materialized residence/place analysis."),
        ExprDeref = supported("C_BACKEND_DESIGN.md §9", "Expression dereference lowers through safe place load rules."),
        ExprCall = supported("C_BACKEND_DESIGN.md §11", "Calls lower through exact direct/extern/indirect/closure ABI planning."),
        ExprLen = supported("C_BACKEND_DESIGN.md §10", "Array/slice/view length extraction lowers from storage or descriptors."),
        ExprField = supported("C_BACKEND_DESIGN.md §9", "Resolved field expressions lower by semantic layout facts."),
        ExprIndex = supported("C_BACKEND_DESIGN.md §9", "Index expressions lower through place/view/pointer address calculation."),
        ExprAgg = supported("C_BACKEND_DESIGN.md §12", "Aggregate literals lower through layout-aware storage initialization."),
        ExprArray = supported("C_BACKEND_DESIGN.md §12", "Array literals lower through fixed storage initialization."),
        ExprIf = supported("C_BACKEND_DESIGN.md §13", "If expressions lower to CFG branches and result joins."),
        ExprSelect = supported("C_BACKEND_DESIGN.md §8", "Select expressions lower directly for safe arms or via CFG when needed."),
        ExprSwitch = supported("C_BACKEND_DESIGN.md §13", "Switch expressions lower to CFG branches, default arm, and result joins."),
        ExprControl = supported("C_BACKEND_DESIGN.md §13", "Expression control regions lower inline to labels/gotos with yield result storage."),
        ExprBlock = supported("C_BACKEND_DESIGN.md §13", "Block expressions lower statements followed by an expression result."),
        ExprClosure = phase_unreachable("C_BACKEND_DESIGN.md §11", "Closure expressions must be closure-converted before backend projection."),
        ExprView = supported("C_BACKEND_DESIGN.md §10", "View expressions lower through complete descriptor construction rules."),
        ExprLoad = supported("C_BACKEND_DESIGN.md §9", "Explicit loads lower through memcpy/typed load helpers according to alignment and aliasing safety."),
        ExprAtomicLoad = supported("C_BACKEND_DESIGN.md §14", "Atomic loads lower through C11/runtime helpers with target feature checks."),
        ExprAtomicRmw = supported("C_BACKEND_DESIGN.md §14", "Atomic read-modify-write lowers through explicit operation/order helpers."),
        ExprAtomicCas = supported("C_BACKEND_DESIGN.md §14", "Compare-exchange lowers with exact expected/replacement/result semantics."),
        ExprSlotValue = phase_unreachable("C_BACKEND_DESIGN.md §8", "Open expression slots must be expanded before tree_to_code lowering."),
        ExprUseExprFrag = phase_unreachable("C_BACKEND_DESIGN.md §8", "Expression fragments must be expanded/spliced before tree_to_code lowering."),
        ExprCtor = supported("C_BACKEND_DESIGN.md §12", "Tagged-union constructors lower through shared tag/payload layout in native and C backends."),
        ExprNull = supported("C_BACKEND_DESIGN.md §8", "Null pointer expressions lower to typed data/code nulls."),
        ExprSizeOf = supported("C_BACKEND_DESIGN.md §7", "Sizeof lowers from target-aware semantic layout facts or prior integer literal rewrite."),
        ExprAlignOf = supported("C_BACKEND_DESIGN.md §7", "Alignof lowers from target-aware semantic layout facts or prior integer literal rewrite."),
        ExprIsNull = supported("C_BACKEND_DESIGN.md §8", "Null tests lower to explicit bool8 pointer comparisons."),
    },

    ["MoonTree.Stmt"] = {
        StmtLet = supported("C_BACKEND_DESIGN.md §15", "Immutable bindings lower through residence-aware locals or constants."),
        StmtVar = supported("C_BACKEND_DESIGN.md §15", "Mutable bindings lower through initialized storage residences."),
        StmtSet = supported("C_BACKEND_DESIGN.md §15", "Assignments lower through place-aware store semantics."),
        StmtAtomicStore = supported("C_BACKEND_DESIGN.md §14", "Atomic stores lower through C11/runtime helpers with ordering."),
        StmtAtomicFence = supported("C_BACKEND_DESIGN.md §14", "Atomic fences lower through target-checked fence helpers."),
        StmtExpr = supported("C_BACKEND_DESIGN.md §15", "Expression statements lower and discard expression results."),
        StmtAssert = supported("C_BACKEND_DESIGN.md §15", "Assertions lower to conditional trap paths."),
        StmtIf = supported("C_BACKEND_DESIGN.md §13", "Statement if lowers through CFG branch/join construction."),
        StmtSwitch = supported("C_BACKEND_DESIGN.md §13", "Scalar switch statements lower to switch/goto CFG; variant arms are tracked separately."),
        StmtJump = supported("C_BACKEND_DESIGN.md §13", "Block jumps lower to parallel block-parameter transfers and goto."),
        StmtJumpCont = phase_unreachable("C_BACKEND_DESIGN.md §13", "Continuation slots must be resolved by region expansion before tree_to_code lowering."),
        StmtYieldVoid = supported("C_BACKEND_DESIGN.md §13", "Void region yields lower to the region join/exit label."),
        StmtYieldValue = supported("C_BACKEND_DESIGN.md §13", "Value region yields assign the result temp and branch to the join label."),
        StmtReturnVoid = supported("C_BACKEND_DESIGN.md §15", "Void returns lower to CBackend return terminators."),
        StmtReturnValue = supported("C_BACKEND_DESIGN.md §15", "Value returns lower through ABI-aware return handling."),
        StmtControl = supported("C_BACKEND_DESIGN.md §13", "Statement control regions lower inline to labels/gotos."),
        StmtUseRegionSlot = phase_unreachable("C_BACKEND_DESIGN.md §13", "Open region slots must be expanded before tree_to_code lowering."),
        StmtUseRegionFrag = phase_unreachable("C_BACKEND_DESIGN.md §13", "Region fragments must be expanded/spliced before tree_to_code lowering."),
        StmtTrap = supported("C_BACKEND_DESIGN.md §15", "Traps lower to trap terminators/helpers."),
    },

    ["MoonTree.Func"] = {
        FuncLocal = supported("C_BACKEND_DESIGN.md §11", "Local functions lower to internal C functions with exact ABI."),
        FuncExport = supported("C_BACKEND_DESIGN.md §11", "Exported functions lower to exported/wrapper C functions with exact ABI."),
        FuncLocalContract = supported("C_BACKEND_DESIGN.md §11", "Local contract functions lower as functions after contract facts/diagnostics are handled."),
        FuncExportContract = supported("C_BACKEND_DESIGN.md §11", "Export contract functions lower as exports after contract facts/diagnostics are handled."),
        FuncDecl = supported("C_BACKEND_DESIGN.md §11", "Function declarations lower to prototypes/signature entries without bodies."),
        FuncOpen = phase_unreachable("C_BACKEND_DESIGN.md §11", "Open functions must be expanded before tree_to_code lowering."),
    },

    ["MoonTree.ExternFunc"] = {
        ExternFunc = supported("C_BACKEND_DESIGN.md §11", "Extern functions lower to exact symbol/header/signature declarations."),
        ExternFuncOpen = phase_unreachable("C_BACKEND_DESIGN.md §11", "Open extern functions must be expanded before tree_to_code lowering."),
    },

    ["MoonTree.ConstItem"] = {
        ConstItem = supported("C_BACKEND_DESIGN.md §16", "Typed constants lower to compile-time values or exact static data as required."),
        ConstItemOpen = phase_unreachable("C_BACKEND_DESIGN.md §16", "Open constants must be expanded before tree_to_code lowering."),
    },

    ["MoonTree.StaticItem"] = {
        StaticItem = supported("C_BACKEND_DESIGN.md §16", "Static items lower to exact typed globals/data initializers."),
        StaticItemOpen = phase_unreachable("C_BACKEND_DESIGN.md §16", "Open statics must be expanded before tree_to_code lowering."),
    },

    ["MoonTree.TypeDecl"] = {
        TypeDeclStruct = supported("C_BACKEND_DESIGN.md §7", "Struct declarations lower with explicit field layout facts and assertions."),
        TypeDeclUnion = supported("C_BACKEND_DESIGN.md §7", "Union declarations lower with explicit layout facts and assertions."),
        TypeDeclEnumSugar = supported("C_BACKEND_DESIGN.md §12", "Enum sugar lowers through resolved __tag layout facts shared by native and C backends."),
        TypeDeclTaggedUnionSugar = supported("C_BACKEND_DESIGN.md §12", "Tagged-union sugar lowers through shared __tag/__payload layout, constructors, and variant switches."),
        TypeDeclHandle = supported("C_BACKEND_DESIGN.md §7", "Handle declarations lower through their explicit representation field and layout assertions."),
        TypeDeclOpenStruct = phase_unreachable("C_BACKEND_DESIGN.md §7", "Open struct declarations must be expanded before tree_to_code lowering."),
        TypeDeclOpenUnion = phase_unreachable("C_BACKEND_DESIGN.md §7", "Open union declarations must be expanded before tree_to_code lowering."),
    },

    ["MoonTree.Item"] = {
        ItemFunc = supported("C_BACKEND_DESIGN.md §17", "Function items lower through the Func classification table."),
        ItemExtern = supported("C_BACKEND_DESIGN.md §17", "Extern items lower through the ExternFunc classification table."),
        ItemConst = supported("C_BACKEND_DESIGN.md §17", "Const items lower through the ConstItem classification table."),
        ItemStatic = supported("C_BACKEND_DESIGN.md §17", "Static items lower through exact data/global lowering."),
        ItemImport = phase_unreachable("C_BACKEND_DESIGN.md §17", "Unresolved imports must not reach tree_to_code/code_to_c lowering; the pipeline reports them explicitly."),
        ItemType = supported("C_BACKEND_DESIGN.md §17", "Type items lower through layout-backed C declarations."),
        ItemRegionFrag = phase_unreachable("C_BACKEND_DESIGN.md §17", "Region fragments are frontend templates and must be expanded or stripped before tree_to_code lowering."),
        ItemExprFrag = phase_unreachable("C_BACKEND_DESIGN.md §17", "Expression fragments are frontend templates and must be expanded or stripped before tree_to_code lowering."),
        ItemUseTypeDeclSlot = phase_unreachable("C_BACKEND_DESIGN.md §17", "Open type-declaration slots must be expanded before tree_to_code lowering."),
        ItemUseItemsSlot = phase_unreachable("C_BACKEND_DESIGN.md §17", "Open items slots must be expanded before tree_to_code lowering."),
        ItemUseModule = supported("C_BACKEND_DESIGN.md §17", "Nested module uses lower recursively after fills are resolved."),
        ItemUseModuleSlot = phase_unreachable("C_BACKEND_DESIGN.md §17", "Open module slots must be expanded before tree_to_code lowering."),
        ItemData = supported("C_BACKEND_DESIGN.md §16", "Data items lower to exact byte/global initializers."),
    },

    ["MoonTree.SwitchStmtArm"] = {
        SwitchStmtArm = supported("C_BACKEND_DESIGN.md §13", "Scalar switch statement arms lower to case-labelled CFG targets."),
    },

    ["MoonTree.SwitchExprArm"] = {
        SwitchExprArm = supported("C_BACKEND_DESIGN.md §13", "Scalar switch expression arms lower to case-labelled CFG targets with result joins."),
    },

    ["MoonTree.SwitchVariantStmtArm"] = {
        SwitchVariantStmtArm = supported("C_BACKEND_DESIGN.md §13", "Variant switch statement arms lower through tag cases, payload binds, and CFG bodies."),
    },

    ["MoonTree.SwitchVariantExprArm"] = {
        SwitchVariantExprArm = supported("C_BACKEND_DESIGN.md §13", "Variant switch expression arms lower through tag cases, payload binds, result assignment, and joins."),
    },

    ["MoonTree.ControlProducts"] = {
        VariantBind = supported("C_BACKEND_DESIGN.md §13", "Variant payload binds lower to arm-local payload loads using shared layout offsets."),
        BlockLabel = supported("C_BACKEND_DESIGN.md §13", "Block labels lower to deterministic C labels."),
        BlockParam = supported("C_BACKEND_DESIGN.md §13", "Block parameters lower to CFG locals with parallel transfer semantics."),
        EntryBlockParam = supported("C_BACKEND_DESIGN.md §13", "Entry parameters lower to initialized CFG locals."),
        JumpArg = supported("C_BACKEND_DESIGN.md §13", "Jump arguments lower via parallel transfer temporaries."),
        EntryControlBlock = supported("C_BACKEND_DESIGN.md §13", "Entry control blocks lower to the first generated C label/block."),
        ControlBlock = supported("C_BACKEND_DESIGN.md §13", "Control blocks lower to C labels and terminators."),
        ControlStmtRegion = supported("C_BACKEND_DESIGN.md §13", "Statement regions lower inline to labels/gotos."),
        ControlExprRegion = supported("C_BACKEND_DESIGN.md §13", "Expression regions lower inline with result temp and join label."),
        ControlVariantArmFact = supported("C_BACKEND_DESIGN.md §13", "Variant control facts are emitted from typed switches and consumed by native/C control lowering."),
        ImportItem = phase_unreachable("C_BACKEND_DESIGN.md §17", "Imports must be resolved before backend item lowering."),
        DataItem = supported("C_BACKEND_DESIGN.md §16", "Data products lower to exact bytes with size/alignment validation."),
    },

    ["MoonCore.UnaryOp"] = {
        UnaryNeg = supported("C_BACKEND_DESIGN.md §14", "Negation lowers through UB-free signed/float helper semantics when required."),
        UnaryNot = supported("C_BACKEND_DESIGN.md §14", "Logical not lowers to normalized bool8."),
        UnaryBitNot = supported("C_BACKEND_DESIGN.md §14", "Bitwise not lowers through exact-width integer helper semantics."),
    },

    ["MoonCore.BinaryOp"] = {
        BinAdd = supported("C_BACKEND_DESIGN.md §14", "Addition lowers with wrapping/float/pointer semantics via helpers where needed."),
        BinSub = supported("C_BACKEND_DESIGN.md §14", "Subtraction lowers with wrapping/float/pointer semantics via helpers where needed."),
        BinMul = supported("C_BACKEND_DESIGN.md §14", "Multiplication lowers with wrapping/float semantics via helpers where needed."),
        BinDiv = supported("C_BACKEND_DESIGN.md §14", "Division lowers with zero and signed-overflow checks."),
        BinRem = supported("C_BACKEND_DESIGN.md §14", "Remainder lowers with zero and signed-overflow checks."),
        BinBitAnd = supported("C_BACKEND_DESIGN.md §14", "Bitwise and lowers with exact-width unsigned helper semantics."),
        BinBitOr = supported("C_BACKEND_DESIGN.md §14", "Bitwise or lowers with exact-width unsigned helper semantics."),
        BinBitXor = supported("C_BACKEND_DESIGN.md §14", "Bitwise xor lowers with exact-width unsigned helper semantics."),
        BinShl = supported("C_BACKEND_DESIGN.md §14", "Left shift lowers with masked counts and exact-width wrapping semantics."),
        BinLShr = supported("C_BACKEND_DESIGN.md §14", "Logical shift right lowers with masked counts and unsigned semantics."),
        BinAShr = supported("C_BACKEND_DESIGN.md §14", "Arithmetic shift right lowers with explicit sign-preserving helper semantics."),
    },

    ["MoonCore.CmpOp"] = {
        CmpEq = supported("C_BACKEND_DESIGN.md §14", "Equality lowers to explicit typed comparisons."),
        CmpNe = supported("C_BACKEND_DESIGN.md §14", "Inequality lowers to explicit typed comparisons."),
        CmpLt = supported("C_BACKEND_DESIGN.md §14", "Less-than lowers to explicit signed/unsigned/float comparisons."),
        CmpLe = supported("C_BACKEND_DESIGN.md §14", "Less-equal lowers to explicit signed/unsigned/float comparisons."),
        CmpGt = supported("C_BACKEND_DESIGN.md §14", "Greater-than lowers to explicit signed/unsigned/float comparisons."),
        CmpGe = supported("C_BACKEND_DESIGN.md §14", "Greater-equal lowers to explicit signed/unsigned/float comparisons."),
    },

    ["MoonCore.LogicOp"] = {
        LogicAnd = supported("C_BACKEND_DESIGN.md §14", "Logical and lowers with short-circuit CFG and bool normalization."),
        LogicOr = supported("C_BACKEND_DESIGN.md §14", "Logical or lowers with short-circuit CFG and bool normalization."),
    },

    ["MoonCore.SurfaceCastOp"] = {
        SurfaceCast = phase_unreachable("C_BACKEND_DESIGN.md §8", "Surface casts must be typechecked into machine casts before tree_to_code lowering."),
        SurfaceTrunc = phase_unreachable("C_BACKEND_DESIGN.md §8", "Surface trunc casts must not reach tree_to_code lowering directly."),
        SurfaceZExt = phase_unreachable("C_BACKEND_DESIGN.md §8", "Surface zero-extend casts must not reach tree_to_code lowering directly."),
        SurfaceSExt = phase_unreachable("C_BACKEND_DESIGN.md §8", "Surface sign-extend casts must not reach tree_to_code lowering directly."),
        SurfaceBitcast = phase_unreachable("C_BACKEND_DESIGN.md §8", "Surface bitcasts must not reach tree_to_code lowering directly."),
        SurfaceSatCast = phase_unreachable("C_BACKEND_DESIGN.md §8", "Surface saturating casts must not reach tree_to_code lowering directly."),
    },

    ["MoonCore.MachineCastOp"] = {
        MachineCastIdentity = supported("C_BACKEND_DESIGN.md §14", "Identity casts preserve typed value representation."),
        MachineCastBitcast = supported("C_BACKEND_DESIGN.md §14", "Bitcasts lower through memcpy/union-safe helper semantics."),
        MachineCastIreduce = supported("C_BACKEND_DESIGN.md §14", "Integer reduction lowers through exact-width truncation helpers."),
        MachineCastSextend = supported("C_BACKEND_DESIGN.md §14", "Signed extension lowers through exact-width signed conversions."),
        MachineCastUextend = supported("C_BACKEND_DESIGN.md §14", "Unsigned extension lowers through exact-width unsigned conversions."),
        MachineCastFpromote = supported("C_BACKEND_DESIGN.md §14", "Float promotion lowers through safe C float conversion."),
        MachineCastFdemote = supported("C_BACKEND_DESIGN.md §14", "Float demotion lowers through safe C float conversion."),
        MachineCastSToF = supported("C_BACKEND_DESIGN.md §14", "Signed integer to float lowers with explicit edge handling where needed."),
        MachineCastUToF = supported("C_BACKEND_DESIGN.md §14", "Unsigned integer to float lowers with explicit edge handling where needed."),
        MachineCastFToS = supported("C_BACKEND_DESIGN.md §14", "Float to signed integer lowers through range-checked helper semantics."),
        MachineCastFToU = supported("C_BACKEND_DESIGN.md §14", "Float to unsigned integer lowers through range-checked helper semantics."),
    },

    ["MoonCore.Intrinsic"] = {
        IntrinsicPopcount = supported("C_BACKEND_DESIGN.md §14", "Popcount lowers through exact-width builtin/helper semantics."),
        IntrinsicClz = supported("C_BACKEND_DESIGN.md §14", "Count-leading-zero lowers with explicit zero handling."),
        IntrinsicCtz = supported("C_BACKEND_DESIGN.md §14", "Count-trailing-zero lowers with explicit zero handling."),
        IntrinsicRotl = supported("C_BACKEND_DESIGN.md §14", "Rotate-left lowers with masked counts."),
        IntrinsicRotr = supported("C_BACKEND_DESIGN.md §14", "Rotate-right lowers with masked counts."),
        IntrinsicBswap = supported("C_BACKEND_DESIGN.md §14", "Byte swap lowers through exact-width helper/builtin semantics."),
        IntrinsicFma = supported("C_BACKEND_DESIGN.md §14", "FMA lowers through target-checked libm/helper semantics."),
        IntrinsicSqrt = supported("C_BACKEND_DESIGN.md §14", "Sqrt lowers through target-checked libm/helper semantics."),
        IntrinsicAbs = supported("C_BACKEND_DESIGN.md §14", "Abs lowers through signed/float edge-case helpers."),
        IntrinsicFloor = supported("C_BACKEND_DESIGN.md §14", "Floor lowers through target-checked libm/helper semantics."),
        IntrinsicCeil = supported("C_BACKEND_DESIGN.md §14", "Ceil lowers through target-checked libm/helper semantics."),
        IntrinsicTruncFloat = supported("C_BACKEND_DESIGN.md §14", "Floating trunc lowers through target-checked libm/helper semantics."),
        IntrinsicRound = supported("C_BACKEND_DESIGN.md §14", "Round lowers through target-checked libm/helper semantics."),
        IntrinsicTrap = supported("C_BACKEND_DESIGN.md §14", "Trap lowers to the backend trap helper/terminator."),
        IntrinsicAssume = supported("C_BACKEND_DESIGN.md §14", "Assume lowers to target-checked assumption or diagnostic-preserving no-op."),
    },

    ["MoonCore.AtomicOrdering"] = {
        AtomicSeqCst = supported("C_BACKEND_DESIGN.md §14", "Sequential consistency maps to C11/runtime atomic order seq_cst."),
    },

    ["MoonCore.AtomicRmwOp"] = {
        AtomicRmwAdd = supported("C_BACKEND_DESIGN.md §14", "Atomic add maps to explicit fetch-add helper semantics."),
        AtomicRmwSub = supported("C_BACKEND_DESIGN.md §14", "Atomic sub maps to explicit fetch-sub helper semantics."),
        AtomicRmwAnd = supported("C_BACKEND_DESIGN.md §14", "Atomic and maps to explicit fetch-and helper semantics."),
        AtomicRmwOr = supported("C_BACKEND_DESIGN.md §14", "Atomic or maps to explicit fetch-or helper semantics."),
        AtomicRmwXor = supported("C_BACKEND_DESIGN.md §14", "Atomic xor maps to explicit fetch-xor helper semantics."),
        AtomicRmwXchg = supported("C_BACKEND_DESIGN.md §14", "Atomic exchange maps to explicit exchange helper semantics."),
    },
}

local aliases = {}
for sum_name in pairs(tables) do
    local short = sum_name:match("%.([^%.]+)$")
    if short and aliases[short] == nil then aliases[short] = sum_name end
end
aliases.ControlProducts = "MoonTree.ControlProducts"

local function canonical_sum_name(sum_name)
    if tables[sum_name] then return sum_name end
    return aliases[sum_name]
end

function M.classification(sum_name, variant_name)
    local canonical = canonical_sum_name(sum_name)
    if not canonical then return nil end
    return tables[canonical][variant_name]
end

function M.assert_known(sum_name, variant_name)
    local c = M.classification(sum_name, variant_name)
    if c == nil then
        error(string.format("missing C backend coverage classification for %s.%s", tostring(sum_name), tostring(variant_name)), 2)
    end
    return c
end

function M.all_tables()
    return tables
end

function M.statuses()
    return VALID_STATUS
end

return M
