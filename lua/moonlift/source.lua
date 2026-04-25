package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")

local M = {}

function M.Define(T, opts)
    local Elab = T.MoonliftElab
    local Sem = T.MoonliftSem
    local Back = T.MoonliftBack
    local Surf = T.MoonliftSurface

    local Parse = require("moonlift.parse").Define(T)
    local SurfaceToElabTop = require("moonlift.lower_surface_to_elab_top").Define(T)
    local SurfaceToElabLoop = require("moonlift.lower_surface_to_elab_loop").Define(T)
    local ElabToSem = require("moonlift.lower_elab_to_sem").Define(T)

    local function default_elab_env(env, module_name)
        local use_module_name = module_name or ""
        if env ~= nil then
            local current_name = env.module_name or ""
            if current_name ~= "" and use_module_name ~= "" and current_name ~= use_module_name then
                error("source: explicit ElabEnv.module_name '" .. current_name .. "' does not match requested module name '" .. use_module_name .. "'")
            end
            if current_name == use_module_name then return env end
            return pvm.with(env, { module_name = use_module_name })
        end
        return Elab.ElabEnv(use_module_name, {}, {}, {})
    end

    local function default_const_env(env)
        if env ~= nil then return env end
        return Elab.ElabConstEnv({})
    end

    local function default_layout_env(env)
        if env ~= nil then return env end
        return Sem.SemLayoutEnv({})
    end

    local function empty_sem_const_env()
        return Sem.SemConstEnv({})
    end

    local function copy_array(src)
        local out = {}
        if src == nil then return out end
        for i = 1, #src do
            out[i] = src[i]
        end
        return out
    end

    local function merge_elab_env(base, extra, module_name)
        local lhs = default_elab_env(base, module_name)
        local rhs = extra or Elab.ElabEnv("", {}, {}, {})
        local values = copy_array(lhs.values)
        for i = 1, #(rhs.values or {}) do
            values[#values + 1] = rhs.values[i]
        end
        local types = copy_array(lhs.types)
        for i = 1, #(rhs.types or {}) do
            types[#types + 1] = rhs.types[i]
        end
        local layouts = copy_array(lhs.layouts)
        for i = 1, #(rhs.layouts or {}) do
            layouts[#layouts + 1] = rhs.layouts[i]
        end
        return Elab.ElabEnv(lhs.module_name or "", values, types, layouts)
    end

    local function merge_elab_const_env(base, extra)
        local entries = copy_array(default_const_env(base).entries)
        local rhs = default_const_env(extra)
        for i = 1, #rhs.entries do
            entries[#entries + 1] = rhs.entries[i]
        end
        return Elab.ElabConstEnv(entries)
    end

    local function merge_sem_const_env(base, extra)
        local lhs = base or empty_sem_const_env()
        local rhs = extra or empty_sem_const_env()
        local entries = copy_array(lhs.entries)
        for i = 1, #rhs.entries do
            entries[#entries + 1] = rhs.entries[i]
        end
        return Sem.SemConstEnv(entries)
    end

    local function merge_layout_env(base, extra)
        local lhs = default_layout_env(base)
        local rhs = default_layout_env(extra)
        local layouts = copy_array(lhs.layouts)
        for i = 1, #rhs.layouts do
            layouts[#layouts + 1] = rhs.layouts[i]
        end
        return Sem.SemLayoutEnv(layouts)
    end

    local function resolve_api()
        return require("moonlift.resolve_sem_layout").Define(T)
    end

    local function back_api()
        return require("moonlift.lower_sem_to_back").Define(T)
    end

    local function jit_api()
        return require("moonlift.jit").Define(T, opts)
    end

    local function surf_path_text(path)
        local parts = {}
        for i = 1, #path.parts do
            parts[i] = path.parts[i].text
        end
        return table.concat(parts, ".")
    end

    local function qualified_name(module_name, item_name)
        if module_name == nil or module_name == "" then
            return item_name
        end
        return module_name .. "." .. item_name
    end

    local function import_path_key(module_name)
        return "import." .. module_name
    end

    local function collect_surface_imports(surface)
        local imports = {}
        local seen = {}
        for i = 1, #surface.items do
            local item = surface.items[i]
            if item.imp ~= nil then
                local module_name = surf_path_text(item.imp.path)
                if not seen[module_name] then
                    imports[#imports + 1] = {
                        module_name = module_name,
                        path = import_path_key(module_name),
                    }
                    seen[module_name] = true
                end
            end
        end
        return imports
    end

    local function exported_elab_env(module)
        local values = {}
        local types = {}
        local layouts = {}
        for i = 1, #module.items do
            local item = module.items[i]
            if item.func ~= nil then
                local params = {}
                for j = 1, #item.func.params do
                    params[j] = item.func.params[j].ty
                end
                local fn_ty = Elab.ElabTFunc(params, item.func.result)
                if item.func.symbol ~= nil then
                    values[#values + 1] = Elab.ElabValueEntry(
                        qualified_name(module.module_name, item.func.name),
                        Elab.ElabExtern(item.func.symbol, fn_ty)
                    )
                else
                    values[#values + 1] = Elab.ElabValueEntry(
                        qualified_name(module.module_name, item.func.name),
                        Elab.ElabGlobalFunc(module.module_name, item.func.name, fn_ty)
                    )
                end
            elseif item.c ~= nil then
                values[#values + 1] = Elab.ElabValueEntry(
                    qualified_name(module.module_name, item.c.name),
                    Elab.ElabGlobalConst(module.module_name, item.c.name, item.c.ty)
                )
            elseif item.s ~= nil then
                values[#values + 1] = Elab.ElabValueEntry(
                    qualified_name(module.module_name, item.s.name),
                    Elab.ElabGlobalStatic(module.module_name, item.s.name, item.s.ty)
                )
            elseif item.t ~= nil then
                types[#types + 1] = Elab.ElabTypeEntry(
                    qualified_name(module.module_name, item.t.name),
                    Elab.ElabTNamed(module.module_name, item.t.name)
                )
                layouts[#layouts + 1] = Elab.ElabLayoutNamed(module.module_name, item.t.name, item.t.fields)
            end
        end
        return Elab.ElabEnv("", values, types, layouts)
    end

    local function exported_elab_const_env(module)
        local entries = {}
        for i = 1, #module.items do
            local item = module.items[i]
            if item.c ~= nil then
                entries[#entries + 1] = Elab.ElabConstEntry(module.module_name, item.c.name, item.c.ty, item.c.value)
            end
        end
        return Elab.ElabConstEnv(entries)
    end

    local function exported_sem_const_env(module)
        local entries = {}
        for i = 1, #module.items do
            local item = module.items[i]
            if item.c ~= nil then
                entries[#entries + 1] = Sem.SemConstEntry(module.module_name, item.c.name, item.c.ty, item.c.value)
            end
        end
        return Sem.SemConstEnv(entries)
    end

    local function normalize_named_modules(modules)
        local ordered = {}
        local lookup = {}
        if modules[1] ~= nil then
            for i = 1, #modules do
                local entry = modules[i]
                if type(entry) ~= "table" or type(entry.name) ~= "string" or type(entry.text) ~= "string" then
                    error("source_package: array modules must use { name = '...', text = '...' } entries")
                end
                if lookup[entry.name] ~= nil then
                    error("source_package: duplicate module '" .. entry.name .. "'")
                end
                ordered[#ordered + 1] = entry.name
                lookup[entry.name] = entry.text
            end
            return ordered, lookup
        end
        local names = {}
        for name, text in pairs(modules) do
            if type(name) ~= "string" or type(text) ~= "string" then
                error("source_package: map modules must use string keys and string source texts")
            end
            names[#names + 1] = name
        end
        table.sort(names)
        for i = 1, #names do
            lookup[names[i]] = modules[names[i]]
        end
        return names, lookup
    end

    local function best_span_for_message(spans, fallback_path, message)
        if spans == nil then return fallback_path, nil end
        local best_path = fallback_path
        local best_span = fallback_path and spans:get(fallback_path) or nil
        local best_len = best_path and #best_path or -1
        if type(message) == "string" then
            for _, path in ipairs(spans:paths()) do
                if string.find(message, path, 1, true) and #path > best_len then
                    best_path = path
                    best_span = spans:get(path)
                    best_len = #path
                end
            end
        end
        return best_path, best_span
    end

    local function normalize_diag_message(message, path)
        if type(message) ~= "string" then
            return tostring(message)
        end
        local out = message
        while true do
            local trimmed, n = string.gsub(out, "^.-%.lua:%d+:%s*", "", 1)
            if n == 0 then break end
            out = trimmed
        end
        while true do
            local trimmed, n = string.gsub(out, "^surface_to_elab_[%w_]+:%s*", "", 1)
            if n == 0 then break end
            out = trimmed
        end
        while true do
            local trimmed, n = string.gsub(out, "^lower_surface_to_elab_[%w_]+:%s*", "", 1)
            if n == 0 then break end
            out = trimmed
        end
        while true do
            local trimmed, n = string.gsub(out, "^resolve_sem_layout:%s*", "", 1)
            if n == 0 then break end
            out = trimmed
        end
        while true do
            local trimmed, n = string.gsub(out, "^lower_sem_to_back[_%w]*:%s*", "", 1)
            if n == 0 then break end
            out = trimmed
        end
        while true do
            local trimmed, n = string.gsub(out, "^lower_elab_to_sem:%s*", "", 1)
            if n == 0 then break end
            out = trimmed
        end
        if path ~= nil and path ~= "" then
            local prefix = path .. ": "
            while string.sub(out, 1, #prefix) == prefix do
                out = string.sub(out, #prefix + 1)
            end
        end
        return out
    end

    local function attach_diag_context(diag, stage, spans, fallback_path, module_name)
        local path, span = best_span_for_message(spans, diag.path or fallback_path, diag.message)
        if path ~= nil then
            diag.path = path
        elseif diag.path == nil then
            diag.path = fallback_path
        end
        if span ~= nil then
            diag.source_span = span
            if diag.line == nil or diag.line == 0 then
                diag.line = span.line
            end
            if diag.col == nil or diag.col == 0 then
                diag.col = span.col
            end
            if diag.offset == nil then
                diag.offset = span.offset
            end
            if diag.finish == nil then
                diag.finish = span.finish
            end
        end
        if stage ~= nil and diag.stage == nil then
            diag.stage = stage
        end
        if module_name ~= nil and module_name ~= "" and diag.module_name == nil then
            diag.module_name = module_name
        end
        diag.message = normalize_diag_message(diag.message, diag.path or fallback_path)
        return diag
    end

    local function annotate_stage_error(stage, err, spans, fallback_path, module_name)
        local diag = Parse.as_diag(err)
        if diag ~= nil then
            return attach_diag_context(diag, stage, spans, fallback_path, module_name)
        end
        local message = tostring(err)
        local path, span = best_span_for_message(spans, fallback_path, message)
        local out = Parse.new_diag(stage, span and span.line or 0, span and span.col or 0, message, span and span.offset or nil, span and span.finish or nil)
        out.path = path
        out.source_span = span
        out.stage = stage
        out.module_name = module_name
        out.cause = err
        return attach_diag_context(out, stage, spans, fallback_path, module_name)
    end

    local function lower_type_text(text, env)
        return pvm.one(SurfaceToElabLoop.lower_type(Parse.parse_type(text), default_elab_env(env, "")))
    end

    local function lower_module_with_spans_text(text, env)
        local surface, spans = Parse.parse_module_with_spans(text)
        local Desugar = require("moonlift.desugar_closures")
        surface = Desugar.desugar(surface, Surf)
        local elab = pvm.one(SurfaceToElabTop.lower_module(surface, default_elab_env(env, "")))
        return elab, spans, surface
    end

    local function lower_type_with_spans_text(text, env)
        local surface, spans = Parse.parse_type_with_spans(text)
        return pvm.one(SurfaceToElabLoop.lower_type(surface, default_elab_env(env, ""))), spans, surface
    end

    local function lower_expr_with_spans_text(text, env, expected_ty)
        local surface, spans = Parse.parse_expr_with_spans(text)
        return pvm.one(SurfaceToElabLoop.lower_expr(surface, default_elab_env(env, ""), expected_ty)), spans, surface
    end

    local function lower_stmt_with_spans_text(text, env, path)
        local surface, spans = Parse.parse_stmt_with_spans(text)
        return pvm.one(SurfaceToElabLoop.lower_stmt(surface, default_elab_env(env, ""), path)), spans, surface
    end

    local function lower_item_with_spans_text(text, env)
        local surface, spans = Parse.parse_item_with_spans(text)
        return pvm.one(SurfaceToElabTop.lower_item(surface, default_elab_env(env, ""))), spans, surface
    end

    local function lower_expr_text(text, env, expected_ty)
        return pvm.one(SurfaceToElabLoop.lower_expr(Parse.parse_expr(text), default_elab_env(env, ""), expected_ty))
    end

    local function lower_stmt_text(text, env, path)
        return pvm.one(SurfaceToElabLoop.lower_stmt(Parse.parse_stmt(text), default_elab_env(env, ""), path))
    end

    local function lower_item_text(text, env)
        return pvm.one(SurfaceToElabTop.lower_item(Parse.parse_item(text), default_elab_env(env, "")))
    end

    local function lower_module_text(text, env)
        local module = Parse.parse_module(text)
        local Desugar = require("moonlift.desugar_closures")
        module = Desugar.desugar(module, Surf)
        return pvm.one(SurfaceToElabTop.lower_module(module, default_elab_env(env, "")))
    end

    local function sem_module_text(text, env, const_env)
        return pvm.one(ElabToSem.lower_module(lower_module_text(text, env), default_const_env(const_env)))
    end

    local function sem_module_with_spans_text(text, env, const_env)
        local elab, spans, surface = lower_module_with_spans_text(text, env)
        return pvm.one(ElabToSem.lower_module(elab, default_const_env(const_env))), spans, surface, elab
    end

    local function layout_module_text(text, env, const_env, layout_env)
        return pvm.one(resolve_api().synthesize_layout_env(
            sem_module_text(text, env, const_env),
            default_layout_env(layout_env)
        ))
    end

    local function layout_module_with_spans_text(text, env, const_env, layout_env)
        local sem, spans, surface, elab = sem_module_with_spans_text(text, env, const_env)
        return pvm.one(resolve_api().synthesize_layout_env(sem, default_layout_env(layout_env))), spans, surface, elab, sem
    end

    local function resolve_module_text(text, env, const_env, layout_env)
        local sem = sem_module_text(text, env, const_env)
        return pvm.one(resolve_api().resolve_module(sem, default_layout_env(layout_env)))
    end

    local function resolve_module_with_spans_text(text, env, const_env, layout_env)
        local sem, spans, surface, elab = sem_module_with_spans_text(text, env, const_env)
        local use_layout_env = pvm.one(resolve_api().synthesize_layout_env(sem, default_layout_env(layout_env)))
        return pvm.one(resolve_api().resolve_module(sem, default_layout_env(layout_env))), spans, surface, elab, sem, use_layout_env
    end

    local function back_text(text, env, const_env, layout_env)
        local sem = sem_module_text(text, env, const_env)
        local use_layout_env = pvm.one(resolve_api().synthesize_layout_env(sem, default_layout_env(layout_env)))
        local resolved = pvm.one(resolve_api().resolve_module(sem, default_layout_env(layout_env)))
        return pvm.one(back_api().lower_module(resolved, use_layout_env))
    end

    local function back_with_spans_text(text, env, const_env, layout_env)
        local resolved, spans, surface, elab, sem, use_layout_env = resolve_module_with_spans_text(text, env, const_env, layout_env)
        return pvm.one(back_api().lower_module(resolved, use_layout_env)), spans, surface, elab, sem, resolved, use_layout_env
    end

    local function pipeline_text(text, env, const_env, layout_env)
        local surface = Parse.parse_module(text)
        local Desugar = require("moonlift.desugar_closures")
        surface = Desugar.desugar(surface, Surf)
        local elab_env = default_elab_env(env, "")
        local use_const_env = default_const_env(const_env)
        local elab = pvm.one(SurfaceToElabTop.lower_module(surface, elab_env))
        local sem = pvm.one(ElabToSem.lower_module(elab, use_const_env))
        local resolved_layout_env = pvm.one(resolve_api().synthesize_layout_env(sem, default_layout_env(layout_env)))
        return {
            surface = surface,
            elab = elab,
            sem = sem,
            layout_env = resolved_layout_env,
        }
    end

    local function pipeline_with_spans_text(text, env, const_env, layout_env)
        local surface, spans = Parse.parse_module_with_spans(text)
        local Desugar = require("moonlift.desugar_closures")
        surface = Desugar.desugar(surface, Surf)
        local elab_env = default_elab_env(env, "")
        local use_const_env = default_const_env(const_env)
        local elab = pvm.one(SurfaceToElabTop.lower_module(surface, elab_env))
        local sem = pvm.one(ElabToSem.lower_module(elab, use_const_env))
        local resolved_layout_env = pvm.one(resolve_api().synthesize_layout_env(sem, default_layout_env(layout_env)))
        return {
            surface = surface,
            spans = spans,
            elab = elab,
            sem = sem,
            layout_env = resolved_layout_env,
        }
    end

    local function compile_text(text, env, const_env, layout_env, jit)
        local back = back_text(text, env, const_env, layout_env)
        local use_jit = jit or jit_api().jit()
        local artifact = use_jit:compile(back)
        return artifact, use_jit
    end

    local function build_named_module_stage(module_name, sources, order, cache, visiting, env, const_env, layout_env, import_site)
        local cached = cache[module_name]
        if cached ~= nil then return cached end
        if visiting[module_name] then
            error(annotate_stage_error(
                "resolve",
                "cyclic module import at '" .. module_name .. "'",
                import_site and import_site.spans or nil,
                import_site and import_site.path or "module",
                import_site and import_site.module_name or nil
            ), 0)
        end
        local text = sources[module_name]
        if text == nil then
            error(annotate_stage_error(
                "resolve",
                "unknown imported module '" .. module_name .. "'",
                import_site and import_site.spans or nil,
                import_site and import_site.path or "module",
                import_site and import_site.module_name or nil
            ), 0)
        end

        local ctx = {
            stage = "parse",
            spans = nil,
        }

        visiting[module_name] = true
        local ok, stage = xpcall(function()
            local surface
            ctx.stage = "parse"
            surface, ctx.spans = Parse.parse_module_with_spans(text)
            local Desugar = require("moonlift.desugar_closures")
            surface = Desugar.desugar(surface, Surf)
            local import_specs = collect_surface_imports(surface)
            local imports = {}
            for i = 1, #import_specs do
                imports[i] = import_specs[i].module_name
            end

            local imported_elab_env = Elab.ElabEnv("", {}, {}, {})
            local imported_elab_const_env = Elab.ElabConstEnv({})
            local imported_sem_const_env = Sem.SemConstEnv({})
            local imported_layout_env = Sem.SemLayoutEnv({})

            ctx.stage = "resolve"
            for i = 1, #import_specs do
                local imported = import_specs[i]
                local dep = build_named_module_stage(imported.module_name, sources, order, cache, visiting, env, const_env, layout_env, {
                    module_name = module_name,
                    spans = ctx.spans,
                    path = imported.path,
                })
                imported_elab_env = merge_elab_env(imported_elab_env, dep.export_elab_env, "")
                imported_elab_const_env = merge_elab_const_env(imported_elab_const_env, dep.export_elab_const_env)
                imported_sem_const_env = merge_sem_const_env(imported_sem_const_env, dep.export_sem_const_env)
                imported_layout_env = merge_layout_env(imported_layout_env, dep.export_layout_env)
            end

            local module_elab_env = merge_elab_env(default_elab_env(env, module_name), imported_elab_env, module_name)
            local module_const_env = merge_elab_const_env(default_const_env(const_env), imported_elab_const_env)
            local module_layout_base = merge_layout_env(default_layout_env(layout_env), imported_layout_env)

            ctx.stage = "lower"
            local elab = pvm.one(SurfaceToElabTop.lower_module(surface, module_elab_env))
            ctx.stage = "sem"
            local sem = pvm.one(ElabToSem.lower_module(elab, module_const_env))
            ctx.stage = "layout"
            local module_layout_env = pvm.one(resolve_api().synthesize_layout_env(sem, module_layout_base))
            ctx.stage = "resolve"
            local resolved = pvm.one(resolve_api().resolve_module(sem, module_layout_base))

            return {
                name = module_name,
                text = text,
                spans = ctx.spans,
                imports = imports,
                import_specs = import_specs,
                surface = surface,
                elab = elab,
                sem = sem,
                resolved = resolved,
                layout_env = module_layout_env,
                import_elab_env = imported_elab_env,
                import_elab_const_env = imported_elab_const_env,
                import_sem_const_env = imported_sem_const_env,
                import_layout_env = imported_layout_env,
                export_elab_env = exported_elab_env(elab),
                export_elab_const_env = merge_elab_const_env(imported_elab_const_env, exported_elab_const_env(elab)),
                export_sem_const_env = merge_sem_const_env(imported_sem_const_env, exported_sem_const_env(sem)),
                export_layout_env = module_layout_env,
            }
        end, function(err)
            return annotate_stage_error(ctx.stage, err, ctx.spans, "module", module_name)
        end)
        visiting[module_name] = nil
        if not ok then
            error(stage, 0)
        end
        cache[module_name] = stage
        order[#order + 1] = stage
        return stage
    end

    local function pipeline_package_text(modules, env, const_env, layout_env)
        local names, sources = normalize_named_modules(modules)
        local order = {}
        local cache = {}
        local visiting = {}
        for i = 1, #names do
            build_named_module_stage(names[i], sources, order, cache, visiting, env, const_env, layout_env)
        end
        return {
            modules = order,
            module_map = cache,
        }
    end

    local function back_package_text(modules, env, const_env, layout_env)
        local stages = pipeline_package_text(modules, env, const_env, layout_env)
        local cmds = {}
        for i = 1, #stages.modules do
            local stage = stages.modules[i]
            local ok, plan = xpcall(function()
                return pvm.one(back_api().lower_module_plan(stage.resolved, stage.layout_env, stage.import_sem_const_env))
            end, function(err)
                return annotate_stage_error("back", err, stage.spans, "module", stage.name)
            end)
            if not ok then
                error(plan, 0)
            end
            for j = 1, #plan.cmds do
                cmds[#cmds + 1] = plan.cmds[j]
            end
        end
        cmds[#cmds + 1] = Back.BackCmdFinalizeModule
        return Back.BackProgram(cmds), stages
    end

    local function compile_package_text(modules, env, const_env, layout_env, jit)
        local back, stages = back_package_text(modules, env, const_env, layout_env)
        local use_jit = jit or jit_api().jit()
        local artifact = use_jit:compile(back)
        return artifact, use_jit, stages
    end

    local function try_pipeline_text(text, env, const_env, layout_env)
        local ctx = { stage = "parse", spans = nil }
        local ok, res = xpcall(function()
            local surface
            ctx.stage = "parse"
            surface, ctx.spans = Parse.parse_module_with_spans(text)
            local Desugar = require("moonlift.desugar_closures")
            surface = Desugar.desugar(surface, Surf)
            ctx.stage = "lower"
            local elab = pvm.one(SurfaceToElabTop.lower_module(surface, default_elab_env(env, "")))
            ctx.stage = "sem"
            local sem = pvm.one(ElabToSem.lower_module(elab, default_const_env(const_env)))
            ctx.stage = "layout"
            local resolved_layout_env = pvm.one(resolve_api().synthesize_layout_env(sem, default_layout_env(layout_env)))
            return {
                surface = surface,
                spans = ctx.spans,
                elab = elab,
                sem = sem,
                layout_env = resolved_layout_env,
            }
        end, function(err)
            return annotate_stage_error(ctx.stage, err, ctx.spans, "module")
        end)
        if ok then return res, nil end
        return nil, res
    end

    local function try_back_text(text, env, const_env, layout_env)
        local ctx = { stage = "parse", spans = nil }
        local ok, res = xpcall(function()
            local surface
            ctx.stage = "parse"
            surface, ctx.spans = Parse.parse_module_with_spans(text)
            local Desugar = require("moonlift.desugar_closures")
            surface = Desugar.desugar(surface, Surf)
            ctx.stage = "lower"
            local elab = pvm.one(SurfaceToElabTop.lower_module(surface, default_elab_env(env, "")))
            ctx.stage = "sem"
            local sem = pvm.one(ElabToSem.lower_module(elab, default_const_env(const_env)))
            ctx.stage = "layout"
            local use_layout_env = pvm.one(resolve_api().synthesize_layout_env(sem, default_layout_env(layout_env)))
            ctx.stage = "resolve"
            local resolved = pvm.one(resolve_api().resolve_module(sem, default_layout_env(layout_env)))
            ctx.stage = "back"
            return pvm.one(back_api().lower_module(resolved, use_layout_env))
        end, function(err)
            return annotate_stage_error(ctx.stage, err, ctx.spans, "module")
        end)
        if ok then return res, nil end
        return nil, res
    end

    local function try_compile_text(text, env, const_env, layout_env, jit)
        local ctx = { stage = "parse", spans = nil }
        local ok, artifact, use_jit = xpcall(function()
            local surface
            ctx.stage = "parse"
            surface, ctx.spans = Parse.parse_module_with_spans(text)
            local Desugar = require("moonlift.desugar_closures")
            surface = Desugar.desugar(surface, Surf)
            ctx.stage = "lower"
            local elab = pvm.one(SurfaceToElabTop.lower_module(surface, default_elab_env(env, "")))
            ctx.stage = "sem"
            local sem = pvm.one(ElabToSem.lower_module(elab, default_const_env(const_env)))
            ctx.stage = "layout"
            local use_layout_env = pvm.one(resolve_api().synthesize_layout_env(sem, default_layout_env(layout_env)))
            ctx.stage = "resolve"
            local resolved = pvm.one(resolve_api().resolve_module(sem, default_layout_env(layout_env)))
            ctx.stage = "back"
            local back = pvm.one(back_api().lower_module(resolved, use_layout_env))
            ctx.stage = "compile"
            local api = jit or jit_api().jit()
            return api:compile(back), api
        end, function(err)
            return annotate_stage_error(ctx.stage, err, ctx.spans, "module")
        end)
        if ok then return artifact, use_jit, nil end
        return nil, nil, artifact
    end

    return {
        lex = Parse.lex,
        new_diag = Parse.new_diag,
        as_diag = Parse.as_diag,

        parse_module = Parse.parse_module,
        parse_item = Parse.parse_item,
        parse_expr = Parse.parse_expr,
        parse_stmt = Parse.parse_stmt,
        parse_type = Parse.parse_type,
        parse_module_with_spans = Parse.parse_module_with_spans,
        parse_item_with_spans = Parse.parse_item_with_spans,
        parse_expr_with_spans = Parse.parse_expr_with_spans,
        parse_stmt_with_spans = Parse.parse_stmt_with_spans,
        parse_type_with_spans = Parse.parse_type_with_spans,

        try_parse_module = Parse.try_parse_module,
        try_parse_item = Parse.try_parse_item,
        try_parse_expr = Parse.try_parse_expr,
        try_parse_stmt = Parse.try_parse_stmt,
        try_parse_type = Parse.try_parse_type,

        lower_type = lower_type_text,
        lower_expr = lower_expr_text,
        lower_stmt = lower_stmt_text,
        lower_item = lower_item_text,
        lower_module = lower_module_text,
        lower_type_with_spans = lower_type_with_spans_text,
        lower_expr_with_spans = lower_expr_with_spans_text,
        lower_stmt_with_spans = lower_stmt_with_spans_text,
        lower_item_with_spans = lower_item_with_spans_text,
        lower_module_with_spans = lower_module_with_spans_text,
        try_lower_type = function(text, env)
            local spans
            local ok, res = xpcall(function()
                local value
                value, spans = Parse.parse_type_with_spans(text)
                return pvm.one(SurfaceToElabLoop.lower_type(value, default_elab_env(env, "")))
            end, function(err)
                return annotate_stage_error("lower", err, spans, "type")
            end)
            if ok then return res, nil end
            return nil, res
        end,
        try_lower_expr = function(text, env, expected_ty)
            local spans
            local ok, res = xpcall(function()
                local value
                value, spans = Parse.parse_expr_with_spans(text)
                return pvm.one(SurfaceToElabLoop.lower_expr(value, default_elab_env(env, ""), expected_ty))
            end, function(err)
                return annotate_stage_error("lower", err, spans, "expr")
            end)
            if ok then return res, nil end
            return nil, res
        end,
        try_lower_stmt = function(text, env, path)
            local spans
            local fallback_path = path or "stmt"
            local ok, res = xpcall(function()
                local value
                value, spans = Parse.parse_stmt_with_spans(text)
                return pvm.one(SurfaceToElabLoop.lower_stmt(value, default_elab_env(env, ""), fallback_path))
            end, function(err)
                return annotate_stage_error("lower", err, spans, fallback_path)
            end)
            if ok then return res, nil end
            return nil, res
        end,
        try_lower_item = function(text, env)
            local spans
            local ok, res = xpcall(function()
                local value
                value, spans = Parse.parse_item_with_spans(text)
                return pvm.one(SurfaceToElabTop.lower_item(value, default_elab_env(env, "")))
            end, function(err)
                return annotate_stage_error("lower", err, spans, "item")
            end)
            if ok then return res, nil end
            return nil, res
        end,
        try_lower_module = function(text, env)
            local spans
            local ok, res = xpcall(function()
                local value
                value, spans = Parse.parse_module_with_spans(text)
                local Desugar = require("moonlift.desugar_closures")
                value = Desugar.desugar(value, Surf)
                return pvm.one(SurfaceToElabTop.lower_module(value, default_elab_env(env, "")))
            end, function(err)
                return annotate_stage_error("lower", err, spans, "module")
            end)
            if ok then return res, nil end
            return nil, res
        end,

        sem_module = sem_module_text,
        sem_module_with_spans = sem_module_with_spans_text,
        layout_module = layout_module_text,
        layout_module_with_spans = layout_module_with_spans_text,
        resolve_module = resolve_module_text,
        resolve_module_with_spans = resolve_module_with_spans_text,

        -- Canonical authored front door for single-module source text.
        pipeline = pipeline_text,
        pipeline_with_spans = pipeline_with_spans_text,
        back = back_text,
        back_with_spans = back_with_spans_text,
        compile = compile_text,

        pipeline_package = pipeline_package_text,
        back_package = back_package_text,
        compile_package = compile_package_text,
        try_pipeline = try_pipeline_text,
        try_back = try_back_text,
        try_compile = try_compile_text,
        try_sem_module = function(text, env, const_env)
            local ctx = { stage = "parse", spans = nil }
            local ok, res = xpcall(function()
                local surface
                ctx.stage = "parse"
                surface, ctx.spans = Parse.parse_module_with_spans(text)
                local Desugar = require("moonlift.desugar_closures")
                surface = Desugar.desugar(surface, Surf)
                ctx.stage = "lower"
                local elab = pvm.one(SurfaceToElabTop.lower_module(surface, default_elab_env(env, "")))
                ctx.stage = "sem"
                return pvm.one(ElabToSem.lower_module(elab, default_const_env(const_env)))
            end, function(err)
                return annotate_stage_error(ctx.stage, err, ctx.spans, "module")
            end)
            if ok then return res, nil end
            return nil, res
        end,
        try_resolve_module = function(text, env, const_env, layout_env)
            local ctx = { stage = "parse", spans = nil }
            local ok, res = xpcall(function()
                local surface
                ctx.stage = "parse"
                surface, ctx.spans = Parse.parse_module_with_spans(text)
                local Desugar = require("moonlift.desugar_closures")
                surface = Desugar.desugar(surface, Surf)
                ctx.stage = "lower"
                local elab = pvm.one(SurfaceToElabTop.lower_module(surface, default_elab_env(env, "")))
                ctx.stage = "sem"
                local sem = pvm.one(ElabToSem.lower_module(elab, default_const_env(const_env)))
                ctx.stage = "layout"
                pvm.one(resolve_api().synthesize_layout_env(sem, default_layout_env(layout_env)))
                ctx.stage = "resolve"
                return pvm.one(resolve_api().resolve_module(sem, default_layout_env(layout_env)))
            end, function(err)
                return annotate_stage_error(ctx.stage, err, ctx.spans, "module")
            end)
            if ok then return res, nil end
            return nil, res
        end,
        try_pipeline_package = function(modules, env, const_env, layout_env)
            local ok, res = xpcall(function()
                return pipeline_package_text(modules, env, const_env, layout_env)
            end, function(err)
                return annotate_stage_error("pipeline", err, nil, "module")
            end)
            if ok then return res, nil end
            return nil, res
        end,
        try_back_package = function(modules, env, const_env, layout_env)
            local ok, back, stages = xpcall(function()
                return back_package_text(modules, env, const_env, layout_env)
            end, function(err)
                return annotate_stage_error("back", err, nil, "module")
            end)
            if ok then return back, stages, nil end
            return nil, nil, back
        end,
        try_compile_package = function(modules, env, const_env, layout_env, jit)
            local ok, artifact, use_jit, stages = xpcall(function()
                local back, built_stages = back_package_text(modules, env, const_env, layout_env)
                local api = jit or jit_api().jit()
                return api:compile(back), api, built_stages
            end, function(err)
                return annotate_stage_error("compile", err, nil, "module")
            end)
            if ok then return artifact, use_jit, stages, nil end
            return nil, nil, nil, artifact
        end,
        jit = function() return jit_api().jit() end,
    }
end

return M
