package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Measure = require("lalin.luajit_measure")

local result = Measure.measure_case {
    name = "small counted loop",
    samples = 2,
    rounds = 1,
    warmup = 1,
    jit_opts = { "hotloop=1", "hotexit=1" },
    fn = function()
        local acc = 0
        for i = 1, 1000 do
            acc = acc + i
        end
        return acc
    end,
}

assert(result.name == "small counted loop")
assert(result.result == 500500)
assert(result.samples == 2)
assert(result.seconds.min >= 0)
assert(result.seconds.max >= result.seconds.min)
assert(result.trace.start >= result.trace.stop)
assert(type(Measure.format_result(result)) == "string")

io.write("lalin luajit_measure ok\n")
