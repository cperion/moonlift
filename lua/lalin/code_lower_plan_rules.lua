local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.code_lower_plan_rules ~= nil then return T._lalin_api_cache.code_lower_plan_rules end

    local lalin = require("lalin")
    local llb = require("llb")
    local Llisle = require("llisle")
    local RuleApi = require("lalin.llisle_rule_api")
    local env = lalin.family.env { scope = "env", base = _G }
    Llisle.use { scope = "env", target = env, base = env, global = false }
    local llisle = env.llisle

    local LowerFragmentInput = llb.symbol("LowerFragmentInput")
    local LowerFragmentSelection = llb.symbol("LowerFragmentSelection")
    local fragment = llb.symbol("fragment")
    local selection = llb.symbol("selection")
    local lower_fragment_selection = llb.symbol("lower_fragment_selection")

    local closed_form = llb.symbol("closed_form")
    local kernel = llb.symbol("kernel")
    local fallback = llb.symbol("fallback")
    local none = llb.symbol("none")

    local function build_selection(fields) return fields end

    local function build_rules()
    return llisle {
  constructor. lower_fragment_selection [build_selection],

  relation. select_lower_fragment {
    input { fragment [LowerFragmentInput] },
    output { selection [LowerFragmentSelection] },
    strategy {
      select. best_cost,
      ambiguity. error,
      coverage. complete,
    },
  },

  rule. planned_closed_form {
    llisle.select_lower_fragment { fragment = P. fragment },
    when {
      (P. fragment.has_kernel :eq (true))
        * (P. fragment.schedule_planned :eq (true))
        * (P. fragment.schedule_closed_form :eq (true))
        * (P. fragment.has_closed_form :eq (true)),
    },
    cost (0),
    run {
      ret {
        selection = lower_fragment_selection {
          kind = closed_form,
          closed_form = P. fragment.closed_form,
        },
      },
    },
  },

  rule. closed_form_schedule_without_fact {
    llisle.select_lower_fragment { fragment = P. fragment },
    when {
      (P. fragment.has_kernel :eq (true))
        * (P. fragment.schedule_planned :eq (true))
        * (P. fragment.schedule_closed_form :eq (true))
        * (P. fragment.has_closed_form :eq (false)),
    },
    cost (0),
    run {
      ret {
        selection = lower_fragment_selection {
          kind = fallback,
          reason = P. fragment.closed_form_missing_reason,
        },
      },
    },
  },

  rule. planned_kernel {
    llisle.select_lower_fragment { fragment = P. fragment },
    when {
      (P. fragment.has_kernel :eq (true))
        * (P. fragment.schedule_planned :eq (true))
        * (P. fragment.schedule_closed_form :eq (false)),
    },
    cost (0),
    run {
      ret {
        selection = lower_fragment_selection {
          kind = kernel,
        },
      },
    },
  },

  rule. planned_kernel_without_schedule {
    llisle.select_lower_fragment { fragment = P. fragment },
    when {
      (P. fragment.has_kernel :eq (true))
        * (P. fragment.schedule_planned :eq (false)),
    },
    cost (0),
    run {
      ret {
        selection = lower_fragment_selection {
          kind = fallback,
          reason = P. fragment.no_schedule_reason,
        },
      },
    },
  },

  rule. rejected_kernel {
    llisle.select_lower_fragment { fragment = P. fragment },
    when {
      (P. fragment.has_kernel :eq (false))
        * (P. fragment.has_kernel_no_plan :eq (true)),
    },
    cost (0),
    run {
      ret {
        selection = lower_fragment_selection {
          kind = fallback,
          reason = P. fragment.kernel_no_plan_reason,
        },
      },
    },
  },

  rule. no_loop_kernel_decision {
    llisle.select_lower_fragment { fragment = P. fragment },
    when {
      (P. fragment.has_kernel :eq (false))
        * (P. fragment.has_kernel_no_plan :eq (false)),
    },
    cost (0),
    run {
      ret {
        selection = lower_fragment_selection {
          kind = none,
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
        closed_form = "closed_form",
        kernel = "kernel",
        fallback = "fallback",
        none = "none",
      },
    })

    T._lalin_api_cache.code_lower_plan_rules = api
    return api
end

return bind_context
