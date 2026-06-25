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
    local topology_group_order = { "contiguous", "view", "slice" }

    local base_rows = {
        { kind = "reduce", vocab = "StencilReduce" },
        { kind = "map", vocab = "StencilApply" },
        { kind = "zip_map", vocab = "StencilApply" },
        { kind = "scan", vocab = "StencilScan" },
        { kind = "copy", vocab = "StencilApply" },
        { kind = "copy_memmove", vocab = "StencilApply" },
        { kind = "fill", vocab = "StencilApply" },
        { kind = "find", vocab = "StencilReduce" },
        { kind = "partition", vocab = "StencilApply" },
        { kind = "cast", vocab = "StencilApply" },
        { kind = "compare", vocab = "StencilApply" },
        { kind = "zip_compare", vocab = "StencilApply" },
        { kind = "select", vocab = "StencilApply" },
        { kind = "gather", vocab = "StencilApply" },
        { kind = "scatter", vocab = "StencilApply" },
        { kind = "in_place_map", vocab = "StencilApply" },
        { kind = "count", vocab = "StencilReduce" },
        { kind = "reduce_n_unary", vocab = "StencilReduce", derived = "reduce_n" },
        { kind = "reduce_n_binary", vocab = "StencilReduce", derived = "reduce_n" },
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
        { name = "byte_span.copy.u8", vocab = "StencilApply", topology = "StencilTopologyByteSpanDescriptor", kind = "byte_copy", derived = "copy" },
        { name = "byte_span.copy_memmove.u8", vocab = "StencilApply", topology = "StencilTopologyByteSpanDescriptor", kind = "byte_copy_memmove", derived = "copy_memmove" },
        { name = "byte_span.fill.u8", vocab = "StencilApply", topology = "StencilTopologyByteSpanDescriptor", kind = "byte_fill", derived = "fill" },
        { name = "byte_span.find.u8", vocab = "StencilReduce", topology = "StencilTopologyByteSpanDescriptor", kind = "byte_find", derived = "find" },
        { name = "byte_span.compare.u8", vocab = "StencilApply", topology = "StencilTopologyByteSpanDescriptor", kind = "byte_compare", derived = "compare" },
        { name = "byte_span.count.u8", vocab = "StencilReduce", topology = "StencilTopologyByteSpanDescriptor", kind = "byte_count", derived = "count" },
        { name = "view.src_copy.i32.scalar", vocab = "StencilApply", topology = "StencilTopologyViewDescriptor", kind = "view_src_copy", derived = "copy" },
        { name = "view.src_copy.i32.v4", vocab = "StencilApply", topology = "StencilTopologyViewDescriptor", kind = "view_src_copy_v4", derived = "copy" },
        { name = "field.reduce.i32", vocab = "StencilReduce", topology = "StencilTopologyFieldProjection", kind = "field_reduce", derived = "reduce" },
        { name = "field.map.i32", vocab = "StencilApply", topology = "StencilTopologyFieldProjection", kind = "field_map", derived = "map" },
        { name = "field.find.i32", vocab = "StencilReduce", topology = "StencilTopologyFieldProjection", kind = "field_find", derived = "find" },
        { name = "field.compare.i32", vocab = "StencilApply", topology = "StencilTopologyFieldProjection", kind = "field_compare", derived = "compare" },
        { name = "field.fill.i32", vocab = "StencilApply", topology = "StencilTopologyFieldProjection", kind = "field_fill", derived = "fill" },
        { name = "soa.zip_map.i32", vocab = "StencilApply", topology = "StencilTopologySoAComponent", kind = "soa_zip_map", derived = "zip_map" },
        { name = "soa.reduce_n.binary.i32", vocab = "StencilReduce", topology = "StencilTopologySoAComponent", kind = "soa_reduce_n_binary", derived = "reduce_n" },
        { name = "soa.zip_compare.i32", vocab = "StencilApply", topology = "StencilTopologySoAComponent", kind = "soa_zip_compare", derived = "zip_compare" },
        { name = "soa.partition.i32", vocab = "StencilApply", topology = "StencilTopologySoAComponent", kind = "soa_partition", derived = "partition" },
    }

    local unary_ops = {
        { name = "identity", op = Stencil.StencilUnaryIdentity },
        { name = "neg", op = Stencil.StencilUnaryNeg },
        { name = "bitnot", op = Stencil.StencilUnaryBitNot },
        { name = "boolnot", op = Stencil.StencilUnaryBoolNot },
    }

    local binary_ops = {
        { name = "add", op = Stencil.StencilBinaryAdd },
        { name = "sub", op = Stencil.StencilBinarySub },
        { name = "mul", op = Stencil.StencilBinaryMul },
        { name = "and", op = Stencil.StencilBinaryAnd },
        { name = "or", op = Stencil.StencilBinaryOr },
        { name = "xor", op = Stencil.StencilBinaryXor },
        { name = "min", op = Stencil.StencilBinaryMin },
        { name = "max", op = Stencil.StencilBinaryMax },
        { name = "shl", op = Stencil.StencilBinaryShl },
        { name = "lshr", op = Stencil.StencilBinaryLShr },
        { name = "ashr", op = Stencil.StencilBinaryAShr },
        { name = "div", op = Stencil.StencilBinaryDiv },
        { name = "mod", op = Stencil.StencilBinaryMod },
    }

    local compare_ops = {
        { name = "eq", op = Core.CmpEq },
        { name = "ne", op = Core.CmpNe },
        { name = "lt", op = Core.CmpLt },
        { name = "le", op = Core.CmpLe },
        { name = "gt", op = Core.CmpGt },
        { name = "ge", op = Core.CmpGe },
    }

    local const_values = {
        { name = "c_m1", value = -1 },
        { name = "c_0", value = 0 },
        { name = "c_1", value = 1 },
    }

    local default_soac_order = 1
    local default_input_count = 4
    local default_second_soac_order = 2
    local default_second_input_count = 4
    local default_second_family = "reduce_after_apply"

    local function target_bytes(opts)
        opts = opts or {}
        local direct = opts.target_bytes or os.getenv("LALIN_MC_BANK_TARGET_BYTES")
        if direct ~= nil then return tonumber(direct) end
        local mb = opts.target_mb or os.getenv("LALIN_MC_BANK_TARGET_MB")
        if mb ~= nil then return math.floor((tonumber(mb) or 0) * 1024 * 1024) end
        return nil
    end

    local function estimated_bytes_per_cell()
        return tonumber(os.getenv("LALIN_MC_BANK_ESTIMATED_BYTES_PER_CELL")) or 90
    end

    local function estimated_bytes_for_soac(cell)
        if os.getenv("LALIN_MC_BANK_ESTIMATED_BYTES_PER_CELL") ~= nil then return estimated_bytes_per_cell() end
        local input_count = tonumber(cell and cell.input_count) or 1
        local order = tonumber(cell and cell.order) or 1
        local base = cell and cell.kind == "reduce_n" and 145 or 125
        return base + math.max(0, input_count - 1) * 30 + math.max(0, order - 1) * 45
    end

    local function cell_estimated_bytes(cell)
        return tonumber(cell and cell.estimated_bytes) or estimated_bytes_per_cell()
    end

    local function cells_estimated_bytes(cells)
        local total = 0
        for _, cell in ipairs(cells or {}) do total = total + cell_estimated_bytes(cell) end
        return total
    end

    local function check_cell(cell)
        local vocab = Matrix.vocabs[cell.vocab]
        assert(vocab and vocab.status == Matrix.status.supported, "copy_patch_mc_intern_set: unsupported vocab cell " .. tostring(cell.vocab))
        local derived = Matrix.derived_plans[cell.derived or cell.kind]
        assert(derived and derived.status == Matrix.status.supported, "copy_patch_mc_intern_set: unsupported derived plan cell " .. tostring(cell.derived or cell.kind))
        assert(derived.basis == cell.vocab, "copy_patch_mc_intern_set: derived plan " .. tostring(cell.derived or cell.kind) .. " belongs to " .. tostring(derived.basis) .. ", not " .. tostring(cell.vocab))
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
            derived = row.derived,
            group = group_name,
            schedule = schedule_variant.schedule and schedule_variant.schedule() or nil,
        }
        check_cell(cell)
        return cell
    end

    local function requested_soac_order(opts)
        opts = opts or {}
        local order = tonumber(opts.soac_order or os.getenv("LALIN_MC_BANK_SOAC_ORDER")) or default_soac_order
        return order
    end

    local function requested_input_count(opts, order)
        opts = opts or {}
        local direct = opts.input_count or os.getenv("LALIN_MC_BANK_INPUT_COUNT")
        if direct ~= nil then return tonumber(direct) or 1 end
        return default_input_count
    end

    local function explicit_rectangular_shape(opts)
        opts = opts or {}
        return opts.soac_order ~= nil
            or opts.input_count ~= nil
            or os.getenv("LALIN_MC_BANK_SOAC_ORDER") ~= nil
            or os.getenv("LALIN_MC_BANK_INPUT_COUNT") ~= nil
    end

    local function input(name)
        return Plan.input_expr(name)
    end

    local function same_ty(a, b)
        if a == b then return true end
        local ac, bc = pvm.classof(a), pvm.classof(b)
        if ac ~= bc then return false end
        if ac == Code.CodeTyInt then return a.bits == b.bits and a.signedness == b.signedness end
        if ac == Code.CodeTyFloat then return a.bits == b.bits end
        return false
    end

    local function supports_binary(op, ty)
        if same_ty(ty, i32) then return true end
        if same_ty(ty, f64) then
            return op == Stencil.StencilBinaryAdd or op == Stencil.StencilBinarySub or op == Stencil.StencilBinaryMul
                or op == Stencil.StencilBinaryDiv or op == Stencil.StencilBinaryMin or op == Stencil.StencilBinaryMax
        end
        if same_ty(ty, bool8) then
            return op == Stencil.StencilBinaryAnd or op == Stencil.StencilBinaryOr or op == Stencil.StencilBinaryXor
        end
        return false
    end

    local function supports_unary(op, ty)
        if op == Stencil.StencilUnaryIdentity then return true end
        if op == Stencil.StencilUnaryBitNot then return same_ty(ty, i32) or same_ty(ty, bool8) end
        if op == Stencil.StencilUnaryNeg then return same_ty(ty, i32) or same_ty(ty, f64) end
        if op == Stencil.StencilUnaryBoolNot then return true end
        return false
    end

    local function unary_cost(op)
        if op == Stencil.StencilUnaryIdentity then return 0 end
        if op == Stencil.StencilUnaryNeg then return 1 end
        if op == Stencil.StencilUnaryBitNot or op == Stencil.StencilUnaryBoolNot then return 2 end
        return 3
    end

    local function binary_cost(op)
        if op == Stencil.StencilBinaryAdd or op == Stencil.StencilBinarySub then return 1 end
        if op == Stencil.StencilBinaryMul or op == Stencil.StencilBinaryMin or op == Stencil.StencilBinaryMax then return 2 end
        if op == Stencil.StencilBinaryAnd or op == Stencil.StencilBinaryOr or op == Stencil.StencilBinaryXor then return 3 end
        if op == Stencil.StencilBinaryShl or op == Stencil.StencilBinaryLShr or op == Stencil.StencilBinaryAShr then return 4 end
        if op == Stencil.StencilBinaryDiv or op == Stencil.StencilBinaryMod then return 5 end
        return 4
    end

    local function type_cost(ty)
        if same_ty(ty, i32) then return 0 end
        if same_ty(ty, bool8) then return 1 end
        return 2
    end

    local function predicates_for(ty)
        local out = { { name = "nonzero", pred = Stencil.StencilPredNonZero } }
        if same_ty(ty, i32) or same_ty(ty, bool8) then
            for _, cmp in ipairs(compare_ops) do
                for _, c in ipairs(const_values) do
                    out[#out + 1] = {
                        name = "pred_" .. cmp.name .. "_" .. c.name,
                        pred = Stencil.StencilPredCompareConst(cmp.op, ty, iconst(c.value)),
                    }
                end
            end
            local ge0 = Stencil.StencilPredCompareConst(Core.CmpGe, ty, iconst(0))
            local le1 = Stencil.StencilPredCompareConst(Core.CmpLe, ty, iconst(1))
            out[#out + 1] = { name = "range_0_1", pred = Stencil.StencilPredRange(ty, Core.CmpGe, iconst(0), Core.CmpLe, iconst(1)) }
            out[#out + 1] = { name = "not_eq_0", pred = Stencil.StencilPredNot(Stencil.StencilPredCompareConst(Core.CmpEq, ty, iconst(0))) }
            out[#out + 1] = { name = "and_ge0_le1", pred = Stencil.StencilPredAnd({ ge0, le1 }) }
            out[#out + 1] = { name = "or_lt0_gt1", pred = Stencil.StencilPredOr({
                Stencil.StencilPredCompareConst(Core.CmpLt, ty, iconst(0)),
                Stencil.StencilPredCompareConst(Core.CmpGt, ty, iconst(1)),
            }) }
        elseif same_ty(ty, f64) then
            out[#out + 1] = { name = "isnan", pred = Stencil.StencilPredIsNaN(f64) }
            out[#out + 1] = { name = "isinf", pred = Stencil.StencilPredIsInf(f64) }
            out[#out + 1] = { name = "isfinite", pred = Stencil.StencilPredIsFinite(f64) }
        end
        return out
    end

    local function casts_for(ty)
        if same_ty(ty, i32) then
            return {
                { name = "cast_identity_i32", op = Core.MachineCastIdentity, from = i32, to = i32 },
                { name = "cast_stof_f64", op = Core.MachineCastSToF, from = i32, to = f64 },
            }
        end
        if same_ty(ty, f64) then
            return {
                { name = "cast_identity_f64", op = Core.MachineCastIdentity, from = f64, to = f64 },
                { name = "cast_ftos_i32", op = Core.MachineCastFToS, from = f64, to = i32 },
            }
        end
        if same_ty(ty, bool8) then
            return {
                { name = "cast_identity_bool8", op = Core.MachineCastIdentity, from = bool8, to = bool8 },
            }
        end
        return {}
    end

    local function soac_cell(kind, group_name, schedule_variant, spec, serial)
        local group = assert(topology_groups[group_name], group_name)
        local cell = {
            name = group_name .. "." .. kind .. ".o" .. tostring(spec.order) .. ".in" .. tostring(spec.input_count) .. ".s" .. tostring(spec.apply_stage_count) .. "." .. tostring(spec.name) .. "." .. schedule_variant.name .. "." .. tostring(serial),
            vocab = kind == "reduce_n" and "StencilReduce" or "StencilApply",
            topology = group.topology,
            kind = kind,
            derived = kind,
            group = group_name,
            schedule = schedule_variant.schedule and schedule_variant.schedule() or nil,
            input_count = spec.input_count,
            order = spec.order,
            apply_stage_count = spec.apply_stage_count,
            expr_name = spec.name,
            expr = spec.expr,
            result_ty = spec.result_ty,
            item_ty = spec.result_ty,
            estimated_bytes = estimated_bytes_for_soac({ kind = kind, input_count = spec.input_count, order = spec.order }),
            serial = serial,
        }
        check_cell(cell)
        return cell
    end

    local function emit_stage_wrappers(base, emit)
        local info = { int_semantics = sem }
        for _, op in ipairs(unary_ops) do
            if supports_unary(op.op, base.result_ty) then
                if emit({
                    name = op.name .. "_" .. base.name,
                    expr = Plan.apply_unary_expr(op.op, base.expr, base.result_ty, info),
                    result_ty = base.result_ty,
                    cost = (base.cost or 1) + unary_cost(op.op),
                }) == false then return false end
            end
        end
        for _, pred in ipairs(predicates_for(base.result_ty)) do
            if emit({
                name = pred.name .. "_" .. base.name,
                expr = Plan.apply_predicate_expr(pred.pred, base.expr, bool8),
                result_ty = bool8,
                cost = (base.cost or 1) + 2,
            }) == false then return false end
        end
        for _, cast in ipairs(casts_for(base.result_ty)) do
            if emit({
                name = cast.name .. "_" .. base.name,
                expr = Plan.apply_cast_expr(cast.op, base.expr, cast.from, cast.to),
                result_ty = cast.to,
                cost = (base.cost or 1) + 2 + type_cost(cast.to),
            }) == false then return false end
        end
        return true
    end

    local function base_terms(input_count)
        local out = {}
        for i = 1, input_count do
            out[#out + 1] = { name = "x" .. tostring(i), expr = input("x" .. tostring(i)), result_ty = i32, cost = 1 }
        end
        for _, c in ipairs(const_values) do
            out[#out + 1] = { name = c.name, expr = Plan.const_expr(iconst(c.value), i32), result_ty = i32, cost = 1 }
        end
        return out
    end

    local function terms_for_primary(primary, bases)
        local out = { primary }
        for _, base in ipairs(bases) do
            if base.name ~= primary.name then out[#out + 1] = base end
        end
        return out
    end

    local function stream_stage_from_primary(input_count, primary, bases, emit)
        local info = { int_semantics = sem }
        local terms = terms_for_primary(primary, bases)
        if emit({ name = primary.name, expr = primary.expr, result_ty = primary.result_ty, input_count = input_count, cost = primary.cost or 1 }) == false then return false end
        if emit_stage_wrappers(primary, function(spec)
            spec.input_count = input_count
            return emit(spec)
        end) == false then return false end
        for _, left in ipairs(terms) do
            for _, right in ipairs(terms) do
                if left == primary or right == primary then
                    for _, op in ipairs(binary_ops) do
                        if same_ty(left.result_ty, right.result_ty) and supports_binary(op.op, left.result_ty) then
                            if emit({
                                name = op.name .. "_" .. left.name .. "_" .. right.name,
                                expr = Plan.apply_binary_expr(op.op, left.expr, right.expr, left.result_ty, info),
                                result_ty = left.result_ty,
                                input_count = input_count,
                                cost = (left.cost or 1) + (right.cost or 1) + binary_cost(op.op),
                            }) == false then return false end
                        end
                    end
                    for _, cmp in ipairs(compare_ops) do
                        if same_ty(left.result_ty, right.result_ty) then
                            if emit({
                                name = "cmp_" .. cmp.name .. "_" .. left.name .. "_" .. right.name,
                                expr = Plan.apply_compare_expr(cmp.op, left.expr, right.expr, bool8),
                                result_ty = bool8,
                                input_count = input_count,
                                cost = (left.cost or 1) + (right.cost or 1) + 2,
                            }) == false then return false end
                        end
                    end
                end
            end
        end
        for _, cond in ipairs(terms) do
            for _, then_spec in ipairs(terms) do
                for _, else_spec in ipairs(terms) do
                    if (cond == primary or then_spec == primary or else_spec == primary) and same_ty(then_spec.result_ty, else_spec.result_ty) then
                        if emit({
                            name = "select_" .. cond.name .. "_" .. then_spec.name .. "_" .. else_spec.name,
                            expr = Plan.apply_select_expr(Stencil.StencilPredNonZero, cond.expr, then_spec.expr, else_spec.expr, then_spec.result_ty),
                            result_ty = then_spec.result_ty,
                            input_count = input_count,
                            cost = (cond.cost or 1) + (then_spec.cost or 1) + (else_spec.cost or 1) + 4,
                        }) == false then return false end
                    end
                end
            end
        end
        return true
    end

    local stream_stage_specs

    stream_stage_specs = function(input_count, apply_stage_count, emit)
        local function emit_one(spec)
            spec.input_count = input_count
            spec.apply_stage_count = apply_stage_count
            return emit(spec)
        end
        if apply_stage_count <= 0 then
            for _, base in ipairs(base_terms(input_count)) do
                if emit_one({
                    name = base.name,
                    expr = base.expr,
                    result_ty = base.result_ty,
                    cost = base.cost or 1,
                }) == false then return false end
            end
            return true
        end
        local bases = base_terms(input_count)
        return stream_stage_specs(input_count, apply_stage_count - 1, function(primary)
            return stream_stage_from_primary(input_count, primary, bases, emit_one)
        end)
    end

    local function append_soac_spec(out, kind, spec, serial, target, estimated_total)
        for _, group_name in ipairs(topology_group_order) do
            for _, schedule_variant in ipairs(schedule_variants) do
                local estimated = estimated_bytes_for_soac({ kind = kind, input_count = spec.input_count, order = spec.order })
                if target ~= nil and estimated_total + estimated > target then
                    return serial, estimated_total, false
                end
                serial = serial + 1
                out[#out + 1] = soac_cell(kind, group_name, schedule_variant, spec, serial)
                estimated_total = estimated_total + estimated
            end
        end
        return serial, estimated_total, true
    end

    local function append_soac_order_stream(out, input_count, order, serial, target, estimated_total)
        estimated_total = estimated_total or cells_estimated_bytes(out)
        local keep_going = true
        stream_stage_specs(input_count, order, function(spec)
            spec.order = order
            serial, estimated_total, keep_going = append_soac_spec(out, "apply_n", spec, serial, target, estimated_total)
            return keep_going
        end)
        if keep_going == false then return serial, estimated_total, false end
        stream_stage_specs(input_count, order - 1, function(spec)
            if same_ty(spec.result_ty, i32) then
                spec.order = order
                serial, estimated_total, keep_going = append_soac_spec(out, "reduce_n", spec, serial, target, estimated_total)
            end
            return keep_going
        end)
        return serial, estimated_total, keep_going
    end

    local function append_reduce_after_apply_stream(out, input_count, serial, target, estimated_total)
        estimated_total = estimated_total or cells_estimated_bytes(out)
        local keep_going = true
        stream_stage_specs(input_count, 1, function(spec)
            if same_ty(spec.result_ty, i32) then
                spec.order = default_second_soac_order
                serial, estimated_total, keep_going = append_soac_spec(out, "reduce_n", spec, serial, target, estimated_total)
            end
            return keep_going
        end)
        return serial, estimated_total, keep_going
    end

    local function append_soac_cells(out, opts)
        opts = opts or {}
        local max_order = requested_soac_order(opts)
        if max_order < 1 then return end
        local target = target_bytes(opts)
        local target_limit = target and target > 0 and target or nil
        local serial = 0
        local estimated_total = cells_estimated_bytes(out)
        local max_input_count = requested_input_count(opts, max_order)
        if max_input_count < 1 then return end
        for order = 1, max_order do
            for input_count = 1, max_input_count do
                local keep_going
                serial, estimated_total, keep_going = append_soac_order_stream(out, input_count, order, serial, target_limit, estimated_total)
                if keep_going == false then return end
            end
        end
    end

    local function append_default_soac_cells(out, opts)
        opts = opts or {}
        local target = target_bytes(opts)
        local target_limit = target and target > 0 and target or nil
        local serial = 0
        local estimated_total = cells_estimated_bytes(out)
        local keep_going
        for input_count = 1, default_input_count do
            serial, estimated_total, keep_going = append_soac_order_stream(out, input_count, default_soac_order, serial, target_limit, estimated_total)
            if keep_going == false then return end
        end
        for input_count = 1, default_second_input_count do
            serial, estimated_total, keep_going = append_reduce_after_apply_stream(out, input_count, serial, target_limit, estimated_total)
            if keep_going == false then return end
        end
    end

    local function shard_cells(cells, opts)
        opts = opts or {}
        local shard_count = tonumber(opts.shard_count or os.getenv("LALIN_MC_BANK_SHARD_COUNT"))
        local shard_index = tonumber(opts.shard_index or os.getenv("LALIN_MC_BANK_SHARD_INDEX"))
        if shard_count == nil and shard_index == nil then return cells end
        assert(shard_count ~= nil and shard_count >= 1, "copy_patch_mc_intern_set: shard_count must be >= 1")
        assert(shard_index ~= nil and shard_index >= 1 and shard_index <= shard_count, "copy_patch_mc_intern_set: shard_index must be in 1..shard_count")
        local out = {}
        for i, cell in ipairs(cells) do
            if ((i - 1) % shard_count) + 1 == shard_index then
                out[#out + 1] = cell
            end
        end
        return out
    end

    function M.cells(opts)
        opts = opts or {}
        local out = {}
        for _, group_name in ipairs(topology_group_order) do
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
        if explicit_rectangular_shape(opts) then
            append_soac_cells(out, opts)
        else
            append_default_soac_cells(out, opts)
        end
        return shard_cells(out, opts)
    end

    local function profile_soac_cells(opts, cells, estimated)
        opts = opts or {}
        local max_order = requested_soac_order(opts)
        if max_order < 1 then return cells, estimated end
        local target = target_bytes(opts)
        local target_limit = target and target > 0 and target or nil
        local max_input_count = requested_input_count(opts, max_order)
        if max_input_count < 1 then return cells, estimated end
        for order = 1, max_order do
            for input_count = 1, max_input_count do
                local keep_going = true
                stream_stage_specs(input_count, order, function(spec)
                    spec.order = order
                    local per_cell = estimated_bytes_for_soac({ kind = "apply_n", input_count = spec.input_count, order = spec.order })
                    local total = per_cell * #topology_group_order * #schedule_variants
                    if target_limit ~= nil and estimated + total > target_limit then keep_going = false; return false end
                    cells = cells + #topology_group_order * #schedule_variants
                    estimated = estimated + total
                    return true
                end)
                if keep_going == false then return cells, estimated end
                stream_stage_specs(input_count, order - 1, function(spec)
                    if same_ty(spec.result_ty, i32) then
                        spec.order = order
                        local per_cell = estimated_bytes_for_soac({ kind = "reduce_n", input_count = spec.input_count, order = spec.order })
                        local total = per_cell * #topology_group_order * #schedule_variants
                        if target_limit ~= nil and estimated + total > target_limit then keep_going = false; return false end
                        cells = cells + #topology_group_order * #schedule_variants
                        estimated = estimated + total
                    end
                    return true
                end)
                if keep_going == false then return cells, estimated end
            end
        end
        return cells, estimated
    end

    local function profile_soac_order_stream(input_count, order, target_limit, cells, estimated)
        local keep_going = true
        stream_stage_specs(input_count, order, function(spec)
            spec.order = order
            local per_cell = estimated_bytes_for_soac({ kind = "apply_n", input_count = spec.input_count, order = spec.order })
            local total = per_cell * #topology_group_order * #schedule_variants
            if target_limit ~= nil and estimated + total > target_limit then keep_going = false; return false end
            cells = cells + #topology_group_order * #schedule_variants
            estimated = estimated + total
            return true
        end)
        if keep_going == false then return cells, estimated, false end
        stream_stage_specs(input_count, order - 1, function(spec)
            if same_ty(spec.result_ty, i32) then
                spec.order = order
                local per_cell = estimated_bytes_for_soac({ kind = "reduce_n", input_count = spec.input_count, order = spec.order })
                local total = per_cell * #topology_group_order * #schedule_variants
                if target_limit ~= nil and estimated + total > target_limit then keep_going = false; return false end
                cells = cells + #topology_group_order * #schedule_variants
                estimated = estimated + total
            end
            return true
        end)
        return cells, estimated, keep_going
    end

    local function profile_reduce_after_apply_stream(input_count, target_limit, cells, estimated)
        local keep_going = true
        stream_stage_specs(input_count, 1, function(spec)
            if same_ty(spec.result_ty, i32) then
                spec.order = default_second_soac_order
                local per_cell = estimated_bytes_for_soac({ kind = "reduce_n", input_count = spec.input_count, order = spec.order })
                local total = per_cell * #topology_group_order * #schedule_variants
                if target_limit ~= nil and estimated + total > target_limit then keep_going = false; return false end
                cells = cells + #topology_group_order * #schedule_variants
                estimated = estimated + total
            end
            return true
        end)
        return cells, estimated, keep_going
    end

    local function profile_default_soac_cells(opts, cells, estimated)
        local target = target_bytes(opts)
        local target_limit = target and target > 0 and target or nil
        local keep_going
        for input_count = 1, default_input_count do
            cells, estimated, keep_going = profile_soac_order_stream(input_count, default_soac_order, target_limit, cells, estimated)
            if keep_going == false then return cells, estimated end
        end
        for input_count = 1, default_second_input_count do
            cells, estimated, keep_going = profile_reduce_after_apply_stream(input_count, target_limit, cells, estimated)
            if keep_going == false then return cells, estimated end
        end
        return cells, estimated
    end

    function M.bank_profile(opts)
        opts = opts or {}
        local cells = #topology_group_order * #base_rows * #schedule_variants + #extra_cells
        local estimated = #topology_group_order * #base_rows * #schedule_variants * estimated_bytes_per_cell()
        for _, cell in ipairs(extra_cells) do estimated = estimated + cell_estimated_bytes(cell) end
        if explicit_rectangular_shape(opts) then
            cells, estimated = profile_soac_cells(opts, cells, estimated)
        else
            cells, estimated = profile_default_soac_cells(opts, cells, estimated)
        end
        return {
            cells = cells,
            estimated_embedded_bytes = estimated,
            estimated_bytes_per_cell = estimated_bytes_per_cell(),
            soac_order = requested_soac_order(opts),
            input_count = requested_input_count(opts, requested_soac_order(opts)),
            second_soac_order = explicit_rectangular_shape(opts) and nil or default_second_soac_order,
            second_input_count = explicit_rectangular_shape(opts) and nil or default_second_input_count,
            second_family = explicit_rectangular_shape(opts) and nil or default_second_family,
            target_bytes = target_bytes(opts),
        }
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

    function builders.reduce_n_unary(cell)
        return Plan.reduce_n_array_artifact(reduction(Value.ReductionAdd, 0), nil, with_schedule(cell, {
            tag = "bank_unary_neg",
            inputs = { { name = "xs", ty = i32, topology = base_top(cell, "reduce_n_xs") } },
            expr = Plan.apply_unary_expr(Stencil.StencilUnaryNeg, Plan.input_expr("xs"), i32, { int_semantics = sem }),
            item_ty = i32,
            result_ty = i32,
            step_num = 1,
        }))
    end

    function builders.reduce_n_binary(cell)
        return Plan.reduce_n_array_artifact(reduction(Value.ReductionAdd, 0), nil, with_schedule(cell, {
            tag = "bank_binary_add",
            inputs = {
                { name = "lhs", ty = i32, topology = base_top(cell, "reduce_n_lhs") },
                { name = "rhs", ty = i32, topology = base_top(cell, "reduce_n_rhs") },
            },
            expr = Plan.apply_binary_expr(Stencil.StencilBinaryAdd, Plan.input_expr("lhs"), Plan.input_expr("rhs"), i32, { int_semantics = sem }),
            item_ty = i32,
            result_ty = i32,
            step_num = 1,
        }))
    end

    function builders.apply_n(cell)
        local input_count = assert(cell.input_count, "apply_n cell requires input_count")
        local inputs = {}
        for i = 1, input_count do
            local name = "x" .. tostring(i)
            inputs[i] = { name = name, ty = i32, topology = base_top(cell, "apply_n_" .. name) }
        end
        return Plan.apply_n_array_artifact(with_schedule(cell, {
            tag = "bank_o" .. tostring(cell.order) .. "_in" .. tostring(cell.input_count) .. "_" .. tostring(cell.expr_name) .. "_" .. tostring(cell.serial),
            result_ty = cell.result_ty or i32,
            inputs = inputs,
            expr = assert(cell.expr, "apply_n cell requires generated expression"),
            step_num = 1,
            dst_topology = base_top(cell, "apply_n_dst"),
        }))
    end

    function builders.reduce_n(cell)
        local input_count = assert(cell.input_count, "reduce_n cell requires input_count")
        local inputs = {}
        for i = 1, input_count do
            local name = "x" .. tostring(i)
            inputs[i] = { name = name, ty = i32, topology = base_top(cell, "reduce_n_" .. name) }
        end
        return Plan.reduce_n_array_artifact(reduction(Value.ReductionAdd, 0), nil, with_schedule(cell, {
            tag = "bank_o" .. tostring(cell.order) .. "_in" .. tostring(cell.input_count) .. "_s" .. tostring(cell.apply_stage_count) .. "_" .. tostring(cell.expr_name) .. "_" .. tostring(cell.serial),
            inputs = inputs,
            expr = assert(cell.expr, "reduce_n cell requires generated expression"),
            item_ty = cell.item_ty or cell.result_ty or i32,
            result_ty = i32,
            step_num = 1,
        }))
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

    function builders.soa_reduce_n_binary()
        return Plan.reduce_n_array_artifact(reduction(Value.ReductionAdd, 0), nil, {
            tag = "soa_binary_add",
            inputs = {
                { name = "lhs", ty = i32, topology = soa_component("left", 0) },
                { name = "rhs", ty = i32, topology = soa_component("right", 1) },
            },
            expr = Plan.apply_binary_expr(Stencil.StencilBinaryAdd, Plan.input_expr("lhs"), Plan.input_expr("rhs"), i32, { int_semantics = sem }),
            item_ty = i32,
            result_ty = i32,
            step_num = 1,
        })
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
        assert(Plan.descriptor_vocab(artifact.instance.descriptor) == Stencil[cell.vocab], "copy_patch_mc_intern_set: cell " .. cell.name .. " produced wrong basis vocab")
        return artifact
    end

    function M.artifacts(opts)
        local out = {}
        for _, cell in ipairs(M.cells(opts)) do out[#out + 1] = M.artifact_for_cell(cell) end
        return out
    end

    function M.expected_symbols(opts)
        local out, seen = {}, {}
        for _, artifact in ipairs(M.artifacts(opts)) do
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
