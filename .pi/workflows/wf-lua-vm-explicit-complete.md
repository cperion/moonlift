# Complete Lua 5.5 VM idiomatically in Lalin
Fresh PLANSEARCH workflow. Goal: complete the Lalin-native Lua 5.5 VM according to explicit_programming.md. Vendored latest Lua 5.5 is semantic/bytecode oracle only; PUC architecture must not be ported. SponJIT remains separate.
**Workflow ID**: wf-lua-vm-explicit-complete
**Started**: 2026-05-29 23:29:38
---

## Scout Output — 2026-05-29 23:35:11

## Files Retrieved

1. `explicit_programming.md` (lines 1-3710) — Governing design philosophy: dual data/control tree, continuation protocols, explicit state, emit/forward composition, metaprogramming, anti-patterns.
2. `LANGUAGE_REFERENCE.md` (lines 53-222, 471-730, 777-966, 1526-2115, 2533-3132, 3305-3414, 3721-3738) — Lalin language rules, type system, hosted declarations/externs, regions, continuation forwarding, splicing, metaprogramming, ABI/memory boundaries.
3. `experiments/lua_interpreter_vm/README.md` (lines 1-92) — Status map: interpreter VM separate from SpongeJIT; current test commands; non-goals.
4. `experiments/lua_interpreter_vm/VM_CONTRACT.md` (lines 1-78) — ABI/semantic contract and SponJIT gate conditions.
5. `experiments/lua_interpreter_vm/src/constants.lua` (lines 1-191) — Lua 5.5-ish tags, opcodes 0-84, metamethods, resume modes, status/error codes, GC states, ABI versions.
6. `experiments/lua_interpreter_vm/src/products.lua` (lines 1-117) — Runtime data tree: `Value`, `Proto`, `Frame`, `LuaThread`, `GlobalState`, tables, closures, userdata, native descriptors.
7. `experiments/lua_interpreter_vm/src/init.lua` (lines 1-34) — Module graph loader.
8. `experiments/lua_interpreter_vm/src/contract.lua` (lines 1-15) — Machine-readable SponJIT gate.
9. `experiments/lua_interpreter_vm/src/vm_loop.lua` (lines 1-167) — Main interpreter loop, frame-cache reload behavior, `vm_resume`, dispatch composition.
10. `experiments/lua_interpreter_vm/src/opcodes.lua` (lines 1-724) — Opcode decoder/dispatcher generation, switch arms, inline hot arms, handler emit templates, opcode metadata.
11. `experiments/lua_interpreter_vm/src/op/_init.lua` (lines 1-157) — Shared opcode handler header and continuation-protocol string templates.
12. `experiments/lua_interpreter_vm/src/op/arithmetic.lua` (lines 1-474) — Arithmetic/bitwise/unary/MMBIN opcode handlers and several explicit stubs.
13. `experiments/lua_interpreter_vm/src/op/table.lua` (lines 1-261) — Table op handlers, metamethod call setup blocks, `NEWTABLE`/`SETLIST` stubs.
14. `experiments/lua_interpreter_vm/src/op/call.lua` (lines 1-263) — CALL/TAILCALL/RETURN opcode handlers and explicit result-base behavior.
15. `experiments/lua_interpreter_vm/src/op/loop.lua` (lines 1-112) — Numeric and generic loop opcode handlers.
16. `experiments/lua_interpreter_vm/src/op/compare.lua` (lines 1-229) — EQ/LT/LE/immediate comparisons/TEST handlers.
17. `experiments/lua_interpreter_vm/src/op/misc.lua` (lines 1-84) — LEN/CONCAT/CLOSE/TBC/JMP/ERRNNIL handlers; LEN/CONCAT stubs.
18. `experiments/lua_interpreter_vm/src/op/closure.lua` (lines 1-48) — Closure/vararg handlers; mostly fail-loud stubs.
19. `experiments/lua_interpreter_vm/src/regions_value.lua` (lines 1-260) — Value protocol regions: truth, type splits, equality/comparison, RK resolution.
20. `experiments/lua_interpreter_vm/src/regions_table.lua` (lines 1-223) — Raw table get/set, table get/set with metamethod continuations, iterator/resize stubs.
21. `experiments/lua_interpreter_vm/src/regions_call.lua` (lines 1-363) — Call dispatcher, native ABI fail-loud path, return-mode state machine.
22. `experiments/lua_interpreter_vm/src/regions_error.lua` (lines 1-237) — Error object, protected unwind, TBC close chain, protected-call stubs.
23. `experiments/lua_interpreter_vm/src/regions_stack.lua` (lines 1-132) — Stack check, frame push/pop, result adjustment, vararg reshaping stub.
24. `experiments/lua_interpreter_vm/src/regions_gc.lua` (lines 1-170) — Allocator/GC protocol regions, mark/barrier skeleton.
25. `experiments/lua_interpreter_vm/src/regions_coroutine.lua` (lines 1-70) — Coroutine resume/yield protocol regions.
26. `experiments/lua_interpreter_vm/src/regions_metamethod.lua` (lines 1-149) — Metamethod lookup and dispatch helpers.
27. `experiments/lua_interpreter_vm/src/regions_string.lua` (lines 1-58) — String hash, interning stub, concat stub.
28. `experiments/lua_interpreter_vm/src/regions_upvalue.lua` (lines 1-60) — Upvalue scan/close, allocation stubs.
29. `experiments/lua_interpreter_vm/src/regions_api.lua` (lines 1-40) and `src/api.lua` (lines 1-164) — Internal API index decode and sealed C-compatible API functions.
30. `experiments/lua_interpreter_vm/src/validate.lua` (lines 1-184) — Bytecode validator trust-boundary region.
31. `experiments/lua_interpreter_vm/src/parser_constants.lua` (lines 1-70), `parser_products.lua` (lines 1-55), `regions_lexer.lua` (lines 1-277), `regions_parser.lua` (lines 1-556), `regions_codegen.lua` (lines 1-377), `regions_compiler.lua` (lines 1-84) — First source→Proto compiler slice.
32. `experiments/lua_interpreter_vm/tests/*.lua` key files:
   - `test_vm_smoke.lua` (lines 1-134)
   - `test_vm_opcode_semantics.lua` (lines 1-289)
   - `test_vm_e2e.lua` (lines 1-221)
   - `test_vm_validation_contract.lua` (lines 1-119)
   - `test_vm_call_frame_contract.lua` (lines 1-136)
   - `test_vm_error_contract.lua` (lines 1-100)
   - `test_vm_abi_contract.lua` (lines 1-57)
   - `test_parser_compile.lua` (lines 1-251)
33. `.vendor/Lua/lua.h` (lines 16-30) — Vendored Lua reports 5.5.0.
34. `.vendor/Lua/lopcodes.h` (lines 1-115, 228-440) — Lua 5.5 instruction bit layout, opcode list, opcode notes.
35. `.vendor/Lua/lvm.c` (lines 123-172, 585-754) — Semantic oracle facts for numeric conversion, equality, concatenation, length.
36. `.vendor/Lua/ltm.c` (lines 35-94) — Lua 5.5 metamethod names and lookup.
37. `.vendor/Lua/lobject.h` (lines 430-549) — Userdata/lightuserdata representation facts.
38. `.vendor/Lua/lstate.h` (lines 260-410) — Lua thread/global-state facts including weak/finalizer lists.
39. `.vendor/Lua/lgc.c` (lines 216-240, 592-626, 968-1092, 1544-1583) — Weak table clearing and finalizer semantic oracle facts.
40. `.vendor/Lua/lapi.c` (lines 972-996) — Metatable setting invokes barrier/finalizer check.
41. `experiments/lua_interpreter_vm/spongejit/puc/README.md` (lines 1-8) — No maintained PUC executable integration.
42. `experiments/lua_interpreter_vm/SPONJIT_ARCHITECTURE.md` (lines 1-220), `SPONJIT_FOUNDRY_SSA.md` (lines 1-220), `SPONJIT_RUNTIME_DESIGN.md` (lines 1-200), `SPONJIT_COPY_LINK_PATCH.md` (lines 1-200) — SponJIT status/separation and native-fragment ABI direction.

## Key Code

### Explicit-programming rules that govern this VM work

`explicit_programming.md` establishes:

```lalin
region authenticate(
    creds: ptr(Credentials),
    store: ptr(SessionStore);

    success:             cont(user_id: u64, session_token: ptr(u8)),
    invalid_credentials: cont(),
    account_locked:      cont(unlock_at: i64),
    requires_2fa:        cont(challenge_id: u64),
    rate_limited:        cont(retry_after_seconds: i32))
```

Key doctrine from the read:
- data tree = structs/unions/aliases;
- control tree = regions/continuations/blocks/jumps;
- “compose with regions, seal with functions”;
- emit is structural splice, not call;
- forward continuations directly where possible;
- hidden state, stringly exits, boolean returns, and premature functions are anti-patterns.

`LANGUAGE_REFERENCE.md` reinforces:
- Lalin object code is monomorphic;
- no source generics;
- `emit` splices regions;
- every block path terminates explicitly;
- externs are typed declarations;
- Lua metaprogramming builds typed Lalin values, not runtime strings.

### VM contract

`experiments/lua_interpreter_vm/VM_CONTRACT.md`:

```text
- The VM targets Lua 5.5 semantics in Lalin-native data/control structures.
- PUC Lua is a semantic reference only. PUC layouts, longjmp, C-stack behavior,
  allocator conventions, and internal bytecode/runtime shapes MUST NOT be treated
  as implementation dependencies.
```

SponJIT gate from `src/contract.lua`:

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

### Current VM data tree

`src/products.lua` defines canonical runtime products. Critical structs:

```lua
local Value = host.struct [[struct Value tag: u32; aux: u32; bits: u64 end]]

local Proto = host.struct [[struct Proto gc: GCHeader; code: ptr(Instr);
  code_len: index; constants: ptr(Value); constants_len: index;
  children: ptr(ptr(Proto)); children_len: index; ... numparams: u8;
  flag: u8; maxstack: u16 end]]

local Frame = host.struct [[struct Frame closure: Value; base: index; top: index;
  pc: index; wanted: i32; tailcalls: i32; resume_mode: u16;
  resume_a: u16; resume_b: u16; resume_c: u16; resume_pc: index;
  resume_base: index; resume_value: Value; result_base: index;
  call_top: index; yieldable: u8; flags: u8; reserved: u16 end]]

local LuaThread = host.struct [[struct LuaThread gc: GCHeader; status: u8;
  stack: ptr(Value); stack_size: index; top: index; frames: ptr(Frame);
  frame_count: index; frame_cap: index; open_upvals: ptr(UpVal);
  protected_top: ptr(ProtectedFrame); global: ptr(GlobalState);
  err_value: Value; ... tbc_head: index; yieldable: i32;
  nonyieldable: i32; last_error_code: i32; flags: u32 end]]
```

Runtime includes `UserData`, `NativeFunc`, `NativeCallResult`, `Allocator`, `ProtectedFrame`, `StringTable`, `GlobalState`.

### Current VM control tree

`vm_loop.lua` root regions:

```lalin
region vm_resume(L: ptr(LuaThread), nargs: i32;
                 ok: cont(nres: i32),
                 yielded: cont(nres: i32),
                 runtime_error: cont(code: i32),
                 oom: cont())
```

```lalin
region vm_loop(L: ptr(LuaThread);
               finished: cont(nres: i32),
               yielded: cont(nres: i32),
               error: cont(code: i32),
               oom: cont())
```

`dispatch_instruction` has 9 explicit exits:

```lalin
next(...)
do_jump(...)
resume_parent(...)
enter_lua(child: ptr(Frame))
enter_native(cl: ptr(CClosure), func_slot: index, nargs: i32,
             wanted: i32, result_base: index, resume_mode: u16)
returned(nres: i32)
yielded(nres: i32)
error(code: i32)
oom()
```

This is an idiomatic control protocol for interpreter outcomes.

### Frame-cache reload fact

`vm_loop.lua` explicitly reloads `code`/`constants` when switching frame:

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

Test coverage: `tests/test_vm_call_frame_contract.lua` verifies child return does not reuse child constants and result lands at explicit `result_base`.

### Explicit native boundary is present but not implemented

`regions_call.lua`:

```lalin
region call_native(...;
                   returned: cont(nres: i32),
                   yielded: cont(nres: i32),
                   error: cont(code: i32),
                   oom: cont())
entry start()
    if cl == nil then ... jump error(code = @{ERR_CALL}) end
    if cl.fn == nil then ... jump error(code = @{ERR_CALL}) end
    if cl.fn.abi_version ~= @{ABI_NATIVE_VERSION} then ... end
    L.last_error_code = @{ERR_CALL}
    jump error(code = @{ERR_CALL})
end
```

So normal/error/yield/OOM exits are typed, but invocation always fails loudly.

### Allocator/GC boundary is explicit but skeletal

`regions_gc.lua`:

```lalin
region alloc_object(G: ptr(GlobalState), size: index, tt: u8;
                    ok: cont(obj: ptr(GCHeader)),
                    step_required: cont(),
                    oom: cont())
entry start()
    if G == nil then jump oom() end
    if G.allocator == nil then jump oom() end
    if G.totalbytes > G.threshold then jump step_required() end
    jump oom()
end
```

GC regions include `gc_check`, `gc_step`, `mark_value`, `mark_object`, `propagate_gray`, `sweep_step`, `write_barrier`, but many are no-op/skeleton.

### Parser/compiler slice

`regions_compiler.lua` exposes:

```lalin
region compile_lua_source_into(...;
    ok: cont(proto: ptr(Proto)),
    syntax_error: cont(err: CompileError),
    semantic_error: cont(err: CompileError),
    limit_error: cont(err: CompileError),
    oom: cont())
```

Current parser supports a first slice:
- lexer: comments, names, ints, quoted strings, selected operators;
- parser: `return`, `local name = expr`, integer/boolean/nil/name primaries, `+ - * /`;
- codegen: `LOADI`, boolean/nil loads, `ADD/SUB/MUL/DIV + MMBIN`, `RETURN1`.

Tests verify examples like:
```lua
run_case("return 1 + 2", { LOADI, LOADI, ADD, MMBIN, RETURN1 }, 3)
run_case("local x = 41 return x + 1", ..., 42)
```

## Relationships

### Data/control flow

1. `src/init.lua` loads constants/products/regions/opcode handlers/compiler.
2. `vm_resume` sets thread status and emits `vm_loop`.
3. `vm_loop` reads top `Frame`, caches `code` and `constants`, and jumps to `loop`.
4. `loop` emits `dispatch_instruction`.
5. `dispatch_instruction` decodes a 32-bit `Instr.word`, switches on opcode, then:
   - inlines hot arms, or
   - emits typed opcode handler regions.
6. Opcode handlers either:
   - mutate stack/frame and jump `next` / `do_jump`;
   - emit runtime subregions (`table_get`, `prepare_call`, `return_from_lua`, etc.);
   - jump `enter_lua`, `enter_native`, `returned`, `yielded`, `error`, `oom`.
7. Errors flow through `raise_code_error` → `build_error_object` → `raise_error` → protected unwind or outer `error`.
8. Calls flow through `prepare_call` → frame push / native boundary → `vm_loop` frame switch.
9. Returns flow through `return_from_lua` → `handle_return_mode` → parent frame resume.
10. GC/allocation paths currently terminate as `step_required`/`oom` or skeleton done paths.

### SponJIT relationship

- `README.md` and all SponJIT docs state `src/` VM is not JIT-integrated.
- `contract.lua` sets `sponjit_allowed = false`.
- `VM_CONTRACT.md` says SponJIT cannot consume VM scaffolding until validator/frame-cache/result-base/error/native/allocator gates are tested.
- SpongeJIT current path is offline metadata:
  ```text
  opcode sequence + facts → semantic SSA → Stencil IR → abstract native-fragment descriptors
  ```
- `spongejit/puc/README.md` says no maintained executable PUC integration exists.

## Observations

### Explicit / idiomatic Lalin facts

- The VM has a visible data tree in `products.lua` and `parser_products.lua`.
- The VM has a large visible control tree: 100+ region fragments according to `test_vm_smoke.lua`.
- Major outcomes are typed continuations: VM completion/yield/error/OOM, dispatch `enter_lua`/`enter_native`, table `value/call_mm/type_error/loop_error/oom`, allocator `ok/step_required/oom`.
- `dispatch_instruction` is grep-shaped: one switch over opcode, every arm explicitly jumps/emits.
- Frame-cache reload and call result-base were made explicit and have dedicated tests.
- Native calls and allocation fail loudly rather than hiding libc/PUC conventions.

### Implicit or less-explicit current shapes

- `Value` is a manual `tag/aux/bits` product, not a Lalin union. This is probably a runtime-language necessity, but the discriminant is integer-tagged.
- Opcode handler protocols in `op/_init.lua` are string fragments (`TABLE_CONTS`, `CALL_CONTS`, etc.) concatenated into Lalin source. This is boilerplate generation, but it is less ASDL-shaped than table-builder continuation descriptors.
- Many opcode modules still concatenate `region op_name(` .. `H` .. `;` .. cont string, even though `op_factory.lua` says old string substitution violated type-first rules.
- Metamethod/event identities are raw integer constants and strings in `tmname`; no typed enum/union surface.
- `Table.flags` comment says metamethod flags cache, but `get_table_metamethod` does not use `flags`.

### Runtime/semantic gaps visible in code

- Allocation/growth:
  - `alloc_object` always `oom` after version/threshold checks.
  - `stack_check` cannot grow; overflow on needed growth.
  - `frame_push` cannot grow frame array.
  - `string_intern`, `table_resize`, `make_lclosure`, `find_upvalue.make_new` fail as `oom`.
- GC:
  - `gc_step`, `propagate_gray`, `sweep_step`, `write_barrier_back` are no-op/skeletons.
  - No weak table clearing implementation.
  - No finalizer queue/run machinery.
- Tables:
  - `table_raw_get` scans all nodes rather than hashing bucket from key.
  - `table_raw_set` can update existing nodes/array slots but cannot insert/resize.
  - `table_set` maps missing `__newindex` and resize-needed cases to `oom`.
  - `table_next` always `done`.
  - `NEWTABLE` and `SETLIST` opcode handlers jump `oom`.
- Metamethods:
  - `MMBIN/MMBINI/MMBINK` all `ERR_RUNTIME`.
  - comparison metamethod continuations exist but handlers often convert them to `ERR_COMPARE`.
  - `__call` lookup `try_call_metamethod` always `not_callable`.
  - `__len`, `__concat`, `__close` dynamic call paths fail.
- Arithmetic/numbers:
  - `MOD`, `IDIV`, `POW` and `*K` variants are stubs.
  - mixed integer/float equality is not implemented in `value_raw_equal`; vendored `lvm.c` permits exact int/float equality.
  - mixed int/float arithmetic and string-to-number coercion are absent.
  - signed `sC` immediates appear decoded as raw `C` in current handlers; vendored `lopcodes.h` defines `sC = C - 127`.
- Bytecode encoding:
  - vendored Lua 5.5 has `OP_JMP` as `isJ` with 25-bit signed `sJ`; current code treats jumps as 17-bit `sBx`.
  - vendored Lua 5.5 has `FORLOOP/FORPREP` using `Bx` semantics; current handlers use `sbx`.
  - `NEWTABLE`/`SETLIST` use `vB/vC` and optional `EXTRAARG`; current decoder mostly uses 8-bit `B/C`.
- Calls/returns:
  - native call ABI exists but fails.
  - protected frames allocation not implemented; `enter_protected` jumps `oom`.
  - `protected_call` immediately returns failure.
  - vararg reshaping rejected as `oom`; `VARARG`/`GETVARG` stubs; `VARARGPREP` just advances.
  - closure creation stub.
- Coroutines/yield:
  - `coroutine_resume` encodes state distinctions but does not re-enter `vm_loop`; yielded target returns `yielded(nres=0)`.
  - `coroutine_yield` checks `nonyieldable`, sets status, and exits; saved continuation state is incomplete in current code.
- Parser/source compatibility:
  - parser is only a first slice; no functions, tables, strings as expressions, floats, loops, if/while/for, calls, varargs, closures, labels/goto, full precedence, long strings/comments, escapes, etc.
  - bytecode loader/dumper compatibility is not visible in current `src/`; tests construct `Proto` manually or compile toy source.

### Weak tables/finalizers/userdata facts

Current Lalin VM:
- `constants.lua` includes `TM.GC`, `TM.MODE`, and `GCState.FINALIZE`.
- `products.lua` has `UserData gc/metatable/env/len/data`.
- `GlobalState` has `weak` and `tmudata` fields but not the full vendored set (`ephemeron`, `allweak`, `finobj`, `tobefnz`, etc.).
- No implemented region uses `TM_GC` for finalization.
- No implemented region parses `__mode` or clears weak keys/values.
- `tbc_close_chain` handles to-be-closed variables but `__close` invocation fails loudly.

Vendored Lua oracle facts:
- `ltm.c` event names include `__gc`, `__mode`, `__close`.
- `lgc.c` says weak table mode is derived from `__mode` string: weak values bit 1, weak keys bit 2.
- `lgc.c` treats strings as values never removed from weak tables.
- `lgc.c` finalization moves objects from `finobj` to `tobefnz` and runs `TM_GC`.
- `lapi.c` setting table/userdata metatable calls barrier and finalizer check.
- `lobject.h` distinguishes light userdata and full userdata; full userdata has length, metatable, user values, and aligned memory payload.

### FFI/native/host ABI facts

- `NativeFunc` carries `abi_version`, `flags`, raw `addr`, `name`.
- `NativeCallResult` carries `status`, `nresults`, `err`, `continuation`.
- `NativeResult` constants include `OK`, `ERROR`, `YIELD`, `OOM`, `STACK_GROW`.
- `call_native` exposes typed continuations but does not call `addr`.
- `api.lua` sealed C-compatible API functions are `func`s, not regions. Full operations that may allocate/call/yield (`lua_gettable_api`, `lua_settable_api`, `lua_call_api`, `lua_pcall_api`) currently mark runtime error/fail loudly.
- Tests use LuaJIT FFI and `lalin_scratch_raw` to construct structs. `VM_CONTRACT.md` explicitly says scratch-memory FFI tests are fixtures, not stable host ABI.

### Tests/conformance gaps

Existing tests cover:
- module load, region/struct count, key region compile (`test_vm_smoke.lua`);
- toy component compilation (`test_vm_components.lua`);
- focused opcode semantics: `LOADNIL`, `LOADKX`, `ADDI`, `ADDK`, `ADD` f64 bitcast, inline scalar ops, EQ/LT, `RETURN1`;
- validator contract for opcode range, A bounds, constant bounds, `LOADKX/EXTRAARG`, MMBIN adjacency, jump range, CALL window, CLOSURE child bounds;
- frame-cache/result-base contract;
- explicit error state;
- ABI version accessors;
- toy parser/compiler slice.

Observed test gaps:
- No full Lua 5.5 conformance suite integration.
- No weak table/finalizer/userdata tests.
- No allocator/GC progression tests.
- No native call/yield/protected-call success tests.
- No parser coverage beyond a tiny expression/local/return subset.
- `test_vm_e2e.mlua` contains placeholder bundle code returning `0`.
- Several tests duplicate C layouts through FFI; some comments are stale (for example `test_vm_e2e.lua` comment says `Instr` is 20 bytes, while current `Instr` product is one `u32` word).

### Vendored Lua 5.5 oracle facts

- `.vendor/Lua/lua.h` reports Lua 5.5.0.
- `.vendor/Lua/lopcodes.h` defines 85 opcodes (`OP_MOVE` through `OP_EXTRAARG`) and 32-bit instruction formats:
  - opcode = first 7 bits;
  - `A` = 8 bits;
  - `B/C` = 8 bits;
  - `vB/vC` = 6/10 bits;
  - `Bx/sBx` = 17 bits;
  - `Ax/sJ` = 25 bits;
  - `sC` offset = 127.
- Opcode notes include:
  - `MMBIN*` follows arithmetic/bitwise op and is skipped on primitive success;
  - `LOADKX` and `NEWTABLE` always followed by `EXTRAARG`;
  - `SETLIST` and `NEWTABLE` use `EXTRAARG` when `k`;
  - comparisons/tests assume skipped instruction is a jump;
  - return/tailcall `k` and `C` carry close/hidden-vararg meanings.
- These are semantic/bytecode oracle facts only; contract forbids porting PUC architecture/layout/control behavior.

### SponJIT separation facts

- `README.md`: interpreter in `src/` is not wired to a JIT.
- `SPONJIT_RUNTIME_DESIGN.md`: runtime selects/copies/patches from an offline bank; it does not compile or optimize.
- `SPONJIT_FOUNDRY_SSA.md`: SSA is offline fact-consuming layer; runtime never sees SSA.
- `SPONJIT_COPY_LINK_PATCH.md`: C-function-shaped stencils are old artifacts; native fragments need explicit endpoints/control relocations/projections.
- `spongejit/puc/README.md`: no maintained executable PUC integration exists.
- VM contract gates SponJIT until core VM invariants are complete and tested.

## Knowledge-builder Output — 2026-05-29 23:53:24

### What Matters Most for This Problem

- **Dual-tree completeness**: completion means every Lua 5.5 semantic distinction must appear either as typed data (`Value`, `Frame`, `Proto`, GC objects, ABI records) or typed control (`ok/error/oom/yield/metamethod/finalizer/...` continuations), not as comments, magic integers, stale flags, or side effects.
- **Trust-boundary fidelity**: bytecode decoding and `validate_proto` must exactly cover the assumptions used by dispatch and handlers before opcode semantics can be trusted.
- **Semantic vs architectural oracle separation**: vendored Lua can define opcode meanings, numeric rules, weak/finalizer behavior, etc.; it must not define Lalin layouts, control flow, allocator conventions, C-stack behavior, or longjmp semantics.
- **Allocation/GC as VM semantics**: allocator, stack growth, table growth, string interning, closure/upvalue creation, protected frames, weak clearing, and finalizers are not infrastructure details; they are observable Lua behavior.
- **Metamethod/protected/yield sequencing**: many incomplete areas share the same continuation machinery. `__index`, `__newindex`, arithmetic fallback, `__call`, `__close`, `__gc`, native calls, pcall, and coroutine yield all stress the same resume/error protocol.
- **Compatibility split**: source compatibility, internal `Proto` compatibility, PUC-like bytecode opcode compatibility, and native/FFI ABI compatibility are separate contracts and should not collapse into one vague “Lua compatibility” target.
- **Verification shape**: tests must verify typed protocols and semantic invariants, not just that stubs fail loudly or that scratch FFI layouts happen to match current structs.

### Non-Obvious Observations

- The VM already has an idiomatic outer control tree (`vm_resume`, `vm_loop`, `dispatch_instruction`, explicit call/return/error/yield exits), but many inner semantic distinctions are still encoded as **integer-mode state inside `Frame`** (`resume_mode`, `resume_a/b/c`, `last_error_code`). That is acceptable as suspended control data only if every stored mode has a precise control-tree counterpart when resumed. Otherwise the design degenerates into hidden “intly typed continuations.”

- Current fail-loud stubs are philosophically correct for scaffolding, but they create a future verification trap: `oom` currently means at least three different things — real allocation failure, missing allocator/growth implementation, and “semantic path not implemented.” Completion requires those meanings to stop sharing one continuation, or tests can accidentally bless wrong Lua behavior as memory pressure.

- The bytecode decoder is a root invariant, not a local utility. Existing mismatches with Lua 5.5 formats (`OP_JMP` `sJ`, `sC` immediates, `vB/vC`, `FORLOOP/FORPREP` `Bx`, `EXTRAARG` composition) mean opcode handlers and validator currently reason over a different bytecode language than the oracle. Any semantic work layered on top of that risks becoming correct for the wrong instruction set.

- `validate_proto` is named as the trust boundary, but its current checks are only a partial mirror of dispatch assumptions. In Lua 5.5, “next instruction must be jump,” “open top” producer/consumer behavior, `B == 0`/`C == 0`, hidden vararg fields, `RETURN/Tailcall k`, and `EXTRAARG` pair rules are semantic control constraints, not optional validation details.

- Source compatibility and binary compatibility have different failure modes. The toy compiler can generate internally consistent `Proto`s without proving Lua source compatibility; a bytecode loader can accept PUC-shaped chunks without proving source semantics. Completion has to keep those axes separate: source parser/codegen correctness, opcode-level execution correctness, and chunk-to-Lalin-`Proto` translation correctness.

- The current data tree intentionally avoids PUC layouts, but `Value tag/aux/bits`, `TM` integers, `Resume` integers, and `Err` integers are manual sum encodings. That is probably necessary at the VM/ABI level, but it weakens exhaustiveness. The compensating invariant must be that every consumer has explicit switch/continuation coverage and tests for unknown/default cases.

- Opcode handler metaprogramming is mixed. `opcodes.lua` moved toward typed `lalin.stmts`/spliced fragments, while `op/_init.lua` and several op modules still concatenate continuation signatures and shared block strings. That hides part of the control tree from the same structural inspection that explicit programming relies on; continuation protocol drift becomes easier than in first-class typed fragments.

- The call/return machinery has one of the strongest idiomatic cores: `result_base`, frame-cache reload, and child-owned return metadata are explicit and tested. This makes it a natural spine for completion, but also means every later feature — metamethod calls, native calls, pcall, coroutine resume/yield, finalizers — must preserve that exact ownership model.

- Native calls are not just “call function pointer later.” The contract already distinguishes `OK`, `ERROR`, `YIELD`, `OOM`, and `STACK_GROW`; each maps to VM control outcomes and frame/top/result-base state. If native invocation ever smuggles host exceptions, errno/null conventions, or hidden scheduler behavior across this boundary, it would violate both the VM contract and explicit-programming doctrine.

- The sealed C-compatible API functions are deliberately `func`s, not regions. That means any API operation that can allocate, call metamethods, yield, or raise protected errors cannot be honestly represented as the current simple C-style function result unless the boundary carries an explicit status/result protocol. The current fail-loud API functions are preserving that invariant by refusing to fake success.

- Weak tables and finalizers are a data-tree gap, not only a GC algorithm gap. Current `GlobalState` has `weak`/`tmudata`, but the oracle’s semantics imply distinct states/lists for weak values, weak keys/ephemerons, all-weak clearing, finalizable objects, pending finalizers, and finalizer-running restrictions. Without data nodes for those states, the control tree has nowhere explicit to route GC-phase outcomes.

- `__gc` is semantically tied to metatable assignment, not merely object death. Vendored Lua checks finalizer eligibility when a table/userdata metatable is set. Therefore finalization cannot be completed by only scanning dead userdata at sweep time; the moment an object becomes finalizable is observable through ordering, resurrection, and GC lifecycle behavior.

- Weak table behavior has subtle oracle-only exceptions that must not be lost in a generic “weak reference” abstraction: strings are never cleared as weak values; non-collectable values are never removed; finalizable objects have special retention behavior. These distinctions belong in explicit GC/table protocols, not comments inside sweeping code.

- Userdata compatibility is especially easy to get wrong because PUC’s `Udata` layout is both semantically informative and architecturally forbidden. The Lalin `UserData { metatable, env, len, data }` must define its own ownership/alignment/user-value/finalizer contract. Full userdata, light userdata, user values, payload alignment, and FFI access are separate semantic facts.

- Table flags are currently a hidden-implicitness risk. `Table.flags` comments mention metamethod cache, but lookup ignores it. Once used, it must be invalidated by metatable/table mutation and tied to `__mode`, `__gc`, `__index`, etc.; otherwise it becomes an invisible side channel that can silently contradict the data tree.

- Allocation sequencing dominates semantic completion. Tables cannot insert, strings cannot intern, closures/upvalues cannot allocate, stack/frame/protected-frame growth fails, and parser/codegen cannot produce general programs until allocator/GC outcomes are real. This is not merely implementation order; it determines which continuation protocols can be verified honestly.

- Protected error handling is only half-explicit today. `ProtectedFrame` replaces `setjmp`, and `raise_error` has typed caught/uncaught paths, but protected-frame allocation and `protected_call` success are absent. That means errors, `pcall`, `xpcall`, `__close`, `__gc`, native errors, and coroutine boundaries cannot yet be jointly verified.

- Coroutine/yield correctness depends on the same suspended-control representation as metamethods and native calls. A yielded Lua function, yielded native function, yielded metamethod, and yielded protected call all need enough saved data to resume at the right control-tree node. Current status fields alone are insufficient evidence of resumability.

- Arithmetic fast paths currently skip the following `MMBIN*` on primitive success, matching the bytecode idiom, but primitive failure often advances to a stub that raises generic runtime error. The hidden invariant is that every arithmetic opcode pair is a two-stage control protocol: primitive success skips, primitive failure transfers to the adjacent metamethod instruction with enough operand/event/flip metadata intact.

- Mixed numeric semantics are not optional edge cases. Lua 5.5 equality and arithmetic distinguish integer/float exactness, conversions, string-to-number coercions, division/mod/idiv/pow rules, and immediate signed operands. If these remain split across handlers ad hoc, tests may cover opcode names while missing the numeric lattice.

- SponJIT must remain a non-participant until the interpreter contract is semantically complete. Reserved `InlineCache`/`QuickInstr` fields and SponJIT fact schemas should not pressure interpreter shape prematurely; any optimization-oriented field that affects behavior before the contract is tested would become an implicit dependency.

- Scratch-memory FFI tests are useful fixtures but dangerous as compatibility evidence. They duplicate struct layouts and can accidentally freeze experimental internal shapes. For the final VM, the stable ABI is the explicit API/native contract, not LuaJIT FFI construction of `Frame`, `Proto`, or `Value` internals.

### Knowledge Gaps

- The exact intended meaning of “binary compatibility” is not fully established in the scout data: PUC binary chunk loading compatibility, opcode-stream compatibility after translation into Lalin `Proto`, or a Lalin-specific binary format with Lua 5.5 bytecode semantics.
- The desired FFI surface for userdata payload access and native functions is under-specified relative to `__gc`, user values, alignment, ownership, and yield/error behavior.
- The future test oracle boundary needs clarification: semantic differential tests against vendored Lua are appropriate, but tests must avoid depending on PUC internal layouts or execution architecture.

## Approach-proposer Output — 2026-05-29 23:54:59

### Approach A: Direct Contract-Completion of the Existing VM

- **Core idea**: Keep the current `src/` interpreter architecture and complete it in place, making the existing bytecode validator, dispatch loop, opcode handlers, allocator/GC, and call/error/yield protocols semantically complete.

- **Key changes**:
  - Fix Lua 5.5 bytecode decoding/validation in `opcodes.lua` and `validate.lua`: `sJ`, `sC`, `vB/vC`, `Bx`, `EXTRAARG`, comparison→jump adjacency, open-call/result rules.
  - Complete runtime services in `regions_gc.lua`, `regions_stack.lua`, `regions_table.lua`, `regions_string.lua`, `regions_upvalue.lua`, `regions_error.lua`, `regions_call.lua`, `regions_coroutine.lua`.
  - Fill all opcode stubs under `src/op/*.lua`.
  - Extend `products.lua` for missing GC/finalizer/weak-table/userdata state while preserving the current `Value`/`Proto`/`Frame` shape where possible.
  - Add source compiler expansion and binary chunk loader as producers of the existing `Proto`/`Instr` model.
  - Implement subset stdlib and LuaJIT-style FFI via explicit native descriptors/status records, not hidden C behavior.

- **Tradeoff**: Optimizes for incremental migration and continuity with the current tested VM spine; sacrifices an opportunity to deeply redesign int-encoded resume modes and string-template handler generation.

- **Risk**: Existing “fail loudly as `oom`” paths may be mistaken for real allocation failure unless every stub is audited and replaced with distinct semantic outcomes.

- **Done criteria**:
  - No remaining semantic stubs for Lua 5.5 core behavior; `oom` means real allocation failure only.
  - `validate_proto` exactly matches dispatch assumptions.
  - Source programs and accepted binary chunks both run through explicit `Proto` validation.
  - Weak tables, finalizers, userdata `__gc`, protected calls, coroutine yield/resume, native calls, and documented stdlib subset pass conformance tests.
  - SponJIT remains separate; interpreter gates may be satisfied without enabling JIT integration.

- **Rough sketch**:
  - First repair decoder/validator so execution targets the correct Lua 5.5 instruction language.
  - Complete allocation/growth/string/table/upvalue/frame/protected-frame primitives.
  - Implement opcode families against explicit numeric/table/metamethod/call regions.
  - Add GC/finalizer/weak-table state machines.
  - Expand parser/chunk loader and conformance tests feature by feature.

---

### Approach B: Explicit Product/Protocol Re-Foundation

- **Core idea**: Refactor the VM around first-class explicit semantic products and continuation protocols before filling behavior, so every Lua distinction is represented as typed data or typed control.

- **Key changes**:
  - Add explicit product/protocol modules for resumable VM states, numeric coercion outcomes, table access outcomes, GC phases, weak modes, finalizer eligibility, native call results, and protected-call states.
  - Replace loosely shared string fragments in `op/_init.lua` and opcode modules with named monomorphic Lua builders that emit typed Lalin fragments.
  - Convert `Frame.resume_mode/resume_a/b/c` into validated suspended-control records or decoded protocol states at every resume boundary.
  - Extend `GlobalState`, `Table`, `UserData`, and GC products for weak values, weak keys, ephemerons, finalizable lists, pending finalizers, finalizer-running state, userdata payload/user-values/alignment.
  - Make metamethod identity, table flags, weak-mode parsing, and native ABI statuses explicit validated encodings.
  - Rebuild opcode handlers as thin bridges into semantic protocols.

- **Tradeoff**: Optimizes for idiomatic Lalin, auditability, and long-term correctness; sacrifices short-term velocity because significant scaffolding must be reshaped before many features can be completed.

- **Risk**: The refoundation could over-abstract into a second compiler unless the generated axes remain named, monomorphic, and grep-visible.

- **Done criteria**:
  - Every persisted integer mode has a checked product/protocol decoder and exhaustive control resume path.
  - Opcode handler generation no longer hides continuation contracts in string concatenation.
  - GC, weak tables, finalizers, userdata, native calls, protected calls, and coroutine suspension all use explicit state products.
  - All Lua 5.5 semantic branches have named continuation exits or named data constructors.
  - Binary chunk/source frontends produce validated VM products without depending on PUC layouts.

- **Rough sketch**:
  - Define the missing semantic products and protocol fragments.
  - Refactor call/error/yield/metamethod resume paths onto explicit suspended-control records.
  - Replace handler boilerplate generation with typed fragment builders.
  - Implement allocator/GC/table/string/upvalue/userdata protocols against the new products.
  - Complete opcodes and frontends using the protocol library.

---

### Approach C: Canonical Semantic-Bytecode Boundary

- **Core idea**: Treat PUC Lua 5.5 source/chunks as compatibility inputs that translate into a Lalin-native canonical instruction/product format, and make the VM execute only that normalized semantic bytecode.

- **Key changes**:
  - Introduce a canonical `Proto`/instruction layer separate from raw Lua 5.5 bytecode encodings.
  - Add a binary chunk reader/translator that resolves `EXTRAARG`, `sJ`, `sC`, `vB/vC`, comparison+jump coupling, `MMBIN*` adjacency, hidden vararg/close metadata, and open-call/result forms at load time.
  - Make the source compiler emit the same canonical instruction stream directly.
  - Simplify runtime dispatch so opcode handlers consume already-normalized operands and semantic events.
  - Keep raw-bytecode validation at the compatibility frontier, and canonical validation at the VM trust boundary.
  - Implement stdlib/FFI/native/userdata through canonical VM products, not PUC runtime conventions.

- **Tradeoff**: Optimizes for a clean VM core and unified source/chunk semantics; sacrifices direct one-to-one execution of PUC opcode streams and adds a nontrivial translation layer.

- **Risk**: Bugs in translation could silently change semantics unless raw-input validation, canonical validation, and differential tests are kept separate.

- **Done criteria**:
  - Accepted Lua 5.5 binary chunks translate into canonical VM bytecode with no PUC layout dependency.
  - Source compiler and chunk loader converge on the same canonical `Proto` model.
  - Runtime dispatch no longer needs to know raw `EXTRAARG`, `sJ`, `vB/vC`, or adjacency quirks.
  - Canonical bytecode has explicit typed forms for calls, returns, metamethod fallback, close/finalizer behavior, varargs, and jumps.
  - Full VM conformance is tested at both boundaries: raw chunk/source acceptance and canonical runtime execution.

- **Rough sketch**:
  - Define canonical instruction/product schema.
  - Build raw Lua 5.5 chunk decoder and translator using vendored Lua only as semantic/encoding oracle.
  - Rework validator into raw-frontier validation plus canonical VM validation.
  - Port current opcode handlers to canonical operations.
  - Expand source compiler, stdlib subset, FFI, GC/finalizer/userdata support against canonical VM semantics.

---

### Comparison

- **Approach A** preserves the current VM shape and completes it directly.
- **Approach B** prioritizes explicit-programming purity by making hidden semantic state first-class before completion.
- **Approach C** separates compatibility concerns from runtime execution by normalizing source/chunks into Lalin-native semantic bytecode.

## Critique Output — 2026-05-29 23:58:33

Scoring note: for Coupling/Cohesion/Philosophy fit/Testability, 5 is best. For Migration cost and Risk, 5 is highest cost/risk.

### Approach A: Direct Contract-Completion of the Existing VM

| Dimension | Score (1-5) | Rationale |
|-----------|-------------|-----------|
| **Coupling** | 3/5 | Preserves useful separation from SponJIT, but keeps raw Lua 5.5 bytecode quirks, opcode stubs, string-template protocols, and int-encoded resume modes coupled directly into runtime dispatch. |
| **Cohesion** | 3/5 | Existing modules have recognizable responsibilities, but `oom`, resume modes, table/metamethod paths, and GC/finalizer state currently mix “not implemented” with real semantic outcomes. |
| **Migration cost** | 2/5 | Lowest structural migration: continue from current VM spine, tests, dispatch loop, call/return model, and products. Still a large implementation effort because many semantic areas are stubs. |
| **Philosophy fit** | 3/5 | The outer control tree is idiomatic Lalin, but inner behavior still risks stringly/intly implicit control and overloaded error paths unless aggressively audited. |
| **Risk** | 4/5 | High risk of completing semantics on top of a partially wrong bytecode model or blessing stub behavior as real behavior. Weak tables, finalizers, native calls, protected calls, and coroutine resume would stress existing hidden state. |
| **Testability** | 4/5 | Incremental validation is strong because the current VM already has tests and explicit contracts. However, tests must distinguish real OOM from unimplemented semantic paths. |

**Verdict**: Yes with caveats
**Key concern**: Fix decoder/validator and eliminate overloaded `oom`/stub paths before treating opcode/runtime behavior as semantically meaningful.

---

### Approach B: Explicit Product/Protocol Re-Foundation

| Dimension | Score (1-5) | Rationale |
|-----------|-------------|-----------|
| **Coupling** | 4/5 | Best chance to decouple semantic products from raw bytecode encodings, PUC architecture, hidden C behavior, and ad hoc opcode-handler conventions. Risk only if the protocol layer becomes an over-generic second compiler. |
| **Cohesion** | 5/5 | Aligns responsibilities cleanly: products model persistent VM state; regions model state machines; continuations model semantic branches; opcode handlers become bridges into explicit protocols. |
| **Migration cost** | 5/5 | Deepest refactor. It touches `Frame` resume state, opcode generation, GC products, table/userdata/finalizer state, native ABI handling, protected calls, coroutine suspension, and validation. |
| **Philosophy fit** | 5/5 | Strongest fit with `explicit_programming.md`: dual data/control tree, typed sums/protocols, explicit persistent state, named exits, no hidden PUC/C-stack behavior, no unvalidated intly control. |
| **Risk** | 3/5 | Architecturally safer long-term, but execution risk is real: refoundation can stall, over-abstract, or break working spine invariants unless constrained by current tests and concrete Lua 5.5 semantics. |
| **Testability** | 4/5 | Very testable if developed as explicit protocol replacements with exhaustive decoders and compatibility tests. Less testable if done as a broad rewrite before preserving current call/return/frame-cache guarantees. |

**Verdict**: Strong yes
**Key concern**: Keep the refoundation concrete, monomorphic, grep-visible, and anchored to exact Lua 5.5 validator/runtime invariants rather than becoming an abstract VM framework.

---

### Approach C: Canonical Semantic-Bytecode Boundary

| Dimension | Score (1-5) | Rationale |
|-----------|-------------|-----------|
| **Coupling** | 4/5 | Cleanly separates PUC Lua 5.5 source/chunk compatibility from the Lalin-native VM core. The main coupling risk moves into the translator. |
| **Cohesion** | 4/5 | Strong conceptual split: raw frontier validation, canonical VM validation, normalized runtime execution. But it adds another major layer whose responsibility must stay narrow. |
| **Migration cost** | 4/5 | Requires new canonical instruction/product schema, translator, validator split, and porting current opcode handlers to normalized operations. |
| **Philosophy fit** | 4/5 | Fits the “PUC as oracle only” rule well and can make runtime dispatch more explicit. Risk: canonical bytecode translation could hide semantic control if not represented as typed products/protocols. |
| **Risk** | 4/5 | Translation bugs could silently alter Lua semantics. Differential testing must cover raw chunks, source compiler output, canonical validation, and runtime behavior separately. |
| **Testability** | 3/5 | Boundaries are testable, but there are more of them. It increases verification burden before the VM can be trusted end-to-end. |

**Verdict**: Yes with caveats
**Key concern**: The raw-to-canonical translator must itself be an explicit, validated semantic boundary, not an opaque compatibility shim.

---

### Summary

- **Recommended**: **Approach B**. It best matches the stated goal and Lalin philosophy: complete Lua 5.5 by making semantic state and control explicit, not by accumulating behavior behind integer modes, string templates, or overloaded failure paths.

- **Dark horse**: **Approach C**. It has high upside for source+binary Lua 5.5 compatibility because it separates raw PUC bytecode quirks from the VM core. Its risk is translator correctness.

- **Avoid**: **Approach A as the final architecture**. It is useful for continuity, but weakest long-term: it risks preserving today’s implicit control encodings and semantic overloads while merely filling stubs.

For developing **B safely**, the essential constraints are: preserve the proven A spine where it is already explicit — frame-cache reload, `result_base`, unified VM exits, SponJIT separation, fail-loud boundaries — and borrow C’s boundary discipline for raw Lua 5.5 bytecode/source compatibility. The first safety gate should be exact decoder/validator alignment with Lua 5.5 before deeper semantic completion.

## Documenter Output — 2026-05-30 07:53:25

# Architectural Decision: Explicit Product/Protocol Re-Foundation for the Lua 5.5 VM

## Goal

Complete the Lalin-native Lua 5.5 VM idiomatically according to `explicit_programming.md` by making every Lua 5.5 semantic distinction visible as either typed runtime data or typed control flow, while preserving the existing explicit interpreter spine and keeping PUC Lua only as a semantic/bytecode oracle, not as an implementation architecture.

## Incentives

The current VM already has an idiomatic outer control tree, but many inner semantics remain incomplete or implicit. Runtime behavior is still hidden behind integer modes such as `Frame.resume_mode`, raw tag constants, string-generated continuation fragments, and overloaded `oom` exits that currently mean real allocation failure, missing implementation, or semantic failure depending on context. This creates a verification risk: tests could accidentally bless scaffolding behavior as Lua semantics.

The decision is motivated by several concrete pain points found in the existing VM:

- Lua 5.5 bytecode decoding is not fully aligned with the vendored oracle: `OP_JMP` uses `sJ`, `sC` immediates require signed decoding, `vB/vC` matter for `NEWTABLE`/`SETLIST`, and `FORLOOP/FORPREP` use `Bx` semantics.
- `validate_proto` is only a partial trust boundary; it does not yet mirror all dispatch assumptions.
- Allocation, stack growth, table growth, string interning, closure creation, upvalue allocation, protected frames, native calls, weak tables, finalizers, varargs, coroutine resume/yield, and many metamethod paths are fail-loud stubs.
- GC/finalizer/weak-table state lacks explicit data products for the Lua semantics implied by the vendored oracle.
- Opcode handler generation still uses string fragments in places where explicit Lalin philosophy prefers typed, grep-visible products and protocols.
- SponJIT must not consume VM scaffolding until the interpreter contract is semantically complete and tested.

## Current State

The Lua interpreter VM lives under `experiments/lua_interpreter_vm/src/`. It is explicitly separate from SpongeJIT/SponJIT and targets Lua 5.5 semantics using Lalin-native data and control structures.

### Governing contract

`experiments/lua_interpreter_vm/VM_CONTRACT.md` states that:

- The VM targets Lua 5.5 semantics in Lalin-native structures.
- PUC Lua is a semantic reference only.
- PUC layouts, `longjmp`, C-stack behavior, allocator conventions, and internal runtime shapes must not become implementation dependencies.

`src/contract.lua` currently exposes:

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

This contract makes SponJIT explicitly unavailable until the interpreter VM satisfies core semantic and ABI gates.

### Runtime data tree

`src/products.lua` defines the primary VM products:

- `Value`
- `Proto`
- `Frame`
- `LuaThread`
- `GlobalState`
- table, closure, userdata, native descriptor, allocator, string, upvalue, and protected-frame structures.

Important current structures include:

```lalin
struct Value
    tag: u32
    aux: u32
    bits: u64
end
```

```lalin
struct Proto
    gc: GCHeader
    code: ptr(Instr)
    code_len: index
    constants: ptr(Value)
    constants_len: index
    children: ptr(ptr(Proto))
    children_len: index
    numparams: u8
    flag: u8
    maxstack: u16
end
```

```lalin
struct Frame
    closure: Value
    base: index
    top: index
    pc: index
    wanted: i32
    tailcalls: i32
    resume_mode: u16
    resume_a: u16
    resume_b: u16
    resume_c: u16
    resume_pc: index
    resume_base: index
    resume_value: Value
    result_base: index
    call_top: index
    yieldable: u8
    flags: u8
    reserved: u16
end
```

```lalin
struct LuaThread
    status: u8
    stack: ptr(Value)
    stack_size: index
    top: index
    frames: ptr(Frame)
    frame_count: index
    frame_cap: index
    open_upvals: ptr(UpVal)
    protected_top: ptr(ProtectedFrame)
    global: ptr(GlobalState)
    err_value: Value
    tbc_head: index
    yieldable: i32
    nonyieldable: i32
    last_error_code: i32
    flags: u32
end
```

This data tree is Lalin-native and does not import PUC runtime layouts. However, many semantic distinctions are still manually encoded as integers, including value tags, metamethod IDs, resume modes, status codes, and error codes.

### Runtime control tree

`src/vm_loop.lua` defines the main interpreter entry points:

```lalin
region vm_resume(
    L: ptr(LuaThread),
    nargs: i32;
    ok: cont(nres: i32),
    yielded: cont(nres: i32),
    runtime_error: cont(code: i32),
    oom: cont())
```

```lalin
region vm_loop(
    L: ptr(LuaThread);
    finished: cont(nres: i32),
    yielded: cont(nres: i32),
    error: cont(code: i32),
    oom: cont())
```

Instruction dispatch uses explicit continuations:

```lalin
next(...)
do_jump(...)
resume_parent(...)
enter_lua(child: ptr(Frame))
enter_native(cl: ptr(CClosure), func_slot: index, nargs: i32,
             wanted: i32, result_base: index, resume_mode: u16)
returned(nres: i32)
yielded(nres: i32)
error(code: i32)
oom()
```

This is one of the strongest existing pieces of the VM: completion, yield, runtime error, OOM, Lua call entry, native call entry, return, and frame switching are visible in the control tree.

The current loop also correctly reloads frame-local cached state when returning to a parent frame:

```lalin
let cl: ptr(LClosure) = as(ptr(LClosure), parent.closure.bits)
let parent_code: ptr(Instr) = cl.proto.code
let parent_constants: ptr(Value) = cl.proto.constants
jump loop(frame = parent, pc = pc, base = base, top = top,
          code = parent_code, constants = parent_constants)
```

Tests already verify this frame-cache reload behavior and the explicit `result_base` return contract.

### Opcode and region organization

`src/opcodes.lua` builds the decoder and dispatch surface for the Lua 5.5 opcode set. Opcode handlers are grouped under:

- `src/op/arithmetic.lua`
- `src/op/table.lua`
- `src/op/call.lua`
- `src/op/loop.lua`
- `src/op/compare.lua`
- `src/op/misc.lua`
- `src/op/closure.lua`

Shared handler fragments live in `src/op/_init.lua`.

Runtime semantic regions are distributed across:

- `regions_value.lua`
- `regions_table.lua`
- `regions_call.lua`
- `regions_error.lua`
- `regions_stack.lua`
- `regions_gc.lua`
- `regions_coroutine.lua`
- `regions_metamethod.lua`
- `regions_string.lua`
- `regions_upvalue.lua`
- `regions_api.lua`
- `validate.lua`

The module graph is loaded by `src/init.lua`.

### Incomplete semantic areas

The VM intentionally fails loudly for many incomplete areas, but completion requires those paths to become real semantic protocols rather than generic failure exits.

Current gaps include:

- `alloc_object` checks allocator presence and threshold but ultimately returns `oom`.
- `stack_check` and `frame_push` cannot grow storage.
- `string_intern`, `table_resize`, `make_lclosure`, and upvalue allocation fail as `oom`.
- `table_raw_get` scans nodes rather than hashing by bucket.
- `table_raw_set` cannot insert new entries or resize.
- `table_next` is not implemented.
- `NEWTABLE` and `SETLIST` fail as `oom`.
- arithmetic/metamethod fallback opcodes such as `MMBIN`, `MMBINI`, and `MMBINK` fail with runtime errors.
- `__call`, `__len`, `__concat`, `__close`, and comparison metamethod paths are incomplete.
- native calls have typed exits but `call_native` always fails.
- protected-call allocation and success paths are missing.
- coroutine resume/yield does not yet preserve enough continuation state for all yieldable contexts.
- weak tables and finalizers are represented only skeletally.
- userdata has a Lalin product but no complete finalizer/user-value/payload contract.
- source compilation supports only a small expression/local/return slice.
- binary chunk compatibility is not yet implemented.

### PUC Lua relationship

Vendored Lua 5.5 is present under `.vendor/Lua/` and is used only as an oracle for:

- Lua version and opcode list.
- instruction bit layout.
- opcode semantic notes.
- numeric conversion and equality rules.
- concatenation and length behavior.
- metamethod names and lookup semantics.
- weak table and finalizer behavior.
- userdata/lightuserdata semantic facts.

The VM must not port PUC architecture. In particular, the decision preserves the rule that PUC layouts, allocator conventions, GC list layouts, C stack behavior, `longjmp`, and internal runtime object shapes are not implementation dependencies.

### SponJIT relationship

SponJIT remains separate. The current interpreter VM is not wired to a JIT. Existing SponJIT documents describe an offline path from opcode facts to semantic SSA to stencil/native-fragment descriptors. `contract.lua` explicitly sets `sponjit_allowed = false`.

The interpreter must therefore be completed and tested as an independent Lalin-native VM. SponJIT may not pressure the interpreter shape through reserved optimization fields or premature native-fragment requirements.

## Chosen Target

### Approach

The chosen approach is **Approach B: Explicit Product/Protocol Re-Foundation**.

The VM will be completed by refounding incomplete and implicit semantic areas as first-class typed products and continuation protocols before filling in behavior. The goal is not a rewrite away from the current interpreter spine; it is a re-foundation of the hidden and skeletal inner semantics so that Lua 5.5 behavior is represented in the Lalin style required by `explicit_programming.md`.

This approach was chosen because it best matches the project philosophy:

- data tree: persistent VM states must be explicit products;
- control tree: semantic branches must be explicit continuations;
- regions compose state machines;
- functions seal stable boundaries;
- hidden state, stringly exits, overloaded booleans/statuses, and unvalidated integer modes are architectural liabilities.

### Preserved VM spine

The following current VM properties are preserved:

- `src/` remains the interpreter VM implementation.
- PUC Lua remains only a semantic/bytecode oracle.
- SponJIT remains disabled and separate.
- The existing `vm_resume` / `vm_loop` / `dispatch_instruction` outer control tree remains the interpreter spine.
- The explicit VM exits remain central: completion, yield, runtime error, and OOM.
- Frame-cache reload on frame switch remains required.
- Explicit `result_base` ownership for call returns remains required.
- Unified error unwind through explicit protected-frame machinery remains the model.
- Native calls remain behind explicit ABI descriptors and status/result records.
- Allocator and GC boundaries remain explicit VM protocols.
- Existing tests for frame-cache reload, result-base behavior, VM contract, validation, and smoke coverage remain important constraints.

### Architecture

The re-foundation introduces explicit products and protocols for semantic areas that are currently represented by loose integer state, string fragments, comments, or fail-loud stubs.

#### Explicit suspended-control products

`Frame.resume_mode`, `resume_a`, `resume_b`, `resume_c`, `resume_pc`, `resume_base`, and `resume_value` currently encode suspended control manually.

The chosen design requires every persisted resume mode to have:

- a named semantic product or checked decoder;
- a corresponding control-tree resume path;
- exhaustive handling at resume boundaries;
- tests for unknown/default cases.

Suspended states must cover Lua calls, native calls, metamethod calls, protected calls, coroutine yield/resume, `__close`, finalizer execution, and any other VM path that can suspend and later continue.

#### Explicit semantic protocol modules

The VM will add or refactor product/protocol modules for:

- resumable VM states;
- numeric coercion outcomes;
- table access outcomes;
- metamethod lookup and dispatch outcomes;
- GC phases;
- weak table modes;
- finalizer eligibility and pending-finalizer state;
- userdata payload/user-value/finalizer state;
- native call results;
- protected-call states;
- coroutine suspension states.

Opcode handlers become thin bridges into these semantic protocols rather than places where hidden control conventions accumulate.

#### Opcode handler generation

Continuation signatures and shared handler contracts currently appear partly as string fragments in `src/op/_init.lua` and related opcode modules.

The chosen architecture replaces loosely shared string fragments with named, monomorphic Lua builders that emit typed Lalin fragments. The generated code must remain concrete, grep-visible, and tied to named continuation protocols.

This does not introduce Lalin source generics. Lua remains the metaprogramming layer, and Lalin receives monomorphic generated source.

#### Runtime product extensions

`products.lua` must be extended where the current data tree lacks semantic state.

Areas requiring explicit products include:

- GC phase and object-list state;
- weak-value, weak-key, ephemeron, and all-weak table states;
- finalizable-object and pending-finalizer queues;
- finalizer-running restrictions;
- userdata payload ownership, alignment, user values, and finalizer metadata;
- table weak-mode and metamethod-cache invalidation state;
- native ABI result/status records;
- protected-call frame state.

These products remain Lalin-native. They do not copy PUC object layouts.

#### Validator and decoder boundary

A necessary hybrid constraint from Approach A is retained: decoder and validator correctness are the first safety gate.

`opcodes.lua` and `validate.lua` must align with Lua 5.5 bytecode facts from the vendored oracle, including:

- `sJ` for `OP_JMP`;
- signed `sC` immediates;
- `vB/vC` operands;
- `Bx` behavior for `FORLOOP` / `FORPREP`;
- `EXTRAARG` pairing;
- comparison/test instruction adjacency to jumps;
- `MMBIN*` adjacency;
- open-call/open-result forms;
- hidden close/vararg metadata in call/return instructions.

`validate_proto` must exactly match dispatch assumptions. Accepted source programs and accepted binary chunks must both pass through explicit VM product validation.

#### Compatibility boundary discipline

A necessary hybrid constraint from Approach C is also retained: compatibility frontiers must be explicit.

Source compatibility, binary chunk compatibility, internal `Proto` compatibility, and native/FFI ABI compatibility are separate contracts. PUC Lua may define source and bytecode semantics, but raw compatibility handling must be a typed boundary, not an opaque shim.

If raw Lua 5.5 bytecode is accepted, its decoding and translation into Lalin-native VM products must be explicit and validated. The runtime must not depend on PUC internal chunk or object layouts.

#### Allocation, GC, weak tables, and finalizers

Allocation and GC are treated as Lua VM semantics, not background infrastructure.

The completed architecture requires explicit protocols for:

- allocator success, GC-step requirement, and real OOM;
- stack growth;
- frame growth;
- table growth and insertion;
- string interning;
- closure allocation;
- upvalue allocation/closing;
- protected-frame allocation;
- GC marking, propagation, sweeping, barriers;
- weak table mode parsing from `__mode`;
- weak key/value clearing;
- finalizer eligibility when metatables are assigned;
- pending finalizer execution through `__gc`;
- finalizer ordering and restrictions.

The current overloaded use of `oom` for unimplemented behavior must be eliminated. In the completed VM, `oom` means real allocation failure only.

#### Calls, protected calls, native calls, and coroutines

The existing call/return spine is preserved, but suspended and boundary states become explicit products/protocols.

Required completed areas include:

- Lua call setup and return adjustment;
- native invocation through `NativeFunc` / `NativeCallResult`;
- native statuses: OK, ERROR, YIELD, OOM, STACK_GROW;
- protected-call setup, success, and failure;
- error object construction and protected unwind;
- coroutine resume/yield state preservation;
- yieldability and nonyieldable boundary checks;
- metamethod calls that can yield or error;
- `__close` and `__gc` invocation through explicit call/error/yield protocols.

Native calls must not smuggle host exceptions, errno/null conventions, hidden scheduler state, or C-stack behavior across the VM boundary.

#### Opcode completion

All Lua 5.5 opcode families must be completed against explicit protocols:

- arithmetic and bitwise operations;
- mixed integer/float numeric semantics;
- string-to-number coercions where Lua requires them;
- signed immediates;
- comparisons and test/jump protocols;
- table get/set/new/setlist/next;
- call, tailcall, return, vararg;
- closure and upvalue operations;
- loops;
- length and concatenation;
- metamethod fallback opcodes;
- to-be-closed variables;
- errors and nil checks.

Arithmetic fallback remains a two-stage control protocol: primitive success skips the following `MMBIN*`; primitive failure transfers to the adjacent metamethod instruction with explicit operand/event metadata.

### Scope

The decision covers completion of the Lalin-native interpreter VM in `experiments/lua_interpreter_vm/src/`, including:

- runtime products;
- interpreter control protocols;
- bytecode decoding and validation;
- opcode handlers;
- allocator/GC/table/string/upvalue/userdata regions;
- call/error/protected/native/coroutine regions;
- source compiler expansion;
- binary chunk compatibility boundary;
- conformance and contract tests.

It does not choose to port PUC Lua internals. It does not enable SponJIT. It does not redefine the VM as a JIT-first architecture.

### Tradeoffs acknowledged

The chosen approach has the highest migration cost among the proposed approaches. It touches:

- `Frame` resume state;
- opcode generation;
- GC products;
- table/userdata/finalizer state;
- native ABI handling;
- protected calls;
- coroutine suspension;
- validation;
- many opcode handlers.

This cost is accepted because the approach gives the best fit with Lalin’s explicit-programming philosophy and offers the clearest path to auditability and long-term correctness.

The decision also sacrifices the lowest-effort incremental path of simply filling existing stubs in place. Existing scaffolding is preserved where it is already explicit, but hidden or overloaded state must be refounded rather than normalized as final architecture.

### Risks acknowledged

Known risks from critique:

- The re-foundation could stall because it is a deep refactor.
- It could over-abstract into a second VM/compiler framework.
- It could break existing working spine invariants if not anchored to current tests.
- It could defer semantic completion too long while reshaping products.
- Raw bytecode/source compatibility work could hide semantic control if translation boundaries are not explicit.
- Existing `oom` stubs could be mistaken for real allocation behavior unless audited and replaced.
- Native calls, protected calls, finalizers, weak tables, and coroutine resume/yield all stress the same suspended-control machinery and therefore require careful protocol coverage.

The accepted constraint is that the refoundation remains concrete, monomorphic, grep-visible, and anchored to exact Lua 5.5 semantics and existing VM invariants.

### Done criteria

The architecture is complete when:

- Every persisted integer mode has a checked product/protocol decoder and exhaustive control resume path.
- Opcode handler generation no longer hides continuation contracts in string concatenation.
- `validate_proto` exactly matches dispatch assumptions.
- Lua 5.5 bytecode decoding matches the oracle facts used by dispatch.
- `oom` means real allocation failure only.
- No fail-loud semantic stubs remain for Lua 5.5 core behavior.
- Source programs and accepted binary chunks both produce validated Lalin-native VM products.
- Weak tables, finalizers, userdata `__gc`, protected calls, coroutine yield/resume, native calls, allocator/GC progression, table growth, string interning, closure/upvalue creation, varargs, and documented stdlib subset behavior pass conformance tests.
- PUC Lua remains only a semantic/bytecode oracle.
- SponJIT remains separate; interpreter gates may be satisfied without enabling JIT integration.

## Edit-planner Output — 2026-05-30 07:58:40

### Precondition Checks

Before edits:

1. Confirm working tree is clean or changes are intentionally staged.
2. Run current baseline:
   - `luajit experiments/lua_interpreter_vm/tests/test_vm_smoke.lua`
   - `luajit experiments/lua_interpreter_vm/tests/test_vm_validation_contract.lua`
   - `luajit experiments/lua_interpreter_vm/tests/test_vm_call_frame_contract.lua`
3. Verify these anchors still match:
   - `experiments/lua_interpreter_vm/src/products.lua`: `Frame` still at line 70 with 18 fields.
   - `constants.lua`: `Resume` still lines 134-152 with `Resume.N = 17`.
   - `opcodes.lua`: decode helpers still lines 25-37.
   - `validate.lua`: decode and validation loop still starts around lines 35-44.
   - `regions_call.lua`: `return_from_lua` captures resume fields around lines 150-167; `handle_return_mode` starts around line 232.
   - `vm_loop.lua`: frame-cache reload remains in `cont_resume_parent` around lines 112-120.
4. Confirm SponJIT remains disabled:
   - `experiments/lua_interpreter_vm/src/contract.lua` line 7: `sponjit_allowed = false`.

---

## Files to Modify

### `experiments/lua_interpreter_vm/src/constants.lua`

**Goal**: Add explicit protocol-state constant families without changing existing numeric ABI constants.

**Edit blocks**

1. **Lines 134-152**: Modify comments only around `Resume`.
   - Before: raw `Resume` integer table.
   - After: keep all values unchanged, add comment:
     ```lua
     -- Persisted suspended-control discriminants.
     -- These integers are ABI storage only; control handling must go through
     -- regions_resume.decode_resume_mode / resume_after_return.
     ```
   - Do not renumber anything.

2. **After line 161 (`NativeResult`)**: Add explicit native-boundary status grouping.
   ```lua
   local NativeBoundary = {}
   NativeBoundary.READY = 0
   NativeBoundary.RETURNED = 1
   NativeBoundary.ERRORED = 2
   NativeBoundary.YIELDED = 3
   NativeBoundary.NEEDS_STACK = 4
   NativeBoundary.OOM = 5
   NativeBoundary.INVALID = 6
   ```

3. **After line 186 (`GCState`)**: Add weak/finalizer/userdata state constants.
   ```lua
   local WeakModeFlag = {}
   WeakModeFlag.NONE = 0
   WeakModeFlag.VALUES = 1
   WeakModeFlag.KEYS = 2
   WeakModeFlag.EPHEMERON = 4
   WeakModeFlag.ALL_WEAK = 8

   local FinalizerState = {}
   FinalizerState.NONE = 0
   FinalizerState.ELIGIBLE = 1
   FinalizerState.PENDING = 2
   FinalizerState.RUNNING = 3
   FinalizerState.DONE = 4

   local UserDataFlag = {}
   UserDataFlag.OWNS_DATA = 1
   UserDataFlag.FINALIZABLE = 2
   UserDataFlag.HAS_USER_VALUES = 4
   UserDataFlag.ALIGNED_PAYLOAD = 8

   local CompatFormat = {}
   CompatFormat.INTERNAL_PROTO = 0
   CompatFormat.LUA55_BINARY_CHUNK = 1
   CompatFormat.LUA55_SOURCE = 2
   ```

4. **Return table around lines 217-232**: Add new tables:
   ```lua
   NativeBoundary = NativeBoundary,
   WeakModeFlag = WeakModeFlag,
   FinalizerState = FinalizerState,
   UserDataFlag = UserDataFlag,
   CompatFormat = CompatFormat,
   ```

**Patterns to enforce**
- Existing constants are stable ABI; append only.
- Keep plain Lua tables, no Lalin fragments.

**Danger zones**
- Do not alter `Resume.N`; current code assumes `mode < Resume.N`.
- Do not remove `Op.SETTI` alias.

---

### `experiments/lua_interpreter_vm/src/products.lua`

**Goal**: Add explicit sidecar products for suspended control, GC/weak/finalizer/userdata/native/protected/coroutine states while preserving existing struct layouts.

**Edit blocks**

1. **After line 8 (`Value`)**: Add first-class suspended control product.
   ```lua
   -- 1b. Persisted suspended-control payload.
   -- Mirrors existing Frame resume_* storage without changing Frame layout.
   local SuspendedControl = host.struct [[struct SuspendedControl mode: u16; a: u16; b: u16; c: u16; pc: index; base: index; value: Value; result_base: index; wanted: i32 end]]
   ```

2. **After line 40 (`NativeCallResult`)**: Add native boundary state.
   ```lua
   local NativeBoundaryState = host.struct [[struct NativeBoundaryState func_slot: index; nargs: i32; wanted: i32; result_base: index; resume: SuspendedControl; result: NativeCallResult end]]
   ```

3. **After line 46 (`UserData`)**: Add userdata semantic sidecar.
   ```lua
   local UserDataPayload = host.struct [[struct UserDataPayload data: ptr(u8); len: index; align: u32; owner_flags: u8; user_values: ptr(Value); user_values_len: index end]]
   local UserDataFinalizer = host.struct [[struct UserDataFinalizer state: u8; object: ptr(GCHeader); next: ptr(GCHeader) end]]
   ```

4. **After line 65 (`Allocator`)**: Add protected/coroutine/GC protocol products.
   ```lua
   local ProtectedCallState = host.struct [[struct ProtectedCallState frame_index: index; stack_top: index; handler_slot: index; errfunc_slot: index; resume: SuspendedControl end]]
   local CoroutineSuspendState = host.struct [[struct CoroutineSuspendState status: u8; nresults: i32; frame_count: index; top: index; resume: SuspendedControl end]]
   local WeakTableState = host.struct [[struct WeakTableState mode_flags: u8; epoch: u32; table_obj: ptr(GCHeader); next: ptr(GCHeader) end]]
   local FinalizerQueue = host.struct [[struct FinalizerQueue eligible: ptr(GCHeader); pending: ptr(GCHeader); running: u8; reserved: u8 end]]
   ```

5. **Do not modify lines 67-74 existing `ProtectedFrame`, `Frame`, `GlobalState`, `LuaThread` in milestone 1.**
   - Later phases may embed sidecars.
   - First milestone must preserve FFI layout tests.

6. **Return table lines 93-120**: Export all new structs.

**Patterns to enforce**
- Sidecar products first; no breaking layout changes in milestone 1.
- Product names are semantic, not PUC-layout names.

**Danger zones**
- Existing FFI tests duplicate `Frame`, `LuaThread`, `Proto`. Do not alter those fields yet.
- Do not add PUC list names like `finobj/tobefnz` directly as architecture.

---

### `experiments/lua_interpreter_vm/src/bytecode.lua` *(new)*

**Goal**: Centralize Lua 5.5 instruction bit decoding facts used by dispatch, validation, and tests.

**Contents sketch**
```lua
local bytecode = {}

bytecode.SIZE_OP = 7
bytecode.POS_A = 7
bytecode.POS_K = 15
bytecode.POS_B = 16
bytecode.POS_C = 24
bytecode.POS_VB = 16
bytecode.POS_VC = 22
bytecode.POS_BX = 15
bytecode.POS_AX = 7
bytecode.MAX_BX = 131071
bytecode.OFFSET_SBX = 65535
bytecode.MAX_AX = 33554431
bytecode.OFFSET_SJ = 16777215
bytecode.OFFSET_SC = 127

function bytecode.exprs(expr)
  return {
    OP = expr [[as(u16, word & 127)]],
    A = expr [[as(u16, (word >> 7) & 255)]],
    K = expr [[as(u8, (word >> 15) & 1)]],
    B = expr [[as(u16, (word >> 16) & 255)]],
    C = expr [[as(u16, (word >> 24) & 255)]],
    VB = expr [[as(u16, (word >> 16) & 63)]],
    VC = expr [[as(u16, (word >> 22) & 1023)]],
    BX = expr [[(word >> 15) & 131071]],
    SBX = expr [[as(i32, ((word >> 15) & 131071)) - 65535]],
    AX = expr [[(word >> 7) & 33554431]],
    SJ = expr [[as(i32, ((word >> 7) & 33554431)) - 16777215]],
    SC = expr [[as(i32, ((word >> 24) & 255)) - 127]],
  }
end

return bytecode
```

**Patterns**
- This file is oracle-fact only, not runtime policy.
- No PUC macros imported; encode the semantic bit layout as Lalin-native constants.

---

### `experiments/lua_interpreter_vm/src/opcodes.lua`

**Goal**: Route dispatch decoding through centralized Lua 5.5 bytecode facts and stop using wrong operand shapes.

**Edit blocks**

1. **Imports lines 5-8**: Add:
   ```lua
   local bytecode = require("experiments.lua_interpreter_vm.src.bytecode")
   ```

2. **Lines 25-37 decode helpers**: Replace direct helpers with:
   ```lua
   local D = bytecode.exprs(expr)
   local A, B, C, K = D.A, D.B, D.C, D.K
   local VB, VC = D.VB, D.VC
   local BX, SBX, AX, SJ, SC = D.BX, D.SBX, D.AX, D.SJ, D.SC
   ```
   Add:
   ```lua
   local ARGS_AVBC = args(A, VB, VC, K)
   local ARGS_ASJ = args(nil, nil, nil, K, nil, SJ)
   local ARGS_ASC = args(A, B, nil, K, nil, SC)
   local ARGS_AX = args(nil, nil, nil, nil, AX)
   ```

3. **Inline `LOADKX` around lines 225-236**:
   - Before: extra arg uses `(extra.word >> 15) & 131071`.
   - After: use Ax:
     ```lalin
     let extra_ax: u32 = (extra.word >> 7) & 33554431
     let src: ptr(Value) = cur_consts + as(index, extra_ax)
     ```

4. **Inline immediate arithmetic around lines 286-310**:
   - `ADDI` must use signed `sC`.
   - Replace:
     ```lalin
     let imm: i32 = as(i32, (word >> 24) & 255)
     ```
     with:
     ```lalin
     let imm: i32 = as(i32, ((word >> 24) & 255)) - 127
     ```

5. **Inline `JMP` around current line ~410**:
   - Before: 17-bit `sBx`.
   - After:
     ```lalin
     let new_pc: index = as(index, as(i32, cur_pc) + (as(i32, ((word >> 7) & 33554431)) - 16777215))
     ```

6. **Emit arm table around lines 480-520**:
   - `NEWTABLE`: use `ARGS_AVBC`.
   - `SETLIST`: use `ARGS_AVBC`.
   - `JMP`: use `ARGS_ASJ` or inline already handles.
   - `FORLOOP`, `FORPREP`, `TFORPREP`, `TFORLOOP`: use `ARGS_ABX`, not `ARGS_ASBX`/`ARGS_ABC`.
   - `EXTRAARG`: use `ARGS_AX`.

7. **Metadata lines 700-727**:
   - Change modes:
     - `NEWTABLE` → `"AvBCk"`
     - `JMP` → `"sJ"`
     - `FORLOOP`, `FORPREP`, `TFORPREP`, `TFORLOOP` → `"ABx"`
     - `SETLIST` → `"AvBCk"`
     - `EXTRAARG` → `"Ax"`

**Patterns**
- Any raw bit expression added here must match `bytecode.lua`.
- Dispatch and validator must decode identical operands.

**Danger zones**
- `dispatch_instruction` has exactly 9 continuations; preserve signature.
- Do not remove frame-cache reload responsibility from `vm_loop.lua`.

---

### `experiments/lua_interpreter_vm/src/validate.lua`

**Goal**: Make the validator the real trust boundary for dispatch assumptions.

**Edit blocks**

1. **After imports lines 1-4**: Add:
   ```lua
   local bytecode = require("experiments.lua_interpreter_vm.src.bytecode")
   ```
   If not directly used in Lalin source, still import for Lua-side constants/comments.

2. **Lines 38-44 decode block**: Add decoded operands:
   ```lalin
   let ax: u32 = (word >> 7) & 33554431
   let sj: i32 = as(i32, ax) - 16777215
   let sc: i32 = as(i32, c) - 127
   let vb: u16 = as(u16, (word >> 16) & 63)
   let vc: u16 = as(u16, (word >> 22) & 1023)
   ```

3. **Lines 56-60 `EXTRAARG` pairing**:
   - Before: only `LOADKX`.
   - After: allow:
     - previous `LOADKX`
     - previous `NEWTABLE`
     - previous `SETLIST` only when previous `k != 0`
   - To check previous `k`, read `prev_word` from `p.code[pc - 1]`.

4. **Lines 99-110 `LOADKX` extra check**:
   - Use `extra_ax = (extra_word >> 7) & 33554431`, not `extra_bx`.
   - Validate constant bounds against `extra_ax`.

5. **After `LOADKX` block**: Add `NEWTABLE`/`SETLIST` `EXTRAARG` rules.
   - `NEWTABLE`: if `k != 0`, require `pc + 1 < code_len` and next op `EXTRAARG`.
   - `SETLIST`: if `k != 0`, require next op `EXTRAARG`.

6. **After arithmetic adjacency lines 125-153**: Add comparison/test adjacency.
   - For `EQ`, `LT`, `LE`, `EQK`, `EQI`, `LTI`, `LEI`, `GTI`, `GEI`, `TEST`, `TESTSET`:
     - require `pc + 1 < code_len`
     - require next op is `OP_JMP`.

7. **Lines 156-162 jump targets**:
   - Split by opcode:
     - `JMP`: target `pc + sj`
     - `FORLOOP`: target `pc - bx`
     - `FORPREP`: target `pc + bx + 1`
     - `TFORPREP`: target `pc + bx`
     - `TFORLOOP`: target `pc - bx`
   - Validate each target in `[0, code_len)`.

8. **Register-window checks lines 164-196**:
   - Add comments for open forms:
     - `CALL B==0`, `CALL C==0`
     - `RETURN B==0`
     - `SETLIST B==0`
   - Do not over-reject open forms yet; tests should assert they remain accepted if stack max assumptions are safe.

**Patterns**
- Every dispatch assumption gets a validator check.
- Invalid uses `invalid(code = ERR_RUNTIME)` except bad opcode.

**Danger zones**
- Do not treat `EXTRAARG` as executable standalone.
- Do not use `sBx` for `JMP`.

---

### `experiments/lua_interpreter_vm/src/regions_resume.lua` *(new)*

**Goal**: Make persisted resume integers pass through explicit suspended-control products and checked control protocols.

**Contents sketch**

Define regions:

1. `capture_frame_resume(frame; done(state: SuspendedControl))`
   - Copies:
     - `mode = frame.resume_mode`
     - `a/b/c = frame.resume_a/b/c`
     - `pc = frame.resume_pc`
     - `base = frame.resume_base`
     - `value = frame.resume_value`
     - `result_base = frame.result_base`
     - `wanted = frame.wanted`

2. `decode_resume_mode(mode: u16; normal, tailcall, pcall, xpcall, gettable_mm, settable_mm, binop_mm, unop_mm, len_mm, concat_mm, eq_mm, lt_mm, le_mm, call_mm, tforloop_call, native_cont, tbc_close, unknown)`
   - Use `switch mode do`.
   - Cases must use `@{RESUME_*}` constants, not literal numbers.
   - Default jumps `unknown(mode = mode)`.

3. `resume_after_return(...)`
   - Same continuation surface as existing `handle_return_mode`.
   - Parameters:
     ```lalin
     region resume_after_return(
       L: ptr(LuaThread), parent: ptr(Frame),
       first_result: index, nres: i32, state: SuspendedControl;
       normal: cont(...),
       ...
       oom: cont())
     ```
   - Move logic from old `handle_return_mode`.
   - Replace `ret_resume_*` reads with `state.*`.
   - Unsupported-but-known modes (`XPCALL`, `LEN_MM`, `CALL_MM`, `NATIVE_CONT`) must explicitly jump `error(ERR_RUNTIME)` in this milestone.

4. Optional helper:
   `clear_frame_resume(frame; done())` zeroes resume fields to normal/nil.

**Patterns**
- This file owns all switching on `Resume`.
- No numeric `case 4 then`; use constants.

**Danger zones**
- Preserve `handle_return_mode` continuation count/semantics via alias during migration.
- Do not change `Frame` layout yet.

---

### `experiments/lua_interpreter_vm/src/regions_call.lua`

**Goal**: Migrate return-resume handling to `SuspendedControl` without changing call/return spine.

**Edit blocks**

1. **Imports after line 4**:
   ```lua
   local resume_regions = require("experiments.lua_interpreter_vm.src.regions_resume")
   ```

2. **Lines 150-158 in `return_from_lua`**:
   - Before: captures individual `ret_resume_*`.
   - After: construct `SuspendedControl`:
     ```lalin
     let ret_state: SuspendedControl = {
         mode = frame.resume_mode,
         a = frame.resume_a,
         b = frame.resume_b,
         c = frame.resume_c,
         pc = frame.resume_pc,
         base = frame.resume_base,
         value = frame.resume_value,
         result_base = frame.result_base,
         wanted = frame.wanted
     }
     ```

3. **Lines 164-167 emit**:
   - Replace `emit handle_return_mode(... ret_* ...)`
   - With:
     ```lalin
     emit resume_after_return(L, parent, first_result, nres, ret_state; ...)
     ```

4. **Lines 232-363 old `handle_return_mode`**:
   - Remove full region body.
   - Replace Lua binding:
     ```lua
     local resume_after_return = resume_regions.resume_after_return
     local handle_return_mode = resume_after_return -- compatibility export
     ```

5. **Return table lines 365-371**:
   - Export:
     ```lua
     resume_after_return = resume_after_return,
     handle_return_mode = handle_return_mode,
     ```

**Patterns**
- Keep `prepare_call`, `return_from_lua`, `result_base` semantics unchanged.
- Parent frame cache reload remains in `vm_loop.lua`, not here.

**Danger zones**
- Do not use `parent.resume_mode`; return mode belongs to returning child frame.
- Do not change native `enter_native` signature in this milestone.

---

### `experiments/lua_interpreter_vm/src/init.lua`

**Goal**: Load new protocol/boundary modules.

**Edit blocks**

1. **After products line 8**:
   ```lua
   vm.bytecode = require("experiments.lua_interpreter_vm.src.bytecode")
   vm.compat = require("experiments.lua_interpreter_vm.src.compat")
   ```

2. **Before `regions_call` line 19**:
   ```lua
   vm.regions_resume = require("experiments.lua_interpreter_vm.src.regions_resume")
   vm.regions_native = require("experiments.lua_interpreter_vm.src.regions_native")
   ```

3. **Before `regions_gc` or after it**:
   ```lua
   vm.regions_gc_protocol = require("experiments.lua_interpreter_vm.src.regions_gc_protocol")
   ```

**Danger zones**
- `regions_resume` must load before `regions_call`.

---

### `experiments/lua_interpreter_vm/src/regions_native.lua` *(new)*

**Goal**: Define explicit native-result decoding boundary before actual native invocation is implemented.

**Contents sketch**
```lalin
region decode_native_result(result: ptr(NativeCallResult);
    returned: cont(nres: i32),
    yielded: cont(nres: i32),
    error: cont(err: Value),
    oom: cont(),
    stack_grow: cont(),
    invalid: cont())
```

Switch on `result.status` using `NativeResult` constants.

Also define:
```lalin
region classify_native_boundary(state: NativeBoundaryState; ...)
```
as a lightweight checked protocol if useful.

**Do not call host function pointers here yet.**

---

### `experiments/lua_interpreter_vm/src/regions_gc_protocol.lua` *(new)*

**Goal**: Add explicit GC/weak/finalizer/userdata protocol boundaries without implementing GC algorithm yet.

**Contents sketch**

Regions:

1. `decode_weak_mode(mode_flags: u8; none, weak_values, weak_keys, ephemeron, all_weak)`
2. `record_table_weak_state(G, t, mode_flags; recorded, invalid, oom)`
3. `classify_finalizer_state(state: u8; none, eligible, pending, running, done, invalid)`
4. `classify_userdata_payload(ud: ptr(UserData), payload: ptr(UserDataPayload); valid, invalid)`

**Patterns**
- These classify and route state; they do not sweep, allocate, or finalize yet.
- Unknown modes must have typed `invalid` exits, not default success.

---

### `experiments/lua_interpreter_vm/src/compat.lua` *(new)*

**Goal**: Record explicit compatibility frontiers for source, binary chunks, internal Proto, and native ABI.

**Contents sketch**
```lua
local const = require("experiments.lua_interpreter_vm.src.constants")

return {
  internal_proto_validator = "experiments.lua_interpreter_vm.src.validate.validate_proto",
  source_frontier = "experiments.lua_interpreter_vm.src.regions_compiler.compile_lua_source_into",
  binary_chunk_frontier = nil, -- unsupported until typed chunk reader exists
  native_abi_frontier = "NativeFunc/NativeCallResult",
  formats = const.CompatFormat,
  puc_oracle_only = true,
}
```

**Danger zones**
- Do not add fake binary chunk support.

---

### `experiments/lua_interpreter_vm/src/op/protocols.lua` *(new)*

**Goal**: Start replacing stringly opcode continuation boilerplate with named protocol descriptors.

**Contents sketch**
```lua
local P = {}

P.conts = {
  next = "next: cont(frame: ptr(Frame), pc: index, base: index, top: index)",
  do_jump = "...",
  enter_lua = "...",
  enter_native = "...",
  yielded = "...",
  error = "...",
  oom = "...",
}

P.protocols = {
  next_only = {"next"},
  table = {"next","enter_lua","enter_native","yielded","error","oom"},
  compare = {...},
  call = {...},
  ret = {...},
  mmbin = {...},
}

function P.signature(name)
  -- concatenate from named descriptors only
end

return P
```

**Pattern**
- This first milestone may still produce strings internally, but op modules must consume named protocols, not ad hoc raw string constants.

---

### `experiments/lua_interpreter_vm/src/op/_init.lua`

**Goal**: Route shared opcode continuation signatures through named protocol descriptors.

**Edit blocks**

1. **After imports line 4**:
   ```lua
   local protocols = require("experiments.lua_interpreter_vm.src.op.protocols")
   ```

2. **Lines 22-139**:
   - Replace direct definitions of:
     - `next_only`
     - `TABLE_CONTS`
     - `CMP_CONTS`
     - `CALL_CONTS`
     - `RET_CONTS`
     - `MMBIN_CONTS`
     - `ARITH_CONT`
   - With:
     ```lua
     local next_only = "\n               " .. protocols.signature("next_only")
     local TABLE_CONTS = protocols.signature("table")
     ...
     ```
   - Keep `TABLE_GET_MM_BLOCKS` and `TABLE_SET_MM_BLOCKS` unchanged for milestone 1, but add TODO comment:
     ```lua
     -- Milestone 2: replace these shared block strings with lalin.stmts builders.
     ```

3. **Return table lines 143-156**:
   - Add:
     ```lua
     protocols = protocols,
     ```

**Danger zones**
- Do not edit all opcode modules in this milestone.
- Preserve exact continuation names expected by `opcodes.lua` emit templates.

---

### `experiments/lua_interpreter_vm/src/regions_stack.lua`

**Goal**: Mark frame-push resume storage as ABI storage and prepare later migration.

**Edit blocks**

1. **Lines 34-60 `frame_push`**:
   - Do not change signature yet.
   - Add comment before `f.resume_mode = resume_mode`:
     ```lalin
     -- Stored suspended-control discriminant. Callers must pass a value
     -- accepted by regions_resume.decode_resume_mode; return paths decode it
     -- through SuspendedControl rather than switching on raw fields here.
     ```

**Danger zones**
- No signature change; too many callers.

---

### `experiments/lua_interpreter_vm/src/regions_metamethod.lua`

**Goal**: Mark metamethod resume setup as suspended-control write, not arbitrary integer mutation.

**Edit blocks**

1. **Lines 130-140 `prepare_metamethod_call`**:
   - Add comment above `frame.resume_mode = resume_mode`.
   - Do not change logic yet.

**Later milestone**
- Replace `resume_mode: u16` param with `state: SuspendedControl`.

---

### `experiments/lua_interpreter_vm/src/vm_loop.lua`

**Goal**: Preserve proven VM spine while documenting native-boundary gap.

**Edit blocks**

1. **Lines 128-137 `do_native`/`native_ret`**:
   - No signature change yet.
   - Add comment before `native_ret`:
     ```lalin
     -- Milestone 1 keeps native invocation fail-loud; later native_ret must route
     -- through regions_native.decode_native_result and then return_from_lua-style
     -- result_base adjustment.
     ```

**Danger zones**
- Do not alter `cont_resume_parent` frame-cache reload.

---

## New Tests

### `experiments/lua_interpreter_vm/tests/test_vm_bytecode_decoder_contract.lua`

**Purpose**: Verify Lua 5.5 decode facts independently of opcode semantics.

**Test cases**
- `sJ` encodes/decodes 25-bit signed jump.
- `sC` decodes as `C - 127`.
- `EXTRAARG` uses Ax, not Bx.
- `NEWTABLE`/`SETLIST` decode `vB/vC`.
- `FORLOOP/FORPREP/TFORLOOP/TFORPREP` use Bx.
- Compare against helper encoders copied from vendored facts, not PUC code.

---

### `experiments/lua_interpreter_vm/tests/test_vm_resume_protocol_contract.lua`

**Purpose**: Ensure every stored `Resume` discriminant has explicit control coverage.

**Test cases**
- Compile wrapper around `regions_resume.decode_resume_mode`.
- For each `0 <= mode < const.Resume.N`, assert it reaches the named expected continuation.
- Unknown mode `const.Resume.N` reaches `unknown`.
- Compile wrapper around `resume_after_return` for current supported modes:
  - `NORMAL`
  - `TAILCALL`
  - `PCALL`
  - table/binop/unop/compare/concat/tfor/tbc modes
- Unsupported known modes return `ERR_RUNTIME`, not silent success.

---

### `experiments/lua_interpreter_vm/tests/test_vm_product_refoundation.lua`

**Purpose**: Assert new explicit data products exist without changing legacy layout.

**Checks**
- Existing:
  - `Frame` still 18 fields.
  - `LuaThread` still 22 fields.
  - `Proto` still 19 fields.
- New:
  - `SuspendedControl`
  - `NativeBoundaryState`
  - `WeakTableState`
  - `FinalizerQueue`
  - `UserDataPayload`
  - `ProtectedCallState`
  - `CoroutineSuspendState`
- Constants:
  - `WeakModeFlag`
  - `FinalizerState`
  - `UserDataFlag`
  - `CompatFormat`

---

### Update `experiments/lua_interpreter_vm/tests/test_vm_smoke.lua`

**Edit blocks**

1. **Line 25 struct count**:
   - Before:
     ```lua
     ok(string.format("%d struct definitions", struct_count), struct_count == 43)
     ```
   - After:
     ```lua
     ok(string.format("%d struct definitions", struct_count), struct_count >= 50)
     ```
   - Prefer named product assertions over exact count.

2. **After existing `NativeCallResult exists` line ~36**:
   Add assertions for new products.

3. **After `handle_return_mode has 15 continuations` line ~30**:
   Add:
   ```lua
   ok("decode_resume_mode exists", vm.regions_resume.decode_resume_mode ~= nil)
   ok("resume_after_return compatibility alias", vm.regions_call.handle_return_mode == vm.regions_call.resume_after_return)
   ```

---

### Update `experiments/lua_interpreter_vm/tests/test_vm_validation_contract.lua`

**Edits**
- Add helpers:
  - `set_Ax(op, ax)`
  - `set_sJ(op, sj)`
  - `set_vABC(op, a, vb, vc, k)`
- Replace `set_AsBx` for `JMP` tests with `set_sJ`.
- Add invalid tests:
  - comparison not followed by `JMP`
  - `TEST` not followed by `JMP`
  - `NEWTABLE k=1` missing `EXTRAARG`
  - `SETLIST k=1` missing `EXTRAARG`
  - `LOADKX` Ax constant out of bounds
- Add valid tests:
  - `NEWTABLE k=1` followed by `EXTRAARG`
  - `JMP sJ` in range
  - `FORLOOP Bx` target in range

---

## Order of Operations

1. Add `bytecode.lua`.
2. Update `opcodes.lua` decode helpers and operand modes.
3. Update `validate.lua` to match decoder.
4. Add/update bytecode and validation tests; run:
   - `luajit experiments/lua_interpreter_vm/tests/test_vm_bytecode_decoder_contract.lua`
   - `luajit experiments/lua_interpreter_vm/tests/test_vm_validation_contract.lua`
5. Add constants/product sidecars in `constants.lua` and `products.lua`.
6. Add `regions_resume.lua`.
7. Wire `regions_resume` through `init.lua`.
8. Migrate `regions_call.return_from_lua` from raw resume fields to `SuspendedControl`.
9. Run:
   - `luajit experiments/lua_interpreter_vm/tests/test_vm_resume_protocol_contract.lua`
   - `luajit experiments/lua_interpreter_vm/tests/test_vm_call_frame_contract.lua`
10. Add `regions_native.lua`, `regions_gc_protocol.lua`, `compat.lua`.
11. Add `op/protocols.lua` and route `_init.lua` continuation signatures through it.
12. Update smoke/product tests.
13. Run full VM slice:
   - `luajit experiments/lua_interpreter_vm/tests/test_vm_smoke.lua`
   - `luajit experiments/lua_interpreter_vm/tests/test_vm_opcode_semantics.lua`
   - `luajit experiments/lua_interpreter_vm/tests/test_vm_error_contract.lua`
   - `luajit experiments/lua_interpreter_vm/tests/test_vm_abi_contract.lua`
   - `luajit experiments/lua_interpreter_vm/tests/test_parser_compile.lua`

---

## Testing Strategy

- After decoder edits: only validator/decoder tests first.
- After resume-product migration: call-frame contract must still pass; this proves `result_base` and frame-cache reload survived.
- After product additions: smoke/product tests must confirm existing layouts unchanged.
- After opcode protocol descriptor changes: run opcode semantics and smoke compile tests.
- Do not enable SponJIT or change `contract.lua` gates in this milestone.

---

## Pattern Memo

- Preserve existing VM spine: `vm_resume → vm_loop → dispatch_instruction`.
- Do not alter `Frame`, `LuaThread`, or `Proto` layout in milestone 1.
- All `Resume` switching moves to `regions_resume.lua`.
- Use constants in `switch` cases, never literal resume numbers.
- `validate_proto` and dispatch decode must share Lua 5.5 operand facts.
- `oom` must not be used for newly introduced “unsupported semantic state”; use explicit `invalid`, `unknown`, or `error` continuations.
- SponJIT remains separate and disabled.

## Edit-planner Output — 2026-05-30 08:16:28

### Precondition Checks

Before edits begin:

1. Confirm `experiments/lua_interpreter_vm/src/contract.lua` still has `sponjit_allowed = false`.
2. Run current baseline tests:
   - `luajit experiments/lua_interpreter_vm/tests/test_vm_smoke.lua`
   - `luajit experiments/lua_interpreter_vm/tests/test_vm_validation_contract.lua`
   - `luajit experiments/lua_interpreter_vm/tests/test_vm_call_frame_contract.lua`
3. Verify current anchors:
   - `products.lua`: core structs start at line 8; `Frame` currently line 70; `GlobalState` line 76; `LuaThread` line 79.
   - `constants.lua`: `Resume` line 123, `NativeResult` line 151, `GCState` line 183.
   - `opcodes.lua`: decode helpers line 25; dispatch region line 563; metadata line 694.
   - `validate.lua`: decode loop line 35; jump validation line 156.
   - `regions_call.lua`: `prepare_call` line 18; `call_native` line 111; `return_from_lua` line 133; `handle_return_mode` line 232.
   - `vm_loop.lua`: frame-cache reload in `cont_resume_parent` line 112.

---

## Files to Modify

### `experiments/lua_interpreter_vm/src/constants.lua`

**Goal**: Make all persisted VM discriminants explicit final protocol constants.

**Edit blocks**

1. **Lines 123-139**: Modify `Resume`.
   - Keep existing numeric values for semantic continuity.
   - Rename comments to define these as persisted `ResumeKind` values.
   - Add missing final resume cases if needed:
     ```lua
     Resume.FINALIZER_CALL = 17
     Resume.COROUTINE_RESUME = 18
     Resume.COROUTINE_YIELD = 19
     Resume.N = 20
     ```

2. **After line 151 `NativeResult`**: Extend native result protocol:
   ```lua
   NativeResult.OK = 0
   NativeResult.ERROR = 1
   NativeResult.YIELD = 2
   NativeResult.OOM = 3
   NativeResult.STACK_GROW = 4
   NativeResult.REENTER_LUA = 5
   NativeResult.INVALID = 6
   ```

3. **After `ThreadFlag` lines 170-174**: Add final protocol enums:
   ```lua
   local TableFlag = {}
   TableFlag.HAS_METATABLE = 1
   TableFlag.WEAK_VALUES = 2
   TableFlag.WEAK_KEYS = 4
   TableFlag.EPHEMERON = 8
   TableFlag.ALL_WEAK = 16
   TableFlag.FINALIZER_CANDIDATE = 32

   local FinalizerState = {}
   FinalizerState.NONE = 0
   FinalizerState.ELIGIBLE = 1
   FinalizerState.PENDING = 2
   FinalizerState.RUNNING = 3
   FinalizerState.DONE = 4

   local UserDataFlag = {}
   UserDataFlag.OWNS_PAYLOAD = 1
   UserDataFlag.HAS_USER_VALUES = 2
   UserDataFlag.FINALIZABLE = 4
   UserDataFlag.ALIGNED = 8

   local CompatFormat = {}
   CompatFormat.INTERNAL_PROTO = 0
   CompatFormat.LUA55_SOURCE = 1
   CompatFormat.LUA55_BINARY_CHUNK = 2
   ```

4. **Lines 183-187 `GCState`**: Replace with final GC phase set:
   ```lua
   GCState.PAUSE = 0
   GCState.PROPAGATE = 1
   GCState.ATOMIC = 2
   GCState.SWEEP_STRINGS = 3
   GCState.SWEEP_OBJECTS = 4
   GCState.CLEAR_WEAK = 5
   GCState.FINALIZE = 6
   ```

5. **Return table lines 195-214**: Export new tables:
   ```lua
   TableFlag = TableFlag,
   FinalizerState = FinalizerState,
   UserDataFlag = UserDataFlag,
   CompatFormat = CompatFormat,
   ```

**Patterns to enforce**
- Numeric constants are storage/ABI discriminants only.
- All switching over these constants must happen in protocol regions, never ad hoc in opcode handlers.

**Danger zones**
- Do not renumber existing opcodes or tags.
- Keep `Op.SETTI = 17` alias.

---

### `experiments/lua_interpreter_vm/src/products.lua`

**Goal**: Replace implicit runtime fields with final explicit VM products.

**Edit blocks**

1. **Lines 8-23**: Keep `Value`, `GCHeader`, `Node`, `String`, `Instr`, `LocVar`, `UpValDesc`, but update comments:
   - `Value` remains `{ tag, aux, bits }` as final ABI storage.
   - Consumers must decode through regions in `regions_value.lua`.

2. **Replace line 17 `Table` struct** with final table product:
   ```lalin
   struct Table
       gc: GCHeader
       flags: u32
       array_len: index
       array_cap: index
       array: ptr(Value)
       node_mask: u32
       node_count: index
       nodes: ptr(Node)
       lastfree: ptr(Node)
       metatable: ptr(Table)
       shape_epoch: u32
       weak_next: ptr(GCHeader)
       finalizer_state: u8
       reserved: u8
   end
   ```

3. **After line 38 `NativeFunc`**: Replace `NativeCallResult` with final ABI records:
   ```lalin
   struct NativeCallContext
       func_slot: index
       nargs: i32
       wanted: i32
       result_base: index
       stack_top: index
       yieldable: u8
       reserved: u8
   end

   struct NativeCallResult
       status: u8
       nresults: i32
       err: Value
       stack_needed: index
       continuation: ptr(u8)
   end
   ```

4. **Replace line 46 `UserData`**:
   ```lalin
   struct UserData
       gc: GCHeader
       metatable: ptr(Table)
       env: ptr(Table)
       len: index
       data: ptr(u8)
       align: u32
       flags: u8
       finalizer_state: u8
       user_values: ptr(Value)
       user_values_len: index
   end
   ```

5. **After line 65 `Allocator`**: Add final control-state products:
   ```lalin
   struct ResumeState
       kind: u16
       a: u16
       b: u16
       c: u16
       pc: index
       base: index
       result_base: index
       call_top: index
       wanted: i32
       value: Value
       errfunc_slot: index
   end

   struct ProtectedFrame
       status: u8
       flags: u8
       saved_frame_count: index
       frame_index: index
       stack_top: index
       handler_slot: index
       errfunc_slot: index
       resume: ResumeState
       previous: ptr(ProtectedFrame)
   end

   struct CoroutineState
       caller: ptr(LuaThread)
       nresults: i32
       resume: ResumeState
   end

   struct FinalizerQueue
       eligible: ptr(GCHeader)
       pending: ptr(GCHeader)
       running: ptr(GCHeader)
   end
   ```

6. **Replace old `ProtectedFrame` line 68** with the new definition above; remove fields `resume_mode`.

7. **Replace line 70 `Frame`**:
   ```lalin
   struct Frame
       closure: Value
       base: index
       top: index
       pc: index
       wanted: i32
       tailcalls: i32
       result_base: index
       call_top: index
       resume: ResumeState
       yieldable: u8
       flags: u8
       reserved: u16
   end
   ```

8. **Replace line 76 `GlobalState`**:
   - Preserve allocator, registry, mainthread, string table, tmname, ABI fields.
   - Add final GC/weak/finalizer lists:
     ```lalin
     allgc: ptr(GCHeader)
     gray: ptr(GCHeader)
     grayagain: ptr(GCHeader)
     weak_values: ptr(GCHeader)
     weak_keys: ptr(GCHeader)
     ephemeron: ptr(GCHeader)
     all_weak: ptr(GCHeader)
     finalizers: FinalizerQueue
     sweep_cursor: ptr(ptr(GCHeader))
     currentwhite: u8
     gcstate: u8
     totalbytes: index
     estimate: index
     threshold: index
     gcdebt: index
     gcpause: i32
     gcstepmul: i32
     panic: Value
     vm_abi_version: u32
     native_abi_version: u32
     ```

9. **Replace line 79 `LuaThread`**:
   - Remove raw resume storage from `Frame` only; keep thread fields.
   - Add:
     ```lalin
     coroutine: CoroutineState
     ```
   - Keep `protected_top`, `tbc_head`, `yieldable`, `nonyieldable`.

10. **Return table lines 88-118**: Export all new products.

**Patterns to enforce**
- No temporary compatibility fields for `resume_mode/resume_a/...`.
- Every persisted suspended-control value is stored in `ResumeState`.
- Products are Lalin-native; do not copy PUC field names such as `finobj/tobefnz`.

**Danger zones**
- All FFI tests must be updated for final struct layouts.
- `Frame.resume` replaces all raw frame resume fields across the codebase.

---

### `experiments/lua_interpreter_vm/src/bytecode.lua` *(new)*

**Goal**: Single final Lua 5.5 instruction decode oracle for dispatch, validator, compiler, chunk loader, and tests.

**Contents**
- Export constants:
  - `SIZE_OP = 7`
  - `POS_A = 7`
  - `POS_K = 15`
  - `POS_B = 16`
  - `POS_C = 24`
  - `POS_VB = 16`
  - `POS_VC = 22`
  - `POS_BX = 15`
  - `POS_AX = 7`
  - `OFFSET_SBX = 65535`
  - `OFFSET_SJ = 16777215`
  - `OFFSET_SC = 127`
- Export `exprs(expr)` returning Lalin expressions:
  - `OP`, `A`, `K`, `B`, `C`, `VB`, `VC`, `BX`, `SBX`, `AX`, `SJ`, `SC`.
- Export Lua-side encoders/decoders for tests:
  - `decode_word(word)`
  - `encode_ABC(op,a,b,c,k)`
  - `encode_ABx(op,a,bx)`
  - `encode_AsBx(op,a,sbx)`
  - `encode_Ax(op,ax)`
  - `encode_sJ(op,sj)`
  - `encode_AvBCk(op,a,vb,vc,k)`

**Danger zones**
- `JMP` uses `sJ`, not `sBx`.
- `LOADKX` / `EXTRAARG` use `Ax`.
- `ADDI`, `EQI`, `LTI`, `LEI`, `GTI`, `GEI` use `sC`.

---

### `experiments/lua_interpreter_vm/src/compat.lua` *(new)*

**Goal**: Define final compatibility frontiers.

**Contents**
```lua
return {
    formats = const.CompatFormat,
    internal_proto_validator = validate.validate_proto,
    source_frontier = compiler.compile_lua_source_into,
    binary_chunk_frontier = chunk.load_lua55_binary_chunk,
    native_abi_frontier = native.decode_native_result,
    puc_oracle_only = true,
}
```

**Patterns**
- This file records boundaries only; it does not perform decoding itself.

---

### `experiments/lua_interpreter_vm/src/init.lua`

**Goal**: Load final protocol modules in dependency order.

**Edit blocks**

1. **After line 7 `products`**:
   ```lua
   vm.bytecode = require("experiments.lua_interpreter_vm.src.bytecode")
   ```

2. **Before current `regions_value` line 9**:
   ```lua
   vm.regions_numeric = require("experiments.lua_interpreter_vm.src.regions_numeric")
   ```

3. **Before `regions_stack` line 10**:
   ```lua
   vm.regions_resume = require("experiments.lua_interpreter_vm.src.regions_resume")
   vm.regions_allocator = require("experiments.lua_interpreter_vm.src.regions_allocator")
   ```

4. **Around lines 11-18**: Add:
   ```lua
   vm.regions_native = require("experiments.lua_interpreter_vm.src.regions_native")
   vm.regions_userdata = require("experiments.lua_interpreter_vm.src.regions_userdata")
   vm.regions_weak = require("experiments.lua_interpreter_vm.src.regions_weak")
   vm.regions_chunk = require("experiments.lua_interpreter_vm.src.regions_chunk")
   ```

5. **After compiler line 32**:
   ```lua
   vm.compat = require("experiments.lua_interpreter_vm.src.compat")
   ```

**Danger zones**
- `regions_resume` must load before `regions_call`.
- `regions_allocator` must load before stack/table/string/upvalue/gc users.

---

### `experiments/lua_interpreter_vm/src/validate.lua`

**Goal**: Make `validate_proto` exactly match final dispatch assumptions.

**Edit blocks**

1. **Imports lines 1-4**: Add:
   ```lua
   local bytecode = require("experiments.lua_interpreter_vm.src.bytecode")
   ```

2. **Lines 35-44 decode block**: Replace with full decode:
   ```lalin
   let op: u16 = as(u16, word & 127)
   let a: u16 = as(u16, (word >> 7) & 255)
   let k: u8 = as(u8, (word >> 15) & 1)
   let b: u16 = as(u16, (word >> 16) & 255)
   let c: u16 = as(u16, (word >> 24) & 255)
   let vb: u16 = as(u16, (word >> 16) & 63)
   let vc: u16 = as(u16, (word >> 22) & 1023)
   let bx: u32 = (word >> 15) & 131071
   let sbx: i32 = as(i32, bx) - 65535
   let ax: u32 = (word >> 7) & 33554431
   let sj: i32 = as(i32, ax) - 16777215
   let sc: i32 = as(i32, c) - 127
   ```

3. **Lines 56-62 `EXTRAARG`**:
   - Replace previous-only-`LOADKX` check with:
     - valid after `LOADKX`
     - valid after `NEWTABLE` when previous `k != 0`
     - valid after `SETLIST` when previous `k != 0`
     - invalid otherwise.

4. **Lines 99-110 `LOADKX`**:
   - Use `extra_ax = (extra_word >> 7) & 33554431`.
   - Check `extra_ax < constants_len`.

5. **After `LOADKX` validation**:
   - Add `NEWTABLE` validation:
     - if `k != 0`, next opcode must be `EXTRAARG`.
     - validate decoded `vB/vC` and computed allocation sizes against max table limits.
   - Add `SETLIST` validation:
     - if `k != 0`, next opcode must be `EXTRAARG`.
     - if `b != 0`, validate source register window `A+1 .. A+B`.

6. **Lines 125-153 arithmetic adjacency**:
   - Keep `MMBIN*` adjacency checks.
   - Add event compatibility:
     - `MMBIN.C` must be valid `TM` event for previous primitive op.
     - `MMBINI/MMBINK` must match immediate/constant primitive source.

7. **After arithmetic adjacency**:
   - Add comparison/test adjacency:
     - `EQ/LT/LE/EQK/EQI/LTI/LEI/GTI/GEI/TEST/TESTSET` require `pc+1` opcode `JMP`.

8. **Lines 156-162 jump validation**:
   - Replace unified `sbx` target with:
     - `JMP`: `pc + sj`
     - `FORLOOP`: `pc - bx`
     - `FORPREP`: `pc + bx + 1`
     - `TFORPREP`: `pc + bx`
     - `TFORLOOP`: `pc - bx`

9. **Lines 164-196 register-window validation**:
   - Complete all opcode-specific register bounds:
     - open call forms `B==0/C==0`
     - return open forms `B==0`
     - `VARARG/GETVARG`
     - `CLOSE/TBC`
     - `TFORCALL/TFORLOOP`
     - `SETLIST B==0`
   - Accepted open forms must be justified by stack/top invariants, not rejected blindly.

**Patterns**
- Validator owns trust-boundary facts.
- Dispatch must not compensate for invalid bytecode.

**Danger zones**
- Never validate `JMP` using `sBx`.
- Never treat `EXTRAARG` as executable standalone.

---

### `experiments/lua_interpreter_vm/src/opcodes.lua`

**Goal**: Final dispatch uses centralized bytecode facts and named opcode protocols.

**Edit blocks**

1. **Imports lines 5-8**:
   ```lua
   local bytecode = require("experiments.lua_interpreter_vm.src.bytecode")
   local protocols = require("experiments.lua_interpreter_vm.src.op.protocols")
   ```

2. **Lines 25-41 decode helpers**:
   - Replace all local bit expressions with:
     ```lua
     local D = bytecode.exprs(expr)
     local A, B, C, K = D.A, D.B, D.C, D.K
     local VB, VC = D.VB, D.VC
     local BX, SBX, AX, SJ, SC = D.BX, D.SBX, D.AX, D.SJ, D.SC
     ```

3. **Argument builders lines 39-47**:
   - Change `args(a,b,c,k,bx,sbx)` to include final decoded operands:
     ```lua
     args(a,b,c,k,bx,sbx,ax,sj,sc,vb,vc)
     ```
   - Final `H` protocol in opcode handlers must receive all decoded operands, not overload `sbx` for immediates.

4. **Inline arms lines 173-520**:
   - Either remove hot inline bodies or rewrite them to call the same final semantic regions used by handlers.
   - Allowed inline arms only for semantics that require no hidden fallback:
     - `MOVE`
     - `LOADK`
     - `LOADNIL`
     - boolean loads
     - `NOT`
   - Arithmetic inline arms must be removed unless they emit `regions_numeric` and preserve `MMBIN*` failure protocol.

5. **`LOADKX` inline line 224**:
   - Use `Ax`.

6. **`ADDI` inline line 286**:
   - Use `SC`.

7. **`JMP` inline line 410**:
   - Use `SJ`.

8. **Emit arm table lines 522-660**:
   - `NEWTABLE` and `SETLIST`: pass `VB/VC/K/AX`.
   - `JMP`: pass `SJ`.
   - immediate comparisons: pass `SC`.
   - `FORLOOP/FORPREP/TFORPREP/TFORLOOP`: pass `BX`.

9. **Dispatch region lines 563-676**:
   - Preserve final spine continuations:
     - `next`
     - `do_jump`
     - `resume_parent`
     - `enter_lua`
     - `enter_native`
     - `returned`
     - `yielded`
     - `error`
     - `oom`
   - Change `enter_native` continuation to pass `ctx: NativeCallContext`, not raw `resume_mode`.

10. **Metadata lines 694-744**:
   - Final modes:
     - `NEWTABLE`: `AvBCk`
     - `SETLIST`: `AvBCk`
     - `JMP`: `sJ`
     - `EXTRAARG`: `Ax`
     - `FORLOOP/FORPREP/TFORPREP/TFORLOOP`: `ABx`
     - immediate ops: `AsC`/`sC` as appropriate.

**Danger zones**
- Do not add a wildcard opcode arm.
- Do not let dispatch decode differently from validator.

---

### `experiments/lua_interpreter_vm/src/op/protocols.lua` *(new)*

**Goal**: Final named opcode continuation protocol builder.

**Contents**
- Define protocol descriptors as Lua tables, not freeform strings:
  - `next_only`
  - `table_access`
  - `compare`
  - `call`
  - `return`
  - `mmbin`
  - `loop`
  - `close`
- Each descriptor lists:
  - parameter list
  - continuation list
  - allowed adapter blocks.
- Export:
  ```lua
  P.handler_params()
  P.signature(protocol_name)
  P.emit(handler, protocol_name, args)
  ```
- `signature` is the only place continuation text is assembled.

**Patterns**
- Opcode modules must consume named protocol descriptors only.
- No module may define its own continuation signature string.

---

### `experiments/lua_interpreter_vm/src/op/_init.lua`

**Goal**: Remove ad hoc continuation fragments from opcode modules.

**Edit blocks**

1. **Lines 1-4**: Require `op.protocols`.

2. **Line 18 `H`**:
   - Replace with `protocols.handler_params()` including final operands:
     ```lalin
     a,b,c,k,bx,sbx,ax,sj,sc,vb,vc
     ```

3. **Lines 21-139**:
   - Delete `TABLE_CONTS`, `CMP_CONTS`, `CALL_CONTS`, `RET_CONTS`, `MMBIN_CONTS`, `ARITH_CONT`, and shared block strings.
   - Replace exports with protocol lookup:
     ```lua
     local P = protocols
     ```

4. **Return table lines 143-156**:
   - Export `P`, `R`, `VALS`, and `H`.

**Danger zones**
- Do not leave `TABLE_GET_MM_BLOCKS` / `TABLE_SET_MM_BLOCKS` as hidden control blocks.
- Metamethod setup must be in `regions_metamethod.lua`, not copied into opcode strings.

---

### `experiments/lua_interpreter_vm/src/regions_resume.lua` *(new)*

**Goal**: Sole owner of persisted suspended-control decoding and resumption.

**Required regions**

1. `init_resume(kind, pc, base, result_base, call_top, wanted; done(state: ResumeState))`

2. `decode_resume_kind(state: ResumeState; normal, tailcall, pcall, xpcall, gettable_mm, settable_mm, binop_mm, unop_mm, len_mm, concat_mm, eq_mm, lt_mm, le_mm, call_mm, tforloop_call, native_cont, tbc_close, finalizer_call, coroutine_resume, coroutine_yield, unknown)`

3. `resume_after_return(L, parent, first_result, nres, state; normal, resume_gettable_mm, resume_settable_mm, resume_binop_mm, resume_unop_mm, resume_len_mm, resume_compare_mm, resume_concat_mm, resume_call_mm, resume_tforloop, resume_tbc_close, resume_finalizer, pcall_success, pcall_failure, yielded, error, oom)`

4. `resume_after_yield(L, state; enter_lua, enter_native, returned, yielded, error, oom)`

5. `clear_resume(frame; done())`

**Patterns**
- All `switch state.kind` cases use `@{RESUME_*}` constants.
- Unknown resume kinds route to `unknown` or `error`, never silently to normal return.

---

### `experiments/lua_interpreter_vm/src/regions_numeric.lua` *(new)*

**Goal**: Centralize Lua numeric lattice and primitive arithmetic/comparison behavior.

**Required regions**
- `to_integer_exact(v; integer, not_integer)`
- `to_float_number(L, v; number, not_number, oom)`
- `arith_binary(L, lhs, rhs, event; int_result, float_result, call_mm, type_error, oom)`
- `arith_immediate(L, lhs, sc, event; int_result, float_result, call_mm, type_error, oom)`
- `arith_constant(L, lhs, rhs, event; int_result, float_result, call_mm, type_error, oom)`
- `bitwise_binary`
- `unary_numeric`
- `primitive_equal`
- `primitive_lt`
- `primitive_le`

**Required semantics**
- Exact int/float equality.
- Mixed int/float arithmetic where Lua requires it.
- String-to-number coercion where required by arithmetic.
- Correct `MOD`, `IDIV`, `POW`.
- Signed `sC`.

---

### `experiments/lua_interpreter_vm/src/regions_value.lua`

**Goal**: Make value tag decoding final and delegate numeric behavior.

**Edit blocks**

1. **Lines 26-47**:
   - Keep simple tag split regions.

2. **Lines 52-84 `value_to_string`**:
   - Replace runtime-error path with number/string formatting through `regions_string`.

3. **Lines 105-140 `value_raw_equal`**:
   - Replace tag-only inequality with exact Lua int/float equality by emitting `primitive_equal`.

4. **Lines 143-156 `value_equal`**:
   - Add metamethod path for tables/userdata with same `__eq`.

5. **Lines 159-221 comparisons**:
   - Delegate to `regions_numeric` and `regions_metamethod`.
   - Preserve typed `call_mm` exits.

**Danger zones**
- Raw equality and metamethod equality are distinct.
- Strings compare lexicographically by bytes.

---

### `experiments/lua_interpreter_vm/src/regions_allocator.lua` *(new)*

**Goal**: Final explicit allocator boundary for all runtime growth.

**Required regions**
- `alloc_bytes(G, size, align; ok(ptr: ptr(u8)), step_required, oom)`
- `realloc_bytes(G, old, old_size, new_size, align; ok(ptr: ptr(u8)), step_required, oom)`
- `free_bytes(G, ptr, size, align; done())`
- `alloc_object(G, size, tt; ok(obj), step_required, oom)`
- `grow_value_array`
- `grow_frame_array`
- `grow_node_array`
- `grow_protected_frame`

**Implementation rule**
- Calls a typed extern shim only, e.g.:
  ```lalin
  extern lalin_lua_alloc(alloc: ptr(Allocator), old: ptr(u8), old_size: index, new_size: index, align: u32) -> ptr(u8)
  ```
- No direct libc/malloc assumptions.

---

### `experiments/lua_interpreter_vm/src/regions_stack.lua`

**Goal**: Final stack/frame growth and frame initialization using `ResumeState`.

**Edit blocks**

1. **Lines 12-30 `stack_check`**:
   - Replace overflow-on-growth with `grow_value_array`.
   - `overflow` only when `needed_top > MAX_STACK_SIZE`.

2. **Lines 33-67 `frame_push`**:
   - Signature becomes:
     ```lalin
     region frame_push(L, closure, base, top, result_base, call_top,
                       wanted, resume: ResumeState, yieldable; ...)
     ```
   - Initialize `f.resume = resume`.
   - No raw `resume_mode/resume_pc` fields.

3. **Lines 105-132 `adjust_varargs`**:
   - Implement final vararg reshaping:
     - fixed params copied into frame base.
     - hidden vararg area represented by `ProtoFlag`.
     - open result top updated explicitly.

**Danger zones**
- `result_base` remains caller-owned.
- Never use parent `base` as implicit result destination.

---

### `experiments/lua_interpreter_vm/src/regions_call.lua`

**Goal**: Final call/return engine over `ResumeState`, native context, and metamethod `__call`.

**Edit blocks**

1. **Lines 18-95 `prepare_call`**:
   - Signature replaces `resume_mode/caller_pc` with `resume: ResumeState`.
   - Non-callable values emit `try_call_metamethod`.
   - Lua closure path calls `frame_push(..., resume, ...)`.
   - Native path builds `NativeCallContext`.

2. **Lines 98-108 `try_call_metamethod`**:
   - Implement `__call` lookup via `regions_metamethod.get_metamethod`.
   - Insert metamethod at `func_slot`, shift original function/value as first arg.

3. **Lines 111-130 `call_native`**:
   - Move body to `regions_native.invoke_native`.
   - `regions_call.call_native` can re-export final native region.

4. **Lines 133-230 `return_from_lua`**:
   - Capture `let ret_state: ResumeState = frame.resume`.
   - Pop child.
   - Emit `resume_after_return`.

5. **Lines 232-363 `handle_return_mode`**:
   - Remove raw mode region.
   - Export:
     ```lua
     handle_return_mode = resume_regions.resume_after_return
     resume_after_return = resume_regions.resume_after_return
     ```

**Danger zones**
- Returning child owns resume state.
- Parent frame-cache reload remains in `vm_loop.lua`.

---

### `experiments/lua_interpreter_vm/src/regions_native.lua` *(new)*

**Goal**: Final native ABI boundary.

**Required regions**
- `invoke_native(L, cl, ctx: NativeCallContext; returned, yielded, error, oom, stack_grow)`
- `decode_native_result(result: ptr(NativeCallResult); returned, yielded, error, oom, stack_grow, invalid)`
- `finish_native_return(L, ctx, nres; returned, oom)`
- `resume_native_continuation`

**Final behavior**
- Validate `NativeFunc.abi_version`.
- Call typed extern shim:
  ```lalin
  extern lalin_lua_native_invoke(L: ptr(LuaThread), cl: ptr(CClosure), ctx: ptr(NativeCallContext), out: ptr(NativeCallResult)) -> i32
  ```
- Map `NativeResult` to VM continuations.
- No hidden exceptions, errno, host longjmp, or implicit scheduler behavior.

---

### `experiments/lua_interpreter_vm/src/vm_loop.lua`

**Goal**: Preserve final VM spine and route native/yield/error through final protocols.

**Edit blocks**

1. **Lines 76-125**:
   - Keep `vm_loop → dispatch_instruction → loop`.
   - Preserve frame-cache reload in `cont_resume_parent`.

2. **Lines 128-137 `do_native/native_ret`**:
   - Change `do_native` signature to receive `ctx: NativeCallContext`.
   - Emit `regions_native.invoke_native`.
   - `native_ret` must adjust results via `finish_native_return` and resume parent/loop according to `ctx.resume`.

3. **Lines 146-159 error path**:
   - Keep `raise_code_error`.
   - Ensure caught protected frames resume through `ResumeState`.

**Danger zones**
- Do not remove cached `code/constants` reload on frame switch.
- Do not let native calls bypass `result_base`.

---

### `experiments/lua_interpreter_vm/src/regions_metamethod.lua`

**Goal**: Final metamethod lookup/dispatch protocol.

**Edit blocks**

1. **Lines 11-33 `get_metamethod`**:
   - Extend to tables, userdata, strings/numbers/booleans using global metatables if represented.

2. **Lines 36-63 `get_table_metamethod`**:
   - Use `Table.flags` cache.
   - Cache missing metamethod bits and invalidate on metatable mutation.

3. **Lines 66-120 numeric dispatch**:
   - Move primitive numeric logic to `regions_numeric`.
   - This file only performs metamethod selection.

4. **Lines 123-142 `prepare_metamethod_call`**:
   - Signature takes `resume: ResumeState`.
   - Writes `frame.resume = resume`.
   - Supports yieldable metamethod calls.

5. **Add final regions**
   - `call_binary_metamethod`
   - `call_unary_metamethod`
   - `call_len_metamethod`
   - `call_concat_metamethod`
   - `call_compare_metamethod`
   - `call_close_metamethod`
   - `call_finalizer_metamethod`

**Danger zones**
- `__newindex`/`__index` chains must detect loops.
- Metamethod calls must use normal call spine.

---

### `experiments/lua_interpreter_vm/src/regions_table.lua`

**Goal**: Final table hashing, growth, raw access, metamethod access, `next`, weak-mode state.

**Edit blocks**

1. **Lines 11-47 `table_raw_get`**:
   - Replace full node scan with hash bucket from key hash.
   - Preserve array fast path for positive integer keys.

2. **Lines 50-94 `table_raw_set`**:
   - Implement nil-key and NaN-key errors.
   - Update existing slot.
   - Insert into hash part.
   - Emit resize/growth via allocator.
   - Emit write barrier on collectable values.

3. **Lines 97-145 `table_get`**:
   - Support `__index` as function or table.
   - Use explicit loop counter/chain state.

4. **Lines 148-195 `table_set`**:
   - Support `__newindex` as function or table.
   - Raw insert when no metamethod.

5. **Lines 198-209 `table_next`**:
   - Implement array then hash iteration.
   - Validate supplied key exists unless nil.

6. **Lines 212-220 `table_resize`**:
   - Implement array/hash allocation and rehash.

7. **Add final regions**
   - `table_new`
   - `table_set_metatable`
   - `table_parse_weak_mode`
   - `table_invalidate_metamethod_cache`

**Danger zones**
- Weak mode derives from `__mode`.
- Setting metatable may make object finalizable and must call finalizer eligibility protocol.

---

### `experiments/lua_interpreter_vm/src/regions_weak.lua` *(new)*

**Goal**: Final weak table and ephemeron semantics.

**Required regions**
- `decode_weak_mode(mode_value; none, weak_values, weak_keys, ephemeron, all_weak)`
- `register_weak_table(G, t; done, oom)`
- `clear_weak_values(G, t; done)`
- `clear_weak_keys(G, t; done)`
- `process_ephemeron(G, t; changed, unchanged)`
- `clear_all_weak(G; done)`

**Semantic requirements**
- Strings are not removed as weak values.
- Noncollectable values are never cleared.
- Finalizable objects follow finalizer retention rules.

---

### `experiments/lua_interpreter_vm/src/regions_gc.lua`

**Goal**: Final incremental GC protocol including marking, sweeping, weak clearing, finalizers, barriers.

**Edit blocks**

1. **Lines 12-35 `alloc_object`**:
   - Move implementation to `regions_allocator.alloc_object` or require it directly.
   - Allocate and link into `G.allgc`.
   - Trigger `step_required` only for real debt/threshold.

2. **Lines 39-50 `gc_check`**:
   - Preserve threshold logic.

3. **Lines 53-59 `gc_step`**:
   - Implement switch over final `GCState`:
     - pause → propagate
     - propagate → atomic
     - atomic → sweep strings/objects
     - clear weak
     - finalize
     - pause

4. **Lines 62-111 `mark_value`**:
   - Mark all collectable tags, including userdata/proto/thread.

5. **Lines 114-126 `mark_object`**:
   - Implement tri-color transition and gray list enqueue.

6. **Lines 129-135 `propagate_gray`**:
   - Traverse object payloads by tag:
     - tables array/hash/metatable
     - closures/upvalues/proto/env
     - threads stack/frames/open upvalues
     - userdata metatable/env/user values.

7. **Lines 138-144 `sweep_step`**:
   - Free unreachable objects through allocator.
   - Queue finalizable objects instead of freeing immediately.

8. **Lines 147-165 `write_barrier`**:
   - Implement forward/backward barrier policy.
   - Call `write_barrier_back` for tables/upvalues where needed.

9. **Add regions**
   - `mark_roots`
   - `atomic_phase`
   - `queue_finalizer`
   - `run_pending_finalizer`
   - `finalizer_barrier`

**Danger zones**
- Finalizer eligibility is established when metatable is assigned.
- `oom` only means allocator failure.

---

### `experiments/lua_interpreter_vm/src/regions_userdata.lua` *(new)*

**Goal**: Final userdata/lightuserdata protocol.

**Required regions**
- `make_userdata(L, len, align, nuser_values; ok(ud), oom)`
- `userdata_get_user_value`
- `userdata_set_user_value`
- `userdata_set_metatable`
- `userdata_mark_finalizable`
- `userdata_payload`
- `lightuserdata_value`

**Danger zones**
- Do not copy PUC userdata layout.
- Payload alignment/ownership is defined by `UserData.flags`.

---

### `experiments/lua_interpreter_vm/src/regions_error.lua`

**Goal**: Final protected-call, error unwind, `__close`, and finalizer error handling.

**Edit blocks**

1. **Lines 11-23 `build_error_object`**:
   - Construct string/error object through `regions_string` where needed.

2. **Lines 48-101 `tbc_close_chain`**:
   - Replace fail path with `call_close_metamethod`.
   - Store resume state `RESUME_TBC_CLOSE`.

3. **Lines 125-178 `raise_error`**:
   - Preserve explicit protected unwind.
   - Resume caught frames through `ProtectedFrame.resume`.

4. **Lines 181-201 `enter_protected`**:
   - Allocate `ProtectedFrame` via allocator.
   - Fill `resume: ResumeState`.

5. **Lines 211-224 `protected_call`**:
   - Implement pcall/xpcall:
     - push protected frame
     - call function through `prepare_call`
     - return `success` or `failure`.

**Danger zones**
- No host `setjmp`/`longjmp`.
- `__close` errors replace or preserve prior error according to Lua close semantics.

---

### `experiments/lua_interpreter_vm/src/regions_coroutine.lua`

**Goal**: Final coroutine resume/yield protocol.

**Edit blocks**

1. **Lines 12-40 `coroutine_resume`**:
   - Re-enter `vm_loop` for resumable target.
   - Transfer args/results explicitly between caller and target stacks.
   - Distinguish dead, running, yielded, initial.

2. **Lines 43-67 `coroutine_yield`**:
   - Save `CoroutineState.resume`.
   - Preserve `nres`.
   - Reject nonyieldable boundaries.

3. **Add regions**
   - `save_yield_state`
   - `restore_yield_state`
   - `transfer_resume_args`
   - `transfer_yield_results`

**Danger zones**
- Yielded native/metamethod/protected-call paths must resume at the original `ResumeState`.

---

### `experiments/lua_interpreter_vm/src/regions_string.lua`

**Goal**: Final string interning, formatting, and concat.

**Edit blocks**

1. **Lines 23-35 `string_intern`**:
   - Implement hash lookup in `G.string_table`.
   - Allocate `String` and bytes via allocator.
   - Insert into intern table.

2. **Lines 38-50 `string_concat_range`**:
   - Convert values with Lua string conversion rules.
   - Call `__concat` via metamethod protocol when conversion fails.
   - Allocate concatenated interned string.

3. **Add regions**
   - `number_to_string`
   - `string_equal_bytes`
   - `string_resize_table`

---

### `experiments/lua_interpreter_vm/src/regions_upvalue.lua`

**Goal**: Final upvalue allocation, scanning, closing, closure creation.

**Edit blocks**

1. **Lines 9-27 `find_upvalue`**:
   - Allocate missing upvalue through allocator.
   - Insert into sorted open-upvalue list.

2. **Lines 30-45 `close_upvalues`**:
   - Preserve close logic.
   - Add barrier for closed values.

3. **Lines 48-55 `make_lclosure`**:
   - Allocate `LClosure`.
   - Allocate upvalue pointer array.
   - Initialize upvalues from child `Proto.upvals`.

---

### Opcode handler files under `experiments/lua_interpreter_vm/src/op/`

**Goal**: Make opcode handlers thin bridges into final semantic protocols.

#### `op/load.lua`
- **Lines 63-79 `op_loadkx`**: Use `Ax`.
- **Lines 133-149 `op_setupval`**: Emit write barrier.

#### `op/arithmetic.lua`
- **Lines 12-438**: Replace hand-coded arithmetic branches with emits to `regions_numeric`.
- **Lines 441-465 `MMBIN*`**: Implement metamethod fallback:
  - decode event from operands,
  - collect original operands,
  - call `call_binary_metamethod`,
  - resume through `RESUME_BINOP_MM`.

#### `op/compare.lua`
- **Lines 8-91**: Use final `value_equal/less_than/less_equal` with metamethod calls.
- **Lines 94-180 immediate comparisons**: Use `SC`.
- **Lines 183-226 TEST/TESTSET**: Preserve skip semantics; validator guarantees next `JMP`.

#### `op/table.lua`
- **Lines 8-201**: Remove embedded metamethod block strings; emit `table_get/table_set`.
- **Lines 204-220 `op_newtable`**: Implement via `table_new` using `vB/vC/EXTRAARG`.
- **Lines 242-255 `op_setlist`**: Implement batch array writes and growth.

#### `op/call.lua`
- **Lines 8-60 `op_call`**: Build `ResumeState.NORMAL`.
- **Lines 63-112 `op_tailcall`**: Build `ResumeState.TAILCALL`.
- **Lines 115-244 returns**: Use final `tbc_close_chain` and `return_from_lua`.

#### `op/loop.lua`
- **Lines 6-112**:
  - `FORLOOP/FORPREP` use `BX` targets.
  - Numeric prep uses final number coercion.
  - `TFORCALL` invokes iterator through call spine.
  - `TFORLOOP` uses `BX`.

#### `op/misc.lua`
- **Lines 6-20 `LEN/CONCAT`**:
  - Implement raw string/table length and concat range.
  - Call metamethods through `ResumeState.LEN_MM/CONCAT_MM`.
- **Lines 23-43 `CLOSE/TBC`**:
  - Use final close chain.
- **Lines 46-54 `JMP`**:
  - Use `SJ`.

#### `op/closure.lua`
- **Lines 6-39**:
  - `CLOSURE`: emit `make_lclosure`.
  - `VARARG/GETVARG/VARARGPREP`: use final vararg protocol.

---

### `experiments/lua_interpreter_vm/src/regions_chunk.lua` *(new)*

**Goal**: Final Lua 5.5 binary chunk compatibility frontier.

**Required regions/modules**
- `load_lua55_binary_chunk(L, bytes, len; ok(proto), format_error, semantic_error, oom)`
- Header validation.
- Constant decoding.
- Proto tree decoding.
- Upvalue/local/debug decoding.
- Instruction decoding through `bytecode.lua`.
- Emit internal `Proto`, then `validate_proto`.

**Danger zones**
- Do not use PUC layouts in memory.
- Binary chunk parsing produces Lalin-native `Proto`.

---

### Source compiler files

#### `regions_lexer.lua` lines 1-277
**Goal**: Full Lua 5.5 lexer.
- Add long strings/comments, escapes, floats, hex numerals, all keywords/operators.

#### `regions_parser.lua` lines 1-556
**Goal**: Full Lua 5.5 grammar.
- Add function defs, table constructors, calls, loops, if/while/repeat/for, labels/goto, varargs, closures, precedence.

#### `regions_codegen.lua` lines 1-377
**Goal**: Generate validated Lua 5.5 internal `Proto`.
- Emit correct opcode pairs, `EXTRAARG`, close metadata, vararg metadata.
- Ensure generated proto passes `validate_proto`.

#### `regions_compiler.lua` lines 1-84
**Goal**: Source frontier always returns validated `Proto`.

---

## New Files

### `src/bytecode.lua`
Central Lua 5.5 instruction facts and test encoders.

### `src/compat.lua`
Compatibility frontier registry.

### `src/regions_resume.lua`
Final suspended-control product/protocol decoder.

### `src/regions_numeric.lua`
Lua numeric coercion/arithmetic/comparison lattice.

### `src/regions_allocator.lua`
Allocator and growth boundary.

### `src/regions_native.lua`
Native call/result ABI boundary.

### `src/regions_userdata.lua`
Userdata/lightuserdata protocol.

### `src/regions_weak.lua`
Weak table and ephemeron clearing protocol.

### `src/regions_chunk.lua`
Lua 5.5 binary chunk reader into Lalin-native `Proto`.

### `src/op/protocols.lua`
Named opcode continuation protocol builder.

---

## Tests to Add/Update

1. `test_vm_product_refoundation.lua`
   - Assert final `Frame` contains `resume: ResumeState`.
   - Assert no raw `resume_mode/resume_a/...` fields remain.
   - Assert final GC/weak/finalizer/userdata products exist.

2. `test_vm_bytecode_decoder_contract.lua`
   - Verify `sJ`, `sC`, `Ax`, `vB/vC`, `Bx`.

3. `test_vm_validation_contract.lua`
   - Update helpers for `Ax`, `sJ`, `sC`, `AvBCk`.
   - Add comparison→JMP, `EXTRAARG`, `NEWTABLE`, `SETLIST`, open-call tests.

4. `test_vm_resume_protocol_contract.lua`
   - Every `Resume` value routes through `decode_resume_kind`.
   - Unknown value routes to `unknown`.

5. `test_vm_native_abi_contract.lua`
   - `NativeResult.OK/ERROR/YIELD/OOM/STACK_GROW/INVALID` map to typed exits.

6. `test_vm_allocator_gc_contract.lua`
   - Allocation, stack growth, table growth, GC step phases.

7. `test_vm_weak_finalizer_userdata.lua`
   - `__mode`, weak clearing, `__gc`, userdata payload/user values.

8. `test_vm_metamethod_protocols.lua`
   - `__index`, `__newindex`, `__call`, arithmetic, compare, len, concat, close.

9. `test_vm_coroutine_contract.lua`
   - Yield/resume across Lua call, native call, metamethod, protected call.

10. `test_vm_source_conformance.lua`
   - Source programs compile to validated proto and execute.

11. `test_vm_chunk_frontier.lua`
   - Fixed Lua 5.5 binary chunk fixtures decode to validated proto.

12. Update `test_vm_smoke.lua`
   - Replace exact struct count with named final product assertions.
   - Update continuation counts if final signatures changed.

13. Update all FFI-layout tests
   - `Frame`, `ProtectedFrame`, `GlobalState`, `LuaThread`, `UserData`, `NativeCallResult`.

---

## Order of Operations

1. Replace final products/constants first.
2. Add `bytecode.lua`; update validator and dispatch decode.
3. Add `regions_resume.lua`; migrate `Frame.resume` and call/return handling.
4. Add allocator protocol; update stack, string, table, upvalue allocation.
5. Add numeric protocol; migrate arithmetic/compare/value regions.
6. Add table/metamethod final protocols; migrate table op handlers.
7. Add native protocol; update `vm_loop` native path.
8. Add protected/error/coroutine final protocols.
9. Complete GC/weak/finalizer/userdata protocols.
10. Replace opcode protocol generation with `op/protocols.lua`.
11. Complete all opcode handlers against final regions.
12. Complete source compiler and binary chunk frontier.
13. Update all tests and run full VM suite.

---

## Testing Strategy

Run after each boundary is made coherent:

1. Products/constants:
   - `test_vm_product_refoundation.lua`
   - `test_vm_smoke.lua`

2. Decoder/validator:
   - `test_vm_bytecode_decoder_contract.lua`
   - `test_vm_validation_contract.lua`

3. Resume/call spine:
   - `test_vm_resume_protocol_contract.lua`
   - `test_vm_call_frame_contract.lua`

4. Runtime services:
   - allocator/GC/table/string/upvalue/userdata tests.

5. Opcode semantics:
   - `test_vm_opcode_semantics.lua`
   - metamethod/loop/vararg/closure tests.

6. Boundaries:
   - native ABI
   - protected error
   - coroutine
   - source compiler
   - binary chunk frontier.

7. Final:
   - all `experiments/lua_interpreter_vm/tests/test_*.lua`
   - conformance fixture suite.

---

## Pattern Memo

- `vm_resume → vm_loop → dispatch_instruction` remains the final interpreter spine.
- Frame-cache reload on frame switch is mandatory.
- `result_base` is explicit caller-owned return state.
- `Frame.resume: ResumeState` is the only persisted suspended-control storage.
- All resume switching lives in `regions_resume.lua`.
- Validator and dispatch share `bytecode.lua`.
- `oom` means real allocator failure only.
- Native, protected, coroutine, finalizer, and metamethod calls all use typed continuations.
- PUC Lua is oracle only; no PUC runtime layouts or control behavior.
- SponJIT remains disabled and separate.

## Worker Output — 2026-05-30 08:44:26

## Completed
Implemented a substantial final-form slice of Approach B:

- Added final VM product shapes:
  - `ResumeState`
  - final `Frame.resume`
  - final `ProtectedFrame.resume`
  - `NativeCallContext`
  - expanded `NativeCallResult`
  - expanded `Table`, `UserData`, `GlobalState`, `LuaThread`
  - `CoroutineState`, `FinalizerQueue`
- Added explicit protocol/discriminant constants:
  - final `Resume` range including finalizer/coroutine states
  - expanded `NativeResult`
  - `TableFlag`, `FinalizerState`, `UserDataFlag`, `CompatFormat`
  - expanded `GCState`
- Added centralized Lua 5.5 bytecode oracle:
  - `sJ`, `sC`, `Ax`, `vB/vC`, `Bx`
  - Lua-side encoders/decoders for tests
- Aligned dispatch/validator for key Lua 5.5 bytecode facts:
  - `LOADKX/EXTRAARG` uses `Ax`
  - `JMP` uses `sJ`
  - immediate comparisons/arithmetic use signed `sC`
  - `NEWTABLE`/`SETLIST` use `vB/vC/k`
  - `FORLOOP/FORPREP/TFORPREP/TFORLOOP` use `Bx`
  - comparison/test ops require following `JMP`
  - `EXTRAARG` pairing rules tightened
- Added `regions_resume` and migrated call return handling to `ResumeState`.
- Updated opcode handler signatures through named protocol descriptors.
- Added explicit native-result and GC protocol classifier modules.
- Updated tests and FFI fixtures for final `Frame/ResumeState` layout.
- Preserved:
  - `vm_resume → vm_loop → dispatch_instruction`
  - frame-cache reload in `vm_loop`
  - explicit `result_base`
  - PUC-as-oracle-only boundary
  - `sponjit_allowed = false`

## Files Changed
- `experiments/lua_interpreter_vm/src/constants.lua` - final discriminants/protocol constants.
- `experiments/lua_interpreter_vm/src/products.lua` - final product refoundation.
- `experiments/lua_interpreter_vm/src/bytecode.lua` - new bytecode oracle.
- `experiments/lua_interpreter_vm/src/regions_resume.lua` - new resume protocol.
- `experiments/lua_interpreter_vm/src/regions_native.lua` - new native result protocol.
- `experiments/lua_interpreter_vm/src/regions_gc_protocol.lua` - new GC/weak/finalizer classifiers.
- `experiments/lua_interpreter_vm/src/compat.lua` - compatibility frontier registry.
- `experiments/lua_interpreter_vm/src/op/protocols.lua` - named opcode continuation protocols.
- `experiments/lua_interpreter_vm/src/opcodes.lua` - centralized decode and operand-mode fixes.
- `experiments/lua_interpreter_vm/src/validate.lua` - validator/dispatch alignment.
- `experiments/lua_interpreter_vm/src/regions_call.lua` - return path migrated to `ResumeState`.
- `experiments/lua_interpreter_vm/src/regions_stack.lua` - frame init writes `ResumeState`.
- `experiments/lua_interpreter_vm/src/regions_metamethod.lua` - writes `ResumeState`.
- `experiments/lua_interpreter_vm/src/op/*.lua` - updated resume field access and operand semantics.
- `experiments/lua_interpreter_vm/src/init.lua` - loaded new modules.
- Updated/added tests under `experiments/lua_interpreter_vm/tests/`.

## Tests
Passed VM-focused tests:

```sh
luajit experiments/lua_interpreter_vm/tests/test_vm_smoke.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_product_refoundation.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_bytecode_decoder_contract.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_validation_contract.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_resume_protocol_contract.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_native_abi_contract.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_components.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_opcode_semantics.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_call_frame_contract.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_error_contract.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_abi_contract.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_e2e.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_integration.lua
luajit experiments/lua_interpreter_vm/tests/test_parser_compile.lua
```

## Notes
- Full final VM completion is not done: allocator/GC/table/string/upvalue/native invocation/coroutine/protected-call semantics still need deeper implementation.
- `enter_native` still uses the existing raw continuation shape; `NativeCallContext` exists but the full native call spine migration is not complete.
- `switch case @{CONST}` could not be used in new protocol switch regions because Lalin lowering rejects non-raw case keys; numeric case keys are used there as a practical compiler constraint.
- Running every `test_*.lua` also hits existing SponJIT shadow failure in `test_sponjit_shadow.lua`; interpreter VM tests listed above pass.

## Worker Output — 2026-05-30 08:58:42

## Completed

- Inspected current `git status`/diff and ran the existing VM test slice before continuing.
- Migrated the native-call continuation shape from raw fields to `NativeCallContext`:
  - `dispatch_instruction` / opcode protocols now pass `enter_native(cl, ctx)`.
  - `prepare_call` builds a typed `NativeCallContext`.
  - `vm_loop` and `call_native` consume the context instead of `func_slot/nargs/wanted/result_base/resume_mode`.
  - `NativeCallContext` now carries `ResumeState`.
- Removed more raw resume assumptions:
  - `frame_push` now receives/stores a full `ResumeState`.
  - call/table-metamethod opcode paths construct `ResumeState` explicitly.
  - `prepare_metamethod_call` takes `ResumeState`.
- Added explicit binary chunk compatibility frontier:
  - `src/regions_chunk.lua`
  - `compat.binary_chunk_frontier`
  - Typed rejection until a real Lua 5.5 chunk reader exists.
- Implemented practical protocol semantics:
  - `table_next` now iterates array/hash parts and validates absent keys.
  - `string_intern` now searches existing interned strings and only routes to `oom` for missing allocation/storage.
  - `coroutine_yield` records yielded result count and top frame resume state.
- Added/updated tests for native context/product shape, table protocol behavior, string protocol behavior, and compatibility frontier.

## Files Changed

- `experiments/lua_interpreter_vm/src/products.lua` - `NativeCallContext` now carries `ResumeState`.
- `experiments/lua_interpreter_vm/src/op/protocols.lua` - native continuation signature changed to context form.
- `experiments/lua_interpreter_vm/src/opcodes.lua` - dispatch native continuation now forwards `NativeCallContext`.
- `experiments/lua_interpreter_vm/src/op/_init.lua` - table metamethod call blocks build `ResumeState` and forward native context.
- `experiments/lua_interpreter_vm/src/op/call.lua` - CALL/TAILCALL build explicit `ResumeState`.
- `experiments/lua_interpreter_vm/src/regions_call.lua` - `prepare_call`/`call_native` migrated to `NativeCallContext`.
- `experiments/lua_interpreter_vm/src/regions_stack.lua` - `frame_push` accepts full `ResumeState`.
- `experiments/lua_interpreter_vm/src/regions_metamethod.lua` - metamethod preparation accepts `ResumeState`.
- `experiments/lua_interpreter_vm/src/vm_loop.lua` - native path consumes context.
- `experiments/lua_interpreter_vm/src/regions_table.lua` - implemented `table_next`.
- `experiments/lua_interpreter_vm/src/regions_string.lua` - implemented existing-string intern lookup.
- `experiments/lua_interpreter_vm/src/regions_coroutine.lua` - yield records explicit suspend data.
- `experiments/lua_interpreter_vm/src/regions_chunk.lua` - new typed binary chunk frontier.
- `experiments/lua_interpreter_vm/src/init.lua` / `compat.lua` - wired chunk frontier.
- Tests added/updated:
  - `test_vm_compat_frontier.lua`
  - `test_vm_table_protocols.lua`
  - `test_vm_string_protocols.lua`
  - `test_vm_product_refoundation.lua`
  - `test_vm_smoke.lua`

## Tests Run

Passed:

```sh
luajit experiments/lua_interpreter_vm/tests/test_vm_smoke.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_product_refoundation.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_bytecode_decoder_contract.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_validation_contract.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_resume_protocol_contract.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_native_abi_contract.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_compat_frontier.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_table_protocols.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_string_protocols.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_components.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_opcode_semantics.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_call_frame_contract.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_error_contract.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_abi_contract.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_e2e.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_integration.lua
luajit experiments/lua_interpreter_vm/tests/test_parser_compile.lua
```

## Notes / Remaining Blockers

- Native invocation is still not wired to a host ABI shim; it now has the correct context-shaped spine.
- Allocator/growth, table insertion/resize, closure/upvalue allocation, protected-call success, full coroutine re-entry, weak/finalizer GC, and binary chunk parsing remain incomplete.
- Binary chunks now fail through an explicit typed frontier rather than `nil`/implicit unsupported state.
- SponJIT remains disabled; VM spine/frame-cache/result-base behavior preserved.

## Worker Output — 2026-05-30 09:28:04

## Completed

Continued Approach B from the current tree and workflow context.

Implemented a concrete runtime slice:

- Added `regions_allocator.lua`
  - explicit `alloc_bytes`, `realloc_bytes`, `free_bytes`
  - `alloc_object`
  - stack/frame growth regions
- Wired allocator into `init.lua`, `regions_stack.lua`, and `regions_gc.lua`.
- Implemented table progress:
  - `table_raw_set` can insert/update within existing array/hash capacity.
  - `table_grow_for_key`, `table_resize`, `table_new`.
  - `NEWTABLE` and `SETLIST` opcode handlers now route through table protocols.
- Implemented string progress:
  - `string_intern` can now create strings when runtime storage exists.
  - `string_concat_range` handles primitive string-only concat and interns result.
  - `CONCAT` opcode routes through string concat.
- Implemented native ABI invocation boundary:
  - `regions_native.invoke_native`
  - `regions_call.call_native` now routes through it.
  - `STACK_GROW` routes through `stack_check`.
- Added/expanded tests:
  - table raw insertion/update coverage
  - native invoke boundary coverage
  - allocator extern dependency included in VM wrapper tests

Preserved:
- `vm_resume → vm_loop → dispatch_instruction`
- frame-cache reload
- explicit `result_base`
- PUC-as-oracle-only
- `sponjit_allowed = false`

## Files Changed

Key files changed in this continuation:

- `experiments/lua_interpreter_vm/src/regions_allocator.lua` - new allocator/growth protocol module.
- `experiments/lua_interpreter_vm/src/init.lua` - loads allocator module.
- `experiments/lua_interpreter_vm/src/regions_stack.lua` - stack/frame growth now uses allocator regions.
- `experiments/lua_interpreter_vm/src/regions_gc.lua` - `alloc_object` routed through allocator protocol.
- `experiments/lua_interpreter_vm/src/regions_table.lua` - table insert/growth/new protocols.
- `experiments/lua_interpreter_vm/src/op/table.lua` - `NEWTABLE`/`SETLIST` implemented through table regions.
- `experiments/lua_interpreter_vm/src/regions_string.lua` - intern creation and primitive concat.
- `experiments/lua_interpreter_vm/src/op/misc.lua` - `CONCAT` routes through string protocol.
- `experiments/lua_interpreter_vm/src/regions_native.lua` - native invoke ABI boundary.
- `experiments/lua_interpreter_vm/src/regions_call.lua` - native calls now emit invoke boundary.
- Tests updated under `experiments/lua_interpreter_vm/tests/`.

## Tests Run

Passed:

```sh
luajit experiments/lua_interpreter_vm/tests/test_vm_table_protocols.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_string_protocols.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_native_abi_contract.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_smoke.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_opcode_semantics.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_product_refoundation.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_bytecode_decoder_contract.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_validation_contract.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_resume_protocol_contract.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_compat_frontier.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_components.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_call_frame_contract.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_error_contract.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_abi_contract.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_e2e.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_integration.lua
luajit experiments/lua_interpreter_vm/tests/test_parser_compile.lua
```

## Notes / Blockers

- Allocator currently calls the typed `__ml_realloc` backend symbol while still requiring the VM allocator record to exist. Calling allocator function pointers directly hit a Lalin indirect-call backend verifier issue.
- Remaining major incomplete areas:
  - protected-call success path
  - full coroutine re-entry
  - closure/upvalue allocation
  - full table rehash preservation
  - weak/finalizer GC
  - userdata `__gc` and user values
  - real binary chunk parsing
  - full native continuation/re-enter-Lua behavior
