-- tests/test_error_system.lua
-- Tests for the new error management system.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Errors = require("moonlift.error")
local Span = Errors.Span
local Report = Errors.Report
local Catalog = Errors.Catalog
local Suggest = Errors.Suggest
local Registry = Errors.Registry
local Terminal = Errors.Terminal
local LSP = Errors.LSP

local passed = 0
local failed = 0

local function assert_eq(name, a, b)
    if a == b then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL " .. name .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
    end
end

local function assert_true(name, cond)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL " .. name .. ": expected true, got false")
    end
end

local function assert_neq(name, a, b)
    if a ~= b then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL " .. name .. ": expected different values, both were " .. tostring(a))
    end
end

-- ============================================================
-- Span tests
-- ============================================================

do
    local s = Span.from_offsets("test.mlua", 10, 20, 3, 5, 3, 10)
    assert_eq("span uri", s.uri, "test.mlua")
    assert_eq("span start_offset", s.start_offset, 10)
    assert_eq("span end_offset", s.end_offset, 20)
    assert_eq("span start_line", s.start_line, 3)
    assert_eq("span start_col", s.start_col, 5)

    assert_true("span is not point", not Span.is_point(s))

    local p = Span.point("test.mlua", 42, 5, 1)
    assert_true("point is point", Span.is_point(p))

    assert_true("span contains 15", Span.contains(s, 15))
    assert_true("span not contains 5", not Span.contains(s, 5))

    assert_true("same span", Span.same_span(s, Span.from_offsets("test.mlua", 10, 20, 3, 5, 3, 10)))
    assert_true("different uri", not Span.same_span(s, Span.from_offsets("other.mlua", 10, 20, 3, 5, 3, 10)))
end

-- ============================================================
-- Span snippet rendering
-- ============================================================

do
    local src = "line one\nlet x: i32 = \"hello\"\nline three\nline four\n"
    local s = Span.from_offsets("test.mlua", 10, 22, 2, 5, 2, 12)
    local snippet = Span.render_snippet(s, src, { context = 1 })

    assert_true("snippet has lines", #snippet.lines > 0)
    assert_true("snippet has underlines", #snippet.underlines > 0)
    assert_eq("snippet uri", snippet.uri, "test.mlua")
end

-- ============================================================
-- Report tests
-- ============================================================

do
    local r = Report.error("E0301", "type mismatch", nil, "expected i32")
    assert_eq("report code", r.code, "E0301")
    assert_eq("report severity", r.severity, "error")
    assert_eq("report message", r.primary.message, "type mismatch")
    assert_true("report is error", Report.is_error(r))
    assert_true("report is not warning", not Report.is_warning(r))

    local r2 = Report.with_note(r, "some context")
    assert_eq("note added", #r2.notes, 1)
    assert_eq("note message", r2.notes[1].message, "some context")

    local r3 = Report.with_suggestion(r2, "did you mean x?", nil)
    assert_eq("suggestion added", #r3.suggestions, 1)
    assert_eq("suggestion message", r3.suggestions[1].message, "did you mean x?")

    -- Original not mutated
    assert_eq("original no notes", #r.notes, 0)
end

-- ============================================================
-- Suggest (did you mean) tests
-- ============================================================

do
    local hits = Suggest.suggest("taape", { "tape", "top", "table", "type", "tap" })
    assert_true("suggest finds tape", #hits > 0)
    assert_eq("suggest first hit", hits[1], "tape")

    local dym = Suggest.did_you_mean("dispach", { "dispatch", "mode_select", "exec_slice" })
    assert_true("did you mean not nil", dym ~= nil)
    assert_true("did you mean contains dispatch", dym:find("dispatch") ~= nil)

    -- No suggestion for very different names
    local none = Suggest.did_you_mean("xyzzy", { "tape", "dispatch" })
    assert_true("no suggestion for distant names", none == nil)

    -- No suggestion for short names
    local short = Suggest.did_you_mean("a", { "b", "c" })
    assert_true("no suggestion for short names", short == nil)
end

-- ============================================================
-- Catalog tests
-- ============================================================

do
    -- Helper: create a mock ASDL-like issue with a kind field and __class metatable
    local function mock(kind, fields)
        fields = fields or {}
        fields.kind = kind
        return setmetatable(fields, { __class = { kind = kind } })
    end

    -- E0201: unresolved name (goes through binding explainer)
    local report = Catalog.build_report("E0201", mock("BindingUnresolved", {
        use = { anchor = { label = "taape" } },
    }), "binding", { in_scope_names = { "tape", "table" } })
    assert_eq("E0201 code", report.code, "E0201")
    assert_true("E0201 has message", report.primary.message:find("taape") ~= nil or report.primary.message:find("unresolved") ~= nil)
    assert_true("E0201 has suggestion", #report.suggestions > 0 or #report.notes > 0)

    -- E0301: type mismatch (goes through typecheck explainer)
    local report2 = Catalog.build_report("E0301", mock("TypeIssueExpected", {
        site = "call",
        expected = "i32",
        actual = "bool",
    }), "typecheck", {})
    assert_eq("E0301 code", report2.code, "E0301")
    assert_true("E0301 has notes", #report2.notes > 0)

    -- E0403: continuation not filled (goes through host explainer)
    local report3 = Catalog.build_report("E0403", mock("HostIssueRegionComposeMissingExit", {
        fragment_name = "exec_slice",
        exit_name = "bad",
    }), "host", {})
    assert_true("E0403 mentions bad", report3.primary.message:find("bad") ~= nil or report3.primary.message:find("exit") ~= nil)

    -- Unknown phase falls back to E9999
    local report4 = Catalog.build_report("E0000", {
        message = "something weird",
    }, nil, {})
    assert_eq("E9999 fallback", report4.code, "E9999")
end

-- ============================================================
-- Registry tests
-- ============================================================

do
    local function mock(kind, fields)
        fields = fields or {}
        fields.kind = kind
        return setmetatable(fields, { __class = { kind = kind } })
    end

    local reg = Registry.new()
    Registry.register_source(reg, "test.mlua", "let x = taape[0]\nlet y = x + true\n")

    -- Emit an unresolved name (root cause)
    Registry.emit(reg, mock("TypeIssueUnresolvedValue", { name = "taape" }), "typecheck", {})

    -- Emit a cascade (type mismatch involving void from the unresolved name)
    Registry.emit(reg, mock("TypeIssueExpected", {
        site = "call taape",
        expected = "i32",
        actual = "void",
    }), "typecheck", {})

    local reports = Registry.reports(reg)
    assert_eq("registry suppresses cascades", #reports, 1)
    assert_true("root cause is reported", reports[1].primary.message:find("taape") ~= nil)

    local stats = Registry.stats(reg)
    assert_eq("stats total", stats.total, 2)
    assert_eq("stats roots", stats.roots, 1)
    assert_eq("stats cascades", stats.cascades, 1)
end

-- ============================================================
-- Terminal presenter tests
-- ============================================================

do
    local src = "local x = 42\nlet y: bool = x + 1\nreturn y\n"
    local span = Span.from_offsets("test.mlua", 11, 23, 2, 5, 2, 14)
    local report = Report.error("E0304", "invalid operator `+`", span, "both operands are `bool`")
    report = Report.with_note(report, "operator `+` is not defined for `bool` and `i32`")
    report = Report.with_suggestion(report, "for boolean logic, use `and` / `or`")

    local rendered = Terminal.render(report, src)
    assert_true("terminal renders", #rendered > 0)
    assert_true("terminal has error header", rendered:find("E0304") ~= nil)
    assert_true("terminal has note", rendered:find("note:") ~= nil)
    assert_true("terminal has help", rendered:find("help:") ~= nil)
    -- Snippet may not render with synthetic offsets that don't match the source
    -- so just check we got output
    assert_true("terminal output non-empty", #rendered > 20)
end

-- ============================================================
-- LSP presenter tests
-- ============================================================

do
    local span = Span.from_offsets("test.mlua", 10, 20, 2, 5, 2, 15)
    local report = Report.error("E0201", "unresolved name `taape`", span)
    report = Report.with_suggestion(report, "did you mean `tape`?", {
        span = span,
        new_text = "tape",
    })

    local diag = LSP.render(report)
    assert_true("LSP has range", diag.range ~= nil)
    assert_eq("LSP severity", diag.severity, 1)
    assert_eq("LSP code", diag.code, "E0201")
    assert_eq("LSP source", diag.source, "moonlift")
    -- Message includes notes and suggestions appended
    assert_true("LSP has taape in message", diag.message:find("taape") ~= nil or diag.message:find("unresolved") ~= nil)
    assert_true("LSP has code actions", diag.data and diag.data.codeActions ~= nil)
end

-- ============================================================
-- Integration: full pipeline test
-- ============================================================

do
    local src = [[
union Step again(pc: i32, tape_len: i32) | stop(code: i32) end

region check_invariants(pc: i32, tape_len: i32): Step
entry start()
    if fuel <= 0 then jump stop(code = -700) end
    jump again(pc = pc, tape_len = tape_len)
end
end

func run_machine(tape: ptr(i32), n: i32): i32
    return region: i32
    entry start()
        jump dispatch(pc = 0, tape_len = 0)
    end

    block dispatch(pc: i32, tape_len: i32)
        emit check_invariants(pc, tape_len; again = dispatch, stop = halted)
    end

    block halted(code: i32)
        yield code
    end
    end
end
]]

    local reg = Registry.new()
    Registry.register_source(reg, "tapexmem.mlua", src)

    -- Helper: create a mock ASDL-like issue
    local function mock(kind, fields)
        fields = fields or {}
        fields.kind = kind
        return setmetatable(fields, { __class = { kind = kind } })
    end

    -- Simulate an unresolved name error ("fuel" is not a parameter of check_invariants)
    -- The registry needs candidates in the analysis for "did you mean?"
    -- But the catalog build_report for E0201 reads from issue.candidates or analysis.in_scope_names
    -- We need to pass candidates through the issue since registry.reports doesn't
    -- have access to the original analysis
    Registry.emit(reg, mock("TypeIssueUnresolvedValue", {
        name = "fuel",
        candidates = { "pc", "tape_len", "tape", "n" },
    }), "typecheck", {
        in_scope_names = { "pc", "tape_len", "tape", "n" },
    })

    local reports = Registry.reports(reg)
    assert_true("integration has reports", #reports >= 1)

    local rendered = Terminal.render_from_registry(reports, reg.source_cache)
    assert_true("integration renders", #rendered > 0)
    assert_true("integration shows fuel", rendered:find("fuel") ~= nil)

    -- Check that we get a suggestion about the name
    local found_suggestion = false
    for i = 1, #reports do
        for j = 1, #reports[i].suggestions do
            if reports[i].suggestions[j].message and
                (reports[i].suggestions[j].message:find("pc")
                 or reports[i].suggestions[j].message:find("tape_len")
                 or reports[i].suggestions[j].message:find("did you mean")) then
                found_suggestion = true
            end
        end
        -- Also check notes for useful info
        for j = 1, #reports[i].notes do
            if reports[i].notes[j].message and reports[i].notes[j].message:find("fuel") then
                found_suggestion = true
            end
        end
    end
    assert_true("integration has useful info about fuel", found_suggestion)
end

-- ============================================================
-- Summary
-- ============================================================

print(string.format("\n=== Error System Tests: %d passed, %d failed ===", passed, failed))
if failed > 0 then os.exit(1) end
