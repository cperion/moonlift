package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

assert(package.loaded["moonlift.tree_to_c"] == nil)
assert(package.loaded["moonlift.tree_control_to_c"] == nil)
assert(package.loaded["moonlift.type_to_c"] == nil)
assert(package.loaded["moonlift.c_places"] == nil)
assert(package.loaded["moonlift.c_residence"] == nil)
assert(package.loaded["moonlift.c_cfg"] == nil)

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local T = pvm.context()
Schema.Define(T)

local Parse = require("moonlift.parse").Define(T)
local OpenFacts = require("moonlift.open_facts").Define(T)
local OpenValidate = require("moonlift.open_validate").Define(T)
local OpenExpand = require("moonlift.open_expand").Define(T)
local SurfaceResolve = require("moonlift.surface_resolve").Define(T)
local ClosureConvert = require("moonlift.closure_convert").Define(T)
local Typecheck = require("moonlift.tree_typecheck").Define(T)
local Layout = require("moonlift.sem_layout_resolve").Define(T)
local TreeToCode = require("moonlift.tree_to_code").Define(T)
local CodeValidate = require("moonlift.code_validate").Define(T)

local Core = T.MoonCore
local Ty = T.MoonType
local Bind = T.MoonBind
local Tr = T.MoonTree
local Code = T.MoonCode

local function assert_no_issues(label, issues)
    assert(#issues == 0, label .. " expected no issues, got " .. tostring(#issues))
end

local function module_pipeline(module)
    local expanded = OpenExpand.module(module)
    local surfaced = SurfaceResolve.module(expanded)
    local open_report = OpenValidate.validate(OpenFacts.facts_of_module(surfaced))
    assert_no_issues("open", open_report.issues)

    local closed = ClosureConvert.module(surfaced)
    local checked = Typecheck.check_module(closed)
    assert_no_issues("typecheck", checked.issues)

    local resolved = Layout.module(checked.module)
    local code_module = TreeToCode.module(resolved)
    local code_report = CodeValidate.validate(code_module)
    assert_no_issues("code_validate", code_report.issues)
    return code_module, resolved
end

local function scalar_pipeline(src)
    local parsed = Parse.parse_module(src)
    assert_no_issues("parse", parsed.issues)
    return module_pipeline(parsed.module)
end

local code_module = scalar_pipeline([[
func const_i32(): i32
    return 42
end

func add_i32(a: i32, b: i32): i32
    let c: i32 = a + b
    return c
end

func choose_i32(a: i32, b: i32): i32
    return select(a > b, a, b)
end

func cast_u8_to_i32(x: u8): i32
    return as(i32, x)
end
]])

assert(#code_module.funcs == 4)
assert(#code_module.sigs >= 3)

local seen = {}
for _, func in ipairs(code_module.funcs) do
    assert(func.entry == func.blocks[1].id)
    assert(#func.blocks == 1)
    assert(func.blocks[1].name == "entry")
    assert(pvm.classof(func.blocks[1].term.kind) == Code.CodeTermReturn)
    for _, block in ipairs(func.blocks) do
        for _, inst in ipairs(block.insts) do
            seen[pvm.classof(inst.kind)] = true
        end
    end
end

assert(seen[Code.CodeInstConst], "expected scalar literal const instruction")
assert(seen[Code.CodeInstBinary], "expected scalar binary instruction")
assert(seen[Code.CodeInstCompare], "expected compare instruction")
assert(seen[Code.CodeInstSelect], "expected select instruction")
assert(seen[Code.CodeInstCast], "expected machine cast instruction")
assert(seen[Code.CodeInstAlias], "expected let alias instruction")

local contract_module, contract_tree = scalar_pipeline([[
func add_noalias_i32(noalias dst: ptr(i32), readonly a: ptr(i32), readonly b: ptr(i32), n: i32): i32
    requires bounds(dst, n)
    requires bounds(a, n)
    requires bounds(b, n)
    requires disjoint(dst, a)
    requires disjoint(dst, b)
    return 0
end
]])
local contract_set = TreeToCode.contracts(contract_tree)
assert(contract_set.module == contract_module.id, "contract fact set should be keyed to the lowered CodeModule id")
assert(#contract_set.facts == 8, "expected explicit and parameter-modifier contracts to lower to CodeContractFactSet")
local contract_counts = { bounds = 0, disjoint = 0, noalias = 0, readonly = 0, rejected = 0 }
local contract_func = contract_module.funcs[1]
local params_by_name = {}
for _, param in ipairs(contract_func.params) do params_by_name[param.name] = param.value end
for _, fact in ipairs(contract_set.facts) do
    assert(fact.func == contract_func.id, "contract fact should be keyed by CodeFuncId")
    local cls = pvm.classof(fact.fact)
    if cls == Code.CodeContractBounds then
        contract_counts.bounds = contract_counts.bounds + 1
        assert(fact.fact.base == params_by_name.dst or fact.fact.base == params_by_name.a or fact.fact.base == params_by_name.b)
        assert(fact.fact.len == params_by_name.n)
    elseif cls == Code.CodeContractDisjoint then
        contract_counts.disjoint = contract_counts.disjoint + 1
    elseif cls == Code.CodeContractNoAlias then
        contract_counts.noalias = contract_counts.noalias + 1
        assert(fact.fact.base == params_by_name.dst)
    elseif cls == Code.CodeContractReadonly then
        contract_counts.readonly = contract_counts.readonly + 1
        assert(fact.fact.base == params_by_name.a or fact.fact.base == params_by_name.b)
    elseif cls == Code.CodeContractRejected then
        contract_counts.rejected = contract_counts.rejected + 1
    end
end
assert(contract_counts.bounds == 3)
assert(contract_counts.disjoint == 2)
assert(contract_counts.noalias == 1)
assert(contract_counts.readonly == 2)
assert(contract_counts.rejected == 0)

local function scan_place(place, out)
    local cls = pvm.classof(place)
    out[cls] = true
    if cls == Code.CodePlaceField then scan_place(place.base, out) end
    if cls == Code.CodePlaceIndex then scan_place(place.base, out) end
end

local function scan_module(module)
    local out = { insts = {}, places = {}, funcs = {}, accesses = {} }
    for _, func in ipairs(module.funcs) do
        out.funcs[func.name] = func
        for _, block in ipairs(func.blocks) do
            for _, inst in ipairs(block.insts) do
                local k = inst.kind
                local cls = pvm.classof(k)
                out.insts[cls] = true
                if cls == Code.CodeInstAddrOf or cls == Code.CodeInstLoad or cls == Code.CodeInstStore then
                    scan_place(k.place, out.places)
                end
                if cls == Code.CodeInstLoad or cls == Code.CodeInstStore then
                    out.accesses[#out.accesses + 1] = k.access
                end
            end
        end
    end
    return out
end

local function assert_no_moontree(node, seen)
    if type(node) ~= "table" then return end
    seen = seen or {}
    if seen[node] then return end
    seen[node] = true
    local cls = pvm.classof(node)
    assert(not (cls and tostring(cls):match("MoonTree")), "MoonCode output should not retain MoonTree node " .. tostring(cls))
    local fields = cls and cls.__fields or nil
    if fields then
        for i = 1, #fields do assert_no_moontree(node[fields[i].name], seen) end
    else
        for _, v in pairs(node) do assert_no_moontree(v, seen) end
    end
end

local i32_ty = Ty.TScalar(Core.ScalarI32)
local global_module = module_pipeline(Tr.Module(Tr.ModuleSurface, {
    Tr.ItemConst(Tr.ConstItem("answer", i32_ty, Tr.ExprLit(Tr.ExprSurface, Core.LitInt("40")))),
    Tr.ItemStatic(Tr.StaticItem("counter", i32_ty, Tr.ExprLit(Tr.ExprSurface, Core.LitInt("2")))),
    Tr.ItemFunc(Tr.FuncLocal("global_sum", {}, i32_ty, {
        Tr.StmtReturnValue(Tr.StmtSurface, Tr.ExprBinary(
            Tr.ExprSurface,
            Core.BinAdd,
            Tr.ExprRef(Tr.ExprSurface, Bind.ValueRefName("answer")),
            Tr.ExprRef(Tr.ExprSurface, Bind.ValueRefName("counter"))
        )),
    })),
}))
local global_seen = scan_module(global_module)
assert(#global_module.globals == 2, "const/static items should lower to CodeGlobal entries")
assert(global_seen.places[Code.CodePlaceGlobal], "global references should load from CodePlaceGlobal")

local data_module = TreeToCode.module(Tr.Module(Tr.ModuleSurface, {
    Tr.ItemData(Tr.DataItem(Core.DataId("blob"), 4, 1, "ABCD")),
}), { layout_env = T.MoonSem.LayoutEnv({}) })
assert_no_issues("code_validate:data", CodeValidate.validate(data_module).issues)
assert(#data_module.data == 1, "data items should lower to CodeData entries")

local place_module = scalar_pipeline([[
struct Pair
    x: i32,
    y: i32,
end

func mutable_local(): i32
    var x: i32 = 1
    x = x + 2
    return x
end

func addr_deref(): i32
    var x: i32 = 7
    let p: ptr(i32) = &x
    return *p
end

func pointer_index(p: ptr(i32), i: index): i32
    p[i] = 4
    return p[i]
end

func struct_field(p: ptr(Pair), v: i32): i32
    (*p).y = v
    return (*p).x + (*p).y
end
]])

local place_seen = scan_module(place_module)
assert(place_seen.insts[Code.CodeInstAddrOf], "expected address-of instruction")
assert(place_seen.insts[Code.CodeInstLoad], "expected load instruction")
assert(place_seen.insts[Code.CodeInstStore], "expected store instruction")
assert(place_seen.places[Code.CodePlaceLocal], "expected local place")
assert(place_seen.places[Code.CodePlaceDeref], "expected deref place")
assert(place_seen.places[Code.CodePlaceIndex], "expected index place")
assert(place_seen.places[Code.CodePlaceField], "expected resolved field place")
assert(#place_seen.accesses > 0, "expected memory access facts")
for _, access in ipairs(place_seen.accesses) do
    assert(access.align >= 1, "memory access align should be explicit")
    assert(access.trap == Code.CodeMayTrap, "memory access trap mode should be explicit")
end
assert(#place_seen.funcs.mutable_local.locals == 1, "mutable local should allocate one CodeLocal")
assert(#place_seen.funcs.addr_deref.locals == 1, "addressed var should allocate one CodeLocal")
assert(#place_seen.funcs.pointer_index.locals == 0, "pointer indexing should not allocate hidden locals")

local control_module = scalar_pipeline([[
func if_else_stmt(a: i32, b: i32): i32
    var x: i32 = 0
    if a > b then x = a else x = b end
    return x
end

func switch_default(n: i32): i32
    let v: i32 = switch n do
    case 1 then 10
    case 2 then
        let x: i32 = 20
        x
    default then 7
    end
    return v
end

func counted_loop(n: i32): i32
    return block loop(i: i32 = 0, acc: i32 = 0): i32
        if i >= n then yield acc else jump loop(i = i + 1, acc = acc + i) end
    end
end

func short_circuit(a: bool, b: bool): bool
    return a and b
end
]])

local control_seen = scan_module(control_module)
assert(control_seen.insts[Code.CodeInstConst], "control tests should still lower literals")
local function term_classes(func)
    local out = {}
    local param_blocks = 0
    for _, block in ipairs(func.blocks) do
        out[pvm.classof(block.term.kind)] = true
        if #block.params > 0 then param_blocks = param_blocks + 1 end
    end
    return out, param_blocks
end

local if_terms = term_classes(control_seen.funcs.if_else_stmt)
assert(if_terms[Code.CodeTermBranch], "if/else statement should lower to explicit branch term")
assert(if_terms[Code.CodeTermJump], "if/else fallthrough should jump to explicit join block")
assert(#control_seen.funcs.if_else_stmt.blocks >= 4, "if/else statement should create explicit blocks")

local switch_terms, switch_param_blocks = term_classes(control_seen.funcs.switch_default)
assert(switch_terms[Code.CodeTermSwitch], "switch expression should lower to CodeTermSwitch")
assert(switch_terms[Code.CodeTermJump], "switch expression cases should jump to value join")
assert(switch_param_blocks >= 1, "switch expression should use a block param for its join value")

local loop_terms, loop_param_blocks = term_classes(control_seen.funcs.counted_loop)
assert(loop_terms[Code.CodeTermBranch], "counted loop if should lower to branch")
assert(loop_terms[Code.CodeTermJump], "counted loop should lower yields/jumps to CodeTermJump")
assert(loop_param_blocks >= 2, "counted loop and expression exit should use CodeBlock params")

local logic_terms, logic_param_blocks = term_classes(control_seen.funcs.short_circuit)
assert(logic_terms[Code.CodeTermBranch], "short-circuit logic should lower to branch, not CodeInstSelect")
assert(logic_terms[Code.CodeTermJump], "short-circuit logic should jump to a bool join")
assert(logic_param_blocks >= 1, "short-circuit logic should use a block param join value")

local call_module = scalar_pipeline([[
extern host_add7(x: i32): i32 as "host_add7_impl" end

func add1(x: i32): i32
    return x + 1
end

func direct_call(y: i32): i32
    return add1(y)
end

func extern_call(y: i32): i32
    return host_add7(y)
end

func indirect_call(y: i32): i32
    let f: func(i32): i32 = add1
    return f(y)
end
]])

local call_targets = {}
local global_refs = {}
for _, func in ipairs(call_module.funcs) do
    for _, block in ipairs(func.blocks) do
        for _, inst in ipairs(block.insts) do
            local k = inst.kind
            if pvm.classof(k) == Code.CodeInstCall then call_targets[pvm.classof(k.target)] = true end
            if pvm.classof(k) == Code.CodeInstGlobalRef then global_refs[pvm.classof(k.ref)] = true end
        end
    end
end
assert(#call_module.externs == 1, "extern declarations should become CodeExterns")
assert(call_targets[Code.CodeCallDirect], "direct function calls should use CodeCallDirect")
assert(call_targets[Code.CodeCallExtern], "extern calls should use CodeCallExtern")
assert(call_targets[Code.CodeCallIndirect], "function pointer calls should use CodeCallIndirect")
assert(global_refs[Code.CodeGlobalRefFunc], "function pointer values should materialize CodeGlobalRefFunc")

local advanced_module = scalar_pipeline([[
struct Pair
    x: i32,
    y: i32,
end

func aggregate_array_view(p: ptr(i32), n: index): i32
    let pair: Pair = Pair{ x = 10, y = 20 }
    let xs: [i32; 3] = [1, 2, 3]
    let v: view(i32) = view(p, n)
    p[0] = 4
    return pair.x + xs[1] + as(i32, len(v)) + v[0] + as(i32, sizeof(Pair)) + as(i32, alignof(Pair))
end

func null_check(p: ptr(i32)): bool
    return is_null(p)
end

func null_literal(): bool
    return is_null(null(ptr(i32)))
end

func atomic_demo(p: ptr(i32)): i32
    atomic_store(i32, p, 10)
    let old: i32 = atomic_fetch_add(i32, p, 5)
    let seen: i32 = atomic_cas(i32, p, 15, 21)
    atomic_fence()
    let after: i32 = atomic_load(i32, p)
    return old + seen + after
end
]])

local advanced_seen = scan_module(advanced_module)
assert(advanced_seen.insts[Code.CodeInstAggregate], "aggregate literals should lower to CodeInstAggregate")
assert(advanced_seen.insts[Code.CodeInstArray], "array literals should lower to CodeInstArray")
assert(advanced_seen.insts[Code.CodeInstViewMake], "view construction should lower to CodeInstViewMake")
assert(advanced_seen.insts[Code.CodeInstViewLen], "view len should lower to CodeInstViewLen")
assert(advanced_seen.insts[Code.CodeInstViewData], "view indexing should project view data")
assert(advanced_seen.insts[Code.CodeInstViewStride], "view indexing should project view stride")
assert(advanced_seen.insts[Code.CodeInstAtomicLoad], "atomic load should lower to CodeInstAtomicLoad")
assert(advanced_seen.insts[Code.CodeInstAtomicStore], "atomic store should lower to CodeInstAtomicStore")
assert(advanced_seen.insts[Code.CodeInstAtomicRmw], "atomic rmw should lower to CodeInstAtomicRmw")
assert(advanced_seen.insts[Code.CodeInstAtomicCas], "atomic cas should lower to CodeInstAtomicCas")
assert(advanced_seen.insts[Code.CodeInstAtomicFence], "atomic fence should lower to CodeInstAtomicFence")

local variant_module = scalar_pipeline([[
union Maybe
    some(i32)
  | none
end

func ctor_match(x: i32): i32
    let m = Maybe.some(x)
    return switch m do
    case .some(v) then v
    default then 0
    end
end

func match_expr(m: Maybe): i32
    return switch m do
    case .some(x) then x
    default then 0
    end
end

func match_stmt(m: Maybe): i32
    var out: i32 = 0
    switch m do
    case .some(x) then out = x
    default then out = 0
    end
    return out
end
]])

local variant_seen = scan_module(variant_module)
assert(variant_seen.insts[Code.CodeInstVariantCtor], "variant constructors should lower to CodeInstVariantCtor")
assert(variant_seen.insts[Code.CodeInstVariantTag], "variant switches should project tags")
assert(variant_seen.insts[Code.CodeInstVariantPayload], "variant binds should project payloads")
local variant_expr_terms = term_classes(variant_seen.funcs.match_expr)
assert(variant_expr_terms[Code.CodeTermVariantSwitch], "variant expression switch should lower to CodeTermVariantSwitch")
local variant_stmt_terms = term_classes(variant_seen.funcs.match_stmt)
assert(variant_stmt_terms[Code.CodeTermVariantSwitch], "variant statement switch should lower to CodeTermVariantSwitch")

for _, module in ipairs({ code_module, global_module, data_module, place_module, control_module, call_module, advanced_module, variant_module }) do
    assert_no_moontree(module)
end

assert(package.loaded["moonlift.tree_to_c"] == nil)
assert(package.loaded["moonlift.tree_control_to_c"] == nil)
assert(package.loaded["moonlift.type_to_c"] == nil)
assert(package.loaded["moonlift.c_places"] == nil)
assert(package.loaded["moonlift.c_residence"] == nil)
assert(package.loaded["moonlift.c_cfg"] == nil)

io.write("moonlift tree_to_code scalar ok\n")
