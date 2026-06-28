local pvm = require("lalin.pvm")

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function mkdir_parent(path)
    local dir = tostring(path):match("^(.*)/[^/]+$")
    if dir ~= nil and dir ~= "" then os.execute("mkdir -p " .. shell_quote(dir)) end
end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.luajit_backend ~= nil then return T._lalin_api_cache.luajit_backend end

    local Stencil = T.LalinStencil
    local LJ = T.LalinLuaJIT
    local Lower = require("lalin.luajit_lower")(T)
    local Emit = require("lalin.luajit_emit")(T)
    local StencilArtifactPlan = require("lalin.stencil_artifact_plan")(T)
    local StencilBank = require("lalin.copy_patch_mc")(T)
    local CopyPatchLuaTrace = require("lalin.copy_patch_luatrace")(T)
    local ExecPlan = require("lalin.exec_plan")(T)
    local CodeSchedulePlan = require("lalin.code_schedule_plan")(T)
    local BackTargetModel = require("lalin.back_target_model")(T)

    local api = {}

    local function default_target_model()
        local Back = T.LalinBack
        local native = BackTargetModel.default_native()
        return Back.BackTargetModel(Back.BackTargetDynasmJit, native.facts)
    end

    local function target_model(opts)
        return opts.target_model or opts.back_target_model or opts.target or default_target_model()
    end

    local function schedule_index(schedule_plan)
        local Schedule = T.LalinSchedule
        local by_kernel = {}
        for _, sched in ipairs(schedule_plan and schedule_plan.schedules or {}) do
            if pvm.classof(sched) == Schedule.SchedulePlanned then by_kernel[sched.kernel.text] = sched end
        end
        return by_kernel
    end

    local function attach_schedule(info, kernel_plan, schedules)
        info = info or {}
        local sched = kernel_plan and schedules[kernel_plan.id.text] or nil
        if sched ~= nil then
            info.kernel_schedule = sched
            info.schedule = sched.kind
        end
        return info
    end

    local function artifact_for(kind, op, reduction, plan, info)
        if kind == "copy" then return StencilArtifactPlan.copy_array_artifact(info) end
        if kind == "fill" then return StencilArtifactPlan.fill_array_artifact(info) end
        if kind == "map" then return StencilArtifactPlan.map_array_artifact(op, info) end
        if kind == "zip_map" then return StencilArtifactPlan.zip_map_array_artifact(op, info) end
        if kind == "cast" then return StencilArtifactPlan.cast_array_artifact(op, info) end
        if kind == "compare" then return StencilArtifactPlan.compare_array_artifact(op, info) end
        if kind == "zip_compare" then return StencilArtifactPlan.zip_compare_array_artifact(op, info) end
        if kind == "gather" then return StencilArtifactPlan.gather_array_artifact(info) end
        if kind == "scatter" then return StencilArtifactPlan.scatter_array_artifact(info) end
        if kind == "scatter_reduce" then return StencilArtifactPlan.scatter_reduce_n_artifact(reduction, plan, info) end
        if kind == "apply_n" then return StencilArtifactPlan.apply_n_artifact(info) end
        if kind == "in_place_map" then return StencilArtifactPlan.in_place_map_array_artifact(op, info) end
        if kind == "scan" then return StencilArtifactPlan.scan_array_artifact(reduction, plan, info) end
        if kind == "find" then return StencilArtifactPlan.find_array_artifact(op, info) end
        if kind == "partition" then return StencilArtifactPlan.partition_array_artifact(op, info) end
        if kind == "reduce" then return StencilArtifactPlan.reduce_array_artifact(reduction, plan, info) end
        if kind == "reduce_n" then return StencilArtifactPlan.reduce_n_artifact(reduction, plan, info) end
        if kind == "count" then return StencilArtifactPlan.count_array_artifact(op, info) end
        if kind == "map_reduce" then
            return StencilArtifactPlan.reduce_n_artifact(reduction, plan, {
                tag = "map_" .. tostring(op),
                inputs = { { name = "xs", ty = assert(info.elem_ty), layout = info.array_layout or info.src_layout } },
                expr = StencilArtifactPlan.apply_unary_expr(op, StencilArtifactPlan.input_expr("xs"), assert(info.mapped_ty), info),
                item_ty = info.mapped_ty,
                result_ty = info.result_ty,
                step_num = info.step_num or info.stride,
                producer = info.producer,
                schedule = info.schedule,
                noalias = info.noalias,
                noalias_pairs = info.noalias_pairs,
                alignment = info.alignment,
                alignments = info.alignments,
            })
        end
        if kind == "zip_reduce" then
            return StencilArtifactPlan.reduce_n_artifact(reduction, plan, {
                tag = "zip_" .. tostring(op),
                inputs = {
                    { name = "lhs", ty = assert(info.lhs_ty), layout = info.lhs_layout },
                    { name = "rhs", ty = assert(info.rhs_ty), layout = info.rhs_layout },
                },
                expr = StencilArtifactPlan.apply_binary_expr(op, StencilArtifactPlan.input_expr("lhs"), StencilArtifactPlan.input_expr("rhs"), assert(info.mapped_ty), info),
                item_ty = info.mapped_ty,
                result_ty = info.result_ty,
                step_num = info.step_num or info.stride,
                producer = info.producer,
                schedule = info.schedule,
                noalias = info.noalias,
                noalias_pairs = info.noalias_pairs,
                alignment = info.alignment,
                alignments = info.alignments,
            })
        end
        error("luajit_backend: unsupported selected stencil kind " .. tostring(kind), 3)
    end

    local function copy_patch_mode(opts)
        local mode = tostring((opts or {}).copy_patch or "mc")
        if mode == "mc" or mode == "bc" then return mode end
        error("luajit_backend: unknown copy_patch materializer " .. mode, 3)
    end

    local function native_residual_mode(opts)
        opts = opts or {}
        if copy_patch_mode(opts) == "bc" then return nil end
        if opts.native_residual ~= nil then return opts.native_residual end
        if opts.tcc_residual ~= nil then return opts.tcc_residual end
        return "tcc"
    end

    local function artifact_with_provider(artifact, opts)
        if copy_patch_mode(opts) == "bc" then
            return CopyPatchLuaTrace.bc_artifact(artifact)
        end
        return artifact
    end

    local function collect_artifact(artifacts, selections, vocab, op, reduction, plan, info, opts)
        info = info or {}
        local artifact = artifact_with_provider(artifact_for(vocab, op, reduction, plan, info), opts)
        artifacts[#artifacts + 1] = artifact
        selections[#selections + 1] = Stencil.StencilPlanEntry(
            plan.id,
            Stencil.StencilSelected(
                artifact.instance,
                StencilArtifactPlan.selection_provenance_for_artifact(artifact)
            )
        )
        return artifact
    end

    function api.lower_module(module, opts)
        opts = opts or {}
        local artifacts = {}
        local selections = {}
        local rejects = opts.collect_rejects or {}
        local graph, flow, value, mem, effect, kernel = Lower.build_kernel(module, opts)
        local schedule_plan = opts.schedule_plan or opts.schedule or CodeSchedulePlan.plan(module, kernel, flow, value, mem, effect, target_model(opts))
        local schedules = schedule_index(schedule_plan)
        local stencil_machines = Lower.plan_stencil_machines(module, {
            contracts = opts.contracts,
            graph = graph,
            flow = flow,
            value = value,
            mem = mem,
            effect = effect,
            kernel = kernel,
            stencil_store_artifact_for = function(_func, vocab, op, plan, info)
                return collect_artifact(artifacts, selections, vocab, op, nil, plan, attach_schedule(info, plan, schedules), opts)
            end,
            stencil_reduce_artifact_for = function(_func, vocab, op, reduction, plan, info)
                return collect_artifact(artifacts, selections, vocab, op, reduction, plan, attach_schedule(info, plan, schedules), opts)
            end,
            stencil_skeleton_artifact_for = function(_func, vocab, op, reduction, plan, info)
                return collect_artifact(artifacts, selections, vocab, op, reduction, plan, attach_schedule(info, plan, schedules), opts)
            end,
        })
        for _, reject in ipairs(stencil_machines.rejects or {}) do rejects[#rejects + 1] = reject end
        local lj_module, facts = Lower.lower_module(module, {
            contracts = opts.contracts,
            graph = graph,
            flow = flow,
            value = value,
            mem = mem,
            effect = effect,
            kernel = kernel,
            stencil_machines_by_func = stencil_machines.machines_by_func,
        })
        facts.schedule = schedule_plan
        facts.schedule_plan = schedule_plan
        facts.stencil = Stencil.StencilModulePlan(module.id, facts.kernel, selections)
        facts.stencil_plan = facts.stencil
        facts.luajit_stencil_machines = LJ.LJStencilMachineModulePlan(module.id, facts.stencil, stencil_machines.machine_plans or {})
        facts.exec = ExecPlan.plan(module, {
            graph = facts.graph,
            flow = facts.flow,
            value = facts.value,
            mem = facts.mem,
            effect = facts.effect,
            kernels = facts.kernel,
            stencil = facts.stencil,
            artifacts = artifacts,
            contracts = opts.contracts,
        })
        facts.exec_plan = facts.exec
        return lj_module, facts, artifacts, rejects
    end

    function api.realize_artifacts(artifacts, opts)
        opts = opts or {}
        if #artifacts == 0 then
            return { kind = "MCStencilBankRealization", symbols = {}, installed = {}, bank = nil }, nil
        end
        local function realize_bc(fallback_reason)
            local realized, err, source = CopyPatchLuaTrace.realize_bc_artifacts(artifacts, {
                bank = opts.bc_bank,
                stem = opts.stem,
                id = opts.bc_bank_id,
                target = opts.bc_target,
                env = opts.bc_env,
            })
            if realized ~= nil and fallback_reason ~= nil then
                realized.fallback_from = "copy_patch_mc"
                realized.fallback_reason = fallback_reason
            end
            return realized, err, source
        end
        if copy_patch_mode(opts) == "bc" then
            return realize_bc(nil)
        end
        local mc_bank = opts.mc_bank
        if mc_bank == nil then
            local err = "luajit_backend: mc realization requires a prebuilt MCStencilBank"
            if opts.allow_bc_fallback then return realize_bc(err) end
            return nil, err
        end
        local realized, err, source = StencilBank.realize_mc_artifacts(artifacts, {
            mc_bank = mc_bank,
            install_policy = opts.install_policy,
        })
        if realized == nil and opts.allow_bc_fallback then return realize_bc(err) end
        return realized, err, source
    end

    function api.build_mc_bank(artifacts, opts)
        return StencilBank.build_mc_bank(artifacts or {}, opts or {})
    end

    function api.build_bc_bank(artifacts, opts)
        return CopyPatchLuaTrace.build_bc_bank(artifacts or {}, opts or {})
    end

    function api.compile_lj_module(lj_module, artifacts, opts)
        opts = opts or {}
        local realized, realize_err, realize_source = api.realize_artifacts(artifacts or {}, opts)
        if realized == nil then return nil, realize_err, realize_source end
        local native_residual = native_residual_mode(opts)
        if realized.kind ~= "MCStencilBankRealization" then native_residual = nil end
        local compiled, emit_err, source = Emit.compile_module(lj_module, {
            chunk_name = opts.chunk_name or "lalin_luajit_backend",
            stencil_symbols = realized.symbols,
            native_residual = native_residual,
        })
        if compiled == nil then return nil, emit_err, source end
        return {
            module = compiled,
            lj_module = lj_module,
            realization = realized,
            source = source,
        }
    end

    function api.emit_lua_artifact(lj_module, artifacts, opts)
        opts = opts or {}
        local stencil_source
        local bc_bank
        local mode = copy_patch_mode(opts)
        if mode == "bc" then
            bc_bank = opts.bc_bank
            if bc_bank == nil then
                local bank_err
                bc_bank, bank_err = api.build_bc_bank(artifacts or {}, {
                    stem = opts.stem,
                    id = opts.bc_bank_id,
                    target = opts.bc_target,
                })
                if bc_bank == nil then return nil, bank_err end
            end
            stencil_source = CopyPatchLuaTrace.emit_bc_bank_source(bc_bank, opts)
        else
            local mc_bank = opts.mc_bank
            if mc_bank == nil and #(artifacts or {}) > 0 then
                return nil, "luajit_backend.emit_lua_artifact requires a prebuilt MCStencilBank"
            end
            stencil_source = mc_bank and StencilBank.emit_mc_bank_source(mc_bank, opts) or "local __lalin_luajit_stencil_symbols = {}\n"
        end
        local module_source = Emit.emit_module(lj_module, {
            chunk_name = opts.chunk_name or "lalin_luajit_artifact",
            native_residual = native_residual_mode(opts),
        })
        local source = table.concat({
            mode == "bc"
                and "-- Generated Lalin LuaJIT LuaTrace BC copy-patch artifact.\n"
                or "-- Generated Lalin LuaJIT MC copy+residual artifact.\n",
            mode == "bc"
                and "-- Stencil descriptors are emitted below as LuaJIT BC stencils.\n"
                or "-- Native MC stencil bytes are embedded below as data; TCC residual glue calls installed bank stencils.\n",
            stencil_source,
            module_source,
        })
        if opts.path ~= nil then
            mkdir_parent(opts.path)
            local f = assert(io.open(opts.path, "wb"))
            f:write(source)
            f:close()
        end
        return source
    end

    function api.emit_module_artifact(module, opts)
        opts = opts or {}
        local lj_module, facts, artifacts, rejects = api.lower_module(module, opts)
        if opts.reject_on_stencil_rejects ~= false and rejects and #rejects > 0 then
            return nil, rejects[1] and rejects[1].reason or "LuaJIT backend rejected module"
        end
        local source, err = api.emit_lua_artifact(lj_module, artifacts, opts)
        if source == nil then return nil, err end
        return {
            kind = "LuaJITSourceArtifact",
            source = source,
            lj_module = lj_module,
            facts = facts,
            stencil_plan = facts.stencil,
            luajit_stencil_machines = facts.luajit_stencil_machines,
            exec_plan = facts.exec,
            artifacts = artifacts,
            rejects = rejects,
            mc_bank = opts.mc_bank,
        }
    end

    function api.compile_module(module, opts)
        opts = opts or {}
        local lj_module, facts, artifacts, rejects = api.lower_module(module, opts)
        if opts.reject_on_stencil_rejects ~= false and rejects and #rejects > 0 then
            return nil, rejects[1] and rejects[1].reason or "LuaJIT backend rejected module"
        end
        local result, err, source = api.compile_lj_module(lj_module, artifacts, opts)
        if result == nil then return nil, err, source end
        result.facts = facts
        result.stencil_plan = facts.stencil
        result.luajit_stencil_machines = facts.luajit_stencil_machines
        result.exec_plan = facts.exec
        result.artifacts = artifacts
        result.rejects = rejects
        return result
    end

    api.artifact_for = artifact_for

    T._lalin_api_cache.luajit_backend = api
    return api
end

return bind_context
