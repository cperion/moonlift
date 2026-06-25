# Complete Lalin Lua VM before SponJIT integration
Audit experiments/lua_interpreter_vm current Lalin Lua VM implementation, identify gaps, and plan completion before any SponJIT integration.
**Workflow ID**: wf-lua-vm-completion
**Started**: 2026-05-29 07:11:07
---

## Scout Output — 2026-05-29 07:18:21

## Files Retrieved

1. `experiments/lua_interpreter_vm/README.md` (lines 1-205) - Top-level README is SponJIT-focused; describes `src/` as Lua VM source but frames repo around PUC SponJIT.
2. `experiments/lua_interpreter_vm/src/init.lua` (lines 1-31) - Module loader and dependency surface.
3. `experiments/lua_interpreter_vm/src/constants.lua` (lines 1-211) - Lua 5.5 value tags, opcodes 0-84, TM events, statuses/errors.
4. `experiments/lua_interpreter_vm/src/products.lua` (lines 1-109) - Core VM data layout: `Value`, `Proto`, `Frame`, `LuaThread`, table/string/closure/upvalue structs.
5. `experiments/lua_interpreter_vm/src/vm_loop.lua` (lines 1-156) - `vm_resume`, `vm_loop`, dispatch loop, call/return top-level flow.
6. `experiments/lua_interpreter_vm/src/opcodes.lua` (lines 1-717) - Instruction decoder, switch arm generation, inline hot opcode bodies, handler mapping, opcode metadata.
7. `experiments/lua_interpreter_vm/src/op/_init.lua` (lines 1-151) - Shared opcode handler boilerplate and continuation signatures.
8. `experiments/lua_interpreter_vm/src/op/load.lua` (lines 1-174) - MOVE/LOAD*/upvalue load/store/EXTRAARG handlers.
9. `experiments/lua_interpreter_vm/src/op/arithmetic.lua` (lines 1-473) - Arithmetic/bitwise/unary/MMBIN handlers; many numeric fast paths, several arithmetic stubs.
10. `experiments/lua_interpreter_vm/src/op/table.lua` (lines 1-261) - GET/SET table opcode handlers; NEWTABLE/SETLIST are OOM stubs.
11. `experiments/lua_interpreter_vm/src/op/call.lua` (lines 1-252) - CALL/TAILCALL/RETURN handlers.
12. `experiments/lua_interpreter_vm/src/op/compare.lua` (lines 1-216) - EQ/LT/LE/immediate compare/TEST handlers.
13. `experiments/lua_interpreter_vm/src/op/loop.lua` (lines 1-113) - Numeric for-loop and generic-for stubs.
14. `experiments/lua_interpreter_vm/src/op/closure.lua` (lines 1-52) - CLOSURE/VARARG/GETVARG stubs; VARARGPREP pass-through.
15. `experiments/lua_interpreter_vm/src/op/misc.lua` (lines 1-84) - LEN/CONCAT stubs; CLOSE/TBC/JMP/ERRNNIL.
16. `experiments/lua_interpreter_vm/src/op_handlers.lua` (lines 1-21) - Aggregates all opcode handler modules.
17. `experiments/lua_interpreter_vm/src/op_factory.lua` (lines 1-22) - Compatibility shim; notes old string-generation approach replaced by typed hosted regions.
18. `experiments/lua_interpreter_vm/src/regions_value.lua` (lines 1-264) - Value predicates/equality/comparison/RK resolution.
19. `experiments/lua_interpreter_vm/src/regions_table.lua` (lines 1-226) - Raw table get/set, metamethod-aware get/set, `next`, resize.
20. `experiments/lua_interpreter_vm/src/regions_call.lua` (lines 1-279) - Call dispatch, native-call stub, return-mode state machine.
21. `experiments/lua_interpreter_vm/src/regions_stack.lua` (lines 1-124) - Stack/frame checks, frame push/pop, result adjustment, vararg adjustment stub.
22. `experiments/lua_interpreter_vm/src/regions_metamethod.lua` (lines 1-151) - Metamethod lookup and dispatch helpers.
23. `experiments/lua_interpreter_vm/src/regions_string.lua` (lines 1-56) - Hash implemented; interning/concat missing.
24. `experiments/lua_interpreter_vm/src/regions_upvalue.lua` (lines 1-60) - Close upvalues implemented; allocate/find/create closure mostly missing.
25. `experiments/lua_interpreter_vm/src/regions_error.lua` (lines 1-195) - Error/TBC/protected-call scaffolding; protected-call allocation and TBC close-call incomplete.
26. `experiments/lua_interpreter_vm/src/regions_gc.lua` (lines 1-165) - GC protocol shell; allocation/propagate/sweep mostly no-op or OOM.
27. `experiments/lua_interpreter_vm/src/gc_impl.lua` (lines 1-7) - Re-exports GC regions.
28. `experiments/lua_interpreter_vm/src/regions_api.lua` (lines 1-43) - Internal API index decoding.
29. `experiments/lua_interpreter_vm/src/api.lua` (lines 1-138) - Sealed C-compatible API functions; most table/call/protected API entries error.
30. `experiments/lua_interpreter_vm/src/regions_coroutine.lua` (lines 1-39) - Coroutine resume/yield stubs.
31. `experiments/lua_interpreter_vm/src/validate.lua` (lines 1-71) - Minimal Proto validation trust boundary.
32. `experiments/lua_interpreter_vm/src/parser_constants.lua` (lines 1-82) - First source compiler token/error constants.
33. `experiments/lua_interpreter_vm/src/parser_products.lua` (lines 1-49) - Source compiler structs.
34. `experiments/lua_interpreter_vm/src/regions_lexer.lua` (lines 1-276) - Lexer for limited Lua source subset.
35. `experiments/lua_interpreter_vm/src/regions_parser.lua` (lines 1-558) - First parser/compiler slice: locals, returns, integer literals, simple arithmetic.
36. `experiments/lua_interpreter_vm/src/regions_codegen.lua` (lines 1-382) - Bytecode emission helpers for limited source compiler.
37. `experiments/lua_interpreter_vm/src/regions_compiler.lua` (lines 1-84) - Public compile entry into caller-provided buffers.
38. `experiments/lua_interpreter_vm/src/jit/stencil_codegen.lua` (lines 1-63) - Early compact StateOp stencil codegen shim.
39. `experiments/lua_interpreter_vm/src/jit/elf_parser.lua` (lines 1-101) - Minimal object parser using `nm`/`objdump`.
40. `experiments/lua_interpreter_vm/tests/test_vm_smoke.lua` (lines 1-130) - Module/region/bundle compile inventory.
41. `experiments/lua_interpreter_vm/tests/test_vm_e2e.lua` (lines 1-215) - FFI scratch-built Proto executing LOADK+RETURN.
42. `experiments/lua_interpreter_vm/tests/test_vm_opcode_semantics.lua` (lines 1-281) - Focused opcode semantic checks.
43. `experiments/lua_interpreter_vm/tests/test_parser_compile.lua` (lines 1-244) - Source compiler + validate + VM execution tests for arithmetic subset.
44. `experiments/lua_interpreter_vm/tests/test_vm_integration.lua` (lines 1-54) - Minimal region composition smoke test; notes direct-pointer workaround.
45. `experiments/lua_interpreter_vm/benchmarks/bench_vm_steady_state.lua` (lines 1-509) - Current VM steady-state benchmark.
46. `experiments/lua_interpreter_vm/benchmarks/bench_vm_comparative.lua` (lines 1-550) - Broader opcode comparison benchmark.
47. `experiments/lua_interpreter_vm/benchmarks/bench_vm_vs_ref.lua` (lines 1-244) - LOADK+RETURN vs Lua references.
48. `experiments/lua_interpreter_vm/benchmarks/bench_cap_vs_vm.lua` (lines 1-315) - Copy-and-patch vs VM dispatch benchmark.
49. `experiments/lua_interpreter_vm/benchmarks/bench_stencil_vs_vm.lua` (lines 1-291) - Stencil ABI mismatch benchmark.
50. `experiments/lua_interpreter_vm/benchmarks/bench_fusion.lua` (lines 1-309) - Fusion experiment benchmark.
51. `experiments/lua_interpreter_vm/tools/jit_harness/README.md` (lines 1-319) - VM-shaped stencil harness status; has mock pieces and Lua 5.5 corpus caveat.
52. `experiments/lua_interpreter_vm/tools/jit_harness/compile.lua` (lines 1-260) - Harness compiler uses current Lalin Lua VM source compiler; fallback token compiler exists.
53. `experiments/lua_interpreter_vm/tools/jit_harness/candidate_emit.lua` (lines 1-600) - VM-shaped candidate stencil emitter and lowering fragments.
54. `experiments/lua_interpreter_vm/spongejit/puc/README.md` (lines 1-116) - Confirms SponJIT current real integration is PUC Lua-oriented.
55. `experiments/lua_interpreter_vm/SPONJIT_ARCHITECTURE.md` (lines 1-120) - SponJIT architecture; read only enough to confirm separate context.

## Key Code

### Core data model

```lua
-- products.lua
local Value = host.struct [[struct Value tag: u32; aux: u32; bits: u64 end]]
local Instr = host.struct [[struct Instr word: u32 end]]
local Proto = host.struct [[struct Proto gc: GCHeader; code: ptr(Instr); code_len: index; constants: ptr(Value); constants_len: index; children: ptr(ptr(Proto)); children_len: index; lineinfo: ptr(i32); lineinfo_len: index; locvars: ptr(LocVar); locvars_len: index; upvals: ptr(UpValDesc); upvals_len: index; source: ptr(String); linedefined: i32; lastlinedefined: i32; numparams: u8; flag: u8; maxstack: u16 end]]
local Frame = host.struct [[struct Frame closure: Value; base: index; top: index; pc: index; wanted: i32; tailcalls: i32; resume_mode: u16; resume_a: u16; resume_b: u16; resume_c: u16; resume_pc: index; resume_base: index; resume_value: Value end]]
```

### VM loop shape

```lua
-- vm_loop.lua
region vm_loop(L: ptr(LuaThread);
               finished: cont(nres: i32),
               yielded: cont(nres: i32),
               error: cont(code: i32),
               oom: cont())
entry start()
    if L.frame_count == 0 then
        jump finished(nres = 0)
    end
    let frame: ptr(Frame) = L.frames + (L.frame_count - 1)
    let pc: index = frame.pc
    let base: index = frame.base
    let top: index = frame.top
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let code: ptr(Instr) = cl.proto.code
    let constants: ptr(Value) = cl.proto.constants
    jump loop(frame = frame, pc = pc, base = base, top = top, code = code, constants = constants)
end
block loop(...)
    emit dispatch_instruction(...;
        next = cont_loop,
        do_jump = cont_jump,
        resume_parent = cont_resume_parent,
        enter_lua = do_lua,
        enter_native = do_native,
        returned = do_returned,
        yielded = do_yielded,
        error = do_error,
        oom = out_of_mem)
end
```

### Dispatch and hot inline opcodes

```lua
-- opcodes.lua
entry decode()
    let ip: ptr(Instr) = cur_code + cur_pc
    let word: u32 = ip.word
    let op: u16 = as(u16, word & 127)
    switch op do
@{switch_arms...}
    default then
        jump error(code = @{ERR_BAD_OPCODE})
    end
end
```

Inline fast paths exist for MOVE, LOADK, ADD, LOADI, LOADF, LOADFALSE/TRUE/NIL, ADDI/ADDK/SUB/MUL/DIV, UNM, NOT, JMP, EQ, LT numeric fast path, TEST.

### Clear missing-behavior examples

```lua
-- op/closure.lua
region op_closure(...; next: cont(...), error: cont(code: i32), oom: cont())
entry start()
    jump error(code = @{ERR_RUNTIME})
end
```

```lua
-- regions_gc.lua
region alloc_object(G: ptr(GlobalState), size: index, tt: u8;
                    ok: cont(obj: ptr(GCHeader)),
                    step_required: cont(),
                    oom: cont())
entry start()
    jump oom()
end
```

```lua
-- regions_string.lua
region string_intern(L: ptr(LuaThread), bytes: ptr(u8), len: index;
                     found: cont(s: ptr(String)),
                     created: cont(s: ptr(String)),
                     oom: cont())
entry start()
    -- String allocation/interning requires the runtime allocator
    jump oom()
end
```

```lua
-- regions_call.lua
region call_native(...)
entry start()
    jump error(code = @{ERR_CALL})
end
```

### Source compiler current slice

```lua
-- regions_compiler.lua
region compile_lua_source_into(... bytes: ptr(u8), len: index, code: ptr(Instr), code_cap: index, locals: ptr(CompileLocal), locals_cap: index; ...)
entry start()
    cu.arena = nil
    ...
    emit compile_prepared_unit(cu;
        ok = compiled,
        syntax_error = syntax_bad,
        semantic_error = sem_bad,
        limit_error = limit_bad,
        oom = out_of_mem)
end
```

It compiles only a small subset currently tested by strings like:

```lua
run_case("return 1 + 2", { LOADI, LOADI, ADD, MMBIN, RETURN1 }, 3)
run_case("local x = 41 return x + 1", { LOADI, LOADI, ADD, MMBIN, RETURN1 }, 42)
```

## Relationships

- `src/init.lua` loads the entire VM surface: constants/products, regions, opcode handlers, dispatch, compiler.
- VM runtime flow:
  `vm_resume` → `vm_loop` → `dispatch_instruction` → inline opcode body or `op_handlers.*` region → subsystem regions (`regions_table`, `regions_call`, `regions_value`, etc.).
- Arithmetic fast path pattern:
  bytecode emits arithmetic op followed by `MMBIN`; fast success jumps `pc + 2`, failure jumps `pc + 1` into `MMBIN`. But `MMBIN/MMBINI/MMBINK` currently runtime-error.
- Calls:
  `op_call` → `prepare_call` → either push Lua frame or enter native. Native then goes to `call_native`, which is currently `ERR_CALL`.
- Returns:
  `op_return*` → optional `tbc_close_chain` → `return_from_lua` → `handle_return_mode` → parent resume or finished.
- Tables:
  opcode handlers call `table_get`/`table_set`. Raw get/set exist for existing array/hash slots. Resize/allocation is missing, so table creation/growth is impossible.
- Source compiler:
  `compile_lua_source_into` uses caller-provided buffers and emits VM bytecode directly; it has no allocator-backed constant/string/proto creation yet.
- Tests construct VM memory manually via FFI and `lalin_scratch_raw`; no real allocator/GC path is exercised.
- SponJIT context is separate:
  - `spongejit/puc/README.md` is explicitly PUC Lua 5.5 bank/runtime integration.
  - `tools/jit_harness` has VM-shaped candidate machinery, but README admits mock parts and corpus limitations.
  - Current Lalin VM completion should not depend on PUC SponJIT as implementation target.

## Observations

### What currently works

- Module/bundle smoke passes:
  - 196 region fragments
  - 42 struct definitions
  - 85 opcode handlers exported
  - full `vm_resume + vm_loop + dispatch` bundle compiles.
- E2E manually built Proto executes `LOADK R0 K0; RETURN R0 2` and returns `42.0`.
- Focused opcode semantic test passes 10/10 for:
  - LOADNIL
  - LOADKX/EXTRAARG
  - ADDI
  - ADDK
  - f64 ADD payload semantics
  - LOADTRUE/NOT/TEST/JMP
  - LOADF
  - EQ numeric
  - LT string fallback
  - RETURN1.
- Source compiler tests pass for integer arithmetic/local/return subset.

### Major completion gaps

- No allocator-backed object creation:
  - `alloc_object`, `string_intern`, `make_lclosure`, `find_upvalue` allocation, `table_resize`, `op_newtable`, `op_setlist` all fail/OOM.
- No full GC:
  - mark helpers exist, but propagation/sweep/allocation are no-op or OOM.
- No closure creation/varargs:
  - `op_closure`, `op_vararg`, `op_getvarg` error; `adjust_varargs` OOM.
- Native/C call path missing:
  - `call_native` errors; public `lua_call_api`/`lua_pcall_api` error.
- Protected calls and coroutines missing:
  - `enter_protected` OOM, `protected_call` immediate failure, coroutine resume/yield not implemented.
- Metamethod invocation incomplete:
  - lookup helpers exist, but MMBIN/MMBINI/MMBINK error; LEN/CONCAT error; TBC close with `__close` errors.
- Tables incomplete:
  - raw get/set can access existing slots; no insertion/growth/new table; `table_next` always done.
- Strings incomplete:
  - hash exists; intern/concat/number-to-string missing.
- Source compiler is a very small first slice, not a Lua compiler:
  - no functions, calls, tables, loops, if, assignments beyond `local x = expr`, string constants, nested protos, upvalues, labels/goto, etc.

### Semantic risks/gaps

- Numeric equality/comparison is tag-strict in several paths; Lua 5.4/5.5-style integer/float cross-numeric equality/comparison is likely incomplete.
- Arithmetic fast paths handle int+int and num+num but not mixed int/float coercions.
- `MOD`, `IDIV`, `POW` and K variants return arithmetic errors.
- `validate_proto` is minimal: checks opcode range, A < maxstack, some constant/child/jump bounds. It does not fully validate B/C register bounds, EXTRAARG pairing, MMBIN sequencing, return discipline, upvalues, stack effects, etc.
- `opcodes_meta` labels some K opcodes as `ABx` while dispatch/handlers use `ABC`-style `c` for implemented ADDK/SUBK/MULK/DIVK; tooling metadata may be inconsistent with execution encoding.

### Performance-relevant structure

- VM loop threads hot state as block parameters: `frame`, `pc`, `base`, `top`, `code`, `constants`.
- Dispatch caches `code` and `constants` pointers rather than reloading through `frame->closure->proto` every opcode.
- Many hot paths avoid aggregate `Value` copies and use scalar field stores.
- Some handlers still use aggregate struct assignment (`L.stack[...] = { ... }`), unlike newer scalar inlined paths.
- `InlineCache` and `QuickInstr` structs exist but are reserved/unused.
- `table_raw_get` scans buckets linearly rather than hashing directly in the miss path; this is correctness-simple but not performance-complete.
- Benchmarks are noisy at small settings, but steady-state run with `STEPS=1000,RUNS=200,refs=0` produced:
  - LOADI ~3.71 hot ns/op
  - LOADK ~2.52 hot ns/op
  - MOVE ~2.62 hot ns/op
  - ADD f64 ~6.45 hot ns/op
  - ADD int ~4.52 hot ns/op
- Benchmark suite includes copy-and-patch/fusion experiments, but several are SponJIT/stencil-oriented and not VM-completion proof.

### Boundary notes

- Current VM is Lalin-hosted regions/functions compiled by Lalin/Cranelift.
- Runtime memory in tests is external FFI/scratch memory; the VM’s own allocator/GC does not back objects yet.
- Public C API is intentionally sealed, but only simple stack/type/string access works.
- SponJIT PUC path has real bank/runtime work, but it targets vendored PUC Lua and should remain separate until Lalin VM semantics and runtime services are complete.

## Knowledge-builder Output — 2026-05-29 08:33:59

## What Matters Most for This Problem

- **Semantic completion boundary**: “VM complete enough before SponJIT” should mean Lua 5.5 behavioral compatibility for executed programs, not just opcode inventory or dispatch speed.
- **Runtime service dependencies**: allocator, strings, tables, closures/upvalues, protected calls, coroutines, native calls, and GC are not independent gaps; many opcode semantics depend on several of them simultaneously.
- **Frame/continuation correctness**: the current jump-first structure is promising, but nested calls, metamethod returns, yields, and protected unwinds create hidden invariants around cached `code/constants`, `pc`, `top`, `resume_mode`, and result placement.
- **Trust boundary / validation**: the VM can execute manually constructed `Proto`s, but invalid bytecode can currently bypass many assumptions. This matters before any JIT consumes the same bytecode contract.
- **Lua 5.5 compatibility vs PUC cloning**: the VM can remain Lalin-native, but must still pin down which parts are semantic compatibility, bytecode compatibility, C API compatibility, and library compatibility.
- **Verification scope**: current tests prove a fast arithmetic/load/return slice, not VM completeness. Future verification must cover dynamic features, malformed bytecode, and cross-feature interactions.

## Non-Obvious Observations

### 1. The strongest hidden blocker is not missing opcodes; it is the missing runtime object economy

Many visible stubs are symptoms of one deeper absence: the VM cannot yet create and manage collectable runtime objects.

This single gap blocks:

- `NEWTABLE`, `SETLIST`, table growth
- string interning and concat
- closure allocation
- upvalue allocation
- protected frame allocation
- stack/frame growth
- userdata/thread creation
- native closure setup
- real compiler output containing strings, nested protos, closures, tables

So “opcode completion” cannot be evaluated one opcode at a time. A large fraction of Lua semantics only becomes meaningful once allocation, ownership, and lifetime are coherent.

### 2. String interning is semantically load-bearing, not an optimization

`value_raw_equal` compares strings by pointer identity. That is Lua-compatible only if every string entering the VM is interned.

But tests currently construct `String` objects manually via FFI. That is okay for limited comparison tests, but once string equality, table keys, constants, field names, metamethod names, and source compiler strings are involved, `string_intern` becomes part of the semantic contract.

Hidden implication: until interning is real, any feature that relies on string identity can appear to work in hand-crafted cases while being semantically wrong in integrated cases.

Relevant files:

- `regions_value.lua`
- `regions_string.lua`
- `regions_metamethod.lua`
- `regions_codegen.lua`

### 3. The arithmetic/MMBIN pattern creates a bytecode sequencing invariant that validation does not enforce

Arithmetic fast paths intentionally do:

- fast numeric success → `pc + 2`
- non-fast path → `pc + 1`, expecting an adjacent `MMBIN/MMBINI/MMBINK`

That means bytecode safety and correctness depend on the instruction following arithmetic ops having the correct shape and operands.

Current `validate_proto` does not verify:

- arithmetic op followed by matching `MMBIN*`
- `LOADKX` followed by valid `EXTRAARG`
- `EXTRAARG` only appearing where meaningful
- register bounds for B/C operands
- constant bounds for K-style opcodes using `c`
- stack effects around call/return
- loop register windows
- upvalue indices

This is especially risky before JIT integration: a JIT would likely rely on the same sequencing invariant, so the VM’s validator needs to become the canonical trust boundary.

### 4. Numeric semantics are currently narrower than Lua semantics in several interacting places

The scout noted int/float equality and mixed arithmetic gaps. The deeper issue is that numeric compatibility affects many subsystems at once:

- arithmetic fast paths
- comparisons
- table key lookup
- table key insertion
- immediate comparison opcodes
- constant equality
- loop setup and loop stepping
- metamethod fallback decisions

Examples:

- `value_raw_equal` returns false for integer `1` vs float `1.0`.
- arithmetic fast paths handle int+int and float+float, but mixed int/float falls into metamethod machinery.
- `table_raw_get` and `table_raw_set` compare `key.tag` and `key.bits`, so integer `1` and float `1.0` are distinct keys.
- array lookup only accepts `TAG_INTEGER`, so float keys representing integral values do not hit the array part.
- NaN table-key rejection is not visible yet; only nil is rejected.

This means numeric semantics should be verified as a cross-cutting invariant, not as isolated opcode tests.

### 5. Some “metamethod scaffolding” currently has the right control shape but the wrong data preservation story

The continuation structure for table/metamethod calls is architecturally promising, but the current stack setup appears to overwrite live registers.

For example, shared table metamethod blocks in `op/_init.lua` place:

```lua
L.stack[base] = mm
L.stack[base + 1] = self
L.stack[base + 2] = key
```

That uses the current function’s register base as a temporary call area. Lua semantics require non-result registers to survive metamethod calls unless explicitly assigned. This can clobber locals in `R0`, `R1`, `R2`, etc.

This is not just an implementation stub. It exposes a missing invariant: every reentrant call path needs a safe, specified call scratch area and result handoff discipline.

### 6. Nested Lua call return currently has a likely cached-code/constants hazard

`vm_loop` caches `code` and `constants` as threaded loop parameters. This is good for speed.

But when returning from a child frame to a parent, `dispatch_instruction`’s `cont_resume` forwards the current `cur_code/cur_consts`. In a child frame, those are the child’s proto pointers. `vm_loop.cont_resume_parent` then resumes the parent frame with those same cached pointers instead of reloading from the parent closure.

That means nested Lua calls can resume the parent using the child’s bytecode/constants.

This is a hidden correctness risk caused by the performance-oriented cache threading. The invariant should be: whenever `frame` changes, cached proto-derived pointers must correspond to that frame.

Relevant files:

- `vm_loop.lua`
- `opcodes.lua`
- `regions_call.lua`

### 7. General call result placement appears under-specified beyond trivial `A == 0` cases

For Lua calls, `op_call` saves `frame.pc = pc`, then enters the callee. On return, `handle_return_mode` for `RESUME_NORMAL` adjusts results into `parent.base`.

But the result destination for a call is `base + A`, not necessarily `parent.base`.

There is some `resume_a` storage on child frames, but the normal return path does not appear to use it to place results. Current tests mostly avoid nested/general calls, so this can remain hidden.

Implication: call/return completion needs to verify result placement for:

- `CALL A B C` with multiple `A` values
- nested calls
- tailcalls
- `C == 0` open result lists
- calls inside expressions
- metamethod calls
- native calls
- coroutine yields/resumes

### 8. Non-vararg function argument adjustment is also incomplete, even before varargs

`prepare_call` checks stack capacity using `proto.maxstack`, but it does not visibly normalize actual arguments to formal parameters:

- missing fixed parameters should become nil
- extra arguments should be ignored except where open-call semantics require them
- frame `top` should be coherent with callable register window and later `CALL B==0` behavior

`adjust_varargs` is explicitly stubbed, but fixed-argument adjustment also needs scrutiny. Otherwise simple function calls can pass tests only when caller and callee happen to agree on exact argument count and register contents are clean.

### 9. Native calls are not merely a missing API feature; they block standard Lua behavior and metamethod completion

`call_native` is stubbed, and public `lua_call_api`/`lua_pcall_api` fail. This affects more than external embedding:

- base library functions
- iterator functions
- metamethods implemented as native closures
- protected calls
- coroutine library
- allocator/finalizer hooks
- error handler callbacks
- possible standard library bootstrap

Even if the Lalin VM is not a PUC clone, it still needs a sealed native-call convention if Lua-visible native functions exist. The current `CClosure` struct already commits to such a boundary.

### 10. Table semantics currently conflate “missing storage” with “OOM”

`table_raw_set` returns `resized` when insertion/growth is needed. `table_set` then:

- checks `__newindex`
- if absent, jumps `oom`

This is useful as fail-loud scaffolding, but semantically it means ordinary table insertion is indistinguishable from allocation failure. Once allocation exists, this path becomes the critical join point for:

- nil/NaN key rejection
- array/hash placement
- write barriers
- shape epoch updates
- metamethod fallback
- weak table behavior
- iterator validity

Table insertion is therefore a high-risk completion boundary, not a local `table_resize` TODO.

### 11. `__index` / `__newindex` behavior is only partially modeled

Current `table_get` and `table_set` can find metamethod values, but Lua semantics distinguish function metamethods from table metamethods:

- `__index` can be a function or table
- `__newindex` can be a function or table
- recursive lookup/assignment must have loop protection

Current continuations are named `call_mm`, suggesting call-only behavior. `loop_error` exists but is not meaningfully exercised.

This is an example where the control protocol anticipates full behavior, but the value-level cases are not yet represented.

### 12. GC write barriers are defined but not integrated into mutating operations

`write_barrier` and `write_barrier_back` exist, but mutations such as:

- table writes
- upvalue writes
- closure upvalue installation
- global registry updates
- metatable writes
- stack-to-heap captures

do not consistently call barriers.

Also, `mark_object` marks gray but does not appear to link objects into `G.gray`, and propagation/sweep are no-ops. So GC is currently a protocol shell, not an incremental collector.

Hidden implication: after allocator work starts, correctness will depend on adding barriers at every semantic mutation site, not just implementing `gc_step`.

### 13. Upvalue closing works only for already-created, correctly sorted open upvalues

`close_upvalues` assumes `L.open_upvals` is ordered by descending stack index. `find_upvalue` also assumes this ordering when it stops at `uv.stack_index < stack_index`.

But new upvalue allocation/insertion is stubbed. The ordering invariant therefore exists but is not yet enforced by any creation path.

This matters for closure completion: a small mistake in open-upvalue list ordering would make `CLOSE`, return, and error unwind close the wrong set of variables.

### 14. To-be-closed variables currently encode only a single head index, which may be insufficient

`LuaThread.tbc_head` is a single `index`, and `op_tbc` sets:

```lua
L.tbc_head = base + A
```

`tbc_close_chain` scans backward through stack slots looking for non-nil values and rewrites `tbc_head`.

This is much simpler than a linked TBC chain and may have edge cases around:

- multiple active to-be-closed variables
- nested scopes
- nil/false close rules
- unwinding across frames
- yields/errors during `__close`
- interleaving with open upvalues

The shape may be intentional for Lalin-native design, but it needs semantic validation against Lua 5.5 behavior.

### 15. Error handling lacks a single visible path from opcode error to protected unwind

`raise_error` and protected-frame scaffolding exist, but `vm_loop` opcode errors currently jump directly to the outer `error` continuation. That bypasses `raise_error` unless some higher layer wraps it later.

This creates a semantic split:

- opcode/runtime error status path
- protected-call catch/unwind path
- TBC close-on-error path
- error object construction path

For Lua compatibility, these cannot remain separate. Errors from opcodes, metamethod calls, native calls, allocation failures, and compiler/runtime API boundaries need one coherent unwinding model.

### 16. Coroutine/yield semantics will stress the same continuation fields as metamethods and protected calls

The VM already has `resume_mode` variants for many dynamic resumptions:

- table metamethods
- binary/unary metamethods
- comparisons
- concat
- generic for
- native continuation
- TBC close
- pcall/xpcall

This is promising, but it means coroutine support cannot be bolted on after the fact. Yieldability affects whether these dynamic calls may suspend and how they resume.

Current `op_return` even maps `op_ret_yielded` to `finished`, suggesting yield paths have not yet been semantically exercised.

### 17. The source compiler currently avoids most runtime features, so compiler tests understate VM gaps

The source compiler emits direct bytecode into caller-provided buffers for a tiny subset: locals, integer literals, arithmetic, return.

It currently does not force the VM to handle:

- string constants
- constant table allocation
- functions/nested protos
- closures/upvalues
- table constructors
- calls
- control-flow joins
- varargs
- labels/goto
- debug info
- full Lua expression coercions

So source-compiler success is not yet an end-to-end semantic signal. It mostly proves the arithmetic/load/return slice plus codegen encoding.

### 18. The VM is fast partly because it assumes trusted, shape-stable bytecode

Hot dispatch assumes:

- `pc` is valid
- register operands are within frame/proto bounds
- constants pointers are valid
- `frame.closure` is an `LClosure`
- arithmetic/MMBIN sequencing is valid
- call frame state is coherent
- cached `code/constants` match current frame

That is reasonable for a high-performance VM, but only if validation and compiler output enforce these conditions. Right now that trust boundary is porous.

This matters especially before SponJIT: a JIT will amplify unsound assumptions.

### 19. Current tests validate “straight-line VM microsemantics,” not “Lua program semantics”

Existing tests are valuable but skew toward:

- manually built protos
- scratch memory
- no allocator
- no nested calls
- no real strings/intern table
- no real tables
- no GC
- no protected calls
- no coroutines
- no native calls
- no malformed bytecode fuzzing
- no standard-library compatibility

The VM can be architecturally promising and fast while still being far from compatibility. The next verification boundary must test feature interactions, not just opcode units.

### 20. SponJIT should consume a stabilized semantic VM contract, not drive the VM design

The findings imply SponJIT integration should wait until the Lalin-native VM has:

- stable value representation rules
- stable frame/call/yield conventions
- stable object allocation and lifetime model
- stable bytecode validation contract
- stable table/string/numeric semantics
- stable error/protected-call behavior

Otherwise SponJIT risks optimizing accidental scaffolding behavior, especially around arithmetic fast paths, cached proto pointers, metamethod calls, and stack layout.

## Knowledge Gaps

- Exact bleeding-edge Lua 5.5 semantic deltas vs Lua 5.4 need to be pinned down locally: opcode meanings, vararg behavior, TBC behavior, numeric corner cases, and debug/API expectations.
- The intended Lalin-native native-call ABI is not yet clear: whether it targets Lua C API compatibility, a smaller sealed ABI, or both.
- The intended standard library boundary is unclear: native-hosted libs, Lua-implemented libs, or hybrid.
- The intended bytecode compatibility level is unclear: PUC-compatible 32-bit opcode stream, Lalin-owned bytecode with Lua 5.5 semantics, or a transitional subset.
- The intended GC strategy is unclear: exact/incremental/generational/arena-first. This affects barriers, object headers, weak tables, finalization, and allocator API.

## Knowledge-builder Output — 2026-05-29 08:50:30

### What Matters Most for This Problem

- **Extern/libc boundaries must not become hidden VM semantics.** Lalin externs are typed C-ABI calls with one return path; Lua VM behavior needs explicit success/error/oom/yield protocols around them.
- **The Lua VM runtime is not Lalin’s runtime.** Lalin has no GC, exceptions, dynamic dispatch, or implicit scheduler. If Lua needs GC, protected calls, coroutines, allocator failure, finalizers, or native callbacks, those are VM data/control structures.
- **Typed regions should be the semantic core.** Multi-outcome VM operations should expose named continuations, not status-code conventions or hidden side channels.
- **PUC compatibility is semantic, not architectural.** PUC’s C-stack, `longjmp`, allocator, registry, and C API idioms are compatibility references, not implementation models.
- **Host ABI stability matters early.** `Value`, `LuaThread`, `Proto`, allocator hooks, native function ABI, and API exposure must be stable before JIT/SponJIT consumes them.
- **Explicit data/control modeling matters more than opcode count.** Lua 5.5 semantics are dynamic, but Lalin requires every dynamic distinction to appear as tags, structs, continuations, or validation facts.

### Non-Obvious Observations

- **`extern` is too weak to directly express VM runtime operations.**
  Lalin extern calls are C-ABI calls to symbols. They cannot declare `oom`, `errno`, `yield`, `protected_error`, `panic`, or `longjmp` exits. Therefore libc calls such as allocation, memcpy-like operations, I/O, or native Lua callbacks cannot be treated as semantically transparent. Any hidden behavior behind a C return value would violate the explicit-programming model.

- **Using libc allocation directly would smuggle in a second runtime.**
  Lua requires allocator-visible object lifetime, GC barriers, finalization, weak tables, string interning, and failure handling. If object creation is “just malloc,” then ownership, reachability, alignment, failure, and reclamation are outside the VM’s typed data/control tree. That conflicts with Lalin’s rule that persistent state and transitions are explicit.

- **Lua’s historical error model maps badly onto Lalin externs.**
  PUC Lua relies heavily on non-local exits (`longjmp`-style protected calls). Lalin has no exceptions and externs do not type non-local control. So protected calls, `error`, metamethod failures, `__close`, native callback failures, and coroutine yields must be represented as explicit VM control outcomes, not host unwinding.

- **The current `error(code: i32)` convention is likely under-shaped.**
  Lua errors carry at least a status, an error object, stack/frame unwind obligations, possible to-be-closed variables, and protected-call target state. A single integer continuation preserves control explicitness but loses data explicitness. This becomes especially inadequate for `pcall`, `xpcall`, `__close`, native errors, and coroutine boundaries.

- **The VM’s `resume_mode` fields are a pressure point for explicit modeling.**
  Lalin encourages state machines as blocks/typed products. The VM currently encodes resumptions with numeric `resume_mode` plus generic `resume_a/b/c/value` fields. That may be compact, but it risks becoming exactly the “state: i32 plus scattered fields” anti-pattern unless every mode’s payload invariant is explicit and mechanically validated.

- **Lua coroutine support should be understood as explicit suspension, not a hidden scheduler.**
  `explicit_programming.md` says suspension is a state struct plus resume tag. That aligns with the VM’s frame model, but implies that every yieldable path—Lua call, native call, metamethod, iterator, `__close`, protected call—must have a complete saved-state shape. Coroutine support cannot be bolted on as an outer wrapper.

- **Native Lua functions need a Lalin-owned ABI, not PUC’s implicit C API behavior.**
  A `CClosure` function pointer can be monomorphic, but Lua-native functions may need to return normally, error, yield, request more stack, or trigger GC. A raw C-style `int (*)(lua_State*)` convention hides too many outcomes unless the VM defines how those outcomes are encoded in `LuaThread` state and return values.

- **Host ABI and internal ABI should not be conflated.**
  Lalin views have configurable host exposure policies, while the VM uses raw structs/pointers (`Value`, `Table`, `Proto`, `LuaThread`). Exposing internal VM memory through host proxies or assuming LuaJIT FFI scratch memory is not the same as defining the VM’s stable ABI. Tests that manually allocate objects do not validate runtime ownership.

- **Pointer types do not encode nullability or lifetime.**
  Lalin’s `ptr(T)` carries no null/lifetime information. For VM completion, nullability of `Proto.code`, `Table.array`, `String.bytes`, allocator returns, native closure pointers, and frame arrays must be explicit invariants. Contracts are compile-time facts, not runtime checks; violating them is UB.

- **`noalias`/`readonly` facts are dangerous around VM state.**
  The Lua VM has intentional aliasing: stack slots can reference heap objects; open upvalues point into the stack; tables point to values; closures share protos/upvalues. Overusing Lalin alias facts could let the backend optimize across mutations incorrectly. The safe facts are narrower than they may look.

- **Lua dynamic dispatch must be explicit tag dispatch.**
  Lalin has no runtime type dispatch, inheritance, or polymorphic inline caches. Lua’s dynamic behavior—value tags, metamethod lookup, callable values, numeric coercion, table/string/userdata dispatch—must remain visible as tag checks, table lookups, and named continuations. Hidden host-side dispatch tables would violate the design philosophy.

- **Metamethod names are runtime strings but semantic operations are not.**
  Lua uses names like `"__add"` and `"__index"`, but the VM should treat the semantic operation as an explicit `TM_*` event. If metamethod dispatch is driven by string conventions rather than typed/tagged events, the design becomes stringly-typed internally. Current `TM` constants are aligned with Lalin; string interning must preserve that contract.

- **Bytecode validation is part of the explicit-programming boundary.**
  Lalin control validation emits facts for jumps, labels, yields, etc. The Lua VM executes a separate bytecode language, so it needs an analogous explicit validation layer. Otherwise opcode handlers rely on hidden assumptions: valid registers, adjacent `MMBIN`, valid `EXTRAARG`, frame shape, constant bounds, and call/return discipline.

- **The Lua VM’s GC is a language feature, not infrastructure.**
  Lalin has no GC. Lua does. Therefore GC cannot be treated as “runtime support”; it is part of the VM being implemented. Mark state, gray lists, barriers, weak modes, finalizers, object colors, allocator debt, and emergency GC paths are semantic data/control nodes.

- **PUC’s C stack should not leak into VM design.**
  Lalin region composition has no call frame; Lua call frames are explicit VM data. This is a strength, but it means nested Lua calls, tail calls, metamethod calls, native callbacks, and yields must update `LuaThread`/`Frame` state coherently. Accidentally relying on the host call stack would produce a PUC-shaped hidden runtime.

- **Extern symbol binding differs between JIT tests and standalone output.**
  The language reference supports `M:symbol("puts", ffi.C.puts)` for JIT binding, but standalone/object emission needs linker-visible symbols. VM completion cannot depend on LuaJIT FFI-only symbol injection if the VM is meant to be a Lalin-native artifact.

- **“Compatible with Lua 5.5” needs a semantic contract separate from PUC layout.**
  Lalin should not clone PUC internals, but compatibility still requires precise choices for numeric equality, table key canonicalization, varargs, to-be-closed variables, coroutine yieldability, C API behavior, debug hooks, and bytecode/source compatibility. Without that contract, PUC behavior may be copied accidentally through hidden assumptions.

### Knowledge Gaps

- Exact bleeding-edge Lua 5.5 semantics and deltas from 5.4, especially around bytecode, numeric keys, TBC, varargs, coroutines, and C API.
- Intended native-function ABI: PUC-compatible `lua_CFunction`, Lalin-owned sealed ABI, or both.
- Intended allocator boundary: libc-backed, host-provided callback, arena-first, or VM-owned allocator protocol.
- Whether standalone Lalin VM must link without LuaJIT/FFI support.
- Whether bytecode compatibility with PUC Lua 5.5 is required, or only source/program semantic compatibility.

## Approach-proposer Output — 2026-05-29 09:22:03

### Approach A: Runtime Object Economy First

- **Core idea**: Complete the Lalin-native heap, string/table/closure/upvalue/runtime services first, then finish opcode semantics on top of a real object economy.
- **Key changes**:
  - `src/products.lua`: firm up `GCHeader`, object structs, allocator state, string table, table layout, native closure/upvalue invariants.
  - `src/regions_gc.lua`: implement VM-owned allocation protocol, GC roots, mark/propagate/sweep or an explicit first collector.
  - `src/regions_string.lua`: implement interning, concat, numeric/string conversion.
  - `src/regions_table.lua`: implement creation, growth, insertion, canonical numeric keys, barriers, `next`.
  - `src/regions_upvalue.lua`, `src/op/closure.lua`: implement closure/upvalue allocation and open-upvalue ordering.
  - Then fill `NEWTABLE`, `SETLIST`, `CLOSURE`, `VARARG`, `LEN`, `CONCAT`, arithmetic/metamethod fallbacks, loops.
- **Tradeoff**: Optimizes for a coherent semantic substrate and avoids building features on scratch-memory scaffolding; sacrifices fast visible Lua-language breadth early.
- **Risk**: GC/allocation/table/string design can absorb a lot of time before user-facing conformance improves.
- **What done means**:
  - VM can allocate and reclaim all core Lua objects itself.
  - Strings are interned everywhere; string equality/table-key semantics no longer depend on hand-built FFI objects.
  - Tables support ordinary Lua insertion/growth/iteration/metatables.
  - Closures and upvalues work across nested functions and returns.
  - Existing fast opcode paths still benchmark within an accepted regression budget.
- **Rough sketch**:
  - Define explicit allocator contract: `ok`, `step_required`, `oom`; no hidden libc semantics.
  - Implement minimal correct GC first, even if non-generational/non-incremental.
  - Wire barriers into table writes, closure setup, upvalue closing, metatable/global mutations.
  - Replace OOM stubs in object-creating regions with real allocation paths.
  - Expand tests from manually built protos to allocator-backed protos/strings/tables/closures.

---

### Approach B: Lua 5.5 Conformance Slices

- **Core idea**: Drive completion from Lua-visible behavior by implementing vertical semantic slices against a Lua 5.5 oracle/test corpus while preserving Lalin’s explicit control/data model internally.
- **Key changes**:
  - Add a conformance harness under `experiments/lua_interpreter_vm/tests/` comparing Lalin VM behavior with bleeding-edge Lua 5.5 behavior.
  - Expand `src/regions_compiler.lua`, `regions_parser.lua`, `regions_codegen.lua` enough to compile representative Lua programs, not just arithmetic.
  - Implement runtime features slice-by-slice: tables + strings, functions + calls, control flow, metamethods, errors/protected calls, coroutines, libraries.
  - Strengthen `src/validate.lua` alongside every new bytecode feature.
  - Keep `tools/jit_harness`/SponJIT code out of the acceptance path.
- **Tradeoff**: Optimizes for externally meaningful semantic compatibility and prevents “complete opcode inventory but wrong Lua”; sacrifices architectural purity sequencing because some runtime pieces may start minimal and be refined as slices demand.
- **Risk**: Top-down conformance can pressure the implementation into ad-hoc bridges unless strict explicit-programming boundaries are enforced.
- **What done means**:
  - A declared Lua 5.5 compatibility suite passes, including numeric edge cases, tables, closures, varargs, metamethods, protected errors, coroutines, and standard behavioral tests.
  - Every accepted semantic feature has both source-level and bytecode-level tests.
  - Deviations from Lua 5.5 are documented as deliberate, not accidental.
  - No conformance test relies on PUC internals, PUC bytecode layout, `longjmp`, or hidden C-stack behavior.
- **Rough sketch**:
  - Pin exact Lua 5.5 semantic contract locally: numeric equality, table key canonicalization, varargs, TBC, coroutine yieldability, C/native API boundary.
  - Build differential tests that run the same Lua snippets on Lalin VM and a Lua 5.5 reference.
  - Implement one vertical feature at a time, including parser/compiler, bytecode validation, runtime regions, and VM loop behavior.
  - Fix known semantic hazards during relevant slices: cached `code/constants` on frame switch, call result placement, metamethod scratch clobbering.
  - Add malformed-bytecode tests for every sequencing invariant: `MMBIN`, `LOADKX/EXTRAARG`, register bounds, upvalues, call/return windows.

---

### Approach C: Explicit VM Contract / ABI First

- **Core idea**: Stabilize the VM’s explicit contracts—bytecode validation, host/native ABI, call/error/yield protocols, and frame invariants—before filling out all runtime features.
- **Key changes**:
  - Add a formal VM contract document near `experiments/lua_interpreter_vm/`, separate from SponJIT docs.
  - `src/products.lua`: revise `LuaThread`, `Frame`, protected-call records, native-call ABI structs, error objects, coroutine state, allocator hooks.
  - `src/regions_call.lua`: redesign call/return around explicit result destinations, frame switching, Lua/native call outcomes, tail calls, yieldable resumptions.
  - `src/regions_error.lua`, `regions_coroutine.lua`: unify opcode errors, protected unwinds, TBC close, native errors, yields.
  - `src/validate.lua`: become the canonical bytecode trust boundary for interpreter and future JIT.
  - `src/api.lua`: expose only ABI-stable host/native entry points.
- **Tradeoff**: Optimizes for long-term stability before SponJIT or external embedders consume accidental behavior; sacrifices short-term feature completion because contracts are designed before many features are fully implemented.
- **Risk**: Over-designing the ABI too early could freeze poor choices before enough Lua 5.5 behavior has been exercised.
- **What done means**:
  - Stable documented ABI for `Value`, `Proto`, `LuaThread`, allocator hooks, native functions, API entry points, and error/yield outcomes.
  - All multi-outcome behavior uses explicit continuations/state, not hidden libc return conventions, exceptions, or PUC-style `longjmp`.
  - Validator enforces every interpreter/JIT assumption: register bounds, constant bounds, opcode pairings, frame shapes, upvalue bounds, stack effects.
  - Calls, metamethods, protected calls, native calls, and coroutines share one coherent resume/unwind protocol.
  - SponJIT can later target this contract without depending on scaffolding.
- **Rough sketch**:
  - Specify internal ABI vs host ABI separately; do not expose scratch-memory test conventions as runtime ABI.
  - Replace `error(code: i32)`-only paths with explicit error object/status/unwind protocol.
  - Define native function ABI with normal return, error, yield, OOM, and stack-growth outcomes.
  - Normalize frame invariants: cached proto pointers must reload when `frame` changes; result placement is `base + A`; metamethod calls use safe scratch/result areas.
  - Harden validation before optimizing dispatch or adding JIT-facing assumptions.

---

### Comparison

- **Approach A** centers the heap/object economy: allocation, GC, strings, tables, closures, and upvalues become real before broad Lua behavior.
- **Approach B** centers observable Lua 5.5 compatibility: features are completed as vertical conformance slices from source program to VM behavior.
- **Approach C** centers stable contracts: ABI, bytecode validation, call/error/yield/coroutine protocols, and host boundaries are fixed before SponJIT can consume them.

## Critique Output — 2026-05-29 09:57:55

Scale note: for **Migration cost / Risk** rows, higher = more costly/risky. For readiness/fit/testability, higher = better.

### Approach A: Runtime Object Economy First

| Dimension | Score (1-5) | Rationale |
|-----------|-------------|-----------|
| **Coupling** | 3/5 | Correctly treats allocator/GC/strings/tables/closures as interdependent, but risks creating a large runtime-service cluster before call/error/yield contracts are settled. |
| **Cohesion** | 4/5 | Very cohesive around the deepest blocker: the VM cannot yet create/manage Lua objects. |
| **Migration cost** | 4/5 | Requires touching core structs, allocation paths, table/string/upvalue semantics, opcode stubs, and tests. |
| **Philosophy fit** | 4/5 | Strong fit if allocation/GC outcomes remain explicit continuations; weaker if implementation falls back to hidden libc/host behavior. |
| **Performance risk** | 3/5 | Table/string/GC choices could affect hot paths, but current dispatch architecture can remain intact. |
| **Semantic compatibility risk** | 3/5 | Reduces many semantic risks, especially strings/tables/closures, but may still miss call/error/coroutine invariants. |
| **SponJIT readiness** | 3/5 | Gives SponJIT real objects to target, but not necessarily a stable bytecode/call/error contract. |
| **Risk** | 4/5 | GC/table/string design can consume large effort before broad Lua conformance improves. |
| **Testability** | 3/5 | Can be tested incrementally, but many failures will be cross-cutting once GC/allocation are introduced. |

**Verdict**: Yes with caveats
**Key concern**: Do not let “object economy first” proceed without simultaneously preserving explicit allocation, barrier, and lifetime invariants.

---

### Approach B: Lua 5.5 Conformance Slices

| Dimension | Score (1-5) | Rationale |
|-----------|-------------|-----------|
| **Coupling** | 3/5 | Vertical slices naturally cross parser/compiler/runtime/validator/VM loop, which is useful but can couple layers through test pressure. |
| **Cohesion** | 3/5 | Cohesive around observable Lua behavior, less cohesive architecturally because each slice spans many subsystems. |
| **Migration cost** | 4/5 | Requires compiler expansion, runtime completion, validation hardening, and differential test infrastructure. |
| **Philosophy fit** | 3/5 | Compatible with Lalin if strict explicit boundaries are enforced; otherwise likely to invite ad-hoc compatibility bridges. |
| **Performance risk** | 2/5 | Lower immediate performance risk because features are added by behavior slice, but late architectural correction could hurt later. |
| **Semantic compatibility risk** | 2/5 | Best at preventing “opcode-complete but semantically wrong” outcomes. |
| **SponJIT readiness** | 3/5 | Strong semantic signal, but SponJIT still needs stable ABI/validation contracts, not just passing behavior tests. |
| **Risk** | 3/5 | Main risk is ad-hoc implementation under conformance pressure. |
| **Testability** | 5/5 | Best incremental validation story: source-level, bytecode-level, malformed-bytecode, and differential tests. |

**Verdict**: Yes with caveats
**Key concern**: Conformance pressure must not override the Lalin rule that control/data outcomes are explicit and typed.

---

### Approach C: Explicit VM Contract / ABI First

| Dimension | Score (1-5) | Rationale |
|-----------|-------------|-----------|
| **Coupling** | 4/5 | Best at separating internal ABI, host ABI, bytecode validation, call protocol, error protocol, and future JIT assumptions. |
| **Cohesion** | 5/5 | Highly cohesive around the most important pre-SponJIT question: what contract is the VM actually promising? |
| **Migration cost** | 5/5 | Likely forces deep revisions to `Frame`, `LuaThread`, call/return, error handling, coroutine state, validation, and API surfaces. |
| **Philosophy fit** | 5/5 | Strongest alignment with Lalin’s explicit-programming philosophy: no hidden exceptions, C-stack behavior, implicit allocator semantics, or stringly contracts. |
| **Performance risk** | 3/5 | May require reworking cached hot-state assumptions, but doing this before SponJIT reduces long-term performance debt. |
| **Semantic compatibility risk** | 3/5 | Reduces structural semantic risks, but can still freeze wrong contracts if not exercised against real Lua behavior. |
| **SponJIT readiness** | 5/5 | Best SponJIT preparation: validator, ABI, frame invariants, error/yield/call semantics become stable before optimization. |
| **Risk** | 4/5 | High over-design risk: contracts may be specified before allocation/table/coroutine/conformance realities fully stress them. |
| **Testability** | 4/5 | Validator and protocol invariants are testable incrementally, though some ABI choices need later semantic pressure. |

**Verdict**: Strong yes, with important caveats
**Key concern**: Contract-first must not become contract-only. The contract needs early pressure from real object allocation and Lua-visible conformance tests before being treated as frozen.

---

### Summary

- **Recommended**: **Approach C: Explicit VM Contract / ABI First**.
  It best matches Lalin’s design philosophy and is the safest pre-SponJIT gate. The current VM’s deepest SponJIT hazards are contract hazards: cached `code/constants` across frame switches, underspecified result placement, weak validation, under-shaped error paths, native-call ambiguity, and coroutine/yield protocol gaps.

- **Dark horse**: **Approach B**.
  It has the most upside for semantic correctness because it keeps the project honest against real Lua 5.5 behavior. Its danger is architectural drift if conformance is pursued without strict explicit-control discipline.

- **Avoid as sole path**: **Approach A**.
  It addresses the biggest runtime blocker, but by itself it can produce a better heap under an unstable call/error/ABI contract. That would still leave SponJIT targeting accidental behavior.

Given the user’s inclination toward C: I agree. Choose C as the architectural gate before SponJIT. The caution is that C should be validated quickly against A-style runtime realities and B-style conformance evidence, otherwise it risks freezing elegant but unexercised ABI decisions.

## Edit-planner Output — 2026-05-29 11:07:21

### Precondition Checks

Before edits, verify the repo still matches these anchors:

- `experiments/lua_interpreter_vm/src/products.lua`
  - `Frame` is still defined at line 69 with 13 fields.
  - `LuaThread` is still defined at line 78 with 18 fields.
  - `NativeFunc` is still the simple `{ addr, flags }` struct at line 42.
- `experiments/lua_interpreter_vm/src/constants.lua`
  - Opcodes still end at `Op.EXTRAARG = 84` around line 92.
  - `Resume` still has modes `0..16` around lines 134-151.
- `experiments/lua_interpreter_vm/src/regions_call.lua`
  - `prepare_call` starts at line 14.
  - `return_from_lua` starts at line 109.
  - `handle_return_mode` starts at line 191.
- `experiments/lua_interpreter_vm/src/vm_loop.lua`
  - `cont_resume_parent` still forwards cached `code/constants` at lines 113-116.
- `experiments/lua_interpreter_vm/src/opcodes.lua`
  - `dispatch_instruction` continuation signatures start around lines 590-610.
  - `cont_resume` still forwards `cur_code/cur_consts` at lines 628-632.
- Confirm `prepare_call(` is only emitted in:
  - `src/op/call.lua`
  - `src/op/_init.lua`
  - `src/regions_call.lua`

---

### Files to Modify

#### `experiments/lua_interpreter_vm/VM_CONTRACT.md`

**Goal**: Add the architectural contract artifact for Approach C.

**Edit blocks**

1. **New file**: Add complete contract document.
   - Include sections:
     - Scope: Lalin-native Lua 5.5 VM contract, not SponJIT.
     - Internal ABI: `Value`, `Proto`, `Frame`, `LuaThread`, `GlobalState`.
     - Host ABI: sealed API functions only.
     - Native ABI: explicit native call result protocol; no hidden `longjmp`, exceptions, or allocator side channels.
     - Bytecode validation contract: validator is required before execution/JIT.
     - Frame/cache invariant: whenever `Frame*` changes, cached `code/constants` must be reloaded from that frame’s closure.
     - Call/return invariant: call results land at explicit `result_base`, never implicitly at `parent.base`.
     - Error/protected unwind invariant: opcode errors must flow through error-object/protected-unwind path.
     - Coroutine/yield invariant: all yieldable paths must carry explicit saved state.
     - Allocator/extern boundary: no raw malloc/libc semantics inside VM semantics.
     - SponJIT gate: no SponJIT integration until validator + frame/error/native contracts are tested.

**Patterns to enforce**
- Use “MUST/SHOULD/MUST NOT” language.
- Keep PUC Lua as semantic reference only, not layout/runtime reference.

**Danger zones**
- Do not describe scratch-memory FFI tests as the stable ABI.
- Do not mention SponJIT as an implementation dependency.

---

#### `experiments/lua_interpreter_vm/src/contract.lua`

**Goal**: Add a machine-readable Lua-side contract summary for tests/tooling.

**Edit blocks**

1. **New file**:
   - Define:
     ```lua
     return {
       vm_abi_version = 1,
       native_abi_version = 1,
       validator_contract_version = 1,
       sponjit_allowed = false,
       required_gates = {
         "bytecode_validator_complete",
         "frame_cache_reload_on_switch",
         "explicit_call_result_base",
         "unified_error_unwind",
         "explicit_native_abi",
         "explicit_allocator_boundary",
       },
     }
     ```

**Patterns to enforce**
- Plain Lua table only; no Lalin fragments here.

**Danger zones**
- Do not import VM modules from this file; avoid load cycles.

---

#### `experiments/lua_interpreter_vm/src/init.lua`

**Goal**: Export the contract table.

**Edit blocks**

1. **Lines 5-8**: Add contract require after constants.
   - Before:
     ```lua
     vm.const = require("experiments.lua_interpreter_vm.src.constants")
     vm.parser_const = require(...)
     ```
   - After:
     ```lua
     vm.const = require("experiments.lua_interpreter_vm.src.constants")
     vm.contract = require("experiments.lua_interpreter_vm.src.contract")
     vm.parser_const = require(...)
     ```

**Danger zones**
- Keep `contract.lua` before heavy region modules; it must not depend on them.

---

#### `experiments/lua_interpreter_vm/src/constants.lua`

**Goal**: Add explicit ABI/native/yield contract constants without changing opcode values.

**Edit blocks**

1. **Lines 134-151**: Extend `Resume`.
   - Add:
     ```lua
     Resume.N = 17
     ```
   - Do not renumber existing modes.

2. **After lines 153-158 `Status`**: Add native result statuses.
   ```lua
   local NativeResult = {}
   NativeResult.OK = 0
   NativeResult.ERROR = 1
   NativeResult.YIELD = 2
   NativeResult.OOM = 3
   NativeResult.STACK_GROW = 4
   ```

3. **After `ProtoFlag` around lines 179-183**: Add frame/thread flags.
   ```lua
   local FrameFlag = {}
   FrameFlag.YIELDABLE = 1
   FrameFlag.PROTECTED = 2
   FrameFlag.NATIVE = 4

   local ThreadFlag = {}
   ThreadFlag.YIELDABLE = 1
   ThreadFlag.IN_PROTECTED = 2
   ThreadFlag.CLOSING = 4
   ```

4. **After `MAX_FRAMES` around lines 196-197**: Add ABI constants.
   ```lua
   local Abi = {}
   Abi.VM_VERSION = 1
   Abi.NATIVE_VERSION = 1
   Abi.VALIDATOR_VERSION = 1
   ```

5. **Return table lines 199-211**: Export new tables.
   - Add:
     ```lua
     NativeResult = NativeResult,
     FrameFlag = FrameFlag,
     ThreadFlag = ThreadFlag,
     Abi = Abi,
     ```

**Patterns to enforce**
- Constants are append-only.
- Existing opcode/resume/error numeric values must remain stable.

**Danger zones**
- Do not change `Op.*` numbers.
- Do not change `Status.OK/YIELDED/RUNTIME_ERROR/OOM/DEAD`.

---

#### `experiments/lua_interpreter_vm/src/products.lua`

**Goal**: Make the internal/native/allocator ABI explicit in structs.

**Edit blocks**

1. **Line 42 `NativeFunc`**: Replace simple native descriptor.
   - Before:
     ```lua
     local NativeFunc = host.struct [[struct NativeFunc addr: ptr(u8); flags: u32 end]]
     ```
   - After:
     ```lua
     local NativeFunc = host.struct [[struct NativeFunc abi_version: u32; flags: u32; addr: ptr(u8); name: ptr(String) end]]
     local NativeCallResult = host.struct [[struct NativeCallResult status: u8; nresults: i32; err: Value; continuation: ptr(u8) end]]
     ```

2. **Line 63 `Allocator`**: Replace opaque-only allocator with explicit hook container.
   - Before:
     ```lua
     local Allocator = host.struct [[struct Allocator _opaque: ptr(u8) end]]
     ```
   - After:
     ```lua
     local Allocator = host.struct [[struct Allocator abi_version: u32; flags: u32; userdata: ptr(u8); alloc: ptr(u8); realloc: ptr(u8); free: ptr(u8) end]]
     ```

3. **Line 66 `ProtectedFrame`**: Extend protected unwind state.
   - Add fields for:
     - `status: u8`
     - `flags: u8`
     - `resume_mode: u16`
     - `saved_frame_count: index`
   - Keep existing fields after these or append them consistently.

4. **Line 69 `Frame`**: Append explicit call-result/yield fields.
   - Existing 13 fields remain first.
   - Append:
     ```lalin
     result_base: index;
     call_top: index;
     yieldable: u8;
     flags: u8;
     reserved: u16;
     ```
   - New field count becomes 18.

5. **Line 75 `GlobalState`**: Append ABI version fields only at the end.
   - Add:
     ```lalin
     vm_abi_version: u32;
     native_abi_version: u32;
     ```
   - Keep first fields unchanged: `allocator`, `registry`, `mainthread`.

6. **Line 78 `LuaThread`**: Append coroutine/error contract fields.
   - Existing 18 fields remain first.
   - Append:
     ```lalin
     yieldable: i32;
     nonyieldable: i32;
     last_error_code: i32;
     flags: u32;
     ```
   - New field count becomes 22.

7. **Return table lines 83-110**: Export `NativeCallResult`.

**Patterns to enforce**
- Append fields where possible to preserve old offsets.
- Keep `GlobalState.allocator`, `registry`, `mainthread` as first fields.

**Danger zones**
- Existing tests allocate scratch structs manually; every FFI cdef must be updated.
- Do not insert fields before `Frame.closure/base/top/pc`.
- Do not insert fields before `LuaThread.stack/frames/global`.

---

#### `experiments/lua_interpreter_vm/src/regions_stack.lua`

**Goal**: Store explicit frame call-result metadata.

**Edit blocks**

1. **Lines 33-60 `frame_push`**: Extend signature and initialization.
   - Before:
     ```lalin
     region frame_push(L, closure, base, top, wanted, resume_mode; ...)
     ```
   - After:
     ```lalin
     region frame_push(L, closure, base, top,
                       result_base: index,
                       call_top: index,
                       wanted: i32,
                       resume_mode: u16,
                       resume_pc: index,
                       yieldable: u8; ...)
     ```
   - Initialize:
     ```lalin
     f.result_base = result_base
     f.call_top = call_top
     f.yieldable = yieldable
     f.flags = 0
     f.reserved = 0
     f.resume_pc = resume_pc
     ```

2. **Lines 79-110 `adjust_results`**: Add contract comment.
   - State explicitly:
     - `dst` is the call’s explicit result base.
     - Never substitute `parent.base`.

**Danger zones**
- Lalin blocks cannot capture local values from previous blocks unless passed as params or stored in structs.
- Ensure all `frame_push` call sites are updated.

---

#### `experiments/lua_interpreter_vm/src/regions_call.lua`

**Goal**: Stabilize call/return result placement and native-call ABI shape.

**Edit blocks**

1. **Lines 21-30 `prepare_call` signature**: Add explicit call metadata.
   - Add params:
     ```lalin
     caller_pc: index,
     result_base: index,
     call_top: index,
     yieldable: u8
     ```
   - Update `enter_native` continuation to carry native ABI metadata:
     ```lalin
     enter_native: cont(cl: ptr(CClosure),
                        func_slot: index,
                        nargs: i32,
                        wanted: i32,
                        result_base: index,
                        resume_mode: u16)
     ```

2. **Lines 45-51 C closure branch**:
   - Before:
     ```lalin
     jump enter_native(cl = cl)
     ```
   - After:
     ```lalin
     jump enter_native(cl = cl, func_slot = func_slot, nargs = nargs,
                       wanted = wanted, result_base = result_base,
                       resume_mode = resume_mode)
     ```

3. **Lines 55-70 `push_frame`**:
   - Update `frame_push` emit to pass:
     - `result_base`
     - `call_top`
     - `wanted`
     - `resume_mode`
     - `caller_pc`
     - `yieldable`

4. **Lines 94-105 `call_native`**:
   - Extend signature:
     ```lalin
     region call_native(L, cl, func_slot, nargs, wanted, result_base, resume_mode; ...)
     ```
   - Keep fail-loud implementation for now:
     - If `cl.fn == nil`, error `ERR_CALL`.
     - If `cl.fn.abi_version ~= Abi.NATIVE_VERSION`, error `ERR_CALL`.
     - Otherwise still `ERR_CALL` until invocation is implemented.
   - Set `L.last_error_code = ERR_CALL` before error.

5. **Lines 109-188 `return_from_lua`**:
   - Before decrementing `L.frame_count`, capture from child frame:
     ```lalin
     let ret_result_base = frame.result_base
     let ret_wanted = frame.wanted
     let ret_resume_mode = frame.resume_mode
     let ret_resume_a = frame.resume_a
     let ret_resume_pc = frame.resume_pc
     let ret_resume_base = frame.resume_base
     let ret_resume_value = frame.resume_value
     ```
   - Pass these into `handle_return_mode`.
   - Do not let `handle_return_mode` read `parent.resume_mode` for the child return.

6. **Lines 191-279 `handle_return_mode`**:
   - Extend signature with captured child return metadata.
   - Switch on `resume_mode` param, not `parent.resume_mode`.
   - For `RESUME_NORMAL` and `RESUME_TAILCALL`, call:
     ```lalin
     emit adjust_results(L, first_result, nres, ret_wanted, ret_result_base; ...)
     ```
   - Resume at:
     ```lalin
     pc = ret_resume_pc + 1
     ```
   - Metamethod result cases use `ret_resume_a` and `ret_resume_pc`.

**Patterns to enforce**
- Child frame owns return-mode metadata.
- Parent frame owns resumed execution state.
- Result placement always uses explicit `result_base`.

**Danger zones**
- Current code silently places normal call results at `parent.base`; remove that behavior.
- Do not use `parent.resume_mode` for child return dispatch.
- Do not depend on native call success yet.

---

#### `experiments/lua_interpreter_vm/src/op/_init.lua`

**Goal**: Update shared opcode continuation signatures and stop metamethod scratch clobbering registers.

**Edit blocks**

1. **Lines 25-31 `TABLE_CONTS`**:
   - Change `enter_native` continuation to extended signature matching `prepare_call`.

2. **Lines 33-43 `TABLE_GET_MM_BLOCKS do_mm`**:
   - Before:
     ```lalin
     L.stack[base] = mm
     L.stack[base + 1] = self
     L.stack[base + 2] = key
     emit prepare_call(L, base, 2, 1, ...)
     ```
   - After:
     ```lalin
     let scratch: index = top
     L.stack[scratch] = mm
     L.stack[scratch + 1] = self
     L.stack[scratch + 2] = key
     emit prepare_call(L, scratch, 2, 1, ..., pc, scratch, top, as(u8, 1); ...)
     ```
   - Result copy reads from `scratch`, then writes to `base + a`.

3. **Lines 72-82 `TABLE_SET_MM_BLOCKS do_mm`**:
   - Same scratch-area change using `let scratch: index = top`.

4. **Lines 116-134 continuation strings**:
   - Update `CMP_CONTS`, `CALL_CONTS`, `MMBIN_CONTS` to use extended `enter_native`.

**Danger zones**
- Do not use `base` as scratch for metamethod calls.
- If a continuation needs `scratch`, pass it through block params or store in `frame.resume_base`.

---

#### `experiments/lua_interpreter_vm/src/op/call.lua`

**Goal**: Pass explicit call metadata into `prepare_call`.

**Edit blocks**

1. **Lines 21-32 `op_call`**:
   - Update `prepare_call` emit:
     ```lalin
     emit prepare_call(L, func_slot, nargs, wanted,
                       as(u16, @{RESUME_NORMAL}),
                       pc, func_slot, top, as(u8, 1); ...)
     ```

2. **Lines 34-40 `do_lua/do_native`**:
   - `do_lua` may keep setting `child.resume_a = a`, but `resume_pc` should already be initialized from `prepare_call`.
   - Update `do_native` signature to extended params and forward them.

3. **Lines 78-88 `op_tailcall`**:
   - Pass:
     ```lalin
     result_base = frame.result_base
     call_top = top
     resume_mode = RESUME_TAILCALL
     yieldable = frame.yieldable
     ```

4. **Lines 139-232 return handlers**:
   - No signature change required, but verify `return_from_lua` emit compiles with new return metadata internally.

**Danger zones**
- `CALL A B C` result base is `base + A`, not `base`.
- Tailcall must preserve caller’s result destination.

---

#### `experiments/lua_interpreter_vm/src/opcodes.lua`

**Goal**: Keep dispatch continuation ABI aligned and avoid stale cached code on frame switch.

**Edit blocks**

1. **Lines 590-610 `dispatch_instruction` signature**:
   - Update `enter_native` continuation to extended native metadata.

2. **Lines 634-638 `cont_enter_native`**:
   - Before:
     ```lalin
     block cont_enter_native(cl: ptr(CClosure))
         jump enter_native(cl = cl)
     end
     ```
   - After:
     ```lalin
     block cont_enter_native(cl: ptr(CClosure), func_slot: index,
                             nargs: i32, wanted: i32,
                             result_base: index, resume_mode: u16)
         jump enter_native(cl = cl, func_slot = func_slot, nargs = nargs,
                           wanted = wanted, result_base = result_base,
                           resume_mode = resume_mode)
     end
     ```

3. **Lines 604-606 / 628-632 `resume_parent`**:
   - Keep the existing `code/constants` params for compatibility, but mark them stale in a comment.
   - `vm_loop` will reload them; do not rely on these values.

**Danger zones**
- Do not reduce dispatch continuation count without updating smoke tests.
- Do not use wildcard switch arms.

---

#### `experiments/lua_interpreter_vm/src/vm_loop.lua`

**Goal**: Enforce frame-cache reload and route errors through unified error handling.

**Edit blocks**

1. **Lines 113-116 `cont_resume_parent`**:
   - Before: forwards `code/constants`.
   - After: reload from `parent.closure`:
     ```lalin
     let cl: ptr(LClosure) = as(ptr(LClosure), parent.closure.bits)
     let parent_code: ptr(Instr) = cl.proto.code
     let parent_constants: ptr(Value) = cl.proto.constants
     jump loop(frame = parent, pc = pc, base = base, top = top,
               code = parent_code, constants = parent_constants)
     ```

2. **Lines 125-134 `do_native/native_ret`**:
   - Change `do_native` signature to extended native metadata.
   - Emit new `call_native(L, cl, func_slot, nargs, wanted, result_base, resume_mode; ...)`.
   - Keep `native_ret` fail-loud unless native success path is implemented in same change.

3. **Lines 141-143 `do_error`**:
   - Replace direct `jump error(code = code)` with:
     - build error object
     - call `raise_code_error`
     - if caught: reload frame cache and resume caught frame
     - if uncaught: jump outer `error`.

**Danger zones**
- This file is the cached-proto-pointer danger zone.
- Every path that changes `frame` must reload `code/constants`.

---

#### `experiments/lua_interpreter_vm/src/regions_error.lua`

**Goal**: Make opcode errors flow through an explicit error-object/protected-unwind region.

**Edit blocks**

1. **After lines 11-20 `build_error_object`**: Add `raise_code_error`.
   ```lalin
   region raise_code_error(L: ptr(LuaThread), code: i32;
                           caught: cont(frame: ptr(Frame)),
                           uncaught: cont(code: i32),
                           oom: cont())
   ```
   - Build `culprit = nil`.
   - Emit `build_error_object`.
   - Store:
     ```lalin
     L.err_value = err
     L.last_error_code = code
     ```
   - Emit `raise_error`.

2. **Lines 102-153 `raise_error`**:
   - Ensure caught path returns the frame to resume.
   - Ensure uncaught path preserves `L.err_value` and `L.last_error_code`.

3. **Lines 156-174 `enter_protected`**:
   - Keep OOM behavior if allocator is unavailable.
   - Add comment that `ProtectedFrame` allocation must use VM allocator, not host stack/setjmp.

4. **Lines 177-188 `protected_call`**:
   - Failure result should use `build_error_object` or set `L.err_value`.
   - Do not silently return nil-only errors.

5. **Return table lines 190-196**:
   - Export `raise_code_error`.

**Danger zones**
- Do not bypass TBC close in protected unwind.
- Do not introduce host exceptions/longjmp.

---

#### `experiments/lua_interpreter_vm/src/regions_coroutine.lua`

**Goal**: Encode coroutine/yield protocol as explicit state, even if full resume remains incomplete.

**Edit blocks**

1. **Lines 6-8 imports/constants**:
   - Import `Status` and `ThreadFlag`.

2. **Lines 11-22 `coroutine_resume`**:
   - Keep full implementation pending, but distinguish:
     - dead target
     - running target
     - yielded target
   - Set `target.last_error_code` on error.

3. **Lines 25-36 `coroutine_yield`**:
   - Check:
     ```lalin
     if L.nonyieldable > 0 then jump not_yieldable() end
     ```
   - On allowed yield:
     ```lalin
     L.status = THREAD_YIELDED
     jump yielded(nres = nres)
     ```

**Danger zones**
- Do not call `vm_resume` from this file if that creates a require cycle.
- Yieldability must be data in `LuaThread`/`Frame`, not hidden control flow.

---

#### `experiments/lua_interpreter_vm/src/regions_gc.lua`

**Goal**: Document and enforce allocator boundary: no hidden malloc semantics.

**Edit blocks**

1. **Lines 14-24 `alloc_object`**:
   - Add checks:
     ```lalin
     if G == nil or G.allocator == nil then jump oom() end
     ```
   - If `G.totalbytes > G.threshold`, jump `step_required`.
   - Otherwise still `oom()` until allocator extern bridge exists.
   - Comment: allocator invocation must return explicit `ok/oom/step_required`.

2. **Lines 27-38 `gc_check`**:
   - Preserve explicit `step` outcome.

**Danger zones**
- Do not add raw libc allocation here.
- Do not hide OOM in null pointer returns.

---

#### `experiments/lua_interpreter_vm/src/validate.lua`

**Goal**: Make bytecode validation the canonical interpreter/JIT trust boundary.

**Edit blocks**

1. **Lines 12-18 validation constants**:
   - Add all opcode constants needed for sequencing:
     - arithmetic ops `ADDI..SHR`, `ADD..SHR`
     - `MMBIN/MMBINI/MMBINK`
     - `RETURN/RETURN0/RETURN1`
     - `CALL/TAILCALL`
     - table/upvalue/loop opcodes.

2. **Lines 20-29 `start`**:
   - Add pointer/shape checks:
     ```lalin
     if p.maxstack == 0 then invalid
     if p.code_len > 0 and p.code == nil then invalid
     if p.constants_len > 0 and p.constants == nil then invalid
     ```

3. **Lines 35-43 decode block**:
   - Decode `b`, `c`, `k`, `ax/extra_bx`.
   - Add helpers as blocks or inline checks:
     - `check_reg(idx)`
     - `check_const(idx)`
     - `check_child(idx)`
     - `check_next_is(pc, op)`.

4. **Lines 44-66 opcode checks**:
   - Replace minimal checks with opcode-family checks:
     - Register A/B/C bounds for opcodes that read/write registers.
     - Constant bounds for `LOADK`, `LOADKX`, `*K`, `EQK`, `GETFIELD/SETFIELD`.
     - Child bounds for `CLOSURE`.
     - Jump target bounds for all jump/loop ops.
     - `LOADKX` must be followed by `EXTRAARG`; extra arg constant index must be valid.
     - `EXTRAARG` cannot appear standalone.
     - Arithmetic fast-path ops must be followed by correct `MMBIN*`.
     - `MMBIN*` cannot appear without matching predecessor.
     - `CALL/TAILCALL/RETURN` register windows must fit `maxstack`.
     - Loop register windows must fit `maxstack`.

5. **Loop increment**:
   - When validating paired instructions, skip the pair only if safe, or continue linearly while remembering predecessor state.
   - Prefer explicit `prev_op`/`prev_pc` block params over hidden state.

**Danger zones**
- Validator must not use wildcard “valid by default” for opcode families.
- Validate the same assumptions the interpreter/JIT will rely on.

---

#### `experiments/lua_interpreter_vm/src/api.lua`

**Goal**: Keep host API sealed and expose ABI status explicitly.

**Edit blocks**

1. **After line 10**: Add ABI constant imports.
   - Use `const.Abi`.

2. **After `lua_tolstring_api` around line 86**: Add:
   ```lalin
   lua_vm_abi_version_api() -> i32
   lua_native_abi_version_api() -> i32
   lua_status_api(L: ptr(LuaThread)) -> i32
   lua_last_error_api(L: ptr(LuaThread)) -> i32
   ```

3. **Lines 96-134 erroring APIs**:
   - For `lua_gettable_api`, `lua_settable_api`, `lua_call_api`, `lua_pcall_api`:
     - Set `L.status = THREAD_RUNTIME_ERROR`.
     - Set `L.last_error_code` to the relevant `ERR_*`.

4. **Return table lines 126-137**:
   - Export new API functions.

**Danger zones**
- Do not make table/call APIs silently perform partial semantics.
- Host API functions are sealed boundaries; no hidden VM control paths.

---

### Tests to Add or Update

#### `experiments/lua_interpreter_vm/tests/test_vm_smoke.lua`

**Goal**: Update structural expectations.

**Edit blocks**

1. **Lines 33-35 continuation counts**:
   - Update expected dispatch continuation signatures if count changes.
   - If count remains 9, update only descriptive text.

2. **Lines 40-42 field counts**:
   - Update:
     ```lua
     Frame has 18 fields
     LuaThread has 22 fields
     ```
   - Add checks:
     ```lua
     NativeCallResult exists
     contract vm_abi_version == 1
     contract sponjit_allowed == false
     ```

3. **Wrapper around lines 45-85**:
   - Update `enter_native` block signature to extended params.

---

#### Existing FFI tests

Files:
- `tests/test_vm_opcode_semantics.lua`
- `tests/test_vm_e2e.lua`
- `tests/test_parser_compile.lua`

**Goal**: Update C struct mirrors.

**Required cdef updates**
- `NativeFunc`: new fields if declared.
- `Frame`: append:
  ```c
  uint64_t result_base;
  uint64_t call_top;
  uint8_t yieldable;
  uint8_t flags;
  uint16_t reserved;
  ```
- `LuaThread`: append:
  ```c
  int32_t yieldable;
  int32_t nonyieldable;
  int32_t last_error_code;
  uint32_t flags;
  ```
- `GlobalState`: append:
  ```c
  uint32_t vm_abi_version;
  uint32_t native_abi_version;
  ```

**Initialization updates**
- Wherever `frames[0]` is initialized, set:
  ```lua
  frames[0].result_base = frames[0].base
  frames[0].call_top = frames[0].top
  frames[0].yieldable = 1
  frames[0].flags = 0
  frames[0].reserved = 0
  ```
- Wherever `LuaThread` is initialized, set:
  ```lua
  L.yieldable = 1
  L.nonyieldable = 0
  L.last_error_code = 0
  L.flags = 0
  ```

---

#### `experiments/lua_interpreter_vm/tests/test_vm_validation_contract.lua`

**Goal**: New malformed-bytecode validator tests.

**Contents sketch**
- Build minimal `Proto` via FFI.
- Compile wrapper around `validate_proto`.
- Cases:
  - valid `LOADK; RETURN1`
  - bad opcode `85`
  - `A >= maxstack`
  - `LOADK` constant out of bounds
  - `LOADKX` missing `EXTRAARG`
  - standalone `EXTRAARG`
  - `ADD` not followed by `MMBIN`
  - `ADDK` not followed by `MMBINK`
  - jump target out of range
  - `CALL` register window exceeds `maxstack`
  - `CLOSURE` child index out of bounds

---

#### `experiments/lua_interpreter_vm/tests/test_vm_call_frame_contract.lua`

**Goal**: Prove frame-cache reload and explicit result placement.

**Contents sketch**
- Build parent and child protos manually.
- Test 1: nested Lua call returns into `base + A`, not `parent.base`.
- Test 2: after child return, parent executes using parent `code/constants`, not child cached pointers.
- Use parent constants distinct from child constants to catch stale cache.

---

#### `experiments/lua_interpreter_vm/tests/test_vm_error_contract.lua`

**Goal**: Prove opcode errors set explicit error state.

**Contents sketch**
- Run proto with bad call target or bad opcode.
- Assert:
  - VM returns runtime error.
  - `L.last_error_code` matches.
  - `L.err_value.aux` carries error code.

---

#### `experiments/lua_interpreter_vm/tests/test_vm_abi_contract.lua`

**Goal**: Prove contract module/API versions are exposed.

**Contents sketch**
- Require `vm.contract`.
- Assert:
  - `vm_abi_version == const.Abi.VM_VERSION`
  - `native_abi_version == const.Abi.NATIVE_VERSION`
  - `sponjit_allowed == false`
- Compile and call new `lua_vm_abi_version_api`.

---

### Order of Operations

1. Add `VM_CONTRACT.md`.
2. Add `src/contract.lua` and export it from `src/init.lua`.
3. Extend constants in `constants.lua`.
4. Extend structs in `products.lua`.
5. Update FFI cdefs and smoke structural tests so the suite can load again.
6. Update `regions_stack.lua` frame metadata.
7. Update `regions_call.lua` call/return/native signatures.
8. Update opcode continuation signatures in `op/_init.lua`, `op/call.lua`, and `opcodes.lua`.
9. Update `vm_loop.lua` cache reload and native continuation plumbing.
10. Add unified error path in `regions_error.lua`; wire `vm_loop.do_error`.
11. Tighten coroutine and allocator boundary stubs.
12. Expand `validate.lua`.
13. Add new contract tests.
14. Run full VM test set.

---

### Testing Strategy

Run after each major stage:

```sh
luajit experiments/lua_interpreter_vm/tests/test_vm_smoke.lua
```

After FFI struct updates:

```sh
cargo build --release
luajit experiments/lua_interpreter_vm/tests/test_vm_e2e.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_opcode_semantics.lua
luajit experiments/lua_interpreter_vm/tests/test_parser_compile.lua
```

After validator work:

```sh
luajit experiments/lua_interpreter_vm/tests/test_vm_validation_contract.lua
```

After call/frame work:

```sh
luajit experiments/lua_interpreter_vm/tests/test_vm_call_frame_contract.lua
```

After error/API work:

```sh
luajit experiments/lua_interpreter_vm/tests/test_vm_error_contract.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_abi_contract.lua
```

Final verification:

```sh
luajit experiments/lua_interpreter_vm/tests/test_vm_smoke.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_e2e.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_opcode_semantics.lua
luajit experiments/lua_interpreter_vm/tests/test_parser_compile.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_validation_contract.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_call_frame_contract.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_error_contract.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_abi_contract.lua
```

---

### Pattern Memo

- All VM multi-outcome behavior uses explicit continuations.
- All frame switches reload `code/constants`.
- All call returns use explicit `result_base`.
- Native calls use explicit ABI/version/result status; no hidden C exceptions.
- Allocator paths never call raw malloc directly.
- Validator enforces interpreter/JIT assumptions.
- SponJIT remains gated and separate until contract tests pass.

## Worker Output — 2026-05-29 17:53:08

## Completed

Inspected `git status`/diff and workflow `wf-lua-vm-completion`, then continued from the existing partial Approach C implementation without restarting or touching SponJIT work.

Already present in the working tree before my edits:
- `VM_CONTRACT.md`
- `src/contract.lua` exported via `src/init.lua`
- ABI/version constants and expanded VM structs
- explicit native/call/frame metadata plumbing
- frame-cache reload in `vm_loop.lua`
- explicit error state / `raise_code_error`
- allocator/coroutine boundary stubs
- stronger `validate_proto`
- updated FFI struct mirrors
- new contract tests:
  - `test_vm_validation_contract.lua`
  - `test_vm_call_frame_contract.lua`
  - `test_vm_error_contract.lua`
  - `test_vm_abi_contract.lua`
- Many unrelated SponJIT files were also already dirty/deleted/untracked; I left them alone.

What I changed:
- Fixed nested Lua call/return contract failure.
- Root cause: `op_ret_resume` block params named `pc/base/top` collided with the opcode handler’s outer `pc/base/top` params, so Lalin resolved the forwarded values to the child opcode state instead of the return continuation values. This resumed the parent at the CALL instruction and errored with `ERR_CALL`.
- Updated return resume blocks to resume using `parent.pc/base/top`, with `parent.pc` set by `handle_return_mode`.
- Replaced temporary/debug `parent.pc = 99` in `handle_return_mode` with `parent.pc = target_pc`.
- Made normal/tailcall/pcall next-PC calculation explicit via `let next_pc`.

## Files Changed By Me

- `experiments/lua_interpreter_vm/src/op/call.lua`
  - Fixed all three return handlers’ `op_ret_resume` forwarding to avoid shadowed continuation values.

- `experiments/lua_interpreter_vm/src/regions_call.lua`
  - Persisted the computed return target PC into `parent.pc`.
  - Made `next_pc` explicit in normal/tailcall/pcall return cases.

## Tests Run

Passed:

```sh
luajit experiments/lua_interpreter_vm/tests/test_vm_smoke.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_e2e.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_opcode_semantics.lua
luajit experiments/lua_interpreter_vm/tests/test_parser_compile.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_validation_contract.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_call_frame_contract.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_error_contract.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_abi_contract.lua
```

Also passed:

```sh
git diff --check -- experiments/lua_interpreter_vm/src ... contract/test paths
```

## Failures / Blockers

- Initial failure observed:
  - `test_vm_call_frame_contract.lua`
  - returned `-214` (`ERR_CALL`)
  - fixed as described above.
- No remaining blockers in the VM contract test set I ran.

## Deviations From Edit Plan

- Did not implement actual native invocation, allocator bridge, full protected-call allocation, or complete coroutine resume semantics; existing fail-loud ABI stubs remain.
- Did not touch SponJIT despite unrelated dirty SponJIT files in the working tree.
- Used `parent.pc` as the stable handoff point in return resume blocks to avoid Lalin name-shadowing behavior in continuation block params.

## Scout Output — 2026-05-29 18:33:33

## Files Retrieved

1. `experiments/lua_interpreter_vm/VM_CONTRACT.md` (lines 1-86) - Post-contract architectural gate: Lua 5.5 semantics, SponJIT separate, validator/frame/native/error/yield/allocator invariants.
2. `experiments/lua_interpreter_vm/src/contract.lua` (lines 1-17) - Machine-readable ABI/contract gates; `sponjit_allowed = false`.
3. `experiments/lua_interpreter_vm/src/init.lua` (lines 1-32) - VM module loader; exports `contract`.
4. `experiments/lua_interpreter_vm/src/constants.lua` (lines 1-238) - Lua 5.5 tags/opcodes/resume/status/native ABI/frame/thread flags.
5. `experiments/lua_interpreter_vm/src/products.lua` (lines 1-111) - Current VM ABI structs: expanded `Frame`, `LuaThread`, `Allocator`, `NativeFunc`, `NativeCallResult`.
6. `experiments/lua_interpreter_vm/src/vm_loop.lua` (lines 1-171) - Main interpreter loop; post-contract frame-cache reload and error routing.
7. `experiments/lua_interpreter_vm/src/opcodes.lua` (lines 1-725) - Dispatch, inline hot opcodes, handler map, opcode metadata.
8. `experiments/lua_interpreter_vm/src/op/_init.lua` (lines 1-156) - Shared opcode continuation signatures; table metamethod scratch now uses `top`.
9. `experiments/lua_interpreter_vm/src/op/load.lua` (lines 1-174) - MOVE/LOAD*/upvalue load/store/EXTRAARG.
10. `experiments/lua_interpreter_vm/src/op/arithmetic.lua` (lines 1-473) - Arithmetic/bitwise/unary handlers; MOD/IDIV/POW and metamethod fallbacks still fail.
11. `experiments/lua_interpreter_vm/src/op/table.lua` (lines 1-261) - GET/SET table opcodes; `NEWTABLE`/`SETLIST` still OOM.
12. `experiments/lua_interpreter_vm/src/op/compare.lua` (lines 1-216) - EQ/LT/LE/immediate comparisons; metamethod compare calls still error.
13. `experiments/lua_interpreter_vm/src/op/call.lua` (lines 1-252) - CALL/TAILCALL/RETURN; explicit result-base return path fixed.
14. `experiments/lua_interpreter_vm/src/op/loop.lua` (lines 1-113) - Numeric loops partly implemented; generic for-call still runtime error.
15. `experiments/lua_interpreter_vm/src/op/closure.lua` (lines 1-52) - CLOSURE/VARARG/GETVARG stubs.
16. `experiments/lua_interpreter_vm/src/op/misc.lua` (lines 1-84) - LEN/CONCAT stubs; CLOSE/TBC/JMP/ERRNNIL.
17. `experiments/lua_interpreter_vm/src/regions_value.lua` (lines 1-264) - Value predicates/equality/compare/RK; mixed numeric and metamethod semantics incomplete.
18. `experiments/lua_interpreter_vm/src/regions_table.lua` (lines 1-226) - Raw table get/set and metamethod-aware shell; no resize/insert/new/next.
19. `experiments/lua_interpreter_vm/src/regions_metamethod.lua` (lines 1-151) - Metamethod lookup helpers; limited to tables and not fully wired.
20. `experiments/lua_interpreter_vm/src/regions_string.lua` (lines 1-56) - Hash implemented; intern/concat missing.
21. `experiments/lua_interpreter_vm/src/regions_upvalue.lua` (lines 1-60) - Close-upvalues implemented; creation/closure allocation missing.
22. `experiments/lua_interpreter_vm/src/regions_gc.lua` (lines 1-178) - Explicit allocator boundary and GC shell; allocation/propagate/sweep mostly no-op/OOM.
23. `experiments/lua_interpreter_vm/src/regions_error.lua` (lines 1-235) - `raise_code_error` added; protected frame allocation and real pcall/TBC close calls missing.
24. `experiments/lua_interpreter_vm/src/regions_coroutine.lua` (lines 1-73) - Explicit coroutine state distinctions; no real resume integration.
25. `experiments/lua_interpreter_vm/src/regions_stack.lua` (lines 1-135) - Frame push/result metadata and result adjustment; no stack growth/vararg reshaping.
26. `experiments/lua_interpreter_vm/src/regions_call.lua` (lines 1-368) - Central call/return/native ABI; native invocation and `__call` missing.
27. `experiments/lua_interpreter_vm/src/api.lua` (lines 1-174) - Sealed API functions; simple type/top/string/ABI/status work, table/call/pcall fail loudly.
28. `experiments/lua_interpreter_vm/src/regions_api.lua` (lines 1-43) - Basic API index decoding only.
29. `experiments/lua_interpreter_vm/src/validate.lua` (lines 1-207) - Strengthened bytecode validator; still partial.
30. `experiments/lua_interpreter_vm/src/parser_constants.lua` (lines 1-82) - Token/keyword/error constants for first compiler slice.
31. `experiments/lua_interpreter_vm/src/parser_products.lua` (lines 1-49) - Source compiler structs.
32. `experiments/lua_interpreter_vm/src/regions_lexer.lua` (lines 1-276) - Lexer supports a small token subset, more than parser uses.
33. `experiments/lua_interpreter_vm/src/regions_parser.lua` (lines 1-558) - Parser/compiler slice: locals, return, integer/bool/nil literals, simple arithmetic.
34. `experiments/lua_interpreter_vm/src/regions_codegen.lua` (lines 1-382) - Bytecode emission for limited compiler subset.
35. `experiments/lua_interpreter_vm/src/regions_compiler.lua` (lines 1-84) - Public compile entry into caller buffers.
36. `experiments/lua_interpreter_vm/tests/test_vm_smoke.lua` (lines 1-133) - Structural/module/bundle smoke; now 197 regions, 43 structs.
37. `experiments/lua_interpreter_vm/tests/test_vm_validation_contract.lua` (lines 1-118) - Validator malformed-bytecode contract tests.
38. `experiments/lua_interpreter_vm/tests/test_vm_call_frame_contract.lua` (lines 1-136) - Nested Lua call test for result-base and code/constants reload.
39. `experiments/lua_interpreter_vm/tests/test_vm_error_contract.lua` (lines 1-100) - Bad opcode error-state test.
40. `experiments/lua_interpreter_vm/tests/test_vm_abi_contract.lua` (lines 1-57) - ABI version API/contract tests.
41. `experiments/lua_interpreter_vm/tests/test_vm_e2e.lua` (lines 1-221) - Manual Proto executes LOADK+RETURN.
42. `experiments/lua_interpreter_vm/tests/test_vm_opcode_semantics.lua` (lines 1-287) - Focused opcode semantic microtests.
43. `experiments/lua_interpreter_vm/tests/test_parser_compile.lua` (lines 1-250) - Source compiler + validator + VM tests for arithmetic subset.
44. `experiments/lua_interpreter_vm/README.md` (lines 1-132) - Confirms VM and SpongeJIT are separate; current VM is experimental.
45. `experiments/lua_interpreter_vm/spongejit/puc/README.md` (lines 1-11) - Confirms no maintained executable PUC/SponJIT integration.
46. `experiments/lua_interpreter_vm/tools/jit_harness/README.md` (lines 1-319) - JIT harness still offline/mock in places; compiler coverage note.
47. `experiments/lua_interpreter_vm/tools/jit_harness/compile.lua` (lines 1-336) - Harness uses current source compiler when available, fallback token compiler otherwise.

## Key Code

### Contract gate exists and keeps SponJIT separate

```lua
-- src/contract.lua
return {
    vm_abi_version = 1,
    native_abi_version = 1,
    validator_contract_version = 1,
    sponjit_allowed = false,
    required_gates = {
        "bytecode_validator_complete",
        "frame_cache_reload_on_switch",
        "explicit_call_result_base",
        "unified_error_unwind",
        "explicit_native_abi",
        "explicit_allocator_boundary",
    },
}
```

### Post-contract ABI fields are present

```lua
-- products.lua
local NativeFunc = host.struct [[struct NativeFunc abi_version: u32; flags: u32; addr: ptr(u8); name: ptr(String) end]]
local NativeCallResult = host.struct [[struct NativeCallResult status: u8; nresults: i32; err: Value; continuation: ptr(u8) end]]

local Frame = host.struct [[struct Frame closure: Value; base: index; top: index; pc: index; wanted: i32; tailcalls: i32; resume_mode: u16; resume_a: u16; resume_b: u16; resume_c: u16; resume_pc: index; resume_base: index; resume_value: Value; result_base: index; call_top: index; yieldable: u8; flags: u8; reserved: u16 end]]

local LuaThread = host.struct [[struct LuaThread ... tbc_head: index; yieldable: i32; nonyieldable: i32; last_error_code: i32; flags: u32 end]]
```

### Frame-cache reload is implemented

```lua
-- vm_loop.lua
block cont_resume_parent(parent: ptr(Frame), pc: index, base: index, top: index,
                         code: ptr(Instr), constants: ptr(Value))
    let cl: ptr(LClosure) = as(ptr(LClosure), parent.closure.bits)
    let parent_code: ptr(Instr) = cl.proto.code
    let parent_constants: ptr(Value) = cl.proto.constants
    jump loop(frame = parent, pc = pc, base = base, top = top,
              code = parent_code, constants = parent_constants)
end
```

### Call result placement now uses explicit child metadata

```lua
-- regions_call.lua
let ret_result_base: index = frame.result_base
let ret_wanted: i32 = frame.wanted
let ret_resume_mode: u16 = frame.resume_mode
...
emit handle_return_mode(L, parent, first_result, nres,
                        ret_result_base, ret_wanted, ret_resume_mode,
                        ...)

-- handle_return_mode normal/tailcall
let next_pc: index = ret_resume_pc + 1
jump adjust_start(parent = parent, dst = ret_result_base,
                  first = first_result, nactual = nres,
                  wanted = ret_wanted, target_pc = next_pc,
                  is_pcall = as(u8, 0))
```

### Unified opcode error entry is present, but protected semantics are still shallow

```lua
-- regions_error.lua
region raise_code_error(L: ptr(LuaThread), code: i32;
                        caught: cont(frame: ptr(Frame)),
                        uncaught: cont(code: i32),
                        oom: cont())
...
    L.err_value = err
    L.last_error_code = code
    emit raise_error(L, err;
        caught = was_caught,
        uncaught = not_caught)
```

```lua
-- regions_error.lua
region enter_protected(...)
entry start()
    -- ProtectedFrame storage must be allocated by the VM allocator.
    jump oom()
end

region protected_call(...)
entry start()
    L.err_value = { tag = @{TAG_NIL}, aux = @{ERR_RUNTIME}, bits = 0 }
    L.last_error_code = @{ERR_RUNTIME}
    jump failure(err = L.err_value)
end
```

### Major runtime stubs remain

```lua
-- regions_gc.lua
region alloc_object(...)
entry start()
    ...
    -- Allocator extern bridge is not wired yet.
    jump oom()
end
```

```lua
-- regions_string.lua
region string_intern(...)
entry start()
    jump oom()
end

region string_concat_range(...)
entry start()
    jump error(code = @{ERR_RUNTIME})
end
```

```lua
-- regions_table.lua
region table_resize(...)
entry start()
    jump oom()
end

region table_next(...)
entry start()
    jump done()
end
```

```lua
-- regions_upvalue.lua
block make_new()
    jump oom()
end

region make_lclosure(...)
entry start()
    jump oom()
end
```

```lua
-- regions_call.lua
region call_native(...)
entry start()
    ...
    L.last_error_code = @{ERR_CALL}
    jump error(code = @{ERR_CALL})
end
```

### Opcode stubs / incomplete semantics

```lua
-- op/closure.lua
region op_closure(...); entry start()
    jump error(code = @{ERR_RUNTIME})
end

region op_vararg(...); entry start()
    jump error(code = @{ERR_RUNTIME})
end

region op_getvarg(...); entry start()
    jump error(code = @{ERR_RUNTIME})
end
```

```lua
-- op/table.lua
region op_newtable(...); entry start()
    jump oom()
end

region op_setlist(...); entry start()
    jump oom()
end
```

```lua
-- op/misc.lua
region op_len(...); entry start()
    jump error(code = @{ERR_RUNTIME})
end

region op_concat(...); entry start()
    jump error(code = @{ERR_RUNTIME})
end
```

```lua
-- op/arithmetic.lua
region op_mod(...);  jump error(code = @{ERR_ARITH})
region op_idiv(...); jump error(code = @{ERR_ARITH})
region op_pow(...);  jump error(code = @{ERR_ARITH})

region op_mmbin(...);  jump error(code = @{ERR_RUNTIME})
region op_mmbini(...); jump error(code = @{ERR_RUNTIME})
region op_mmbink(...); jump error(code = @{ERR_RUNTIME})
```

### Source compiler is very limited

```lua
-- regions_compiler.lua
builder.constants = { data = nil, len = 0, cap = 0 }
builder.children = { data = nil, len = 0, cap = 0 }
builder.locvars = { data = nil, len = 0, cap = 0 }
builder.upvals = { data = nil, len = 0, cap = 0 }
```

Current parser supports only:
- `return expr`
- `local name = expr`
- semicolons/comments
- integer, true/false/nil, local names
- `+ - * /` precedence

Tests confirm examples like:

```lua
run_case("return 1 + 2", { LOADI, LOADI, ADD, MMBIN, RETURN1 }, 3)
run_case("local x = 41 return x + 1", ..., 42)
```

## Relationships

- Runtime execution path:
  `vm_resume` → `vm_loop` → `dispatch_instruction` → opcode handler → runtime regions.
- Post-contract call path:
  `op_call` → `prepare_call` → `frame_push` → child frame → `return_from_lua` → `handle_return_mode` → parent resume with reloaded code/constants.
- Error path:
  opcode handler/dispatch error → `vm_loop.do_error` → `raise_code_error` → `raise_error` → protected frame if present, otherwise outer error.
- Object allocation dependency cluster:
  `alloc_object` is needed before `string_intern`, `table_resize`, `op_newtable`, `make_lclosure`, upvalue creation, protected frames, stack/frame growth, userdata/thread creation, real compiler constants/children, and GC ownership can be completed.
- Metamethod dependency cluster:
  table get/set can discover `__index`/`__newindex`, but real behavior depends on callable/table metamethod dispatch, native/Lua call completion, safe scratch areas, yield/error continuation, and recursive loop protection.
- Source compiler dependency:
  compiler cannot become a Lua 5.5 program entry point until runtime supports constants/strings/tables/functions/upvalues/control flow/calls/varargs and allocator-backed `Proto` construction.
- SponJIT relation:
  current VM contract says SponJIT is gated and separate. README and `spongejit/puc/README.md` confirm no maintained executable SponJIT/PUC integration should be used as VM completion.

## Observations

### Current verified post-contract state

Working tree under `experiments/lua_interpreter_vm` is clean.

Tests run and passed:

```sh
luajit experiments/lua_interpreter_vm/tests/test_vm_smoke.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_validation_contract.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_call_frame_contract.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_error_contract.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_abi_contract.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_e2e.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_opcode_semantics.lua
luajit experiments/lua_interpreter_vm/tests/test_parser_compile.lua
```

Smoke reports:
- 197 region fragments
- 43 struct definitions
- 85 opcode handlers
- dispatch/vm_resume bundle compiles
- `Frame` has 18 fields
- `LuaThread` has 22 fields
- `NativeCallResult` exists
- contract gates SponJIT.

Behavior currently proven:
- manual `LOADK; RETURN` returns `42.0`
- focused opcode tests pass 10/10
- nested Lua call returns into explicit result base and reloads parent constants/code
- bad opcode sets `L.last_error_code` and `L.err_value.aux`
- source compiler arithmetic/local subset works.

### Remaining completion work, by concrete target area

#### 1. VM-owned allocation and GC are the largest blocker

Still missing:
- allocator extern bridge
- object allocation for every GC object
- stack/frame growth
- string allocation/intern table allocation
- table allocation/resizing
- closure/upvalue allocation
- protected frame allocation
- userdata/thread allocation
- real mark/propagate/sweep
- gray lists and write barriers integrated into mutations
- weak tables/finalization/userdata GC behavior.

Current GC shell is explicit but not functional:
- `alloc_object` always OOM after boundary checks
- `gc_step` immediately done
- `propagate_gray` empty
- `sweep_step` done
- barriers exist but table/upvalue/closure writes do not consistently call them.

#### 2. Strings are not semantically complete

Implemented:
- simple `string_hash`
- string comparisons over already-built `String` objects.

Missing:
- `string_intern`
- canonical string identity across VM
- concat
- numeric-to-string conversion
- string constant creation from compiler
- TM name initialization likely depends on interned `__add`, `__index`, etc.

This matters because `value_raw_equal` compares strings by pointer identity.

#### 3. Tables are only preallocated raw containers

Implemented:
- array lookup for integer keys already in range
- hash lookup by linear scan over existing nodes
- raw set into existing array/hash slots
- shell for `__index`/`__newindex`.

Missing:
- `NEWTABLE`
- insertion/growth/resize
- `SETLIST`
- `next`
- numeric key canonicalization details
- nil/NaN key rules beyond nil rejection
- barriers/shape epoch updates
- weak tables
- table-valued `__index`/`__newindex` recursion and loop protection.

Current `table_set` treats ordinary insertion/growth as OOM unless `__newindex` exists.

#### 4. Closures/upvalues/varargs are mostly absent

Implemented:
- `GETUPVAL`, `SETUPVAL` assume existing closure/upvalue arrays
- `close_upvalues` closes already-created ordered open upvalues.

Missing:
- `CLOSURE`
- `make_lclosure`
- upvalue allocation/insertion
- open-upvalue list ordering enforcement
- nested function compilation
- `VARARG`, `GETVARG`
- real fixed-arg/vararg adjustment.

#### 5. Native calls/API are versioned but not executable

Implemented:
- `NativeFunc` carries ABI version
- `call_native` checks null/version and fails loudly
- ABI/status accessors.

Missing:
- actual native function ABI invocation
- native outcomes: OK/error/yield/OOM/stack-grow
- `lua_call_api`, `lua_pcall_api`
- standard library/native closures
- `__call` metamethod support.

`try_call_metamethod` always returns not callable.

#### 6. Error/protected/TBC/coroutine protocols are explicit but incomplete

Implemented:
- opcode errors flow through `raise_code_error`
- uncaught errors preserve `err_value`/`last_error_code`
- protected unwind has data structures.

Missing:
- protected frame allocation
- actual `pcall`/`xpcall`
- error object construction beyond nil-with-code
- error handlers
- TBC `__close` invocation
- yields through protected/metamethod/native/TBC paths
- real coroutine resume/re-entry.

`coroutine_resume` only distinguishes states and returns `yielded(0)` for yielded target; it does not resume `vm_loop`.

#### 7. Opcode semantic inventory is far from complete

Mostly/partly working:
- loads, moves, simple upvalue access
- simple arithmetic fast paths for int/int and num/num on ADD/SUB/MUL/DIV subset
- bitwise integer operations
- numeric/string compare subset
- CALL/RETURN for Lua closures in controlled cases
- numeric for loops for homogeneous int or float triples
- JMP/TEST/TESTSET.

Missing or incomplete:
- MOD/IDIV/POW and K variants
- mixed int/float arithmetic/coercions
- arithmetic/metamethod fallback (`MMBIN*`)
- comparison metamethod calls
- LEN/CONCAT
- NEWTABLE/SETLIST
- CLOSURE/VARARG/GETVARG
- generic for-call
- native calls
- `__call`
- table constructor behavior
- full tailcall semantics
- open-result calls/returns likely under-tested
- TBC close semantics.

#### 8. Numeric semantics remain cross-cutting risk

Current facts:
- `value_raw_equal` requires identical tags, so integer `1` and float `1.0` are unequal.
- arithmetic fast paths generally handle int+int or num+num, not mixed.
- table array lookup only accepts `TAG_INTEGER`.
- table hash compares tag+bits.

Lua-compatible numeric equality/key/cast semantics need to be decided and implemented across:
- equality
- comparison
- arithmetic
- table key lookup/insertion
- constants
- loops
- compiler output.

#### 9. Validator is stronger but not complete

Now validates:
- opcode range
- universal A bound
- some B/C register families
- LOADK/LOADKX/EXTRAARG
- arithmetic/MMBIN adjacency
- some jump/loop/call/return windows
- CLOSURE child bounds.

Remaining holes observed:
- upvalue bounds for `GETUPVAL`, `SETUPVAL`, `GETTABUP`, `SETTABUP`
- many opcode-specific B/C meanings not covered
- `EQK` appears to be validated using `c` in one grouped check, while handler uses `bx`
- `MMBINK`/K opcode encoding metadata and dispatch/handler conventions are inconsistent in places
- no validation of closure upvalue descriptors
- no full stack-effect/control-flow validation
- no validation of frame/proto object invariants beyond pointers/maxstack
- no malformed tests for many op families.

#### 10. Source compiler is a small arithmetic slice, not Lua 5.5

Lexer recognizes some extra tokens, but parser/compiler lacks:
- function definitions
- calls
- table constructors
- strings as constants
- floats
- assignments beyond `local x = expr`
- globals/environment/upvalues
- if/while/repeat/for/goto/labels
- boolean operators
- unary operators
- varargs
- multi-return
- nested protos/debug info
- constant table allocation
- standard library integration.

The JIT harness notes only a few AWFY files compile cleanly and has fallback token compilation; this is not VM semantics.

#### 11. Test/conformance gap

Current tests are useful but mostly:
- manually constructed FFI protos
- scratch/external memory, not VM allocator
- no real GC
- no real strings/interning
- no real table creation/growth
- no closures/upvalues created by VM
- no native calls
- no protected calls
- no coroutines
- no standard library
- no differential Lua 5.5 conformance suite
- limited malformed-bytecode tests
- limited nested call/open-result/tailcall coverage.

Completion needs conformance tests for actual Lua programs and bytecode-level edge cases, not only opcode microsemantics.

### Completion dependency shape

A concrete path to “complete VM” cannot treat opcodes independently. The dependencies are clustered:

1. **Allocator/GC/object creation** unlocks strings, tables, closures, protected frames, stack growth, compiler constants/protos.
2. **String interning + TM names** unlock string equality, table keys, metamethod lookup, compiler string constants.
3. **Tables** unlock globals/environments, metatables, standard library state, constructors, iteration.
4. **Closures/upvalues/calls** unlock functions, nested functions, `__call`, library functions, metamethod invocation.
5. **Unified error/protected/yield** unlocks pcall/xpcall, coroutines, yieldable metamethods/native calls, TBC.
6. **Compiler expansion + validator hardening** make source programs and future JIT consumption safe.
7. **Conformance suite** must pressure all above before SponJIT integration.
