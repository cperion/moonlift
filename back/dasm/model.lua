local pvm = require("lalin.pvm")
local A2 = require("lalin.asdl")

local M = {}

local CTX = nil

function M.set_context(T)
    CTX = T
    if T and (not T.LalinBack or not T.LalinDasm) then A2.Define(T) end
end

local function ensure_context()
    if not CTX then error("back.dasm.model: context not set; call Mx.set_context(T) first", 2) end
    if not CTX.LalinBack or not CTX.LalinDasm then A2.Define(CTX) end
    return CTX
end

function M.context() return ensure_context() end
function M.back() return ensure_context().LalinBack end
function M.dasm() return ensure_context().LalinDasm end

function M.idkey(v)
    return type(v) == "string" and v or (v and v.text) or nil
end

function M.to_label(key)
    local s = tostring(key or "")
    s = s:gsub("[^%w_@]", "_")
    if s == "" then s = "_" end
    if not s:match("^[%a_]") then s = "_" .. s end
    return s
end

function M.scalar_kind(s)
    if type(s) == "table" then return s.kind end
    return nil
end

function M.shape_scalar_kind(shape)
    if type(shape) ~= "table" then return nil end
    if shape.kind == "BackShapeScalar" and shape.scalar then return shape.scalar.kind end
    return nil
end

function M.is_float_scalar(sk)
    return sk == "BackF32" or sk == "BackF64"
end

local function as_back_id(v, ctor_name)
    local B = M.back()
    local k = M.idkey(v)
    if not k then return v end
    local ctor = B[ctor_name]
    local cls = pvm.classof(v)
    if cls and cls == ctor then return v end
    return ctor(k)
end

function M.back_val_id(v) return as_back_id(v, "BackValId") end
function M.back_block_id(v) return as_back_id(v, "BackBlockId") end
function M.back_func_id(v) return as_back_id(v, "BackFuncId") end
function M.back_sig_id(v) return as_back_id(v, "BackSigId") end
function M.back_slot_id(v) return as_back_id(v, "BackStackSlotId") end

function M.make_phase_func(cmds, func)
    local D = M.dasm()
    return D.DPhaseFunc(func, cmds)
end

function M.scalar_entries_from_map(map)
    local D = M.dasm()
    local ks, out = {}, {}
    for k in pairs(map or {}) do ks[#ks + 1] = k end
    table.sort(ks)
    for i = 1, #ks do
        local k = ks[i]
        out[#out + 1] = D.DScalarMapEntry(k, map[k])
    end
    return out
end

function M.scalar_map_from_entries(entries)
    local out = {}
    for i = 1, #(entries or {}) do
        local e = entries[i]
        out[e.key] = e.scalar
    end
    return out
end

function M.phase_func_cmds(v)
    local D = M.dasm()
    if pvm.classof(v) ~= D.DPhaseFunc then
        error("expected LalinDasm.DPhaseFunc", 2)
    end
    return v.cmds
end

function M.phase_func_id(v)
    local D = M.dasm()
    if pvm.classof(v) ~= D.DPhaseFunc then
        error("expected LalinDasm.DPhaseFunc", 2)
    end
    return v.func
end

local function to_label_pairs(map)
    local ks, out = {}, {}
    for k in pairs(map or {}) do ks[#ks + 1] = k end
    table.sort(ks)
    for i = 1, #ks do out[#out + 1] = { key = ks[i], label = map[ks[i]] } end
    return out
end

local function from_label_pairs(pairs)
    local out = {}
    for i = 1, #(pairs or {}) do
        local p = pairs[i]
        out[p.key] = p.label
    end
    return out
end

function M.make_phase_module(sigs, funcs, externs, datas, fkeys, ekeys, dkeys, labels)
    local D = M.dasm()
    labels = labels or { funcs = {}, externs = {}, datas = {} }

    local sig_entries, func_entries, extern_entries, data_entries = {}, {}, {}, {}

    local skeys = {}
    for k in pairs(sigs or {}) do skeys[#skeys + 1] = k end
    table.sort(skeys)
    for i = 1, #skeys do
        local k = skeys[i]
        local s = sigs[k]
        sig_entries[#sig_entries + 1] = D.DSigEntry(k, s.params or {}, s.results or {})
    end

    for i = 1, #(fkeys or {}) do
        local k = fkeys[i]
        local f = funcs[k]
        func_entries[#func_entries + 1] = D.DFuncEntry(k, f.sig, f.visibility or "VisibilityPrivate", f.body or {})
    end

    for i = 1, #(ekeys or {}) do
        local k = ekeys[i]
        local e = externs[k]
        extern_entries[#extern_entries + 1] = D.DExternEntry(k, e.symbol, e.sig)
    end

    for i = 1, #(dkeys or {}) do
        local k = dkeys[i]
        local d = datas[k]
        data_entries[#data_entries + 1] = D.DDataEntry(k, d.buf, d.size or 0, d.align or 1)
    end

    local lpf, lpe, lpd = {}, {}, {}
    local fl = to_label_pairs(labels.funcs)
    for i = 1, #fl do lpf[i] = D.DLabelPair(fl[i].key, fl[i].label) end
    local el = to_label_pairs(labels.externs)
    for i = 1, #el do lpe[i] = D.DLabelPair(el[i].key, el[i].label) end
    local dl = to_label_pairs(labels.datas)
    for i = 1, #dl do lpd[i] = D.DLabelPair(dl[i].key, dl[i].label) end

    return D.DPhaseModule(
        sig_entries,
        func_entries,
        extern_entries,
        data_entries,
        fkeys or {},
        ekeys or {},
        dkeys or {},
        D.DLabelMap(lpf, lpe, lpd)
    )
end

function M.phase_module_maps(v)
    local D = M.dasm()
    if pvm.classof(v) ~= D.DPhaseModule then
        error("expected LalinDasm.DPhaseModule", 2)
    end

    local out = {
        sigs = {}, funcs = {}, externs = {}, datas = {},
        fkeys = {}, ekeys = {}, dkeys = {},
        labels = { funcs = {}, externs = {}, datas = {} },
    }

    for i = 1, #(v.sigs or {}) do
        local s = v.sigs[i]
        out.sigs[s.key] = { params = s.params, results = s.results }
    end
    for i = 1, #(v.funcs or {}) do
        local f = v.funcs[i]
        out.funcs[f.key] = { sig = f.sig, visibility = f.visibility, body = f.body }
    end
    for i = 1, #(v.externs or {}) do
        local e = v.externs[i]
        out.externs[e.key] = { symbol = e.symbol, sig = e.sig }
    end
    for i = 1, #(v.datas or {}) do
        local d = v.datas[i]
        out.datas[d.key] = { buf = d.buf, size = d.size, align = d.align }
    end

    for i = 1, #(v.func_order or {}) do out.fkeys[i] = v.func_order[i] end
    for i = 1, #(v.extern_order or {}) do out.ekeys[i] = v.extern_order[i] end
    for i = 1, #(v.data_order or {}) do out.dkeys[i] = v.data_order[i] end

    if #out.fkeys == 0 then for k in pairs(out.funcs) do out.fkeys[#out.fkeys + 1] = k end table.sort(out.fkeys) end
    if #out.ekeys == 0 then for k in pairs(out.externs) do out.ekeys[#out.ekeys + 1] = k end table.sort(out.ekeys) end
    if #out.dkeys == 0 then for k in pairs(out.datas) do out.dkeys[#out.dkeys + 1] = k end table.sort(out.dkeys) end

    out.labels.funcs = from_label_pairs(v.labels and v.labels.funcs or {})
    out.labels.externs = from_label_pairs(v.labels and v.labels.externs or {})
    out.labels.datas = from_label_pairs(v.labels and v.labels.datas or {})

    return out
end

return M
