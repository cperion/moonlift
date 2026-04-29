local pvm = require("moonlift.pvm")
local SourceTextApply = require("moonlift.source_text_apply")

local M = {}

local function copy_array(xs)
    local out = {}
    for i = 1, #xs do out[i] = xs[i] end
    return out
end

local function uri_eq(a, b)
    return a == b or (a and b and a.text == b.text)
end

local function find_doc(docs, uri)
    for i = 1, #docs do
        if uri_eq(docs[i].uri, uri) then return i, docs[i] end
    end
    return nil, nil
end

function M.Define(T)
    local E = T.Moon2Editor
    local SourceApply = SourceTextApply.Define(T)

    local function initial_state()
        return E.WorkspaceState(E.ServerCreated, {}, {}, {})
    end

    local function with_docs(state, docs)
        return pvm.with(state, { open_docs = docs })
    end

    local function upsert_doc(state, document)
        local docs = copy_array(state.open_docs)
        local idx = find_doc(docs, document.uri)
        if idx then docs[idx] = document else docs[#docs + 1] = document end
        return with_docs(state, docs)
    end

    local function remove_doc(state, uri)
        local docs = {}
        for i = 1, #state.open_docs do
            local doc = state.open_docs[i]
            if not uri_eq(doc.uri, uri) then
                docs[#docs + 1] = doc
            end
        end
        return with_docs(state, docs)
    end

    local client_initialized_class = pvm.classof(E.ClientInitialized)
    local client_exit_class = pvm.classof(E.ClientExit)
    local function is_bare(cls, event, variant, variant_class)
        return event == variant or (variant_class ~= false and cls == variant_class)
    end

    local apply_event_phase = pvm.phase("moon2_editor_workspace_apply", function(event, state)
        local before = state
        local cls = pvm.classof(event)
        local after = before

        if cls == E.ClientInitialize then
            after = E.WorkspaceState(E.ServerInitializing, event.roots, event.capabilities, before.open_docs)
        elseif is_bare(cls, event, E.ClientInitialized, client_initialized_class) then
            after = pvm.with(before, { mode = E.ServerReady })
        elseif cls == E.ClientShutdown then
            after = pvm.with(before, { mode = E.ServerShutdownRequested })
        elseif is_bare(cls, event, E.ClientExit, client_exit_class) then
            after = pvm.with(before, { mode = E.ServerStopped })
        elseif cls == E.ClientDidOpen then
            after = upsert_doc(before, event.document)
        elseif cls == E.ClientDidChange then
            local _, doc = find_doc(before.open_docs, event.edit.uri)
            if doc then
                local result = SourceApply.apply(doc, event.edit)
                if pvm.classof(result) == T.Moon2Source.SourceApplyOk then
                    after = upsert_doc(before, result.document)
                end
            end
        elseif cls == E.ClientDidClose then
            after = remove_doc(before, event.uri)
        elseif cls == E.ClientDidSave then
            after = before
        else
            -- Queries and unsupported/ignored events are explicit events, but
            -- they do not mutate workspace source state.
            after = before
        end

        return E.Transition(before, event, after)
    end, { args_cache = "last" })

    local function apply_event(state, event)
        return pvm.one(apply_event_phase(event, state))
    end

    return {
        initial_state = initial_state,
        apply_event_phase = apply_event_phase,
        apply_event = apply_event,
        find_doc = find_doc,
    }
end

return M
