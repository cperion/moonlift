-- Benchmark: our SSA→C→GCC→C+P pipeline vs Moonlift VM
-- Uses: ssa_to_c.lua, GCC compile, .text extract, mmap RWX, direct call
-- Uses: Moonlift VM build_thread + runner_fn for baseline

local ffi = require("ffi")
local bit = require("bit")
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local moon = require("moonlift")
local vm = require("experiments.lua_interpreter_vm.src.init")
local const = vm.const

-- ── Step 1: Generate monolithic stencil via our pipeline ──────────────
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;" .. package.path
local SSA = require("src.ssa")
local SSAtoC = require("src.ssa_to_c")

-- MUL+ADD+JMP → absorbs 2 ops
local ops = {{op="MUL",a=2,b=0,c=1},{op="ADD",a=3,b=2,c=4},{op="JMP",sbx=-5}}
local r = SSA.compile(ops, {"lhs_i64","rhs_i64","returns_prev"})
local c = SSAtoC.generate(r, ops)
assert(c and c.n_absorbed == 2, "generate failed")
io.popen("mkdir -p build","r"):read()
local c_path = "experiments/lua_interpreter_vm/spongejit/build/bench_stencil.c"
io.open(c_path,"w"):write(c.c_code):close()
os.execute("cd experiments/lua_interpreter_vm/spongejit && gcc -O2 -fomit-frame-pointer -c build/bench_stencil.c -o build/bench_stencil.o 2>/dev/null")
assert(os.execute("test -f experiments/lua_interpreter_vm/spongejit/build/bench_stencil.o"), "gcc failed")
print(string.format("Generated stencil: absorbs %d/%d ops, %d nodes", c.n_absorbed, c.n_total, c.node_count))

-- ── Step 2: Extract .text bytes ───────────────────────────────────────
local function extract_text(o)
    local p = io.popen("objdump -s -j .text " .. o .. " 2>/dev/null", "r")
    local d = p:read("*a"); p:close()
    local bytes = {}
    for line in d:gmatch("[^\n]+") do
        if line:match("^ ") then
            for i=2,5 do
                local w = line:match("%s*(%x%x%x%x%x%x%x%x)%s", (i-2)*9 + 1)
                -- simpler: split by spaces
            end
        end
    end
    -- Parse hex dump: each data line starts with space, has 4 hex groups of 8 chars
    for line in d:gmatch("[^\n]+") do
        if line:match("^ ") then
            -- groups are 8 hex chars separated by spaces, columns 2-5
            local parts = {}
            for p in line:gmatch("%x%x%x%x%x%x%x%x") do
                parts[#parts+1] = p
            end
            for _, p in ipairs(parts) do
                for i = 1, 8, 2 do
                    bytes[#bytes+1] = tonumber(p:sub(i,i+1), 16)
                end
            end
        end
    end
    return bytes
end

local text_bytes = extract_text("experiments/lua_interpreter_vm/spongejit/build/bench_stencil.o")
assert(text_bytes and #text_bytes > 0, "no .text bytes")
print(string.format("Extracted %d .text bytes", #text_bytes))

-- ── Step 3: mmap RWX + memcpy ─────────────────────────────────────────
ffi.cdef [[
void *mmap(void *a, size_t l, int p, int f, int fd, long o);
int munmap(void *a, size_t l);
void *memcpy(void *d, const void *s, size_t n);
]]
local sz = #text_bytes
local rwx = ffi.cast("uint8_t*", ffi.C.mmap(nil, sz, 7, 0x22, -1, 0))  -- RWX=7, PRIVATE|ANON=0x22
local buf = ffi.new("uint8_t[?]", sz)
for i = 0, sz-1 do buf[i] = text_bytes[i+1] end
ffi.C.memcpy(rwx, buf, sz)
local stencil_fn = ffi.cast("void(*)(void*)", rwx)

-- ── Step 4: Moonlift VM infra ─────────────────────────────────────────
local function pack_ABC(op, a, b, c)
    return bit.bor(op, bit.lshift(a,7), bit.lshift(b,16), bit.lshift(c,24))
end
ffi.cdef [[void* moonlift_scratch_raw(int s,int e,int c);]]
local ml = (pcall(ffi.load,"./target/release/libmoonlift.so") and ffi.load("./target/release/libmoonlift.so")) or ffi.load("./target/debug/libmoonlift.so")
local sr = ml.moonlift_scratch_raw
local function S(s,e,c,t) return ffi.cast(t or "uint8_t*",sr(s,e,c)) end
ffi.cdef [[
typedef struct{void*n;uint8_t t;uint8_t m;}GC;
typedef struct{uint32_t tag;uint32_t a;uint64_t b;}V;
typedef struct{uint32_t w;}I;
typedef struct{GC g;void*c;uint64_t cl;void*co;uint64_t col;void**ch;uint64_t chl;int32_t*li;uint64_t lil;void*lv;uint64_t lvl;void*uv;uint64_t uvl;void*s;int32_t ld;int32_t ll;uint8_t np;uint8_t f;uint16_t ms;}P;
typedef struct{GC g;void*e;P*p;void**u;uint8_t nu;}L;
typedef struct{V c;uint64_t b;uint64_t t;uint64_t pc;int32_t w;int32_t tc;uint16_t rm;uint16_t ra;uint16_t rb;uint16_t rc;uint64_t rpc;uint64_t rba;V rv;}F;
typedef struct{GC g;uint8_t st;V*s;uint64_t ss;uint64_t tp;F*fr;uint64_t fc;uint64_t fcp;void*ou;void*pt;void*gl;V ev;uint8_t hm;uint8_t ah;int32_t hc;int32_t bhc;V hk;uint64_t tbc;}T;
typedef struct{void*a;V r;void*mt;}GS;
]]
local function si(v,n) v.tag=const.Tag.INTEGER; v.a=0; v.b=ffi.cast("uint64_t",n) end
local function sn(v) v.tag=const.Tag.NIL; v.a=0; v.b=0 end
function build(fill, steps)
    steps=steps or 50000; local cs=steps; local sl=40+cs
    local consts=S(sl,16,4,"V*"); si(consts[0],42); si(consts[1],99); si(consts[2],7); si(consts[3],2)
    local code=S(sl+1,ffi.sizeof("I"),cs+1,"I*")
    for i=0,cs do code[i].w=0 end
    fill(code,steps)
    code[cs].w=0  -- RETURN
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
local runner = moon.func{vm_resume=vm.vm_loop.vm_resume}[[
run(L:ptr(T),n:i32)->i32
return region->i32
entry start() emit@{vm_resume}(L,n;ok=d,yielded=y,runtime_error=e,oom=o) end
block d(n:i32)return n end block y(n:i32)return-100-n end block e(c:i32)return-200-c end block o()return-999 end end
end]]:compile()

-- ── Benchmarks ────────────────────────────────────────────────────────
local N = 50000
local RUNS = 1000
-- Program: MUL R0,R1,R2 + ADD R0,R1,R2 repeated N times
local function fill_muladd(code, steps)
    for i=0,steps-1,2 do
        code[i].w = pack_ABC(const.Op.MUL, 0, 1, 2)
        code[i+1].w = pack_ABC(const.Op.ADD, 0, 1, 2)
    end
end
-- Use code_slots = N*2 (2 ops per pair, but N pairs = N*2 ops)
local code_slots = N * 2

print(string.format("\nBenchmark: %d MUL+ADD pairs (%d total ops)\n", N, N*2))
print(string.format("%-25s  %12s", "Method", "ns/pair"))
print(string.rep("-", 40))

-- A) Moonlift VM
do
    local t,s,f = build(fill_muladd, code_slots)
    assert(runner(t,0)==1,"vm verify fail")
    runner(t,0); reset(t,s,f)
    local t0 = os.clock()
    for _=1,RUNS do runner(t,0); reset(t,s,f) end
    local ns = (os.clock()-t0)/(RUNS*N)*1e9
    print(string.format("%-25s  %8.2f ns", "Moonlift VM dispatch", ns))
end

-- B) C+P monolithic stencil (our pipeline)
-- The stencil expects a StencilCtx with instructions at ctx->pc.
-- We call it once per pair, resetting pc each time.
do
    local _,stack,_,code = build(fill_muladd, code_slots)
    -- Build a minimal Ctx matching the stencil's ABI
    ffi.cdef[[
    typedef struct { unsigned long long v; unsigned char t; } TV;
    typedef union { TV val; } SV;
    typedef unsigned int Ins;
    typedef struct { SV* base; TV* k; const Ins* pc; TV* cur; long long a; int st; int lc; int sc; int uc; TV scr; } SCtx;
    ]]
    -- Map the Moonlift Value[] to our stack. Both are 16 bytes.
    -- Moonlift Value = {uint32_t tag, uint32_t aux, uint64_t bits}
    -- Our TValue = {unsigned long long value_, unsigned char tt_}
    -- These are COMPLETELY DIFFERENT layouts! Moonlift uses tag/aux/bits;
    -- our stencil expects value_/tt_. This won't work directly.
    print(string.format("%-25s  %8s", "C+P stencil", "n/a (ABI mismatch)"))
end

print(string.rep("-", 40))
print("\nThe Moonlift VM uses Value {tag, aux, bits} (12 bytes + padding).")
print("Our stencil uses TValue {value_, tt_} (9 bytes + padding).")
print("Direct copy-patch into Moonlift VM needs ABI bridge.")

ffi.C.munmap(rwx, sz)
runner:free()
