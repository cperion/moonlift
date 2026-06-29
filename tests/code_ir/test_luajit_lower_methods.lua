package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local T = asdl.context()
Schema(T)
require("lalin.luajit_lower")(T)

local SM = T.LalinStencilMachine

do
    local selection = SM.StencilMachineKernelInput(
        true, true, true,
        true, false, false,
        true,
        true, true, false,
        true,
        false, false, false, false,
        "no lowering"
    ):select_stencil_machine_kernel()
    assert(selection:stencil_machine_kernel_is_reduce(), "stencil reduce is the canonical reduction lowering")
end

do
    local selection = SM.StencilMachineKernelInput(
        true, true, true,
        false, true, true,
        true,
        false, false, true,
        false,
        true, true, true, true,
        "no lowering"
    ):select_stencil_machine_kernel()
    assert(selection:stencil_machine_kernel_is_skeleton(), "skeleton stencil should win over generic store stencil")
end

do
    local selection = SM.StencilMachineKernelInput(
        true, true, true,
        false, true, false,
        true,
        false, false, true,
        false,
        true, true, true, false,
        "no lowering"
    ):select_stencil_machine_kernel()
    assert(selection:stencil_machine_kernel_is_store(), "store stencil should select from store-ready facts")
end

do
    local selection = SM.StencilMachineKernelInput(
        true, true, true,
        true, false, false,
        true,
        true, true, false,
        false,
        false, false, false, false,
        "reduction rejected"
    ):select_stencil_machine_kernel()
    assert(selection:stencil_machine_kernel_is_no_plan(), "no ready lowering fact should produce explicit no-plan")
    assert(selection.reason == "reduction rejected", "no-plan should preserve reject reason")
end

local function selected_plan(tag)
    local info = SM.StencilMachineSelectionInfo(
        nil, nil,
        nil, nil, nil, nil,
        nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil,
        nil, nil, nil, nil,
        {},
        nil,
        nil, nil, nil, nil,
        nil, nil, nil,
        tag,
        nil, nil, nil, nil
    )
    return SM.StencilMachineSkeletonPlan(SM.StencilMachineSelectStoreN(info, {}), nil, nil)
end

do
    local scan = selected_plan("scan")
    local selection = SM.StencilMachineSkeletonInput(
        scan,
        selected_plan("find"),
        selected_plan("partition"),
        selected_plan("copy"),
        selected_plan("scatter_reduce"),
        "none"
    ):select_stencil_machine_skeleton()
    assert(selection:stencil_machine_skeleton_is_scan(), "scan skeleton should have first priority")
    assert(selection:planned_stencil_machine_skeleton() == scan, "scan skeleton should return scan plan")
end

do
    local find = selected_plan("find")
    local selection = SM.StencilMachineSkeletonInput(nil, find, selected_plan("partition"), selected_plan("copy"), selected_plan("scatter_reduce"), "none"):select_stencil_machine_skeleton()
    assert(selection:stencil_machine_skeleton_is_find(), "find skeleton should win after scan rejection")
    assert(selection:planned_stencil_machine_skeleton() == find, "find skeleton should return find plan")
end

do
    local partition = selected_plan("partition")
    local selection = SM.StencilMachineSkeletonInput(nil, nil, partition, selected_plan("copy"), selected_plan("scatter_reduce"), "none"):select_stencil_machine_skeleton()
    assert(selection:stencil_machine_skeleton_is_partition(), "partition skeleton should win after scan/find rejection")
    assert(selection:planned_stencil_machine_skeleton() == partition, "partition skeleton should return partition plan")
end

do
    local copy = selected_plan("copy")
    local selection = SM.StencilMachineSkeletonInput(nil, nil, nil, copy, selected_plan("scatter_reduce"), "none"):select_stencil_machine_skeleton()
    assert(selection:stencil_machine_skeleton_is_copy(), "copy skeleton should win after other skeletons reject")
    assert(selection:planned_stencil_machine_skeleton() == copy, "copy skeleton should return copy plan")
end

do
    local scatter_reduce = selected_plan("scatter_reduce")
    local selection = SM.StencilMachineSkeletonInput(nil, nil, nil, nil, scatter_reduce, "none"):select_stencil_machine_skeleton()
    assert(selection:stencil_machine_skeleton_is_scatter_reduce(), "scatter-reduce skeleton should win after copy rejects")
    assert(selection:planned_stencil_machine_skeleton() == scatter_reduce, "scatter-reduce skeleton should return scatter-reduce plan")
end

do
    local selection = SM.StencilMachineSkeletonInput(nil, nil, nil, nil, nil, "no skeleton"):select_stencil_machine_skeleton()
    assert(selection:stencil_machine_skeleton_is_no_plan(), "no skeleton should produce explicit no-plan")
    local planned, reason = selection:planned_stencil_machine_skeleton()
    assert(planned == nil, "no-plan should not return a skeleton plan")
    assert(reason == "no skeleton", "skeleton no-plan should preserve reject reason")
end

assert(not pcall(require, "lalin.luajit_lower_rules"), "old LuaJIT lowering rules module must not exist")

io.write("lalin luajit_lower methods ok\n")
