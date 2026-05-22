-- Quick ADD path perf test: int vs float operands
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local moon = require("moonlift")
local vm = require("experiments.lua_interpreter_vm.src.init")
local const = vm.const

ffi.cdef[[void* moonlift_scratch_raw(int,int,int);]]
local lib
for _,p in ipairs({"./target/release/libmoonlift.so","./target/debug/libmoonlift.so","libmoonlift"}) do
    local ok,l=pcall(ffi.load,p)
    if ok then lib=l; break end
end
if not lib then error("libmoonlift not found") end
local S = function(slot, esz, cnt, ct)
    return ffi.cast(ct or "uint8_t*", lib.moonlift_scratch_raw(slot, esz, cnt))
end

ffi.cdef[[
typedef struct{void* next; uint8_t tt, marked;} GCHeader;
typedef struct{uint32_t tag,aux; uint64_t bits;} Value;
typedef struct{uint16_t op,a,b,c; uint8_t k; uint32_t bx; int32_t sbx;} Instr;
typedef struct{GCHeader gc; void* code; uint64_t code_len; void* constants; uint64_t constants_len; void** children; uint64_t children_len; int32_t* lineinfo; uint64_t lineinfo_len; void* locvars,upvals; uint64_t locvars_len,upvals_len; void* source; int32_t linedefined,lastlinedefined; uint8_t numparams,flag; uint16_t maxstack;} Proto;
typedef struct{void* gc_next; uint8_t tt,marked; void* env; Proto* proto; void** upvals; uint8_t nupvals;} LClosure;
typedef struct{Value closure; uint64_t base,top,pc; int32_t wanted,tailcalls; uint16_t resume_mode; uint16_t resume_a,resume_b,resume_c; uint64_t resume_pc,resume_base; Value resume_value;} Frame;
typedef struct{GCHeader gc; uint8_t status; Value* stack; uint64_t stack_size,top; Frame* frames; uint64_t frame_count,frame_cap; void* open_upvals,*protected_top,*global; Value err_value; uint8_t hookmask,allowhook; int32_t hookcount,basehookcount; Value hook; uint64_t tbc_head;} LuaThread;
typedef struct{void* allocator; Value registry; void* mainthread;} GlobalState;
]]

local function d2b(x) local u=ffi.new("union{double d;uint64_t u;}") u.d=x; return u.u end
local STEPS=5000; local RUNS=200

local function test_add(name, r0tag, r0val, r1tag, r1val)
    local ncode = STEPS*2 + 1
    local code = S(100, 20, ncode, "Instr*")
    for i=0,STEPS-1 do
        local pc=i*2
        code[pc].op=const.Op.ADD; code[pc].a=2; code[pc].b=0; code[pc].c=1; code[pc].k=0; code[pc].bx=0; code[pc].sbx=0
        code[pc+1].op=const.Op.MMBIN; code[pc+1].a=0; code[pc+1].b=const.TM.ADD; code[pc+1].c=0; code[pc+1].k=0; code[pc+1].bx=0; code[pc+1].sbx=0
    end
    code[ncode-1].op=const.Op.RETURN; code[ncode-1].a=0; code[ncode-1].b=2; code[ncode-1].k=0; code[ncode-1].bx=0; code[ncode-1].sbx=0

    local proto=S(101,1,256,"Proto*")
    proto.code=ffi.cast("void*",code); proto.code_len=ncode; proto.maxstack=4; proto.numparams=0; proto.flag=0
    proto.constants=S(102,16,0,"Value*"); proto.constants_len=0
    proto.children_len=0; proto.lineinfo_len=0; proto.locvars_len=0; proto.upvals_len=0
    proto.linedefined=-1; proto.lastlinedefined=-1

    local closure=S(103,1,64,"LClosure*")
    closure.proto=proto; closure.env=nil; closure.nupvals=0

    local stack=S(104,16,64,"Value*")
    for i=0,63 do stack[i].tag=const.Tag.NIL; stack[i].aux=0; stack[i].bits=0 end
    stack[0].tag=const.Tag.LCLOSURE; stack[0].aux=0; stack[0].bits=ffi.cast("uint64_t",closure)
    stack[1].tag=r0tag; stack[1].aux=0; stack[1].bits=r0val
    stack[2].tag=r1tag; stack[2].aux=0; stack[2].bits=r1val

    local frames=S(105,1,512,"Frame*")
    for i=0,7 do
        frames[i].closure.tag=const.Tag.LCLOSURE; frames[i].closure.aux=0; frames[i].closure.bits=ffi.cast("uint64_t",closure)
        frames[i].base=1; frames[i].top=3; frames[i].pc=0; frames[i].wanted=1; frames[i].tailcalls=0
        frames[i].resume_mode=const.Resume.NORMAL
    end

    local gstate=S(106,1,64,"GlobalState*")
    local thread=S(107,1,256,"LuaThread*")
    thread.status=const.Status.OK; thread.stack=stack; thread.stack_size=64; thread.top=3
    thread.frames=frames; thread.frame_count=1; thread.frame_cap=8; thread.global=gstate; thread.tbc_head=0

    local function reset()
        thread.status=const.Status.OK; thread.top=3; thread.frame_count=1
        frames[0].base=1; frames[0].top=3; frames[0].pc=0; frames[0].wanted=1
        stack[1].tag=r0tag; stack[1].bits=r0val
        stack[2].tag=r1tag; stack[2].bits=r1val
    end

    local vr=vm.vm_loop.vm_resume
    local runner=moon.func{vr=vr}[[
    run(L:ptr(LuaThread))->i32
    return region->i32
    entry start() emit @{vr}(L,0;ok=d,yielded=y,runtime_error=e,oom=o) end
    block d(n:i32)return n end block y(n:i32)return-100-n end block e(c:i32)return-200-c end block o()return-999 end
    end
]]:compile()

    runner(thread); reset()
    local t0=os.clock()
    for _=1,RUNS do reset(); runner(thread) end
    local e=(os.clock()-t0)
    runner:free()
    return (e/RUNS)*1e9, STEPS/e
end

print(string.format("%-24s %12s %12s", "path", "ns/op", "Mop/s"))
print(string.rep("-",50))
local ns_f, mops_f = test_add("NUM+NUM (float)", const.Tag.NUM, d2b(42.0), const.Tag.NUM, d2b(99.0))
local ns_i, mops_i = test_add("INT+INT (int)", const.Tag.INTEGER, 42, const.Tag.INTEGER, 99)
local ns_m, mops_m = test_add("INT+NUM (mixed)", const.Tag.INTEGER, 42, const.Tag.NUM, d2b(99.0))
print(string.format("%-24s %11.2f ns %11.1f", "NUM+NUM (float)", ns_f, mops_f))
print(string.format("%-24s %11.2f ns %11.1f", "INT+INT (int)", ns_i, mops_i))
print(string.format("%-24s %11.2f ns %11.1f", "INT+NUM (mixed)", ns_m, mops_m))
print(string.format("%-24s %11.2fx slower", "float vs int", ns_f/ns_i))
