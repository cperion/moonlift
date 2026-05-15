# MOM Native Parser Design

MOM's front door is native: source bytes go directly to typed MoonTree ASDL.
The parser is not a Lua service and not a string-template pass. It is ordinary
Moonlift code over `ptr(u8)` + `index`, with typed token tapes, typed cursors,
typed arenas, typed diagnostics, and typed AST output.

Moonlift can also call libc through `extern`, so file IO, allocation, mmap,
stdout/stderr diagnostics, and process-level integration are available at the
low level. Keep those OS adapters outside the pure parser core: the core parses
memory buffers; adapters acquire buffers from files/stdin/mmap/etc.

---

## 1. Goals

1. **Whole pipeline input:** `SourceBuffer(data, len, uri)` → `Module` /
   fragments / issues / anchors.
2. **No Lua runtime in the compiler core:** Lua may stage/generate MOM itself,
   but the compiled parser runs as native code.
3. **Zero-copy hot path:** tokens point into source by byte offsets; names and
   literals intern only when semantic identity requires it.
4. **Typed output:** produce MoonTree/MoonOpen/MoonMlua ASDL directly.
5. **Fast recovery:** parse as much as possible, collect `ParseIssue`, continue.
6. **Editor-ready spans:** AST stays semantic; anchors/source ranges are emitted
   side-by-side as typed data.

Non-goal for phase 1: a full concrete syntax tree. Add a CST later only if LSP
recovery needs exact malformed trivia.

---

## 2. Pipeline

```text
OS adapter / host buffer
  -> SourceBuffer(ptr, len, uri, lifetime)
  -> scan_document       -- .mlua segmentation / pure .moon single island
  -> lex_island          -- bytes -> TokenTape
  -> parse_island        -- TokenTape -> AST/frags/decls
  -> parse_module        -- combined MoonTree.Module + issues + anchors
  -> open/bind/typecheck -- existing semantic pipeline, ported later
```

Pure `.moon` files can skip Lua-aware segmentation and become one module island.
`.mlua` files use a lightweight scanner that skips Lua strings/comments/long
brackets and finds hosted Moonlift islands (`func`, `region`, `expr`, `struct`,
`union`, `extern`). Splice evaluation is a staging concern; the native parser
represents splices as typed holes.

---

## 3. OS / libc Adapter Layer

Parser core API should be buffer-based:

```moonlift
func parse_buffer(data: ptr(u8), len: index, uri: ptr(u8)) -> ParseOutput
```

Everything involving the OS is an adapter that obtains a buffer and calls the
core. Moonlift externs make this straightforward:

```moonlift
extern malloc(size: index) -> ptr(u8) as "malloc" end
extern realloc(p: ptr(u8), size: index) -> ptr(u8) as "realloc" end
extern free(p: ptr(u8)) -> void as "free" end

extern open(path: ptr(u8), flags: i32, mode: i32) -> i32 as "open" end
extern read(fd: i32, buf: ptr(u8), count: index) -> index as "read" end
extern close(fd: i32) -> i32 as "close" end
extern write(fd: i32, buf: ptr(u8), count: index) -> index as "write" end
```

Optional later adapters:

- `mmap`/`munmap` for large files
- `fstat` for pre-sized allocation
- `getenv` for config
- `write(2, ...)` for diagnostics

Rule: OS calls produce/acquire bytes; parsing remains deterministic over
`SourceBuffer`.

---

## 4. Core Data Model

Add/expand `MoonParse` schema with these concepts.

```moonlift
struct SourceBuffer
    data: ptr(u8)
    len: index
    uri: DocUri
end

struct SourceSpan
    start: index
    stop: index        -- inclusive or exclusive; choose one and never mix
    line: i32
    col: i32
end
```

Use **exclusive stop offsets** (`[start, stop)`) for implementation simplicity.
Convert to existing `SourceRange` at API boundaries.

### Token tape

For first implementation, use array-of-structs for clarity. If profiling says
lexer/parser wants SoA, split later.

```moonlift
union TokenKind
    | TokEof | TokName | TokInt | TokFloat | TokString | TokNewline
    | TokHole | TokInvalid
    | TokLParen | TokRParen | TokLBrack | TokRBrack
    | TokComma | TokColon | TokDot | TokSemi | TokArrow
    | TokPlus | TokMinus | TokStar | TokSlash | TokPercent
    | TokEq | TokEqEq | TokNe | TokLt | TokLe | TokGt | TokGe
    | TokAmp | TokPipe | TokTilde | TokShl | TokAShr | TokLShr
    | TokFunc | TokStruct | TokUnion | TokExtern | TokType
    | TokLet | TokVar | TokIf | TokThen | TokElseIf | TokElse | TokEnd
    | TokSwitch | TokCase | TokDefault | TokDo
    | TokBlock | TokEntry | TokJump | TokYield | TokReturn
    | TokRegion | TokExpr | TokEmit
    | TokTrue | TokFalse | TokNil | TokAnd | TokOr | TokNot
    | TokView | TokNoAlias | TokReadonly | TokWriteonly
    | TokRequires | TokBounds | TokDisjoint | TokLen
    | TokSameLen | TokWindowBounds | TokAs
end

struct Token
    kind: TokenKind
    start: index
    stop: index
    line: i32
    col: i32
    text_id: i32       -- intern id, splice id, or -1
end

struct TokenTape
    source: SourceBuffer
    tokens: view(Token)
end

struct ParseCursor
    tape: TokenTape
    i: index
end
```

### Builders

MOM needs typed builders because parse lists are everywhere.

```moonlift
struct TokenBuilder data: ptr(Token); len: index; cap: index end
struct IssueBuilder data: ptr(ParseIssue); len: index; cap: index end
struct AnchorBuilder data: ptr(AnchorSpan); len: index; cap: index end
struct StmtBuilder data: ptr(Stmt); len: index; cap: index end
struct ExprBuilder data: ptr(Expr); len: index; cap: index end
-- plus ParamBuilder, FieldBuilder, VariantBuilder, BlockBuilder, etc.
```

The append path uses `realloc` or an arena chunk allocator. Finalization returns
`view(T)`.

---

## 5. Memory and Lifetime

Use two levels:

1. **Source lifetime:** the source buffer must outlive tokens, spans, and any
   zero-copy literal slices.
2. **Parse arena lifetime:** AST values, interned names, token tape, issues,
   anchors, and builders live until the compile session ends.

Recommended initial allocator:

```moonlift
struct ArenaChunk next: ptr(ArenaChunk); used: index; cap: index; data: ptr(u8) end
struct Arena head: ptr(ArenaChunk) end
```

Use libc `malloc/free` for arena chunks. Later, switch file buffers to `mmap`
when useful.

---

## 6. Document / Island Scanner

The document scanner is a byte-level state machine that only understands enough
Lua to skip opaque regions safely:

- skip Lua short strings `'...'`, `"..."`
- skip Lua long brackets `[=[...]=]`
- skip line and long comments
- detect Moonlift island keywords in allowed positions
- track balanced `end` inside islands using Moonlift tokenization rules
- record island kind, byte range, optional assignment-inferred name

```moonlift
union IslandKind | IslandFunc | IslandRegion | IslandExpr | IslandStruct | IslandUnion | IslandExtern end

struct Island
    kind: IslandKind
    start: index
    stop: index
    name_hint: i32     -- intern id or -1
end

struct DocumentScan
    source: SourceBuffer
    islands: view(Island)
    issues: view(ParseIssue)
    anchors: AnchorSet
end
```

For pure `.moon`, create one synthetic module island spanning the whole file.

---

## 7. Lexer Regions

The lexer is the highest-value early port: a jump-first native byte scanner.
Every helper has a typed continuation back to the main loop.

```moonlift
region lex(source: SourceBuffer, toks: ptr(TokenBuilder), issues: ptr(IssueBuilder);
           done: cont(tape: TokenTape))
entry loop(i: index = 0, line: i32 = 1, col: i32 = 1)
    if i >= source.len then
        emit append_token(toks, TokEof, i, i, line, col)
        jump done(tape = freeze_tokens(source, toks))
    end

    let c: u8 = source.data[i]
    if c == 32 or c == 9 or c == 13 then
        jump loop(i = i + 1, line = line, col = col + 1)
    end
    if c == 10 then
        emit append_token(toks, TokNewline, i, i + 1, line, col)
        jump loop(i = i + 1, line = line + 1, col = 1)
    end
    if is_alpha(c) then emit scan_ident(source, toks, i, line, col; done = loop) end
    if is_digit(c) then emit scan_number(source, toks, i, line, col; done = loop) end
    emit scan_operator_or_issue(source, toks, issues, i, line, col; done = loop)
end
end
```

Hot helpers:

- `scan_ident` + keyword classification
- `scan_number` for decimal/hex/int/float/exponent/underscores
- `scan_string` for single-line Moonlift strings
- `scan_comment`
- `scan_antiquote` for `@{...}` with brace balancing and string/comment skip
- `scan_operator_or_issue` for one/two/three-byte operators

Keyword classification should be staged: Lua generates a Moonlift `switch` by
length/first byte/name bytes. The generated compiler code is pure Moonlift and
runs native.

---

## 8. Splices / Holes

The lexer emits `TokHole` for `@{...}`. The token carries a splice id and a
spread flag.

```moonlift
union SpliceRole
    | SpliceExpr | SpliceType | SpliceName | SpliceStmtList
    | SpliceParamList | SpliceFieldList | SpliceVariantList
    | SpliceBlockList | SpliceContList | SpliceSwitchArmList
end

struct SpliceSlot
    id: i32
    role: SpliceRole
    spread: bool
    span: SourceSpan
end
```

The parser decides the role from syntactic position. It records `SpliceSlot`
and returns placeholder/open ASDL nodes:

- expression position → `ExprOpenSlot` / equivalent
- type position → `TypeOpenSlot`
- region/name position → `NameRefSlot`
- spread list → sentinel item plus slot metadata

For a pure native compiler invocation, unresolved splices are diagnostics. For
staged `.mlua`, a staging step resolves slots before handing the final module to
native typecheck/lowering.

---

## 9. Parser API

Cursor primitives:

```moonlift
func peek(cur: ptr(ParseCursor)) -> Token
func peek_kind(cur: ptr(ParseCursor)) -> TokenKind
func advance(cur: ptr(ParseCursor)) -> Token
func accept(cur: ptr(ParseCursor), k: TokenKind) -> bool
func expect(cur: ptr(ParseCursor), k: TokenKind, msg: ptr(u8), issues: ptr(IssueBuilder)) -> Token
func skip_nl(cur: ptr(ParseCursor)) -> void
func skip_sep(cur: ptr(ParseCursor)) -> void
```

Parse functions:

```moonlift
func parse_type(cur: ptr(ParseCursor), arena: ptr(Arena), ctx: ptr(ParseCtx)) -> Type
func parse_expr(cur: ptr(ParseCursor), arena: ptr(Arena), ctx: ptr(ParseCtx), rbp: i32) -> Expr
func parse_stmt(cur: ptr(ParseCursor), arena: ptr(Arena), ctx: ptr(ParseCtx)) -> Stmt
func parse_func(cur: ptr(ParseCursor), arena: ptr(Arena), ctx: ptr(ParseCtx)) -> Func
func parse_region_frag(cur: ptr(ParseCursor), arena: ptr(Arena), ctx: ptr(ParseCtx)) -> RegionFrag
func parse_module(tape: TokenTape, arena: ptr(Arena), ctx: ptr(ParseCtx)) -> ParseOutput
```

`ParseCtx` holds issues, anchors, interner, known protocol type variants for
region protocol sugar, current value/continuation parse scopes, and splice slots.

---

## 10. Pratt Expression Parser

Pratt parsing maps well to Moonlift. Operator tables become functions generated
from the grammar:

```moonlift
func lbp(k: TokenKind) -> i32
    switch token_kind_tag(k) do
    case TOK_OR then return 10
    case TOK_AND then return 20
    case TOK_EQ then return 30
    case TOK_PLUS then return 70
    case TOK_STAR then return 80
    default then return 0
    end
end
```

Parser shape:

```moonlift
func parse_expr(cur: ptr(ParseCursor), arena: ptr(Arena), ctx: ptr(ParseCtx), rbp0: i32) -> Expr
    let t: Token = advance(cur)
    var left: Expr = nud(cur, arena, ctx, t)
    block loop(left0: Expr = left)
        let k: TokenKind = peek_kind(cur)
        if lbp(k) <= rbp0 then return left0 end
        let op: Token = advance(cur)
        jump loop(left0 = led(cur, arena, ctx, op, left0))
    end
end
```

`nud` handles literals, refs, prefix ops, `as(T, x)`, `view(...)`, `select`,
parentheses, `switch` expressions, control expressions, and `emit` expression
fragments. `led` handles binary ops, compare ops, logic ops, calls, indexing,
field access, load/store intrinsics, etc.

---

## 11. Statements / Types / Top Level

Recursive descent is clearer for non-expression grammar:

```moonlift
func parse_stmt(cur: ptr(ParseCursor), arena: ptr(Arena), ctx: ptr(ParseCtx)) -> Stmt
    let k: TokenKind = peek_kind(cur)
    switch token_kind_tag(k) do
    case TOK_LET then return parse_let(cur, arena, ctx)
    case TOK_VAR then return parse_var(cur, arena, ctx)
    case TOK_IF then return parse_if_stmt(cur, arena, ctx)
    case TOK_SWITCH then return parse_switch_stmt(cur, arena, ctx)
    case TOK_RETURN then return parse_return(cur, arena, ctx)
    case TOK_JUMP then return parse_jump(cur, arena, ctx)
    case TOK_BLOCK then return parse_control_stmt(cur, arena, ctx)
    default then return parse_expr_or_assignment_stmt(cur, arena, ctx)
    end
end
```

Types are also recursive descent: scalar names, `ptr(T)`, `view(T)`, function
pointer types, closure types, named/path types, and holes.

Top-level island parsers produce exactly the ASDL consumed downstream:

- `func` → `FuncLocal` / `FuncExport` / contracts
- `region` → `RegionFrag`
- `expr` → `ExprFrag`
- `struct` / `union` → `TypeDecl`
- `extern` → `ExternFunc`

---

## 12. Error Recovery

Every `expect` should produce an issue and return a safe placeholder token.
Parser functions should synchronize at strong boundaries:

- statement boundary: newline, semicolon, `end`, `else`, `elseif`, `case`, `default`
- declaration boundary: top-level island start keyword
- list boundary: comma, closing paren/bracket, `end`

Semantic placeholders should be explicit and loud:

- bad expression → `ExprRef(ValueRefName("<parse-error>"))` plus issue
- bad type → `TScalar(void)` plus issue
- bad statement → `StmtExpr(<parse-error>)` or empty expression statement

Do not silently drop source. Always emit a diagnostic and continue.

---

## 13. Anchors and Source Maps

AST nodes remain semantic. Source/editor information is separate:

- emit `AnchorSpan` for definitions/uses/keywords/types/fields/continuations
- store byte ranges from tokens
- build a `SourceLineIndex` for offset → line/utf16 conversion when needed
- diagnostics carry offsets and line/col immediately

This preserves the clean ASDL tree while still supporting LSP.

---

## 14. Initial Milestones

1. **Core schema:** add `TokenKind`, `Token`, `TokenTape`, `SourceBuffer`,
   `Island`, `SpliceSlot`, `ParseOutput`.
2. **Buffer parser harness:** `parse_buffer(ptr, len, uri)` returning issues.
3. **Lexer:** identifiers, keywords, ints, operators, strings, comments, eof.
4. **Type parser:** enough for struct/union/function signatures.
5. **Struct/union/extern parser:** easiest AST output, validates builders.
6. **Pratt expressions:** literals, refs, calls, unary/binary/compare/select.
7. **Statements:** let/var/set/if/switch/return/block/jump/yield/emit.
8. **Function parser:** produce `Module` for pure `.moon` files.
9. **Region/expr fragments and splices.**
10. **Document scanner:** `.mlua` island discovery and parse combination.

At milestone 8, MOM can parse pure Moonlift source to MoonTree without Lua. At
milestone 10, it can parse hosted islands and hand the same typed AST to the
rest of the native compiler pipeline.
