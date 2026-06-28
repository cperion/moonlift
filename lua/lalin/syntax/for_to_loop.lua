-- lalin.syntax.for_to_loop
-- Lowers parsed StmtForRange into LalinTree.ControlStmtRegion (4-block CPS).
-- Follows the same lowering pattern as the DSL's native_loop_stmt_tree.
--
-- Usage: local for_to_loop = require("lalin.syntax.for_to_loop")(T)

local pvm = require("lalin.pvm")

local function bind_context(T)
  if not T.LalinCore then
    require("lalin.schema_projection")(T)
  end
  local C, Ty, B, Tr = T.LalinCore, T.LalinType, T.LalinBind, T.LalinTree

  local to_tree = require("lalin.syntax.to_tree")(T)
  local M = {}
  local loop_seq = 0
  local idx_ty = Ty.TScalar(C.ScalarIndex)

  local function binding(name, ty)
    return B.Binding(C.Id("parsed." .. tostring(name)), name, ty, B.BindingClassLocalValue)
  end

  local function lit(n)
    return { tag = "Literal", kind = "number", value = n }
  end

  local function ast_scalar(v)
    if type(v) ~= "table" then return v end
    if v.tag == "Literal" then
      if v.kind == "string" then
        local raw = tostring(v.source or "")
        return raw:sub(1, 1) == raw:sub(-1) and raw:sub(2, -2) or raw
      end
      return v.value
    end
    return v
  end

  local function ast_record(v)
    if type(v) ~= "table" or v.tag ~= "Record" then return nil end
    local out = {}
    for _, f in ipairs(v.fields or {}) do
      local value = ast_scalar(f.value)
      if f.key then out[f.key] = value else out[#out + 1] = value end
    end
    return out
  end

  local function ast_table(v)
    local record = ast_record(v)
    if not record then return ast_scalar(v) end
    for k, value in pairs(record) do
      if type(value) == "table" and value.tag == "Record" then
        record[k] = ast_table(value)
      end
    end
    return record
  end

  local function expr_from_value(v)
    if type(v) == "table" and v.tag then return to_tree.expr(v) end
    return to_tree.expr(lit(v))
  end

  local function source_zero(v)
    return type(v) == "number" and v == 0
  end

  local function axis_from_spec(spec)
    spec = ast_table(spec)
    if type(spec) ~= "table" then error("parsed range_nd axes expect { start, stop } ranges", 2) end
    local start = spec.start or spec[1] or 0
    local stop = spec.stop or spec[2]
    if stop == nil then error("parsed range_nd axis expects a stop bound", 2) end
    local step = spec.step or spec[3] or 1
    if type(step) ~= "number" or step == 0 then error("parsed range_nd axis step must be a non-zero numeric literal", 2) end
    return {
      ty = step < 0 and Ty.TScalar(C.ScalarI32) or idx_ty,
      start = start,
      stop = stop,
      step = math.abs(step),
      order = step < 0 and "backward" or "forward",
    }
  end

  local function domain_from_parsed(parsed)
    local spec = ast_table((parsed.args or {})[1])
    if type(spec) ~= "table" then error("parsed " .. tostring(parsed.producer) .. " expects a record/table argument", 2) end
    local axes_src = ast_table(spec.axes or spec)
    local axes = {}
    if type(axes_src) == "table" and axes_src.tag == "Record" then axes_src = ast_table(axes_src) end
    for i = 1, #axes_src do axes[i] = axis_from_spec(axes_src[i]) end
    if #axes == 0 then error("parsed " .. tostring(parsed.producer) .. " expects at least one axis", 2) end
    if parsed.producer == "range_nd" then
      return { kind = "range_nd", axes = axes }
    elseif parsed.producer == "tiled_nd" then
      local tiles = ast_table(spec.tiles or spec.tile_sizes or spec.tile)
      if type(tiles) ~= "table" or #tiles ~= #axes then error("parsed tiled_nd expects one tile size per axis", 2) end
      local out = {}
      for i = 1, #tiles do
        local n = tonumber(tiles[i])
        if n == nil or math.floor(n) ~= n or n <= 0 then error("parsed tiled_nd tile sizes must be positive integer literals", 2) end
        out[i] = n
      end
      return { kind = "tiled_nd", axes = axes, tile_sizes = out }
    elseif parsed.producer == "window_nd" then
      local windows_src = ast_table(spec.windows or spec.window)
      if type(windows_src) ~= "table" or #windows_src ~= #axes then error("parsed window_nd expects one window per axis", 2) end
      local windows = {}
      for i = 1, #windows_src do
        local w = ast_table(windows_src[i])
        if type(w) ~= "table" then error("parsed window_nd windows expect records", 2) end
        local before = tonumber(w.before or w[1] or 0)
        local after = tonumber(w.after or w[2] or 0)
        local boundary = w.boundary or "reject"
        if boundary ~= "reject" and boundary ~= "clamp" and boundary ~= "wrap" and boundary ~= "zero" then
          error("parsed window_nd boundary must be reject, clamp, wrap, or zero", 2)
        end
        windows[i] = { before = before, after = after, boundary = boundary }
      end
      return { kind = "window_nd", axes = axes, windows = windows }
    end
  end

  local function reducer_expr(by, acc, step)
    if by == nil or by == "add" then
      return Tr.ExprBinary(Tr.ExprSurface, C.BinAdd, acc, step)
    elseif by == "mul" then
      return Tr.ExprBinary(Tr.ExprSurface, C.BinMul, acc, step)
    elseif by == "band" or by == "and" then
      return Tr.ExprBinary(Tr.ExprSurface, C.BinBitAnd, acc, step)
    elseif by == "bor" or by == "or" then
      return Tr.ExprBinary(Tr.ExprSurface, C.BinBitOr, acc, step)
    elseif by == "bxor" or by == "xor" then
      return Tr.ExprBinary(Tr.ExprSurface, C.BinBitXor, acc, step)
    elseif by == "min" then
      return Tr.ExprSelect(Tr.ExprSurface, Tr.ExprCompare(Tr.ExprSurface, C.CmpLe, acc, step), acc, step)
    elseif by == "max" then
      return Tr.ExprSelect(Tr.ExprSurface, Tr.ExprCompare(Tr.ExprSurface, C.CmpGe, acc, step), acc, step)
    end
    error("parsed fold/scan reducer must be one of add, mul, band, bor, bxor, min, max", 2)
  end

  local function split_sink(body)
    local out, sink = {}, nil
    for _, stmt in ipairs(body or {}) do
      if stmt.tag == "StmtFold" or stmt.tag == "StmtScan" then
        if sink ~= nil then
          error("parsed for loop accepts only one fold or scan sink", 2)
        end
        sink = stmt
      else
        out[#out + 1] = stmt
      end
    end
    return out, sink
  end

  local function lower_nd(parsed)
    loop_seq = loop_seq + 1
    local tag = "parsed." .. tostring(loop_seq)
    local domain = domain_from_parsed(parsed)
    local indexes = parsed.indexes or { parsed.index }
    local axis_count = #(domain.axes or {})
    if #indexes ~= axis_count then error("parsed " .. tostring(parsed.producer) .. " expects one index name per axis", 2) end
    for _, axis in ipairs(domain.axes or {}) do
      if axis.order ~= "forward" then error("parsed range_nd lowering currently expects forward axes", 2) end
      if axis.step <= 0 then error("parsed range_nd axis step must be positive", 2) end
    end

    local body_src, sink = split_sink(parsed.body)
    local result_ty = parsed.result_type and to_tree.parsed_type(parsed.result_type) or nil
    if result_ty == nil and sink ~= nil and sink.tag == "StmtFold" then
      result_ty = to_tree.parsed_type(sink.type)
    end
    if result_ty ~= nil and sink == nil then error("parsed ND loop result type requires a fold or scan sink", 2) end
    if sink ~= nil and sink.tag == "StmtScan" and axis_count > 1 and sink.axis == nil then error("parsed scan over ND loop requires `over`", 2) end

    local flat_name = "__lln_flat_" .. tag
    local flat_ref = Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(flat_name))
    local function ref(name) return Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(name)) end
    local function cast_idx(v) return Tr.ExprCast(Tr.ExprSurface, C.SurfaceCast, idx_ty, expr_from_value(v)) end
    local function bin(op, a, b) return Tr.ExprBinary(Tr.ExprSurface, op, a, b) end
    local function axis_expr(axis, value) return Tr.ExprCast(Tr.ExprSurface, C.SurfaceCast, axis.ty, expr_from_value(value)) end
    local function axis_param_name(axis_i, field, axis, index_name)
      return "__lln_axis_" .. tag .. "_" .. tostring(axis_i) .. "_idx_" .. tostring(index_name) .. "_" .. field .. "_step_" .. tostring(axis.step) .. "_order_" .. axis.order
    end

    local axis_specs = {}
    local loop_params = { Tr.BlockParam(flat_name, idx_ty) }
    local body_params = { Tr.BlockParam(flat_name, idx_ty) }
    local entry_args = { Tr.JumpArg(flat_name, cast_idx(0)) }
    for i, axis in ipairs(domain.axes) do
      local index_name = indexes[i]
      local start_name = axis_param_name(i, "start", axis, index_name)
      local stop_name = axis_param_name(i, "stop", axis, index_name)
      local trip_name = axis_param_name(i, "trip", axis, index_name)
      local start_init = axis_expr(axis, axis.start)
      local stop_init = axis_expr(axis, axis.stop)
      local diff = bin(C.BinSub, stop_init, start_init)
      local trip = diff
      if axis.step ~= 1 then
        trip = bin(C.BinDiv, bin(C.BinAdd, diff, axis_expr(axis, axis.step - 1)), axis_expr(axis, axis.step))
      end
      loop_params[#loop_params + 1] = Tr.BlockParam(start_name, axis.ty)
      loop_params[#loop_params + 1] = Tr.BlockParam(stop_name, axis.ty)
      loop_params[#loop_params + 1] = Tr.BlockParam(trip_name, axis.ty)
      body_params[#body_params + 1] = Tr.BlockParam(start_name, axis.ty)
      body_params[#body_params + 1] = Tr.BlockParam(stop_name, axis.ty)
      body_params[#body_params + 1] = Tr.BlockParam(trip_name, axis.ty)
      entry_args[#entry_args + 1] = Tr.JumpArg(start_name, start_init)
      entry_args[#entry_args + 1] = Tr.JumpArg(stop_name, stop_init)
      entry_args[#entry_args + 1] = Tr.JumpArg(trip_name, trip)
      axis_specs[i] = { index = index_name, ty = axis.ty, start_name = start_name, stop_name = stop_name, trip_name = trip_name, step = axis.step }
    end

    local scan_axis
    if sink ~= nil and sink.tag == "StmtScan" then
      if sink.axis ~= nil then
        if type(sink.axis) == "number" then scan_axis = sink.axis
        elseif type(sink.axis) == "string" then
          for i, spec in ipairs(axis_specs) do if spec.index == sink.axis then scan_axis = i end end
        elseif type(sink.axis) == "table" and sink.axis.tag == "Literal" then scan_axis = sink.axis.value
        elseif type(sink.axis) == "table" and sink.axis.tag == "Name" then
          for i, spec in ipairs(axis_specs) do if spec.index == sink.axis.name then scan_axis = i end end
        end
      end
      if axis_count > 1 and (scan_axis == nil or scan_axis < 1 or scan_axis > axis_count) then
        error("parsed scan `over` must name an index or axis number in this loop", 2)
      end
    end

    local scan_axis_suffix = scan_axis ~= nil and ("_scan_axis_" .. tostring(scan_axis)) or ""
    local producer_suffix = ""
    if domain.kind == "tiled_nd" then
      producer_suffix = "_tiled_" .. table.concat(domain.tile_sizes or {}, "x")
    elseif domain.kind == "window_nd" then
      local parts = {}
      for i, w in ipairs(domain.windows or {}) do parts[i] = tostring(w.boundary) .. "_" .. tostring(w.before) .. "_" .. tostring(w.after) end
      producer_suffix = "_window_" .. table.concat(parts, "__")
    end
    local entry_label = Tr.BlockLabel("lln_entry_" .. tag .. scan_axis_suffix)
    local loop_label = Tr.BlockLabel("lln_loop_nd_" .. tag .. producer_suffix .. scan_axis_suffix)
    local body_label = Tr.BlockLabel("lln_body_nd_" .. tag .. scan_axis_suffix)
    local done_label = Tr.BlockLabel("lln_done_nd_" .. tag .. scan_axis_suffix)

    local function invariant_jump_args()
      local out = {}
      for _, axis in ipairs(axis_specs) do
        out[#out + 1] = Tr.JumpArg(axis.start_name, ref(axis.start_name))
        out[#out + 1] = Tr.JumpArg(axis.stop_name, ref(axis.stop_name))
        out[#out + 1] = Tr.JumpArg(axis.trip_name, ref(axis.trip_name))
      end
      return out
    end
    local function loop_jump_args(flat_value, acc_name, acc_value)
      local out = { Tr.JumpArg(flat_name, flat_value) }
      for _, arg in ipairs(invariant_jump_args()) do out[#out + 1] = arg end
      if acc_name ~= nil then out[#out + 1] = Tr.JumpArg(acc_name, acc_value) end
      return out
    end

    local total = ref(axis_specs[axis_count].trip_name)
    for i = axis_count - 1, 1, -1 do total = bin(C.BinMul, ref(axis_specs[i].trip_name), total) end
    local cond = Tr.ExprCompare(Tr.ExprSurface, C.CmpLt, flat_ref, total)
    local next_flat = bin(C.BinAdd, flat_ref, cast_idx(1))

    local coord_stmts, stride = {}, cast_idx(1)
    for i = axis_count, 1, -1 do
      local axis, spec = domain.axes[i], axis_specs[i]
      local lane = flat_ref
      if i < axis_count then lane = bin(C.BinDiv, flat_ref, stride) end
      lane = bin(C.BinRem, lane, ref(spec.trip_name))
      local coord = lane
      if axis.step ~= 1 then coord = bin(C.BinMul, coord, axis_expr(axis, axis.step)) end
      coord = bin(C.BinAdd, ref(spec.start_name), coord)
      coord_stmts[i] = Tr.StmtLet(Tr.StmtSurface, binding(spec.index, spec.ty), coord)
      stride = bin(C.BinMul, stride, ref(spec.trip_name))
    end

    local function expr_ref_name(expr)
      if pvm.classof(expr) ~= Tr.ExprRef then return nil end
      local r = expr.ref
      if pvm.classof(r) == B.ValueRefName then return r.name end
      return nil
    end
    local function expr_lit_int(expr)
      if pvm.classof(expr) ~= Tr.ExprLit then return nil end
      local value = expr.value
      if pvm.classof(value) == C.LitInt then return tostring(value.raw) end
      return nil
    end
    local function expr_key(expr)
      local cls = pvm.classof(expr)
      if cls == Tr.ExprRef then return "ref:" .. tostring(expr_ref_name(expr)) end
      if cls == Tr.ExprLit then return "int:" .. tostring(expr_lit_int(expr)) end
      if cls == Tr.ExprCast then return expr_key(expr.value) end
      if cls == Tr.ExprBinary then return "bin:" .. tostring(expr.op) .. "(" .. tostring(expr_key(expr.lhs)) .. "," .. tostring(expr_key(expr.rhs)) .. ")" end
      return nil
    end
    local extent_keys = {}
    for i = 1, axis_count do
      local axis = domain.axes[i]
      local stop_expr = expr_from_value(axis.stop)
      extent_keys[i] = { [expr_key(stop_expr)] = true }
      if not source_zero(axis.start) or axis.step ~= 1 then
        local start_expr = expr_from_value(axis.start)
        local diff = bin(C.BinSub, stop_expr, start_expr)
        local trip = diff
        if axis.step ~= 1 then trip = bin(C.BinDiv, bin(C.BinAdd, diff, expr_from_value(axis.step - 1)), expr_from_value(axis.step)) end
        extent_keys[i][expr_key(trip)] = true
      end
    end
    local function same_expr(a, b) return expr_key(a) == expr_key(b) end
    local function is_ref(expr, name) return expr_ref_name(expr) == name end
    local function is_extent(expr, axis_i) return extent_keys[axis_i] ~= nil and extent_keys[axis_i][expr_key(expr)] == true end
    local function strip_axis_start(expr, axis_i)
      local axis = domain.axes[axis_i]
      if source_zero(axis.start) then return expr end
      if pvm.classof(expr) ~= Tr.ExprBinary or expr.op ~= C.BinSub then return nil end
      if not is_ref(expr.lhs, axis_specs[axis_i].index) then return nil end
      if not same_expr(expr.rhs, expr_from_value(axis.start)) then return nil end
      return expr.lhs
    end
    local function is_axis_lane(expr, axis_i)
      local axis = domain.axes[axis_i]
      local lane = expr
      if axis.step ~= 1 then
        if pvm.classof(lane) ~= Tr.ExprBinary or lane.op ~= C.BinDiv then return false end
        if not same_expr(lane.rhs, expr_from_value(axis.step)) then return false end
        lane = lane.lhs
      end
      lane = strip_axis_start(lane, axis_i)
      return lane ~= nil and is_ref(lane, axis_specs[axis_i].index)
    end
    local is_row_major_prefix
    local function is_mul_prefix_extent(expr, prefix_axis)
      return pvm.classof(expr) == Tr.ExprBinary and expr.op == C.BinMul
        and ((is_row_major_prefix(expr.lhs, prefix_axis) and is_extent(expr.rhs, prefix_axis + 1))
          or (is_row_major_prefix(expr.rhs, prefix_axis) and is_extent(expr.lhs, prefix_axis + 1)))
    end
    is_row_major_prefix = function(expr, axis_i)
      if axis_i == 1 then return is_axis_lane(expr, 1) end
      return pvm.classof(expr) == Tr.ExprBinary and expr.op == C.BinAdd
        and ((is_mul_prefix_extent(expr.lhs, axis_i - 1) and is_axis_lane(expr.rhs, axis_i))
          or (is_mul_prefix_extent(expr.rhs, axis_i - 1) and is_axis_lane(expr.lhs, axis_i)))
    end
    local function is_row_major_nd(expr) return is_row_major_prefix(expr, axis_count) end

    local rewrite_expr, rewrite_place, rewrite_index_base
    rewrite_expr = function(expr)
      local cls = pvm.classof(expr)
      if is_row_major_nd(expr) then return flat_ref end
      if cls == Tr.ExprBinary then return Tr.ExprBinary(expr.h, expr.op, rewrite_expr(expr.lhs), rewrite_expr(expr.rhs)) end
      if cls == Tr.ExprCompare then return Tr.ExprCompare(expr.h, expr.op, rewrite_expr(expr.lhs), rewrite_expr(expr.rhs)) end
      if cls == Tr.ExprLogic then return Tr.ExprLogic(expr.h, expr.op, rewrite_expr(expr.lhs), rewrite_expr(expr.rhs)) end
      if cls == Tr.ExprUnary then return Tr.ExprUnary(expr.h, expr.op, rewrite_expr(expr.value)) end
      if cls == Tr.ExprCast then return Tr.ExprCast(expr.h, expr.op, expr.ty, rewrite_expr(expr.value)) end
      if cls == Tr.ExprIndex then return Tr.ExprIndex(expr.h, rewrite_index_base(expr.base), rewrite_expr(expr.index)) end
      if cls == Tr.ExprCall then
        local args = {}
        for i, arg in ipairs(expr.args or {}) do args[i] = rewrite_expr(arg) end
        return Tr.ExprCall(expr.h, rewrite_expr(expr.callee), args)
      end
      return expr
    end
    rewrite_place = function(place)
      local cls = pvm.classof(place)
      if cls == Tr.PlaceIndex then return Tr.PlaceIndex(place.h, rewrite_index_base(place.base), rewrite_expr(place.index)) end
      if cls == Tr.PlaceDot then return Tr.PlaceDot(place.h, rewrite_place(place.base), place.name) end
      return place
    end
    rewrite_index_base = function(base)
      local cls = pvm.classof(base)
      if cls == Tr.IndexBaseExpr then return Tr.IndexBaseExpr(rewrite_expr(base.base)) end
      if cls == Tr.IndexBasePlace then return Tr.IndexBasePlace(rewrite_place(base.base), base.elem) end
      return base
    end
    local function rewrite_stmt(stmt)
      local cls = pvm.classof(stmt)
      if cls == Tr.StmtSet then return Tr.StmtSet(stmt.h, rewrite_place(stmt.place), rewrite_expr(stmt.value)) end
      if cls == Tr.StmtLet then return Tr.StmtLet(stmt.h, stmt.binding, rewrite_expr(stmt.init)) end
      if cls == Tr.StmtVar then return Tr.StmtVar(stmt.h, stmt.binding, rewrite_expr(stmt.init)) end
      if cls == Tr.StmtExpr then return Tr.StmtExpr(stmt.h, rewrite_expr(stmt.expr)) end
      if cls == Tr.StmtIf then
        local then_body, else_body = {}, {}
        for i, child in ipairs(stmt.then_body or {}) do then_body[i] = rewrite_stmt(child) end
        for i, child in ipairs(stmt.else_body or {}) do else_body[i] = rewrite_stmt(child) end
        return Tr.StmtIf(stmt.h, rewrite_expr(stmt.cond), then_body, else_body)
      end
      return stmt
    end

    local body_stmts = {}
    for i = 1, #coord_stmts do body_stmts[#body_stmts + 1] = coord_stmts[i] end
    for _, stmt in ipairs(to_tree.stmts(body_src)) do body_stmts[#body_stmts + 1] = rewrite_stmt(stmt) end

    if sink == nil then
      body_stmts[#body_stmts + 1] = Tr.StmtJump(Tr.StmtSurface, loop_label, loop_jump_args(next_flat))
      return Tr.StmtControl(Tr.StmtSurface, Tr.ControlStmtRegion(tag, Tr.EntryControlBlock(entry_label, {}, {
        Tr.StmtJump(Tr.StmtSurface, loop_label, entry_args),
      }), {
        Tr.ControlBlock(loop_label, loop_params, {
          Tr.StmtIf(Tr.StmtSurface, cond, { Tr.StmtJump(Tr.StmtSurface, body_label, loop_jump_args(flat_ref)) }, {}),
          Tr.StmtJump(Tr.StmtSurface, done_label, {}),
        }),
        Tr.ControlBlock(body_label, body_params, body_stmts),
        Tr.ControlBlock(done_label, {}, { Tr.StmtYieldVoid(Tr.StmtSurface) }),
      }))
    end

    local acc, acc_ty = sink.name, to_tree.parsed_type(sink.type)
    local acc_ref = ref(acc)
    loop_params[#loop_params + 1] = Tr.BlockParam(acc, acc_ty)
    body_params[#body_params + 1] = Tr.BlockParam(acc, acc_ty)
    entry_args[#entry_args + 1] = Tr.JumpArg(acc, Tr.ExprCast(Tr.ExprSurface, C.SurfaceCast, acc_ty, to_tree.expr(sink.init)))
    local step_name = "__lln_step_" .. tag
    body_stmts[#body_stmts + 1] = Tr.StmtLet(Tr.StmtSurface, binding(step_name, acc_ty), rewrite_expr(to_tree.expr(sink.step)))
    local next_acc = reducer_expr(sink.by, acc_ref, ref(step_name))
    if sink.tag == "StmtScan" then
      local next_name = "__lln_scan_" .. tag
      body_stmts[#body_stmts + 1] = Tr.StmtLet(Tr.StmtSurface, binding(next_name, acc_ty), next_acc)
      body_stmts[#body_stmts + 1] = Tr.StmtSet(Tr.StmtSurface, rewrite_place(to_tree.place(sink.into)), ref(next_name))
      body_stmts[#body_stmts + 1] = Tr.StmtJump(Tr.StmtSurface, loop_label, loop_jump_args(next_flat, acc, ref(next_name)))
    else
      body_stmts[#body_stmts + 1] = Tr.StmtJump(Tr.StmtSurface, loop_label, loop_jump_args(next_flat, acc, next_acc))
    end

    local loop_block = Tr.ControlBlock(loop_label, loop_params, {
      Tr.StmtIf(Tr.StmtSurface, cond, { Tr.StmtJump(Tr.StmtSurface, body_label, loop_jump_args(flat_ref, acc, acc_ref)) }, {}),
      Tr.StmtJump(Tr.StmtSurface, done_label, { Tr.JumpArg(acc, acc_ref) }),
    })
    local body_block = Tr.ControlBlock(body_label, body_params, body_stmts)
    local done_block = Tr.ControlBlock(done_label, { Tr.BlockParam(acc, acc_ty) }, {
      result_ty ~= nil and Tr.StmtYieldValue(Tr.StmtSurface, acc_ref) or Tr.StmtYieldVoid(Tr.StmtSurface),
    })
    if result_ty ~= nil then
      return Tr.StmtReturnValue(Tr.StmtSurface, Tr.ExprControl(Tr.ExprSurface, Tr.ControlExprRegion(
        tag, result_ty, Tr.EntryControlBlock(entry_label, {}, { Tr.StmtJump(Tr.StmtSurface, loop_label, entry_args) }), { loop_block, body_block, done_block }
      )))
    end
    return Tr.StmtControl(Tr.StmtSurface, Tr.ControlStmtRegion(
      tag, Tr.EntryControlBlock(entry_label, {}, { Tr.StmtJump(Tr.StmtSurface, loop_label, entry_args) }), { loop_block, body_block, done_block }
    ))
  end

  --- Lower a parsed loop over a 1D range into LalinTree ASDL.
  --   loop i in lo .. hi do ... end    step defaults to 1
  --   loop i in lo .. hi .. step do ... end
  function M.lower(parsed)
    if parsed.producer ~= "range" then
      return lower_nd(parsed)
    end
    loop_seq = loop_seq + 1
    local tag = "parsed." .. tostring(loop_seq)
    local index = parsed.index
    local args = parsed.args or {}
    if #args == 1 and type(args[1]) == "table" and args[1].tag == "Record" then
      local fields = args[1].fields or {}
      args = {}
      for i, field in ipairs(fields) do
        if field.key == nil then args[#args + 1] = field.value end
      end
    end
    local result_ty = parsed.result_type and to_tree.parsed_type(parsed.result_type) or nil

    -- Cast range arguments to index type, matching the DSL lowering pattern.
    local function to_idx(v)
      return Tr.ExprCast(Tr.ExprSurface, C.SurfaceCast, idx_ty, to_tree.expr(v))
    end
    local zero  = to_idx({ tag = "Literal", kind = "number", value = 0 })
    local one   = to_idx({ tag = "Literal", kind = "number", value = 1 })
    local start_expr = args[1] and to_idx(args[1]) or zero
    local stop_expr  = args[2] and to_idx(args[2]) or one
    local step_expr  = args[3] and to_idx(args[3]) or one

    -- Build loop body: original body statements + tail jump back to loop header
    local body_src, sink = split_sink(parsed.body)
    if result_ty == nil and sink ~= nil and sink.tag == "StmtFold" then
      result_ty = to_tree.parsed_type(sink.type)
    end
    if result_ty ~= nil and sink == nil then
      error("parsed for loop result type requires a fold or scan sink", 2)
    end
    local body_stmts = to_tree.stmts(body_src)
    local index_ref = Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(index))
    local next_index = Tr.ExprBinary(Tr.ExprSurface, C.BinAdd, index_ref, step_expr)
    local cond = Tr.ExprCompare(Tr.ExprSurface, C.CmpLt, index_ref, stop_expr)

    local entry_label  = Tr.BlockLabel(tag .. ".entry")
    local loop_label   = Tr.BlockLabel(tag .. ".loop")
    local body_label   = Tr.BlockLabel(tag .. ".body")
    local done_label   = Tr.BlockLabel(tag .. ".done")
    local idx_param    = Tr.BlockParam(index, idx_ty)

    if sink ~= nil then
      local acc = sink.name
      local acc_ty = to_tree.parsed_type(sink.type)
      local acc_ref = Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(acc))
      local step_name = "__lln_step_" .. tag
      local step_binding = B.Binding(C.Id("parsed." .. step_name), step_name, acc_ty, B.BindingClassLocalValue)
      local step_ref = Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(step_name))
      body_stmts[#body_stmts + 1] = Tr.StmtLet(Tr.StmtSurface, step_binding, to_tree.expr(sink.step))
      local next_acc = reducer_expr(sink.by, acc_ref, step_ref)
      local entry_args = {
        Tr.JumpArg(index, start_expr),
        Tr.JumpArg(acc, Tr.ExprCast(Tr.ExprSurface, C.SurfaceCast, acc_ty, to_tree.expr(sink.init))),
      }
      local function jump_args(i_value, acc_value)
        return { Tr.JumpArg(index, i_value), Tr.JumpArg(acc, acc_value) }
      end

      if sink.tag == "StmtScan" then
        local next_name = "__lln_scan_" .. tag
        local next_binding = B.Binding(C.Id("parsed." .. next_name), next_name, acc_ty, B.BindingClassLocalValue)
        local next_ref = Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(next_name))
        body_stmts[#body_stmts + 1] = Tr.StmtLet(Tr.StmtSurface, next_binding, next_acc)
        body_stmts[#body_stmts + 1] = Tr.StmtSet(Tr.StmtSurface, to_tree.place(sink.into), next_ref)
        body_stmts[#body_stmts + 1] = Tr.StmtJump(Tr.StmtSurface, loop_label, jump_args(next_index, next_ref))
      else
        body_stmts[#body_stmts + 1] = Tr.StmtJump(Tr.StmtSurface, loop_label, jump_args(next_index, next_acc))
      end

      local loop_block = Tr.ControlBlock(loop_label, { Tr.BlockParam(index, idx_ty), Tr.BlockParam(acc, acc_ty) }, {
        Tr.StmtIf(Tr.StmtSurface, cond, {
          Tr.StmtJump(Tr.StmtSurface, body_label, jump_args(index_ref, acc_ref)),
        }, {}),
        Tr.StmtJump(Tr.StmtSurface, done_label, { Tr.JumpArg(acc, acc_ref) }),
      })
      local body_block = Tr.ControlBlock(body_label, { Tr.BlockParam(index, idx_ty), Tr.BlockParam(acc, acc_ty) }, body_stmts)
      local done_block = Tr.ControlBlock(done_label, { Tr.BlockParam(acc, acc_ty) }, {
        result_ty ~= nil and Tr.StmtYieldValue(Tr.StmtSurface, acc_ref) or Tr.StmtYieldVoid(Tr.StmtSurface),
      })
      if result_ty ~= nil then
        return Tr.StmtReturnValue(Tr.StmtSurface, Tr.ExprControl(Tr.ExprSurface, Tr.ControlExprRegion(
          tag,
          result_ty,
          Tr.EntryControlBlock(entry_label, {}, { Tr.StmtJump(Tr.StmtSurface, loop_label, entry_args) }),
          { loop_block, body_block, done_block }
        )))
      end
      return Tr.StmtControl(Tr.StmtSurface, Tr.ControlStmtRegion(
        tag,
        Tr.EntryControlBlock(entry_label, {}, { Tr.StmtJump(Tr.StmtSurface, loop_label, entry_args) }),
        { loop_block, body_block, done_block }
      ))
    end

    body_stmts[#body_stmts + 1] = Tr.StmtJump(Tr.StmtSurface, loop_label, {
      Tr.JumpArg(index, next_index),
    })

    return Tr.StmtControl(Tr.StmtSurface, Tr.ControlStmtRegion(
      tag,
      Tr.EntryControlBlock(entry_label, {}, {
        Tr.StmtJump(Tr.StmtSurface, loop_label, {
          Tr.JumpArg(index, start_expr),
        }),
      }),
      {
        Tr.ControlBlock(loop_label, { idx_param }, {
          Tr.StmtIf(Tr.StmtSurface, cond, {
            Tr.StmtJump(Tr.StmtSurface, body_label, {
              Tr.JumpArg(index, index_ref),
            }),
          }, {}),
          Tr.StmtJump(Tr.StmtSurface, done_label, {}),
        }),
        Tr.ControlBlock(body_label, { idx_param }, body_stmts),
        Tr.ControlBlock(done_label, {}, {
          Tr.StmtYieldVoid(Tr.StmtSurface),
        }),
      }
    ))
  end

  return M
end

return bind_context
