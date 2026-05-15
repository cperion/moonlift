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

The schema seed exists. The major missing front-end piece is the native parser
layer: `ptr(u8)+len` source buffers, token tape, island scanner, Pratt
expression parser, recursive-descent statement/type parser, and AST builders
that produce MoonTree ASDL directly. OS integration can be done through
Moonlift `extern` calls to libc; the parser core itself should remain a pure
buffer-to-AST component.

## Schema seed

Current translated schema files:

| File | Purpose | Status |
|------|---------|--------|
| `schema/MoonCore.mlua` | core scalar/operator/id types | ✓ |
| `schema/MoonBack.mlua` | backend command/fact/validation types | ✓ seed |
| `schema/MoonSource.mlua` | source ranges/anchors/document types | ✓ seed |
| `schema/MoonLink.mlua` | link plan/result types | ✓ seed |
| `schema/MoonCyclic.mlua` | combined cyclic group: MoonOpen/MoonType/MoonBind/MoonSem/MoonTree/MoonVec/MoonHost/MoonParse extras | ✓ seed |
| `schema/MoonMlua.mlua` | mlua document parse/analysis types | ✓ seed |
| `schema/MoonDasm.mlua` | disassembly/inspection types | ✓ seed |
| `schema/MoonEditorLspRpc.mlua` | editor/LSP/RPC combined types | ✓ seed |

The schema is a seed, not the compiler. The next work is executable native
Moonlift code for the pipeline.

## Immediate design work

1. Add/expand a real `MoonParse` schema: `SourceBuffer`, `TokenKind`, `Token`,
   `TokenTape`, `Island`, `ParseCursor`, `SpliceSlot`, builders/freeze results.
2. Implement native scanner/lexer regions over `ptr(u8)+len`.
3. Implement Pratt expression parsing and recursive-descent statement/type/top
   level parsing that constructs MoonTree ASDL directly.
4. Then port phases in dependency order: open/bind/typecheck → tree lowering →
   control facts → back validation/inspection → vectorization/link/execution.
