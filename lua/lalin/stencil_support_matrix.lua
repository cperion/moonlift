local function bind_context(T)
    local Code = T.LalinCode

    local M = {}

    M.status = {
        supported = "supported",
        rejected = "rejected",
        future = "future",
    }

    M.vocabs = {
        StencilApply = { status = "supported", scope = "primitive generator for elementwise, copy/fill/cast/compare/select, gather/scatter, and current generated partition artifacts" },
        StencilReduce = { status = "supported", scope = "primitive generator for folds plus generated count/find and generic reduce_n fusion artifacts" },
        StencilScan = { status = "supported", scope = "primitive generator for prefix reductions and generated filter/partition plans" },
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
        gather = { status = "supported", basis = "StencilApply", scope = "identity apply with indexed read topology" },
        scatter = { status = "supported", basis = "StencilApply", scope = "identity apply with indexed write topology and conflict contract" },
        in_place_map = { status = "supported", basis = "StencilApply", scope = "unary apply over readwrite lane" },
        partition = { status = "supported", basis = "StencilApply", scope = "current generated partition artifact; target derivation is apply + scan + scatter" },
        reduce = { status = "supported", basis = "StencilReduce", scope = "plain fold" },
        count = { status = "supported", basis = "StencilReduce", scope = "predicate apply fused into count reduction" },
        find = { status = "supported", basis = "StencilReduce", scope = "predicate apply fused into min-index/not-found reduction" },
        reduce_n = { status = "supported", basis = "StencilReduce", scope = "generic expression-backed ApplyN fused into fold with arity capped at 4" },
        scan = { status = "supported", basis = "StencilScan", scope = "prefix fold" },
    }

    M.topologies = {
        StencilTopologyScalar = { status = "supported", scope = "reduction accumulators/control values, not memory lanes" },
        StencilTopologyContiguous = { status = "supported", scope = "primary scalar array topology" },
        StencilTopologyIndexed = { status = "supported", scope = "gather/scatter index lanes" },
        StencilTopologyInPlace = { status = "supported", scope = "in-place map source/destination" },
        StencilTopologyFieldProjection = { status = "supported", scope = "partial vocab matrix" },
        StencilTopologySoAComponent = { status = "supported", scope = "partial vocab matrix" },
        StencilTopologySliceDescriptor = { status = "supported", scope = "current i32 scalar matrix" },
        StencilTopologyByteSpanDescriptor = { status = "supported", scope = "u8 byte operation subset" },
        StencilTopologyViewDescriptor = { status = "supported", scope = "current i32 scalar matrix with dynamic stride" },
    }

    M.domains = {
        StencilDomainRange1D = { status = "supported", scope = "only materialized stencil iteration domain today" },
        StencilDomainRangeND = { status = "future", scope = "represented for ND iteration, rejected by current 1D materializers" },
        StencilDomainWindowND = { status = "future", scope = "represented for neighborhood/windowed stencil kernels, rejected by current 1D materializers" },
        StencilDomainTiledND = { status = "future", scope = "represented for blocked/tiled ND iteration, rejected by current 1D materializers" },
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
            scope = "semantic LuaTrace bytecode materializer for supported artifact shapes",
        },
        copy_patch_mc = {
            status = "supported",
            scope = "fast embedded machine-code subset from explicit intern set",
        },
    }

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
        apply_n = "apply_n_array_artifact",
        gather = "gather_array_artifact",
        scatter = "scatter_array_artifact",
        in_place_map = "in_place_map_array_artifact",
        reduce = "reduce_array_artifact",
        count = "count_array_artifact",
        reduce_n = "reduce_n_array_artifact",
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
