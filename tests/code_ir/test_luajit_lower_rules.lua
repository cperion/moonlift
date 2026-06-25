package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")

local T = pvm.context()
Schema(T)

local Rules = require("lalin.luajit_lower_rules")(T)

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
        single_store = false,
        store_dst_base = false,
        stencil_store_ready = false,
        stencil_skeleton_ready = false,
        any_ready_lowering = false,
        reject_reason = "no lowering",
    }
end

do
    local c = base()
    c.has_reduce_provider = true
    c.result_reduction = true
    c.returns_reduction = true
    c.stencil_reduce_ready = true
    c.any_ready_lowering = true
    local selection, err = Rules:run("select_kernel_lowering", { kernel = c }, "selection", "no LuaJIT kernel lowering selected")
    assert(selection ~= nil, tostring(err))
    assert(selection.kind == "stencil_reduce", "stencil reduce is the canonical reduction lowering")
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
    c.any_ready_lowering = true
    local selection, err = Rules:run("select_kernel_lowering", { kernel = c }, "selection", "no LuaJIT kernel lowering selected")
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
    c.any_ready_lowering = true
    local selection, err = Rules:run("select_kernel_lowering", { kernel = c }, "selection", "no LuaJIT kernel lowering selected")
    assert(selection ~= nil, tostring(err))
    assert(selection.kind == "stencil_store", "store stencil should select from store-ready facts")
end

do
    local c = base()
    c.has_reduce_provider = true
    c.result_reduction = true
    c.returns_reduction = true
    c.stencil_reduce_ready = false
    c.reject_reason = "reduction rejected"
    local selection, err = Rules:run("select_kernel_lowering", { kernel = c }, "selection", "no LuaJIT kernel lowering selected")
    assert(selection ~= nil, tostring(err))
    assert(selection.kind == "no_plan", "no ready lowering fact should produce explicit no_plan")
    assert(selection.reason == "reduction rejected", "no_plan should preserve reject reason")
end

do
    local selection, err = Rules:run("select_skeleton_lowering", { skeleton = {
        scan_ready = true,
        scan_plan = "scan",
        find_ready = true,
        find_plan = "find",
        partition_ready = true,
        partition_plan = "partition",
        copy_ready = true,
        copy_plan = "copy",
        reject_reason = "none",
    } }, "selection", "no LuaJIT skeleton lowering selected")
    assert(selection ~= nil, tostring(err))
    assert(selection.kind == "skeleton_scan", "scan skeleton should have first priority")
    assert(selection.planned == "scan", "scan skeleton should return scan plan")
end

do
    local selection, err = Rules:run("select_skeleton_lowering", { skeleton = {
        scan_ready = false,
        find_ready = true,
        find_plan = "find",
        partition_ready = true,
        partition_plan = "partition",
        copy_ready = true,
        copy_plan = "copy",
        reject_reason = "none",
    } }, "selection", "no LuaJIT skeleton lowering selected")
    assert(selection ~= nil, tostring(err))
    assert(selection.kind == "skeleton_find", "find skeleton should win after scan rejection")
    assert(selection.planned == "find", "find skeleton should return find plan")
end

do
    local selection, err = Rules:run("select_skeleton_lowering", { skeleton = {
        scan_ready = false,
        find_ready = false,
        partition_ready = true,
        partition_plan = "partition",
        copy_ready = true,
        copy_plan = "copy",
        reject_reason = "none",
    } }, "selection", "no LuaJIT skeleton lowering selected")
    assert(selection ~= nil, tostring(err))
    assert(selection.kind == "skeleton_partition", "partition skeleton should win after scan/find rejection")
    assert(selection.planned == "partition", "partition skeleton should return partition plan")
end

do
    local selection, err = Rules:run("select_skeleton_lowering", { skeleton = {
        scan_ready = false,
        find_ready = false,
        partition_ready = false,
        copy_ready = true,
        copy_plan = "copy",
        reject_reason = "none",
    } }, "selection", "no LuaJIT skeleton lowering selected")
    assert(selection ~= nil, tostring(err))
    assert(selection.kind == "skeleton_copy", "copy skeleton should win after other skeletons reject")
    assert(selection.planned == "copy", "copy skeleton should return copy plan")
end

do
    local selection, err = Rules:run("select_skeleton_lowering", { skeleton = {
        scan_ready = false,
        find_ready = false,
        partition_ready = false,
        copy_ready = false,
        reject_reason = "no skeleton",
    } }, "selection", "no LuaJIT skeleton lowering selected")
    assert(selection ~= nil, tostring(err))
    assert(selection.kind == "no_plan", "no skeleton should produce explicit no_plan")
    assert(selection.reason == "no skeleton", "skeleton no_plan should preserve reject reason")
end

io.write("lalin luajit_lower_rules ok\n")
