# MOM — Agent Guidance

MOM is the native Moonlift compiler port. The goal is not to wrap or simulate
the Lua compiler. The goal is a real compiler core written in Moonlift: source
bytes enter as `ptr(u8)+len`, typed compiler data flows through native phases,
and the result is `BackProgram` data handed to the backend.

Lua may stage/build MOM, generate specialized Moonlift source, and run tests.
Lua must not be a parser, materializer, semantic phase, or lowering runtime for
MOM.

## Source of Truth

**THE FIRST SOT FOR IMPLEMENTATION IS THE ACTUAL MOONLIFT LUA CODE ALREADY PRESENT IT WORKS WELL THATS WHY WE CAN BUILD THE MOM ON IT.**
Always go look at /home/cedric/dev/moonlift/lua/moonlift

Read these before changing direction:

| File | Purpose |
|---|---|
| `lua/moonlift/mom/PORTING_GUIDE.md` | Porting contract, phase plan, module organization, lowering discipline |
| `lua/moonlift/mom/PARSER_DESIGN.md` | Native parser/source-to-AST design |
| `lua/moonlift/mom/README.md` | Current MOM status and high-level map |
| `lua/moonlift/mom/parser/README.md` | Parser implementation boundaries |
| `LANGUAGE_REFERENCE.md` | Moonlift language semantics |
| `SOURCE_GRAMMAR.md` | Source grammar contract |
| `lua/moonlift/schema/*.lua` | Current ASDL source of truth |
| `lua/moonlift/mom/schema/*.mlua` | MOM schema seed |
| current Lua phase modules under `lua/moonlift/` | Behavioral reference, not architecture to copy |

When in doubt, the current Lua compiler is a **behavioral oracle**. It is not a
design template. Port compiler meaning, not Lua/PVM mechanics.

## Non-Negotiable Discipline

1. No “for now”, “temporary”, “bridge”, “bootstrap shortcut”, or “we can fix it later” framing in plans or code comments.
2. Make design choices explicit. If a representation is chosen, document why and define the typed interface.
3. No Lua runtime dependency in compiler-core modules.
4. No Lua materialization path as part of MOM. Verification harnesses may compare against Lua but must stay outside the native dependency graph.
5. No hidden side tables. State is passed as typed structs, builders, arenas, cursors, and views.
6. No stringly dispatch. Use enum/tag integers, interned ids, or typed unions.
7. No PVM-style phase cache in MOM. Use `func` + `switch`, regions, explicit builders, and explicit symbol maps.
8. Every native module must compile independently and have a focused test.
9. Every control-flow path in Moonlift regions/blocks terminates with `jump`, `yield`, or `return`.
10. Target-program control is emitted as `Back.Cmd` data. MOM's own `block`/`jump` controls the compiler, not the user's program.

## Correct Framing

Use this language:

- “verification harness” for Lua comparison code
- “native compiler dependency graph” for real MOM modules
- “typed tape/accessor representation” for SoA data
- “arena-owned union values” for direct typed AST/IR values
- “implementation gap” for behavior missing in current Lua
- “design contract” for chosen representation/API

Avoid this language:

- “for now”
- “temporary”
- “compatibility bridge”
- “first step” when it means an escape hatch
- “later” as a substitute for a design decision
- “acceptable until...”

## Module Organization

Follow `PORTING_GUIDE.md` section 14.

Current intended layout:

```text
lua/moonlift/mom/
  runtime/      -- arenas, builders, strings, sets, diagnostics
  parser/       -- source scan, lex, parse cursor/type/expr/stmt/item/module
  open/         -- open facts, validation, expansion
  typecheck/    -- env, expr/place/stmt/control/func/module typing
  layout/       -- layout env/type/field/resolve
  back/         -- ids, env, ops, ABI, memory, address, expr, stmt, control, func, module, validate
  vec/          -- facts, decision, plan, lowering, validation
  driver/       -- source/module to BackProgram and backend FFI adapters
  tests/        -- focused tests per layer
```

A compiler `.mlua` module should be one of:

1. data schema module
2. pure helper module
3. builder/runtime module
4. compiler phase module
5. driver module

Do not mix these roles.

## Implementation Pattern

### Pure dispatch helpers

Use `func` with `switch`:

```moonlift
func mb_lower_compare_op(op: i32, scalar: i32) -> i32
    let is_float: bool = mb_is_float_scalar(scalar)
    switch op do
    case CMP_EQ then return select(is_float, BACK_FCMP_EQ, BACK_ICMP_EQ)
    default then return 0
    end
end
```

Use `select` for scalar compiler values only. If constructing different union
variants or emitting different effects, use `if`/`switch`.

### Stateful walkers/lowerers

Use regions or explicit state-returning funcs. Thread state through typed block
params or result structs:

```moonlift
region lower_stmt_list(stmts: view(Stmt), st: LowerState;
                       done: cont(st: LowerState, flow: Flow))
entry loop(i: index = 0, st0: LowerState = st)
    if i >= len(stmts) then jump done(st = st0, flow = FallsThrough) end
    emit lower_stmt(stmts[i], st0; done = next)
end
block next(st1: LowerState, flow1: Flow)
    if flow1 == Terminates then jump done(st = st1, flow = Terminates) end
    jump loop(i = i + 1, st0 = st1)
end
end
```

### Builders

Builders never allocate. They append if capacity allows and always advance
`len`, so callers know required capacity.

```moonlift
func push(b: ptr(Builder), value: T) -> index
    let i: index = b.len
    if i < b.cap then b.data[i] = value end
    b.len = i + 1
    return i
end
```

Allocation belongs in runtime/arena/driver modules, not in phase logic.

## Current Native Groundwork

Existing native MOM modules:

| File | Role |
|---|---|---|
| `runtime/builders.mlua` | allocation-free typed builders |
| `runtime/sets.mlua` | allocation-free integer maps for symbol/fact ids |
| `back/ids.mlua` | backend id allocator core |
| `back/env.mlua` | function-local backend environment frames |
| `back/ops.mlua` | pure backend op/scalar selection helpers |
| `driver/wire.mlua` | allocation-free MLBT v3 binary backend ABI writer |
| `driver/backend_ffi.mlua` | native MLBT v3 Rust backend FFI adapter |
| `driver/lower_wire.mlua` | wire boundary; parser tapes must not bypass semantic phases |
| `parser/document_scan.mlua` | native `.mlua`/document island scanner over `ptr(u8)+len` |
| `parser/native_lexer.mlua` | native lexer and parse-event scanner |
| `parser/native_core.mlua` | native parser recognition core with internal compact storage |
| `parser/native_tree.mlua` | native typed AST arena materializer for the parser output boundary |
| `vec/vec_facts.mlua` | Phase 8a: loop recognition → VecFact tape |
| `vec/vec_decide.mlua` | Phase 8b: VecFact → legal/illegal decision |
| `vec/vec_plan.mlua` | Phase 8c: decision → VecKernelPlan |
| `vec/vec_lower.mlua` | Phase 8d: plan → BackCmd vector blocks |

Verification harness code:

| File | Role |
|---|---|
| `parser/native_ast.lua` | compares native token/parser behavior against current Lua/PVM pipeline |

Verification harness code must not be imported by native compiler modules.

## Tests

Run focused tests after edits:

```sh
luajit tests/test_mom_groundwork.lua            # MOM compiler foundation
luajit tests/test_mom_document_scan.lua         # Native document/island scanner
luajit tests/test_mom_native_lexer.mlua         # Native lexer
luajit tests/test_mom_native_core.lua           # Native parser core
luajit tests/test_mom_native_tree.lua           # Native typed AST output boundary
luajit tests/test_mom_native_ast.lua            # Native AST verification
luajit tests/test_mom_check_correctness.mlua    # Schema correctness
luajit tests/test_mom_vec.lua                   # Vectorization pipeline
luajit tests/test_mom_wire.lua                  # MLBT v3 wire format
luajit tests/test_mom_source_to_binary.lua      # MOM API source → MLBT → execute
luajit tests/test_mom_cli.lua                   # Standalone MOM binary run/object paths
```

Regression for region-id collision:

```sh
luajit tests/test_control_region_id_collision.lua
```

When touching general Moonlift parser/type/lowering behavior, also run relevant
existing tests, for example:

```sh
luajit tests/test_parse_typecheck.lua
luajit tests/test_region_normal_form_recursive.lua
luajit tests/test_switch_stmt_lowering.lua
```

## Porting Workflow for AI Agents

1. Read `PORTING_GUIDE.md` and the relevant Lua behavioral reference module.
2. Identify the compiler meaning: inputs, outputs, invariants, issues.
3. Choose the native representation deliberately: struct/view/SoA accessor/arena union.
4. Add or extend a small `.mlua` module with one responsibility.
5. Add a focused Lua harness that compiles the module and calls exported funcs through FFI.
6. Compare against the Lua pipeline only as an oracle, never as a runtime dependency.
7. Run tests and report exact commands.
8. Keep docs in sync when a design contract changes.

## Review Checklist

Before considering a change complete:

- [ ] No forbidden “for now” framing was introduced.
- [ ] Native modules do not import Lua verification harnesses.
- [ ] State is typed and explicit.
- [ ] Dispatch is `switch`, not strings/callbacks.
- [ ] Builders have documented capacity behavior.
- [ ] Region ids and backend ids come from allocators/scopes, not local labels alone.
- [ ] New code compiles as Moonlift.
- [ ] Focused tests pass.
- [ ] The plan/docs still describe the actual design.
