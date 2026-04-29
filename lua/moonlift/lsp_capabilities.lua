local M = {}

function M.Define(T)
    local L = (T.MoonLsp or T.Moon2Lsp)

    local capabilities_json = [[{"textDocumentSync":{"openClose":true,"change":1},"hoverProvider":true,"documentSymbolProvider":true,"diagnosticProvider":{"interFileDependencies":false,"workspaceDiagnostics":false},"completionProvider":{"triggerCharacters":[".",":","("," "]},"signatureHelpProvider":{"triggerCharacters":["(",","],"retriggerCharacters":[","]},"definitionProvider":true,"referencesProvider":true,"documentHighlightProvider":true,"renameProvider":{"prepareProvider":true},"codeActionProvider":true,"foldingRangeProvider":true,"selectionRangeProvider":true,"inlayHintProvider":true,"semanticTokensProvider":{"full":true,"range":true,"legend":{"tokenTypes":["namespace","type","class","enum","interface","struct","typeParameter","parameter","variable","property","enumMember","event","function","method","macro","keyword","modifier","comment","string","number","regexp","operator","decorator"],"tokenModifiers":["declaration","definition","readonly","static","deprecated","abstract","async","modification","documentation","defaultLibrary","mutable","exported","storage","diagnostic"]}},"positionEncoding":"utf-16"}]]

    local function initialize_result()
        return L.InitializeResult("moonlift-lsp", "utf-16", capabilities_json)
    end

    return {
        capabilities_json = capabilities_json,
        initialize_result = initialize_result,
    }
end

return M
