-- Benchmark: multi-opcode absorption (MUL+ADDI fused vs sequential)
local ffi = require("ffi")
local bit = require("bit")
package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path
local lalin = require("lalin")
local vm = require("experiments.lua_interpreter_vm.src.init")
local const = vm.const

-- Extract .text bytes from .o
local function extract_text(o)
    local p = io.popen("objdump -d -j .text " .. o .. " 2>/dev/null", "r")
    local d = p:read("*a"); p:close()
    local b = {}
    for l in d:gmatch("[^\n]+") do
        local h = l:match("^%s*[0-9a-f]+:%s+([0-9a-f ]+)%s+")
        if h then for x in h:gmatch("[0-9a-f][0-9a-f]") do b[#b+1] = tonumber(x, 16) end end
    end
    return b
end

-- mmap RWX, memcpy code
local function mmap_rwx(bytes)
    ffi.cdef [[
    void *mmap(void *a, size_t l, int p, int f, int fd, long o);
    int munmap(void *a, size_t l);
    void *memcpy(void *d, const void *s, size_t n);
    ]]
    local sz = #bytes
    local mem = ffi.cast("uint8_t*",
        ffi.C.mmap(nil, sz, 7, 0x22, -1, 0))  -- RWX = 7, MAP_PRIVATE|ANON = 0x22
    local buf = ffi.new("uint8_t[?]", sz)
    for i = 0, sz - 1 do buf[i] = bytes[i + 1] end
    ffi.C.memcpy(mem, buf, sz)
    return mem
end

ffi.cdef [[
typedef struct { uint32_t tag; uint32_t aux; uint64_t bits; } Value;
typedef struct { uint32_t word; } Instr;
typedef struct { Value *s; Instr *c; uint64_t pc; uint64_t b; uint64_t t; int32_t st; } Ctx;
]]

-- Compile the C stencil with both functions
local c_src = [[
#include <stdint.h>
typedef struct { uint32_t tag; uint32_t aux; uint64_t bits; } Value;
typedef struct { uint32_t word; } Instr;
typedef struct { Value *s; Instr *c; uint64_t pc; uint64_t b; uint64_t t; int32_t st; } Ctx;

// Sequential dispatch (baseline: one op at a time)
int seq_run(Ctx *ctx) {
    for (;;) {
        uint32_t w = ctx->c[ctx->pc].word;
        uint32_t op = w & 127;
        if (op == 0) return 0;
        if (op == 1) {
            ctx->s[ctx->b + ((w>>7)&255)].tag = 8; ctx->s[ctx->b + ((w>>7)&255)].aux = 0;
            ctx->s[ctx->b + ((w>>7)&255)].bits = (uint64_t)(int64_t)((int32_t)((w>>15)&131071)-65535);
            ctx->pc++; continue;
        }
        if (op == 34) { // ADD
            uint32_t d=ctx->b+((w>>7)&255), l=ctx->b+((w>>16)&255), r_i=ctx->b+((w>>24)&255);
            if (ctx->s[l].tag==8 && ctx->s[r_i].tag==8) {
                ctx->s[d].tag=8; ctx->s[d].bits = (uint64_t)((int64_t)ctx->s[l].bits + (int64_t)ctx->s[r_i].bits);
            }
            ctx->pc++; continue;
        }
        if (op == 36) { // MUL
            uint32_t d=ctx->b+((w>>7)&255), l=ctx->b+((w>>16)&255), r_i=ctx->b+((w>>24)&255);
            if (ctx->s[l].tag==8 && ctx->s[r_i].tag==8) {
                int64_t r = (int64_t)ctx->s[l].bits * (int64_t)ctx->s[r_i].bits;
                ctx->s[d].tag=8; ctx->s[d].bits = (uint64_t)r;
            }
            ctx->pc++; continue;
        }
        ctx->pc++; continue;
    }
}

// Fused: absorbs MUL+ADD as one unit
int fused_run(Ctx *ctx) {
    for (;;) {
        uint32_t w = ctx->c[ctx->pc].word;
        uint32_t op = w & 127;
        if (op == 0) return 0;
        if (op == 1) {
            ctx->s[ctx->b + ((w>>7)&255)].tag = 8; ctx->s[ctx->b + ((w>>7)&255)].bits = (uint64_t)(int64_t)((int32_t)((w>>15)&131071)-65535);
            ctx->pc++; continue;
        }
        // Fuse: MUL + ADD
        if (op == 36) {
            uint32_t w2 = ctx->c[ctx->pc + 1].word;
            if ((w2 & 127) == 34) {
                uint32_t md=ctx->b+((w>>7)&255), ml=ctx->b+((w>>16)&255), mr_i=ctx->b+((w>>24)&255);
                uint32_t ad=ctx->b+((w2>>7)&255), al=ctx->b+((w2>>16)&255), ar_i=ctx->b+((w2>>24)&255);
                if (ctx->s[ml].tag==8 && ctx->s[mr_i].tag==8 && ctx->s[al].tag==8 && ctx->s[ar_i].tag==8) {
                    int64_t mr = (int64_t)ctx->s[ml].bits * (int64_t)ctx->s[mr_i].bits;
                    ctx->s[md].tag=8; ctx->s[md].bits = (uint64_t)mr;
                    int64_t ar = (int64_t)ctx->s[al].bits + (int64_t)ctx->s[ar_i].bits;
                    ctx->s[ad].tag=8; ctx->s[ad].bits = (uint64_t)ar;
                    ctx->pc += 2;
                    continue;
                }
            }
            ctx->pc++; continue;
        }
        if (op == 34) { ctx->pc++; continue; }
        ctx->pc++; continue;
    }
}
]]
local f = io.open("/tmp/stencil_fusion.c", "w"); f:write(c_src); f:close()
os.execute("gcc -O2 -fomit-frame-pointer -c /tmp/stencil_fusion.c -o /tmp/stencil_fusion.o 2>&1")
assert(os.execute("test -f /tmp/stencil_fusion.o"), "compile failed")

local seq_bytes = extract_text("/tmp/stencil_fusion.o")
print(string.format("seq: %d bytes", #seq_bytes))

-- Actually we need to extract each function separately
local function extract_fn(o, fn)
    local p = io.popen("objdump -d -j .text " .. o .. " 2>/dev/null | sed -n '/<"..fn..">:/,/^$/p'", "r")
    local d = p:read("*a"); p:close()
    local b = {}
    local in_fn = false
    for l in d:gmatch("[^\n]+") do
        if l:match("<" .. fn .. ">:") then in_fn = true end
        if in_fn then
            if l:match("^$") then break end
            local h = l:match("^%s*[0-9a-f]+:%s+([0-9a-f ]+)%s+")
            if h then for x in h:gmatch("[0-9a-f][0-9a-f]") do b[#b+1] = tonumber(x, 16) end end
        end
    end
    return b
end

-- Use objdump per function
local function get_fn_bytes(fn_name)
    local d = io.popen("objdump -d /tmp/stencil_fusion.o 2>/dev/null", "r"):read("*a")
    local b = {}
    local capturing = false
    for l in d:gmatch("[^\n]+") do
        if l:match("<" .. fn_name .. ">:") then capturing = true end
        if capturing then
            if l:match("^$") or (capturing and l:match("^[0-9a-f]+ <[^" .. fn_name .. "]")) then
                if capturing and not l:match("<" .. fn_name .. ">") then break end
            end
            local h = l:match("^%s*[0-9a-f]+:%s+([0-9a-f ]+)%s+")
            if h then for x in h:gmatch("[0-9a-f][0-9a-f]") do b[#b+1]=tonumber(x,16) end end
        end
    end
    return b
end

local seq_bytes = get_fn_bytes("seq_run")
local fused_bytes = get_fn_bytes("fused_run")
print(string.format("seq_run: %d bytes, fused_run: %d bytes", #seq_bytes, #fused_bytes))

-- mmap both
local seq_mem = mmap_rwx(seq_bytes)
local fused_mem = mmap_rwx(fused_bytes)
local seq_fn = ffi.cast("int(*)(Ctx*)", seq_mem)
local fused_fn = ffi.cast("int(*)(Ctx*)", fused_mem)

-- VM infra
local function pack_ABC(op, a, b, c) return bit.bor(op, bit.lshift(a,7), bit.lshift(b,16), bit.lshift(c,24)) end
local function pack_AsBx(op, a, sbx) return bit.bor(op, bit.lshift(a,7), bit.lshift(sbx+65535,15)) end
local function set_ABC(i, op, a, b, c) i.word = pack_ABC(op, a, b, c) end
local function set_AsBx(i, op, a, sbx) i.word = pack_AsBx(op, a, sbx) end
ffi.cdef [[void* lalin_scratch_raw(int s, int e, int c);]]
local ml = (pcall(ffi.load,"./target/release/liblalin.so") and ffi.load("./target/release/liblalin.so")) or ffi.load("./target/debug/liblalin.so")
local sr = ml.lalin_scratch_raw
local function S(s,e,c,t) return ffi.cast(t or "uint8_t*", sr(s,e,c)) end
ffi.cdef [[
typedef struct{void*n;uint8_t t;uint8_t m;} GC;
typedef struct{uint32_t tag;uint32_t a;uint64_t b;} V;
typedef struct{uint32_t w;} I;
typedef struct{GC g;void*c;uint64_t cl;void*co;uint64_t col;void**ch;uint64_t chl;int32_t*li;uint64_t lil;void*lv;uint64_t lvl;void*uv;uint64_t uvl;void*s;int32_t ld;int32_t ll;uint8_t np;uint8_t f;uint16_t ms;} P;
typedef struct{GC g;void*e;P*p;void**u;uint8_t nu;} L;
typedef struct{V c;uint64_t b;uint64_t t;uint64_t pc;int32_t w;int32_t tc;uint16_t rm;uint16_t ra;uint16_t rb;uint16_t rc;uint64_t rpc;uint64_t rba;V rv;} F;
typedef struct{GC g;uint8_t st;V*s;uint64_t ss;uint64_t tp;F*fr;uint64_t fc;uint64_t fcp;void*ou;void*pt;void*gl;V ev;uint8_t hm;uint8_t ah;int32_t hc;int32_t bhc;V hk;uint64_t tbc;} T;
typedef struct{void*a;V r;void*mt;} GS;
]]
local function si(v, n) v.tag=const.Tag.INTEGER; v.a=0; v.b=ffi.cast("uint64_t",n) end
local function sn(v) v.tag=const.Tag.NIL; v.a=0; v.b=0 end

function build(fill, steps)
    steps=steps or 50000; local cs=steps; local sl=40+cs
    local consts=S(sl,16,4,"V*"); si(consts[0],42); si(consts[1],99); si(consts[2],7); si(consts[3],2)
    local code=S(sl+1,ffi.sizeof("I"),cs+1,"I*")
    for i=0,cs do set_ABC(code[i],0,0,0,0) end
    fill(code,steps)
    set_ABC(code[cs],0,0,2,0)
    local proto=S(sl+2,1,256,"P*"); proto.c=ffi.cast("void*",code); proto.cl=cs+1
    proto.co=ffi.cast("void*",consts); proto.col=4; proto.ms=8
    local closure=S(sl+3,1,64,"L*"); closure.p=proto; closure.nu=0
    local stack=S(sl+4,16,64,"V*")
    for i=0,63 do sn(stack[i]) end
    stack[0].tag=const.Tag.LCLOSURE; stack[0].b=ffi.cast("uint64_t",closure)
    si(stack[1],42); si(stack[2],99); si(stack[3],7)
    local frames=S(sl+5,1,512,"F*")
    frames[0].c.tag=const.Tag.LCLOSURE; frames[0].c.b=ffi.cast("uint64_t",closure)
    frames[0].b=1; frames[0].t=3; frames[0].pc=0; frames[0].w=1; frames[0].rm=const.Resume.NORMAL
    local gs=S(sl+6,1,64,"GS*")
    local thread=S(sl+7,1,256,"T*")
    thread.st=const.Status.OK; thread.s=stack; thread.ss=64; thread.tp=3
    thread.fr=frames; thread.fc=1; thread.fcp=8; thread.gl=gs
    return thread, stack, frames, code
end
local function reset(t,s,f)
    t.st=const.Status.OK; t.tp=3; t.fc=1; f[0].b=1; f[0].t=3; f[0].pc=0; f[0].w=1
    f[0].rm=const.Resume.NORMAL; si(s[1],42); si(s[2],99); si(s[3],7)
end

local runner = lalin.func{vm_resume=vm.vm_loop.vm_resume}[[
run(L:ptr(T),n:i32): i32
return region: i32
entry start() emit@{vm_resume}(L,n;ok=d,yielded=y,runtime_error=e,oom=o) end
block d(n:i32)return n end block y(n:i32)return-100-n end block e(c:i32)return-200-c end block o()return-999 end end
end]]:compile()

-- Benchmark: MUL+ADD pairs
-- VM: MUL at pc, ADD at pc+1
-- C+P seq: same sequential dispatch
-- C+P fused: MUL+ADD absorbed as one
local STEPS = 50000
local RUNS = 500

local function bench_vm(fill)
    local t,s,f = build(fill, STEPS)
    assert(runner(t,0)==1)
    runner(t,0); reset(t,s,f)
    local t0 = os.clock()
    for _=1,RUNS do runner(t,0); reset(t,s,f) end
    return (os.clock()-t0)/(RUNS*STEPS)*1e9
end

local function bench_cap(fn, fill)
    local _,s,_, code = build(fill, STEPS)
    local ctx = ffi.new("Ctx")
    ctx.s=s; ctx.c=code; ctx.pc=0; ctx.b=1; ctx.t=3; ctx.st=0
    si(s[1],42); si(s[2],99); si(s[3],7)
    fn(ctx) -- warmup
    ctx.pc=0; si(s[1],42); si(s[2],99); si(s[3],7)
    local t0=os.clock()
    for _=1,RUNS do fn(ctx); ctx.pc=0; si(s[1],42); si(s[2],99); si(s[3],7) end
    return (os.clock()-t0)/(RUNS*STEPS)*1e9
end

-- Program: pairs of MUL R0,R1,R2 + ADD R0,R1,R2
local function fill_mul_add_pairs(c, s)
    for i=0,s-1 do
        set_ABC(c[i*2], const.Op.MUL, 0, 1, 2)  -- MUL R0, R1, R2
        set_ABC(c[i*2+1], const.Op.ADD, 0, 1, 2) -- ADD R0, R1, R2
    end
end
local code_slots = STEPS * 2

-- Build for C+P (uses a code array with the right fill)
local function fill_both(c, s) fill_mul_add_pairs(c, s) end

print(string.format("\n=== MUL+ADD PAIRS (2 ops each) ==="))
print(string.format("STEPS=%d pairs  RUNS=%d\n", STEPS, RUNS))
print(string.format("%-20s  %12s", "BENCHMARK", "ns/op"))
print(string.rep("-", 35))

-- Build with code_slots
do
    local t,s,f = build(function(c,steps)
        for i=0,steps-1 do set_ABC(c[i*2],const.Op.MUL,0,1,2); set_ABC(c[i*2+1],const.Op.ADD,0,1,2) end
    end, STEPS*2)
    assert(runner(t,0)==1)
    runner(t,0); reset(t,s,f)
    local t0=os.clock()
    for _=1,RUNS do runner(t,0); reset(t,s,f) end
    print(string.format("%-20s  %8.2f ns", "VM (Cranelift)", (os.clock()-t0)/(RUNS*STEPS*2)*1e9))
end

-- C+P sequential (one op at a time)
do
    local _,s,_,code = build(function(c,steps)
        for i=0,steps-1 do set_ABC(c[i*2],const.Op.MUL,0,1,2); set_ABC(c[i*2+1],const.Op.ADD,0,1,2) end
    end, STEPS*2)
    local ctx = ffi.new("Ctx"); ctx.s=s; ctx.c=code; ctx.pc=0; ctx.b=1; ctx.t=3; ctx.st=0
    si(s[1],42); si(s[2],99); si(s[3],7)
    seq_fn(ctx); ctx.pc=0; si(s[1],42); si(s[2],99); si(s[3],7)
    local t0=os.clock()
    for _=1,RUNS do seq_fn(ctx); ctx.pc=0; si(s[1],42); si(s[2],99); si(s[3],7) end
    print(string.format("%-20s  %8.2f ns", "C+P sequential", (os.clock()-t0)/(RUNS*STEPS*2)*1e9))
end

-- C+P fused (absorbs MUL+ADD as one)
do
    local _,s,_,code = build(function(c,steps)
        for i=0,steps-1 do set_ABC(c[i*2],const.Op.MUL,0,1,2); set_ABC(c[i*2+1],const.Op.ADD,0,1,2) end
    end, STEPS*2)
    local ctx = ffi.new("Ctx"); ctx.s=s; ctx.c=code; ctx.pc=0; ctx.b=1; ctx.t=3; ctx.st=0
    si(s[1],42); si(s[2],99); si(s[3],7)
    fused_fn(ctx); ctx.pc=0; si(s[1],42); si(s[2],99); si(s[3],7)
    local t0=os.clock()
    for _=1,RUNS do fused_fn(ctx); ctx.pc=0; si(s[1],42); si(s[2],99); si(s[3],7) end
    print(string.format("%-20s  %8.2f ns", "C+P fused (2 ops)", (os.clock()-t0)/(RUNS*STEPS)*1e9))
end

print(string.rep("-", 35))
print("fused ns/op = per PAIR (2 ops), others = per op")

ffi.C.munmap(seq_mem, #seq_bytes)
ffi.C.munmap(fused_mem, #fused_bytes)
runner:free()
