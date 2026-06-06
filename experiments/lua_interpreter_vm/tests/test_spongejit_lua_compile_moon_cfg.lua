#!/usr/bin/env luajit
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;./experiments/lua_interpreter_vm/spongejit/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local moon = require("moonlift")
local C = require("lua_compile")
local Validate = require("lua_compile.moon_cfg_validate")
local Emit = require("lua_compile.moon_cfg_emit")
local ContractKey = require("lua_compile.compile_contract_key")
local ContractValidate = require("lua_compile.compile_contract_validate")
local StencilKey = require("lua_compile.stencil_key")
local ArityModel = require("lua_compile.lua_rt_arity_model")
local Schema = require("lua_compile.schema")
local pvm = require("moonlift.pvm")
local T = Schema.get()
local CFG, CC, RT, Exec, Stencil = T.MoonCFG, T.CompileContract, T.LuaRT, T.LuaExec, T.Stencil

local function kernel_from(events, evidence)
  local r = C.compile_to_moon_kernel(C.unit_from_events(events, evidence or {}))
  assert(r.kind == "Ok", "compile_to_moon_kernel rejected fixture: " .. tostring(r.diagnostic and r.diagnostic.reason and r.diagnostic.reason.kind))
  assert(r.product.kernel.id.name.text == "lua_exec_core_kernel", "MoonKernel must be produced by LuaExec route")
  return r.product.kernel
end

local function contains_class(v, target, seen)
  if type(v) ~= "table" then return false end
  seen = seen or {}; if seen[v] then return false end; seen[v] = true
  if pvm.classof(v) == target then return true end
  local cls = pvm.classof(v)
  if cls and cls.__fields then
    for _, f in ipairs(cls.__fields) do if contains_class(v[f.name], target, seen) then return true end end
  elseif not cls then
    for _, x in pairs(v) do if contains_class(x, target, seen) then return true end end
  end
  return false
end

local function assert_validate_ok(kernel)
  local ok, errs = Validate.validate(kernel)
  assert(ok, table.concat(errs, "\n"))
end

local function assert_no_protocol_source(src)
  assert(not src:match("out_tag"), "emitted source must not contain out_tag")
  assert(not src:match("out_event_kind"), "emitted source must not contain out_event_kind")
  assert(not src:match("generic_for"), "emitted source must not contain generic_for protocol tag")
  assert(not src:match("getvarg"), "emitted source must not contain getvarg protocol tag")
  assert(not src:match("setlist"), "emitted source must not contain setlist protocol tag")
end

local function contract0()
  return CC.Contract(CC.Transfer({}, {}), {}, {}, {})
end
local function name(s) return CFG.Name(s) end
local function ty(s) return CFG.TypeRef(s) end
local function param(s, moon_type) return CFG.Param(name(s), ty(moon_type), CFG.ValueParam) end
local function kid(s) return CFG.KernelId(name(s)) end
local function rid(s) return CFG.RegionId(name(s)) end
local function bid(s) return CFG.BlockId(name(s)) end
local function bref(s) return CFG.BlockRef(bid(s)) end
local function pvalue(s) return CFG.ParamValue(name(s)) end
local function i64(n) return CFG.ConstValue(CFG.I64Const(n)) end
local function kernel_manual(id, params, returns, blocks)
  local body = CFG.Region(rid(id .. "_body"), params or {}, {}, blocks[1].id, blocks)
  return CFG.Kernel(kid(id), CFG.InlineSpan, params or {}, returns or { ty("i64") }, body, contract0())
end

-- Positive structural slice: LOADI + RETURN1 becomes a one-block MoonCFG kernel.
local kernel = kernel_from({ {op="LOADI",pc=1,a=1,b=42}, {op="RETURN1",pc=2,a=1} }, {})
assert(pvm.classof(kernel) == CFG.Kernel)
assert(kernel["normal" .. "_form"] == nil, "MoonCFG kernel must not carry retired executable payloads")
assert(kernel.body and kernel.body.blocks and #kernel.body.blocks == 1)
assert(kernel.body.blocks[1].terminator.kind == "Return")
assert_validate_ok(kernel)
local src = Emit.emit(kernel, { name = "test_moon_cfg_loadi" })
assert(src:match("local test_moon_cfg_loadi = func"))
assert_no_protocol_source(src)
assert(src == Emit.emit(kernel, { name = "test_moon_cfg_loadi" }), "MoonCFG emission must be deterministic")
local fn = assert(moon.loadstring(src, "=(test_moon_cfg_loadi)"))()
local native = assert(fn:compile())
assert(native() == 42)
native:free()

-- ADDI scalar arithmetic is now LuaExec-owned. Because arithmetic has an
-- explicit nonnumeric error edge, the public MoonKernel route returns a typed
-- outcome projection rather than the old NF scalar direct value.
local addk = kernel_from({ {op="ADDI",pc=1,a=1,b=1,c=128,sc=1}, {op="RETURN1",pc=2,a=1} }, { {slot=1,predicate="is_i64"} })
assert_validate_ok(addk)
assert(#addk.params == 2 and addk.params[1].name.text == "frame0_strings" and addk.params[2].name.text == "slot_1_i64")
local add_src = Emit.emit(addk, { name = "test_moon_cfg_addi" })
assert(add_src:match("LuaRTOutcome") and add_src:match("LuaRTValue"), "LuaExec ADDI should use typed value/outcome substrate")
assert_no_protocol_source(add_src)

-- Actual bytecode-window closed control: an in-window JMP becomes an internal
-- MoonCFG jump carrying the live scalar slot to the target block. The skipped
-- LOADI remains an unreachable in-window block, not an external jump exit.
local closed_jump = kernel_from({
  {op="LOADI",pc=1,a=1,b=1},
  {op="JMP",pc=2,offset=1}, -- target pc = 2 + 1 + 1 = 4
  {op="LOADI",pc=3,a=1,b=2},
  {op="RETURN1",pc=4,a=1},
}, {})
assert_validate_ok(closed_jump)
assert(#closed_jump.body.blocks >= 2, "closed JMP window should lower to internal blocks")
local closed_jump_src = Emit.emit(closed_jump, { name = "test_closed_cfg_jmp" })
assert(closed_jump_src:match("jump pc_4%("), "closed JMP should render as internal block jump")
assert_no_protocol_source(closed_jump_src)
local closed_jump_fn = assert(moon.loadstring(closed_jump_src, "=(test_closed_cfg_jmp)"))()
local closed_jump_native = assert(closed_jump_fn:compile())
assert(closed_jump_native() == 1)
closed_jump_native:free()

-- Actual bytecode-window closed control: PUC comparison+following-JMP is a
-- closed internal branch when both targets are in-window. EQI's true edge is
-- the following JMP target; the false edge skips that JMP.
local closed_eqi = kernel_from({
  {op="EQI",pc=1,a=1,sb=0,k=true},
  {op="JMP",pc=2,offset=2}, -- true target pc = 5
  {op="LOADI",pc=3,a=2,b=22},
  {op="RETURN1",pc=4,a=2},
  {op="LOADI",pc=5,a=2,b=11},
  {op="RETURN1",pc=6,a=2},
}, { {slot=1,predicate="is_i64"} })
assert_validate_ok(closed_eqi)
assert(#closed_eqi.params == 1 and closed_eqi.params[1].name.text == "slot_1_i64")
local closed_eqi_src = Emit.emit(closed_eqi, { name = "test_closed_cfg_eqi" })
assert(closed_eqi_src:match("then jump pc_5"), "EQI branch should render the in-window jump target")
assert(closed_eqi_src:match("LuaRTValue") and closed_eqi_src:match("payload_i64"), "EQI path should use runtime-value substrate before i64 comparison")
assert_no_protocol_source(closed_eqi_src)
local closed_eqi_fn = assert(moon.loadstring(closed_eqi_src, "=(test_closed_cfg_eqi)"))()
local closed_eqi_native = assert(closed_eqi_fn:compile())
assert(closed_eqi_native(0) == 11)
assert(closed_eqi_native(7) == 22)
closed_eqi_native:free()

-- TEST over a proven bool slot is internal branch control, not an out_tag protocol.
local closed_test = kernel_from({
  {op="TEST",pc=1,a=1,k=true},
  {op="JMP",pc=2,offset=2}, -- true target pc = 5
  {op="LOADI",pc=3,a=2,b=22},
  {op="RETURN1",pc=4,a=2},
  {op="LOADI",pc=5,a=2,b=11},
  {op="RETURN1",pc=6,a=2},
}, { {slot=1,predicate="is_bool"} })
assert_validate_ok(closed_test)
assert(#closed_test.params == 1 and closed_test.params[1].name.text == "slot_1_bool")
local closed_test_src = Emit.emit(closed_test, { name = "test_closed_cfg_test" })
assert(closed_test_src:match("if truthy%d* then jump pc_5"), "TEST branch should render runtime-value truthiness as closed control")
assert(closed_test_src:match("%.tag") and closed_test_src:match("LuaRTValue"), "TEST must use LuaRTValue tag truthiness")
assert_no_protocol_source(closed_test_src)
local closed_test_fn = assert(moon.loadstring(closed_test_src, "=(test_closed_cfg_test)"))()
local closed_test_native = assert(closed_test_fn:compile())
assert(closed_test_native(true) == 11)
assert(closed_test_native(false) == 22)
closed_test_native:free()

-- Closed TESTSET can be represented honestly for supported scalar values: the
-- taken edge copies R[B] into R[A] and passes that value via BranchArgs if the
-- target reads it.
local closed_testset = kernel_from({
  {op="TESTSET",pc=1,a=2,b=1,k=true},
  {op="JMP",pc=2,offset=2}, -- true target pc = 5, which reads assigned R2
  {op="LOADFALSE",pc=3,a=2},
  {op="RETURN1",pc=4,a=2},
  {op="RETURN1",pc=5,a=2},
}, { {slot=1,predicate="is_bool"}, {slot=2,predicate="is_bool"} })
assert_validate_ok(closed_testset)
local closed_testset_src = Emit.emit(closed_testset, { name = "test_closed_cfg_testset" })
assert(closed_testset_src:match("then jump pc_5%(pc_5_slot_2 = box_bool%d*%) end"), "TESTSET should pass copied LuaRTValue on the taken edge")
assert_no_protocol_source(closed_testset_src)
local closed_testset_fn = assert(moon.loadstring(closed_testset_src, "=(test_closed_cfg_testset)"))()
local closed_testset_native = assert(closed_testset_fn:compile())
assert(closed_testset_native(true) == true)
assert(closed_testset_native(false) == false)
closed_testset_native:free()

-- Closed branch targets can receive live i64 values through BranchArgs.  This
-- exercises comparison+JMP with target block params, not only direct branches.
local closed_branch_arg = kernel_from({
  {op="LOADI",pc=1,a=2,b=99},
  {op="EQI",pc=2,a=1,sb=0,k=true},
  {op="JMP",pc=3,offset=2}, -- true target pc = 6, which reads R2 before def
  {op="LOADI",pc=4,a=2,b=22},
  {op="RETURN1",pc=5,a=2},
  {op="RETURN1",pc=6,a=2},
}, { {slot=1,predicate="is_i64"} })
assert_validate_ok(closed_branch_arg)
local closed_branch_arg_src = Emit.emit(closed_branch_arg, { name = "test_closed_cfg_branch_arg" })
assert(closed_branch_arg_src:match("then jump pc_6%(pc_6_slot_2 = i64v%d*%) end"), "BranchArgs should pass live LuaRTValue values to branch targets")
assert_no_protocol_source(closed_branch_arg_src)
local closed_branch_arg_fn = assert(moon.loadstring(closed_branch_arg_src, "=(test_closed_cfg_branch_arg)"))()
local closed_branch_arg_native = assert(closed_branch_arg_fn:compile())
assert(closed_branch_arg_native(0) == 99)
assert(closed_branch_arg_native(1) == 22)
closed_branch_arg_native:free()

local function comparison_kernel(opname, fields, evidence, name)
  local ev = { op=opname, pc=1, a=1, b=2, c=0, k=true }
  for k, v in pairs(fields or {}) do ev[k] = v end
  return kernel_from({
    ev,
    {op="JMP",pc=2,offset=2},
    {op="LOADI",pc=3,a=3,b=22},
    {op="RETURN1",pc=4,a=3},
    {op="LOADI",pc=5,a=3,b=11},
    {op="RETURN1",pc=6,a=3},
  }, evidence), name
end

collectgarbage("collect")

local rr_cases = {
  { "EQ", {}, {5, 5, 11}, {5, 6, 22} },
  { "LT", {}, {4, 5, 11}, {5, 4, 22} },
  { "LE", {}, {5, 5, 11}, {6, 5, 22} },
}
for _, case in ipairs(rr_cases) do
  local k = comparison_kernel(case[1], case[2], { {slot=1,predicate="is_i64"}, {slot=2,predicate="is_i64"} })
  assert_validate_ok(k)
  local s = Emit.emit(k, { name = "test_closed_cfg_rr_" .. case[1]:lower() })
  assert_no_protocol_source(s)
  local f = assert(moon.loadstring(s, "test_closed_cfg_cmp_rr_" .. case[1]:lower() .. ".mlua"))()
  local n = assert(f:compile())
  assert(n(case[3][1], case[3][2]) == case[3][3], case[1] .. " true case")
  assert(n(case[4][1], case[4][2]) == case[4][3], case[1] .. " false case")
  n:free()
end

local ri_cases = {
  { "EQI", {sb=5}, {5, 11}, {6, 22} },
  { "LTI", {sb=5}, {4, 11}, {5, 22} },
  { "LEI", {sb=5}, {5, 11}, {6, 22} },
  { "GTI", {sb=5}, {6, 11}, {5, 22} },
  { "GEI", {sb=5}, {5, 11}, {4, 22} },
}
for _, case in ipairs(ri_cases) do
  local k = comparison_kernel(case[1], case[2], { {slot=1,predicate="is_i64"} })
  assert_validate_ok(k)
  local s = Emit.emit(k, { name = "test_closed_cfg_ri_" .. case[1]:lower() })
  assert_no_protocol_source(s)
  local f = assert(moon.loadstring(s, "test_closed_cfg_cmp_ri_" .. case[1]:lower() .. ".mlua"))()
  local n = assert(f:compile())
  assert(n(case[3][1]) == case[3][2], case[1] .. " true case")
  assert(n(case[4][1]) == case[4][2], case[1] .. " false case")
  n:free()
end

local eqk_kernel = comparison_kernel("EQK", {b=1}, { {slot=1,predicate="is_i64"}, {const=1,predicate="const_i64",value=5} })
assert_validate_ok(eqk_kernel)
local eqk_src = Emit.emit(eqk_kernel, { name = "test_closed_cfg_eqk" })
assert(eqk_src:match("payload_i64 = as%(i64, 5%)") and eqk_src:match("== unbox_i64"), "EQK should box/project the proven ConstI64 value explicitly")
assert_no_protocol_source(eqk_src)
local eqk_fn = assert(moon.loadstring(eqk_src, "=(test_closed_cfg_eqk)"))()
local eqk_native = assert(eqk_fn:compile())
assert(eqk_native(5) == 11)
assert(eqk_native(6) == 22)
eqk_native:free()

-- Closed ADD participates in LuaExec internal window control when followed by
-- closed control; arithmetic uses the runtime-value substrate.
local closed_add = kernel_from({
  {op="ADD",pc=1,a=2,b=1,c=1},
  {op="EQI",pc=2,a=2,sb=10,k=true},
  {op="JMP",pc=3,offset=2},
  {op="LOADI",pc=4,a=3,b=22},
  {op="RETURN1",pc=5,a=3},
  {op="LOADI",pc=6,a=3,b=11},
  {op="RETURN1",pc=7,a=3},
}, { {slot=1,predicate="is_i64"} })
assert_validate_ok(closed_add)
local closed_add_src = Emit.emit(closed_add, { name = "test_closed_cfg_add" })
assert(closed_add_src:match("LuaRTValue") and closed_add_src:match("payload_i64"), "closed ADD should use LuaExec runtime-value arithmetic before branch")
assert_no_protocol_source(closed_add_src)

-- Out-of-window jumps reject from LuaExec; no closed-CFG/NF fallback may accept
-- them as external exits.
local external_jump = C.compile_to_moon_kernel(C.unit_from_events({
  {op="JMP",pc=1,offset=99},
  {op="RETURN0",pc=2},
}, {}))
assert(external_jump.kind == "Reject", "external jump target must not compile as closed success")

local legacy_mul = C.compile_to_moon_kernel(C.unit_from_events({
  {op="MUL",pc=1,a=1,b=1,c=2},
  {op="RETURN1",pc=2,a=1},
}, { {slot=1,predicate="is_i64"}, {slot=2,predicate="is_i64"} }))
assert(legacy_mul.kind == "Reject", "NF-owned MUL must not compile through MoonKernel fallback")

-- Manual MoonCFG: multi-block BoolChoice branch closes inside the kernel and
-- runs as native Moonlift. This is positive CFG target coverage, not Lua opcode
-- semantic coverage.
local flag = param("flag", "bool")
local branch_kernel = kernel_manual("test_bool_branch", { flag }, { ty("i64") }, {
  CFG.Block(bid("start"), {}, {}, CFG.Branch(CFG.BoolChoice(pvalue("flag")), bref("yes"), bref("no"))),
  CFG.Block(bid("yes"), {}, {}, CFG.Return({ i64(11) })),
  CFG.Block(bid("no"), {}, {}, CFG.Return({ i64(22) })),
})
assert_validate_ok(branch_kernel)
local branch_src = Emit.emit(branch_kernel, { name = "test_moon_cfg_bool_branch" })
assert(branch_src:match("return region %-%> i64"), "multi-block kernels should render as a Moonlift region expression")
assert(branch_src:match("entry start%(flag: bool = flag%)"), "entry block should expose function params as region entry defaults")
assert(branch_src:match("block yes%(%s*%)") and branch_src:match("block no%(%s*%)"), "target blocks should be rendered")
assert_no_protocol_source(branch_src)
local branch_fn = assert(moon.loadstring(branch_src, "=(test_moon_cfg_bool_branch)"))()
local branch_native = assert(branch_fn:compile())
assert(branch_native(true) == 11)
assert(branch_native(false) == 22)
branch_native:free()

-- Manual MoonCFG: Jump carries a named block parameter and returns it.
local x = param("x", "i64")
local jump_kernel = kernel_manual("test_jump_param", { x }, { ty("i64") }, {
  CFG.Block(bid("start"), {}, {}, CFG.Jump(bref("done"), { CFG.Arg(name("v"), pvalue("x")) })),
  CFG.Block(bid("done"), { param("v", "i64") }, {}, CFG.Return({ pvalue("v") })),
})
assert_validate_ok(jump_kernel)
local jump_src = Emit.emit(jump_kernel, { name = "test_moon_cfg_jump_param" })
assert(jump_src:match("jump done%(v = x%)"), "jump arguments must render by name")
assert(jump_src:match("block done%(v: i64%)"), "block params must render with types")
assert_no_protocol_source(jump_src)
local jump_fn = assert(moon.loadstring(jump_src, "=(test_moon_cfg_jump_param)"))()
local jump_native = assert(jump_fn:compile())
assert(jump_native(99) == 99)
jump_native:free()

-- Manual MoonCFG: simple NumericChoice branch.
local nx = param("nx", "i64")
local numeric_kernel = kernel_manual("test_numeric_branch", { nx }, { ty("i64") }, {
  CFG.Block(bid("start"), {}, {}, CFG.Branch(CFG.NumericChoice(CFG.NumLt, pvalue("nx"), i64(0)), bref("neg"), bref("nonneg"))),
  CFG.Block(bid("neg"), {}, {}, CFG.Return({ i64(1) })),
  CFG.Block(bid("nonneg"), {}, {}, CFG.Return({ i64(0) })),
})
assert_validate_ok(numeric_kernel)
local numeric_src = Emit.emit(numeric_kernel, { name = "test_moon_cfg_numeric_branch" })
assert(numeric_src:match("nx < as%(i64, 0%)"), "numeric branch predicate should render mechanically")
assert_no_protocol_source(numeric_src)
local numeric_fn = assert(moon.loadstring(numeric_src, "=(test_moon_cfg_numeric_branch)"))()
local numeric_native = assert(numeric_fn:compile())
assert(numeric_native(-5) == 1)
assert(numeric_native(5) == 0)
numeric_native:free()

-- Protocol operations must not compile as success. This is a forbidden-success
-- gate only; it is not a claim that these valid Lua operations are implemented.
local function sample_event(op)
  return { op=op, name=op, pc=1, a=1, b=2, c=3, offset=1, k=false, bx=1, sbx=1, ax=1, binop="ADD" }
end
for _, op in ipairs({ "CALL", "TAILCALL", "CLOSE", "TBC", "TFORPREP", "TFORCALL", "TFORLOOP", "SETLIST", "GETVARG" }) do
  local r = C.compile_to_moon_kernel(C.unit_from_events({ sample_event(op) }, {}))
  assert(r.kind == "Reject", op .. " must not compile as protocol success")
end

local function assert_unsupported_reject(op, needle)
  local r = C.compile_to_moon_kernel(C.unit_from_events({ sample_event(op), { op="RETURN0", pc=2 } }, {}))
  assert(r.kind == "Reject", op .. " must reject")
  local msg = r.diagnostic and r.diagnostic.message or ""
  assert(msg:match(needle), op .. " expected " .. needle .. ", got " .. msg)
end
assert_unsupported_reject("CALL", "unsupported_source_semantics:CallRegion")
assert_unsupported_reject("TAILCALL", "unsupported_source_semantics:TailCallRegion")
assert_unsupported_reject("CLOSE", "unsupported_source_semantics:CloseRegion")
assert_unsupported_reject("TBC", "unsupported_source_semantics:CloseRegion")
assert_unsupported_reject("NEWTABLE", "unsupported_source_semantics:GCAllocRegion")
assert_unsupported_reject("CLOSURE", "unsupported_source_semantics:GCAllocRegion")

local descriptor = Exec.RegionDescriptor(
  Exec.RegionId(Exec.Name("typed_region")),
  Exec.CoreWindowRegion,
  Exec.LoadMoveFamily,
  RT.Pc(1),
  RT.Pc(2)
)
local arity_seq = RT.ValueSeq(RT.FixedSeq, {}, RT.FixedCount(0), RT.FromLiteralValues)
local arity_channel = ArityModel.result_channel("OutcomeReturnChannel", arity_seq, RT.FixedCount(0))
local semantic_contract = CC.Contract(
  CC.Transfer({}, {}),
  {
    CC.RequiresSemanticAssumption(CC.AssumesRegionDescriptor(descriptor)),
    CC.RequiresSemanticAssumption(CC.AssumesResultChannel(arity_channel)),
  },
  {
    CC.GuaranteesSemanticAssumption(CC.AssumesRegionDescriptor(descriptor)),
    CC.GuaranteesSemanticAssumption(CC.AssumesResultChannel(arity_channel)),
  },
  {}
)
local contract_ok, contract_errors = ContractValidate.validate(semantic_contract)
assert(contract_ok, table.concat(contract_errors or {}, "\n"))
local contract_key = ContractKey.key(semantic_contract)
assert(contract_key:match("AssumesRegionDescriptor"), "contract key must include typed semantic assumption")
assert(contract_key:match("AssumesResultChannel"), "contract key must include typed result-channel assumption")
local key_ok, key_errors = StencilKey.check_no_forbidden_strings({ Stencil.FromRegionDescriptor(descriptor) })
assert(key_ok, table.concat(key_errors or {}, "\n"))
local target = RT.UnknownCallTarget(RT.TempValue(RT.Name("callee0")))
key_ok, key_errors = StencilKey.check_no_forbidden_strings({ Stencil.FromCallTarget(target) })
assert(key_ok, table.concat(key_errors or {}, "\n"))
local caller = RT.FrameRef(RT.Name("caller0"))
local callee = RT.FrameRef(RT.Name("callee1"))
local identity = RT.LuaClosureTargetIdentity(RT.ClosureRef(RT.Name("closure0")), T.LuaSrc.KRef(0), 9, {})
local layout = RT.CallFrameLayout(RT.CallFrameRef(RT.Name("frame_layout0")), caller, callee, RT.Slot(0), RT.Slot(1), RT.FixedCount(1), RT.Slot(2), RT.FixedCount(1), RT.Count(4))
key_ok, key_errors = StencilKey.check_no_forbidden_strings({ Stencil.FromCallTargetIdentity(identity), Stencil.FromCallFrameLayout(layout) })
assert(key_ok, table.concat(key_errors or {}, "\n"))
key_ok, key_errors = StencilKey.check_no_forbidden_strings({ "call" })
assert(not key_ok and table.concat(key_errors or {}, "\n"):match("forbidden stencil key string: call"), "lowercase call string must remain forbidden")

-- Direct validator negatives for tag ABI and forbidden protocol concepts.
local empty_contract = CC.Contract(CC.Transfer({}, {}), {}, {}, {})
local kid = CFG.KernelId(CFG.Name("bad"))
local rid = CFG.RegionId(CFG.Name("body"))
local bid = CFG.BlockId(CFG.Name("entry"))
local block = CFG.Block(bid, {}, {}, CFG.Return({ CFG.ConstValue(CFG.I64Const(0)) }))
local region = CFG.Region(rid, {}, {}, bid, { block })
local bad_param = CFG.Kernel(kid, CFG.InlineSpan, { CFG.Param(CFG.Name("out_tag"), CFG.TypeRef("ptr(i32)"), CFG.ValueParam) }, { CFG.TypeRef("i64") }, region, empty_contract)
local ok, errs = Validate.validate(bad_param)
assert(not ok and table.concat(errs, "\n"):match("forbidden_param:out_tag"), "validator must reject out_tag params")

local bad_proto = CFG.Kernel(kid, CFG.InlineSpan, {}, { CFG.TypeRef("i64") }, region, empty_contract)
rawset(bad_proto, "contract", { kind = "CallProtocolExit" })
ok, errs = Validate.validate(bad_proto)
assert(not ok and table.concat(errs, "\n"):match("forbidden_protocol_exit_concept:CallProtocolExit"), "validator must reject protocol-exit concepts inside accepted kernels")

print("ok - SpongeJIT LuaCompile MoonCFG LuaExec route")
