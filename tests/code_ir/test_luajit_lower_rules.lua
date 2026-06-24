package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")

local T = pvm.context()
Schema(T)

local Rules = require("moonlift.luajit_lower_rules")(T)

local function base()
    return {
        loop_plan = true,
        owns_loop = true,
        planned = true,
        has_reduce_provider = false,
        has_store_provider = false,
        has_skeleton_provider = false,
        counted_positive = true,
        result_reduction = false,
        returns_reduction = false,
        returns_void = false,
        stencil_reduce_ready = false,
        vector_reduce_ready = false,
        single_store = false,
        store_dst_base = false,
        stencil_store_ready = false,
        stencil_skeleton_ready = false,
    }
end

do
    local c = base()
    c.has_reduce_provider = true
    c.result_reduction = true
    c.returns_reduction = true
    c.stencil_reduce_ready = true
    c.vector_reduce_ready = true
    local selection, err = Rules.select(c)
    assert(selection ~= nil, tostring(err))
    assert(selection.kind == "stencil_reduce", "stencil reduce must win over vector reduce")
end

do
    local c = base()
    c.result_reduction = true
    c.returns_reduction = true
    c.vector_reduce_ready = true
    local selection, err = Rules.select(c)
    assert(selection ~= nil, tostring(err))
    assert(selection.kind == "vector_reduce", "vector reduce should select when stencil reduce is unavailable")
end

do
    local c = base()
    c.has_skeleton_provider = true
    c.stencil_skeleton_ready = true
    c.has_store_provider = true
    c.returns_void = true
    c.single_store = true
    c.store_dst_base = true
    c.stencil_store_ready = true
    local selection, err = Rules.select(c)
    assert(selection ~= nil, tostring(err))
    assert(selection.kind == "stencil_skeleton", "skeleton stencil should win over generic store stencil")
end

do
    local c = base()
    c.has_store_provider = true
    c.returns_void = true
    c.single_store = true
    c.store_dst_base = true
    c.stencil_store_ready = true
    local selection, err = Rules.select(c)
    assert(selection ~= nil, tostring(err))
    assert(selection.kind == "stencil_store", "store stencil should select from store-ready facts")
end

do
    local c = base()
    c.has_reduce_provider = true
    c.result_reduction = true
    c.returns_reduction = true
    c.stencil_reduce_ready = false
    c.vector_reduce_ready = false
    local selection = Rules.select(c)
    assert(selection == nil, "no strategy should select when no ready lowering fact is present")
end

io.write("moonlift luajit_lower_rules ok\n")
