-- back_luajit.lua — MoonBack ASDL -> hygienic LuaJIT source compiler.
-- Hard-refactored backend: whole-module quote emission, explicit representations,
-- CFG edge parallel copies, lane-expanded vectors, and runtime helpers.
local ffi = require("ffi")
local bit = require("bit")
local pvm = require("moonlift.pvm")
local quote = require("moonlift.quote")
local rt = require("moonlift.back_luajit_runtime")

local M = {}

local function kind(x) return x and (x.kind or (pvm.classof(x) and pvm.classof(x).kind)) end
local function id_text(id) return type(id) == "string" and id or id.text end
local function scalar_name(s) return (kind(s) or "BackI32"):gsub("^Back", "") end
local function scalar(sn) return { tag="scalar", name=type(sn)=="string" and sn or scalar_name(sn) } end
local function shape_of(node)
    if not node then return nil end
    local k = kind(node)
    if k == "BackShapeScalar" then return { tag="scalar", scalar=scalar_name(node.scalar) } end
    if k == "BackShapeVec" then return { tag="vec", elem=scalar_name(node.vec.elem), lanes=node.vec.lanes } end
    if k and k:match("^Back") then return { tag="scalar", scalar=scalar_name(node) } end
    error("back_luajit: unsupported shape " .. tostring(k))
end
local function scalar_shape(s) return { tag="scalar", scalar=type(s)=="string" and s or scalar_name(s) } end
local function ptr_shape() return scalar_shape("Ptr") end
local function bool_shape() return scalar_shape("Bool") end
local function is64(sn) return sn == "I64" or sn == "U64" end
local function is_signed(sn) return sn == "I8" or sn == "I16" or sn == "I32" or sn == "I64" end
local function is_float(sn) return sn == "F32" or sn == "F64" end
local function is_intlike(sn) return sn == "Bool" or sn == "I8" or sn == "U8" or sn == "I16" or sn == "U16" or sn == "I32" or sn == "U32" or sn == "I64" or sn == "U64" or sn == "Index" end
local function width(sn)
    return ({Bool=8,I8=8,U8=8,I16=16,U16=16,I32=32,U32=32,I64=64,U64=64,Index=64,Ptr=64,F32=32,F64=64})[sn] or 32
end
local function elem_size(sn) return rt.scalar_bytes(sn) end
local function qstr(s) return string.format("%q", tostring(s)) end

local function shape_key(sh)
    if sh.tag == "scalar" then return sh.scalar end
    return sh.elem .. "x" .. tostring(sh.lanes)
end

local function comp_count_shape(sh)
    if sh.tag == "scalar" then return is64(sh.scalar) and 2 or 1 end
    local per = is64(sh.elem) and 2 or 1
    return sh.lanes * per
end

local function comp_names_for_hint(q, hint, sh)
    local out = {}
    if sh.tag == "scalar" then
        if is64(sh.scalar) then
            out[1] = q:sym(hint .. "_lo")
            out[2] = q:sym(hint .. "_hi")
        else
            out[1] = q:sym(hint)
        end
    else
        for lane=0,sh.lanes-1 do
            if is64(sh.elem) then
                out[#out+1] = q:sym(hint .. "_" .. lane .. "_lo")
                out[#out+1] = q:sym(hint .. "_" .. lane .. "_hi")
            else
                out[#out+1] = q:sym(hint .. "_" .. lane)
            end
        end
    end
    return out
end

local function collect(T, program)
    local Back, Core = T.MoonBack, T.MoonCore
    assert(pvm.classof(program) == Back.BackProgram, "back_luajit.compile expects MoonBack.BackProgram")
    local mod = { T=T, Back=Back, Core=Core, sigs={}, datas={}, externs={}, funcs={}, func_order={}, exported={}, finalize_seen=false }
    local current
    for i,cmd in ipairs(program.cmds) do
        local k = kind(cmd)
        if not current then
            if k == "CmdTargetModel" or k == "CmdAliasFact" then
                -- metadata/facts: no executable Lua emitted
            elseif k == "CmdCreateSig" then
                local sid = id_text(cmd.sig)
                if mod.sigs[sid] then error("duplicate signature "..sid) end
                local ps, rs = {}, {}
                for j=1,#cmd.params do ps[j] = scalar_name(cmd.params[j]) end
                for j=1,#cmd.results do rs[j] = scalar_name(cmd.results[j]) end
                mod.sigs[sid] = { id=sid, params=ps, results=rs, src=cmd, index=i }
            elseif k == "CmdDeclareData" then
                local did = id_text(cmd.data)
                if mod.datas[did] then error("duplicate data "..did) end
                mod.datas[did] = { id=did, size=cmd.size, align=cmd.align, inits={}, src=cmd, index=i }
            elseif k == "CmdDataInitZero" then
                local did = id_text(cmd.data); local d = assert(mod.datas[did], "data init for undeclared data "..did)
                d.inits[#d.inits+1] = { kind="zero", offset=cmd.offset, size=cmd.size, src=cmd, index=i }
            elseif k == "CmdDataInit" then
                local did = id_text(cmd.data); local d = assert(mod.datas[did], "data init for undeclared data "..did)
                d.inits[#d.inits+1] = { kind="init", offset=cmd.offset, scalar=scalar_name(cmd.ty), value=cmd.value, src=cmd, index=i }
            elseif k == "CmdDeclareExtern" then
                local eid = id_text(cmd.func)
                if mod.externs[eid] then error("duplicate extern "..eid) end
                mod.externs[eid] = { id=eid, symbol=cmd.symbol, sig=id_text(cmd.sig), src=cmd, index=i }
            elseif k == "CmdDeclareFunc" then
                local fid = id_text(cmd.func)
                if mod.funcs[fid] and mod.funcs[fid].declared then error("duplicate function "..fid) end
                local f = mod.funcs[fid] or { id=fid, body_cmds={}, blocks={}, block_order={}, block_params={}, values={}, stack_slots={} }
                f.sig = id_text(cmd.sig); f.declared = true; f.visibility = (cmd.visibility and kind(cmd.visibility) == "VisibilityExport") and "export" or "local"
                mod.funcs[fid] = f; mod.func_order[#mod.func_order+1] = fid
                if f.visibility == "export" then mod.exported[fid] = true end
            elseif k == "CmdBeginFunc" then
                local fid = id_text(cmd.func); local f = assert(mod.funcs[fid], "body for undeclared function "..fid)
                current = f; f.begin_index = i
            elseif k == "CmdFinalizeModule" then
                mod.finalize_seen = true
            else
                error("command "..tostring(k).." cannot appear at module top level")
            end
        else
            if k == "CmdFinishFunc" then
                if id_text(cmd.func) ~= current.id then error("finish func mismatch: "..id_text(cmd.func).." while in "..current.id) end
                current.finish_index = i; current = nil
            elseif k == "CmdBeginFunc" then
                error("nested function "..id_text(cmd.func))
            else
                current.body_cmds[#current.body_cmds+1] = { cmd=cmd, kind=k, index=i }
            end
        end
    end
    if current then error("unterminated function "..current.id) end
    return mod
end

local function add_value(f, id, sh, def)
    if not id then return end
    local vt = id_text(id)
    local old = f.values[vt]
    if old then
        if sh and shape_key(old.shape) ~= shape_key(sh) then error("value "..vt.." shape mismatch "..shape_key(old.shape).." vs "..shape_key(sh)) end
        return old
    end
    local v = { id=vt, shape=assert(sh, "missing shape for value "..vt), def=def, uses={} }
    f.values[vt] = v
    return v
end
local function use_value(f, id, nc, role)
    if not id then return end
    local vt = id_text(id)
    local v = f.values[vt]
    if v then v.uses[#v.uses+1] = { index=nc.index, role=role } end
end
local function alias_shape(f, dst, src, nc)
    local s = f.values[id_text(src)]
    if not s then error("alias source has no shape: "..id_text(src)) end
    add_value(f, dst, s.shape, { kind="cmd", index=nc.index })
end

local function analyze_function(mod, f)
    local sig = assert(mod.sigs[f.sig], "missing signature "..tostring(f.sig))
    f.params, f.results = sig.params, sig.results
    f.current_block = nil
    f.switch_order = {}
    local switched_seen = {}
    -- First pass: blocks, params, stack slots, entry params, value shapes.
    for _,nc in ipairs(f.body_cmds) do
        local cmd,k = nc.cmd,nc.kind
        if k == "CmdCreateBlock" then
            local bid = id_text(cmd.block)
            if f.blocks[bid] then error("duplicate block "..bid.." in "..f.id) end
            f.blocks[bid] = { id=bid, params={}, cmds={}, term=nil, sealed=false, index=nc.index }
            f.block_order[#f.block_order+1] = bid
        elseif k == "CmdSwitchToBlock" then
            local bid = id_text(cmd.block); assert(f.blocks[bid], "switch to unknown block "..bid)
            f.current_block = bid
            if not switched_seen[bid] then switched_seen[bid]=true; f.switch_order[#f.switch_order+1]=bid end
        elseif k == "CmdSealBlock" then
            local bid=id_text(cmd.block); if f.blocks[bid] then f.blocks[bid].sealed=true end
        elseif k == "CmdBindEntryParams" then
            local bid = id_text(cmd.block); f.entry_block = bid; f.entry_params = {}
            for i,v in ipairs(cmd.values) do
                local vt=id_text(v); f.entry_params[i]=vt
                add_value(f, v, scalar_shape(sig.params[i]), { kind="entry_param", index=nc.index, block=bid })
            end
        elseif k == "CmdAppendBlockParam" then
            local bid = id_text(cmd.block); local b=assert(f.blocks[bid], "param for unknown block "..bid)
            local sh = shape_of(cmd.ty)
            b.params[#b.params+1] = { value=id_text(cmd.value), shape=sh }
            f.block_params[bid] = f.block_params[bid] or {}; f.block_params[bid][#f.block_params[bid]+1] = id_text(cmd.value)
            add_value(f, cmd.value, sh, { kind="block_param", index=nc.index, block=bid })
        elseif k == "CmdCreateStackSlot" then
            f.stack_slots[id_text(cmd.slot)] = { id=id_text(cmd.slot), size=cmd.size, align=cmd.align }
        elseif k == "CmdAlias" then alias_shape(f, cmd.dst, cmd.src, nc); use_value(f, cmd.src, nc, "src")
        elseif k == "CmdStackAddr" then add_value(f, cmd.dst, ptr_shape(), {kind="cmd",index=nc.index})
        elseif k == "CmdDataAddr" or k == "CmdFuncAddr" or k == "CmdExternAddr" then add_value(f, cmd.dst, ptr_shape(), {kind="cmd",index=nc.index})
        elseif k == "CmdConst" then add_value(f, cmd.dst, scalar_shape(cmd.ty), {kind="cmd",index=nc.index})
        elseif k == "CmdUnary" or k == "CmdIntrinsic" then
            add_value(f, cmd.dst, shape_of(cmd.ty), {kind="cmd",index=nc.index}); use_value(f, cmd.value or (cmd.args and cmd.args[1]), nc, "value"); if cmd.args then for _,a in ipairs(cmd.args) do use_value(f,a,nc,"arg") end end
        elseif k == "CmdCompare" then add_value(f, cmd.dst, bool_shape(), {kind="cmd",index=nc.index}); use_value(f,cmd.lhs,nc,"lhs"); use_value(f,cmd.rhs,nc,"rhs")
        elseif k == "CmdCast" then add_value(f, cmd.dst, scalar_shape(cmd.ty), {kind="cmd",index=nc.index}); use_value(f,cmd.value,nc,"value")
        elseif k == "CmdPtrOffset" then add_value(f, cmd.dst, ptr_shape(), {kind="cmd",index=nc.index}); if kind(cmd.base)=="BackAddrValue" then use_value(f,cmd.base.value,nc,"base") end; use_value(f,cmd.index,nc,"index")
        elseif k == "CmdLoadInfo" then add_value(f, cmd.dst, shape_of(cmd.ty), {kind="cmd",index=nc.index}); if cmd.addr then if kind(cmd.addr.base)=="BackAddrValue" then use_value(f,cmd.addr.base.value,nc,"addr.base") end; use_value(f,cmd.addr.byte_offset,nc,"addr.off") end
        elseif k == "CmdStoreInfo" then use_value(f,cmd.value,nc,"value"); if cmd.addr then if kind(cmd.addr.base)=="BackAddrValue" then use_value(f,cmd.addr.base.value,nc,"addr.base") end; use_value(f,cmd.addr.byte_offset,nc,"addr.off") end
        elseif k == "CmdIntBinary" or k == "CmdBitBinary" or k == "CmdShift" or k == "CmdRotate" or k == "CmdFloatBinary" then
            add_value(f, cmd.dst, scalar_shape(cmd.scalar), {kind="cmd",index=nc.index}); use_value(f,cmd.lhs,nc,"lhs"); use_value(f,cmd.rhs,nc,"rhs")
        elseif k == "CmdBitNot" then add_value(f,cmd.dst,scalar_shape(cmd.scalar),{kind="cmd",index=nc.index}); use_value(f,cmd.value,nc,"value")
        elseif k == "CmdMemcpy" then use_value(f,cmd.dst,nc,"dst"); use_value(f,cmd.src,nc,"src"); use_value(f,cmd.len,nc,"len")
        elseif k == "CmdMemset" then use_value(f,cmd.dst,nc,"dst"); use_value(f,cmd.byte,nc,"byte"); use_value(f,cmd.len,nc,"len")
        elseif k == "CmdSelect" then add_value(f,cmd.dst,shape_of(cmd.ty),{kind="cmd",index=nc.index}); use_value(f,cmd.cond,nc,"cond"); use_value(f,cmd.then_value,nc,"then"); use_value(f,cmd.else_value,nc,"else")
        elseif k == "CmdFma" then add_value(f,cmd.dst,scalar_shape(cmd.ty),{kind="cmd",index=nc.index}); use_value(f,cmd.a,nc,"a"); use_value(f,cmd.b,nc,"b"); use_value(f,cmd.c,nc,"c")
        elseif k == "CmdVecSplat" then add_value(f,cmd.dst,{tag="vec",elem=scalar_name(cmd.ty.elem),lanes=cmd.ty.lanes},{kind="cmd",index=nc.index}); use_value(f,cmd.value,nc,"value")
        elseif k == "CmdVecBinary" or k == "CmdVecCompare" then add_value(f,cmd.dst,{tag="vec",elem=scalar_name(cmd.ty.elem),lanes=cmd.ty.lanes},{kind="cmd",index=nc.index}); use_value(f,cmd.lhs,nc,"lhs"); use_value(f,cmd.rhs,nc,"rhs")
        elseif k == "CmdVecSelect" then add_value(f,cmd.dst,{tag="vec",elem=scalar_name(cmd.ty.elem),lanes=cmd.ty.lanes},{kind="cmd",index=nc.index}); use_value(f,cmd.mask,nc,"mask"); use_value(f,cmd.then_value,nc,"then"); use_value(f,cmd.else_value,nc,"else")
        elseif k == "CmdVecMask" then add_value(f,cmd.dst,{tag="vec",elem=scalar_name(cmd.ty.elem),lanes=cmd.ty.lanes},{kind="cmd",index=nc.index}); for _,a in ipairs(cmd.args) do use_value(f,a,nc,"arg") end
        elseif k == "CmdVecInsertLane" then add_value(f,cmd.dst,{tag="vec",elem=scalar_name(cmd.ty.elem),lanes=cmd.ty.lanes},{kind="cmd",index=nc.index}); use_value(f,cmd.value,nc,"value"); use_value(f,cmd.lane_value,nc,"lane")
        elseif k == "CmdVecExtractLane" then add_value(f,cmd.dst,scalar_shape(cmd.ty),{kind="cmd",index=nc.index}); use_value(f,cmd.value,nc,"value")
        elseif k == "CmdCall" then
            if kind(cmd.result) == "BackCallValue" then add_value(f,cmd.result.dst,scalar_shape(cmd.result.ty),{kind="cmd",index=nc.index}) end
            if kind(cmd.target)=="BackCallIndirect" then use_value(f,cmd.target.callee,nc,"callee") end
            for _,a in ipairs(cmd.args) do use_value(f,a,nc,"arg") end
        elseif k == "CmdJump" then for _,a in ipairs(cmd.args) do use_value(f,a,nc,"arg") end
        elseif k == "CmdBrIf" then use_value(f,cmd.cond,nc,"cond"); for _,a in ipairs(cmd.then_args) do use_value(f,a,nc,"then_arg") end; for _,a in ipairs(cmd.else_args) do use_value(f,a,nc,"else_arg") end
        elseif k == "CmdSwitchInt" then use_value(f,cmd.value,nc,"value")
        elseif k == "CmdReturnValue" then use_value(f,cmd.value,nc,"return")
        end
    end
    -- Assign commands to blocks and CFG.
    f.cfg = { preds={}, succs={} }
    local cb
    for _,bid in ipairs(f.block_order) do f.cfg.preds[bid]={}; f.cfg.succs[bid]={} end
    local function succ(a,b) if a and b then table.insert(f.cfg.succs[a], b); table.insert(f.cfg.preds[b], a) end end
    for _,nc in ipairs(f.body_cmds) do
        local cmd,k = nc.cmd,nc.kind
        if k == "CmdSwitchToBlock" then cb = id_text(cmd.block)
        elseif f.blocks[cb] and not (k=="CmdCreateBlock" or k=="CmdSealBlock" or k=="CmdAppendBlockParam" or k=="CmdBindEntryParams" or k=="CmdCreateStackSlot") then
            local b=f.blocks[cb]
            if k=="CmdJump" or k=="CmdBrIf" or k=="CmdSwitchInt" or k=="CmdReturnVoid" or k=="CmdReturnValue" or k=="CmdTrap" then b.term=nc else b.cmds[#b.cmds+1]=nc end
            if k=="CmdJump" then succ(cb,id_text(cmd.dest))
            elseif k=="CmdBrIf" then succ(cb,id_text(cmd.then_block)); succ(cb,id_text(cmd.else_block))
            elseif k=="CmdSwitchInt" then for _,cs in ipairs(cmd.cases) do succ(cb,id_text(cs.dest)) end; succ(cb,id_text(cmd.default_dest)) end
        end
    end
end

local function prepare_emit(q, mod)
    mod.emit = { fn={}, export={}, data={}, extern={}, ctype={} }
    for _,fid in ipairs(mod.func_order) do mod.emit.fn[fid] = q:sym("fn_"..fid:gsub("[^%w_]","_")) end
    for _,fid in ipairs(mod.func_order) do if mod.exported[fid] then mod.emit.export[fid] = q:sym("export_"..fid:gsub("[^%w_]","_")) end end
    for did in pairs(mod.datas) do mod.emit.data[did] = { owner=q:sym("data_owner"), ptr=q:sym("data_ptr") } end
    for eid,ex in pairs(mod.externs) do mod.emit.extern[eid] = q:val(ffi.C[ex.symbol], "extern_"..ex.symbol) end
    local ctypes = {
        u8p="uint8_t*", i8p="int8_t*", u16p="uint16_t*", i16p="int16_t*", u32p="uint32_t*", i32p="int32_t*",
        u64p="uint64_t*", i64p="int64_t*", f32p="float*", f64p="double*", voidp="void*",
    }
    for k,s in pairs(ctypes) do mod.emit.ctype[k] = q:val(ffi.typeof(s), k.."_t") end
    mod.emit.rt = q:val(rt, "rt")
    mod.emit.cast = q:val(ffi.cast, "cast")
    mod.emit.copy = q:val(ffi.copy, "copy")
    mod.emit.fill = q:val(ffi.fill, "fill")
    mod.emit.band = q:val(bit.band, "band")
    mod.emit.bor = q:val(bit.bor, "bor")
    mod.emit.bxor = q:val(bit.bxor, "bxor")
    mod.emit.bnot = q:val(bit.bnot, "bnot")
    mod.emit.lshift = q:val(bit.lshift, "lshift")
    mod.emit.rshift = q:val(bit.rshift, "rshift")
    mod.emit.arshift = q:val(bit.arshift, "arshift")
    mod.emit.tobit = q:val(bit.tobit, "tobit")
    mod.emit.sqrt = q:val(math.sqrt, "sqrt")
    mod.emit.abs = q:val(math.abs, "abs")
    mod.emit.floor = q:val(math.floor, "floor")
    mod.emit.ceil = q:val(math.ceil, "ceil")
end

local function assign_value_symbols(q, f)
    f.emit = { val={}, labels={}, stack={}, scratch=q:sym("scratch") }
    for _,bid in ipairs(f.block_order) do f.emit.labels[bid] = q:sym("block_"..bid:gsub("[^%w_]","_")) end
    local order, seen = {}, {}
    if f.entry_block then order[#order+1]=f.entry_block; seen[f.entry_block]=true end
    for _,bid in ipairs(f.switch_order or {}) do if not seen[bid] then order[#order+1]=bid; seen[bid]=true end end
    for _,bid in ipairs(f.block_order) do if not seen[bid] then order[#order+1]=bid; seen[bid]=true end end
    f.emit.order = order
    for vid,v in pairs(f.values) do f.emit.val[vid] = comp_names_for_hint(q, vid:gsub("[^%w_]","_"), v.shape) end
    for sid in pairs(f.stack_slots) do f.emit.stack[sid] = { owner=q:sym("slot_owner"), ptr=q:sym("slot_ptr") } end
end

local function comps(f, id) return assert(f.emit.val[id_text(id)], "no components for value "..id_text(id)) end
local function shape(f, id) return assert(f.values[id_text(id)], "unknown value "..id_text(id)).shape end
local function first(f,id) return comps(f,id)[1] end

local function comp_slice_for_lane(f, id, lane)
    local sh = shape(f,id); assert(sh.tag=="vec")
    local per = is64(sh.elem) and 2 or 1
    local c = comps(f,id); local out={}
    for i=1,per do out[i]=c[lane*per+i] end
    return out
end

local function normalize_expr(E, sn, expr)
    if sn == "Bool" then return string.format("(%s ~= 0 and 1 or 0)", expr) end
    if sn == "I8" or sn == "U8" then return string.format("%s.u8(%s)", E.rt, expr) end
    if sn == "I16" or sn == "U16" then return string.format("%s.u16(%s)", E.rt, expr) end
    if sn == "I32" then return string.format("%s(%s)", E.tobit, expr) end
    if sn == "U32" then return string.format("%s.u32(%s)", E.rt, expr) end
    if sn == "F32" then return string.format("%s.f32(%s)", E.rt, expr) end
    return expr
end
local function signed_expr(E, sn, expr)
    if sn == "I8" then return string.format("%s.s8(%s)", E.rt, expr) end
    if sn == "I16" then return string.format("%s.s16(%s)", E.rt, expr) end
    if sn == "I32" then return expr end
    return expr
end
local function assign_scalar(q, E, dst, sn, expr)
    if is64(sn) then error("assign_scalar called for 64-bit "..sn) end
    q("%s=%s", dst, normalize_expr(E, sn, expr))
end
local function assign_comps(q, dst, src)
    for i=1,#dst do q("%s=%s", dst[i], src[i]) end
end

local function emit_parallel_copy(q, f, dsts, srcs)
    local copies = {}
    for i=1,#dsts do if dsts[i] ~= srcs[i] then copies[#copies+1] = { d=dsts[i], s=srcs[i] } end end
    while #copies > 0 do
        local srcset = {}; for _,c in ipairs(copies) do srcset[c.s]=true end
        local progress=false
        for i=#copies,1,-1 do
            local c=copies[i]
            if not srcset[c.d] then q("%s=%s", c.d, c.s); table.remove(copies,i); progress=true end
        end
        if not progress then
            local d = copies[1].d
            q("%s=%s", f.emit.scratch, d)
            for _,c in ipairs(copies) do if c.s == d then c.s = f.emit.scratch end end
        end
    end
end

local function edge_copy(q, f, dest_block, args)
    local params = f.block_params[id_text(dest_block)] or {}
    if #params ~= #args then if #params == 0 and #args == 0 then return else error("block arg count mismatch for "..id_text(dest_block)) end end
    local dsts, srcs = {}, {}
    for i=1,#params do
        local dc, sc = comps(f, params[i]), comps(f, args[i])
        for j=1,#dc do dsts[#dsts+1]=dc[j]; srcs[#srcs+1]=sc[j] end
    end
    emit_parallel_copy(q, f, dsts, srcs)
end

local function scalar_load_expr(E, sn, addr)
    local c=E.ctype
    if sn=="Bool" or sn=="U8" then return string.format("tonumber(%s(%s,%s)[0])", E.cast,c.u8p,addr) end
    if sn=="I8" then return string.format("%s.u8(tonumber(%s(%s,%s)[0]))", E.rt,E.cast,c.i8p,addr) end
    if sn=="U16" then return string.format("tonumber(%s(%s,%s)[0])",E.cast,c.u16p,addr) end
    if sn=="I16" then return string.format("%s.u16(tonumber(%s(%s,%s)[0]))",E.rt,E.cast,c.i16p,addr) end
    if sn=="U32" then return string.format("%s.u32(tonumber(%s(%s,%s)[0]))",E.rt,E.cast,c.u32p,addr) end
    if sn=="I32" then return string.format("tonumber(%s(%s,%s)[0])",E.cast,c.i32p,addr) end
    if sn=="F32" then return string.format("%s.f32(tonumber(%s(%s,%s)[0]))",E.rt,E.cast,c.f32p,addr) end
    if sn=="F64" then return string.format("tonumber(%s(%s,%s)[0])",E.cast,c.f64p,addr) end
    if sn=="Ptr" then return string.format("%s(%s,%s)[0]",E.cast,c.u8p,addr) end
    error("scalar_load_expr unsupported "..sn)
end
local function scalar_store_stmt(q,E,sn,addr,src)
    local c=E.ctype
    if sn=="Bool" or sn=="U8" then q("%s(%s,%s)[0]=%s",E.cast,c.u8p,addr,src[1])
    elseif sn=="I8" then q("%s(%s,%s)[0]=%s.s8(%s)",E.cast,c.i8p,addr,E.rt,src[1])
    elseif sn=="U16" then q("%s(%s,%s)[0]=%s",E.cast,c.u16p,addr,src[1])
    elseif sn=="I16" then q("%s(%s,%s)[0]=%s.s16(%s)",E.cast,c.i16p,addr,E.rt,src[1])
    elseif sn=="U32" then q("%s(%s,%s)[0]=%s",E.cast,c.u32p,addr,src[1])
    elseif sn=="I32" then q("%s(%s,%s)[0]=%s",E.cast,c.i32p,addr,src[1])
    elseif sn=="F32" then q("%s(%s,%s)[0]=%s",E.cast,c.f32p,addr,src[1])
    elseif sn=="F64" then q("%s(%s,%s)[0]=%s",E.cast,c.f64p,addr,src[1])
    elseif sn=="I64" then q("%s.store_i64(%s,%s,%s)",E.rt,addr,src[1],src[2])
    elseif sn=="U64" or sn=="Index" then q("%s.store_u64(%s,%s,%s)",E.rt,addr,src[1],src[2])
    elseif sn=="Ptr" then q("%s(%s,%s)[0]=%s(%s,%s)",E.cast,c.u8p,addr,E.cast,c.u8p,src[1])
    else error("store unsupported "..sn) end
end

local function addr_expr(mod, f, E, addr)
    local bk = kind(addr.base); local base
    if bk == "BackAddrValue" then base = first(f, addr.base.value)
    elseif bk == "BackAddrStack" then base = f.emit.stack[id_text(addr.base.slot)].ptr
    elseif bk == "BackAddrData" then base = mod.emit.data[id_text(addr.base.data)].ptr
    else error("unsupported address base "..tostring(bk)) end
    local offid = addr.byte_offset
    local sh = shape(f, offid)
    local oc = comps(f, offid)
    if is64(sh.scalar) then return string.format("%s.ptr_add_bytes(%s,%s,%s)", E.rt, base, oc[1], oc[2]) end
    return string.format("%s(%s,%s)+(%s)", E.cast, E.ctype.u8p, base, oc[1])
end

local function emit_const(q,E,f,cmd)
    local dst = comps(f,cmd.dst); local sn=scalar_name(cmd.ty); local lit=cmd.value; local lk=kind(lit)
    if is64(sn) then
        if lk=="BackLitInt" then q("%s,%s=%s.%s(%q)",dst[1],dst[2],E.rt,(sn=="I64" and "const_i64" or "const_u64"),lit.raw)
        elseif lk=="BackLitNull" then q("%s,%s=0,0",dst[1],dst[2])
        else error("unsupported 64-bit const literal "..tostring(lk)) end
        return
    end
    local expr
    if lk=="BackLitInt" or lk=="BackLitFloat" then expr=lit.raw
    elseif lk=="BackLitBool" then expr=lit.value and "1" or "0"
    elseif lk=="BackLitNull" then expr=string.format("%s.null_ptr()",E.rt)
    else error("unknown literal "..tostring(lk)) end
    assign_scalar(q,E,dst[1],sn,expr)
end

local function emit_cmd(q, mod, f, nc)
    local E=mod.emit; local cmd,k=nc.cmd,nc.kind
    if k=="CmdAlias" then assign_comps(q, comps(f,cmd.dst), comps(f,cmd.src))
    elseif k=="CmdDataAddr" then q("%s=%s", first(f,cmd.dst), mod.emit.data[id_text(cmd.data)].ptr)
    elseif k=="CmdFuncAddr" then q("%s=%s", first(f,cmd.dst), mod.emit.fn[id_text(cmd.func)])
    elseif k=="CmdExternAddr" then q("%s=%s", first(f,cmd.dst), mod.emit.extern[id_text(cmd.func)])
    elseif k=="CmdStackAddr" then q("%s=%s", first(f,cmd.dst), f.emit.stack[id_text(cmd.slot)].ptr)
    elseif k=="CmdConst" then emit_const(q,E,f,cmd)
    elseif k=="CmdUnary" then
        local dst, v = comps(f,cmd.dst), comps(f,cmd.value); local sh=shape_of(cmd.ty); local sn=sh.scalar; local op=kind(cmd.op)
        if is64(sn) then
            if op=="BackUnaryIneg" then q("%s,%s=%s.u64_sub(0,0,%s,%s)",dst[1],dst[2],E.rt,v[1],v[2])
            elseif op=="BackUnaryBnot" then q("%s,%s=%s.u64_bnot(%s,%s)",dst[1],dst[2],E.rt,v[1],v[2])
            else error("unsupported 64 unary "..op) end
        else
            local expr = v[1]
            if op=="BackUnaryIneg" or op=="BackUnaryFneg" then expr="-("..expr..")"
            elseif op=="BackUnaryBnot" then expr=string.format("%s(%s)",E.bnot,expr)
            elseif op=="BackUnaryBoolNot" then expr=string.format("(%s==0 and 1 or 0)",expr) end
            assign_scalar(q,E,dst[1],sn,expr)
        end
    elseif k=="CmdIntrinsic" then
        local dst= comps(f,cmd.dst); local a=comps(f,cmd.args[1]); local sh=shape_of(cmd.ty); local sn=sh.scalar; local op=kind(cmd.op)
        if is64(sn) then
            local fn=({BackIntrinsicPopcount="u64_popcnt",BackIntrinsicClz="u64_clz",BackIntrinsicCtz="u64_ctz",BackIntrinsicBswap="u64_bswap"})[op]
            if not fn then error("unsupported 64 intrinsic "..op) end
            q("%s,%s=%s.%s(%s,%s)",dst[1],dst[2],E.rt,fn,a[1],a[2])
        else
            local expr
            if op=="BackIntrinsicSqrt" then expr=string.format("%s(%s)",E.sqrt,a[1])
            elseif op=="BackIntrinsicAbs" then expr=string.format("%s(%s)",E.abs,(is_signed(sn) and signed_expr(E,sn,a[1]) or a[1]))
            elseif op=="BackIntrinsicFloor" then expr=string.format("%s(%s)",E.floor,a[1])
            elseif op=="BackIntrinsicCeil" then expr=string.format("%s(%s)",E.ceil,a[1])
            elseif op=="BackIntrinsicTruncFloat" then expr=string.format("%s.trunc(%s)",E.rt,a[1])
            elseif op=="BackIntrinsicRound" then expr=string.format("%s.round(%s)",E.rt,a[1])
            elseif op=="BackIntrinsicPopcount" then expr=string.format("%s.popc32(%s)",E.rt,a[1])
            elseif op=="BackIntrinsicClz" then expr=string.format("%s.clz32(%s)",E.rt,a[1])
            elseif op=="BackIntrinsicCtz" then expr=string.format("%s.ctz32(%s)",E.rt,a[1])
            elseif op=="BackIntrinsicBswap" then expr=string.format("%s.bswap32(%s)",E.rt,a[1])
            else error("unsupported intrinsic "..op) end
            assign_scalar(q,E,dst[1],sn,expr)
        end
    elseif k=="CmdCompare" then
        local dst=comps(f,cmd.dst); local l=comps(f,cmd.lhs); local r=comps(f,cmd.rhs); local op=kind(cmd.op); local osh=shape(f,cmd.lhs); local sn=osh.scalar
        local expr
        if is64(sn) then
            if op=="BackIcmpEq" then expr=string.format("%s.u64_eq(%s,%s,%s,%s)",E.rt,l[1],l[2],r[1],r[2])
            elseif op=="BackIcmpNe" then expr=string.format("not %s.u64_eq(%s,%s,%s,%s)",E.rt,l[1],l[2],r[1],r[2])
            elseif op:match("^BackSIcmp") then
                local fn=(op:match("Lt") and "i64_lt") or (op:match("Le") and "i64_le")
                if op:match("Gt") then expr=string.format("%s.i64_lt(%s,%s,%s,%s)",E.rt,r[1],r[2],l[1],l[2]) elseif op:match("Ge") then expr=string.format("%s.i64_le(%s,%s,%s,%s)",E.rt,r[1],r[2],l[1],l[2]) else expr=string.format("%s.%s(%s,%s,%s,%s)",E.rt,fn,l[1],l[2],r[1],r[2]) end
            elseif op:match("^BackUIcmp") then
                local fn=(op:match("Lt") and "u64_lt") or (op:match("Le") and "u64_le")
                if op:match("Gt") then expr=string.format("%s.u64_lt(%s,%s,%s,%s)",E.rt,r[1],r[2],l[1],l[2]) elseif op:match("Ge") then expr=string.format("%s.u64_le(%s,%s,%s,%s)",E.rt,r[1],r[2],l[1],l[2]) else expr=string.format("%s.%s(%s,%s,%s,%s)",E.rt,fn,l[1],l[2],r[1],r[2]) end
            else error("unsupported compare "..op) end
            q("%s=(%s) and 1 or 0",dst[1],expr)
        else
            local ll, rr = l[1], r[1]
            if op:match("^BackSIcmp") then ll=signed_expr(E,sn,ll); rr=signed_expr(E,sn,rr) end
            local cmp=({BackIcmpEq="==",BackFCmpEq="==",BackIcmpNe="~=",BackFCmpNe="~=",BackSIcmpLt="<",BackUIcmpLt="<",BackFCmpLt="<",BackSIcmpLe="<=",BackUIcmpLe="<=",BackFCmpLe="<=",BackSIcmpGt=">",BackUIcmpGt=">",BackFCmpGt=">",BackSIcmpGe=">=",BackUIcmpGe=">=",BackFCmpGe=">="})[op]
            q("%s=(%s %s %s) and 1 or 0",dst[1],ll,cmp,rr)
        end
    elseif k=="CmdCast" then
        local dst=comps(f,cmd.dst); local src=comps(f,cmd.value); local dsn=scalar_name(cmd.ty); local op=kind(cmd.op); local ssh=shape(f,cmd.value); local ssn=ssh.scalar
        if is64(dsn) then
            if is64(ssn) then assign_comps(q,dst,src)
            elseif op=="BackSextend" then q("%s,%s=%s.sext64(%d,%s)",dst[1],dst[2],E.rt,width(ssn),src[1])
            else q("%s,%s=%s.uext64(%d,%s)",dst[1],dst[2],E.rt,width(ssn),src[1]) end
        elseif is64(ssn) then
            if dsn=="I32" or dsn=="U32" then q("%s=%s.u32(%s)",dst[1],E.rt,src[1])
            elseif dsn=="I16" or dsn=="U16" then q("%s=%s.u16(%s)",dst[1],E.rt,src[1])
            elseif dsn=="I8" or dsn=="U8" or dsn=="Bool" then q("%s=%s.u8(%s)",dst[1],E.rt,src[1])
            elseif is_float(dsn) then q("%s=%s",dst[1], normalize_expr(E,dsn,string.format("%s.%s64_to_number(%s,%s)",E.rt,is_signed(ssn) and "i" or "u",src[1],src[2])))
            else q("%s=%s",dst[1],src[1]) end
        else
            local expr=src[1]
            if op=="BackSToF" then expr=signed_expr(E,ssn,expr)
            elseif op=="BackFToS" or op=="BackFToU" then expr=string.format("%s.trunc(%s)",E.rt,expr) end
            assign_scalar(q,E,dst[1],dsn,expr)
        end
    elseif k=="CmdIntBinary" or k=="CmdBitBinary" or k=="CmdShift" or k=="CmdRotate" or k=="CmdFloatBinary" then
        local dst,l,r=comps(f,cmd.dst),comps(f,cmd.lhs),comps(f,cmd.rhs); local sn=scalar_name(cmd.scalar); local op=kind(cmd.op)
        if is64(sn) then
            local fn=({BackIntAdd="u64_add",BackIntSub="u64_sub",BackIntMul="u64_mul",BackIntSDiv="i64_sdiv",BackIntUDiv="u64_udiv",BackIntSRem="i64_srem",BackIntURem="u64_urem",BackBitAnd="u64_band",BackBitOr="u64_bor",BackBitXor="u64_bxor",BackShiftLeft="u64_shl",BackShiftLogicalRight="u64_shr",BackShiftArithmeticRight="i64_shr",BackRotateLeft="u64_rotl",BackRotateRight="u64_rotr"})[op]
            if k=="CmdShift" or k=="CmdRotate" then q("%s,%s=%s.%s(%s,%s,%s)",dst[1],dst[2],E.rt,fn,l[1],l[2],r[1]) else q("%s,%s=%s.%s(%s,%s,%s,%s)",dst[1],dst[2],E.rt,fn,l[1],l[2],r[1],r[2]) end
        else
            local expr
            if op=="BackIntAdd" then expr=string.format("(%s+%s)",l[1],r[1])
            elseif op=="BackIntSub" then expr=string.format("(%s-%s)",l[1],r[1])
            elseif op=="BackIntMul" then expr=string.format("(%s*%s)",l[1],r[1])
            elseif op=="BackIntSDiv" then expr=string.format("%s.sdiv32(%s,%s)",E.rt,l[1],r[1])
            elseif op=="BackIntUDiv" then expr=string.format("%s.udiv32(%s,%s)",E.rt,l[1],r[1])
            elseif op=="BackIntSRem" then expr=string.format("%s.srem32(%s,%s)",E.rt,l[1],r[1])
            elseif op=="BackIntURem" then expr=string.format("%s.urem32(%s,%s)",E.rt,l[1],r[1])
            elseif op=="BackBitAnd" then expr=string.format("%s(%s,%s)",E.band,l[1],r[1])
            elseif op=="BackBitOr" then expr=string.format("%s(%s,%s)",E.bor,l[1],r[1])
            elseif op=="BackBitXor" then expr=string.format("%s(%s,%s)",E.bxor,l[1],r[1])
            elseif op=="BackShiftLeft" then expr=string.format("%s(%s,%s)",E.lshift,l[1],r[1])
            elseif op=="BackShiftLogicalRight" then expr=string.format("%s(%s,%s)",E.rshift,l[1],r[1])
            elseif op=="BackShiftArithmeticRight" then expr=string.format("%s(%s,%s)",E.arshift,l[1],r[1])
            elseif op=="BackRotateLeft" then expr=string.format("%s(%s(%s,%s),%s(%s,32-%s))",E.bor,E.lshift,l[1],r[1],E.rshift,l[1],r[1])
            elseif op=="BackRotateRight" then expr=string.format("%s(%s(%s,%s),%s(%s,32-%s))",E.bor,E.rshift,l[1],r[1],E.lshift,l[1],r[1])
            elseif op=="BackFloatAdd" then expr=string.format("(%s+%s)",l[1],r[1])
            elseif op=="BackFloatSub" then expr=string.format("(%s-%s)",l[1],r[1])
            elseif op=="BackFloatMul" then expr=string.format("(%s*%s)",l[1],r[1])
            elseif op=="BackFloatDiv" then expr=string.format("(%s/%s)",l[1],r[1])
            else error("unsupported binary op "..op) end
            assign_scalar(q,E,dst[1],sn,expr)
        end
    elseif k=="CmdBitNot" then
        local dst,v=comps(f,cmd.dst),comps(f,cmd.value); local sn=scalar_name(cmd.scalar)
        if is64(sn) then q("%s,%s=%s.u64_bnot(%s,%s)",dst[1],dst[2],E.rt,v[1],v[2]) else assign_scalar(q,E,dst[1],sn,string.format("%s(%s)",E.bnot,v[1])) end
    elseif k=="CmdPtrOffset" then
        local dst=first(f,cmd.dst); local base
        if kind(cmd.base)=="BackAddrValue" then base=first(f,cmd.base.value) elseif kind(cmd.base)=="BackAddrStack" then base=f.emit.stack[id_text(cmd.base.slot)].ptr elseif kind(cmd.base)=="BackAddrData" then base=mod.emit.data[id_text(cmd.base.data)].ptr else error("bad ptr base") end
        local ix=comps(f,cmd.index); local ish=shape(f,cmd.index)
        if is64(ish.scalar) then q("%s=%s.ptr_offset(%s,%s,%s,%d,%d)",dst,E.rt,base,ix[1],ix[2],cmd.elem_size or 1,cmd.const_offset or 0)
        else q("%s=%s(%s,%s)+((%s*%d)+%d)",dst,E.cast,E.ctype.u8p,base,ix[1],cmd.elem_size or 1,cmd.const_offset or 0) end
    elseif k=="CmdLoadInfo" then
        local sh=shape_of(cmd.ty); local addr=addr_expr(mod,f,E,cmd.addr); local dst=comps(f,cmd.dst)
        if sh.tag=="scalar" then
            if sh.scalar=="I64" then q("%s,%s=%s.load_i64(%s)",dst[1],dst[2],E.rt,addr)
            elseif sh.scalar=="U64" or sh.scalar=="Index" then q("%s,%s=%s.load_u64(%s)",dst[1],dst[2],E.rt,addr)
            else q("%s=%s",dst[1],scalar_load_expr(E,sh.scalar,addr)) end
        else
            local per=is64(sh.elem) and 2 or 1; local es=elem_size(sh.elem)
            for lane=0,sh.lanes-1 do
                local a=string.format("%s(%s,%s)+%d",E.cast,E.ctype.u8p,addr,lane*es)
                if is64(sh.elem) then local i=lane*per+1; q("%s,%s=%s.%s(%s)",dst[i],dst[i+1],E.rt,sh.elem=="I64" and "load_i64" or "load_u64",a)
                else q("%s=%s",dst[lane+1],scalar_load_expr(E,sh.elem,a)) end
            end
        end
    elseif k=="CmdStoreInfo" then
        local sh=shape_of(cmd.ty); local addr=addr_expr(mod,f,E,cmd.addr); local src=comps(f,cmd.value)
        if sh.tag=="scalar" then scalar_store_stmt(q,E,sh.scalar,addr,src)
        else local per=is64(sh.elem) and 2 or 1; local es=elem_size(sh.elem); for lane=0,sh.lanes-1 do local a=string.format("%s(%s,%s)+%d",E.cast,E.ctype.u8p,addr,lane*es); local ss={}; for j=1,per do ss[j]=src[lane*per+j] end; scalar_store_stmt(q,E,sh.elem,a,ss) end end
    elseif k=="CmdMemcpy" then q("%s(%s,%s,%s)",E.copy,first(f,cmd.dst),first(f,cmd.src),first(f,cmd.len))
    elseif k=="CmdMemset" then q("%s(%s,%s,%s.u8(%s))",E.fill,first(f,cmd.dst),first(f,cmd.len),E.rt,first(f,cmd.byte))
    elseif k=="CmdSelect" then
        local dst,tc,ec=comps(f,cmd.dst),comps(f,cmd.then_value),comps(f,cmd.else_value)
        q("if %s~=0 then",first(f,cmd.cond)); assign_comps(q,dst,tc); q("else"); assign_comps(q,dst,ec); q("end")
    elseif k=="CmdFma" then local dst,a,b,c=comps(f,cmd.dst),first(f,cmd.a),first(f,cmd.b),first(f,cmd.c); assign_scalar(q,E,dst[1],scalar_name(cmd.ty),string.format("(%s*%s+%s)",a,b,c))
    elseif k:match("^CmdVec") then
        local sh = shape(f,cmd.dst); local elem=sh.elem; local per=is64(elem) and 2 or 1; local dst=comps(f,cmd.dst)
        if k=="CmdVecSplat" then local s=comps(f,cmd.value); for lane=0,sh.lanes-1 do for j=1,per do q("%s=%s",dst[lane*per+j],s[j]) end end
        elseif k=="CmdVecBinary" then local l=comps(f,cmd.lhs); local r=comps(f,cmd.rhs); local fake={scalar=elem}; for lane=0,sh.lanes-1 do local subcmd={dst={text=""},lhs={text=""},rhs={text=""},scalar=cmd.ty.elem,op=cmd.op}; local dl={}; for j=1,per do dl[j]=dst[lane*per+j] end; if is64(elem) then local fn=({BackVecIntAdd="u64_add",BackVecIntSub="u64_sub",BackVecIntMul="u64_mul",BackVecBitAnd="u64_band",BackVecBitOr="u64_bor",BackVecBitXor="u64_bxor"})[kind(cmd.op)]; q("%s,%s=%s.%s(%s,%s,%s,%s)",dl[1],dl[2],E.rt,fn,l[lane*per+1],l[lane*per+2],r[lane*per+1],r[lane*per+2]) else local op=kind(cmd.op); local expr=({BackVecIntAdd=string.format("(%s+%s)",l[lane+1],r[lane+1]),BackVecIntSub=string.format("(%s-%s)",l[lane+1],r[lane+1]),BackVecIntMul=string.format("(%s*%s)",l[lane+1],r[lane+1]),BackVecBitAnd=string.format("%s(%s,%s)",E.band,l[lane+1],r[lane+1]),BackVecBitOr=string.format("%s(%s,%s)",E.bor,l[lane+1],r[lane+1]),BackVecBitXor=string.format("%s(%s,%s)",E.bxor,l[lane+1],r[lane+1])})[op]; assign_scalar(q,E,dst[lane+1],elem,expr) end end
        elseif k=="CmdVecCompare" then local l=comps(f,cmd.lhs); local r=comps(f,cmd.rhs); local op=kind(cmd.op); for lane=0,sh.lanes-1 do local expr; if is64(elem) then local li=lane*per+1; if op:match("Eq") then expr=string.format("%s.u64_eq(%s,%s,%s,%s)",E.rt,l[li],l[li+1],r[li],r[li+1]) elseif op:match("Ne") then expr=string.format("not %s.u64_eq(%s,%s,%s,%s)",E.rt,l[li],l[li+1],r[li],r[li+1]) elseif op:match("^BackVecS") then if op:match("Lt") then expr=string.format("%s.i64_lt(%s,%s,%s,%s)",E.rt,l[li],l[li+1],r[li],r[li+1]) elseif op:match("Le") then expr=string.format("%s.i64_le(%s,%s,%s,%s)",E.rt,l[li],l[li+1],r[li],r[li+1]) elseif op:match("Gt") then expr=string.format("%s.i64_lt(%s,%s,%s,%s)",E.rt,r[li],r[li+1],l[li],l[li+1]) else expr=string.format("%s.i64_le(%s,%s,%s,%s)",E.rt,r[li],r[li+1],l[li],l[li+1]) end else if op:match("Lt") then expr=string.format("%s.u64_lt(%s,%s,%s,%s)",E.rt,l[li],l[li+1],r[li],r[li+1]) elseif op:match("Le") then expr=string.format("%s.u64_le(%s,%s,%s,%s)",E.rt,l[li],l[li+1],r[li],r[li+1]) elseif op:match("Gt") then expr=string.format("%s.u64_lt(%s,%s,%s,%s)",E.rt,r[li],r[li+1],l[li],l[li+1]) else expr=string.format("%s.u64_le(%s,%s,%s,%s)",E.rt,r[li],r[li+1],l[li],l[li+1]) end end; q("%s,%s=(%s) and 0xffffffff or 0,(%s) and 0xffffffff or 0",dst[li],dst[li+1],expr,expr) else local li=lane+1; local ll,rr=l[li],r[li]; if op:match("^BackVecS") then ll=signed_expr(E,elem,ll); rr=signed_expr(E,elem,rr) end; local cmp=(op:match("Eq") and "==") or (op:match("Ne") and "~=") or (op:match("Lt") and "<") or (op:match("Le") and "<=") or (op:match("Gt") and ">") or ">="; local mask=({[8]="0xff",[16]="0xffff",[32]="0xffffffff"})[width(elem)]; q("%s=(%s %s %s) and %s or 0",dst[li],ll,cmp,rr,mask) end end
        elseif k=="CmdVecMask" then local args=cmd.args; local a=comps(f,args[1]); local b=args[2] and comps(f,args[2]); local op=kind(cmd.op); for i=1,#dst do if op=="BackVecMaskNot" then q("%s=%s.u%d(%s(%s))",dst[i],E.rt,(is64(elem) and 32 or width(elem)),E.bnot,a[i]) elseif op=="BackVecMaskAnd" then q("%s=%s(%s,%s)",dst[i],E.band,a[i],b[i]) else q("%s=%s(%s,%s)",dst[i],E.bor,a[i],b[i]) end end
        elseif k=="CmdVecSelect" then if is_float(elem) then error("float vector select is rejected") end; local m,t,e=comps(f,cmd.mask),comps(f,cmd.then_value),comps(f,cmd.else_value); for i=1,#dst do q("%s=%s(%s(%s,%s),%s(%s(%s),%s))",dst[i],E.bor,E.band,m[i],t[i],E.band,E.bnot,m[i],e[i]) end
        elseif k=="CmdVecInsertLane" then assign_comps(q,dst,comps(f,cmd.value)); local lv=comps(f,cmd.lane_value); for j=1,per do q("%s=%s",dst[cmd.lane*per+j],lv[j]) end
        elseif k=="CmdVecExtractLane" then local src=comps(f,cmd.value); local d=comps(f,cmd.dst); for j=1,#d do q("%s=%s",d[j],src[cmd.lane*per+j]) end
        end
    elseif k=="CmdCall" then
        local sig=mod.sigs[id_text(cmd.sig)]
        local target=cmd.target; local tk=kind(target); local rc=kind(cmd.result)
        local function c_arg(sn, cs)
            if sn=="I8" then return string.format("%s.s8(%s)",E.rt,cs[1]) end
            if sn=="I16" then return string.format("%s.s16(%s)",E.rt,cs[1]) end
            if sn=="I32" then return string.format("%s.s32(%s)",E.rt,cs[1]) end
            if sn=="I64" then return string.format("%s.pack_i64(%s,%s)",E.rt,cs[1],cs[2]) end
            if sn=="U64" or sn=="Index" then return string.format("%s.pack_u64(%s,%s)",E.rt,cs[1],cs[2]) end
            if sn=="Bool" then return string.format("%s~=0",cs[1]) end
            return cs[1]
        end
        if tk=="BackCallExtern" then
            local args={}; for i,a in ipairs(cmd.args) do args[#args+1]=c_arg(sig.params[i], comps(f,a)) end
            local call=mod.emit.extern[id_text(target.func)]
            if rc=="BackCallValue" then
                local dst=comps(f,cmd.result.dst); local rsn=scalar_name(cmd.result.ty)
                if is64(rsn) then q("%s=%s(%s)",f.emit.scratch,call,table.concat(args,",")); q("%s,%s=%s.%s(%s)",dst[1],dst[2],E.rt,rsn=="I64" and "unpack_i64" or "unpack_u64",f.emit.scratch)
                else q("%s=%s",dst[1],normalize_expr(E,rsn,string.format("%s(%s)",call,table.concat(args,",")))) end
            else q("%s(%s)",call,table.concat(args,",")) end
        else
            local args={}; for _,a in ipairs(cmd.args) do local cs=comps(f,a); for _,c in ipairs(cs) do args[#args+1]=c end end
            local call
            if tk=="BackCallDirect" then call=mod.emit.fn[id_text(target.func)]
            else
                local callee=first(f,target.callee)
                local cpars={}; for _,sn in ipairs(sig.params) do cpars[#cpars+1]=(({Bool="bool",I8="int8_t",U8="uint8_t",I16="int16_t",U16="uint16_t",I32="int32_t",U32="uint32_t",I64="int64_t",U64="uint64_t",F32="float",F64="double",Ptr="void*",Index="uint64_t"})[sn] or "int32_t") end
                local ret=sig.results[1] and (({Bool="bool",I8="int8_t",U8="uint8_t",I16="int16_t",U16="uint16_t",I32="int32_t",U32="uint32_t",I64="int64_t",U64="uint64_t",F32="float",F64="double",Ptr="void*",Index="uint64_t"})[sig.results[1]] or "int32_t") or "void"
                local fp=ffi.typeof(ret.."(*)("..table.concat(cpars,",")..")")
                call=string.format("(type(%s)=='function' and %s or %s(%s,%s))",callee,callee,E.cast,q:val(fp,"fp"),callee)
            end
            if rc=="BackCallValue" then local dst=comps(f,cmd.result.dst); q("%s=%s(%s)",table.concat(dst,","),call,table.concat(args,",")) else q("%s(%s)",call,table.concat(args,",")) end
        end
    end
end

local function emit_function(q, mod, f)
    local E=mod.emit; assign_value_symbols(q,f)
    local params={}
    for _,pid in ipairs(f.entry_params or {}) do for _,c in ipairs(comps(f,pid)) do params[#params+1]=c end end
    q("%s=function(%s)", mod.emit.fn[f.id], table.concat(params,","))
    local locals={f.emit.scratch}
    for vid,cs in pairs(f.emit.val) do
        local isparam=false; for _,p in ipairs(params) do for _,c in ipairs(cs) do if c==p then isparam=true end end end
        if not isparam then for _,c in ipairs(cs) do locals[#locals+1]=c end end
    end
    for _,s in pairs(f.emit.stack) do locals[#locals+1]=s.owner; locals[#locals+1]=s.ptr end
    if #locals>0 then q("local %s", table.concat(locals,",")) end
    for sid,info in pairs(f.stack_slots) do local s=f.emit.stack[sid]; q("%s,%s=%s.alloc_aligned(%d,%d)",s.owner,s.ptr,E.rt,info.size,info.align) end
    for _,bid in ipairs(f.emit.order) do
        local b=f.blocks[bid]
        q("::%s::", f.emit.labels[bid])
        for _,nc in ipairs(b.cmds) do emit_cmd(q,mod,f,nc) end
        local term=b.term
        if term then
            local cmd,k=term.cmd,term.kind
            if k=="CmdJump" then edge_copy(q,f,cmd.dest,cmd.args); q("goto %s",f.emit.labels[id_text(cmd.dest)])
            elseif k=="CmdBrIf" then q("if %s~=0 then",first(f,cmd.cond)); edge_copy(q,f,cmd.then_block,cmd.then_args); q("goto %s",f.emit.labels[id_text(cmd.then_block)]); q("else"); edge_copy(q,f,cmd.else_block,cmd.else_args); q("goto %s",f.emit.labels[id_text(cmd.else_block)]); q("end")
            elseif k=="CmdSwitchInt" then
                local v=comps(f,cmd.value); local sh=shape(f,cmd.value); local firstcase=true
                for _,cs in ipairs(cmd.cases) do
                    local cond
                    if is64(sh.scalar) then local lo,hi=rt.const_u64(cs.raw); cond=string.format("%s==%d and %s==%d",v[1],lo,v[2],hi) else cond=string.format("%s==%s",v[1],cs.raw) end
                    q("%s %s then", firstcase and "if" or "elseif", cond); q("goto %s",f.emit.labels[id_text(cs.dest)]); firstcase=false
                end
                q("else"); q("goto %s",f.emit.labels[id_text(cmd.default_dest)]); q("end")
            elseif k=="CmdReturnVoid" then q("do return end")
            elseif k=="CmdReturnValue" then q("do return %s end", table.concat(comps(f,cmd.value),","))
            elseif k=="CmdTrap" then q("do error('trap') end") end
        end
    end
    q("end")
end

local function public_arg_expr(E, sn, name)
    if sn=="Bool" then return { string.format("%s.bool8(%s)",E.rt,name) }
    elseif sn=="I8" or sn=="U8" then return { string.format("%s.u8(%s)",E.rt,name) }
    elseif sn=="I16" or sn=="U16" then return { string.format("%s.u16(%s)",E.rt,name) }
    elseif sn=="I32" then return { string.format("%s(%s)",E.tobit,name) }
    elseif sn=="U32" then return { string.format("%s.u32(%s)",E.rt,name) }
    elseif sn=="I64" then return { string.format("select(1,%s.unpack_i64(%s))",E.rt,name), string.format("select(2,%s.unpack_i64(%s))",E.rt,name) }
    elseif sn=="U64" or sn=="Index" then return { string.format("select(1,%s.unpack_u64(%s))",E.rt,name), string.format("select(2,%s.unpack_u64(%s))",E.rt,name) }
    elseif sn=="F32" then return { string.format("%s.f32(%s)",E.rt,name) }
    else return { name } end
end
local function public_ret_expr(E, sn, comps)
    if sn=="Bool" then return string.format("%s~=0",comps[1]) end
    if sn=="I8" then return string.format("%s.s8(%s)",E.rt,comps[1]) end
    if sn=="I16" then return string.format("%s.s16(%s)",E.rt,comps[1]) end
    if sn=="I32" then return comps[1] end
    if sn=="U8" or sn=="U16" or sn=="U32" or sn=="F32" or sn=="F64" or sn=="Ptr" then return comps[1] end
    if sn=="I64" then return string.format("%s.pack_i64(%s,%s)",E.rt,comps[1],comps[2]) end
    if sn=="U64" or sn=="Index" then return string.format("%s.pack_u64(%s,%s)",E.rt,comps[1],comps[2]) end
    return comps[1]
end

local function emit_exports(q, mod)
    local E=mod.emit
    for _,fid in ipairs(mod.func_order) do if mod.exported[fid] then
        local f=mod.funcs[fid]; local ps={}; for i=1,#f.params do ps[i]=q:sym("arg") end
        q("%s=function(%s)",mod.emit.export[fid],table.concat(ps,","))
        local callargs={}
        for i,sn in ipairs(f.params) do local exs=public_arg_expr(E,sn,ps[i]); for _,e in ipairs(exs) do callargs[#callargs+1]=e end end
        if #f.results==0 then q("%s(%s)",mod.emit.fn[fid],table.concat(callargs,",")); q("return")
        else
            local rsh=scalar_shape(f.results[1]); local rvars=comp_names_for_hint(q,"ret",rsh)
            q("local %s",table.concat(rvars,",")); q("%s=%s(%s)",table.concat(rvars,","),mod.emit.fn[fid],table.concat(callargs,",")); q("return %s",public_ret_expr(E,f.results[1],rvars))
        end
        q("end")
    end end
    q("local module={}")
    q("local functions={}")
    for _,fid in ipairs(mod.func_order) do q("functions[%q]=%s",fid,mod.emit.fn[fid]); if mod.exported[fid] then q("module[%q]=%s",fid,mod.emit.export[fid]) end end
    q("return {module=module,functions=functions,data_owners=__data_owners}")
end

local function emit_module(mod, opts)
    local q=quote(); prepare_emit(q,mod); local E=mod.emit
    -- data allocation/init. Keep owners in the returned payload so data pointers never dangle.
    q("local __data_owners={}")
    for did,d in pairs(mod.datas) do local ds=mod.emit.data[did]; q("local %s,%s=%s.alloc_aligned(%d,%d)",ds.owner,ds.ptr,E.rt,d.size,d.align); q("__data_owners[%q]=%s",did,ds.owner); for _,init in ipairs(d.inits) do if init.kind=="zero" then q("%s.data_zero(%s,%d,%d)",E.rt,ds.ptr,init.offset,init.size) else local lit=init.value; local lk=kind(lit); if lk=="BackLitInt" then q("%s.data_init(%s,%d,%q,'I',%q)",E.rt,ds.ptr,init.offset,init.scalar,lit.raw) elseif lk=="BackLitFloat" then q("%s.data_init(%s,%d,%q,'F',%q)",E.rt,ds.ptr,init.offset,init.scalar,lit.raw) elseif lk=="BackLitBool" then q("%s.data_init(%s,%d,%q,'B',%q)",E.rt,ds.ptr,init.offset,init.scalar,lit.value and "1" or "0") elseif lk=="BackLitNull" then q("%s.data_init(%s,%d,%q,'N','0')",E.rt,ds.ptr,init.offset,init.scalar) end end end end
    local fns={}; for _,fid in ipairs(mod.func_order) do fns[#fns+1]=mod.emit.fn[fid] end; if #fns>0 then q("local %s",table.concat(fns,",")) end
    local exps={}; for _,fid in ipairs(mod.func_order) do if mod.exported[fid] then exps[#exps+1]=mod.emit.export[fid] end end; if #exps>0 then q("local %s",table.concat(exps,",")) end
    for _,fid in ipairs(mod.func_order) do emit_function(q,mod,mod.funcs[fid]) end
    emit_exports(q,mod)
    local payload,src = q:compile("=moonlift_back_luajit")
    return payload, src
end

function M.Define(T, opts)
    local function compile(program, compile_opts)
        local mod = collect(T, program)
        for _,fid in ipairs(mod.func_order) do analyze_function(mod, mod.funcs[fid]) end
        local payload, src = emit_module(mod, compile_opts or opts or {})
        return { module=payload.module, functions=payload.functions, data_owners=payload.data_owners, source=src, meta=mod }
    end
    return { compile=compile }
end

return M
