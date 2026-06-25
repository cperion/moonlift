local function bind_context(T)
    local L = T.LalinLsp

    local capabilities_json = [[{"textDocumentSync":{"openClose":true,"change":1},"hoverProvider":true,"documentSymbolProvider":true,"diagnosticProvider":{"interFileDependencies":false,"workspaceDiagnostics":false},"completionProvider":{"triggerCharacters":[".",":","("," "]},"signatureHelpProvider":{"triggerCharacters":["(",","],"retriggerCharacters":[","]},"definitionProvider":true,"referencesProvider":true,"documentHighlightProvider":true,"renameProvider":{"prepareProvider":true},"codeActionProvider":true,"selectionRangeProvider":true,"positionEncoding":"utf-16"}]]

    local function initialize_result()
        return L.InitializeResult("lalin-lsp", "utf-16", capabilities_json)
    end

    return {
        capabilities_json = capabilities_json,
        initialize_result = initialize_result,
    }
end

return bind_context