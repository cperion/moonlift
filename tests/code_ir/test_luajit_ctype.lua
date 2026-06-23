package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")

local T = pvm.context()
Schema(T)

local Core = T.MoonCore
local Ty = T.MoonType
local Code = T.MoonCode
local Back = T.MoonBack
local LJ = T.MoonLuaJIT
local CType = require("moonlift.luajit_ctype")(T)

local function cls(value) return pvm.classof(value) end

assert(CType.scalar_spelling(Back.BackI32) == "int32_t")
assert(CType.scalar_spelling(Back.BackIndex) == "intptr_t")
assert(CType.scalar_ctype(Back.BackI32) == LJ.LJCTypeScalar(Back.BackI32, "int32_t"))
assert(CType.scalar_register_rep(Back.BackI32) == LJ.LJRegTraceInt32(32, Code.CodeSigned))
assert(CType.scalar_register_rep(Back.BackU32) == LJ.LJRegTraceInt32(32, Code.CodeUnsigned))
assert(CType.scalar_register_rep(Back.BackF64) == LJ.LJRegLuaNumber)
assert(CType.scalar_register_rep(Back.BackBool) == LJ.LJRegLuaBoolean)
assert(cls(CType.scalar_register_rep(Back.BackI64)) == LJ.LJRegCData)
assert(cls(CType.scalar_register_rep(Back.BackPtr)) == LJ.LJRegCData)

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local u64 = Code.CodeTyInt(64, Code.CodeUnsigned)
local f64 = Code.CodeTyFloat(64)

local p_i32 = CType.physical_type(i32, {})
assert(p_i32.register == LJ.LJRegTraceInt32(32, Code.CodeSigned))
assert(p_i32.storage == LJ.LJCTypeScalar(Back.BackI32, "int32_t"))
assert(p_i32.abi == p_i32.storage)

local p_u64 = CType.physical_type(u64, {})
assert(cls(p_u64.register) == LJ.LJRegCData)
assert(p_u64.storage == LJ.LJCTypeScalar(Back.BackU64, "uint64_t"))

local p_f64 = CType.physical_type(f64, {})
assert(p_f64.register == LJ.LJRegLuaNumber)
assert(CType.ctype_spelling(p_f64.abi, {}) == "double")

local ptr = CType.physical_type(Code.CodeTyDataPtr(i32), {})
assert(cls(ptr.register) == LJ.LJRegCData)
assert(cls(ptr.storage) == LJ.LJCTypePointer)
assert(ptr.storage.pointee == p_i32.storage)
assert(CType.ctype_spelling(ptr.storage, {}) == "int32_t*")

local ctx = {}
local sig = Code.CodeSig(Code.CodeSigId("sig:add"), { i32, i32 }, { i32 })
ctx.code_sigs = { [sig.id.text] = sig }
local codeptr = CType.physical_type(Code.CodeTyCodePtr(sig.id), ctx)
assert(cls(codeptr.storage) == LJ.LJCTypeFuncPtr)
assert(ctx.lj_sigs["sig:add"] ~= nil)
assert(ctx.lj_sigs["sig:add"].c_sig == "int32_t (*)(int32_t, int32_t)")

local view = CType.physical_type(Code.CodeTyView(i32), ctx)
assert(cls(view.register) == LJ.LJRegTuple)
assert(#view.register.fields == 3)
assert(cls(view.storage) == LJ.LJCTypeNamed)
assert(ctx.lj_cdefs[view.storage.id.text] ~= nil)
assert(ctx.lj_cdefs[view.storage.id.text].fields[1].name == "data")

local slice = CType.physical_type(Code.CodeTySlice(i32), ctx)
assert(cls(slice.register) == LJ.LJRegTuple)
assert(#slice.register.fields == 2)
assert(ctx.lj_cdefs[slice.storage.id.text] ~= nil)

local closure = CType.physical_type(Code.CodeTyClosure(sig.id), ctx)
assert(cls(closure.register) == LJ.LJRegCData)
assert(ctx.lj_cdefs[closure.storage.id.text].fields[1].name == "fn")

local named = CType.physical_type(Code.CodeTyNamed("Demo", "Pair", Ty.TNamed(Ty.TypeRefGlobal("Demo", "Pair"))), {})
assert(cls(named.storage) == LJ.LJCTypeNamed)
assert(named.storage.spelling == "Demo_Pair")

local imported = CType.physical_type(Code.CodeTyImportedC(T.MoonC.CTypeId("host", "uint128_t")), {})
assert(imported.storage.spelling == "uint128_t")

local moon_ptr = CType.type_to_physical(Ty.TPtr(Ty.TScalar(Core.ScalarI32)), {})
assert(cls(moon_ptr.storage) == LJ.LJCTypePointer)

io.write("moonlift luajit_ctype ok\n")
