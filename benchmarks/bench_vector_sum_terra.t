-- Terra scalar equivalent for vectorization-path validation.

local quick = arg and arg[1] == "quick"
local N = tonumber(os.getenv("TERRA_VECTOR_SUM_N") or (quick and "1000000" or "100000000"))
local WARMUP = tonumber(os.getenv("TERRA_VECTOR_SUM_WARMUP") or (quick and "1" or "3"))
local ITERS = tonumber(os.getenv("TERRA_VECTOR_SUM_ITERS") or (quick and "1" or "5"))

local terra sum_terra(n: int64): int64
    var i: int64 = 0
    var acc: int64 = 0
    while i < n do
        var term: int64 = (i * 1664525 + 1013904223) and 1023
        i = i + 1
        acc = acc + term
    end
    return acc
end

local function bench(f, n)
    for _ = 1, WARMUP do f(n) end
    local best = math.huge
    for _ = 1, ITERS do
        local t0 = os.clock()
        f(n)
        local dt = os.clock() - t0
        if dt < best then best = dt end
    end
    return best
end

sum_terra:compile()
local t = bench(sum_terra, N)
io.write(string.format("terra %.9f %d\n", t, sum_terra(N)))
