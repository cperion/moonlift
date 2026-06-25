# Complete Lua VM Source Compiler 
Finish the source compiler for experiments/lua_interpreter_vm so Lua 5.5 source programs compile into Lalin-native VM bytecode/products and execute correctly, with PUC Lua 5.5 as oracle only and SponJIT separate.
**Workflow ID**: wf-lua-vm-compiler-complete
**Started**: 2026-05-30 13:21:44
---

## Scout Output — 2026-05-30 13:37:32

## Files Retrieved

1. `explicit_programming.md` (lines 1-240) — explicit-programming doctrine: all meaningful distinctions should be typed/named/visible; relevant to compiler/VM architecture expectations.
2. `LANGUAGE_REFERENCE.md` (lines 1-220) — Lalin layers, hosted declarations, explicit ASDL/control rules.
3. `experiments/lua_interpreter_vm/README.md` (lines 1-102) — experiment status; interpreter VM and SpongeJIT are separate; source/compiler pieces exist but are experimental.
4. `experiments/lua_interpreter_vm/VM_CONTRACT.md` (lines 1-76) — VM contract/gates; source compiler complete is an explicit required gate; PUC is oracle only.
5. `experiments/lua_interpreter_vm/src/init.lua` (lines 1-40) — module loader exports lexer/parser/codegen/compiler/runtime modules.
6. `experiments/lua_interpreter_vm/src/compat.lua` (lines 1-14) — compatibility frontiers; exposes `source_frontier = compile_lua_source_into`; PUC oracle only.
7. `experiments/lua_interpreter_vm/src/regions_chunk.lua` (lines 1-33) — binary chunk frontier currently rejects chunks explicitly.
8. `experiments/lua_interpreter_vm/src/parser_constants.lua` (lines 1-107) — token, keyword, expression-kind, local-kind, parse-error enums.
9. `experiments/lua_interpreter_vm/src/parser_products.lua` (lines 1-54) — source/compiler product structs: `Lexer`, `FuncBuilder`, `CompileUnit`, `ExpDesc`, etc.
10. `experiments/lua_interpreter_vm/src/regions_lexer.lua` (lines 1-376) — current source-byte lexer.
11. `experiments/lua_interpreter_vm/src/regions_parser.lua` (lines 1-681) — current parser/direct bytecode compiler slice.
12. `experiments/lua_interpreter_vm/src/regions_codegen.lua` (lines 1-685) — typed bytecode builder helpers and local resolution.
13. `experiments/lua_interpreter_vm/src/regions_compiler.lua` (lines 1-90) — public source compiler entry region.
14. `experiments/lua_interpreter_vm/src/constants.lua` (lines 1-279) — Lua 5.5-aligned tags/opcodes/TM/errors/statuses.
15. `experiments/lua_interpreter_vm/src/bytecode.lua` (lines 1-99) — Lua 5.5 bytecode bit layout encoder/decoder facts.
16. `experiments/lua_interpreter_vm/src/products.lua` (lines 1-151) — VM product/data layout tree: `Value`, `Proto`, `Frame`, `LuaThread`, etc.
17. `experiments/lua_interpreter_vm/src/validate.lua` (lines 1-343) — proto validator/trust boundary.
18. `experiments/lua_interpreter_vm/src/vm_loop.lua` (lines 1-170) — `vm_resume`, `vm_loop`, frame-cache reload behavior.
19. `experiments/lua_interpreter_vm/src/opcodes.lua` (lines 1-817) — opcode dispatch switch and handler wiring for opcodes 0-84.
20. `experiments/lua_interpreter_vm/src/op/*.lua` — opcode handler modules: load/arithmetic/table/compare/call/loop/closure/misc/protocols.
21. `experiments/lua_interpreter_vm/src/regions_allocator.lua` (lines 1-185) — explicit allocator/growth boundary.
22. `experiments/lua_interpreter_vm/src/regions_string.lua` (lines 1-178) — string hash/intern/concat regions.
23. `experiments/lua_interpreter_vm/src/regions_table.lua` (lines 1-714) — raw and metamethod-aware table get/set/next/new/resize.
24. `experiments/lua_interpreter_vm/src/regions_call.lua` (lines 1-401) — call/return engine and native call boundary.
25. `experiments/lua_interpreter_vm/src/regions_resume.lua` (lines 1-243) — explicit suspended-control resume protocols.
26. `experiments/lua_interpreter_vm/src/regions_native.lua` (lines 1-76) — explicit native ABI invocation/result decoder.
27. `experiments/lua_interpreter_vm/src/api.lua` (lines 1-175) — sealed host API functions; several runtime APIs fail loud.
28. `experiments/lua_interpreter_vm/tests/test_parser_compile.lua` (lines 1-272) — current source compiler/lexer/run tests.
29. `experiments/lua_interpreter_vm/tools/jit_harness/compile.lua` (lines 1-335) — harness compiler wrapper and fallback-token compiler.
30. `.vendor/Lua/llex.h` (lines 1-77), `.vendor/Lua/llex.c` (lines 244-607) — PUC Lua 5.5 lexer token and lexical oracle facts.
31. `.vendor/Lua/lopcodes.h` (lines 1-441) — PUC Lua 5.5 opcode names/layout/notes.
32. `.vendor/Lua/ltm.h` (lines 1-76) — PUC Lua 5.5 tag-method order.
33. `.vendor/Lua/manual/manual.of` (lines 9705-9819) — Lua 5.5 full grammar excerpt.

## Key Code

### Compiler entry point

`src/regions_compiler.lua` initializes a caller-supplied `CompileUnit`, `FuncBuilder`, output `Proto`, code buffer, and local buffer, then emits `compile_prepared_unit`:

```lua
region compile_lua_source_into(
    cu: ptr(CompileUnit),
    builder: ptr(FuncBuilder),
    out_proto: ptr(Proto),
    bytes: ptr(u8),
    len: index,
    code: ptr(Instr),
    code_cap: index,
    locals: ptr(CompileLocal),
    locals_cap: index;
    ok: cont(proto: ptr(Proto)),
    syntax_error: cont(err: CompileError),
    semantic_error: cont(err: CompileError),
    limit_error: cont(err: CompileError),
    oom: cont())
```

Facts:
- No `LuaThread`/`GlobalState`/allocator parameter.
- `cu.arena = nil`; `CompileArena` exists but is unused here.
- `builder.constants`, `children`, `locvars`, `upvals` are initialized with `nil` data and zero capacity.
- Only code and locals are caller-provided writable arrays.

### Compiler products

`src/parser_products.lua` defines compiler-state products, not a separate AST:

```lua
local Token = host.struct [[struct Token kind: u16; start: index; len: index; line: i32; aux: u32; bits: u64 end]]
local Lexer = host.struct [[struct Lexer src: SourceView; pos: index; line: i32; col: i32; current: Token; lookahead: Token; has_lookahead: u8 end]]
local FuncBuilder = host.struct [[struct FuncBuilder parent: ptr(FuncBuilder); out_proto: ptr(Proto); code: InstrVec; constants: ValueVec; children: ProtoPtrVec; locvars: LocVarVec; upvals: UpValDescVec; locals: ptr(CompileLocal); ... end]]
local CompileUnit = host.struct [[struct CompileUnit arena: ptr(CompileArena); lexer: Lexer; root: ptr(FuncBuilder); current: ptr(FuncBuilder); expr_tmp: ExpDesc; ... scratch_index2: index end]]
```

There are parser/compiler products, but no AST node product tree in this experiment.

### Current lexer coverage

`src/parser_constants.lua` has tokens for:
- names, ints, floats, strings
- arithmetic: `+ - * / % //`
- comparisons: `== ~= < <= > >=`
- dots: `. .. ...`
- table/function syntax punctuation: `{ } [ ] ( ) : :: , ;`
- bitwise: `& | ~ << >>`
- keywords: `local return function end if then else elseif for in do while repeat until break true false nil and or not`

Current lexer implementation:
- Scans identifiers/keywords.
- Scans decimal integer literals only.
- Scans simple quoted strings by finding closing quote; no escape decoding.
- Skips short `--` comments only.
- Does not implement long strings/comments.
- Does not implement hex numerals, floats, exponent forms, `.123`, UTF-8/string escapes, `\z`, decimal/hex escapes, etc.
- Does not include Lua 5.5 `global` or `goto` tokens/keywords.

PUC Lua 5.5 oracle (`.vendor/Lua/llex.h`) includes reserved tokens:

```c
TK_AND, TK_BREAK,
TK_DO, TK_ELSE, TK_ELSEIF, TK_END, TK_FALSE, TK_FOR, TK_FUNCTION,
TK_GLOBAL, TK_GOTO, TK_IF, TK_IN, TK_LOCAL, TK_NIL, TK_NOT, TK_OR,
TK_REPEAT, TK_RETURN, TK_THEN, TK_TRUE, TK_UNTIL, TK_WHILE,
```

### Current parser/source-language coverage

`src/regions_parser.lua` supports:

Statements:
- `return`
- `return <expr>`
- `local <name>`
- `local <name> = <expr>`
- `<local_name> = <expr>`
- `;`

Expressions:
- integer literals
- local names
- `true`, `false`, `nil`
- binary `* / % //` precedence tier
- binary `+ -` precedence tier

Emitted opcodes currently exercised:
- `LOADI`
- `LOADTRUE`
- `LOADFALSE`
- `LOADNIL`
- `MOVE`
- `ADD`, `SUB`, `MUL`, `DIV`, `MOD`, `IDIV`
- adjacent `MMBIN`
- `RETURN0`, `RETURN1`

The parser rejects undeclared names; there is no `_ENV`/global lookup path.

### Current parser omissions vs Lua 5.5 grammar

From PUC manual grammar, Lua 5.5 has:
- labels and `goto`
- `break`
- `do ... end`
- `while`, `repeat`, numeric `for`, generic `for`
- `if/elseif/else`
- function definitions, local/global functions
- `global` declarations
- attribute names: `<const>`, `<close>`, etc.
- varlists/explists with comma adjustment
- prefix expressions: indexing, field access, calls, method calls, parenthesized exprs
- table constructors
- function literals
- varargs
- full binary operators: `+ - * / // ^ % & ~ | >> << .. < <= > >= == ~= and or`
- unary operators: `- not # ~`

Most of that grammar is not implemented in `regions_parser.lua`.

### Bytecode layout

`src/bytecode.lua` matches PUC Lua 5.5 packed 32-bit instruction facts:
- 7-bit opcode
- A at bit 7
- k at bit 15
- B/C at 16/24
- vB/vC at 16/22
- Bx at 15
- Ax/sJ at 7

PUC `lopcodes.h` confirms same layout and opcode list through `OP_EXTRAARG`.

### Opcode/runtime coverage

Dispatch wires all opcodes 0-84. Many handlers exist, but several are stub/error paths:

- `op_pow`, `op_powk` → `ERR_ARITH`
- `op_mmbin`, `op_mmbini`, `op_mmbink` → `ERR_RUNTIME`
- compare metamethod paths → `ERR_COMPARE`
- concat metamethod path → `ERR_CONCAT`
- `op_tforcall` → `ERR_RUNTIME`
- `op_getvarg` → `ERR_RUNTIME`
- `tbc_close_chain` path in `regions_error.lua` comments says `__close` reentry not wired and fails loudly.
- API `lua_gettable_api`, `lua_settable_api`, `lua_call_api`, `lua_pcall_api` mark runtime errors rather than performing full behavior.

### Tests/run facts

Commands run:

- `luajit experiments/lua_interpreter_vm/tests/test_vm_components.lua` → pass.
- `luajit experiments/lua_interpreter_vm/tests/test_vm_opcode_semantics.lua` → pass.
- `luajit experiments/lua_interpreter_vm/tests/test_vm_integration.lua` → pass.
- `luajit experiments/lua_interpreter_vm/tests/test_vm_e2e.lua` → pass; manual Proto `LOADK; RETURN` executes.
- `luajit experiments/lua_interpreter_vm/tests/test_vm_validation_contract.lua` → pass.
- `luajit experiments/lua_interpreter_vm/tests/test_vm_call_frame_contract.lua` → pass.
- `luajit experiments/lua_interpreter_vm/tests/test_vm_compat_frontier.lua` → pass.
- `stdbuf -o0 luajit experiments/lua_interpreter_vm/tests/test_parser_compile.lua`:
  - lexer tests pass
  - simple compile/run cases pass through `return 10 // 4`
  - `compile_case("return 9 / 3", ...)` passes
  - process segfaults immediately after, at the negative compile-status check for trailing statements.

Observed output before segfault includes:

```text
PASS return 1 + 2
RUN  return 1 + 2 => 3
PASS local x = 41 return x + 1
RUN  local x = 41 return x + 1 => 42
...
PASS return 9 / 3
Segmentation fault
```

## Relationships

- `src/init.lua` loads all VM modules and exposes `regions_lexer`, `regions_parser`, `regions_codegen`, `regions_compiler`.
- `regions_compiler.compile_lua_source_into` initializes compiler state and calls `compile_prepared_unit`.
- `compile_prepared_unit` calls `lex_next`, then `parse_block`, then `close_func_builder`.
- Parser functions call codegen helpers directly; there is no AST/product layer between parse and bytecode.
- Codegen writes packed `Instr.word` into the caller-provided `InstrVec`.
- `close_func_builder` copies builder vectors into the output `Proto`.
- Executing compiled source requires a manually constructed `LClosure`, `Frame`, `LuaThread`, and stack, then `validate_proto` and `vm_resume`.
- `vm_loop` dispatches through `opcodes.dispatch_instruction`, which maps packed opcodes to handlers under `src/op/`.
- `validate_proto` is the trust boundary before interpreter/JIT consumption.
- `compat.lua` exposes source and binary frontiers, but binary chunks currently always format-error.
- SpongeJIT/harness code can compile source for profiling, but README states SpongeJIT is separate and not the execution engine for `src/vm_loop.lua`.

## Observations

- The current source compiler is a direct parser-to-bytecode slice, not a full Lua 5.5 compiler.
- Current source tests prove simple integer arithmetic/local/return programs can compile and execute.
- The parser compile test segfaults on an error-path case after many successful cases; this is a current working-tree blocker.
- `test_parser_compile.lua` and `tools/jit_harness/compile.lua` define `CompileUnit` FFI structs missing the newer trailing fields (`scratch_reg`, `scratch_count`, `scratch_op`, `scratch_index`, `scratch_index2`) present in `parser_products.lua`.
- The compiler entry has no allocator/runtime state, while full Lua source needs allocation for constants, strings, child protos, upvalue descriptors, line info, tables, etc.
- `return` emits `RETURN0` but uses no registers, leaving `maxstack` at 0; `validate_proto` rejects `p.maxstack == 0`.
- A block with non-return statements can close without an implicit `RETURN0`; validator does not appear to require a terminal return/jump.
- PUC Lua 5.5 has `global` and `goto`; current parser constants/lexer omit both.
- Current lexer tokenizes some operators/punctuation that parser does not consume.
- Current codegen has helpers for calls, len, tables, tests/jumps, numeric for, vararg, etc., but parser does not call most of them.
- Runtime has many Lua 5.5 opcode handlers wired, but several semantic paths still fail loudly, especially metamethod continuation paths, power, generic-for call, getvarg, and full protected/TBC behavior.
- Binary chunk loader is an explicit reject boundary, not a loader.
- PUC Lua is locally available as `.vendor/Lua/lua` and reports `Lua 5.5.0`; PUC facts are source/semantic oracle only per VM contract.

## Knowledge-builder Output — 2026-05-30 13:39:54

### What Matters Most for This Problem

- **Semantic completeness, not syntax coverage alone**: “compile Lua 5.5 source and execute correctly” is constrained by VM opcode/runtime semantics, not just parser coverage.
- **Explicit-programming fit**: Lua source distinctions must become typed compiler products/control exits, not hidden in conventions, fallbacks, or host-side fixtures.
- **Compiler ↔ VM contract alignment**: generated `Proto`s must satisfy `validate_proto` and runtime invariants by construction.
- **Allocator/lifetime ownership**: full Lua source compilation requires durable constants, strings, child protos, upvalues, locvars, labels, and debug metadata; current entry point cannot own these explicitly.
- **Oracle discipline**: PUC Lua 5.5 is semantic oracle only; PUC bytecode/layout/allocator behavior cannot become an implementation dependency.
- **Verification pressure**: compile success is insufficient unless followed by validation and execution against oracle-relevant cases.

### Non-Obvious Observations

- **The current compiler ABI is already unsound in tests.**  
  `parser_products.lua` added trailing `CompileUnit` fields, but `test_parser_compile.lua` still declares an older FFI struct. `compile_lua_source_into` writes `scratch_reg`, `scratch_count`, etc. unconditionally, so the test allocates too-small memory. The observed segfault after several successful cases is likely delayed memory corruption, not a parser semantic failure. This is an explicit-programming violation: the struct schema exists in two unsynchronized places.

- **“Source compiler complete” is gated by runtime semantics.**  
  The parser could emit bytecode for more grammar today, but several VM paths are fail-loud or incomplete: `POW`, `MMBIN*`, generic-for call, `GETVARG`, compare metamethods, concat metamethods, protected/TBC close paths. Any source construct that reaches those paths would compile but not execute correctly against PUC Lua.

- **The compiler entry point cannot currently express full Lua compilation ownership.**  
  `compile_lua_source_into` receives only caller-provided code/local buffers. Constants, strings, children, locvars, upvals, labels, and gotos are initialized as nil/zero-capacity vectors. Full Lua source needs durable allocation for all of these. Because VM contract says allocation is VM semantics with explicit `ok/step_required/oom` outcomes, hidden host allocation would conflict with the allocator boundary.

- **String tokens currently point into source bytes, but compiled Lua constants must outlive source bytes.**  
  Current lexer string tokens store source offsets/lengths and do not decode escapes. That is enough for syntax tests, but not enough for `Proto.constants`: literals need VM-owned/interpretable `String` objects, correct escape decoding, and lifetime independent of the caller’s source buffer.

- **The lexer/schema omits Lua 5.5 reserved words that affect semantics.**  
  PUC Lua 5.5 reserves `global` and `goto`; current constants/lexer omit both. This is not just a missing parser branch: lexing them as names changes the legal program set, name resolution, and static-error behavior.

- **Undeclared-name rejection is incompatible with Lua’s `_ENV` model.**  
  Current name parsing only resolves locals and otherwise emits `UNDECLARED_NAME`. Lua source semantics require unresolved names to become environment accesses through `_ENV`/global declaration rules. This implies hidden dependencies on upvalue descriptors, closure environment construction, constants for field names, and table access opcodes.

- **The apparent PUC bytecode-layout match is not a license to mirror PUC codegen.**  
  `bytecode.lua` and `lopcodes.h` agree on packed instruction layout, but `VM_CONTRACT.md` explicitly forbids treating PUC layouts/conventions as dependencies. The stable target is Lalin `Proto` + validator assumptions, not PUC chunks or PUC compiler output.

- **`validate_proto` is stricter than current compiler success.**  
  `RETURN0` can leave `maxstack == 0`, which `validate_proto` rejects before execution. Also chunks with no explicit return can close without terminal return bytecode. Thus an `ok(proto)` from the compiler is not equivalent to “executable bytecode product.”

- **The direct parser-to-bytecode architecture raises ordering pressure for control expressions.**  
  Lua expressions include short-circuit `and/or`, comparisons, concat, right-associative `^`/`..`, function calls with multiple results, and conditional jumps. Existing `ExpDesc` has `VJMP/t/f` fields, but the current parser mostly treats expressions as registers. Completing semantics requires preserving control distinctions explicitly, or jump/fallthrough behavior will become implicit and fragile.

- **Register lifetime is currently monotonic and conflates locals with temporaries.**  
  `reserve_reg` only increments `freereg`; temporaries are not released. Simple arithmetic works, but larger expressions, blocks, nested scopes, and multiple assignment will consume registers unnecessarily and obscure lifetime. More importantly, current binary codegen often writes results into the left operand register, which is unsafe for Lua’s simultaneous-assignment and multi-result adjustment semantics.

- **Current locals have no real scope exit behavior.**  
  `CompileLocal` entries accumulate; blocks do not restore `locals_len`, `nactvar`, or `freereg`. Lua blocks, loops, functions, labels/gotos, upvalues, and `<close>` attributes all depend on precise scope boundaries. Existing `firstlocal`, `nactvar`, `kind`, labels, and gotos fields hint at the needed distinctions but are not yet operational.

- **Labels/gotos require allocation and scope metadata, not just tokens.**  
  `LabelDesc` stores `name: ptr(String)` and `nactvar`, while current lexer/local names are source spans plus hashes. Lua’s `goto` rules depend on whether jumps enter scopes with locals/to-be-closed variables. This crosses lexer, name interning, local-scope tracking, jump patching, and error reporting.

- **`global` declarations are a semantic fault line unique to Lua 5.5.**  
  They change how bare names are classified and what declarations are legal. Treating them as ordinary names would silently diverge from the oracle and hide a meaningful source distinction, directly conflicting with explicit-programming doctrine.

- **Attributes are tied to runtime unwind semantics.**  
  `<const>` is compile-time binding discipline; `<close>` connects source parsing to VM protected-unwind, `__close`, yieldability, and error-state preservation. Since TBC/`__close` paths are currently fail-loud/incomplete, attribute parsing cannot be considered isolated compiler work.

- **Arithmetic oracle cases are under-tested even for already-emitted opcodes.**  
  Existing tests use positive `%` and `//`. Lua floor division/modulo semantics differ from truncating integer division for negatives. Current runtime appears to use raw integer `/` and `%`, so exposing more arithmetic through the source compiler may reveal VM semantic mismatches unrelated to parsing.

- **Constants are not optional once non-integer literals appear.**  
  Current compiler avoids constants by using `LOADI`, booleans, nil, and registers. Floats, strings, field names, global names, function prototypes, and some numeric ranges require constant vectors. The nil `constants.data`/zero capacity state is therefore a hard boundary, not an implementation detail.

- **Full function support couples compiler output to closure/upvalue runtime invariants.**  
  Function literals/definitions require child `Proto`s, `UpValDesc`s, `_ENV` capture, parent/child builder switching, and `OP_CLOSURE`. Runtime `op_closure` assumes child protos and upvalue metadata are valid. Missing compiler metadata can produce validator-accepted but runtime-invalid closures.

- **Main chunks likely need vararg/env decisions made explicitly.**  
  Lua chunks behave as functions with environment and vararg-related semantics. Current root builder initializes `numparams = 0`, `flag = 0`, no upvals, no `_ENV`. That may be enough for arithmetic-only chunks but is not a faithful Lua source chunk model.

- **Lexer completeness has semantic consequences beyond accepting input.**  
  Missing long strings/comments, escape decoding, numerals, `.123`, hex floats, `\z`, UTF-8 escapes, and overflow behavior affect actual runtime values, not just syntax. PUC oracle comparison will catch value-level mismatches.

- **Error categories are too coarse for a complete explicit frontier.**  
  `UNSUPPORTED_SOURCE`/`UNEXPECTED_TOKEN` can serve early experiments, but full compiler correctness needs source distinctions like lexical malformed numeral/string, reserved-word misuse, invalid break/goto, scope violations, const assignment, vararg misuse, and limit errors to remain visible.

- **The JIT harness fallback compiler is a verification hazard.**  
  Any fallback/token compiler path can mask failures in the real source compiler. The VM contract says SponJIT is separate and must not consume scaffolding behavior, so source-compiler verification must avoid conflating harness convenience with the VM source frontier.

### Knowledge Gaps

- Exact intended completeness boundary: all Lua 5.5 syntax, or all syntax whose runtime semantics are currently implemented?
- Whether source compilation is expected to allocate through `GlobalState`/VM allocator or through a separate compile arena with explicit lifetime.
- Precise Lua 5.5 `global` declaration semantics and how PUC’s 5.5 branch treats `_ENV`.
- Full runtime semantic gaps for already wired opcodes under negative arithmetic, string/number coercions, calls, varargs, tables, and metamethods.
- Whether compiled chunks are required to include debug metadata/source/lineinfo for the “complete” gate, or only executable semantics.

## Edit-planner Output — 2026-05-30 13:44:57

### Precondition Checks

- Confirm `experiments/lua_interpreter_vm/src/parser_products.lua:28` still defines `CompileUnit` with trailing fields `scratch_reg`, `scratch_count`, `scratch_op`, `scratch_index`, `scratch_index2`.
- Confirm stale FFI copies still exist at:
  - `experiments/lua_interpreter_vm/tests/test_parser_compile.lua:56`
  - `experiments/lua_interpreter_vm/tools/jit_harness/compile.lua:130`
- Confirm `regions_compiler.lua:6-17` still exposes `compile_lua_source_into` without `LuaThread`/allocator access.
- Confirm `regions_codegen.lua:598-623` `close_func_builder` still copies nil-capacity `constants`, `children`, `locvars`, `upvals`.
- Confirm runtime stubs remain:
  - `op/arithmetic.lua:142-146`, `376-380`, `495-517`
  - `op/loop.lua:85-90`
  - `op/closure.lua:67-73`
  - `regions_error.lua:93-96`
- Run `luajit experiments/lua_interpreter_vm/tests/test_parser_compile.lua` only after the FFI schema fix; current version is allowed to segfault.

---

### Files to Modify

#### `experiments/lua_interpreter_vm/tools/vm_ffi_schema.lua`

**Goal**: Add one shared LuaJIT FFI schema source for VM test/tool fixtures so product structs cannot silently drift.

**Edit blocks**
1. **New file**: Add module returning `cdef` text and `apply(ffi)`.
   - Include all structs currently duplicated in `test_parser_compile.lua:11-106`.
   - `CompileUnit` must exactly match `parser_products.lua:28`:
     ```c
     typedef struct CompileUnit {
       CompileArena* arena;
       Lexer lexer;
       FuncBuilder* root;
       FuncBuilder* current;
       ExpDesc expr_tmp;
       ExpDesc expr_tmp2;
       ExpDesc expr_tmp3;
       Token token_tmp;
       uint16_t tmp_reg;
       uint16_t scratch_reg;
       uint16_t scratch_count;
       uint16_t scratch_op;
       uint64_t scratch_index;
       uint64_t scratch_index2;
     } CompileUnit;
     ```
   - Include current `LuaThread` with `CoroutineState` tail fields, matching `products.lua:90-96`.
   - Export:
     ```lua
     local M = {}
     M.cdef = [[...]]
     function M.apply(ffi) ffi.cdef(M.cdef) end
     return M
     ```

**Patterns to enforce**
- This file is the only FFI schema for Lua VM tests/tools.
- Comments must name canonical source files: `products.lua`, `parser_products.lua`.

**Danger zones**
- LuaJIT `ffi.cdef` cannot redefine incompatible structs. Keep names identical and only call once per process where possible.

---

#### `experiments/lua_interpreter_vm/tests/test_parser_compile.lua`

**Goal**: Stop memory corruption immediately and then update the source compiler tests to the final compile ABI.

**Edit blocks**
1. **Lines 11-106**: Remove inline `ffi.cdef [[...]]`.
   - Before: large hand-written schema ending with stale `CompileUnit`.
   - After:
     ```lua
     require("experiments.lua_interpreter_vm.tools.vm_ffi_schema").apply(ffi)
     ```

2. **Lines 113-132**: Modify `compile_text` wrapper after compiler ABI changes.
   - Before:
     ```lalin
     compile_text(cu, b, p, bytes, n, code, locals) -> i32
       emit compile_lua_source_into(cu, b, p, bytes, n, code, 32, locals, 16; ...)
     ```
   - After:
     ```lalin
     compile_text(L, cu, b, p, arena, bytes, n) -> i32
       emit compile_lua_source_into(L, cu, b, p, arena, bytes, n, nil;
         ok = ok,
         syntax_error = syntax_bad,
         semantic_error = semantic_bad,
         limit_error = limit_bad,
         step_required = step_bad,
         oom = oom_bad)
     ```
   - Map `step_required` to a distinct negative status, e.g. `-998`.

3. **Lines 167-186 and 226-237**: Remove caller-owned `code`/`locals` arrays from compile helpers.
   - Before: `local code = ffi.new("Instr[128]")`, `local locals = ffi.new("CompileLocal[32]")`.
   - After: allocate `CompileArena` plus backing bytes; inspect `p.code[i]`, not `code[i]`.

4. **Line 273 negative status check**: Keep the trailing-statement rejection test, but it should no longer be the first post-run negative check. Add one sanity call immediately after schema load:
   ```lua
   assert(ffi.sizeof("CompileUnit") >= expected_min_size)
   ```

**Patterns to enforce**
- Test fixtures inspect returned `Proto`, never caller-owned code buffers.
- Any new cdef belongs in `tools/vm_ffi_schema.lua`.

**Danger zones**
- Do not keep stale local `GlobalState` definition if shared schema defines the full one.

---

#### `experiments/lua_interpreter_vm/tools/jit_harness/compile.lua`

**Goal**: Remove stale schema and route harness compilation through the real source compiler only.

**Edit blocks**
1. **Lines 85-130**: Replace inline `ffi.cdef` with shared schema.
   ```lua
   require("experiments.lua_interpreter_vm.tools.vm_ffi_schema").apply(ffi)
   ```

2. **Lines 133-165**: Update wrapper signature to final compiler ABI:
   - Pass `LuaThread* L`, `CompileArena* arena`.
   - Remove `code`, `code_cap`, `locals`, `locals_cap` parameters.
   - Add `step_required` continuation.

3. **Remaining fallback-token compiler paths**: Remove or hard-error any fallback compiler that fabricates bytecode from tokens.
   - The harness may report source compiler failure.
   - It must not generate substitute bytecode.

**Patterns to enforce**
- Harness uses `vm.regions_compiler.compile_lua_source_into`.
- No hidden source fallback.

**Danger zones**
- SpongeJIT tooling must remain separate; do not wire foundry code into VM execution.

---

#### `experiments/lua_interpreter_vm/src/parser_constants.lua`

**Goal**: Complete Lua 5.5 token, keyword, expression, variable, and compile-error discriminants.

**Edit blocks**
1. **Lines 1-36**: Extend `Tok`.
   - Add missing punctuation/operators used by grammar:
     ```lua
     Tok.CARET = 37      -- ^
     Tok.ATTR_LT = ...   -- only if attributes are tokenized distinctly; otherwise use LT
     ```
   - Keep existing numeric values stable if tests depend on them; append new tokens.

2. **Lines 38-58**: Add Lua 5.5 keywords:
   ```lua
   Kw.GLOBAL = 85
   Kw.GOTO = 86
   ```
   - Do not lex these as names.

3. **Lines 60-72**: Extend `ExpKind`.
   - Add explicit kinds for:
     - global/upvalue indexed variables
     - table index variables
     - constants
     - function literals
     - multi-result calls
     - short-circuit/jump expressions
   - Use names like `VUPVAL`, `VINDEXED`, `VGLOBAL`, `VK`, `VMULTRET`.

4. **Lines 74-79**: Extend `VarKind`.
   - Add `LOCAL`, `UPVAL`, `GLOBAL`, `INDEXED`, `CONST`, `TBC`.

5. **Lines 81-99**: Replace coarse error list with explicit source errors.
   - Add:
     ```lua
     MALFORMED_NUMBER
     MALFORMED_STRING
     EXPECTED_UNTIL
     EXPECTED_WHILE
     EXPECTED_FOR
     EXPECTED_IN
     EXPECTED_FUNCTION_BODY
     INVALID_BREAK
     INVALID_GOTO
     GOTO_INTO_SCOPE
     ASSIGN_TO_CONST
     VARARG_OUTSIDE_VARARG
     TOO_MANY_LOCALS
     TOO_MANY_UPVALUES
     TOO_MANY_CONSTANTS
     TOO_MANY_PROTOS
     ```
   - Keep old names as aliases only if existing tests compare them.

**Patterns to enforce**
- Constants are append-only unless all tests are updated.
- Error names describe semantic distinction; no catch-all for implemented grammar.

**Danger zones**
- `global` and `goto` must be reserved words, not recoverable names.

---

#### `experiments/lua_interpreter_vm/src/parser_products.lua`

**Goal**: Make compiler state capable of final Lua source compilation with explicit allocation/lifetime ownership.

**Edit blocks**
1. **Lines 11-18**: Add vector structs:
   ```lua
   local LineInfoVec = host.struct [[struct LineInfoVec data: ptr(i32); len: index; cap: index end]]
   local CompileLocalVec = host.struct [[struct CompileLocalVec data: ptr(CompileLocal); len: index; cap: index end]]
   local FuncBuilderVec = host.struct [[struct FuncBuilderVec data: ptr(FuncBuilder); len: index; cap: index end]]
   ```

2. **Lines 20-24**: Replace source-span-only locals with durable names/scope info.
   - Before:
     ```lua
     struct CompileLocal name_start; name_len; hash; reg; kind
     ```
   - After:
     ```lua
     struct CompileLocal
       name: ptr(String);
       name_start: index;
       name_len: index;
       hash: u32;
       reg: u16;
       kind: u8;
       depth: u16;
       startpc: index;
       endpc: index;
       captured: u8;
     end
     ```

3. **Line 25 `FuncBuilder`**: Add final vectors and scope state.
   - Add `lineinfo: LineInfoVec`.
   - Add `locals_vec: CompileLocalVec` or replace raw `locals/locals_len/locals_cap`.
   - Add:
     ```c
     upvalue_refs: ptr(UpvalueRef); upvalue_refs_len; upvalue_refs_cap;
     break_patches: ptr(LabelPatch); break_patches_len; break_patches_cap;
     scope_depth: u16;
     loop_depth: u16;
     vararg_allowed: u8;
     has_tbc: u8;
     ```
   - Keep `locals` fields temporarily only if regions still compile; remove after codegen update.

4. **Line 26 `ExpDesc`**: Add fields needed by direct parser/codegen:
   ```c
   struct ExpDesc
     kind: u16;
     info: u32;
     aux: u32;
     t: index;
     f: index;
     value: Value;
     reg: u16;
     nresults: i32;
   end
   ```

5. **Line 28 `CompileUnit`**: Add allocator/runtime and parse scratch:
   ```c
   L: ptr(LuaThread);
   arena: ptr(CompileArena);
   source_name: ptr(String);
   root/current...
   decoded_bytes: ptr(u8);
   decoded_len: index;
   decoded_cap: index;
   ```
   - Keep trailing scratch fields synchronized with shared FFI schema.

6. **Return table lines 30-54**: Export new structs.

**Patterns to enforce**
- Durable VM products use `ptr(String)`, `ptr(Proto)`, `ptr(Value)`.
- Source offsets are retained only for diagnostics/debug metadata.

**Danger zones**
- Every FFI copy must be updated via `tools/vm_ffi_schema.lua` after struct changes.

---

#### `experiments/lua_interpreter_vm/src/regions_allocator.lua`

**Goal**: Add explicit allocation sizes for compiler-owned VM products and reusable array-growth helpers.

**Edit blocks**
1. **Lines 13-26**: Add size/alignment constants:
   ```lua
   I.SIZE_INSTR = lalin.int(4)
   I.ALIGN_INSTR = lalin.int(4)
   I.SIZE_PROTO = lalin.int(<ffi/product size>)
   I.ALIGN_PROTO = lalin.int(8)
   I.SIZE_PROTOPTR = lalin.int(8)
   I.SIZE_LOCVAR = lalin.int(24)
   I.SIZE_UPVALDESC = lalin.int(16)
   I.SIZE_I32 = lalin.int(4)
   ```
   - Verify sizes against `products.lua`.

2. **After `alloc_object` lines 83-108**: Add generic growth regions for compiler arrays:
   - `grow_instr_array(G, old, old_cap, needed; ok(data, cap), step_required, oom)`
   - `grow_value_array_raw(G, old, old_cap, needed; ...)`
   - `grow_protoptr_array`
   - `grow_locvar_array`
   - `grow_upvaldesc_array`
   - `grow_i32_array`

3. **Return table lines 172-185**: Export all new growth helpers and sizes.

**Patterns to enforce**
- All growth exposes `step_required` separately from `oom`.
- Capacity policy doubles until `needed`, with overflow checks.

**Danger zones**
- Existing `grow_value_array(L, ...)` is stack-specific; do not reuse it for `Proto.constants`.

---

#### `experiments/lua_interpreter_vm/src/regions_compiler.lua`

**Goal**: Replace buffer-based compiler entry with allocator-aware final source compiler entry.

**Edit blocks**
1. **Lines 5-18**: Change signature.
   - Before:
     ```lalin
     region compile_lua_source_into(cu, builder, out_proto, bytes, len, code, code_cap, locals, locals_cap; ...)
     ```
   - After:
     ```lalin
     region compile_lua_source_into(
       L: ptr(LuaThread),
       cu: ptr(CompileUnit),
       builder: ptr(FuncBuilder),
       out_proto: ptr(Proto),
       arena: ptr(CompileArena),
       bytes: ptr(u8),
       len: index,
       source_name: ptr(String);
       ok: cont(proto: ptr(Proto)),
       syntax_error: cont(err: CompileError),
       semantic_error: cont(err: CompileError),
       limit_error: cont(err: CompileError),
       step_required: cont(),
       oom: cont())
     ```

2. **Lines 19-56**: Initialize compiler state with `L`, `arena`, VM-owned vectors.
   - Set `cu.L = L`, `cu.arena = arena`, `cu.source_name = source_name`.
   - Initialize builder vectors with nil/zero, but not final capacity.
   - Set `builder.maxstack = 1` so `RETURN0` chunks validate.
   - Set root chunk as vararg-compatible if Lua chunks require it:
     ```lalin
     builder.vararg_allowed = 1
     builder.flag = @{PF_VAHID} -- if runtime expects this
     ```

3. **Lines 58-65**: Add `step_required` propagation from `compile_prepared_unit`.

4. **Lines 67-88**: Add `block need_step() jump step_required() end`.

**Patterns to enforce**
- The compiler does not receive code/local output arrays.
- All durable allocations flow through `L.global`.

**Danger zones**
- Existing callers will not compile until tests/harness wrappers are updated.

---

#### `experiments/lua_interpreter_vm/src/regions_codegen.lua`

**Goal**: Turn bytecode builder into allocator-aware final Proto builder.

**Edit blocks**
1. **Lines 43-101 emit helpers**: Replace direct `cap` failure with vector growth.
   - Before:
     ```lalin
     if fs.code.len >= fs.code.cap then jump oom() end
     ```
   - After:
     ```lalin
     if fs.code.len >= fs.code.cap then
       emit ensure_code_capacity(cu, fs.code.len + 1; ok = code_ready, step_required = need_step, oom = out_of_mem)
     end
     ```
   - Add `step_required` continuation to emit helpers.

2. **After line 102**: Add allocation helpers:
   - `ensure_code_capacity`
   - `ensure_constant_capacity`
   - `ensure_child_capacity`
   - `ensure_locvar_capacity`
   - `ensure_upval_capacity`
   - `add_constant_value`
   - `intern_source_span`
   - `add_string_constant`
   - `add_float_constant`
   - `add_proto_child`
   - `add_lineinfo`

3. **Lines 103-139 register management**:
   - Add `free_to_reg(cu, reg)` and `enter_scope`/`leave_scope`.
   - `leave_scope` must restore `locals_len`, `nactvar`, and `freereg`, close upvalues, and emit `CLOSE/TBC` when required.

4. **Lines 141-218 literals**:
   - `emit_load_integer` must use `LOADI` only when `n` fits signed 17-bit `sBx`; otherwise add integer constant and emit `LOADK/LOADKX`.
   - Add:
     - `emit_load_float`
     - `emit_load_string`
     - `emit_load_constant`

5. **Lines 219-331 arithmetic/unary**:
   - Add emitters for all Lua binary/unary operators:
     - `POW`, `BAND`, `BOR`, `BXOR`, `SHL`, `SHR`, `CONCAT`
     - `UNM`, `BNOT`, `NOT`, `LEN`
   - Ensure arithmetic emitters always emit paired `MMBIN*` as validator expects.

6. **Lines 345-401 calls/tables**:
   - Add:
     - `emit_gettable`, `emit_settable`
     - `emit_getfield`, `emit_setfield`
     - `emit_gettabup`, `emit_settabup`
     - `emit_self`
     - `emit_closure`
     - table constructor helpers for array/hash fields.

7. **Lines 429-506 jumps/tests**:
   - Replace placeholder-only helpers with patch-list helpers:
     - `new_patch_list`
     - `concat_patch_list`
     - `patch_list_to_current`
     - `emit_testset`
     - `emit_boolean_jump`
   - Keep validator rule: comparisons/tests followed by `JMP`.

8. **Lines 508-537 numeric loop helpers**:
   - Keep `FORPREP/FORLOOP`, add generic-for helpers:
     - `emit_tforprep`
     - `emit_tforcall`
     - `emit_tforloop`

9. **Lines 539-589 returns/locals**:
   - Add `emit_return_multi`, `emit_tailcall`, `emit_varargprep`, `emit_getvarg`.
   - Modify `add_local` to use interned `String*`, scope depth, `startpc`.
   - Add `add_locvar_debug` so `Proto.locvars` is populated.

10. **Lines 598-623 close_func_builder**:
    - Set:
      ```lalin
      p.lineinfo = fs.lineinfo.data
      p.lineinfo_len = fs.lineinfo.len
      p.source = cu.source_name
      p.linedefined = ...
      p.lastlinedefined = ...
      ```
    - If no explicit return was emitted, emit `RETURN0` before closing.
    - Ensure `maxstack >= 1`.

11. **Return table lines 626-685**: Export all new helpers.

**Patterns to enforce**
- No wildcard “unsupported” codegen path for grammar that parser accepts.
- Every allocation helper has `ok`, `step_required`, `oom`.

**Danger zones**
- Validator requires arithmetic op + adjacent `MMBIN*`.
- `JMP` target encoding in `patch_jump_to_current` must match `validate.lua:287-294`.

---

#### `experiments/lua_interpreter_vm/src/regions_lexer.lua`

**Goal**: Implement complete Lua 5.5 lexical semantics.

**Edit blocks**
1. **Lines 47-97 `keyword_kind`**: Add `global` and `goto`.
   - `global` length 6.
   - `goto` length 4.

2. **Lines 112-121 whitespace/comment handling**:
   - Recognize long comments `--[=*[ ... ]=*]`.
   - Preserve correct line/col through CRLF, LF, CR.

3. **Lines 124-128 token dispatch**:
   - Replace `scan_int` with `scan_number_start`.
   - Add `.123` handling before `TOK_DOT`.
   - Add hex numerals `0x`, decimal exponent, hex float `p/P`.

4. **Lines 139-216 name/int scanning**:
   - Keep name hash logic.
   - Replace duplicate keyword checks with call to `keyword_kind`; do not maintain two divergent keyword tables.

5. **Lines 217-240 string scanning**:
   - Replace simple close-quote search with:
     - short string escape decoder
     - `\a\b\f\n\r\t\v\\\"\'`
     - decimal `\ddd`
     - hex `\xXX`
     - UTF-8 `\u{...}`
     - whitespace skip `\z`
   - Token should carry original source span; decoded bytes go through compiler scratch when parser asks for string value.

6. **After string scanner**: Add long string scanner:
   - `[=*[ ... ]=*]`
   - Strip initial newline as Lua requires.
   - Return `TOK_STRING`.

7. **Lines 241-327 operator dispatch**:
   - Add caret `^`.
   - Ensure `...`, `..`, `.`, `.number` precedence is correct.
   - `::` remains label token.

8. **Error blocks line 368**:
   - Use explicit errors:
     - malformed number
     - malformed string
     - unfinished long string/comment
     - unexpected char

**Patterns to enforce**
- Lexer only tokenizes and records spans/decoded numeric bits; durable strings are interned later.
- All line changes update `line` and `col`.

**Danger zones**
- `.123` must not become `DOT INT`.
- `global`/`goto` must not be `NAME`.

---

#### `experiments/lua_interpreter_vm/src/regions_parser.lua`

**Goal**: Replace the current arithmetic slice with a complete Lua 5.5 recursive-descent direct bytecode compiler.

**Edit blocks**
1. **Lines 24-38 `exp_to_reg`**:
   - Replace with final expression discharge helpers:
     - `exp_to_any_reg`
     - `exp_to_next_reg`
     - `exp_to_value`
     - `exp_to_condition`
     - `exp_to_assignment_target`
   - These must handle locals, upvalues, globals, indexed vars, constants, calls, varargs, and jump expressions.

2. **Lines 40-137 `parse_primary`**:
   - Replace with prefix/simple expression stack:
     - literals: nil/false/true/int/float/string
     - `...`
     - function literals
     - table constructors
     - parenthesized expressions
     - names as variables/global accesses
   - Add suffix loop for:
     - `.name`
     - `[expr]`
     - `:method(args)`
     - function calls with `()`, table args, string args.

3. **Lines 139-343 expression parser**:
   - Replace `parse_term`/`parse_expr` with Pratt or precedence-climbing parser covering:
     ```text
     or
     and
     < <= > >= ~= ==
     |
     ~
     &
     << >>
     ..
     + -
     * / // %
     unary not # - ~
     ^
     ```
   - Right-associate `^` and `..`.
   - Short-circuit `and/or` must use jump lists, not eager boolean registers.

4. **Lines 345-400 assignment parser**:
   - Replace single local assignment with full `varlist = explist`.
   - Implement simultaneous assignment and multi-result adjustment.
   - Support global/upvalue/table assignment.
   - Reject assigning to `<const>` locals.

5. **Lines 403-447 return parser**:
   - Support `return explist? ;?`.
   - Emit `RETURN`, `RETURN0`, `RETURN1` according to result count.
   - Multi-result last expression must remain open until return emission.

6. **Lines 449-510 local parser**:
   - Support:
     - `local attnamelist`
     - `local attnamelist = explist`
     - `local function name funcbody`
   - Attributes:
     - `<const>` marks immutable local.
     - `<close>` emits `TBC` and marks scope has TBC.

7. **Lines 512-573 statement dispatch**:
   - Add branches for:
     - `break`
     - `goto`
     - label `:: name ::`
     - `do block end`
     - `while exp do block end`
     - `repeat block until exp`
     - `if exp then block {elseif exp then block} [else block] end`
     - numeric `for`
     - generic `for`
     - `function funcname funcbody`
     - `global` declarations
     - call statements.

8. **Lines 575-615 block parser**:
   - Add terminator-aware block parsing.
   - Block must stop on `end`, `else`, `elseif`, `until`, or EOF depending on caller.
   - Enter/leave lexical scopes around every block.
   - Patch breaks/gotos on scope exit.

9. **Lines 617-659 compile_prepared_unit**:
   - Initialize root `_ENV`/global declaration state.
   - Parse full chunk.
   - If chunk has no explicit return, emit implicit `RETURN0`.
   - Resolve pending gotos.
   - Close builder.
   - Propagate `step_required`.

10. **Return table lines 665-680**:
    - Export final parser regions only; remove obsolete `parse_term` if replaced.

**Patterns to enforce**
- No undeclared-name semantic error for normal names; bare names lower through `_ENV`/global rules.
- Every block has explicit scope enter/leave.
- Parser emits bytecode through named codegen helpers only.

**Danger zones**
- Multiple assignment must evaluate RHS before storing LHS.
- `goto` must not enter scope containing locals or TBC variables.
- `repeat ... until` condition sees block locals per Lua rules.

---

#### `experiments/lua_interpreter_vm/src/op/arithmetic.lua`

**Goal**: Complete arithmetic, bitwise, power, and metamethod fallback semantics reached by source compiler.

**Edit blocks**
1. **Lines 108-139 `op_mod`/`op_idiv`**:
   - Replace truncating `%` and `/` integer behavior with Lua floor division/modulo.
   - Negative cases must match PUC Lua 5.5.

2. **Lines 142-146 `op_pow`**:
   - Implement integer/float power using an explicit runtime helper.
   - If Lalin lacks intrinsic pow, add host/VM numeric helper rather than returning `ERR_ARITH`.

3. **Lines 376-380 `op_powk`**:
   - Same as `op_pow`, constant RHS path.

4. **Lines 495-517 `op_mmbin*`**:
   - Implement metamethod dispatch:
     - reconstruct operands from previous arithmetic opcode and `MMBIN*`
     - call selected metamethod via `prepare_call`
     - save `ResumeState.kind = RESUME_BINOP_MM`
     - on return, place result in saved destination register.
   - Missing metamethod raises `ERR_ARITH`.

**Patterns to enforce**
- Fast primitive path advances `pc + 2`.
- Metamethod path advances through call continuation, not direct `pc + 2`.

**Danger zones**
- `frame.resume.a` currently stores destination in some arithmetic fast-fail paths; standardize it before implementing `MMBIN`.

---

#### `experiments/lua_interpreter_vm/src/regions_value.lua`

**Goal**: Provide value conversion/comparison protocols needed by full Lua source.

**Edit blocks**
1. **Lines 40-54 `value_to_number`**:
   - Add string-to-number conversion for Lua numeric strings.
   - Return explicit integer/float/not_number.

2. **Lines 75-83 `value_to_string`**:
   - Implement number-to-string allocation through `string_intern`.
   - Keep `oom` explicit.

3. **Lines 159-177 `value_equal`**:
   - Add `__eq` metamethod lookup for matching metamethod cases.
   - Use `call_mm` continuation instead of returning false immediately.

4. **Lines 181-247 comparisons**:
   - Add `__lt`/`__le` lookup.
   - `__le` must fall back to `__lt` where Lua requires.

**Patterns to enforce**
- Conversion helpers return typed continuations, not encoded booleans.
- Any allocation exposes `oom`.

**Danger zones**
- Equality metamethod is not attempted for all unequal primitive values; follow Lua semantics.

---

#### `experiments/lua_interpreter_vm/src/op/compare.lua`

**Goal**: Wire comparison metamethod continuations so compiled relational expressions execute correctly.

**Edit blocks**
1. **Lines 6-94 `op_eq`, `op_lt`, `op_le`**:
   - Replace current error-only metamethod branch with call setup.
   - Save resume kind `RESUME_EQ_MM`, `RESUME_LT_MM`, `RESUME_LE_MM`.

2. **Lines 97-171 immediate/constant comparisons**:
   - Apply same metamethod/error behavior for `EQK`, `EQI`, `LTI`, `LEI`, `GTI`, `GEI`.

3. **Lines 173-209 tests**:
   - Keep `TEST/TESTSET` primitive truthiness; no metamethod.

**Patterns to enforce**
- Comparison op remains followed by `JMP`.
- Result controls skip/jump, not register boolean unless parser requested a value.

**Danger zones**
- Inverted operands for `GTI/GEI` must preserve Lua result.

---

#### `experiments/lua_interpreter_vm/src/op/misc.lua`

**Goal**: Complete length, concat, close/TBC behavior needed by source constructs.

**Edit blocks**
1. **Lines 6-92 `op_len`**:
   - Complete `__len` call path and resume state.
   - Primitive string/table length remains fast.

2. **Lines 94-141 `op_concat`**:
   - Implement concat metamethod path via `RESUME_CONCAT_MM`.
   - Use `value_to_string` for number/string conversion.

3. **Lines 143-178 `op_close`, `op_tbc`, `op_errnnil`**:
   - Ensure TBC chain records enough state for close on normal return and error.
   - `op_errnnil` must report correct runtime error for closed variables.

**Patterns to enforce**
- Concatenation writes final value to register `A`.
- TBC never silently skips `__close`.

**Danger zones**
- `__close` can yield/error; resume state must preserve original error.

---

#### `experiments/lua_interpreter_vm/src/regions_error.lua`

**Goal**: Finish protected unwind and to-be-closed variable semantics for source `<close>`, errors, and `pcall`.

**Edit blocks**
1. **Lines 56-103 `tbc_close_chain`**:
   - Replace fail-loud `have_close` block with real `__close` invocation.
   - Save `RESUME_TBC_CLOSE`.
   - Pass original error object as second argument where Lua requires.

2. **Lines 134-186 `raise_error`**:
   - Preserve `L.err_value` and `last_error_code`.
   - Resume/continue TBC close chain until protected frame or uncaught error.

3. **Lines 213-223 `protected_call`**:
   - Replace immediate failure with protected frame setup + `prepare_call`.
   - Return success/failure through existing explicit continuations.

**Patterns to enforce**
- Error path must be explicit data/control, no host exceptions.
- TBC close is part of unwind, not parser-only behavior.

**Danger zones**
- Do not overwrite original error when `__close` succeeds.

---

#### `experiments/lua_interpreter_vm/src/op/loop.lua`

**Goal**: Complete numeric and generic loop runtime opcodes.

**Edit blocks**
1. **Lines 1-83 `FORPREP/FORLOOP/TFORPREP`**:
   - Verify numeric for handles integer and float loops according to Lua semantics.
   - Replace `ERR_RUNTIME` primitive conversion failures with `ERR_LOOP`.

2. **Lines 85-90 `op_tforcall`**:
   - Implement iterator call:
     - call generator at `A`
     - pass state/control
     - request `C` results
     - save `RESUME_TFORLOOP_CALL`.

3. **Lines 92-109 `op_tforloop`**:
   - Ensure control variable update and jump behavior match Lua.

**Patterns to enforce**
- Generic-for call path may yield.
- Loop register window must match validator `A..A+3`.

**Danger zones**
- `TFORCALL` result placement feeds directly into `TFORLOOP`.

---

#### `experiments/lua_interpreter_vm/src/op/closure.lua`

**Goal**: Complete function literals, closures, upvalues, and varargs.

**Edit blocks**
1. **Lines 5-24 `op_closure`**:
   - Verify child proto/upvalue descriptors are consumed exactly as compiler emits them.

2. **Lines 26-65 `op_vararg`**:
   - Keep current behavior, but align with root chunk/function flags emitted by compiler.

3. **Lines 67-73 `op_getvarg`**:
   - Implement vararg table access if Lua 5.5 `GETVARG` is required by chosen bytecode lowering.
   - Otherwise ensure compiler never emits `GETVARG` and validator rejects it for source products.

4. **Lines 75-84 `op_varargprep`**:
   - Ensure it agrees with `Proto.flag` semantics.

**Patterns to enforce**
- Compiler and runtime must agree on `_ENV` as upvalue 0 if used.
- Vararg misuse is compile-time error where possible.

**Danger zones**
- Closure upvalue metadata can validate but still bind wrong variable if `instack/index` is wrong.

---

#### `experiments/lua_interpreter_vm/src/regions_string.lua`

**Goal**: Support compiler/runtime string allocation and conversions.

**Edit blocks**
1. **Lines 10-20**: Keep `string_hash`; use it from lexer/codegen for names.
2. **Lines 22-100 `string_intern`**:
   - Verify it handles zero-length strings.
   - Add `step_required` continuation or explicitly document allocation treats step as `oom`; final compiler should expose `step_required`.
3. **Lines 102-176 `string_concat_range`**:
   - Free temporary concat buffer or make ownership explicit if current allocator requires it.

**Patterns to enforce**
- Source string literals are decoded into temporary bytes, then interned.
- `String.bytes` must outlive source buffer.

**Danger zones**
- Do not store source-buffer pointers in `Proto.constants`.

---

#### `experiments/lua_interpreter_vm/src/compat.lua`

**Goal**: Expose the allocator-aware source frontier.

**Edit blocks**
1. **Line 12**:
   - Before:
     ```lua
     source_frontier = compiler.compile_lua_source_into,
     ```
   - After: keep same exported name but updated region signature.
   - Add comment:
     ```lua
     -- Source frontier requires LuaThread/GlobalState allocator ownership.
     ```

**Patterns to enforce**
- PUC remains oracle-only.
- Binary chunks remain separate frontier.

---

#### `experiments/lua_interpreter_vm/src/init.lua`

**Goal**: Load any new compiler modules before `regions_compiler`.

**Edit blocks**
1. **Lines 34-38**:
   - If parser/codegen is split, add:
     ```lua
     vm.regions_compile_alloc = require(...)
     vm.regions_parser_expr = require(...)
     vm.regions_parser_stmt = require(...)
     ```
   - Keep `regions_compiler` loaded after lexer/parser/codegen helpers.

**Patterns to enforce**
- Module order must satisfy Lalin region symbol availability.

**Danger zones**
- Cyclic requires can break host region compilation.

---

### New Files

#### `experiments/lua_interpreter_vm/src/regions_compile_alloc.lua`
- **Purpose**: Compiler-specific arena and durable-vector allocation helpers.
- **Contents sketch**:
  - `compile_arena_alloc`
  - `compile_arena_alloc_array`
  - `ensure_builder_stack`
  - helpers for labels/gotos/local temp arrays
- **Imports required**:
  - `regions_allocator`
  - `parser_constants`
  - `parser_products`

#### `experiments/lua_interpreter_vm/tests/test_source_compiler_lua55_oracle.lua`
- **Purpose**: Execute compiled Lua 5.5 source programs in Lalin VM and compare observable results/errors against `.vendor/Lua/lua`.
- **Contents sketch**:
  - shared compile/run harness using `tools/vm_ffi_schema.lua`
  - oracle runner invoking `.vendor/Lua/lua`
  - cases for literals, expressions, blocks, loops, functions, tables, globals, varargs, labels/goto, attributes, errors
- **Imports required**:
  - `experiments.lua_interpreter_vm.src.init`
  - `experiments.lua_interpreter_vm.tools.vm_ffi_schema`

#### `experiments/lua_interpreter_vm/tests/test_source_lexer_lua55.lua`
- **Purpose**: Exhaustive lexer tests for numerals, strings, long comments, `global`, `goto`.
- **Contents sketch**:
  - token kind sequences
  - decoded literal value checks through compilation
  - malformed token error checks

---

### Order of Operations

1. Add `tools/vm_ffi_schema.lua`.
2. Replace stale cdefs in `test_parser_compile.lua` and `tools/jit_harness/compile.lua`; verify segfault is gone.
3. Extend `parser_constants.lua` and `parser_products.lua`; update shared FFI schema immediately after.
4. Add compiler allocation helpers and allocator growth helpers.
5. Change `regions_compiler.lua` ABI and update all wrappers/tests.
6. Rework `regions_codegen.lua` so produced `Proto`s own code/constants/children/metadata.
7. Complete lexer.
8. Replace parser with full Lua 5.5 grammar lowering.
9. Complete runtime opcode dependencies: arithmetic/metamethods, comparisons, concat/len, loops, closures/varargs, TBC/protected calls.
10. Update `compat.lua` and `init.lua`.
11. Add oracle tests and expand existing parser/compiler tests to inspect returned `Proto`.

---

### Testing Strategy

- After schema fix:
  ```sh
  luajit experiments/lua_interpreter_vm/tests/test_parser_compile.lua
  ```
  Expected: no segfault; failures should be ordinary assertions/statuses.

- After compiler ABI change:
  - Run parser compile test.
  - Run validation contract:
    ```sh
    luajit experiments/lua_interpreter_vm/tests/test_vm_validation_contract.lua
    ```

- After codegen changes:
  - Every compiled source case must pass `validate_proto` before execution.
  - Add checks for `return`, empty chunk, and chunks without explicit return.

- After lexer changes:
  ```sh
  luajit experiments/lua_interpreter_vm/tests/test_source_lexer_lua55.lua
  ```

- After parser/runtime completion:
  ```sh
  luajit experiments/lua_interpreter_vm/tests/test_source_compiler_lua55_oracle.lua
  luajit experiments/lua_interpreter_vm/tests/test_vm_opcode_semantics.lua
  luajit experiments/lua_interpreter_vm/tests/test_vm_integration.lua
  luajit experiments/lua_interpreter_vm/tests/test_vm_e2e.lua
  ```

- Oracle comparison rule:
  - PUC Lua 5.5 supplies source semantics only.
  - Do not compare PUC bytecode or internal layouts.

---

### Pattern Memo

- All durable compiler output is VM-owned: code, constants, strings, child protos, locvars, upvals, lineinfo.
- All allocation paths expose `ok`, `step_required`, `oom`.
- Parser accepts only grammar it lowers to executable, validated VM bytecode.
- Bare names lower through `_ENV`/global declaration semantics, not undeclared-name errors.
- Arithmetic bytecode that can metamethod must emit required adjacent `MMBIN*`.
- Every scope enter has a matching scope leave restoring locals/registers and handling upvalues/TBC.
- Shared FFI schema is the only test/tool struct definition source.

## Worker Output — 2026-05-30 14:19:43

## Completed
- Fixed `test_parser_compile.lua` segfault cause by replacing stale inline FFI struct copies with a shared schema.
- Added shared LuaJIT FFI schema at `experiments/lua_interpreter_vm/tools/vm_ffi_schema.lua`, synchronized with current VM/compiler products including the trailing `CompileUnit` fields and `LuaThread.coroutine`.
- Updated JIT harness to use the shared schema and stopped hidden fallback compilation by default; fallback is now only an explicit `force_fallback` harness escape hatch.
- Expanded source compiler coverage:
  - Lexer now reserves Lua 5.5 `global` and `goto`.
  - Lexer recognizes `^`.
  - Parser/codegen now compile and execute integer bitwise `&`.
  - Chunks without explicit return now get implicit `RETURN0`.
  - Root compiler builder starts with executable `maxstack >= 1`.
- Added codegen helpers for more arithmetic/bitwise/unary/compare lowering groundwork.
- Updated validator to accept paired unary metamethod bytecode shape for `UNM`/`BNOT` groundwork.
- Fixed runtime integer `//` and `%` for negative values to match Lua floor division/modulo semantics.
- Expanded parser compile tests to cover:
  - shared FFI schema sanity
  - `global`, `goto`, `^` lexing
  - implicit `RETURN0`
  - bitwise `&` source execution
  - negative floor division/modulo source execution

## Files Changed
- `experiments/lua_interpreter_vm/tools/vm_ffi_schema.lua` - new shared FFI schema for tests/tools.
- `experiments/lua_interpreter_vm/tests/test_parser_compile.lua` - removed stale inline cdef, added schema use and new compiler/runtime cases.
- `experiments/lua_interpreter_vm/tools/jit_harness/compile.lua` - uses shared schema; no hidden fallback by default.
- `experiments/lua_interpreter_vm/src/parser_constants.lua` - added `CARET`, `GLOBAL`, `GOTO`, and explicit future discriminants/errors.
- `experiments/lua_interpreter_vm/src/regions_lexer.lua` - lexes `global`, `goto`, `^`.
- `experiments/lua_interpreter_vm/src/regions_codegen.lua` - added bitwise/unary/compare codegen helpers; ensures `maxstack >= 1`.
- `experiments/lua_interpreter_vm/src/regions_parser.lua` - implicit return; parses/lowers `&`.
- `experiments/lua_interpreter_vm/src/regions_compiler.lua` - explicit legacy ownership note; starts root maxstack at 1.
- `experiments/lua_interpreter_vm/src/validate.lua` - validator accepts unary `UNM`/`BNOT` paired `MMBIN` shape.
- `experiments/lua_interpreter_vm/src/op/arithmetic.lua` - floor semantics for integer `%` and `//`.

## Tests Run
- `luajit experiments/lua_interpreter_vm/tests/test_parser_compile.lua` ✅
- `luajit experiments/lua_interpreter_vm/tests/test_vm_validation_contract.lua` ✅
- `luajit experiments/lua_interpreter_vm/tests/test_vm_opcode_semantics.lua` ✅
- `luajit experiments/lua_interpreter_vm/tests/test_vm_components.lua` ✅
- `luajit experiments/lua_interpreter_vm/tests/test_jit_harness.lua` ✅
- `luajit experiments/lua_interpreter_vm/tests/test_vm_integration.lua` ✅
- `luajit experiments/lua_interpreter_vm/tests/test_vm_e2e.lua` ✅
- `luajit experiments/lua_interpreter_vm/tests/test_vm_compat_frontier.lua` ✅

## Notes
Actual source features now compiled/executed include integer locals/assignment/return, arithmetic `+ - * / % //`, integer bitwise `&`, implicit empty/non-return chunk return, and negative integer floor `%`/`//`.

Remaining blockers: full allocator-owned compiler ABI is not complete; constants/strings/functions/tables/control-flow/full Lua 5.5 grammar remain incomplete; fallback metamethod paths, power, full globals/`_ENV`, and source string/numeric literal completeness still need substantial work.
