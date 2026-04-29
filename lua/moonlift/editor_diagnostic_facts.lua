local pvm = require("moonlift.pvm")
local PositionIndex = require("moonlift.source_position_index")
local AnchorIndex = require("moonlift.source_anchor_index")
local BindingScopes = require("moonlift.editor_binding_scope_facts")

local M = {}

local function append_all(dst, xs)
    for i = 1, #(xs or {}) do dst[#dst + 1] = xs[i] end
end

local function class_name(node)
    local cls = pvm.classof(node)
    return cls and cls.kind or tostring(node)
end

local function host_issue_label(H, issue)
    local cls = pvm.classof(issue)
    if cls == H.HostIssueDuplicateField then return issue.field_name end
    if cls == H.HostIssueBareBoolInBoundaryStruct then return issue.field_name end
    if cls == H.HostIssueInvalidPackedAlign then return issue.type_name end
    if cls == H.HostIssueDuplicateType then return issue.type_name end
    if cls == H.HostIssueUnsealedType then return issue.type_name end
    if cls == H.HostIssueSealedMutation then return issue.type_name end
    if cls == H.HostIssueAlreadySealed then return issue.type_name end
    if cls == H.HostIssueInvalidName then return issue.name end
    if cls == H.HostIssueDuplicateDecl then
        return tostring(issue.name):match(":(.+)$") or issue.name
    end
    return nil
end

local function first_anchor_with_label(anchor_set, label)
    if not label then return nil end
    for i = 1, #anchor_set.anchors do
        local a = anchor_set.anchors[i]
        if a.label == label then return a end
    end
    return nil
end

function M.Define(T)
    local S = T.Moon2Source
    local E = T.Moon2Editor
    local C = T.Moon2Core
    local Ty = T.Moon2Type
    local Mlua = T.Moon2Mlua
    local H = T.Moon2Host
    local O = T.Moon2Open
    local Tr = T.Moon2Tree
    local B = T.Moon2Back
    local V = T.Moon2Vec
    local P = PositionIndex.Define(T)
    local AI = AnchorIndex.Define(T)
    local ScopeFacts = BindingScopes.Define(T)

    local function full_range(analysis)
        local index = P.build_index(analysis.parse.parts.document)
        return assert(P.range_from_offsets(index, 0, #analysis.parse.parts.document.text))
    end

    local is_void_type

    local function publish_open_issue(issue)
        local cls = pvm.classof(issue)
        -- These are compiler expansion/planning facts for hosted fragments until
        -- a concrete use site has an anchor. Publishing them at [1,1] is noisy
        -- and not actionable in the editor.
        if cls == O.IssueUnexpandedExprFragUse then return false end
        if cls == O.IssueUnexpandedRegionFragUse then return false end
        if cls == O.IssueUnexpandedModuleUse then return false end
        if cls == O.IssueUnfilledContSlot then return false end
        return true
    end

    local function cascade_from_void(issue)
        local cls = pvm.classof(issue)
        if cls == Tr.TypeIssueExpected then return is_void_type(issue.expected) or is_void_type(issue.actual) end
        if cls == Tr.TypeIssueNotCallable then return is_void_type(issue.ty) end
        if cls == Tr.TypeIssueNotIndexable then return is_void_type(issue.ty) end
        if cls == Tr.TypeIssueNotPointer then return is_void_type(issue.ty) end
        if cls == Tr.TypeIssueInvalidUnary then return is_void_type(issue.ty) end
        if cls == Tr.TypeIssueInvalidBinary then return is_void_type(issue.lhs) or is_void_type(issue.rhs) end
        if cls == Tr.TypeIssueInvalidCompare then return is_void_type(issue.lhs) or is_void_type(issue.rhs) end
        if cls == Tr.TypeIssueInvalidLogic then return is_void_type(issue.lhs) or is_void_type(issue.rhs) end
        return false
    end

    local function publish_type_issue(issue, unresolved_values)
        local cls = pvm.classof(issue)
        if cls == Tr.TypeIssueInvalidControl then
            local rcls = pvm.classof(issue.reject)
            if rcls == Tr.ControlRejectUnterminatedBlock then return false end
        end
        if cls == Tr.TypeIssueUnresolvedValue and unresolved_values and unresolved_values[issue.name] then return false end
        if unresolved_values and next(unresolved_values) ~= nil and cascade_from_void(issue) then return false end
        return true
    end

    local function range_at_offset(analysis, one_based_offset)
        local index = P.build_index(analysis.parse.parts.document)
        local start_offset = math.max(0, (one_based_offset or 1) - 1)
        if start_offset > #analysis.parse.parts.document.text then start_offset = #analysis.parse.parts.document.text end
        local stop_offset = math.min(#analysis.parse.parts.document.text, start_offset + 1)
        return assert(P.range_from_offsets(index, start_offset, stop_offset))
    end

    local scalar_labels = {
        ScalarVoid = "void", ScalarBool = "bool",
        ScalarI8 = "i8", ScalarI16 = "i16", ScalarI32 = "i32", ScalarI64 = "i64",
        ScalarU8 = "u8", ScalarU16 = "u16", ScalarU32 = "u32", ScalarU64 = "u64",
        ScalarF32 = "f32", ScalarF64 = "f64", ScalarRawPtr = "rawptr", ScalarIndex = "index",
    }

    local function scalar_name(scalar)
        local cls = pvm.classof(scalar)
        return cls and (scalar_labels[cls.kind] or cls.kind) or tostring(scalar)
    end

    local function type_name(ty)
        local cls = pvm.classof(ty)
        if cls == Ty.TScalar then return scalar_name(ty.scalar) end
        if cls == Ty.TPtr then return "ptr(" .. type_name(ty.elem) .. ")" end
        if cls == Ty.TView then return "view(" .. type_name(ty.elem) .. ")" end
        if cls == Ty.TSlice then return "slice(" .. type_name(ty.elem) .. ")" end
        if cls == Ty.TArray then return "array(" .. type_name(ty.elem) .. ")" end
        if cls == Ty.TFunc then return "func(...) -> " .. type_name(ty.result) end
        if cls == Ty.TClosure then return "closure(...) -> " .. type_name(ty.result) end
        if cls == Ty.TNamed then
            local ref = ty.ref
            local rcls = pvm.classof(ref)
            if rcls == Ty.TypeRefGlobal then return ref.type_name end
            if rcls == Ty.TypeRefLocal then return ref.sym.name end
            if rcls == Ty.TypeRefPath then
                local parts = {}
                for i = 1, #ref.path.parts do parts[i] = ref.path.parts[i].text end
                return table.concat(parts, ".")
            end
        end
        return class_name(ty)
    end

    is_void_type = function(ty)
        return pvm.classof(ty) == Ty.TScalar and ty.scalar == C.ScalarVoid
    end

    local function range_for_label(analysis, label)
        local anchor = first_anchor_with_label(analysis.anchors, label)
        if anchor then return anchor.range end
        return full_range(analysis)
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
        ["Moon2Core.BinAdd"] = "+", ["Moon2Core.BinSub"] = "-", ["Moon2Core.BinMul"] = "*", ["Moon2Core.BinDiv"] = "/", ["Moon2Core.BinRem"] = "%",
        ["Moon2Core.BinBitAnd"] = "&", ["Moon2Core.BinBitOr"] = "|", ["Moon2Core.BinBitXor"] = "~", ["Moon2Core.BinShl"] = "<<", ["Moon2Core.BinLShr"] = ">>", ["Moon2Core.BinAShr"] = ">>",
        ["Moon2Core.CmpEq"] = "==", ["Moon2Core.CmpNe"] = "~=", ["Moon2Core.CmpLt"] = "<", ["Moon2Core.CmpLe"] = "<=", ["Moon2Core.CmpGt"] = ">", ["Moon2Core.CmpGe"] = ">=",
        ["Moon2Core.LogicAnd"] = "&&", ["Moon2Core.LogicOr"] = "||", ["Moon2Core.UnaryNot"] = "not", ["Moon2Core.UnaryNeg"] = "-", ["Moon2Core.UnaryBitNot"] = "~",
    }

    local function op_symbol(op)
        return op_symbols[tostring(op)] or tostring(op)
    end

    local function operator_range(analysis, op, ordinal)
        local anchor = nth_anchor_kind_label(analysis, S.AnchorOpaque("operator"), op_symbol(op), ordinal or 1)
        return anchor and anchor.range or full_range(analysis)
    end

    local function site_range(analysis, site)
        site = tostring(site or "")
        local name = site:match("^let%s+([_%a][_%w]*)") or site:match("^var%s+([_%a][_%w]*)") or site:match("^block param%s+([_%a][_%w]*)")
        if name then return range_for_label(analysis, name) end
        local keyword = site:match("^(return)") or site:match("^(yield)") or site:match("^(if)") or site:match("^(select)") or site:match("^(switch)")
        if keyword == "select" then keyword = "if" end
        local anchor = keyword and first_anchor_kind_label(analysis, S.AnchorKeyword, keyword)
        if anchor then return anchor.range end
        if site == "call" or site == "call arg" then
            anchor = first_anchor_kind_label(analysis, S.AnchorFunctionUse)
            if anchor then return anchor.range end
        end
        if site == "index" then
            anchor = first_anchor_kind_label(analysis, S.AnchorOpaque("operator"), "[")
            if anchor then return anchor.range end
        end
        return full_range(analysis)
    end

    local parse_issue_diag_phase = pvm.phase("moon2_editor_parse_issue_diagnostic", function(issue, analysis)
        local range = range_at_offset(analysis, issue.offset)
        return E.DiagnosticFact(E.DiagnosticError, E.DiagFromParse(issue), "parse", issue.message, range)
    end, { args_cache = "full" })

    local host_issue_diag_phase = pvm.phase("moon2_editor_host_issue_diagnostic", {
        [H.HostIssueInvalidName] = function(issue, analysis)
            return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromHost(issue), "host.invalidName", issue.site .. " has invalid name '" .. issue.name .. "'", range_for_label(analysis, issue.name)))
        end,
        [H.HostIssueExpected] = function(issue, analysis)
            return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromHost(issue), "host.expected", issue.site .. " expected " .. issue.expected .. ", got " .. issue.actual, full_range(analysis)))
        end,
        [H.HostIssueDuplicateField] = function(issue, analysis)
            return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromHost(issue), "host.duplicateField", "duplicate field '" .. issue.field_name .. "' in " .. issue.type_name, range_for_label(analysis, issue.field_name)))
        end,
        [H.HostIssueDuplicateType] = function(issue, analysis)
            return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromHost(issue), "host.duplicateType", "duplicate type '" .. issue.type_name .. "' in " .. issue.module_name, range_for_label(analysis, issue.type_name)))
        end,
        [H.HostIssueDuplicateDecl] = function(issue, analysis)
            local label = host_issue_label(H, issue)
            return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromHost(issue), "host.duplicateDecl", "duplicate host declaration '" .. issue.name .. "'", range_for_label(analysis, label)))
        end,
        [H.HostIssueDuplicateFunc] = function(issue, analysis)
            return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromHost(issue), "host.duplicateFunc", "duplicate function '" .. issue.func_name .. "' in " .. issue.module_name, range_for_label(analysis, issue.func_name)))
        end,
        [H.HostIssueUnsealedType] = function(issue, analysis)
            return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromHost(issue), "host.unsealedType", "unsealed type '" .. issue.type_name .. "'", range_for_label(analysis, issue.type_name)))
        end,
        [H.HostIssueSealedMutation] = function(issue, analysis)
            return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromHost(issue), "host.sealedMutation", "cannot mutate sealed type '" .. issue.type_name .. "'", range_for_label(analysis, issue.type_name)))
        end,
        [H.HostIssueAlreadySealed] = function(issue, analysis)
            return pvm.once(E.DiagnosticFact(E.DiagnosticWarning, E.DiagFromHost(issue), "host.alreadySealed", "type already sealed: " .. issue.type_name, range_for_label(analysis, issue.type_name)))
        end,
        [H.HostIssueUnknownBinding] = function(issue, analysis)
            return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromHost(issue), "host.unknownBinding", issue.site .. " references unknown binding '" .. issue.name .. "'", range_for_label(analysis, issue.name)))
        end,
        [H.HostIssueInvalidEmitFill] = function(issue, analysis)
            return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromHost(issue), "host.invalidEmitFill", "invalid emit fill '" .. issue.fill_name .. "' for " .. issue.fragment_name, full_range(analysis)))
        end,
        [H.HostIssueMissingEmitFill] = function(issue, analysis)
            return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromHost(issue), "host.missingEmitFill", "missing emit fill '" .. issue.fill_name .. "' for " .. issue.fragment_name, full_range(analysis)))
        end,
        [H.HostIssueInvalidPackedAlign] = function(issue, analysis)
            return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromHost(issue), "host.invalidPackedAlign", "invalid packed alignment " .. tostring(issue.align) .. " for " .. issue.type_name, range_for_label(analysis, issue.type_name)))
        end,
        [H.HostIssueBareBoolInBoundaryStruct] = function(issue, analysis)
            return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromHost(issue), "host.bareBoolBoundary", "boundary struct field '" .. issue.field_name .. "' in " .. issue.type_name .. " must use explicit bool storage", range_for_label(analysis, issue.field_name)))
        end,
        [H.HostIssueArgCount] = function(issue, analysis)
            return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromHost(issue), "host.argCount", issue.site .. " expected " .. tostring(issue.expected) .. " args, got " .. tostring(issue.actual), full_range(analysis)))
        end,
    }, { args_cache = "full" })

    local open_issue_diag_phase = pvm.phase("moon2_editor_open_issue_diagnostic", function(issue, analysis)
        return E.DiagnosticFact(E.DiagnosticError, E.DiagFromOpen(issue), "open." .. class_name(issue), class_name(issue), full_range(analysis))
    end, { args_cache = "full" })

    local function path_text(path)
        local parts = {}
        for i = 1, #(path.parts or {}) do parts[i] = path.parts[i].text end
        return table.concat(parts, ".")
    end

    local function control_reject_message(reject)
        local cls = pvm.classof(reject)
        if cls == Tr.ControlRejectDuplicateLabel then return "duplicate control label '" .. reject.label.name .. "'" end
        if cls == Tr.ControlRejectMissingLabel then return "missing control label '" .. reject.label.name .. "'" end
        if cls == Tr.ControlRejectMissingJumpArg then return "missing jump argument '" .. reject.name .. "' for " .. reject.label.name end
        if cls == Tr.ControlRejectExtraJumpArg then return "extra jump argument '" .. reject.name .. "' for " .. reject.label.name end
        if cls == Tr.ControlRejectDuplicateJumpArg then return "duplicate jump argument '" .. reject.name .. "' for " .. reject.label.name end
        if cls == Tr.ControlRejectJumpType then return "jump argument '" .. reject.name .. "' for " .. reject.label.name .. " expected " .. type_name(reject.expected) .. ", got " .. type_name(reject.actual) end
        if cls == Tr.ControlRejectYieldOutsideRegion then return reject.reason end
        if cls == Tr.ControlRejectYieldType then return "yield expected " .. type_name(reject.expected) .. ", got " .. type_name(reject.actual) end
        if cls == Tr.ControlRejectUnterminatedBlock then return "unterminated control block '" .. reject.label.name .. "'" end
        if cls == Tr.ControlRejectIrreducible then return "irreducible control flow: " .. reject.reason end
        return class_name(reject)
    end

    local function control_reject_range(analysis, reject)
        local cls = pvm.classof(reject)
        if cls == Tr.ControlRejectDuplicateLabel or cls == Tr.ControlRejectMissingLabel or cls == Tr.ControlRejectUnterminatedBlock then return range_for_label(analysis, reject.label.name) end
        if cls == Tr.ControlRejectMissingJumpArg or cls == Tr.ControlRejectExtraJumpArg or cls == Tr.ControlRejectDuplicateJumpArg or cls == Tr.ControlRejectJumpType then return range_for_label(analysis, reject.name) end
        return full_range(analysis)
    end

    local type_issue_diag_phase = pvm.phase("moon2_editor_type_issue_diagnostic", {
        [Tr.TypeIssueUnresolvedValue] = function(issue, analysis)
            return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromType(issue), "type.unresolvedValue", "unresolved value '" .. issue.name .. "'", range_for_label(analysis, issue.name)))
        end,
        [Tr.TypeIssueUnresolvedPath] = function(issue, analysis)
            local text = path_text(issue.path)
            return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromType(issue), "type.unresolvedPath", "unresolved path '" .. text .. "'", range_for_label(analysis, issue.path.parts[1] and issue.path.parts[1].text or text)))
        end,
        [Tr.TypeIssueExpected] = function(issue, analysis)
            return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromType(issue), "type.expected", issue.site .. " expected " .. type_name(issue.expected) .. ", got " .. type_name(issue.actual), site_range(analysis, issue.site)))
        end,
        [Tr.TypeIssueArgCount] = function(issue, analysis)
            return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromType(issue), "type.argCount", issue.site .. " expected " .. tostring(issue.expected) .. " args, got " .. tostring(issue.actual), site_range(analysis, issue.site)))
        end,
        [Tr.TypeIssueNotCallable] = function(issue, analysis)
            local anchor = first_anchor_kind_label(analysis, S.AnchorFunctionUse)
            return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromType(issue), "type.notCallable", "not callable: " .. type_name(issue.ty), anchor and anchor.range or full_range(analysis)))
        end,
        [Tr.TypeIssueNotIndexable] = function(issue, analysis)
            return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromType(issue), "type.notIndexable", "not indexable: " .. type_name(issue.ty), full_range(analysis)))
        end,
        [Tr.TypeIssueNotPointer] = function(issue, analysis)
            return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromType(issue), "type.notPointer", "not a pointer: " .. type_name(issue.ty), full_range(analysis)))
        end,
        [Tr.TypeIssueInvalidUnary] = function(issue, analysis, ordinal)
            return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromType(issue), "type.invalidUnary", "invalid unary operand for " .. op_symbol(issue.op) .. ": " .. type_name(issue.ty), operator_range(analysis, issue.op, ordinal)))
        end,
        [Tr.TypeIssueInvalidBinary] = function(issue, analysis, ordinal)
            return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromType(issue), "type.invalidBinary", "invalid binary operands for " .. op_symbol(issue.op) .. ": " .. type_name(issue.lhs) .. " and " .. type_name(issue.rhs), operator_range(analysis, issue.op, ordinal)))
        end,
        [Tr.TypeIssueInvalidCompare] = function(issue, analysis, ordinal)
            return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromType(issue), "type.invalidCompare", "invalid comparison operands for " .. op_symbol(issue.op) .. ": " .. type_name(issue.lhs) .. " and " .. type_name(issue.rhs), operator_range(analysis, issue.op, ordinal)))
        end,
        [Tr.TypeIssueInvalidLogic] = function(issue, analysis, ordinal)
            return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromType(issue), "type.invalidLogic", "logical expression expected bool operands, got " .. type_name(issue.lhs) .. " and " .. type_name(issue.rhs), operator_range(analysis, "Moon2Core.LogicAnd", ordinal)))
        end,
        [Tr.TypeIssueMissingJumpTarget] = function(issue, analysis)
            return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromType(issue), "type.missingJumpTarget", "missing jump target '" .. issue.label.name .. "'", range_for_label(analysis, issue.label.name)))
        end,
        [Tr.TypeIssueMissingJumpArg] = function(issue, analysis)
            return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromType(issue), "type.missingJumpArg", "missing jump argument '" .. issue.name .. "' for " .. issue.label.name, range_for_label(analysis, issue.name)))
        end,
        [Tr.TypeIssueExtraJumpArg] = function(issue, analysis)
            return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromType(issue), "type.extraJumpArg", "extra jump argument '" .. issue.name .. "' for " .. issue.label.name, range_for_label(analysis, issue.name)))
        end,
        [Tr.TypeIssueDuplicateJumpArg] = function(issue, analysis)
            return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromType(issue), "type.duplicateJumpArg", "duplicate jump argument '" .. issue.name .. "' for " .. issue.label.name, range_for_label(analysis, issue.name)))
        end,
        [Tr.TypeIssueUnexpectedYield] = function(issue, analysis)
            return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromType(issue), "type.unexpectedYield", "unexpected " .. issue.site, site_range(analysis, "yield")))
        end,
        [Tr.TypeIssueInvalidControl] = function(issue, analysis)
            return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromType(issue), "type.invalidControl", control_reject_message(issue.reject), control_reject_range(analysis, issue.reject)))
        end,
    }, { args_cache = "full" })

    local function unresolved_type_issue_names(issues)
        local out = {}
        for i = 1, #issues do
            local issue = issues[i]
            if pvm.classof(issue) == Tr.TypeIssueUnresolvedValue then out[issue.name] = true end
        end
        return out
    end

    local function publish_binding_resolution(resolution, type_unresolved_names)
        if pvm.classof(resolution) ~= E.BindingUnresolved then return false end
        if resolution.use.anchor.id.text:find("value%.use%.", 1) == nil then return false end
        return type_unresolved_names[resolution.use.anchor.label] == true
    end

    local binding_resolution_diag_phase = pvm.phase("moon2_editor_binding_resolution_diagnostic", {
        [E.BindingUnresolved] = function(resolution)
            local name = resolution.use.anchor.label
            return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromBindingResolution(resolution), "binding.unresolved", "unresolved binding '" .. name .. "'", resolution.use.anchor.range))
        end,
        [E.BindingResolved] = function()
            return pvm.empty()
        end,
    }, { args_cache = "full" })

    local function id_text(id)
        return (id and id.text) or tostring(id)
    end

    local function back_range(analysis)
        return full_range(analysis)
    end

    local back_issue_diag_phase = pvm.phase("moon2_editor_back_issue_diagnostic", {
        [B.BackIssueEmptyProgram] = function(issue, analysis) return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromBack(issue), "back.emptyProgram", "backend command stream is empty", back_range(analysis))) end,
        [B.BackIssueMissingFinalize] = function(issue, analysis) return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromBack(issue), "back.missingFinalize", "backend command stream is missing finalization", back_range(analysis))) end,
        [B.BackIssueCommandAfterFinalize] = function(issue, analysis) return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromBack(issue), "back.commandAfterFinalize", "backend command after finalize at #" .. tostring(issue.index), back_range(analysis))) end,
        [B.BackIssueCommandOutsideFunction] = function(issue, analysis) return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromBack(issue), "back.commandOutsideFunction", "backend command outside function at #" .. tostring(issue.index), back_range(analysis))) end,
        [B.BackIssueNestedFunction] = function(issue, analysis) return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromBack(issue), "back.nestedFunction", "nested backend function " .. id_text(issue.next) .. " while " .. id_text(issue.active) .. " is active", back_range(analysis))) end,
        [B.BackIssueFinishWithoutBegin] = function(issue, analysis) return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromBack(issue), "back.finishWithoutBegin", "finish without begin for " .. id_text(issue.func), back_range(analysis))) end,
        [B.BackIssueFinishWrongFunction] = function(issue, analysis) return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromBack(issue), "back.finishWrongFunction", "finish wrong function: expected " .. id_text(issue.expected) .. ", got " .. id_text(issue.actual), back_range(analysis))) end,
        [B.BackIssueUnfinishedFunction] = function(issue, analysis) return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromBack(issue), "back.unfinishedFunction", "unfinished backend function " .. id_text(issue.func), back_range(analysis))) end,
        [B.BackIssueDuplicateSig] = function(issue, analysis) return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromBack(issue), "back.duplicateSig", "duplicate backend signature " .. id_text(issue.sig), back_range(analysis))) end,
        [B.BackIssueDuplicateData] = function(issue, analysis) return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromBack(issue), "back.duplicateData", "duplicate backend data " .. id_text(issue.data), back_range(analysis))) end,
        [B.BackIssueDuplicateFunc] = function(issue, analysis) return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromBack(issue), "back.duplicateFunc", "duplicate backend function " .. id_text(issue.func), back_range(analysis))) end,
        [B.BackIssueDuplicateExtern] = function(issue, analysis) return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromBack(issue), "back.duplicateExtern", "duplicate backend extern " .. id_text(issue.func), back_range(analysis))) end,
        [B.BackIssueDuplicateBlock] = function(issue, analysis) return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromBack(issue), "back.duplicateBlock", "duplicate backend block " .. id_text(issue.block), back_range(analysis))) end,
        [B.BackIssueDuplicateStackSlot] = function(issue, analysis) return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromBack(issue), "back.duplicateStackSlot", "duplicate backend stack slot " .. id_text(issue.slot), back_range(analysis))) end,
        [B.BackIssueDuplicateValue] = function(issue, analysis) return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromBack(issue), "back.duplicateValue", "duplicate backend value " .. id_text(issue.value), back_range(analysis))) end,
        [B.BackIssueMissingSig] = function(issue, analysis) return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromBack(issue), "back.missingSig", "missing backend signature " .. id_text(issue.sig), back_range(analysis))) end,
        [B.BackIssueMissingData] = function(issue, analysis) return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromBack(issue), "back.missingData", "missing backend data " .. id_text(issue.data), back_range(analysis))) end,
        [B.BackIssueMissingFunc] = function(issue, analysis) return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromBack(issue), "back.missingFunc", "missing backend function " .. id_text(issue.func), back_range(analysis))) end,
        [B.BackIssueMissingExtern] = function(issue, analysis) return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromBack(issue), "back.missingExtern", "missing backend extern " .. id_text(issue.func), back_range(analysis))) end,
        [B.BackIssueMissingBlock] = function(issue, analysis) return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromBack(issue), "back.missingBlock", "missing backend block " .. id_text(issue.block), back_range(analysis))) end,
        [B.BackIssueMissingStackSlot] = function(issue, analysis) return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromBack(issue), "back.missingStackSlot", "missing backend stack slot " .. id_text(issue.slot), back_range(analysis))) end,
        [B.BackIssueMissingValue] = function(issue, analysis) return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromBack(issue), "back.missingValue", "missing backend value " .. id_text(issue.value), back_range(analysis))) end,
        [B.BackIssueShapeRequiresScalar] = function(issue, analysis) return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromBack(issue), "back.shapeRequiresScalar", "backend shape requires scalar at #" .. tostring(issue.index), back_range(analysis))) end,
        [B.BackIssueShapeRequiresVector] = function(issue, analysis) return pvm.once(E.DiagnosticFact(E.DiagnosticError, E.DiagFromBack(issue), "back.shapeRequiresVector", "backend shape requires vector at #" .. tostring(issue.index), back_range(analysis))) end,
    }, { args_cache = "full" })

    local vec_reject_diag_phase = pvm.phase("moon2_editor_vec_reject_diagnostic", function(reject, analysis)
        return E.DiagnosticFact(E.DiagnosticInformation, E.DiagFromVectorReject(reject), "vec." .. class_name(reject), class_name(reject), full_range(analysis))
    end, { args_cache = "full" })

    local document_diagnostics_phase = pvm.phase("moon2_editor_document_diagnostics", {
        [Mlua.DocumentAnalysis] = function(analysis)
            local diagnostics = {}
            for i = 1, #analysis.parse.combined.issues do
                diagnostics[#diagnostics + 1] = pvm.one(parse_issue_diag_phase(analysis.parse.combined.issues[i], analysis))
            end
            for i = 1, #analysis.host.report.issues do
                local g, p, c = host_issue_diag_phase(analysis.host.report.issues[i], analysis)
                pvm.drain_into(g, p, c, diagnostics)
            end
            for i = 1, #analysis.open_report.issues do
                if publish_open_issue(analysis.open_report.issues[i]) then
                    diagnostics[#diagnostics + 1] = pvm.one(open_issue_diag_phase(analysis.open_report.issues[i], analysis))
                end
            end
            local unresolved_values = {}
            local type_unresolved_names = unresolved_type_issue_names(analysis.type_issues)
            local binding_report = ScopeFacts.report(analysis)
            for i = 1, #binding_report.resolutions do
                local resolution = binding_report.resolutions[i]
                if publish_binding_resolution(resolution, type_unresolved_names) then
                    unresolved_values[resolution.use.anchor.label] = true
                    local g, p, c = binding_resolution_diag_phase(resolution, analysis)
                    pvm.drain_into(g, p, c, diagnostics)
                end
            end
            local type_occurrences = {}
            for i = 1, #analysis.type_issues do
                local issue = analysis.type_issues[i]
                local cls = pvm.classof(issue)
                local key = cls and cls.kind or tostring(issue)
                if cls == Tr.TypeIssueInvalidUnary or cls == Tr.TypeIssueInvalidBinary or cls == Tr.TypeIssueInvalidCompare then key = key .. ":" .. op_symbol(issue.op) end
                if cls == Tr.TypeIssueInvalidLogic then key = key .. ":logic" end
                type_occurrences[key] = (type_occurrences[key] or 0) + 1
                if publish_type_issue(issue, unresolved_values) then
                    diagnostics[#diagnostics + 1] = pvm.one(type_issue_diag_phase(issue, analysis, type_occurrences[key]))
                end
            end
            for i = 1, #analysis.back_report.issues do
                diagnostics[#diagnostics + 1] = pvm.one(back_issue_diag_phase(analysis.back_report.issues[i], analysis))
            end
            -- Vector rejects are optimization planning facts, not source-language
            -- diagnostics. Keep them in DocumentAnalysis for compiler/editor
            -- queries, but do not publish them as LSP diagnostics by default.
            return pvm.seq(diagnostics)
        end,
    })

    local function diagnostics(analysis)
        return pvm.drain(document_diagnostics_phase(analysis))
    end

    return {
        document_diagnostics_phase = document_diagnostics_phase,
        parse_issue_diag_phase = parse_issue_diag_phase,
        host_issue_diag_phase = host_issue_diag_phase,
        open_issue_diag_phase = open_issue_diag_phase,
        type_issue_diag_phase = type_issue_diag_phase,
        back_issue_diag_phase = back_issue_diag_phase,
        vec_reject_diag_phase = vec_reject_diag_phase,
        binding_resolution_diag_phase = binding_resolution_diag_phase,
        diagnostics = diagnostics,
    }
end

return M
