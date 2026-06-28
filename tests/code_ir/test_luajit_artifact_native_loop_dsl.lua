package.path = table.concat({
    './?.lua',
    './?/init.lua',
    './lua/?.lua',
    './lua/?/init.lua',
    package.path,
}, ';')

local ffi = require('ffi')
local pvm = require('lalin.pvm')
local lalin = require('lalin')

local source = [=[
return unit. NativeLoopDSL {
  fn. native_zip_add { dst [ptr [i32]], lhs [ptr [i32]], rhs [ptr [i32]], n [index] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (lhs)(n), readonly(lhs),
      bounds (rhs)(n), readonly(rhs),
      disjoint (dst)(lhs), disjoint (dst)(rhs), disjoint (lhs)(rhs),
    },

    lln.loop. i [lln.range { 0, n }] {
      set (dst[i])(lhs[i] + rhs[i]),
    },
  },

  fn. native_dot { lhs [ptr [i32]], rhs [ptr [i32]], n [index] } [i32] {
    requires {
      bounds (lhs)(n), readonly(lhs),
      bounds (rhs)(n), readonly(rhs),
    },

    lln.loop. i [lln.range { 0, n }] [lln.i32] {
      lln.fold. acc [lln.i32] {
        init = 0,
        by = lln.add,
        step = lhs[i] * rhs[i],
      },
    },
  },

  fn. native_product { xs [ptr [i32]], n [index] } [i32] {
    requires {
      bounds (xs)(n), readonly(xs),
    },

    lln.loop. i [lln.range { 0, n }] [lln.i32] {
      lln.fold. acc [lln.i32] {
        init = 1,
        by = lln.mul,
        step = xs[i],
      },
    },
  },

  fn. native_min { xs [ptr [i32]], n [index] } [i32] {
    requires {
      bounds (xs)(n), readonly(xs),
    },

    lln.loop. i [lln.range { 0, n }] [lln.i32] {
      lln.fold. acc [lln.i32] {
        init = 2147483647,
        by = lln.min,
        step = xs[i],
      },
    },
  },

  fn. native_scan { dst [ptr [i32]], xs [ptr [i32]], n [index] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (xs)(n), readonly(xs),
      disjoint (dst)(xs),
    },

    lln.loop. i [lln.range { 0, n }] {
      lln.scan. acc [lln.i32] {
        init = 0,
        by = lln.add,
        step = xs[i],
        into = dst[i],
      },
    },
  },

  fn. native_scan_product { dst [ptr [i32]], xs [ptr [i32]], n [index] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (xs)(n), readonly(xs),
      disjoint (dst)(xs),
    },

    lln.loop. i [lln.range { 0, n }] {
      lln.scan. acc [lln.i32] {
        init = 1,
        by = lln.mul,
        step = xs[i],
        into = dst[i],
      },
    },
  },
}
]=]

local session = lalin.use { scope = 'env' }

local function emit_mc_artifact(decl, opts)
    local plan = lalin.plan_luajit_artifact(decl, opts)
    local bank = assert(plan.backend.build_mc_bank(plan.artifacts, { stem = opts.stem }))
    opts.mc_bank = bank
    return lalin.emit_luajit_plan_artifact(plan, opts)
end

local decl = assert(session:loadstring(source, 'test_luajit_artifact_native_loop_dsl.lua'))()
local artifact = emit_mc_artifact(decl, {
    path = 'target/test_artifacts/test_luajit_artifact_native_loop_dsl.lua',
    name = 'NativeLoopDSL',
    stem = 'test_luajit_artifact_native_loop_dsl',
})

assert(artifact.kind == 'LuaJITSourceArtifact')
assert(#artifact.artifacts == 6, 'native lln.loop should select store, fold, and scan stencil artifacts')

local sinks = {}
for _, item in ipairs(artifact.artifacts) do
    local desc = item.instance.descriptor
    assert(tostring(pvm.classof(desc.producer.shape)):match('StencilProduceRange1D'), 'lln.range should project to a Range1D producer')
    sinks[tostring(pvm.classof(desc.sink))] = true
end
assert(sinks['Class(LalinStencil.StencilSinkStore)'], 'native store loop should project to a store sink')
assert(sinks['Class(LalinStencil.StencilSinkReduce)'], 'native fold loop should project to a reduce sink')
assert(sinks['Class(LalinStencil.StencilSinkScan)'], 'native scan loop should project to a scan sink')

local loaded = assert(loadfile(artifact.path))()
local lhs = ffi.new('int32_t[5]', { 1, -2, 5, 0, 3 })
local rhs = ffi.new('int32_t[5]', { 10, 20, -5, 7, 4 })
local out = ffi.new('int32_t[5]')

loaded.native_zip_add(out, lhs, rhs, 5)
assert(out[0] == 11 and out[1] == 18 and out[2] == 0 and out[3] == 7 and out[4] == 7, 'native lln.loop zip add')

local dot = loaded.native_dot(lhs, rhs, 5)
assert(dot == -43, 'native lln.fold dot result')

local product_xs = ffi.new('int32_t[4]', { 2, -3, 4, 5 })
assert(loaded.native_product(product_xs, 4) == -120, 'native lln.fold product result')
assert(loaded.native_min(product_xs, 4) == -3, 'native lln.fold min result')

local xs = ffi.new('int32_t[5]', { 1, -2, 5, 0, 3 })
local scan_out = ffi.new('int32_t[5]')
loaded.native_scan(scan_out, xs, 5)
assert(scan_out[0] == 1 and scan_out[1] == -1 and scan_out[2] == 4 and scan_out[3] == 4 and scan_out[4] == 7, 'native lln.scan output')

local scan_product_xs = ffi.new('int32_t[4]', { 2, 3, 4, 5 })
local scan_product_out = ffi.new('int32_t[4]')
loaded.native_scan_product(scan_product_out, scan_product_xs, 4)
assert(scan_product_out[0] == 2 and scan_product_out[1] == 6 and scan_product_out[2] == 24 and scan_product_out[3] == 120, 'native lln.scan product output')

local reverse_source = [=[
return unit. NativeReverseLoopDSL {
  fn. backward_copy { dst [ptr [i32]], src [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (src)(n), readonly(src),
      disjoint (dst)(src),
    },

    lln.loop. i [lln.range { n - 1, -1, -1, ty = lln.i32 }] {
      set (dst[i])(src[i]),
    },
  },

  fn. reverse_affine_copy { dst [ptr [i32]], src [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (src)(n), readonly(src),
      disjoint (dst)(src),
    },

    lln.loop. i [lln.range { n - 1, -1, -1, ty = lln.i32 }] {
      set (dst[(n - 1) - i])(src[i]),
    },
  },

  fn. backward_sum { xs [ptr [i32]], n [i32] } [i32] {
    requires {
      bounds (xs)(n), readonly(xs),
    },

    lln.loop. i [lln.range { n - 1, -1, -1, ty = lln.i32 }] [lln.i32] {
      lln.fold. acc [lln.i32] {
        init = 0,
        by = lln.add,
        step = xs[i],
      },
    },
  },

  fn. backward_scan { dst [ptr [i32]], xs [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (xs)(n), readonly(xs),
      disjoint (dst)(xs),
    },

    lln.loop. i [lln.range { n - 1, -1, -1, ty = lln.i32 }] {
      lln.scan. acc [lln.i32] {
        init = 0,
        by = lln.add,
        step = xs[i],
        into = dst[i],
      },
    },
  },

  fn. reverse_affine_scan { dst [ptr [i32]], xs [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (xs)(n), readonly(xs),
      disjoint (dst)(xs),
    },

    lln.loop. i [lln.range { n - 1, -1, -1, ty = lln.i32 }] {
      lln.scan. acc [lln.i32] {
        init = 0,
        by = lln.add,
        step = xs[i],
        into = dst[(n - 1) - i],
      },
    },
  },
}
]=]

local reverse_decl = assert(session:loadstring(reverse_source, 'test_luajit_artifact_native_reverse_loop_dsl.lua'))()
local reverse_artifact = emit_mc_artifact(reverse_decl, {
    path = 'target/test_artifacts/test_luajit_artifact_native_reverse_loop_dsl.lua',
    name = 'NativeReverseLoopDSL',
    stem = 'test_luajit_artifact_native_reverse_loop_dsl',
})
assert(#reverse_artifact.artifacts == 5, 'negative-step lln.range should select backward Range1D stencil artifacts for copy, reverse-affine copy, fold, scan, and reverse-affine scan')
local saw_backward_range = false
for _, fact in ipairs(reverse_artifact.facts.flow.domain_shapes or {}) do
    if tostring(pvm.classof(fact.shape)):match('FlowDomainShapeRange1D') then
        saw_backward_range = tostring(pvm.classof(fact.shape.order)):match('FlowDomainBackward') ~= nil
            and fact.shape.step == 1
            and tostring(pvm.classof(fact.origin)):match('FlowFactFrontendFact') ~= nil
    end
end
assert(saw_backward_range, 'negative-step lln.range should author a backward Range1D Flow domain fact')
local saw_backward_artifact = false
local saw_reverse_affine_layout = false
for _, item in ipairs(reverse_artifact.artifacts) do
    local shape = item.instance.descriptor.producer.shape
    assert(tostring(pvm.classof(shape)):match('StencilProduceRange1D'), 'negative-step lln.range should project to a Range1D producer')
    assert(tostring(pvm.classof(shape.order)):match('StencilProducerBackward'), 'negative-step lln.range should preserve backward producer order')
    if item.symbol.text:match('_bs1$') then saw_backward_artifact = true end
    for _, access in ipairs(item.instance.descriptor.accesses or {}) do
        if tostring(pvm.classof(access.role)):match('StencilAccessWrite')
            and tostring(pvm.classof(access.layout)):match('StencilLayoutAffine1D') then
            saw_reverse_affine_layout = true
        end
    end
end
assert(saw_backward_artifact, 'backward Range1D artifact symbol should include backward producer tag')
assert(saw_reverse_affine_layout, 'reverse-affine destination index should be represented as StencilLayoutAffine1D')
local reverse_loaded = assert(loadfile(reverse_artifact.path))()
local reverse_src = ffi.new('int32_t[5]', { 9, 8, 7, 6, 5 })
local reverse_dst = ffi.new('int32_t[5]')
reverse_loaded.backward_copy(reverse_dst, reverse_src, 5)
assert(reverse_dst[0] == 9 and reverse_dst[1] == 8 and reverse_dst[2] == 7 and reverse_dst[3] == 6 and reverse_dst[4] == 5, 'native negative-step lln.range copy output')
local reverse_affine_src = ffi.new('int32_t[5]', { 1, 2, 3, 4, 5 })
local reverse_affine_dst = ffi.new('int32_t[5]')
reverse_loaded.reverse_affine_copy(reverse_affine_dst, reverse_affine_src, 5)
assert(reverse_affine_dst[0] == 5 and reverse_affine_dst[1] == 4 and reverse_affine_dst[2] == 3 and reverse_affine_dst[3] == 2 and reverse_affine_dst[4] == 1, 'native negative-step lln.range reverse-affine copy output')
assert(reverse_loaded.backward_sum(reverse_src, 5) == 35, 'native negative-step lln.fold output')
local reverse_scan_src = ffi.new('int32_t[5]', { 1, 2, 3, 4, 5 })
local reverse_scan_dst = ffi.new('int32_t[5]')
reverse_loaded.backward_scan(reverse_scan_dst, reverse_scan_src, 5)
assert(reverse_scan_dst[0] == 15 and reverse_scan_dst[1] == 14 and reverse_scan_dst[2] == 12 and reverse_scan_dst[3] == 9 and reverse_scan_dst[4] == 5, 'native negative-step lln.scan output')
local reverse_affine_scan_dst = ffi.new('int32_t[5]')
reverse_loaded.reverse_affine_scan(reverse_affine_scan_dst, reverse_scan_src, 5)
assert(reverse_affine_scan_dst[0] == 5 and reverse_affine_scan_dst[1] == 9 and reverse_affine_scan_dst[2] == 12 and reverse_affine_scan_dst[3] == 14 and reverse_affine_scan_dst[4] == 15, 'native negative-step lln.scan reverse-affine output')

local nd_source = [=[
return unit. NativeNDLoopDSL {
  fn. nd_shape { dst [ptr [i32]], src [ptr [i32]], h [index], w [index], n [index] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (src)(n), readonly(src),
      disjoint (dst)(src),
    },

    lln.loop { i, j } [lln.range_nd { { 0, h }, { 0, w } }] {
      set (dst[i * w + j])(src[i * w + j]),
    },
  },

  fn. nd_sum { xs [ptr [i32]], h [index], w [index], n [index] } [i32] {
    requires {
      bounds (xs)(n), readonly(xs),
    },

    lln.loop { i, j } [lln.range_nd { { 0, h }, { 0, w } }] [lln.i32] {
      lln.fold. acc [lln.i32] {
        init = 0,
        by = lln.add,
        step = xs[i * w + j],
      },
    },
  },

	  fn. nd_scan_rows { dst [ptr [i32]], xs [ptr [i32]], h [index], w [index], n [index] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (xs)(n), readonly(xs),
      disjoint (dst)(xs),
    },

    lln.loop { i, j } [lln.range_nd { { 0, h }, { 0, w } }] {
      lln.scan. acc [lln.i32] {
        init = 0,
        by = lln.add,
        axis = 2,
        step = xs[i * w + j],
        into = dst[i * w + j],
	      },
	    },
	  },

	  fn. nd3_shape { dst [ptr [i32]], src [ptr [i32]], a [index], b [index], c [index], n [index] } [void] {
	    requires {
	      bounds (dst)(n), writeonly(dst),
	      bounds (src)(n), readonly(src),
	      disjoint (dst)(src),
	    },

	    lln.loop { i, j, k } [lln.range_nd { { 0, a }, { 0, b }, { 0, c } }] {
	      set (dst[((i * b + j) * c) + k])(src[((i * b + j) * c) + k]),
	    },
	  },

  fn. nd_stepped_start_shape { dst [ptr [i32]], src [ptr [i32]], n [index] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (src)(n), readonly(src),
      disjoint (dst)(src),
    },

    lln.loop { i, j } [lln.range_nd { { 2, 6, 2 }, { 3, 12, 3 } }] {
      set (dst[((i - 2) / 2) * 3 + ((j - 3) / 3)])(src[((i - 2) / 2) * 3 + ((j - 3) / 3)]),
    },
  },

  fn. nd_column_major_store { dst [ptr [i32]], src [ptr [i32]], n [index] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (src)(n), readonly(src),
      disjoint (dst)(src),
    },

    lln.loop { i, j } [lln.range_nd { { 0, 2 }, { 0, 3 } }] {
      set (dst[j * 2 + i])(src[i * 3 + j]),
    },
  },
	}
]=]

local nd_decl = assert(session:loadstring(nd_source, 'test_luajit_artifact_native_nd_loop_dsl.lua'))()
local nd_artifact = emit_mc_artifact(nd_decl, {
    path = 'target/test_artifacts/test_luajit_artifact_native_nd_loop_dsl.lua',
    name = 'NativeNDLoopDSL',
    stem = 'test_luajit_artifact_native_nd_loop_dsl',
})
assert(#nd_artifact.artifacts == 6, 'range_nd copy, fold, axis scan, rank-3 copy, stepped-start copy, and column-major store should select native stencil artifacts')
local nd_sinks = {}
local saw_axis_scan = false
local saw_affine_nd_layout = false
for _, item in ipairs(nd_artifact.artifacts) do
    local desc = item.instance.descriptor
    assert(tostring(pvm.classof(desc.producer.shape)):match('StencilProduceRangeND'), 'lln.range_nd should project to a RangeND producer')
    nd_sinks[tostring(pvm.classof(desc.sink))] = true
    if tostring(pvm.classof(desc.sink)):match('StencilSinkScan') then
        saw_axis_scan = desc.sink.axis and desc.sink.axis.index == 2
    end
    for _, access in ipairs(desc.accesses or {}) do
        if tostring(pvm.classof(access.layout)):match('StencilLayoutAffineND') then saw_affine_nd_layout = true end
    end
end
assert(nd_sinks['Class(LalinStencil.StencilSinkStore)'], 'lln.range_nd copy should project to a store sink')
assert(nd_sinks['Class(LalinStencil.StencilSinkReduce)'], 'lln.range_nd fold should project to a reduce sink')
assert(nd_sinks['Class(LalinStencil.StencilSinkScan)'], 'lln.range_nd scan should project to a scan sink')
assert(saw_axis_scan, 'lln.range_nd scan should preserve explicit scan axis')
assert(saw_affine_nd_layout, 'column-major lln.range_nd index should project to StencilLayoutAffineND')
local nd_loaded = assert(loadfile(nd_artifact.path))()
local nd_src = ffi.new('int32_t[6]', { 1, 2, 3, 4, 5, 6 })
local nd_dst = ffi.new('int32_t[6]')
nd_loaded.nd_shape(nd_dst, nd_src, 2, 3, 6)
assert(nd_dst[0] == 1 and nd_dst[1] == 2 and nd_dst[2] == 3 and nd_dst[3] == 4 and nd_dst[4] == 5 and nd_dst[5] == 6, 'native lln.range_nd copy output')
assert(nd_loaded.nd_sum(nd_src, 2, 3, 6) == 21, 'native lln.range_nd fold output')
local nd_scan_dst = ffi.new('int32_t[6]')
nd_loaded.nd_scan_rows(nd_scan_dst, nd_src, 2, 3, 6)
assert(nd_scan_dst[0] == 1 and nd_scan_dst[1] == 3 and nd_scan_dst[2] == 6 and nd_scan_dst[3] == 4 and nd_scan_dst[4] == 9 and nd_scan_dst[5] == 15, 'native lln.range_nd axis scan output')
local nd3_src = ffi.new('int32_t[12]', { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 })
local nd3_dst = ffi.new('int32_t[12]')
nd_loaded.nd3_shape(nd3_dst, nd3_src, 2, 3, 2, 12)
assert(nd3_dst[0] == 1 and nd3_dst[5] == 6 and nd3_dst[11] == 12, 'native rank-3 lln.range_nd copy output')
local nd_step_start_src = ffi.new('int32_t[12]', { 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120 })
local nd_step_start_dst = ffi.new('int32_t[12]')
nd_loaded.nd_stepped_start_shape(nd_step_start_dst, nd_step_start_src, 12)
assert(nd_step_start_dst[0] == 10 and nd_step_start_dst[5] == 60 and nd_step_start_dst[11] == 120, 'native stepped-start lln.range_nd copy output')
local nd_col_dst = ffi.new('int32_t[6]')
nd_loaded.nd_column_major_store(nd_col_dst, nd_src, 6)
assert(nd_col_dst[0] == 1 and nd_col_dst[1] == 4 and nd_col_dst[2] == 2 and nd_col_dst[3] == 5 and nd_col_dst[4] == 3 and nd_col_dst[5] == 6, 'native column-major lln.range_nd store output')

local producer_head_source = [=[
return unit. NativeProducerHeadDSL {
  fn. tiled_copy { dst [ptr [i32]], src [ptr [i32]], h [index], w [index], n [index] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (src)(n), readonly(src),
      disjoint (dst)(src),
    },

    lln.loop { i, j } [lln.tiled_nd { axes = { { 0, h }, { 0, w } }, tiles = { 2, 2 } }] {
      set (dst[i * w + j])(src[i * w + j]),
    },
  },

  fn. window_copy { dst [ptr [i32]], src [ptr [i32]], n [index] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (src)(n), readonly(src),
      disjoint (dst)(src),
    },

    lln.loop { i } [lln.window_nd { axes = { { 0, n } }, windows = { { 1, 1, boundary = "clamp" } } }] {
      set (dst[i])(src[i]),
    },
  },
}
]=]

local producer_head_decl = assert(session:loadstring(producer_head_source, 'test_luajit_artifact_native_producer_heads.lua'))()
local producer_head_artifact = emit_mc_artifact(producer_head_decl, {
    path = 'target/test_artifacts/test_luajit_artifact_native_producer_heads.lua',
    name = 'NativeProducerHeadDSL',
    stem = 'test_luajit_artifact_native_producer_heads',
})
assert(#producer_head_artifact.artifacts == 2, 'tiled_nd and window_nd source heads should select stencil artifacts')
local saw_tiled_flow, saw_window_flow = false, false
for _, fact in ipairs(producer_head_artifact.facts.flow.domain_shapes or {}) do
    local name = tostring(pvm.classof(fact.shape))
    saw_tiled_flow = saw_tiled_flow or name:match('FlowDomainShapeTiledND') ~= nil
    saw_window_flow = saw_window_flow or name:match('FlowDomainShapeWindowND') ~= nil
end
assert(saw_tiled_flow, 'lln.tiled_nd should author a TiledND Flow domain fact')
assert(saw_window_flow, 'lln.window_nd should author a WindowND Flow domain fact')
local saw_tiled_stencil, saw_window_stencil = false, false
for _, item in ipairs(producer_head_artifact.artifacts) do
    local name = tostring(pvm.classof(item.instance.descriptor.producer.shape))
    saw_tiled_stencil = saw_tiled_stencil or name:match('StencilProduceTiledND') ~= nil
    saw_window_stencil = saw_window_stencil or name:match('StencilProduceWindowND') ~= nil
end
assert(saw_tiled_stencil, 'lln.tiled_nd should project to a TiledND stencil producer')
assert(saw_window_stencil, 'lln.window_nd should project to a WindowND stencil producer')
io.write('test_luajit_artifact_native_loop_dsl: ok\n')
