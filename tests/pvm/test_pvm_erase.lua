package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Erase = require("moonlift.pvm_erase")

local fixture = [[
local pvm = require("moonlift.pvm")

local A = { kind = "A" }
local B = { kind = "B" }

local function bind_context()
    local scalar_phase = pvm.phase("fixture_scalar", function(node)
        if pvm.classof(node) == A then return node.value end
        return "miss"
    end, { node_cache = "none", args_cache = "none" })

    local cached_phase = pvm.phase("fixture_cached", function(node)
        return node.value
    end)

    local dispatch_phase = pvm.phase("fixture_dispatch", {
        [A] = function(node)
            return pvm.once(node.value)
        end,
        [B] = function(node)
            return pvm.empty()
        end,
    })

    local function scalar(node)
        return pvm.one(scalar_phase(node))
    end

    local function cached(node)
        return cached_phase:one_uncached(node)
    end

    local function dispatch_one(node)
        return pvm.one(dispatch_phase(node))
    end

    local function dispatch_many(node)
        return dispatch_phase:drain_uncached(node)
    end

    return {
        A = A,
        B = B,
        scalar = scalar,
        cached = cached,
        dispatch_one = dispatch_one,
        dispatch_many = dispatch_many,
    }
end

return bind_context
]]

local phase_source, report = Erase.transform_source(fixture, { path = "fixture.lua" })

assert(report.erased_count == 3, Erase.report_string(report))
assert(report.rewritten_one_calls == 2, "expected pvm.one call rewrites")
assert(report.rewritten_method_calls == 2, "expected uncached method rewrites")
assert(not phase_source:match("moonlift%.pvm"), "phase fixture should not require moonlift.pvm")
assert(not phase_source:match("pvm%."), "phase fixture should not reference pvm")
assert(not phase_source:match("moonlift%.phase_"), "phase fixture should not use a runtime shim")
assert(phase_source:match("local schema = require%(\"moonlift%.schema_runtime\"%)"), "phase fixture should use schema runtime")
assert(phase_source:match("local function single%(value%)"), "phase fixture should use local output helpers")
assert(phase_source:match("local function scalar_phase%(node%)"), "scalar phase should become a direct function")
assert(phase_source:match("local function dispatch_phase%(node, %.%.%.%)"), "dispatch phase should become a direct dispatcher")

local chunk = assert(loadstring(phase_source, "@fixture_phase.lua"))
local mod = chunk()()

local function node(cls, value)
    return setmetatable({ value = value }, { __class = cls })
end

local a = node(mod.A, "ok")
assert(mod.scalar(a) == "ok")
assert(mod.cached(a) == "ok")
assert(mod.dispatch_one(a) == "ok")
local many = mod.dispatch_many(a)
assert(#many == 1 and many[1] == "ok")

local moonlift_phase_refs = assert(io.popen("rg -n 'pvm\\.phase\\(' lua/moonlift --glob '!pvm.lua' --glob '!pvm_erase.lua'", "r"))
local leaked = moonlift_phase_refs:read("*a") or ""
moonlift_phase_refs:close()
assert(leaked == "", "moonlift production modules should be switched away from pvm.phase:\n" .. leaked)

io.write("pvm erase ok\n")
