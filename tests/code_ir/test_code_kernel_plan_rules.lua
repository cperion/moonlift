package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")

local T = pvm.context()
Schema(T)

local Rules = require("lalin.code_kernel_plan_rules")(T)

local function base()
    return {
        counted = true,
        has_func_id = true,
        has_func = true,
        has_rejects = false,
        has_closed_form = false,
        has_reduction = false,
        has_skeleton_result = false,
        closed_form_trip_unknown = false,
        not_counted_rejects = { "not-counted" },
        no_owner_rejects = { "no-owner" },
        rejects = {},
    }
end

do
    local c = base()
    c.counted = false
    c.has_func_id = false
    local selection, err = Rules:run("select_loop_kernel_plan", { loop = c }, "selection", "no Kernel loop plan selected")
    assert(selection ~= nil, tostring(err))
    assert(selection.kind == "no_plan", "uncounted loop must reject")
    assert(selection.rejects[1] == "not-counted", "uncounted loop must use counted-domain reject")
end

do
    local c = base()
    c.has_func_id = false
    local selection, err = Rules:run("select_loop_kernel_plan", { loop = c }, "selection", "no Kernel loop plan selected")
    assert(selection ~= nil, tostring(err))
    assert(selection.kind == "no_plan", "ownerless loop must reject")
    assert(selection.rejects[1] == "no-owner", "ownerless loop must use graph-owner reject")
end

do
    local c = base()
    c.has_rejects = true
    c.rejects = { "memory-reject", "effect-reject" }
    local selection, err = Rules:run("select_loop_kernel_plan", { loop = c }, "selection", "no Kernel loop plan selected")
    assert(selection ~= nil, tostring(err))
    assert(selection.kind == "no_plan", "loop rejects must prevent planning")
    assert(#selection.rejects == 2 and selection.rejects[2] == "effect-reject", "semantic rejects must be preserved")
end

do
    local c = base()
    c.has_closed_form = true
    c.has_reduction = true
    c.closed_form = "closed-form"
    c.reduction = "reduction"
    c.closed_form_trip_unknown = true
    local selection, err = Rules:run("select_loop_kernel_plan", { loop = c }, "selection", "no Kernel loop plan selected")
    assert(selection ~= nil, tostring(err))
    assert(selection.kind == "planned", "closed-form input must plan")
    assert(selection.result_kind == "closed_form", "closed form must win over reduction")
    assert(selection.closed_form == "closed-form", "closed-form fact must be returned")
    assert(selection.add_trip_unknown_proof == true, "trip-count proof bit must be carried")
end

do
    local c = base()
    c.has_reduction = true
    c.reduction = "reduction"
    local selection, err = Rules:run("select_loop_kernel_plan", { loop = c }, "selection", "no Kernel loop plan selected")
    assert(selection ~= nil, tostring(err))
    assert(selection.kind == "planned", "reduction input must plan")
    assert(selection.result_kind == "reduction", "reduction result must be selected")
    assert(selection.reduction == "reduction", "reduction fact must be returned")
end

do
    local c = base()
    c.has_skeleton_result = true
    c.skeleton_result = "void-copy"
    local selection, err = Rules:run("select_loop_kernel_plan", { loop = c }, "selection", "no Kernel loop plan selected")
    assert(selection ~= nil, tostring(err))
    assert(selection.kind == "planned", "skeleton input must plan")
    assert(selection.result_kind == "skeleton", "skeleton result must be selected")
    assert(selection.skeleton_result == "void-copy", "skeleton result must be returned")
end

do
    local c = base()
    local selection, err = Rules:run("select_loop_kernel_plan", { loop = c }, "selection", "no Kernel loop plan selected")
    assert(selection ~= nil, tostring(err))
    assert(selection.kind == "planned", "plain counted input must plan")
    assert(selection.result_kind == "original_control", "original-control result must be the semantic default")
end

io.write("lalin code_kernel_plan_rules ok\n")
