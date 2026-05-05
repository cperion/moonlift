-- tape_encode.lua — Flatten MoonBack.BackProgram → flat tape arrays
local pvm = require("moonlift.pvm")
local M = {}

local TAG = {
    CONST_INT=1,CONST_FLT=2,CONST_BOOL=3,CONST_NULL=4,
    IADD=10,ISUB=11,IMUL=12,SDIV=13,UDIV=14,SREM=15,UREM=16,
    BAND=20,BOR=21,BXOR=22,BNOT=23,ISHL=24,SSHR=25,USHR=26,ROTL=27,ROTR=28,
    FADD=30,FSUB=31,FMUL=32,FDIV=33,
    ICMP_EQ=40,ICMP_NE=41,SCMP_LT=42,SCMP_LE=43,SCMP_GT=44,SCMP_GE=45,
    UCMP_LT=46,UCMP_LE=47,UCMP_GT=48,UCMP_GE=49,
    FCMP_EQ=50,FCMP_NE=51,FCMP_LT=52,FCMP_LE=53,FCMP_GT=54,FCMP_GE=55,
    BITCAST=60,IREDUCE=61,SEXTEND=62,UEXTEND=63,FPROMOTE=64,FDEMOTE=65,
    STOF=66,UTOF=67,FTOS=68,FTOU=69,
    INEG=70,FNEG=71,BOOLNOT=72,
    POPCOUNT=80,CLZ=81,CTZ=82,BSWAP=83,SQRT=84,
    ABS_I=85,ABS_F=86,FLOOR=87,CEIL=88,TRUNC=89,ROUND=90,
    JUMP=100,BR_IF=101,SWITCH=102,RET_VOID=103,RET_VAL=104,TRAP=105,
    LOAD=110,STORE=111,PTR_OFFSET=112,MEMCPY=113,MEMSET=114,
    STACK_ADDR=120,
    CALL_DIR=130,CALL_EXT=131,CALL_IND=132,
    CALL_DIR_V=133,CALL_EXT_V=134,CALL_IND_V=135,
    ALIAS=140,SELECT_=150,FMA=151,BLOCK_ARG=160,NARROW=161,
}
local narrow_mask = {I8=0xFF,U8=0xFF,I16=0xFFFF,U16=0xFFFF,I32=0xFFFFFFFF,U32=0xFFFFFFFF}
local sc_bytes = {Bool=1,I8=1,U8=1,I16=2,U16=2,I32=4,U32=4,F32=4,I64=8,U64=8,F64=8,Ptr=8,Index=8}

local function sname(s) local k=pvm.classof(s).kind; return k and k:gsub("^Back","") or "I32" end
local function itxt(id) if type(id)=="string" then return id end; return id.text end
local function cls(x) return pvm.classof(x) end

function M.Define(T_ctx)
    local Back=T_ctx.MoonBack; local Core=T_ctx.MoonCore

    local icmp_tag={[Back.BackIcmpEq]=TAG.ICMP_EQ,[Back.BackIcmpNe]=TAG.ICMP_NE,[Back.BackSIcmpLt]=TAG.SCMP_LT,[Back.BackSIcmpLe]=TAG.SCMP_LE,[Back.BackSIcmpGt]=TAG.SCMP_GT,[Back.BackSIcmpGe]=TAG.SCMP_GE,[Back.BackUIcmpLt]=TAG.UCMP_LT,[Back.BackUIcmpLe]=TAG.UCMP_LE,[Back.BackUIcmpGt]=TAG.UCMP_GT,[Back.BackUIcmpGe]=TAG.UCMP_GE}
    local fcmp_tag={[Back.BackFCmpEq]=TAG.FCMP_EQ,[Back.BackFCmpNe]=TAG.FCMP_NE,[Back.BackFCmpLt]=TAG.FCMP_LT,[Back.BackFCmpLe]=TAG.FCMP_LE,[Back.BackFCmpGt]=TAG.FCMP_GT,[Back.BackFCmpGe]=TAG.FCMP_GE}
    local int_op={[Back.BackIntAdd]=TAG.IADD,[Back.BackIntSub]=TAG.ISUB,[Back.BackIntMul]=TAG.IMUL,[Back.BackIntSDiv]=TAG.SDIV,[Back.BackIntUDiv]=TAG.UDIV,[Back.BackIntSRem]=TAG.SREM,[Back.BackIntURem]=TAG.UREM}
    local bit_op={[Back.BackBitAnd]=TAG.BAND,[Back.BackBitOr]=TAG.BOR,[Back.BackBitXor]=TAG.BXOR}
    local sh_op={[Back.BackShiftLeft]=TAG.ISHL,[Back.BackShiftLogicalRight]=TAG.USHR,[Back.BackShiftArithmeticRight]=TAG.SSHR}
    local fl_op={[Back.BackFloatAdd]=TAG.FADD,[Back.BackFloatSub]=TAG.FSUB,[Back.BackFloatMul]=TAG.FMUL,[Back.BackFloatDiv]=TAG.FDIV}
    local cast_op={[Back.BackBitcast]=TAG.BITCAST,[Back.BackIreduce]=TAG.IREDUCE,[Back.BackSextend]=TAG.SEXTEND,[Back.BackUextend]=TAG.UEXTEND,[Back.BackFpromote]=TAG.FPROMOTE,[Back.BackFdemote]=TAG.FDEMOTE,[Back.BackSToF]=TAG.STOF,[Back.BackUToF]=TAG.UTOF,[Back.BackFToS]=TAG.FTOS,[Back.BackFToU]=TAG.FTOU}
    local intr_op={[Back.BackIntrinsicPopcount]=TAG.POPCOUNT,[Back.BackIntrinsicClz]=TAG.CLZ,[Back.BackIntrinsicCtz]=TAG.CTZ,[Back.BackIntrinsicBswap]=TAG.BSWAP,[Back.BackIntrinsicSqrt]=TAG.SQRT,[Back.BackIntrinsicFloor]=TAG.FLOOR,[Back.BackIntrinsicCeil]=TAG.CEIL,[Back.BackIntrinsicTruncFloat]=TAG.TRUNC,[Back.BackIntrinsicRound]=TAG.ROUND}

    local function encode(program)
        local cmds=program.cmds; if #cmds==0 then return {funcs={},externs={}} end

        -- Phase 1: collect metadata, assign registers
        local sigs,func_decls,extern_decls,exported={},{},{},{}
        local cf=nil; local reg_map,reg_count={},0
        local funcs={} -- fid → {entry_params,entry_block,body_cmds,block_params}

        local function reg(id)
            if id==nil then return 0 end
            local rt=itxt(id); if rt==nil then return 0 end
            if not reg_map[rt] then reg_count=reg_count+1; reg_map[rt]=reg_count end
            return reg_map[rt]
        end

        for _,cmd in ipairs(cmds) do
            local c=cls(cmd)
            if c==Back.CmdCreateSig then sigs[itxt(cmd.sig)]={params=cmd.params,results=cmd.results}
            elseif c==Back.CmdDeclareFunc then
                local fid=itxt(cmd.func); func_decls[fid]={sig=sigs[itxt(cmd.sig)]}
                if cmd.visibility and cls(cmd.visibility)==Core.VisibilityExport then exported[fid]=true end
            elseif c==Back.CmdDeclareExtern then extern_decls[itxt(cmd.func)]={symbol=cmd.symbol,sig=sigs[itxt(cmd.sig)]}
            elseif c==Back.CmdBeginFunc then cf=itxt(cmd.func); funcs[cf]={entry_params={},entry_block=nil,body_cmds={},block_params={}}
            elseif c==Back.CmdBindEntryParams and cf then
                local f=funcs[cf]; f.entry_block=itxt(cmd.block)
                for _,v in ipairs(cmd.values) do f.entry_params[#f.entry_params+1]=itxt(v) end
            elseif c==Back.CmdAppendBlockParam and cf then
                local f=funcs[cf]; local bid=itxt(cmd.block)
                if not f.block_params[bid] then f.block_params[bid]={} end
                f.block_params[bid][#f.block_params[bid]+1]=itxt(cmd.value)
            elseif cf then
                funcs[cf].body_cmds[#funcs[cf].body_cmds+1]=cmd
            end
        end

        -- Pre-register all vals
        for _,cmd in ipairs(cmds) do
            local function rv(x) if x then reg(x) end end
            rv(cmd.dst);rv(cmd.src);rv(cmd.lhs);rv(cmd.rhs);rv(cmd.cond)
            rv(cmd.then_value);rv(cmd.else_value);rv(cmd.value);rv(cmd.index)
            rv(cmd.byte_offset);rv(cmd.byte);rv(cmd.len);rv(cmd.callee)
            rv(cmd.a);rv(cmd.b);rv(cmd.c);rv(cmd.lane_value)
            if cmd.args then for _,a in ipairs(cmd.args) do rv(a) end end
            if cmd.values then for _,a in ipairs(cmd.values) do rv(a) end end
        end

        -- Phase 2: encode each function body
        local encoded_funcs={}
        for fid,finfo in pairs(funcs) do
            local tape={}
            local block_pos={} -- block_id_text → tape index
            local pending={} -- {idx,field,block_id} for forward references

            local function emit(tag,...)
                local t={tag,...}; tape[#tape+1]=t; return #tape
            end
            local function place_block(bid)
                block_pos[bid]=#tape+1
                -- resolve pending references to this block
                for i=#pending,1,-1 do
                    local p=pending[i]
                    if p.block==bid then tape[p.idx][p.field]=block_pos[bid]; table.remove(pending,i) end
                end
            end
            local function set_or_pend(idx,field,bid) -- set PC or defer for forward ref
                if block_pos[bid] then tape[idx][field]=block_pos[bid]
                else pending[#pending+1]={idx=idx,field=field,block=bid}; tape[idx][field]=0 end
            end
            local function narrow_reg(dst_reg,scalar)
                local m=narrow_mask[sname(scalar)]; if m then emit(TAG.NARROW,dst_reg,m) end
            end

            for _,cmd in ipairs(finfo.body_cmds) do
                local c=cls(cmd)

                if c==Back.CmdCreateBlock then
                elseif c==Back.CmdSwitchToBlock then place_block(itxt(cmd.block))
                elseif c==Back.CmdSealBlock then
                elseif c==Back.CmdBindEntryParams then place_block(itxt(cmd.block))
                elseif c==Back.CmdAppendBlockParam then
                elseif c==Back.CmdCreateStackSlot then
                elseif c==Back.CmdAlias then emit(TAG.ALIAS,reg(cmd.dst),reg(cmd.src))
                elseif c==Back.CmdStackAddr then emit(TAG.STACK_ADDR,reg(cmd.dst),itxt(cmd.slot))

                elseif c==Back.CmdConst then
                    local lit=cmd.value; local lc=cls(lit)
                    if lc==Back.BackLitInt then emit(TAG.CONST_INT,reg(cmd.dst),lit.raw)
                    elseif lc==Back.BackLitFloat then emit(TAG.CONST_FLT,reg(cmd.dst),lit.raw)
                    elseif lc==Back.BackLitBool then emit(TAG.CONST_BOOL,reg(cmd.dst),lit.value and 1 or 0)
                    elseif lc==Back.BackLitNull then emit(TAG.CONST_NULL,reg(cmd.dst)) end

                elseif c==Back.CmdUnary then
                    local op=cmd.op
                    if op==Back.BackUnaryIneg then emit(TAG.INEG,reg(cmd.dst),reg(cmd.value))
                    elseif op==Back.BackUnaryFneg then emit(TAG.FNEG,reg(cmd.dst),reg(cmd.value))
                    elseif op==Back.BackUnaryBnot then emit(TAG.BNOT,reg(cmd.dst),reg(cmd.value))
                    elseif op==Back.BackUnaryBoolNot then emit(TAG.BOOLNOT,reg(cmd.dst),reg(cmd.value)) end
                    if cmd.ty and cls(cmd.ty)==Back.BackShapeScalar then narrow_reg(reg(cmd.dst),cmd.ty.scalar) end

                elseif c==Back.CmdIntrinsic then
                    local op=cmd.op; local tv
                    if op==Back.BackIntrinsicAbs then
                        local sc=cmd.ty and cls(cmd.ty)==Back.BackShapeScalar and cmd.ty.scalar
                        tv=sc and (sname(sc):match("^F") and TAG.ABS_F or TAG.ABS_I) or TAG.ABS_I
                    else tv=intr_op[op] end
                    if tv then emit(tv,reg(cmd.dst),reg(cmd.args[1])); narrow_reg(reg(cmd.dst),cmd.ty and cmd.ty.scalar) end

                elseif c==Back.CmdCompare then
                    local ot=icmp_tag[cmd.op] or fcmp_tag[cmd.op]
                    if ot then emit(ot,reg(cmd.dst),reg(cmd.lhs),reg(cmd.rhs)) end

                elseif c==Back.CmdCast then
                    if cmd.op==Back.BackIreduce then
                        local m=narrow_mask[sname(cmd.ty)]; emit(TAG.ALIAS,reg(cmd.dst),reg(cmd.value))
                        if m then emit(TAG.NARROW,reg(cmd.dst),m) end
                    else
                        local ot=cast_op[cmd.op]
                        if ot then emit(ot,reg(cmd.dst),reg(cmd.value)); narrow_reg(reg(cmd.dst),cmd.ty) end
                    end

                elseif c==Back.CmdIntBinary then
                    local ot=int_op[cmd.op]; if ot then emit(ot,reg(cmd.dst),reg(cmd.lhs),reg(cmd.rhs)); narrow_reg(reg(cmd.dst),cmd.scalar) end
                elseif c==Back.CmdBitBinary then
                    local ot=bit_op[cmd.op]; if ot then emit(ot,reg(cmd.dst),reg(cmd.lhs),reg(cmd.rhs)); narrow_reg(reg(cmd.dst),cmd.scalar) end
                elseif c==Back.CmdBitNot then emit(TAG.BNOT,reg(cmd.dst),reg(cmd.value)); narrow_reg(reg(cmd.dst),cmd.scalar)
                elseif c==Back.CmdShift then
                    local ot=sh_op[cmd.op]; if ot then emit(ot,reg(cmd.dst),reg(cmd.lhs),reg(cmd.rhs)); narrow_reg(reg(cmd.dst),cmd.scalar) end
                elseif c==Back.CmdRotate then
                    local tv=cmd.op==Back.BackRotateLeft and TAG.ROTL or TAG.ROTR
                    emit(tv,reg(cmd.dst),reg(cmd.lhs),reg(cmd.rhs)); narrow_reg(reg(cmd.dst),cmd.scalar)
                elseif c==Back.CmdFloatBinary then
                    local ot=fl_op[cmd.op]; if ot then emit(ot,reg(cmd.dst),reg(cmd.lhs),reg(cmd.rhs)) end

                elseif c==Back.CmdSelect then
                    emit(TAG.SELECT_,reg(cmd.dst),reg(cmd.cond),reg(cmd.then_value),reg(cmd.else_value))
                    if cls(cmd.ty)==Back.BackShapeScalar then narrow_reg(reg(cmd.dst),cmd.ty.scalar) end
                elseif c==Back.CmdFma then emit(TAG.FMA,reg(cmd.dst),reg(cmd.a),reg(cmd.b),reg(cmd.c))

                elseif c==Back.CmdPtrOffset then
                    local base=0; local bc=cls(cmd.base)
                    if bc==Back.BackAddrValue then base=reg(cmd.base.value) end
                    emit(TAG.PTR_OFFSET,reg(cmd.dst),base,reg(cmd.index),cmd.elem_size or 1,cmd.const_offset or 0)

                elseif c==Back.CmdLoadInfo then
                    local sz=4; local sg=1
                    if cls(cmd.ty)==Back.BackShapeScalar then
                        local sn=sname(cmd.ty.scalar); sz=sc_bytes[sn] or 4
                        sg=(sn:match("^[IU]") and sn~="I") and 0 or 1
                    end
                    local base=cmd.addr and cmd.addr.base and cls(cmd.addr.base)==Back.BackAddrValue and reg(cmd.addr.base.value) or 0
                    local off=cmd.addr and reg(cmd.addr.byte_offset) or 0
                    emit(TAG.LOAD,reg(cmd.dst),base,off,sz,sg)

                elseif c==Back.CmdStoreInfo then
                    local sz=4
                    if cls(cmd.ty)==Back.BackShapeScalar then sz=sc_bytes[sname(cmd.ty.scalar)] or 4 end
                    local base=cmd.addr and cmd.addr.base and cls(cmd.addr.base)==Back.BackAddrValue and reg(cmd.addr.base.value) or 0
                    local off=cmd.addr and reg(cmd.addr.byte_offset) or 0
                    emit(TAG.STORE,base,off,reg(cmd.value),sz)

                elseif c==Back.CmdMemcpy then emit(TAG.MEMCPY,reg(cmd.dst),reg(cmd.src),reg(cmd.len))
                elseif c==Back.CmdMemset then emit(TAG.MEMSET,reg(cmd.dst),reg(cmd.byte),reg(cmd.len))

                elseif c==Back.CmdCall then
                    local tc=cls(cmd.target); local rc=cls(cmd.result)
                    local has_res=rc==Back.BackCallValue; local dr=has_res and reg(cmd.result.dst) or 0
                    local ar={}; for _,a in ipairs(cmd.args) do ar[#ar+1]=reg(a) end
                    if tc==Back.BackCallDirect then emit(has_res and TAG.CALL_DIR or TAG.CALL_DIR_V,dr,itxt(cmd.target.func),ar)
                    elseif tc==Back.BackCallExtern then
                        local ee=extern_decls[itxt(cmd.target.func)]
                        emit(has_res and TAG.CALL_EXT or TAG.CALL_EXT_V,dr,ee and ee.symbol or itxt(cmd.target.func),ar)
                    elseif tc==Back.BackCallIndirect then
                        local sig=sigs[itxt(cmd.sig)]; local pt,rt={},"I32"
                        if sig then for _,p in ipairs(sig.params) do pt[#pt+1]=sname(p) end; if #sig.results>0 then rt=sname(sig.results[1]) end end
                        emit(has_res and TAG.CALL_IND or TAG.CALL_IND_V,dr,reg(cmd.target.callee),ar,pt,rt)
                    end
                    if has_res and cmd.result.ty then narrow_reg(reg(cmd.result.dst),cmd.result.ty) end

                elseif c==Back.CmdJump then
                    local dest_id=itxt(cmd.dest)
                    -- Emit BLOCK_ARG for each jump arg
                    local bp=finfo.block_params; local ba=bp and bp[dest_id]
                    if ba and #cmd.args>0 then
                        for i=1,math.min(#ba,#cmd.args) do emit(TAG.BLOCK_ARG,reg(ba[i]),reg(cmd.args[i])) end
                    end
                    local idx=emit(TAG.JUMP,0)
                    set_or_pend(idx,2,dest_id)

                elseif c==Back.CmdBrIf then
                    local idx=emit(TAG.BR_IF,reg(cmd.cond),0,0)
                    set_or_pend(idx,3,itxt(cmd.then_block))
                    set_or_pend(idx,4,itxt(cmd.else_block))

                elseif c==Back.CmdSwitchInt then
                    local cases={}
                    for _,cs in ipairs(cmd.cases) do cases[cs.raw]=0; table.insert(pending,{idx=0,field=0,block=itxt(cs.dest),cases=cases,key=cs.raw}) end
                    local idx=emit(TAG.SWITCH,reg(cmd.value),0,cases)
                    -- fixup all case targets
                    for _,p in ipairs(pending) do
                        if p.cases==cases then
                            if block_pos[p.block] then cases[p.key]=block_pos[p.block]
                            else table.insert(pending,{idx=idx,field=0,block=p.block,cases=cases,key=p.key}) end
                        end
                    end
                    set_or_pend(idx,2,itxt(cmd.default_dest))

                elseif c==Back.CmdReturnVoid then emit(TAG.RET_VOID)
                elseif c==Back.CmdReturnValue then emit(TAG.RET_VAL,reg(cmd.value))
                elseif c==Back.CmdTrap then emit(TAG.TRAP)
                end
            end

            local entry_pc=finfo.entry_block and block_pos[finfo.entry_block] or 1
            encoded_funcs[fid]={tape=tape,entry_pc=entry_pc,entry_params=finfo.entry_params}
        end

        return {funcs=encoded_funcs,externs=extern_decls,sigs=sigs,exported=exported,reg_map=reg_map}
    end

    return {encode=encode,TAG=TAG}
end
return M
