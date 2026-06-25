-- Benchmark: LLPVM bytecode image load + native drain.
--
-- This exercises the real boundary:
--   Lua authoring API -> LLPV bytecode -> llpvm_load_program -> native tape
--   -> llpvm_drain.
--
-- Run:
--   luajit benchmarks/bench_llpvm_image_load.lua
--   luajit benchmarks/bench_llpvm_image_load.lua full

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/llpvm/native/?.lua;./lua/llpvm/native/?.mlua;" .. package.path

local lalin = require("lalin")
local ffi = require("ffi")
local bit = require("bit")
local ll = require("llpvm")
local pvm = require("lalin.pvm")
local Runtime = require("llpvm.runtime_ffi")

ffi.cdef [[
typedef long time_t;
struct timespec { time_t tv_sec; long tv_nsec; };
int clock_gettime(int clk_id, struct timespec *tp);
]]

local CLOCK_MONOTONIC = 1
local ts = ffi.new("struct timespec[1]")

local function now()
    if ffi.C.clock_gettime(CLOCK_MONOTONIC, ts) == 0 then
        return tonumber(ts[0].tv_sec) + tonumber(ts[0].tv_nsec) * 1e-9
    end
    return os.clock()
end

local function stats(samples)
    table.sort(samples)
    local n = #samples
    local sum = 0
    for i = 1, n do sum = sum + samples[i] end
    return {
        min = samples[1],
        median = samples[math.floor((n + 1) / 2)],
        avg = sum / n,
    }
end

local function make_program(op_count)
    local vm = ll.vm {}
    local Expr = vm.language "Expr"
    local Node = Expr "Node"
    Node.Int = { value = lalin.i64 }
    Node.Add = { left = Node, right = Node }
    local world = Expr:world()
    local ops = {}
    for i = 1, op_count do
        if i % 8 == 0 and i > 2 then
            ops[i] = world.Node.Add { left = ops[i - 1], right = ops[i - 2] }
        else
            ops[i] = world.Node.Int { value = i }
        end
    end
    local tape = world:seq(ops)
    local program = vm.program { tape }
    return program, ops
end

local bench_sink = 0

local function consume_array(xs)
    local n = #xs
    local acc = n
    for i = 1, n do
        if xs[i] ~= nil then
            acc = acc + i
        end
    end
    bench_sink = bit.bxor(bench_sink, acc)
    return acc
end

local mode = arg and arg[1] or "quick"
local full = mode == "full"
local cases = full and { 16, 128, 1024, 4096 } or { 16, 128, 1024 }
local rounds = tonumber(os.getenv("LALIN_BENCH_ROUNDS") or (full and "200" or "50"))
local samples_n = tonumber(os.getenv("LALIN_BENCH_SAMPLES") or (full and "9" or "5"))

io.write("building LLPVM runtime .so ... ")
io.flush()
local build_t0 = now()
local rt = Runtime.build {
    cleanup = true,
}
print(string.format("%.3fs", now() - build_t0))

print(string.format("llpvm image load benchmark mode=%s rounds=%d samples=%d", mode, rounds, samples_n))
print("llpvm load borrows a caller-owned immutable byte buffer")
print("drain-only preloads tapes first, then measures native drain separately")

for _, op_count in ipairs(cases) do
    local program, authored_ops = make_program(op_count)

    local encode_t0 = now()
    local image = program:bytecode()
    local encode_s = now() - encode_t0
    local image_buf = ffi.new("uint8_t[?]", #image)
    ffi.copy(image_buf, image, #image)

    local pvm_drain_samples = {}
    local pvm_into_samples = {}
    local pvm_checksum = 0
    for sample = 1, samples_n do
        local t0 = now()
        for _ = 1, rounds do
            local out = pvm.drain(pvm.seq(authored_ops))
            pvm_checksum = pvm_checksum + consume_array(out)
        end
        pvm_drain_samples[sample] = now() - t0
    end
    for sample = 1, samples_n do
        local t0 = now()
        for _ = 1, rounds do
            local out = {}
            local g, p, c = pvm.seq(authored_ops)
            pvm.drain_into(g, p, c, out)
            pvm_checksum = pvm_checksum + consume_array(out)
        end
        pvm_into_samples[sample] = now() - t0
    end

    local vm = rt:open {
        initial_abi_cap = 8,
        initial_world_cap = 8,
        initial_op_cap = op_count * rounds + 8,
        initial_buffer_cap = rounds * (samples_n * 3 + 2) + 16,
        initial_tape_cap = rounds * (samples_n * 4 + 2) + 16,
        initial_program_cap = rounds * (samples_n * 4 + 2) + 16,
        cache_bytes = 4096,
    }

    local warm_st, warm_tape = vm:load_program_buffer(image_buf, #image)
    warm_st:assert("warm llpvm_load_program")
    local warm_drain, warm_buffer = vm:drain(warm_tape)
    warm_drain:assert("warm llpvm_drain")
    assert(warm_buffer ~= 0, "warm drain produced no buffer")

    local raw_load_drain_samples = {}
    local checksum = 0
    for sample = 1, samples_n do
        local t0 = now()
        for _ = 1, rounds do
            local st, tape = vm:load_program_buffer(image_buf, #image)
            st:assert("raw llpvm_load_program")
            local drain_st, buffer = vm:drain(tape)
            drain_st:assert("raw llpvm_drain")
            checksum = checksum + tape + buffer
        end
        raw_load_drain_samples[sample] = now() - t0
    end

    local load_only_samples = {}
    local load_tapes = ffi.new("uint32_t[?]", rounds)
    for sample = 1, samples_n do
        local t0 = now()
        for i = 0, rounds - 1 do
            local st, tape = vm:load_program_buffer(image_buf, #image)
            st:assert("load-only llpvm_load_program")
            load_tapes[i] = tape
            checksum = checksum + tape
        end
        load_only_samples[sample] = now() - t0
    end

    local preload = ffi.new("uint32_t[?]", rounds * samples_n)
    for i = 0, rounds * samples_n - 1 do
        local st, tape = vm:load_program_buffer(image_buf, #image)
        st:assert("preload llpvm_load_program")
        preload[i] = tape
    end

    local drain_only_samples = {}
    local count_only_samples = {}
    for sample = 1, samples_n do
        local t0 = now()
        local base = (sample - 1) * rounds
        for i = 0, rounds - 1 do
            local drain_st, buffer = vm:drain(preload[base + i])
            drain_st:assert("drain-only llpvm_drain")
            checksum = checksum + buffer
        end
        drain_only_samples[sample] = now() - t0
    end
    for sample = 1, samples_n do
        local t0 = now()
        local base = (sample - 1) * rounds
        for i = 0, rounds - 1 do
            local count_st, count = vm:drain_count(preload[base + i])
            count_st:assert("count-only llpvm_drain_count")
            checksum = checksum + count
        end
        count_only_samples[sample] = now() - t0
    end

    local report = vm:report()
    vm:close()

    local raw_s = stats(raw_load_drain_samples)
    local load_s = stats(load_only_samples)
    local drain_s = stats(drain_only_samples)
    local count_s = stats(count_only_samples)
    local pvm_s = stats(pvm_drain_samples)
    local pvm_into_s = stats(pvm_into_samples)
    local ops_per_round = op_count
    local total_ops = rounds * ops_per_round
    local raw_ops_s = total_ops / raw_s.median
    local raw_ns_op = raw_s.median * 1e9 / total_ops
    local load_ops_s = total_ops / load_s.median
    local load_ns_op = load_s.median * 1e9 / total_ops
    local drain_ops_s = total_ops / drain_s.median
    local drain_ns_op = drain_s.median * 1e9 / total_ops
    local count_ops_s = total_ops / count_s.median
    local count_ns_op = count_s.median * 1e9 / total_ops
    local pvm_median_ops_s = total_ops / pvm_s.median
    local pvm_median_ns_op = pvm_s.median * 1e9 / total_ops
    local pvm_into_median_ops_s = total_ops / pvm_into_s.median
    local pvm_into_median_ns_op = pvm_into_s.median * 1e9 / total_ops
    print(string.format(
        "case ops=%d image_bytes=%d encode_ms=%.3f stores_ops=%d checksum=%d",
        op_count,
        #image,
        encode_s * 1000,
        report.ops,
        checksum
    ))
    print(string.format(
        "llpvm raw     load+drain median_ms=%.3f Mops_s=%.2f ns_op=%.2f",
        raw_s.median * 1000,
        raw_ops_s / 1e6,
        raw_ns_op
    ))
    print(string.format(
        "llpvm raw     load-only  median_ms=%.3f Mops_s=%.2f ns_op=%.2f",
        load_s.median * 1000,
        load_ops_s / 1e6,
        load_ns_op
    ))
    print(string.format(
        "llpvm raw     drain-only median_ms=%.3f Mops_s=%.2f ns_op=%.2f",
        drain_s.median * 1000,
        drain_ops_s / 1e6,
        drain_ns_op
    ))
    print(string.format(
        "llpvm raw     count-only median_ms=%.3f Mops_s=%.2f ns_op=%.2f",
        count_s.median * 1000,
        count_ops_s / 1e6,
        count_ns_op
    ))
    print(string.format(
        "pvm  ops=%d drain_median_ms=%.3f drain_Mops_s=%.2f drain_ns_op=%.2f into_median_ms=%.3f into_Mops_s=%.2f into_ns_op=%.2f checksum=%d",
        op_count,
        pvm_s.median * 1000,
        pvm_median_ops_s / 1e6,
        pvm_median_ns_op,
        pvm_into_s.median * 1000,
        pvm_into_median_ops_s / 1e6,
        pvm_into_median_ns_op,
        pvm_checksum
    ))
    print(string.format(
        "RESULT ops=%d image_bytes=%d rounds=%d samples=%d encode_s=%.9f raw_load_drain_median_s=%.9f raw_load_only_median_s=%.9f raw_drain_only_median_s=%.9f raw_count_only_median_s=%.9f pvm_drain_median_s=%.9f pvm_into_median_s=%.9f raw_load_drain_ops_s=%.3f raw_load_only_ops_s=%.3f raw_drain_only_ops_s=%.3f raw_count_only_ops_s=%.3f pvm_drain_ops_s=%.3f pvm_into_ops_s=%.3f",
        op_count, #image, rounds, samples_n, encode_s,
        raw_s.median, load_s.median, drain_s.median, count_s.median,
        pvm_s.median, pvm_into_s.median,
        raw_ops_s, load_ops_s, drain_ops_s, count_ops_s,
        pvm_median_ops_s, pvm_into_median_ops_s
    ))
end

rt:close()
