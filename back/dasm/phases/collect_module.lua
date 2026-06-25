local ffi = require("ffi")
local pvm = require("lalin.pvm")
local Mx = require("back.dasm.model")

local function sorted_keys(map)
    local ks = {}
    for k in pairs(map) do ks[#ks + 1] = k end
    table.sort(ks)
    return ks
end

local function build_data(program)
    local ds = {}
    for _, cmd in ipairs(program.cmds) do
        local k = cmd.kind
        if k == "CmdDeclareData" then
            local key = Mx.idkey(cmd.data)
            local size = tonumber(cmd.size) or 0
            local align = tonumber(cmd.align) or 1
            local buf = ffi.new("uint8_t[?]", size)
            ffi.fill(buf, size, 0)
            ds[key] = { buf = buf, size = size, align = align }
        elseif k == "CmdDataInitZero" then
            local d = ds[Mx.idkey(cmd.data)]
            if d then ffi.fill(d.buf + cmd.offset, cmd.size, 0) end
        elseif k == "CmdDataInit" then
            local d = ds[Mx.idkey(cmd.data)]
            if d and cmd.value then
                local v = cmd.value
                if v.kind == "BackLitInt" then
                    ffi.copy(d.buf + cmd.offset, ffi.new("int64_t[1]", math.floor(tonumber(v.raw) or 0)), 8)
                elseif v.kind == "BackLitFloat" then
                    local sk = cmd.ty and cmd.ty.kind
                    if sk == "BackF32" then
                        local bits = string.unpack("I4", string.pack("f", tonumber(v.raw) or 0))
                        ffi.copy(d.buf + cmd.offset, ffi.new("uint32_t[1]", bits), 4)
                    else
                        ffi.copy(d.buf + cmd.offset, ffi.new("double[1]", tonumber(v.raw) or 0), 8)
                    end
                elseif v.kind == "BackLitBool" then
                    d.buf[cmd.offset] = v.value and 1 or 0
                end
            end
        end
    end
    return ds
end

local PHASE = nil
local function phase()
    if PHASE then return PHASE end
    local B = Mx.back()

    PHASE = pvm.phase("lalin_dasm_collect_module", {
        [B.BackProgram] = function(program)
            local sigs, funcs, externs = {}, {}, {}
            local body = nil

            for _, cmd in ipairs(program.cmds) do
                local k = cmd.kind
                if k == "CmdCreateSig" then
                    sigs[Mx.idkey(cmd.sig)] = { params = cmd.params or {}, results = cmd.results or {} }
                elseif k == "CmdDeclareFunc" then
                    local vis = cmd.visibility and cmd.visibility.kind
                    funcs[Mx.idkey(cmd.func)] = { sig = Mx.idkey(cmd.sig), visibility = vis }
                elseif k == "CmdDeclareExtern" then
                    externs[Mx.idkey(cmd.func)] = { symbol = cmd.symbol, sig = Mx.idkey(cmd.sig) }
                elseif k == "CmdBeginFunc" then
                    body = {}
                elseif k == "CmdFinishFunc" then
                    local fk = Mx.idkey(cmd.func)
                    if funcs[fk] then funcs[fk].body = body end
                    body = nil
                elseif body and k ~= "CmdCreateSig" and k ~= "CmdDeclareData"
                        and k ~= "CmdDataInitZero" and k ~= "CmdDataInit"
                        and k ~= "CmdDeclareFunc" and k ~= "CmdDeclareExtern"
                        and k ~= "CmdFinalizeModule" and k ~= "CmdTargetModel"
                        and k ~= "CmdAliasFact" then
                    body[#body + 1] = cmd
                end
            end

            local datas = build_data(program)
            local fkeys = sorted_keys(funcs)
            local ekeys = sorted_keys(externs)
            local dkeys = sorted_keys(datas)

            return pvm.once(Mx.make_phase_module(sigs, funcs, externs, datas, fkeys, ekeys, dkeys, {
                funcs = {}, externs = {}, datas = {},
            }))
        end,
    })

    return PHASE
end

return {
    phase = function() return phase() end,
    run = function(program)
        return pvm.one(phase()(program))
    end,
}
