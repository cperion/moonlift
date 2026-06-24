local function bind_context(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.luajit_lower_rules ~= nil then return T._moonlift_api_cache.luajit_lower_rules end

    local moon = require("moonlift")
    local llb = require("llb")
    local Llisle = require("llisle")
    local env = moon.family.env { scope = "env", base = _G }
    Llisle.use { scope = "env", target = env, base = env, global = false }
    local llisle = env.llisle
    local LuaJITKernelLoweringCandidate = llb.symbol("LuaJITKernelLoweringCandidate")
    local LuaJITKernelLoweringSelection = llb.symbol("LuaJITKernelLoweringSelection")
    local candidate = llb.symbol("candidate")
    local selection = llb.symbol("selection")
    local kernel_lowering = llb.symbol("kernel_lowering")
    local stencil_reduce = llb.symbol("stencil_reduce")
    local vector_reduce = llb.symbol("vector_reduce")
    local stencil_store = llb.symbol("stencil_store")
    local stencil_skeleton = llb.symbol("stencil_skeleton")
    local function build_kernel_lowering(fields) return fields end

    local function build_rules()
    return llisle {
  constructor. kernel_lowering [build_kernel_lowering],

  relation. select_kernel_lowering {
    input { candidate [LuaJITKernelLoweringCandidate] },
    output { selection [LuaJITKernelLoweringSelection] },
    strategy {
      select. best_cost,
      ambiguity. error,
      coverage. complete,
    },
  },

  rule. stencil_reduce {
    llisle.select_kernel_lowering { candidate = P. candidate },
    when {
      (P. candidate.loop_plan :eq (true))
        * (P. candidate.owns_loop :eq (true))
        * (P. candidate.planned :eq (true))
        * (P. candidate.has_reduce_provider :eq (true))
        * (P. candidate.counted_positive :eq (true))
        * (P. candidate.result_reduction :eq (true))
        * (P. candidate.returns_reduction :eq (true))
        * (P. candidate.stencil_reduce_ready :eq (true)),
    },
    cost (0),
    run {
      ret { selection = kernel_lowering { kind = stencil_reduce } },
    },
  },

  rule. vector_reduce {
    llisle.select_kernel_lowering { candidate = P. candidate },
    when {
      (P. candidate.loop_plan :eq (true))
        * (P. candidate.owns_loop :eq (true))
        * (P. candidate.planned :eq (true))
        * (P. candidate.vector_reduce_ready :eq (true)),
    },
    cost (10),
    run {
      ret { selection = kernel_lowering { kind = vector_reduce } },
    },
  },

  rule. stencil_skeleton {
    llisle.select_kernel_lowering { candidate = P. candidate },
    when {
      (P. candidate.loop_plan :eq (true))
        * (P. candidate.owns_loop :eq (true))
        * (P. candidate.planned :eq (true))
        * (P. candidate.has_skeleton_provider :eq (true))
        * (P. candidate.counted_positive :eq (true))
        * (P. candidate.stencil_skeleton_ready :eq (true)),
    },
    cost (15),
    run {
      ret { selection = kernel_lowering { kind = stencil_skeleton } },
    },
  },

  rule. stencil_store {
    llisle.select_kernel_lowering { candidate = P. candidate },
    when {
      (P. candidate.loop_plan :eq (true))
        * (P. candidate.owns_loop :eq (true))
        * (P. candidate.planned :eq (true))
        * (P. candidate.has_store_provider :eq (true))
        * (P. candidate.counted_positive :eq (true))
        * (P. candidate.returns_void :eq (true))
        * (P. candidate.single_store :eq (true))
        * (P. candidate.store_dst_base :eq (true))
        * (P. candidate.stencil_store_ready :eq (true)),
    },
    cost (20),
    run {
      ret { selection = kernel_lowering { kind = stencil_store } },
    },
  },
}
    end
    if setfenv then setfenv(build_rules, env) end
    local rules = build_rules()

    local engine = Llisle.compile(rules)

    local api = {}

    function api.select(candidate)
        local result, err = engine:run("select_kernel_lowering", { candidate = candidate })
        if result == nil then return nil, err and err.message or "no LuaJIT kernel lowering selected" end
        return result.output.selection, nil
    end

    api.rules = rules
    api.engine = engine

    T._moonlift_api_cache.luajit_lower_rules = api
    return api
end

return bind_context
