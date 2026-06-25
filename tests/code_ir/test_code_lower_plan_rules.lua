package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")
local T = pvm.context()
Schema(T)
local Rules = require("lalin.code_lower_plan_rules")(T)

local function input(fields)
    local out = {
        has_kernel = false,
        has_kernel_no_plan = false,
        schedule_planned = false,
        schedule_closed_form = false,
        has_closed_form = false,
        closed_form = nil,
        closed_form_missing_reason = "missing closed form",
        no_schedule_reason = "missing schedule",
        kernel_no_plan_reason = "kernel rejected",
    }
    for k, v in pairs(fields or {}) do out[k] = v end
    return out
end

local function select(fields)
    local selection, err = Rules:run("select_lower_fragment", { fragment = input(fields) }, "selection", "no lower fragment selected")
    assert(selection ~= nil, err)
    return selection
end

local cf = { id = { text = "cf:add" } }

local closed = select {
    has_kernel = true,
    schedule_planned = true,
    schedule_closed_form = true,
    has_closed_form = true,
    closed_form = cf,
}
assert(closed.kind == Rules.kind.closed_form)
assert(closed.closed_form == cf)

local missing_cf = select {
    has_kernel = true,
    schedule_planned = true,
    schedule_closed_form = true,
    has_closed_form = false,
    closed_form_missing_reason = "closed-form schedule lacks fact",
}
assert(missing_cf.kind == Rules.kind.fallback)
assert(missing_cf.reason == "closed-form schedule lacks fact")

local kernel = select {
    has_kernel = true,
    schedule_planned = true,
    schedule_closed_form = false,
}
assert(kernel.kind == Rules.kind.kernel)

local no_schedule = select {
    has_kernel = true,
    schedule_planned = false,
    no_schedule_reason = "no schedule selected",
}
assert(no_schedule.kind == Rules.kind.fallback)
assert(no_schedule.reason == "no schedule selected")

local rejected = select {
    has_kernel = false,
    has_kernel_no_plan = true,
    kernel_no_plan_reason = "kernel plan rejected",
}
assert(rejected.kind == Rules.kind.fallback)
assert(rejected.reason == "kernel plan rejected")

local none = select {
    has_kernel = false,
    has_kernel_no_plan = false,
}
assert(none.kind == Rules.kind.none)
