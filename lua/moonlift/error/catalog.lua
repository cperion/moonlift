-- moonlift/error/catalog.lua
-- Error Catalog: the single source of truth for what each error means.
--
-- Every internal compiler issue kind maps to a catalog entry with:
--   - A stable, searchable error code (E0xxx)
--   - A severity level
--   - A build function that turns (issue, analysis_context) → ErrorReport
--
-- The build function is NOT a static string — it receives the full issue
-- and analysis context so it can produce rich, contextual reports with
-- source spans, secondary pointers, notes, and suggestions.

local Report = require("moonlift.error.report")
local Span = require("moonlift.error.span")
local Suggest = require("moonlift.error.suggest")

local M = {}

-------------------------------------------------------------------------------
-- Catalog entry
-------------------------------------------------------------------------------

local Entry = {}
Entry.__index = Entry

function M.entry(code, severity, build)
    return setmetatable({
        code = code,
        severity = severity,
        build = build,
    }, Entry)
end

-------------------------------------------------------------------------------
-- Type name formatting (replaces the scattered type_name functions)
-------------------------------------------------------------------------------

local scalar_labels = {
    ScalarVoid = "void", ScalarBool = "bool",
    ScalarI8 = "i8", ScalarI16 = "i16", ScalarI32 = "i32", ScalarI64 = "i64",
    ScalarU8 = "u8", ScalarU16 = "u16", ScalarU32 = "u32", ScalarU64 = "u64",
    ScalarF32 = "f32", ScalarF64 = "f64", ScalarRawPtr = "rawptr", ScalarIndex = "index",
}

local function type_name(ty)
    if not ty then return "<unknown>" end
    if type(ty) ~= "table" then return tostring(ty) end
    local pvm = require("moonlift.pvm")
    local cls = pvm.classof(ty)

    -- Check for ASDL types
    if cls then
        if scalar_labels[cls.kind] then return scalar_labels[cls.kind] end

        if cls.kind == "TScalar" then
            local scls = ty.scalar and pvm.classof(ty.scalar)
            return (scls and scalar_labels[scls.kind]) or cls.kind
        end
        if cls.kind == "TPtr" then return "ptr(" .. type_name(ty.elem) .. ")" end
        if cls.kind == "TView" then return "view(" .. type_name(ty.elem) .. ")" end
        if cls.kind == "TSlice" then return "slice(" .. type_name(ty.elem) .. ")" end
        if cls.kind == "TArray" then return "array(" .. type_name(ty.elem) .. ")" end
        if cls.kind == "TFunc" then return "func(...) -> " .. type_name(ty.result) end
        if cls.kind == "TClosure" then return "closure(...) -> " .. type_name(ty.result) end
        if cls.kind == "TNamed" then
            local ref = ty.ref
            if ref then
                local rcls = pvm.classof(ref)
                if rcls and rcls.kind == "TypeRefGlobal" then return ref.type_name end
                if rcls and rcls.kind == "TypeRefLocal" then return ref.sym and ref.sym.name or ref.sym end
                if rcls and rcls.kind == "TypeRefPath" and ref.path then
                    local parts = {}
                    for i = 1, #(ref.path.parts or {}) do parts[i] = ref.path.parts[i].text end
                    return table.concat(parts, ".")
                end
            end
        end
        return cls.kind
    end

    -- Fallback for simple tables
    if ty.scalar then return type_name(ty.scalar) end
    if ty.elem then return "ptr(" .. type_name(ty.elem) .. ")" end
    return tostring(ty)
end

M.type_name = type_name

-------------------------------------------------------------------------------
-- Operator symbol formatting
-------------------------------------------------------------------------------

local op_symbols = {
    BinAdd = "+", BinSub = "-", BinMul = "*", BinDiv = "/", BinRem = "%",
    BinBitAnd = "&", BinBitOr = "|", BinBitXor = "~", BinShl = "<<", BinLShr = ">>>", BinAShr = ">>",
    CmpEq = "==", CmpNe = "~=", CmpLt = "<", CmpLe = "<=", CmpGt = ">", CmpGe = ">=",
    LogicAnd = "&&", LogicOr = "||", UnaryNot = "not", UnaryNeg = "-", UnaryBitNot = "~",
    ["MoonCore.BinAdd"] = "+", ["MoonCore.BinSub"] = "-", ["MoonCore.BinMul"] = "*", ["MoonCore.BinDiv"] = "/", ["MoonCore.BinRem"] = "%",
    ["MoonCore.BinBitAnd"] = "&", ["MoonCore.BinBitOr"] = "|", ["MoonCore.BinBitXor"] = "~", ["MoonCore.BinShl"] = "<<", ["MoonCore.BinLShr"] = ">>>", ["MoonCore.BinAShr"] = ">>",
    ["MoonCore.CmpEq"] = "==", ["MoonCore.CmpNe"] = "~=", ["MoonCore.CmpLt"] = "<", ["MoonCore.CmpLe"] = "<=", ["MoonCore.CmpGt"] = ">", ["MoonCore.CmpGe"] = ">=",
    ["MoonCore.LogicAnd"] = "and", ["MoonCore.LogicOr"] = "or",
    ["MoonCore.UnaryNot"] = "not", ["MoonCore.UnaryNeg"] = "-", ["MoonCore.UnaryBitNot"] = "~",
}

local function op_symbol(op)
    if not op then return "?" end
    local s = tostring(op)
    if op_symbols[s] then return op_symbols[s] end
    -- Strip "MoonCore." prefix if present and retry
    local short = s:match("^MoonCore%.(.+)$")
    if short and op_symbols[short] then return op_symbols[short] end
    return s
end

-------------------------------------------------------------------------------
-- Fallback span from analysis context
-------------------------------------------------------------------------------

local function issue_span(issue, analysis)
    if issue.span then return issue.span end
    if issue.offset and analysis and analysis.source_text then
        local src = analysis.source_text
        local line_starts = {}
        local n = #src
        for i = 1, n do
            if string.byte(src, i) == 10 then line_starts[#line_starts + 1] = i + 1 end
        end
        table.insert(line_starts, 1, 1)
        local line = 1
        for i = 1, #line_starts do
            if line_starts[i] <= (issue.offset + 1) then line = i end
        end
        local col = (issue.offset + 1) - line_starts[line] + 1
        return Span.from_offsets(
            analysis.uri or "?",
            issue.offset, issue.offset + 1,
            line, col, line, col + 1
        )
    end
    return nil
end

-------------------------------------------------------------------------------
-- The Catalog
-------------------------------------------------------------------------------

M.entries = {}

local function register(code, severity, build)
    M.entries[code] = M.entry(code, severity, build)
end

local function lookup(code)
    return M.entries[code]
end

M.lookup = lookup

-------------------------------------------------------------------------------
-- E01xx: Parse Errors
-------------------------------------------------------------------------------

-- E0101: Unexpected token
register("E0101", "error", function(issue, analysis)
    local span = issue_span(issue, analysis)
    local msg = issue.message or "unexpected token"

    -- Enrich the message with construct context if available
    local notes = {}
    local suggestions = {}

    -- Detect common Moonlift-specific parse situations
    local m = msg:match("expected '(.-)', got")
    if m then
        -- "expected 'end', got end of input" → explain which construct is open
        if m == "end" then
            notes[#notes + 1] = { message = "an open construct has not been closed" }
            notes[#notes + 1] = { message = "check that every `region`, `func`, `if`, `switch`, or `block` has a matching `end`" }
        elseif m == "then" then
            notes[#notes + 1] = { message = "`if` and `case` expressions require `then` before the body" }
            suggestions[#suggestions + 1] = { message = "add `then` after the condition" }
        elseif m == "do" then
            notes[#notes + 1] = { message = "`switch` requires `do` before the first `case`: `switch expr do case ... end`" }
            suggestions[#suggestions + 1] = { message = "add `do` after the switch expression" }
        elseif m == "'='" then
            notes[#notes + 1] = { message = "assignment and block parameter initialization require `=`" }
        elseif m == "')'" then
            notes[#notes + 1] = { message = "there may be a missing comma or extra argument in this list" }
        end
    end

    return Report.new({
        code = "E0101",
        severity = "error",
        phase_context = "while parsing this file",
        primary = { span = span, message = msg },
        notes = notes,
        suggestions = suggestions,
    })
end)

-- E0102: Unterminated construct
register("E0102", "error", function(issue, analysis)
    local span = issue_span(issue, analysis)
    local construct = issue.construct or "construct"
    local name = issue.name or ""

    return Report.new({
        code = "E0102",
        severity = "error",
        phase_context = "while parsing this file",
        primary = {
            span = span,
            message = construct .. " " .. (name ~= "" and ("`" .. name .. "` ") or "") .. "is not terminated",
        },
        notes = {
            { message = "every " .. construct .. " must be closed with `end`" },
        },
        suggestions = {
            { message = "add `end` at the end of this " .. construct },
        },
    })
end)

-- E0103: Missing keyword
register("E0103", "error", function(issue, analysis)
    local span = issue_span(issue, analysis)
    local keyword = issue.keyword or issue.expected or "?"
    local context = issue.context or ""

    local notes = {}
    local suggestions = {}

    if keyword == "do" and context == "switch" then
        notes[#notes + 1] = { message = "`switch` requires `do` before the first `case`: `switch expr do case ... end`" }
        suggestions[#suggestions + 1] = { message = "write `switch ... do`" }
    elseif keyword == "then" then
        notes[#notes + 1] = { message = "`if` and `case` require `then` before the body" }
        suggestions[#suggestions + 1] = { message = "add `then` after the condition" }
    elseif keyword == "end" then
        notes[#notes + 1] = { message = "this construct must be closed with `end`" }
        suggestions[#suggestions + 1] = { message = "add `end` to close the " .. (context ~= "" and context or "construct") }
    else
        notes[#notes + 1] = { message = "expected `" .. keyword .. "` here" }
        suggestions[#suggestions + 1] = { message = "insert `" .. keyword .. "`" }
    end

    return Report.new({
        code = "E0103",
        severity = "error",
        phase_context = "while parsing this file",
        primary = {
            span = span,
            message = "expected `" .. keyword .. "`" .. (context ~= "" and (" in " .. context) or ""),
        },
        notes = notes,
        suggestions = suggestions,
    })
end)

-------------------------------------------------------------------------------
-- E02xx: Name Resolution
-------------------------------------------------------------------------------

-- E0201: Unresolved name
register("E0201", "error", function(issue, analysis)
    local span = issue_span(issue, analysis)
    local name = issue.name or "?"
    local candidates = issue.candidates or (analysis and analysis.in_scope_names) or {}
    local dym = Suggest.did_you_mean(name, candidates)

    local notes = {
        { message = "`" .. name .. "` is not defined in this scope" },
    }

    local suggestions = {}
    if dym then suggestions[#suggestions + 1] = { message = dym } end

    return Report.new({
        code = "E0201",
        severity = "error",
        phase_context = "while resolving names",
        primary = { span = span, message = "unresolved name `" .. name .. "`" },
        notes = notes,
        suggestions = suggestions,
    })
end)

-- E0202: Unresolved path
register("E0202", "error", function(issue, analysis)
    local span = issue_span(issue, analysis)
    local path_text = issue.path_text or "?"
    local first = issue.first_name or (path_text:match("^([%w_]+)"))

    local notes = {
        { message = "the path `" .. path_text .. "` could not be resolved" },
    }

    if first then
        local candidates = issue.candidates or (analysis and analysis.in_scope_names) or {}
        local dym = Suggest.did_you_mean(first, candidates)
        if dym then
            notes[#notes + 1] = { message = "the first segment `" .. first .. "` is not in scope" }
        end
    end

    return Report.new({
        code = "E0202",
        severity = "error",
        phase_context = "while resolving names",
        primary = { span = span, message = "unresolved path `" .. path_text .. "`" },
        notes = notes,
        suggestions = {},
    })
end)

-- E0203: Duplicate name
register("E0203", "error", function(issue, analysis)
    local span = issue_span(issue, analysis)
    local name = issue.name or "?"
    local kind = issue.kind or "name"
    local first_span = issue.first_span

    local report = Report.new({
        code = "E0203",
        severity = "error",
        phase_context = "while checking declarations",
        primary = {
            span = span,
            message = "duplicate " .. kind .. " `" .. name .. "`",
        },
        notes = {
            { message = kind:gsub("^%l", string.upper) .. " `" .. name .. "` was already defined" },
        },
        suggestions = {
            { message = "rename or remove the duplicate" },
        },
    })

    if first_span then
        report = Report.with_secondary(report, first_span, "first defined here")
    end

    return report
end)

-------------------------------------------------------------------------------
-- E03xx: Type Mismatches
-------------------------------------------------------------------------------

-- E0301: Type mismatch (expected X, got Y)
register("E0301", "error", function(issue, analysis)
    local span = issue_span(issue, analysis)
    local site = issue.site or "expression"
    local expected = type_name(issue.expected)
    local actual = type_name(issue.actual)
    local expected_raw = issue.expected
    local actual_raw = issue.actual

    local notes = {}
    local suggestions = {}

    -- Context-specific notes — exhaustive over all site strings from tree_typecheck.lua
    if site:find("call") then
        notes[#notes + 1] = { message = "this argument has type `" .. actual .. "`, but the function expects `" .. expected .. "`" }
    elseif site:find("let ") or site:find("var ") then
        local var_name = site:match("let (%w+)") or site:match("var (%w+)") or ""
        notes[#notes + 1] = { message = "the initializer has type `" .. actual .. "`, but the variable is declared as `" .. expected .. "`" }
    elseif site:find("return") then
        notes[#notes + 1] = { message = "the return value has type `" .. actual .. "`, but the function returns `" .. expected .. "`" }
    elseif site:find("yield") then
        notes[#notes + 1] = { message = "the yielded value has type `" .. actual .. "`, but the region yields `" .. expected .. "`" }
    elseif site:find("set") then
        notes[#notes + 1] = { message = "the assigned value has type `" .. actual .. "`, but the target has type `" .. expected .. "`" }
    elseif site:find("if cond") or site:find("select cond") then
        notes[#notes + 1] = { message = "the condition has type `" .. actual .. "`, but the condition must be `bool`" }
    elseif site:find("if branches") or site:find("select branches") then
        notes[#notes + 1] = { message = "both branches must have the same type; the then-branch is `" .. actual .. "`, the else-branch is `" .. expected .. "`" }
    elseif site:find("index") then
        notes[#notes + 1] = { message = "indexing requires an integer type, got `" .. actual .. "`" }
    elseif site:find("view data") then
        notes[#notes + 1] = { message = "view data must be a `ptr` or `view`, got `" .. actual .. "`" }
    elseif site:find("view len") or site:find("view stride")
        or site:find("view window") or site:find("bounds")
        or site:find("window_bounds") then
        notes[#notes + 1] = { message = "expected `" .. expected .. "`, got `" .. actual .. "`" }
    elseif site:find("disjoint") then
        notes[#notes + 1] = { message = "disjoint contract requires `ptr` or `view`, got `" .. actual .. "`" }
    elseif site:find("same_len") then
        notes[#notes + 1] = { message = "same_len contract requires `view`, got `" .. actual .. "`" }
    elseif site:find("memory contract") then
        notes[#notes + 1] = { message = "memory contract requires `ptr` or `view`, got `" .. actual .. "`" }
    elseif site:find("atomic") then
        notes[#notes + 1] = { message = "expected `" .. expected .. "`, got `" .. actual .. "`" }
    elseif site:find("block param") then
        notes[#notes + 1] = { message = "block parameter initializer has type `" .. actual .. "`, but the parameter is declared as `" .. expected .. "`" }
    elseif site:find("assert") then
        notes[#notes + 1] = { message = "assert condition must be `bool`, got `" .. actual .. "`" }
    elseif site:find("switch key") then
        notes[#notes + 1] = { message = "switch key has type `" .. actual .. "`, but the switch expression is `" .. expected .. "`" }
    elseif site:find("switch arm") then
        notes[#notes + 1] = { message = "switch arm has type `" .. actual .. "`, but the default arm is `" .. expected .. "`" }
    elseif site:find("array elem") then
        notes[#notes + 1] = { message = "array element has type `" .. actual .. "`, but the array expects `" .. expected .. "`" }
    elseif site:find("len") then
        notes[#notes + 1] = { message = "`len` requires a `view`, got `" .. actual .. "`" }
    elseif site:find("const") or site:find("static") then
        notes[#notes + 1] = { message = "the initializer has type `" .. actual .. "`, but the declaration is `" .. expected .. "`" }
    else
        notes[#notes + 1] = { message = "expected `" .. expected .. "`, got `" .. actual .. "`" }
    end

    -- Numeric conversion hint
    local pvm = require("moonlift.pvm")
    local function is_integer(ty)
        if not ty then return false end
        local cls = pvm.classof(ty)
        if cls and cls.kind == "TScalar" and ty.scalar then
            local scls = pvm.classof(ty.scalar)
            return scls and (scls.kind == "ScalarI32" or scls.kind == "ScalarI64"
                or scls.kind == "ScalarU32" or scls.kind == "ScalarU8"
                or scls.kind == "ScalarI8" or scls.kind == "ScalarI16"
                or scls.kind == "ScalarU16" or scls.kind == "ScalarU64"
                or scls.kind == "ScalarIndex")
        end
        return false
    end

    if actual == "bool" and expected ~= "bool" then
        suggestions[#suggestions + 1] = { message = "to convert a boolean to an integer, use a conditional: `select(flag, 1, 0)`" }
    elseif actual == "f64" and is_integer(expected_raw) then
        suggestions[#suggestions + 1] = { message = "to convert a float to an integer, use `as(i32, value)`" }
    elseif is_integer(actual_raw) and expected == "f64" then
        suggestions[#suggestions + 1] = { message = "to convert an integer to a float, use `as(f64, value)`" }
    end

    return Report.new({
        code = "E0301",
        severity = "error",
        phase_context = "while type-checking",
        primary = { span = span, message = "type mismatch" },
        notes = notes,
        suggestions = suggestions,
    })
end)

-- E0302: Not callable
register("E0302", "error", function(issue, analysis)
    local span = issue_span(issue, analysis)
    local ty = type_name(issue.ty)

    return Report.new({
        code = "E0302",
        severity = "error",
        phase_context = "while type-checking a call",
        primary = { span = span, message = "type `" .. ty .. "` is not callable" },
        notes = {
            { message = "only `func` and `closure` types can be called" },
        },
        suggestions = {
            { message = "did you mean to index? write `expr[idx]` for element access" },
        },
    })
end)

-- E0303: Not indexable
register("E0303", "error", function(issue, analysis)
    local span = issue_span(issue, analysis)
    local ty = type_name(issue.ty)

    return Report.new({
        code = "E0303",
        severity = "error",
        phase_context = "while type-checking an index",
        primary = { span = span, message = "type `" .. ty .. "` is not indexable" },
        notes = {
            { message = "only `view`, `ptr`, and `array` types support indexing" },
        },
        suggestions = {
            { message = "if you meant to access a field, use `.` syntax: `expr.field`" },
        },
    })
end)

-- E0304: Invalid operator
register("E0304", "error", function(issue, analysis)
    local span = issue_span(issue, analysis)
    local op = op_symbol(issue.op)
    local kind = issue.op_kind or "binary"

    if kind == "unary" then
        local ty = type_name(issue.ty)
        local notes = {}
        local suggestions = {}

        if op == "not" then
            notes[#notes + 1] = { message = "`not` requires a `bool` operand, got `" .. ty .. "`" }
        else
            notes[#notes + 1] = { message = "operator `" .. op .. "` is not defined for type `" .. ty .. "`" }
            notes[#notes + 1] = { message = "arithmetic operators require numeric types (i8, i16, i32, ...)" }
        end

        if ty == "bool" and op ~= "not" then
            suggestions[#suggestions + 1] = { message = "for boolean logic, use `not`: `not value`" }
        end

        return Report.new({
            code = "E0304",
            severity = "error",
            phase_context = "while type-checking an expression",
            primary = { span = span, message = "invalid unary operator `" .. op .. "` for type `" .. ty .. "`" },
            notes = notes,
            suggestions = suggestions,
        })
    end

    -- Binary
    local lhs = type_name(issue.lhs)
    local rhs = type_name(issue.rhs)
    local notes = {
        { message = "operator `" .. op .. "` is not defined for `" .. lhs .. "` and `" .. rhs .. "`" },
    }
    local suggestions = {}

    if lhs == "bool" and rhs == "bool" then
        if op == "+" or op == "-" or op == "*" or op == "/" then
            notes[#notes + 1] = { message = "arithmetic operators require numeric types (i8, i16, i32, ...)" }
            suggestions[#suggestions + 1] = { message = "for boolean logic, use `and` / `or`: `a and b` or `a or b`" }
        end
    end

    if lhs ~= rhs then
        notes[#notes + 1] = { message = "both operands must have the same type" }
    end

    return Report.new({
        code = "E0304",
        severity = "error",
        phase_context = "while type-checking an expression",
        primary = { span = span, message = "invalid operator `" .. op .. "`" },
        notes = notes,
        suggestions = suggestions,
    })
end)

-- E0305: Argument count mismatch
register("E0305", "error", function(issue, analysis)
    local span = issue_span(issue, analysis)
    local site = issue.site or "call"
    local expected = tostring(issue.expected or "?")
    local actual = tostring(issue.actual or "?")

    return Report.new({
        code = "E0305",
        severity = "error",
        phase_context = "while type-checking a " .. site,
        primary = { span = span, message = site .. " expected " .. expected .. " arguments, got " .. actual },
        notes = {
            { message = "the number of arguments does not match the function's parameter count" },
        },
        suggestions = {
            { message = "check the function signature and add or remove arguments accordingly" },
        },
    })
end)

-------------------------------------------------------------------------------
-- E04xx: Control Flow Errors
-------------------------------------------------------------------------------

-- E0401: Unterminated block
register("E0401", "error", function(issue, analysis)
    local span = issue_span(issue, analysis)
    local label = (issue.label and issue.label.name) or (issue.label_name) or "?"
    local region = issue.region_id or "?"

    return Report.new({
        code = "E0401",
        severity = "error",
        phase_context = "while checking control flow",
        primary = {
            span = span,
            message = "block `" .. label .. "` doesn't exit",
        },
        notes = {
            { message = "every block must end with `jump` or `yield` — execution cannot fall through" },
        },
        suggestions = {
            { message = "add a `jump` to another block, or `yield` a value from the enclosing region" },
        },
    })
end)

-- E0402: Missing jump target
register("E0402", "error", function(issue, analysis)
    local span = issue_span(issue, analysis)
    local label = (issue.label and issue.label.name) or (issue.label_name) or "?"
    local candidates = issue.block_names or {}

    local dym = Suggest.did_you_mean(label, candidates)

    local notes = {
        { message = "block `" .. label .. "` is not defined in this region" },
    }
    local suggestions = {}
    if dym then suggestions[#suggestions + 1] = { message = dym } end

    return Report.new({
        code = "E0402",
        severity = "error",
        phase_context = "while checking control flow",
        primary = { span = span, message = "missing jump target `" .. label .. "`" },
        notes = notes,
        suggestions = suggestions,
    })
end)

-- E0403: Continuation not filled
register("E0403", "error", function(issue, analysis)
    local span = issue_span(issue, analysis)
    local cont_name = issue.cont_name or "?"
    local region_name = issue.region_name or "?"
    local declared_conts = issue.declared_conts or {}

    local cont_list = {}
    for i = 1, #declared_conts do cont_list[i] = "`" .. declared_conts[i] .. "`" end
    local cont_str = table.concat(cont_list, ", ")

    local dym = Suggest.did_you_mean(cont_name, declared_conts)

    local notes = {
        { message = "`" .. region_name .. "` declares continuations: " .. cont_str },
    }
    local suggestions = {}
    if dym then
        suggestions[#suggestions + 1] = { message = dym }
    else
        suggestions[#suggestions + 1] = {
            message = "add a continuation fill: `" .. cont_name .. " = <block_label>`",
        }
    end

    return Report.new({
        code = "E0403",
        severity = "error",
        phase_context = "while checking control flow",
        primary = {
            span = span,
            message = "continuation `" .. cont_name .. "` is not filled at this emit site",
        },
        notes = notes,
        suggestions = suggestions,
    })
end)

-- E0404: Continuation type mismatch
register("E0404", "error", function(issue, analysis)
    local span = issue_span(issue, analysis)
    local cont_name = issue.cont_name or "?"
    local expected_params = issue.expected_params or {}
    local actual_params = issue.actual_params or {}

    local function param_list(params)
        local parts = {}
        for i = 1, #params do
            parts[i] = params[i].name .. ": " .. type_name(params[i].ty)
        end
        return table.concat(parts, ", ")
    end

    local notes = {
        { message = "continuation `" .. cont_name .. "` expects: " .. param_list(expected_params) },
        { message = "the target block accepts: " .. param_list(actual_params) },
    }

    return Report.new({
        code = "E0404",
        severity = "error",
        phase_context = "while checking control flow",
        primary = {
            span = span,
            message = "continuation `" .. cont_name .. "` type mismatch",
        },
        notes = notes,
        suggestions = {
            { message = "ensure the continuation parameters match the target block's parameters" },
        },
    })
end)

-- E0405: Irreducible control flow
register("E0405", "error", function(issue, analysis)
    local span = issue_span(issue, analysis)
    local reason = issue.reason or "irreducible cycle detected"

    return Report.new({
        code = "E0405",
        severity = "error",
        phase_context = "while checking control flow",
        primary = {
            span = span,
            message = "irreducible control flow in this region",
        },
        notes = {
            { message = reason },
            { message = "control flow is irreducible when two blocks both jump to each other without a common dominator" },
        },
        suggestions = {
            { message = "restructure so one block dominates the other, or add a dispatch block that chooses between them" },
        },
    })
end)

-- E0406: Duplicate block label
register("E0406", "error", function(issue, analysis)
    local span = issue_span(issue, analysis)
    local label = (issue.label and issue.label.name) or (issue.label_name) or "?"

    return Report.new({
        code = "E0406",
        severity = "error",
        phase_context = "while checking control flow",
        primary = { span = span, message = "duplicate block label `" .. label .. "`" },
        notes = {
            { message = "block labels must be unique within a region" },
        },
        suggestions = {
            { message = "rename one of the blocks, e.g. `" .. label .. "_after_gc`" },
        },
    })
end)

-- E0407: Yield outside region
register("E0407", "error", function(issue, analysis)
    local span = issue_span(issue, analysis)
    local site = issue.site or "yield"

    return Report.new({
        code = "E0407",
        severity = "error",
        phase_context = "while type-checking",
        primary = { span = span, message = "`" .. site .. "` used outside a region" },
        notes = {
            { message = "`yield` can only be used inside a `region` or a `return region -> T` expression" },
        },
        suggestions = {
            { message = "did you mean `return`? Functions use `return`, not `yield`" },
        },
    })
end)

-------------------------------------------------------------------------------
-- E05xx: Host / Struct Errors
-------------------------------------------------------------------------------

-- E0501: Duplicate field
register("E0501", "error", function(issue, analysis)
    local span = issue_span(issue, analysis)
    local field_name = issue.field_name or "?"
    local type_name = issue.type_name or "?"

    return Report.new({
        code = "E0501",
        severity = "error",
        phase_context = "while checking struct declarations",
        primary = { span = span, message = "duplicate field `" .. field_name .. "` in struct `" .. type_name .. "`" },
        notes = {
            { message = "struct fields must have unique names" },
        },
        suggestions = {
            { message = "remove or rename the duplicate field" },
        },
    })
end)

-- E0502: Duplicate type
register("E0502", "error", function(issue, analysis)
    local span = issue_span(issue, analysis)
    local type_name_str = issue.type_name or "?"

    return Report.new({
        code = "E0502",
        severity = "error",
        phase_context = "while checking type declarations",
        primary = { span = span, message = "duplicate type `" .. type_name_str .. "`" },
        notes = {
            { message = "each type name must be unique within its module" },
        },
        suggestions = {
            { message = "rename one of the duplicate type declarations" },
        },
    })
end)

-- E0503: Unsealed type mutation
register("E0503", "error", function(issue, analysis)
    local span = issue_span(issue, analysis)
    local type_name_str = issue.type_name or "?"

    return Report.new({
        code = "E0503",
        severity = "error",
        phase_context = "while checking type declarations",
        primary = { span = span, message = "cannot mutate sealed type `" .. type_name_str .. "`" },
        notes = {
            { message = "once a type is sealed, no further fields can be added" },
        },
        suggestions = {
            { message = "add fields before sealing, or create a new type" },
        },
    })
end)

-- E0504: Invalid name
register("E0504", "error", function(issue, analysis)
    local span = issue_span(issue, analysis)
    local name = issue.name or "?"
    local site = issue.site or "declaration"

    return Report.new({
        code = "E0504",
        severity = "error",
        phase_context = "while checking declarations",
        primary = { span = span, message = site .. " has invalid name `" .. name .. "`" },
        notes = {
            { message = "names must be valid identifiers: start with a letter or underscore, followed by letters, digits, or underscores" },
        },
        suggestions = {},
    })
end)

-- E0505: Boundary struct bool storage must be explicit
register("E0505", "error", function(issue, analysis)
    local span = issue_span(issue, analysis)
    local type_name_str = issue.type_name or "?"
    local field_name = issue.field_name or "?"
    return Report.new({
        code = "E0505",
        severity = "error",
        phase_context = "while checking host boundary declarations",
        primary = { span = span, message = "boundary struct field `" .. field_name .. "` in `" .. type_name_str .. "` must use explicit bool storage" },
        notes = {
            { message = "plain `bool` has no stable host ABI size; choose `bool8` or `bool32`" },
        },
        suggestions = {
            { message = "write `" .. field_name .. ": bool32` for an i32-backed boolean, or `" .. field_name .. ": bool8` for a byte-backed boolean" },
        },
    })
end)

-- E0506: Invalid packed alignment
register("E0506", "error", function(issue, analysis)
    local span = issue_span(issue, analysis)
    local type_name_str = issue.type_name or "?"
    local align = tostring(issue.align or "?")
    return Report.new({
        code = "E0506",
        severity = "error",
        phase_context = "while checking host layout declarations",
        primary = { span = span, message = "invalid packed alignment `" .. align .. "` for `" .. type_name_str .. "`" },
        notes = {
            { message = "packed alignment must be a positive power of two" },
        },
        suggestions = {
            { message = "use an alignment such as 1, 2, 4, 8, or remove `repr(packed(...))`" },
        },
    })
end)

-------------------------------------------------------------------------------
-- E06xx: Backend Errors (mapped to source-level concepts)
-------------------------------------------------------------------------------

-- E0601: Missing definition (block, function, value, etc.)
register("E0601", "error", function(issue, analysis)
    local span = issue_span(issue, analysis)
    local kind = issue.def_kind or "definition"
    local name = issue.name or "?"

    return Report.new({
        code = "E0601",
        severity = "error",
        phase_context = "while compiling",
        primary = { span = span, message = "missing " .. kind .. " `" .. name .. "`" },
        notes = {
            { message = "this " .. kind .. " is referenced but never defined" },
        },
        suggestions = {
            { message = "add a definition for `" .. name .. "`" },
        },
    })
end)

-- E0602: Duplicate definition
register("E0602", "error", function(issue, analysis)
    local span = issue_span(issue, analysis)
    local kind = issue.def_kind or "definition"
    local name = issue.name or "?"

    return Report.new({
        code = "E0602",
        severity = "error",
        phase_context = "while compiling",
        primary = { span = span, message = "duplicate " .. kind .. " `" .. name .. "`" },
        notes = {},
        suggestions = {
            { message = "rename or remove the duplicate" },
        },
    })
end)

-- E0603: Command order violation (after finalize, outside function, etc.)
register("E0603", "error", function(issue, analysis)
    local span = issue_span(issue, analysis)
    local violation = issue.violation or "command order violation"

    return Report.new({
        code = "E0603",
        severity = "error",
        phase_context = "while compiling",
        primary = { span = span, message = violation },
        notes = {
            { message = "backend commands must follow the correct order: begin → commands → finalize" },
        },
        suggestions = {},
    })
end)

-------------------------------------------------------------------------------
-- E07xx: Splice / Metaprogramming Errors
-------------------------------------------------------------------------------

-- E0701: Splice type mismatch
register("E0701", "error", function(issue, analysis)
    local span = issue_span(issue, analysis)
    local splice_id = issue.splice_id or "?"
    local expected = type_name(issue.expected)
    local actual = type_name(issue.actual)

    return Report.new({
        code = "E0701",
        severity = "error",
        phase_context = "while expanding splices",
        primary = {
            span = span,
            message = "splice `@{" .. splice_id .. "}` produced type `" .. actual .. "`, but this position requires `" .. expected .. "`",
        },
        notes = {
            { message = "splice values must match the type expected at their position — there is no implicit conversion" },
        },
        suggestions = {
            { message = "the Lua expression bound to `" .. splice_id .. "` must evaluate to a `" .. expected .. "` value" },
        },
    })
end)

-- E0702: Missing splice fill
register("E0702", "error", function(issue, analysis)
    local span = issue_span(issue, analysis)
    local fill_name = issue.fill_name or "?"
    local frag_name = issue.fragment_name or "?"

    return Report.new({
        code = "E0702",
        severity = "error",
        phase_context = "while expanding splices",
        primary = {
            span = span,
            message = "missing splice fill `" .. fill_name .. "` for fragment `" .. frag_name .. "`",
        },
        notes = {
            { message = "all splice slots declared by a fragment must be filled at each use site" },
        },
        suggestions = {
            { message = "add a fill: `@{..." .. fill_name .. " = value}`" },
        },
    })
end)

-------------------------------------------------------------------------------
-- Fallback: Unknown issue
-------------------------------------------------------------------------------

register("E9999", "error", function(issue, analysis)
    local span = issue_span(issue, analysis)
    local msg = issue.message or tostring(issue)

    return Report.new({
        code = "E9999",
        severity = "error",
        phase_context = issue.phase_context or "during compilation",
        primary = { span = span, message = msg },
        notes = {
            { message = "this is an unclassified error — please report it as a bug" },
        },
        suggestions = {},
    })
end)

-------------------------------------------------------------------------------
-- Catalog lookup with fallback
-------------------------------------------------------------------------------

function M.build_report(code, issue, analysis)
    local entry = M.entries[code]
    if not entry then
        entry = M.entries["E9999"]
    end
    local ok, report = pcall(entry.build, issue, analysis)
    if not ok then
        return Report.new({
            code = "E9999",
            severity = "error",
            primary = { span = nil, message = "internal error: " .. tostring(report) },
            notes = {
                { message = "the error reporter failed while trying to display another error" },
            },
        })
    end
    return report
end

-------------------------------------------------------------------------------
-- Issue-to-code mapping
--
-- Maps internal issue types to catalog codes. This is the bridge between
-- the compiler's internal vocabulary and the user-facing error catalog.
-------------------------------------------------------------------------------

local issue_code_map = {
    -- Parse issues
    ParseIssue = "E0101",

    -- Name resolution
    TypeIssueUnresolvedValue = "E0201",
    TypeIssueUnresolvedPath = "E0202",
    BindingUnresolved = "E0201",

    -- Type mismatches
    TypeIssueExpected = "E0301",
    TypeIssueArgCount = "E0305",
    TypeIssueNotCallable = "E0302",
    TypeIssueNotIndexable = "E0303",
    TypeIssueNotPointer = "E0303",
    TypeIssueInvalidUnary = "E0304",
    TypeIssueInvalidBinary = "E0304",
    TypeIssueInvalidCompare = "E0304",
    TypeIssueInvalidLogic = "E0304",

    -- Control flow
    TypeIssueInvalidControl = "E0405",
    TypeIssueMissingJumpTarget = "E0402",
    TypeIssueMissingJumpArg = "E0404",
    TypeIssueExtraJumpArg = "E0404",
    TypeIssueDuplicateJumpArg = "E0404",
    TypeIssueUnexpectedYield = "E0407",

    -- Host issues
    HostIssueDuplicateField = "E0501",
    HostIssueDuplicateType = "E0502",
    HostIssueDuplicateDecl = "E0203",
    HostIssueDuplicateFunc = "E0203",
    HostIssueUnsealedType = "E0503",
    HostIssueSealedMutation = "E0503",
    HostIssueAlreadySealed = "E0503",
    HostIssueInvalidName = "E0504",
    HostIssueUnknownBinding = "E0201",
    HostIssueExpected = "E0301",
    HostIssueArgCount = "E0305",
    HostIssueInvalidPackedAlign = "E0506",
    HostIssueBareBoolInBoundaryStruct = "E0505",
    HostIssueInvalidEmitFill = "E0702",
    HostIssueMissingEmitFill = "E0702",

    -- Back issues → source-level mapping
    BackIssueEmptyProgram = "E0603",
    BackIssueMissingFinalize = "E0603",
    BackIssueCommandAfterFinalize = "E0603",
    BackIssueCommandOutsideFunction = "E0603",
    BackIssueNestedFunction = "E0603",
    BackIssueFinishWithoutBegin = "E0603",
    BackIssueFinishWrongFunction = "E0603",
    BackIssueUnfinishedFunction = "E0603",
    BackIssueDuplicateSig = "E0602",
    BackIssueDuplicateData = "E0602",
    BackIssueDuplicateFunc = "E0602",
    BackIssueDuplicateExtern = "E0602",
    BackIssueDuplicateBlock = "E0406",
    BackIssueDuplicateStackSlot = "E0602",
    BackIssueDuplicateValue = "E0602",
    BackIssueMissingSig = "E0601",
    BackIssueMissingData = "E0601",
    BackIssueMissingFunc = "E0601",
    BackIssueMissingExtern = "E0601",
    BackIssueMissingBlock = "E0402",
    BackIssueMissingStackSlot = "E0601",
    BackIssueMissingValue = "E0601",

    -- Unknown variant
    TypeIssueUnknownVariant = "E0301",
    TypeIssueVariantPayloadMismatch = "E0301",
    TypeIssueDuplicateVariant = "E0203",
}

function M.code_for_issue(issue)
    if not issue then return "E9999" end
    if type(issue) ~= "table" then return "E9999" end

    -- Check for explicit code
    if issue.error_code then return issue.error_code end

    -- Map by class kind
    local pvm = require("moonlift.pvm")
    local cls = pvm.classof(issue)
    if cls then
        local code = issue_code_map[cls.kind]
        if code then return code end
    end

    -- Check for issue kind field
    if issue.kind then
        local code = issue_code_map[issue.kind]
        if code then return code end
    end

    return "E9999"
end

return M
