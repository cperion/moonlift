# Complete Lalin-native Lua 5.5 VM runtime
New PLANSEARCH workflow for the remaining work after the VM contract milestone. Goal: one concrete definition of complete — the Lalin-native runtime can run Lua 5.5 programs with correct VM semantics through its own runtime, while SponJIT remains separate.
**Workflow ID**: wf-lua-vm-complete-runtime
**Started**: 2026-05-29 18:34:36
---

## Scout Output — 2026-05-29 18:39:09

## Files Retrieved

1. `experiments/lua_interpreter_vm/README.md` (lines 1-120) - Current status: VM in `src/` is separate from SpongeJIT; not production; tests listed.
2. `experiments/lua_interpreter_vm/VM_CONTRACT.md` (lines 1-86) - Prior contract gates: validator, frame cache reload, result base, error unwind, native ABI, allocator boundary.
3. `experiments/lua_interpreter_vm/src/constants.lua` (lines 1-238) - Lua 5.5 tags, opcodes 0-84, TM events, resume modes, statuses, ABI versions.
4. `experiments/lua_interpreter_vm/src/products.lua` (lines 1-111) - VM product tree: `Value`, `Proto`, `Frame`, `LuaThread`, `GlobalState`, allocator/native structs.
5. `experiments/lua_interpreter_vm/src/init.lua` (lines 1-32) - Module loader for all VM components.
6. `experiments/lua_interpreter_vm/src/contract.lua` (lines 1-17) - Machine-readable gate summary, `sponjit_allowed=false`.
7. `experiments/lua_interpreter_vm/src/vm_loop.lua` (lines 1-171) - `vm_resume`, `vm_loop`, dispatch loop, frame-cache reload on parent/child switch, native stub path.
8. `experiments/lua_interpreter_vm/src/opcodes.lua` (lines 1-725) - Instruction decoder, inline hot opcodes, handler switch, opcode metadata.
9. `experiments/lua_interpreter_vm/src/validate.lua` (lines 1-207) - Current bytecode validator.
10. `experiments/lua_interpreter_vm/src/regions_value.lua` (lines 1-264) - Value predicates, raw equality, numeric/string comparison, RK resolution.
11. `experiments/lua_interpreter_vm/src/regions_table.lua` (lines 1-226) - Raw table access, metamethod-aware get/set, `table_next`, resize stubs.
12. `experiments/lua_interpreter_vm/src/regions_call.lua` (lines 1-368) - Call dispatcher, native-call fail-loud path, return-mode machine.
13. `experiments/lua_interpreter_vm/src/regions_stack.lua` (lines 1-135) - Stack/frame push/check/result adjustment; stack growth and varargs incomplete.
14. `experiments/lua_interpreter_vm/src/regions_error.lua` (lines 1-235) - Error object/protected unwind/TBC scaffolding; protected call incomplete.
15. `experiments/lua_interpreter_vm/src/regions_gc.lua` (lines 1-178) - Allocator/GC protocol shell; no real allocation/propagation/sweep.
16. `experiments/lua_interpreter_vm/src/regions_string.lua` (lines 1-56) - Hash only; intern/concat missing.
17. `experiments/lua_interpreter_vm/src/regions_upvalue.lua` (lines 1-60) - Closing existing upvalues works; creation/closure allocation missing.
18. `experiments/lua_interpreter_vm/src/regions_metamethod.lua` (lines 1-151) - Metamethod lookup and binop/unop dispatch helpers.
19. `experiments/lua_interpreter_vm/src/regions_coroutine.lua` (lines 1-73) - Coroutine state distinctions/yieldability shell.
20. `experiments/lua_interpreter_vm/src/api.lua` (lines 1-174) - Sealed API funcs; simple stack/type/status work, table/call/pcall fail.
21. `experiments/lua_interpreter_vm/src/regions_api.lua` (lines 1-43) - API index decoding.
22. `experiments/lua_interpreter_vm/src/op/*.lua`:
    - `load.lua` (1-174) - Load/upvalue handlers.
    - `arithmetic.lua` (1-473) - Arithmetic fast paths plus many arithmetic/MMBIN stubs.
    - `table.lua` (1-261) - Table opcode handlers; `NEWTABLE`/`SETLIST` OOM.
    - `call.lua` (1-251) - CALL/TAILCALL/RETURN handlers.
    - `compare.lua` (1-216) - Compare/test handlers.
    - `loop.lua` (1-113) - Numeric for-loop; generic for call stub.
    - `closure.lua` (1-52) - Closure/vararg stubs.
    - `misc.lua` (1-84) - LEN/CONCAT stubs; CLOSE/TBC/JMP/ERRNNIL.
23. `experiments/lua_interpreter_vm/src/parser_constants.lua` (lines 1-82), `parser_products.lua` (1-49), `regions_lexer.lua` (1-276), `regions_parser.lua` (1-558), `regions_codegen.lua` (1-382), `regions_compiler.lua` (1-84) - First source→Proto compiler slice.
24. Tests read:
    - `tests/test_vm_smoke.lua` (1-133)
    - `tests/test_vm_e2e.lua` (1-221)
    - `tests/test_vm_opcode_semantics.lua` (1-287)
    - `tests/test_parser_compile.lua` (1-250)
    - `tests/test_vm_abi_contract.lua` (1-57)
    - `tests/test_vm_call_frame_contract.lua` (1-136)
    - `tests/test_vm_error_contract.lua` (1-100)
    - `tests/test_vm_validation_contract.lua` (1-118)
25. `.vendor/Lua/lopcodes.h` (lines 225-454) - PUC Lua 5.5 opcode reference and opcode notes.
26. SponJIT docs:
    - `SPONJIT_ARCHITECTURE.md` (1-80)
    - `SPONJIT_COPY_LINK_PATCH.md` (1-140)
    - `SPONJIT_RUNTIME_DESIGN.md` (1-120)
    - `spongejit/puc/README.md` (1-8)
    - `spongejit/src/fragment_ir.lua` (1-220)
    - `spongejit/src/worker_compile.lua` (1-101)
    - `spongejit/include/sponbank.h` (1-260)

## Key Code

### Current completion contract

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

### VM loop frame-cache reload is now present

```lua
-- src/vm_loop.lua
block cont_resume_parent(parent: ptr(Frame), pc: index, base: index, top: index,
                         code: ptr(Instr), constants: ptr(Value))
    let cl: ptr(LClosure) = as(ptr(LClosure), parent.closure.bits)
    let parent_code: ptr(Instr) = cl.proto.code
    let parent_constants: ptr(Value) = cl.proto.constants
    jump loop(frame = parent, pc = pc, base = base, top = top,
              code = parent_code, constants = parent_constants)
end
```

### Native ABI explicitly fails loud

```lua
-- src/regions_call.lua
region call_native(...; returned: cont(nres: i32), yielded: cont(nres: i32),
                   error: cont(code: i32), oom: cont())
entry start()
    if cl == nil then ... jump error(code = @{ERR_CALL}) end
    if cl.fn == nil then ... jump error(code = @{ERR_CALL}) end
    if cl.fn.abi_version ~= @{ABI_NATIVE_VERSION} then ... jump error(code = @{ERR_CALL}) end
    L.last_error_code = @{ERR_CALL}
    jump error(code = @{ERR_CALL})
end
```

### Object economy is mostly absent

```lua
-- src/regions_gc.lua
region alloc_object(G: ptr(GlobalState), size: index, tt: u8;
                    ok: cont(obj: ptr(GCHeader)),
                    step_required: cont(),
                    oom: cont())
...
    -- Allocator extern bridge is not wired yet.
    jump oom()
end
```

```lua
-- src/regions_string.lua
region string_intern(...; found: cont(s: ptr(String)), created: cont(s: ptr(String)), oom: cont())
entry start()
    jump oom()
end
```

```lua
-- src/op/table.lua
region op_newtable(...; next: cont(...), oom: cont())
entry start()
    jump oom()
end
```

### Major opcode stubs

```lua
-- src/op/closure.lua
op_closure  -> ERR_RUNTIME
op_vararg   -> ERR_RUNTIME
op_getvarg  -> ERR_RUNTIME
```

```lua
-- src/op/misc.lua
op_len    -> ERR_RUNTIME
op_concat -> ERR_RUNTIME
```

```lua
-- src/op/arithmetic.lua
op_mod/op_idiv/op_pow and K variants -> ERR_ARITH
op_mmbin/op_mmbini/op_mmbink -> ERR_RUNTIME
```

### Source compiler current slice

Current parser/compiler supports a small subset: comments, names, integer literals, booleans/nil, `local x = expr`, `return expr`, `+ - * /`, semicolons.

Example verified by tests:

```lua
run_case("return 2 + 3 * 4",
  { LOADI, LOADI, LOADI, MUL, MMBIN, ADD, MMBIN, RETURN1 },
  14)
```

## Relationships

- Runtime flow:
  `vm_resume` → `vm_loop` → `dispatch_instruction` → inline opcode body or `op_handlers.*` → subsystem regions.
- Call flow:
  `op_call` → `prepare_call` → Lua frame push or native entry → `vm_loop.do_lua` / `call_native`.
- Return flow:
  `op_return*` → optional `tbc_close_chain` → `return_from_lua` → `handle_return_mode` → parent resume/finish.
- Table flow:
  `op_get*`/`op_set*` → `table_get`/`table_set` → raw table access → metamethod lookup/call continuation.
- Error flow:
  Opcode errors in `vm_loop` call `raise_code_error`, which builds `err_value`, records `last_error_code`, and calls `raise_error`.
- SponJIT:
  Current docs and README repeatedly state it is separate. `src/` VM is not JIT-integrated. SpongeJIT is metadata/foundry/native-fragment ABI work, not the VM runtime.

## Observations

### What is already working

I ran these tests successfully:

- `test_vm_abi_contract.lua` — PASS
- `test_vm_call_frame_contract.lua` — PASS
- `test_vm_error_contract.lua` — PASS
- `test_vm_validation_contract.lua` — 11/11 PASS
- `test_vm_opcode_semantics.lua` — 10/10 PASS
- `test_parser_compile.lua` — arithmetic/local/return source compiler tests PASS
- `test_vm_e2e.lua` — scratch-built Proto `LOADK; RETURN` executes and returns `42`
- `test_vm_smoke.lua` — 197 region fragments, 43 structs, full VM bundle compiles
- `test_vm_components.lua` — 10/10 PASS
- `test_vm_integration.lua` — PASS

Verified behavior includes:
- Manual `Proto` execution.
- Basic load/return/arithmetic/test/jump/compare slice.
- Nested Lua call frame-cache/result-base contract.
- Error state preservation for bad opcode.
- Validator detects some malformed bytecode.

### Major remaining gaps for “complete Lua 5.5 programs”

1. **Allocator / heap / GC**
   - No real allocator bridge.
   - No string/table/closure/upvalue/protected-frame allocation.
   - GC mark helpers exist, but gray propagation/sweep are no-op.
   - Barriers exist but are not integrated broadly.

2. **Tables**
   - Can read/write existing array/hash slots.
   - Cannot create tables (`NEWTABLE` OOM).
   - Cannot grow/resize/insert missing keys.
   - `table_next` immediately finishes.
   - `SETLIST` OOM.
   - Numeric key canonicalization and NaN rejection need work.

3. **Strings**
   - Hash exists.
   - Interning missing.
   - Concat missing.
   - Number/string coercion missing.
   - Pointer-based string equality depends on real interning.

4. **Closures/upvalues/varargs**
   - `make_lclosure`, `find_upvalue` allocation, `op_closure` missing.
   - `op_vararg`, `op_getvarg`, `adjust_varargs` missing.
   - Closing assumes already-created sorted open-upvalue list.

5. **Metamethods**
   - Lookup helpers exist.
   - Arithmetic fallback opcodes `MMBIN*` error.
   - `LEN`, `CONCAT`, comparison metamethod calls error.
   - `__index`/`__newindex` table-vs-function behavior incomplete.
   - `__call` path stubbed (`try_call_metamethod` → `not_callable`).

6. **Calls/native/API**
   - Lua calls now have meaningful frame/result tests.
   - Native calls always error.
   - Public `lua_gettable_api`, `lua_settable_api`, `lua_call_api`, `lua_pcall_api` fail-loud.
   - Standard library/native function story absent.

7. **Protected calls/errors/TBC/coroutines**
   - `raise_code_error` now centralizes opcode error state.
   - `enter_protected` OOM.
   - `protected_call` immediate failure.
   - `__close` invocation fail-loud.
   - Coroutine resume/yield is only a shell; no full VM re-entry protocol.

8. **Opcode semantic coverage**
   - Missing/incomplete: `MOD`, `IDIV`, `POW`, K variants, `MMBIN*`, `NEWTABLE`, `LEN`, `CONCAT`, `TFORCALL`, `SETLIST`, `CLOSURE`, `VARARG`, `GETVARG`.
   - Current arithmetic is mostly int+int / num+num; mixed int/float semantics need verification.
   - PUC Lua 5.5 opcode notes show possible encoding/semantic mismatches to audit: `JMP sJ`, `FORLOOP Bx`, `FORPREP Bx`, `SELF` uses `K[C]:shortstring`, `NEWTABLE`/`SETLIST` use `EXTRAARG`.

9. **Validator**
   - Much stronger than old milestone: opcode range, A bounds, LOADK/LOADKX, MMBIN pairing, some B/C/register windows, jump/loop/call/return checks.
   - Still needs full Lua 5.5 trust-boundary coverage:
     - upvalue bounds,
     - all constant/RK operand bounds (`GETTABUP`, `SETTABUP`, `SETFIELD`, `SETI`, etc.),
     - `NEWTABLE`/`SETLIST` `EXTRAARG`,
     - test-op “next instruction is jump” invariant,
     - exact PUC Lua 5.5 instruction modes,
     - proto child/upvalue descriptor invariants.

10. **Source compiler**
    - Not a Lua compiler yet.
    - No functions, calls, tables, strings-as-constants, loops, if, assignments, labels/goto, nested protos, upvalues, varargs, debug info, full precedence, standard libraries.

### Dependency clusters

- **Object economy cluster**: allocator → GC roots/barriers → strings → tables → closures/upvalues → protected frames → userdata/thread creation.
- **Control cluster**: calls → metamethods → protected unwind → TBC → coroutine yield/resume → native ABI.
- **Bytecode/validator cluster**: opcode semantics, exact 5.5 instruction modes, validator trust boundary, compiler emission.
- **Conformance cluster**: Lua 5.5 oracle, source compiler coverage, bytecode fixtures, negative tests, standard library/API choices.
- **SponJIT cluster**: intentionally separate; should not consume scaffolding behavior. Current SpongeJIT native fragment ABI is draft/not wired into VM.

### Verification evidence still needed

- Lua 5.5 conformance corpus against `.vendor/Lua/lua` as semantic oracle.
- Allocator-backed tests, not scratch-only FFI memory.
- Table/string/closure/upvalue integration tests.
- Metamethod and yield-across-metamethod tests.
- Protected call + error object + TBC unwind tests.
- Coroutine resume/yield across Lua/native/metamethod/protected boundaries.
- Bytecode validator fuzz/malformed-proto tests.
- Native ABI tests for normal/error/yield/OOM/stack-growth outcomes.
- GC tests: roots, barriers, weak/finalization if supported, stress allocation.
- Source→Proto→validate→run tests for real Lua programs, not only arithmetic subset.

## Knowledge-builder Output — 2026-05-29 18:42:57

## What Matters Most for This Problem

- **Exact Lua 5.5 VM semantic compatibility**, not just “all opcodes have handlers.”
- **Bytecode format stability**: decoder, validator, compiler, and PUC Lua 5.5 opcode definitions must agree bit-for-bit.
- **Runtime object economy**: allocation, strings, tables, closures, upvalues, protected frames, threads, userdata, and GC are one coupled substrate.
- **Control re-entry correctness**: calls, metamethods, errors, protected calls, TBC, yields, and coroutines all share the same continuation/resume machinery.
- **Safety at the trust boundary**: handlers dereference raw pointers and assume validated operands; incomplete validation is a memory-safety issue, not only a semantic gap.
- **Compatibility boundaries**: Lalin-native runtime must not rely on SponJIT or PUC execution, but it still needs a precise oracle and a clear boundary for native libraries/API support.
- **Verification boundaries**: tests must stop proving only scaffolding contracts and start proving externally observable Lua behavior against Lua 5.5.

## Non-Obvious Observations

### 1. The current “contract-complete” VM is not on a smooth path to “Lua-complete”; it is a scaffold with many fail-loud semantic holes

The previous milestone intentionally established safety contracts: validator exists, frame-cache reload exists, native ABI fails loudly, allocator boundary exists, etc. That is valuable, but for this new definition of complete, those same fail-loud paths become blockers.

A valid Lua 5.5 program must not hit:

- allocator `oom()` for ordinary table/string/closure/protected-frame creation,
- native-call `ERR_CALL` for standard library functions,
- `ERR_RUNTIME` for closures, varargs, metamethod fallbacks, concat, len, generic for,
- `ERR_ARITH` for valid `%`, `//`, `^`,
- API hard failures for table access/call/pcall.

So completion is not “fill remaining stubs”; it is “remove every fail-loud path from valid-program semantics, while preserving fail-loud behavior for invalid/unsupported host boundaries.”

### 2. There is a deeper bytecode dialect risk: the VM currently treats Lua 5.5 as more uniform than PUC’s opcode format actually is

The dispatcher mostly decodes:

- `A = bits 7..14`
- `k = bit 15`
- `B = bits 16..23`
- `C = bits 24..31`
- `Bx/sBx = bits 15..31`

But PUC Lua 5.5 has multiple formats: `iABC`, `ivABC`, `iABx`, `iAsBx`, `iAx`, `isJ`.

This causes non-obvious semantic mismatches:

- `JMP` uses `sJ`, a 25-bit signed field, not 17-bit `sBx`.
- `FORLOOP`, `FORPREP`, `TFORLOOP` use `Bx`-style loop offsets, not the current signed handling.
- `NEWTABLE` and `SETLIST` use `ivABC` plus optional `EXTRAARG`.
- `EXTRAARG` is `Ax`, not a 17-bit `Bx`.
- Immediate arithmetic/comparison operands use signed `sB`/`sC`, not current raw `B/C` or full `sBx`.
- `TEST`/`TESTSET` use the `k` bit, but current handlers inspect `C`.
- `SELF` should use `K[C]:shortstring`; current `op_self` reads `R[C]`.
- `SETTABLE` appears operand-swapped relative to PUC: PUC is `R[A][R[B]] := RK(C)`, current code uses `R[B][R[C]] := R[A]`.

This is not just “some opcodes missing.” It means existing tests and compiler output may be validating a Lalin-local bytecode dialect rather than Lua 5.5 bytecode.

### 3. The validator is part of memory safety, not just correctness

Many handlers directly index raw arrays:

- `cl.upvals[b]`
- `cl.proto.constants[c]`
- `cl.proto.children[bx]`
- `L.stack[base + operand]`
- `p.code[pc + 1]`

The validator currently catches some malformed bytecode, but not the full trust boundary. Missing checks are dangerous because Lalin-native code has no Lua table bounds safety at runtime.

Examples of hidden safety dependencies:

- `GETUPVAL`/`SETUPVAL` need upvalue bounds.
- `GETTABUP`/`SETTABUP` need both upvalue and constant bounds.
- RK operands must validate register-or-constant based on `k`.
- `SELF` writes `A+1`, so `A+1 < maxstack` matters.
- `LOADNIL A B` writes through `A+B`.
- `NEWTABLE`, `SETLIST`, `LOADKX`, `EXTRAARG` need pair and reachability invariants.
- Test/comparison ops assume the skipped instruction is a jump.
- Pair-only opcodes like `MMBIN*` and `EXTRAARG` must not be jump targets.

For completion, the validator must become the canonical bytecode memory-safety boundary before arbitrary bytecode/source output can be trusted.

### 4. Strings are a foundational runtime primitive, not an isolated feature

String interning is currently missing, but many later semantics quietly depend on it:

- `Value` raw equality for strings is pointer equality.
- Metamethod names use `G.tmname[event]` interned strings.
- `GETFIELD`, `SELF`, `SETFIELD`, `GETTABUP`, `SETTABUP` expect shortstring constants.
- Table hashing/equality depends on stable string identity/hash.
- Error messages, debug names, source names, global names, and standard library keys are strings.
- `__close` lookup currently constructs a bogus key using `aux = TM_CLOSE` instead of the global metamethod-name string path.

Without interned strings and canonical metamethod-name setup, tables, metamethods, globals, error messages, and libraries cannot become correct independently.

### 5. Tables are not merely missing allocation; their equality/key invariants are incomplete

The current raw table operations can read/write pre-existing slots, but completion requires more than `NEWTABLE` and resize:

- Lua number key canonicalization matters: `t[1]` and `t[1.0]` must refer to the same key where appropriate.
- NaN keys must be rejected.
- `nil` keys must error.
- Deleted hash slots and reinsertions need defined behavior.
- `next` must preserve iteration semantics and detect invalid keys.
- `#t` depends on Lua’s table length/border rules.
- Weak tables depend on metatable `__mode` and GC.
- Array/hash split affects both semantics and performance, but even a slow table must preserve key identity rules.

Because current `table_raw_get` linearly scans all hash buckets, it may hide missing hash correctness in small tests. But once insertion/resizing exists, correctness depends on canonical keys and equality, not just storage.

### 6. Metamethods are a dynamic control-flow feature, not a lookup helper

The code has metamethod lookup helpers, but correct metamethod behavior requires VM re-entry with full continuation state.

Affected operations include:

- arithmetic fallback `MMBIN*`,
- `__index` / `__newindex`,
- `__call`,
- `__len`,
- `__concat`,
- `__eq`, `__lt`, `__le`,
- `__close`,
- standard-library-visible table behavior.

These are not local “call function and continue” sites. They interact with:

- frame cache reload,
- result placement,
- `pc` advancement,
- stack top preservation,
- yieldability,
- protected calls,
- native calls,
- error unwinding,
- TBC closing.

The existing `Resume.*` enum shows the VM already anticipates this. The hidden risk is that each metamethod opcode path must preserve the same resume invariants as normal calls; otherwise the VM will pass simple call tests but fail nested/yielding/erroring metamethod programs.

### 7. `top` discipline is a cross-instruction invariant and currently under-specified

Lua call semantics depend on `top` carrying dynamic result counts across instructions:

- `CALL B=0` consumes arguments up to `top`.
- `CALL C=0` sets `top` for a following open instruction.
- `RETURN B=0` returns up to `top`.
- `SETLIST B=0` uses `top`.
- `VARARG C=0` sets `top`.

The VM has both `L.top` and cached/frame `top`, but many handlers pass `top` through unchanged. Metamethod scratch space uses `scratch = top` without a visible stack-capacity invariant. Current tests mostly avoid open-call/top chains.

Completion needs a clear invariant for when `L.top`, `Frame.top`, and dispatch `top` are authoritative. Otherwise varargs, multiple returns, generic for, table constructors, and chained calls will be fragile.

### 8. Protected calls, TBC, and coroutines are one coupled control system

These are listed as separate gaps, but semantically they overlap:

- Errors unwind frames and must close TBC variables.
- `pcall`/`xpcall` catches after TBC processing.
- `__close` can invoke Lua/native code and interact with errors.
- Coroutines can yield across Lua calls and some metamethod/library boundaries.
- Native calls can return OK/error/yield/OOM/stack-grow.
- Protected frames require allocator-backed storage.

Current `raise_error` and `tbc_close_chain` are scaffolds. A VM can pass direct error tests yet still fail real Lua programs involving:

```lua
local x <close> = obj
return f()
```

or:

```lua
local ok, err = pcall(function() error("x") end)
```

or coroutine-yielding through library/metamethod boundaries.

### 9. Native ABI completion is required even if SponJIT remains separate

SponJIT being separate does not mean native functions are optional. Lua programs normally depend on host/native functions for:

- base library,
- `print`, `error`, `pcall`, `xpcall`,
- `next`, `pairs`, `ipairs`,
- `coroutine.*`,
- `table`, `string`, `math`, possibly `io/os/debug`,
- module loading if supported.

Current `call_native` always errors, and API table/call/pcall functions fail loud. That means the runtime cannot host a standard library yet.

The compatibility boundary must distinguish:

- “SponJIT native fragment ABI” — separate and not used by VM completion.
- “VM native function ABI” — necessary for libraries/API/host interop.
- “PUC Lua C API compatibility” — maybe not required fully, but must be explicitly bounded.

### 10. The source compiler can accidentally mask VM incompatibility

The current compiler supports only a small arithmetic/local/return slice. More importantly, it emits bytecode consumed by this VM. If the compiler and VM share the same wrong opcode dialect, source-to-run tests may pass while diverging from Lua 5.5.

Examples:

- current arithmetic test emits `ADD; MMBIN` pairs, matching VM expectations;
- if `JMP`, `TEST`, `SELF`, `SETTABLE`, immediate operands, or `EXTRAARG` are encoded incorrectly on both sides, source tests will not catch the mismatch;
- manually built Proto tests bypass binary chunk loading and allocator/GC invariants.

Completion verification needs an oracle boundary independent of the Lalin compiler’s current encoding assumptions.

### 11. Numeric semantics are a dense hidden-risk area

The current numeric fast paths are narrower than Lua’s semantics:

- raw equality treats integer and float as unequal if tags differ; Lua numeric equality requires cross integer/float equality when mathematically equal.
- mixed int/float arithmetic is mostly missing.
- `/` should produce floats even for integer inputs.
- `%`, `//`, and `^` are missing.
- immediate operands are likely signed incorrectly.
- float immediates in comparisons require the PUC `C` flag behavior.
- integer overflow/wrap behavior must match Lua’s integer model.
- shifts require exact handling for negative/large counts.
- NaN and `-0.0` affect equality, ordering, and table keys.

These details are easy to under-test because simple integer arithmetic already passes.

### 12. Closure/upvalue correctness depends on aliasing and lifetime, not just allocation

`close_upvalues` exists for already-created upvalues, but closure semantics need:

- child proto descriptors,
- open-upvalue lookup/reuse,
- stack-slot aliasing while open,
- closed value storage after close,
- sorted open-upvalue list invariant,
- barriers when closures/upvalues capture collectable values,
- interaction with TBC and returns,
- vararg hidden parameters.

This is a memory identity problem: two closures capturing the same local must observe the same upvalue object until it closes. That cannot be tested by merely checking `CLOSURE` creates a non-null object.

### 13. GC cannot remain a no-op once allocation becomes real

A leak-only allocator might run simple programs, but “correct Lua 5.5 programs” likely includes GC-observable behavior:

- weak tables via `__mode`,
- finalizers / `__gc` where applicable,
- string interning lifetime,
- userdata lifetime,
- table/closure/upvalue barriers,
- registry/mainthread/global roots,
- coroutine stacks as roots,
- protected frames and error objects as roots.

The existing product tree already includes weak/tmudata/gray fields, so the schema implies a Lua-like GC contract. If completion excludes some GC-observable features, that must be a declared compatibility boundary; otherwise GC is semantic, not just resource management.

### 14. Existing tests mostly prove internal contracts, not Lua conformance

The passing tests are valuable but limited:

- manual Proto execution,
- selected opcode smoke semantics,
- validator samples,
- call frame/result-base contracts,
- error state preservation,
- compiler arithmetic subset.

They do not yet prove:

- bytecode compatibility with PUC Lua 5.5,
- source-language coverage,
- allocator-created object lifetimes,
- table/string/closure integration,
- metamethod calls and yields,
- protected error semantics,
- coroutine resume/yield protocol,
- GC roots/barriers/finalization/weak behavior,
- standard library behavior.

So “all current tests pass” is not strong evidence of progress toward the new complete definition except that the scaffold compiles and some core invariants are preserved.

### 15. Completion requires freezing the Lua 5.5 compatibility target

Lua 5.5 appears to be taken from vendored PUC sources. Because Lua 5.5 is not a widely stable released target in the same sense as Lua 5.4, the exact vendored revision matters.

The VM’s constants say “Lua 5.5 aligned,” but alignment must include:

- opcode enum,
- bitfield formats,
- parser/codegen behavior,
- numeric semantics,
- library behavior,
- error messages where observable,
- binary chunk/proto schema if loading chunks is in scope.

Without freezing the oracle revision, “correct Lua 5.5” can drift underneath the implementation.

## Knowledge Gaps

- Whether “Lua 5.5 programs” means **source programs only**, **binary chunks**, or both.
- Whether full PUC standard libraries are in scope, and if not, which library/API subset defines compatibility.
- Whether GC-observable semantics such as weak tables, finalizers, and userdata `__gc` are required for completion.
- Whether the vendored `.vendor/Lua` revision is the fixed Lua 5.5 oracle.
- Whether binary chunk loading/dumping must match PUC, or whether Lalin Proto construction may be VM-private.
- Exact intended boundary between the VM native ABI and any Lua C API compatibility layer.

## Approach-proposer Output — 2026-05-29 23:20:46

### Approach A: Oracle-First Incremental Completion

- **Core idea**: Keep the current VM architecture, but drive completion by first making bytecode/source behavior match vendored PUC Lua 5.5 exactly, then closing runtime gaps dependency-by-dependency.
- **Key changes**:
  - Audit and fix opcode decoding in `src/opcodes.lua`, `src/constants.lua`, compiler emission, and validator against `.vendor/Lua/lopcodes.h`.
  - Expand `src/validate.lua` into the complete memory-safety boundary for binary chunks.
  - Implement allocator-backed strings, tables, closures, upvalues, varargs, protected frames, native calls, and GC inside the existing `regions_*` structure.
  - Extend source compiler only after bytecode semantics are fixed.
  - Add conformance harness comparing Lalin VM results against vendored Lua 5.5.
- **Tradeoff**: Optimizes for preserving current work and making steady measurable progress; sacrifices architectural cleanup and may accumulate complexity in existing regions.
- **Risk**: Existing bytecode dialect assumptions may be deeply embedded in tests, compiler, and handlers, making “incremental” correction more disruptive than expected.
- **Done means**:
  - Source programs and binary chunks from the vendored Lua 5.5 dialect validate and run.
  - Validator rejects malformed chunks before any unsafe dereference.
  - All valid Lua 5.5 opcodes, operand modes, `EXTRAARG`, jumps, calls, varargs, closures, and metamethod pairs are implemented.
  - Required standard-library subset, weak tables, finalizers, userdata `__gc`, and LuaJIT-style FFI work through the VM-native ABI.
  - Conformance suite passes against vendored PUC Lua for in-scope behavior.
- **Rough sketch**:
  - Freeze vendored `.vendor/Lua` revision as the oracle.
  - Fix opcode formats first: `iABC`, `ivABC`, `iABx`, `iAsBx`, `iAx`, `isJ`, signed immediates, `TEST`, `SELF`, `SETTABLE`, loop offsets.
  - Make validator complete before accepting arbitrary binary chunks.
  - Build object economy: allocator → GC roots/barriers → strings → tables → closures/upvalues → userdata/threads.
  - Fill semantic holes in opcode handlers, then grow compiler and libraries under oracle tests.

---

### Approach B: Runtime-Kernel First Rewrite

- **Core idea**: Treat the current VM as a scaffold and build a new completion-grade runtime kernel around heap objects, stack/top discipline, continuation re-entry, protected unwind, and coroutine semantics before filling opcode coverage.
- **Key changes**:
  - Introduce a centralized runtime kernel owning:
    - allocation/GC,
    - stack and `top` invariants,
    - call/result placement,
    - native ABI,
    - protected frames,
    - TBC unwind,
    - coroutine yield/resume,
    - metamethod re-entry.
  - Refactor `regions_call.lua`, `regions_error.lua`, `regions_coroutine.lua`, `regions_stack.lua`, and metamethod paths around one continuation protocol.
  - Rework opcode handlers to become thin clients of the runtime kernel.
  - Keep SponJIT separate; native functions and FFI use a VM-native ABI only.
- **Tradeoff**: Optimizes for semantic correctness in the hardest coupled areas; sacrifices short-term progress because many existing handlers must be adapted.
- **Risk**: The kernel may become too abstract or large before enough conformance tests exist to validate it.
- **Done means**:
  - Every dynamic control feature uses the same re-entry protocol: Lua calls, native calls, metamethods, protected calls, TBC, errors, yields, and coroutine resumes.
  - `L.top`, cached `top`, frame `top`, open-call results, varargs, `CALL C=0`, `RETURN B=0`, `SETLIST B=0`, and `VARARG C=0` have one documented invariant.
  - Heap allocation, GC, barriers, weak tables, finalizers, userdata `__gc`, string interning, table resizing, closures, and upvalues are runtime-kernel services.
  - Binary chunk validator is complete and guards all raw accesses.
  - Source compiler and bytecode loader target the same PUC-compatible instruction model.
- **Rough sketch**:
  - Specify the VM kernel invariants in a runtime contract document.
  - Implement allocator/GC/string/table/userdata/thread substrate first.
  - Replace ad-hoc call/metamethod/error/coroutine paths with one resume-mode state machine.
  - Port existing opcode handlers onto the kernel.
  - Add conformance tests for nested calls, yielding metamethods, `pcall`, `__close`, coroutine edges, weak/finalizer behavior, and FFI calls.

---

### Approach C: PUC-Derived Compatibility Port

- **Core idea**: Use the vendored Lua 5.5 implementation as the structural source of truth, deriving VM metadata, bytecode validation rules, compiler behavior, and library semantics from PUC wherever possible while still executing on the Lalin-native VM.
- **Key changes**:
  - Generate opcode tables, modes, operand validation metadata, and disassembler/validator facts from `.vendor/Lua` headers.
  - Align Lalin `Proto`, chunk loader, and compiler output with PUC’s bytecode/proto model.
  - Port or mirror PUC runtime algorithms for tables, strings, closures, upvalues, GC, weak tables, userdata/finalizers, and standard-library subset.
  - Build LuaJIT-style FFI as a VM-native library layered beside, not inside, SponJIT.
  - Use PUC Lua as test oracle only, never as runtime execution fallback.
- **Tradeoff**: Optimizes for compatibility and reducing interpretation drift; sacrifices Lalin-native design freedom and may produce code that feels less idiomatic to the current region architecture.
- **Risk**: Mechanical alignment with PUC C structures may conflict with existing `products.lua` layout and Lalin control-region style.
- **Done means**:
  - Opcode definitions, instruction modes, binary chunk parsing, validator checks, and compiler emission are traceably derived from the vendored Lua 5.5 source.
  - Lalin VM accepts PUC-compatible binary chunks and produces matching observable behavior.
  - Source compiler behavior matches the vendored parser/codegen for in-scope Lua 5.5.
  - Required libraries, weak tables, finalizers, userdata `__gc`, and LuaJIT-style FFI match the declared compatibility surface.
  - A conformance harness can explain mismatches in terms of either accepted compatibility exclusions or bugs.
- **Rough sketch**:
  - Add generated opcode/operand metadata from `.vendor/Lua/lopcodes.h`.
  - Rebuild `validate.lua` around generated instruction-mode facts.
  - Port chunk loading and proto invariants against the vendored binary format.
  - Mirror PUC algorithms for object layout-sensitive behavior: string interning, table keys, `next`, length, GC, weak tables, finalizers.
  - Expand compiler and libraries by comparing emitted bytecode and runtime behavior against vendored Lua.

---

### Comparison

- **Approach A** preserves the current VM and completes it through conformance-driven incremental work.
- **Approach B** prioritizes a correct runtime/control substrate before broad opcode and library completion.
- **Approach C** maximizes PUC Lua 5.5 compatibility by deriving metadata and behavior from the vendored oracle as much as possible.

## Critique Output — 2026-05-29 23:22:17

Scoring note: for **compatibility, cohesion, fit, verification, bytecode safety, source/binary coverage**, `5 = best`. For **coupling, migration cost, performance risk, risk**, `5 = highest/worst`.

## Approach A: Oracle-First Incremental Completion

| Dimension | Score | Rationale |
|---|---:|---|
| **Compatibility** | 4/5 | Strong oracle-first framing, but preserving the current VM may leave dialect assumptions embedded longer. |
| **Coupling** | 3/5 | Keeps existing `regions_*` structure; moderate risk of semantic fixes spreading across opcode/compiler/validator/runtime. |
| **Cohesion** | 3/5 | Existing subsystems remain recognizable, but object economy + control semantics may become patched across many regions. |
| **Migration cost** | 3/5 | Less disruptive than a rewrite, but opcode format correction may invalidate tests, compiler emission, and handlers. |
| **Lalin explicit-programming fit** | 4/5 | Fits fail-loud boundaries, explicit validator, explicit regions, and incremental conformance gates. |
| **Performance risk** | 3/5 | Incremental object/runtime work may become correct but not well-shaped; fewer rewrite risks than B/C. |
| **Verification strength** | 5/5 | Best explicit emphasis on oracle tests, validator completion, and measurable conformance progress. |
| **Bytecode safety** | 5/5 | Treats validator as the trust boundary before arbitrary chunks. |
| **Source/binary coverage** | 4/5 | Explicitly includes both, but source compiler is intentionally delayed and current dialect drift is a concern. |
| **Risk** | 3/5 | Manageable, but hidden coupling from the current bytecode dialect is the major unknown. |

**Verdict**: **Yes with caveats**
**Key concern**: The opcode/bytecode audit must happen before growing the compiler or libraries, otherwise source tests may reinforce a non-PUC dialect.

---

## Approach B: Runtime-Kernel First Rewrite

| Dimension | Score | Rationale |
|---|---:|---|
| **Compatibility** | 3/5 | Addresses the hardest runtime-control semantics, but PUC bytecode/source compatibility is not the primary driver. |
| **Coupling** | 4/5 | A centralized kernel risks binding allocator, GC, calls, errors, coroutines, metamethods, and native ABI too tightly. |
| **Cohesion** | 4/5 | If successful, the control substrate becomes conceptually coherent; if not, it becomes a god-kernel. |
| **Migration cost** | 5/5 | Deep refactor of call/error/coroutine/stack/metamethod paths and many opcode handlers. |
| **Lalin explicit-programming fit** | 3/5 | Explicit invariants fit Lalin well, but a large abstraction layer may become less grep-shaped and less region-local. |
| **Performance risk** | 4/5 | New generalized continuation/kernel machinery could introduce overhead or awkward control lowering. |
| **Verification strength** | 3/5 | Needs conformance tests early; otherwise the kernel can become internally elegant but externally wrong. |
| **Bytecode safety** | 4/5 | Includes complete validator in done criteria, but not as the central sequencing principle. |
| **Source/binary coverage** | 3/5 | Eventually covers both, but opcode/chunk/source compatibility are secondary to runtime refactor. |
| **Risk** | 5/5 | Highest unknowns: rewrite scope, abstraction risk, and delayed compatibility feedback. |

**Verdict**: **Significant concerns**
**Key concern**: Without PUC-oracle pressure from the start, the new kernel could solve the wrong abstraction problem while compatibility debt grows.

---

## Approach C: PUC-Derived Compatibility Port

| Dimension | Score | Rationale |
|---|---:|---|
| **Compatibility** | 5/5 | Best match for clarified scope: vendored latest Lua 5.5 is the semantic and bytecode oracle. |
| **Coupling** | 4/5 | Intentionally couples metadata and algorithms to PUC; good for compatibility, risky for Lalin-native independence. |
| **Cohesion** | 4/5 | Generated opcode facts, validator rules, chunk/proto invariants, and mirrored runtime algorithms give clear responsibilities. |
| **Migration cost** | 4/5 | Likely forces changes to `products.lua`, validator, compiler, chunk model, table/string/GC semantics, and tests. |
| **Lalin explicit-programming fit** | 3/5 | Generated facts and explicit validator fit well; mechanically mirroring PUC C algorithms may feel less idiomatic in regions. |
| **Performance risk** | 3/5 | PUC algorithms are proven, but layout/control mismatches with Lalin may create performance cliffs or awkward translations. |
| **Verification strength** | 5/5 | Strongest traceability from vendored headers/source to metadata, validator, compiler, and conformance harness. |
| **Bytecode safety** | 5/5 | Generated instruction-mode facts are the strongest foundation for complete validator coverage. |
| **Source/binary coverage** | 5/5 | Best aligned with source programs plus PUC-compatible binary chunks. |
| **Risk** | 4/5 | Main risk is structural conflict between PUC-derived behavior and existing Lalin product/region architecture. |

**Verdict**: **Strong yes, with architectural discipline**
**Key concern**: Keep PUC derivation as semantic/metadata authority without blindly importing C-shaped structure that fights Lalin’s explicit region model.

---

## Summary

- **Recommended**: **Approach C**. Under the clarified scope—source and binary chunks, vendored Lua 5.5 as oracle, PUC behavior compatibility, weak tables/finalizers/userdata `__gc`, subset stdlib, LuaJIT-style FFI—compatibility and bytecode safety dominate. C best addresses dialect drift and gives the strongest validator/compiler/runtime traceability.

- **Necessary hybridization**: Use **C as the primary architecture**, but preserve **A’s incremental oracle-first delivery discipline** and require **B’s explicit top/call/error/coroutine/metamethod invariants** as acceptance criteria. That is not a separate direction so much as a constraint on making C survivable in this codebase.

- **Dark horse**: **Approach A**. It has the best migration profile and verification sequencing. If the current architecture proves more compatible than feared after the opcode audit, A could deliver faster.

- **Avoid**: **Approach B as the primary path**. Its runtime-control insight is valuable, but a kernel-first rewrite is too risky before bytecode/source compatibility is nailed down.

## Approach-proposer Output — 2026-05-29 23:26:47

### Approach A: Contract-Ladder Region Completion
- **Core idea**: Preserve the existing Lalin-native region architecture and finish Lua 5.5 by adding explicit completion gates, each oracle-checked against vendored `.vendor/Lua`.
- **Key changes**:
  - Extend `experiments/lua_interpreter_vm/src/contract.lua` with runtime-completion gates.
  - Fix opcode decoding/metadata in `src/constants.lua`, `src/opcodes.lua`, `src/validate.lua` using vendored Lua 5.5 as bytecode oracle.
  - Complete existing `regions_*` modules in place: allocator/GC, strings, tables, closures/upvalues, varargs, metamethods, protected calls, coroutines, native ABI.
  - Grow `regions_compiler.lua` only after bytecode compatibility is fixed.
  - Add oracle conformance tests for source and binary chunks.
- **Tradeoff**: Optimizes for preserving current work and Lalin’s explicit contracts; sacrifices some architectural cleanup because fixes remain spread across existing regions.
- **Risk**: Existing tests/compiler/handlers may encode a Lalin-local bytecode dialect, so compatibility fixes may be more invasive than expected.
- **Done criteria**:
  - Source programs and binary chunks for the vendored Lua 5.5 dialect validate and execute.
  - Validator is the complete unsafe-bytecode boundary.
  - Valid Lua programs no longer hit fail-loud stubs for allocator, tables, strings, closures, varargs, metamethods, protected calls, coroutines, or required stdlib/FFI paths.
  - Weak tables, finalizers, userdata `__gc`, and LuaJIT-style FFI work through VM-native mechanisms.
  - SponJIT remains unused.
- **Rough sketch**:
  - Freeze vendored Lua 5.5 revision as semantic/bytecode oracle.
  - Correct instruction formats: `iABC`, `ivABC`, `iABx`, `iAsBx`, `iAx`, `isJ`, signed immediates, `EXTRAARG`, loops, `SELF`, `TEST`, `SETTABLE`.
  - Make `validate.lua` complete before accepting arbitrary chunks.
  - Implement object economy in dependency order: allocator → GC roots/barriers → strings → tables → closures/upvalues → userdata/threads.
  - Complete control semantics: calls → metamethods → protected unwind/TBC → coroutine yield/resume → native stdlib/FFI.

---

### Approach B: Explicit Runtime Protocol Spine
- **Core idea**: Keep Lalin-native regions, but introduce a small set of explicit runtime protocols for heap, stack/top, call/re-entry, error/unwind, and coroutine state, then make opcode handlers clients of those protocols.
- **Key changes**:
  - Add documented protocol contracts for:
    - heap allocation/GC/barriers,
    - stack and `top` authority,
    - call/result placement,
    - metamethod re-entry,
    - protected error unwind,
    - TBC closing,
    - coroutine yield/resume,
    - native ABI outcomes.
  - Refactor `regions_stack.lua`, `regions_call.lua`, `regions_error.lua`, `regions_coroutine.lua`, `regions_metamethod.lua` around those protocols.
  - Keep opcode handlers in `src/op/*.lua`, but reduce ad-hoc continuation logic inside them.
  - Use vendored Lua only for semantic expectations and bytecode facts, not runtime structure.
- **Tradeoff**: Optimizes for correctness in the hardest coupled VM semantics; sacrifices short-term delivery because existing paths need protocol migration.
- **Risk**: The protocol spine could become too broad if not kept explicit and grep-shaped.
- **Done criteria**:
  - One documented invariant governs `L.top`, frame top, cached dispatch `top`, open calls, varargs, `CALL C=0`, `RETURN B=0`, `SETLIST B=0`, and `VARARG C=0`.
  - Lua calls, native calls, metamethod calls, protected calls, errors, TBC, yields, and coroutine resumes use one re-entry discipline.
  - Heap services cover strings, tables, closures, upvalues, userdata, weak tables, finalizers, and GC barriers.
  - Bytecode/source behavior matches vendored Lua 5.5 for in-scope semantics.
  - Full C API compatibility is not required; VM-native stdlib/FFI boundary is complete enough for the declared subset.
- **Rough sketch**:
  - Write a VM runtime protocol document alongside `VM_CONTRACT.md`.
  - Define continuation/result modes centrally and map all call-like operations onto them.
  - Implement allocator/GC/string/table services as explicit regions with barrier responsibilities.
  - Port existing op handlers onto the protocols one family at a time.
  - Add oracle tests specifically for nested/yielding metamethods, `pcall`, `__close`, coroutine edges, weak/finalizer behavior, and FFI calls.

---

### Approach C: Vertical Semantic Slices
- **Core idea**: Complete the VM by delivering full Lua-visible feature slices end-to-end, each spanning bytecode validation, runtime objects, opcodes, compiler emission, stdlib hooks, and oracle tests.
- **Key changes**:
  - Organize work into feature slices rather than subsystem rewrites:
    - bytecode/chunk safety slice,
    - strings/globals slice,
    - tables/metatables slice,
    - functions/closures/upvalues/varargs slice,
    - numeric/operator slice,
    - errors/protected/TBC slice,
    - coroutines slice,
    - stdlib/userdata/FFI slice,
    - GC-observable semantics slice.
  - For each slice, update `validate.lua`, relevant `regions_*`, `src/op/*.lua`, compiler, and tests together.
  - Keep all implementation Lalin-native and region-shaped.
  - Use vendored Lua as oracle for expected bytecode and observable behavior.
- **Tradeoff**: Optimizes for externally visible progress and avoids building unused infrastructure; sacrifices some global uniformity because cross-cutting invariants must be maintained slice-by-slice.
- **Risk**: Shared concerns like GC barriers, `top` discipline, and validator completeness can be under-designed if slices are too narrow.
- **Done criteria**:
  - Every declared slice has source tests, binary chunk tests, malformed validator tests, and oracle comparison tests.
  - No slice relies on PUC implementation architecture or SponJIT.
  - Required stdlib subset, weak tables, finalizers, userdata `__gc`, and LuaJIT-style FFI are covered by end-to-end programs.
  - Binary chunk validator rejects unsafe/malformed chunks before execution.
  - Remaining unsupported surfaces, such as full C API compatibility, are explicit non-completion items.
- **Rough sketch**:
  - Start with bytecode/chunk safety so all later slices target the correct dialect.
  - Add a conformance harness that can run the same source/chunk against vendored Lua and Lalin VM.
  - Implement slices in dependency order, but require each to be usable from real Lua programs before moving on.
  - Maintain per-slice contracts in `contract.lua` or companion metadata.
  - Finish with stress suites: GC, weak/finalizers, coroutine/protected-call interactions, and FFI/library integration.
