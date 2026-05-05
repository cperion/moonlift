-- back_luajit.lua — LuaJIT Cranelift Machine
--
-- Replaces src/lib.rs (Rust/Cranelift). Walks a verified MoonBack.BackProgram
-- tape and generates Lua source. Per-function compilation with trampoline
-- self-calls (push+goto for recursion). LuaJIT traces to native code.
--
-- No Rust. No Cranelift. No build. Pure LuaJIT from BackCmd → native.

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local quote = require("moonlift.quote")

local M = {}

local scalar_ctype = {
    Bool="bool", I8="int8_t", U8="uint8_t", I16="int16_t", U16="uint16_t",
    I32="int32_t", U32="uint32_t", F32="float", I64="int64_t",
    U64="uint64_t", F64="double", Ptr="void*", Index="uint64_t",
}
local narrow_mask = {
    I8="bit.band(%s,0xFF)", U8="bit.band(%s,0xFF)",
    I16="bit.band(%s,0xFFFF)", U16="bit.band(%s,0xFFFF)",
    I32="bit.band(%s,0xFFFFFFFF)", U32="bit.band(%s,0xFFFFFFFF)",
}

local function sname(s) local k=pvm.classof(s).kind; return k and k:gsub("^Back","") or "I32" end
local function ish(t) return t:gsub("[^%w]","_"):gsub("_+","_"):gsub("^_",""):gsub("_$","") end
local function itxt(id) if type(id)=="string" then return id end; return id.text end
local function mn(buf,dst,sn) local m=narrow_mask[sn]; if m then buf("%s=%s",dst,string.format(m,dst)) end end

function M.Define(T)
    local Back=T.MoonBack; local Core=T.MoonCore
    local function cls(x) return pvm.classof(x) end

    local function compile(program)
        assert(cls(program)==Back.BackProgram,"back_luajit expects MoonBack.BackProgram")
        local cmds=program.cmds; if #cmds==0 then error("empty BackProgram") end

        -- Phase 1: collect
        local sigs,funcs,externs,exported={},{},{},{}
        local cf=nil
        local blocks,vals,slots={},{},{}
        local entry_params,block_params={},{}
        local func_entry_block={} -- fid → block_id_text of entry block
        local vs,ss,bs=0,0,0

        local function rv(id)
            if id==nil then return nil end
            local vt=itxt(id); if vt==nil then return nil end
            if not vals[vt] then vs=vs+1; vals[vt]=string.format("v%d",vs) end
            return vals[vt]
        end

        for _,cmd in ipairs(cmds) do
            local c=cls(cmd)
            if c==Back.CmdCreateSig then sigs[itxt(cmd.sig)]={params=cmd.params,results=cmd.results}
            elseif c==Back.CmdDeclareFunc then
                local fid=itxt(cmd.func); funcs[fid]={sig=sigs[itxt(cmd.sig)]}
                if cmd.visibility and cls(cmd.visibility)==Core.VisibilityExport then exported[fid]=true end
            elseif c==Back.CmdDeclareExtern then externs[itxt(cmd.func)]={symbol=cmd.symbol,sig=sigs[itxt(cmd.sig)]}
            elseif c==Back.CmdBeginFunc then cf=itxt(cmd.func); entry_params[cf]={}
            elseif c==Back.CmdFinishFunc then cf=nil
            elseif c==Back.CmdCreateBlock then bs=bs+1; blocks[itxt(cmd.block)]=string.format("b%d_%s",bs,ish(itxt(cmd.block)))
            elseif c==Back.CmdBindEntryParams then
                if cf then
                    func_entry_block[cf]=itxt(cmd.block)
                    for _,v in ipairs(cmd.values) do entry_params[cf][#entry_params[cf]+1]=itxt(v) end
                end
            elseif c==Back.CmdCreateStackSlot then ss=ss+1; slots[itxt(cmd.slot)]={size=cmd.size,align=cmd.align,var=string.format("slot%d",ss)}
            elseif c==Back.CmdAppendBlockParam then
                local bid=itxt(cmd.block); if not block_params[bid] then block_params[bid]={} end
                block_params[bid][#block_params[bid]+1]=itxt(cmd.value)
            end
            if cmd.dst then rv(cmd.dst) end; if cmd.src then rv(cmd.src) end
            if cmd.lhs then rv(cmd.lhs) end; if cmd.rhs then rv(cmd.rhs) end
            if cmd.cond then rv(cmd.cond) end
            if cmd.then_value then rv(cmd.then_value) end; if cmd.else_value then rv(cmd.else_value) end
            if cmd.value then rv(cmd.value) end; if cmd.index then rv(cmd.index) end
            if cmd.byte_offset then rv(cmd.byte_offset) end; if cmd.byte then rv(cmd.byte) end
            if cmd.len then rv(cmd.len) end; if cmd.callee then rv(cmd.callee) end
            if cmd.a then rv(cmd.a) end; if cmd.b then rv(cmd.b) end; if cmd.c then rv(cmd.c) end
            if cmd.lane_value then rv(cmd.lane_value) end
            if cmd.args then for _,a in ipairs(cmd.args) do rv(a) end end
        end

        -- Phase 2: per-function generation
        local func_bodies={}
        local self_ret_labels={} -- collects all sret label strings
        cf=nil; bs=0
        local buf=nil; local saw_vals={}
        local self_ret_seq=0

        local function vn(val) return vals[itxt(val)] end
        local function lb(id) return blocks[itxt(id)] end

        local function declare_all_vals(skip)
            skip=skip or {}; local n={}
            for _,v in pairs(vals) do if not saw_vals[v] and not skip[v] then n[#n+1]=v; saw_vals[v]=true end end
            if #n>0 then buf("local %s",table.concat(n,", ")) end
        end

        local function init_slots()
            for _,s in pairs(slots) do
                buf("local %s=ffi.new(\"uint8_t[?]\",%d)",s.var,s.size)
            end
        end

        local function ax(addr)
            if not addr then return "nil" end
            local ac=cls(addr.base)
            if ac==Back.BackAddrValue then return string.format("ffi.cast(\"uint8_t*\",%s)+%s",vn(addr.base.value),vn(addr.byte_offset))
            elseif ac==Back.BackAddrStack then
                local sid=itxt(addr.base.slot); local sv=slots[sid] and slots[sid].var or "nil"
                return string.format("ffi.cast(\"uint8_t*\",%s)+%s",sv,vn(addr.byte_offset))
            end; return "nil"
        end

        local function ea(dst,expr,sr)
            local d=vn(dst); buf("%s=%s",d,expr)
            if sr then mn(buf,d,sname(sr)) end
        end

        for _,cmd in ipairs(cmds) do
            local c=cls(cmd)

            if c==Back.CmdCreateSig or c==Back.CmdDeclareFunc or c==Back.CmdDeclareExtern
               or c==Back.CmdTargetModel or c==Back.CmdDeclareData
               or c==Back.CmdDataInitZero or c==Back.CmdDataInit or c==Back.CmdDataAddr then

            elseif c==Back.CmdBeginFunc then
                cf=itxt(cmd.func); local ep=entry_params[cf] or {}; saw_vals={}
                local skip={}; for _,p in ipairs(ep) do skip[vn(p)]=true end
                buf=quote(); self_ret_seq=0; self_ret_labels={}

                local pns={}; for _,p in ipairs(ep) do pns[#pns+1]=vn(p) end
                buf("local function fn_%s(%s)",ish(cf),table.concat(pns,", "))
                buf("local ffi=require(\"ffi\")")
                buf("local bit=require(\"bit\")")
                -- Trampoline for self-calls
                buf("local _cs={} local _sp=0 local _r=nil")
                declare_all_vals(skip)
                init_slots()

            elseif c==Back.CmdCreateBlock then
                bs=bs+1; local bid=itxt(cmd.block)
                blocks[bid]=string.format("b%d_%s",bs,ish(bid))
            elseif c==Back.CmdSwitchToBlock then buf("::%s::",lb(cmd.block))
            elseif c==Back.CmdSealBlock then
            elseif c==Back.CmdBindEntryParams then
            elseif c==Back.CmdAppendBlockParam then
            elseif c==Back.CmdCreateStackSlot then
            elseif c==Back.CmdAlias then buf("%s=%s",vn(cmd.dst),vn(cmd.src))
            elseif c==Back.CmdStackAddr then
                local sid=itxt(cmd.slot); if slots[sid] then buf("%s=%s",vn(cmd.dst),slots[sid].var) end

            elseif c==Back.CmdConst then
                local lit=cmd.value; local lc=cls(lit); local vs
                if lc==Back.BackLitInt then vs=lit.raw
                elseif lc==Back.BackLitFloat then vs=lit.raw
                elseif lc==Back.BackLitBool then vs=lit.value and "true" or "false"
                elseif lc==Back.BackLitNull then vs="nil" else vs="nil" end
                ea(cmd.dst,vs,cmd.ty)

            elseif c==Back.CmdUnary then
                local op=cmd.op; local v=vn(cmd.value); local ex
                if op==Back.BackUnaryIneg or op==Back.BackUnaryFneg then ex="-"..v
                elseif op==Back.BackUnaryBnot then ex=string.format("bit.bnot(%s)",v)
                elseif op==Back.BackUnaryBoolNot then ex="(not "..v..")" else ex=v end
                ea(cmd.dst,ex,cmd.ty.scalar)

            elseif c==Back.CmdIntrinsic then
                local op=cmd.op; local a={}; for _,x in ipairs(cmd.args) do a[#a+1]=vn(x) end; local ex
                if op==Back.BackIntrinsicSqrt then ex=string.format("math.sqrt(%s)",a[1])
                elseif op==Back.BackIntrinsicAbs then ex=string.format("math.abs(%s)",a[1])
                elseif op==Back.BackIntrinsicFloor then ex=string.format("math.floor(%s)",a[1])
                elseif op==Back.BackIntrinsicCeil then ex=string.format("math.ceil(%s)",a[1])
                elseif op==Back.BackIntrinsicPopcount then ex=string.format("bit.popc(%s)",a[1])
                elseif op==Back.BackIntrinsicClz then ex=string.format("bit.clz32(bit.band(%s,0xFFFFFFFF))",a[1])
                elseif op==Back.BackIntrinsicCtz then ex=string.format("bit.ctz(bit.band(%s,0xFFFFFFFF))",a[1])
                elseif op==Back.BackIntrinsicBswap then ex=string.format("bit.bswap(%s)",a[1])
                else ex=a[1] end; ea(cmd.dst,ex,cmd.ty.scalar)

            elseif c==Back.CmdCompare then
                local op=cmd.op; local lu="=="
                if op==Back.BackIcmpEq or op==Back.BackFCmpEq then lu="=="
                elseif op==Back.BackIcmpNe or op==Back.BackFCmpNe then lu="~="
                elseif op==Back.BackSIcmpLt or op==Back.BackUIcmpLt or op==Back.BackFCmpLt then lu="<"
                elseif op==Back.BackSIcmpLe or op==Back.BackUIcmpLe or op==Back.BackFCmpLe then lu="<="
                elseif op==Back.BackSIcmpGt or op==Back.BackUIcmpGt or op==Back.BackFCmpGt then lu=">"
                elseif op==Back.BackSIcmpGe or op==Back.BackUIcmpGe or op==Back.BackFCmpGe then lu=">=" end
                ea(cmd.dst,string.format("(%s %s %s)",vn(cmd.lhs),lu,vn(cmd.rhs)),Back.BackBool)

            elseif c==Back.CmdCast then
                local op=cmd.op; local ds=sname(cmd.ty); local v=vn(cmd.value); local ex
                if op==Back.BackBitcast then ex=string.format("ffi.cast(\"%s\",%s)",scalar_ctype[ds] or "void*",v)
                elseif op==Back.BackIreduce then local m=narrow_mask[ds]; ex=m and string.format(m,v) or v
                elseif op==Back.BackSextend or op==Back.BackUextend then ex=v
                elseif op==Back.BackFpromote then ex=string.format("tonumber(%s)",v)
                elseif op==Back.BackFdemote then ex=string.format("ffi.cast(\"float\",%s)",v)
                elseif op==Back.BackSToF or op==Back.BackUToF then ex=string.format("tonumber(%s)",v)
                elseif op==Back.BackFToS then ex=string.format("math.floor(%s)",v)
                elseif op==Back.BackFToU then ex=string.format("math.floor(math.abs(%s))",v)
                else ex=v end; ea(cmd.dst,ex,cmd.ty)

            elseif c==Back.CmdIntBinary then
                local op=cmd.op; local l=vn(cmd.lhs); local r=vn(cmd.rhs); local ex
                if op==Back.BackIntAdd then ex=string.format("(%s+%s)",l,r)
                elseif op==Back.BackIntSub then ex=string.format("(%s-%s)",l,r)
                elseif op==Back.BackIntMul then ex=string.format("(%s*%s)",l,r)
                elseif op==Back.BackIntSDiv or op==Back.BackIntUDiv then ex=string.format("math.floor(%s/%s)",l,r)
                elseif op==Back.BackIntSRem or op==Back.BackIntURem then ex=string.format("(%s%%%s)",l,r)
                else ex=string.format("(%s+%s)",l,r) end; ea(cmd.dst,ex,cmd.scalar)

            elseif c==Back.CmdBitBinary then
                local op=cmd.op; local fn="bit.band"
                if op==Back.BackBitOr then fn="bit.bor" elseif op==Back.BackBitXor then fn="bit.bxor" end
                ea(cmd.dst,string.format("%s(%s,%s)",fn,vn(cmd.lhs),vn(cmd.rhs)),cmd.scalar)

            elseif c==Back.CmdBitNot then ea(cmd.dst,string.format("bit.bnot(%s)",vn(cmd.value)),cmd.scalar)

            elseif c==Back.CmdShift then
                local op=cmd.op; local fn="bit.lshift"
                if op==Back.BackShiftLogicalRight then fn="bit.rshift"
                elseif op==Back.BackShiftArithmeticRight then fn="bit.arshift" end
                ea(cmd.dst,string.format("%s(%s,%s)",fn,vn(cmd.lhs),vn(cmd.rhs)),cmd.scalar)

            elseif c==Back.CmdRotate then
                local l=vn(cmd.lhs); local r=vn(cmd.rhs)
                if cmd.op==Back.BackRotateLeft then buf("%s=bit.bor(bit.lshift(%s,%s),bit.rshift(%s,32-%s))",vn(cmd.dst),l,r,l,r)
                else buf("%s=bit.bor(bit.rshift(%s,%s),bit.lshift(%s,32-%s))",vn(cmd.dst),l,r,l,r) end
                mn(buf,vn(cmd.dst),sname(cmd.scalar))

            elseif c==Back.CmdFloatBinary then
                local op=cmd.op; local os="+"
                if op==Back.BackFloatSub then os="-" elseif op==Back.BackFloatMul then os="*"
                elseif op==Back.BackFloatDiv then os="/" end
                ea(cmd.dst,string.format("(%s %s %s)",vn(cmd.lhs),os,vn(cmd.rhs)),cmd.scalar)

            elseif c==Back.CmdPtrOffset then
                local dst=vn(cmd.dst); local base
                local bc=cls(cmd.base)
                if bc==Back.BackAddrValue then base=vn(cmd.base.value)
                elseif bc==Back.BackAddrStack then base=slots[itxt(cmd.base.slot)].var else base="nil" end
                local ix=vn(cmd.index); local es=cmd.elem_size or 1; local co=cmd.const_offset or 0
                if co~=0 then buf("%s=ffi.cast(\"uint8_t*\",%s)+(%s*%d)+%d",dst,base,ix,es,co)
                else buf("%s=ffi.cast(\"uint8_t*\",%s)+(%s*%d)",dst,base,ix,es) end

            elseif c==Back.CmdLoadInfo then
                local as=ax(cmd.addr); local lt="int32_t"
                local sc=cls(cmd.ty); if sc==Back.BackShapeScalar then lt=scalar_ctype[sname(cmd.ty.scalar)] or "int32_t" end
                buf("%s=ffi.cast(\"%s*\",%s)[0]",vn(cmd.dst),lt,as)

            elseif c==Back.CmdStoreInfo then
                local as=ax(cmd.addr); local st="int32_t"
                local sc=cls(cmd.ty); if sc==Back.BackShapeScalar then st=scalar_ctype[sname(cmd.ty.scalar)] or "int32_t" end
                buf("ffi.cast(\"%s*\",%s)[0]=%s",st,as,vn(cmd.value))

            elseif c==Back.CmdSelect then
                local sr=nil; local sc=cls(cmd.ty); if sc==Back.BackShapeScalar then sr=cmd.ty.scalar end
                ea(cmd.dst,string.format("(%s and %s or %s)",vn(cmd.cond),vn(cmd.then_value),vn(cmd.else_value)),sr)

            elseif c==Back.CmdFma then ea(cmd.dst,string.format("(%s*%s+%s)",vn(cmd.a),vn(cmd.b),vn(cmd.c)),cmd.ty)
            elseif c==Back.CmdMemcpy then buf("ffi.copy(%s,%s,%s)",vn(cmd.dst),vn(cmd.src),vn(cmd.len))
            elseif c==Back.CmdMemset then buf("ffi.fill(%s,%s,%s)",vn(cmd.dst),vn(cmd.byte),vn(cmd.len))
            elseif c==Back.CmdAliasFact then

            elseif c==Back.CmdCall then
                local tc=cls(cmd.target); local rc=cls(cmd.result)
                local sig=sigs[itxt(cmd.sig)]

                if tc==Back.BackCallDirect then
                    local target_fid=itxt(cmd.target.func)
                    if target_fid==cf then
                        -- Self-call: trampoline
                        self_ret_seq=self_ret_seq+1
                        local rl=string.format("sret%d",self_ret_seq)
                        self_ret_labels[#self_ret_labels+1]=rl
                        local ags={}; for _,a in ipairs(cmd.args) do ags[#ags+1]=vn(a) end
                        local ep=entry_params[cf]; local ep_vs={}; for _,p in ipairs(ep) do ep_vs[#ep_vs+1]=vn(p) end
                        -- Push frame with saved entry params BEFORE overwriting them
                        buf("_sp=_sp+1; _cs[_sp]={ret=\"%s\"",rl)
                        for i,pv in ipairs(ep_vs) do buf(",s%d=%s",i,pv) end
                        buf("}")
                        -- NOW set callee entry params from args
                        for i=1,#ags do if ep_vs[i] then buf("%s=%s",ep_vs[i],ags[i]) end end
                        local entry_lbl = func_entry_block[cf]
                        if entry_lbl and blocks[entry_lbl] then
                            buf("goto %s",blocks[entry_lbl])
                        else
                            buf("error(\"no entry block for self-call\")")
                        end
                        buf("::%s::",rl)
                        -- Copy result
                        if rc==Back.BackCallValue then
                            buf("%s=_r",vn(cmd.result.dst))
                            if cmd.result.ty then mn(buf,vn(cmd.result.dst),sname(cmd.result.ty)) end
                        end
                    else
                        -- Cross-function call: Lua call
                        local ce="fn_"..ish(target_fid)
                        local ags={}; for _,a in ipairs(cmd.args) do ags[#ags+1]=vn(a) end
                        if rc==Back.BackCallValue then
                            buf("%s=%s(%s)",vn(cmd.result.dst),ce,table.concat(ags,","))
                            if cmd.result.ty then mn(buf,vn(cmd.result.dst),sname(cmd.result.ty)) end
                        else buf("%s(%s)",ce,table.concat(ags,",")) end
                    end
                elseif tc==Back.BackCallExtern then
                    local ee=externs[itxt(cmd.target.func)]
                    local ce=ee and ("ffi.C."..ee.symbol) or "nil"
                    local ags={}; for _,a in ipairs(cmd.args) do ags[#ags+1]=vn(a) end
                    if rc==Back.BackCallValue then
                        local rt=cmd.result.ty and sname(cmd.result.ty) or "I32"
                        buf("%s=ffi.cast(\"%s\",%s(%s))",vn(cmd.result.dst),scalar_ctype[rt] or "int32_t",ce,table.concat(ags,","))
                        mn(buf,vn(cmd.result.dst),rt)
                    else buf("%s(%s)",ce,table.concat(ags,",")) end
                elseif tc==Back.BackCallIndirect then
                    local pe=vn(cmd.target.callee); local ags={}; for _,a in ipairs(cmd.args) do ags[#ags+1]=vn(a) end
                    if rc==Back.BackCallValue then
                        local pct={}; if sig then for _,p in ipairs(sig.params) do pct[#pct+1]=scalar_ctype[sname(p)] or "int32_t" end end
                        local rct=sig and #sig.results>0 and scalar_ctype[sname(sig.results[1])] or "int32_t"
                        local ss=rct.."(*)"..(#pct>0 and ("("..table.concat(pct,",")..")") or "()")
                        buf("%s=ffi.cast(\"%s\",%s)(%s)",vn(cmd.result.dst),ss,pe,table.concat(ags,","))
                    else buf("ffi.cast(\"void(*)\",%s)(%s)",pe,table.concat(ags,",")) end
                end

            elseif c==Back.CmdJump then
                local dest=lb(cmd.dest); local bp=block_params[itxt(cmd.dest)]
                if bp and #cmd.args>0 then for i=1,math.min(#bp,#cmd.args) do buf("%s=%s",vn(bp[i]),vn(cmd.args[i])) end end
                buf("goto %s",dest)

            elseif c==Back.CmdBrIf then
                local cd=vn(cmd.cond); local tb=lb(cmd.then_block); local fb=lb(cmd.else_block)
                local tbp=block_params[itxt(cmd.then_block)]; local fbp=block_params[itxt(cmd.else_block)]
                buf("if %s then",cd)
                if tbp and #cmd.then_args>0 then for i=1,math.min(#tbp,#cmd.then_args) do buf("  %s=%s",vn(tbp[i]),vn(cmd.then_args[i])) end end
                buf("  goto %s",tb); buf("else")
                if fbp and #cmd.else_args>0 then for i=1,math.min(#fbp,#cmd.else_args) do buf("  %s=%s",vn(fbp[i]),vn(cmd.else_args[i])) end end
                buf("  goto %s",fb); buf("end")

            elseif c==Back.CmdSwitchInt then
                local val=vn(cmd.value); local df=lb(cmd.default_dest)
                for i,cs in ipairs(cmd.cases) do
                    if i==1 then buf("if %s==%s then goto %s",val,cs.raw,lb(cs.dest))
                    else buf("elseif %s==%s then goto %s",val,cs.raw,lb(cs.dest)) end
                end; buf("else goto %s end",df)

            elseif c==Back.CmdReturnVoid then
                buf("if _sp>0 then goto return_dispatch end")
                buf("do return end")

            elseif c==Back.CmdReturnValue then
                buf("_r=%s",vn(cmd.value))
                buf("if _sp>0 then goto return_dispatch end")
                buf("do return _r end")

            elseif c==Back.CmdTrap then buf("error(\"trap\")")

            elseif c==Back.CmdFinishFunc then
                -- Emit return dispatch for trampoline
                buf("::return_dispatch::")
                if #self_ret_labels > 0 then
                    local ep=entry_params[cf]; local ep_vs={}; for _,p in ipairs(ep or {}) do ep_vs[#ep_vs+1]=vn(p) end
                    buf("local fr=_cs[_sp]; _sp=_sp-1")
                    -- Restore caller entry params from frame
                    for i,pv in ipairs(ep_vs) do
                        buf("%s=fr.s%d",pv,i)
                    end
                    buf("local _ret=fr.ret")
                    for i, rl in ipairs(self_ret_labels) do
                        if i == 1 then
                            buf("if _ret==\"%s\" then goto %s", rl, rl)
                        else
                            buf("elseif _ret==\"%s\" then goto %s", rl, rl)
                        end
                    end
                    buf("else error(\"unknown return label: \"..tostring(_ret)) end")
                else
                    buf("error(\"return_dispatch reached without trampoline\")")
                end
                buf("end"); buf("return fn_%s",ish(cf))
                local fn,_=buf:compile("=fn_"..ish(cf))
                func_bodies[cf]=fn; cf=nil

            elseif c==Back.CmdFinalizeModule then
                local mq=quote()
                for fid,fn in pairs(func_bodies) do mq:val(fn,"fn_"..ish(fid)) end
                mq("local mod={}")
                for fid,_ in pairs(exported) do
                    if func_bodies[fid] then
                        local nm=mq:val(func_bodies[fid],"fn_"..ish(fid))
                        mq("mod.%s=%s",ish(fid),nm)
                    end
                end
                mq("return mod")
                local mod_fn,_=mq:compile("=mod")
                local result={module=mod_fn}
                for fid,fn in pairs(func_bodies) do result[ish(fid)]=fn end
                if mod_fn then for k,v in pairs(mod_fn()) do result[k]=v end end
                return result
            end
        end

        local result={}
        for fid,fn in pairs(func_bodies) do result[ish(fid)]=fn end
        return result
    end
    return {compile=compile}
end
return M
