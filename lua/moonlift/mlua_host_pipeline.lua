local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local H = (T.MoonHost or T.Moon2Host)
    local MluaParse = require("moonlift.mlua_parse").Define(T)
    local HostDeclValidate = require("moonlift.host_decl_validate").Define(T)
    local HostLayoutResolve = require("moonlift.host_layout_resolve").Define(T)
    local HostViewAbiPlan = require("moonlift.host_view_abi_plan").Define(T)
    local HostAccessPlan = require("moonlift.host_access_plan").Define(T)
    local HostLuaFfiEmitPlan = require("moonlift.host_lua_ffi_emit_plan").Define(T)
    local HostTerraEmitPlan = require("moonlift.host_terra_emit_plan").Define(T)
    local HostCEmitPlan = require("moonlift.host_c_emit_plan").Define(T)

    local function append_all(dst, xs)
        for i = 1, #(xs or {}) do dst[#dst + 1] = xs[i] end
    end

    local function empty_result(parsed, report, module_name, header_name)
        local env = H.HostLayoutEnv({})
        local facts = H.HostFactSet({})
        return H.MluaHostPipelineResult(
            parsed,
            report or H.HostReport({}),
            env,
            facts,
            H.HostLuaFfiPlan(module_name, {}, {}),
            H.HostTerraPlan(module_name, "", {}, {}),
            H.HostCPlan(header_name, "", {}, {})
        )
    end

    local function collect_layouts_and_facts(decls, target)
        local layouts = {}
        local facts = {}
        for i = 1, #decls.decls do
            local d = decls.decls[i]
            if pvm.classof(d) == H.HostDeclStruct then
                local layout, layout_facts = HostLayoutResolve.resolve_layout(d.decl, target)
                if layout then layouts[#layouts + 1] = layout end
                append_all(facts, layout_facts.facts)
            end
        end
        return layouts, facts
    end

    local function has_lua_facet(expose)
        for i = 1, #expose.facets do
            if expose.facets[i].target == H.HostExposeLua then return true end
        end
        return false
    end

    local function add_access_facts_for_expose(facts, expose, env, expose_facts)
        if not has_lua_facet(expose) then return end
        for i = 1, #expose_facts.facts do
            local fact = expose_facts.facts[i]
            if pvm.classof(fact) == H.HostFactViewDescriptor then
                facts[#facts + 1] = H.HostFactAccessPlan(HostAccessPlan.plan(H.HostAccessView(fact.descriptor)))
            end
        end
        if pvm.classof(expose.subject) == H.HostExposeType or pvm.classof(expose.subject) == H.HostExposePtr then
            local subject_layout = HostViewAbiPlan.plan_subject(expose.subject, env)
            if subject_layout and pvm.classof(subject_layout) == H.HostTypeLayout then
                if pvm.classof(expose.subject) == H.HostExposePtr then
                    facts[#facts + 1] = H.HostFactAccessPlan(HostAccessPlan.plan(H.HostAccessPtr(subject_layout)))
                else
                    facts[#facts + 1] = H.HostFactAccessPlan(HostAccessPlan.plan(H.HostAccessRecord(subject_layout)))
                end
            end
        end
    end

    local function run(parsed, module_name, target)
        module_name = module_name or "mlua"
        local header_name = module_name .. ".h"
        if #parsed.issues ~= 0 then return empty_result(parsed, H.HostReport({}), module_name, header_name) end
        local report = HostDeclValidate.validate(parsed.decls)
        if #report.issues ~= 0 then return empty_result(parsed, report, module_name, header_name) end
        target = target or HostLayoutResolve.default_target_model()

        local layouts, facts = collect_layouts_and_facts(parsed.decls, target)
        local env = H.HostLayoutEnv(layouts)
        for i = 1, #parsed.decls.decls do
            local d = parsed.decls.decls[i]
            if pvm.classof(d) == H.HostDeclExpose then
                local expose_facts = HostViewAbiPlan.plan_facts(d.decl, env, target)
                append_all(facts, expose_facts.facts)
                add_access_facts_for_expose(facts, d.decl, env, expose_facts)
            end
        end

        local base_fact_set = H.HostFactSet(facts)
        local lua = HostLuaFfiEmitPlan.plan(base_fact_set, module_name)
        local terra = HostTerraEmitPlan.plan(base_fact_set, module_name)
        local c = HostCEmitPlan.plan(base_fact_set, header_name)
        local all_facts = {}
        append_all(all_facts, base_fact_set.facts)
        all_facts[#all_facts + 1] = H.HostFactLuaFfi(lua)
        all_facts[#all_facts + 1] = H.HostFactTerra(terra)
        all_facts[#all_facts + 1] = H.HostFactC(c)
        return H.MluaHostPipelineResult(parsed, report, env, H.HostFactSet(all_facts), lua, terra, c)
    end

    local phase = pvm.phase("moon2_mlua_host_pipeline", {
        [H.MluaSource] = function(self, module_name, target)
            local parsed = MluaParse.parse(self.source, self.name)
            return pvm.once(run(parsed, module_name or self.name, target))
        end,
        [H.MluaParseResult] = function(self, module_name, target)
            return pvm.once(run(self, module_name, target))
        end,
    }, { args_cache = "full" })

    return {
        phase = phase,
        run = run,
        pipeline = function(source, module_name, target) return pvm.one(phase(source, module_name, target)) end,
    }
end

return M
