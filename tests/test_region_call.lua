package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local T = pvm.context()
A.Define(T)

local Parse = require("moonlift.parse").Define(T)
local OpenExpand = require("moonlift.open_expand").Define(T)
local OpenFacts = require("moonlift.open_facts").Define(T)
local OpenValidate = require("moonlift.open_validate").Define(T)
local Typecheck = require("moonlift.tree_typecheck").Define(T)
local RegionCall = require("moonlift.region_call_lowering").Define(T)
local C, Ty, O, Tr = T.MoonCore, T.MoonType, T.MoonOpen, T.MoonTree

local function assert_no_issues(label, issues)
    assert(#issues == 0, label .. " issues: " .. (#issues > 0 and tostring(issues[1].message or pvm.classof(issues[1]).kind) or ""))
end

local i32 = Ty.TScalar(C.ScalarI32)

local frag = Parse.parse_region([[region scan(x: i32; hit(v: i32) | miss() | pair(a: i32, b: i32))
entry start()
    if x > 0 then jump hit(v = x) end
    if x < 0 then jump pair(a = x, b = 1) end
    jump miss()
end
end]])
assert_no_issues("region parse", frag.issues)

local func = Parse.parse_func([[func f(x: i32): i32
    return region: i32
    entry start()
        call scan(x; hit = found, miss = not_found, pair = got_pair)
    end
    block found(v: i32)
        yield v
    end
    block not_found()
        yield 0
    end
    block got_pair(a: i32, b: i32)
        yield a + b
    end
    end
end]])
assert_no_issues("func parse", func.issues)

local emit_stmt = Parse.parse_stmts([[emit scan(1; hit = found, miss = not_found, pair = got_pair)]])
assert_no_issues("emit parse", emit_stmt.issues)
assert(emit_stmt.value[1].mode == Tr.RegionUseEmit, "emit statement should keep RegionUseEmit mode")

local call_stmt = Parse.parse_stmts([[call scan(1; hit = found, miss = not_found, pair = got_pair)]])
assert_no_issues("call parse", call_stmt.issues)
assert(call_stmt.value[1].mode == Tr.RegionUseCall, "call statement should parse as RegionUseCall")

local raw_wrapper = RegionCall.ensure_wrapper(frag.value).wrapper_func
local raw_emit, raw_call = 0, 0
local function walk_raw(stmts)
    for _, stmt in ipairs(stmts or {}) do
        local cls = pvm.classof(stmt)
        if cls == Tr.StmtUseRegionFrag then
            if stmt.mode == Tr.RegionUseEmit then raw_emit = raw_emit + 1 end
            if stmt.mode == Tr.RegionUseCall then raw_call = raw_call + 1 end
        elseif cls == Tr.StmtReturnValue and pvm.classof(stmt.value) == Tr.ExprControl then
            walk_raw(stmt.value.region.entry.body)
            for _, b in ipairs(stmt.value.region.blocks) do walk_raw(b.body) end
        end
    end
end
walk_raw(raw_wrapper.body)
assert(raw_emit == 1 and raw_call == 0, "raw generated wrapper should use emit, never call")

local mod = Tr.Module(Tr.ModuleSurface, { Tr.ItemFunc(func.value) })
local expanded = OpenExpand.module(mod, OpenExpand.env_with_frags({ frag.value }, {}))
assert_no_issues("open validate", OpenValidate.validate(OpenFacts.facts_of_module(expanded)).issues)

local result_types, wrappers = 0, 0
local wrapper
for _, item in ipairs(expanded.items) do
    if pvm.classof(item) == Tr.ItemType and pvm.classof(item.t) == Tr.TypeDeclTaggedUnionSugar and item.t.name:match("^__moon_region_call_scan_") then
        result_types = result_types + 1
        assert(#item.t.variants == 3, "result type should mirror continuation protocol")
        for _, v in ipairs(item.t.variants) do
            if v.name == "pair" then assert(#v.fields == 2, "multi-payload continuation should become two fields") end
        end
    elseif pvm.classof(item) == Tr.ItemFunc and item.func.name:match("^__moon_region_call_scan_") then
        wrappers = wrappers + 1
        wrapper = item.func
    end
end
assert(result_types == 1, "one generated result type expected")
assert(wrappers == 1, "one generated wrapper expected")

local region_use_emit, region_use_call, default_trap, pair_dispatch = 0, 0, 0, 0
local function walk_stmts(stmts)
    for _, stmt in ipairs(stmts or {}) do
        local cls = pvm.classof(stmt)
        if cls == Tr.StmtUseRegionFrag then
            if stmt.mode == Tr.RegionUseEmit then region_use_emit = region_use_emit + 1 end
            if stmt.mode == Tr.RegionUseCall then region_use_call = region_use_call + 1 end
        elseif cls == Tr.StmtSwitch then
            if #(stmt.default_body or {}) == 1 and pvm.classof(stmt.default_body[1]) == Tr.StmtTrap then default_trap = default_trap + 1 end
            for _, arm in ipairs(stmt.variant_arms or {}) do
                if arm.variant_name == "pair" then
                    pair_dispatch = pair_dispatch + 1
                    assert(#arm.binds == 2, "pair dispatch should unpack two payloads")
                end
                walk_stmts(arm.body)
            end
        elseif cls == Tr.StmtIf then
            walk_stmts(stmt.then_body); walk_stmts(stmt.else_body)
        elseif cls == Tr.StmtReturnValue and pvm.classof(stmt.value) == Tr.ExprControl then
            walk_stmts(stmt.value.region.entry.body)
            for _, b in ipairs(stmt.value.region.blocks) do walk_stmts(b.body) end
        end
    end
end
for _, item in ipairs(expanded.items) do if item.func then walk_stmts(item.func.body) end end
assert(region_use_call == 0, "OpenExpand/RNF must remove all RegionUseCall nodes")
assert(default_trap >= 1, "lowered dispatch should have a default trap")
assert(pair_dispatch == 1, "call dispatch should include multi-payload pair arm")

local func2 = Parse.parse_func([[func g(x: i32): i32
    return region: i32
    entry start()
        call scan(x; hit = found, miss = not_found, pair = got_pair)
    end
    block found(v: i32)
        call scan(v; hit = found2, miss = not_found, pair = got_pair)
    end
    block found2(v: i32)
        yield v
    end
    block not_found()
        yield 0
    end
    block got_pair(a: i32, b: i32)
        yield a + b
    end
    end
end]])
assert_no_issues("func2 parse", func2.issues)
local expanded2 = OpenExpand.module(Tr.Module(Tr.ModuleSurface, { Tr.ItemFunc(func2.value) }), OpenExpand.env_with_frags({ frag.value }, {}))
local wrapper_count = 0
for _, item in ipairs(expanded2.items) do
    if pvm.classof(item) == Tr.ItemFunc and item.func.name:match("^__moon_region_call_scan_") then wrapper_count = wrapper_count + 1 end
end
assert(wrapper_count == 1, "repeated calls should reuse one wrapper")

local lease_ty = Ty.TLease(Ty.TPtr(i32), Ty.LeaseOriginUnknown)
local bad = Tr.Module(Tr.ModuleSurface, {
    Tr.ItemType(Tr.TypeDeclTaggedUnionSugar("__moon_region_call_bad_result", {
        Ty.VariantDecl("ok", Ty.TScalar(C.ScalarVoid), { Ty.FieldDecl("p", lease_ty) }),
    })),
})
local checked = Typecheck.check_module(bad)
assert(#checked.issues >= 1, "lease payload should be rejected")
local explained = require("moonlift.tree_typecheck").explain_type_issue(checked.issues[1])
assert(explained.primary.message:match("cannot call region"), "lease diagnostic should mention cannot call region")
assert(explained.suggestions[1].message:match("use `emit`"), "lease diagnostic should suggest emit")

io.write("moonlift region call structural tests ok\n")
