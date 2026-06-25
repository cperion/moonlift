# Finish Lalin-native Lua VM
Complete experiments/lua_interpreter_vm into a final-form idiomatic Lalin-native Lua 5.5 VM, grounded in explicit_programming.md, keeping SponJIT separate and PUC Lua as oracle only.
**Workflow ID**: wf-lua-vm-finish-final
**Started**: 2026-05-30 09:51:58
---

## Scout Output — 2026-05-30 09:58:38

## Files Retrieved

1. `explicit_programming.md` (lines 1-220, 220-900, 900-1540, 1540-2040, 2420-2840, 3260-3709) — Governing philosophy: dual data/control tree, no implicit state, regions/continuations, emit composition, Lua metaprogramming, anti-patterns.
2. `experiments/lua_interpreter_vm/README.md` (lines 1-132) — Status map: interpreter VM is separate from SpongeJIT; test commands; non-goals.
3. `experiments/lua_interpreter_vm/VM_CONTRACT.md` (lines 1-86) — ABI/semantic gate: Lua 5.5 target, PUC oracle-only, SponJIT disabled until gates pass.
4. `experiments/lua_interpreter_vm/src/constants.lua` (lines 1-278) — Tags, opcodes 0–84, metamethod IDs, resume states, status/errors, GC/table/userdata/finalizer constants.
5. `experiments/lua_interpreter_vm/src/products.lua` (lines 1-131) — Runtime data products: `Value`, `Proto`, `Frame`, `LuaThread`, tables, closures, userdata, allocator, native/protected/coroutine/finalizer state.
6. `experiments/lua_interpreter_vm/src/bytecode.lua` (lines 1-105) — Central Lua 5.5 instruction bit-layout facts and Lua-side encoders/decoders.
7. `experiments/lua_interpreter_vm/src/init.lua` (lines 1-39) — Module graph loader.
8. `experiments/lua_interpreter_vm/src/contract.lua` (lines 1-17) — Machine-readable SponJIT gate.
9. `experiments/lua_interpreter_vm/src/opcodes.lua` (lines 1-723) — Dispatch generator, inline opcode arms, handler protocol adapters, opcode metadata.
10. `experiments/lua_interpreter_vm/src/op/_init.lua` (lines 1-162) and `src/op/protocols.lua` (lines 1-41) — Opcode handler boilerplate and continuation protocol strings.
11. `experiments/lua_interpreter_vm/src/op/*.lua`:
    - `load.lua` (1-174)
    - `arithmetic.lua` (1-473)
    - `table.lua` (1-320)
    - `call.lua` (1-277)
    - `compare.lua` (1-216)
    - `loop.lua` (1-113)
    - `misc.lua` (1-105)
    - `closure.lua` (1-52)
12. `experiments/lua_interpreter_vm/src/validate.lua` (lines 1-290) — Current bytecode trust boundary.
13. `experiments/lua_interpreter_vm/src/vm_loop.lua` (lines 1-173) — `vm_resume`, main interpreter loop, frame-cache reload on parent resume.
14. Runtime regions:
    - `regions_value.lua` (1-264)
    - `regions_stack.lua` (1-151)
    - `regions_call.lua` (1-284)
    - `regions_resume.lua` (1-214)
    - `regions_table.lua` (1-482)
    - `regions_string.lua` (1-161)
    - `regions_metamethod.lua` (1-155)
    - `regions_upvalue.lua` (1-60)
    - `regions_gc.lua` (1-159)
    - `regions_gc_protocol.lua` (1-46)
    - `regions_error.lua` (1-235)
    - `regions_coroutine.lua` (1-78)
    - `regions_allocator.lua` (1-192)
    - `regions_native.lua` (1-83)
    - `regions_chunk.lua` (1-33)
    - `regions_api.lua` (1-43)
    - `api.lua` (1-174)
15. Source/chunk path:
    - `parser_constants.lua` (1-82)
    - `parser_products.lua` (1-49)
    - `regions_lexer.lua` (1-276)
    - `regions_parser.lua` (1-558)
    - `regions_codegen.lua` (1-382)
    - `regions_compiler.lua` (1-84)
    - `compat.lua` (1-16)
16. Tests:
    - `test_vm_smoke.lua` (1-139)
    - `test_vm_opcode_semantics.lua` (1-295)
    - `test_vm_validation_contract.lua` (1-144)
    - `test_parser_compile.lua` (1-260)
    - plus run output for bytecode/product/resume/native/allocator/compat/table/string/call/error/e2e tests.
17. Vendored Lua oracle:
    - `.vendor/Lua/lua.h` (16-35) — reports Lua 5.5.0.
    - `.vendor/Lua/lopcodes.h` (1-120, 228-439) — instruction formats, opcode list, opcode notes.
    - `.vendor/Lua/ltm.h` (15-49), `.vendor/Lua/ltm.c` (35-110) — metamethod enum/name order.
    - `.vendor/Lua/lvm.c` (123-193, 585-765) — numeric conversion/equality/concat/len facts.
    - `.vendor/Lua/lobject.h` (430-560) — userdata/lightuserdata facts.
    - `.vendor/Lua/lstate.h` (260-430) — thread/global state, GC lists.
    - `.vendor/Lua/lgc.c` (216-256, 592-692, 968-1108, 1544-1619) — weak/finalizer/atomic GC facts.
18. SponJIT docs:
    - `SPONJIT_ARCHITECTURE.md` (1-90)
    - `SPONJIT_RUNTIME_DESIGN.md` (1-140)
    - `SPONJIT_FOUNDRY_SSA.md` (1-80)
    - `SPONJIT_COPY_LINK_PATCH.md` (1-120)
    - `spongejit/puc/README.md` (1-8)
19. `lua/lalin/back_command_binary.lua` diff around body encoder — current uncommitted backend fix for indirect-call signature IDs.

## Key Code

### Explicit-programming constraints

```md
Explicit programming makes every behaviorally-meaningful distinction
visible in the source as a typed value, a named exit, or a declared
protocol.
```

```md
The output of explicit-programming design is the dual tree: a data
type forest and a control type forest...
Every distinction that matters appears as structure in one of the two trees.
```

```md
The control half ... outcomes are continuations, payloads are
minimal-sufficient, no fallthrough, state machines are regions with
named blocks, compose with emit and seal with func, forward continuations directly.
```

### VM contract

`VM_CONTRACT.md`:

```md
- The VM targets Lua 5.5 semantics in Lalin-native data/control structures.
- PUC Lua is a semantic reference only. PUC layouts, `longjmp`,
  C-stack behavior, allocator conventions, and internal bytecode/runtime
  shapes MUST NOT be treated as implementation dependencies.
- SponJIT remains separate and MUST NOT optimize or depend on scaffolding behavior.
```

`src/contract.lua`:

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

### Runtime products

`src/products.lua` currently has explicit sidecar state for previously implicit VM control:

```lua
local ResumeState = host.struct [[struct ResumeState kind: u16; a: u16; b: u16; c: u16; pc: index; base: index; result_base: index; call_top: index; wanted: i32; value: Value; errfunc_slot: index end]]
local NativeCallContext = host.struct [[struct NativeCallContext func_slot: index; nargs: i32; wanted: i32; result_base: index; stack_top: index; yieldable: u8; reserved: u8; resume: ResumeState end]]
local ProtectedFrame = host.struct [[struct ProtectedFrame status: u8; flags: u8; saved_frame_count: index; frame_index: index; stack_top: index; handler_slot: index; errfunc_slot: index; resume: ResumeState; previous: ptr(ProtectedFrame) end]]
local CoroutineState = host.struct [[struct CoroutineState caller: ptr(LuaThread); nresults: i32; resume: ResumeState end]]
local FinalizerQueue = host.struct [[struct FinalizerQueue eligible: ptr(GCHeader); pending: ptr(GCHeader); running: ptr(GCHeader) end]]
local Frame = host.struct [[struct Frame closure: Value; base: index; top: index; pc: index; wanted: i32; tailcalls: i32; result_base: index; call_top: index; resume: ResumeState; yieldable: u8; flags: u8; reserved: u16 end]]
```

### Bytecode frontier

`src/bytecode.lua` centralizes Lua 5.5 fields:

```lua
bytecode.SIZE_OP = 7
bytecode.POS_A = 7
bytecode.POS_K = 15
bytecode.POS_B = 16
bytecode.POS_C = 24
bytecode.POS_VB = 16
bytecode.POS_VC = 22
bytecode.POS_BX = 15
bytecode.POS_AX = 7
bytecode.OFFSET_SBX = 65535
bytecode.OFFSET_SJ = 16777215
bytecode.OFFSET_SC = 127
```

`validate.lua` now enforces several key Lua 5.5 invariants: opcode range, `LOADKX/EXTRAARG`, `NEWTABLE/SETLIST` extraarg, MMBIN adjacency, compare/test followed by JMP, `sJ` jump bounds, `FORLOOP/FORPREP` Bx targets, and CALL/RETURN windows.

### VM loop frame-cache invariant

`src/vm_loop.lua` reloads parent frame prototype pointers on return:

```lalin
block cont_resume_parent(parent: ptr(Frame), pc: index, base: index, top: index,
                         code: ptr(Instr), constants: ptr(Value))
    let cl: ptr(LClosure) = as(ptr(LClosure), parent.closure.bits)
    let parent_code: ptr(Instr) = cl.proto.code
    let parent_constants: ptr(Value) = cl.proto.constants
    jump loop(frame = parent, pc = pc, base = base, top = top,
              code = parent_code, constants = parent_constants)
end
```

### Explicit native boundary

`src/regions_native.lua`:

```lalin
region decode_native_result(result: ptr(NativeCallResult);
                            returned: cont(nres: i32),
                            yielded: cont(nres: i32),
                            error: cont(err: Value),
                            oom: cont(),
                            stack_grow: cont(needed: index),
                            reenter_lua: cont(),
                            invalid: cont())
```

`src/vm_loop.lua` still gates successful native returns at the loop boundary:

```lalin
block native_ret(nres: i32)
    -- Actual native invocation is still gated...
    jump error(code = @{ERR_RUNTIME})
end
```

### Binary chunk frontier

`src/regions_chunk.lua` is currently an explicit rejection boundary:

```lalin
region load_lua55_binary_chunk(...;
                               ok: cont(proto: ptr(Proto)),
                               format_error: cont(err: CompileError),
                               semantic_error: cont(err: CompileError),
                               oom: cont())
entry start()
    let err: CompileError = { code = @{ERR_RUNTIME}, ... }
    jump format_error(err = err)
end
```

### Current backend/repo issue affecting VM work

`lua/lalin/back_command_binary.lua` has an uncommitted fix for indirect-call signatures:

```diff
-            w4(buf, 0) -- sig_id placeholder
+            if tag == T.CallIndirect then
+                local sid = b.sig_map and b.sig_map[id(cmd.sig)]
+                assert(sid ~= nil, "missing indirect call signature id: " .. tostring(id(cmd.sig)))
+                w4(buf, sid)
+            else
+                w4(buf, 0)
+            end
...
+        b.sig_map = sig_idx
```

This is relevant because allocator/native boundary code casts stored pointers to typed function pointers and uses indirect calls.

## Relationships

- `init.lua` loads all VM modules; tests import `experiments.lua_interpreter_vm.src.init`.
- `products.lua` defines the data tree; `constants.lua` defines integer discriminants for ABI/storage.
- `bytecode.lua` is shared by tests and should be the shared opcode encoding oracle; `opcodes.lua` and `validate.lua` currently duplicate some decode expressions inline while also importing it.
- `vm_loop.vm_resume` → `vm_loop.vm_loop` → `opcodes.dispatch_instruction`.
- `dispatch_instruction` either runs inline opcode arms or emits handler regions from `src/op/*.lua`.
- Opcode handlers call shared runtime regions:
  - table ops → `table_get`, `table_set`, `prepare_call` for metamethod setup;
  - call ops → `prepare_call`, `return_from_lua`;
  - return path → `regions_resume.resume_after_return`;
  - concat → `string_concat_range`;
  - close/TBC/error → `regions_error`;
  - validation is external trust boundary before dispatch.
- Native calls:
  - `prepare_call` sees `TAG_CCLOSURE` and emits `enter_native(cl, ctx)`.
  - `vm_loop.do_native` emits `call_native`.
  - `call_native` checks ABI version and emits `regions_native.invoke_native`.
  - `decode_native_result` has full routing, but `vm_loop.native_ret` still turns successful native returns into runtime error.
- Source path:
  - `compat.source_frontier` → `regions_compiler.compile_lua_source_into`.
  - compiler initializes `CompileUnit`/`FuncBuilder`, emits `compile_prepared_unit`.
  - lexer/parser/codegen support only a small source slice.
- Binary path:
  - `compat.binary_chunk_frontier` → `regions_chunk.load_lua55_binary_chunk`, which currently rejects explicitly.
- SponJIT:
  - separate `spongejit/` offline foundry: opcode/facts → semantic SSA → Stencil IR → native-fragment metadata.
  - `src/contract.lua` and README state interpreter is not JIT-integrated.
  - `spongejit/puc/README.md` says no maintained executable PUC integration exists.

## Observations

### Current working tree

`git status --short` shows many uncommitted VM changes plus new modules/tests:

- Modified VM files include `constants.lua`, `products.lua`, `opcodes.lua`, most `src/op/*.lua`, `regions_call.lua`, `regions_stack.lua`, `regions_table.lua`, `regions_string.lua`, `validate.lua`, `vm_loop.lua`, and tests.
- New VM files include:
  - `src/bytecode.lua`
  - `src/compat.lua`
  - `src/op/protocols.lua`
  - `src/regions_allocator.lua`
  - `src/regions_chunk.lua`
  - `src/regions_gc_protocol.lua`
  - `src/regions_native.lua`
  - `src/regions_resume.lua`
  - new contract tests for bytecode/product/resume/native/allocator/compat/string/table.
- `lua/lalin/back_command_binary.lua` is modified for indirect-call signature IDs.
- `.vendor/Lua` submodule status points at commit `a5522f06...`; `.vendor/Lua/lua.h` reports Lua 5.5.0.

### Test baseline observed

The following passed in the current working tree:

- `test_vm_bytecode_decoder_contract.lua` — 5/5
- `test_vm_product_refoundation.lua` — 14/14
- `test_vm_resume_protocol_contract.lua` — 21/21
- `test_vm_native_abi_contract.lua` — 8/8
- `test_vm_allocator_indirect_call.lua` — 1/1
- `test_vm_compat_frontier.lua` — 4/4
- `test_vm_table_protocols.lua` — 9/9
- `test_vm_string_protocols.lua` — 2/2
- `test_vm_validation_contract.lua` — 20/20
- `test_vm_call_frame_contract.lua`
- `test_vm_error_contract.lua`
- `test_vm_smoke.lua`
- `test_vm_opcode_semantics.lua` — 10/10
- `test_parser_compile.lua`
- `test_vm_components.lua` — 10/10
- `test_vm_integration.lua`
- `test_vm_e2e.lua` — executes `return 42`

### Implemented products/protocols

- Data products now explicitly name:
  - suspended return/metamethod/protected/coroutine/native state;
  - native call result routes;
  - weak/finalizer/userdata/table state;
  - allocator hook table;
  - sealed API structs.
- Control protocols now explicitly route:
  - bytecode validation `ok/invalid/oom`;
  - resume-state decoding;
  - native return/error/yield/oom/stack-grow/reenter/invalid;
  - table get/set raw hit/miss/metamethod/error;
  - string intern found/created/oom;
  - protected unwind caught/uncaught;
  - coroutine resume/yield distinctions.
- Opcode handler protocols are named in `op/protocols.lua`, but many are still assembled as Lua strings.

### Current major gaps

Facts visible in code:

- **Binary chunks**: no Lua 5.5 binary chunk reader yet; boundary rejects all chunks as `format_error`.
- **Source compatibility**: lexer/parser/compiler are a first slice only:
  - supports simple names, decimal integers, quoted string tokens, comments, `local`, `return`, `nil/true/false`, arithmetic precedence for `+ - * /`;
  - not full Lua 5.5 grammar, functions, closures, table constructors, loops, labels/goto, varargs, calls, full numerals/strings/escapes.
- **Closure/upvalues**:
  - `find_upvalue` scans but new allocation exits `oom`;
  - `make_lclosure` exits `oom`;
  - `OP_CLOSURE`, `OP_VARARG`, `OP_GETVARG` raise runtime error;
  - `OP_VARARGPREP` is a no-op.
- **Native calls**:
  - `decode_native_result` and `invoke_native` are present;
  - loop-level successful native return still becomes runtime error.
- **Protected calls/TBC/finalizers**:
  - `enter_protected` exits `oom`;
  - `protected_call` returns failure immediately;
  - `__close` lookup exists but calling `__close` raises runtime error.
- **GC**:
  - allocation boundary exists;
  - mark/barrier skeleton exists;
  - `gc_step`, `propagate_gray`, `sweep_step`, weak clearing, finalizer queue execution are skeletal.
- **Tables**:
  - raw get/set, new, resize, grow, next are partially implemented;
  - metamethod fallback invokes call setup for table get/set, but chain/loop semantics are not complete;
  - `table_resize` initializes fresh nodes and preserves array entries, but existing hash entries are not rehashed in that region.
- **Strings**:
  - hash/intern/concat for already-string operands exist;
  - number-to-string coercion is rejected;
  - concat non-string/metamethod path raises `ERR_CONCAT`.
- **Arithmetic/numeric semantics**:
  - add/sub/mul/div and some bit ops are implemented for narrow primitive cases;
  - `mod`, `idiv`, `pow` and K variants are fail-loud `ERR_ARITH`;
  - mixed integer/float equality is not oracle-complete: current `value_raw_equal` treats different tags as not equal, while PUC Lua 5.5 compares exact int/float equality.
- **Comparisons/metamethods**:
  - compare handlers have `call_mm` continuations but most metamethod paths raise `ERR_COMPARE`.
- **Length**:
  - `OP_LEN` raises runtime error.
- **Coroutines**:
  - state products/protocols exist, but full VM re-entry/resume/yield machinery is not implemented.
- **Allocator/GC interaction**:
  - `realloc_bytes` has `step_required`, but many callers map GC step-required to OOM.

### Oracle mismatch observed

Vendored Lua 5.5 metamethod order from `.vendor/Lua/ltm.h`:

```c
TM_INDEX, TM_NEWINDEX, TM_GC, TM_MODE, TM_LEN, TM_EQ,
TM_ADD, TM_SUB, TM_MUL, TM_MOD, TM_POW, TM_DIV, TM_IDIV,
TM_BAND, TM_BOR, TM_BXOR, TM_SHL, TM_SHR, TM_UNM, TM_BNOT,
TM_LT, TM_LE, TM_CONCAT, TM_CALL, TM_CLOSE, TM_N
```

Current `constants.lua` order:

```lua
INDEX=0, NEWINDEX=1, GC=2, MODE=3, EQ=4,
ADD=5, SUB=6, MUL=7, DIV=8, MOD=9, POW=10,
UNM=11, LEN=12, LT=13, ...
```

This is a first-order mismatch between VM `TM` constants and the Lua 5.5 oracle.

### SponJIT separation facts

- README: interpreter in `src/` is not wired to JIT.
- `contract.lua`: `sponjit_allowed = false`.
- SponJIT docs describe an offline bank/foundry path; runtime does not run SSA or compile.
- `spongejit/puc/README.md`: legacy PUC executable/materializer path removed; no maintained PUC executable integration.
- SponJIT docs include aspirational/native-fragment design; not current interpreter runtime.

### Backend issue

The uncommitted `back_command_binary.lua` change is materially relevant: current VM allocator/native paths use indirect function-pointer calls. The binary backend needed `CallIndirect` to write a per-call signature ID instead of zero. This affects finishing runtime allocation/native ABI tests and any Lalin-native VM code using indirect calls.

## Knowledge-builder Output — 2026-05-30 10:15:38

### What Matters Most for This Problem

- **Semantic exhaustiveness**: “complete Lua 5.5 VM” means every opcode, metamethod, numeric rule, control transfer, GC/finalizer path, and error/yield behavior must be explicit.
- **Explicit-programming fit**: no hidden fallthrough, implicit C-stack behavior, longjmp-like unwinds, side-channel state, or stringly protocols.
- **Oracle alignment without layout dependency**: PUC Lua can define behavior, opcode facts, metamethod order, and edge cases, but not storage layout or control mechanisms.
- **Control-state integrity**: calls, returns, metamethods, native calls, protected calls, coroutines, finalizers, and TBC all intersect through `ResumeState`, frames, stack ranges, and error/yield paths.
- **Trust-boundary stability**: validator, binary chunk loader, and source compiler must agree on bytecode invariants before external bytecode can be accepted.
- **SponJIT separation**: interpreter correctness cannot depend on quickening, inline caches, or future JIT scaffolding.

### Non-Obvious Observations

- The current VM has made important explicit-programming progress, but many stubs still collapse multiple Lua-visible outcomes into `ERR_RUNTIME`, `ERR_ARITH`, or `oom`. In this architecture, that is not merely incomplete behavior; it hides control distinctions that Lua semantics later needs to resume, protect, yield, or finalize correctly.

- The `TM` constant order mismatch is a deep ABI/semantic fault line, not a cosmetic enum issue. Metamethod IDs flow through source codegen, MMBIN operands, `GlobalState.tmname`, table metamethod lookup, TBC/`__close`, and binary chunk interpretation. A wrong order can make bytecode invoke the wrong metamethod while still looking structurally valid.

- Lua 5.5 paired opcode patterns create a tight validator/executor invariant. Arithmetic fast paths currently advance `pc + 2` to skip the following `MMBIN*`, while slow paths advance `pc + 1` to enter it. Therefore adjacency alone is insufficient: the paired `MMBIN*` must semantically correspond to the preceding arithmetic opcode and operands, or the VM can skip arbitrary instructions or call the wrong metamethod.

- Current arithmetic behavior has already-visible oracle mismatches beyond missing stubs. For example, `DIV` handles only float/float; int/int division should be primitive numeric behavior rather than falling into metamethod/error handling. Mixed integer/float arithmetic and equality are similar high-risk seams because the current tag-split fast paths often treat “different numeric tags” as non-equal or non-numeric.

- `value_raw_equal` and table key equality are not aligned. `value_raw_equal` is tag/bits-oriented, while `table_raw_set` compares `tag`, `aux`, and `bits`, but `table_raw_get` compares only `tag` and `bits`. Any meaningful use of `aux` in keys can produce false hits or misses. This matters because the VM’s `Value` type explicitly reserves `aux` as ABI storage, so equality rules cannot be accidental.

- Metamethod lookup is currently table-centered. `UserData` has an explicit metatable product, strings/numbers may need type metatable behavior, and Lua’s operators can consult metamethods for non-table values. The product tree does not yet fully expose all non-table metatable sources, so metamethod completion is also a data-model completeness problem.

- The frame-cache reload fix on parent resume addresses one concrete stale-proto hazard, but the invariant is broader: every control transfer that changes the active frame must refresh cached `code`, `constants`, `base`, `top`, and closure-derived state. Metamethod calls, native reentry, coroutine resume/yield, protected unwinds, and finalizer calls all carry the same risk.

- Native calls already have an explicit ABI result protocol, but successful native return is still gated at the VM loop. The hidden invariant is that native returns must converge semantically with Lua returns: result adjustment, `wanted`, `result_base`, `call_top`, resume state, yieldability, and protected-error behavior cannot drift between Lua and native callees.

- The error path currently tends to carry `code: i32`, while Lua errors semantically carry values. `NativeCallResult` has an error `Value`, `LuaThread.err_value` exists, and protected frames have handler slots, but many continuations discard the value payload. This will become a blocker for `pcall`, `xpcall`, metamethod errors, native errors, and finalizer errors.

- Protected calls are not just another call form. They require explicit unwind across frames, stack restoration, error object routing, handler invocation, and interaction with yield restrictions. Any region that locally jumps `error(code)` without preserving sufficient unwind state becomes incompatible with unified protected-call semantics.

- Coroutine/yield support is entangled with almost every “slow path.” Lua calls, native calls, metamethods, iterator calls, protected calls, and some library/native boundaries can all yield or reject yielding depending on context. The existing `yieldable`, `nonyieldable`, `CoroutineState`, and `ResumeState` fields indicate the right pressure, but many current protocols still treat yield as a narrow native-call outcome.

- GC and allocator behavior cannot stay collapsed into OOM. The allocator has a `step_required`-like distinction, while Lua GC can trigger weak-table processing, finalizer eligibility, finalizer calls, and barriers. Mapping GC-progress requirements to allocation failure loses observable behavior and violates the explicit distinction between memory failure and required collector work.

- Table resizing is semantically dangerous in its current partial form. The scout noted that array entries are preserved but hash entries are not rehashed. Because metatables are themselves tables, this can corrupt not only user data structures but metamethod lookup, `__index`, `__newindex`, `__close`, and weak/finalizer bookkeeping.

- `table_get`/`table_set` currently expose `loop_error`, but the observed paths do not fully realize chained `__index`/`__newindex` semantics or loop detection. Lua table access semantics require distinguishing raw miss, nil metamethod, table-valued metamethod chain, callable metamethod, type error, and loop; collapsing these will make table behavior non-oracular in subtle ways.

- Closure/upvalue support is an ordering pressure because it is not isolated to “function syntax.” Binary chunks, nested functions, captured locals, `OP_CLOSE`, TBC, returns, GC reachability, and coroutine stack suspension all depend on open/closed upvalue correctness. Current fail-loud allocation paths mean many otherwise-valid chunks cannot yet be represented.

- Binary chunk rejection is a clean explicit boundary, but accepting chunks will expand the trust boundary dramatically. The loader must translate external Lua 5.5 bytecode into Lalin-native `Proto`, `Value`, constants, upvalue descriptors, maxstack, and child proto graphs without importing PUC layout assumptions. Validator completeness becomes a prerequisite for safety, not just a test nicety.

- Source compiler tests can mask VM incompleteness. The current source slice emits only a small subset of bytecode and arithmetic patterns, so passing source/e2e tests does not imply interpreter completeness. Bytecode-level oracle tests are more revealing for VM semantics until the compiler is itself complete.

- The existing `InlineCache` and `QuickInstr` products are explicitly reserved. That creates a semantic boundary: interpreter correctness must not rely on quickening or cache state. Any cache/epoch field must remain observationally optional until the interpreter gates pass and SponJIT is allowed.

- Opcode handler protocols are named in `op/protocols.lua`, but still assembled as Lua strings. This is a tension with the explicit-programming goal: protocol names exist, but the control interface is not yet a first-class typed product. As opcode slow paths gain yield, reentry, protected error, and GC exits, stringly protocol drift becomes increasingly risky.

- `TFORCALL` currently shares the `MMBIN` continuation category in dispatch metadata. Generic-for iterator calls have distinct result and resume behavior from binary metamethod calls, so protocol reuse here is a semantic smell even if it compiles.

- The backend indirect-call signature fix is not peripheral. Allocator and native ABI paths use typed function-pointer calls; if the backend encodes indirect-call signatures incorrectly, VM-level allocator/native correctness can appear broken even when the VM regions are semantically sound.

### Knowledge Gaps

- Exact Lua 5.5 numeric conversion rules still need pinning down for mixed int/float arithmetic, division, modulo, floor division, bitwise conversion, shifts, NaN equality, and string-to-number coercion.
- Full Lua 5.5 binary chunk format obligations need mapping onto the Lalin-native `Proto`/`Value` products.
- Non-table metatable representation in the current VM product tree needs clarification before metamethod completion can be judged complete.

## Scout Output — 2026-05-30 10:39:15

## Files Retrieved

1. `experiments/lua_interpreter_vm/src/constants.lua` (1-278) — tags, opcodes, TM IDs, resume/status/native/error/GC/ABI constants.
2. `experiments/lua_interpreter_vm/src/products.lua` (1-131) — VM product/type forest.
3. `experiments/lua_interpreter_vm/src/init.lua` (1-39) — module loader/import graph.
4. `src/bytecode.lua` (1-105), `src/validate.lua` (1-290) — bytecode layout and Proto validator.
5. `src/vm_loop.lua` (1-173), `regions_resume.lua` (1-214), `regions_call.lua` (1-284), `regions_native.lua` (1-83), `regions_error.lua` (1-235), `regions_coroutine.lua` (1-78), `regions_stack.lua` (1-151), `regions_value.lua` (1-264).
6. `src/opcodes.lua` (1-723), `src/op_handlers.lua` (1-21), `src/op/*.lua` — dispatch and opcode handlers.
7. `regions_table.lua` (1-482), `regions_string.lua` (1-161), `regions_metamethod.lua` (1-155), `regions_upvalue.lua` (1-60), `regions_gc.lua` (1-159), `regions_gc_protocol.lua` (1-46), `regions_allocator.lua` (1-192), `regions_chunk.lua` (1-33).
8. Parser/compiler path: `parser_constants.lua` (1-82), `parser_products.lua` (1-49), `regions_lexer.lua` (1-276), `regions_parser.lua` (1-558), `regions_codegen.lua` (1-382), `regions_compiler.lua` (1-84), `compat.lua` (1-16).
9. Tests under `experiments/lua_interpreter_vm/tests/*.lua`, especially VM ABI/product/resume/native/allocator/compat/table/string/validation/opcode/call/error/parser/e2e tests.

Current working tree has many modified VM files and new files: `src/bytecode.lua`, `src/compat.lua`, `src/op/protocols.lua`, `regions_allocator.lua`, `regions_chunk.lua`, `regions_gc_protocol.lua`, `regions_native.lua`, `regions_resume.lua`, and several new tests are untracked.

---

## Key Code / Line Anchors

### Constants/products/init

#### `src/constants.lua`
- Imports: none.
- Tags: lines 5-17.
- Opcodes 0-84: lines 19-103.
  - Alias: `Op.SETI = 17`, `Op.SETTI = 17` lines 35-36.
- TM constants: lines 105-130.
  - Dangerous invariant: these IDs feed `regions_codegen.lua` MMBIN generation lines 186-201 and `regions_metamethod.lua` `G.tmname[event]` lookup lines 36-49.
- Resume discriminants: lines 132-157.
- Thread status: lines 159-165.
- Native result statuses: lines 167-175.
- Error codes: lines 177-195.
- Proto/frame/thread/table/finalizer/userdata/compat/GC/ABI constants: lines 197-263.
- Return/export table: lines 265-278.

Dangerous current invariant:
- `TM` order is storage/control ABI. Current order has `EQ=4`, `ADD=5`, `DIV=8`, `LEN=12`, `CLOSE=23`, no `BNOT`; all consumers assume this ordering is correct.

#### `src/products.lua`
- Imports: `lalin`, `lalin.host` lines 5-6.
- Core products:
  - `Value`: line 10.
  - `GCHeader`: line 13.
  - `Node`: line 16.
  - `String`: line 19.
  - `Table`: line 24.
  - `Instr`: line 27.
  - `Proto`: line 36.
  - `UpVal`, `LClosure`: lines 39-42.
  - `NativeFunc`, `NativeCallResult`, `CClosure`: lines 45-49.
  - `UserData`: line 53.
  - reserved `InlineCache`, `QuickInstr`: lines 56-59.
  - `Allocator`: line 68.
  - `ResumeState`: line 72.
  - `NativeCallContext`: line 76.
  - `ProtectedFrame`: line 79.
  - `CoroutineState`: line 82.
  - `FinalizerQueue`: line 85.
  - `Frame`: line 88.
  - `GlobalState`: line 94.
  - `LuaThread`: line 97.
- Export table: lines 102-131.

Dangerous invariants:
- Hard-coded product sizes in allocator/table/string must match these structs:
  - `regions_allocator.lua` lines 14-30.
  - `regions_table.lua` lines 11-13.
  - `regions_string.lua` line 10.
- `LuaThread`/`GlobalState` circular pointer dependency is explicitly noted lines 99-100.
- `Frame.resume` is the single persisted suspended-control state line 72/88.

#### `src/init.lua`
- Loader imports constants/contract/parser/product/bytecode/regions/opcodes/vm/compiler/compat lines 5-37.
- Return `vm`: line 39.
- Import ordering currently loads products before regions, `regions_call` after native/chunk, `vm_loop` after opcodes.

---

### Bytecode / validator

#### `src/bytecode.lua`
- Imports: none.
- Bit layout constants: lines 5-17.
- `bytecode.exprs(expr)`: lines 30-44. Used by `opcodes.lua` lines 27-35.
- `norm32`: lines 47-51.
- `decode_word`: lines 53-79.
- Encoders:
  - `encode_ABC`: lines 81-83.
  - `encode_ABx`: lines 85-87.
  - `encode_AsBx`: lines 89-91.
  - `encode_Ax`: lines 93-95.
  - `encode_sJ`: lines 97-99.
  - `encode_AvBCk`: lines 101-103.

Dangerous invariant:
- Validator duplicates decode expressions manually in `validate.lua` lines 41-52 rather than using `bytecode.exprs`.

#### `src/validate.lua`
- Imports: `lalin`, `lalin.host`, `constants`, `bytecode` lines 3-6.
- Builds `I` constants: lines 8-9.
- `validate_proto`: lines 15-288.
- Initial structural checks: lines 18-34.
- Decode fields per instruction: lines 41-52.
- Opcode/A-register bounds: lines 55-60.
- Pair-only opcode validation:
  - `EXTRAARG`: lines 63-78.
  - `MMBIN`: lines 79-83.
  - `MMBINI`: lines 84-88.
  - `MMBINK`: lines 89-93.
- Register bounds:
  - common B ops: lines 96-100.
  - B/C ops: lines 101-109.
- Constant/child bounds:
  - `LOADK`: lines 112-115.
  - `LOADKX + EXTRAARG`: lines 116-129.
  - `NEWTABLE` extraarg: lines 130-141.
  - `SETLIST` extraarg/window: lines 142-158.
  - K ops/constants: lines 160-164.
  - `CLOSURE` child: lines 165-169.
- Arithmetic adjacent fallback invariant:
  - reg ops → `MMBIN`: lines 172-180.
  - immediate ops → `MMBINI`: lines 182-190.
  - K ops → `MMBINK`: lines 192-200.
- Compare/test followed by `JMP`: lines 204-212.
- Jump/loop targets: lines 215-245.
- Loop register windows: lines 247-256.
- Call/return register windows: lines 260-280.
- Loop advance: line 283.

Dangerous invariants:
- Arithmetic fast paths skip `pc + 2`; validator only checks adjacency, not event/operand correspondence of paired `MMBIN*`.
- Validator imports `bytecode` but does not use it except import line 6.

---

### VM loop / resume / call / native / error / coroutine

#### `src/vm_loop.lua`
- Imports: `lalin`, `host`, `constants` lines 5-7; opcodes lines 11-12.
- `commit_vm_state`: lines 14-24.
- `vm_resume`: lines 27-68.
  - Empty frame runtime error: lines 41-42.
  - Sets status OK/DEAD/YIELDED/RUNTIME_ERROR/OOM: lines 44, 50, 54, 59, 64.
- `vm_loop`: lines 70-169.
  - Loads active frame/proto caches: lines 80-88.
  - Main dispatch emit: lines 92-102.
  - `cont_loop`, `cont_jump`: lines 104-113.
  - Parent resume reloads parent `code/constants`: lines 115-123.
  - Enter Lua child reloads child `code/constants`: lines 124-130.
  - Native call path: lines 131-139.
  - **Stub/error:** `native_ret` successful native return still jumps runtime error lines 135-139.
  - Error path emits `raise_code_error`: lines 149-154.
  - Caught error reloads frame caches: lines 155-158.

Dangerous invariant:
- Any active-frame switch must reload cached `code/constants`. This file does so for parent return lines 115-123, child enter lines 124-130, and caught error lines 155-158.

#### `src/regions_resume.lua`
- Imports: lines 3-5.
- `decode_resume_kind`: lines 13-59.
- `resume_after_return`: lines 80-189.
  - Normal/tailcall/pcall result adjustment: lines 99-119.
  - Metamethod resume writebacks:
    - gettable: lines 120-122.
    - settable: lines 123-124.
    - binop/unop: lines 125-130.
    - compare: lines 131-136.
    - concat/tfor/tbc: lines 137-139.
  - Unknown/default runtime error: lines 140-142.
  - Result adjustment blocks: lines 144-181.
  - `hm_oom` unused oom block: lines 184-186.
- `clear_resume`: lines 191-207.

Stubs/gaps:
- `resume_after_return` recognizes only kinds 0,1,2,4,5,6,7,9,10,11,12,14,16. Kinds for xpcall/native/finalizer/coroutine/etc. default to runtime error.

#### `src/regions_call.lua`
- Imports: constants plus `regions_resume`, `regions_native` lines 3-7.
- `prepare_call`: lines 25-103.
  - Dispatches only `TAG_LCLOSURE` and `TAG_CCLOSURE`: lines 38-43.
  - Lua closure stack check/frame push: lines 45-94.
  - Native call context construction: lines 61-73.
- **Stub:** `try_call_metamethod` always `not_callable`: lines 106-118.
- `call_native`: lines 121-187.
  - ABI checks: lines 127-137.
  - Emits `invoke_native`: lines 139-147.
  - Routes native error value to `last_error_code = err.aux`: lines 154-158.
  - Stack grow retry: lines 159-174.
- `return_from_lua`: lines 192-272.
  - Copies child `frame.resume` before pop: line 204.
  - Pops frame count: line 205.
  - Emits `resume_after_return`: lines 211-224.
  - All resume categories currently forward to `resume_parent`: lines 225-256.
- Aliases/export: lines 275-284.

Dangerous invariant:
- Native success is explicit in `call_native`, but `vm_loop.native_ret` still rejects it.
- `try_call_metamethod` means non-function `__call` is unreachable.

#### `src/regions_native.lua`
- Imports: lines 3-5.
- `invoke_native`: lines 12-45.
  - Validates pointers lines 20-24.
  - Casts `cl.fn.addr` to function pointer line 33.
  - Nonzero rc → invalid line 35.
  - Decodes result lines 36-44.
- `decode_native_result`: lines 49-80.
  - status 0 returned, 1 error, 2 yielded, 3 oom, 4 stack_grow, 5 reenter_lua, 6/default invalid.

Dangerous invariant:
- Requires backend indirect call signatures to be correct because line 33 casts and calls a typed function pointer.

#### `src/regions_error.lua`
- Imports: lines 3-5.
- `build_error_object`: lines 15-24. Builds nil-tag error with `aux = code`.
- `raise_code_error`: lines 27-55.
- `tbc_close_chain`: lines 64-106.
  - **Stub/error:** found `__close` jumps runtime error lines 93-96.
- `tbc_get_close`: lines 109-132.
  - Looks only at table metatable.
  - Constructs key `{ tag=TAG_STR, bits=0, aux=TM_CLOSE }` line 116, unlike `get_table_metamethod` which uses `G.tmname`.
- `raise_error`: lines 136-188.
- **Stub:** `enter_protected` always `oom`: lines 192-201.
- `leave_protected`: lines 205-211.
- **Stub:** `protected_call` always failure with runtime nil error: lines 215-225.

Dangerous invariants:
- Error objects are mostly code-in-`aux`, while native errors carry full `Value`.
- `tbc_get_close` keying differs from global `tmname` convention.

#### `src/regions_coroutine.lua`
- Imports: lines 3-5.
- `coroutine_resume`: lines 20-46.
  - Dead returns `dead`; OK errors; yielded returns `yielded(nres=0)`.
  - No vm_loop reentry.
- `coroutine_yield`: lines 53-72.
  - Rejects nil L and nonyieldable.
  - Stores `L.coroutine.nresults` and top frame resume.

Stub/gap:
- Resume does not actually transfer control into target thread; yield stores state only.

---

### Opcode dispatch and handlers

#### `src/opcodes.lua`
- Imports: `lalin`, constants, bytecode, op_handlers lines 6-9.
- `VALS`: lines 11-15.
- Bytecode decode expressions: lines 27-35.
- Args helpers: lines 36-55.
- `inline_arm`: lines 57-64.
- Continuation-set string names: lines 70-82.
- Emit templates: lines 86-148.
- `emit_arm`: lines 153-161.
- Inline hot opcodes:
  - MOVE: lines 165-177.
  - LOADK: lines 179-191.
  - ADD: lines 193-219.
  - LOADI: lines 221-228.
  - LOADF/LOADKX/LOADFALSE/LFALSESKIP/LOADTRUE/LOADNIL/ADDI/ADDK/SUB/MUL/DIV/UNM/NOT/JMP/EQ/LT/TEST: lines 230-500 approx.
- Non-inline handler mapping: lines 504-591.
  - `TFORCALL` uses `C_MMBIN`: line 585.
- `dispatch_instruction` region source: lines 596-658.
  - Default bad opcode: lines 622-623.
  - `cont_resume` warns `cur_code/cur_consts` may belong to child: lines 634-639.
- Metadata table: lines 667-717.
- Return: lines 720-723.

Dangerous invariants:
- Inline arithmetic fast paths skip paired fallback (`pc+2`), slow path advances to `MMBIN*` (`pc+1`).
- Handler continuation protocols are still assembled as strings/templates.
- `TFORCALL` mapped to `C_MMBIN` despite distinct iterator-call semantics.

#### `src/op/_init.lua`
- Imports: `lalin`, `host`, constants, protocols lines 3-6.
- `VALS`: lines 8-14.
- `R(src)`: lines 16-20.
- `H = protocols.handler_params()`: line 22.
- Shared protocol strings: lines 26-28, 140-146.
- Table get metamethod adapter: lines 29-85.
- Table set metamethod adapter: lines 87-139.
- Export: lines 149-162.

Dangerous invariant:
- Table metamethod adapters reserve scratch at `top` but rely on caller having stack capacity.

#### `src/op/protocols.lua`
- Continuation strings: lines 5-16.
- Protocol groups: lines 18-27.
- `signature(name)`: lines 28-35.
- `handler_params()`: lines 37-39.

#### `src/op/load.lua`
- Import: `_init` line 4.
- Handlers:
  - `op_move`: lines 8-22.
  - `op_loadi`: lines 24-34.
  - `op_loadf`: lines 36-46.
  - `op_loadk`: lines 48-63.
  - `op_loadkx`: lines 65-82.
  - booleans/nil: lines 84-134.
  - `op_getupval`: lines 137-146.
  - `op_setupval`: lines 148-158.
  - `op_extraarg`: lines 160-165.
- Dangerous invariant: upvalue handlers assume `cl.upvals[b]` nonnil.

#### `src/op/arithmetic.lua`
- Import: `_init` line 14.
- Primitive implemented:
  - add/sub/mul/div: lines 18-96.
  - bit ops/shifts: lines 123-194.
  - addi/shli/shri: lines 198-241.
  - addk/subk/mulk/divk: lines 244-317.
  - bandk/bork/bxork: lines 344-388.
  - unm/bnot/not: lines 392-435.
- **Stubs/error:**
  - `op_mod`: lines 99-104.
  - `op_idiv`: lines 107-112.
  - `op_pow`: lines 115-120.
  - `op_modk`: lines 320-325.
  - `op_powk`: lines 328-333.
  - `op_idivk`: lines 336-341.
  - `op_mmbin`: lines 438-444.
  - `op_mmbini`: lines 447-453.
  - `op_mmbink`: lines 456-462.
- Dangerous invariants:
  - Mixed int/float numeric operations usually fall to MMBIN/error.
  - `DIV` only fast-paths float/float.
  - Immediate ADDI in handler uses `c` not `sc` lines 202-208, while dispatch passes ARGS_ABC for ADDI line 525 and inline decodes `SC` semantics separately around lines 290-307.

#### `src/op/table.lua`
- Import: `_init` line 3.
- Get handlers:
  - `op_gettabup`: lines 7-30.
  - `op_gettable`: lines 32-53.
  - `op_geti`: lines 55-76.
  - `op_getfield`: lines 78-100.
- Set handlers:
  - `op_settabup`: lines 102-132.
  - `op_settable`: lines 134-155.
  - `op_setti`: lines 157-182.
  - `op_setfield`: lines 184-210.
- `op_newtable`: lines 212-238.
- `op_self`: lines 240-262.
- `op_setlist`: lines 264-312.
  - Non-table maps to oom line 273.
  - `set_error` maps to oom lines 305-306.

Dangerous invariants:
- Table op slow paths call adapters from `_init.lua`.
- `SETLIST` hides type/index errors as oom.

#### `src/op/compare.lua`
- Import: `_init` line 3.
- `op_eq`: lines 7-35.
- `op_lt`: lines 37-65.
- `op_le`: lines 67-95.
- `op_eqk`: lines 98-124.
- `_cmp_imm_handler`: lines 126-165.
- `op_eqi/lti/lei/gti/gei`: lines 167-171.
- `op_test`: lines 175-191.
- `op_testset`: lines 193-209.
- **Stubs/error:** all `do_mm` blocks raise `ERR_COMPARE` lines 24-25, 54-55, 84-85, 154-155.

#### `src/op/call.lua`
- Import: `_init` line 3.
- `op_call`: lines 7-80.
- `op_tailcall`: lines 82-135.
- `op_return`: lines 137-187.
- `op_return0`: lines 190-229.
- `op_return1`: lines 232-271.
- Dangerous invariant:
  - `op_ret_resume` ignores continuation params and uses `parent.pc/base/top` lines 171-172, 213-214, 256-257.
  - Yielded return maps to `finished` lines 177-178, 219-220, 262-263.

#### `src/op/loop.lua`
- Import: `_init` line 3.
- Numeric `op_forloop`: lines 7-46.
- Numeric `op_forprep`: lines 48-74.
- `op_tforprep`: lines 76-84.
- **Stub/error:** `op_tforcall`: lines 86-92.
- `op_tforloop`: lines 95-108.
- Dangerous invariant: numeric for only exact int/int/int or num/num/num.

#### `src/op/misc.lua`
- Import: `_init` line 3.
- **Stub/error:** `op_len` runtime error lines 7-13.
- `op_concat`: lines 16-43; metamethod path raises `ERR_CONCAT` lines 33-34.
- `op_close`: lines 46-63.
- `op_tbc`: lines 65-75.
- `op_jmp`: lines 77-85.
- `op_errnnil`: lines 87-99.

#### `src/op/closure.lua`
- Import: `_init` line 3.
- **Stubs/error:**
  - `op_closure`: lines 7-15.
  - `op_vararg`: lines 18-26.
  - `op_getvarg`: lines 29-37.
- `op_varargprep` no-op: lines 40-47.

---

### Table/string/metamethod/upvalue/GC/allocator/chunk

#### `src/regions_table.lua`
- Imports: lines 3-5.
- Hard-coded sizes: lines 11-13.
- `table_raw_get`: lines 17-58.
  - Hash equality checks tag+bits only line 50.
- `table_raw_set`: lines 61-119.
  - Rejects nil key lines 64-65.
  - Hash uses bits/tag/aux line 83.
  - Existing key equality checks tag+aux+bits line 94.
- `table_get`: lines 123-162.
  - Non-table type_error lines 129-132.
  - Only table metatable `__index`.
- `table_set`: lines 169-226.
  - Non-table type_error lines 175-178.
  - `set_err` converts any raw-set error to type_error lines 219-220.
- `table_next`: lines 230-317.
- `table_resize`: lines 320-380.
  - Allocates new array+nodes lines 326-333.
  - Preserves array entries lines 339-350.
  - Clears nodes lines 352-363.
  - Resets `node_count=0` line 371.
- `table_grow_for_key`: lines 383-405.
- `table_new`: lines 408-471.

Dangerous invariants:
- `table_resize` discards/not rehashes existing hash entries.
- Raw get and raw set disagree on key equality (`aux` ignored by get, used by set).
- `step_required` from allocator maps to oom in resize/new.

#### `src/regions_string.lua`
- Imports: lines 3-5.
- Size constant: line 10.
- `string_hash`: lines 14-27.
- `string_intern`: lines 30-100.
  - Missing runtime storage maps to oom lines 35-39.
  - Searches all buckets linearly lines 42-56; insert uses hashed bucket lines 87-94.
- `string_concat_range`: lines 106-155.
  - Only accepts existing strings; non-string error line 117.
  - Allocates temp bytes then interns lines 121-149.
- Dangerous invariant: temp concat buffer is never freed after intern.

#### `src/regions_metamethod.lua`
- Imports: lines 3-5.
- `get_metamethod`: lines 14-33. Only table values supported.
- `get_table_metamethod`: lines 36-64. Uses `G.tmname[event]`.
- `binop_dispatch`: lines 67-100.
- `unop_dispatch`: lines 104-127.
- `prepare_metamethod_call`: lines 131-146.
- Dangerous invariant: no non-table metatable sources; userdata/string/type metatables absent.

#### `src/regions_upvalue.lua`
- Imports: lines 3-5.
- `find_upvalue`: lines 12-27.
  - Scans open list lines 16-20.
  - **Stub:** `make_new` jumps oom lines 22-24.
- `close_upvalues`: lines 30-46.
- **Stub:** `make_lclosure` always oom lines 49-54.

#### `src/regions_gc.lua`
- Imports: lines 3-5; allocator import lines 15-17.
- `gc_check`: lines 20-30.
- **Stub:** `gc_step` immediate done lines 33-38.
- `mark_value`: lines 45-83.
  - marks table/lclosure/cclosure, strings done; userdata/thread/proto declared in constants but not handled.
- `mark_object`: lines 87-101.
- **Stub:** `propagate_gray` empty lines 104-110.
- **Stub:** `sweep_step` done lines 113-119.
- `write_barrier`: lines 126-139.
- **Stub:** `write_barrier_back` done lines 142-147.

#### `src/regions_gc_protocol.lua`
- Imports: lines 3-5.
- `decode_weak_mode`: lines 12-24.
- `classify_finalizer_state`: lines 27-40.

#### `src/regions_allocator.lua`
- Imports: lines 5-7.
- Product sizes: lines 14-30.
- `realloc_bytes`: lines 39-63.
  - Checks allocator/realloc lines 42-44.
  - `totalbytes > threshold` exits `step_required` lines 45-49.
  - Casts allocator.realloc to typed function pointer line 51.
- `alloc_bytes`: lines 68-76.
- `free_bytes`: lines 80-96.
- `alloc_object`: lines 99-122.
- `grow_value_array`: lines 125-149.
  - `step_required` maps to oom lines 142-143.
- `grow_frame_array`: lines 152-176.
  - `step_required` maps to oom lines 169-170.

Dangerous invariant:
- Size constants must track `products.lua`; no computed size source.

#### `src/regions_chunk.lua`
- Imports: lines 7-9.
- **Stub/frontier:** `load_lua55_binary_chunk`: lines 15-28.
  - Always returns `format_error` with `ERR_RUNTIME`.

#### `src/compat.lua`
- Imports constants/validate/compiler/native/chunk lines 3-7.
- Exposes:
  - `internal_proto_validator`: line 11.
  - `source_frontier`: line 12.
  - `binary_chunk_frontier`: line 13.
  - `native_abi_frontier`: line 14.
  - `puc_oracle_only = true`: line 15.

---

### Parser/compiler/codegen

#### `src/parser_constants.lua`
- Tokens: lines 3-25.
- Keywords: lines 27-43.
- Expression kinds: lines 45-58.
- Variable kinds: lines 60-65.
- Parse errors: lines 67-77.

#### `src/parser_products.lua`
- Import: `host` line 3.
- Source/error/token/lexer: lines 5-9.
- Compile arena/vectors: lines 11-17.
- Labels/locals/upvalues: lines 19-21.
- `FuncBuilder`: line 23.
- `ExpDesc`: line 25.
- `CompileUnit`: line 27.
- Export: lines 30-49.

#### `src/regions_compiler.lua`
- Import: `host` line 3.
- `compile_lua_source_into`: lines 6-80.
  - Initializes `CompileUnit`/`FuncBuilder`: lines 22-57.
  - Emits `compile_prepared_unit`: lines 59-63.
  - Routes syntax/semantic/limit/oom: lines 64-77.

#### `src/regions_codegen.lua`
- Imports: lines 3-6.
- Error/instruction emitters:
  - `emit_compile_error`: lines 16-28.
  - `instr_push`: lines 31-41.
  - `emit_ABC`: lines 44-56.
  - `emit_ABx`: lines 59-71.
  - `emit_AsBx`: lines 74-86.
- Register/value emitters:
  - `reserve_reg`: lines 89-105.
  - `emit_load_integer`: lines 108-124.
  - `emit_move`: lines 127-143.
  - booleans/nil: lines 147-183.
- Arithmetic bytecode emit:
  - `emit_binary_op`: lines 186-200; emits paired `OP_MMBIN`.
  - `emit_add/sub/mul/div`: lines 203-252.
- Return/local/name/proto:
  - `emit_return1`: lines 255-271.
  - `add_local`: lines 274-290.
  - `same_name`: lines 294-306.
  - `resolve_local`: lines 309-335.
  - `close_func_builder`: lines 337-357.
- Dangerous invariant: emits `TM_*` IDs from `constants.lua` into MMBIN line 197.

#### `src/regions_lexer.lua`
- Imports: lines 3-5.
- `make_lex_error`: lines 13-24.
- Byte classifiers: lines 27-56.
- `keyword_kind`: lines 59-75; only local/return.
- `lex_next`: lines 78-266.
  - whitespace/comments: lines 90-113.
  - names/keywords: lines 124-167.
  - decimal ints only: lines 170-183.
  - simple quoted string no escapes: lines 185-203.
  - operator dispatch: lines 206-240.
- Export: lines 269-276.

#### `src/regions_parser.lua`
- Imports: lines 3-5.
- `parser_error`: lines 14-26.
- `exp_to_reg`: lines 29-41.
- `parse_primary`: lines 44-137.
  - supports int/name/true/false/nil.
  - undeclared name semantic error lines 121-124.
- `parse_term`: lines 140-218. Handles `*` and `/`.
- `parse_expr`: lines 221-299. Handles `+` and `-`.
- `parse_return_statement`: lines 302-342. Single return expression.
- `parse_local_statement`: lines 345-398. `local name = expr`.
- `parse_statement`: lines 401-453. return/local/semicolon only.
- `parse_block`: lines 456-495.
- `compile_prepared_unit`: lines 498-544.
  - Rejects trailing statements after return lines 516-524.
- Export: lines 547-558.

Dangerous current source-slice limits:
- No functions/closures, calls, tables, loops, labels/goto, varargs, unary ops, comparisons as expressions, full numerals/strings/escapes.

---

## Tests / Current Coverage Anchors

- `test_vm_abi_contract.lua`
  - Contract version/SponJIT gated assertions lines 10-13.
  - ABI API check line 55.
- `test_vm_product_refoundation.lua`
  - Product/resume/native/table/userdata/global/coroutine checks lines 22-35.
- `test_vm_resume_protocol_contract.lua`
  - Resume routing check setup lines 53-65; unknown kind line 62.
- `test_vm_native_abi_contract.lua`
  - `decode_native_result` routes lines 44-56.
  - `invoke_native` nil rejection line 101.
- `test_vm_allocator_indirect_call.lua`
  - Indirect-call regression description lines 1-5.
  - Callback pointer run check line 46.
- `test_vm_compat_frontier.lua`
  - Compat exports lines 17-19.
  - Binary frontier explicit rejection line 39.
- `test_vm_table_protocols.lua`
  - `table_next` behavior lines 85-100.
  - `table_raw_set` array/hash insert/update lines 125-133.
- `test_vm_string_protocols.lua`
  - Hash check line 30.
  - Intern missing-runtime rejection line 48.
- `test_vm_validation_contract.lua`
  - Bytecode builders lines 30-36.
  - Validator cases lines 78-137.
- `test_vm_opcode_semantics.lua`
  - Focused opcode cases:
    - LOADNIL line 177.
    - LOADKX line 187.
    - ADDI line 198.
    - ADDK line 209.
    - f64 payload arithmetic lines 220-221.
    - inline scalar ops line 233.
    - compare ops line 256.
    - RETURN1 line 284.
- `test_vm_call_frame_contract.lua`
  - Child/parent call setup comments lines 91-100.
  - Result/cache reload assertions lines 141-144.
- `test_vm_error_contract.lua`
  - Bad opcode error-state assertions lines 105-108.
- `test_parser_compile.lua`
  - Compiler wrapper line 88; compiled wrapper line 108.
  - `compile_case` line 167.
  - `run_case` line 231.
  - Lexer case line 242.
  - Parser/e2e arithmetic cases lines 249-255.
- `test_vm_smoke.lua`
  - Module/region/struct inventory lines 17-51.
  - dispatch/vm_resume compile wrappers lines 56-120.
- `test_vm_e2e.lua`
  - Manual Proto construction starts line 107.
  - LOADK/RETURN instructions lines 118-124.
  - vm_resume wrapper/call lines 182-213.

---

## Main Stub/Error Exits Found

- Binary chunks: `regions_chunk.lua` lines 15-28 always `format_error`.
- Native success: `vm_loop.lua` lines 135-139 returns runtime error.
- `__call`: `regions_call.lua` lines 106-118 always not callable.
- Protected frames/calls:
  - `enter_protected` oom lines 192-201.
  - `protected_call` failure lines 215-225.
- TBC/`__close`: `regions_error.lua` lines 93-96 runtime error on found close method.
- Upvalues/closures:
  - `find_upvalue.make_new` oom lines 22-24.
  - `make_lclosure` oom lines 49-54.
  - `op_closure`, `op_vararg`, `op_getvarg` runtime errors in `op/closure.lua` lines 7-37.
  - `op_varargprep` no-op lines 40-47.
- Arithmetic/metamethod:
  - mod/idiv/pow and K variants error in `op/arithmetic.lua` lines 99-120, 320-341.
  - `op_mmbin*` runtime error lines 438-462.
- Compare metamethods: `op/compare.lua` `do_mm` blocks error lines 24-25, 54-55, 84-85, 154-155.
- `LEN`: `op/misc.lua` lines 7-13.
- `TFORCALL`: `op/loop.lua` lines 86-92.
- GC:
  - `gc_step` done only lines 33-38.
  - `propagate_gray` empty lines 104-110.
  - `sweep_step` done lines 113-119.
  - `write_barrier_back` done lines 142-147.
- Varargs: `regions_stack.lua` lines 135-141 maps to oom.
- API sealed stubs:
  - `lua_gettable_api`: `api.lua` lines 128-134.
  - `lua_settable_api`: lines 137-142.
  - `lua_call_api`: lines 145-150.
  - `lua_pcall_api`: lines 153-158.

## Edit-planner Output — 2026-05-30 10:43:18

### Precondition Checks

- Confirm current VM files still match these anchors:
  - `src/constants.lua`: TM constants begin at line 105 and still mismatch Lua 5.5.
  - `src/products.lua`: `GlobalState` at line 94, `LuaThread` at line 97.
  - `src/vm_loop.lua`: `native_ret` still errors at lines 135-139.
  - `src/regions_chunk.lua`: binary chunk loader still rejects at lines 15-28.
  - `src/op/arithmetic.lua`: `MOD/IDIV/POW/MMBIN*` still error at lines 99-120 and 438-462.
  - `src/regions_upvalue.lua`: `find_upvalue`/`make_lclosure` still exit `oom` at lines 22-54.
- Confirm `lua/lalin/back_command_binary.lua` contains the indirect-call signature-ID fix for `T.CallIndirect`; allocator/native tests depend on it.
- Confirm SponJIT files are not imported by `experiments/lua_interpreter_vm/src/init.lua`; no VM file should add a `spongejit` dependency.
- Run existing baseline tests before editing:
  - `luajit experiments/lua_interpreter_vm/tests/test_vm_smoke.lua`
  - `luajit experiments/lua_interpreter_vm/tests/test_vm_validation_contract.lua`
  - `luajit experiments/lua_interpreter_vm/tests/test_vm_opcode_semantics.lua`

---

### Files to Modify

#### `experiments/lua_interpreter_vm/src/constants.lua`

**Goal**: Align ABI constants with Lua 5.5 oracle and add missing explicit discriminants.

**Edit blocks**

1. **Lines 105-130**: Modify TM order.
   - Before: `EQ=4`, `ADD=5`, `LEN=12`, no `BNOT`.
   - After:
     ```lua
     TM.INDEX = 0
     TM.NEWINDEX = 1
     TM.GC = 2
     TM.MODE = 3
     TM.LEN = 4
     TM.EQ = 5
     TM.ADD = 6
     TM.SUB = 7
     TM.MUL = 8
     TM.MOD = 9
     TM.POW = 10
     TM.DIV = 11
     TM.IDIV = 12
     TM.BAND = 13
     TM.BOR = 14
     TM.BXOR = 15
     TM.SHL = 16
     TM.SHR = 17
     TM.UNM = 18
     TM.BNOT = 19
     TM.LT = 20
     TM.LE = 21
     TM.CONCAT = 22
     TM.CALL = 23
     TM.CLOSE = 24
     TM.N = 25
     ```
   - Quirk: update every test that assumes old TM ids.

2. **After line 17**: Add explicit type-metatable slot constants if using indexed primitive metatables:
   ```lua
   local TypeMeta = {}
   TypeMeta.NIL = 0
   TypeMeta.BOOLEAN = 1
   TypeMeta.LIGHTUD = 2
   TypeMeta.NUMBER = 3
   TypeMeta.STRING = 4
   TypeMeta.FUNCTION = 5
   TypeMeta.THREAD = 6
   TypeMeta.N = 7
   ```

3. **Lines 177-195**: Add distinct error codes for semantic routes currently collapsed:
   ```lua
   Err.METAMETHOD = 17
   Err.FINALIZER = 18
   Err.COROUTINE = 19
   Err.BINARY_CHUNK = 20
   ```
   Keep old numeric values stable; append only.

4. **Lines 240-247**: Add GC/finalizer helper constants only if needed:
   - weak-mode bits for `k`, `v`;
   - finalizer queue states already exist.

5. **Lines 265-278**: Export new `TypeMeta`.

**Patterns to enforce**
- Constants are ABI/storage values. Never reorder except the required TM oracle correction.
- Append new error/status constants; do not renumber existing non-TM constants.

**Danger zones**
- TM ids flow into bytecode `MMBIN*`, `G.tmname[event]`, codegen, and tests.

---

#### `experiments/lua_interpreter_vm/src/products.lua`

**Goal**: Complete runtime data products for primitive metatables, chunk reader state, GC traversal, varargs, and API/native resume state.

**Edit blocks**

1. **After line 49**: Add explicit native continuation payload if native re-entry is supported:
   ```lua
   local NativeContinuation = host.struct [[struct NativeContinuation fn: ptr(u8); ctx: ptr(u8); status: i32 end]]
   ```

2. **After line 68**: Add binary chunk reader product:
   ```lua
   local BinaryChunkReader = host.struct [[struct BinaryChunkReader data: ptr(u8); len: index; pos: index; endian: u8; int_size: u8; size_t_size: u8; instr_size: u8; lua_integer_size: u8; lua_number_size: u8; strip: u8 end]]
   ```

3. **Line 72 `ResumeState`**: Extend only if needed for finalizer/coroutine/native payloads. Preferred minimal change:
   - keep existing fields;
   - use `a/b/c`, `pc/base/result_base/call_top/wanted/value/errfunc_slot` consistently.
   - Do not add untyped side tables.

4. **Line 88 `Frame`**: Add vararg metadata:
   ```lua
   vararg_base: index; vararg_count: i32;
   ```
   Place before `resume` or after `call_top`; update all frame construction sites.

5. **Line 94 `GlobalState`**: Add primitive metatable table:
   ```lua
   type_metatables: ptr(ptr(Table));
   ```
   Keep `tmname` as `ptr(ptr(String))`.

6. **Line 97 `LuaThread`**: Add explicit yield/error transfer fields:
   ```lua
   yield_base: index; yield_nresults: i32;
   ```
   Keep `err_value` as the canonical error payload.

7. **Lines 102-131**: Export all new structs.

**Patterns to enforce**
- Any new cross-region semantic state must be a named product, not hidden Lua state.
- Keep `Value` unchanged unless unavoidable; many regions assume 16-byte layout.

**Danger zones**
- Hard-coded sizes in `regions_allocator.lua`, `regions_table.lua`, and `regions_string.lua` must be updated after struct changes.

---

#### `experiments/lua_interpreter_vm/src/init.lua`

**Goal**: Load new helper regions in dependency order.

**Edit blocks**

1. **Lines 15-35**: Add requires:
   ```lua
   vm.regions_key = require("experiments.lua_interpreter_vm.src.regions_key")
   vm.regions_numeric = require("experiments.lua_interpreter_vm.src.regions_numeric")
   vm.regions_binary_reader = require("experiments.lua_interpreter_vm.src.regions_binary_reader")
   vm.regions_finalizer = require("experiments.lua_interpreter_vm.src.regions_finalizer")
   ```
   Load before modules that emit them:
   - `regions_key` before table/value/metamethod;
   - `regions_numeric` before arithmetic/compare;
   - `regions_finalizer` before error/gc;
   - `regions_binary_reader` before `regions_chunk`.

**Danger zones**
- Do not import SponJIT.
- Avoid cyclic Lua `require` ordering between helper regions and opcode handlers.

---

#### `experiments/lua_interpreter_vm/src/contract.lua`

**Goal**: Bump ABI contracts after product/TM changes while preserving SponJIT separation.

**Edit blocks**

1. **Lines 2-5**: Increment:
   ```lua
   vm_abi_version = 2,
   native_abi_version = 2,
   validator_contract_version = 2,
   sponjit_allowed = false,
   ```
2. **Lines 7-14**: Replace gate names with final explicit gates:
   ```lua
   "lua55_tm_order",
   "bytecode_validator_complete",
   "binary_chunk_loader_complete",
   "source_compiler_complete",
   "frame_cache_reload_on_all_switches",
   "native_return_converges_with_lua_return",
   "unified_error_value_unwind",
   "explicit_coroutine_transfer",
   "gc_finalizer_weak_table_protocols",
   ```
   Keep `sponjit_allowed = false`.

---

#### `lua/lalin/back_command_binary.lua`

**Goal**: Keep indirect-call signatures correct for allocator/native function pointers.

**Edit blocks**

1. **Existing body encoder around `T.CallIndirect`**: Ensure it writes `sig_id` instead of zero:
   ```lua
   if tag == T.CallIndirect then
       local sid = b.sig_map and b.sig_map[id(cmd.sig)]
       assert(sid ~= nil, "missing indirect call signature id: " .. tostring(id(cmd.sig)))
       w4(buf, sid)
   else
       w4(buf, 0)
   end
   ```
2. **Signature table construction**: Ensure `b.sig_map = sig_idx` is assigned before command body emission.

**Danger zones**
- Do not change non-indirect call encoding.
- Run allocator/native tests immediately after this file.

---

#### `experiments/lua_interpreter_vm/src/bytecode.lua`

**Goal**: Make bytecode decoding the single Lua-side oracle for fields and signed operands.

**Edit blocks**

1. **Lines 30-44**: Extend `bytecode.exprs` to include:
   ```lua
   SK = "... signed K/immediate flag if needed ..."
   EVENT = "..." -- MMBIN event extraction if separate from C
   ```
   Only add expressions used by validator/opcodes.

2. **After line 79**: Add Lua helpers:
   ```lua
   bytecode.opname = { [0] = "MOVE", ... [84] = "EXTRAARG" }
   bytecode.arith_to_tm = { [Op.ADD]=TM.ADD, ... }
   bytecode.mmbin_expected = function(prev_word, mm_word) ... end
   ```
   Use `constants.lua`, but avoid circular import if necessary by passing maps in from validator.

**Patterns**
- All bit layout constants remain here.
- No duplicated magic shifts in validator after this change.

---

#### `experiments/lua_interpreter_vm/src/validate.lua`

**Goal**: Complete trust-boundary validation for all executable bytecode invariants.

**Edit blocks**

1. **Lines 41-52**: Replace manual decode expressions with names from `bytecode.exprs`.

2. **Lines 172-200**: Strengthen `MMBIN/MMBINI/MMBINK` checks:
   - verify following opcode kind;
   - verify event matches arithmetic opcode;
   - verify operands match Lua 5.5 paired-op rules;
   - reject dangling `MMBIN*`.

3. **Lines 204-212**: Extend compare/test validation:
   - `EQ/LT/LE/EQK/EQI/LTI/LEI/GTI/GEI/TEST/TESTSET` must be followed by `JMP`;
   - reject paired `JMP` target out of range.

4. **Lines 260-280**: Complete call/return window validation:
   - validate `CALL`, `TAILCALL`, `RETURN`, `RETURN0`, `RETURN1`;
   - validate vararg forms `VARARG`, `GETVARG`, `VARARGPREP`;
   - validate `CLOSURE` child/upvalue descriptor counts.

5. **After line 256**: Add close/TBC validation:
   - `TBC A` requires `A < maxstack`;
   - `CLOSE A` requires `A <= maxstack`;
   - to-be-closed ranges cannot exceed stack.

6. **Before line 283**: Add table/list validation:
   - `SETLIST` extraarg usage;
   - `NEWTABLE` extraarg usage;
   - `GETFIELD/SETFIELD` constant string index checks;
   - `GETTABUP/SETTABUP` upvalue bounds.

**Danger zones**
- Keep no wildcard validation escape for unknown opcodes.
- Validator must reject malformed bytecode before dispatch can observe it.

---

#### `experiments/lua_interpreter_vm/src/regions_value.lua`

**Goal**: Delegate equality, truthiness, conversion, and key semantics to explicit helper regions.

**Edit blocks**

1. **Existing equality region around lines 1-264**: Replace tag-only equality with `emit value_raw_equal`.
   - For int/float: exact numeric equality.
   - For strings/tables/functions/userdata/thread: identity.
   - For nil/booleans/lightuserdata: Lua semantics.

2. **Add/modify truthiness region**:
   - only `nil` and `false` are false;
   - integer zero and float zero are true.

3. **Remove any table-key equality duplication** and call `regions_key.value_key_equal`.

**Danger zones**
- Mixed integer/float equality must work for table comparisons and `EQ`.

---

#### `experiments/lua_interpreter_vm/src/regions_key.lua` **(new)**

- **Purpose**: Centralize table key equality and hashing.
- **Contents sketch**:
  - `region value_key_hash(v: Value; ok(hash: u32), invalid_key(), oom())`
  - `region value_key_equal(a: Value, b: Value; yes(), no())`
  - integer/float canonicalization for exact equal numeric keys;
  - reject nil and NaN keys;
  - include `aux` only where semantically meaningful.
- **Imports required**:
  - `constants`
  - `regions_numeric` for numeric canonical checks.

---

#### `experiments/lua_interpreter_vm/src/regions_numeric.lua` **(new)**

- **Purpose**: Centralize Lua 5.5 numeric conversion and arithmetic.
- **Contents sketch**:
  - `region value_to_integer(v; ok(i: i64), no())`
  - `region value_to_number(v; int(i: i64), float(n: f64), no())`
  - `region arithmetic_binop(event, lhs, rhs; value(v), call_mm(), error())`
  - `region arithmetic_unop(event, v; value(out), call_mm(), error())`
  - `region compare_values(event, lhs, rhs; true_(), false_(), call_mm(), error())`
  - helpers for `mod`, `idiv`, `pow`, bitwise ops, shifts.
- **Imports required**:
  - `constants`
  - `regions_string` only if string-to-number coercion is implemented there; otherwise keep string numeric parsing here.

---

#### `experiments/lua_interpreter_vm/src/regions_table.lua`

**Goal**: Complete raw table behavior, resizing, chained `__index/__newindex`, weak-mode state, and key semantics.

**Edit blocks**

1. **Lines 11-13**: Update hard-coded struct sizes after `products.lua` changes.

2. **Lines 17-58 `table_raw_get`**:
   - Replace `n.key.tag == key.tag and n.key.bits == key.bits` with `emit value_key_equal`.
   - Use `value_key_hash` to select bucket instead of linear bucket scan.
   - Preserve array fast path for positive integer keys.

3. **Lines 61-119 `table_raw_set`**:
   - Reject nil and NaN via `value_key_hash.invalid_key`.
   - Use same hash/equality helper as raw get.
   - On nil value, delete entry without incrementing `node_count`.
   - Call write barrier after storing collectable values.

4. **Lines 123-162 `table_get`**:
   - Implement chained `__index`:
     - raw hit → value;
     - no metatable or nil metamethod → nil;
     - table metamethod → repeat with loop counter;
     - callable metamethod → `call_mm`;
     - non-callable non-table → type_error.
   - Use explicit `loop_error` after bounded chain count.

5. **Lines 169-226 `table_set`**:
   - Implement chained `__newindex`:
     - existing raw key → store;
     - table metamethod → repeat set;
     - callable metamethod → `call_mm`;
     - nil metamethod → grow/raw store.
   - Do not map raw-set semantic errors to `oom`.

6. **Lines 320-380 `table_resize`**:
   - Preserve and rehash old hash entries.
   - Free old storage if allocator owns it.
   - Keep `node_count` accurate.
   - Do not reset hash entries without reinserting them.

7. **Lines 408-471 `table_new`**:
   - Initialize `metatable`, weak flags, finalizer state.
   - Link into `allgc`.
   - Route allocator `step_required` to GC step, not OOM.

**Danger zones**
- Raw get and raw set must use identical key equality.
- Rehashing must not invoke metamethods.

---

#### `experiments/lua_interpreter_vm/src/regions_string.lua`

**Goal**: Complete string interning, concatenation coercion, and memory ownership.

**Edit blocks**

1. **Line 10**: Update `SIZE_STRING` if struct size changed.

2. **Lines 30-100 `string_intern`**:
   - Use hash bucket traversal only; avoid full-table scan.
   - Grow string table when load factor is high.
   - Link new strings into `allgc`.
   - Add write barrier where needed.

3. **Lines 106-155 `string_concat_range`**:
   - Accept strings and numbers with Lua number-to-string conversion.
   - For other operands, exit through `call_mm` rather than direct error; adjust signature:
     ```lalin
     call_mm: cont(lhs_index: index, rhs_index: index)
     ```
   - Free temp buffer after intern success/failure if allocator owns it.

4. **Add numeric formatting helper region**:
   - integer decimal;
   - float oracle-compatible formatting.

**Danger zones**
- Interned string identity is table key equality for strings.
- Temporary concat buffers cannot leak across repeated concat.

---

#### `experiments/lua_interpreter_vm/src/regions_metamethod.lua`

**Goal**: Complete metamethod lookup for tables, userdata, and primitive type metatables.

**Edit blocks**

1. **Lines 14-33 `get_metamethod`**:
   - Replace table-only logic with tag dispatch:
     - table → table.metatable;
     - userdata → userdata.metatable;
     - string/number/boolean/lightuserdata/function/thread/nil → `G.type_metatables[slot]`.
   - Missing metatable → `missing`.

2. **Lines 36-64 `get_table_metamethod`**:
   - Keep `G.tmname[event]` lookup.
   - Validate `event < TM.N`.
   - Use raw table get; no metamethod recursion.

3. **Lines 67-127 `binop_dispatch` / `unop_dispatch`**:
   - Try first operand metamethod, then second operand where Lua requires it.
   - Return explicit `missing`, `found`, `error` outcomes.

4. **Lines 131-146 `prepare_metamethod_call`**:
   - Write callable and args into explicit stack slots.
   - Build `ResumeState` with the correct kind:
     - `BINOP_MM`, `UNOP_MM`, `LEN_MM`, `CONCAT_MM`, `EQ_MM`, `LT_MM`, `LE_MM`, `CALL_MM`, etc.
   - Call `prepare_call`.

**Danger zones**
- `TM.CLOSE` lookup must use `G.tmname[TM.CLOSE]`, not a fake string value.

---

#### `experiments/lua_interpreter_vm/src/regions_call.lua`

**Goal**: Make Lua/native/metamethod calls converge through one explicit call/return protocol.

**Edit blocks**

1. **Lines 25-103 `prepare_call`**:
   - Before `ERR_CALL`, emit `try_call_metamethod`.
   - For vararg functions, fill `Frame.vararg_base/vararg_count`.
   - Set `Frame.flags` from yieldability/protected state.

2. **Lines 106-118 `try_call_metamethod`**:
   - Implement `__call`:
     - lookup metamethod with `TM.CALL`;
     - shift original function value to arg 1;
     - place metamethod in `func_slot`;
     - exit `replaced`.

3. **Lines 121-187 `call_native`**:
   - On `returned`, call result-adjustment helper shared with Lua returns.
   - On `yielded`, store `LuaThread.yield_base/yield_nresults` and status.
   - On `reenter_lua`, route to explicit continuation rather than `ERR_CALL`.

4. **Lines 192-272 `return_from_lua`**:
   - Preserve error/yield payloads.
   - Add handling for all `ResumeState.kind` values:
     - native continuation;
     - finalizer;
     - coroutine resume/yield;
     - xpcall;
     - len/call metamethod.
   - Every frame switch must return parent frame only; `vm_loop` reloads cached code/constants.

**Danger zones**
- Native successful return must not diverge from Lua successful return.
- Do not read child `cur_code/cur_consts` after popping child frame.

---

#### `experiments/lua_interpreter_vm/src/regions_resume.lua`

**Goal**: Decode every persisted control state and perform final result writeback.

**Edit blocks**

1. **Lines 13-59 `decode_resume_kind`**:
   - Add all current `Resume.*` values:
     - `XPCALL`, `LEN_MM`, `CALL_MM`, `NATIVE_CONT`, `FINALIZER_CALL`, `COROUTINE_RESUME`, `COROUTINE_YIELD`.

2. **Lines 80-189 `resume_after_return`**:
   - Add explicit blocks for:
     - `LEN_MM`: write result to `a`;
     - `CALL_MM`: resume original caller with returned values;
     - `EQ_MM/LT_MM/LE_MM`: coerce first result to boolean and apply jump behavior;
     - `NATIVE_CONT`: invoke native continuation or re-enter VM;
     - `FINALIZER_CALL`: continue close/finalizer queue;
     - `COROUTINE_RESUME`: transfer results to caller thread;
     - `COROUTINE_YIELD`: park yielding thread and resume caller.
   - Keep `unknown` as runtime error.

3. **Lines 191-207 `clear_resume`**:
   - Clear all payload fields, including any new fields in `ResumeState`.

**Danger zones**
- Do not collapse unknown resume kinds into normal return.
- Result adjustment must respect `wanted == -1` multi-return behavior.

---

#### `experiments/lua_interpreter_vm/src/vm_loop.lua`

**Goal**: Route all VM control transfers explicitly and reload frame caches after every active-frame switch.

**Edit blocks**

1. **Lines 92-102 dispatch emit**:
   - Add continuations required by native reentry/coroutine/finalizer if dispatch signature changes.

2. **Lines 115-130**:
   - Keep parent and child cache reload logic.
   - Factor repeated reload into blocks if helpful:
     ```lalin
     let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
     let code: ptr(Instr) = cl.proto.code
     let constants: ptr(Value) = cl.proto.constants
     ```

3. **Lines 131-139 `do_native/native_ret`**:
   - Replace runtime error with return convergence:
     ```lalin
     block native_ret(nres: i32)
         emit resume_after_return/native_return_adjustment ...
     end
     ```
   - Store status/yield results for native yield.

4. **Lines 149-158 error/caught_error**:
   - Preserve `L.err_value`.
   - Reload frame caches after protected catch.
   - If no protected frame, set `RUNTIME_ERROR`.

5. **Add blocks for coroutine transfer**:
   - entering a yielded thread;
   - returning/yielding to caller.

**Danger zones**
- Cached `code/constants/base/top` must never belong to an inactive frame.

---

#### `experiments/lua_interpreter_vm/src/regions_error.lua`

**Goal**: Implement value-carrying errors, protected calls, to-be-closed variables, and finalizer error routing.

**Edit blocks**

1. **Lines 15-24 `build_error_object`**:
   - Preserve full error `Value`.
   - Only synthesize code-in-aux for code-originated errors.

2. **Lines 27-55 `raise_code_error`**:
   - Set both `L.last_error_code` and `L.err_value`.

3. **Lines 64-106 `tbc_close_chain`**:
   - Replace found-`__close` runtime error with call setup.
   - Build `ResumeState.TBC_CLOSE`.
   - Pass original error object into close call as Lua requires.

4. **Lines 109-132 `tbc_get_close`**:
   - Use `get_metamethod(... TM.CLOSE ...)`.
   - Support table/userdata/primitive if Lua permits.

5. **Lines 136-188 `raise_error`**:
   - Unwind frames to `protected_top`.
   - Run close handlers while unwinding.
   - Route caught error to protected frame result slots.

6. **Lines 192-201 `enter_protected`**:
   - Allocate/push `ProtectedFrame`.
   - Save frame count, stack top, handler slot, errfunc slot, resume state.

7. **Lines 215-225 `protected_call`**:
   - Implement `pcall`/`xpcall` call setup:
     - success writes `true, results...`;
     - failure writes `false, error`;
     - xpcall invokes handler through explicit resume kind.

**Danger zones**
- No longjmp-like hidden unwind.
- `__close` errors replace or combine with prior error according to Lua 5.5 semantics.

---

#### `experiments/lua_interpreter_vm/src/regions_coroutine.lua`

**Goal**: Implement explicit thread transfer for resume/yield.

**Edit blocks**

1. **Lines 20-46 `coroutine_resume`**:
   - Validate target status.
   - Move resume args into target stack.
   - Set `target.coroutine.caller = L`.
   - Build `ResumeState.COROUTINE_RESUME`.
   - Exit through `enter_thread(target)` continuation; update signature.

2. **Lines 53-72 `coroutine_yield`**:
   - Reject nonyieldable contexts.
   - Store yielded results in yielding thread.
   - Transfer to caller thread through explicit continuation.
   - Set statuses: yielding thread `YIELDED`, caller `OK`.

**Danger zones**
- Yield across nonyieldable native/protected/finalizer boundary must produce `ERR_YIELD`.

---

#### `experiments/lua_interpreter_vm/src/regions_stack.lua`

**Goal**: Complete stack growth, result adjustment, and vararg layout.

**Edit blocks**

1. **Frame push/pop areas around lines 1-151**:
   - Update `Frame` initialization for new `vararg_base/vararg_count`.
   - Preserve old stack values during grow.

2. **Lines 135-141 current vararg OOM route**:
   - Implement `adjust_varargs`:
     - fixed params stay at base;
     - extra args copied to vararg segment;
     - missing fixed params filled nil;
     - set frame vararg metadata.

3. **Add result adjustment helper**:
   - shared by Lua return, native return, metamethod return, coroutine resume.

**Danger zones**
- `wanted == -1` must preserve all returned values.

---

#### `experiments/lua_interpreter_vm/src/regions_upvalue.lua`

**Goal**: Implement open/closed upvalues and closure allocation.

**Edit blocks**

1. **Lines 12-27 `find_upvalue`**:
   - If existing `stack_index` found, return it.
   - Else allocate `UpVal`, link into `L.open_upvals` sorted by descending stack index.
   - Set `v = L.stack + stack_index`, `closed = nil`.

2. **Lines 30-46 `close_upvalues`**:
   - For every open upvalue at or above stack index:
     - copy `*v` into `closed`;
     - set `v = &closed`;
     - unlink from open list.
   - Run TBC close handling before stack slots are invalidated.

3. **Lines 49-54 `make_lclosure`**:
   - Allocate `LClosure` plus upvalue pointer array.
   - Initialize env/proto/nupvals.
   - Link into GC list.
   - For each `UpValDesc`, capture local or parent upvalue.

**Danger zones**
- Open upvalue list order matters for efficient close.
- Child closure must share parent upvalue object, not copy value.

---

#### `experiments/lua_interpreter_vm/src/regions_gc.lua`

**Goal**: Implement incremental mark/sweep, weak tables, barriers, and finalizer queue movement.

**Edit blocks**

1. **Lines 20-38 `gc_check/gc_step`**:
   - Route allocator `step_required` into bounded GC work.
   - Advance `GCState` explicitly.

2. **Lines 45-83 `mark_value`**:
   - Handle all collectable tags:
     - string, table, lclosure, cclosure, userdata, thread, proto.

3. **Lines 87-110 `mark_object/propagate_gray`**:
   - Traverse object fields:
     - table array/hash/metatable;
     - closure proto/upvalues/env;
     - thread stack/frames/open upvalues;
     - userdata metatable/user values;
     - proto constants/children/debug strings.

4. **Lines 113-119 `sweep_step`**:
   - Sweep `allgc`.
   - Free unreachable objects through allocator.
   - Preserve finalizable objects by moving to finalizer queue.

5. **Lines 126-147 barriers**:
   - Implement forward and back barriers using object colors.
   - Queue black-to-white table/closure updates.

6. **Add weak clearing/finalizer queue processing**:
   - weak keys/values/ephemeron behavior from table flags;
   - finalizer call uses `ResumeState.FINALIZER_CALL`.

**Danger zones**
- Finalizer execution can re-enter VM; must not run hidden calls inside GC step without explicit continuation.

---

#### `experiments/lua_interpreter_vm/src/regions_allocator.lua`

**Goal**: Preserve allocator/GC distinction and update size constants.

**Edit blocks**

1. **Lines 14-30**:
   - Update sizes after `products.lua` changes.
   - Add sizes for new products:
     ```lua
     I.SIZE_UPVAL = ...
     I.SIZE_LCLOSURE = ...
     I.SIZE_BINARY_CHUNK_READER = ...
     ```

2. **Lines 39-63 `realloc_bytes`**:
   - Keep `step_required` distinct from `oom`.
   - Do not let callers collapse `step_required` unless they first emit `gc_step`.

3. **Lines 125-176 grow helpers**:
   - Replace `step_required = oom` with:
     - emit `gc_step`;
     - retry once/bounded;
     - then `oom`.

**Danger zones**
- Indirect allocator call depends on backend signature IDs.

---

#### `experiments/lua_interpreter_vm/src/regions_native.lua`

**Goal**: Complete native ABI result routing.

**Edit blocks**

1. **Lines 12-45 `invoke_native`**:
   - Validate ABI version, stack bounds, and yieldability before call.
   - Preserve `ctx.resume`.

2. **Lines 49-80 `decode_native_result`**:
   - Keep all status cases.
   - For `REENTER_LUA`, include explicit continuation payload if product added.
   - For invalid status, set `ERR_CALL`.

**Danger zones**
- Native error carries `Value`, not just integer code.

---

#### `experiments/lua_interpreter_vm/src/regions_chunk.lua`

**Goal**: Replace explicit rejection with a Lua 5.5 binary chunk reader that produces Lalin-native `Proto`.

**Edit blocks**

1. **Lines 15-28**: Replace whole region with reader pipeline:
   - validate signature/version/format;
   - read sizes and endianness;
   - read top-level function proto;
   - validate resulting proto via `validate_proto`;
   - return `ok(proto)`.

2. **Use new `regions_binary_reader.lua` helpers**:
   - `read_u8/u16/u32/u64`;
   - `read_lua_integer`;
   - `read_lua_number`;
   - `read_string`;
   - `read_code`;
   - `read_constants`;
   - `read_upvalue_descs`;
   - `read_children`;
   - `read_debug`.

3. **Error routing**
   - malformed bytes → `format_error`;
   - semantically invalid proto → `semantic_error`;
   - allocation failure → `oom`.

**Danger zones**
- Do not cast external bytes to VM structs.
- PUC binary format is input data only; never import PUC in-memory layouts.

---

#### `experiments/lua_interpreter_vm/src/regions_binary_reader.lua` **(new)**

- **Purpose**: Typed reader for Lua 5.5 binary chunks.
- **Contents sketch**:
  - reader bounds checks;
  - endian-aware integer reads;
  - string allocation/interning;
  - proto graph allocation;
  - constant decoding into `Value`;
  - recursive child proto loading.
- **Imports required**:
  - `constants`
  - `products`
  - `regions_allocator`
  - `regions_string`
  - `validate`

---

#### `experiments/lua_interpreter_vm/src/op/protocols.lua`

**Goal**: Give every opcode handler a precise continuation group.

**Edit blocks**

1. **Lines 5-16**: Add protocol strings for:
   - metamethod call;
   - generic-for call;
   - length/concat call;
   - closure/upvalue allocation;
   - vararg;
   - protected/error/yield.

2. **Lines 18-27**: Split `TFORCALL` away from `MMBIN`.
   - Add `C_TFORCALL`.

**Danger zones**
- Do not reuse binary metamethod protocol for iterator calls.

---

#### `experiments/lua_interpreter_vm/src/opcodes.lua`

**Goal**: Dispatch all opcodes through correct typed handler protocols.

**Edit blocks**

1. **Lines 27-35**:
   - Use `bytecode.exprs` names only.

2. **Lines 70-82 and 86-148**:
   - Add emit templates for new protocols from `op/protocols.lua`.

3. **Lines 193-500 inline arithmetic/compare**:
   - Either delegate to `regions_numeric` or ensure inline fast paths exactly mirror it.
   - Fast primitive arithmetic still skips paired `MMBIN*` via `pc + 2`.
   - Slow path must advance to paired fallback via `pc + 1`.

4. **Line 585**:
   - Change:
     ```lua
     emit_arm(76, "op_tforcall", C_MMBIN, ARGS_ABC)
     ```
     to:
     ```lua
     emit_arm(76, "op_tforcall", C_TFORCALL, ARGS_ABC)
     ```

5. **Lines 596-658 dispatch region**:
   - Add continuations required by new protocols.
   - Keep default bad-opcode branch.

6. **Lines 667-717 metadata**:
   - Update opcode metadata for validator/test use:
     - paired arithmetic;
     - call-like opcodes;
     - close/TBC;
     - vararg.

**Danger zones**
- Exhaustive switch must remain explicit; no wildcard handler except default bad opcode.

---

#### `experiments/lua_interpreter_vm/src/op/arithmetic.lua`

**Goal**: Complete numeric ops and metamethod fallback.

**Edit blocks**

1. **Lines 18-96 existing add/sub/mul/div**:
   - Replace narrow tag checks with `regions_numeric.arithmetic_binop`.
   - Preserve primitive fast returns where correct.

2. **Lines 99-120**:
   - Implement `MOD`, `IDIV`, `POW`.

3. **Lines 123-194 and 198-241**:
   - Route bitwise ops through integer conversion helper.
   - Fix `ADDI` handler to use signed `sc`, not unsigned `c`.

4. **Lines 244-388 K variants**:
   - Implement `MODK`, `POWK`, `IDIVK`.
   - Ensure constants are bounds-validated already but not trusted blindly.

5. **Lines 392-435 unary ops**:
   - Implement `BNOT` and numeric `UNM` for int/float.
   - `NOT` remains truthiness-only.

6. **Lines 438-462 `op_mmbin*`**:
   - Decode event from instruction.
   - Lookup metamethod with `binop_dispatch`.
   - Call metamethod with correct `ResumeState`.
   - If missing, raise `ERR_ARITH`.

**Danger zones**
- Primitive success skips paired fallback; primitive failure enters paired fallback.

---

#### `experiments/lua_interpreter_vm/src/op/compare.lua`

**Goal**: Complete equality/order comparisons and metamethods.

**Edit blocks**

1. **Lines 7-95 `EQ/LT/LE`**:
   - Use `regions_numeric.compare_values` and `value_raw_equal`.
   - Implement `EQ_MM`, `LT_MM`, `LE_MM` resume states.

2. **Lines 98-171 immediate/K comparisons**:
   - Apply same comparison helper.
   - Correct signed immediate handling.

3. **Lines 24-25, 54-55, 84-85, 154-155**:
   - Replace `ERR_COMPARE` direct branches with metamethod call setup.

4. **Lines 175-209 `TEST/TESTSET`**:
   - Use central truthiness helper.

---

#### `experiments/lua_interpreter_vm/src/op/table.lua`

**Goal**: Complete table op semantics and stop hiding semantic errors as OOM.

**Edit blocks**

1. **Lines 7-210 get/set handlers**:
   - Use completed `table_get/table_set`.
   - Metamethod calls must build correct resume states.

2. **Lines 212-238 `op_newtable`**:
   - Interpret `B/C/extraarg` sizes per Lua 5.5.
   - Allocate table with correct array/hash capacities.

3. **Lines 264-312 `op_setlist`**:
   - Non-table → `ERR_TYPE`, not OOM.
   - Raw set errors → `ERR_INDEX`/`ERR_TYPE`, not OOM.
   - Respect extraarg large block index.

---

#### `experiments/lua_interpreter_vm/src/op/call.lua`

**Goal**: Complete call, tailcall, return, and yield-aware result paths.

**Edit blocks**

1. **Lines 7-80 `op_call`**:
   - Support `B == 0` actual arg count from `top`.
   - Support `C == 0` multi-result wanted.
   - Set `ResumeState.NORMAL`.

2. **Lines 82-135 `op_tailcall`**:
   - Reuse current frame when legal.
   - Close upvalues/TBC as required.
   - Preserve tailcall count.

3. **Lines 137-271 returns**:
   - Close upvalues/TBC before frame pop.
   - Correctly compute `first_result` and `nres`.
   - Do not map yielded return to finished.

---

#### `experiments/lua_interpreter_vm/src/op/loop.lua`

**Goal**: Complete numeric and generic for loops.

**Edit blocks**

1. **Lines 7-74 numeric for**:
   - Support int and float loops with Lua 5.5 coercions.
   - Validate step zero behavior.
   - Update control variable exactly as oracle.

2. **Lines 76-108 generic for**:
   - Implement `TFORPREP`, `TFORCALL`, `TFORLOOP`.
   - `TFORCALL` calls iterator with state/control vars.
   - Resume through `ResumeState.TFORLOOP_CALL`.

---

#### `experiments/lua_interpreter_vm/src/op/misc.lua`

**Goal**: Complete length, concat, close/TBC, and nil-check ops.

**Edit blocks**

1. **Lines 7-13 `op_len`**:
   - Strings → length.
   - Tables → Lua table length boundary search.
   - Other values → `TM.LEN` metamethod or `ERR_TYPE`.

2. **Lines 16-43 `op_concat`**:
   - Use completed `string_concat_range`.
   - Metamethod fallback via `TM.CONCAT`.
   - Resume with `ResumeState.CONCAT_MM`.

3. **Lines 46-75 `op_close/op_tbc`**:
   - Register to-be-closed slots.
   - Emit close chain on `CLOSE`.
   - Preserve errors through close.

4. **Lines 87-99 `op_errnnil`**:
   - Raise value-carrying error.

---

#### `experiments/lua_interpreter_vm/src/op/closure.lua`

**Goal**: Implement closure and vararg opcodes.

**Edit blocks**

1. **Lines 7-15 `op_closure`**:
   - Load child proto.
   - Emit `make_lclosure`.
   - Store closure value in `A`.

2. **Lines 18-37 `op_vararg/op_getvarg`**:
   - Copy requested varargs to registers.
   - Support wanted count zero/multi-result.

3. **Lines 40-47 `op_varargprep`**:
   - Initialize frame vararg metadata.

---

#### `experiments/lua_interpreter_vm/src/op/load.lua`

**Goal**: Keep load/upvalue ops consistent with final closure semantics.

**Edit blocks**

1. **Lines 137-158 `GETUPVAL/SETUPVAL`**:
   - Validate upvalue pointer nonnil.
   - Read/write through `uv.v`.
   - Apply write barrier for collectable writes.

---

#### `experiments/lua_interpreter_vm/src/regions_codegen.lua`

**Goal**: Emit bytecode consistent with corrected TM ids and complete source compiler.

**Edit blocks**

1. **Lines 186-200 `emit_binary_op`**:
   - Use corrected `TM.*`.
   - Emit matching `MMBIN*` event for every arithmetic opcode.

2. **After line 252**:
   - Add emitters for:
     - comparisons;
     - unary ops;
     - table constructors;
     - calls;
     - closures;
     - loops;
     - labels/goto;
     - varargs;
     - TBC/close.

3. **Lines 337-357 `close_func_builder`**:
   - Fill full `Proto`:
     - constants;
     - children;
     - upvalue descriptors;
     - locvars;
     - lineinfo;
     - numparams;
     - flags;
     - maxstack.

---

#### `experiments/lua_interpreter_vm/src/regions_lexer.lua`

**Goal**: Lex full Lua 5.5 source.

**Edit blocks**

1. **Lines 27-75 classifiers/keywords**:
   - Add all Lua keywords and punctuators.

2. **Lines 170-203 numerals/strings**:
   - Implement decimal/hex integers/floats.
   - Implement short and long strings.
   - Implement escapes and UTF escapes as Lua 5.5 requires.

3. **Lines 206-240 operator dispatch**:
   - Add multi-char tokens:
     `//`, `..`, `...`, `==`, `~=`, `<=`, `>=`, `<<`, `>>`, `::`.

---

#### `experiments/lua_interpreter_vm/src/regions_parser.lua`

**Goal**: Parse full Lua 5.5 grammar into explicit compile products.

**Edit blocks**

1. **Lines 44-299 expression parsing**:
   - Replace simple precedence parser with full precedence table:
     - or/and;
     - comparisons;
     - bitwise;
     - shifts;
     - concat right-associative;
     - add/sub;
     - mul/div/idiv/mod;
     - unary;
     - power right-associative;
     - primary suffix calls/indexing.

2. **Lines 302-453 statements**:
   - Add assignment, function call statements, do/end, while, repeat, if, numeric/generic for, function definitions, local function, labels/goto, break, return, TBC locals.

3. **Lines 456-495 block parsing**:
   - Track labels, gotos, local scope, upvalues, close variables.

4. **Lines 498-544 compile entry**:
   - Build nested function prototypes.
   - Validate unresolved gotos and upvalues.

---

#### `experiments/lua_interpreter_vm/src/regions_compiler.lua`

**Goal**: Compile full source into validated `Proto`.

**Edit blocks**

1. **Lines 22-57 builder initialization**:
   - Initialize new builder fields for constants, children, labels, gotos, upvalues, varargs, lineinfo.

2. **Lines 59-63 compile call**:
   - After codegen, emit validator.
   - Route validator failure as `semantic_error`.

---

#### `experiments/lua_interpreter_vm/src/compat.lua`

**Goal**: Expose completed frontiers while preserving oracle/SponJIT boundaries.

**Edit blocks**

1. **Lines 11-15**:
   - Keep:
     ```lua
     puc_oracle_only = true
     ```
   - Ensure:
     ```lua
     binary_chunk_frontier = chunk.load_lua55_binary_chunk
     source_frontier = compiler.compile_lua_source_into
     ```
   - Add:
     ```lua
     sponjit_integrated = false
     ```

---

### New Files

#### `experiments/lua_interpreter_vm/src/regions_key.lua`
- Central table key hash/equality semantics.

#### `experiments/lua_interpreter_vm/src/regions_numeric.lua`
- Central Lua 5.5 numeric conversions/arithmetic/comparison.

#### `experiments/lua_interpreter_vm/src/regions_binary_reader.lua`
- Binary chunk reader helpers.

#### `experiments/lua_interpreter_vm/src/regions_finalizer.lua`
- Finalizer queue execution and `__gc`/`__close` call setup.

#### `experiments/lua_interpreter_vm/tests/test_vm_lua55_tm_contract.lua`
- Assert TM order exactly matches vendored Lua 5.5.

#### `experiments/lua_interpreter_vm/tests/test_vm_numeric_semantics.lua`
- Int/float arithmetic, division, modulo, idiv, pow, bitwise, equality, NaN.

#### `experiments/lua_interpreter_vm/tests/test_vm_metamethod_semantics.lua`
- `__index`, `__newindex`, arithmetic, comparison, concat, len, call, close.

#### `experiments/lua_interpreter_vm/tests/test_vm_closure_upvalue_semantics.lua`
- Open/closed upvalues, nested closures, varargs.

#### `experiments/lua_interpreter_vm/tests/test_vm_binary_chunk_semantics.lua`
- Load binary chunk fixtures and execute.

#### `experiments/lua_interpreter_vm/tests/test_vm_coroutine_protected_semantics.lua`
- `pcall`, `xpcall`, yield/resume, yield errors.

#### `experiments/lua_interpreter_vm/tests/test_vm_gc_finalizer_semantics.lua`
- Weak tables, barriers, finalizers, userdata.

---

### Order of Operations

1. Apply backend indirect-call signature fix and run allocator/native ABI tests.
2. Correct `constants.lua` TM order and bump contract versions.
3. Update `products.lua` and all hard-coded size constants.
4. Add `regions_key.lua` and `regions_numeric.lua`; wire through `init.lua`.
5. Update `regions_value.lua`, `regions_table.lua`, and `regions_string.lua`.
6. Complete `regions_metamethod.lua`.
7. Complete call/resume/native/error/coroutine stack control:
   - `regions_stack.lua`
   - `regions_call.lua`
   - `regions_resume.lua`
   - `regions_error.lua`
   - `regions_coroutine.lua`
   - `vm_loop.lua`
8. Implement upvalues/closures/varargs.
9. Complete opcode handlers and dispatch protocols.
10. Complete GC/allocator/finalizer behavior.
11. Complete validator and bytecode helper consolidation.
12. Implement binary chunk reader.
13. Complete lexer/parser/codegen/compiler.
14. Update compat exports and tests.
15. Run full VM test suite.

---

### Testing Strategy

- After constants/product edits:
  - `test_vm_product_refoundation.lua`
  - `test_vm_lua55_tm_contract.lua`
- After backend/native edits:
  - `test_vm_allocator_indirect_call.lua`
  - `test_vm_native_abi_contract.lua`
- After numeric/value/table/string edits:
  - `test_vm_numeric_semantics.lua`
  - `test_vm_table_protocols.lua`
  - `test_vm_string_protocols.lua`
- After call/resume/error/coroutine edits:
  - `test_vm_resume_protocol_contract.lua`
  - `test_vm_call_frame_contract.lua`
  - `test_vm_error_contract.lua`
  - `test_vm_coroutine_protected_semantics.lua`
- After opcode edits:
  - `test_vm_opcode_semantics.lua`
  - add bytecode-level tests for every opcode 0-84.
- After validator/chunk/source edits:
  - `test_vm_validation_contract.lua`
  - `test_vm_binary_chunk_semantics.lua`
  - `test_parser_compile.lua`
  - `test_vm_e2e.lua`
- Final verification:
  - run every `experiments/lua_interpreter_vm/tests/test_*.lua`.
  - grep check: no fail-loud semantic branches remain for implemented Lua behavior:
    - `grep -R "ERR_RUNTIME" experiments/lua_interpreter_vm/src/op experiments/lua_interpreter_vm/src/regions_*.lua`
    - inspect every remaining hit.

---

### Pattern Memo

- Every Lua-visible semantic distinction must be a named product field, constant, or continuation.
- PUC Lua 5.5 is an oracle for behavior and external bytecode facts only; never copy PUC layouts.
- SponJIT stays separate: no `spongejit` imports, `sponjit_allowed = false`.
- All active-frame switches reload `code/constants/base/top`.
- Native and Lua returns converge through the same result-adjustment path.
- Allocator `step_required` is not OOM; emit GC work then retry.
- Table raw get/set must share one key equality/hash implementation.
- Metamethod lookup always goes through `G.tmname[event]`.
- Opcode slow paths use explicit `ResumeState.kind`; no stringly hidden state.
- Validator rejects malformed paired opcodes before dispatch sees them.

## Worker Output — 2026-05-30 10:54:54

## Completed

- Aligned VM `TM` constants with Lua 5.5 oracle order from `.vendor/Lua/ltm.h`.
- Added explicit `TypeMeta` discriminants and appended semantic error codes.
- Bumped VM/native/validator ABI constants and contract gates while keeping `sponjit_allowed = false`.
- Strengthened `validate_proto` so arithmetic opcodes must be followed by matching `MMBIN*`:
  - correct fallback opcode kind
  - correct source operands
  - correct metamethod event
- Corrected source codegen for `OP_MMBIN` to encode operands/event in Lua 5.5 fields (`A`, `B`, `C`), not event in `B`.
- Split generic-for `TFORCALL` into its own named opcode continuation protocol instead of reusing `mmbin`.
- Updated tests to use central `bytecode` encoders for affected instructions.
- Added a Lua 5.5 TM-order contract test.

## Files Changed

- `experiments/lua_interpreter_vm/src/constants.lua` - Lua 5.5 `TM` order, `TypeMeta`, ABI v2, appended errors.
- `experiments/lua_interpreter_vm/src/contract.lua` - ABI/validator v2 and updated required gates.
- `experiments/lua_interpreter_vm/src/validate.lua` - paired arithmetic/`MMBIN*` operand and event validation.
- `experiments/lua_interpreter_vm/src/regions_codegen.lua` - emits oracle-aligned `MMBIN` fields.
- `experiments/lua_interpreter_vm/src/op/protocols.lua` - added `tforcall` protocol.
- `experiments/lua_interpreter_vm/src/op/_init.lua` - exported `TFORCALL_CONTS`.
- `experiments/lua_interpreter_vm/src/op/loop.lua` - `op_tforcall` uses named generic-for protocol.
- `experiments/lua_interpreter_vm/src/opcodes.lua` - dispatch maps `TFORCALL` to `generic_for_call`.
- `experiments/lua_interpreter_vm/tests/test_vm_lua55_tm_contract.lua` - new TM ABI oracle test.
- `experiments/lua_interpreter_vm/tests/test_vm_validation_contract.lua` - added paired-op validation cases.
- `experiments/lua_interpreter_vm/tests/test_vm_abi_contract.lua` - ABI assertions use constants.
- `experiments/lua_interpreter_vm/tests/test_vm_opcode_semantics.lua` - updated `MMBIN*`/`ADDI` encodings.
- `experiments/lua_interpreter_vm/tests/test_vm_call_frame_contract.lua` - updated `MMBIN` encoding.
- `experiments/lua_interpreter_vm/tests/test_vm_smoke.lua` - ABI smoke check follows constants.

## Tests Run

Passed:

```sh
luajit experiments/lua_interpreter_vm/tests/test_parser_compile.lua
for t in experiments/lua_interpreter_vm/tests/test_vm*.lua; do luajit "$t"; done
```

Also specifically observed:

- `test_vm_lua55_tm_contract.lua` PASS
- `test_vm_validation_contract.lua` 25/25 PASS
- all `test_vm*.lua` PASS
- parser/source slice PASS

Full `test_*.lua` sweep was not clean because `test_sponjit_shadow.lua` fails with `lowering failed`; that is outside the VM slice and preserves the requested SponJIT separation.

## Notes

Remaining VM completion work is still substantial: binary chunks, full source grammar/codegen, closures/upvalues/varargs, protected calls/TBC/finalizers, coroutine transfer, full GC/weak tables, native-success convergence, full numeric/metamethod/table semantics.

## Shared Workflow Context

Workflow ID: `wf-lua-vm-finish-final`

## Worker Output — 2026-05-30 11:08:14

## Completed

Implemented a substantial connected runtime push in two areas:

1. **Native success now converges with Lua return/resume**
   - `call_native` no longer treats `NativeResult.OK` as a gated/stub outcome.
   - Native results are adjusted through `resume_after_return` using the explicit `NativeCallContext.resume`.
   - `vm_loop.native_ret` now reloads the active frame’s `code/constants` and resumes execution, matching the frame-cache invariant used by Lua returns.
   - Added an end-to-end test where a real FFI native callback writes a result and the VM continues to execute the following Lua `RETURN1`.

2. **Primitive numeric semantics expanded**
   - Mixed integer/float `ADD/SUB/MUL/DIV` fast paths now execute as primitive numeric behavior instead of falling into metamethod/error paths.
   - Integer `/` now returns `TAG_NUM`, matching Lua division semantics.
   - Integer `MOD`, `IDIV`, `MODK`, and `IDIVK` now have primitive integer paths instead of fail-loud `ERR_ARITH`.
   - `value_raw_equal`, `<`, and `<=` now support exact int/float numeric comparison.
   - Inline `EQ`/`LT` paths now handle mixed int/float cases.
   - Corrected K-op dispatch metadata/argument passing for `*K` arithmetic and `MMBINK` to use Lua 5.5 `ABC` fields.

## Files Changed

- `experiments/lua_interpreter_vm/src/regions_call.lua`
  - Native OK return routes through `resume_after_return`.
- `experiments/lua_interpreter_vm/src/vm_loop.lua`
  - Native return resumes the current frame and reloads frame caches.
- `experiments/lua_interpreter_vm/src/opcodes.lua`
  - Mixed numeric inline arithmetic/comparison.
  - Corrected `*K`/`MMBINK` dispatch argument modes.
- `experiments/lua_interpreter_vm/src/op/arithmetic.lua`
  - Implemented integer `MOD/IDIV/MODK/IDIVK`.
  - Expanded division primitive paths.
- `experiments/lua_interpreter_vm/src/regions_value.lua`
  - Mixed int/float equality and ordering.
- `experiments/lua_interpreter_vm/tests/test_vm_native_return_convergence.lua`
  - New end-to-end native success/resume test.
- `experiments/lua_interpreter_vm/tests/test_vm_opcode_semantics.lua`
  - Added numeric primitive behavior coverage.

## Tests Run

Passed:

```sh
luajit experiments/lua_interpreter_vm/tests/test_vm_opcode_semantics.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_native_return_convergence.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_smoke.lua
luajit experiments/lua_interpreter_vm/tests/test_parser_compile.lua
for t in experiments/lua_interpreter_vm/tests/test_vm*.lua; do luajit "$t"; done
```

Final combined VM slice:

```sh
parser + VM slice passed
```

## Remains

- Native `YIELD` and `REENTER_LUA` still need full VM transfer semantics.
- `pcall/xpcall`, protected unwind, and value-preserving error routing remain incomplete.
- Numeric semantics still need full oracle coverage for negative floor division/modulo, float modulo/idiv, power, string-to-number coercion, and metamethod fallbacks.
- Closures/upvalues/varargs, binary chunks, full source grammar/codegen, GC/weak/finalizer semantics, and table rehash/key canonicalization remain open.

## Worker Output — 2026-05-30 11:39:52

## Completed

Implemented a connected table-semantics push:

- Added `regions_key.lua` as the explicit table-key protocol boundary:
  - canonical table-key hash
  - canonical table-key equality
  - integral float keys compare/hash like integer keys
  - nil and NaN are invalid set keys
  - shared node-key helpers for raw lookup, update, iteration, and rehash

- Reworked table raw access:
  - `table_raw_get` now hashes to the canonical bucket instead of scanning all buckets.
  - `table_raw_get` and `table_raw_set` now use the same key equality semantics.
  - integer key `42` and float key `42.0` address the same table entry.
  - setting a hash entry to nil deletes it and updates `node_count`.

- Reworked table growth/resize:
  - `table_resize` now preserves and rehashes existing hash entries.
  - resize can move integral numeric hash keys into the array part.
  - `table_grow_for_key` chooses capacity from existing hash load instead of resetting to a fixed small hash size.
  - array growth for integer keys is explicit and tested.

- Improved table metamethod behavior:
  - `table_get` now follows table-valued `__index` chains.
  - `table_set` now follows Lua’s absent-key `__newindex` behavior:
    - existing raw key updates directly
    - absent key checks `__newindex`
    - table-valued `__newindex` chains
    - callable/non-table `__newindex` exits through `call_mm`
  - Loop guard is explicit (`depth >= 200` → `loop_error`).

## Files Changed

- `experiments/lua_interpreter_vm/src/init.lua`
  - loads `regions_key`.

- `experiments/lua_interpreter_vm/src/regions_key.lua`
  - new explicit key hash/equality/index protocol regions.

- `experiments/lua_interpreter_vm/src/regions_table.lua`
  - canonical raw get/set, deletion, resize rehash, growth, `__index`/`__newindex` chaining.

- `experiments/lua_interpreter_vm/tests/test_vm_table_protocols.lua`
  - added coverage for canonical int/float keys, hash deletion, resize rehash, array migration, grow+store, table-valued `__index`, table-valued `__newindex`.

## Tests Run

```sh
luajit experiments/lua_interpreter_vm/tests/test_vm_table_protocols.lua
luajit experiments/lua_interpreter_vm/tests/test_parser_compile.lua
for t in experiments/lua_interpreter_vm/tests/test_vm*.lua; do luajit "$t"; done
```

Observed:

```text
test_vm_table_protocols.lua: 17/17 passed
parser + VM slice passed
```

## Remaining Blockers / Open Semantics

- Callable metamethod invocation paths still need completion for arithmetic/comparison/table/call operators.
- Protected call/value-carrying error unwind and TBC close semantics remain incomplete.
- Closures/upvalues/varargs remain incomplete.
- Binary chunk loading remains an explicit rejection boundary.
- GC weak/finalizer behavior remains skeletal.
- Native yield/reenter-Lua transfer remains incomplete.

SponJIT remains separate; no SponJIT dependency was added.

## Worker Output — 2026-05-30 11:53:36

## Completed

Implemented closure/upvalue runtime semantics end-to-end:

- `OP_CLOSURE` now allocates a real `LClosure` for child protos.
- `make_lclosure` now captures upvalues from:
  - current stack slots (`instack != 0`) via open upvalues
  - parent closure upvalues (`instack == 0`) by sharing the same `UpVal`
- `find_upvalue` now creates and links open upvalues in descending stack-index order.
- `close_upvalues` is now exercised by returns; return paths close open upvalues for the returning frame.
- Closed upvalues now survive after their defining frame is gone.
- Fixed `LClosure` allocation size from `40` to `48` bytes to match the Lalin/C-compatible layout and prevent memory corruption.

## Files Changed

- `experiments/lua_interpreter_vm/src/regions_upvalue.lua`
  - implemented open-upvalue allocation/linking
  - implemented closure allocation and upvalue descriptor capture
- `experiments/lua_interpreter_vm/src/op/closure.lua`
  - implemented `OP_CLOSURE`
- `experiments/lua_interpreter_vm/src/op/call.lua`
  - return paths now close frame upvalues before returning
- `experiments/lua_interpreter_vm/src/regions_allocator.lua`
  - corrected `SIZE_LCLOSURE` to `48`
- `experiments/lua_interpreter_vm/tests/test_vm_closure_upvalue_semantics.lua`
  - new semantic coverage for open capture and closed-upvalue survival

## Tests Run

```sh
luajit experiments/lua_interpreter_vm/tests/test_vm_closure_upvalue_semantics.lua
luajit experiments/lua_interpreter_vm/tests/test_parser_compile.lua
for t in experiments/lua_interpreter_vm/tests/test_vm*.lua; do luajit "$t"; done
```

Observed:

```text
test_vm_closure_upvalue_semantics.lua: 2/2 passed
parser + VM slice passed
```

## Remaining Blockers

- `OP_VARARG` / `OP_GETVARG` / `VARARGPREP` remain incomplete.
- Callable metamethod fallback still needs full call setup for arithmetic/comparison/table/call.
- Protected calls and value-carrying unwind remain incomplete.
- Binary chunk loading remains an explicit rejection boundary.
- GC/weak/finalizer execution remains skeletal.
- Native yield/reenter-Lua transfer remains incomplete.

SponJIT remains separate; no SponJIT dependency was added.

## Worker Output — 2026-05-30 12:28:44

## Completed

Implemented several connected runtime semantics beyond the prior closure/upvalue chunk:

- **Varargs**
  - `adjust_varargs` no longer fails with OOM; it preserves the incoming argument window and pads missing fixed params with nil.
  - `OP_VARARG` now copies actual varargs from after fixed parameters.
  - `OP_VARARG C=0` sets the open top for all available varargs.
  - `VARARGPREP` remains explicit no-hidden-state because varargs live in the frame argument window.

- **Callable `__call` metamethod**
  - `prepare_call` now handles non-function values by looking up `TM_CALL`.
  - When `__call` exists, the VM shifts the original callee into arg1, installs the metamethod at `func_slot`, and dispatches through the normal Lua/native call path.
  - This works end-to-end for table values with a Lua closure `__call`.

- **Length operator**
  - `OP_LEN` now implements primitive string length.
  - `OP_LEN` implements simple raw table array length scan.
  - `OP_LEN` can route through `TM_LEN` using explicit `ResumeState.LEN_MM`.
  - `resume_after_return` now handles `LEN_MM` result writeback.

- **Metamethod resume correctness**
  - `resume_after_return` now writes `parent.pc` for direct metamethod resume cases (`get/set table`, binop/unop/len/compare/concat/tfor/tbc), so resumed frames carry explicit continuation PC state.

## Files Changed

- `experiments/lua_interpreter_vm/src/regions_stack.lua`
  - implemented vararg frame-window handling.
- `experiments/lua_interpreter_vm/src/op/closure.lua`
  - implemented `OP_VARARG`; documented no-hidden-state `VARARGPREP`.
- `experiments/lua_interpreter_vm/src/regions_call.lua`
  - implemented table/non-function `__call` lookup, stack shifting, and redispatch through normal call protocol.
- `experiments/lua_interpreter_vm/src/op/misc.lua`
  - implemented `OP_LEN` primitive string/table behavior and `TM_LEN` call setup.
- `experiments/lua_interpreter_vm/src/regions_resume.lua`
  - added `LEN_MM` writeback and parent PC updates for metamethod resumes.
- `experiments/lua_interpreter_vm/tests/test_vm_closure_upvalue_semantics.lua`
  - added vararg and `__call` end-to-end VM tests.
- `experiments/lua_interpreter_vm/tests/test_vm_opcode_semantics.lua`
  - added string `LEN` opcode coverage.

## Tests Run

```sh
luajit experiments/lua_interpreter_vm/tests/test_vm_closure_upvalue_semantics.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_opcode_semantics.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_smoke.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_resume_protocol_contract.lua
luajit experiments/lua_interpreter_vm/tests/test_parser_compile.lua
for t in experiments/lua_interpreter_vm/tests/test_vm*.lua; do luajit "$t"; done
```

Observed final VM slice:

```text
parser + VM slice passed
```

## Remaining Blockers

- `OP_GETVARG` and vararg table mode are still incomplete.
- Arithmetic/comparison callable metamethod fallback (`MMBIN*`, compare MM) remains incomplete.
- Protected call/value-carrying unwind and TBC close calls remain incomplete.
- Native yield/reenter-Lua, binary chunks, and GC weak/finalizer execution remain open.
- SponJIT remains separate; no SponJIT dependency was added.
