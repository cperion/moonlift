-- Legacy entrypoint kept for convenience.
-- The old in-process parser pipeline in this file drifted from current Parse API.
-- Delegate to the maintained subprocess-safe harness.

dofile("benchmarks/bench_cranelift_vs_dynasm_harness.lua")
