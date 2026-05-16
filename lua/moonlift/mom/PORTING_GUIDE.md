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

The schema files (`lua/moonlift/mom/schema/`) are the seed — ASDL types as
Moonlift struct/union declarations. The parser contract is explicit:
`ptr(u8)+len` source bytes become typed MoonTree AST values before semantic
phases run.

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

All Moonlift input is `.mlua`. MOM scans Lua-opaque regions enough to find
Moonlift islands and typed splice holes. Lua staging resolves splice values
before the closed native compiler core runs. The Moonlift island parser is
independent of Lua by design.

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

MOM uses SoA storage for scanner writes and parser-facing accessors that expose
`Token` values/views. All token spans are retained so AST nodes, anchors, and
errors can point back to source without string side tables.

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
4. **Separate semantic AST from concrete/editor data.** The compiler consumes
   MoonTree. Editor recovery consumes TokenTape/AnchorSpan plus a shallow CST
   product when exact malformed trivia is required.
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

MOM needs a real `MoonParse` model: `SourceBuffer`, `TokenKind`, `Token`,
`TokenTape`, `Island`, `ParseCursor`, `ParseIssue`, `SpliceSlot`, and
builder/freeze result types. A `ParseIssue`-only model is not a parser model.

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
target-program control. The canonical spelling for union-valued command
construction is compiler `if`/`switch`; `select` is reserved for scalar compiler
values.

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

**Lua (current):** the current lowerer reports that if-expression lowering is
not implemented. That is an implementation gap, not a MOM design choice.

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
compiled user program makes at its runtime.

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

`lua/moonlift/mom/schema/` — all ASDL types as Moonlift struct/union.

### Phase 1: Native Parser Layer

Source bytes → token tape → MoonTree AST.

- `scan_document(src) -> DocumentParts` for `.mlua`/island segmentation
- `lex_island(source, range) -> TokenTape`
- `parse_type`, `parse_expr`, `parse_stmt`, `parse_func`, `parse_region_frag`
- `parse_module(source) -> Module + ParseIssue + AnchorSet`
- token/splice/name interning and arena-backed list builders

This layer is the front door. Lowerings consume real native ASDL values from
this boundary; they do not consume Lua materialized ASTs.

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
union command, use compiler `if`/`switch`.

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

---

## 13. Lowering Audit: What the Lua Pipeline Actually Does

This section is the implementation checklist for porting the current Lua
lowerers into clean, idiomatic native Moonlift/MOM.  The rule is: port the
*compiler meaning*, not the Lua/PVM mechanics.

### 13.1 Current Lowering Stack

| Lua module | Role today | MOM port shape |
|---|---|---|
| `open_expand.lua` | Resolve open slots, splices, fragment use sites, imported names | `func`/`region` pass over parsed AST + splice environment; outputs closed AST plus typed open issues |
| `open_facts.lua`, `open_validate.lua` | Gather open-slot facts and validate fills/imports | fact extraction region + validator region over fact tape |
| `tree_typecheck.lua` | Bind/check expressions, statements, regions, functions, contracts | typed recursive-descent over AST tags; env is a typed stack/view, issues append to builder |
| `sem_layout_resolve.lua` | Resolve named/struct/union layout-dependent fields and storage | post-typecheck rewrite pass; mostly pure functions plus list-walk regions |
| `type_to_back_scalar.lua`, `type_abi_classify.lua`, `type_func_abi_plan.lua` | Type-to-back scalar and ABI classification | small `switch` funcs and ABI-plan builders |
| `tree_control_facts.lua` | Extract/decide control-region facts | region fact walker + deterministic decision function |
| `tree_control_to_back.lua` | Lower `block`/`region` source control into target `Back.Cmd` CFG | compiler regions that emit target block/cmd data |
| `tree_contract_facts.lua` | Extract vectorization/alias contract facts | fact extraction region over contract AST |
| `tree_to_back.lua` | Main MoonTree → MoonBack lowering | split into stateful expression/stmt/function/module lowerers, not one mega-file |
| `vec_loop_facts.lua` | Recognize vectorizable control regions | fact extraction + recognizer funcs over typed facts |
| `vec_loop_decide.lua` | Decide vector legality for target model | pure decision funcs over fact tape and target capabilities |
| `vec_kernel_plan.lua` | Build vector kernel plan from facts/contracts | staged planner + native plan builder funcs |
| `vec_kernel_to_back.lua`, `vec_to_back.lua` | Lower vector plans/IR to `Back.Cmd` | command-emitting regions with explicit block/value id allocators |
| `back_validate.lua` | Validate backend program invariants | one validation region over `Cmd` tape; separate symbol tables for sig/func/block/value/access scopes |
| `link_*`, `host_*_emit_plan.lua`, `back_diagnostics.lua` | Drivers/adapters/diagnostics | after core compiler: thin native adapters, not part of semantic lowering core |

The immediate MOM lowering target is the path:

```text
closed MoonTree.Module
  -> typecheck
  -> sem/layout resolve
  -> tree/control/vector lowering
  -> BackProgram
  -> back_validate
```

Open/splice expansion stays ahead of typecheck.  Link/JIT/object drivers stay
after validation.

### 13.2 Cross-Cutting Runtime Data Structures

Do not port Lua tables directly.  Use a few typed state records everywhere:

```moonlift
struct IssueBuilder
    tags: ptr(i32)
    a: ptr(i32)
    b: ptr(i32)
    count: index
    cap: index
end

struct CmdBuilder
    cmds: ptr(BackCmd)      -- typed command storage; SoA is an internal storage choice behind accessors
    count: index
    cap: index
end

struct IdAllocator
    next_value: i32
    next_block: i32
    next_access: i32
    next_slot: i32
end

struct LowerState
    cmds: ptr(CmdBuilder)
    ids: IdAllocator
    locals: LocalEnv
    ret: ReturnMode
    module_name: NameId
    current_func: NameId
end
```

Idiomatic MOM lowerers thread `LowerState` through region block parameters:

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

The target program's control flow is still `Back.Cmd` data.  MOM's own
`block`/`jump` only controls the native compiler.

### 13.3 Non-Negotiable Porting Rules Found During Audit

1. **Region ids must be globally unique within a module.**  The Lua parser used
   per-island `region_seq`; identical `block loop()` islands collided and PVM
   reused lowerings across functions.  MOM must allocate region ids from a
   module-level/id-arena allocator, never from a per-function local counter.
2. **Backend ids must be scoped by function or by allocator.**  `v1`, `v2`,
   `ctl.if.then1`, access ids, and stack slots are target-function local.  The
   allocator must reset only at `BeginFunc`, and cached/generated code must not
   smuggle ids from another function.
3. **Do not memoize lowering by structurally interned AST alone when env
   matters.**  Env-sensitive phases (`expr_to_back`, `stmt_to_back`, layout
   resolve, control lowering) are plain native functions/regions in MOM, not
   PVM cache boundaries.
4. **Facts are tapes, not implicit Lua arrays.**  Every facts phase appends
   typed fact records into a builder, then validates/decides from the tape.
5. **Unsupported cases become explicit issues or `CmdTrap`, never silent
   fallback.**  Keep the current fail-loud behavior, but make the reason a typed
   diagnostic payload.

### 13.4 Open Expansion Port

Current files: `open_expand.lua`, `open_facts.lua`, `open_validate.lua`.

Port as three native stages:

```text
Open AST + SpliceEnv
  -> OpenFact tape
  -> OpenIssue tape
  -> Closed AST
```

Implementation shape:

- `expand_type`, `expand_expr`, `expand_stmt`, `expand_item`, `expand_module`
  are `func`s switching on variant tags.
- List expansion (`expand_exprs`, `expand_stmts`, `expand_items`) is a region
  over `view(T)` with output builders.
- Slot lookup is an explicit typed map lookup (`SlotKey -> SlotValue`) in
  `SpliceEnv`, not a Lua table lookup.
- Fragment expansion (`StmtUseRegionFrag`, `ExprUseExprFrag`) should first
  produce typed slot/fill facts, then splice the resolved fragment body with a
  fresh region id and fresh local ids.

Open expansion is a required phase whenever parsed input contains slots,
fragments, imports, or staged `.mlua` holes. Closed `.mlua` modules (no
open constructs) still pass through the same phase boundary; it is an identity
transform.

### 13.5 Typecheck Port

Current file: `tree_typecheck.lua`.

Split into these MOM units:

```text
mom_type_env.mlua          -- Env, lookup, module bindings, field layouts
mom_type_expr.mlua         -- Expr -> typed Expr + Type + issues
mom_type_stmt.mlua         -- Stmt -> typed Stmt + issues + flow/yield checks
mom_type_control.mlua      -- region param bindings + control validation call
mom_type_module.mlua       -- item/function/module orchestration
```

Port pattern:

- `type_expr(expr, ctx) -> TypeExprResult`
- `type_place(place, ctx) -> TypePlaceResult`
- `type_stmt(stmt, ctx; done: cont(ctx, typed_stmt, issues, flow))`
- `type_func(func, module_env) -> TypeFuncResult`

Important Lua semantics to preserve:

- integer literal adoption to expected scalar type
- pointer/view indexing normalization
- struct/union field resolution hooks
- call target decision via `sem_call_decide.lua`
- region block param bindings use region id + label + param index
- every path in block/region must terminate with jump/yield/return
- `yield` mode differs between statement regions and expression regions

Type equality and scalar predicates are pure `func`s. Env lookup is a reverse
scan over a typed local stack; module/global lookup uses the shared symbol map
from `runtime/sets.mlua`.

### 13.6 Semantic Layout Resolve Port

Current file: `sem_layout_resolve.lua`.

This pass should stay separate from typecheck.  It rewrites typed AST nodes that
need concrete layout knowledge:

- named type refs -> layout entries
- struct/union fields -> `FieldByOffset` / resolved storage metadata
- view/domain/index/place nodes -> layout-aware forms
- globals/statics -> storage/data refs

Port as pure rewrite functions plus list-walk regions.  It should not allocate
backend `BackValId`s and should not emit `Back.Cmd`; it produces a more concrete
MoonTree/MoonSem tree for backend lowering.

### 13.7 Type/ABI Helper Port

Current files: `type_to_back_scalar.lua`, `type_abi_classify.lua`,
`type_func_abi_plan.lua`, plus helper logic duplicated in `tree_to_back.lua`.

This is a foundational module because every backend lowering uses it:

```moonlift
func scalar_to_back(s: Scalar) -> BackScalar
func type_to_back_scalar(ty: Type) -> BackScalarResult
func abi_classify(ty: Type, layouts: LayoutEnv) -> AbiClass
func func_abi_plan(name: NameId, params: view(Param), result: Type) -> FuncAbiPlan
```

These are mostly `switch` + simple layout queries.  Keep all ABI lowering in one
module so tree lowering, vector lowering, extern lowering, and host wrappers use
the same rules.

### 13.8 Main Tree-to-Back Port

Current file: `tree_to_back.lua` should not become one huge `.mlua` file.  Port
it as modules with one responsibility each:

```text
mom_back_ids.mlua          -- BackValId/BlockId/AccessId/StackSlot allocators
mom_back_env.mlua          -- Local env, stack/view/scalar locals, globals
mom_back_ops.mlua          -- unary/binary/compare/cast op selection
mom_back_address.mlua      -- view/place/index/field address lowering
mom_back_expr.mlua         -- expression lowering
mom_back_stmt.mlua         -- statement lowering
mom_back_func.mlua         -- ABI, entry params, returns, wrappers
mom_back_module.mlua       -- items, hoisting, finalize module
```

#### Expression lowering inventory

Port these as command-emitting regions/functions:

| Lua handler | MOM lowering |
|---|---|
| `ExprLit` | const/literal command or direct constant value |
| `ExprRef` | env/global lookup; scalar/view/data refs |
| `ExprUnary` | lower operand, emit unary cmd |
| `ExprBinary` | lower operands, emit int/float cmd |
| `ExprCompare` | lower operands, emit compare cmd |
| `ExprCast` | semantic/surface cast op, emit cast/copy as needed |
| `ExprSelect` | lower cond/a/b, emit `CmdSelect` |
| `ExprLogic` | lower lhs/rhs, emit bool `CmdSelect` |
| `ExprCall` | lower args, choose direct/extern/indirect target, emit call |
| `ExprLen` | view/local len lookup |
| `ExprSwitch` | emit target `CmdSwitchInt` plus arm blocks/join param |
| `ExprControl` | delegate to control-region lowerer |
| `ExprDeref`, `ExprLoad`, atomics | address lowering + load/atomic cmds |
| `ExprField`, `ExprIndex` | address lowering + load/store scalar |

Deferred Lua lowerings to explicitly decide in MOM:

- `ExprIf`: scalar/effect-free case must lower to `CmdSelect`; effectful case
  lowers with target blocks and join param.
- `ExprBlock`: lower statement prefix then final expression.
- `ExprDot`/`PlaceDot`: layout resolve converts these to field/offset forms;
  unresolved dot nodes are typed backend issues.
- aggregates/arrays/closures: require explicit runtime representation specs
  before lowering; without that spec they are typed backend issues.
- slot/fragment expressions: open expansion eliminates them before backend.

#### Statement lowering inventory

| Lua handler | MOM lowering |
|---|---|
| `StmtLet` | lower init, bind scalar/view local in env |
| `StmtVar` | create stack slot if address-taken/mutable; otherwise same as let |
| `StmtSet` | lower place address and value, emit store |
| `StmtIf` | emit target blocks, branch, join, phi-like block params |
| `StmtSwitch` | emit target switch and arm/default/join blocks |
| `StmtExpr` | lower call-as-statement specially; otherwise lower/discard value |
| `StmtReturn*` | emit return value/view ABI stores or void return |
| `StmtAtomicStore/Fence` | emit atomic store/fence cmd |
| `StmtControl` | delegate to control-region lowerer |
| `StmtJump/Yield*` outside control lowerer | backend trap/typed issue |

Use `Flow = FallsThrough | Terminates` in `LowerState` results.  Never infer
fallthrough from missing commands.

### 13.9 Control Lowering Port

Current files: `tree_control_facts.lua`, `tree_control_to_back.lua`.

Keep two phases:

1. `control_facts(region) -> ControlFact tape`
2. `lower_control_region(region, st; done)` emits target CFG

Do not merge validation and lowering.  The current Lua validates reducibility,
labels, jump args, yield modes, and terminators before emitting.  MOM should do
the same, then lower.

Lowering model:

- allocate a fresh nonce/block prefix from `LowerState.ids`
- create all target blocks and target block params up front
- lower entry initializers to target jump args
- for each control block: switch to target block, bind block params into local
  env, lower body, require termination or emit `CmdTrap`
- seal blocks and switch to exit block
- expression regions append an exit block param as the yielded value

This is where the parser collision bug matters most: region ids are semantic
identity and must be allocated by the module parser/AST builder, not inferred
from a local label alone.

### 13.10 Vectorization Port

Current files: `vec_loop_facts.lua`, `vec_loop_decide.lua`,
`vec_kernel_plan.lua`, `vec_kernel_to_back.lua`, `vec_to_back.lua`,
`vec_kernel_safety.lua`, `vec_inspect.lua`.

Dependency order:

1. **Fact extraction**: recognize counted loops, access patterns, aliases,
   reductions, terminal exits. Output `VecFact`/`VecLoopFacts` tapes.
2. **Decision**: pure legality check over facts and target model.
3. **Plan**: construct `VecKernelPlan` for map/reduce/algebraic kernels.
4. **Lower plan to Back**: emit vector blocks/cmds.

`vec_kernel_to_back` depends on facts and plans; it is not an independent entry
point. Vector lowering calls the shared ABI/type/address helpers. Vector IR
forms without a defined backend mapping (`ramp`, horizontal reduce, vector
select for unsupported shapes) produce explicit typed rejects.

### 13.11 Back Validation Port

Current file: `back_validate.lua`.

Port as two native passes over the command tape:

1. `cmd_facts(cmds) -> BackFact tape`
2. `validate_back_facts(facts, cmds) -> BackValidationIssue tape`

State required:

```moonlift
struct BackValidateState
    active_func: BackFuncId
    seen_sig: SymbolSet
    seen_func: SymbolSet
    seen_extern: SymbolSet
    seen_data: SymbolSet
    seen_block: SymbolSet        -- reset per function
    seen_value: SymbolSet        -- reset per function
    seen_slot: SymbolSet         -- reset per function
    seen_access: SymbolSet       -- reset per function
    finalized: bool
end
```

The Lua validator uses string/table sets; MOM should start with sorted symbol
tapes or open-addressed hash tables.  Keep per-function reset semantics exactly:
value/block/access uniqueness is function-local, not module-global.

Also port memory checks as small pure funcs:

- scalar/shape byte size
- alignment power-of-two and minimum-size checks
- dereference/trap/motion/mode invariants
- target-supported-shape checks

### 13.12 Lowering Milestones

Implement lowerings in this order, with tests after each milestone:

1. `mom_back_ops.mlua`: scalar/type/op/ABI helpers.
2. `mom_back_env.mlua` + id allocators.
3. `mom_back_expr.mlua`: literals, refs, unary/binary/compare/cast/select/logic.
4. `mom_back_address.mlua`: ptr/view/index/field load/store.
5. `mom_back_stmt.mlua`: let/var/set/return/if/switch/call-stmt/atomics.
6. `mom_control_facts.mlua` + `mom_control_to_back.mlua`.
7. `mom_back_func.mlua` + `mom_back_module.mlua`.
8. `mom_back_validate.mlua`.
9. Vector facts/decision/plan/lowering.
10. Link/JIT/object driver.

Each milestone must have a native test that compares MOM output to the current
Lua pipeline for the same source or validates through `back_validate` and JIT.
Tests compare the strongest available contract at that boundary: exact typed
results for pure helpers, fact/command tape shapes for lowering stages, full
`BackProgram` command tapes modulo fresh id names for complete backend paths,
and executed results for JIT-capable programs.

---

## 14. MOM Code Organization and Implementation Pattern

MOM should be organized as a native compiler, not as a mirror of the Lua module
layout.  Lua modules often combine schemas, ad-hoc tables, PVM phase boundaries,
helpers, tests, and driver code in one file.  MOM files should have one narrow
compiler responsibility and one explicit native data interface.

### 14.1 Directory Layout

Use this layout under `lua/moonlift/mom/`. This is the intended compiler source
shape; moving it under `lua/moonlift/mom/` or embedding it is a packaging
operation, not a redesign.

```text
lua/moonlift/mom/
  schema/
    MoonCore.mlua          -- scalar/op/name/id data
    MoonType.mlua          -- types and ABI helper data
    MoonBind.mlua          -- bindings/env-visible symbols
    MoonSem.mlua           -- typed semantic decisions
    MoonTree.mlua          -- AST/control/typing/lowering result data
    MoonBack.mlua          -- backend command/fact/validation data
    MoonParse.mlua         -- source/token/parser data
    MoonVec.mlua           -- vector facts/plans

  runtime/
    arena.mlua             -- bump arena, typed array/view builders
    strings.mlua           -- interned names/slices/ids
    sets.mlua              -- small symbol sets / open-addressed maps
    diag.mlua              -- issue builders and source spans

  parser/
    native_lexer.mlua      -- token tape scanner over ptr(u8)+len
    native_core.mlua       -- native AST tape parser core
    source_scan.mlua       -- .mlua document island scanner
    parse_cursor.mlua      -- cursor helpers, expect/accept/recover
    parse_type.mlua
    parse_expr.mlua
    parse_stmt.mlua
    parse_item.mlua
    parse_module.mlua
    parse_splice.mlua

  open/
    open_facts.mlua
    open_validate.mlua
    open_expand.mlua

  typecheck/
    type_env.mlua
    type_scalar.mlua
    type_expr.mlua
    type_place.mlua
    type_stmt.mlua
    type_control.mlua
    type_func.mlua
    type_module.mlua

  layout/
    layout_env.mlua
    layout_type.mlua
    layout_field.mlua
    layout_resolve.mlua

  back/
    back_ids.mlua
    back_env.mlua
    back_ops.mlua
    back_abi.mlua
    back_memory.mlua
    back_address.mlua
    back_expr.mlua
    back_stmt.mlua
    back_control_facts.mlua
    back_control_lower.mlua
    back_func.mlua
    back_module.mlua
    back_validate_facts.mlua
    back_validate.mlua

  vec/
    vec_facts.mlua
    vec_decide.mlua
    vec_plan.mlua
    vec_lower.mlua
    vec_validate.mlua

  driver/
    compile_module.mlua    -- source/module -> BackProgram
    jit_driver.mlua        -- validated BackProgram -> backend FFI
    object_driver.mlua
    diagnostics.mlua

  tests/
    test_parser_*.lua
    test_type_*.lua
    test_back_*.lua
    test_vec_*.lua
```

Verification harnesses such as `parser/native_ast.lua` belong outside the native
compiler dependency graph, e.g. `parser/verify/`. They may compare native output
against the Lua pipeline, but compiler modules must not import them.

### 14.2 Module Boundary Rule

Every `.mlua` compiler module should export one of these shapes:

1. **Data schema module** — only `struct`, `union`, constants, no phase logic.
2. **Pure helper module** — `func`s only, no builders except returned values.
3. **Builder/runtime module** — typed mutable buffers, append/freeze helpers.
4. **Compiler phase module** — public entry function/region plus private helpers.
5. **Driver module** — connects phases and backend FFI, no semantic decisions.

Do not mix parser, typecheck, lowering, validation, and driver concerns in a
single file.  If a function needs both type and backend knowledge, it belongs in
an adapter module (`back_abi`, `back_address`), not in general typecheck.

### 14.3 File Template

Use the same file shape everywhere:

```lua
-- mom/back/back_ops.mlua
-- Pure backend op selection helpers. No builders, no env mutation.

local M = moon.module("mom_back_ops")

local BackIntAdd = 1
local BackFloatAdd = 1
-- constants generated/staged from schema tags

local is_float_scalar = func(s: i32) -> bool
    return s == @{BACK_F32} or s == @{BACK_F64}
end

local lower_binary_op = func(op: i32, scalar: i32) -> i32
    let is_float: bool = is_float_scalar(scalar)
    switch op do
    case @{BIN_ADD} then return select(is_float, @{FLOAT_ADD}, @{INT_ADD})
    case @{BIN_SUB} then return select(is_float, @{FLOAT_SUB}, @{INT_SUB})
    default then return 0
    end
end

M:add_func(is_float_scalar)
M:add_func(lower_binary_op)
return M
```

Rules:

- Constants at top, generated by Lua staging from schema where possible.
- Private helpers first, public entry points last.
- `M:add_func(...)` order follows dependency order.
- No hidden side tables.  If state is needed, pass a pointer/state struct.
- No stringly dispatch in runtime code; use enum/tag integers or interned ids.

### 14.4 Naming Convention

Use stable prefixes by layer:

| Layer | Prefix | Example |
|---|---|---|
| parser | `mp_` | `mp_parse_expr`, `mp_accept` |
| open | `mo_` | `mo_expand_stmt` |
| typecheck | `mt_` | `mt_type_expr` |
| layout | `ml_` | `ml_resolve_field` |
| backend lowering | `mb_` | `mb_lower_expr` |
| control lowering | `mc_` | `mc_lower_region` |
| vector | `mv_` | `mv_plan_kernel` |
| validation | `mvb_` or `mbv_` | `mbv_validate_cmds` |
| runtime/util | `mr_` | `mr_push_issue` |

Avoid generic exported names like `parse`, `lower`, `loop`, `env`, `state`.
The recent region-id collision showed why stable, scoped identity matters.
Generic names are fine only for local block labels inside a single function, and
module-level region ids must still come from an allocator.

### 14.5 Data Ownership Pattern

MOM has three lifetimes:

1. **Source lifetime** — source bytes and token spans; never copied unless
   interned as a name/literal.
2. **Compiler arena lifetime** — AST, typed AST, facts, plans, diagnostics;
   lives for one compilation/session.
3. **Backend program lifetime** — `BackProgram` command/data tapes passed to
   validation and backend FFI.

Pattern:

```moonlift
func phase(input: InputView, arena: ptr(Arena), issues: ptr(IssueBuilder)) -> OutputView
```

or for stateful output:

```moonlift
region phase(input: InputView, st: PhaseState;
             done: cont(st: PhaseState, out: OutputView))
```

No phase should allocate with libc directly except arena/runtime modules.  Phase
code appends through builders and freezes views.

### 14.6 Builder Pattern

Every variable-length output uses the same append/freeze interface:

```moonlift
struct BuilderI32
    data: ptr(i32)
    len: index
    cap: index
end

func push_i32(b: ptr(BuilderI32), value: i32) -> index
    let i: index = b.len
    if i < b.cap then b.data[i] = value end
    b.len = i + 1
    return i
end
```

For hot parser/lowering builders, SoA tapes are a valid native representation
when paired with typed accessors and a documented schema:

```moonlift
expr_tag[i], expr_a[i], expr_b[i], expr_c[i]
```

The design choice is explicit: either a phase consumes the typed SoA accessor
API, or it consumes arena-owned union values. It never consumes Lua
materializers.

### 14.7 Dispatch Pattern

Port every PVM dispatch table to a `switch`:

```moonlift
func mb_lower_expr_tag(tag: i32, expr_id: i32, st: ptr(LowerState)) -> i32
    switch tag do
    case @{EXPR_LIT} then return mb_lower_lit(expr_id, st)
    case @{EXPR_REF} then return mb_lower_ref(expr_id, st)
    case @{EXPR_BINARY} then return mb_lower_binary(expr_id, st)
    default then
        mr_issue(st.issues, @{ISSUE_UNSUPPORTED_EXPR}, expr_id)
        return 0
    end
end
```

Use `select` only for scalar compiler values.  If each arm performs different
work or constructs different union variants, use `switch`/`if`.

### 14.8 Region Pattern for Walkers

Use regions for loops that thread compiler state:

```moonlift
region mb_lower_expr_list(xs: view(Expr), st: LowerState;
                          done: cont(st: LowerState, values: view(BackValId)))
entry loop(i: index = 0, st0: LowerState = st, vals: ValBuilder = empty_vals())
    if i >= len(xs) then jump done(st = st0, values = freeze_vals(vals)) end
    let r: LowerExprResult = mb_lower_expr(xs[i], st0)
    let vals2: ValBuilder = push_val(vals, r.value)
    jump loop(i = i + 1, st0 = r.st, vals = vals2)
end
end
```

This replaces Lua `for` + `append_all`.  Region block params are the visible,
typed form of env threading.

### 14.9 Error/Issue Pattern

Every phase has a typed issue enum.  Do not return strings from native compiler
logic except as interned/source-slice ids.

```moonlift
func issue_type_mismatch(issues: ptr(IssueBuilder), site: NodeId,
                         expected: TypeId, actual: TypeId)
    push_issue4(issues, @{ISSUE_TYPE_MISMATCH}, site, expected, actual, 0)
end
```

When a phase can recover, append an issue and produce an error node/result.  When
backend lowering cannot recover, emit `CmdTrap` plus an issue if one is in scope.
Validation should report all issues it can find in one pass.

### 14.10 Testing Organization

Each module gets tests at the same layer:

```text
tests/mom_parser_*       -- token/AST tape/parser behavior
tests/mom_type_*         -- typecheck results and issue tags
tests/mom_back_ops_*     -- pure op mapping
tests/mom_back_expr_*    -- expression lowering command tags
tests/mom_back_stmt_*    -- CFG command shape
tests/mom_control_*      -- facts + lowering
tests/mom_validate_*     -- validator issues
tests/mom_pipeline_*     -- source -> JIT behavior
```

Test progression for each new native phase:

1. Compile the `.mlua` module.
2. Unit-test pure functions directly through FFI.
3. Feed small typed tapes/AST fixtures.
4. Compare command/fact tags to the Lua pipeline.
5. Run `back_validate`.
6. JIT and execute if the phase reaches `BackProgram`.

Do not wait for the full compiler to test a module. Every helper module is
callable independently from a small harness that loads the native artifact and
exercises its exported functions.
