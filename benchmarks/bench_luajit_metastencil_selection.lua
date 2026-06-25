package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")

local T = pvm.context()
Schema(T)

local Core = T.LalinCore
local Code = T.LalinCode
local Flow = T.LalinFlow
local Graph = T.LalinGraph
local Value = T.LalinValue
local Stencil = T.LalinStencil
local Plan = require("lalin.stencil_artifact_plan")(T)
local Meta = require("lalin.stencil_metastencil")(T)

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)

local function iconst(raw)
    return Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt(tostring(raw))))
end

local function reduction(kind, init)
    local domain = Flow.FlowDomainLoop(Graph.GraphLoopId("loop:bench_meta"))
    return Value.ReductionFact(
        Value.AlgebraFactId("reduction:bench_meta"),
        domain,
        Code.CodeValueId("v:acc"),
        kind,
        iconst(init),
        Value.ValueExprValue(Code.CodeValueId("v:item")),
        i32,
        sem,
        nil,
        Value.AlgebraProofFlow(domain, "metastencil benchmark reduction")
    )
end

local function input(name)
    return Plan.input_expr(name)
end

local function apply_artifact(tag)
    return Plan.apply_n_array_artifact({
        tag = tag,
        result_ty = i32,
        inputs = {
            { name = "x1", ty = i32 },
            { name = "x2", ty = i32 },
        },
        expr = Plan.apply_binary_expr(Stencil.StencilBinaryAdd, input("x1"), input("x2"), i32, { int_semantics = sem }),
        step_num = 1,
    })
end

local function reduce_artifact(tag)
    return Plan.reduce_n_array_artifact(reduction(Value.ReductionAdd, 0), nil, {
        tag = tag,
        item_ty = i32,
        result_ty = i32,
        inputs = { { name = "x", ty = i32 } },
        expr = input("x"),
        step_num = 1,
    })
end

local x1 = Meta.external_port("x1", Stencil.StencilMetastencilPortInput, i32)
local x2 = Meta.external_port("x2", Stencil.StencilMetastencilPortInput, i32)

local descriptors = {}
for i = 1, 16 do
    local a = Meta.node_from_artifact("a" .. tostring(i), apply_artifact("bench_a" .. tostring(i)))
    local r = Meta.node_from_artifact("r" .. tostring(i), reduce_artifact("bench_r" .. tostring(i)))
    descriptors[#descriptors + 1] = Meta.descriptor(
        "meta:bench:" .. tostring(i),
        { x1, x2 },
        { a, r },
        {
            Meta.wire("w:" .. tostring(i) .. ":x1", nil, "x1", a.id, "x1", i32),
            Meta.wire("w:" .. tostring(i) .. ":x2", nil, "x2", a.id, "x2", i32),
            Meta.wire("w:" .. tostring(i) .. ":fold", a.id, "dst", r.id, "x", i32),
        },
        r.artifact.instance.abi
    )
end

local candidates = {}
for i, desc in ipairs(descriptors) do candidates[i] = Meta.candidate(desc) end

local iterations = tonumber(os.getenv("LALIN_META_BENCH_ITERS") or "50000")
local t0 = os.clock()
local selected
for _ = 1, iterations do
    selected = Meta.select_longest_legal_cover(candidates)
end
local elapsed = os.clock() - t0

assert(selected.candidate.covered_nodes == 2)
io.write(string.format(
    "metastencil selection: candidates=%d iterations=%d elapsed=%.6fs selections/s=%.0f\n",
    #candidates,
    iterations,
    elapsed,
    iterations / elapsed
))
