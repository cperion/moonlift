local M = {}

M.SCHEMA = [[
module MoonliftLsp {
    Document = (string uri, number version, string text) unique
    Position = (number line, number character) unique
    Range = (MoonliftLsp.Position start, MoonliftLsp.Position stop) unique

    DiagnosticSeverity = DiagError | DiagWarning | DiagInfo | DiagHint
    Diagnostic = (MoonliftLsp.Range range, MoonliftLsp.DiagnosticSeverity severity, string source, string message) unique

    IslandKind = IslandStruct | IslandExpose | IslandFunc | IslandModule | IslandRegion | IslandExpr
    Island = (MoonliftLsp.IslandKind kind, string name, MoonliftLsp.Range range, MoonliftLsp.Range selection_range, number start_offset, number stop_offset, string source) unique

    SymbolKind = SymFile | SymModule | SymStruct | SymField | SymFunction | SymProperty | SymVariable
    Symbol = (string name, MoonliftLsp.SymbolKind kind, MoonliftLsp.Range range, MoonliftLsp.Range selection_range, MoonliftLsp.Symbol* children) unique

    HoverQuery = (MoonliftLsp.Document document, MoonliftLsp.Position position) unique
    Hover = (MoonliftLsp.Range range, string markdown) unique

    CompletionQuery = (MoonliftLsp.Document document, MoonliftLsp.Position position) unique
    CompletionItem = (string label, string detail, string insert_text, number kind) unique
}
]]

function M.Define(T)
    if not T.Moon2Core then require("moonlift.asdl").Define(T) end
    if not T.MoonliftLsp then T:Define(M.SCHEMA) end
    return T
end

function M.context(opts)
    local pvm = require("moonlift.pvm")
    return M.Define(pvm.context(opts))
end

return M
