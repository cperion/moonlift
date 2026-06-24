package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")

local T = pvm.context()
Schema(T)

local Rules = require("moonlift.code_schedule_plan_rules")(T)

local function cap(executable, rejects)
    return { executable = executable, kind = executable and "ok" or "reject", rejects = rejects or {} }
end

local function base()
    return {
        has_vector_candidate = false,
        vector_executable = false,
        vector_kind = "vector",
        vector_capability = cap(false, { "vector-reject" }),
        vector_rejects = { "vector-reject" },
        scalar_executable = true,
        scalar_kind = "scalar",
        scalar_capability = cap(true),
        scalar_rejects = {},
    }
end

do
    local c = base()
    c.has_vector_candidate = true
    c.vector_executable = true
    c.vector_capability = cap(true)
    local selection, err = Rules.select(c)
    assert(selection ~= nil, tostring(err))
    assert(selection.kind == "planned", "executable vector candidate must plan")
    assert(selection.schedule_kind == "vector", "vector schedule must win")
    assert(#selection.rejected_alternatives == 0, "winning vector schedule has no rejected alternatives")
end

do
    local c = base()
    c.has_vector_candidate = true
    c.vector_executable = false
    c.scalar_executable = true
    local selection, err = Rules.select(c)
    assert(selection ~= nil, tostring(err))
    assert(selection.kind == "planned", "scalar must plan after vector rejection")
    assert(selection.schedule_kind == "scalar", "scalar schedule must be selected after vector rejection")
    assert(selection.rejected_alternatives[1] == "vector-reject", "vector rejects must be retained as alternatives")
end

do
    local c = base()
    c.has_vector_candidate = false
    c.scalar_kind = "closed_form"
    local selection, err = Rules.select(c)
    assert(selection ~= nil, tostring(err))
    assert(selection.kind == "planned", "non-vector scalar/closed-form candidate must plan")
    assert(selection.schedule_kind == "closed_form", "closed-form schedule kind must be preserved")
    assert(#selection.rejected_alternatives == 0, "non-vector plan has no vector alternatives")
end

do
    local c = base()
    c.has_vector_candidate = true
    c.vector_executable = false
    c.scalar_executable = false
    c.scalar_rejects = { "scalar-reject" }
    local selection, err = Rules.select(c)
    assert(selection ~= nil, tostring(err))
    assert(selection.kind == "no_plan", "failed vector plus failed scalar must reject")
    assert(selection.rejects[1] == "scalar-reject", "no-plan rejects must come from executable fallback")
end

do
    local c = base()
    c.has_vector_candidate = false
    c.scalar_executable = false
    c.scalar_rejects = { "closed-reject" }
    local selection, err = Rules.select(c)
    assert(selection ~= nil, tostring(err))
    assert(selection.kind == "no_plan", "failed scalar/closed-form candidate must reject")
    assert(selection.rejects[1] == "closed-reject", "scalar rejects must be preserved")
end

io.write("moonlift code_schedule_plan_rules ok\n")
