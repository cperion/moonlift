local function bind_context(T)
    local Code = T.LalinCode

    local M = {}

    M.status = {
        supported = "supported",
        rejected = "rejected",
        future = "future",
    }

    M.vocabs = {
        StencilReduce = { status = "supported", scope = "scalar selection/artifact/luatrace; partial MC intern coverage" },
        StencilMap = { status = "supported", scope = "scalar selection/artifact/luatrace; partial MC intern coverage" },
        StencilZipMap = { status = "supported", scope = "matching scalar lhs/rhs/result" },
        StencilScan = { status = "supported", scope = "scalar reductions; thin runtime matrix" },
        StencilCopy = { status = "supported", scope = "scalar and selected byte-span cells" },
        StencilFill = { status = "supported", scope = "scalar and selected byte-span cells" },
        StencilFind = { status = "supported", scope = "scalar predicates; selected runtime cells" },
        StencilPartition = { status = "supported", scope = "scalar predicates; stable semantics path" },
        StencilCast = { status = "supported", scope = "scalar casts; incomplete cast-op matrix tests" },
        StencilCompare = { status = "supported", scope = "scalar predicate-to-bool8" },
        StencilZipCompare = { status = "supported", scope = "matching scalar lhs/rhs to bool8" },
        StencilSelect = { status = "supported", scope = "scalar predicate-controlled then/else blend" },
        StencilGather = { status = "supported", scope = "scalar elements with index data lanes" },
        StencilScatter = { status = "supported", scope = "scalar elements with index data lanes" },
        StencilInPlaceMap = { status = "supported", scope = "scalar unary maps where src/dst match" },
        StencilCount = { status = "supported", scope = "scalar predicate count to i32" },
        StencilMapReduce = { status = "supported", scope = "scalar unary map plus supported reduction" },
        StencilZipReduce = { status = "supported", scope = "matching scalar zip-map plus supported reduction" },
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
        StencilReduce = "reduce_array_artifact",
        StencilMap = "map_array_artifact",
        StencilZipMap = "zip_map_array_artifact",
        StencilScan = "scan_array_artifact",
        StencilCopy = "copy_array_artifact",
        StencilFill = "fill_array_artifact",
        StencilFind = "find_array_artifact",
        StencilPartition = "partition_array_artifact",
        StencilCast = "cast_array_artifact",
        StencilCompare = "compare_array_artifact",
        StencilZipCompare = "zip_compare_array_artifact",
        StencilSelect = "select_array_artifact",
        StencilGather = "gather_array_artifact",
        StencilScatter = "scatter_array_artifact",
        StencilInPlaceMap = "in_place_map_array_artifact",
        StencilCount = "count_array_artifact",
        StencilMapReduce = "map_reduce_array_artifact",
        StencilZipReduce = "zip_reduce_array_artifact",
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
