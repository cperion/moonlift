package.path = './?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;' .. package.path

local ffi=require('ffi')
local pvm=require('moonlift.pvm')
local T=pvm.context(); require('moonlift.schema').Define(T)
local BackValidate=require('moonlift.back_validate').Define(T)
local BackJit=require('moonlift.back_jit').Define(T)
local BackCommandBinary=require('moonlift.back_command_binary').Define(T)
local C=T.MoonCore; local B=T.MoonBack
local function sid(s) return B.BackSigId(s) end
local function fid(s) return B.BackFuncId(s) end
local function bid(s) return B.BackBlockId(s) end
local function vid(s) return B.BackValId(s) end
local i32=B.BackI32; local ptr=B.BackPtr; local vec=B.BackVec(i32,4); local vshape=B.BackShapeVec(vec)
local function mem(id, mode) return B.BackMemoryInfo(B.BackAccessId(id), B.BackAlignKnown(4), B.BackDerefBytes(16,'vector smoke'), B.BackNonTrapping('test buffer'), B.BackCanMove('test buffer'), mode) end
local function addr(base, off) return B.BackAddress(B.BackAddrValue(base), off, B.BackProvArg(base.text), B.BackPtrInBounds('test buffer')) end
local sig=sid('sig:vec_add1_store'); local fn=fid('vec_add1_store'); local entry=bid('entry')
local dst=vid('dst'); local src=vid('src'); local z=vid('z'); local loaded=vid('loaded'); local one=vid('one'); local ones=vid('ones'); local added=vid('added'); local first=vid('first')
local program=B.BackProgram({
 B.CmdCreateSig(sig,{ptr,ptr},{i32}),
 B.CmdDeclareFunc(C.VisibilityExport,fn,sig),
 B.CmdBeginFunc(fn),
 B.CmdCreateBlock(entry),
 B.CmdSwitchToBlock(entry),
 B.CmdBindEntryParams(entry,{dst,src}),
 B.CmdConst(z,B.BackIndex,B.BackLitInt('0')),
 B.CmdLoadInfo(loaded,vshape,addr(src,z),mem('vec:load',B.BackAccessRead)),
 B.CmdConst(one,i32,B.BackLitInt('1')),
 B.CmdVecSplat(ones,vec,one),
 B.CmdVecBinary(added,B.BackVecIntAdd,vec,loaded,ones),
 B.CmdStoreInfo(vshape,addr(dst,z),added,mem('vec:store',B.BackAccessWrite)),
 B.CmdVecExtractLane(first,i32,added,0),
 B.CmdReturnValue(first),
 B.CmdSealBlock(entry),
 B.CmdFinishFunc(fn),
 B.CmdFinalizeModule,
})
local report=BackValidate.validate(program); assert(#report.issues==0)
local wire=BackCommandBinary.encode(program); assert(type(wire)=='string' and #wire>32,'binary encoder produced wire payload')
local jit=BackJit.jit(); local artifact=jit:compile(program); local cfn=ffi.cast('int32_t (*)(int32_t*, const int32_t*)', artifact:getpointer(fn))
local xs=ffi.new('int32_t[4]',{4,5,6,7}); local ys=ffi.new('int32_t[4]',{0,0,0,0})
assert(cfn(ys,xs)==5); for i=0,3 do assert(ys[i]==xs[i]+1,'bad vector store lane '..i) end
artifact:free()
io.write('moonlift back_vector_jit ok\n')
