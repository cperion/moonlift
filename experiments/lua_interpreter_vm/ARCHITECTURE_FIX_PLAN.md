# Lua Interpreter VM Architecture Fix Plan

Status: implementation plan / architectural refactor guide  
Scope: `experiments/lua_interpreter_vm`  
Primary goals:

1. Bring the VM implementation closer to the Lua 5.5 / PUC Lua opcode semantics described by `.vendor/Lua/lvm.c` and `.vendor/Lua/lopcodes.h`.
2. Remove the current hot-path architectural bottleneck: aggregate `Instr` / `Value` product copies in the interpreter loop.
3. Remove large-scale Moonlift source string concatenation and restore the typed, explicit-programming style that Moonlift exists to support.
4. Make benchmark results meaningful, stable, and useful for identifying real VM costs.

Non-goals for the first refactor pass:

- Do not implement the entire Lua language/compiler in one step.
- Do not optimize with a tracing/JIT compiler.
- Do not add speculative quickening until the baseline interpreter shape is correct and measurable.
- Do not hide semantic gaps with silent fallbacks.

---

## 1. Current situation

The Lua interpreter VM has made good progress:

- Lua 5.5 opcode numbering is mostly aligned with PUC Lua.
- `Value`, `Instr`, `Proto`, `Frame`, and `LuaThread` products exist.
- A Moonlift-native dispatch loop exists.
- Basic end-to-end execution works for simple bytecode such as `LOADK; RETURN`.
- A small native parser/compiler milestone exists for tiny `return`/`local` examples.
- A steady-state benchmark now reports tables and comparisons.

However, the implementation has two major architectural problems.

---

## 2. Architectural problem A: hot-path product copying

### 2.1 Symptom

Cheap bytecodes are slower than expected even after return teardown is amortized.

Representative benchmark shape:

```sh
MOONLIFT_VM_COMPARE_REFS=0 luajit experiments/lua_interpreter_vm/benchmarks/bench_vm_steady_state.lua
```

Typical results on the current implementation:

```text
RETURN-only overhead: ~14 ns/resume
LOADK:                ~5.5-6 ns/op
MOVE:                 ~6-6.5 ns/op
ADD:                  ~9.5-10 ns/op
```

The return boundary is cheap enough that it is not the main issue. The cost is in the dispatch/handler hot path.

### 2.2 Root cause

The interpreter loop copies entire products by value.

Current dispatch shape in `src/opcodes.lua`:

```moonlift
let cl: ptr(LClosure) = as(ptr(LClosure), cur_frame.closure.bits)
let code_ptr: ptr(Instr) = cl.proto.code + cur_pc
let instr: Instr = *code_ptr
let a: u16 = instr.a
let b: u16 = instr.b
let c: u16 = instr.c
let bx: u32 = instr.bx
let sbx: i32 = instr.sbx
switch instr.op do
    ...
end
```

`Instr` is a 20-byte product:

```moonlift
struct Instr op: u16; a: u16; b: u16; c: u16; k: u8; bx: u32; sbx: i32 end
```

Loading it by value can lower to an aggregate copy through stack memory. Disassembly confirms a large generated stack frame and a 20-byte copy in the dispatch path.

Observed generated-code pattern:

```asm
sub    rsp,0xed20
...
mov    edx,0x14       ; 20 bytes = sizeof(Instr)
...
call   ...            ; aggregate copy helper / memcpy-like path
...
movzx  ..., WORD PTR [rsp+...] ; fields read from copied Instr
```

The same pattern appears in handlers with `Value` products:

```moonlift
let lhs: Value = L.stack[base + as(index, b)]
let rhs: Value = L.stack[base + as(index, c)]
L.stack[base + as(index, a)] = { tag = ..., aux = ..., bits = ... }
```

`Value` is a 16-byte product:

```moonlift
struct Value tag: u32; aux: u32; bits: u64 end
```

Copying `Value` products is semantically clean, but it is the wrong architecture for the interpreter hot loop.

### 2.3 Why this is architectural, not micro-optimization

The VM is intended to be a register VM. The desired machine is:

```text
pc -> instruction pointer -> scalar field reads -> opcode handler -> scalar field writes
```

The current machine is closer to:

```text
pc -> copy decoded instruction product -> decode copied product
handler -> copy value products -> inspect copied products -> write value product
```

That shape bakes avoidable memory traffic into every opcode. Quickened opcodes cannot fix this because they still pay the same dispatch and product-copy architecture.

### 2.4 Target shape

Dispatch should use pointer/scalar reads:

```moonlift
let ip: ptr(Instr) = cl.proto.code + cur_pc
let op: u16 = ip.op
let a: u16 = ip.a
let b: u16 = ip.b
let c: u16 = ip.c
let k: u8 = ip.k
let bx: u32 = ip.bx
let sbx: i32 = ip.sbx
switch op do
    ...
end
```

Handlers should use `ptr(Value)` and scalar fields:

```moonlift
let src: ptr(Value) = L.stack + (base + as(index, b))
let dst: ptr(Value) = L.stack + (base + as(index, a))
dst.tag = src.tag
dst.aux = src.aux
dst.bits = src.bits
```

For numeric arithmetic:

```moonlift
let lhs: ptr(Value) = L.stack + (base + as(index, b))
let rhs: ptr(Value) = L.stack + (base + as(index, c))
let out: ptr(Value) = L.stack + (base + as(index, a))

if lhs.tag == TAG_INTEGER and rhs.tag == TAG_INTEGER then
    let x: i64 = as(i64, lhs.bits)
    let y: i64 = as(i64, rhs.bits)
    out.tag = TAG_INTEGER
    out.aux = 0
    out.bits = as(u64, x + y)
    jump next(... pc = pc + 2 ...)
end
```

---

## 3. Architectural problem B: string-concatenated Moonlift code

### 3.1 Symptom

`src/op_handlers.lua` contains large Lua functions that generate Moonlift source strings by concatenating fragments:

```lua
local function _body_both(expr)
    return "entry start()\n" ..
    "    let lhs: Value = L.stack[base + as(index, b)]\n" ..
    ...
    "        let r: i64 = " .. expr .. "\n" ..
    ...
end
```

`src/opcodes.lua` also constructs switch arms as text:

```lua
local function make_arm_src(entry, eff)
    local conts = build_continuation_src(eff)
    return string.format([[... emit %s(...) ...]], entry.handler, conts)
end
```

This is the bad pattern Moonlift was intended to remove.

### 3.2 Why this is architectural

String-concatenated Moonlift source has several costs:

1. **Semantics are hidden in strings**  
   Grep and structural tooling see Lua string assembly, not the actual VM semantics.

2. **Typed composition is bypassed**  
   Lua strings can represent invalid or subtly wrong Moonlift fragments until runtime compilation.

3. **Spec auditing becomes difficult**  
   It is hard to compare opcode-by-opcode behavior against PUC Lua when many handlers are generated indirectly.

4. **Refactors become unsafe**  
   Changing handler signatures or continuations requires editing text templates, not typed values.

5. **Design intent is lost**  
   Moonlift's explicit-programming style wants products, protocols, regions, blocks, and jumps to be first-class structure. String codegen turns the compiler back into a text preprocessor.

### 3.3 Acceptable use of Lua metaprogramming

Lua should still be used for:

- Building tables of constants.
- Registering modules.
- Selecting typed region values.
- Creating metadata for docs, tests, validation, and dispatch.
- Reusing explicit typed fragments.

Lua should not be used for:

- Concatenating expression strings such as `"x + y"` into Moonlift source.
- Constructing whole opcode bodies as raw text.
- Hiding semantic differences between opcodes inside textual templates.
- Making dispatch correctness depend on string formatting.

### 3.4 Target shape

Prefer explicit typed regions and small typed helper regions.

Instead of this family generator:

```lua
local function _body_both(expr)
    return "... let r: i64 = " .. expr .. " ..."
end
```

Use explicit typed regions:

```moonlift
region op_add(...; next: cont(...), error: cont(...))
entry start()
    emit arith_add_rr(L, frame, pc, base, top, a, b, c;
        next = next,
        fallback = add_fallback,
        error = error)
end
...
end
```

Or explicit Moonlift fragments per operation:

```moonlift
region arith_add_i64(x: i64, y: i64; done: cont(r: i64))
entry start()
    jump done(r = x + y)
end
end
```

The key rule is: **the operation must be a typed value or an explicit region, not a string expression inserted into a source template.**

---

## 4. Secondary problem: quickening is currently the wrong layer

### 4.1 Current quickening state

`src/quickening.lua` defines:

- `quicken_instruction`
- `deopt_instruction`
- `probe_gettable_cache`

The VM also defines quickened opcodes:

```lua
Op.LOADK_FAST = 100
Op.MOVE_FAST = 101
Op.ADD_NUM = 102
```

But the normal interpreter path does not currently call `quicken_instruction`. The benchmark manually installs quickened opcodes to measure them.

### 4.2 Why quickening does not help enough

Current quickened handlers still pay:

- the same switch dispatch cost;
- the same decoded `Instr` product-copy cost;
- the same `Value` aggregate load/store pattern;
- most of the same stack/register addressing cost.

Therefore quickening is trying to optimize after the dominant cost has already been paid.

### 4.3 Decision

Until the baseline VM is scalarized and spec-clean, quickening should be either:

1. **Quarantined** as experimental code not used by correctness benchmarks; or
2. **Temporarily removed from the main dispatch** to simplify spec auditing.

Recommended choice: quarantine it.

Keep the files if useful, but do not treat quickening as part of the baseline architecture until:

- dispatch no longer copies `Instr`;
- common handlers no longer copy `Value` products;
- opcode semantics are validated by focused tests;
- benchmark measurements show a clear remaining bottleneck that quickening can actually address.

---

## 5. Desired final architecture

The hot interpreter path should be:

```text
LuaThread -> current Frame -> Proto.code + pc
                               |
                               v
                         ptr(Instr)
                               |
                               v
                      scalar opcode fields
                               |
                               v
                         switch opcode
                               |
                               v
                handler reads/writes ptr(Value) fields
                               |
                               v
                    jump loop(frame, pc, base, top)
```

The VM should not do this in the hot path:

```text
copy Instr product -> decode copied product
copy Value product -> inspect copied product
store Value product through aggregate assignment
```

The source organization should be:

```text
products.lua          storage products only
constants.lua         Lua 5.5 constants/opcode numbers only
opcodes.lua           dispatch + opcode metadata only
op/                   spec-shaped opcode modules
  load.lua
  arithmetic.lua
  compare.lua
  table.lua
  call.lua
  loop.lua
  closure.lua
  misc.lua
regions_*.lua         reusable semantic engines
quickening.lua        quarantined/optional adaptive layer
validate.lua          bytecode/proto validation
SPEC_STATUS.md        opcode-by-opcode implementation state
```

---

## 6. Implementation plan

## Phase 0 — Freeze behavior and record the baseline

### 0.1 Keep existing passing tests

Run:

```sh
for t in experiments/lua_interpreter_vm/tests/*.lua; do
  luajit "$t" || exit 1
done
```

Current important tests:

- `tests/test_vm_components.lua`
- `tests/test_vm_e2e.lua`
- `tests/test_vm_integration.lua`
- `tests/test_vm_smoke.lua`
- `tests/test_parser_compile.lua`
- `tests/test_vm_opcode_semantics.lua`

### 0.2 Keep benchmark baseline

Run:

```sh
MOONLIFT_VM_COMPARE_REFS=0 \
luajit experiments/lua_interpreter_vm/benchmarks/bench_vm_steady_state.lua
```

Record:

- `RETURN` ns/resume
- `LOADI` ns/op
- `LOADK` ns/op
- `MOVE` ns/op
- `ADD` ns/op
- `ADD_NUM` ns/op

The benchmark is not the spec oracle. It is only for detecting architectural cost changes.

---

## Phase 1 — Build a real opcode spec matrix

Create:

```text
experiments/lua_interpreter_vm/SPEC_STATUS.md
```

For every opcode in `.vendor/Lua/lopcodes.h`, record:

```text
Opcode: OP_LOADKX
PUC reference: .vendor/Lua/lvm.c:1256
Moonlift handler: src/op_handlers.lua / later src/op/load.lua
Status: implemented / partial / stub / wrong / untested
Tests: tests/test_vm_opcode_semantics.lua::LOADKX
Notes: reads following EXTRAARG and advances pc by 2
```

Minimum fields:

| Field | Meaning |
|---|---|
| Opcode | PUC opcode name and number |
| PUC behavior | Short behavior summary |
| Handler | Moonlift region implementing it |
| Status | `implemented`, `partial`, `stub`, `wrong`, `untested` |
| Tests | Test file/case |
| Gaps | Known missing behavior |

### 1.1 Initial known gaps

Known incomplete or stubbed areas include:

- `MMBIN`, `MMBINI`, `MMBINK` metamethod fallback;
- `LEN`;
- `CONCAT`;
- `CALL` native-call path;
- `TAILCALL` full semantics;
- `CLOSURE`;
- `VARARG`, `GETVARG`, `VARARGPREP` full behavior;
- generic `TFORCALL`;
- full to-be-closed variable semantics;
- complete error/protected-call behavior;
- complete GC barriers and write barriers;
- complete table metamethod behavior.

The status matrix must say this explicitly. No silent “done enough” framing.

---

## Phase 2 — Scalarize instruction dispatch

### 2.1 Change dispatch field access

File:

```text
experiments/lua_interpreter_vm/src/opcodes.lua
```

Replace:

```moonlift
let code_ptr: ptr(Instr) = cl.proto.code + cur_pc
let instr: Instr = *code_ptr
let a: u16 = instr.a
...
switch instr.op do
```

With:

```moonlift
let ip: ptr(Instr) = cl.proto.code + cur_pc
let op: u16 = ip.op
let a: u16 = ip.a
let b: u16 = ip.b
let c: u16 = ip.c
let k: u8 = ip.k
let bx: u32 = ip.bx
let sbx: i32 = ip.sbx
switch op do
```

### 2.2 Handler signature decision

Current handler signature does not include `k`:

```moonlift
region op_xxx(..., a: u16, b: u16, c: u16, bx: u32, sbx: i32; ...)
```

Some handlers currently reload the instruction to read `k`:

```moonlift
let inst_ret: Instr = cl_ret.proto.code[pc]
if inst_ret.k ~= 0 then ... end
```

This repeats the aggregate-copy problem.

Change the standard handler signature to include `k`:

```moonlift
region op_xxx(..., a: u16, b: u16, c: u16, k: u8, bx: u32, sbx: i32; ...)
```

Then dispatch emits:

```moonlift
emit op_xxx(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, k, bx, sbx; ...)
```

### 2.3 Expected validation

After scalarizing dispatch:

- tests must pass;
- disassembly should no longer show a 20-byte aggregate copy at the top of dispatch;
- generated stack frame should shrink significantly;
- cheap-op benchmark should improve or at least not regress.

---

## Phase 3 — Introduce scalar `Value` helper regions

Create or extend:

```text
experiments/lua_interpreter_vm/src/regions_value.lua
```

Add helpers that operate on `ptr(Value)`:

```moonlift
region value_copy_ptr(dst: ptr(Value), src: ptr(Value); done: cont())
entry start()
    dst.tag = src.tag
    dst.aux = src.aux
    dst.bits = src.bits
    jump done()
end
end
```

```moonlift
region value_set_nil(dst: ptr(Value); done: cont())
entry start()
    dst.tag = TAG_NIL
    dst.aux = 0
    dst.bits = 0
    jump done()
end
end
```

```moonlift
region value_set_integer(dst: ptr(Value), x: i64; done: cont())
entry start()
    dst.tag = TAG_INTEGER
    dst.aux = 0
    dst.bits = as(u64, x)
    jump done()
end
end
```

```moonlift
region value_set_float(dst: ptr(Value), x: f64; done: cont())
entry start()
    dst.tag = TAG_NUM
    dst.aux = 0
    dst.bits = as(u64, x)
    jump done()
end
end
```

Do not over-abstract if helper calls cost too much. For the hottest opcodes, inline scalar field assignments inside handlers may be better. The architectural rule is about avoiding aggregate copies, not forcing helper calls everywhere.

---

## Phase 4 — Scalarize the first hot opcode set

Start with the opcodes used by current tests and benchmark.

### 4.1 `MOVE`

Current shape:

```moonlift
L.stack[base + as(index, a)] = L.stack[base + as(index, b)]
```

Target:

```moonlift
let dst: ptr(Value) = L.stack + (base + as(index, a))
let src: ptr(Value) = L.stack + (base + as(index, b))
dst.tag = src.tag
dst.aux = src.aux
dst.bits = src.bits
```

### 4.2 `LOADK`

Current shape:

```moonlift
L.stack[base + as(index, a)] = cl.proto.constants[bx]
```

Target:

```moonlift
let dst: ptr(Value) = L.stack + (base + as(index, a))
let src: ptr(Value) = cl.proto.constants + as(index, bx)
dst.tag = src.tag
dst.aux = src.aux
dst.bits = src.bits
```

### 4.3 `LOADI` / `LOADF`

Set destination fields directly:

```moonlift
let dst: ptr(Value) = L.stack + (base + as(index, a))
dst.tag = TAG_INTEGER
dst.aux = 0
dst.bits = as(u64, as(i64, sbx))
```

### 4.4 `LOADNIL`

Loop over destination pointers and set scalar fields:

```moonlift
let first: index = base + as(index, a)
let last: index = first + as(index, b)
jump loop(i = first, last = last, ...)
...
let dst: ptr(Value) = L.stack + i
dst.tag = TAG_NIL
...
```

### 4.5 `RETURN`, `RETURN0`, `RETURN1`

Return handling should not reload `Instr` to inspect `k`. It should receive `k` as a scalar argument from dispatch.

---

## Phase 5 — Scalarize arithmetic handlers

### 5.1 Stop generating arithmetic handlers from expression strings

Current template families:

- `_body_int(expr)`
- `_body_both(expr)`
- `_body_float(expr)`
- `_body_imm_both(expr)`
- `_body_k_both(expr)`

These should be removed.

### 5.2 Replace with explicit regions

Target explicit regions:

```text
op_add
op_sub
op_mul
op_div
op_band
op_bor
op_bxor
op_shl
op_shr
op_addi
op_addk
...
```

Each handler should be directly readable. Example:

```moonlift
region op_add(...)
entry start()
    let lhs: ptr(Value) = L.stack + (base + as(index, b))
    let rhs: ptr(Value) = L.stack + (base + as(index, c))
    let dst: ptr(Value) = L.stack + (base + as(index, a))

    if lhs.tag == TAG_INTEGER and rhs.tag == TAG_INTEGER then
        dst.tag = TAG_INTEGER
        dst.aux = 0
        dst.bits = as(u64, as(i64, lhs.bits) + as(i64, rhs.bits))
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end

    if lhs.tag == TAG_NUM and rhs.tag == TAG_NUM then
        dst.tag = TAG_NUM
        dst.aux = 0
        dst.bits = as(u64, as(f64, lhs.bits) + as(f64, rhs.bits))
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end

    frame.resume_a = a
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
```

This is verbose, but it is explicit, typed, and grep-shaped.

### 5.3 Later deduplication without strings

After explicit correctness is established, deduplicate with typed helper regions, not strings:

```moonlift
region arith_add_rr(...)
region arith_sub_rr(...)
region arith_mul_rr(...)
```

The helpers can share operand loading and result writing patterns while preserving explicit operations.

---

## Phase 6 — Split `op_handlers.lua` into spec-shaped modules

`op_handlers.lua` is too large and mixes too many concerns.

Create:

```text
experiments/lua_interpreter_vm/src/op/load.lua
experiments/lua_interpreter_vm/src/op/arithmetic.lua
experiments/lua_interpreter_vm/src/op/compare.lua
experiments/lua_interpreter_vm/src/op/table.lua
experiments/lua_interpreter_vm/src/op/call.lua
experiments/lua_interpreter_vm/src/op/loop.lua
experiments/lua_interpreter_vm/src/op/closure.lua
experiments/lua_interpreter_vm/src/op/misc.lua
```

Suggested ownership:

### `op/load.lua`

- `MOVE`
- `LOADI`
- `LOADF`
- `LOADK`
- `LOADKX`
- `LOADFALSE`
- `LFALSESKIP`
- `LOADTRUE`
- `LOADNIL`
- `GETUPVAL`
- `SETUPVAL`

### `op/arithmetic.lua`

- `ADDI`
- `ADDK`, `SUBK`, `MULK`, `MODK`, `POWK`, `DIVK`, `IDIVK`
- `BANDK`, `BORK`, `BXORK`
- `SHLI`, `SHRI`
- `ADD`, `SUB`, `MUL`, `MOD`, `POW`, `DIV`, `IDIV`
- `BAND`, `BOR`, `BXOR`, `SHL`, `SHR`
- `MMBIN`, `MMBINI`, `MMBINK`
- `UNM`, `BNOT`, `NOT`

### `op/table.lua`

- `GETTABUP`
- `GETTABLE`
- `GETI`
- `GETFIELD`
- `SETTABUP`
- `SETTABLE`
- `SETI`
- `SETFIELD`
- `NEWTABLE`
- `SELF`
- `SETLIST`

### `op/compare.lua`

- `EQ`
- `LT`
- `LE`
- `EQK`
- `EQI`
- `LTI`
- `LEI`
- `GTI`
- `GEI`
- `TEST`
- `TESTSET`

### `op/call.lua`

- `CALL`
- `TAILCALL`
- `RETURN`
- `RETURN0`
- `RETURN1`

### `op/loop.lua`

- `FORLOOP`
- `FORPREP`
- `TFORPREP`
- `TFORCALL`
- `TFORLOOP`

### `op/closure.lua`

- `CLOSURE`
- `VARARG`
- `GETVARG`
- `VARARGPREP`

### `op/misc.lua`

- `LEN`
- `CONCAT`
- `CLOSE`
- `TBC`
- `JMP`
- `ERRNNIL`
- `EXTRAARG`

Keep `op_handlers.lua` as an aggregator:

```lua
local load = require("...src.op.load")
local arithmetic = require("...src.op.arithmetic")
...
return merge(load, arithmetic, compare, table_ops, call, loop, closure, misc)
```

---

## Phase 7 — Replace string-built dispatch

Current dispatch is generated by formatting switch arms as source text.

### 7.1 Short-term target

Use an explicit `switch` region in `opcodes.lua`.

This will be long, but it is auditable:

```moonlift
switch op do
case OP_MOVE then
    emit op_move(...)
case OP_LOADI then
    emit op_loadi(...)
...
default then
    jump error(code = ERR_BAD_OPCODE)
end
```

### 7.2 Metadata remains in Lua tables

It is still fine to keep opcode metadata as Lua tables:

```lua
opcodes_meta = {
  MOVE = { op = 0, mode = "ABC", handler = handlers.op_move },
  ...
}
```

But metadata should not be the only source of dispatch semantics.

### 7.3 Long-term typed dispatch builder

If Moonlift gains or already has a typed statement builder for switch arms, use that. Until then, prefer explicit source over string-generated source.

---

## Phase 8 — Make benchmarks architecture-aware

The steady-state benchmark should continue to report:

- `elapsed(s)`;
- `ns/run`;
- `naive ns/dispatch`;
- `hot ns/op` after subtracting `RETURN` overhead;
- `Mop/s`;
- generic/quickened speedups;
- optional LuaJIT/PUC comparisons.

Add an architecture check section where possible:

1. Compile the runner.
2. Disassemble the runner.
3. Search for aggregate-copy patterns.
4. Fail or warn if a 20-byte `Instr` copy appears near dispatch.

This can be a separate diagnostic script if fragile:

```text
benchmarks/inspect_vm_dispatch_codegen.lua
```

Expected output:

```text
Dispatch codegen audit:
  Instr aggregate copy: not found
  Stack frame size:     <target threshold>
  memcpy-like calls:    <count>
```

Do not make this a hard CI gate until the pattern is stable across platforms.

---

## Phase 9 — Decide quickening after scalarization

After Phases 2-8, re-run benchmarks.

If `MOVE`, `LOADK`, and `ADD` improve significantly, then quickening can be reconsidered.

Questions quickening must answer before being part of the architecture:

1. What cost does this quickened opcode remove?
2. Is that cost still present after scalarization?
3. How is the opcode patched during normal execution?
4. Where are guards stored?
5. How is deopt triggered?
6. Is the quickened opcode still Lua 5.5-compatible at the semantic boundary?

If these questions are unanswered, quickening remains experimental.

---

## 7. Testing plan

### 7.1 Unit/spec tests

Expand `tests/test_vm_opcode_semantics.lua`.

Add tests for:

- `MOVE`
- `LOADI`
- `LOADF`
- `LOADK`
- `LOADKX`
- `LOADFALSE`
- `LFALSESKIP`
- `LOADTRUE`
- `LOADNIL`
- `JMP`
- `TEST`
- `TESTSET`
- `RETURN`
- `RETURN0`
- `RETURN1`
- `ADD`
- `ADDI`
- `ADDK`
- `EQ`
- `EQI`
- `EQK`
- `FORPREP`
- `FORLOOP`

For each opcode, build a tiny `Proto`, run `vm_resume`, and assert:

- result count;
- result tag;
- result bits;
- final frame count/status where relevant;
- expected `pc` behavior where observable.

### 7.2 Stub tests

For incomplete opcodes, tests should assert explicit failure codes rather than silently skipping:

- `MMBIN` currently returns runtime error on fallback;
- `LEN` currently returns runtime error;
- `CONCAT` currently returns runtime error;
- `CLOSURE` currently returns runtime error;
- `VARARG` currently returns runtime error.

This makes incomplete behavior visible.

### 7.3 Integration tests

Keep:

```sh
luajit experiments/lua_interpreter_vm/tests/test_vm_e2e.lua
luajit experiments/lua_interpreter_vm/tests/test_parser_compile.lua
```

Add source-to-VM execution tests once compiler output is stable:

```lua
return 42
return 1 + 2
local x = 41 return x + 1
```

These should eventually execute through the VM, not only inspect compiled opcode shapes.

### 7.4 Full test command

```sh
for t in experiments/lua_interpreter_vm/tests/*.lua; do
  echo "== $t"
  luajit "$t" || exit 1
done
```

---

## 8. Migration order and expected checkpoints

### Checkpoint A — Spec matrix exists

Files changed/added:

```text
experiments/lua_interpreter_vm/SPEC_STATUS.md
```

Validation:

```sh
rg 'Status: stub|Status: wrong|Status: partial' experiments/lua_interpreter_vm/SPEC_STATUS.md
```

The point is not to have all green. The point is to know the truth.

### Checkpoint B — Dispatch scalarized

Files changed:

```text
src/opcodes.lua
src/op_handlers.lua  -- handler signature accepts k
```

Validation:

```sh
for t in experiments/lua_interpreter_vm/tests/*.lua; do luajit "$t" || exit 1; done
MOONLIFT_VM_COMPARE_REFS=0 luajit experiments/lua_interpreter_vm/benchmarks/bench_vm_steady_state.lua
```

Expected:

- tests pass;
- no handler reloads `Instr` only to read `k`;
- disassembly no longer shows a 20-byte instruction copy in dispatch.

### Checkpoint C — Hot value handlers scalarized

Files changed:

```text
src/op_handlers.lua or src/op/load.lua
src/op/arithmetic.lua
src/regions_value.lua
```

Validation:

- `MOVE`, `LOADK`, `LOADI`, `ADD`, `RETURN` tests pass;
- benchmark improves;
- generated stack frame shrinks.

### Checkpoint D — String templates removed from arithmetic

Files changed:

```text
src/op/arithmetic.lua
src/op_handlers.lua
```

Validation:

```sh
rg '".*\.\..*"|_body_|string.format' experiments/lua_interpreter_vm/src/op_handlers.lua experiments/lua_interpreter_vm/src/op
```

Expected:

- no `_body_both`, `_body_int`, etc.;
- no string-generated arithmetic bodies;
- arithmetic handlers are explicit typed regions.

### Checkpoint E — Opcode modules split

Files added:

```text
src/op/load.lua
src/op/arithmetic.lua
src/op/compare.lua
src/op/table.lua
src/op/call.lua
src/op/loop.lua
src/op/closure.lua
src/op/misc.lua
```

Validation:

```sh
rg '^local op_' experiments/lua_interpreter_vm/src/op
```

Should show a grep-shaped opcode surface.

### Checkpoint F — Dispatch no longer string-generated

Files changed:

```text
src/opcodes.lua
```

Validation:

```sh
rg 'make_arm_src|dispatch_arm_src|string.format' experiments/lua_interpreter_vm/src/opcodes.lua
```

Expected:

- no dispatch arm string builder;
- explicit switch or typed dispatch builder.

---

## 9. Coding rules for this refactor

1. **No new hot-path aggregate loads.**
   - Avoid `let x: Instr = *ptr` in dispatch.
   - Avoid `let x: Value = stack[...]` in hot handlers.

2. **No source-string handler factories.**
   - Do not generate Moonlift expressions with Lua string concatenation.

3. **Prefer explicit handlers over clever generators.**
   - Verbose but correct is better than compact but opaque.

4. **Every opcode has a status.**
   - Implemented, partial, stub, wrong, untested.

5. **Stubs fail loudly.**
   - No silent success for unimplemented semantics.

6. **Benchmarks do not define correctness.**
   - Tests and PUC spec references define correctness.

7. **Quickening is not baseline.**
   - Do not use quickening to hide baseline interpreter architectural issues.

8. **Moonlift structure over text.**
   - Products, protocols, regions, blocks, and jumps must be visible as structure.

---

## 10. Immediate next edits

The next implementation session should do the following in order:

1. Create `SPEC_STATUS.md` with all Lua 5.5 opcodes and current status.
2. Change dispatch to read `Instr` fields through `ptr(Instr)`.
3. Add `k: u8` to the standard handler signature.
4. Remove handler-side `Instr` reloads for return/close behavior.
5. Scalarize `MOVE`, `LOADK`, `LOADI`, `LOADF`, `LOADNIL`, `RETURN*`.
6. Re-run all tests.
7. Re-run benchmark and record before/after numbers.
8. Start splitting `op_handlers.lua` with `op/load.lua` first.
9. Replace arithmetic string templates with explicit handlers.

---

## 11. Success criteria

This refactor is successful when:

- The VM has an explicit opcode spec matrix.
- The dispatch path does not copy `Instr` by value.
- The common handlers do not copy `Value` by value in the hot path.
- Arithmetic handlers are explicit typed Moonlift regions, not Lua-generated source strings.
- Opcode modules are organized by Lua VM domain.
- Benchmarks continue to produce comparison tables.
- Quickening is either quarantined or justified by post-scalarization measurements.
- The implementation is easier to audit against `.vendor/Lua/lvm.c` than before.

The final intended VM is not merely faster. It is more Moonlift-native: explicit data, explicit control, visible semantics, and no hidden text-generated compiler inside the compiler.
