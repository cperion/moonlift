# MOM — Moonlift On Moonlift

The Moonlift compiler, rewritten in Moonlift. Zero Lua in the compiler core at
runtime.

MOM is the whole pipeline: source bytes → scanner/lexer → parser → MoonTree AST
→ binding/opening/typecheck → Back.Cmd lowering → validation/vectorization →
backend execution. Every compiler phase is a Moonlift `func` or `region`.
Every compiler dispatch is a Moonlift `switch`; compiler data choice is
`select`; compiler control choice is `if`/`jump`/`emit`.

Lua is only the staging layer for building/specializing MOM itself —
`moon.stmts [[ ]]` + `@{...}` generates specialized Moonlift compiler code.
The generated compiler runs as native code.

See [PORTING_GUIDE.md](PORTING_GUIDE.md) for the full porting strategy and
[PARSER_DESIGN.md](PARSER_DESIGN.md) for the native parser/source-to-AST design.

## Current status

The schema seed exists and native parser work has started. `parser/native_lexer.mlua`
is a native token tape lexer over `ptr(u8)+len`, plus native parse-event passes.
`parser/native_ast.lua` is a verification harness that materializes today's
Lua/PVM MoonTree values from the native token tape to compare against the
existing pipeline; it is outside the compiler dependency graph. The MOM parser
core is `parser/native_core.mlua`: compiled Moonlift parser functions/regions
that write native AST tapes into caller-provided buffers. `driver/wire.mlua`
writes MLBT v3 buffers directly into caller-provided memory for fully checked
BackProgram data. Parser tapes must not be serialized directly to backend
commands. The standalone `mom` binary links LuaJIT, embedded Moonlift/MOM
sources, and the Rust Cranelift backend; its CLI uses the production semantic
pipeline while native MOM semantic phases continue to be ported. OS integration
can be done through Moonlift `extern` calls to libc; the parser core itself
remains a pure buffer-to-AST component.

## Schema seed

Current translated schema files:

| File | Purpose | Status |
|------|---------|--------|
| `schema/MoonCore.mlua` | core scalar/operator/id types | ✓ |
| `schema/MoonBack.mlua` | backend command/fact/validation types | ✓ seed |
| `schema/MoonSource.mlua` | source ranges/anchors/document types | ✓ seed |
| `schema/MoonLink.mlua` | link plan/result types | ✓ seed |
| `schema/MoonCyclic.mlua` | combined cyclic group: MoonOpen/MoonType/MoonBind/MoonSem/MoonTree/MoonVec/MoonHost extras | ✓ seed |
| `schema/MoonParse.mlua` | native parser token tape/island/splice/output types | ✓ seed |
| `schema/MoonMlua.mlua` | mlua document parse/analysis types | ✓ seed |
| `schema/MoonDasm.mlua` | disassembly/inspection types | ✓ seed |
| `schema/MoonEditorLspRpc.mlua` | editor/LSP/RPC combined types | ✓ seed |

The schema is a seed, not the compiler. The next work is executable native
Moonlift code for the pipeline.

## Immediate design work

1. Keep expanding `MoonParse` as implementation needs demand.
2. Extend native scanner/lexer coverage and document scanner/island handling.
3. Implement native typed AST/open/typecheck phases and parity tests against the
   Lua frontend.
4. Implement tree_to_back-equivalent lowering only after typed semantics are
   available, then serialize checked BackProgram data through MLBT v3.
