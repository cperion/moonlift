local asdl = require("lalin.asdl")

local function bind_context(T)
    local Core = T.LalinCore
    local Code = T.LalinCode
    local Ty = T.LalinType
    local Value = T.LalinValue
    local Schedule = T.LalinSchedule
    local Stencil = T.LalinStencil
    local Matrix = require("lalin.stencil_support_matrix")(T)
    local Plan = require("lalin.stencil_artifact_plan")(T)
    local Meta = require("lalin.stencil_metastencil")(T)
    local ReductionAlgebra = require("lalin.reduction_algebra")(T)

    local M = {}

    local i8 = Code.CodeTyInt(8, Code.CodeSigned)
    local u8 = Code.CodeTyInt(8, Code.CodeUnsigned)
    local i16 = Code.CodeTyInt(16, Code.CodeSigned)
    local u16 = Code.CodeTyInt(16, Code.CodeUnsigned)
    local i32 = Code.CodeTyInt(32, Code.CodeSigned)
    local u32 = Code.CodeTyInt(32, Code.CodeUnsigned)
    local i64 = Code.CodeTyInt(64, Code.CodeSigned)
    local u64 = Code.CodeTyInt(64, Code.CodeUnsigned)
    local f32 = Code.CodeTyFloat(32)
    local f64 = Code.CodeTyFloat(64)
    local bool8 = Code.CodeTyBool8
    local pair_ty = Code.CodeTyNamed("Demo", "Pair", Ty.TNamed(Ty.TypeRefGlobal("Demo", "Pair")))
    local pair_soa_ty = Code.CodeTyNamed("Demo", "PairSoA", Ty.TNamed(Ty.TypeRefGlobal("Demo", "PairSoA")))
    local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftTrapOutOfRange)

    local same_ty

    local scalar_type_specs = {
        { name = "i8", ty = i8, family = "int", signed = true },
        { name = "u8", ty = u8, family = "int", signed = false },
        { name = "i16", ty = i16, family = "int", signed = true },
        { name = "u16", ty = u16, family = "int", signed = false },
        { name = "i32", ty = i32, family = "int", signed = true },
        { name = "u32", ty = u32, family = "int", signed = false },
        { name = "i64", ty = i64, family = "int", signed = true },
        { name = "u64", ty = u64, family = "int", signed = false },
        { name = "index", ty = Code.CodeTyIndex, family = "index", signed = false },
        { name = "f32", ty = f32, family = "float", signed = true },
        { name = "f64", ty = f64, family = "float", signed = true },
        { name = "bool8", ty = bool8, family = "bool", signed = false },
    }

    local function type_label(ty)
        for _, spec in ipairs(scalar_type_specs) do
            if spec.ty == ty or same_ty and same_ty(spec.ty, ty) then return spec.name end
        end
        local cls = asdl.classof(ty)
        if cls == Code.CodeTyInt then
            return (ty.signedness == Code.CodeSigned and "i" or "u") .. tostring(ty.bits)
        end
        if cls == Code.CodeTyFloat then return "f" .. tostring(ty.bits) end
        if ty == Code.CodeTyIndex then return "index" end
        if ty == Code.CodeTyBool8 then return "bool8" end
        return "ty"
    end

    local function const_expr(ty, raw)
        local lit
        if ty == Code.CodeTyBool8 then
            local n = tonumber(raw)
            lit = Core.LitBool(raw == true or (n ~= nil and n ~= 0))
        elseif asdl.classof(ty) == Code.CodeTyFloat then
            lit = Core.LitFloat(tostring(raw))
        else
            lit = Core.LitInt(tostring(raw))
        end
        return Value.ValueExprConst(Code.CodeConstLiteral(ty, lit))
    end

    local function iconst(raw)
        return const_expr(i32, raw)
    end

    local function reduction_identity(op, ty)
        local identity, reason = ReductionAlgebra.identity_expr(op, ty)
        assert(identity ~= nil, "residual_mc_intern_set: reduction identity missing: " .. tostring(reason))
        return identity
    end

    local function reduction(op, ty)
        return {
            op = op,
            init = reduction_identity(op, ty),
            int_semantics = sem,
            float_mode = nil,
        }
    end

    local reduction_ops = {
        { name = "add", op = Value.ReductionAdd, numeric = true },
        { name = "mul", op = Value.ReductionMul, numeric = true },
        { name = "min", op = Value.ReductionMin, numeric = true },
        { name = "max", op = Value.ReductionMax, numeric = true },
        { name = "and", op = Value.ReductionAnd, int_only = true },
        { name = "or", op = Value.ReductionOr, int_only = true },
        { name = "xor", op = Value.ReductionXor, int_only = true },
    }

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
            layout_element_ty = i32,
            access_layout = function() return field_layout() end,
        },
        field_view = {
            layout = "StencilLayoutFieldProjection",
            layout_element_ty = i32,
            access_layout = function(name) return field_layout(view_layout(name)) end,
        },
        field_slice = {
            layout = "StencilLayoutFieldProjection",
            layout_element_ty = i32,
            access_layout = function(name) return field_layout(slice_layout(name)) end,
        },
        soa = {
            layout = "StencilLayoutSoAComponent",
            layout_element_ty = i32,
            access_layout = soa_layout,
        },
        soa_view = {
            layout = "StencilLayoutSoAComponent",
            layout_element_ty = i32,
            access_layout = function(name) return soa_layout(name, view_layout(name)) end,
        },
        soa_slice = {
            layout = "StencilLayoutSoAComponent",
            layout_element_ty = i32,
            access_layout = function(name) return soa_layout(name, slice_layout(name)) end,
        },
        indexed_read = {
            layout = "StencilLayoutIndexed",
            requires_point_input = true,
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
            requires_point_input = true,
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
            requires_point_input = true,
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
            requires_point_input = true,
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
            supports = function(kind) return kind == "store_n" or kind == "scan_n" or kind == "scatter_reduce_n" end,
            dst_layout = function() return indexed_layout("dst") end,
            input_layout = function() return nil end,
            extra_inputs = function()
                return { { name = "idx_dst", ty = i32, layout = nil } }
            end,
        },
        indexed_view_write = {
            layout = "StencilLayoutIndexed",
            scatter_reduce_dst = true,
            supports = function(kind) return kind == "store_n" or kind == "scan_n" or kind == "scatter_reduce_n" end,
            dst_layout = function() return indexed_layout("dst", view_layout("dst")) end,
            input_layout = function() return nil end,
            extra_inputs = function()
                return { { name = "idx_dst", ty = i32, layout = nil } }
            end,
        },
        indexed_slice_write = {
            layout = "StencilLayoutIndexed",
            scatter_reduce_dst = true,
            supports = function(kind) return kind == "store_n" or kind == "scan_n" or kind == "scatter_reduce_n" end,
            dst_layout = function() return indexed_layout("dst", slice_layout("dst")) end,
            input_layout = function() return nil end,
            extra_inputs = function()
                return { { name = "idx_dst", ty = i32, layout = nil } }
            end,
        },
        indexed_bytespan_write = {
            layout = "StencilLayoutIndexed",
            scatter_reduce_dst = true,
            supports = function(kind) return kind == "store_n" or kind == "scan_n" or kind == "scatter_reduce_n" end,
            dst_layout = function() return indexed_layout("dst", bytespan_layout("dst")) end,
            input_layout = function() return nil end,
            extra_inputs = function()
                return { { name = "idx_dst", ty = i32, layout = nil } }
            end,
        },
        scalar_input = {
            layout = "StencilLayoutScalar",
            requires_point_input = true,
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

    local function schedule_variants_for_kind(kind, spec)
        if kind == "scatter_reduce_n" then return { schedule_variants[1] } end
        if spec ~= nil and not same_ty(spec.result_ty, i32) then return { schedule_variants[1] } end
        return schedule_variants
    end

    local function layout_group_supports_type(group, spec)
        if group.layout_element_ty == nil then return true end
        return spec ~= nil and same_ty(spec.result_ty, group.layout_element_ty)
    end

    local function layout_group_supports_kind(group, kind, spec)
        if group.requires_point_input == true and tonumber(spec and spec.input_count) == 0 then return false end
        if not layout_group_supports_type(group, spec) then return false end
        if kind == "scatter_reduce_n" then return group.scatter_reduce_dst == true end
        return group.supports == nil or group.supports(kind, spec)
    end

    local function producer_axis(step)
        return Stencil.StencilProducerAxis(Code.CodeTyIndex, nil, nil, step or 1, Stencil.StencilProducerForward)
    end

    local producer_groups = {
        range1d = {
            name = "range1d",
            matrix_key = "StencilProduceRange1D",
            producer = nil,
        },
        range_nd2 = {
            name = "range_nd2",
            matrix_key = "StencilProduceRangeND",
            producer = function()
                return Stencil.StencilProducer(nil, Stencil.StencilProduceRangeND({ producer_axis(1), producer_axis(1) }))
            end,
        },
        tiled_nd2 = {
            name = "tiled_nd2",
            matrix_key = "StencilProduceTiledND",
            producer = function()
                return Stencil.StencilProducer(nil, Stencil.StencilProduceTiledND({ producer_axis(1), producer_axis(1) }, { 2, 2 }))
            end,
        },
        window_nd1 = {
            name = "window_nd1",
            matrix_key = "StencilProduceWindowND",
            producer = function()
                return Stencil.StencilProducer(nil, Stencil.StencilProduceWindowND({ producer_axis(1) }, {
                    Stencil.StencilWindowAxis(1, 1, Stencil.StencilWindowBoundaryClamp),
                }))
            end,
        },
    }
    local producer_group_order = { "range1d", "range_nd2", "tiled_nd2", "window_nd1" }

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
    local default_budget = {
        point_input_max = 3,
        point_stage_max = 1,
        primitive_sink_input_count = 1,
        primitive_sink_stage_count = 0,
        max_metastencil_nodes = 2,
    }

    local function estimated_bytes_for_cell(cell)
        local input_count = tonumber(cell and cell.input_count) or 1
        local order = tonumber(cell and cell.order) or 1
        local base = cell and (cell.kind == "reduce_n" or cell.kind == "scan_n") and 145 or 125
        local scalar_estimate = base + math.max(0, input_count - 1) * 30 + math.max(0, order - 1) * 45
        return math.ceil(scalar_estimate * 8)
    end

    local function cell_estimated_bytes(cell)
        return tonumber(cell and cell.estimated_bytes) or estimated_bytes_for_cell(cell)
    end

    local function cells_estimated_bytes(cells)
        if type(cells) ~= "table" then return 0 end
        local total = 0
        for _, cell in ipairs(cells or {}) do total = total + cell_estimated_bytes(cell) end
        return total
    end

    local function copy_budget(overrides)
        local budget = {}
        for k, v in pairs(default_budget) do budget[k] = v end
        for k, v in pairs(overrides or {}) do budget[k] = v end
        local env_total = tonumber(os.getenv("LALIN_MC_BANK_MAX_CELLS") or "")
        if env_total ~= nil then budget.max_cells = env_total end
        return budget
    end

    local function saturation_budget(opts)
        opts = opts or {}
        return copy_budget(opts.budget)
    end

    local function budget_allows(counter, budget, kind)
        if budget.max_cells ~= nil and counter.total >= budget.max_cells then return false end
        return true
    end

    local function budget_count(counter, kind)
        counter.total = counter.total + 1
        if kind == "primitive" then counter.primitive = counter.primitive + 1 end
        if kind == "composed" then counter.composed = counter.composed + 1 end
    end

    local function append_output(out, cell)
        if type(out) == "function" then return out(cell) end
        out[#out + 1] = cell
        return true
    end

    local function check_cell(cell)
        local vocab = Matrix.sink_vocabs[cell.vocab]
        assert(vocab and vocab.status == Matrix.status.supported, "residual_mc_intern_set: unsupported vocab cell " .. tostring(cell.vocab))
        local layout = Matrix.layouts[cell.layout]
        assert(layout and layout.status == Matrix.status.supported, "residual_mc_intern_set: unsupported layout cell " .. tostring(cell.layout))
        local producer_group = producer_groups[cell.producer_group]
        local producer = Matrix.producers[producer_group and producer_group.matrix_key]
        assert(producer and producer.status == Matrix.status.supported, "residual_mc_intern_set: unsupported producer cell " .. tostring(cell.producer_group))
        if cell.kind == "reduce_n" or cell.kind == "scan_n" or cell.kind == "scatter_reduce_n" then
            assert(cell.reduction ~= nil and cell.reduction.op ~= nil, "residual_mc_intern_set: sink cell requires reduction")
        end
    end

    local function input(name)
        return Plan.input_expr(name)
    end

    function same_ty(a, b)
        if a == b then return true end
        local ac, bc = asdl.classof(a), asdl.classof(b)
        if ac ~= bc then return false end
        if ac == Code.CodeTyInt then return a.bits == b.bits and a.signedness == b.signedness end
        if ac == Code.CodeTyFloat then return a.bits == b.bits end
        return false
    end

    local function is_int_ty(ty)
        return asdl.classof(ty) == Code.CodeTyInt or ty == Code.CodeTyIndex
    end

    local function is_signed_int_ty(ty)
        return asdl.classof(ty) == Code.CodeTyInt and ty.signedness == Code.CodeSigned
    end

    local function is_bool_ty(ty)
        return ty == Code.CodeTyBool8
    end

    local function is_integer_storage_ty(ty)
        return is_int_ty(ty) or is_bool_ty(ty)
    end

    local function integer_storage_bits(ty)
        if ty == Code.CodeTyIndex then return 64 end
        if ty == Code.CodeTyBool8 then return 8 end
        return tonumber(ty.bits)
    end

    local function is_float_ty(ty)
        return asdl.classof(ty) == Code.CodeTyFloat
    end

    local function is_numeric_ty(ty)
        return is_int_ty(ty) or is_float_ty(ty)
    end

    local function is_bitwise_ty(ty)
        return is_int_ty(ty) or is_bool_ty(ty)
    end

    local function is_shift_ty(ty)
        return is_int_ty(ty)
    end

    local function supports_binary(op, ty)
        if op == Stencil.StencilBinaryAdd or op == Stencil.StencilBinarySub or op == Stencil.StencilBinaryMul
            or op == Stencil.StencilBinaryDiv or op == Stencil.StencilBinaryMin or op == Stencil.StencilBinaryMax then
            return is_numeric_ty(ty)
        end
        if op == Stencil.StencilBinaryMod then return is_int_ty(ty) end
        if op == Stencil.StencilBinaryAnd or op == Stencil.StencilBinaryOr or op == Stencil.StencilBinaryXor then
            return is_bitwise_ty(ty)
        end
        if op == Stencil.StencilBinaryShl or op == Stencil.StencilBinaryLShr or op == Stencil.StencilBinaryAShr then
            return is_shift_ty(ty)
        end
        return false
    end

    local function supports_unary(op, ty)
        if op == Stencil.StencilUnaryIdentity then return true end
        if op == Stencil.StencilUnaryBitNot then return is_bitwise_ty(ty) end
        if op == Stencil.StencilUnaryNeg then return is_numeric_ty(ty) end
        if op == Stencil.StencilUnaryBoolNot then return is_numeric_ty(ty) or is_bool_ty(ty) end
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

    local function const_values_for(ty)
        if is_bool_ty(ty) then
            return {
                { name = "c_false", value = false },
                { name = "c_true", value = true },
            }
        end
        if is_float_ty(ty) or is_signed_int_ty(ty) then
            return const_values
        end
        return {
            { name = "c_0", value = 0 },
            { name = "c_1", value = 1 },
        }
    end

    local function predicates_for(ty)
        local out = { { name = "nonzero", pred = Stencil.StencilPredNonZero } }
        if is_numeric_ty(ty) or is_bool_ty(ty) then
            for _, cmp in ipairs(compare_ops) do
                for _, c in ipairs(const_values_for(ty)) do
                    out[#out + 1] = {
                        name = "pred_" .. cmp.name .. "_" .. c.name,
                        pred = Stencil.StencilPredCompareConst(cmp.op, ty, const_expr(ty, c.value)),
                    }
                end
            end
            if is_numeric_ty(ty) then
                local zero = const_expr(ty, 0)
                local one = const_expr(ty, 1)
                local ge0 = Stencil.StencilPredCompareConst(Core.CmpGe, ty, zero)
                local le1 = Stencil.StencilPredCompareConst(Core.CmpLe, ty, one)
                out[#out + 1] = { name = "range_0_1", pred = Stencil.StencilPredRange(ty, Core.CmpGe, zero, Core.CmpLe, one) }
                out[#out + 1] = { name = "not_eq_0", pred = Stencil.StencilPredNot(Stencil.StencilPredCompareConst(Core.CmpEq, ty, zero)) }
                out[#out + 1] = { name = "and_ge0_le1", pred = Stencil.StencilPredAnd({ ge0, le1 }) }
                out[#out + 1] = { name = "or_lt0_gt1", pred = Stencil.StencilPredOr({
                    Stencil.StencilPredCompareConst(Core.CmpLt, ty, zero),
                    Stencil.StencilPredCompareConst(Core.CmpGt, ty, one),
                }) }
            end
        end
        if is_float_ty(ty) then
            out[#out + 1] = { name = "isnan", pred = Stencil.StencilPredIsNaN(ty) }
            out[#out + 1] = { name = "isinf", pred = Stencil.StencilPredIsInf(ty) }
            out[#out + 1] = { name = "isfinite", pred = Stencil.StencilPredIsFinite(ty) }
        end
        return out
    end

    local function cast_between_ints(from, to)
        if same_ty(from, to) then return Core.MachineCastIdentity end
        local from_bits = integer_storage_bits(from)
        local to_bits = integer_storage_bits(to)
        if to_bits <= from_bits then return Core.MachineCastIreduce end
        return is_signed_int_ty(from) and Core.MachineCastSextend or Core.MachineCastUextend
    end

    local function scalar_cast_op(from, to)
        if same_ty(from, to) then return Core.MachineCastIdentity end
        if is_integer_storage_ty(from) and is_integer_storage_ty(to) then return cast_between_ints(from, to) end
        if is_integer_storage_ty(from) and is_float_ty(to) then return is_signed_int_ty(from) and Core.MachineCastSToF or Core.MachineCastUToF end
        if is_float_ty(from) and is_integer_storage_ty(to) then return is_signed_int_ty(to) and Core.MachineCastFToS or Core.MachineCastFToU end
        if is_float_ty(from) and is_float_ty(to) then
            return (from.bits or 0) < (to.bits or 0) and Core.MachineCastFpromote or Core.MachineCastFdemote
        end
        return nil
    end

    local function append_cast(out, name, op, from, to)
        out[#out + 1] = { name = name, op = op, from = from, to = to }
    end

    local function casts_for(ty)
        local out = {}
        for _, to_spec in ipairs(scalar_type_specs) do
            local op = scalar_cast_op(ty, to_spec.ty)
            if op ~= nil then
                append_cast(out, "cast_" .. type_label(ty) .. "_" .. to_spec.name, op, ty, to_spec.ty)
            end
        end
        return out
    end

    local function reduction_variants_for(kind, spec)
        if kind ~= "reduce_n" and kind ~= "scan_n" and kind ~= "scatter_reduce_n" then
            return { false }
        end
        local out = {}
        for _, red in ipairs(reduction_ops) do
            if red.int_only then
                if is_bitwise_ty(spec.result_ty) then out[#out + 1] = red end
            elseif red.numeric then
                if is_numeric_ty(spec.result_ty) then out[#out + 1] = red end
            else
                out[#out + 1] = red
            end
        end
        return out
    end

    local function sink_vocab(kind)
        if kind == "reduce_n" then return "StencilReduce" end
        if kind == "scan_n" then return "StencilScan" end
        if kind == "scatter_reduce_n" then return "StencilScatterReduce" end
        return "StencilStore"
    end

    local function stencil_cell(kind, group_name, producer_group_name, schedule_variant, spec, serial, red)
        local group = assert(layout_groups[group_name], group_name)
        local producer_group = assert(producer_groups[producer_group_name], producer_group_name)
        local reduction_suffix = red and (".red_" .. tostring(red.name)) or ""
        local type_suffix = ".ty_" .. type_label(spec.input_ty or spec.result_ty) .. "_to_" .. type_label(spec.result_ty)
        local cell = {
            name = producer_group.name .. "." .. group_name .. "." .. kind .. reduction_suffix .. type_suffix .. ".o" .. tostring(spec.order) .. ".in" .. tostring(spec.input_count) .. ".s" .. tostring(spec.point_stage_count) .. "." .. tostring(spec.name) .. "." .. schedule_variant.name .. "." .. tostring(serial),
            vocab = sink_vocab(kind),
            layout = group.layout,
            kind = kind,
            group = group_name,
            producer_group = producer_group_name,
            schedule = schedule_variant.schedule and schedule_variant.schedule() or nil,
            input_count = spec.input_count,
            order = spec.order,
            point_stage_count = spec.point_stage_count,
            expr_name = spec.name,
            expr = spec.expr,
            input_ty = spec.input_ty or spec.result_ty,
            result_ty = spec.result_ty,
            item_ty = spec.result_ty,
            estimated_bytes = estimated_bytes_for_cell({ kind = kind, input_count = spec.input_count, order = spec.order }),
            serial = serial,
        }
        if red ~= nil then
            cell.reduction = {
                name = red.name,
                op = red.op,
                init = reduction_identity(red.op, spec.result_ty),
            }
        end
        check_cell(cell)
        return cell
    end

    local function empty_refs()
        return {}
    end

    local function one_ref(name)
        return { [name] = true }
    end

    local function merge_refs(...)
        local out = {}
        for i = 1, select("#", ...) do
            local refs = select(i, ...)
            for name in pairs(refs or {}) do out[name] = true end
        end
        return out
    end

    local function ref_count(refs)
        local n = 0
        for name in pairs(refs or {}) do
            if tostring(name):match("^x%d+$") then n = n + 1 end
        end
        return n
    end

    local function point_spec(attrs)
        attrs.refs = attrs.refs or empty_refs()
        attrs.cost = attrs.cost or 1
        return attrs
    end

    local function point_atoms(max_input_count, ty)
        local out = {}
        for i = 1, max_input_count do
            local name = "x" .. tostring(i)
            out[#out + 1] = point_spec({
                name = name,
                expr = input(name),
                input_ty = ty,
                result_ty = ty,
                refs = one_ref(name),
            })
        end
        for _, c in ipairs(const_values_for(ty)) do
            out[#out + 1] = point_spec({
                name = c.name,
                expr = Plan.const_expr(const_expr(ty, c.value), ty),
                input_ty = ty,
                result_ty = ty,
                refs = empty_refs(),
            })
        end
        return out
    end

    local function spec_key(spec)
        return table.concat({
            spec.name,
            type_label(spec.input_ty or spec.result_ty),
            type_label(spec.result_ty),
        }, ":")
    end

    local function append_spec(out, seen, spec)
        local key = spec_key(spec)
        if seen[key] then return false end
        seen[key] = true
        out[#out + 1] = spec
        return true
    end

    local function emit_spec_once(seen, spec, emit)
        local key = spec_key(spec)
        if seen[key] then return true end
        seen[key] = true
        return emit(spec)
    end

    local function append_stage_wrappers(out, seen, base)
        local info = { int_semantics = sem }
        for _, op in ipairs(unary_ops) do
            if supports_unary(op.op, base.result_ty) then
                append_spec(out, seen, point_spec({
                    name = op.name .. "_" .. base.name,
                    expr = Plan.point_unary_expr(op.op, base.expr, base.result_ty, info),
                    input_ty = base.input_ty or base.result_ty,
                    result_ty = base.result_ty,
                    refs = base.refs,
                    cost = (base.cost or 1) + unary_cost(op.op),
                }))
            end
        end
        for _, pred in ipairs(predicates_for(base.result_ty)) do
            append_spec(out, seen, point_spec({
                name = pred.name .. "_" .. base.name,
                expr = Plan.point_predicate_expr(pred.pred, base.expr, bool8),
                input_ty = base.input_ty or base.result_ty,
                result_ty = bool8,
                refs = base.refs,
                cost = (base.cost or 1) + 2,
            }))
        end
        for _, cast in ipairs(casts_for(base.result_ty)) do
            append_spec(out, seen, point_spec({
                name = cast.name .. "_" .. base.name,
                expr = Plan.point_cast_expr(cast.op, base.expr, cast.from, cast.to),
                input_ty = base.input_ty or base.result_ty,
                result_ty = cast.to,
                refs = base.refs,
                cost = (base.cost or 1) + 2 + type_cost(cast.to),
            }))
        end
    end

    local function stream_stage_terms(previous_stage, atoms, emit)
        local seen = {}
        local info = { int_semantics = sem }
        local terms = {}
        for i = 1, #previous_stage do terms[#terms + 1] = previous_stage[i] end
        for i = 1, #atoms do terms[#terms + 1] = atoms[i] end
        for _, primary in ipairs(previous_stage) do
            local wrappers = {}
            append_stage_wrappers(wrappers, {}, primary)
            for _, spec in ipairs(wrappers) do
                if emit_spec_once(seen, spec, emit) == false then return false end
            end
            for _, other in ipairs(terms) do
                for _, pair in ipairs({
                    { primary, other },
                    { other, primary },
                }) do
                    local left, right = pair[1], pair[2]
                    for _, op in ipairs(binary_ops) do
                        if same_ty(left.result_ty, right.result_ty) and supports_binary(op.op, left.result_ty) then
                            if emit_spec_once(seen, point_spec({
                                name = op.name .. "_" .. left.name .. "_" .. right.name,
                                expr = Plan.point_binary_expr(op.op, left.expr, right.expr, left.result_ty, info),
                                input_ty = left.input_ty or left.result_ty,
                                result_ty = left.result_ty,
                                refs = merge_refs(left.refs, right.refs),
                                cost = (left.cost or 1) + (right.cost or 1) + binary_cost(op.op),
                            }), emit) == false then return false end
                        end
                    end
                    for _, cmp in ipairs(compare_ops) do
                        if same_ty(left.result_ty, right.result_ty) then
                            if emit_spec_once(seen, point_spec({
                                name = "cmp_" .. cmp.name .. "_" .. left.name .. "_" .. right.name,
                                expr = Plan.point_compare_expr(cmp.op, left.expr, right.expr, bool8),
                                input_ty = left.input_ty or left.result_ty,
                                result_ty = bool8,
                                refs = merge_refs(left.refs, right.refs),
                                cost = (left.cost or 1) + (right.cost or 1) + 2,
                            }), emit) == false then return false end
                        end
                    end
                end
            end
            for _, then_spec in ipairs(terms) do
                for _, else_spec in ipairs(terms) do
                    if same_ty(then_spec.result_ty, else_spec.result_ty) then
                        if emit_spec_once(seen, point_spec({
                            name = "select_" .. primary.name .. "_" .. then_spec.name .. "_" .. else_spec.name,
                            expr = Plan.point_select_expr(Stencil.StencilPredNonZero, primary.expr, then_spec.expr, else_spec.expr, then_spec.result_ty),
                            input_ty = then_spec.input_ty or then_spec.result_ty,
                            result_ty = then_spec.result_ty,
                            refs = merge_refs(primary.refs, then_spec.refs, else_spec.refs),
                            cost = (primary.cost or 1) + (then_spec.cost or 1) + (else_spec.cost or 1) + 4,
                        }), emit) == false then return false end
                    end
                end
            end
        end
        return true
    end

    local function stream_point_specs(point_input_count, point_stage_count, ty, emit)
        local atoms = point_atoms(point_input_count, ty)
        if point_stage_count == 0 then
            for _, spec in ipairs(atoms) do
                if ref_count(spec.refs) == point_input_count then
                    spec.input_count = point_input_count
                    spec.point_stage_count = point_stage_count
                    if emit(spec) == false then return false end
                end
            end
            return true
        end
        local previous_stage = atoms
        for stage = 1, point_stage_count do
            if stage == point_stage_count then
                return stream_stage_terms(previous_stage, atoms, function(spec)
                    if ref_count(spec.refs) ~= point_input_count then return true end
                    spec.input_count = point_input_count
                    spec.point_stage_count = point_stage_count
                    return emit(spec)
                end)
            end
            local next_stage = {}
            local keep_going = stream_stage_terms(previous_stage, atoms, function(spec)
                next_stage[#next_stage + 1] = spec
                return true
            end)
            if keep_going == false then return false end
            previous_stage = next_stage
        end
        return true
    end

    local function stream_point_spec_space(input_max, stage_max, filter, emit)
        local input_order = {}
        local seen_input_count = {}
        local function append_input_count(n)
            if n >= 0 and n <= input_max and seen_input_count[n] == nil then
                input_order[#input_order + 1] = n
                seen_input_count[n] = true
            end
        end
        append_input_count(1)
        append_input_count(2)
        append_input_count(0)
        append_input_count(4)
        append_input_count(3)
        for input_count = 5, input_max do append_input_count(input_count) end
        for stage_count = 0, stage_max do
            for _, input_count in ipairs(input_order) do
                for _, ty_spec in ipairs(scalar_type_specs) do
                    local keep_going = stream_point_specs(input_count, stage_count, ty_spec.ty, function(spec)
                        if filter == nil or filter(spec) then return emit(spec) end
                        return true
                    end)
                    if keep_going == false then return false end
                end
            end
        end
        return true
    end

    local function append_stencil_cell(out, kind, spec, serial, estimated_total, counter, budget, budget_kind)
        for _, group_name in ipairs(layout_group_order) do
            local group = assert(layout_groups[group_name], group_name)
            if layout_group_supports_kind(group, kind, spec) then
                for _, producer_group_name in ipairs(producer_group_order) do
                    for _, schedule_variant in ipairs(schedule_variants_for_kind(kind, spec)) do
                        for _, red in ipairs(reduction_variants_for(kind, spec)) do
                            local estimated = estimated_bytes_for_cell({ kind = kind, input_count = spec.input_count, order = spec.order })
                            serial = serial + 1
                            if counter ~= nil and not budget_allows(counter, budget or {}, budget_kind or "primitive") then
                                return serial, estimated_total, false
                            end
                            local cell = stencil_cell(kind, group_name, producer_group_name, schedule_variant, spec, serial, red ~= false and red or nil)
                            if budget_kind == "composed" then
                                cell.composition = "store_to_sink"
                                cell.metastencil_nodes = 2
                            end
                            if counter ~= nil then budget_count(counter, budget_kind or "primitive") end
                            if append_output(out, cell) == false then
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

    local function append_saturated_cells(out, budget)
        local counter = { total = 0, primitive = 0, composed = 0 }
        local serial = 0
        local estimated_total = cells_estimated_bytes(out)
        local keep_going = true
        stream_point_spec_space(budget.point_input_max, budget.point_stage_max, nil, function(spec)
            spec.order = 1
            if spec.input_count == budget.primitive_sink_input_count
                and spec.point_stage_count == budget.primitive_sink_stage_count then
                serial, estimated_total, keep_going = append_stencil_cell(out, "reduce_n", spec, serial, estimated_total, counter, budget, "primitive")
                if keep_going then
                    serial, estimated_total, keep_going = append_stencil_cell(out, "scan_n", spec, serial, estimated_total, counter, budget, "primitive")
                end
                if keep_going then
                    serial, estimated_total, keep_going = append_stencil_cell(out, "scatter_reduce_n", spec, serial, estimated_total, counter, budget, "primitive")
                end
                if not keep_going then return false end
            end
            serial, estimated_total, keep_going = append_stencil_cell(out, "store_n", spec, serial, estimated_total, counter, budget, "primitive")
            if keep_going then
                local can_compose = tonumber(budget.max_metastencil_nodes or 0) >= 2
                    and spec.input_count >= 1
                    and (spec.input_count ~= budget.primitive_sink_input_count
                        or spec.point_stage_count ~= budget.primitive_sink_stage_count)
                if can_compose then
                    serial, estimated_total, keep_going = append_stencil_cell(out, "reduce_n", spec, serial, estimated_total, counter, budget, "composed")
                    if keep_going then
                        serial, estimated_total, keep_going = append_stencil_cell(out, "scan_n", spec, serial, estimated_total, counter, budget, "composed")
                    end
                    if keep_going then
                        serial, estimated_total, keep_going = append_stencil_cell(out, "scatter_reduce_n", spec, serial, estimated_total, counter, budget, "composed")
                    end
                end
            end
            return keep_going
        end)
        return counter, keep_going
    end

    local function append_rank_scope_window_probe_cells(out)
        local cells = {
            {
                name = "rank.range_nd2.contiguous.reduce_n.axis2.sum",
                vocab = "StencilReduce",
                layout = "StencilLayoutContiguous",
                kind = "reduce_n",
                group = "contiguous",
                producer_group = "range_nd2",
                input_count = 1,
                order = 1,
                point_stage_count = 0,
                expr_name = "axis2_sum_x1",
                expr = input("x1"),
                result_ty = i32,
                item_ty = i32,
                reduction = { name = "add", op = Value.ReductionAdd, init = 0 },
                scope = Stencil.StencilReduceScopeAxes({ Stencil.StencilAxisRef(2) }, Stencil.StencilAccessRef("dst")),
                estimated_bytes = estimated_bytes_for_cell({ kind = "reduce_n", input_count = 1, order = 1 }),
                serial = "rank_axis_reduce",
            },
            {
                name = "rank.window_nd1.contiguous.reduce_n.window.sum",
                vocab = "StencilReduce",
                layout = "StencilLayoutContiguous",
                kind = "reduce_n",
                group = "contiguous",
                producer_group = "window_nd1",
                input_count = 1,
                order = 1,
                point_stage_count = 0,
                expr_name = "window_sum_x1",
                expr = input("x1"),
                result_ty = i32,
                item_ty = i32,
                reduction = { name = "add", op = Value.ReductionAdd, init = 0 },
                scope = Stencil.StencilReduceScopeWindow({ Stencil.StencilAxisRef(1) }, Stencil.StencilAccessRef("dst")),
                estimated_bytes = estimated_bytes_for_cell({ kind = "reduce_n", input_count = 1, order = 1 }),
                serial = "rank_window_reduce",
            },
            {
                name = "rank.window_nd1.contiguous.store_n.neighbor_minus1",
                vocab = "StencilStore",
                layout = "StencilLayoutContiguous",
                kind = "store_n",
                group = "contiguous",
                producer_group = "window_nd1",
                input_count = 1,
                order = 1,
                point_stage_count = 0,
                expr_name = "window_neighbor_minus1",
                expr = Stencil.StencilPointWindowInput(Stencil.StencilAccessRef("x1"), {
                    Stencil.StencilWindowOffset(Stencil.StencilAxisRef(1), -1),
                }),
                result_ty = i32,
                item_ty = i32,
                estimated_bytes = estimated_bytes_for_cell({ kind = "store_n", input_count = 1, order = 1 }),
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
        assert(shard_count ~= nil and shard_count >= 1, "residual_mc_intern_set: shard_count must be >= 1")
        assert(shard_index ~= nil and shard_index >= 1 and shard_index <= shard_count, "residual_mc_intern_set: shard_index must be in 1..shard_count")
        local ordinal = 0
        return function(cell)
            ordinal = ordinal + 1
            if ((ordinal - 1) % shard_count) + 1 ~= shard_index then return true end
            return emit(cell)
        end
    end

    function M.each_cell(opts, emit)
        opts = opts or {}
        emit = shard_filter(opts, assert(emit, "residual_mc_intern_set.each_cell requires an emit callback"))
        local budget = saturation_budget(opts)
        append_saturated_cells(emit, budget)
        append_rank_scope_window_probe_cells(emit)
    end

    function M.cells(opts)
        local out = {}
        M.each_cell(opts, function(cell)
            out[#out + 1] = cell
            return true
        end)
        return out
    end

    function M.saturation_summary(opts)
        local budget = saturation_budget(opts)
        local cells, composed, estimated = 0, 0, 0
        M.each_cell(opts, function(cell)
            cells = cells + 1
            if cell.composition ~= nil then composed = composed + 1 end
            estimated = estimated + cell_estimated_bytes(cell)
            return true
        end)
        return {
            cells = cells,
            primitive_cells = cells - composed,
            composed_cells = composed,
            estimated_embedded_bytes = estimated,
            budget = budget,
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

    local function append_point_body_extra_inputs(inputs, cell, input_count)
        local group = assert(layout_groups[cell.group], cell.group)
        if group.scatter_reduce_dst == true then return inputs end
        return append_extra_inputs(inputs, cell, input_count)
    end

    local function point_inputs(cell, input_count, layouts)
        local inputs = {}
        local input_ty = cell.input_ty or cell.item_ty or cell.result_ty or i32
        for i = 1, input_count do
            local name = "x" .. tostring(i)
            inputs[i] = { name = name, ty = input_ty, layout = layouts and input_layout(cell, name) or nil }
        end
        return inputs
    end

    local builders = {}

    local function cell_reduction(cell)
        local red = assert(cell.reduction, "residual_mc_intern_set: sink cell missing reduction")
        return reduction(assert(red.op, "residual_mc_intern_set: reduction missing op"), cell.result_ty or cell.item_ty or i32)
    end

    local function cell_tag(cell, prefix)
        local red = cell.reduction and ("_" .. tostring(cell.reduction.name)) or ""
        return tostring(prefix) .. red .. "_o" .. tostring(cell.order) .. "_in" .. tostring(cell.input_count) .. "_s" .. tostring(cell.point_stage_count) .. "_" .. tostring(cell.expr_name) .. "_" .. tostring(cell.serial)
    end

    function builders.store_n(cell)
        local input_count = assert(cell.input_count, "store_n cell requires input_count")
        local inputs = point_inputs(cell, input_count, true)
        append_extra_inputs(inputs, cell, input_count)
        return Plan.store_n_artifact(with_producer(cell, {
            result_ty = cell.result_ty or i32,
            inputs = inputs,
            expr = assert(cell.expr, "store_n cell requires generated expression"),
            step_num = 1,
            dst_layout = dst_layout(cell),
        }))
    end

    function builders.reduce_n(cell)
        local input_count = assert(cell.input_count, "reduce_n cell requires input_count")
        local inputs = point_inputs(cell, input_count, true)
        append_extra_inputs(inputs, cell, input_count)
        return Plan.reduce_n_artifact(cell_reduction(cell), nil, with_producer(cell, {
            tag = cell_tag(cell, "bank"),
            inputs = inputs,
            expr = assert(cell.expr, "reduce_n cell requires generated expression"),
            item_ty = cell.item_ty or cell.result_ty or i32,
            result_ty = cell.result_ty or i32,
            step_num = 1,
            scope = cell.scope,
            dst_layout = dst_layout(cell),
        }))
    end

    function builders.scan_n(cell)
        local input_count = assert(cell.input_count, "scan_n cell requires input_count")
        local inputs = point_inputs(cell, input_count, true)
        append_extra_inputs(inputs, cell, input_count)
        return Plan.scan_n_artifact(cell_reduction(cell), nil, with_producer(cell, {
            tag = cell_tag(cell, "bank"),
            inputs = inputs,
            expr = assert(cell.expr, "scan_n cell requires generated expression"),
            item_ty = cell.item_ty or cell.result_ty or i32,
            result_ty = cell.result_ty or i32,
            step_num = 1,
            dst_layout = dst_layout(cell),
            axis = cell.axis,
        }))
    end

    function builders.scatter_reduce_n(cell)
        local input_count = assert(cell.input_count, "scatter_reduce_n cell requires input_count")
        local inputs = point_inputs(cell, input_count, true)
        append_extra_inputs(inputs, cell, input_count)
        return Plan.scatter_reduce_n_artifact(cell_reduction(cell), nil, with_producer(cell, {
            tag = cell_tag(cell, "bank"),
            inputs = inputs,
            expr = assert(cell.expr, "scatter_reduce_n cell requires generated expression"),
            item_ty = cell.item_ty or cell.result_ty or i32,
            result_ty = cell.result_ty or i32,
            index_ty = cell.index_ty or i32,
            step_num = 1,
            dst_layout = dst_layout(cell),
        }))
    end

    local function metastencil_store_artifact(cell)
        local input_count = assert(cell.input_count, "metastencil store cell requires input_count")
        local inputs = point_inputs(cell, input_count, true)
        append_point_body_extra_inputs(inputs, cell, input_count)
        return Plan.store_n_artifact(with_producer(cell, {
            result_ty = cell.result_ty or i32,
            inputs = inputs,
            expr = assert(cell.expr, "metastencil store cell requires generated expression"),
            step_num = 1,
            dst_layout = nil,
        }))
    end

    local function metastencil_sink_artifact(cell)
        local inputs = { { name = "x1", ty = cell.result_ty or i32, layout = nil } }
        append_extra_inputs(inputs, cell, 1)
        if cell.kind == "reduce_n" then
            return Plan.reduce_n_artifact(cell_reduction(cell), nil, with_producer(cell, {
                tag = cell_tag(cell, "meta_sink"),
                inputs = inputs,
                expr = input("x1"),
                item_ty = cell.result_ty or i32,
                result_ty = cell.result_ty or i32,
                step_num = 1,
                scope = cell.scope,
                dst_layout = dst_layout(cell),
            }))
        end
        if cell.kind == "scan_n" then
            return Plan.scan_n_artifact(cell_reduction(cell), nil, with_producer(cell, {
                tag = cell_tag(cell, "meta_sink"),
                inputs = inputs,
                expr = input("x1"),
                item_ty = cell.result_ty or i32,
                result_ty = cell.result_ty or i32,
                step_num = 1,
                dst_layout = dst_layout(cell),
                axis = cell.axis,
            }))
        end
        if cell.kind == "scatter_reduce_n" then
            return Plan.scatter_reduce_n_artifact(cell_reduction(cell), nil, with_producer(cell, {
                tag = cell_tag(cell, "meta_sink"),
                inputs = inputs,
                expr = input("x1"),
                item_ty = cell.result_ty or i32,
                result_ty = cell.result_ty or i32,
                index_ty = cell.index_ty or i32,
                step_num = 1,
                dst_layout = dst_layout(cell),
            }))
        end
        error("residual_mc_intern_set: unsupported metastencil sink kind " .. tostring(cell.kind), 2)
    end

    local function metastencil_artifact_for_cell(cell)
        local store_artifact = metastencil_store_artifact(cell)
        local sink_artifact = metastencil_sink_artifact(cell)
        local store_node = Meta.node_from_artifact("store", store_artifact)
        local sink_node = Meta.node_from_artifact("sink", sink_artifact)
        local desc = Meta.descriptor(
            "bank:" .. tostring(cell.name),
            {},
            { store_node, sink_node },
            { Meta.wire("w:store:sink", "store", "dst", "sink", "x1", cell.result_ty or i32) },
            sink_artifact.instance.abi
        )
        local cover = Meta.select_longest_legal_cover({ desc })
        local artifacts = Meta.normalize_artifact_inputs({ cover })
        assert(#artifacts == 1, "residual_mc_intern_set: metastencil cover must materialize one fused artifact")
        return artifacts[1]
    end

    function M.artifact_for_cell(cell)
        if cell.composition == "store_to_sink" then
            local artifact = metastencil_artifact_for_cell(cell)
            assert(Plan.descriptor_vocab(artifact.instance.descriptor) == Stencil[cell.vocab], "residual_mc_intern_set: cell " .. cell.name .. " produced wrong metastencil vocab")
            return artifact
        end
        local build = assert(builders[cell.kind], "residual_mc_intern_set: no builder for cell kind " .. tostring(cell.kind))
        local artifact = build(cell)
        assert(Plan.descriptor_vocab(artifact.instance.descriptor) == Stencil[cell.vocab], "residual_mc_intern_set: cell " .. cell.name .. " produced wrong basis vocab")
        return artifact
    end

    function M.each_artifact(opts, emit)
        emit = assert(emit, "residual_mc_intern_set.each_artifact requires an emit callback")
        return M.each_cell(opts, function(cell)
            return emit(M.artifact_for_cell(cell), cell)
        end)
    end

    function M.artifact_batches(opts, emit)
        opts = opts or {}
        emit = assert(emit, "residual_mc_intern_set.artifact_batches requires an emit callback")
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
