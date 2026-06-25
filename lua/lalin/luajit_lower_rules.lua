local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.luajit_lower_rules ~= nil then return T._lalin_api_cache.luajit_lower_rules end

    local lalin = require("lalin")
    local llb = require("llb")
    local Llisle = require("llisle")
    local RuleApi = require("lalin.llisle_rule_api")
    local env = lalin.family.env { scope = "env", base = _G }
    Llisle.use { scope = "env", target = env, base = env, global = false }
    local llisle = env.llisle
    local LuaJITKernelLoweringInput = llb.symbol("LuaJITKernelLoweringInput")
    local LuaJITKernelLoweringSelection = llb.symbol("LuaJITKernelLoweringSelection")
    local LuaJITSkeletonLoweringInput = llb.symbol("LuaJITSkeletonLoweringInput")
    local LuaJITSkeletonLoweringSelection = llb.symbol("LuaJITSkeletonLoweringSelection")
    local kernel = llb.symbol("kernel")
    local skeleton = llb.symbol("skeleton")
    local selection = llb.symbol("selection")
    local kernel_lowering = llb.symbol("kernel_lowering")
    local stencil_reduce = llb.symbol("stencil_reduce")
    local stencil_store = llb.symbol("stencil_store")
    local stencil_skeleton = llb.symbol("stencil_skeleton")
    local no_plan = llb.symbol("no_plan")
    local skeleton_scan = llb.symbol("skeleton_scan")
    local skeleton_find = llb.symbol("skeleton_find")
    local skeleton_partition = llb.symbol("skeleton_partition")
    local skeleton_copy = llb.symbol("skeleton_copy")
    local function build_kernel_lowering(fields) return fields end

    local function build_rules()
    return llisle {
  constructor. kernel_lowering [build_kernel_lowering],

  relation. select_kernel_lowering {
    input { kernel [LuaJITKernelLoweringInput] },
    output { selection [LuaJITKernelLoweringSelection] },
    strategy {
      select. best_cost,
      ambiguity. error,
      coverage. complete,
    },
  },

  relation. select_skeleton_lowering {
    input { skeleton [LuaJITSkeletonLoweringInput] },
    output { selection [LuaJITSkeletonLoweringSelection] },
    strategy {
      select. best_cost,
      ambiguity. error,
      coverage. complete,
    },
  },

  rule. stencil_reduce {
    llisle.select_kernel_lowering { kernel = P. kernel },
    when {
      (P. kernel.loop_plan :eq (true))
        * (P. kernel.owns_loop :eq (true))
        * (P. kernel.planned :eq (true))
        * (P. kernel.has_reduce_provider :eq (true))
        * (P. kernel.counted_positive :eq (true))
        * (P. kernel.result_reduction :eq (true))
        * (P. kernel.returns_reduction :eq (true))
        * (P. kernel.stencil_skeleton_ready :eq (false))
        * (P. kernel.stencil_reduce_ready :eq (true)),
    },
    cost (20),
    run {
      ret { selection = kernel_lowering { kind = stencil_reduce } },
    },
  },

  rule. stencil_skeleton {
    llisle.select_kernel_lowering { kernel = P. kernel },
    when {
      (P. kernel.loop_plan :eq (true))
        * (P. kernel.owns_loop :eq (true))
        * (P. kernel.planned :eq (true))
        * (P. kernel.has_skeleton_provider :eq (true))
        * (P. kernel.counted_positive :eq (true))
        * (P. kernel.stencil_skeleton_ready :eq (true)),
    },
    cost (30),
    run {
      ret { selection = kernel_lowering { kind = stencil_skeleton } },
    },
  },

  rule. stencil_store {
    llisle.select_kernel_lowering { kernel = P. kernel },
    when {
      (P. kernel.loop_plan :eq (true))
        * (P. kernel.owns_loop :eq (true))
        * (P. kernel.planned :eq (true))
        * (P. kernel.has_store_provider :eq (true))
        * (P. kernel.counted_positive :eq (true))
        * (P. kernel.returns_void :eq (true))
        * (P. kernel.single_store :eq (true))
        * (P. kernel.store_dst_base :eq (true))
        * (P. kernel.stencil_skeleton_ready :eq (false))
        * (P. kernel.stencil_store_ready :eq (true)),
    },
    cost (10),
    run {
      ret { selection = kernel_lowering { kind = stencil_store } },
    },
  },

  rule. no_kernel_lowering {
    llisle.select_kernel_lowering { kernel = P. kernel },
    when {
      P. kernel.any_ready_lowering :eq (false),
    },
    cost (100),
    run {
      ret {
        selection = kernel_lowering {
          kind = no_plan,
          reason = P. kernel.reject_reason,
        },
      },
    },
  },

  rule. skeleton_scan {
    llisle.select_skeleton_lowering { skeleton = P. skeleton },
    when {
      P. skeleton.scan_ready :eq (true),
    },
    cost (0),
    run {
      ret {
        selection = kernel_lowering {
          kind = skeleton_scan,
          planned = P. skeleton.scan_plan,
        },
      },
    },
  },

  rule. skeleton_find {
    llisle.select_skeleton_lowering { skeleton = P. skeleton },
    when {
      (P. skeleton.scan_ready :eq (false))
        * (P. skeleton.find_ready :eq (true)),
    },
    cost (10),
    run {
      ret {
        selection = kernel_lowering {
          kind = skeleton_find,
          planned = P. skeleton.find_plan,
        },
      },
    },
  },

  rule. skeleton_partition {
    llisle.select_skeleton_lowering { skeleton = P. skeleton },
    when {
      (P. skeleton.scan_ready :eq (false))
        * (P. skeleton.find_ready :eq (false))
        * (P. skeleton.partition_ready :eq (true)),
    },
    cost (20),
    run {
      ret {
        selection = kernel_lowering {
          kind = skeleton_partition,
          planned = P. skeleton.partition_plan,
        },
      },
    },
  },

  rule. skeleton_copy {
    llisle.select_skeleton_lowering { skeleton = P. skeleton },
    when {
      (P. skeleton.scan_ready :eq (false))
        * (P. skeleton.find_ready :eq (false))
        * (P. skeleton.partition_ready :eq (false))
        * (P. skeleton.copy_ready :eq (true)),
    },
    cost (30),
    run {
      ret {
        selection = kernel_lowering {
          kind = skeleton_copy,
          planned = P. skeleton.copy_plan,
        },
      },
    },
  },

  rule. skeleton_no_plan {
    llisle.select_skeleton_lowering { skeleton = P. skeleton },
    when {
      (P. skeleton.scan_ready :eq (false))
        * (P. skeleton.find_ready :eq (false))
        * (P. skeleton.partition_ready :eq (false))
        * (P. skeleton.copy_ready :eq (false)),
    },
    cost (100),
    run {
      ret {
        selection = kernel_lowering {
          kind = no_plan,
          reason = P. skeleton.reject_reason,
        },
      },
    },
  },
}
    end
    if setfenv then setfenv(build_rules, env) end
    local rules = build_rules()

    local engine = Llisle.compile(rules)

    local api = RuleApi.new(rules, engine, {
      kind = {
        stencil_reduce = "stencil_reduce",
        stencil_store = "stencil_store",
        stencil_skeleton = "stencil_skeleton",
        no_plan = "no_plan",
        skeleton_scan = "skeleton_scan",
        skeleton_find = "skeleton_find",
        skeleton_partition = "skeleton_partition",
        skeleton_copy = "skeleton_copy",
      },
    })

    T._lalin_api_cache.luajit_lower_rules = api
    return api
end

return bind_context
