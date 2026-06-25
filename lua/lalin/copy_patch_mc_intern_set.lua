local function bind_context(T)
    local Core = T.LalinCore
    local Code = T.LalinCode
    local Ty = T.LalinType
    local Value = T.LalinValue
    local Schedule = T.LalinSchedule
    local Stencil = T.LalinStencil
    local Matrix = require("lalin.stencil_support_matrix")(T)
    local Plan = require("lalin.stencil_artifact_plan")(T)

    local M = {}

    local i32 = Code.CodeTyInt(32, Code.CodeSigned)
    local u8 = Code.CodeTyInt(8, Code.CodeUnsigned)
    local f64 = Code.CodeTyFloat(64)
    local bool8 = Code.CodeTyBool8
    local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)
    local pair_ty = Code.CodeTyNamed("Demo", "Pair", Ty.TNamed(Ty.TypeRefGlobal("Demo", "Pair")))
    local pair_soa_ty = Code.CodeTyNamed("Demo", "PairSoA", Ty.TNamed(Ty.TypeRefGlobal("Demo", "PairSoA")))

    local function iconst(raw)
        return Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt(tostring(raw))))
    end

    local function u8const(raw)
        return Value.ValueExprConst(Code.CodeConstLiteral(u8, Core.LitInt(tostring(raw))))
    end

    local function pred(cmp, ty, value)
        return Stencil.StencilPredCompareConst(cmp, ty, value)
    end

    local function reduction(kind, init)
        return {
            kind = kind,
            init = iconst(init),
            int_semantics = sem,
            float_mode = nil,
        }
    end

    local function view_topology(name)
        return Stencil.StencilTopologyViewDescriptor(
            Code.CodeValueId("v:view:" .. name),
            Code.CodeValueId("v:data:" .. name),
            Code.CodeValueId("v:len:" .. name),
            Code.CodeValueId("v:stride:" .. name),
            nil
        )
    end

    local function slice_topology(name)
        return Stencil.StencilTopologySliceDescriptor(
            Code.CodeValueId("v:slice:" .. name),
            Code.CodeValueId("v:data:" .. name),
            Code.CodeValueId("v:len:" .. name)
        )
    end

    local function bytespan_topology(name)
        return Stencil.StencilTopologyByteSpanDescriptor(
            Code.CodeValueId("v:bytespan:" .. name),
            Code.CodeValueId("v:data:" .. name),
            Code.CodeValueId("v:len:" .. name)
        )
    end

    local function field_topology()
        return Stencil.StencilTopologyFieldProjection(
            Stencil.StencilTopologyContiguous(1),
            pair_ty,
            "right",
            4
        )
    end

    local function soa_component(field_name, component_index)
        return Stencil.StencilTopologySoAComponent(
            Stencil.StencilTopologyContiguous(1),
            pair_soa_ty,
            field_name,
            component_index
        )
    end

    local topology_groups = {
        contiguous = {
            topology = "StencilTopologyContiguous",
            top = function() return nil end,
        },
        view = {
            topology = "StencilTopologyViewDescriptor",
            top = view_topology,
        },
        slice = {
            topology = "StencilTopologySliceDescriptor",
            top = slice_topology,
        },
    }

    local base_rows = {
        { kind = "reduce", vocab = "StencilReduce" },
        { kind = "map", vocab = "StencilMap" },
        { kind = "zip_map", vocab = "StencilZipMap" },
        { kind = "scan", vocab = "StencilScan" },
        { kind = "copy", vocab = "StencilCopy" },
        { kind = "copy_memmove", vocab = "StencilCopy" },
        { kind = "fill", vocab = "StencilFill" },
        { kind = "find", vocab = "StencilFind" },
        { kind = "partition", vocab = "StencilPartition" },
        { kind = "cast", vocab = "StencilCast" },
        { kind = "compare", vocab = "StencilCompare" },
        { kind = "zip_compare", vocab = "StencilZipCompare" },
        { kind = "select", vocab = "StencilSelect" },
        { kind = "gather", vocab = "StencilGather" },
        { kind = "scatter", vocab = "StencilScatter" },
        { kind = "in_place_map", vocab = "StencilInPlaceMap" },
        { kind = "count", vocab = "StencilCount" },
        { kind = "map_reduce", vocab = "StencilMapReduce" },
        { kind = "zip_reduce", vocab = "StencilZipReduce" },
    }

    local schedule_variants = {
        { name = "scalar" },
        {
            name = "v4",
            schedule = function()
                return Schedule.ScheduleVector(Schedule.LaneVector(i32, 4), 1, 1, Schedule.TailScalar)
            end,
        },
    }

    local extra_cells = {
        { name = "byte_span.copy.u8", vocab = "StencilCopy", topology = "StencilTopologyByteSpanDescriptor", kind = "byte_copy" },
        { name = "byte_span.copy_memmove.u8", vocab = "StencilCopy", topology = "StencilTopologyByteSpanDescriptor", kind = "byte_copy_memmove" },
        { name = "byte_span.fill.u8", vocab = "StencilFill", topology = "StencilTopologyByteSpanDescriptor", kind = "byte_fill" },
        { name = "byte_span.find.u8", vocab = "StencilFind", topology = "StencilTopologyByteSpanDescriptor", kind = "byte_find" },
        { name = "byte_span.compare.u8", vocab = "StencilCompare", topology = "StencilTopologyByteSpanDescriptor", kind = "byte_compare" },
        { name = "byte_span.count.u8", vocab = "StencilCount", topology = "StencilTopologyByteSpanDescriptor", kind = "byte_count" },
        { name = "view.src_copy.i32.scalar", vocab = "StencilCopy", topology = "StencilTopologyViewDescriptor", kind = "view_src_copy" },
        { name = "view.src_copy.i32.v4", vocab = "StencilCopy", topology = "StencilTopologyViewDescriptor", kind = "view_src_copy_v4" },
        { name = "field.reduce.i32", vocab = "StencilReduce", topology = "StencilTopologyFieldProjection", kind = "field_reduce" },
        { name = "field.map.i32", vocab = "StencilMap", topology = "StencilTopologyFieldProjection", kind = "field_map" },
        { name = "field.find.i32", vocab = "StencilFind", topology = "StencilTopologyFieldProjection", kind = "field_find" },
        { name = "field.compare.i32", vocab = "StencilCompare", topology = "StencilTopologyFieldProjection", kind = "field_compare" },
        { name = "field.fill.i32", vocab = "StencilFill", topology = "StencilTopologyFieldProjection", kind = "field_fill" },
        { name = "soa.zip_map.i32", vocab = "StencilZipMap", topology = "StencilTopologySoAComponent", kind = "soa_zip_map" },
        { name = "soa.zip_reduce.i32", vocab = "StencilZipReduce", topology = "StencilTopologySoAComponent", kind = "soa_zip_reduce" },
        { name = "soa.zip_compare.i32", vocab = "StencilZipCompare", topology = "StencilTopologySoAComponent", kind = "soa_zip_compare" },
        { name = "soa.partition.i32", vocab = "StencilPartition", topology = "StencilTopologySoAComponent", kind = "soa_partition" },
    }

    local function check_cell(cell)
        local vocab = Matrix.vocabs[cell.vocab]
        assert(vocab and vocab.status == Matrix.status.supported, "copy_patch_mc_intern_set: unsupported vocab cell " .. tostring(cell.vocab))
        local topology = Matrix.topologies[cell.topology]
        assert(topology and topology.status == Matrix.status.supported, "copy_patch_mc_intern_set: unsupported topology cell " .. tostring(cell.topology))
    end

    local function base_cell(row, group_name, schedule_variant)
        local group = assert(topology_groups[group_name], group_name)
        local cell = {
            name = group_name .. "." .. row.kind .. ".i32." .. schedule_variant.name,
            vocab = row.vocab,
            topology = group.topology,
            kind = row.kind,
            group = group_name,
            schedule = schedule_variant.schedule and schedule_variant.schedule() or nil,
        }
        check_cell(cell)
        return cell
    end

    function M.cells()
        local out = {}
        for _, group_name in ipairs({ "contiguous", "view", "slice" }) do
            for _, row in ipairs(base_rows) do
                for _, schedule_variant in ipairs(schedule_variants) do
                    out[#out + 1] = base_cell(row, group_name, schedule_variant)
                end
            end
        end
        for _, cell in ipairs(extra_cells) do
            check_cell(cell)
            out[#out + 1] = cell
        end
        return out
    end

    local function with_schedule(cell, info)
        info = info or {}
        if cell.schedule ~= nil then info.schedule = cell.schedule end
        return info
    end

    local function base_top(cell, name)
        local group = assert(topology_groups[cell.group], cell.group)
        return group.top(name)
    end

    local builders = {}

    function builders.reduce(cell)
        return Plan.reduce_array_artifact(reduction(Value.ReductionAdd, 0), nil, with_schedule(cell, { elem_ty = i32, result_ty = i32, step_num = 1, array_topology = base_top(cell, "reduce_xs") }))
    end

    function builders.map(cell)
        return Plan.map_array_artifact(Stencil.StencilUnaryNeg, with_schedule(cell, { elem_ty = i32, result_ty = i32, step_num = 1, dst_topology = base_top(cell, "map_dst"), src_topology = base_top(cell, "map_xs") }))
    end

    function builders.zip_map(cell)
        return Plan.zip_map_array_artifact(Stencil.StencilBinaryAdd, with_schedule(cell, { lhs_ty = i32, rhs_ty = i32, result_ty = i32, step_num = 1, dst_topology = base_top(cell, "zip_map_dst"), lhs_topology = base_top(cell, "zip_map_lhs"), rhs_topology = base_top(cell, "zip_map_rhs") }))
    end

    function builders.scan(cell)
        return Plan.scan_array_artifact(reduction(Value.ReductionAdd, 0), nil, with_schedule(cell, { elem_ty = i32, result_ty = i32, step_num = 1, dst_topology = base_top(cell, "scan_dst"), array_topology = base_top(cell, "scan_xs") }))
    end

    function builders.copy(cell)
        return Plan.copy_array_artifact(with_schedule(cell, { elem_ty = i32, step_num = 1, dst_topology = base_top(cell, "copy_dst"), src_topology = base_top(cell, "copy_src") }))
    end

    function builders.copy_memmove(cell)
        return Plan.copy_array_artifact(with_schedule(cell, { elem_ty = i32, semantics = Stencil.StencilCopyMemMove, step_num = 1, dst_topology = base_top(cell, "copy_move_dst"), src_topology = base_top(cell, "copy_move_src") }))
    end

    function builders.fill(cell)
        return Plan.fill_array_artifact(with_schedule(cell, { elem_ty = i32, value = iconst(7), step_num = 1, dst_topology = base_top(cell, "fill_dst") }))
    end

    function builders.find(cell)
        return Plan.find_array_artifact(pred(Core.CmpEq, i32, iconst(5)), with_schedule(cell, { elem_ty = i32, step_num = 1, array_topology = base_top(cell, "find_xs") }))
    end

    function builders.partition(cell)
        return Plan.partition_array_artifact(pred(Core.CmpGt, i32, iconst(0)), with_schedule(cell, { elem_ty = i32, step_num = 1, dst_topology = base_top(cell, "partition_dst"), array_topology = base_top(cell, "partition_xs") }))
    end

    function builders.cast(cell)
        return Plan.cast_array_artifact(Core.MachineCastSToF, with_schedule(cell, { src_ty = i32, dst_ty = f64, step_num = 1, dst_topology = base_top(cell, "cast_dst"), src_topology = base_top(cell, "cast_xs") }))
    end

    function builders.compare(cell)
        return Plan.compare_array_artifact(pred(Core.CmpGt, i32, iconst(0)), with_schedule(cell, { elem_ty = i32, result_ty = bool8, step_num = 1, dst_topology = base_top(cell, "compare_dst"), src_topology = base_top(cell, "compare_xs") }))
    end

    function builders.zip_compare(cell)
        return Plan.zip_compare_array_artifact(Core.CmpLt, with_schedule(cell, { lhs_ty = i32, rhs_ty = i32, result_ty = bool8, step_num = 1, dst_topology = base_top(cell, "zip_compare_dst"), lhs_topology = base_top(cell, "zip_compare_lhs"), rhs_topology = base_top(cell, "zip_compare_rhs") }))
    end

    function builders.select(cell)
        return Plan.select_array_artifact(Stencil.StencilPredNonZero, with_schedule(cell, { cond_ty = bool8, elem_ty = i32, result_ty = i32, step_num = 1, dst_topology = base_top(cell, "select_dst"), cond_topology = base_top(cell, "select_cond"), then_topology = base_top(cell, "select_then"), else_topology = base_top(cell, "select_else") }))
    end

    function builders.gather(cell)
        return Plan.gather_array_artifact(with_schedule(cell, { elem_ty = i32, index_ty = i32, step_num = 1, dst_topology = base_top(cell, "gather_dst"), index_topology = base_top(cell, "gather_idx") }))
    end

    function builders.scatter(cell)
        return Plan.scatter_array_artifact(with_schedule(cell, { elem_ty = i32, index_ty = i32, conflicts = Stencil.StencilScatterUniqueIndices, step_num = 1, src_topology = base_top(cell, "scatter_src"), index_topology = base_top(cell, "scatter_idx") }))
    end

    function builders.in_place_map(cell)
        return Plan.in_place_map_array_artifact(Stencil.StencilUnaryNeg, with_schedule(cell, { elem_ty = i32, step_num = 1, src_topology = base_top(cell, "in_place_xs") }))
    end

    function builders.count(cell)
        return Plan.count_array_artifact(pred(Core.CmpGt, i32, iconst(0)), with_schedule(cell, { elem_ty = i32, step_num = 1, array_topology = base_top(cell, "count_xs") }))
    end

    function builders.map_reduce(cell)
        return Plan.map_reduce_array_artifact(Stencil.StencilUnaryNeg, reduction(Value.ReductionAdd, 0), nil, with_schedule(cell, { elem_ty = i32, mapped_ty = i32, result_ty = i32, step_num = 1, array_topology = base_top(cell, "map_reduce_xs") }))
    end

    function builders.zip_reduce(cell)
        return Plan.zip_reduce_array_artifact(Stencil.StencilBinaryAdd, reduction(Value.ReductionAdd, 0), nil, with_schedule(cell, { lhs_ty = i32, rhs_ty = i32, mapped_ty = i32, result_ty = i32, step_num = 1, lhs_topology = base_top(cell, "zip_reduce_lhs"), rhs_topology = base_top(cell, "zip_reduce_rhs") }))
    end

    function builders.byte_copy()
        return Plan.copy_array_artifact({ elem_ty = u8, step_num = 1, dst_topology = bytespan_topology("copy_dst"), src_topology = bytespan_topology("copy_src") })
    end

    function builders.byte_copy_memmove()
        return Plan.copy_array_artifact({ elem_ty = u8, semantics = Stencil.StencilCopyMemMove, step_num = 1, dst_topology = bytespan_topology("move_dst"), src_topology = bytespan_topology("move_src") })
    end

    function builders.byte_fill()
        return Plan.fill_array_artifact({ elem_ty = u8, value = u8const(127), step_num = 1, dst_topology = bytespan_topology("fill_dst") })
    end

    function builders.byte_find()
        return Plan.find_array_artifact(pred(Core.CmpEq, u8, u8const(13)), { elem_ty = u8, step_num = 1, array_topology = bytespan_topology("find_xs") })
    end

    function builders.byte_compare()
        return Plan.compare_array_artifact(pred(Core.CmpGt, u8, u8const(9)), { elem_ty = u8, result_ty = bool8, step_num = 1, dst_topology = bytespan_topology("compare_dst"), src_topology = bytespan_topology("compare_xs") })
    end

    function builders.byte_count()
        return Plan.count_array_artifact(pred(Core.CmpGt, u8, u8const(9)), { elem_ty = u8, step_num = 1, array_topology = bytespan_topology("count_xs") })
    end

    function builders.view_src_copy_v4()
        return Plan.copy_array_artifact({
            elem_ty = i32,
            step_num = 1,
            src_topology = view_topology("src"),
            schedule = schedule_variants[2].schedule(),
        })
    end

    function builders.view_src_copy()
        return Plan.copy_array_artifact({
            elem_ty = i32,
            step_num = 1,
            src_topology = view_topology("src"),
        })
    end

    function builders.field_reduce()
        return Plan.reduce_array_artifact(reduction(Value.ReductionAdd, 0), nil, { elem_ty = i32, result_ty = i32, step_num = 1, array_topology = field_topology() })
    end

    function builders.field_map()
        return Plan.map_array_artifact(Stencil.StencilUnaryNeg, { elem_ty = i32, result_ty = i32, step_num = 1, src_topology = field_topology() })
    end

    function builders.field_find()
        return Plan.find_array_artifact(pred(Core.CmpEq, i32, iconst(20)), { elem_ty = i32, step_num = 1, array_topology = field_topology() })
    end

    function builders.field_compare()
        return Plan.compare_array_artifact(pred(Core.CmpGt, i32, iconst(10)), { elem_ty = i32, result_ty = bool8, step_num = 1, src_topology = field_topology() })
    end

    function builders.field_fill()
        return Plan.fill_array_artifact({ elem_ty = i32, value = iconst(99), step_num = 1, dst_topology = field_topology() })
    end

    function builders.soa_zip_map()
        return Plan.zip_map_array_artifact(Stencil.StencilBinaryAdd, { lhs_ty = i32, rhs_ty = i32, result_ty = i32, step_num = 1, dst_topology = soa_component("sum", 2), lhs_topology = soa_component("left", 0), rhs_topology = soa_component("right", 1) })
    end

    function builders.soa_zip_reduce()
        return Plan.zip_reduce_array_artifact(Stencil.StencilBinaryAdd, reduction(Value.ReductionAdd, 0), nil, { lhs_ty = i32, rhs_ty = i32, mapped_ty = i32, result_ty = i32, step_num = 1, lhs_topology = soa_component("left", 0), rhs_topology = soa_component("right", 1) })
    end

    function builders.soa_zip_compare()
        return Plan.zip_compare_array_artifact(Core.CmpLt, { lhs_ty = i32, rhs_ty = i32, result_ty = bool8, step_num = 1, dst_topology = soa_component("lt", 2), lhs_topology = soa_component("left", 0), rhs_topology = soa_component("right", 1) })
    end

    function builders.soa_partition()
        return Plan.partition_array_artifact(pred(Core.CmpGt, i32, iconst(0)), { elem_ty = i32, step_num = 1, dst_topology = soa_component("positive_then_rest", 1), array_topology = soa_component("left", 0) })
    end

    function M.artifact_for_cell(cell)
        local build = assert(builders[cell.kind], "copy_patch_mc_intern_set: no builder for cell kind " .. tostring(cell.kind))
        local artifact = build(cell)
        assert(Plan.descriptor_vocab(artifact.instance.descriptor) == Stencil[cell.vocab], "copy_patch_mc_intern_set: cell " .. cell.name .. " produced wrong vocab")
        return artifact
    end

    function M.artifacts()
        local out = {}
        for _, cell in ipairs(M.cells()) do out[#out + 1] = M.artifact_for_cell(cell) end
        return out
    end

    function M.expected_symbols()
        local out, seen = {}, {}
        for _, artifact in ipairs(M.artifacts()) do
            local symbol = artifact.symbol.text
            if not seen[symbol] then
                out[#out + 1] = symbol
                seen[symbol] = true
            end
        end
        table.sort(out)
        return out
    end

    function M.preamble()
        return "typedef struct { int32_t left; int32_t right; } Demo_Pair;"
    end

    return M
end

return bind_context
