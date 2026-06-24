local function bind_context(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.code_schedule_plan_rules ~= nil then return T._moonlift_api_cache.code_schedule_plan_rules end

    local moon = require("moonlift")
    local llb = require("llb")
    local Llisle = require("llisle")
    local env = moon.family.env { scope = "env", base = _G }
    Llisle.use { scope = "env", target = env, base = env, global = false }
    local llisle = env.llisle
    local KernelScheduleCandidate = llb.symbol("KernelScheduleCandidate")
    local KernelScheduleSelection = llb.symbol("KernelScheduleSelection")
    local candidate = llb.symbol("candidate")
    local selection = llb.symbol("selection")
    local kernel_schedule = llb.symbol("kernel_schedule")
    local planned = llb.symbol("planned")
    local no_plan = llb.symbol("no_plan")
    local function build_kernel_schedule(fields) return fields end

    local function build_rules()
    return llisle {
  constructor. kernel_schedule [build_kernel_schedule],

  relation. select_kernel_schedule {
    input { candidate [KernelScheduleCandidate] },
    output { selection [KernelScheduleSelection] },
    strategy {
      select. best_cost,
      ambiguity. error,
      coverage. complete,
    },
  },

  rule. vector_executable {
    llisle.select_kernel_schedule { candidate = P. candidate },
    when {
      (P. candidate.has_vector_candidate :eq (true))
        * (P. candidate.vector_executable :eq (true)),
    },
    cost (0),
    run {
      ret {
        selection = kernel_schedule {
          kind = planned,
          schedule_kind = P. candidate.vector_kind,
          capability = P. candidate.vector_capability,
          rejected_alternatives = {},
        },
      },
    },
  },

  rule. scalar_after_vector_reject {
    llisle.select_kernel_schedule { candidate = P. candidate },
    when {
      (P. candidate.has_vector_candidate :eq (true))
        * (P. candidate.vector_executable :eq (false))
        * (P. candidate.scalar_executable :eq (true)),
    },
    cost (10),
    run {
      ret {
        selection = kernel_schedule {
          kind = planned,
          schedule_kind = P. candidate.scalar_kind,
          capability = P. candidate.scalar_capability,
          rejected_alternatives = P. candidate.vector_rejects,
        },
      },
    },
  },

  rule. scalar_without_vector {
    llisle.select_kernel_schedule { candidate = P. candidate },
    when {
      (P. candidate.has_vector_candidate :eq (false))
        * (P. candidate.scalar_executable :eq (true)),
    },
    cost (20),
    run {
      ret {
        selection = kernel_schedule {
          kind = planned,
          schedule_kind = P. candidate.scalar_kind,
          capability = P. candidate.scalar_capability,
          rejected_alternatives = {},
        },
      },
    },
  },

  rule. no_executable_schedule_after_vector_reject {
    llisle.select_kernel_schedule { candidate = P. candidate },
    when {
      (P. candidate.has_vector_candidate :eq (true))
        * (P. candidate.vector_executable :eq (false))
        * (P. candidate.scalar_executable :eq (false)),
    },
    cost (30),
    run {
      ret {
        selection = kernel_schedule {
          kind = no_plan,
          rejects = P. candidate.scalar_rejects,
        },
      },
    },
  },

  rule. no_executable_schedule_without_vector {
    llisle.select_kernel_schedule { candidate = P. candidate },
    when {
      (P. candidate.has_vector_candidate :eq (false))
        * (P. candidate.scalar_executable :eq (false)),
    },
    cost (40),
    run {
      ret {
        selection = kernel_schedule {
          kind = no_plan,
          rejects = P. candidate.scalar_rejects,
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
        local result, err = engine:run("select_kernel_schedule", { candidate = candidate })
        if result == nil then return nil, err and err.message or "no Kernel schedule selected" end
        return result.output.selection, nil
    end

    api.rules = rules
    api.engine = engine

    T._moonlift_api_cache.code_schedule_plan_rules = api
    return api
end

return bind_context
