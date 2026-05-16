local pvm = require("moonlift.pvm")
local Errors = require("moonlift.error")
local PositionIndex = require("moonlift.source_position_index")
local BindingScopes = require("moonlift.editor_binding_scope_facts")

local M = {}

local function class_name(node)
    local cls = pvm.classof(node)
    return cls and cls.kind or tostring(node)
end

local function append_all(dst, xs)
    for i = 1, #(xs or {}) do dst[#dst + 1] = xs[i] end
end

function M.Define(T)
    local S = T.MoonSource
    local H = T.MoonHost
    local Tr = T.MoonTree
    local B = T.MoonBack
    local Mlua = T.MoonMlua
    local P = PositionIndex.Define(T)
    local ScopeFacts = BindingScopes.Define(T)

    local function span_from_range(r)
        if not r then return nil end
        return Errors.Span.from_offsets(
            r.uri and r.uri.text or "?",
            r.start_offset or 0,
            r.stop_offset or r.start_offset or 0,
            (r.start and r.start.line or 0) + 1,
            (r.start and r.start.utf16_col or 0) + 1,
            (r.stop and r.stop.line or 0) + 1,
            (r.stop and r.stop.utf16_col or 0) + 1
        )
    end

    local function full_range(analysis)
        local index = P.build_index(analysis.parse.parts.document)
        return assert(P.range_from_offsets(index, 0, #analysis.parse.parts.document.text))
    end

    local function range_at_offset(analysis, one_based_offset)
        local index = P.build_index(analysis.parse.parts.document)
        local start_offset = math.max(0, (one_based_offset or 1) - 1)
        if start_offset > #analysis.parse.parts.document.text then start_offset = #analysis.parse.parts.document.text end
        local stop_offset = math.min(#analysis.parse.parts.document.text, start_offset + 1)
        return assert(P.range_from_offsets(index, start_offset, stop_offset))
    end

    local function first_anchor_with_label(analysis, label)
        if not label then return nil end
        for i = 1, #analysis.anchors.anchors do
            local a = analysis.anchors.anchors[i]
            if a.label == label then return a end
        end
        return nil
    end

    local function range_for_label(analysis, label)
        local a = first_anchor_with_label(analysis, label)
        return a and a.range or nil
    end

    local function first_anchor_kind_label(analysis, kind, label)
        for i = 1, #analysis.anchors.anchors do
            local a = analysis.anchors.anchors[i]
            if a.kind == kind and (label == nil or a.label == label) then return a end
        end
        return nil
    end

    local function nth_anchor_kind_label(analysis, kind, label, ordinal)
        local n = 0
        for i = 1, #analysis.anchors.anchors do
            local a = analysis.anchors.anchors[i]
            if a.kind == kind and (label == nil or a.label == label) then
                n = n + 1
                if n == ordinal then return a end
            end
        end
        return nil
    end

    local op_symbols = {
        ["MoonCore.BinAdd"] = "+", ["MoonCore.BinSub"] = "-", ["MoonCore.BinMul"] = "*", ["MoonCore.BinDiv"] = "/", ["MoonCore.BinRem"] = "%",
        ["MoonCore.BinBitAnd"] = "&", ["MoonCore.BinBitOr"] = "|", ["MoonCore.BinBitXor"] = "~", ["MoonCore.BinShl"] = "<<", ["MoonCore.BinLShr"] = ">>>", ["MoonCore.BinAShr"] = ">>",
        ["MoonCore.CmpEq"] = "==", ["MoonCore.CmpNe"] = "~=", ["MoonCore.CmpLt"] = "<", ["MoonCore.CmpLe"] = "<=", ["MoonCore.CmpGt"] = ">", ["MoonCore.CmpGe"] = ">=",
        ["MoonCore.LogicAnd"] = "and", ["MoonCore.LogicOr"] = "or",
        ["MoonCore.UnaryNot"] = "not", ["MoonCore.UnaryNeg"] = "-", ["MoonCore.UnaryBitNot"] = "~",
    }

    local function op_symbol(op)
        return op_symbols[tostring(op)] or tostring(op)
    end

    local function operator_range(analysis, op, ordinal)
        local sym = op_symbol(op)
        -- Logic operators "and"/"or" are keywords, not operator tokens
        local a
        if sym == "and" or sym == "or" then
            a = nth_anchor_kind_label(analysis, S.AnchorKeyword, sym, ordinal or 1)
        else
            a = nth_anchor_kind_label(analysis, S.AnchorOpaque("operator"), sym, ordinal or 1)
        end
        return a and a.range or nil
    end

    local function site_range(analysis, site)
        site = tostring(site or "")

        -- 1. Variable/param bindings: "let x", "var x", "block param x"
        local name = site:match("^let%s+([_%a][_%w]*)")
                  or site:match("^var%s+([_%a][_%w]*)")
                  or site:match("^block param%s+([_%a][_%w]*)")
        if name then
            local a = first_anchor_with_label(analysis, name)
            if a then return a.range end
        end

        -- 2. Keyword sites: direct keyword anchor lookup
        local keyword_sites = {
            ["return"] = "return", ["yield"] = "yield", ["yield value"] = "yield",
            ["if cond"] = "if", ["if branches"] = "if",
            ["select cond"] = "if", ["select branches"] = "if",
            ["switch key"] = "switch", ["switch arm"] = "switch",
            ["assert"] = "assert", ["not"] = "not",
            ["const"] = "const", ["static"] = "static",
            ["view data"] = "view", ["view len"] = "view", ["view stride"] = "view",
            ["view window start"] = "view", ["view window len"] = "view",
        }
        local kw = keyword_sites[site]
        if kw then
            local a = first_anchor_kind_label(analysis, S.AnchorKeyword, kw)
            if a then return a.range end
        end

        -- 3. Function-like sites: names used as builtins or function calls
        local func_sites = {
            ["call"] = true, ["call arg"] = true,
            ["len"] = true,
            ["bounds base"] = true, ["bounds len"] = true,
            ["window_bounds base"] = true, ["window_bounds base_len"] = true,
            ["window_bounds start"] = true, ["window_bounds len"] = true,
            ["disjoint lhs"] = true, ["disjoint rhs"] = true,
            ["same_len lhs"] = true, ["same_len rhs"] = true,
            ["memory contract base"] = true,
            ["atomic_load"] = true, ["atomic_load addr"] = true,
            ["atomic_rmw"] = true, ["atomic_rmw addr"] = true,
            ["atomic_rmw value"] = true,
            ["atomic_rmw pointer op"] = true, ["atomic_rmw bool add/sub"] = true,
            ["atomic_store"] = true, ["atomic_store addr"] = true,
            ["atomic_store value"] = true,
            ["atomic_cas"] = true, ["atomic_cas addr"] = true,
            ["atomic_cas expected"] = true, ["atomic_cas replacement"] = true,
        }
        if func_sites[site] then
            local fn_name = site:match("^([_%a][_%w]*)") or site
            local a = first_anchor_kind_label(analysis, S.AnchorFunctionUse, fn_name)
                   or first_anchor_kind_label(analysis, S.AnchorKeyword, fn_name)
            if a then return a.range end
        end

        -- 4. Operator/punctuation sites
        local op_sites = {
            ["set"] = "=",
            ["index"] = "[",
        }
        local op = op_sites[site]
        if op then
            local a = first_anchor_kind_label(analysis, S.AnchorOpaque("operator"), op)
            if a then return a.range end
        end

        -- 5. Named ref sites (resolve via binding-use or function-use anchors)
        if site:match("^[_%a][_%w]*$") then
            local a = first_anchor_kind_label(analysis, S.AnchorBindingUse, site)
                   or first_anchor_kind_label(analysis, S.AnchorFunctionUse, site)
            if a then return a.range end
        end

        return nil
    end

    local function control_reject_issue(analysis, reject)
        local cls = pvm.classof(reject)
        if cls == Tr.ControlRejectUnterminatedBlock then
            return { kind = "ControlRejectUnterminatedBlock", error_code = "E0401", label = reject.label, span = span_from_range(range_for_label(analysis, reject.label.name)) }
        end
        if cls == Tr.ControlRejectMissingLabel then
            return { kind = "TypeIssueMissingJumpTarget", label = reject.label, span = span_from_range(range_for_label(analysis, reject.label.name)) }
        end
        if cls == Tr.ControlRejectDuplicateLabel then
            return { kind = "ControlRejectDuplicateLabel", error_code = "E0406", label = reject.label, span = span_from_range(range_for_label(analysis, reject.label.name)) }
        end
        return { kind = "TypeIssueInvalidControl", error_code = "E0405", reason = reject.reason or class_name(reject), span = nil }
    end

    local function type_issue_for_report(issue, analysis, ordinal)
        local cls = pvm.classof(issue)
        if cls == Tr.TypeIssueUnresolvedValue then
            return { kind = "TypeIssueUnresolvedValue", name = issue.name, span = span_from_range(range_for_label(analysis, issue.name)) }
        elseif cls == Tr.TypeIssueUnresolvedPath then
            local parts = {}
            for i = 1, #(issue.path.parts or {}) do parts[i] = issue.path.parts[i].text end
            local text = table.concat(parts, ".")
            return { kind = "TypeIssueUnresolvedPath", path_text = text, first_name = parts[1], span = span_from_range(range_for_label(analysis, parts[1] or text)) }
        elseif cls == Tr.TypeIssueExpected then
            return { kind = "TypeIssueExpected", site = issue.site, expected = issue.expected, actual = issue.actual, span = span_from_range(site_range(analysis, issue.site)) }
        elseif cls == Tr.TypeIssueArgCount then
            return { kind = "TypeIssueArgCount", site = issue.site, expected = issue.expected, actual = issue.actual, span = span_from_range(site_range(analysis, issue.site)) }
        elseif cls == Tr.TypeIssueNotCallable then
            return { kind = "TypeIssueNotCallable", ty = issue.ty, span = span_from_range(site_range(analysis, "call")) }
        elseif cls == Tr.TypeIssueNotIndexable then
            return { kind = "TypeIssueNotIndexable", ty = issue.ty, span = span_from_range(site_range(analysis, "index")) }
        elseif cls == Tr.TypeIssueNotPointer then
            return { kind = "TypeIssueNotPointer", ty = issue.ty, span = span_from_range(site_range(analysis, "set")) }
        elseif cls == Tr.TypeIssueInvalidUnary then
            return { kind = "TypeIssueInvalidUnary", op_kind = "unary", op = issue.op, ty = issue.ty, span = span_from_range(operator_range(analysis, issue.op, ordinal)) }
        elseif cls == Tr.TypeIssueInvalidBinary then
            return { kind = "TypeIssueInvalidBinary", op_kind = "binary", op = issue.op, lhs = issue.lhs, rhs = issue.rhs, span = span_from_range(operator_range(analysis, issue.op, ordinal)) }
        elseif cls == Tr.TypeIssueInvalidCompare then
            return { kind = "TypeIssueInvalidCompare", op_kind = "binary", op = issue.op, lhs = issue.lhs, rhs = issue.rhs, span = span_from_range(operator_range(analysis, issue.op, ordinal)) }
        elseif cls == Tr.TypeIssueInvalidLogic then
            return { kind = "TypeIssueInvalidLogic", op_kind = "binary", op = issue.op, lhs = issue.lhs, rhs = issue.rhs, span = span_from_range(operator_range(analysis, issue.op, ordinal)) }
        elseif cls == Tr.TypeIssueMissingJumpTarget then
            return { kind = "TypeIssueMissingJumpTarget", label = issue.label, span = span_from_range(range_for_label(analysis, issue.label.name)) }
        elseif cls == Tr.TypeIssueUnexpectedYield then
            return { kind = "TypeIssueUnexpectedYield", site = issue.site, span = span_from_range(site_range(analysis, "yield")) }
        elseif cls == Tr.TypeIssueInvalidControl then
            return control_reject_issue(analysis, issue.reject)
        end
        return { kind = class_name(issue), message = class_name(issue), span = nil }
    end

    local function host_issue_for_report(issue, analysis)
        local cls = pvm.classof(issue)
        if cls == H.HostIssueBareBoolInBoundaryStruct then
            return { kind = "HostIssueBareBoolInBoundaryStruct", error_code = "E0505", type_name = issue.type_name, field_name = issue.field_name, span = span_from_range(range_for_label(analysis, issue.field_name)) }
        elseif cls == H.HostIssueInvalidPackedAlign then
            return { kind = "HostIssueInvalidPackedAlign", error_code = "E0506", type_name = issue.type_name, align = issue.align, span = span_from_range(range_for_label(analysis, issue.type_name)) }
        elseif cls == H.HostIssueDuplicateField then
            return { kind = "HostIssueDuplicateField", type_name = issue.type_name, field_name = issue.field_name, span = span_from_range(range_for_label(analysis, issue.field_name)) }
        elseif cls == H.HostIssueDuplicateType then
            return { kind = "HostIssueDuplicateType", type_name = issue.type_name, module_name = issue.module_name, span = span_from_range(range_for_label(analysis, issue.type_name)) }
        elseif cls == H.HostIssueDuplicateDecl then
            local label = tostring(issue.name):match(":(.+)$") or issue.name
            return { kind = "HostIssueDuplicateDecl", name = issue.name, span = span_from_range(range_for_label(analysis, label)) }
        elseif cls == H.HostIssueInvalidName then
            return { kind = "HostIssueInvalidName", site = issue.site, name = issue.name, span = span_from_range(range_for_label(analysis, issue.name)) }
        elseif cls == H.HostIssueExpected then
            return { kind = "HostIssueExpected", site = issue.site, expected = issue.expected, actual = issue.actual, span = span_from_range(site_range(analysis, issue.site)) }
        elseif cls == H.HostIssueArgCount then
            return { kind = "HostIssueArgCount", site = issue.site, expected = issue.expected, actual = issue.actual, span = span_from_range(site_range(analysis, issue.site)) }
        elseif cls == H.HostIssueUnknownBinding then
            return { kind = "HostIssueUnknownBinding", name = issue.name, span = span_from_range(range_for_label(analysis, issue.name)) }
        elseif cls == H.HostIssueInvalidEmitFill or cls == H.HostIssueMissingEmitFill then
            return { kind = class_name(issue), fill_name = issue.fill_name, fragment_name = issue.fragment_name, span = nil }
        end
        return { kind = class_name(issue), message = class_name(issue), span = nil }
    end

    local function back_issue_for_report(issue, analysis)
        local cls = pvm.classof(issue)
        local k = class_name(issue)
        local name = issue.func or issue.block or issue.value or issue.sig or issue.data or issue.extern or issue.slot
        local text = name and ((name.text) or tostring(name)) or k
        if k:match("Duplicate") then
            return { kind = k, def_kind = "backend definition", name = text, span = nil }
        elseif k:match("Missing") or k:match("Unfinished") then
            return { kind = k, def_kind = "backend definition", name = text, span = nil }
        end
        return { kind = k, violation = k, span = nil }
    end

    local function reports(analysis)
        local reg = Errors.registry()
        local doc = analysis.parse.parts.document
        Errors.register_source(reg, doc.uri.text, doc.text)

        for i = 1, #analysis.parse.combined.issues do
            local issue = analysis.parse.combined.issues[i]
            Errors.emit(reg, {
                kind = "ParseIssue",
                message = issue.message,
                offset = issue.offset,
                span = span_from_range(range_at_offset(analysis, issue.offset)),
            }, "parse", analysis)
        end

        for i = 1, #analysis.host.report.issues do
            Errors.emit(reg, host_issue_for_report(analysis.host.report.issues[i], analysis), "host", analysis)
        end

        local known_types = {}
        for i = 1, #analysis.parse.combined.decls.decls do
            local d = analysis.parse.combined.decls.decls[i]
            if pvm.classof(d) == H.HostDeclStruct then known_types[d.decl.name] = true end
        end
        local binding_report = ScopeFacts.report(analysis)
        for i = 1, #binding_report.resolutions do
            local r = binding_report.resolutions[i]
            if pvm.classof(r) == T.MoonEditor.BindingUnresolved and not known_types[r.use.anchor.label] then
                Errors.emit(reg, { kind = "BindingUnresolved", name = r.use.anchor.label, span = span_from_range(r.use.anchor.range) }, "binding", analysis)
            end
        end

        local occurrences = {}
        for i = 1, #analysis.type_issues do
            local issue = analysis.type_issues[i]
            local key = class_name(issue)
            if issue.op then key = key .. ":" .. op_symbol(issue.op) end
            occurrences[key] = (occurrences[key] or 0) + 1
            Errors.emit(reg, type_issue_for_report(issue, analysis, occurrences[key]), "typecheck", analysis)
        end

        for i = 1, #analysis.back_report.issues do
            Errors.emit(reg, back_issue_for_report(analysis.back_report.issues[i], analysis), "backend", analysis)
        end

        return Errors.reports(reg)
    end

    return { reports = reports }
end

return M
