# MOM — Moonlift On Moonlift

MOM is the in-progress port of the Moonlift compiler to Moonlift. It is not yet
the whole compiler, and it has not replaced the production Lua semantic
pipeline.

The target MOM pipeline is: source bytes → scanner/lexer → parser → MoonTree AST
→ binding/opening/typecheck → Back.Cmd lowering → validation/vectorization →
backend execution. The goal is for every compiler phase to be a Moonlift `func`
or `region`, with dispatch as Moonlift `switch` and explicit `if`/`jump`/`emit`
control.

Lua is still used today for the production semantic compiler pipeline and for
staging/specializing MOM modules. The generated MOM components that exist run as
native code, but the complete native compiler does not yet exist.

See [PORTING_GUIDE.md](PORTING_GUIDE.md) for the full porting strategy and
[PARSER_DESIGN.md](PARSER_DESIGN.md) for the native parser/source-to-AST design.

## Current status

The schema seed exists and native parser work has started.
`parser/document_scan.mlua` scans full source buffers and records Moonlift
islands while skipping Lua strings/comments/long brackets. `parser/native_lexer.mlua`
is a native token tape lexer over `ptr(u8)+len`, plus native parse-event passes.
`parser/native_ast.lua` is a verification harness that materializes today's
Lua/PVM MoonTree values from the native token tape to compare against the
existing pipeline; it is outside the compiler dependency graph. The MOM parser
core recognition code is `parser/native_core.mlua`: compiled Moonlift parser
functions/regions that use compact internal storage while parsing, including
top-level union, region, and expression-fragment coverage. The parser output
boundary is `parser/native_tree.mlua`, which materializes those internal records
into a typed AST arena shaped around MoonCyclic surface concepts (Type/Expr/Stmt/Item)
for the next compiler phases. `driver/wire.mlua` writes MLBT v3 buffers directly
into caller-provided memory for fully checked BackProgram data.
Parser tapes must not be serialized directly to backend commands. The standalone
`mom` binary links LuaJIT, embedded Moonlift/MOM sources, and the Rust Cranelift
backend; its CLI uses the production semantic pipeline while native MOM semantic
phases continue to be ported. OS integration can be done through Moonlift
`extern` calls to libc; the parser core itself remains a pure buffer-to-AST
component.

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

The schema is a seed, not the compiler. The native lexer/parser and MLBT wire
pieces are groundwork, not a completed port. The next work is executable native
Moonlift code for each semantic phase with parity tests against the Lua compiler.

## Immediate design work

1. Keep expanding `MoonParse` as implementation needs demand.
2. Extend native scanner/lexer coverage and document scanner/island handling.
3. Implement native typed AST/open/typecheck phases and parity tests against the
   Lua frontend.
4. Implement tree_to_back-equivalent lowering only after typed semantics are
   available, then serialize checked BackProgram data through MLBT v3.
