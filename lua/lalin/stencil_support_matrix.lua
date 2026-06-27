local function bind_context(T)
    local Code = T.LalinCode

    local M = {}

    M.status = {
        supported = "supported",
        rejected = "rejected",
        future = "future",
    }

    M.materializer_status = {
        materialized = "materialized",
        materialized_center_domain = "materialized_center_domain",
        typed_reject = "typed_reject",
        covered = "covered",
        partial = "partial",
        future = "future",
    }

    M.coverage_policy = {
        semantic_probe = "semantic_probe",
        fast_subset = "fast_subset",
        deployment_bank = "deployment_bank",
    }

    M.vocabs = {
        StencilApply = { status = "supported", scope = "primitive generator for elementwise, copy/fill/cast/compare/select, gather/scatter, and current generated partition artifacts" },
        StencilReduce = { status = "supported", scope = "primitive generator for folds plus generated count/find and generic reduce_n fusion artifacts" },
        StencilScan = { status = "supported", scope = "primitive generator for axis-aware prefix reductions; copy_patch_mc and LuaTrace materialize Range1D and RangeND axis scans" },
        StencilScatterReduce = { status = "supported", scope = "primitive generator for indexed accumulation/reduce_by_index over an externally initialized destination" },
    }

    M.derived_plans = {
        map = { status = "supported", basis = "StencilApply", scope = "unary apply over one input lane" },
        zip_map = { status = "supported", basis = "StencilApply", scope = "binary apply over two input lanes" },
        copy = { status = "supported", basis = "StencilApply", scope = "identity apply with copy overlap contract" },
        copy_memmove = { status = "supported", basis = "StencilApply", scope = "identity apply with memmove overlap contract" },
        fill = { status = "supported", basis = "StencilApply", scope = "fill apply with scalar value" },
        cast = { status = "supported", basis = "StencilApply", scope = "cast apply" },
        compare = { status = "supported", basis = "StencilApply", scope = "predicate apply to bool8 result" },
        zip_compare = { status = "supported", basis = "StencilApply", scope = "comparison apply over two input lanes" },
        select = { status = "supported", basis = "StencilApply", scope = "predicate-controlled blend apply" },
        apply_n = { status = "supported", basis = "StencilApply", scope = "generic expression-backed ApplyN with arity capped at 4" },
        gather = { status = "supported", basis = "StencilApply", scope = "identity apply with indexed read layout" },
        scatter = { status = "supported", basis = "StencilApply", scope = "identity apply with indexed write layout and conflict contract" },
        scatter_reduce = { status = "supported", basis = "StencilScatterReduce", scope = "indexed accumulation with reducer over readwrite destination layout" },
        in_place_map = { status = "supported", basis = "StencilApply", scope = "unary apply over readwrite lane" },
        partition = { status = "supported", basis = "StencilApply", scope = "current generated partition artifact; target derivation is apply + scan + scatter" },
        reduce = { status = "supported", basis = "StencilReduce", scope = "plain fold" },
        count = { status = "supported", basis = "StencilReduce", scope = "predicate apply fused into count reduction" },
        find = { status = "supported", basis = "StencilReduce", scope = "predicate apply fused into min-index/not-found reduction" },
        reduce_n = { status = "supported", basis = "StencilReduce", scope = "generic expression-backed ApplyN fused into fold with arity capped at 4" },
        scan = { status = "supported", basis = "StencilScan", scope = "prefix fold" },
        scan_n = { status = "supported", basis = "StencilScan", scope = "generic expression-backed ApplyN fused into prefix fold with arity capped at 4; MC and BC support Range1D plus RangeND axis scan" },
    }

    M.layouts = {
        StencilLayoutScalar = { status = "supported", scope = "reduction accumulators/control values, not memory lanes" },
        StencilLayoutContiguous = { status = "supported", scope = "generated ApplyN/ReduceN/ScanN basis layout" },
        StencilLayoutIndexed = { status = "supported", scope = "generated ApplyN/ReduceN/ScanN basis layout with explicit index access reference" },
        StencilLayoutAffine1D = { status = "supported", scope = "generated ApplyN/ReduceN/ScanN/ScatterReduceN basis layout for affine 1D access remapping" },
        StencilLayoutAffineND = { status = "partial", scope = "MC/C ApplyN over RangeND with constant axis coefficients; dynamic coefficients and BC coverage remain open" },
        StencilLayoutFieldProjection = { status = "supported", scope = "generated ApplyN/ReduceN/ScanN basis layout with record-pointer ABI projection" },
        StencilLayoutSoAComponent = { status = "supported", scope = "generated ApplyN/ReduceN/ScanN basis layout over component buffers" },
        StencilLayoutSliceDescriptor = { status = "supported", scope = "generated ApplyN/ReduceN/ScanN basis layout" },
        StencilLayoutByteSpanDescriptor = { status = "supported", scope = "generated ApplyN/ReduceN/ScanN basis layout" },
        StencilLayoutViewDescriptor = { status = "supported", scope = "generated ApplyN/ReduceN/ScanN basis layout with dynamic stride parameterization" },
    }

    M.producers = {
        StencilProduceRange1D = {
            status = "supported",
            scope = "shape-supported; positive forward ranges materialize in BC, MC, and emitted-bank cells",
            shape = "supported",
            copy_patch_bc = "materialized",
            copy_patch_mc = "materialized",
            bank = "covered",
        },
        StencilProduceRangeND = {
            status = "supported",
            scope = "shape-supported; forward ND ranges materialize in copy_patch_bc and copy_patch_mc generic ApplyN/domain-ReduceN/axis-ReduceN/axis-ScanN plus emitted-bank cells",
            shape = "supported",
            copy_patch_bc = "materialized",
            copy_patch_mc = "materialized",
            bank = "covered",
        },
        StencilProduceWindowND = {
            status = "supported",
            scope = "shape-supported; center-domain WindowND materializes in copy_patch_mc generic ApplyN/domain-ReduceN/axis-ScanN, window-neighbor apply, and window-local reduce; BC rejects with typed producer facts",
            shape = "supported",
            copy_patch_bc = "typed_reject",
            copy_patch_bc_gap = "semantic BC producer materializer does not yet execute WindowND loops or window-relative body inputs",
            copy_patch_mc = "materialized_center_domain",
            bank = "covered",
        },
        StencilProduceTiledND = {
            status = "supported",
            scope = "shape-supported; forward tiled ND loops materialize in copy_patch_mc generic ApplyN/domain-ReduceN/axis-ScanN and emitted-bank cells; BC rejects with typed producer facts",
            shape = "supported",
            copy_patch_bc = "typed_reject",
            copy_patch_bc_gap = "semantic BC producer materializer does not yet execute tiled ND loops",
            copy_patch_mc = "materialized",
            bank = "covered",
        },
    }

    M.predicates = {
        StencilPredNonZero = { status = "supported", scope = "numeric/bool scalar predicate" },
        StencilPredCompareConst = { status = "supported", scope = "typed scalar comparison against a literal constant" },
        StencilPredRange = { status = "supported", scope = "typed scalar lower/upper-bound predicate" },
        StencilPredAnd = { status = "supported", scope = "compound scalar predicate conjunction" },
        StencilPredOr = { status = "supported", scope = "compound scalar predicate disjunction" },
        StencilPredNot = { status = "supported", scope = "compound scalar predicate negation" },
        StencilPredIsNaN = { status = "supported", scope = "float scalar NaN classification" },
        StencilPredIsInf = { status = "supported", scope = "float scalar infinity classification" },
        StencilPredIsFinite = { status = "supported", scope = "float scalar finite classification" },
    }

    M.type_families = {
        CodeTyBool8 = { status = "supported", scope = "bool8 scalar cells" },
        CodeTyInt = { status = "supported", scope = "8/16/32/64 signed and unsigned scalar cells" },
        CodeTyFloat = { status = "supported", scope = "f32/f64 scalar cells; no bitwise reductions" },
        CodeTyIndex = { status = "supported", scope = "index scalar cells and index-lane classification" },
        CodeTyVoid = { status = "rejected", scope = "not an element type" },
        CodeTyDataPtr = { status = "supported", scope = "pointer-valued element lanes for copy/fill/gather/scatter/identity-map" },
        CodeTyCodePtr = { status = "supported", scope = "code-pointer element lanes for copy/fill/gather/scatter/identity-map" },
        CodeTyNamed = { status = "supported", scope = "whole-record element lanes for copy/fill/gather/scatter/identity-map" },
        CodeTyArray = { status = "supported", scope = "whole-array element lanes for copy/fill/gather/scatter/identity-map" },
        CodeTySlice = { status = "supported", scope = "descriptor-valued element lanes for copy/fill/gather/scatter/identity-map" },
        CodeTyView = { status = "supported", scope = "descriptor-valued element lanes for copy/fill/gather/scatter/identity-map" },
        CodeTyByteSpan = { status = "supported", scope = "descriptor-valued element lanes for copy/fill/gather/scatter/identity-map" },
        CodeTyHandle = { status = "supported", scope = "handle representation element lanes for copy/fill/gather/scatter/identity-map" },
        CodeTyLease = { status = "supported", scope = "lease representation element lanes for copy/fill/gather/scatter/identity-map" },
        CodeTyClosure = { status = "supported", scope = "closure descriptor element lanes for copy/fill/gather/scatter/identity-map" },
        CodeTyImportedC = { status = "supported", scope = "imported C element lanes for copy/fill/gather/scatter/identity-map" },
        CodeTyImportedCFuncPtr = { status = "supported", scope = "imported C function-pointer lanes for copy/fill/gather/scatter/identity-map" },
        CodeTyVector = { status = "supported", scope = "vector element lanes for copy/fill/gather/scatter/identity-map" },
    }

    M.materializers = {
        copy_patch_bc = {
            status = "supported",
            policy = M.coverage_policy.semantic_probe,
            fallback_rank = 2,
            scope = "semantic LuaTrace bytecode materializer; it is the correctness probe and must either materialize a supported cell or expose an exact typed unsupported cell",
        },
        copy_patch_mc = {
            status = "supported",
            policy = M.coverage_policy.fast_subset,
            fallback = "copy_patch_bc",
            fallback_rank = 1,
            scope = "fast machine-code subset from explicit compiled artifacts; missing fast cells can explicitly fall back to copy_patch_bc when the semantic materializer supports the cell",
        },
        emitted_bank = {
            status = "supported",
            policy = M.coverage_policy.deployment_bank,
            fallback = "copy_patch_bc",
            fallback_rank = 0,
            scope = "deployment bank containing the intended interned BC/MC artifacts; missing or stale entries must be visible, with explicit BC fallback available instead of silent satisfaction",
        },
    }

    function M.producer_materializer_status(producer_name, materializer)
        local row = M.producers[producer_name]
        if row == nil then return nil end
        if materializer == "copy_patch_bc" then return row.copy_patch_bc end
        if materializer == "copy_patch_mc" then return row.copy_patch_mc end
        if materializer == "emitted_bank" then return row.bank end
        return nil
    end

    function M.copy_patch_bc_semantic_gap(producer_name)
        local row = M.producers[producer_name]
        if row == nil or row.shape ~= "supported" then return nil end
        if row.copy_patch_bc == M.materializer_status.materialized then return nil end
        return row.copy_patch_bc_gap or ("copy_patch_bc does not materialize " .. tostring(producer_name))
    end

    M.artifact_constructors = {
        map = "map_array_artifact",
        zip_map = "zip_map_array_artifact",
        scan = "scan_array_artifact",
        copy = "copy_array_artifact",
        copy_memmove = "copy_array_artifact",
        fill = "fill_array_artifact",
        find = "find_array_artifact",
        partition = "partition_array_artifact",
        cast = "cast_array_artifact",
        compare = "compare_array_artifact",
        zip_compare = "zip_compare_array_artifact",
        select = "select_array_artifact",
        apply_n = "apply_n_artifact",
        gather = "gather_array_artifact",
        scatter = "scatter_array_artifact",
        scatter_reduce = "scatter_reduce_n_artifact",
        in_place_map = "in_place_map_array_artifact",
        reduce = "reduce_array_artifact",
        count = "count_array_artifact",
        reduce_n = "reduce_n_artifact",
        scan_n = "scan_n_artifact",
    }

    function M.type_family_for(ty)
        local cls = require("lalin.pvm").classof(ty)
        if ty == Code.CodeTyBool8 then return "CodeTyBool8" end
        if ty == Code.CodeTyIndex then return "CodeTyIndex" end
        if cls == nil then return tostring(ty) end
        local name = tostring(cls):match("Class%((.-)%)") or tostring(cls)
        return name:match("%.([^%.]+)$") or name
    end

    function M.entry(table_name, key)
        local table_ = M[table_name]
        return table_ and table_[key] or nil
    end

    return M
end

return bind_context
