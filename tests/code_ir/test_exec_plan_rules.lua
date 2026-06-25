package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")
local T = pvm.context()
Schema(T)
local Rules = require("lalin.exec_plan_rules")(T)

local function input(fields)
    local out = {
        stencil_selected = false,
        has_artifact = false,
        has_func = false,
        selected_reason = "selected",
        unselected_reason = "not selected",
        missing_artifact_reason = "missing artifact",
        missing_func_reason = "missing function",
    }
    for k, v in pairs(fields or {}) do out[k] = v end
    return out
end

local function select(fields)
    local selection, err = Rules:run("select_exec_fragment", { fragment = input(fields) }, "selection", "no exec fragment selected")
    assert(selection ~= nil, tostring(err))
    return selection
end

local stencil = select {
    stencil_selected = true,
    has_artifact = true,
    has_func = true,
    selected_reason = "materialize",
}
assert(stencil.kind == Rules.kind.stencil)
assert(stencil.reason == "materialize")

local unselected = select {
    stencil_selected = false,
    unselected_reason = "entry skipped",
}
assert(unselected.kind == Rules.kind.skip)
assert(unselected.reason == "entry skipped")

local missing_artifact = select {
    stencil_selected = true,
    has_artifact = false,
    missing_artifact_reason = "artifact absent",
}
assert(missing_artifact.kind == Rules.kind.skip)
assert(missing_artifact.reason == "artifact absent")

local missing_func = select {
    stencil_selected = true,
    has_artifact = true,
    has_func = false,
    missing_func_reason = "function absent",
}
assert(missing_func.kind == Rules.kind.skip)
assert(missing_func.reason == "function absent")
