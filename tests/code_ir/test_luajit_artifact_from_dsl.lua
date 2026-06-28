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
return unit. CopyPatchRegression {
  fn. sum_i32 { xs [ptr [i32]], n [i32] } [i32] {
    requires { bounds (xs)(n), readonly(xs) },

    entry. start {} { jump. loop { i = 0, acc = 0 }, },

    block. loop { i [i32], acc [i32] } {
      when (i :lt (n)) {
        jump. body { i = i, acc = acc },
      },

      jump. done { acc = acc },
    },

    block. body { i [i32], acc [i32] } {
      jump. loop { i = i + 1, acc = acc + xs[i] },
    },

    block. done { acc [i32] } {
      ret (acc),
    },
  },

  fn. copy_i32 { dst [ptr [i32]], src [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (src)(n), readonly(src),
      disjoint (dst)(src),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[i])(src[i]),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. copy_i32_memmove { dst [ptr [i32]], src [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (src)(n), readonly(src),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[i])(src[i]),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. fill_i32 { dst [ptr [i32]], n [i32], value [i32] } [void] {
    requires { bounds (dst)(n), writeonly(dst) },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[i])(value),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. map_neg_i32 { dst [ptr [i32]], src [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (src)(n), readonly(src),
      disjoint (dst)(src),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[i])(-src[i]),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. zip_add_i32 { dst [ptr [i32]], lhs [ptr [i32]], rhs [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (lhs)(n), readonly(lhs),
      bounds (rhs)(n), readonly(rhs),
      disjoint (dst)(lhs), disjoint (dst)(rhs), disjoint (lhs)(rhs),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[i])(lhs[i] + rhs[i]),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. zip_fused_i32 { dst [ptr [i32]], lhs [ptr [i32]], rhs [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (lhs)(n), readonly(lhs),
      bounds (rhs)(n), readonly(rhs),
      disjoint (dst)(lhs), disjoint (dst)(rhs), disjoint (lhs)(rhs),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[i])((lhs[i] + rhs[i]) * (lhs[i] - rhs[i])),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. select_pos_i32 { dst [ptr [i32]], lhs [ptr [i32]], rhs [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (lhs)(n), readonly(lhs),
      bounds (rhs)(n), readonly(rhs),
      disjoint (dst)(lhs), disjoint (dst)(rhs), disjoint (lhs)(rhs),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[i])(select (lhs[i] :gt (0))(lhs[i])(rhs[i])),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. bitmix_i32 { dst [ptr [i32]], lhs [ptr [i32]], rhs [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (lhs)(n), readonly(lhs),
      bounds (rhs)(n), readonly(rhs),
      disjoint (dst)(lhs), disjoint (dst)(rhs), disjoint (lhs)(rhs),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[i])(bxor (shl (lhs[i] % rhs[i])(1))(bor (band (lhs[i])(15))(rhs[i]))),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. minmax_i32 { dst [ptr [i32]], lhs [ptr [i32]], rhs [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (lhs)(n), readonly(lhs),
      bounds (rhs)(n), readonly(rhs),
      disjoint (dst)(lhs), disjoint (dst)(rhs), disjoint (lhs)(rhs),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[i])(max (min (lhs[i])(rhs[i]))(0)),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. cast_i32_f64 { dst [ptr [f64]], src [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (src)(n), readonly(src),
      disjoint (dst)(src),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[i])(as [f64] (src[i])),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. compare_gt_zero_i32 { dst [ptr [bool]], src [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (src)(n), readonly(src),
      disjoint (dst)(src),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[i])(src[i] :gt (0)),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. zip_compare_lt_i32 { dst [ptr [bool]], lhs [ptr [i32]], rhs [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (lhs)(n), readonly(lhs),
      bounds (rhs)(n), readonly(rhs),
      disjoint (dst)(lhs), disjoint (dst)(rhs), disjoint (lhs)(rhs),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[i])(lhs[i] :lt (rhs[i])),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. gather_i32 { dst [ptr [i32]], src [ptr [i32]], idx [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (src)(n), readonly(src),
      bounds (idx)(n), readonly(idx),
      disjoint (dst)(src), disjoint (dst)(idx), disjoint (src)(idx),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[i])(src[idx[i]]),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. scatter_i32 { dst [ptr [i32]], src [ptr [i32]], idx [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (src)(n), readonly(src),
      bounds (idx)(n), readonly(idx),
      disjoint (dst)(src), disjoint (dst)(idx), disjoint (src)(idx),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[idx[i]])(src[i]),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. scatter_reduce_add_i32 { dst [ptr [i32]], src [ptr [i32]], idx [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n),
      bounds (src)(n), readonly(src),
      bounds (idx)(n), readonly(idx),
      disjoint (dst)(src), disjoint (dst)(idx), disjoint (src)(idx),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[idx[i]])(dst[idx[i]] + src[i]),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. scatter_reduce_add_zip_i32 { dst [ptr [i32]], src [ptr [i32]], rhs [ptr [i32]], idx [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n),
      bounds (src)(n), readonly(src),
      bounds (rhs)(n), readonly(rhs),
      bounds (idx)(n), readonly(idx),
      disjoint (dst)(src), disjoint (dst)(rhs), disjoint (dst)(idx),
      disjoint (src)(rhs), disjoint (src)(idx), disjoint (rhs)(idx),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[idx[i]])(dst[idx[i]] + (src[i] + rhs[i])),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. scatter_reduce_mul_i32 { dst [ptr [i32]], src [ptr [i32]], idx [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n),
      bounds (src)(n), readonly(src),
      bounds (idx)(n), readonly(idx),
      disjoint (dst)(src), disjoint (dst)(idx), disjoint (src)(idx),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[idx[i]])(dst[idx[i]] * src[i]),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. scatter_reduce_and_i32 { dst [ptr [i32]], src [ptr [i32]], idx [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n),
      bounds (src)(n), readonly(src),
      bounds (idx)(n), readonly(idx),
      disjoint (dst)(src), disjoint (dst)(idx), disjoint (src)(idx),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[idx[i]])(band (dst[idx[i]])(src[i])),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. scatter_reduce_or_i32 { dst [ptr [i32]], src [ptr [i32]], idx [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n),
      bounds (src)(n), readonly(src),
      bounds (idx)(n), readonly(idx),
      disjoint (dst)(src), disjoint (dst)(idx), disjoint (src)(idx),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[idx[i]])(bor (dst[idx[i]])(src[i])),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. scatter_reduce_xor_i32 { dst [ptr [i32]], src [ptr [i32]], idx [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n),
      bounds (src)(n), readonly(src),
      bounds (idx)(n), readonly(idx),
      disjoint (dst)(src), disjoint (dst)(idx), disjoint (src)(idx),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[idx[i]])(bxor (dst[idx[i]])(src[i])),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. scatter_reduce_min_i32 { dst [ptr [i32]], src [ptr [i32]], idx [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n),
      bounds (src)(n), readonly(src),
      bounds (idx)(n), readonly(idx),
      disjoint (dst)(src), disjoint (dst)(idx), disjoint (src)(idx),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[idx[i]])(min (dst[idx[i]])(src[i])),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. scatter_reduce_max_i32 { dst [ptr [i32]], src [ptr [i32]], idx [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n),
      bounds (src)(n), readonly(src),
      bounds (idx)(n), readonly(idx),
      disjoint (dst)(src), disjoint (dst)(idx), disjoint (src)(idx),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[idx[i]])(max (dst[idx[i]])(src[i])),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. in_place_neg_i32 { dst [ptr [i32]], n [i32] } [void] {
    requires { bounds (dst)(n) },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[i])(-dst[i]),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. count_gt_zero_i32 { xs [ptr [i32]], n [i32] } [i32] {
    requires { bounds (xs)(n), readonly(xs) },

    entry. start {} { jump. loop { i = 0, acc = 0 }, },

    block. loop { i [i32], acc [i32] } {
      when (i :lt (n)) {
        jump. body { i = i, acc = acc },
      },

      jump. done { acc = acc },
    },

    block. body { i [i32], acc [i32] } {
      jump. loop { i = i + 1, acc = acc + as [i32] (xs[i] :gt (0)) },
    },

    block. done { acc [i32] } {
      ret (acc),
    },
  },

  fn. sum_neg_i32 { xs [ptr [i32]], n [i32] } [i32] {
    requires { bounds (xs)(n), readonly(xs) },

    entry. start {} { jump. loop { i = 0, acc = 0 }, },

    block. loop { i [i32], acc [i32] } {
      when (i :lt (n)) {
        jump. body { i = i, acc = acc },
      },

      jump. done { acc = acc },
    },

    block. body { i [i32], acc [i32] } {
      jump. loop { i = i + 1, acc = acc + -xs[i] },
    },

    block. done { acc [i32] } {
      ret (acc),
    },
  },

  fn. sum_zip_i32 { lhs [ptr [i32]], rhs [ptr [i32]], n [i32] } [i32] {
    requires {
      bounds (lhs)(n), readonly(lhs),
      bounds (rhs)(n), readonly(rhs),
      disjoint (lhs)(rhs),
    },

    entry. start {} { jump. loop { i = 0, acc = 0 }, },

    block. loop { i [i32], acc [i32] } {
      when (i :lt (n)) {
        jump. body { i = i, acc = acc },
      },

      jump. done { acc = acc },
    },

    block. body { i [i32], acc [i32] } {
      jump. loop { i = i + 1, acc = acc + (lhs[i] + rhs[i]) },
    },

    block. done { acc [i32] } {
      ret (acc),
    },
  },

  fn. scan_sum_i32 { dst [ptr [i32]], xs [ptr [i32]], n [i32] } [i32] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (xs)(n), readonly(xs),
      disjoint (dst)(xs),
    },

    entry. start {} { jump. loop { i = 0, acc = 0 }, },

    block. loop { i [i32], acc [i32] } {
      when (i :lt (n)) {
        jump. body { i = i, acc = acc },
      },

      jump. done { acc = acc },
    },

    block. body { i [i32], acc [i32] } {
      let. nxt [i32] (acc + xs[i]),
      set (dst[i])(nxt),
      jump. loop { i = i + 1, acc = nxt },
    },

    block. done { acc [i32] } {
      ret (acc),
    },
  },

  fn. find_gt_zero_i32 { xs [ptr [i32]], n [i32] } [i32] {
    requires { bounds (xs)(n), readonly(xs) },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done { pos = -1 },
    },

    block. body { i [i32] } {
      when (xs[i] :gt (0)) {
        jump. done { pos = i },
      },

      jump. loop { i = i + 1 },
    },

    block. done { pos [i32] } {
      ret (pos),
    },
  },

  fn. partition_gt_zero_i32 { dst [ptr [i32]], xs [ptr [i32]], n [i32] } [i32] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (xs)(n), readonly(xs),
      disjoint (dst)(xs),
    },

    entry. start {} { jump. pos_loop { i = 0, out = 0 }, },

    block. pos_loop { i [i32], out [i32] } {
      when (i :lt (n)) {
        jump. pos_body { i = i, out = out },
      },

      jump. neg_loop { j = 0, out = out },
    },

    block. pos_body { i [i32], out [i32] } {
      when (xs[i] :gt (0)) {
        set (dst[out])(xs[i]),
        jump. pos_loop { i = i + 1, out = out + 1 },
      },

      jump. pos_loop { i = i + 1, out = out },
    },

    block. neg_loop { j [i32], out [i32] } {
      when (j :lt (n)) {
        jump. neg_body { j = j, out = out },
      },

      jump. done { split = out },
    },

    block. neg_body { j [i32], out [i32] } {
      when (xs[j] :gt (0)) {
        jump. neg_loop { j = j + 1, out = out },
      },

      set (dst[out])(xs[j]),
      jump. neg_loop { j = j + 1, out = out + 1 },
    },

    block. done { split [i32] } {
      ret (split),
    },
  },

}
]=]

local session = lalin.use { scope = 'env' }
local decl = assert(session:loadstring(source, 'test_luajit_artifact_from_dsl.lua'))()
local plan = lalin.plan_luajit_artifact(decl, {
    name = 'CopyPatchRegression',
    stem = 'test_luajit_artifact_from_dsl',
})
local bank = assert(plan.backend.build_mc_bank(plan.artifacts, { stem = 'test_luajit_artifact_from_dsl' }))
local artifact = lalin.emit_luajit_plan_artifact(plan, {
    path = 'target/test_artifacts/test_luajit_artifact_from_dsl.lua',
    name = 'CopyPatchRegression',
    stem = 'test_luajit_artifact_from_dsl',
    mc_bank = bank,
})

assert(artifact.kind == 'LuaJITSourceArtifact')
assert(#artifact.artifacts == 30, 'expected selected stencil artifact for each DSL loop')
assert(artifact.source:match('__ml_check_stencil_target'), 'expected generated target guard')

local expected_counts = {
    reduce = 1,
    copy = 1,
    copy_memmove = 1,
    fill = 1,
    map = 2,
    zip_map = 3,
    select = 2,
    cast = 1,
    compare = 1,
    zip_compare = 1,
    gather = 1,
    scatter = 1,
    scatter_reduce = 8,
    apply_reduce = 1,
    map_reduce = 1,
    zip_reduce = 1,
    scan = 1,
    find = 1,
    partition = 1,
}
local function selected_label(descriptor)
    local function class_name(v)
        return tostring(pvm.classof(v)):match('Class%((.-)%)')
    end
    local function access_named(name)
        for _, access in ipairs(descriptor.accesses or {}) do
            if access.name == name then return access end
        end
        return nil
    end
    local sink_kind = class_name(descriptor.sink)
    local expr = descriptor.body.expr
    local expr_kind = class_name(expr)
    local function layout_kind(access)
        return access and class_name(access.layout) or nil
    end
    local function has_indexed_read()
        for _, access in ipairs(descriptor.accesses or {}) do
            if class_name(access.role) == 'LalinStencil.StencilAccessRead'
                and layout_kind(access) == 'LalinStencil.StencilLayoutIndexed' then return true end
        end
        return false
    end
    local function read_count()
        local n = 0
        for _, access in ipairs(descriptor.accesses or {}) do
            if class_name(access.role) == 'LalinStencil.StencilAccessRead'
                and layout_kind(access) ~= 'LalinStencil.StencilLayoutScalar' then n = n + 1 end
        end
        return n
    end
    if sink_kind == 'LalinStencil.StencilSinkScan' then return 'scan' end
    if sink_kind == 'LalinStencil.StencilSinkScatterReduce' then return 'scatter_reduce' end
    if sink_kind == 'LalinStencil.StencilSinkReduce' then
        local mode_kind = class_name(descriptor.sink.mode)
        if mode_kind == 'LalinStencil.StencilReduceFind' then return 'find' end
        if expr_kind == 'LalinStencil.StencilApplyCast' then return 'apply_reduce' end
        if expr_kind == 'LalinStencil.StencilApplyUnary' then return 'map_reduce' end
        if expr_kind == 'LalinStencil.StencilApplyBinary' then return 'zip_reduce' end
        return 'reduce'
    end
    if sink_kind == 'LalinStencil.StencilSinkStore' then
        local mode_kind = class_name(descriptor.sink.mode)
        if mode_kind == 'LalinStencil.StencilStoreCopy' then
            if tostring(descriptor.sink.mode.semantics):match('StencilCopyMemMove') then return 'copy_memmove' end
            return 'copy'
        end
        if mode_kind == 'LalinStencil.StencilStoreScatter' then return 'scatter' end
        if mode_kind == 'LalinStencil.StencilStorePartition' then return 'partition' end
        if expr_kind == 'LalinStencil.StencilApplyInput' then
            local access = access_named(expr.access.name)
            if access and class_name(access.layout) == 'LalinStencil.StencilLayoutScalar' then return 'fill' end
            if has_indexed_read() then return 'gather' end
            return 'map'
        end
        if expr_kind == 'LalinStencil.StencilApplyUnary' then
            return 'map'
        end
        if expr_kind == 'LalinStencil.StencilApplyBinary' then return 'zip_map' end
        if expr_kind == 'LalinStencil.StencilApplyCast' then return 'cast' end
        if expr_kind == 'LalinStencil.StencilApplyPredicate' then return 'compare' end
        if expr_kind == 'LalinStencil.StencilApplyCompare' then
            if read_count() == 1 then return 'compare' end
            return 'zip_compare'
        end
        if expr_kind == 'LalinStencil.StencilApplySelect' then return 'select' end
        return 'map'
    end
    return nil
end
local seen = {}
local nested_apply_binary = 0
for _, selected in ipairs(artifact.artifacts) do
    local descriptor = selected.instance.descriptor
    local label = selected_label(descriptor)
    assert(label ~= nil, 'unexpected selected stencil descriptor ' .. tostring(pvm.classof(descriptor)))
    if tostring(pvm.classof(descriptor.body.expr)):match('StencilApplyBinary')
        and tostring(pvm.classof(descriptor.body.expr.left)):match('StencilApplyBinary')
        and tostring(pvm.classof(descriptor.body.expr.right)):match('StencilApplyBinary') then
        nested_apply_binary = nested_apply_binary + 1
    end
    if label == 'find' or label == 'partition' or label == 'scatter_reduce' then
        assert(tostring(selected.instance.schedule):match('StencilScheduleScalar'), label .. ' should carry a scalar ordered-control stencil schedule')
    else
        assert(tostring(selected.instance.schedule):match('StencilScheduleAutoVector'), label .. ' should carry an auto-vector stencil schedule')
    end
    seen[label] = (seen[label] or 0) + 1
end
for label, count in pairs(expected_counts) do
    assert(seen[label] == count, 'expected ' .. tostring(count) .. ' selected stencil artifact(s) for ' .. label .. ', got ' .. tostring(seen[label] or 0))
end
assert(nested_apply_binary >= 2, 'expected nested ApplyN binary bodies from fused source expressions')

local loaded = assert(loadfile(artifact.path))()
local arr = ffi.new('int32_t[6]', { 1, 2, 3, 4, 5, 6 })
assert(loaded.sum_i32(arr, 6) == 21)

local src = ffi.new('int32_t[6]', { 5, -3, 8, 0, 9, 2 })
local rhs = ffi.new('int32_t[6]', { 1, 10, -8, 7, 4, 11 })
local rhs_pos = ffi.new('int32_t[6]', { 2, 3, 4, 5, 6, 7 })
local idx = ffi.new('int32_t[6]', { 2, 0, 4, 1, 5, 3 })
local out = ffi.new('int32_t[6]')
local out_bool = ffi.new('uint8_t[6]')
local out_f64 = ffi.new('double[6]')

loaded.copy_i32(out, src, 6)
for i = 0, 5 do assert(out[i] == src[i], 'copy mismatch at ' .. tostring(i)) end

local move = ffi.new('int32_t[7]', { 1, 2, 3, 4, 5, 6, 0 })
loaded.copy_i32_memmove(move + 1, move, 6)
for i = 0, 6 do
    local expect = ({ 1, 1, 2, 3, 4, 5, 6 })[i + 1]
    assert(move[i] == expect, 'memmove copy mismatch at ' .. tostring(i))
end

loaded.fill_i32(out, 6, 77)
for i = 0, 5 do assert(out[i] == 77, 'fill mismatch at ' .. tostring(i)) end

loaded.map_neg_i32(out, src, 6)
for i = 0, 5 do assert(out[i] == -src[i], 'map mismatch at ' .. tostring(i)) end

loaded.zip_add_i32(out, src, rhs, 6)
for i = 0, 5 do assert(out[i] == src[i] + rhs[i], 'zip mismatch at ' .. tostring(i)) end

loaded.zip_fused_i32(out, src, rhs, 6)
for i = 0, 5 do
    assert(out[i] == (src[i] + rhs[i]) * (src[i] - rhs[i]), 'zip fused mismatch at ' .. tostring(i))
end

loaded.select_pos_i32(out, src, rhs, 6)
for i = 0, 5 do
    assert(out[i] == (src[i] > 0 and src[i] or rhs[i]), 'select mismatch at ' .. tostring(i))
end

loaded.bitmix_i32(out, src, rhs_pos, 6)
local bit = require('bit')
for i = 0, 5 do
    local rem = src[i] % rhs_pos[i]
    local expect = bit.bxor(bit.lshift(rem, 1), bit.bor(bit.band(src[i], 15), rhs_pos[i]))
    assert(out[i] == expect, 'bitmix mismatch at ' .. tostring(i))
end

loaded.minmax_i32(out, src, rhs, 6)
for i = 0, 5 do
    local m = src[i] <= rhs[i] and src[i] or rhs[i]
    local expect = m >= 0 and m or 0
    assert(out[i] == expect, 'minmax mismatch at ' .. tostring(i))
end

loaded.cast_i32_f64(out_f64, src, 6)
for i = 0, 5 do assert(out_f64[i] == src[i], 'cast mismatch at ' .. tostring(i)) end

loaded.compare_gt_zero_i32(out_bool, src, 6)
for i = 0, 5 do assert(out_bool[i] == (src[i] > 0 and 1 or 0), 'compare mismatch at ' .. tostring(i)) end

loaded.zip_compare_lt_i32(out_bool, src, rhs, 6)
for i = 0, 5 do assert(out_bool[i] == (src[i] < rhs[i] and 1 or 0), 'zip compare mismatch at ' .. tostring(i)) end

loaded.gather_i32(out, src, idx, 6)
for i = 0, 5 do assert(out[i] == src[idx[i]], 'gather mismatch at ' .. tostring(i)) end

for i = 0, 5 do out[i] = 0 end
loaded.scatter_i32(out, src, idx, 6)
for i = 0, 5 do
    local found = false
    for j = 0, 5 do if idx[j] == i then found = out[i] == src[j] end end
    assert(found, 'scatter mismatch at ' .. tostring(i))
end
for i = 0, 5 do out[i] = 0 end
local dup_idx = ffi.new('int32_t[6]', { 0, 2, 0, 2, 2, 5 })
loaded.scatter_reduce_add_i32(out, src, dup_idx, 6)
assert(out[0] == 13 and out[1] == 0 and out[2] == 6 and out[3] == 0 and out[4] == 0 and out[5] == 2, 'scatter-reduce add mismatch')

for i = 0, 5 do out[i] = 0 end
loaded.scatter_reduce_add_zip_i32(out, src, rhs, dup_idx, 6)
assert(out[0] == 6 and out[1] == 0 and out[2] == 27 and out[3] == 0 and out[4] == 0 and out[5] == 13, 'scatter-reduce zip add mismatch')

for i = 0, 5 do out[i] = 1 end
loaded.scatter_reduce_mul_i32(out, src, dup_idx, 6)
assert(out[0] == 40 and out[1] == 1 and out[2] == 0 and out[3] == 1 and out[4] == 1 and out[5] == 2, 'scatter-reduce mul mismatch')

for i = 0, 5 do out[i] = -1 end
loaded.scatter_reduce_and_i32(out, src, dup_idx, 6)
assert(out[0] == 0 and out[1] == -1 and out[2] == 0 and out[3] == -1 and out[4] == -1 and out[5] == 2, 'scatter-reduce and mismatch')

for i = 0, 5 do out[i] = 0 end
loaded.scatter_reduce_or_i32(out, src, dup_idx, 6)
assert(out[0] == bit.bor(5, 8) and out[1] == 0 and out[2] == bit.bor(bit.bor(-3, 0), 9) and out[3] == 0 and out[4] == 0 and out[5] == 2, 'scatter-reduce or mismatch')

for i = 0, 5 do out[i] = 0 end
loaded.scatter_reduce_xor_i32(out, src, dup_idx, 6)
assert(out[0] == bit.bxor(5, 8) and out[1] == 0 and out[2] == bit.bxor(bit.bxor(-3, 0), 9) and out[3] == 0 and out[4] == 0 and out[5] == 2, 'scatter-reduce xor mismatch')

for i = 0, 5 do out[i] = 2147483647 end
loaded.scatter_reduce_min_i32(out, src, dup_idx, 6)
assert(out[0] == 5 and out[1] == 2147483647 and out[2] == -3 and out[3] == 2147483647 and out[4] == 2147483647 and out[5] == 2, 'scatter-reduce min mismatch')

for i = 0, 5 do out[i] = -2147483648 end
loaded.scatter_reduce_max_i32(out, src, dup_idx, 6)
assert(out[0] == 8 and out[1] == -2147483648 and out[2] == 9 and out[3] == -2147483648 and out[4] == -2147483648 and out[5] == 2, 'scatter-reduce max mismatch')

local inplace = ffi.new('int32_t[6]', { 5, -3, 8, 0, 9, 2 })
loaded.in_place_neg_i32(inplace, 6)
for i = 0, 5 do assert(inplace[i] == -src[i], 'in-place map mismatch at ' .. tostring(i)) end

assert(loaded.count_gt_zero_i32(src, 6) == 4, 'count mismatch')
assert(loaded.sum_neg_i32(src, 6) == -21, 'map reduce mismatch')
assert(loaded.sum_zip_i32(src, rhs, 6) == 46, 'zip reduce mismatch')

loaded.scan_sum_i32(out, arr, 6)
local running = 0
for i = 0, 5 do
    running = running + arr[i]
    assert(out[i] == running, 'scan mismatch at ' .. tostring(i))
end
assert(running == 21, 'scan final mismatch')

assert(loaded.find_gt_zero_i32(src, 6) == 0, 'find mismatch')

local part = ffi.new('int32_t[6]')
assert(loaded.partition_gt_zero_i32(part, src, 6) == 4, 'partition split mismatch')
assert(part[0] == 5 and part[1] == 8 and part[2] == 9 and part[3] == 2 and part[4] == -3 and part[5] == 0, 'partition order mismatch')

io.write('test_luajit_artifact_from_dsl: ok\n')
