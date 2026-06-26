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
    local f64 = Code.CodeTyFloat(64)
    local bool8 = Code.CodeTyBool8
    local pair_ty = Code.CodeTyNamed("Demo", "Pair", Ty.TNamed(Ty.TypeRefGlobal("Demo", "Pair")))
    local pair_soa_ty = Code.CodeTyNamed("Demo", "PairSoA", Ty.TNamed(Ty.TypeRefGlobal("Demo", "PairSoA")))
    local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)

    local function iconst(raw)
        return Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt(tostring(raw))))
    end

    local function reduction(kind, init)
        return {
            kind = kind,
            init = iconst(init),
            int_semantics = sem,
            float_mode = nil,
        }
    end

    local function view_layout(name)
        return Stencil.StencilLayoutViewDescriptor(
            Code.CodeValueId("v:view:" .. name),
            Code.CodeValueId("v:data:" .. name),
            Code.CodeValueId("v:len:" .. name),
            Code.CodeValueId("v:stride:" .. name),
            nil
        )
    end

    local function slice_layout(name)
        return Stencil.StencilLayoutSliceDescriptor(
            Code.CodeValueId("v:slice:" .. name),
            Code.CodeValueId("v:data:" .. name),
            Code.CodeValueId("v:len:" .. name)
        )
    end

    local function bytespan_layout(name)
        return Stencil.StencilLayoutByteSpanDescriptor(
            Code.CodeValueId("v:bytespan:" .. name),
            Code.CodeValueId("v:data:" .. name),
            Code.CodeValueId("v:len:" .. name)
        )
    end

    local function field_layout(parent)
        return Stencil.StencilLayoutFieldProjection(
            parent or Stencil.StencilLayoutContiguous(1),
            pair_ty,
            "right",
            4
        )
    end

    local function soa_layout(access_name, parent)
        local component = tonumber(tostring(access_name):match("(%d+)$")) or 0
        return Stencil.StencilLayoutSoAComponent(
            parent or Stencil.StencilLayoutContiguous(1),
            pair_soa_ty,
            tostring(access_name),
            component
        )
    end

    local function indexed_layout(access_name, parent)
        return Stencil.StencilLayoutIndexed(
            parent or Stencil.StencilLayoutContiguous(1),
            Stencil.StencilAccessRef("idx_" .. tostring(access_name)),
            i32,
            1
        )
    end

    local layout_groups = {
        contiguous = {
            layout = "StencilLayoutContiguous",
            access_layout = function() return nil end,
        },
        affine = {
            layout = "StencilLayoutAffine1D",
            access_layout = function()
                return Stencil.StencilLayoutAffine1D(Stencil.StencilLayoutContiguous(1), -1, nil)
            end,
        },
        view = {
            layout = "StencilLayoutViewDescriptor",
            access_layout = view_layout,
        },
        slice = {
            layout = "StencilLayoutSliceDescriptor",
            access_layout = slice_layout,
        },
        bytespan = {
            layout = "StencilLayoutByteSpanDescriptor",
            access_layout = bytespan_layout,
        },
        field = {
            layout = "StencilLayoutFieldProjection",
            access_layout = function() return field_layout() end,
        },
        field_view = {
            layout = "StencilLayoutFieldProjection",
            access_layout = function(name) return field_layout(view_layout(name)) end,
        },
        field_slice = {
            layout = "StencilLayoutFieldProjection",
            access_layout = function(name) return field_layout(slice_layout(name)) end,
        },
        soa = {
            layout = "StencilLayoutSoAComponent",
            access_layout = soa_layout,
        },
        soa_view = {
            layout = "StencilLayoutSoAComponent",
            access_layout = function(name) return soa_layout(name, view_layout(name)) end,
        },
        soa_slice = {
            layout = "StencilLayoutSoAComponent",
            access_layout = function(name) return soa_layout(name, slice_layout(name)) end,
        },
        indexed_read = {
            layout = "StencilLayoutIndexed",
            dst_layout = function() return nil end,
            input_layout = indexed_layout,
            extra_inputs = function(input_count)
                local out = {}
                for i = 1, input_count do
                    local name = "idx_x" .. tostring(i)
                    out[#out + 1] = { name = name, ty = i32, layout = nil }
                end
                return out
            end,
        },
        indexed_view_read = {
            layout = "StencilLayoutIndexed",
            dst_layout = function() return nil end,
            input_layout = function(name) return indexed_layout(name, view_layout(name)) end,
            extra_inputs = function(input_count)
                local out = {}
                for i = 1, input_count do
                    local name = "idx_x" .. tostring(i)
                    out[#out + 1] = { name = name, ty = i32, layout = nil }
                end
                return out
            end,
        },
        indexed_slice_read = {
            layout = "StencilLayoutIndexed",
            dst_layout = function() return nil end,
            input_layout = function(name) return indexed_layout(name, slice_layout(name)) end,
            extra_inputs = function(input_count)
                local out = {}
                for i = 1, input_count do
                    local name = "idx_x" .. tostring(i)
                    out[#out + 1] = { name = name, ty = i32, layout = nil }
                end
                return out
            end,
        },
        indexed_bytespan_read = {
            layout = "StencilLayoutIndexed",
            dst_layout = function() return nil end,
            input_layout = function(name) return indexed_layout(name, bytespan_layout(name)) end,
            extra_inputs = function(input_count)
                local out = {}
                for i = 1, input_count do
                    local name = "idx_x" .. tostring(i)
                    out[#out + 1] = { name = name, ty = i32, layout = nil }
                end
                return out
            end,
        },
        indexed_write = {
            layout = "StencilLayoutIndexed",
            scatter_reduce_dst = true,
            supports = function(kind) return kind == "apply_n" or kind == "scan_n" or kind == "scatter_reduce_n" end,
            dst_layout = function() return indexed_layout("dst") end,
            input_layout = function() return nil end,
            extra_inputs = function()
                return { { name = "idx_dst", ty = i32, layout = nil } }
            end,
        },
        indexed_view_write = {
            layout = "StencilLayoutIndexed",
            scatter_reduce_dst = true,
            supports = function(kind) return kind == "apply_n" or kind == "scan_n" or kind == "scatter_reduce_n" end,
            dst_layout = function() return indexed_layout("dst", view_layout("dst")) end,
            input_layout = function() return nil end,
            extra_inputs = function()
                return { { name = "idx_dst", ty = i32, layout = nil } }
            end,
        },
        indexed_slice_write = {
            layout = "StencilLayoutIndexed",
            scatter_reduce_dst = true,
            supports = function(kind) return kind == "apply_n" or kind == "scan_n" or kind == "scatter_reduce_n" end,
            dst_layout = function() return indexed_layout("dst", slice_layout("dst")) end,
            input_layout = function() return nil end,
            extra_inputs = function()
                return { { name = "idx_dst", ty = i32, layout = nil } }
            end,
        },
        indexed_bytespan_write = {
            layout = "StencilLayoutIndexed",
            scatter_reduce_dst = true,
            supports = function(kind) return kind == "apply_n" or kind == "scan_n" or kind == "scatter_reduce_n" end,
            dst_layout = function() return indexed_layout("dst", bytespan_layout("dst")) end,
            input_layout = function() return nil end,
            extra_inputs = function()
                return { { name = "idx_dst", ty = i32, layout = nil } }
            end,
        },
        scalar_input = {
            layout = "StencilLayoutScalar",
            supports = function(kind) return kind ~= "scatter_reduce_n" end,
            dst_layout = function() return nil end,
            input_layout = function() return Stencil.StencilLayoutScalar(nil) end,
        },
    }
    local layout_group_order = {
        "contiguous",
        "affine",
        "view",
        "slice",
        "bytespan",
        "field",
        "field_view",
        "field_slice",
        "soa",
        "soa_view",
        "soa_slice",
        "indexed_read",
        "indexed_view_read",
        "indexed_slice_read",
        "indexed_bytespan_read",
        "indexed_write",
        "indexed_view_write",
        "indexed_slice_write",
        "indexed_bytespan_write",
        "scalar_input",
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

    local function schedule_variants_for_kind(kind)
        if kind == "scatter_reduce_n" then return { schedule_variants[1] } end
        return schedule_variants
    end

    local function layout_group_supports_kind(group, kind, spec)
        if kind == "scatter_reduce_n" then return group.scatter_reduce_dst == true end
        return group.supports == nil or group.supports(kind, spec)
    end

    local function producer_axis(step)
        return Stencil.StencilProducerAxis(Code.CodeTyIndex, nil, nil, step or 1, Stencil.StencilProducerForward)
    end

    local producer_groups = {
        range1d = {
            name = "range1d",
            producer = nil,
        },
        range_nd2 = {
            name = "range_nd2",
            producer = function()
                return Stencil.StencilProducer(nil, Stencil.StencilProduceRangeND({ producer_axis(1), producer_axis(1) }))
            end,
        },
        tiled_nd2 = {
            name = "tiled_nd2",
            producer = function()
                return Stencil.StencilProducer(nil, Stencil.StencilProduceTiledND({ producer_axis(1), producer_axis(1) }, { 2, 2 }))
            end,
        },
        window_nd1 = {
            name = "window_nd1",
            producer = function()
                return Stencil.StencilProducer(nil, Stencil.StencilProduceWindowND({ producer_axis(1) }, {
                    Stencil.StencilWindowAxis(1, 1, Stencil.StencilWindowBoundaryClamp),
                }))
            end,
        },
    }
    local producer_group_order = { "range1d", "range_nd2", "tiled_nd2", "window_nd1" }

    local function producer_group_supports(kind, producer_group_name)
        return true
    end

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
    local default_input_count = 1

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
        local base = cell and (cell.kind == "reduce_n" or cell.kind == "scan_n") and 145 or 125
        local scalar_estimate = base + math.max(0, input_count - 1) * 30 + math.max(0, order - 1) * 45
        return math.ceil(scalar_estimate * 8)
    end

    local function cell_estimated_bytes(cell)
        return tonumber(cell and cell.estimated_bytes) or estimated_bytes_per_cell()
    end

    local function cells_estimated_bytes(cells)
        if type(cells) ~= "table" then return 0 end
        local total = 0
        for _, cell in ipairs(cells or {}) do total = total + cell_estimated_bytes(cell) end
        return total
    end

    local function append_output(out, cell)
        if type(out) == "function" then return out(cell) end
        out[#out + 1] = cell
        return true
    end

    local function check_cell(cell)
        local vocab = Matrix.vocabs[cell.vocab]
        assert(vocab and vocab.status == Matrix.status.supported, "copy_patch_mc_intern_set: unsupported vocab cell " .. tostring(cell.vocab))
        local derived = Matrix.derived_plans[cell.derived or cell.kind]
        assert(derived and derived.status == Matrix.status.supported, "copy_patch_mc_intern_set: unsupported derived plan cell " .. tostring(cell.derived or cell.kind))
        assert(derived.basis == cell.vocab, "copy_patch_mc_intern_set: derived plan " .. tostring(cell.derived or cell.kind) .. " belongs to " .. tostring(derived.basis) .. ", not " .. tostring(cell.vocab))
        local layout = Matrix.layouts[cell.layout]
        assert(layout and layout.status == Matrix.status.supported, "copy_patch_mc_intern_set: unsupported layout cell " .. tostring(cell.layout))
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

    local function exact_shape(opts)
        opts = opts or {}
        local raw = opts.exact_shape or os.getenv("LALIN_MC_BANK_EXACT_SHAPE")
        return raw == true or raw == 1 or raw == "1" or raw == "true" or raw == "yes"
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

    local function soac_vocab(kind)
        if kind == "reduce_n" then return "StencilReduce" end
        if kind == "scan_n" then return "StencilScan" end
        if kind == "scatter_reduce_n" then return "StencilScatterReduce" end
        return "StencilApply"
    end

    local function soac_derived(kind)
        if kind == "scatter_reduce_n" then return "scatter_reduce" end
        return kind
    end

    local function soac_cell(kind, group_name, producer_group_name, schedule_variant, spec, serial)
        local group = assert(layout_groups[group_name], group_name)
        local producer_group = assert(producer_groups[producer_group_name], producer_group_name)
        local cell = {
            name = producer_group.name .. "." .. group_name .. "." .. kind .. ".o" .. tostring(spec.order) .. ".in" .. tostring(spec.input_count) .. ".s" .. tostring(spec.apply_stage_count) .. "." .. tostring(spec.name) .. "." .. schedule_variant.name .. "." .. tostring(serial),
            vocab = soac_vocab(kind),
            layout = group.layout,
            kind = kind,
            derived = soac_derived(kind),
            group = group_name,
            producer_group = producer_group_name,
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
        for _, group_name in ipairs(layout_group_order) do
            local group = assert(layout_groups[group_name], group_name)
            if layout_group_supports_kind(group, kind, spec) then
                for _, producer_group_name in ipairs(producer_group_order) do
                    if producer_group_supports(kind, producer_group_name) then
                        for _, schedule_variant in ipairs(schedule_variants_for_kind(kind)) do
                            local estimated = estimated_bytes_for_soac({ kind = kind, input_count = spec.input_count, order = spec.order })
                            if target ~= nil and estimated_total + estimated > target then
                                return serial, estimated_total, false
                            end
                            serial = serial + 1
                            if append_output(out, soac_cell(kind, group_name, producer_group_name, schedule_variant, spec, serial)) == false then
                                return serial, estimated_total, false
                            end
                            estimated_total = estimated_total + estimated
                        end
                    end
                end
            end
        end
        return serial, estimated_total, true
    end

    local function active_layout_count(kind, spec)
        local count = 0
        local schedules = schedule_variants_for_kind(kind)
        for _, group_name in ipairs(layout_group_order) do
            local group = assert(layout_groups[group_name], group_name)
            if layout_group_supports_kind(group, kind, spec) then
                for _, producer_group_name in ipairs(producer_group_order) do
                    if producer_group_supports(kind, producer_group_name) then count = count + #schedules end
                end
            end
        end
        return count
    end

    local function profile_sink_kind(kind, spec, target_limit, cells, estimated)
        local per_cell = estimated_bytes_for_soac({ kind = kind, input_count = spec.input_count, order = spec.order })
        local total = per_cell * active_layout_count(kind, spec)
        if target_limit ~= nil and estimated + total > target_limit then return cells, estimated, false end
        return cells + active_layout_count(kind, spec), estimated + total, true
    end

    local function append_soac_order_stream(out, input_count, order, serial, target, estimated_total)
        estimated_total = estimated_total or cells_estimated_bytes(out)
        local keep_going = true
        stream_stage_specs(input_count, order - 1, function(spec)
            if same_ty(spec.result_ty, i32) then
                spec.order = order
                serial, estimated_total, keep_going = append_soac_spec(out, "reduce_n", spec, serial, target, estimated_total)
                if keep_going then
                    serial, estimated_total, keep_going = append_soac_spec(out, "scan_n", spec, serial, target, estimated_total)
                end
                if keep_going then
                    serial, estimated_total, keep_going = append_soac_spec(out, "scatter_reduce_n", spec, serial, target, estimated_total)
                end
            end
            return keep_going
        end)
        if keep_going == false then return serial, estimated_total, false end
        stream_stage_specs(input_count, order, function(spec)
            spec.order = order
            serial, estimated_total, keep_going = append_soac_spec(out, "apply_n", spec, serial, target, estimated_total)
            return keep_going
        end)
        return serial, estimated_total, keep_going
    end

    local function append_soac_cells(out, opts)
        opts = opts or {}
        local max_order = requested_soac_order(opts)
        if max_order < 1 then return cells_estimated_bytes(out) end
        local target = target_bytes(opts)
        local target_limit = target and target > 0 and target or nil
        local serial = 0
        local estimated_total = cells_estimated_bytes(out)
        local max_input_count = requested_input_count(opts, max_order)
        if max_input_count < 1 then return estimated_total end
        local min_order = exact_shape(opts) and max_order or 1
        local min_input_count = exact_shape(opts) and max_input_count or 1
        for order = min_order, max_order do
            for input_count = min_input_count, max_input_count do
                local keep_going
                serial, estimated_total, keep_going = append_soac_order_stream(out, input_count, order, serial, target_limit, estimated_total)
                if keep_going == false then return estimated_total end
            end
        end
        return estimated_total
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
    end

    local function append_rank_aware_coverage_cells(out)
        local cells = {
            {
                name = "rank.range_nd2.contiguous.reduce_n.axis2.sum",
                vocab = "StencilReduce",
                layout = "StencilLayoutContiguous",
                kind = "reduce_n",
                derived = "reduce_n",
                group = "contiguous",
                producer_group = "range_nd2",
                input_count = 1,
                order = 1,
                apply_stage_count = 0,
                expr_name = "axis2_sum_x1",
                expr = input("x1"),
                result_ty = i32,
                item_ty = i32,
                scope = Stencil.StencilReduceScopeAxes({ Stencil.StencilAxisRef(2) }, Stencil.StencilAccessRef("dst")),
                estimated_bytes = estimated_bytes_for_soac({ kind = "reduce_n", input_count = 1, order = 1 }),
                serial = "rank_axis_reduce",
            },
            {
                name = "rank.window_nd1.contiguous.reduce_n.window.sum",
                vocab = "StencilReduce",
                layout = "StencilLayoutContiguous",
                kind = "reduce_n",
                derived = "reduce_n",
                group = "contiguous",
                producer_group = "window_nd1",
                input_count = 1,
                order = 1,
                apply_stage_count = 0,
                expr_name = "window_sum_x1",
                expr = input("x1"),
                result_ty = i32,
                item_ty = i32,
                scope = Stencil.StencilReduceScopeWindow({ Stencil.StencilAxisRef(1) }, Stencil.StencilAccessRef("dst")),
                estimated_bytes = estimated_bytes_for_soac({ kind = "reduce_n", input_count = 1, order = 1 }),
                serial = "rank_window_reduce",
            },
            {
                name = "rank.window_nd1.contiguous.apply_n.neighbor_minus1",
                vocab = "StencilApply",
                layout = "StencilLayoutContiguous",
                kind = "apply_n",
                derived = "apply_n",
                group = "contiguous",
                producer_group = "window_nd1",
                input_count = 1,
                order = 1,
                apply_stage_count = 0,
                expr_name = "window_neighbor_minus1",
                expr = Stencil.StencilApplyWindowInput(Stencil.StencilAccessRef("x1"), {
                    Stencil.StencilWindowOffset(Stencil.StencilAxisRef(1), -1),
                }),
                result_ty = i32,
                item_ty = i32,
                estimated_bytes = estimated_bytes_for_soac({ kind = "apply_n", input_count = 1, order = 1 }),
                serial = "rank_window_neighbor",
            },
        }
        for i = 1, #cells do
            check_cell(cells[i])
            if append_output(out, cells[i]) == false then return false end
        end
        return true
    end

    local function shard_filter(opts, emit)
        opts = opts or {}
        local shard_count = tonumber(opts.shard_count or os.getenv("LALIN_MC_BANK_SHARD_COUNT"))
        local shard_index = tonumber(opts.shard_index or os.getenv("LALIN_MC_BANK_SHARD_INDEX"))
        if shard_count == nil and shard_index == nil then return emit end
        assert(shard_count ~= nil and shard_count >= 1, "copy_patch_mc_intern_set: shard_count must be >= 1")
        assert(shard_index ~= nil and shard_index >= 1 and shard_index <= shard_count, "copy_patch_mc_intern_set: shard_index must be in 1..shard_count")
        local ordinal = 0
        return function(cell)
            ordinal = ordinal + 1
            if ((ordinal - 1) % shard_count) + 1 ~= shard_index then return true end
            return emit(cell)
        end
    end

    function M.each_cell(opts, emit)
        opts = opts or {}
        emit = shard_filter(opts, assert(emit, "copy_patch_mc_intern_set.each_cell requires an emit callback"))
        if explicit_rectangular_shape(opts) then
            append_soac_cells(emit, opts)
        else
            append_default_soac_cells(emit, opts)
        end
        append_rank_aware_coverage_cells(emit)
    end

    function M.cells(opts)
        local out = {}
        M.each_cell(opts, function(cell)
            out[#out + 1] = cell
            return true
        end)
        return out
    end

    local function profile_soac_cells(opts, cells, estimated)
        opts = opts or {}
        local max_order = requested_soac_order(opts)
        if max_order < 1 then return cells, estimated end
        local target = target_bytes(opts)
        local target_limit = target and target > 0 and target or nil
        local max_input_count = requested_input_count(opts, max_order)
        if max_input_count < 1 then return cells, estimated end
        local min_order = exact_shape(opts) and max_order or 1
        local min_input_count = exact_shape(opts) and max_input_count or 1
        for order = min_order, max_order do
            for input_count = min_input_count, max_input_count do
                local keep_going = true
                stream_stage_specs(input_count, order - 1, function(spec)
                    if same_ty(spec.result_ty, i32) then
                        spec.order = order
                        cells, estimated, keep_going = profile_sink_kind("reduce_n", spec, target_limit, cells, estimated)
                        if keep_going then cells, estimated, keep_going = profile_sink_kind("scan_n", spec, target_limit, cells, estimated) end
                        if keep_going then cells, estimated, keep_going = profile_sink_kind("scatter_reduce_n", spec, target_limit, cells, estimated) end
                    end
                    return keep_going
                end)
                if keep_going == false then return cells, estimated end
                stream_stage_specs(input_count, order, function(spec)
                    spec.order = order
                    cells, estimated, keep_going = profile_sink_kind("apply_n", spec, target_limit, cells, estimated)
                    return keep_going
                end)
                if keep_going == false then return cells, estimated end
            end
        end
        return cells, estimated
    end

    local function profile_soac_order_stream(input_count, order, target_limit, cells, estimated)
        local keep_going = true
        stream_stage_specs(input_count, order - 1, function(spec)
            if same_ty(spec.result_ty, i32) then
                spec.order = order
                cells, estimated, keep_going = profile_sink_kind("reduce_n", spec, target_limit, cells, estimated)
                if keep_going then cells, estimated, keep_going = profile_sink_kind("scan_n", spec, target_limit, cells, estimated) end
                if keep_going then cells, estimated, keep_going = profile_sink_kind("scatter_reduce_n", spec, target_limit, cells, estimated) end
            end
            return keep_going
        end)
        if keep_going == false then return cells, estimated, false end
        stream_stage_specs(input_count, order, function(spec)
            spec.order = order
            cells, estimated, keep_going = profile_sink_kind("apply_n", spec, target_limit, cells, estimated)
            return keep_going
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
        return cells, estimated
    end

    local function profile_rank_aware_coverage_cells(cells, estimated)
        append_rank_aware_coverage_cells(function(cell)
            cells = cells + 1
            estimated = estimated + cell_estimated_bytes(cell)
            return true
        end)
        return cells, estimated
    end

    function M.bank_profile(opts)
        opts = opts or {}
        local cells = 0
        local estimated = 0
        local explicit = explicit_rectangular_shape(opts)
        if explicit then
            cells, estimated = profile_soac_cells(opts, cells, estimated)
        else
            cells, estimated = profile_default_soac_cells(opts, cells, estimated)
        end
        cells, estimated = profile_rank_aware_coverage_cells(cells, estimated)
        return {
            cells = cells,
            estimated_embedded_bytes = estimated,
            estimated_bytes_per_cell = estimated_bytes_per_cell(),
            soac_order = requested_soac_order(opts),
            input_count = requested_input_count(opts, requested_soac_order(opts)),
            exact_shape = exact_shape(opts),
            target_bytes = target_bytes(opts),
        }
    end

    local function with_schedule(cell, info)
        info = info or {}
        if cell.schedule ~= nil then info.schedule = cell.schedule end
        return info
    end

    local function with_producer(cell, info)
        info = with_schedule(cell, info)
        local producer_group = assert(producer_groups[cell.producer_group or "range1d"], cell.producer_group or "range1d")
        if producer_group.producer ~= nil then info.producer = producer_group.producer() end
        return info
    end

    local function base_layout(cell, name)
        local group = assert(layout_groups[cell.group], cell.group)
        return group.access_layout and group.access_layout(name) or nil
    end

    local function input_layout(cell, name)
        local group = assert(layout_groups[cell.group], cell.group)
        if group.input_layout ~= nil then return group.input_layout(name) end
        return base_layout(cell, name)
    end

    local function dst_layout(cell)
        local group = assert(layout_groups[cell.group], cell.group)
        if group.dst_layout ~= nil then return group.dst_layout() end
        return base_layout(cell, "dst")
    end

    local function extra_inputs(cell, input_count)
        local group = assert(layout_groups[cell.group], cell.group)
        if group.extra_inputs == nil then return {} end
        return group.extra_inputs(input_count) or {}
    end

    local function append_extra_inputs(inputs, cell, input_count)
        local extras = extra_inputs(cell, input_count)
        for i = 1, #extras do inputs[#inputs + 1] = extras[i] end
        return inputs
    end

    local builders = {}

    function builders.apply_n(cell)
        local input_count = assert(cell.input_count, "apply_n cell requires input_count")
        local inputs = {}
        for i = 1, input_count do
            local name = "x" .. tostring(i)
            inputs[i] = { name = name, ty = i32, layout = input_layout(cell, name) }
        end
        append_extra_inputs(inputs, cell, input_count)
        return Plan.apply_n_artifact(with_producer(cell, {
            tag = "bank_o" .. tostring(cell.order) .. "_in" .. tostring(cell.input_count) .. "_" .. tostring(cell.expr_name) .. "_" .. tostring(cell.serial),
            result_ty = cell.result_ty or i32,
            inputs = inputs,
            expr = assert(cell.expr, "apply_n cell requires generated expression"),
            step_num = 1,
            dst_layout = dst_layout(cell),
        }))
    end

    function builders.reduce_n(cell)
        local input_count = assert(cell.input_count, "reduce_n cell requires input_count")
        local inputs = {}
        for i = 1, input_count do
            local name = "x" .. tostring(i)
            inputs[i] = { name = name, ty = i32, layout = input_layout(cell, name) }
        end
        append_extra_inputs(inputs, cell, input_count)
        return Plan.reduce_n_artifact(reduction(Value.ReductionAdd, 0), nil, with_producer(cell, {
            tag = "bank_o" .. tostring(cell.order) .. "_in" .. tostring(cell.input_count) .. "_s" .. tostring(cell.apply_stage_count) .. "_" .. tostring(cell.expr_name) .. "_" .. tostring(cell.serial),
            inputs = inputs,
            expr = assert(cell.expr, "reduce_n cell requires generated expression"),
            item_ty = cell.item_ty or cell.result_ty or i32,
            result_ty = i32,
            step_num = 1,
            scope = cell.scope,
            dst_layout = dst_layout(cell),
        }))
    end

    function builders.scan_n(cell)
        local input_count = assert(cell.input_count, "scan_n cell requires input_count")
        local inputs = {}
        for i = 1, input_count do
            local name = "x" .. tostring(i)
            inputs[i] = { name = name, ty = i32, layout = input_layout(cell, name) }
        end
        append_extra_inputs(inputs, cell, input_count)
        return Plan.scan_n_artifact(reduction(Value.ReductionAdd, 0), nil, with_producer(cell, {
            tag = "bank_o" .. tostring(cell.order) .. "_in" .. tostring(cell.input_count) .. "_s" .. tostring(cell.apply_stage_count) .. "_" .. tostring(cell.expr_name) .. "_" .. tostring(cell.serial),
            inputs = inputs,
            expr = assert(cell.expr, "scan_n cell requires generated expression"),
            item_ty = cell.item_ty or cell.result_ty or i32,
            result_ty = i32,
            step_num = 1,
            dst_layout = dst_layout(cell),
            axis = cell.axis,
        }))
    end

    function builders.scatter_reduce_n(cell)
        local input_count = assert(cell.input_count, "scatter_reduce_n cell requires input_count")
        local inputs = {}
        for i = 1, input_count do
            local name = "x" .. tostring(i)
            inputs[i] = { name = name, ty = i32, layout = input_layout(cell, name) }
        end
        append_extra_inputs(inputs, cell, input_count)
        return Plan.scatter_reduce_n_artifact(reduction(Value.ReductionAdd, 0), nil, with_producer(cell, {
            tag = "bank_o" .. tostring(cell.order) .. "_in" .. tostring(cell.input_count) .. "_s" .. tostring(cell.apply_stage_count) .. "_" .. tostring(cell.expr_name) .. "_" .. tostring(cell.serial),
            inputs = inputs,
            expr = assert(cell.expr, "scatter_reduce_n cell requires generated expression"),
            item_ty = cell.item_ty or cell.result_ty or i32,
            result_ty = cell.result_ty or i32,
            index_ty = cell.index_ty or i32,
            step_num = 1,
            dst_layout = dst_layout(cell),
        }))
    end

    function M.artifact_for_cell(cell)
        local build = assert(builders[cell.kind], "copy_patch_mc_intern_set: no builder for cell kind " .. tostring(cell.kind))
        local artifact = build(cell)
        assert(Plan.descriptor_vocab(artifact.instance.descriptor) == Stencil[cell.vocab], "copy_patch_mc_intern_set: cell " .. cell.name .. " produced wrong basis vocab")
        return artifact
    end

    function M.each_artifact(opts, emit)
        emit = assert(emit, "copy_patch_mc_intern_set.each_artifact requires an emit callback")
        return M.each_cell(opts, function(cell)
            return emit(M.artifact_for_cell(cell), cell)
        end)
    end

    function M.artifact_batches(opts, emit)
        opts = opts or {}
        emit = assert(emit, "copy_patch_mc_intern_set.artifact_batches requires an emit callback")
        local batch_size = tonumber(opts.batch_size or os.getenv("LALIN_MC_BANK_BATCH_SIZE")) or 1024
        if batch_size < 1 then batch_size = 1 end
        batch_size = math.floor(batch_size)
        local batch = {}
        local batch_index = 0
        local keep_going = true
        local function flush()
            if #batch == 0 then return true end
            batch_index = batch_index + 1
            local current = batch
            batch = {}
            return emit(current, batch_index)
        end
        M.each_artifact(opts, function(artifact)
            batch[#batch + 1] = artifact
            if #batch >= batch_size then
                keep_going = flush()
                return keep_going
            end
            return true
        end)
        if keep_going ~= false then flush() end
    end

    function M.artifacts(opts)
        local out = {}
        M.each_artifact(opts, function(artifact)
            out[#out + 1] = artifact
            return true
        end)
        return out
    end

    function M.expected_symbols(opts)
        local out, seen = {}, {}
        M.each_artifact(opts, function(artifact)
            local symbol = artifact.symbol.text
            if not seen[symbol] then
                out[#out + 1] = symbol
                seen[symbol] = true
            end
            return true
        end)
        table.sort(out)
        return out
    end

    function M.c_decls()
        local C = require("llbl.c")
        local LLBL = require("llbl")
        return {
            C.typedef_struct [LLBL.N.Demo_Pair] {
                LLBL.N.left [C.i32],
                LLBL.N.right [C.i32],
            },
        }
    end

    function M.ffi_preamble()
        return "typedef struct { int32_t left; int32_t right; } Demo_Pair;"
    end

    return M
end

return bind_context
