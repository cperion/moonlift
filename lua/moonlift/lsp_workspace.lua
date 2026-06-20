local pvm = require("moonlift.pvm")
local Uri = require("moonlift.lsp_uri")
local FileScan = require("moonlift.lsp_file_scan")

local M = {}

local function read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
end

local function doc_fingerprint(doc)
    return tostring(doc.version.value) .. ":" .. tostring(#doc.text)
end

local function uri_key(uri)
    return Uri.uri_text(uri)
end

function M.Define(T)
    local S = T.MoonSource
    local E = T.MoonEditor

    local function open_file_entry(doc)
        return E.WorkspaceFile(doc.uri, Uri.uri_to_path(doc.uri) or "", doc.language, doc.version, E.WorkspaceFileOpen, doc_fingerprint(doc))
    end

    local function disk_file_entry(file)
        return E.WorkspaceFile(S.DocUri(file.uri), file.path, S.LangMlua, S.DocVersion(0), E.WorkspaceFileDisk, file.path)
    end

    local function scan_roots(roots)
        local files, seen = {}, {}
        for i = 1, #(roots or {}) do
            local root_path = Uri.uri_to_path(roots[i].uri)
            for _, file in ipairs(FileScan.scan(root_path)) do
                if not seen[file.uri] then
                    seen[file.uri] = true
                    files[#files + 1] = disk_file_entry(file)
                end
            end
        end
        return files
    end

    local function build_index(state, generation)
        local files, by_uri = {}, {}
        for _, file in ipairs(scan_roots(state.roots)) do
            files[#files + 1] = file
            by_uri[uri_key(file.uri)] = #files
        end
        for i = 1, #state.open_docs do
            local file = open_file_entry(state.open_docs[i])
            local key = uri_key(file.uri)
            local idx = by_uri[key]
            if idx then files[idx] = file else files[#files + 1] = file end
            by_uri[key] = idx or #files
        end
        table.sort(files, function(a, b) return a.uri.text < b.uri.text end)
        return E.WorkspaceIndex(generation or ((state.index and state.index.generation or 0) + 1), files)
    end

    local function sync_after_event(state, event)
        local cls = pvm.classof(event)
        if cls == E.ClientInitialize or cls == E.ClientDidOpen or cls == E.ClientDidClose or cls == E.ClientDidSave then
            return pvm.with(state, { index = build_index(state) })
        elseif cls == E.ClientDidChange then
            return pvm.with(state, { index = build_index(state, (state.index and state.index.generation or 0) + 1) })
        end
        return state
    end

    local function open_doc(state, uri)
        for i = 1, #state.open_docs do
            if Uri.same_uri(state.open_docs[i].uri, uri) then return state.open_docs[i] end
        end
        return nil
    end

    local function indexed_file(state, uri)
        local key = uri_key(uri)
        for i = 1, #(state.index and state.index.files or {}) do
            if uri_key(state.index.files[i].uri) == key then return state.index.files[i] end
        end
        return nil
    end

    local function document_for_uri(state, uri)
        local doc = open_doc(state, uri)
        if doc then return doc end
        local file = indexed_file(state, uri)
        if not file or file.origin ~= E.WorkspaceFileDisk or file.path == "" then return nil end
        local text = read_file(file.path)
        if not text then return nil end
        return S.DocumentSnapshot(file.uri, file.version, file.language, text)
    end

    local function open_documents(state)
        local docs, seen = {}, {}
        for i = 1, #state.open_docs do
            local doc = state.open_docs[i]
            docs[#docs + 1] = doc
            seen[uri_key(doc.uri)] = true
        end
        return docs, seen
    end

    local function documents(state, opts)
        opts = opts or {}
        local docs, seen = open_documents(state)
        if not opts.include_disk then return docs end
        local max_disk = opts.max_disk or 32
        local added_disk = 0
        for i = 1, #(state.index and state.index.files or {}) do
            local file = state.index.files[i]
            if file.origin == E.WorkspaceFileDisk and not seen[uri_key(file.uri)] then
                local text = file.path ~= "" and read_file(file.path) or nil
                if text then
                    docs[#docs + 1] = S.DocumentSnapshot(file.uri, file.version, file.language, text)
                    seen[uri_key(file.uri)] = true
                    added_disk = added_disk + 1
                    if added_disk >= max_disk then break end
                end
            end
        end
        return docs
    end

    return {
        build_index = build_index,
        sync_after_event = sync_after_event,
        document_for_uri = document_for_uri,
        open_documents = open_documents,
        documents = documents,
    }
end

return M
