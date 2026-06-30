package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local T = asdl.context()
Schema(T)
require("lalin.luajit_lower")(T)

local SM = T.LalinStencilMachine
local Code = T.LalinCode
local Stencil = T.LalinStencil

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
    assert(selection == SM.StencilMachineKernelReduce, "stencil reduce is the canonical reduction lowering")
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
    assert(selection == SM.StencilMachineKernelSkeleton, "skeleton stencil should win over generic store stencil")
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
    assert(selection == SM.StencilMachineKernelStore, "store stencil should select from store-ready facts")
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
    assert(selection.reason == "reduction rejected", "no-plan should preserve reject reason")
end

local function selected_plan(tag)
    local descriptor = SM.StencilMachineStoreNDescriptor(
        1,
        Stencil.StencilProducer(nil, Stencil.StencilProduceRange1D(Code.CodeTyIndex, nil, nil, 1, Stencil.StencilProducerForward)),
        Code.CodeTyInt(32, Code.CodeSigned),
        nil,
        nil,
        {},
        nil,
        nil,
        tag,
        nil,
        nil,
        nil,
        nil
    )
    return SM.StencilMachineSkeletonPlan(SM.StencilMachineSelectStoreN(descriptor, {}), nil, nil)
end

local function skeleton_input(candidates, reason)
    return SM.StencilMachineSkeletonInput(candidates or {}, reason or "none")
end

do
    local scan = selected_plan("scan")
    local selection = skeleton_input({
        SM.StencilMachineSkeletonScanCandidate(scan),
        SM.StencilMachineSkeletonFindCandidate(selected_plan("find")),
        SM.StencilMachineSkeletonPartitionCandidate(selected_plan("partition")),
        SM.StencilMachineSkeletonCopyCandidate(selected_plan("copy")),
        SM.StencilMachineSkeletonScatterReduceCandidate(selected_plan("scatter_reduce")),
    }):select_stencil_machine_skeleton()
    assert(selection:planned_stencil_machine_skeleton() == scan, "scan skeleton should return scan plan")
end

do
    local find = selected_plan("find")
    local selection = skeleton_input({
        SM.StencilMachineSkeletonFindCandidate(find),
        SM.StencilMachineSkeletonPartitionCandidate(selected_plan("partition")),
        SM.StencilMachineSkeletonCopyCandidate(selected_plan("copy")),
        SM.StencilMachineSkeletonScatterReduceCandidate(selected_plan("scatter_reduce")),
    }):select_stencil_machine_skeleton()
    assert(selection:planned_stencil_machine_skeleton() == find, "find skeleton should return find plan")
end

do
    local partition = selected_plan("partition")
    local selection = skeleton_input({
        SM.StencilMachineSkeletonPartitionCandidate(partition),
        SM.StencilMachineSkeletonCopyCandidate(selected_plan("copy")),
        SM.StencilMachineSkeletonScatterReduceCandidate(selected_plan("scatter_reduce")),
    }):select_stencil_machine_skeleton()
    assert(selection:planned_stencil_machine_skeleton() == partition, "partition skeleton should return partition plan")
end

do
    local copy = selected_plan("copy")
    local selection = skeleton_input({
        SM.StencilMachineSkeletonCopyCandidate(copy),
        SM.StencilMachineSkeletonScatterReduceCandidate(selected_plan("scatter_reduce")),
    }):select_stencil_machine_skeleton()
    assert(selection:planned_stencil_machine_skeleton() == copy, "copy skeleton should return copy plan")
end

do
    local scatter_reduce = selected_plan("scatter_reduce")
    local selection = skeleton_input({
        SM.StencilMachineSkeletonScatterReduceCandidate(scatter_reduce),
    }):select_stencil_machine_skeleton()
    assert(selection:planned_stencil_machine_skeleton() == scatter_reduce, "scatter-reduce skeleton should return scatter-reduce plan")
end

do
    local selection = skeleton_input({}, "no skeleton"):select_stencil_machine_skeleton()
    local planned, reason = selection:planned_stencil_machine_skeleton()
    assert(planned == nil, "no-plan should not return a skeleton plan")
    assert(reason == "no skeleton", "skeleton no-plan should preserve reject reason")
end

assert(not pcall(require, "lalin.luajit_lower_rules"), "old LuaJIT lowering rules module must not exist")

io.write("lalin luajit_lower methods ok\n")
