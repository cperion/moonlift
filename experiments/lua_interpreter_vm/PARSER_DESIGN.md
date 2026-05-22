# Moonlift Lua Source → Bytecode Parser/Compiler Design

Status: design for next implementation phase.  
Scope: a super-fast Moonlift-native Lua 5.5 frontend that consumes source bytes and produces VM `Proto` / decoded `Instr[]` products for `experiments/lua_interpreter_vm`.  
Primary rule: **no string-concat codegen, no stringly semantic state**. Lua may generate monomorphic typed regions, opcode tables, and keyword tries; Moonlift code manipulates typed products and continuations.

---

## 0. Purpose

Compile Lua source text bytes into a validated `Proto` tree executable by the VM:

```text
source bytes -> lexer -> Pratt/parser regions -> direct bytecode builder -> Proto tree -> validate_proto -> VM
```

The frontend follows `explicit_programming.md`:

- data that persists is a product;
- alternatives consumed immediately are continuations;
- parser states are blocks, not integer flags;
- C/Puc status returns become protocols;
- sealed functions only at allocation/API boundaries;
- repeated grammar/operator/opcode families are Lua-generated typed declarations, never runtime string codegen.

---

## 1. Non-negotiable rules

1. **No AST as required hot-path product.** The fastest baseline compiler parses and emits bytecode directly, like PUC Lua. A debug/inspection AST can be optional later, but the production path is parser + codegen state.
2. **Tokens are storage, token meaning is control.** `Token.kind` may be a compact `u16`; consumers use `token_is_name`, `token_is_binop`, `parse_statement` continuations, etc.
3. **No parser result codes.** Every parse/codegen operation exits through named continuations: `ok`, `syntax_error`, `semantic_error`, `oom`, `limit_error`.
4. **No hidden lookahead conventions.** Lexer state has `current` and `lookahead` products; consuming/peeking is explicit.
5. **Bytecode emission is typed.** Emission regions take `Op`/operand scalars and write `Instr` products. No packed instruction strings.
6. **Jumps are patch records, not magic integers.** Pending jumps and labels are explicit compiler products.
7. **Lua metaprogramming generates tables and families only.** Keyword trie, precedence table, statement dispatch, and opcode emitters can be Lua-generated monomorphic regions.
8. **Final output is decoded `Instr[]`.** The loader may also support packed Lua chunks later, but the VM contract remains `Instr` products with decoded `k`, `bx`, `sbx`.

---

## 2. Data tree additions

These products live alongside `src/products.lua`, likely in a new `src/parser_products.lua` until stable.

### 2.1 Source and diagnostics

```moonlift
struct SourceView
    bytes: ptr(u8)
    len: index
    source_name: ptr(String)
end

struct SourcePos
    offset: index
    line: i32
    col: i32
end

struct CompileError
    code: i32
    pos: SourcePos
    token: u16
end
```

Diagnostics are compact; human rendering is a sealed/API layer later.

### 2.2 Lexer products

```moonlift
struct Token
    kind: u16
    start: index
    len: index
    line: i32
    aux: u32      -- keyword id, short-string flag, numeric subtype, etc.
    bits: u64     -- integer bits, float bits, interned String ptr, or small payload
end

struct Lexer
    src: SourceView
    pos: index
    line: i32
    col: i32
    current: Token
    lookahead: Token
    has_lookahead: u8
end
```

`Token.bits` is storage only. Semantic consumers are regions:

```moonlift
region token_as_name(tok: Token; name: cont(s: ptr(String)), not_name: cont())
region token_as_int(tok: Token; integer: cont(n: i64), not_integer: cont())
region token_as_float(tok: Token; float: cont(n: f64), not_float: cont())
region token_is_keyword(tok: Token, kw: u16; yes: cont(), no: cont())
```

### 2.3 Compile arena and growable vectors

The parser needs fast append-only memory. Allocation policy is sealed behind arenas/vectors.

```moonlift
struct CompileArena
    base: ptr(u8)
    pos: index
    cap: index
    overflowed: u8
end

struct InstrVec
    data: ptr(Instr)
    len: index
    cap: index
end

struct ValueVec
    data: ptr(Value)
    len: index
    cap: index
end

struct ProtoPtrVec
    data: ptr(ptr(Proto))
    len: index
    cap: index
end

struct LocVarVec
    data: ptr(LocVar)
    len: index
    cap: index
end

struct UpValDescVec
    data: ptr(UpValDesc)
    len: index
    cap: index
end
```

Vectors have protocols:

```moonlift
region instr_push(v: ptr(InstrVec), inst: Instr; ok: cont(pc: index), oom: cont())
region value_intern_const(cs: ptr(ValueVec), v: Value; found: cont(k: u32), added: cont(k: u32), oom: cont())
```

### 2.4 Function/compiler state

```moonlift
struct LabelPatch
    pc: index
    next: index
end

struct LabelDesc
    name: ptr(String)
    pc: index
    line: i32
    nactvar: u16
end

struct LocalDesc
    name: ptr(String)
    startpc: index
    endpc: index
    reg: u16
    kind: u8       -- regular, const, tbc, vararg table
end

struct UpvalueRef
    name: ptr(String)
    instack: u8
    index: u16
end

struct FuncBuilder
    parent: ptr(FuncBuilder)
    code: InstrVec
    constants: ValueVec
    children: ProtoPtrVec
    locvars: LocVarVec
    upvals: UpValDescVec
    labels: ptr(LabelDesc)
    labels_len: index
    gotos: ptr(LabelDesc)
    gotos_len: index
    firstlocal: index
    nactvar: u16
    freereg: u16
    maxstack: u16
    pc: index
    lasttarget: index
    numparams: u8
    flag: u8       -- ProtoFlag bits
end

struct CompileUnit
    arena: ptr(CompileArena)
    lexer: Lexer
    root: ptr(FuncBuilder)
    current: ptr(FuncBuilder)
end
```

### 2.5 Expression descriptors

PUC `expdesc` is real compiler state; keep it, but as a product plus consumer protocols.

```moonlift
struct ExpDesc
    kind: u16       -- VNIL, VTRUE, VKINT, VLOCAL, VINDEXED, VCALL, VJMP, etc.
    info: u32
    aux: u32
    t: index        -- true jump list, or NO_JUMP
    f: index        -- false jump list, or NO_JUMP
    value: Value    -- constant payload when applicable
end
```

Consumers:

```moonlift
region exp_to_anyreg(cu: ptr(CompileUnit), e: ExpDesc; reg: cont(r: u16), error: cont(code: i32), oom: cont())
region exp_to_nextreg(cu: ptr(CompileUnit), e: ExpDesc; ok: cont(e: ExpDesc), error: cont(code: i32), oom: cont())
region exp_to_const(cu: ptr(CompileUnit), e: ExpDesc; constant: cont(k: u32), not_const: cont(), oom: cont())
region store_var(cu: ptr(CompileUnit), var: ExpDesc, val: ExpDesc; ok: cont(), semantic_error: cont(code: i32), oom: cont())
```

---

## 3. Control tree

### 3.1 Top-level compiler entry

```moonlift
region compile_lua_source(
    arena: ptr(CompileArena),
    bytes: ptr(u8),
    len: index,
    source_name: ptr(String);

    ok: cont(proto: ptr(Proto)),
    syntax_error: cont(err: CompileError),
    semantic_error: cont(err: CompileError),
    limit_error: cont(err: CompileError),
    oom: cont())
```

Flow:

```text
compile_lua_source
  -> init_compile_unit
  -> lex_next
  -> parse_main_func
  -> close_func_builder
  -> validate_proto
```

### 3.2 Lexer regions

```moonlift
region lex_next(cu: ptr(CompileUnit);
    token: cont(tok: Token),
    lexical_error: cont(err: CompileError),
    oom: cont())

region lex_peek(cu: ptr(CompileUnit);
    token: cont(tok: Token),
    lexical_error: cont(err: CompileError),
    oom: cont())

region lex_skip_space_and_comments(cu: ptr(CompileUnit);
    done: cont(),
    lexical_error: cont(err: CompileError))
```

Fast path lexer structure:

```text
lex_next
  block dispatch_byte(pos,line,col)
    ASCII one-byte tokens: direct token emit
    first char name/keyword: scan_name -> keyword trie -> intern
    digit or dot-digit: scan_number
    quote: scan_short_string
    '[' maybe long string/comment
    operators: 2/3 byte dispatch table
```

Keyword recognition is a Lua-generated nested byte switch/trie region. It returns a keyword token or name token, with no runtime hash-table lookup for reserved words.

### 3.3 Parser regions

Parsing is recursive-descent with Pratt expression parsing. Each grammar nonterminal is a region with explicit exits.

```moonlift
region parse_main_func(cu: ptr(CompileUnit);
    ok: cont(proto: ptr(Proto)),
    syntax_error: cont(err: CompileError),
    semantic_error: cont(err: CompileError),
    limit_error: cont(err: CompileError),
    oom: cont())

region parse_block(cu: ptr(CompileUnit), until_mask: u64;
    done: cont(),
    did_return: cont(),
    syntax_error: cont(err: CompileError),
    semantic_error: cont(err: CompileError),
    limit_error: cont(err: CompileError),
    oom: cont())

region parse_statement(cu: ptr(CompileUnit);
    next: cont(),
    returned: cont(),
    syntax_error: cont(err: CompileError),
    semantic_error: cont(err: CompileError),
    limit_error: cont(err: CompileError),
    oom: cont())
```

Statement dispatch is a region, not a return-code switch:

```moonlift
region classify_statement_start(tok: Token;
    if_stmt: cont(), while_stmt: cont(), repeat_stmt: cont(), for_stmt: cont(),
    local_stmt: cont(), function_stmt: cont(), global_stmt: cont(),
    return_stmt: cont(), break_stmt: cont(), goto_stmt: cont(),
    label_stmt: cont(), expr_stmt: cont(), empty_stmt: cont(),
    end_of_block: cont())
```

### 3.4 Expression parser

Use Pratt / precedence-climbing because it is fast and maps cleanly to Lua's expression grammar.

```moonlift
region parse_expr(cu: ptr(CompileUnit), limit: u8;
    expr: cont(e: ExpDesc),
    syntax_error: cont(err: CompileError),
    semantic_error: cont(err: CompileError),
    limit_error: cont(err: CompileError),
    oom: cont())
```

Lua-generated operator table:

```text
TokenKind -> BinOpInfo(left_pri, right_pri, opcode, metamethod_event, associativity)
TokenKind -> UnOpInfo(priority, opcode, metamethod_event)
```

Consumer protocols:

```moonlift
region token_as_binop(tok: Token;
    binop: cont(op: u16, left_pri: u8, right_pri: u8),
    not_binop: cont())

region token_as_unop(tok: Token;
    unop: cont(op: u16, pri: u8),
    not_unop: cont())
```

### 3.5 Bytecode builder regions

The code generator is not a separate string pass. Parser regions emit typed instructions into the active `FuncBuilder`.

```moonlift
region emit_ABC(cu: ptr(CompileUnit), op: u16, a: u16, b: u16, c: u16, k: u8;
    pc: cont(pc: index), limit_error: cont(err: CompileError), oom: cont())

region emit_ABx(cu: ptr(CompileUnit), op: u16, a: u16, bx: u32;
    pc: cont(pc: index), limit_error: cont(err: CompileError), oom: cont())

region emit_AsBx(cu: ptr(CompileUnit), op: u16, a: u16, sbx: i32;
    pc: cont(pc: index), limit_error: cont(err: CompileError), oom: cont())

region patch_jump(cu: ptr(CompileUnit), pc: index, target: index;
    ok: cont(), limit_error: cont(err: CompileError))
```

Optimization remains typed:

- `emit_loadnil_range` coalesces adjacent `LOADNIL` instructions.
- `emit_load_const` chooses `LOADI`, `LOADF`, `LOADK`, `LOADKX`.
- `emit_binop` emits fast-path op + following `MMBIN/MMBINI/MMBINK` as required by the VM README.
- `emit_return` chooses `RETURN0`, `RETURN1`, or `RETURN`.

---

## 4. Fast path architecture

### 4.1 Single-pass direct-to-bytecode baseline

The production compiler should mirror PUC's fast shape while making control explicit:

```text
lexer produces one token at a time
parser consumes token stream
expression descriptors carry partially-emitted code state
codegen patches jumps and registers in place
closing a function freezes builder vectors into Proto products
```

No source AST is required in the hot path. This avoids allocation volume and cache misses.

### 4.2 Memory behavior

All compile-time temporaries come from `CompileArena`. Products that become runtime-visible (`Proto`, `Instr[]`, constants, children, locvars, upvals, strings) are finalized into stable allocations through a sealed allocator boundary.

Arena protocol:

```moonlift
region arena_alloc(arena: ptr(CompileArena), size: index, align: index;
    ok: cont(p: ptr(u8)), oom: cont())
```

Vector protocol grows geometrically. If growth cannot happen, `oom` exits immediately; no partial silent result.

### 4.3 Source scanning performance

- ASCII byte-class table: `u8 -> class` generated by Lua as a static array or switch.
- Keyword trie: generated byte-switch, no hashing for reserved words.
- Operators: two/three-byte dispatch for `//`, `..`, `...`, `==`, `>=`, `<=`, `~=`, `<<`, `>>`, `::`.
- Line tracking is inline in whitespace/comment scan.
- Short strings scan with separate blocks for normal / escape / hex / decimal / unicode if Lua 5.5 needs it.
- Numerals use a liberal scan then typed conversion region; conversion failure is a lexical error.

---

## 5. Lua 5.5 alignment plan

Opcode emission must target the current 0–84 opcode table in `src/constants.lua` / README:

- globals compile as `_ENV` upvalue access via `GETTABUP`/`SETTABUP`;
- booleans use `LOADFALSE`, `LFALSESKIP`, `LOADTRUE`; no `LOADBOOL`;
- integer and float constants are split: `TAG_INTEGER` vs `TAG_NUM`;
- arithmetic fast path emits `OP_*` followed by `MMBIN/MMBINI/MMBINK` according to README;
- vararg functions emit `VARARGPREP` at function entry;
- to-be-closed locals emit `TBC` and returns carry `k` where needed;
- `LOADKX`, `NEWTABLE(k=1)`, `SETLIST(k=1)` are finalized with folded `EXTRAARG` before VM validation.

---

## 6. Implementation order

1. `parser_constants.lua`: token kinds, keyword ids, expression kinds, variable kinds, operator metadata.
2. `parser_products.lua`: products above.
3. `regions_lexer.lua`: byte scanner, keyword trie, number/string skeleton.
4. `regions_codegen.lua`: vectors, constants, emitters, jump patching, register allocator.
5. `regions_expr.lua`: ExpDesc consumers + Pratt expression parser.
6. `regions_parser.lua`: block/statement/function parser.
7. `compiler.lua`: `compile_lua_source` root region and module exports.
8. Tests: lexer golden tests, expression bytecode tests, statement bytecode tests, full source -> Proto -> VM execution tests.

---

## 7. First milestone subset without design compromise

Implement a narrow but final-shape slice:

```lua
return 1 + 2
local x = 41
return x + 1
```

This requires real final products/protocols:

- lexer for names, keywords, integers, `+`, `=`, `return`, `local`, EOF;
- `FuncBuilder`, `InstrVec`, `ValueVec`;
- expression parser for integer literals, local variables, `+`;
- codegen for `LOADI`, `MOVE`, `ADD + MMBIN`, `RETURN1`;
- `close_func_builder` producing a `Proto`.

No temporary AST, no fake string codegen, no ad-hoc status returns.

---

## 8. Grep-shaped verification

The implementation should make these useful and complete:

```bash
rg '^struct .*Lexer|^struct .*Func|^struct .*Exp' experiments/lua_interpreter_vm/src
rg '^region lex_' experiments/lua_interpreter_vm/src
rg '^region parse_' experiments/lua_interpreter_vm/src
rg '^region emit_' experiments/lua_interpreter_vm/src
rg '\bjump syntax_error|\bjump semantic_error|\bjump limit_error|\bjump oom' experiments/lua_interpreter_vm/src
rg '\bOP_LOADBOOL\b|GETGLOBAL|SETGLOBAL' experiments/lua_interpreter_vm/src   # must stay empty
```

The control graph is the documentation.
