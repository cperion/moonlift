package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

assert(package.loaded["moonlift.tree_to_c"] == nil)
assert(package.loaded["moonlift.tree_control_to_c"] == nil)
assert(package.loaded["moonlift.type_to_c"] == nil)
assert(package.loaded["moonlift.c_places"] == nil)
assert(package.loaded["moonlift.c_residence"] == nil)
assert(package.loaded["moonlift.c_cfg"] == nil)

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local T = pvm.context(); Schema.Define(T)

local Parse = require("moonlift.parse").Define(T)
local OpenFacts = require("moonlift.open_facts").Define(T)
local OpenValidate = require("moonlift.open_validate").Define(T)
local OpenExpand = require("moonlift.open_expand").Define(T)
local ClosureConvert = require("moonlift.closure_convert").Define(T)
local Typecheck = require("moonlift.tree_typecheck").Define(T)
local Layout = require("moonlift.sem_layout_resolve").Define(T)
local TreeToCode = require("moonlift.tree_to_code").Define(T)
local CodeValidate = require("moonlift.code_validate").Define(T)
local CodeToC = require("moonlift.code_to_c").Define(T)
assert(package.loaded["moonlift.tree_to_c"] == nil)
assert(package.loaded["moonlift.tree_control_to_c"] == nil)
assert(package.loaded["moonlift.type_to_c"] == nil)
assert(package.loaded["moonlift.c_places"] == nil)
assert(package.loaded["moonlift.c_residence"] == nil)
assert(package.loaded["moonlift.c_cfg"] == nil)
local CValidate = require("moonlift.c_validate").Define(T)
local CEmit = require("moonlift.c_emit").Define(T)

local C = T.MoonC
local Core = T.MoonCore
local Code = T.MoonCode

local function assert_no_issues(label, issues)
    assert(#issues == 0, label .. " expected no issues, got " .. tostring(#issues))
end

local function code_pipeline(src)
    local parsed = Parse.parse_module(src)
    assert_no_issues("parse", parsed.issues)
    local expanded = OpenExpand.module(parsed.module)
    assert_no_issues("open", OpenValidate.validate(OpenFacts.facts_of_module(expanded)).issues)
    local checked = Typecheck.check_module(ClosureConvert.module(expanded))
    assert_no_issues("typecheck", checked.issues)
    local resolved = Layout.module(checked.module)
    local code_module = TreeToCode.module(resolved)
    assert_no_issues("code", CodeValidate.validate(code_module).issues)
    return code_module
end

local code_module = code_pipeline([[
extern host_add7(x: i32): i32 as "host_add7_impl" end

union Maybe
    some(i32)
  | none
end

func add1(x: i32): i32
    return x + 1
end

func direct_call(y: i32): i32
    return add1(y)
end

func extern_call(y: i32): i32
    return host_add7(y)
end

func choose(a: i32, b: i32): i32
    if a > b then return a else return b end
end

func classify(n: i32): i32
    return switch n do
    case 1 then 10
    case 2 then 20
    default then 0
    end
end

func atomic_demo(p: ptr(i32)): i32
    atomic_store(i32, p, 10)
    let old: i32 = atomic_fetch_add(i32, p, 5)
    let seen: i32 = atomic_cas(i32, p, 15, 21)
    atomic_fence()
    let after: i32 = atomic_load(i32, p)
    return old + seen + after
end

func match_maybe(m: Maybe): i32
    return switch m do
    case .some(x) then x
    default then 0
    end
end
]])

local unit = CodeToC.module(code_module, { dialect = "c11" })
assert_no_issues("c", CValidate.validate(unit).issues)
assert(#unit.funcs == #code_module.funcs, "all Code funcs should become C funcs")
assert(#unit.externs == 1, "Code extern should become C extern")
assert(#unit.helpers > 0, "integer arithmetic should register C helpers")

local saw_goto, saw_switch, saw_call = false, false, false
for _, func in ipairs(unit.funcs) do
    for _, block in ipairs(func.blocks) do
        local term_cls = pvm.classof(block.term)
        if term_cls == C.CBackendIfGoto then saw_goto = true end
        if term_cls == C.CBackendSwitchGoto then saw_switch = true end
        for _, stmt in ipairs(block.stmts) do
            if pvm.classof(stmt) == C.CBackendCall then saw_call = true end
        end
    end
end
assert(saw_goto, "branch CodeTerm should lower to CBackendIfGoto")
assert(saw_switch, "switch CodeTerm should lower to CBackendSwitchGoto")
assert(saw_call, "calls should lower to CBackendCall")

local src = CEmit.emit_artifact(unit).source
assert(src:match("int32_t add1"), "emitted C contains add1")
assert(src:match("extern int32_t host_add7"), "emitted C contains extern")
assert(src:match("#include <stdatomic.h>"), "atomic Code instructions should request C11 atomics")
assert(src:match("atomic_compare_exchange"), "atomic cas helper should be emitted")
assert(src:match("__tag"), "variant type should expose tag field")
assert(src:match("__payload"), "variant type should expose payload field")

local cc = os.getenv("CC") or "cc"
local ok_probe = os.execute(cc .. " --version >/dev/null 2>&1")
if ok_probe == true or ok_probe == 0 then
    local path = os.tmpname() .. ".c"
    local f = assert(io.open(path, "wb")); f:write(src); f:close()
    local ok = os.execute(cc .. " -std=c11 -fsyntax-only " .. path .. " >/dev/null 2>&1")
    os.remove(path)
    assert(ok == true or ok == 0, "code_to_c emitted C should pass cc -std=c99 -fsyntax-only")
else
    io.write("skipping cc syntax check; no C compiler found\n")
end

do
    local origin = Code.CodeOriginGenerated("atomic local-place lowering")
    local i32 = Code.CodeTyInt(32, Code.CodeSigned)
    local sig_id = Code.CodeSigId("sig:atomic_local_place")
    local func_id = Code.CodeFuncId("fn:atomic_local_place")
    local block_id = Code.CodeBlockId("block:atomic_local_place:entry")
    local slot = Code.CodeLocalId("local:atomic_slot")
    local place = Code.CodePlaceLocal(slot, i32)
    local one = Code.CodeValueId("v:atomic:one")
    local two = Code.CodeValueId("v:atomic:two")
    local seen = Code.CodeValueId("v:atomic:seen")
    local old = Code.CodeValueId("v:atomic:old")
    local cas = Code.CodeValueId("v:atomic:cas")
    local access = Code.CodeMemoryAccess(Code.CodeMemoryReadWrite, i32, 4, Code.CodeMayTrap, false, Core.AtomicSeqCst)
    local load_access = Code.CodeMemoryAccess(Code.CodeMemoryRead, i32, 4, Code.CodeMayTrap, false, Core.AtomicSeqCst)
    local store_access = Code.CodeMemoryAccess(Code.CodeMemoryWrite, i32, 4, Code.CodeMayTrap, false, Core.AtomicSeqCst)
    local module = Code.CodeModule(
        Code.CodeModuleId("module:atomic_local_place"),
        { Code.CodeSig(sig_id, {}, { i32 }) },
        {}, {}, {}, {},
        {
            Code.CodeFunc(func_id, "atomic_local_place", Code.CodeLinkageLocal, sig_id, {}, {
                Code.CodeLocal(slot, "atomic_slot", i32, Code.CodeResidenceAddressed, origin),
            }, block_id, {
                Code.CodeBlock(block_id, "entry", {}, {
                    Code.CodeInst(Code.CodeInstId("inst:atomic:one"), Code.CodeInstConst(one, Code.CodeConstLiteral(i32, Core.LitInt("1"))), origin),
                    Code.CodeInst(Code.CodeInstId("inst:atomic:two"), Code.CodeInstConst(two, Code.CodeConstLiteral(i32, Core.LitInt("2"))), origin),
                    Code.CodeInst(Code.CodeInstId("inst:atomic:store"), Code.CodeInstAtomicStore(place, one, store_access, Core.AtomicSeqCst), origin),
                    Code.CodeInst(Code.CodeInstId("inst:atomic:load"), Code.CodeInstAtomicLoad(seen, place, load_access, Core.AtomicSeqCst), origin),
                    Code.CodeInst(Code.CodeInstId("inst:atomic:rmw"), Code.CodeInstAtomicRmw(old, Core.AtomicRmwAdd, place, two, access, Core.AtomicSeqCst), origin),
                    Code.CodeInst(Code.CodeInstId("inst:atomic:cas"), Code.CodeInstAtomicCas(cas, place, two, one, access, Core.AtomicSeqCst), origin),
                }, Code.CodeTerm(Code.CodeTermId("term:atomic_local_place:return"), Code.CodeTermReturn({ cas }), origin), origin),
            }, origin),
        },
        origin
    )
    local atomic_unit = CodeToC.module(module, { dialect = "c11" })
    assert_no_issues("atomic local-place c", CValidate.validate(atomic_unit).issues)
    local atomic_src = CEmit.emit_artifact(atomic_unit).source
    assert(atomic_src:match("atomic_addr_inst_atomic_load_load"), "atomic load on a local place should declare an address scratch")
    assert(atomic_src:match("atomic_addr_inst_atomic_store_store"), "atomic store on a local place should declare an address scratch")
    assert(atomic_src:match("atomic_addr_inst_atomic_rmw_rmw"), "atomic rmw on a local place should declare an address scratch")
    assert(atomic_src:match("atomic_addr_inst_atomic_cas_cas"), "atomic cas on a local place should declare an address scratch")
    if ok_probe == true or ok_probe == 0 then
        local path = os.tmpname() .. ".c"
        local f = assert(io.open(path, "wb")); f:write(atomic_src); f:close()
        local ok = os.execute(cc .. " -std=c11 -fsyntax-only " .. path .. " >/dev/null 2>&1")
        os.remove(path)
        assert(ok == true or ok == 0, "Code atomics on non-deref places should emit valid C")
    end
end

assert(package.loaded["moonlift.tree_to_c"] == nil)
assert(package.loaded["moonlift.tree_control_to_c"] == nil)
assert(package.loaded["moonlift.c_places"] == nil)
assert(package.loaded["moonlift.c_residence"] == nil)
assert(package.loaded["moonlift.c_cfg"] == nil)

local fh = assert(io.open("lua/moonlift/code_to_c.lua", "r"))
local source = fh:read("*a"); fh:close()
assert(not source:find("ctx%." .. "view_values"), "C lowering must not keep hidden view-value side table")
assert(not source:find("view_" .. "parts"), "C lowering must not keep view component side table")
io.write("moonlift code_to_c ok\n")
