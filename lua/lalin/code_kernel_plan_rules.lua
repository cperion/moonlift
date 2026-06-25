local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.code_kernel_plan_rules ~= nil then return T._lalin_api_cache.code_kernel_plan_rules end

    local lalin = require("lalin")
    local llb = require("llb")
    local Llisle = require("llisle")
    local RuleApi = require("lalin.llisle_rule_api")
    local env = lalin.family.env { scope = "env", base = _G }
    Llisle.use { scope = "env", target = env, base = env, global = false }
    local llisle = env.llisle
    local KernelLoopPlanInput = llb.symbol("KernelLoopPlanInput")
    local KernelLoopPlanSelection = llb.symbol("KernelLoopPlanSelection")
    local loop = llb.symbol("loop")
    local selection = llb.symbol("selection")
    local kernel_plan = llb.symbol("kernel_plan")
    local no_plan = llb.symbol("no_plan")
    local planned = llb.symbol("planned")
    local closed_form = llb.symbol("closed_form")
    local reduction = llb.symbol("reduction")
    local skeleton = llb.symbol("skeleton")
    local original_control = llb.symbol("original_control")
    local function build_kernel_plan(fields) return fields end

    local function build_rules()
    return llisle {
  constructor. kernel_plan [build_kernel_plan],

  relation. select_loop_kernel_plan {
    input { loop [KernelLoopPlanInput] },
    output { selection [KernelLoopPlanSelection] },
    strategy {
      select. best_cost,
      ambiguity. error,
      coverage. complete,
    },
  },

  rule. no_counted_domain {
    llisle.select_loop_kernel_plan { loop = P. loop },
    when {
      P. loop.counted :eq (false),
    },
    cost (0),
    run {
      ret {
        selection = kernel_plan {
          kind = no_plan,
          rejects = P. loop.not_counted_rejects,
        },
      },
    },
  },

  rule. no_graph_owner {
    llisle.select_loop_kernel_plan { loop = P. loop },
    when {
      (P. loop.counted :eq (true))
        * (P. loop.has_func_id :eq (false)),
    },
    cost (0),
    run {
      ret {
        selection = kernel_plan {
          kind = no_plan,
          rejects = P. loop.no_owner_rejects,
        },
      },
    },
  },

  rule. rejected_loop {
    llisle.select_loop_kernel_plan { loop = P. loop },
    when {
      (P. loop.counted :eq (true))
        * (P. loop.has_func_id :eq (true))
        * (P. loop.has_rejects :eq (true)),
    },
    cost (0),
    run {
      ret {
        selection = kernel_plan {
          kind = no_plan,
          rejects = P. loop.rejects,
        },
      },
    },
  },

  rule. planned_closed_form {
    llisle.select_loop_kernel_plan { loop = P. loop },
    when {
      (P. loop.counted :eq (true))
        * (P. loop.has_func_id :eq (true))
        * (P. loop.has_func :eq (true))
        * (P. loop.has_rejects :eq (false))
        * (P. loop.has_closed_form :eq (true)),
    },
    cost (0),
    run {
      ret {
        selection = kernel_plan {
          kind = planned,
          result_kind = closed_form,
          closed_form = P. loop.closed_form,
          add_trip_unknown_proof = P. loop.closed_form_trip_unknown,
        },
      },
    },
  },

  rule. planned_reduction {
    llisle.select_loop_kernel_plan { loop = P. loop },
    when {
      (P. loop.counted :eq (true))
        * (P. loop.has_func_id :eq (true))
        * (P. loop.has_func :eq (true))
        * (P. loop.has_rejects :eq (false))
        * (P. loop.has_closed_form :eq (false))
        * (P. loop.has_reduction :eq (true)),
    },
    cost (10),
    run {
      ret {
        selection = kernel_plan {
          kind = planned,
          result_kind = reduction,
          reduction = P. loop.reduction,
          add_trip_unknown_proof = false,
        },
      },
    },
  },

  rule. planned_skeleton_result {
    llisle.select_loop_kernel_plan { loop = P. loop },
    when {
      (P. loop.counted :eq (true))
        * (P. loop.has_func_id :eq (true))
        * (P. loop.has_func :eq (true))
        * (P. loop.has_rejects :eq (false))
        * (P. loop.has_closed_form :eq (false))
        * (P. loop.has_reduction :eq (false))
        * (P. loop.has_skeleton_result :eq (true)),
    },
    cost (15),
    run {
      ret {
        selection = kernel_plan {
          kind = planned,
          result_kind = skeleton,
          skeleton_result = P. loop.skeleton_result,
          add_trip_unknown_proof = false,
        },
      },
    },
  },

  rule. planned_original_control {
    llisle.select_loop_kernel_plan { loop = P. loop },
    when {
      (P. loop.counted :eq (true))
        * (P. loop.has_func_id :eq (true))
        * (P. loop.has_func :eq (true))
        * (P. loop.has_rejects :eq (false))
        * (P. loop.has_closed_form :eq (false))
        * (P. loop.has_reduction :eq (false))
        * (P. loop.has_skeleton_result :eq (false)),
    },
    cost (20),
    run {
      ret {
        selection = kernel_plan {
          kind = planned,
          result_kind = original_control,
          add_trip_unknown_proof = false,
        },
      },
    },
  },
}
    end
    if setfenv then setfenv(build_rules, env) end
    local rules = build_rules()

    local engine = Llisle.compile(rules)

    local api = RuleApi.new(rules, engine)

    T._lalin_api_cache.code_kernel_plan_rules = api
    return api
end

return bind_context
