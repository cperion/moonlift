local pvm = require("moonlift.pvm")

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function mkdir_parent(path)
    local dir = tostring(path):match("^(.*)/[^/]+$")
    if dir ~= nil and dir ~= "" then os.execute("mkdir -p " .. shell_quote(dir)) end
end

local function bind_context(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.luajit_backend ~= nil then return T._moonlift_api_cache.luajit_backend end

    local Stencil = T.MoonStencil
    local LJ = T.MoonLuaJIT
    local Lower = require("moonlift.luajit_lower")(T)
    local Emit = require("moonlift.luajit_emit")(T)
    local StencilArtifactPlan = require("moonlift.stencil_artifact_plan")(T)
    local StencilBank = require("moonlift.stencil_bank")(T)
    local StencilLuaJIT = require("moonlift.stencil_luajit")(T)
    local ExecPlan = require("moonlift.exec_plan")(T)
    local CodeSchedulePlan = require("moonlift.code_schedule_plan")(T)
    local BackTargetModel = require("moonlift.back_target_model")(T)

    local api = {}

    local function default_target_model()
        local Back = T.MoonBack
        local native = BackTargetModel.default_native()
        return Back.BackTargetModel(Back.BackTargetDynasmJit, native.facts)
    end

    local function target_model(opts)
        return opts.target_model or opts.back_target_model or opts.target or default_target_model()
    end

    local function schedule_index(schedule_plan)
        local Schedule = T.MoonSchedule
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

    local function artifact_for(vocab, op, reduction, plan, info)
        if vocab == Stencil.StencilCopy then return StencilArtifactPlan.copy_array_artifact(info) end
        if vocab == Stencil.StencilFill then return StencilArtifactPlan.fill_array_artifact(info) end
        if vocab == Stencil.StencilMap then return StencilArtifactPlan.map_array_artifact(op, info) end
        if vocab == Stencil.StencilZipMap then return StencilArtifactPlan.zip_map_array_artifact(op, info) end
        if vocab == Stencil.StencilCast then return StencilArtifactPlan.cast_array_artifact(op, info) end
        if vocab == Stencil.StencilCompare then return StencilArtifactPlan.compare_array_artifact(op, info) end
        if vocab == Stencil.StencilZipCompare then return StencilArtifactPlan.zip_compare_array_artifact(op, info) end
        if vocab == Stencil.StencilGather then return StencilArtifactPlan.gather_array_artifact(info) end
        if vocab == Stencil.StencilScatter then return StencilArtifactPlan.scatter_array_artifact(info) end
        if vocab == Stencil.StencilInPlaceMap then return StencilArtifactPlan.in_place_map_array_artifact(op, info) end
        if vocab == Stencil.StencilScan then return StencilArtifactPlan.scan_array_artifact(reduction, plan, info) end
        if vocab == Stencil.StencilFind then return StencilArtifactPlan.find_array_artifact(op, info) end
        if vocab == Stencil.StencilPartition then return StencilArtifactPlan.partition_array_artifact(op, info) end
        if vocab == Stencil.StencilReduce then return StencilArtifactPlan.reduce_array_artifact(reduction, plan, info) end
        if vocab == Stencil.StencilCount then return StencilArtifactPlan.count_array_artifact(op, info) end
        if vocab == Stencil.StencilMapReduce then return StencilArtifactPlan.map_reduce_array_artifact(op, reduction, plan, info) end
        if vocab == Stencil.StencilZipReduce then return StencilArtifactPlan.zip_reduce_array_artifact(op, reduction, plan, info) end
        error("luajit_backend: unsupported selected stencil vocab " .. tostring(vocab), 3)
    end

    local function provider_name(opts)
        return tostring((opts or {}).stencil_provider or (opts or {}).provider or "c")
    end

    local function is_luatrace_provider(provider)
        return provider == "lua_trace" or provider == "luatrace" or provider == "gps"
    end

    local function luatrace_materializer(opts)
        local materializer = tostring((opts or {}).luatrace_materializer or (opts or {}).stencil_materializer or (opts or {}).materializer or "bytecode")
        if materializer == "bytecode" or materializer == "bc" or materializer == "bc_copy_patch" or materializer == "bytecode_copy_patch" then
            return "bytecode"
        end
        error("luajit_backend: unknown LuaTrace materializer " .. tostring(materializer), 3)
    end

    local function artifact_with_provider(artifact, opts)
        local provider = provider_name(opts)
        if provider == "c" or provider == "copy_patch" or provider == "binary" then return artifact end
        if is_luatrace_provider(provider) then
            return StencilLuaJIT.lua_trace_artifact(artifact)
        end
        error("luajit_backend: unknown stencil provider " .. tostring(provider), 3)
    end

    local function collect_artifact(artifacts, selections, vocab, op, reduction, plan, info, opts)
        info = info or {}
        local artifact = artifact_with_provider(artifact_for(vocab, op, reduction, plan, info), opts)
        artifacts[#artifacts + 1] = artifact
        selections[#selections + 1] = Stencil.StencilPlanEntry(plan.id, Stencil.StencilSelected(artifact.instance))
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
            return { kind = "BinaryStencilBankRealization", symbols = {}, installed = {}, bank = nil }, nil
        end
        local provider = provider_name(opts)
        if is_luatrace_provider(provider) then
            luatrace_materializer(opts)
            return StencilLuaJIT.realize_bytecode_artifacts(artifacts, {
                bank = opts.bytecode_bank or opts.bc_bank,
                stem = opts.stem,
                id = opts.bytecode_bank_id or opts.bc_bank_id,
                target = opts.bytecode_target or opts.bc_target,
                patch_bindings = opts.bytecode_patch_bindings or opts.patch_bindings,
                env = opts.bytecode_env,
            })
        end
        local bank = opts.bank
        if bank == nil then
            return nil, "luajit_backend: binary realization requires a prebuilt BinaryStencilBank"
        end
        return StencilBank.realize_binary_artifacts(artifacts, {
            bank = bank,
            patch_values = opts.patch_values,
            install_policy = opts.install_policy,
        })
    end

    function api.build_binary_bank(artifacts, opts)
        return StencilBank.build_binary_bank(artifacts or {}, opts or {})
    end

    function api.build_bytecode_bank(artifacts, opts)
        return StencilLuaJIT.build_bytecode_bank(artifacts or {}, opts or {})
    end

    function api.compile_lj_module(lj_module, artifacts, opts)
        opts = opts or {}
        local realized, realize_err, realize_source = api.realize_artifacts(artifacts or {}, opts)
        if realized == nil then return nil, realize_err, realize_source end
        local compiled, emit_err, source = Emit.compile_module(lj_module, {
            chunk_name = opts.chunk_name or "moonlift_luajit_backend",
            stencil_symbols = realized.symbols,
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
        local provider = provider_name(opts)
        local stencil_source
        local bytecode_bank
        if is_luatrace_provider(provider) then
            luatrace_materializer(opts)
            bytecode_bank = opts.bytecode_bank or opts.bc_bank
            if bytecode_bank == nil then
                local bank_err
                bytecode_bank, bank_err = api.build_bytecode_bank(artifacts or {}, {
                    stem = opts.stem,
                    id = opts.bytecode_bank_id or opts.bc_bank_id,
                    target = opts.bytecode_target or opts.bc_target,
                })
                if bytecode_bank == nil then return nil, bank_err end
            end
            stencil_source = StencilLuaJIT.emit_bytecode_bank_source(bytecode_bank, opts)
        else
            local bank = opts.bank
            if bank == nil and #(artifacts or {}) > 0 then
                return nil, "luajit_backend.emit_lua_artifact requires a prebuilt BinaryStencilBank"
            end
            stencil_source = bank and StencilBank.emit_lua_bank_source(bank, opts) or "local __moonlift_luajit_stencil_symbols = {}\n"
        end
        local module_source = Emit.emit_module(lj_module, {
            chunk_name = opts.chunk_name or "moonlift_luajit_artifact",
        })
        local is_luatrace = is_luatrace_provider(provider)
        local source = table.concat({
            is_luatrace
                and "-- Generated Moonlift LuaJIT LuaTrace bytecode copy-patch artifact.\n"
                or "-- Generated Moonlift LuaJIT copy-and-patch artifact.\n",
            is_luatrace
                and "-- Stencil descriptors are emitted below as LuaJIT bytecode stencils.\n"
                or "-- Native stencil bytes are embedded below as data and installed before the runtime module loads.\n",
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
            bank = opts.bank,
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

    T._moonlift_api_cache.luajit_backend = api
    return api
end

return bind_context
