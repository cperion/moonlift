package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

-- test_closure_desugar.lua
-- Integration test: parse a module with a closure,
-- verify desugaring produces ctx struct + helper func,
-- and that the module compiles through the pipeline.

local pvm = require("pvm")
local T = pvm.context()
local A = require("moonlift.asdl")
A.Define(T)

local Surf = T.MoonliftSurface
local Elab = T.MoonliftElab
local Sem = T.MoonliftSem
local Back = T.MoonliftBack

local Parse = require("moonlift.parse").Define(T)
local Desugar = require("moonlift.desugar_closures")
local SurfaceToElabTop = require("moonlift.lower_surface_to_elab_top").Define(T)
local ElabToSem = require("moonlift.lower_elab_to_sem").Define(T)
local resolve_api = require("moonlift.resolve_sem_layout").Define(T)
local back_api = require("moonlift.lower_sem_to_back").Define(T)

local function assert_eq(a, b, msg)
    if a == b then return end
    error((msg or "assertion failed") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

local function has_item(items, kind, name)
    for _, item in ipairs(items) do
        if item.kind == kind then
            local target = nil
            if kind == "SurfItemFunc" then target = item.func
            elseif kind == "SurfItemType" then target = item.t
            elseif kind == "SurfItemConst" then target = item.c
            end
            if target and target.name == name then return true end
        end
    end
    return false
end

-- Test 1: simple closure — capture one variable
print("test 1: simple closure capture")
local mod_text = [[
export func multiplier(factor: i32) -> closure(i32) -> i32
    return fn(x: i32) -> i32
        return x * factor
    end
end
]]
local surface = Parse.parse_module(mod_text)
local desugared = Desugar.desugar(surface, Surf)

-- After desugaring, there should be:
-- - _closure_ctx_1 struct with field "factor: i32"
-- - _closure_1 struct with fields "fn" and "ctx"
-- - _closure_fn_1 func that takes (ctx, x) and returns x * (*ctx).factor
-- - The original multiplier returns a closure value
assert(has_item(desugared.items, "SurfItemType", "_closure_ctx_1"),
    "expected _closure_ctx_1 struct")
assert(has_item(desugared.items, "SurfItemType", "_closure_1"),
    "expected _closure_1 struct")
assert(has_item(desugared.items, "SurfItemFunc", "_closure_fn_1"),
    "expected _closure_fn_1 func")

print("  ok")

-- Test 2: closure with no captures (degenerate case)
print("test 2: no-capture closure")
local mod2_text = [[
export func make_adder() -> closure(i32) -> i32
    return fn(x: i32) -> i32
        return x + 1
    end
end
]]
local surface2 = Parse.parse_module(mod2_text)
local desugared2 = Desugar.desugar(surface2, Surf)
-- Should have generated items even with no captures (ctx struct is empty)
assert(has_item(desugared2.items, "SurfItemType", "_closure_ctx_1"),
    "expected empty ctx struct")
assert(has_item(desugared2.items, "SurfItemFunc", "_closure_fn_1"),
    "expected _closure_fn_1 func")
print("  ok")

-- Test 3: parse closure type
print("test 3: closure type parsing")
local cty = Parse.parse_type("closure(i32, f64) -> i32")
assert_eq(cty.kind, "SurfTClosure")
assert_eq(#cty.params, 2)
assert_eq(cty.params[1].kind, "SurfTI32")
assert_eq(cty.params[2].kind, "SurfTF64")
assert_eq(cty.result.kind, "SurfTI32")
print("  ok")

-- Test 4: module without closures passes through unchanged
print("test 4: no-closure module unchanged")
local mod3_text = [[
export func add(x: i32, y: i32) -> i32
    return x + y
end
]]
local surface3 = Parse.parse_module(mod3_text)
local desugared3 = Desugar.desugar(surface3, Surf)
assert_eq(#desugared3.items, #surface3.items,
    "module without closures should have same item count")
print("  ok")

-- Test 5: desugared module lowers through Surface -> Elab
print("test 5: desugared module compiles through pipeline")
local lower_mod = mod_text -- use the closure module
local surface5 = Parse.parse_module(lower_mod)
local desugared5 = Desugar.desugar(surface5, Surf)
local elab_env = Elab.ElabEnv("", {}, {}, {})
local elab = pvm.one(SurfaceToElabTop.lower_module(desugared5, elab_env))
-- Verify the generated function is in elab
local has_generated_fn = false
for _, item in ipairs(elab.items) do
    if item.func and item.func.name == "_closure_fn_1" then
        has_generated_fn = true
    end
end
assert(has_generated_fn, "expected generated function in Elab module")
-- Lower through Elab -> Sem
local sem = pvm.one(ElabToSem.lower_module(elab, nil))
assert(sem.items ~= nil, "Sem lowering should succeed")
print("  ok")

print("\nall closure tests passed")
