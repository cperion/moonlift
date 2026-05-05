local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local H = T.MoonHost
    local MluaParse = require("moonlift.mlua_parse").Define(T)
    local HostDeclValidate = require("moonlift.host_decl_validate").Define(T)
    local HostLayoutResolve = require("moonlift.host_layout_resolve").Define(T)
    local HostViewAbiPlan = require("moonlift.host_view_abi_plan").Define(T)
    local HostAccessPlan = require("moonlift.host_access_plan").Define(T)
    local HostLuaFfiEmitPlan = require("moonlift.host_lua_ffi_emit_plan").Define(T)
    local HostTerraEmitPlan = require("moonlift.host_terra_emit_plan").Define(T)
    local HostCEmitPlan = require("moonlift.host_c_emit_plan").Define(T)

    -- C frontend modules (lazy-loaded when C code detected)
    local c_lexer, cpp_expand, c_parse, cimport, lower_c

    -- Detect if source contains C code with function bodies or preprocessor directives
    local function is_c_source_with_bodies(source)
        if not source then return false end
        -- Check for preprocessor directives
        if source:find("#") then return true end
        -- Check for function bodies: ) followed by { (function definition)
        if source:find("%)%s*{") then return true end
        -- Check for GNU statement expressions: ({ ... })
        if source:find("%(%s*{") then return true end
        return false
    end

    -- Extract C source segments from MLUA source
    -- Looks for `import c` islands with bodies
    local function extract_c_source(mlua_source)
        local c_parts = {}
        -- Match import c [[ ... ]] or import c " ... "
        for body in mlua_source:gmatch("import%s+c%s+%[%[(.-)%]%]") do
            if is_c_source_with_bodies(body) then
                c_parts[#c_parts + 1] = body
            end
        end
        -- Also match import c "file.c" patterns
        for file_path in mlua_source:gmatch('import%s+c%s+"([^"]+)"') do
            if file_path:match("%.c$") or file_path:match("%.h$") then
                -- File path reference — would be handled by VFS
                c_parts[#c_parts + 1] = "__file__:" .. file_path
            end
        end
        return c_parts
    end

    -- Run the C frontend pipeline on C source text
    local function run_c_pipeline(c_source, module_name)
        if not c_lexer then
            c_lexer = require("moonlift.c.c_lexer")
            c_parse = require("moonlift.c.c_parse").Define(T)
            cimport = require("moonlift.c.cimport").Define(T)
            lower_c = require("moonlift.c.lower_c").Define(T)
        end

        local issues = {}

        -- Phase 1: Lex
        local result = c_lexer.lex(c_source, "c://" .. (module_name or "c"))

        -- cpp_expand: if directive tokens present, expand macros
        local has_directives = false
        for _, t in ipairs(result.tokens) do
            if t._variant == "CTokDirective" then has_directives = true; break end
        end

        if has_directives then
            -- Run preprocessor
            local cpp = require("moonlift.c.cpp_expand").Define(T)
            local vfs_module = require("moonlift.c.vfs")
            local vfs = vfs_module.real_fs()
            local expanded = cpp.expand(result.tokens, result.spans, result.issues, vfs, ".")
            result.tokens = expanded.tokens
            result.spans = expanded.spans
            append_all(result.issues, expanded.issues)
        end

        for i = 1, #result.issues do
            issues[#issues + 1] = result.issues[i]
        end

        -- Phase 2: Parse
        local tu, parse_issues = c_parse.parse(result.tokens, result.spans)
        for i = 1, #parse_issues do
            issues[#issues + 1] = parse_issues[i]
        end

        if #issues > 0 then
            return nil, issues
        end

        -- Phase 3: cimport (type integration)
        local type_facts, layout_facts, extern_funcs = cimport.cimport(tu.items, module_name)

        -- Phase 4: Lower to MoonTree
        local module = lower_c.lower(tu.items, type_facts, layout_facts, extern_funcs, module_name)

        return module, issues
    end

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

    local phase = pvm.phase("moonlift_mlua_host_pipeline", {
        [H.MluaSource] = function(self, module_name, target)
            local parsed = MluaParse.parse(self.source, self.name)

            -- Check for C code with bodies and route through C frontend
            local c_modules = {}
            local c_parts = extract_c_source(self.source)
            for i = 1, #c_parts do
                if not c_parts[i]:match("^__file__:") then
                    local c_module, c_issues = run_c_pipeline(c_parts[i], (module_name or self.name) .. "_c")
                    if c_module then
                        c_modules[#c_modules + 1] = c_module
                    end
                    if c_issues then
                        for j = 1, #c_issues do
                            parsed.issues[#parsed.issues + 1] = c_issues[j]
                        end
                    end
                end
            end

            -- Merge C modules into parsed module
            if #c_modules > 0 then
                for _, cm in ipairs(c_modules) do
                    for _, item in ipairs(cm.items) do
                        parsed.module.items[#parsed.module.items + 1] = item
                    end
                end
            end

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
