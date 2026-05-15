# MOM parser implementation

Native Moonlift parser-core code lives here.

## `native_lexer.mlua`

Despite the historical name, this module now contains the compiled native
front-end core:

- byte lexer over `ptr(u8)+len`: `mom_lex_into`
- token classification and keyword recognition
- string/comment/antiquote scanning
- shallow module parse event pass: `mom_parse_module_events`
- recursive parser event pass: `mom_parse_full_events`
  - top-level declarations
  - function params and result types
  - recursive type parsing
  - Pratt expression parsing
  - statement-list parsing for `let`/`var`/`if`/`switch`/`return`/`yield`/`jump`/`emit`

The implementation writes into caller-provided buffers. That is intentional:
OS/libc allocation and file IO are adapters around this pure buffer-to-token /
buffer-to-event core.

## `native_ast.lua`

Verification harness over the native token tape. It materializes existing
Lua/PVM MoonTree values so native token/parser behavior can be compared against
today's pipeline. It is not part of the native compiler dependency graph.

## `native_core.mlua`

Compiled Moonlift parser core producing native AST tapes in caller-provided
buffers. This is where parser state, node builders, list builders, and recovery
belong. The parser API is functions; hot loops, scanners, statement-list
walking, and recovery paths use jump-first regions / block loops internally.
