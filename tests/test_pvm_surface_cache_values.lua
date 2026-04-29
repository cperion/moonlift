package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local moon = require("moonlift.host")
local SurfaceModel = require("moonlift.pvm_surface_model")
local TypeRefSurface = require("moonlift.type_ref_classify_surface")
local CacheValues = require("moonlift.pvm_surface_cache_values")

local T = moon.T
SurfaceModel.Define(T)
local Tr = T.MoonTree

local body = TypeRefSurface.Define(T)
local M = moon.module("NativePvmCacheTest")
local fn = CacheValues.add_one_result_cache(moon, M, body)
assert(fn.name == "type_ref_classify")

local module = M:to_asdl()
local saw_hit, saw_entry, saw_cache, saw_func = false, false, false, false
for i = 1, #module.items do
    local item = module.items[i]
    if pvm.classof(item) == Tr.ItemType then
        if pvm.classof(item.t) == Tr.TypeDeclStruct and item.t.name == "type_ref_classifyCacheHit" then saw_hit = true end
        if pvm.classof(item.t) == Tr.TypeDeclStruct and item.t.name == "type_ref_classifyCacheEntry" then saw_entry = true end
        if pvm.classof(item.t) == Tr.TypeDeclStruct and item.t.name == "type_ref_classifyCache" then saw_cache = true end
    elseif pvm.classof(item) == Tr.ItemFunc and pvm.classof(item.func) == Tr.FuncExport and item.func.name == "type_ref_classify" then
        saw_func = true
        assert(#item.func.body >= 6)
        assert(pvm.classof(item.func.body[2]) == Tr.StmtLet) -- hit = lookup(...)
        assert(pvm.classof(item.func.body[3]) == Tr.StmtIf)  -- if hit.valid return hit.value
        assert(pvm.classof(item.func.body[#item.func.body]) == Tr.StmtReturnValue)
    end
end
assert(saw_hit)
assert(saw_entry)
assert(saw_cache)
assert(saw_func)

io.write("moonlift pvm_surface_cache_values ok\n")
