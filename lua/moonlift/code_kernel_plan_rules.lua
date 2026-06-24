local function bind_context(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.code_kernel_plan_rules ~= nil then return T._moonlift_api_cache.code_kernel_plan_rules end

    local moon = require("moonlift")
    local llb = require("llb")
    local Llisle = require("llisle")
    local env = moon.family.env { scope = "env", base = _G }
    Llisle.use { scope = "env", target = env, base = env, global = false }
    local llisle = env.llisle
    local KernelLoopPlanCandidate = llb.symbol("KernelLoopPlanCandidate")
    local KernelLoopPlanSelection = llb.symbol("KernelLoopPlanSelection")
    local candidate = llb.symbol("candidate")
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
    input { candidate [KernelLoopPlanCandidate] },
    output { selection [KernelLoopPlanSelection] },
    strategy {
      select. best_cost,
      ambiguity. error,
      coverage. complete,
    },
  },

  rule. no_counted_domain {
    llisle.select_loop_kernel_plan { candidate = P. candidate },
    when {
      P. candidate.counted :eq (false),
    },
    cost (0),
    run {
      ret {
        selection = kernel_plan {
          kind = no_plan,
          rejects = P. candidate.not_counted_rejects,
        },
      },
    },
  },

  rule. no_graph_owner {
    llisle.select_loop_kernel_plan { candidate = P. candidate },
    when {
      (P. candidate.counted :eq (true))
        * (P. candidate.has_func_id :eq (false)),
    },
    cost (0),
    run {
      ret {
        selection = kernel_plan {
          kind = no_plan,
          rejects = P. candidate.no_owner_rejects,
        },
      },
    },
  },

  rule. rejected_loop {
    llisle.select_loop_kernel_plan { candidate = P. candidate },
    when {
      (P. candidate.counted :eq (true))
        * (P. candidate.has_func_id :eq (true))
        * (P. candidate.has_rejects :eq (true)),
    },
    cost (0),
    run {
      ret {
        selection = kernel_plan {
          kind = no_plan,
          rejects = P. candidate.rejects,
        },
      },
    },
  },

  rule. planned_closed_form {
    llisle.select_loop_kernel_plan { candidate = P. candidate },
    when {
      (P. candidate.counted :eq (true))
        * (P. candidate.has_func_id :eq (true))
        * (P. candidate.has_func :eq (true))
        * (P. candidate.has_rejects :eq (false))
        * (P. candidate.has_closed_form :eq (true)),
    },
    cost (0),
    run {
      ret {
        selection = kernel_plan {
          kind = planned,
          result_kind = closed_form,
          closed_form = P. candidate.closed_form,
          add_trip_unknown_proof = P. candidate.closed_form_trip_unknown,
        },
      },
    },
  },

  rule. planned_reduction {
    llisle.select_loop_kernel_plan { candidate = P. candidate },
    when {
      (P. candidate.counted :eq (true))
        * (P. candidate.has_func_id :eq (true))
        * (P. candidate.has_func :eq (true))
        * (P. candidate.has_rejects :eq (false))
        * (P. candidate.has_closed_form :eq (false))
        * (P. candidate.has_reduction :eq (true)),
    },
    cost (10),
    run {
      ret {
        selection = kernel_plan {
          kind = planned,
          result_kind = reduction,
          reduction = P. candidate.reduction,
          add_trip_unknown_proof = false,
        },
      },
    },
  },

  rule. planned_skeleton_result {
    llisle.select_loop_kernel_plan { candidate = P. candidate },
    when {
      (P. candidate.counted :eq (true))
        * (P. candidate.has_func_id :eq (true))
        * (P. candidate.has_func :eq (true))
        * (P. candidate.has_rejects :eq (false))
        * (P. candidate.has_closed_form :eq (false))
        * (P. candidate.has_reduction :eq (false))
        * (P. candidate.has_skeleton_result :eq (true)),
    },
    cost (15),
    run {
      ret {
        selection = kernel_plan {
          kind = planned,
          result_kind = skeleton,
          skeleton_result = P. candidate.skeleton_result,
          add_trip_unknown_proof = false,
        },
      },
    },
  },

  rule. planned_original_control {
    llisle.select_loop_kernel_plan { candidate = P. candidate },
    when {
      (P. candidate.counted :eq (true))
        * (P. candidate.has_func_id :eq (true))
        * (P. candidate.has_func :eq (true))
        * (P. candidate.has_rejects :eq (false))
        * (P. candidate.has_closed_form :eq (false))
        * (P. candidate.has_reduction :eq (false))
        * (P. candidate.has_skeleton_result :eq (false)),
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

    local api = {}

    function api.select(candidate)
        local result, err = engine:run("select_loop_kernel_plan", { candidate = candidate })
        if result == nil then return nil, err and err.message or "no Kernel loop plan selected" end
        return result.output.selection, nil
    end

    api.rules = rules
    api.engine = engine

    T._moonlift_api_cache.code_kernel_plan_rules = api
    return api
end

return bind_context
