package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local T = asdl.context()
Schema(T)
require("lalin.residual_native")(T)

local Back = T.LalinBack
local Code = T.LalinCode
local Core = T.LalinCore
local ffi = require("ffi")
local LJ = T.LalinLuaJIT
local Residual = T.LalinResidual
local Stencil = T.LalinStencil
local Value = T.LalinValue

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local i32_c = LJ.LJCTypeScalar(Back.BackI32, "int32_t")
local ptr_i32_c = LJ.LJCTypePointer(i32_c, false)
local phys_i32 = LJ.LJPhysicalType(i32, LJ.LJRegCData(i32_c), i32_c, i32_c)
local phys_ptr_i32 = LJ.LJPhysicalType(Code.CodeTyDataPtr(i32), LJ.LJRegCData(ptr_i32_c), ptr_i32_c, ptr_i32_c)

local init = Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt("0")))
local producer = Stencil.StencilProducer(nil, Stencil.StencilProduceRange1D(Code.CodeTyIndex, nil, nil, 1, Stencil.StencilProducerForward))
local descriptor = Stencil.StencilDescriptor(
    producer,
    {
        Stencil.StencilAccess("xs", Stencil.StencilAccessRead, i32, Stencil.StencilLayoutContiguous(1)),
        Stencil.StencilAccess("out", Stencil.StencilAccessWrite, i32, Stencil.StencilLayoutScalar(init)),
    },
    Stencil.StencilBodyPoint(Stencil.StencilPointInput(Stencil.StencilAccessRef("xs"))),
    Stencil.StencilSinkStore(Stencil.StencilAccessRef("out"), Stencil.StencilStoreElementwise)
)

local compiler = Stencil.StencilCompilerPolicy(
    Stencil.StencilCompilerGcc,
    Stencil.StencilOptO3,
    Stencil.StencilMachineNative,
    {}
)
local instance = Stencil.StencilInstance(
    Stencil.StencilInstanceId("stencil:store_i32"),
    descriptor,
    Stencil.StencilScheduleScalar(compiler),
    Stencil.StencilAbi({ Code.CodeTyDataPtr(i32), i32, i32, i32 }, i32),
    {}
)
local artifact = Stencil.StencilArtifact(
    instance,
    Stencil.StencilProviderC,
    Stencil.StencilSymbolId("ml_stencil_store_i32"),
    "int32_t ml_stencil_store_i32(int32_t const *, int32_t, int32_t, int32_t);",
    Stencil.StencilArtifactFingerprint("residual:test"),
    nil,
    {},
    {}
)

local selection = instance:select_patch_template()
assert(asdl.classof(selection) == Residual.StencilPatchTemplateSelected)
assert(selection.family.spine == Residual.StencilSpineStoreNRange1D)
assert(#selection.runtime_params == #instance.abi.params)

local storage = artifact:select_stencil_storage()
assert(asdl.classof(storage) == Residual.StencilStoredExactMC)
local materialized = assert(storage:materialize_stencil())
assert(asdl.classof(materialized) == Residual.MaterializedExactStencil)

local sig_id = LJ.LJFuncSigId("sig:store")
local sig = LJ.LJFuncSig(sig_id, { phys_ptr_i32 }, phys_i32, "int32_t (*)(int32_t const *)")
local xs = LJ.LJValueId("xs")
local machine_id = LJ.LJMachineId("machine:stencil")
local call = LJ.LJMachineStencilCall(
    artifact,
    {
        LJ.LJExprValue(xs),
        LJ.LJExprLiteral(Core.LitInt("0"), phys_i32),
        LJ.LJExprLiteral(Core.LitInt("16"), phys_i32),
        LJ.LJExprLiteral(Core.LitInt("0"), phys_i32),
    },
    phys_i32
)
local machine = LJ.LJMachine(machine_id, call, phys_i32, LJ.LJStateNone, LJ.LJTraceHot)
local func = LJ.LJFunc(
    LJ.LJFuncId("fn:store"),
    nil,
    "store",
    sig_id,
    { LJ.LJParam(xs, "xs", phys_ptr_i32) },
    {},
    { machine },
    LJ.LJBodyMachine(machine_id, LJ.LJTerminalFirst(nil)),
    LJ.LJTraceHot
)
local module = LJ.LJModule(nil, { func }, { sig }, {}, {}, {})
local plan = module:select_residual_luajit_module(
    Residual.ResidualLuaJITModuleRequest(module, Residual.ResidualTargetNativeTcc, Residual.ResidualStorageAllowExactOrPatchTemplate)
)

assert(#plan.functions == 1)
assert(asdl.classof(plan.functions[1]) == Residual.ResidualFunctionC)
assert(#plan.c_units == 1)
assert(plan.c_units[1].source:find("ml_stencil_store_i32", 1, true) ~= nil)
assert(plan.c_units[1].wrappers[1].wrapper_symbol:find("__lalin_native_fn_store", 1, true) ~= nil)
assert(plan.c_units[1].host_symbols[1].name == "ml_stencil_store_i32")

local target = LJ.LJMCTarget(
    ffi.arch,
    ffi.os,
    "c",
    ffi.abi("64bit") and 64 or 32,
    ffi.abi("le") and "little" or "big"
)

if ffi.arch == "x64" and ffi.abi("le") then
    local imm_template = Residual.StencilPatchTemplate(
        Stencil.StencilSymbolId("patched_return_i32"),
        selection.family,
        target,
        "int (*)(void)",
        string.char(0xB8, 0, 0, 0, 0, 0xC3),
        {
            Residual.PatchImm32(Residual.StencilPatchHoleId("imm32:return"), 1, true, Residual.PatchEndianLittle),
        }
    )
    local imm_view = Residual.StencilPatchTemplateSelected(
        instance,
        selection.family,
        { Residual.StencilPatchCoordImmediateI32(77) },
        instance.abi.params
    )
    local imm_plan = assert(imm_view:select_expansion_plan(target, imm_template))
    local imm_installed = assert(imm_plan:install_patched_stencil({
        install = { rwx = false },
    }))
    assert(imm_installed.fn() == 77, "patched imm32 template should return coordinate value")

    local callback = ffi.cast("int (*)(void)", function()
        return 123
    end)
    local ptr_template = Residual.StencilPatchTemplate(
        Stencil.StencilSymbolId("patched_call_ptr"),
        selection.family,
        target,
        "int (*)(void)",
        string.char(0x48, 0x83, 0xEC, 0x08, 0x48, 0xB8, 0, 0, 0, 0, 0, 0, 0, 0, 0xFF, 0xD0, 0x48, 0x83, 0xC4, 0x08, 0xC3),
        {
            Residual.PatchPtr(Residual.StencilPatchHoleId("ptr:callback"), 6, 64, Residual.PatchEndianLittle),
        }
    )
    local ptr_view = Residual.StencilPatchTemplateSelected(
        instance,
        selection.family,
        { Residual.StencilPatchCoordSymbolAddress(Stencil.StencilSymbolId("callback")) },
        instance.abi.params
    )
    local ptr_plan = assert(ptr_view:select_expansion_plan(target, ptr_template))
    local ptr_installed = assert(ptr_plan:install_patched_stencil({
        install = { rwx = false },
        symbols = { callback = callback },
    }))
    assert(ptr_installed.fn() == 123, "patched pointer template should call supplied symbol")
    callback:free()
end

io.write("lalin schema_residual ok\n")
