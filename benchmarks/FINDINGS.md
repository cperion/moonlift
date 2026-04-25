# Moonlift benchmark findings

This is a small, current snapshot from the scalar benchmark track. Treat numbers as
local machine observations, not stable promises.

The purpose is architectural: identify where explicit Moonlift source/ASDL shape
helps the existing `Surface -> Elab -> Sem -> Back -> Artifact` path, and where
we are merely depending on Cranelift to rediscover intent.

## Current full shape run

Command:

```bash
cargo build --manifest-path moonlift/Cargo.toml --release
luajit moonlift/benchmarks/bench_moonlift_shapes.lua
```

Observed run:

```text
shape                  generic                        time moonlift-shaped                time   speedup
---------------------- ------------------------ ---------- ------------------------ ---------- ---------
sum range domain       sum_while_index           63.546 ms sum_for_index             63.705 ms     1.00x
collatz select         collatz_if              1051.867 ms collatz_select           962.415 ms     1.09x
mandelbrot range       mandelbrot_while_i32      44.386 ms mandelbrot_for_index      43.624 ms     1.02x
poly range             poly_while_i32             2.243 ms poly_for_index             2.250 ms     1.00x
popcount intrinsic     popcount_manual_sum      101.466 ms popcount_intrinsic_sum     4.244 ms    23.91x
fib range domain       fib_while_i64             19.744 ms fib_for_index             19.990 ms     0.99x
gcd range domain       gcd_while_i64             85.269 ms gcd_for_index             82.548 ms     1.03x
switch structure       switch_if_chain          101.072 ms switch_expr_sum           78.034 ms     1.30x
```

## Findings by construct

### `popcount(...)`

This is the clearest win.

- Generic form: an inner loop shifts and masks one bit at a time.
- Moonlift-shaped form: `popcount(i)` lowers through the intrinsic path.
- Generated machine code includes `popcnt`.

This confirms the design rule: code-shape-sensitive operations should be explicit
ASDL/source constructs rather than hoping backend recovery finds them.

Inspect:

```bash
luajit moonlift/benchmarks/bench_moonlift_shapes.lua quick disasm popcount_intrinsic_sum
```

### `switch`

The explicit `switch` expression is materially better than a chain of statement
`if`s in the benchmark.

- Generic form: repeated `if` statements mutate a local `inc`.
- Moonlift-shaped form: `switch r do ... end` remains explicit through lowering.
- Generated machine code shows jump-table-style structure for the shaped version.

Inspect:

```bash
luajit moonlift/benchmarks/bench_moonlift_shapes.lua quick disasm switch_expr_sum
```

### `select(cond, a, b)`

`select` helps the Collatz kernel modestly on this run.

This is kernel-sensitive: `select` is a dataflow choice, so it may evaluate both
value expressions before selecting. Use it when branchless/dataflow semantics are
actually intended, not as a universal replacement for `if`.

### Range-domain `for`

Range-domain `for` is now mostly neutral in these scalar kernels.

Important correction: an earlier shape test made `for` look artificially slow by
computing `i + 1` inside the loop body while the `for` lowering also had to compute
the implicit next index. The current shape benchmark uses the natural range index
`i` directly for the range-domain variants.

Current conclusion:

- `for i in 0..n` is the clearer source construct for index domains.
- It does not yet produce a consistent scalar speedup by itself.
- The Terra gap on simple loops is therefore more likely backend optimization
  depth / loop optimization than missing source shape alone.

## Why the fair Terra benchmark is still faster

The largest simple-loop gap is not mainly a Moonlift source-shape problem.
For the `sum_loop`-style integer recurrence, Moonlift currently emits a clean
scalar loop through Cranelift, while Terra/LLVM vectorizes and unrolls it.

Moonlift disassembly for the shaped/generic sum loop is essentially scalar:

```asm
cmp    rsi,rdi
jb     body
...
imul   rdx,rdx,0x19660d
add    rdx,0x3c6ef35f
and    rdx,0x3ff
add    rax,rdx
jmp    header
```

Terra/LLVM, for the equivalent source, emits vector IR and AVX-512-style machine
code on this host:

```llvm
%vec.phi = phi <8 x i64> ...
%2 = mul <8 x i64> %vec.ind, splat (i64 525)
%7 = and <8 x i64> %3, splat (i64 1023)
%11 = add <8 x i64> %7, %vec.phi
%16 = call i64 @llvm.vector.reduce.add.v8i64(...)
```

```asm
vpmullq  %zmm2, %zmm1, %zmm12
vpaddq   ...
vpandq   ...
vpaddq   ...
```

That explains the very large `sum_loop` ratio: LLVM is doing loop
vectorization/reduction recognition; Cranelift is not recovering that shape from
our scalar `Back` facts.

For branchy or division-heavy kernels, the gap is smaller because there is less
SIMD/vector structure to recover. `gcd_sum` is close compared with the simple
vectorizable loops. `collatz` remains slower, but the shaped `select` version shows
that preserving branchless/dataflow choice can help modestly.

## Architectural implication

Do not expect backend auto-vectorization to be the main performance story.
Under the Moonlift/PVM discipline, if vector/data-parallel intent matters, it
should become explicit source/ASDL structure and lower to explicit `Back` facts.

Near-term options:

1. Keep scalar benchmarks as the fairness track and accept that Terra/LLVM will
   win vectorizable scalar loops for now.
2. Add explicit SIMD/vector source forms later if Moonlift wants to compete on
   vectorizable numeric kernels without relying on backend recovery.
3. Add explicit unroll/vector skeletons as ASDL forms only if they are real source
   semantics, not an ad hoc backend peephole.
4. Continue using intrinsics (`popcount`, `fma`, etc.) for operations where a
   scalar source construct should map to one machine instruction.

## Initial ASDL vector fact layer

There is now an initial prototype at:

- `moonlift/lua/moonlift/vector_facts.lua`
- `moonlift/test_vector_facts.lua`

It adds a `MoonliftVec` ASDL vocabulary for:

- lane-index facts
- invariant expression facts
- recursive lane-wise binary expression facts
- counted range-domain loop facts
- add-reduction facts
- explicit reject reasons
- an initial add-reduction vector plan

This is detection/planning only. It does not yet emit vector `Back` commands.
The current successful case is a simple range loop:

```moonlift
for i in 0..n with acc: index = 0 do
    let term: index = (i * 1664525 + 1013904223) & 1023
    next acc = acc + term
end
```

That loop now gathers a recursive lane-wise expression fact and an explicit
`VecAddReductionPlan(lanes=8, ...)`. Arbitrary `while` counted-loop recovery,
memory access/dependence facts, vector `Back` commands, and Cranelift vector IR
lowering are still pending.

## Current next targets

1. Keep the fair Terra benchmark scalar-equivalent.
2. Use `bench_moonlift_shapes.lua` to add best-Moonlift variants separately.
3. For any shaped win, inspect both `BackProgram` and disassembly to ensure the
   source distinction is preserved as an explicit backend fact.
4. For neutral/slower shaped forms, inspect whether the `Back` stream contains
   redundant aliases/block params or whether Cranelift simply does not optimize as
   deeply as LLVM/Terra for that kernel.
5. Lower the new `MoonliftVec` plan layer to explicit vector `Back` commands.
6. Add counted-`while` recovery, memory access/dependence facts, and scalar-tail
   plans only as explicit ASDL facts/plans, not Rust-side peepholes.
