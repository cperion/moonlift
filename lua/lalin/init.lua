-- Public Lalin Lua facade.
--
-- Entry API:
--   lalin.loadstring(src [, name])  — load a .lln value chunk from a string
--   lalin.loadfile(path)            — load a .lln value chunk from a file
--   lalin.dofile(path, ...)         — load and immediately execute a .lln file
--   lalin.require(name)             — require a .lln module through lalin.path
--   lalin.install_searcher()        — let Lua require() discover .lln modules
--   lalin.format(value [, opts])    — canonical format for evaluated DSL values
--   lalin.format_file(path [, opts]) — evaluate a format-owned file and render it
--
-- DSL source loading lives under lalin.dsl.
--
-- Object emission (hosted pipeline):
--   lalin.emit_c_artifact(decl [, opts])
--   lalin.emit_luajit_artifact(decl [, path_or_opts [, name [, opts]]])
--
-- Low-level modules are exposed for direct use.

local M = {}

M.pvm = require("lalin.pvm")
M.triplet = require("lalin.triplet")
M.schema_context = require("lalin.schema_context")
M.schema_projection_model = require("lalin.schema_projection_model")
M.schema = require("lalin.schema")
M.schema_projection = require("lalin.schema_projection")
M.context_define_schema = require("lalin.context_define_schema")
M.phase_model = require("lalin.phase_model")
M.phase_dsl = require("lalin.phase_dsl")
M.phase_validate = require("lalin.phase_validate")
M.phase_plan = require("lalin.phase_plan")
M.phase_execute = require("lalin.phase_execute")
M.compiler_package = require("lalin.compiler_package")
M.compiler_model = require("lalin.compiler_model")
M.compiler_driver = require("lalin.compiler_driver")
M.flatline = require("lalin.flatline")
M.ast = require("lalin.ast")
M.dsl = require("lalin.dsl")
M.syntax = require("lalin.syntax")
M.loader = require("lalin.loader")
M.path = M.loader.path
M.lalin = M.dsl.namespace()
M.lln = M.dsl.namespace { name = "lln" }
M.back_program = require("lalin.back_program")
M.back_target_model = require("lalin.back_target_model")
M.back_inspect = require("lalin.back_inspect")
M.link_target_model = require("lalin.link_target_model")
M.link_plan_validate = require("lalin.link_plan_validate")
M.link_command_plan = require("lalin.link_command_plan")
M.link_execute = require("lalin.link_execute")
M.code_type = require("lalin.code_type")
M.code_validate = require("lalin.code_validate")
M.tree_to_code = require("lalin.tree_to_code")
M.code_to_c = require("lalin.code_to_c")
M.code_to_back = require("lalin.code_to_back")
M.exec_plan = require("lalin.exec_plan")
M.stencil_rules = require("lalin.stencil_rules")
M.stencil_artifact_plan = require("lalin.stencil_artifact_plan")
M.c_validate = require("lalin.c_validate")
M.c_emit = require("lalin.c_emit")
M.c_helpers = require("lalin.c_helpers")
M.c_tcc = require("lalin.c_tcc")


local llbl = require("llbl")
local llpvm_dsl = require("llpvm.dsl")
local schema_dsl = require("lalin.schema.dsl")
M.schema_dsl = schema_dsl
M.schema_namespace = schema_dsl.namespace()

local function family_add_error(bag, err, value, code)
    if llbl.is(err, "Diagnostic") then return bag:add(err) end
    return bag:error {
        code = code or "E_FAMILY_TOOL",
        message = tostring(err),
        primary = llbl.origin_of(value),
    }
end

local function is_lalin_decl(value)
    local mt = type(value) == "table" and getmetatable(value) or nil
    return mt and rawget(mt, "__dsl_class") == "Decl"
end

local function is_lalin_parsed_decl(value)
    return type(value) == "table" and type(value.tag) == "string" and value.tag:match("^Decl") ~= nil
end

local function parsed_decls_from(value)
    if is_lalin_parsed_decl(value) then return { value } end
    if type(value) ~= "table" then return nil end
    local out = {}
    local n = #value
    for i = 1, n do
        if not is_lalin_parsed_decl(value[i]) then return nil end
        out[#out + 1] = value[i]
    end
    for k, v in pairs(value) do
        if type(k) ~= "number" then
            if is_lalin_parsed_decl(v) then
                if type(k) == "string" and v.name == nil then
                    v.public_name = v.public_name or k
                    v.debug_name = v.debug_name or k
                    v.name = k
                end
                out[#out + 1] = v
            end
        end
    end
    if #out == 0 then return nil end
    return out
end

local function is_llpvm_value(value)
    local mt = type(value) == "table" and getmetatable(value) or nil
    return mt == llpvm_dsl.ProgramSpec or mt == llpvm_dsl.ProgramImage or mt == llpvm_dsl.TaskSpec
end

local function is_schema_value(value)
    return schema_dsl.is_schema_value(value)
end

local function collect_schema_values(out, value, seen)
    if type(value) ~= "table" then return out end
    seen = seen or {}
    if seen[value] then return out end
    seen[value] = true
    if is_schema_value(value) then
        out[#out + 1] = value
        return out
    end
    if llbl.is(value, "Zone") then
        if value.member == "lalinschema.dsl" or value.name == "schema" or value.name == "lalinschema" then
            for _, item in ipairs(value.items or {}) do collect_schema_values(out, item, seen) end
        end
        return out
    end
    if llbl.is(value, "LanguageBundle") then
        for _, z in ipairs(value.zones or {}) do collect_schema_values(out, z, seen) end
        return out
    end
    for i = 1, #value do collect_schema_values(out, value[i], seen) end
    for k, v in pairs(value) do if type(k) ~= "number" then collect_schema_values(out, v, seen) end end
    return out
end

local function collect_llpvm_values(out, value, seen)
    if type(value) ~= "table" then return out end
    seen = seen or {}
    if seen[value] then return out end
    seen[value] = true
    if is_llpvm_value(value) then
        out[#out + 1] = value
        return out
    end
    if llbl.is(value, "Zone") then
        if value.member == "llpvm.dsl" or value.name == "llpvm" then
            for _, item in ipairs(value.items or {}) do collect_llpvm_values(out, item, seen) end
        end
        return out
    end
    if llbl.is(value, "LanguageBundle") then
        for _, z in ipairs(value.zones or {}) do collect_llpvm_values(out, z, seen) end
        return out
    end
    for i = 1, #value do collect_llpvm_values(out, value[i], seen) end
    for k, v in pairs(value) do if type(k) ~= "number" then collect_llpvm_values(out, v, seen) end end
    return out
end

local function lalin_diagnostics(value, bag, opts, language)
    local zones = language:owned_zones(value, "lalin.dsl")
    local targets = #zones > 0 and zones or { value }
    for _, target in ipairs(targets) do
        local ok, unit = pcall(M.dsl.to_unit, opts and opts.name or "FamilyDiagnostics", target)
        if not ok then
            family_add_error(bag, unit, target, "E_LALIN_PROJECTION")
        else
            local ok_syntax, syntax_or_err = pcall(function() return unit:syntax() end)
            if not ok_syntax then
                family_add_error(bag, syntax_or_err, target, "E_LALIN_SYNTAX")
            else
                local ok_type, report = pcall(function() return unit:typecheck() end)
                if not ok_type then
                    family_add_error(bag, report, target, "E_LALIN_TYPECHECK")
                elseif type(report) == "table" and report.issues then
                    for i = 1, #report.issues do
                        bag:error {
                            code = "E_LALIN_TYPECHECK",
                            message = tostring(report.issues[i].message or report.issues[i]),
                            primary = llbl.origin_of(target),
                        }
                    end
                end
            end
        end
    end
    return bag
end

local function lalin_index(value, opts, language)
    local out = { symbols = {}, hovers = {}, diagnostics = {} }
    local zones = language:owned_zones(value, "lalin.dsl")
    local targets = #zones > 0 and zones or { value }
    for _, target in ipairs(targets) do
        local ok, unit = pcall(M.dsl.to_unit, opts and opts.name or "FamilyIndex", target)
        if ok and type(unit) == "table" and unit.body then
            for _, decl in ipairs(unit.body or {}) do
                if type(decl) == "table" and decl.name then
                    out.symbols[#out.symbols + 1] = {
                        name = tostring(decl.name),
                        kind = decl.kind or "lalin",
                        member = "lalin.dsl",
                        origin = llbl.origin_of(decl),
                    }
                end
            end
        else
            out.diagnostics[#out.diagnostics + 1] = llbl.diagnostic {
                code = "E_LALIN_INDEX",
                message = tostring(unit),
                primary = llbl.origin_of(target),
            }
        end
    end
    return out
end

local function llpvm_diagnostics(value, bag, opts, language)
    local targets = collect_llpvm_values({}, value)
    for _, target in ipairs(targets) do
        local ok, projected = pcall(llpvm_dsl.to_program, target)
        if not ok then
            family_add_error(bag, projected, target, "E_LLPVM_PROJECTION")
        elseif projected ~= nil then
            local mt = type(projected) == "table" and getmetatable(projected) or nil
            if mt == llpvm_dsl.ProgramSpec then
                local ok_bytecode, bytes_or_err = pcall(function() return projected:bytecode() end)
                if not ok_bytecode then
                    family_add_error(bag, bytes_or_err, target, "E_LLPVM_LOWER")
                else
                    for ev in llpvm_dsl.validate(bytes_or_err) do
                        if ev.kind == "diagnostic" then
                            bag:add(ev.diagnostic or llbl.diagnostic { code = ev.code, message = ev.message, primary = llbl.origin_of(target) })
                        end
                    end
                end
            elseif mt == llpvm_dsl.TaskSpec then
                local ok_task, err = pcall(function() return projected:asdl() end)
                if not ok_task then family_add_error(bag, err, target, "E_LLPVM_TASK") end
            end
        end
    end
    return bag
end

local function llpvm_index(value, opts, language)
    local out = { symbols = {}, hovers = {}, diagnostics = {} }
    local function visit(item)
        if type(item) == "table" and item.name then
            out.symbols[#out.symbols + 1] = {
                name = tostring(item.name),
                kind = "llpvm",
                member = "llpvm.dsl",
                origin = llbl.origin_of(item),
            }
        end
        if type(item) == "table" then
            for _, child in ipairs(item.body or {}) do visit(child) end
        end
    end
    for _, item in ipairs(collect_llpvm_values({}, value)) do visit(item) end
    return out
end

local function schema_diagnostics(value, bag, opts, language)
    local targets = collect_schema_values({}, value)
    if #targets == 0 then return bag end
    local modules = {}
    for _, target in ipairs(targets) do
        if schema_dsl.is_schema_value(target, "Module") then modules[#modules + 1] = target end
    end
    if #modules > 0 then
        local ok, err = pcall(function()
            local T = opts and opts.context or M.pvm.context()
            schema_dsl.to_asdl_schema(T, modules)
        end)
        if not ok then family_add_error(bag, err, value, "E_SCHEMA_PROJECTION") end
    end
    return bag
end

local function schema_index(value, opts, language)
    local out = { symbols = {}, hovers = {}, diagnostics = {} }
    local function visit(item, parent)
        if schema_dsl.is_schema_value(item, "Module") then
            out.symbols[#out.symbols + 1] = {
                name = tostring(item.name),
                kind = "schema",
                member = "lalinschema.dsl",
                origin = llbl.origin_of(item),
            }
            for _, decl in ipairs(item.decls or {}) do visit(decl, item.name) end
        elseif schema_dsl.is_schema_value(item, "Decl") then
            out.symbols[#out.symbols + 1] = {
                name = tostring(item.name),
                kind = tostring(item.kind or "schema"),
                member = "lalinschema.dsl",
                origin = llbl.origin_of(item),
                parent = parent,
            }
        end
    end
    for _, item in ipairs(collect_schema_values({}, value)) do visit(item) end
    return out
end

local function lalin_markdown(member, opts, language)
    return table.concat({
        "## lalin.dsl",
        "",
        "Lalin is the typed native language member of the language. It owns functions, regions, types, resources, and native compilation projection.",
        "",
        "Language source uses the `lln` namespace value for Lalin. `lalin` is the long alias. Call `lln { ... }` when a language value contains Lalin declarations.",
        "",
        "```lua",
        "lln {",
        "  lln.fn. add { a [lln.i32], b [lln.i32] } [lln.i32] {",
        "    lln.ret (a + b),",
        "  },",
        "}",
        "```",
        "",
        llbl.markdown_dialect(member.dialect, { level = 3, title = "Lalin LLBL Surface" }),
    }, "\n")
end

local function llpvm_markdown(member, opts, language)
    return table.concat({
        "## llpvm.dsl",
        "",
        "LLPVM is the low-level process/bytecode VM member of the Lalin language. It owns bytecode programs, task/process specs, validation, and inspection.",
        "",
        "Language source uses the `llpvm` namespace value. Call `llpvm { ... }` when a language value carries LLPVM programs next to Lalin declarations.",
        "",
        "```lua",
        "llpvm {",
        "  llpvm.task. compile {",
        "    llpvm.input [lln.i32],",
        "    llpvm.output [lln.i32],",
        "    llpvm.event. progress [lln.i32],",
        "  },",
        "}",
        "```",
        "",
        llbl.markdown_dialect(member.dialect, { level = 3, title = "LLPVM LLBL Surface" }),
    }, "\n")
end

local function schema_markdown(member, opts, language)
    return table.concat({
        "## lalinschema.dsl",
        "",
        "LalinSchema is the ASDL/schema member of the Lalin language. It owns typed schema declarations used to define the compiler language itself.",
        "",
        "In the full Lalin language, LalinSchema is exposed through the `schema` namespace value. Use `schema. Name { ... }` for modules, `schema.product`, `schema.sum`, `schema.alias`, `schema.field`, and schema helpers such as `schema.many`.",
        "",
        "```lua",
        "schema {",
        "  schema. Demo {",
        "    schema.product. Pair { schema.interned, left [LalinType.Type], right [LalinType.Type] },",
        "  },",
        "}",
        "```",
        "",
        llbl.markdown_dialect(member.dialect, { level = 3, title = "LalinSchema LLBL Surface" }),
    }, "\n")
end

M.language = llbl.language. lalin {
    prefer = {
        cache = "llpvm.dsl",
        entry = "llpvm.dsl",
        event = "llpvm.dsl",
        from = "llpvm.dsl",
        input = "llpvm.dsl",
        lang = "llpvm.dsl",
        language = "llpvm.dsl",
        llpvm = "llpvm.dsl",
        lln = "lalin.dsl",
        machine = "llpvm.dsl",
        lalin = "lalin.dsl",
        schema = "lalinschema.dsl",
        op = "llpvm.dsl",
        output = "llpvm.dsl",
        phase = "llpvm.dsl",
        pvm = "llpvm.dsl",
        record = "llpvm.dsl",
        root = "llpvm.dsl",
        tape = "llpvm.dsl",
        task = "llpvm.dsl",
        to = "llpvm.dsl",
        type = "llpvm.dsl",
        world = "llpvm.dsl",
    },
    shared = {
        "origin",
        "fragment",
        "generic-region",
        "type_value",
        "diagnostic",
        "process",
    },
    reserved = {
        "pvm",
        "lang",
        "type",
        "op",
        "world",
        "tape",
        "record",
        "machine",
        "phase",
        "task",
        "event",
        "input",
        "output",
        "root",
        "lln",
        "lalin",
        "llpvm",
        "schema",
    },
    {
        name = "lalin.dsl",
        dialect = M.dsl.language,
        exports = function(opts) return M.dsl.make_language_env(opts) end,
        match = is_lalin_decl,
        format = function(value, opts) return M.dsl.format(value, opts) end,
        diagnostics = lalin_diagnostics,
        index = lalin_index,
        markdown = lalin_markdown,
        provides = { "lalin.types", "lalin.dsl" },
        semantics = {
            owns = {
                "native-program",
                "native-region-lowering",
                "native-type-values",
                "resource-discipline",
                "native-compilation",
            },
            uses = {
                "authoring-substrate",
                "diagnostics",
                "language-composition",
                "fragments",
                "generic-region",
                "namespaces",
                "origins",
                "type-language",
            },
        },
    },
    {
        name = "lalinschema.dsl",
        dialect = schema_dsl.Dialect,
        exports = function(opts) return schema_dsl.make_language_env(opts) end,
        match = is_schema_value,
        format = function(value, opts) return schema_dsl.format(value, opts) end,
        diagnostics = schema_diagnostics,
        index = schema_index,
        markdown = schema_markdown,
        provides = { "lalinschema.dsl", "lalin.schema" },
        semantics = {
            owns = {
                "schema-modules",
                "type-language",
                "product-sum-schema",
                "schema-identity",
            },
            uses = {
                "authoring-substrate",
                "diagnostics",
                "language-composition",
                "fragments",
                "namespaces",
                "origins",
            },
        },
    },
    {
        name = "llpvm.dsl",
        dialect = llpvm_dsl.meta_language,
        exports = function(opts) return llpvm_dsl.make_language_env(opts) end,
        match = is_llpvm_value,
        format = function(value, opts) return llpvm_dsl.format(value, opts) end,
        diagnostics = llpvm_diagnostics,
        index = llpvm_index,
        markdown = llpvm_markdown,
        requires = { "lalin.types", "lalin.schema" },
        provides = { "llpvm.dsl" },
        semantics = {
            owns = {
                "bytecode-program",
                "bytecode-tape",
                "process-task",
                "pvm-image",
            },
            uses = {
                "authoring-substrate",
                "diagnostics",
                "language-composition",
                "fragments",
                "namespaces",
                "origins",
                "native-type-values",
                "type-language",
            },
        },
    },
}

--- Install Lalin DSL globals into _G so plain .lua files can use
-- fn, i32, unit, struct, region, etc. as unqualified names.
-- Call this once at the top of any .lua file that authors Lalin DSL.
--
--   require("lalin").use()       -- injects DSL globals into _G
--   fn. add { a [i32], b [i32] } [i32] { ret (a + b) }
--   return add
M.use = M.dsl.use
M.process = M.dsl.process
M.source = M.dsl.source

function M.markdown(opts)
    return M.language.markdown(opts)
end

function M.write_markdown(path, opts)
    return M.language.write_markdown(path, opts)
end

--- Canonical formatting for evaluated Lalin DSL values.

function M.format(value, opts)
    return M.dsl.format(value, opts)
end

function M.format_file(path, opts)
    return M.dsl.format_file(path, opts)
end

function M.write_format_file(path, opts)
    return M.dsl.write_format_file(path, opts)
end

--- Hosted .lln value loading.

function M.loadstring(src, chunk_name, opts)
    return M.loader.loadstring(src, chunk_name or "=(lalin .lln)", opts)
end

function M.loadfile(path, opts)
    return M.loader.loadfile(path, opts)
end

function M.dofile(path, opts, ...)
    local chunk, err = M.loadfile(path, opts)
    if not chunk then error(err, 2) end
    return chunk(...)
end

function M.eval(src, chunk_name, opts, ...)
    if type(chunk_name) == "table" and opts == nil then
        opts = chunk_name
        chunk_name = nil
    end
    local chunk, err = M.loadstring(src, chunk_name or "=(lalin eval)", opts)
    if not chunk then error(err, 2) end
    return chunk(...)
end

M.load = M.eval

function M.searchpath(name, path, sep, rep)
    return M.loader.searchpath(name, path or M.path, sep, rep)
end

local function facade_loader_opts(opts)
    opts = opts or {}
    if opts.path ~= nil then return opts end
    local copy = {}
    for k, v in pairs(opts) do copy[k] = v end
    copy.path = function() return M.path end
    return copy
end

function M.searcher(name, opts)
    return M.loader.searcher(name, facade_loader_opts(opts))
end

function M.install_searcher(opts)
    return M.loader.install_searcher(facade_loader_opts(opts))
end

function M.remove_searcher()
    return M.loader.remove_searcher()
end

function M.require(name, opts)
    return M.loader.require(name, facade_loader_opts(opts))
end

local function module_ast_from(value, name)
    local pvm = require("lalin.pvm")
    local ok, cls = pcall(pvm.classof, value)
    if ok and cls and tostring(cls) == "Class(LalinTree.Module)" then return value end
    local parsed_decls = parsed_decls_from(value)
    if parsed_decls then return M.syntax.to_module(parsed_decls, name) end
    if type(value) == "table" and type(value.ast) == "function" then
        local ast = value:ast()
        local ast_ok, ast_cls = pcall(pvm.classof, ast)
        if ast_ok and ast_cls and tostring(ast_cls) == "Class(LalinTree.Module)" then return ast end
        local unit = M.dsl.to_unit(name or "Unit", value)
        if type(unit.ast) == "function" then return unit:ast() end
        return unit
    end
    if type(value) == "table" and rawget(value, "__module_ast") ~= nil then return rawget(value, "__module_ast") end
    local projected = M.dsl.to_unit(name or "Unit", value)
    if type(projected.ast) == "function" then return projected:ast() end
    return projected
end

function M.unit(name, decls)
    return M.dsl.unit(name, decls)
end

function M.compile(name_or_decls, decls_or_opts, maybe_opts)
    local name, decls, opts
    if type(name_or_decls) == "string" then
        name = name_or_decls
        decls = decls_or_opts
        opts = maybe_opts or {}
    else
        decls = name_or_decls
        opts = decls_or_opts or {}
        name = opts.name or "Unit"
    end
    opts.name = opts.name or name
    local artifact = M.emit_luajit_artifact(decls, opts)
    local loader = loadstring or load
    local chunk, err = loader(artifact.source, "@" .. tostring(opts.name or name) .. ".luajit.lua")
    if chunk == nil then error(tostring(err), 2) end
    local module = chunk()
    if type(module) == "table" then
        rawset(module, "__lalin_artifact", artifact)
    end
    return module
end

function M.emit_c_artifact(decl, path_or_opts, name, opts)
    if type(path_or_opts) == "table" and opts == nil then
        opts = path_or_opts
        path_or_opts = nil
    end
    opts = opts or {}
    local pvm = require("lalin.pvm")
    local A2 = require("lalin.schema_projection")
    local Driver = require("lalin.compiler_driver")
    local CEmit = require("lalin.c_emit")

    local module_ast = module_ast_from(decl, name or opts.name or "lalin_c")
    local cls = pvm.classof(module_ast)
    local T = (cls and rawget(cls, "__context")) or pvm.context()
    if T.LalinCompiler == nil then A2(T) end
    local driver_opts = { site = "emit_c_artifact", root = "emit_c", context = T, c_opts = opts, c_target = opts.c_target, target = opts.target, name = name or opts.name }
    local c_unit = Driver.lower_module(module_ast, driver_opts)
    local artifact = CEmit(T).emit_artifact(c_unit, opts)
    function artifact:write(write_opts)
        write_opts = write_opts or {}
        if type(write_opts) == "string" then write_opts = { c_path = write_opts } end
        local function mkdir_parent(path)
            local dir = tostring(path):match("^(.*)/[^/]+$")
            if dir ~= nil and dir ~= "" then os.execute("mkdir -p '" .. dir:gsub("'", "'\\''") .. "'") end
        end
        local function write(path, text)
            mkdir_parent(path)
            local f = assert(io.open(path, "wb"))
            f:write(text or "")
            f:close()
        end
        if write_opts.c_path or write_opts.source_path then write(write_opts.c_path or write_opts.source_path, self.source) end
        if write_opts.h_path or write_opts.header_path then write(write_opts.h_path or write_opts.header_path, self.header) end
        if write_opts.support_path then write(write_opts.support_path, self.support) end
        if write_opts.combined_path or write_opts.single_path then write(write_opts.combined_path or write_opts.single_path, self.combined) end
        return self
    end
    if path_or_opts then artifact:write(path_or_opts) end
    if opts.c_path or opts.source_path or opts.h_path or opts.header_path or opts.support_path or opts.combined_path or opts.single_path then
        artifact:write(opts)
    end
    return artifact
end

local function prepare_luajit_artifact(decl, name, opts)
    opts = opts or {}
    name = name or opts.name or "lalin_luajit"
    local function sanitize(s)
        s = tostring(s or "x"):gsub("[^%w_]", "_")
        if s == "" then s = "x" end
        if s:match("^%d") then s = "_" .. s end
        return s
    end

    local pvm = require("lalin.pvm")
    local A2 = require("lalin.schema_projection")
    local module_ast = module_ast_from(decl, name)
    local cls = pvm.classof(module_ast)
    local T = (cls and rawget(cls, "__context")) or pvm.context()
    if T.LalinCompiler == nil or T.LalinLuaJIT == nil or T.LalinStencil == nil then A2(T) end

    local Pipeline = require("lalin.frontend_pipeline")(T)
    local Backend = require("lalin.luajit_backend")(T)
    local residual = tostring(opts.residual or "mc")
    if residual ~= "mc" and residual ~= "bc" then
        error("emit_luajit_artifact: unknown residual materializer " .. residual, 2)
    end
    local checked = Pipeline.typecheck_module(module_ast, {
        context = T,
        site = "emit_luajit_artifact:typecheck",
        name = name,
    })
    local code_result = Pipeline.checked_to_code_result(checked, {
        context = T,
        site = "emit_luajit_artifact:code",
        name = name,
    })

    local lj_module, facts, artifacts, rejects = Backend.lower_module(code_result.module, {
        contracts = code_result.contracts,
        graph = opts.graph,
        flow = opts.flow,
        value = opts.value,
        mem = opts.mem,
        effect = opts.effect,
        kernel = opts.kernel,
        target_model = opts.target_model,
        back_target_model = opts.back_target_model,
        target = opts.target,
        schedule = opts.schedule,
        schedule_plan = opts.schedule_plan,
        collect_rejects = opts.collect_rejects,
        residual = residual,
    })
    if opts.reject_on_stencil_rejects ~= false and rejects and #rejects > 0 then
        error("emit_luajit_artifact rejected module: " .. tostring(rejects[1].reason or rejects[1]), 2)
    end

    return {
        kind = "LuaJITArtifactPlan",
        name = name,
        residual = residual,
        sanitize = sanitize,
        module_ast = module_ast,
        checked = checked,
        code_result = code_result,
        backend = Backend,
        lj_module = lj_module,
        facts = facts,
        stencil_plan = facts.stencil_plan or facts.stencil,
        luajit_stencil_machines = facts.luajit_stencil_machines,
        exec_plan = facts.exec_plan or facts.exec,
        artifacts = artifacts,
        rejects = rejects,
    }
end

function M.plan_luajit_artifact(decl, opts)
    opts = opts or {}
    return prepare_luajit_artifact(decl, opts.name or "lalin_luajit", opts)
end

function M.emit_luajit_plan_artifact(plan, path_or_opts, name, opts)
    if type(path_or_opts) == "table" and opts == nil then
        opts = path_or_opts
        path_or_opts = nil
    end
    opts = opts or {}
    local path = path_or_opts or opts.path
    name = name or opts.name or plan.name or "lalin_luajit"

    local mc_bank = opts.mc_bank
    local bc_bank = opts.bc_bank
    local residual = plan.residual
    if mc_bank == nil and #(plan.artifacts or {}) > 0 and residual == "mc" then
        local reason = "emit_luajit_plan_artifact: residual='mc' requires a prebuilt MCStencilBank"
        if opts.allow_bc_fallback == false then error(reason, 2) end
        local warning = "luajit_backend: falling back from residual_mc to residual_bc: " .. reason
        if opts.collect_warnings ~= nil then opts.collect_warnings[#opts.collect_warnings + 1] = warning end
        if opts.on_warning ~= nil then opts.on_warning(warning)
        elseif opts.warn ~= nil then opts.warn(warning)
        elseif not opts.silent_warnings and not opts.quiet then io.stderr:write("warning: " .. warning .. "\n") end
        residual = "bc"
    end
    if bc_bank == nil and #(plan.artifacts or {}) > 0 and residual == "bc" then
        bc_bank = assert(plan.backend.build_bc_bank(plan.artifacts, {
            stem = opts.stem or plan.sanitize(name),
            id = opts.bc_bank_id,
            target = opts.bc_target,
        }))
    end

    local source, err = plan.backend.emit_lua_artifact(plan.lj_module, plan.artifacts, {
        mc_bank = mc_bank,
        bc_bank = bc_bank,
        path = path,
        chunk_name = opts.chunk_name or name,
        residual = residual,
        allow_bc_fallback = opts.allow_bc_fallback,
        collect_warnings = opts.collect_warnings,
        on_warning = opts.on_warning,
        warn = opts.warn,
        silent_warnings = true,
        native_residual = opts.native_residual,
        tcc_residual = opts.tcc_residual,
    })
    if source == nil then error(err or "emit_luajit_plan_artifact failed", 2) end

    local artifact = {
        kind = "LuaJITSourceArtifact",
        source = source,
        path = path,
        name = name,
        unit = plan.module_ast,
        checked = plan.checked,
        code_result = plan.code_result,
        lj_module = plan.lj_module,
        facts = plan.facts,
        stencil_plan = plan.stencil_plan,
        luajit_stencil_machines = plan.luajit_stencil_machines,
        exec_plan = plan.exec_plan,
        artifacts = plan.artifacts,
        rejects = plan.rejects,
        mc_bank = mc_bank,
        bc_bank = bc_bank,
        residual = residual,
        requested_residual = plan.residual,
        warnings = opts.collect_warnings,
    }
    function artifact:write(write_path)
        write_path = write_path or self.path
        assert(write_path, "emit_luajit_plan_artifact artifact:write requires a path")
        local dir = tostring(write_path):match("^(.*)/[^/]+$")
        if dir ~= nil and dir ~= "" then os.execute("mkdir -p '" .. dir:gsub("'", "'\\''") .. "'") end
        local f = assert(io.open(write_path, "wb"))
        f:write(self.source)
        f:close()
        self.path = write_path
        return self
    end
    return artifact
end

function M.emit_luajit_artifact(decl, path_or_opts, name, opts)
    if type(path_or_opts) == "table" and opts == nil then
        opts = path_or_opts
        path_or_opts = nil
    end
    opts = opts or {}
    local path = path_or_opts or opts.path
    name = name or opts.name or "lalin_luajit"

    local plan = prepare_luajit_artifact(decl, name, opts)
    return M.emit_luajit_plan_artifact(plan, path, name, opts)
end


function M.compile_c(decl, opts)
    opts = opts or {}
    local artifact = M.emit_c_artifact(decl, opts)
    if opts.c_path or opts.source_path or opts.h_path or opts.header_path or opts.support_path or opts.combined_path or opts.single_path then
        artifact:write(opts)
    end
    local c_src = artifact.combined
    local CTcc = require("lalin.c_tcc")
    if opts.runner == "libtcc" or opts.use_libtcc or os.getenv("LALIN_C_USE_LIBTCC") == "1" then
        local session, err = CTcc.compile(c_src, opts.libtcc_opts or { libraries = { "m" } })
        if not session then error(err and err.message or "libtcc compile failed", 2) end
        return session, c_src
    end
    return c_src
end

function M.context(opts)
    return M.pvm.context(opts)
end

local function bind_context(T)
    return require("lalin.schema_projection")(T)
end

return setmetatable(M, {
    __call = function(_, ...)
        return bind_context(...)
    end,
})
