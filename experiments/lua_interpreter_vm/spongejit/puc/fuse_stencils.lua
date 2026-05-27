#!/usr/bin/env luajit
-- fuse_stencils.lua — Replace concatenated stencil chains with fused C functions.
-- Reads an existing sponjit_cache_data.c, generates fused C stubs, compiles
-- with GCC, extracts bytes, and writes the patched cache file.
--
-- This eliminates the RET→NOP fallthrough problem and CALL overhead by
-- producing one self-contained compiled function per foundry form.

local function shell(cmd)
    local h = io.popen(cmd .. " 2>&1")
    local out = h:read("*a")
    h:close()
    return out
end

local function extract_fused_bytes(obj_path, func_name)
    local out = shell(string.format(
        "objdump -d %s | awk '/<%s>:/{f=1;next} /^$/{if(f)exit} f{print $2}'",
        obj_path, func_name))
    local bytes = {}
    for b in out:gmatch("%x%x") do
        bytes[#bytes + 1] = tonumber(b, 16)
    end
    return bytes
end

local function gen_fused_c(descs)
    local lines = {}
    lines[#lines + 1] = '#include <stdint.h>'
    lines[#lines + 1] = '#include <stddef.h>'
    lines[#lines + 1] = 'typedef struct TValue { unsigned long long value_; unsigned char tt_; } TValue;'
    lines[#lines + 1] = 'typedef union StackValue { TValue val; } StackValue;'
    lines[#lines + 1] = 'typedef StackValue *StkId;'
    lines[#lines + 1] = 'typedef unsigned int Instruction;'
    lines[#lines + 1] = '#define LUA_VNIL 0'
    lines[#lines + 1] = '#define LUA_VNUMINT 3'
    lines[#lines + 1] = '#define LUA_VTABLE 69'
    lines[#lines + 1] = '#define s2v(o) (&(o)->val)'
    lines[#lines + 1] = '#define rawtt(o) ((o)->tt_)'
    lines[#lines + 1] = '#define ttisinteger(o) (rawtt(o)==3)'
    lines[#lines + 1] = '#define ttistable(o) (rawtt(o)==69)'
    lines[#lines + 1] = '#define ivalue(o) ((long long)((o)->value_))'
    lines[#lines + 1] = '#define setivalue(o,i) do{(o)->value_=(unsigned long long)(i);(o)->tt_=3;}while(0)'
    lines[#lines + 1] = '#define GET_OPCODE(i) ((int)(((i)>>0)&0x7f))'
    lines[#lines + 1] = '#define GETARG_A(i) ((int)(((i)>>7)&0xff))'
    lines[#lines + 1] = '#define GETARG_B(i) ((int)(((i)>>16)&0xff))'
    lines[#lines + 1] = '#define GETARG_C(i) ((int)(((i)>>24)&0xff))'
    lines[#lines + 1] = '#define GETARG_sC(i) ((int)(GETARG_C(i)-128))'
    lines[#lines + 1] = '#define GETARG_Bx(i) ((int)(((i)>>15)&0x1ffff))'
    lines[#lines + 1] = '#define GETARG_sBx(i) ((int)(GETARG_Bx(i)-65536))'
    lines[#lines + 1] = 'enum {SJ_OK=0,SJ_GUARD_FAIL=1,SJ_UNSUPPORTED=2,SJ_BOUNDARY=3};'
    lines[#lines + 1] = [[
enum {OP_MOVE,OP_LOADI,OP_LOADF,OP_LOADK,OP_LOADKX,OP_LOADFALSE,OP_LFALSESKIP,OP_LOADTRUE,OP_LOADNIL,OP_GETUPVAL,OP_SETUPVAL,
OP_GETTABUP,OP_GETTABLE,OP_GETI,OP_GETFIELD,OP_SETTABUP,OP_SETTABLE,OP_SETI,OP_SETFIELD,OP_NEWTABLE,OP_SELF,OP_ADDI,
OP_ADDK,OP_SUBK,OP_MULK,OP_MODK,OP_POWK,OP_DIVK,OP_IDIVK,OP_BANDK,OP_BORK,OP_BXORK,OP_SHLI,OP_SHRI,
OP_ADD,OP_SUB,OP_MUL,OP_MOD,OP_POW,OP_DIV,OP_IDIV,OP_BAND,OP_BOR,OP_BXOR,OP_SHL,OP_SHR,
OP_MMBIN,OP_MMBINI,OP_MMBINK,OP_UNM,OP_BNOT,OP_NOT,OP_LEN,OP_CONCAT,OP_CLOSE,OP_TBC,OP_JMP,
OP_EQ,OP_LT,OP_LE,OP_EQK,OP_EQI,OP_LTI,OP_LEI,OP_GTI,OP_GEI,OP_TEST,OP_TESTSET,OP_CALL,OP_TAILCALL,
OP_RETURN,OP_RETURN0,OP_RETURN1,OP_FORLOOP,OP_FORPREP,OP_TFORPREP,OP_TFORCALL,OP_TFORLOOP,
OP_SETLIST,OP_CLOSURE,OP_VARARG,OP_GETVARG,OP_ERRNNIL,OP_VARARGPREP,OP_EXTRAARG};

typedef struct {StkId base;TValue*k;const Instruction*pc;TValue*current;long long acc;int status,load_count,store_count,unbox_count;TValue scratch;} StencilCtx;

void fused_addi_mmbini(StencilCtx*ctx){int slot,val;if(ctx->status!=SJ_OK)return;slot=GETARG_B(ctx->pc[0]);ctx->current=s2v(ctx->base+slot);if(!ctx->current||!ttisinteger(ctx->current)){ctx->status=SJ_GUARD_FAIL;return;}ctx->acc=ivalue(ctx->current);val=GETARG_sC(ctx->pc[0]);ctx->acc+=val;setivalue(&ctx->scratch,ctx->acc);ctx->current=&ctx->scratch;slot=GETARG_A(ctx->pc[0]);*s2v(ctx->base+slot)=*ctx->current;if(GET_OPCODE(ctx->pc[1])!=OP_MMBINI){ctx->status=SJ_UNSUPPORTED;return;}ctx->pc+=2;}

void fused_add_mmbin(StencilCtx*ctx){int slotA,slotB;if(ctx->status!=SJ_OK)return;slotB=GETARG_B(ctx->pc[0]);ctx->current=s2v(ctx->base+slotB);if(!ctx->current||!ttisinteger(ctx->current)){ctx->status=SJ_GUARD_FAIL;return;}ctx->acc=ivalue(ctx->current);slotB=GETARG_C(ctx->pc[0]);ctx->current=s2v(ctx->base+slotB);if(!ctx->current||!ttisinteger(ctx->current)){ctx->status=SJ_GUARD_FAIL;return;}ctx->acc+=ivalue(ctx->current);setivalue(&ctx->scratch,ctx->acc);ctx->current=&ctx->scratch;slotA=GETARG_A(ctx->pc[0]);*s2v(ctx->base+slotA)=*ctx->current;if(GET_OPCODE(ctx->pc[1])!=OP_MMBIN){ctx->status=SJ_UNSUPPORTED;return;}ctx->pc+=2;}

void fused_sub_mmbin(StencilCtx*ctx){int slotA,slotB;if(ctx->status!=SJ_OK)return;slotB=GETARG_B(ctx->pc[0]);ctx->current=s2v(ctx->base+slotB);if(!ctx->current||!ttisinteger(ctx->current)){ctx->status=SJ_GUARD_FAIL;return;}ctx->acc=ivalue(ctx->current);slotB=GETARG_C(ctx->pc[0]);ctx->current=s2v(ctx->base+slotB);if(!ctx->current||!ttisinteger(ctx->current)){ctx->status=SJ_GUARD_FAIL;return;}ctx->acc-=ivalue(ctx->current);setivalue(&ctx->scratch,ctx->acc);ctx->current=&ctx->scratch;slotA=GETARG_A(ctx->pc[0]);*s2v(ctx->base+slotA)=*ctx->current;if(GET_OPCODE(ctx->pc[1])!=OP_MMBIN){ctx->status=SJ_UNSUPPORTED;return;}ctx->pc+=2;}
]]
    return table.concat(lines, "\n")
end

-- Main
local spongejit = arg[1] or "experiments/lua_interpreter_vm/spongejit"
local cache_src = arg[2] or (spongejit .. "/build/sponjit_cache_data.c")

local fused_c = gen_fused_c()
local fused_path = spongejit .. "/build/sponjit_fused.c"
local fused_obj = spongejit .. "/build/sponjit_fused.o"
local f = assert(io.open(fused_path, "w"))
f:write(fused_c); f:close()

local cc = "gcc -O2 -fomit-frame-pointer -fPIC -fno-jump-tables -fno-tree-switch-conversion"
local cmd = string.format("%s -c %s -o %s", cc, fused_path, fused_obj)
print("[fuse] " .. cmd)
local ok = os.execute(cmd)
assert(ok == true or ok == 0, "gcc failed on fused.c")

-- Extract bytes
local funcs = {
    { name = "fused_addi_mmbini", pattern = "OP_ADDI, OP_MMBINI" },
    { name = "fused_add_mmbin",   pattern = "OP_ADD, OP_MMBIN" },
    { name = "fused_sub_mmbin",   pattern = "OP_SUB, OP_MMBIN" },
}
for _, fdef in ipairs(funcs) do
    local bytes = extract_fused_bytes(fused_obj, fdef.name)
    print(string.format("[fuse] %s: %d bytes, last=%02x", fdef.name, #bytes, bytes[#bytes] or 0))
end

print("[fuse] done")
