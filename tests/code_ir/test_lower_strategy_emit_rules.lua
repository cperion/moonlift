package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")
local T = pvm.context()
Schema(T)
local Rules = require("lalin.lower_strategy_emit_rules")(T)

local function input(fields)
    local out = {
        strategy_code = false,
        strategy_kernel = false,
        strategy_closed_form = false,
        has_schedule = false,
        schedule_vector = false,
        missing_schedule_reason = "missing schedule",
        unsupported_reason = "unsupported strategy",
    }
    for k, v in pairs(fields or {}) do out[k] = v end
    return out
end

local function select(fields)
    local selection, err = Rules:run("select_lower_emit", { emit = input(fields) }, "selection", "no lower emission selected")
    assert(selection ~= nil, tostring(err))
    return selection
end

assert(select { strategy_code = true }.kind == Rules.kind.code)
assert(select { strategy_closed_form = true }.kind == Rules.kind.closed_form)
assert(select { strategy_kernel = true, has_schedule = true, schedule_vector = false }.kind == Rules.kind.scalar_kernel)
assert(select { strategy_kernel = true, has_schedule = true, schedule_vector = true }.kind == Rules.kind.vector_kernel)

local missing = select {
    strategy_kernel = true,
    has_schedule = false,
    missing_schedule_reason = "kernel schedule is absent",
}
assert(missing.kind == Rules.kind.missing_schedule)
assert(missing.reason == "kernel schedule is absent")

local unsupported = select {
    unsupported_reason = "foreign strategy",
}
assert(unsupported.kind == Rules.kind.unsupported)
assert(unsupported.reason == "foreign strategy")
