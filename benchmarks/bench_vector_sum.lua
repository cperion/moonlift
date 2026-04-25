-- Validate ASDL vectorization path on a vectorizable reduction.
-- Emits: moonlift_scalar, moonlift_vec, moonlift_vec_uN

package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path
if not package.preload["gps.asdl_lexer"] then
    package.preload["gps.asdl_lexer"] = function() return require("asdl_lexer") end
    package.preload["gps.asdl_parser"] = function() return require("asdl_parser") end
    package.preload["gps.asdl_context"] = function() return require("asdl_context") end
end

local ffi = require("ffi")
local pvm = require("pvm")
local A = require("moonlift.asdl")
local Source = require("moonlift.source")
local VecFacts = require("moonlift.vector_facts")
local VecToBack = require("moonlift.vector_to_back")
local J = require("moonlift.jit")

local quick = arg and arg[1] == "quick"
local N = tonumber(os.getenv("MOONLIFT_VECTOR_SUM_N") or (quick and "1000000" or "100000000"))
local WARMUP = tonumber(os.getenv("MOONLIFT_VECTOR_SUM_WARMUP") or (quick and "1" or "3"))
local ITERS = tonumber(os.getenv("MOONLIFT_VECTOR_SUM_ITERS") or (quick and "1" or "5"))
local LANES = tonumber(os.getenv("MOONLIFT_VECTOR_SUM_LANES") or "2")
local UNROLL = tonumber(os.getenv("MOONLIFT_VECTOR_SUM_UNROLL") or "4")
local CHUNK = tonumber(os.getenv("MOONLIFT_VECTOR_SUM_CHUNK") or "1048576")

local SRC = [[
export func sum_scalar(n: index) -> index
    for i in 0..n with acc: index = 0 do
        let term: index = (i * 1664525 + 1013904223) & 1023
        next acc = acc + term
    end
    return acc
end
]]

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

local function result_string(v)
    return (tostring(v):gsub("ULL$", ""):gsub("LL$", ""))
end

local T = pvm.context()
A.Define(T)
local S = Source.Define(T)
local VF = VecFacts.Define(T)
local VB = VecToBack.Define(T)
local jit_api = J.Define(T)
local jit = jit_api.jit()
local Back = T.MoonliftBack

local scalar_artifact = S.compile(SRC, nil, nil, nil, jit)
local scalar = ffi.cast("intptr_t (*)(intptr_t)", scalar_artifact:getpointer(Back.BackFuncId("sum_scalar")))

local sem = S.sem_module((SRC:gsub("sum_scalar", "sum_vec_source")))
local loop = sem.items[1].func.body[1].loop
local vec_module = pvm.one(VF.vector_module(sem, nil, LANES, 1))
local vec_back = pvm.one(VB.lower_module(vec_module, "sum_vec"))
local vec_artifact = jit:compile(vec_back)
local vec = ffi.cast("intptr_t (*)(intptr_t)", vec_artifact:getpointer(Back.BackFuncId("sum_vec")))
local unroll_module = pvm.one(VF.vector_module(sem, nil, LANES, UNROLL))
local unroll_back = pvm.one(VB.lower_module(unroll_module, "sum_vec_u" .. UNROLL))
local unroll_artifact = jit:compile(unroll_back)
local vec_u = ffi.cast("intptr_t (*)(intptr_t)", unroll_artifact:getpointer(Back.BackFuncId("sum_vec_u" .. UNROLL)))
local chunk_module = pvm.one(VF.vector_module(sem, nil, 4, UNROLL, CHUNK))
local chunk_back = pvm.one(VB.lower_module(chunk_module, "sum_vec_i32c_u" .. UNROLL))
local chunk_artifact = jit:compile(chunk_back)
local vec_c = ffi.cast("intptr_t (*)(intptr_t)", chunk_artifact:getpointer(Back.BackFuncId("sum_vec_i32c_u" .. UNROLL)))

local scalar_result = scalar(N)
local vec_result = vec(N)
local vec_u_result = vec_u(N)
local vec_c_result = vec_c(N)
assert(scalar_result == vec_result, "vector result mismatch: " .. result_string(scalar_result) .. " vs " .. result_string(vec_result))
assert(scalar_result == vec_u_result, "unrolled vector result mismatch: " .. result_string(scalar_result) .. " vs " .. result_string(vec_u_result))
assert(scalar_result == vec_c_result, "chunked i32 vector result mismatch: " .. result_string(scalar_result) .. " vs " .. result_string(vec_c_result))

local scalar_time = bench(scalar, N)
local vec_time = bench(vec, N)
local vec_u_time = bench(vec_u, N)
local vec_c_time = bench(vec_c, N)

io.write(string.format("moonlift_scalar %.9f %s\n", scalar_time, result_string(scalar(N))))
io.write(string.format("moonlift_vec%d %.9f %s\n", LANES, vec_time, result_string(vec(N))))
io.write(string.format("moonlift_vec%d_u%d %.9f %s\n", LANES, UNROLL, vec_u_time, result_string(vec_u(N))))
io.write(string.format("moonlift_i32x4_u%d %.9f %s\n", UNROLL, vec_c_time, result_string(vec_c(N))))

if os.getenv("MOONLIFT_VECTOR_SUM_DISASM") == "1" then
    io.stderr:write(vec_artifact:disasm("sum_vec", { bytes = 320 }) .. "\n")
    io.stderr:write(unroll_artifact:disasm("sum_vec_u" .. UNROLL, { bytes = 480 }) .. "\n")
    io.stderr:write(chunk_artifact:disasm("sum_vec_i32c_u" .. UNROLL, { bytes = 640 }) .. "\n")
end

scalar_artifact:free()
vec_artifact:free()
unroll_artifact:free()
chunk_artifact:free()
