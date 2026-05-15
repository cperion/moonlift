# MOM Bootstrap — Porting Guide

Porting the Moonlift compiler from Lua PVM phases to **pure Moonlift**.

There is no Lua in the compiler core at runtime. The pipeline starts at
source bytes and ends at executable native code: document scan, lexing,
parsing, AST construction, binding/opening, typecheck, lowering, validation,
vectorization, backend handoff.

Every compiler phase is a Moonlift `func` or `region`. Every compiler
dispatch is a Moonlift `switch`. Every compiler data choice is `select`.
Every compiler control choice is `if`/`jump`/`emit` inside a region.

Lua is the **staging layer for building MOM itself** — `moon.stmts [[ ]]` +
`@{...}` generates specialized Moonlift compiler code. The generated compiler
runs as native code with zero Lua dependencies.

---

## 0. The One Rule

```
moon.stmts [[ ]]  writes source-shaped Moonlift.
@{x}              injects one Lua-computed value.
@{xs...}          injects a Lua array of values.
The compiler core result is pure Moonlift. No Lua in the core runtime.
```

Lua computes *which* Moonlift to generate. Moonlift is *what* runs.

---

## 1. What We're Porting

The current compiler is ~80 Lua modules under `lua/moonlift/`. Today the
front half is a Lua scanner/parser that constructs MoonTree ASDL, and the
middle/back half is mostly PVM phases: dispatch tables from ASDL variant class
to analysis/lowering functions.

**All of it ports.** Not just the schema — source scanning, lexing, parsing,
AST construction, host/island document splitting, binding/opening, typecheck,
lowerings, validation, inspection, control analysis, vectorization, link plans.
Every module becomes Moonlift `func` and `region` declarations.

The schema files (`experiments/mom/schema/`) are the seed — ASDL types as
Moonlift struct/union declarations. The next missing layer is the parser:
`ptr(u8)+len` source bytes must become typed MoonTree AST values before the
existing phase pipeline can run.

The parser produces ASDL output (`Module`, `Func`, `Stmt`, `Expr`, `Type`,
`RegionFrag`, `ExprFrag`, parse issues, anchors). The lowerings then consume
that ASDL. The control analysis walks the AST and yields facts. Validation
switches on variant tags and yields diagnostics.

---

## 2. The Three Tools

### 2.1 `moon.stmts [[ ]]` — Source-Shaped Moonlift

When the code you want is *source-shaped*, write it in `[[ ]]`:

```lua
local body = moon.stmts [[
    let c: i32 = as(i32, p[i])
    if c >= 48 then
        if c <= 57 then
            jump ok(next = i + 1, value = c - 48)
        end
    end
    jump err(pos = i, code = 2)
]]
```

This is the **primary tool**. Most lowering logic is source-shaped.
`[[ ]]` gives you the full Moonlift syntax — `if`, `switch`, `select`,
`as()`, `emit`, regions, everything.

### 2.2 `@{x}` and `@{xs...}` — Staging Holes

Lua computes which Moonlift to generate. `@{...}` injects the result:

```lua
local T = moon.i32
local zero = moon.int(0)

local body = moon.stmts [[
    let x: @{T} = @{zero}
    return x + 1
]]
```

Every syntactic position accepts splices — types, expressions, names,
parameter lists, field lists, statement lists, continuation lists,
switch arms, fragment positions:

```lua
local params = { moon.param("a", moon.i32), moon.param("b", moon.i32) }
local conts  = { moon.cont_decl("ok", { moon.param("v", moon.i32) }) }
```

```moonlift
region add_and_exit(@{params...}; @{conts...})
entry start()
    jump ok(v = a + b)
end
end
```

**`moon.stmts [[ ]]` gives you the shape. `@{...}` gives you the holes.
The result is pure Moonlift.**

### 2.3 Standard Moonlift — Everything Else

Inside `[[ ]]` is normal Moonlift. All the control primitives are available:

- **`select(c, a, b)`** — dataflow choice, no branching
- **`if` / `switch`** — control-flow branching
- **`region` / `emit` / `jump` / `yield`** — typed control composition
- **`as(T, v)`** — the only conversion form
- **`block loop(i = 0)` / `jump loop(i = i + 1)`** — loops

These are the *runtime* primitives of the generated compiler. The compiler
itself uses them to scan bytes, parse tokens, walk ASTs, dispatch on variant
tags, thread values through control flow, and produce ASDL output. No Lua
needed in the compiler core at runtime — just Moonlift.

---

## 3. Critical Distinction: Compiler Control vs Target-Program Control

There are three different times at which a choice can happen:

| Layer | Mechanism | Chooses |
|---|---|---|
| Staging | Lua `if` while building MOM | Which compiler code exists |
| MOM compiler runtime | Moonlift `if`/`switch`/`select` | How the native compiler parses/analyzes/lowers |
| Program being compiled | `Back.Cmd` data (`CmdBrIf`, `CmdSelect`, `CmdJump`) | What the user's program does |

This distinction is non-negotiable.

If a value is a compiler boolean, use Moonlift control/dataflow:

```moonlift
let is_float: bool = scalar == BackF32 or scalar == BackF64
let op: BackCompareOp = select(is_float, BackFCmpEq, BackICmpEq)
```

If a value is a target-program value id, such as `BackValId`, the compiler
cannot branch on it. The compiler must emit IR data:

```moonlift
-- cond is a BackValId. This constructs target-program dataflow.
let cmd: Cmd = CmdSelect(dst, BackShapeScalar(BackBool), cond, then_v, else_v)
```

And target-program control flow is also emitted as data:

```moonlift
append_cmd(out, CmdBrIf(cond, then_block, else_block))
append_cmd(out, CmdSwitchToBlock(then_block))
-- lower then body...
append_cmd(out, CmdJump(join_block, then_args))
```

Moonlift block parameters are still extremely useful in MOM: they thread the
compiler's own state (`cursor`, `arena`, `env`, `cmd_builder`, diagnostics,
next ids). They do **not** replace target-program blocks unless MOM is staging
a known Moonlift fragment as source-shaped code. For general user source,
target control is `Back.Cmd` output.

---

## 4. Parser Layer: Source Bytes → Token Tape → MoonTree AST

The original guide skipped the front of the pipeline. MOM starts before ASDL
lowering: it receives source text and must produce typed AST values. See
[PARSER_DESIGN.md](PARSER_DESIGN.md) for the concrete parser/source-to-AST plan.

Moonlift is outrageously well suited for this layer:

- byte loops compile to tight native code over `ptr(u8)` + `index` length
- token kinds are small integer/union tags, not dynamic Lua strings
- scanner state is explicit block parameters (`i`, `line`, `col`, mode)
- Pratt expression parsing is a tiny dispatch loop over token tags
- recursive-descent statement/type parsing becomes ordinary typed functions
- arena-backed builders freeze variable-length lists into `view(T)`
- diagnostics and anchors are typed output, not side tables

### 4.1 Parse Pipeline

The native parser should be split into explicit tapes and builders:

```text
SourceBuffer(data: ptr(u8), len: index, uri)
  -> scan_document       -- .mlua segmentation: LuaOpaque / HostedIsland
  -> lex_island          -- byte stream -> TokenTape
  -> parse_module        -- TokenTape + cursor -> MoonTree.Module
  -> parse fragments     -- RegionFrag / ExprFrag / struct / union / extern
  -> anchors/issues      -- Source ranges, names, diagnostics
```

For pure `.moon` input, `scan_document` can produce one hosted module island.
For `.mlua`, MOM should scan Lua-opaque regions only enough to find Moonlift
islands. If the long-term goal is **no Lua runtime for user programs either**,
then `.mlua` staging must be handled before the native compiler core or by a
separate staged evaluator. MOM phase one should make the native Moonlift
island parser independent of Lua.

Moonlift can call libc through `extern`, so OS-level integration is not a
blocker: adapters can use `open`/`read`/`close`, `malloc`/`realloc`/`free`,
optional `mmap`, and `write` for diagnostics. Keep that as a thin source
acquisition/output layer; the parser core should remain `ptr(u8)+len` → typed
parse result.

### 4.2 Token Tape Design

Do not parse from strings repeatedly. Lex once into a compact tape:

```moonlift
union TokenKind
    | TokEof | TokName | TokInt | TokFloat | TokString | TokNewline
    | TokHole | TokInvalid
    | TokLParen | TokRParen | TokComma | TokColon | TokArrow
    | TokFunc | TokStruct | TokUnion | TokIf | TokThen | TokElse | TokEnd
    | TokSwitch | TokCase | TokDefault | TokBlock | TokJump | TokYield
    -- ... all keywords/operators
end

struct Token
    kind: TokenKind
    start: index
    stop: index
    line: i32
    col: i32
    text_id: i32      -- interned slice or -1
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

The current Lua parser uses parallel arrays (`kind`, `text`, `start`, `stop`,
`line`, `col`). MOM can use either SoA for maximum scanner speed or `view(Token)`
for simplicity. The important part is that all token spans are retained so AST
nodes, anchors, and errors can point back to source without string side tables.

### 4.3 Lexer as Jump-First State Machine

The lexer is a perfect Moonlift region: hot byte classification, explicit
state, no allocation except appending tokens/issues.

```moonlift
region lex(data: ptr(u8), n: index, out: ptr(TokenBuilder), issues: ptr(IssueBuilder);
           done: cont(tape: TokenTape))
entry loop(i: index = 0, line: i32 = 1, col: i32 = 1)
    if i >= n then
        emit append_token(out, TokEof, i, i, line, col)
        jump done(tape = freeze_tokens(out))
    end

    let c: u8 = data[i]
    if c == 32 or c == 9 or c == 13 then
        jump loop(i = i + 1, line = line, col = col + 1)
    end
    if c == 10 then
        emit append_token(out, TokNewline, i, i, line, col)
        jump loop(i = i + 1, line = line + 1, col = 1)
    end
    if is_alpha(c) then emit scan_ident(data, n, i, line, col; done = loop) end
    if is_digit(c) then emit scan_number(data, n, i, line, col; done = loop) end
    emit scan_operator_or_issue(data, n, i, line, col, out, issues; done = loop)
end
end
```

Each scanner helper is another region with a typed continuation. This is much
faster and clearer than callback-driven parser combinators: every transition is
a `jump`, every emitted token is typed, and the hot path is plain native code.

### 4.4 Parser to AST Gap

The gap is not just "recognize grammar". The parser must manufacture the exact
ASDL values the rest of the compiler expects.

Recommended design:

1. **Token cursor is mutable compiler state.** Parser functions take
   `ptr(ParseCursor)` plus `ptr(ParseArena)`/builders. Advancing is explicit.
2. **Parse direct to MoonTree for the compiler path.** `parse_expr` returns
   `Expr`, `parse_stmt` returns `Stmt`, `parse_type` returns `Type`. This is
   the fastest route to typecheck/lowering.
3. **Keep spans outside semantic nodes.** Emit `AnchorSpan`/diagnostics keyed by
   token offsets and generated ids. Do not pollute semantic AST variants with
   editor-only trivia.
4. **Use an optional CST only for editor/recovery needs.** If LSP needs exact
   malformed-tree recovery, add a shallow concrete syntax tree later. The core
   compiler should not wait for it.
5. **Intern names and slices once.** `Name`, `Path`, ids, and literal raw text
   should reference interned source slices or arena strings. No hidden Lua
   string tables at runtime.
6. **Represent splices explicitly.** `@{...}` becomes a `TokHole` and then a
   typed open slot (`NameRefSlot`, `ExprOpenSlot`, `TypeOpenSlot`, spread-list
   sentinel). The parser records the slot; staging resolves it before native
   compilation of the final module.
7. **Lists are builders, then views.** Params, fields, statements, switch arms,
   blocks, variants, contracts, issues, anchors all append to typed builders and
   freeze to `view(T)`.

The first schema addition MOM needs is therefore a real `MoonParse` model:
`SourceBuffer`, `TokenKind`, `Token`, `TokenTape`, `Island`, `ParseCursor`,
`ParseIssue`, `SpliceSlot`, and builder/freeze result types. The current
`ParseIssue`-only model is enough for validation experiments but not enough for
native parsing.

### 4.5 Pratt Expressions, Recursive Statements

Expression parsing should stay Pratt-style because it maps exactly to the
current language:

```moonlift
func parse_expr(cur: ptr(ParseCursor), arena: ptr(ParseArena), rbp: i32) -> Expr
    let t: Token = advance(cur)
    var left: Expr = nud(cur, arena, t)
    block loop(left0: Expr = left)
        let k: TokenKind = peek(cur).kind
        if lbp(k) <= rbp then return left0 end
        let op: Token = advance(cur)
        let right: Expr = parse_expr(cur, arena, lbp(k))
        jump loop(left0 = led(arena, op, left0, right))
    end
end
```

Statements/types/top-level declarations are recursive descent with `switch` on
`peek(cur).kind`. This gives the whole front end the same property as the rest
of MOM: grep-shaped, typed, jump-first, native.

---

## 5. Every Phase Becomes Moonlift

### 5.1 Lookup Tables → `func` with `switch`

**Lua (current):** PVM phase dispatch table
```lua
unary_op = pvm.phase("name", {
    [C.UnaryNeg] = function(_, scalar)
        if scalar == Back.BackF32 or scalar == Back.BackF64 then
            return pvm.once(Back.BackUnaryFneg)
        end
        return pvm.once(Back.BackUnaryIneg)
    end,
    [C.UnaryNot] = function() return pvm.once(Back.BackUnaryBoolNot) end,
    [C.UnaryBitNot] = function() return pvm.once(Back.BackUnaryBnot) end,
})
```

**Moonlift (ported):** A `func` with `switch` on the variant tag.

```moonlift
func lower_unary(op: i32, scalar: i32) -> i32
    let is_float: bool = scalar == BackF32 or scalar == BackF64
    switch op do
    case 0 then  -- UnaryNeg
        select(is_float, BackUnaryFneg, BackUnaryIneg)
    case 1 then  -- UnaryNot
        BackUnaryBoolNot
    case 2 then  -- UnaryBitNot
        BackUnaryBnot
    default then
        0
    end
end
```

**No Lua dispatch. No PVM phase.** A pure Moonlift function that switches
on the variant tag and uses `select` for the scalar-dependent choice. The
`scalar` field is an integer tag — we compare it to `BackF32`/`BackF64`
constants, compute `is_float` once, then `select` picks the right variant
without branching.

When the factory needs to generate specialized variants (monomorphization),
Lua stages the specialization:

```lua
local function make_typed_unary_lower(scalar)
    local scalar_name = scalar_name_for(scalar)
    local is_float = (scalar == Back.BackF32 or scalar == Back.BackF64)
    return func lower_unary_@{scalar_name}(op: i32) -> i32
        switch op do
        case 0 then  -- UnaryNeg
            @{is_float and "BackUnaryFneg" or "BackUnaryIneg"}
        case 1 then  -- UnaryNot
            BackUnaryBoolNot
        case 2 then  -- UnaryBitNot
            BackUnaryBnot
        default then
            0
        end
    end
end
```

Now the float/int decision is **staged out** — it happened at generation
time. The generated function doesn't even contain the comparison.

### 5.2 Compare Dispatch → `func` with `switch` + `select`

**Lua (current):**
```lua
compare_op = pvm.phase("name", {
    [C.CmpEq] = function(_, scalar)
        if scalar == Back.BackF32 or scalar == Back.BackF64 then
            return pvm.once(Back.BackFCmpEq)
        end
        return pvm.once(Back.BackIcmpEq)
    end,
    -- ... 6 variants, each with float/int split
})
```

**Moonlift (ported):**
```moonlift
func lower_compare(op: i32, scalar: i32) -> i32
    let is_float: bool = scalar == BackF32 or scalar == BackF64
    switch op do
    case 0 then select(is_float, BackFCmpEq,  BackIcmpEq)
    case 1 then select(is_float, BackFCmpNe,  BackIcmpNe)
    case 2 then select(is_float, BackFCmpLt,  BackSIcmpLt)
    case 3 then select(is_float, BackFCmpLe,  BackSIcmpLe)
    case 4 then select(is_float, BackFCmpGt,  BackSIcmpGt)
    case 5 then select(is_float, BackFCmpGe,  BackSIcmpGe)
    default then 0
    end
end
```

`is_float` is computed once, then `select` picks the right variant — no
branching, no PVM phase, pure dataflow. This compiles to a single
comparison + conditional move chain.

### 5.3 Binary Lowering → `func` with `switch` + compiler `if`

**Lua (current):** 12 entries, each checking float/int and producing
different `Cmd` variants.

**Moonlift (ported):**
```moonlift
func lower_binary(op: i32, scalar: i32, dst: BackValId,
                  lhs: BackValId, rhs: BackValId,
                  semantics: BackIntSemantics) -> Cmd
    let is_float: bool = scalar == BackF32 or scalar == BackF64
    switch op do
    case 0 then  -- Add
        if is_float then
            return CmdFloatBinary(dst, BackFloatAdd, scalar, BackFloatStrict, lhs, rhs)
        end
        return CmdIntBinary(dst, BackIntAdd, scalar, semantics, lhs, rhs)
    case 1 then  -- Sub
        if is_float then
            return CmdFloatBinary(dst, BackFloatSub, scalar, BackFloatStrict, lhs, rhs)
        end
        return CmdIntBinary(dst, BackIntSub, scalar, semantics, lhs, rhs)
    -- ... etc for Mul, Div, Rem, BitAnd, BitOr, BitXor, Shl, LShr, AShr
    default then
        return CmdTrap
    end
end
```

The float/int decision is compiler control over compiler data (`scalar`), not
target-program control. If union-valued `select` becomes supported everywhere,
this can be written as dataflow; until then, compiler `if` is clearer and safe.

### 5.4 Logic Lowering → Emit `CmdSelect`

**Lua (current):** Manually constructs `CmdSelect` for `and`/`or`.

**Moonlift (ported):** The compiler emits target-program `CmdSelect` data:
```moonlift
func lower_logic(op: i32, lhs: BackValId, rhs: BackValId,
                 false_val: BackValId, true_val: BackValId,
                 dst: BackValId) -> Cmd
    switch op do
    case 0 then return CmdSelect(dst, BackShapeScalar(BackBool), lhs, rhs, false_val)
    case 1 then return CmdSelect(dst, BackShapeScalar(BackBool), lhs, true_val, rhs)
    default then return CmdTrap
    end
end
```

When writing MOM's own compiler code, `a and b` can become a Moonlift
`select(a, b, false)` if `a` and `b` are compiler booleans. When lowering a
user program, `lhs` and `rhs` are `BackValId`s, so the compiler constructs a
`CmdSelect`.

### 5.5 ExprIf → Emit `CmdSelect` (The Big Unlock)

**Lua (current):**
```lua
[Tr.ExprIf] = function(_, env)
    return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "if expression lowering deferred"))
end,
```

**Deferred** because building blocks + phis for a ternary is ~90 lines.

**Moonlift (ported):**
```moonlift
append_cmd(out, CmdSelect(dst, BackShapeScalar(result_scalar), cond, then_val, else_val))
```

One target command for the scalar/dataflow case. The entire class of
"scalar if-expression with already-lowered branch values" lowerings that the
Lua code punted on becomes trivial. If either branch contains statements,
side effects, or control exits, lower it as target-program control blocks
(`CmdBrIf`, arm blocks, join block, block params).

---

## 6. Control Phases Become Regions

The real power: phases that need to walk structures, accumulate state,
and make control-flow decisions become Moonlift **regions**.

### 6.1 If-Statement Lowering → Region That Emits Target Blocks

**Lua (current):** ~90 lines manually creating blocks, sealing, emitting
`CmdBrIf`, `CmdAppendBlockParam` for phi values, patching jump args.

**Moonlift (ported):** a region threads the compiler's lowering state while it
emits the target-program block commands. `cond_val` is a `BackValId`; do not
branch on it in the compiler.

```moonlift
region lower_if_stmt(cond_val: BackValId,
                     then_stmts: view(Stmt), else_stmts: view(Stmt),
                     st: LowerState;
                     done: cont(st: LowerState))
entry start()
    let then_block: BackBlockId = fresh_block(st, "if.then")
    let else_block: BackBlockId = fresh_block(st, "if.else")
    let join_block: BackBlockId = fresh_block(st, "if.join")

    emit cmd(st, CmdCreateBlock(then_block); done = s1)
end
block s1(st1: LowerState)
    emit cmd(st1, CmdCreateBlock(else_block); done = s2)
end
block s2(st2: LowerState)
    emit cmd(st2, CmdCreateBlock(join_block); done = s3)
end
block s3(st3: LowerState)
    emit cmd(st3, CmdBrIf(cond_val, then_block, else_block); done = lower_then)
end
block lower_then(st4: LowerState)
    emit cmd(st4, CmdSwitchToBlock(then_block); done = then_body)
end
block then_body(st5: LowerState)
    emit lower_stmt_list(then_stmts, st5; done = then_done)
end
block then_done(st6: LowerState)
    emit cmd(st6, CmdJump(join_block, current_phi_args(st6)); done = lower_else)
end
block lower_else(st7: LowerState)
    emit cmd(st7, CmdSwitchToBlock(else_block); done = else_body)
end
block else_body(st8: LowerState)
    emit lower_stmt_list(else_stmts, st8; done = else_done)
end
block else_done(st9: LowerState)
    emit cmd(st9, CmdJump(join_block, current_phi_args(st9)); done = seal_join)
end
block seal_join(st10: LowerState)
    emit cmd(st10, CmdSwitchToBlock(join_block); done = done)
end
end
```

The *compiler* region block params (`st1`, `st2`, ...) replace Lua's manual env
threading. The *target program* phi params are still explicit `Back.Cmd` data:
`CmdAppendBlockParam` plus `CmdJump(... args ...)`, because those blocks belong
to the program being compiled.

### 6.2 Switch-Statement Lowering → Region That Emits `CmdSwitchInt`

**Lua (current):** ~130 lines.

**Moonlift (ported):** a compiler region loops over case metadata to build
`BackSwitchCase` data, emits `CmdSwitchInt`, then lowers each arm into its
own target block.

```moonlift
region lower_switch_stmt(value: BackValId, arms: view(SwitchArm),
                         default_body: view(Stmt), st: LowerState;
                         done: cont(st: LowerState))
entry start()
    let dispatch_block: BackBlockId = current_block(st)
    let default_block: BackBlockId = fresh_block(st, "switch.default")
    let join_block: BackBlockId = fresh_block(st, "switch.join")
    emit build_switch_cases(arms, st; done = emit_switch)
end
block emit_switch(st1: LowerState, cases: view(BackSwitchCase))
    emit cmd(st1, CmdSwitchInt(value, cases, default_block); done = lower_arms)
end
block lower_arms(st2: LowerState)
    emit lower_switch_arms(arms, join_block, st2; done = lower_default)
end
block lower_default(st3: LowerState)
    emit cmd(st3, CmdSwitchToBlock(default_block); done = default_body_block)
end
block default_body_block(st4: LowerState)
    emit lower_stmt_list(default_body, st4; done = default_done)
end
block default_done(st5: LowerState)
    emit cmd(st5, CmdJump(join_block, current_phi_args(st5)); done = finish)
end
block finish(st6: LowerState)
    emit cmd(st6, CmdSwitchToBlock(join_block); done = done)
end
end
```

Use Moonlift `switch` when the compiler is dispatching on a known tag (for
example `stmt_tag(stmt)`). Use `CmdSwitchInt` when the target program must
switch on a `BackValId` at runtime.

### 6.3 Validation → Region that Switches on Cmd Tag

**Lua (current):** `back_validate.lua` walks the Cmd array, checks
invariants per variant, accumulates issues.

**Moonlift (ported):** A region that loops over the command tape and
switches on each command's variant tag:

```moonlift
region validate(cmds: view(Cmd);
    done: cont(issues: view(BackValidationIssue)))
entry loop(i: index = 0, issues: view(BackValidationIssue) = empty)
    if i >= len(cmds) then jump done(issues = issues) end
    let cmd: Cmd = cmds[i]
    switch cmd_tag(cmd) do
    case 0 then   -- CmdTargetModel
        -- validate target model invariants
        jump loop(i = i + 1, issues = append(issues, check_target(cmd)))
    case 1 then   -- CmdCreateSig
        jump loop(i = i + 1, issues = append(issues, check_sig(cmd)))
    -- ... all 60+ variants
    default then
        jump loop(i = i + 1, issues = issues)
    end
end
end
```

Every command variant gets its own case. The validation logic for each
variant is a Moonlift function that reads the Cmd struct fields and
produces `BackValidationIssue` values.

### 6.4 Control Fact Extraction → Region that Walks AST

```moonlift
region extract_control_facts(stmts: view(Stmt), region_id: ptr(u8);
    done: cont(facts: view(ControlFact)))
entry loop(i: index = 0, facts: view(ControlFact) = empty)
    if i >= len(stmts) then jump done(facts = facts) end
    let stmt: Stmt = stmts[i]
    switch stmt_tag(stmt) do
    case 8 then   -- StmtIf
        -- extract conditional branch facts
        jump loop(i = i + 1, facts = append(facts, if_facts(stmt, region_id)))
    case 9 then   -- StmtSwitch
        jump loop(i = i + 1, facts = append(facts, switch_facts(stmt, region_id)))
    case 10 then  -- StmtJump
        -- record jump edge fact
        jump loop(i = i + 1, facts = append(facts, jump_fact(stmt, region_id)))
    -- ... etc
    default then
        jump loop(i = i + 1, facts = facts)
    end
end
end
```

This IS the `tree_control_facts.lua` phase — but it's a Moonlift region
that yields typed facts instead of a Lua function that appends to an array.

---

## 7. The `select` Doctrine

`select` is the **boundary** between data choice and control choice, but keep
the layer straight.

| Situation | MOM compiler primitive | Target-program output |
|---|---|---|
| Compiler chooses between two compiler scalar values | `select(c, a, b)` | native `select`/cmov in the compiler |
| Compiler chooses between two compiler actions | `if`/`switch` + `jump` | native branch in the compiler |
| User program chooses between two runtime values | construct `CmdSelect(...)` | Cranelift `select`/cmov in generated code |
| User program chooses between two runtime actions | construct `CmdBrIf`/blocks/jumps | target-program branch |

So there are two spellings depending on the layer:

```moonlift
-- compiler dataflow: c/a/b are MOM compiler values
let chosen: i32 = select(c, a, b)

-- target-program dataflow: cond/a/b are BackValId values
append_cmd(out, CmdSelect(dst, shape, cond, a, b))
```

**The four target-program patterns that become `CmdSelect`:**

| Source pattern | MOM output | Why |
|---|---|---|
| ExprSelect | `CmdSelect(dst, shape, cond, a, b)` | Choosing a runtime value |
| ExprLogic | `CmdSelect(dst, bool_shape, a, b, false)` / `CmdSelect(..., a, true, b)` | Choosing a runtime bool value |
| Bool materialization | `CmdSelect(dst, int_shape, bool_val, one, zero)` | Choosing runtime integer 0/1 |
| **ExprIf (scalar)** | `CmdSelect(dst, shape, cond, then_val, else_val)` | Choosing a scalar value |

The last one is the unlock. The current lowerer punts on scalar `ExprIf`
because it treated ternary value choice like block construction. MOM should
lower the pure scalar case directly to `CmdSelect`; only effectful/control arms
need `CmdBrIf` + join blocks.

---

## 8. Generation-Time vs Runtime

This distinction exists in the current Lua code too, but Lua has one
mechanism (`if`) for multiple layers. MOM makes it explicit:

| When the choice happens | Mechanism | Example |
|---|---|---|
| **MOM generation time** | Lua `if` + `moon.stmts [[ ]]` | "Generate a specialized parser/lowerer for this schema." |
| **Compiler runtime, data choice** | Moonlift `select` | "Choose a compiler value while parsing/lowering." |
| **Compiler runtime, control choice** | Moonlift `if`/`switch`/`jump` | "Which AST variant/token/cmd tag is this?" |
| **Target-program runtime, data choice** | emit `CmdSelect` | "The user program chooses between runtime values." |
| **Target-program runtime, control choice** | emit `CmdBrIf`/`CmdSwitchInt`/`CmdJump` | "The user program branches." |

```lua
-- GENERATION TIME: which specialized function to emit?
local is_float = (scalar == Back.BackF32 or scalar == Back.BackF64)

if is_float then
    return func lower_add_f32(...) -- float-specific code
        ...
    end
else
    return func lower_add_i32(...) -- int-specific code
        ...
    end
end
```

```moonlift
-- COMPILER RUNTIME: which compiler value is produced?
let result: i32 = select(cond, a, b)
```

Lua `if` chooses **which compiler code exists**. Moonlift `select` chooses
**which value the compiler produces while it runs**. Moonlift `if` chooses
**which compiler path runs**. `CmdSelect`/`CmdBrIf` describe choices that the
compiled user program will make later.

---

## 9. Phases as Functions and Regions

### 9.1 PVM Phase → Moonlift `func`

A PVM phase that maps input variant to output variant:

```lua
-- Lua PVM phase (current)
my_phase = pvm.phase("name", {
    [VariantA] = function(self) return pvm.once(Result1) end,
    [VariantB] = function(self) return pvm.once(Result2) end,
})
```

```moonlift
-- Moonlift function (ported)
func my_phase(tag: i32) -> i32
    switch tag do
    case 0 then Result1
    case 1 then Result2
    default then 0
    end
end
```

### 9.2 PVM Phase with Accumulation → Moonlift `region`

A PVM phase that walks a structure and accumulates results:

```lua
-- Lua PVM phase (current) — accumulates into array
my_walker = pvm.phase("name", {
    [NodeA] = function(self, env)
        local results = {}
        -- ... accumulate
        return pvm.once(results)
    end,
})
```

```moonlift
-- Moonlift region (ported) — accumulates through block params
region my_walker(nodes: view(Node);
    done: cont(results: view(Result)))
entry loop(i: index = 0, acc: view(Result) = empty)
    if i >= len(nodes) then jump done(results = acc) end
    let node: Node = nodes[i]
    switch node_tag(node) do
    case 0 then
        jump loop(i = i + 1, acc = append(acc, process_a(node)))
    case 1 then
        jump loop(i = i + 1, acc = append(acc, process_b(node)))
    default then
        jump loop(i = i + 1, acc = acc)
    end
end
end
```

The accumulator is a block parameter — the region's own control flow
handles the threading. No manual env management. No `append_all`.

### 9.3 Caching

PVM's `args_cache = "last"` and memoization are staging-level optimizations.
They don't need to be ported — they're replaced by:

- **Monomorphization** — Lua generates specialized variants at staging time
  (e.g., one `func` per scalar type), eliminating the need for runtime caching
- **Function calls** — Moonlift `func` calls are cheap; the Cranelift backend
  can inline them
- **Region `emit`** — zero-cost CFG splicing, no call overhead

If a phase truly needs memoization (e.g., deduplication of `BackSigId`
creation), it's a Moonlift `func` that checks a hash table through FFI.

---

## 10. Porting Order

### Phase 0: Schema ✅ (done)

`experiments/mom/schema/` — all ASDL types as Moonlift struct/union.

### Phase 1: Native Parser Layer

Source bytes → token tape → MoonTree AST.

- `scan_document(src) -> DocumentParts` for `.mlua`/island segmentation
- `lex_island(source, range) -> TokenTape`
- `parse_type`, `parse_expr`, `parse_stmt`, `parse_func`, `parse_region_frag`
- `parse_module(source) -> Module + ParseIssue + AnchorSet`
- token/splice/name interning and arena-backed list builders

This is the missing layer. Build it before porting lowerings so every later
phase consumes real native ASDL values.

### Phase 2: Pure Dispatch Functions

Variant → variant mappings. These become `func` with `switch`:

- `lower_unary(op, scalar) -> BackUnaryOp`
- `lower_compare(op, scalar) -> BackCompareOp`
- `lower_cast(op) -> BackCastOp`
- `lower_atomic_ordering(ordering) -> BackAtomicOrdering`
- `lower_atomic_rmw(op) -> BackAtomicRmwOp`
- `scalar_to_back(scalar_tag) -> BackScalar`
- `type_to_back_scalar(type_tag) -> BackScalar`

These are the simplest ports — pure `switch`, no state, no accumulation.

### Phase 3: Command-Producing Functions

Variant → Cmd construction. These become `func` with `switch` and compiler
`if`/`select` over compiler data:

- `lower_binary(op, scalar, dst, lhs, rhs, sem) -> Cmd`
- `lower_unary_cmd(op, scalar, dst, value) -> Cmd`
- `lower_compare_cmd(op, scalar, dst, lhs, rhs) -> Cmd`
- `lower_cast_cmd(op, scalar, dst, value) -> Cmd`

Still pure functions, but they construct `Back.Cmd` union values. If the
choice is over scalar enum values, use `select`; if the result is an aggregate
union command, compiler `if` is the safe spelling.

### Phase 4: Expression Lowering Regions

These walk expression ASTs and produce command sequences. They become
`region` declarations that dispatch on expression variant and accumulate
`Cmd` values:

- `lower_expr(expr, env; done: cont(cmds, value, env))`
- `lower_lit`, `lower_ref`, `lower_binary_expr`, `lower_compare_expr`
- `lower_select_expr` — emit `CmdSelect(cond, a, b)`
- `lower_logic_expr` — emit `CmdSelect(a, b, false)` / `CmdSelect(a, true, b)`
- `lower_if_expr` — emit `CmdSelect(cond, then, else)` for scalar (THE UNLOCK)
- `lower_switch_expr` — emit `CmdSwitchInt` + target join block

### Phase 5: Statement Lowering Regions

These walk statement ASTs and produce command sequences with control flow:

- `lower_if_stmt` — compiler region that emits `CmdBrIf` + target blocks/phis
- `lower_switch_stmt` — compiler region that emits `CmdSwitchInt` + target blocks/phis
- `lower_let`, `lower_var`, `lower_set` — struct field access
- `lower_return`, `lower_jump`, `lower_yield` — control exits

### Phase 6: Control Analysis Regions

- `extract_control_facts(stmts; done)` — walk AST, yield `ControlFact`
- `extract_contract_facts(fn; done)` — walk params, yield `ContractFact`
- `validate_control(facts; done)` — check facts, yield `ControlReject`

### Phase 7: Validation and Inspection Regions

- `validate_back(cmds; done)` — walk Cmd tape, yield `BackValidationIssue`
- `inspect_back(cmds; done)` — walk Cmd tape, yield `BackInspectionReport`

### Phase 8: Vectorization Pipeline Regions

- `extract_vec_loop_facts(region; done)` — counted-loop facts
- `decide_vectorization(facts; done)` — VecLoopDecision
- `plan_kernel(decision; done)` — VecKernelPlan
- `lower_kernel(plan; done)` — VecCmd sequence

### Phase 9: Link/JIT/Object Execution Driver

The Cranelift backend stays Rust, but the compiler driver around it ports:

- build `BackProgram` from lowered modules
- validate/inspect before execution
- choose target model and link plan
- call backend FFI for JIT/object/shared emission
- expose native entry points and diagnostics

This completes string → AST → Back.Cmd → native execution.

---

## 11. What NOT to Port

### 11.1 PVM Framework Mechanics

`pvm.phase`, `pvm.once`, `pvm.empty`, `args_cache` — these are the
*dispatch and caching mechanism*. They're replaced by:
- `func` + `switch` for dispatch
- Monomorphization via Lua staging for caching
- Region `emit` for zero-cost composition

### 11.2 Lua Env Threading Mechanics

Do not port Lua table-based env threading as-is. MOM should use typed
`LowerState`, `ParseCursor`, builders, and region block params to thread the
compiler's state. However, the compiler still has to allocate target
`BackValId`/`BackBlockId` values when producing `Back.Cmd` output.

### 11.3 Confusing Compiler Blocks with Target Blocks

Do not use MOM's own `block`/`jump` as if they were the user program's blocks.
MOM blocks control the native compiler. User-program blocks are emitted as
`CmdCreateBlock`, `CmdSealBlock`, `CmdSwitchToBlock`, `CmdJump`, `CmdBrIf`,
`CmdAppendBlockParam`, etc. Those commands remain part of the output IR.

### 11.4 JIT Backend

The Rust Cranelift backend (`src/lib.rs`, `src/ffi.rs`) stays as Rust.
It's the runtime — the thing that turns `Back.Cmd` values into machine code.
The MOM compiler produces `Back.Cmd` values; the Rust backend executes them.

---

## 12. The Bootstrap Loop

```
1. Schema in Moonlift          ✅ (seed done)
2. Native parser layer         🔜 Phase 1
3. Dispatch funcs              🔜 Phase 2
4. Command-producing funcs     🔜 Phase 3
5. Expression lowering regions 🔜 Phase 4
6. Statement lowering regions  🔜 Phase 5
7. Analysis + validation       🔜 Phase 6-7
8. Vectorization pipeline      🔜 Phase 8
9. Link/JIT/object driver      🔜 Phase 9
10. String -> native execution 🎯 The milestone
11. Lua layer shrinks to shell 🏁 Pure Moonlift compiler core
```

At step 10, a source string can be scanned, parsed, typechecked, lowered,
validated, and executed/emitted through the backend by native Moonlift compiler
code. At step 11, Lua is only the staging shell used to generate/specialize MOM
itself; the compiler core runtime is pure native code.

Every function follows the same pattern:

```
Read source bytes or ASDL input
  → scan/lex/parse to typed MoonTree ASDL
  → switch on variant/token tags with Moonlift switch
  → compute compiler output (select for compiler data, if/jump for compiler control)
  → emit target-program ASDL output (Back.Cmd, ControlFact, diagnostics, etc.)
```

The parser layer is the front door: source bytes become typed AST, not Lua
objects. `select` is still a keystone for compiler data choice, and `CmdSelect`
is the target-program data-choice output.
`moon.stmts [[ ]]` + `@{...}` is the staging backbone — it generates
source-shaped Moonlift with computed holes, producing pure Moonlift.
Regions are the composition mechanism — every phase that walks, accumulates,
or dispatches becomes a Moonlift region with typed block params and
continuation protocols.

No Lua in the compiler core runtime. Pure Moonlift. Native code.
